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

## Still to establish

- Whether the media processor takes a client offer (as OST sends for audio) with video receive slots, or needs Teams' server-offer flow.
- The active speaker: Teams reads `dominantSpeakerInfo` from conversation updates. Its event shape hasn't been captured yet.
- How many slots Teams desktop asks for. Teams web was offered 9; the gallery shows up to 49 with pagination.
