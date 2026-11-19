---
id: TASK-0182
title: Sign language mode as Teams
status: To Do
assignee: []
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-19T14:40:00Z'
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
- [ ] #1 With it on, meetings show Teams' signer view and settings, as Teams
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
<!-- SECTION:NOTES:END -->
