---
id: TASK-0311
title: 'Security: embedded web apps get permissions only for their own pages'
status: To Do
assignee: []
created_date: '2026-11-25T19:49:00Z'
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
