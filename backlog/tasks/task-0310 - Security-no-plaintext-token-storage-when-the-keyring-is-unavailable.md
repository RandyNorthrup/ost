---
id: TASK-0310
title: 'Security: no plaintext token storage when the keyring is unavailable'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). If the system keyring is disabled or unavailable, access and refresh tokens fall back to a plaintext config file (mode 0600).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Without a working Secret Service keyring, OST doesn't write access or refresh tokens to disk by default; it keeps them in memory and asks to sign in again next start, and Settings explains why and how to enable a keyring
- [ ] #2 Storing tokens in a file needs an explicit opt-in (OST_NO_KEYRING=1 or a setting), is documented as weaker than the keyring, and the file is created 0600 atomically
- [ ] #3 Existing plaintext tokens are moved into the keyring when it becomes available, and the plaintext copy is removed
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Config load/save behind a SecretStore trait (keyring; fake in tests).
2. Save: keyring first; without one, tokens stay in a per-profile in-memory store unless the user opted in (OST_NO_KEYRING=1 or the new allow_token_file setting), then the 0600 file.
3. Load: tokens found in the file move to the keyring when it works; without keyring and opt-in they are kept for this run and stripped from the file.
4. Atomic 0600 writes via a fresh create_new temp file + rename; config dir created 0700.
5. Settings > Accounts and orgs card explaining the state, how to enable a keyring, and the opt-in toggle.
6. Unit tests; docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): src/config/mod.rs:217-231 Config::save wrote access/refresh/Skype/Graph/IC3 tokens into config.toml whenever keyring set_password failed (line 224 "storing tokens in the config file") or the keyring entry was unavailable (line 230), with no opt-in. write_private (mod.rs:385) reused a fixed config.toml.tmp opened with truncate, so a pre-existing tmp file kept its mode.

Live check on linuxlt (2026-11-25, my build with --features test-harness, fresh profile OST_PROFILE=sectest as ost-test1, keyring on; removed afterwards):
- 0309: sign-in worked; with an empty XDG_CACHE_HOME the chat list and OST group test fetched 6 card images, 40 inline images, 19 profile photos and 12 thumbnails through the new checks, with no "Refusing to send credentials" or "not following a redirect" lines.
- 0310: config.toml has tokens_in_keyring = true and no token fields; after sign-out the keyring entry holds no tokens.
- 0311: Planner hosted and framed (the host's new address check passed); an injected https://example.com iframe asking for microphone and geolocation was refused by origin ("device permission refused: the page isn't one of the app's"); Planner's own frame passed the origin check and was refused only by its App permission (off by default, as in Teams).
- 0313: --sign-out-test: "signed out; restarting", the restarted process removed ~/.local/share/OST/QtWebEngine/ost-apps-sectest and its cache before Qt WebEngine opened; the next sign-in asked for the e-mail address (no remembered account). First run crashed in libQt6Qml during teardown before the restart; fixed (re-exec right after the event loop) and re-verified: restart within 1.5 s.
- 0314: --feedback-test: the issue URL holds only template, title, text and contact ("logs in url: false"); masked logs went to OST report details.txt (0600, folder 0700) with no JWTs; the sectest log has no eyJ tokens.
<!-- SECTION:NOTES:END -->
