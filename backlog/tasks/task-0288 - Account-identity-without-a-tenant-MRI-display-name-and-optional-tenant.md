---
id: TASK-0288
title: 'Account identity without a tenant: MRI, display name and optional tenant'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-25T18:08:00Z'
labels:
  - personal-accounts
dependencies: []
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST assumes every account is a work account: it builds 8:orgid: IDs in about 75 places and reads oid, tid, name and upn from the access token. Personal accounts have 8:live: IDs, no tenant and opaque access tokens. Make the signed-in account's identity an abstraction that both kinds fill in, without changing what work accounts see.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The signed-in user's MRI, object ID, tenant (optional) and display name come from one account identity, not from parsing the access token at each call site
- [x] #2 No code builds an 8:orgid: MRI from a bare object ID outside the identity module
- [x] #3 Work-account sign-in, chat, calls, calendar and files behave exactly as before (desktop and teams-cli tests pass; live check with ost-test1)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add src/identity.rs: AccountKind (Work/Personal), AccountIdentity {kind, mri, object_id, tenant_id?, display_name?, upn?}, built from a work access token; MRI helpers (work_user_mri, user_mri keeping any prefix, work_object_id, mri_id, is_person_mri, mri_from_skype_token) - the only place building 8:orgid: MRIs.
2. Config holds the identity: filled in set_access_token (sign-in and refresh), set_identity() for the personal sign-in (TASK-0292), derived once on load for old configs, persisted in config.toml, cleared on sign-out. tenant_id()/object_id()/display_name()/user_principal_name()/self_mri() read it; TeamsClient exposes identity()/self_mri().
3. Replace every 8:orgid: build/strip in the engine, teams-cli and desktop Rust with self_mri() or identity helpers; keep other people's MRI prefixes (group chats, ringing members, call targets).
4. QML: Mri singleton for MRIs built from directory object IDs; backend.userOid from the identity instead of stripping userMri.
5. Tests: identity unit tests, config tests; root lib tests, desktop tests, clippy, fmt on linuxlt.
6. Live check on linuxlt as ost-test1: sign-in/restart, chats, send to OST Test 2, channel post, calendar, presence, profile card, test call, teams-cli tui/chats.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-25: dependency on TASK-0287 dropped: the identity abstraction is built and verified with work accounts now; the personal-account values (8:live: MRI, no tenant, name from the Skype token) are filled in by TASK-0292 after the live capture.

- src/identity.rs: AccountIdentity {kind, mri, object_id, tenant_id?, display_name?, upn?} + MRI helpers; Config fills it in set_access_token, derives it on load for old configs, saves it in config.toml, clears it on sign-out; set_identity() is the hook for TASK-0292.
- Replaced ~105 Rust sites (engine, teams-cli, examples, desktop) that built or cut 8:orgid: MRIs; the only remaining non-test occurrence outside identity.rs is an error message. QML: Mri singleton (32 builds from directory ids) and backend.userOid (6 places that cut userMri).
- Other people keep their prefix: group chats accept 8:live: members, group calls ring member_mris(), call targets and member lists passed as MRIs are kept.
- linuxlt: clippy --workspace --all-targets -D warnings clean; engine lib tests 977 passed; desktop tests 38 passed; fmt clean.
- Live (ost-test1, OST_PROFILE=spatest): restart from stored sign-in, identity written to config.toml, chat list and self chat, sent "OST TEST 288" to OST Test 2 (seen on the server via teams-cli read), channel post in OST Test Team > General, calendar views, OST Test 2 profile card with presence, Echo test call (desktop and teams-cli call-test --echo: audio both ways), teams-cli status/whoami/chats/read and tui. teams-cli presence returns Graph 403 with the old binary too (pre-existing).

- Two-party call on linuxlt: ost-test1 (spatest) called OST Test 2 (test2, --call-test answering): calling -> connected -> ended on both sides; held the build lock during the call. Camera stayed off except during the Echo test call (Teams' test call turns it on).

- Files were not run live on their own. The OneDrive and drive code is unchanged; the file paths that did change (member_oids and member_emails for sharing in chats, cloud_attach chat_people) now go through member_mris, and only work-account object IDs come out of it, as before.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The signed-in account's identity is now one abstraction, filled in once at sign-in and refresh, instead of each caller decoding the access token or gluing `8:orgid:` onto an object ID. This is the groundwork for personal Microsoft accounts (8:live: MRIs, no tenant, opaque tokens); work accounts behave as before.

Changes:
- New `src/identity.rs`: `AccountKind` (Work, Personal), `AccountIdentity` {kind, mri, object_id, tenant_id: Option, display_name, upn}, `AccountIdentity::from_work_token`, and the MRI helpers `work_user_mri`, `user_mri` (keeps any existing prefix; a bare object ID is a work user), `app_endpoint_mri`, `work_object_id`, `mri_id`, `is_person_mri`, `mri_from_skype_token`. It is the only place that builds an `8:orgid:` MRI from a bare ID.
- `Config` holds the identity: `set_access_token` fills it in (sign-in and refresh), `load()` derives it for configs written before it existed, `save()` keeps it in config.toml (it is not a secret), sign-out clears it. `set_identity()` is where TASK-0292 records a personal account's identity, and an opaque token leaves that identity alone. `tenant_id()` (None for personal accounts), `object_id()`, `display_name()`, `user_principal_name()` and the new `self_mri()` read the identity. `TeamsClient` adds `identity()` and `self_mri()`.
- About 105 Rust sites in the engine, teams-cli, examples and desktop now use `self_mri()` or the helpers. Other people keep their own prefix: group chats accept `8:live:` members, group calls ring every person in the chat (`files::member_mris`), and call, transfer and consult targets passed as MRIs are kept as they are. Graph lookups stay limited to work users.
- QML: an `Mri` singleton builds directory people's MRIs (32 sites). `backend.userOid` comes from the identity and replaces the 6 places that cut it out of `userMri`.

Tests (linuxlt):
- `cargo clippy --locked --workspace --all-targets -- -D warnings`: clean. `cargo fmt --all --check`: clean.
- `cargo test --features audio,video --lib`: 977 passed. New identity and config tests cover token parsing, prefix handling, Skype-token MRIs, migrating old configs, keeping a personal identity, and having no tenant.
- `cargo test -p ost-desktop`: 38 passed.
- Live, signed in as ost-test1: restart from the stored sign-in, chat list and self chat, a message to OST Test 2 (confirmed on the server), a channel post, calendar views, OST Test 2's profile card and presence, Echo test calls from the desktop app and from teams-cli, a two-party call with OST Test 2, and teams-cli status, whoami, chats, read and tui.

Follow-ups: TASK-0292 fills in the personal identity. `teams-cli presence` returns Graph 403; the older binary does the same, so this change did not cause it.
<!-- SECTION:FINAL_SUMMARY:END -->
