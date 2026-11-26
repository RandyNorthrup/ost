---
id: TASK-0309
title: 'Security: Teams tokens only go to Microsoft hosts over HTTPS'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-26T02:01:00Z'
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
- [x] #1 No request attaches a Teams, Graph, Skype or other token unless the URL is https and its host matches an exact allowlist of the Microsoft service hosts that token is meant for (suffix checks done on label boundaries)
- [x] #2 Card images and other third-party URLs are fetched without any token, and plain-HTTP URLs never carry credentials or cookies
- [x] #3 Unit tests cover lookalike hosts (evil-microsoft.com, microsoft.com.evil.net, userinfo tricks, http://, IP literals)
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

Live check on linuxlt (2026-11-25, my build with --features test-harness, fresh profile OST_PROFILE=sectest as ost-test1, keyring on; removed afterwards):
- 0309: sign-in worked; with an empty XDG_CACHE_HOME the chat list and OST group test fetched 6 card images, 40 inline images, 19 profile photos and 12 thumbnails through the new checks, with no "Refusing to send credentials" or "not following a redirect" lines.
- 0310: config.toml has tokens_in_keyring = true and no token fields; after sign-out the keyring entry holds no tokens.
- 0311: Planner hosted and framed (the host's new address check passed); an injected https://example.com iframe asking for microphone and geolocation was refused by origin ("device permission refused: the page isn't one of the app's"); Planner's own frame passed the origin check and was refused only by its App permission (off by default, as in Teams).
- 0313: --sign-out-test: "signed out; restarting", the restarted process removed ~/.local/share/OST/QtWebEngine/ost-apps-sectest and its cache before Qt WebEngine opened; the next sign-in asked for the e-mail address (no remembered account). First run crashed in libQt6Qml during teardown before the restart; fixed (re-exec right after the event loop) and re-verified: restart within 1.5 s.
- 0314: --feedback-test: the issue URL holds only template, title, text and contact ("logs in url: false"); masked logs went to OST report details.txt (0600, folder 0700) with no JWTs; the sectest log has no eyJ tokens.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Tokens go only to the Microsoft services they are for, over HTTPS.

Changes:
- src/auth/token_hosts.rs: allowed(url, audience) (https, no user info, DNS host, exact host or label-boundary domain allowlist for the Teams/Skype/IC3 and Graph tokens), ensure(), service_url() (validated https base + encoded segments), a redirect policy that follows only https redirects to Microsoft services, and http_client().
- TeamsClient: every token method checks its destination; its client uses the redirect policy.
- is_service_link (call links), Better Together, transcript history, recorder invite, events requests use the check; calendar respond/cancel and collab-object reads use service_url (CodeQL rust/cleartext-transmission #9, #30, #31).
- Card pictures: https only, token only via the check, third-party pictures without credentials and no downgrade redirects; live_share and event highlights parse hosts with url::Url and require https.

Tests: token_hosts unit tests (lookalikes, userinfo, fragment/query tricks, http, IP literals, trailing dot, redirects, service_url); live: images, cards and photos load with no refusals.

PR #7 (branch task-0309-0315-app-security); CI Format, Clippy (with and without test-harness), Build and test, Release build refuses test-harness flags; CodeQL clean on the PR.
<!-- SECTION:FINAL_SUMMARY:END -->
