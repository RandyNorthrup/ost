# Content-sharing sessions — Teams desktop behaviour (spec)

Microsoft Whiteboard, PowerPoint Live, Excel Live and Annotate are not
screen shares: each is a **content-sharing session** of the call's
conversation, and every participant hosts the same web page (Whiteboard,
PowerPoint for the web, Excel for the web) on the stage. Read from Teams'
bundles (calling-pluginless, 89637, r_data-client-calling, 326418,
whiteboard-renderer, annotation-app, ppt-1js-bootstrapper; 2026-11-18) and
captured live on winpc (Teams presenting Whiteboard and PowerPoint Live in a
calendar Meet now "OST TEST 208 Meet now", ost-test1 alone, camera and mic
off; network through the WebView2 debugger, DOM only). TASK-0214.

## 1. The session on the wire (shared by all four)

- **Start** (presenter): `POST <conversation links.addModality>` with
  `X-Microsoft-Skype-ContentSharing-Chain-ID: <new correlation id>` (and the
  usual calling token and headers):
  ```json
  {"participants": {"from": {id, displayName, endpointId, participantId, languageId}, "to": []},
   "contentSharing": {"identifier": "<base64 of the content's UTF-8 JSON>", "subject": "<''|file name>",
     "sessionState": null, "sequenceNumber": 1,
     "links": {"sessionUpdate": "<cb>/conversation/contentSharingUpdate/", "sessionEnd": "<cb>/conversation/contentSharingEnd/"}},
   "links": {"addModalitySuccess": "<cb>/conversation/addModalitySuccess/", "addModalityFailure": "<cb>/conversation/addModalityFailure/"}}
  ```
  The HTTP answer is ignored; the trouter callback
  `conversation/addModalitySuccess/` brings `modalitySuccess.contentSharing
  = {sessionId, contentSharingCorrelationId, identifier, presenter, subject,
  sessionState, links: {contentSharingController, takeControl,
  updateSessionState, sync, leave…}}` (failure: `modalityFailure.contentSharing`
  with code / subCode / phrase; Teams waits 65 s). Teams desktop sends this
  from its native calling stack (nothing of it shows in the page's network).
- **State** (presenter): `POST links.updateSessionState` `{operationId,
  sessionUpdateSequenceNumber: n (from 1), sessionState: "<JSON string>",
  participants: {from}}`.
- **Stop**: `DELETE links.contentSharingController` `{contentSharingTransactionEnd:
  {code: 0, subCode: 0, phrase: "CallEndReasonLocalUserInitiated"}, participants: {from}}`.
- **Viewers** find the session in the roster: the presenter's endpoint's
  `contentSharing.sessionInformation = {role: "presenter",
  contentSharingCorrelationId, contentSharingSessionId, identifier,
  contentSharingController, subject, sessionState}`; they join it (`POST
  sessionInformation.contentSharingController` `{contentSharing: {links:
  {sessionUpdate, sessionEnd}}, participants: {from}}`, answered with the
  session's links and state) and then get `conversation/contentSharingUpdate/`
  (`{contentSharingCorrelationId, sessionState, sequenceNumber…}`, older
  sequence numbers dropped) and `conversation/contentSharingEnd/`. A session
  gone from the roster has ended.
- Teams also records the share for the meeting's content list: `POST
  https://teams.microsoft.com/api/mcps/us/contents` `{threadId, callId,
  resources: [{location, type: "MeetingStage", subType: "Whiteboard" |
  "PowerPoint", metadata: {appId?, appTitle, fileTitle, imageUrl?, userId,
  shareUrl?, fileId?, fileType, baseUrl?, objectUrl?, siteId?,
  listItemUniqueId?}}], meetingUrl, messageId: "0", organizer:
  "<oid>@<tid>", iCalUid: "", instanceICalUid: ""}` (captured).

## 2. Microsoft Whiteboard (tray ▸ Microsoft Whiteboard ▸ Start Whiteboard)

Captured (presenter, 2026-11-18):
1. `GET {mt}/beta/meetings/fluidboard?threadId=…&messageId=0&organizerId=8:orgid:…&tenantId=…&meetingTitle=…`
   → `{url: "https://app.whiteboard.microsoft.com/meeting?embed=1&meetingTitle=…", shareUrl}`
   (a meeting without a board yet; the meeting's board once it has one).
2. The stage hosts the board at once: an iframe "Whiteboard"
   (`embedded-page-container`, 1029 × 541 at 5, 133 in the 1035-wide stage
   beside a 240 × 135 side tile; sandbox `allow-storage-access-by-user-activation
   allow-scripts allow-same-origin allow-top-navigation-to-custom-protocols
   allow-forms allow-popups allow-popups-to-escape-sandbox allow-pointer-lock
   allow-modals allow-downloads`) at the session's address plus Teams'
   parameters: `…meeting?embed=1&meetingTitle=…&initiatorId=<oid>
   &initiatorTimestamp=<ms>&meetingType=1&meetingTenantId=…&correlationId=…
   &culture=en-us&enableReactApp=1&isInitiator=1&isEduUser=0&meetingId=<b64
   0#chat#0>&teamsEnvV2=prod&client=TeamsModern&userRole=Member&teamsCallId=…
   &meetingTenantId=…&isMeetingRecurring=false&isEU=false&userId=…
   &userTenantId=…&isNAAEnabled=true`.
3. Teams `POST {mt}/beta/meetings/v2/whiteboard?…` `"https://app.whiteboard.microsoft.com/meeting?embed=1&openDetached=1"`
   (answered `{}`), then the session starts (content `{appId:
   95de633a-…, type: "whiteboard", conversationId, messageId, url (as in
   2), shareUrl: "", loaderLabel: "", initiatorParticipantId,
   permittedFileUsers: [], initialNoteContent: []}`).
4. Whiteboard (TeamsJS app 95de633a, frameContext meetingStage) creates the
   board in the presenter's OneDrive (`Whiteboards/<meeting title>.whiteboard`
   through SharePoint's Fluid opStream), makes an organization edit link
   (`createLink {type: edit, scope: organization}`) and posts
   `changeWhiteboardUrl [url]` (`meeting?embed=1&encodedShareLink=…
   &shareLinkId=…&canEditBoardUsingProofToken=…&fluidFileId=…`). Teams sends
   it as the session state `{url, passThrough?, initiatorParticipantId?}`
   and keeps it for the meeting (`POST …/v2/whiteboard`, the address without
   its proof token; answered `{"success": true}`; twice).
5. Viewers host the content's address with `participantTimestamp` and the
   state's board, and get `whiteboardUrlChanged [url, passThrough]` on each
   update (also after their frame's `readyForUrl`).
- The bar while presenting (setting on, 1280): …Controls | **Stop sharing**
  (`whiteboard-sharing-controls`, 62 wide) **Pop out** | More; Share stays
  "Share". Stop sharing ends the session (no confirmation); nothing else
  goes over the page's network.
- The board's own UI (Whiteboard's: title, Follow me, Open in browser,
  toolbar, Copilot) is Whiteboard's page.

## 3. PowerPoint Live (tray ▸ a recent deck, or Browse OneDrive)

Captured (presenter "OST TEST 214 deck.pptx", 2026-11-18):
1. The tray lists recent decks and workbooks from Office's MRU:
   `GET https://ocws.officeapps.live.com/ocs/v2/recent/docs?sort=date&show=12&apps=PowerPoint&exts=pptx,ppsx,ppt,pps,pot,potx,pptm,potm,ppam,ppsm,ppa,odp`
   (and `apps=Excel&exts=xlsx,xlsm,xlsb`; token api.office.net). Browse
   OneDrive opens OneDrive's FilePicker (`FilePicker.aspx?app=Teams.Chat&scenario=FilesPersonalPicker`)
   filtered to decks, its button "Attach".
2. `GET {site}/_api/v2.0/shares/u!<b64 file url>/driveItem?select=id,file,webDavUrl,sharepointIds,size,name,@microsoft.graph.downloadUrl,etag,webUrl,OpenWith,officeBundle,currentUserRole,sensitivityLabel`.
3. `POST https://usc.snap.officeapps.live.com/GetDownloadUrl.ashx`
   `{CallID, ContentId: "<siteId>_<listId>_<uniqueId>", DownloadUrl:
   "<download.aspx?UniqueId=…&tempauth=…>", CustomFontCatalogUrl: "",
   FileExtension: "pptx", FileLengthHint, ETag, DocId, MultiRangeEnabled:
   false, TailRangeEnabled: true, AuthHeaderForHostDownloadEnabled: false,
   GuaranteeLevel: 1, FileEnvironment: "USC-powerpoint.officeapps.live.com"}`
   → `{FSuccess: true, SnapUrl: "https://wus-dc.snap.officeapps.live.com/DownloadSnapUrlHandler.ashx?…"}`.
4. The stage form-posts PowerPoint's slide show into an iframe
   (`slideshowframe-pptframe-<hostSessionId>`, 1029 × 577):
   `POST https://usc.pods.officeapps.live.com/slideshow.aspx` with
   parentWindowOrigin, fileurl, fileName, fileSize, presentationUrl (the
   SnapUrl), DocID/docId, ETag, hostsessionid, ApiId, user_id, tid,
   contentId, meetingChatId, endpointId, callid, participantid,
   ispresenter=true, wdPresenterViewInTeams=true, fh=SharePoint Online,
   uih=teams, odvs=https://usc.pods.officeapps.live.com/,
   odve=podView.svc/jsonAnonymous, env=wac, powerpointview=ChromelessView…
   — PowerPoint's presenter view (slide, Notes "Visible only to you", slide
   strip, ‹ 1 of 3 ›).
5. `POST …/mcps/us/contents` subType PowerPoint, and the session (content
   type "ppt", subject the file name).
- The bar: …Controls | **Layout** (`ppt-sharing-layout-toolbar`: Content
  only, Cameo) **Stop sharing** (`stopPresentingPptBtn`) **Pop out** | More.
  Stop sharing asks "Stop presenting?" / "This will end the presentation for
  everyone. To switch presenters select Cancel so the next person can take
  control" [Cancel] [Stop presenting] (400 × 205).
- **Take control** (an attendee; Teams' PptControlsSection shows the
  viewer's `ppt-sharing-viewer-controls` ▸ `takeControlPptBtn` "Take
  control" to every meeting role but Attendee; production has
  `enableMoveTakeControlButtonToPPT` off, so it's on the bar, not in
  PowerPoint's frame): `POST links.takeControl` (the session's join answer
  link) with `{participants: {from}}`; the answer is `{identifier,
  presenter: {id}, subject, sessionState}`. Everyone (the old presenter
  too) gets `contentSharingUpdate` naming the new presenter. The frames
  switch roles in place (SetNavigationOptions 31 and SwitchRole 34: 1
  presenting, 0 viewing, 2 browsing privately); the new presenter asks
  PowerPoint where it stands (GetCurrentPosition 3) and sends that as a Nav
  state. The old presenter's bar goes back to Take control, and it gets
  Teams' warning alert PptSharingStolen: "Another user took control" /
  "{userName} is now in control of the presentation." [Take back] (Take
  back is the same request).
- **Ink and laser** (measured 2026-11-18, Teams on winpc presenting with
  PowerPoint's Drawing tools — pointer, laser, pen, highlighter, eraser):
  the frame sends `m_type 53` AnnotationEvent up (`m_annotationEventType`,
  `m_annotationEventJson`, `m_annotationStrokeID`, `m_annotationSlideID`,
  `m_metadata {ae, se}`; types: 0 stroke added, 1 erased, 2 all erased on
  the slide, 3–5 wet, 6 laser start, 7 laser move, 8 laser end, 9 laser
  removed, 12 cursor move, 13 cursor hidden). Dry ink (0–2) goes out as a
  session state `{stateId, causeId, updateType: "DryInk",
  requestingParticipantId, slideIndex, timeLineMappings,
  newDryInkEvent: {eventType, eventJson, strokeID, slideID, metadata},
  presentationUrlEvent, metadata {PresenterId, StateId, …}}` — seen as
  OST's sequence 3 and 4 after two pen strokes; the pointer (6–9, 12, 13)
  as a proxied "LiveInking" message on the conversation's message link
  (`payload.EventData` the same AnnotationData as a JSON string, scope
  "all"). Viewers hand either to their frame as `m_type 53` down
  (`m_eventType, m_slideID, m_strokeID, m_eventJson, m_metadata`).
- **Cameo** (Layout ▸ Cameo): Teams enables it only with the camera on
  ("Turn on your camera to select this layout") and a cameo in the deck
  (PowerPoint's `m_type 66` CameoDetectedInPresentation; otherwise "Add
  your video feed to this slide to use Cameo."; with a plain deck it is
  greyed, measured 2026-11-18). Picking it publishes the presenter's
  weatherPerson state `{mode: "Cameo", x, y, width, height, zOrder: 2}`
  and sends `PPTSharingLayoutChanged` (46) to the frame; attendees take
  the mode from that state. Every client composites the presenter's camera
  itself (its own camera, or the presenter's incoming video) at the slide
  view's size (`m_type 48` `m_slideViewBounds {left, top, right,
  bottom}`) and posts it into the frame: `postMessage({bufferMetadata:
  '{"sharedArrayBuffer": false, "width": W, "height": H, "format":
  "BGRA"}', arrayBuffer}, origin, [arrayBuffer])` (a 0 × 0 frame with an
  empty buffer when there's no picture).

## 4. Excel Live and Annotate (from Teams' code)

- **Excel Live** (`officeAppsMeetingConfigs` Excel 1c256a65-…, Collaboration,
  MultiStepPermission): share the workbook with the meeting's people (edit
  link to them), host Excel's Teams app page (its staticTabs[0].contentUrl
  with `{sourceOrigin}` = `Teams.<source>.MeetingStage`, `callId` and a
  `subEntityId` JSON {fileType, shareUrl, objectUrl, baseUrl, fileId, ctx,
  tenantId}) and start the session with content `{conversationId:
  "<chat>|1c256a65-…", id: 1c256a65-…, type: "extensible_app", url,
  messageId, loaderLabel, extensibleAppContext: "{permittedFileUsers…}",
  substrateFileId}`, state `{extensibleAppContext}`.
- **Annotate** (Sharing control bar ▸ Annotate, whole-screen shares): a
  session of type "annotation" (`{appId: "annotation", type: "annotation",
  conversationId, messageId, url: "", shareUrl: "", loaderLabel:
  "annotation"}`) whose board comes from `GET {mt}/beta/meetings/annotation?
  threadId&organizerId&tenantId&meetingTitle` with `annotation=true`,
  `sharedScreenWidth/Height`, `sharedScreenFullHeight`, `isScreenSharerOnT2`,
  `osType` and, for the presenter, `screenSharer=1`. The presenter hosts it
  in a transparent, always-on-top window over the shared screen kept out of
  the capture; viewers in a transparent layer over the share; the board's
  address goes out as the session state (`url + "&annotation=true"`) and is
  kept (`POST …/meetings/annotation`). The ink is Whiteboard's.

## OST status

- [x] The session protocol (`teams_cli::calling::content_sharing`,
  `OutgoingCall::start_content_sharing` / `update_content_state` /
  `stop_content_sharing` / `join_content` / `content_event`; the roster's
  `content_sessions`), with unit tests.
- [x] Whiteboard: Start Whiteboard in the tray starts the session with the
  meeting's board; the stage hosts Whiteboard (ContentStage.qml, Teams'
  frame address and parameters); the board Whiteboard reports goes out as
  the session state and is kept for the meeting; viewers host the board
  from the roster and follow its updates; the bar's Stop sharing.
- [x] PowerPoint Live (`api::live_share`, PptLiveStage.qml, ppt_host.js): the
  tray's recent decks (Office's MRU, else OneDrive's recent files) and
  Browse OneDrive; the deck redeemed in SharePoint, PowerPoint's snap
  service, the session (content type "ppt", the file name as subject); the
  stage form-posts PowerPoint's slide show as Teams' bundled bootstrapper
  does (its fields, in its order) and speaks its frame protocol (m_type 38 /
  28 / 0 handshake, trust 69 → 65, Initialize, SetNavigationOptions,
  SwitchRole, …); the presenter's OnPositionChanged goes out as Teams'
  "Nav" state and attendees GoToSlide; Layout (Content only, Cameo) and
  Stop sharing with Teams' "Stop presenting?".
- [x] PowerPoint Live's Take control (`content_sharing::take_control_body`,
  `OutgoingCall::take_content_control` / `content_presenter`): the
  viewer's Take control on the bar (PptControlsSection, not for
  Attendees) and PowerPoint's own (m_type 72); the session moves between
  "ours" and "viewed" as the updates name the presenter, the frame
  switches roles in place, and the old presenter gets "Another user took
  control" with Take back (CallAlert's title and action).
- [x] Ink and laser: the presenter's frame's AnnotationEvents go out as
  DryInk states (strokes) and LiveInking messages (pointer,
  `OutgoingCall::live_inking_sender`, sent without holding the call);
  viewers draw others' DryInk states and LiveInking messages
  (`content_sharing::live_inking`, Backend `contentInking`) with
  SetAnnotation.
- [x] Cameo: Layout ▸ Cameo as Teams enables it (camera on, a cameo in the
  deck), published as the weatherPerson state; attendees follow the
  presenter's mode; the camera's picture (ours, or the presenter's
  incoming video) reaches the frame at the slide view's size through
  `cameo_feed` (a loopback WebSocket with a secret path, BGRA) and
  ppt_host.js's VideoFrameToPptForCameo.
- [x] Excel Live (`api::live_share::excel_share`): an edit link for the
  meeting's people, Excel's meeting stage page from its app definition,
  the extensible_app session; attendees host it with isPresenter and
  shareToStageId, and getExtensibleAppContext answers the session's
  context.
- [x] Annotate (Sharing control bar, whole-screen shares): the annotation
  session and board; AnnotationOverlay.qml, a transparent overlay-layer
  window over the screen, kept out of the share (KWin's
  excludeFromCapture), with Whiteboard's click-through as an input region;
  the board goes out as the state and is kept for the meeting; viewers see
  others' annotation boards over the shared picture.
- [x] Pop out shows the session's page in its own window.
- Live checks (2026-11-18, Teams on winpc as ost-test1, OST on linuxlt):
  - PowerPoint Live, OST Test 2 presenting "OST TEST 214 deck.pptx": the
    session started (addModality 202, addModalitySuccess with its links),
    OST's stage showed PowerPoint's presenter view (slide, notes, strip);
    Teams joined it and showed the slide ("1 of 3", its own frame
    `slideshowframe-pptframe-…`, with Teams' Take control); OST's Next went
    out as a Nav state (200) and Teams followed to "2 of 3"; Stop sharing
    (DELETE 204) took Teams' stage back to people.
  - PowerPoint Live, Teams presenting the same deck: OST found it in the
    roster, joined it (200), loaded the attendee slide show and followed
    Teams' jump to slide 3 ("3 of 3"); Teams' Stop presenting ended it in
    OST.
  - Whiteboard, OST Test 2 presenting: the session started and OST's stage
    hosted the board with the bar's Stop sharing and Pop out, but
    Whiteboard showed "This whiteboard is unsaved": its nested app
    authentication needs the browser sign-in (OST Test 2 is signed in with
    a device code), so Whiteboard and Excel are checked with ost-test1.
  - Your own sessions from your other devices are viewed (Teams on another
    device presenting); only the one this device presents is left out.
  - Whiteboard, OST (ost-test1) presenting in a meeting that had a board:
    the session carried the meeting's board (its fluidboard address with
    `encodedShareLink`), Teams joined it and showed the same board; text
    Teams wrote on it ("OST TEST 214 from Teams") appeared on OST's stage
    through Whiteboard's own sync. Teams presenting: OST found and joined
    the session and hosted the board; a viewer now waits for the
    presenter's board in the state (with the session's parameters added,
    Teams' appendSearchParams) and is sent `whiteboardUrlChanged [url,
    passThrough]` after its `readyForUrl` (the pass-through carries
    Whiteboard's proof token).
  - Excel Live, OST Test 2 presenting "OST TEST 214 workbook.xlsx": the
    extensible_app session started; Teams joined it and opened the
    workbook in Excel for the web (`m365.cloud.microsoft/launch/excel/
    officeunihost/teams…`, "Welcome to Excel Live", OST Test 2's cursor in
    it). OST presenting as ost-test1 hosted Excel's page with the workbook
    (Excel's own "Resume following presenter"); the bar shows Stop sharing
    (Teams' whiteboard-sharing-controls also serve Excel Live). A Teams
    presenter of Excel Live couldn't be tried: Teams' tray lists only
    Office's recent workbooks and the test workbook had none.
  - Annotate, OST (ost-test1) sharing linuxlt's screen: the annotation
    session started, the overlay window showed Whiteboard's annotation
    toolbar (pen, highlighter, laser, eraser, shapes, "Interacting with
    background" tip) over the screen and Whiteboard created the meeting's
    annotation board (OneDrive `Whiteboards/Annotations/Annotations -
    Meeting.whiteboard`); once KWin's excludeFromCapture was set the
    toolbar disappeared from what Teams received (set after the window is
    mapped: 1.5 s and 3 s after it shows).
  - Rechecked 2026-11-18 (afternoon) with the fixes in:
    - Annotate (ost-test1 sharing linuxlt's screen): KWin reports the
      overlay `excludeFromCapture` true once mapped; the "Starting
      annotations for everyone…" card shows on linuxlt and not in the
      picture Teams receives.
    - Whiteboard, Teams presenting in "OST TEST 214 recheck" (Teams'
      template "Note pack - yellow" on the board): OST (ost-test1) showed
      that same board, and with Teams' Follow me on, "Following OST Test 1"
      with Teams' viewport ("Participants are following you" in Teams).
    - Whiteboard, OST Test 3 presenting: Teams (a different account)
      opened the meeting's board with both people on it (O1, O3), Fit to
      Screen showing the same Note pack.
    - Annotate, OST Test 3 sharing its screen: the session started and the
      overlay stayed out of the picture, but Teams showed no annotation
      layer (only Take control). Teams' sharer also publishes its
      participant property `screenSharerAttributes {source,
      annotationWindowSize {width, height, offset, fullHeight}}` when
      sharing starts (updateScreensharerPropertyBag); OST now sends it too.
    - Excel Live, Teams presenting: Teams first asks "Share with all
      participants?" (400 × 235; "Everyone invited to this meeting will be
      able to access this file. Learn more", the file's card with "People
      invited to this meeting can edit", Cancel / Share). Its session's
      content: `{appId, conversationId, extensibleAppContext:
      '{"permittedFileUsers":[],"appLoadState":"preLoadApp","fileId"}',
      initialNoteContent: [], loaderLabel: "Excel", messageId: "0",
      permittedFileUsers: [], shareUrl: "", substrateId: "SPO_" +
      base64("{siteId},{webId},{listId}") + "_" + driveItemId, type:
      "extensible_app", url}`; its state `{url: "", extensibleAppContext:
      {permittedFileUsers: [the presenter], appLoadState: "fullLoadApp",
      fileId}}`. OST Test 3 hosted Excel's page but it stayed on "Your
      colleague is preparing to share an Excel workbook": Teams sends the
      context to the app as `onExtensibleAppContextChanged` whenever it
      changes, which OST didn't. Both fixed (content, state and the
      message as Teams; the dialog before OST's own Excel Live). Rerun:
      Excel opened the workbook in OST and said "You don't have access to
      this file" — Teams' state permits only the presenter, and this Meet
      now invites nobody; a scheduled meeting with the viewer invited is
      needed to see whether Teams grants it.
    - PowerPoint Live, OST Test 3 presenting a deck with a cameo: Teams'
      Take control took it over; OST showed "Another user took control /
      OST Test 1 is now in control of the presentation. [Take back]" and
      its viewer's Take control, PowerPoint switching roles in place; Take
      back took it again and Teams went back to Take control (Teams showed
      no alert of its own then). Teams' pen stroke and laser showed in
      OST's slide (DryInk, LiveInking); OST's pen stroke showed in Teams
      (its LiveInking posts answered 202).
    - Cameo: with OST presenting, its camera on (a test feed) and Layout ▸
      Cameo, Teams showed OST's camera inside the slide's cameo (Teams'
      viewer composites the presenter's video itself). OST's own slide show
      gets the frames over the loopback feed (`cameo frames … 383x287`)
      but PowerPoint doesn't draw them there yet — open.
    - Annotate, OST Test 3 sharing with screenSharerAttributes sent: still
      no annotation layer in Teams — open.
  - With the same account on both ends Teams treats a session as its own
    (it showed Stop sharing and "This may take a few seconds..." for OST's
    Excel Live, and no annotation layer), so Teams-as-viewer checks of
    Whiteboard and Annotate need a second browser-signed-in account.
- Not built: private viewing's toggle from OST's own bar (PowerPoint's own
  frame has it, as in Teams with isMovePrivateViewingToPPTEnabled).
