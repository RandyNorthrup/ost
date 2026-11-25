---
id: TASK-0309
title: 'Security: Teams tokens only go to Microsoft hosts over HTTPS'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). Some card-image requests can carry a Teams token over plain HTTP, and the destination check is weak. Every request that attaches a token (card images, inline images, avatars, app icons, any proxied fetch) must check the exact destination.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No request attaches a Teams, Graph, Skype or other token unless the URL is https and its host matches an exact allowlist of the Microsoft service hosts that token is meant for (suffix checks done on label boundaries)
- [ ] #2 Card images and other third-party URLs are fetched without any token, and plain-HTTP URLs never carry credentials or cookies
- [ ] #3 Unit tests cover lookalike hosts (evil-microsoft.com, microsoft.com.evil.net, userinfo tricks, http://, IP literals)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add one central check (src/auth/token_hosts.rs): https, no userinfo, DNS host (no IP), exact host or label-boundary suffix per token audience (Teams/Skype/IC3, Graph).
2. Use it in every TeamsClient token method (teams_*, csa_*, chat_*, ams_*, graph_*), in is_service_link (call links), and in direct senders taking remote URLs (Better Together, transcript, recorder, events).
3. Give token-bearing clients a redirect policy that only follows https redirects to Microsoft services (custom headers like X-Skypetoken survive reqwest redirects).
4. Card images: token only via the central check; third-party pictures without credentials; no plain http at all.
5. Unit tests for lookalikes, userinfo, fragments, http, IP literals.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404):
- src/api/emoticons.rs:419-424 remote_image_file: host taken as url.split('/').nth(2) and checked with ends_with(".teams.microsoft.com"|".asm.skype.com"), no scheme check, so http://x.teams.microsoft.com/... got the Skype token over plain HTTP, and https://evil.example#.teams.microsoft.com (or ?.teams...) passed the check (token to evil.example).
- desktop/src/backend.rs:21250 card_image accepted http:// card picture URLs.
- src/api/client.rs:338/488/566 (teams_get, chat_get, ams_get and the other skype-token helpers) attached the token to whatever URL they were given; client.rs:89 used reqwest defaults, whose redirects keep custom X-Skypetoken/Authentication headers.
- src/api/better_together.rs:518 send() posted the Skype token to a peer-supplied URL unchecked; transcript history and recorder invite likewise for call links.
<!-- SECTION:NOTES:END -->
