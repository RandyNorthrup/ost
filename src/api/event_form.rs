//! Outlook's event form as Teams desktop shows it (your event's page): what
//! the form reads and saves beyond Graph, as Outlook on the web's hosted
//! calendar sends it (captured on winpc 2026-11-24, TASK-0274..0276).
//!
//! - The page reads the event with `GetCalendarEvent` (Response options'
//!   `DoNotForwardMeeting`, `IsRoomRequested`, the email reminders
//!   `InboxReminders`, Copilot's managed-event properties, `CharmId`, the
//!   attachments).
//! - Send carries Response options, Rebook declined rooms and the Copilot
//!   reschedule switch as `SetItemField`s of its `UpdateCalendarEvent`
//!   ([`form_updates`]); email reminders, a new category and attachments
//!   are saved at once.
//! - Time suggestions come from Outlook's scheduling service
//!   (`SchedulingB2/api/v1.0/me/findmeetingtimes`).

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::calendar::{HOSTED_CALENDAR_APP, OWA_USER_AGENT, event_path_id, ews_id, mailbox_time_zone, owa_action};

/// Outlook's own property set for Copilot's calendar properties
/// (`CopilotManagedEventType`, `Intent`, `IsDefaultPreferences`, …).
pub const COPILOT_PROPERTY_SET: &str = "11000e07-b51b-40d6-af21-caa85edab1d0";

/// One of Outlook's Copilot calendar properties.
fn ext_uri(name: &str, ty: &str) -> Value {
    json!({ "__type": "ExtendedPropertyUri:#Exchange", "PropertySetId": COPILOT_PROPERTY_SET, "PropertyName": name, "PropertyType": ty })
}

fn header(tz: &str) -> Value {
    json!({
        "__type": "JsonRequestHeaders:#Exchange",
        "RequestServerVersion": "V2018_01_08",
        "TimeZoneContext": { "__type": "TimeZoneContext:#Exchange", "TimeZoneDefinition": { "__type": "TimeZoneDefinitionType:#Exchange", "Id": tz } }
    })
}

/// A `SetItemField` of a calendar item's own field.
pub fn set_field(field: &str, value: Value) -> Value {
    json!({
        "__type": "SetItemField:#Exchange",
        "Path": { "__type": "PropertyUri:#Exchange", "FieldURI": field },
        "Item": { "__type": "CalendarItem:#Exchange", field: value }
    })
}

/// A `SetItemField` of one of Copilot's properties; `None` sends the
/// property without a value, as Outlook's form does for one it leaves as
/// it is (`IsDefaultPreferences`) or clears (`Intent`).
pub fn set_extended(name: &str, ty: &str, value: Option<String>) -> Value {
    let mut prop = json!({ "__type": "ExtendedPropertyType:#Exchange", "ExtendedFieldURI": ext_uri(name, ty) });
    if let Some(v) = value {
        prop["Value"] = v.into();
    }
    json!({
        "__type": "SetItemField:#Exchange",
        "Path": ext_uri(name, ty),
        "Item": { "__type": "Message:#Exchange", "ExtendedProperty": [prop] }
    })
}

/// What Send adds to the form's `UpdateCalendarEvent` for the switches only
/// Outlook keeps, in Outlook's order (captured 2026-11-24): `form` holds
/// the ones that changed —
/// - `allowForwarding` → `DoNotForwardMeeting` (its opposite),
///   `requestResponses` → `IsResponseRequested`, `hideAttendees` →
///   `HideAttendees` (Response options);
/// - `rebookRooms` → `IsRoomRequested` (Location settings' Rebook declined
///   rooms);
/// - `managed` `{on, intent}`: "If conflicts arise, let Copilot reschedule
///   this event." with its Acceptable times: on, `CopilotAutoReschedulingCount`
///   0, `CopilotManagedEventType` 1, `Intent` (the times as Outlook's
///   constraint JSON) and `IsDefaultPreferences` false; off,
///   `CopilotManagedEventType` 0 with `Intent` and `IsDefaultPreferences`
///   sent empty;
/// - `docLinks`: the Loop components put in the body (`DocLinks`,
///   OneDrivePro, permission 6).
///
/// Any other change also sends `IsDefaultPreferences` empty, as Outlook does.
pub fn form_updates(form: &Value) -> Vec<Value> {
    let mut out = Vec::new();
    let b = |k: &str| form.get(k).and_then(Value::as_bool);
    if let Some(on) = b("allowForwarding") {
        out.push(set_field("DoNotForwardMeeting", (!on).into()));
    }
    if let Some(on) = b("requestResponses") {
        // (Outlook's path for it is CalendarIsResponseRequested.)
        let mut f = set_field("IsResponseRequested", on.into());
        f["Path"]["FieldURI"] = "CalendarIsResponseRequested".into();
        out.push(f);
    }
    if let Some(on) = b("hideAttendees") {
        out.push(set_field("HideAttendees", on.into()));
    }
    if let Some(links) = form.get("docLinks").and_then(Value::as_array).filter(|l| !l.is_empty()) {
        let links: Vec<Value> = links
            .iter()
            .filter_map(Value::as_str)
            .map(|u| json!({ "__type": "DocLink", "PermissionType": 6, "ProviderType": "OneDrivePro", "Url": u }))
            .collect();
        out.push(set_field("DocLinks", links.into()));
    }
    let managed = form.get("managed").filter(|m| m.is_object());
    match managed {
        Some(m) if m.get("on").and_then(Value::as_bool) == Some(true) => {
            out.push(set_extended("CopilotAutoReschedulingCount", "Integer", Some("0".into())));
            out.push(set_extended("CopilotManagedEventType", "Integer", Some("1".into())));
            let intent = m.get("intent").and_then(Value::as_str).unwrap_or_default();
            out.push(set_extended("Intent", "String", Some(intent).filter(|i| !i.is_empty()).map(str::to_string)));
            out.push(set_extended("IsDefaultPreferences", "Boolean", Some("false".into())));
        }
        Some(_) => {
            out.push(set_extended("CopilotManagedEventType", "Integer", Some("0".into())));
            out.push(set_extended("Intent", "String", None));
            out.push(set_extended("IsDefaultPreferences", "Boolean", None));
        }
        None if !out.is_empty() || b("rebookRooms").is_some() => out.push(set_extended("IsDefaultPreferences", "Boolean", None)),
        None => {}
    }
    if let Some(on) = b("rebookRooms") {
        out.push(set_field("IsRoomRequested", on.into()));
    }
    // Outlook sends its changes in the order of their names.
    let name = |u: &Value| {
        let p = &u["Path"];
        let n = p.get("PropertyName").or_else(|| p.get("FieldURI")).and_then(Value::as_str).unwrap_or_default();
        n.strip_prefix("Calendar").unwrap_or(n).to_string()
    };
    out.sort_by_key(name);
    out
}

/// Outlook's "Acceptable times" as its `Intent` property (captured
/// 2026-11-24): `{"IntentConstraint": {"ConstraintType": "AND",
/// "Constraints": [days, times]}, "Version": 1}`, the days an OR of `Date`
/// filters (a run of days `2026-11-24..2026-11-27`, a single day
/// `2026-11-30`), the times an OR of `TimeOfDay` minute ranges (Morning
/// `0..720`, Midday `720..780`, Afternoon `780..1440`, Custom
/// `start..end`). One filter goes alone, without its OR.
pub fn intent_json(days: &[chrono::NaiveDate], times: &[(u32, u32)]) -> String {
    let mut days: Vec<chrono::NaiveDate> = days.to_vec();
    days.sort();
    days.dedup();
    let day = |d: &chrono::NaiveDate| d.format("%Y-%m-%d").to_string();
    let mut runs: Vec<Value> = Vec::new();
    let mut i = 0;
    while i < days.len() {
        let mut j = i;
        while j + 1 < days.len() && days[j + 1] - days[j] == chrono::Duration::days(1) {
            j += 1;
        }
        let v = if i == j { day(&days[i]) } else { format!("{}..{}", day(&days[i]), day(&days[j])) };
        runs.push(json!({ "FilterType": "Date", "FilterValue": v }));
        i = j + 1;
    }
    let times: Vec<Value> = times.iter().map(|(a, b)| json!({ "FilterType": "TimeOfDay", "FilterValue": format!("{a}..{b}") })).collect();
    let group = |mut l: Vec<Value>| match l.len() {
        0 => None,
        1 => l.pop(),
        _ => Some(json!({ "ConstraintType": "OR", "Constraints": l })),
    };
    let parts: Vec<Value> = [group(runs), group(times)].into_iter().flatten().collect();
    json!({ "IntentConstraint": { "ConstraintType": "AND", "Constraints": parts }, "Version": 1 }).to_string()
}

/// The days and times an `Intent` holds (the inverse of [`intent_json`]).
pub fn parse_intent(intent: &str) -> (Vec<String>, Vec<(u32, u32)>) {
    let v: Value = serde_json::from_str(intent).unwrap_or_default();
    let mut days = Vec::new();
    let mut times = Vec::new();
    fn walk(v: &Value, days: &mut Vec<String>, times: &mut Vec<(u32, u32)>) {
        if let Some(c) = v.get("Constraints").and_then(Value::as_array) {
            for x in c {
                walk(x, days, times);
            }
            return;
        }
        let val = v.get("FilterValue").and_then(Value::as_str).unwrap_or_default();
        match v.get("FilterType").and_then(Value::as_str) {
            Some("Date") => {
                let (a, b) = val.split_once("..").unwrap_or((val, val));
                if let (Ok(a), Ok(b)) = (chrono::NaiveDate::parse_from_str(a, "%Y-%m-%d"), chrono::NaiveDate::parse_from_str(b, "%Y-%m-%d")) {
                    let mut d = a;
                    while d <= b && days.len() < 400 {
                        days.push(d.format("%Y-%m-%d").to_string());
                        d += chrono::Duration::days(1);
                    }
                }
            }
            Some("TimeOfDay") => {
                if let Some((a, b)) = val.split_once("..") {
                    if let (Ok(a), Ok(b)) = (a.parse(), b.parse()) {
                        times.push((a, b));
                    }
                }
            }
            _ => {}
        }
    }
    walk(v.get("IntentConstraint").unwrap_or(&Value::Null), &mut days, &mut times);
    (days, times)
}

/// What Outlook's form reads of your event that Graph doesn't give
/// (`GetCalendarEvent`, as the form opens): Response options' Allow
/// forwarding, Rebook declined rooms, the email reminders, Copilot's
/// reschedule switch and its acceptable times, the charm, the attachments.
pub async fn outlook_event(id: &str) -> Result<Value> {
    let tz = mailbox_time_zone().await;
    let body = json!({
        "__type": "GetCalendarEventJsonRequest:#Exchange",
        "Header": header(&tz),
        "Body": {
            "__type": "GetCalendarEventRequest:#Exchange",
            "EventIds": [{ "__type": "ItemId:#Exchange", "Id": ews_id(event_path_id(id)?) }],
            "ItemShape": {
                "BaseShape": "IdOnly", "BodyType": "HTML", "FilterHtmlContent": true, "ClientSupportsIrm": true, "MaximumBodySize": 0,
                "AdditionalProperties": [
                    ext_uri("Intent", "String"), ext_uri("CopilotManagedEventType", "Integer"),
                    ext_uri("CopilotAutoReschedulingCount", "Integer"), ext_uri("IsDefaultPreferences", "Boolean")
                ]
            },
            "DraftOnlineMeetingSupport": true
        }
    });
    let v = owa_action("GetCalendarEvent", &body).await?;
    let item = v
        .pointer("/Body/Items/0")
        .or_else(|| v.pointer("/Body/ResponseMessages/Items/0/Items/0"))
        .cloned()
        .context("Outlook didn't give the event")?;
    Ok(outlook_event_from(&item))
}

/// [`outlook_event`]'s answer from Outlook's item.
pub fn outlook_event_from(item: &Value) -> Value {
    let ext = |name: &str| {
        item.get("ExtendedProperty")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .find(|p| p.pointer("/ExtendedFieldURI/PropertyName").and_then(Value::as_str) == Some(name))
            .and_then(|p| p.get("Value"))
            .and_then(|v| v.as_str().map(str::to_string).or_else(|| Some(v.to_string())))
            .unwrap_or_default()
    };
    let reminders: Vec<Value> = item
        .get("InboxReminders")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|r| {
            json!({
                "id": r.get("Id").and_then(Value::as_str).unwrap_or_default(),
                "offset": r.get("ReminderOffset").and_then(Value::as_i64).unwrap_or(15),
                "message": r.get("Message").and_then(Value::as_str).unwrap_or_default(),
                // (Outlook answers the option as a number: 1 User, 2 all
                // attendees.)
                "sendOption": match r.get("SendOption").map(|s| s.as_str().map(str::to_string).unwrap_or_else(|| s.to_string())).as_deref() {
                    Some("2") | Some("All") | Some("AllAttendees") => "AllAttendees",
                    _ => "User",
                },
                "organizer": r.get("IsOrganizerReminder").and_then(Value::as_bool).unwrap_or(true),
            })
        })
        .collect();
    let attachments: Vec<Value> = item
        .get("Attachments")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|a| !a.get("IsInline").and_then(Value::as_bool).unwrap_or(false))
        .map(|a| {
            json!({
                "id": a.pointer("/AttachmentId/Id").and_then(Value::as_str).unwrap_or_default(),
                "name": a.get("Name").and_then(Value::as_str).unwrap_or_default(),
                "size": a.get("Size").and_then(Value::as_i64).unwrap_or(0),
                "contentType": a.get("ContentType").and_then(Value::as_str).unwrap_or_default(),
            })
        })
        .collect();
    let (days, times) = parse_intent(&ext("Intent"));
    json!({
        "allowForwarding": !item.get("DoNotForwardMeeting").and_then(Value::as_bool).unwrap_or(false),
        "requestResponses": item.get("IsResponseRequested").and_then(Value::as_bool).unwrap_or(true),
        "hideAttendees": item.get("HideAttendees").and_then(Value::as_bool).unwrap_or(false),
        "rebookRooms": item.get("IsRoomRequested").and_then(Value::as_bool).unwrap_or(false),
        "inboxReminders": reminders,
        "managed": ext("CopilotManagedEventType").parse::<i64>().unwrap_or(-1),
        "intentDays": days,
        "intentTimes": times.iter().map(|(a, b)| json!([a, b])).collect::<Vec<_>>(),
        "charm": item.get("CharmId").or_else(|| item.get("Charm")).and_then(Value::as_i64).unwrap_or(0),
        "attachments": attachments,
        "changeKey": item.pointer("/ItemId/ChangeKey").and_then(Value::as_str).unwrap_or_default(),
    })
}

/// An `UpdateCalendarEvent` of these fields alone, saved at once (as
/// Outlook's form saves the email reminders and categories): `scope` 0.
pub async fn save_now(id: &str, updates: Vec<Value>) -> Result<()> {
    if updates.is_empty() {
        bail!("Nothing to change");
    }
    let tz = mailbox_time_zone().await;
    let item_id = json!({ "__type": "ItemId:#Exchange", "Id": ews_id(event_path_id(id)?) });
    let body = json!({
        "__type": "UpdateCalendarEventJsonRequest:#Exchange",
        "Header": header(&tz),
        "Body": {
            "__type": "UpdateCalendarEventRequest:#Exchange",
            "EventId": item_id,
            "ItemChange": { "__type": "ItemChange:#Exchange", "Updates": updates, "ItemId": item_id },
            "EventScope": 0, "ShouldSendUpdateToAttendees": false, "TargetAudience": 0, "ClientSupportsIrm": true
        }
    });
    let v = owa_action("UpdateCalendarEvent", &body).await?;
    let code = v.pointer("/Body/ResponseMessages/Items/0/ResponseCode").and_then(Value::as_str).unwrap_or("NoError");
    if code != "NoError" {
        bail!("Outlook didn't save the event: {code}");
    }
    Ok(())
}

/// The email reminders as Outlook saves them (Reminder ▸ Add email
/// reminder; captured 2026-11-24): `InboxReminders` `[{ReminderOffset
/// (minutes before), Message, IsOrganizerReminder: true, SendOption
/// ("User", or "AllAttendees" with Send to attendees), OccurrenceChange:
/// "None"}]`, saved when the dialog closes.
pub fn inbox_reminders(list: &[Value]) -> Value {
    list.iter()
        .map(|r| {
            let mut o = json!({
                "__typename": "InboxReminder",
                "ReminderOffset": r.get("offset").and_then(Value::as_i64).unwrap_or(15),
                "Message": r.get("message").and_then(Value::as_str).unwrap_or_default(),
                "IsOrganizerReminder": true,
                "SendOption": if r.get("sendOption").and_then(Value::as_str) == Some("AllAttendees") { "AllAttendees" } else { "User" },
                "OccurrenceChange": "None",
            });
            if let Some(id) = r.get("id").and_then(Value::as_str).filter(|i| !i.is_empty()) {
                o["Id"] = id.into();
            }
            o
        })
        .collect::<Vec<_>>()
        .into()
}

/// Categories ▸ New category (Outlook's "Create new category"; captured
/// 2026-11-24): `UpdateMasterCategoryList` adds `{Name, Color, Id,
/// LastTimeUsed, KeyboardShortcut: 0}` (Color is the preset number, -1 for
/// None), then the event gets it (`Categories`, saved at once).
pub async fn add_master_category(name: &str, color: i64) -> Result<()> {
    let name = name.trim();
    if name.is_empty() {
        bail!("A category needs a name");
    }
    let body = json!({
        "request": {
            "__type": "UpdateMasterCategoryListRequest:#Exchange",
            "AddCategoryList": [{
                "Name": name, "Color": color.clamp(-1, 24), "Id": uuid::Uuid::new_v4().to_string(),
                "LastTimeUsed": chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string(), "KeyboardShortcut": 0
            }],
            "RemoveCategoryList": [], "ChangeCategoryColorList": [], "UpdateCategoryLastTimeUsedList": [], "ChangeCategoryKeyboardShortcutList": []
        }
    });
    let v = owa_action("UpdateMasterCategoryList", &body).await?;
    if v.pointer("/Body/ResponseClass").and_then(Value::as_str) == Some("Error") || v.get("WasSuccessful").and_then(Value::as_bool) == Some(false) {
        bail!("Outlook didn't add the category");
    }
    Ok(())
}

/// Attach ▸ Browse this computer, as Outlook's form attaches a file to the
/// event (captured 2026-11-24): `POST owa/service.svc/CreateAttachmentFromLocalFile`
/// with the request (`CreateAttachmentRequest`: the event's id, one
/// `FileAttachment` with its name, type and size) in `X-OWA-UrlPostData`
/// (encodeURI) and the file itself as the body. The answer names the
/// attachment.
pub async fn attach_file(id: &str, path: &std::path::Path) -> Result<Value> {
    let bytes = tokio::fs::read(path).await.with_context(|| format!("Can't read {}", path.display()))?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("attachment").to_string();
    let content_type = mime_of(&name);
    let tz = mailbox_time_zone().await;
    let cancel = uuid::Uuid::new_v4().to_string();
    let request = json!({
        "__type": "CreateAttachmentJsonRequest:#Exchange",
        "Header": header(&tz),
        "Body": {
            "__type": "CreateAttachmentRequest:#Exchange",
            "ParentItemId": { "__type": "ItemId:#Exchange", "Id": ews_id(event_path_id(id)?) },
            "Attachments": [{
                "__type": "FileAttachment:#Exchange", "Content": "", "ContentType": content_type, "IsContactPhoto": false,
                "IsInline": false, "Name": name, "Size": bytes.len()
            }],
            "CancellationId": cancel, "RequireImageType": false, "IncludeContentIdInResponse": false, "ClientSupportsIrm": true,
            "SliceNumber": 0, "TotalSlices": 1
        }
    });
    let len = bytes.len() as i64;
    let v = owa_upload("CreateAttachmentFromLocalFile", &request, bytes).await?;
    let a = v
        .pointer("/ResponseMessages/Items/0/Attachments/0")
        .or_else(|| v.pointer("/Body/ResponseMessages/Items/0/Attachments/0"))
        .cloned()
        .unwrap_or_default();
    let code = v
        .pointer("/ResponseMessages/Items/0/ResponseCode")
        .or_else(|| v.pointer("/Body/ResponseMessages/Items/0/ResponseCode"))
        .and_then(Value::as_str)
        .unwrap_or("NoError");
    if code != "NoError" {
        bail!("Outlook didn't attach the file: {code}");
    }
    Ok(json!({
        "id": a.pointer("/AttachmentId/Id").and_then(Value::as_str).unwrap_or_default(),
        "name": a.get("Name").and_then(Value::as_str).unwrap_or(&name),
        "size": a.get("Size").and_then(Value::as_i64).filter(|n| *n > 0).unwrap_or(len),
        "contentType": content_type,
    }))
}

/// An attachment's More actions ▸ Remove attachment (`DeleteAttachment`).
pub async fn delete_attachment(event_id: &str, attachment_id: &str) -> Result<()> {
    if attachment_id.is_empty() || !attachment_id.bytes().all(|b| b.is_ascii_alphanumeric() || b"+/=-_".contains(&b)) {
        bail!("Not an attachment");
    }
    let tz = mailbox_time_zone().await;
    let body = json!({
        "__type": "DeleteAttachmentJsonRequest:#Exchange",
        "Header": header(&tz),
        "Body": {
            "__type": "DeleteAttachmentRequest:#Exchange", "ClientSupportsIrm": true,
            "AttachmentIds": [{ "Id": attachment_id, "RootItemId": ews_id(event_path_id(event_id)?) }]
        }
    });
    let v = owa_action("DeleteAttachment", &body).await?;
    let code = v.pointer("/Body/ResponseMessages/Items/0/ResponseCode").and_then(Value::as_str).unwrap_or("NoError");
    if code != "NoError" {
        bail!("Outlook didn't remove the attachment: {code}");
    }
    Ok(())
}

/// An attachment's content (Preview, Download), through Graph.
pub async fn attachment_bytes(client: &super::client::TeamsClient, event_id: &str, attachment_id: &str) -> Result<Vec<u8>> {
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
    let id = event_path_id(event_id)?;
    let r = client
        .graph_get_with(&format!("/me/events/{id}/attachments/{}/$value", enc(&attachment_id.replace('/', "-").replace('+', "_"))), &[("Prefer", "IdType=\"ImmutableId\"")])
        .await?;
    Ok(r.bytes().await?.to_vec())
}

/// Attach ▸ OneDrive ▸ Share link: the file's link as Outlook's form puts
/// it in the body (captured 2026-11-24: the organization's sharing link,
/// `https://…-my.sharepoint.com/:t:/p/…`).
pub async fn share_link(client: &super::client::TeamsClient, drive_id: &str, item_id: &str) -> Result<String> {
    let ok = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"!-_".contains(&b));
    if !ok(drive_id) || !ok(item_id) {
        bail!("Not a OneDrive file");
    }
    let v: Value = client
        .graph_post(&format!("/drives/{drive_id}/items/{item_id}/createLink"), &json!({ "type": "view", "scope": "organization" }))
        .await?
        .json()
        .await
        .context("createLink")?;
    v.pointer("/link/webUrl").and_then(Value::as_str).map(str::to_string).context("No link")
}

/// Attach ▸ Upload and share ("Upload to" OneDrive ▸ Attachments; captured
/// 2026-11-24: the file goes to your OneDrive's Attachments folder, a name
/// already there renamed, and its link goes in the body).
pub async fn upload_and_share(client: &super::client::TeamsClient, path: &std::path::Path) -> Result<Value> {
    let name = path.file_name().and_then(|n| n.to_str()).context("File has no name")?.to_string();
    let bytes = tokio::fs::read(path).await.with_context(|| format!("Can't read {}", path.display()))?;
    let seg = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>().replace('+', "%20");
    let item: Value = client
        .graph_put_bytes(&format!("/me/drive/root:/Attachments/{}:/content?@microsoft.graph.conflictBehavior=rename", seg(&name)), bytes, "application/octet-stream")
        .await?
        .json()
        .await
        .context("Upload reply")?;
    let item_id = item.get("id").and_then(Value::as_str).context("Upload reply has no id")?;
    let drive_id = item.pointer("/parentReference/driveId").and_then(Value::as_str).context("Upload reply has no drive")?;
    let url = share_link(client, drive_id, item_id).await?;
    Ok(json!({ "url": url, "name": item.get("name").and_then(Value::as_str).unwrap_or(&name) }))
}

/// The Graphics pane's Stock images and Stickers (Insert emoji, images and
/// stickers; captured 2026-11-24): Microsoft's content service,
/// `GET hubblecontent.osi.office.net/contentsvc/api/pivots?filter=pivotNames/any(p: p eq '<pivot>')&search=…&top=…&app=5&secureurl=1`,
/// pictures under `cdn.hubblecontent.osi.office.net/<Path>`.
pub async fn graphics(pivot: &str, search: &str, top: u32) -> Result<Value> {
    if !matches!(pivot, "Stock Images" | "Stickers") {
        bail!("Not a pivot");
    }
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
    let url = format!(
        "https://hubblecontent.osi.office.net/contentsvc/api/pivots?filter={}&search={}&top={}&app=5&secureurl=1",
        enc(&format!("pivotNames/any(p: p eq '{pivot}' )")),
        enc(search),
        top.clamp(1, 60)
    );
    let v: Value = reqwest::Client::new().get(url).header("user-agent", OWA_USER_AGENT).send().await?.error_for_status()?.json().await?;
    Ok(json!({ "pivot": pivot, "search": search, "items": graphics_from(&v) }))
}

/// The items of a content-service answer.
pub fn graphics_from(v: &Value) -> Vec<Value> {
    const CDN: &str = "https://cdn.hubblecontent.osi.office.net/";
    v.as_array()
        .into_iter()
        .flatten()
        .flat_map(|p| p.get("MicrosoftContents").and_then(Value::as_array).cloned().unwrap_or_default())
        .filter_map(|c| {
            let path = c.get("Path").and_then(Value::as_str)?;
            let thumb = c.pointer("/ThumbnailInfo/Medium/Path").and_then(Value::as_str).unwrap_or(path);
            Some(json!({
                "id": c.get("Id").and_then(Value::as_str).unwrap_or_default(),
                "description": c.get("Description").and_then(Value::as_str).unwrap_or_default(),
                "url": format!("{CDN}{path}"),
                "thumb": format!("{CDN}{thumb}"),
                "width": c.get("Width").and_then(Value::as_i64).unwrap_or(0),
                "height": c.get("Height").and_then(Value::as_i64).unwrap_or(0),
            }))
        })
        .collect()
}

/// A stock picture's local copy (shown in the body while editing).
pub async fn graphics_file(url: &str) -> Result<std::path::PathBuf> {
    if !url.starts_with("https://cdn.hubblecontent.osi.office.net/") {
        bail!("Not a stock picture");
    }
    let bytes = reqwest::Client::new().get(url).send().await?.error_for_status()?.bytes().await?;
    let dir = std::env::temp_dir().join("ost-graphics");
    tokio::fs::create_dir_all(&dir).await?;
    let name = url.rsplit('/').next().unwrap_or("picture.png").chars().filter(|c| c.is_ascii_alphanumeric() || "._-".contains(*c)).collect::<String>();
    let file = dir.join(format!("{}-{}", uuid::Uuid::new_v4().simple(), if name.is_empty() { "picture.png".into() } else { name }));
    tokio::fs::write(&file, &bytes).await?;
    Ok(file)
}

fn mime_of(name: &str) -> &'static str {
    match name.rsplit('.').next().map(|e| e.to_ascii_lowercase()).as_deref() {
        Some("txt") => "text/plain",
        Some("pdf") => "application/pdf",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("docx") => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        Some("xlsx") => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        Some("pptx") => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        Some("zip") => "application/zip",
        Some("csv") => "text/csv",
        Some("html") | Some("htm") => "text/html",
        _ => "application/octet-stream",
    }
}

/// Outlook's upload request (`owa/service.svc/<action>`): the request JSON
/// in `X-OWA-UrlPostData` (encodeURI, as Outlook's XHR sends it) and the
/// file as the body.
async fn owa_upload(action: &str, request: &Value, bytes: Vec<u8>) -> Result<Value> {
    let (token, _) = crate::auth::oauth::brokered_token(HOSTED_CALENDAR_APP, "https://outlook.office.com", "https://outlook.office.com/.default", None).await?;
    let tenant = crate::config::Config::load().ok().and_then(|c| c.tenant_id).unwrap_or_default();
    let anchor = crate::config::Config::load().ok().and_then(|c| c.object_id()).map(|o| format!("OID:{o}@{tenant}")).unwrap_or_default();
    // encodeURI: everything but A-Z a-z 0-9 ;,/?:@&=+$-_.!~*'()# is escaped.
    let data: String = request
        .to_string()
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b";,/?:@&=+$-_.!~*'()#".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    let resp = reqwest::Client::new()
        .post(format!("https://outlook.office.com/owa/service.svc/{action}"))
        .bearer_auth(token)
        .header("x-anchormailbox", anchor)
        .header("user-agent", OWA_USER_AGENT)
        .header("x-owa-action", action)
        .header("x-owa-correlationid", uuid::Uuid::new_v4().to_string())
        .header("x-req-source", "Calendar")
        .header("x-owa-hosted-ux", "true")
        .header("x-owa-host-app", "teams_desktop")
        .header("origin", "https://outlook.office.com")
        .header("prefer", "IdType=\"ImmutableId\", exchange.behavior=\"IncludeThirdPartyOnlineMeetingProviders\"")
        .header("x-owa-urlpostdata", data)
        .body(bytes)
        .send()
        .await
        .with_context(|| format!("{action} failed"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("{action}: {status} {}", text.chars().take(300).collect::<String>());
    }
    let v: Value = serde_json::from_str(&text).unwrap_or_default();
    Ok(v.get("Body").cloned().unwrap_or(v))
}

/// The time panel's Time suggestions, from Outlook's scheduling service as
/// its form asks (captured 2026-11-24: `POST outlook.office.com/SchedulingB2/api/v1.0/me/findmeetingtimes`,
/// the hosted calendar's token, `x-findmeetingtimes-appscenario:
/// suggestions`, `x-isupdateevent` for an existing event): the attendees
/// (`{EmailAddress: {address}, Type: "required"|"optional"}`); for one
/// event `timeConstraint` one timeslot from its start to 9 days later
/// (local "yyyy-MM-dd HH:mm:ss" in the mailbox's zone) and
/// `constraints.queryExpression` "Date:2026-12-01..2026-12-06" (5 days);
/// for a series `constraints.patternedRecurrence` (`{pattern: {type,
/// interval, firstDayofWeek, daysOfWeek: [4]}, range: {type, startDate,
/// endDate, recurrenceTimeZone}}`); `meetingDuration` ("PT30M"),
/// `minimumAttendeePercentage` 100, `maxCandidates` 5,
/// `returnSuggestionReasons`, `locationConstraint` null.
/// The answer's `MeetingTimeSuggestions` become `[{start, end (local, the
/// zone's), available (how many are free), total, confidence}]`.
pub async fn find_meeting_times(req: &Value) -> Result<Value> {
    let tz = mailbox_time_zone().await;
    let s = |k: &str| req.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let attendees: Vec<Value> = req
        .get("attendees")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let address = a.get("address").and_then(Value::as_str)?.trim();
            (address.contains('@')).then(|| {
                json!({ "EmailAddress": { "address": address }, "Type": if a.get("optional").and_then(Value::as_bool) == Some(true) { "optional" } else { "required" } })
            })
        })
        .collect();
    let minutes = req.get("duration").and_then(Value::as_i64).unwrap_or(30).max(1);
    let local = |t: &str| t.replace('T', " ").chars().take(19).collect::<String>();
    let mut body = json!({
        "attendees": attendees,
        "meetingDuration": format!("PT{minutes}M"),
        "minimumAttendeePercentage": 100,
        "maxCandidates": 5,
        "returnSuggestionReasons": true,
        "locationConstraint": null,
        "PrioritizeInPersonAvailability": false,
    });
    if let Some(r) = req.get("recurrence").filter(|r| r.is_object()) {
        let mut r = r.clone();
        r["range"]["recurrenceTimeZone"] = tz.clone().into();
        body["constraints"] = json!({ "patternedRecurrence": r });
    } else {
        body["timeConstraint"] = json!({ "timeslots": [{
            "Start": { "DateTime": local(&s("from")), "TimeZone": tz },
            "End": { "DateTime": local(&s("to")), "TimeZone": tz }
        }] });
        // The 5-day window ("The best options in a 5-day window").
        if !s("query").is_empty() {
            body["constraints"] = json!({ "queryExpression": s("query") });
        }
    }
    let (token, _) = crate::auth::oauth::brokered_token(HOSTED_CALENDAR_APP, "https://outlook.office.com", "https://outlook.office.com/.default", None).await?;
    let tenant = crate::config::Config::load().ok().and_then(|c| c.tenant_id).unwrap_or_default();
    let anchor = crate::config::Config::load().ok().and_then(|c| c.object_id()).map(|o| format!("OID:{o}@{tenant}")).unwrap_or_default();
    let mut http = reqwest::Client::new()
        .post("https://outlook.office.com/SchedulingB2/api/v1.0/me/findmeetingtimes")
        .bearer_auth(token)
        .header("x-anchormailbox", anchor)
        .header("user-agent", OWA_USER_AGENT)
        .header("x-findmeetingtimes-appname", "owa-react")
        .header("x-findmeetingtimes-appscenario", "suggestions")
        .header("x-maxfilteredsuggestions", "5")
        .header("x-getschedule-whv2", "true")
        .header("x-tenantid", tenant.as_str())
        .header("prefer", "IdType=\"ImmutableId\", exchange.behavior=\"IncludeThirdPartyOnlineMeetingProviders\"")
        .header("x-returnaccommodations", "true")
        .header("x-filterbusyrequiredattendees", "true")
        .header("x-ReturnOriginalAvailability", "true")
        .header("x-owa-hosted-ux", "true")
        .header("origin", "https://outlook.office.com")
        .json(&body);
    if req.get("existing").and_then(Value::as_bool) == Some(true) {
        http = http.header("x-isupdateevent", "true");
    }
    let resp = http.send().await.context("findmeetingtimes failed")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("findmeetingtimes: {status} {}", text.chars().take(300).collect::<String>());
    }
    let v: Value = serde_json::from_str(&text).unwrap_or_default();
    Ok(json!({ "suggestions": suggestions_from(&v), "reason": v.get("EmptySuggestionsReason").and_then(Value::as_str).unwrap_or_default() }))
}

/// The suggestions of a findmeetingtimes answer (PascalCase, as Outlook's
/// scheduling service answers; camelCase too).
pub fn suggestions_from(v: &Value) -> Vec<Value> {
    let get = |o: &Value, k: &str| o.get(k).or_else(|| o.get(&lower_first(k))).cloned().unwrap_or(Value::Null);
    get(v, "MeetingTimeSuggestions")
        .as_array()
        .into_iter()
        .flatten()
        .map(|s| {
            let slot = get(s, "MeetingTimeSlot");
            // The service answers in UTC (TimeZone "UTC"): those times get
            // a Z, others are the zone's wall times.
            let t = |k: &str| {
                let p = get(&slot, k);
                let dt = get(&p, "DateTime").as_str().unwrap_or_default().split('.').next().unwrap_or_default().to_string();
                let tz = get(&p, "TimeZone").as_str().unwrap_or("UTC").to_string();
                if tz.is_empty() || tz.eq_ignore_ascii_case("UTC") { format!("{dt}Z") } else { dt }
            };
            let people = get(s, "AttendeeAvailability");
            let people = people.as_array().cloned().unwrap_or_default();
            let free = people.iter().filter(|p| matches!(get(p, "Availability").as_str(), Some("Free") | Some("free"))).count();
            let organizer_free = matches!(get(s, "OrganizerAvailability").as_str(), Some("Free") | Some("free"));
            json!({
                "start": t("Start"),
                "end": t("End"),
                "available": free + usize::from(organizer_free),
                "total": people.len() + 1,
                "confidence": get(s, "Confidence").as_f64().unwrap_or(0.0),
            })
        })
        .collect()
}

fn lower_first(k: &str) -> String {
    let mut c = k.chars();
    c.next().map(|f| f.to_ascii_lowercase().to_string() + c.as_str()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intent_as_outlook_writes_it() {
        let d = |s: &str| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
        let days = [d("2026-11-24"), d("2026-11-25"), d("2026-11-26"), d("2026-11-27"), d("2026-11-30")];
        // As captured from Outlook's form (Morning and Midday picked).
        assert_eq!(
            intent_json(&days, &[(0, 720), (720, 780)]),
            r#"{"IntentConstraint":{"ConstraintType":"AND","Constraints":[{"ConstraintType":"OR","Constraints":[{"FilterType":"Date","FilterValue":"2026-11-24..2026-11-27"},{"FilterType":"Date","FilterValue":"2026-11-30"}]},{"ConstraintType":"OR","Constraints":[{"FilterType":"TimeOfDay","FilterValue":"0..720"},{"FilterType":"TimeOfDay","FilterValue":"720..780"}]}]},"Version":1}"#
        );
        let (dd, tt) = parse_intent(&intent_json(&days, &[(0, 720), (720, 780)]));
        assert_eq!(dd.len(), 5);
        assert_eq!(dd[4], "2026-11-30");
        assert_eq!(tt, vec![(0, 720), (720, 780)]);
        // One filter of a kind goes alone.
        assert!(intent_json(&[d("2026-12-01")], &[(780, 1440)]).contains(r#"[{"FilterType":"Date","FilterValue":"2026-12-01"},{"FilterType":"TimeOfDay","FilterValue":"780..1440"}]"#));
    }

    #[test]
    fn send_carries_outlooks_switches() {
        let u = form_updates(&json!({ "allowForwarding": false }));
        assert_eq!(u.len(), 2);
        assert_eq!(u[0]["Path"]["FieldURI"], "DoNotForwardMeeting");
        assert_eq!(u[0]["Item"]["DoNotForwardMeeting"], true);
        assert_eq!(u[1]["Path"]["PropertyName"], "IsDefaultPreferences");
        assert!(u[1]["Item"]["ExtendedProperty"][0].get("Value").is_none());
        let u = form_updates(&json!({ "rebookRooms": true }));
        assert_eq!(u[1]["Item"]["IsRoomRequested"], true);
        // As captured: HideAttendees, IsDefaultPreferences, CalendarIsResponseRequested.
        let u = form_updates(&json!({ "requestResponses": false, "hideAttendees": true }));
        let paths: Vec<&str> = u.iter().map(|x| x["Path"]["FieldURI"].as_str().or(x["Path"]["PropertyName"].as_str()).unwrap()).collect();
        assert_eq!(paths, ["HideAttendees", "IsDefaultPreferences", "CalendarIsResponseRequested"]);
        assert_eq!(u[2]["Item"]["IsResponseRequested"], false);
        let u = form_updates(&json!({ "managed": { "on": true, "intent": "{}" } }));
        let names: Vec<&str> = u.iter().map(|x| x["Path"]["PropertyName"].as_str().unwrap()).collect();
        assert_eq!(names, ["CopilotAutoReschedulingCount", "CopilotManagedEventType", "Intent", "IsDefaultPreferences"]);
        assert_eq!(u[1]["Item"]["ExtendedProperty"][0]["Value"], "1");
        let u = form_updates(&json!({ "managed": { "on": false } }));
        assert_eq!(u[0]["Item"]["ExtendedProperty"][0]["Value"], "0");
        assert!(form_updates(&json!({})).is_empty());
    }

    #[test]
    fn reads_outlooks_item() {
        let item = json!({
            "DoNotForwardMeeting": true, "IsRoomRequested": true, "CharmId": 57,
            "InboxReminders": [{ "Id": "r1", "ReminderOffset": 15, "Message": "note", "SendOption": "User", "IsOrganizerReminder": true }],
            "ExtendedProperty": [{ "ExtendedFieldURI": { "PropertyName": "CopilotManagedEventType" }, "Value": "1" },
                                 { "ExtendedFieldURI": { "PropertyName": "Intent" }, "Value": "{\"IntentConstraint\":{\"ConstraintType\":\"AND\",\"Constraints\":[{\"FilterType\":\"TimeOfDay\",\"FilterValue\":\"0..720\"}]},\"Version\":1}" }]
        });
        let v = outlook_event_from(&item);
        assert_eq!(v["allowForwarding"], false);
        assert_eq!(v["rebookRooms"], true);
        assert_eq!(v["charm"], 57);
        assert_eq!(v["managed"], 1);
        assert_eq!(v["intentTimes"], json!([[0, 720]]));
        assert_eq!(v["inboxReminders"][0]["message"], "note");
    }

    #[test]
    fn suggestions_count_who_is_free() {
        let v = json!({ "MeetingTimeSuggestions": [{
            "Confidence": 100.0, "OrganizerAvailability": "Free",
            "MeetingTimeSlot": { "Start": { "DateTime": "2026-12-01T10:30:00.0000000", "TimeZone": "Pacific Standard Time" }, "End": { "DateTime": "2026-12-01T11:00:00.0000000" } },
            "AttendeeAvailability": [{ "Availability": "Free" }, { "Availability": "Busy" }]
        }]});
        let s = suggestions_from(&v);
        assert_eq!(s[0]["available"], 2);
        assert_eq!(s[0]["total"], 3);
        assert_eq!(s[0]["start"], "2026-12-01T10:30:00");
        assert_eq!(s[0]["end"], "2026-12-01T11:00:00Z");
    }
}
