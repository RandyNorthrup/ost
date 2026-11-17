---
id: TASK-0213
title: Meeting data channel reconnects after admission from the lobby
status: Done
assignee:
  - '@claude'
created_date: '2026-11-17T02:43:00Z'
updated_date: '2026-11-17T04:50:00Z'
labels:
  - desktop
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0210: when OST is admitted from a meeting lobby, its meeting data channel doesn't come back after the media move. Give/take control now re-attaches on a new session, but anything else on the data channel (captions, reactions' channel messages, presenter layouts) may be lost after a lobby admission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After admission from the lobby, OST's meeting data channel reconnects and its features work as before, verified with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Fixed by a subagent (004a7a5, merged): on admission the server moves the call with a newOffer re-offer under its own mids; Teams opens a new peer connection with main-channel and answers with the server's numbering. OST now answers the move as a meeting (its mids inside, the server's on the wire), keeps the camera sending, re-requests cameras and share, and the old session no longer turns off the new one's echo canceller and send estimate.
- Live with Teams on winpc (OST Test 2 admitted): data channel back each time, captions of a guest arrived, give/take control typed into Teams' Notepad; re-run after rebasing on the two-step join. Harness --join-lobby-data.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
After admission from the lobby, OST's meeting data channel, video and share come back as in Teams: the server's call move is answered as Teams answers it. Verified live with captions and screen control after admission.
<!-- SECTION:FINAL_SUMMARY:END -->
