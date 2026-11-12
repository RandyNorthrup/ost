---
id: TASK-0123
title: 'Add to playlist (a video''s) as Teams: Stream playlists'
status: To Do
assignee: []
created_date: '2026-11-12T19:58:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A video's Add to playlist opens OneDrive's file picker (FilePicker.aspx scenario StreamPlaylist.AddToPlaylist) listing your Stream playlists (personal lists, SP.PersonalListsProxy.GetPersonalListsProxy templateTypeId 3a867b4a-7429-0e1a-b02e-bf4b240ff1ce) under My lists, Recent lists and Favorites. OST Test 1 has no playlist, so the add request couldn't be captured; a test playlist must be made first (Stream on the web). docs/spec/file-actions.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A video's Add to playlist lists your playlists as Teams' picker does
- [ ] #2 Picking a playlist adds the video to it as Teams does, verified with a test playlist
<!-- AC:END -->
