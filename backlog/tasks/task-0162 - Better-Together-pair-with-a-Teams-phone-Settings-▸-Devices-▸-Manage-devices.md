---
id: TASK-0162
title: 'Better Together: pair with a Teams phone (Settings ▸ Devices ▸ Manage devices)'
status: To Do
assignee: []
created_date: '2026-11-15T20:59:00Z'
updated_date: '2026-11-21T08:00:00Z'
labels:
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Manage devices page (Settings ▸ Devices ▸ Connected devices) lists the Teams phones paired with the PC (Better Together: betterTogetherPairedDevicesChangedEvent, deviceName, Connected, Disconnect via betterTogetherUnpairDevice). OST shows the page with an empty list (TASK-0159). Pairing needs a Teams phone, or an emulation of one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A paired Teams phone shows on Manage devices with Teams' name, status and Disconnect
- [ ] #2 Disconnect unpairs it as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-20 (setF-0162) research, Teams 26304 bundles (527114 TransportConnectionHandler/TransportCommandRouter, settings-app BttDeviceSettings, r_data-client-calling) and SlimCoreWebview2.dll (BTT transport, Ghidra):
- Manage devices page (BetterTogetherManagePage): "Select a device to connect", then per paired device: phone icon, deviceName, "Connected" when connectionStatus is Connected (0; 1 PairedNotConnected, 2 Locked), and a "Disconnect" button. Disconnect = betterTogetherUnpairDevice(endpointId) -> TransportConnectionHandler.unpairDevice: send the phone an "unpair" command with {salt:[currentSalt]} and drop it from the list (disconnect if connected), persisted as pairedTransportCompanionDevices (user preference) / BTPairedDevices.
- Pairing: the phone sends "pair" with commandDetails {deviceName, clientType, clientVersion, endpointSignature, capabilities, salt}; the PC accepts without a scan if the salt matches its current salt (or capabilities has WIRED_CONNECTION), else scans BLE 15 s for the phone; then a confirm dialog (better_together_pair_title/_message {deviceName}/_button/_cancel_button), 50 s timeout; on Pair the device is stored Connected and the response is {accepted:true, salt}. Other phone commands: broadcast (reply deviceName = OS + salt), autopair, unpair, locked, unlocked, updateendpoint, response; PC sends keepalive every 30 s, lock/unlock, unpair, response.
- Companion beacon: Microsoft 0x0006 data 34 F0 40, 16-byte packed user oid, byte 16, salt = d[18]<<8|d[17], endpointSignature int16 LE at 19 (or endpoint id bytes 15,14); RSSI >= -75.
- Transport (SlimCore BTT): commands are JSON {registrationId, command, commandSequenceNumber, commandDetails, transportDetails {context, endpointType, url}, debugContent {chainId, causeId}} POSTed to the peer's Trouter path "bettertogether" (headers X-Skypetoken or Bearer, MS-CV, X-Microsoft-Skype-Chain-ID / -Message-ID); endpoints found through the registrar (prod.registrar.skype.com/v2/registrations). Endpoint id = the calling registration id.

- Built (not yet live-verified): engine api::better_together (message codec, beacon, registrar register/discover, send, acks), Trouter routing of the bettertogether path (acks in the Trouter reply, EventKind::BetterTogether), desktop better_together.rs (pair prompt, list, keepalive/lock/unlock, Disconnect), room_ble companion scanning, Manage devices list + pairing dialog in QML, harness --better-together-test, emulator examples/teams_phone.rs. Rig: ~/bt162-rig.sh up|down on linuxlt (btvirt pair: OST scans hci1, phone advertises on hci2 00:AA:01:01:00:02; RSSI invalid -> OST_BT_ASSUMED_RSSI=-40). Open: registrar BTT registration/discover format and the pair dialog strings (missing from Teams' en-us resources) to read on winpc.

2026-11-21 live findings (linuxlt spatest, registrar listing; winpc CDP read-only):
- Teams desktop registers Better Together as a second Trouter transport on its calling registration (NextGenCalling, DesktopNgc_2.5:SkypeNgc): context "BetterTogether", path https://<socket>-t.trouter.teams.microsoft.com:443/v3/f/<id>/bettertogether/send. No registration of its own. The registrar lists {bindings: [...]} with lowercase "trouter" transports.
- A command POSTed with a Skype token to the socket's -t host at port 443 is delivered to the socket (3::: frame, url .../bettertogether/send, headers ms-cv, x-microsoft-skype-chain-id/-message-id, Trouter-Timeout ~7 s); the -f host at 3443 answers 401. The ack in the Trouter reply (200 {}) is the sender's HTTP answer.
- Teams' pairing strings (CDP): "Connection request", "<name> would like to pair with your PC.\nClick on "Connect" to approve.", Connect / Cancel. Page: "Manage devices", "Select a device to connect", "Connected", "Disconnect".
- Teams desktop on winpc answered the emulated phone's broadcast with Trouter 504 (no ack within the timeout), twice, so pairing is verified OST <-> emulator.
- Test leftovers: the emulator's registrations were deleted from the registrar (202).
<!-- SECTION:NOTES:END -->
