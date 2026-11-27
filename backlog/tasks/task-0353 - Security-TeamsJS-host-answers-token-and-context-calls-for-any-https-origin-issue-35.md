---
id: TASK-0353
title: >-
  Security: TeamsJS host answers token and context calls for any https origin
  (issue #35)
status: In Progress
assignee:
  - '@t353b'
created_date: '2026-11-27T15:36:00Z'
updated_date: '2026-11-27T21:10:00Z'
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

- t353b (2026-11-27): took over from the earlier agent's branch (abaeca4f), rebased cleanly on origin/main; reviewed against ACs: every frame message now passes appOrigin (current origin = first origin, switches only to a valid domain), events posted to the current origin only, sso/naa/ssrToken carry the asking origin and Rust checks it (sso_origin_allowed), full-trust resources limited to ECS overrides or FULL_TRUST_RESOURCES, navigateCrossDomain limited to valid domains. No other TeamsJS host in OST answers getAuthToken (AppAuthWindow.qml already keeps to the first valid-domain origin).

- Live (t353b, testpc2 WSLg, OST Test 3, this branch's debug build, CDP into the app frames' main world):
  - Planner (--app-window-test=planner): loads (framed, initialize, appLoaded, success). From tasks.teams.microsoft.com: initialize, getContext (39 keys), getUser answered; navigateCrossDomain https://example.com → [false, "Url is invalid"]; getAuthToken → FailedToGetToken (Planner has no webApplicationInfo; Teams answers the same). Frame sent to https://example.com by script: initialize, getContext, getUser, getAuthToken x2, navigateCrossDomain all unanswered, no events in 12 s; log: "APPHOST Planner ignored <func> from a page outside the app's domains". Back on tasks.teams.microsoft.com it is answered again.
  - Calendar's New event form (--cal-test --cal-event-form; outlook.office.com): form draws (framed, initialize 2.58.0, appLoaded, success). From outlook.office.com getAuthToken https://outlook.office.com/ → token; https://graph.microsoft.com → refused (Invalid resource: not on Teams' list for 5966c135). Same frame on https://example.com: nothing answered, all ignored.
  - SharePoint tab configuration (--add-tab-test --add-tab-app=SharePoint, OST layout test channel, nothing saved): page draws (Recommended/Pages/Lists/Document libraries); from scnetsolutions.sharepoint.com getContext (48 keys) and getAuthToken https://scnetsolutions.sharepoint.com and Graph → tokens (full-trust, not on an ECS override list, so FULL_TRUST_RESOURCES applies).
  - Copilot (--embedded-apps-test=copilot): server-rendered page gets its ssrToken and loads (framed, initialize, ChatReady, success). OneNote (--app-window-test=onenote): framed, initialize, appLoaded, success.
  - Loop/Notes tabs use OST's own Loop host (LoopPage.qml, not app_host.js / teamsHost), so this change doesn't touch them.
  - One harmless console line: an event posted to the SharePoint origin before the frame's page had loaded (about:blank) is dropped by the browser; before it went to "*" and reached the blank page.
  - ECS on test3: restrictedFullTrustOverrides lists d2c6f111 (SharePoint), b5abf2ae, bd9fb5cb, 5966c135 (Calendar), as the earlier notes say.
<!-- SECTION:NOTES:END -->
