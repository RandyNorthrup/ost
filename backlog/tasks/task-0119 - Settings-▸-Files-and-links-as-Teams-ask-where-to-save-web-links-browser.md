---
id: TASK-0119
title: 'Settings ▸ Files and links as Teams: ask where to save, web links browser'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T06:53:00Z'
updated_date: '2026-11-12T22:07:00Z'
labels:
  - settings
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Files and links page also has "Always ask where to save downloaded file" (a toggle under Downloads) and "Links open preference ▸ Always open web links in:" (a browser picker, e.g. Microsoft Edge). OST's page has neither (docs/spec/file-actions.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Always ask where to save downloaded file works as in Teams
- [x] #2 Always open web links in: offers Teams' choices (Default browser, Microsoft Edge when installed) and web links open in the one chosen
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings ▸ Files and links now has the rest of Teams' page.

- "Always ask where to save downloaded file" (device setting askDownloadLocation): chat files, OneDrive files and zips ask for their place via a save dialog (backend save_as_requested / save_as_answer), the file then saved under the chosen name.
- "Links open preference ▸ Always open web links in:" with Teams' choices (Default browser; Microsoft Edge when installed, Teams' default). OST installs Backend::open_web_link as Qt's http/https URL handler (native.cpp), so every web link and browser-opened Office file follows the choice.

Tests: --files-links-test on linuxlt with a stand-in microsoft-edge (link recorded) and an answered save dialog (file at the chosen path); settings restored. Teams on winpc offered exactly Default browser and Microsoft Edge.
<!-- SECTION:FINAL_SUMMARY:END -->
