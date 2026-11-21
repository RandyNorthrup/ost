---
id: TASK-0233
title: 'App languages: strings from Teams'' other bundles'
status: In Progress
assignee: []
created_date: '2026-11-20T04:10:00Z'
updated_date: '2026-11-21T18:23:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0142: about 800 OST strings stay English because Teams keeps their translations outside its main string table: the Stream player and recorder, the file preview, and the web apps OST hosts or mirrors (OneDrive/SharePoint, Planner, OneNote, the Outlook calendar, the downloads panel). Teams has its own translations for these in other bundles.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's text for the Stream player, recorder, file preview and mirrored web-app screens appears in the chosen language with Teams' wording, fetched at runtime like the main catalogue (no Microsoft strings in the repo)
- [ ] #2 untranslated.txt lists only text that Teams itself has no translation for
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (agent tuiF) sources found (Teams 26304 and what it loads):
  - OneDrive web (file browser, Move/Copy picker, file preview, playlist picker): https://res.public.onecdn.static.microsoft/files/odsp-web-prod_2026-11-06.005/{file-browser-odb-teams,spofilepickerwebpack}/<lang>/{initial,ondemand}.resx.js (webpack JSON modules, keys <module>.<key>, lang = locale or its language: de, ar, pt-br, zh-cn, sr-latn-rs).
  - Clip recorder (OneCamera): Teams hashed-assets onecamera-locale-<lang>-<hash>.js (ES module object literals; en-us inside 707202-*.js), names from Teams' runtime-*.js (a.un/a.uh).
  - Stream player (OnePlayer): hashed-assets <lang>-strings-jsonThinRes-<hash>.js, en "english strings-<hash>.js".
  - Outlook calendar (hosted calendar): res.public.onecdn.static.microsoft/owamail/hashed-v1/resources/locale-consolidated/<folder>/owa.consolidated.hostedcalendar.runtime.h.4c09a120.json (flat JSON; folders en, de, pt, zh-hans, no, sr, sr-cyrl…).
  - Planner: res.public.onecdn.static.microsoft/msplanner/ui/static/releases/planner_prod/all/js/ uno-<lang>-resources-strings-json and planner-view-personal-<lang>-…-strings-json chunks (names from runtime.1e6b250318.bundle.js).
  - Meeting options: the options reply's translations, asked with Accept-Language (now sent in the app language).
  - Downloads panel: only in the WebView2/Edge runtime's locale .pak files (no CDN serves them). OneNote: 3 of 16 in Office start/Teams notes bundles; the rest in OneNote for the web (signed-in page). Events templates: in no Teams 26304 bundle.
- Built: desktop/i18n/extra_sources.json + extra_strings.py (`l10n.py extra`), gen keys OST text to "x.<source>:<key>" ids only where Teams' main table has none; teams_resources.json `extra` lists each language's file per source; src/api/teams_strings.rs downloads and parses them (json modules, ES object literals, flat JSON) into the catalogue. Their apostrophes are literal (quoted as ICU ''). untranslated.txt 843 -> 433.

- 2026-11-20 verified (agent tuiF, linuxlt, ost-test1, isolated XDG_CONFIG_HOME, app language de-de): the catalogue built from Teams' CDN plus the other bundles (4,345 strings, 365 from them: OneDrive 218, Outlook calendar 70, OneCamera 34, OnePlayer 28, Planner 15); OneDrive's screens showed OneDrive's German (Filter by pane, menus, "Eigene Dateien"). A bundle's text is only used on its own screens (extra_sources.json usedIn), so a generic word never takes another app's wording. untranslated.txt: 843 -> 484.
- Open: the Downloads panel (Edge/WebView2 runtime strings, no CDN), most of OneNote (OneNote for the web's bundle needs a signed-in page to find), Events' templates (not in Teams 26304), meeting options' labels (OST now asks with Accept-Language; mapping OST's fallbacks to the reply's translations keys needs a live reply), and strings whose OST wording differs from the bundles'.

- 2026-11-20 merged as 29f89fc; AC1 met for the Stream player, recorder, file preview and OneDrive/Outlook/Planner screens. AC2 open: Downloads panel, OneNote, Events templates, meeting-options labels.

- 2026-11-20 (agent setF-0233) AC2 work in progress:
  - Catalogue moved to Teams 26304.1207.5384.858 (winpc's current build; its locale chunks are on the CDN). Many new strings (Interpreter etc.) only exist there.
  - Downloads panel: WebView2 Fixed Version cabinet (msedge.sf.dl.delivery.mp.microsoft.com …FixedVersionRuntime.157.0.4341.60.x64.cab, 310 MB, one MSZIP folder, takes HTTP ranges). desktop/i18n/cabpak.py indexes its blocks; the app fetches only the blocks holding the hub's strings (~ a few hundred KB) and inflates them with an unknown history (two passes, 0x00/0xFF, equal bytes are exact). Source x.edge (kind cabpak, ids 12290-12520 and 20690-20840, prefer on DownloadsFlyout.qml).
  - Loop host strings: Teams' hostUxStrings<N> chunks, a webpack context "./<lang>/HostUxStrings.json" (source x.loop, teamsContext).
  - Meeting options: Teams' dialog shows the reply's translations as they are (meetingsOptions_<SECTION>, _<option>, _<option>_Info, _<option>_<value>); OST now prefers them, its fallbacks marked qsTr(…, "reply:meetingsOptions").
  - Events templates: not in Teams 26304.1201/1207 desktop bundles nor in the web client's loaded assets; eventTemplates lists only saved templates; the Meet app is not available in Randy's tenant. Open.
  - Profile card (LPC): its strings are livepersonacardstrings_<hash>.js from res.cdn.office.net/midgard/versionless, named by loki.delve.office.com/api/v1/livepersonacard/configuration?cultureName=<lang> (X-ClientType: Teams, needs a Loki token). Open.

- 2026-11-20 (agent setF-0233) committed 3765762: untranslated.txt 516 -> 428 (4677 strings keyed, 29 from the meeting-options reply). Also reworded OST text to Teams' exact text (plurals with %n, OneDrive and Outlook punctuation, app language names, and others). The parsers now take Loop's {count, number} and a literal brace (Teams' i18next "{}"). OneDrive texts with a trailing space or zero-width space now match.
- Verified live on linuxlt (OST Test 2, isolated XDG_CONFIG_HOME, app language de-de, --menu-test). The catalogue was built from the 1207 CDN files plus the other bundles: 4,634 strings, 11 from the WebView2 cabinet and 7 from Loop. The Downloads panel showed "Datei öffnen" and "Entfernt" from Edge's pack. cargo test --lib: 859 passed; webview2_cabinet_live (ignored, network) passed; desktop tests: 29 passed.
- Still open:
  - Events templates: no source found.
  - Profile card (LPC): its strings file is named only by a configuration call that needs a Loki token.
  - "Search all files" and "%1, removed" in the Downloads panel: Edge builds these in its hub JS.
  - Meeting-options keys: not yet seen in a live reply.
  - OST-only strings: the feedback and help pages, and "not available in OST yet".

- 2026-11-21 (agent setH) recorder effects (TASK-0137 screens):
  - x.onecamera usedIn now has ClipCanvasItems/ClipCatalog/ClipDrawer/ClipEditOverlay/ClipEffectPanels/ClipEffectsState.qml.
  - New source x.webrec (kind "loc"): the Stream web recorder's language chunks in Teams' hashed assets (webrec2-language-<lang>-<hash>.js, `loc:new a({…})`, 124 strings, 56 languages): the backdrop/board/sticker names (effects.*), "Record again", "Review your clips", "Recording in progress", "Screen recording", fonts. Parsers: extra_strings.py parse_loc_table and teams_strings.rs parse_loc_table (tested). `l10n.py extra` rerun on linuxlt (cache ~/l10n3; strings-extra.json backed up as strings-extra.json.setH-bak).
  - OST text reworded to Teams' (OneCamera): Font menu / Text color menu / Text shadow menu / Text background menu, "Video editing tools: %1 menu", "The camera is %1 percent of the video viewport", "Choose image file to upload", "Delete this clip. Your video will be lost.", "This will delete your video clips."; shared words (sticker categories, Music) name their OneCamera ids explicitly (l10n.py now accepts dotted keys in qsTr("…", "<ns>:<key>")).
  - untranslated.txt 542 -> 437 lines; recorder lines 140 -> 28 (left: OST's own accessibility texts and keyboard hints Teams has no string for, e.g. "Alt + left arrow key", "Mic is off", file-dialog filters).
<!-- SECTION:NOTES:END -->
