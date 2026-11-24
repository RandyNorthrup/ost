//! Copilot's "Suggested names" in OneDrive's Rename, as Teams' Files app
//! shows them (OneDrive's RenameSuggestions, captured on winpc 2026-11-19;
//! docs/spec/file-actions.md "Rename").
//!
//! OneDrive first reads the file's sensitivity label from Graph and gives up
//! on "Highly Confidential" / "Restricted" protected files. Otherwise it opens
//! an AugLoop session of its own for each request
//! (`wss://augloop.svc.cloud.microsoft/`, appName "odsp") and:
//! - adds an `AugLoop_OdspCopilot_ODSPCopilotInputSignal` ("main") with its
//!   prompt, the file (`{fileName, siteId, webId, listId, uniqueId}`, braced
//!   GUIDs) as the data source and the scenario's `llmScenarioGuid`;
//! - seeds the "doc" document, activates
//!   `AugLoop_OdspCopilot_ODSPCopilotOutputAnnotation`, provides the token and
//!   adds the "context" scope (the file as entity constraint and selection);
//! - reads the answer from the annotations: bot "Chat" message text plus the
//!   `basinWrite` pieces (each a JSON string), NDJSON lines of
//!   `{"type":"suggestion","name":…}`, then `{"type":"done"}` or one
//!   `{"type":"error","code":…}`; chatResponse status 13 is a partial
//!   answer, 0 the end.

use futures::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio_tungstenite::tungstenite::Message;

/// OneDrive's scenario for rename suggestions.
pub const LLM_SCENARIO: &str = "f44f84d5-dd13-4369-9939-c8cb945fe62f";
/// The annotation OneDrive activates.
pub const ANNOTATION: &str = "AugLoop_OdspCopilot_ODSPCopilotOutputAnnotation";
const SIGNAL: &str = "AugLoop_OdspCopilot_ODSPCopilotInputSignal";

/// OneDrive's prompt (its NDJSON variant, the one Teams sent).
pub const PROMPT: &str = "Suggest 3 clear, descriptive filenames (without extension) for this file based on its content.\nFor image files, base the name on the visual content (subjects, scene, setting, or key objects).\n\nLANGUAGE\n- Write the suggested names in the same natural language as the content of the file (e.g. Spanish content → Spanish names, Japanese content → Japanese names). The English-style examples below are formatting guidance only; do NOT translate the content into English. Only fall back to English when the content language is genuinely indeterminate.\n\nNAMING RULES\n- 4–8 words, title case (or the equivalent capitalization convention for the target language), use \" – \" (en-dash) between components.\n- Aim for ≤40 characters; never exceed 55 characters.\n- Prefer 2 components (purpose + 1 key differentiator). Add a third component only when the total stays under 55 chars.\n- Drop generic filler when already implied by the doc type (\"Summary\", \"Overview\", \"Analysis\", \"Data\", \"Report\").\n- Use concise references: \"Q2 2024\" not \"Quarter 2 2024\"; \"FY25\" not \"Fiscal Year 2025\".\nONEDRIVE/SHAREPOINT VALIDITY RULES (MUST FOLLOW)\n- Output ONLY the base name (no extension) and do not add quotes.\n- Do NOT use any of these characters anywhere in the name: \" * : < > ? / \\\\ .\n- No leading or trailing spaces.\n- Do NOT output any of these reserved names (case-insensitive): CON, PRN, AUX, NUL, COM0–COM9, LPT0–LPT9, .lock, _vti_, desktop.ini.\n- Do NOT start the name with \"~$\".\n\nCRITICAL: Output is NDJSON — one JSON object per line, no surrounding array, no commas between lines. Emit suggestions as you generate them so the client can render incrementally.\n\nSuccess: emit 3 suggestion events followed by a single done event:\n  {\"type\":\"suggestion\",\"name\":\"<name>\"}\n  ... (repeat 3 times) ...\n  {\"type\":\"done\"}\n\nError: emit exactly one error event and nothing else:\n{\"type\":\"error\",\"code\":\"<code>\"}\nwhere <code> is one of:\n- \"InsufficientContent\": the file is empty, has minimal/no readable content, or otherwise lacks enough information to derive meaningful names. Use this whenever you simply do not see content to work with.\n- \"FileNotAvailable\": the file does not exist, was deleted, or otherwise could not be located.\n- \"Confidential\": you received an explicit access-denied signal because the file is protected by an information-protection policy (encrypted content, IRM / sensitivity label that blocks access). Do NOT use this just because content is missing or sparse — only when access itself was refused.\n- \"UnknownError\": otherwise\n\nDo not output any other lines, fields, or explanatory text.";

/// The extensions OneDrive offers suggestions for (its module 5164).
const EXTENSIONS: &[&str] = &[
    "doc", "docx", "docm", "dot", "dotx", "dotm", "xls", "xlsx", "xlsm", "xlt", "xltx", "xltm", "ppt", "pptx", "pptm", "pot", "potx", "potm", "pdf", "txt",
    "rtf", "csv", "tsv", "json", "md", "odt", "ods", "odp", "jpg", "jpeg", "png", "bmp", "tiff", "tif",
];

/// Whether OneDrive offers Suggested names for a file with this name.
pub fn offered_for(name: &str) -> bool {
    name.rsplit_once('.').is_some_and(|(_, ext)| EXTENSIONS.contains(&ext.to_ascii_lowercase().as_str()))
}

/// The file as OneDrive names it to Copilot.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FileInfo {
    pub file_name: String,
    pub site_id: String,
    pub web_id: String,
    pub list_id: String,
    pub unique_id: String,
}

fn braced(g: &str) -> String {
    let g = g.trim_matches(|c| c == '{' || c == '}');
    format!("{{{g}}}")
}

impl FileInfo {
    fn json(&self) -> Value {
        json!({"fileName": self.file_name, "siteId": braced(&self.site_id), "webId": braced(&self.web_id),
            "listId": braced(&self.list_id), "uniqueId": braced(&self.unique_id.to_uppercase())})
    }
}

/// How a request ended: the names (at most three) or OneDrive's error code
/// ("InsufficientContent", "FileNotAvailable", "Confidential", or "Generic"
/// for anything else).
pub type Outcome = Result<Vec<String>, String>;

fn h(t: &str, b: &[&str]) -> Value {
    json!({"T_": t, "B_": b})
}

/// The input signal's sync operation, as OneDrive adds it.
pub fn signal_op(query_id: &str, file: &FileInfo) -> Value {
    json!({"parentPath": ["Signal", SIGNAL],
        "items": [{"id": "main", "body": {"queryId": query_id, "query": PROMPT, "isNewConversation": true, "raw": false, "disableStreaming": false,
            "dataSources": {"dataSources": {"files": [file.json()]}}, "llmScenarioGuid": LLM_SCENARIO,
            "H_": h(SIGNAL, &["AugLoop_OdspCopilot_ODSPBaseCopilotInputSignal", "AugLoop_Copilot_CopilotInputSignal", "AugLoop_Copilot_SignalWithQueryId", "AugLoop_Signals_Signal"])},
            "contextId": "C1"}],
        "H_": h("AugLoop_Signals_SignalOperation", &["AugLoop_Core_Operation"])})
}

/// The "context" scope OneDrive adds under the session.
pub fn context_op(file: &FileInfo) -> Value {
    let mut c = file.json();
    c["@domainType"] = json!("File");
    json!({"parentPath": ["session"],
        "items": [{"id": "context", "body": {"searchContext": {"domains": ["File"], "entityConstraints": [c]},
            "selectionContext": {"File": [{"name": file.file_name}]},
            "H_": h("AugLoop_OdspCopilot_ODSPCopilotScopeContext", &["AugLoop_Core_Annotation"])}, "contextId": "C4"}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])})
}

/// OneDrive's SessionInit for its Copilot session.
pub fn session_init(ui_language: &str, cv: &str, mid: &str) -> Value {
    json!({"protocolVersion": 2,
        "clientMetadata": {"appName": "odsp", "appPlatform": "Web",
            "flights": "enableAnalyzeImagePlugin:true;Microsoft.Office.AugLoop.PreserveSliceUrlOnOffline:true;Microsoft.Office.AugLoop.OfflineConnectionCheckIntervalMs:15000",
            "releaseAudienceGroup": "Production", "sessionId": format!("alproxy_{}", uuid::Uuid::new_v4()), "uiLanguage": ui_language},
        "extensionConfigs": [], "returnWorkflowInputTypes": true, "enableRemoteExecutionNotification": false, "createBlobStorageContainer": false,
        "H_": h("AugLoop_Session_Protocol_SessionInitMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})
}

/// What one annotation message adds to the answer: (text so far after it,
/// whether it is the end).
pub fn absorb(v: &Value, query_id: &str, so_far: &mut String) -> Option<bool> {
    if v["annotationType"].as_str() != Some(ANNOTATION) {
        return None;
    }
    let mut end = None;
    for op in v["ops"].as_array().into_iter().flatten() {
        for it in op["items"].as_array().into_iter().flatten() {
            let b = &it["body"];
            if b["queryId"].as_str().is_some_and(|q| q != query_id) {
                continue;
            }
            let cr = &b["chatResponse"];
            let status = cr["status"].as_i64();
            if status == Some(0) {
                // The whole answer: the last bot Chat message.
                let msgs = cr["messagesToAddOrReplace"].as_array().or_else(|| cr["messages"].as_array());
                if let Some(t) = msgs.into_iter().flatten().rev().find(|m| m["author"] == "bot" && m["messageType"] == "Chat").and_then(|m| m["text"].as_str()) {
                    *so_far = t.to_string();
                }
                end = Some(true);
                continue;
            }
            for m in cr["messagesToAddOrReplace"].as_array().into_iter().flatten() {
                if m["author"] == "bot" && m["messageType"] == "Chat" {
                    so_far.push_str(m["text"].as_str().unwrap_or_default());
                }
            }
            if let Some(w) = cr["basinWrite"].as_str()
                && let Ok(piece) = serde_json::from_str::<String>(w)
            {
                so_far.push_str(&piece);
            }
            if b["error"].is_object() || status.is_some_and(|s| s != 13 && s != 0) {
                end = Some(true);
            } else if end.is_none() {
                end = Some(false);
            }
        }
    }
    end
}

/// OneDrive's reading of the NDJSON answer (`partial`: the last line may be
/// cut, so it is left out).
pub fn parse(text: &str, partial: bool) -> Outcome {
    let body = if partial { text.rfind('\n').map(|i| &text[..i]).unwrap_or("") } else { text };
    let mut names = Vec::new();
    for line in body.split('\n') {
        let l = line.trim();
        if !l.starts_with('{') {
            continue;
        }
        let Ok(v) = serde_json::from_str::<Value>(l) else { continue };
        match v["type"].as_str() {
            Some("suggestion") => {
                if let Some(n) = v["name"].as_str().filter(|n| !n.is_empty()) {
                    names.push(n.to_string());
                }
            }
            Some("error") => return Err(v["code"].as_str().filter(|c| !c.is_empty()).unwrap_or("Generic").to_string()),
            _ => {}
        }
    }
    names.truncate(3);
    Ok(names)
}

/// Whether Graph's sensitivity label keeps OneDrive from asking (a
/// protected "Highly Confidential" or "Restricted" label).
pub fn is_confidential(item: &Value) -> bool {
    let l = &item["sensitivityLabel"];
    l["protectionEnabled"].as_bool() == Some(true)
        && matches!(l["displayName"].as_str().unwrap_or_default().split(" \\ ").next().unwrap_or_default(), "Highly Confidential" | "Restricted")
}

/// The file's ids and whether it is confidential (Graph's `sharepointIds`
/// and, as OneDrive reads it on its own, `sensitivityLabel`); with the
/// SharePoint origin its page would run on.
pub async fn file_info(client: &crate::api::client::TeamsClient, drive: &str, item: &str) -> anyhow::Result<(FileInfo, String, bool)> {
    let v: Value = client.graph_get(&format!("/drives/{drive}/items/{item}?$select=name,sharepointIds")).await?.error_for_status()?.json().await?;
    let s = |p: &str| v.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    let info = FileInfo {
        file_name: s("/name"),
        site_id: s("/sharepointIds/siteId"),
        web_id: s("/sharepointIds/webId"),
        list_id: s("/sharepointIds/listId"),
        unique_id: s("/sharepointIds/listItemUniqueId"),
    };
    anyhow::ensure!(!info.unique_id.is_empty() && !info.site_id.is_empty(), "The file has no SharePoint ids");
    let site = s("/sharepointIds/siteUrl");
    let origin = site.find("://").and_then(|i| site[i + 3..].find('/').map(|j| site[..i + 3 + j].to_string())).unwrap_or(site);
    // OneDrive treats a failed label read as "not confidential".
    let confidential = match client.graph_get(&format!("/drives/{drive}/items/{item}?$select=sensitivityLabel")).await {
        Ok(r) if r.status().is_success() => r.json::<Value>().await.map(|l| is_confidential(&l)).unwrap_or(false),
        _ => false,
    };
    Ok((info, origin, confidential))
}

async fn token() -> anyhow::Result<String> {
    crate::auth::oauth::access_token_for("https://augloop.office.com/v2/.default").await
}

/// Ask Copilot for names for `file` as OneDrive does; `partial` gets the
/// names as they stream in. `origin` is the SharePoint host OneDrive's page
/// runs on.
pub async fn suggest(file: &FileInfo, origin: &str, ui_language: &str, partial: impl Fn(Vec<String>)) -> anyhow::Result<Outcome> {
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request("wss://augloop.svc.cloud.microsoft/")?;
    req.headers_mut().insert("Origin", origin.parse()?);
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await?;
    let id = uuid::Uuid::new_v4().simple().to_string();
    let mut n = 0u64;
    let next = |n: &mut u64| {
        *n += 1;
        (format!("ost{}.{}", &id[..12], n), format!("c{n}"))
    };
    let send = |v: Value| Message::Text(v.to_string().into());
    let (cv, mid) = next(&mut n);
    ws.send(send(session_init(ui_language, &cv, &mid))).await?;
    let wait = std::time::Duration::from_secs(20);
    loop {
        let Some(m) = tokio::time::timeout(wait, ws.next()).await? else { anyhow::bail!("AugLoop closed") };
        if let Message::Text(t) = m?
            && t.as_str() != "~"
        {
            let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
            if v.get("sessionKey").is_some() {
                break;
            }
            if v.pointer("/H_/T_").and_then(|x| x.as_str()).is_some_and(|t| t.contains("Error")) {
                anyhow::bail!("AugLoop refused the session");
            }
        }
    }
    let query_id = uuid::Uuid::new_v4().to_string();
    let (cv, mid) = next(&mut n);
    ws.send(send(json!({"cv": cv, "ops": [signal_op(&query_id, file)], "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid}))).await?;
    let (cv, mid) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 0, "ops": [{"parentPath": ["session"], "items": [{"id": "doc", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
    .await?;
    let (cv, mid) = next(&mut n);
    ws.send(send(json!({"annotationType": ANNOTATION, "token": uuid::Uuid::new_v4().to_string(), "ignoreExistingAnnotations": false, "sendStateUpdates": false,
        "returnAnnotationDoesNotExist": true, "sendApologies": false,
        "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})))
    .await?;
    let (cv, mid) = next(&mut n);
    ws.send(send(json!({"authToken": token().await?, "version": 1, "H_": h("AugLoop_Session_Protocol_TokenProvisionMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})))
        .await?;
    let (cv, mid) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 1, "ops": [context_op(file)], "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
        .await?;
    let mut text = String::new();
    let mut shown = 0usize;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(90);
    let outcome = loop {
        let m = match tokio::time::timeout_at(deadline, ws.next()).await {
            Err(_) => break Err("Generic".to_string()),
            Ok(None) | Ok(Some(Err(_))) => break Err("Generic".to_string()),
            Ok(Some(Ok(m))) => m,
        };
        let Message::Text(t) = m else { continue };
        if t.as_str() == "~" {
            continue;
        }
        let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
        if let Some(mid) = v["messageId"].as_str().filter(|m| m.starts_with('s')) {
            ws.send(send(json!({"H_": h("AugLoop_Session_Protocol_Response", &[]), "messageId": mid}))).await?;
        }
        match absorb(&v, &query_id, &mut text) {
            Some(true) => break parse(&text, false),
            Some(false) => {
                if let Ok(names) = parse(&text, true)
                    && names.len() > shown
                {
                    shown = names.len();
                    partial(names);
                }
            }
            None => {}
        }
    };
    let _ = ws.close(None).await;
    Ok(match outcome {
        Ok(names) if names.is_empty() => Err("Generic".to_string()),
        o => o,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file() -> FileInfo {
        FileInfo {
            file_name: "ost-share-test.txt".into(),
            site_id: "fa160c33-a34a-4705-87b6-1f62802d97df".into(),
            web_id: "21b0d3cf-2b9e-45f6-a12e-fcf782c99233".into(),
            list_id: "0e0a18f3-101b-4090-a53e-1e24c4d98efd".into(),
            unique_id: "1dd3508e-41d2-4fb6-8358-d55e775d08eb".into(),
        }
    }

    #[test]
    fn signal_is_onedrives() {
        let op = signal_op("q1", &file());
        assert_eq!(op["parentPath"], json!(["Signal", "AugLoop_OdspCopilot_ODSPCopilotInputSignal"]));
        let b = &op["items"][0]["body"];
        assert_eq!(b["dataSources"]["dataSources"]["files"][0]["uniqueId"], "{1DD3508E-41D2-4FB6-8358-D55E775D08EB}");
        assert_eq!(b["dataSources"]["dataSources"]["files"][0]["siteId"], "{fa160c33-a34a-4705-87b6-1f62802d97df}");
        assert_eq!(b["llmScenarioGuid"], LLM_SCENARIO);
        let c = context_op(&file());
        assert_eq!(c["items"][0]["body"]["searchContext"]["entityConstraints"][0]["@domainType"], "File");
        assert_eq!(c["items"][0]["body"]["selectionContext"]["File"][0]["name"], "ost-share-test.txt");
    }

    #[test]
    fn answer_streams_through_basin_writes() {
        let ann = |cr: Value| json!({"annotationType": ANNOTATION, "ops": [{"items": [{"body": {"queryId": "q", "chatResponse": cr}}]}]});
        let mut t = String::new();
        assert_eq!(absorb(&ann(json!({"status": 13, "messagesToAddOrReplace": [{"author": "bot", "messageType": "Progress", "text": "Thinking..."}]})), "q", &mut t), Some(false));
        assert_eq!(absorb(&ann(json!({"status": 13, "messagesToAddOrReplace": [{"author": "bot", "messageType": "Chat", "text": "{\""}]})), "q", &mut t), Some(false));
        let piece = serde_json::to_string("type\":\"suggestion\",\"name\":\"OST Share Dialog – Safe To Delete\"}\n{\"type\":\"sugg").unwrap();
        assert_eq!(absorb(&ann(json!({"status": 13, "basinWrite": piece})), "q", &mut t), Some(false));
        assert_eq!(parse(&t, true), Ok(vec!["OST Share Dialog – Safe To Delete".to_string()]));
        let done = "{\"type\":\"suggestion\",\"name\":\"A\"}\n{\"type\":\"suggestion\",\"name\":\"B\"}\n{\"type\":\"suggestion\",\"name\":\"C\"}\n{\"type\":\"done\"}";
        assert_eq!(absorb(&ann(json!({"status": 0, "messagesToAddOrReplace": [{"author": "bot", "messageType": "Chat", "text": done}]})), "q", &mut t), Some(true));
        assert_eq!(parse(&t, false), Ok(vec!["A".into(), "B".into(), "C".into()]));
        assert_eq!(parse("{\"type\":\"error\",\"code\":\"InsufficientContent\"}", false), Err("InsufficientContent".into()));
    }

    #[test]
    fn offered_as_onedrive() {
        assert!(offered_for("ost-share-test.txt"));
        assert!(offered_for("Deck.PPTX"));
        assert!(!offered_for("clip.mp4"));
        assert!(!offered_for("folder"));
        assert!(is_confidential(&json!({"sensitivityLabel": {"protectionEnabled": true, "displayName": "Highly Confidential \\ All Employees"}})));
        assert!(!is_confidential(&json!({"sensitivityLabel": {"protectionEnabled": false, "displayName": "Restricted"}})));
    }
}
