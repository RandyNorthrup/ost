---
id: TASK-0114
title: >-
  Forward and Share pickers on Teams' picker service; Format in the share
  message
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T05:29:00Z'
updated_date: '2026-11-12T05:52:00Z'
labels:
  - search
  - files
  - chat
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Forward dialog and Share this file use the same people picker (isForwardDialogBoxPeoplePicker) on Substrate's peoplepicker.newChat suggestions. OST's Share this file uses it (api::search::recipients); OST's ForwardDialog still filters local chats and the directory. The share dialog's message box also lacks Teams' Format button.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Forward this message's Add recipients shows Teams' suggestions (people, chats, channels, teams in Teams' order, Teams' second lines), shared with Share this file
- [x] #2 Share this file's message box has Teams' Format button and formatting bar, and the message is sent formatted as Teams sends it
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11 (0af75d3): Forward's Add recipients now uses api::search::recipients (Teams' peoplepicker.newChat) via share_action "fw:recipients"; chats/channels single choice, people add up (Teams' rules kept). Share this file got Format: FormatBar (new `discard: false`) over a RichText note; sent through teams_html_with_media + files::send_html_with_files.
- Verified: Teams' share dialog Format measured on winpc (bar 458 at 6.67, 9.67; dialog +20.67); live "OST test 110" (bold) shared to OST Test 2; OST Test 2 forwarded "OST test 109" to OST Test 1 with the new picker (--forward-test, OST_PROFILE=test2).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Forward and Share this file now share Teams' recipient picker, and the share message can be formatted.

Changes:
- ForwardDialog: suggestions from Substrate peoplepicker.newChat (people, chats, channels, teams in Teams' best-match order, Teams' second lines and pictures) instead of local chat/directory filtering.
- ShareFileDialog: Format button with the compose formatting bar (no Discard), RichText note, formatted HTML sent with the file.
- FormatBar: `discard` option.

Tests:
- cargo test --lib (455 pass).
- --sharefile-test --sharefile-send (OST test 110), --forward-test as OST Test 2; Teams measured side by side.
<!-- SECTION:FINAL_SUMMARY:END -->
