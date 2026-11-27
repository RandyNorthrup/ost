---
id: TASK-0368
title: Profiles signed in with OST_NO_KEYRING=1 lose their refresh token
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T18:48:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the 2026-11-27 parity audit (side finding): after signing in a new profile with OST_NO_KEYRING=1, Calendar, search, presence and other services failed with 'Token expired and no refresh token'. The profile's config recorded tokens_in_keyring = true although the keyring wasn't used; restarting without the variable fixed it. Details: /home/randy/.local/share/ost-remaining/audit/auditA.md, side findings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A profile signed in with OST_NO_KEYRING=1 keeps working across token expiry and restarts (tokens stored and read where the config says they are), with a regression test
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce on linuxlt with a throwaway profile (OST_NO_KEYRING=1, OST Test 3) and find what writes tokens_in_keyring = true.
2. Fix src/config so every process reads the tokens from where the config says they are and every write sets the flag to where it put them; an OST_NO_KEYRING process touches the keyring only when the profile's own config says its tokens are there (read, then move back to the file on its next save, and delete on sign-out).
3. Regression tests in storage_tests for the mixed-mode sequence (opt-in file -> keyring process migrates -> no-keyring process still reads, refreshes, restarts) and for sign-out.
4. Live check on linuxlt: both modes, forced expiry + refresh, restart, and the mixed sequence; remove the profile and its keyring entry.
5. PR, CI/CodeQL/Codex to green.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause found (2026-11-27):
- Reproduced the audit's sequence from the transcripts: auditA OST ran with OST_NO_KEYRING=1 and kept its tokens in config.toml (as designed). At 17:57:02 UTC another agent ran a teams-cli example (mt_post) with OST_PROFILE=auditA but without OST_NO_KEYRING. Its Config::load took the opt-in file's tokens for 0.2.1 plaintext and migrated them: keyring set, tokens_in_keyring = true, tokens stripped from the file (auditA config.toml mtime 17:57). Six seconds later the OST_NO_KEYRING instance's next Config::load hit tokens_in_keyring && keyring disabled -> "Tokens are in the keyring, but the keyring is disabled" -> no tokens -> "Token expired and no refresh token" for every service. A restart with the variable read the same file (no tokens); a restart without it read the keyring, so it "fixed" it.
- Code: src/config/mod.rs load_from returns no tokens when the flag says keyring but keyring_entry() is None (OST_NO_KEYRING), and clear_tokens under OST_NO_KEYRING never deletes a keyring copy. A fresh OST_NO_KEYRING sign-in by itself is fine (checked live with profile t368nk: file holds the tokens, flag absent, services work).

Fix committed and PR #47 opened (branch task-0368-no-keyring-tokens): OST_NO_KEYRING runs read the tokens from where the config says (keyring only when the config names it), put them back in the file at the next save and then delete the keyring copy; unreadable keyring under OST_NO_KEYRING = signed out, not an error; sign-out deletes a keyring copy. Regression tests: storage_tests::no_keyring_runs_find_tokens_another_run_moved_to_the_keyring, no_keyring_runs_sign_in_again_when_the_keyring_cant_be_read. Live checks pending (build boxes queued).

Live repro on linuxlt (main build, profile t368nk, OST_NO_KEYRING=1, OST Test 3): fresh sign-in kept the tokens in the file with no flag and services worked. Then `OST_PROFILE=t368nk mt_post ...` without the variable (the same tool as in the audit) at 18:47:44 UTC: config.toml now tokens_in_keyring = true with no refresh_token. 18:48:25 the running OST logged "Tokens are in the keyring, but the keyring is disabled" and "presence lookup failed: Not signed in (no refresh token)".
<!-- SECTION:NOTES:END -->
