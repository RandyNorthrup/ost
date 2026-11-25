---
id: TASK-0312
title: 'Security: escape remote values in the embedded auth window'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The embedded auth window inserts remotely supplied values into an inline script without escaping them for HTML/JavaScript.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every value placed into injected scripts or HTML is serialized safely (JSON with <, >, &, U+2028/2029 escaped, or passed through WebChannel/messages instead of string building)
- [ ] #2 A test shows a value containing </script>, quotes and newlines can't break out
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. api::app_host::script_json: JSON with <, >, &, U+2028/2029 escaped for inline scripts; exposed as backend.scriptJson.
2. AppAuthWindow.qml builds its opener page with it for the link app's URL and validDomains.
3. Also: the app print view (WebApp printer) loads frame-supplied HTML with JavaScript off and only an https base.
4. Unit test with </script>, quotes, newlines, U+2028.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): desktop/qml/AppAuthWindow.qml:61 placed JSON.stringify(win.url) and JSON.stringify(win.validDomains) (from a link card's app) inside an inline <script> of a page loaded with base https://teams.microsoft.com/v2/ in the shared web profile; JSON.stringify does not escape </script> or <!--, so a crafted URL could close the script and run its own in Teams' origin. Related: desktop/qml/WebApp.qml:504 printHtml loaded HTML posted by any frame with a frame-chosen base URL and JavaScript enabled.
<!-- SECTION:NOTES:END -->
