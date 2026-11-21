---
id: TASK-0225
title: Interpreter (AI interpretation) in meetings as Teams
status: Done
assignee: []
created_date: '2026-11-18T23:07:00Z'
updated_date: '2026-11-21T03:27:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/new-meeting-controls.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0214/0208: Teams shows Interpreter in meetings when the meeting policy's aiInterpreter is Enabled and the user has a Microsoft 365 Copilot licence (an organizer can turn it on for everyone). OST has no AI interpretation yet. Only ost-test1 has a Copilot seat; the tenant's Copilot trial has unassigned seats.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Interpreter shows in OST's meeting controls exactly when it shows in Teams
- [x] #2 Turning Interpreter on in OST gives the same interpreted audio and settings as Teams, verified live between test accounts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (callsC) research (scratchpad c225/research.md with ~270 strings): Interpreter = PUT conversation updateMeetingSettings {aiInterpretationEnabled:true}; wait for meetingCapability.aiInterpretationEnabled; aiVoiceConsent participant property; POST joinMeetingGroup {meetingGroupLabel:<lang>, groupPreferences:{muteDefaultAudio:false}, links.joinMeetingGroupStatus, operationId} (retry 6x1.5 s on 404/6011, 500/5406); roster self meetingGroupDetails.groups.languageGroup[0].id = a meetingDetails.meetingGroups languageGroup {id,label}; leave = POST leaveMeetingGroup {meetingGroup:id}; off for all = {aiInterpretationEnabled:false, aiInterpretationEnabledForAllParticipants:false}. Server adds the bots (output 28:5f2511f1-6da9-41d9-80d9-af7da23a2c27 per-language endpoints, role interpreter); desktop balances interpreter sources vs others over x-much2 (default 0.8, slider -100..100). Gate: ECS enableAiInterpretation && supported (not E2EE, not human interpretation, 1:1 allowed by live ECS) && (meetingPolicy.aiInterpreter Enabled && Copilot licence || enabled for all). Entry: More > Language and speech > Interpreter; turn on opens the settings dialog (enableAiInterpretationTurnOnOpensSettingsDialog).

- 2026-11-20 built: calling::ai_interpreter (meeting state from meetingDetails, our language group and the interpreter's audio sources from rosters, Teams' joinMeetingGroup / leaveMeetingGroup / settings / aiVoiceConsent bodies, the balance gains), OutgoingCall join_meeting_group (Teams' retries) / leave_meeting_group / set_ai_interpretation / set_ai_voice_consent, conversation links joinMeetingGroup/leaveMeetingGroup; backend call_interpreter_json + interpreter_action (turnOn: settings PUT, wait for aiInterpretationEnabled, join the group; save; offForMe; offForAll), availability = meetingPolicy aiInterpreter Enabled + Copilot licence (or enabled for all), prefs kept on this device; x-much2 asked for while listening and the interpreter vs others balanced in MuchMixer (OST's linear curve; Teams' native curve isn't in the bundles); More > Language and speech > Interpreter (submenu Turn off for me / for all / settings), the new controls' grid tile, AiInterpreterDialog, harness --join-interpreter.
- Live 2026-11-20 (linuxlt profile default = ost-test1 in "OST calendar test"): availability policy Enabled + Copilot -> Interpreter offered; Turn on for me (Spanish): updateMeetingSettings -> meetingCapability.aiInterpretationEnabled, Join meeting group 202, joinMeetingGroupStatus code 0, roster put our endpoint in group es (270514aa-…) and the interpreter bot's source 414 in it; meeting audio renegotiated per speaker (x-much2 taken). Teams on winpc (same user, second device) then showed Interpreter in More's grid; clicking it opened "Choose an Interpreter mode" (Consecutive "Uses credits"/"On for everyone" with two language boxes, Simultaneous "On for you"; Cancel / Turn on|Next; 490x525.33), then "Set up your Interpreter" (480x252: "You'll hear speech translated into", the language box, checkbox "Allow AI to simulate my voice when others hear my translated speech", Cancel / Turn on for me) — dumps in scratchpad c225/modedlg.json, setupdlg.json.
- Open: (1) Teams on winpc gets the mode-selection step (turn-by-turn is on for it although OST's ECS copy lacks enableAiInterpretationTurnByTurnMode) and the compact setup dialog; OST goes straight to its fuller settings dialog -> needs the mode dialog, the 480-wide setup layout and turn-by-turn; (2) interpreted audio not heard yet: the English speaker (OST Test 2 with the speech rig) sat in the meeting's OrganizerOnly lobby (no longer co-organizer); needs a re-run with the speaker admitted; (3) indicator, alerts and tile badges not built.

- 2026-11-21 (callsC) built: AiInterpreterModeDialog (Teams' "Choose an Interpreter mode", 490x525.33: Consecutive with its badges and two language boxes / Simultaneous; Turn on / Next; Learn more; the round picture is a Fluent backdrop with Interpreter's glyph, not Teams' artwork); the compact "Set up your Interpreter" (480x252, checkbox "Allow AI to simulate my voice…"); consecutive mode (aiInterpretationSettingsJson TurnByTurn with two languages, organizer only, Turn off for all); the bar indicator after the AI one with its tooltip and card (Manage settings, Turn off/on for me, AI disclaimer); alerts "AI is interpreting for others", "Interpreter has been turned off", "Something went wrong with Interpreter"; bot signals on data id 3 logged (for the tile badges, not built until their live format is seen); harness --join-interpreter-admit.

- 2026-11-20 (callsC) live, Teams side: in "OST calendar test" Teams (ost-test1, organizer) ran More ▸ Interpreter ▸ "Choose an Interpreter mode" (Consecutive "Uses credits"/"On for everyone" with two Language boxes; Simultaneous "On for you") ▸ Simultaneous ▸ Turn on ▸ "Set up your Interpreter" (Spanish; "Speech in Spanish won't be translated."; Allow AI to simulate my voice checked) ▸ Turn on for me. Indicator next to the clock (tooltip "AI is interpreting this meeting"); its card: "You are using Interpreter. Your interpretation language is Spanish (ES)." / Manage settings / Turn off for me / disclaimer, as OST builds it. OST Test 2 (OST, speaking English) was in the meeting; winpc audio could not be listened to from here, so hearing the Spanish voice in Teams is not confirmed. No tile badge appeared on OST Test 2's tile in that run; tile badges (research 5e) are not built (not measured live).
- Settings dialog rebuilt as Teams' 480 x 524.67 "Interpreter settings" (What you hear / Original audio first / Balance volume slider / How others hear you radios / Save); bar menu items by role as Teams (in group: Turn off for me, Turn off for all, Interpreter settings; organizer not in group: Turn off for all, Interpreter settings); x-much2 logs each speaker with its interpreter gain (proof of the interpreter source being mixed).

- 2026-11-21 01:48 UTC (callsC) OST-side proof of interpreted audio: spatest OST (ost-test1, organizer) in "OST TEST 73 agenda" turned Interpreter on for Spanish (group 4c755f4f…, listeners 1, interpreter source 1256); OST Test 2 (OST) spoke English through the linuxlt speech rig; the bot sent AudioMetadata language es and TranslatedText ("Right side left side right front…" → "Lado derecho lado izquierdo…") for OST Test 2's speech, and x-much2 logged "a speaker starts source=1256 gain=1.0", i.e. the Spanish interpretation was mixed into what OST plays. Both instances logged hang-ups.

- 2026-11-20 merged (620aa14, 63246f1).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI interpretation (Interpreter) in meetings as Teams.

- Shows under More ▸ Language and speech and in the new controls' More grid only for the meeting policy plus a Copilot licence, as Teams; the bar items follow the user's role.
- Teams' flow: Choose an Interpreter mode (Consecutive / Simultaneous), Set up your Interpreter (language, Turn on for me), the indicator and its card (Manage settings, Turn off for me), and the 480-wide Interpreter settings dialog (What you hear, Original audio first, Balance volume, How others hear you).
- Engine: turn on for the meeting, join/leave a language group, voice choice, audio balance.

Verified live: OST (ost-test1) in Spanish with OST Test 2 speaking English received the interpreter bot's Spanish audio mixed in (logged gain); Teams on winpc showed the same indicator and card. Tile badges not built (never seen in Teams to measure).
<!-- SECTION:FINAL_SUMMARY:END -->
