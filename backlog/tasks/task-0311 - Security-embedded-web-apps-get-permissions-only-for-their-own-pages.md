---
id: TASK-0311
title: 'Security: embedded web apps get permissions only for their own pages'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:16:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The WebEngine permission handler trusts the app ID without checking which page asks for camera, microphone, location or notifications.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Camera, microphone, location, notification and other feature requests are granted only when the requesting origin belongs to the hosted app's declared valid domains (or Microsoft's own hosts Teams trusts for that app), and only for the permissions Teams grants that app
- [ ] #2 Requests from any other origin (navigations, iframes, redirects to other sites) are denied, with a unit or harness test
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. app_host::device_origin_allowed(origin, facts): requesting origin must match the app's valid domains (Teams' isValidOriginForApp) or, for Microsoft-owned apps, Microsoft service hosts over https.
2. Backend appPermissionFor(appId, kind, origin): grant only if origin passes and the App permission is on; pending while the app definition loads, then re-decided.
3. WebApp.qml uses p.origin; LoopPage clipboard grant limited to Microsoft hosts.
4. Unit tests for foreign origins.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): desktop/qml/WebApp.qml:678-686 onPermissionRequested granted camera/mic/geolocation/notifications when backend.appPermission(root.appId, kind) was true, never looking at p.origin, so any page or frame inside a hosted app's view (a link it navigated to, a third-party iframe) got the app's permissions. desktop/qml/LoopPage.qml:220-222 granted clipboard read/write to any origin.
<!-- SECTION:NOTES:END -->
