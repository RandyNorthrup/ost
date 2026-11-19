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
    use super::is_newer;

    #[test]
    fn versions_compare_as_numbers() {
        assert!(is_newer("0.2.0", "0.1.0"));
        assert!(is_newer("0.10.0", "0.9.9"));
        assert!(!is_newer("0.1.0", "0.1.0"));
        assert!(!is_newer("0.1.0", "0.2.0"));
        assert!(is_newer("0.1.0", "0.1.0-dev"));
        assert!(!is_newer("0.1.0-dev", "0.1.0"));
    }
}
