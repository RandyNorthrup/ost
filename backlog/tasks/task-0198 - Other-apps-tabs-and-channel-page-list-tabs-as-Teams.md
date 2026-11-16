---
id: TASK-0198
title: Other apps' tabs and channel page/list tabs as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T09:43:00Z'
updated_date: '2026-11-16T17:31:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Add a tab picker opens each app's own configuration page (OneNote, PDF, Excel, Whiteboard…) in a TeamsJS host, and a channel's "+" menu offers New page, Existing page, New list and Existing list. OST shows these but can't save them yet: it can't host Teams' embedded app pages (TASK-0053).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Choosing an app other than Website in the picker shows that app's configuration page and Save adds its tab for everyone, as in Teams
- [x] #2 A channel's Existing page, New list and Existing list add their tabs as in Teams (New page: TASK-0205)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (16a17d0), measured in Teams on the web; spec docs/spec/add-a-tab.md.
- App configuration pages: Save sends settings.save; the page's setSettings is written as Teams' tab property (fixed keys, URI-encoded name, " (n)" for repeats), then the post and reply chain. Checked with OneNote's notebook picker in OST group test (tab added, opened, removed).
- New list / Existing list: "Untitled list" tab at once, renamed from SharePoint's setSettings; Existing page: link lookup, card, createLink, Page tab. Checked in OST test channel; test lists, pages and tabs removed.
- New page needs the Loop page host: TASK-0205. Teams' channel-access warnings in Add an existing page are not built.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Other apps' tabs and channel lists and pages, as Teams.

- The Add a tab dialog hosts the app's configuration page and saves its settings the way Teams writes them; chats' own app tabs are hosted too.
- New list, Existing list and Existing page add their tabs as Teams does (list tab renamed in place from SharePoint's settings).

Harness: --add-tab-save, --add-tab-choice, --tab-cleanup. Follow-up: TASK-0205 (New page).
<!-- SECTION:FINAL_SUMMARY:END -->
