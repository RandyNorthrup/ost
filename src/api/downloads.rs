//! OST's download history: what Settings and more ▸ Downloads lists (Teams
//! shows WebView2's downloads hub there: each file with Open file, Open
//! containing folder and Delete file, a removed one struck through). Every
//! file OST saves into the Downloads folder is recorded here, newest first,
//! in `$XDG_STATE_HOME/ost/downloads.json` (else ~/.local/state).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// One download.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Download {
    pub path: String,
    pub name: String,
    /// When it finished (Unix milliseconds).
    pub at: i64,
}

/// A download as the list shows it: whether the file is still there.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Listed {
    #[serde(flatten)]
    pub download: Download,
    pub exists: bool,
}

/// How many downloads are kept.
const KEEP: usize = 200;

fn history_path() -> Option<PathBuf> {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local").join("state")))
        .map(|b| b.join("ost").join("downloads.json"))
}

fn load_from(file: &Path) -> Vec<Download> {
    std::fs::read(file)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

fn save_to(file: &Path, all: &[Download]) -> Result<()> {
    std::fs::create_dir_all(file.parent().context("History folder")?)?;
    std::fs::write(file, serde_json::to_vec(all)?)?;
    Ok(())
}

/// Add a download (newest first; one entry per path).
pub fn record_in(file: &Path, path: &Path, at: i64) -> Result<()> {
    let mut all = load_from(file);
    let p = path.display().to_string();
    all.retain(|d| d.path != p);
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default()
        .to_string();
    all.insert(0, Download { path: p, name, at });
    all.truncate(KEEP);
    save_to(file, &all)
}

/// Record a file OST saved as a download. Failures are only logged.
pub fn record(path: &Path) {
    let Some(file) = history_path() else { return };
    if let Err(e) = record_in(&file, path, crate::clock::now_ms()) {
        tracing::warn!("download history: {e:#}");
    }
}

/// The downloads, newest first, with whether each file still exists.
pub fn list() -> Vec<Listed> {
    history_path()
        .map(|f| load_from(&f))
        .unwrap_or_default()
        .into_iter()
        .map(|d| {
            let exists = Path::new(&d.path).is_file();
            Listed {
                download: d,
                exists,
            }
        })
        .collect()
}

/// Delete file: remove the file itself (the entry stays, shown as removed).
pub fn delete_file(path: &str) -> Result<()> {
    anyhow::ensure!(
        list().iter().any(|d| d.download.path == path),
        "Not a download"
    );
    std::fs::remove_file(path).with_context(|| format!("Deleting {path}"))
}

/// Clear all download history (the files stay).
pub fn clear() -> Result<()> {
    let Some(file) = history_path() else {
        return Ok(());
    };
    save_to(&file, &[])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn history_keeps_newest_first_and_one_entry_per_path() {
        let dir = std::env::temp_dir().join(format!("ost-dl-{}", std::process::id()));
        let file = dir.join("downloads.json");
        record_in(&file, Path::new("/tmp/a.txt"), 1).unwrap();
        record_in(&file, Path::new("/tmp/b.txt"), 2).unwrap();
        record_in(&file, Path::new("/tmp/a.txt"), 3).unwrap();
        let all = load_from(&file);
        assert_eq!(
            all.iter().map(|d| d.name.as_str()).collect::<Vec<_>>(),
            ["a.txt", "b.txt"]
        );
        assert_eq!(all[0].at, 3);
        let _ = std::fs::remove_dir_all(dir);
    }
}
