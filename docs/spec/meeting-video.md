# Meeting video: how Teams receives video in meetings and group calls

Research for TASK-0047, from three sources:

- **Teams web's live SDP.** An anonymous guest (Chrome on linuxlt) joined the test meeting, and the offer/answer were read from `chrome://webrtc-internals`.
- **The calling code.** The `calling-pluginless` bundle (Teams' browser media stack), plus the roster and UI bundles.
- **OST's own roster logs** from the same meeting.

## Media lines (server offer to Teams web, 14 m-sections, one BUNDLE)

| mid | kind | direction (server offer → guest answer) | notes |
|---|---|---|---|
| 1 | audio | sendrecv → sendrecv | OPUS 102/RED, G722, PCMU, PCMA; msid `mainAudio-<ssrc>` |
| 2 | video | sendrecv → sendrecv | the guest's camera (`main-video`); the answer sends 3 simulcast layers (`a=rid:1..3 send`, `a=simulcast:send 1;2;3`) |
| 5–9 | video | sendrecv → sendrecv | receive slots that also carry the client's extra send streams |
| 10–13 | video | sendonly → recvonly | receive-only slots |
| 3 | video | sendrecv → sendrecv | screen sharing: H.264 107 and AV1 116 with RTX; msid `applicationsharingVideo-<ssrc>` |
| 4 | application | sendrecv | SCTP data channel, port 5000 (Teams' media control plane) |

- Every video slot offers H.264 107 (`packetization-mode=1;profile-level-id=42C02A`) with RTX 99.
- Each slot has its own `a=ssrc-group:FID` pair and msid `mainVideo-<ssrc>`, e.g. mid 5 is `mainVideo-45911` (45911 / 45961).
- The header extensions are abs-send-time, transport-cc, sdes:mid, rtp-stream-id, repaired-rtp-stream-id and video-layers-allocation00. `b=AS:3920`.

## Who sends video: the roster

Each endpoint in a `conversation/rosterUpdate/` lists its `call.mediaStreams`:

```json
{"direction":"sendrecv","label":"main-audio","sourceId":201,"type":"audio","serverMuted":false}
{"direction":"recvonly","label":"main-video","sourceId":202,"type":"video","mdRequestId":1}
{"direction":"recvonly","label":"applicationsharing-video","sourceId":212,"type":"applicationsharing-video"}
{"direction":"sendrecv","label":"data","sourceId":213,"type":"data"}
```

A participant whose camera is on has a `main-video` stream that sends (`sendrecv`/`sendonly`). Its `sourceId` is what a receive slot gets subscribed to. A roster delta only carries what changed, so the full set comes from the first updates after joining.

## Subscribing a slot: source requests

The media processor sends nothing on a receive slot until the client asks for a source. In `calling-pluginless`, `requestSource` → `mediaMessageController.sendSourceRequest(streamMsid, sourceId, mid, fmtParams, subStreamIndex)`.

With `useApplyChannelParametersForSourceRequests`, the request goes over signalling to the call's `applyChannelParameters` link (it arrives in the call acceptance links). This means no data channel is needed:

```json
{"applyChannelParameters":{"multiChannelParameter":{
  "mids":["<slot mid>"],
  "mediaParameter":"{\"controlVideoStreaming\":{\"sequenceNumber\":<n>,\"controlInfo\":{\"sourceId\":<roster sourceId>,\"streamMsid\":\"<slot msid, e.g. mainVideo-45911>\",\"fmtParams\":[\"<capabilities>\"],\"subStreamIndex\":<i>}}}"}}}
```

- `fmtParams` entries are `;`-joined `key=value` capability strings. The keys come from Teams' `VIDEO_CAPABILITIES`: `max-fs`, `max-mbps`, `max-fps`, `max-br`, `max-width`, `max-height`, `ssrc`, `rid`.
- `sequenceNumber` increases with every message.
- Without that flag, the same `controlVideoStreaming` goes over the data channel as `{type:"sr", …}`.

The client also states what its own camera can send, per mid, with `maxVideoSendCapabilities` (`max-width`, `max-height`, `max-fps` and so on) on the same link.

## Screen sharing

Screen sharing has its own line (mid 3, `applicationsharingVideo-<ssrc>`). The presenter's `applicationsharing-video` stream turns to sending in the roster. OST already receives this line in 1:1 calls.

## What a client offer gets (OST, 2026-11-07)

OST's own offer (audio, a recvonly `main-video` line and an inactive `applicationsharing-video` line, RTP/SAVP with DTLS, as Teams desktop's offers look) is accepted by the meeting's media processor. It answers in Skype's model, not the per-slot WebRTC one:

- `main-video` comes back `sendonly` with one SSRC range for everything it may send, e.g. `a=x-ssrc-range:68418-68517`, H.264 107 `42C01E`, and `a=x-signaling-fb:* x-message app send:src,csrc,vc recv:src`.
- About 8 s later it re-offers with its full codec list and an `m=x-data` line (mid 4, `a=rtcp-fb:* x-message app`, `x-bwealgorithm:rmestimator bwc packetpair webrtc`).
- The acceptance links include `controlVideoStreaming` and `applyChannelParameters`.
- Its RTCP names the first SSRC of the main-video range as a sender (SR) with 0 packets, and carries Microsoft's profile extensions (TURN bandwidth `0x0008`, peer info `0x000C`, modality send limit `0x000E`).

Source requests tried, all for the guests' roster `main-video` sourceIds; none made it send video:

| Route | Body | Result |
|---|---|---|
| `controlVideoStreaming` link | `{controlVideoStreaming:{sequenceNumber, globalTimeStamp, controlInfo:[{control:"start", sourceId, streamMsid, fmtParams}]}}` (Teams' `getVideoControlMessage`) | 400 while `streamMsid` isn't an integer ("Could not convert string to integer"); 202 with an SSRC from the MP's range, our range, or the line's `x-source-streamid`; no RTP |
| `applyChannelParameters` link | `{applyChannelParameters:{multiChannelParameter:{mids:["1"], mediaParameter:"{controlVideoStreaming:{…, controlInfo:{sourceId, streamMsid, fmtParams:[…], subStreamIndex}}}"}}}` | 202, no RTP |
| RTCP | MS-RTP Video Source Request (PSFB FMT 15, AFB type 1, MSI = sourceId, one H.264 entry up to 1280×720), with RR and REMB every second, `goog-remb` offered | no RTP |

Teams desktop (winpc, in the same meeting) makes no HTTP or WebSocket request when a guest's camera comes back on, so its source requests travel inside its native media stack: most likely the `x-data` line, which OST declines. The guest browsers (Teams web) get video through the server-offer flow above.

Next: accept the `x-data` line and find the message format on it, or move meetings to the server-offer flow Teams web uses (join with no SDP, answer the media processor's offer, subscribe slots on `applyChannelParameters`).

## The media control plane (MCP): how Teams actually subscribes video

Captured from Teams web (a guest's page, its own data channel hooked) leaving and rejoining the test meeting, 2026-11-07. Teams desktop sends nothing over HTTP either, so it uses the same channel.

**The offer.** Teams' client offer (`mediaContent.contentType: application/sdp-ngc-1.0`, RTP/SAVP dialect) has, bundled:

- mid 0 audio;
- mid 1 `main-video` sendrecv (its camera; `x-ssrc-range` of 100 for simulcast);
- mids 2–6 `main-video` sendrecv and mids 7–10 `main-video` recvonly (receive slots; recvonly ones carry `a=x-ssrc-range:1-1`);
- mid 11 `applicationsharing-video`;
- mid 12 `m=x-data … RTP/SAVP 127 126` with `a=x-data-protocol:sctp`, `a=sctp-port:5000`, `a=max-message-size:262144`.

Every video line carries `a=x-signaling-fb:* x-message app send:src recv:src,vc`, `goog-remb`, `transport-cc`, `nack`, `nack pli` and `ccm fir`. The join body also lists `mediaContent.mediaDescriptions` ({mid, direction, label} per line) and `applyChannelParameters.multiChannelParameter.mediaParameter` `{"sendSideBWSeed":{"seedValueBitsPerSec":1500000}}`.

**The answer and slots.** Each answered video line has its own `a=x-source-streamid` (e.g. 7761) and SSRC range with an FID pair (e.g. `117238 117288`). The data line's `x-source-streamid` is the client's MCP id.

**The channel.** After DTLS, the client opens an SCTP data channel labelled `main-channel` (default reliable, ordered). Every message on it is a packet in Teams' packetizer format (calling-pluginless; `src/calling/datapacket.rs`): an 11-byte header, 4 bytes per recipient, then the payload.

| bytes | value |
|---|---|
| 0 | `0x10` (version 1) with the header length's high 4 bits |
| 1 | the header length's low 8 bits (11 + 4 × recipients) |
| 2 | `0x80` on a message's first packet, with the data id (6 bits) |
| 3–4 | the sender's packet sequence for that data id, big-endian, from 0 |
| 5 | how many more packets the message takes (0: whole) |
| 6–9 | the sender's data source id (u32) |
| 10 | how many recipients follow (0: everyone), 4 bytes each |

A message split into several packets carries its source and recipients in the first; the rest follow in sequence and are joined.

Data ids: 18 the media control plane (MCP, below), 3 speech recognition (the transcript and live captions; JSON), 24 real-time text (`{"s": …}` as UTF-8; see call-and-meeting-window.md §1.8f).

An MCP payload is a version byte `0x01`, then a JSON array of one message, to the MP alone: `10 0f 92 <seq> 00 <our id> 01 ff ff ff fc 01 [...]`. The MP's id is `0xfffffffc`. The client is `0xfffffffe` until the `ack`, which names it as its recipient; that is the client's data source id from then on (other data ids are sent from it too).

**Messages** (client → MP unless marked):

```json
{"type":"syn","client_capabilities":["dsh","bwe","sr","ssbwe","leave","vdclc","heartbeat"]}
← {"type":"ack","receive_capabilities":["sr","ssbwe","leave","heartbeat"],"send_capabilities":["bwe","dsh","sr_res","heartbeat","vdclc"]}
{"type":"heartbeat","state":0}                      (both ways, every second)
← {"type":"bwe","bw":1500000,"video_bw":1271458}   (downlink estimate)
{"type":"sr","controlVideoStreaming":{"sequenceNumber":43,"controlInfo":{"sourceId":2244,"streamMsid":7761,
   "fmtParams":[{"max-fs":8160,"max-mbps":244800,"max-fps":3000,"profile-level-id":"64001f"}]}}}
← {"type":"sr_res","result":"ok","sequenceNumber":43}
← {"type":"vdclc","sourceId":7761,"fmtParamsList":["KeyFrame=1;max-br=586;max-fps=3000.000000;max-fs=920;max-mbps=27600;rid=1;sequence-number=0;ssrc=…", …]}
   (what to send of our own camera, per simulcast layer)
{"type":"ssbwe","BwMessage":[{"streamMsid":7761,"bw":750000}]}
```

- `sourceId` is the sender's roster `main-video` `sourceId`.
- `streamMsid` is the receive slot's `x-source-streamid`.
- `max-fps` is in hundredths.
- `dsh` (dominant speaker history) is announced as an MP send capability.
- The guest also posts `maxVideoSendCapabilities` per sending mid to `applyChannelParameters` (via the `cc/v1/mcProxy` link): `{"applyChannelParameters":{"multiChannelParameter":{"mids":["1"],"mediaParameter":"{\"maxVideoSendCapabilities\":{\"caps\":{\"max-width\":1280,\"max-height\":1280,\"max-fps\":30,\"max-streams\":3,\"max-layers\":3,\"sequence-number\":24}}}"}}}`.

The MP re-offers after lobby admission (`call/mediaRenegotiation`); the client answers on the `negotiations` link, and a new MCP session (new `syn`) starts on the new data channel.

## OST's implementation (2026-11-07, verified live)

- **Offer.** OST offers audio, the camera line (mid 1, sendrecv), nine `main-video` recvonly receive slots (mids 2–10, `x-ssrc-range:1-1`), sharing (mid 11, sendrecv) and the `x-data` SCTP line (mid 12), in Teams' RTP/SAVP dialect.
- **No `mediaDescriptions` or `sendSideBWSeed`.** OST's SDP states every direction as meant. With either field the processor ends the join with 410, subCode 300400.
- **SCTP.** The processor opens an association from its side too (both ends send INIT), so OST accepts the peer's association as well as its own and uses the first that comes up. `main-channel` is stream 0, opened with DCEP. The MCP id in `ack` equals the answer's data-line `x-source-streamid`.
- **Rosters.** The first roster update after joining names people without their streams. OST seeds the roster from the join response's `roster`, and later updates that carry no endpoints keep the stream fields.
- **Receiving.** Each slot's video arrives on the first SSRC of its answered range (its RTX on the second), so OST routes packets by range plus payload type.
- **Verified.** Both guests' cameras showed in OST's tiles in the test meeting, with `sr_res ok` for each request.

Code: `src/calling/datachannel.rs` (SCTP and DCEP), `src/calling/mcp.rs` (framing and messages), `src/calling/meeting_media.rs` (slots, subscriptions), `webrtc_audio::offer_sdp_meeting`.

## Quality and the gallery (2026-11-07, verified live)

- **Bandwidth feedback.** Teams negotiates transport-wide congestion control on every line: `a=extmap:3 http:\\www.ietf.org\id\draft-holmer-rmcat-transport-wide-cc-extensions-01` (Teams' backslash URI) and `a=rtcp-fb:* transport-cc`. Without feedback, the processor sent OST only the lowest simulcast layer (284×160 or 320×180). OST now reports arrivals every 50 ms (`src/calling/twcc.rs`). The processor's `bwe` then rose to 1.75 Mbps, and the 960×540 layer arrived.
- **Source requests.** These use Teams' capabilities: `max-fs` 8160, `max-mbps` 244800, `max-fps` 3000.
- **Dominant speaker.** This needs `a=x-signaling-fb:* x-message app recv:dsh` on the audio line; MCP then sends `{"type":"dsh","history":[<audio sourceId>…]}`.
- **Gallery** (measured on winpc, 3 people in a 900.7×576 stage):
  - 16:9 tiles (450.3×253.3), using the column count that gives the largest tiles.
  - Rows are centred, the last one too. You are the first tile ("myself-video").
  - The stage is inset 2.67. The tile content is inset 2: radius 6, #F5F5F5, a 0.67 px rgba(0,0,0,.1) border.
  - Name tag: 24 tall, rgba(0,0,0,.5), radius 4, 6 px padding, 14 px white, 8 px from the bottom-left.
  - Speaking ("voice-level-stream-outline"): 4 px #5B5FC7, radius 6, with a 0.67 px #F5F5F5 line 4 px in (radius 3).
  - Avatar: 124 px at a 249 px tile height.
- **Gallery pages** (measured on winpc 2026-11-08: gallery size 4, five people, a 1260.66×576 stage):
  - The gallery shows the gallery size's worth of people per page. The tiles fill `only-videos-wrapper` (1260.66×540), laid out by the same fitting. The last page holds the rest; one person alone gets one large tile.
  - Under the tiles, a 34 px row (`calling-pagination`), 2 px above the stage's bottom: centred `‹ n/m ›`.
    - The buttons (`calling-pagination-prev-button` / `-next-button`) are 32×32, radius 4, padding 5, 2 px below the row's top. Each has a 20 px Fluent chevron (left/right, regular; it stays regular on hover).
    - Colours: #242424 when there's a page that way, #BDBDBD (disabled) when not. Hover background #F5F5F5.
    - Tooltips "Previous page" / "Next page". Accessible names: "Navigate to previous video page. Currently n/m" and "Navigate to next video page. Currently n/m".
    - The counter (`calling-pagination-counter`) is 14 px regular #252423, 20 tall, between the buttons with no gap.
  - OST asks for video only for the people on the shown page (its tiles' widths drive the source requests).

## Sending: camera and screen (2026-11-08, verified live)

- **Lines.** Teams offers its camera and sharing lines `sendrecv` from the start. It switches them with `UpdateMediaDescriptions` on the acceptance's `updateMediaDescriptions` link, never with a re-offer. A line described as sending must be `sendrecv` in the SDP; a `sendonly` share line from a re-offer gets 400, operationFailure 1047 "Invalid MediaDescriptions", and the processor ends the call (410 InvalidUpdatedMediaDescriptions).
- **Descriptions** (captured from Teams web): every video line Teams sends on, each time.
  - Camera on: `{"mid":<camera>,"direction":"sendrecv","label":"main-video"}`; off: `{"mid":<camera>,"direction":"recvonly"}`.
  - Sharing: `{"mid":<share>,"direction":"sendonly","label":"applicationsharing-video"}` with `"negotiationTag":"<callId>;ss_<n>"` beside `descriptions`; stopped: `{"mid":<share>,"direction":"recvonly"}`.
  - `n` counts the shares in the call (1, 2, …). `callId` is the meeting call's id, the same for everyone in it.
- **The call's id.** Joining a call that's going on, Teams uses that call's id as its `x-microsoft-skype-chain-id`. The id is the `conversationId` of the chat thread's `awareness_conversationLiveState:*` entry. A new call gets a new id. The processor's events carry it as `correlationId`.
- **Watching our screen.** When someone starts watching, the processor sends `call/controlVideoStreaming/` (not MCP): `{"controlVideoStreaming":{"controlInfo":[{"control":0,"fmtParams":"max-fs=8160;max-fps=1500;profile-level-id=42C02A;packetization-mode=1;max-br=1003;max-mbps=135000","sourceId":<our share stream>}],…}}`. Teams' media stack applies it; OST caps the encoder to it and sends a keyframe. The camera's requests come as MCP `vdclc`.
- **Payload types.** The processor's answer writes `profile-level-id=42C01E` (Constrained Baseline as `42C0…`) and payload type 107 on both lines. OST sends with that type; it receives the share with its own offered 102.
- **Verified.** A guest on Teams web saw OST's camera (on, then off) and OST's shared window (shown, then back to the gallery on stop).

## Who is speaking (2026-11-08, verified live)

- Teams' voice-level outline: a participant's `voiceLevel` is 1 while their roster audio `sourceId` is among the contributing sources (RTP CSRCs) of the mixed audio the processor sends, else 0 (`onContributingSourcesChanged` → `updateVoiceLevel`). The tile outline shows when it's above 0. `dsh` (dominant speaker history) drives Speaker view instead.
- Your own tile gets no outline in Teams web's meeting stage.
- Measured on Teams web: the outline goes off about 60 ms after the speaker's CSRCs stop arriving (180–220 ms after they mute). Gaps of up to about 120 ms in the CSRCs don't turn it off.
- OST: `src/calling/active_speakers.rs` keeps each CSRC for 150 ms after its last packet and reports the set as it changes (event `ost/activeSpeakers/`). The backend maps the sources to people through the roster (`callSpeakingJson`).

## Mute state (2026-11-08, verified live)

- **Others' mute** (calling-pluginless): someone is unmuted when one of their endpoints has a first audio stream that isn't `serverMuted` and an `endpointState.state.isMuted` that isn't true. Otherwise they're muted. Roster updates carry each endpoint's `endpointState` (`{"endpointStateSequenceNumber":n,"state":{"isMuted":b}}`).
- **Our mute, as others see it:**
  - Muting, or unmuting yourself, posts `{"from":{…},"endpointState":{"state":{"isMuted":b},"endpointStateSequenceNumber":n}}` to the conversation's `updateEndpointState` link (200).
  - When the meeting has muted our endpoint (our audio stream `serverMuted`), Teams mutes locally. Unmuting first posts `{"from":{…},"mediaTypes":["audio"]}` to the conversation's `unmute` link (202). Once the roster shows the server mute lifted, the mic opens and the endpoint state says unmuted.
- **Verified:**
  - A Teams web guest saw OST's tag switch between mic-off and mic (with the speaking outline) as OST unmuted and muted, including lifting a server mute left from Mute all.
  - OST's tiles showed Guest 1's own mute and unmute.

- **"You've been muted"** (alert MicMutedRemotely, measured on Teams web, styled by Fluent tokens):
  - Teams shows it when the meeting mutes you while you're unmuted (`micMutedRemotely`: not muted, not streaming, not audio-restricted).
  - It closes after 30 s (`CL = 3e4`), when you dismiss it, or once you're unmuted. Unmute in it toggles the mic, as the Mic button does.
  - Look, in the same notice family as RoomNotice on winpc:
    - 320 wide, NeutralBackground2, a NeutralStroke3 edge, radius 8.
    - The filled mic-off glyph (20) and a 12 px NeutralForeground1 title; dismiss (16, NeutralForeground3).
    - "You have been muted." in 14/20 NeutralForeground3.
    - A full-width primary "Unmute" button (32 tall, radius 4, 14/600).

## Still to establish

- Whether the media processor takes a client offer (as OST sends for audio) with video receive slots, or needs Teams' server-offer flow.
- The active speaker: Teams reads `dominantSpeakerInfo` from conversation updates. Its event shape hasn't been captured yet.
- How many slots Teams desktop asks for. Teams web was offered 9; the gallery shows up to 49 with pagination.
