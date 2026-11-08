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
    /// The meeting's link to share (Share invite).
    property string inviteUrl: ""
    /// Who waits in the meeting's lobby: [{id, name, suspected}].
    property var lobby: []
    signal admitLobby(string id, string name, bool notBot)
    signal denyLobby(string id, string name)
    signal admitAllLobby()
    /// Organizers: Teams' End meeting (after its confirmation).
    signal endMeeting()
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
        && others.some(p => p.active !== false && !p.server_muted)
    /// Your own MRI, to tell you apart in the roster.
    property string selfId: ""
    readonly property var others: roster.filter(p => p.id !== selfId)
    // Teams shows Controls and Rooms to the meeting's organizer only.
    readonly property bool organizer: ((roster.find(p => p.id === selfId) || {}).role || "").toLowerCase() === "organizer"
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
          .concat(others.map(p => ({ name: p.name, id: p.id, you: false, mutedNow: p.server_muted, role: p.role, hand: !!p.hand, guest: !!p.guest, suspected: !!p.suspected })))
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
    }

    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
        const two = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + two(m) : two(m)) + ":" + two(sec)
    }

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
        Text {
            x: win.meeting ? 44.7 : 16; anchors.verticalCenter: parent.verticalCenter
            text: win.state === "connected" ? win.clock(win.seconds) : "--:--"
            color: theme.textStrong
            font.family: theme.font; font.pixelSize: 14
        }
        // A meeting's controls, as Teams desktop lays them out (56 px slots,
        // right-aligned 4 px before the Leave group). Those OST can't do yet
        // are shown disabled.
        Row {
            visible: win.meeting
            anchors { right: leaveGroup.left; rightMargin: 17; top: parent.top }
            spacing: 0
            BarButton {
                icon: "call-chat"; label: "Chat"; checked: win.side === "chat"
                onClicked: { win.side = win.side === "chat" ? "" : "chat"; if (win.side === "chat") win.openChat() }
            }
            BarButton {
                icon: "call-people"; label: "People"; checked: win.side === "people"
                // Teams: people waiting in the lobby, or raised hands, as a
                // red count; else how many are here.
                badge: win.lobby.length > 0 ? win.lobby.length : win.hands.length > 0 ? win.hands.length : win.roster.length > 1 ? win.roster.length : 0
                badgeAlert: win.lobby.length > 0 || win.hands.length > 0
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton {
                icon: "call-raise"; label: win.handRaised ? "Lower" : "Raise"
                enabled: win.live
                checked: win.handRaised
                onClicked: win.toggleHand()
            }
            BarButton {
                id: reactButton
                icon: "call-react"; label: "React"
                enabled: win.live
                checked: reactMenu.visible
                onClicked: reactMenu.open()
            }
            BarButton { id: viewBtnM; icon: "call-view"; label: "View"; checked: viewMenu.visible && viewMenu.parent === viewBtnM; onClicked: { viewMenu.parent = viewBtnM; viewMenu.open() } }
            // Controls: the meeting options (organizers), as Teams opens them.
            BarButton { visible: win.organizer; icon: "call-controls"; label: "Controls"; enabled: win.optionsUrl.length > 0; onClicked: Qt.openUrlExternally(win.optionsUrl) }
            // Notes: Teams keeps meeting notes in the meeting chat's Notes tab.
            BarButton { icon: "call-notes"; label: "Notes"; enabled: win.chatUrl.length > 0; onClicked: Qt.openUrlExternally(win.chatUrl) }
            BarButton { visible: win.organizer; icon: "call-rooms"; label: "Rooms"; enabled: false }
            BarButton { id: appsBtnM; icon: "call-apps"; label: "Apps"; checked: appsMenu.visible && appsMenu.parent === appsBtnM; onClicked: { appsMenu.parent = appsBtnM; appsMenu.open() } }
            BarButton { id: moreBtnM; icon: "call-more"; label: "More"; checked: moreMenu.visible && moreMenu.parent === moreBtnM; onClicked: { moreMenu.parent = moreBtnM; moreMenu.open() } }
            Divider {}
            BarButton {
                icon: win.cameraOn ? "call-camera-filled" : "call-camera-off-filled"; label: "Camera"; strong: true
                enabled: win.canVideo
                onClicked: win.toggleCamera()
            }
            BarButton {
                id: micButtonM
                icon: win.muted || !win.hasAudio ? "call-mic-off-filled" : "call-mic-filled"; label: "Mic"; strong: true
                enabled: win.hasAudio
                split: true; chevronLabel: "Open audio options"
                chevronChecked: audioFlyout.visible && audioFlyout.parent === micButtonM
                onClicked: win.toggleMute()
                onChevronClicked: win.openAudioOptions(micButtonM)
            }
            BarButton {
                icon: win.sharing ? "call-share-stop-filled" : "call-share-filled"
                label: win.sharing ? "Stop sharing" : "Share"; strong: true
                iconColor: win.sharing ? "#B10E1C" : theme.text
                enabled: win.canShare || win.sharing
                onClicked: win.toggleShare()
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
                split: win.meeting
                chevronLabel: "More options"
                chevronChecked: leaveMenu.visible
                onClicked: win.leave()
                onChevronClicked: leaveMenu.open()
            }
        }
        Row {
            visible: !win.meeting
            anchors { right: leaveGroup.left; rightMargin: 17; top: parent.top }
            spacing: 0
            BarButton {
                id: transferBtn
                icon: "call-transfer"; label: "Transfer"
                enabled: win.live
                checked: picker.visible && picker.mode === "transfer"
                onClicked: { picker.mode = "transfer"; picker.parent = transferBtn; picker.open() }
            }
            BarButton {
                id: consultBtn
                icon: "consult"; label: "Consult"
                enabled: win.live
                checked: picker.visible && picker.mode === "consult"
                onClicked: { picker.mode = "consult"; picker.parent = consultBtn; picker.open() }
            }
            Divider {}
            BarButton {
                id: padBtn
                icon: "dialpad"; label: "Dial pad"
                enabled: win.live && win.canDtmf && !win.held
                checked: dialPad.visible
                onClicked: dialPad.visible ? dialPad.close() : dialPad.open()
            }
            BarButton {
                visible: !win.held
                icon: "pause"; label: "Hold"
                enabled: win.live && win.hasAudio
                onClicked: win.toggleHold()
            }
            // Held: Teams swaps Hold for a bordered "Resume" pill.
            Rectangle {
                visible: win.held
                anchors.verticalCenter: parent.verticalCenter
                width: resumeRow.implicitWidth + 40; height: 48; radius: theme.radius
                color: rph.hovered ? theme.pane : theme.rowHover
                border.color: theme.stroke
                Row {
                    id: resumeRow
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "play-20"; size: 20; color: theme.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Resume"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                }
                HoverHandler { id: rph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.toggleHold() }
                Accessible.role: Accessible.Button
                Accessible.name: "Resume"
            }
            Divider {}
            BarButton {
                icon: "call-chat"; label: "Chat"; checked: win.side === "chat"
                onClicked: { win.side = win.side === "chat" ? "" : "chat"; if (win.side === "chat") win.openChat() }
            }
            BarButton {
                icon: "call-people"; label: "People"; checked: win.side === "people"
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton { id: viewBtn; icon: "call-view"; label: "View"; checked: viewMenu.visible && viewMenu.parent === viewBtn; onClicked: { viewMenu.parent = viewBtn; viewMenu.open() } }
            BarButton { id: appsBtn; icon: "call-apps"; label: "Apps"; checked: appsMenu.visible && appsMenu.parent === appsBtn; onClicked: { appsMenu.parent = appsBtn; appsMenu.open() } }
            BarButton { id: moreBtn; icon: "call-more"; label: "More"; checked: moreMenu.visible && moreMenu.parent === moreBtn; onClicked: { moreMenu.parent = moreBtn; moreMenu.open() } }
            Divider {}
            BarButton {
                icon: win.cameraOn ? "call-camera-filled" : "call-camera-off-filled"; label: "Camera"; strong: true
                enabled: win.canVideo && !win.held
                onClicked: win.toggleCamera()
            }
            BarButton {
                id: micButton1
                icon: win.muted || !win.hasAudio ? "call-mic-off-filled" : "call-mic-filled"; label: "Mic"; strong: true
                enabled: win.hasAudio && !win.held
                split: true; chevronLabel: "Open audio options"
                chevronChecked: audioFlyout.visible && audioFlyout.parent === micButton1
                onClicked: win.toggleMute()
                onChevronClicked: win.openAudioOptions(micButton1)
            }
            BarButton {
                icon: win.sharing ? "call-share-stop-filled" : "call-share-filled"
                label: win.sharing ? "Stop sharing" : "Share"; strong: true
                iconColor: win.sharing ? "#B10E1C" : theme.text
                enabled: win.canShare || win.sharing
                onClicked: win.toggleShare()
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // Stage
    Rectangle {
        id: stage
        anchors { top: bar.bottom; left: parent.left; right: sidePane.visible ? sidePane.left : parent.right; bottom: parent.bottom; margins: 6 }
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
            visible: win.meeting && win.others.length > 0 && win.layout !== "focus"
            anchors { fill: parent; margins: 2.67 }
            readonly property bool speakerView: win.layout === "speaker"
            readonly property var speaker: {
                const pool = win.speakerMeInGallery && !win.hideMe ? win.others.concat([win.selfEntry]) : win.others
                return pool.find(p => p.id === win.speakerId) || win.othersOrdered[0]
            }
            readonly property var side: speakerView
                ? win.othersOrdered.filter(p => p !== speaker).concat(win.hideMe || speaker.self ? [] : [win.selfEntry])
                : (win.hideMe || win.meInGallery ? [] : [win.selfEntry])
            readonly property var gallery: (win.hideMe || !win.meInGallery ? [] : [win.selfEntry]).concat(win.othersOrdered).slice(0, win.gallerySize)
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
                visible: tiles.speakerView
                call: win
                person: tiles.speaker || ({})
                width: Math.min(tiles.mainW, tiles.mainH * 16 / 9); height: width * 9 / 16
                x: tiles.mainX + (tiles.mainW - width) / 2; y: tiles.mainY + (tiles.mainH - height) / 2
            }
            // Gallery.
            GalleryGrid {
                visible: !tiles.speakerView
                x: tiles.mainX; y: tiles.mainY; width: tiles.mainW; height: tiles.mainH
                call: win
                people: tiles.gallery
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
            visible: hasFrame && win.state === "connected" && !win.held && !win.heldByPeer
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
        color: win.side === "people" ? theme.pane : theme.surface
        clip: true
        Conversation {
            id: chatPane
            visible: win.side === "chat"
            anchors.fill: parent; anchors.margins: 1
            pane: true
            onClosePane: win.side = ""
        }
        PeoplePane {
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
            onShareInvite: inviteDialog.open()
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
    function closeMenusForTest() { viewMenu.close() }
    /// For the --join-view harness: open the View menu (and a submenu row).
    function viewMenuForTest(sub) {
        viewMenu.parent = meeting ? viewBtnM : viewBtn
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
    // Leave's options (hangup-button-more-options-menu, measured): a 171.3
    // wide surface right-aligned to the chevron, 6 below it, padding 16;
    // 138 x 32 items, 14 px #424242, 2 apart. End meeting is the
    // organizer's, after Teams' confirmation.
    Popup {
        id: leaveMenu
        parent: leaveButton
        x: leaveButton.width - width; y: 60
        width: 171.3; padding: 16
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: win.organizer ? [{ k: "leave", t: "Leave" }, { k: "end", t: "End meeting" }] : [{ k: "leave", t: "Leave" }]
                Rectangle {
                    required property var modelData
                    width: 138; height: 32; radius: 4
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
    // Teams' Mute all confirmation ("All" scope).
    ConfirmDialog {
        id: muteAllAsk
        title: "Mute everyone?"
        body: "This will mute everyone in the meeting but you."
        confirmText: "Mute"
        onConfirmed: win.muteAll()
    }
    InviteDialog { id: inviteDialog; link: win.inviteUrl }

    // Mic ▾: Teams' audio options, right-aligned to the chevron at the
    // bar's bottom edge, at most 5 px short of the window's bottom.
    AudioFlyout {
        id: audioFlyout
        muted: win.muted || !win.hasAudio
        onToggleMute: win.toggleMute()
        x: parent ? parent.width - width : 0
        y: 60
        maxHeight: win.height - 60 - 5
    }
    function openAudioOptions(button) { audioFlyout.parent = button; audioFlyout.open() }

    // React (reaction-menu-button-toolbox, measured on winpc): a 249.3 x
    // 73.3 surface under the React button, padding 16, five 32 px buttons
    // 12 apart holding Teams' 24 px reaction pictures.
    Popup {
        id: reactMenu
        parent: reactButton
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
    // More: settings and window actions.
    MenuPopup {
        id: moreMenu
        x: parent ? parent.width - width : 0; y: parent ? parent.height + 4 : 0
        width: 240
        items: [
            { label: "Device settings", icon: "settings-20" },
            { label: win.visibility === Window.FullScreen ? "Exit full screen" : "Full screen", icon: "full-screen-maximize-20" }
        ]
        onPicked: i => i === 0 ? win.deviceSettings() : win.toggleFullScreen()
    }
    // Dial pad: Teams' keypad under the button; keys send tones.
    Popup {
        id: dialPad
        parent: padBtn
        x: (padBtn.width - width) / 2; y: padBtn.height + 4
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
    function audioOptionsForTest() { openAudioOptions(micButtonM) }
    function inviteForTest() { side = "people"; inviteDialog.open() }
    function closeDialPadForTest() { dialPad.close() }
    function pressForTest(keys) { for (const k of keys) dialPad.press(k) }

    // Teams' call toolbar button (ubar, measured on winpc): a 56 px slot
    // holding a 48 x 48 button 6 px from the top; a 25 px glyph at
    // (11.5, 3.5) over an 11 px label; #424242 at rest (#242424 for the
    // media buttons), #EBEBEB behind and #242424 on hover; a 2 px brand
    // line under it while its pane is open.
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
        signal clicked()
        signal chevronClicked()
        width: split ? 74 : 56; height: 60
        Rectangle {
            visible: bb.split
            x: 52; y: 6; width: 22; height: 48
            topRightRadius: 4; bottomRightRadius: 4
            color: (chevHover.hovered || bb.chevronChecked) ? theme.rowHover : "transparent"
            FluentIcon { x: 3; y: 16; name: "call-chevron"; size: 16; color: theme.text }
            HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: bb.chevronClicked() }
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
