//! Breakout rooms, as Teams' organizers manage them (captured from Teams
//! desktop 2026-11-11, and its middle-tier adapter): every call goes to
//! `{mt}/beta/breakoutRoom/...` with the main meeting's coordinates in the
//! path, `{tenant}/{organizer}/{thread}/{message}` (the thread with its
//! `:` as `_`, `19_meeting_…`). Changes carry `?newVersion=<our
//! participant id in the call>_<new uuid>`; the meeting then sends its
//! new state to everyone in it (`breakoutDetails` on the call), which is
//! what Teams waits for.
//!
//! - create: `POST breakoutRoom/{main}` `{breakoutRoomConfigurations:
//!   {roomCount}, preconfiguration:[{name, participants}], settings}` →
//!   `{breakoutMeetings:[room]}`
//! - list: `GET breakoutRoom/bulk/{main}` → `{breakoutRoomMeetings:[room]}`
//! - assign: `PUT breakoutRoom/bulk/v2/{main}` `{totalParticipantCount,
//!   breakoutRooms:[{coordinates, roomName, participants, settings:
//!   {restrictChatAccess}}]}` → `{breakoutRooms:[room]}`
//! - open / close: `POST breakoutRoom/open|close/{main}` `{rooms:
//!   [{coordinates}], useNewTimerFlow, totalParticipantCount}`
//! - settings: `GET`/`PUT breakoutRoom/settings/{main}`
//!   `{allowUsersToSelectBreakoutRoom, roomDuration, managers,
//!   extensionData:{allowJoinBackToMainMeeting:"true",
//!   allowMoveParticipantsAutomatically:"true"}}`
//! - add a room: `POST breakoutRoom/add/{main}` `{name, participants}`
//! - rename / reassign one: `PUT breakoutRoom/{room}` `{name,
//!   participants, restrictChatAccess}`
//! - delete one: `DELETE breakoutRoom/{room}`; all: `DELETE
//!   breakoutRoom/rooms/all/{main}` with `[{meetingJoinUrl,
//!   meetingUpdateUrl}]`
//! - announce: `POST breakoutRoom/announce/{main}` `{roomThreadIds,
//!   message}`
//!
//! A room is open when it has people and its chat isn't restricted
//! (Teams' own test: `participants.length > 0 && !restrictChatAccess`).

use anyhow::{Context, Result, bail};
use serde::Serialize;
use serde_json::{Value, json};

use super::client::TeamsClient;

/// A meeting's (or a room's) coordinates.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Coords {
    pub tenant: String,
    pub organizer: String,
    /// `19:meeting_…@thread.v2`.
    pub thread: String,
    pub message: String,
}

impl Coords {
    pub fn new(tenant: &str, organizer: &str, thread: &str, message: &str) -> Result<Self> {
        let thread = thread.replacen("19_", "19:", 1);
        super::meeting_options::check_ids(tenant, organizer, &thread, message)?;
        Ok(Self {
            tenant: tenant.to_string(),
            organizer: organizer.to_string(),
            thread,
            message: message.to_string(),
        })
    }

    /// The path form: `tenant/organizer/19_meeting_…/message`.
    pub fn path(&self) -> String {
        format!("{}/{}/{}/{}", self.tenant, self.organizer, self.thread.replace(':', "_"), self.message)
    }

    /// The body form Teams sends (the thread underscored, as in the path).
    pub fn json(&self) -> Value {
        json!({
            "tenantId": self.tenant,
            "organizerId": self.organizer,
            "threadId": self.thread.replace(':', "_"),
            "messageId": self.message,
        })
    }
}

/// A breakout room.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Room {
    pub name: String,
    pub coords: Coords,
    pub join_url: String,
    pub update_url: String,
    /// As the service has them: `{mri, objectId, tenantId, role, …}`.
    pub participants: Vec<Value>,
    pub restrict_chat: bool,
    pub open: bool,
}

/// The rooms in a reply (`breakoutMeetings`, `breakoutRoomMeetings` or
/// `breakoutRooms`), each with the reply's tenant and organizer when its
/// own are missing.
pub fn rooms_from(v: &Value) -> Vec<Room> {
    let list = ["breakoutMeetings", "breakoutRoomMeetings", "breakoutRooms"]
        .iter()
        .find_map(|k| v.get(*k).and_then(|l| l.as_array()));
    let s = |o: &Value, k: &str| o.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    list.into_iter()
        .flatten()
        .filter_map(|r| {
            let tenant = Some(s(r, "tenantId")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(v, "tenantId"));
            let organizer = Some(s(r, "organizerId")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(v, "organizerId"));
            let message = Some(s(r, "messageId")).filter(|t| !t.is_empty()).unwrap_or_else(|| "0".into());
            let coords = Coords::new(&tenant, &organizer, &s(r, "threadId"), &message).ok()?;
            let participants = r.get("participants").and_then(|p| p.as_array()).cloned().unwrap_or_default();
            let restrict_chat = r.get("restrictChatAccess").and_then(|x| x.as_bool()).unwrap_or(false);
            Some(Room {
                name: s(r, "roomName"),
                open: !participants.is_empty() && !restrict_chat,
                coords,
                join_url: s(r, "meetingJoinUrl"),
                update_url: s(r, "meetingUpdateUrl"),
                participants,
                restrict_chat,
            })
        })
        .collect()
}

/// The rooms' settings (Teams' Room settings pane).
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Settings {
    pub allow_select: bool,
    /// Minutes (Teams' "Set a time limit"); none for no limit.
    pub room_duration: Option<i64>,
    pub allow_return: Option<bool>,
    pub auto_move: Option<bool>,
    /// Breakout rooms managers (Teams' "Assign presenters to manage
    /// rooms"): `[{upn, mri, objectId, role}]`.
    pub managers: Option<Value>,
}

impl Settings {
    pub fn from_reply(v: &Value) -> Self {
        let flag = |k: &str| {
            v.pointer(&format!("/extensionData/{k}"))
                .and_then(|x| x.as_str())
                .map(|s| s.eq_ignore_ascii_case("true"))
        };
        Self {
            allow_select: v["allowUsersToSelectBreakoutRoom"].as_bool().unwrap_or(false),
            room_duration: duration_minutes(&v["roomDuration"]),
            allow_return: flag("allowJoinBackToMainMeeting"),
            auto_move: flag("allowMoveParticipantsAutomatically"),
            managers: v.get("managers").filter(|m| !m.is_null()).cloned(),
        }
    }

    /// From OST's own JSON (the field names this struct serializes to).
    pub fn from_args(v: &Value) -> Self {
        Self {
            allow_select: v["allow_select"].as_bool().unwrap_or(false),
            room_duration: v["room_duration"].as_i64().filter(|d| *d > 0),
            allow_return: v["allow_return"].as_bool(),
            auto_move: v["auto_move"].as_bool(),
            managers: v.get("managers").filter(|m| !m.is_null()).cloned(),
        }
    }

    /// The body Teams sends.
    pub fn body(&self) -> Value {
        let mut ext = serde_json::Map::new();
        if let Some(b) = self.allow_return {
            ext.insert("allowJoinBackToMainMeeting".into(), json!(b.to_string()));
        }
        if let Some(b) = self.auto_move {
            ext.insert("allowMoveParticipantsAutomatically".into(), json!(b.to_string()));
        }
        let mut body = json!({ "allowUsersToSelectBreakoutRoom": self.allow_select, "extensionData": ext });
        if let Some(d) = self.room_duration {
            // Teams sends the limit as "HH:MM:00".
            body["roomDuration"] = json!(format!("{:02}:{:02}:00", d / 60, d % 60));
        }
        if let Some(m) = &self.managers {
            body["managers"] = m.clone();
        }
        body
    }
}

/// A room time limit in minutes from Teams' "HH:MM:SS" (or a number).
fn duration_minutes(v: &Value) -> Option<i64> {
    if let Some(n) = v.as_i64() {
        return (n > 0).then_some(n);
    }
    let mut parts = v.as_str()?.split(':').map(|p| p.trim().parse::<i64>().ok());
    let (h, m) = (parts.next()??, parts.next().flatten().unwrap_or(0));
    let total = h * 60 + m;
    (total > 0).then_some(total)
}

/// A change's version: our participant id in the call, then a new id.
pub fn new_version(participant_id: &str) -> String {
    let me = if participant_id.is_empty() { uuid::Uuid::new_v4().to_string() } else { participant_id.to_string() };
    format!("{me}_{}", uuid::Uuid::new_v4())
}

fn versioned(path: String, version: &str) -> String {
    if version.is_empty() { path } else { format!("{path}?newVersion={version}") }
}

async fn send(client: &TeamsClient, method: reqwest::Method, path: &str, body: Option<Value>, what: &str) -> Result<Value> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let mut req = client.http().request(method, format!("{base}/beta/breakoutRoom/{path}")).bearer_auth(&token);
    if let Some(b) = body {
        req = req.json(&b);
    }
    let resp = req.send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("{what}: HTTP {status} {}", text.chars().take(200).collect::<String>());
    }
    Ok(serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// A room to create: its name and who's in it.
pub struct NewRoom {
    pub name: String,
    pub participants: Vec<Value>,
}

/// Create rooms (Teams' Create rooms): `rooms` names them (Teams' "Room
/// 1", "Room 2", …) and holds who's assigned (manual assignment leaves
/// them empty).
pub async fn create(client: &TeamsClient, main: &Coords, rooms: &[NewRoom], settings: Option<&Settings>, version: &str) -> Result<Vec<Room>> {
    let mut body = json!({
        "breakoutRoomConfigurations": { "roomCount": rooms.len() },
        "preconfiguration": rooms.iter().map(|r| json!({ "participants": r.participants, "name": r.name })).collect::<Vec<_>>(),
    });
    if let Some(s) = settings {
        body["settings"] = s.body();
    }
    let v = send(client, reqwest::Method::POST, &versioned(main.path(), version), Some(body), "Create breakout rooms").await?;
    Ok(rooms_from(&v))
}

/// The meeting's rooms.
pub async fn list(client: &TeamsClient, main: &Coords) -> Result<Vec<Room>> {
    let v = send(client, reqwest::Method::GET, &format!("bulk/{}", main.path()), None, "Breakout rooms").await?;
    Ok(rooms_from(&v))
}

/// Assign people to rooms (Teams' Assign participants): the rooms whose
/// people changed, each with everyone in it now (`{upn, mri}`).
pub async fn assign(client: &TeamsClient, main: &Coords, rooms: &[Room], total_participants: usize, version: &str) -> Result<Vec<Room>> {
    let body = json!({
        "totalParticipantCount": total_participants,
        // As Teams' Assign dialog saves: only the rooms whose people
        // changed, without their names or settings.
        "breakoutRooms": rooms.iter().map(|r| json!({
            "coordinates": r.coords.json(),
            "participants": r.participants,
            "settings": {},
        })).collect::<Vec<_>>(),
    });
    let v = send(client, reqwest::Method::PUT, &versioned(format!("bulk/v2/{}", main.path()), version), Some(body), "Assign participants").await?;
    Ok(rooms_from(&v))
}

/// Open rooms (Teams' Open rooms, or Open on one room).
pub async fn open(client: &TeamsClient, main: &Coords, rooms: &[Coords], total_participants: usize, version: &str) -> Result<()> {
    let body = json!({
        "rooms": rooms.iter().map(|c| json!({ "coordinates": c.json() })).collect::<Vec<_>>(),
        "useNewTimerFlow": true,
        "totalParticipantCount": total_participants,
    });
    send(client, reqwest::Method::POST, &versioned(format!("open/{}", main.path()), version), Some(body), "Open rooms").await?;
    Ok(())
}

/// Close rooms (Teams' Close rooms, or Close on one room): the people in
/// them go back to the main meeting.
pub async fn close(client: &TeamsClient, main: &Coords, rooms: &[Coords], total_participants: usize, version: &str) -> Result<()> {
    let body = json!({
        "rooms": rooms.iter().map(|c| json!({ "coordinates": c.json() })).collect::<Vec<_>>(),
        "totalParticipantCount": total_participants,
    });
    send(client, reqwest::Method::POST, &versioned(format!("close/{}", main.path()), version), Some(body), "Close rooms").await?;
    Ok(())
}

/// The rooms' settings.
pub async fn settings(client: &TeamsClient, main: &Coords) -> Result<Settings> {
    let v = send(client, reqwest::Method::GET, &format!("settings/{}", main.path()), None, "Room settings").await?;
    Ok(Settings::from_reply(&v))
}

/// Change the rooms' settings.
pub async fn set_settings(client: &TeamsClient, main: &Coords, settings: &Settings, version: &str) -> Result<Settings> {
    let v = send(client, reqwest::Method::PUT, &versioned(format!("settings/{}", main.path()), version), Some(settings.body()), "Room settings").await?;
    Ok(if v.is_null() { settings.clone() } else { Settings::from_reply(&v) })
}

/// Add a room (Teams' Add room).
pub async fn add_room(client: &TeamsClient, main: &Coords, name: &str, participants: &[Value], version: &str) -> Result<()> {
    send(client, reqwest::Method::POST, &versioned(format!("add/{}", main.path()), version), Some(json!({ "name": name, "participants": participants })), "Add room").await?;
    Ok(())
}

/// Rename a room, or change who's in it.
pub async fn update_room(client: &TeamsClient, room: &Room, version: &str) -> Result<()> {
    let body = json!({ "name": room.name, "participants": room.participants, "restrictChatAccess": room.restrict_chat });
    send(client, reqwest::Method::PUT, &versioned(room.coords.path(), version), Some(body), "Update room").await?;
    Ok(())
}

/// Delete a room (Teams' Delete room).
pub async fn delete_room(client: &TeamsClient, room: &Coords, version: &str) -> Result<()> {
    send(client, reqwest::Method::DELETE, &versioned(room.path(), version), None, "Delete room").await?;
    Ok(())
}

/// Delete every room (Teams' Delete rooms).
pub async fn delete_all(client: &TeamsClient, main: &Coords, rooms: &[Room], version: &str) -> Result<()> {
    let refs: Vec<Value> = rooms
        .iter()
        .filter(|r| !r.join_url.is_empty() && !r.update_url.is_empty())
        .map(|r| json!({ "meetingJoinUrl": r.join_url, "meetingUpdateUrl": r.update_url }))
        .collect();
    send(client, reqwest::Method::DELETE, &versioned(format!("rooms/all/{}", main.path()), version), Some(json!(refs)), "Delete rooms").await?;
    Ok(())
}

/// Post an announcement to the rooms' chats (Teams' Make an announcement).
pub async fn announce(client: &TeamsClient, main: &Coords, room_threads: &[String], message: &str) -> Result<()> {
    if message.trim().is_empty() {
        bail!("Nothing to announce");
    }
    send(client, reqwest::Method::POST, &format!("announce/{}", main.path()), Some(json!({ "roomThreadIds": room_threads, "message": message })), "Announcement")
        .await
        .context("Announcement")?;
    Ok(())
}

/// Teams' CSV import template: one row per person, the room's name then
/// their email (`Breakout Room Name,Participant Email`).
pub const CSV_TEMPLATE: &str = "Breakout Room Name,Participant Email\n";
pub const CSV_TEMPLATE_NAME: &str = "Breakout room bulk import template.csv";
/// Teams' limits: 2 MB files, 100 rooms, 1000 people, names and emails up
/// to 256 characters.
const CSV_MAX_BYTES: usize = 2 * 1024 * 1024;
const CSV_MAX_ROOMS: usize = 100;
const CSV_MAX_PEOPLE: usize = 1000;
const CSV_MAX_FIELD: usize = 256;

/// What a CSV import found: the rooms in file order with their people's
/// emails, and Teams' warnings (`MALFORMED_ENTRIES`,
/// `USER_ASSIGNED_MULTIPLE_ROOMS`, `LIMIT_EXCEEDED`).
#[derive(Debug, Default, PartialEq)]
pub struct CsvImport {
    pub rooms: Vec<(String, Vec<String>)>,
    pub warnings: Vec<&'static str>,
}

fn csv_fields(line: &str) -> Vec<String> {
    let (mut out, mut cur, mut quoted) = (Vec::new(), String::new(), false);
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' if quoted && chars.peek() == Some(&'"') => {
                cur.push('"');
                chars.next();
            }
            '"' => quoted = !quoted,
            ',' if !quoted => out.push(std::mem::take(&mut cur)),
            _ => cur.push(c),
        }
    }
    out.push(cur);
    out.into_iter().map(|f| f.trim().to_string()).collect()
}

/// Read a breakout rooms CSV as Teams does: the template's header row is
/// skipped, a person listed twice keeps their last room.
pub fn parse_csv(text: &str) -> Result<CsvImport> {
    if text.len() > CSV_MAX_BYTES {
        bail!("We couldn't import this file. The file type, size, or content isn't supported. Please update the file and try again.");
    }
    let mut import = CsvImport::default();
    let mut room_of: Vec<(String, String)> = Vec::new();
    fn warn(w: &'static str, import: &mut CsvImport) {
        if !import.warnings.contains(&w) {
            import.warnings.push(w);
        }
    }
    for (i, line) in text.trim_start_matches('\u{feff}').lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let f = csv_fields(line);
        if i == 0 && f.first().is_some_and(|h| h.eq_ignore_ascii_case("Breakout Room Name")) {
            continue;
        }
        let (room, email) = match f.as_slice() {
            [room, email, ..] => (room.clone(), email.to_lowercase()),
            _ => {
                warn("MALFORMED_ENTRIES", &mut import);
                continue;
            }
        };
        if room.is_empty() || room.chars().count() > CSV_MAX_FIELD || email.len() > CSV_MAX_FIELD || !email.contains('@') {
            warn("MALFORMED_ENTRIES", &mut import);
            continue;
        }
        if let Some(k) = room_of.iter().position(|(e, _)| *e == email) {
            warn("USER_ASSIGNED_MULTIPLE_ROOMS", &mut import);
            room_of.remove(k);
        }
        room_of.push((email, room));
    }
    for (email, room) in room_of {
        match import.rooms.iter().position(|(r, _)| *r == room) {
            Some(k) => import.rooms[k].1.push(email),
            None if import.rooms.len() < CSV_MAX_ROOMS => import.rooms.push((room, vec![email])),
            None => warn("LIMIT_EXCEEDED", &mut import),
        }
    }
    let mut count = 0;
    let mut cut = false;
    for (_, people) in import.rooms.iter_mut() {
        let keep = CSV_MAX_PEOPLE.saturating_sub(count).min(people.len());
        cut |= keep < people.len();
        people.truncate(keep);
        count += keep;
    }
    if cut {
        warn("LIMIT_EXCEEDED", &mut import);
    }
    if import.rooms.is_empty() {
        bail!("We couldn't import this file. The file type, size, or content isn't supported. Please update the file and try again.");
    }
    Ok(import)
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: &str = "2716d134-5614-4856-a48d-2002edd9a570";
    const O: &str = "4287e791-1b98-4963-8b94-281c50472683";

    #[test]
    fn coordinates_go_in_the_path_as_teams_sends_them() {
        let main = Coords::new(T, O, "19:meeting_YTQy@thread.v2", "0").unwrap();
        assert_eq!(main.path(), format!("{T}/{O}/19_meeting_YTQy@thread.v2/0"));
        assert_eq!(main.json()["threadId"], "19_meeting_YTQy@thread.v2");
        // The service's underscored ids read back as threads.
        assert_eq!(Coords::new(T, O, "19_meeting_YTQy@thread.v2", "0").unwrap(), main);
        assert!(Coords::new(T, O, "19:meeting_x@thread.v2/../x", "0").is_err());
        assert!(new_version("p1").starts_with("p1_"));
    }

    #[test]
    fn rooms_are_read_from_the_create_reply() {
        // Teams desktop creating one room for OST Test 2 (2026-11-11).
        let reply: Value = serde_json::from_str(r#"{"tenantId":"2716d134-5614-4856-a48d-2002edd9a570","organizerId":"4287e791-1b98-4963-8b94-281c50472683","breakoutMeetings":[{"detailsAvailable":true,"roomName":"Room 1","participants":[{"mri":"8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5","objectId":"9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5","tenantId":"2716d134-5614-4856-a48d-2002edd9a570","role":"Admin"}],"restrictChatAccess":true,"tenantId":"2716d134-5614-4856-a48d-2002edd9a570","organizerId":"4287e791-1b98-4963-8b94-281c50472683","threadId":"19_meeting_MmRh@thread.v2","messageId":"0","meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_MmRh%40thread.v2/0","meetingUpdateUrl":"https://api.scheduler.teams.microsoft.com/teams/x"}]}"#).unwrap();
        let rooms = rooms_from(&reply);
        assert_eq!(rooms.len(), 1);
        assert_eq!(rooms[0].name, "Room 1");
        assert_eq!(rooms[0].coords.thread, "19:meeting_MmRh@thread.v2");
        assert_eq!(rooms[0].participants.len(), 1);
        // Created rooms are closed: their chat is restricted.
        assert!(!rooms[0].open);
    }

    #[test]
    fn a_csv_is_read_as_teams_reads_it() {
        let csv = "Breakout Room Name,Participant Email\nRoom A,ost-test2@scnetsolutions.com\n\"Room, B\",a@x.com\nRoom A,A@X.com\nbad line\n";
        let import = parse_csv(csv).unwrap();
        // a@x.com was listed twice: the last room wins.
        assert_eq!(import.rooms, vec![("Room A".to_string(), vec!["ost-test2@scnetsolutions.com".to_string(), "a@x.com".to_string()])]);
        assert_eq!(import.warnings, vec!["USER_ASSIGNED_MULTIPLE_ROOMS", "MALFORMED_ENTRIES"]);
        assert!(parse_csv(CSV_TEMPLATE).is_err());
    }

    #[test]
    fn settings_round_trip() {
        let s = Settings::from_reply(&json!({"extensionData":{"allowJoinBackToMainMeeting":"false"},"allowUsersToSelectBreakoutRoom":false}));
        assert_eq!(s.allow_return, Some(false));
        assert_eq!(s.auto_move, None);
        assert_eq!(s.body(), json!({"allowUsersToSelectBreakoutRoom":false,"extensionData":{"allowJoinBackToMainMeeting":"false"}}));
        // A time limit goes as Teams writes it.
        let limited = Settings { room_duration: Some(90), ..Settings::default() };
        assert_eq!(limited.body()["roomDuration"], "01:30:00");
        assert_eq!(Settings::from_reply(&limited.body()).room_duration, Some(90));
        assert_eq!(Settings::from_reply(&json!({"roomDuration":"00:00:00"})).room_duration, None);
    }
}
