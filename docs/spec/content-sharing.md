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
- Not built: the attendee's PowerPoint "Take control" (Teams'
  takeControlPptBtn: the attendee takes the presentation over), private
  viewing's toggle from OST's own bar (PowerPoint's own frame has it),
  PowerPoint's laser and ink sync (LiveInking proxied messages) and Cameo's
  camera frames into the slide show.
