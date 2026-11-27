---
id: TASK-0353
title: >-
  Security: TeamsJS host answers token and context calls for any https origin
  (issue #35)
status: In Progress
assignee:
  - '@t353c'
created_date: '2026-11-27T15:36:00Z'
updated_date: '2026-11-27T23:29:00Z'
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
- [x] #1 The TeamsJS host only answers messages whose origin is the app's first origin or one of its validDomains (nestedAppAuth keeps its broker check), as Teams' isValidOriginForApp does
- [x] #2 Native sso and ssrToken receive the caller's origin and refuse to mint a token for an origin outside the app's domains; full-trust resources are limited to an allowlist
- [x] #3 The app frame navigates as in Teams desktop (measured: it may go to another site in the frame); a page outside the app's valid domains gets no TeamsJS answers, events or tokens, and navigateCrossDomain only loads valid-domain addresses
- [x] #4 Tests cover the origin checks; existing apps (Planner, OneNote, SharePoint tabs, Copilot, Loop) still work live
- [ ] #5 Issue #35 is answered and closed after the fix is merged
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

- PR #59 (branch task-0353-teamsjs-origin-2). AC #3: tests and live app checks done; its last part (issue #35 answered and closed) is the coordinator's after merge, so it stays open; the PR says Refs #35, not Fixes.

- PR #59: CI (build+test, both clippy runs, format, audit, release-harness check, CodeQL) all pass; Codex code and security review completed with no findings. testpc2's C: was full for a while during this work (WSL failed to start; later 125 GB free, fixed by someone else); this task's ~/b/task-0353b build folder there was removed afterwards.

- t353c (2026-11-27): JS test for app_host.js's origin checks: desktop/tests/app_host.test.mjs (Node's built-in runner, no packages; CI job "JavaScript tests"). The repo had no JS unit tests, and its harness flags need a signed-in session and are not run in CI. The file runs the real app_host.js in a vm sandbox (fake ost web channel, app iframe, message listener). It has 10 tests: first origin answered; foreign page gets nothing and no sso/naa; events to the current origin only; a valid domain becomes current; look-alike/http/null refused; getAuthToken carries the asking origin; nested frames NAA only, with their own origin; deepNaa off; navigateCrossDomain valid domains only. A red check in the suite runs the host with appOrigin bypassed and shows a foreign page is then answered and minted for. Hand red drills on mutated app_host.js copies (gate removed, any https current, events to *, nested any func, navigateCrossDomain unchecked, naa/sso origin replaced) each fail at least one test.
- Live (t353c, testpc2 WSLg, OST Test 3, main at 183e8732 + this branch, which changes no app code): no channel had a SharePoint tab, so one was added to OST layout test (SharePoint app, site page "Home", --add-tab-save --add-tab-nopost, nothing posted). A fresh run then opened it as an existing tab (--app-host-test=Home): framed, initialize, success; the site page draws (Activity cards). From scnetsolutions.sharepoint.com: getContext (49 keys, frameContext content) and getAuthToken for the site gave a token; navigateCrossDomain https://example.com gave [false, "Url is invalid"]. With the frame sent to example.com, getContext, getAuthToken and navigateCrossDomain got no answer (log: ignored … from a page outside the app's domains). The tab was removed afterwards (ok, tabs back to Conversation/Shared/Notes).
- Loop: General › Page (--loop-test=page --loop-tab=Page) is ready: framed, code, icon, rendered, title, connected; "Loop paragraph" page text and insert row drawn.
- wslbuild.sh fix (coordinator's script, not in the repo): touch ~/b/<name> created a file where the build folder goes, so every first build on a box failed (exit 74); now touch -c.

- AC #3 split (t353c): its tests and live app part is now AC #4 (checked); the issue #35 part is AC #5, left for the coordinator after merge.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TeamsJS host now answers only the app's own pages, as Teams' iframe bridge does: the frame's current origin is the framed one or a valid-domain origin, other pages get no answers or events, and Teams' events go to that origin only. The native sso, naa and ssrToken calls carry the asking origin, and Rust mints tokens only for the app's domains. getAuthToken resources follow Teams' rules: the manifest resource must match the origin, and full-trust apps are limited to the ECS restrictedFullTrustOverrides list or FULL_TRUST_RESOURCES (Calendar to its list). navigateCrossDomain is limited to valid domains. Live checks on testpc2 (OST Test 3): Planner, OneNote, Copilot (SSR), Calendar's event form (token for Outlook, Graph refused) and SharePoint's tab configuration all work. A page the frame was sent to (example.com) got nothing. PR #59 (Refs #35). Left for the coordinator after merge: answer and close issue #35 (AC #3), then set the task to Done.

Follow-up (PR #65): desktop/tests/app_host.test.mjs tests the JS origin checks under Node (CI job "JavaScript tests"), including a red check with the check taken out. Live on testpc2 (OST Test 3): an existing SharePoint channel tab (site page, added for the check and removed after) loads and is answered from its own origin, but not after the frame is sent to example.com. The General channel's Loop page tab loads. Left for the coordinator: AC #5 (answer and close issue #35), then Done.
<!-- SECTION:FINAL_SUMMARY:END -->
