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
    property string peer
    property string selfName
    property string state       // "calling" | "connecting" | "connected" | "ended"
    property bool muted
    property bool hasAudio: true
    property real connectedAt: 0
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
    // The meeting muted us while we talked: Teams' "You've been muted",
    // for 30 s, until dismissed, or until we're unmuted.
    property int mutedRemotely: 0
    property bool mutedNoticeShown: false
    onMutedRemotelyChanged: if (mutedRemotely > 0) { mutedNoticeShown = true; mutedNoticeTimer.restart() }
    onMutedChanged: if (!muted) mutedNoticeShown = false
    Timer { id: mutedNoticeTimer; interval: 30000; onTriggered: win.mutedNoticeShown = false }
    /// Who presents their screen in the meeting (empty: nobody).
    property string shareId: ""
    readonly property bool presenting: meeting && shareId !== ""
    /// Pop out: the shared content shows in its own window.
    property bool contentPoppedOut: false
    onPresentingChanged: if (!presenting) contentPoppedOut = false
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
    // Pin for me: who you pinned (yours only); Spotlight for everyone: who
    // the meeting spotlights. Either takes the stage as in Speaker view.
    property string pinnedId: ""
    readonly property var spotlighted: roster.filter(p => p.active !== false && !!p.spotlight)
    /// A participant menu action for the meeting (mute, roles, spotlight,
    /// remove).
    signal participantAction(string action, string id, string name, string stateId)
    readonly property var others: roster.filter(p => p.id !== selfId)
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
    readonly property string networkHeading: networkStrength === "Bad" ? "Connection is weak"
        : networkStrength === "Poor" ? "Connection is unstable" : "Connection is good"
    readonly property string networkTip: {
        const p2p = !meeting, cam = cameraOn, inc = !incomingVideoOff
        if (networkStrength === "Bad") {
            if (cam && inc) return p2p ? "One or both participants may have network problems. Try turning off your camera and incoming video to use less bandwidth." : "Try turning off your camera and incoming video to use less bandwidth."
            if (cam) return p2p ? "One or both participants may have network problems. Try turning off your camera to use less bandwidth." : "Try turning off your camera to use less bandwidth."
            if (inc) return p2p ? "One or both participants may have network problems. Try turning off incoming video to use less bandwidth." : "Try turning off incoming video to use less bandwidth."
            return p2p ? "One or both participants may have network problems. This might impact the quality of the call." : "This may impact the quality of your call."
        }
        if (networkStrength === "Poor")
            return wired ? "Check your cable connection or try turning off other apps."
                : p2p ? "One or both participants may have network problems. This might impact the quality of the call." : "This may impact the quality of your call."
        return "Turn on your camera and video anytime."
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
    property bool aiAvailable: false
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
        if (canMuteAll) out.push({ k: "muteAll", t: "Mute all", icon: "mic-off-20" })
        const attendees = others.some(p => p.active !== false && (p.role || "").toLowerCase() === "attendee")
        if (manager && attendees) {
            out.push(attendeeRestrictions & 1
                ? { k: "allowMic", t: "Allow mic for attendees", icon: "mic-20" }
                : { k: "restrictMic", t: "Disable mic for attendees", icon: "mic-prohibited-20" })
            out.push(attendeeRestrictions & 2
                ? { k: "allowCamera", t: "Allow camera for attendees", icon: "video-20" }
                : { k: "restrictCamera", t: "Disable camera for attendees", icon: "video-prohibited-20" })
        }
        if (manager && hands.length > 0) out.push({ k: "lowerHands", t: "Lower all hands", icon: "hand-right-off-20" })
        if (organizer) out.push({ k: "attendance", t: "Download attendance list", icon: "arrow-download-20" })
        if (manager && spotlighted.length > 1) out.push({ k: "stopSpotlights", t: "Stop all spotlights", icon: "spotlight-20" })
        if (organizer) out.push(locked ? { k: "unlock", t: "Unlock the meeting", icon: "lock-closed-20" }
                                       : { k: "lock", t: "Lock the meeting", icon: "lock-closed-20" })
        return out
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
        ? [{ name: selfName || "You", id: "me", you: true, mutedNow: muted || !hasAudio, hand: handRaised,
             role: (roster.find(p => p.id === selfId) || {}).role || "" }]
          .concat(others.map(p => ({ name: p.name, id: p.id, you: false, mutedNow: p.muted, role: p.role, hand: !!p.hand, guest: !!p.guest, suspected: !!p.suspected, spotlight: p.spotlight || "" })))
        : [{ name: selfName || "You", id: "me", you: true, mutedNow: muted || !hasAudio },
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
    readonly property var selfEntry: ({ id: selfId, name: selfName || "You", self: true })
    /// How wide each person's tile is drawn ({mri: px}): the size of video
    /// to ask for (Teams asks to fit its tiles).
    readonly property var videoWidths: {
        const out = {}
        if (!meeting) return out
        const sideSlot = tiles.atTop ? tiles.sideH * 16 / 9 : tiles.sideW
        for (const p of tiles.side) out[p.id] = sideSlot
        if (layout === "speaker" && !presenting && tiles.speaker)
            out[tiles.speaker.id] = Math.min(tiles.mainW, tiles.mainH * 16 / 9)
        if (layout !== "speaker" && !presenting)
            for (const p of tiles.gallery) out[p.id] = galleryTileWidth
        return out
    }
    property real galleryTileWidth: 0
    /// Someone has video on (or it's you with the camera on).
    function hasVideo(p) { return p.self ? cameraOn : !!videoKeys[p.id] }
    /// The others in gallery order (videos first, when asked).
    readonly property var othersOrdered: videosFirst ? others.filter(p => hasVideo(p)).concat(others.filter(p => !hasVideo(p))) : others
    signal deviceSettings()
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
    /// Consulting someone before transferring (their chat is open).
    property var consulting: null
    readonly property bool live: state === "connected"
    function toggleFullScreen() { visibility = visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    /// The open side pane: "", "chat" or "people".
    property string side: ""
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
        if (state === "connected") { connectedAt = Date.now(); seconds = 0 }
        else consulting = null
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
    readonly property var ubarFacts: ({
        p2p: !meeting, pstn: pstnCall, consult: false, scheduled: scheduled,
        organizer: organizer, onHold: held, canPopOut: presenting && !contentPoppedOut, reactions: true
    })
    TextMetrics { id: resumeMetrics; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; text: "Resume" }
    // Each control's slot (button 48 + 4 either side; split buttons 74).
    readonly property var ubarWidths: ({ MicrophoneButton: 74, VideoButton: 74, ResumeButton: Math.ceil(resumeMetrics.advanceWidth) + 20 + 8 + 40 + 8 })
    // The middle slot's room: from 4 past the indicators (shield, timer)
    // to 17 before Leave.
    readonly property real ubarRoom: leaveGroup.x - 17 - (timerText.x + timerText.implicitWidth + 6.67 + 4)
    readonly property var ubar: JSON.parse(backend.ubarArrange(JSON.stringify(ubarFacts), JSON.stringify(ubarWidths), 17,
                                                               ubarRoom - 10) || '{"bar":[],"end":[],"overflowed":[],"more":[],"onHold":[]}')
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
            ChatButton: cChat, RosterButton: cPeople, RaiseHandsButton: cRaise, ReactionButton: cReact,
            ViewModeButton: cView, OrganizerControlButton: cControls, MeetingDetailsButton: cNotes,
            StartBreakoutRoomButton: cRooms, MeetingAppsAddButton: cApps, MoreButton: cMore,
            VideoButton: cCamera, MicrophoneButton: cMic, ShareButton: cShare
        })[name] || null
    }
    // What each control does, from the bar or from More.
    function runControl(name) {
        if (name === "ChatButton") { side = side === "chat" ? "" : "chat"; if (side === "chat") openChat() }
        else if (name === "RosterButton") side = side === "people" ? "" : "people"
        else if (name === "RaiseHandsButton") toggleHand()
        else if (name === "ReactionButton") { reactMenu.parent = barItem(name); reactMenu.open() }
        else if (name === "ViewModeButton") { viewMenu.parent = barItem(name); viewMenu.open() }
        else if (name === "OrganizerControlButton") Qt.openUrlExternally(optionsUrl)
        else if (name === "MeetingDetailsButton") Qt.openUrlExternally(chatUrl)
        else if (name === "MeetingAppsAddButton") { appsMenu.parent = barItem(name); appsMenu.open() }
        else if (name === "MoreButton") { moreMenu.parent = barItem(name); moreMenu.open() }
        else if (name === "VideoButton") toggleCamera()
        else if (name === "MicrophoneButton") toggleMute()
        else if (name === "ShareButton") toggleShare()
        else if (name === "PopoutContentButton") contentPoppedOut = true
        else if (name === "CallTransferButtonV2" || name === "CallConsultativeTransferButtonV2") {
            picker.mode = name === "CallTransferButtonV2" ? "transfer" : "consult"
            picker.parent = barItem(name); picker.open()
        }
        else if (name === "DialpadButton") { if (dialPad.visible) dialPad.close(); else { dialPad.parent = barItem(name); dialPad.open() } }
        else if (name === "HoldButton" || name === "ResumeButton") toggleHold()
        else if (name === "CameraEffectsButton") deviceSettings()
        else if (name === "AudioSettingsButton") side = side === "audio" ? "" : "audio"
        else if (name === "MeetingInfoButton") { side = side === "info" ? "" : "info"; if (side === "info") loadMeetingInfo() }
    }
    function controlEnabled(name) {
        if (!holdOk(name)) return false
        if (["RaiseHandsButton", "ReactionButton", "CallTransferButtonV2", "CallConsultativeTransferButtonV2"].indexOf(name) >= 0) return live
        if (name === "OrganizerControlButton") return optionsUrl.length > 0
        if (name === "MeetingDetailsButton") return chatUrl.length > 0
        if (name === "StartBreakoutRoomButton") return false
        if (name === "VideoButton") return canVideo
        if (name === "MicrophoneButton") return hasAudio
        if (name === "ShareButton") return canShare || sharing
        if (name === "DialpadButton") return live && canDtmf
        if (name === "HoldButton") return live && hasAudio
        return true
    }
    // An overflowed control in More, as Teams names it there (the menu
    // uses the control's title, else its label).
    function overflowItem(name) {
        const m = {
            ChatButton: { label: "Chat", icon: "call-chat", checked: side === "chat" },
            RosterButton: { label: side === "people" ? "Hide people" : "People", icon: "call-people", checked: side === "people" },
            RaiseHandsButton: { label: handRaised ? "Lower hand" : "Raise hand", icon: "call-raise" },
            ReactionButton: { label: "Send a reaction", icon: "call-react" },
            ViewModeButton: { label: "View", icon: "call-view", chevron: true },
            OrganizerControlButton: { label: "Controls", icon: "call-controls", chevron: true },
            MeetingDetailsButton: { label: "Open notes", icon: "call-notes" },
            StartBreakoutRoomButton: { label: "Breakout rooms", icon: "call-rooms" },
            MeetingAppsAddButton: { label: "Get more apps and agents", icon: "call-apps" },
            PopoutContentButton: { label: "Pop out", icon: "call-popout" },
            CallTransferButtonV2: { label: "Transfer", icon: "call-transfer" },
            CallConsultativeTransferButtonV2: { label: "Consult then transfer", icon: "consult" },
            DialpadButton: { label: "Dial pad", icon: "dialpad" },
            HoldButton: { label: "Hold", icon: "pause" },
            ResumeButton: { label: "Resume", icon: "play-20" }
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
        if (n === "MeetingInfoButton") return { label: "Meeting info", icon: "info-20" }
        if (n === "CameraEffectsButton") return { label: "Video effects and settings", icon: "video-background-effect-20" }
        if (n === "AudioSettingsButton") return { label: "Audio settings", icon: "speaker-settings-20" }
        if (n === "RecordingMenuControl") return { label: "Record and transcribe", icon: "record-20" }
        if (n === "RecordingButton") return recording
            ? { label: "Stop recording", icon: "record-stop-20", tip: "Stop recording and transcription" }
            : { label: "Start recording", icon: "record-20", tip: transcribing ? "Start recording only" : "Start recording and transcription" }
        if (n === "TranscriptButton") return transcribing
            ? { label: "Stop transcription", icon: "call-transcript-stop-20" }
            : { label: "Start transcription", icon: "call-transcript-20" }
        if (n === "LanguageSpeechMenuControl") return { label: "Language and speech", icon: "local-language-20" }
        if (n === "ClosedCaptionsButton") return {
            label: captionsOn ? "Hide live captions" : "Show live captions",
            icon: "closed-caption-20", keys: "Alt+Shift+C", endCheck: captionsOn }
        // Once a transcript has run in the meeting: show or hide its pane.
        if (n === "TranscriptPanelButton") return transcriptStarted
            ? { label: side === "transcript" ? "Hide transcript" : "Show transcript",
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
            if (mode !== "recording") win.openTranscriptWhenStarted = true
            win.recorderCommand(mode === "transcription" ? "startTranscription" : "startRecording", language, audioOnly)
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
    signal updateAccessibility(string patch)
    signal saveCaptionStyles(var styles)
    readonly property bool captionsAtTop: captionStyles.captionsPosition === "Top"
    readonly property var spokenLanguages: recordStart.languages.map(l => ({ code: l[0], name: l[1] }))
    function languageName(code) {
        const l = recordStart.languages.find(x => x[0] === code)
        return l ? l[1] : "English (US)"
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
    // A transcript has run in this meeting (Teams' hasBeenStarted: More
    // then offers Show transcript).
    property bool transcriptRan: false
    readonly property bool transcriptStarted: transcriptRan || transcribing || transcript.length > 0
    onTranscribingChanged: {
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
        title: "Stop transcription?"; body: ""; confirmText: "Stop"
        onConfirmed: win.recorderCommand("stopTranscription", "", false)
    }
    ConfirmDialog {
        id: stopRecordingAsk
        title: "Stop recording and transcription?"; body: ""; confirmText: "Stop"
        onConfirmed: win.recorderCommand("stopRecording", "", false)
    }
    function recordMenuForTest() {
        moreMenu.parent = barItem("MoreButton") || moreMenu.parent
        moreMenu.open()
        const i = barMoreItems.findIndex(it => it.name === "RecordingMenuControl")
        if (i >= 0) moreMenu.openSubmenuForTest(i)
    }
    function closeMoreForTest() { moreMenu.close() }
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
        if (name === "ClosedCaptionsButton") setCaptions(!captionsOn)
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
        width: parent.width; height: 60
        color: theme.surface
        // Meetings: Teams' shield (meeting info) beside the timer: a 30 x 32
        // indicator at x 8 with its 20 px glyph, then the duration in
        // 14 px #424242 with 6.7 px of padding.
        FluentIcon {
            visible: win.meeting
            x: 13; y: 20
            name: "call-shield"; size: 20; color: theme.textStrong
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
            visible: win.meeting && win.recordingState !== ""
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
            visible: win.meeting && win.aiIndicator
            x: recordingIndicator.visible ? 68 : 38; y: 14; width: 37.33; height: 32
            readonly property bool active: win.aiOn && win.aiAvailable
            readonly property string tip: !win.aiAvailable ? "AI isn't available in this meeting"
                : active ? "AI is on in the meeting" : "AI is turned off and doesn't have access to the meeting"
            Rectangle {
                x: 4.67; y: 6; width: 28; height: 20; radius: 10
                color: aiIndicator.active ? (aiHover.hovered ? theme.brandHover : theme.brandFill) : theme.surface
                FluentIcon {
                    x: 4; y: 0
                    name: aiIndicator.active ? "sparkle-20-filled" : "sparkle-off-20-regular"; size: 20
                    color: aiIndicator.active ? theme.textOnBrand
                        : !win.aiAvailable ? theme.disabled
                        : aiHover.hovered || aiPopover.visible ? theme.brand : theme.text
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
        Text {
            id: timerText
            // After the shield (and the AI indicator), 6.67 into the
            // duration's slot.
            x: !win.meeting ? 16 : 38 + (recordingIndicator.visible ? 30 : 0) + (aiIndicator.visible ? 37.33 : 0) + 6.67
            anchors.verticalCenter: parent.verticalCenter
            text: win.state === "connected" ? win.clock(win.seconds) : "--:--"
            color: theme.textStrong
            font.family: theme.font; font.pixelSize: 14
        }
        // The controls, as Teams' layout engine places them
        // (teams_cli::calling::ubar over Teams' layout config): which show,
        // their order and dividers come from the config and the call; the
        // slot is right-aligned 4 px before the end slot and whatever
        // doesn't fit (Fluent's overflow, keeping 10 px free) moves to the
        // top of More.
        Row {
            id: middleSlot
            anchors { right: leaveGroup.left; rightMargin: 17; top: parent.top }
            spacing: 0
            Repeater {
                model: win.ubar.bar
                Loader {
                    required property string modelData
                    sourceComponent: modelData === "|" ? barDivider : win.barComponent(modelData)
                    onLoaded: if (modelData !== "|") win.registerBarItem(modelData, item)
                }
            }
        }
        // Leave: 13 px in from the middle group's end, 14 from the window edge.
        Row {
            id: leaveGroup
            anchors { right: parent.right; rightMargin: 14; top: parent.top }
            BarButton {
                id: leaveButton
                icon: "call-leave-filled"; label: "Leave"; strong: true
                iconColor: "#B10E1C"
                tip: "Leave"; shortcut: "Ctrl+Shift+H"
                // Teams splits Leave only when its menu has more than Leave.
                split: win.meeting && win.leaveItems.length > 1
                chevronLabel: "More options"
                chevronChecked: leaveMenu.visible
                onClicked: win.leave()
                onChevronClicked: leaveMenu.open()
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // Live captions: a strip 4 in from the sides and bottom (or under the
    // bar, "At top"), the stage above (or below) it.
    CaptionsWindow {
        id: captionsWindow
        visible: win.captionsOn && win.state === "connected"
        x: 4; width: (sidePane.visible ? sidePane.x : win.contentItem.width) - 8
        height: implicitHeight
        y: win.captionsAtTop ? bar.y + bar.height + 4 : win.contentItem.height - 4 - height
        captions: win.captions
        roster: win.people
        meId: backend.userMri
        meName: backend.userName
        filterProfanity: win.accessibility.profanityFilterEnabled === true
        languageName: win.languageName(win.captionsLanguage)
        styles: win.captionStyles
        windowHeight: win.height
        areaHeight: win.contentItem.height - bar.y - bar.height
        onClosed: win.setCaptions(false)
        onSettingsRequested: anchor => win.openCaptionSettings(anchor)
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
    MenuPopup {
        id: captionsOverflow
        items: [{ label: "Open caption settings", icon: "settings-20", chevron: true }]
        onPicked: i => win.showCaptionSettings(captionsOverflow.parent)
    }

    // Stage
    Rectangle {
        id: stage
        anchors {
            top: captionsWindow.visible && win.captionsAtTop ? captionsWindow.bottom : bar.bottom
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
            GradientStop { position: 0.0; color: "#F2F1F8" }
            GradientStop { position: 1.0; color: "#EEF6F6" }
        }
        // Meetings: alone, your picture and "Waiting for others to join…";
        // otherwise a tile for each other person.
        Column {
            visible: win.meeting && win.others.length === 0
            anchors.centerIn: parent
            spacing: 24
            Avatar { size: 154; name: win.selfName || "You"; photoId: "me"; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.state === "connected" ? "Waiting for others to join…" : win.state === "ended" ? "You left the meeting" : "Connecting…"
                color: theme.text
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            }
        }
        // Teams' stage layouts. The side gallery (Speaker view's others, or
        // you when you're out of the gallery) is a column of 16:9 slots on
        // the right (160 px wide, up to all but 161) or, with "Show gallery
        // at top", a row of them on top (90 px tall, up to 485); a 5 px
        // divider with a 1 px #D1D1D1 line resizes it.
        Item {
            id: tiles
            visible: win.meeting && win.others.length > 0 && (win.layout !== "focus" || win.presenting)
            anchors { fill: parent; margins: 2.67 }
            // Spotlight (for everyone) and Pin for me put that person on
            // the stage, everyone else in the side gallery.
            readonly property var featured: {
                const sp = win.spotlighted.length ? win.spotlighted[0] : null
                if (sp) return sp.id === win.selfId ? win.selfEntry : sp
                return win.others.find(p => p.id === win.pinnedId) || null
            }
            readonly property bool speakerView: win.layout === "speaker" || !!featured
            readonly property var speaker: {
                if (featured) return featured
                const pool = win.speakerMeInGallery && !win.hideMe ? win.others.concat([win.selfEntry]) : win.others
                return pool.find(p => p.id === win.speakerId) || win.othersOrdered[0]
            }
            // Presenting: the content on stage, everyone in the side gallery
            // (no one in Focus on content).
            // (Popped out, the content has its own window and the stage
            // goes back to people.)
            readonly property bool content: win.presenting && !win.contentPoppedOut
            readonly property var side: content
                ? (win.layout === "focus" ? [] : win.othersOrdered.concat(win.hideMe ? [] : [win.selfEntry]))
                : speakerView
                ? win.othersOrdered.filter(p => p !== speaker).concat(win.hideMe || speaker.self ? [] : [win.selfEntry])
                : (win.hideMe || win.meInGallery ? [] : [win.selfEntry])
            // Everyone in the gallery, in pages of the gallery size.
            readonly property var galleryAll: (win.hideMe || !win.meInGallery ? [] : [win.selfEntry]).concat(win.othersOrdered)
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
                visible: tiles.speakerView && !tiles.content
                call: win
                person: tiles.speaker || ({})
                width: Math.min(tiles.mainW, tiles.mainH * 16 / 9); height: width * 9 / 16
                x: tiles.mainX + (tiles.mainW - width) / 2; y: tiles.mainY + (tiles.mainH - height) / 2
            }
            // Gallery.
            GalleryGrid {
                id: galleryGrid
                visible: !tiles.speakerView && !tiles.content
                x: tiles.mainX; y: tiles.mainY; width: tiles.mainW; height: tiles.mainH - tiles.pagerH
                onTileWChanged: win.galleryTileWidth = tileW
                call: win
                people: tiles.gallery
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
                            { icon: "chevron-left-20", tip: "Previous page", step: -1 },
                            { counter: true },
                            { icon: "chevron-right-20", tip: "Next page", step: 1 }
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
                                color: "#252423"
                                font.family: theme.font; font.pixelSize: 14
                            }
                            Rectangle {
                                visible: !pagerItem.modelData.counter
                                y: 2; width: 32; height: 32; radius: 4
                                color: pagerHover.hovered ? "#F5F5F5" : "transparent"
                                FluentIcon {
                                    anchors.centerIn: parent
                                    name: pagerItem.modelData.icon || ""
                                    color: pagerItem.enabledStep ? "#242424" : "#BDBDBD"
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
                                Accessible.name: (pagerItem.modelData.step < 0 ? "Navigate to previous video page. Currently " : "Navigate to next video page. Currently ")
                                    + (tiles.page + 1) + "/" + tiles.pageCount
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
                VideoFrame {
                    id: meetingShare
                    source: "share"
                    fit: true
                    letterbox: false
                    anchors.fill: parent
                    Timer {
                        interval: 33; repeat: true
                        running: win.visible && contentTile.visible
                        onTriggered: meetingShare.refresh()
                    }
                }
                Rectangle {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 8 }
                    height: 24; radius: 4
                    width: contentName.implicitWidth + 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { id: contentName; x: 6; anchors.verticalCenter: parent.verticalCenter; text: win.presenterName; color: "white"; font.family: theme.font; font.pixelSize: 14 }
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: win.presenterName + " is presenting"
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
                    color: "#D1D1D1"
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
                Accessible.name: tiles.atTop ? "Resize top gallery" : "Resize side gallery"
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
            color: "#CC000000"
            Text { id: shareText; anchors.centerIn: parent; text: win.peer + " is presenting"; color: "white"; font.family: theme.font; font.pixelSize: theme.small }
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
                Text { anchors.verticalCenter: parent.verticalCenter; text: "You're presenting"; color: theme.text; font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold }
            }
        }
        Column {
            visible: !win.meeting && !remoteVideo.visible && !shareVideo.visible
            anchors.centerIn: parent
            spacing: 24
            Avatar { size: 144; name: win.peer; photoId: backend.callPeerId; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.state === "calling" ? "Calling…"
                    : win.state === "connecting" ? "Connecting…"
                    : win.state === "ended" ? "Call ended"
                    : win.held || win.heldByPeer ? ""
                    : !win.hasAudio ? "Connected without audio" : ""
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
                    text: win.held ? "On hold " + win.clock(win.heldSeconds) : "On hold"
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
            color: "#99000000"
            Text {
                id: nameText
                anchors.centerIn: parent
                text: win.peer
                color: "white"
                font.family: theme.font; font.pixelSize: theme.small
            }
        }
        // Your own tile, bottom right, in a 1:1 call (meetings have you as
        // a tile)
        Rectangle {
            visible: !win.meeting
            z: 2
            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
            width: 240; height: 134; radius: 6
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#F6EEF2" }
                GradientStop { position: 1.0; color: "#EEF0F8" }
            }
            border.color: theme.dividerSoft
            Avatar { visible: !selfVideo.visible; anchors.centerIn: parent; size: 64; name: win.selfName || "You"; photoId: "me" }
            ReactionShown { z: 3; mri: win.selfId }
            // Your camera, mirrored as Teams shows your own video.
            VideoFrame {
                id: selfVideo
                source: "self"
                anchors.fill: parent; anchors.margins: 1
                visible: win.cameraOn && hasFrame
                transform: Scale { origin.x: selfVideo.width / 2; xScale: -1 }
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
                color: "#99000000"
                FluentIcon { anchors.centerIn: parent; name: "mic-off-24"; size: 16; color: "white" }
            }
        }
    }

    // Side pane: the chat with them, or the people in the call.
    property alias chatPane: chatPane
    Rectangle {
        id: sidePane
        visible: win.side !== ""
        // Teams' calling-right-side-panel: 360 wide, flush with the window.
        anchors { top: bar.bottom; right: parent.right; bottom: parent.bottom }
        width: 360
        color: win.side === "people" || win.side === "info" || win.side === "audio" || win.side === "transcript" || win.side === "captionStyles" ? theme.pane : theme.surface
        clip: true
        Conversation {
            id: chatPane
            visible: win.side === "chat"
            anchors.fill: parent; anchors.margins: 1
            pane: true
            onClosePane: win.side = ""
        }
        AudioSettingsPane {
            id: audioSettingsPane
            visible: win.side === "audio"
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
        CaptionStylesPane {
            id: captionStylesPane
            visible: win.side === "captionStyles"
            anchors.fill: parent
            styles: win.captionStyles
            onClosed: win.side = ""
            onChanged: s => win.saveCaptionStyles(s)
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
            meeting: win.meeting
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
            pinnedId: win.pinnedId
            onParticipantAction: (action, id, name, stateId) => {
                if (action === "pin") win.pinnedId = id
                else if (action === "unpin") win.pinnedId = ""
                // Teams asks "Change role?" first.
                else if (action === "attendee" || action === "presenter") roleAsk.ask(action, id, name)
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
    onRoomModeChanged: roomNoticeDismissed = false
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
                title: "Shared content | " + win.peer + " | OST"
                width: 1280; height: 680
                visible: true
                color: "#F5F5F5"
                onClosing: win.contentPoppedOut = false
                VideoFrame {
                    id: poppedShare
                    x: 2.67; y: 2.67; width: parent.width - 5.33; height: parent.height - 5.33
                    source: "share"
                    fit: true
                    letterbox: false
                    Timer { interval: 33; repeat: true; running: true; onTriggered: poppedShare.refresh() }
                }
                Rectangle {
                    x: 10.67; anchors.bottom: parent.bottom; anchors.bottomMargin: 10.67
                    height: 24; radius: 4
                    width: poppedName.implicitWidth + 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { id: poppedName; x: 6; anchors.verticalCenter: parent.verticalCenter; text: win.presenterName; color: "white"; font.family: theme.font; font.pixelSize: 14 }
                }
            }
        }
    }
    function closeMenusForTest() { viewMenu.close(); moreMenu.close(); videoFlyout.close(); audioFlyout.close(); peoplePane.closeMenusForTest() }
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
        visible: win.roomMode && !win.roomNoticeDismissed
        x: stage.x + (stage.width - width) / 2
        y: bar.height + 10.7
        z: 5
        onDismissed: win.roomNoticeDismissed = true
    }
    MutedNotice {
        visible: win.mutedNoticeShown
        x: stage.x + (stage.width - width) / 2
        y: bar.height + 10.7
        z: 5
        onDismissed: win.mutedNoticeShown = false
        onUnmute: { win.mutedNoticeShown = false; win.toggleMute() }
    }
    // Teams' MeetingLocked / MeetingUnlocked alerts (ufd_MeetingLocked):
    // the notice card with the filled lock, for 10 s.
    property bool lockNoticeShown: false
    onLockNoticesChanged: if (lockNotices > 0) { lockNoticeShown = true; lockNoticeTimer.restart() }
    Timer { id: lockNoticeTimer; interval: 10000; onTriggered: win.lockNoticeShown = false }
    MutedNotice {
        visible: win.lockNoticeShown
        x: stage.x + (stage.width - width) / 2
        y: bar.height + 10.7
        z: 5
        icon: "lock-closed-20-filled"
        title: win.locked ? "This meeting is locked." : "This meeting is unlocked."
        text: win.locked ? "No one else can join." : "People can join."
        action: ""
        onDismissed: win.lockNoticeShown = false
    }
    MutedNotice {
        visible: win.recorderFailure.length > 0
        x: stage.x + (stage.width - width) / 2
        y: bar.height + 10.7
        z: 5
        icon: "alert-warning-16-filled"
        title: win.recorderFailure
        text: ""
        action: ""
        onDismissed: win.recorderFailure = ""
    }
    LobbyToast {
        id: lobbyToast
        x: stage.x + (stage.width - width) / 2
        y: bar.height + 10.7
        z: 5
        lobby: win.lobby
        rosterOpen: win.side === "people"
        onAdmit: (id, name) => win.admitLobby(id, name, false)
        onDeny: (id, name) => win.denyLobby(id, name)
        onViewLobby: win.side = "people"
    }
    // Leave's options (hangup-button-more-options-menu, measured): a
    // surface right-aligned to the chevron, 6 below it, padding 16, a 0.67
    // edge; 32 px items 2 apart, as wide as the longest label + 20 (at
    // least 138), 14 px #424242 at 12. Leave; "Leave on all my devices"
    // when more than one of your devices is in the call; End meeting for
    // the organizer, after Teams' confirmation.
    readonly property int myDevices: { const me = roster.find(p => p.id === selfId); return me ? (me.devices || 0) : 0 }
    readonly property var leaveItems: [{ k: "leave", t: "Leave" }]
        .concat(myDevices > 1 ? [{ k: "all", t: "Leave on all my devices" }] : [])
        .concat(organizer ? [{ k: "end", t: "End meeting" }] : [])
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
                    required property var modelData
                    width: leaveMenu.leaveItemW; height: 32; radius: 4
                    color: lmHover.hovered ? theme.menuHover : theme.surface
                    Text {
                        // Teams: 6 px padding, then the label's own 4 + 2 inset.
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.t
                        font.family: theme.font; font.pixelSize: 14
                        color: lmHover.hovered ? theme.text : theme.textStrong
                    }
                    HoverHandler { id: lmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            leaveMenu.close()
                            if (parent.modelData.k === "end") endAsk.open()
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
    // Teams' compact view while the meeting window is minimised.
    CompactCallWindow {
        id: compactView
        call: win
        visible: win.meeting && win.state === "connected" && win.visibility === Window.Minimized
        onRestore: { win.showNormal(); win.raise(); win.requestActivate() }
    }
    function minimizeForTest() { win.showMinimized() }
    function compactViewForTest() { return compactView }
    function participantMenuForTest(id) { const p = win.people.find(x => x.id === id); if (p) peoplePane.participantMenuForTest(p) }
    // Teams' Mute all confirmation ("All" scope).
    ConfirmDialog {
        id: muteAllAsk
        title: "Mute everyone?"
        body: "This will mute everyone in the meeting but you."
        confirmText: "Mute"
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
        title: modality === 1 ? (disabling ? "Disable mic for attendees?" : "Allow mic for attendees?")
                              : (disabling ? "Disable camera for attendees?" : "Allow camera for attendees?")
        body: modality === 1
            ? (disabling ? "Attendees won’t be able to unmute themselves. The organizer and presenters can let people unmute as needed."
                         : "Everyone in the meeting will be able to unmute themselves.")
            : (disabling ? "Attendees won’t be able to share video. The organizer and presenters can let people turn on their cameras as needed."
                         : "Everyone in the meeting will be able to share video.")
        confirmText: modality === 1 ? (disabling ? "Disable mics" : "Allow mics")
                                    : (disabling ? "Disable cameras" : "Allow cameras")
        onConfirmed: win.setAttendeeRestrictions((win.attendeeRestrictions & 3) ^ modality)
    }
    // Teams' "Lower all hands?" (confirm-attendee-lower-all-raised-hand).
    ConfirmDialog {
        id: lowerHandsAsk
        property int count: 0
        title: "Lower all hands?"
        body: count === 1 ? "You'll lower 1 raised hand." : "You'll lower " + count + " raised hands."
        confirmText: "Lower all hands"
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
        title: unlocking ? "Couldn't unlock the meeting" : "Couldn't lock the meeting"
        body: unlocking ? "An error occurred. Try unlocking it again." : "An error occurred. Try locking it again."
        confirmText: "Try again"
        onConfirmed: win.meetingAction(unlocking ? "unlock" : "lock")
    }
    function meetingActionFailed(action) {
        if (action === "lock" || action === "unlock") { lockRetry.unlocking = action === "unlock"; lockRetry.open() }
        if (action === "startTranscription" || action === "startRecording") openTranscriptWhenStarted = false
        if (action === "startRecording") { recorderFailure = "Couldn't start recording"; recorderFailureTimer.restart() }
        else if (action.indexOf("Transcription") >= 0 || action === "stopRecording") {
            recorderFailure = "Something went wrong with transcription. Please try again later."; recorderFailureTimer.restart()
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
        onToggleMute: win.toggleMute()
        // Teams opens its Audio settings pane (TASK-0062); OST's device settings for now.
        onMoreAudioSettings: win.side = "audio"
        x: parent ? parent.width - width : 0
        y: 60
        maxHeight: win.height - 60 - 5
    }
    function openAudioOptions(button) { audioFlyout.parent = button; audioFlyout.open() }
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
    NetworkPopover {
        id: networkPopover
        call: win
        onLeft: networkPopoverClose.restart()
    }
    VideoFlyout {
        id: videoFlyout
        cameraOn: win.cameraOn
        x: parent ? parent.width - width : 0
        y: 60
        // Teams opens its Video effects and settings pane (TASK-0062).
        onMoreVideoSettings: win.deviceSettings()
    }
    function videoOptionsForTest() { videoFlyout.parent = barItem("VideoButton"); videoFlyout.open() }

    // React (reaction-menu-button-toolbox, measured on winpc): a 249.3 x
    // 73.3 surface under the React button, padding 16, five 32 px buttons
    // 12 apart holding Teams' 24 px reaction pictures.
    Popup {
        id: reactMenu
        x: 4; y: 59.3
        width: 249.3; height: 73.3
        padding: 0
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Row {
            x: 20.7; y: 20.7; spacing: 12
            Repeater {
                model: [{ n: "like", t: "Like" }, { n: "heart", t: "Love" }, { n: "applause", t: "Applause" }, { n: "laugh", t: "Laugh" }, { n: "surprised", t: "Surprised" }]
                Rectangle {
                    required property var modelData
                    width: 32; height: 32; radius: 4
                    color: rmHover.hovered ? theme.menuHover : "transparent"
                    Image { x: 4; y: 4; width: 24; height: 24; smooth: true; source: win.reactionUrl(parent.modelData.n, false) }
                    HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { reactMenu.close(); win.sendReaction(parent.modelData.n) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.t
                }
            }
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
            { label: win.galleryAtTop ? "Show gallery on right" : "Show gallery at top", checked: false },
            { label: "Turn off other videos", checked: win.incomingVideoOff },
            { label: "Hide me", checked: win.hideMe },
            win.layout === "speaker"
                ? { label: win.speakerMeInGallery ? "Remove me from gallery" : "Include me in gallery", checked: false }
                : { label: win.meInGallery ? "Remove me from gallery" : "Include me in gallery", checked: false },
            { label: "Optimize for room", checked: win.roomMode },
            { label: "Full screen", keys: "F11", checked: win.visibility === Window.FullScreen }]
        items: win.meeting
            ? [{ label: "Gallery", icon: "view-gallery-20", checked: win.layout === "gallery" },
               { label: "Speaker", icon: "view-speaker-20", checked: win.layout === "speaker" },
               { label: "Focus on content", icon: "view-focus-20", checked: win.layout === "focus", enabled: win.shareShown || win.layout === "focus" },
               { separator: true }]
              .concat(win.layout === "gallery" ? [
               { label: "Gallery size", icon: "view-gallery-size-20", submenu: [4, 9, 16, 49].map(n => ({ label: n + " people", checked: win.gallerySize === n })) },
               { label: "Show videos first", icon: "view-videos-first-20", checked: win.videosFirst }] : [])
              .concat([{ label: "More options", submenu: moreOptions }])
            : [{ label: win.visibility === Window.FullScreen ? "Exit full screen" : "Full screen", icon: "full-screen-maximize-20" },
               { label: win.incomingVideoOff ? "Turn on incoming video" : "Turn off incoming video", icon: "video-off-20" }]
        onPicked: i => {
            const l = items[i].label
            if (l === "Gallery") win.layout = "gallery"
            else if (l === "Speaker") win.layout = "speaker"
            else if (l === "Focus on content") win.layout = win.layout === "focus" ? "gallery" : "focus"
            else if (l === "Show videos first") win.videosFirst = !win.videosFirst
            else if (l.indexOf("ull screen") >= 0) win.toggleFullScreen()
            else win.incomingVideoOff = !win.incomingVideoOff
        }
        onSubPicked: (i, j) => {
            const it = items[i]
            if (it.label === "Gallery size") { win.gallerySize = [4, 9, 16, 49][j]; return }
            const l = it.submenu[j].label
            if (l.startsWith("Show gallery")) win.galleryAtTop = !win.galleryAtTop
            else if (l === "Turn off other videos") win.incomingVideoOff = !win.incomingVideoOff
            else if (l === "Hide me") win.hideMe = !win.hideMe
            else if (l.endsWith("me from gallery") || l.endsWith("me in gallery")) {
                if (win.layout === "speaker") win.speakerMeInGallery = !win.speakerMeInGallery
                else win.meInGallery = !win.meInGallery
            }
            else if (l === "Optimize for room") win.roomMode = !win.roomMode
            else if (l === "Full screen") win.toggleFullScreen()
        }
    }
    Shortcut { sequence: "F11"; enabled: win.meeting; onActivated: win.toggleFullScreen() }
    // Teams' call shortcuts (§13). Mute, camera and leave work app-wide
    // (Main.qml); the rest in the call window.
    readonly property bool inCall: state === "connected" || state === "calling" || state === "connecting"
    Shortcut { sequence: "Ctrl+Shift+K"; enabled: win.live && win.ubar.bar.concat(win.ubar.overflowed).indexOf("RaiseHandsButton") >= 0; onActivated: win.toggleHand() }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: win.live && (win.canShare || win.sharing); onActivated: win.toggleShare() }
    // Language and speech ▸ Show / Hide live captions.
    Shortcut { sequence: "Alt+Shift+C"; enabled: win.live && win.ubar.more.some(sec => sec.items.some(i => i.name === "LanguageSpeechMenuControl")); onActivated: win.setCaptions(!win.captionsOn) }
    // Admit the person the lobby notification shows.
    Shortcut {
        sequence: "Ctrl+Shift+Y"
        enabled: lobbyToast.visible && win.lobby.length === 1 && !win.lobby[0].suspected
        onActivated: win.admitLobby(win.lobby[0].id, win.lobby[0].name, false)
    }
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
    }
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
                        required property var modelData
                        width: 68; height: 48; radius: theme.radius
                        color: kh.pressed ? theme.selected : kh2.hovered ? theme.rowHover : "transparent"
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; font.family: theme.font; font.pixelSize: 20; color: theme.text }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary; visible: text.length > 0 }
                        }
                        HoverHandler { id: kh2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: kh; onTapped: dialPad.press(modelData[0]) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Dial " + modelData[0]
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
                text: picker.mode === "transfer" ? "Transfer to" : "Consult with"
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
            Rectangle {
                width: 296; height: 32; radius: theme.radius
                color: theme.input; border.color: who.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: who
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !who.text; text: "Type a name"; color: theme.textTertiary; font: who.font }
                    onTextChanged: win.searchPeople(text)
                    Keys.onEscapePressed: picker.close()
                    Accessible.name: picker.mode === "transfer" ? "Transfer to" : "Consult with"
                }
            }
            Repeater {
                model: who.text.trim().length >= 2 ? win.directory.slice(0, 6) : []
                Rectangle {
                    required property var modelData
                    width: 296; height: 44; radius: theme.radius
                    color: ph.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 28; name: modelData.name; photoId: "8:orgid:" + modelData.id }
                    Column {
                        x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                        Text { width: parent.width; elide: Text.ElideRight; visible: !!modelData.job_title || !!modelData.mail; text: modelData.job_title || modelData.mail; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                    }
                    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            picker.close()
                            if (picker.mode === "transfer") win.transfer(modelData.id, modelData.name)
                            else { win.consulting = { id: modelData.id, name: modelData.name }; win.consult(modelData.id, modelData.name) }
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: (picker.mode === "transfer" ? "Transfer to " : "Consult with ") + modelData.name
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
            Text { anchors.verticalCenter: parent.verticalCenter; text: win.consulting ? "Consulting " + win.consulting.name : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Rectangle {
                width: 84; height: 28; radius: theme.radius; color: theme.brandFill
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "Transfer"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                TapHandler { onTapped: { const c = win.consulting; win.consulting = null; win.transfer(c.id, c.name) } }
                Accessible.role: Accessible.Button
                Accessible.name: "Transfer to " + (win.consulting ? win.consulting.name : "")
            }
            Rectangle {
                width: 84; height: 28; radius: theme.radius; color: theme.input; border.color: theme.stroke
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "Resume"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                TapHandler { onTapped: { win.consulting = null; if (win.held) win.toggleHold() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Stop consulting and resume"
            }
        }
    }

    function consultForTest(oid, name) { consulting = { id: oid, name: name }; consult(oid, name) }
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
    Component { id: barDivider; Item { width: 17; height: 60; Rectangle { x: 8; y: 13.5; width: 0.67; height: 33; color: theme.stroke } } }
    Component { id: cPopout; BarButton { icon: "call-popout"; label: "Pop out"; tip: "Pop out"; onClicked: win.runControl("PopoutContentButton") } }
    Component { id: cTransfer; BarButton { icon: "call-transfer"; label: "Transfer"; tip: "Transfer"; enabled: win.controlEnabled("CallTransferButtonV2"); checked: picker.visible && picker.mode === "transfer"; onClicked: win.runControl("CallTransferButtonV2") } }
    Component { id: cConsult; BarButton { icon: "consult"; label: "Consult"; tip: "Consult then transfer"; enabled: win.controlEnabled("CallConsultativeTransferButtonV2"); checked: picker.visible && picker.mode === "consult"; onClicked: win.runControl("CallConsultativeTransferButtonV2") } }
    Component { id: cDialpad; BarButton { icon: "dialpad"; label: "Dial pad"; tip: "Dial pad"; enabled: win.controlEnabled("DialpadButton"); checked: dialPad.visible; onClicked: win.runControl("DialpadButton") } }
    Component { id: cHold; BarButton { icon: "pause"; label: "Hold"; tip: "Hold"; enabled: win.controlEnabled("HoldButton"); onClicked: win.runControl("HoldButton") } }
    // Held: Teams' "Resume" text button in the contextual group.
    Component {
        id: cResume
        Item {
            width: win.ubarWidths.ResumeButton; height: 60
            Rectangle {
                x: 4; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 8; height: 48; radius: theme.radius
                color: rph.hovered ? theme.pane : theme.rowHover
                border.color: theme.stroke
                Row {
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "play-20"; size: 20; color: theme.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Resume"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                }
                HoverHandler { id: rph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.runControl("ResumeButton") }
                Accessible.role: Accessible.Button
                Accessible.name: "Resume"
            }
        }
    }
    Component { id: cChat; BarButton { icon: "call-chat"; label: "Chat"; checked: win.side === "chat"; tip: win.side === "chat" ? "Hide conversation" : "Show conversation"; enabled: win.controlEnabled("ChatButton"); onClicked: win.runControl("ChatButton") } }
    Component {
        id: cPeople
        BarButton {
            icon: "call-people"; label: "People"; checked: win.side === "people"
            readonly property int count: win.roster.length
            tip: (count === 0 ? "" : count === 1 ? "1 participant. " : count + " participants. ") + (win.side === "people" ? "Hide participants" : "Show participants")
            // Teams: people waiting in the lobby, or raised hands, as a
            // red count; else how many are here (meetings).
            badge: !win.meeting ? 0 : win.lobby.length > 0 ? win.lobby.length : win.hands.length > 0 ? win.hands.length : win.roster.length > 1 ? win.roster.length : 0
            badgeAlert: win.lobby.length > 0 || win.hands.length > 0
            enabled: win.controlEnabled("RosterButton")
            onClicked: win.runControl("RosterButton")
        }
    }
    Component { id: cRaise; BarButton { icon: "call-raise"; label: win.handRaised ? "Lower" : "Raise"; checked: win.handRaised; tip: win.handRaised ? "Lower your hand" : "Raise your hand"; shortcut: "Ctrl+Shift+K"; enabled: win.controlEnabled("RaiseHandsButton"); onClicked: win.runControl("RaiseHandsButton") } }
    Component { id: cReact; BarButton { icon: "call-react"; label: "React"; checked: reactMenu.visible; tip: "Send a reaction"; enabled: win.controlEnabled("ReactionButton"); onClicked: win.runControl("ReactionButton") } }
    Component { id: cView; BarButton { id: viewB; icon: "call-view"; label: "View"; tip: "Change your view"; checked: viewMenu.visible && viewMenu.parent === viewB; enabled: win.controlEnabled("ViewModeButton"); onClicked: win.runControl("ViewModeButton") } }
    // Controls: the meeting options (organizers), as Teams opens them.
    Component { id: cControls; BarButton { icon: "call-controls"; label: "Controls"; enabled: win.controlEnabled("OrganizerControlButton"); onClicked: win.runControl("OrganizerControlButton") } }
    // Notes: Teams keeps meeting notes in the meeting chat's Notes tab.
    Component { id: cNotes; BarButton { icon: "call-notes"; label: "Notes"; tip: "Open notes"; enabled: win.controlEnabled("MeetingDetailsButton"); onClicked: win.runControl("MeetingDetailsButton") } }
    Component { id: cRooms; BarButton { icon: "call-rooms"; label: "Rooms"; tip: "Create breakout rooms"; enabled: win.controlEnabled("StartBreakoutRoomButton") } }
    Component { id: cApps; BarButton { id: appsB; icon: "call-apps"; label: "Apps"; tip: appsMenu.visible ? "Close apps" : "Find apps and more"; checked: appsMenu.visible && appsMenu.parent === appsB; onClicked: win.runControl("MeetingAppsAddButton") } }
    Component { id: cMore; BarButton { icon: "call-more"; label: "More"; tip: "More actions"; checked: moreMenu.visible; onClicked: win.runControl("MoreButton") } }
    Component {
        id: cCamera
        BarButton {
            id: camB
            icon: win.cameraOn ? "call-camera-filled" : "call-camera-off-filled"; label: "Camera"; strong: true
            // Teams' disabled reasons, first match wins (§3).
            readonly property string disabledReason: !win.canVideo ? "No available camera found"
                : win.videoRestricted ? "Only select participants can share video" : ""
            tip: disabledReason.length > 0 ? disabledReason : win.cameraOn ? "Turn camera off" : "Turn camera on"
            shortcut: disabledReason.length > 0 ? "" : "Ctrl+Shift+O"
            enabled: win.controlEnabled("VideoButton") && !win.videoRestricted
            // Teams' Camera ▾ (video-button-configure, "Open video options").
            split: true; chevronLabel: "Open video options"
            chevronChecked: videoFlyout.visible && videoFlyout.parent === camB
            onClicked: win.runControl("VideoButton")
            onChevronClicked: { videoFlyout.parent = camB; videoFlyout.open() }
        }
    }
    Component {
        id: cMic
        BarButton {
            id: micB
            icon: win.muted || !win.hasAudio ? "call-mic-off-filled" : "call-mic-filled"; label: "Mic"; strong: true
            tip: win.micRestricted ? "Only select participants can unmute"
                : !win.hasAudio ? "Turn audio on" : win.muted ? "Unmute mic" : "Mute mic"
            shortcut: win.micRestricted ? "" : "Ctrl+Shift+M"
            enabled: win.controlEnabled("MicrophoneButton") && !win.micRestricted
            split: true; chevronLabel: "Open audio options"
            chevronChecked: audioFlyout.visible && audioFlyout.parent === micB
            onClicked: win.runControl("MicrophoneButton")
            onChevronClicked: win.openAudioOptions(micB)
        }
    }
    Component {
        id: cShare
        BarButton {
            icon: win.sharing ? "call-share-stop-filled" : "call-share-filled"
            label: win.sharing ? "Stop sharing" : "Share"; strong: true
            iconColor: win.sharing ? "#B10E1C" : theme.text
            tip: win.sharing ? "Stop sharing" : "Share content"; shortcut: "Ctrl+Shift+E"
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
        width: split ? 74 : 56; height: 60
        // Teams' bar tooltip (Fluent Tooltip, measured on winpc): 10 below
        // the button, its left edge on the button's (or its right edge on
        // the button's when it would leave the window); 12/16 text,
        // padding 4 / 11 / 6, radius 4, a 12 px arrow at the button's
        // centre, shadows 2 and 8.
        function tipForTest() { bbTip.open() }
        ToolTip {
            id: bbTip
            parent: bb
            visible: bb.tip.length > 0 && bbHover.hovered
            delay: 250
            topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
            readonly property bool flip: bb.mapToItem(null, 4 + implicitWidth, 0).x > (bb.Window.window ? bb.Window.window.width : 1e9)
            x: flip ? 52 - implicitWidth : 4
            y: 64
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
            visible: bb.split
            x: 52; y: 6; width: 22; height: 48
            topRightRadius: 4; bottomRightRadius: 4
            color: (chevHover.hovered || bb.chevronChecked) ? theme.rowHover : "transparent"
            // Disabled together with the button (Teams' split buttons).
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon { x: 3; y: 16; name: "call-chevron"; size: 16; color: theme.text }
            HoverHandler { id: chevHover; cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: bb.enabled; onTapped: bb.chevronClicked() }
            Accessible.role: Accessible.Button
            Accessible.name: bb.chevronLabel
        }
        Rectangle {
            x: 4; y: 6; width: 48; height: 48
            radius: 4
            topRightRadius: bb.split ? 0 : 4; bottomRightRadius: bb.split ? 0 : 4
            color: bbHover.hovered && bb.enabled ? theme.rowHover : "transparent"
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon {
                x: 11.5; y: 3.5
                name: bb.icon; size: 25; color: bb.iconColor
                // Teams' alert badge (roster-button-badge): 18 px with a
                // 2 px white ring, #C50F1F, 10/700 white, 16 px right of
                // and 1.8 px above the glyph's corner.
                Rectangle {
                    visible: bb.badge > 0 && bb.badgeAlert
                    x: 16; y: -1.8
                    width: Math.max(18, bbAlert.implicitWidth + 8); height: 18; radius: 10
                    color: "#C50F1F"
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
                    color: bb.iconColor
                }
            }
            Text {
                x: 0.7; y: 30.3; width: 46.7; height: 16
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: bb.label
                elide: Text.ElideRight
                color: bb.strong || bbHover.hovered ? theme.text : theme.textStrong
                font.family: theme.font; font.pixelSize: 11
            }
            Rectangle {
                visible: bb.checked
                x: 0.7; y: 50.3; width: 46.7; height: 2; radius: 1
                color: theme.brand
            }
            HoverHandler { id: bbHover; cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (bb.enabled) bb.clicked() }
        }
        Accessible.role: Accessible.Button
        Accessible.name: bb.label
    }
}
