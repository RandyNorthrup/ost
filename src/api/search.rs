//! Teams' search results page (Enter in the title bar's search; measured
//! on winpc 2026-11-10): Substrate's search service with the requests Teams
//! sends per tab. The bodies are Teams' own (src/api/search_requests/*.json,
//! `{QUERY}` and `{TZ}` filled in); the filters change their query strings
//! as Teams' do.

use anyhow::Result;

use super::find::{self, Found, Hit};

/// The page's tabs.
pub const TABS: [&str; 8] = [
    "all",
    "messages",
    "files",
    "people",
    "channels",
    "groupchats",
    "meetings",
    "images",
];

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
    /// Files in Grid view: Teams asks for 24 a page (25 in List view).
    pub grid: bool,
}

const THREAD_TYPE: &str =
    "Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)";
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
        terms.push(format!(
            "mentions:{}",
            my_oid.replace('-', "").to_ascii_lowercase()
        ));
    }
    match (f.in_kind.as_str(), f.kind.as_str()) {
        ("chat", _) if !f.in_thread.is_empty() => {
            terms.push(format!("clientthreadid:{}", f.in_thread));
            terms.push(format!("NOT ({THREAD_TYPE})"));
        }
        // A channel or a team: its thread only (a team's is its General
        // channel's); the team goes in a filter term (both captured from
        // Teams, 2026-11-11 and 2026-11-13).
        ("channel" | "team", _) if !f.in_thread.is_empty() => {
            terms.push(format!("clientthreadid:{}", f.in_thread))
        }
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
        q.push_str(if all_tab && f.person_mail.is_empty() {
            " AND "
        } else {
            " "
        });
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
        "Europe/Berlin" | "Europe/Amsterdam" | "Europe/Rome" | "Europe/Stockholm"
        | "Europe/Vienna" | "Europe/Zurich" | "Europe/Oslo" => "W. Europe Standard Time",
        "Europe/Paris" | "Europe/Brussels" | "Europe/Madrid" | "Europe/Copenhagen" => {
            "Romance Standard Time"
        }
        "Europe/Warsaw" | "Europe/Prague" | "Europe/Budapest" => "Central European Standard Time",
        "Europe/Helsinki" | "Europe/Kyiv" | "Europe/Riga" | "Europe/Vilnius" | "Europe/Tallinn" => {
            "FLE Standard Time"
        }
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
    let key = if body.get("EntityRequests").is_some() {
        "EntityRequests"
    } else {
        "entityRequests"
    };
    body.get_mut(key).and_then(|v| v.as_array_mut())
}

fn query_obj(r: &mut serde_json::Value) -> Option<&mut serde_json::Value> {
    let key = if r.get("Query").is_some() {
        "Query"
    } else {
        "query"
    };
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
pub fn bodies(
    tab: &str,
    keywords: &str,
    f: &Filters,
    from: usize,
    timezone: &str,
    my_oid: &str,
    tenant: &str,
) -> Vec<serde_json::Value> {
    let names: Vec<&str> = if tab == "images" {
        vec!["images-messages", "images-files"]
    } else {
        vec![tab]
    };
    let quoted = |s: &str| serde_json::to_string(s).unwrap_or_default();
    let mut out = Vec::new();
    for name in names {
        let Some(t) = template(name) else { continue };
        // Placeholders sit inside JSON strings: fill them escaped.
        let text = t
            .replace("{QUERY}", quoted(keywords).trim_matches('"'))
            .replace("{TZ}", quoted(timezone).trim_matches('"'))
            .replace("{WINTZ}", windows_zone(timezone));
        let Ok(mut body) = serde_json::from_str::<serde_json::Value>(&text) else {
            continue;
        };
        body["cvid"] = uuid::Uuid::new_v4().to_string().into();
        body["logicalId"] = uuid::Uuid::new_v4().to_string().into();
        let all_tab = tab == "all";
        if let Some(reqs) = entity_requests(&mut body) {
            for r in reqs.iter_mut() {
                let kind = r
                    .get("entityType")
                    .or_else(|| r.get("EntityType"))
                    .and_then(|k| k.as_str())
                    .unwrap_or_default()
                    .to_string();
                let qs = match kind.as_str() {
                    "Message" if name == "images-messages" => None,
                    "Message" => Some(message_query(keywords, f, my_oid, all_tab)),
                    "File" if name == "images-files" => None,
                    "File" => Some(file_query(keywords, f)),
                    _ => None,
                };
                if let Some(q) = query_obj(r) {
                    if let Some(qs) = qs {
                        let key = if q.get("QueryString").is_some() {
                            "QueryString"
                        } else {
                            "queryString"
                        };
                        q[key] = qs.into();
                    }
                    if matches!(kind.as_str(), "Message" | "File")
                        && let Some(p) = people_note(f, tenant)
                    {
                        q["queryAnnotations"] = serde_json::json!([p]);
                    }
                }
                if kind == "Message" && name != "images-messages" {
                    if matches!(f.in_kind.as_str(), "team" | "channel") && !f.in_group.is_empty() {
                        r["Filter"] = serde_json::json!({ "Term": { "GroupId": f.in_group } });
                    } else if f.in_thread.is_empty() && f.kind == "chat" {
                        r["Filter"] =
                            serde_json::json!({ "Term": { "ConversationType": "OneToOne" } });
                    }
                    // (Type ▸ Channel sends no filter term, as Teams.)
                }
                if kind == "File" && name == "files" && f.grid {
                    let key = if r.get("Size").is_some() {
                        "Size"
                    } else {
                        "size"
                    };
                    r[key] = 24.into();
                }
                if from > 0 {
                    let key = if r.get("From").is_some() {
                        "From"
                    } else {
                        "from"
                    };
                    r[key] = from.into();
                }
            }
        }
        if let Some(a) = body
            .get_mut("AnswerEntityRequests")
            .and_then(|v| v.as_array_mut())
        {
            for r in a {
                let key = if r.get("From").is_some() {
                    "From"
                } else {
                    "from"
                };
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
    /// Communities (Viva Engage's groups).
    #[serde(default)]
    pub communities: Vec<CommunityHit>,
}

/// A Viva Engage community found by Teams' Communities tab.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct CommunityHit {
    pub id: String,
    pub name: String,
    pub description: String,
    /// The picture's address template ("{width}x{height}" to fill in).
    pub avatar: String,
    pub official: bool,
    /// "MEMBER", "NOT_MEMBER", "PENDING"…
    pub membership: String,
    /// "PUBLIC" / "PRIVATE".
    pub privacy: String,
}

/// Teams' Communities search (captured 2026-11-13): Viva Engage's GraphQL
/// `CommunitySearchTeams` at www.yammer.com/graphql with the user's token for
/// https://web.yammer.com/teams.
pub const COMMUNITY_SEARCH: &str = "\n  query CommunitySearchTeams($query: String!) {\n    search(query: $query) {\n      groups(first: 25) {\n        edges {\n          node {\n            id\n            displayName\n            description\n            avatarUrlTemplate\n            isOfficial\n            viewerMembershipStatus\n            privacy\n            hasDefaultAvatar\n          }\n        }\n        pageInfo {\n          hasNextPage\n          endCursor\n        }\n      }\n    }\n  }\n";

/// The communities in a CommunitySearchTeams reply.
pub fn read_communities(reply: &serde_json::Value) -> Vec<CommunityHit> {
    reply
        .pointer("/data/search/groups/edges")
        .and_then(|e| e.as_array())
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let n = e.get("node")?;
            Some(CommunityHit {
                id: s(&n["id"]),
                name: s(&n["displayName"]),
                description: s(&n["description"]),
                avatar: if n["hasDefaultAvatar"].as_bool() == Some(true) {
                    String::new()
                } else {
                    s(&n["avatarUrlTemplate"])
                },
                official: n["isOfficial"].as_bool().unwrap_or(false),
                membership: s(&n["viewerMembershipStatus"]),
                privacy: s(&n["privacy"]),
            })
        })
        .collect()
}

/// Search Viva Engage's communities as Teams' Communities tab does.
pub async fn communities(keywords: &str) -> Result<Vec<CommunityHit>> {
    let token =
        crate::auth::oauth::access_token_for("https://web.yammer.com/teams/.default").await?;
    let body = serde_json::json!({ "query": COMMUNITY_SEARCH, "operationName": "CommunitySearchTeams", "variables": { "query": keywords } });
    let reply: serde_json::Value = reqwest::Client::new()
        .post("https://www.yammer.com/graphql")
        .bearer_auth(token)
        .header("content-type", "application/json")
        .header("referer", "https://teams.microsoft.com/")
        .json(&body)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(read_communities(&reply))
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
        page.terms = reply["SearchTerms"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|t| t.as_str().map(str::to_string))
            .collect();
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
                page.chats = rs["Results"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|r| {
                        let src = &r["Source"];
                        ChatHit {
                            thread: s(&src["ThreadId"]),
                            name: s(&src["Name"]),
                            thread_type: s(&src["ThreadType"]),
                            members: src["Members"]
                                .as_array()
                                .into_iter()
                                .flatten()
                                .filter_map(|m| m.as_str().map(str::to_string))
                                .collect(),
                            member_mris: src["ChatMembers"]
                                .as_array()
                                .into_iter()
                                .flatten()
                                .map(|m| s(&m["MRI"]))
                                .collect(),
                            member_count: src["TotalChatMembersCount"].as_u64().unwrap_or_default(),
                            last_message: s(&src["LastMessageTime"]),
                        }
                    })
                    .collect();
            }
            "TeamsChannel" => {
                page.channels_total = total;
                page.channels = rs["Results"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|r| {
                        let src = &r["Source"];
                        ChannelHit {
                            thread: s(&src["ThreadId"]),
                            name: s(&src["Name"]),
                            team: s(&src["TeamName"]),
                            group: s(&src["GroupId"]),
                            channel_type: s(&src["ChannelType"]),
                        }
                    })
                    .collect();
            }
            "People" => {
                page.people_total = total;
                page.people = rs["Results"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|r| {
                        let src = &r["Source"];
                        let mail = src["EmailAddresses"]
                            .as_array()
                            .and_then(|a| a.first())
                            .map(s)
                            .filter(|m| !m.is_empty())
                            .unwrap_or_else(|| s(&src["UserPrincipalName"]));
                        PersonHit {
                            mri: s(&src["MRI"]),
                            name: s(&src["DisplayName"]),
                            mail,
                            title: s(&src["JobTitle"]),
                            department: s(&src["Department"]),
                            company: s(&src["CompanyName"]),
                        }
                    })
                    .collect();
            }
            _ => {}
        }
    }
    for set in reply["AnswerEntitySets"].as_array().into_iter().flatten() {
        let rs = &set["ResultSets"][0];
        let events: Vec<EventHit> = rs["Results"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|r| r["Source"].get("Subject").is_some())
            .map(|r| {
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
                    join_url: [
                        &src["OnlineMeeting"]["JoinUrl"],
                        &src["ParsedBodyInfo"]["OnlineMeetingUrl"],
                    ]
                    .iter()
                    .map(|v| s(v))
                    .find(|u| !u.is_empty())
                    .unwrap_or_default(),
                    web_link: s(&src["WebLink"]),
                }
            })
            .collect();
        if !events.is_empty() {
            page.events_total = rs["Total"]
                .as_u64()
                .unwrap_or(events.len() as u64)
                .max(events.len() as u64);
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
                .map(|e| {
                    (
                        e["Position"].as_u64().unwrap_or(99),
                        section(e["EntityType"].as_str().unwrap_or_default()).to_string(),
                    )
                })
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
    let token =
        crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
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
        .post(
            "https://substrate.office.com/search/api/v1/suggestions?scenario=peoplepicker.newChat",
        )
        .bearer_auth(token)
        .json(&body)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(v)
}

/// Teams' share and forward picker ("Add recipients"): Substrate's
/// peoplepicker.newChat suggestions for people, chats, channels and teams,
/// in its best-match order, as {kind, oid, id, name, sub, upn}. People are
/// "person" (their object id); chats, channels and teams are "chat" (the
/// thread to post to). Their second line is Teams': a person's sign-in name
/// before "@" in capitals (with the job title after it in brackets), a
/// channel's team.
pub async fn recipients(keyword: &str, my_oid: &str) -> Result<Vec<serde_json::Value>> {
    let token =
        crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let reply: serde_json::Value = reqwest::Client::new()
        .post(
            "https://substrate.office.com/search/api/v1/suggestions?scenario=peoplepicker.newChat",
        )
        .bearer_auth(token)
        .json(&recipients_body(keyword))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(parse_recipients(&reply, my_oid))
}

pub fn recipients_body(keyword: &str) -> serde_json::Value {
    let q = serde_json::json!({ "QueryString": keyword, "DisplayQueryString": keyword });
    serde_json::json!({
        "EntityRequests": [
            {
                "Query": q, "EntityType": "People", "Size": 20,
                "Fields": ["Id", "MRI", "DisplayName", "EmailAddresses", "PeopleType", "PeopleSubtype", "Phones", "UserPrincipalName", "GivenName", "Surname", "Cid", "CompanyName", "JobTitle", "ImAddress", "ExternalDirectoryObjectId", "ConcatenatedId", "Department"],
                "Filter": { "And": [
                    { "Or": [{ "Term": { "PeopleType": "Person" } }, { "Term": { "PeopleType": "Other" } }, { "Term": { "PeopleType": "Group" } }] },
                    { "Or": [{ "Term": { "PeopleSubtype": "OrganizationUser" } }, { "Term": { "PeopleSubtype": "PendingOrgContact" } }, { "Term": { "PeopleSubtype": "OrgContact" } }, { "Term": { "PeopleSubtype": "Guest" } }, { "Term": { "PeopleSubtype": "PublicDistributionList" } }, { "Term": { "PeopleSubtype": "UnifiedGroup" } }] },
                    { "Or": [{ "Term": { "Flags": "NonHidden" } }] }
                ] },
                "Provenances": ["Mailbox", "Directory", "SecurityGroups", "ExtendedDirectory"], "From": 0, "ServeNoEmailContacts": true
            },
            { "Query": { "QueryString": keyword }, "EntityType": "Chat", "Size": 20 },
            { "Query": { "QueryString": keyword }, "EntityType": "Channel", "Size": 20, "Filter": { "Or": [{ "Term": { "ChannelType": "Standard" } }, { "Term": { "ChannelType": "Shared" } }] } },
            { "Query": { "QueryString": keyword }, "EntityType": "Team", "Size": 20 }
        ],
        "Scenario": { "Name": "peoplepicker.newChat" },
        "Cvid": uuid::Uuid::new_v4().to_string(),
        "AppName": "Microsoft Teams",
        "LogicalId": uuid::Uuid::new_v4().to_string(),
    })
}

/// The suggestions in Teams' order (LayoutHints.BestMatchSuggestions, then
/// any left over). Groups (Microsoft 365 groups and lists) are left out:
/// OST doesn't post to them.
pub fn parse_recipients(reply: &serde_json::Value, my_oid: &str) -> Vec<serde_json::Value> {
    let s = |v: &serde_json::Value| v.as_str().unwrap_or_default().to_string();
    let mut by_ref: Vec<(String, serde_json::Value)> = Vec::new();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        let group = g["Type"].as_str().unwrap_or_default();
        for r in g["Suggestions"].as_array().into_iter().flatten() {
            let item = match group {
                "People"
                    if r["PeopleType"] == "Person"
                        || r["PeopleSubtype"] == "Guest"
                        || crate::identity::work_object_id(&s(&r["MRI"])).is_some() =>
                {
                    // A directory person (guests included); one known only
                    // as a contact by its Teams id.
                    let mut oid = s(&r["ExternalDirectoryObjectId"]).to_ascii_lowercase();
                    if oid.is_empty() {
                        oid = crate::identity::mri_id(&s(&r["MRI"])).to_ascii_lowercase();
                    }
                    let upn = s(&r["UserPrincipalName"]);
                    let alias = upn.split('@').next().unwrap_or_default().to_uppercase();
                    let job = s(&r["JobTitle"]);
                    let guest = r["PeopleSubtype"] == "Guest";
                    let sub = if !job.is_empty() {
                        if alias.is_empty() {
                            job
                        } else {
                            format!("({alias}) {job}")
                        }
                    } else if !guest {
                        alias
                    } else {
                        r["EmailAddresses"][0]
                            .as_str()
                            .map(str::to_string)
                            .unwrap_or(upn.clone())
                    };
                    let plain = s(&r["DisplayName"]);
                    // You: "<name> (You)" (Teams' self tag, in the app
                    // language); `plain_name` is the name alone.
                    if !my_oid.is_empty() && oid == my_oid.to_ascii_lowercase() {
                        let name = format!(
                            "{plain} {}",
                            crate::i18n::tr_id("(You)", "autosuggest:k9m83y7y2")
                        );
                        serde_json::json!({ "kind": "person", "oid": oid, "name": name, "plain_name": plain, "you": true, "sub": sub, "upn": upn, "guest": guest })
                    } else {
                        serde_json::json!({ "kind": "person", "oid": oid, "name": plain, "sub": sub, "upn": upn, "guest": guest })
                    }
                }
                "Chat" => {
                    serde_json::json!({ "kind": "chat", "id": s(&r["ThreadId"]), "name": s(&r["Name"]), "sub": "", "thread_type": s(&r["ThreadType"]) })
                }
                "Channel" => {
                    serde_json::json!({ "kind": "chat", "id": s(&r["ThreadId"]), "name": s(&r["Name"]), "sub": s(&r["TeamName"]), "thread_type": "channel", "group": s(&r["GroupId"]) })
                }
                "Team" => {
                    serde_json::json!({ "kind": "chat", "id": s(&r["ThreadId"]), "name": s(&r["Name"]), "sub": "", "thread_type": "team", "group": s(&r["GroupId"]) })
                }
                _ => continue,
            };
            by_ref.push((s(&r["ReferenceId"]), item));
        }
    }
    let mut out = Vec::new();
    for hint in reply["LayoutHints"]["BestMatchSuggestions"]
        .as_array()
        .into_iter()
        .flatten()
    {
        if let Some(i) = by_ref
            .iter()
            .position(|(r, _)| r == hint["ReferenceId"].as_str().unwrap_or_default())
        {
            let mut v = by_ref.remove(i).1;
            v["best"] = serde_json::Value::Bool(true);
            out.push(v);
        }
    }
    out.extend(by_ref.into_iter().map(|(_, v)| v));
    out
}

/// The new chat form's request (Teams' peoplepicker.newChat as its To: box
/// sends it, captured on winpc 2026-11-20): people (organization users,
/// cross-tenant users, guests, distribution lists and Microsoft 365
/// groups), chats, channels and teams.
pub fn new_chat_body(keyword: &str) -> serde_json::Value {
    let q = serde_json::json!({ "QueryString": keyword, "DisplayQueryString": keyword });
    serde_json::json!({
        "EntityRequests": [
            {
                "Query": q, "EntityType": "People", "Size": 20,
                "Fields": ["Id", "MRI", "DisplayName", "EmailAddresses", "PeopleType", "PeopleSubtype", "Phones", "UserPrincipalName", "GivenName", "Surname", "Cid", "CompanyName", "JobTitle", "ImAddress", "ExternalDirectoryObjectId", "ConcatenatedId", "Department"],
                "Filter": { "And": [
                    { "Or": [{ "Term": { "PeopleType": "Person" } }, { "Term": { "PeopleType": "Other" } }, { "Term": { "PeopleType": "Group" } }] },
                    { "Or": [{ "Term": { "PeopleSubtype": "OrganizationUser" } }, { "Term": { "PeopleSubtype": "MTOUser" } }, { "Term": { "PeopleSubtype": "Guest" } }, { "Term": { "PeopleSubtype": "PublicDistributionList" } }, { "Term": { "PeopleSubtype": "UnifiedGroup" } }] },
                    { "Or": [{ "Term": { "Flags": "NonHidden" } }] }
                ] },
                "Provenances": ["Mailbox", "Directory", "SecurityGroups"], "From": 0, "ServeNoEmailContacts": true
            },
            { "Query": { "QueryString": keyword }, "EntityType": "Chat", "Size": 20 },
            { "Query": { "QueryString": keyword }, "EntityType": "Channel", "Size": 20, "Filter": { "Or": [{ "Term": { "ChannelType": "Standard" } }, { "Term": { "ChannelType": "Shared" } }] } },
            { "Query": { "QueryString": keyword }, "EntityType": "Team", "Size": 20 }
        ],
        "Scenario": { "Name": "peoplepicker.newChat" },
        "Cvid": uuid::Uuid::new_v4().to_string(),
        "AppName": "Microsoft Teams",
        "LogicalId": uuid::Uuid::new_v4().to_string(),
    })
}

/// The x-client-flights Teams sends with the new chat form's suggestions.
pub const NEW_CHAT_FLIGHTS: &str = "EnableSelfSuggestion,TeamsHiddenPeopleDirectorySearch";

/// A chat in your chat list, for the new chat form's local chat search.
#[derive(Debug, Clone, Default)]
pub struct LocalChat {
    pub id: String,
    /// Its own name (a group chat's topic); empty for an unnamed chat.
    pub topic: String,
    pub group: bool,
    pub meeting: bool,
    /// Its last activity (ms), newest first within a rank.
    pub time: i64,
    /// A channel of one of your teams: its team's name ("" for a chat).
    pub channel_team: String,
}

/// The new chat form's typed suggestions, as Teams lists them.
pub async fn new_chat_suggestions(
    keyword: &str,
    my_oid: &str,
    local: &[LocalChat],
) -> Result<Vec<serde_json::Value>> {
    let token =
        crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    // Teams' flights for this call (captured on winpc 2026-11-21): with
    // EnableSelfSuggestion Substrate lists you too ("OST Test 1 (You)").
    let reply: serde_json::Value = reqwest::Client::new()
        .post(
            "https://substrate.office.com/search/api/v1/suggestions?scenario=peoplepicker.newChat",
        )
        .bearer_auth(token)
        .header("x-client-flights", NEW_CHAT_FLIGHTS)
        .header("x-client-version", "T2.1")
        .json(&new_chat_body(keyword))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(new_chat_arrange(&reply, my_oid, local, keyword))
}

/// Teams' local chat match (worker 54954 with the matcher 68583): every
/// word typed starts a word of the chat's name, without case or accents;
/// the rank class (exact 1, the name starting with what was typed 2, the
/// rest 4) or None.
fn local_chat_rank(name: &str, query: &str) -> Option<u8> {
    let fold = |s: &str| s.to_lowercase();
    let words = |s: &str| {
        fold(s)
            .split(|c: char| !c.is_alphanumeric())
            .filter(|w| !w.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>()
    };
    let (n, q) = (words(name), words(query));
    if q.is_empty()
        || !q
            .iter()
            .all(|t| n.iter().any(|w| w.starts_with(t.as_str())))
    {
        return None;
    }
    let (fname, fq) = (fold(name.trim()), fold(query.trim()));
    Some(if fname == fq {
        1
    } else if fname.starts_with(&fq) {
        2
    } else {
        4
    })
}

/// Teams' typed suggestions (worker resolver 81199, slots 964128; checked
/// against Teams on winpc 2026-11-20: "OST" gives 22 rows in a 225 px
/// list). People are Substrate's in its order, without anyone lacking an
/// id or a name (you are "<name> (You)"); group chats are Substrate's that
/// are in your chat list (not meeting chats), with your own matching named
/// chats (the first at the third place, the rest after); then channels,
/// teams and distribution lists. The slots, in order: 5 people, 5
/// federated people and bots (none here), 3 group chats, 3 channels, 1
/// team, 2 distribution lists, 15 more people, then what didn't fit, up to
/// 22. Items: {kind: person|chat|channel|team|dl, id, name, sub, …}.
pub fn new_chat_arrange(
    reply: &serde_json::Value,
    my_oid: &str,
    local: &[LocalChat],
    query: &str,
) -> Vec<serde_json::Value> {
    let s = |v: &serde_json::Value| v.as_str().unwrap_or_default().to_string();
    let (mut people, mut dls, mut chats, mut channels, mut teams) =
        (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut seen: std::collections::HashSet<String> = Default::default();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        for r in g["Suggestions"].as_array().into_iter().flatten() {
            match g["Type"].as_str().unwrap_or_default() {
                "People" => {
                    let name = s(&r["DisplayName"]);
                    let subtype = r["PeopleSubtype"].as_str().unwrap_or_default();
                    if matches!(subtype, "PublicDistributionList" | "UnifiedGroup") {
                        let mail = r["EmailAddresses"][0]
                            .as_str()
                            .map(str::to_string)
                            .unwrap_or_default();
                        let id = s(&r["ExternalDirectoryObjectId"]).to_ascii_lowercase();
                        let key = if id.is_empty() {
                            mail.to_ascii_lowercase()
                        } else {
                            id.clone()
                        };
                        if name.is_empty() || key.is_empty() || !seen.insert(key.clone()) {
                            continue;
                        }
                        dls.push(serde_json::json!({ "kind": "dl", "id": key, "name": name, "sub": mail, "unified": subtype == "UnifiedGroup" }));
                        continue;
                    }
                    // The person's object id (from their Teams id when
                    // Substrate leaves it out, as it does for you).
                    let mut id = s(&r["ExternalDirectoryObjectId"]).to_ascii_lowercase();
                    if id.is_empty() {
                        id = crate::identity::work_object_id(&s(&r["MRI"]))
                            .unwrap_or_default()
                            .to_ascii_lowercase();
                    }
                    if id.is_empty() || name.is_empty() || !seen.insert(id.clone()) {
                        continue;
                    }
                    let upn = s(&r["UserPrincipalName"]);
                    let alias = upn.split('@').next().unwrap_or_default().to_uppercase();
                    let job = s(&r["JobTitle"]);
                    let guest = subtype == "Guest";
                    let sub = if !job.is_empty() {
                        if alias.is_empty() {
                            job
                        } else {
                            format!("({alias}) {job}")
                        }
                    } else if !guest {
                        alias
                    } else {
                        r["EmailAddresses"][0]
                            .as_str()
                            .map(str::to_string)
                            .unwrap_or(upn.clone())
                    };
                    let you = !my_oid.is_empty() && id == my_oid.to_ascii_lowercase();
                    let shown = if you {
                        format!(
                            "{name} {}",
                            crate::i18n::tr_id("(You)", "autosuggest:k9m83y7y2")
                        )
                    } else {
                        name.clone()
                    };
                    people.push(serde_json::json!({ "kind": "person", "id": id, "name": shown, "plain_name": name, "you": you, "sub": sub, "upn": upn, "guest": guest }));
                }
                "Chat" => {
                    let id = s(&r["ThreadId"]);
                    let known = local.iter().find(|c| c.id == id);
                    let name = known
                        .map(|c| c.topic.clone())
                        .filter(|t| !t.is_empty())
                        .unwrap_or_else(|| s(&r["Name"]));
                    // Only chats in your list (Teams looks them up locally),
                    // not meeting chats, and not nameless ones.
                    if known.is_none_or(|c| c.meeting)
                        || name.is_empty()
                        || !seen.insert(id.clone())
                    {
                        continue;
                    }
                    chats.push(
                        serde_json::json!({ "kind": "chat", "id": id, "name": name, "sub": "" }),
                    );
                }
                "Channel" => {
                    let id = s(&r["ThreadId"]);
                    if s(&r["Name"]).is_empty() || !seen.insert(format!("ch:{id}")) {
                        continue;
                    }
                    channels.push(serde_json::json!({ "kind": "channel", "id": id, "name": s(&r["Name"]), "sub": s(&r["TeamName"]), "group": s(&r["GroupId"]) }));
                }
                "Team" => {
                    let id = s(&r["ThreadId"]);
                    if s(&r["Name"]).is_empty() || !seen.insert(format!("team:{id}")) {
                        continue;
                    }
                    teams.push(serde_json::json!({ "kind": "team", "id": id, "name": s(&r["Name"]), "sub": "", "group": s(&r["GroupId"]) }));
                }
                _ => {}
            }
        }
    }
    // The channels of your teams that match and Substrate didn't give
    // (Teams' local search over its teams store, checked on winpc
    // 2026-11-21: Substrate gave "OST layout test" and "OST test channel",
    // Teams added "OST threads test" and "OST test channel 2"), best match,
    // then latest activity, first.
    let mut more: Vec<(&LocalChat, u8)> = local
        .iter()
        .filter(|c| {
            !c.channel_team.is_empty()
                && !c.topic.is_empty()
                && !channels.iter().any(|v| v["id"] == c.id.as_str())
        })
        .filter_map(|c| local_chat_rank(&c.topic, query).map(|r| (c, r)))
        .collect();
    more.sort_by(|a, b| a.1.cmp(&b.1).then(b.0.time.cmp(&a.0.time)));
    channels.extend(more.into_iter().map(|(c, _)| serde_json::json!({ "kind": "channel", "id": c.id, "name": c.topic, "sub": c.channel_team, "group": "" })));
    // Your own named group chats that match and Substrate didn't give: the
    // best at the third place, the rest after.
    let mut extra: Vec<(&LocalChat, u8)> = local
        .iter()
        .filter(|c| {
            c.group
                && !c.meeting
                && !c.topic.is_empty()
                && !chats.iter().any(|v| v["id"] == c.id.as_str())
        })
        .filter_map(|c| local_chat_rank(&c.topic, query).map(|r| (c, r)))
        .collect();
    extra.sort_by(|a, b| a.1.cmp(&b.1).then(b.0.time.cmp(&a.0.time)));
    let mut extra = extra.into_iter().map(
        |(c, _)| serde_json::json!({ "kind": "chat", "id": c.id, "name": c.topic, "sub": "" }),
    );
    if let Some(first) = extra.next() {
        chats.insert(chats.len().min(2), first);
    }
    chats.extend(extra);

    const SLOTS: [(&str, usize); 7] = [
        ("person", 5),
        ("chat", 3),
        ("channel", 3),
        ("team", 1),
        ("dl", 2),
        ("person", 15),
        ("", 0),
    ];
    const MAX: usize = 22;
    let lists: [(&str, &Vec<serde_json::Value>); 5] = [
        ("person", &people),
        ("chat", &chats),
        ("channel", &channels),
        ("team", &teams),
        ("dl", &dls),
    ];
    let mut used = vec![0usize; lists.len()];
    let (mut out, mut overflow) = (Vec::new(), Vec::new());
    for (kind, count) in SLOTS {
        let Some(li) = lists.iter().position(|(k, _)| *k == kind) else {
            continue;
        };
        let list = lists[li].1;
        let take = list.len().saturating_sub(used[li]).min(count);
        out.extend(list[used[li]..used[li] + take].iter().cloned());
        used[li] += take;
        // Teams keeps what didn't fit a slot for the end.
        for v in &list[used[li]..] {
            if !overflow.contains(v) {
                overflow.push(v.clone());
            }
        }
    }
    for v in overflow {
        if out.len() >= MAX {
            break;
        }
        if !out.contains(&v) {
            out.push(v);
        }
    }
    out.truncate(MAX);
    out
}

/// The new chat form's suggestions before anything is typed: Teams' top-N
/// people (its worker's zero-state suggestions, `getTopNSuggestions` over
/// the "peoplecache" scenario: Substrate's people for an empty query, in
/// rank order, ranks 1 to 20). People only, with Teams' second lines
/// ([`parse_recipients`]); you as "<name> (You)".
pub async fn zero_state_people(
    my_oid: &str,
    my_mail: &str,
    my_name: &str,
) -> Result<Vec<serde_json::Value>> {
    let token =
        crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let reply: serde_json::Value = reqwest::Client::new()
        .post("https://substrate.office.com/search/api/v1/suggestions?scenario=peoplecache")
        .bearer_auth(token)
        .json(&zero_state_body())
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let reply = with_me(reply, my_oid, my_mail, my_name);
    let seen: Vec<String> = reply["Groups"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|g| g["Suggestions"].as_array().cloned().unwrap_or_default())
        .map(|s| {
            format!(
                "{}/{}/{}/{}/{}",
                s["DisplayName"].as_str().unwrap_or("?"),
                s["PeopleType"].as_str().unwrap_or("?"),
                s["PeopleSubtype"].as_str().unwrap_or("?"),
                !s["ExternalDirectoryObjectId"]
                    .as_str()
                    .unwrap_or_default()
                    .is_empty(),
                s["MRI"]
                    .as_str()
                    .unwrap_or("-")
                    .chars()
                    .take(20)
                    .collect::<String>()
            )
        })
        .collect();
    tracing::debug!(people = ?seen, "zero-state suggestions");
    if std::env::var_os("OST_PICKER_DEBUG").is_some() {
        for s in reply["Groups"]
            .as_array()
            .into_iter()
            .flatten()
            .flat_map(|g| g["Suggestions"].as_array().cloned().unwrap_or_default())
        {
            if s["PeopleSubtype"] == "PersonalContact" {
                eprintln!("PICKER contact {s} me={my_mail}");
            }
        }
        eprintln!(
            "PICKER zero-state {} {:?}",
            reply["Groups"].as_array().map(|g| g.len()).unwrap_or(0),
            seen
        );
    }
    Ok(people_only(
        parse_recipients(&reply, my_oid),
        ZERO_STATE_COUNT,
    ))
}

/// The top-N list has you as a personal contact (no Teams id, your
/// address): Teams turns it into you, "<name> (You)", in that place.
pub fn with_me(
    mut reply: serde_json::Value,
    my_oid: &str,
    my_mail: &str,
    my_name: &str,
) -> serde_json::Value {
    if my_oid.is_empty() || my_mail.is_empty() {
        return reply;
    }
    for g in reply["Groups"].as_array_mut().into_iter().flatten() {
        for r in g["Suggestions"].as_array_mut().into_iter().flatten() {
            // Your address, or (as ost-test1's list has it) a personal
            // contact with no name and no address: the mailbox's own card.
            let emails: Vec<&str> = r["EmailAddresses"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|e| e.as_str())
                .collect();
            let unnamed = r["DisplayName"].as_str().unwrap_or_default().is_empty();
            let mine = r["ExternalDirectoryObjectId"]
                .as_str()
                .unwrap_or_default()
                .is_empty()
                && r["MRI"].as_str().unwrap_or_default().is_empty()
                && r["PeopleSubtype"] == "PersonalContact"
                && (emails.iter().any(|e| e.eq_ignore_ascii_case(my_mail))
                    || (emails.is_empty() && unnamed));
            if mine {
                r["ExternalDirectoryObjectId"] = serde_json::json!(my_oid);
                r["PeopleType"] = serde_json::json!("Person");
                r["PeopleSubtype"] = serde_json::json!("OrganizationUser");
                if r["DisplayName"].as_str().unwrap_or_default().is_empty() {
                    r["DisplayName"] = serde_json::json!(my_name);
                }
                if r["UserPrincipalName"]
                    .as_str()
                    .unwrap_or_default()
                    .is_empty()
                {
                    r["UserPrincipalName"] = serde_json::json!(my_mail);
                }
            }
        }
    }
    reply
}

/// Teams' zeroStateSuggestionsTopNCacheEndRank (live 20).
pub const ZERO_STATE_COUNT: usize = 20;

/// Teams' maxTopNFetchSize (live 500): the top-N store's size.
pub const TOP_N_FETCH: usize = 500;

pub fn zero_state_body() -> serde_json::Value {
    let mut body = recipients_body("");
    let mut people = body["EntityRequests"][0].clone();
    // The top-N store holds everyone the service ranks (no picker filter).
    if let Some(m) = people.as_object_mut() {
        m.remove("Filter");
        m.remove("Provenances");
        m.remove("ServeNoEmailContacts");
    }
    body["EntityRequests"] = serde_json::json!([people]);
    body["EntityRequests"][0]["Size"] = serde_json::json!(TOP_N_FETCH);
    body["Scenario"]["Name"] = serde_json::json!("peoplecache");
    body
}

/// People among picker suggestions (no groups, chats, channels or teams),
/// the first `max`.
pub fn people_only(items: Vec<serde_json::Value>, max: usize) -> Vec<serde_json::Value> {
    items
        .into_iter()
        .filter(|v| v["kind"] == "person" && !v["oid"].as_str().unwrap_or_default().is_empty())
        .take(max)
        .collect()
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
    let anchor = if my_oid.is_empty() || tenant.is_empty() {
        String::new()
    } else {
        format!("OID:{my_oid}@{tenant}")
    };
    let mut page = Page::default();
    if tab == "communities" {
        page.communities = communities(keywords).await?;
        return Ok(page);
    }
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
            let m = super::messages::read_message(client, &thread, &id)
                .await
                .ok();
            (
                i,
                m.map(|m| {
                    (
                        find::row_text(&m),
                        m.subject.clone(),
                        m.images.first().map(|im| (im.id.clone(), im.url.clone())),
                    )
                }),
            )
        })
        .buffer_unordered(6)
        .collect()
        .await;
    for (i, r) in read {
        let Some((text, subject, image)) = r else {
            continue;
        };
        let h: &mut Hit = &mut found.hits[i];
        if let Some((id, url)) = image {
            h.image_id = id;
            h.image_ams = url;
        }
        if !subject.is_empty() {
            h.text = if text.is_empty() {
                subject.clone()
            } else {
                format!("{subject} - {text}")
            };
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
    fn new_chat_arranges_as_teams() {
        // Substrate's answer for "OST" (shape as captured 2026-11-20).
        let person = |n: &str, id: &str, sub: &str| serde_json::json!({"DisplayName": n, "ExternalDirectoryObjectId": id, "PeopleSubtype": sub, "UserPrincipalName": format!("{id}@x.com"), "EmailAddresses": [format!("{id}@x.com")]});
        let mut ppl: Vec<serde_json::Value> = vec![
            person("OST Test 2", "t2", "OrganizationUser"),
            person("OST Guest 02", "g2", "Guest"),
            person("OST Guest 01", "g1", "Guest"),
            person("OST Test 1", "me", "OrganizationUser"),
            person("OST Test 3", "t3", "OrganizationUser"),
            person("OST Test Team", "team", "UnifiedGroup"),
            person("No id", "", "OrganizationUser"),
        ];
        for i in 3..10 {
            ppl.push(person(
                &format!("OST Guest 0{i}"),
                &format!("g{i}"),
                "Guest",
            ));
        }
        ppl.push(person("OST Test Community", "comm", "UnifiedGroup"));
        let chat = |n: &str, id: &str| serde_json::json!({"Name": n, "ThreadId": id});
        let chan = |n: &str, id: &str| serde_json::json!({"Name": n, "ThreadId": id, "TeamName": "OST Test Team", "GroupId": "gid"});
        let reply = serde_json::json!({"Groups": [
            {"Type": "People", "Suggestions": ppl},
            {"Type": "Chat", "Suggestions": [chat("OST group test", "19:a"), chat("OST TEST group call", "19:b"), chat("Meeting", "19:meeting_m"), chat("Not mine", "19:z")]},
            {"Type": "Channel", "Suggestions": [chan("OST layout test", "19:c1"), chan("OST test channel", "19:c2")]},
        ]});
        let lc = |id: &str, t: &str, time: i64| LocalChat {
            id: id.into(),
            topic: t.into(),
            group: true,
            meeting: id.starts_with("19:meeting_"),
            time,
            channel_team: String::new(),
        };
        let lch = |id: &str, t: &str, time: i64| LocalChat {
            id: id.into(),
            topic: t.into(),
            time,
            channel_team: "OST Test Team".into(),
            ..Default::default()
        };
        let local = [
            lc("19:a", "OST group test", 9),
            lc("19:b", "OST TEST group call", 8),
            lc("19:meeting_m", "Meeting", 7),
            lc("19:e", "OST empty chat test", 6),
            lc("19:l", "OST large chat test", 5),
            lc("19:o", "Other", 4),
            lch("19:c1", "OST layout test", 1),
            lch("19:c3", "OST threads test", 3),
            lch("19:c4", "OST test channel 2", 2),
            lch("19:c5", "OST test channel 3", 1),
            lch("19:g", "General", 9),
        ];
        let out = new_chat_arrange(&reply, "me", &local, "OST");
        let names: Vec<&str> = out
            .iter()
            .map(|v| v["plain_name"].as_str().or(v["name"].as_str()).unwrap())
            .collect();
        assert_eq!(
            names,
            [
                "OST Test 2",
                "OST Guest 02",
                "OST Guest 01",
                "OST Test 1",
                "OST Test 3",
                "OST group test",
                "OST TEST group call",
                "OST empty chat test",
                "OST layout test",
                "OST test channel",
                "OST threads test",
                "OST Test Team",
                "OST Test Community",
                "OST Guest 03",
                "OST Guest 04",
                "OST Guest 05",
                "OST Guest 06",
                "OST Guest 07",
                "OST Guest 08",
                "OST Guest 09",
                "OST large chat test",
                "OST test channel 2"
            ]
        );
        assert_eq!(out[3]["you"], true);
        assert_eq!(out[1]["sub"], "g2@x.com");
        assert_eq!(out[8]["sub"], "OST Test Team");
        // "OST group": no one matches, the chats do.
        let reply = serde_json::json!({"Groups": [{"Type": "Chat", "Suggestions": [chat("OST group test", "19:a")]}]});
        let out = new_chat_arrange(&reply, "me", &local, "OST group");
        assert_eq!(
            out.iter()
                .map(|v| v["name"].as_str().unwrap())
                .collect::<Vec<_>>(),
            ["OST group test", "OST TEST group call"]
        );
        assert_eq!(local_chat_rank("OST group test", "ost gr"), Some(2));
        assert_eq!(local_chat_rank("OST group test", "group"), Some(4));
        assert_eq!(local_chat_rank("OST group test", "roup"), None);
    }

    #[test]
    fn communities_read_engages_reply() {
        let reply = serde_json::json!({"data": {"search": {"groups": {"edges": [
            {"node": {"id": "g1", "displayName": "OST community", "description": "A test", "avatarUrlTemplate": "https://x/{width}x{height}", "isOfficial": true, "viewerMembershipStatus": "MEMBER", "privacy": "PUBLIC", "hasDefaultAvatar": false}},
            {"node": {"id": "g2", "displayName": "Other", "description": "", "avatarUrlTemplate": "https://x/d", "isOfficial": false, "viewerMembershipStatus": "NOT_MEMBER", "privacy": "PRIVATE", "hasDefaultAvatar": true}}
        ], "pageInfo": {"hasNextPage": false, "endCursor": null}}}}});
        let c = read_communities(&reply);
        assert_eq!(c.len(), 2);
        assert_eq!(
            (c[0].name.as_str(), c[0].avatar.as_str(), c[0].official),
            ("OST community", "https://x/{width}x{height}", true)
        );
        assert_eq!(c[1].avatar, "");
        assert!(
            read_communities(&serde_json::json!({"data": {"search": {"groups": {"edges": []}}}}))
                .is_empty()
        );
        assert!(COMMUNITY_SEARCH.contains("query CommunitySearchTeams($query: String!)"));
    }

    #[test]
    fn every_tab_has_teams_request() {
        for tab in TABS {
            let b = bodies(
                tab,
                "OST test",
                &Filters::default(),
                0,
                "America/Los_Angeles",
                "o",
                "t",
            );
            assert!(!b.is_empty(), "{tab}");
            let text = serde_json::to_string(&b).unwrap();
            assert!(
                !text.contains("{QUERY}") && !text.contains("{TZ}") && !text.contains("{WINTZ}"),
                "{tab}"
            );
        }
        assert_eq!(
            bodies("images", "x", &Filters::default(), 0, "UTC", "", "").len(),
            2
        );
        let m = bodies(
            "meetings",
            "x",
            &Filters::default(),
            0,
            "America/Los_Angeles",
            "",
            "",
        );
        assert_eq!(m[0]["timezone"], "Pacific Standard Time");
    }

    #[test]
    fn recipients_come_in_teams_order_with_teams_lines() {
        // As the service answered "OST T" (Share this file, 2026-11-11).
        let reply = serde_json::json!({
            "Groups": [
                { "Type": "People", "Suggestions": [
                    { "DisplayName": "OST Test 2", "PeopleType": "Person", "PeopleSubtype": "OrganizationUser", "UserPrincipalName": "ost-test2@x.com", "ExternalDirectoryObjectId": "9EDCC62F", "ReferenceId": "r1" },
                    { "DisplayName": "OST Test 1", "PeopleType": "Person", "PeopleSubtype": "OrganizationUser", "UserPrincipalName": "ost-test1@x.com", "ExternalDirectoryObjectId": "4287e791", "JobTitle": "Tester", "ReferenceId": "r2" },
                    { "DisplayName": "OST Test Team", "PeopleType": "Group", "PeopleSubtype": "UnifiedGroup", "ReferenceId": "r3" }
                ] },
                { "Type": "Team", "Suggestions": [{ "Name": "OST Test Team", "ThreadId": "19:team@thread.tacv2", "GroupId": "g", "ReferenceId": "r14" }] },
                { "Type": "Channel", "Suggestions": [{ "Name": "OST test channel", "ThreadId": "19:c@thread.tacv2", "TeamName": "OST Test Team", "GroupId": "g", "ReferenceId": "r9" }] },
                { "Type": "Chat", "Suggestions": [{ "Name": "OST group test", "ThreadId": "19:g@thread.v2", "ThreadType": "Chat", "ReferenceId": "r8" }] }
            ],
            "LayoutHints": { "BestMatchSuggestions": [
                { "ReferenceId": "r1" }, { "ReferenceId": "r2" }, { "ReferenceId": "r3" }, { "ReferenceId": "r8" }, { "ReferenceId": "r14" }, { "ReferenceId": "r9" }
            ] }
        });
        let r = parse_recipients(&reply, "4287E791");
        let lines: Vec<(String, String)> = r
            .iter()
            .map(|v| {
                (
                    v["name"].as_str().unwrap().to_string(),
                    v["sub"].as_str().unwrap().to_string(),
                )
            })
            .collect();
        assert_eq!(
            lines,
            [
                ("OST Test 2".to_string(), "OST-TEST2".to_string()),
                (
                    "OST Test 1 (You)".to_string(),
                    "(OST-TEST1) Tester".to_string()
                ),
                ("OST group test".to_string(), String::new()),
                ("OST Test Team".to_string(), String::new()),
                ("OST test channel".to_string(), "OST Test Team".to_string()),
            ]
        );
        assert_eq!(r[0]["oid"], "9edcc62f");
        assert_eq!(r[4]["id"], "19:c@thread.tacv2");
        // The new chat form keeps the people only.
        let people = people_only(r, 20);
        assert_eq!(people.len(), 2);
        assert_eq!(people[1]["name"], "OST Test 1 (You)");
    }

    #[test]
    fn guests_show_their_email_and_are_marked() {
        // As Teams' new chat form shows them (winpc, 2026-11-16).
        let reply = serde_json::json!({ "Groups": [{ "Type": "People", "Suggestions": [
            { "DisplayName": "OST Guest 08", "PeopleType": "Person", "PeopleSubtype": "Guest", "UserPrincipalName": "ostguest08_x.com#EXT#@y.onmicrosoft.com", "EmailAddresses": ["ostguest08@x.com"], "ExternalDirectoryObjectId": "e7dbe546", "ReferenceId": "r1" },
            { "DisplayName": "Randy Northrup", "PeopleType": "Person", "PeopleSubtype": "OrganizationUser", "UserPrincipalName": "Randy@x.com", "ExternalDirectoryObjectId": "5050c9d6", "ReferenceId": "r2" }
        ] }] });
        let r = parse_recipients(&reply, "");
        assert_eq!(r[0]["sub"], "ostguest08@x.com");
        assert_eq!(r[0]["guest"], true);
        assert_eq!(r[1]["sub"], "RANDY");
        assert_eq!(r[1]["guest"], false);
        // You, as the top-N list has you (a personal contact).
        let top = serde_json::json!({ "Groups": [{ "Type": "People", "Suggestions": [
            { "DisplayName": "OST Test 2", "PeopleType": "Person", "PeopleSubtype": "OrganizationUser", "UserPrincipalName": "ost-test2@x.com", "ExternalDirectoryObjectId": "9edcc62f", "ReferenceId": "a" },
            { "DisplayName": "OST Test Team", "PeopleType": "Group", "PeopleSubtype": "UnifiedGroup", "ReferenceId": "b" },
            { "PeopleType": "Person", "PeopleSubtype": "PersonalContact", "EmailAddresses": ["OST-test1@x.com"], "ReferenceId": "c" },
            { "DisplayName": "OST Guest 08", "PeopleType": "Other", "PeopleSubtype": "Guest", "MRI": "8:orgid:e7dbe546", "EmailAddresses": ["g8@y.com"], "ReferenceId": "d" }
        ] }] });
        let names: Vec<String> = people_only(
            parse_recipients(
                &with_me(top, "4287e791", "ost-test1@x.com", "OST Test 1"),
                "4287e791",
            ),
            20,
        )
        .iter()
        .map(|p| {
            format!(
                "{} | {}",
                p["name"].as_str().unwrap(),
                p["sub"].as_str().unwrap()
            )
        })
        .collect();
        assert_eq!(
            names,
            [
                "OST Test 2 | OST-TEST2",
                "OST Test 1 (You) | OST-TEST1",
                "OST Guest 08 | g8@y.com"
            ]
        );
        let z = zero_state_body();
        assert_eq!(z["Scenario"]["Name"], "peoplecache");
        assert_eq!(z["EntityRequests"].as_array().unwrap().len(), 1);
        assert_eq!(z["EntityRequests"][0]["EntityType"], "People");
        assert_eq!(z["EntityRequests"][0]["Query"]["QueryString"], "");
    }

    #[test]
    fn files_grid_asks_for_teams_page() {
        let list = bodies("files", "x", &Filters::default(), 0, "UTC", "", "");
        assert_eq!(list[0]["entityRequests"][0]["size"], 25);
        let grid = bodies(
            "files",
            "x",
            &Filters {
                grid: true,
                ..Default::default()
            },
            0,
            "UTC",
            "",
            "",
        );
        assert_eq!(grid[0]["entityRequests"][0]["size"], 24);
    }

    #[test]
    fn message_filters_are_teams_terms() {
        // As Teams sent them (Messages tab, "OST test").
        let none = Filters::default();
        assert_eq!(
            message_query("OST test", &none, "", false),
            "NOT (isClientSoftDeleted:TRUE) OST test"
        );
        assert_eq!(
            message_query("OST test", &none, "", true),
            "NOT (isClientSoftDeleted:TRUE) AND OST test"
        );
        let chat = Filters {
            kind: "chat".into(),
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &chat, "", false),
            "NOT (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        let b = bodies("messages", "OST test", &chat, 0, "UTC", "", "");
        assert_eq!(
            b[0]["entityRequests"][0]["Filter"],
            serde_json::json!({"Term": {"ConversationType": "OneToOne"}})
        );
        // Type ▸ Channel: the thread-type clause only, no filter term.
        let chan = Filters {
            kind: "channel".into(),
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &chan, "", false),
            "(Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        assert!(
            bodies("messages", "OST test", &chan, 0, "UTC", "", "")[0]["entityRequests"][0]
                .get("Filter")
                .is_none()
        );
        let mention = Filters {
            mentions: true,
            ..Default::default()
        };
        assert_eq!(
            message_query(
                "OST test",
                &mention,
                "4287e791-1b98-4963-8b94-281c50472683",
                false
            ),
            "mentions:4287e7911b9849638b94281c50472683 AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        let att = Filters {
            attachment: true,
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &att, "", false),
            "hasattachment:yes AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        let inchat = Filters {
            in_kind: "chat".into(),
            in_thread: "19:ef2@thread.v2".into(),
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &inchat, "", false),
            "clientthreadid:19:ef2@thread.v2 AND NOT (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        // In ▸ a channel (as Teams sent it).
        let inchan = Filters {
            in_kind: "channel".into(),
            in_thread: "19:7826@thread.tacv2".into(),
            in_group: "1fac3ae3".into(),
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &inchan, "", false),
            "clientthreadid:19:7826@thread.tacv2 AND NOT (isClientSoftDeleted:TRUE) OST test"
        );
        assert_eq!(
            bodies("messages", "OST test", &inchan, 0, "UTC", "", "")[0]["entityRequests"][0]["Filter"],
            serde_json::json!({"Term": {"GroupId": "1fac3ae3"}})
        );
        // In ▸ a team (as Teams sent it for OST Test Team, 2026-11-13).
        let inteam = Filters {
            in_kind: "team".into(),
            in_thread: "19:ekCPvoD9@thread.tacv2".into(),
            in_group: "1fac3ae3".into(),
            ..Default::default()
        };
        assert_eq!(
            message_query("channel reply", &inteam, "", false),
            "clientthreadid:19:ekCPvoD9@thread.tacv2 AND NOT (isClientSoftDeleted:TRUE) channel reply"
        );
        assert_eq!(
            bodies("messages", "channel reply", &inteam, 0, "UTC", "", "")[0]["entityRequests"][0]
                ["Filter"],
            serde_json::json!({"Term": {"GroupId": "1fac3ae3"}})
        );
        let from = Filters {
            person_mail: "a@b.c".into(),
            person_oid: "o1".into(),
            person_from: true,
            ..Default::default()
        };
        assert_eq!(
            message_query("OST test", &from, "", false),
            "NOT (isClientSoftDeleted:TRUE) a@b.c OST test"
        );
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
        assert_eq!(
            p.order,
            ["messages", "groupchats", "channels", "files", "meetings"]
        );
        assert_eq!(p.terms, ["ost", "test"]);
        assert_eq!(
            (p.chats[0].name.as_str(), p.chats[0].member_count),
            ("OST group test", 2)
        );
        assert_eq!(p.channels[0].team, "OST Test Team");
        assert_eq!(p.events[0].join_url, "https://teams/l/meetup-join/x");
        assert!(p.events[0].is_organizer);
    }
}
