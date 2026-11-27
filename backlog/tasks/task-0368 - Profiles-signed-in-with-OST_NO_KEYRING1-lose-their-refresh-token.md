---
id: TASK-0368
title: Profiles signed in with OST_NO_KEYRING=1 lose their refresh token
status: Done
assignee:
  - '@claude'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T20:35:00Z'
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
- [x] #1 A profile signed in with OST_NO_KEYRING=1 keeps working across token expiry and restarts (tokens stored and read where the config says they are), with a regression test
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

Codex review (2 P2 findings, both fixed, threads replied and resolved):
- 4b7b60fb: per-profile flock (.config.toml.lock, 0600) held by saves and by loads that move the tokens, so a move from another run can't fall between writing the file and deleting the keyring copy.
- dcf67927: the keyring is opened lazily from the same read of the config that the tokens come from, not from an earlier look at the file.
- 35df3de6: the store-taking load_from/save_to wrappers are #[cfg(test)] (Clippy dead code). 035def59: the "found it in the keyring" info line is said once a run (it repeated 54 times).

Live checks on linuxlt with the fixed build (2026-11-27, 20:25-20:34 UTC):
- No-keyring profile t368nk (OST Test 3), config left by the repro with tokens_in_keyring = true: the fixed OST with OST_NO_KEYRING=1 read the sign-in from the keyring and logged it, renewed the browser sign-in and connected to Trouter with no warnings. Its save put the tokens back in config.toml, removed the flag and deleted the keyring item (secret-tool label check).
- With that OST running, a teams-cli load without the variable moved the tokens to the keyring again (flag true). OST_NO_KEYRING expire then moved them back to the file (flag gone, keyring item gone). OST_NO_KEYRING api refreshed the expired tokens (Graph /me 200), and they stayed in the file.
- Restart with OST_NO_KEYRING=1 after expiring every token: 3 x "Token refresh complete", Trouter connected, 0 WARN lines, and the tokens were fresh in the file.
- Keyring profile t368k (OST Test 2, no variable): tokens_in_keyring = true, no tokens in the file, keyring item present. expire then api refreshed (200), still in the keyring. A restart with expired tokens refreshed 3 times with no warnings.
- Not a bug and unchanged: a fresh profile logs "Token expired and no refresh token" for a few services before its first sign-in, in both modes. That is the auditor's 17:22 line too.
- Cleanup: OST instances stopped by pid; profiles t368nk and t368k, their web storage and cache, logs, keyring items, accounts.json entries, ~/ost-build-t368 and the virtual mic modules removed; MacBook build dir removed. No call was joined, so no microphone stream was opened.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A profile signed in with OST_NO_KEYRING=1 now stays signed in when another run of the same profile moves its tokens to the keyring. The stored-where flag always matches where the tokens are.

Cause: the opt-in keeps the tokens in config.toml. Any run of the profile without the variable (another OST, teams-cli, an example; in the audit another agent's mt_post at 17:57:02 UTC) took them for an older OST's plaintext and moved them to the keyring (tokens_in_keyring = true). The OST_NO_KEYRING run then saw "in the keyring" with its keyring disabled and carried on with no tokens, so every service failed with "Token expired and no refresh token", also after restarting with the variable.

Changes (src/config/mod.rs):
- Loads read the tokens from wherever the config they read says they are. An OST_NO_KEYRING run opens the keyring only when that config names it, and opens it lazily from the same read.
- An OST_NO_KEYRING save writes the file, then deletes the keyring copy, so the flag and the tokens agree. If the keyring can't be read under OST_NO_KEYRING, the profile is signed out rather than failing with an error. Sign-out removes a keyring copy.
- Per-profile flock (.config.toml.lock, 0600) around saves and around loads that move the tokens. A load that finds the tokens gone from the keyring retries under the lock.
- TASK-0310 rules unchanged: no plaintext without an opt-in, and file tokens still move to a working keyring.
- docs/desktop.md: the mixed case.

Tests: storage_tests no_keyring_runs_find_tokens_another_run_moved_to_the_keyring, no_keyring_runs_sign_in_again_when_the_keyring_cant_be_read, no_keyring_runs_open_the_keyring_only_when_the_config_they_read_names_it, moving_the_tokens_waits_for_the_profiles_lock (18/18 config tests pass). CI, CodeQL and Codex are clean on PR #47.

Live (linuxlt): reproduced on main. With the fix, both modes refresh across forced expiry and restarts, and the mixed sequence keeps the profile signed in. Details in the notes.
<!-- SECTION:FINAL_SUMMARY:END -->
