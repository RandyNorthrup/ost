//! Who is signed in, and the user MRIs built from IDs.
//!
//! Teams names people by MRI: `8:orgid:{object id}` for a work (Entra)
//! account, `8:live:.cid.{hex}` (or `8:live:{skype name}`) for a personal
//! Microsoft account, `28:…` for bots and so on. The signed-in account's
//! identity ([`AccountIdentity`]) is filled in once, when the tokens are
//! stored at sign-in and refresh ([`crate::config::Config`]), and every
//! caller reads it from there instead of decoding the access token.
//!
//! This module is the only place that turns a bare object ID into an
//! `8:orgid:` MRI ([`work_user_mri`], [`user_mri`]); everyone else keeps
//! the MRI they were given, whatever its prefix.

use serde::{Deserialize, Serialize};

/// A work (Entra ID) user's MRI prefix.
pub const WORK_PREFIX: &str = "8:orgid:";
/// A personal Microsoft account's MRI prefix.
pub const PERSONAL_PREFIX: &str = "8:live:";

/// What kind of account is signed in.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AccountKind {
    /// A work or school account: `8:orgid:` MRI, a tenant, JWT access tokens.
    #[default]
    Work,
    /// A personal Microsoft account (Teams free): `8:live:` MRI, no tenant,
    /// opaque access tokens. Filled in from the Skype token by the personal
    /// sign-in (TASK-0292).
    Personal,
}

/// The signed-in account's identity.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountIdentity {
    #[serde(default)]
    pub kind: AccountKind,
    /// The user's own MRI (`8:orgid:{oid}` or `8:live:…`).
    pub mri: String,
    /// The account's object ID: the Entra `oid` for a work account. For a
    /// personal account, the ID the personal sign-in records (TASK-0292).
    pub object_id: String,
    /// The work tenant; personal accounts have none.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tenant_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    /// The sign-in name (user@domain, or a personal account's email).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upn: Option<String>,
}

impl AccountIdentity {
    /// A work account's identity from its Entra object ID.
    pub fn work(
        object_id: &str,
        tenant_id: Option<String>,
        display_name: Option<String>,
        upn: Option<String>,
    ) -> Self {
        Self {
            kind: AccountKind::Work,
            mri: work_user_mri(object_id),
            object_id: object_id.to_string(),
            tenant_id,
            display_name,
            upn,
        }
    }

    /// A work account's identity from its access token (a JWT): `oid`,
    /// `tid`, `name` and `upn` (else `unique_name`). None when the token
    /// isn't a work JWT with an object ID (such as a personal account's
    /// opaque token).
    pub fn from_work_token(token: &str) -> Option<Self> {
        let oid = jwt_claim(token, "oid").filter(|o| is_guid(o))?;
        Some(Self::work(
            &oid,
            tenant_id_from_jwt(token),
            jwt_claim(token, "name").filter(|n| !n.trim().is_empty()),
            jwt_claim(token, "upn")
                .or_else(|| jwt_claim(token, "unique_name"))
                .filter(|n| n.contains('@')),
        ))
    }

    pub fn is_personal(&self) -> bool {
        self.kind == AccountKind::Personal
    }

    /// Whether `mri_or_id` names this account: its MRI, or its bare
    /// object ID (ignoring case, as Teams' IDs vary in case).
    pub fn is_me(&self, mri_or_id: &str) -> bool {
        let s = mri_or_id.trim();
        !s.is_empty()
            && (s.eq_ignore_ascii_case(&self.mri) || s.eq_ignore_ascii_case(&self.object_id))
    }
}

/// A work user's MRI from their Entra object ID (`8:orgid:{oid}`).
pub fn work_user_mri(object_id: &str) -> String {
    format!("{WORK_PREFIX}{object_id}")
}

/// A resource account's (application endpoint's) MRI from its object ID
/// (`28:orgid:{oid}`), such as a call queue or auto attendant.
pub fn app_endpoint_mri(object_id: &str) -> String {
    format!("28:orgid:{object_id}")
}

/// An MRI for an ID that may already be one: an MRI (`8:live:…`, `28:…`)
/// is kept as it is, a Skype ID (`orgid:…`, `live:…`) gets its `8:`, and
/// a bare object ID is a work user's (`8:orgid:{oid}`).
pub fn user_mri(id: &str) -> String {
    let id = id.trim();
    if has_type_prefix(id) {
        id.to_string()
    } else if id.contains(':') {
        format!("8:{id}")
    } else {
        work_user_mri(id)
    }
}

/// The Entra object ID in a work user's MRI (`8:orgid:{oid}`); None for
/// any other kind of MRI.
pub fn work_object_id(mri: &str) -> Option<&str> {
    mri.strip_prefix(WORK_PREFIX).filter(|o| !o.is_empty())
}

/// The ID part of an MRI, without its type: the object ID of
/// `8:orgid:{oid}`, `live:.cid.…` of a personal MRI, the app ID of a
/// `28:` bot; a string that isn't an MRI comes back as it is.
pub fn mri_id(mri: &str) -> &str {
    if let Some(oid) = work_object_id(mri) {
        return oid;
    }
    if has_type_prefix(mri) {
        let rest = &mri[mri.find(':').map_or(0, |i| i + 1)..];
        return rest.strip_prefix("orgid:").unwrap_or(rest);
    }
    mri
}

/// Whether an MRI names a person (`8:…`: work, personal, guest), not a
/// bot (`28:`), a phone number (`4:`) or a thread.
pub fn is_person_mri(mri: &str) -> bool {
    mri.starts_with("8:") && mri.len() > 2
}

/// `{digits}:` at the start, as every MRI has (`8:`, `28:`, `4:`, `19:`).
fn has_type_prefix(s: &str) -> bool {
    s.split_once(':').is_some_and(|(t, rest)| {
        !t.is_empty() && !rest.is_empty() && t.bytes().all(|b| b.is_ascii_digit())
    })
}

/// The user's MRI from a Skype token's `skypeid` claim (`orgid:{oid}`,
/// `live:.cid.…`, `teamsvisitor:…`), falling back to its `oid` claim.
pub fn mri_from_skype_token(token: &str) -> Option<String> {
    if let Some(id) = jwt_claim(token, "skypeid").filter(|s| !s.is_empty()) {
        return Some(user_mri(&id));
    }
    jwt_claim(token, "oid")
        .filter(|o| is_guid(o))
        .map(|o| work_user_mri(&o))
}

/// Read one string claim from a JWT payload without verifying the token.
///
/// Tokens here were issued to us by Azure AD over TLS; claims read this way
/// are used only for display and routing, never for authorization.
pub(crate) fn jwt_claim(token: &str, claim: &str) -> Option<String> {
    use base64::Engine;
    let payload = token.split('.').nth(1)?;
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    let json: serde_json::Value = serde_json::from_slice(&decoded).ok()?;
    Some(json.get(claim)?.as_str()?.to_string())
}

pub(crate) fn is_guid(s: &str) -> bool {
    s.len() == 36
        && s.chars().enumerate().all(|(i, c)| {
            matches!(i, 8 | 13 | 18 | 23) == (c == '-') && (c == '-' || c.is_ascii_hexdigit())
        })
}

/// Read the `tid` (tenant id) claim, accepting only a GUID.
pub(crate) fn tenant_id_from_jwt(token: &str) -> Option<String> {
    jwt_claim(token, "tid").filter(|t| is_guid(t))
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    fn jwt_with(payload: &str) -> String {
        let enc = base64::engine::general_purpose::URL_SAFE_NO_PAD;
        format!(
            "{}.{}.sig",
            enc.encode(b"{\"alg\":\"none\"}"),
            enc.encode(payload)
        )
    }

    const OID: &str = "4287e791-1b98-4963-8b94-281c50472683";
    const TID: &str = "09a28c80-30f0-4c4d-98ba-0f7f8d19b780";

    #[test]
    fn work_identity_from_the_access_token() {
        let t = jwt_with(&format!(
            r#"{{"oid":"{OID}","tid":"{TID}","name":"OST Test 1","upn":"ost-test1@x.com"}}"#
        ));
        let me = AccountIdentity::from_work_token(&t).unwrap();
        assert_eq!(me.kind, AccountKind::Work);
        assert_eq!(me.mri, format!("8:orgid:{OID}"));
        assert_eq!(me.object_id, OID);
        assert_eq!(me.tenant_id.as_deref(), Some(TID));
        assert_eq!(me.display_name.as_deref(), Some("OST Test 1"));
        assert_eq!(me.upn.as_deref(), Some("ost-test1@x.com"));
        assert!(me.is_me(&me.mri.to_uppercase()) && me.is_me(OID) && !me.is_me("8:orgid:x"));
        assert!(!me.is_me(""));
    }

    #[test]
    fn no_work_identity_without_an_object_id() {
        // A personal account's opaque token, or a JWT without a GUID oid.
        assert_eq!(
            AccountIdentity::from_work_token("EwB4A8l6BAAU…opaque"),
            None
        );
        assert_eq!(
            AccountIdentity::from_work_token(&jwt_with(r#"{"oid":"nope"}"#)),
            None
        );
        let t = jwt_with(&format!(
            r#"{{"oid":"{OID}","unique_name":"u@x","name":" "}}"#
        ));
        let me = AccountIdentity::from_work_token(&t).unwrap();
        assert_eq!(me.upn.as_deref(), Some("u@x"));
        assert_eq!((me.display_name, me.tenant_id), (None, None));
    }

    #[test]
    fn user_mris_keep_their_prefix() {
        assert_eq!(user_mri(OID), format!("8:orgid:{OID}"));
        assert_eq!(
            user_mri("8:live:.cid.0123456789abcdef"),
            "8:live:.cid.0123456789abcdef"
        );
        assert_eq!(
            user_mri("live:.cid.0123456789abcdef"),
            "8:live:.cid.0123456789abcdef"
        );
        assert_eq!(user_mri("orgid:abc"), "8:orgid:abc");
        assert_eq!(user_mri("28:bot-id"), "28:bot-id");
        assert_eq!(user_mri(" 8:orgid:a "), "8:orgid:a");
        assert_eq!(work_object_id("8:orgid:a"), Some("a"));
        assert_eq!(work_object_id("8:live:a"), None);
        assert_eq!(work_object_id("8:orgid:"), None);
        assert_eq!(mri_id("8:orgid:a"), "a");
        assert_eq!(mri_id("8:live:.cid.1"), "live:.cid.1");
        assert_eq!(mri_id("28:orgid:bot"), "bot");
        assert_eq!(mri_id("28:bot"), "bot");
        assert_eq!(mri_id("a"), "a");
        assert!(is_person_mri("8:live:x") && is_person_mri("8:orgid:x"));
        assert!(!is_person_mri("28:x") && !is_person_mri("8:"));
    }

    #[test]
    fn skype_token_mri() {
        let work = jwt_with(&format!(r#"{{"skypeid":"orgid:{OID}"}}"#));
        assert_eq!(mri_from_skype_token(&work), Some(format!("8:orgid:{OID}")));
        let personal = jwt_with(r#"{"skypeid":"live:.cid.0123456789abcdef"}"#);
        assert_eq!(
            mri_from_skype_token(&personal).as_deref(),
            Some("8:live:.cid.0123456789abcdef")
        );
        let oid_only = jwt_with(&format!(r#"{{"oid":"{OID}"}}"#));
        assert_eq!(
            mri_from_skype_token(&oid_only),
            Some(format!("8:orgid:{OID}"))
        );
        assert_eq!(mri_from_skype_token("x"), None);
    }

    #[test]
    fn identity_round_trips_through_toml() {
        let me = AccountIdentity::work(OID, Some(TID.into()), Some("A".into()), None);
        #[derive(Serialize, Deserialize)]
        struct W {
            identity: AccountIdentity,
        }
        let s = toml::to_string(&W {
            identity: me.clone(),
        })
        .unwrap();
        assert!(s.contains("kind = \"work\""));
        assert_eq!(toml::from_str::<W>(&s).unwrap().identity, me);
    }
}
