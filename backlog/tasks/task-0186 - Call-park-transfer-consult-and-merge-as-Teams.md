---
id: TASK-0186
title: Call park, transfer-consult and merge as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-17T18:15:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's toolbar knows Teams' merge and park buttons but never enables them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Park, retrieve and merge calls work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-17 (16255e9): the engine holds one call while placing a second. Consult starts a call ("Open chat" keeps the chat consult); the banner offers Transfer (Teams' transfer request naming the replaced call), Merge Calls (three-person group chat, invite, leave the held call) and End consult. Unit-tested against Teams' calling code. Harness: --consult-call, --consult-transfer, --consult-merge.
- Not yet live: needs a third user. ost-test3 was created; the user approved a Business Basic licence for it and the Teams Phone Standard trial for Park (2026-11-17).
- Not built: the receiving side of a consult transfer.

- 2026-11-17 (f1724de): Park Call appeared in Teams after the park policy, Teams Phone Standard trial, Enterprise Voice and a policy-cache clear. Park is a transfer to the park server, with a pickup code of 10-99; retrieve calls the park server with that code.
- Built: taking a transfer, Park Call in More (Teams' gating), Teams' parked screen and retrieve by code, and receiving a consult transfer.
- Fixed: consult transfers going blind (OST waits for the real answer), and merge dropping the group call.
- Live with three users (Teams desktop as ost-test1, OST as test2 and test3): consult then transfer, merge (all three in Teams' roster), test2 parks Teams and test3 retrieves, Teams parks test2 and test3 retrieves.
- Leftovers in TASK-0221.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Park, retrieve, consult-then-transfer and merge work as in Teams, verified live across three users.

Changes:
- Calling engine holds one call while placing a second (src/calling/consult.rs).
- Consult, then:
  - Transfer: Teams' transfer request naming the replaced call;
  - Merge Calls: three-person group chat, invite, leave the held call;
  - End consult.
- Taking a transfer or park: OST places the requested call, answers both transfer steps and continues in the new call.
- Park Call in More, gated as Teams (policy, Teams Phone, not held, not E2EE). Teams' parked screen with the pickup code and Copy code; retrieve by code.
- A received consult transfer is answered at once, and the end of the replaced call no longer ends it.
- Fixes: consult transfers went blind on early media; merge dropped the group call.
- Harness: --consult-call, --consult-transfer, --consult-merge, --park-test, --unpark, --hangup-after (docs/desktop.md). Spec §5 and §1.8m.

Tenant (test accounts only):
- call park policy;
- Teams Phone Standard trial (billing off by Dec 15);
- Enterprise Voice;
- ost-test3 with a Business Basic licence.

Tests:
- cargo test --features audio,video --lib: 697 passed.
- Live with Teams desktop on winpc as ost-test1 and OST as test2 and test3.

Follow-up: TASK-0221.
<!-- SECTION:FINAL_SUMMARY:END -->
