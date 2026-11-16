---
id: TASK-0185
title: Share tray options as Teams (sound, presenter modes, PowerPoint Live, control)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T23:39:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST shares a screen or window through the desktop portal only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Share opens Teams' tray (header, Include sound, presenter-mode buttons, Screen and Window), and Include sound mixes the computer's sound into the call as Teams does
- [x] #2 Presenter modes, PowerPoint/Excel Live, give/take control and the Sharing control bar: TASK-0210
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (e07b90b, merged); Teams measured sharing only Notepad. Include sound: every other app's sound (not the call) mixed into the sent audio, also while muted, as Teams; checked live via PipeWire and the sent-audio rate.
- The rest moved to TASK-0210.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' share tray and Include sound. Presenter modes, give/take control, the Sharing control bar and PowerPoint/Excel Live continue in TASK-0210. Harness --join-share-tray, --join-share-sound.
<!-- SECTION:FINAL_SUMMARY:END -->
