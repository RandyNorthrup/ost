---
id: TASK-0315
title: 'Security: test hooks are not in release builds'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:17:00Z'
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
- [ ] #1 Test-harness flags and any code that runs caller-supplied JavaScript are compiled only with a dev/test cargo feature that release packages don't enable
- [ ] #2 Release builds ignore or reject those flags, checked in CI
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
<!-- SECTION:NOTES:END -->
