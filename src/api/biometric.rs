//! Teams' Recognition: your voice and face profiles in Teams' biometric
//! service (Settings ▸ Recognition, Teams' biometric-enrollment app).
//!
//! - The service is the region GTM `biometricService`
//!   (`https://teams.microsoft.com/api/biometric/<region>/`), called with
//!   an AAD token for its resource and Teams' `x-ringoverride` (the client
//!   ring, ECS `metadata.ring.id`).
//! - Status: `GET v2/voice/enroll/status?enrollmentFilter=Enrolled&
//!   checkVoiceRecording=true` and `GET v2/face/enroll/status?
//!   checkFaceCapture=true` (the "enrollments" lists).
//! - Removal: `DELETE unenroll` (voice), `DELETE me/face/unenroll` (face).
//! - Capture: a short-lived "cognition" token (`GET beta/cognition/token?
//!   type=face|voice` → endPointUrl, azureToken, identifier) opens
//!   Microsoft's signature service, which turns a photo (BSON, per head
//!   pose) or a recording (Azure Speech WebSocket, 16 kHz mono PCM) into
//!   a signature. Teams then stores it: `POST beta/me/face/enroll/mandatory/
//!   signatures` (BSON: the photos and their signatures) or `POST
//!   v2/voice/enroll` (JSON: the recording and its signature). Consent
//!   rides along as ConsentTextVersion "V1": pressing Start is consenting,
//!   as Teams' text says.
//!
//! No face or voice processing happens here: the signatures are made by
//! the service from what is sent.

use anyhow::{Context, Result, bail};
use base64::Engine;

use super::client::TeamsClient;

/// The biometric service's AAD resource (Teams' voice/faceEnrollment-
/// ServiceResource).
pub const RESOURCE: &str = "00edd498-7c0c-4e68-859c-5a55d518c9c0";

/// What Teams' text asks you to read for your voice profile (en-us;
/// biometricEnrollment.voice_enrollment_capture_text).
pub const VOICE_TEXT: &str = "Hi, Teams. I\u{2019}m going to speak for a moment to help you get to know my voice better. You need to hear more than just a few words to be able to accurately recognize me in meetings. If I make a mistake, that\u{2019}s all right you\u{2019}ll let me know if I need to read this again.";

/// The service, with a token for it.
pub struct Biometric {
    base: String,
    token: String,
    http: reqwest::Client,
}

/// Whether you have each profile (and a capture waiting to become one).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Status {
    pub voice: bool,
    pub voice_recording: bool,
    pub face: bool,
    pub face_capture: bool,
}

/// The short-lived token for Microsoft's signature service.
#[derive(Debug, Clone, serde::Deserialize)]
pub struct CognitionToken {
    #[serde(rename = "endPointUrl")]
    pub endpoint: String,
    #[serde(rename = "azureToken")]
    pub azure_token: String,
    pub identifier: String,
}

/// A head pose Teams asks for (center first).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeadPose {
    Center,
    Left,
    Right,
}

impl HeadPose {
    fn wire(self) -> &'static str {
        match self {
            HeadPose::Center => "Center",
            HeadPose::Left => "Left",
            HeadPose::Right => "Right",
        }
    }
}

/// A photo's outcome: its signature, or Teams' reason it was refused
/// (MultipleFaces, NoFaces, FaceTooSmall, UnexpectedHeadPose, BadLighting,
/// DetectorFailed, HeadPoseFailed, UnspecifiedFailure).
#[derive(Debug, Clone, PartialEq)]
pub enum FaceOutcome {
    Signed(serde_json::Value),
    Refused(String),
}

/// The client ring Teams names in `x-ringoverride`.
fn ring() -> String {
    super::ecs::setting("metadata", "ring")
        .and_then(|r| r.get("id").and_then(|i| i.as_str()).map(str::to_string))
        .unwrap_or_else(|| "general".into())
}

/// Teams' `AppEnrolledFrom` ("<client type>,<version>"), for OST.
pub fn app_enrolled_from() -> String {
    format!("ost-desktop,{}", env!("CARGO_PKG_VERSION"))
}

impl Biometric {
    pub async fn new(client: &TeamsClient) -> Result<Self> {
        let base = client
            .region_endpoint("biometricService")
            .context("no biometric service for this account")?;
        let token = crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
        Ok(Self { base: format!("{base}/"), token, http: client.http().clone() })
    }

    fn request(&self, method: reqwest::Method, path: &str) -> reqwest::RequestBuilder {
        self.http
            .request(method, format!("{}{}", self.base, path.trim_start_matches('/')))
            .bearer_auth(&self.token)
            .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
            .header("x-ringoverride", ring())
            .header("x-ms-client-version", app_enrolled_from())
    }

    async fn get_json(&self, path: &str) -> Result<serde_json::Value> {
        let r = self.request(reqwest::Method::GET, path).header("Accept", "application/json").send().await?;
        let status = r.status();
        let text = r.text().await.unwrap_or_default();
        if !status.is_success() {
            bail!("HTTP {status} for {path}: {}", text.chars().take(300).collect::<String>());
        }
        Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
    }

    /// Whether you have a voice and a face profile.
    pub async fn status(&self) -> Result<Status> {
        let voice = self.get_json("v2/voice/enroll/status?enrollmentFilter=Enrolled&checkVoiceRecording=true").await?;
        let face = self.get_json("v2/face/enroll/status?checkFaceCapture=true").await?;
        Ok(status_from(&voice, &face))
    }

    /// Remove your voice profile.
    pub async fn remove_voice(&self) -> Result<()> {
        let r = self.request(reqwest::Method::DELETE, "unenroll").send().await?;
        if !r.status().is_success() {
            bail!("removing the voice profile: HTTP {}", r.status());
        }
        Ok(())
    }

    /// Remove your face profile.
    pub async fn remove_face(&self) -> Result<()> {
        let r = self.request(reqwest::Method::DELETE, "me/face/unenroll").send().await?;
        if !r.status().is_success() {
            bail!("removing the face profile: HTTP {}", r.status());
        }
        Ok(())
    }

    /// A token for the signature service, for "face" or "voice".
    pub async fn cognition_token(&self, kind: &str) -> Result<CognitionToken> {
        let v = self
            .get_json(&format!("beta/cognition/token?type={kind}"))
            .await?;
        let t: CognitionToken = serde_json::from_value(v["Data"].clone()).context("cognition token")?;
        if t.endpoint.is_empty() || t.azure_token.is_empty() || t.identifier.is_empty() {
            bail!("malformed cognition token");
        }
        Ok(t)
    }

    /// Store your face profile: each accepted photo with its signature.
    pub async fn store_face(&self, photos: &[(Vec<u8>, serde_json::Value)]) -> Result<()> {
        let body = face_store_body(photos, &app_enrolled_from())?;
        let r = self
            .request(reqwest::Method::POST, "beta/me/face/enroll/mandatory/signatures")
            .header("Content-Type", "application/bson")
            .body(body)
            .send()
            .await?;
        let status = r.status();
        if !(status == reqwest::StatusCode::OK || status == reqwest::StatusCode::CREATED) {
            bail!("storing the face profile: HTTP {status}: {}", r.text().await.unwrap_or_default().chars().take(300).collect::<String>());
        }
        Ok(())
    }

    /// Store your voice profile: the recording, its speaker signature and
    /// its voice-isolation signature.
    pub async fn store_voice(&self, locale: &str, wav: &[u8], signature: &serde_json::Value) -> Result<()> {
        let body = voice_store_body(locale, wav, signature, &app_enrolled_from());
        let r = self
            .request(reqwest::Method::POST, "v2/voice/enroll")
            .header("Content-Type", "application/json;charset=UTF-8")
            .json(&body)
            .send()
            .await?;
        let status = r.status();
        let text = r.text().await.unwrap_or_default();
        if status != reqwest::StatusCode::OK {
            tracing::warn!(%status, body = %text.chars().take(500).collect::<String>(), "storing the voice profile");
            let code = serde_json::from_str::<serde_json::Value>(&text)
                .ok()
                .and_then(|v| v["ErrorCode"].as_str().map(str::to_string))
                .unwrap_or_else(|| format!("HTTP {status}"));
            bail!("{code}");
        }
        Ok(())
    }
}

/// Your passive-enrollment consent (Teams keeps it in the middle tier's
/// biometric settings).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Passive {
    pub voice: bool,
    pub face: bool,
}

/// Read your passive-enrollment consent (`GET {mt}/beta/users/
/// getUserBiometricSettings/tenant/{tid}/user/{oid}`; 201/204: none).
pub async fn passive(client: &TeamsClient) -> Result<Passive> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let url = format!(
        "{base}/beta/users/getUserBiometricSettings/tenant/{}/user/{}",
        client.tenant_id().unwrap_or_default(),
        client.object_id().unwrap_or_default()
    );
    let r = client.http().get(&url).bearer_auth(&token).send().await?;
    if r.status() == reqwest::StatusCode::CREATED || r.status() == reqwest::StatusCode::NO_CONTENT {
        return Ok(Passive::default());
    }
    let v: serde_json::Value = r.error_for_status()?.json().await.unwrap_or_default();
    Ok(Passive {
        voice: v["isPassiveVoiceEnrollmentConsented"].as_bool().unwrap_or(false),
        face: v["isPassiveFaceEnrollmentConsented"].as_bool().unwrap_or(false),
    })
}

async fn upsert_passive(client: &TeamsClient, body: serde_json::Value) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let url = format!(
        "{base}/beta/users/upsertUserBiometricSettings/tenant/{}/user/{}",
        client.tenant_id().unwrap_or_default(),
        client.object_id().unwrap_or_default()
    );
    client.http().put(&url).bearer_auth(&token).json(&body).send().await?.error_for_status()?;
    Ok(())
}

impl Biometric {
    /// Teams' voice "Start voice capture" on Settings ▸ Recognition: opt in
    /// to keeping your voice profile up to date from your calls (consent
    /// to the service, then the setting); Opt out turns it off and removes
    /// the profile.
    pub async fn set_passive_voice(&self, client: &TeamsClient, on: bool) -> Result<()> {
        if on {
            let r = self
                .request(reqwest::Method::PUT, "v3/passive/consent/enroll")
                .json(&serde_json::json!({ "ConsentTextVersion": "1", "AppEnrolledFrom": "Desktop" }))
                .send()
                .await?;
            if !r.status().is_success() {
                bail!("consent: HTTP {}", r.status());
            }
            upsert_passive(client, serde_json::json!({ "isPassiveVoiceEnrollmentConsented": true, "passiveEnrollmentConsentTextVersion": 1 })).await
        } else {
            upsert_passive(client, serde_json::json!({ "isPassiveVoiceEnrollmentConsented": false, "passiveEnrollmentConsentTextVersion": 1 })).await?;
            self.remove_voice().await
        }
    }

    /// Teams' Export: your voice or face data as a zip.
    pub async fn export(&self, kind: &str) -> Result<Vec<u8>> {
        let r = self
            .request(reqwest::Method::GET, &format!("data/v3/export/{kind}"))
            .header("Accept", "application/zip")
            .send()
            .await?;
        if !r.status().is_success() {
            bail!("export: HTTP {}", r.status());
        }
        Ok(r.bytes().await?.to_vec())
    }
}

/// Have-profile flags from Teams' two status replies.
pub fn status_from(voice: &serde_json::Value, face: &serde_json::Value) -> Status {
    let some = |v: &serde_json::Value| v["enrollments"].as_array().is_some_and(|a| !a.is_empty());
    Status {
        voice: some(voice),
        voice_recording: voice["hasVoiceRecording"].as_bool().unwrap_or(false),
        face: some(face),
        face_capture: face["hasFaceCapture"].as_bool().unwrap_or(false),
    }
}

/// A BSON value (the little of BSON Teams' biometric service needs:
/// documents, arrays, strings, binary, numbers, booleans and null).
#[derive(Debug, Clone, PartialEq)]
pub enum Bson {
    Doc(Vec<(String, Bson)>),
    Array(Vec<Bson>),
    Str(String),
    Binary(Vec<u8>),
    Int(i64),
    Double(f64),
    Bool(bool),
    Null,
}

impl Bson {
    /// The same value from JSON.
    pub fn from_json(v: &serde_json::Value) -> Bson {
        match v {
            serde_json::Value::Null => Bson::Null,
            serde_json::Value::Bool(b) => Bson::Bool(*b),
            serde_json::Value::Number(n) => n.as_i64().map(Bson::Int).unwrap_or_else(|| Bson::Double(n.as_f64().unwrap_or(0.0))),
            serde_json::Value::String(s) => Bson::Str(s.clone()),
            serde_json::Value::Array(a) => Bson::Array(a.iter().map(Bson::from_json).collect()),
            serde_json::Value::Object(o) => Bson::Doc(o.iter().map(|(k, v)| (k.clone(), Bson::from_json(v))).collect()),
        }
    }

    /// This document's bytes (a document's own; any other value is
    /// wrapped as nothing).
    pub fn to_bytes(&self) -> Vec<u8> {
        match self {
            Bson::Doc(fields) => doc_bytes(&fields.iter().map(|(k, v)| (k.as_str(), v)).collect::<Vec<_>>()),
            _ => doc_bytes(&[]),
        }
    }
}

fn doc_bytes(fields: &[(&str, &Bson)]) -> Vec<u8> {
    let mut body = Vec::new();
    for &(name, value) in fields {
        let (kind, bytes) = match value {
            Bson::Doc(f) => (0x03u8, doc_bytes(&f.iter().map(|(k, v)| (k.as_str(), v)).collect::<Vec<_>>())),
            Bson::Array(items) => {
                let keys: Vec<String> = (0..items.len()).map(|i| i.to_string()).collect();
                (0x04, doc_bytes(&keys.iter().map(String::as_str).zip(items.iter()).collect::<Vec<_>>()))
            }
            Bson::Str(s) => {
                let mut b = ((s.len() + 1) as i32).to_le_bytes().to_vec();
                b.extend_from_slice(s.as_bytes());
                b.push(0);
                (0x02, b)
            }
            Bson::Binary(data) => {
                let mut b = (data.len() as i32).to_le_bytes().to_vec();
                b.push(0x00); // generic subtype
                b.extend_from_slice(data);
                (0x05, b)
            }
            Bson::Int(n) if i32::try_from(*n).is_ok() => (0x10, (*n as i32).to_le_bytes().to_vec()),
            Bson::Int(n) => (0x12, n.to_le_bytes().to_vec()),
            Bson::Double(f) => (0x01, f.to_le_bytes().to_vec()),
            Bson::Bool(b) => (0x08, vec![u8::from(*b)]),
            Bson::Null => (0x0A, Vec::new()),
        };
        body.push(kind);
        body.extend_from_slice(name.as_bytes());
        body.push(0);
        body.extend_from_slice(&bytes);
    }
    let mut out = ((body.len() + 5) as i32).to_le_bytes().to_vec();
    out.extend_from_slice(&body);
    out.push(0);
    out
}

/// The BSON Teams sends the signature service for one photo.
pub fn face_signature_body(jpeg: &[u8], pose: HeadPose, user_oid: &str, tenant: &str, version: Option<&str>) -> Result<Vec<u8>> {
    let image = Bson::Doc(vec![
        ("Payload".into(), Bson::Binary(jpeg.to_vec())),
        ("ExpectedHeadPose".into(), Bson::Str(pose.wire().into())),
    ]);
    let request = Bson::Doc(vec![
        ("UserId".into(), Bson::Str(user_oid.into())),
        ("TenantID".into(), Bson::Str(tenant.into())),
        ("Images".into(), Bson::Array(vec![image])),
    ]);
    let mut doc = Vec::new();
    if let Some(v) = version {
        doc.push(("Version".to_string(), Bson::Str(v.into())));
    }
    doc.push(("PerUserFaceSignatureBatchRequest".to_string(), Bson::Array(vec![request])));
    Ok(Bson::Doc(doc).to_bytes())
}

/// The signature service's answer for one photo.
pub fn face_outcome(reply: &serde_json::Value) -> FaceOutcome {
    let r = &reply["PerUserFaceSignatureBatchResponse"][0]["Responses"][0];
    let signature = &r["Signature"];
    if r["Result"].as_str() == Some("Fail") || signature.is_null() {
        let reason = if r["Error"].as_str() == Some("WrongHeadPose") {
            "UnexpectedHeadPose".to_string()
        } else {
            match r["ErrorDetails"].as_str().unwrap_or_default() {
                d @ ("MultipleFaces" | "NoFaces" | "FaceTooSmall" | "UnexpectedHeadPose" | "BadLighting"
                | "DetectorFailed" | "HeadPoseFailed") => d.to_string(),
                _ => "UnspecifiedFailure".to_string(),
            }
        };
        return FaceOutcome::Refused(reason);
    }
    FaceOutcome::Signed(signature.clone())
}

/// Ask the signature service for one photo's signature.
pub async fn face_signature(
    http: &reqwest::Client,
    token: &CognitionToken,
    jpeg: &[u8],
    pose: HeadPose,
    user_oid: &str,
    version: Option<&str>,
) -> Result<FaceOutcome> {
    let body = face_signature_body(jpeg, pose, user_oid, &token.identifier, version)?;
    let r = http
        .post(format!("https://{}", token.endpoint))
        .bearer_auth(&token.azure_token)
        .header("Content-Type", "application/bson")
        .body(body)
        .send()
        .await?;
    let status = r.status();
    let text = r.text().await.unwrap_or_default();
    if !(status.is_success() || status == reqwest::StatusCode::BAD_REQUEST) {
        bail!("face signature: HTTP {status}: {}", text.chars().take(300).collect::<String>());
    }
    let reply: serde_json::Value = serde_json::from_str(&text).context("face signature reply")?;
    Ok(face_outcome(&reply))
}

/// The BSON storing a face profile.
pub fn face_store_body(photos: &[(Vec<u8>, serde_json::Value)], app: &str) -> Result<Vec<u8>> {
    let data: Vec<Bson> = photos
        .iter()
        .map(|(jpeg, sig)| {
            let field = |k: &str| Bson::from_json(&sig[k]);
            Bson::Doc(vec![
                ("Image".into(), Bson::Binary(jpeg.clone())),
                (
                    "Signature".into(),
                    Bson::Doc(vec![
                        ("Type".into(), field("Type")),
                        ("Version".into(), field("Version")),
                        ("Data".into(), field("Data")),
                        ("HeadPose".into(), field("HeadPose")),
                    ]),
                ),
            ])
        })
        .collect();
    Ok(Bson::Doc(vec![
        (
            "EnrollmentMetadata".into(),
            Bson::Doc(vec![
                ("ConsentTextVersion".into(), Bson::Str("V1".into())),
                ("AppEnrolledFrom".into(), Bson::Str(app.into())),
            ]),
        ),
        ("Data".into(), Bson::Array(data)),
    ])
    .to_bytes())
}

/// The JSON storing a voice profile.
pub fn voice_store_body(locale: &str, wav: &[u8], signature: &serde_json::Value, app: &str) -> serde_json::Value {
    serde_json::json!({
        "Locale": locale,
        "RawData": base64::engine::general_purpose::STANDARD.encode(wav),
        "Metadata": { "ConsentTextVersion": "V1", "AppEnrolledFrom": app },
        "RockfallSignature": { "Version": signature["Version"], "Data": signature["Data"] },
        // Teams sends the voice-isolation (PNS) signature when its media
        // stack's model version is the signature's own (v4_5, Teams'
        // supportedVoiceSignatureModelVersions); the service requires one.
        "VoiceIsolationSignature": { "Version": signature["Version"], "Data": signature["PNSData"] },
    })
}

/// A 16 kHz, 16-bit mono WAV of `pcm` (Teams' header).
pub fn wav_16k(pcm: &[i16]) -> Vec<u8> {
    let n = (pcm.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + n as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + n).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&16000u32.to_le_bytes());
    out.extend_from_slice(&32000u32.to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&n.to_le_bytes());
    for s in pcm {
        out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

/// A voice capture's outcome: the signature, or Teams' reason
/// (NotEnoughWords, NoWords, HighErrorRate, BadAudioQuality, …).
#[derive(Debug, Clone, PartialEq)]
pub enum VoiceOutcome {
    Signed(serde_json::Value),
    Refused(String),
}

/// Teams' reading of the signature service's `speech.event`: NotEnoughWords
/// turns into HighErrorRate above the error threshold (ECS
/// enrollmentErrorThresholdInPercentage, 25) and into NoWords below 0.
pub fn voice_outcome(event: &serde_json::Value, threshold: f64) -> VoiceOutcome {
    if event["Result"].as_str() == Some("Success") && !event["Signature"].is_null() {
        return VoiceOutcome::Signed(event["Signature"].clone());
    }
    let error = event["Error"].as_str().unwrap_or("UnspecifiedFailure").to_string();
    if error == "NotEnoughWords" {
        let details = event["ErrorDetails"].as_str().unwrap_or_default();
        let rate = details
            .split(|c: char| !(c.is_ascii_digit() || c == '.' || c == '-'))
            .find_map(|t| t.parse::<f64>().ok());
        return VoiceOutcome::Refused(match rate {
            Some(r) if r > threshold => "HighErrorRate".into(),
            Some(r) if r < 0.0 => "NoWords".into(),
            _ => "NotEnoughWords".into(),
        });
    }
    VoiceOutcome::Refused(error)
}

/// One Azure Speech WebSocket message: a text frame of header lines and a
/// body, or a binary frame of a 2-byte big-endian header length, the
/// headers and the payload.
fn speech_headers(path: &str, request_id: &str, content_type: Option<&str>) -> String {
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ");
    let mut h = format!("Path: {path}\r\nX-RequestId: {request_id}\r\nX-Timestamp: {now}\r\n");
    if let Some(ct) = content_type {
        h.push_str(&format!("Content-Type: {ct}\r\n"));
    }
    h
}

fn speech_binary(path: &str, request_id: &str, content_type: Option<&str>, payload: &[u8]) -> Vec<u8> {
    let headers = speech_headers(path, request_id, content_type);
    let mut out = Vec::with_capacity(2 + headers.len() + payload.len());
    out.extend_from_slice(&(headers.len() as u16).to_be_bytes());
    out.extend_from_slice(headers.as_bytes());
    out.extend_from_slice(payload);
    out
}

/// The voice signature for a recording (16 kHz mono WAV), as Teams gets it:
/// Azure Speech's WebSocket at the token's endpoint, with Teams' text as a
/// phrase hint; the signature comes back in a `speech.event` message.
pub async fn voice_signature(token: &CognitionToken, locale: &str, wav: &[u8], text: &str, threshold: f64) -> Result<VoiceOutcome> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;
    let connection = uuid::Uuid::new_v4().simple().to_string().to_uppercase();
    let url = format!(
        "wss://{}?&language={}&customid={}&Authorization={}&X-ConnectionId={connection}",
        token.endpoint,
        urlencode(locale),
        urlencode(&token.identifier),
        urlencode(&format!("Bearer {}", token.azure_token)),
    );
    let (mut ws, _) = tokio_tungstenite::connect_async(url.as_str()).await.context("CTSConnectionError")?;
    let request = uuid::Uuid::new_v4().simple().to_string().to_uppercase();
    let config = serde_json::json!({
        "context": {
            "system": { "name": "SpeechSDK", "version": "1.32.0", "build": "JavaScript", "lang": "JavaScript" },
            "os": { "platform": "Linux", "name": "OST", "version": env!("CARGO_PKG_VERSION") },
            "audio": { "source": { "bitspersample": 16, "channelcount": 1, "connectivity": "Unknown", "manufacturer": "Speech SDK", "model": "Microphone", "samplerate": 16000, "type": "Microphones" } },
        },
        "recognition": "conversation",
    });
    let text_msg = |path: &str, rid: &str, ct: &str, body: String| {
        Message::Text(format!("{}\r\n{body}", speech_headers(path, rid, Some(ct))).into())
    };
    ws.send(text_msg("speech.config", &request, "application/json", config.to_string())).await?;
    let phrases = serde_json::json!({ "dgi": { "Groups": [{ "Type": "Generic", "Items": [{ "Text": text }] }] } });
    ws.send(text_msg("speech.context", &request, "application/json", phrases.to_string())).await?;
    // The WAV header first (Content-Type audio/x-wav), then the samples in
    // 100 ms pieces, then an empty audio message: the end.
    let (header, samples) = wav.split_at(44.min(wav.len()));
    ws.send(Message::Binary(speech_binary("audio", &request, Some("audio/x-wav"), header).into())).await?;
    for piece in samples.chunks(3200) {
        ws.send(Message::Binary(speech_binary("audio", &request, None, piece).into())).await?;
    }
    ws.send(Message::Binary(speech_binary("audio", &request, None, &[]).into())).await?;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(60);
    loop {
        let next = tokio::time::timeout_at(deadline, ws.next()).await.context("signature service timed out")?;
        let Some(msg) = next else { bail!("CTSConnectionError") };
        let msg = msg?;
        let raw = match msg {
            Message::Text(t) => t.to_string(),
            Message::Binary(_) => continue,
            Message::Close(_) => bail!("CTSConnectionError"),
            _ => continue,
        };
        let (head, body) = raw.split_once("\r\n\r\n").unwrap_or((raw.as_str(), ""));
        let path = head
            .lines()
            .find_map(|l| l.strip_prefix("Path:").or_else(|| l.strip_prefix("path:")))
            .map(str::trim)
            .unwrap_or_default();
        tracing::debug!(path, "speech message");
        if path.eq_ignore_ascii_case("speech.event") {
            let event: serde_json::Value = serde_json::from_str(body).context("speech.event")?;
            let _ = ws.close(None).await;
            return Ok(voice_outcome(&event, threshold));
        }
    }
}

fn urlencode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_from_teams_replies() {
        let none = serde_json::json!({ "provisionalEnrollments": [], "enrollments": [], "hasVoiceRecording": false });
        let face = serde_json::json!({ "enrollments": [{ "version": "4" }], "hasFaceCapture": true });
        assert_eq!(
            status_from(&none, &face),
            Status { voice: false, voice_recording: false, face: true, face_capture: true }
        );
    }

    #[test]
    fn face_outcomes_as_teams_reads_them() {
        let ok = serde_json::json!({ "PerUserFaceSignatureBatchResponse": [{ "Responses": [{ "Result": "Success", "Signature": { "Version": "4", "Data": "x" } }] }] });
        assert!(matches!(face_outcome(&ok), FaceOutcome::Signed(_)));
        let pose = serde_json::json!({ "PerUserFaceSignatureBatchResponse": [{ "Responses": [{ "Result": "Fail", "Error": "WrongHeadPose" }] }] });
        assert_eq!(face_outcome(&pose), FaceOutcome::Refused("UnexpectedHeadPose".into()));
        let many = serde_json::json!({ "PerUserFaceSignatureBatchResponse": [{ "Responses": [{ "Result": "Fail", "Error": "Invalid", "ErrorDetails": "MultipleFaces" }] }] });
        assert_eq!(face_outcome(&many), FaceOutcome::Refused("MultipleFaces".into()));
        let odd = serde_json::json!({ "PerUserFaceSignatureBatchResponse": [{ "Responses": [{ "Result": "Fail", "ErrorDetails": "Huh" }] }] });
        assert_eq!(face_outcome(&odd), FaceOutcome::Refused("UnspecifiedFailure".into()));
    }

    #[test]
    fn voice_outcomes_as_teams_reads_them() {
        let few = |d: &str| serde_json::json!({ "Result": "Fail", "Error": "NotEnoughWords", "ErrorDetails": d });
        assert_eq!(voice_outcome(&few("error rate 40.5"), 25.0), VoiceOutcome::Refused("HighErrorRate".into()));
        assert_eq!(voice_outcome(&few("error rate -1"), 25.0), VoiceOutcome::Refused("NoWords".into()));
        assert_eq!(voice_outcome(&few("error rate 10"), 25.0), VoiceOutcome::Refused("NotEnoughWords".into()));
        let ok = serde_json::json!({ "Result": "Success", "Signature": { "Version": "v4_5", "Data": "d" } });
        assert!(matches!(voice_outcome(&ok, 25.0), VoiceOutcome::Signed(_)));
    }

    #[test]
    fn bodies_round_trip() {
        // BSON's own example: {"hello": "world"}.
        let hello = Bson::Doc(vec![("hello".into(), Bson::Str("world".into()))]).to_bytes();
        assert_eq!(hello, b"\x16\x00\x00\x00\x02hello\x00\x06\x00\x00\x00world\x00\x00");
        let body = face_signature_body(&[1, 2, 3], HeadPose::Center, "oid", "ident", None).unwrap();
        assert_eq!(i32::from_le_bytes(body[..4].try_into().unwrap()) as usize, body.len());
        assert!(body.windows(5).any(|w| w == b"ident"));
        assert!(!body.windows(7).any(|w| w == b"Version"));
        // Binary: length 3, generic subtype, the bytes.
        assert!(body.windows(8).any(|w| w == [0x03, 0, 0, 0, 0, 1, 2, 3]));
        let wav = wav_16k(&[0, 1, -1]);
        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(wav.len(), 44 + 6);
        let b = voice_store_body("en-us", &wav, &serde_json::json!({ "Version": "v4_5", "Data": "d" }), "ost-desktop,1");
        assert_eq!(b["RockfallSignature"]["Version"], "v4_5");
        let m = speech_binary("audio", "R", None, &[9]);
        assert_eq!(u16::from_be_bytes([m[0], m[1]]) as usize, m.len() - 3);
    }
}
