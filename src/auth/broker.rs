//! Teams' broker for embedded apps: nested app authentication (NAA), as
//! Teams' host answers TeamsJS `nestedAppAuth.execute`.
//!
//! Measured in Teams on the web (the same React client as Teams desktop)
//! hosting the channel Notes tab, 2026-11-16 (docs/spec/app-host.md):
//! - An app (or a frame nested in it) posts a `NestedAppAuthRequest`
//!   string: `{messageType, method: GetInitContext | GetToken |
//!   GetTokenPopup, requestId, sendTime, clientLibrary,
//!   clientLibraryVersion, tokenParams: {clientId, scope, correlationId,
//!   claims?, authority?, platformBrokerId?, forceRefresh?,
//!   authenticationScheme, extraParameters}}`.
//! - Teams answers a `NestedAppAuthResponse` string (Teams' module 711436):
//!   - GetInitContext: `initContext: {sdkName: "Teams Auth SDK",
//!     sdkVersion: "V1", accountContext?}`, the account context only for an
//!     origin Teams trusts (the app's valid domains, or one the app added
//!     with `manageNAATrustedOrigins`);
//!   - GetToken / GetTokenPopup: `token: {access_token, id_token,
//!     expires_in, scope (as asked), account}` and `account`, the account
//!     `{homeAccountId (the user's object id), environment, username, name,
//!     __typename: "NestedAppUser"}`; the token is minted for the app's
//!     client with the asking frame's host as its broker return address
//!     (`brk-multihub://<host>`, see [`super::spa::app_redirect_uri`]);
//!   - failures: `success: false, error: {status, isExpected, code,
//!     subError, description}`.
//!
//! Tokens are kept in memory only (per app client, origin, scope and
//! claims) until five minutes before they expire, as Teams' worker keeps
//! them, and never logged.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use base64::Engine as _;
use serde_json::{Value, json};

use crate::config::Config;

/// The authority host Teams names as the account's environment.
pub const ENVIRONMENT: &str = "login.microsoftonline.com";
/// Tokens are reused until this long before they expire.
const RENEW_BEFORE: Duration = Duration::from_secs(300);

/// The signed-in account, as Teams describes it to apps.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Account {
    /// The user's object id (Teams' homeAccountId for NAA).
    pub oid: String,
    pub tenant_id: String,
    pub username: String,
    pub name: String,
}

impl Account {
    fn json(&self) -> Value {
        json!({ "homeAccountId": self.oid, "environment": ENVIRONMENT, "username": self.username, "name": self.name, "__typename": "NestedAppUser" })
    }

    /// The account from an OpenID token's claims (oid, tid,
    /// preferred_username, name); the signature isn't checked, the token
    /// came straight from Azure AD.
    pub fn from_id_token(id_token: &str) -> Option<Self> {
        let payload = id_token.split('.').nth(1)?;
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(payload.trim_end_matches('='))
            .ok()?;
        let c: Value = serde_json::from_slice(&bytes).ok()?;
        let s = |k: &str| {
            c.get(k)
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string()
        };
        let a = Self {
            oid: s("oid"),
            tenant_id: s("tid"),
            username: s("preferred_username"),
            name: s("name"),
        };
        (!a.oid.is_empty()).then_some(a)
    }
}

/// What an app asked for.
#[derive(Debug, Clone, PartialEq)]
pub enum Request {
    InitContext {
        request_id: String,
    },
    Token {
        request_id: String,
        client_id: String,
        scope: String,
        claims: Option<String>,
        force_refresh: bool,
    },
    /// A token request without a client or scope.
    MissingParameters {
        request_id: String,
    },
    Invalid {
        request_id: String,
    },
}

impl Request {
    pub fn parse(request: &str) -> Self {
        let v: Value = serde_json::from_str(request).unwrap_or(Value::Null);
        let request_id = v
            .get("requestId")
            .and_then(Value::as_str)
            .unwrap_or("N/A")
            .to_string();
        if v.get("messageType").and_then(Value::as_str) != Some("NestedAppAuthRequest") {
            return Self::Invalid { request_id };
        }
        match v.get("method").and_then(Value::as_str) {
            Some("GetInitContext") => Self::InitContext { request_id },
            Some("GetToken" | "GetTokenPopup") => {
                let p = v.get("tokenParams").cloned().unwrap_or(Value::Null);
                let s = |k: &str| {
                    p.get(k)
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_string()
                };
                let (client_id, scope) = (s("clientId"), s("scope"));
                if client_id.is_empty() || scope.is_empty() {
                    return Self::MissingParameters { request_id };
                }
                let claims = Some(s("claims")).filter(|c| !c.is_empty());
                let force_refresh = p
                    .get("forceRefresh")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                Self::Token {
                    request_id,
                    client_id,
                    scope,
                    claims,
                    force_refresh,
                }
            }
            _ => Self::Invalid { request_id },
        }
    }
}

fn response(request_id: &str, body: Value) -> String {
    let mut v = json!({ "messageType": "NestedAppAuthResponse", "requestId": request_id });
    if let (Some(o), Value::Object(b)) = (v.as_object_mut(), body) {
        o.extend(b);
    }
    v.to_string()
}

/// GetInitContext's answer; the account context only for a trusted origin.
pub fn init_context(request_id: &str, account: Option<&Account>) -> String {
    let mut ctx = json!({ "sdkName": "Teams Auth SDK", "sdkVersion": "V1" });
    if let Some(a) = account {
        ctx["accountContext"] =
            json!({ "homeAccountId": a.oid, "tenantId": a.tenant_id, "environment": ENVIRONMENT });
    }
    response(request_id, json!({ "success": true, "initContext": ctx }))
}

/// A token answer (`scope` as the app asked it).
pub fn token(
    request_id: &str,
    scope: &str,
    access_token: &str,
    id_token: &str,
    expires_in: u64,
    account: &Account,
) -> String {
    let a = account.json();
    response(
        request_id,
        json!({ "success": true,
                "token": { "access_token": access_token, "id_token": id_token, "expires_in": expires_in, "scope": scope, "account": a },
                "account": a }),
    )
}

/// Teams' error statuses (TeamsJS / MSAL's NAA error statuses).
pub const USER_INTERACTION_REQUIRED: &str = "USER_INTERACTION_REQUIRED";
pub const NO_NETWORK: &str = "NO_NETWORK";
pub const TRANSIENT_ERROR: &str = "TRANSIENT_ERROR";
pub const PERSISTENT_ERROR: &str = "PERSISTENT_ERROR";
pub const API_CONTRACT_VIOLATION: &str = "API_CONTRACT_VIOLATION";

/// A failed token request, as Teams maps its token service's errors
/// (`code` is that service's error code).
pub fn token_error(
    request_id: &str,
    status: &str,
    code: &str,
    description: &str,
    is_expected: bool,
) -> String {
    response(
        request_id,
        json!({ "success": false, "error": { "status": status, "isExpected": is_expected, "code": code, "subError": "", "description": description } }),
    )
}

/// A request Teams refuses before asking for a token.
pub fn contract_error(request_id: &str, description: &str) -> String {
    response(
        request_id,
        json!({ "success": false, "error": { "status": API_CONTRACT_VIOLATION, "isExpected": true, "description": description } }),
    )
}

/// How an Azure AD failure is reported: (status, code, expected).
pub fn classify(err: &anyhow::Error) -> (&'static str, &'static str, bool) {
    let s = format!("{err:#}");
    let has = |n: &str| s.contains(n);
    if has("interaction_required")
        || has("consent_required")
        || has("login_required")
        || has("AADSTS65001")
        || has("AADSTS50076")
        || has("AADSTS50079")
        || has("AADSTS50058")
        || has("AADSTS700084")
    {
        (USER_INTERACTION_REQUIRED, "InteractionRequired", true)
    } else if has("failed to send") || has("error sending request") || has("dns error") {
        (NO_NETWORK, "NoNetwork", false)
    } else if has("temporarily_unavailable") || has("HTTP 5") || has("(5") {
        (TRANSIENT_ERROR, "TransientError", false)
    } else {
        (PERSISTENT_ERROR, "PersistentError", false)
    }
}

struct Cached {
    access_token: String,
    id_token: String,
    until: Instant,
}

static CACHE: Mutex<Option<HashMap<String, Cached>>> = Mutex::new(None);

fn cache_key(client_id: &str, origin: &str, scope: &str, claims: Option<&str>) -> String {
    format!(
        "{client_id}\n{origin}\n{scope}\n{}",
        claims.unwrap_or_default()
    )
}

/// Forget every brokered token (sign-out).
pub fn clear() {
    if let Ok(mut c) = CACHE.lock() {
        *c = None;
    }
}

/// The signed-in account from OST's stored sign-in (no network).
pub fn stored_account() -> Option<Account> {
    let c = Config::load().ok()?;
    let oid = c.object_id()?;
    Some(Account {
        oid,
        tenant_id: c.tenant_id().unwrap_or_default(),
        username: c.user_principal_name().unwrap_or_default(),
        name: c.display_name().unwrap_or_default(),
    })
}

/// Answer one `NestedAppAuthRequest` from a frame served from `origin`.
/// `trusted`: whether Teams trusts that origin for this app (it then
/// tells the app which account is signed in).
pub async fn execute(request: &str, origin: &str, trusted: bool) -> String {
    match Request::parse(request) {
        Request::InitContext { request_id } => {
            let account = if trusted { stored_account() } else { None };
            init_context(&request_id, account.as_ref())
        }
        Request::MissingParameters { request_id } => {
            contract_error(&request_id, "Missing parameters.")
        }
        Request::Invalid { request_id } => contract_error(&request_id, "Not a valid request."),
        Request::Token {
            request_id,
            client_id,
            scope,
            claims,
            force_refresh,
        } => {
            if !origin.starts_with("https://") {
                return contract_error(&request_id, "Missing parameters.");
            }
            let key = cache_key(&client_id, origin, &scope, claims.as_deref());
            let cached = (!force_refresh)
                .then(|| {
                    let c = CACHE.lock().ok()?;
                    let e = c.as_ref()?.get(&key)?;
                    let left = e.until.checked_duration_since(Instant::now())?;
                    (left > RENEW_BEFORE)
                        .then(|| (e.access_token.clone(), e.id_token.clone(), left.as_secs()))
                })
                .flatten();
            let (access, id, left) = match cached {
                Some(t) => t,
                None => match super::oauth::brokered_tokens(
                    &client_id,
                    origin,
                    &scope,
                    claims.as_deref(),
                )
                .await
                {
                    Ok(t) => {
                        let left = t.expires_in.unwrap_or(3600);
                        let id = t.id_token.clone().unwrap_or_default();
                        if let Ok(mut c) = CACHE.lock() {
                            c.get_or_insert_with(HashMap::new).insert(
                                key,
                                Cached {
                                    access_token: t.access_token.clone(),
                                    id_token: id.clone(),
                                    until: Instant::now() + Duration::from_secs(left),
                                },
                            );
                        }
                        (t.access_token, id, left)
                    }
                    Err(e) => {
                        let (status, code, expected) = classify(&e);
                        // The description is Azure AD's (no tokens in it).
                        let d = format!("{e:#}");
                        tracing::warn!("NAA token for {client_id} from {origin} failed: {status}");
                        return token_error(
                            &request_id,
                            status,
                            code,
                            &d.chars().take(300).collect::<String>(),
                            expected,
                        );
                    }
                },
            };
            let account = Account::from_id_token(&id)
                .or_else(stored_account)
                .unwrap_or_default();
            token(&request_id, &scope, &access, &id, left, &account)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(method: &str, params: Value) -> String {
        json!({ "messageType": "NestedAppAuthRequest", "method": method, "requestId": "r1", "sendTime": 1, "clientLibrary": "msal.js.browser",
                "clientLibraryVersion": "5.6.1", "tokenParams": params })
        .to_string()
    }

    #[test]
    fn requests_parse_as_msal_sends_them() {
        assert_eq!(
            Request::parse(&req("GetInitContext", Value::Null)),
            Request::InitContext {
                request_id: "r1".into()
            }
        );
        let r = Request::parse(&req(
            "GetToken",
            json!({ "clientId": "243c63a3-247d-41c5-9d83-7788c43f1c43", "scope": "e03a13ee-9730-4cae-8525-47559c8cf18a/.default",
                    "claims": "{\"access_token\":{\"xms_cc\":{\"values\":[\"CP1\"]}}}", "forceRefresh": true, "correlationId": "c" }),
        ));
        assert_eq!(
            r,
            Request::Token {
                request_id: "r1".into(),
                client_id: "243c63a3-247d-41c5-9d83-7788c43f1c43".into(),
                scope: "e03a13ee-9730-4cae-8525-47559c8cf18a/.default".into(),
                claims: Some("{\"access_token\":{\"xms_cc\":{\"values\":[\"CP1\"]}}}".into()),
                force_refresh: true
            }
        );
        assert!(matches!(
            Request::parse(&req(
                "GetTokenPopup",
                json!({ "clientId": "x", "scope": "s" })
            )),
            Request::Token { .. }
        ));
        assert_eq!(
            Request::parse(&req("GetToken", json!({ "clientId": "x" }))),
            Request::MissingParameters {
                request_id: "r1".into()
            }
        );
        assert_eq!(
            Request::parse(&req("Other", Value::Null)),
            Request::Invalid {
                request_id: "r1".into()
            }
        );
        assert_eq!(
            Request::parse("not json"),
            Request::Invalid {
                request_id: "N/A".into()
            }
        );
    }

    #[test]
    fn answers_are_teams_shape() {
        let a = Account {
            oid: "o".into(),
            tenant_id: "t".into(),
            username: "u@x".into(),
            name: "N".into(),
        };
        let v: Value = serde_json::from_str(&init_context("r1", Some(&a))).unwrap();
        assert_eq!(v["messageType"], "NestedAppAuthResponse");
        assert_eq!(v["success"], true);
        assert_eq!(v["initContext"]["sdkName"], "Teams Auth SDK");
        assert_eq!(
            v["initContext"]["accountContext"],
            json!({ "homeAccountId": "o", "tenantId": "t", "environment": ENVIRONMENT })
        );
        let v: Value = serde_json::from_str(&init_context("r1", None)).unwrap();
        assert!(v["initContext"].get("accountContext").is_none());

        let v: Value =
            serde_json::from_str(&token("r1", "https://x/.default", "A", "I", 4000, &a)).unwrap();
        assert_eq!(v["token"]["scope"], "https://x/.default");
        assert_eq!(v["token"]["expires_in"], 4000);
        assert_eq!(v["account"]["__typename"], "NestedAppUser");
        assert_eq!(v["account"], v["token"]["account"]);
        assert_eq!(v["account"]["homeAccountId"], "o");

        let v: Value = serde_json::from_str(&contract_error("r1", "Missing parameters.")).unwrap();
        assert_eq!(v["success"], false);
        assert_eq!(v["error"]["status"], API_CONTRACT_VIOLATION);
        let v: Value = serde_json::from_str(&token_error(
            "r1",
            USER_INTERACTION_REQUIRED,
            "InteractionRequired",
            "d",
            true,
        ))
        .unwrap();
        assert_eq!(v["error"]["code"], "InteractionRequired");
        assert_eq!(v["error"]["subError"], "");
    }

    #[test]
    fn errors_are_classified() {
        let e = |s: &str| anyhow::anyhow!(s.to_string());
        assert_eq!(
            classify(&e(
                "broker token rejected (400): invalid_grant: AADSTS65001: consent"
            ))
            .0,
            USER_INTERACTION_REQUIRED
        );
        assert_eq!(
            classify(&e("Broker token request failed to send")).0,
            NO_NETWORK
        );
        assert_eq!(
            classify(&e("broker token failed with HTTP 503 Service Unavailable")).0,
            TRANSIENT_ERROR
        );
        assert_eq!(
            classify(&e(
                "broker token rejected (400): invalid_request: AADSTS700046"
            ))
            .0,
            PERSISTENT_ERROR
        );
    }

    #[test]
    fn account_comes_from_the_id_token() {
        let enc = |v: Value| base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(v.to_string());
        let t = format!(
            "{}.{}.sig",
            enc(json!({"alg": "none"})),
            enc(json!({"oid": "o1", "tid": "t1", "preferred_username": "u@x", "name": "U X"}))
        );
        assert_eq!(
            Account::from_id_token(&t),
            Some(Account {
                oid: "o1".into(),
                tenant_id: "t1".into(),
                username: "u@x".into(),
                name: "U X".into()
            })
        );
        assert_eq!(Account::from_id_token("junk"), None);
    }
}
