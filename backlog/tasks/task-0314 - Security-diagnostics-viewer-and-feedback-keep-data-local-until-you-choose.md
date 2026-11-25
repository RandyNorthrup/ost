---
id: TASK-0314
title: 'Security: diagnostics viewer and feedback keep data local until you choose'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:17:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The optional diagnostic data viewer can stream events over plain HTTP to a private-network address for up to 24 hours. Feedback sends report text and opted-in logs when it opens the issue form, before you submit. Log masking is pattern-based.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The diagnostic data viewer streams only to a loopback address unless the user enters another host, and plain HTTP to a non-loopback host is refused
- [ ] #2 Opening Report a problem sends nothing anywhere: logs are never put in the issue URL; OST saves them to a file the user reviews and attaches, and the issue form opens with only the text the user typed
- [ ] #3 Log masking covers tokens (JWT, opaque bearer, Skype tokens, refresh tokens, cookies, SAS/sig query parameters, codes in URLs), email addresses and phone numbers, with tests; logs never contain tokens in the first place
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. DDV: connection strings are loopback (http) or https://host; plain HTTP to another host refused; old private-address states drop to idle; no redirects.
2. Feedback: issue URL holds only the template, title, typed text and contact answer; version/OS/area/context/file names and opted-in masked logs go to "OST report details.txt" (0600) in the report folder, which opens for review. Same for suggested-reply feedback.
3. Logs: feedback::scrub_secrets removes JWTs, bearer/Skype tokens, refresh tokens (0.A/1.A, M.C), EwA tokens, cookies, token/code/sig params (query, fragment, form, JSON) and long opaque runs; a Scrubbed MakeWriter applies it to every event in the desktop log file, stderr and the CLI/TUI. mask_line = scrub + PII.
4. Tests; PRIVACY/help docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404):
- src/api/ddv.rs:98-107 accepted any RFC1918 address; src/api/ddv/wire.rs:184-188 always streamed over http:// to it, for 24 h (ddv.rs:19).
- src/feedback.rs:94-160 issue_url put area, context, version, OS, file names and, with "Yes, share", the newest masked log lines (url.push_str("&logs=") at :153) into the new-issue URL; desktop/src/backend.rs:18515 read the log for it. Opening the URL in the browser sends all of that before the user submits.
- src/feedback.rs:163 mask_line was pattern based (eyJ JWTs, Bearer, query strings) and only applied on export; the log file itself was written raw (desktop/src/main.rs file layer), so a token in an error URL or header would land in it.
<!-- SECTION:NOTES:END -->
