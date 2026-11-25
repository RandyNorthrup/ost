---
id: TASK-0286
title: teams-cli logout keeps the sign-in method setting
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T04:38:00Z'
updated_date: '2026-11-25T05:06:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen in TASK-0283 testing: teams-cli logout rewrote config.toml down to tenant_id and tokens_in_keyring, dropping auth_flow = "teams-web", so the next sign-in silently switched sign-in method. Logout should clear the account's tokens and account data only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After logout, config.toml keeps auth_flow and other non-account settings, and the next sign-in uses the same method
- [x] #2 A unit test covers logout preserving settings
- [x] #3 teams-cli login on a profile that signs in with the browser (auth_flow teams-web) says so and exits non-zero instead of switching to the device code; with --device-code it proceeds and switches, and a test covers the choice
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Keep auth_flow through sign-out: move the clearing out of clear_tokens into a keyring-free Config::forget_account (tokens + account data).
2. teams-cli login refuses to switch a teams-web profile without --device-code; help text.
3. Unit tests; verify on linuxlt with a temp config.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: Config::clear_tokens (teams-cli logout and the desktop's Sign out) also set auth_flow = None.
- Fix: the clearing moved to Config::forget_account (no keyring access, so it can be unit-tested): tokens, tenant_id, region_gtms, license_details, tokens_in_keyring; auth_flow stays. clear_tokens = delete the keyring entry + forget_account.
- Coordinator/user decision: teams-cli login on a teams-web profile refuses with an explanation and exits non-zero; --device-code switches. Documented in login --help; wiki Terminal-client line sent to the packaging agent (goes out with its wiki push).
- linuxlt (rustup 1.94, -j 4, temp folder deleted): engine lib tests 970 passed / 3 ignored (incl. sign_out_tests and login_tests); clippy -p teams-cli --features audio,video,screencast --all-targets -D warnings clean.
- Manual check with a throwaway config (temp XDG dirs, OST_NO_KEYRING=1, fake tokens): logout left config.toml as just auth_flow = "teams-web"; login without the flag printed the message and exited 1; login --device-code went on to the device-code prompt (stopped there).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Signing out no longer drops the profile's sign-in method, and teams-cli login no longer silently switches a browser sign-in profile to the device code.

Changes:
- `Config::clear_tokens` (teams-cli logout, the desktop's Sign out) now deletes the keyring entry and calls the new `Config::forget_account`, which clears the tokens and the account data that came with them (tenant_id, region_gtms, license_details, tokens_in_keyring). `auth_flow` stays, so config.toml keeps how the profile signs in. Before, logout left only tenant_id and tokens_in_keyring.
- `teams-cli login` on a profile with auth_flow "teams-web" explains that it signs in through OST desktop's browser sign-in (which the desktop's embedded apps need), that running ost-desktop signs it in again, and exits non-zero. The new `--device-code` flag proceeds and switches the profile to the device code, as before. Documented in `teams-cli login --help`; the wiki Terminal-client wording went to the packaging agent.

Tests:
- New unit tests: config `sign_out_tests` (settings survive, account data and tokens go, the saved file is just auth_flow and selects the same client) and oauth `login_tests` (refusal only without --device-code on a teams-web profile).
- linuxlt: `cargo test --features audio,video --lib` 970 passed; clippy on teams-cli (desktop features, all targets, -D warnings) clean.
- Manual, throwaway config with OST_NO_KEYRING=1: logout keeps `auth_flow = "teams-web"`; login exits 1 with the message; login --device-code reaches the device-code prompt.

Behavior change: logout now also forgets the tenant id (account data). The desktop's Sign out follows the same rule.
<!-- SECTION:FINAL_SUMMARY:END -->
