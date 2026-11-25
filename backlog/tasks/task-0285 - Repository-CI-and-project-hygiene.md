---
id: TASK-0285
title: Repository CI and project hygiene
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T01:43:00Z'
updated_date: '2026-11-25T03:58:00Z'
labels:
  - packaging
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repo has no CI: nothing builds or tests pushes and pull requests, main is unprotected, there is no Dependabot config and no SECURITY/CONTRIBUTING/CODE_OF_CONDUCT. Set it up for a public project people use and contribute to.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every push to main and every pull request builds ost-desktop and teams-cli and runs the engine and desktop tests in GitHub Actions (Ubuntu 26.04 container with Qt 6.8+), with cargo caching, and the run passes
- [ ] #2 Formatting and lint checks (cargo fmt --check, clippy) run in CI and pass, with any needed fixes or documented allowances
- [ ] #3 main is protected: no force pushes or deletion, and pull requests need the CI checks to pass
- [ ] #4 SECURITY.md (private vulnerability reporting enabled), CONTRIBUTING.md and CODE_OF_CONDUCT.md exist and match how the project works
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Dependabot AC removed (user: leave Dependabot off for now); no dependabot.yml, Dependabot alerts/security updates left off.

- ci.yml: Ubuntu 26.04 container, deps from build-deb.sh --deps-only (the release agent's debian/control is the one package list); jobs Format, Clippy, Build and test; rust-cache saved from main only; debug info off.
- Test-branch run 45528346170 (ci-test, since deleted): Format and Clippy passed; ost-desktop failed to link with GNU ld.bfd (Ubuntu's rustc links with cc + bfd; cxx-qt needs lld or mold). The release agent adds lld to Build-Depends.
- cargo fmt: the tree was never rustfmt-formatted (about 4,900 hunks). The reformat is its own commit, made last on the final main, with a blame-ignore-revs entry.
- clippy 1.93 (workspace, all targets): 95 findings. Machine-applicable ones from clippy --fix (run 45530414624), the rest by hand: type aliases, simpler booleans, iterators, doc lists. Allowed with reasons: result_unit_err (chat_notes), large_enum_variant (2 short-lived enums); clippy.toml too-many-arguments-threshold = 8.
- main protection: no force push or deletion; required checks Format, Clippy, Build and test (GitHub Actions app); admins not enforced, so the owner can push directly.
- Security settings (enabled by the coordinator): Dependabot alerts and security updates, private vulnerability reporting, CodeQL default setup (rust, c-cpp, javascript-typescript, python). No dependabot.yml version updates.

- linuxlt check (rustup 1.94, -j 4): clippy --workspace --all-targets -D warnings clean after allowing result_large_err on the three tungstenite handshake callbacks (new in 1.94); engine lib tests 968 passed / 3 ignored; ost-desktop tests 38 passed. Folder deleted.
- Commits rebased onto main 42fe5a61, waiting for the packaging work to land: community files, clippy --fix, doc comments, manual clippy fixes + clippy.toml, ci.yml, result_large_err allows. Then the reformat (cargo fmt --all) regenerated last, with the blame-ignore-revs entry, merged fast-forward; then watch CI on main and add actions to CodeQL default setup if it isn't picked up.
<!-- SECTION:NOTES:END -->
