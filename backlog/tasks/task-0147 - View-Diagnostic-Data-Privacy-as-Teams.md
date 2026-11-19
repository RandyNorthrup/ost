---
id: TASK-0147
title: View Diagnostic Data (Privacy) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-19T14:18:00Z'
labels:
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > Privacy > View Diagnostic Data > Manage opens its diagnostic data viewer (privacy_trusted_ui_diagnostic_data_viewer when ECS telemetry.enableTUIDdv), listing the diagnostic events the app sends to Microsoft. OST sends no diagnostic events to Microsoft yet. Decide what the viewer shows for OST (what it sends), then build it with Teams' layout; until then the card is left out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Privacy shows 'View Diagnostic Data' with a Manage button as Teams
- [ ] #2 Manage opens a viewer laid out as Teams' diagnostic data viewer, listing exactly the diagnostic data OST sends
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research (settings-app FF/RF/b8; live on winpc):
  - The Privacy card "View Diagnostic Data" (DataArea icon) with Manage (96x31) sits between the screen-lock card and Extended diagnostics data, 73.3 tall. It shows when ECS telemetry.enableDdv or enableTUIDdv is on and the OCPS level isn't "Neither".
  - Manage opens Privacy › "Diagnostic data viewer" (live: the trusted-UI iframe, 790x224 at pane 20,21).
  - The page: "View Diagnostic Data" 16/700/22; at y37 the description 14/20; at y85 the disclaimer; at y153 "Learn More" (https://support.microsoft.com/office/using-the-diagnostic-data-viewer-with-office-cf761ce9-d805-4c60-a339-4e07f3182855); at y188 the switch (56x36 hit area) with "Enable data viewing" 16/700 at x56.
  - With the switch on: "Diagnostic data viewer connection string" 14/600 at y239; an input 324x31 at (1,268) beside Connect (96x32, brand) at x335. Status: "Attempting to establish connection..." / "Connection established" / "Couldn't connect. …", plus a check or error icon in the input.
  - Teams has no event list of its own. The viewer is Microsoft's Windows Diagnostic Data Viewer: the host streams the app's diagnostic data to it over HTTP for 24 h.
- OST sends no telemetry. What it does send that is diagnostic data:
  - the update check (GitHub releases/latest with User-Agent ost/<version>);
  - Report a problem / compliment / call quality details (a GitHub issue URL opened in the browser, with the version, OS and masked logs if chosen);
  - suggested-reply feedback.
  Each is now recorded with api::ddv::record and, while data viewing is connected, streamed to the viewer.
- Built: api::ddv (state in ~/.config/ost/ddv.json, a private-IPv4 connection string, the 24 h expiry, events); the Privacy card and the viewer page; backend ddv_json / load_ddv / set_ddv_enabled / connect_ddv.
- Pending: the wire format (api/ddv/wire.rs). It will be captured from Teams on winpc against a linuxlt listener, then checked against the real Windows DDV.

- Status 2026-11-19:
  - Protocol captured from Teams on winpc against a linuxlt listener:
    - Connect is GET / then an empty POST /.
    - Events are POSTs of raw-deflated Bond CompactBinary Common Schema 3.0 records, with headers App-Name, App-Platform, Machine-Identifier, Content-Type Application/bond-compact-binary.
    - Decoder: scratchpad set/bond.py.
  - Built: api/ddv/wire.rs (the same format: record fields 1/2/3/5/6/23/24/25/32/33/60/70).
  - Verified (--ddv-test=10.10.11.110:8787):
    - The OST page matches Teams' layout; the Privacy card is 73.3 tall, 12 under the screen-lock card.
    - Connect gives "Connection established" with the check icon; the Ost.UpdateCheck event reached the listener; it decodes to the same structure as Teams' records.
  - Incident: Teams' host (ms-teams.exe) crashed once at 05:49:54 while streaming to the listener (C++ exception 0xe06d7363), and restarted itself. Data viewing is now off in Teams.
  - Open: Microsoft's Windows Diagnostic Data Viewer was not used: it may need the Windows Diagnostics setting, which must not be changed.
<!-- SECTION:NOTES:END -->
