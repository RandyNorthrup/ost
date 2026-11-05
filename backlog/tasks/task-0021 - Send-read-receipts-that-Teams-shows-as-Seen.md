---
id: TASK-0021
title: Send read receipts that Teams shows as Seen
status: To Do
assignee: []
created_date: '2026-11-05T06:25:00Z'
labels:
  - chat
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When OST shows a chat, the sender in Teams should see their message as Seen.

Findings (2026-11-05): OST sets the consumption horizon (PUT …/conversations/{id}/properties?name=consumptionhorizon, "msgId;now;clientMsgId"). It is stored (read back from the conversation), and OST uses it for its own unread state, but Teams web still shows the sender's message as Sent after a reload. Teams v2 likely reports reads another way. Look in the calling-pluginless / chat bundles for "readReceipt" / "consumptionhorizon".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A message from Teams web shows as Seen in Teams after OST displays it in a focused window
- [ ] #2 OST shows Seen on its own messages once the other person has read them
<!-- AC:END -->
