//! Authenticated HTTP client for Teams APIs
//!
//! Wraps reqwest::Client with automatic token injection and refresh.

use anyhow::{Context, Result, bail};

use crate::auth::TokenStore;
use crate::auth::token_hosts::{self, Audience};
use crate::config::Config;

const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";
/// Teams web's User-Agent on Linux. AMS reads the platform from its
/// `Teams/{version}/{platform}` part; SharePoint words friendly dates only
/// for browsers.
pub const TEAMS_WEB_UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36 Teams/26276.513.5241.9675/1415";
const DEFAULT_CHAT_SERVICE: &str = "https://amer.ng.msg.teams.microsoft.com";
const CHATSVCAGG: &str = "https://chatsvcagg.teams.microsoft.com";

/// Authenticated client that handles both Graph (AAD) and Teams (Skype) APIs.
pub struct TeamsClient {
    http: reqwest::Client,
    config: Config,
}

impl TeamsClient {
    /// The signed-in user's display name, for message `imdisplayname`.
    pub fn display_name(&self) -> Option<String> {
        self.config.display_name()
    }

    /// The signed-in tenant.
    pub fn tenant_id(&self) -> Option<String> {
        self.config.tenant_id()
    }

    /// Teams' authz `licenseDetails` for the signed-in user.
    pub fn license_details(&self) -> Option<serde_json::Value> {
        self.config.get_license_details()
    }

    /// The signed-in user's sign-in name (user@domain).
    pub fn user_principal_name(&self) -> Option<String> {
        self.config.user_principal_name()
    }

    /// The signed-in user's object id (a work account's Entra `oid`).
    pub fn object_id(&self) -> Option<String> {
        self.config.object_id()
    }

    /// The signed-in account's identity.
    pub fn identity(&self) -> Option<&crate::identity::AccountIdentity> {
        self.config.identity()
    }

    /// The signed-in user's own MRI, to recognise their own messages and
    /// name them in requests.
    pub fn self_mri(&self) -> Option<String> {
        self.config.self_mri()
    }

    /// Load config and build client. Attempts token refresh if AAD token is expired.
    pub async fn new() -> Result<Self> {
        let mut config = Config::load()?;

        // Auto-refresh if any token is expired but refresh token exists
        let needs_refresh = config.get_access_token().is_none_or(|t| t.is_expired())
            || config.get_graph_token().is_none_or(|t| t.is_expired());
        if needs_refresh {
            if config.get_refresh_token().is_some() {
                tracing::info!("Tokens missing or expired, refreshing...");
                match crate::auth::oauth::refresh().await {
                    Ok(true) => {
                        config = Config::load()?;
                        tracing::info!("Token refreshed");
                    }
                    Ok(false) => {
                        bail!("No refresh token available. Run 'teams-cli login'.");
                    }
                    Err(e) => {
                        bail!("Token refresh failed: {:#}. Run 'teams-cli login'.", e);
                    }
                }
            } else {
                bail!("Token expired and no refresh token. Run 'teams-cli login'.");
            }
        }

        Ok(Self {
            http: token_hosts::http_client(),
            config,
        })
    }

    fn graph_token(&self) -> Result<String> {
        let token = self
            .config
            .get_graph_token()
            .context("No Graph token. Run 'teams-cli login' first.")?;
        if token.is_expired() {
            bail!("Graph token expired. Run 'teams-cli login'.");
        }
        Ok(token.token)
    }

    /// The Skype token, for services that want it as `x-skypetoken`.
    pub fn skype_token_value(&self) -> Result<String> {
        self.skype_token()
    }

    fn skype_token(&self) -> Result<String> {
        let token = self
            .config
            .get_skype_token()
            .context("No Skype token. Run 'teams-cli login' first.")?;
        if token.is_expired() {
            bail!("Skype token expired. Run 'teams-cli login'.");
        }
        Ok(token.token)
    }

    /// GET request to Microsoft Graph API (bearer auth with Graph token).
    pub async fn graph_get(&self, path: &str) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        tracing::debug!("Graph GET {}", url);

        let resp = self
            .http
            .get(&url)
            .bearer_auth(&token)
            .send()
            .await
            .with_context(|| format!("Graph GET {} failed", url))?;

        check_response(resp, &url).await
    }

    /// POST request to Microsoft Graph API (bearer auth with Graph token).
    /// GET with extra request headers (e.g. `ConsistencyLevel` for $search).
    pub async fn graph_get_with(
        &self,
        path: &str,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        tracing::debug!("Graph GET {}", url);
        let mut req = self.http.get(&url).bearer_auth(token);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        let resp = req
            .send()
            .await
            .with_context(|| format!("Graph GET {} failed", url))?;
        check_response(resp, &url).await
    }

    /// GET a Graph resource that may not exist: `Ok(None)` for 404.
    pub async fn graph_get_opt(&self, path: &str) -> Result<Option<reqwest::Response>> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .get(&url)
            .bearer_auth(&token)
            .send()
            .await
            .with_context(|| format!("Graph GET {} failed", url))?;
        if resp.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }
        Ok(Some(check_response(resp, &url).await?))
    }

    pub async fn graph_post(
        &self,
        path: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        tracing::debug!("Graph POST {}", url);

        let resp = self
            .http
            .post(&url)
            .bearer_auth(&token)
            .json(body)
            .send()
            .await
            .with_context(|| format!("Graph POST {} failed", url))?;

        check_response(resp, &url).await
    }

    /// GET or POST on Graph's beta endpoint (features v1.0 lacks, such as
    /// a site's recycle bin). `body` None is a GET.
    pub async fn graph_beta(
        &self,
        path: &str,
        body: Option<&serde_json::Value>,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("https://graph.microsoft.com/beta{}", path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let req = match body {
            Some(b) => self.http.post(&url).json(b),
            None => self.http.get(&url),
        }
        .bearer_auth(&token);
        let resp = req
            .send()
            .await
            .with_context(|| format!("Graph beta {} failed", url))?;
        check_response(resp, &url).await
    }

    /// POST a raw body with its content type (OneNote takes XHTML).
    pub async fn graph_post_raw(
        &self,
        path: &str,
        content_type: &str,
        body: String,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .post(&url)
            .bearer_auth(&token)
            .header(reqwest::header::CONTENT_TYPE, content_type)
            .body(body)
            .send()
            .await
            .with_context(|| format!("Graph {} failed", url))?;
        check_response(resp, &url).await
    }

    /// PATCH on Graph's beta endpoint.
    pub async fn graph_beta_patch(
        &self,
        path: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("https://graph.microsoft.com/beta{}", path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .patch(&url)
            .bearer_auth(&token)
            .json(body)
            .send()
            .await
            .with_context(|| format!("Graph beta {} failed", url))?;
        check_response(resp, &url).await
    }

    /// PATCH a Graph path with a JSON body.
    pub async fn graph_patch(
        &self,
        path: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .patch(&url)
            .bearer_auth(&token)
            .json(body)
            .send()
            .await
            .with_context(|| format!("Graph PATCH {} failed", url))?;
        check_response(resp, &url).await
    }

    /// PATCH or DELETE a Graph path with extra headers (Planner needs
    /// `If-Match: <etag>`); `body` is None for DELETE.
    pub async fn graph_change_with(
        &self,
        path: &str,
        body: Option<&serde_json::Value>,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let mut req = match body {
            Some(b) => self.http.patch(&url).json(b),
            None => self.http.delete(&url),
        }
        .bearer_auth(&token);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        let resp = req
            .send()
            .await
            .with_context(|| format!("Graph change {} failed", url))?;
        check_response(resp, &url).await
    }

    /// DELETE a Graph path.
    pub async fn graph_delete(&self, path: &str) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .delete(&url)
            .bearer_auth(&token)
            .send()
            .await
            .with_context(|| format!("Graph DELETE {} failed", url))?;
        check_response(resp, &url).await
    }

    /// PUT raw bytes to a Graph path (small file uploads).
    pub async fn graph_put_bytes(
        &self,
        path: &str,
        bytes: Vec<u8>,
        content_type: &str,
    ) -> Result<reqwest::Response> {
        let token = self.graph_token()?;
        let url = format!("{}{}", GRAPH_BASE, path);
        token_hosts::ensure(&url, Audience::Graph)?;
        let resp = self
            .http
            .put(&url)
            .bearer_auth(&token)
            .header("Content-Type", content_type)
            .body(bytes)
            .send()
            .await
            .with_context(|| format!("Graph PUT {} failed", url))?;
        check_response(resp, &url).await
    }

    /// GET request to Teams/Skype API (X-SkypeToken header).
    pub async fn teams_get(&self, url: &str) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Teams GET {}", url);

        let resp = self
            .http
            .get(url)
            .header("X-SkypeToken", &token)
            .send()
            .await
            .with_context(|| format!("Teams GET {} failed", url))?;

        check_response(resp, url).await
    }

    /// POST request to Teams/Skype API (X-SkypeToken header).
    pub async fn teams_post(
        &self,
        url: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Teams POST {}", url);

        let resp = self
            .http
            .post(url)
            .header("X-SkypeToken", &token)
            .json(body)
            .send()
            .await
            .with_context(|| format!("Teams POST {} failed", url))?;

        check_response(resp, url).await
    }

    /// Chat service base URL from region_gtms, falling back to default.
    pub fn chat_service_url(&self) -> String {
        self.config
            .get_region_gtms()
            .and_then(|v| {
                v.get("chatService")
                    .and_then(|s| s.as_str())
                    .map(String::from)
            })
            .unwrap_or_else(|| DEFAULT_CHAT_SERVICE.to_string())
    }

    /// The Teams middle-tier base URL (e.g. …/api/mt/part/amer-03) from
    /// region_gtms, which serves pictures among other things.
    pub fn middle_tier_url(&self) -> Option<String> {
        self.config
            .get_region_gtms()?
            .get("middleTier")?
            .as_str()
            .filter(|u| u.starts_with("https://"))
            .map(|u| u.trim_end_matches('/').to_string())
    }

    /// Any https endpoint from region_gtms by its key (such as
    /// "appsSuggestionService").
    pub fn region_endpoint(&self, key: &str) -> Option<String> {
        self.config
            .get_region_gtms()?
            .get(key)?
            .as_str()
            .filter(|u| u.starts_with("https://"))
            .map(|u| u.trim_end_matches('/').to_string())
    }

    /// Teams' media store (AMS) base URL from region_gtms ("ams").
    pub fn ams_url(&self) -> Option<String> {
        self.config
            .get_region_gtms()?
            .get("ams")?
            .as_str()
            .filter(|u| u.starts_with("https://"))
            .map(|u| u.trim_end_matches('/').to_string())
    }

    /// The AMS v2 gateway (asyncgw) base URL from region_gtms ("amsV2"),
    /// where custom emoji pictures are served.
    pub fn ams_v2_url(&self) -> Option<String> {
        self.config
            .get_region_gtms()?
            .get("amsV2")?
            .as_str()
            .filter(|u| u.starts_with("https://"))
            .map(|u| u.trim_end_matches('/').to_string())
    }

    /// The shared HTTP client.
    pub fn http(&self) -> &reqwest::Client {
        &self.http
    }

    /// Chat service aggregator URL from region_gtms, falling back to default.
    pub fn chatsvcagg_url(&self) -> String {
        self.config
            .get_region_gtms()
            .and_then(|v| {
                v.get("chatServiceAggregator")
                    .and_then(|s| s.as_str())
                    .map(String::from)
            })
            .unwrap_or_else(|| CHATSVCAGG.to_string())
    }

    /// GET using `Authorization: Bearer {skype_token}` with client version header (CSA/AFD endpoint).
    pub async fn csa_get(&self, url: &str) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("CSA GET {}", url);

        let resp = self
            .http
            .get(url)
            .bearer_auth(&token)
            .header("x-ms-client-version", "1416/1.0.0.2024050301")
            .send()
            .await
            .with_context(|| format!("CSA GET {} failed", url))?;

        check_response(resp, url).await
    }

    /// POST to CSA (the chat service aggregator) with the same auth as
    /// `csa_get`; the reply is returned whatever its status.
    pub async fn csa_post(
        &self,
        url: &str,
        body: &serde_json::Value,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("CSA POST {}", url);
        let mut req = self
            .http
            .post(url)
            .bearer_auth(&token)
            .header("x-ms-client-version", "1416/1.0.0.2024050301")
            .json(body);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        req.send()
            .await
            .with_context(|| format!("CSA POST {} failed", url))
    }

    /// GET using `Authentication: skypetoken=...` header (native chat API).
    pub async fn chat_get(&self, url: &str) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat GET {}", url);

        let resp = self
            .http
            .get(url)
            .header("Authentication", format!("skypetoken={}", token))
            .send()
            .await
            .with_context(|| format!("Chat GET {} failed", url))?;

        check_response(resp, url).await
    }

    /// POST using `Authentication: skypetoken=...` header (native chat API).
    pub async fn chat_post(
        &self,
        url: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat POST {}", url);

        let resp = self
            .http
            .post(url)
            .header("Authentication", format!("skypetoken={}", token))
            .json(body)
            .send()
            .await
            .with_context(|| format!("Chat POST {} failed", url))?;

        check_response(resp, url).await
    }

    /// POST a JSON body given as text (its keys in the order the client
    /// sends them) to the chat service.
    pub async fn chat_post_text(&self, url: &str, body: &str) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat POST {}", url);
        let resp = self
            .http
            .post(url)
            .header("Authentication", format!("skypetoken={}", token))
            .header("Content-Type", "application/json")
            .body(body.to_string())
            .send()
            .await
            .with_context(|| format!("Chat POST {} failed", url))?;
        check_response(resp, url).await
    }

    /// POST to the chat service and hand back the reply whatever its status
    /// (the send pipeline classifies failures itself). Err only when no reply
    /// came at all.
    pub async fn chat_post_unchecked(
        &self,
        url: &str,
        body: &serde_json::Value,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat POST {}", url);
        let mut req = self
            .http
            .post(url)
            .header("Authentication", format!("skypetoken={}", token))
            .json(body);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        req.send()
            .await
            .with_context(|| format!("Chat POST {} failed", url))
    }

    /// GET from Teams' media store (AMS), which wants `skype_token`.
    pub async fn ams_get(&self, url: &str) -> Result<Vec<u8>> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        let resp = self
            .http
            .get(url)
            .header("Authorization", format!("skype_token {}", token))
            .send()
            .await
            .context("Media GET failed")?;
        let resp = check_response(resp, url).await?;
        Ok(resp.bytes().await.context("Media body")?.to_vec())
    }

    /// Upload a picture to AMS for the members of `conv`, as Teams does for
    /// inline pictures: `POST {ams}/v1/objects/` with type `pish/image` and
    /// read permission for the conversation, then `PUT …/content/imgpsh`
    /// with the bytes. Returns the object id.
    pub async fn ams_upload_image(
        &self,
        conv: &str,
        bytes: Vec<u8>,
        filename: &str,
    ) -> Result<String> {
        self.ams_upload_image_for(conv, bytes, filename).await
    }

    /// As ams_upload_image, readable by `conv`: a conversation id, or
    /// `*:tid:{tenant}` for the whole organisation (custom emoji).
    pub async fn ams_upload_image_for(
        &self,
        conv: &str,
        bytes: Vec<u8>,
        filename: &str,
    ) -> Result<String> {
        let token = self.skype_token()?;
        let base = self
            .ams_url()
            .context("No media store address for this account")?;
        token_hosts::ensure(&base, Audience::Teams)?;
        let auth = format!("skype_token {}", token);
        // AMS reads the caller's platform from the User-Agent's
        // `Teams/{version}/{platform}` part (Teams desktop sends …/49) and
        // refuses a request without it; OST is platform 1415 elsewhere.
        const UA: &str = TEAMS_WEB_UA;
        let created = self
            .http
            .post(format!("{base}/v1/objects/"))
            .header("Authorization", &auth)
            .header(reqwest::header::USER_AGENT, UA)
            .json(&serde_json::json!({
                "type": "pish/image",
                "permissions": { conv: ["read"] },
                "filename": filename,
            }))
            .send()
            .await
            .context("Media create failed")?;
        let created = check_response(created, &base).await?;
        let v: serde_json::Value = created.json().await.context("Media create reply")?;
        let id = v
            .get("id")
            .and_then(|i| i.as_str())
            .context("No media object id")?
            .to_string();
        anyhow::ensure!(
            id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'),
            "Unexpected media object id"
        );
        let put = self
            .http
            .put(format!("{base}/v1/objects/{id}/content/imgpsh"))
            .header("Authorization", &auth)
            .header(reqwest::header::USER_AGENT, UA)
            .header("Content-Type", "application/octet-stream")
            .body(bytes)
            .send()
            .await
            .context("Media upload failed")?;
        check_response(put, &base).await?;
        Ok(id)
    }

    /// Store a recorded video clip in AMS for the members of `conv`, as
    /// Teams does after its recorder (captured on winpc, 2026-11-14):
    /// `POST {ams}/v1/objects/` with type `sharing/videototranscode`, then
    /// `PUT …/content/thumbnail` (the poster), `…/content/original` (the
    /// recording) and `…/content/transcript_info`. AMS then transcodes it
    /// (`…/views/video`). Returns the object id.
    pub async fn ams_upload_video(
        &self,
        conv: &str,
        original: Vec<u8>,
        thumbnail: Vec<u8>,
    ) -> Result<String> {
        let token = self.skype_token()?;
        let base = self
            .ams_url()
            .context("No media store address for this account")?;
        token_hosts::ensure(&base, Audience::Teams)?;
        let auth = format!("skype_token {}", token);
        const UA: &str = TEAMS_WEB_UA;
        let created = self
            .http
            .post(format!("{base}/v1/objects/"))
            .header("Authorization", &auth)
            .header(reqwest::header::USER_AGENT, UA)
            .json(&serde_json::json!({
                "type": "sharing/videototranscode",
                "permissions": { conv: ["read"] },
                "sharingMode": "Unknown",
            }))
            .send()
            .await
            .context("Media create failed")?;
        let created = check_response(created, &base).await?;
        let v: serde_json::Value = created.json().await.context("Media create reply")?;
        let id = v
            .get("id")
            .and_then(|i| i.as_str())
            .context("No media object id")?
            .to_string();
        anyhow::ensure!(
            id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'),
            "Unexpected media object id"
        );
        for (content, bytes) in [
            ("thumbnail", thumbnail),
            ("original", original),
            ("transcript_info", b"transcript_info".to_vec()),
        ] {
            let put = self
                .http
                .put(format!("{base}/v1/objects/{id}/content/{content}"))
                .header("Authorization", &auth)
                .header(reqwest::header::USER_AGENT, UA)
                .header("Content-Type", "application/octet-stream")
                .body(bytes)
                .send()
                .await
                .context("Media upload failed")?;
            check_response(put, &base).await?;
        }
        Ok(id)
    }

    /// `chat_request` with extra headers.
    pub async fn chat_request_with(
        &self,
        method: reqwest::Method,
        url: &str,
        body: &serde_json::Value,
        headers: &[(&str, &str)],
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat {} {}", method, url);
        let req = self
            .http
            .request(method.clone(), url)
            .header("Authentication", format!("skypetoken={}", token));
        let resp = headers
            .iter()
            .fold(req, |r, (k, v)| r.header(*k, *v))
            .json(body)
            .send()
            .await
            .with_context(|| format!("Chat {} {} failed", method, url))?;
        check_response(resp, url).await
    }

    /// Any method with `Authentication: skypetoken=...` (native chat API).
    pub async fn chat_request(
        &self,
        method: reqwest::Method,
        url: &str,
        body: &serde_json::Value,
    ) -> Result<reqwest::Response> {
        let token = self.skype_token()?;
        token_hosts::ensure(url, Audience::Teams)?;
        tracing::debug!("Chat {} {}", method, url);
        let resp = self
            .http
            .request(method.clone(), url)
            .header("Authentication", format!("skypetoken={}", token))
            .json(body)
            .send()
            .await
            .with_context(|| format!("Chat {} {} failed", method, url))?;
        check_response(resp, url).await
    }
}

/// Check HTTP response status code and return a clear error on failure.
async fn check_response(resp: reqwest::Response, url: &str) -> Result<reqwest::Response> {
    let status = resp.status();
    if status == reqwest::StatusCode::UNAUTHORIZED {
        bail!(
            "401 Unauthorized for {}. Token may be invalid -- run 'teams-cli login'.",
            url
        );
    }
    if !status.is_success() {
        let retry_after = retry_after(resp.headers());
        let body = resp.text().await.unwrap_or_default();
        return Err(HttpError {
            status: status.as_u16(),
            url: url.to_string(),
            body,
            retry_after,
        }
        .into());
    }
    Ok(resp)
}

/// A service's error answer, worded "HTTP {status} for {url}: {body}",
/// with the wait it asked for (`Retry-After`) when it throttled the
/// request.
#[derive(Debug)]
pub struct HttpError {
    pub status: u16,
    pub url: String,
    pub body: String,
    pub retry_after: Option<std::time::Duration>,
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "HTTP {} for {}: {}", self.status, self.url, self.body)
    }
}

impl std::error::Error for HttpError {}

/// A `Retry-After` in seconds, as the Teams services send it. Zero (the
/// chat service's throttle sends `Retry-After: 0`) says nothing, as for
/// Teams' retry policy, which waits only for a positive one.
fn retry_after(headers: &reqwest::header::HeaderMap) -> Option<std::time::Duration> {
    let secs: f64 = headers
        .get(reqwest::header::RETRY_AFTER)?
        .to_str()
        .ok()?
        .trim()
        .parse()
        .ok()?;
    (secs.is_finite() && secs > 0.0).then(|| std::time::Duration::from_secs_f64(secs))
}

/// The longest `Retry-After` waited for before asking again; a longer one
/// fails the request.
const MAX_RETRY_AFTER: std::time::Duration = std::time::Duration::from_secs(30);

/// How long to wait before asking again after the error `e`: for a
/// throttled request (HTTP 429), the `Retry-After` it gave, else
/// `fallback`. `None` for any other error, or for a wait longer than
/// [`MAX_RETRY_AFTER`].
pub fn throttle_wait(
    e: &anyhow::Error,
    fallback: std::time::Duration,
) -> Option<std::time::Duration> {
    match e.chain().find_map(|c| c.downcast_ref::<HttpError>()) {
        Some(h) if h.status == 429 => Some(h.retry_after.unwrap_or(fallback)),
        Some(_) => None,
        // An error that only quotes one in its text.
        None => format!("{e:#}").contains("HTTP 429").then_some(fallback),
    }
    .filter(|w| *w <= MAX_RETRY_AFTER)
}

/// Teams' HTTP layer waits and asks again when a service throttles a
/// request (HTTP 429): as long as its `Retry-After` says (Teams'
/// HttpThrottleHandler), or 2, 4 and 8 s apart when it says nothing; up
/// to three more times.
pub async fn retry_throttled<T, F, Fut>(mut f: F) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let mut fallback = std::time::Duration::from_secs(2);
    for _ in 0..3 {
        match f().await {
            Err(e) => match throttle_wait(&e, fallback) {
                Some(wait) => {
                    tracing::info!(
                        wait_ms = wait.as_millis() as u64,
                        "throttled (429): asking again"
                    );
                    tokio::time::sleep(wait).await;
                    fallback *= 2;
                }
                None => return Err(e),
            },
            r => return r,
        }
    }
    f().await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn throttled(retry_after: Option<Duration>) -> anyhow::Error {
        anyhow::Error::new(HttpError {
            status: 429,
            url: "https://chat/v1/threads/19:x@thread.v2".into(),
            body: "API calls quota exceeded! 20Per10Secs".into(),
            retry_after,
        })
        .context("Group members unavailable")
    }

    #[test]
    fn throttled_requests_wait_as_the_service_says() {
        let fallback = Duration::from_secs(2);
        let e = throttled(Some(Duration::from_secs(7)));
        assert_eq!(throttle_wait(&e, fallback), Some(Duration::from_secs(7)));
        // The error reads as it always has.
        assert!(format!("{e:#}").contains("HTTP 429 for https://chat/"));
        assert_eq!(throttle_wait(&throttled(None), fallback), Some(fallback));
        // Longer than Teams would wait: fails now.
        assert_eq!(
            throttle_wait(&throttled(Some(Duration::from_secs(600))), fallback),
            None
        );
        let other = anyhow::Error::new(HttpError {
            status: 404,
            url: String::new(),
            body: String::new(),
            retry_after: None,
        });
        assert_eq!(throttle_wait(&other, fallback), None);
        assert_eq!(
            throttle_wait(&anyhow::anyhow!("HTTP 429 for x: busy"), fallback),
            Some(fallback)
        );
    }

    #[test]
    fn retry_after_is_read_in_seconds() {
        let mut h = reqwest::header::HeaderMap::new();
        assert_eq!(retry_after(&h), None);
        h.insert(reqwest::header::RETRY_AFTER, "3".parse().unwrap());
        assert_eq!(retry_after(&h), Some(Duration::from_secs(3)));
        h.insert(reqwest::header::RETRY_AFTER, "0.5".parse().unwrap());
        assert_eq!(retry_after(&h), Some(Duration::from_millis(500)));
        h.insert(reqwest::header::RETRY_AFTER, "soon".parse().unwrap());
        assert_eq!(retry_after(&h), None);
        // The chat service's throttle: no wait given.
        h.insert(reqwest::header::RETRY_AFTER, "0".parse().unwrap());
        assert_eq!(retry_after(&h), None);
    }

    #[tokio::test]
    async fn throttled_reads_are_asked_again() {
        let tries = std::cell::Cell::new(0);
        let r = retry_throttled(|| {
            tries.set(tries.get() + 1);
            let n = tries.get();
            async move {
                if n < 3 {
                    Err(throttled(Some(Duration::ZERO)))
                } else {
                    Ok(n)
                }
            }
        })
        .await;
        assert_eq!(r.unwrap(), 3);
        // Other errors aren't.
        tries.set(0);
        let r: Result<()> = retry_throttled(|| {
            tries.set(tries.get() + 1);
            async { Err(anyhow::anyhow!("HTTP 403 for x: no")) }
        })
        .await;
        assert!(r.is_err());
        assert_eq!(tries.get(), 1);
    }
}
