---
id: TASK-0353
title: >-
  Security: TeamsJS host answers token and context calls for any https origin
  (issue #35)
status: To Do
assignee: []
created_date: '2026-11-27T15:36:00Z'
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
- [ ] #3 The app frame can only navigate within the app's valid domains; other addresses open in the browser, as in Teams
- [ ] #4 Tests cover the origin checks; existing apps (Planner, OneNote, SharePoint tabs, Copilot, Loop) still work live; issue #35 is answered and closed after the fix is merged
<!-- AC:END -->
