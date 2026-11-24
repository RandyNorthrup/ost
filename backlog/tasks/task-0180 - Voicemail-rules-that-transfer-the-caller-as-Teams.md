---
id: TASK-0180
title: Voicemail rules that transfer the caller, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-19T15:45:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' voicemail answer rules include two that transfer the caller to a picked person; OST offers the other three.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Both transfer rules show with Teams' people picker and save where Teams saves them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research (settings-app rg/bA/$a; 527114 getVoicemailSettings):
  - Teams reads the voicemail settings from the voice admin settings' electedSettings (useraggregatesettings voiceAdminSettings).
  - It saves the whole object plus the change (POST {mt}/beta/usersettings/{mri}/voicemailsettings).
  - Five rules: RegularVoicemail, VoicemailWithTransferOption, PromptOnly, PromptOnlyWithTransfer, DeclineCall.
  - A transfer rule with no target is held locally until someone is picked.
  - Then vmTransferTarget {objectId, tenantId (when there is an oid), type User|ApplicationEndpoint|Pstn, sipUri null, telUri = mri minus the first "4:"} is saved with vmCallAnswerRule.
  - Delete only clears the box; nothing is saved.
  - Picker filter voicemailTransferTarget: AADTenant, Guest, B2BMembers, Bot, DisabledUser, ModernGroup, UserDefinedGroup, Pstn, CallQandAA, SkypeConsumer.
- Measured on winpc:
  - The picker box is 294 x 33.3, filled #F0F0F0, radius 4, right-aligned 15.6 under the dropdown; placeholder "Type a name or number".
  - Suggestions are 50 px rows: avatar 32 at (12,9); name at x 60 with the typed part bold; a second line 12/16 #616161.
  - Typed letters become a +1 keypad number, shown with an External badge and a #48D1CC avatar.
  - The chosen target is a 294 x 48 box: avatar 32 at (12,8) with presence; name at 52; Delete 32 x 31.3 at 255.
  - Dropdown options are 32 or 52 tall (wrapped), with 2 px gaps.
- winpc's ost-test1 now has VoicemailWithTransferOption with OST Test 2 as the target (set while measuring). Put it back to the original (rule unset) through OST.
- Built:
  - api::preferences voice_admin_settings / voicemail_settings_of / voicemail_transfer_target.
  - backend mt.vm, with a whole-object save.
  - VoicemailTransferPicker.qml and Settings' five rules.
  - Harness --vm-transfer-test.

- Status 2026-11-19:
  - Verified live: OST reads the electedSettings that Teams saved (VoicemailWithTransferOption + OST Test 2), and shows them in Teams' 294x48 target box.
  - Verified live: OST's picker suggestions ("OST Test" → "+1 6788378" External, OST Test 2 / OST-TEST2, OST Test 3…) and picking OST Test 3. Saved and read back from the service; Teams on winpc then showed OST Test 3.
  - Measured since: a whole US number shows as "+1 425-555-0100". The PSTN picture is Teams' mediumturquoise square with person_20_regular. The External badge icon is Teams' own people-error 16 filled.
  - Open: put ost-test1 back to the original (rule unset, no target) with `--vm-transfer-test --vm-transfer-raw='{"vmCallAnswerRule":null,"vmTransferTarget":null}'` and check the read-back. The dark-mode badge colours are not measured.

- 2026-11-19: ost-test1 restored (vmCallAnswerRule null, vmTransferTarget null, read back from the service as unset).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Voicemail transfer rules as Teams.

- Settings ▸ Calls reads voicemail settings from electedSettings and saves the whole object plus the change, as Teams does; all five answer rules; a transfer rule is only saved once a target is picked.
- VoicemailTransferPicker.qml: Teams' people picker with presence, External phone suggestions formatted as Teams, the chosen-target box with Delete (measured on winpc).
- Live: OST read the target Teams saved; OST saved OST Test 3 and Teams on winpc showed it; ost-test1 restored to unset.
- 787 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
