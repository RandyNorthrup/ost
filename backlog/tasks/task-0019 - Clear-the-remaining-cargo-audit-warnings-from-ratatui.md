---
id: TASK-0019
title: Clear the remaining cargo audit warnings from ratatui
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T03:22:00Z'
updated_date: '2026-11-10T15:36:00Z'
labels:
  - security
  - deps
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the 2026-11-04 dependency work, cargo audit reports 0 vulnerabilities and 3 warnings, all through ratatui 0.29: paste (unmaintained, RUSTSEC-2024-0436) and lru 0.12 (unsound, RUSTSEC-2026-0253 and RUSTSEC-2026-0002).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cargo audit reports no warnings, or each remaining one is documented as not reachable
- [x] #2 The TUI still works after any ratatui upgrade
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cargo audit reports no warnings.

- The ratatui warnings (paste, lru 0.12) went with the move to ratatui 0.30 (43019d5).
- The three left (RUSTSEC-2026-0370/0371/0372) are "unmaintained" notices, not vulnerabilities: zbus 6 merged zvariant, zbus_names and zvariant_derive into zbus. OST gets them only through keyring's Linux Secret Service store (keyring 4 → zbus-secret-service-keyring-store 1.0 → secret-service 5 → zbus 5).
- .cargo/audit.toml ignores those three and says why. Remove it once the store moves to secret-service 6 / zbus 6 (6.0.0-rc.1 is out).

TUI check: built `teams-cli` with ratatui 0.30 and ran `teams-cli tui` in tmux on linuxlt. It signs in, lists teams and chats, opens OST Test Team ▸ General, and shows its messages, compose box and help.
<!-- SECTION:FINAL_SUMMARY:END -->
