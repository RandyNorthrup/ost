---
id: TASK-0162
title: 'Better Together: pair with a Teams phone (Settings ▸ Devices ▸ Manage devices)'
status: Done
assignee: []
created_date: '2026-11-15T20:59:00Z'
updated_date: '2026-11-21T15:20:00Z'
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
- [x] #1 A paired Teams phone shows on Manage devices with Teams' name, status and Disconnect
- [x] #2 Disconnect unpairs it as Teams does
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

2026-11-21 verified live on linuxlt (spatest = ost-test1; btvirt pair: OST scans hci1, the emulated phone advertises on hci2; OST_BT_ASSUMED_RSSI -40):
- The emulated phone (examples/teams_phone.rs: own Trouter socket, calling registration with the BetterTogether transport, beacon 34 F0 40 via bluetoothctl) found OST at the registrar, sent broadcast: OST heard the beacon, learned salt 5664 and answered deviceName Linux. pair: OST showed "Connection request / OST TEST 162 Phone would like to pair with your PC." (bt-pair.png), Connect -> response accepted:true; Manage devices listed "OST TEST 162 Phone" / Connected / Disconnect (bt-paired.png).
- Disconnect: OST sent unpair {companionResponseRequired:false, salt, targetEndpointId}, the phone acknowledged 200 and answered; the list emptied (bt-unpaired.png). (AC #1, #2)
- Keep-alives every 30 s (proximity scan, keepalive with companionResponseRequired:true, the phone's response); the 50 s prompt timeout answered accepted:false RejectedByTimeout.
- Found: after an OST restart the stored phone showed paired-not-connected, but the phone refused OST's keepalive (300 DEVICE_NOT_PAIRED) because OST's calling endpoint id was new; fixed by keeping it (profile file calling-endpoint-id; OST_CALLING_ENDPOINT_ID for a second client of the profile). btvirt reports RSSI 127 (HCI "not available"), now read as missing.
- Cleanup: OST and phone stopped by pid, btvirt down, the test registrations deleted from the registrar (202).

- 2026-11-21 merged (ed054b1, 97cc7a9, 7206139); 871 lib + 29 desktop tests pass on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Better Together as Teams: pair OST with a Teams phone.

- OST registers Better Together as Teams does, as a second transport (context BetterTogether) on its calling registration, and keeps its calling endpoint id across restarts so a paired phone keeps talking to it.
- Pairing: the phone's beacon and broadcast reach OST, which answers with its device name; the phone's pair request shows Teams' "Connection request" prompt (50 s timeout answered RejectedByTimeout); keep-alives every 30 s.
- Settings ▸ Devices ▸ Manage devices lists the phone with Teams' name, Connected status and Disconnect; Disconnect sends Teams' unpair and the phone is unpaired.

Verified live on linuxlt with an emulated Teams phone (examples/teams_phone: own Trouter socket, calling registration with the BetterTogether transport, beacon over a btvirt pair); test registrations deleted. No real Teams phone in the test setup (no hardware bought).
<!-- SECTION:FINAL_SUMMARY:END -->
