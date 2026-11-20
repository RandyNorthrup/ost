---
id: TASK-0087
title: Shared channels and private channel members as Teams
status: To Do
assignee: []
created_date: '2026-11-10T05:09:00Z'
updated_date: '2026-11-20T23:39:00Z'
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

- 2026-11-20 live, the whole shared-channel flow between test accounts (linuxlt; ost-test1 = spatest, OST Test 2 = test2, OST Test 3 = test3):
  - Tenant/test content made: teams "OST TEST 087 team1" (ost-test1 owner) and "OST TEST 087 team2" (OST Test 2 owner); channels "OST TEST 087 private" and "OST TEST 087 shared" in OST Test Team. All to be deleted after the check.
  - Share with a team: ost-test1 invited OST Test 2 and OST Test 3 (provisioning invitations → {errors: []}). Both saw the invite in Pending invites (users/me/invitations: channel, organization, inviter, expiry).
  - Decline: OST Test 3 declined → the list empties for them and the host sees state Declined.
  - Accept: Teams' body is {targetTeamThreadMri: <team thread>} (found with examples/invite_accept_probe; a bare JSON string is answered 400 "Request required"). OST Test 2 accepted for team2 → {state: "Pending"}; ost-test1 approved (…/invitations/{id}/approve, new Approve / Deny on pending rows in Invites and requests) → sharedWithTeams lists OST TEST 087 team2.
  - Share with a team you own: ost-test1 linked "OST TEST 087 team1" (linkedTeams) → sharedWithTeams = OST Test Team (host), OST TEST 087 team1, OST TEST 087 team2.
  - Fix: CSA answers channelType 1 for private and shared channels alike; OST now tells them apart by threadSubType (SharedChannel / PrivateChannel) or isShared, so Manage channel shows a shared channel's tabs. Sent invites now lists only Sent / Pending ones, as Teams.

- 2026-11-20 live UI (linuxlt, ost-test1, --channel-share-test manage/shot): Manage channel on the shared channel shows Teams' tabs (Members, Invites and requests, Settings), the "Share with people ▾" split button, Owners (1) / Members (0) / Teams (3); on the private channel Members, Settings, Analytics with "+ Add member", Owners (1) / Members and guests (1) (OST Test 2).
- Cleanup done: "OST TEST 087 shared" and "OST TEST 087 private" deleted (ost-test1), "OST TEST 087 team1" deleted (ost-test1), "OST TEST 087 team2" deleted (OST Test 2). No other tenant settings were changed for this task.
<!-- SECTION:NOTES:END -->
