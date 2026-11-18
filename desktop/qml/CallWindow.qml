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
        const lockTip = "This option is locked because everyone in this meeting already has presenter permissions."
        return [
            { label: "Lock meeting", key: "lock", checked: locked, tip: "When the meeting is locked, nobody else can join the meeting." },
            { label: "Enable lobby", key: "AutoAdmittedUsers", checked: loaded && controlValue("AutoAdmittedUsers") !== "Everyone", enabled: loaded,
              tip: "When lobby is enabled, participants will wait in a lobby until admitted by an organizer." },
            { separator: true },
            { heading: "Allow all participants to:" },
            { label: "Present", key: "PresenterOption", checked: loaded && controlValue("PresenterOption") === "Everyone", enabled: loaded },
            { label: "Chat", key: "AllowMeetingChat", checked: loaded && controlValue("AllowMeetingChat") !== "Disabled", enabled: loaded },
            { label: "Unmute themselves", key: "audio", checked: avActive(true), enabled: loaded && !controlsEveryonePresents, tip: controlsEveryonePresents ? lockTip : "" },
            { label: "Turn on their cameras", key: "video", checked: avActive(false), enabled: loaded && !controlsEveryonePresents, tip: controlsEveryonePresents ? lockTip : "" },
            { separator: true },
            { label: "View more options", key: "options" }
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
            create: ["Breakout rooms have been created.", "call-rooms"], add: ["Room was added", ""],
            rename: ["Room was renamed", ""], delete: ["Room was deleted", ""], delete_all: ["Rooms were deleted", ""],
            import_csv: ["Breakout rooms have been created.", "call-rooms"]
        }
        const failed = {
            create: "We ran into a problem creating rooms. Try again.", add: "Room failed to be added",
            rename: "Room failed to be renamed", delete: "Room failed to be deleted", delete_all: "Couldn't delete rooms.",
            assign: "We had some trouble assigning participants.", announce: "Couldn't send your announcement.",
            settings: "Your settings failed to save", import_csv: "We ran into a problem creating rooms. Try again."
        }
        // A CSV import that skipped entries says why (Teams' import
        // warnings).
        const warnings = action === "import_csv" && !error
            ? ((backend.callBreakoutRoomsJson ? JSON.parse(backend.callBreakoutRoomsJson) : {}).warnings || []) : []
        if (error && failed[action]) showBreakoutAlert(action === "import_csv" && error.indexOf("couldn't import") >= 0 ? error : failed[action], "alert-warning-16-filled")
        else if (warnings.length > 1) showBreakoutAlert("Your CSV was imported, but some entries were skipped because of multiple issues.", "alert-warning-16-filled")
        else if (warnings.length === 1) showBreakoutAlert({
                MALFORMED_ENTRIES: "Some entries in CSV were skipped because of the following issues",
                USER_ASSIGNED_MULTIPLE_ROOMS: "Some participants were listed in multiple rooms. Each participant can be assigned to only one room. We kept the assignment from the last occurrence in the file. Remove duplicates, then import again.",
                LIMIT_EXCEEDED: "Breakout room limits were exceeded. Teams supports up to 100 rooms and 1000 participants. Reduce the number of rooms or participants in your CSV, then import again.",
                UNMATCHED_PARTICIPANTS: "Some entries in CSV were skipped because of the following issues"
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
        { key: "everyone", label: "Everyone", tip: "Chat for everyone in the meeting" },
        { key: "lobby", label: "Lobby", tip: "Chat for organizers messaging people in the lobby", badge: lobby.length + " waiting", count: lobby.length }
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
            return Object.assign({}, m, { text: named + " is in the lobby.", event: Object.assign({}, m.event, { unverified: (m.event.unverified || []).map(n => n === shown ? named : n) }) })
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
        organizer: organizer, onHold: held, canPopOut: presenting && !contentPoppedOut,
        // A town hall or webinar shows React only where the meeting allows reactions.
        reactions: !isEvent || !!liveEvent.reactions,
        roomToJoin: roomToJoin, canReturnToMain: canReturnToMain, breakoutRoom: backend.callBreakoutRoomJson !== "" || !!heldMeeting,
        centered: newControls, customization: dragPreview || controlsCustomization, echo: testCall, copilot: copilotAllowed,
        canTakeControl: presenting && !!controlState.capable,
        callMe: !!phone.available && !!phone.dialIn && !!phone.dial, facilitator: copilotAllowed,
        townHall: !!liveEvent.townHall, webinar: !!liveEvent.webinar, attendee: myRole === "attendee",
        greenRoom: !!liveEvent.staging && myRole !== "attendee" && live && liveEvent.eventPhase === "prelive",
        eventPhase: liveEvent.eventPhase || "", qna: !!liveEvent.qna && scheduled,
        e2ee: e2ee, canPark: canPark, voicemail: voicemail
    })
    /// A town hall or webinar (Backend call_event_json): its green room,
    /// live state, Manage what attendees see and Q&A
    /// (docs/spec/town-halls-and-webinars.md).
    readonly property var liveEvent: backend.callEventJson ? JSON.parse(backend.callEventJson) : ({})
    /// Teams' isEvent: a town hall or webinar says "event" (End event).
    readonly property bool isEvent: !!liveEvent.townHall || !!liveEvent.webinar
    /// Teams' enableTownhallDelayMessage (off in shipped clients): the
    /// town hall's own Start event wording.
    readonly property bool townhallDelayMessage: false
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
        { name: "FacilitatorToggle", label: aiFacilitator ? "Turn off Facilitator" : "Turn on Facilitator", icon: "ai-facilitator", enabled: organizer },
        { name: "FacilitatorVoice", label: backend.callAiFacilitatorVoice ? "Disable voice" : "Enable voice", icon: "sound-wave-circle-20", enabled: aiFacilitator && organizer }
    ]
    function facilitatorAction(name) {
        if (name === "FacilitatorToggle") {
            if (aiFacilitator) { backend.meetingAction("facilitatorOff"); return }
            backend.meetingAction("facilitatorOn")
            // Facilitator works from the transcript: Teams asks to start it.
            if (!transcribing) { facilitatorAsk = true; copilotAsk.visible = true }
        } else if (name === "FacilitatorVoice") backend.meetingAction(backend.callAiFacilitatorVoice ? "facilitatorVoiceOff" : "facilitatorVoiceOn")
    }
    TextMetrics { id: resumeMetrics; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; text: "Resume" }
    // Each control's slot (button 48 + 4 either side; split buttons 74).
    TextMetrics { id: joinRoomMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: "Join room" }
    TextMetrics { id: returnMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: "Return" }
    TextMetrics { id: startEventMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: win.startLabel }
    TextMetrics { id: endEventMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: win.endLabel }
    /// The green room's buttons (Teams' StagingRoomStartMeetingButton,
    /// "Start meeting" unless enableTownhallDelayMessage; End event for
    /// town halls and webinars, else End meeting).
    readonly property string startLabel: townhallDelayMessage && liveEvent.townHall ? "Start event" : "Start meeting"
    readonly property string endLabel: isEvent ? "End event" : "End meeting"
    // The compact bar: 32 px buttons in 36 px slots, split buttons 54.
    readonly property real ubarButton: compactBar ? 36 : 56
    readonly property real ubarDivider: compactBar ? 9 : 17
    readonly property var ubarWidths: ({ MicrophoneButton: compactBar ? 54 : 74, VideoButton: compactBar ? 54 : 74,
                                         ResumeButton: Math.ceil(resumeMetrics.advanceWidth) + 20 + 8 + 40 + 8,
                                         ReturnToBreakoutRoomButton: Math.ceil(joinRoomMetrics.advanceWidth) + 24.67 + 16,
                                         BreakoutRoomReturnToMainButton: Math.ceil(returnMetrics.advanceWidth) + 24.67 + 16,
                                         StagingRoomStartMeetingButton: Math.ceil(startEventMetrics.advanceWidth) + 24.67 + 16,
                                         StagingRoomEndMeetingButton: Math.ceil(endEventMetrics.advanceWidth) + 24.67 + 16,
                                         default: ubarButton })
    // The middle slot's room: from 4 past the indicators (shield, timer)
    // to 17 before Leave; the new controls' slot ends 4 before the end
    // slot and centres its controls.
    readonly property real ubarStart: timerText.x + timerText.implicitWidth + (compactBar ? 2.7 : 6.67) + 4
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
            ScreensharingControlButton: cTakeControl
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
        else if (name === "AudioSettingsButton") side = side === "audio" ? "" : "audio"
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
            ChatButton: { label: "Chat", icon: "call-chat", checked: side === "chat" },
            RosterButton: { label: side === "people" ? "Hide people" : "People", icon: "call-people", checked: side === "people" },
            RaiseHandsButton: { label: handRaised ? "Lower hand" : "Raise hand", icon: "call-raise" },
            ReactionButton: { label: "Send a reaction", icon: "call-react" },
            ViewModeButton: { label: "View", icon: "call-view", chevron: true },
            OrganizerControlButton: { label: "Controls", icon: "call-controls", chevron: true },
            MeetingDetailsButton: { label: side === "notes" ? "Close notes" : "Open notes", icon: "call-notes", checked: side === "notes" },
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
        // Teams' PstnButton ("Call me", the Call glyph).
        if (n === "PstnButton") return { label: "Call me", icon: "call-20", enabled: live }
        // Teams' FacilitatorButton: its glyph in brand while Facilitator is on.
        if (n === "FacilitatorButton") return { label: "Facilitator", icon: "ai-facilitator", iconColor: aiFacilitator ? theme.brand : undefined }
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
        if (n === "SettingsMenuControl") return { label: "Settings", icon: "settings-20" }
        if (n === "AccessibilitySettingsButton") return { label: "Accessibility settings", icon: "accessibility-20" }
        // Teams toggles the pane (toggle_call_health_on/off).
        if (n === "CallHealth") return { label: side === "callHealth" ? "Hide call health" : "Call health", icon: "pulse-20" }
        if (n === "ChatBubblesButton") return chatBubblesSuppressed
            ? { label: "Show chat bubbles", icon: "chat-bubbles-20" }
            : { label: "Don't show chat bubbles", icon: "chat-bubbles-off-20" }
        if (n === "MeetingHelpButton") return { label: "Help", icon: "question-circle-20" }
        if (n === "ReportMeetingButton") return { label: "Report a concern", icon: "shield-error-20" }
        if (n === "CallParkButton") return { label: "Park Call", icon: "call-park-20" }
        if (n === "MeetingFacilitatorTimerButton") return timerCanView
            ? { label: "Timer", icon: "timer-20", endCheck: timerVisible } : null
        if (n === "MuteNotificationsButton") return notificationsMuted
            ? { label: "Allow notifications", icon: "alert-20" }
            : { label: "Mute notifications", icon: "alert-off-20" }
        if (n === "ClosedCaptionsButton") return {
            label: captionsOn ? "Hide live captions" : "Show live captions",
            icon: "closed-caption-20", keys: "Alt+Shift+C", endCheck: captionsOn }
        // Once on, RTT stays on for the call (Teams greys it, checked).
        if (n === "RealTimeTextButton") return {
            label: "Turn on RTT for this call", icon: "real-time-text-20",
            endCheck: rttOn, enabled: !rttOn }
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
        title: "RTT"
        body: "RTT (real-time text) will be turned on for everyone in the call."
        confirmText: "Turn on"
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
    function openCopilot() {
        if (side === "copilot") { side = ""; return }
        if (!copilotOrTranscript && !copilotAsk.visible) { facilitatorAsk = false; copilotTurnOnAsk = copilotOnly; copilotAsk.visible = true; return }
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
            text: win.facilitatorAsk ? "Start transcription to use Facilitator"
                : win.copilotTurnOnAsk ? (win.callingScenario ? "Turn on Copilot for everyone in this call?" : "Turn on Copilot for everyone?")
                : "Start transcription to use Copilot"
            font.family: theme.font; font.pixelSize: 12; color: theme.text
        }
        FluentIcon {
            x: 291.3; y: 14.7; size: 16; name: "dismiss-16"; color: closeH.hovered ? theme.text : theme.textSecondary
            HoverHandler { id: closeH; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copilotAsk.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Text {
            id: askText
            x: win.facilitatorAsk ? 13 : 12.7; y: win.facilitatorAsk ? 41 : 40.7; width: 296.7
            text: win.facilitatorAsk ? "Transcription is required to get help from Facilitator in this meeting."
                : win.copilotTurnOnAsk ? (win.callingScenario ? "Copilot uses the audio, chat, and other content to answer questions. Start transcription to get an AI-generated recap."
                                                              : "Copilot uses the audio, chat, and other content to answer questions during the meeting.")
                : win.callingScenario ? "Transcription is required to get help from Copilot in the call."
                : "Transcription is required to get help from Copilot in the meeting."
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
            label: win.facilitatorAsk ? "Dismiss" : copilotAsk.callChoice ? "Just Copilot" : "Cancel"
            onClicked: {
                copilotAsk.visible = false
                if (!copilotAsk.callChoice) return
                win.copilotAfterTranscript = true
                recordStart.ask("copilot")
            }
        }
        SettingsParts.Button {
            x: 164; y: copilotAsk.buttonsY; width: 143.3; primary: true
            label: copilotAsk.callChoice ? "Transcribe" : win.copilotTurnOnAsk && !win.facilitatorAsk ? "Turn on" : "Start"
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
        x: (win.width - width) / 2; y: bar.height + 10.7
        width: 320; height: noticeText.y + noticeText.implicitHeight + 12.7; radius: 8
        color: theme.pick("#FAFAFA", "#292929", "#000000")
        border.width: theme.highContrast ? 1 : 0
        border.color: "#FFFFFF"
        Accessible.role: Accessible.AlertMessage
        Accessible.name: "Copilot is available in this meeting"
        FluentIcon { x: 12.7; y: 12.7; size: 20; name: "ai-copilot"; color: theme.text }
        Text {
            x: 40.7; y: 12.7; height: 20; verticalAlignment: Text.AlignVCenter
            text: "Copilot is available in this meeting"
            font.family: theme.font; font.pixelSize: 12; color: theme.text
        }
        FluentIcon {
            x: 291.3; y: 14.7; size: 16; name: "dismiss-16"; color: noticeClose.hovered ? theme.text : theme.textSecondary
            HoverHandler { id: noticeClose; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copilotOnNotice.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Text {
            id: noticeText
            x: 12.7; y: 40.7; width: 296.7
            textFormat: Text.StyledText
            text: "Copilot uses your data to generate responses during the meeting. Interactions with Copilot might be retained due to the host organization's policy."
                  + (win.privacyUrl ? " <a href=\"" + win.privacyUrl + "\">Privacy policy</a>" : "")
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
        else if (name === "PstnButton") openPhoneAudio()
        else if (name === "ClosedCaptionsButton") setCaptions(!captionsOn)
        else if (name === "RealTimeTextButton") { if (!rttOn) rttAsk.open() }
        else if (name === "AccessibilitySettingsButton") side = side === "accessibility" ? "" : "accessibility"
        else if (name === "CallHealth") side = side === "callHealth" ? "" : "callHealth"
        else if (name === "ChatBubblesButton") setChatBubblesSuppressed(!chatBubblesSuppressed)
        else if (name === "MuteNotificationsButton") {
            setNotificationsMuted(!notificationsMuted)
            // Teams announces it to screen readers.
            contentItem.Accessible.announce(notificationsMuted ? "Notifications allowed" : "Notifications muted")
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
            IndicatorTip { target: encryptionIndicator; text: "Encryption status"; shown: encHover.hovered && !encryptionCard.visible }
            Accessible.role: Accessible.Button
            Accessible.name: "Encryption status"
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
            x: win.compactBar ? (recordingIndicator.visible ? 52 : 30) : recordingIndicator.visible ? 68 : 38
            y: win.compactBar ? 8.7 : 14; width: win.compactBar ? 24.9 : 37.33; height: win.compactBar ? 22 : 32
            readonly property bool active: win.aiOn && win.aiAvailable
            readonly property string tip: !win.aiAvailable ? "AI isn't available in this meeting"
                : active ? "AI is on in the meeting" : "AI is turned off and doesn't have access to the meeting"
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
        // Teams' event state pill (VirtualEventsLiveIndicator) with a green
        // room: "Not started", "Live" or "Ended", then (presenters) the
        // attendees; attendees see "Waiting", "Live", "Ended".
        Rectangle {
            id: liveIndicator
            readonly property string phase: win.liveEvent.eventPhase || ""
            readonly property bool attendeeView: win.myRole === "attendee"
            visible: win.meeting && !win.compactBar && !!win.liveEvent.staging && (!attendeeView || phase === "active" || phase === "ended" || !!win.liveEvent.townHall)
            x: timerText.x - width - 8
            anchors.verticalCenter: parent.verticalCenter
            height: 24; radius: 12; width: liveRow.implicitWidth + 16
            color: phase === "active" ? "#C4314B" : theme.pick("#F0F0F0", "#333333", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: theme.text
            readonly property string label: phase === "active" ? "Live" : phase === "ended" ? "Ended" : attendeeView ? "Waiting" : "Not started"
            readonly property string tip: attendeeView
                ? (phase === "active" ? "The event is live." : phase === "ended" ? "The event has ended." : "Waiting for the event to start.")
                : phase === "active" ? (win.attendeeCount === 1 ? "1 attendee watching" : win.attendeeCount + " attendees watching")
                : phase === "ended" ? (win.attendeeCount === 1 ? "1 attendee remains" : win.attendeeCount + " attendees remain")
                : (win.attendeeCount === 1 ? "1 attendee waiting" : win.attendeeCount + " attendees waiting")
            Row {
                id: liveRow
                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: liveIndicator.label; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                       color: liveIndicator.phase === "active" ? "#FFFFFF" : theme.textStrong }
                Rectangle { visible: !liveIndicator.attendeeView; width: 1; height: 12; anchors.verticalCenter: parent.verticalCenter
                            color: liveIndicator.phase === "active" ? "#FFFFFF" : theme.textSecondary }
                FluentIcon { visible: !liveIndicator.attendeeView; anchors.verticalCenter: parent.verticalCenter; name: "people-16"; size: 16
                             color: liveIndicator.phase === "active" ? "#FFFFFF" : theme.textStrong }
                Text { visible: !liveIndicator.attendeeView; anchors.verticalCenter: parent.verticalCenter; text: win.attendeeCount; font.family: theme.font; font.pixelSize: 12
                       color: liveIndicator.phase === "active" ? "#FFFFFF" : theme.textStrong }
            }
            HoverHandler { id: liveHover }
            IndicatorTip { target: liveIndicator; text: liveIndicator.tip; shown: liveHover.hovered }
            Accessible.role: Accessible.StaticText; Accessible.name: liveIndicator.label + ". " + liveIndicator.tip
        }
        Text {
            id: timerText
            // After the shield (and the AI indicator), 6.67 into the
            // duration's slot.
            x: win.compactBar ? 30 + (recordingIndicator.visible ? 22 : 0) + (aiIndicator.visible ? 24.9 : 0) + 2.7
               : 38 + (recordingIndicator.visible ? 30 : 0) + (aiIndicator.visible ? 37.33 : 0) + 6.67
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
            x: win.newControls ? win.ubarStart + Math.max(0, (win.ubarRoom - implicitWidth) / 2)
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
                label: win.heldMeeting ? "Leave room" : "Leave"; strong: true
                iconColor: win.newControls ? theme.nmcLeave : theme.hc("#B10E1C", "#FFFFFF")
                danger: true
                tip: win.heldMeeting ? "Leave room" : "Leave"; shortcut: "Ctrl+Shift+H"
                // Teams splits Leave only when its menu has more than Leave.
                split: win.meeting && win.leaveItems.length > 1
                chevronLabel: "More options"
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
                    text: "Are you sure you want to leave?"
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                Item { width: 1; height: 18 }
                Rectangle {
                    id: hcFill2
                    width: 240; height: 31.3; radius: 4
                    color: stayHover.hovered ? theme.menuHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Text { anchors.centerIn: parent; text: "Stay"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                    HoverHandler { id: stayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: leaveConfirm.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Stay"
                }
                Item { width: 1; height: 8 }
                Rectangle {
                    id: hcFill3
                    width: 240; height: 31.3; radius: 4
                    color: goHover.hovered ? theme.hc("#A80C1A", "#1AEBFF") : theme.hc("#C50F1F", "#000000")
                    Text { anchors.centerIn: parent; text: "Leave"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, "white") }
                    HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { leaveConfirm.close(); win.leave() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Leave"
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
    onCameraOnChanged: if (side === "callHealth") refreshCallHealth()
    function callHealthPaneForTest() { return callHealthPane }
    property var timerData: null
    property bool everyonePresents: false
    readonly property bool timerCanView: meeting && everyonePresents
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
        if (timerVisible && timerStrip.cancelled && !timerViewOnly) Qt.callLater(timerStrip.openControls)
    }
    onTimerDataChanged: {
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
            if (!timerCancelledByMe) timerVisible = false
            timerCancelledByMe = false
        }
        // What changed, as Teams announces it to everyone.
        const left = timerStrip.spoken(timerData.adhoc.remainingDuration || 0)
        if (before === "Paused" && st === "InProgress") contentItem.Accessible.announce("Timer resumed with " + left + " remaining.")
        else if (before === "InProgress" && st === "Paused") contentItem.Accessible.announce("Timer paused at " + left + ".")
        else if (before === "Cancelled" && st === "InProgress") contentItem.Accessible.announce("Timer started with " + left + ".")
        else if (before === "InProgress" && st === "Cancelled") contentItem.Accessible.announce("Timer stopped.")
    }
    function timerStripForTest() { return timerStrip }
    MeetingTimerStrip {
        id: timerStrip
        visible: win.timerVisible && win.timerCanView && win.state === "connected"
        y: bar.y + bar.height
        width: sidePane.visible ? sidePane.x : win.contentItem.width
        info: win.timerData
        viewOnly: win.timerViewOnly
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
        items: (win.rttOn ? [{ label: "Live Captions", toggle: true, checked: win.captionsOn }] : []).concat([
                { label: "Open caption settings", icon: "settings-20", chevron: true },
                { label: win.rttOn ? "Open RTT/Captions in new window" : "Open captions in new window", icon: "captions-pop-out-20" }])
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
        title: "Help"
        width: 946; height: 593
        color: theme.surface
        property bool pinned: false
        flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
        readonly property Item titleBarForTest: helpTitle
        readonly property Item appForTest: helpApp.item
        ChildWindowTitleBar {
            id: helpTitle
            title: "Help"
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
        Rectangle {
            id: stagingScreen
            readonly property string phase: win.liveEvent.eventPhase || ""
            visible: win.meeting && win.myRole === "attendee" && (phase === "prelive" || phase === "ended")
            anchors.fill: parent; radius: parent.radius; color: theme.pane; z: 5
            Column {
                anchors.centerIn: parent; spacing: 8; width: parent.width - 48
                Text { visible: stagingScreen.phase === "prelive"; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Welcome to"
                       color: theme.text; font.family: theme.font; font.pixelSize: 16 }
                Text { visible: stagingScreen.phase === "prelive"; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: win.peer
                       color: theme.text; font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: stagingScreen.phase === "ended" ? "The event has concluded. Thank you for attending." : "This meeting will start shortly"
                       color: theme.text; font.family: theme.font; font.pixelSize: 16 }
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: stagingScreen.phase === "ended" ? "The event has concluded. Thank you for attending." : "Welcome to " + win.peer + ". This meeting will start shortly"
        }
        // Alone with your video on (measured on Teams desktop, a Meet now,
        // 2026-11-17): your own video (myself-video) fills the stage at
        // 16:9 (1031.8 x 578.7 in a 1274.7 x 582.7 stage, 2 from the top),
        // with its name tag (24 high, rgba(0,0,0,0.5), radius 4) 8 in from
        // the bottom left showing your voice level and mic state.
        Item {
            id: soloSelf
            visible: win.meeting && win.others.length === 0 && win.cameraOn && win.state === "connected" && !stagingScreen.visible
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
                    Accessible.name: "Myself video, " + (win.selfName || "You") + ", video is on"
                }
            }
        }
        Column {
            visible: win.meeting && win.others.length === 0 && !soloSelf.visible
            anchors.centerIn: parent
            spacing: 24
            Avatar { ring: false; size: 154; name: win.selfName || "You"; photoId: "me"; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // (Teams: an organizer or presenter is asked to invite.)
                text: win.state === "connected" ? (win.canMuteAll ? "Invite people to join you" : "Waiting for others to join...") : win.state === "ended" ? "You left the meeting" : "Connecting…"
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
            // Teams (updateShouldMeBeInOverlay, live): with at most two
            // people tiles, the other person fills the stage and you float
            // over it, bottom right.
            readonly property bool meOverlay: !content && win.others.length === 1 && !win.hideMe
            readonly property var side: content
                ? (win.layout === "focus" ? [] : win.othersOrdered.concat(win.hideMe ? [] : [win.selfEntry]))
                : meOverlay ? []
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
                visible: tiles.speakerView && !tiles.content && !tiles.meOverlay
                call: win
                person: tiles.speaker || ({})
                width: Math.min(tiles.mainW, tiles.mainH * 16 / 9); height: width * 9 / 16
                x: tiles.mainX + (tiles.mainW - width) / 2; y: tiles.mainY + (tiles.mainH - height) / 2
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
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 8 }
                    height: 24; radius: 4
                    width: contentName.implicitWidth + 12
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Text { id: contentName; x: 6; anchors.verticalCenter: parent.verticalCenter; text: win.presenterName; color: theme.onFill(hcFill5, "white"); font.family: theme.font; font.pixelSize: 14 }
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
            color: theme.hc("#CC000000", "#000000")
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
            Avatar { ring: false; size: 144; name: win.peer; photoId: backend.callPeerId; anchors.horizontalCenter: parent.horizontalCenter }
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
            Avatar { ring: false; visible: !selfVideo.visible; anchors.centerIn: parent; size: 64; name: win.selfName || "You"; photoId: "me" }
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
        // (Copilot's pane is 320 wide.)
        width: win.side === "copilot" ? 320 : 360
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
            chatName: "Lobby"
            myName: backend.userName
            isGroup: true
            messages: win.lobbyMessages
            paneTabs: win.chatTabs
            paneTab: win.chatTab
            onPaneTabPicked: key => win.chatTab = key
            onClosePane: win.side = ""
            emptyTitle: "Messages you send to people waiting in the lobby will show up here."
            // Teams' banners: the awareness note while someone waits, else
            // the compose is off with "Chat will be available…".
            composeTextOnly: true
            composeDisabled: win.lobby.length === 0
            composeNoteMuted: win.lobby.length === 0
            composeNote: win.lobby.length === 0 ? "Chat will be available when someone is waiting in the lobby."
                : "Messages you send are only visible to people currently in the lobby. They can view messages but not reply."
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
                    text: "Copilot"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                BarButton {
                    x: parent.width - 56; y: 6; width: 32; height: 31.3
                    icon: "dismiss-20"; label: ""; tip: ""
                    onClicked: win.side = ""
                    Accessible.name: "Close Copilot"
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
            onAnnounce: { roomText.rename = false; roomText.title = "Announcement"; roomText.initial = ""; roomText.placeholder = "Make an announcement"; roomText.thread = ""; roomText.show() }
            onRemoveRooms: removeRoomsAsk.open()
            onSaveSettings: s => win.breakoutRun("settings", s)
            onRoomAction: (action, room) => {
                if (action === "join") win.joinRoomAsOrganizer(room)
                else if (action === "open" || action === "close") win.breakoutRun(action, { threads: [room.thread] })
                else if (action === "rename") { roomText.rename = true; roomText.title = "Rename " + room.name + "?"; roomText.initial = room.name; roomText.placeholder = ""; roomText.thread = room.thread; roomText.show() }
                else if (action === "delete") { deleteRoomAsk.thread = room.thread; deleteRoomAsk.title = "Delete " + room.name + "?"; deleteRoomAsk.open() }
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
            pinnedId: win.pinnedId
            onParticipantAction: (action, id, name, stateId) => {
                if (action === "pin") win.pinnedId = id
                else if (action === "unpin") win.pinnedId = ""
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
                title: "Shared content | " + win.peer + " | OST"
                width: 1280; height: 680
                visible: true
                color: theme.hc("#F5F5F5", "#000000")
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
        title: "Your microphone is muted"
        text: "Press Ctrl+Shift+M to unmute your mic, or press and hold down Ctrl+Space."
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
        title: "Your report was sent"
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
        title: win.locked ? "This meeting is locked." : "This meeting is unlocked."
        text: win.locked ? "No one else can join." : "People can join."
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
    BreakoutInviteAlert {
        visible: !!win.breakoutInvite && !win.breakoutAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        roomName: win.breakoutInvite ? win.breakoutInvite.name : ""
        onLater: win.breakoutInvite = null
        onJoin: { win.breakoutInvite = null; win.joinBreakoutRoom() }
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
    readonly property var leaveItems: heldMeeting ? [{ k: "room", t: "Leave room" }, { k: "meeting", t: "Leave meeting" }]
        : [{ k: "leave", t: "Leave" }]
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
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Resume"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill8, theme.text) }
                        }
                        HoverHandler { id: resumeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.leaveRoom(true) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Resume"
                    }
                }
                BarButton { icon: "call-chat"; label: "Chat"; tip: "Chat"; onClicked: if (win.heldMeeting) backend.openChatWindow(win.heldMeeting.thread) }
                BarButton { icon: "call-people"; label: "People"; enabled: false }
                BarButton { icon: "call-raise"; label: "Raise"; enabled: false }
                BarButton { icon: "call-react"; label: "React"; enabled: false }
                BarButton { icon: "call-view"; label: "View"; enabled: false }
                BarButton { icon: "call-controls"; label: "Controls"; enabled: false }
                BarButton { icon: "call-notes"; label: "Notes"; enabled: false }
                BarButton { icon: "call-rooms"; label: "Rooms"; tip: "Breakout rooms"; checked: heldWindow.roomsShown; onClicked: heldWindow.roomsShown = !heldWindow.roomsShown }
                BarButton { icon: "call-apps"; label: "Apps"; enabled: false }
                Rectangle { width: 17; height: 60; color: "transparent"; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
                BarButton { icon: "call-camera-off-filled"; label: "Camera"; strong: true; split: true; enabled: false }
                BarButton { icon: "call-mic-off-filled"; label: "Mic"; strong: true; split: true; enabled: false }
                BarButton { icon: "call-share-filled"; label: "Share"; strong: true; enabled: false }
                Rectangle { width: 17; height: 60; color: "transparent"; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
                BarButton { icon: "call-leave-filled"; label: "Leave"; strong: true; iconColor: theme.hc("#B10E1C", "#FFFFFF"); tip: "Leave"; onClicked: backend.leaveHeldMeeting() }
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
                    text: "On hold " + win.clock(win.mainHeldSeconds)
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
        title: "Remove rooms?"
        body: "This will delete all existing rooms."
        confirmText: "Remove"
        onConfirmed: win.breakoutRun("delete_all", {})
    }
    ConfirmDialog {
        id: deleteRoomAsk
        property string thread: ""
        width: 500; closeButton: true
        body: ""
        confirmText: "Delete"
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
        title: "Overwriting rooms and participant assignment"
        body: "There are already rooms created with participants in them. If you import a CSV it will overwrite the current rooms and participant assignment. Are you sure to continue?"
        confirmText: "Continue"
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
        // Right-aligned to the chevron; start-aligned to the button when
        // that would leave the window (the new controls' Mic and Camera).
        x: !parent ? 0 : parent.mapToItem(null, parent.width - width, 0).x < 0 ? 0 : parent.width - width
        y: parent ? parent.height : 60
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
                text: "Call is parked"
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold
                lineHeight: 32; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Share this code " + win.parkCode + " to retrieve the call"
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
                    text: "Copy code"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.text
                }
                HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.copyText(win.parkCode) }
                Accessible.role: Accessible.Button
                Accessible.name: "Copy code " + win.parkCode
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
                text: win.meeting ? "End-to-end encryption enabled for this meeting" : "End-to-end encryption enabled for this call"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                id: encryptionText
                width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: theme.brandForeground1
                text: (!win.e2ee ? (win.meeting ? "This meeting is secured by OST data encryption. " : "This call is secured by OST data encryption. ")
                       : win.meeting ? "This meeting is end-to-end encrypted if the numbers below are the same for all participants. "
                       : "Verify your call's encryption by making sure the numbers below are the same for both of you. ")
                      + "<a href=\"" + (win.e2ee ? "https://go.microsoft.com/fwlink/?linkid=2174740" : "https://go.microsoft.com/fwlink/?linkid=2174896") + "\">Learn more</a>"
                font.family: theme.font; font.pixelSize: 12
                lineHeight: win.e2ee ? 20 : 16; lineHeightMode: Text.FixedHeight
                color: theme.textSecondary
                onLinkActivated: l => Qt.openUrlExternally(l)
                HoverHandler { cursorShape: encryptionText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                Accessible.name: win.e2ee ? "Learn more about OST End-to-end encryption" : "Learn more about OST data encryption"
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
                Accessible.name: "End-to-end encryption numbers " + win.e2eeNumbers.join(" ")
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
                model: [{ n: "like", t: "Like" }, { n: "heart", t: "Love" }, { n: "applause", t: "Applause" }, { n: "laugh", t: "Laugh" }, { n: "surprised", t: "Surprised" }]
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
                    text: win.handRaised ? "Lower hand" : "Raise hand"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(hcFillRaise, win.handRaised ? theme.textOnBrand : raiseHover.hovered ? theme.text : theme.textStrong)
                }
            }
            HoverHandler { id: raiseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: win.live; onTapped: win.toggleHand() }
            Accessible.role: Accessible.Button
            Accessible.name: "Raise"
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

    // ── Teams' New meeting controls: More's grid and list, the arrange
    // menus (measured on winpc 2026-11-16; docs/spec/new-meeting-controls.md).

    /// A control as More's grid shows it (and as it shows on the bar once
    /// pinned): its short label and glyph; null when OST doesn't show it.
    function gridEntry(name) {
        let e = null
        if (name === "RecordingButton") e = { label: recording ? "Recording" : "Record", icon: "nmc-record", checked: recording }
        else if (name === "TranscriptButton") {
            e = { label: transcribing ? "Transcribing" : "Transcribe", icon: "nmc-transcribe", checked: transcribing }
            // Once a transcript has run: its pane from the item's chevron.
            if (transcriptStarted) e.submenu = [{ name: "TranscriptPanelButton", label: side === "transcript" ? "Hide transcript" : "Show transcript",
                                                 icon: "transcript-panel-20", checked: side === "transcript" }]
        }
        else if (name === "MeetingFacilitatorTimerButton") e = timerCanView ? { label: "Timer", icon: "nmc-timer", checked: timerVisible } : null
        else if (name === "MeetingDetailsButton") e = { label: "Notes", icon: "nmc-notes", checked: side === "notes" }
        else if (name === "ClosedCaptionsButton") e = { label: "Captions", icon: "nmc-captions", checked: captionsOn }
        else if (name === "StartBreakoutRoomButton") e = { label: "Rooms", icon: "nmc-rooms", checked: side === "rooms" }
        else if (name === "RealTimeTextButton") e = { label: "RTT", icon: "nmc-rtt", checked: rttOn, enabled: !rttOn }
        else if (name === "MeetingAppsAddButton") e = { label: "Get more apps and agents", apps: true, checked: appsMenu.visible }
        // Bar controls that overflowed or were unpinned: their bar label.
        else if (name === "ChatButton") e = { label: "Chat", icon: "nmc-chat", checked: side === "chat" }
        else if (name === "RosterButton") e = { label: "People", icon: "nmc-people", checked: side === "people" }
        else if (name === "MeetingCollabButton") e = { label: "Copilot", icon: side === "copilot" ? "copilot-filled-48" : "ai-copilot", checked: side === "copilot" }
        else if (name === "ReactionButton") e = { label: "React", icon: handRaised ? "nmc-react-filled" : "nmc-react", checked: handRaised }
        else if (name === "RaiseHandsButton") e = { label: handRaised ? "Lower" : "Raise", icon: "nmc-raise", checked: handRaised }
        else if (name === "OrganizerControlButton") e = { label: "Controls", icon: "nmc-controls", chevron: true }
        else if (name === "PopoutContentButton") e = { label: "Pop out", icon: "call-popout" }
        else if (name === "CallTransferButtonV2") e = { label: "Transfer", icon: "call-transfer" }
        else if (name === "CallConsultativeTransferButtonV2") e = { label: "Consult", icon: "consult" }
        else if (name === "DialpadButton") e = { label: "Dial pad", icon: "dialpad" }
        else if (name === "HoldButton") e = { label: "Hold", icon: "pause" }
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
        if (n === "ViewModeButton") return { label: "View", icon: "nmc-view", submenu: newViewItems }
        if (n === "JoinInfoMenuControl") return { label: "Join info", icon: "nmc-info" }
        if (n === "SettingsMenuControl") return { label: "Settings", icon: "nmc-settings" }
        if (n === "MeetingInfoButton") return { label: "Meeting info", icon: "nmc-info", checked: side === "info" }
        if (n === "CallHealth") return { label: "Call health", icon: "nmc-health", checked: side === "callHealth" }
        if (n === "PstnButton") return { label: "Call me", icon: "nmc-callme" }
        if (n === "AccessibilitySettingsButton") return { label: "Accessibility settings", icon: "nmc-accessibility", checked: side === "accessibility" }
        if (n === "ChatBubblesButton") return chatBubblesSuppressed ? { label: "Show chat bubbles", icon: "nmc-bubbles" }
                                                                   : { label: "Don't show chat bubbles", icon: "nmc-bubbles-off" }
        if (n === "ToggleHideMyselfButton") return hideMe ? { label: "Unhide me", icon: "nmc-show-me" } : { label: "Hide me", icon: "nmc-hide-me" }
        if (n === "CameraEffectsButton") return { label: "Video effects and settings", icon: "nmc-effects", checked: side === "video" }
        if (n === "AudioSettingsButton") return { label: "Audio settings", icon: "nmc-audio", checked: side === "audio" }
        if (n === "ByodMeetingRoomModeButton") return { label: "Optimize for room", icon: "nmc-room", checked: roomMode }
        if (n === "ReportMeetingButton") return { label: "Report a concern", icon: "nmc-report" }
        if (n === "CallParkButton") return { label: "Park Call", icon: "call-park-20" }
        if (n === "MeetingHelpButton") return { label: "Help", icon: "nmc-help" }
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
        { action: "gallery", label: "Gallery", icon: "nmc-view", checked: layout === "gallery" },
        { action: "speaker", label: "Speaker", icon: "nmc-speaker", checked: layout === "speaker" },
        { separator: true },
        { action: "fullscreen", label: "Full screen", icon: "nmc-fullscreen", keys: "F11", checked: visibility === Window.FullScreen },
        { action: "focus", label: "Focus on content", icon: "nmc-focus", checked: layout === "focus", enabled: shareShown || layout === "focus" },
        { action: "galleryTop", label: galleryAtTop ? "Show gallery on right" : "Show gallery at top", icon: "nmc-gallery-right" }]
        .concat(layout === "gallery" ? [{ action: "gallerySize", label: "Gallery size", icon: "nmc-gallery-size",
                                          submenu: [4, 9, 16, 49].map(n => ({ label: n + " people", checked: gallerySize === n })) }] : [])
        .concat([{ separator: true },
                 { action: "incoming", label: incomingVideoOff ? "Turn on other videos" : "Turn off other videos", icon: "nmc-videos-off" }])
        .concat(layout === "gallery" ? [{ action: "videosFirst", label: "Show videos first", icon: "view-videos-first-20", checked: videosFirst }] : [])
    function runViewAction(a) {
        if (a === "gallery") layout = "gallery"
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
                        Accessible.name: "More options for " + cell.modelData.label
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
                Accessible.name: "Apps"
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
        if (i > 0) rows.push({ action: "before", label: "Move before \"" + controlLabel(group[i - 1]) + "\"", icon: "nmc-move-before" })
        if (i < group.length - 1) rows.push({ action: "after", label: "Move after \"" + controlLabel(group[i + 1]) + "\"", icon: "nmc-move-after" })
        rows.push({ action: "unpin", label: "Unpin", icon: "nmc-unpin" }, { separator: true },
                  { action: "reset", label: "Reset meeting controls", icon: "nmc-reset" })
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
            rows.push({ action: "pin", label: "Pin", icon: "nmc-pin" }, { separator: true })
        rows.push({ action: "reset", label: "Reset meeting controls", icon: "nmc-reset" })
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
                        text: "Open chat"; font.family: theme.font; font.pixelSize: theme.small; color: theme.brandForeground1
                        z: 2
                        TapHandler { onTapped: { picker.close(); win.consulting = { id: modelData.id, name: modelData.name }; win.consult(modelData.id, modelData.name) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Open chat with " + modelData.name
                    }
                    TapHandler {
                        onTapped: {
                            picker.close()
                            if (picker.mode === "transfer") win.transfer(modelData.id, modelData.name)
                            else win.consultByCall(modelData.id, modelData.name)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: (picker.mode === "transfer" ? "Transfer to " : "Start a call with ") + modelData.name
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
                text: parent.parent.consultState === "calling" ? "Calling " + parent.parent.who + "…"
                    : parent.parent.consultState === "transferring" ? "Transferring to " + parent.parent.who + "…"
                    : parent.parent.consultState === "merging" ? "Merging calls…"
                    : "Consulting " + parent.parent.who
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            Repeater {
                model: [
                    { key: "transfer", label: "Transfer", primary: true, on: true },
                    { key: "merge", label: "Merge Calls", primary: false, on: true },
                    { key: "end", label: "End consult", primary: false, on: false }
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
            Text { anchors.verticalCenter: parent.verticalCenter; text: win.consulting ? "Consulting " + win.consulting.name : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Rectangle {
                id: hcFill11
                width: 84; height: 28; radius: theme.radius; color: theme.brandFill
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "Transfer"; color: theme.onFill(hcFill11, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
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
                id: hcFill12
                x: 4; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 8; height: 48; radius: theme.radius
                color: rph.hovered ? theme.hc(theme.pane, theme.hcHighlight) : theme.rowHover
                border.color: theme.stroke
                Row {
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "play-20"; size: 20; color: theme.onFill(hcFill12, theme.text) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Resume"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(hcFill12, theme.text) }
                }
                HoverHandler { id: rph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.runControl("ResumeButton") }
                Accessible.role: Accessible.Button
                Accessible.name: "Resume"
            }
        }
    }
    // Copilot (meeting-collab-button): Teams' Copilot mark, filled while
    // its pane is open; "Open Copilot (Alt+C)" / "Close Copilot".
    Component { id: cCopilot; BarButton { icon: win.side === "copilot" ? "copilot-filled-48" : "ai-copilot"; label: "Copilot"; checked: win.side === "copilot"; tip: win.side === "copilot" ? "Close Copilot" : "Open Copilot"; shortcut: win.side === "copilot" ? "" : "Alt+C"; enabled: win.controlEnabled("MeetingCollabButton"); onClicked: win.runControl("MeetingCollabButton") } }
    Component { id: cChat; BarButton { icon: win.newControls ? "nmc-chat" : "call-chat"; label: "Chat"; checked: win.side === "chat"; tip: win.side === "chat" ? "Hide conversation" : "Show conversation"; enabled: win.controlEnabled("ChatButton"); onClicked: win.runControl("ChatButton") } }
    Component {
        id: cPeople
        BarButton {
            icon: win.newControls ? "nmc-people" : "call-people"; label: "People"; checked: win.side === "people"
            readonly property int count: win.roster.length
            // The new controls' tooltip has no count.
            tip: (count === 0 || win.newControls ? "" : count === 1 ? "1 participant. " : count + " participants. ") + (win.side === "people" ? "Hide participants" : "Show participants")
            // Teams: people waiting in the lobby, or raised hands, as a
            // red count; else how many are here (meetings).
            badge: !win.meeting ? 0 : win.lobby.length > 0 ? win.lobby.length : win.hands.length > 0 ? win.hands.length : win.roster.length > 1 ? win.roster.length : 0
            badgeAlert: win.lobby.length > 0 || win.hands.length > 0
            enabled: win.controlEnabled("RosterButton")
            onClicked: win.runControl("RosterButton")
        }
    }
    Component { id: cRaise; BarButton { icon: "call-raise"; label: win.handRaised ? "Lower" : "Raise"; checked: win.handRaised; tip: win.handRaised ? "Lower your hand" : "Raise your hand"; shortcut: "Ctrl+Shift+K"; enabled: win.controlEnabled("RaiseHandsButton"); onClicked: win.runControl("RaiseHandsButton") } }
    // The new controls: React holds Raise hand too; its glyph is the
    // emoji-hand, filled in brand while your hand is up.
    Component { id: cReact; BarButton { icon: !win.newControls ? "call-react" : win.handRaised ? "nmc-react-filled" : "nmc-react"; label: "React"; checked: reactMenu.visible
            iconColor: win.newControls && win.handRaised ? theme.brand : hovered ? theme.text : theme.textStrong
            tip: !win.newControls ? "Send a reaction" : win.handRaised ? "React or lower your hand. Your hand is raised" : "React or raise your hand. Your hand is not raised"; enabled: win.controlEnabled("ReactionButton"); onClicked: win.runControl("ReactionButton") } }
    Component { id: cView; BarButton { id: viewB; icon: "call-view"; label: "View"; tip: "Change your view"; checked: viewMenu.visible && viewMenu.parent === viewB; enabled: win.controlEnabled("ViewModeButton"); onClicked: win.runControl("ViewModeButton") } }
    // Controls: the meeting options (organizers), as Teams opens them.
    Component { id: cControls; BarButton { id: ctlB; icon: win.newControls ? "nmc-controls" : "call-controls"; label: "Controls"; checked: controlsMenu.visible; enabled: win.controlEnabled("OrganizerControlButton"); onClicked: win.runControl("OrganizerControlButton"); Component.onCompleted: win.controlsButton = ctlB } }
    // Notes: Teams keeps meeting notes in the meeting chat's Notes tab.
    Component { id: cNotes; BarButton { icon: win.newControls ? "nmc-notes" : "call-notes"; label: "Notes"; tip: win.side === "notes" ? "Close notes" : "Open notes"; checked: win.side === "notes"; enabled: win.controlEnabled("MeetingDetailsButton"); onClicked: win.runControl("MeetingDetailsButton") } }
    Component { id: cRooms; BarButton { icon: win.newControls ? "nmc-rooms" : "call-rooms"; label: "Rooms"; tip: win.breakoutRooms.length ? "Breakout rooms" : "Create breakout rooms"; checked: win.side === "rooms"; enabled: win.controlEnabled("StartBreakoutRoomButton"); onClicked: win.runControl("StartBreakoutRoomButton") } }
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
    Component { id: cJoinRoom; BarTextButton { label: "Join room"; control: "ReturnToBreakoutRoomButton" } }
    // Start meeting (primary) and End event in the end slot; disabled
    // while a presenter starts or ends it (Teams' tooltips).
    Component { id: cStartEvent; BarTextButton { label: win.startLabel; control: "StagingRoomStartMeetingButton"; primary: true; usable: !win.liveEvent.busy
        tip: win.liveEvent.busy ? (win.isEvent ? "A presenter already started the event" : "A presenter already started the meeting") : "" } }
    Component { id: cEndEvent; BarTextButton { label: win.endLabel; control: "StagingRoomEndMeetingButton"; usable: !win.liveEvent.busy
        tip: win.liveEvent.busy ? (win.isEvent ? "Someone already ended the event" : "Someone already ended the meeting") : "" } }
    Component { id: cQna; BarButton { icon: "chat-bubbles-question-20"; label: "Q&A"; tip: "Q&A"; checked: win.side === "qna"; onClicked: win.runControl("YammerQnaButton") } }
    Component { id: cReturnMain; BarTextButton { label: "Return"; control: "BreakoutRoomReturnToMainButton" } }
    Component { id: cApps; BarButton { id: appsB; icon: "call-apps"; label: "Apps"; tip: appsMenu.visible ? "Close apps" : "Find apps and more"; checked: appsMenu.visible && appsMenu.parent === appsB; onClicked: win.runControl("MeetingAppsAddButton") } }
    Component { id: cMore; BarButton { icon: win.newControls ? "nmc-more" : "call-more"; label: "More"; tip: "More actions"; checked: moreMenu.visible || newMore.visible; dropTarget: win.dragZone === "more"; onClicked: win.runControl("MoreButton") } }
    Component {
        id: cCamera
        BarButton {
            id: camB
            // The new controls draw the regular glyphs in #424242.
            icon: win.newControls ? (win.cameraOn ? "nmc-camera" : "nmc-camera-off") : win.cameraOn ? "call-camera-filled" : "call-camera-off-filled"
            label: "Camera"; strong: !win.newControls
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
            icon: win.newControls ? (win.muted || !win.hasAudio ? "nmc-mic-off" : "nmc-mic") : win.muted || !win.hasAudio ? "call-mic-off-filled" : "call-mic-filled"
            label: "Mic"; strong: !win.newControls
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
    // Teams' ScreensharingControlButton (someone else presents and their
    // screen can be controlled): Take control, Waiting for approval,
    // Stop control.
    Component {
        id: cTakeControl
        BarButton {
            readonly property string st: win.controlState.state || "none"
            icon: "take-control-20"
            label: st === "controlling" ? "Stop control" : st === "requested" ? "Waiting for approval" : "Take control"
            checked: st === "controlling"
            tip: win.controlState.deniedBySharer ? "Requesting control is disabled by the sharer company's administrator"
                : st === "controlling" ? "Stop control" : st === "requested" ? "Waiting for approval" : "Take control of the presentation"
            enabled: win.controlEnabled("ScreensharingControlButton")
            onClicked: win.runControl("ScreensharingControlButton")
        }
    }
    Component {
        id: cShare
        BarButton {
            icon: win.newControls ? (win.sharing ? "nmc-share-stop" : "nmc-share") : win.sharing ? "call-share-stop-filled" : "call-share-filled"
            label: win.sharing ? "Stop sharing" : "Share"; strong: !win.newControls
            iconColor: win.sharing ? theme.hc("#B10E1C", "#FFFFFF") : win.newControls && !hovered ? theme.textStrong : theme.text
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
        readonly property real bw: compact ? 32 : Math.max(48, Math.ceil(bbLabelMetrics.advanceWidth) + 8)
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
    function openShareTray() {
        const b = barItem("ShareButton")
        const c = b && b !== bar ? b.mapToItem(win.contentItem, b.width / 2, 0).x : win.width / 2
        shareTray.x = Math.max(8, Math.min(win.width - 360 - 8, c - 180))
        shareTray.y = bar.height - 0.7
        shareTray.open()
    }
    function shareTrayForTest() { return shareTray }
    ShareTray {
        id: shareTray
        parent: win.contentItem
        cameraOn: win.cameraOn
        mode: win.presentingState.mode || "ContentOnly"
        backgroundId: win.presentingState.background ? win.presentingState.background.id : ""
        onShare: kind => { close(); win.shareKind = kind; win.startShare(kind) }
        onPickMode: m => win.setPresenterMode(m)
        onPickBackground: b => win.setPresenterBackground(JSON.stringify(b))
        onContentCamera: type => { contentCameraDialog.type = type; contentCameraDialog.open() }
    }
    // Content from camera's setup (Teams' content camera setup dialog):
    // Camera and Content type, then Share — the camera goes out as shared
    // content (as the screen does).
    Popup {
        id: contentCameraDialog
        property string type: "whiteboard"
        property var devices: []
        property string device: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 440; padding: 24
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        onAboutToShow: {
            const d = JSON.parse(backend.videoDevices() || "{}")
            devices = d.devices || []
            device = d.current || (devices[0] ? devices[0].path : "")
        }
        contentItem: Column {
            spacing: 16
            Text {
                text: "Content from camera"
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            }
            Column {
                spacing: 4
                Text { text: "Camera"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Dropdown {
                    width: 392
                    label: (contentCameraDialog.devices.find(d => d.path === contentCameraDialog.device) || { name: "None" }).name
                    options: contentCameraDialog.devices.map(d => [d.path, d.name])
                    accessibleName: "Camera"
                    onPicked: code => contentCameraDialog.device = code
                }
            }
            Column {
                spacing: 4
                Text { text: "Content type"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Dropdown {
                    width: 392
                    label: ({ whiteboard: "Whiteboard", document: "Document", video: "Video" })[contentCameraDialog.type]
                    options: [["whiteboard", "Whiteboard"], ["document", "Document"], ["video", "Video"]]
                    accessibleName: "Content type"
                    onPicked: code => contentCameraDialog.type = code
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                SettingsParts.Button { label: "Cancel"; onClicked: contentCameraDialog.close() }
                SettingsParts.Button {
                    label: "Share"; primary: true
                    enabled: contentCameraDialog.device.length > 0
                    onClicked: { contentCameraDialog.close(); win.shareKind = "camera"; backend.startContentCamera(contentCameraDialog.device) }
                }
            }
        }
    }
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
        title: th ? "Start the event for everyone?" : "Start the meeting for everyone?"
        body: th ? (win.attendeeCount === 1 ? "1 attendee will enter and watch the event at a slight delay." : win.attendeeCount + " attendees will enter and watch the event at a slight delay.")
                 : (win.attendeeCount === 1 ? "1 attendee will enter the meeting" : win.attendeeCount + " attendees will enter the meeting")
        confirmText: th ? "Start event" : "Start meeting"
        onConfirmed: backend.setEventLive(true)
    }
    ConfirmDialog {
        id: endEventDialog
        title: win.isEvent ? "End the event for attendees?" : "End the meeting for attendees?"
        body: win.isEvent ? "This will end the event for all attendees and return organizers and presenters to the Green Room."
                          : "This will end the meeting for all attendees and return organizers and presenters to the Green Room."
        confirmText: win.isEvent ? "End event for all attendees" : "End meeting"
        onConfirmed: backend.setEventLive(false)
    }
    property int eventFailures: 0
    function startEventForTest() { startEventDialog.close(); backend.setEventLive(true) }
    function endEventForTest() { endEventDialog.close(); backend.setEventLive(false) }
    ConfirmDialog {
        id: eventFailedDialog
        property bool starting: true
        title: starting ? "Unable to start meeting" : (win.isEvent ? "Couldn't end event" : "Couldn't end meeting")
        body: starting ? (win.eventFailures > 1 ? "Wait and try again later or ask another presenter or organizer to start the meeting for you." : "Let's try starting the meeting again.")
                       : win.eventFailures > 1 ? "Wait and try again or ask another organizer to end it." : (win.isEvent ? "Let's try ending the event again." : "Let's try ending the meeting again.")
        confirmText: "Try again"
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
    CallAlert {
        readonly property bool ended: win.liveEvent.eventPhase === "ended" && win.myRole !== "attendee"
        visible: (win.ubarFacts.greenRoom || ended) && !win.liveEvent.busy && !win.greenRoomAlertClosed && !win.breakoutAlert
        x: stage.x + (stage.width - width) / 2
        y: win.belowBar + 10.7
        z: 6
        // Back in the green room after the end (Teams' info alert).
        text: !ended ? "Start the meeting whenever you're ready."
            : win.isEvent ? "The event has ended for attendees. If recording was enabled, it has now stopped."
            : "The meeting has ended for attendees and recording has stopped."
        icon: "info-20"
        onDismissed: win.greenRoomAlertClosed = true
        onEndedChanged: if (ended) win.greenRoomAlertClosed = false
    }
    ConfirmDialog {
        id: requestControlDialog
        title: "Request control?"
        body: "You'll control the content the presenter is sharing."
        confirmText: "Request"
        onConfirmed: win.screenControl("request", "")
    }
    // Give / take control's alerts (calling alerts 523673 and the
    // viewer's notices).
    property var controlAlert: null
    Connections {
        target: backend
        function onScreenControlNotice(kind, mri, name) {
            const n = name || "Someone"
            if (kind === "request") win.controlAlert = { kind: "request", text: n + " is requesting control.", mri: mri }
            else if (kind === "withdrawn" && win.controlAlert && win.controlAlert.kind === "request") win.controlAlert = null
            else if (kind === "hasControl") win.controlAlert = { kind: "has", text: n + " has control.", mri: mri }
            else if (kind === "controlEnded" && win.controlAlert && win.controlAlert.kind === "has") win.controlAlert = null
            else if (kind === "given") win.controlAlert = { kind: "note", text: "You have been given screen control" }
            else if (kind === "denied") win.controlAlert = { kind: "note", text: "Your request for control wasn't accepted." }
            else if (kind === "takenBack") win.controlAlert = { kind: "note", text: "The person sharing took control back." }
            else if (kind === "stopped") win.controlAlert = { kind: "note", text: "Screen control has been stopped" }
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
