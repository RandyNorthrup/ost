---
id: TASK-0313
title: 'Security: sign-out clears web sessions'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). Web cookies persist, and the sign-out path doesn't explicitly clear them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Signing out deletes the account's WebEngine cookies, local storage, IndexedDB, cache and service workers for every profile OST uses (sign-in, hosted apps, Loop, viewers), and the next sign-in starts clean
- [x] #2 Each OST profile (OST_PROFILE) keeps its own web storage, so accounts never share cookies
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Per-profile web storage name (ost-apps, ost-apps-<profile>) from the backend.
2. Sign-out writes a marker and restarts OST; at start, before Qt WebEngine initializes, the profile's storage (data dir with cookies/local storage/IndexedDB/service workers, and its HTTP cache) is removed.
3. Docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): desktop/qml/Main.qml:46 one WebEngineProfilePrototype storageName "ost-apps" with ForcePersistentCookies for every OST_PROFILE (on linuxlt all profiles share ~/.local/share/OST/QtWebEngine/ost-apps); desktop/src/backend.rs:10621 sign_out only cleared tokens (auth::sign_out), never web cookies/storage.

Live check on linuxlt (2026-11-25, my build with --features test-harness, fresh profile OST_PROFILE=sectest as ost-test1, keyring on; removed afterwards):
- 0309: sign-in worked; with an empty XDG_CACHE_HOME the chat list and OST group test fetched 6 card images, 40 inline images, 19 profile photos and 12 thumbnails through the new checks, with no "Refusing to send credentials" or "not following a redirect" lines.
- 0310: config.toml has tokens_in_keyring = true and no token fields; after sign-out the keyring entry holds no tokens.
- 0311: Planner hosted and framed (the host's new address check passed); an injected https://example.com iframe asking for microphone and geolocation was refused by origin ("device permission refused: the page isn't one of the app's"); Planner's own frame passed the origin check and was refused only by its App permission (off by default, as in Teams).
- 0313: --sign-out-test: "signed out; restarting", the restarted process removed ~/.local/share/OST/QtWebEngine/ost-apps-sectest and its cache before Qt WebEngine opened; the next sign-in asked for the e-mail address (no remembered account). First run crashed in libQt6Qml during teardown before the restart; fixed (re-exec right after the event loop) and re-verified: restart within 1.5 s.
- 0314: --feedback-test: the issue URL holds only template, title, text and contact ("logs in url: false"); masked logs went to OST report details.txt (0600, folder 0700) with no JWTs; the sectest log has no eyJ tokens.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sign-out clears the embedded pages' web sessions; profiles don't share them.

Changes:
- Per-profile web storage name (ost-apps, ost-apps-<profile>).
- Sign-out writes a marker and restarts OST (re-exec right after the event loop, without QML teardown, which crashed); before Qt WebEngine starts, the profile's data and cache folders (cookies, local storage, IndexedDB, service workers, cache) are removed.
- --sign-out-test harness flag; docs.

Tests: live on linuxlt (restart, wipe, clean next sign-in).

PR #7 (branch task-0309-0315-app-security); CI Format, Clippy (with and without test-harness), Build and test, Release build refuses test-harness flags; CodeQL clean on the PR.
<!-- SECTION:FINAL_SUMMARY:END -->
