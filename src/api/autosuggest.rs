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
            {
                "Query": { "QueryString": query, "DisplayQueryString": query, "NormalizedQueryString": query },
                "EntityType": "People", "Size": 5,
                "Fields": ["Id", "MRI", "DisplayName", "EmailAddresses", "PeopleType", "PeopleSubtype", "Phones", "UserPrincipalName", "GivenName", "Surname", "Cid", "CompanyName", "JobTitle", "ImAddress", "ExternalDirectoryObjectId", "ConcatenatedId", "Department"],
                "Filter": { "And": [
                    { "Or": [{ "Term": { "PeopleType": "Person" } }, { "Term": { "PeopleType": "Other" } }] },
                    { "Or": [{ "Term": { "PeopleSubtype": "OrganizationUser" } }, { "Term": { "PeopleSubtype": "MTOUser" } }, { "Term": { "PeopleSubtype": "PersonalContact" } }, { "Term": { "PeopleSubtype": "Guest" } }] },
                    { "Or": [{ "Term": { "Flags": "NonHidden" } }] }
                ] },
                "Provenances": ["Mailbox", "Directory"], "From": 0
            },
            { "Query": q, "EntityType": "File", "Size": 3 },
            { "Query": q, "EntityType": "Chat", "Size": 5 },
            { "Query": q, "EntityType": "Team", "Size": 3 },
            { "Query": q, "EntityType": "Channel", "Size": 4, "Filter": { "Or": [{ "Term": { "ChannelType": "Standard" } }, { "Term": { "ChannelType": "Shared" } }] } },
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

/// Ask the suggestions service, with Teams' headers: the zero-query GET
/// for an empty `query`, else the typed POST.
pub async fn fetch(query: &str, me: &Me, tenant: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for(SCOPE)
        .await
        .context("Suggestions token")?;
    let (cvid, logical) = (
        uuid::Uuid::new_v4().to_string(),
        uuid::Uuid::new_v4().to_string(),
    );
    let request_id = uuid::Uuid::new_v4().to_string();
    let client = reqwest::Client::new();
    let mut req = if query.trim().is_empty() {
        client.get(format!(
            "{URL}?scenario=powerbar&query=&cvid={cvid}&logicalId={logical}"
        ))
    } else {
        client
            .post(format!("{URL}?scenario=powerbar&setflight={SET_FLIGHT}"))
            .json(&typed_body(query, &cvid, &logical))
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
fn chat(r: &Value, me: &Me) -> Value {
    let total = r["TotalChatMembersCount"].as_u64().unwrap_or(0) as usize;
    let names: Vec<String> = r["MatchingMembers"]
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
        .filter_map(|m| m["DisplayName"].as_str().filter(|n| !n.is_empty()))
        .map(first_name)
        .collect();
    let members = join_names(&names, total.saturating_sub(1));
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
fn message(r: &Value, me: &Me) -> Value {
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
        .filter_map(|t| t["DisplayName"].as_str().map(str::to_string))
        .collect();
    let people = match r["ToPreview"].as_array().map(|a| a.len()).unwrap_or(0) {
        1 => {
            let n = s(&r["ToPreview"][0]["DisplayName"]);
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

fn convert(group: &str, r: &Value, query: &str, me: &Me) -> Option<Value> {
    Some(match group {
        "People" => person(r, me)?,
        "Chat" => chat(r, me),
        "Team" => team(r),
        "Channel" => channel(r),
        "File" => file(r),
        "Event" => event(r, query, me),
        "Text" => text(r),
        "Message" => message(r, me),
        _ => return None,
    })
}

/// A group of suggestions under its heading (Teams' strings).
fn group(id: &str, title: String, items: Vec<Value>) -> Value {
    json!({ "id": id, "title": title, "items": items })
}

/// The suggestions in Teams' groups; see the module comment. Empty groups
/// are left out. `people` is the zero-query People row (Teams' top-N).
pub fn arrange(reply: &Value, query: &str, me: &Me, people: Vec<Value>) -> Vec<Value> {
    // Every suggestion by group, with its reference.
    let mut by_group: Vec<(String, Vec<(String, Value)>)> = Vec::new();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        let name = s(&g["Type"]);
        let items: Vec<(String, Value)> = g["Suggestions"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|r| Some((s(&r["ReferenceId"]), convert(&name, r, query, me)?)))
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
        let images: Vec<Value> = all_messages
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
            .take(IMAGES)
            .collect();
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
        let g = arrange(&reply(), "release", &me(), vec![]);
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
        let g = arrange(&reply(), "", &me(), people);
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
    fn channel_folder_from_address() {
        assert_eq!(
            channel_folder(
                "https://x/sites/T/Shared%20Documents/OST%20test%20channel/a.loop?web=1"
            ),
            "OST test channel"
        );
        assert_eq!(channel_folder("https://x/personal/a/Documents/a.loop"), "");
    }
}
