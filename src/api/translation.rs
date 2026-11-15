//! Teams' automatic translation: your translation settings (Settings ▸
//! General ▸ Translation) and the rule that decides, from a message's
//! language stamp, whether Teams offers to translate it ("Translate |
//! Never translate German") or translates it by itself.
//!
//! Teams keeps these settings on the device (its TranslationSettingsV2 in
//! local storage; it copies them to your Microsoft account's language
//! settings only when ECS' enableTranslationSettingsRoaming is on, which it
//! isn't for this tenant), so OST keeps them in its own settings.

/// How to handle messages in other languages (Teams' translationMode).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mode {
    /// Ask me before translating (Teams' default).
    #[default]
    Suggest,
    /// Auto-translate all messages.
    Always,
    /// Never translate.
    Never,
}

impl Mode {
    /// Teams' names: SUGGEST_TRANSLATION, ALWAYS_TRANSLATE, NEVER_TRANSLATE.
    pub fn parse(s: &str) -> Mode {
        match s {
            "ALWAYS_TRANSLATE" => Mode::Always,
            "NEVER_TRANSLATE" => Mode::Never,
            _ => Mode::Suggest,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Mode::Suggest => "SUGGEST_TRANSLATION",
            Mode::Always => "ALWAYS_TRANSLATE",
            Mode::Never => "NEVER_TRANSLATE",
        }
    }
}

/// Your translation settings.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Settings {
    /// Translate messages into this language (a translator code: "en").
    pub target: String,
    pub mode: Mode,
    /// Never translate messages in these languages.
    pub known: Vec<String>,
}

/// A locale ("en-US") as a translator language code, as Teams normalises
/// it: lower case, the region dropped but a script kept ("sr-latn"), and
/// Chinese as zh-chs or zh-cht.
pub fn language_code(locale: &str) -> String {
    let l = locale.to_lowercase().replace('_', "-");
    if l.starts_with("zh-") {
        return match l.as_str() {
            "zh-cht" | "zh-hant" | "zh-hk" | "zh-tw" => "zh-cht".into(),
            _ => "zh-chs".into(),
        };
    }
    let Some(first) = l[1.min(l.len())..].find('-').map(|i| i + 1) else {
        return l;
    };
    let second = l[first + 1..].find('-').map(|i| i + first + 1).unwrap_or(l.len());
    // A four-letter script subtag stays.
    let end = if second - first == 5 { second } else { first };
    l[..end].to_string()
}

/// Teams' defaults: your app language, and that language as the one you
/// never want translated.
pub fn default_settings(locale: &str) -> Settings {
    let target = language_code(locale);
    Settings { target: target.clone(), mode: Mode::Suggest, known: vec![target] }
}

/// The language Teams reads from a message's languageStamp property
/// ("languages=de:100;nl:54;length:101;&detector=Bling") and whether it
/// trusts it (Teams' toSourceLanguageCode). `tuner` is ECS'
/// translationLanguageStampingTunerSettings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Source {
    pub code: String,
    pub high: bool,
}

pub fn source_language(stamp: &str, target: &str, tuner: &serde_json::Value) -> Option<Source> {
    let mut languages = "";
    let mut length: Option<&str> = None;
    let mut detector = "";
    for part in stamp.split('&') {
        match part.split_once('=') {
            Some(("languages", v)) => languages = v,
            Some(("length", v)) => length = Some(v),
            Some(("detector", v)) => detector = v,
            _ => {}
        }
    }
    let mut scores: Vec<(&str, i64)> = languages
        .split(';')
        .map(|e| {
            let (c, s) = e.split_once(':').unwrap_or((e, ""));
            (c, s.parse().unwrap_or(0))
        })
        .collect();
    let first = scores.first()?.0;
    if first == "null" || first.is_empty() {
        return None;
    }
    let code = first.to_string();
    if scores.last().is_some_and(|(c, _)| c.is_empty()) {
        scores.pop();
    }
    let low = Source { code: code.clone(), high: false };
    let length_entry = scores.last().is_some_and(|(c, _)| *c == "length");
    if length.is_none() && !length_entry {
        return Some(low);
    }
    let Some(pe) = tuner
        .get("settingsData")
        .and_then(|d| d.as_array())
        .and_then(|d| d.iter().find(|e| e.get("detector").and_then(|x| x.as_str()) == Some(detector)))
    else {
        return Some(low);
    };
    let Some(min_confidence) = pe.get("minConfidence").and_then(|x| x.as_i64()).filter(|c| *c != 0) else {
        return Some(low);
    };
    if target.is_empty() {
        return Some(low);
    }
    if target != code {
        let chars = match length {
            Some(l) => l.parse().unwrap_or(0),
            None => scores.last().map(|(_, s)| *s).unwrap_or(0),
        };
        if chars < min_chars(pe, &code) {
            return Some(low);
        }
        // Text that also reads well as your language is yours.
        if scores.iter().find(|(c, _)| *c == target).is_some_and(|(_, s)| *s >= min_confidence) {
            return Some(Source { code: target.to_string(), high: false });
        }
    }
    Some(Source { code, high: true })
}

/// The shortest text Teams trusts a detection for, by the language's script.
fn min_chars(pe: &serde_json::Value, code: &str) -> i64 {
    let script = match code {
        "ar" | "fa" | "ku" => "arabic",
        "ru" | "uk" | "bg" | "sr" | "sr-cyrl" | "mk" | "uz" => "cyrillic",
        "zh" | "zh-chs" | "zh-cht" | "ja" | "ko" => "han",
        "vi" | "en" | "de" | "fr" | "es" | "it" | "pt" | "ca" | "nl" | "pl" | "tr" | "sv" | "cs" | "da" | "hu" | "no" | "nb"
        | "ro" | "fi" | "ms" | "sk" | "et" | "hr" | "lt" | "sl" | "id" | "lv" | "gl" | "is" | "sq" | "nn" | "cy" | "af" | "mt"
        | "ga" | "eo" | "so" | "sw" | "bs" | "eu" | "az" | "ht" | "la" | "za" | "sr-latn" => "latin",
        _ => "",
    };
    let get = |o: Option<&serde_json::Value>, k: &str| o.and_then(|m| m.get(k)).and_then(|x| x.as_i64());
    get(pe.get("minCharMapOverrides"), code)
        .or_else(|| get(pe.get("minCharMap"), script))
        .or_else(|| get(pe.get("minCharMap"), "others"))
        .unwrap_or(5)
}

/// Whether Teams offers "Translate | Never translate …" on a message:
/// in Ask me mode for a trusted language that isn't yours, and in
/// Auto-translate mode once you've gone back to the original of a message
/// it translated (Teams' shouldSuggestTranslation).
pub fn suggest(settings: &Settings, source: Option<&Source>, showing_original_of_auto: bool) -> bool {
    let Some(src) = source.filter(|s| s.high) else { return false };
    if is_known(settings, &src.code) {
        return false;
    }
    match settings.mode {
        Mode::Suggest => true,
        Mode::Always => showing_original_of_auto,
        Mode::Never => false,
    }
}

/// Whether Teams translates the message by itself (Auto-translate all
/// messages, a trusted language that isn't yours).
pub fn auto_translate(settings: &Settings, source: Option<&Source>) -> bool {
    settings.mode == Mode::Always && source.is_some_and(|s| s.high && !is_known(settings, &s.code))
}

fn is_known(settings: &Settings, code: &str) -> bool {
    code == settings.target || settings.known.iter().any(|k| k == code)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tuner() -> serde_json::Value {
        serde_json::json!({"settingsData":[{"detector":"Bling","minConfidence":70,"minCharMap":{"latin":30,"cyrillic":35,"arabic":15,"hebrew":15,"han":15,"others":15},"minCharMapOverrides":{"zh-chs":10,"zh-cht":10,"ru":35}}]})
    }

    #[test]
    fn codes_as_teams_normalises_them() {
        assert_eq!(language_code("en-US"), "en");
        assert_eq!(language_code("de"), "de");
        assert_eq!(language_code("sr-Latn-RS"), "sr-latn");
        assert_eq!(language_code("zh-TW"), "zh-cht");
        assert_eq!(language_code("zh-CN"), "zh-chs");
        assert_eq!(language_code("pt_BR"), "pt");
        assert_eq!(default_settings("en-US"), Settings { target: "en".into(), mode: Mode::Suggest, known: vec!["en".into()] });
    }

    #[test]
    fn stamps_as_teams_reads_them() {
        let t = tuner();
        // OST TEST 139, German from OST Test 2: trusted.
        let de = source_language("languages=de:100;nl:54;sk:49;length:101;&detector=Bling", "en", &t).unwrap();
        assert_eq!(de, Source { code: "de".into(), high: true });
        // A table that also reads as English (99 ≥ 70): yours.
        let table = source_language("languages=de:100;en:99;fr:95;length:51;&detector=Bling", "en", &t).unwrap();
        assert_eq!(table, Source { code: "en".into(), high: false });
        // Too short to trust.
        let short = source_language("languages=de:100;nl:30;length:17;&detector=Bling", "en", &t).unwrap();
        assert!(!short.high);
        // No length, unknown detector, nothing detected.
        assert!(!source_language("languages=de:100;", "en", &t).unwrap().high);
        assert!(!source_language("languages=de:100;length:80;&detector=Other", "en", &t).unwrap().high);
        assert_eq!(source_language("languages=null:0;", "en", &t), None);
        assert_eq!(source_language("", "en", &t), None);
        // Your own language is trusted as is.
        assert!(source_language("languages=en:100;length:5;&detector=Bling", "en", &t).unwrap().high);
    }

    #[test]
    fn suggestions_and_auto_translation_follow_the_mode() {
        let de = Source { code: "de".into(), high: true };
        let mut s = default_settings("en-US");
        assert!(suggest(&s, Some(&de), false));
        assert!(!auto_translate(&s, Some(&de)));
        assert!(!suggest(&s, Some(&Source { code: "de".into(), high: false }), false));
        assert!(!suggest(&s, Some(&Source { code: "en".into(), high: true }), false));
        s.known.push("de".into());
        assert!(!suggest(&s, Some(&de), false));
        s.known.pop();
        s.mode = Mode::Always;
        assert!(auto_translate(&s, Some(&de)));
        assert!(!suggest(&s, Some(&de), false));
        assert!(suggest(&s, Some(&de), true));
        s.mode = Mode::Never;
        assert!(!suggest(&s, Some(&de), true) && !auto_translate(&s, Some(&de)));
        assert_eq!(Mode::parse("ALWAYS_TRANSLATE"), Mode::Always);
        assert_eq!(Mode::parse(Mode::Never.name()), Mode::Never);
        assert_eq!(Mode::parse("x"), Mode::Suggest);
    }
}
