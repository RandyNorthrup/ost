//! The title bar search's suggestions, as Teams desktop shows them under
//! the box (captured on winpc 2026-11-27, Teams 26304): Substrate's
//! suggestions service, scenario "powerbar".
//! - Focused with nothing typed: `GET …/suggestions?scenario=powerbar&query=`
//!   (its best matches are the "Suggestions" section; the "People" row is
//!   Teams' top-N people, [`super::search::zero_state_people`]).
//! - As you type: `POST …/suggestions?scenario=powerbar&setflight=…` with
//!   people, files, chats, teams, channels, text, messages, events and apps.
//!
//! [`arrange`] puts a reply into Teams' groups: the best matches first ("Top
//! hits", LayoutHints.BestMatchSuggestions in order), then each group in the
//! ECS autosuggest.suggestionsGroupOrder (Recent messages, People, Files,
//! Channels, Teams, Group Chats, Meetings, Recent images) without what the
//! top hits already show. The texts are Teams' (its suggestion converters).

use anyhow::{Context, Result};
use serde_json::{Value, json};

const URL: &str = "https://substrate.office.com/search/api/v1/suggestions";
const SCOPE: &str = "https://substrate.office.com/.default";
/// The flights Teams' powerbar sends (x-client-flights).
const FLIGHTS: &str = "IncludeHistoryInBMDynamic,PeopleKeywordAsTextSuggestion,TDPeopleSynthetic,syntvar2,EnableKql,TMEUnscopedCountTD5,EnableSelfSuggestion";
/// And the typed request's setflight.
const SET_FLIGHT: &str = "EnableMessageImageSearch,EnableTeamsChannelDomainPowerbar";

/// ECS autosuggest.unscopedDomainConfig: five recent messages.
pub const MESSAGES: usize = 5;
/// Recent images in unscoped suggestions (Teams' constant).
pub const IMAGES: usize = 6;
/// Message identifiers: at most this many icons before the date.
const ICONS: usize = 2;

/// Who is searching.
#[derive(Debug, Clone, Default)]
pub struct Me {
    pub oid: String,
    pub mri: String,
    pub mail: String,
    pub name: String,
}

/// The typed request's body, as Teams' powerbar sends it.
pub fn typed_body(query: &str, cvid: &str, logical_id: &str) -> Value {
    let q = json!({ "QueryString": query, "NormalizedQueryString": query });
    json!({
        "EntityRequests": [
            people_request(json!({ "QueryString": query, "DisplayQueryString": query, "NormalizedQueryString": query }), 5, true),
            { "Query": q, "EntityType": "File", "Size": 3 },
            { "Query": q, "EntityType": "Chat", "Size": 5 },
            { "Query": q, "EntityType": "Team", "Size": 3 },
            { "Query": q, "EntityType": "Channel", "Size": 4, "Filter": channel_filter() },
            { "Query": q, "EntityType": "Text", "Size": 2 },
            { "Query": q, "EntityType": "Message", "Size": 11 },
            { "Query": q, "EntityType": "Event", "Size": 3 },
            { "Query": q, "EntityType": "App", "Size": 5, "Filter": { "Or": [{ "Term": { "AppType": "Catalog" } }] }, "Provenances": ["Mailbox", "Directory"], "From": 0 }
        ],
        "Scenario": { "Name": "powerbar", "Dimensions": [{ "DimensionName": "QueryType", "DimensionValue": "PeopleCentricSearch" }] },
        "Cvid": cvid,
        "AppName": "Microsoft Teams",
        "LogicalId": logical_id,
        "dataSource": "personScoped",
    })
}

/// The fields Teams asks for of each person.
const PEOPLE_FIELDS: [&str; 17] = [
    "Id",
    "MRI",
    "DisplayName",
    "EmailAddresses",
    "PeopleType",
    "PeopleSubtype",
    "Phones",
    "UserPrincipalName",
    "GivenName",
    "Surname",
    "Cid",
    "CompanyName",
    "JobTitle",
    "ImAddress",
    "ExternalDirectoryObjectId",
    "ConcatenatedId",
    "Department",
];

/// A People request: people and guests in the directory, with your
/// personal contacts unless it's a KQL picker's (from:, in:).
fn people_request(query: Value, size: u64, contacts: bool) -> Value {
    let mut sub = vec![
        json!({ "Term": { "PeopleSubtype": "OrganizationUser" } }),
        json!({ "Term": { "PeopleSubtype": "MTOUser" } }),
    ];
    if contacts {
        sub.push(json!({ "Term": { "PeopleSubtype": "PersonalContact" } }));
    }
    sub.push(json!({ "Term": { "PeopleSubtype": "Guest" } }));
    json!({
        "Query": query, "EntityType": "People", "Size": size, "Fields": PEOPLE_FIELDS,
        "Filter": { "And": [
            { "Or": [{ "Term": { "PeopleType": "Person" } }, { "Term": { "PeopleType": "Other" } }] },
            { "Or": sub },
            { "Or": [{ "Term": { "Flags": "NonHidden" } }] }
        ] },
        "Provenances": ["Mailbox", "Directory"], "From": 0
    })
}

/// Standard and shared channels (private ones aren't suggested).
fn channel_filter() -> Value {
    json!({ "Or": [{ "Term": { "ChannelType": "Standard" } }, { "Term": { "ChannelType": "Shared" } }] })
}

/// Ask the suggestions service, with Teams' headers: the zero-query GET
/// for an empty `query`, else the typed POST.
pub async fn fetch(query: &str, me: &Me, tenant: &str) -> Result<Value> {
    let (cvid, logical) = (
        uuid::Uuid::new_v4().to_string(),
        uuid::Uuid::new_v4().to_string(),
    );
    if query.trim().is_empty() {
        send(
            &format!("{URL}?scenario=powerbar&query=&cvid={cvid}&logicalId={logical}"),
            None,
            me,
            tenant,
        )
        .await
    } else {
        send(
            &format!("{URL}?scenario=powerbar&setflight={SET_FLIGHT}"),
            Some(typed_body(query, &cvid, &logical)),
            me,
            tenant,
        )
        .await
    }
}

/// One request to the suggestions service (a POST when there's a body).
async fn send(url: &str, body: Option<Value>, me: &Me, tenant: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for(SCOPE)
        .await
        .context("Suggestions token")?;
    let request_id = uuid::Uuid::new_v4().to_string();
    let client = reqwest::Client::new();
    let mut req = match body {
        None => client.get(url),
        Some(b) => client.post(url).json(&b),
    };
    req = req
        .bearer_auth(token)
        .header(reqwest::header::USER_AGENT, super::client::TEAMS_WEB_UA)
        .header("Referer", "https://teams.microsoft.com/")
        .header("x-client-flights", FLIGHTS)
        .header("x-client-version", "T2.1")
        .header("x-cafelatencyheaderenabled", "1")
        .header("x-client-localtime", crate::clock::now_iso_ms())
        .header("client-request-id", &request_id)
        .header("clientrequestid", &request_id)
        .header("x-ms-request-id", &request_id)
        .header("content-type", "application/json");
    if !me.oid.is_empty() && !tenant.is_empty() {
        req = req.header("x-anchormailbox", format!("Oid:{}@{tenant}", me.oid));
    }
    let resp = req.send().await.context("Suggestions request")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(
        status.is_success(),
        "Suggestions failed ({status}): {}",
        text.chars().take(300).collect::<String>()
    );
    serde_json::from_str(&text).context("Suggestions reply")
}

/// Names for people the service names only by their Teams id: personal
/// (Teams free, `8:live:`) accounts, by MRI (lowercase), as
/// `directory::tfl_profiles` finds them (TASK-0376).
pub type Names = std::collections::HashMap<String, String>;

/// The `8:live:` people a reply names only by their id (a message's
/// `ToPreview`, a chat's members): who to look up for [`Names`].
pub fn unnamed_people(reply: &Value) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        for r in g["Suggestions"].as_array().into_iter().flatten() {
            let people = r["ToPreview"]
                .as_array()
                .into_iter()
                .flatten()
                .chain(r["ChatMembers"].as_array().into_iter().flatten())
                .chain(r["MatchingMembers"].as_array().into_iter().flatten());
            for p in people {
                let name = s(&p["DisplayName"]);
                let mri = s(&p["MRI"]);
                for m in [name.as_str(), mri.as_str()] {
                    if crate::identity::is_consumer_mri(m)
                        && (name.is_empty() || name == m)
                        && !out.iter().any(|o| o.eq_ignore_ascii_case(m))
                    {
                        out.push(m.to_string());
                    }
                }
            }
        }
    }
    out
}

/// A person's name in a reply: their DisplayName, or the name [`Names`]
/// has for a personal account the service names by its id.
fn display_name(p: &Value, names: &Names) -> String {
    let name = s(&p["DisplayName"]);
    let mri = s(&p["MRI"]);
    let key = if crate::identity::is_consumer_mri(&name) {
        name.clone()
    } else if name.is_empty() {
        mri
    } else {
        return name;
    };
    names
        .get(&key.to_ascii_lowercase())
        .cloned()
        .unwrap_or(name)
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn first_name(name: &str) -> String {
    name.split(' ').next().unwrap_or_default().to_string()
}

/// Teams' list of names in a line (its people formatter, en-us): as many
/// as fit in 24 characters, ", " between; "+n" for the rest. All of them
/// fitting, two or more read as a list ("A and B", "A, B, and C") when
/// that still fits in 26.
pub fn join_names(names: &[String], count: usize) -> String {
    if names.is_empty() {
        return String::new();
    }
    let mut line = names[0].clone();
    let mut shown = 1;
    while shown < names.len() && line.chars().count() + names[shown].chars().count() <= 24 {
        line = format!("{line}, {}", names[shown]);
        shown += 1;
    }
    let mut rest = if shown < count {
        Some(count - shown + 1)
    } else {
        None
    };
    if rest.is_none() && shown > 1 {
        let list = names[..shown].to_vec();
        let spoken = match list.len() {
            2 => format!("{} and {}", list[0], list[1]),
            n => format!("{}, and {}", list[..n - 1].join(", "), list[n - 1]),
        };
        if spoken.chars().count() <= 26 {
            line = spoken;
        } else {
            line = list[..list.len() - 1].join(", ");
            rest = Some(2);
        }
    }
    match rest {
        Some(n) => format!("{line}, +{n}"),
        None => line,
    }
}

fn person(r: &Value, me: &Me) -> Option<Value> {
    let mut items = super::search::parse_recipients(
        &json!({ "Groups": [{ "Type": "People", "Suggestions": [r] }] }),
        &me.oid,
    );
    let mut p = items.pop()?;
    p["mri"] = json!(format!("8:orgid:{}", s(&p["oid"])));
    Some(p)
}

/// A chat: its name, or its members' first names (you left out); a named
/// chat's members under it. Meeting chats have Teams' calendar picture.
fn chat(r: &Value, me: &Me, names: &Names) -> Value {
    let total = r["TotalChatMembersCount"].as_u64().unwrap_or(0) as usize;
    let people: Vec<String> = r["MatchingMembers"]
        .as_array()
        .into_iter()
        .flatten()
        .chain(r["ChatMembers"].as_array().into_iter().flatten())
        .filter(|m| {
            !m["MRI"]
                .as_str()
                .unwrap_or_default()
                .eq_ignore_ascii_case(&me.mri)
        })
        .map(|m| display_name(m, names))
        .filter(|n| !n.is_empty())
        .map(|n| first_name(&n))
        .collect();
    let members = join_names(&people, total.saturating_sub(1));
    let name = s(&r["Name"]);
    let (title, sub) = if name.is_empty() {
        (members, String::new())
    } else {
        (name, members)
    };
    json!({
        "kind": "chat", "thread": s(&r["ThreadId"]), "title": title, "sub": sub,
        "meeting": r["ThreadType"] == "Meeting", "named": !s(&r["Name"]).is_empty(),
    })
}

fn team(r: &Value) -> Value {
    json!({ "kind": "team", "thread": s(&r["ThreadId"]), "group": s(&r["GroupId"]), "title": s(&r["Name"]) })
}

fn channel(r: &Value) -> Value {
    json!({
        "kind": "channel", "thread": s(&r["ThreadId"]), "group": s(&r["GroupId"]),
        "title": s(&r["Name"]), "sub": s(&r["TeamName"]), "ctype": s(&r["ChannelType"]),
    })
}

/// The folder a channel file is in (the path segment after the library).
fn channel_folder(url: &str) -> String {
    let path = url.split('?').next().unwrap_or_default();
    let mut parts = path
        .split('/')
        .skip_while(|p| *p != "Shared%20Documents" && *p != "Shared Documents");
    parts.next();
    parts
        .next()
        .map(|f| f.replace("%20", " "))
        .unwrap_or_default()
}

/// A file: "Created by", "Shared by" (a file shared with you, or found by
/// who sent it) or a channel file's "Team > Folder".
fn file(r: &Value) -> Value {
    let ext = s(&r["FileExtension"]).to_ascii_lowercase();
    let author = s(&r["Author"]);
    let hits: Vec<String> = r["PropertyHits"]
        .as_array()
        .into_iter()
        .flatten()
        .map(s)
        .collect();
    let has = |h: &str| hits.iter().any(|x| x == h);
    let sharer = r["From"]["EmailAddress"]["Name"]
        .as_str()
        .or(r["From"]["EmailAddress"]["Address"].as_str())
        .unwrap_or_default()
        .to_string();
    let mut sub = if author.is_empty() {
        String::new()
    } else {
        crate::i18n::fill(
            &crate::i18n::tr_id("Created by %1", "autosuggest:k5emj2apv"),
            &[&author],
        )
    };
    if s(&r["UserRelationshipType"]).eq_ignore_ascii_case("none")
        || has("EmailSenderName")
        || has("EmailSenderAddress")
    {
        if !sharer.is_empty() {
            let line =
                if s(&r["SpoUniqueId"]).is_empty() && r["FileSourceType"] == "ClassicAttachment" {
                    crate::i18n::tr_id("Shared by %1 in Outlook", "autosuggest:k21eqtz6m")
                } else {
                    crate::i18n::tr_id("Shared by %1", "autosuggest:kjk5uv96")
                };
            sub = crate::i18n::fill(&line, &[&sharer]);
        }
    } else if r["FileSourceType"] == "SharepointOnline" && !has("Author") && !has("AuthorEmail") {
        let folder = channel_folder(&s(&r["AccessUrl"]));
        let site = s(&r["SourceTitle"]);
        if !folder.is_empty() && !site.is_empty() {
            sub = format!("{site} > {folder}");
        }
    }
    // Loop and Fluid open their reader address.
    let url = if matches!(ext.as_str(), "loop" | "fluid")
        && r["AlternateAccessUrlType"] == "ReaderUrl"
        && !s(&r["AlternateAccessUrl"]).is_empty()
    {
        s(&r["AlternateAccessUrl"])
    } else {
        s(&r["AccessUrl"])
    };
    json!({
        "kind": "file", "id": s(&r["SpoUniqueId"]), "title": s(&r["FileName"]), "ext": ext, "sub": sub, "url": url,
    })
}

/// A meeting: who invited whom (Teams' attendee line: you as the
/// organiser, or the organiser's first name; attendees matching the query
/// first, two at most, then "+n others").
fn event(r: &Value, query: &str, me: &Me) -> Value {
    let props: Value = serde_json::from_str(&s(&r["SkypeTeamsProperties"])).unwrap_or_default();
    let organizer_mail = s(&r["OrganizerAddress"]);
    let organizer = first_name(&s(&r["OrganizerName"]));
    let attendees: Vec<(String, String)> = r["Attendees"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|a| {
            (
                s(&a["EmailAddress"]["Address"]),
                s(&a["EmailAddress"]["Name"]),
            )
        })
        .collect();
    let mine = |m: &str| !me.mail.is_empty() && m.eq_ignore_ascii_case(&me.mail);
    let organizing = mine(&organizer_mail);
    let invited = attendees.iter().any(|(m, _)| mine(m));
    let others: Vec<&(String, String)> = attendees
        .iter()
        .filter(|(m, _)| !mine(m) && !m.eq_ignore_ascii_case(&organizer_mail))
        .collect();
    let words: Vec<String> = query
        .split(' ')
        .filter(|w| w.chars().count() >= 2)
        .map(str::to_lowercase)
        .collect();
    let mut shown: Vec<String> = others
        .iter()
        .filter(|(_, n)| words.iter().any(|w| n.to_lowercase().contains(w)))
        .map(|(_, n)| n.clone())
        .collect();
    let room = 2usize.saturating_sub(shown.len());
    let rest: Vec<String> = others
        .iter()
        .filter(|(_, n)| !shown.contains(n))
        .take(room)
        .map(|(_, n)| n.clone())
        .collect();
    shown.extend(rest);
    let count = r["NumberOfAttendees"].as_u64().unwrap_or(0) as usize;
    let attendee_line = if others.is_empty() {
        String::new()
    } else {
        let more = count.saturating_sub(shown.len());
        let names = shown
            .iter()
            .map(|n| first_name(n))
            .collect::<Vec<_>>()
            .join(", ");
        if more > 0 {
            names
                + &crate::i18n::fill(
                    &crate::i18n::tr_id(" +%1 others", "autosuggest:k7zypmt6g"),
                    &[&more.to_string()],
                )
        } else {
            names
        }
    };
    let who = if organizing {
        crate::i18n::tr_id("You invited ", "autosuggest:k25rza2tf") + &attendee_line
    } else if invited {
        let head = crate::i18n::fill(
            &crate::i18n::tr_id("%1 invited you", "autosuggest:kd4s7sknp"),
            &[&organizer],
        );
        if attendee_line.is_empty() {
            head
        } else {
            format!("{head}, {attendee_line}")
        }
    } else {
        let head = crate::i18n::fill(
            &crate::i18n::tr_id("%1 invited ", "autosuggest:kaic6f24d"),
            &[&organizer],
        );
        if attendee_line.is_empty() {
            head + &organizer
        } else {
            head + &attendee_line
        }
    };
    json!({
        "kind": "event", "id": s(&props["cid"]), "title": s(&r["Subject"]),
        "start": s(&r["Start"]), "end": s(&r["End"]), "who": who,
        "join": s(&r["SkypeTeamsMeetingUrl"]), "uid": s(&r["Uid"]),
        "thread": s(&props["cid"]), "recurring": !s(&r["SeriesMasterId"]).is_empty(),
        "online": !s(&r["SkypeTeamsMeetingUrl"]).is_empty(),
    })
}

/// A message: "<sender's first name>[ (You)]: [subject - ]preview", where it
/// was said (a channel's "Team > Channel"; a group chat's topic and
/// members; a 1:1's other person), its date and identifier icons.
fn message(r: &Value, me: &Me, names: &Names) -> Value {
    let sender_mri = s(&r["From"]["MRI"]);
    let sender = s(&r["From"]["EmailAddress"]["Name"]);
    let me_sent = !me.mri.is_empty() && sender_mri.eq_ignore_ascii_case(&me.mri);
    let prefix = if me_sent {
        format!(
            "{} {}: ",
            first_name(&sender),
            crate::i18n::tr_id("(You)", "autosuggest:k9m83y7y2")
        )
    } else {
        format!("{}: ", first_name(&sender))
    };
    let subject = s(&r["Subject"]);
    let text = if subject.is_empty() {
        s(&r["Preview"])
    } else {
        format!("{subject} - {}", s(&r["Preview"]))
    };
    let thread = s(&r["ClientThreadId"]);
    let channel = r["ThreadType"] == "Channel";
    let sub_type = s(&r["ThreadSubType"]);
    // Where: 1:1 (and meeting) chats name the other people; group chats
    // their topic and members.
    let to: Vec<String> = r["ToPreview"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|t| {
            let mri = t["MRI"].as_str().unwrap_or_default();
            if mri.is_empty() {
                !t["DisplayName"]
                    .as_str()
                    .unwrap_or_default()
                    .eq_ignore_ascii_case(&me.name)
            } else {
                !mri.eq_ignore_ascii_case(&me.mri)
            }
        })
        .map(|t| display_name(t, names))
        .collect();
    let people = match r["ToPreview"].as_array().map(|a| a.len()).unwrap_or(0) {
        1 => {
            let n = display_name(&r["ToPreview"][0], names);
            if sub_type == "PersonalNotes" || sub_type == "SelfChat" {
                format!(
                    "{n} {}",
                    crate::i18n::tr_id("(You)", "autosuggest:k9m83y7y2")
                )
            } else {
                n
            }
        }
        _ => join_names(
            &to.iter().map(|n| first_name(n)).collect::<Vec<_>>(),
            (r["RecipientsCount"].as_u64().unwrap_or(1) as usize).saturating_sub(1),
        ),
    };
    let (place, topic) = if channel {
        (
            format!("{} > {}", s(&r["Team"]), s(&r["Channel"])),
            String::new(),
        )
    } else {
        (people, s(&r["Topic"]))
    };
    let mut icons: Vec<&str> = Vec::new();
    for m in r["Metadata"].as_array().into_iter().flatten() {
        let icon = match m.as_str().unwrap_or_default() {
            "HasAttachments" => "attach",
            "HasImage" => "image",
            "HasLinks" => "link",
            "Important" => "important",
            "IsMentioned" => "mention",
            "Urgent" => "urgent",
            _ => continue,
        };
        if !icons.contains(&icon) {
            icons.push(icon);
        }
    }
    icons.truncate(ICONS);
    json!({
        "kind": "message", "id": s(&r["InternetMessageId"]), "thread": thread,
        "parent": s(&r["ParentMessageId"]), "channel": channel, "group": s(&r["GroupId"]),
        "prefix": prefix, "title": text, "time": s(&r["DateTimeSent"]),
        "place": place, "topic": topic, "sender_mri": sender_mri, "sender": sender,
        "one_on_one": sub_type == "OneOnOneChat" || sub_type == "MeetingChat",
        "icons": icons, "images": r["AMSReferences"].clone(),
        "image": r["EntitySubType"] == "Image",
    })
}

/// A text suggestion: a recent search (Attributes.IsHistory), Teams' "<person>
/// in all results" for a person named in the query, or a suggested query.
fn text(r: &Value) -> Value {
    if r["TextSuggestionType"] == "PeopleAsText" {
        let p = &r["PersonSuggestions"][0];
        return json!({
            "kind": "pcs", "title": s(&p["DisplayName"]), "oid": s(&p["ExternalDirectoryObjectId"]),
            "mail": p["EmailAddresses"][0].as_str().map(str::to_string).unwrap_or_else(|| s(&p["UserPrincipalName"])),
            "mri": s(&p["MRI"]), "query": s(&r["QueryText"]),
        });
    }
    json!({
        "kind": "text", "title": s(&r["Text"]), "query": s(&r["QueryText"]),
        "history": r["Attributes"]["IsHistory"].as_bool().unwrap_or(false),
    })
}

fn convert(group: &str, r: &Value, query: &str, me: &Me, names: &Names) -> Option<Value> {
    Some(match group {
        "People" => person(r, me)?,
        "Chat" => chat(r, me, names),
        "Team" => team(r),
        "Channel" => channel(r),
        "File" => file(r),
        "Event" => event(r, query, me),
        "Text" => text(r),
        "Message" => message(r, me, names),
        _ => return None,
    })
}

/// A group of suggestions under its heading (Teams' strings).
fn group(id: &str, title: String, items: Vec<Value>) -> Value {
    json!({ "id": id, "title": title, "items": items })
}

/// The suggestions in Teams' groups; see the module comment. Empty groups
/// are left out. `people` is the zero-query People row (Teams' top-N).
pub fn arrange(
    reply: &Value,
    query: &str,
    me: &Me,
    people: Vec<Value>,
    names: &Names,
) -> Vec<Value> {
    // Every suggestion by group, with its reference.
    let mut by_group: Vec<(String, Vec<(String, Value)>)> = Vec::new();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        let name = s(&g["Type"]);
        let items: Vec<(String, Value)> = g["Suggestions"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|r| Some((s(&r["ReferenceId"]), convert(&name, r, query, me, names)?)))
            .collect();
        by_group.push((name, items));
    }
    let mut best: Vec<Value> = Vec::new();
    let mut taken: Vec<String> = Vec::new();
    for hint in reply["LayoutHints"]["BestMatchSuggestions"]
        .as_array()
        .into_iter()
        .flatten()
    {
        let reference = s(&hint["ReferenceId"]);
        let found = by_group
            .iter()
            .filter(|(g, _)| *g == s(&hint["Group"]))
            .flat_map(|(_, items)| items.iter())
            .find(|(r, _)| *r == reference);
        if let Some((_, v)) = found {
            best.push(v.clone());
            taken.push(reference);
        }
    }
    let rest = |g: &str| -> Vec<Value> {
        by_group
            .iter()
            .filter(|(name, _)| name == g)
            .flat_map(|(_, items)| items.iter())
            .filter(|(r, _)| !taken.contains(r))
            .map(|(_, v)| v.clone())
            .collect()
    };
    let mut out = Vec::new();
    if query.trim().is_empty() {
        let people: Vec<Value> = people
            .into_iter()
            .map(|mut p| {
                if p["mri"].is_null() {
                    p["mri"] = json!(format!("8:orgid:{}", s(&p["oid"])));
                }
                p
            })
            .collect();
        out.push(group(
            "PEOPLE",
            crate::i18n::tr_id("People", "autosuggest:k7s0n9myt"),
            people,
        ));
        out.push(group(
            "HISTORY",
            crate::i18n::tr_id("Suggestions", "autosuggest:k368mmn7n"),
            best,
        ));
    } else {
        out.push(group("TOPHITS", String::new(), best));
        let all_messages = rest("Message");
        let mut messages: Vec<Value> = all_messages.iter().take(MESSAGES).cloned().collect();
        if !messages.is_empty() {
            messages.push(json!({ "kind": "seemore", "query": query.trim() }));
        }
        out.push(group(
            "MESSAGES",
            crate::i18n::tr_id("Recent messages", "autosuggest:kbwxzlnau"),
            messages,
        ));
        out.push(group(
            "PEOPLE",
            crate::i18n::tr_id("People", "autosuggest:k7s0n9myt"),
            rest("People"),
        ));
        out.push(group(
            "FILES",
            crate::i18n::tr_id("Files", "autosuggest:kckk9oukc"),
            rest("File"),
        ));
        out.push(group(
            "CHANNELS",
            crate::i18n::tr_id("Channels", "autosuggest:k5er54tii"),
            rest("Channel"),
        ));
        out.push(group(
            "TEAMS",
            crate::i18n::tr_id("Teams", "autosuggest:k1ve7gv7y"),
            rest("Team"),
        ));
        out.push(group(
            "GROUPCHATS",
            crate::i18n::tr_id("Group Chats", "autosuggest:k3xy694dn"),
            rest("Chat"),
        ));
        out.push(group(
            "EVENTS",
            crate::i18n::tr_id("Meetings", "autosuggest:kdgd2s8xm"),
            rest("Event"),
        ));
        // Recent images: the messages' pictures.
        let images = image_tiles(&all_messages, IMAGES);
        out.push(group(
            "IMAGES",
            crate::i18n::tr_id("Recent images", "autosuggest:k2vpagigo"),
            images,
        ));
    }
    out.into_iter()
        .filter(|g| {
            g["items"]
                .as_array()
                .map(|a| !a.is_empty())
                .unwrap_or(false)
        })
        .collect()
}

// ---------------------------------------------------------------------------
// A scope pill, KQL filters and go-to mode (TASK-0371; Teams desktop 26304
// on winpc, 2026-11-27).
// - A scope pill puts "is:<Domain>" in the box: Teams asks
//   `?scenario=powerbar&setflight=TurnOffMPLSuppressionTeams…&domain=<entity>`
//   for that entity alone (ECS autosuggest.domainScopingConfig's count),
//   with the domain and every picked filter as QueryAnnotations; with
//   words typed, also one person (the from:<person> pill Teams offers).
// - A from: or in: pill opens Teams' picker: people (from:), or group
//   chats, channels, teams and people (in:), asked with the operator as
//   KqlKeyword. filetype: is a list of types; has: (Messages) a filter.
// - A from:<person> pill with no scope: that person's chats, files and
//   messages (Teams' people-centric search).
// - Go-to mode (Ctrl+G): Teams' local chats, channels and people, and
//   when none match `?scenario=powerbar.goto` (people, chats, teams,
//   channels).
// ---------------------------------------------------------------------------

/// A scope pill's domain, as Teams asks for it and shows it.
struct Domain {
    /// The QueryAnnotation's DomainType and Text (Meetings has none).
    annotation: Option<(&'static str, &'static str)>,
    entity: &'static str,
    /// `domain=` in the address, and the flights after Teams' own.
    url: &'static str,
    flights: &'static str,
    /// ECS autosuggest.domainScopingConfig (zqCount and qfCount agree).
    size: u64,
    /// Words typed: ask for a person too (the from:<person> pill).
    person: bool,
    group: &'static str,
    /// The heading with nothing typed.
    heading: (&'static str, &'static str),
}

fn domain(key: &str) -> Option<Domain> {
    let d = |annotation, entity, url, flights, size, person, group, heading| Domain {
        annotation,
        entity,
        url,
        flights,
        size,
        person,
        group,
        heading,
    };
    Some(match key {
        "messages" => d(
            Some(("Message", "Messages")),
            "Message",
            "Message",
            "",
            10,
            true,
            "MESSAGES",
            ("Suggested messages", "autosuggest:kasjwn81c"),
        ),
        "files" => d(
            Some(("File", "Files")),
            "File",
            "File",
            "",
            10,
            true,
            "FILES",
            ("Suggested files", "autosuggest:k3e34yeuw"),
        ),
        "channels" => d(
            Some(("Teamschannel", "Channels")),
            "TeamsChannel",
            "TeamsChannel",
            ",EnableTeamsChannelDomainPowerbar",
            8,
            false,
            "TEAMSANDCHANNELS",
            ("Suggested channels", "autosuggest:katfx1kvg"),
        ),
        "groupchats" => d(
            Some(("Groupchat", "Group Chats")),
            "Chat",
            "Chat",
            "",
            10,
            true,
            "GROUPCHATS",
            ("Suggested group chats", "autosuggest:kbhfa9xuf"),
        ),
        "meetings" => d(
            None,
            "Event",
            "Event",
            "",
            10,
            false,
            "EVENTS",
            ("Suggested meetings", "autosuggest:k15fn11i4"),
        ),
        "images" => d(
            Some(("Message", "Images")),
            "Message",
            "Message",
            ",EnableMessageImageSearch",
            18,
            true,
            "IMAGES",
            ("Recent images", "autosuggest:k2vpagigo"),
        ),
        _ => return None,
    })
}

/// A picked from: or in: filter's QueryAnnotation (Teams' shapes): a
/// person (`{kind: "person", name, mail, mri, oid}`), a channel or team
/// (`thread`, `group`, `ctype`) or a chat (`thread`).
pub fn annotation(p: &Value, tenant: &str) -> Value {
    let kw = if p["kw"] == "in" { "In" } else { "From" };
    let name = s(&p["name"]);
    match p["kind"].as_str().unwrap_or_default() {
        "person" => {
            let mail = s(&p["mail"]);
            let oid = s(&p["oid"]);
            let emails: Vec<&str> = if mail.is_empty() {
                Vec::new()
            } else {
                vec![mail.as_str()]
            };
            let id = if tenant.is_empty() || oid.is_empty() {
                oid.clone()
            } else {
                format!("{oid}@{tenant}")
            };
            json!({
                "AdditionalEmailList": emails, "DisplayName": name, "Email": mail, "Id": id,
                "Mri": s(&p["mri"]), "Text": name, "Type": "People", "KqlKeyword": kw,
            })
        }
        "channel" => {
            let mut ctype = s(&p["ctype"]);
            if ctype.is_empty() {
                ctype = "Standard".into();
            }
            json!({
                "ChannelType": ctype,
                "GroupId": s(&p["group"]), "Name": name, "TenantId": tenant, "Text": name,
                "ThreadId": s(&p["thread"]), "Type": "Channel", "KqlKeyword": kw,
            })
        }
        "team" => json!({
            "GroupId": s(&p["group"]), "Name": name, "TenantId": tenant, "Text": name,
            "ThreadId": s(&p["thread"]), "Type": "Team", "KqlKeyword": kw,
        }),
        _ => json!({
            "Name": name, "Text": name, "ThreadId": s(&p["thread"]), "Type": "Chat", "KqlKeyword": kw,
        }),
    }
}

/// The request for a scoped or KQL box (`spec`: `text` the box, `words`
/// what's typed besides the filters, `scope` the pill's key, `picks` the
/// from:/in: filters, `filetype` (Teams' ExtensionType, "Pdf"), `mentions`,
/// `attachments`, `picker` ("from" / "in") with `picker_query`, or `goto`):
/// its address and body.
pub fn kql_request(spec: &Value, tenant: &str, cvid: &str, logical: &str) -> (String, Value) {
    let text = s(&spec["text"]);
    let words = s(&spec["words"]).trim().to_string();
    if spec["goto"].as_bool() == Some(true) {
        let q = json!({ "QueryString": words, "NormalizedQueryString": words });
        let body = json!({
            "EntityRequests": [
                people_request(json!({ "QueryString": words, "DisplayQueryString": words, "NormalizedQueryString": words }), 5, true),
                { "Query": q, "EntityType": "Chat", "Size": 5 },
                { "Query": q, "EntityType": "Team", "Size": 3 },
                { "Query": q, "EntityType": "Channel", "Size": 4, "Filter": channel_filter() }
            ],
            "Scenario": { "Name": "powerbar.goto" },
            "Cvid": cvid, "AppName": "Microsoft Teams", "LogicalId": logical,
        });
        return (
            format!("{URL}?scenario=powerbar.goto&setflight={SET_FLIGHT}"),
            body,
        );
    }
    let scope = s(&spec["scope"]);
    let d = domain(&scope);
    let mut annotations: Vec<Value> = Vec::new();
    if let Some((t, label)) = d.as_ref().and_then(|d| d.annotation) {
        annotations
            .push(json!({ "DomainType": t, "Text": label, "Type": "Domain", "KqlKeyword": "Is" }));
    }
    annotations.extend(
        spec["picks"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|p| annotation(p, tenant)),
    );
    let query = |kw: Option<&str>, normalized: &str| {
        let mut q = json!({ "QueryString": text, "NormalizedQueryString": normalized });
        if let Some(k) = kw {
            q["KqlKeyword"] = json!(k);
        }
        if !annotations.is_empty() {
            q["QueryAnnotations"] = json!(annotations);
        }
        q
    };
    let body = |requests: Vec<Value>| {
        json!({
            "EntityRequests": requests,
            "Scenario": { "Name": "powerbar", "Dimensions": [{ "DimensionName": "QueryType", "DimensionValue": "PeopleCentricSearch" }] },
            "Cvid": cvid, "AppName": "Microsoft Teams", "LogicalId": logical, "dataSource": "personScoped",
        })
    };
    let picker = s(&spec["picker"]);
    if picker == "from" || picker == "in" {
        let pq = s(&spec["picker_query"]).trim().to_string();
        let q = query(Some(if picker == "in" { "In" } else { "From" }), &pq);
        let mut requests = Vec::new();
        if picker == "in" {
            requests.push(json!({ "Query": q, "EntityType": "Chat", "Size": 2 }));
            requests.push(json!({ "Query": q, "EntityType": "Channel", "Size": 2, "Filter": channel_filter() }));
            requests.push(json!({ "Query": q, "EntityType": "Team", "Size": 2 }));
        }
        requests.push(people_request(q, 5, false));
        return (
            format!("{URL}?scenario=powerbar&setflight=TurnOffMPLSuppressionTeams"),
            body(requests),
        );
    }
    let person = |q: &Value| {
        let mut pq = q.clone();
        pq["DisplayQueryString"] = json!(words);
        people_request(pq, 1, true)
    };
    match d {
        Some(d) => {
            let q = if d.annotation.is_none() {
                json!({ "QueryString": words, "NormalizedQueryString": words })
            } else {
                query(None, &words)
            };
            let mut main = json!({ "Query": q, "EntityType": d.entity, "Size": d.size });
            let mut terms: Vec<Value> = Vec::new();
            let filetype = s(&spec["filetype"]);
            if d.entity == "File" && !filetype.is_empty() {
                terms.push(json!({ "Or": [{ "Term": { "FileType": filetype } }] }));
            }
            if scope == "messages" {
                if spec["attachments"].as_bool() == Some(true) {
                    terms.push(json!({ "Or": [{ "Term": { "HasAttachments": "True" } }] }));
                }
                if spec["mentions"].as_bool() == Some(true) {
                    terms.push(json!({ "Or": [{ "Term": { "HasMentions": "True" } }] }));
                }
            }
            if scope == "channels" {
                main["Filter"] = channel_filter();
            } else if !terms.is_empty() {
                main["Filter"] = json!({ "And": terms });
            }
            let mut requests = vec![main];
            if d.person && !words.is_empty() {
                requests.push(person(&q));
            }
            (
                format!(
                    "{URL}?scenario=powerbar&setflight=TurnOffMPLSuppressionTeams{}&domain={}",
                    d.flights, d.url
                ),
                body(requests),
            )
        }
        // From a person with no scope: their chats, files and messages.
        None => {
            let q = query(None, &words);
            let requests = vec![
                json!({ "Query": q, "EntityType": "Chat", "Size": 5 }),
                json!({ "Query": q, "EntityType": "File", "Size": 3 }),
                json!({ "Query": q, "EntityType": "Message", "Size": MESSAGES }),
                person(&q),
            ];
            (
                format!("{URL}?scenario=powerbar&setflight={SET_FLIGHT}"),
                body(requests),
            )
        }
    }
}

/// Ask for a scoped or KQL box (see [`kql_request`]).
pub async fn fetch_kql(spec: &Value, me: &Me, tenant: &str) -> Result<Value> {
    let (url, body) = kql_request(
        spec,
        tenant,
        &uuid::Uuid::new_v4().to_string(),
        &uuid::Uuid::new_v4().to_string(),
    );
    send(&url, Some(body), me, tenant).await
}

/// A message's pictures as Recent images tiles.
fn image_tiles(messages: &[Value], max: usize) -> Vec<Value> {
    messages
        .iter()
        .filter(|m| m["image"].as_bool() == Some(true))
        .flat_map(|m| {
            m["images"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|a| a.as_str())
                .map(|a| json!({ "kind": "image", "ams": a, "thread": m["thread"], "id": m["id"], "parent": m["parent"], "channel": m["channel"], "title": m["title"] }))
                .collect::<Vec<_>>()
        })
        .take(max)
        .collect()
}

/// A scoped or KQL reply in Teams' groups (`{groups, pcs}`; `pcs` is the
/// person for the from:<person> pill, or null).
pub fn arrange_kql(reply: &Value, spec: &Value, me: &Me, names: &Names) -> Value {
    let words = s(&spec["words"]).trim().to_string();
    let scope = s(&spec["scope"]);
    let picker = s(&spec["picker"]);
    let items = |g: &str| -> Vec<Value> {
        reply["Groups"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|x| x["Type"] == g)
            .flat_map(|x| x["Suggestions"].as_array().into_iter().flatten())
            .filter_map(|r| convert(g, r, &words, me, names))
            .collect()
    };
    let keyword = |list: Vec<Value>, kw: &str| -> Vec<Value> {
        list.into_iter()
            .map(|mut v| {
                v["kql"] = json!(kw);
                v
            })
            .collect()
    };
    let mut groups: Vec<Value> = Vec::new();
    let mut pcs = Value::Null;
    if spec["goto"].as_bool() == Some(true) {
        let mut all = items("People");
        for g in ["Chat", "Team", "Channel"] {
            all.extend(items(g));
        }
        groups.push(group("GOTO", String::new(), all));
    } else if picker == "from" {
        groups.push(group(
            "PEOPLE",
            String::new(),
            keyword(items("People"), "from"),
        ));
    } else if picker == "in" {
        for (id, g) in [
            ("GROUPCHATS", "Chat"),
            ("CHANNELS", "Channel"),
            ("TEAMS", "Team"),
            ("PEOPLE", "People"),
        ] {
            groups.push(group(id, String::new(), keyword(items(g), "in")));
        }
    } else if let Some(d) = domain(&scope) {
        let list: Vec<Value> = match scope.as_str() {
            "channels" => reply["Groups"]
                .as_array()
                .into_iter()
                .flatten()
                .flat_map(|x| x["Suggestions"].as_array().into_iter().flatten())
                .map(|r| {
                    if r["EntityType"] == "TeamSuggestion" {
                        team(r)
                    } else {
                        channel(r)
                    }
                })
                .collect(),
            "images" => image_tiles(&items("Message"), d.size as usize),
            _ => items(d.entity),
        };
        let heading = if words.is_empty() {
            crate::i18n::tr_id(d.heading.0, d.heading.1)
        } else {
            String::new()
        };
        groups.push(group(d.group, heading, list));
        if d.person && !words.is_empty() {
            pcs = items("People").into_iter().next().unwrap_or(Value::Null);
        }
    } else {
        // From a person, no scope: them, their messages (and "See more
        // messages from …"), files and group chats; a place alone: its
        // messages, files and group chats.
        let from = spec["picks"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|p| p["kw"] == "from" && p["kind"] == "person");
        if let Some(p) = from {
            if words.is_empty() {
                groups.push(group(
                    "TOPHITS",
                    String::new(),
                    vec![json!({
                        "kind": "person", "oid": s(&p["oid"]), "name": s(&p["name"]), "mail": s(&p["mail"]),
                        "mri": s(&p["mri"]), "sub": s(&p["sub"]),
                    })],
                ));
            } else {
                groups.push(group(
                    "TOPHITS",
                    String::new(),
                    items("People").into_iter().take(1).collect(),
                ));
            }
            let mut messages: Vec<Value> = items("Message").into_iter().take(MESSAGES).collect();
            if !messages.is_empty() {
                messages.push(json!({ "kind": "seemore", "query": words, "from": s(&p["name"]) }));
            }
            groups.push(group(
                "MESSAGES",
                crate::i18n::tr_id("Recent messages", "autosuggest:kbwxzlnau"),
                messages,
            ));
            groups.push(group(
                "FILES",
                crate::i18n::tr_id("Files", "autosuggest:kckk9oukc"),
                items("File"),
            ));
            groups.push(group(
                "GROUPCHATS",
                crate::i18n::tr_id("Group Chats", "autosuggest:k3xy694dn"),
                items("Chat"),
            ));
        } else {
            // Only a place (in:) with no scope: what's said and shared there.
            let mut messages: Vec<Value> = items("Message").into_iter().take(MESSAGES).collect();
            if !messages.is_empty() && !words.is_empty() {
                messages.push(json!({ "kind": "seemore", "query": words }));
            }
            groups.push(group(
                "MESSAGES",
                crate::i18n::tr_id("Recent messages", "autosuggest:kbwxzlnau"),
                messages,
            ));
            groups.push(group(
                "FILES",
                crate::i18n::tr_id("Files", "autosuggest:kckk9oukc"),
                items("File"),
            ));
            groups.push(group(
                "GROUPCHATS",
                crate::i18n::tr_id("Group Chats", "autosuggest:k3xy694dn"),
                items("Chat"),
            ));
        }
    }
    let groups: Vec<Value> = groups
        .into_iter()
        .filter(|g| g["items"].as_array().is_some_and(|a| !a.is_empty()))
        .collect();
    json!({ "groups": groups, "pcs": pcs })
}

/// How many messages the Messages pill asks the suggestions service for
/// (ECS autosuggest.domainScopingConfig); fewer back and Teams backfills.
const MESSAGE_DOMAIN_SIZE: usize = 10;

/// Teams' message backfill (captured on winpc, Teams 26304, 2026-11-28):
/// with the Messages pill, when the suggestions bring back fewer messages
/// than the 10 asked for, Teams also asks the search service
/// (searchservice/api/v2/query, PowerbarTypeAheadMsg, 25) with the box's
/// filters, and lists the messages the suggestions don't have after theirs.
/// That's where its hits come from when the suggestions service has none
/// (has:@Mentions with words, in:<channel>). Not for a picker or go-to.
pub fn wants_backfill(spec: &Value, arranged: &Value) -> bool {
    if s(&spec["scope"]) != "messages"
        || !s(&spec["picker"]).is_empty()
        || spec["goto"].as_bool() == Some(true)
    {
        return false;
    }
    let shown = arranged["groups"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|g| g["id"] == "MESSAGES")
        .map(|g| g["items"].as_array().map_or(0, Vec::len))
        .sum::<usize>();
    shown < MESSAGE_DOMAIN_SIZE
}

/// The box's filters as the search service's (a picked from: person, an
/// in: chat, channel or team, @Mentions, Has attachments).
pub fn backfill_filters(spec: &Value) -> super::search::Filters {
    let mut f = super::search::Filters {
        mentions: spec["mentions"].as_bool() == Some(true),
        attachment: spec["attachments"].as_bool() == Some(true),
        ..Default::default()
    };
    for p in spec["picks"].as_array().into_iter().flatten() {
        match (s(&p["kw"]).as_str(), s(&p["kind"]).as_str()) {
            ("from", "person") => {
                f.person_mail = s(&p["mail"]);
                f.person_oid = s(&p["oid"]);
            }
            ("in", kind @ ("chat" | "channel" | "team")) => {
                f.in_kind = kind.to_string();
                f.in_thread = s(&p["thread"]);
                f.in_group = s(&p["group"]);
            }
            _ => {}
        }
    }
    f
}

/// The fields Teams' powerbar asks the search service for.
const BACKFILL_FIELDS: [&str; 12] = [
    "Extension_SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_FileData_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String",
    "GroupId",
    "Extension_SkypeSpaces_ConversationPost_Extension_SenderTenantId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ParentMessageId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ConversationType_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_Topic_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ImageSrc_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_AmsReferences_StringArray",
    "Extension_SkypeSpaces_ConversationPost_Extension_ParentMessageId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_MessageSubType_String",
];

/// The backfill's request, as Teams sends it: the search page's query
/// string for the filters ("mentions:<oid> AND NOT (isClientSoftDeleted:TRUE)
/// release"; "*" with no words), the person as a query annotation.
pub fn backfill_body(
    spec: &Value,
    my_oid: &str,
    tenant: &str,
    timezone: &str,
    cvid: &str,
    logical: &str,
) -> Value {
    let words = s(&spec["words"]).trim().to_string();
    let words = if words.is_empty() {
        "*".to_string()
    } else {
        words
    };
    let f = backfill_filters(spec);
    let mut query = json!({
        "queryString": super::search::message_query(&words, &f, my_oid, false),
        "displayQueryString": words,
    });
    if !f.person_mail.is_empty() {
        query["queryAnnotations"] = json!([{
            "type": "People", "text": f.person_mail, "userId": f.person_oid, "tenantId": tenant,
        }]);
    }
    json!({
        "entityRequests": [{
            "entityType": "Message", "contentSources": ["Teams"], "fields": BACKFILL_FIELDS,
            "query": query, "propertySet": "Optimized", "topResultsCount": 10, "from": 0, "size": 25,
        }],
        "cvid": cvid,
        "logicalId": logical,
        "QueryAlterationOptions": { "EnableAlteration": true, "EnableSuggestion": true, "SupportedRecourseDisplayTypes": ["Suggestion"] },
        "scenario": {
            "Dimensions": [
                { "DimensionName": "QueryType", "DimensionValue": "PowerbarTypeAheadMsg" },
                { "DimensionName": "FormFactor", "DimensionValue": "general.cdlworker.reactSearch" }
            ],
            "Name": "powerbar",
        },
        "timezone": timezone,
    })
}

/// A search service result as a suggestion (Teams' converter `el`): its
/// sender, where it was said (a channel's team and channel, a chat's topic
/// and the people it went to), its date, its summary without the
/// highlighting, its identifiers.
fn backfill_suggestion(r: &Value) -> Value {
    let src = &r["Source"];
    let ext = &src["Extensions"];
    let e = |k: &str| s(&ext[format!("SkypeSpaces_ConversationPost_Extension_{k}")]);
    let thread_type = match e("ThreadType").to_ascii_lowercase().as_str() {
        "chat" | "streamofnotes" | "sfbinteropchat" => "Chat",
        "meeting" => "Meeting",
        _ => "Channel",
    };
    let conversation_type = e("ConversationType");
    let sub_type = match conversation_type.as_str() {
        "P2PChat" => "OneOnOneChat",
        "PersonalStream" => "SelfChat",
        t @ ("NamedGroupChat" | "UnnamedGroupChat" | "MeetingChat" | "SharedChannel"
        | "StandardChannel") => t,
        _ => "",
    };
    let to: Vec<Value> = s(&src["DisplayTo"])
        .split(';')
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map(|n| json!({ "DisplayName": n, "MRI": "" }))
        .collect();
    let mut metadata = Vec::new();
    match s(&src["Importance"]).as_str() {
        "High" => metadata.push("Important"),
        "Urgent" => metadata.push("Urgent"),
        _ => {}
    }
    if src["MentionsPreview"]["IsMentioned"].as_bool() == Some(true) {
        metadata.push("IsMentioned");
    }
    if src["HasAttachments"].as_bool() == Some(true) {
        metadata.push("HasAttachments");
    }
    let summary = if r["HitHighlightedSummary"].is_string() {
        s(&r["HitHighlightedSummary"])
    } else {
        s(&src["Preview"])
    };
    json!({
        "From": { "MRI": e("FromSkypeInternalId"), "EmailAddress": src["Sender"]["EmailAddress"].clone() },
        "ThreadType": thread_type, "ThreadSubType": sub_type,
        "Topic": e("Topic"), "Team": s(&src["TeamName"]), "Channel": s(&src["ChannelName"]),
        "GroupId": s(&src["GroupId"]), "ClientThreadId": s(&src["ClientThreadId"]),
        "DateTimeSent": s(&src["DateTimeSent"]), "InternetMessageId": s(&src["InternetMessageId"]),
        "ParentMessageId": e("ParentMessageId"), "Preview": strip_tags(&summary),
        "Metadata": metadata, "RecipientsCount": to.len(), "ToPreview": to,
        "AMSReferences": ext["SkypeSpaces_ConversationPost_Extension_AmsReferences"].clone(),
    })
}

/// Text without its tags (Teams' `zF`), entities read, spaces as one.
fn strip_tags(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    let out = out
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&");
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The backfill reply's messages as suggestion rows.
pub fn backfill_messages(reply: &Value, me: &Me, names: &Names) -> Vec<Value> {
    reply["EntitySets"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|set| set["ResultSets"].as_array().into_iter().flatten())
        .flat_map(|rs| rs["Results"].as_array().into_iter().flatten())
        .filter(|r| r["Type"] == "Message" || r["Source"]["InternetMessageId"].is_string())
        .map(|r| message(&backfill_suggestion(r), me, names))
        .collect()
}

/// The backfilled messages after the suggestions' own (those the
/// suggestions already list are left out, as Teams dedupes by message id).
pub fn merge_backfill(arranged: &mut Value, extra: Vec<Value>) {
    if extra.is_empty() {
        return;
    }
    let groups = arranged["groups"].as_array_mut();
    let Some(groups) = groups else { return };
    let i = match groups.iter().position(|g| g["id"] == "MESSAGES") {
        Some(i) => i,
        // (Only the backfill's: Teams shows them under no heading.)
        None => {
            groups.insert(0, group("MESSAGES", String::new(), Vec::new()));
            0
        }
    };
    let Some(items) = groups[i]["items"].as_array_mut() else {
        return;
    };
    let mut seen: std::collections::HashSet<String> = items.iter().map(|m| s(&m["id"])).collect();
    for m in extra {
        let id = s(&m["id"]);
        if id.is_empty() || seen.insert(id) {
            items.push(m);
        }
    }
}

/// Ask the search service for the backfill (see [`wants_backfill`]).
pub async fn fetch_backfill(
    spec: &Value,
    my_oid: &str,
    tenant: &str,
    timezone: &str,
) -> Result<Value> {
    let body = backfill_body(
        spec,
        my_oid,
        tenant,
        timezone,
        &uuid::Uuid::new_v4().to_string(),
        &uuid::Uuid::new_v4().to_string(),
    );
    let anchor = if my_oid.is_empty() || tenant.is_empty() {
        String::new()
    } else {
        format!("OID:{my_oid}@{tenant}")
    };
    super::find::search_raw_flights(&body, &anchor, super::find::POWERBAR_FLIGHTS).await
}

/// Your affinity with your chats, channels and teams, as Teams' go-to
/// ranking reads it (Substrate's user knowledge base,
/// `GET /userknowledgebase/v1.0/{upn}/teams/affinityscore`): each kind's
/// scores (ScoreV2, else Score; below 0 counts as 0) as z-scores scaled to
/// 0…1, by thread id, plus each kind's mean (`means`: UCMean, UGCMean,
/// UTMean) for chats too new to have a score of their own.
pub fn affinity_scores(reply: &Value) -> Value {
    let v = &reply["value"][0];
    let mut out = serde_json::Map::new();
    let mut means = serde_json::Map::new();
    for (key, id_key, mean) in [
        ("UCScore", "ThreadId", "UCMean"),
        ("UGCScore", "ThreadId", "UGCMean"),
        ("UTScore", "TeamId", "UTMean"),
    ] {
        let rows: Vec<(String, f64)> = v[key]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|r| r["Score"].as_f64() != Some(-1.0))
            .map(|r| {
                let score = r["ScoreV2"]
                    .as_f64()
                    .or_else(|| r["Score"].as_f64())
                    .unwrap_or(0.0)
                    .max(0.0);
                (s(&r[id_key]), score)
            })
            .collect();
        let scaled = normalised(&rows.iter().map(|(_, x)| *x).collect::<Vec<_>>());
        let n = scaled.len().max(1) as f64;
        means.insert(mean.into(), json!(scaled.iter().sum::<f64>() / n));
        for ((id, _), x) in rows.into_iter().zip(scaled) {
            if !id.is_empty() && x > 0.0 {
                out.insert(id, json!(x));
            }
        }
    }
    json!({ "scores": out, "means": means })
}

/// Teams' z-scores scaled to 0…1 (`dcs` then `ucs`): equal scores give
/// NaN there, which its ranking reads as 0.
fn normalised(xs: &[f64]) -> Vec<f64> {
    if xs.is_empty() {
        return Vec::new();
    }
    let n = xs.len() as f64;
    let mean = xs.iter().sum::<f64>() / n;
    let sd = (xs.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / n).sqrt();
    let z: Vec<f64> = xs.iter().map(|x| (x - mean) / sd).collect();
    let (lo, hi) = z
        .iter()
        .fold((f64::INFINITY, f64::NEG_INFINITY), |(a, b), &x| {
            (a.min(x), b.max(x))
        });
    z.iter()
        .map(|x| {
            let v = (x - lo) / (hi - lo);
            if v.is_finite() { v } else { 0.0 }
        })
        .collect()
}

/// Ask for your affinity scores (see [`affinity_scores`]).
pub async fn fetch_affinity(upn: &str, me: &Me, tenant: &str) -> Result<Value> {
    let url = format!(
        "https://substrate.office.com/userknowledgebase/v1.0/{}/teams/affinityscore",
        url::form_urlencoded::byte_serialize(upn.as_bytes()).collect::<String>()
    );
    send(&url, None, me, tenant).await
}

/// Teams' Communities group (Viva Engage's communities matching the
/// query), after the others; at most three.
pub fn communities_group(hits: &[super::search::CommunityHit]) -> Option<Value> {
    let items: Vec<Value> = hits
        .iter()
        .take(3)
        .map(|c| json!({ "kind": "community", "id": c.id, "title": c.name, "avatar": c.avatar }))
        .collect();
    (!items.is_empty()).then(|| {
        group(
            "ENGAGECOMMUNITY",
            crate::i18n::tr_id("Communities", "autosuggest:kh863a35"),
            items,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn me() -> Me {
        Me {
            oid: "aaaa".into(),
            mri: "8:orgid:aaaa".into(),
            mail: "me@x.test".into(),
            name: "Ada Lovelace".into(),
        }
    }

    #[test]
    fn typed_body_is_teams_powerbar() {
        let b = typed_body("release", "c", "l");
        assert_eq!(b["Scenario"]["Name"], "powerbar");
        assert_eq!(
            b["Scenario"]["Dimensions"][0]["DimensionValue"],
            "PeopleCentricSearch"
        );
        let types: Vec<&str> = b["EntityRequests"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r["EntityType"].as_str().unwrap())
            .collect();
        assert_eq!(
            types,
            [
                "People", "File", "Chat", "Team", "Channel", "Text", "Message", "Event", "App"
            ]
        );
        assert_eq!(b["EntityRequests"][6]["Size"], 11);
        assert_eq!(b["dataSource"], "personScoped");
    }

    #[test]
    fn names_join_as_teams() {
        let n = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        assert_eq!(join_names(&n(&["Bob"]), 1), "Bob");
        assert_eq!(join_names(&n(&["Bob", "Cy"]), 2), "Bob and Cy");
        assert_eq!(join_names(&n(&["Bob", "Cy", "Di"]), 3), "Bob, Cy, and Di");
        // More people than names: "+n".
        assert_eq!(join_names(&n(&["Bob", "Cy"]), 4), "Bob, Cy, +3");
        // Too long for one line.
        assert_eq!(
            join_names(&n(&["Bartholomew", "Christopher", "Dmitri"]), 3),
            "Bartholomew, Christopher, +2"
        );
    }

    fn reply() -> Value {
        json!({
            "Groups": [
                { "Type": "Chat", "Suggestions": [
                    { "Name": "Release planning", "ThreadId": "19:a@thread.v2", "ThreadType": "Chat", "TotalChatMembersCount": 3,
                      "ChatMembers": [{ "MRI": "8:orgid:aaaa", "DisplayName": "Ada Lovelace" }, { "MRI": "8:orgid:b", "DisplayName": "Bob Smith" }, { "MRI": "8:orgid:c", "DisplayName": "Cy Young" }],
                      "ReferenceId": "r.chat1" },
                    { "Name": "Other chat", "ThreadId": "19:b@thread.v2", "ThreadType": "Chat", "ReferenceId": "r.chat2" },
                    { "ThreadId": "19:meeting_x@thread.v2", "ThreadType": "Meeting", "Name": "Weekly sync", "ReferenceId": "r.chat3" }
                ]},
                { "Type": "File", "Suggestions": [
                    { "FileName": "Release tasks.loop", "FileExtension": "loop", "Author": "Ada Lovelace", "UserRelationshipType": "RecentlyAccessed",
                      "PropertyHits": ["FileName"], "From": { "EmailAddress": { "Name": "Ada Lovelace" } }, "FileSourceType": "OneDriveForBusiness",
                      "AccessUrl": "https://x/a.loop", "AlternateAccessUrl": "https://x/reader", "AlternateAccessUrlType": "ReaderUrl", "SpoUniqueId": "f1", "ReferenceId": "r.f1" },
                    { "FileName": "Release-notes.pdf", "FileExtension": "pdf", "Author": "Cy Young", "UserRelationshipType": "None",
                      "From": { "EmailAddress": { "Name": "Cy Young" } }, "FileSourceType": "OneDriveForBusiness", "AccessUrl": "https://x/n.pdf", "SpoUniqueId": "f2", "ReferenceId": "r.f2" },
                    { "FileName": "Notes.docx", "FileExtension": "docx", "Author": "Bob Smith", "UserRelationshipType": "RecentlyAccessed", "PropertyHits": [],
                      "FileSourceType": "SharepointOnline", "SourceTitle": "Test Team", "AccessUrl": "https://x.sharepoint.com/sites/T/Shared%20Documents/General/Notes.docx", "SpoUniqueId": "f3", "ReferenceId": "r.f3" }
                ]},
                { "Type": "Text", "Suggestions": [{ "Text": "release notes", "QueryText": "release notes", "Attributes": { "IsHistory": true }, "ReferenceId": "r.t1" }] },
                { "Type": "Message", "Suggestions": [
                    { "ClientThreadId": "19:a@thread.v2", "ThreadType": "Chat", "ThreadSubType": "NamedGroupChat", "DateTimeSent": "2026-11-25T17:11:24Z",
                      "ToPreview": [{ "DisplayName": "Ada Lovelace" }, { "DisplayName": "Bob Smith" }], "InternetMessageId": "111", "ParentMessageId": "111",
                      "Preview": "Here's the chart", "From": { "EmailAddress": { "Name": "Cy Young" }, "MRI": "8:orgid:c" }, "Topic": "Release planning", "RecipientsCount": 3,
                      "Metadata": ["IsRead", "HasAttachments", "HasImage"], "AMSReferences": ["0-wus-d4-1"], "EntitySubType": "Image", "ReferenceId": "r.m1" },
                    { "ClientThreadId": "19:t@thread.tacv2", "ThreadType": "Channel", "DateTimeSent": "2026-11-25T18:00:00Z", "InternetMessageId": "222", "ParentMessageId": "200",
                      "Preview": "checklist", "Subject": "0.3 release", "From": { "EmailAddress": { "Name": "Ada Lovelace" }, "MRI": "8:orgid:aaaa" }, "Team": "Test Team", "Channel": "General", "ReferenceId": "r.m2" }
                ]},
                { "Type": "Event", "Suggestions": [
                    { "Subject": "Release go/no-go", "OrganizerName": "Ada Lovelace", "OrganizerAddress": "me@x.test",
                      "Attendees": [{ "EmailAddress": { "Address": "b@x.test", "Name": "Bob Smith" } }, { "EmailAddress": { "Address": "c@x.test", "Name": "Cy Young" } }, { "EmailAddress": { "Address": "d@x.test", "Name": "Di Prince" } }],
                      "NumberOfAttendees": 3, "Start": "2026-12-03T18:00:00Z", "End": "2026-12-03T19:00:00Z", "SkypeTeamsMeetingUrl": "https://teams/join",
                      "SkypeTeamsProperties": "{\"cid\":\"19:meeting_y@thread.v2\"}", "ReferenceId": "r.e1" },
                    { "Subject": "Review", "OrganizerName": "Bob Smith", "OrganizerAddress": "b@x.test",
                      "Attendees": [{ "EmailAddress": { "Address": "me@x.test", "Name": "Ada Lovelace" } }], "NumberOfAttendees": 1,
                      "Start": "2026-11-27T18:00:00Z", "End": "2026-11-27T18:30:00Z", "ReferenceId": "r.e2" }
                ]}
            ],
            "LayoutHints": { "BestMatchSuggestions": [
                { "ReferenceId": "r.t1", "Group": "Text" }, { "ReferenceId": "r.chat1", "Group": "Chat" }, { "ReferenceId": "r.f1", "Group": "File" }
            ]}
        })
    }

    #[test]
    fn typed_groups_in_teams_order_without_top_hits() {
        let g = arrange(&reply(), "release", &me(), vec![], &Names::new());
        let ids: Vec<&str> = g.iter().map(|g| g["id"].as_str().unwrap()).collect();
        assert_eq!(
            ids,
            [
                "TOPHITS",
                "MESSAGES",
                "FILES",
                "GROUPCHATS",
                "EVENTS",
                "IMAGES"
            ]
        );
        let top: Vec<&str> = g[0]["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["kind"].as_str().unwrap())
            .collect();
        assert_eq!(top, ["text", "chat", "file"]);
        assert_eq!(g[0]["items"][0]["history"], true);
        // The top-hit chat names its members, you left out.
        assert_eq!(g[0]["items"][1]["sub"], "Bob and Cy");
        // Loop files open their reader address.
        assert_eq!(g[0]["items"][2]["url"], "https://x/reader");
        assert_eq!(g[0]["items"][2]["sub"], "Created by Ada Lovelace");
        // Messages: five at most, then "See more messages".
        let m = g[1]["items"].as_array().unwrap();
        assert_eq!(m.len(), 3);
        assert_eq!(m[0]["prefix"], "Cy: ");
        assert_eq!(m[0]["topic"], "Release planning");
        assert_eq!(m[0]["place"], "Bob, +2");
        assert_eq!(m[0]["icons"], json!(["attach", "image"]));
        assert_eq!(m[1]["prefix"], "Ada (You): ");
        assert_eq!(m[1]["title"], "0.3 release - checklist");
        assert_eq!(m[1]["place"], "Test Team > General");
        assert_eq!(m[2]["kind"], "seemore");
        // Files left: a shared one, a channel one.
        let f = g[2]["items"].as_array().unwrap();
        assert_eq!(f[0]["sub"], "Shared by Cy Young");
        assert_eq!(f[1]["sub"], "Test Team > General");
        // Chats left; the meeting chat has the calendar picture.
        let c = g[3]["items"].as_array().unwrap();
        assert_eq!(c.len(), 2);
        assert_eq!(c[1]["meeting"], true);
        // Meetings: who invited whom.
        let e = g[4]["items"].as_array().unwrap();
        assert_eq!(e[0]["who"], "You invited Bob, Cy +1 others");
        assert_eq!(e[0]["thread"], "19:meeting_y@thread.v2");
        assert_eq!(e[1]["who"], "Bob invited you");
        // Recent images.
        assert_eq!(g[5]["items"][0]["ams"], "0-wus-d4-1");
    }

    #[test]
    fn zero_query_people_then_suggestions() {
        let people = vec![json!({ "kind": "person", "oid": "b", "name": "Bob Smith" })];
        let g = arrange(&reply(), "", &me(), people, &Names::new());
        let ids: Vec<&str> = g.iter().map(|g| g["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["PEOPLE", "HISTORY"]);
        assert_eq!(g[0]["title"], "People");
        assert_eq!(g[0]["items"][0]["mri"], "8:orgid:b");
        assert_eq!(g[1]["title"], "Suggestions");
        assert_eq!(g[1]["items"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn people_as_text_and_attendee_matches() {
        let r = json!({ "TextSuggestionType": "PeopleAsText", "Text": "Messages from Bob Smith", "QueryText": "Messages from Bob Smith",
                        "PersonSuggestions": [{ "DisplayName": "Bob Smith", "ExternalDirectoryObjectId": "b", "EmailAddresses": ["b@x.test"], "MRI": "8:orgid:b" }] });
        let t = text(&r);
        assert_eq!(t["kind"], "pcs");
        assert_eq!(t["title"], "Bob Smith");
        // An attendee matching the query comes first.
        let e = event(&reply()["Groups"][4]["Suggestions"][0], "di", &me());
        assert_eq!(e["who"], "You invited Di, Bob +1 others");
    }

    #[test]
    fn communities_after_the_rest() {
        let c = super::super::search::CommunityHit {
            id: "g1".into(),
            name: "OST Test Community".into(),
            ..Default::default()
        };
        let g = communities_group(&[c]).unwrap();
        assert_eq!(g["id"], "ENGAGECOMMUNITY");
        assert_eq!(g["items"][0]["kind"], "community");
        assert!(communities_group(&[]).is_none());
    }

    #[test]
    fn channel_folder_from_address() {
        assert_eq!(
            channel_folder(
                "https://x/sites/T/Shared%20Documents/OST%20test%20channel/a.loop?web=1"
            ),
            "OST test channel"
        );
        assert_eq!(channel_folder("https://x/personal/a/Documents/a.loop"), "");
    }

    #[test]
    fn scoped_requests_are_teams() {
        // Files with a person and a type picked.
        let spec = json!({ "text": "is:Files from:OST Test 2 filetype:PDF ", "words": "", "scope": "files",
            "picks": [{ "kw": "from", "kind": "person", "name": "OST Test 2", "mail": "t2@x.test", "mri": "8:orgid:b", "oid": "b" }],
            "filetype": "Pdf" });
        let (url, b) = kql_request(&spec, "ten", "c", "l");
        assert!(url.ends_with("setflight=TurnOffMPLSuppressionTeams&domain=File"));
        let r = &b["EntityRequests"];
        assert_eq!(r.as_array().unwrap().len(), 1);
        assert_eq!(r[0]["EntityType"], "File");
        assert_eq!(r[0]["Size"], 10);
        assert_eq!(r[0]["Filter"]["And"][0]["Or"][0]["Term"]["FileType"], "Pdf");
        let a = &r[0]["Query"]["QueryAnnotations"];
        assert_eq!(a[0]["Type"], "Domain");
        assert_eq!(a[0]["DomainType"], "File");
        assert_eq!(a[1]["Type"], "People");
        assert_eq!(a[1]["KqlKeyword"], "From");
        assert_eq!(a[1]["Id"], "b@ten");
        // Messages with words: the domain, has: filters, and one person.
        let spec = json!({ "text": "is:Messages release has:@Mentions ", "words": "release", "scope": "messages", "mentions": true });
        let (url, b) = kql_request(&spec, "ten", "c", "l");
        assert!(url.ends_with("&domain=Message"));
        assert_eq!(
            b["EntityRequests"][0]["Filter"]["And"][0]["Or"][0]["Term"]["HasMentions"],
            "True"
        );
        assert_eq!(b["EntityRequests"][1]["EntityType"], "People");
        assert_eq!(b["EntityRequests"][1]["Size"], 1);
        assert_eq!(
            b["EntityRequests"][1]["Query"]["DisplayQueryString"],
            "release"
        );
        // Meetings: the words alone; channels: the channel domain.
        let (url, b) = kql_request(
            &json!({ "text": "is:Meetings ", "words": "", "scope": "meetings" }),
            "",
            "c",
            "l",
        );
        assert!(url.ends_with("&domain=Event"));
        assert_eq!(b["EntityRequests"][0]["Query"]["QueryString"], "");
        let (url, b) = kql_request(
            &json!({ "text": "is:Channels ost", "words": "ost", "scope": "channels" }),
            "",
            "c",
            "l",
        );
        assert!(url.contains("EnableTeamsChannelDomainPowerbar&domain=TeamsChannel"));
        assert_eq!(b["EntityRequests"][0]["Size"], 8);
        assert_eq!(b["EntityRequests"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn pickers_and_goto_requests() {
        let spec = json!({ "text": "is:Files in:ost", "words": "", "scope": "files", "picker": "in", "picker_query": "ost" });
        let (url, b) = kql_request(&spec, "", "c", "l");
        assert!(url.ends_with("setflight=TurnOffMPLSuppressionTeams"));
        let types: Vec<&str> = b["EntityRequests"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r["EntityType"].as_str().unwrap())
            .collect();
        assert_eq!(types, ["Chat", "Channel", "Team", "People"]);
        assert_eq!(b["EntityRequests"][0]["Query"]["KqlKeyword"], "In");
        assert_eq!(
            b["EntityRequests"][0]["Query"]["NormalizedQueryString"],
            "ost"
        );
        // A picker's people leave out personal contacts.
        let sub = b["EntityRequests"][3]["Filter"]["And"][1]["Or"].to_string();
        assert!(!sub.contains("PersonalContact"));
        let (url, b) = kql_request(&json!({ "goto": true, "words": "ost" }), "", "c", "l");
        assert!(url.contains("scenario=powerbar.goto"));
        assert_eq!(b["Scenario"]["Name"], "powerbar.goto");
        let types: Vec<&str> = b["EntityRequests"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r["EntityType"].as_str().unwrap())
            .collect();
        assert_eq!(types, ["People", "Chat", "Team", "Channel"]);
    }

    #[test]
    fn scoped_replies_in_teams_groups() {
        let files = arrange_kql(
            &reply(),
            &json!({ "scope": "files", "words": "" }),
            &me(),
            &Names::new(),
        );
        assert_eq!(files["groups"][0]["id"], "FILES");
        assert_eq!(files["groups"][0]["title"], "Suggested files");
        assert_eq!(files["groups"][0]["items"].as_array().unwrap().len(), 3);
        // Typed: no heading.
        let typed = arrange_kql(
            &reply(),
            &json!({ "scope": "messages", "words": "release" }),
            &me(),
            &Names::new(),
        );
        assert_eq!(typed["groups"][0]["title"], "");
        assert_eq!(typed["groups"][0]["items"][0]["kind"], "message");
        // The in: picker: chats as in: places.
        let picker = arrange_kql(
            &reply(),
            &json!({ "scope": "files", "picker": "in" }),
            &me(),
            &Names::new(),
        );
        assert_eq!(picker["groups"][0]["id"], "GROUPCHATS");
        assert_eq!(picker["groups"][0]["items"][0]["kql"], "in");
        // From a person, no scope: them first, then their messages.
        let pcs = arrange_kql(
            &reply(),
            &json!({ "words": "", "picks": [{ "kw": "from", "kind": "person", "name": "Bob Smith", "oid": "b", "mri": "8:orgid:b" }] }),
            &me(),
            &Names::new(),
        );
        let ids: Vec<&str> = pcs["groups"]
            .as_array()
            .unwrap()
            .iter()
            .map(|g| g["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["TOPHITS", "MESSAGES", "FILES", "GROUPCHATS"]);
        assert_eq!(
            pcs["groups"][1]["items"]
                .as_array()
                .unwrap()
                .last()
                .unwrap()["from"],
            "Bob Smith"
        );
        // Only an in: place, no scope: its messages, files and chats.
        let place = arrange_kql(
            &reply(),
            &json!({ "words": "release", "picks": [{ "kw": "in", "kind": "chat", "name": "Release planning", "thread": "19:a@thread.v2" }] }),
            &me(),
            &Names::new(),
        );
        let ids: Vec<&str> = place["groups"]
            .as_array()
            .unwrap()
            .iter()
            .map(|g| g["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["MESSAGES", "FILES", "GROUPCHATS"]);
    }

    #[test]
    fn personal_accounts_named() {
        // The service names a Teams free person by their id (TASK-0376).
        let r = json!({ "Groups": [{ "Type": "Message", "Suggestions": [
            { "ClientThreadId": "19:uni01_x@thread.v2", "ThreadType": "Chat", "ThreadSubType": "OneOnOneChat", "ToPreview": [{ "DisplayName": "8:live:.cid.abc" }],
              "RecipientsCount": 1, "Preview": "hi", "From": { "EmailAddress": { "Name": "Ada Lovelace" }, "MRI": "8:orgid:aaaa" }, "ReferenceId": "m1" }]}]});
        assert_eq!(unnamed_people(&r), ["8:live:.cid.abc"]);
        let mut names = Names::new();
        names.insert("8:live:.cid.abc".into(), "OST Personal 2".into());
        let g = arrange(&r, "hi", &me(), vec![], &names);
        assert_eq!(g[0]["items"][0]["place"], "OST Personal 2");
        // Not found: the id stays, as Teams shows it.
        let g = arrange(&r, "hi", &me(), vec![], &Names::new());
        assert_eq!(g[0]["items"][0]["place"], "8:live:.cid.abc");
    }

    #[test]
    fn messages_backfill_as_teams() {
        // Captured on winpc 2026-11-28: is:Messages has:@Mentions with one
        // suggestion back, so Teams asks the search service too.
        let spec = json!({ "scope": "messages", "words": "", "mentions": true, "picks": [] });
        let arranged = json!({ "groups": [{ "id": "MESSAGES", "items": [{ "kind": "message", "id": "1795640822153" }] }] });
        assert!(wants_backfill(&spec, &arranged));
        let ten: Vec<Value> = (0..10).map(|i| json!({ "id": i.to_string() })).collect();
        assert!(!wants_backfill(
            &spec,
            &json!({ "groups": [{ "id": "MESSAGES", "items": ten }] })
        ));
        assert!(!wants_backfill(
            &json!({ "scope": "files" }),
            &json!({ "groups": [] })
        ));
        assert!(!wants_backfill(
            &json!({ "scope": "messages", "picker": "from" }),
            &json!({ "groups": [] })
        ));
        let body = backfill_body(
            &spec,
            "4287e791-1b98-4963-8b94-281c50472683",
            "t",
            "America/Los_Angeles",
            "c",
            "l",
        );
        let q = &body["entityRequests"][0]["query"];
        assert_eq!(
            q["queryString"],
            "mentions:4287e7911b9849638b94281c50472683 AND NOT (isClientSoftDeleted:TRUE) *"
        );
        assert_eq!(q["displayQueryString"], "*");
        assert_eq!(body["entityRequests"][0]["size"], 25);
        assert_eq!(
            body["scenario"]["Dimensions"][0]["DimensionValue"],
            "PowerbarTypeAheadMsg"
        );
        // in:<channel> with words; from:<person> as Teams annotates it.
        let inch = json!({ "scope": "messages", "words": "test", "picks": [{ "kw": "in", "kind": "channel", "thread": "19:7826@thread.tacv2", "group": "g" }] });
        assert_eq!(
            backfill_body(&inch, "o", "t", "UTC", "c", "l")["entityRequests"][0]["query"]["queryString"],
            "clientthreadid:19:7826@thread.tacv2 AND NOT (isClientSoftDeleted:TRUE) test"
        );
        let from = json!({ "scope": "messages", "words": "release", "picks": [{ "kw": "from", "kind": "person", "mail": "ost-test2@x.com", "oid": "9edc" }] });
        let q =
            backfill_body(&from, "o", "t", "UTC", "c", "l")["entityRequests"][0]["query"].clone();
        assert_eq!(
            q["queryString"],
            "NOT (isClientSoftDeleted:TRUE) ost-test2@x.com release"
        );
        assert_eq!(
            q["queryAnnotations"][0],
            json!({ "type": "People", "text": "ost-test2@x.com", "userId": "9edc", "tenantId": "t" })
        );

        // The reply's messages as rows, after the suggestions' (one already
        // listed is left out).
        let reply = json!({ "EntitySets": [{ "ResultSets": [{ "Results": [
            { "Type": "Message", "HitHighlightedSummary": "OST Test 1 can you confirm the <c0>Ubuntu</c0> package?",
              "Source": { "InternetMessageId": "1795640822153", "ClientThreadId": "19:5c15@thread.v2", "DateTimeSent": "2026-11-25T21:07:02.153Z",
                "DisplayTo": "OST Test 1; OST Test 3", "Sender": { "EmailAddress": { "Name": "OST Test 2" } }, "MentionsPreview": { "IsMentioned": true },
                "Extensions": { "SkypeSpaces_ConversationPost_Extension_ThreadType": "chat", "SkypeSpaces_ConversationPost_Extension_Topic": "Release planning",
                  "SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId": "8:orgid:9edc", "SkypeSpaces_ConversationPost_Extension_ConversationType": "GroupChat" } } },
            { "Type": "Message", "HitHighlightedSummary": "The meeting &quot;OST CAL&quot; is cancelled",
              "Source": { "InternetMessageId": "1794919274462", "ClientThreadId": "19:7826@thread.tacv2", "DateTimeSent": "2026-11-17T12:41:14.462Z",
                "DisplayTo": "OST Test Team", "TeamName": "OST Test Team", "ChannelName": "OST test channel", "GroupId": "g",
                "Sender": { "EmailAddress": { "Name": "OST Test 1" } },
                "Extensions": { "SkypeSpaces_ConversationPost_Extension_ThreadType": "topic", "SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId": "8:orgid:me",
                  "SkypeSpaces_ConversationPost_Extension_ParentMessageId": "1794919204110" } } }
        ]}]}]});
        let rows = backfill_messages(&reply, &me(), &Names::new());
        assert_eq!(rows.len(), 2);
        assert_eq!(
            rows[0]["title"],
            "OST Test 1 can you confirm the Ubuntu package?"
        );
        assert_eq!(rows[0]["topic"], "Release planning");
        assert_eq!(rows[0]["prefix"], "OST: ");
        assert_eq!(rows[0]["icons"], json!(["mention"]));
        assert_eq!(rows[1]["place"], "OST Test Team > OST test channel");
        assert_eq!(rows[1]["title"], "The meeting \"OST CAL\" is cancelled");
        assert_eq!(rows[1]["parent"], "1794919204110");
        assert_eq!(rows[1]["channel"], true);
        let mut arranged = arranged.clone();
        merge_backfill(&mut arranged, rows);
        let ids: Vec<&str> = arranged["groups"][0]["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|m| m["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["1795640822153", "1794919274462"]);
        // Nothing from the suggestions: the backfill's alone, no heading.
        let mut none = json!({ "groups": [] });
        merge_backfill(&mut none, backfill_messages(&reply, &me(), &Names::new()));
        assert_eq!(none["groups"][0]["id"], "MESSAGES");
        assert_eq!(none["groups"][0]["title"], "");
    }

    #[test]
    fn affinity_scaled_as_teams() {
        let r = json!({ "value": [{
            "UGCScore": [{ "ThreadId": "19:a@thread.v2", "Score": 4.0 }, { "ThreadId": "19:b@thread.v2", "Score": 2.0 }, { "ThreadId": "19:c@thread.v2", "Score": -1 }],
            "UCScore": [{ "ThreadId": "19:ch@thread.tacv2", "Score": 1.0, "ScoreV2": 3.0 }],
            "UTScore": []
        }]});
        let a = affinity_scores(&r);
        assert_eq!(a["scores"]["19:a@thread.v2"], 1.0);
        // The lowest scales to 0 (and counts as none); -1 is no score.
        assert!(a["scores"].get("19:b@thread.v2").is_none());
        assert!(a["scores"].get("19:c@thread.v2").is_none());
        assert_eq!(a["means"]["UGCMean"], 0.5);
        // One score alone: Teams' z-score is NaN, read as 0.
        assert!(a["scores"].get("19:ch@thread.tacv2").is_none());
        assert_eq!(a["means"]["UTMean"], 0.0);
    }
}
