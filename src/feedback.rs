//! Feedback and help to OST's GitHub repo in Microsoft's place (Teams' Report
//! a problem, Give a compliment and Suggest a feature; spec
//! docs/spec/feedback-and-help.md). OST never posts anything: it opens the
//! repo's issue form filled in and the reporter submits it on GitHub.

/// The repo feedback and help go to ("owner/name"); a build can set
/// `OST_FEEDBACK_REPO` (an upstream port points it at its own repo).
pub fn repo() -> &'static str {
    match option_env!("OST_FEEDBACK_REPO") {
        Some(r) if !r.is_empty() => r,
        _ => "RandyNorthrup/ost",
    }
}

/// The repo's address.
pub fn repo_url() -> String {
    format!("https://github.com/{}", repo())
}

/// Feedback ▸ Suggest a feature: the repo's Discussions ▸ Ideas.
pub fn ideas_url() -> String {
    format!("{}/discussions/categories/ideas", repo_url())
}

/// The privacy statement, and its section on what feedback shares.
pub fn privacy_url(section: &str) -> String {
    let anchor = if section.is_empty() { String::new() } else { format!("#{section}") };
    format!("{}/blob/main/PRIVACY.md{anchor}", repo_url())
}

/// What the form holds.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct Report {
    /// "problem" (Report a problem) or "compliment" (Give a compliment).
    pub kind: String,
    /// What did you dislike? / What did you like?
    pub text: String,
    /// Where in OST it was sent from ("Settings and more", "Find in chat").
    pub area: String,
    /// What OST fills in about that place (a search's words and results).
    pub context: String,
    /// Share relevant content samples and additional log files?
    pub share_logs: bool,
    /// May we contact you about your feedback?
    pub contact: bool,
    /// Files added (screenshots and attachments); named in the details.
    pub files: Vec<String>,
}

/// GitHub keeps new-issue URLs to about 8 KB; the logs fill what's left.
const URL_BUDGET: usize = 7600;

/// The issue's title: "Problem: " / "Compliment: " and the text's first line.
pub fn title(r: &Report) -> String {
    let lead = if r.kind == "compliment" { "Compliment" } else { "Problem" };
    let first = r.text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or_default();
    let mut t: String = first.chars().take(80).collect();
    if first.chars().count() > 80 {
        t.push('…');
    }
    format!("{lead}: {t}")
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// The new-issue address with the form filled in; `logs` are the masked
/// log lines (used only when the reporter chose to share them).
pub fn issue_url(r: &Report, version: &str, os: &str, logs: &str) -> String {
    let template = if r.kind == "compliment" { "give-a-compliment.yml" } else { "report-a-problem.yml" };
    let mut details = r.context.clone();
    if !r.files.is_empty() {
        if !details.is_empty() {
            details.push_str("\n\n");
        }
        details.push_str("Screenshots and files: paste or drop them here (OST put the first on the clipboard).\n");
        for f in &r.files {
            let name = std::path::Path::new(f).file_name().and_then(|n| n.to_str()).unwrap_or(f);
            details.push_str(&format!("- {name}\n"));
        }
    }
    let contact = if r.contact { "Yes, you may contact me" } else { "No, don't contact me" };
    let fields = [
        ("template", template.to_string()),
        ("title", title(r)),
        ("what", r.text.clone()),
        ("details", details),
        ("contact", contact.to_string()),
        ("area", r.area.clone()),
        ("version", version.to_string()),
        ("os", os.to_string()),
    ];
    let mut url = format!("{}/issues/new?", repo_url());
    url.push_str(&fields.iter().filter(|(_, v)| !v.is_empty()).map(|(k, v)| format!("{k}={}", enc(v))).collect::<Vec<_>>().join("&"));
    if r.share_logs && !logs.is_empty() {
        // The newest lines, as many as fit.
        let room = URL_BUDGET.saturating_sub(url.len() + 6);
        let mut kept: Vec<&str> = Vec::new();
        let mut used = 0;
        for line in logs.lines().rev() {
            let cost = enc(line).len() + 3;
            if used + cost > room {
                break;
            }
            used += cost;
            kept.push(line);
        }
        kept.reverse();
        if !kept.is_empty() {
            url.push_str("&logs=");
            url.push_str(&enc(&kept.join("\n")));
        }
    }
    url
}

/// A log line with what could identify people taken out: quoted values
/// (names, message text, titles), e-mail addresses, phone numbers, ids
/// (GUIDs, MRIs, thread ids), tokens and URL queries.
pub fn mask_line(line: &str) -> String {
    use std::sync::OnceLock;
    static RES: OnceLock<Vec<(regex::Regex, &'static str)>> = OnceLock::new();
    let res = RES.get_or_init(|| {
        [
            (r#""(?:[^"\\]|\\.)*""#, "\"…\""),
            (r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer …"),
            (r"eyJ[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]+)*", "<token>"),
            (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<email>"),
            (r"\b(?:8|28|29|48):[A-Za-z0-9:._-]+", "<mri>"),
            (r"19:[A-Za-z0-9_.@=-]+", "<thread>"),
            (r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "<id>"),
            (r"(https?://[^\s?#]+)\?[^\s#]*", "$1?…"),
            (r"\+\d[\d\s().-]{7,}\d|\(\d{3}\)\s?\d{3}[-.\s]\d{4}|\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b", "<number>"),
        ]
        .into_iter()
        .map(|(p, r)| (regex::Regex::new(p).expect("mask pattern"), r))
        .collect()
    });
    let mut out = line.to_string();
    for (re, with) in res {
        out = re.replace_all(&out, *with).into_owned();
    }
    out
}

/// The newest `n` lines of a log, masked.
pub fn masked_tail(log: &str, n: usize) -> String {
    let lines: Vec<&str> = log.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].iter().map(|l| mask_line(l)).collect::<Vec<_>>().join("\n")
}

/// The operating system as the issue names it (os-release's PRETTY_NAME).
pub fn os_name() -> String {
    let pretty = std::fs::read_to_string("/etc/os-release").ok().and_then(|s| {
        s.lines()
            .find_map(|l| l.strip_prefix("PRETTY_NAME="))
            .map(|v| v.trim_matches('"').to_string())
    });
    let base = pretty.unwrap_or_else(|| std::env::consts::OS.to_string());
    format!("{base} ({})", std::env::consts::ARCH)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report() -> Report {
        Report { kind: "problem".into(), text: "Search shows nothing\nsecond line".into(), area: "Find in chat".into(), contact: true, ..Default::default() }
    }

    #[test]
    fn the_issue_form_is_filled_in() {
        let u = issue_url(&report(), "0.1.0", "Arch Linux (x86_64)", "");
        assert!(u.starts_with("https://github.com/RandyNorthrup/ost/issues/new?template=report-a-problem.yml&title=Problem%3A+Search+shows+nothing&what=Search+shows+nothing%0Asecond+line"), "{u}");
        assert!(u.contains("&contact=Yes%2C+you+may+contact+me"));
        assert!(u.contains("&area=Find+in+chat&version=0.1.0&os=Arch+Linux+%28x86_64%29"));
        assert!(!u.contains("logs="), "logs only when shared");
        let c = Report { kind: "compliment".into(), text: "Nice".into(), ..Default::default() };
        let cu = issue_url(&c, "1", "x", "");
        assert!(cu.contains("template=give-a-compliment.yml&title=Compliment%3A+Nice"));
        assert!(cu.contains("contact=No%2C+don%27t+contact+me"));
    }

    #[test]
    fn shared_logs_fit_the_address() {
        let mut r = report();
        r.share_logs = true;
        let logs: String = (0..2000).map(|i| format!("2026-11-10T10:00:00Z INFO line {i} with some text\n")).collect();
        let u = issue_url(&r, "1", "x", &logs);
        assert!(u.len() <= URL_BUDGET, "{}", u.len());
        assert!(u.contains("line+1999"), "the newest lines are kept");
        assert!(!u.contains("line+0+"));
    }

    #[test]
    fn files_are_named_in_the_details() {
        let mut r = report();
        r.files = vec!["/tmp/x/Screenshot 1.png".into()];
        let u = issue_url(&r, "1", "x", "");
        assert!(u.contains("details=Screenshots+and+files"));
        assert!(u.contains("-+Screenshot+1.png"));
        assert!(!u.contains("%2Ftmp"), "no local paths");
    }

    #[test]
    fn logs_lose_what_identifies_people() {
        let l = r#"INFO chat opened name="Randy Northrup" thread=19:ef213c7c46cf4036b11608300e96fee4@thread.v2 from=8:orgid:4287e791-1b98-4963-8b94-281c50472683 mail=ost-test1@scnetsolutions.com url=https://x.com/a?code=abc phone +1 (555) 010-2030 auth=Bearer abc.def oid 4287e791-1b98-4963-8b94-281c50472683"#;
        let m = mask_line(l);
        for gone in ["Randy", "ef213c7c", "4287e791", "ost-test1", "code=abc", "555", "abc.def"] {
            assert!(!m.contains(gone), "{gone} in {m}");
        }
        assert!(m.contains("INFO chat opened name=\"…\""), "{m}");
        let t = mask_line("2026-11-10T10:00:00.123Z  INFO call 555-010-2030 took 1234567 ms");
        assert!(t.starts_with("2026-11-10T10:00:00.123Z"), "timestamps stay: {t}");
        assert!(t.contains("<number>") && t.contains("1234567"), "{t}");
    }

    #[test]
    fn titles_are_short() {
        let r = Report { text: "x".repeat(200), ..Default::default() };
        assert_eq!(title(&r).chars().count(), "Problem: ".len() + 81);
    }
}
