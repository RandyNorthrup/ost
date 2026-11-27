---
id: TASK-0342
title: Teams desktop draws OST's Standout/Reporter camera with a black box
status: In Progress
assignee:
  - '@meet'
created_date: '2026-11-26T21:39:00Z'
updated_date: '2026-11-27T05:42:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0324's Teams desktop check (2026-11-26, winpc).

OST presenting in Standout or Reporter reaches Teams desktop. It labels the share "in presentation mode" and lays the camera out over or beside the content. But it draws OST's camera as an opaque rectangle: the cut-out background is black, not transparent.

Teams' own presenter camera arrives at OST with the implicit luma mask (OST clears its background), so OST's receive side matches.

Teams desktop must take the camera's alpha from something OST doesn't send. Two candidates:
- Teams' main-video stream carries roster metadata {negotiationTag: "<callId>;v_1"}; OST's has none.
- A frame or RTP signal from Teams' native engine.

Also seen in the same check: while OST controlled Teams' shared test window, "OST TEST" arrived as "OST TESt". The last Shift-held key came through lowercase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST's Standout and Reporter camera shows cut out, with no black box, in Teams desktop, verified live
- [x] #2 Keys OST sends while controlling a Teams share arrive with their modifiers, verified live
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture what Teams desktop's own Standout camera carries that OST's doesn't: RTP header extensions, SEI/SPS/PPS, SDP, roster metadata, published state, MCP requests. Done: identical apart from the camera's negotiation tag, now added.
2. Compare decoded pixel statistics of both cameras (in memory only). Done: same scheme.
3. Make the roster identical (capabilities, client version) as an experiment. Done: no change.
4. Next: receive Teams desktop's camera as X-H264UC with the native extmaps to find a native-only alpha signal.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Teams desktop was in a scheduled test meeting, sharing a window, with its status on Do not disturb while presenting.

- Keys (AC #2), 2026-11-26: OST controlled Teams desktop's shared test window on winpc and typed 16 Shift-held capitals (3.2 s with Shift down), a space and 4 more capitals. All arrived as typed. The bytes OST sends are the same for Qt keys and scan codes (generic Shift 0x10, then the letter's virtual key). The earlier "OST TESt" didn't reproduce. Teams' viewer forwards browser keydowns, auto-repeats included, so a held Shift isn't timed out on the sharer.
- Black box (AC #1): Teams desktop places OST's Standout camera by mode (lower right) but draws its background black. Compared with Teams desktop's own Standout camera (winpc C920; no frames kept), OST sends the same in every channel checked:
  - RTP: only transport-wide cc (extension 3) on Teams' camera; no SEI or PACSI units.
  - SPS: plain Constrained Baseline with VUI aspect ratio only (no video signal type or colour description).
  - SDP: no alpha attribute.
  - Published state: the same weatherPerson content.
  - MCP: the same send-layer requests to the presenter.
  - Roster: Teams' camera carries metadata.negotiationTag "<callId>;v_<n>". OST now tags its camera the same way (UpdateMediaDescriptions); Teams desktop still drew the black box.
  - Teams on the web's compositor never sets implicitMask (no cut-outs there). Teams desktop cuts out the presenter in native SlimCore (useAlpha for Standout/Reporter), so its alpha decision isn't in the JS bundles.
- Developer aid added: OST_VIDEO_META=1 logs each received video stream's extensions, NAL types and SEI/SPS/PPS/PACSI bytes (no picture data).
- Left open: AC #1. Next step: compare the decoded pixels themselves (background and edge luma/chroma of Teams' masked frames against OST's) with Teams' camera on a synthetic source, or trace SlimCore's native alpha path.

- Pixel comparison, 2026-11-26 evening. winpc Teams desktop (ost-test1) and OST on linuxlt, in the Meet-now test meeting "OST TEST 342". Statistics were computed in memory from decoded frames (OST_VIDEO_STATS=1, added here); no image or raw frame was written.
  - Teams desktop's own Standout camera: winpc C920, on about 1.5 min. Received at 320x180:
    - background (Y < 23): 79.9%, Y 0.1±0.8, U and V 128.0±0.2; (0,128,128) exactly is 77% of the frame;
    - person (Y ≥ 59): 18.9%, Y 59–198;
    - edge band (23–58): 1.2%;
    - all four corners (0,128,128); 90% of the border is background.
  - The same camera without Standout: an ordinary picture (background Y 10±5, no exact key value).
  - OST's Standout camera (synthetic test camera): background 72%, Y 0.0±0.2, U and V 128.0±0.5; (0,128,128) exactly is 68%; person Y 59–226; edge band 0.1%; corners (0,128,128). The same scheme.
  - Neither stream has an alpha or matte plane, SEI, PACSI, colour description or full-range flag. Both are 4:2:0 Constrained Baseline at the same sizes. Teams' SPS VUI adds only aspect ratio 1:1; constraint flags 0x40 vs OST's 0xC0.
- Signalling made identical (experiment only, reverted afterwards):
  - Teams desktop's roster entry has endpointCapabilities 587 (OST 579: bit 8) and clientEndpointCapabilities 15611602 (OST 9320130: supportsParticipantMapping 16, supportsImmersiveModeV2, supportsPreheatInStreamingMode).
  - Its clientVersion is "CallSignalingAgent (49/26304.…)".
  - With OST sending the same bits and the same client version, its roster entry matched Teams desktop's (587, 15611602, CallSignalingAgent), and the negotiation tags already matched. Teams desktop still drew OST's Standout camera as a black rectangle.
  - Neither field enables the cut-out, so OST keeps advertising only what it implements.
- Conclusion: the wire format, pixels, published state, roster and media descriptions are all identical, and Teams desktop still doesn't cut OST's camera out. Its cut-out is decided natively (SlimCore's compositor, useAlpha for Standout/Reporter), from something OST can't see.
  - The likeliest place is the native video path between Teams desktop endpoints and the media processor. Native Teams offers X-H264UC (MS-H264PF, PACSI/SEI) and its own header extensions (frame-counters, fast_bandwidth_feedback, video-orientation, framemarking). OST negotiates plain H.264 with transport-wide cc only, so the processor forwards Teams' camera to OST without any native-only metadata, and OST has never seen it.
  - Not reproducible from what OST receives today.
- Proposed workaround and next steps:
  1. Keep the current Standout/Reporter output. It is exactly Teams' own scheme, so OST viewers cut it out, and Teams desktop at least places the camera correctly by mode (the black rectangle is the only flaw).
  2. To find the native signal: offer X-H264UC and the native extmaps as a receiver on the camera slots, receive Teams desktop's Standout camera that way, and compare its PACSI/SEI and extensions between Standout and normal. Then send whatever differs.
  3. Optional cosmetic mitigation until then: crop OST's outgoing presenter frame to the person's box, so Teams desktop's rectangle is mostly person, not black. This changes the camera's aspect for every viewer, so only with the user's OK.

- Native X-H264UC receive (step 2), 2026-11-26 night, winpc Teams desktop (ost-test1) in the Meet-now test meeting with OST Test 3 on linuxlt.
  - The media processor's own offers list x-h264uc (pt 122) and H265v2 (114) before H.264 (107), with its fast_bandwidth_feedback extension (id 3). Clients' offers are answered H.264 only.
  - OST_VIDEO_NATIVE=1 (developer switch, off by default) offers X-H264UC (`packetization-mode=1;mst-mode=NI-TC`) first on the receive slots. The processor still answered every slot `107` only, including with Teams desktop's client version (tried, then reverted).
  - The processor's own offers come when it moves a call: here, after a lobby admission.
    - To get one, the meeting was set to let only organizers bypass the lobby (value before: "People in my org and guests"; restored and checked afterwards).
    - OST answered the move with `122 107` on every slot.
    - Teams desktop's camera (C920 on about 47 s; metadata only, nothing saved) still reached OST as H.264 pt 107, and not one pt 122 packet arrived.
    - So the processor forwards Teams' camera natively only to native endpoints and never sends X-H264UC to OST, however OST negotiates.
  - The depacketizer now keeps only the base layer of an X-H264UC stream (drops SVC prefix 14 and extension slices 20, as it did PACSI 30), so that path decodes if a processor ever sends it.
- Conclusion: whatever lets Teams desktop cut out a presenter's camera travels only on the native path between Teams desktop clients and the processor (X-H264UC/H265 with their own metadata). That path isn't open to OST's WebRTC-style endpoint, so OST can't observe it or send it. Everything OST can see is already identical to Teams desktop's own Standout camera.
- Recommendation: keep OST's Standout/Reporter output as it is (Teams' exact scheme: OST viewers cut it out; Teams desktop draws it in place with a black background). Leave AC #1 open as a Teams-side limitation unless a native capture becomes possible (only by decoding Teams desktop's own native media, which OST can't).
- Also found: joining by meeting ID fails while the lobby holds you. Filed separately.

- Wire capture, Teams desktop to Teams desktop, 2026-11-27 05:26–05:35 UTC. winpc Teams (ost-test1, C920, muted) organized a Meet-now "OST TEST 342 capture" and presented a Notepad test window. testpc2 Teams (OST Test 2, no camera) viewed it. Windows pktmon ran on both NICs. Phases (UTC): camera on 05:28:27; Standout share 05:29:57; Reporter 05:32:19; Side-by-side 05:33:17 (added as a no-alpha control); share stopped 05:34:05; camera off 05:34:42. Layout state was read through UIA. Only headers and sizes were analyzed (tshark plus a script). The pcaps were deleted afterwards and no frames were kept.
  - Media: everything is UDP to the media processor (one IP): port 3479 audio, 3480 camera, 3481 screen and data. Client-to-processor packets are wrapped in a 12-byte `ff10 <len> <8-byte id>` header; processor-to-client packets are plain RTP. Payloads are SRTP (first-byte entropy 7.99 bits). SRTCP is encrypted too (E flag set), so VSR and other RTCP contents can't be read.
  - Native camera format: PT 122 (X-H264UC) and PT 123 (FEC, the frame's last packets on the main stream). There are two simulcast streams, here sender SSRCs 0x198b (main, about 950 kbps, 22 packets per frame) and 0x198c (about 230 kbps). The processor forwards them unchanged to the native viewer: same packet counts, each packet 4 bytes longer for an added CSRC (0xca); only the SSRC is rewritten into the viewer's slot range (0x59da/0x59db).
  - Header extensions: the camera carries only one-byte (0xBEDE) id 1, 3 bytes, which is abs-send-time (it tracks wall time in 6.18 fixed point). It's the same set in every phase. The screen stream carries ids 1 and 6 (3 bytes). There's no RFC 6904 encryption; the values are in the clear. Standout and Reporter add no extension, PT or stream that normal or Side-by-side lack, and RTCP types and sizes don't change by mode (VSR stays 120 bytes on 3480, 188 on 3481). Mode switches send no data-channel packets (PT 127 appears only at share setup).
  - The one difference: the first packet of each frame on the main stream is the PACSI/SEI packet. It's 73 bytes (77 at the viewer) in normal and Side-by-side, every frame. In Standout and Reporter, 40–70% of frames start with a 102-byte packet instead (106 at the viewer). The keyframe variant grows the same way (136 to 165). Counts: normal 0 of 613 frames, Standout 466 of 1005, Reporter 183 of 407, Side-by-side 2 of 331 (at the switch). The 102-byte frames come in runs, so they're content-driven, and they appear within one frame of the Standout/Reporter switch and stop at the Side-by-side switch. So in exactly Teams' useAlpha modes, the sender adds 29 bytes of in-band metadata to the frame's PACSI, and the processor forwards it.
  - 29 bytes is exactly one MS-H264PF Cropping Info SEI message with one window (§2.2.6): payloadType 5, payloadSize 27 (18 + 9×1), UUID BB7FC1A0-6986-4052-90F0-0929217539CF, numOfCropData 1, crop_info_type 0, confidence, then left/right/top/bottom offsets (2 bytes each). The spec describes these as "regions of interest … decided by a face tracker", used by the receiver to crop. The content is encrypted, so this identification rests on size and timing only.
  - Reporter also moves the camera to two new sender SSRCs (0x198d/0x198e, a new encoder configuration, likely for its crop). Standout keeps the original ones.
- What OST could send: OST's camera is plain H.264 (PT 107) and carries no SEI or PACSI. Teams desktop's alpha decision may be keyed on (or use) this per-frame crop info, which OST never sends.
- Proposal (next experiment):
  1. In Standout and Reporter only, have OST's camera encoder emit an SEI NAL (type 6) in each access unit, before the first slice. It carries one user_data_unregistered message in Teams' Cropping Info layout: the UUID above, then 1, 0, confidence 100, and the left/right/top/bottom offsets of the person's bounding box taken from OST's segmentation mask. Optionally also send Teams' per-frame Bitstream Info SEI (05FBC6B9-5A80-40E5-A22A-AB4020267E26, ref_frm_cnt and num_of_nal_unit).
  2. Verify with the same rig: OST presents in Standout while testpc2 Teams views, with pktmon on testpc2. If the frame-leading packets grow by the SEI's size, the processor forwards OST's SEI; if Teams desktop then cuts OST out, AC #1 is met.
  3. If the processor strips SEI from H.264 senders, the remaining route is sending X-H264UC with a PACSI that carries the same SEI. The processor has only ever answered OST with 107, so that likely needs the native send negotiation.
<!-- SECTION:NOTES:END -->
