//! Teams' language and regional formats (Settings ▸ General ▸ Language and
//! regional formats): the date and time patterns every view formats with.
//!
//! Teams takes them from the OS ("Follow OS settings", its default) or from
//! the app language you pick, whose culture brings its own short and long
//! date and time patterns (Teams' culture table, `regional_cultures.json`),
//! optionally overridden by one of Teams' eight date formats and four time
//! formats. Patterns are Windows' (.NET) as Teams keeps them; `to_qt`
//! turns one into a Qt format string. Changes apply after a restart, as in
//! Teams.

use serde::Deserialize;

/// A culture's formats (.NET patterns).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Formats {
    pub short_date: String,
    pub long_date: String,
    pub short_time: String,
    pub long_time: String,
    /// 0 Sunday … 6 Saturday.
    pub first_day_of_week: u8,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Culture {
    cultures: Vec<String>,
    #[serde(flatten)]
    formats: Formats,
}

/// One of Teams' app languages.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppLanguage {
    pub code: String,
    pub name: String,
    pub native_name: String,
}

fn cultures() -> &'static [Culture] {
    static C: std::sync::OnceLock<Vec<Culture>> = std::sync::OnceLock::new();
    C.get_or_init(|| serde_json::from_str(include_str!("regional_cultures.json")).expect("regional_cultures.json"))
}

/// Teams' app languages (its language picker's list).
pub fn app_languages() -> &'static [AppLanguage] {
    static L: std::sync::OnceLock<Vec<AppLanguage>> = std::sync::OnceLock::new();
    L.get_or_init(|| serde_json::from_str(include_str!("regional_languages.json")).expect("regional_languages.json"))
}

/// The app languages the language picker offers: all of Teams'. OST's
/// text in each is Teams' own (desktop/i18n's catalogues, one per string
/// locale; see `string_locale`).
pub fn available_app_languages() -> Vec<&'static AppLanguage> {
    app_languages().iter().collect()
}

/// The locales Teams ships its UI strings in (its `*-locale-<locale>-*`
/// string resources); OST has a catalogue for each.
pub const STRING_LOCALES: [&str; 63] = [
    "af-za", "ar-sa", "az-latn-az", "bg-bg", "bs-latn-ba", "ca-es", "ca-es-valencia", "cs-cz", "cy-gb", "da-dk", "de-de", "el-gr", "en-gb",
    "en-us", "es-es", "es-mx", "et-ee", "eu-es", "fa-ir", "fi-fi", "fil-ph", "fr-ca", "fr-fr", "gl-es", "he-il", "hi-in", "hr-hr", "hu-hu",
    "id-id", "is-is", "it-it", "ja-jp", "ka-ge", "kk-kz", "km-kh", "ko-kr", "lo-la", "lt-lt", "lv-lv", "mk-mk", "ms-my", "mt-mt", "nb-no",
    "nl-nl", "nn-no", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sq-al", "sr-cyrl-rs", "sr-latn-rs", "sv-se", "th-th",
    "tr-tr", "uk-ua", "uz-latn-uz", "vi-vn", "zh-cn", "zh-tw",
];

/// The string locale Teams shows a language in, as its loader picks it:
/// the language itself if Teams has its strings, else its table's
/// fallback for the language ("de-at" -> "de-de", "es-ar" -> "es-mx",
/// "zh-sg" -> "zh-cn"), else the fallback for its base language, else
/// en-us.
pub fn string_locale(code: &str) -> &'static str {
    static MAP: std::sync::OnceLock<std::collections::HashMap<String, String>> = std::sync::OnceLock::new();
    let map = MAP.get_or_init(|| serde_json::from_str(include_str!("regional_locale_map.json")).expect("regional_locale_map.json"));
    let c = code.trim().replace('_', "-").to_lowercase();
    let known = |l: &str| STRING_LOCALES.iter().copied().find(|s| *s == l);
    if let Some(l) = known(&c) {
        return l;
    }
    if let Some(l) = map.get(&c).and_then(|l| known(l)) {
        return l;
    }
    let base = c.split('-').next().unwrap_or_default();
    map.get(base).and_then(|l| known(l)).unwrap_or("en-us")
}

/// Whether Teams lays a language out right to left (its loader's list of
/// right-to-left languages, by base language).
pub fn is_rtl(code: &str) -> bool {
    const RTL: [&str; 70] = [
        "aao", "abh", "abv", "acm", "acq", "acw", "acx", "acy", "adf", "ads", "ae", "aeb", "aec", "afb", "ajp", "apc", "apd", "ar", "arb",
        "arc", "arq", "ars", "ary", "arz", "auz", "avl", "ayh", "ayl", "ayn", "ayp", "bbz", "bcc", "bqi", "ckb", "dv", "fa", "glk", "hbo",
        "he", "jpr", "ku", "men", "mzn", "nqo", "pbt", "pbu", "peo", "pes", "pga", "pnb", "prd", "prp", "prs", "ps", "pst", "sam", "sd",
        "shu", "sqr", "ssh", "ug", "ur", "xaa", "xmn", "ydd", "yhd", "yi", "yih", "yud", "pseudo_rtl",
    ];
    let base = code.trim().split(['-', '_']).next().unwrap_or_default().to_lowercase();
    RTL.contains(&base.as_str())
}

/// Teams' default formats (en-US, Windows).
pub fn default_formats() -> Formats {
    Formats {
        short_date: "M/d/yyyy".into(),
        long_date: "dddd, MMMM d, yyyy".into(),
        short_time: "h:mm tt".into(),
        long_time: "h:mm:ss tt".into(),
        first_day_of_week: 0,
    }
}

/// A culture's formats ("en-GB", any case, `_` or `-`), as Teams' table has
/// them; None for a culture it doesn't list.
pub fn culture_formats(culture: &str) -> Option<Formats> {
    let c = culture.replace('_', "-");
    cultures()
        .iter()
        .find(|e| e.cultures.iter().any(|x| x.eq_ignore_ascii_case(&c)))
        .map(|e| e.formats.clone())
}

/// Teams' Date format choices.
pub const DATE_FORMATS: [&str; 8] = ["d/M/yyyy", "dd-MM-yyyy", "dd.MM.yyyy", "dd/MM/yyyy", "M/d/yyyy", "yyyy-MM-dd", "yyyy.MM.dd", "yyyy/MM/dd"];

/// Teams' Time format choices (Windows): (short, long).
pub const TIME_FORMATS: [(&str, &str); 4] = [("HH:mm", "HH:mm:ss"), ("H:mm", "H:mm:ss"), ("hh:mm tt", "hh:mm:ss tt"), ("h:mm tt", "h:mm:ss tt")];

/// Your choices: follow the OS, or an app language with an optional date
/// format and time format (short patterns from the lists above).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Choice {
    pub follow_os: bool,
    pub app_language: String,
    pub date_format: String,
    pub time_format: String,
}

/// The formats in effect: the OS locale's culture when following the OS
/// (Teams' defaults when the table doesn't have it), else the app
/// language's, with your date and time formats over them.
pub fn resolve(choice: &Choice, os_locale: &str) -> Formats {
    if choice.follow_os {
        return culture_formats(os_locale).unwrap_or_else(default_formats);
    }
    let mut f = culture_formats(&choice.app_language).unwrap_or_else(default_formats);
    if DATE_FORMATS.contains(&choice.date_format.as_str()) {
        f.short_date = choice.date_format.clone();
    }
    if let Some((short, long)) = TIME_FORMATS.iter().find(|(s, _)| *s == choice.time_format) {
        f.short_time = short.to_string();
        f.long_time = long.to_string();
    }
    f
}

/// A pattern without its year, as Teams shows dates of this year ("M/d"
/// for "M/d/yyyy", "dd.MM." for "dd.MM.yyyy" in German).
pub fn without_year(pattern: &str, culture: &str) -> String {
    // Teams' regexes: some cultures keep the dot before the year.
    let lang = culture.split(['-', '_']).next().unwrap_or_default().to_lowercase();
    let keep_dot = ["bs", "cs", "de", "dsb", "fi", "gsw", "hr", "hsb", "hu", "is", "ko", "lb", "lv", "nb", "nds", "nn", "sk", "sl", "sr"]
        .contains(&lang.as_str())
        || culture.eq_ignore_ascii_case("fr-CH");
    let seps: &[char] = if keep_dot { &['/', '-', ','] } else { &['.', '/', '-', ','] };
    let chars: Vec<char> = pattern.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        // Separators (each with an optional space), then the year, then
        // trailing . / - go.
        let mut j = i;
        while j < chars.len() && seps.contains(&chars[j]) {
            j += 1;
            if j < chars.len() && chars[j] == ' ' {
                j += 1;
            }
        }
        let year_start = j;
        let mut matched = false;
        loop {
            if j < chars.len() && chars[j] == 'y' {
                j += 1;
                matched = true;
            } else if let Some(n) = ["年", "년", "'年'", "'년'"].iter().find_map(|w| {
                let w: Vec<char> = w.chars().collect();
                chars[j..].starts_with(&w).then_some(w.len())
            }) {
                j += n;
                matched = true;
            } else {
                break;
            }
        }
        if matched && j > year_start {
            while j < chars.len() && ['.', '/', '-'].contains(&chars[j]) {
                j += 1;
            }
            i = j;
            continue;
        }
        out.push(chars[i]);
        i += 1;
    }
    out.trim().to_string()
}

/// A .NET pattern as a Qt format string: Qt reads d/M/y/H/h/m/s and quoted
/// text the same way; the AM/PM designator (tt, t) is AP / A.
pub fn to_qt(pattern: &str) -> String {
    let mut out = String::new();
    let mut quoted = false;
    let chars: Vec<char> = pattern.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            quoted = !quoted;
            out.push(c);
        } else if !quoted && c == 't' {
            let run = chars[i..].iter().take_while(|x| **x == 't').count();
            out.push_str(if run >= 2 { "AP" } else { "A" });
            i += run;
            continue;
        } else {
            out.push(c);
        }
        i += 1;
    }
    out
}

/// The formats in effect for text the engine formats (the desktop sets
/// them at start; Teams' defaults until then).
fn current() -> &'static std::sync::RwLock<Formats> {
    static C: std::sync::OnceLock<std::sync::RwLock<Formats>> = std::sync::OnceLock::new();
    C.get_or_init(|| std::sync::RwLock::new(default_formats()))
}

pub fn set_current(f: Formats) {
    *current().write().unwrap() = f;
}

pub fn current_formats() -> Formats {
    current().read().unwrap().clone()
}

/// A .NET pattern as a chrono (strftime) format.
pub fn to_strftime(pattern: &str) -> String {
    let chars: Vec<char> = pattern.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            i += 1;
            while i < chars.len() && chars[i] != '\'' {
                if chars[i] == '%' {
                    out.push('%');
                }
                out.push(chars[i]);
                i += 1;
            }
            i += 1;
            continue;
        }
        let run = chars[i..].iter().take_while(|x| **x == c).count();
        let spec = match (c, run) {
            ('y', 1 | 2) => "%y",
            ('y', _) => "%Y",
            ('M', 1) => "%-m",
            ('M', 2) => "%m",
            ('M', 3) => "%b",
            ('M', _) => "%B",
            ('d', 1) => "%-d",
            ('d', 2) => "%d",
            ('d', 3) => "%a",
            ('d', _) => "%A",
            ('H', 1) => "%-H",
            ('H', _) => "%H",
            ('h', 1) => "%-I",
            ('h', _) => "%I",
            ('m', 1) => "%-M",
            ('m', _) => "%M",
            ('s', 1) => "%-S",
            ('s', _) => "%S",
            ('t', _) => "%p",
            ('%', _) => {
                out.push_str(&"%%".repeat(run));
                i += run;
                continue;
            }
            _ => {
                out.extend(std::iter::repeat_n(c, run));
                i += run;
                continue;
            }
        };
        out.push_str(spec);
        i += run;
    }
    out
}

fn fmt<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>, pattern: &str) -> String
where
    Tz::Offset: std::fmt::Display,
{
    t.format(&to_strftime(pattern)).to_string()
}

/// A time as the short time format shows it ("4:09 PM", "16:09").
pub fn short_time<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    fmt(t, &current_formats().short_time)
}

/// With seconds.
pub fn long_time<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    fmt(t, &current_formats().long_time)
}

/// A date as the short date format shows it ("11/14/2026").
pub fn short_date<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    fmt(t, &current_formats().short_date)
}

/// The short date with a two-digit year ("11/14/26").
pub fn short_date_yy<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    fmt(t, &current_formats().short_date.replace("yyyy", "yy"))
}

/// Short date and time ("11/14/2026 4:09 PM").
pub fn date_time<Tz: chrono::TimeZone>(t: &chrono::DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    format!("{} {}", short_date(t), short_time(t))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cultures_and_choices_as_teams_resolves_them() {
        assert_eq!(culture_formats("en-US"), Some(default_formats()));
        let gb = culture_formats("en_gb").unwrap();
        assert_eq!((gb.short_date.as_str(), gb.short_time.as_str(), gb.first_day_of_week), ("dd/MM/yyyy", "HH:mm", 1));
        assert_eq!(culture_formats("xx-YY"), None);
        assert_eq!(resolve(&Choice { follow_os: true, ..Default::default() }, "en_GB"), gb);
        assert_eq!(resolve(&Choice { follow_os: true, ..Default::default() }, "C"), default_formats());
        let c = Choice { follow_os: false, app_language: "en-gb".into(), date_format: "yyyy-MM-dd".into(), time_format: "h:mm tt".into() };
        let f = resolve(&c, "en-US");
        assert_eq!((f.short_date.as_str(), f.short_time.as_str(), f.long_time.as_str()), ("yyyy-MM-dd", "h:mm tt", "h:mm:ss tt"));
        assert_eq!(f.long_date, "dd MMMM yyyy");
        // A format that isn't one of Teams' choices is ignored.
        let f = resolve(&Choice { date_format: "nope".into(), ..c }, "en-US");
        assert_eq!(f.short_date, "dd/MM/yyyy");
    }

    #[test]
    fn languages_map_to_teams_string_locales() {
        assert_eq!(string_locale("de-at"), "de-de");
        assert_eq!(string_locale("es-AR"), "es-mx");
        assert_eq!(string_locale("zh-sg"), "zh-cn");
        assert_eq!(string_locale("zh_HK"), "zh-tw");
        assert_eq!(string_locale("en-029"), "en-us");
        assert_eq!(string_locale("en-au"), "en-gb");
        assert_eq!(string_locale("sv-fi"), "sv-se");
        assert_eq!(string_locale("ca-es-valencia"), "ca-es-valencia");
        assert_eq!(string_locale("pt"), "pt-br");
        assert_eq!(string_locale("xx-yy"), "en-us");
        // Every app language has Teams' strings: its own or a fallback's.
        for l in app_languages() {
            let s = string_locale(&l.code);
            assert!(s != "en-us" || l.code.starts_with("en-"), "{} has no strings", l.code);
        }
        assert!(is_rtl("ar-sa") && is_rtl("he-IL") && is_rtl("fa_IR") && is_rtl("ur") && !is_rtl("en-us"));
        assert_eq!(app_languages().iter().filter(|l| is_rtl(&l.code)).count(), 3);
    }

    #[test]
    fn year_goes_as_teams_strips_it() {
        assert_eq!(without_year("M/d/yyyy", "en-US"), "M/d");
        assert_eq!(without_year("dd/MM/yyyy", "en-GB"), "dd/MM");
        assert_eq!(without_year("yyyy-MM-dd", "en-US"), "MM-dd");
        assert_eq!(without_year("dd.MM.yyyy", "de-DE"), "dd.MM.");
        assert_eq!(without_year("dd.MM.yyyy", "ru-RU"), "dd.MM");
        assert_eq!(without_year("dddd, MMMM d, yyyy", "en-US"), "dddd, MMMM d");
        assert_eq!(without_year("yyyy/M/d", "ja-JP"), "M/d");
    }

    #[test]
    fn patterns_as_qt_formats() {
        assert_eq!(to_qt("h:mm tt"), "h:mm AP");
        assert_eq!(to_qt("hh:mm:ss tt"), "hh:mm:ss AP");
        assert_eq!(to_qt("HH:mm"), "HH:mm");
        assert_eq!(to_qt("dd MMMM yyyy 'at' t"), "dd MMMM yyyy 'at' A");
        assert_eq!(to_strftime("M/d/yyyy h:mm tt"), "%-m/%-d/%Y %-I:%M %p");
        assert_eq!(to_strftime("dd.MM.yyyy HH:mm:ss"), "%d.%m.%Y %H:%M:%S");
        assert_eq!(to_strftime("dddd, MMMM d 'at' h"), "%A, %B %-d at %-I");
        assert_eq!(to_strftime("'100%' yy"), "100%% %y");
        use chrono::TimeZone;
        let t = chrono::Utc.with_ymd_and_hms(2026, 1, 31, 16, 9, 5).unwrap();
        assert_eq!(fmt(&t, "M/d/yyyy h:mm tt"), "1/31/2026 4:09 PM");
        assert_eq!(fmt(&t, "dd/MM/yyyy HH:mm"), "31/01/2026 16:09");
        assert_eq!(available_app_languages().len(), 109);
        assert!(available_app_languages().iter().any(|l| l.code == "en-us"));
    }
}
