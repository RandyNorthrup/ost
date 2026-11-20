---
id: TASK-0233
title: 'App languages: strings from Teams'' other bundles'
status: To Do
assignee: []
created_date: '2026-11-20T04:10:00Z'
updated_date: '2026-11-20T20:08:00Z'
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
- [ ] #1 OST's text for the Stream player, recorder, file preview and mirrored web-app screens appears in the chosen language with Teams' wording, fetched at runtime like the main catalogue (no Microsoft strings in the repo)
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
<!-- SECTION:NOTES:END -->
