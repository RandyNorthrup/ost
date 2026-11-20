---
id: TASK-0225
title: Interpreter (AI interpretation) in meetings as Teams
status: To Do
assignee: []
created_date: '2026-11-18T23:07:00Z'
updated_date: '2026-11-20T23:22:00Z'
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
- [ ] #1 Interpreter shows in OST's meeting controls exactly when it shows in Teams
- [ ] #2 Turning Interpreter on in OST gives the same interpreted audio and settings as Teams, verified live between test accounts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (callsC) research (scratchpad c225/research.md with ~270 strings): Interpreter = PUT conversation updateMeetingSettings {aiInterpretationEnabled:true}; wait for meetingCapability.aiInterpretationEnabled; aiVoiceConsent participant property; POST joinMeetingGroup {meetingGroupLabel:<lang>, groupPreferences:{muteDefaultAudio:false}, links.joinMeetingGroupStatus, operationId} (retry 6x1.5 s on 404/6011, 500/5406); roster self meetingGroupDetails.groups.languageGroup[0].id = a meetingDetails.meetingGroups languageGroup {id,label}; leave = POST leaveMeetingGroup {meetingGroup:id}; off for all = {aiInterpretationEnabled:false, aiInterpretationEnabledForAllParticipants:false}. Server adds the bots (output 28:5f2511f1-6da9-41d9-80d9-af7da23a2c27 per-language endpoints, role interpreter); desktop balances interpreter sources vs others over x-much2 (default 0.8, slider -100..100). Gate: ECS enableAiInterpretation && supported (not E2EE, not human interpretation, 1:1 allowed by live ECS) && (meetingPolicy.aiInterpreter Enabled && Copilot licence || enabled for all). Entry: More > Language and speech > Interpreter; turn on opens the settings dialog (enableAiInterpretationTurnOnOpensSettingsDialog).

- 2026-11-20 built: calling::ai_interpreter (meeting state from meetingDetails, our language group and the interpreter's audio sources from rosters, Teams' joinMeetingGroup / leaveMeetingGroup / settings / aiVoiceConsent bodies, the balance gains), OutgoingCall join_meeting_group (Teams' retries) / leave_meeting_group / set_ai_interpretation / set_ai_voice_consent, conversation links joinMeetingGroup/leaveMeetingGroup; backend call_interpreter_json + interpreter_action (turnOn: settings PUT, wait for aiInterpretationEnabled, join the group; save; offForMe; offForAll), availability = meetingPolicy aiInterpreter Enabled + Copilot licence (or enabled for all), prefs kept on this device; x-much2 asked for while listening and the interpreter vs others balanced in MuchMixer (OST's linear curve; Teams' native curve isn't in the bundles); More > Language and speech > Interpreter (submenu Turn off for me / for all / settings), the new controls' grid tile, AiInterpreterDialog, harness --join-interpreter.
- Live 2026-11-20 (linuxlt profile default = ost-test1 in "OST calendar test"): availability policy Enabled + Copilot -> Interpreter offered; Turn on for me (Spanish): updateMeetingSettings -> meetingCapability.aiInterpretationEnabled, Join meeting group 202, joinMeetingGroupStatus code 0, roster put our endpoint in group es (270514aa-…) and the interpreter bot's source 414 in it; meeting audio renegotiated per speaker (x-much2 taken). Teams on winpc (same user, second device) then showed Interpreter in More's grid; clicking it opened "Choose an Interpreter mode" (Consecutive "Uses credits"/"On for everyone" with two language boxes, Simultaneous "On for you"; Cancel / Turn on|Next; 490x525.33), then "Set up your Interpreter" (480x252: "You'll hear speech translated into", the language box, checkbox "Allow AI to simulate my voice when others hear my translated speech", Cancel / Turn on for me) — dumps in scratchpad c225/modedlg.json, setupdlg.json.
- Open: (1) Teams on winpc gets the mode-selection step (turn-by-turn is on for it although OST's ECS copy lacks enableAiInterpretationTurnByTurnMode) and the compact setup dialog; OST goes straight to its fuller settings dialog -> needs the mode dialog, the 480-wide setup layout and turn-by-turn; (2) interpreted audio not heard yet: the English speaker (OST Test 2 with the speech rig) sat in the meeting's OrganizerOnly lobby (no longer co-organizer); needs a re-run with the speaker admitted; (3) indicator, alerts and tile badges not built.
<!-- SECTION:NOTES:END -->
