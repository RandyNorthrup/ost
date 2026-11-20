---
id: TASK-0142
title: OST's text in Teams' app languages
status: To Do
assignee: []
created_date: '2026-11-15T01:31:00Z'
updated_date: '2026-11-20T01:04:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams offers 109 app languages (Settings ▸ General ▸ Language and regional formats). OST's text is English only, so its App language picker offers only Teams' 16 English locales (00d238b). To match Teams, OST's UI text needs to be available in Teams' other app languages and switch with App language after Save and restart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 App language offers every language Teams lists
- [ ] #2 After Save and restart, OST's own text appears in the chosen language, with Teams' wording for that language
- [x] #3 Right-to-left languages lay out right to left as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: Teams' full list of 109 app languages is stored, and Save and restart works for regional formats. Missing: only English is offered; no translations and no right-to-left layout. (Audit 2026-11-16)

2026-11-19 progress (TASK-0142 agent):
- Teams strings: 64 string locales (*-locale-<loc>-*.js in hashed-assets, 102 namespaces, 36,390 strings each); Teams maps its 109 app languages to them with its loader table (now src/api/regional_locale_map.json); RTL = its loader list (ar, he, fa among the 109).
- Built: desktop/i18n (teams_strings.py, l10n.py gen/flips, wrap.py, qmltok/qmlctx), ids.json + catalogs/<locale>.json (Teams wording, OST for Teams), src/i18n.cpp translator (plurals by CLDR, explicit ids via qsTr disambiguation), RtlMirror.qml per window, RtlTextAligner, flipInRtl icons, backend tr()/tr_n().
- QML marked with qsTr (~3,500 strings keyed to Teams ids); Rust UI strings via tr().
- Verified: German Settings live on linuxlt (XDG_CONFIG_HOME=~/l10n/xdg isolates desktop.json, which all profiles share). Teams on winpc captured in de-de and ar-sa, restored to English (Follow OS on).

2026-11-19 verified live:
- linuxlt (ost-test1, isolated XDG_CONFIG_HOME=~/l10n/xdg): --regional-test --regional-lang=ar-sa / de-de / en-us: Save and restart applies the language (log "app language ar-sa: strings ar-sa, right to left"); chat, Settings, Calendar captured; settings put back.
- RTL: whole window mirrored (src/i18n.cpp RtlLayout), text, pictures, web and video mirrored back, text right-aligned, flipInRtl icons mirrored, Arabic-Indic numerals and AM/PM via theme.fmt* (Qt.locale()). Matches Teams ar-sa on winpc (chat list, compose, settings tiles, rail on the right).
- Open: engine strings such as chat system messages ("X added Y to the chat", "Recording stopped") and call durations ("11m") stay English (the engine crate has no translator); the "(You)" suffix from the backend; about 970 OST strings have no Teams string (desktop/i18n/untranslated.txt, mostly OneDrive wording and OST-only text); Latin text in RTL elides at the end, Teams at the left.

2026-11-19 (user decision: no Microsoft translations in the repo): catalogues removed from history; OST now keeps only ids.json (ids + en-us placeholder order + OST English plural forms) and teams_resources.json (per-locale resource file names on https://statics.teams.cdn.office.net/teams-modular-packages/hashed-assets/, Teams 26304.1201.5310.7985; content hash in each name). On first use of a non-en-us language OST downloads them at start, builds the catalogue (src/api/teams_strings.rs) into ~/.cache/ost/i18n/<locale>.json atomically; offline it logs and stays English LTR. Rebased onto 58868f5.

2026-11-19 runtime catalogue verified on linuxlt: empty ~/.cache/ost/i18n, --regional-test de-de and ar-sa (Save and restart) downloaded 39 files and built 3,560 strings (1.7 s / 2.8 s) and showed Teams wording (ar-sa right to left). Offline (unshare -n): logs 'Teams strings unavailable ... showing English', no cache written, English LTR. Gotcha: Teams CDN sends some resources gzipped regardless of Accept-Encoding (decoded with flate2). Tests: lib 796 ok, desktop 29 ok.

- Merged 6799365 (2026-11-19): translations fetched at runtime from Teams' CDN (pinned to Teams 26304.1201.5310.7985) and built into ~/.cache/ost/i18n; no Microsoft strings in the repo or its history. 796 lib + 29 desktop tests passed; de-de and ar-sa verified from an empty cache; offline stays English.
- AC2 open: the engine's chat system messages and call durations stay English (no translator in the engine yet); the "(You)" suffix; strings Teams has that OST still words differently. Strings OST has that Teams doesn't stay English by design (untranslated.txt).
<!-- SECTION:NOTES:END -->
