//! Teams' emoticons (personal expressions): the catalogue Teams downloads
//! from its CDN, and the images it draws reactions and emoji with.
//!
//! From the client code (async-entry 401251 `C`/`W`, 446619 sizes, 983508
//! base URL; metadata loader `loadEmoticonResourcesFromCDN`):
//! - metadata: `{statics}/evergreen-assets/personal-expressions/v1/metadata/{emoticonAssetVersion}/{locale}.json`;
//! - image: `{base}/{id}/default/{size}[_anim]_f[_s{tone+1}].png?v={etag}`.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Teams' statics host and the emoticon paths under it.
pub const STATICS: &str = "https://teams.public.onecdn.static.microsoft";
pub const ASSET_PATH: &str = "/evergreen-assets/personal-expressions/v2/assets/emoticons";
pub const METADATA_PATH: &str = "/evergreen-assets/personal-expressions/v1/metadata/";
/// The live `emoticonAssetVersion` (Messaging settings).
pub const ASSET_VERSION: &str = "ec4576179210cde40ce5494513213583";
/// Skin tones run 0 (none) to 5 (401251 `u`).
pub const MAX_TONE: u8 = 5;

/// One emoticon from the metadata.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Emoticon {
    pub id: String,
    pub description: String,
    #[serde(default)]
    pub shortcuts: Vec<String>,
    #[serde(default)]
    pub unicode: String,
    /// The image version (`?v=`).
    #[serde(default)]
    pub etag: String,
    /// Has skin tones.
    #[serde(default)]
    pub diverse: bool,
    #[serde(default)]
    pub keywords: Vec<String>,
}

/// A picker category.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub title: String,
    pub emoticons: Vec<Emoticon>,
}

#[derive(Debug, Deserialize)]
struct Metadata {
    categories: Vec<Category>,
}

/// The catalogue: categories in Teams' order, and every emoticon by id.
#[derive(Debug, Clone, Default)]
pub struct Catalog {
    pub categories: Vec<Category>,
    by_id: HashMap<String, Emoticon>,
}

impl Catalog {
    pub fn from_json(json: &[u8]) -> Result<Self> {
        let m: Metadata = serde_json::from_slice(json).context("emoticon metadata")?;
        let by_id = m
            .categories
            .iter()
            .flat_map(|c| c.emoticons.iter())
            .map(|e| (e.id.clone(), e.clone()))
            .collect();
        Ok(Self {
            categories: m.categories,
            by_id,
        })
    }

    pub fn get(&self, id: &str) -> Option<&Emoticon> {
        self.by_id.get(id)
    }

    /// A reaction's name as Teams shows it: the six classic ones by name,
    /// otherwise the emoticon's description (226455).
    pub fn reaction_name(&self, key: &str) -> String {
        let (id, _) = parse_key(key);
        match id.as_str() {
            "like" | "yes" => "Like".into(),
            "heart" => "Heart".into(),
            "laugh" => "Laugh".into(),
            "surprised" => "Surprised".into(),
            "sad" => "Sad".into(),
            "angry" => "Angry".into(),
            _ => self.get(&id).map(|e| e.description.clone()).unwrap_or(id),
        }
    }

    /// The emoji character for a key (for text and accessibility).
    pub fn unicode(&self, key: &str) -> String {
        let (id, _) = parse_key(key);
        self.get(asset_id(&id))
            .or_else(|| self.get(&id))
            .map(|e| e.unicode.clone())
            .unwrap_or_default()
    }

    /// The image URL for a key at `size` (one of Teams' asset sizes).
    pub fn image_url(&self, key: &str, size: u32, animated: bool) -> Option<String> {
        let (id, tone) = parse_key(key);
        let asset = asset_id(&id);
        let e = self.get(asset).or_else(|| self.get(&id))?;
        let tone = if tone > 0 {
            format!("_s{}", tone + 1)
        } else {
            String::new()
        };
        let anim = if animated { "_anim" } else { "" };
        let v = if e.etag.is_empty() {
            String::new()
        } else {
            format!("?v={}", e.etag)
        };
        Some(format!(
            "{STATICS}{ASSET_PATH}/{asset}/default/{size}{anim}_f{tone}.png{v}"
        ))
    }
}

/// Teams' quick reactions when the user has none set
/// (`defaultMessageReactions`, live and code default).
pub const DEFAULT_QUICK_REACTIONS: [&str; 4] = ["like", "heart", "laugh", "surprised"];

/// Teams' Recent emoticons before the user has any
/// (`recentReactions.defaultReactions`, live).
pub const DEFAULT_RECENT_REACTIONS: [&str; 36] = [
    "surprised",
    "cry",
    "angry",
    "hearteyes",
    "cool",
    "handsinair",
    "fistbump",
    "fire",
    "1f389_partypopper",
    "1f440_eyes",
    "1f4af_hundredpointssymbol",
    "1f4a1_electriclightbulb",
    "2714_heavycheckmark",
    "2795_heavyplussign",
    "2716_heavymultiplicationx",
    "1f51c_soon",
    "1f6a2_ship",
    "think",
    "1f97a_pleadingface",
    "loudlycrying",
    "giggle",
    "relieved",
    "whew",
    "1f4ce_paperclip",
    "upsidedownface",
    "smilingfacewithtear",
    "screamingfear",
    "speechless",
    "blankface",
    "stareyes",
    "1f92a_zanyface",
    "unamused",
    "party",
    "rofl",
    "highfive",
    "rock",
];

/// The Recent list after reacting with `key`: it moves to the front, and the
/// list keeps Teams' length.
pub fn note_recent(list: &[String], key: &str) -> Vec<String> {
    let (id, _) = parse_key(key);
    let mut out = vec![id.clone()];
    out.extend(list.iter().filter(|k| **k != id).cloned());
    out.truncate(DEFAULT_RECENT_REACTIONS.len());
    out
}

/// Roam the Recent list, as Teams writes it.
pub async fn set_recent_reactions(
    client: &super::client::TeamsClient,
    list: &[String],
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/properties?name=recentReactions",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "recentReactions": serde_json::to_string(list)? }),
        )
        .await?;
    Ok(())
}

/// Save the quick reactions (Teams' Customize: `updateUserPreferences`
/// category `defaultMessageReactions`, a JSON string of service keys).
pub async fn set_default_reactions(
    client: &super::client::TeamsClient,
    client_ids: &[String],
) -> Result<()> {
    let keys: Vec<&str> = client_ids.iter().map(|k| server_key(k)).collect();
    let url = format!(
        "{}/v1/users/ME/properties?name=defaultMessageReactions",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "defaultMessageReactions": serde_json::to_string(&keys)? }),
        )
        .await?;
    Ok(())
}

/// Save the preferred skin tone (category `preferredSkinToneIndex`, sent as
/// a string).
pub async fn set_skin_tone(client: &super::client::TeamsClient, tone: u8) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/properties?name=preferredSkinToneIndex",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "preferredSkinToneIndex": tone.min(MAX_TONE).to_string() }),
        )
        .await?;
    Ok(())
}

/// A reaction key's emoticon and skin tone: `like-tone2` → (`like`, 2)
/// (401251 `W`).
pub fn parse_key(key: &str) -> (String, u8) {
    if key.len() <= 40
        && let Some((id, tone)) = key.rsplit_once("-tone")
        && !id.is_empty()
        && !id.contains(char::is_whitespace)
        && let Ok(t) = tone.parse::<u8>()
    {
        return (id.to_string(), t.min(MAX_TONE));
    }
    (key.to_string(), 0)
}

/// The server's `like` is drawn with the `yes` asset.
/// Emoticon ids are Teams' client ids; the service keys three of them
/// differently (77708): its `like` is the client's `yes`, and the client's
/// `like` and `star` are `likeWithFaceMSER` and `starMSER` there.
fn asset_id(id: &str) -> &str {
    id
}

/// The client id of a service reaction key (77708 `$`).
pub fn client_key(key: &str) -> &str {
    match key {
        "like" => "yes",
        "likeWithFaceMSER" => "like",
        "starMSER" => "star",
        k => k,
    }
}

/// The service key of a client reaction id (77708 `a`).
pub fn server_key(key: &str) -> &str {
    match key {
        "like" => "likeWithFaceMSER",
        "star" => "starMSER",
        "yes" => "like",
        k => k,
    }
}

/// An emoticon in the user's preferred skin tone: `{id}-tone{n}` for one
/// with skin tones when a tone is set (Teams' `NM`).
pub fn with_tone(catalog: Option<&Catalog>, id: &str, tone: u8) -> String {
    let (base, _) = parse_key(id);
    let diverse = catalog
        .and_then(|c| c.get(&base))
        .is_some_and(|e| e.diverse);
    if diverse && tone > 0 {
        format!("{base}-tone{}", tone.min(MAX_TONE))
    } else {
        id.to_string()
    }
}

/// The quick reactions as the hover bar shows them: with a skin tone set,
/// Like becomes `yes-tone{n}` (547607 `x`); then the client ids.
pub fn quick_with_tone(list: &[String], tone: u8) -> Vec<String> {
    list.iter()
        .map(|k| {
            if tone > 0 && k == "like" {
                format!("yes-tone{}", tone.min(MAX_TONE))
            } else {
                client_key(k).to_string()
            }
        })
        .collect()
}

/// The user's reaction settings, from the roamed user properties: Recent,
/// the quick reactions and the preferred skin tone (0 for none).
pub struct ReactionPrefs {
    pub recent: Vec<String>,
    pub quick: Vec<String>,
    pub tone: u8,
}

impl ReactionPrefs {
    /// From the user properties object (`/v1/users/ME/properties`).
    pub fn from_properties(v: &serde_json::Value) -> Self {
        let list = |name: &str| {
            v.get(name)
                .and_then(|r| r.as_str())
                .and_then(|s| serde_json::from_str::<Vec<String>>(s).ok())
                .filter(|l| !l.is_empty())
        };
        let owned = |l: &[&str]| l.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let tone = v
            .get("preferredSkinToneIndex")
            .and_then(|t| t.as_u64().or_else(|| t.as_str()?.trim().parse().ok()))
            .filter(|t| *t <= MAX_TONE as u64)
            .unwrap_or(0) as u8;
        let quick =
            list("defaultMessageReactions").unwrap_or_else(|| owned(&DEFAULT_QUICK_REACTIONS));
        Self {
            recent: list("recentReactions").unwrap_or_else(|| owned(&DEFAULT_RECENT_REACTIONS)),
            quick: quick_with_tone(&quick, tone),
            tone,
        }
    }
}

/// The user's reaction settings, or Teams' defaults when unreadable.
pub async fn reaction_prefs(client: &super::client::TeamsClient) -> ReactionPrefs {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v = match client.chat_get(&url).await {
        Ok(r) => r.json::<serde_json::Value>().await.unwrap_or_default(),
        Err(_) => serde_json::Value::Null,
    };
    ReactionPrefs::from_properties(&v)
}

/// Teams' named emoticon sizes and their asset sizes, normal and hi-DPI
/// (401251 `b`, 446619): the hover bar's reactions are "medium".
pub fn asset_size(named: &str, hidpi: bool) -> u32 {
    match (named, hidpi) {
        ("extra-large", _) => 100,
        ("large", false) => 50,
        ("large", true) => 100,
        ("medium", false) => 30,
        ("medium", true) => 60,
        ("medium-large", false) => 40,
        ("medium-large", true) => 100,
        ("extra-small", false) => 16,
        ("extra-small", true) => 20,
        (_, false) => 20,
        (_, true) => 50,
    }
}

/// The catalogue, downloaded once and kept in `cache_dir`.
pub async fn load_catalog(cache_dir: &Path, locale: &str) -> Result<Catalog> {
    let file = cache_dir.join(format!("emoticons-{ASSET_VERSION}-{locale}.json"));
    if let Ok(b) = std::fs::read(&file)
        && let Ok(c) = Catalog::from_json(&b)
    {
        return Ok(c);
    }
    let url = format!("{STATICS}{METADATA_PATH}{ASSET_VERSION}/{locale}.json");
    let bytes = reqwest::get(&url)
        .await
        .context("emoticon metadata request")?
        .error_for_status()
        .context("emoticon metadata")?
        .bytes()
        .await?;
    let catalog = Catalog::from_json(&bytes)?;
    std::fs::create_dir_all(cache_dir)?;
    std::fs::write(&file, &bytes)?;
    Ok(catalog)
}

/// An emoticon image on disk, downloading it the first time.
pub async fn image_file(url: &str, cache_dir: &Path) -> Result<PathBuf> {
    let name: String = url
        .trim_start_matches(&format!("{STATICS}{ASSET_PATH}/"))
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let path = cache_dir.join("emoticons").join(name);
    if path.exists() {
        return Ok(path);
    }
    let bytes = reqwest::get(url).await?.error_for_status()?.bytes().await?;
    std::fs::create_dir_all(path.parent().unwrap_or(cache_dir))?;
    let tmp = path.with_extension("part");
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &path)?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn catalog() -> Catalog {
        Catalog::from_json(
            br#"{"categories":[{"id":"c1","title":"Smilies","emoticons":[
                {"id":"yes","description":"Yes","unicode":"+1","etag":"v70","diverse":true},
                {"id":"like","description":"Like","unicode":"+1","etag":"v37","diverse":true},
                {"id":"heart","description":"Heart","unicode":"<3","etag":"v34"},
                {"id":"1f603_grinningfacewithbigeyes","description":"Grinning face with big eyes","etag":"v11"}]}]}"#,
        )
        .unwrap()
    }

    #[test]
    fn keys_and_urls_are_teams() {
        assert_eq!(parse_key("like-tone2"), ("like".into(), 2));
        assert_eq!(client_key("like"), "yes");
        assert_eq!(server_key("yes"), "like");
        assert_eq!(server_key("like"), "likeWithFaceMSER");
        assert_eq!(client_key("yes-tone2"), "yes-tone2");
        assert_eq!(parse_key("heart"), ("heart".into(), 0));
        assert_eq!(parse_key("x-tone9"), ("x".into(), 5));
        let c = catalog();
        assert_eq!(
            c.image_url("yes", 60, false).unwrap(),
            "https://teams.public.onecdn.static.microsoft/evergreen-assets/personal-expressions/v2/assets/emoticons/yes/default/60_f.png?v=v70"
        );
        assert_eq!(
            c.image_url("like", 60, false).unwrap(),
            "https://teams.public.onecdn.static.microsoft/evergreen-assets/personal-expressions/v2/assets/emoticons/like/default/60_f.png?v=v37"
        );
        assert_eq!(
            c.image_url("yes-tone2", 30, true).unwrap(),
            "https://teams.public.onecdn.static.microsoft/evergreen-assets/personal-expressions/v2/assets/emoticons/yes/default/30_anim_f_s3.png?v=v70"
        );
        assert!(c.image_url("nope", 30, false).is_none());
        assert_eq!(with_tone(Some(&c), "yes", 3), "yes-tone3");
        assert_eq!(with_tone(Some(&c), "yes", 0), "yes");
        let p = ReactionPrefs::from_properties(&serde_json::json!({"preferredSkinToneIndex": "2"}));
        assert_eq!(p.tone, 2);
        assert_eq!(p.quick, vec!["yes-tone2", "heart", "laugh", "surprised"]);
        let p = ReactionPrefs::from_properties(&serde_json::Value::Null);
        assert_eq!(p.quick, vec!["yes", "heart", "laugh", "surprised"]);
        assert_eq!(c.reaction_name("like-tone1"), "Like");
        assert_eq!(
            c.reaction_name("1f603_grinningfacewithbigeyes"),
            "Grinning face with big eyes"
        );
        assert_eq!(asset_size("medium", true), 60);
        assert_eq!(asset_size("medium", false), 30);
        assert_eq!(asset_size("small", false), 20);
        let base: Vec<String> = DEFAULT_RECENT_REACTIONS
            .iter()
            .map(|s| s.to_string())
            .collect();
        let r = note_recent(&base, "fire");
        assert_eq!(
            (r[0].as_str(), r[1].as_str(), r.len()),
            ("fire", "surprised", 36)
        );
        let r = note_recent(&base, "like-tone2");
        assert_eq!(
            (r[0].as_str(), r.len(), r.last().unwrap().as_str()),
            ("like", 36, "highfive")
        );
    }
}
