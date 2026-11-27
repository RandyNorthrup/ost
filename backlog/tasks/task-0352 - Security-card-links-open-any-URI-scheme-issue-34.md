---
id: TASK-0352
title: 'Security: card links open any URI scheme (issue #34)'
status: In Progress
assignee:
  - '@seccards'
created_date: '2026-11-27T15:36:00Z'
updated_date: '2026-11-27T15:56:00Z'
labels:
  - security
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #34 (Serph91P): links from card content (Adaptive Card Action.OpenUrl and markdown links, RichTextBlock selectAction, Hero card buttons, Connector card links) reach Qt.openUrlExternally with no scheme check, so file:, smb:, sftp:, davs: and other apps' custom schemes go to xdg-open without confirmation; RichTextBlock selectAction.url is concatenated into HTML unescaped. Message HTML already goes through safe_url().
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every remote-data call site of Qt.openUrlExternally goes through one native gate that allows only https, http, mailto, tel and OST's own schemes and refuses everything else, matching what Teams desktop opens from cards
- [ ] #2 Card markdown links and RichTextBlock selectAction URLs are scheme-checked and HTML-escaped, so a card can't inject markup
- [ ] #3 Unit tests cover the gate and the escaping; issue #34 is answered and closed after the fix is merged
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams: card/markdown sanitizer schemes and the desktop host's webLauncher.allowedExternalProtocols (testpc1).
2. desktop/src/link_gate.rs: classify() allowlist (https/http/mailto/tel), local_path(), desktop_schemes() from x-scheme-handler associations; unit tests.
3. backend: openExternal, externalLinkAllowed, openLocalPath, refuseLink; native.cpp installs refusing handlers for every other desktop scheme.
4. Migrate all 173 Qt.openUrlExternally call sites in desktop/qml to the gate (local files to openLocalPath); test that none remain.
5. AdaptiveCard markdown links and RichTextBlock selectAction: scheme-checked, escaped; ConnectorCard HTML reduced to its tags; AppDetailsDialog manifest links escaped.
6. Live: post a card with https, mailto, file and smb links to a test chat, click them in OST on linuxlt with an xdg-open shim logging what is opened.
7. PR, CI + Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams research (testpc1, MSTeams 26304.1207.5384.858): the desktop host ms-teams.exe launches only schemes on ECS webLauncher.allowedExternalProtocols (logs LaunchExternalUri_NotInAllowedExternalProtocols otherwise); the list (ecs_settings.dat64) has http, https, mailto, tel, sip, ms-word and other vendor schemes but no file:, smb:, sftp:, dav(s):. Its card/markdown sanitizer (sanitize-html) allows http, https, ftp, mailto, tel.
- OST gate: desktop/src/link_gate.rs (https/http/mailto/tel), backend.openExternal / linkHref / openLocalPath / refuseLink; native.cpp registers refuseLink for every other scheme the desktop has a handler for (x-scheme-handler associations + GIO/KIO built-ins).
- All 173 Qt.openUrlExternally sites in desktop/qml migrated (5 local-file ones and third-party notices to openLocalPath); a unit test fails if one comes back.
<!-- SECTION:NOTES:END -->
