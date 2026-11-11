//! Breakout rooms as a meeting's participant sees them (captured from a
//! meeting Teams desktop organized, 2026-11-11): when the organizer
//! creates, opens or closes rooms, each participant's call gets a
//! `conversation/localParticipantUpdate` with
//! `breakoutDetails.mainMeetingProperties.assignedBreakoutRooms`: the
//! rooms they're in, each `{name, isOpen, meetingJoinUrl,
//! allowMoveParticipantsAutomatically, moveJitter}`. A room is a meeting
//! of its own; Teams moves people into it (after `moveJitter` ms) when it
//! opens and back to the main meeting when it closes.

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AssignedRoom {
    pub name: String,
    pub open: bool,
    pub join_url: String,
    pub auto_move: bool,
    pub move_jitter_ms: u64,
}

/// The rooms a call event assigns us, if it is a breakout update.
pub fn assigned_rooms(json: &str) -> Option<Vec<AssignedRoom>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let rooms = v.pointer("/body/breakoutDetails/mainMeetingProperties")?.get("assignedBreakoutRooms");
    let rooms = match rooms {
        Some(r) => r.as_array()?.clone(),
        None => Vec::new(),
    };
    Some(
        rooms
            .iter()
            .filter_map(|r| {
                Some(AssignedRoom {
                    name: r["name"].as_str().unwrap_or_default().to_string(),
                    open: r["isOpen"].as_bool().unwrap_or(false),
                    join_url: r["meetingJoinUrl"].as_str()?.to_string(),
                    auto_move: r["allowMoveParticipantsAutomatically"].as_bool().unwrap_or(false),
                    move_jitter_ms: r["moveJitter"].as_u64().unwrap_or(0),
                })
            })
            .collect(),
    )
}

/// A meeting's breakout room as its organizer's call shows it
/// (`breakoutDetails.mainMeetingProperties.allBreakoutRooms`).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct MeetingRoom {
    pub name: String,
    /// The room's thread (`19:meeting_…@thread.v2`), from its join link.
    pub thread: String,
    pub join_url: String,
    pub open: bool,
    /// Who's assigned to it (MRIs).
    pub invitees: Vec<String>,
    pub auto_move: bool,
    pub allow_return: bool,
}

/// The thread a meeting join link names (`…/meetup-join/19%3ameeting_…
/// %40thread.v2/0?…`).
pub fn thread_of_join_url(url: &str) -> Option<String> {
    let path = url.split("/meetup-join/").nth(1)?.split('/').next()?;
    let thread = path.replace("%3a", ":").replace("%3A", ":").replace("%40", "@");
    (thread.starts_with("19:") && thread.contains('@')).then_some(thread)
}

/// The meeting's rooms, if a call event (to its organizer or a breakout
/// rooms manager) lists them.
pub fn all_rooms(json: &str) -> Option<Vec<MeetingRoom>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let props = v.pointer("/body/breakoutDetails/mainMeetingProperties")?;
    let rooms = props.get("allBreakoutRooms")?.as_array()?;
    Some(
        rooms
            .iter()
            .filter_map(|r| {
                let join_url = r["meetingJoinUrl"].as_str()?.to_string();
                Some(MeetingRoom {
                    name: r["name"].as_str().unwrap_or_default().to_string(),
                    thread: thread_of_join_url(&join_url)?,
                    open: r["isOpen"].as_bool().unwrap_or(false),
                    invitees: r["invitees"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|i| i["id"].as_str().map(str::to_string))
                        .collect(),
                    auto_move: r["allowMoveParticipantsAutomatically"].as_bool().unwrap_or(false),
                    allow_return: r
                        .pointer("/additionalData/allowJoinBackToMainMeeting")
                        .and_then(|a| a.as_str())
                        .is_some_and(|a| a.eq_ignore_ascii_case("true")),
                    join_url,
                })
            })
            .collect(),
    )
}

/// The breakout room you're in, as its call describes it
/// (`meetingDetails.breakoutDetails` on the room's conversation updates):
/// closing a room restricts its chat, which is how Teams tells it's
/// closed.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RoomState {
    pub closed: bool,
    /// The organizer lets people go back (Teams' "Return").
    pub allow_return: bool,
    pub main_join_url: String,
    pub move_jitter_ms: u64,
}

pub fn room_state(json: &str) -> Option<RoomState> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let details = v.pointer("/body/meetingDetails/breakoutDetails")?;
    let props = details.get("breakoutRoomProperties")?;
    let main_join_url = props["mainMeetingJoinUrl"].as_str()?.to_string();
    Some(RoomState {
        closed: props["restrictChatAccess"].as_bool().unwrap_or(false),
        allow_return: details
            .pointer("/additionalData/allowJoinBackToMainMeeting")
            .and_then(|a| a.as_str())
            .is_some_and(|a| a.eq_ignore_ascii_case("true")),
        main_join_url,
        move_jitter_ms: props["moveJitter"].as_u64().unwrap_or(0),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rooms_are_read_as_teams_sends_them() {
        // OST Test 2 assigned to Room 1 when Teams opened it.
        let open = r#"{"body":{"breakoutDetails":{"mainMeetingProperties":{"assignedBreakoutRooms":[{"allowMoveParticipantsAutomatically":true,"isOpen":true,"meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_Mm%40thread.v2/0?context={}","moveJitter":0,"name":"Room 1"}],"breakoutRoomVersion":"v","isDataFetched":true}},"sequenceNumber":3},"callAgentPath":"conversation/localParticipantUpdate/"}"#;
        let rooms = assigned_rooms(open).unwrap();
        assert_eq!(rooms.len(), 1);
        assert!(rooms[0].open && rooms[0].auto_move);
        assert_eq!(rooms[0].name, "Room 1");
        assert!(assigned_rooms(r#"{"body":{"x":1}}"#).is_none());
    }

    #[test]
    fn a_room_says_when_it_closes() {
        // Room 1 as OST Test 2 saw it when Teams closed it (2026-11-11).
        let ev = r#"{"body":{"meetingDetails":{"breakoutDetails":{"additionalData":{"allowJoinBackToMainMeeting":"false"},"breakoutRoomProperties":{"allowUsersToSelectBreakoutRoom":false,"mainMeetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_YTQy%40thread.v2/0","moveJitter":0,"restrictChatAccess":true},"mainMeetingProperties":{"breakoutRoomVersion":"v"}}}},"callAgentPath":"conversation/conversationUpdate/"}"#;
        let state = room_state(ev).unwrap();
        assert!(state.closed && !state.allow_return);
        assert!(state.main_join_url.contains("meeting_YTQy"));
        // The main meeting's own updates aren't a room's.
        assert!(room_state(r#"{"body":{"meetingDetails":{"breakoutDetails":{"mainMeetingProperties":{}}}}}"#).is_none());
    }

    #[test]
    fn the_organizer_sees_every_room() {
        // OST Test 2 organizing, Room 1 open with OST Test 1 in it.
        let ev = r#"{"body":{"breakoutDetails":{"mainMeetingProperties":{"allBreakoutRooms":[{"additionalData":{"allowJoinBackToMainMeeting":"false"},"allowMoveParticipantsAutomatically":false,"eTag":"x","invitees":[{"id":"8:orgid:4287e791-1b98-4963-8b94-281c50472683"}],"isOpen":true,"meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zjcx%40thread.v2/0?context={\"Tid\"%3a\"t\"}","moveJitter":0,"name":"Room 1"}],"breakoutRoomVersion":"v","isDataFetched":true}},"sequenceNumber":4},"callAgentPath":"conversation/localParticipantUpdate/"}"#;
        let rooms = all_rooms(ev).unwrap();
        assert_eq!(rooms[0].thread, "19:meeting_Zjcx@thread.v2");
        assert!(rooms[0].open && !rooms[0].allow_return);
        assert_eq!(rooms[0].invitees, vec!["8:orgid:4287e791-1b98-4963-8b94-281c50472683"]);
        // A participant's update has no list.
        assert!(all_rooms(r#"{"body":{"breakoutDetails":{"mainMeetingProperties":{"assignedBreakoutRooms":[]}}}}"#).is_none());
    }
}
