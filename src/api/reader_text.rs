//! What Immersive Reader reads for a message with cards, as Teams builds
//! it (docs/spec/app-host.md "Immersive Reader"; Teams' module 299105 and
//! its card-to-text module 498891, read 2026-11-16).
//!
//! Teams hands the reader the message's own HTML (`message.content`) with
//! each card's placeholder replaced by the card as text: for a
//! `RichText/Html` message the first `<span itemid="…</span></span>` per
//! card, for a `RichText/Media_Card` message the first
//! `<URIObject type="SWIFT.1" url_thumbnail="…</URIObject>`, each by
//! `<br> {card text} <br>` (a card with no text leaves its placeholder).
//!
//! The card's text is Teams' accessible text for it: an Adaptive Card's
//! `speak`; a hero, thumbnail or sign-in card's title, subtitle and text
//! (HTML stripped), "Image {i}" per picture (from 0) and per button
//! "Button {n}", its title and, for an openUrl button, its value; an
//! Office 365 connector card's title, text and per section its title,
//! text and activity title, subtitle and text. Each field is
//! "{label}:\n{value}. \n\n" (a value already ending in "." gets " ").
//! Measured on a thumbnail card in Teams on the web:
//! `<br> Card title:\nRust (programming language). \n\nCard text
//! content:\n… programming. \n\nImage 0:\n\n <br>`.

use serde_json::Value;

const ADAPTIVE: &str = "application/vnd.microsoft.card.adaptive";
const HERO: &str = "application/vnd.microsoft.card.hero";
const THUMBNAIL: &str = "application/vnd.microsoft.card.thumbnail";
const SIGNIN: &str = "application/vnd.microsoft.card.signin";
const O365: &str = "application/vnd.microsoft.teams.card.o365connector";
const O365_ALIAS: &str = "application/vnd.microsoft.card.o365connector";

/// Teams' value ending: trimmed, then ". " (or " " after a final ".").
fn ending(v: &str) -> String {
    let v = v.trim();
    if v.ends_with('.') { format!("{v} ") } else { format!("{v}. ") }
}

/// One field: "{label}:\n", the value (stripped of HTML when it is rich
/// text) with Teams' ending and "\n", then "\n".
fn field(label: &str, value: Option<&str>, rich: bool) -> String {
    let mut s = format!("{label}:\n");
    if let Some(v) = value.filter(|v| !v.is_empty()) {
        let v = if rich { super::strip_html(v) } else { v.to_string() };
        s.push_str(&ending(&v));
        s.push('\n');
    }
    s.push('\n');
    s
}

fn text<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key).and_then(Value::as_str).filter(|s| !s.is_empty())
}

fn items(v: &Value, key: &str) -> Vec<Value> {
    v.get(key).and_then(Value::as_array).cloned().unwrap_or_default()
}

/// A hero, thumbnail or sign-in card (Teams' `_` with images and buttons).
fn rich_card(c: &Value) -> String {
    let mut s = String::new();
    if let Some(t) = text(c, "title") {
        s += &field("Card title", Some(t), true);
    }
    if let Some(t) = text(c, "subtitle") {
        s += &field("Card subtitle", Some(t), true);
    }
    if let Some(t) = text(c, "text") {
        s += &field("Card text content", Some(t), true);
    }
    for (i, _) in items(c, "images").iter().enumerate() {
        s += &field(&format!("Image {i}"), None, false);
    }
    for (i, b) in items(c, "buttons").iter().enumerate() {
        s += &field(&format!("Button {}", i + 1), None, false);
        s += &field("Button title", text(b, "title"), false);
        if b.get("type").and_then(Value::as_str) == Some("openUrl") {
            s += &field("Button value", text(b, "value"), false);
        }
    }
    s
}

/// An Office 365 connector card (Teams' `b`: no facts, pictures or
/// buttons in this reading).
fn connector_card(c: &Value) -> String {
    let mut s = String::new();
    if let Some(t) = text(c, "title") {
        s += &field("Card title", Some(t), false);
    }
    if let Some(t) = text(c, "text") {
        s += &field("Card text content", Some(t), false);
    }
    for (i, sec) in items(c, "sections").iter().enumerate() {
        s += &field(&format!("Section {}", i + 1), None, false);
        if let Some(t) = text(sec, "title") {
            s += &field("Section title", Some(t), false);
        }
        if let Some(t) = text(sec, "text") {
            s += &field("Section text", Some(t), false);
        }
        if let Some(t) = text(sec, "activityTitle") {
            s += &field("Activity title", Some(t), false);
        }
        if let Some(t) = text(sec, "activitySubtitle") {
            s += &field("Activity subtitle", Some(t), false);
        }
        if let Some(t) = text(sec, "activityText") {
            s += &field("Activity text", Some(t), false);
        }
    }
    s
}

/// A card as Teams reads it out (empty when Teams has no text for it).
pub fn card_text(content_type: &str, content: &Value) -> String {
    if !content.is_object() {
        return String::new();
    }
    let t = content_type.to_ascii_lowercase();
    if t == ADAPTIVE {
        text(content, "speak").unwrap_or_default().to_string()
    } else if t == O365 || t == O365_ALIAS {
        connector_card(content)
    } else if t == HERO || t == THUMBNAIL || t == SIGNIN {
        rich_card(content)
    } else {
        String::new()
    }
}

/// The message's HTML for the reader: its raw content with each card's
/// placeholder replaced by the card's text, as Teams does. `kind` is the
/// message type (`RichText/Html` or `RichText/Media_Card`).
pub fn reader_html(raw: &str, kind: &str, cards: &[(String, Value)]) -> String {
    use std::sync::OnceLock;
    static SPAN: OnceLock<regex::Regex> = OnceLock::new();
    static SWIFT: OnceLock<regex::Regex> = OnceLock::new();
    let re = if kind == "RichText/Media_Card" {
        SWIFT.get_or_init(|| regex::Regex::new(r#"(?i)<URIObject type="SWIFT.1" url_thumbnail="(.*?)</URIObject>"#).expect("regex"))
    } else {
        SPAN.get_or_init(|| regex::Regex::new(r#"(?i)<span itemid="(.*?)</span></span>"#).expect("regex"))
    };
    let mut out = raw.to_string();
    for (t, c) in cards {
        let s = card_text(t, c);
        if s.is_empty() || out.is_empty() {
            continue;
        }
        let with = format!("<br> {s} <br>");
        out = re.replacen(&out, 1, regex::NoExpand(&with)).into_owned();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn thumbnail_card_reads_as_measured() {
        // The link card measured in Teams on the web (OST group test).
        let card = json!({"title": "Rust (programming language)",
            "text": "Rust is a general-purpose programming language that emphasizes performance, type safety, concurrency, and memory safety. Rust supports multiple programming",
            "images": [{"url": "https://x/rust.png"}]});
        let raw = "<p>OST TEST 168a app card</p>\r\n<span itemid=\"c1\" itemtype=\"http://schema.skype.com/Card\"><span>card</span></span> tail";
        let got = reader_html(raw, "RichText/Html", &[(THUMBNAIL.into(), card)]);
        assert_eq!(got, "<p>OST TEST 168a app card</p>\r\n<br> Card title:\nRust (programming language). \n\nCard text content:\nRust is a general-purpose programming language that emphasizes performance, type safety, concurrency, and memory safety. Rust supports multiple programming. \n\nImage 0:\n\n <br> tail");
    }

    #[test]
    fn values_end_once_and_html_is_stripped() {
        let c = json!({"title": "<b>Done.</b>", "subtitle": "Sub", "buttons": [{"type": "openUrl", "title": "Open", "value": "https://x"}, {"type": "imBack", "title": "Hi"}]});
        assert_eq!(card_text(HERO, &c),
            "Card title:\nDone. \n\nCard subtitle:\nSub. \n\nButton 1:\n\nButton title:\nOpen. \n\nButton value:\nhttps://x. \n\nButton 2:\n\nButton title:\nHi. \n\n");
    }

    #[test]
    fn adaptive_cards_read_their_speak_only() {
        assert_eq!(card_text(ADAPTIVE, &json!({"body": [{"type": "TextBlock", "text": "x"}]})), "");
        assert_eq!(card_text(ADAPTIVE, &json!({"speak": "Hello there"})), "Hello there");
        // No text leaves the placeholder.
        let raw = "a<span itemid=\"1\"><span>x</span></span>";
        assert_eq!(reader_html(raw, "RichText/Html", &[(ADAPTIVE.into(), json!({}))]), raw);
    }

    #[test]
    fn connector_sections() {
        let c = json!({"title": "T", "sections": [{"activityTitle": "A", "text": "S", "facts": [{"name": "n", "value": "v"}]}]});
        assert_eq!(card_text(O365_ALIAS, &c), "Card title:\nT. \n\nSection 1:\n\nSection text:\nS. \n\nActivity title:\nA. \n\n");
    }

    #[test]
    fn media_cards_replace_the_swift_object() {
        let raw = "<URIObject type=\"SWIFT.1\" url_thumbnail=\"x\"><Swift b64=\"..\"/></URIObject>";
        let got = reader_html(raw, "RichText/Media_Card", &[(HERO.into(), json!({"title": "Hi"}))]);
        assert_eq!(got, "<br> Card title:\nHi. \n\n <br>");
    }
}
