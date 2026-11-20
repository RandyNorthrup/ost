---
id: TASK-0142
title: OST's text in Teams' app languages
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T01:31:00Z'
updated_date: '2026-11-20T02:54:00Z'
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

Built so far: all 109 app languages offered; OST's text in each language in Teams' own wording, fetched at runtime from Teams' CDN and built locally (no Microsoft strings in the repo); right to left for Arabic, Hebrew and others, verified live in de-de and ar-sa against Teams on winpc. Missing: the engine's chat system messages and call durations, the "(You)" suffix, and OST wordings that still differ from Teams' (in progress).

2026-11-19 AC2 finish (agent l10n2), in progress:
- Teams' string ids are k + base36(polyhash131("<ns>:<keyName>") mod 2^40) (+ _mf) (async-entry module 263249). A map of 31k ids to Teams' key names, built from the bundles (linuxlt ~/l10n2/revmap.json), picks the exact ids Teams' code uses.
- One translator: src/i18n.rs (teams_cli::i18n: ids.json compiled in, the catalogue, CLDR plurals, =N forms, ar/fa digits for %n). The QTranslator in desktop/src/i18n.cpp asks it (ost_i18n_lookup); backend tr()/tr_n() use it.
- Teams' empty components (<0></0>) are placeholders now (teams_strings.rs, l10n.py).
- Engine: chat system messages (messages.rs event_text, module 75579's keys), chat-list previews and recording rows (chat.rs) keyed to Teams ids. "(You)": chat_self_chat_header_title / autosuggest_self_tag, with plain_name for avatars (the QML regex strips are gone). Call durations: calling_duration_hours/minutes/seconds.
- Pending: engine sweep and untranslated.txt review (helper agents), ids.json regenerated on linuxlt (l10n.py gen with ~/l10n/all.json and ~/l10n/teams-loc), build, live de-de/ar-sa check with --regional-test --regional-chats=...

2026-11-19 AC2 engine/(You)/wording pass done (agent l10n2):
- One translator for QML, backend and engine: src/i18n.rs (teams_cli::i18n; ids.json compiled in, English plural forms without a catalogue, the downloaded catalogue after Save and restart, CLDR plurals and =N forms, Arabic/Persian digits for ICU counts). desktop/src/i18n.cpp's QTranslator asks it via ost_i18n_lookup; backend tr()/tr_n() call it.
- Teams' empty rich-text components (<0></0>) are placeholders (api::teams_strings, l10n.py); by text, l10n.py prefers Teams' plain-text strings. Rust tr_id()/tr_id_n() name a Teams id explicitly.
- Engine text keyed to the ids Teams' own code uses (found by hashing its key names: id = k + base36(polyhash131("ns:name") mod 2^40)):
  - chat system messages (event_text: module 75579's one/two/many forms, share-history plural, meeting variants), recording rows, chat-list previews;
  - activity feed, date groups, chat-list folders, send errors, tab menus/errors, channel-name errors, meeting info durations/recurrence, call quality survey, call health, roster tooltips, reader-text labels, room call titles, timer, reactions.
- Call durations (chat and channel call rows, Calls, attendance) use calling_duration_hours/minutes/seconds; "Call ended" is messaging's calling_callEnded.
- "(You)": chat_self_chat_header_title for your notes chat, autosuggest_self_tag for you in people lists; the engine sends plain_name/you, so the QML regex strips are gone.
- untranslated.txt pass: about 190 more strings switched to Teams' wording/ids (3,976 keyed, 800 left: OneDrive/SharePoint, Stream, Planner, OneNote, Outlook calendar and WebView2 pages Teams embeds (their strings aren't in Teams' string table), and OST-only text).
- Verified live on linuxlt (ost-test1, profile default, XDG_CONFIG_HOME=~/l10n/xdg), --regional-test --regional-lang=de-de|ar-sa --regional-chats="OST TEST 217 r3 town hall B|...": system messages, recording rows, "Besprechung beendet: 11 Min." / Arabic call durations, "OST Test 1 (Sie)" / "(أنت)", previews ("Aufzeichnung ist bereit") in Teams' wording; ar-sa right to left. Settings put back (Follow OS, English).
- Left: winpc Teams side-by-side of these rows (needs the user's OK); strings in Teams' separate bundles (Stream player/recorder, file preview) aren't in the catalogue; Call health values are translated in the quality report sent to GitHub.

2026-11-19 review fixes (agent l10n2):
- Trial pill "1 days left" is Teams' own: more_options_menu_premium_trial_days ("{{days}} days left") is filled with {days}, not an i18next count, and there is no singular or _one variant (async-entry dnt()). Kept as Teams shows it, with a comment in TitleBar.qml. No other count string lost its plural in the wording pass (checked every removed "=== 1" / "1 x" pair: they became Teams' plural messages).
- Raise hand: Teams' bar button (unified-bar-container-manager Y2) always labels it calling_raise_hand_icon_label "Raise", active while raised; only the tooltip and aria label switch to Lower ("Lower your hand"). Teams has no "Lower" label string. Full screen is the same: one "calling_full_screen" label with a toggled state (no "Exit full screen" string). OST matches both.
- Download/upload/error status: Teams' strings carry no details ("1 file was downloaded.", "Downloading...", "Uploading 1 file", "The file didn't download."); details go to OST's log. Kept.
- Reports to GitHub stay English: teams_cli::i18n::in_english() builds the call-health values for the call-quality report in English; english() maps a translated area/context (window titles, search tab, Find filters) back to OST's English in feedback_issue_url and the QML contexts (backend.englishText).
- Pending: Teams on winpc in de-de/ar-sa side by side (call durations' digits in Arabic, the German recording row, system messages), waiting for winpc to be free.
<!-- SECTION:NOTES:END -->
