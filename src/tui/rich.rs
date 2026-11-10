//! A message's formatting for the terminal: the sanitized HTML the desktop
//! reads (and its flow parts: quotes, code blocks, pictures) as styled
//! lines. Headings, quotes, code blocks and list items get their own line
//! kinds; bold, italic, underline, strikethrough and inline code are span
//! styles; pictures and files become labelled placeholders.

use crate::api::messages::FlowPart;

/// How a run of text is styled.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Fmt {
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strike: bool,
    pub code: bool,
    /// A placeholder for a picture or file.
    pub media: bool,
}

/// What a line is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Kind {
    Text,
    Heading(u8),
    Quote,
    Code,
    /// A list item, with its bullet or number.
    Item(String),
}

/// One line of a message, before wrapping.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RichLine {
    pub kind: Kind,
    pub spans: Vec<(String, Fmt)>,
}

impl RichLine {
    fn new(kind: Kind) -> Self {
        Self { kind, spans: Vec::new() }
    }

    /// The line's text, styles dropped.
    pub fn text(&self) -> String {
        self.spans.iter().map(|(t, _)| t.as_str()).collect()
    }
}

/// The message's lines: its flow parts when it has them (quotes, code
/// blocks and pictures in order), else its HTML; `files` are listed after.
pub fn message_lines(html: &str, flow: &[FlowPart], files: &[String]) -> Vec<RichLine> {
    let mut out = Vec::new();
    if flow.is_empty() {
        out.extend(from_html(html, false));
    } else {
        for part in flow {
            if let Some(code) = &part.code {
                for l in code.text.trim_end_matches('\n').split('\n') {
                    out.push(RichLine { kind: Kind::Code, spans: vec![(l.to_string(), Fmt { code: true, ..Fmt::default() })] });
                }
            } else if let Some(q) = &part.quote {
                out.extend(from_html(q, true));
            } else if part.pic.is_some() {
                out.push(RichLine { kind: Kind::Text, spans: vec![("[Image]".into(), Fmt { media: true, ..Fmt::default() })] });
            } else if !part.html.is_empty() {
                out.extend(from_html(&part.html, false));
            }
        }
    }
    for f in files {
        out.push(RichLine { kind: Kind::Text, spans: vec![(format!("[file] {f}"), Fmt { media: true, ..Fmt::default() })] });
    }
    // No blank lines at the ends, and never two in a row.
    let blank = |l: &RichLine| l.text().trim().is_empty() && l.kind != Kind::Code;
    let mut tidy: Vec<RichLine> = Vec::new();
    for l in out {
        if blank(&l) && (tidy.is_empty() || tidy.last().is_some_and(blank)) {
            continue;
        }
        tidy.push(l);
    }
    while tidy.last().is_some_and(blank) {
        tidy.pop();
    }
    tidy
}

/// Decode the entities the sanitizer leaves.
fn decode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        let tail = &rest[i..];
        let Some(end) = tail.find(';').filter(|e| *e <= 10) else {
            out.push('&');
            rest = &tail[1..];
            continue;
        };
        let name = &tail[1..end];
        let ch = match name {
            "nbsp" => Some(' '),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "amp" => Some('&'),
            "quot" => Some('"'),
            "apos" | "#39" => Some('\''),
            n if n.starts_with("#x") || n.starts_with("#X") => u32::from_str_radix(&n[2..], 16).ok().and_then(char::from_u32),
            n if n.starts_with('#') => n[1..].parse().ok().and_then(char::from_u32),
            _ => None,
        };
        match ch {
            Some(c) => {
                out.push(c);
                rest = &tail[end + 1..];
            }
            None => {
                out.push('&');
                rest = &tail[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// The HTML's lines (`quote`: all of them inside a quote).
pub fn from_html(html: &str, quote: bool) -> Vec<RichLine> {
    #[derive(Default)]
    struct State {
        bold: u32,
        italic: u32,
        underline: u32,
        strike: u32,
        code: u32,
        quote: u32,
        pre: u32,
        heading: u8,
        /// Open lists: None for bullets, Some(n) for the next number.
        lists: Vec<Option<u32>>,
    }
    let mut st = State { quote: u32::from(quote), ..State::default() };
    let mut lines: Vec<RichLine> = Vec::new();
    let mut cur: Option<RichLine> = None;
    let kind_now = |st: &State| {
        if st.pre > 0 {
            Kind::Code
        } else if st.heading > 0 {
            Kind::Heading(st.heading)
        } else if st.quote > 0 {
            Kind::Quote
        } else {
            Kind::Text
        }
    };
    let flush = |cur: &mut Option<RichLine>, lines: &mut Vec<RichLine>| {
        if let Some(l) = cur.take() {
            lines.push(l);
        }
    };
    let push_text = |text: &str, st: &State, cur: &mut Option<RichLine>| {
        if text.is_empty() {
            return;
        }
        let line = cur.get_or_insert_with(|| RichLine::new(kind_now(st)));
        let fmt = Fmt {
            bold: st.bold > 0 || st.heading > 0,
            italic: st.italic > 0,
            underline: st.underline > 0,
            strike: st.strike > 0,
            code: st.code > 0 || st.pre > 0,
            media: false,
        };
        match line.spans.last_mut() {
            Some((t, f)) if *f == fmt => t.push_str(text),
            _ => line.spans.push((text.to_string(), fmt)),
        }
    };

    let mut i = 0;
    let bytes = html.as_bytes();
    while i < html.len() {
        if bytes[i] == b'<' {
            let Some(end) = html[i..].find('>').map(|e| i + e) else { break };
            let raw = &html[i + 1..end];
            i = end + 1;
            let closing = raw.starts_with('/');
            let body = raw.trim_start_matches('/').trim_end_matches('/');
            let name = body.split(|c: char| c.is_whitespace()).next().unwrap_or_default().to_ascii_lowercase();
            let attrs = &body[name.len().min(body.len())..];
            let delta = |n: &mut u32| {
                if closing {
                    *n = n.saturating_sub(1)
                } else {
                    *n += 1
                }
            };
            match name.as_str() {
                "b" | "strong" => delta(&mut st.bold),
                "i" | "em" => delta(&mut st.italic),
                "u" | "ins" => delta(&mut st.underline),
                "s" | "strike" | "del" => delta(&mut st.strike),
                "code" if st.pre == 0 => delta(&mut st.code),
                "a" => delta(&mut st.underline),
                "span" if !closing && attrs.contains("font-weight:bold") => st.bold += 1,
                "br" => {
                    let k = kind_now(&st);
                    flush(&mut cur, &mut lines);
                    cur = Some(RichLine::new(k));
                }
                "img" if !closing => {
                    let alt = attrs.split("alt=\"").nth(1).and_then(|a| a.split('"').next()).unwrap_or_default();
                    // Emoticons are pictures with their emoji as alt text.
                    let emoji = attrs.contains("itemtype=\"http://schema.skype.com/Emoji\"") || attrs.contains("class=\"emoji\"");
                    let (text, media) = if emoji && !alt.is_empty() { (decode(alt), false) } else { ("[Image]".to_string(), true) };
                    let line = cur.get_or_insert_with(|| RichLine::new(kind_now(&st)));
                    line.spans.push((text, Fmt { media, ..Fmt::default() }));
                }
                "blockquote" => {
                    flush(&mut cur, &mut lines);
                    delta(&mut st.quote);
                }
                "pre" => {
                    flush(&mut cur, &mut lines);
                    delta(&mut st.pre);
                }
                "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                    flush(&mut cur, &mut lines);
                    st.heading = if closing { 0 } else { name[1..].parse().unwrap_or(1) };
                }
                "ul" | "ol" => {
                    flush(&mut cur, &mut lines);
                    if closing {
                        st.lists.pop();
                    } else {
                        st.lists.push((name == "ol").then_some(1));
                    }
                }
                "li" => {
                    flush(&mut cur, &mut lines);
                    if !closing {
                        let depth = st.lists.len().saturating_sub(1);
                        let bullet = match st.lists.last_mut() {
                            Some(Some(n)) => {
                                let b = format!("{n}. ");
                                *n += 1;
                                b
                            }
                            _ => "• ".to_string(),
                        };
                        cur = Some(RichLine::new(Kind::Item(format!("{}{bullet}", "  ".repeat(depth)))));
                    }
                }
                "p" | "div" | "tr" | "table" => flush(&mut cur, &mut lines),
                "td" | "th" if !closing => push_text(" | ", &st, &mut cur),
                _ => {}
            }
            continue;
        }
        let next = html[i..].find('<').map(|n| i + n).unwrap_or(html.len());
        let raw = &html[i..next];
        i = next;
        if st.pre > 0 {
            // Code keeps its lines and spaces.
            for (n, piece) in decode(raw).split('\n').enumerate() {
                if n > 0 {
                    flush(&mut cur, &mut lines);
                    cur = Some(RichLine::new(Kind::Code));
                }
                push_text(piece, &st, &mut cur);
            }
        } else {
            let text: String = decode(&raw.replace(['\r', '\n', '\t'], " "));
            // Collapse runs of spaces (non-breaking ones stay).
            let mut collapsed = String::with_capacity(text.len());
            let mut prev_space = cur.as_ref().is_none_or(|l| l.text().ends_with(' ') || l.spans.is_empty());
            for c in text.chars() {
                if c == ' ' {
                    if prev_space {
                        continue;
                    }
                    prev_space = true;
                } else {
                    prev_space = false;
                }
                collapsed.push(c);
            }
            if !collapsed.is_empty() && (cur.is_some() || !collapsed.trim().is_empty()) {
                push_text(&collapsed, &st, &mut cur);
            }
        }
    }
    flush(&mut cur, &mut lines);
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(lines: &[RichLine]) -> Vec<(Kind, String)> {
        lines.iter().map(|l| (l.kind.clone(), l.text().trim().to_string())).collect()
    }

    #[test]
    fn teams_formatting_becomes_line_kinds_and_styles() {
        // "OST TEST 69"/"70" as the desktop reads them (trimmed).
        let html = "<p>OST TEST 69 <b>bold</b> <i>it</i> <u>un</u> <s>st</s> and <code>inline</code></p>\
            <blockquote><p>a quote</p></blockquote><h2>Heading two</h2>\
            <ul><li>one</li><li>two</li></ul><ol><li>first</li></ol><p>a&nbsp;&amp;&lt;b&gt;</p>";
        let lines = from_html(html, false);
        assert_eq!(
            kinds(&lines),
            vec![
                (Kind::Text, "OST TEST 69 bold it un st and inline".into()),
                (Kind::Quote, "a quote".into()),
                (Kind::Heading(2), "Heading two".into()),
                (Kind::Item("• ".into()), "one".into()),
                (Kind::Item("• ".into()), "two".into()),
                (Kind::Item("1. ".into()), "first".into()),
                (Kind::Text, "a &<b>".into()),
            ]
        );
        let first = &lines[0].spans;
        let style = |t: &str| first.iter().find(|(s, _)| s.contains(t)).unwrap().1;
        assert!(style("bold").bold && style("it").italic && style("un").underline && style("st").strike && style("inline").code);
        assert!(!style("OST").bold);
    }

    #[test]
    fn code_blocks_pictures_and_files_from_the_flow() {
        let flow = vec![
            FlowPart { html: "<p>OST TEST 87 code block (Rust)</p>".into(), ..FlowPart::default() },
            FlowPart { code: Some(crate::api::messages::CodeBlock { lang: "rust".into(), name: "Rust".into(), text: "fn main() {\n    let n = 1;\n}".into() }), ..FlowPart::default() },
            FlowPart { pic: Some(0), ..FlowPart::default() },
        ];
        let lines = message_lines("", &flow, &["notes.pdf".to_string()]);
        assert_eq!(
            kinds(&lines),
            vec![
                (Kind::Text, "OST TEST 87 code block (Rust)".into()),
                (Kind::Code, "fn main() {".into()),
                (Kind::Code, "let n = 1;".into()),
                (Kind::Code, "}".into()),
                (Kind::Text, "[Image]".into()),
                (Kind::Text, "[file] notes.pdf".into()),
            ]
        );
        assert_eq!(lines[2].text(), "    let n = 1;", "code keeps its indentation");
    }
}
