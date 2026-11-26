---
id: TASK-0311
title: 'Security: embedded web apps get permissions only for their own pages'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-26T02:00:00Z'
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

Live check on linuxlt (2026-11-25, my build with --features test-harness, fresh profile OST_PROFILE=sectest as ost-test1, keyring on; removed afterwards):
- 0309: sign-in worked; with an empty XDG_CACHE_HOME the chat list and OST group test fetched 6 card images, 40 inline images, 19 profile photos and 12 thumbnails through the new checks, with no "Refusing to send credentials" or "not following a redirect" lines.
- 0310: config.toml has tokens_in_keyring = true and no token fields; after sign-out the keyring entry holds no tokens.
- 0311: Planner hosted and framed (the host's new address check passed); an injected https://example.com iframe asking for microphone and geolocation was refused by origin ("device permission refused: the page isn't one of the app's"); Planner's own frame passed the origin check and was refused only by its App permission (off by default, as in Teams).
- 0313: --sign-out-test: "signed out; restarting", the restarted process removed ~/.local/share/OST/QtWebEngine/ost-apps-sectest and its cache before Qt WebEngine opened; the next sign-in asked for the e-mail address (no remembered account). First run crashed in libQt6Qml during teardown before the restart; fixed (re-exec right after the event loop) and re-verified: restart within 1.5 s.
- 0314: --feedback-test: the issue URL holds only template, title, text and contact ("logs in url: false"); masked logs went to OST report details.txt (0600, folder 0700) with no JWTs; the sectest log has no eyJ tokens.
<!-- SECTION:NOTES:END -->
