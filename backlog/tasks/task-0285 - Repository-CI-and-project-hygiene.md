---
id: TASK-0285
title: Repository CI and project hygiene
status: In Progress
assignee: []
created_date: '2026-11-25T01:43:00Z'
updated_date: '2026-11-25T01:43:00Z'
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
- [ ] #3 Dependabot keeps Cargo and GitHub Actions dependencies up to date
- [ ] #4 main is protected: no force pushes or deletion, and pull requests need the CI checks to pass
- [ ] #5 SECURITY.md (private vulnerability reporting enabled), CONTRIBUTING.md and CODE_OF_CONDUCT.md exist and match how the project works
<!-- AC:END -->
