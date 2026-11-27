//! Teams links handed to OST from outside the app (TASK-0369): the
//! browser's "Join on the Teams app" (Teams' launcher page hands the
//! desktop an `msteams:` link), a link on the command line, or one a
//! second launch passes over the instance socket (main.rs).
//!
//! Teams desktop takes the `msteams:` and `web+msteams:` schemes and its
//! own hosts (its package's protocol and app URI handler registrations:
//! teams.microsoft.com, teams.cloud.microsoft, and teams.live.com for
//! Teams free). OST takes the same and nothing else: any other scheme or
//! host is refused before anything reads it, and nothing here opens or
//! fetches the link. A link is only read into a [`TeamsLink`], which names
//! a place in OST (a meeting's pre-join, a chat, a channel, a message, a
//! file in OST's viewer); what OST can't open yet says so.
//!
//! Forms read, as Teams' launcher and Teams' "Copy link" write them:
//! - `msteams:/l/meetup-join/<thread>/0?context=…&deeplinkId=…&launchAgent=join_launcher…`
//!   (the launcher's `fqdn=` names the host when it isn't
//!   teams.microsoft.com), and `msteams://teams.microsoft.com/l/…`;
//! - `https://teams.microsoft.com/l/meetup-join/…`, `…/meet/<ID>?p=<passcode>`,
//!   `https://teams.live.com/meet/<ID>?p=…`;
//! - the launcher page itself (`/dl/launcher/launcher.html?url=/_#/l/…`)
//!   and the web client's `/_#/l/…` and `/v2/#/l/…`;
//! - `/l/chat/<id>/…`, `/l/chat/0/0?users=…&topicName=…&message=…`,
//!   `/l/channel/<id>/<name>?groupId=…`, `/l/team/<id>/…`,
//!   `/l/message/<id>/<message id>?parentMessageId=…`,
//!   `/l/file/<id>?objectUrl=…&fileType=…`, `/l/app/<id>`,
//!   `/l/settings/<page>`.

use serde_json::{Value, json};

/// Teams' own hosts (its app URI handler's, and Teams free's).
pub const HOSTS: [&str; 3] = [
    "teams.microsoft.com",
    "teams.cloud.microsoft",
    "teams.live.com",
];

/// Teams free's host: its meetings belong to a personal account.
const LIVE_HOST: &str = "teams.live.com";

/// Longer than any link Teams writes (a file link with its SharePoint
/// address is the longest, well under this).
const MAX_LEN: usize = 8192;

/// Most people a new-chat link may name (Teams' group chat limit).
const MAX_NEW_CHAT_USERS: usize = 250;

/// Where a Teams link leads in OST.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TeamsLink {
    /// Just bring the window forward (`msteams:` with nothing after it).
    Open,
    /// A meeting's join link: its pre-join. `url` is the canonical
    /// `https://teams.microsoft.com/l/meetup-join/…` link OST joins.
    Meeting { url: String },
    /// A meeting by its ID and passcode (`/meet/<ID>?p=…`): Join with an ID.
    MeetingId { id: String, passcode: String },
    /// A Teams free meeting (teams.live.com), which belongs to a personal
    /// account. `url` is the https link.
    PersonalMeeting { url: String },
    /// A chat (`19:…@thread.v2`, `19:…@unq.gbl.spaces`, `48:notes`…).
    Chat { thread: String },
    /// A new chat with these people (e-mail addresses / UPNs), its name and
    /// first message prefilled.
    NewChat {
        users: Vec<String>,
        topic: String,
        message: String,
    },
    /// A channel (a team's link is its General channel's, `name` empty).
    Channel { thread: String, name: String },
    /// A message in a chat or channel; `parent` is the post a channel reply
    /// belongs to.
    Message {
        thread: String,
        message: String,
        parent: Option<String>,
    },
    /// A file in OST's viewer.
    File {
        name: String,
        file_type: String,
        object_url: String,
    },
    /// A link OST's own link handling opens in the app (`/l/app/…`,
    /// `/l/settings/…`): the canonical https link.
    InApp { url: String },
    /// A Teams link OST can't open (yet): `kind` is its `/l/<kind>/`,
    /// `url` the https link on its Teams host.
    Unsupported { kind: String, url: String },
}

#[cfg_attr(feature = "test-harness", allow(dead_code))]
/// Whether `arg` is meant as a link (a scheme OST would read one from),
/// whether or not it's a Teams link.
pub fn looks_like_link(arg: &str) -> bool {
    matches!(
        crate::link_gate::scheme(arg.trim()).as_deref(),
        Some("msteams" | "web+msteams" | "https" | "http")
    )
}

/// Read a Teams link; None for anything that isn't one (another scheme,
/// another host, credentials or an odd port in it, control characters,
/// or too long).
pub fn parse(link: &str) -> Option<TeamsLink> {
    let link = link.trim();
    if link.is_empty()
        || link.len() > MAX_LEN
        || link.chars().any(|c| c.is_control() || c.is_whitespace())
    {
        return None;
    }
    let scheme = crate::link_gate::scheme(link)?;
    let rest = &link[scheme.len() + 1..];
    let (host, path_and_query) = match scheme.as_str() {
        "msteams" | "web+msteams" => match rest.strip_prefix("//") {
            Some(r) => {
                let (host, path) = split_authority(r)?;
                (host, path.to_string())
            }
            None => {
                // The launcher's fqdn= names Teams' host when it isn't
                // teams.microsoft.com (Teams free).
                let host = query_param(query_of(rest), "fqdn")
                    .map(|h| h.to_ascii_lowercase())
                    .filter(|h| HOSTS.contains(&h.as_str()))
                    .unwrap_or_else(|| HOSTS[0].to_string());
                (host, rest.to_string())
            }
        },
        "https" => {
            let (host, path) = split_authority(rest.strip_prefix("//")?)?;
            (host, path.to_string())
        }
        _ => return None,
    };
    Some(route(&host, &unwrap_web_path(&path_and_query)?))
}

/// The host and the rest of `//host[:443]/…`: only Teams' hosts, without
/// credentials or another port.
fn split_authority(r: &str) -> Option<(String, &str)> {
    let end = r.find(['/', '?', '#']).unwrap_or(r.len());
    let (authority, path) = r.split_at(end);
    if authority.contains('@') {
        return None;
    }
    let host = authority
        .strip_suffix(":443")
        .unwrap_or(authority)
        .to_ascii_lowercase();
    HOSTS.contains(&host.as_str()).then_some((host, path))
}

/// The path (with its query) a web address stands for: the launcher's
/// `url=` and the web client's `#/l/…` fragment are the link itself.
fn unwrap_web_path(p: &str) -> Option<String> {
    let path = p.split(['?', '#']).next().unwrap_or("");
    if path.eq_ignore_ascii_case("/dl/launcher/launcher.html") {
        let inner = query_param(query_of(p), "url")?;
        // Once: the launcher's url= is a path, never another launcher.
        let inner = strip_hash_route(&inner);
        return (inner.starts_with("/l/") || inner.starts_with("/meet/"))
            .then(|| inner.to_string());
    }
    if let Some((_, fragment)) = p.split_once('#')
        && let Some(route) = fragment.strip_prefix('/')
        && matches!(path, "" | "/" | "/_" | "/v2" | "/v2/")
    {
        return Some(format!("/{route}"));
    }
    Some(strip_hash_route(p).to_string())
}

/// `/_#/l/…` → `/l/…`.
fn strip_hash_route(p: &str) -> &str {
    p.strip_prefix("/_#").unwrap_or(p)
}

/// The query of `path?query#fragment`.
fn query_of(p: &str) -> &str {
    p.split_once('?')
        .map(|(_, q)| q.split('#').next().unwrap_or(""))
        .unwrap_or("")
}

/// A query parameter, percent-decoded (`+` is a space, as forms write it).
fn query_param(query: &str, key: &str) -> Option<String> {
    query.split('&').find_map(|kv| {
        let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
        (k.eq_ignore_ascii_case(key)).then(|| percent_decode(&v.replace('+', " ")))?
    })
}

/// Strict percent-decoding to UTF-8 (None on a broken escape).
fn percent_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let hex = std::str::from_utf8(b.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// A chat or channel id as Teams writes them: `19:…@thread.v2`,
/// `19:…@thread.tacv2`, `19:…@thread.skype`, `19:…@unq.gbl.spaces`,
/// `48:notes` and the like; nothing that could be markup or a path.
fn valid_thread(t: &str) -> bool {
    let Some((prefix, body)) = t.split_once(':') else {
        return false;
    };
    prefix.len() == 2
        && prefix.bytes().all(|b| b.is_ascii_digit())
        && !body.is_empty()
        && t.len() <= 256
        && body
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_-=.@".contains(c))
}

/// A message id: Teams' are the post time in milliseconds.
fn valid_message_id(m: &str) -> bool {
    !m.is_empty() && m.len() <= 20 && m.bytes().all(|b| b.is_ascii_digit())
}

/// An e-mail address or UPN a new-chat link names.
fn valid_user(u: &str) -> bool {
    let Some((local, domain)) = u.split_once('@') else {
        return false;
    };
    !local.is_empty()
        && domain.contains('.')
        && u.len() <= 320
        && u.chars()
            .all(|c| c.is_ascii_alphanumeric() || "._-+'@".contains(c))
}

/// Where `path` (a `/l/…` or `/meet/…` path with its query) on `host`
/// leads.
fn route(host: &str, path_and_query: &str) -> TeamsLink {
    let (path, query) = match path_and_query.split_once('?') {
        Some((p, q)) => (p, q.split('#').next().unwrap_or("")),
        None => (path_and_query.split('#').next().unwrap_or(""), ""),
    };
    let https = |p: &str| {
        if query.is_empty() {
            format!("https://{host}{p}")
        } else {
            format!("https://{host}{p}?{query}")
        }
    };
    let segments: Vec<&str> = path.trim_matches('/').split('/').collect();
    let unsupported = |kind: &str| TeamsLink::Unsupported {
        kind: kind.to_string(),
        url: https(path),
    };
    let seg = |i: usize| segments.get(i).copied().unwrap_or("");
    let decoded = |i: usize| percent_decode(seg(i)).unwrap_or_default();
    match (seg(0), seg(1)) {
        ("", "") => TeamsLink::Open,
        ("meet", code) => {
            let code: String = code.chars().filter(|c| *c != '-').collect();
            if code.is_empty() || code.len() > 32 || !code.bytes().all(|b| b.is_ascii_digit()) {
                return unsupported("meet");
            }
            if host == LIVE_HOST {
                return TeamsLink::PersonalMeeting { url: https(path) };
            }
            TeamsLink::MeetingId {
                id: code,
                passcode: query_param(query, "p").unwrap_or_default(),
            }
        }
        ("l", "meetup-join") => {
            if host == LIVE_HOST {
                return TeamsLink::PersonalMeeting { url: https(path) };
            }
            // Only the meeting's own parts: the launcher's (deeplinkId,
            // launchAgent, anon…) are left behind.
            let context = query
                .split('&')
                .find(|kv| kv.starts_with("context="))
                .map(|c| format!("?{c}"))
                .unwrap_or_default();
            let url = format!(
                "https://teams.microsoft.com/l/meetup-join/{}/{}{context}",
                seg(2),
                seg(3)
            );
            match teams_cli::calling::outgoing::MeetingLink::parse(&url) {
                Some(_) => TeamsLink::Meeting { url },
                None => unsupported("meetup-join"),
            }
        }
        ("l", "chat") => {
            let thread = decoded(2);
            if thread == "0" {
                let users: Vec<String> = query_param(query, "users")
                    .unwrap_or_default()
                    .split(',')
                    .map(|u| u.trim().to_string())
                    .filter(|u| !u.is_empty())
                    .collect();
                if users.is_empty()
                    || users.len() > MAX_NEW_CHAT_USERS
                    || !users.iter().all(|u| valid_user(u))
                {
                    return unsupported("chat");
                }
                return TeamsLink::NewChat {
                    users,
                    topic: query_param(query, "topicName").unwrap_or_default(),
                    message: query_param(query, "message").unwrap_or_default(),
                };
            }
            if !valid_thread(&thread) {
                return unsupported("chat");
            }
            TeamsLink::Chat { thread }
        }
        ("l", kind @ ("channel" | "team")) => {
            let thread = decoded(2);
            if !valid_thread(&thread) {
                return unsupported(kind);
            }
            let name = if kind == "channel" {
                decoded(3)
            } else {
                String::new()
            };
            TeamsLink::Channel { thread, name }
        }
        ("l", "message") => {
            let (thread, message) = (decoded(2), decoded(3));
            if !valid_thread(&thread) || !valid_message_id(&message) {
                return unsupported("message");
            }
            let parent = query_param(query, "parentMessageId")
                .filter(|p| valid_message_id(p) && *p != message);
            TeamsLink::Message {
                thread,
                message,
                parent,
            }
        }
        ("l", "file") => {
            let object_url = query_param(query, "objectUrl").unwrap_or_default();
            if !is_sharepoint_file(&object_url) {
                return unsupported("file");
            }
            let name = object_url
                .rsplit('/')
                .next()
                .and_then(percent_decode)
                .unwrap_or_default();
            let file_type = query_param(query, "fileType")
                .filter(|t| t.len() <= 16 && t.bytes().all(|b| b.is_ascii_alphanumeric()))
                .unwrap_or_else(|| {
                    name.rsplit_once('.')
                        .map(|(_, e)| e.to_string())
                        .unwrap_or_default()
                })
                .to_ascii_lowercase();
            TeamsLink::File {
                name,
                file_type,
                object_url,
            }
        }
        ("l", "app" | "settings") => TeamsLink::InApp {
            url: format!(
                "https://teams.microsoft.com{path}{}",
                if query.is_empty() {
                    String::new()
                } else {
                    format!("?{query}")
                }
            ),
        },
        ("l", kind) if !kind.is_empty() => unsupported(kind),
        _ => unsupported(""),
    }
}

/// A file link's document: an https address on SharePoint (where Teams
/// keeps chat and channel files), the only kind OST's viewer opens.
fn is_sharepoint_file(u: &str) -> bool {
    let Some(rest) = u.strip_prefix("https://") else {
        return false;
    };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    !host.contains(['@', ':'])
        && host
            .to_ascii_lowercase()
            .strip_suffix(".sharepoint.com")
            .is_some_and(|tenant| {
                !tenant.is_empty()
                    && tenant
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-')
            })
        && rest.len() > host.len() + 1
        && !u.chars().any(char::is_control)
}

impl TeamsLink {
    /// For QML (Main.qml openTeamsLink): `{kind, …}`.
    pub fn to_json(&self) -> Value {
        match self {
            TeamsLink::Open => json!({ "kind": "open" }),
            TeamsLink::Meeting { url } => json!({ "kind": "meeting", "url": url }),
            TeamsLink::MeetingId { id, passcode } => {
                json!({ "kind": "meetingId", "id": id, "passcode": passcode })
            }
            TeamsLink::PersonalMeeting { url } => json!({ "kind": "personalMeeting", "url": url }),
            TeamsLink::Chat { thread } => json!({ "kind": "chat", "thread": thread }),
            TeamsLink::NewChat {
                users,
                topic,
                message,
            } => json!({ "kind": "newChat", "users": users, "topic": topic, "message": message }),
            TeamsLink::Channel { thread, name } => {
                json!({ "kind": "channel", "thread": thread, "name": name })
            }
            TeamsLink::Message {
                thread,
                message,
                parent,
            } => {
                json!({ "kind": "message", "thread": thread, "message": message, "parent": parent.clone().unwrap_or_default() })
            }
            TeamsLink::File {
                name,
                file_type,
                object_url,
            } => {
                json!({ "kind": "file", "name": name, "fileType": file_type, "objectUrl": object_url })
            }
            TeamsLink::InApp { url } => json!({ "kind": "inApp", "url": url }),
            TeamsLink::Unsupported { kind, url } => {
                json!({ "kind": "unsupported", "linkKind": kind, "url": url })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const THREAD: &str =
        "19%3ameeting_NjQ4ZTk0YzAtZWE2Ni00YjI1LTg0ZTMtNmZkNmU2MTFmNjZl%40thread.v2";
    const CONTEXT: &str = "context=%7b%22Tid%22%3a%2272f988bf-86f1-41af-91ab-2d7cd011db47%22%2c%22Oid%22%3a%228b5d8b6a-36a5-4a18-a3a6-0dd1d6a6c0a8%22%7d";

    fn meeting_url() -> String {
        format!("https://teams.microsoft.com/l/meetup-join/{THREAD}/0?{CONTEXT}")
    }

    #[test]
    fn meeting_links_in_every_form_reach_the_same_meeting() {
        let want = TeamsLink::Meeting { url: meeting_url() };
        for link in [
            meeting_url(),
            // The launcher's, with its own parameters.
            format!(
                "msteams:/l/meetup-join/{THREAD}/0?{CONTEXT}&anon=true&deeplinkId=4b0c&launchAgent=join_launcher&type=meetup-join&directDl=true&msLaunch=true&enableMobilePage=true&suppressPrompt=true"
            ),
            format!("web+msteams:/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            format!("msteams://teams.microsoft.com/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            format!("https://teams.cloud.microsoft/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            format!("https://TEAMS.microsoft.com:443/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            format!("https://teams.microsoft.com/_#/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            format!("https://teams.microsoft.com/v2/#/l/meetup-join/{THREAD}/0?{CONTEXT}"),
            // The launcher page itself (its url= is the link, encoded).
            format!(
                "https://teams.microsoft.com/dl/launcher/launcher.html?url=%2F_%23%2Fl%2Fmeetup-join%2F{}%2F0%3F{}&type=meetup-join&deeplinkId=x&directDl=true&msLaunch=true",
                THREAD.replace('%', "%25"),
                CONTEXT.replace('%', "%25").replace('=', "%3D")
            ),
        ] {
            assert_eq!(parse(&link), Some(want.clone()), "{link}");
        }
        // What Teams' launcher page hands the desktop today (captured
        // 2026-11-27: enableWebMsteamsProtocol and enableFQDN on, the
        // thread decoded from its url=): the same meeting.
        let launched = "web+msteams:/l/meetup-join/19:meeting_NjQ4ZTk0YzAtZWE2Ni00YjI1LTg0ZTMtNmZkNmU2MTFmNjZl@thread.v2/0?context=%7b%22Tid%22%3a%2272f988bf-86f1-41af-91ab-2d7cd011db47%22%2c%22Oid%22%3a%228b5d8b6a-36a5-4a18-a3a6-0dd1d6a6c0a8%22%7d&anon=true&deeplinkId=0fe34c07&launchAgent=join_launcher&type=meetup-join&directDl=true&msLaunch=true&enableMobilePage=true&fqdn=teams.microsoft.com";
        let Some(TeamsLink::Meeting { url }) = parse(launched) else {
            panic!("{launched}")
        };
        assert_eq!(
            teams_cli::calling::outgoing::MeetingLink::parse(&url),
            teams_cli::calling::outgoing::MeetingLink::parse(&meeting_url())
        );
        // Without a context too.
        assert!(matches!(
            parse(&format!("msteams:/l/meetup-join/{THREAD}/0")),
            Some(TeamsLink::Meeting { .. })
        ));
    }

    #[test]
    fn short_links_join_with_the_meeting_id() {
        assert_eq!(
            parse("https://teams.microsoft.com/meet/2873487134553?p=fB8HJ2uS"),
            Some(TeamsLink::MeetingId {
                id: "2873487134553".into(),
                passcode: "fB8HJ2uS".into()
            })
        );
        assert_eq!(
            parse("msteams:/meet/2873487134553?p=a%2Bb&anon=true"),
            Some(TeamsLink::MeetingId {
                id: "2873487134553".into(),
                passcode: "a+b".into()
            })
        );
    }

    #[test]
    fn teams_free_meetings_are_personal() {
        for link in [
            "https://teams.live.com/meet/9876543210123?p=Abc123",
            "msteams:/meet/9876543210123?p=Abc123&fqdn=teams.live.com",
            "https://teams.live.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0",
        ] {
            assert!(
                matches!(parse(link), Some(TeamsLink::PersonalMeeting { ref url }) if url.starts_with("https://teams.live.com/")),
                "{link}"
            );
        }
    }

    #[test]
    fn chats_channels_and_messages() {
        assert_eq!(
            parse(
                "https://teams.microsoft.com/l/chat/19%3a7d1f6a2b3c4d5e6f%40thread.v2/conversations?context=%7b%22contextType%22%3a%22chat%22%7d"
            ),
            Some(TeamsLink::Chat {
                thread: "19:7d1f6a2b3c4d5e6f@thread.v2".into()
            })
        );
        assert_eq!(
            parse("msteams:/l/chat/19:a1b2-c3_d4@unq.gbl.spaces/conversations"),
            Some(TeamsLink::Chat {
                thread: "19:a1b2-c3_d4@unq.gbl.spaces".into()
            })
        );
        assert_eq!(
            parse(
                "https://teams.microsoft.com/l/chat/0/0?users=ost-test2@example.com,ost-test3@example.com&topicName=Plan%20it&message=Hi+there"
            ),
            Some(TeamsLink::NewChat {
                users: vec![
                    "ost-test2@example.com".into(),
                    "ost-test3@example.com".into()
                ],
                topic: "Plan it".into(),
                message: "Hi there".into(),
            })
        );
        assert_eq!(
            parse(
                "https://teams.microsoft.com/l/channel/19%3aQWxpY2U%40thread.tacv2/General?groupId=2f0c&tenantId=72f9"
            ),
            Some(TeamsLink::Channel {
                thread: "19:QWxpY2U@thread.tacv2".into(),
                name: "General".into()
            })
        );
        assert_eq!(
            parse(
                "https://teams.microsoft.com/l/team/19%3aQWxpY2U%40thread.tacv2/conversations?groupId=2f0c&tenantId=72f9"
            ),
            Some(TeamsLink::Channel {
                thread: "19:QWxpY2U@thread.tacv2".into(),
                name: String::new()
            })
        );
        assert_eq!(
            parse(
                "https://teams.microsoft.com/l/message/19%3aQWxpY2U%40thread.tacv2/1732712345678?tenantId=72f9&groupId=2f0c&parentMessageId=1732700000000&teamName=T&channelName=General&createdTime=1732712345678"
            ),
            Some(TeamsLink::Message {
                thread: "19:QWxpY2U@thread.tacv2".into(),
                message: "1732712345678".into(),
                parent: Some("1732700000000".into()),
            })
        );
        // A top-level post names itself as its parent.
        assert_eq!(
            parse(
                "msteams:/l/message/19:abc@thread.v2/1732712345678?parentMessageId=1732712345678"
            ),
            Some(TeamsLink::Message {
                thread: "19:abc@thread.v2".into(),
                message: "1732712345678".into(),
                parent: None
            })
        );
    }

    #[test]
    fn files_open_only_from_sharepoint() {
        assert_eq!(
            parse("https://teams.microsoft.com/l/file/5E0154E0-7B2F-4E0B-9D7C-2D8E1F1A9B0C?tenantId=72f9&fileType=docx&objectUrl=https%3A%2F%2Fcontoso.sharepoint.com%2Fsites%2FTeam%2FShared%20Documents%2FGeneral%2FPlan%20v2.docx&baseUrl=https%3A%2F%2Fcontoso.sharepoint.com%2Fsites%2FTeam&serviceName=teams&threadId=19:abc@thread.tacv2&groupId=2f0c"),
            Some(TeamsLink::File {
                name: "Plan v2.docx".into(),
                file_type: "docx".into(),
                object_url: "https://contoso.sharepoint.com/sites/Team/Shared Documents/General/Plan v2.docx".into(),
            })
        );
        for bad in [
            "https%3A%2F%2Fevil.example%2Fa.docx",
            "https%3A%2F%2Fcontoso.sharepoint.com.evil.example%2Fa.docx",
            "https%3A%2F%2Fuser%40contoso.sharepoint.com%2Fa.docx",
            "file%3A%2F%2F%2Fetc%2Fpasswd",
            "http%3A%2F%2Fcontoso.sharepoint.com%2Fa.docx",
        ] {
            assert!(
                matches!(parse(&format!("https://teams.microsoft.com/l/file/x?objectUrl={bad}")), Some(TeamsLink::Unsupported { ref kind, .. }) if kind == "file"),
                "{bad}"
            );
        }
    }

    #[test]
    fn other_teams_links_say_what_they_are() {
        assert_eq!(parse("msteams:"), Some(TeamsLink::Open));
        assert_eq!(
            parse("https://teams.microsoft.com/l/app/com.microsoft.teamspace.tab.planner"),
            Some(TeamsLink::InApp {
                url: "https://teams.microsoft.com/l/app/com.microsoft.teamspace.tab.planner".into()
            })
        );
        assert_eq!(
            parse("msteams:/l/call/0/0?users=a@example.com"),
            Some(TeamsLink::Unsupported {
                kind: "call".into(),
                url: "https://teams.microsoft.com/l/call/0/0?users=a@example.com".into()
            })
        );
        // Broken ids are reported, not guessed at.
        for link in [
            "https://teams.microsoft.com/l/chat/<script>/conversations",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40evil.example/0",
            "https://teams.microsoft.com/l/message/19:abc@thread.v2/notanumber",
            "https://teams.microsoft.com/l/chat/0/0?users=javascript:alert(1)",
        ] {
            assert!(
                matches!(parse(link), Some(TeamsLink::Unsupported { .. })),
                "{link}"
            );
        }
    }

    #[test]
    fn nothing_but_teams_links_is_taken() {
        for link in [
            "",
            "https://example.com/l/meetup-join/19%3ameeting_x%40thread.v2/0",
            "https://teams.microsoft.com.evil.example/l/chat/19:a@thread.v2/x",
            "https://evil.example/?x=https://teams.microsoft.com/l/chat/19:a@thread.v2/x",
            "https://user@teams.microsoft.com/l/chat/19:a@thread.v2/x",
            "https://teams.microsoft.com:8443/l/chat/19:a@thread.v2/x",
            "http://teams.microsoft.com/l/chat/19:a@thread.v2/x",
            "msteams://evil.example/l/chat/19:a@thread.v2/x",
            "file:///etc/passwd",
            "ms-teams:/l/chat/19:a@thread.v2/x",
            "javascript:alert(1)",
            "/tmp/shot.png",
            "--nav-test",
            "https://teams.microsoft.com/l/chat/19:a@thread.v2/x\nactivate",
            "https://teams.microsoft.com/l/chat/19:a@thread.v2/x\topen",
            "msteams:/l/chat/19:a@thread.v2/a b",
        ] {
            assert_eq!(parse(link), None, "{link:?}");
        }
        // The launcher's fqdn= can't send it elsewhere.
        assert!(matches!(
            parse("msteams:/l/call/0/0?fqdn=evil.example"),
            Some(TeamsLink::Unsupported { ref url, .. }) if url.starts_with("https://teams.microsoft.com/")
        ));
        assert_eq!(
            parse(&format!(
                "msteams:/l/chat/19:a@thread.v2/{}",
                "x".repeat(MAX_LEN)
            )),
            None
        );
    }

    #[test]
    fn link_arguments_are_told_from_options_and_paths() {
        assert!(looks_like_link("msteams:/l/meetup-join/x/0"));
        assert!(looks_like_link("https://example.com/"));
        assert!(!looks_like_link("--room"));
        assert!(!looks_like_link("/tmp/shot.png"));
        assert!(!looks_like_link("-platform"));
    }
}
