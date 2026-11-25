//! The compose box's clean HTML (what the desktop's RichText exports, and
//! `teams_html_with_media` sends) read back as its blocks, so a draft can be
//! put back in the box with every format it had (Teams keeps a draft's
//! formatting when you switch chats and after a restart).
//!
//! The HTML is OST's own export, so the grammar is small: `<p>` (with an
//! optional `margin-left` indent), `<h1>`–`<h3>`, `<hr>`, `<blockquote>`
//! runs, `<ul>`/`<ol>` of `<li>`, Teams' code block (a CodeBlockEditor
//! marker paragraph and a `<pre class="language-…">`) and
//! `<table><tbody><tr><td>…`. Inline content (b/i/u/s, styled spans, code,
//! links, mentions, pictures, `<br>`) is left as HTML for Qt to read, with
//! inline code marked so the editor can restore it.

use serde::Serialize;

/// The font family inline code is marked with for the editor, which turns
/// it back into its own inline code.
pub const INLINE_CODE_MARK: &str = "ost-inline-code";

/// One paragraph of the compose box, or a table.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ComposeBlock {
    /// "p", "h", "li", "hr", "code" or "table".
    pub kind: &'static str,
    /// In a quote.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub quote: bool,
    /// A paragraph's indent steps (40 px each).
    #[serde(skip_serializing_if = "is_zero")]
    pub indent: u32,
    /// A heading's level (1-3).
    #[serde(skip_serializing_if = "is_zero")]
    pub level: u32,
    /// A list item's list: "ul" or "ol", and which list (items of one list
    /// share it).
    #[serde(skip_serializing_if = "str::is_empty")]
    pub list: &'static str,
    #[serde(skip_serializing_if = "is_zero")]
    pub list_id: u32,
    /// A code line's language (as Teams names it, "plaintext" by default)
    /// and its text.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub lang: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub text: String,
    /// The inline content as HTML for Qt ("" for an empty paragraph).
    #[serde(skip_serializing_if = "String::is_empty")]
    pub html: String,
    /// A table's cells by row, each its own blocks.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub rows: Vec<Vec<Vec<ComposeBlock>>>,
}

fn is_zero(n: &u32) -> bool {
    *n == 0
}

/// The blocks of compose HTML, in order.
pub fn compose_blocks(html: &str) -> Vec<ComposeBlock> {
    let mut lists = 0;
    parse(html, &mut lists)
}

/// The blocks as JSON (for the editor).
pub fn compose_blocks_json(html: &str) -> String {
    serde_json::to_string(&compose_blocks(html)).unwrap_or_else(|_| "[]".into())
}

fn parse(html: &str, lists: &mut u32) -> Vec<ComposeBlock> {
    let mut out = Vec::new();
    let mut quote = false;
    let mut list: Option<(&'static str, u32)> = None;
    let mut rest = html;
    loop {
        rest = rest.trim_start();
        if rest.is_empty() {
            break;
        }
        // Text outside any block: a paragraph of its own.
        if !rest.starts_with('<') {
            let end = rest.find('<').unwrap_or(rest.len());
            out.push(ComposeBlock {
                kind: "p",
                quote,
                html: inline(&rest[..end]),
                ..Default::default()
            });
            rest = &rest[end..];
            continue;
        }
        let Some(gt) = rest.find('>') else { break };
        let tag = &rest[1..gt];
        let name = tag_name(tag);
        let after = &rest[gt + 1..];
        rest = after;
        match name.as_str() {
            "blockquote" => quote = true,
            "/blockquote" => quote = false,
            "ul" | "ol" => {
                *lists += 1;
                list = Some((if name == "ol" { "ol" } else { "ul" }, *lists));
            }
            "/ul" | "/ol" => list = None,
            "li" => {
                let (inner, next) = until(after, "</li>");
                rest = next;
                let (kind, id) = list.unwrap_or_else(|| {
                    *lists += 1;
                    ("ul", *lists)
                });
                out.push(ComposeBlock {
                    kind: "li",
                    quote,
                    list: kind,
                    list_id: id,
                    html: inline(inner),
                    ..Default::default()
                });
            }
            "p" => {
                let (inner, next) = until(after, "</p>");
                rest = next;
                // Teams' code block marker paragraph: the <pre> follows.
                if attr(tag, "itemtype").is_some_and(|t| t.contains("CodeBlockEditor")) {
                    continue;
                }
                let indent = attr(tag, "style")
                    .and_then(|s| style_px(&s, "margin-left"))
                    .map(|px| (px + 20) / 40)
                    .unwrap_or(0);
                out.push(ComposeBlock {
                    kind: "p",
                    quote,
                    indent,
                    html: inline(inner),
                    ..Default::default()
                });
            }
            "h1" | "h2" | "h3" => {
                let (inner, next) = until(after, &format!("</{name}>"));
                rest = next;
                out.push(ComposeBlock {
                    kind: "h",
                    quote,
                    level: u32::from(name.as_bytes()[1] - b'0'),
                    html: inline(inner),
                    ..Default::default()
                });
            }
            "hr" => out.push(ComposeBlock {
                kind: "hr",
                quote,
                ..Default::default()
            }),
            "pre" => {
                let (inner, next) = until(after, "</pre>");
                rest = next;
                let lang = attr(tag, "class")
                    .and_then(|c| {
                        c.split_whitespace()
                            .find_map(|w| w.strip_prefix("language-").map(str::to_string))
                    })
                    .filter(|l| !l.is_empty())
                    .unwrap_or_else(|| "plaintext".into());
                let code = inner
                    .trim_start_matches("<code>")
                    .trim_end_matches("</code>");
                for line in code.split('\n') {
                    out.push(ComposeBlock {
                        kind: "code",
                        lang: lang.clone(),
                        text: unescape(line.trim_end_matches('\r')),
                        ..Default::default()
                    });
                }
            }
            "table" => {
                let (inner, next) = until(after, "</table>");
                rest = next;
                out.push(ComposeBlock {
                    kind: "table",
                    rows: table_rows(inner, lists),
                    ..Default::default()
                });
            }
            // tbody, stray closers and anything else: no block of their own.
            _ => {}
        }
    }
    out
}

/// A table's rows of cells, each cell parsed as blocks.
fn table_rows(html: &str, lists: &mut u32) -> Vec<Vec<Vec<ComposeBlock>>> {
    let mut rows = Vec::new();
    for row in html.split("<tr>").skip(1) {
        let row = row.split("</tr>").next().unwrap_or("");
        let mut cells = Vec::new();
        let mut rest = row;
        while let Some(at) = rest.find("<td") {
            let Some(gt) = rest[at..].find('>') else {
                break;
            };
            let (inner, next) = until(&rest[at + gt + 1..], "</td>");
            let mut blocks = parse(inner, lists);
            if blocks.is_empty() {
                blocks.push(ComposeBlock {
                    kind: "p",
                    ..Default::default()
                });
            }
            cells.push(blocks);
            rest = next;
        }
        if !cells.is_empty() {
            rows.push(cells);
        }
    }
    rows
}

/// The text up to `close`, and what follows it.
fn until<'a>(s: &'a str, close: &str) -> (&'a str, &'a str) {
    match s.find(close) {
        Some(i) => (&s[..i], &s[i + close.len()..]),
        None => (s, ""),
    }
}

/// A tag's name, lower case ("/p" for a closing tag).
fn tag_name(tag: &str) -> String {
    tag.split(|c: char| c.is_whitespace() || c == '>')
        .next()
        .unwrap_or("")
        .trim_end_matches('/')
        .to_ascii_lowercase()
}

/// A double-quoted attribute's value (as the export writes them).
fn attr(tag: &str, name: &str) -> Option<String> {
    let key = format!(" {name}=\"");
    let start = tag.find(&key)? + key.len();
    let end = tag[start..].find('"')?;
    Some(unescape(&tag[start..start + end]))
}

/// `prop:Npx` in a style.
fn style_px(style: &str, prop: &str) -> Option<u32> {
    style.split(';').find_map(|d| {
        let (k, v) = d.split_once(':')?;
        (k.trim() == prop)
            .then(|| v.trim().trim_end_matches("px").trim().parse().ok())
            .flatten()
    })
}

/// Inline HTML for Qt: an empty paragraph's `&nbsp;` dropped, inline code
/// marked, and spaces kept as typed (Qt would collapse them).
fn inline(html: &str) -> String {
    if html.is_empty() || html == "&nbsp;" {
        return String::new();
    }
    let marked = html.replace(
        "<code>",
        &format!("<span style=\"font-family:'{INLINE_CODE_MARK}'\">"),
    );
    let marked = marked.replace("</code>", "</span>");
    format!("<span style=\"white-space:pre-wrap\">{marked}</span>")
}

/// Text from escaped HTML (the export escapes &, <, > and ").
fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let entity = rest.find(';').filter(|&e| e <= 8).map(|e| &rest[..=e]);
        let decoded = match entity {
            Some("&amp;") => Some('&'),
            Some("&lt;") => Some('<'),
            Some("&gt;") => Some('>'),
            Some("&quot;") => Some('"'),
            Some("&#39;") | Some("&#x27;") | Some("&apos;") => Some('\''),
            Some("&nbsp;") => Some('\u{a0}'),
            _ => None,
        };
        match (entity, decoded) {
            (Some(e), Some(c)) => {
                out.push(c);
                rest = &rest[e.len()..];
            }
            _ => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wrapped(s: &str) -> String {
        format!("<span style=\"white-space:pre-wrap\">{s}</span>")
    }

    #[test]
    fn paragraphs_headings_and_indent() {
        let b = compose_blocks(
            "<p><b>bold</b> and <i>it</i></p><p>&nbsp;</p><h2>Head</h2><p style=\"margin-left:80px\">in</p><hr>",
        );
        assert_eq!(b.len(), 5);
        assert_eq!(b[0].kind, "p");
        assert_eq!(b[0].html, wrapped("<b>bold</b> and <i>it</i>"));
        assert_eq!(b[1].kind, "p");
        assert!(b[1].html.is_empty(), "empty paragraph stays empty");
        assert_eq!((b[2].kind, b[2].level), ("h", 2));
        assert_eq!(b[2].html, wrapped("Head"));
        assert_eq!((b[3].kind, b[3].indent), ("p", 2));
        assert_eq!(b[4].kind, "hr");
    }

    #[test]
    fn quotes_and_lists() {
        let b = compose_blocks(
            "<blockquote><p>q1</p><ul><li>a</li><li>b</li></ul></blockquote><ol><li>one</li></ol><ul><li>c</li></ul>",
        );
        assert_eq!(b.len(), 5);
        assert!(b[0].quote && b[1].quote && b[2].quote);
        assert!(!b[3].quote && !b[4].quote);
        assert_eq!((b[1].kind, b[1].list), ("li", "ul"));
        assert_eq!(b[1].list_id, b[2].list_id, "items of one list share it");
        assert_eq!(b[3].list, "ol");
        assert_ne!(b[3].list_id, b[1].list_id);
        assert_ne!(
            b[4].list_id, b[1].list_id,
            "a second bulleted list is its own"
        );
    }

    #[test]
    fn code_block_lines_and_language() {
        let b = compose_blocks(
            "<p>before</p><p itemtype=\"http://schema.skype.com/CodeBlockEditor\" id=\"codeBlockEditor-1\">&nbsp;</p><pre class=\"language-rust\" itemid=\"codeBlockEditor-1\"><code>fn main() {\n    let s = &quot;a &lt;b&gt; &amp;amp;&quot;;\n\n}</code></pre><p>after</p>",
        );
        let kinds: Vec<_> = b.iter().map(|x| x.kind).collect();
        assert_eq!(kinds, ["p", "code", "code", "code", "code", "p"]);
        assert!(b[1..5].iter().all(|x| x.lang == "rust"));
        assert_eq!(b[1].text, "fn main() {");
        assert_eq!(b[2].text, "    let s = \"a <b> &amp;\";");
        assert_eq!(b[3].text, "");
        assert_eq!(b[4].text, "}");
    }

    #[test]
    fn code_block_without_language_is_plain_text() {
        let b = compose_blocks("<pre><code>x</code></pre>");
        assert_eq!(
            (b[0].kind, b[0].lang.as_str(), b[0].text.as_str()),
            ("code", "plaintext", "x")
        );
    }

    #[test]
    fn tables_keep_their_cells() {
        let b = compose_blocks(
            "<p>&nbsp;</p><table><tbody><tr><td><p>a</p></td><td><p>&nbsp;</p></td></tr><tr><td><p>c</p><p>c2</p></td><td><h1>d</h1></td></tr></tbody></table><p>&nbsp;</p>",
        );
        let kinds: Vec<_> = b.iter().map(|x| x.kind).collect();
        assert_eq!(kinds, ["p", "table", "p"]);
        let rows = &b[1].rows;
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|r| r.len() == 2));
        assert_eq!(rows[0][0][0].html, wrapped("a"));
        assert!(rows[0][1][0].html.is_empty());
        assert_eq!(rows[1][0].len(), 2);
        assert_eq!((rows[1][1][0].kind, rows[1][1][0].level), ("h", 1));
    }

    #[test]
    fn inline_code_links_mentions_and_pictures() {
        let b = compose_blocks(
            "<p>run <code>ls -l</code> at <a href=\"https://example.com/?a=1&amp;b=2\">site</a>, <a href=\"mention:8:orgid:x\">Ann</a>&nbsp;<img src=\"https://e/20_f.png\" width=\"20\" height=\"20\"><br>next</p>",
        );
        assert_eq!(b.len(), 1);
        let h = &b[0].html;
        assert!(
            h.contains("<span style=\"font-family:'ost-inline-code'\">ls -l</span>"),
            "{h}"
        );
        assert!(!h.contains("<code>"));
        assert!(h.contains("<a href=\"https://example.com/?a=1&amp;b=2\">site</a>"));
        assert!(h.contains("<a href=\"mention:8:orgid:x\">Ann</a>&nbsp;<img"));
        assert!(h.contains("<br>next"));
    }

    #[test]
    fn spaces_are_kept() {
        let b = compose_blocks("<p>  two  spaces </p>");
        assert_eq!(b[0].html, wrapped("  two  spaces "));
    }

    #[test]
    fn json_leaves_defaults_out() {
        let j = compose_blocks_json("<p>x</p><hr>");
        assert_eq!(
            j,
            r#"[{"kind":"p","html":"<span style=\"white-space:pre-wrap\">x</span>"},{"kind":"hr"}]"#
        );
        assert_eq!(compose_blocks_json(""), "[]");
    }

    #[test]
    fn unescape_decodes_once() {
        assert_eq!(
            unescape("&amp;lt; &lt;&gt; &quot;&#39; &nbsp;& &bogus;"),
            "&lt; <> \"' \u{a0}& &bogus;"
        );
    }
}
