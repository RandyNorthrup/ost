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
/// `start..end`). One filter goes alone, without its OR. A series' days are
/// weekdays instead (captured 2026-11-24 on a weekly series): an OR of
/// `DayOfWeek` filters (`"Thursday"`), the series' own days first, then the
/// picked ones in the order they were picked.
pub fn intent_json(days: &[chrono::NaiveDate], weekdays: &[String], times: &[(u32, u32)]) -> String {
    let mut days: Vec<chrono::NaiveDate> = days.to_vec();
    days.sort();
    days.dedup();
    let day = |d: &chrono::NaiveDate| d.format("%Y-%m-%d").to_string();
    let mut runs: Vec<Value> = Vec::new();
    let mut seen: Vec<&String> = Vec::new();
    for w in weekdays {
        if !seen.contains(&w) {
            seen.push(w);
            runs.push(json!({ "FilterType": "DayOfWeek", "FilterValue": w }));
        }
    }
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

/// The days, weekdays and times an `Intent` holds (the inverse of
/// [`intent_json`]).
pub fn parse_intent(intent: &str) -> (Vec<String>, Vec<String>, Vec<(u32, u32)>) {
    let v: Value = serde_json::from_str(intent).unwrap_or_default();
    let mut days = Vec::new();
    let mut times = Vec::new();
    let mut weekdays = Vec::new();
    fn walk(v: &Value, days: &mut Vec<String>, weekdays: &mut Vec<String>, times: &mut Vec<(u32, u32)>) {
        if let Some(c) = v.get("Constraints").and_then(Value::as_array) {
            for x in c {
                walk(x, days, weekdays, times);
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
            Some("DayOfWeek") => weekdays.push(val.to_string()),
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
    walk(v.get("IntentConstraint").unwrap_or(&Value::Null), &mut days, &mut weekdays, &mut times);
    (days, weekdays, times)
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
    let (days, weekdays, times) = parse_intent(&ext("Intent"));
    json!({
        "allowForwarding": !item.get("DoNotForwardMeeting").and_then(Value::as_bool).unwrap_or(false),
        "requestResponses": item.get("IsResponseRequested").and_then(Value::as_bool).unwrap_or(true),
        "hideAttendees": item.get("HideAttendees").and_then(Value::as_bool).unwrap_or(false),
        "rebookRooms": item.get("IsRoomRequested").and_then(Value::as_bool).unwrap_or(false),
        "inboxReminders": reminders,
        "managed": ext("CopilotManagedEventType").parse::<i64>().unwrap_or(-1),
        "intentDays": days,
        "intentWeekdays": weekdays,
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

/// Editor's correction categories in Outlook's overridden options (the
/// NLEditor ids of Spelling and Grammar).
const SPELLING_ID: &str = "19a112ec-21fd-432a-9d1f-195e5e94a00b";
const GRAMMAR_ID: &str = "04aeb01b-175a-4385-9257-bfc5f7e4b650";

/// The Microsoft Editor Settings switches as Outlook keeps them (the body's
/// Editor button; captured 2026-11-24): your mailbox's Outlook options
/// `Proofing` (spellCheckEnabled, grammarEnabled, proofingLocale),
/// `AutoCorrect` (isAutoCorrectEnabled, isAutoCapitalizationEnabled,
/// autoCapitalizeI) and `TextPrediction`, from `GET ows/v1.0/OutlookOptions`
/// (Outlook's defaults, all on, while you have none).
pub fn editor_options_from(all: &Value) -> Value {
    let find = |class: &str| all.get("options").and_then(Value::as_array).and_then(|l| l.iter().find(|o| o.get("itemClass").and_then(Value::as_str) == Some(class)).cloned()).unwrap_or(Value::Null);
    let (p, a) = (find("Proofing"), find("AutoCorrect"));
    let on = |o: &Value, k: &str| o.get(k).and_then(Value::as_bool).unwrap_or(true);
    json!({
        "autocorrect": on(&a, "isAutoCorrectEnabled"),
        "capitalizeI": on(&a, "autoCapitalizeI"),
        "autoCapitalize": on(&a, "isAutoCapitalizationEnabled"),
        "spelling": on(&p, "spellCheckEnabled"),
        "grammar": on(&p, "grammarEnabled"),
        "proofingLocale": p.get("proofingLocale").and_then(Value::as_str).unwrap_or_default(),
    })
}

pub async fn editor_options() -> Result<Value> {
    let all = super::calendar::ows(reqwest::Method::GET, "ows/v1.0/OutlookOptions", None).await?;
    Ok(editor_options_from(&all))
}

/// What the dialog's OK writes, in Outlook's order: `Proofing`,
/// `TextPrediction`, `AutoCorrect`, each `{correlationId, options}` POSTed
/// to `ows/v1.0/OutlookOptions/<class>` the first time (Outlook's new
/// option: feature 25, 63, 56) and PATCHed as the whole option after. A
/// Spelling or Grammar change also goes in the overridden options'
/// `editorServiceOverriddenSettings` and `editorPaneOverriddenSettings`
/// (`{id, name, value "0"/"1", languageId}`). `opts`: the dialog's
/// switches; `locale`: the proofing locale ("en-us").
pub fn editor_option_writes(all: &Value, opts: &Value, locale: &str) -> Vec<(reqwest::Method, String, Value)> {
    let find = |class: &str| all.get("options").and_then(Value::as_array).and_then(|l| l.iter().find(|o| o.get("itemClass").and_then(Value::as_str) == Some(class)).cloned());
    let flag = |k: &str| opts.get(k).and_then(Value::as_bool).unwrap_or(true);
    let locale = if locale.is_empty() { "en-us" } else { locale };
    let mut out = Vec::new();
    let mut put = |class: &str, current: Option<Value>, fresh: Value, set: Value| {
        let existed = current.is_some();
        let mut o = current.unwrap_or(fresh);
        if let Some(m) = o.as_object_mut() {
            for k in ["feature@is.Queryable", "feature@odata.type", "createdDateTime", "lastModifiedDateTime"] {
                m.remove(k);
            }
            for (k, v) in set.as_object().into_iter().flatten() {
                m.insert(k.clone(), v.clone());
            }
        }
        let body = json!({ "correlationId": uuid::Uuid::new_v4().to_string(), "options": o });
        out.push((if existed { reqwest::Method::PATCH } else { reqwest::Method::POST }, format!("ows/v1.0/OutlookOptions/{class}"), body));
    };
    // Proofing, with Editor's category overrides.
    let proofing = find("Proofing");
    let was = |k: &str| proofing.as_ref().and_then(|p| p.get(k)).and_then(Value::as_bool).unwrap_or(true);
    let mut over: Value = proofing
        .as_ref()
        .and_then(|p| p.get("overriddenOptions"))
        .and_then(Value::as_str)
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_else(|| {
            json!({ "options": [], "categories": [], "sharedUserSettings": {
                "editorServiceOverriddenSettings": [{ "id": SPELLING_ID, "value": "1" }, { "id": GRAMMAR_ID, "value": "1" }],
                "inlineEditingSettings": [], "augloopOverriddenSettings": [], "editorPaneOverriddenSettings": [] } })
        });
    for (id, name, key, setting) in [(SPELLING_ID, "Spelling", "spelling", "spellCheckEnabled"), (GRAMMAR_ID, "Grammar", "grammar", "grammarEnabled")] {
        if flag(key) == was(setting) {
            continue;
        }
        let entry = json!({ "id": id, "name": name, "value": if flag(key) { "1" } else { "0" }, "languageId": locale });
        for list in ["editorServiceOverriddenSettings", "editorPaneOverriddenSettings"] {
            if let Some(l) = over.pointer_mut(&format!("/sharedUserSettings/{list}")).and_then(Value::as_array_mut) {
                l.retain(|e| !(e.get("id").and_then(Value::as_str) == Some(id) && e.get("name").is_some()));
                l.push(entry.clone());
            }
        }
    }
    put(
        "Proofing",
        proofing.clone(),
        json!({ "feature": 25, "writingRefinementsEnabled": true, "proofingLocale": locale, "isTonalFreExperienceEnabled": true, "isEditorIndicatorEnabled": true,
                "isToneEnabledInEditorIndicator": true, "shouldShowIndicatorButton": false, "areMxLanguagesSeeded": false, "isLanguageAutoDetectEnabled": true, "isSpellCheckOnSendEnabled": false }),
        json!({ "spellCheckEnabled": flag("spelling"), "grammarEnabled": flag("grammar"), "overriddenOptions": over.to_string() }),
    );
    let prediction = find("TextPrediction");
    let predict = prediction.as_ref().and_then(|p| p.get("isTextPredictionEnabled")).and_then(Value::as_bool).unwrap_or(false);
    put("TextPrediction", prediction, json!({ "feature": 63 }), json!({ "isTextPredictionEnabled": predict }));
    put(
        "AutoCorrect",
        find("AutoCorrect"),
        json!({ "feature": 56 }),
        json!({ "isAutoCorrectEnabled": flag("autocorrect"), "isAutoCapitalizationEnabled": flag("autoCapitalize"), "autoCapitalizeI": flag("capitalizeI") }),
    );
    out
}

pub async fn set_editor_options(opts: &Value) -> Result<Value> {
    use super::calendar::ows;
    let all = ows(reqwest::Method::GET, "ows/v1.0/OutlookOptions", None).await?;
    let locale = all
        .get("options")
        .and_then(Value::as_array)
        .and_then(|l| l.iter().find(|o| o.get("itemClass").and_then(Value::as_str) == Some("Proofing")))
        .and_then(|p| p.get("proofingLocale"))
        .and_then(Value::as_str)
        .unwrap_or("en-us")
        .to_string();
    for (method, path, body) in editor_option_writes(&all, opts, &locale) {
        ows(method, &path, Some(&body)).await?;
    }
    editor_options().await
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

fn is_drive_id(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"!-_".contains(&b))
}

/// "Upload to" ▸ Change location: the folders in one of your OneDrive's
/// folders (`folder_id` "root" for Files), by name, as Outlook lists them.
pub async fn drive_folders(client: &super::client::TeamsClient, folder_id: &str) -> Result<Value> {
    let base = match folder_id {
        "root" | "" => "/me/drive/root".to_string(),
        id if is_drive_id(id) => format!("/me/drive/items/{id}"),
        _ => bail!("Not a folder"),
    };
    let v: Value = client.graph_get(&format!("{base}/children?$select=id,name,folder&$top=999")).await?.json().await.context("Folders")?;
    Ok(json!({ "folderId": folder_id, "folders": folders_from(&v) }))
}

/// The folders of a children answer, sorted by name (case-blind).
pub fn folders_from(v: &Value) -> Vec<Value> {
    let mut l: Vec<Value> = v
        .get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|i| i.get("folder").is_some())
        .map(|i| json!({ "id": i.get("id").and_then(Value::as_str).unwrap_or_default(), "name": i.get("name").and_then(Value::as_str).unwrap_or_default() }))
        .collect();
    l.sort_by_key(|f| f["name"].as_str().unwrap_or_default().to_lowercase());
    l
}

/// "Upload to" ▸ Create new folder: a folder in the folder shown (a name
/// already there fails, as Outlook's "This folder name is already in use.").
pub async fn create_drive_folder(client: &super::client::TeamsClient, parent_id: &str, name: &str) -> Result<Value> {
    let base = match parent_id {
        "root" | "" => "/me/drive/root".to_string(),
        id if is_drive_id(id) => format!("/me/drive/items/{id}"),
        _ => bail!("Not a folder"),
    };
    let r = client.graph_post(&format!("{base}/children"), &json!({ "name": name, "folder": {}, "@microsoft.graph.conflictBehavior": "fail" })).await?;
    if r.status() == reqwest::StatusCode::CONFLICT {
        bail!("in use");
    }
    let v: Value = r.error_for_status()?.json().await?;
    Ok(json!({ "id": v.get("id").and_then(Value::as_str).unwrap_or_default(), "name": v.get("name").and_then(Value::as_str).unwrap_or(name) }))
}

/// The file-type icon Outlook puts before a OneDrive file's link (its
/// Fluent item-types picture, by extension; captured 2026-11-24:
/// `…/item-types/24_1.5x/docx.png`).
pub fn file_type_icon(name: &str) -> String {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    let kind = match ext.as_str() {
        "doc" | "docm" | "docx" => "docx",
        "dot" | "dotm" | "dotx" => "dotx",
        "xls" | "xlsb" | "xlsm" | "xlsx" => "xlsx",
        "xlt" | "xltm" | "xltx" => "xltx",
        "ppt" | "pptm" | "pptx" | "pps" => "pptx",
        "pot" | "potm" | "potx" => "potx",
        "ppsm" | "ppsx" => "ppsx",
        "pdf" => "pdf",
        "txt" | "log" => "txt",
        "rtf" => "rtf",
        "csv" => "csv",
        "one" | "onepkg" | "onetoc" => "one",
        "vsd" | "vsdm" | "vsdx" => "vsdx",
        "mpp" => "mpp",
        "pub" => "pub",
        "loop" | "fluid" => "loop",
        "zip" | "7z" | "rar" | "tar" | "gz" | "tgz" | "bz2" | "cab" => "zip",
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "tif" | "tiff" | "heic" | "webp" => "photo",
        "svg" | "eps" | "ai" => "vector",
        "mp3" | "wav" | "wma" | "m4a" | "aac" | "flac" | "ogg" => "audio",
        "mp4" | "mov" | "avi" | "wmv" | "mkv" | "m4v" | "webm" => "video",
        "html" | "htm" | "mht" => "html",
        "xml" => "xml",
        "js" | "ts" | "py" | "rs" | "c" | "cpp" | "h" | "cs" | "java" | "json" | "css" | "sh" | "ps1" | "sql" | "go" | "rb" => "code",
        "eml" | "msg" => "email",
        "exe" | "msi" | "dll" | "bat" => "exe",
        "url" | "website" => "link",
        _ => "genericfile",
    };
    format!("https://res.public.onecdn.static.microsoft/assets/fluentui-resources/1.1.0/app-min/assets/item-types/24_1.5x/{kind}.png")
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
/// already there renamed, and its link goes in the body). Change location
/// puts it in another of your folders (`folder_id`, "root" for Files).
pub async fn upload_and_share(client: &super::client::TeamsClient, path: &std::path::Path, folder_id: &str) -> Result<Value> {
    let name = path.file_name().and_then(|n| n.to_str()).context("File has no name")?.to_string();
    let bytes = tokio::fs::read(path).await.with_context(|| format!("Can't read {}", path.display()))?;
    let seg = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>().replace('+', "%20");
    let target = match folder_id {
        "" => format!("/me/drive/root:/Attachments/{}:", seg(&name)),
        "root" => format!("/me/drive/root:/{}:", seg(&name)),
        id if is_drive_id(id) => format!("/me/drive/items/{id}:/{}:", seg(&name)),
        _ => bail!("Not a folder"),
    };
    let item: Value = client
        .graph_put_bytes(&format!("{target}/content?@microsoft.graph.conflictBehavior=rename"), bytes, "application/octet-stream")
        .await?
        .json()
        .await
        .context("Upload reply")?;
    let item_id = item.get("id").and_then(Value::as_str).context("Upload reply has no id")?;
    let drive_id = item.pointer("/parentReference/driveId").and_then(Value::as_str).context("Upload reply has no drive")?;
    let url = share_link(client, drive_id, item_id).await?;
    Ok(json!({ "url": url, "name": item.get("name").and_then(Value::as_str).unwrap_or(&name) }))
}

/// The Graphics pane's Emoji, Stock images and Stickers (Insert emoji,
/// images and stickers; Outlook's content picker, captured 2026-11-24):
/// Microsoft's content service,
/// `GET hubblecontent.osi.office.net/contentsvc/api/pivots?filter=pivotNames/any(p: p eq '<pivot>' )&search=…&top=…&app=5&tid=&secureurl=1`
/// (the search upper-cased, as Outlook sends it), pictures under
/// `cdn.hubblecontent.osi.office.net/<Path>`. An Emoji category is a search
/// for its name (200 at most), of which Outlook keeps Smilies' faces and
/// Hand gestures' hands ([`emoji_category_filter`]).
pub async fn graphics(pivot: &str, search: &str, top: u32, category: &str) -> Result<Value> {
    if !matches!(pivot, "Stock Images" | "Stickers" | "Emojis") {
        bail!("Not a pivot");
    }
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>().replace('+', "%20");
    let url = format!(
        "{HUBBLE}/contentsvc/api/pivots?filter={}&search={}&top={}&app=5&tid=&secureurl=1",
        enc(&format!("pivotNames/any(p: p eq '{pivot}' )")),
        enc(&search.to_uppercase()),
        top.clamp(1, 200)
    );
    let v = hubble_get(&url).await?;
    let mut items = graphics_from(&v);
    if pivot == "Emojis" {
        items = emoji_category_filter(items, category);
    }
    Ok(json!({ "pivot": pivot, "search": search, "items": items }))
}

const HUBBLE: &str = "https://hubblecontent.osi.office.net";
const HUBBLE_CDN: &str = "https://cdn.hubblecontent.osi.office.net/";

async fn hubble_get(url: &str) -> Result<Value> {
    Ok(reqwest::Client::new()
        .get(url)
        .header("user-agent", OWA_USER_AGENT)
        .header("accept", "application/json")
        .header("accept-language", "en-US")
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?)
}

/// Outlook's filters for two Emoji categories (English): Smilies keeps the
/// emoji described with "face", "smile" or "smiley", Hand gestures those
/// with "hand", "index", "thumb", "finger", "palm", "fist", "gesture",
/// "gesturing" or "tipping hand".
pub fn emoji_category_filter(items: Vec<Value>, category: &str) -> Vec<Value> {
    let words: &[&str] = match category {
        "Smilies" => &["face", "smile", "smiley"],
        "Hand gestures" => &["hand", "index", "thumb", "finger", "palm", "fist", "gesture", "gesturing", "tipping hand"],
        _ => return items,
    };
    items
        .into_iter()
        .filter(|i| {
            let d = i.get("description").and_then(Value::as_str).unwrap_or_default().to_lowercase();
            words.iter().any(|w| d.contains(w))
        })
        .collect()
}

/// A pivot's themes (`GET …/contentsvc/api/pivots/<pivot id>/themes`):
/// Stock images' category tiles (the empty Stock images tab shows each as
/// its picture with its name over a 50 % black veil; picking one searches
/// for its name).
pub async fn graphics_themes(kind: &str) -> Result<Value> {
    let id = match kind {
        "Stock Images" => "f8218404-63dd-4670-b0f5-f8b50674f963",
        "Emojis" => "84e04d41-3574-4764-a2d3-c24ae80c75eb",
        _ => bail!("Not a pivot"),
    };
    let v = hubble_get(&format!("{HUBBLE}/contentsvc/api/pivots/{id}/themes")).await?;
    Ok(json!({ "kind": kind, "themes": themes_from(&v) }))
}

/// A themes answer as `{id, name, thumb}`, the name capitalised (Outlook
/// shows and searches it so).
pub fn themes_from(v: &Value) -> Vec<Value> {
    v.as_array()
        .into_iter()
        .flatten()
        .filter_map(|t| {
            let name = t.get("NameWithLocale").and_then(Value::as_str).filter(|s| !s.is_empty()).or_else(|| t.get("Name").and_then(Value::as_str))?;
            let mut c = name.chars();
            let name = c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default();
            let thumb = t.pointer("/ThumbnailInfo/Small/Path").and_then(Value::as_str).map(|p| format!("{HUBBLE_CDN}{p}")).unwrap_or_default();
            Some(json!({ "id": t.get("Id").and_then(Value::as_str).unwrap_or_default(), "name": name, "thumb": thumb }))
        })
        .collect()
}

/// The items of a content-service answer: an emoji's glyph, or a picture's
/// address, its thumbnail and their sizes.
pub fn graphics_from(v: &Value) -> Vec<Value> {
    v.as_array()
        .into_iter()
        .flatten()
        .flat_map(|p| p.get("MicrosoftContents").and_then(Value::as_array).cloned().unwrap_or_default())
        .filter_map(|c| {
            let text = |k: &str| c.get(k).and_then(Value::as_str).filter(|s| !s.is_empty());
            let description = text("DescriptionWithLocale").or_else(|| text("Description")).unwrap_or_default();
            let id = text("Id").unwrap_or_default();
            if let Some(glyph) = text("Glyph") {
                return Some(json!({ "id": id, "glyph": glyph, "description": description }));
            }
            let path = text("Path")?;
            let thumb = c.pointer("/ThumbnailInfo/Medium/Path").and_then(Value::as_str).unwrap_or(path);
            let num = |p: &str| c.pointer(p).and_then(Value::as_i64).unwrap_or(0);
            Some(json!({
                "id": id,
                "description": description,
                "url": format!("{HUBBLE_CDN}{path}"),
                "thumb": format!("{HUBBLE_CDN}{thumb}"),
                "thumbWidth": num("/ThumbnailInfo/Medium/Width"),
                "thumbHeight": num("/ThumbnailInfo/Medium/Height"),
                "width": num("/Width"),
                "height": num("/Height"),
            }))
        })
        .collect()
}

/// A file as a `data:` address, as Outlook keeps an inserted stock image or
/// sticker in the body (`data:image/jpeg;base64,…`, a sticker's own PNG).
pub fn file_data_uri(path: &std::path::Path, mime: &str) -> Result<String> {
    use base64::Engine;
    let bytes = std::fs::read(path).with_context(|| format!("Can't read {}", path.display()))?;
    Ok(format!("data:{mime};base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes)))
}

/// A stock picture's local copy (shown in the body while editing).
pub async fn graphics_file(url: &str) -> Result<std::path::PathBuf> {
    if !url.starts_with(HUBBLE_CDN) {
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
    fn graphics_answers_as_outlook_reads_them() {
        let emoji = json!([{ "MicrosoftContents": [
            { "Id": "a", "Glyph": "😄", "Description": "Grinning face with smiling eyes" },
            { "Id": "b", "Glyph": "🎉", "Description": "Party popper" },
            { "Id": "c", "Glyph": "👍", "Description": "Thumbs up" }
        ] }]);
        let items = graphics_from(&emoji);
        assert_eq!(items[0]["glyph"], "😄");
        // Smilies keeps faces, Hand gestures hands; others keep all.
        assert_eq!(emoji_category_filter(items.clone(), "Smilies").len(), 1);
        assert_eq!(emoji_category_filter(items.clone(), "Hand gestures")[0]["id"], "c");
        assert_eq!(emoji_category_filter(items, "Objects").len(), 3);
        let stock = json!([{ "MicrosoftContents": [{ "Id": "p", "Path": "m365content/publish/p/1.jpg", "Width": 5760, "Height": 3840, "Description": "Skill",
            "ThumbnailInfo": { "Medium": { "Path": "m365content/publish/p/thumbnails/medium.jpg", "Width": 195, "Height": 130 } } }] }]);
        let p = &graphics_from(&stock)[0];
        assert_eq!(p["url"], "https://cdn.hubblecontent.osi.office.net/m365content/publish/p/1.jpg");
        assert_eq!(p["thumbHeight"], 130);
        let themes = themes_from(&json!([{ "Id": "t", "Name": "skill", "ThumbnailInfo": { "Small": { "Path": "m365content/publish/t/thumbnails/small.jpg" } } }]));
        assert_eq!(themes[0]["name"], "Skill");
        assert_eq!(themes[0]["thumb"], "https://cdn.hubblecontent.osi.office.net/m365content/publish/t/thumbnails/small.jpg");
    }

    #[test]
    fn intent_as_outlook_writes_it() {
        let d = |s: &str| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
        let days = [d("2026-11-24"), d("2026-11-25"), d("2026-11-26"), d("2026-11-27"), d("2026-11-30")];
        // As captured from Outlook's form (Morning and Midday picked).
        assert_eq!(
            intent_json(&days, &[], &[(0, 720), (720, 780)]),
            r#"{"IntentConstraint":{"ConstraintType":"AND","Constraints":[{"ConstraintType":"OR","Constraints":[{"FilterType":"Date","FilterValue":"2026-11-24..2026-11-27"},{"FilterType":"Date","FilterValue":"2026-11-30"}]},{"ConstraintType":"OR","Constraints":[{"FilterType":"TimeOfDay","FilterValue":"0..720"},{"FilterType":"TimeOfDay","FilterValue":"720..780"}]}]},"Version":1}"#
        );
        let (dd, ww, tt) = parse_intent(&intent_json(&days, &[], &[(0, 720), (720, 780)]));
        assert_eq!(dd.len(), 5);
        assert_eq!(dd[4], "2026-11-30");
        assert!(ww.is_empty());
        assert_eq!(tt, vec![(0, 720), (720, 780)]);
        // One filter of a kind goes alone.
        assert!(intent_json(&[d("2026-12-01")], &[], &[(780, 1440)]).contains(r#"[{"FilterType":"Date","FilterValue":"2026-12-01"},{"FilterType":"TimeOfDay","FilterValue":"780..1440"}]"#));
    }

    #[test]
    fn editor_settings_as_outlook_saves_them() {
        // No options yet: Outlook POSTs each (Grammar off and Capitalize 'I'
        // off, as captured).
        let opts = json!({ "autocorrect": true, "capitalizeI": false, "autoCapitalize": true, "spelling": true, "grammar": false });
        let w = editor_option_writes(&json!({ "options": [] }), &opts, "en-us");
        let paths: Vec<_> = w.iter().map(|(m, p, _)| format!("{m} {p}")).collect();
        assert_eq!(paths, ["POST ows/v1.0/OutlookOptions/Proofing", "POST ows/v1.0/OutlookOptions/TextPrediction", "POST ows/v1.0/OutlookOptions/AutoCorrect"]);
        let p = &w[0].2["options"];
        assert_eq!(p["feature"], 25);
        assert_eq!(p["grammarEnabled"], false);
        assert_eq!(p["proofingLocale"], "en-us");
        let over: Value = serde_json::from_str(p["overriddenOptions"].as_str().unwrap()).unwrap();
        assert_eq!(
            over["sharedUserSettings"]["editorPaneOverriddenSettings"],
            json!([{ "id": GRAMMAR_ID, "name": "Grammar", "value": "0", "languageId": "en-us" }])
        );
        assert_eq!(over["sharedUserSettings"]["editorServiceOverriddenSettings"].as_array().unwrap().len(), 3);
        assert_eq!(w[1].2["options"], json!({ "feature": 63, "isTextPredictionEnabled": false }));
        assert_eq!(w[2].2["options"], json!({ "feature": 56, "isAutoCorrectEnabled": true, "isAutoCapitalizationEnabled": true, "autoCapitalizeI": false }));
        // Existing options are PATCHed whole, the Grammar override replaced.
        let all = json!({ "options": [
            { "itemClass": "Proofing", "feature": 25, "id": "P", "createdDateTime": "x", "spellCheckEnabled": true, "grammarEnabled": false, "proofingLocale": "en-us", "overriddenOptions": over.to_string() },
            { "itemClass": "AutoCorrect", "feature": 56, "id": "A", "autoCapitalizeI": false, "isAutoCorrectEnabled": true, "isAutoCapitalizationEnabled": true },
            { "itemClass": "TextPrediction", "feature": 63, "id": "T", "isTextPredictionEnabled": false } ] });
        let back = editor_option_writes(&all, &json!({ "autocorrect": true, "capitalizeI": true, "autoCapitalize": true, "spelling": true, "grammar": true }), "en-us");
        assert!(back.iter().all(|(m, _, _)| *m == reqwest::Method::PATCH));
        let p = &back[0].2["options"];
        assert_eq!(p["id"], "P");
        assert!(p.get("createdDateTime").is_none());
        let over: Value = serde_json::from_str(p["overriddenOptions"].as_str().unwrap()).unwrap();
        assert_eq!(over["sharedUserSettings"]["editorPaneOverriddenSettings"][0]["value"], "1");
        assert_eq!(over["sharedUserSettings"]["editorPaneOverriddenSettings"].as_array().unwrap().len(), 1);
        assert_eq!(editor_options_from(&all)["capitalizeI"], false);
        assert_eq!(editor_options_from(&json!({}))["grammar"], true);
    }

    #[test]
    fn series_intent_as_outlook_writes_it() {
        // Captured from Outlook's form on a weekly Thursday series: Monday
        // taken off, Saturday added, Morning and Afternoon.
        let w: Vec<String> = ["Thursday", "Tuesday", "Wednesday", "Friday", "Saturday"].iter().map(|s| s.to_string()).collect();
        assert_eq!(
            intent_json(&[], &w, &[(0, 720), (780, 1440)]),
            r#"{"IntentConstraint":{"ConstraintType":"AND","Constraints":[{"ConstraintType":"OR","Constraints":[{"FilterType":"DayOfWeek","FilterValue":"Thursday"},{"FilterType":"DayOfWeek","FilterValue":"Tuesday"},{"FilterType":"DayOfWeek","FilterValue":"Wednesday"},{"FilterType":"DayOfWeek","FilterValue":"Friday"},{"FilterType":"DayOfWeek","FilterValue":"Saturday"}]},{"ConstraintType":"OR","Constraints":[{"FilterType":"TimeOfDay","FilterValue":"0..720"},{"FilterType":"TimeOfDay","FilterValue":"780..1440"}]}]},"Version":1}"#
        );
        let (dd, ww, tt) = parse_intent(&intent_json(&[], &w, &[(0, 720)]));
        assert!(dd.is_empty());
        assert_eq!(ww, w);
        assert_eq!(tt, vec![(0, 720)]);
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
