---
id: TASK-0114
title: >-
  Forward and Share pickers on Teams' picker service; Format in the share
  message
status: To Do
assignee: []
created_date: '2026-11-12T05:29:00Z'
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
- [ ] #1 Forward this message's Add recipients shows Teams' suggestions (people, chats, channels, teams in Teams' order, Teams' second lines), shared with Share this file
- [ ] #2 Share this file's message box has Teams' Format button and formatting bar, and the message is sent formatted as Teams sends it
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->
