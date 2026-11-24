---
id: TASK-0182
title: Sign language mode as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T02:13:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST saves Teams' sign language setting but doesn't act on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With it on, meetings show Teams' signer view and settings, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research (settings-app, 527114 SignerMixin, 813237, calling-roster; agent dumps in linuxlt ~/sl-research and scratchpad sl/):
  - Storage: the callAccessibilitySettings user property: accessibilityModeEnabledV2, signLanguageModeSelection "SIGNER"|"INTERPRETER", showSignerIdentificationToOthers (true), selectedDHHInterpreters [mri] (tethering on); guests (8:teamsvisitor:, 8:guest:, 4:) are kept for the call only.
  - Meeting: POST links.publishState {from, publishedState {content, level "user", stateType "dhhSigner"|"signLanguageInterpreter", sequenceNumber}}.
    - Signer content: {"interpreterIds":"a,b","showSignerIdentificationToOthers":bool}; interpreter content: {}.
    - removeState {from, sequenceNumber, scope "specified", stateIds:[id]} when the mode goes off or the role changes.
  - Stage priority by your role: Signer → interpreters, Interpreter → signers, paired → your partners.
    - Gallery/speaker: the pin area, max 9. With content shared: focused area, max 2.
    - These tiles request the main (HQ) video.
  - People pane: role-matched people sort to the top; second line "Sign Language Interpreter" / "Your Sign Language Interpreter" / "Paired to you".
  - Tile icons: HandMultipleStack filled for signers (shown when they share their status or you are their interpreter); an interpreter icon.
  - Joining as a Signer with no interpreters: an 8 s alert "Add interpreters for your meetings" / "Select interpreters in your Accessibility settings for Sign language mode to work correctly. Learn more" (go.microsoft.com/fwlink/?linkid=2330204).
- Settings measured on winpc (in-card; the card is 276.7 tall with the mode on):
  - Rows (body x 57): Signer radio row top at 83; checkbox row at 129 (x +49); "Manage interpreters" button at 171 (x +28, 155x31); Interpreter radio at 208, 48 tall; 20.7 bottom padding.
  - Manage interpreters subpage (pane-relative): "Add someone as an interpreter" 18/700 at (20,20); "Please choose the interpreters for your meetings." 11.67px at (20,56); picker box 600 wide at (20,~82), 33.3 tall, placeholder "Add someone as an interpreter".
  - Teams was put back to sign language off.

- Status 2026-11-19:
  - Built:
    - Settings card (radios, checkbox, Manage interpreters) and the Manage interpreters page (picker, list, Remove as signer).
    - Meeting: publishState dhhSigner / signLanguageInterpreter (outgoing::sign_language_state); roster sign_role / sign_content.
    - CallWindow: role-based priority (first in order; featured in View ▸ Sign language, with the hand-wave icon); tile icons; People second line and sort; "Add interpreters" alert.
  - Verified live: ost-test1 as Signer published dhhSigner {interpreterIds, showSignerIdentificationToOthers} in the "OST calendar test" meeting; the view was set to accessibility.
  - Found: OST Test 2 has no user properties yet (404 UserProperties not found), so its Interpreter setting wasn't saved. call_accessibility_settings now treats that as defaults (rebuild pending). It also waited in the lobby: --sign-language-admit added.
  - Open: a two-account run with test2 as Interpreter (camera /dev/video20) checking priority, icon and People line; the interpreter icon name; the alert's icon; the signing badge; HQ video for priority tiles.

- 2026-11-19 two-account run (OST calendar test meeting): ost-test1 as Signer and OST Test 2 as Interpreter (in-call camera). Each published its role and read the other's. With the interpreter's video on, ost-test1's signFirst is [OST Test 2] and the Sign language view features them. People lines: 'Your Sign Language Interpreter' (signer side) and 'Paired to you' (interpreter side). The signer icon shows on OST Test 1's tile in OST Test 2's window. Both accounts were then put back to mode off with no interpreters.

- Merged c4696d0 (2026-11-19) into desktop/foundation; 787 lib, 28 vfx, 29 desktop tests passed. See the notes above for what is verified and open. (Voice isolation model is downloaded on first need with a pinned SHA-256, not committed.)

- 2026-11-19 (set2) research + build, uncommitted in worktree agent-a2f35e8cd5b26c3af:
  - Icons from the bundles: interpreter = M.Pc7 = bundleIcon(PersonSupportFilled, PersonSupportRegular) (module 698714/364739) -> assets person-support-20-filled.svg; signer = Teams' own HandMultipleStack (783885, filled `u`) -> hand-multiple-stack-20-filled.svg. Both filled at 16 px on the name tag.
  - "Add interpreters" alert: INTERPRETERS_NOT_SELECTED has no entry in Teams' UFD icon map (263640 `i` Map) and passes no icon, so Teams shows no glyph. OST's alert now has none; its text is interpreters_not_selected_text with Accessibility at 600 and the Learn more link (CallAlert richText).
  - Pin area: PinStage max 9 (303772 g3 / MAX_ITEMS_ON_STAGE_3x3); isPinningDisabled = pinned >= maxItemsOnStage, tooltip "You reached the maximum number of pins". Sign language view: FocusedStage 2. Order: role-matched signers, spotlights, pins in pin order. Built: CallWindow pinnedIds (9), pinArea/focusedArea in a GalleryGrid, side lists the rest.
  - HQ: 879019 shouldFocusMainStream (pinned/spotlighted/focused signer/sign people in pin or focused area) -> focus flag. Built: CallWindow videoFocus -> backend set_video_focus: focused people take video slots first and ask at 1920 (max-fs 8160).
  - Signing badge (agent research, ~/set2-research/signing-badge.md on linuxlt): detection in SlimCore (desktop) / websld ONNX worker (web); events are JSON {timestamp,duration,signDetected} on data channel data id 25 to everyone, stop after timeoutOfSigningSignal 3 s; badge = 5-bar waveform pill at the tile's top-left when actively signing and tethered; outline as speaking; active signers ahead of dominant speakers. Built: mcp SIGN_LANGUAGE_DATA_ID send/receive, meeting_media/outgoing send_sign_language, backend call_signing_json, MeetingTile badge + outline, CallWindow tetheredOf/signingTooltip. Native detector being built (vfx sign_detection).

- 2026-11-19 sign detection (native): MoveNet SinglePose Lightning (Apache-2.0, Xenova ONNX on Hugging Face pinned to commit ed0f314, SHA-256 1ad4f8d6...a464ad, 9.4 MB) downloaded on first need to <cache>/models/, run with tract ~10/s on a worker (vfx sign_detection + calling::sign_detection); signing = a wrist in the signing space that moves (>= 0.3 shoulder widths over 800 ms) or changes shape (fingerspelling); Teams' aggregator rules (start after 500 ms, still-signing from 2 s on 500 ms ticks, stop on a quiet tick or 3 s). Clips: ASL/NGT signers 0.83-0.90 of frames, talking heads 0.00-0.02, a gesturing speaker 0.20 (known false positive).
- 2026-11-19 live two-account run (OST calendar test meeting, linuxlt): OST Test 2 = Signer naming OST Test 1, camera a v4l2loopback device (/dev/video22, removed after) playing the CC BY-SA ASL demo clip; OST Test 1 = Interpreter. OST Test 2 detected signing and sent 259 data id 25 events (start / still signing / stop); OST Test 1 received them (active signers 1), showed the waveform badge (tethered: OST Test 1; tooltip "Voice interpretation in progress" as the interpreter) and the speaking outline, with OST Test 2 featured in the Sign language view and their video focused (HQ). On the signer's side the badge tooltip read "OST Test 1 is voice interpreting". Both left (hung up 202); both accounts put back to mode off with no interpreters.

- Merged cc5e866 (2026-11-19): see the agent notes above; 791 lib tests passed on linuxlt.

- 2026-11-19 three-account pin area check (linuxlt, OST calendar test meeting): ost-test1 pinned OST Test 2 and OST Test 3 (--vi-pin-all=2): both went to the pin area (pins/featured in pin order), their videos were focused (video focus count 2) and took slots; unpinned 30 s later (pins []). Two pinned on an 864x560 area first stacked 2x1; GalleryGrid now follows Teams' 1x2 rule for two people (aspect >= 1.25, oneByTwoGridSizeAspectRatioBreakpoint) and showed them side by side. All three left (hung up 202). test3's sign language settings were not touched.
- Open (OST bug seen, not this task): people who join before the organizer wait in the lobby and the organizer's lobby list stays empty, so they are never admitted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sign language mode as Teams.

- Settings ▸ Accessibility: Signer / Interpreter, "Show my signer status…", Manage interpreters, saved in Teams' callAccessibilitySettings (Teams' defaults when an account has none).
- Meetings: roles published as Teams does; your signers or interpreters come first, a Sign language view, Teams' tile icons, People lines ("Your Sign Language Interpreter", "Paired to you"), the "Add interpreters" alert with Teams' text; up to 9 people in the pin area (side by side when wide), featured tiles requesting the high-quality stream; a live signing badge from signing detection (MoveNet, downloaded with a pinned hash).
- Live: ost-test1 (Signer) and OST Test 2 (Interpreter) each saw the other's role; three-account pin area; signing badge from a CC-licensed ASL clip. Settings restored.
- 796 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
