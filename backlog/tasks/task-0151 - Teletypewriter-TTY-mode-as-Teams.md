---
id: TASK-0151
title: Teletypewriter (TTY) mode as Teams
status: To Do
assignee: []
created_date: '2026-11-15T05:37:00Z'
labels:
  - calling
  - accessibility
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Accessibility > 'Teletypewriter (TTY) mode' (isTTYSettingEnabled / toggleTTYSetting): Teams' desktop media stack turns on TTY support (mediaConfigurationService.enableTtySupport) and keeps the choice on the device; after toggling, Teams shows its 'active call' notice (tty_dialog_active_call_warning). Find out exactly what TTY support changes in the media path (audio processing, codec) and do the same in OST's audio engine; the card is left out until then.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings > Accessibility shows 'Teletypewriter (TTY) mode' with Teams' text and icon, kept on this device, and the notice Teams shows after toggling
- [ ] #2 With it on, OST's call audio is handled as Teams' TTY support handles it, so a TTY device's tones pass through a call intact (checked against Teams)
<!-- AC:END -->
