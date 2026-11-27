//! The Activity feed: Teams' `48:notifications` stream. Each message
//! carries a `properties.activity` record (what happened, who did it,
//! where, and a preview), which Teams words as "Randy reacted to your
//! message", "Missed call from Randy", and so on.
//!
//! Apps' activities (`msGraph`, Teams 26304's GraphActivityProcessor) are
//! worded by the app: its manifest's `activities.activityItems` entry for
//! the activity's subtype gives `templateText`, whose `{name}`s are filled
//! from the activity's `templateParameters` and `{actor}` with who did it;
//! the second line is the activity's `location` (custom text, a chat's
//! name or a channel), the picture the app's icon.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One notification, ready to show.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ActivityItem {
    pub id: String,
    /// "reaction", "mention", "tagMention", "reply", "missedCall", "voicemail",
    /// "addedToTeam", "teamShare", "app" (an app's activity), or the
    /// service's own type for anything else.
    pub kind: String,
    /// The headline, as Teams words it.
    pub title: String,
    /// Message preview (may be empty).
    pub preview: String,
    /// "In chat with you", "OST call", a chat's or team's name, an app's own
    /// text (which can hold Teams' `<DateTimeRange>…` markup: Theme.qml's
    /// activityPlace words it) …
    pub context: String,
    /// A channel's name after its team (`context`), Teams' "Team > Channel".
    pub channel: String,
    pub time: String,
    pub unread: bool,
    /// Who did it (MRI) and their name, for the picture.
    pub actor_mri: String,
    pub actor_name: String,
    /// Where to go: the chat or channel thread, and the message in it.
    pub thread_id: String,
    pub message_id: String,
    /// For reactions: the emoji as text (for plain-text places).
    pub emoji: String,
    /// For reactions: Teams' emoticon (its client id: the service's `like`
    /// is the thumbs-up `yes`), which Teams shows on the picture.
    pub reaction: String,
    /// An app's activity: the app and its icon (Teams' picture for it).
    pub app_id: String,
    pub icon: String,
    /// An app's activity's link (its `customTapAction`).
    pub link: String,
    /// What the second pass (`resolve`) still needs.
    #[serde(skip)]
    pending: Option<Pending>,
}

/// The parts of an activity that need the app's manifest or the thread.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct Pending {
    /// msGraph: the subtype, its `templateParameters` and `location`.
    app_subtype: Option<String>,
    params: serde_json::Value,
    location: serde_json::Value,
    /// A bot's app (its icon).
    source_app: String,
    /// A channel's activity: its team's name from the activity, and the
    /// thread to read the channel's name from.
    channel_thread: Option<String>,
}

/// The newest notifications, newest first.
pub async fn feed(client: &TeamsClient, limit: usize) -> Result<Vec<ActivityItem>> {
    let url = format!(
        "{}/v1/users/ME/conversations/48:notifications/messages?pageSize={}&view=msnp24Equivalent",
        client.chat_service_url(),
        limit
    );
    let text = client
        .chat_get(&url)
        .await?
        .text()
        .await
        .context("Activity reply")?;
    let mut items = parse_feed(&text);
    resolve(client, &mut items).await;
    Ok(items)
}

/// What a thread tells the feed: its topic, the team and channel names
/// of a channel, and a meeting chat's backroom kind. `None`: the thread
/// can't be read (gone, or not yours).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ThreadFacts {
    pub topic: String,
    pub team: String,
    pub channel: String,
    pub backroom: String,
}

impl ThreadFacts {
    /// From a conversation's `threadProperties` or a thread's
    /// `properties`. A channel's name is its topic; a team's first
    /// channel's is `topicThreadTopic`, else "General".
    pub fn from_props(p: &serde_json::Value) -> Self {
        let s = |k: &str| {
            p.get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let map: std::collections::HashMap<String, serde_json::Value> = p
            .as_object()
            .map(|o| o.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
            .unwrap_or_default();
        let topic = s("topic");
        let space = matches!(s("threadType").as_str(), "space" | "topic");
        let channel = if !space {
            String::new()
        } else if !topic.is_empty() {
            topic.clone()
        } else if !s("topicThreadTopic").is_empty() {
            s("topicThreadTopic")
        } else {
            "General".to_string()
        };
        Self {
            team: s("spaceThreadTopic"),
            channel,
            backroom: super::chat::backroom_kind(&map).to_string(),
            topic,
        }
    }
}

/// A thread's facts, asked once per thread and session.
pub async fn thread_facts(client: &TeamsClient, id: &str) -> Option<ThreadFacts> {
    static KNOWN: std::sync::Mutex<Option<std::collections::HashMap<String, Option<ThreadFacts>>>> =
        std::sync::Mutex::new(None);
    if let Some(k) = KNOWN
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|m| m.get(id).cloned())
    {
        return k;
    }
    let base = client.chat_service_url();
    // The thread itself has a meeting chat's backroom facts; your
    // conversation of it the channel's names (and is there when the
    // thread's own roster isn't readable).
    let get = |url: String| async move {
        match client.chat_get(&url).await {
            Ok(r) => Ok(r.json::<serde_json::Value>().await.ok()),
            Err(e) => Err(e.to_string()),
        }
    };
    let conv = get(format!(
        "{base}/v1/users/ME/conversations/{id}?view=msnp24Equivalent"
    ))
    .await;
    let thread = get(format!("{base}/v1/threads/{id}?view=msnp24Equivalent")).await;
    let gone = |r: &Result<Option<serde_json::Value>, String>| matches!(r, Err(e) if e.contains("HTTP 404") || e.contains("HTTP 403"));
    let facts = match (&conv, &thread) {
        (Ok(Some(c)), t) => {
            let mut f = ThreadFacts::from_props(&c["threadProperties"]);
            if let Ok(Some(t)) = t {
                let tf = ThreadFacts::from_props(&t["properties"]);
                f.backroom = tf.backroom;
                if f.topic.is_empty() {
                    f.topic = tf.topic;
                }
            }
            Some(f)
        }
        (_, Ok(Some(t))) => Some(ThreadFacts::from_props(&t["properties"])),
        _ if gone(&conv) && gone(&thread) => None,
        // (a network failure: nothing known, and asked again next time)
        _ => return Some(ThreadFacts::default()),
    };
    // A meeting chat's backroom kind as the chat list worked it out, when
    // the thread itself didn't say.
    let facts = facts.map(|mut f| {
        if f.backroom.is_empty()
            && let Some((kind, _)) = super::chat::backroom_of(id)
        {
            f.backroom = kind;
        }
        f
    });
    // A thread that didn't answer for another reason (throttled) is asked
    // again next time.
    if let Err(e) = &thread
        && !gone(&thread)
    {
        tracing::info!(
            "activity: thread {} not read: {}",
            &id[..id.len().min(24)],
            e.chars().take(80).collect::<String>()
        );
        return facts;
    }
    KNOWN
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(Default::default)
        .insert(id.to_string(), facts.clone());
    facts
}

/// Apps' definitions, asked once per app and session.
async fn app_definitions(
    client: &TeamsClient,
    ids: &[String],
) -> std::collections::HashMap<String, serde_json::Value> {
    static KNOWN: std::sync::Mutex<Option<std::collections::HashMap<String, serde_json::Value>>> =
        std::sync::Mutex::new(None);
    let known = |id: &str| {
        KNOWN
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|m| m.get(id).cloned())
    };
    let missing: Vec<String> = ids
        .iter()
        .filter(|i| known(&i.to_lowercase()).is_none())
        .cloned()
        .collect();
    if !missing.is_empty() {
        match super::app_details::definitions(client, &missing).await {
            Ok(defs) => {
                let mut g = KNOWN.lock().unwrap_or_else(|e| e.into_inner());
                let m = g.get_or_insert_with(Default::default);
                for d in defs {
                    if let Some(id) = d["id"].as_str() {
                        m.insert(id.to_lowercase(), d.clone());
                    }
                }
            }
            Err(e) => tracing::warn!("activity: app definitions: {e}"),
        }
    }
    ids.iter()
        .filter_map(|i| known(&i.to_lowercase()).map(|d| (i.to_lowercase(), d)))
        .collect()
}

/// The second pass: apps' activities worded from their manifests (those
/// Teams can't word aren't shown, as Teams' isMessageValid drops them),
/// chats' and channels' names from their threads.
async fn resolve(client: &TeamsClient, items: &mut Vec<ActivityItem>) {
    let mut app_ids: Vec<String> = Vec::new();
    let mut threads: Vec<String> = Vec::new();
    for it in items.iter() {
        let Some(p) = &it.pending else { continue };
        for id in [&it.app_id, &p.source_app] {
            if !id.is_empty() && !app_ids.contains(id) {
                app_ids.push(id.clone());
            }
        }
        let thread = if p.app_subtype.is_some() {
            Some(&it.thread_id)
        } else {
            p.channel_thread.as_ref()
        };
        if let Some(t) = thread.filter(|t| !t.is_empty() && !threads.contains(t)) {
            threads.push(t.clone());
        }
    }
    if app_ids.is_empty() && threads.is_empty() {
        return;
    }
    let defs = app_definitions(client, &app_ids).await;
    // (four at a time: the chat service throttles a burst)
    let mut facts: std::collections::HashMap<String, Option<ThreadFacts>> =
        std::collections::HashMap::new();
    for chunk in threads.chunks(4) {
        let got = futures::future::join_all(chunk.iter().map(|t| thread_facts(client, t))).await;
        facts.extend(chunk.iter().cloned().zip(got));
    }
    items.retain_mut(|it| {
        let Some(p) = it.pending.take() else {
            return true;
        };
        let thread = facts.get(&it.thread_id).cloned().flatten();
        if let Some(sub) = &p.app_subtype {
            let Some(def) = defs.get(&it.app_id.to_lowercase()) else {
                return false;
            };
            // (a chat it names that can't be read: Teams drops it too)
            if !it.thread_id.is_empty() && facts.get(&it.thread_id).is_some_and(|f| f.is_none()) {
                return false;
            }
            match graph_text(def, sub, &p.params, &it.actor_name) {
                Some(t) => it.title = t,
                None => return false,
            }
            if it.icon.is_empty() {
                it.icon = app_icon(def);
            }
            let loc = |k: &str| {
                p.location
                    .get(k)
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
            };
            if let Some(c) = loc("Custom") {
                it.context = c.to_string();
            } else if loc("GroupChatId").is_some() {
                it.context = thread.as_ref().map(chat_place).unwrap_or_default();
            } else if loc("TeamId").is_some() {
                (it.context, it.channel) = channel_place(thread.as_ref(), "");
            }
            return true;
        }
        if !p.source_app.is_empty()
            && let Some(def) = defs.get(&p.source_app.to_lowercase())
        {
            it.icon = app_icon(def);
        }
        if p.channel_thread.is_some() {
            let team = std::mem::take(&mut it.context);
            (it.context, it.channel) = channel_place(thread.as_ref(), &team);
        }
        true
    });
}

/// An app's icon (its largeImageUrl; one on Teams' own client path, like
/// the Channel Agent's, from the assets' CDN).
fn app_icon(def: &serde_json::Value) -> String {
    super::tabs::https_only(&super::app_details::evergreen_asset_url(
        def["largeImageUrl"].as_str().unwrap_or_default(),
    ))
}

/// An app's activity's headline (Teams' getFirstLineReasonString and
/// doTitleTranslation): its type's templateText, each `{name}` replaced
/// by that template parameter, then `{actor}` by who did it. `None` when
/// the app has no such type or a parameter is missing (Teams' isMessageValid).
pub fn graph_text(
    def: &serde_json::Value,
    subtype: &str,
    params: &serde_json::Value,
    actor: &str,
) -> Option<String> {
    let template = def
        .pointer("/activities/activityItems")?
        .as_array()?
        .iter()
        .find(|i| {
            i["type"]
                .as_str()
                .is_some_and(|t| t.eq_ignore_ascii_case(subtype))
        })?
        .get("templateText")
        .and_then(|t| t.as_str())
        .unwrap_or_default();
    let mut text = template.to_string();
    for name in template_names(template) {
        if name == "actor" {
            continue;
        }
        let value = match params.get(&name)? {
            serde_json::Value::String(s) => s.clone(),
            other => other.to_string(),
        };
        text = text.replacen(&format!("{{{name}}}"), &value, 1);
    }
    Some(text.replacen("{actor}", actor, 1))
}

/// A template's `{name}`s (Teams' /\{\w+\}/g), in order.
fn template_names(t: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = t;
    while let Some(i) = rest.find('{') {
        let after = &rest[i + 1..];
        let word: String = after
            .chars()
            .take_while(|c| c.is_alphanumeric() || *c == '_')
            .collect();
        if !word.is_empty() && after[word.len()..].starts_with('}') {
            out.push(word.clone());
            rest = &after[word.len() + 1..];
        } else {
            rest = after;
        }
    }
    out
}

/// A chat's name as the feed's second line (Teams' B5 for a named chat):
/// an event's or meeting's backroom chat with Teams' prefix.
fn chat_place(f: &ThreadFacts) -> String {
    use crate::i18n::{fill, tr_id};
    if f.topic.is_empty() {
        return String::new();
    }
    match f.backroom.as_str() {
        "event" => fill(
            &tr_id("Event Group Chat: %1", "activity:k2gijpv1u"),
            &[&f.topic],
        ),
        "meeting" => fill(
            &tr_id("Planning Group: %1", "activity:kav8nwl3t"),
            &[&f.topic],
        ),
        _ => f.topic.clone(),
    }
}

/// A channel's place (Teams' MM): its team and channel ("General" for the
/// General channel, in the app language); "Unavailable conversation"
/// when the thread can't be read.
fn channel_place(f: Option<&ThreadFacts>, team_hint: &str) -> (String, String) {
    use crate::i18n::tr_id;
    let Some(f) = f else {
        return (
            tr_id("Unavailable conversation", "activity:ktczwse8"),
            String::new(),
        );
    };
    // (not read this time: the team as the activity names it)
    let team = Some(f.team.clone())
        .filter(|t| !t.is_empty())
        .unwrap_or_else(|| team_hint.to_string());
    let channel = f.channel.clone();
    let channel = if channel == "General" {
        tr_id("General", "activity:k1y1nokmp")
    } else {
        channel
    };
    (team, channel)
}

/// Mark one notification read (Teams does this when it is opened).
pub async fn mark_item_read(client: &TeamsClient, id: &str) -> Result<()> {
    if !id.chars().all(|c| c.is_ascii_digit()) {
        anyhow::bail!("Not a message id");
    }
    let url = format!(
        "{}/v1/users/ME/conversations/48:notifications/messages/{}/properties?name=isread",
        client.chat_service_url(),
        id
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "isread": "true" }),
        )
        .await?;
    Ok(())
}

/// Mark the feed read up to its newest item (Teams does this when the
/// Activity view is shown).
pub async fn mark_read(client: &TeamsClient, newest_id: &str) -> Result<()> {
    super::messages::mark_read(client, "48:notifications", newest_id, newest_id).await
}

/// Parse a `48:notifications/messages` reply.
pub fn parse_feed(json: &str) -> Vec<ActivityItem> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let mut items: Vec<ActivityItem> = v
        .get("messages")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(item_of)
        .collect();
    items.sort_by(|a, b| b.time.cmp(&a.time));
    items
}

fn item_of(m: &serde_json::Value) -> Option<ActivityItem> {
    let props = m.get("properties")?;
    // `activity` (and its `activityContext`, and some of that's values)
    // is JSON text, sometimes already an object.
    let json_of = |v: Option<&serde_json::Value>| match v {
        Some(serde_json::Value::String(s)) => {
            serde_json::from_str::<serde_json::Value>(s).unwrap_or_default()
        }
        Some(v) => v.clone(),
        None => serde_json::Value::Null,
    };
    let act = json_of(Some(props.get("activity")?));
    if !act.is_object() {
        return None;
    }
    let ctx = json_of(act.get("activityContext"));
    // (ids can come as numbers)
    let text_of = |v: Option<&serde_json::Value>| match v {
        Some(serde_json::Value::String(s)) => s.clone(),
        Some(serde_json::Value::Number(n)) => n.to_string(),
        _ => String::new(),
    };
    let s = |k: &str| text_of(act.get(k));
    let c = |k: &str| text_of(ctx.get(k));
    let kind_raw = s("activityType");
    let sub = s("activitySubtype");
    let mut actor_mri = s("sourceUserId");
    let mut actor = s("sourceUserImDisplayName");
    let topic = s("sourceThreadTopic");
    let thread_type = s("sourceThreadType");
    let is_app = actor_mri.starts_with("28:");
    let graph = kind_raw == "msGraph";
    let mut pending = Pending::default();
    if graph {
        // Who it's attributed to stands for the app (Teams' getProfiles).
        let by = json_of(ctx.get("attributedToActor"));
        if let Some(id) = by
            .get("Id")
            .and_then(|v| v.as_str())
            .filter(|v| !v.is_empty())
        {
            actor_mri = id.to_string();
            actor = by
                .get("DisplayName")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
        }
        // Teams drops an app's activity without a valid link.
        if reqwest::Url::parse(&s("customTapAction")).is_err() {
            return None;
        }
        pending.app_subtype = Some(sub.clone());
        pending.params = json_of(ctx.get("templateParameters"));
        pending.location = json_of(ctx.get("location"));
    } else if is_app {
        // A bot shows as its app's name ("<channel> Agent").
        if !s("sourceAppDisplayName").is_empty() {
            actor = s("sourceAppDisplayName");
        }
        pending.source_app = s("sourceAppId");
    }
    let message_id = s("sourceMessageId");
    let reply_chain = s("sourceReplyChainId");
    // A reply in a threads-layout conversation (Teams' J2 / eFe: a
    // threaded conversation and not the thread's first post).
    let in_thread = c("chatModalityType") == "Conversational"
        && !reply_chain.is_empty()
        && reply_chain != message_id;
    let channel = matches!(thread_type.as_str(), "space" | "topic");
    use crate::i18n::{fill, tr_id};
    let who = if actor.is_empty() {
        "Someone".to_string()
    } else {
        actor.clone()
    };
    let (kind, title, context) = match (kind_raw.as_str(), sub.as_str()) {
        ("msGraph", _) => ("app", String::new(), String::new()),
        ("teamMembershipChange", "addedToTeam") => (
            "addedToTeam",
            if is_app || actor.is_empty() {
                fill(
                    &tr_id("A team owner added you to %1", "activity:kblxnh5e8"),
                    &[&topic],
                )
            } else {
                fill(
                    &tr_id("%1 added you to %2", "activity:kd00tkje3"),
                    &[&who, &topic],
                )
            },
            String::new(),
        ),
        // A channel shared with a team you own (Teams'
        // TeamShareTeamOwnerNotifyTitle), in the team's channel.
        ("teamMembershipChange", "teamShareTeamOwnerNotify") => (
            "teamShare",
            fill(
                &tr_id("%1 shared a channel with your team", "activity:kaa2vlwgg"),
                &[&who],
            ),
            in_where(&thread_type, &topic),
        ),
        ("reactionInChat" | "reaction", _) => (
            "reaction",
            if in_thread {
                fill(
                    &tr_id(
                        "%1 reacted to your message in a thread",
                        "activity:kd5bl809d",
                    ),
                    &[&who],
                )
            } else {
                fill(
                    &tr_id("%1 reacted to your message", "activity:ku1d8rgk"),
                    &[&who],
                )
            },
            in_where(&thread_type, &topic),
        ),
        // A tag you are in (Teams' mention_tag processor: "{name}
        // mentioned {tag}", the tag from activityContext.tagname; only the
        // Tag mentions filter shows it).
        ("mention", "tag") => (
            "tagMention",
            fill(
                &tr_id("%1 mentioned %2", "activity:k20ny01cj"),
                &[&who, &c("tagname")],
            ),
            in_where(&thread_type, &topic),
        ),
        ("mention" | "mentionInChat", _) => (
            "mention",
            if in_thread {
                fill(
                    &tr_id("%1 mentioned you in a thread", "activity:k4748rov2"),
                    &[&who],
                )
            } else {
                fill(&tr_id("%1 mentioned you", "activity:k75li603v"), &[&who])
            },
            in_where(&thread_type, &topic),
        ),
        ("reply" | "replyToReply", _) => (
            "reply",
            format!("{who} replied to your message"),
            in_where(&thread_type, &topic),
        ),
        // Your reminder came due (Teams' dueReminder / dueReminderInChat
        // processors, behind enableReminderFeedItems): "Reminder due",
        // the message, and where it is.
        ("dueReminder" | "dueReminderInChat", _) => (
            "reminder",
            tr_id("Reminder due", "activity:k90ftcegy"),
            in_where(&thread_type, &topic),
        ),
        ("call", "missedCall") => (
            "missedCall",
            fill(&tr_id("Missed call from %1", "activity:kdp1gq3h3"), &[&who]),
            tr_id("OST call", "activity:kcgixikhw"),
        ),
        ("call", "voicemail") => (
            "voicemail",
            fill(&tr_id("Voicemail from %1", "activity:k8rphovyq"), &[&who]),
            String::new(),
        ),
        _ => {
            let k = if kind_raw.is_empty() {
                "activity"
            } else {
                kind_raw.as_str()
            };
            (
                k,
                format!("{who}: {}", if sub.is_empty() { k } else { sub.as_str() }),
                String::new(),
            )
        }
    };
    // A channel's place is its team and channel (read from the thread).
    if channel
        && matches!(
            kind,
            "mention" | "tagMention" | "reaction" | "reply" | "teamShare"
        )
    {
        pending.channel_thread = Some(s("sourceThreadId"));
    }
    // `isread` is a JSON boolean until the item is opened, then "true".
    let unread = match props.get("isread") {
        Some(serde_json::Value::Bool(b)) => !b,
        Some(serde_json::Value::String(r)) => r.eq_ignore_ascii_case("false"),
        _ => false,
    };
    let time = {
        let t = s("activityTimestamp");
        if t.is_empty() {
            m.get("composetime")
                .and_then(|t| t.as_str())
                .unwrap_or_default()
                .to_string()
        } else {
            t
        }
    };
    let needs_more = pending != Pending::default();
    Some(ActivityItem {
        id: m
            .get("id")
            .and_then(|i| i.as_str())
            .unwrap_or_default()
            .to_string(),
        kind: kind.to_string(),
        title,
        preview: s("messagePreview"),
        context,
        channel: String::new(),
        time,
        unread,
        actor_mri,
        actor_name: actor,
        thread_id: s("sourceThreadId"),
        message_id,
        emoji: if kind == "reaction" {
            super::messages::reaction_emoji(super::emoticons::client_key(&sub)).to_string()
        } else {
            String::new()
        },
        reaction: if kind == "reaction" {
            super::emoticons::client_key(&sub).to_string()
        } else {
            String::new()
        },
        app_id: if graph {
            c("teamsAppId")
        } else {
            String::new()
        },
        icon: if graph {
            super::tabs::https_only(&super::app_details::evergreen_asset_url(&c("iconUrl")))
        } else {
            String::new()
        },
        link: if graph {
            s("customTapAction")
        } else {
            String::new()
        },
        pending: needs_more.then_some(pending),
    })
}

/// "In chat with you" for chats, the channel or team name otherwise.
fn in_where(thread_type: &str, topic: &str) -> String {
    match thread_type {
        "chat" => crate::i18n::tr_id("In chat with you", "activity:k39mhg4c0"),
        _ if !topic.is_empty() => topic.to_string(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(id: &str, activity: serde_json::Value, read: bool) -> serde_json::Value {
        serde_json::json!({
            "id": id,
            "properties": {
                "activity": activity.to_string(),
                "isread": read
            }
        })
    }

    #[test]
    fn words_items_like_teams() {
        let feed = serde_json::json!({ "messages": [
            msg("1", serde_json::json!({"activityType":"call","activitySubtype":"missedCall",
                "activityTimestamp":"2026-11-05T04:42:03Z","sourceUserId":"8:orgid:a",
                "sourceUserImDisplayName":"Randy Northrup"}), true),
            msg("2", serde_json::json!({"activityType":"reactionInChat","activitySubtype":"like",
                "activityTimestamp":"2026-11-05T06:09:29Z","messagePreview":"OST test 5",
                "sourceThreadType":"chat","sourceThreadId":"19:x@unq.gbl.spaces",
                "sourceMessageId":"17","sourceUserId":"8:orgid:a",
                "sourceUserImDisplayName":"Randy Northrup"}), false),
            msg("3", serde_json::json!({"activityType":"teamMembershipChange","activitySubtype":"addedToTeam",
                "activityTimestamp":"2026-11-05T06:54:31Z","sourceThreadTopic":"Secure Coast",
                "sourceUserId":"28:app:x"}), false),
        ]});
        let items = parse_feed(&feed.to_string());
        let titles: Vec<_> = items.iter().map(|i| i.title.as_str()).collect();
        assert_eq!(
            titles,
            [
                "A team owner added you to Secure Coast",
                "Randy Northrup reacted to your message",
                "Missed call from Randy Northrup",
            ]
        );
        assert!(items[0].unread && items[1].unread && !items[2].unread);
        assert_eq!(items[1].context, "In chat with you");
        assert_eq!(items[1].thread_id, "19:x@unq.gbl.spaces");
        assert_eq!(items[2].context, "OST call");
        assert!(parse_feed("not json").is_empty());
    }

    #[test]
    fn due_reminders_read_reminder_due() {
        let feed = serde_json::json!({ "messages": [
            msg("9", serde_json::json!({"activityType":"dueReminderInChat","sourceThreadType":"chat",
                "sourceUserImDisplayName":"OST Test 3","messagePreview":"Also, lunch is at 12:30"}), false)
        ]});
        let items = parse_feed(&feed.to_string());
        assert_eq!(items[0].kind, "reminder");
        assert_eq!(items[0].title, "Reminder due");
        assert_eq!(items[0].preview, "Also, lunch is at 12:30");
        assert_eq!(items[0].context, "In chat with you");
    }

    #[test]
    fn tag_mentions_name_the_tag() {
        let feed = serde_json::json!({ "messages": [
            msg("4", serde_json::json!({"activityType":"mention","activitySubtype":"tag",
                "activityTimestamp":"2026-11-09T13:03:45Z","sourceThreadTopic":"General",
                "sourceThreadType":"topic","sourceUserId":"8:orgid:a",
                "sourceUserImDisplayName":"Randy Northrup",
                "activityContext":{"tagname":"OST test tag"}}), false),
        ]});
        let items = parse_feed(&feed.to_string());
        assert_eq!(items[0].kind, "tagMention");
        assert_eq!(items[0].title, "Randy Northrup mentioned OST test tag");
    }

    /// Apps' activities as Teams words them (ost-test1's feed, 2026-11-22,
    /// and the apps' manifests).
    #[test]
    fn app_activities_use_their_templates() {
        let qna = serde_json::json!({"activities": {"activityItems": [
            {"type": "teamsQnAEnabledForMeeting", "templateText": "Q&A is enabled for this event. Ask your questions!"},
            {"type": "newTeamsQnAQuestionPosted", "templateText": "{actor} {actors_count}asked a question"}]}});
        assert_eq!(
            graph_text(
                &qna,
                "teamsQnAEnabledForMeeting",
                &serde_json::json!({}),
                "Q&A"
            )
            .as_deref(),
            Some("Q&A is enabled for this event. Ask your questions!")
        );
        // A parameter the template needs and the activity lacks: not shown.
        assert_eq!(
            graph_text(
                &qna,
                "newTeamsQnAQuestionPosted",
                &serde_json::json!({}),
                "A"
            ),
            None
        );
        assert_eq!(
            graph_text(
                &qna,
                "newTeamsQnAQuestionPosted",
                &serde_json::json!({"actors_count": ""}),
                "Ann"
            )
            .as_deref(),
            Some("Ann asked a question")
        );
        assert_eq!(
            graph_text(&qna, "unknown", &serde_json::json!({}), "A"),
            None
        );
        // The type matches whatever its case (Audio Recap's "RecapPodcastReady").
        let recap = serde_json::json!({"activities": {"activityItems": [{"type": "RecapPodcastReady", "templateText": "{title}"}]}});
        assert_eq!(
            graph_text(
                &recap,
                "recapPodcastReady",
                &serde_json::json!({"title": "Audio recap ready: X"}),
                "Audio Recap"
            )
            .as_deref(),
            Some("Audio recap ready: X")
        );
        let cal = serde_json::json!({"activities": {"activityItems": [{"type": "privateMeetingUpdated", "templateText": "{actor} updated"}]}});
        assert_eq!(
            graph_text(
                &cal,
                "privateMeetingUpdated",
                &serde_json::json!({}),
                "OST Test 1"
            )
            .as_deref(),
            Some("OST Test 1 updated")
        );
        assert_eq!(
            template_names("Recap ready: {subject} {x y} {a_b}"),
            ["subject", "a_b"]
        );

        let feed = serde_json::json!({ "messages": [
            msg("5", serde_json::json!({"activityType":"msGraph","activitySubtype":"recapIsReadyV2",
                "activityTimestamp":"2026-11-21T04:48:55Z","sourceUserId":"28:x","sourceUserImDisplayName":"Meeting Recaps",
                "customTapAction":"https://teams.microsoft.com/l/entity/x","messagePreview":"Review AI notes and tasks",
                "activityContext":{"teamsAppId":"981bbfd0-5eb8-4393-8158-bfff69d2d6b5","templateParameters":"{\"subject\":\"OST TEST 73 agenda\"}",
                    "location":"{\"Custom\":\"<DateTimeRange><StartDateTime>2026-11-21T01:00:00Z</StartDateTime><EndDateTime>2026-11-21T01:30:00Z</EndDateTime></DateTimeRange>\"}",
                    "attributedToActor":"{\"Id\":\"8:orgid:a\",\"DisplayName\":\"Ann\"}"}}), false),
            // No valid link: Teams doesn't show it.
            msg("6", serde_json::json!({"activityType":"msGraph","activitySubtype":"x","activityContext":{"teamsAppId":"y"}}), false),
        ]});
        let items = parse_feed(&feed.to_string());
        assert_eq!(items.len(), 1);
        assert_eq!(
            (
                items[0].kind.as_str(),
                items[0].app_id.as_str(),
                items[0].actor_name.as_str()
            ),
            ("app", "981bbfd0-5eb8-4393-8158-bfff69d2d6b5", "Ann")
        );
        let p = items[0].pending.as_ref().unwrap();
        assert_eq!(p.params["subject"], "OST TEST 73 agenda");
        assert!(
            p.location["Custom"]
                .as_str()
                .unwrap()
                .starts_with("<DateTimeRange>")
        );
    }

    /// A bot's mention in a threads-layout channel (ost-test1's Channel
    /// Agent): its app's name, "in a thread", the channel to read.
    #[test]
    fn thread_mentions_and_channel_places() {
        let feed = serde_json::json!({ "messages": [
            msg("7", serde_json::json!({"activityType":"mention","activitySubtype":"person",
                "activityTimestamp":"2026-11-22T21:28:59Z","sourceUserId":"28:3cf9","sourceUserImDisplayName":"Project-Agent-Prod",
                "sourceAppDisplayName":"OST TEST channel Agent","sourceAppId":"3372a6f1","sourceMessageId":1795382871609u64,
                "sourceReplyChainId":1795382685197u64,"sourceThreadId":"19:M@thread.tacv2","sourceThreadType":"space",
                "sourceThreadTopic":"OST TEST 206 agent I","activityContext":{"chatModalityType":"Conversational"}}), true),
        ]});
        let items = parse_feed(&feed.to_string());
        assert_eq!(
            items[0].title,
            "OST TEST channel Agent mentioned you in a thread"
        );
        assert_eq!(items[0].message_id, "1795382871609");
        let p = items[0].pending.as_ref().unwrap();
        assert_eq!(
            (p.channel_thread.as_deref(), p.source_app.as_str()),
            (Some("19:M@thread.tacv2"), "3372a6f1")
        );

        // A team's first channel is named by topicThreadTopic.
        let f = ThreadFacts::from_props(
            &serde_json::json!({"threadType":"space","spaceThreadTopic":"OST TEST 0195 teams team","topicThreadTopic":"OST TEST channel"}),
        );
        assert_eq!(
            channel_place(Some(&f), ""),
            (
                "OST TEST 0195 teams team".to_string(),
                "OST TEST channel".to_string()
            )
        );
        let g = ThreadFacts::from_props(
            &serde_json::json!({"threadType":"space","spaceThreadTopic":"T"}),
        );
        assert_eq!(channel_place(Some(&g), "").1, "General");
        assert_eq!(channel_place(None, "T").0, "Unavailable conversation");
        // Meeting chats by their topic; an event's or meeting's backroom
        // chat with Teams' prefix.
        let m = ThreadFacts::from_props(
            &serde_json::json!({"threadType":"meeting","topic":"OST TEST 212 recap long"}),
        );
        assert_eq!(chat_place(&m), "OST TEST 212 recap long");
        let ev = ThreadFacts {
            topic: "OST TEST 217 town hall".into(),
            backroom: "event".into(),
            ..Default::default()
        };
        assert_eq!(chat_place(&ev), "Event Group Chat: OST TEST 217 town hall");
        let pl = ThreadFacts {
            topic: "X".into(),
            backroom: "meeting".into(),
            ..Default::default()
        };
        assert_eq!(chat_place(&pl), "Planning Group: X");
    }
}
