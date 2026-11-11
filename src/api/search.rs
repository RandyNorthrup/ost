//! Teams' search results page (Enter in the title bar's search; measured
//! on winpc 2026-11-10): Substrate's search service with the requests Teams
//! sends per tab. The bodies are Teams' own (src/api/search_requests/*.json,
//! `{QUERY}` and `{TZ}` filled in); the filters change their query strings
//! as Teams' do.

use anyhow::Result;

use super::find::{self, Found, Hit};

/// The page's tabs.
pub const TABS: [&str; 8] = ["all", "messages", "files", "people", "channels", "groupchats", "meetings", "images"];

fn template(tab: &str) -> Option<&'static str> {
    Some(match tab {
        "all" => include_str!("search_requests/all.json"),
        "messages" => include_str!("search_requests/messages.json"),
        "files" => include_str!("search_requests/files.json"),
        "people" => include_str!("search_requests/people.json"),
        "channels" => include_str!("search_requests/channels.json"),
        "groupchats" => include_str!("search_requests/groupchats.json"),
        "meetings" => include_str!("search_requests/meetings.json"),
        "images-messages" => include_str!("search_requests/images-messages.json"),
        "images-files" => include_str!("search_requests/images-files.json"),
        _ => return None,
    })
}

/// The page's filters.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct Filters {
    /// Type ▾ (Messages): "chat" or "channel".
    pub kind: String,
    /// In ▾: a chat, channel or team ("chat" / "channel" / "team") and its
    /// thread (and a channel's or team's group id).
    pub in_kind: String,
    pub in_thread: String,
    pub in_group: String,
    /// Person ▾: their address and object id; From (sent by them) or With.
    pub person_mail: String,
    pub person_oid: String,
    pub person_from: bool,
    /// Date ▾ (ISO UTC, start inclusive).
    pub start: String,
    pub end: String,
    /// More ▾: @mentions me, Has attachment (Hide apps & bots is the page's).
    pub mentions: bool,
    pub attachment: bool,
    /// File Type ▾ (Files): find::type_extensions' kinds.
    pub file_type: String,
}

const THREAD_TYPE: &str = "Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)";
const SOFT_DELETED: &str = "NOT (isClientSoftDeleted:TRUE)";

/// A Message request's query string, as Teams builds it: the date, More's
/// terms, In or Type, the soft-delete guard, then the person's address and
/// the keywords (the All tab joins the last two with AND).
pub fn message_query(keywords: &str, f: &Filters, my_oid: &str, all_tab: bool) -> String {
    let mut terms: Vec<String> = Vec::new();
    if !f.start.is_empty() && !f.end.is_empty() {
        terms.push(format!("sent >= {} AND sent < {}", f.start, f.end));
    }
    if f.attachment {
        terms.push("hasattachment:yes".into());
    }
    if f.mentions && !my_oid.is_empty() {
        terms.push(format!("mentions:{}", my_oid.replace('-', "").to_ascii_lowercase()));
    }
    match (f.in_kind.as_str(), f.kind.as_str()) {
        ("chat", _) if !f.in_thread.is_empty() => {
            terms.push(format!("clientthreadid:{}", f.in_thread));
            terms.push(format!("NOT ({THREAD_TYPE})"));
        }
        // (A channel: its thread only; the team goes in a filter term.)
        ("channel", _) if !f.in_thread.is_empty() => terms.push(format!("clientthreadid:{}", f.in_thread)),
        ("team", _) => terms.push(format!("({THREAD_TYPE})")),
        (_, "chat") => terms.push(format!("NOT ({THREAD_TYPE})")),
        (_, "channel") => terms.push(format!("({THREAD_TYPE})")),
        _ => {}
    }
    terms.push(SOFT_DELETED.into());
    let mut q = terms.join(" AND ");
    if !f.person_mail.is_empty() {
        q.push(' ');
        q.push_str(&f.person_mail);
    }
    if !keywords.is_empty() {
        q.push_str(if all_tab && f.person_mail.is_empty() { " AND " } else { " " });
        q.push_str(keywords);
    }
    q
}

/// A File request's query string: the date, the type, the person, then
/// the keywords (as Find in chat's Files).
pub fn file_query(keywords: &str, f: &Filters) -> String {
    let ff = find::Filters {
        files: true,
        start: f.start.clone(),
        end: f.end.clone(),
        from_mail: f.person_mail.clone(),
        file_type: f.file_type.clone(),
        ..Default::default()
    };
    find::query_string("", keywords, &ff, "")
}

/// Teams sends the Meetings tab's time zone by its Windows name.
pub fn windows_zone(iana: &str) -> &'static str {
    match iana {
        "America/Los_Angeles" | "America/Vancouver" | "America/Tijuana" => "Pacific Standard Time",
        "America/Denver" | "America/Edmonton" | "America/Boise" => "Mountain Standard Time",
        "America/Phoenix" => "US Mountain Standard Time",
        "America/Chicago" | "America/Winnipeg" | "America/Mexico_City" => "Central Standard Time",
        "America/New_York" | "America/Toronto" | "America/Detroit" => "Eastern Standard Time",
        "America/Anchorage" => "Alaskan Standard Time",
        "Pacific/Honolulu" => "Hawaiian Standard Time",
        "America/Halifax" => "Atlantic Standard Time",
        "America/Sao_Paulo" => "E. South America Standard Time",
        "Europe/London" | "Europe/Dublin" | "Europe/Lisbon" => "GMT Standard Time",
        "Europe/Berlin" | "Europe/Amsterdam" | "Europe/Rome" | "Europe/Stockholm" | "Europe/Vienna" | "Europe/Zurich" | "Europe/Oslo" => "W. Europe Standard Time",
        "Europe/Paris" | "Europe/Brussels" | "Europe/Madrid" | "Europe/Copenhagen" => "Romance Standard Time",
        "Europe/Warsaw" | "Europe/Prague" | "Europe/Budapest" => "Central European Standard Time",
        "Europe/Helsinki" | "Europe/Kyiv" | "Europe/Riga" | "Europe/Vilnius" | "Europe/Tallinn" => "FLE Standard Time",
        "Europe/Athens" | "Europe/Bucharest" => "GTB Standard Time",
        "Europe/Istanbul" => "Turkey Standard Time",
        "Europe/Moscow" => "Russian Standard Time",
        "Asia/Dubai" => "Arabian Standard Time",
        "Asia/Kolkata" | "Asia/Calcutta" => "India Standard Time",
        "Asia/Shanghai" | "Asia/Hong_Kong" => "China Standard Time",
        "Asia/Singapore" => "Singapore Standard Time",
        "Asia/Tokyo" => "Tokyo Standard Time",
        "Asia/Seoul" => "Korea Standard Time",
        "Australia/Sydney" | "Australia/Melbourne" => "AUS Eastern Standard Time",
        "Australia/Perth" => "W. Australia Standard Time",
        "Pacific/Auckland" => "New Zealand Standard Time",
        _ => "UTC",
    }
}

fn entity_requests(body: &mut serde_json::Value) -> Option<&mut Vec<serde_json::Value>> {
    let key = if body.get("EntityRequests").is_some() { "EntityRequests" } else { "entityRequests" };
    body.get_mut(key).and_then(|v| v.as_array_mut())
}

fn query_obj(r: &mut serde_json::Value) -> Option<&mut serde_json::Value> {
    let key = if r.get("Query").is_some() { "Query" } else { "query" };
    r.get_mut(key)
}

fn people_note(f: &Filters, tenant: &str) -> Option<serde_json::Value> {
    (!f.person_mail.is_empty()).then(|| {
        let mut p = serde_json::json!({ "type": "People", "text": f.person_mail, "userId": f.person_oid, "tenantId": tenant });
        if f.person_from {
            p["subtype"] = serde_json::json!(["Sharer"]);
        }
        p
    })
}

/// The request bodies for `tab` (Images sends two: messages and files).
#[allow(clippy::too_many_arguments)]
pub fn bodies(tab: &str, keywords: &str, f: &Filters, from: usize, timezone: &str, my_oid: &str, tenant: &str) -> Vec<serde_json::Value> {
    let names: Vec<&str> = if tab == "images" { vec!["images-messages", "images-files"] } else { vec![tab] };
    let quoted = |s: &str| serde_json::to_string(s).unwrap_or_default();
    let mut out = Vec::new();
    for name in names {
        let Some(t) = template(name) else { continue };
        // Placeholders sit inside JSON strings: fill them escaped.
        let text = t
            .replace("{QUERY}", quoted(keywords).trim_matches('"'))
            .replace("{TZ}", quoted(timezone).trim_matches('"'))
            .replace("{WINTZ}", windows_zone(timezone));
        let Ok(mut body) = serde_json::from_str::<serde_json::Value>(&text) else { continue };
        body["cvid"] = uuid::Uuid::new_v4().to_string().into();
        body["logicalId"] = uuid::Uuid::new_v4().to_string().into();
        let all_tab = tab == "all";
        if let Some(reqs) = entity_requests(&mut body) {
            for r in reqs.iter_mut() {
                let kind = r.get("entityType").or_else(|| r.get("EntityType")).and_then(|k| k.as_str()).unwrap_or_default().to_string();
                let qs = match kind.as_str() {
                    "Message" if name == "images-messages" => None,
                    "Message" => Some(message_query(keywords, f, my_oid, all_tab)),
                    "File" if name == "images-files" => None,
                    "File" => Some(file_query(keywords, f)),
                    _ => None,
                };
                if let Some(q) = query_obj(r) {
                    if let Some(qs) = qs {
                        let key = if q.get("QueryString").is_some() { "QueryString" } else { "queryString" };
                        q[key] = qs.into();
                    }
                    if matches!(kind.as_str(), "Message" | "File") {
                        if let Some(p) = people_note(f, tenant) {
                            q["queryAnnotations"] = serde_json::json!([p]);
                        }
                    }
                }
                if kind == "Message" && name != "images-messages" {
                    if matches!(f.in_kind.as_str(), "team" | "channel") && !f.in_group.is_empty() {
                        r["Filter"] = serde_json::json!({ "Term": { "GroupId": f.in_group } });
                    } else if f.in_thread.is_empty() && f.kind == "chat" {
                        r["Filter"] = serde_json::json!({ "Term": { "ConversationType": "OneToOne" } });
                    }
                    // (Type ▸ Channel sends no filter term, as Teams.)
                }
                if from > 0 {
                    let key = if r.get("From").is_some() { "From" } else { "from" };
                    r[key] = from.into();
                }
            }
        }
        if let Some(a) = body.get_mut("AnswerEntityRequests").and_then(|v| v.as_array_mut()) {
            for r in a {
                let key = if r.get("From").is_some() { "From" } else { "from" };
                r[key] = from.into();
            }
        }
        out.push(body);
    }
    out
}

/// A chat found (Group chats).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ChatHit {
    pub thread: String,
    pub name: String,
    pub thread_type: String,
    pub members: Vec<String>,
    pub member_mris: Vec<String>,
    pub member_count: u64,
    pub last_message: String,
}

/// A channel or team found.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ChannelHit {
    pub thread: String,
    pub name: String,
    pub team: String,
    pub group: String,
    pub channel_type: String,
}

/// A person found.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct PersonHit {
    pub mri: String,
    pub name: String,
    pub mail: String,
    pub title: String,
    pub department: String,
    pub company: String,
}

/// A meeting found (the Event answer).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct EventHit {
    pub id: String,
    pub subject: String,
    pub start: String,
    pub end: String,
    pub location: String,
    pub organizer: String,
    pub is_organizer: bool,
    pub cancelled: bool,
    pub join_url: String,
    pub web_link: String,
}

/// A page of results.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Page {
    /// The sections in Teams' order (All): "messages", "groupchats",
    /// "channels", "files", "people", "meetings".
    pub order: Vec<String>,
    pub terms: Vec<String>,
    pub messages: Found,
    pub files: Found,
    pub images: Found,
    pub chats: Vec<ChatHit>,
    pub chats_total: u64,
    pub channels: Vec<ChannelHit>,
    pub channels_total: u64,
    pub people: Vec<PersonHit>,
    pub people_total: u64,
    pub events: Vec<EventHit>,
    pub events_total: u64,
}

fn s(v: &serde_json::Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn section(entity: &str) -> &'static str {
    match entity {
        "Message" => "messages",
        "Chat" => "groupchats",
        "TeamsChannel" => "channels",
        "File" => "files",
        "People" => "people",
        "Event" => "meetings",
        _ => "",
    }
}

/// Merge one reply into `page` (`images` marks the Images tab's replies).
pub fn read_reply(page: &mut Page, reply: &serde_json::Value, images: bool) {
    if page.terms.is_empty() {
        page.terms = reply["SearchTerms"].as_array().into_iter().flatten().filter_map(|t| t.as_str().map(str::to_string)).collect();
    }
    for set in reply["EntitySets"].as_array().into_iter().flatten() {
        let kind = s(&set["EntityType"]);
        let one = serde_json::json!({ "EntitySets": [set] });
        let rs = &set["ResultSets"][0];
        let total = rs["Total"].as_u64().unwrap_or_default();
        match kind.as_str() {
            "Message" | "File" if images => {
                let f = find::found_from(&one);
                page.images.total += f.total;
                page.images.more |= f.more;
                page.images.hits.extend(f.hits);
            }
            "Message" => page.messages = find::found_from(&one),
            "File" => page.files = find::found_from(&one),
            "Chat" => {
                page.chats_total = total;
                page.chats = rs["Results"].as_array().into_iter().flatten().map(|r| {
                    let src = &r["Source"];
                    ChatHit {
                        thread: s(&src["ThreadId"]),
                        name: s(&src["Name"]),
                        thread_type: s(&src["ThreadType"]),
                        members: src["Members"].as_array().into_iter().flatten().filter_map(|m| m.as_str().map(str::to_string)).collect(),
                        member_mris: src["ChatMembers"].as_array().into_iter().flatten().map(|m| s(&m["MRI"])).collect(),
                        member_count: src["TotalChatMembersCount"].as_u64().unwrap_or_default(),
                        last_message: s(&src["LastMessageTime"]),
                    }
                }).collect();
            }
            "TeamsChannel" => {
                page.channels_total = total;
                page.channels = rs["Results"].as_array().into_iter().flatten().map(|r| {
                    let src = &r["Source"];
                    ChannelHit { thread: s(&src["ThreadId"]), name: s(&src["Name"]), team: s(&src["TeamName"]), group: s(&src["GroupId"]), channel_type: s(&src["ChannelType"]) }
                }).collect();
            }
            "People" => {
                page.people_total = total;
                page.people = rs["Results"].as_array().into_iter().flatten().map(|r| {
                    let src = &r["Source"];
                    let mail = src["EmailAddresses"].as_array().and_then(|a| a.first()).map(s).filter(|m| !m.is_empty()).unwrap_or_else(|| s(&src["UserPrincipalName"]));
                    PersonHit { mri: s(&src["MRI"]), name: s(&src["DisplayName"]), mail, title: s(&src["JobTitle"]), department: s(&src["Department"]), company: s(&src["CompanyName"]) }
                }).collect();
            }
            _ => {}
        }
    }
    for set in reply["AnswerEntitySets"].as_array().into_iter().flatten() {
        let rs = &set["ResultSets"][0];
        let events: Vec<EventHit> = rs["Results"].as_array().into_iter().flatten().filter(|r| r["Source"].get("Subject").is_some()).map(|r| {
            let src = &r["Source"];
            EventHit {
                id: s(&src["EventId"]["Id"]),
                subject: s(&src["Subject"]),
                start: s(&src["Start"]),
                end: s(&src["End"]),
                location: s(&src["Location"]),
                organizer: s(&src["OrganizerName"]),
                is_organizer: src["IsOrganizer"].as_bool().unwrap_or_default(),
                cancelled: src["IsCancelled"].as_bool().unwrap_or_default(),
                join_url: [&src["OnlineMeeting"]["JoinUrl"], &src["ParsedBodyInfo"]["OnlineMeetingUrl"]].iter().map(|v| s(v)).find(|u| !u.is_empty()).unwrap_or_default(),
                web_link: s(&src["WebLink"]),
            }
        }).collect();
        if !events.is_empty() {
            page.events_total = rs["Total"].as_u64().unwrap_or(events.len() as u64).max(events.len() as u64);
            page.events = events;
        }
    }
    // The All page's order: the ranking's cards, else the sets' positions.
    if page.order.is_empty() {
        let mut order: Vec<String> = reply["WholePageRankings"][0]["Cards"]
            .as_array()
            .into_iter()
            .flatten()
            .flat_map(|c| c["EntityCards"].as_array().cloned().unwrap_or_default())
            .map(|e| section(e["EntityType"].as_str().unwrap_or_default()).to_string())
            .filter(|n| !n.is_empty())
            .collect();
        if order.is_empty() {
            let mut sets: Vec<(u64, String)> = reply["EntitySets"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|e| (e["Position"].as_u64().unwrap_or(99), section(e["EntityType"].as_str().unwrap_or_default()).to_string()))
                .filter(|(_, n)| !n.is_empty())
                .collect();
            sets.sort();
            order = sets.into_iter().map(|(_, n)| n).collect();
        }
        order.dedup();
        page.order = order;
    }
}

/// In ▾'s suggestions: Substrate's suggestions for chats, channels and
/// teams (Teams' peoplepicker.newChat scenario); the raw reply.
pub async fn in_suggestions(keyword: &str) -> Result<serde_json::Value> {
    let token = crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let body = serde_json::json!({
        "EntityRequests": [
            { "Query": { "QueryString": keyword }, "EntityType": "Chat", "Size": 20 },
            { "Query": { "QueryString": keyword }, "EntityType": "Channel", "Size": 20, "Filter": { "Or": [{ "Term": { "ChannelType": "Standard" } }, { "Term": { "ChannelType": "Shared" } }] } },
            { "Query": { "QueryString": keyword }, "EntityType": "Team", "Size": 20 }
        ],
        "Scenario": { "Name": "peoplepicker.newChat" },
        "Cvid": uuid::Uuid::new_v4().to_string(),
        "AppName": "Microsoft Teams",
        "LogicalId": uuid::Uuid::new_v4().to_string(),
    });
    let v = reqwest::Client::new()
        .post("https://substrate.office.com/search/api/v1/suggestions?scenario=peoplepicker.newChat")
        .bearer_auth(token)
        .json(&body)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(v)
}

/// Search `tab` as Teams' results page does.
#[allow(clippy::too_many_arguments)]
pub async fn search(
    client: &super::client::TeamsClient,
    tab: &str,
    keywords: &str,
    f: &Filters,
    from: usize,
    timezone: &str,
    my_oid: &str,
    tenant: &str,
) -> Result<Page> {
    let anchor = if my_oid.is_empty() || tenant.is_empty() { String::new() } else { format!("OID:{my_oid}@{tenant}") };
    let mut page = Page::default();
    for body in bodies(tab, keywords, f, from, timezone, my_oid, tenant) {
        let reply = find::search_raw(&body, &anchor).await?;
        read_reply(&mut page, &reply, tab == "images");
    }
    // Rows show whole messages (the service cuts its summaries short).
    fill_by_thread(client, &mut page.messages).await;
    fill_by_thread(client, &mut page.images).await;
    Ok(page)
}

/// Read each result's message from its own conversation (results span
/// chats and channels).
async fn fill_by_thread(client: &super::client::TeamsClient, found: &mut Found) {
    use futures::StreamExt;
    let jobs: Vec<(usize, String, String)> = found
        .hits
        .iter()
        .enumerate()
        .filter(|(_, h)| !h.id.is_empty() && !h.thread.is_empty() && h.file_name.is_empty())
        .map(|(i, h)| (i, h.thread.clone(), h.id.clone()))
        .collect();
    type Read = (String, String, Option<(String, String)>);
    let read: Vec<(usize, Option<Read>)> = futures::stream::iter(jobs)
        .map(|(i, thread, id)| async move {
            let m = super::messages::read_message(client, &thread, &id).await.ok();
            (i, m.map(|m| (find::row_text(&m), m.subject.clone(), m.images.first().map(|im| (im.id.clone(), im.url.clone())))))
        })
        .buffer_unordered(6)
        .collect()
        .await;
    for (i, r) in read {
        let Some((text, subject, image)) = r else { continue };
        let h: &mut Hit = &mut found.hits[i];
        if let Some((id, url)) = image {
            h.image_id = id;
            h.image_ams = url;
        }
        if !subject.is_empty() {
            h.text = if text.is_empty() { subject.clone() } else { format!("{subject} - {text}") };
            h.subject = subject;
        } else if !text.is_empty() {
            h.text = text;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_tab_has_teams_request() {
        for tab in TABS {
            let b = bodies(tab, "OST test", &Filters::default(), 0, "America/Los_Angeles", "o", "t");
            assert!(!b.is_empty(), "{tab}");
            let text = serde_json::to_string(&b).unwrap();
            assert!(!text.contains("{QUERY}") && !text.contains("{TZ}") && !text.contains("{WINTZ}"), "{tab}");
        }
        assert_eq!(bodies("images", "x", &Filters::default(), 0, "UTC", "", "").len(), 2);
        let m = bodies("meetings", "x", &Filters::default(), 0, "America/Los_Angeles", "", "");
        assert_eq!(m[0]["timezone"], "Pacific Standard Time");
    }

    #[test]
    fn message_filters_are_teams_terms() {
        // As Teams sent them (Messages tab, "OST test").
        let none = Filters::default();
        assert_eq!(message_query("OST test", &none, "", false), "NOT (isClientSoftDeleted:TRUE) OST test");
        assert_eq!(message_query("OST test", &none, "", true), "NOT (isClientSoftDeleted:TRUE) AND OST test");
        let chat = Filters { kind: "chat".into(), ..Default::default() };
        assert_eq!(
            message_query("OST test", &chat, "", false),
            "NOT (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        let b = bodies("messages", "OST test", &chat, 0, "UTC", "", "");
        assert_eq!(b[0]["entityRequests"][0]["Filter"], serde_json::json!({"Term": {"ConversationType": "OneToOne"}}));
        // Type ▸ Channel: the thread-type clause only, no filter term.
        let chan = Filters { kind: "channel".into(), ..Default::default() };
        assert_eq!(
            message_query("OST test", &chan, "", false),
            "(Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        assert!(bodies("messages", "OST test", &chan, 0, "UTC", "", "")[0]["entityRequests"][0].get("Filter").is_none());
        let mention = Filters { mentions: true, ..Default::default() };
        assert_eq!(message_query("OST test", &mention, "4287e791-1b98-4963-8b94-281c50472683", false), "mentions:4287e7911b9849638b94281c50472683 AND NOT (isClientSoftDeleted:TRUE) OST test");
        let att = Filters { attachment: true, ..Default::default() };
        assert_eq!(message_query("OST test", &att, "", false), "hasattachment:yes AND NOT (isClientSoftDeleted:TRUE) OST test");
        let inchat = Filters { in_kind: "chat".into(), in_thread: "19:ef2@thread.v2".into(), ..Default::default() };
        assert_eq!(
            message_query("OST test", &inchat, "", false),
            "clientthreadid:19:ef2@thread.v2 AND NOT (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        // In ▸ a channel (as Teams sent it).
        let inchan = Filters { in_kind: "channel".into(), in_thread: "19:7826@thread.tacv2".into(), in_group: "1fac3ae3".into(), ..Default::default() };
        assert_eq!(message_query("OST test", &inchan, "", false), "clientthreadid:19:7826@thread.tacv2 AND NOT (isClientSoftDeleted:TRUE) OST test");
        assert_eq!(bodies("messages", "OST test", &inchan, 0, "UTC", "", "")[0]["entityRequests"][0]["Filter"], serde_json::json!({"Term": {"GroupId": "1fac3ae3"}}));
        let from = Filters { person_mail: "a@b.c".into(), person_oid: "o1".into(), person_from: true, ..Default::default() };
        assert_eq!(message_query("OST test", &from, "", false), "NOT (isClientSoftDeleted:TRUE) a@b.c OST test");
        let b = bodies("messages", "OST test", &from, 0, "UTC", "", "t1");
        assert_eq!(
            b[0]["entityRequests"][0]["query"]["queryAnnotations"],
            serde_json::json!([{"type": "People", "text": "a@b.c", "userId": "o1", "tenantId": "t1", "subtype": ["Sharer"]}])
        );
    }

    #[test]
    fn replies_fill_the_page_in_teams_order() {
        let reply = serde_json::json!({
            "SearchTerms": ["ost", "test"],
            "EntitySets": [
                {"EntityType": "Chat", "Position": 2, "ResultSets": [{"Total": 2, "Results": [{"Source": {"Name": "OST group test", "ThreadId": "19:a@thread.v2", "ThreadType": "Chat", "Members": ["R N", "OST Test 1"], "TotalChatMembersCount": 2, "LastMessageTime": "2026-11-09T11:32:21Z", "ChatMembers": [{"MRI": "8:orgid:x"}]}}]}]},
                {"EntityType": "TeamsChannel", "Position": 3, "ResultSets": [{"Total": 1, "Results": [{"Source": {"Name": "OST test channel", "ThreadId": "19:c@thread.tacv2", "TeamName": "OST Test Team", "GroupId": "g"}}]}]}
            ],
            "AnswerEntitySets": [{"ResultSets": [{"Results": [{"Source": {"Subject": "OST calendar test", "Start": "2026-11-06T23:00:00Z", "End": "2026-11-06T23:30:00Z", "IsOrganizer": true, "OnlineMeeting": {"JoinUrl": "https://teams/l/meetup-join/x"}, "EventId": {"Id": "e1"}}}]}]}],
            "WholePageRankings": [{"Cards": [{"EntityCards": [{"EntityType": "Message"}, {"EntityType": "Chat"}, {"EntityType": "TeamsChannel"}, {"EntityType": "File"}, {"EntityType": "Event"}]}]}]
        });
        let mut p = Page::default();
        read_reply(&mut p, &reply, false);
        assert_eq!(p.order, ["messages", "groupchats", "channels", "files", "meetings"]);
        assert_eq!(p.terms, ["ost", "test"]);
        assert_eq!((p.chats[0].name.as_str(), p.chats[0].member_count), ("OST group test", 2));
        assert_eq!(p.channels[0].team, "OST Test Team");
        assert_eq!(p.events[0].join_url, "https://teams/l/meetup-join/x");
        assert!(p.events[0].is_organizer);
    }
}
