---
id: TASK-0183
title: >-
  Keyboard shortcuts: react to last message, announce active speaker, profile in
  the dialog, as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-19T17:27:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST lacks these two shortcuts and has the profile choice only in Settings ▸ General.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both shortcuts work as Teams'
- [ ] #2 The Keyboard shortcuts dialog offers the profile choice as Teams'
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research (async-entry keymaps; 74041 ca; calling-app nz):
  - ReactToLastMessage is Ctrl+Alt+R (Slack: Ctrl+Shift+\). It focuses the message pane's latest message, then that message's firstReactionItem-<mid> (the first quick reaction in its hover bar).
  - AnnounceActiveSpeaker is Ctrl+Alt+Shift+S (Zoom: Ctrl+2). It announces aria-live, assertive: "Latest speaker: {{speakerOrStatus}}", where the status is the name, "Unknown", or "Nobody is speaking" when there is no dominant speaker or they are missing from the roster. When a paired signer's interpreter speaks: "{{signerDisplayName}} voiced by {{interpreterDisplayName}}".
  - Profiles for Windows desktop (Z: chats_alt L, meetings_alt N, chats_meetings_alt V). The dialog's "N available changes" counts the profile's entries that change a listed row (21 / 11 / 40 in Teams).
- Dialog measured on winpc (dialog-relative):
  - Title 16/700 at (25,28); Close 32x31 at (851,28).
  - "Use shortcuts from other apps" 14/400 at (23,66), height 24.
  - Profile dropdown 224x30 at (23,90): "Teams only (default)". Options are 48 tall: label plus "Default" / "21 available changes", with 2 px gaps.
  - Apply 62x31 at (258,90): disabled until the pick differs from the saved profile.
  - View options 32x31 at (328,90), shown only for a non-default pick. Its menu is 300x115 at the button's bottom right, with two menuitemcheckbox rows of 52: "Highlight shortcuts from other apps" (on) and "Bring shortcuts from other apps to top" (off).
  - Filter 280x31 at (597,90). Sections start at y 131.
  - A previewed change highlights its label and key tokens: #DCE0FA (colorBrandBackground2Hover), weight 600.
  - The winpc profile was never applied; it is back to Teams only.
- Built:
  - KeyboardShortcuts.qml: profile dropdown, Apply, View options, highlight / bring to top, the two new rows.
  - Main.qml: Ctrl+Alt+R / Ctrl+Shift+\ call conversation.reactToLatest().
  - HoverBar: keyboard focus on the quick reactions.
  - CallWindow: announceActiveSpeaker with Ctrl+Alt+Shift+S / Ctrl+2.
  - OutlineDropdown: sublabel, display, 2 px gaps, wrapping.
  - Harness --kb-dialog-test (KbDialogTest.qml).

- Status 2026-11-19, verified on linuxlt (--kb-dialog-test, real key events):
  - Ctrl+. opens the dialog. Previews: Slack 12 changes, Zoom 6, combined 18 (OST's listed rows, counted by Teams' rule). Changed rows are highlighted. Closes without Apply.
  - Ctrl+Alt+R in a chat shows the newest message's hover bar with the first quick reaction focused (outlined); Right moves; Escape returns to compose.
  - Teams' Zoom preview shows only the first key of a multi-key command (Alt + A), as OST does.
  - Open: Announce active speaker is not yet pressed in a live call (the ANNOUNCE line via --kb-dialog-call).

- Merged c4696d0 (2026-11-19) into desktop/foundation; 787 lib, 28 vfx, 29 desktop tests passed. See the notes above for what is verified and open. (Voice isolation model is downloaded on first need with a pinned SHA-256, not committed.)

- 2026-11-19 (set2): Teams' rule (calling-app nz/_5/K5/ez, 256699 N): the dominant speaker unless missing from the roster; their name, "Unknown" if empty; an interpreter tethered to a signer: "<signer> voiced by <interpreter>", "You" when you are that signer (q5 on your tetheredSignerInterpreters), the signer only when exactly one names them. Built in announceActiveSpeaker (case logged). Live press via --voice-isolation-test --vi-announce.

- 2026-11-19 live (linuxlt, real key events via --voice-isolation-test --vi-announce): in the OST calendar test meeting Ctrl+Alt+Shift+S announced "Latest speaker: OST Test 1" (known_speaker) every 5 s; with sign language mode (OST Test 2 Signer, OST Test 1 Interpreter speaking through a virtual mic) OST Test 2's press announced "Latest speaker: You voiced by OST Test 1" (paired_signer), Teams' tethered case. Not yet compared side by side with Teams on winpc (needs the user's OK for winpc GUI/CDP).
<!-- SECTION:NOTES:END -->
