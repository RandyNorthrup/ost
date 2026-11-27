---
id: TASK-0353
title: >-
  Security: TeamsJS host answers token and context calls for any https origin
  (issue #35)
status: In Progress
assignee:
  - '@secjs'
created_date: '2026-11-27T15:36:00Z'
updated_date: '2026-11-27T16:31:00Z'
labels:
  - security
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #35 (Serph91P): desktop/src/app_host.js answers getContext, authentication.getUser, getAuthToken and other host calls for any https origin loaded in the app frame, with no validDomains/first-origin check; native sso/ssrToken never check the origin; sso_resource() accepts any https/api resource for full-trust Microsoft apps (including Graph); sub-frame navigation is only limited to https. Teams validates every message with isValidOriginForApp.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The TeamsJS host only answers messages whose origin is the app's first origin or one of its validDomains (nestedAppAuth keeps its broker check), as Teams' isValidOriginForApp does
- [ ] #2 Native sso and ssrToken receive the caller's origin and refuse to mint a token for an origin outside the app's domains; full-trust resources are limited to an allowlist
- [ ] #3 Tests cover the origin checks; existing apps (Planner, OneNote, SharePoint tabs, Copilot, Loop) still work live; issue #35 is answered and closed after the fix is merged
- [ ] #4 The app frame navigates as in Teams desktop (measured: it may go to another site in the frame); a page outside the app's valid domains gets no TeamsJS answers, events or tokens, and navigateCrossDomain only loads valid-domain addresses
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 code: isValidOriginForApp (module 775554), the iframe bridge's current-origin rule (927719 onMessageReceived), getAuthToken resource rules (434318 D / 775554 N), ECS restrictedFullTrustOverrides, navigateCrossDomain.
2. Measure Teams desktop on testpc1 (CDP): app frame navigation to another site; TeamsJS answers to a foreign origin; getAuthToken resources first-party apps ask for.
3. app_host.js: Teams' current-origin rule for frame messages, events to the current origin only, origin passed to sso/naa/ssrToken, navigateCrossDomain.
4. Rust: sso_origin_allowed (valid domains with placeholders filled), resource_matches_origin, full-trust allowlist (ECS overrides, else FULL_TRUST_RESOURCES), calendar limited to its list; unit tests.
5. Live: Planner, OneNote, SharePoint tab, Copilot, Loop, Calendar, an SSO app on linuxlt; foreign-origin probe.
6. PR, CI + Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams 26304 (testpc1, CDP, 2026-11-27): a script (location.href) and a real mouse click on a link both took the Calendar app's hwc-iframe from outlook.office.com to example.com / iana.org inside the frame; no browser opened. From example.com, initialize/getContext posted to Teams got no answer; the same getContext from outlook.office.com was answered. So Teams does not limit the frame's navigation: it answers only the app's origin (927719 onMessageReceived: current origin = framed origin, switches to an origin isValidOriginForApp accepts, otherwise drops) and posts events to that origin only.
- AC #3 reworded to that measured behavior (frame may navigate; outside pages get nothing; navigateCrossDomain only to valid domains, as Teams' handleLoadCrossDomainUrl).
- getAuthToken in Teams: non-full-trust apps get their manifest resource only when it matches the asking origin (434318 A, validResourcePattern ^((https|api)://{host}([:/].*)?)$); full-trust apps get what they ask unless ECS extensibility.restrictedFullTrustOverrides lists resources for the app (Calendar 5966c135, SharePoint d2c6f111, Viva Connections bd9fb5cb, b5abf2ae).

- getAuthToken calls seen in Teams on testpc1 opening 23 apps (Calendar, Planner, Workflows, Word, Whiteboard, Clipchamp, Polly, Power BI, OneNote, PowerPoint, Excel, Help, Shifts, Events, People, Visio, Loop, Meeting Recaps, Updates, Viva Learning, SharePoint, Activity): Calendar (outlook.office.com) asks https://outlook.office.com/ and https://ic3.teams.office.com/; SharePoint (scnetsolutions.sharepoint.com) asks api://<tenant>.sharepoint.com and https://<tenant>.sharepoint.com; Polly (teams.polly.ai) asks with no resource (its webApplicationInfo). All other first-party apps use NAA. Every full-trust request is on Teams' ECS lists, so FULL_TRUST_RESOURCES is those lists' commercial-cloud entries.
- testpc1: Teams restarted normally (debug port off, HKCU value removed), C:\Users\Public\secjs deleted.
- Unit tests (cargo test --lib api::app_host on linuxlt): 14 passed.
<!-- SECTION:NOTES:END -->
