---
id: TASK-0062
title: In-meeting More menu items as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-08T20:41:00Z'
updated_date: '2026-11-09T05:30:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' More (…) menu in meetings (verified on winpc): Record and transcribe ▸, Meeting info, Timer, Video effects and settings, Audio settings, Language and speech ▸, Settings ▸, Report a concern, Help. The bar engine already places them from Teams' config; OST shows only Video effects and settings and Audio settings, which open OST's device settings rather than Teams' side panes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Meeting info opens Teams' meeting info pane (title, time, join link, dial-in, copy)
- [x] #2 Audio settings opens Teams' Audio settings side pane (Speaker, Microphone, Advanced settings with noise suppression and High fidelity music mode), as measured on winpc
- [x] #3 Record and transcribe ▸ starts and stops transcription and recording as Teams (menu, language and record-mode dialogs, stop confirmations), verified live
- [x] #4 Teams' Transcript side pane: opens when transcription starts, Hide/Show transcript in the menu, the live transcript and its events
- [x] #5 Starting transcription or recording where the meeting's recorder hasn't joined yet (group calls, fresh meetings) works as Teams
- [ ] #6 Report a concern as Teams (no real reports filed while testing)
- [ ] #7 Language and speech ▸ (live captions with their settings, pop-out window and RTT), Settings ▸ (Call health, Accessibility, Chat bubbles, Mute notifications) and Help as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#1 Meeting info: measured the pane on winpc (calling-right-side-panel) and read calling-meeting-info-panel + the calling service adapter (getExchangeMeetingInfo / getMeetingFormattedTime / recurrence formatter 197544).
- Data: join response meetingDetails (meetingChatProperties subject/location, start/end, iCalUid, shortJoinUrl) + calendar event by iCalUid (Graph body + recurrence).
- Copy join info verified byte-identical to Teams' clipboard (fallback "Join Teams meeting" with the short /meet/ link, as this meeting's body has no me-email-text block).
- Dial-in: the test tenant has no audio conferencing (pstnDetails null), so Teams shows no dial-in block either; not verifiable here.
- Qt rich text needs: <font size> dropped (Qt applies it on top of the span size), pt->px, word joiners in link text so URLs wrap as Chrome does.

- AC#4 Audio settings pane: read audio-settings-panel + spatial audio (196818), noise suppression (327752), music mode (697455); measured on winpc incl. music mode on/off (then reverted).
- Spatial audio row hidden: Teams hides it when the media stack can't render spatial audio (isSpatialAudioAvailable false); OST plays the server mix.
- Background noise only / Voice isolation radios hidden: Teams hides them when voice isolation is not supported (needs Microsoft's voice profile); NS row then shows its info button.
- Music mode (Microsoft: 32 kHz sampling, up to 128 kbps, mono): Opus retuned live to Audio/Music at 128 kbit/s full band, AGC off, AEC per checkbox; turning it on turns NS off and off restores NS (as Teams). "Display in the microphone dropdown menu" adds the row to Mic ▾.
- Video effects pane moved to TASK-0064 (its content is the background effects).

- Record and transcribe research (winpc capture 2026-11-09): Teams POSTs to the hidden recorder participant's endpointMetadata.commandUrl (from the roster; port changes) with Bearer token aud 4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76 scp access_recorder_service, header x-microsoft-skype-chain-id = call id. Body {timestamp, participantMri, participantLegId, action start|stop, mode "transcription" (transcript only), processingModes ["realTimeTranscript"] or ["recording","realTimeTranscript"], actionParameters {recordingFeatures{...}, recordingStorageSettings[{StorageType OnedriveForBusiness, StorageLocation Recordings, FileName "<title>-YYYYMMDD_HHMMSS-Meeting Transcript|Recording"}], iCalUid, correlationId, meetingTitle, exchangeId, meetingOrganizer, recordingMode "Normal" (recording), spokenLanguage, type start}, participantSkypeToken ""}; stop sends only the first fields. Response {CorrelationId}.
- Dialogs: spoken-language-selection-dialog 480 wide ("What language is everyone speaking?" / "Start recording and transcription" 522 wide with More options > Choose what to record: Video and audio); stop confirmations 400 wide ("Stop transcription?", "Stop recording and transcription?"). Teams then opens the Transcript side pane (RTAF storage artifacts).

- AC#4 done: src/calling/recorder.rs builds Teams' recorder commands (start/stop transcription, start recording [+transcript], recording only when the transcript runs, stop) and POSTs them to the recorder's commandUrl from the roster with a recorder-audience token (auth::oauth::access_token_for). Desktop: More > Record and transcribe ▸ (submenu opens left, Teams' glyphs and tooltips), RecordStartDialog (Teams' 57 spoken languages, verified against its loc keys; More options > Choose what to record), stop confirmations; failures show Teams' "Couldn't start recording" / transcription error notice.
- Verified live (--join-record): OST started and stopped transcription and recording in the test meeting; 200 from the recorder; roster states followed; Teams on winpc showed the same.
- Fixed on the way: roster updates are applied by participant version (an older update arrived after the stop and showed recording again); the call recorder (CallRecorder Bot) is hidden from the stage and count like Teams.

- AC#5 Transcript pane: live finals from the MCP data channel (0b83 frames), stored history via the rtaf getArtifacts link (speaker ids resolved as Teams' nt), measured layout, Go to current, Show/Hide transcript row with end check, auto-open when you start transcription. Verified live against winpc: same rows and grouping, OST-started transcript opens the pane, live stop event arrives.
- Fixed FluentIcon: a late icon reply could overwrite a newer glyph (the Mic showed on while muted at join).
- Follow-up TASK-0066: initials avatar colours differ from Teams.

- AC#2 progress: Language and speech ▸ Show/Hide live captions (Alt+Shift+C) with Teams' captions window, settings menu (spoken language, Caption styles pane, position, Always turn on captions, Filter profane words), recorder start command + endpoint metadata, accessibility user property. Verified live: captions render as Teams (one item per utterance, partials replaced), settings menu, styles at Large, metadata PUT 200.
- Not yet: captions start command against a recorder that is not already running captions (it stayed Active from Teams' session); pop-out captions window; RTT; Timer; Settings ▸; Help; Language settings pane (Transcript header button).
- Transcript pane now also shows each speaker's current partial (Teams' store logic).

- AC#6: OST invites the meeting's recorder (addParticipant with Teams' combined-bot botData) when it is not in the call, waits for its command URL, then sends the command. Verified live in a fresh meeting conversation: invited 202, joined in 3.7 s, StartCaptions 200, closedCaptions Active, metadata 200. The captions start body matched Teams' capture byte for byte.

- Timer moved to its own task (meeting timer app: ad-hoc, agenda, Run of Show).

- Settings ▸ Accessibility settings: Teams' in-meeting Accessibility pane (captions settings, Monitoring participants: hide the compact window when minimized except while sharing). Sign language mode and Muted notification cards stay hidden until those features exist (TASK-0068 for the notice). Left in Settings ▸: Call health, chat bubbles, Mute notifications.
<!-- SECTION:NOTES:END -->
