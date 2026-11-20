---
id: TASK-0233
title: 'App languages: strings from Teams'' other bundles'
status: To Do
assignee: []
created_date: '2026-11-20T04:10:00Z'
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
