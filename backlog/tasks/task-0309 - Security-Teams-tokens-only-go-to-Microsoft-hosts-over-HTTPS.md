---
id: TASK-0309
title: 'Security: Teams tokens only go to Microsoft hosts over HTTPS'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). Some card-image requests can carry a Teams token over plain HTTP, and the destination check is weak. Every request that attaches a token (card images, inline images, avatars, app icons, any proxied fetch) must check the exact destination.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No request attaches a Teams, Graph, Skype or other token unless the URL is https and its host matches an exact allowlist of the Microsoft service hosts that token is meant for (suffix checks done on label boundaries)
- [ ] #2 Card images and other third-party URLs are fetched without any token, and plain-HTTP URLs never carry credentials or cookies
- [ ] #3 Unit tests cover lookalike hosts (evil-microsoft.com, microsoft.com.evil.net, userinfo tricks, http://, IP literals)
<!-- AC:END -->
