---
id: TASK-0211
title: Test call and meeting Copilot leftovers as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T23:39:00Z'
updated_date: '2026-11-18T15:19:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0141 and TASK-0188 (docs/spec/call-and-meeting-window.md):
- The Echo bot shows as round "EC" initials; Teams shows a square bot avatar. OST can't detect some of Teams' test-call report causes (call drop, device permission, camera freeze).
- Meeting Copilot loads the app as Teams on the web does, not desktop's pre-rendered form (welcome text differs); "Turn on Copilot for everyone?" (only during the meeting) isn't built; userEligibilityInformation and some feature flags go unanswered; in the classic bar Copilot moves into More while its pane is open.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Echo bot's avatar and the test-call report causes match Teams
- [x] #2 Meeting Copilot opens with Teams desktop's first page, answers all of the app's host messages, and offers Turn on Copilot for everyone as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-18 Teams desktop read on winpc (CDP, read-only hooks on both sides of the Copilot frame) and in its bundles:
  - Echo bot avatar: every 28: participant is a bot; its tile is Fluent's agent avatar (radius 4, shadow4) holding a squircle picture (border-radius 50% + corner-shape squircle, #FAFAFA, 1 px rgba(0,0,0,.05) inset outline); the Echo bot has no picture, so Teams' default bot image (module 961014). Built as BotAvatar.qml + assets/illustrations/default-bot.png.
  - Report causes (addDescriptionForQualityEvent; rules per Microsoft's ACS User Facing Diagnostics): permission refused, device start failure, camera without frames for 5 s, network disconnected. Built calling::device_health (open outcomes, camera frames, default route; PipeWire socket refusal = mic permission) and echo_report::Watch::devices. "Teams needs permission" reads "OST needs permission".
  - Copilot pane: Teams desktop server-renders it (ChatReady renderMode SSR); its whole conversation is initialize, getContext x2, registerHandler, ChatReady, appInitialization.success, NAA, shortcutRelay.getHostShortcuts. OST now posts the SSR form, adds appPerformanceMetrics / copilot.eligibility / mouseRelay, hostRing, the meeting window's shortcut list.
  - "Turn on Copilot for everyone?" (copilot-ufd-control Fn/Nn/M.Op): copilotMode "Enabled" with no transcript or Copilot running; Turn on asks the spoken language and sends the recorder {mode: transcription, processingModes: [copilot]}; then Teams' "Copilot is available in this meeting" notice. Calls ask "Turn on Copilot for everyone in this call?" (Just Copilot / Transcribe) and say "in the call".
- Tenant: to test copilotMode "Enabled" a meeting policy "OST test accounts" (Global's settings, Copilot = Enabled) was granted to ost-test1 only, then removed again the same day (ost-test1 back on Global).
- Verified live on linuxlt (OST, ost-test1; pictures in linuxlt:~/cop211/shots): tc7/tc9-call (bot avatar), tc3-report (camera frozen 9 s: Didn't work), tc4-report (camera chmod 000: OST needs permission), tc5-report (network namespace's route removed 8 s: Call drop detected), tc10-report (PipeWire socket refused: mic OST needs permission), tc9-copilot-ask (call variant), cop1/cop2-copilot-ask, -language, -pane (SSR first page, Copilot alone running, notice with Privacy policy), StartCopilot/StopCopilot 200 OK; no unhandled host messages. Every call left (hung up the call leg / bot left). Test meetings deleted.
- Open: Teams' ubar overflow is width-only (no rule keeps an open pane's button), so whether Copilot moving into More with the pane open differs from Teams wasn't measured.

- Merged 39cfa18 (2026-11-18): build OK, 734 lib tests passed. AC1 done (verified live). AC2 open: Teams' own Turn on Copilot for everyone? and Copilot's place in the bar with the pane open are being measured on winpc.
- 2026-11-18 (follow-up) measured live in Teams desktop on winpc, ost-test1 under the temporary policy (Copilot "Only during the meeting"; removed again the same day, test meetings deleted):
  - In a meeting with copilotMode Enabled, Copilot asks nothing more: straight to "What language is everyone speaking?", then Copilot alone and the notice "Copilot is available in this meeting" / "...during the meeting and an Intelligent recap after the meeting. Interactions and summaries..." (320 wide, #FAFAFA, 0.67 #F0F0F0, Sparkle 20, centred over the stage). "Turn on Copilot for everyone?" needs the flag enableToggleCopilotDuringMeeting, absent here. OST now does the same (the call variant stays as in the code).
  - Echo test call: Copilot opens its pane at once (no alert); its classic bar has no Apps. OST matches.
  - Copilot pane and side panes: Teams' end slot widths (32rem < 947, 36rem to 1439, 42rem, 48rem, 60rem); 360 at 1280. With the pane open at 1280 both bars keep Copilot; OST matches (cop3-copilot-pane, tc12-copilot-ask).
- The mic-permission rig side effect (speaker "Didn't work") comes from the rig: refusing the PipeWire socket takes the speaker away too; OST reports that correctly. Not an OST bug.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Test call and meeting Copilot now match Teams desktop, measured live on winpc.

- Echo bot: square bot avatar (BotAvatar.qml) with Teams' default bot image for every 28: participant.
- Test-call report causes from src/calling/device_health.rs: permission refused, device failed to start, camera frozen >5 s, network disconnected; each caused and checked live.
- Meeting Copilot: first page rendered server-side as desktop does (SSR form, hostRing, runtime capabilities); no unhandled host messages.
- Copilot "Only during the meeting": as in this tenant's Teams (enableToggleCopilotDuringMeeting off), Copilot goes straight to the spoken-language question, runs alone and shows Teams' notice (text and geometry measured). The call version is built from Teams' code. Echo test call: Copilot pane opens at once, no Apps on the classic bar.
- Side panes use Teams' width steps (320/360/420/480/600); Copilot stays on the bar at 1280.
- Harness: --test-call-copilot, --join-subject=, --join-copilot-turn-on, --call-window=WxH, OST_CAMERA_DEVICE.
- Tests: 734 lib tests pass. A temporary ost-test1-only meeting policy was used and removed.
<!-- SECTION:FINAL_SUMMARY:END -->
