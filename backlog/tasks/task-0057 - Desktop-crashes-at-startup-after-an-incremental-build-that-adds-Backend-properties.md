---
id: TASK-0057
title: >-
  Desktop crashes at startup after an incremental build that adds Backend
  properties
status: Done
assignee: []
created_date: '2026-11-08T06:31:00Z'
updated_date: '2026-11-08T09:16:00Z'
labels:
  - desktop
  - build
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After adding two qproperties to Backend (backend.rs) and changing Main.qml/CallWindow.qml, an incremental `cargo build` of ost-desktop produced a binary that segfaults ~3 s after start: QMetaObject::methodOffset() from AOT-compiled Main.qml (aotBuiltFunctions lambda #328) called via a PeopleView.qml signal. `cargo clean -p ost-desktop` + rebuild fixed it. qt-build-utils reruns qmlcachegen for every QML file whenever build.rs runs, so the stale piece is elsewhere (metatypes/qmltypes or generated C++ objects).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An incremental build after adding a Backend qproperty starts and runs without crashing
- [x] #2 The cause is identified and fixed in the build (no manual clean needed)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- A second startup crash (after adding VideoFrame.radius) was not stale: Qt 6.10 qmlcachegen miscompiled a `readonly property var` binding that returned an object literal (initGetValueLookup on a null meta-object). Rewritten with plain numbers. The first crash (Backend properties) did clear with a clean build, so that one stays open.

- Root cause (2026-11-08): not a stale build. Qt Labs Platform's widget tray menu (active once OST ran as a QApplication) crashes in Qt 6.10 when the tray's icon bindings update on a presence change (meeting join), corrupting the heap; crashes showed up at random later points (AOT lookups, XHR GC, fonts). Fixed by a native StatusNotifierItem tray (desktop/src/tray.rs) and going back to QGuiApplication: 10 meeting joins without a crash (was 2-3 of 6).

- A second, real cause: qt-build-utils runs qmlcachegen before qmltyperegistrar writes plugin.qmltypes, so incremental builds compiled QML against the previous types (Main.qml.cpp at 00:57:22, plugin.qmltypes at 00:57:44); stale meta-method indices crashed once Backend gained members. desktop/build.rs removes the old plugin.qmltypes first; verified an incremental build after adding Backend members runs.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Startup/join crashes fixed: the tray is native Rust (ksni StatusNotifierItem + DBus menu) instead of Qt Labs Platform, whose widget menu crashed on presence changes under QApplication in Qt 6.10. OST is a QGuiApplication again (no Qt Widgets). Verified on linuxlt: tray menu over DBus on Plasma; 10 meeting joins with and without the tray, no crash.
<!-- SECTION:FINAL_SUMMARY:END -->
