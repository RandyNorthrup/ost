//! The one gate for links OST hands to the desktop (issue #34).
//!
//! Links come from content other people control: cards from bots,
//! webhooks, Workflows and connectors, message HTML, app manifests, tenant
//! settings. Teams opens only web, mail and phone links from them (its
//! card and message sanitizers drop every other scheme), so OST hands the
//! desktop the same four schemes and refuses the rest, `file:`, `smb:`,
//! `sftp:`, `davs:` and other apps' custom handlers among them. OST's own
//! internal links (`ost:`, `mention:` and the like) are handled in QML and
//! never leave the app.
//!
//! Local files OST itself saved (downloads, printed pages, feedback
//! details) open through [`local_path`], which takes a path, never a URL
//! from content.

use std::path::{Path, PathBuf};

/// How an allowed link opens.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkKind {
    /// http(s): in the browser chosen in Settings ▸ Files and links.
    Web,
    /// mailto: and tel: — the desktop's mail or phone app.
    System,
}

/// The schemes OST opens outside the app.
pub const ALLOWED_SCHEMES: [&str; 4] = ["https", "http", "mailto", "tel"];

/// A URL's scheme (RFC 3986: a letter, then letters, digits, `+`, `-`,
/// `.`), lower-cased; None when the text has none.
pub fn scheme(url: &str) -> Option<String> {
    let (s, _) = url.split_once(':')?;
    let mut chars = s.chars();
    let first = chars.next()?;
    if !first.is_ascii_alphabetic()
        || !chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
    {
        return None;
    }
    Some(s.to_ascii_lowercase())
}

/// Whether OST may open this link outside the app, and how. Web links need
/// `//` and a host; mail and phone links something after the colon. Text
/// with whitespace or control characters around or inside the scheme is
/// refused rather than guessed at.
pub fn classify(url: &str) -> Option<LinkKind> {
    if url.is_empty() || url.chars().any(|c| c.is_control()) {
        return None;
    }
    let scheme = scheme(url)?;
    let rest = &url[scheme.len() + 1..];
    match scheme.as_str() {
        "https" | "http" => {
            let host = rest.strip_prefix("//")?;
            let host = host.split(['/', '?', '#']).next().unwrap_or("");
            let host = host.rsplit('@').next().unwrap_or("");
            (!host.is_empty() && !host.chars().any(char::is_whitespace)).then_some(LinkKind::Web)
        }
        "mailto" | "tel" => (!rest.trim().is_empty()).then_some(LinkKind::System),
        _ => None,
    }
}

/// A link from content (a card's markdown, a RichTextBlock's
/// selectAction, an app's manifest) as the value of an HTML `href="…"`:
/// escaped so it can't close the attribute or open a tag, and empty when
/// OST wouldn't open it, so the text shows without a link (as Teams'
/// sanitizer leaves it). `url` is plain text, not HTML.
pub fn link_href(url: &str) -> String {
    let url = url.trim();
    if classify(url).is_none() {
        return String::new();
    }
    let mut out = String::with_capacity(url.len());
    for c in url.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            c => out.push(c),
        }
    }
    out
}

/// What a refusal logs: the scheme only (the rest may be personal or long).
pub fn refusal_note(url: &str) -> String {
    match scheme(url) {
        Some(s) => format!("refused a {s}: link"),
        None => "refused a link without a scheme".to_string(),
    }
}

/// A local file or folder OST saved, as a path or a `file://` URL: the
/// absolute path when it names something that exists, else None.
pub fn local_path(path_or_url: &str) -> Option<PathBuf> {
    let found = |p: &str| {
        let path = Path::new(p);
        (path.is_absolute() && path.exists()).then(|| path.to_path_buf())
    };
    match path_or_url.strip_prefix("file://") {
        // OST builds some of these by hand ("file://" + path), so a path
        // that isn't percent-encoded is taken as it is.
        Some(rest) => percent_decode(rest)
            .and_then(|p| found(&p))
            .or_else(|| found(rest)),
        None => found(path_or_url),
    }
}

fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// The schemes this desktop would hand to some app (xdg-open's
/// `x-scheme-handler/<scheme>` associations in mimeapps.list,
/// mimeinfo.cache and .desktop files), plus the file and network-share
/// schemes file managers open themselves. OST installs a refusing handler
/// for each one it doesn't open (native.cpp), so nothing that reaches Qt's
/// QDesktopServices directly (a web view's external link, a stray call)
/// starts them either.
pub fn desktop_schemes() -> Vec<String> {
    // GIO's and KIO's own: files, shares, and their virtual places.
    const BUILT_IN: &str = "file smb cifs sftp ssh fish ftp ftps dav davs webdav webdavs nfs \
                            afp mtp admin trash recent network computer burn archive \
                            google-drive onedrive zip tar man help info ghelp settings";
    let mut out: Vec<String> = BUILT_IN.split_whitespace().map(str::to_string).collect();
    for file in mime_association_files() {
        if let Ok(text) = std::fs::read_to_string(&file) {
            out.extend(schemes_in(&text));
        }
    }
    out.sort();
    out.dedup();
    out.retain(|s| !ALLOWED_SCHEMES.contains(&s.as_str()));
    out
}

/// `x-scheme-handler/<scheme>` names in a mimeapps.list, mimeinfo.cache or
/// .desktop file.
pub fn schemes_in(text: &str) -> Vec<String> {
    const KEY: &str = "x-scheme-handler/";
    let mut out = Vec::new();
    let lower = text.to_ascii_lowercase();
    let mut at = 0;
    while let Some(i) = lower[at..].find(KEY) {
        let start = at + i + KEY.len();
        let end = lower[start..]
            .find(|c: char| !(c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.')))
            .map_or(lower.len(), |e| start + e);
        let s = &lower[start..end];
        if s.chars().next().is_some_and(|c| c.is_ascii_alphabetic()) {
            out.push(s.to_string());
        }
        at = end;
    }
    out
}

fn mime_association_files() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|h| h.join(".config")));
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|h| h.join(".local/share")));
    let data_dirs = std::env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".to_string());
    let mut files = Vec::new();
    if let Some(c) = config {
        files.push(c.join("mimeapps.list"));
    }
    let mut apps: Vec<PathBuf> = data_home
        .into_iter()
        .map(|d| d.join("applications"))
        .collect();
    apps.extend(std::env::split_paths(&data_dirs).map(|d| d.join("applications")));
    for dir in apps {
        files.push(dir.join("mimeapps.list"));
        files.push(dir.join("mimeinfo.cache"));
        // .desktop files not yet in a mimeinfo.cache (a user's own).
        if let Ok(entries) = std::fs::read_dir(&dir) {
            files.extend(
                entries
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.extension().is_some_and(|e| e == "desktop")),
            );
        }
    }
    files
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn web_mail_and_phone_links_open() {
        assert_eq!(classify("https://example.com/a?b#c"), Some(LinkKind::Web));
        assert_eq!(classify("HTTP://Example.com"), Some(LinkKind::Web));
        assert_eq!(classify("https://user@example.com/"), Some(LinkKind::Web));
        assert_eq!(
            classify("mailto:someone@example.com?subject=Hi"),
            Some(LinkKind::System)
        );
        assert_eq!(
            classify("MAILTO:someone@example.com"),
            Some(LinkKind::System)
        );
        assert_eq!(classify("tel:+15551234567"), Some(LinkKind::System));
    }

    #[test]
    fn every_other_scheme_is_refused() {
        for url in [
            "file:///etc/passwd",
            "file://host/share/x.desktop",
            "smb://attacker.example/share",
            "sftp://attacker.example/",
            "davs://attacker.example/dav",
            "ftp://example.com/",
            "javascript:alert(1)",
            "data:text/html,<b>x</b>",
            "vscode://file/etc/passwd",
            "steam://run/1",
            "ms-word:ofe|u|https://example.com/a.docx",
            "msteams://teams.microsoft.com/l/chat/0/0",
            "ost:notes-tab",
            "mention:8:orgid:x",
        ] {
            assert_eq!(classify(url), None, "{url}");
        }
    }

    #[test]
    fn malformed_links_are_refused() {
        for url in [
            "",
            "example.com",
            "/etc/passwd",
            "-https://example.com",
            " https://example.com",
            "https:example.com",
            "https:/example.com",
            "https://",
            "https:///path",
            "https://user@/x",
            "https://exa mple.com/",
            "https://example.com/\nfile:///x",
            "mailto:",
            "tel: ",
            "1https://example.com",
        ] {
            assert_eq!(classify(url), None, "{url:?}");
        }
    }

    #[test]
    fn refusals_log_only_the_scheme() {
        assert_eq!(
            refusal_note("smb://host/secret-share"),
            "refused a smb: link"
        );
        assert_eq!(refusal_note("FILE:///home/me"), "refused a file: link");
        assert_eq!(refusal_note("no scheme"), "refused a link without a scheme");
    }

    #[test]
    fn local_paths_must_be_absolute_and_exist() {
        let dir = std::env::temp_dir();
        let d = dir.display().to_string();
        assert_eq!(local_path(&d), Some(dir.clone()));
        assert_eq!(local_path(&format!("file://{d}")), Some(dir.clone()));
        assert_eq!(local_path("relative/path"), None);
        assert_eq!(local_path("/no/such/ost/path/at/all"), None);
        assert_eq!(local_path("smb://host/share"), None);
        assert_eq!(local_path("file://%zz"), None);
        let spaced = dir.join("ost link gate test");
        std::fs::create_dir_all(&spaced).unwrap();
        assert_eq!(
            local_path(&format!("file://{}", spaced.display()).replace(' ', "%20")),
            Some(spaced.clone())
        );
        std::fs::remove_dir(&spaced).unwrap();
    }

    /// QML never hands a link to Qt directly: every one goes through
    /// backend.openExternal (or openLocalPath for OST's own files).
    #[test]
    fn qml_opens_links_only_through_the_gate() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("qml");
        let mut checked = 0;
        for entry in std::fs::read_dir(&dir).unwrap().flatten() {
            let path = entry.path();
            if !path.extension().is_some_and(|e| e == "qml" || e == "js") {
                continue;
            }
            let text = std::fs::read_to_string(&path).unwrap();
            for (n, line) in text.lines().enumerate() {
                assert!(
                    !line.contains("openUrlExternally"),
                    "{}:{}: use backend.openExternal",
                    path.display(),
                    n + 1
                );
            }
            checked += 1;
        }
        assert!(checked > 100, "only {checked} QML files found");
    }

    #[test]
    fn hrefs_are_escaped_and_only_for_links_that_open() {
        assert_eq!(
            link_href(" https://example.com/a?b=1&c=2 "),
            "https://example.com/a?b=1&amp;c=2"
        );
        // A selectAction url that tries to close the attribute and add
        // markup (a remote image that loads when the card is only viewed).
        assert_eq!(
            link_href("https://example.com/\"><img src=\"https://evil.example/x.png\">"),
            "https://example.com/&quot;&gt;&lt;img src=&quot;https://evil.example/x.png&quot;&gt;"
        );
        assert_eq!(
            link_href("https://example.com/'x'"),
            "https://example.com/&#39;x&#39;"
        );
        assert_eq!(link_href("mailto:a@example.com"), "mailto:a@example.com");
        assert_eq!(link_href("tel:+15551234567"), "tel:+15551234567");
        for refused in [
            "file:///etc/passwd",
            "smb://attacker.example/share",
            "javascript:alert(1)",
            "\"><img src=x>",
            "",
        ] {
            assert_eq!(link_href(refused), "", "{refused}");
        }
    }

    /// Card markup builds every href from link_href.
    #[test]
    fn card_markup_takes_hrefs_from_the_gate() {
        let qml = |f: &str| {
            std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("qml").join(f))
                .unwrap()
        };
        let card = qml("AdaptiveCard.qml");
        assert!(card.contains("backend.linkHref(String(url))"));
        assert!(card.contains("card.href(r.selectAction.url)"));
        assert!(card.contains("card.href(url)"));
        assert!(!card.contains("r.selectAction.url + "));
        assert!(!card.contains("<a href=\"$2\""));
        let connector = qml("ConnectorCard.qml");
        assert!(connector.contains("htmlBlocks(cleanHtml(t))"));
        assert!(connector.contains("backend.linkHref(url)"));
        assert!(qml("AppDetailsDialog.qml").contains("backend.linkHref(String(u))"));
    }

    #[test]
    fn scheme_handlers_are_read_from_mime_files() {
        let text = "[Default Applications]\nx-scheme-handler/http=firefox.desktop\n\
                    x-scheme-handler/zoommtg=Zoom.desktop\nMimeType=x-scheme-handler/sgnl;\
                    X-Scheme-Handler/Vscode;text/plain;x-scheme-handler/;\n";
        assert_eq!(schemes_in(text), ["http", "zoommtg", "sgnl", "vscode"]);
        let all = desktop_schemes();
        assert!(all.iter().any(|s| s == "file") && all.iter().any(|s| s == "smb"));
        assert!(!all.iter().any(|s| ALLOWED_SCHEMES.contains(&s.as_str())));
    }
}
