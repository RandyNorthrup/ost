//! Trouter registrar — registers our endpoint with the Teams notification service

use anyhow::{Context, Result};

/// Registration entry: appId, templateKey, path suffix, context
struct RegEntry {
    app_id: &'static str,
    template_key: &'static str,
    path_suffix: &'static str,
    context: &'static str,
}

const REGISTRATIONS: &[RegEntry] = &[
    RegEntry {
        // Business-tenant CDL registration (template 2.1, empty
        // transport context). Was 2.6 + transport context "TFL" (the
        // consumer "Teams for Life" product context, and in the wrong
        // field): registrations succeeded but no chat-service messaging
        // push ever reached the socket.
        app_id: "TeamsCDLWebWorker",
        template_key: "TeamsCDLWebWorker_2.1",
        path_suffix: "",
        context: "",
    },
    RegEntry {
        app_id: "SkypeSpacesWeb",
        template_key: "SkypeSpacesWeb_2.4",
        path_suffix: "SkypeSpacesWeb",
        context: "",
    },
    RegEntry {
        app_id: "NextGenCalling",
        template_key: "DesktopNgc_2.5:SkypeNgc",
        path_suffix: "NGCallManagerWin",
        context: "",
    },
];

/// Register our trouter endpoint with the Teams registrar service.
///
/// Performs three separate registrations (TeamsCDLWebWorker, SkypeSpacesWeb,
/// NextGenCalling) as the real Teams client does.
pub async fn register(
    http: &reqwest::Client,
    skype_token: &str,
    registrar_url: &str,
    trouter_surl: &str,
) -> Result<()> {
    register_with_endpoint(http, skype_token, registrar_url, trouter_surl, None).await
}

/// Like [`register`], but the CDL (chat) registration's
/// `registrationId` is the socket's endpoint id (`epid`), as the Teams
/// clients do; other apps keep a random id.
pub async fn register_with_endpoint(
    http: &reqwest::Client,
    skype_token: &str,
    registrar_url: &str,
    trouter_surl: &str,
    epid: Option<&str>,
) -> Result<()> {
    register_all(http, skype_token, registrar_url, trouter_surl, epid, None).await
}

/// This process's calling registration id: Teams' calling endpoint id,
/// which is also its Better Together endpoint id.
/// It is kept across runs (the profile's `calling-endpoint-id`), as Teams
/// keeps its own: paired phones know the PC by it.
pub fn calling_registration_id() -> &'static str {
    static ID: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    ID.get_or_init(|| {
        // A second client of the same profile on one machine (the emulated
        // phone) names its own.
        if let Some(id) = std::env::var("OST_CALLING_ENDPOINT_ID")
            .ok()
            .filter(|s| uuid::Uuid::parse_str(s).is_ok())
        {
            return id;
        }
        let path = crate::config::Config::config_dir()
            .ok()
            .map(|d| d.join("calling-endpoint-id"));
        if let Some(id) = path
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .map(|s| s.trim().to_string())
            .filter(|s| uuid::Uuid::parse_str(s).is_ok())
        {
            return id;
        }
        let id = uuid::Uuid::new_v4().to_string();
        if let Some(p) = path {
            if let Some(dir) = p.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            let _ = std::fs::write(&p, &id);
        }
        id
    })
}

/// Like [`register_with_endpoint`]; with `better_together` the calling
/// (NextGenCalling) registration also carries Teams' Better Together
/// transport, as Teams desktop registers it: a second Trouter transport
/// with context `BetterTogether` at `<base>bettertogether/send` (`base`:
/// the session's `url`, the socket's address for user-token senders), under the
/// calling registration id ([`calling_registration_id`]).
pub async fn register_all(
    http: &reqwest::Client,
    skype_token: &str,
    registrar_url: &str,
    trouter_surl: &str,
    epid: Option<&str>,
    better_together: Option<&str>,
) -> Result<()> {
    let url = registrar_url.trim_end_matches('/').to_string();

    for entry in REGISTRATIONS {
        let calling = entry.app_id == "NextGenCalling";
        let reg_id = match epid {
            Some(e) if entry.app_id == "TeamsCDLWebWorker" && !e.trim().is_empty() => e.to_string(),
            _ if calling && better_together.is_some() => calling_registration_id().to_string(),
            _ => uuid::Uuid::new_v4().to_string(),
        };
        let path = format!("{}{}", trouter_surl, entry.path_suffix);
        let mut transports =
            vec![serde_json::json!({"context": entry.context, "path": path, "ttl": 86400})];
        if calling && let Some(base) = better_together {
            transports.push(serde_json::json!({
                "context": crate::api::better_together::TRANSPORT_CONTEXT,
                "path": crate::api::better_together::trouter_url(base),
                "ttl": 86400
            }));
        }

        let payload = serde_json::json!({
            "clientDescription": {
                "appId": entry.app_id,
                "aesKey": "",
                "languageId": "en-US",
                "platform": "edge",
                "templateKey": entry.template_key,
                "platformUIVersion": "49/1.0.0"
            },
            "registrationId": reg_id,
            "nodeId": "",
            "transports": { "TROUTER": transports }
        });

        tracing::info!(
            "Registering {} at {} (appId={}, templateKey={})",
            if entry.path_suffix.is_empty() {
                "base"
            } else {
                entry.path_suffix
            },
            url,
            entry.app_id,
            entry.template_key,
        );

        let resp = http
            .post(&url)
            .header("X-Skypetoken", skype_token)
            .json(&payload)
            .send()
            .await
            .context("Registrar POST failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Registrar {} returned {}: {}", entry.app_id, status, body);
        }
        tracing::info!("Registrar {} registration succeeded", entry.app_id);
    }

    Ok(())
}

/// Re-register only the CDL (chat) entry under `template_key`
/// with `registrationId` = `epid` (same id → replaces the first one). The
/// Teams clients do this with `TeamsCDLWebWorker_1.9` when the server
/// reports `trouter.message_loss` right after connect.
pub async fn register_cdl(
    http: &reqwest::Client,
    skype_token: &str,
    registrar_url: &str,
    trouter_surl: &str,
    epid: &str,
    template_key: &str,
) -> Result<()> {
    let payload = serde_json::json!({
        "clientDescription": {
            "appId": "TeamsCDLWebWorker",
            "aesKey": "",
            "languageId": "en-US",
            "platform": "edge",
            "templateKey": template_key,
            "platformUIVersion": "49/1.0.0"
        },
        "registrationId": epid,
        "nodeId": "",
        "transports": {"TROUTER": [{"context": "", "path": trouter_surl, "ttl": 86400}]}
    });
    let resp = http
        .post(registrar_url.trim_end_matches('/'))
        .header("X-Skypetoken", skype_token)
        .json(&payload)
        .send()
        .await
        .context("Registrar POST failed")?;
    let status = resp.status();
    if !status.is_success() {
        anyhow::bail!("Registrar CDL {} returned {}", template_key, status);
    }
    tracing::info!("Registrar CDL {} registration succeeded", template_key);
    Ok(())
}

/// Teams free's chat registrar (its web client's `registrarDefaultEndpoint`;
/// a work account's comes from the Trouter negotiate).
pub const PERSONAL_REGISTRAR: &str = "https://edge.skype.com/registrar/prod/v2/registrations";
/// How long a personal account's registrations last, as Teams free's web
/// client asks (re-registered before then).
pub const PERSONAL_TTL_SECS: u64 = 3600;
/// Teams free's web client version, as its registrations name it.
const PERSONAL_UI_VERSION: &str = "1415/26101516645";

/// The two chat registrations Teams free's web client makes for a
/// personal account's socket (captured on teams.live.com 2026-11-27/28;
/// it answers 202): the
/// chat worker under template `TeamsCDLWebWorker_2.7` with product
/// context `TFL` (whose pushes carry personal chats' messages, typing
/// and read receipts), and `<epid>_GG` under `TeamsCDLWebWorker_2.3` with
/// no context.
pub fn personal_registrations(surl: &str, epid: &str) -> Vec<serde_json::Value> {
    let entry =
        |id: String, template: &str, context: &str, language: &str, path: &str, ttl: u64| {
            serde_json::json!({
                "clientDescription": {
                    "appId": "TeamsCDLWebWorker",
                    "aesKey": "",
                    "languageId": language,
                    "platform": "edge",
                    "templateKey": template,
                    "platformUIVersion": PERSONAL_UI_VERSION,
                    "productContext": context
                },
                "registrationId": id,
                "nodeId": "",
                "transports": {"TROUTER": [{"context": "", "path": path, "ttl": ttl}]}
            })
        };
    let with_slash = format!("{}/", surl.trim_end_matches('/'));
    vec![
        entry(
            epid.to_string(),
            "TeamsCDLWebWorker_2.7",
            "TFL",
            "en-US",
            &with_slash,
            PERSONAL_TTL_SECS,
        ),
        // (as the web client sends it: no language, the path without its
        // trailing slash)
        entry(
            format!("{epid}_GG"),
            "TeamsCDLWebWorker_2.3",
            "",
            "",
            surl.trim_end_matches('/'),
            86523,
        ),
    ]
}

/// Register a personal account's Trouter socket for its chat pushes at
/// Teams free's registrar ([`personal_registrations`]), with the headers
/// its web client sends.
pub async fn register_personal(
    http: &reqwest::Client,
    skype_token: &str,
    trouter_surl: &str,
    epid: &str,
) -> Result<()> {
    for payload in personal_registrations(trouter_surl, epid) {
        let template = payload["clientDescription"]["templateKey"]
            .as_str()
            .unwrap_or_default()
            .to_string();
        let resp = http
            .post(PERSONAL_REGISTRAR)
            .header("X-Skypetoken", skype_token)
            .header("X-MS-Migration", "True")
            .header("x-ms-test-user", "False")
            .json(&payload)
            .send()
            .await
            .context("Registrar POST failed")?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!(
                "Registrar {template} returned {status}: {}",
                crate::feedback::scrub_secrets(&body)
            );
        }
        tracing::info!("Registrar {template} registration succeeded (personal)");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_personal_socket_registers_as_teams_free() {
        let r = personal_registrations("https://pub-csm-x-f.trouter.skype.com:3443/v4/f/A/", "ep");
        assert_eq!(r.len(), 2);
        assert_eq!(r[0]["registrationId"], "ep");
        assert_eq!(
            r[0]["clientDescription"]["templateKey"],
            "TeamsCDLWebWorker_2.7"
        );
        assert_eq!(r[0]["clientDescription"]["productContext"], "TFL");
        assert_eq!(r[0]["transports"]["TROUTER"][0]["ttl"], 3600);
        assert_eq!(
            r[0]["transports"]["TROUTER"][0]["path"],
            "https://pub-csm-x-f.trouter.skype.com:3443/v4/f/A/"
        );
        assert_eq!(r[1]["registrationId"], "ep_GG");
        assert_eq!(
            r[1]["clientDescription"]["templateKey"],
            "TeamsCDLWebWorker_2.3"
        );
        assert_eq!(r[1]["clientDescription"]["productContext"], "");
        assert_eq!(
            r[1]["transports"]["TROUTER"][0]["path"],
            "https://pub-csm-x-f.trouter.skype.com:3443/v4/f/A"
        );
    }
}
