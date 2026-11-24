//! OST's update check (Settings ▸ About OST, as Teams' "You've got the latest
//! version"): OST is released on GitHub (the project's releases); the
//! latest published release is the newest version.

use anyhow::{Context, Result};

/// Where OST is released.
pub const REPOSITORY: &str = "RandyNorthrup/ost";

/// The newest release: its version (without a leading "v") and its page.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Release {
    pub version: String,
    pub url: String,
}

/// The latest published release, or None when there is none yet.
pub async fn latest_release(http: &reqwest::Client) -> Result<Option<Release>> {
    let r = http
        .get(format!("https://api.github.com/repos/{REPOSITORY}/releases/latest"))
        .header("Accept", "application/vnd.github+json")
        .header("User-Agent", concat!("ost/", env!("CARGO_PKG_VERSION")))
        .send()
        .await
        .context("update check")?;
    // What the check tells GitHub about this copy (View Diagnostic Data).
    super::ddv::record(
        "Ost.UpdateCheck",
        serde_json::json!({
            "url": format!("https://api.github.com/repos/{REPOSITORY}/releases/latest"),
            "userAgent": concat!("ost/", env!("CARGO_PKG_VERSION")),
            "status": r.status().as_u16(),
        }),
    );
    if r.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    let v: serde_json::Value = r.error_for_status().context("update check")?.json().await?;
    let tag = v["tag_name"].as_str().unwrap_or_default();
    Ok(Some(Release {
        version: tag.trim_start_matches(['v', 'V']).to_string(),
        url: v["html_url"].as_str().unwrap_or_default().to_string(),
    }))
}

/// The newest release including pre-releases (OST's public preview: Settings
/// ▸ About OST ▸ Early access ▸ Public preview, as Teams' desktop host offers
/// its preview builds where the update policy allows them).
pub async fn latest_preview_release(http: &reqwest::Client) -> Result<Option<Release>> {
    let url = format!("https://api.github.com/repos/{REPOSITORY}/releases?per_page=10");
    let r = http
        .get(&url)
        .header("Accept", "application/vnd.github+json")
        .header("User-Agent", concat!("ost/", env!("CARGO_PKG_VERSION")))
        .send()
        .await
        .context("update check")?;
    super::ddv::record("Ost.UpdateCheck", serde_json::json!({ "url": url, "userAgent": concat!("ost/", env!("CARGO_PKG_VERSION")), "status": r.status().as_u16() }));
    if r.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    let v: serde_json::Value = r.error_for_status().context("update check")?.json().await?;
    Ok(newest_published(&v))
}

/// The first release in GitHub's list (newest first) that isn't a draft.
pub fn newest_published(list: &serde_json::Value) -> Option<Release> {
    list.as_array()?.iter().find(|r| r["draft"].as_bool() != Some(true)).map(|r| Release {
        version: r["tag_name"].as_str().unwrap_or_default().trim_start_matches(['v', 'V']).to_string(),
        url: r["html_url"].as_str().unwrap_or_default().to_string(),
    })
}

/// Whether the effective Teams update policy lets you opt in to public
/// preview (teamsUpdateManagementPolicy.allowPublicPreview: Enabled,
/// Forced or FollowOfficePreview; Disabled or none: no).
pub fn public_preview_allowed(policies: &serde_json::Value) -> bool {
    matches!(
        policies.pointer("/teamsUpdateManagementPolicy/value/allowPublicPreview").and_then(|v| v.as_str()),
        Some("Enabled" | "Forced" | "FollowOfficePreview")
    )
}

/// Whether `latest` is newer than `current` (dotted numbers; a
/// pre-release suffix counts as older than the plain version).
pub fn is_newer(latest: &str, current: &str) -> bool {
    fn parts(v: &str) -> (Vec<u64>, bool) {
        let (core, pre) = match v.split_once('-') {
            Some((c, _)) => (c, true),
            None => (v, false),
        };
        (core.split('.').map(|p| p.parse().unwrap_or(0)).collect(), pre)
    }
    let ((a, a_pre), (b, b_pre)) = (parts(latest), parts(current));
    let n = a.len().max(b.len());
    for i in 0..n {
        let (x, y) = (a.get(i).copied().unwrap_or(0), b.get(i).copied().unwrap_or(0));
        if x != y {
            return x > y;
        }
    }
    !a_pre && b_pre
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_as_numbers() {
        assert!(is_newer("0.2.0", "0.1.0"));
        assert!(is_newer("0.10.0", "0.9.9"));
        assert!(!is_newer("0.1.0", "0.1.0"));
        assert!(!is_newer("0.1.0", "0.2.0"));
        assert!(is_newer("0.1.0", "0.1.0-dev"));
        assert!(!is_newer("0.1.0-dev", "0.1.0"));
    }

    #[test]
    fn preview_channel() {
        let list = serde_json::json!([{ "tag_name": "v0.2.0-preview.1", "html_url": "u1", "draft": true }, { "tag_name": "v0.2.0-preview.0", "html_url": "u2", "prerelease": true }]);
        assert_eq!(newest_published(&list), Some(Release { version: "0.2.0-preview.0".into(), url: "u2".into() }));
        assert!(public_preview_allowed(&serde_json::json!({ "teamsUpdateManagementPolicy": { "value": { "allowPublicPreview": "Enabled" } } })));
        assert!(!public_preview_allowed(&serde_json::json!({ "teamsUpdateManagementPolicy": { "value": { "allowPublicPreview": "Disabled" } } })));
    }
}
