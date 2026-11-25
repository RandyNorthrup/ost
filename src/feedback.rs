//! Feedback and help to OST's GitHub repo in Microsoft's place (Teams' Report
//! a problem, Give a compliment and Suggest a feature; spec
//! docs/spec/feedback-and-help.md). OST never posts anything: it opens the
//! repo's issue form with only what the reporter typed, and saves the rest
//! (where it was sent from, versions, and the masked logs when they chose
//! to share them) to a file they review and attach themselves before
//! submitting on GitHub. Nothing leaves the device until they do.

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

/// Help's articles on GitHub (docs/help on the branch that has them; a
/// build can set `OST_DOCS_BRANCH`).
pub fn docs_url() -> String {
    let branch = match option_env!("OST_DOCS_BRANCH") {
        Some(b) if !b.is_empty() => b,
        _ => "desktop/foundation",
    };
    format!("{}/blob/{branch}/docs/help", repo_url())
}

/// The privacy statement, and its section on what feedback shares.
pub fn privacy_url(section: &str) -> String {
    let anchor = if section.is_empty() {
        String::new()
    } else {
        format!("#{section}")
    };
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
    /// Files added (screenshots and attachments).
    pub files: Vec<String>,
}

/// The file OST saves beside the report's screenshots for the reporter to
/// review and attach.
pub const DETAILS_FILE: &str = "OST report details.txt";

/// The issue's title: "Problem: " / "Compliment: " and the text's first line.
pub fn title(r: &Report) -> String {
    let lead = if r.kind == "compliment" {
        "Compliment"
    } else {
        "Problem"
    };
    let first = r
        .text
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or_default();
    let mut t: String = first.chars().take(80).collect();
    if first.chars().count() > 80 {
        t.push('…');
    }
    format!("{lead}: {t}")
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// The new-issue address with the form filled in with only what the
/// reporter typed or chose in it: the title (from their text), their text
/// and their contact answer. Logs, versions, where it was sent from and
/// file names stay on the device ([`details_text`]); opening this address
/// sends GitHub nothing else.
pub fn issue_url(r: &Report) -> String {
    let template = if r.kind == "compliment" {
        "give-a-compliment.yml"
    } else {
        "report-a-problem.yml"
    };
    let contact = if r.contact {
        "Yes, you may contact me"
    } else {
        "No, don't contact me"
    };
    let fields = [
        ("template", template.to_string()),
        ("title", title(r)),
        ("what", r.text.clone()),
        ("contact", contact.to_string()),
    ];
    let mut url = format!("{}/issues/new?", repo_url());
    url.push_str(
        &fields
            .iter()
            .filter(|(_, v)| !v.is_empty())
            .map(|(k, v)| format!("{k}={}", enc(v)))
            .collect::<Vec<_>>()
            .join("&"),
    );
    url
}

/// What OST saves for the reporter to review and attach (DETAILS_FILE):
/// where in OST it was sent from and what OST knows about it, the version
/// and operating system, the files added, and `logs` (masked log lines,
/// only when the reporter chose to share them).
pub fn details_text(r: &Report, version: &str, os: &str, logs: &str) -> String {
    let mut t = String::from(
        "OST report details. Review this file before you attach it to the issue: it is public once posted.\n\n",
    );
    for (k, v) in [
        ("Where in OST", r.area.as_str()),
        ("OST version", version),
        ("Operating system", os),
    ] {
        if !v.is_empty() {
            t.push_str(&format!("{k}: {v}\n"));
        }
    }
    if !r.context.trim().is_empty() {
        t.push_str(&format!("\nAdd more details:\n{}\n", r.context.trim_end()));
    }
    if !r.files.is_empty() {
        t.push_str("\nScreenshots and files (in this folder):\n");
        for f in &r.files {
            let name = std::path::Path::new(f)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(f);
            t.push_str(&format!("- {name}\n"));
        }
    }
    if r.share_logs && !logs.is_empty() {
        t.push_str(
            "\nRelevant content samples and additional log files (names and addresses masked):\n",
        );
        t.push_str(logs);
        t.push('\n');
    }
    t
}

/// Secrets taken out of log text: JWTs (Teams', Graph's and Skype's
/// tokens), bearer and Skype token headers, refresh tokens (Entra's `0.A…`
/// / `1.A…`, Microsoft accounts' `M.C…`), Microsoft accounts' opaque
/// `EwA…` tokens, cookies, token, code and signature parameters in
/// addresses, forms and JSON (SAS `sig`, OAuth `code`, `access_token`…),
/// and any long opaque run. OST's log writers ([`Scrubbed`]) apply this to
/// every line before it is written, so logs never hold a token.
pub fn scrub_secrets(text: &str) -> String {
    use std::sync::OnceLock;
    static RES: OnceLock<Vec<(regex::Regex, &'static str)>> = OnceLock::new();
    let res = RES.get_or_init(|| {
        const PARAMS: &str = "access_token|refresh_token|id_token|token|skypetoken|code|client_secret|client_assertion|assertion|password|passwd|sig|signature|tempauth|key|apikey|api_key|otc|sessionToken|sharingToken";
        [
            // Headers and their values, to the end of the value.
            (
                r#"(?i)\b(authorization|x-skypetoken|cookie|set-cookie|x-ms-auth[a-z-]*)(\s*[:=]\s*)"?[^\r\n"]+"?"#.to_string(),
                "$1$2<redacted>",
            ),
            (
                r"(?i)\b(bearer)(\s+)[A-Za-z0-9._~+/=%!*$-]{4,}".to_string(),
                "$1$2<token>",
            ),
            (
                r"(?i)\b(skype_token|skypetoken)([\s=:]+)[A-Za-z0-9._~+/=%!*$-]{20,}".to_string(),
                "$1$2<token>",
            ),
            // JSON fields.
            (
                format!(r#"(?i)"({PARAMS})"(\s*:\s*)"(?:[^"\\]|\\.)*""#),
                "\"$1\"$2\"<redacted>\"",
            ),
            // Address, fragment and form parameters.
            (
                format!(r#"(?i)([?&#;]|\b)({PARAMS})=[^&#\s"'<>]+"#),
                "$1$2=<redacted>",
            ),
            (
                r"eyJ[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]*){1,2}".to_string(),
                "<token>",
            ),
            (r"\b[01]\.A[A-Za-z0-9_.-]{40,}".to_string(), "<token>"),
            (
                r"\bM\.C\d+_[A-Za-z0-9]+\.[A-Za-z0-9!*$_.-]{20,}".to_string(),
                "<token>",
            ),
            (r"\bEw[A-Za-z0-9+/]{100,}={0,2}".to_string(), "<token>"),
            // (Not across '/': long paths stay readable.)
            (r"[A-Za-z0-9+_.%=-]{200,}".to_string(), "<long value>"),
        ]
        .into_iter()
        .map(|(p, r)| (regex::Regex::new(&p).expect("secret pattern"), r))
        .collect()
    });
    let mut out = text.to_string();
    for (re, with) in res {
        if re.is_match(&out) {
            out = re.replace_all(&out, *with).into_owned();
        }
    }
    out
}

/// A log writer factory whose writers take secrets out of each event
/// ([`scrub_secrets`]) before the wrapped writer sees it.
pub struct Scrubbed<M>(pub M);

impl<'a, M: tracing_subscriber::fmt::MakeWriter<'a>> tracing_subscriber::fmt::MakeWriter<'a>
    for Scrubbed<M>
{
    type Writer = ScrubWriter<M::Writer>;
    fn make_writer(&'a self) -> Self::Writer {
        ScrubWriter {
            inner: self.0.make_writer(),
            buf: Vec::new(),
        }
    }
}

/// One event's writer: collects the event, then writes it scrubbed.
pub struct ScrubWriter<W: std::io::Write> {
    inner: W,
    buf: Vec<u8>,
}

impl<W: std::io::Write> ScrubWriter<W> {
    fn emit(&mut self) -> std::io::Result<()> {
        if self.buf.is_empty() {
            return Ok(());
        }
        let text = scrub_secrets(&String::from_utf8_lossy(&self.buf));
        self.buf.clear();
        self.inner.write_all(text.as_bytes())?;
        self.inner.flush()
    }
}

impl<W: std::io::Write> std::io::Write for ScrubWriter<W> {
    fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
        self.buf.extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        // Whole events only: a token split across two writes is caught
        // when the event is complete (on drop).
        Ok(())
    }
}

impl<W: std::io::Write> Drop for ScrubWriter<W> {
    fn drop(&mut self) {
        let _ = self.emit();
    }
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
            (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<email>"),
            (r"\b(?:8|28|29|48):[A-Za-z0-9:._-]+", "<mri>"),
            (r"19:[A-Za-z0-9_.@=-]+", "<thread>"),
            (r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "<id>"),
            (r"(https?://[^\s?#]+)[?#][^\s]*", "$1?…"),
            (r"\+\d[\d\s().-]{7,}\d|\(\d{3}\)\s?\d{3}[-.\s]\d{4}|\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b", "<number>"),
        ]
        .into_iter()
        .map(|(p, r)| (regex::Regex::new(p).expect("mask pattern"), r))
        .collect()
    });
    let mut out = scrub_secrets(line);
    for (re, with) in res {
        out = re.replace_all(&out, *with).into_owned();
    }
    out
}

/// The newest `n` lines of a log, masked.
pub fn masked_tail(log: &str, n: usize) -> String {
    let lines: Vec<&str> = log.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..]
        .iter()
        .map(|l| mask_line(l))
        .collect::<Vec<_>>()
        .join("\n")
}

/// The operating system as the issue names it (os-release's PRETTY_NAME).
pub fn os_name() -> String {
    let pretty = std::fs::read_to_string("/etc/os-release")
        .ok()
        .and_then(|s| {
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
        Report {
            kind: "problem".into(),
            text: "Search shows nothing\nsecond line".into(),
            area: "Find in chat".into(),
            contact: true,
            ..Default::default()
        }
    }

    #[test]
    fn the_issue_form_holds_only_what_was_typed() {
        let mut r = report();
        r.context = "search words: secret project".into();
        r.files = vec!["/tmp/x/Screenshot 1.png".into()];
        r.share_logs = true;
        let u = issue_url(&r);
        assert!(u.starts_with("https://github.com/RandyNorthrup/ost/issues/new?template=report-a-problem.yml&title=Problem%3A+Search+shows+nothing&what=Search+shows+nothing%0Asecond+line"), "{u}");
        assert!(u.contains("&contact=Yes%2C+you+may+contact+me"));
        for absent in [
            "logs=",
            "area=",
            "version=",
            "os=",
            "details=",
            "secret",
            "Screenshot",
            "%2Ftmp",
        ] {
            assert!(!u.contains(absent), "{absent} in {u}");
        }
        let c = Report {
            kind: "compliment".into(),
            text: "Nice".into(),
            ..Default::default()
        };
        let cu = issue_url(&c);
        assert!(cu.contains("template=give-a-compliment.yml&title=Compliment%3A+Nice"));
        assert!(cu.contains("contact=No%2C+don%27t+contact+me"));
    }

    #[test]
    fn the_rest_goes_to_a_file_to_review() {
        let mut r = report();
        r.files = vec!["/tmp/x/Screenshot 1.png".into()];
        let logs = masked_tail("INFO opened chat with ost-test1@scnetsolutions.com", 10);
        let t = details_text(&r, "OST desktop 1", "Arch Linux (x86_64)", &logs);
        assert!(
            t.contains("Where in OST: Find in chat") && t.contains("OST version: OST desktop 1")
        );
        assert!(t.contains("- Screenshot 1.png") && !t.contains("/tmp/x"));
        assert!(!t.contains("opened chat"), "logs only when shared: {t}");
        r.share_logs = true;
        let t = details_text(&r, "1", "x", &logs);
        assert!(t.contains("INFO opened chat with <email>"), "{t}");
        assert!(!t.contains("ost-test1"));
    }

    #[test]
    fn logs_lose_what_identifies_people() {
        let l = r#"INFO chat opened name="Randy Northrup" thread=19:ef213c7c46cf4036b11608300e96fee4@thread.v2 from=8:orgid:4287e791-1b98-4963-8b94-281c50472683 mail=ost-test1@scnetsolutions.com url=https://x.com/a?code=abc phone +1 (555) 010-2030 auth=Bearer abc.def oid 4287e791-1b98-4963-8b94-281c50472683"#;
        let m = mask_line(l);
        for gone in [
            "Randy",
            "ef213c7c",
            "4287e791",
            "ost-test1",
            "code=abc",
            "555",
            "abc.def",
        ] {
            assert!(!m.contains(gone), "{gone} in {m}");
        }
        assert!(m.contains("INFO chat opened name=\"…\""), "{m}");
        let t = mask_line("2026-11-10T10:00:00.123Z  INFO call 555-010-2030 took 1234567 ms");
        assert!(
            t.starts_with("2026-11-10T10:00:00.123Z"),
            "timestamps stay: {t}"
        );
        assert!(t.contains("<number>") && t.contains("1234567"), "{t}");
    }

    #[test]
    fn tokens_never_reach_the_log() {
        let jwt = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiJodHRwczovL2FwaS5zcGFjZXMuc2t5cGUuY29tIn0.c2lnbmF0dXJlLXNlY3JldA";
        let lines = [
            format!("GET https://x.teams.microsoft.com/a?skypetoken={jwt}&x=1"),
            format!("header Authorization: Bearer {jwt}"),
            "Authentication: skypetoken=opaqueSKYPEsecret1234567890".to_string(),
            "X-Skypetoken: opaqueSKYPEsecret1234567890".to_string(),
            "auth=Bearer abc.def.ghi-SECRETbearer".to_string(),
            r#"{"refresh_token":"0.AXEAsecretREFRESH","access_token":"EwBsecretACCESS"}"#.to_string(),
            "refresh 0.AXEAgIvtn0K3sEqi4ivfpWB5xZZbK2vIXu1Gi5_Lrb0SECRETxxxxxxxxxxxx.AgABAwEAAABVrSpeuWamRam2jAF1XRQEAwDs_wUA9P8_SECRET".to_string(),
            "msa M.C552_BAY.0.U.-CsecretMSArefreshTokenXXXXXXXXXXXXXX".to_string(),
            format!("token Ew{}==", "A".repeat(150)),
            "Cookie: ESTSAUTH=secretCOOKIE; buid=secretCOOKIE2".to_string(),
            "Set-Cookie: SignInStateCookie=secretCOOKIE3; path=/".to_string(),
            "download https://t.blob.core.windows.net/c/f.png?sv=2020&sig=secretSAS%3D&se=2026".to_string(),
            "redirect https://login.microsoftonline.com/x#code=secretCODE&state=1".to_string(),
            "form grant_type=authorization_code&code=secretCODE2&client_secret=secretCLIENT".to_string(),
            format!("blob {}", "Q".repeat(300)),
        ];
        for l in &lines {
            let s = scrub_secrets(l);
            for secret in ["secret", "SECRET", "eyJ", "AAAAAAAAAA", "QQQQQQQQQQ"] {
                assert!(!s.contains(secret), "{secret} left in {s:?} (from {l:?})");
            }
        }
        // What isn't a secret stays readable.
        let plain = "2026-11-25T10:00:00Z  INFO Teams GET https://x.teams.microsoft.com/v1/users/ME/conversations?view=msnp24Equivalent took 120 ms";
        assert_eq!(scrub_secrets(plain), plain);
        assert_eq!(
            scrub_secrets("WARN Authentication failed: HTTP 401"),
            "WARN Authentication failed: HTTP 401"
        );
    }

    #[test]
    fn the_log_writer_scrubs_whole_events() {
        use std::io::Write;
        use tracing_subscriber::fmt::MakeWriter;
        #[derive(Clone, Default)]
        struct Sink(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);
        impl Write for Sink {
            fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
                self.0.lock().unwrap().extend_from_slice(b);
                Ok(b.len())
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }
        let sink = Sink::default();
        let make = Scrubbed({
            let s = sink.clone();
            move || s.clone()
        });
        {
            let mut w = make.make_writer();
            // A token split across two writes.
            w.write_all(b"INFO X-Skypetoken: eyJ0eXAiOiJKV1QiLCJh")
                .unwrap();
            w.write_all(b"bGciOiJSUzI1NiJ9.eyJzZWNyZXQiOjF9.c2ln\n")
                .unwrap();
        }
        let out = String::from_utf8(sink.0.lock().unwrap().clone()).unwrap();
        assert!(
            out.starts_with("INFO X-Skypetoken") && !out.contains("eyJ"),
            "{out}"
        );
    }

    #[test]
    fn titles_are_short() {
        let r = Report {
            text: "x".repeat(200),
            ..Default::default()
        };
        assert_eq!(title(&r).chars().count(), "Problem: ".len() + 81);
    }
}
