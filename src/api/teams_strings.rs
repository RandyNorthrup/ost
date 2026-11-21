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
//! Text Teams shows from its other bundles (the clip recorder, OneDrive's
//! and Stream's web apps, …) keeps its translations outside that table:
//! webpack chunks whose modules are JSON string tables, one chunk per
//! language (teams_resources.json's `extra`, also pinned to the build that
//! Teams 26304 loads). Their ids are `x.<source>:<module>.<key path>`.
//!
//! The Downloads panel is WebView2's own downloads hub, whose text is only
//! in the WebView2 runtime's `Locales/<lang>.pak` resource packs. Microsoft
//! serves the runtime as one cabinet (the WebView2 Fixed Version runtime);
//! OST fetches by HTTP range just the few MSZIP blocks that hold the
//! strings it needs (`kind: "cabpak"`, desktop/i18n/cabpak.py lists them
//! per language) and inflates them with `mszip_known`.
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
    /// String tables from Teams' other bundles, by namespace (`x.…`).
    #[serde(default)]
    pub extra: HashMap<String, ExtraSource>,
}

/// One of Teams' other string bundles: a webpack chunk of JSON modules per
/// language.
#[derive(Debug, Clone, Deserialize)]
pub struct ExtraSource {
    /// Where its files are.
    pub base: String,
    /// Its keys start with the module's id (the same in every language's
    /// chunk); else only the key path counts.
    #[serde(default)]
    pub ids: bool,
    /// "json": modules holding `JSON.parse('…')` tables (OneDrive's resx
    /// chunks); "esm": an ES module exporting object literals
    /// (`const n={…};…e.common=n`, the clip recorder's); "flatjson": a
    /// plain JSON table (Outlook's calendar).
    #[serde(default)]
    pub kind: String,
    /// Each locale's file (under `base`).
    pub files: HashMap<String, String>,
    /// "cabpak": each locale's byte ranges of the cabinet at `base`.
    #[serde(default)]
    pub parts: HashMap<String, CabPart>,
}

/// One language's strings in the WebView2 runtime cabinet: the byte ranges
/// to fetch (`[start, end)`, each starting at an MSZIP block, and the
/// offset in the cabinet's folder that block inflates to) and each needed
/// resource's (folder offset, size).
#[derive(Debug, Clone, Default, Deserialize)]
pub struct CabPart {
    pub segments: Vec<(u64, u64, u64)>,
    pub res: HashMap<String, (u64, usize)>,
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

/// The strings in a webpack chunk whose modules are JSON tables
/// (`7680(f){f.exports=JSON.parse('{"a":"Add Comment",…}')}`), by
/// `<module>.<key path>` (or the key path alone without `with_ids`).
pub fn parse_json_modules(js: &str, with_ids: bool) -> HashMap<String, String> {
    const MARK: &str = ".exports=JSON.parse(";
    let mut out = HashMap::new();
    let mut from = 0;
    while let Some(p) = js[from..].find(MARK) {
        let at = from + p;
        from = at + MARK.len();
        let Some((text, end)) = matches!(js.as_bytes().get(from), Some(b'\'' | b'"' | b'`')).then(|| js_string(js, from)).flatten() else {
            continue;
        };
        from = end;
        let Ok(v) = serde_json::from_str::<Value>(&text) else { continue };
        let prefix = if with_ids {
            match module_id(&js[..at]) {
                Some(id) => id.to_string(),
                None => continue,
            }
        } else {
            String::new()
        };
        flatten(&v, prefix, &mut out);
    }
    out
}

/// The strings an ES module exports as object literals: `const n={a:"…",
/// b:{c:"…"}},t={…};…e.common=n,e.header=t` gives `common.a`,
/// `common.b.c`, `header.…`.
pub fn parse_esm_tables(js: &str) -> HashMap<String, String> {
    let b = js.as_bytes();
    let ident = |c: u8| c.is_ascii_alphanumeric() || c == b'_' || c == b'$';
    // every `<name>={` object literal, by its variable
    let mut objects: HashMap<&str, Value> = HashMap::new();
    let mut i = 0;
    while let Some(p) = js[i..].find("={") {
        let eq = i + p;
        i = eq + 1;
        let mut s = eq;
        while s > 0 && ident(b[s - 1]) {
            s -= 1;
        }
        if s == eq || (s > 0 && b[s - 1] == b'.') {
            continue;
        }
        if let Some((v, end)) = object_literal(js, eq + 1) {
            objects.insert(&js[s..eq], v);
            i = end;
        }
    }
    // `e.<export>=<variable>` names them
    let mut out = HashMap::new();
    let mut i = 0;
    while let Some(p) = js[i..].find('=') {
        let eq = i + p;
        i = eq + 1;
        let mut v = eq + 1;
        while v < b.len() && ident(b[v]) {
            v += 1;
        }
        let Some(obj) = objects.get(&js[eq + 1..v]) else { continue };
        if !matches!(b.get(v), Some(b',' | b'}' | b';')) {
            continue;
        }
        let mut s = eq;
        while s > 0 && ident(b[s - 1]) {
            s -= 1;
        }
        if s == eq || s < 2 || b[s - 1] != b'.' || !ident(b[s - 2]) {
            continue;
        }
        flatten(obj, js[s..eq].to_string(), &mut out);
    }
    out
}

/// A JS object literal of strings and nested objects at `i` (its `{`);
/// other values (numbers, `!0`) are skipped. None if it isn't one.
fn object_literal(js: &str, i: usize) -> Option<(Value, usize)> {
    let b = js.as_bytes();
    let ws = |j: &mut usize| {
        while *j < b.len() && b[*j].is_ascii_whitespace() {
            *j += 1;
        }
    };
    if b.get(i) != Some(&b'{') {
        return None;
    }
    let mut j = i + 1;
    let mut map = Map::new();
    loop {
        ws(&mut j);
        match *b.get(j)? {
            b'}' => return Some((Value::Object(map), j + 1)),
            b',' => {
                j += 1;
                continue;
            }
            _ => {}
        }
        let key = if matches!(b[j], b'"' | b'\'') {
            let (k, n) = js_string(js, j)?;
            j = n;
            k
        } else {
            let s = j;
            while j < b.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_' || b[j] == b'$') {
                j += 1;
            }
            if j == s {
                return None;
            }
            js[s..j].to_string()
        };
        ws(&mut j);
        if b.get(j) != Some(&b':') {
            return None;
        }
        j += 1;
        ws(&mut j);
        match *b.get(j)? {
            b'"' | b'\'' | b'`' => {
                let (v, n) = js_string(js, j)?;
                // a template with substitutions isn't a plain string
                if b[j] == b'`' && v.contains("${") {
                    j = n;
                    continue;
                }
                map.insert(key, Value::String(v));
                j = n;
            }
            b'{' => {
                let (v, n) = object_literal(js, j)?;
                map.insert(key, v);
                j = n;
            }
            _ => {
                // skip a simple value
                while j < b.len() && !matches!(b[j], b',' | b'}') {
                    j += 1;
                }
            }
        }
    }
}

/// The webpack module id just before `…{f.exports`: the digits before the
/// `(f)` or `:function(e)` that start the module.
fn module_id(before: &str) -> Option<&str> {
    let mut start = before.len().saturating_sub(64);
    while !before.is_char_boundary(start) {
        start += 1;
    }
    let tail = &before[start..];
    let b = tail.as_bytes();
    // the last "<digits>(" or "<digits>:" in the tail
    let mut i = b.len();
    while i > 0 {
        i -= 1;
        if b[i] == b'(' || b[i] == b':' {
            let mut j = i;
            while j > 0 && b[j - 1].is_ascii_digit() {
                j -= 1;
            }
            if j < i && (j == 0 || !(b[j - 1].is_ascii_alphanumeric() || b[j - 1] == b'_' || b[j - 1] == b'$')) {
                return Some(&tail[j..i]);
            }
        }
    }
    None
}

fn flatten(v: &Value, prefix: String, out: &mut HashMap<String, String>) {
    match v {
        Value::Object(m) => {
            for (k, x) in m {
                flatten(x, if prefix.is_empty() { k.clone() } else { format!("{prefix}.{k}") }, out);
            }
        }
        Value::String(s) => {
            out.insert(prefix, s.clone());
        }
        _ => {}
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
    let (mut parts, mut i) = parse_parts(&chars, 0, false)?;
    // a brace closing nothing is literal
    while i < chars.len() {
        parts.push(Part::Text("}".into()));
        let (more, next) = parse_parts(&chars, i, false)?;
        parts.extend(more);
        i = next;
    }
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
                // not a placeholder: a literal brace (Teams' i18next texts)
                buf.push('{');
                i += 1;
                continue;
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
            if kind == "number" {
                // `{count, number}` (Loop's): the value as it is
                let close = (j..c.len()).find(|&k| c[k] == '}')?;
                out.push(Part::Arg(name));
                i = close + 1;
                continue;
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
            // `#` is formatted in the language's numbering system (Teams'
            // ICU messages: Arabic-Indic digits in Arabic); the count named
            // as an argument ({days}) is written as it is: %N.
            Part::Hash => out.push_str("%n"),
            Part::Arg(n) if Some(n.as_str()) == plural_var => out.push_str("%N"),
            Part::Arg(n) => out.push_str(&format!("%{}", args.iter().position(|a| a == n)? + 1)),
            _ => return None,
        }
    }
    Some(out)
}

fn plural_forms(var: &str, forms: &[(String, Vec<Part>)], before: &[Part], after: &[Part], args: &[String], trim: bool) -> Option<Map<String, Value>> {
    let mut m = Map::new();
    for (sel, body) in forms {
        let mut whole = before.to_vec();
        whole.extend(body.iter().cloned());
        whole.extend(after.iter().cloned());
        let r = render(&whole, args, Some(var))?;
        m.insert(sel.clone(), Value::String(if trim { r.trim().to_string() } else { r }));
    }
    m.contains_key("other").then_some(m)
}

/// A Teams message in Qt's form, its placeholders numbered by `args` (the
/// en-us order): a string, or a plural message's forms. A message with
/// several plurals ("{hour, plural, …} {min, plural, …}") becomes its
/// segments: text, and `{"var": name, "forms": {…}}` for each count. None
/// for what that can't hold (selects, a placeholder en-us lacks).
pub fn to_qt(text: &str, args: &[String]) -> Option<Value> {
    let parts = parse_message(text)?;
    let plurals: Vec<&Part> = parts.iter().filter(|p| matches!(p, Part::Plural(..))).collect();
    if parts.iter().any(|p| matches!(p, Part::Select)) {
        return None;
    }
    match plurals.as_slice() {
        [] => render(&parts, args, None).map(Value::String),
        [Part::Plural(var, forms)] => {
            let k = parts.iter().position(|p| matches!(p, Part::Plural(..)))?;
            plural_forms(var, forms, &parts[..k], &parts[k + 1..], args, true).map(Value::Object)
        }
        _ => {
            let mut segs = Vec::new();
            for p in &parts {
                segs.push(match p {
                    Part::Plural(var, forms) => serde_json::json!({ "var": var, "forms": plural_forms(var, forms, &[], &[], args, false)? }),
                    other => Value::String(render(std::slice::from_ref(other), args, None)?),
                });
            }
            Some(Value::Array(segs))
        }
    }
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
        // a segment's "var" is Teams' name for a count ("hour"): no product name in it
        Value::Object(m) => Value::Object(m.into_iter().map(|(k, v)| (k.clone(), if k == "var" { v } else { ostify_value(v, locale) })).collect()),
        Value::Array(a) => Value::Array(a.into_iter().map(|v| ostify_value(v, locale)).collect()),
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
    // Teams' other bundles: a language a bundle lacks (or one that won't
    // download) leaves its text in English, as in Teams.
    let extras = res.extra.iter().filter_map(|(ns, src)| {
        let file = src.files.get(locale)?;
        let url = format!("{}{}", src.base, file);
        Some(async move {
            let got = async {
                if src.kind == "cabpak" {
                    return cab_strings(client, src, locale).await;
                }
                let r = client.get(&url).send().await?.error_for_status()?;
                let body = decode_body(&r.bytes().await?)?;
                anyhow::Ok(match src.kind.as_str() {
                    "esm" => parse_esm_tables(&body),
                    "flatjson" => {
                        let mut t = HashMap::new();
                        if let Ok(v) = serde_json::from_str::<Value>(&body) {
                            flatten(&v, String::new(), &mut t);
                        }
                        t
                    }
                    _ => parse_json_modules(&body, src.ids),
                })
            }
            .await;
            (ns, url, got)
        })
    });
    for (ns, url, got) in futures::future::join_all(extras).await {
        match got {
            // Their texts aren't ICU: an apostrophe is just one ("Filter
            // by '{0}'"), so it is quoted as ICU's ''.
            Ok(table) => strings.entry(ns.clone()).or_default().extend(table.into_iter().map(|(k, v)| (k, v.replace('\'', "''")))),
            Err(e) => tracing::warn!("app language {locale}: {url}: {e:#}"),
        }
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

/// A language's strings from the WebView2 runtime cabinet: its byte ranges
/// fetched by HTTP range and inflated (`mszip_known`); a resource counts
/// only when every byte of it came out exact.
async fn cab_strings(client: &reqwest::Client, src: &ExtraSource, locale: &str) -> anyhow::Result<HashMap<String, String>> {
    let part = src.parts.get(locale).ok_or_else(|| anyhow::anyhow!("no ranges"))?;
    let mut out = HashMap::new();
    for &(start, end, uoff) in &part.segments {
        anyhow::ensure!(end > start && end - start <= 8 << 20, "bad range");
        let r = client.get(&src.base).header(reqwest::header::RANGE, format!("bytes={start}-{}", end - 1)).send().await?.error_for_status()?;
        anyhow::ensure!(r.status() == reqwest::StatusCode::PARTIAL_CONTENT, "no range reply");
        let body = r.bytes().await?;
        anyhow::ensure!(body.len() as u64 == end - start, "short range");
        let (data, known) = mszip_known(&body)?;
        for (id, &(o, n)) in &part.res {
            let Some(i) = o.checked_sub(uoff).map(|i| i as usize) else { continue };
            let Some(bytes) = data.get(i..i + n) else { continue };
            if known[i..i + n].iter().all(|&k| k)
                && let Ok(t) = std::str::from_utf8(bytes)
            {
                out.insert(id.clone(), pak_text(t));
            }
        }
    }
    Ok(out)
}

/// MSZIP blocks (a cabinet's CFDATA: checksum, compressed and uncompressed
/// size, then "CK" and a deflate stream that may refer to the 32 KiB before
/// it) inflated from a block whose history isn't at hand, and which bytes
/// came out exact: inflated twice, the unknown history all 0x00 and then
/// all 0xFF, a byte equal both times owes nothing to it.
pub fn mszip_known(data: &[u8]) -> anyhow::Result<(Vec<u8>, Vec<bool>)> {
    let a = mszip_inflate(data, 0)?;
    let b = mszip_inflate(data, 0xFF)?;
    let known = a.iter().zip(&b).map(|(x, y)| x == y).collect();
    Ok((a, known))
}

fn mszip_inflate(data: &[u8], fill: u8) -> anyhow::Result<Vec<u8>> {
    use std::io::Read;
    const HIST: usize = 32768;
    let mut hist = vec![fill; HIST];
    let mut out = Vec::new();
    let mut p = 0;
    while p + 8 <= data.len() {
        let cb = u16::from_le_bytes([data[p + 4], data[p + 5]]) as usize;
        let ucb = u16::from_le_bytes([data[p + 6], data[p + 7]]) as usize;
        let body = data.get(p + 8..p + 8 + cb).ok_or_else(|| anyhow::anyhow!("cut block"))?;
        anyhow::ensure!(body.starts_with(b"CK"), "not an MSZIP block");
        // the history as a stored deflate block, then the block's own data
        let mut stream = Vec::with_capacity(5 + HIST + cb);
        stream.push(0);
        stream.extend_from_slice(&(HIST as u16).to_le_bytes());
        stream.extend_from_slice(&(!(HIST as u16)).to_le_bytes());
        stream.extend_from_slice(&hist);
        stream.extend_from_slice(&body[2..]);
        let mut all = Vec::with_capacity(HIST + ucb);
        flate2::read::DeflateDecoder::new(&stream[..]).read_to_end(&mut all)?;
        let chunk = &all[HIST..];
        anyhow::ensure!(chunk.len() == ucb, "bad MSZIP block");
        out.extend_from_slice(chunk);
        let keep = HIST.min(chunk.len());
        hist.drain(..keep);
        hist.extend_from_slice(&chunk[chunk.len() - keep..]);
        p += 8 + cb;
    }
    Ok(out)
}

/// A WebView2 pak string in Teams' form: `$1` as `{0}`, `$$` a dollar.
fn pak_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        match (c, it.peek().copied()) {
            ('$', Some('$')) => {
                it.next();
                out.push('$');
            }
            ('$', Some(d @ '1'..='9')) => {
                it.next();
                out.push_str(&format!("{{{}}}", d as u32 - '1' as u32));
            }
            _ => out.push(c),
        }
    }
    out
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
    fn mszip_with_unknown_history() {
        // two MSZIP blocks, the second referring back into the first
        let hex = "0000000031007000434bcb48cdc9c95728cf2fca49d151c840e69464a42aa4e497e7e5e427a6142b649426291427561643d4e8a12a25411f00000000000f002900434bc3270b314121313d31334f1100";
        let raw: Vec<u8> = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect();
        let first = b"hello world, hello world, the downloads hub says hello. ".repeat(2);
        let (all, known) = mszip_known(&raw).unwrap();
        assert_eq!(&all[..112], &first[..]);
        assert_eq!(&all[112..], b"the downloads hub says hello world again!");
        assert!(known.iter().all(|&k| k));
        // from the second block alone: what it copies from the first is unknown
        let (part, known) = mszip_known(&raw[8 + 0x31..]).unwrap();
        assert_eq!(part.len(), 41);
        assert!(!known.iter().all(|&k| k));
        assert!(part.iter().zip(&known).zip(b"the downloads hub says hello world again!").all(|((a, k), b)| !k || a == b));
        assert_eq!(pak_text("Search $1 for $$2 $2"), "Search {0} for $2 {1}");
        assert_eq!(to_qt("characters: ~#%&*{}+/", &[]), Some(Value::String("characters: ~#%&*{}+/".into())));
        assert_eq!(to_qt("{count, number} groups giving access", &["count".into()]), Some(Value::String("%1 groups giving access".into())));
    }

    /// The Downloads panel's German strings out of Microsoft's WebView2
    /// cabinet, as the app fetches them (network: `cargo test -- --ignored
    /// webview2_cabinet_live`).
    #[tokio::test]
    #[ignore]
    async fn webview2_cabinet_live() {
        let res: Resources = serde_json::from_str(include_str!("../../desktop/i18n/teams_resources.json")).unwrap();
        let src = &res.extra["x.edge"];
        let got = cab_strings(&reqwest::Client::new(), src, "de-de").await.unwrap();
        assert_eq!(got.len(), src.parts["de-de"].res.len());
        assert_eq!(got["20707"], "Downloads durchsuchen");
        assert_eq!(got["20812"], "Übergeordneten Ordner öffnen");
    }

    #[test]
    fn json_module_chunks() {
        let js = r#"(self.odspNextWebpackJsonp=self.odspNextWebpackJsonp||[]).push([["ondemand.resx"],{7680(f){f.exports=JSON.parse('{"a":"Add Comment","b":"Don\u0027t {0}"}')},10655(f){f.exports=JSON.parse('{"x":{"y":"Deep"}}')}}]);"#;
        let m = parse_json_modules(js, true);
        assert_eq!(m.get("7680.a").map(String::as_str), Some("Add Comment"));
        assert_eq!(m.get("7680.b").map(String::as_str), Some("Don't {0}"));
        assert_eq!(m.get("10655.x.y").map(String::as_str), Some("Deep"));
        // multibyte text just before a module (German quotes)
        let de = format!(r#"push([["x"],{{1(f){{f.exports=JSON.parse('{{"a":"{}"}}')}},22(f){{f.exports=JSON.parse('{{"b":"c"}}')}}}}]);"#, "„Zitat“".repeat(20));
        assert_eq!(parse_json_modules(&de, true).get("22.b").map(String::as_str), Some("c"));
        let teams =r#"(self.webpackChunk=self.webpackChunk||[]).push([[752149],{204247:function(e){"use strict";e.exports=JSON.parse('{"common":{"addMusic":"Musik hinzufügen"}}')}}]);"#;
        let m = parse_json_modules(teams, false);
        assert_eq!(m.get("common.addMusic").map(String::as_str), Some("Musik hinzufügen"));
        assert_eq!(parse_json_modules(teams, true).get("204247.common.addMusic").map(String::as_str), Some("Musik hinzufügen"));
        let esm = r#"push([[752149],{204247:(Xe,e)=>{Object.defineProperty(e,Symbol.toStringTag,{value:"Module"});const n={direction:"ltr","_direction.comment":"x",addMusic:"Musik hinzufügen",n:1,deep:{a:'Tief'}},t={title:"Kopf"};e.common=n,e.header=t}}]);"#;
        let m = parse_esm_tables(esm);
        assert_eq!(m.get("common.addMusic").map(String::as_str), Some("Musik hinzufügen"));
        assert_eq!(m.get("common.deep.a").map(String::as_str), Some("Tief"));
        assert_eq!(m.get("header.title").map(String::as_str), Some("Kopf"));
        assert!(!m.contains_key("common.n"));
    }

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
        // a count named as an argument is written as it is (%N), # in the
        // language's digits (%n)
        let p = to_qt("{d, plural, =1{ und läuft in {d} Tag ab.} other{ und läuft in {d} Tagen ab.}}", &[]).unwrap();
        assert_eq!(p["other"], "und läuft in %N Tagen ab.");
        // several plurals: segments
        let p = to_qt("{hour, plural, =0{} other{#Std.}} {min, plural, =0{} other{#Min.}}", &[]).unwrap();
        assert_eq!(p, serde_json::json!([{"var": "hour", "forms": {"=0": "", "other": "%nStd."}}, " ", {"var": "min", "forms": {"=0": "", "other": "%nMin."}}]));
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
