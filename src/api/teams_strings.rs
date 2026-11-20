//! OST's text in Teams' app languages, built on the device from Teams'
//! own string resources.
//!
//! OST keys each of its strings to the Teams string id whose en-us text it
//! is (desktop/i18n/ids.json; OST for Teams). For any other language it
//! downloads that locale's string resources from Teams' CDN, the same
//! `<namespace>-locale-<locale>-<hash>.js` webpack chunks Teams loads
//! (desktop/i18n/teams_resources.json lists them, pinned to one Teams build
//! by the content hash in their names), and turns the ids it needs into a
//! catalogue in Qt's form:
//!
//! - Teams' `{{name}}` / `{name}` / `{0}` placeholders and its empty
//!   rich-text components (`<0></0>`: a name or link its React code fills)
//!   become `%1`, `%2`… in the order the id's en-us text has them
//!   (ids.json carries it);
//! - an ICU plural message becomes its forms (`{"=1": …, "one": …,
//!   "other": …}`), its count `%n`;
//! - Teams' product name becomes OST (`ostify`), for strings that name it.
//!
//! The catalogue is cached (written atomically); the desktop's translator
//! reads it.

use std::collections::HashMap;

use serde::Deserialize;
use serde_json::{Map, Value};

/// One of OST's strings: its source text, disambiguation, Teams id, the
/// id's placeholders in en-us order, and OST's English plural forms.
#[derive(Debug, Clone, Deserialize)]
pub struct IdRow(pub String, pub String, pub String, pub Vec<String>, #[serde(default)] pub Option<Value>);

/// Where Teams' string resources are, per locale.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Resources {
    pub teams_version: String,
    pub base: String,
    pub files: HashMap<String, Vec<String>>,
}

/// Teams' strings by namespace and key.
pub type Strings = HashMap<String, HashMap<String, String>>;

// ------------------------------------------------------------ resources

/// The translations in one of Teams' locale chunks, added to `out`
/// (`{namespace:"…",locale:"…",translations:{<key>:"<text>",…}}`, possibly
/// several in one file).
pub fn parse_chunk(js: &str, out: &mut Strings) {
    const HEAD: &str = "namespace:\"";
    let b = js.as_bytes();
    let mut from = 0;
    while let Some(p) = js[from..].find(HEAD) {
        let start = from + p + HEAD.len();
        from = start;
        let Some(ns_end) = js[start..].find('"') else { break };
        let ns = js[start..start + ns_end].to_string();
        let rest = &js[start + ns_end..];
        let Some(t) = rest.find("translations:{") else { break };
        // the locale field sits between the two
        if !rest[..t].contains("locale:\"") {
            continue;
        }
        let mut i = start + ns_end + t + "translations:{".len();
        let table = out.entry(ns).or_default();
        loop {
            while i < b.len() && matches!(b[i], b' ' | b',' | b'\n') {
                i += 1;
            }
            if i >= b.len() || b[i] == b'}' {
                break;
            }
            let key = if b[i] == b'"' || b[i] == b'\'' {
                let Some((k, n)) = js_string(js, i) else { return };
                i = n;
                k
            } else {
                let Some(c) = js[i..].find(':') else { return };
                let k = js[i..i + c].to_string();
                i += c;
                k
            };
            if b.get(i) != Some(&b':') {
                return;
            }
            i += 1;
            if !matches!(b.get(i), Some(b'"' | b'\'' | b'`')) {
                return;
            }
            let Some((v, n)) = js_string(js, i) else { return };
            i = n;
            table.insert(key, v);
        }
        from = i;
    }
}

/// The JS string literal starting at `i` (its quote) and the index after it.
fn js_string(s: &str, i: usize) -> Option<(String, usize)> {
    let b = s.as_bytes();
    let q = b[i];
    let mut j = i + 1;
    let mut units: Vec<u16> = Vec::new();
    while j < b.len() {
        let c = b[j];
        if c == q {
            return Some((String::from_utf16_lossy(&units), j + 1));
        }
        if c == b'\\' {
            let n = *b.get(j + 1)?;
            match n {
                b'u' if b.get(j + 2) == Some(&b'{') => {
                    let end = s[j..].find('}')? + j;
                    let cp = u32::from_str_radix(&s[j + 3..end], 16).ok()?;
                    let mut buf = [0u16; 2];
                    units.extend_from_slice(char::from_u32(cp)?.encode_utf16(&mut buf));
                    j = end + 1;
                }
                b'u' => {
                    units.push(u16::from_str_radix(s.get(j + 2..j + 6)?, 16).ok()?);
                    j += 6;
                }
                b'x' => {
                    units.push(u16::from_str_radix(s.get(j + 2..j + 4)?, 16).ok()?);
                    j += 4;
                }
                _ => {
                    let ch = match n {
                        b'n' => '\n',
                        b't' => '\t',
                        b'r' => '\r',
                        b'0' => '\0',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'v' => '\u{b}',
                        _ => {
                            // any other escaped character stands for itself
                            let ch = s[j + 1..].chars().next()?;
                            let mut buf = [0u16; 2];
                            units.extend_from_slice(ch.encode_utf16(&mut buf));
                            j += 1 + ch.len_utf8();
                            continue;
                        }
                    };
                    units.push(ch as u16);
                    j += 2;
                }
            }
            continue;
        }
        let ch = s[j..].chars().next()?;
        let mut buf = [0u16; 2];
        units.extend_from_slice(ch.encode_utf16(&mut buf));
        j += ch.len_utf8();
    }
    None
}

// -------------------------------------------------------------- messages

#[derive(Debug, Clone, PartialEq)]
enum Part {
    Text(String),
    Arg(String),
    Hash,
    Plural(String, Vec<(String, Vec<Part>)>),
    Select,
}

/// Teams' message syntax: `{{name}}` placeholders and ICU `{arg}`,
/// `{n, plural, …}` (`#` its count) and `{x, select, …}`.
fn parse_message(s: &str) -> Option<Vec<Part>> {
    let s = components(s);
    let chars: Vec<char> = s.chars().collect();
    let (parts, _) = parse_parts(&chars, 0, false)?;
    Some(parts)
}

/// Teams' empty rich-text components (`<0></0>`, `<1/>`: a name, a link,
/// filled by its React code) are placeholders: `{{<0>}}`. A component that
/// only wraps one (`<0><0></0></0>`) is that placeholder too.
fn components(s: &str) -> std::borrow::Cow<'_, str> {
    use std::sync::OnceLock;
    static EMPTY: OnceLock<regex::Regex> = OnceLock::new();
    static WRAP: OnceLock<regex::Regex> = OnceLock::new();
    if !s.contains('<') {
        return s.into();
    }
    let empty = EMPTY.get_or_init(|| regex::Regex::new(r"<(\d+)>\s*</(\d+)>|<(\d+)\s*/>").unwrap());
    let wrap = WRAP.get_or_init(|| regex::Regex::new(r"<(\d+)>(\{\{<\d+>\}\})</(\d+)>").unwrap());
    let mut t = empty
        .replace_all(s, |c: &regex::Captures| match (c.get(1), c.get(2), c.get(3)) {
            (Some(a), Some(b), _) if a.as_str() == b.as_str() => format!("{{{{<{}>}}}}", a.as_str()),
            (_, _, Some(a)) => format!("{{{{<{}>}}}}", a.as_str()),
            _ => c[0].to_string(),
        })
        .into_owned();
    loop {
        let next = wrap
            .replace_all(&t, |c: &regex::Captures| if c[1] == c[3] { c[2].to_string() } else { c[0].to_string() })
            .into_owned();
        if next == t {
            break;
        }
        t = next;
    }
    t.into()
}

fn parse_parts(c: &[char], mut i: usize, in_plural: bool) -> Option<(Vec<Part>, usize)> {
    let mut out = Vec::new();
    let mut buf = String::new();
    let flush = |buf: &mut String, out: &mut Vec<Part>| {
        if !buf.is_empty() {
            out.push(Part::Text(std::mem::take(buf)));
        }
    };
    while i < c.len() {
        let ch = c[i];
        if ch == '{' && c.get(i + 1) == Some(&'{') {
            let close = (i + 2..c.len().saturating_sub(1)).find(|&k| c[k] == '}' && c[k + 1] == '}')?;
            flush(&mut buf, &mut out);
            out.push(Part::Arg(c[i + 2..close].iter().collect::<String>().trim().to_string()));
            i = close + 2;
            continue;
        }
        if ch == '{' {
            flush(&mut buf, &mut out);
            let mut j = i + 1;
            while j < c.len() && c[j].is_whitespace() {
                j += 1;
            }
            let name_start = j;
            while j < c.len() && (c[j].is_alphanumeric() || c[j] == '_' || c[j] == '.') {
                j += 1;
            }
            let name: String = c[name_start..j].iter().collect();
            if name.is_empty() {
                return None;
            }
            while j < c.len() && c[j].is_whitespace() {
                j += 1;
            }
            if c.get(j) == Some(&'}') {
                out.push(Part::Arg(name));
                i = j + 1;
                continue;
            }
            if c.get(j) != Some(&',') {
                return None;
            }
            j += 1;
            while j < c.len() && c[j].is_whitespace() {
                j += 1;
            }
            let kind_start = j;
            while j < c.len() && c[j].is_alphabetic() {
                j += 1;
            }
            let kind: String = c[kind_start..j].iter().collect();
            while j < c.len() && c[j].is_whitespace() {
                j += 1;
            }
            if c.get(j) != Some(&',') {
                return None;
            }
            j += 1;
            let plural = kind == "plural" || kind == "selectordinal";
            if !plural && kind != "select" {
                return None;
            }
            let mut forms = Vec::new();
            loop {
                while j < c.len() && c[j].is_whitespace() {
                    j += 1;
                }
                match c.get(j) {
                    Some('}') => {
                        j += 1;
                        break;
                    }
                    None => return None,
                    _ => {}
                }
                let sel_start = j;
                while j < c.len() && !c[j].is_whitespace() && c[j] != '{' {
                    j += 1;
                }
                let sel: String = c[sel_start..j].iter().collect();
                while j < c.len() && c[j].is_whitespace() {
                    j += 1;
                }
                if c.get(j) != Some(&'{') {
                    return None;
                }
                let (body, next) = parse_parts(c, j + 1, plural)?;
                forms.push((sel, body));
                j = next;
            }
            out.push(if plural { Part::Plural(name, forms) } else { Part::Select });
            i = j;
            continue;
        }
        if ch == '}' {
            flush(&mut buf, &mut out);
            return Some((out, i + 1));
        }
        if ch == '#' && in_plural {
            flush(&mut buf, &mut out);
            out.push(Part::Hash);
            i += 1;
            continue;
        }
        // ICU quoting: '{' is a literal brace, '' a quote ({{x}} excepted).
        if ch == '\'' && matches!(c.get(i + 1), Some('{' | '}' | '#' | '\'')) && !(c.get(i + 1) == Some(&'{') && c.get(i + 2) == Some(&'{')) {
            if c[i + 1] == '\'' {
                buf.push('\'');
                i += 2;
                continue;
            }
            let end = (i + 1..c.len()).find(|&k| c[k] == '\'').unwrap_or(c.len());
            buf.extend(&c[i + 1..end]);
            i = end + 1;
            continue;
        }
        buf.push(ch);
        i += 1;
    }
    flush(&mut buf, &mut out);
    Some((out, i))
}

fn arg_names(parts: &[Part], out: &mut Vec<String>) {
    for p in parts {
        match p {
            Part::Arg(n) if !out.contains(n) => out.push(n.clone()),
            Part::Plural(_, forms) => {
                // 'other' first, as the generator numbers them
                let mut f: Vec<&(String, Vec<Part>)> = forms.iter().collect();
                f.sort_by_key(|(s, _)| (s != "other", s.clone()));
                for (_, body) in f {
                    arg_names(body, out);
                }
            }
            _ => {}
        }
    }
}

fn render(parts: &[Part], args: &[String], plural_var: Option<&str>) -> Option<String> {
    let mut out = String::new();
    for p in parts {
        match p {
            Part::Text(t) => out.push_str(t),
            Part::Hash => out.push_str("%n"),
            Part::Arg(n) if Some(n.as_str()) == plural_var => out.push_str("%n"),
            Part::Arg(n) => out.push_str(&format!("%{}", args.iter().position(|a| a == n)? + 1)),
            _ => return None,
        }
    }
    Some(out)
}

/// A Teams message in Qt's form, its placeholders numbered by `args` (the
/// en-us order): a string, or a plural message's forms; None for what Qt's
/// form can't hold (selects, two plurals, a placeholder en-us lacks).
pub fn to_qt(text: &str, args: &[String]) -> Option<Value> {
    let parts = parse_message(text)?;
    let plurals: Vec<&Part> = parts.iter().filter(|p| matches!(p, Part::Plural(..))).collect();
    if parts.iter().any(|p| matches!(p, Part::Select)) || plurals.len() > 1 {
        return None;
    }
    let Some(Part::Plural(var, forms)) = plurals.first().copied() else {
        return render(&parts, args, None).map(Value::String);
    };
    let k = parts.iter().position(|p| matches!(p, Part::Plural(..)))?;
    let mut m = Map::new();
    for (sel, body) in forms {
        let mut whole = parts[..k].to_vec();
        whole.extend(body.iter().cloned());
        whole.extend(parts[k + 1..].iter().cloned());
        m.insert(sel.clone(), Value::String(render(&whole, args, Some(var))?.trim().to_string()));
    }
    m.contains_key("other").then_some(Value::Object(m))
}

/// The en-us placeholder order of a message (its plural count excluded).
pub fn message_args(text: &str) -> Vec<String> {
    let Some(parts) = parse_message(text) else { return Vec::new() };
    let vars: Vec<String> = parts.iter().filter_map(|p| if let Part::Plural(v, _) = p { Some(v.clone()) } else { None }).collect();
    let mut names = Vec::new();
    arg_names(&parts, &mut names);
    names.retain(|n| !vars.contains(n));
    names
}

// ------------------------------------------------------------ the name

/// Teams' product name in a translation as OST ("Microsoft Teams" and
/// "Teams", inflected forms kept: "Teamsista" -> "OST:ista" in Finnish,
/// "Teamsbe" -> "OST-be" in Hungarian, "Teams를" -> "OST를").
pub fn ostify(text: &str, locale: &str) -> String {
    let joiner = match locale.split('-').next().unwrap_or_default() {
        "fi" | "et" => ":",
        "hu" | "uz" | "kk" => "-",
        _ => "",
    };
    let t = text.replace("Microsoft Teams", "Teams");
    let chars: Vec<char> = t.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let at_word = i == 0 || !chars[i - 1].is_alphanumeric();
        if at_word && chars[i..].starts_with(&['T', 'e', 'a', 'm', 's']) {
            let mut j = i + 5;
            while j < chars.len() && chars[j].is_alphanumeric() {
                j += 1;
            }
            out.push_str("OST");
            if j > i + 5 {
                out.push_str(joiner);
                out.extend(&chars[i + 5..j]);
            }
            i = j;
            continue;
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

fn ostify_value(v: Value, locale: &str) -> Value {
    match v {
        Value::String(s) => Value::String(ostify(&s, locale)),
        Value::Object(m) => Value::Object(m.into_iter().map(|(k, v)| (k, ostify_value(v, locale))).collect()),
        v => v,
    }
}

// ------------------------------------------------------------ catalogue

/// The catalogue for `locale`: each id's translation in Qt's form.
pub fn build(ids: &[IdRow], strings: &Strings, locale: &str) -> Map<String, Value> {
    let mut out = Map::new();
    for IdRow(source, _, id, args, _) in ids {
        if out.contains_key(id) {
            continue;
        }
        let Some((ns, key)) = id.split_once(':') else { continue };
        let Some(text) = strings.get(ns).and_then(|t| t.get(key)) else { continue };
        // a translation may only use en-us's placeholders
        if message_args(text).iter().any(|a| !args.contains(a)) {
            continue;
        }
        let Some(q) = to_qt(text, args) else { continue };
        out.insert(id.clone(), if source.contains("OST") { ostify_value(q, locale) } else { q });
    }
    out
}

/// A short fingerprint of ids.json (a cached catalogue is rebuilt when OST's
/// strings change). FNV-1a, stable across builds.
pub fn fingerprint(data: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in data.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}")
}

/// Download `locale`'s string resources from Teams' CDN and build its
/// catalogue: `{"teamsVersion", "ids", "locale", "strings": {id: …}}`.
pub async fn fetch(client: &reqwest::Client, res: &Resources, ids: &[IdRow], ids_fingerprint: &str, locale: &str) -> anyhow::Result<Value> {
    let files = res.files.get(locale).ok_or_else(|| anyhow::anyhow!("no Teams strings for {locale}"))?;
    let gets = files.iter().map(|f| {
        let url = format!("{}{}", res.base, f);
        async move {
            let r = client.get(&url).send().await?.error_for_status()?;
            anyhow::Ok(decode_body(&r.bytes().await?)?)
        }
    });
    let bodies = futures::future::try_join_all(gets).await?;
    let mut strings = Strings::new();
    for b in &bodies {
        parse_chunk(b, &mut strings);
    }
    let cat = build(ids, &strings, locale);
    if cat.is_empty() {
        anyhow::bail!("Teams' {locale} resources held none of OST's strings");
    }
    Ok(serde_json::json!({
        "teamsVersion": res.teams_version,
        "ids": ids_fingerprint,
        "locale": locale,
        "strings": cat,
    }))
}

/// A resource's text. Teams' CDN keeps some of them gzipped and sends them
/// so whatever the request asked for.
fn decode_body(b: &[u8]) -> anyhow::Result<String> {
    if b.starts_with(&[0x1f, 0x8b]) {
        use std::io::Read;
        let mut s = String::new();
        flate2::read::GzDecoder::new(b).read_to_string(&mut s)?;
        return Ok(s);
    }
    Ok(String::from_utf8(b.to_vec())?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_teams_locale_chunks() {
        let js = r#""use strict";(this.w=this.w||[]).push([[1],{2:(t,e,n)=>{n.r(e),n.d(e,{default:()=>i});const i={namespace:"desktop",locale:"de-de",translations:{k548bytkb:"Kennwort f\xFCr Microsoft Teams eingeben",kx:"Zeile\neins ä 😀",'q y':"x"}}}}]);const j={namespace:"activity",locale:"de-de",translations:{ka:"Aktivität"}}"#;
        let mut s = Strings::new();
        parse_chunk(js, &mut s);
        assert_eq!(s["desktop"]["k548bytkb"], "Kennwort für Microsoft Teams eingeben");
        assert_eq!(s["desktop"]["kx"], "Zeile\neins ä 😀");
        assert_eq!(s["desktop"]["q y"], "x");
        assert_eq!(s["activity"]["ka"], "Aktivität");
    }

    #[test]
    fn messages_in_qt_form() {
        let a = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(to_qt("{{name}} schreibt", &a(&["name"])), Some(Value::String("%1 schreibt".into())));
        // a translation may reorder placeholders; numbering follows en-us
        assert_eq!(to_qt("{{b}} vor {{a}}", &a(&["a", "b"])), Some(Value::String("%2 vor %1".into())));
        assert_eq!(to_qt("{0} von {1} Sternen", &a(&["0", "1"])), Some(Value::String("%1 von %2 Sternen".into())));
        let p = to_qt("{n, plural, =1{eine Nachricht} one{# Nachricht} few {# Nachrichten} other{# Nachrichten}}", &[]).unwrap();
        assert_eq!(p["=1"], "eine Nachricht");
        assert_eq!(p["few"], "%n Nachrichten");
        assert_eq!(p["other"], "%n Nachrichten");
        let p = to_qt("{{who}} hat {c, plural, one{# Datei} other{# Dateien}} geteilt", &a(&["who"])).unwrap();
        assert_eq!(p["one"], "%1 hat %n Datei geteilt");
        assert_eq!(to_qt("'{{x}}' ist ungültig", &a(&["x"])), Some(Value::String("'%1' ist ungültig".into())));
        assert_eq!(to_qt("{g, select, m{er} other{sie}}", &[]), None);
        assert_eq!(message_args("{c, plural, one{{{a}} #} other{{{a}} und {{b}}}}"), a(&["a", "b"]));
        assert_eq!(to_qt("{{unbekannt}}", &a(&["name"])), None);
        // Teams' empty components are placeholders too
        assert_eq!(message_args("<0></0> added <1></1> and {otherTargets} to the chat."), a(&["<0>", "<1>", "otherTargets"]));
        assert_eq!(to_qt("<0></0> hat <1></1> zum Chat hinzugefügt.", &a(&["<0>", "<1>"])), Some(Value::String("%1 hat %2 zum Chat hinzugefügt.".into())));
        assert_eq!(to_qt("قام <1/> بإضافة <0></0>", &a(&["<0>", "<1>"])), Some(Value::String("قام %2 بإضافة %1".into())));
        assert_eq!(to_qt("<0><0></0></0> wurden erstellt", &a(&["<0>"])), Some(Value::String("%1 wurden erstellt".into())));
        assert_eq!(to_qt("<0>Link</0> und <b>", &[]), Some(Value::String("<0>Link</0> und <b>".into())));
    }

    #[test]
    fn teams_name_reads_ost() {
        assert_eq!(ostify("Informationen zu Microsoft Teams", "de-de"), "Informationen zu OST");
        assert_eq!(ostify("diese Teams-App", "de-de"), "diese OST-App");
        assert_eq!(ostify("Tietoja Teamsista", "fi-fi"), "Tietoja OST:ista");
        assert_eq!(ostify("Indítsa újra a Teamst", "hu-hu"), "Indítsa újra a OST-t");
        assert_eq!(ostify("Teams를 다시 시작", "ko-kr"), "OST를 다시 시작");
        assert_eq!(ostify("tat-Teams", "mt-mt"), "tat-OST");
        assert_eq!(ostify("Steams", "en-us"), "Steams");
    }

    #[test]
    fn catalogue_from_ids() {
        let ids: Vec<IdRow> = serde_json::from_str(r#"[["About OST","","framework:ka",[]],["%1 is typing","","m:kb",["name"]],["%n days","","c:kc",[],{"one":"%n day","other":"%n days"}],["Gone","","x:kd",[]]]"#).unwrap();
        let mut s = Strings::new();
        s.entry("framework".into()).or_default().insert("ka".into(), "Informationen zu Teams".into());
        s.entry("m".into()).or_default().insert("kb".into(), "{{name}} schreibt".into());
        s.entry("c".into()).or_default().insert("kc".into(), "{n, plural, one{# Tag} other{# Tage}}".into());
        let cat = build(&ids, &s, "de-de");
        assert_eq!(cat["framework:ka"], "Informationen zu OST");
        assert_eq!(cat["m:kb"], "%1 schreibt");
        assert_eq!(cat["c:kc"]["one"], "%n Tag");
        assert!(!cat.contains_key("x:kd"));
        use std::io::Write;
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all("namespace:\"x\" ü".as_bytes()).unwrap();
        assert_eq!(decode_body(&gz.finish().unwrap()).unwrap(), "namespace:\"x\" ü");
        assert_eq!(decode_body("plain".as_bytes()).unwrap(), "plain");
        assert_eq!(fingerprint("abc"), fingerprint("abc"));
        assert_ne!(fingerprint("abc"), fingerprint("abd"));
    }
}
