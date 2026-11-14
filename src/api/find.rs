//! Find in chat, as Teams searches a conversation (captured on winpc
//! 2026-11-10): Substrate's search service, `POST
//! https://substrate.office.com/searchservice/api/v2/query`.
//! - Messages: one Message entity request scoped to the chat with
//!   `clientthreadid:{thread}`, the filters as query terms before it.
//! - Files: one OneDriveBusiness File request annotated with the chat.

use anyhow::{Context, Result};

const SEARCH_URL: &str = "https://substrate.office.com/searchservice/api/v2/query";
const SCOPE: &str = "https://substrate.office.com/.default";
/// Teams asks for 25 at a time.
pub const PAGE: usize = 25;

/// The fields Teams asks for (ParentMessageId twice, as Teams sends it).
const FIELDS: [&str; 11] = [
    "Extension_SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_FileData_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String",
    "GroupId",
    "Extension_SkypeSpaces_ConversationPost_Extension_SenderTenantId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ParentMessageId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ConversationType_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_Topic_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ImageSrc_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_ParentMessageId_String",
    "Extension_SkypeSpaces_ConversationPost_Extension_MessageSubType_String",
];

/// The fields of a Files search.
const FILE_FIELDS: [&str; 20] = [
    "DefaultEncodingUrl",
    "FileName",
    "FileType",
    "HitHighlightedSummary",
    "LastModifiedTime",
    "LinkingUrl",
    "ModifiedBy",
    "OriginalPath",
    "Path",
    "Title",
    "ServerRedirectedPreviewUrl",
    "SpWebUrl",
    "ChannelGroupId",
    "FileExtension",
    "VisualizationAccessURL",
    "LastSharedWithMailboxOwnerByDisplayName",
    "LastSharedWithMailboxOwnerDateTime",
    "FileContextType",
    "ClassicAttachmentVisualizationUrl",
    "UniqueId",
];

/// Which files a Files search leaves out (Teams' refiner).
const FILE_REFINER: &str = "or(andnot(IsDocument:true,Title:or(OneNote_DeletedPages,OneNote_RecycleBin),SecondaryFileExtension:onetoc2,FileExtension:vtt,ContentClass:ExternalLink,and(ContentClass:STS_List_DocumentLibrary,SiteTemplateId:21),FileType:or(aspx,htm,html,mhtml),and(ContentTypeId:0x0101009D1CB255DA76424F860D91F20E6C4118*,PromotedState:2)),ContentTypeId:or(0x010100F3754F12A9B6490D9622A01FE9D8F012,0x0120D520A808*),SecondaryFileExtension:or(wmv,avi,mpg,asf,mp4,ogg,ogv,webm,mov),FileType:or(ai,bmp,dib,dst,emb,eps,gif,ico,jpeg,jpg,odg,png,rle,svg,tiff,webp,wmf,wpd))";

/// This machine's time zone (IANA), which Teams sends with a search.
pub fn local_timezone() -> String {
    iana_time_zone::get_timezone().unwrap_or_else(|_| "UTC".into())
}

/// A folder's address as Teams names a channel's in a search ("Shared
/// Documents", not "Shared%20Documents").
pub fn folder_path(web_url: &str) -> String {
    url::Url::parse(web_url)
        .ok()
        .map(|u| {
            let path: Vec<String> = u
                .path_segments()
                .into_iter()
                .flatten()
                .map(|seg| {
                    url::form_urlencoded::parse(format!("x={}", seg.replace('+', "%2B")).as_bytes())
                        .next()
                        .map(|(_, v)| v.into_owned())
                        .unwrap_or_default()
                })
                .collect();
            format!("{}://{}/{}", u.scheme(), u.host_str().unwrap_or_default(), path.join("/"))
        })
        .unwrap_or_else(|| web_url.to_string())
}

/// The pane's filters.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct Filters {
    /// Files instead of messages.
    pub files: bool,
    /// The date range, ISO UTC (local day boundaries), start inclusive.
    pub start: String,
    pub end: String,
    /// Only messages with attachments.
    pub attachment: bool,
    /// Only messages that mention you.
    pub mentions: bool,
    /// From this person: their e-mail and object id.
    pub from_mail: String,
    pub from_oid: String,
    /// Files of this type (Teams' Type menu): excel, images, loop,
    /// onenote, pdf, powerpoint, text or word.
    pub file_type: String,
    /// A channel's team (its group id) and folder (the library's address,
    /// as "{site}/Shared Documents/{folder}"), for a channel's Files.
    pub channel_group: String,
    pub channel_path: String,
    /// Find in post (a post's window): the post's id; the search is then
    /// its conversation only.
    pub post_root: String,
}

/// The extensions of a Type menu choice (as Teams sends them).
pub fn type_extensions(kind: &str) -> &'static [&'static str] {
    match kind {
        "excel" => &["xls", "xlsx"],
        "images" => &["png", "jpg", "jpeg", "gif"],
        "loop" => &["fluid", "loop"],
        "onenote" => &["one"],
        "pdf" => &["pdf"],
        "powerpoint" => &["ppt", "pptx"],
        "text" => &["txt"],
        "word" => &["doc", "docx"],
        _ => &[],
    }
}

/// Teams' term for a file type: `(filetype:a OR … OR fileExtension:a OR …)`.
fn type_term(kind: &str) -> Option<String> {
    let exts = type_extensions(kind);
    (!exts.is_empty()).then(|| {
        let terms: Vec<String> = exts
            .iter()
            .map(|e| format!("filetype:{e}"))
            .chain(exts.iter().map(|e| format!("fileExtension:{e}")))
            .collect();
        format!("({})", terms.join(" OR "))
    })
}

/// Teams' conversationType filter for a thread: OneToOne for chats (group
/// chats included, as Teams sent for OST group test), Channel for
/// channels.
fn conversation_type(thread: &str) -> &'static str {
    if thread.ends_with("@thread.tacv2") || thread.ends_with("@thread.skype") {
        "Channel"
    } else {
        "OneToOne"
    }
}

/// The query string Teams builds: the date range, attachment and mention
/// terms, the chat, then the sender's address and the keywords.
pub fn query_string(thread: &str, keywords: &str, f: &Filters, my_oid: &str) -> String {
    let mut q = String::new();
    let field = if f.files { "LastModifiedTime" } else { "sent" };
    if !f.start.is_empty() && !f.end.is_empty() {
        q += &format!("{field} >= {} AND {field} < {} AND ", f.start, f.end);
    }
    if f.files {
        if let Some(t) = type_term(&f.file_type) {
            q += &t;
            q += " AND ";
        }
    }
    if !f.files {
        if f.attachment {
            q += "hasattachment:yes AND ";
        }
        if f.mentions && !my_oid.is_empty() {
            q += &format!("mentions:{} AND ", my_oid.replace('-', "").to_ascii_lowercase());
        }
        if f.post_root.is_empty() {
            // Chats leave out channels' (topic / space) threads; a channel
            // asks for them.
            let not = if conversation_type(thread) == "Channel" { "" } else { "NOT " };
            q += &format!(
                "clientthreadid:{thread} AND {not}(Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE)"
            );
        } else {
            q += &format!("clientconversationid:{thread};messageId={} AND NOT (isClientSoftDeleted:TRUE)", f.post_root);
        }
        if !f.from_mail.is_empty() {
            q += " ";
        }
    } else if q.ends_with("AND ") && f.from_mail.is_empty() && keywords.is_empty() {
        q.truncate(q.len() - 5);
    }
    q += &f.from_mail;
    if !keywords.is_empty() {
        if !q.is_empty() && !q.ends_with(' ') {
            q += " ";
        }
        q += keywords;
    }
    q
}

/// The sender filter's annotation (Teams' People annotation).
fn people(f: &Filters, tenant: &str) -> Option<serde_json::Value> {
    (!f.from_mail.is_empty()).then(|| {
        serde_json::json!({ "type": "People", "text": f.from_mail, "userId": f.from_oid, "tenantId": tenant })
    })
}

/// The request body Teams sends for `keywords` in `thread`.
pub fn query_body(
    thread: &str,
    keywords: &str,
    f: &Filters,
    from: usize,
    timezone: &str,
    my_oid: &str,
    tenant: &str,
) -> serde_json::Value {
    let mut query = serde_json::json!({
        "queryString": query_string(thread, keywords, f, my_oid),
        "displayQueryString": keywords,
    });
    if f.files {
        // A chat's files are in its people's OneDrives; a channel's in its
        // team's SharePoint folder.
        let channel = conversation_type(thread) == "Channel";
        let mut notes: Vec<serde_json::Value> = people(f, tenant).into_iter().collect();
        notes.push(if channel {
            serde_json::json!({ "type": "Channel", "threadId": thread, "text": "dummyText", "groupId": f.channel_group, "tenantId": tenant, "path": f.channel_path })
        } else {
            serde_json::json!({ "type": "Chat", "id": thread, "text": "dummyText" })
        });
        query["queryAnnotations"] = notes.into();
        return serde_json::json!({
            "entityRequests": [{
                "entityType": "File",
                "contentSources": [if channel { "SharePoint" } else { "OneDriveBusiness" }],
                "fields": FILE_FIELDS,
                "query": query,
                "size": PAGE,
                "EnableQueryUnderstanding": false,
                "EnableSpeller": false,
                "HitHighlight": { "HitHighlightedProperties": ["HitHighlightedSummary"], "SummaryLength": 200 },
                "IdFormat": "EwsId",
                "ParserType": "None",
                "propertySet": "Optimized",
                "ResultsMerge": { "Type": "Interleaved" },
                "Sort": [{ "Field": "LastModifiedTime", "SortDirection": "Desc" }],
                "extendedQueries": [{
                    "SearchProvider": "SharePoint",
                    "Query": {
                        "SourceId": "8413CD39-2156-4E00-B54D-11EFD9ABDB89",
                        "EnableQueryRules": false,
                        "TrimDuplicates": false,
                        "BypassResultTypes": true,
                        "ProcessBestBets": false,
                        "ProcessPersonalFavorites": false,
                        "EnableInterleaving": false,
                        "EnableMultiGeo": true,
                        "RankingModelId": "ABBAABBA-AAAA-AAAA-CCCC-000000000426",
                        "Culture": 1033,
                    },
                }],
                "RefiningQueries": [{ "RefinerString": FILE_REFINER }],
                "EnableResultAnnotations": true,
                "AnnotationsCount": 1,
                "from": from,
            }],
            "cvid": uuid::Uuid::new_v4().to_string(),
            "logicalId": uuid::Uuid::new_v4().to_string(),
            "QueryAlterationOptions": { "EnableSuggestion": true },
            "scenario": {
                "Dimensions": [
                    { "DimensionName": "QueryType", "DimensionValue": "ContextualFilesTypeAhead" },
                    { "DimensionName": "FormFactor", "DimensionValue": "general.cdlworker.reactSearch" },
                ],
                "Name": "powerbar",
            },
            "textDecorations": "Off",
        });
    }
    if let Some(p) = people(f, tenant) {
        query["queryAnnotations"] = serde_json::json!([p]);
    }
    let mut request = serde_json::json!({
        "entityType": "Message",
        "contentSources": ["Teams"],
        "fields": FIELDS,
        "query": query,
        "propertySet": "Optimized",
        "from": from,
        "size": PAGE,
    });
    // (Find in post names the conversation itself.)
    // A channel's search is filtered to its team; a chat's to chats.
    if f.post_root.is_empty() {
        request["filter"] = if conversation_type(thread) == "Channel" {
            serde_json::json!({ "term": { "groupId": f.channel_group } })
        } else {
            serde_json::json!({ "term": { "conversationType": "OneToOne" } })
        };
    }
    serde_json::json!({
        "entityRequests": [request],
        "cvid": uuid::Uuid::new_v4().to_string(),
        "logicalId": uuid::Uuid::new_v4().to_string(),
        "QueryAlterationOptions": {
            "EnableAlteration": true,
            "EnableSuggestion": true,
            "SupportedRecourseDisplayTypes": ["Suggestion"],
        },
        "scenario": {
            "Dimensions": [
                { "DimensionName": "QueryType", "DimensionValue": "ContextualTypeahead" },
                { "DimensionName": "FormFactor", "DimensionValue": "general.cdlworker.reactSearch" },
            ],
            "Name": "powerbar",
        },
        "timezone": timezone,
    })
}

/// One result.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Hit {
    /// The message's id (to jump to it), or the file's unique id.
    pub id: String,
    /// A channel reply's post (its ParentMessageId when not itself).
    pub parent_id: String,
    pub sender_mri: String,
    pub sender_name: String,
    pub sender_mail: String,
    /// When it was sent (or the file last changed), ISO UTC.
    pub time: String,
    /// The text, tags taken out (Teams highlights the terms itself).
    pub text: String,
    /// A channel post's subject.
    pub subject: String,
    /// Where it was said: the thread ("19:…"), its conversation (a
    /// channel post's "{channel};messageid={post}"), its type ("chat",
    /// "topic" / "space" for channels, "streamofnotes", "meeting"…), and a
    /// channel's team (name and thread).
    pub thread: String,
    pub conversation: String,
    pub thread_type: String,
    pub team: String,
    pub team_thread: String,
    /// The message's first picture (Images): its AMS id and address, and
    /// the cached copy once downloaded.
    pub image_id: String,
    pub image_ams: String,
    pub image_url: String,
    /// A file's name, type and link (`url` to open; `file_url` its
    /// address for Graph).
    pub file_name: String,
    pub file_type: String,
    pub url: String,
    pub file_url: String,
    /// The search page's line for a file: what its person did ("Shared
    /// by", "Created by", "Modified by"; empty when only its author is
    /// known, shown alone), who, and when.
    pub file_action: String,
    pub file_by: String,
    pub file_when: String,
    /// The file's folder (its link), for the search page's place line.
    pub file_folder: String,
    /// The file's site and list, for SharePoint's sharing methods.
    pub file_site: String,
    pub file_list: String,
    /// The team a channel's file belongs to (ChannelGroupId), which
    /// Teams' place line names first.
    #[serde(default)]
    pub file_group_id: String,
    /// Shared with you but never opened (no Path): Teams shows no place.
    #[serde(default)]
    pub file_unredeemed: bool,
}

/// A page of results.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Found {
    pub total: u64,
    pub more: bool,
    /// The words the service matched (Teams highlights these).
    pub terms: Vec<String>,
    pub hits: Vec<Hit>,
}

/// Text from a summary's HTML: tags dropped, entities decoded, white space
/// folded (as Teams shows it).
pub fn plain(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => {
                in_tag = false;
                out.push(' ');
            }
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

/// A file result's line as Teams builds it: its first annotation's action,
/// person and time ("Shared by OST Test 1", 6 days ago); else who last
/// modified it and when; else just its author ("System Account").
fn file_context(r: &serde_json::Value) -> (String, String, String) {
    let src = &r["Source"];
    let note = &r["Annotations"][0];
    let action = match note["Type"].as_str().unwrap_or_default() {
        "Shared" => "Shared by",
        "Created" => "Created by",
        "" => "",
        _ => "Modified by",
    };
    if !action.is_empty() {
        return (action.into(), s(&note["User"]["DisplayName"]), s(&note["Timestamp"]));
    }
    let by = s(&src["ModifiedBy"]);
    if !by.is_empty() {
        return ("Modified by".into(), by, s(&src["LastModifiedTime"]));
    }
    (String::new(), s(&src["Author"]), String::new())
}

fn s(v: &serde_json::Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

/// The results in the service's reply.
pub fn found_from(reply: &serde_json::Value) -> Found {
    let set = &reply["EntitySets"][0];
    let rs = &set["ResultSets"][0];
    let mut found = Found {
        total: rs["Total"].as_u64().unwrap_or_default(),
        more: rs["MoreResultsAvailable"].as_bool().unwrap_or_default(),
        terms: set["SearchTerms"]
            .as_array()
            .or_else(|| reply["SearchTerms"].as_array())
            .into_iter()
            .flatten()
            .filter_map(|t| t.as_str().map(str::to_string))
            .collect(),
        hits: Vec::new(),
    };
    for r in rs["Results"].as_array().into_iter().flatten() {
        let src = &r["Source"];
        let hit = if r["Type"] == "File" || src.get("FileName").is_some() {
            let (file_action, file_by, file_when) = file_context(r);
            Hit {
                id: s(&src["UniqueId"]),
                sender_name: s(&src["ModifiedBy"]),
                time: s(&src["LastModifiedTime"]),
                file_action,
                file_by,
                file_when,
                file_folder: s(&src["ParentLink"]),
                file_site: [&src["SpWebUrl"], &src["SiteName"]].iter().map(|v| s(v)).find(|u| !u.is_empty()).unwrap_or_default(),
                file_list: s(&src["ListId"]),
                file_group_id: s(&src["ChannelGroupId"]),
                file_unredeemed: src["Path"].is_null(),
                text: plain(&s(&r["HitHighlightedSummary"])),
                file_name: s(&src["FileName"]),
                file_type: [&src["FileType"], &src["FileExtension"], &src["SecondaryFileExtension"]]
                    .iter()
                    .map(|v| s(v))
                    .find(|t| !t.is_empty())
                    .unwrap_or_default(),
                file_url: s(&src["DefaultEncodingUrl"]),
                url: [&src["LinkingUrl"], &src["DefaultEncodingUrl"], &src["Path"]]
                    .iter()
                    .map(|v| s(v))
                    .find(|u| !u.is_empty())
                    .unwrap_or_default(),
                ..Default::default()
            }
        } else {
            let ext = &src["Extensions"];
            let id = s(&src["InternetMessageId"]);
            let parent = s(&ext["SkypeSpaces_ConversationPost_Extension_ParentMessageId"]);
            let summary = r["HitHighlightedSummary"].as_str().or_else(|| src["Preview"].as_str()).unwrap_or_default();
            let thread_type = s(&ext["SkypeSpaces_ConversationPost_Extension_ThreadType"]);
            let channel = thread_type == "topic" || thread_type == "space";
            Hit {
                parent_id: if parent == id { String::new() } else { parent },
                thread: s(&src["ClientThreadId"]),
                conversation: s(&src["ClientConversationId"]),
                team: if channel { s(&src["DisplayTo"]) } else { String::new() },
                team_thread: s(&ext["SkypeSpaces_ConversationPost_Extension_SkypeGroupId"]),
                // (A chat's ConversationTopic is the chat's name, not a subject.)
                subject: if channel { s(&src["Subject"]) } else { String::new() },
                thread_type,
                id,
                sender_mri: s(&ext["SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId"]),
                sender_name: s(&src["From"]["EmailAddress"]["Name"]),
                sender_mail: s(&src["From"]["EmailAddress"]["Address"]),
                time: s(&src["DateTimeSent"]),
                text: plain(summary),
                ..Default::default()
            }
        };
        found.hits.push(hit);
    }
    found
}

/// The search service's flights Teams sends (they scope a Files search to
/// the chat, among others).
const FLIGHTS: &str = "DisableTeamsSharedFilesFilter,QueryMicroservice,KeepAliveEnabledFlight,RequestFileMetaDataExtension,nwShortenCaptionsForTeamsCtrlfSearch,FakeConversationUXFlight,EnableFileFiltersViaKQL,EnableCAForTeamsFlight,SearchV2Flight,SubstrateSearchFanoutFlight,lutmsearchmsg,TMSParseRefiningQueries";

/// Send a query (with Teams' headers; `anchor` is "OID:{oid}@{tenant}");
/// the service's reply.
pub async fn search_raw(body: &serde_json::Value, anchor: &str) -> Result<serde_json::Value> {
    let token = crate::auth::oauth::access_token_for(SCOPE).await.context("Search token")?;
    let request_id = uuid::Uuid::new_v4().to_string();
    let mut req = reqwest::Client::new()
        .post(SEARCH_URL)
        .bearer_auth(token)
        .header("x-client-flights", FLIGHTS)
        .header("x-client-version", "T2.1")
        .header("x-client-ui-language", "userLocale")
        .header("client-request-id", &request_id)
        .header("x-ms-request-id", &request_id);
    if !anchor.is_empty() {
        req = req.header("x-anchormailbox", anchor).header("x-routingparameter-sessionkey", anchor);
    }
    let resp = req
        .json(body)
        .send()
        .await
        .context("Search request")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(status.is_success(), "Search failed ({status}): {}", text.chars().take(300).collect::<String>());
    serde_json::from_str(&text).context("Search reply")
}

/// The words a card shows (its titles and texts, in order).
fn card_words(v: &serde_json::Value, out: &mut Vec<String>) {
    match v {
        serde_json::Value::Object(o) => {
            for (k, x) in o {
                match (k.as_str(), x) {
                    ("text" | "title" | "subtitle", serde_json::Value::String(t)) if !t.trim().is_empty() => out.push(plain(t)),
                    _ => card_words(x, out),
                }
            }
        }
        serde_json::Value::Array(a) => a.iter().for_each(|x| card_words(x, out)),
        _ => {}
    }
}

/// A message as a result row shows it: its text, then its cards' words.
pub fn row_text(m: &super::messages::MessageView) -> String {
    // (A shared contact's ID-card glyph isn't in Teams' row.)
    let mut words = vec![plain(&m.text.replace('\u{1FAAA}', " "))];
    for c in &m.cards {
        card_words(&c.content, &mut words);
    }
    words.retain(|w| !w.is_empty());
    words.join(" ")
}

/// The service's summaries are cut short; Teams shows each message whole,
/// so the results' messages are read (a few at a time).
pub async fn fill_texts(client: &super::client::TeamsClient, thread: &str, found: &mut Found) {
    use futures::StreamExt;
    let ids: Vec<(usize, String)> = found
        .hits
        .iter()
        .enumerate()
        .filter(|(_, h)| h.file_name.is_empty() && !h.id.is_empty())
        .map(|(i, h)| (i, h.id.clone()))
        .collect();
    let texts: Vec<(usize, Option<(String, String)>)> = futures::stream::iter(ids)
        .map(|(i, id)| async move {
            let m = super::messages::read_message(client, thread, &id).await.ok();
            (i, m.map(|m| (row_text(&m), m.subject.clone())))
        })
        .buffer_unordered(6)
        .collect()
        .await;
    for (i, t) in texts {
        let Some((text, subject)) = t else { continue };
        // A post's row: its subject (bold), then the subject and text.
        let hit = &mut found.hits[i];
        if !subject.is_empty() {
            hit.text = if text.is_empty() { subject.clone() } else { format!("{subject} {text}") };
            hit.subject = subject;
        } else if !text.is_empty() {
            hit.text = text;
        }
    }
}

/// Search `thread` as Teams' find pane does.
pub async fn search(
    client: &super::client::TeamsClient,
    thread: &str,
    keywords: &str,
    f: &Filters,
    from: usize,
    timezone: &str,
    my_oid: &str,
    tenant: &str,
) -> Result<Found> {
    let body = query_body(thread, keywords, f, from, timezone, my_oid, tenant);
    let anchor = if my_oid.is_empty() || tenant.is_empty() { String::new() } else { format!("OID:{my_oid}@{tenant}") };
    let mut found = found_from(&search_raw(&body, &anchor).await?);
    if !f.files {
        fill_texts(client, thread, &mut found).await;
    }
    Ok(found)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHAT: &str = "19:ef213c7c46cf4036b11608300e96fee4@thread.v2";
    const TAIL: &str = "clientthreadid:19:ef213c7c46cf4036b11608300e96fee4@thread.v2 AND NOT (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE)";

    #[test]
    fn the_query_is_teams() {
        let b = query_body(CHAT, "bubble", &Filters::default(), 0, "America/Los_Angeles", "", "");
        let r = &b["entityRequests"][0];
        assert_eq!(r["query"]["queryString"], format!("{TAIL} bubble"));
        assert_eq!(r["filter"]["term"]["conversationType"], "OneToOne");
        assert_eq!(r["size"], 25);
        assert_eq!(r["fields"].as_array().unwrap().len(), 11);
        assert_eq!(b["scenario"]["Name"], "powerbar");
        assert!(r["query"].get("queryAnnotations").is_none());
        // As Teams sent it in OST Test Team > General ("body").
        let g = Filters { channel_group: "1fac3ae3-c9c0-4ddb-90bb-58f52209c181".into(), ..Default::default() };
        let c = query_body("19:x@thread.tacv2", "body", &g, 0, "UTC", "", "");
        assert_eq!(c["entityRequests"][0]["filter"], serde_json::json!({"term": {"groupId": "1fac3ae3-c9c0-4ddb-90bb-58f52209c181"}}));
        assert_eq!(
            c["entityRequests"][0]["query"]["queryString"],
            "clientthreadid:19:x@thread.tacv2 AND (Extension_SkypeSpaces_ConversationPost_Extension_ThreadType_String:(topic OR space)) AND NOT (isClientSoftDeleted:TRUE) body"
        );
    }

    #[test]
    fn filters_are_teams_terms() {
        // As Teams sent them (winpc, OST group test, "bubble").
        let mut f = Filters { attachment: true, ..Default::default() };
        assert_eq!(query_string(CHAT, "bubble", &f, "4287e791-1b98-4963-8b94-281c50472683"), format!("hasattachment:yes AND {TAIL} bubble"));
        f.mentions = true;
        assert_eq!(
            query_string(CHAT, "bubble", &f, "4287e791-1b98-4963-8b94-281c50472683"),
            format!("hasattachment:yes AND mentions:4287e7911b9849638b94281c50472683 AND {TAIL} bubble")
        );
        f.start = "2026-11-08T08:00:00.000Z".into();
        f.end = "2026-11-15T08:00:00.000Z".into();
        f.from_mail = "someone@example.com".into();
        f.from_oid = "5050c9d6-0000-0000-0000-000000000000".into();
        assert_eq!(
            query_string(CHAT, "bubble", &f, "4287e791-1b98-4963-8b94-281c50472683"),
            format!("sent >= 2026-11-08T08:00:00.000Z AND sent < 2026-11-15T08:00:00.000Z AND hasattachment:yes AND mentions:4287e7911b9849638b94281c50472683 AND {TAIL} someone@example.com bubble")
        );
        let b = query_body(CHAT, "bubble", &f, 0, "UTC", "", "t1");
        assert_eq!(
            b["entityRequests"][0]["query"]["queryAnnotations"],
            serde_json::json!([{"type": "People", "text": "someone@example.com", "userId": "5050c9d6-0000-0000-0000-000000000000", "tenantId": "t1"}])
        );
    }

    #[test]
    fn file_hits_carry_what_teams_place_line_needs() {
        let reply = serde_json::json!({"EntitySets": [{"ResultSets": [{"Results": [
            {"Type": "File", "Source": {"FileName": "a.loop", "ChannelGroupId": "g1", "Path": "https://x/sites/T/Shared Documents/General/a.loop",
                                         "SpWebUrl": "https://x/sites/T", "DefaultEncodingUrl": "https://x/sites/T/Shared Documents/General/a.loop"}},
            {"Type": "File", "Source": {"FileName": "b.docx", "SpWebUrl": "https://x/sites/T"}}
        ]}]}]});
        let f = found_from(&reply);
        assert_eq!((f.hits[0].file_group_id.as_str(), f.hits[0].file_unredeemed), ("g1", false));
        assert_eq!((f.hits[1].file_group_id.as_str(), f.hits[1].file_unredeemed), ("", true));
    }

    #[test]
    fn files_are_a_onedrive_search() {
        let f = Filters {
            files: true,
            start: "2026-11-08T08:00:00.000Z".into(),
            end: "2026-11-15T08:00:00.000Z".into(),
            from_mail: "someone@example.com".into(),
            from_oid: "o".into(),
            ..Default::default()
        };
        let b = query_body(CHAT, "bubble", &f, 0, "UTC", "", "t1");
        let r = &b["entityRequests"][0];
        assert_eq!(r["entityType"], "File");
        assert_eq!(
            r["query"]["queryString"],
            "LastModifiedTime >= 2026-11-08T08:00:00.000Z AND LastModifiedTime < 2026-11-15T08:00:00.000Z AND someone@example.com bubble"
        );
        assert_eq!(r["query"]["queryAnnotations"][1], serde_json::json!({"type": "Chat", "id": CHAT, "text": "dummyText"}));
        assert_eq!(b["scenario"]["Dimensions"][0]["DimensionValue"], "ContextualFilesTypeAhead");
        let plain_files = Filters { files: true, ..Default::default() };
        assert_eq!(query_string(CHAT, "bubble", &plain_files, ""), "bubble");
    }

    #[test]
    fn a_row_shows_the_message_and_its_cards() {
        let m = crate::api::messages::MessageView {
            text: "Take a look at this app.\nHelp".into(),
            cards: vec![crate::api::messages::Card {
                content_type: "application/vnd.microsoft.card.adaptive".into(),
                content: serde_json::json!({"body": [{"type": "TextBlock", "text": "Help"}, {"type": "TextBlock", "text": "Microsoft Corporation"}]}),
                app_id: String::new(),
            }],
            ..Default::default()
        };
        assert_eq!(row_text(&m), "Take a look at this app. Help Help Microsoft Corporation");
    }

    #[test]
    fn find_in_post_names_the_post() {
        // As Teams sent it (a post's window, "OST").
        let f = Filters { post_root: "1794312231733".into(), ..Default::default() };
        let b = query_body("19:c@thread.tacv2", "OST", &f, 0, "UTC", "", "");
        let r = &b["entityRequests"][0];
        assert_eq!(r["query"]["queryString"], "clientconversationid:19:c@thread.tacv2;messageId=1794312231733 AND NOT (isClientSoftDeleted:TRUE) OST");
        assert!(r.get("filter").is_none());
    }

    #[test]
    fn channel_folders_are_named_as_teams() {
        assert_eq!(
            folder_path("https://x.sharepoint.com/sites/OSTTestTeam/Shared%20Documents/General"),
            "https://x.sharepoint.com/sites/OSTTestTeam/Shared Documents/General"
        );
    }

    #[test]
    fn file_types_and_channels_are_teams() {
        // As Teams sent them (Type ▸ Text file, This week; a channel's Files).
        let f = Filters {
            files: true,
            file_type: "text".into(),
            start: "2026-11-08T08:00:00.000Z".into(),
            end: "2026-11-15T08:00:00.000Z".into(),
            ..Default::default()
        };
        assert_eq!(
            query_string(CHAT, "attachment", &f, ""),
            "LastModifiedTime >= 2026-11-08T08:00:00.000Z AND LastModifiedTime < 2026-11-15T08:00:00.000Z AND (filetype:txt OR fileExtension:txt) AND attachment"
        );
        let w = Filters { files: true, file_type: "word".into(), ..Default::default() };
        assert_eq!(query_string(CHAT, "attachment", &w, ""), "(filetype:doc OR filetype:docx OR fileExtension:doc OR fileExtension:docx) AND attachment");
        let c = Filters {
            files: true,
            channel_group: "g".into(),
            channel_path: "https://x.sharepoint.com/sites/T/Shared Documents/General".into(),
            ..Default::default()
        };
        let b = query_body("19:c@thread.tacv2", "ost", &c, 0, "UTC", "", "t1");
        let r = &b["entityRequests"][0];
        assert_eq!(r["contentSources"], serde_json::json!(["SharePoint"]));
        assert_eq!(
            r["query"]["queryAnnotations"],
            serde_json::json!([{"type": "Channel", "threadId": "19:c@thread.tacv2", "text": "dummyText", "groupId": "g", "tenantId": "t1", "path": "https://x.sharepoint.com/sites/T/Shared Documents/General"}])
        );
    }

    #[test]
    fn results_come_from_the_entity_set() {
        // As the service answered "OST test" in OST group test.
        let reply = serde_json::json!({"EntitySets": [{"SearchTerms": ["ost", "test"], "ResultSets": [{
            "Total": 33, "MoreResultsAvailable": true, "Results": [{
                "Type": "Message",
                "HitHighlightedSummary": "Take a look at this app. <a href=\"https://x\" data-hyperlink=\"true\">Help</a>   https://x&amp;y",
                "Source": {
                    "DateTimeSent": "2026-11-09T11:32:21.112Z",
                    "InternetMessageId": "1794223941112",
                    "From": {"EmailAddress": {"Address": "ost-test1@example.com", "Name": "OST Test 1"}},
                    "Extensions": {
                        "SkypeSpaces_ConversationPost_Extension_FromSkypeInternalId": "8:orgid:4287e791-1b98-4963-8b94-281c50472683",
                        "SkypeSpaces_ConversationPost_Extension_ParentMessageId": "1794223941112"
                    }
                }
            }]
        }]}]});
        let f = found_from(&reply);
        assert_eq!((f.total, f.more), (33, true));
        assert_eq!(f.terms, ["ost", "test"]);
        let h = &f.hits[0];
        assert_eq!(h.id, "1794223941112");
        assert_eq!(h.parent_id, "", "a chat message is its own parent");
        assert_eq!(h.sender_name, "OST Test 1");
        assert_eq!(h.sender_mri, "8:orgid:4287e791-1b98-4963-8b94-281c50472683");
        assert_eq!(h.text, "Take a look at this app. Help https://x&y");
    }

    #[test]
    fn file_lines_read_as_teams_words_them() {
        // As the service answered "OST" on the Files tab (2026-11-11).
        let reply = serde_json::json!({"EntitySets": [{"ResultSets": [{"Results": [
            {"Type": "File", "Annotations": [{"Type": "Shared", "Timestamp": "2026-11-05T17:46:04.0000000Z", "User": {"DisplayName": "OST Test 1"}}],
             "Source": {"FileName": "ost-attachment-test.txt", "ModifiedBy": "OST Test 1", "LastModifiedTime": "2026-11-05T17:45:45Z"}},
            {"Type": "File", "Annotations": [{"Type": "Modified", "Timestamp": "2026-11-07T02:12:12.0000000Z", "User": {"DisplayName": "OST Test 1"}}],
             "Source": {"FileName": "Untitled", "ModifiedBy": "OST Test 1"}},
            {"Type": "File", "Source": {"FileName": "All.aspx", "Author": "System Account", "LastModifiedTime": "2026-11-08T23:41:49Z"}}
        ]}]}]});
        let f = found_from(&reply);
        let line = |i: usize| (f.hits[i].file_action.as_str(), f.hits[i].file_by.as_str(), f.hits[i].file_when.as_str());
        assert_eq!(line(0), ("Shared by", "OST Test 1", "2026-11-05T17:46:04.0000000Z"));
        assert_eq!(line(1), ("Modified by", "OST Test 1", "2026-11-07T02:12:12.0000000Z"));
        assert_eq!(line(2), ("", "System Account", ""));
        assert_eq!(f.hits[0].sender_name, "OST Test 1", "Find in chat keeps the modifier");
    }
}

