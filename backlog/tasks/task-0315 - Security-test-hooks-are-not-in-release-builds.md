---
id: TASK-0315
title: 'Security: test hooks are not in release builds'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). A calendar test hook runs JavaScript supplied through local launch flags. The desktop test harness flags (screenshots, scripted actions, JS injection) are for development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test-harness flags and any code that runs caller-supplied JavaScript are compiled only with a dev/test cargo feature that release packages don't enable
- [x] #2 Release builds ignore or reject those flags, checked in CI
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. desktop/Cargo.toml feature test-harness (not default; no packaging enables it).
2. main.rs: without the feature, refuse any argument other than --help/--version/--room and Qt's own options (exit 2) before Qt starts, so Qt.application.arguments never carries harness flags; OST_QML_DIR only with the feature.
3. Rust hooks (--cqf-always, OST_CQF_ALWAYS, --stationary-fixture, OST_VOICE_PROFILE_WAV) only with the feature; QML script hooks (--cal-page-steps Function(), loopJs/--loop-steps, LoopPage.evalForTest) also check backend.testHarness().
4. CI: clippy and dev build with the feature; a release-harness-off job builds --release and checks the flags are refused; unit test of the argument check.
5. docs/desktop.md test harness section.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): desktop/qml/Main.qml:4851-4852 --cal-page-steps ran its text with Function("f","cv", s) (JavaScript from launch flags); Main.qml:2657/2667 --loop-test --loop-steps=<file> ran each line with runJavaScript in a Loop page; desktop/src/main.rs:229 OST_QML_DIR loaded QML from any directory; ~640 --*-test flags in Main.qml were all compiled into release builds.

CI on PR #7: the new job "Release build refuses test-harness flags" builds --release and checks --nav-test, --cal-test --cal-page-steps, --loop-test --loop-steps, a positional capture path and --room --shots are refused with exit 2 (passed); clippy runs with and without the feature. Harness workflows now need cargo build -p ost-desktop --features test-harness (used for all live checks above).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Test hooks are compiled only with the test-harness feature.

Changes:
- desktop/Cargo.toml feature test-harness (not default; no package enables it).
- Without it ost-desktop refuses any argument but --help, --version, --room and Qt's own options (exit 2) before Qt starts, ignores OST_QML_DIR, OST_CQF_ALWAYS, --stationary-fixture and OST_VOICE_PROFILE_WAV; QML script hooks (--cal-page-steps, --loop-steps, evalForTest) also check backend.testHarness().
- CI: clippy and dev build with the feature, new release-harness-off job checking a release build refuses the flags.
- docs/desktop.md Test harness section.

Tests: release_builds_take_only_ost_and_qt_options; CI job passed.

PR #7 (branch task-0309-0315-app-security); CI Format, Clippy (with and without test-harness), Build and test, Release build refuses test-harness flags; CodeQL clean on the PR.
<!-- SECTION:FINAL_SUMMARY:END -->
