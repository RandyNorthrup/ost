---
id: TASK-0144
title: Notification sounds and ringtones as Teams (sound choice and preview)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T03:46:00Z'
updated_date: '2026-11-15T19:19:00Z'
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
- [x] #1 Sound offers Teams' notification and urgent sound choices with Preview, saved where Teams saves them
- [x] #2 Notifications play the chosen sound
- [x] #3 Calls offers 'Choose a ringtone for you' with Teams' ringtones and a play button, saved where Teams saves it, and incoming calls ring with it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Also Settings ▸ Calls ▸ 'Choose a ringtone for you' (dropdown + play button; Teams' ringtoneSettings assignments Regular/CallGroup/CallQueue/Delegate), which plays Teams' packaged ringtone files: the same decision about Microsoft's sound files.

2026-11-15: user decided: "we can use the same audio as teams and if it becomes an issue later we will change them".
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST sounds as Teams does: Teams' notification sounds and ringtones (its own files, as the user chose), chosen and stored where Teams keeps them.

- assets/sounds: Teams' 8 notification sounds, 3 urgent sounds, 18 ringtones (public evergreen assets) and its meet-up reminder (package).
- Settings ▸ Notifications ▸ Sound: Teams' rows (labels wrap at 332.3, 44/64 apart), the notification and urgent sound dropdowns (toastSettings.alertSoundType / alertUrgentSoundType) with Preview sound; card 296.3 as Teams.
- Settings ▸ Calls ▸ Choose a ringtone for you: Teams' 18 ringtones with Preview ringtone, saved with POST {mt}/beta/usersettings/{mri}/ringtonesettings (other call types kept) and read from useraggregatesettings voiceAdminSettings; card 385.7 as Teams.
- Banners play the chosen sound (urgent ones the urgent sound when that is on; meeting started: Teams' meet-up reminder); incoming calls ring with the chosen ringtone on the speaker and the secondary ringer (QML MediaPlayer; the engine's synthesised ring is no longer used for calls).

Tests: cards-test Sound/Calls heights; ringtone set/read against the service (Bubbles, then back to Default); a real call rang with bubbles.mp3; a real chat banner played Teams' default sound.
<!-- SECTION:FINAL_SUMMARY:END -->
