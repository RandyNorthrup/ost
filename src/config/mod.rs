//! Configuration and credential storage

use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::auth::{StoredToken, TokenStore};
use crate::identity::{AccountIdentity, tenant_id_from_jwt};

/// Application configuration
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Config {
    /// Stored AAD access token (audience: api.spaces.skype.com)
    pub access_token: Option<StoredToken>,
    /// Stored AAD refresh token
    pub refresh_token: Option<String>,
    /// User's tenant ID (from last login)
    pub tenant_id: Option<String>,
    /// Stored Skype token (from authsvc exchange)
    pub skype_token: Option<StoredToken>,
    /// Stored Graph API access token (audience: graph.microsoft.com)
    pub graph_token: Option<StoredToken>,
    /// Stored IC3 token (audience: ic3.teams.office.com)
    pub ic3_token: Option<StoredToken>,
    /// Stored recorder service token (audience: 4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76)
    pub recorder_token: Option<StoredToken>,
    /// Regional endpoint URLs from authsvc response (JSON stored as string for TOML compat)
    pub region_gtms: Option<String>,
    /// How the stored tokens were signed in: None for the device code (Teams
    /// desktop's client), "teams-web" for the browser sign-in (Teams on the
    /// web's client). Not a secret; kept when signing out.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth_flow: Option<String>,
    /// Teams' authz `licenseDetails` (JSON as a string, like region_gtms).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub license_details: Option<String>,
    /// True when the tokens above live in the desktop keyring instead of
    /// this file; the file then holds no secrets.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub tokens_in_keyring: bool,
    /// Keep the tokens in this file when there is no keyring (opt-in,
    /// weaker than the keyring; Settings ▸ Accounts or `OST_NO_KEYRING=1`).
    /// Not a secret; kept when signing out.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub allow_token_file: bool,
    /// The signed-in account, filled in when its tokens are stored (sign-in
    /// and refresh). Not a secret: it is what the app shows as "you".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub identity: Option<AccountIdentity>,
}

/// Every secret in [`Config`], stored as one keyring entry.
#[derive(Default, Clone, Serialize, Deserialize)]
struct Secrets {
    access_token: Option<StoredToken>,
    refresh_token: Option<String>,
    skype_token: Option<StoredToken>,
    graph_token: Option<StoredToken>,
    ic3_token: Option<StoredToken>,
    recorder_token: Option<StoredToken>,
}

impl Secrets {
    fn any(&self) -> bool {
        self.access_token.is_some()
            || self.refresh_token.is_some()
            || self.skype_token.is_some()
            || self.graph_token.is_some()
            || self.ic3_token.is_some()
            || self.recorder_token.is_some()
    }

    fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

const KEYRING_SERVICE: &str = "ost";
const KEYRING_ACCOUNT: &str = "teams-tokens";

/// A second account's profile (`OST_PROFILE=name`): its own config folder
/// and keyring entry, so two accounts can be signed in side by side.
pub fn profile() -> Option<String> {
    std::env::var("OST_PROFILE")
        .ok()
        .map(|p| p.trim().to_string())
        .filter(|p| {
            !p.is_empty()
                && p.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        })
}

/// The keyring account the tokens live under ("teams-tokens", or
/// "teams-tokens:{profile}"). In a Flatpak the config folder is the
/// sandbox's own (~/.var/app/{app id}/config) but the desktop keyring is
/// the host's, so the account also carries the app id
/// ("teams-tokens@io.github.RandyNorthrup.ost"): the sandbox's sign-in
/// never replaces an OST installed on the host.
fn keyring_account() -> String {
    let account = match profile() {
        Some(p) => format!("{KEYRING_ACCOUNT}:{p}"),
        None => KEYRING_ACCOUNT.to_string(),
    };
    match std::env::var("FLATPAK_ID")
        .ok()
        .filter(|id| !id.trim().is_empty())
    {
        Some(id) => format!("{account}@{}", id.trim()),
        None => account,
    }
}

/// `OST_NO_KEYRING=1`: don't use the keyring; keep the tokens in the
/// config file (an explicit opt-in for headless machines and CI).
fn keyring_disabled() -> bool {
    std::env::var_os("OST_NO_KEYRING").is_some()
}

fn keyring_entry() -> Option<keyring::Entry> {
    if keyring_disabled() {
        return None;
    }
    keyring::Entry::new(KEYRING_SERVICE, &keyring_account()).ok()
}

/// Where the signed-in account's tokens are kept.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum TokenStorage {
    /// The desktop keyring (Secret Service): the default.
    Keyring,
    /// The config file (0600), as the user chose (`OST_NO_KEYRING=1` or
    /// Settings): weaker than the keyring.
    File,
    /// Only this run's memory: there is no working keyring and no opt-in
    /// to the file, so the next start asks to sign in again.
    Memory,
}

/// A secret store for the tokens (the keyring; a fake in tests).
trait SecretStore {
    fn get(&self) -> std::result::Result<Option<String>, String>;
    fn set(&self, json: &str) -> std::result::Result<(), String>;
    fn delete(&self) -> std::result::Result<(), String>;
}

impl SecretStore for keyring::Entry {
    fn get(&self) -> std::result::Result<Option<String>, String> {
        match self.get_password() {
            Ok(j) => Ok(Some(j)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }
    fn set(&self, json: &str) -> std::result::Result<(), String> {
        self.set_password(json).map_err(|e| e.to_string())
    }
    fn delete(&self) -> std::result::Result<(), String> {
        match self.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

/// Tokens kept in memory only (no keyring, no opt-in), by keyring account
/// (one per profile), so every `Config::load` in this run finds them.
static MEMORY: std::sync::Mutex<Vec<(String, Secrets)>> = std::sync::Mutex::new(Vec::new());
/// Where the last load or save kept the tokens.
static STORAGE: std::sync::Mutex<Option<TokenStorage>> = std::sync::Mutex::new(None);

fn memory_get(account: &str) -> Option<Secrets> {
    MEMORY
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .iter()
        .find(|(a, _)| a == account)
        .map(|(_, s)| s.clone())
}

fn memory_set(account: &str, secrets: Option<Secrets>) {
    let mut m = MEMORY.lock().unwrap_or_else(|e| e.into_inner());
    m.retain(|(a, _)| a != account);
    if let Some(s) = secrets {
        m.push((account.to_string(), s));
    }
}

fn note_storage(s: TokenStorage) {
    *STORAGE.lock().unwrap_or_else(|e| e.into_inner()) = Some(s);
}

/// Where this run keeps the tokens (for Settings): the file when opted
/// in, memory when the keyring didn't work, else the keyring.
pub fn token_storage() -> TokenStorage {
    if keyring_disabled() {
        return TokenStorage::File;
    }
    STORAGE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .unwrap_or(TokenStorage::Keyring)
}

/// Settings ▸ Accounts' "Stay signed in without a keyring": the opt-in to
/// keeping the tokens in the config file (0600) when there is no keyring.
pub fn set_allow_token_file(on: bool) -> Result<()> {
    let mut c = Config::load()?;
    c.allow_token_file = on;
    c.save()
}

impl Config {
    /// The signed-in account. Configs written before it was recorded get it
    /// from their stored access token when they are loaded.
    pub fn identity(&self) -> Option<&AccountIdentity> {
        self.identity.as_ref()
    }

    /// Record the signed-in account. A work account's identity comes from
    /// its access token ([`TokenStore::set_access_token`]); the personal
    /// sign-in (TASK-0292) sets its `8:live:` identity here from the Skype
    /// token, since its access tokens are opaque.
    pub fn set_identity(&mut self, identity: AccountIdentity) {
        if identity.tenant_id.is_some() || identity.is_personal() {
            self.tenant_id = identity.tenant_id.clone();
        }
        self.identity = Some(identity);
    }

    /// The signed-in user's own MRI (`8:orgid:{oid}`, or `8:live:…`).
    pub fn self_mri(&self) -> Option<String> {
        Some(self.identity()?.mri.clone())
    }

    /// The signed-in tenant: the account's, or for configs from before the
    /// identity was recorded, the one recorded at the last sign-in. None
    /// for a personal account.
    pub fn tenant_id(&self) -> Option<String> {
        match self.identity() {
            Some(me) if me.is_personal() => None,
            Some(me) if me.tenant_id.is_some() => me.tenant_id.clone(),
            _ => self.tenant_id.clone(),
        }
    }

    /// The signed-in user's display name.
    pub fn display_name(&self) -> Option<String> {
        self.identity()?.display_name.clone()
    }

    /// The signed-in user's sign-in name (user@domain).
    pub fn user_principal_name(&self) -> Option<String> {
        self.identity()?.upn.clone()
    }

    /// The signed-in user's object id (a work account's Entra `oid`).
    pub fn object_id(&self) -> Option<String> {
        Some(self.identity()?.object_id.clone()).filter(|o| !o.is_empty())
    }

    /// Fill in the identity of a config written before it was recorded,
    /// from its stored (work) access token.
    fn ensure_identity(&mut self) {
        if self.identity.is_none()
            && let Some(me) = self
                .access_token
                .as_ref()
                .and_then(|t| AccountIdentity::from_work_token(&t.token))
        {
            self.set_identity(me);
        }
    }

    /// Get config directory path
    pub fn config_dir() -> Result<PathBuf> {
        let proj_dirs = ProjectDirs::from("com", "teams-cli", "teams-cli")
            .context("Could not determine config directory")?;
        let base = proj_dirs.config_dir().to_path_buf();
        Ok(match profile() {
            Some(p) => base.join("profiles").join(p),
            None => base,
        })
    }

    /// Get config file path
    fn config_path() -> Result<PathBuf> {
        Ok(Self::config_dir()?.join("config.toml"))
    }

    /// Load configuration from disk, and the tokens from the keyring (or
    /// this run's memory, or the file when opted in).
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;
        let entry = keyring_entry();
        let store = entry.as_ref().map(|e| e as &dyn SecretStore);
        Self::load_from(&path, store, keyring_disabled(), &keyring_account())
    }

    fn load_from(
        path: &std::path::Path,
        store: Option<&dyn SecretStore>,
        no_keyring: bool,
        account: &str,
    ) -> Result<Self> {
        if !path.exists() {
            let mut c = Self::default();
            if let Some(s) = memory_get(account) {
                c.apply_secrets(s);
            }
            return Ok(c);
        }

        let content = fs::read_to_string(path).context("Failed to read config file")?;
        let mut config: Self = toml::from_str(&content).context("Failed to parse config file")?;
        if config.tokens_in_keyring {
            match store.map(|s| s.get()) {
                Some(Ok(Some(json))) => {
                    config.apply_secrets(
                        serde_json::from_str(&json).context("Keyring entry is not valid")?,
                    );
                    note_storage(TokenStorage::Keyring);
                }
                Some(Ok(None)) => {
                    tracing::warn!("Tokens were in the keyring but are gone; sign in again");
                }
                Some(Err(e)) => return Err(anyhow::anyhow!("Could not read the keyring: {e}")),
                None => tracing::warn!("Tokens are in the keyring, but the keyring is disabled"),
            }
        } else if config.secrets().any() {
            if no_keyring {
                note_storage(TokenStorage::File);
            } else {
                // Tokens in the file: move them to the keyring once it
                // works (OST 0.2.1 and earlier fell back to the file
                // without asking). Without a keyring they stay in the file
                // only if the user opted in; otherwise they last this run
                // and the plaintext copy goes.
                let secrets = config.secrets();
                let mut on_disk = config.clone_settings();
                match store.map(|s| s.set(&secrets.to_json())) {
                    Some(Ok(())) => {
                        on_disk.tokens_in_keyring = true;
                        note_storage(TokenStorage::Keyring);
                        tracing::info!("Moved the sign-in from the config file to the keyring");
                        write_private(path, toml::to_string_pretty(&on_disk)?.as_bytes())?;
                    }
                    _ if config.allow_token_file => note_storage(TokenStorage::File),
                    other => {
                        if let Some(Err(e)) = other {
                            tracing::warn!("Keyring unavailable ({e})");
                        }
                        memory_set(account, Some(secrets));
                        note_storage(TokenStorage::Memory);
                        tracing::warn!(
                            "No keyring: removed the sign-in from the config file; it lasts until OST quits"
                        );
                        write_private(path, toml::to_string_pretty(&on_disk)?.as_bytes())?;
                    }
                }
            }
        } else if let Some(s) = memory_get(account) {
            config.apply_secrets(s);
            note_storage(TokenStorage::Memory);
        }
        config.ensure_identity();
        Ok(config)
    }

    /// Save configuration. Tokens go to the desktop keyring; without a
    /// working keyring they stay in this run's memory (the next start asks
    /// to sign in again), unless the user opted in to keeping them in the
    /// file (`OST_NO_KEYRING=1` or Settings), which is created owner-only
    /// (0600) and replaced atomically.
    pub fn save(&self) -> Result<()> {
        let dir = Self::config_dir()?;
        create_private_dir(&dir)?;
        let entry = keyring_entry();
        let store = entry.as_ref().map(|e| e as &dyn SecretStore);
        self.save_to(
            &Self::config_path()?,
            store,
            keyring_disabled(),
            &keyring_account(),
        )
    }

    fn save_to(
        &self,
        path: &std::path::Path,
        store: Option<&dyn SecretStore>,
        no_keyring: bool,
        account: &str,
    ) -> Result<()> {
        let secrets = self.secrets();
        let mut on_disk = self.clone_settings();
        let to_file = |on_disk: &mut Config, secrets: Secrets| {
            on_disk.apply_secrets(secrets);
            memory_set(account, None);
            note_storage(TokenStorage::File);
        };
        if no_keyring {
            to_file(&mut on_disk, secrets);
        } else {
            match store.map(|s| s.set(&secrets.to_json())) {
                Some(Ok(())) => {
                    on_disk.tokens_in_keyring = true;
                    memory_set(account, None);
                    note_storage(TokenStorage::Keyring);
                }
                other => {
                    let why = match other {
                        Some(Err(e)) => e,
                        _ => "no keyring".into(),
                    };
                    if self.allow_token_file {
                        tracing::warn!(
                            "Keyring unavailable ({why}); keeping the sign-in in the config file, as chosen"
                        );
                        to_file(&mut on_disk, secrets);
                    } else {
                        tracing::warn!(
                            "Keyring unavailable ({why}); keeping the sign-in in memory until OST quits"
                        );
                        memory_set(account, secrets.any().then_some(secrets));
                        note_storage(TokenStorage::Memory);
                    }
                }
            }
        }
        let content = toml::to_string_pretty(&on_disk).context("Failed to serialize config")?;
        write_private(path, content.as_bytes())
    }

    fn secrets(&self) -> Secrets {
        Secrets {
            access_token: self.access_token.clone(),
            refresh_token: self.refresh_token.clone(),
            skype_token: self.skype_token.clone(),
            graph_token: self.graph_token.clone(),
            ic3_token: self.ic3_token.clone(),
            recorder_token: self.recorder_token.clone(),
        }
    }

    fn apply_secrets(&mut self, s: Secrets) {
        self.access_token = s.access_token;
        self.refresh_token = s.refresh_token;
        self.skype_token = s.skype_token;
        self.graph_token = s.graph_token;
        self.ic3_token = s.ic3_token;
        self.recorder_token = s.recorder_token;
    }

    /// Everything except the tokens.
    fn clone_settings(&self) -> Self {
        Self {
            tenant_id: self.tenant_id.clone(),
            region_gtms: self.region_gtms.clone(),
            license_details: self.license_details.clone(),
            auth_flow: self.auth_flow.clone(),
            identity: self.identity.clone(),
            allow_token_file: self.allow_token_file,
            ..Self::default()
        }
    }

    pub fn get_skype_token(&self) -> Option<StoredToken> {
        self.skype_token.clone()
    }

    pub fn set_skype_token(&mut self, token: String, expires_in: Option<u64>) {
        self.skype_token = Some(StoredToken::new(token, expires_in));
    }

    pub fn set_region_gtms(&mut self, gtms: serde_json::Value) {
        self.region_gtms = Some(gtms.to_string());
    }

    pub fn get_region_gtms(&self) -> Option<serde_json::Value> {
        self.region_gtms
            .as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
    }

    pub fn set_license_details(&mut self, l: serde_json::Value) {
        self.license_details = Some(l.to_string());
    }

    pub fn get_license_details(&self) -> Option<serde_json::Value> {
        self.license_details
            .as_deref()
            .and_then(|s| serde_json::from_str(s).ok())
    }

    pub fn get_graph_token(&self) -> Option<StoredToken> {
        self.graph_token.clone()
    }

    pub fn set_graph_token(&mut self, token: String, expires_in: Option<u64>) {
        self.graph_token = Some(StoredToken::new(token, expires_in));
    }

    pub fn get_ic3_token(&self) -> Option<StoredToken> {
        self.ic3_token.clone()
    }

    pub fn set_ic3_token(&mut self, token: String, expires_in: Option<u64>) {
        self.ic3_token = Some(StoredToken::new(token, expires_in));
    }

    pub fn get_recorder_token(&self) -> Option<StoredToken> {
        self.recorder_token.clone()
    }

    pub fn set_recorder_token(&mut self, token: String, expires_in: Option<u64>) {
        self.recorder_token = Some(StoredToken::new(token, expires_in));
    }
}

impl TokenStore for Config {
    fn get_access_token(&self) -> Option<StoredToken> {
        self.access_token.clone()
    }

    fn set_access_token(&mut self, token: String, expires_in: Option<u64>) {
        // The account's identity (and the tenant calling needs) comes from
        // a work account's access token each time it is stored, so both a
        // fresh login and a refresh keep it current. A personal account's
        // opaque token leaves the identity its sign-in recorded.
        match AccountIdentity::from_work_token(&token) {
            Some(me) => self.set_identity(me),
            None => {
                if let Some(tid) = tenant_id_from_jwt(&token) {
                    self.tenant_id = Some(tid);
                }
            }
        }
        self.access_token = Some(StoredToken::new(token, expires_in));
    }

    fn get_refresh_token(&self) -> Option<String> {
        self.refresh_token.clone()
    }

    fn set_refresh_token(&mut self, token: String) {
        self.refresh_token = Some(token);
    }

    fn clear_tokens(&mut self) {
        if let Some(entry) = keyring_entry()
            && let Err(e) = SecretStore::delete(&entry)
        {
            tracing::warn!("Could not remove tokens from the keyring: {e}");
        }
        memory_set(&keyring_account(), None);
        self.forget_account();
    }
}

impl Config {
    /// Forget the signed-in account: its tokens and what came with them
    /// (tenant, regional endpoints, license details). Settings stay, such
    /// as `auth_flow`, so signing out doesn't change how this profile
    /// signs in.
    fn forget_account(&mut self) {
        self.tokens_in_keyring = false;
        self.access_token = None;
        self.refresh_token = None;
        self.skype_token = None;
        self.graph_token = None;
        self.ic3_token = None;
        self.recorder_token = None;
        self.tenant_id = None;
        self.identity = None;
        self.region_gtms = None;
        self.license_details = None;
    }
}

/// Write a file readable only by its owner, atomically and without a
/// window in which it is readable by others: a fresh temporary file
/// created 0600 (never an existing one, whose mode would stay), synced,
/// then renamed over the old file.
fn write_private(path: &std::path::Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("config.toml");
    let tmp = path.with_file_name(format!(
        ".{name}.{}.{}.tmp",
        std::process::id(),
        uuid::Uuid::new_v4().simple()
    ));
    let mut opts = fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    let mut f = opts.open(&tmp).context("Failed to write config file")?;
    let written = f
        .write_all(bytes)
        .and_then(|_| f.sync_all())
        .context("Failed to write config file")
        .and_then(|_| fs::rename(&tmp, path).context("Failed to replace config file"));
    if written.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    written
}

/// The config folder, owner-only (0700) when it is created.
fn create_private_dir(dir: &std::path::Path) -> Result<()> {
    let mut b = fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        b.mode(0o700);
    }
    b.create(dir).context("Failed to create config directory")
}

/// An account signed in on this device (Teams' "Accounts and orgs" list):
/// each lives in its own profile, with its own tokens and windows.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Account {
    /// The profile ("" for the first account, else `OST_PROFILE`).
    pub profile: String,
    pub upn: String,
    pub name: String,
    #[serde(default)]
    pub object_id: String,
    /// The account's last presence, as its window last saw it.
    #[serde(default)]
    pub availability: String,
    /// Its organisation's name (Teams' Accounts and orgs list).
    #[serde(default)]
    pub org: String,
}

fn accounts_path() -> Result<PathBuf> {
    let proj_dirs = ProjectDirs::from("com", "teams-cli", "teams-cli")
        .context("Could not determine config directory")?;
    Ok(proj_dirs.config_dir().join("accounts.json"))
}

/// Every account signed in on this device, the first one first.
pub fn accounts() -> Vec<Account> {
    accounts_path()
        .ok()
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// The list with `a` recorded (by profile), the first profile first.
pub fn with_account(mut list: Vec<Account>, a: Account) -> Vec<Account> {
    match list.iter_mut().find(|x| x.profile == a.profile) {
        Some(x) => *x = a,
        None => list.push(a),
    }
    list.sort_by_key(|x| !x.profile.is_empty());
    list
}

/// Records this profile's account (at sign-in and as its presence
/// changes); `None` removes it (signed out).
pub fn record_account(a: Option<Account>) -> Result<()> {
    let me = profile().unwrap_or_default();
    let list: Vec<Account> = accounts()
        .into_iter()
        .filter(|x| x.profile != me || a.is_some())
        .collect();
    let list = match a {
        Some(a) => with_account(list, Account { profile: me, ..a }),
        None => list,
    };
    let path = accounts_path()?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    write_private(&path, serde_json::to_string_pretty(&list)?.as_bytes())
}

/// A profile name for the next account ("account2", "account3", …) that
/// no account or profile folder uses yet.
pub fn new_profile_name(list: &[Account], taken: &[String]) -> String {
    (2..)
        .map(|n| format!("account{n}"))
        .find(|p| !list.iter().any(|a| &a.profile == p) && !taken.contains(p))
        .expect("a free name")
}

/// A profile's config folder ("" is the first account's).
pub fn profile_dir(profile: &str) -> Result<PathBuf> {
    let base = ProjectDirs::from("com", "teams-cli", "teams-cli")
        .context("Could not determine config directory")?
        .config_dir()
        .to_path_buf();
    Ok(if profile.is_empty() {
        base
    } else {
        base.join("profiles").join(profile)
    })
}

/// What each account's window last published for Teams' "Activity in
/// other accounts and orgs" (its missed count and recent activity and
/// chats), read by the other accounts' windows.
pub fn hub_summary(profile: &str) -> Option<serde_json::Value> {
    let text = fs::read_to_string(profile_dir(profile).ok()?.join("hub.json")).ok()?;
    serde_json::from_str(&text).ok()
}

/// Publish this account's summary (written only when it changed).
pub fn write_hub_summary(json: &str) -> Result<()> {
    let path = Config::config_dir()?.join("hub.json");
    if fs::read_to_string(&path).is_ok_and(|old| old == json) {
        return Ok(());
    }
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    write_private(&path, json.as_bytes())
}

/// Teams lets at most two orgs be pinned to the app bar (its hub's
/// pinningDisabled at two pinned tenants).
pub const MAX_PINNED_ORGS: usize = 2;

fn hub_pins_path() -> Result<PathBuf> {
    let proj_dirs = ProjectDirs::from("com", "teams-cli", "teams-cli")
        .context("Could not determine config directory")?;
    Ok(proj_dirs.config_dir().join("hub-pins.json"))
}

/// The orgs pinned to the app bar from "Activity in other accounts and
/// orgs" ("Pin this org"), in the order they were pinned: each account's
/// address, lower-case (each OST account is one org). One list for the
/// device, as Teams keeps it for its one app.
pub fn hub_pins() -> Vec<String> {
    hub_pins_path()
        .ok()
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// The list with `upn` pinned (added at the end, at most
/// MAX_PINNED_ORGS) or unpinned.
pub fn with_hub_pin(mut list: Vec<String>, upn: &str, on: bool) -> Vec<String> {
    let upn = upn.to_lowercase();
    list.retain(|u| u != &upn);
    if on && !upn.is_empty() && list.len() < MAX_PINNED_ORGS {
        list.push(upn);
    }
    list
}

/// Pin or unpin an account's org.
pub fn set_hub_pin(upn: &str, on: bool) -> Result<()> {
    let list = with_hub_pin(hub_pins(), upn, on);
    let path = hub_pins_path()?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    write_private(&path, serde_json::to_string_pretty(&list)?.as_bytes())
}

/// The profile folders that already exist.
pub fn profile_folders() -> Vec<String> {
    ProjectDirs::from("com", "teams-cli", "teams-cli")
        .and_then(|d| fs::read_dir(d.config_dir().join("profiles")).ok())
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().into_string().ok())
        .collect()
}

#[cfg(test)]
mod account_tests {
    use super::*;

    #[test]
    fn accounts_keep_one_per_profile_first_account_first() {
        let a = Account {
            profile: "account2".into(),
            upn: "b@x".into(),
            ..Default::default()
        };
        let first = Account {
            profile: String::new(),
            upn: "a@x".into(),
            ..Default::default()
        };
        let list = with_account(with_account(vec![], a.clone()), first.clone());
        assert_eq!(list[0].upn, "a@x");
        let again = with_account(
            list,
            Account {
                availability: "Busy".into(),
                ..a
            },
        );
        assert_eq!(again.len(), 2);
        assert_eq!(again[1].availability, "Busy");
        assert_eq!(new_profile_name(&again, &["account3".into()]), "account4");
    }

    #[test]
    fn pinned_orgs_keep_their_order_up_to_two() {
        let l = with_hub_pin(vec![], "B@x", true);
        let l = with_hub_pin(l, "a@x", true);
        assert_eq!(l, ["b@x", "a@x"]);
        // A third waits (Teams disables Pin this org at two).
        assert_eq!(with_hub_pin(l.clone(), "c@x", true), ["b@x", "a@x"]);
        assert_eq!(with_hub_pin(l, "b@x", false), ["a@x"]);
    }
}

#[cfg(test)]
mod tenant_id_tests {
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

    #[test]
    fn reads_tid_claim() {
        let t = jwt_with(r#"{"tid":"2716d134-5614-4856-a48d-2002edd9a570","oid":"x"}"#);
        assert_eq!(
            tenant_id_from_jwt(&t).as_deref(),
            Some("2716d134-5614-4856-a48d-2002edd9a570")
        );
    }

    #[test]
    fn rejects_missing_or_malformed_tid() {
        assert_eq!(tenant_id_from_jwt(&jwt_with(r#"{"oid":"x"}"#)), None);
        assert_eq!(
            tenant_id_from_jwt(&jwt_with(r#"{"tid":"../../etc"}"#)),
            None
        );
        assert_eq!(tenant_id_from_jwt("not-a-jwt"), None);
    }

    #[test]
    fn identity_comes_from_the_access_token_once() {
        let mut c = Config::default();
        assert_eq!(c.display_name(), None);
        assert_eq!(c.self_mri(), None);
        c.set_access_token(
            jwt_with(
                r#"{"name":"OST Test 1","oid":"4287e791-1b98-4963-8b94-281c50472683","upn":"t1@x.com"}"#,
            ),
            Some(3600),
        );
        assert_eq!(c.display_name().as_deref(), Some("OST Test 1"));
        assert_eq!(c.user_principal_name().as_deref(), Some("t1@x.com"));
        assert_eq!(
            c.object_id().as_deref(),
            Some("4287e791-1b98-4963-8b94-281c50472683")
        );
        assert_eq!(
            c.self_mri().as_deref(),
            Some("8:orgid:4287e791-1b98-4963-8b94-281c50472683")
        );
        // A refresh brings the new name.
        c.set_access_token(
            jwt_with(r#"{"name":"OST One","oid":"4287e791-1b98-4963-8b94-281c50472683"}"#),
            None,
        );
        assert_eq!(c.display_name().as_deref(), Some("OST One"));
        // A token without an object id (a personal account's opaque one)
        // keeps the identity its sign-in recorded.
        c.set_access_token("opaque".into(), None);
        assert_eq!(c.display_name().as_deref(), Some("OST One"));
    }

    #[test]
    fn old_configs_get_their_identity_and_keep_it_on_disk() {
        let mut c = Config {
            access_token: Some(StoredToken::new(
                jwt_with(
                    r#"{"oid":"4287e791-1b98-4963-8b94-281c50472683","tid":"09a28c80-30f0-4c4d-98ba-0f7f8d19b780"}"#,
                ),
                Some(3600),
            )),
            ..Default::default()
        };
        assert_eq!(c.identity(), None);
        c.ensure_identity();
        assert_eq!(
            c.tenant_id().as_deref(),
            Some("09a28c80-30f0-4c4d-98ba-0f7f8d19b780")
        );
        let on_disk = toml::to_string_pretty(&c.clone_settings()).unwrap();
        let back: Config = toml::from_str(&on_disk).unwrap();
        assert_eq!(back.identity(), c.identity());
        assert!(back.access_token.is_none());
    }

    #[test]
    fn personal_accounts_have_no_tenant() {
        let mut c = Config {
            tenant_id: Some("09a28c80-30f0-4c4d-98ba-0f7f8d19b780".into()),
            ..Default::default()
        };
        c.set_identity(AccountIdentity {
            kind: crate::identity::AccountKind::Personal,
            mri: "8:live:.cid.0123456789abcdef".into(),
            object_id: String::new(),
            tenant_id: None,
            display_name: Some("P".into()),
            upn: None,
        });
        assert_eq!(c.tenant_id(), None);
        assert_eq!(c.object_id(), None);
        assert_eq!(
            c.self_mri().as_deref(),
            Some("8:live:.cid.0123456789abcdef")
        );
    }

    #[test]
    fn set_access_token_records_tenant() {
        let mut c = Config::default();
        c.set_access_token(
            jwt_with(r#"{"tid":"09a28c80-30f0-4c4d-98ba-0f7f8d19b780"}"#),
            Some(3600),
        );
        assert_eq!(
            c.tenant_id.as_deref(),
            Some("09a28c80-30f0-4c4d-98ba-0f7f8d19b780")
        );
    }
}

#[cfg(test)]
mod sign_out_tests {
    use super::*;

    #[test]
    fn signing_out_keeps_settings_and_forgets_the_account() {
        let mut c = Config {
            access_token: Some(StoredToken::new("aad".into(), Some(3600))),
            refresh_token: Some("refresh".into()),
            tenant_id: Some("09a28c80-30f0-4c4d-98ba-0f7f8d19b780".into()),
            skype_token: Some(StoredToken::new("skype".into(), Some(3600))),
            graph_token: Some(StoredToken::new("graph".into(), Some(3600))),
            ic3_token: Some(StoredToken::new("ic3".into(), Some(3600))),
            recorder_token: Some(StoredToken::new("recorder".into(), Some(3600))),
            region_gtms: Some("{}".into()),
            auth_flow: Some(crate::auth::TEAMS_WEB_FLOW.into()),
            license_details: Some("{}".into()),
            tokens_in_keyring: true,
            allow_token_file: false,
            identity: AccountIdentity::from_work_token(
                "x.eyJvaWQiOiI0Mjg3ZTc5MS0xYjk4LTQ5NjMtOGI5NC0yODFjNTA0NzI2ODMifQ.s",
            ),
        };
        assert!(c.identity().is_some());
        c.forget_account();
        assert!(c.secrets().refresh_token.is_none() && c.get_access_token().is_none());
        assert!(
            c.skype_token.is_none()
                && c.graph_token.is_none()
                && c.ic3_token.is_none()
                && c.recorder_token.is_none()
        );
        assert!(c.tenant_id.is_none() && c.region_gtms.is_none() && c.license_details.is_none());
        assert!(c.identity().is_none());
        assert!(!c.tokens_in_keyring);

        // config.toml as save() writes it: the sign-in method stays, so the
        // next sign-in refreshes with the same client.
        let on_disk = toml::to_string_pretty(&c.clone_settings()).unwrap();
        assert_eq!(on_disk.trim(), "auth_flow = \"teams-web\"");
        let back: Config = toml::from_str(&on_disk).unwrap();
        assert_eq!(back.auth_flow.as_deref(), Some(crate::auth::TEAMS_WEB_FLOW));
        assert_eq!(
            crate::auth::AuthConfig::for_flow(back.auth_flow.as_deref()).client_id,
            crate::auth::spa::CLIENT_ID
        );
    }
}

#[cfg(test)]
mod storage_tests {
    use super::*;
    use std::cell::RefCell;

    /// A keyring that works, or one that refuses every call.
    struct FakeStore {
        working: bool,
        value: RefCell<Option<String>>,
    }

    impl FakeStore {
        fn new(working: bool) -> Self {
            Self {
                working,
                value: RefCell::new(None),
            }
        }
    }

    impl SecretStore for FakeStore {
        fn get(&self) -> std::result::Result<Option<String>, String> {
            if !self.working {
                return Err("no Secret Service".into());
            }
            Ok(self.value.borrow().clone())
        }
        fn set(&self, json: &str) -> std::result::Result<(), String> {
            if !self.working {
                return Err("no Secret Service".into());
            }
            *self.value.borrow_mut() = Some(json.to_string());
            Ok(())
        }
        fn delete(&self) -> std::result::Result<(), String> {
            *self.value.borrow_mut() = None;
            Ok(())
        }
    }

    fn signed_in() -> Config {
        Config {
            access_token: Some(StoredToken::new("aad-secret".into(), Some(3600))),
            refresh_token: Some("refresh-secret".into()),
            skype_token: Some(StoredToken::new("skype-secret".into(), Some(3600))),
            region_gtms: Some("{}".into()),
            ..Default::default()
        }
    }

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "ost-config-test-{name}-{}",
            uuid::Uuid::new_v4().simple()
        ));
        fs::create_dir_all(&d).unwrap();
        d.join("config.toml")
    }

    fn on_disk(path: &std::path::Path) -> String {
        fs::read_to_string(path).unwrap()
    }

    #[test]
    fn without_a_keyring_tokens_stay_in_memory_not_on_disk() {
        let path = dir("memory");
        let account = format!("test-memory-{}", uuid::Uuid::new_v4());
        let broken = FakeStore::new(false);
        signed_in()
            .save_to(&path, Some(&broken), false, &account)
            .unwrap();
        let text = on_disk(&path);
        assert!(!text.contains("secret"), "a token in the file");
        assert!(!text.contains("tokens_in_keyring"));
        // This run still has them.
        let back = Config::load_from(&path, Some(&broken), false, &account).unwrap();
        assert_eq!(back.refresh_token.as_deref(), Some("refresh-secret"));
        // A new run (memory gone) asks to sign in again.
        memory_set(&account, None);
        let fresh = Config::load_from(&path, Some(&broken), false, &account).unwrap();
        assert!(fresh.refresh_token.is_none() && fresh.access_token.is_none());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);
        }
    }

    #[test]
    fn with_a_keyring_the_file_holds_no_secrets() {
        let path = dir("keyring");
        let account = format!("test-keyring-{}", uuid::Uuid::new_v4());
        let store = FakeStore::new(true);
        signed_in()
            .save_to(&path, Some(&store), false, &account)
            .unwrap();
        let text = on_disk(&path);
        assert!(!text.contains("secret") && text.contains("tokens_in_keyring = true"));
        assert!(
            store
                .value
                .borrow()
                .as_deref()
                .unwrap()
                .contains("refresh-secret")
        );
        let back = Config::load_from(&path, Some(&store), false, &account).unwrap();
        assert_eq!(back.skype_token.unwrap().token, "skype-secret");
    }

    #[test]
    fn the_file_holds_tokens_only_when_opted_in() {
        let path = dir("optin");
        let account = format!("test-optin-{}", uuid::Uuid::new_v4());
        // OST_NO_KEYRING=1.
        signed_in().save_to(&path, None, true, &account).unwrap();
        assert!(on_disk(&path).contains("refresh-secret"));
        let back = Config::load_from(&path, None, true, &account).unwrap();
        assert_eq!(back.refresh_token.as_deref(), Some("refresh-secret"));
        // The setting, with a keyring that doesn't work.
        let path = dir("optin-setting");
        let mut c = signed_in();
        c.allow_token_file = true;
        c.save_to(&path, Some(&FakeStore::new(false)), false, &account)
            .unwrap();
        let text = on_disk(&path);
        assert!(text.contains("refresh-secret") && text.contains("allow_token_file = true"));
        // The opt-in is a fallback: a working keyring still gets them.
        let keyring_path = dir("optin-keyring");
        c.save_to(&keyring_path, Some(&FakeStore::new(true)), false, &account)
            .unwrap();
        assert!(!on_disk(&keyring_path).contains("secret"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);
        }
    }

    #[test]
    fn plaintext_tokens_move_to_the_keyring_once_it_works() {
        let path = dir("migrate");
        let account = format!("test-migrate-{}", uuid::Uuid::new_v4());
        // A file from OST 0.2.1, written when the keyring wasn't there.
        signed_in().save_to(&path, None, true, &account).unwrap();
        assert!(on_disk(&path).contains("refresh-secret"));
        let store = FakeStore::new(true);
        let c = Config::load_from(&path, Some(&store), false, &account).unwrap();
        assert_eq!(c.refresh_token.as_deref(), Some("refresh-secret"));
        let text = on_disk(&path);
        assert!(
            !text.contains("secret") && text.contains("tokens_in_keyring = true"),
            "the file still holds a token"
        );
        assert!(
            store
                .value
                .borrow()
                .as_deref()
                .unwrap()
                .contains("refresh-secret")
        );
        // Still no keyring: the plaintext copy goes all the same.
        let path = dir("migrate-nokeyring");
        signed_in().save_to(&path, None, true, &account).unwrap();
        let c = Config::load_from(&path, Some(&FakeStore::new(false)), false, &account).unwrap();
        assert_eq!(c.refresh_token.as_deref(), Some("refresh-secret"));
        assert!(!on_disk(&path).contains("secret"));
        memory_set(&account, None);
    }

    #[test]
    fn signing_out_forgets_the_memory_copy() {
        let path = dir("signout");
        let account = format!("test-signout-{}", uuid::Uuid::new_v4());
        let broken = FakeStore::new(false);
        signed_in()
            .save_to(&path, Some(&broken), false, &account)
            .unwrap();
        let mut c = Config::load_from(&path, Some(&broken), false, &account).unwrap();
        c.forget_account();
        c.save_to(&path, Some(&broken), false, &account).unwrap();
        assert!(memory_get(&account).is_none());
        let back = Config::load_from(&path, Some(&broken), false, &account).unwrap();
        assert!(back.refresh_token.is_none());
    }
}
