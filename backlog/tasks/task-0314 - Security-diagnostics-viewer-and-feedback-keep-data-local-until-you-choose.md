---
id: TASK-0314
title: 'Security: diagnostics viewer and feedback keep data local until you choose'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The optional diagnostic data viewer can stream events over plain HTTP to a private-network address for up to 24 hours. Feedback sends report text and opted-in logs when it opens the issue form, before you submit. Log masking is pattern-based.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The diagnostic data viewer streams only to a loopback address unless the user enters another host, and plain HTTP to a non-loopback host is refused
- [ ] #2 Opening Report a problem sends nothing anywhere: logs are never put in the issue URL; OST saves them to a file the user reviews and attaches, and the issue form opens with only the text the user typed
- [ ] #3 Log masking covers tokens (JWT, opaque bearer, Skype tokens, refresh tokens, cookies, SAS/sig query parameters, codes in URLs), email addresses and phone numbers, with tests; logs never contain tokens in the first place
<!-- AC:END -->
