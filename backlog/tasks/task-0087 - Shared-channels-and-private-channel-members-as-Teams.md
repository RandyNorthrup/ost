---
id: TASK-0087
title: Shared channels and private channel members as Teams
status: To Do
assignee: []
created_date: '2026-11-10T05:09:00Z'
updated_date: '2026-11-16T04:52:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Private channels: OST creates and deletes them as Teams, but adding people (the member step's Add, Manage channel ▸ Members) uses an unverified middle-tier PUT. Teams' client adds channel members through the provisioning service (POST teams/{group}/channels/OID:{channel group}@{tenant}/users?forceSync=… {users:[{id:'OID:{user}@{tenant}', role}]}); OST Test Team has no other member to test with. Shared channels (create's share step, Share channel, Requests and invites, Pending invites' accept/decline via users/me/invitations/{id}/accept|decline) are off in this tenant (isSharedChannelCreationEnabled false).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Adding people to a private channel sends Teams' request and they appear in Teams' channel roster (needs a second member in OST Test Team)
- [ ] #2 Shared channel creation, sharing and invitations work as Teams where the tenant allows shared channels
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 tenant (user: "you are authorized to adjust anything in the test tenant to unblock us"): the Teams policy already allows shared channels (Create shared channels / Invite external / Join external: On), and OST Test 2 is a member of OST Test Team, so both criteria can be tested live now.

Built so far: Creating a Shared channel (the type is offered), a member step for private channels (an unverified middle-tier request, not Teams' provisioning one), and Pending invites listed read-only. Missing: sharing a channel, accepting/declining invitations, live checks. (Audit 2026-11-16)
<!-- SECTION:NOTES:END -->
