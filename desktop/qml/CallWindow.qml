import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import com.ost.desktop

// A 1:1 call, laid out as the Teams call screen (light theme, measured
// from the Teams client at 1x): a 60 px meeting bar with the timer on the
// left and icon-over-label controls on the right, then the stage with the
// other person's avatar, their name chip and your own tile.
Window {
    id: win
    // Teams' "Always use dark theme for calls and meetings" (Settings ▸
    // Appearance): this window's own theme, dark then even in Light.
    Theme {
        id: theme
        dark: window.appTheme.dark || window.callsDark
        classic: window.appTheme.classic
        highContrast: window.appTheme.highContrast
        hoverCard: window.appTheme.hoverCard
    }
    property string peer
    property string selfName
    property string state       // "calling" | "connecting" | "connected" | "ended"
    /// Removed from the meeting: Teams' retry screen fills the window.
    property string retryReason: ""
    signal rejoin()
    property bool muted
    property bool hasAudio: true
    property real connectedAt: 0
    // The next "connected" is the same call carried on (a transfer, merge
    // or park retrieve replaced it without closing the window), so the
    // clock keeps running instead of restarting.
    property bool callContinues: false
    /// Teams' voicemail greeting call (Settings ▸ Calls ▸ Record a
    /// greeting): no Chat or People, no hold, transfer or park.
    property bool voicemail: false
    signal leave()
    signal toggleMute()
    /// Video: whether the call can carry ours, and whether the camera is on.
    property bool canVideo: false
    property bool cameraOn: false
    signal toggleCamera()
    /// Sharing your screen: possible in this call, and on.
    property bool canShare: false
    property bool sharing: false
    signal toggleShare()
    /// Presenting (TASK-0210): our presenter mode, Add background,
    /// Optimize and give / take control (the backend's
    /// call_presenting_json: {mode, background, optimize, control: {capable,
    /// deniedBySharer, state, controller, request, controllable}}).
    property var presentingState: ({ mode: "ContentOnly", control: {} })
    readonly property var controlState: presentingState.control || ({})
    signal setPresenterMode(string mode)
    signal setPresenterBackground(string json)
    signal setShareOptimize(bool on)
    signal screenControl(string action, string arg)
    /// What we share ("screen" or "window"): the Sharing control bar's
    /// badge and its Give control menu.
    property string shareKind: "window"
    /// Teams: sharing minimizes the meeting window (its compact view
    /// shows) and the Sharing control bar opens; stopping brings the
    /// window back.
    onSharingChanged: {
        // The shared screen's size (Teams' screen sharer attributes, Annotate's board).
        if (sharing) backend.setShareScreen(Screen.width, Screen.height, Screen.desktopAvailableHeight, Screen.devicePixelRatio)
        // Stopping the screen share stops Annotate (Teams' stopAnnotationFromSharer).
        if (!sharing && annotating) backend.contentShareStop()
        if (sharing && meeting) showMinimized()
        else if (!sharing && visibility === Window.Minimized) { showNormal(); raise() }
        // Teams refreshes Call health at once when your media turns on or off.
        if (side === "callHealth") refreshCallHealth()
    }
    /// The Sharing control bar's More ▸ Chat / People: the pane in the
    /// meeting window, shown again.
    function showSidePane(name) {
        if (visibility === Window.Minimized) showNormal()
        raise(); requestActivate()
        if (side !== name) runControl(name === "chat" ? "ChatButton" : "RosterButton")
    }
    /// A Teams meeting: Teams' meeting toolbar, the roster and its stage.
    property bool meeting: false
    /// The meeting's participants (from the roster): [{id, name, role}].
    property var roster: []
    /// The call's chat members (People added to the chat).
    property var chatMembers: []
    // Teams' camera-off tile backgrounds: four soft radial gradients,
    // random per tile but kept for the call (its gradientKey).
    property var tileBackgrounds: ({})
    function tileBackground(id) {
        if (!tileBackgrounds[id]) {
            const light = ["hsla(24, 100%, 89%, .08)","hsla(43, 100%, 66%, .08)","hsla(330, 100%, 69%, .08)","hsla(291, 100%, 50%, .08)","hsla(43, 100%, 66%, .08)","hsla(291, 100%, 84%, .08)","hsla(330, 100%, 69%, .08)","hsla(156, 85%, 54%, .08)","hsla(191, 91%, 45%, .08)","hsla(98, 74%, 80%, .08)","hsla(291, 100%, 78%, .08)","hsla(0, 0%, 96%, .08)","hsla(281, 100%, 100%, .08)","hsla(281, 100%, 90%, .08)","hsla(258, 67%, 65%, .08)","hsla(324, 85%, 70%, .08)","hsla(54, 73%, 65%, .08)","hsla(7, 100%, 50%, .08)","hsla(258, 67%, 65%, .08)","hsla(48, 100%, 49%, .08)","hsla(190, 97%, 51%, .08)","hsla(234, 82%, 58%, .08)","hsla(166, 97%, 56%, .08)","hsla(48, 100%, 49%, .08)","hsla(72, 100%, 71%, .08)","hsla(158, 100%, 50%, .08)","hsla(175, 62%, 64%, .08)","hsla(0, 0%, 96%, .08)","hsla(207, 100%, 77%, .08)","hsla(32, 100%, 59%, .08)","hsla(182, 81%, 54%, .08)","hsla(234, 82%, 58%, .08)"]
            const dark = ["hsla(207, 100%, 77%, .1)","hsla(32, 100%, 59%, .1)","hsla(182, 81%, 54%, .1)","hsla(239, 68%, 27%, .1)","hsla(207, 100%, 77%, .1)","hsla(357, 64%, 42%, .1)","hsla(35, 62%, 58%, .1)","hsla(173, 39%, 62%, .1)","hsla(106, 39%, 58%, .1)","hsla(37, 65%, 63%, .1)","hsla(0, 0%, 0%, .1)","hsla(21, 81%, 63%, .1)","hsla(1, 80%, 73%, .1)","hsla(20, 93%, 88%, .1)","hsla(0, 0%, 0%, .1)","hsla(102, 5%, 58%, .1)","hsla(180, 19%, 48%, .1)","hsla(28, 1%, 83%, .1)","hsla(287, 22%, 64%, .1)","hsla(218, 36%, 40%, .1)","hsla(0, 0%, 0%, .1)","hsla(280, 38%, 34%, .1)","hsla(46, 72%, 67%, .1)","hsla(177, 13%, 67%, .1)","hsla(177, 13%, 67%, .1)","hsla(177, 13%, 67%, .1)","hsla(1, 59%, 56%, .1)","hsla(199, 35%, 30%, .1)","hsla(199, 35%, 30%, .1)","hsla(137, 26%, 84%, .1)","hsla(36, 77%, 71%, .1)","hsla(36, 77%, 71%, .1)","hsla(1, 59%, 56%, .1)","hsla(253, 46%, 29%, .1)","hsla(0, 0%, 0%, .1)"]
            const rand = (a, b) => Math.floor(Math.random() * (b - a + 1)) + a
            const lo = () => rand(-15, 40), hi = () => rand(60, 115)
            const at = [() => [lo(), lo()], () => [hi(), lo()], () => [lo(), hi()], () => [hi(), hi()]]
            // Dark: one of the four may be left out, as Teams does.
            const skip = theme.dark && rand(0, 1) ? rand(0, 5) : -1
            const list = theme.dark ? dark : light
            const out = []
            for (let i = 0; i < 4; i++) {
                if (i === skip) continue
                const p = at[i]()
                out.push({ x: p[0], y: p[1], color: list[rand(0, list.length - 1)], stop: theme.dark ? rand(60, 80) : rand(72, 98) })
            }
            tileBackgrounds[id] = out
        }
        return tileBackgrounds[id]
    }
    /// In a meeting: whose camera shows where ({mri: frame key}).
    property var videoKeys: ({})
    /// The meeting's dominant speaker (Speaker view puts them on stage).
    property string speakerId: ""
    // Who is speaking now (Teams' voice-level outline).
    property var speakingIds: []
    /// Sign language mode: who is actively signing (their detection
    /// events on the data channel; you, as you send yours): [mri].
    property var signingIds: []
    function isSigning(id) { return signMode && signingIds.indexOf(id) >= 0 }
    // The meeting muted us while we talked: Teams' "You've been muted",
    // for 30 s, until dismissed, or until we're unmuted.
    property int mutedRemotely: 0
    property bool mutedNoticeShown: false
    onMutedRemotelyChanged: if (mutedRemotely > 0) { mutedNoticeShown = true; mutedNoticeTimer.restart() }
    onMutedChanged: {
        if (!muted) mutedNoticeShown = false
        if (side === "callHealth") refreshCallHealth()
    }
    Timer { id: mutedNoticeTimer; interval: 30000; onTriggered: win.mutedNoticeShown = false }
    // Teams' DeviceSpeakWhileMuted alert: you're talking with the mic off.
    // It shows while that lasts (unless the meeting disabled attendees'
    // mics, or you turned the notice off in Accessibility settings); Close
    // hides it until the next time.
    property bool speakingWhileMuted: false
    property bool speakingNoticeClosed: false
    onSpeakingWhileMutedChanged: if (!speakingWhileMuted) speakingNoticeClosed = false
    readonly property bool speakingNoticeShown: speakingWhileMuted && showMutedNotice && !speakingNoticeClosed
                                                && !micRestricted && state === "connected"
    /// Who presents their screen in the meeting (empty: nobody).
    property string shareId: ""
    /// Content-sharing sessions (Backend call_content_json): Whiteboard,
    /// PowerPoint Live, Excel Live, Annotate — {mine, others, starting,
    /// error, board}.
    readonly property var contentState: { try { return JSON.parse(backend.callContentJson || "{}") || ({}) } catch (e) { return ({}) } }
    /// The session the stage shows: ours, else the newest someone else
    /// presents (Annotate draws over a shared screen instead).
    readonly property var contentSession: {
        const m = contentState.mine
        if (m && m.content && m.content.type !== "annotation") return m
        const o = (contentState.others || []).filter(x => x.content && x.content.type !== "annotation")
        return o.length ? o[o.length - 1] : null
    }
    readonly property bool contentShown: meeting && !!contentSession
    // Annotate (the Sharing control bar's): our annotation session over
    // the screen we share, or someone's over theirs.
    readonly property bool annotating: !!contentState.mine && !!contentState.mine.content && contentState.mine.content.type === "annotation"
    readonly property bool annotationBusy: contentState.starting === "annotation"
    readonly property var annotationViewed: {
        const o = (contentState.others || []).filter(x => x.content && x.content.type === "annotation" && x.presenter === shareId)
        return o.length ? o[o.length - 1] : null
    }
    function toggleAnnotation() {
        if (annotating) backend.contentShareStop()
        else if (!annotationBusy) backend.contentShareStart("annotation", "{}")
    }
    // The presenter's annotation board on top of the shared screen
    // (annotation-app: screenSharer=1 and the shared screen's size).
    readonly property string annotationFrameUrl: {
        if (!annotating || !contentState.board) return ""
        const s = Qt.application.screens[0]
        return backend.contentBoardFrameUrl(contentState.board, true, JSON.stringify({
            sharedScreenWidth: String(s ? s.width : 1920), sharedScreenFullHeight: String(s ? s.height : 1080),
            isScreenSharerOnT2: "true", osType: "Linux", meetingType: String(contentMeetingType),
            meetingTenantId: backend.tenantId(), screenSharer: "1" }))
    }
    Loader {
        active: win.annotationFrameUrl !== "" && win.sharing
        sourceComponent: AnnotationOverlay {
            visible: true
            frameUrl: win.annotationFrameUrl
            thread: backend.callThreadId
            meetingTitle: win.peer
            onBoardReported: (url, passThrough) => {
                const u = url.indexOf("annotation=true") >= 0 ? url : url + (url.indexOf("?") >= 0 ? "&" : "?") + "annotation=true"
                backend.contentShareState(JSON.stringify(passThrough !== undefined && passThrough !== null ? { url: u, passThrough: passThrough } : { url: u }))
                backend.contentSaveBoard("annotation", url)
            }
        }
    }
    readonly property string contentKind: contentSession && contentSession.content ? (contentSession.content.type || "") : ""
    /// Teams' meetingType for shared boards (content_sharing::meeting_type).
    readonly property int contentMeetingType: !meeting ? 5 : adhocMeeting ? 3 : scheduled ? 0 : 4
    readonly property bool presenting: meeting && shareId !== ""
    /// Pop out: the shared content shows in its own window.
    property bool contentPoppedOut: false
    onPresentingChanged: if (!presenting && !contentShown) contentPoppedOut = false
    onContentShownChanged: if (!presenting && !contentShown) contentPoppedOut = false
    readonly property string presenterName: (others.find(p => p.id === shareId) || {}).name || ""
    /// The meeting's link to share (Share invite).
    property string inviteUrl: ""
    /// Who waits in the meeting's lobby: [{id, name, suspected}].
    property var lobby: []
    signal admitLobby(string id, string name, bool notBot)
    signal denyLobby(string id, string name)
    signal admitAllLobby()
    /// Organizers: Teams' End meeting (after its confirmation).
    signal endMeeting()
    /// Teams' "Leave on all my devices".
    signal leaveOnAllDevices()
    /// Teams' Mute all (after its confirmation).
    signal muteAll()
    /// Meeting reactions (Teams: like, heart, applause, laugh, surprised).
    signal sendReaction(string name)
    /// Reactions showing now: {mri: {name, until}} (Teams keeps one on the
    /// sender's tile for 4.25 s).
    property var reactions: ({})
    function showReaction(mri, name) {
        const r = Object.assign({}, reactions)
        r[(mri || "").toLowerCase()] = { name: name, until: Date.now() + 4250 }
        reactions = r
    }
    function reactionOf(mri) {
        const r = reactions[(mri || "").toLowerCase()]
        return r && r.until > Date.now() ? r.name : ""
    }
    Timer {
        running: Object.keys(win.reactions).length > 0
        interval: 250; repeat: true
        onTriggered: {
            const now = Date.now(), r = {}
            for (const k in win.reactions) if (win.reactions[k].until > now) r[k] = win.reactions[k]
            win.reactions = r
        }
    }
    // Teams' reaction pictures: the menu's 64 px V2 and the tile's 168 px V4.
    readonly property var reactionAssets: ({ like: "yes", heart: "heart", applause: "clap", laugh: "laugh", surprised: "surprised" })
    function reactionUrl(name, big) {
        const a = reactionAssets[name]
        if (!a) return ""
        backend.emoticonsVersion
        return backend.cardImage("https://statics.teams.cdn.office.net/evergreen-assets/skype/v2/" + a + (big ? "V4-3D/168.png" : "V2-3D/64.png"))
    }
    // Teams offers Mute all in meetings to organizers and presenters
    // while someone else is connected and not muted by the meeting.
    readonly property bool canMuteAll: meeting && ["organizer", "presenter"].indexOf(((roster.find(p => p.id === selfId) || {}).role || "").toLowerCase()) >= 0
        && others.some(p => p.active !== false && !p.muted)
    /// Your own MRI, to tell you apart in the roster.
    property string selfId: ""
    // Pin for me: whom you pinned (yours only), in pin order; Spotlight for
    // everyone: who the meeting spotlights. Both go to Teams' pin area
    // (813237 PinStage), which holds 9 (maxItemsOnStage); once 9 are
    // pinned, Pin for me is disabled ("You reached the maximum number of
    // pins", isPinningDisabled).
    property var pinnedIds: []
    readonly property int maxPins: 9
    readonly property bool pinningFull: pinnedIds.length >= maxPins
    function pinPerson(id) { if (id && pinnedIds.indexOf(id) < 0 && !pinningFull) pinnedIds = pinnedIds.concat([id]) }
    function unpinPerson(id) { pinnedIds = pinnedIds.filter(x => x !== id) }
    readonly property var spotlighted: roster.filter(p => p.active !== false && !!p.spotlight)
    /// A participant menu action for the meeting (mute, roles, spotlight,
    /// remove).
    signal participantAction(string action, string id, string name, string stateId)
    readonly property var others: roster.filter(p => p.id !== selfId)
    // The stage's tiles changing leaves the side pane's web page showing
    // black until it draws again: ask it for a new frame.
    onOthersChanged: { stageRefresh.round = 0; stageRefresh.restart() }
    // (Again after 1.5 and 4 s: the tiles settle after the roster.)
    Timer {
        id: stageRefresh
        property int round: 0
        interval: round === 0 ? 300 : round === 1 ? 1200 : 2500
        onTriggered: { videoEffectsPane.refreshFrames(); if (++round < 3) restart(); else round = 0 }
    }
    // Teams' spatial audio (SpatialAudioMixinImplementation): on while the
    // layout is Gallery or Speaker (Together mode too in Teams), the call
    // isn't a 1:1 call and more than one other person (not a bot) is in
    // it; each tile's centre on the stage, in percent, goes to the media
    // path for that person's voice (every 240 ms at most, as Teams'
    // debounced updateParticipantPositions).
    readonly property bool spatialLayout: meeting && live && (layout === "gallery" || layout === "speaker")
        && others.filter(p => p.active !== false && (p.id || "").indexOf("28:") !== 0).length > 1
    function spatialTiles() {
        const out = []
        const stage = tiles
        if (!stage.visible || stage.width <= 0 || stage.height <= 0) return out
        const walk = item => {
            for (let i = 0; i < item.children.length; i++) {
                const c = item.children[i]
                if (!c.visible) continue
                if (c.person !== undefined && c.call !== undefined && c.person && c.person.id && !c.person.self && c.width > 0) {
                    const p = c.mapToItem(stage, c.width / 2, c.height / 2)
                    out.push({ id: c.person.id, x: Math.round(p.x / stage.width * 1000) / 10, y: Math.round(p.y / stage.height * 1000) / 10 })
                } else walk(c)
            }
        }
        walk(stage)
        return out
    }
    function spatialForTest() { return { layout: spatialLayout, tiles: spatialTiles() } }
    Timer {
        id: spatialTimer
        interval: 240; repeat: true
        running: win.visible && win.meeting && win.live
        property string last: ""
        onTriggered: {
            const t = win.spatialLayout ? win.spatialTiles() : []
            const key = win.spatialLayout + JSON.stringify(t)
            if (key === last) return
            last = key
            backend.setSpatialState(win.spatialLayout, JSON.stringify(t))
        }
        onRunningChanged: if (!running) { last = ""; backend.setSpatialState(false, "[]") }
    }
    // Teams shows Controls and Rooms to the meeting's organizer only.
    readonly property bool organizer: ((roster.find(p => p.id === selfId) || {}).role || "").toLowerCase() === "organizer"
    readonly property string myRole: ((roster.find(p => p.id === selfId) || {}).role || "").toLowerCase()
    // Teams' network strength indicator (your name tag's bars): shown while
    // the strength isn't Good, and for 120 s after it is again.
    property string networkStrength: "Good"
    /// Your connection is wired (Teams' tip then mentions the cable).
    property bool wired: false
    property bool nsiShown: false
    property bool nsiCaptured: false
    Timer { id: nsiHide; interval: 120000; onTriggered: win.nsiShown = false }
    onNetworkStrengthChanged: {
        if (networkStrength === "Poor" || networkStrength === "Bad") { nsiShown = true; nsiHide.stop() }
        else if (nsiShown && !nsiHide.running) nsiHide.start()
    }
    /// Turned off by "Turn off all video" (Teams then offers to turn it on).
    property bool nsiVideoOff: false
    readonly property string networkHeading: networkStrength === "Bad" ? qsTr("Connection is weak")
        : networkStrength === "Poor" ? qsTr("Connection is unstable") : qsTr("Connection is good")
    readonly property string networkTip: {
        const p2p = !meeting, cam = cameraOn, inc = !incomingVideoOff
        if (networkStrength === "Bad") {
            if (cam && inc) return p2p ? qsTr("One or both participants may have network problems. Try turning off your camera and incoming video to use less bandwidth.") : qsTr("Try turning off your camera and incoming video to use less bandwidth.")
            if (cam) return p2p ? qsTr("One or both participants may have network problems. Try turning off your camera to use less bandwidth.") : qsTr("Try turning off your camera to use less bandwidth.")
            if (inc) return p2p ? qsTr("One or both participants may have network problems. Try turning off incoming video to use less bandwidth.") : qsTr("Try turning off incoming video to use less bandwidth.")
            return p2p ? qsTr("One or both participants may have network problems. This might impact the quality of the call.") : qsTr("This may impact the quality of your call.")
        }
        if (networkStrength === "Poor")
            return wired ? qsTr("Check your cable connection or try turning off other apps.")
                : p2p ? qsTr("One or both participants may have network problems. This might impact the quality of the call.") : qsTr("This may impact the quality of your call.")
        return qsTr("Turn on your camera and video anytime.")
    }
    function showNetworkPopover(item) { networkPopoverClose.stop(); if (!networkPopover.opened) { networkPopover.anchorItem = item; networkPopover.open() } }
    function leaveNetworkPopover() { networkPopoverClose.restart() }
    function networkPopoverForTest() { networkPopover.anchorItem = timerText; networkPopover.open() }
    Timer { id: networkPopoverClose; interval: 250; onTriggered: if (!networkPopover.hovered) networkPopover.close() }
    /// The meeting is locked (Teams' Lock the meeting), and what attendees
    /// may not do (bits: mic 1, camera 2).
    property bool locked: false
    property int attendeeRestrictions: 0
    // Teams' AI indicator (calling-agents-control-ubar-indicator): shown in
    // Meet now and private scheduled meetings; disabled when the meeting
    // has no AI ("AI isn't available in this meeting"); lit while the
    // meeting's transcript runs ("AI is on in the meeting").
    property bool aiIndicator: false
    /// End-to-end encryption (Teams' e2eeStatusChangedEvent): whether the
    /// call is end-to-end encrypted, and its encryption numbers (Teams'
    /// fingerprint hash as 4-digit groups) to compare with the other side.
    property bool e2ee: false
    /// Teams' isCallParkAvailable for you (park policy and Enterprise Voice).
    property bool canPark: false
    /// The call was parked: Teams' window then says "Call is parked" with
    /// the pickup code and Copy code (measured on winpc 2026-11-17).
    property string parkCode: ""
    function parkedViewForTest() { return parkedView }
    /// Park Call (More): the call goes to the park server and its pickup
    /// code comes back.
    signal parkCall()
    property var e2eeNumbers: []
    function encryptionCardForTest() { encryptionCard.open() }
    function encryptionCardItemForTest() { return encryptionCard }
    property bool aiAvailable: false
    /// The meeting's Allow Copilot is "Only during the meeting"
    /// (copilotMode "Enabled"): Copilot runs without a saved transcript.
    property bool copilotOnly: false
    /// Copilot runs (the recorder's copilot processing mode).
    property bool copilotRunning: false
    property bool aiFacilitator: false
    property bool aiOn: false
    /// Teams' Meeting info pane: {title, hours, schedule, location, body,
    /// canCopy} once loaded.
    property var meetingInfo: null
    signal loadMeetingInfo()
    signal copyMeetingJoinInfo()
    // Teams' recording indicator (recording-indicator-custom):
    // "Transcribing", "Recording" or "RecordingAndTranscribing" ("" hides
    // it), with who started them as its tooltip.
    property string recordingState: ""
    property string recordingTip: ""
    function aiPopoverForTest() { aiPopover.open() }
    function aiPopoverCloseForTest() { aiPopover.close() }
    function audioPaneForTest() { return audioSettingsPane }
    /// You're an attendee and the meeting has disabled attendees' mic or
    /// camera (Teams then disables the button with its reason).
    readonly property bool micRestricted: meeting && myRole === "attendee" && (attendeeRestrictions & 1) !== 0 && muted
    readonly property bool videoRestricted: meeting && myRole === "attendee" && (attendeeRestrictions & 2) !== 0 && !cameraOn
    /// Bumped by the backend when the meeting locks or unlocks.
    property int lockNotices: 0
    /// The People pane's More actions, as Teams offers them
    /// (roster-header-more-menu): Mute all; Disable / Allow mic and camera
    /// for attendees when there are attendees; Lower all hands while hands
    /// are up; Download attendance list (organizer); Stop all spotlights
    /// with more than one; Lock / Unlock the meeting (organizer).
    readonly property var moreItems: {
        if (!meeting) return []
        const out = []
        const manager = myRole === "organizer" || myRole === "presenter" || myRole === "coorganizer"
        if (canMuteAll) out.push({ k: "muteAll", t: qsTr("Mute all"), icon: "mic-off-20" })
        const attendees = others.some(p => p.active !== false && (p.role || "").toLowerCase() === "attendee")
        if (manager && attendees) {
            out.push(attendeeRestrictions & 1
                ? { k: "allowMic", t: qsTr("Allow mic for attendees"), icon: "mic-20" }
                : { k: "restrictMic", t: qsTr("Disable mic for attendees"), icon: "mic-prohibited-20" })
            out.push(attendeeRestrictions & 2
                ? { k: "allowCamera", t: qsTr("Allow camera for attendees"), icon: "video-20" }
                : { k: "restrictCamera", t: qsTr("Disable camera for attendees"), icon: "video-prohibited-20" })
        }
        if (manager && hands.length > 0) out.push({ k: "lowerHands", t: qsTr("Lower all hands"), icon: "hand-right-off-20" })
        if (organizer) out.push({ k: "attendance", t: qsTr("Download attendance list"), icon: "arrow-download-20" })
        if (manager && spotlighted.length > 1) out.push({ k: "stopSpotlights", t: qsTr("Stop all spotlights"), icon: "spotlight-20" })
        if (organizer) out.push(locked ? { k: "unlock", t: qsTr("Unlock the meeting"), icon: "lock-closed-20" }
                                       : { k: "lock", t: qsTr("Lock the meeting"), icon: "lock-closed-20" })
        return out
    }
    /// Teams' Controls menu (organizers), read from the meeting's options
    /// (call_controls_json): {options: [{name, currentValue, ...}]}.
    property var controlsOptions: ({})
    /// The people pickers' invitees, names and organizer (the same reply).
    property var controlsPeople: ({})
    signal loadControls()
    signal setMeetingOption(string name, var value)
    signal applyMeetingOptions(var changes)
    function openMeetingOptions() { loadControls(); optionsDialog.open() }
    function controlValue(n) { const o = controlsOptions[n]; return o ? o.currentValue : undefined }
    // Teams' item states and toggles (unified-bar-container-manager `St`,
    // `xe`, `je`, `gt`): everyone presenting locks the A/V restrictions to
    // unrestricted.
    readonly property bool controlsEveryonePresents: ["Everyone", "EveryoneInCompany"].indexOf(controlValue("PresenterOption")) >= 0
    readonly property string avRestrictions: controlsEveryonePresents ? "UnRestricted" : (controlValue("AttendeeRestrictions") || "")
    function avActive(audio) {
        const r = avRestrictions
        if (!r) return false
        if (r === "UnRestricted") return true
        if (r === "DisableAudio") return !audio
        if (r === "DisableVideo") return audio
        return false
    }
    function avToggle(audio) {
        switch (avRestrictions) {
        case "": return "DisableAudio,DisableVideo"
        case "UnRestricted": return audio ? "DisableAudio" : "DisableVideo"
        case "DisableAudio": return audio ? "UnRestricted" : "DisableAudio,DisableVideo"
        case "DisableVideo": return audio ? "DisableAudio,DisableVideo" : "UnRestricted"
        default: return audio ? "DisableVideo" : "DisableAudio"
        }
    }
    function listToggle(current) { return current === "Everyone" ? "OrganizerOnly" : "Everyone" }
    readonly property var controlsItems: {
        const loaded = Object.keys(controlsOptions).length > 0
        const lockTip = qsTr("This option is locked because everyone in this meeting already has presenter permissions.")
        return [
            { label: qsTr("Lock meeting"), key: "lock", checked: locked, tip: qsTr("When the meeting is locked, nobody else can join the meeting.") },
            { label: qsTr("Enable lobby"), key: "AutoAdmittedUsers", checked: loaded && controlValue("AutoAdmittedUsers") !== "Everyone", enabled: loaded,
              tip: qsTr("When lobby is enabled, participants will wait in a lobby until admitted by an organizer.") },
            { separator: true },
            { heading: qsTr("Allow all participants to:") },
            { label: qsTr("Present"), key: "PresenterOption", checked: loaded && controlValue("PresenterOption") === "Everyone", enabled: loaded },
            { label: qsTr("Chat"), key: "AllowMeetingChat", checked: loaded && controlValue("AllowMeetingChat") !== "Disabled", enabled: loaded },
            { label: qsTr("Unmute themselves"), key: "audio", checked: avActive(true), enabled: loaded && !controlsEveryonePresents, tip: controlsEveryonePresents ? lockTip : "" },
            { label: qsTr("Turn on their cameras"), key: "video", checked: avActive(false), enabled: loaded && !controlsEveryonePresents, tip: controlsEveryonePresents ? lockTip : "" },
            { separator: true },
            { label: qsTr("View more options"), key: "options" }
        ]
    }
    function pickControl(key) {
        if (key === "lock") runMoreAction(locked ? "unlock" : "lock")
        else if (key === "options") openMeetingOptions()
        else if (key === "AutoAdmittedUsers" || key === "PresenterOption") setMeetingOption(key, listToggle(controlValue(key)))
        else if (key === "AllowMeetingChat") setMeetingOption(key, controlValue(key) === "Disabled" ? "Enabled" : "Disabled")
        else if (key === "audio" || key === "video") setMeetingOption("AttendeeRestrictions", avToggle(key === "audio"))
    }
    /// A More actions request: "lock", "unlock", "lowerHands",
    /// "stopSpotlights".
    signal meetingAction(string action)
    /// Set the attendee restriction bits (Disable / Allow mic or camera).
    signal setAttendeeRestrictions(int bits)
    signal downloadAttendance()
    function runMoreAction(k) {
        if (k === "muteAll") muteAllAsk.open()
        else if (k === "restrictMic" || k === "allowMic") { restrictAsk.modality = 1; restrictAsk.open() }
        else if (k === "restrictCamera" || k === "allowCamera") { restrictAsk.modality = 2; restrictAsk.open() }
        else if (k === "lowerHands") { lowerHandsAsk.count = hands.length; lowerHandsAsk.open() }
        else if (k === "attendance") downloadAttendance()
        else if (k === "stopSpotlights") meetingAction("stopSpotlights")
        else if (k === "lock" || k === "unlock") { lockAsk.locked = locked; lockAsk.open() }
    }
    readonly property bool remoteVideoShown: remoteVideo.visible
    readonly property bool shareShown: shareVideo.visible
    // People pane rows: you first, then everyone else.
    /// Raise hand: yours, and everyone's in the order they raised.
    property bool handRaised: false
    signal toggleHand()
    readonly property var hands: roster.filter(p => !!p.hand).map(p => p.id)
    readonly property var people: meeting
        ? [{ name: selfName || qsTr("You"), id: "me", you: true, mutedNow: muted || !hasAudio, hand: handRaised,
             role: (roster.find(p => p.id === selfId) || {}).role || "" }]
          .concat(others.map(p => ({ name: p.name, id: p.id, you: false, mutedNow: p.muted, role: p.role, hand: !!p.hand, guest: !!p.guest, suspected: !!p.suspected, spotlight: p.spotlight || "", signLine: signLine(p), signFirst: signMode && (iSign ? p.sign_role === "signLanguageInterpreter" : p.sign_role === "dhhSigner") })))
        : [{ name: selfName || qsTr("You"), id: "me", you: true, mutedNow: muted || !hasAudio },
           { name: peer, id: backend.callPeerId, you: false, mutedNow: false }]
    /// Hold: you put the call on hold, or the other person did.
    property bool held: false
    property bool heldByPeer: false
    signal toggleHold()
    /// Dial pad: the call takes tones; dtmf(key) sends one.
    property bool canDtmf: false
    signal dtmf(string key)
    /// View: "gallery" or "speaker"; incoming video can be turned off.
    property string layout: "gallery"
    property bool incomingVideoOff: false
    // Teams' View menu settings for meetings.
    property int gallerySize: 16
    // Which page of the gallery shows, when more people are in it than its
    // size (Teams' "‹ 1/2 ›" under the tiles).
    property int galleryPage: 0
    property bool videosFirst: false
    property bool galleryAtTop: false
    property bool hideMe: false
    /// Gallery: you are one of its tiles (else you sit in the side gallery).
    property bool meInGallery: true
    /// Speaker: you are ordered with the others in the side gallery (else
    /// docked at its end).
    property bool speakerMeInGallery: false
    /// Optimize for room: the gallery shows in a shared display window.
    property bool roomMode: false
    /// Your tile entry, as the layouts use it.
    readonly property var selfEntry: ({ id: selfId, name: selfName || qsTr("You"), self: true })
    /// How wide each person's tile is drawn ({mri: px}): the size of video
    /// to ask for (Teams asks to fit its tiles).
    readonly property var videoWidths: {
        const out = {}
        if (!meeting) return out
        const sideSlot = tiles.atTop ? tiles.sideH * 16 / 9 : tiles.sideW
        for (const p of tiles.side) out[p.id] = sideSlot
        if (tiles.featured && !presenting)
            for (const p of tiles.featuredList) out[p.id] = pinGrid.tileW
        else if (layout === "speaker" && !presenting && tiles.speaker)
            out[tiles.speaker.id] = Math.min(tiles.mainW, tiles.mainH * 16 / 9)
        if (layout !== "speaker" && !presenting)
            for (const p of tiles.gallery) out[p.id] = galleryTileWidth
        return out
    }
    property real galleryTileWidth: 0
    /// Whose video Teams focuses (879019 shouldFocusMainStream: pinned,
    /// spotlighted, sign language people on the focused or pin area): they
    /// get the main stream at its best, and slots first.
    readonly property var videoFocus: !meeting ? [] : tiles.featuredList.filter(p => !p.self).map(p => p.id)
    /// Someone has video on (or it's you with the camera on).
    function hasVideo(p) { return p.self ? cameraOn : !!videoKeys[p.id] }
    // ---- Sign language mode (Teams' SignerMixin, 813237, calling-roster;
    // TASK-0182): your role from Settings ▸ Accessibility, published in
    // the meeting; the people your role signs with come first on the stage
    // (with video), get their tile icon and their People line. ----
    readonly property var a11y: { let v = window.syncedProps.callAccessibilitySettings; if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { v = null } } return v || ({}) }
    readonly property bool signMode: a11y.accessibilityModeEnabledV2 === true
    readonly property bool iSign: signMode && a11y.signLanguageModeSelection !== "INTERPRETER"
    readonly property bool iInterpret: signMode && a11y.signLanguageModeSelection === "INTERPRETER"
    readonly property var myInterpreters: Array.isArray(a11y.selectedDHHInterpreters) ? a11y.selectedDHHInterpreters : []
    function signContentOf(p) { try { return JSON.parse(p.sign_content || "{}") } catch (e) { return ({}) } }
    // A signer who named you as their interpreter.
    function pairedSigner(p) { return p.sign_role === "dhhSigner" && (signContentOf(p).interpreterIds || "").split(",").indexOf(selfId) >= 0 }
    function myInterpreter(p) { return p.sign_role === "signLanguageInterpreter" && myInterpreters.indexOf(p.id) >= 0 }
    // Teams' signer icon shows when they share their status or you're
    // their interpreter (and you're in the mode).
    function signerShown(p) { return signMode && p.sign_role === "dhhSigner" && (signContentOf(p).showSignerIdentificationToOthers !== false || pairedSigner(p)) }
    // Their People line (calling-roster): an interpreter is "Sign Language
    // Interpreter" (yours: "Your Sign Language Interpreter"), a signer who
    // chose you "Paired to you".
    function signLine(p) {
        if (!signMode) return ""
        if (p.sign_role === "signLanguageInterpreter") return myInterpreter(p) ? qsTr("Your Sign Language Interpreter") : qsTr("Sign Language Interpreter")
        if (pairedSigner(p)) return qsTr("Paired to you")
        return ""
    }
    // Role 3 (paired): a partner with video on; then only partners count.
    readonly property bool signPaired: signMode && others.some(p => hasVideo(p) && (iSign ? myInterpreter(p) : pairedSigner(p)))
    function signPriority(p) {
        if (!signMode || !hasVideo(p)) return false
        if (signPaired) return iSign ? myInterpreter(p) : pairedSigner(p)
        return iSign ? p.sign_role === "signLanguageInterpreter" : p.sign_role === "dhhSigner"
    }
    readonly property var signFirst: others.filter(p => signPriority(p))
    // Teams' tethering (937485, 813237): a signer and an interpreter they
    // named who is in the call as an interpreter hold each other in
    // tetheredInCallDHHParticipants (you included, by your own role).
    function tetheredOf(p) {
        if (!signMode || !p) return []
        const me = Object.assign({}, selfEntry, { sign_role: iInterpret ? "signLanguageInterpreter" : iSign ? "dhhSigner" : "",
                                                  sign_content: iSign ? signContent : "{}" })
        const all = others.concat([me])
        const subject = p.self ? me : p
        const names = q => (signContentOf(q).interpreterIds || "").split(",").filter(s => s)
        if (subject.sign_role === "dhhSigner")
            return all.filter(q => q.id !== subject.id && q.sign_role === "signLanguageInterpreter" && names(subject).indexOf(q.id) >= 0)
        if (subject.sign_role === "signLanguageInterpreter")
            return all.filter(q => q.id !== subject.id && q.sign_role === "dhhSigner" && names(q).indexOf(subject.id) >= 0)
        return []
    }
    // The badge's tooltip (293537): "<interpreter> is voice interpreting"
    // with one tethered interpreter (with several, the first among the
    // dominant speakers), else when you are one of them or the name is
    // unknown "Voice interpretation in progress".
    function signingTooltip(tethered) {
        const ids = (tethered || []).map(q => q.id)
        if (!ids.length || ids.indexOf(selfId) >= 0) return qsTr("Voice interpretation in progress")
        const pick = ids.length === 1 ? tethered[0] : (tethered.find(q => q.id === speakerId) || null)
        const name = pick ? (pick.name || "").trim() : ""
        return name ? qsTr("%1 is voice interpreting").arg(name) : qsTr("Voice interpretation in progress")
    }
    // What we publish, kept in step with the settings while in the meeting.
    readonly property string signKind: !signMode ? "" : iInterpret ? "signLanguageInterpreter" : "dhhSigner"
    readonly property string signContent: signKind === "dhhSigner" ? JSON.stringify({ interpreterIds: myInterpreters.join(","), showSignerIdentificationToOthers: a11y.showSignerIdentificationToOthers !== false }) : "{}"
    readonly property string signWanted: live && meeting ? signKind + "|" + signContent : ""
    property string signPublished: ""
    onSignWantedChanged: Qt.callLater(syncSignState)
    function syncSignState() {
        if (!live || !meeting) { signPublished = ""; return }
        if (signWanted === signPublished) return
        if (!signKind && !signPublished) return
        console.warn("SIGN publish", signKind, signContent)
        backend.setSignLanguageState(signKind, signContent)
        signPublished = signWanted
    }
    // Teams: a Signer joining with no interpreters chosen is reminded.
    property bool signAlertShown: false
    onLiveChanged: if (live && meeting && iSign && myInterpreters.length === 0 && !signAlertShown) { signAlertShown = true; signAlert.show() }
    // Leaving the mode leaves its view.
    onSignModeChanged: if (!signMode && layout === "accessibility") layout = "gallery"
    /// The others in gallery order (Sign language mode's people first,
    /// then videos first, when asked).
    readonly property var othersOrdered: {
        const rest = others.filter(p => signFirst.indexOf(p) < 0)
        return signFirst.concat(videosFirst ? rest.filter(p => hasVideo(p)).concat(rest.filter(p => !hasVideo(p))) : rest)
    }
    /// Meetings: Teams' meeting options page (Controls) and the meeting
    /// chat on the web (Notes), and opening an app from Apps.
    property string optionsUrl: ""
    property string chatUrl: ""
    signal openApp(string key)
    /// Transfer and Consult: the people search, and the person picked.
    property var directory: []
    signal searchPeople(string query)
    signal transfer(string oid, string name)
    signal consult(string oid, string name)
    /// Consult by call (Teams' Consult ▸ Start a call): the first call is
    /// held and a second one placed; from it, Transfer (replacing it),
    /// Merge Calls, or End consult (back to the held call).
    signal consultByCall(string oid, string name)
    signal consultTransfer()
    signal consultMerge()
    signal consultEnd()
    /// The consult call as it stands: {state: calling | connected |
    /// transferring | merging, mri, name}, or null.
    property var consultCall: null
    /// Consulting someone before transferring (their chat is open).
    property var consulting: null
    readonly property bool live: state === "connected"
    function toggleFullScreen() { visibility = visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    /// The open side pane: "", "chat" or "people".
    property string side: ""
    /// Leave, asking first when Settings ▸ General says to (meetings).
    function leaveAsked() {
        if (win.meeting && backend.setting("leaveConfirmation") === "true") leaveConfirm.open()
        else win.leave()
    }
    /// The effects pane's "Green screen settings" (Main shows Settings ▸
    /// Devices).
    signal greenScreenSettings()
    // Breakout rooms. As organizer: the meeting's rooms (its call lists
    // them), their settings and Teams' alerts for what you do; as a
    // participant (Main.qml moves you): whether your room is open to join,
    // and whether you may go back.
    readonly property var breakoutRooms: {
        const all = backend.callBreakoutAllJson ? JSON.parse(backend.callBreakoutAllJson) : null
        if (all) return all
        const api = backend.callBreakoutRoomsJson ? JSON.parse(backend.callBreakoutRoomsJson) : {}
        return (api.rooms || []).map(r => ({ name: r.name, thread: r.thread, join_url: r.join_url, open: r.open,
                                            invitees: (r.participants || []).map(p => p.mri) }))
    }
    readonly property var breakoutSettings: (backend.callBreakoutRoomsJson ? JSON.parse(backend.callBreakoutRoomsJson) : {}).settings || ({})
    property var breakoutNames: ({})
    onPeopleChanged: {
        let added = false
        const n = Object.assign({}, breakoutNames)
        for (const p of people) if (!p.you && p.id && n[p.id] !== p.name) { n[p.id] = p.name; added = true }
        if (added) breakoutNames = n
    }
    property bool breakoutBusy: false
    property bool roomToJoin: false
    /// The main meeting on hold while you (its organizer) are in a room:
    /// {title, url, since}, or null.
    readonly property var heldMeeting: backend.callHeldMeetingJson ? JSON.parse(backend.callHeldMeetingJson) : null
    /// Leave room (`resume`: back to the held main meeting) or Leave meeting.
    signal leaveRoom(bool resume)
    property bool canReturnToMain: false
    signal joinBreakoutRoom()
    signal returnToMainMeeting()
    /// The organizer's Join on a room's menu.
    signal joinRoomAsOrganizer(var room)
    function breakoutRun(action, args) {
        breakoutBusy = true
        const a = Object.assign({ total: people.length }, args || {})
        backend.breakoutAction(action, JSON.stringify(a))
    }
    function nextRoomName() {
        const used = breakoutRooms.map(r => { const m = /^Room (\d+)$/.exec(r.name); return m ? parseInt(m[1]) : 0 })
        return "Room " + (Math.max(0, ...used) + 1)
    }
    // Teams' Create rooms: "Room 1" … "Room n"; automatic assignment
    // spreads everyone else evenly at random; letting people choose sets
    // the rooms' allowUsersToSelectBreakoutRoom.
    // `late`: people not in the meeting yet assigned to the first room
    // (Teams' assignment before they join; the late-joiner harness).
    function createBreakoutRooms(count, mode, late) {
        const others = people.filter(p => !p.you)
        for (let i = others.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [others[i], others[j]] = [others[j], others[i]] }
        const rooms = []
        for (let i = 0; i < count; i++) rooms.push({ name: "Room " + (i + 1), participants: [] })
        if (mode === "automatic")
            others.forEach((p, i) => rooms[i % count].participants.push({ mri: p.id, role: p.guest ? "guest" : "admin", tenantId: backend.tenantId() }))
        for (const mri of late || []) rooms[0].participants.push({ mri: mri, role: "admin", tenantId: backend.tenantId() })
        breakoutRun("create", { rooms: rooms, settings: { allow_select: mode === "selfselect", allow_return: false } })
    }
    function importBreakoutCsv() { csvDialog.open() }
    // The breakout rooms harness (--breakout-test): open a view or dialog.
    function heldWindowForTest() { return heldWindow.visible ? heldWindow : null }
    function roomsForTest(op) {
        if (op === "pane") side = "rooms"
        else if (op === "assign") assignRooms.show()
        else if (op === "settings") roomsPane.settingsOpen = true
        else if (op === "back") roomsPane.settingsOpen = false
        else if (op === "announce") roomsPane.announce()
        else if (op === "rename" && breakoutRooms.length) roomsPane.roomAction("rename", breakoutRooms[0])
        else if (op === "remove") removeRoomsAsk.open()
        else if (op === "csv") csvDialog.open()
        else if (op === "close") for (const d of [assignRooms, roomText, removeRoomsAsk, deleteRoomAsk, csvDialog]) d.close()
    }
    function breakoutDone(action, error) {
        breakoutBusy = false
        const ok = {
            create: [qsTr("Breakout rooms have been created."), "call-rooms"], add: [qsTr("Room was added"), ""],
            rename: [qsTr("Room was renamed"), ""], delete: [qsTr("Room was deleted"), ""], delete_all: [qsTr("Rooms were deleted"), ""],
            import_csv: [qsTr("Breakout rooms have been created."), "call-rooms"]
        }
        const failed = {
            create: qsTr("We ran into a problem creating rooms. Try again."), add: qsTr("Room failed to be added"),
            rename: qsTr("Room failed to be renamed"), delete: qsTr("Room failed to be deleted"), delete_all: qsTr("Couldn't delete rooms."),
            assign: qsTr("We had some trouble assigning participants."), announce: qsTr("Couldn't send your announcement."),
            settings: qsTr("Your settings failed to save"), import_csv: qsTr("We ran into a problem creating rooms. Try again.")
        }
        // A CSV import that skipped entries says why (Teams' import
        // warnings).
        const warnings = action === "import_csv" && !error
            ? ((backend.callBreakoutRoomsJson ? JSON.parse(backend.callBreakoutRoomsJson) : {}).warnings || []) : []
        if (error && failed[action]) showBreakoutAlert(action === "import_csv" && error.indexOf("couldn't import") >= 0 ? error : failed[action], "alert-warning-16-filled")
        else if (warnings.length > 1) showBreakoutAlert(qsTr("Your CSV was imported, but some entries were skipped because of multiple issues."), "alert-warning-16-filled")
        else if (warnings.length === 1) showBreakoutAlert({
                MALFORMED_ENTRIES: qsTr("Some entries in CSV were skipped because of the following issues"),
                USER_ASSIGNED_MULTIPLE_ROOMS: qsTr("Some participants were listed in multiple rooms. Each participant can be assigned to only one room. We kept the assignment from the last occurrence in the file. Remove duplicates, then import again."),
                LIMIT_EXCEEDED: qsTr("Breakout room limits were exceeded. Teams supports up to %1 rooms and %2 participants. Reduce the number of rooms or participants in your CSV, then import again.").arg(100).arg(1000),
                UNMATCHED_PARTICIPANTS: qsTr("Some entries in CSV were skipped because of the following issues")
            }[warnings[0]] || "", "alert-warning-16-filled")
        else if (!error && ok[action]) showBreakoutAlert(ok[action][0], ok[action][1])
    }
    // Teams' lobby chat (organizers of a meeting with a lobby): the toast's
    // chat button opens the chat pane on its Lobby tab.
    // Only scheduled meetings have one (a channel meeting's lobby chat
    // request answers 404).
    readonly property bool lobbyChatAvailable: meeting && myRole === "organizer" && backend.callThreadId.indexOf("19:meeting_") === 0
    readonly property bool lobbyTabShown: lobbyChatAvailable && backend.callLobbyThread !== ""
    property string chatTab: "everyone"
    readonly property var chatTabs: [
        { key: "everyone", label: qsTr("Everyone"), tip: qsTr("Chat for everyone in the meeting") },
        { key: "lobby", label: qsTr("Lobby"), tip: qsTr("Chat for organizers messaging people in the lobby"), badge: qsTr("%n waiting", "", lobby.length), count: lobby.length }
    ]
    function openLobbyChat() {
        side = "chat"; openChat(); chatTab = "lobby"
        backend.openLobbyChat()
    }
    property string lobbyChatOpen: ""
    Connections {
        target: backend
        function onCallLobbyThreadChanged() {
            if (win.lobbyChatOpen) backend.closeChatWindow(win.lobbyChatOpen)
            win.lobbyChatOpen = backend.callLobbyThread
            if (win.lobbyChatOpen) backend.openChatWindow(win.lobbyChatOpen)
            else win.chatTab = "everyone"
        }
    }
    // The lobby thread's people join masked ("Attendee"); with one person
    // waiting Teams names them: "Attendee (OST Test 2) is in the lobby."
    readonly property var lobbyMessages: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        // Teams' Lobby tab shows the messages and who is in the lobby, not
        // the thread's other control messages.
        const msgs = (all["win:" + backend.callLobbyThread] || []).filter(m => m.kind === "message" || (m.kind === "event" && m.event && m.event.kind === "LobbyJoined"))
        if (lobby.length !== 1) return msgs
        const real = lobby[0].name
        return msgs.map(m => {
            if (m.kind !== "event" || !m.event || m.event.kind !== "LobbyJoined" || (m.event.targets || []).length !== 1) return m
            const shown = m.text.replace(/ is in the lobby\.$/, "")
            const named = shown + " (" + real + ")"
            return Object.assign({}, m, { text: qsTr("%1 is in the lobby.").arg(named), event: Object.assign({}, m.event, { unverified: (m.event.unverified || []).map(n => n === shown ? named : n) }) })
        })
    }
    signal openChat()

    width: 1024; height: 640
    minimumWidth: 720; minimumHeight: 420
    color: theme.surface
    title: peer + " | OST"

    property int seconds: 0
    property real heldAt: 0
    property int heldSeconds: 0
    onHeldChanged: { heldAt = Date.now(); heldSeconds = 0 }
    Timer {
        interval: 1000; repeat: true
        running: win.visible && win.held
        onTriggered: win.heldSeconds = Math.floor((Date.now() - win.heldAt) / 1000)
    }
    Timer {
        interval: 1000; repeat: true
        running: win.visible && win.state === "connected"
        onTriggered: win.seconds = Math.floor((Date.now() - win.connectedAt) / 1000)
    }
    onStateChanged: {
        // Resuming a held meeting carries on its time (nextConnectedAt); a
        // call that replaced the one we were in (a transfer, a merge, a
        // retrieved park) keeps the running clock too, since the window
        // never closed.
        if (state === "connected") {
            // Teams' voicemail greeting call opens with its dial pad (the
            // voicemail's menu is driven by keys; winpc 2026-11-17).
            if (voicemail) Qt.callLater(() => { if (win.voicemail && win.live && !dialPad.visible && win.controlEnabled("DialpadButton")) win.runControl("DialpadButton") })
            if (connectedAt === 0 || !win.callContinues) connectedAt = nextConnectedAt || Date.now()
            nextConnectedAt = 0; seconds = Math.floor((Date.now() - connectedAt) / 1000)
        }
        else consulting = null
        if (state === "ended" || state === "") connectedAt = 0
        // A new call: lobby notifications are on again.
        if (state === "calling") lobbyToast.resetForCall()
        if (state === "calling" || state === "connecting") { transcriptRan = false; openTranscriptWhenStarted = false }
    }

    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
        const two = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + two(m) : two(m)) + ":" + two(sec)
    }

    // The bar, from Teams' layout config (see the middle slot below).
    readonly property bool pstnCall: !meeting && (backend.callPeerId || "").indexOf("4:") === 0
    /// A scheduled meeting (joined from its link), not a chat's group call.
    property bool scheduled: false
    /// A channel's Meet now: a meeting, ad hoc.
    property bool adhocMeeting: false
    // Teams' New meeting controls (Settings ▸ General ▸ Meeting, a Teams
    // Labs feature kept on this device): its InlineCentered layout. Read
    // again whenever the window is activated, so turning it on or off in
    // Settings reaches a meeting in progress, as in Teams.
    property bool newControls: backend.setting("newMeetingControls") === "true"
    /// The bar's fill: the new controls' NeutralBackground1, else the
    /// surface.
    readonly property color barFill: newControls ? theme.menu : theme.surface
    // The user's arrangement of the new controls (Pin, Unpin, Move), per
    // client as Teams keeps it: {unpinned, pinned, order} per layout.
    property var controlsLayouts: { try { return JSON.parse(backend.setting("meetingControlsLayouts") || "{}") } catch (e) { return {} } }
    readonly property string controlsLayoutId: meeting ? "default" : pstnCall ? "oneToOnePstn" : "oneToOneOrGroupCall"
    readonly property var controlsCustomization: controlsLayouts[controlsLayoutId] || ({})
    onActiveChanged: if (active) {
        newControls = backend.setting("newMeetingControls") === "true"
    }
    function saveCustomization(c) {
        const all = Object.assign({}, controlsLayouts)
        if (c) all[controlsLayoutId] = c
        else delete all[controlsLayoutId]
        controlsLayouts = all
        backend.setSetting("meetingControlsLayouts", JSON.stringify(all))
    }
    // Under 480 px wide Teams' bar turns compact: 40 tall, 32 px buttons
    // without labels (measured with New meeting controls on).
    readonly property bool compactBar: newControls && width < 480
    readonly property var ubarFacts: ({
        p2p: !meeting, pstn: pstnCall, consult: false, scheduled: scheduled, adhoc: adhocMeeting,
        organizer: organizer, onHold: held, canPopOut: (presenting || contentShown) && !contentPoppedOut,
        // A town hall or webinar shows React only where the meeting allows reactions.
        reactions: !isEvent || !!liveEvent.reactions,
        roomToJoin: roomToJoin, canReturnToMain: canReturnToMain, breakoutRoom: backend.callBreakoutRoomJson !== "" || !!heldMeeting,
        centered: newControls, customization: dragPreview || controlsCustomization, echo: testCall, copilot: copilotAllowed,
        canTakeControl: presenting && !!controlState.capable,
        callMe: !!phone.available && !!phone.dialIn && !!phone.dial, facilitator: copilotAllowed,
        townHall: !!liveEvent.townHall, webinar: !!liveEvent.webinar, attendee: myRole === "attendee" || streaming, streaming: streaming,
        greenRoom: !!liveEvent.staging && myRole !== "attendee" && !streaming && live && liveEvent.eventPhase === "prelive",
        eventPhase: liveEvent.eventPhase || "", qna: !!liveEvent.qna && scheduled,
        e2ee: e2ee, canPark: canPark, voicemail: voicemail,
        whiteboardSharing: !!contentState.mine && !!contentState.mine.content && ["whiteboard", "extensible_app"].indexOf(contentState.mine.content.type) >= 0,
        pptSharing: pptPresenting,
        pptViewing: pptViewed && myRole !== "attendee"
    })
    /// We present PowerPoint Live.
    readonly property bool pptPresenting: !!contentState.mine && !!contentState.mine.content && contentState.mine.content.type === "ppt"
    /// We view someone's PowerPoint Live (the stage shows it, not ours).
    readonly property bool pptViewed: !pptPresenting && !!contentSession && !contentSession.mine && !!contentSession.content && contentSession.content.type === "ppt"
    /// A town hall or webinar (Backend call_event_json): its green room,
    /// live state, Manage what attendees see and Q&A
    /// (docs/spec/town-halls-and-webinars.md).
    readonly property var liveEvent: backend.callEventJson ? JSON.parse(backend.callEventJson) : ({})
    /// Watching a town hall as its attendee (Backend call_stream_json):
    /// {lobby, url, player}.
    readonly property var streamState: backend.callStreamJson ? JSON.parse(backend.callStreamJson) : ({})
    readonly property bool streaming: backend.callStreamJson !== ""
    /// Teams' isEvent: a town hall or webinar says "event" (End event).
    readonly property bool isEvent: !!liveEvent.townHall || !!liveEvent.webinar
    /// Manage what attendees see is on (HostMode) and you manage the
    /// screen: Teams' managed-mode stage (measured in Teams desktop
    /// 2026-11-18, a town hall's green room): the "Manage screen" panel on
    /// the left (240 wide) with the people off screen, and on the stage
    /// only who and what is on screen.
    readonly property bool manageScreen: meeting && !!liveEvent.managed && !streaming && myRole !== "" && myRole !== "attendee"
    /// Who is on screen for attendees (spotlighted), you as your tile.
    readonly property var onScreen: spotlighted.map(p => p.id === selfId ? Object.assign({}, selfEntry, { spotlight: p.spotlight }) : p)
    /// The Manage screen panel's filter: "All", "Live", "People" or
    /// "Content".
    property string manageFilter: "All"
    function manageFilterLabel(k) { return ({ All: qsTr("All"), Live: qsTr("Live"), People: qsTr("People"), Content: qsTr("Content") })[k] || k }
    /// "On with preview" (Manage what attendees see: AdvancedHostMode)
    /// and you manage the screen: Teams' production view (measured in
    /// Teams desktop 2026-11-19): the Preview and Live stages side by side,
    /// Send live under the Preview, the Manage screen strip along the
    /// bottom with an "Add to preview" switch on each tile.
    readonly property bool previewMode: manageScreen && !!liveEvent.preview
    /// The preview's sources (Teams keeps the preview on the producer's
    /// side until Send live): {id, participantId, endpointId, modality}.
    property var previewSources: []
    /// What is live for attendees (the conversation's production layout).
    readonly property var liveSources: liveEvent.layout && liveEvent.layout.participants ? liveEvent.layout.participants : []
    /// An attendee of a webinar with "On with preview": the stage shows
    /// only what was sent live (Teams renders the production layout).
    readonly property bool liveOnly: meeting && !!liveEvent.preview && !manageScreen && !streaming && myRole === "attendee"
    /// The stage shows only who is on screen (managing it, or watching
    /// the live layout).
    readonly property bool stageOnly: manageScreen || liveOnly
    readonly property var shownOnly: liveOnly ? sourcePeople(liveSources) : onScreen
    /// A layout's sources as tiles (you as your own tile).
    function sourcePeople(list) {
        const out = []
        for (const s of list) {
            if (s.modality && s.modality !== "VIDEO") continue
            const p = s.id === selfId ? selfEntry : roster.find(r => r.id === s.id)
            if (p) out.push(p)
        }
        return out
    }
    /// Add someone to the preview or take them off it (the tile's switch).
    function togglePreview(p, on) {
        const id = p.self ? selfId : p.id
        const rest = previewSources.filter(s => s.id !== id)
        if (!on) { previewSources = rest; return }
        const r = roster.find(x => x.id === id) || {}
        previewSources = rest.concat([{ id: id, participantId: r.participant_id || "", endpointId: r.endpoint_id || "", modality: "VIDEO" }])
    }
    /// Send live: the preview becomes what attendees see.
    function sendLive() { backend.sendLive(JSON.stringify(previewSources)) }
    /// Teams' production view, for the harness.
    function previewForTest() {
        return { preview: previewSources.map(s => s.id), live: liveSources.map(s => s.id), busy: liveEvent.busy || "", failed: liveEvent.failed || "" }
    }
    /// Teams' enableTownhallDelayMessage: on in Teams desktop (measured
    /// 2026-11-18: a town hall streaming to its attendees says "Start
    /// event", "Start the event for everyone?" and "1 attendee will enter
    /// and watch the event at a slight delay."); webinars keep "Start
    /// meeting".
    readonly property bool townhallDelayMessage: true
    /// Attendees in the meeting (Teams counts its attendees and streaming
    /// attendees for the LIVE pill and Start's confirmation).
    readonly property int attendeeCount: roster.filter(p => p.active !== false && (p.role || "").toLowerCase() === "attendee").length
    property bool greenRoomAlertClosed: false
    /// Teams' Q&A page for this meeting: its id ("0#{thread}#0", base64)
    /// in a TeamsMeeting reference, with the tenant, call and template.
    function qnaUrl() {
        const mid = Qt.btoa("0#" + backend.callThreadId + "#0")
        const ref = Qt.btoa(JSON.stringify({ _type: "TeamsMeeting", id: mid })).replace(/=+$/, "")
        const g = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16) })
        return "https://web.yammer.com/teamsmeeting/teams-meeting/" + ref + "?client=teams&qnaAppType=native&meetingTenantId=" + encodeURIComponent(backend.tenantId() || "")
            + (liveEvent.townHall ? "&meetingTemplate=Townhall" : liveEvent.webinar ? "&meetingTemplate=Webinar" : "") + "&appSessionId=" + g
    }
    /// Teams' phone audio for the meeting (Backend call_phone_json).
    readonly property var phone: backend.callPhoneJson ? JSON.parse(backend.callPhoneJson) : ({})
    /// Teams' "Use phone for audio" (after joining with Phone audio, More ▸
    /// Call me).
    function openPhoneAudio() { phoneDialog.open() }
    function phoneDialogForTest() { return phoneDialog }
    PhoneAudioDialog {
        id: phoneDialog
        anchors.fill: parent
        phone: win.phone
    }
    /// More ▸ Facilitator ▸: Turn on / Turn off Facilitator, Enable /
    /// Disable voice (Teams' FacilitatorButton menu, measured 2026-11-16).
    readonly property var facilitatorItems: [
        { name: "FacilitatorToggle", label: aiFacilitator ? qsTr("Turn off %1", "calling:k2hy66cyv").arg("Facilitator") : qsTr("Turn on %1", "calling:k4o9pjbg6").arg("Facilitator"), icon: "ai-facilitator", enabled: organizer },
        { name: "FacilitatorVoice", label: backend.callAiFacilitatorVoice ? qsTr("Disable voice") : qsTr("Enable voice"), icon: "sound-wave-circle-20", enabled: aiFacilitator && organizer }
    ]
    function facilitatorAction(name) {
        if (name === "FacilitatorToggle") {
            if (aiFacilitator) { backend.meetingAction("facilitatorOff"); return }
            backend.meetingAction("facilitatorOn")
            // Facilitator works from the transcript: Teams asks to start it.
            if (!transcribing) { facilitatorAsk = true; copilotAsk.visible = true }
        } else if (name === "FacilitatorVoice") backend.meetingAction(backend.callAiFacilitatorVoice ? "facilitatorVoiceOff" : "facilitatorVoiceOn")
    }
    // Interpreter (Teams' AiInterpretationButtonForAll in More ▸ Language
    // and speech): shown when we may turn it on, or while it is on; with
    // Teams' enableAiInterpretationTurnOnOpensSettingsDialog, Turn on opens
    // the settings first. In a group: Turn off for me, Turn off for all
    // (organizer), Interpreter settings.
    readonly property var interpreter: backend.callInterpreterJson ? JSON.parse(backend.callInterpreterJson) : ({})
    readonly property bool interpreterInGroup: !!interpreter.myGroup
    readonly property bool interpreterShown: meeting && !e2ee && (!!interpreter.available || !!interpreter.on)
    readonly property var interpreterItems: interpreterInGroup
        ? [{ name: "InterpreterOffForMe", label: qsTr("Turn off for me"), icon: "sound-wave-circle-sparkle-20" }]
          .concat(organizer ? [{ name: "InterpreterOffForAll", label: qsTr("Turn off for all"), icon: "sound-wave-circle-sparkle-20" }] : [])
          .concat([{ name: "InterpreterSettings", label: qsTr("Interpreter settings"), icon: "settings-20" }])
        : (organizer && interpreter.on ? [{ name: "InterpreterOffForAll", label: qsTr("Turn off for all"), icon: "sound-wave-circle-sparkle-20" }, { name: "InterpreterSettings", label: qsTr("Interpreter settings"), icon: "settings-20" }] : [])
    function interpreterAction(name) {
        if (name === "AiInterpretationButtonForAll" || name === "InterpreterTurnOn") {
            if (interpreterConsecutive) interpreterOffAsk.open()
            else interpreterMode.show()
        }
        else if (name === "InterpreterSettings") interpreterDialog.show(false)
        else if (name === "InterpreterOffForMe") backend.interpreterAction("offForMe", "{}")
        else if (name === "InterpreterOffForAll") interpreterOffAsk.open()
    }
    AiInterpreterDialog {
        id: interpreterDialog
        state_: win.interpreter
        onConfirmed: (language, voice, balance) => backend.interpreterAction(setup ? "turnOn" : "save", JSON.stringify({ language: language, voice: voice, balance: balance }))
    }
    ConfirmDialog {
        id: interpreterOffAsk
        title: qsTr("Turn off Interpreter for all?")
        body: qsTr("This will turn off Interpreter for everyone.")
        confirmText: qsTr("Turn off")
        onConfirmed: backend.interpreterAction("offForAll", "{}")
    }
    // Consecutive interpretation is on for everyone (organizer); the mode
    // step comes first, as Teams' new Interpreter controls.
    AiInterpreterModeDialog {
        id: interpreterMode
        languages: (win.interpreter.languages || []).slice().sort((a, b) => a.name.localeCompare(b.name))
        canConsecutive: win.organizer
        onConsecutive: (first, second) => backend.interpreterAction("turnOnConsecutive", JSON.stringify({ first: first, second: second }))
        onSimultaneous: interpreterDialog.show(true)
    }
    readonly property bool interpreterConsecutive: !!interpreter.consecutive
    /// People listening in a language group (others in the roster's groups
    /// and us), as the indicator counts them.
    readonly property int interpreterListeners: interpreter.listeners || 0
    readonly property int interpreterOthers: Math.max(0, interpreterListeners - (interpreterInGroup ? 1 : 0))
    readonly property bool interpreterIndicator: (!!interpreter.on && interpreterListeners > 0) || interpreterConsecutive
    readonly property string interpreterLanguageName: ((interpreter.languages || []).find(l => l.code === interpreter.myLanguage) || {}).name || ""
    readonly property string interpreterTip: interpreterConsecutive && interpreter.paused ? qsTr("Interpreter is paused") : qsTr("AI is interpreting this meeting")
    // Teams' Interpreter alerts: "AI is interpreting for others" (licensed,
    // not listening), "Interpreter has been turned off", and "Something
    // went wrong with Interpreter".
    property string interpreterAlert: ""
    property bool interpreterOthersShown: false
    property bool interpreterWasOn: false
    onInterpreterChanged: {
        const on = !!interpreter.on || interpreterConsecutive
        if (interpreterWasOn && !on) interpreterAlert = "off"
        else if (on && !interpreterInGroup && !interpreterConsecutive && !!interpreter.available && interpreterListeners > 0 && !interpreterOthersShown) { interpreterOthersShown = true; interpreterAlert = "others" }
        else if (interpreter.error) interpreterAlert = "failed"
        interpreterWasOn = on
    }
    onInterpreterAlertChanged: {
        if (interpreterAlert === "others") showBreakoutAlert(qsTr("AI is interpreting for others") + " · " + qsTr("People are using Interpreter. You can turn it on to listen in your preferred language."), "sound-wave-circle-sparkle-20")
        else if (interpreterAlert === "off") showBreakoutAlert(qsTr("Interpreter has been turned off"), "sound-wave-circle-sparkle-20")
        else if (interpreterAlert === "failed") showBreakoutAlert(qsTr("Something went wrong with Interpreter") + " · " + qsTr("Try turning Interpreter on again."), "alert-warning-16-filled")
        interpreterAlert = ""
    }
    TextMetrics { id: resumeMetrics; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; text: qsTr("Resume") }
    // Each control's slot (button 48 + 4 either side; split buttons 74).
    TextMetrics { id: joinRoomMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: qsTr("Join room") }
    TextMetrics { id: returnMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: qsTr("Return") }
    TextMetrics { id: startEventMetrics; font.family: theme.font; font.pixelSize: 11; text: win.startLabel }
    TextMetrics { id: endEventMetrics; font.family: theme.font; font.pixelSize: 11; text: win.endLabel }
    /// The green room's buttons (Teams' StagingRoomStartMeetingButton,
    /// "Start meeting" unless enableTownhallDelayMessage; End event for
    /// town halls and webinars, else End meeting).
    readonly property string startLabel: townhallDelayMessage && !!liveEvent.streaming ? qsTr("Start event") : qsTr("Start meeting")
    readonly property string endLabel: isEvent ? qsTr("End event") : qsTr("End meeting")
    // The compact bar: 32 px buttons in 36 px slots, split buttons 54.
    readonly property real ubarButton: compactBar ? 36 : 56
    readonly property real ubarDivider: compactBar ? 9 : 17
    readonly property var ubarWidths: ({ MicrophoneButton: compactBar ? 54 : 74, VideoButton: compactBar ? 54 : 74,
                                         ResumeButton: Math.ceil(resumeMetrics.advanceWidth) + 20 + 8 + 40 + 8,
                                         ReturnToBreakoutRoomButton: Math.ceil(joinRoomMetrics.advanceWidth) + 24.67 + 16,
                                         BreakoutRoomReturnToMainButton: Math.ceil(returnMetrics.advanceWidth) + 24.67 + 16,
                                         StagingRoomStartMeetingButton: Math.max(48, Math.ceil(startEventMetrics.advanceWidth) + 1.33) + 8,
                                         StagingRoomEndMeetingButton: Math.max(48, Math.ceil(endEventMetrics.advanceWidth) + 1.33) + 8,
                                         // Teams' "Stop sharing" (62 wide) and PowerPoint Live's Layout + Stop sharing.
                                         WhiteboardControlsSection: 70, PptControlsSection: pptViewed ? 60 : 126,
                                         default: ubarButton })
    // The middle slot's room: from 4 past the indicators (shield, timer)
    // to 17 before Leave; the new controls' slot ends 4 before the end
    // slot and centres its controls.
    readonly property real ubarStart: streaming ? liveIndicator.x + (liveIndicator.visible ? liveIndicator.width : 0) + 12
                                      : timerText.x + timerText.implicitWidth + (compactBar ? 2.7 : 6.67) + 4
    readonly property real ubarRoom: newControls ? leaveGroup.x - 4 - ubarStart : leaveGroup.x - 17 - ubarStart
    readonly property var ubar: JSON.parse(backend.ubarArrange(JSON.stringify(ubarFacts), JSON.stringify(ubarWidths), ubarDivider,
                                                               ubarRoom - 10) || '{"bar":[],"end":[],"overflowed":[],"more":[],"onHold":[],"movable":[]}')
    /// Teams disables what isn't marked usable on hold.
    function holdOk(name) { return !held || ubar.onHold.indexOf(name) >= 0 }
    property var barItems: ({})
    function registerBarItem(name, item) { barItems[name] = item }
    /// The control on the bar, or More when it has overflowed.
    function barItem(name) {
        const n = ubar.bar.indexOf(name) >= 0 ? name : "MoreButton"
        return barItems[n] || bar
    }
    function barComponent(name) {
        return ({
            PopoutContentButton: cPopout, ResumeButton: cResume, CallTransferButtonV2: cTransfer,
            CallConsultativeTransferButtonV2: cConsult, DialpadButton: cDialpad, HoldButton: cHold,
            ChatButton: cChat, RosterButton: cPeople, MeetingCollabButton: cCopilot, RaiseHandsButton: cRaise, ReactionButton: cReact,
            ViewModeButton: cView, OrganizerControlButton: cControls, MeetingDetailsButton: cNotes,
            StartBreakoutRoomButton: cRooms, MeetingAppsAddButton: cApps, MoreButton: cMore,
            ReturnToBreakoutRoomButton: cJoinRoom, BreakoutRoomReturnToMainButton: cReturnMain,
            StagingRoomStartMeetingButton: cStartEvent, StagingRoomEndMeetingButton: cEndEvent, YammerQnaButton: cQna,
            VideoButton: cCamera, MicrophoneButton: cMic, ShareButton: cShare,
            // More's grid controls the user pinned to the bar.
            RecordingButton: cPinned, TranscriptButton: cPinned, MeetingFacilitatorTimerButton: cPinned,
            ClosedCaptionsButton: cPinned, RealTimeTextButton: cPinned,
            ScreensharingControlButton: cTakeControl,
            WhiteboardControlsSection: cContentStop, PptControlsSection: cPptControls
        })[name] || null
    }
    // What each control does, from the bar or from More.
    function runControl(name) {
        if (name === "ChatButton") { side = side === "chat" ? "" : "chat"; if (side === "chat") openChat() }
        else if (name === "RosterButton") side = side === "people" ? "" : "people"
        else if (name === "MeetingCollabButton") openCopilot()
        else if (name === "RaiseHandsButton") toggleHand()
        else if (name === "ReactionButton") { if (reactMenu.visible) reactMenu.close(); else { reactMenu.parent = barItem(name); reactMenu.open() } }
        else if (["RecordingButton", "TranscriptButton", "ClosedCaptionsButton", "RealTimeTextButton"].indexOf(name) >= 0) recordControl(name)
        else if (name === "ViewModeButton") { viewMenu.parent = barItem(name); viewMenu.open() }
        else if (name === "OrganizerControlButton") { loadControls(); controlsMenu.open() }
        // Notes: the meeting's notes as a Loop page in the side pane.
        else if (name === "MeetingDetailsButton") { side = side === "notes" ? "" : "notes"; if (side === "notes") meetingNotesPane.open() }
        else if (name === "MeetingAppsAddButton") { appsMenu.parent = barItem(name); appsMenu.open() }
        else if (name === "MoreButton") {
            if (newControls) { if (newMore.visible) newMore.close(); else newMore.openAt(barItem(name)) }
            else { moreMenu.parent = barItem(name); moreMenu.open() }
        }
        else if (name === "VideoButton") toggleCamera()
        else if (name === "MicrophoneButton") toggleMute()
        else if (name === "ShareButton") {
            // Teams: Share opens the share tray; while sharing it stops.
            if (sharing) toggleShare()
            else if (shareTray.visible) shareTray.close()
            else openShareTray()
        }
        else if (name === "PopoutContentButton") contentPoppedOut = true
        // Stop sharing a Whiteboard (Teams' whiteboard-sharing-controls);
        // PowerPoint Live asks first ("Stop presenting?").
        else if (name === "WhiteboardControlsSection") backend.contentShareStop()
        // A viewer's Take control takes the presentation over at once.
        else if (name === "PptControlsSection") {
            if (pptViewed) backend.contentTakeControl(contentSession.correlationId)
            else stopPresentingDialog.open()
        }
        else if (name === "ScreensharingControlButton") {
            // Teams' viewer button: Take control (asks first), Stop control.
            if (controlState.state === "controlling") screenControl("release", "")
            else if (controlState.state !== "requested") requestControlDialog.open()
        }
        else if (name === "CallTransferButtonV2" || name === "CallConsultativeTransferButtonV2") {
            picker.mode = name === "CallTransferButtonV2" ? "transfer" : "consult"
            picker.parent = barItem(name); picker.open()
        }
        else if (name === "DialpadButton") { if (dialPad.visible) dialPad.close(); else { dialPad.parent = barItem(name); dialPad.open() } }
        else if (name === "HoldButton" || name === "ResumeButton") toggleHold()
        else if (name === "CallParkButton") parkCall()
        else if (name === "CameraEffectsButton") side = side === "video" ? "" : "video"
        else if (name === "AudioSettingsButton" || name === "DeviceSettingsButton") side = side === "audio" ? "" : "audio"
        else if (name === "MeetingInfoButton") { side = side === "info" ? "" : "info"; if (side === "info") loadMeetingInfo() }
        else if (name === "PstnButton") openPhoneAudio()
        else if (name === "MeetingHelpButton") { helpWindow.show(); helpWindow.raise(); helpWindow.requestActivate() }
        else if (name === "ReportMeetingButton") openMeetingReport()
        else if (name === "MeetingFacilitatorTimerButton") toggleTimer()
        else if (name === "StartBreakoutRoomButton") { side = side === "rooms" ? "" : "rooms"; if (side === "rooms") backend.breakoutAction("refresh", "{}") }
        else if (name === "ReturnToBreakoutRoomButton") joinBreakoutRoom()
        else if (name === "BreakoutRoomReturnToMainButton") returnToMainMeeting()
        else if (name === "StagingRoomStartMeetingButton") { if (!liveEvent.busy) startEventDialog.open() }
        else if (name === "StagingRoomEndMeetingButton") { if (!liveEvent.busy) endEventDialog.open() }
        else if (name === "YammerQnaButton") side = side === "qna" ? "" : "qna"
    }
    function controlEnabled(name) {
        if (!holdOk(name)) return false
        if (["RaiseHandsButton", "ReactionButton", "CallTransferButtonV2", "CallConsultativeTransferButtonV2"].indexOf(name) >= 0) return live
        if (name === "OrganizerControlButton") return optionsUrl.length > 0
        if (name === "MeetingDetailsButton") return chatUrl.length > 0
        if (name === "StartBreakoutRoomButton") return live
        if (name === "VideoButton") return canVideo
        if (name === "MicrophoneButton") return hasAudio
        if (name === "ShareButton") return canShare || sharing
        if (name === "DialpadButton") return live && canDtmf
        if (name === "HoldButton") return live && hasAudio
        if (name === "RealTimeTextButton") return !rttOn
        // Waiting for approval; or the sharer's company turned it off.
        if (name === "ScreensharingControlButton") return controlState.state !== "requested" && !controlState.deniedBySharer
        // Copilot off in the meeting's options (copilotMode Disabled).
        if (name === "MeetingCollabButton") return live && aiAvailable
        return true
    }
    // An overflowed control in More, as Teams names it there (the menu
    // uses the control's title, else its label).
    function overflowItem(name) {
        const m = {
            ChatButton: { label: qsTr("Chat"), icon: "call-chat", checked: side === "chat" },
            RosterButton: { label: side === "people" ? qsTr("Hide people") : qsTr("People"), icon: "call-people", checked: side === "people" },
            RaiseHandsButton: { label: handRaised ? qsTr("Lower hand") : qsTr("Raise hand"), icon: "call-raise" },
            ReactionButton: { label: qsTr("Send a reaction"), icon: "call-react" },
            ViewModeButton: { label: qsTr("View"), icon: "call-view", chevron: true },
            OrganizerControlButton: { label: qsTr("Controls"), icon: "call-controls", chevron: true },
            MeetingDetailsButton: { label: side === "notes" ? qsTr("Close notes") : qsTr("Open notes"), icon: "call-notes", checked: side === "notes" },
            StartBreakoutRoomButton: { label: qsTr("Breakout rooms"), icon: "call-rooms" },
            MeetingAppsAddButton: { label: qsTr("Get more apps and agents"), icon: "call-apps" },
            PopoutContentButton: { label: qsTr("Pop out"), icon: "call-popout" },
            CallTransferButtonV2: { label: qsTr("Transfer"), icon: "call-transfer" },
            CallConsultativeTransferButtonV2: { label: qsTr("Consult then transfer"), icon: "consult" },
            DialpadButton: { label: qsTr("Dial pad"), icon: "dialpad" },
            HoldButton: { label: qsTr("Hold"), icon: "pause" },
            ResumeButton: { label: qsTr("Resume"), icon: "play-20" }
        }[name]
        if (!m) return null
        m.name = name
        m.enabled = controlEnabled(name)
        return m
    }
    // More's own rows (Teams' labels and icons); Record and transcribe
    // follows the recorder's state.
    readonly property bool transcribing: recordingState === "Transcribing" || recordingState === "RecordingAndTranscribing"
    readonly property bool recording: recordingState === "Recording" || recordingState === "RecordingAndTranscribing"
    function moreLabel(n) {
        if (n === "MeetingInfoButton") return { label: qsTr("Meeting info"), icon: "info-20" }
        // Teams' PstnButton ("Call me", the Call glyph).
        if (n === "PstnButton") return { label: qsTr("Call me"), icon: "call-20", enabled: live }
        // Teams' FacilitatorButton: its glyph in brand while Facilitator is on.
        if (n === "FacilitatorButton") return { label: qsTr("Facilitator"), icon: "ai-facilitator", iconColor: aiFacilitator ? theme.brand : undefined }
        if (n === "CameraEffectsButton") return { label: qsTr("Video effects and settings"), icon: "video-background-effect-20" }
        if (n === "AudioSettingsButton") return { label: qsTr("Audio settings"), icon: "speaker-settings-20" }
        // A town hall attendee's More (Teams' DeviceSettingsButton).
        if (n === "DeviceSettingsButton") return { label: qsTr("Device settings"), icon: "speaker-settings-20" }
        if (n === "RecordingMenuControl") return { label: qsTr("Record and transcribe"), icon: "record-20" }
        if (n === "RecordingButton") return recording
            ? { label: qsTr("Stop recording"), icon: "record-stop-20", tip: qsTr("Stop recording and transcription") }
            : { label: qsTr("Start recording"), icon: "record-20", tip: transcribing ? qsTr("Start recording only") : qsTr("Start recording and transcription") }
        if (n === "TranscriptButton") return transcribing
            ? { label: qsTr("Stop transcription"), icon: "call-transcript-stop-20" }
            : { label: qsTr("Start transcription"), icon: "call-transcript-20" }
        if (n === "LanguageSpeechMenuControl") return { label: qsTr("Language and speech"), icon: "local-language-20" }
        if (n === "AiInterpretationButtonForAll") {
            if (!interpreterShown) return null
            const row = { label: qsTr("Interpreter"), icon: "sound-wave-circle-sparkle-20", endCheck: interpreterInGroup }
            if (interpreterItems.length > 0) row.submenu = interpreterItems
            return row
        }
        if (n === "SettingsMenuControl") return { label: qsTr("Settings"), icon: "settings-20" }
        if (n === "AccessibilitySettingsButton") return { label: qsTr("Accessibility settings"), icon: "accessibility-20" }
        // Teams toggles the pane (toggle_call_health_on/off).
        if (n === "CallHealth") return { label: side === "callHealth" ? qsTr("Hide call health") : qsTr("Call health"), icon: "pulse-20" }
        if (n === "ChatBubblesButton") return chatBubblesSuppressed
            ? { label: qsTr("Show chat bubbles"), icon: "chat-bubbles-20" }
            : { label: qsTr("Don't show chat bubbles"), icon: "chat-bubbles-off-20" }
        if (n === "MeetingHelpButton") return { label: qsTr("Help"), icon: "question-circle-20" }
        if (n === "ReportMeetingButton") return { label: qsTr("Report a concern"), icon: "shield-error-20" }
        if (n === "CallParkButton") return { label: qsTr("Park Call"), icon: "call-park-20" }
        if (n === "MeetingFacilitatorTimerButton") return timerCanView
            ? { label: qsTr("Timer"), icon: "timer-20", endCheck: timerVisible } : null
        if (n === "MuteNotificationsButton") return notificationsMuted
            ? { label: qsTr("Allow notifications"), icon: "alert-20" }
            : { label: qsTr("Mute notifications"), icon: "alert-off-20" }
        if (n === "ClosedCaptionsButton") return {
            label: captionsOn ? qsTr("Hide live captions") : qsTr("Show live captions"),
            icon: "closed-caption-20", keys: "Alt+Shift+C", endCheck: captionsOn }
        // Once on, RTT stays on for the call (Teams greys it, checked).
        if (n === "RealTimeTextButton") return {
            label: qsTr("Turn on RTT for this call"), icon: "real-time-text-20",
            endCheck: rttOn, enabled: !rttOn }
        // Once a transcript has run in the meeting: show or hide its pane.
        if (n === "TranscriptPanelButton") return transcriptStarted
            ? { label: side === "transcript" ? qsTr("Hide transcript") : qsTr("Show transcript"),
                icon: "transcript-panel-20", endCheck: side === "transcript" }
            : null
        return null
    }
    // A menu control's sections as one list (a divider after a section of
    // more than one, as More's own).
    function submenuOf(item) {
        const secs = (item.sections || []).map(sec => sec.items.filter(i => !!moreLabel(i.name)))
                                         .filter(sec => sec.length > 0)
        const out = []
        secs.forEach((sec, i) => {
            sec.forEach(i2 => out.push(Object.assign({ name: i2.name }, moreLabel(i2.name))))
            if (i < secs.length - 1 && sec.length > 1) out.push({ separator: true })
        })
        return out
    }
    /// More's rows: what overflowed, a divider, then More's own sections
    /// (a section of one merges into the next, as on the bar); a menu
    /// control carries its items as a submenu.
    readonly property var barMoreItems: {
        const out = []
        for (const n of ubar.overflowed) { const it = overflowItem(n); if (it) out.push(it) }
        const sections = ubar.more.map(sec => sec.items.filter(i => !!moreLabel(i.name) && (!i.sections || submenuOf(i).length > 0)))
                                  .filter(sec => sec.length > 0)
        if (out.length > 0 && sections.length > 0) out.push({ separator: true })
        sections.forEach((sec, i) => {
            sec.forEach(it => {
                const row = Object.assign({ name: it.name }, moreLabel(it.name))
                if (it.sections) row.submenu = submenuOf(it)
                if (it.name === "FacilitatorButton") row.submenu = facilitatorItems
                out.push(row)
            })
            if (i < sections.length - 1 && sec.length > 1) out.push({ separator: true })
        })
        return out
    }
    // Record and transcribe: the starts ask first, as Teams.
    signal recorderCommand(string command, string language, bool audioOnly)
    RecordStartDialog {
        id: recordStart
        onConfirmed: (language, audioOnly) => {
            // Teams opens the Transcript pane for whoever starts it.
            if (mode !== "recording" && mode !== "copilot" && !win.copilotAfterTranscript) win.openTranscriptWhenStarted = true
            win.recorderCommand(mode === "copilot" ? "startCopilot" : mode === "transcription" ? "startTranscription" : "startRecording", language, audioOnly)
        }
    }
    // The Transcript pane: its rows, and asking for the stored ones.
    property var transcript: []
    // Live captions (Language and speech ▸ Show live captions).
    property bool captionsOn: false
    property var captions: []
    property string captionsLanguage: "en-us"
    /// Teams' calling accessibility settings ({startCaptionsAutomatically,
    /// profanityFilterEnabled, …}).
    property var accessibility: ({})
    /// Caption styles ({fontColor, backgroundColor, fontSize,
    /// captionHeight, captionsPosition}), kept on this device.
    property var captionStyles: ({})
    signal setCaptions(bool on)
    signal setCaptionsLanguage(string code)
    /// Real-time text (Language and speech ▸ Turn on RTT for this call).
    property bool rttOn: false
    property bool rttInitiator: false
    property string privacyUrl: ""
    signal startRtt()
    ConfirmDialog {
        id: rttAsk
        stacked: true
        title: qsTr("RTT")
        body: qsTr("RTT (real-time text) will be turned on for everyone in the call.")
        confirmText: qsTr("Turn on")
        onConfirmed: win.startRtt()
    }
    function rttAskForTest() { return rttAsk }
    signal updateAccessibility(string patch)
    signal saveCaptionStyles(var styles)
    /// The 'You're muted' notice while you speak muted (Accessibility ▸
    /// Muted notification; kept on this device).
    property bool showMutedNotice: true
    /// More ▸ Settings ▸ Don't show chat bubbles (for this call).
    property bool chatBubblesSuppressed: false
    signal setChatBubblesSuppressed(bool on)
    // Someone else's message in the call's chat: Teams' bubble, unless the
    // chat is open or bubbles are off.
    function showChatBubble(mri, name, text) {
        if (chatBubblesSuppressed || side === "chat") return
        const p = people.find(x => (x.id || "").toLowerCase() === (mri || "").toLowerCase())
        chatBubble.show({ mri: mri, name: p && p.name ? p.name : name, text: text,
                          guest: p ? !!p.guest : (mri || "").startsWith("8:teamsvisitor:"),
                          // Teams badges the avatar; a guest's presence is unknown.
                          presence: p && p.presence ? p.presence : "Unknown" })
    }
    /// More ▸ Settings ▸ Mute notifications (for this call).
    property bool notificationsMuted: false
    signal setNotificationsMuted(bool on)
    signal setShowMutedNotice(bool on)
    readonly property bool captionsAtTop: captionStyles.captionsPosition === "Top"
    readonly property var spokenLanguages: recordStart.languages.map(l => ({ code: l[0], name: l[1] }))
    function languageName(code) {
        const l = recordStart.languages.find(x => x[0] === code)
        return l ? l[1] : qsTr("English (US)")
    }
    function openCaptionSettings(anchor) {
        if (captionsWindow.overflow) {
            captionsOverflow.parent = anchor
            captionsOverflow.x = anchor.width - captionsOverflow.implicitWidth
            captionsOverflow.y = captionsAtTop ? anchor.height + 4 : -captionsOverflow.implicitHeight - 4
            captionsOverflow.open()
            return
        }
        showCaptionSettings(anchor)
    }
    function showCaptionSettings(anchor) {
        captionSettings.parent = anchor
        captionSettings.x = anchor.width - captionSettings.implicitWidth
        captionSettings.y = captionsAtTop ? anchor.height + 4 : -captionSettings.implicitHeight - 4
        captionSettings.open()
    }
    signal loadTranscript()
    property bool openTranscriptWhenStarted: false
    // ---- Copilot in the meeting (TASK-0188; measured on winpc 2026-11-16,
    // docs/spec/call-and-meeting-window.md §1.8j) ----
    // For a user with a Copilot licence Teams' bar has Copilot
    // (meeting-collab-button, "Open Copilot (Alt+C)"). Without the
    // meeting's transcript it first asks to start it (the calling alert
    // "Start transcription to use Copilot", Cancel / Start: Start runs
    // Teams' spoken-language confirmation, starts the transcript and
    // opens the pane). The pane (320 wide) is Teams' header — the Copilot
    // mark, "Copilot" 14/600, Close Copilot — over the Microsoft 365
    // Copilot app as a TeamsJS side panel (api::meeting_copilot): OST
    // hosts it as Teams does and tells it the meeting
    // (contextualChatChanged, again when the transcript starts or stops).
    property bool copilotAllowed: false
    property var copilotLaunch: null
    property bool copilotAfterTranscript: false
    readonly property bool copilotShown: side === "copilot"
    // With the meeting's Copilot "Only during the meeting" Teams asks
    // "Turn on Copilot for everyone?" (Cancel / Turn on) instead; Turn on
    // asks the spoken language, then starts Copilot alone (no transcript
    // is kept) and opens the pane (Teams' copilot-ufd-control, read
    // 2026-11-18).
    // In a call (1:1 or a chat's group call: Teams' calling scenario) it
    // asks "Turn on Copilot for everyone in this call?" instead, with Just
    // Copilot (Copilot alone) and Transcribe (the transcript), and without
    // a transcript the text names the call ("…from Copilot in the call.").
    property bool copilotTurnOnAsk: false
    readonly property bool callingScenario: !scheduled && !adhocMeeting
    readonly property bool copilotOrTranscript: transcribing || copilotRunning
    // Measured live in Teams desktop (2026-11-18, ost-test1 with Allow
    // Copilot "Only during the meeting"): in a meeting Teams asks nothing
    // more (its "Turn on Copilot for everyone?" needs the
    // enableToggleCopilotDuringMeeting flag, off here): Copilot goes
    // straight to the spoken-language question, then runs alone. In the
    // test call, which can't be transcribed, the pane opens at once.
    function openCopilot() {
        if (side === "copilot") { side = ""; return }
        if (!copilotOrTranscript && !copilotAsk.visible && !testCall) {
            facilitatorAsk = false
            copilotTurnOnAsk = copilotOnly
            if (copilotOnly && !callingScenario) { copilotAfterTranscript = true; recordStart.ask("copilot"); return }
            copilotAsk.visible = true
            return
        }
        copilotAsk.visible = false
        side = "copilot"
        if (!copilotLaunch) backend.meetingCopilotLaunch(copilotHostTheme)
    }
    readonly property string copilotHostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    function sendCopilotContext() {
        if (!copilotLaunch || !copilotLoader.item) return
        const chat = JSON.parse(JSON.stringify(copilotLaunch.contextualChat))
        // Teams: running while either transcript runs; kept only for the
        // meeting while Copilot runs alone.
        chat.contentItems[0].meetingContext.isTranscriptRunningDuringMeeting = copilotOrTranscript
        chat.contentItems[0].meetingContext.isTemporaryStorageForMeetingTranscript = copilotRunning && !transcribing
        copilotLoader.item.sendFrameMessage("contextualChatChanged", [chat])
        copilotLoader.item.sendFrameMessage("updateCapabilities", [copilotLaunch.capabilities])
    }
    Connections {
        target: backend
        function onMeetingCopilotReady(json) {
            try { win.copilotLaunch = JSON.parse(json) } catch (e) { win.copilotLaunch = null }
            console.info("COPILOT launch", win.copilotLaunch ? "ready" : "failed")
        }
    }
    Shortcut { sequence: "Alt+C"; enabled: win.live && win.ubar.bar.concat(win.ubar.overflowed).indexOf("MeetingCollabButton") >= 0; onActivated: win.openCopilot() }
    function copilotAskForTest() { return copilotAsk }
    // Start (Turn on in a meeting, Just Copilot in a call).
    function copilotStartForTest() { const turnOn = copilotTurnOnAsk; copilotAsk.visible = false; copilotAfterTranscript = true; recordStart.ask(turnOn ? "copilot" : "transcription") }
    function copilotTurnOnAskForTest() { return copilotTurnOnAsk }
    function recordStartForTest(mode) { recordStart.ask(mode) }
    function copilotEventsForTest() { return copilotLoader.item ? copilotLoader.item.hostEvents : [] }
    // Teams' calling alert (ufd_copilotShowTranscriptUfd): 320 x 136.7,
    // #FAFAFA, radius 8, centred 10.7 under the bar; the Copilot mark (20)
    // and the title (12 px) 12.7 in, Close (16) at the end, the text 14/20
    // #616161 at 40.7, Cancel and Start (143.3 x 31.3) at 92.7.
    // Teams' Facilitator alert is the same card (ufd_groupCopilotShow-
    // TranscriptUfd, measured 2026-11-16: 320 x 138, a #F0F0F0 hairline,
    // the 16 px Facilitator glyph 13 in, the title at 37, Dismiss and
    // Start); Start turns the transcript on after the language question.
    property bool facilitatorAsk: false
    Rectangle {
        id: copilotAsk
        visible: false
        z: 50
        x: (win.width - width) / 2; y: bar.height + 10.7
        width: 320; height: win.facilitatorAsk ? 138 : askText.y + askText.implicitHeight + 12 + 31.3 + 12.7; radius: 8
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        border.width: theme.highContrast || win.facilitatorAsk ? 1 : 0
        border.color: theme.highContrast ? "#FFFFFF" : theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
        Accessible.role: Accessible.AlertMessage
        Accessible.name: askTitle.text
        FluentIcon {
            x: win.facilitatorAsk ? 13 : 12.7; y: win.facilitatorAsk ? 13 : 12.7
            size: win.facilitatorAsk ? 16 : 20
            name: win.facilitatorAsk ? "ai-facilitator" : "ai-copilot"; color: theme.text
        }
        Text {
            id: askTitle
            x: win.facilitatorAsk ? 37 : 40.7; y: win.facilitatorAsk ? 13 : 12.7; height: 20; verticalAlignment: Text.AlignVCenter
            text: win.facilitatorAsk ? qsTr("Start transcription to use %1").arg("Facilitator")
                : win.copilotTurnOnAsk ? (win.callingScenario ? qsTr("Turn on Copilot for everyone in this call?") : qsTr("Turn on Copilot for everyone?"))
                : qsTr("Start transcription to use Copilot")
            font.family: theme.font; font.pixelSize: 12; color: theme.text
        }
        FluentIcon {
            x: 291.3; y: 14.7; size: 16; name: "dismiss-16"; color: closeH.hovered ? theme.text : theme.textSecondary
            HoverHandler { id: closeH; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copilotAsk.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Text {
            id: askText
            x: win.facilitatorAsk ? 13 : 12.7; y: win.facilitatorAsk ? 41 : 40.7; width: 296.7
            text: win.facilitatorAsk ? qsTr("Transcription is required to get help from %1 in this meeting.").arg("Facilitator")
                : win.copilotTurnOnAsk ? (win.callingScenario ? qsTr("Copilot uses the audio, chat, and other content to answer questions. Start transcription to get an AI-generated recap.")
                                                              : qsTr("Copilot uses the audio, chat, and other content to answer questions during the meeting."))
                : win.callingScenario ? qsTr("Transcription is required to get help from Copilot in the call.")
                : qsTr("Transcription is required to get help from Copilot in the meeting.")
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        readonly property bool callChoice: win.copilotTurnOnAsk && !win.facilitatorAsk && win.callingScenario
        readonly property real buttonsY: win.facilitatorAsk ? 93 : askText.y + askText.implicitHeight + 12
        // In a call: Just Copilot (dontStartTranscriptButton) starts Copilot
        // alone; in a meeting: Cancel.
        SettingsParts.Button {
            x: 12.7; y: copilotAsk.buttonsY; width: 143.3
            label: win.facilitatorAsk ? qsTr("Dismiss") : copilotAsk.callChoice ? qsTr("Just Copilot") : qsTr("Cancel")
            onClicked: {
                copilotAsk.visible = false
                if (!copilotAsk.callChoice) return
                win.copilotAfterTranscript = true
                recordStart.ask("copilot")
            }
        }
        SettingsParts.Button {
            x: 164; y: copilotAsk.buttonsY; width: 143.3; primary: true
            label: copilotAsk.callChoice ? qsTr("Transcribe") : win.copilotTurnOnAsk && !win.facilitatorAsk ? qsTr("Turn on") : qsTr("Start")
            onClicked: {
                copilotAsk.visible = false
                if (!win.facilitatorAsk) win.copilotAfterTranscript = true
                recordStart.ask(win.copilotTurnOnAsk && !win.facilitatorAsk && !copilotAsk.callChoice ? "copilot" : "transcription")
            }
        }
    }
    onCopilotRunningChanged: {
        if (copilotLaunch && copilotLoader.item && copilotLoader.item.hostEvents.indexOf("ChatReady") >= 0) sendCopilotContext()
        if (!copilotRunning) { copilotOnNotice.visible = false; return }
        if (copilotAfterTranscript) { copilotAfterTranscript = false; side = "copilot"; if (!copilotLaunch) backend.meetingCopilotLaunch(copilotHostTheme) }
        if (!transcribing) copilotOnNotice.visible = true
        // Its text depends on the meeting's Intelligent recap option.
        if (Object.keys(controlsOptions).length === 0) loadControls()
    }
    // Teams' calling alert once Copilot runs alone (ShowCopilotOnlyMode,
    // the licensed bizChat text): "Copilot is available in this meeting",
    // "Copilot uses your data to generate responses during the meeting.
    // Interactions with Copilot might be retained due to the host
    // organization's policy." and the privacy link; the same card as the
    // transcript alert, without buttons.
    Rectangle {
        id: copilotOnNotice
        visible: false
        z: 50
        x: ((win.width - (sidePane.visible ? sidePane.width : 0)) - width) / 2; y: bar.height + 10.67
        width: 320; height: noticeText.y + noticeText.implicitHeight + 8.67; radius: 8
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        border.width: theme.highContrast ? 1 : 0.67
        border.color: theme.highContrast ? "#FFFFFF" : theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
        Accessible.role: Accessible.AlertMessage
        Accessible.name: qsTr("Copilot is available in this meeting")
        FluentIcon { x: 12.67; y: 12.67; size: 20; name: "sparkle-20"; color: theme.text }
        Text {
            x: 40.67; y: 12.67; height: 20; verticalAlignment: Text.AlignVCenter
            text: qsTr("Copilot is available in this meeting")
            font.family: theme.font; font.pixelSize: 12; color: theme.text
        }
        FluentIcon {
            x: 291.3; y: 14.7; size: 16; name: "dismiss-16"; color: noticeClose.hovered ? theme.text : theme.textSecondary
            HoverHandler { id: noticeClose; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copilotOnNotice.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Text {
            id: noticeText
            x: 12.67; y: 40.67; width: 294.67
            textFormat: Text.StyledText
            // With the meeting's "Start Intelligent Recap when Copilot is
            // turned on" (on unless the organizer turned it off) Teams names
            // the recap too.
            text: (win.controlValue("IsRecapEnabled") !== false
                   ? qsTr("Copilot uses your data to generate responses during the meeting and an Intelligent recap after the meeting. Interactions and summaries with Copilot might be retained due to the host organization’s policy.")
                   : qsTr("Copilot uses your data to generate responses during the meeting. Interactions with Copilot might be retained due to the host organization's policy."))
                  + (win.privacyUrl ? " <a href=\"" + win.privacyUrl + "\">" + qsTr("Privacy policy") + "</a>" : "")
            linkColor: theme.link
            onLinkActivated: link => Qt.openUrlExternally(link)
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
    }
    function copilotNoticeForTest() { return copilotOnNotice }
    // A transcript has run in this meeting (Teams' hasBeenStarted: More
    // then offers Show transcript).
    property bool transcriptRan: false
    readonly property bool transcriptStarted: transcriptRan || transcribing || transcript.length > 0
    onTranscribingChanged: {
        // Copilot is told when the transcript starts or stops; Start in
        // its alert opens the pane once the transcript runs.
        if (copilotLaunch && copilotLoader.item && copilotLoader.item.hostEvents.indexOf("ChatReady") >= 0) sendCopilotContext()
        if (transcribing && copilotAfterTranscript) { copilotAfterTranscript = false; side = "copilot"; if (!copilotLaunch) backend.meetingCopilotLaunch(copilotHostTheme) }
        if (!transcribing) return
        transcriptRan = true
        if (openTranscriptWhenStarted) {
            openTranscriptWhenStarted = false
            if (side !== "transcript") toggleTranscript()
        }
    }
    function toggleTranscript() {
        side = side === "transcript" ? "" : "transcript"
        if (side === "transcript") loadTranscript()
    }
    ConfirmDialog {
        id: stopTranscriptAsk
        title: qsTr("Stop transcription?"); body: ""; confirmText: qsTr("Stop")
        onConfirmed: win.recorderCommand("stopTranscription", "", false)
    }
    ConfirmDialog {
        id: stopRecordingAsk
        title: qsTr("Stop recording and transcription?"); body: ""; confirmText: qsTr("Stop")
        onConfirmed: win.recorderCommand("stopRecording", "", false)
    }
    function recordMenuForTest() {
        moreMenu.parent = barItem("MoreButton") || moreMenu.parent
        moreMenu.open()
        const i = barMoreItems.findIndex(it => it.name === "RecordingMenuControl")
        if (i >= 0) moreMenu.openSubmenuForTest(i)
    }
    function closeMoreForTest() { moreMenu.close() }
    function captionsPopoutForTest() { return captionsPopout }
    function captionsWindowForTest() { return captionsWindow }
    function accessibilityPaneForTest() { return accessibilityPane }
    function meetingReportForTest() { return meetingReport }
    function helpWindowForTest() { return helpWindow }
    function moreSubmenuForTest(name) {
        moreMenu.parent = barItem("MoreButton") || moreMenu.parent
        moreMenu.open()
        const i = barMoreItems.findIndex(it => it.name === name)
        if (i >= 0) moreMenu.openSubmenuForTest(i)
    }
    function captionSettingsForTest() { openCaptionSettings(captionsWindow.settingsAnchorForTest) }
    function closeCaptionSettingsForTest() { captionSettings.close(); captionsOverflow.close() }
    function transcriptScrollTopForTest() { transcriptPane.scrollToTopForTest() }
    function cancelRecordDialogForTest() { recordStart.close() }
    function confirmRecordDialogForTest() {
        if (recordStart.opened) { recordStart.close(); recordStart.confirmed(recordStart.language, recordStart.audioOnly); return true }
        for (const d of [stopTranscriptAsk, stopRecordingAsk])
            if (d.opened) { d.close(); d.confirmed(); return true }
        return false
    }
    function recordControl(name) {
        if (name === "FacilitatorToggle" || name === "FacilitatorVoice") facilitatorAction(name)
        else if (name === "AiInterpretationButtonForAll" || name.indexOf("Interpreter") === 0) interpreterAction(name)
        else if (name === "PstnButton") openPhoneAudio()
        else if (name === "ClosedCaptionsButton") setCaptions(!captionsOn)
        else if (name === "RealTimeTextButton") { if (!rttOn) rttAsk.open() }
        else if (name === "AccessibilitySettingsButton") side = side === "accessibility" ? "" : "accessibility"
        else if (name === "CallHealth") side = side === "callHealth" ? "" : "callHealth"
        else if (name === "ChatBubblesButton") setChatBubblesSuppressed(!chatBubblesSuppressed)
        else if (name === "MuteNotificationsButton") {
            setNotificationsMuted(!notificationsMuted)
            // Teams announces it to screen readers.
            contentItem.Accessible.announce(notificationsMuted ? qsTr("Notifications allowed") : qsTr("Notifications muted"))
        }
        else if (name === "TranscriptPanelButton") toggleTranscript()
        else if (name === "RecordingButton") {
            if (recording) stopRecordingAsk.open()
            else recordStart.ask(transcribing ? "recording" : "recordingAndTranscription")
        } else if (name === "TranscriptButton") {
            if (transcribing) stopTranscriptAsk.open()
            else recordStart.ask("transcription")
        }
    }
    // Teams' alerts when the recorder refuses (10 s, as the lock notices).
    property string recorderFailure: ""
    Timer { id: recorderFailureTimer; interval: 10000; onTriggered: win.recorderFailure = "" }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Meeting bar
    Rectangle {
        id: bar
        // The compact bar (new controls under 480 px): 40 tall.
        width: parent.width; height: win.compactBar ? 40 : 60
        // The new controls' bar is Teams' NeutralBackground1 (#292929 in
        // dark, measured), a step up from the stage's surface.
        color: win.barFill
        // Teams' encryption indicator (E2EEncryptionIndicator, id
        // e2ee-status; measured on winpc 2026-11-17 in a 1:1 call and in
        // meetings): a 30 x 32 button at x 8 with the 20 px Shield (Shield
        // Lock when the call is end-to-end encrypted), then the duration in
        // 14 px #424242 with 6.7 px of padding. Its tooltip is "Encryption
        // status"; a click opens the encryption card under it.
        Item {
            id: encryptionIndicator
            // A town hall's stream has only its state pill (Teams'
            // streamingClient layout).
            visible: !win.streaming
            // Compact: a 22 px indicator with its 14 px glyph.
            x: win.compactBar ? 7 : 8; y: win.compactBar ? 8.7 : 14
            width: win.compactBar ? 22 : 30; height: win.compactBar ? 22 : 32
            FluentIcon {
                anchors.centerIn: parent
                name: win.e2ee ? "shield-keyhole-20" : "call-shield"; size: win.compactBar ? 14 : 20
                color: encHover.hovered || encryptionCard.visible ? theme.brandForeground1 : theme.textStrong
            }
            HoverHandler { id: encHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: encryptionCard.visible ? encryptionCard.close() : encryptionCard.open() }
            IndicatorTip { target: encryptionIndicator; text: qsTr("Encryption status"); shown: encHover.hovered && !encryptionCard.visible }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Encryption status")
            Accessible.onPressAction: encryptionCard.open()
        }
        // The AI indicator (measured in Teams, 2026-11-08): a 37.33 x 32
        // button at x 38 with a 28 x 20 pill (padding 0 4) holding the
        // 20 px sparkle — off: Sparkle Off on the surface in #242424 (brand
        // on hover); on: the filled sparkle in white on the brand pill
        // (BrandBackgroundHover on hover); disabled without AI. It opens
        // the "Meeting AI" menu 13.33 below it.
        // The recording indicator: a 30 x 32 slot after the shield with
        // its 20 px glyph 5 in — the transcript glyph while only the
        // transcript runs, else the recording ring (#424242) round a red
        // (#D13438) dot of radius 4.6.
        Item {
            id: recordingIndicator
            visible: win.meeting && win.recordingState !== "" && !win.streaming
            x: 38; y: 14; width: 30; height: 32
            FluentIcon {
                x: 5; y: 6
                name: win.recordingState === "Transcribing" ? "call-transcript-20" : "call-recording-ring"; size: 20
                color: theme.textStrong
                Rectangle {
                    visible: win.recordingState !== "Transcribing"
                    x: 5.4; y: 5.4; width: 9.2; height: 9.2; radius: 4.6
                    color: theme.redForeground3
                }
            }
            HoverHandler { id: recHover }
            IndicatorTip { target: recordingIndicator; text: win.recordingTip; shown: recHover.hovered }
            Accessible.role: Accessible.Graphic
            Accessible.name: win.recordingTip
        }
        Item {
            id: aiIndicator
            visible: win.meeting && win.aiIndicator && !win.streaming
            x: win.compactBar ? (recordingIndicator.visible ? 52 : 30) : recordingIndicator.visible ? 68 : 38
            y: win.compactBar ? 8.7 : 14; width: win.compactBar ? 24.9 : 37.33; height: win.compactBar ? 22 : 32
            readonly property bool active: win.aiOn && win.aiAvailable
            readonly property string tip: !win.aiAvailable ? qsTr("AI isn't available in this meeting")
                : active ? qsTr("AI is on in the meeting") : qsTr("AI is turned off and doesn't have access to the meeting")
            Rectangle {
                id: hcFill1
                x: win.compactBar ? 2.7 : 4.67; y: win.compactBar ? 4 : 6
                width: win.compactBar ? 19.6 : 28; height: win.compactBar ? 14 : 20; radius: height / 2
                color: aiIndicator.active ? (aiHover.hovered ? theme.brandHover : theme.brandFill) : win.barFill
                FluentIcon {
                    x: win.compactBar ? 2.8 : 4; y: 0
                    name: aiIndicator.active ? "sparkle-20-filled" : "sparkle-off-20-regular"; size: win.compactBar ? 14 : 20
                    color: theme.onFill(hcFill1, aiIndicator.active ? theme.textOnBrand
                        : !win.aiAvailable ? theme.disabled
                        : aiHover.hovered || aiPopover.visible ? theme.brand : theme.text)
                }
            }
            HoverHandler { id: aiHover; cursorShape: win.aiAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler {
                enabled: win.aiAvailable
                onTapped: aiPopover.visible ? aiPopover.close() : aiPopover.open()
            }
            IndicatorTip { target: aiIndicator; text: aiIndicator.tip; shown: aiHover.hovered && !aiPopover.visible }
            Accessible.role: Accessible.Button
            Accessible.name: aiIndicator.tip
            Accessible.onPressAction: if (win.aiAvailable) aiPopover.open()
        }
        // Teams' Interpreter indicator (AiInterpretationIndicator, after the
        // AI one): while Interpreter is on and someone listens in a
        // language group, or consecutive interpretation is on; its 20 px
        // sparkle sound wave, the tooltip "AI is interpreting this meeting"
        // ("Interpreter is paused"); a click opens its card.
        Item {
            id: interpIndicator
            visible: win.meeting && !win.streaming && win.interpreterIndicator
            x: (win.compactBar ? 30 : 38) + (recordingIndicator.visible ? (win.compactBar ? 22 : 30) : 0) + (aiIndicator.visible ? (win.compactBar ? 24.9 : 37.33) : 0)
            y: win.compactBar ? 8.7 : 14; width: win.compactBar ? 22 : 30; height: win.compactBar ? 22 : 32
            FluentIcon {
                anchors.centerIn: parent
                name: "sound-wave-circle-sparkle-20"; size: win.compactBar ? 14 : 20
                color: interpHover.hovered || interpCard.visible ? theme.brand : theme.textStrong
            }
            HoverHandler { id: interpHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: interpCard.visible ? interpCard.close() : interpCard.open() }
            IndicatorTip { target: interpIndicator; text: win.interpreterTip; shown: interpHover.hovered && !interpCard.visible }
            Accessible.role: Accessible.Button
            Accessible.name: win.interpreterTip
            Popup {
                id: interpCard
                y: parent.height + 13.33; width: 320; padding: 16
                background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
                contentItem: Column {
                    spacing: 12
                    Text { text: win.interpreterTip; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text {
                        width: 288; wrapMode: Text.Wrap
                        text: win.interpreterInGroup
                            ? (win.interpreterOthers === 0 ? qsTr("You are using Interpreter. Your interpretation language is %1.").arg(win.interpreterLanguageName)
                                                           : qsTr("You and %1 others are using Interpreter. Your interpretation language is %2.").arg(win.interpreterOthers).arg(win.interpreterLanguageName))
                            : qsTr("%n people are using Interpreter.", "", win.interpreterListeners)
                        font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                    }
                    Row {
                        spacing: 8
                        Rectangle {
                            width: manageText.implicitWidth + 24; height: 32; radius: 4
                            color: manageHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 0.67
                            Text { id: manageText; anchors.centerIn: parent; text: qsTr("Manage settings"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { interpCard.close(); interpreterDialog.show(!win.interpreterInGroup) } }
                            Accessible.role: Accessible.Button; Accessible.name: manageText.text
                        }
                        Rectangle {
                            visible: win.interpreterInGroup || !!win.interpreter.available
                            width: offText.implicitWidth + 24; height: 32; radius: 4
                            color: win.interpreterInGroup ? (offHover.hovered ? theme.menuHover : theme.surface) : (offHover.hovered ? theme.brandHover : theme.brandFill)
                            border.color: win.interpreterInGroup ? theme.stroke : "transparent"; border.width: 0.67
                            Text { id: offText; anchors.centerIn: parent; text: win.interpreterInGroup ? qsTr("Turn off for me") : qsTr("Turn on for me"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: win.interpreterInGroup ? theme.text : theme.textOnBrand }
                            HoverHandler { id: offHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { interpCard.close(); if (win.interpreterInGroup) backend.interpreterAction("offForMe", "{}"); else interpreterDialog.show(true) } }
                            Accessible.role: Accessible.Button; Accessible.name: offText.text
                        }
                    }
                    Rectangle { width: 288; height: 1; color: theme.divider }
                    Text { width: 288; wrapMode: Text.Wrap; text: qsTr("AI-generated content may be incorrect."); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                }
            }
        }
        // Teams' event state pill (VirtualEventsLiveIndicator) with a green
        // room, measured in Teams desktop 2026-11-18: 22 tall, radius 10,
        // 8 padding, the label 11.67 uppercase; presenters see "Not
        // started" on #FDE300, "Live" on #D13438 (white) or "Ended" on
        // #EBEBEB, then a divider, the eye glyph (22) and the attendee
        // count; attendees (the stream) see "Waiting", "Live", "Ended",
        // first in the bar.
        Rectangle {
            id: liveIndicator
            readonly property string phase: win.streaming && win.streamState.lobby && (win.liveEvent.eventPhase || "") === "" ? "prelive" : win.liveEvent.eventPhase || ""
            readonly property bool attendeeView: win.myRole === "attendee" || win.streaming
            visible: win.meeting && !win.compactBar && (!!win.liveEvent.staging || win.streaming) && (!attendeeView || phase === "active" || phase === "ended" || !!win.liveEvent.townHall || win.streaming)
            x: win.streaming ? 14.67 : timerText.x - width - 8
            anchors.verticalCenter: parent.verticalCenter
            height: 21.67; radius: 10; width: liveRow.implicitWidth + 16
            color: theme.highContrast ? theme.pane
                 : phase === "active" ? "#D13438" : !attendeeView ? "#FDE300" : theme.pick("#EBEBEB", "#333333", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: theme.text
            readonly property color ink: theme.highContrast ? theme.text : phase === "active" ? "#FFFFFF" : !attendeeView ? "#242424" : theme.pick("#616161", "#D6D6D6", "#FFFFFF")
            readonly property string label: phase === "active" ? qsTr("Live") : phase === "ended" ? qsTr("Ended") : attendeeView ? qsTr("Waiting") : qsTr("Not started")
            // As Teams' live tile: the tooltip from its tooltipKey, the
            // aria-label from its descriptionKey.
            readonly property string tip: attendeeView
                ? (phase === "active" ? qsTr("The event is live.") : phase === "ended" ? qsTr("The event has ended.") : qsTr("Waiting for the event to start."))
                : phase === "active" ? (win.liveEvent.townHall ? qsTr("%n attendees watching. Some may watch with a delay", "", win.attendeeCount) : qsTr("%n attendees watching", "", win.attendeeCount))
                : phase === "ended" ? qsTr("%n attendees remain", "", win.attendeeCount)
                : qsTr("%n attendees waiting", "", win.attendeeCount)
            readonly property string desc: attendeeView
                ? (phase === "active" ? qsTr("Live state.") : phase === "ended" ? qsTr("Ended state.") : qsTr("Pre-live state."))
                : phase === "active" ? (win.liveEvent.townHall ? qsTr("Live state. %n attendees watching at a delay", "", win.attendeeCount) : qsTr("Live state. %n attendees", "", win.attendeeCount))
                : phase === "ended" ? qsTr("Ended state. %n attendees", "", win.attendeeCount)
                : qsTr("Pre-live state. %n people have joined", "", win.attendeeCount)
            Row {
                id: liveRow
                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                Text { anchors.verticalCenter: parent.verticalCenter; text: liveIndicator.label.toUpperCase(); font.family: theme.font; font.pointSize: 8.75 // 11.67 px
                       color: liveIndicator.ink }
                // Fluent's vertical divider: a 0.67 line, 9 tall, in a 10.67 slot.
                Item { visible: !liveIndicator.attendeeView; width: 10.67; height: 22
                    Rectangle { anchors.centerIn: parent; width: 0.67; height: 9; color: liveIndicator.ink } }
                FluentIcon { visible: !liveIndicator.attendeeView; anchors.verticalCenter: parent.verticalCenter; name: "eye-20"; size: 22
                             color: liveIndicator.ink }
                Text { visible: !liveIndicator.attendeeView; anchors.verticalCenter: parent.verticalCenter; text: win.attendeeCount; font.family: theme.font; font.pointSize: 8.75 // 11.67 px
                       color: liveIndicator.ink }
            }
            HoverHandler { id: liveHover }
            IndicatorTip { target: liveIndicator; text: liveIndicator.tip; shown: liveHover.hovered }
            Accessible.role: Accessible.StaticText; Accessible.name: liveIndicator.desc
        }
        Text {
            id: timerText
            visible: !win.streaming
            // After the shield (and the AI indicator), 6.67 into the
            // duration's slot.
            x: win.compactBar ? 30 + (recordingIndicator.visible ? 22 : 0) + (aiIndicator.visible ? 24.9 : 0) + (interpIndicator.visible ? 22 : 0) + 2.7
               : 38 + (recordingIndicator.visible ? 30 : 0) + (aiIndicator.visible ? 37.33 : 0) + (interpIndicator.visible ? 30 : 0) + 6.67
                 + (liveIndicator.visible ? liveIndicator.width + 8 : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: win.state === "connected" ? win.clock(win.seconds) : "--:--"
            color: theme.textStrong
            // Compact: 12 px.
            font.family: theme.font; font.pixelSize: win.compactBar ? 12 : 14
        }
        // The controls, as Teams' layout engine places them
        // (teams_cli::calling::ubar over Teams' layout config): which show,
        // their order and dividers come from the config and the call; the
        // slot is right-aligned 4 px before the end slot and whatever
        // doesn't fit (Fluent's overflow, keeping 10 px free) moves to the
        // top of More.
        // The new controls' slot runs from 4 past the indicators to 4 before
        // the end slot, its controls centred in it.
        Row {
            id: middleSlot
            // A town hall's stream centres its few controls in the slot
            // (measured: Q&A, Captions, More around the window's middle).
            x: win.newControls || win.streaming ? win.ubarStart + Math.max(0, (win.ubarRoom - implicitWidth) / 2)
                               : leaveGroup.x - 17 - implicitWidth
            anchors.top: parent.top
            spacing: 0
            Repeater {
                model: win.ubar.bar
                Loader {
                    required property string modelData
                    sourceComponent: modelData === "|" ? barDivider : win.barComponent(modelData)
                    // The dragged control keeps its place hidden.
                    opacity: win.dragState && !win.dragState.cancelled && win.dragState.name === modelData ? 0 : 1
                    onLoaded: if (modelData !== "|") {
                        win.registerBarItem(modelData, item)
                        // The new controls: right-click to arrange them.
                        if (item.contextMenu) item.contextMenu.connect(p => win.openControlMenu(modelData, item, p))
                    }
                }
            }
        }
        // Dragging the new controls (see dragBegin): the bar outlives the
        // controls it lays out again while the drag goes on.
        HoverHandler {
            id: barDragHover
            enabled: win.newControls
        }
        DragHandler {
            id: barDrag
            target: null
            dragThreshold: 2
            acceptedButtons: Qt.LeftButton
            // Only a press on a control that can move starts a drag.
            enabled: win.newControls && (active || win.ubar.movable.some(g => g.indexOf(win.barControlAt(bar.mapToItem(win.contentItem, barDragHover.point.position))) >= 0))
            cursorShape: win.dragZone === "blocked" ? Qt.ForbiddenCursor : Qt.ClosedHandCursor
            readonly property point at: win.contentItem.mapFromItem(null, centroid.scenePosition)
            onActiveChanged: {
                if (active) {
                    const p = win.contentItem.mapFromItem(null, centroid.scenePressPosition)
                    const n = win.barControlAt(p)
                    win.dragBegin(n, "bar", p, win.barItems[n] ? win.barItems[n].mapToItem(win.contentItem, 0, 0) : null)
                    win.dragMove(at)
                } else if (win.dragState) win.dragEnd(true)
            }
            onAtChanged: if (active && win.dragState) win.dragMove(at)
        }
        // Leave: 13 px in from the middle group's end, 14 from the window edge.
        Row {
            id: leaveGroup
            anchors { right: parent.right; rightMargin: 14; top: parent.top }
            // The new controls keep Resume, Join room and Return in the end
            // slot, before Leave.
            Repeater {
                model: win.newControls ? win.ubar.end.filter(n => n !== "CallButton") : []
                Loader {
                    required property string modelData
                    sourceComponent: win.barComponent(modelData)
                    onLoaded: win.registerBarItem(modelData, item)
                }
            }
            BarButton {
                id: leaveButton
                // In a room joined over the held main meeting: Teams' "Leave
                // room" with its exit arrow, and Leave meeting in its menu.
                icon: win.heldMeeting ? "arrow-exit-20-filled" : "call-leave-filled"
                label: win.heldMeeting ? qsTr("Leave room") : qsTr("Leave"); strong: true
                iconColor: win.newControls ? theme.nmcLeave : theme.hc("#B10E1C", "#FFFFFF")
                danger: true
                tip: win.heldMeeting ? qsTr("Leave room") : qsTr("Leave"); shortcut: "Ctrl+Shift+H"
                // Teams splits Leave only when its menu has more than Leave.
                split: win.meeting && win.leaveItems.length > 1 && !win.streaming
                chevronLabel: qsTr("More options")
                chevronChecked: leaveMenu.visible
                onClicked: win.heldMeeting ? win.leaveRoom(true) : win.leaveAsked()
                onChevronClicked: leaveMenu.open()
            }
        }
        // Teams' "Ask me to confirm when I leave a meeting" (Settings ▸
        // General; measured on winpc 2026-11-14): a 287.3 x 156 surface
        // right-aligned under Leave, 5.3 below it, padding 23.7: "Are you
        // sure you want to leave?" (14 px), then Stay (secondary) and Leave
        // (#C50F1F), 240 x 31.3 each, 8 apart.
        Popup {
            id: leaveConfirm
            parent: Overlay.overlay
            width: 287.3; height: 156; padding: 23.7
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            onAboutToShow: {
                const p = leaveButton.mapToItem(Overlay.overlay, leaveButton.width, leaveButton.height)
                x = p.x - width; y = p.y + 5.3
            }
            Column {
                spacing: 0
                Text {
                    width: 240; height: 20; verticalAlignment: Text.AlignVCenter
                    text: qsTr("Are you sure you want to leave?")
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                Item { width: 1; height: 18 }
                Rectangle {
                    id: hcFill2
                    width: 240; height: 31.3; radius: 4
                    color: stayHover.hovered ? theme.menuHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Text { anchors.centerIn: parent; text: qsTr("Stay"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                    HoverHandler { id: stayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: leaveConfirm.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Stay")
                }
                Item { width: 1; height: 8 }
                Rectangle {
                    id: hcFill3
                    width: 240; height: 31.3; radius: 4
                    color: goHover.hovered ? theme.hc("#A80C1A", "#1AEBFF") : theme.hc("#C50F1F", "#000000")
                    Text { anchors.centerIn: parent; text: qsTr("Leave"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, "white") }
                    HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { leaveConfirm.close(); win.leave() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Leave")
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // Where the stage's notices start: under the bar, or the meeting
    // timer when it shows.
    readonly property real belowBar: bar.y + bar.height + (timerStrip.visible ? timerStrip.height : 0)

    // More ▸ Timer: Teams' meeting timer strip under the bar (its
    // visibility rules: timer/spec.md §5). Teams shows it where everyone
    // can present; attendees get it view-only.
    /// Call health's values ({values: {data-tid: {value, enabled}}});
    /// refreshCallHealth() asks the backend for fresh ones.
    property var callHealth: ({})
    signal refreshCallHealth()
    // Teams refreshes at once when your media turns on or off.
    onCameraOnChanged: {
        if (side === "callHealth") refreshCallHealth()
        // PowerPoint Live's Cameo goes back to Content only when the camera goes off.
        if (!cameraOn && pptPresenting && pptLayout === "Cameo") { pptLayout = "ContentOnly"; backend.contentPptCameo(false) }
    }
    function callHealthPaneForTest() { return callHealthPane }
    property var timerData: null
    property bool everyonePresents: false
    // A chat's group call has no presenter option: everyone presents (Teams
    // showed Timer in a group chat's Meet now and Audio call, 2026-11-18).
    readonly property bool timerCanView: meeting && (everyonePresents || (!scheduled && !adhocMeeting && !testCall))
    readonly property bool timerViewOnly: !timerCanView || myRole === "attendee"
    property bool timerVisible: false
    // You cancelled it: Teams keeps your strip; everyone else's closes.
    property bool timerCancelledByMe: false
    property string timerPrevState: ""
    signal timerAction(string name, int arg)
    signal timerChime()
    function toggleTimer() {
        timerVisible = !timerVisible
        // Nothing running: Teams opens the setup at once.
        if (timerVisible && timerStrip.cancelled && !timerViewOnly && !timerStrip.agendaActive) Qt.callLater(timerStrip.openControls)
    }
    onTimerDataChanged: {
        agendaChanged()
        const st = timerData && timerData.adhoc ? timerData.adhoc.state : "Cancelled"
        const before = timerPrevState
        timerPrevState = st
        if (!timerData) { timerVisible = false; return }
        if (before === "") {
            // Joined with a timer running: it shows.
            if (st !== "Cancelled") timerVisible = true
            return
        }
        if (before === "Cancelled" && st === "InProgress") { timerVisible = true; timerCancelledByMe = false }
        else if (before !== "Cancelled" && st === "Cancelled") {
            if (!timerCancelledByMe && !timerStrip.agendaActive) timerVisible = false
            timerCancelledByMe = false
        }
        // What changed, as Teams announces it to everyone.
        const left = timerStrip.spoken(timerData.adhoc.remainingDuration || 0)
        if (before === "Paused" && st === "InProgress") contentItem.Accessible.announce(qsTr("Timer resumed with %1 remaining.").arg(left))
        else if (before === "InProgress" && st === "Paused") contentItem.Accessible.announce(qsTr("Timer paused at %1.").arg(left))
        else if (before === "Cancelled" && st === "InProgress") contentItem.Accessible.announce(qsTr("Timer started with %1.").arg(left))
        else if (before === "InProgress" && st === "Cancelled") contentItem.Accessible.announce(qsTr("Timer stopped."))
    }
    function timerStripForTest() { return timerStrip }
    // The agenda: when it starts (or you join with one running) the strip
    // opens on it; cancelled, the strip goes back to the ad-hoc timer or
    // closes for everyone.
    property string agendaPrevState: ""
    function agendaChanged() {
        const a = timerData && timerData.agenda ? timerData.agenda : null
        const st = a && (a.sections || []).length && timerData.facilitator !== false ? a.state || "Cancelled" : "Cancelled"
        const before = agendaPrevState
        agendaPrevState = st
        if (st === before) return
        const adhocOn = timerData && timerData.adhoc && timerData.adhoc.state !== "Cancelled"
        if (st !== "Cancelled" && (before === "" || before === "Cancelled")) {
            timerVisible = true
            timerStrip.view = "agenda"
        } else if (st === "Cancelled" && before !== "" && before !== "Cancelled") {
            if (adhocOn) timerStrip.view = "adhoc"
            else if (timerStrip.shownView === "agenda" || timerStrip.view === "agenda") { timerVisible = false; timerStrip.view = "adhoc" }
        }
    }
    ConfirmDialog {
        id: cancelTrackerAsk
        title: qsTr("Cancel tracker for all?")
        body: qsTr("This will cancel and remove the tracker for everyone.")
        cancelText: qsTr("Close")
        confirmText: qsTr("Cancel tracker")
        closeButton: true
        onConfirmed: {
            backend.agendaEdit("cancel", "{}")
            contentItem.Accessible.announce(qsTr("Timer has been ended."))
        }
    }
    MeetingTimerStrip {
        id: timerStrip
        visible: win.timerVisible && win.timerCanView && win.state === "connected"
        y: bar.y + bar.height
        width: sidePane.visible ? sidePane.x : win.contentItem.width
        info: win.timerData
        viewOnly: win.timerViewOnly
        // Teams' canEditAgendaTimer: timer controls and a Copilot licence.
        agendaEditable: !win.timerViewOnly && win.copilotAllowed
        onCancelAgendaAsked: cancelTrackerAsk.open()
        onAction: (name, arg) => {
            if (name === "cancel" || name === "cancelOverTime") win.timerCancelledByMe = true
            win.timerAction(name, arg)
        }
        onAnnounce: text => win.contentItem.Accessible.announce(text)
        onTimeUp: win.timerChime()
    }

    // Live captions: a strip 4 in from the sides and bottom (or under the
    // bar, "At top"), the stage above (or below) it.
    CaptionsWindow {
        id: captionsWindow
        visible: (win.captionsOn || win.rttOn) && win.state === "connected" && !win.captionsPoppedOut
        x: 4; width: (sidePane.visible ? sidePane.x : win.contentItem.width) - 8
        height: implicitHeight
        y: win.captionsAtTop ? win.belowBar + 4 : win.contentItem.height - 4 - height
        captions: win.captions
        roster: win.people
        meId: backend.userMri
        meName: backend.userName
        filterProfanity: win.accessibility.profanityFilterEnabled === true
        languageName: win.languageName(win.captionsLanguage)
        styles: win.captionStyles
        windowHeight: win.height
        areaHeight: win.contentItem.height - bar.y - bar.height
        rttOn: win.rttOn
        rttInitiator: win.rttInitiator
        privacyUrl: win.privacyUrl
        onClosed: win.setCaptions(false)
        onSettingsRequested: anchor => win.openCaptionSettings(anchor)
        onPopOut: win.captionsPoppedOut = true
    }
    // Captions in a window of their own (Open captions in new window).
    property bool captionsPoppedOut: false
    onCaptionsOnChanged: if (!captionsOn && !rttOn) captionsPoppedOut = false
    CaptionsPopout {
        id: captionsPopout
        visible: (win.captionsOn || win.rttOn) && win.captionsPoppedOut && win.state === "connected"
        meetingTitle: win.meetingInfo ? win.meetingInfo.title : win.peer
        captions: win.captions
        roster: win.people
        meId: backend.userMri
        meName: backend.userName
        filterProfanity: win.accessibility.profanityFilterEnabled === true
        languageName: win.languageName(win.captionsLanguage)
        styles: win.captionStyles
        rttOn: win.rttOn
        rttInitiator: win.rttInitiator
        privacyUrl: win.privacyUrl
        captionsOn: win.captionsOn
        onSetCaptions: on => win.setCaptions(on)
        onPopIn: win.captionsPoppedOut = false
        onSettingsRequested: anchor => win.showCaptionSettings(anchor)
    }
    CaptionsSettingsMenu {
        id: captionSettings
        language: win.captionsLanguage
        languageName: win.languageName(win.captionsLanguage)
        languages: win.spokenLanguages
        position: win.captionsAtTop ? "Top" : "Bottom"
        alwaysOn: win.accessibility.startCaptionsAutomatically === true
        filterProfanity: win.accessibility.profanityFilterEnabled === true
        onLanguagePicked: code => win.setCaptionsLanguage(code)
        onCaptionStyles: win.side = "captionStyles"
        onPositionPicked: pos => win.saveCaptionStyles(Object.assign({}, win.captionStyles, { captionsPosition: pos }))
        onAlwaysOnToggled: on => win.updateAccessibility(JSON.stringify({ startCaptionsAutomatically: on }))
        onFilterProfanityToggled: on => win.updateAccessibility(JSON.stringify({ profanityFilterEnabled: on }))
    }
    // "…" when the buttons don't fit: Open caption settings ▸.
    // With RTT on it leads with a "Live Captions" switch and pops out
    // "RTT/Captions".
    MenuPopup {
        id: captionsOverflow
        items: (win.rttOn ? [{ label: qsTr("Live Captions"), toggle: true, checked: win.captionsOn }] : []).concat([
                { label: qsTr("Open caption settings"), icon: "settings-20", chevron: true },
                { label: win.rttOn ? qsTr("Open RTT/Captions in new window") : qsTr("Open captions in new window"), icon: "captions-pop-out-20" }])
        onPicked: i => {
            const k = win.rttOn ? i - 1 : i
            if (k < 0) win.setCaptions(!win.captionsOn)
            else if (k === 0) win.showCaptionSettings(captionsOverflow.parent)
            else win.captionsPoppedOut = true
        }
    }

    // More ▸ Report a concern: the meeting, and everyone in it or its chat
    // but you.
    function openMeetingReport() {
        if (!meetingInfo) loadMeetingInfo()
        const me = (backend.userMri || "").toLowerCase()
        const seen = {}
        const people = []
        // Teams lists the chat's members first, then who else is here.
        for (const p of (win.chatMembers || []).concat(win.people)) {
            const id = (p.id || p.mri || "").toLowerCase()
            // The roster names you "me".
            if (!id || id === "me" || id === me || seen[id] || id.startsWith("28:")) continue
            seen[id] = true
            people.push({ id: p.id || p.mri, name: p.name || p.displayName || "" })
        }
        const org = win.people.find(p => (p.role || "").toLowerCase() === "organizer")
        meetingReport.people = people
        meetingReport.person = null
        meetingReport.organizer = org ? org.name : ""
        meetingReport.open()
    }
    function openPersonReport(id, name) {
        if (!meetingInfo) loadMeetingInfo()
        meetingReport.people = []
        meetingReport.person = { id: id, name: name }
        meetingReport.open()
    }
    MeetingReportDialog {
        id: meetingReport
        property string organizer: ""
        meeting: ({ title: win.meetingInfo ? win.meetingInfo.title : "", start: win.meetingInfo ? (win.meetingInfo.startText || "") : "", organizer: organizer })
        onReported: { win.reportSent = true; reportSentTimer.restart() }
    }
    property bool reportSent: false
    Timer { id: reportSentTimer; interval: 5000; onTriggered: win.reportSent = false }

    // More ▸ Help: Teams' Help app in a window of its own, opened on its
    // meetings page (help.svc's "helpappmeetings").
    readonly property string helpSession: Qt.md5(String(Date.now()) + Math.random()).replace(/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/, "$1-$2-$3-$4-$5")
    function helpUrl(subEntity) {
        const ctx = { TeamsTheme: theme.pick("default", "dark"), SessionId: helpSession,
                      AppVersionMajor: "16", AppVersionMinor: "0", AppVersionBuild: "0", AppVersionUpdate: "0",
                      HostClientType: "desktop", TeamsHostName: "TeamsModern", SubEntityId: subEntity }
        return "https://help.svc.cloud.microsoft/f1/home/?shownav=True&NS=MSFTTEAMS&version=16&omkt="
            + Qt.locale().name.toLowerCase().replace("_", "-") + "&RingId=general&context=" + encodeURIComponent(JSON.stringify(ctx))
    }
    // Teams' Help window (measured on winpc): its title row (Help,
    // Settings and more), the Help app's header, then the page.
    Window {
        id: helpWindow
        title: qsTr("Help")
        width: 946; height: 593
        color: theme.surface
        property bool pinned: false
        flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
        readonly property Item titleBarForTest: helpTitle
        readonly property Item appForTest: helpApp.item
        ChildWindowTitleBar {
            id: helpTitle
            title: qsTr("Help")
            pinned: helpWindow.pinned
            onTogglePin: helpWindow.pinned = !helpWindow.pinned
        }
        Loader {
            id: helpApp
            anchors { top: helpTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            active: helpWindow.visible
            // Teams' Help app (its id names the app's tile and name).
            sourceComponent: WebApp { appId: "5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83"; appName: "Help"; home: win.helpUrl("helpappmeetings") }
        }
    }

    // Chat bubbles: centred over the stage, 10.67 under the bar (or the
    // captions at the top).
    ChatBubble {
        id: chatBubble
        z: 50
        x: stage.x + (stage.width - width) / 2
        y: (captionsWindow.visible && win.captionsAtTop ? captionsWindow.y + captionsWindow.height : win.belowBar) + 10.67
        onOpenChat: win.side = "chat"
        onMuteBubbles: win.setChatBubblesSuppressed(true)
    }

    // Stage
    Rectangle {
        id: stage
        anchors {
            top: captionsWindow.visible && win.captionsAtTop ? captionsWindow.bottom : timerStrip.visible ? timerStrip.bottom : bar.bottom
            left: parent.left; right: sidePane.visible ? sidePane.left : parent.right
            bottom: captionsWindow.visible && !win.captionsAtTop ? captionsWindow.top : parent.bottom
            margins: 6
            topMargin: captionsWindow.visible && win.captionsAtTop ? 2.67 : 6
            bottomMargin: captionsWindow.visible && !win.captionsAtTop ? 2.67 : 6
        }
        radius: 6
        // Teams: a flat stage in meetings, a soft gradient in 1:1 calls.
        color: theme.pane
        gradient: win.meeting ? null : oneToOne
        Gradient {
            id: oneToOne
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.hc("#F2F1F8", "#000000") }
            GradientStop { position: 1.0; color: theme.hc("#EEF6F6", "#000000") }
        }
        // Meetings: alone, your video (below) or your picture and "Invite
        // people to join you" / "Waiting for others to join...";
        // otherwise a tile for each other person.
        // An attendee waiting for a webinar or town hall to start (Teams'
        // staging screen: "Welcome to", the title, "This meeting will start
        // shortly"), or after it ended ("The event has concluded. Thank you
        // for attending.").
        // A town hall's attendee watches the event's stream where the
        // stage is (Teams' streaming player).
        LiveStreamPlayer {
            id: streamPlayer
            anchors.fill: parent
            z: 4
            visible: win.streaming
            source: win.streamState.url || ""
            active: win.streaming && !win.streamState.lobby && (win.liveEvent.eventPhase || "") !== "prelive"
            onFullScreenRequested: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen()
        }
        Rectangle {
            id: stagingScreen
            readonly property string phase: win.streaming && win.streamState.lobby && (win.liveEvent.eventPhase || "") !== "ended" ? "prelive" : win.liveEvent.eventPhase || ""
            // A town hall's stream keeps playing after the end (Teams
            // shows the Ended pill over the player).
            visible: win.meeting && (win.streaming ? phase === "prelive" : win.myRole === "attendee" && (phase === "prelive" || phase === "ended"))
            anchors.fill: parent; radius: parent.radius; color: theme.pane; z: 5
            // A town hall's stream before it's live (Teams' streaming
            // curtain, measured 2026-11-18: 24/32 bold, centred, on the
            // #F5F5F5 calling background).
            Text {
                visible: win.streaming && stagingScreen.phase === "prelive"
                anchors.centerIn: parent; width: parent.width - 48; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: qsTr("The event isn't live right now.")
                color: theme.pick("#252423", "#FFFFFF", "#FFFFFF"); font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight
            }
            // (Measured in Teams desktop 2026-11-19, a webinar's attendee
            // before the start: "Welcome to" and "This meeting will start
            // shortly" 14/400 #616161, the title 20/700/28 #242424, 16 apart.)
            Column {
                visible: !win.streaming
                anchors.centerIn: parent; spacing: 16; width: parent.width - 48
                Text { visible: stagingScreen.phase === "prelive"; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Welcome to")
                       color: theme.textSecondary; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight }
                Text { visible: stagingScreen.phase === "prelive"; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: win.peer
                       color: theme.text; font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold; lineHeight: 28; lineHeightMode: Text.FixedHeight }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: stagingScreen.phase === "ended" ? qsTr("The event has concluded. Thank you for attending.") : qsTr("This meeting will start shortly")
                       color: theme.textSecondary; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight }
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: stagingScreen.phase === "ended" ? qsTr("The event has concluded. Thank you for attending.") : qsTr("Welcome to %1. This meeting will start shortly").arg(win.peer)
        }
        // Managing the screen (Manage what attendees see on, Teams'
        // managed-mode stage measured in a town hall's green room
        // 2026-11-18): with nobody on screen the stage says "Bring
        // presenters on screen and share content that you want attendees
        // to see." (18/700 #252423 on #F5F5F5, centred).
        Rectangle {
            visible: win.manageScreen && !win.previewMode && !tiles.visible && !stagingScreen.visible
            x: 240; width: parent.width - 240; height: parent.height
            radius: parent.radius; color: theme.pane
            Text {
                anchors.centerIn: parent; width: Math.min(653, parent.width - 48)
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: qsTr("Bring presenters on screen and share content that you want attendees to see.")
                color: theme.pick("#252423", "#FFFFFF", "#FFFFFF"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
                lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            }
        }
        // The "Manage screen" panel (240 wide on the stage's left): the
        // header (60 tall: "Manage screen" 14/600, its info button, Add
        // Videos), "Attendees can still hear your audio when you're off
        // screen." (12/14 #424242), the All / Live / People / Content pills
        // (24 tall, the chosen one brand with white 12/600), then a 236 x 131
        // tile for each organizer and presenter with its Stage presence
        // switch at the top right.
        Item {
            id: manageScreenPane
            visible: win.manageScreen && !win.previewMode && !stagingScreen.visible
            width: 240; height: parent.height
            readonly property var people: {
                const all = win.roster.filter(p => p.active !== false && (p.role || "").toLowerCase() !== "attendee" && !p.bot)
                    .map(p => p.id === win.selfId ? Object.assign({}, win.selfEntry, { spotlight: p.spotlight || "", role: p.role }) : p)
                if (win.manageFilter === "Live") return all.filter(p => !!p.spotlight)
                if (win.manageFilter === "Content") return []
                return all
            }
            Text { x: 20; y: 20; text: qsTr("Manage screen"); color: theme.pick("#252423", "#FFFFFF", "#FFFFFF"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
            FluentIcon {
                id: manageInfo
                x: 121; y: 22; name: "info-16"; size: 16; color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
                HoverHandler { id: manageInfoHover }
                ToolTip.visible: manageInfoHover.hovered
                ToolTip.text: qsTr("Only organizers and presenters can manage the screen.")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("More information")
            }
            Rectangle {
                x: 196; y: 14; width: 32; height: 32; radius: 4
                color: addVideosHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "video-add-20"; size: 20; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                HoverHandler { id: addVideosHover; cursorShape: Qt.PointingHandCursor }
                ToolTip.visible: addVideosHover.hovered; ToolTip.text: qsTr("Add Videos")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Add Videos")
            }
            Rectangle { y: 59.3; width: 240; height: 1; color: theme.dividerSoft }
            Text {
                x: 20; y: 66; width: 200; wrapMode: Text.Wrap
                text: qsTr("Attendees can still hear your audio when you're off screen.")
                color: theme.pick("#424242", "#D6D6D6", "#FFFFFF"); font.family: theme.font; font.pixelSize: 12; lineHeight: 14; lineHeightMode: Text.FixedHeight
            }
            Row {
                x: 20; y: 102; spacing: 4
                Repeater {
                    model: ["All", "Live", "People", "Content"]
                    Rectangle {
                        id: pill
                        required property string modelData
                        readonly property bool chosen: win.manageFilter === modelData
                        width: pillText.implicitWidth + 13.3; height: 24; radius: 12
                        color: chosen ? theme.brand : pillHover.hovered ? theme.hover : "transparent"
                        border.width: chosen ? 0 : 1; border.color: theme.divider
                        Text {
                            id: pillText; anchors.centerIn: parent; text: win.manageFilterLabel(pill.modelData)
                            color: pill.chosen ? "white" : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                            font.family: theme.font; font.pixelSize: 12; font.weight: pill.chosen ? Font.DemiBold : Font.Normal
                        }
                        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.manageFilter = pill.modelData }
                        Accessible.role: Accessible.RadioButton; Accessible.name: win.manageFilterLabel(pill.modelData); Accessible.checked: pill.chosen
                    }
                }
            }
            ListView {
                x: 0; y: 134.6; width: 240; height: parent.height - y
                clip: true; spacing: 4
                model: manageScreenPane.people
                delegate: Item {
                    id: backstageTile
                    required property var modelData
                    width: 240; height: 135
                    MeetingTile { x: 2; y: 2; width: 236; height: 131; call: win; person: backstageTile.modelData }
                    SettingsParts.Toggle {
                        x: 240 - 2 - width - 8; y: 12; stateLabel: false
                        on: !!backstageTile.modelData.spotlight
                        accessibleName: on ? qsTr("Stage presence: On stage") : qsTr("Stage presence: Off stage")
                        onToggled: v => {
                            const p = backstageTile.modelData
                            if (v) win.participantAction("spotlight", p.self ? win.selfId : p.id, p.name || "", "")
                            else win.participantAction("unspotlight", p.self ? win.selfId : p.id, p.name || "", p.spotlight || "")
                        }
                    }
                }
            }
            Accessible.role: Accessible.Pane; Accessible.name: qsTr("Manage screen")
        }
        // "On with preview" (measured in Teams desktop 2026-11-19, a town
        // hall's green room, 1280 x 680): the stage's top part (all but
        // 224) holds the Preview and Live stages 32 apart about the middle,
        // each 16:9 and 132.1 shorter than that part (402.9 x 226.6 here),
        // a 2.67 frame, its title 12 above (16/700, 8 in), Send live (96 x
        // 31.3, #FDE300, 14/600 #242424) 24 under the Preview's right edge;
        // then the Manage screen strip: a 60 tall header ("Manage screen"
        // 18/700, the info button, the hint 12 #424242, the pills, Add
        // Videos at the right) and a row of 273 x 152 tiles 4 apart, each
        // with its "Add to preview" switch at the top right.
        Item {
            id: production
            anchors.fill: parent
            visible: win.previewMode && !stagingScreen.visible
            readonly property real topH: height - 224
            readonly property real subH: Math.max(90, Math.min(topH - 132.1, (width / 2 - 24) * 9 / 16))
            readonly property real subW: subH * 16 / 9
            readonly property color ink: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
            component SubStage: Item {
                id: sub
                property string title
                property color edge
                property var people: []
                property string empty
                /// Teams' "Last updated by <b>name</b>" (13/400, the name
                /// bold) at the title row's right end.
                property string updatedBy
                width: production.subW; height: 58.8 + production.subH
                Text { x: 8; y: 20; text: sub.title; color: production.ink; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text {
                    visible: sub.updatedBy !== ""
                    anchors.right: parent.right; y: 22.1; width: Math.min(implicitWidth, parent.width / 2 - 12)
                    elide: Text.ElideRight; textFormat: Text.StyledText
                    text: qsTr("Last updated by <0>%1</0>").replace("<0>", "<b>").replace("</0>", "</b>").arg(sub.updatedBy.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
                    color: production.ink; font.family: theme.font; font.pixelSize: 13; lineHeight: 18.6; lineHeightMode: Text.FixedHeight
                }
                Rectangle {
                    y: 58.8; width: parent.width; height: production.subH
                    color: "transparent"; border.width: 2.67; border.color: sub.edge; radius: 2
                    Rectangle {
                        anchors { fill: parent; margins: 2.67 }
                        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                        visible: sub.people.length === 0
                        Text {
                            anchors.centerIn: parent; width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: sub.empty; color: production.ink
                            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
                            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                        }
                    }
                    // Teams' CLASSIC layout (measured with three sources
                    // sent live, 2026-11-19): a grid of equal 16:9 tiles,
                    // ceil(sqrt(n)) a row, 2 apart across and none down, the
                    // last row centred (397.6 x 221.3 inside: two 196.7 x
                    // 110.6 tiles, the third under them).
                    Item {
                        id: grid
                        anchors { fill: parent; margins: 2.67 }
                        visible: sub.people.length > 0
                        readonly property int n: sub.people.length
                        readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n)))
                        readonly property int rows: Math.max(1, Math.ceil(n / cols))
                        readonly property real tw: Math.min((width - 2 * (cols - 1)) / cols, height / rows * 16 / 9)
                        readonly property real th: tw * 9 / 16
                        Repeater {
                            model: sub.people
                            MeetingTile {
                                required property var modelData
                                required property int index
                                readonly property int row: Math.floor(index / grid.cols)
                                readonly property int inRow: row === grid.rows - 1 ? grid.n - row * grid.cols : grid.cols
                                x: (grid.width - (inRow * grid.tw + 2 * (inRow - 1))) / 2 + (index % grid.cols) * (grid.tw + 2)
                                y: (grid.height - grid.rows * grid.th) / 2 + row * grid.th
                                width: grid.tw; height: grid.th
                                call: win; person: modelData
                            }
                        }
                    }
                    Accessible.role: Accessible.Pane; Accessible.name: sub.title + " stage"
                }
            }
            SubStage {
                id: previewStage
                x: production.width / 2 - 16 - width; y: 0
                title: qsTr("Preview"); edge: "#FDE300"
                people: win.sourcePeople(win.previewSources)
                empty: qsTr("Bring presenters on screen and share content that you want attendees to see.")
            }
            SubStage {
                x: production.width / 2 + 16; y: 0
                title: qsTr("Live"); edge: (win.liveEvent.eventPhase || "") === "active" ? "#D13438" : "#FDE300"
                people: win.sourcePeople(win.liveSources)
                updatedBy: {
                    const id = win.liveEvent.layout ? win.liveEvent.layout.updatedBy || "" : ""
                    if (!id) return ""
                    if (id === win.selfId) return "you"
                    const p = win.roster.find(r => r.id === id)
                    return p ? p.name : ""
                }
                empty: (win.liveEvent.eventPhase || "") === "prelive" ? qsTr("The event hasn't started yet.") : qsTr("Bring presenters on screen and share content that you want attendees to see.")
            }
            Rectangle {
                id: sendLiveButton
                readonly property bool busy: (win.liveEvent.busy || "") === "sendingLive"
                x: previewStage.x + previewStage.width - width; y: previewStage.y + previewStage.height + 24
                width: 96; height: 31.3; radius: 4
                color: busy ? theme.pick("#F0F0F0", "#141414", "#000000") : sendLiveHover.hovered ? "#E6CE00" : "#FDE300"
                Text { anchors.centerIn: parent; text: qsTr("Send live"); color: sendLiveButton.busy ? theme.disabled : "#242424"
                       font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                HoverHandler { id: sendLiveHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !sendLiveButton.busy; onTapped: win.sendLive() }
                ToolTip.visible: sendLiveHover.hovered; ToolTip.text: sendLiveButton.busy ? qsTr("Waiting for previous action to complete.") : qsTr("Send the preview to the live screen")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Send the preview to the live screen")
            }
            // The Manage screen strip.
            Item {
                y: production.topH; width: parent.width; height: 224
                Text { x: 20; y: 18; text: qsTr("Manage screen"); color: production.ink; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 24; lineHeightMode: Text.FixedHeight }
                FluentIcon {
                    x: 158; y: 22; name: "info-16"; size: 16; color: production.ink
                    HoverHandler { id: prodInfoHover }
                    ToolTip.visible: prodInfoHover.hovered
                    ToolTip.text: qsTr("Only organizers and presenters can manage the screen.")
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("More information")
                }
                Text {
                    x: 186; y: 26; text: qsTr("Attendees can still hear your audio when you're off screen.")
                    color: theme.pick("#424242", "#D6D6D6", "#FFFFFF"); font.family: theme.font; font.pixelSize: 12; lineHeight: 14; lineHeightMode: Text.FixedHeight
                }
                Row {
                    x: 512; y: 18; spacing: 4
                    Repeater {
                        model: ["All", "Live", "People", "Content"]
                        Rectangle {
                            id: ppill
                            required property string modelData
                            readonly property bool chosen: win.manageFilter === modelData
                            width: ppText.implicitWidth + 13.3; height: 24; radius: 12
                            color: chosen ? theme.brand : ppHover.hovered ? theme.hover : "transparent"
                            Text { id: ppText; anchors.centerIn: parent; text: win.manageFilterLabel(ppill.modelData)
                                   color: ppill.chosen ? "white" : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                   font.family: theme.font; font.pixelSize: 12; font.weight: ppill.chosen ? Font.DemiBold : Font.Normal }
                            HoverHandler { id: ppHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: win.manageFilter = ppill.modelData }
                            Accessible.role: Accessible.RadioButton; Accessible.name: win.manageFilterLabel(ppill.modelData); Accessible.checked: ppill.chosen
                        }
                    }
                }
                Rectangle {
                    x: parent.width - 46; y: 14; width: 32; height: 32; radius: 4
                    color: prodAddHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "video-add-20"; size: 20; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                    HoverHandler { id: prodAddHover; cursorShape: Qt.PointingHandCursor }
                    ToolTip.visible: prodAddHover.hovered; ToolTip.text: qsTr("Add Videos")
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Add Videos")
                }
                ListView {
                    x: 4; y: 64; width: parent.width - 8; height: 156
                    orientation: ListView.Horizontal; spacing: 4; clip: true
                    model: {
                        const ids = win.previewSources.map(s => s.id)
                        const live = win.liveSources.map(s => s.id)
                        const all = win.roster.filter(p => p.active !== false && (p.role || "").toLowerCase() !== "attendee" && !p.bot)
                            .map(p => p.id === win.selfId ? Object.assign({}, win.selfEntry, { role: p.role }) : p)
                        if (win.manageFilter === "Live") return all.filter(p => live.indexOf(p.self ? win.selfId : p.id) >= 0)
                        if (win.manageFilter === "Content") return []
                        return all
                    }
                    delegate: Item {
                        id: prodTile
                        required property var modelData
                        readonly property bool inPreview: win.previewSources.some(s => s.id === (modelData.self ? win.selfId : modelData.id))
                        width: 277; height: 156
                        MeetingTile { x: 2; y: 2; width: 273; height: 152; call: win; person: prodTile.modelData }
                        SettingsParts.Toggle {
                            x: 277 - 2 - width - 8; y: 12; stateLabel: false
                            on: prodTile.inPreview
                            accessibleName: on ? qsTr("Remove from preview") : qsTr("Add to preview")
                            onToggled: v => win.togglePreview(prodTile.modelData, v)
                        }
                    }
                }
            }
            Accessible.role: Accessible.Pane; Accessible.name: qsTr("Production view")
        }
        // Alone with your video on (measured on Teams desktop, a Meet now,
        // 2026-11-17): your own video (myself-video) fills the stage at
        // 16:9 (1031.8 x 578.7 in a 1274.7 x 582.7 stage, 2 from the top),
        // with its name tag (24 high, rgba(0,0,0,0.5), radius 4) 8 in from
        // the bottom left showing your voice level and mic state.
        Item {
            id: soloSelf
            visible: win.meeting && win.others.length === 0 && win.cameraOn && win.state === "connected" && !stagingScreen.visible && !win.manageScreen
            anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
            readonly property real vw: Math.min(width, height * 16 / 9)
            Item {
                anchors.centerIn: parent
                width: soloSelf.vw; height: soloSelf.vw * 9 / 16
                clip: true
                VideoFrame {
                    id: soloVideo
                    anchors.fill: parent
                    source: soloSelf.visible ? "self" : ""
                    transform: Scale { origin.x: soloVideo.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
                }
                Timer { interval: 33; repeat: true; running: soloSelf.visible; onTriggered: soloVideo.refresh() }
                ReactionShown { z: 3; mri: win.selfId }
                Rectangle {
                    x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    width: soloTag.implicitWidth + 12; height: 24; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Row {
                        id: soloTag
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        // Teams' voice level: three 2 px bars (4, 7 and 10 high).
                        Item {
                            visible: !win.muted && win.hasAudio
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10; height: 10
                            Repeater {
                                model: [4, 7, 10]
                                Rectangle { required property var modelData; required property int index; x: index * 4; y: 10 - modelData; width: 2; height: modelData; color: "white" }
                            }
                        }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "mic-off-24"; size: 16; color: "white"; visible: win.muted || !win.hasAudio }
                    }
                    Accessible.role: Accessible.StaticText
                    Accessible.name: [qsTr("Myself video", "calling:k3zq2w8xc"), win.selfName || qsTr("You"), qsTr("video is on")].join(", ")
                }
            }
        }
        Column {
            visible: win.meeting && win.others.length === 0 && !soloSelf.visible && !win.contentShown && !win.manageScreen
            anchors.centerIn: parent
            spacing: 24
            Avatar { ring: false; size: 154; name: win.selfName || qsTr("You"); photoId: "me"; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // (Teams: an organizer or presenter is asked to invite.)
                text: win.state === "connected" ? (win.canMuteAll ? qsTr("Invite people to join you") : qsTr("Waiting for others to join...")) : win.state === "ended" ? qsTr("You left the meeting") : qsTr("Connecting...", "calling:kdhfq8tet")
                color: theme.text
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
            }
        }
        // Teams' stage layouts. The side gallery (Speaker view's others, or
        // you when you're out of the gallery) is a column of 16:9 slots on
        // the right (160 px wide, up to all but 161) or, with "Show gallery
        // at top", a row of them on top (90 px tall, up to 485); a 5 px
        // divider with a 1 px #D1D1D1 line resizes it.
        Item {
            id: tiles
            visible: win.previewMode ? false : win.stageOnly ? win.shownOnly.length > 0 || win.contentShown
                     : win.meeting && (win.others.length > 0 || win.contentShown) && (win.layout !== "focus" || win.presenting || win.contentShown)
            // Managing the screen: the stage right of the Manage screen
            // panel shows only who is on screen.
            anchors { fill: parent; margins: 2.67; leftMargin: win.manageScreen ? 240 : 2.67 }
            // Teams' stage buckets (813237 fillBucketForItem, 303772):
            // in Gallery and Speaker view the pin area (PinStage, up to 9)
            // takes the people your sign language role signs with (with
            // video), then the spotlighted, then your pins in pin order
            // (leanCompare); in the Sign language view the focused area
            // (FocusedStage, 2) takes the people your role signs with, and
            // the spotlighted and pinned go to the side. The centre shows
            // the focused area, else the pin area, as a 16:9 grid (Teams'
            // fixed aspect strategy); everyone else is in the side gallery.
            readonly property var focusedArea: win.stageOnly || win.layout !== "accessibility" ? [] : win.signFirst.slice(0, 2)
            readonly property var pinArea: {
                if (win.stageOnly) return []
                const out = []
                const add = p => { if (p && out.indexOf(p) < 0 && focusedArea.indexOf(p) < 0 && out.length < win.maxPins) out.push(p) }
                if (win.layout !== "accessibility") win.signFirst.forEach(add)
                win.spotlighted.forEach(sp => add(sp.id === win.selfId ? win.selfEntry : sp))
                win.pinnedIds.forEach(id => add(win.others.find(p => p.id === id)))
                return out
            }
            readonly property var featuredList: focusedArea.length ? focusedArea : pinArea
            readonly property var featured: featuredList.length ? featuredList[0] : null
            function isFeatured(p) { return featuredList.some(f => f.id === p.id) }
            readonly property bool speakerView: !win.stageOnly && (win.layout === "speaker" || !!featured)
            readonly property var speaker: {
                if (featured) return featured
                const pool = win.speakerMeInGallery && !win.hideMe ? win.others.concat([win.selfEntry]) : win.others
                // Teams (813237 onActiveSignerChanged, 937485 xB): people
                // actively signing come before the dominant speakers.
                const signer = win.signMode ? win.others.find(p => win.signingIds.indexOf(p.id) >= 0) : null
                return signer || pool.find(p => p.id === win.speakerId) || win.othersOrdered[0]
            }
            // Presenting: the content on stage, everyone in the side gallery
            // (no one in Focus on content).
            // (Popped out, the content has its own window and the stage
            // goes back to people.)
            readonly property bool content: (win.presenting || win.contentShown) && !win.contentPoppedOut
            // Teams (updateShouldMeBeInOverlay, live): with at most two
            // people tiles, the other person fills the stage and you float
            // over it, bottom right.
            readonly property bool meOverlay: !content && win.others.length === 1 && !win.hideMe && !win.stageOnly
            // (With content on the stage, the side lists the focused and
            // pinned people first.)
            readonly property var side: win.stageOnly ? (content && win.layout !== "focus" ? win.shownOnly : [])
                : content
                ? (win.layout === "focus" ? [] : featuredList.filter(p => !p.self).concat(win.othersOrdered.filter(p => !isFeatured(p))).concat(win.hideMe ? [] : [win.selfEntry]))
                : meOverlay ? []
                : speakerView
                ? win.othersOrdered.filter(p => !isFeatured(p) && p !== speaker).concat(win.hideMe || speaker.self || isFeatured(win.selfEntry) ? [] : [win.selfEntry])
                : (win.hideMe || win.meInGallery ? [] : [win.selfEntry])
            // Everyone in the gallery, in pages of the gallery size.
            readonly property var galleryAll: win.stageOnly ? win.shownOnly
                : (win.hideMe || !win.meInGallery ? [] : [win.selfEntry]).concat(win.othersOrdered)
            readonly property int pageCount: Math.max(1, Math.ceil(galleryAll.length / win.gallerySize))
            readonly property int page: Math.min(win.galleryPage, pageCount - 1)
            readonly property var gallery: galleryAll.slice(page * win.gallerySize, (page + 1) * win.gallerySize)
            // Teams' pager row: 34 tall under the tiles, 2 from the bottom.
            readonly property real pagerH: pageCount > 1 && !speakerView && !content ? 36 : 0
            readonly property bool atTop: win.galleryAtTop
            property real sideWidth: 160
            property real sideHeight: 90
            readonly property real sideW: side.length ? Math.max(160, Math.min(sideWidth, width - 161)) : 0
            readonly property real sideH: side.length ? Math.max(90, Math.min(sideHeight, 485, height - 91)) : 0
            // What's left for the speaker or the gallery.
            readonly property real mainX: 0
            readonly property real mainY: atTop ? sideH : 0
            readonly property real mainW: atTop ? width : width - sideW
            readonly property real mainH: atTop ? height - sideH : height
            // Speaker: one 16:9 tile, centred.
            MeetingTile {
                visible: tiles.speakerView && !tiles.featured && !tiles.content && !tiles.meOverlay
                call: win
                person: tiles.speaker || ({})
                width: Math.min(tiles.mainW, tiles.mainH * 16 / 9); height: width * 9 / 16
                x: tiles.mainX + (tiles.mainW - width) / 2; y: tiles.mainY + (tiles.mainH - height) / 2
            }
            // The focused or pin area: its people in a 16:9 grid.
            GalleryGrid {
                id: pinGrid
                visible: !!tiles.featured && !tiles.content && !tiles.meOverlay
                x: tiles.mainX; y: tiles.mainY; width: tiles.mainW; height: tiles.mainH
                call: win
                people: tiles.featuredList
            }
            // Gallery.
            GalleryGrid {
                id: galleryGrid
                visible: !tiles.speakerView && !tiles.content && !tiles.meOverlay
                x: tiles.mainX; y: tiles.mainY; width: tiles.mainW; height: tiles.mainH - tiles.pagerH
                onTileWChanged: win.galleryTileWidth = tileW
                call: win
                people: tiles.gallery
            }
            // Two people: the other person on the whole stage (Teams'
            // participant-speaker)...
            MeetingTile {
                visible: tiles.meOverlay
                call: win
                person: win.others[0] || ({})
                x: tiles.mainX; y: tiles.mainY; width: tiles.mainW; height: tiles.mainH
            }
            // ...and you over it (Teams' me-tile overlay, measured on winpc
            // 2026-11-10): 245 x 137, 5.6 from the right and 5.5 from the
            // bottom, a 2 px #F5F5F5 ring with radius 6, the name tag
            // without your name.
            Rectangle {
                visible: tiles.meOverlay
                z: 1
                width: 245; height: 137; radius: 6
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 5.6; bottomMargin: 5.5 }
                color: theme.hc("#F5F5F5", "#000000")
                MeetingTile {
                    anchors.fill: parent
                    call: win
                    person: win.selfEntry
                    overlay: true
                }
            }
            // Teams' video pages: ‹ n/m › centred under the tiles; 32 px
            // buttons (radius 4, 20 px chevrons, #242424; #BDBDBD when
            // there's no page that way) around the 14 px counter.
            Item {
                id: pager
                visible: tiles.pagerH > 0
                x: tiles.mainX; y: tiles.mainY + tiles.mainH - tiles.pagerH
                width: tiles.mainW; height: 34
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: [
                            { icon: "chevron-left-20", tip: qsTr("Previous page"), step: -1 },
                            { counter: true },
                            { icon: "chevron-right-20", tip: qsTr("Next page"), step: 1 }
                        ]
                        Item {
                            id: pagerItem
                            required property var modelData
                            readonly property bool enabledStep: !modelData.counter
                                && tiles.page + modelData.step >= 0 && tiles.page + modelData.step < tiles.pageCount
                            width: modelData.counter ? counterText.implicitWidth : 32
                            height: 34
                            Text {
                                id: counterText
                                visible: !!pagerItem.modelData.counter
                                y: 7; height: 20
                                verticalAlignment: Text.AlignVCenter
                                text: (tiles.page + 1) + "/" + tiles.pageCount
                                color: theme.hc("#252423", "#FFFFFF")
                                font.family: theme.font; font.pixelSize: 14
                            }
                            Rectangle {
                                id: hcFill4
                                visible: !pagerItem.modelData.counter
                                y: 2; width: 32; height: 32; radius: 4
                                color: pagerHover.hovered ? theme.hc("#F5F5F5", "#1AEBFF") : "transparent"
                                FluentIcon {
                                    anchors.centerIn: parent
                                    name: pagerItem.modelData.icon || ""
                                    color: theme.onFill(hcFill4, pagerItem.enabledStep ? theme.hc("#242424", "#FFFFFF") : theme.hc("#BDBDBD", "#3FF23F"))
                                }
                                HoverHandler { id: pagerHover; enabled: !pagerItem.modelData.counter }
                                TapHandler {
                                    enabled: pagerItem.enabledStep
                                    onTapped: win.galleryPage = tiles.page + pagerItem.modelData.step
                                }
                                ToolTip {
                                    visible: pagerHover.hovered && !pagerItem.modelData.counter; delay: 500
                                    y: parent.height + 4; padding: 8
                                    background: FluentSurface { depth: 16; radius: 4 }
                                    contentItem: Text { text: pagerItem.modelData.tip || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: (pagerItem.modelData.step < 0 ? qsTr("Navigate to previous video page. Currently %1/%2") : qsTr("Navigate to next video page. Currently %1/%2"))
                                    .arg(tiles.page + 1).arg(tiles.pageCount)
                            }
                        }
                    }
                }
            }
            // The shared content, as Teams' content tile: the main area,
            // inset 2, the screen fitted in it, the presenter's name tag.
            Item {
                id: contentTile
                visible: tiles.content
                x: tiles.mainX + 2; y: tiles.mainY + 2
                width: tiles.mainW - 4; height: tiles.mainH - 4
                clip: true
                // Presenter modes (Teams' weatherPerson state): the
                // presenter's camera composited with the screen, laid out
                // by Teams' arithmetic (presenter_mode.rs).
                readonly property var presenterEntry: win.roster.find(p => p.id === win.shareId) || null
                readonly property var wp: {
                    const s = presenterEntry ? presenterEntry.weather_person : ""
                    if (!s) return null
                    try { const l = JSON.parse(s); return l && l.mode && l.mode !== "ContentOnly" ? l : null } catch (e) { return null }
                }
                readonly property string camKey: wp ? (win.videoKeys[win.shareId] || "") : ""
                readonly property var comp: {
                    if (!wp || !camKey) return null
                    const ca = meetingShare.frameHeight > 0 ? meetingShare.frameWidth / meetingShare.frameHeight : 0
                    const pa = presenterCam.frameHeight > 0 ? presenterCam.frameWidth / presenterCam.frameHeight : 0
                    const r = backend.presenterLayout(JSON.stringify(wp), width, height, ca, pa)
                    return r ? JSON.parse(r) : null
                }
                // Side-by-side and Reporter: Add background's picture behind.
                Image {
                    visible: !!contentTile.comp && !!contentTile.wp && !!contentTile.wp.background && !!contentTile.wp.background.url
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: visible ? (contentTile.wp.background.url.startsWith("http") ? "" : "https://statics.teams.cdn.office.net") + contentTile.wp.background.url : ""
                }
                // Someone annotates the screen they share: their board, see-
                // through, over the picture (Teams' AnnotationOverlay).
                Loader {
                    id: annotationLayer
                    z: 3
                    x: meetingShare.x; y: meetingShare.y; width: meetingShare.width; height: meetingShare.height
                    readonly property var st: { try { return win.annotationViewed && win.annotationViewed.state ? JSON.parse(win.annotationViewed.state) : null } catch (e) { return null } }
                    readonly property string boardUrl: st && st.url ? st.url : ""
                    // The board the frame first loaded; later boards are posted
                    // to it (whiteboardUrlChanged).
                    property string loadedFor: ""
                    property string frameUrl: ""
                    active: !!win.annotationViewed && boardUrl !== "" && !win.contentShown
                    onActiveChanged: if (active) {
                        loadedFor = boardUrl
                        frameUrl = backend.contentBoardFrameUrl(boardUrl, false, JSON.stringify({ meetingType: String(win.contentMeetingType),
                            meetingTenantId: backend.tenantId(), participantTimestamp: String(Date.now()) }))
                    }
                    onBoardUrlChanged: if (item && loadedFor !== "" && boardUrl !== "" && boardUrl !== loadedFor) { loadedFor = boardUrl; item.sendFrameMessage("whiteboardUrlChanged", [boardUrl]) }
                    sourceComponent: WebApp {
                        transparentPage: true
                        showHeader: false
                        appName: "Whiteboard"
                        appId: "95de633a-083e-42f5-b444-a4295d8e9314"
                        location: win.peer
                        home: annotationLayer.frameUrl
                        teamsHost: true
                        deepNaa: false
                        frameContext: "meetingStage"
                        hostThread: backend.callThreadId
                        hostContext: ({ entityId: "", subEntityId: "" })
                    }
                }
                // A Whiteboard, PowerPoint Live or Excel Live share: the
                // session's page (ContentStage.qml), over the screen share.
                ContentStage {
                    id: contentStage
                    visible: win.contentShown
                    z: 2
                    anchors.fill: parent
                    // (Popped out, the session's page moves to that window.)
                    session: win.contentPoppedOut ? null : win.contentSession
                    board: win.contentState.board || ""
                    meetingType: win.contentMeetingType
                    thread: backend.callThreadId
                    title: win.peer
                    presenterName: win.contentSession ? (win.contentSession.mine ? win.selfName : win.contentSession.presenterName) : ""
                    attendees: win.others.length + 1
                    pptLayout: win.pptStageLayout
                    pptCameoKey: win.pptCameoKey
                    onPptNavigated: state => backend.contentShareState(state)
                    onBoardReported: (url, passThrough) => {
                        backend.contentShareState(JSON.stringify(passThrough !== undefined && passThrough !== null
                            ? { url: url, passThrough: passThrough } : { url: url }))
                        backend.contentSaveBoard(win.contentKind, url)
                    }
                }
                VideoFrame {
                    id: meetingShare
                    source: "share"
                    fit: true
                    letterbox: false
                    readonly property var area: contentTile.comp ? contentTile.comp.content : null
                    x: area ? area.x * contentTile.width : 0
                    y: area ? area.y * contentTile.height : 0
                    width: area ? area.width * contentTile.width : contentTile.width
                    height: area ? area.height * contentTile.height : contentTile.height
                    Timer {
                        interval: 33; repeat: true
                        running: win.visible && contentTile.visible
                        onTriggered: { meetingShare.refresh(); if (contentTile.camKey) presenterCam.refresh() }
                    }
                }
                VideoFrame {
                    id: presenterCam
                    visible: !!contentTile.comp
                    source: contentTile.camKey
                    fit: !!contentTile.comp && !contentTile.comp.crop
                    letterbox: false
                    readonly property var area: contentTile.comp ? contentTile.comp.presenter : null
                    x: area ? area.x * contentTile.width : 0
                    y: area ? area.y * contentTile.height : 0
                    width: area ? area.width * contentTile.width : 0
                    height: area ? area.height * contentTile.height : 0
                }
                // In control of the presenter's screen: our mouse and keys
                // go to it (Teams' control capturer: positions over the
                // picture from 0 to 65535, moves at most every 30–50 ms).
                MouseArea {
                    id: controlArea
                    readonly property bool active: win.controlState.state === "controlling"
                    enabled: active
                    visible: active
                    x: meetingShare.x; y: meetingShare.y; width: meetingShare.width; height: meetingShare.height
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.ArrowCursor
                    focus: active
                    // The picture inside the frame (fitted, letterboxed).
                    readonly property real fw: meetingShare.frameWidth > 0 ? meetingShare.frameWidth : width
                    readonly property real fh: meetingShare.frameHeight > 0 ? meetingShare.frameHeight : height
                    readonly property real pictureScale: Math.min(width / fw, height / fh)
                    readonly property real px: (width - fw * pictureScale) / 2
                    readonly property real py: (height - fh * pictureScale) / 2
                    property real lastMove: 0
                    function nx(mx) { return (mx - px) / (fw * pictureScale) }
                    function ny(my) { return (my - py) / (fh * pictureScale) }
                    function inside(mx, my) { const x = nx(mx), y = ny(my); return x >= 0 && x < 1 && y >= 0 && y < 1 }
                    function button(b) { return b === Qt.RightButton ? 1 : b === Qt.MiddleButton ? 2 : 0 }
                    onPositionChanged: mouse => {
                        if (!inside(mouse.x, mouse.y)) return
                        const now = Date.now()
                        if (now - lastMove < (pressed ? 30 : 50)) return
                        lastMove = now
                        backend.controlMouse(0, 0, false, nx(mouse.x), ny(mouse.y), 0)
                    }
                    onPressed: mouse => { forceActiveFocus(); if (inside(mouse.x, mouse.y)) backend.controlMouse(2, button(mouse.button), true, nx(mouse.x), ny(mouse.y), 0) }
                    onReleased: mouse => { if (inside(mouse.x, mouse.y)) backend.controlMouse(2, button(mouse.button), false, nx(mouse.x), ny(mouse.y), 0) }
                    onWheel: wheel => backend.controlMouse(1, 0, false, nx(wheel.x), ny(wheel.y), wheel.angleDelta.y > 0 ? 120 : -120)
                    Keys.onPressed: event => { backend.controlKey(event.key, event.nativeScanCode, false, event.isAutoRepeat); event.accepted = true }
                    Keys.onReleased: event => { if (!event.isAutoRepeat) backend.controlKey(event.key, event.nativeScanCode, true, false); event.accepted = true }
                }
                Rectangle {
                    id: hcFill5
                    visible: !win.contentShown
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 8 }
                    height: 24; radius: 4
                    width: contentName.implicitWidth + 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { id: contentName; x: 6; anchors.verticalCenter: parent.verticalCenter; text: win.presenterName; color: theme.onFill(hcFill5, "white"); font.family: theme.font; font.pixelSize: 14 }
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("%1 is presenting").arg(win.presenterName)
            }
            // The side gallery.
            Grid {
                visible: tiles.side.length > 0
                columns: tiles.atTop ? tiles.side.length : 1
                x: tiles.atTop ? (tiles.width - tiles.side.length * slotW) / 2 : tiles.width - tiles.sideW
                y: tiles.atTop ? 0 : (tiles.height - tiles.side.length * slotH) / 2
                readonly property real slotW: tiles.atTop ? tiles.sideH * 16 / 9 : tiles.sideW
                readonly property real slotH: slotW * 9 / 16
                Repeater {
                    model: tiles.visible ? tiles.side : []
                    MeetingTile {
                        required property var modelData
                        call: win
                        person: modelData
                        // Side gallery tiles are small: Teams drops the
                        // names from their tags.
                        compact: true
                        width: parent.slotW; height: parent.slotH
                    }
                }
            }
            // Teams' "Resize side gallery" / "Resize top gallery" divider.
            Item {
                visible: tiles.side.length > 0
                x: tiles.atTop ? 0 : tiles.width - tiles.sideW - 2
                y: tiles.atTop ? tiles.sideH - 3 : 0
                width: tiles.atTop ? tiles.width : 5
                height: tiles.atTop ? 5 : tiles.height
                Rectangle {
                    x: tiles.atTop ? 0 : 2; y: tiles.atTop ? 2 : 0
                    width: tiles.atTop ? parent.width : 1; height: tiles.atTop ? 1 : parent.height
                    color: theme.hc("#D1D1D1", "#000000")
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: tiles.atTop ? Qt.SizeVerCursor : Qt.SizeHorCursor
                    property real start
                    property real startSize
                    onPressed: m => { const p = mapToItem(tiles, m.x, m.y); start = tiles.atTop ? p.y : p.x; startSize = tiles.atTop ? tiles.sideH : tiles.sideW }
                    onPositionChanged: m => {
                        const p = mapToItem(tiles, m.x, m.y)
                        if (tiles.atTop) tiles.sideHeight = startSize + (p.y - start)
                        else tiles.sideWidth = startSize - (p.x - start)
                    }
                }
                Accessible.role: Accessible.Slider
                Accessible.name: tiles.atTop ? qsTr("Resize top gallery") : qsTr("Resize side gallery")
                activeFocusOnTab: true
                Keys.onLeftPressed: tiles.sideWidth = tiles.sideW + 16
                Keys.onRightPressed: tiles.sideWidth = tiles.sideW - 16
                Keys.onUpPressed: tiles.sideHeight = tiles.sideH - 9
                Keys.onDownPressed: tiles.sideHeight = tiles.sideH + 9
            }
        }
        // Their video, filling the stage, once frames arrive; while they
        // share their screen it moves to a small tile (as in Teams).
        VideoFrame {
            id: remoteVideo
            source: "remote"
            readonly property bool small: shareVideo.visible
            anchors.fill: small ? undefined : parent
            x: small ? parent.width - width - 12 : 0; y: small ? 12 : 0
            width: small ? 240 : parent.width; height: small ? 135 : parent.height
            z: small ? 3 : 0
            visible: hasFrame && !win.meeting && win.state === "connected" && !win.incomingVideoOff && !win.held && !win.heldByPeer
        }
        // Their shared screen takes the stage, fitted (not cropped).
        VideoFrame {
            id: shareVideo
            source: "share"
            fit: true
            anchors.fill: parent
            z: 1
            visible: !win.meeting && hasFrame && win.state === "connected" && !win.held && !win.heldByPeer
        }
        Rectangle {
            visible: shareVideo.visible
            z: 2
            anchors { left: parent.left; top: parent.top; margins: 12 }
            width: shareText.implicitWidth + 16; height: 28; radius: 4
            color: theme.hc("#CC000000", "#000000")
            Text { id: shareText; anchors.centerIn: parent; text: qsTr("%1 is presenting").arg(win.peer); color: "white"; font.family: theme.font; font.pixelSize: theme.small }
        }
        Timer {
            interval: 33; repeat: true
            running: win.visible && win.state === "connected"
            onTriggered: { remoteVideo.refresh(); shareVideo.refresh() }
        }
        // While you share, as Teams: a red-outlined "You're presenting".
        Rectangle {
            visible: win.sharing
            z: 4
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
            width: presentingRow.implicitWidth + 24; height: 32; radius: 4
            color: theme.surface; border.color: theme.leave; border.width: 2
            Row {
                id: presentingRow
                anchors.centerIn: parent; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "share-screen"; size: 16; color: theme.leave }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("You're presenting"); color: theme.text; font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold }
            }
        }
        Column {
            visible: !win.meeting && !remoteVideo.visible && !shareVideo.visible
            anchors.centerIn: parent
            spacing: 24
            Avatar { ring: false; size: 144; name: win.peer; photoId: backend.callPeerId; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.state === "calling" ? qsTr("Calling…")
                    : win.state === "connecting" ? qsTr("Connecting...", "calling:kdya2sghq")
                    : win.state === "ended" ? qsTr("Call ended")
                    : win.held || win.heldByPeer ? ""
                    : !win.hasAudio ? qsTr("Connected without audio") : ""
                visible: text.length > 0
                color: theme.text
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            // Teams: "On hold 00:14" under the avatar for the one holding,
            // plain "On hold" for the one held.
            Row {
                visible: (win.held || win.heldByPeer) && win.live
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "pause"; size: 20; color: theme.text }
                Text {
                    text: win.held ? qsTr("On hold") + " " + win.clock(win.heldSeconds) : qsTr("On hold")
                    color: theme.text
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
            }
        }
        // Their name chip, bottom left
        Rectangle {
            visible: !win.meeting
            z: 2
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            width: nameText.implicitWidth + 12; height: 24; radius: 4
            color: theme.hc("#99000000", "#000000")
            Text {
                id: nameText
                anchors.centerIn: parent
                text: win.peer
                color: "white"
                font.family: theme.font; font.pixelSize: theme.small
            }
        }
        // Your own tile, bottom right, in a 1:1 call (meetings have you as
        // a tile, or alone with your video on, on the whole stage)
        Rectangle {
            visible: !win.meeting
            z: 2
            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
            width: 240; height: 134; radius: 6
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.hc("#F6EEF2", "#000000") }
                GradientStop { position: 1.0; color: theme.hc("#EEF0F8", "#000000") }
            }
            border.color: theme.dividerSoft
            Avatar { ring: false; visible: !selfVideo.visible; anchors.centerIn: parent; size: 64; name: win.selfName || qsTr("You"); photoId: "me" }
            ReactionShown { z: 3; mri: win.selfId }
            // Your camera, mirrored as Teams shows your own video.
            VideoFrame {
                id: selfVideo
                source: "self"
                anchors.fill: parent; anchors.margins: 1
                visible: win.cameraOn && hasFrame
                transform: Scale { origin.x: selfVideo.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
            }
            Timer {
                interval: 66; repeat: true
                running: win.visible && win.cameraOn
                onTriggered: selfVideo.refresh()
            }
            Rectangle {
                visible: win.muted || !win.hasAudio
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                width: 28; height: 24; radius: 4
                color: theme.hc("#99000000", "#000000")
                FluentIcon { anchors.centerIn: parent; name: "mic-off-24"; size: 16; color: "white" }
            }
        }
    }

    // Side pane: the chat with them, or the people in the call.
    property alias chatPane: chatPane
    property alias meetingNotesPaneForTest: meetingNotesPane
    Rectangle {
        id: sidePane
        visible: win.side !== ""
        // Teams' calling-right-side-panel: 360 wide, flush with the window.
        anchors { top: bar.bottom; right: parent.right; bottom: parent.bottom }
        // Teams' end slot (app-layout-area--end) by window width: 32rem
        // under 947, 36rem to 1439, 42rem to 1679, 48rem to 1919, then 60rem
        // (its layout map; measured 360 at 1280 for Copilot and the panes).
        width: win.width < 947 ? 320 : win.width < 1440 ? 360 : win.width < 1680 ? 420 : win.width < 1920 ? 480 : 600
        color: win.side === "people" || win.side === "info" || win.side === "audio" || win.side === "transcript" || win.side === "captionStyles" || win.side === "accessibility" || win.side === "callHealth" || win.side === "rooms" || win.side === "video" || win.side === "notes" ? theme.pane : theme.surface
        clip: true
        Conversation {
            id: chatPane
            visible: win.side === "chat" && (win.chatTab === "everyone" || !win.lobbyTabShown)
            anchors.fill: parent; anchors.margins: 1
            pane: true
            paneTabs: win.lobbyTabShown ? win.chatTabs : []
            paneTab: win.chatTab
            onPaneTabPicked: key => win.chatTab = key
            onClosePane: win.side = ""
        }
        // Teams' Lobby tab: the meeting's lobby chat thread, live as a chat
        // window's, sent to through the chat window path.
        Conversation {
            id: lobbyPane
            visible: win.side === "chat" && win.lobbyTabShown && win.chatTab === "lobby"
            anchors.fill: parent; anchors.margins: 1
            pane: true; popout: true
            chatId: backend.callLobbyThread
            chatName: qsTr("Lobby")
            myName: backend.userName
            isGroup: true
            messages: win.lobbyMessages
            paneTabs: win.chatTabs
            paneTab: win.chatTab
            onPaneTabPicked: key => win.chatTab = key
            onClosePane: win.side = ""
            emptyTitle: qsTr("Messages you send to people waiting in the lobby will show up here.")
            // Teams' banners: the awareness note while someone waits, else
            // the compose is off with "Chat will be available…".
            composeTextOnly: true
            composeDisabled: win.lobby.length === 0
            composeNoteMuted: win.lobby.length === 0
            composeNote: win.lobby.length === 0 ? qsTr("Chat will be available when someone is waiting in the lobby.")
                : qsTr("Messages you send are only visible to people currently in the lobby. They can view messages but not reply.")
            onReact: (id, key, on) => backend.toggleReaction(id, key, on)
            onEditMessage: (id, text) => backend.editMessage(id, text)
            onDeleteMessage: id => backend.deleteMessage(id)
        }
        VideoEffectsPane {
            id: videoEffectsPane
            visible: win.side === "video"
            anchors.fill: parent
            cameraOn: win.cameraOn
            onClosed: win.side = ""
            onTurnOnVideo: if (!win.cameraOn) win.runControl("VideoButton")
            onTurnOffVideo: if (win.cameraOn) win.runControl("VideoButton")
            onGreenScreenSettings: win.greenScreenSettings()
        }
        // Copilot (Teams' copilot side pane: 320 wide; a 44 tall header
        // with the Copilot mark (20) 24.7 in, "Copilot" 14/600 at 49.7
        // and Close Copilot (32 x 31.3) 24 from the end; the app below).
        Item {
            id: copilotPane
            visible: win.side === "copilot"
            anchors.fill: parent
            Rectangle {
                id: copilotHeader
                width: parent.width; height: 44; color: theme.surface
                FluentIcon { x: 24.7; y: 11.7; size: 20; name: "copilot-color-48"; color: theme.text }
                Text {
                    x: 49.7; y: 11.7; height: 20; verticalAlignment: Text.AlignVCenter
                    text: qsTr("Copilot")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                BarButton {
                    x: parent.width - 56; y: 6; width: 32; height: 31.3
                    icon: "dismiss-20"; label: ""; tip: ""
                    onClicked: win.side = ""
                    Accessible.name: qsTr("Close Copilot")
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
            }
            Loader {
                id: copilotLoader
                anchors { top: copilotHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                active: !!win.copilotLaunch
                sourceComponent: WebApp {
                    showHeader: false; teamsHost: true; deepNaa: true
                    appName: "Copilot"; appId: "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162"
                    frameContext: "sidePanel"
                    // Teams desktop server-renders the pane's first page
                    // (it posts the app's token with the address; the app
                    // then reports renderMode "SSR"), and offers it the
                    // Copilot eligibility, performance and mouse relay
                    // capabilities (measured 2026-11-18).
                    ssr: true
                    runtimeSupports: ({ appPerformanceMetrics: {}, copilot: { eligibility: {} }, mouseRelay: {} })
                    // Teams' meeting window's shortcuts, as it lists them to
                    // the pane (measured 2026-11-18).
                    hostShortcuts: ["ctrl+.", "alt+/", "ctrl+e", "ctrl+/", "ctrl+shift+/", "ctrl+shift+7", "ctrl+g", "ctrl+n", "ctrl+shift+n", "ctrl+shift+f", "ctrl+,", "f1", "ctrl++", "ctrl+=", "ctrl+-", "ctrl+_", "ctrl+0", "ctrl+alt+shift+r", "alt+q", "ctrl+shift+t", "ctrl+\\", "ctrl+1", "ctrl+2", "ctrl+3", "ctrl+4", "ctrl+5", "ctrl+6", "ctrl+7", "ctrl+8", "ctrl+9", "ctrl+l", "ctrl+m", "ctrl+alt+t", "f6", "shift+f6", "ctrl+f6", "ctrl+shift+f6", "alt+left", "alt+right", "ctrl+h", "shift+esc", "f", "p", "del", "s", "r", "t", "e", "u", "q", "ctrl+j", "ctrl+o", "ctrl+alt+r", "alt+p", "alt+c", "alt+shift+r", "alt+1", "alt+2", "alt+3", "alt+4", "alt+5", "alt+6", "alt+7", "alt+8", "alt+9", "ctrl+alt+z", "ctrl+alt+u", "ctrl+alt+q", "ctrl+alt+b", "ctrl+alt+c", "ctrl+alt+a", "alt+pagedown", "alt+pageup", "ctrl+alt+down", "ctrl+alt+up", "ctrl+shift+s", "ctrl+shift+j", "ctrl+shift+r", "alt+shift+v", "f11", "ctrl+shift+p", "alt+shift++", "alt+shift+=", "alt+shift+-", "alt+shift+_", "alt+shift+0", "ctrl+f", "ctrl+alt+f", "ctrl+alt+w", "ctrl+alt+q", "ctrl+alt+enter", "ctrl+shift+enter", "ctrl+shift+a", "ctrl+shift+a", "ctrl+shift+a", "ctrl+shift+d", "ctrl+shift+d", "meta+shift+y", "alt+shift+a", "ctrl+shift+e", "ctrl+shift+space", "ctrl+shift+m", "ctrl+shift+u", "ctrl+shift+o", "ctrl+shift+y", "ctrl+shift+h", "ctrl+shift+k", "alt+shift+c", "ctrl+shift+l", "ctrl+alt+shift+s", "ctrl+space", "ctrl+alt+shift+1", "shift+esc", "ctrl+alt+k", "ctrl+alt+u", "ctrl+alt+m", "ctrl+alt+c", "alt+t", "alt+l", "ctrl+alt+shift+2", "ctrl+alt+shift+8"]
                    hostThread: backend.callThreadId
                    hostContext: win.copilotLaunch.context
                    home: win.copilotLaunch.url
                    // Teams tells the app the meeting once it is up.
                    onHostEvent: (name, json) => { if (name === "ChatReady") win.sendCopilotContext() }
                }
            }
        }
        AudioSettingsPane {
            id: audioSettingsPane
            visible: win.side === "audio"
            roomAudio: win.roomDeviceJoined
            // Teams' P2P call type (as the Mic flyout's).
            oneToOne: !win.meeting && !win.testCall
            anchors.fill: parent
            muted: win.muted || !win.hasAudio
            onToggleMute: win.toggleMute()
            onClosed: win.side = ""
        }
        TranscriptPane {
            id: transcriptPane
            visible: win.side === "transcript"
            anchors.fill: parent
            entries: win.transcript
            roster: win.people
            meId: backend.userMri
            meName: backend.userName
            filterProfanity: win.accessibility.profanityFilterEnabled === true
            captionsAvailable: !win.captionsOn
            onClosed: win.side = ""
            // Teams turns captions on and closes the pane.
            onSwitchToCaptions: { win.setCaptions(true); win.side = "" }
        }
        AccessibilityPane {
            id: accessibilityPane
            visible: win.side === "accessibility"
            anchors.fill: parent
            accessibility: win.accessibility
            showMutedNotice: win.showMutedNotice
            onClosed: win.side = ""
            onUpdateAccessibility: patch => win.updateAccessibility(patch)
            onMutedNoticeToggled: on => win.setShowMutedNotice(on)
        }
        BreakoutRoomsPane {
            id: roomsPane
            visible: win.side === "rooms"
            anchors.fill: parent
            rooms: win.breakoutRooms
            people: win.people.filter(p => !p.you).map(p => ({ id: p.id, name: p.name, role: p.role || "", guest: !!p.guest }))
            names: win.breakoutNames
            settings: win.breakoutSettings
            busy: win.breakoutBusy
            onClosed: win.side = ""
            onCreateRooms: (count, mode) => win.createBreakoutRooms(count, mode)
            onImportCsv: win.importBreakoutCsv()
            onAssignParticipants: assignRooms.show()
            onOpenRooms: win.breakoutRun("open", { threads: win.breakoutRooms.filter(r => (r.invitees || []).length > 0).map(r => r.thread) })
            onCloseRooms: win.breakoutRun("close", { threads: win.breakoutRooms.filter(r => r.open).map(r => r.thread) })
            onAddRoom: win.breakoutRun("add", { name: win.nextRoomName() })
            onAnnounce: { roomText.rename = false; roomText.title = qsTr("Announcement"); roomText.initial = ""; roomText.placeholder = qsTr("Make an announcement"); roomText.thread = ""; roomText.show() }
            onRemoveRooms: removeRoomsAsk.open()
            onSaveSettings: s => win.breakoutRun("settings", s)
            onRoomAction: (action, room) => {
                if (action === "join") win.joinRoomAsOrganizer(room)
                else if (action === "open" || action === "close") win.breakoutRun(action, { threads: [room.thread] })
                else if (action === "rename") { roomText.rename = true; roomText.title = qsTr("Rename %1?").arg(room.name); roomText.initial = room.name; roomText.placeholder = ""; roomText.thread = room.thread; roomText.show() }
                else if (action === "delete") { deleteRoomAsk.thread = room.thread; deleteRoomAsk.title = qsTr("Delete %1?").arg(room.name); deleteRoomAsk.open() }
            }
        }
        CallHealthPane {
            id: callHealthPane
            visible: win.side === "callHealth"
            anchors.fill: parent
            health: win.callHealth
            onClosed: win.side = ""
            onRefresh: win.refreshCallHealth()
        }
        CaptionStylesPane {
            id: captionStylesPane
            visible: win.side === "captionStyles"
            anchors.fill: parent
            styles: win.captionStyles
            onClosed: win.side = ""
            onChanged: s => win.saveCaptionStyles(s)
        }
        // Q&A (Teams' YammerQnaButton): Viva Engage's meeting Q&A, the page
        // Teams hosts in its side pane, with the call and the template.
        Loader {
            id: qnaPaneLoader
            active: win.side === "qna"
            visible: active
            anchors.fill: parent
            sourceComponent: WebApp {
                showHeader: false; appName: "Q&A"; appId: "5db56dd0-534d-467b-aeda-d622bee2574a"; location: win.peer
                home: win.qnaUrl(); teamsHost: true; deepNaa: false; hostThread: backend.callThreadId
                hostContext: ({ entityId: "", subEntityId: "" })
            }
        }
        MeetingNotesPane {
            id: meetingNotesPane
            visible: win.side === "notes"
            anchors.fill: parent
            onClosed: win.side = ""
        }
        MeetingInfoPane {
            id: meetingInfoPane
            visible: win.side === "info"
            anchors.fill: parent
            info: win.meetingInfo
            onClosed: win.side = ""
            onCopyJoinInfo: win.copyMeetingJoinInfo()
        }
        PeoplePane {
            id: peoplePane
            visible: win.side === "people"
            anchors.fill: parent
            people: win.people
            chatMembers: win.chatMembers
            lobby: win.lobby
            lobbyChatAvailable: win.lobbyChatAvailable
            onChatLobby: win.openLobbyChat()
            meeting: win.meeting
            managed: !!win.liveEvent.managed
            onClosed: win.side = ""
            onAdmit: (id, name) => win.admitLobby(id, name, false)
            onAdmitSuspected: (id, name) => admitAsk.ask(id, name)
            onDeny: (id, name) => win.denyLobby(id, name)
            onAdmitAll: win.admitAllLobby()
            onAdmitEach: list => list.forEach(p => win.admitLobby(p.id, p.name, false))
            onDenyEach: list => list.forEach(p => win.denyLobby(p.id, p.name))
            inviteUrl: win.inviteUrl
            canMuteAll: win.canMuteAll
            onMuteAll: muteAllAsk.open()
            canManage: win.organizer
            canReport: win.scheduled || win.adhocMeeting
            pinnedIds: win.pinnedIds
            pinningFull: win.pinningFull
            onParticipantAction: (action, id, name, stateId) => {
                if (action === "pin") win.pinPerson(id)
                else if (action === "unpin") win.unpinPerson(id)
                // Teams asks "Change role?" first.
                else if (action === "attendee" || action === "presenter") roleAsk.ask(action, id, name)
                // Report this person: Teams' report dialog for them.
                else if (action === "report") win.openPersonReport(id, name)
                else win.participantAction(action, id, name, stateId)
            }
            onShareInvite: inviteDialog.open()
            moreItems: win.moreItems
            onMoreAction: k => win.runMoreAction(k)
            handOrder: win.hands
            selfKey: win.selfId
        }
    }

    // Teams asks before admitting a guest its join shield flagged.
    AdmitSuspectedDialog {
        id: admitAsk
        onAdmit: (id, name, notBot) => win.admitLobby(id, name, notBot)
        onDeny: (id, name) => win.denyLobby(id, name)
    }

    // The lobby notification, 8 px below the top of the stage, centred on it.
    // Optimize for room: the shared display window, and the notice here.
    property bool roomNoticeDismissed: false
    /// Joined with a connected room device (Teams' BYOD Room audio): its
    /// "Connected to a room device" notice shows for the call.
    property bool roomDeviceJoined: false
    /// Teams explains the shared display only the first three times
    /// (its byodSdmUfdTriggerCount); later the notice is the title alone.
    property bool roomNoticeBody: true
    property bool roomNoticeCounted: false
    function showRoomNotice() {
        roomNoticeDismissed = false
        if (roomNoticeCounted) return
        roomNoticeCounted = true
        const n = parseInt(backend.setting("byodSdmUfdTriggerCount") || "0") || 0
        roomNoticeBody = n < 3
        if (n < 3) backend.setSetting("byodSdmUfdTriggerCount", String(n + 1))
    }
    onRoomModeChanged: if (roomMode) showRoomNotice()
    Loader {
        id: roomLoader
        active: win.roomMode
        sourceComponent: Component { SharedDisplayWindow { call: win; visible: true } }
    }
    readonly property var roomWindow: roomLoader.item
    // Pop out: Teams' "Shared content | <meeting>" window, the screen
    // fitted on the stage with the presenter's name tag; closing it docks
    // the content again.
    Loader {
        active: win.contentPoppedOut
        sourceComponent: Component {
            Window {
                title: qsTr("Shared content | %1").arg(win.peer) + " | OST"
                width: 1280; height: 680
                visible: true
                color: theme.hc("#F5F5F5", "#000000")
                onClosing: win.contentPoppedOut = false
                // A Whiteboard, PowerPoint Live or Excel Live share pops out
                // with its page.
                ContentStage {
                    visible: win.contentShown
                    z: 2
                    x: 2.67; y: 2.67; width: parent.width - 5.33; height: parent.height - 5.33
                    session: win.contentSession
                    board: win.contentState.board || ""
                    meetingType: win.contentMeetingType
                    thread: backend.callThreadId
                    title: win.peer
                    presenterName: win.contentSession ? (win.contentSession.mine ? win.selfName : win.contentSession.presenterName) : ""
                    attendees: win.others.length + 1
                    pptLayout: win.pptStageLayout
                    pptCameoKey: win.pptCameoKey
                    onPptNavigated: state => backend.contentShareState(state)
                    onBoardReported: (url, passThrough) => {
                        backend.contentShareState(JSON.stringify(passThrough !== undefined && passThrough !== null
                            ? { url: url, passThrough: passThrough } : { url: url }))
                        backend.contentSaveBoard(win.contentKind, url)
                    }
                }
                VideoFrame {
                    id: poppedShare
                    x: 2.67; y: 2.67; width: parent.width - 5.33; height: parent.height - 5.33
                    source: "share"
                    fit: true
                    letterbox: false
                    Timer { interval: 33; repeat: true; running: true; onTriggered: poppedShare.refresh() }
                }
                Rectangle {
                    id: hcFill6
                    x: 10.67; anchors.bottom: parent.bottom; anchors.bottomMargin: 10.67
                    height: 24; radius: 4
                    width: poppedName.implicitWidth + 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { id: poppedName; x: 6; anchors.verticalCenter: parent.verticalCenter; text: win.presenterName; color: theme.onFill(hcFill6, "white"); font.family: theme.font; font.pixelSize: 14 }
                }
            }
        }
    }
    function closeMenusForTest() { viewMenu.close(); controlsMenu.close(); moreMenu.close(); newMore.close(); reactMenu.close(); arrangeMenu.close(); cellMenu.close(); videoFlyout.close(); audioFlyout.close(); peoplePane.closeMenusForTest() }
    function newMoreSubForTest(i) { newMore.openSubmenuForTest(i) }
    /// For the --join-view harness: open the View menu (and a submenu row).
    function viewMenuForTest(sub) {
        viewMenu.parent = barItem("ViewModeButton")
        viewMenu.open()
        if (sub >= 0) viewMenuSubTimer.sub = sub, viewMenuSubTimer.start()
    }
    Timer {
        id: viewMenuSubTimer
        property int sub: -1
        interval: 300
        onTriggered: viewMenu.openSubmenuForTest(sub)
    }
    RoomNotice {
        visible: (win.roomMode || win.roomDeviceJoined) && !win.roomNoticeDismissed
        body: win.roomNoticeBody
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        onDismissed: win.roomNoticeDismissed = true
    }
    MutedNotice {
        visible: win.mutedNoticeShown
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        onDismissed: win.mutedNoticeShown = false
        onUnmute: { win.mutedNoticeShown = false; win.toggleMute() }
    }
    MutedNotice {
        visible: win.speakingNoticeShown && !win.mutedNoticeShown
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        title: qsTr("Your microphone is muted")
        text: qsTr("Press %1 to unmute your mic, or press and hold down %2.").arg("Ctrl+Shift+M").arg("Ctrl+Space")
        action: ""
        onDismissed: win.speakingNoticeClosed = true
    }
    // Report a concern sent: Teams says "Your report was sent" (its shell
    // toast; shown here as the meeting's notice card, its layout not yet
    // measured: that takes a real report).
    MutedNotice {
        visible: win.reportSent
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        icon: "checkmark-circle-20-filled"
        title: qsTr("Your report was sent")
        text: ""
        action: ""
        onDismissed: win.reportSent = false
    }
    // Teams' MeetingLocked / MeetingUnlocked alerts (ufd_MeetingLocked):
    // the notice card with the filled lock, for 10 s.
    property bool lockNoticeShown: false
    onLockNoticesChanged: if (lockNotices > 0) { lockNoticeShown = true; lockNoticeTimer.restart() }
    Timer { id: lockNoticeTimer; interval: 10000; onTriggered: win.lockNoticeShown = false }
    MutedNotice {
        visible: win.lockNoticeShown
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        icon: "lock-closed-20-filled"
        title: win.locked ? qsTr("This meeting is locked.") : qsTr("This meeting is unlocked.")
        text: win.locked ? qsTr("No one else can join.") : qsTr("People can join.")
        action: ""
        onDismissed: win.lockNoticeShown = false
    }
    MutedNotice {
        visible: win.recorderFailure.length > 0
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        icon: "alert-warning-16-filled"
        title: win.recorderFailure
        text: ""
        action: ""
        onDismissed: win.recorderFailure = ""
    }
    // Teams' breakout rooms alerts ("Breakout rooms have been created.",
    // "We'll move you to your assigned room in 10 seconds." …).
    property var breakoutAlert: null
    function showBreakoutAlert(text, icon) { breakoutAlert = { text: text, icon: icon || "" }; breakoutAlertTimer.restart() }
    Timer { id: breakoutAlertTimer; interval: 10000; onTriggered: win.breakoutAlert = null }
    // The room you're assigned to opened (no automatic move): Teams'
    // "Join breakout room?" invite, until Later, Join room, or the room
    // closing or a move (Main.qml).
    property var breakoutInvite: null
    // Room mode: Teams Rooms' auto exit once the meeting is over and the
    // room is alone. The end comes from the meeting's details, else the
    // room's calendar entry for the meeting's chat.
    RoomAutoExit {
        readonly property var entry: {
            if (!backend.roomMode || !backend.callThreadId) return null
            let evs = []
            try { evs = JSON.parse(backend.calendarJson || "[]") } catch (e) {}
            return evs.find(ev => ev.join_url && decodeURIComponent(ev.join_url).indexOf(backend.callThreadId) >= 0) || null
        }
        active: backend.roomMode && win.meeting && backend.callState === "connected"
        alone: win.others.filter(p => p.active !== false).length === 0
        // The meeting's scheduled end: its details, else the room's calendar.
        endMs: backend.roomMeetingEnd ? Date.parse(backend.roomMeetingEnd) : entry ? Date.parse(entry.end_utc) : 0
        adhoc: !backend.roomMeetingEnd && !entry
        onLeave: backend.hangUp()
    }
    BreakoutInviteAlert {
        visible: !!win.breakoutInvite && !win.breakoutAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        roomName: win.breakoutInvite ? win.breakoutInvite.name : ""
        onLater: win.breakoutInvite = null
        onJoin: { win.breakoutInvite = null; win.joinBreakoutRoom() }
    }
    // PowerPoint Live taken over (Teams' PptSharingStolen warning):
    // "Another user took control" / "{name} is now in control of the
    // presentation." with Take back (takes it again).
    property string pptTakenDismissed: ""
    CallAlert {
        readonly property string takenBy: win.contentState.takenBy || ""
        visible: takenBy !== "" && win.pptTakenDismissed !== takenBy && !win.breakoutAlert && win.pptViewed
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        icon: "warning-20-filled"
        title: qsTr("Another user took control")
        text: qsTr("%1 is now in control of the presentation.").arg(takenBy)
        actionText: qsTr("Take back")
        onAction: { win.pptTakenDismissed = takenBy; backend.contentTakeControl(win.contentSession.correlationId) }
        onDismissed: win.pptTakenDismissed = takenBy
    }
    // Teams' "Add interpreters for your meetings" (SignerMixin's
    // openInterpretersNotSelectedUfd: INTERPRETERS_NOT_SELECTED, a
    // dismissable Warning for 8 s). Its type has no entry in Teams' alert
    // icon map (263640) and it passes none, so it shows no glyph; its text
    // is calling's interpreters_not_selected_text, with "Accessibility" at
    // 600 and the Learn more link.
    CallAlert {
        id: signAlert
        function show() { visible = true; signAlertTimer.restart(); console.warn("SIGN alert shown") }
        visible: false
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        title: qsTr("Add interpreters for your meetings")
        richText: true
        text: qsTr("Select interpreters in your <span style=\"font-weight: 600;\">Accessibility</span> settings for Sign language mode to work correctly. <a href=\"https://go.microsoft.com/fwlink/?linkid=2330204\" target=\"_blank\">Learn more</a>")
        onDismissed: visible = false
        Timer { id: signAlertTimer; interval: 8000; onTriggered: signAlert.visible = false }
    }
    CallAlert {
        visible: !!win.breakoutAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        text: win.breakoutAlert ? win.breakoutAlert.text : ""
        icon: win.breakoutAlert ? win.breakoutAlert.icon : ""
        onDismissed: win.breakoutAlert = null
    }
    LobbyToast {
        id: lobbyToast
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 5
        lobby: win.lobby
        rosterOpen: win.side === "people"
        onAdmit: (id, name) => win.admitLobby(id, name, false)
        onDeny: (id, name) => win.denyLobby(id, name)
        onViewLobby: win.side = "people"
        chatAvailable: win.lobbyChatAvailable
        onChatLobby: win.openLobbyChat()
    }
    // Leave's options (hangup-button-more-options-menu, measured): a
    // surface right-aligned to the chevron, 6 below it, padding 16, a 0.67
    // edge; 32 px items 2 apart, as wide as the longest label + 20 (at
    // least 138), 14 px #424242 at 12. Leave; "Leave on all my devices"
    // when more than one of your devices is in the call; End meeting for
    // the organizer, after Teams' confirmation.
    readonly property int myDevices: { const me = roster.find(p => p.id === selfId); return me ? (me.devices || 0) : 0 }
    readonly property var leaveItems: heldMeeting ? [{ k: "room", t: qsTr("Leave room") }, { k: "meeting", t: qsTr("Leave meeting") }]
        : [{ k: "leave", t: qsTr("Leave") }]
        .concat(myDevices > 1 ? [{ k: "all", t: qsTr("Leave on all my devices") }] : [])
        .concat(organizer ? [{ k: "end", t: qsTr("End meeting") }] : [])
    Popup {
        id: leaveMenu
        parent: leaveButton
        x: leaveButton.width - width; y: 60
        width: leaveItemW + 33.3; padding: 16
        readonly property real leaveItemW: Math.max(138, leaveMetrics.width + 20)
        TextMetrics {
            id: leaveMetrics
            font.family: theme.font; font.pixelSize: 14
            text: win.leaveItems.reduce((a, b) => b.t.length > a.length ? b.t : a, "")
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: win.leaveItems
                Rectangle {
                    id: hcFill7
                    required property var modelData
                    width: leaveMenu.leaveItemW; height: 32; radius: 4
                    color: lmHover.hovered ? theme.menuHover : theme.surface
                    Text {
                        // Teams: 6 px padding, then the label's own 4 + 2 inset.
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.t
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.onFill(hcFill7, lmHover.hovered ? theme.text : theme.textStrong)
                    }
                    HoverHandler { id: lmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            leaveMenu.close()
                            if (parent.modelData.k === "end") endAsk.open()
                            else if (parent.modelData.k === "room") win.leaveRoom(true)
                            else if (parent.modelData.k === "meeting") win.leaveRoom(false)
                            else if (parent.modelData.k === "all") win.leaveOnAllDevices()
                            else win.leave()
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.t
                }
            }
        }
    }
    ConfirmDialog { id: endAsk; onConfirmed: win.endMeeting() }
    // Teams' held main meeting (measured on winpc 2026-11-11): while its
    // organizer is in a breakout room, the main meeting keeps a window of
    // its own — the meeting's title and time, "▷ Resume" (a bordered
    // button, 105 x 31.33) first on the bar, the bar's other controls
    // greyed but Chat, Rooms and Leave, and on the stage your avatar (153)
    // over "On hold mm:ss" (24/600). Resume (as Leave room) goes back;
    // Leave leaves the main meeting and keeps you in the room.
    property real heldElapsedBase: 0
    /// When the next connected call started (a resumed meeting's start).
    property real nextConnectedAt: 0
    property int mainHeldSeconds: 0
    Timer {
        running: !!win.heldMeeting; interval: 1000; repeat: true; triggeredOnStart: true
        onTriggered: win.mainHeldSeconds = win.heldMeeting ? Math.max(0, Math.floor((Date.now() - win.heldMeeting.since) / 1000)) : 0
    }
    Window {
        id: heldWindow
        visible: !!win.heldMeeting
        title: win.heldMeeting ? win.heldMeeting.title : ""
        width: win.width; height: win.height
        x: win.x + 40; y: win.y + 40
        color: theme.pane
        property bool roomsShown: false
        Rectangle { anchors.fill: parent; color: theme.pane }
        Rectangle {
            id: heldBar
            width: parent.width; height: 60
            color: theme.surface
            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "call-shield"; size: 20; color: theme.textStrong }
            Text {
                x: 44.67; anchors.verticalCenter: parent.verticalCenter
                text: win.clock(Math.floor(win.heldElapsedBase) + win.mainHeldSeconds)
                color: theme.textStrong
                font.family: theme.font; font.pixelSize: 14
            }
            Row {
                anchors { right: parent.right; rightMargin: 14; top: parent.top }
                Item {
                    width: resumeRow.width + 24.67 + 16; height: 60
                    Rectangle {
                        id: hcFill8
                        anchors.centerIn: parent
                        width: resumeRow.width + 24.67; height: 31.33; radius: 4
                        color: resumeHover.hovered ? theme.menuHover : theme.surface
                        border.color: theme.stroke; border.width: 0.67
                        Row {
                            id: resumeRow
                            anchors.centerIn: parent; spacing: 6
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "play-20"; size: 20; color: theme.onFill(hcFill8, theme.text) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Resume"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill8, theme.text) }
                        }
                        HoverHandler { id: resumeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.leaveRoom(true) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Resume")
                    }
                }
                BarButton { icon: "call-chat"; label: qsTr("Chat"); tip: qsTr("Chat"); onClicked: if (win.heldMeeting) backend.openChatWindow(win.heldMeeting.thread) }
                BarButton { icon: "call-people"; label: qsTr("People"); enabled: false }
                BarButton { icon: "call-raise"; label: qsTr("Raise"); enabled: false }
                BarButton { icon: "call-react"; label: qsTr("React"); enabled: false }
                BarButton { icon: "call-view"; label: qsTr("View"); enabled: false }
                BarButton { icon: "call-controls"; label: qsTr("Controls"); enabled: false }
                BarButton { icon: "call-notes"; label: qsTr("Notes"); enabled: false }
                BarButton { icon: "call-rooms"; label: qsTr("Rooms"); tip: qsTr("Breakout rooms"); checked: heldWindow.roomsShown; onClicked: heldWindow.roomsShown = !heldWindow.roomsShown }
                BarButton { icon: "call-apps"; label: qsTr("Apps"); enabled: false }
                Rectangle { width: 17; height: 60; color: "transparent"; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
                BarButton { icon: "call-camera-off-filled"; label: qsTr("Camera"); strong: true; split: true; enabled: false }
                BarButton { icon: "call-mic-off-filled"; label: qsTr("Mic"); strong: true; split: true; enabled: false }
                BarButton { icon: "call-share-filled"; label: qsTr("Share"); strong: true; enabled: false }
                Rectangle { width: 17; height: 60; color: "transparent"; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
                BarButton { icon: "call-leave-filled"; label: qsTr("Leave"); strong: true; iconColor: theme.hc("#B10E1C", "#FFFFFF"); tip: qsTr("Leave"); onClicked: backend.leaveHeldMeeting() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
        }
        Item {
            y: heldBar.height; width: parent.width - (heldWindow.roomsShown ? 360 : 0); height: parent.height - y
            Column {
                anchors.centerIn: parent; spacing: 48
                Avatar { anchors.horizontalCenter: parent.horizontalCenter; size: 153; name: win.selfName; photoId: "me" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("On hold") + " " + win.clock(win.mainHeldSeconds)
                    font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                    color: theme.text
                }
            }
        }
        BreakoutRoomsPane {
            visible: heldWindow.roomsShown
            x: parent.width - 360; y: heldBar.height; width: 360; height: parent.height - y
            rooms: win.breakoutRooms
            names: win.breakoutNames
            settings: win.breakoutSettings
            busy: win.breakoutBusy
            onClosed: heldWindow.roomsShown = false
            onOpenRooms: win.breakoutRun("open", { threads: win.breakoutRooms.filter(r => (r.invitees || []).length > 0).map(r => r.thread) })
            onCloseRooms: win.breakoutRun("close", { threads: win.breakoutRooms.filter(r => r.open).map(r => r.thread) })
            onAddRoom: win.breakoutRun("add", { name: win.nextRoomName() })
            onSaveSettings: st => win.breakoutRun("settings", st)
        }
    }

    // Teams' compact view while the meeting window is minimised.
    CompactCallWindow {
        id: compactView
        call: win
        // "Hide Call Monitor when minimizing" (Accessibility) keeps it
        // away, except while you share (as Teams says).
        visible: win.meeting && win.state === "connected" && win.visibility === Window.Minimized
                 && (win.accessibility.hideCallMonitorOnMinimize !== true || win.sharing)
        onRestore: { win.showNormal(); win.raise(); win.requestActivate() }
    }
    function minimizeForTest() { win.showMinimized() }
    function compactViewForTest() { return compactView }
    function participantMenuForTest(id) { const p = win.people.find(x => x.id === id); if (p) peoplePane.participantMenuForTest(p) }
    // Teams' Mute all confirmation ("All" scope).
    ConfirmDialog {
        id: muteAllAsk
        title: qsTr("Mute everyone?")
        body: qsTr("This will mute everyone in the meeting but you.")
        confirmText: qsTr("Mute")
        onConfirmed: win.muteAll()
    }
    InviteDialog { id: inviteDialog; link: win.inviteUrl }
    // Teams' attendee mic / camera confirmations (confirm-attendee-hard-
    // mute-dialog, 410 wide, a warning before the title when disabling).
    ConfirmDialog {
        id: restrictAsk
        property int modality: 1
        readonly property bool disabling: !(win.attendeeRestrictions & modality)
        width: 410
        fixedButtons: true
        titleIcon: disabling ? "alert-warning-16-filled" : ""
        title: modality === 1 ? (disabling ? qsTr("Disable mic for attendees?") : qsTr("Allow mic for attendees?"))
                              : (disabling ? qsTr("Disable camera for attendees?") : qsTr("Allow camera for attendees?"))
        body: modality === 1
            ? (disabling ? qsTr("Attendees won’t be able to unmute themselves. The organizer and presenters can let people unmute as needed.")
                         : qsTr("Everyone in the meeting will be able to unmute themselves."))
            : (disabling ? qsTr("Attendees won’t be able to share video. The organizer and presenters can let people turn on their cameras as needed.")
                         : qsTr("Everyone in the meeting will be able to share video."))
        confirmText: modality === 1 ? (disabling ? qsTr("Disable mics") : qsTr("Allow mics"))
                                    : (disabling ? qsTr("Disable cameras") : qsTr("Allow cameras"))
        onConfirmed: win.setAttendeeRestrictions((win.attendeeRestrictions & 3) ^ modality)
    }
    // Teams' "Lower all hands?" (confirm-attendee-lower-all-raised-hand).
    ConfirmDialog {
        id: lowerHandsAsk
        property int count: 0
        title: qsTr("Lower all hands?")
        body: qsTr("You'll lower %n raised hands.", "", count)
        confirmText: qsTr("Lower all hands")
        onConfirmed: win.meetingAction("lowerHands")
    }
    RoleChangeDialog {
        id: roleAsk
        property string role: ""
        property string who: ""
        property string whoName: ""
        function ask(newRole, personId, personName) {
            roleAsk.role = newRole; roleAsk.who = personId; roleAsk.whoName = personName
            roleAsk.presenting = newRole === "attendee" && personId !== "" && (win.shareId || "").toLowerCase() === personId.toLowerCase()
            roleAsk.open()
        }
        onConfirmed: win.participantAction(roleAsk.role, roleAsk.who, roleAsk.whoName, "")
    }
    AssignRoomsDialog {
        id: assignRooms
        rooms: win.breakoutRooms
        people: win.people.filter(p => !p.you).map(p => ({ id: p.id, name: p.name }))
        onSaved: changes => { if (changes.length) win.breakoutRun("assign", { rooms: changes.map(c => ({ thread: c.thread, participants: c.participants.map(id => ({ mri: id })) })) }) }
    }
    BreakoutTextDialog {
        id: roomText
        property string thread: ""
        onConfirmed: text => {
            if (rename) win.breakoutRun("rename", { thread: thread, name: text })
            else win.breakoutRun("announce", { message: text })
        }
    }
    ConfirmDialog {
        id: removeRoomsAsk
        width: 450; closeButton: true
        title: qsTr("Remove rooms?")
        body: qsTr("This will delete all existing rooms.")
        confirmText: qsTr("Remove")
        onConfirmed: win.breakoutRun("delete_all", {})
    }
    ConfirmDialog {
        id: deleteRoomAsk
        property string thread: ""
        width: 500; closeButton: true
        body: ""
        confirmText: qsTr("Delete")
        onConfirmed: win.breakoutRun("delete", { thread: thread })
    }
    BreakoutCsvDialog {
        id: csvDialog
        onDownloadTemplate: backend.breakoutAction("csv_template", "{}")
        onPicked: path => {
            // Rooms with people in them: Teams asks before replacing them.
            if (win.breakoutRooms.some(r => (r.invitees || []).length > 0)) { csvOverwriteAsk.path = path; csvOverwriteAsk.open() }
            else win.breakoutRun("import_csv", { path: path })
        }
    }
    ConfirmDialog {
        id: csvOverwriteAsk
        property string path: ""
        width: 500
        title: qsTr("Overwriting rooms and participant assignment")
        body: qsTr("There are already rooms created with participants in them. If you import a CSV it will overwrite the current rooms and participant assignment. Are you sure to continue?")
        confirmText: qsTr("Continue")
        onConfirmed: win.breakoutRun("import_csv", { path: path })
    }
    LockMeetingDialog {
        id: lockAsk
        onConfirmed: win.meetingAction(locked ? "unlock" : "lock")
    }
    // Teams' "Couldn't lock the meeting" (confirm-meeting-retry-lock-dialog)
    // with Try again.
    ConfirmDialog {
        id: lockRetry
        property bool unlocking: false
        width: 430
        titleIcon: "alert-warning-16-filled"
        title: unlocking ? qsTr("Couldn't unlock the meeting") : qsTr("Couldn't lock the meeting")
        body: unlocking ? qsTr("An error occurred. Try unlocking it again.") : qsTr("An error occurred. Try locking it again.")
        confirmText: qsTr("Try again")
        onConfirmed: win.meetingAction(unlocking ? "unlock" : "lock")
    }
    function meetingActionFailed(action) {
        if (action === "lock" || action === "unlock") { lockRetry.unlocking = action === "unlock"; lockRetry.open() }
        if (action === "startTranscription" || action === "startRecording") openTranscriptWhenStarted = false
        if (action === "startRecording") { recorderFailure = qsTr("Couldn't start recording"); recorderFailureTimer.restart() }
        else if (action.indexOf("Transcription") >= 0 || action === "stopRecording") {
            recorderFailure = qsTr("Something went wrong with transcription. Please try again later."); recorderFailureTimer.restart()
        }
    }
    function moreMenuForTest() { side = "people"; peoplePane.moreMenuForTest() }
    function peopleRowsForTest() { return peoplePane.rowsForTest() }
    function tipForTest(name) { const b = barItems[name]; if (b && b.tipForTest) b.tipForTest() }
    function askRoleForTest(action, id, name) { roleAsk.ask(action, id, name) }
    // Confirm whichever More actions dialog is open.
    function confirmOpenDialogForTest() {
        for (const d of [restrictAsk, lowerHandsAsk, lockAsk, muteAllAsk, roleAsk])
            if (d.opened) { d.close(); d.confirmed(); return }
    }

    // Mic ▾: Teams' audio options, right-aligned to the chevron at the
    // bar's bottom edge, at most 5 px short of the window's bottom.
    AudioFlyout {
        id: audioFlyout
        muted: win.muted || !win.hasAudio
        roomAudio: win.roomDeviceJoined
        // Teams' Spatial audio row is off and disabled in a 1:1 call
        // (Teams' P2P call type; its test call is not one: measured).
        oneToOne: !win.meeting && !win.testCall
        onToggleMute: win.toggleMute()
        // Teams opens its Audio settings pane (TASK-0062); OST's device settings for now.
        onMoreAudioSettings: win.side = "audio"
        // Right-aligned to the chevron; start-aligned to the button when
        // that would leave the window (the new controls' Mic and Camera).
        x: !parent ? 0 : parent.mapToItem(null, parent.width - width, 0).x < 0 ? 0 : parent.width - width
        y: parent ? parent.height : 60
        maxHeight: win.height - 60 - 5
    }
    function openAudioOptions(button) { audioFlyout.parent = button; audioFlyout.open() }
    /// The Mic flyout opened at the top right (harness pictures).
    function openAudioOptionsForTest() { audioFlyout.parent = contentItem; audioFlyout.open(); audioFlyout.x = contentItem.width - audioFlyout.width - 8; audioFlyout.y = 60 }
    /// The Mic flyout's Spatial audio row (harness): its state and place.
    function audioFlyoutSpatialForTest() { return audioFlyout.spatialRowForTest() }
    function toggleFlyoutSpatialForTest() { audioFlyout.toggleSpatialForTest() }
    AiPopover {
        id: aiPopover
        aiOn: win.aiOn && win.aiAvailable
        facilitatorEnabled: win.aiFacilitator
        onAboutToShow: {
            const p = aiIndicator.mapToItem(Overlay.overlay, 0, 0)
            x = p.x
            y = p.y + aiIndicator.height + 13.33
        }
    }
    // Teams' parked view (1280 x 680 window, measured): centred, "Call is
    // parked" 24/32 bold, 30 below it "Share this code {code} to retrieve
    // the call" 16/22 bold, 30 below that Copy code (192 x 31.3, white,
    // radius 4, 14/20 semibold #424242; aria "Copy code {code}").
    Rectangle {
        id: parkedView
        visible: win.parkCode !== ""
        anchors.fill: parent
        z: 50
        color: theme.surface
        Column {
            anchors.centerIn: parent
            spacing: 30
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Call is parked")
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold
                lineHeight: 32; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Share this code %1 to retrieve the call").arg(win.parkCode)
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Rectangle {
                id: copyCode
                anchors.horizontalCenter: parent.horizontalCenter
                width: 192; height: 31.33; radius: 4
                color: copyHover.hovered ? theme.rowHover : theme.surface
                border.width: 1; border.color: theme.stroke
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Copy code")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.text
                }
                HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.copyText(win.parkCode) }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Copy code %1").arg(win.parkCode)
            }
        }
    }
    // The encryption card (Teams' e2ee status dialog, a Fluent popover;
    // measured on winpc 2026-11-17): 280.3 wide, 13.3 under the indicator
    // and start-aligned to it, padding 12, radius 4, shadow 16, 12/16
    // #616161 text with "Learn more" (#4F52B2) after it. Not end-to-end
    // encrypted: "This call (meeting) is secured by OST data encryption."
    // End-to-end encrypted (measured on winpc 2026-11-17, a live E2EE call):
    // a 10 px column; the title 14/20 semibold #242424 with 16 px bottom
    // padding; "Verify your call's encryption by making sure the numbers
    // below are the same for both of you." (meetings: "…for all
    // participants.") 12/20 #616161 with Learn more; then, 16 px further
    // down, the five 4-digit numbers (14/20 #242424) spread edge to edge
    // on a #FAFAFA band (radius 4, padding 10, 40 tall). 280.3 x 217.3.
    Popup {
        id: encryptionCard
        parent: Overlay.overlay
        width: 280.33; padding: 12
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: {
            const p = encryptionIndicator.mapToItem(Overlay.overlay, 0, 0)
            x = p.x
            y = p.y + encryptionIndicator.height + 13.33
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            spacing: 10
            Text {
                visible: win.e2ee
                width: parent.width; wrapMode: Text.Wrap
                bottomPadding: 16
                text: win.meeting ? qsTr("End-to-end encryption enabled for this meeting") : qsTr("End-to-end encryption enabled for this call")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                id: encryptionText
                width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: theme.brandForeground1
                text: (!win.e2ee ? (win.meeting ? qsTr("This meeting is secured by OST data encryption. ") : qsTr("This call is secured by OST data encryption. "))
                       : (win.meeting ? qsTr("This meeting is end-to-end encrypted if the numbers below are the same for all participants.")
                       : qsTr("Verify your call's encryption by making sure the numbers below are the same for both of you.")) + " ")
                      + "<a href=\"" + (win.e2ee ? "https://go.microsoft.com/fwlink/?linkid=2174740" : "https://go.microsoft.com/fwlink/?linkid=2174896") + "\">" + qsTr("Learn more") + "</a>"
                font.family: theme.font; font.pixelSize: 12
                lineHeight: win.e2ee ? 20 : 16; lineHeightMode: Text.FixedHeight
                color: theme.textSecondary
                onLinkActivated: l => Qt.openUrlExternally(l)
                HoverHandler { cursorShape: encryptionText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                Accessible.name: win.e2ee ? qsTr("Learn more about OST End-to-end encryption") : qsTr("Learn more about OST data encryption")
            }
            Item {
                visible: win.e2ee && win.e2eeNumbers.length > 0
                width: parent.width; height: 16 + 40
                Rectangle {
                    id: numbersBand
                    y: 16; width: parent.width; height: 40; radius: 4
                    color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                    // Teams spreads the groups edge to edge (space-between).
                    Repeater {
                        model: win.e2eeNumbers
                        Text {
                            required property var modelData
                            required property int index
                            readonly property real slot: win.e2eeNumbers.length > 1 ? (numbersBand.width - 20 - implicitWidth) / (win.e2eeNumbers.length - 1) : 0
                            x: 10 + index * slot; y: 10
                            text: modelData
                            font.family: theme.font; font.pixelSize: 14
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                    }
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("End-to-end encryption numbers") + " " + win.e2eeNumbers.join(" ")
            }
        }
    }
    NetworkPopover {
        id: networkPopover
        call: win
        onLeft: networkPopoverClose.restart()
    }
    VideoFlyout {
        id: videoFlyout
        cameraOn: win.cameraOn
        // Right-aligned to the chevron; start-aligned to the button when
        // that would leave the window (the new controls' Mic and Camera).
        x: !parent ? 0 : parent.mapToItem(null, parent.width - width, 0).x < 0 ? 0 : parent.width - width
        y: parent ? parent.height : 60
        // Teams opens its Video effects and settings pane.
        onMoreVideoSettings: { videoEffectsPane.tab = "effects"; win.side = "video" }
        onMoreAvatarSettings: { videoEffectsPane.tab = "avatars"; win.side = "video" }
        onTurnOnVideo: if (!win.cameraOn) win.runControl("VideoButton")
        onTurnOffVideo: if (win.cameraOn) win.runControl("VideoButton")
    }
    function videoOptionsForTest() { videoFlyout.parent = barItem("VideoButton"); videoFlyout.open() }
    function videoFlyoutForTest() { return videoFlyout }
    function videoEffectsPaneForTest() { return videoEffectsPane }

    // React (reaction-menu-button-toolbox, measured on winpc): a 249.3 x
    // 73.3 surface under the React button, padding 16, five 32 px buttons
    // 12 apart holding Teams' 24 px reaction pictures.
    // The new controls (measured on winpc 2026-11-16): 250 x 104.7, the
    // reactions 14.1 apart from 16.7 in, and under them Teams' "Raise
    // hand" / "Lower hand" button (224.7 x 35.3 at 12.7, 56.7; outlined,
    // brand while raised); it stays open after a pick
    // (enableReactionsPersistentFlyout).
    Popup {
        id: reactMenu
        x: win.compactBar ? 2 : 4; y: win.compactBar ? 41 : 59.3
        width: win.newControls ? 250 : 249.3; height: win.newControls ? 104.7 : 73.3
        padding: 0
        background: FluentSurface { depth: 16; radius: 4; color: win.newControls ? theme.menu : theme.surface }
        Row {
            x: win.newControls ? 16.7 : 20.7; y: win.newControls ? 16.7 : 20.7; spacing: win.newControls ? 14.13 : 12
            Repeater {
                model: [{ n: "like", t: qsTr("Like") }, { n: "heart", t: qsTr("Love") }, { n: "applause", t: qsTr("Applause") }, { n: "laugh", t: qsTr("Laugh") }, { n: "surprised", t: qsTr("Surprised") }]
                Rectangle {
                    required property var modelData
                    width: 32; height: 32; radius: 4
                    // The new controls: Teams' bar hover, the picture
                    // growing to 38.4 px (1.6 times) while hovered.
                    color: rmHover.hovered ? (win.newControls ? theme.nmcHover : theme.menuHover) : "transparent"
                    Image {
                        x: 4; y: 4; width: 24; height: 24; smooth: true; source: win.reactionUrl(parent.modelData.n, false)
                        scale: win.newControls && rmHover.hovered ? 1.6 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                    }
                    HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (!win.newControls) reactMenu.close(); win.sendReaction(parent.modelData.n) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.t
                }
            }
        }
        Rectangle {
            id: hcFillRaise
            visible: win.newControls
            x: 12.7; y: 56.7; width: 224.7; height: 35.3; radius: 4
            color: win.handRaised ? (raiseHover.hovered ? theme.brandHover : theme.checkedFill)
                 : raiseHover.hovered ? theme.nmcHover : theme.menu
            border.width: 0.67
            border.color: win.handRaised ? theme.hc("#C7C7C7", "#1AEBFF") : raiseHover.hovered ? theme.strokeHover : theme.stroke
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "nmc-raise"; size: 24
                    color: theme.onFill(hcFillRaise, win.handRaised ? theme.textOnBrand : raiseHover.hovered ? theme.text : theme.textStrong)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.handRaised ? qsTr("Lower hand") : qsTr("Raise hand")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(hcFillRaise, win.handRaised ? theme.textOnBrand : raiseHover.hovered ? theme.text : theme.textStrong)
                }
            }
            HoverHandler { id: raiseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: win.live; onTapped: win.toggleHand() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Raise")
            Accessible.onPressAction: win.toggleHand()
        }
    }
    function reactForTest(name) { sendReaction(name) }

    // A reaction on someone's tile: Teams' 84 px picture, centred, its top
    // at the tile's middle, while it lasts.
    component ReactionShown: Image {
        property string mri
        readonly property string reaction: { win.reactions; return win.reactionOf(mri) }
        visible: reaction.length > 0
        width: 84; height: 84
        x: (parent.width - width) / 2; y: parent.height / 2
        smooth: true
        source: reaction ? win.reactionUrl(reaction, true) : ""
        Accessible.role: Accessible.Graphic
        Accessible.name: reaction
    }

    component Divider: Item {
        width: 17; height: 60
        Rectangle { x: 8; y: 13.5; width: 0.67; height: 33; color: theme.stroke }
    }

    // View: Teams' layout menu (measured on winpc): 230 px list in a
    // 16 px padded surface at the button's left, 5.3 px under it; check
    // marks at the end; submenus beside the list.
    MenuPopup {
        id: viewMenu
        viewStyle: win.meeting
        x: win.meeting ? 4 : (parent ? parent.width - width : 0)
        y: win.meeting ? 59.3 : (parent ? parent.height + 4 : 0)
        width: win.meeting ? 263.3 : 240
        readonly property var moreOptions: [
            { k: "galleryTop", label: win.galleryAtTop ? qsTr("Show gallery on right") : qsTr("Show gallery at top"), checked: false },
            { k: "incoming", label: qsTr("Turn off other videos"), checked: win.incomingVideoOff },
            { k: "hideMe", label: qsTr("Hide me"), checked: win.hideMe },
            win.layout === "speaker"
                ? { k: "meInGallery", label: win.speakerMeInGallery ? qsTr("Remove me from gallery") : qsTr("Include me in gallery"), checked: false }
                : { k: "meInGallery", label: win.meInGallery ? qsTr("Remove me from gallery") : qsTr("Include me in gallery"), checked: false },
            { k: "room", label: qsTr("Optimize for room"), checked: win.roomMode },
            { k: "fullscreen", label: qsTr("Full screen"), keys: "F11", checked: win.visibility === Window.FullScreen }]
        items: win.meeting
            ? [{ k: "gallery", label: qsTr("Gallery"), icon: "view-gallery-20", checked: win.layout === "gallery" },
               { k: "speaker", label: qsTr("Speaker", "calling:k26t72ax"), icon: "view-speaker-20", checked: win.layout === "speaker" }].concat(win.signMode ? [{ k: "sign", label: qsTr("Sign language"), icon: "hand-wave-20", checked: win.layout === "accessibility" }] : []).concat([
               { k: "focus", label: qsTr("Focus on content"), icon: "view-focus-20", checked: win.layout === "focus", enabled: win.shareShown || win.layout === "focus" },
               { separator: true }])
              .concat(win.layout === "gallery" ? [
               { k: "gallerySize", label: qsTr("Gallery size"), icon: "view-gallery-size-20", submenu: [4, 9, 16, 49].map(n => ({ label: qsTr("%n people", "calling:k8syueuxc_mf", n), checked: win.gallerySize === n })) },
               { k: "videosFirst", label: qsTr("Show videos first"), icon: "view-videos-first-20", checked: win.videosFirst }] : [])
              .concat([{ k: "more", label: qsTr("More options"), submenu: moreOptions }])
            : [{ k: "fullscreen", label: qsTr("Full screen", "calling:k5hqewcjf"), icon: "full-screen-maximize-20", checked: win.visibility === Window.FullScreen },
               { k: "incoming", label: win.incomingVideoOff ? qsTr("Turn on other videos") : qsTr("Turn off other videos"), icon: "video-off-20" }]
        onPicked: i => {
            const k = items[i].k
            if (k === "gallery") win.layout = "gallery"
            else if (k === "speaker") win.layout = "speaker"
            else if (k === "sign") { win.layout = "accessibility"; win.contentItem.Accessible.announce(qsTr("Accessibility mode was set")) }
            else if (k === "focus") win.layout = win.layout === "focus" ? "gallery" : "focus"
            else if (k === "videosFirst") win.videosFirst = !win.videosFirst
            else if (k === "fullscreen") win.toggleFullScreen()
            else win.incomingVideoOff = !win.incomingVideoOff
        }
        onSubPicked: (i, j) => {
            const it = items[i]
            if (it.k === "gallerySize") { win.gallerySize = [4, 9, 16, 49][j]; return }
            const k = it.submenu[j].k
            if (k === "galleryTop") win.galleryAtTop = !win.galleryAtTop
            else if (k === "incoming") win.incomingVideoOff = !win.incomingVideoOff
            else if (k === "hideMe") win.hideMe = !win.hideMe
            else if (k === "meInGallery") {
                if (win.layout === "speaker") win.speakerMeInGallery = !win.speakerMeInGallery
                else win.meInGallery = !win.meInGallery
            }
            else if (k === "room") win.roomMode = !win.roomMode
            else if (k === "fullscreen") win.toggleFullScreen()
        }
    }
    // Teams' Controls menu (organizer-control-button-menu, measured on
    // winpc 2026-11-10): the View menu's style (263.3 wide, padding
    // 16.67, 32 px rows, labels at 10, checks at the end), under the
    // Controls button.
    MenuPopup {
        id: controlsMenu
        viewStyle: true
        parent: win.contentItem
        x: Math.max(4, Math.min(win.width - width - 4, win.controlsButton ? win.controlsButton.mapToItem(win.contentItem, 0, 0).x : 4))
        y: 59.3
        width: 263.3
        items: win.controlsItems
        onPicked: i => win.pickControl(items[i].key)
    }
    property Item controlsButton: null
    function optionsDialogForTest() { return optionsDialog }
    function lobbyPaneForTest() { return lobbyPane }
    function lobbyToastForTest() { return lobbyToast }
    MeetingOptionsDialog {
        id: optionsDialog
        options: win.controlsOptions
        people: win.controlsPeople
        onApply: changes => win.applyMeetingOptions(changes)
    }
    Shortcut { sequence: "F11"; enabled: win.meeting; onActivated: win.toggleFullScreen() }
    // Teams' call shortcuts (§13). Mute, camera and leave work app-wide
    // (Main.qml); the rest in the call window.
    readonly property bool inCall: state === "connected" || state === "calling" || state === "connecting"
    Shortcut { sequence: "Ctrl+Shift+K"; enabled: win.live && (win.ubar.bar.concat(win.ubar.overflowed).indexOf("RaiseHandsButton") >= 0
                                                       // The new controls raise hands from React.
                                                       || win.newControls && win.ubar.bar.concat(win.ubar.overflowed).indexOf("ReactionButton") >= 0); onActivated: win.toggleHand() }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: win.live && (win.canShare || win.sharing); onActivated: win.runControl("ShareButton") }
    // Language and speech ▸ Show / Hide live captions.
    Shortcut { sequence: "Alt+Shift+C"; enabled: win.live && win.ubar.more.some(sec => sec.items.some(i => i.name === "LanguageSpeechMenuControl" || i.name === "ClosedCaptionsButton")); onActivated: win.setCaptions(!win.captionsOn) }
    // Admit the person the lobby notification shows.
    Shortcut {
        sequence: "Ctrl+Shift+Y"
        enabled: lobbyToast.visible && win.lobby.length === 1 && !win.lobby[0].suspected
        onActivated: win.admitLobby(win.lobby[0].id, win.lobby[0].name, false)
    }
    /// The stage as laid out (harness lines): the speaker tile, the
    /// focused or pin area, whose video is focused.
    function stageForTest() {
        return { speaker: tiles.speaker ? tiles.speaker.name || "" : "", featured: tiles.featuredList.map(p => p.name || ""),
                 focus: videoFocus, pins: pinnedIds, layout: layout }
    }
    // Teams' "Announce active speaker (screen reader)" (calling-app nz):
    // Ctrl+Alt+Shift+S, Ctrl+2 with Zoom's shortcuts; the screen reader
    // says "Latest speaker: <name>" (Unknown with no name), or "Nobody is
    // speaking" when the meeting names no dominant speaker in the call.
    // Teams' AnnounceActiveSpeaker (calling-app nz): "Latest speaker: " the
    // dominant speaker's name ("Unknown" without one), "Nobody is speaking"
    // with none or one missing from the roster. When the speaker is a sign
    // language interpreter tethered to a signer (Teams' tethering: the
    // signer's interpreterIds), it is "<signer> voiced by <interpreter>",
    // with "You" when you are that signer.
    function announceActiveSpeaker() {
        const id = win.speakerId
        const p = !id ? null : (id === win.selfId ? { name: win.selfName } : win.others.find(o => o.id === id))
        const named = n => (n || "").trim() || qsTr("Unknown")
        // Teams reads the roster's display name: the test call's Echo bot
        // has none there (OST names it from its profile), so Teams says
        // "Unknown" (seen on winpc, 2026-11-19).
        let who = p && p.roster_named !== false ? (p.name || "").trim() : ""
        let kase = !p ? "nobody_speaking" : who ? "known_speaker" : "unknown_speaker"
        if (p && p.sign_role === "signLanguageInterpreter") {
            let signer = ""
            if (win.iSign && win.myInterpreters.indexOf(id) >= 0) signer = qsTr("You")
            else {
                const s = win.others.filter(o => o.sign_role === "dhhSigner" && (win.signContentOf(o).interpreterIds || "").split(",").indexOf(id) >= 0)
                if (s.length === 1) signer = named(s[0].name)
            }
            if (signer) { who = qsTr("%1 voiced by %2").arg(signer).arg(named(p.name)); kase = "paired_signer" }
        }
        const text = qsTr("Latest speaker: %1").arg(!p ? qsTr("Nobody is speaking") : who || qsTr("Unknown"))
        console.warn("ANNOUNCE", JSON.stringify({ speaker: id, case: kase, text: text }))
        win.contentItem.Accessible.announce(text, Accessible.Assertive)
        return text
    }
    Shortcut { sequences: window.zoomShortcuts ? ["Ctrl+2"] : ["Ctrl+Alt+Shift+S"]; enabled: win.live; onActivated: win.announceActiveSpeaker() }
    // Ctrl+Space: talk while held when muted (Teams' temporary unmute).
    property bool talkHeld: false
    Item {
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Space && e.modifiers === Qt.ControlModifier && !e.isAutoRepeat
                && win.live && win.hasAudio && win.muted) {
                win.talkHeld = true; win.toggleMute(); e.accepted = true
            }
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Space && !e.isAutoRepeat && win.talkHeld) {
                win.talkHeld = false; if (!win.muted) win.toggleMute(); e.accepted = true
            }
        }
    }
    // Apps: what Teams offers in a call. Planner and OneNote open in the
    // main window; Whiteboard and Clipchamp are web apps.
    MenuPopup {
        id: appsMenu
        x: parent ? parent.width - width : 0; y: parent ? parent.height + 4 : 0
        width: 240
        items: [
            { label: "Whiteboard", icon: "board-20" },
            { label: "Planner", icon: "clipboard-task-list-ltr-24" },
            { label: "OneNote", icon: "notebook-20" },
            { label: "Clipchamp", icon: "video" }
        ]
        onPicked: i => {
            const l = items[i].label
            if (l === "Whiteboard") Qt.openUrlExternally("https://whiteboard.cloud.microsoft/")
            else if (l === "Clipchamp") Qt.openUrlExternally("https://app.clipchamp.com/")
            else win.openApp(l.toLowerCase())
        }
    }
    // More (Teams' "More actions" menu, measured on winpc): View's menu
    // style, at the button's left 5.3 px under it; what overflowed off the
    // bar first, then More's own items from Teams' config.
    MenuPopup {
        id: moreMenu
        viewStyle: true
        // Teams' More list is 230 wide (its submenus too: they take its width).
        minRowWidth: 230
        x: 4; y: 59.3
        items: win.barMoreItems
        submenuLeft: true
        onPicked: i => {
            const it = win.barMoreItems[i]
            // Overflowed menus open from More's place on the bar.
            win.runControl(it.name)
        }
        onSubPicked: (i, j) => win.recordControl(win.barMoreItems[i].submenu[j].name)
        onSubSubPicked: (i, j, k) => win.interpreterAction(win.barMoreItems[i].submenu[j].submenu[k].name)
    }

    // ── Teams' New meeting controls: More's grid and list, the arrange
    // menus (measured on winpc 2026-11-16; docs/spec/new-meeting-controls.md).

    /// A control as More's grid shows it (and as it shows on the bar once
    /// pinned): its short label and glyph; null when OST doesn't show it.
    function gridEntry(name) {
        let e = null
        if (name === "RecordingButton") e = { label: recording ? qsTr("Recording") : qsTr("Record"), icon: "nmc-record", checked: recording }
        else if (name === "TranscriptButton") {
            e = { label: transcribing ? qsTr("Transcribing") : qsTr("Transcribe"), icon: "nmc-transcribe", checked: transcribing }
            // Once a transcript has run: its pane from the item's chevron.
            if (transcriptStarted) e.submenu = [{ name: "TranscriptPanelButton", label: side === "transcript" ? qsTr("Hide transcript") : qsTr("Show transcript"),
                                                 icon: "transcript-panel-20", checked: side === "transcript" }]
        }
        else if (name === "MeetingFacilitatorTimerButton") e = timerCanView ? { label: qsTr("Timer"), icon: "nmc-timer", checked: timerVisible } : null
        // Interpreter (Teams' More grid, measured on winpc 2026-11-20).
        else if (name === "AiInterpretationButtonForAll") { e = interpreterShown ? { label: qsTr("Interpreter"), icon: "sound-wave-circle-sparkle-20", checked: interpreterInGroup } : null; if (e && interpreterItems.length) e.submenu = interpreterItems }
        else if (name === "MeetingDetailsButton") e = { label: qsTr("Notes"), icon: "nmc-notes", checked: side === "notes" }
        else if (name === "ClosedCaptionsButton") e = { label: qsTr("Captions"), icon: "nmc-captions", checked: captionsOn }
        else if (name === "StartBreakoutRoomButton") e = { label: qsTr("Rooms"), icon: "nmc-rooms", checked: side === "rooms" }
        else if (name === "RealTimeTextButton") e = { label: qsTr("RTT"), icon: "nmc-rtt", checked: rttOn, enabled: !rttOn }
        else if (name === "MeetingAppsAddButton") e = { label: qsTr("Get more apps and agents"), apps: true, checked: appsMenu.visible }
        // Bar controls that overflowed or were unpinned: their bar label.
        else if (name === "ChatButton") e = { label: qsTr("Chat"), icon: "nmc-chat", checked: side === "chat" }
        else if (name === "RosterButton") e = { label: qsTr("People"), icon: "nmc-people", checked: side === "people" }
        else if (name === "MeetingCollabButton") e = { label: qsTr("Copilot"), icon: side === "copilot" ? "copilot-filled-48" : "ai-copilot", checked: side === "copilot" }
        else if (name === "ReactionButton") e = { label: qsTr("React"), icon: handRaised ? "nmc-react-filled" : "nmc-react", checked: handRaised }
        else if (name === "RaiseHandsButton") e = { label: qsTr("Raise", "calling:k9th2ytq2"), icon: "nmc-raise", checked: handRaised }
        else if (name === "OrganizerControlButton") e = { label: qsTr("Controls"), icon: "nmc-controls", chevron: true }
        else if (name === "PopoutContentButton") e = { label: qsTr("Pop out"), icon: "call-popout" }
        else if (name === "CallTransferButtonV2") e = { label: qsTr("Transfer"), icon: "call-transfer" }
        else if (name === "CallConsultativeTransferButtonV2") e = { label: qsTr("Consult"), icon: "consult" }
        else if (name === "DialpadButton") e = { label: qsTr("Dial pad"), icon: "dialpad" }
        else if (name === "HoldButton") e = { label: qsTr("Hold"), icon: "pause" }
        if (!e) return null
        e.name = name
        if (e.enabled === undefined) e.enabled = controlEnabled(name)
        return e
    }
    /// More's grid: what overflowed off the bar (in bar order), then the
    /// grid section (unpinned controls first, Apps last).
    readonly property var newGridItems: {
        if (!newControls) return []
        const out = []
        for (const n of ubar.overflowed) { const e = gridEntry(n); if (e) out.push(e) }
        for (const sec of ubar.more) if (sec.grid) for (const it of sec.items) {
            if (ubar.overflowed.indexOf(it.name) >= 0) continue
            const e = gridEntry(it.name); if (e) out.push(e)
        }
        return out
    }
    /// More's list rows (and their submenus), as the new controls name them.
    function newLabel(n) {
        if (n === "ViewModeButton") return { label: qsTr("View"), icon: "nmc-view", submenu: newViewItems }
        if (n === "JoinInfoMenuControl") return { label: qsTr("Join info"), icon: "nmc-info" }
        if (n === "SettingsMenuControl") return { label: qsTr("Settings"), icon: "nmc-settings" }
        if (n === "MeetingInfoButton") return { label: qsTr("Meeting info"), icon: "nmc-info", checked: side === "info" }
        if (n === "CallHealth") return { label: qsTr("Call health"), icon: "nmc-health", checked: side === "callHealth" }
        if (n === "PstnButton") return { label: qsTr("Call me"), icon: "nmc-callme" }
        if (n === "AccessibilitySettingsButton") return { label: qsTr("Accessibility settings"), icon: "nmc-accessibility", checked: side === "accessibility" }
        if (n === "ChatBubblesButton") return chatBubblesSuppressed ? { label: qsTr("Show chat bubbles"), icon: "nmc-bubbles" }
                                                                   : { label: qsTr("Don't show chat bubbles"), icon: "nmc-bubbles-off" }
        if (n === "ToggleHideMyselfButton") return hideMe ? { label: qsTr("Unhide me"), icon: "nmc-show-me" } : { label: qsTr("Hide me"), icon: "nmc-hide-me" }
        if (n === "CameraEffectsButton") return { label: qsTr("Video effects and settings"), icon: "nmc-effects", checked: side === "video" }
        if (n === "AudioSettingsButton") return { label: qsTr("Audio settings"), icon: "nmc-audio", checked: side === "audio" }
        if (n === "ByodMeetingRoomModeButton") return { label: qsTr("Optimize for room"), icon: "nmc-room", checked: roomMode }
        if (n === "ReportMeetingButton") return { label: qsTr("Report a concern"), icon: "nmc-report" }
        if (n === "CallParkButton") return { label: qsTr("Park Call"), icon: "call-park-20" }
        if (n === "MeetingHelpButton") return { label: qsTr("Help"), icon: "nmc-help" }
        return null
    }
    // A menu control's sections as one list (a section of one merges
    // into the next, as Teams' Settings ▸ shows).
    function newSubmenuOf(item) {
        const secs = (item.sections || []).map(sec => sec.items.filter(i => !!newLabel(i.name))).filter(sec => sec.length > 0)
        const out = []
        secs.forEach((sec, i) => {
            sec.forEach(i2 => out.push(Object.assign({ name: i2.name }, newLabel(i2.name))))
            if (i < secs.length - 1 && sec.length > 1) out.push({ separator: true })
        })
        return out
    }
    readonly property var newListItems: {
        if (!newControls) return []
        const out = []
        const secs = ubar.more.filter(sec => !sec.grid).map(sec => sec.items.filter(i => !!newLabel(i.name)))
        secs.forEach((sec, si) => {
            for (const it of sec) {
                const row = Object.assign({ name: it.name }, newLabel(it.name))
                if (it.sections && it.sections.length) {
                    row.submenu = newSubmenuOf(it)
                    if (row.submenu.length === 0) continue
                }
                out.push(row)
            }
            if (si < secs.length - 1 && sec.length > 0) out.push({ separator: true })
        })
        return out
    }
    // More ▸ View (measured): Gallery, Speaker | Full screen, Focus on
    // content, Show gallery at top, Gallery size ▸ | Turn off other
    // videos, Show videos first.
    readonly property var newViewItems: [
        { action: "gallery", label: qsTr("Gallery"), icon: "nmc-view", checked: layout === "gallery" },
        { action: "speaker", label: qsTr("Speaker", "calling:k26t72ax"), icon: "nmc-speaker", checked: layout === "speaker" }].concat(signMode ? [{ action: "signLanguage", label: qsTr("Sign language"), icon: "hand-wave-20", checked: layout === "accessibility" }] : []).concat([
        { separator: true },
        { action: "fullscreen", label: qsTr("Full screen"), icon: "nmc-fullscreen", keys: "F11", checked: visibility === Window.FullScreen },
        { action: "focus", label: qsTr("Focus on content"), icon: "nmc-focus", checked: layout === "focus", enabled: shareShown || layout === "focus" },
        { action: "galleryTop", label: galleryAtTop ? qsTr("Show gallery on right") : qsTr("Show gallery at top"), icon: "nmc-gallery-right" }])
        .concat(layout === "gallery" ? [{ action: "gallerySize", label: qsTr("Gallery size"), icon: "nmc-gallery-size",
                                          submenu: [4, 9, 16, 49].map(n => ({ label: qsTr("%n people", "calling:k8syueuxc_mf", n), checked: gallerySize === n })) }] : [])
        .concat([{ separator: true },
                 { action: "incoming", label: incomingVideoOff ? qsTr("Turn on other videos") : qsTr("Turn off other videos"), icon: "nmc-videos-off" }])
        .concat(layout === "gallery" ? [{ action: "videosFirst", label: qsTr("Show videos first"), icon: "view-videos-first-20", checked: videosFirst }] : [])
    function runViewAction(a) {
        if (a === "gallery") layout = "gallery"
        else if (a === "signLanguage") { layout = "accessibility"; contentItem.Accessible.announce(qsTr("Accessibility mode was set")) }
        else if (a === "speaker") layout = "speaker"
        else if (a === "focus") layout = layout === "focus" ? "gallery" : "focus"
        else if (a === "fullscreen") toggleFullScreen()
        else if (a === "galleryTop") galleryAtTop = !galleryAtTop
        else if (a === "incoming") incomingVideoOff = !incomingVideoOff
        else if (a === "videosFirst") videosFirst = !videosFirst
    }
    function runNewMore(name) {
        if (name === "ToggleHideMyselfButton") hideMe = !hideMe
        else if (name === "ByodMeetingRoomModeButton") roomMode = !roomMode
        else if (["MeetingInfoButton", "CameraEffectsButton", "AudioSettingsButton", "MeetingHelpButton", "ReportMeetingButton"].indexOf(name) >= 0) runControl(name)
        else recordControl(name)
    }
    // More (new controls): a 309.3 wide surface (padding 12.67) start-
    // aligned 5.3 under the More button, end-aligned when it would leave
    // the window; the grid (70 x 52 items in 96 px columns, 58 px rows),
    // "Get more apps and agents", a full-width divider, then the list
    // (284 px rows); submenus (230 px rows) open to the left.
    MenuPopup {
        id: newMore
        viewStyle: true; newStyle: true
        parent: win.contentItem
        minRowWidth: 284; submenuMinWidth: 230
        items: win.newListItems
        header: newMoreGrid
        submenuLeft: x >= 255.33
        function openAt(button) {
            const p = button.mapToItem(win.contentItem, 0, 0)
            const bx = p.x + (win.compactBar ? 2 : 4), bw = win.compactBar ? 32 : 48
            x = bx + width > win.width ? bx + bw - width : bx
            y = p.y + (win.compactBar ? 3.7 + 32 : 6 + 48) + 5.33
            open()
        }
        onPicked: i => {
            const it = win.newListItems[i]
            if (it && !it.submenu) win.runNewMore(it.name)
        }
        onSubPicked: (i, j) => {
            const it = win.newListItems[i]
            const sub = it.submenu[j]
            if (it.name === "ViewModeButton") win.runViewAction(sub.action)
            else win.runNewMore(sub.name)
        }
        onSubSubPicked: (i, j, k) => {
            const it = win.newListItems[i]
            if (it.name === "ViewModeButton" && it.submenu[j].action === "gallerySize") win.gallerySize = [4, 9, 16, 49][k]
        }
    }
    function newMoreForTest() { newMore.openAt(barItem("MoreButton")); return newMore }
    Component {
        id: newMoreGrid
        Item {
            id: gridRoot
            readonly property var cells: win.newGridItems.filter(e => !e.apps)
            readonly property var apps: win.newGridItems.find(e => e.apps)
            readonly property int rows: Math.ceil(cells.length / 3)
            readonly property real gridHeight: rows > 0 ? rows * 58 - 6 : 0
            height: gridHeight + (apps ? (rows > 0 ? 12 : 0) + 32 : 0) + 6
            /// The grid item at `p` (this item's coordinates), or "".
            function cellAt(p) {
                const col = Math.floor((p.x - 12) / 96), row = Math.floor(p.y / 58)
                if (col < 0 || col > 2 || row < 0 || p.x - 12 - col * 96 >= 70 || p.y - row * 58 >= 52) return ""
                const c = cells[row * 3 + col]
                return c ? c.name : ""
            }
            // Dragging a grid item onto the bar (see dragBegin).
            HoverHandler { id: gridDragHover }
            DragHandler {
                target: null
                dragThreshold: 2
                acceptedButtons: Qt.LeftButton
                enabled: active || gridRoot.cellAt(gridDragHover.point.position) !== ""
                cursorShape: win.dragZone === "blocked" ? Qt.ForbiddenCursor : Qt.ClosedHandCursor
                readonly property point at: win.contentItem.mapFromItem(null, centroid.scenePosition)
                onActiveChanged: {
                    if (active) {
                        const g = gridRoot.mapFromItem(null, centroid.scenePressPosition)
                        const n = gridRoot.cellAt(g)
                        const p = win.contentItem.mapFromItem(null, centroid.scenePressPosition)
                        const col = Math.floor((g.x - 12) / 96), row = Math.floor(g.y / 58)
                        win.dragBegin(n, "grid", p, gridRoot.mapToItem(win.contentItem, 12 + col * 96, row * 58))
                        win.dragMove(at)
                    } else if (win.dragState) win.dragEnd(true)
                }
                onAtChanged: if (active && win.dragState) win.dragMove(at)
            }
            Repeater {
                model: gridRoot.cells
                Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool on: modelData.enabled !== false
                    readonly property bool hasMenu: !!modelData.submenu
                    x: 12 + (index % 3) * 96; y: Math.floor(index / 3) * 58
                    width: hasMenu ? 92 : 70; height: 52
                    Rectangle {
                        id: hcFillCell
                        width: 70; height: 52
                        radius: 4; topRightRadius: cell.hasMenu ? 0 : 4; bottomRightRadius: cell.hasMenu ? 0 : 4
                        color: cellHover.hovered && cell.on ? theme.nmcHover : "transparent"
                        FluentIcon {
                            x: 22.5; y: 4.5; size: 25; name: cell.modelData.icon || ""
                            color: theme.onFill(hcFillCell, !cell.on ? theme.disabled : cell.modelData.checked ? theme.brand
                                                : cellHover.hovered ? theme.text : theme.textStrong)
                        }
                        Text {
                            x: 0.67; y: 33.3; width: 68.67; height: 16
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: cell.modelData.label; elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: 11
                            color: theme.onFill(hcFillCell, !cell.on ? theme.disabled : cellHover.hovered ? theme.text : theme.textStrong)
                        }
                        HoverHandler { id: cellHover; cursorShape: cell.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: cell.on
                            onTapped: {
                                const n = cell.modelData.name
                                newMore.close()
                                win.runControl(n)
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: (ev) => win.openGridMenu(cell.modelData.name, hcFillCell.mapToItem(win.contentItem, ev.position.x, ev.position.y))
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: cell.modelData.label
                        Accessible.checkable: cell.modelData.checked !== undefined
                        Accessible.checked: !!cell.modelData.checked
                    }
                    // A grid item with a menu of its own: its 22 px chevron.
                    Rectangle {
                        id: hcFillCellChev
                        visible: cell.hasMenu
                        x: 70; width: 22; height: 52
                        topRightRadius: 4; bottomRightRadius: 4
                        color: chevHoverCell.hovered ? theme.nmcHover : "transparent"
                        FluentIcon { x: 3; y: 18; size: 16; name: "call-chevron"; color: theme.onFill(hcFillCellChev, theme.textStrong) }
                        HoverHandler { id: chevHoverCell; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                cellMenu.items = cell.modelData.submenu
                                cellMenu.parent = hcFillCellChev
                                cellMenu.open()
                            }
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: qsTr("More options for %1").arg(cell.modelData.label)
                    }
                }
            }
            // "Get more apps and agents": a 284 x 32 outlined button.
            Rectangle {
                id: hcFillApps
                visible: !!gridRoot.apps
                y: gridRoot.gridHeight + (gridRoot.rows > 0 ? 12 : 0)
                width: 284; height: 32; radius: 4
                color: appsHover.hovered ? theme.nmcHover : theme.menu
                border.width: 0.67; border.color: appsHover.hovered ? theme.strokeHover : theme.stroke
                Text {
                    anchors.centerIn: parent
                    text: gridRoot.apps ? gridRoot.apps.label : ""
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.onFill(hcFillApps, appsHover.hovered ? theme.text : theme.textStrong)
                }
                HoverHandler { id: appsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { newMore.close(); win.runControl("MeetingAppsAddButton") } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: qsTr("Apps")
            }
        }
    }
    // A grid item's own menu (Transcribe ▸ Show transcript).
    MenuPopup {
        id: cellMenu
        viewStyle: true; newStyle: true
        minRowWidth: 230
        x: parent ? parent.width : 0; y: 0
        onPicked: i => { const n = items[i].name; newMore.close(); win.recordControl(n) }
    }

    // Right-click on a bar control (new controls, its group customizable):
    // Move before "{previous}", Move after "{next}", Unpin, divider, Reset
    // meeting controls; on a grid item: Pin, divider, Reset (207 wide at
    // the pointer).
    property string arrangeTarget: ""
    function controlLabel(n) { const e = gridEntry(n); return e ? e.label : n }
    function openControlMenu(name, item, p) {
        if (!newControls) return
        const group = ubar.movable.find(g => g.indexOf(name) >= 0)
        if (!group) return
        const i = group.indexOf(name)
        const rows = []
        if (i > 0) rows.push({ action: "before", label: qsTr("Move before \"%1\"").arg(controlLabel(group[i - 1])), icon: "nmc-move-before" })
        if (i < group.length - 1) rows.push({ action: "after", label: qsTr("Move after \"%1\"").arg(controlLabel(group[i + 1])), icon: "nmc-move-after" })
        rows.push({ action: "unpin", label: qsTr("Unpin"), icon: "nmc-unpin" }, { separator: true },
                  { action: "reset", label: qsTr("Reset meeting controls"), icon: "nmc-reset" })
        arrangeTarget = name
        arrangeMenu.items = rows
        const q = item.mapToItem(win.contentItem, p.x, p.y)
        arrangeMenu.x = Math.min(q.x - 5, win.width - arrangeMenu.implicitWidth)
        arrangeMenu.y = q.y - 4
        arrangeMenu.open()
    }
    function openGridMenu(name, q) {
        const rows = []
        const grid = ubar.more.filter(s => s.grid).reduce((a, s) => a.concat(s.items.map(i => i.name)), [])
        if (name !== "MeetingAppsAddButton" && (grid.indexOf(name) >= 0 || ubar.overflowed.indexOf(name) >= 0))
            rows.push({ action: "pin", label: qsTr("Pin"), icon: "nmc-pin" }, { separator: true })
        rows.push({ action: "reset", label: qsTr("Reset meeting controls"), icon: "nmc-reset" })
        arrangeTarget = name
        arrangeMenu.items = rows
        arrangeMenu.x = Math.min(q.x - 5, win.width - arrangeMenu.implicitWidth)
        arrangeMenu.y = q.y - 4
        arrangeMenu.open()
    }
    function arrange(action, name) {
        const c = JSON.parse(JSON.stringify(controlsCustomization))
        c.unpinned = c.unpinned || []; c.pinned = c.pinned || []; c.order = c.order || []
        if (action === "reset") { saveCustomization(null); return }
        if (action === "unpin") {
            c.unpinned = [name].concat(c.unpinned.filter(n => n !== name))
            c.pinned = c.pinned.filter(n => n !== name)
        } else if (action === "pin") {
            if (c.unpinned.indexOf(name) >= 0) c.unpinned = c.unpinned.filter(n => n !== name)
            else if (ubar.overflowed.indexOf(name) < 0 && c.pinned.indexOf(name) < 0) c.pinned.push(name)
        } else {
            const order = ubar.movable.map(g => g.slice())
            const g = order.find(g => g.indexOf(name) >= 0)
            if (!g) return
            const i = g.indexOf(name), j = action === "before" ? i - 1 : i + 1
            if (j < 0 || j >= g.length) return
            g[i] = g[j]; g[j] = name
            c.order = order.reduce((a, g2) => a.concat(g2), [])
        }
        saveCustomization(c)
    }
    MenuPopup {
        id: arrangeMenu
        viewStyle: true; newStyle: true
        parent: win.contentItem
        minRowWidth: 181.67
        onPicked: i => win.arrange(items[i].action, win.arrangeTarget)
    }
    function arrangeForTest(action, name) { arrange(action, name) }

    // Drag and drop between the bar and More (the new controls; Teams'
    // dnd-kit, measured on winpc 2026-11-16, docs/spec/new-meeting-
    // controls.md §6a): a customizable bar control or a grid item moves
    // after 2 px. A copy follows the pointer at 0.7 opacity, drawn as a
    // bar button over the bar (as a grid item over More), in its hover
    // fill; the bar makes room where it would land and the control itself
    // is hidden there. Over More (the button or its menu) a bar control is
    // unpinned: More shows pressed and the copy fades to 0.4. Over a
    // control of its own group a bar control moves before it when dragged
    // left, after it when dragged right; a grid item dropped on the bar is
    // pinned there. Over a control that can't take it (Mic, Camera, Share,
    // Leave) the pointer says it isn't allowed. Escape cancels. The result
    // is saved as Move / Pin / Unpin save it.
    property var dragState: null
    /// The arrangement shown while dragging (saved on a drop).
    property var dragPreview: null
    /// Where the pointer is: "bar" (a place on the bar), "more" (More),
    /// "blocked", or "".
    property string dragZone: ""
    /// Draw the dragged copy as a grid item ("grid") or a bar button.
    property string dragLook: "bar"
    function dragInside(it, p) {
        if (!it || !it.visible) return false
        const q = it.mapToItem(win.contentItem, 0, 0)
        return p.x >= q.x && p.x < q.x + it.width && p.y >= q.y && p.y < q.y + it.height
    }
    /// The bar control under `p` (window coordinates), or "".
    function barControlAt(p) {
        for (const n of ubar.bar) if (n !== "|" && dragInside(barItems[n], p)) return n
        return ""
    }
    function dragOverMore(p) {
        if (dragInside(barItems["MoreButton"], p) && ubar.bar.indexOf("MoreButton") >= 0) return true
        return newMore.visible && p.x >= newMore.x && p.x < newMore.x + newMore.width && p.y >= newMore.y && p.y < newMore.y + newMore.height
    }
    function dragCopy(c) {
        const o = JSON.parse(JSON.stringify(c || {}))
        o.unpinned = o.unpinned || []; o.pinned = o.pinned || []; o.order = o.order || []
        return o
    }
    /// Start dragging `name` from the bar or the grid, the pointer at `p`.
    function dragBegin(name, from, p, topLeft) {
        if (!newControls || !name || name === "MeetingAppsAddButton") return false
        const groups = ubar.movable.map(g => g.slice())
        const grid = ubar.more.filter(s => s.grid).reduce((a, s) => a.concat(s.items.map(i => i.name)), [])
        const movable = groups.some(g => g.indexOf(name) >= 0)
        if (from === "bar" ? !movable : !(movable || grid.indexOf(name) >= 0)) return false
        const q = topLeft || p
        dragState = { name: name, from: from, start: p, offset: Qt.point(p.x - q.x, p.y - q.y), groups: groups,
                      label: controlLabel(name), icon: (gridEntry(name) || {}).icon || "" }
        dragLook = from === "grid" ? "grid" : "bar"
        dragZone = ""
        dragPreview = null
        dragGhost.place(p)
        return true
    }
    function dragMove(p) {
        const d = dragState
        if (!d || d.cancelled) return
        dragGhost.place(p)
        const dx = p.x - d.start.x
        const base = dragCopy(controlsCustomization)
        const order = d.groups.reduce((a, g) => a.concat(g), [])
        if (dragOverMore(p)) {
            // Only a bar control can be unpinned; a grid item over its
            // own menu changes nothing.
            if (d.from === "bar" || ubar.overflowed.indexOf(d.name) >= 0) {
                base.unpinned = [d.name].concat(base.unpinned.filter(n => n !== d.name))
                base.pinned = base.pinned.filter(n => n !== d.name)
                dragPreview = base; dragZone = "more"
            } else { dragPreview = null; dragZone = "" }
            return
        }
        const over = barControlAt(p)
        if (!over) {
            // Off the controls: nothing would change (the bar's own gaps
            // keep the last place).
            if (!dragInside(bar, p)) { dragPreview = null; dragZone = "" }
            return
        }
        dragLook = "bar"
        if (over === d.name) return
        const target = d.groups.find(g => g.indexOf(over) >= 0)
        const own = d.groups.find(g => g.indexOf(d.name) >= 0)
        if (!target || (own && own !== target)) { dragPreview = null; dragZone = "blocked"; return }
        // Before when dragged left, after when dragged right (Teams'
        // resolveMode on the drag's horizontal travel).
        const rest = order.filter(n => n !== d.name)
        const at = rest.indexOf(over) + (dx > 0 ? 1 : 0)
        rest.splice(at, 0, d.name)
        base.order = rest
        if (!own) {
            if (base.unpinned.indexOf(d.name) >= 0) base.unpinned = base.unpinned.filter(n => n !== d.name)
            else if (base.pinned.indexOf(d.name) < 0) base.pinned.push(d.name)
        }
        dragPreview = base; dragZone = "bar"
    }
    function dragEnd(dropped) {
        const d = dragState
        const result = dragPreview
        const keep = dropped && d && !d.cancelled && result && (dragZone === "bar" || dragZone === "more")
        if (keep) {
            console.info("meeting controls: dragged", d.name, dragZone === "more" ? "into More" : "on the bar")
            saveCustomization(result)
        }
        dragPreview = null; dragZone = ""; dragState = null
    }
    function dragCancel() { if (dragState) { dragState = Object.assign({}, dragState, { cancelled: true }); dragPreview = null; dragZone = "" } }
    Shortcut { sequence: "Escape"; enabled: !!win.dragState; onActivated: win.dragCancel() }
    // The dragged copy: a bar button (56 x 60, its 48 px button in the
    // hover fill) or a grid item (70 x 52), above the menus.
    Item {
        id: dragGhost
        parent: Overlay.overlay
        z: 1000
        visible: !!win.dragState && !win.dragState.cancelled
        width: win.dragLook === "grid" ? 70 : 56; height: win.dragLook === "grid" ? 52 : 60
        opacity: win.dragZone === "more" ? 0.4 : 0.7
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        function place(p) {
            const d = win.dragState
            if (!d) return
            const q = win.contentItem.mapToItem(parent, p.x - d.offset.x, p.y - d.offset.y)
            x = q.x; y = q.y
        }
        Rectangle {
            id: hcFillGhost
            x: win.dragLook === "grid" ? 0 : 4; y: win.dragLook === "grid" ? 0 : 6
            width: win.dragLook === "grid" ? 70 : 48; height: win.dragLook === "grid" ? 52 : 48
            radius: 4; color: theme.nmcHover
            FluentIcon {
                x: win.dragLook === "grid" ? 22.5 : 11.5; y: win.dragLook === "grid" ? 4.5 : 3.5; size: 25
                name: win.dragState ? win.dragState.icon : ""; color: theme.onFill(hcFillGhost, theme.text)
            }
            Text {
                x: 0.7; y: win.dragLook === "grid" ? 33.3 : 30.3; width: parent.width - 1.3; height: 16
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: win.dragState ? win.dragState.label : ""; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 11; color: theme.onFill(hcFillGhost, theme.text)
            }
        }
    }
    function dragForTest(name, from, points, drop) {
        const it = from === "bar" ? barItems[name] : null
        if (!dragBegin(name, from, points[0], it ? it.mapToItem(win.contentItem, 0, 0) : null)) return false
        for (const p of points.slice(1)) dragMove(p)
        const zone = dragZone
        if (drop) dragEnd(true)
        return zone
    }
    /// A bar control's centre (window coordinates), or (0, 0).
    function centerForTest(name) {
        const it = ubar.bar.indexOf(name) >= 0 ? barItems[name] : null
        return it ? it.mapToItem(win.contentItem, it.width / 2, it.height / 2) : Qt.point(0, 0)
    }
    /// A grid item's centre while More is open (its 24.67 px inset, 96 px
    /// columns and 58 px rows).
    function gridCenterForTest(name) {
        const i = newGridItems.filter(e => !e.apps).findIndex(e => e.name === name)
        if (i < 0 || !newMore.visible) return Qt.point(0, 0)
        return Qt.point(newMore.x + 24.67 + (i % 3) * 96 + 35, newMore.y + 12.67 + Math.floor(i / 3) * 58 + 26)
    }
    function dragEndForTest(drop) { if (drop === "escape") { dragCancel(); dragEnd(true) } else dragEnd(drop) }
    function controlMenuForTest(name) { const it = barItems[name]; if (it) openControlMenu(name, it, Qt.point(24, 24)) }
    function arrangeMenuForTest() { return arrangeMenu }
    // Dial pad: Teams' keypad under the button; keys send tones.
    Popup {
        id: dialPad
        x: parent ? (parent.width - width) / 2 : 0; y: parent ? parent.height + 4 : 0
        width: 236; padding: 12
        property string dialed: ""
        onOpened: dialed = ""
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 8
            focus: true
            Keys.onPressed: e => {
                const k = e.text
                if (k && "0123456789*#".indexOf(k) >= 0) { dialPad.press(k); e.accepted = true }
            }
            Rectangle {
                width: 212; height: 36; radius: theme.radius
                color: theme.input; border.color: theme.stroke
                Text {
                    x: 10; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                    text: dialPad.dialed; elide: Text.ElideLeft
                    font.family: theme.font; font.pixelSize: 18; color: theme.text
                }
                FluentIcon {
                    visible: dialPad.dialed.length > 0
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    name: "backspace-20"; size: 20; color: theme.textStrong
                    TapHandler { onTapped: dialPad.dialed = dialPad.dialed.slice(0, -1) }
                }
            }
            Grid {
                columns: 3; spacing: 4
                Repeater {
                    model: [["1", ""], ["2", "ABC"], ["3", "DEF"], ["4", "GHI"], ["5", "JKL"], ["6", "MNO"],
                            ["7", "PQRS"], ["8", "TUV"], ["9", "WXYZ"], ["*", ""], ["0", "+"], ["#", ""]]
                    Rectangle {
                        id: hcFill9
                        required property var modelData
                        width: 68; height: 48; radius: theme.radius
                        color: kh.pressed ? theme.selected : kh2.hovered ? theme.rowHover : "transparent"
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; font.family: theme.font; font.pixelSize: 20; color: theme.onFill(hcFill9, theme.text) }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 10; color: theme.onFill(hcFill9, theme.textSecondary); visible: text.length > 0 }
                        }
                        HoverHandler { id: kh2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: kh; onTapped: dialPad.press(modelData[0]) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Dial %1").arg(modelData[0])
                    }
                }
            }
        }
        function press(k) { dialed += k; win.dtmf(k) }
    }

    // Transfer / Consult: Teams' "Transfer to" picker under the button.
    Popup {
        id: picker
        property string mode: "transfer"
        x: 0; y: parent ? parent.height + 4 : 0
        width: 320; padding: 12
        onOpened: { who.text = ""; who.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 8
            Text {
                text: picker.mode === "transfer" ? qsTr("Transfer the call") : qsTr("Choose a person to consult")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
            Rectangle {
                width: 296; height: 32; radius: theme.radius
                color: theme.input; border.color: who.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: who
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !who.text; text: qsTr("Type a name"); color: theme.textTertiary; font: who.font }
                    onTextChanged: win.searchPeople(text)
                    Keys.onEscapePressed: picker.close()
                    Accessible.name: picker.mode === "transfer" ? qsTr("Transfer the call") : qsTr("Choose a person to consult")
                }
            }
            Repeater {
                model: who.text.trim().length >= 2 ? win.directory.slice(0, 6) : []
                Rectangle {
                    id: hcFill10
                    required property var modelData
                    width: 296; height: 44; radius: theme.radius
                    color: ph.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 28; name: modelData.name; photoId: "8:orgid:" + modelData.id }
                    Column {
                        x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill10, theme.text) }
                        Text { width: parent.width; elide: Text.ElideRight; visible: !!modelData.job_title || !!modelData.mail; text: modelData.job_title || modelData.mail; font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill10, theme.textSecondary) }
                    }
                    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                    // Consult: Start a call (the row) or Open chat.
                    Text {
                        id: openChat
                        visible: picker.mode === "consult"
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: qsTr("Open chat"); font.family: theme.font; font.pixelSize: theme.small; color: theme.brandForeground1
                        z: 2
                        TapHandler { onTapped: { picker.close(); win.consulting = { id: modelData.id, name: modelData.name }; win.consult(modelData.id, modelData.name) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Open chat with %1").arg(modelData.name)
                    }
                    TapHandler {
                        onTapped: {
                            picker.close()
                            if (picker.mode === "transfer") win.transfer(modelData.id, modelData.name)
                            else win.consultByCall(modelData.id, modelData.name)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: (picker.mode === "transfer" ? qsTr("Transfer to %1") : qsTr("Start a call with %1")).arg(modelData.name)
                }
            }
        }
    }
    // Consulting by call: the held call's banner with the consult call's
    // state and Teams' Transfer, Merge Calls and End consult.
    Rectangle {
        visible: !!win.consultCall && win.live
        z: 5
        anchors { top: bar.bottom; topMargin: 12; horizontalCenter: stage.horizontalCenter }
        width: callConsultRow.implicitWidth + 24; height: 44; radius: 8
        color: theme.menu; border.color: theme.dividerSoft
        readonly property string who: win.consultCall ? win.consultCall.name : ""
        readonly property string consultState: win.consultCall ? win.consultCall.state : ""
        Row {
            id: callConsultRow
            anchors.centerIn: parent; spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.consultState === "calling" ? qsTr("Calling %1…").arg(parent.parent.who)
                    : parent.parent.consultState === "transferring" ? qsTr("Transferring to %1").arg(parent.parent.who)
                    : parent.parent.consultState === "merging" ? qsTr("Merging calls...")
                    : qsTr("Consulting with %1", "calling:kbasbnmza").arg(parent.parent.who)
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            Repeater {
                model: [
                    { key: "transfer", label: qsTr("Transfer"), primary: true, on: true },
                    { key: "merge", label: qsTr("Merge Calls"), primary: false, on: true },
                    { key: "end", label: qsTr("End consult"), primary: false, on: false }
                ]
                Rectangle {
                    id: hcFillC
                    required property var modelData
                    readonly property bool usable: modelData.key === "end" || win.consultCall && win.consultCall.state === "connected"
                    width: Math.max(84, cLabel.implicitWidth + 24); height: 28; radius: theme.radius
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.primary ? (usable ? theme.brandFill : theme.bgDisabled) : theme.input
                    border.color: modelData.primary ? "transparent" : theme.stroke
                    Text {
                        id: cLabel
                        anchors.centerIn: parent; text: modelData.label
                        color: !parent.usable ? theme.disabled : parent.modelData.primary ? theme.onFill(hcFillC, "white") : theme.text
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: parent.modelData.primary ? Font.DemiBold : Font.Normal
                    }
                    TapHandler {
                        enabled: parent.usable
                        onTapped: parent.modelData.key === "transfer" ? win.consultTransfer() : parent.modelData.key === "merge" ? win.consultMerge() : win.consultEnd()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
    }
    // Consulting: a banner over the stage with Transfer and Resume.
    Rectangle {
        visible: !!win.consulting && win.live
        z: 5
        anchors { top: bar.bottom; topMargin: 12; horizontalCenter: stage.horizontalCenter }
        width: consultRow.implicitWidth + 24; height: 44; radius: 8
        color: theme.menu; border.color: theme.dividerSoft
        Row {
            id: consultRow
            anchors.centerIn: parent; spacing: 12
            Text { anchors.verticalCenter: parent.verticalCenter; text: win.consulting ? qsTr("Consulting with %1", "calling:kbasbnmza").arg(win.consulting.name) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Rectangle {
                id: hcFill11
                width: 84; height: 28; radius: theme.radius; color: theme.brandFill
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: qsTr("Transfer"); color: theme.onFill(hcFill11, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                TapHandler { onTapped: { const c = win.consulting; win.consulting = null; win.transfer(c.id, c.name) } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Transfer to %1").arg(win.consulting ? win.consulting.name : "")
            }
            Rectangle {
                width: 84; height: 28; radius: theme.radius; color: theme.input; border.color: theme.stroke
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: qsTr("Resume"); color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                TapHandler { onTapped: { win.consulting = null; if (win.held) win.toggleHold() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Stop consulting and resume")
            }
        }
    }

    function consultForTest(oid, name) { consulting = { id: oid, name: name }; consult(oid, name) }
    function consultByCallForTest(oid, name) { consultByCall(oid, name) }
    function transferFromConsultForTest() { const c = consulting; consulting = null; transfer(c.id, c.name) }
    function dialPadForTest() { dialPad.open() }
    function leaveMenuForTest() { leaveMenu.open() }
    function audioOptionsForTest() { openAudioOptions(barItem("MicrophoneButton")) }
    function inviteForTest() { side = "people"; inviteDialog.open() }
    function closeDialPadForTest() { dialPad.close() }
    function pressForTest(keys) { for (const k of keys) dialPad.press(k) }

    // Teams' call toolbar button (ubar, measured on winpc): a 56 px slot
    // holding a 48 x 48 button 6 px from the top; a 25 px glyph at
    // (11.5, 3.5) over an 11 px label; #424242 at rest (#242424 for the
    // media buttons), #EBEBEB behind and #242424 on hover; a 2 px brand
    // line under it while its pane is open.
    // The bar's controls (see barComponent), with Teams' labels and
    // tooltips (titles and shortcuts as Teams shows them).
    // Compact: 9 wide, the line 4 in and 21.6 tall.
    Component { id: barDivider; Item { width: win.ubarDivider; height: bar.height; Rectangle { x: win.compactBar ? 4 : 8; y: win.compactBar ? 8.9 : 13.5; width: 0.67; height: win.compactBar ? 21.6 : 33; color: theme.stroke } } }
    Component { id: cPopout; BarButton { icon: "call-popout"; label: qsTr("Pop out"); tip: qsTr("Pop out"); onClicked: win.runControl("PopoutContentButton") } }
    // Presenting a Whiteboard: Teams' whiteboard-sharing-controls, "Stop
    // sharing" (62 wide, measured 2026-11-18).
    Component {
        id: cContentStop
        BarButton {
            icon: win.newControls ? "nmc-share-stop" : "call-share-stop-filled"; label: qsTr("Stop sharing"); strong: !win.newControls
            iconColor: theme.hc("#B10E1C", "#FFFFFF")
            tip: qsTr("Stop sharing")
            onClicked: win.runControl("WhiteboardControlsSection")
        }
    }
    // Presenting PowerPoint Live: Layout (Content only, Cameo) and Stop
    // sharing (ppt-sharing-layout-toolbar, stopPresentingPptBtn).
    Component {
        id: cPptControls
        Row {
            // Viewing: Take control (ppt-sharing-viewer-controls'
            // takeControlPptBtn).
            BarButton {
                visible: win.pptViewed
                icon: "take-control-20"; label: qsTr("Take control"); tip: qsTr("Take control")
                onClicked: win.runControl("PptControlsSection")
            }
            BarButton {
                visible: !win.pptViewed
                id: pptLayoutB
                icon: "scb-layout"; label: qsTr("Layout"); tip: qsTr("Layout")
                onClicked: { pptLayoutMenu.parent = pptLayoutB; pptLayoutMenu.open() }
            }
            BarButton {
                visible: !win.pptViewed
                icon: win.newControls ? "nmc-share-stop" : "call-share-stop-filled"; label: qsTr("Stop sharing"); strong: !win.newControls
                iconColor: theme.hc("#B10E1C", "#FFFFFF")
                tip: qsTr("Stop sharing")
                onClicked: win.runControl("PptControlsSection")
            }
        }
    }
    // PowerPoint Live's Layout: Content only or Cameo (your camera on the
    // slide).
    property string pptLayout: "ContentOnly"
    onPptPresentingChanged: if (!pptPresenting) pptLayout = "ContentOnly"
    readonly property bool pptCameoDetected: {
        const s = contentStageForTest()
        return !!s && s.pptCameoDetected
    }
    // The slide show's layout: ours while we present, else the presenter's
    // (their weatherPerson state's mode, Teams' sharingLayoutMode).
    readonly property string pptStageLayout: {
        if (pptPresenting) return pptLayout
        const s = contentSession
        if (!s) return "ContentOnly"
        const p = pptPresenterEntry
        try { const l = p && p.weather_person ? JSON.parse(p.weather_person) : null; return l && l.mode === "Cameo" ? "Cameo" : "ContentOnly" } catch (e) { return "ContentOnly" }
    }
    // Cameo's picture: our camera while we present, else the presenter's
    // incoming video (each client composites it, as Teams).
    readonly property string pptCameoKey: pptPresenting ? (cameraOn ? "self" : "") : (pptPresenterEntry ? (videoKeys[pptPresenterEntry.id] || "") : "")
    readonly property var pptPresenterEntry: contentSession ? (roster.find(r => String(r.id).toLowerCase() === contentSession.presenter) || null) : null
    MenuPopup {
        id: pptLayoutMenu
        y: parent ? parent.height + 5 : 0
        items: [
            { label: qsTr("Content only"), checked: win.pptLayout === "ContentOnly" },
            // Teams: Cameo needs your camera and a cameo in the deck.
            { label: qsTr("Cameo"), checked: win.pptLayout === "Cameo", enabled: win.cameraOn && win.pptCameoDetected,
              tip: !win.cameraOn ? qsTr("Turn on your camera to select this layout") : !win.pptCameoDetected ? qsTr("Add your video feed to this slide to use Cameo.") : "" }
        ]
        onPicked: i => { win.pptLayout = i === 1 ? "Cameo" : "ContentOnly"; backend.contentPptCameo(win.pptLayout === "Cameo") }
    }
    // Teams' "Stop presenting?" (400 x 205, measured 2026-11-18).
    ConfirmDialog {
        id: stopPresentingDialog
        dialogWidth: 400
        title: qsTr("Stop presenting?")
        body: qsTr("This will end the presentation for everyone. To switch presenters select Cancel so the next person can take control")
        confirmText: qsTr("Stop presenting")
        onConfirmed: backend.contentShareStop()
    }
    Component { id: cTransfer; BarButton { icon: "call-transfer"; label: qsTr("Transfer"); tip: qsTr("Transfer"); enabled: win.controlEnabled("CallTransferButtonV2"); checked: picker.visible && picker.mode === "transfer"; onClicked: win.runControl("CallTransferButtonV2") } }
    Component { id: cConsult; BarButton { icon: "consult"; label: qsTr("Consult"); tip: qsTr("Consult then transfer"); enabled: win.controlEnabled("CallConsultativeTransferButtonV2"); checked: picker.visible && picker.mode === "consult"; onClicked: win.runControl("CallConsultativeTransferButtonV2") } }
    Component { id: cDialpad; BarButton { icon: "dialpad"; label: qsTr("Dial pad"); tip: qsTr("Dial pad"); enabled: win.controlEnabled("DialpadButton"); checked: dialPad.visible; onClicked: win.runControl("DialpadButton") } }
    Component { id: cHold; BarButton { icon: "pause"; label: qsTr("Hold"); tip: qsTr("Hold"); enabled: win.controlEnabled("HoldButton"); onClicked: win.runControl("HoldButton") } }
    // Held: Teams' "Resume" text button in the contextual group.
    Component {
        id: cResume
        Item {
            width: win.ubarWidths.ResumeButton; height: 60
            Rectangle {
                id: hcFill12
                x: 4; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 8; height: 48; radius: theme.radius
                color: rph.hovered ? theme.hc(theme.pane, theme.hcHighlight) : theme.rowHover
                border.color: theme.stroke
                Row {
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "play-20"; size: 20; color: theme.onFill(hcFill12, theme.text) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Resume"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(hcFill12, theme.text) }
                }
                HoverHandler { id: rph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.runControl("ResumeButton") }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Resume")
            }
        }
    }
    // Copilot (meeting-collab-button): Teams' Copilot mark, filled while
    // its pane is open; "Open Copilot (Alt+C)" / "Close Copilot".
    Component { id: cCopilot; BarButton { icon: win.side === "copilot" ? "copilot-filled-48" : "ai-copilot"; label: qsTr("Copilot"); checked: win.side === "copilot"; tip: win.side === "copilot" ? qsTr("Close Copilot") : qsTr("Open Copilot"); shortcut: win.side === "copilot" ? "" : "Alt+C"; enabled: win.controlEnabled("MeetingCollabButton"); onClicked: win.runControl("MeetingCollabButton") } }
    Component { id: cChat; BarButton { icon: win.newControls ? "nmc-chat" : "call-chat"; label: qsTr("Chat"); checked: win.side === "chat"; tip: win.side === "chat" ? qsTr("Hide conversation") : qsTr("Show conversation"); enabled: win.controlEnabled("ChatButton"); onClicked: win.runControl("ChatButton") } }
    Component {
        id: cPeople
        BarButton {
            icon: win.newControls ? "nmc-people" : "call-people"; label: qsTr("People"); checked: win.side === "people"
            readonly property int count: win.roster.length
            // The new controls' tooltip has no count.
            tip: (count === 0 || win.newControls ? "" : (qsTr("%n participants.", "", count) + " ")) + (win.side === "people" ? qsTr("Hide participants") : qsTr("Show participants"))
            // Teams: people waiting in the lobby, or raised hands, as a
            // red count; else how many are here (meetings).
            badge: !win.meeting ? 0 : win.lobby.length > 0 ? win.lobby.length : win.hands.length > 0 ? win.hands.length : win.roster.length > 1 ? win.roster.length : 0
            badgeAlert: win.lobby.length > 0 || win.hands.length > 0
            enabled: win.controlEnabled("RosterButton")
            onClicked: win.runControl("RosterButton")
        }
    }
    // Teams' raise-hand button (unified-bar-container-manager's Y2): its
    // label is always calling_raise_hand_icon_label ("Raise"), shown active
    // while your hand is up; only its tooltip (and aria label) says Lower.
    // Full screen is the same: one "Full screen" label, toggled.
    Component { id: cRaise;BarButton { icon: "call-raise"; label: qsTr("Raise", "calling:k9th2ytq2"); checked: win.handRaised; tip: win.handRaised ? qsTr("Lower your hand") : qsTr("Raise your hand"); shortcut: "Ctrl+Shift+K"; enabled: win.controlEnabled("RaiseHandsButton"); onClicked: win.runControl("RaiseHandsButton") } }
    // The new controls: React holds Raise hand too; its glyph is the
    // emoji-hand, filled in brand while your hand is up.
    Component { id: cReact; BarButton { icon: !win.newControls ? "call-react" : win.handRaised ? "nmc-react-filled" : "nmc-react"; label: qsTr("React"); checked: reactMenu.visible
            iconColor: win.newControls && win.handRaised ? theme.brand : hovered ? theme.text : theme.textStrong
            tip: !win.newControls ? qsTr("Send a reaction") : win.handRaised ? qsTr("React or lower your hand. Your hand is raised") : qsTr("React or raise your hand. Your hand is not raised"); enabled: win.controlEnabled("ReactionButton"); onClicked: win.runControl("ReactionButton") } }
    Component { id: cView; BarButton { id: viewB; icon: "call-view"; label: qsTr("View"); tip: qsTr("Change your view"); checked: viewMenu.visible && viewMenu.parent === viewB; enabled: win.controlEnabled("ViewModeButton"); onClicked: win.runControl("ViewModeButton") } }
    // Controls: the meeting options (organizers), as Teams opens them.
    Component { id: cControls; BarButton { id: ctlB; icon: win.newControls ? "nmc-controls" : "call-controls"; label: qsTr("Controls"); checked: controlsMenu.visible; enabled: win.controlEnabled("OrganizerControlButton"); onClicked: win.runControl("OrganizerControlButton"); Component.onCompleted: win.controlsButton = ctlB } }
    // Notes: Teams keeps meeting notes in the meeting chat's Notes tab.
    Component { id: cNotes; BarButton { icon: win.newControls ? "nmc-notes" : "call-notes"; label: qsTr("Notes"); tip: win.side === "notes" ? qsTr("Close notes") : qsTr("Open notes"); checked: win.side === "notes"; enabled: win.controlEnabled("MeetingDetailsButton"); onClicked: win.runControl("MeetingDetailsButton") } }
    Component { id: cRooms; BarButton { icon: win.newControls ? "nmc-rooms" : "call-rooms"; label: qsTr("Rooms"); tip: win.breakoutRooms.length ? qsTr("Breakout rooms") : qsTr("Create breakout rooms"); checked: win.side === "rooms"; enabled: win.controlEnabled("StartBreakoutRoomButton"); onClicked: win.runControl("StartBreakoutRoomButton") } }
    // A More grid control the user pinned to the bar (new controls): its
    // grid label and glyph.
    Component {
        id: cPinned
        BarButton {
            readonly property string ctl: parent ? parent.modelData : ""
            readonly property var entry: win.gridEntry(ctl) || ({ label: "", icon: "" })
            icon: entry.icon; label: entry.label; tip: entry.label
            checked: !!entry.checked
            enabled: entry.enabled !== false
            onClicked: win.runControl(ctl)
        }
    }
    // Teams' contextual text buttons (the layout's "button" template): a
    // bordered 31.33 tall button, 14/600, padded 12, in an 8 wider slot.
    component BarTextButton: Item {
        id: btb
        property string label
        property string control
        property bool primary: false
        property bool usable: true
        property string tip: ""
        width: btbText.implicitWidth + 24.67 + 16; height: bar.height
        Rectangle {
            id: hcFill13
            anchors.centerIn: parent
            width: btbText.implicitWidth + 24.67; height: 31.33; radius: 4
            color: btb.primary ? (!btb.usable ? theme.pick("#F0F0F0", "#333333", "#000000") : btbHover.hovered ? theme.brandHover : theme.brandFill)
                : btbHover.hovered ? theme.menuHover : theme.surface
            border.color: btb.primary ? "transparent" : theme.stroke; border.width: 0.67
            Text {
                id: btbText
                anchors.centerIn: parent
                text: btb.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: !btb.usable ? theme.disabled : btb.primary ? theme.textOnBrand : theme.onFill(hcFill13, theme.text)
            }
            HoverHandler { id: btbHover; cursorShape: btb.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: btb.usable; onTapped: win.runControl(btb.control) }
            ToolTip.visible: btb.tip !== "" && btbHover.hovered; ToolTip.text: btb.tip
        }
        Accessible.role: Accessible.Button
        Accessible.name: btb.label
    }
    Component { id: cJoinRoom; BarTextButton { label: qsTr("Join room"); control: "ReturnToBreakoutRoomButton" } }
    // Start meeting (primary) and End event in the end slot; disabled
    // while a presenter starts or ends it (Teams' tooltips).
    // Teams' StagingRoomStartMeetingButton and End event: bar buttons with
    // their glyph (PlayCircle filled, DismissCircle) and label, as wide as
    // the label (measured 2026-11-18: "Start event" 53.4, "End event"
    // 49.3), greyed while a presenter starts or ends it.
    Component { id: cStartEvent; BarButton { icon: "play-circle-20-filled"; label: win.startLabel; labelPad: 1.33; enabled: !win.liveEvent.busy
        tip: win.liveEvent.busy ? (win.liveEvent.streaming ? qsTr("A presenter already started the event") : qsTr("A presenter already started the meeting")) : win.startLabel
        onClicked: win.runControl("StagingRoomStartMeetingButton") } }
    Component { id: cEndEvent; BarButton { icon: "dismiss-circle-20"; label: win.endLabel; labelPad: 1.33; enabled: !win.liveEvent.busy
        tip: win.liveEvent.busy ? (win.isEvent ? qsTr("Someone already ended the event") : qsTr("Someone already ended the meeting")) : win.endLabel
        onClicked: win.runControl("StagingRoomEndMeetingButton") } }
    Component { id: cQna; BarButton { icon: "chat-bubbles-question-20"; label: "Q&A"; tip: "Q&A"; checked: win.side === "qna"; onClicked: win.runControl("YammerQnaButton") } }
    Component { id: cReturnMain; BarTextButton { label: qsTr("Return"); control: "BreakoutRoomReturnToMainButton" } }
    Component { id: cApps; BarButton { id: appsB; icon: "call-apps"; label: qsTr("Apps"); tip: appsMenu.visible ? qsTr("Close apps") : qsTr("Find apps and more"); checked: appsMenu.visible && appsMenu.parent === appsB; onClicked: win.runControl("MeetingAppsAddButton") } }
    Component { id: cMore; BarButton { icon: win.newControls ? "nmc-more" : "call-more"; label: qsTr("More"); tip: qsTr("More actions"); checked: moreMenu.visible || newMore.visible; dropTarget: win.dragZone === "more"; onClicked: win.runControl("MoreButton") } }
    Component {
        id: cCamera
        BarButton {
            id: camB
            // The new controls draw the regular glyphs in #424242.
            icon: win.newControls ? (win.cameraOn ? "nmc-camera" : "nmc-camera-off") : win.cameraOn ? "call-camera-filled" : "call-camera-off-filled"
            label: qsTr("Camera"); strong: !win.newControls
            // Teams' disabled reasons, first match wins (§3).
            readonly property string disabledReason: !win.canVideo ? qsTr("No available camera found")
                : win.videoRestricted ? qsTr("Only select participants can share video") : ""
            tip: disabledReason.length > 0 ? disabledReason : win.cameraOn ? qsTr("Turn camera off") : qsTr("Turn camera on")
            shortcut: disabledReason.length > 0 ? "" : "Ctrl+Shift+O"
            enabled: win.controlEnabled("VideoButton") && !win.videoRestricted
            // Teams' Camera ▾ (video-button-configure, "Open video options").
            split: true; chevronLabel: qsTr("Open video options")
            chevronChecked: videoFlyout.visible && videoFlyout.parent === camB
            onClicked: win.runControl("VideoButton")
            onChevronClicked: { videoFlyout.parent = camB; videoFlyout.open() }
        }
    }
    Component {
        id: cMic
        BarButton {
            id: micB
            icon: win.newControls ? (win.muted || !win.hasAudio ? "nmc-mic-off" : "nmc-mic") : win.muted || !win.hasAudio ? "call-mic-off-filled" : "call-mic-filled"
            label: qsTr("Mic"); strong: !win.newControls
            tip: win.micRestricted ? qsTr("Only select participants can unmute")
                : !win.hasAudio ? qsTr("Turn audio on") : win.muted ? qsTr("Unmute mic") : qsTr("Mute mic")
            shortcut: win.micRestricted ? "" : "Ctrl+Shift+M"
            enabled: win.controlEnabled("MicrophoneButton") && !win.micRestricted
            split: true; chevronLabel: qsTr("Open audio options")
            chevronChecked: audioFlyout.visible && audioFlyout.parent === micB
            onClicked: win.runControl("MicrophoneButton")
            onChevronClicked: win.openAudioOptions(micB)
        }
    }
    // Teams' ScreensharingControlButton (someone else presents and their
    // screen can be controlled): Take control, Waiting for approval,
    // Stop control.
    Component {
        id: cTakeControl
        BarButton {
            readonly property string st: win.controlState.state || "none"
            icon: "take-control-20"
            label: st === "controlling" ? qsTr("Stop control") : st === "requested" ? qsTr("Waiting for approval") : qsTr("Take control")
            checked: st === "controlling"
            tip: win.controlState.deniedBySharer ? qsTr("Requesting control is disabled by the sharer company's administrator")
                : st === "controlling" ? qsTr("Stop control") : st === "requested" ? qsTr("Waiting for approval") : qsTr("Take control of the presentation")
            enabled: win.controlEnabled("ScreensharingControlButton")
            onClicked: win.runControl("ScreensharingControlButton")
        }
    }
    Component {
        id: cShare
        BarButton {
            icon: win.newControls ? (win.sharing ? "nmc-share-stop" : "nmc-share") : win.sharing ? "call-share-stop-filled" : "call-share-filled"
            label: win.sharing ? qsTr("Stop sharing") : qsTr("Share"); strong: !win.newControls
            iconColor: win.sharing ? theme.hc("#B10E1C", "#FFFFFF") : win.newControls && !hovered ? theme.textStrong : theme.text
            tip: win.sharing ? qsTr("Stop sharing") : qsTr("Share content"); shortcut: "Ctrl+Shift+E"
            enabled: win.controlEnabled("ShareButton")
            onClicked: win.runControl("ShareButton")
        }
    }

    // Teams' bar tooltip for the indicators: start-aligned 50 below the
    // indicator (4 under the bar), 12/16 text, padding 4 / 11 / 6, up to
    // 240 wide, its arrow at the indicator's centre.
    component IndicatorTip: ToolTip {
        id: it
        property Item target
        property bool shown: false
        parent: target
        visible: shown && text.length > 0
        delay: 250
        topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
        x: 0; y: 50
        contentItem: Text {
            text: it.text
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
            wrapMode: Text.Wrap
            width: Math.min(implicitWidth, 218)
        }
        background: Item {
            FluentSurface { anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }
            Rectangle {
                width: 8.48; height: 8.48; rotation: 45
                color: theme.surface
                x: it.target.width / 2 - width / 2 - 0.67
                y: -width / 2
            }
        }
    }
    component BarButton: Item {
        id: bb
        property string icon
        property string label
        property bool checked: false
        /// Camera, Mic, Share and Leave: #242424 at rest.
        property bool strong: false
        /// Leave: the new controls hover it in red tints.
        property bool danger: false
        /// More while a dragged control would be unpinned into it.
        property bool dropTarget: false
        readonly property bool hovered: bbHover.hovered
        property color iconColor: bb.strong || bbHover.hovered ? theme.text : theme.textStrong
        /// A count beside the icon (People: how many are in the meeting).
        property int badge: 0
        /// Show the count as Teams' red alert badge (raised hands, lobby).
        property bool badgeAlert: false
        /// Teams' split buttons (Leave, Camera, Mic): a 22 px chevron
        /// after the 48 px button, in a 74 px slot.
        property bool split: false
        property string chevronLabel: ""
        property bool chevronChecked: false
        /// Teams' tooltip and its keyboard shortcut ("{tip} ({shortcut})").
        property string tip: ""
        property string shortcut: ""
        signal clicked()
        signal chevronClicked()
        /// Right-click (the new controls' Move / Pin / Unpin menu), at the
        /// pointer in this button's coordinates.
        signal contextMenu(point p)
        /// The new controls' compact bar (under 480 px): a 32 px button in
        /// a 36 px slot without its label, the chevron 20 wide (slot 54).
        readonly property bool compact: win.compactBar
        // 48 wide, or wider for a long label (Teams' "Leave room").
        property real labelPad: 8
        readonly property real bw: compact ? 32 : Math.max(48, Math.ceil(bbLabelMetrics.advanceWidth) + labelPad)
        readonly property real bx: compact ? 2 : 4
        readonly property real by: compact ? 3.7 : 6
        readonly property real cw: compact ? 20 : 22
        TextMetrics { id: bbLabelMetrics; font.family: theme.font; font.pixelSize: 11; text: bb.label }
        width: split ? bx + bw + cw : bw + 2 * bx; height: compact ? 40 : 60
        // Teams' bar tooltip (Fluent Tooltip, measured on winpc): 10 below
        // the button, its left edge on the button's (or its right edge on
        // the button's when it would leave the window); 12/16 text,
        // padding 4 / 11 / 6, radius 4, a 12 px arrow at the button's
        // centre, shadows 2 and 8.
        function tipForTest() { bbTip.open() }
        ToolTip {
            id: bbTip
            parent: bb
            // Not over the screens that replace the bar once the call ends
            // (the test call's results, the call quality survey).
            visible: bb.tip.length > 0 && bbHover.hovered && !win.barCovered
            delay: 250
            topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
            readonly property bool flip: bb.mapToItem(null, 4 + implicitWidth, 0).x > (bb.Window.window ? bb.Window.window.width : 1e9)
            x: flip ? bb.bx + bb.bw - implicitWidth : bb.bx
            y: bb.by + (bb.compact ? 32 : 48) + 10
            contentItem: Text {
                text: bb.tip + (bb.shortcut.length > 0 ? " (" + bb.shortcut + ")" : "")
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
                wrapMode: Text.Wrap
                width: Math.min(implicitWidth, 218)
            }
            background: Item {
                FluentSurface { anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }
                Rectangle {
                    width: 8.48; height: 8.48; rotation: 45
                    color: theme.surface
                    x: (bbTip.flip ? bbTip.implicitWidth - 24 : 24) - width / 2 - 0.67
                    y: -width / 2
                }
            }
        }
        Rectangle {
            id: hcFill14
            visible: bb.split
            x: bb.bx + bb.bw; y: bb.by; width: bb.cw; height: bb.compact ? 32 : 48
            topRightRadius: 4; bottomRightRadius: 4
            // The new controls: the hovered half in Teams' bar hover, the
            // other half a shade lighter (Leave in its red tints).
            color: !win.newControls ? ((chevHover.hovered || bb.chevronChecked) ? theme.rowHover : "transparent")
                 : (chevHover.hovered || bb.chevronChecked) ? (bb.danger ? theme.nmcLeaveHover : theme.nmcHover)
                 : bbHover.hovered && bb.enabled ? (bb.danger ? theme.nmcLeaveHoverOther : theme.nmcHoverOther) : "transparent"
            // Disabled together with the button (Teams' split buttons).
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon { x: bb.compact ? 4 : 3; y: bb.compact ? 10 : 16; name: "call-chevron"; size: bb.compact ? 12 : 16
                         color: theme.onFill(hcFill14, !win.newControls || bb.strong || chevHover.hovered || bb.chevronChecked ? theme.text : theme.textStrong) }
            HoverHandler { id: chevHover; cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: bb.enabled; onTapped: bb.chevronClicked() }
            Accessible.role: Accessible.Button
            Accessible.name: bb.chevronLabel
        }
        Rectangle {
            id: hcFill15
            x: bb.bx; y: bb.by; width: bb.bw; height: bb.compact ? 32 : 48
            radius: 4
            topRightRadius: bb.split ? 0 : 4; bottomRightRadius: bb.split ? 0 : 4
            color: !win.newControls ? (bbHover.hovered && bb.enabled ? theme.rowHover : "transparent")
                 : bb.dropTarget ? theme.nmcDropTarget
                 : bbHover.hovered && bb.enabled ? (bb.danger ? theme.nmcLeaveHover : theme.nmcHover)
                 : bb.split && chevHover.hovered && bb.enabled ? (bb.danger ? theme.nmcLeaveHoverOther : theme.nmcHoverOther) : "transparent"
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon {
                x: bb.compact ? 6 : (bb.bw - 25) / 2; y: bb.compact ? 6 : 3.5
                // The new controls draw a checked control's glyph in brand
                // (white in High contrast).
                name: bb.icon; size: bb.compact ? 20 : 25; color: theme.onFill(hcFill15, win.newControls && (bb.checked || bb.dropTarget) ? theme.nmcChecked : bb.iconColor)
                // Teams' alert badge (roster-button-badge): 18 px with a
                // 2 px white ring, #C50F1F, 10/700 white, 16 px right of
                // and 1.8 px above the glyph's corner.
                Rectangle {
                    visible: bb.badge > 0 && bb.badgeAlert
                    x: 16; y: -1.8
                    width: Math.max(18, bbAlert.implicitWidth + 8); height: 18; radius: 10
                    color: theme.hc("#C50F1F", "#000000")
                    border.color: "white"; border.width: 2
                    Text {
                        id: bbAlert
                        anchors.centerIn: parent
                        text: bb.badge
                        font.family: theme.font; font.pixelSize: 10; font.weight: Font.Bold
                        color: "white"
                    }
                }
                Text {
                    visible: bb.badge > 0 && !bb.badgeAlert
                    x: parent.width - 2; y: -1
                    text: bb.badge
                    font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill15, bb.iconColor)
                }
            }
            Text {
                visible: !bb.compact
                x: 0.7; y: 30.3; width: bb.bw - 1.3; height: 16
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: bb.label
                elide: Text.ElideRight
                color: theme.onFill(hcFill15, bb.strong || bbHover.hovered || (win.newControls && bb.checked) ? theme.text : theme.textStrong)
                font.family: theme.font; font.pixelSize: 11
            }
            Rectangle {
                visible: bb.checked
                x: 0.7; y: bb.compact ? 34.3 : 50.3; width: bb.bw - 1.3; height: 2; radius: 1
                color: win.newControls ? theme.nmcChecked : theme.brand
            }
            HoverHandler { id: bbHover; cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (bb.enabled) bb.clicked() }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (ev) => bb.contextMenu(hcFill15.mapToItem(bb, ev.position.x, ev.position.y))
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: bb.label
    }
    RetryScreen {
        anchors.fill: parent
        z: 100
        visible: win.retryReason !== ""
        reason: win.retryReason
        onRetry: { win.retryReason = ""; win.rejoin() }
        onDismiss: win.retryReason = ""
    }
    // Teams' share tray (ShareTray.qml): under the bar, centred on Share
    // (kept in the window), down to 7.3 above the window's bottom.
    signal startShare(string kind)
    property alias shareIncludeSound: shareTray.includeSound
    /// PowerPoint Live or Excel Live for `file` ({name, url, driveId,
    /// itemId}); Excel Live gives the meeting's people edit access.
    function startOfficeLive(kind, file, confirmed) {
        // Excel Live asks first (Teams' "Share with all participants?").
        if (kind === "excel" && !confirmed) { meetingFileShareDialog.file = file; meetingFileShareDialog.open(); return }
        const people = others.map(p => String(p.id || "")).filter(i => i.indexOf("8:orgid:") === 0).map(i => i.slice(8))
        backend.contentShareStart(kind, JSON.stringify({ url: file.url || "", driveId: file.driveId || file.drive_id || "", itemId: file.itemId || file.id || "", people: people }))
    }
    MeetingFileShareDialog {
        id: meetingFileShareDialog
        property var file: null
        fileName: file ? (file.name || "") : ""
        learnMoreUrl: "https://support.microsoft.com/office/sharing-files-folders-and-list-items-74cab0bf-39c6-4112-a63f-88ee121722d0?ns=spostandard"
        onConfirmed: if (file) win.startOfficeLive("excel", file, true)
    }
    function openShareTray() {
        const b = barItem("ShareButton")
        const c = b && b !== bar ? b.mapToItem(win.contentItem, b.width / 2, 0).x : win.width / 2
        shareTray.x = Math.max(8, Math.min(win.width - 360 - 8, c - 180))
        shareTray.y = bar.height - 0.7
        shareTray.open()
        // PowerPoint Live's and Excel Live's recent files (Office's MRU).
        backend.contentRecentLoad()
    }
    function shareTrayForTest() { return shareTray }
    function contentStageForTest() { return contentStage }
    ShareTray {
        id: shareTray
        parent: win.contentItem
        cameraOn: win.cameraOn
        mode: win.presentingState.mode || "ContentOnly"
        backgroundId: win.presentingState.background ? win.presentingState.background.id : ""
        onShare: kind => { close(); win.shareKind = kind; win.startShare(kind) }
        onPickMode: m => win.setPresenterMode(m)
        onPickBackground: b => win.setPresenterBackground(JSON.stringify(b))
        onContentCamera: type => contentCameraDialog.openFor(type)
        onWhiteboard: { close(); backend.contentShareStart("whiteboard", "{}") }
        pptFiles: (win.contentState.recent || {}).ppt || []
        excelFiles: (win.contentState.recent || {}).excel || []
        onOfficeFile: (kind, file) => { close(); win.startOfficeLive(kind, file) }
        onBrowse: where => { close(); if (where === "onedrive") { officePicker.entry = "myfiles"; officePicker.open() } }
    }
    // Browse OneDrive: a deck from your OneDrive for PowerPoint Live (or a
    // workbook for Excel Live).
    CloudPicker {
        id: officePicker
        onAttached: files => {
            const f = files && files[0]
            if (!f) return
            const n = String(f.name || "").toLowerCase()
            win.startOfficeLive(/\.(xlsx|xlsm|xlsb)$/.test(n) ? "excel" : "ppt", { name: f.name, url: f.web_url || "", driveId: f.drive_id || "", itemId: f.id || "" })
        }
    }
    // Content from camera's setup (Teams' content camera setup dialog,
    // ContentCameraDialog.qml): the processed camera goes out as shared
    // content, as the screen does.
    ContentCameraDialog {
        id: contentCameraDialog
        onShare: device => { win.shareKind = "camera"; backend.startContentCamera(device) }
    }
    function contentCameraDialogForTest() { return contentCameraDialog }
    function sharingBarForTest() { return sharingBarLoader.item }
    /// The presenter's mode on the stage: {layout, comp, camKey, stage}.
    function presenterCompositeForTest() {
        return { layout: contentTile.wp, comp: contentTile.comp, camKey: contentTile.camKey, stage: [contentTile.width, contentTile.height],
                 share: [meetingShare.frameWidth, meetingShare.frameHeight], camera: [presenterCam.frameWidth, presenterCam.frameHeight] }
    }
    function requestControlDialogForTest() { return requestControlDialog }
    // Teams' Sharing control bar while we share (SharingControlBar.qml).
    Loader {
        id: sharingBarLoader
        active: win.sharing && win.meeting
        sourceComponent: Component {
            SharingControlBar { call: win; kind: win.shareKind }
        }
    }
    // Take control ▸ (Teams' ScreensharingControlButton): "Request
    // control?" first.
    // The green room's Start (Teams' staging-room-meeting-start-dialog)
    // and End event confirmations, and their failures.
    ConfirmDialog {
        id: startEventDialog
        readonly property bool th: win.townhallDelayMessage && !!win.liveEvent.townHall
        title: th ? qsTr("Start the event for everyone?") : qsTr("Start the meeting for everyone?")
        body: th ? qsTr("%n attendees will enter and watch the event at a slight delay.", "", win.attendeeCount)
                 : qsTr("%n attendees will enter the meeting", "", win.attendeeCount)
        confirmText: th ? qsTr("Start event") : qsTr("Start meeting")
        onConfirmed: backend.setEventLive(true)
    }
    ConfirmDialog {
        id: endEventDialog
        title: win.isEvent ? qsTr("End the event for attendees?") : qsTr("End the meeting for attendees?")
        body: win.isEvent ? qsTr("This will end the event for all attendees and return organizers and presenters to the Green Room.")
                          : qsTr("This will end the meeting for all attendees and return organizers and presenters to the Green Room.")
        confirmText: win.isEvent ? qsTr("End event for all attendees") : qsTr("End meeting")
        onConfirmed: backend.setEventLive(false)
    }
    property int eventFailures: 0
    function startEventForTest() { startEventDialog.close(); backend.setEventLive(true) }
    function streamForTest() { return { playing: streamPlayer.playing, waiting: streamPlayer.waiting, error: streamPlayer.error, staging: stagingScreen.visible } }
    function endEventForTest() { endEventDialog.close(); backend.setEventLive(false) }
    function leaveSplitForTest() { return leaveButton.split }
    function greenRoomAlertForTest() { return greenRoomAlert.visible }
    function greenRoomAlertTextForTest() { return { visible: greenRoomAlert.visible, text: greenRoomAlert.text, icon: greenRoomAlert.icon, waiting: win.recordingWaiting, w: greenRoomAlert.width, h: greenRoomAlert.height } }
    ConfirmDialog {
        id: eventFailedDialog
        property bool starting: true
        title: starting ? qsTr("Unable to start meeting") : (win.isEvent ? qsTr("Couldn't end event") : qsTr("Couldn't end meeting"))
        body: starting ? (win.eventFailures > 1 ? qsTr("Wait and try again later or ask another presenter or organizer to start the meeting for you.") : qsTr("Let's try starting the meeting again."))
                       : win.eventFailures > 1 ? qsTr("Wait and try again or ask another organizer to end it.") : (win.isEvent ? qsTr("Let's try ending the event again.") : qsTr("Let's try ending the meeting again."))
        confirmText: qsTr("Try again")
        onConfirmed: backend.setEventLive(starting)
    }
    Connections {
        target: backend
        function onCallEventJsonChanged() {
            const f = win.liveEvent.failed || ""
            if (f) { win.eventFailures++; eventFailedDialog.starting = f === "start"; eventFailedDialog.open() }
            else if (win.liveEvent.eventPhase === "active") win.eventFailures = 0
        }
    }
    // "Start the meeting whenever you're ready." (Teams' green room alert,
    // info, dismissable) while presenters wait in the green room.
    // Teams' calling alerts show one alert at a time, the latest on top:
    // in an auto-recorded event the call recorder joins the green room
    // waiting for the meeting to go live (its processing modes in the
    // state "WaitingForMeetingLive"), and Teams' recording alert
    // (RecordingAndTranscriptWaitingForMeetingLive, a dismissable warning
    // with the record glyph: "Recording and transcription will begin when
    // the meeting starts", or the recording's or the transcript's own)
    // covers the start alert, for a webinar's waiting attendees too
    // (measured on winpc 2026-11-19).
    property bool recordingWaitingClosed: false
    readonly property string recordingWaiting: backend.callRecordingWaiting
    onRecordingWaitingChanged: recordingWaitingClosed = false
    CallAlert {
        id: greenRoomAlert
        readonly property bool ended: win.liveEvent.eventPhase === "ended" && win.myRole !== "attendee"
        readonly property bool recording: win.recordingWaiting !== "" && !win.recordingWaitingClosed && !ended
        readonly property bool waitingRoom: win.ubarFacts.greenRoom || (stagingScreen.visible && stagingScreen.phase === "prelive")
        visible: (recording ? waitingRoom : (win.ubarFacts.greenRoom || ended) && !win.greenRoomAlertClosed) && !win.liveEvent.busy && !win.breakoutAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        recordingLayout: recording
        // Back in the green room after the end (Teams' info alert).
        text: recording ? (win.recordingWaiting === "Recording" ? qsTr("Recording will begin when the meeting starts")
                           : win.recordingWaiting === "Transcript" ? qsTr("Transcription will begin when the meeting starts")
                           : qsTr("Recording and transcription will begin when the meeting starts"))
            : !ended ? qsTr("Start the meeting whenever you're ready.")
            : win.isEvent ? qsTr("The event has ended for attendees. If recording was enabled, it has now stopped.")
            : qsTr("The meeting has ended for attendees and recording has stopped.")
        // Teams' alert icon map (263640): the record glyph for the
        // recording's alerts, the transcript's for its own.
        icon: recording ? (win.recordingWaiting === "Transcript" ? "call-transcript-20" : "record-20") : "info-20"
        onDismissed: { if (recording) win.recordingWaitingClosed = true; else win.greenRoomAlertClosed = true }
        onEndedChanged: if (ended) win.greenRoomAlertClosed = false
    }
    ConfirmDialog {
        id: requestControlDialog
        title: qsTr("Request control?")
        body: qsTr("You'll control the content the presenter is sharing.")
        confirmText: qsTr("Request")
        onConfirmed: win.screenControl("request", "")
    }
    // Give / take control's alerts (calling alerts 523673 and the
    // viewer's notices).
    property var controlAlert: null
    Connections {
        target: backend
        function onScreenControlNotice(kind, mri, name) {
            const n = name || qsTr("Someone")
            if (kind === "request") win.controlAlert = { kind: "request", text: qsTr("%1 is requesting control.").arg(n), mri: mri }
            else if (kind === "withdrawn" && win.controlAlert && win.controlAlert.kind === "request") win.controlAlert = null
            else if (kind === "hasControl") win.controlAlert = { kind: "has", text: qsTr("%1 has control.").arg(n), mri: mri }
            else if (kind === "controlEnded" && win.controlAlert && win.controlAlert.kind === "has") win.controlAlert = null
            else if (kind === "given") win.controlAlert = { kind: "note", text: qsTr("You have been given screen control") }
            else if (kind === "denied") win.controlAlert = { kind: "note", text: qsTr("Your request for control wasn't accepted.") }
            else if (kind === "takenBack") win.controlAlert = { kind: "note", text: qsTr("The person sharing took control back.") }
            else if (kind === "stopped") win.controlAlert = { kind: "note", text: qsTr("Screen control has been stopped") }
        }
    }
    Timer {
        running: !!win.controlAlert && win.controlAlert.kind === "note"
        interval: 5000
        onTriggered: win.controlAlert = null
    }
    ControlAlert {
        alert: win.controlAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        onGive: { win.screenControl("accept", ""); win.controlAlert = null }
        onDeny: { win.screenControl("deny", ""); win.controlAlert = null }
        onTakeBack: { win.screenControl("takeBack", ""); win.controlAlert = null }
        onDismissed: win.controlAlert = null
    }
    // Teams' post-call "How was the call quality?" (docs/spec/
    // feedback-and-help.md §5), for those who opted in under Settings ▸
    // Privacy: once a call Teams would sample ends (not the test call, not
    // one under 5 s, or 8 s for a meeting, which Teams asks about as "pretty
    // short"), the survey replaces the window until it's answered or
    // dismissed (60 s).
    property var qualitySurvey: null
    readonly property bool barCovered: state === "ended" && (!!qualitySurvey || (testCall && testReport.length > 0))
    property string qualityKind: ""
    property int qualitySeconds: 0
    signal qualityFeedback(string text, string details)
    signal qualitySurveyDone()
    function qualityCallKind() {
        if ((backend.callPeerId || "").indexOf("4:") === 0) return "pstn"
        if (!meeting) return "oneToOne"
        // A chat's group call isn't a meeting (Teams' CQF call types).
        return scheduled || adhocMeeting ? "meeting" : "group"
    }
    Connections {
        target: win
        function onStateChanged() {
            if (win.state === "connected") { win.qualitySurvey = null; return }
            if (win.state !== "ended" || win.testCall || win.qualitySurvey || win.retryReason) return
            const kind = win.qualityCallKind()
            if (win.seconds < (kind === "meeting" ? 8 : 5)) return
            const json = backend.callQualitySurvey(kind, win.canVideo)
            if (!json) return
            win.qualityKind = kind
            win.qualitySeconds = win.seconds
            win.qualitySurvey = JSON.parse(json)
        }
    }
    function qualitySurveyForTest() { return qualitySurveyView }
    CallQualitySurvey {
        id: qualitySurveyView
        anchors.fill: parent
        z: 100
        visible: win.state === "ended" && !!win.qualitySurvey
        survey: win.qualitySurvey || ({})
        onSendFeedback: reasons => {
            const all = (win.qualitySurvey.categories || []).reduce((a, c) => a.concat(c.items), [])
            const labels = reasons.map(r => (all.find(i => i.id === r) || {}).label).filter(l => !!l)
            const text = "The call quality had issues" + (labels.length ? ": " + labels.join("; ") : ".")
            win.qualityFeedback(text, backend.callQualityDetails(win.qualityKind, win.qualitySeconds, JSON.stringify(reasons)))
        }
        onFinished: { win.qualitySurvey = null; win.qualitySurveyDone() }
    }
    // Teams' test call (Settings ▸ Devices ▸ Make a test call): once it
    // ends, its results replace the bar and stage until Close.
    property bool testCall: false
    property var testReport: []
    signal testCallClosed()
    function testReportForTest() { return testReportView }
    TestCallReport {
        id: testReportView
        anchors.fill: parent
        z: 100
        visible: win.testCall && win.state === "ended" && win.testReport.length > 0
        rows: win.testReport
        onClosed: win.testCallClosed()
    }
}
