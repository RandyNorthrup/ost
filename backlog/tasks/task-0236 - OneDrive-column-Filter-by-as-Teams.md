---
id: TASK-0236
title: OneDrive column Filter by as Teams
status: To Do
assignee: []
created_date: '2026-11-20T15:35:00Z'
updated_date: '2026-11-20T20:07:00Z'
labels:
  - files
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0189: the Modified and Modified By column menus in Teams have Filter by, which OST doesn't build yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Filter by in the Modified and Modified By column menus works as in Teams, verified against Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 measured on winpc (Teams OneDrive app, My files, odsp-web-prod_2026-11-06.005):
  - Header menu Filter by opens a right pane (340 wide, full height, white, shadow 0 0 8 .12 + 0 32 64 .14): title "Filter by '{col}'" 20/600 #616161 at 24,20 (+" (N)" when N ticked), Close X 32x32 at right 30; rows of checkbox (16 px, x+8) + text 14 #616161; Apply (80x32, primary when changed) and Clear all (84x32) at the bottom (16 from it). Clear all only unticks; nothing happens until Apply. Apply closes the pane.
  - Values: POST {web}/_api/web/GetListUsingPath(DecodedUrl=@a1)/RenderListFilterData?@a1='{list}'&FieldInternalName='Editor|Modified'&ViewId='{view}'&RootFolder={folder}&{current filters}; reply value = base64 HTML <SELECT> of <OPTION Value="v">label</OPTION> after (All).
  - Modified By pane: a people box "Enter a name or email address" (290x34; ClientPeoplePickerSearchUser QueryString per keystroke, MaximumEntitySuggestions 30, PrincipalType 13, PrincipalSource 15, UseSubstrateSearch true; suggestions 260 wide rows 54 with 40 px pictures), then @Me (row 32), then each editor (row 40, 24 px picture). A picked person is added ticked; box clears.
  - Modified pane: no box; the distinct dates M/D/YYYY (option values YYYY-MM-DD), rows 32.
  - Filtering = RenderListDataAsStream with FilterField1=Editor&FilterValue1=SharePoint App&FilterType1=User (one value), FilterFields1/FilterValues1=a;#b/FilterTypes1 (several), Modified: FilterField1=Modified&FilterValue1=2026-11-11&FilterType1=DateTime&FilterDisplay1=11/11/2026; both columns = numbered 1,2. With @Me: no URL filter, body OverrideViewXml <View><Query><Where><Or id="Editor"> nested <Or> of <Eq><FieldRef Name="Editor"/><Value Type="User">name</Value></Eq> and <Value Type="User"><UserID/></Value>.
  - Filtered list: a bar above the header (42.67 tall, starts x+25): "Modified:" / "Modified By:" label 14 #424242, chips (24 tall, radius 12, 24 px round picture for people, text 13.33, X 16) 8 apart, "[Me]" for @Me; a "Clear X" pill at the right (22 tall, 1 px #424242, radius 12) clears all. A chip X removes that value (re-query). Header shows a funnel icon after its name; its menu shows "✓ Filter by (N)".
  - Restored: filters cleared, Teams back on Chat.
- Teams' picker All files still shows the stuck "Please sign in" (TASK-0128 AC2 can't be measured live).

- 2026-11-20 built (agent tuiF): Filter by in the Modified / Modified By menus ("Filter by (N)" ticked when filtered), header funnel, the right pane (Modified By: people box via ClientPeoplePickerSearchUser, @Me, editors; Modified: dates) from RenderListFilterData, Apply / Clear all, the chip bar with Clear; filtered rows from RenderListDataAsStream with OneDrive's FilterField/FilterValues params (OverrideViewXml CAML with @Me). api::list_rows filter_request/filter_values/filter_people (+ tests), backend drive_set_filters / drive_filter_values / drive_filter_people, harness --filter-by-test; spec docs/spec/onedrive-rows.md. Pending: live run.

- 2026-11-20 verified live (agent tuiF, linuxlt, ost-test1, --filter-by-test at 1280x680): menus "Filter by" / "Filter by (1)" ticked; Modified By pane listed @Me, OST Test 1, SharePoint App (RenderListFilterData); SharePoint App applied -> only Recordings (as Teams on winpc); +OST Test 1 -> all 11; Modified pane listed the 7 dates 11/5..11/16/2026 (same as Teams) and 11/5 + both editors -> Microsoft Teams Chat Files, Notebooks; the box found OST Test 2 and added it ticked; @Me applied (CAML <UserID/> merged into OST's ViewXml: SharePoint ignores OverrideViewXml next to a ViewXml); chip X and Clear restored all rows. Bar, chips, [Me], funnel and pane match the winpc captures. German run: pane in OneDrive's German ("Filtern nach \"Geändert von\" (3)", "Einen Namen oder eine E-Mail-Adresse eingeben", "Anwenden", "Alle löschen"). Fixes found live: RenderListFilterData answers HTML (sharing::send_text), font.pixelSize must be int.
<!-- SECTION:NOTES:END -->
