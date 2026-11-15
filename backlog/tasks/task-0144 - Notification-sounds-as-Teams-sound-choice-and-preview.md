---
id: TASK-0144
title: Notification sounds as Teams (sound choice and preview)
status: To Do
assignee: []
created_date: '2026-11-15T03:46:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings ▸ Notifications ▸ Sound has a sound dropdown and a Preview button for notifications (Default, Vibe, Nudge, Tap, Flick, Pluck, Summon, Ping; stored in userPersonalSettings.emailSettings.alertSoundType). Urgent and priority contacts have their own (Default, Prioritize, Escalate, Alarm; alertUrgentSoundType). Teams plays these from audio files in its installed package (Audio/*.mp3, for example 00_teams_basic_notification_r4_default), not from a public CDN. OST ships no Microsoft sounds (its ringtone is synthesised). How OST gets each sound needs a decision before this can match Teams.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sound offers Teams' notification and urgent sound choices with Preview, saved where Teams saves them
- [ ] #2 Notifications play the chosen sound
<!-- AC:END -->
