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
          .concat(others.map(p => ({ name: p.name, id: p.id, you: false, mutedNow: p.server_muted, role: p.role, hand: !!p.hand })))
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
        // Meetings: Teams' shield (meeting info) beside the timer.
        FluentIcon {
            visible: win.meeting
            x: 16; anchors.verticalCenter: parent.verticalCenter
            name: "shield-24"; size: 20; color: theme.textStrong
        }
        Text {
            x: win.meeting ? 48 : 16; anchors.verticalCenter: parent.verticalCenter
            text: win.state === "connected" ? win.clock(win.seconds) : "--:--"
            color: theme.text
            font.family: theme.font; font.pixelSize: 14
        }
        // A meeting's controls, as Teams desktop lays them out. Those OST
        // can't do yet are shown disabled.
        Row {
            visible: win.meeting
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 0
            BarButton {
                icon: "chat-24"; label: "Chat"; checked: win.side === "chat"
                onClicked: { win.side = win.side === "chat" ? "" : "chat"; if (win.side === "chat") win.openChat() }
            }
            BarButton {
                icon: "people"; label: "People"; checked: win.side === "people"
                // Teams: raised hands as a red count, else how many are here.
                badge: win.hands.length > 0 ? win.hands.length : win.roster.length > 1 ? win.roster.length : 0
                badgeAlert: win.hands.length > 0
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton {
                icon: "hand-left-24"; label: win.handRaised ? "Lower" : "Raise"
                enabled: win.live
                checked: win.handRaised
                onClicked: win.toggleHand()
            }
            BarButton { icon: "emoji-24"; label: "React"; enabled: false }
            BarButton { id: viewBtnM; icon: "grid"; label: "View"; checked: viewMenu.visible && viewMenu.parent === viewBtnM; onClicked: { viewMenu.parent = viewBtnM; viewMenu.open() } }
            // Controls: the meeting options (organizers), as Teams opens them.
            BarButton { visible: win.organizer; icon: "shield-task-24"; label: "Controls"; enabled: win.optionsUrl.length > 0; onClicked: Qt.openUrlExternally(win.optionsUrl) }
            // Notes: Teams keeps meeting notes in the meeting chat's Notes tab.
            BarButton { icon: "notepad-24"; label: "Notes"; enabled: win.chatUrl.length > 0; onClicked: Qt.openUrlExternally(win.chatUrl) }
            BarButton { visible: win.organizer; icon: "conference-room-24"; label: "Rooms"; enabled: false }
            BarButton { id: appsBtnM; icon: "apps-add"; label: "Apps"; checked: appsMenu.visible && appsMenu.parent === appsBtnM; onClicked: { appsMenu.parent = appsBtnM; appsMenu.open() } }
            BarButton { id: moreBtnM; icon: "more-24"; label: "More"; checked: moreMenu.visible && moreMenu.parent === moreBtnM; onClicked: { moreMenu.parent = moreBtnM; moreMenu.open() } }
            Divider {}
            BarButton {
                icon: win.cameraOn ? "video" : "video-off"; label: "Camera"
                enabled: win.canVideo
                checked: win.cameraOn
                onClicked: win.toggleCamera()
            }
            BarButton {
                icon: win.muted ? "mic-off-24" : "mic-24"; label: "Mic"
                enabled: win.hasAudio
                checked: !win.muted
                onClicked: win.toggleMute()
            }
            BarButton {
                icon: win.sharing ? "share-screen-stop" : "share-screen"
                label: win.sharing ? "Stop sharing" : "Share"
                iconColor: win.sharing ? theme.leave : theme.text
                enabled: win.canShare || win.sharing
                onClicked: win.toggleShare()
            }
            Divider {}
            BarButton {
                icon: "call-end-24"; label: "Leave"
                iconColor: theme.leave
                onClicked: win.leave()
            }
        }
        Row {
            visible: !win.meeting
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
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
                icon: "chat-24"; label: "Chat"; checked: win.side === "chat"
                onClicked: { win.side = win.side === "chat" ? "" : "chat"; if (win.side === "chat") win.openChat() }
            }
            BarButton {
                icon: "people"; label: "People"; checked: win.side === "people"
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton { id: viewBtn; icon: "grid"; label: "View"; checked: viewMenu.visible && viewMenu.parent === viewBtn; onClicked: { viewMenu.parent = viewBtn; viewMenu.open() } }
            BarButton { id: appsBtn; icon: "apps-add"; label: "Apps"; checked: appsMenu.visible && appsMenu.parent === appsBtn; onClicked: { appsMenu.parent = appsBtn; appsMenu.open() } }
            BarButton { id: moreBtn; icon: "more-24"; label: "More"; checked: moreMenu.visible && moreMenu.parent === moreBtn; onClicked: { moreMenu.parent = moreBtn; moreMenu.open() } }
            Divider {}
            BarButton {
                icon: win.cameraOn ? "video" : "video-off"; label: "Camera"
                enabled: win.canVideo && !win.held
                checked: win.cameraOn
                onClicked: win.toggleCamera()
            }
            BarButton {
                icon: win.muted ? "mic-off-24" : "mic-24"; label: "Mic"
                enabled: win.hasAudio && !win.held
                checked: !win.muted
                onClicked: win.toggleMute()
            }
            BarButton {
                icon: win.sharing ? "share-screen-stop" : "share-screen"
                label: win.sharing ? "Stop sharing" : "Share"
                iconColor: win.sharing ? theme.leave : theme.text
                enabled: win.canShare || win.sharing
                onClicked: win.toggleShare()
            }
            Divider {}
            BarButton {
                icon: "call-end-24"; label: "Leave"
                iconColor: theme.leave
                onClicked: win.leave()
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
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
        Grid {
            id: tiles
            visible: win.meeting && win.others.length > 0
            anchors { fill: parent; margins: 8; bottomMargin: strip.visible ? strip.height + 16 : 8 }
            // Speaker: one large tile (the others in a strip below).
            readonly property var shown: win.layout === "speaker" ? win.others.slice(0, 1) : win.others
            columns: Math.max(1, Math.ceil(Math.sqrt(shown.length)))
            readonly property int rowsN: Math.max(1, Math.ceil(shown.length / columns))
            spacing: 8
            Repeater {
                model: win.meeting ? tiles.shown : []
                Rectangle {
                    required property var modelData
                    width: (tiles.width - (tiles.columns - 1) * tiles.spacing) / tiles.columns
                    height: (tiles.height - (tiles.rowsN - 1) * tiles.spacing) / tiles.rowsN
                    radius: 6
                    color: "#FFFFFF"; opacity: 0.9
                    // A raised hand: Teams' gold outline and "1 ✋" badge.
                    readonly property int handAt: win.hands.indexOf(modelData.id)
                    border.color: handAt >= 0 ? theme.handRaised : theme.dividerSoft
                    border.width: handAt >= 0 ? 3 : 1
                    Avatar { anchors.centerIn: parent; size: Math.min(144, parent.height * 0.45); name: parent.modelData.name; photoId: parent.modelData.id }
                    Rectangle {
                        visible: parent.handAt >= 0
                        anchors { left: parent.left; top: parent.top; margins: 10 }
                        width: handRow.implicitWidth + 12; height: 28; radius: 14
                        color: "white"; border.color: theme.dividerSoft
                        Row {
                            id: handRow
                            anchors.centerIn: parent; spacing: 4
                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.parent.handAt + 1; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u270B"; font.pixelSize: 16 }
                        }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Hand raised"
                    }
                    Rectangle {
                        anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                        width: tileName.implicitWidth + 12; height: 24; radius: 4
                        color: "#99000000"
                        Text { id: tileName; anchors.centerIn: parent; text: parent.parent.modelData.name; color: "white"; font.family: theme.font; font.pixelSize: theme.small }
                    }
                    Accessible.role: Accessible.Grouping
                    Accessible.name: modelData.name
                }
            }
        }
        Row {
            id: strip
            visible: win.meeting && win.layout === "speaker" && win.others.length > 1
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
            height: 96; spacing: 8
            Repeater {
                model: strip.visible ? win.others.slice(1) : []
                Rectangle {
                    required property var modelData
                    width: 160; height: 96; radius: 6
                    color: "#FFFFFF"; border.color: theme.dividerSoft
                    Avatar { anchors.centerIn: parent; size: 48; name: parent.modelData.name; photoId: parent.modelData.id }
                    Text { x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; width: parent.width - 12; elide: Text.ElideRight; text: parent.modelData.name; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    Accessible.role: Accessible.Grouping
                    Accessible.name: modelData.name
                }
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
        // Your own tile, bottom right (in a meeting, once others are there)
        Rectangle {
            visible: !win.meeting || win.others.length > 0
            z: 2
            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
            width: 240; height: 134; radius: 6
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#F6EEF2" }
                GradientStop { position: 1.0; color: "#EEF0F8" }
            }
            border.color: theme.dividerSoft
            Avatar { visible: !selfVideo.visible; anchors.centerIn: parent; size: 64; name: win.selfName || "You"; photoId: "me" }
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
        anchors { top: bar.bottom; right: parent.right; bottom: parent.bottom; margins: 6 }
        width: 320; radius: 6
        color: theme.surface
        border.color: theme.dividerSoft
        clip: true
        Conversation {
            id: chatPane
            visible: win.side === "chat"
            anchors.fill: parent; anchors.margins: 1
            pane: true
            onClosePane: win.side = ""
        }
        Item {
            visible: win.side === "people"
            anchors.fill: parent
            Text {
                x: 16; y: 18
                text: "Participants"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                color: theme.text
            }
            Rectangle {
                x: parent.width - 44; y: 12; width: 32; height: 32; radius: theme.radius
                color: pch.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: pch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.side = "" }
                Accessible.role: Accessible.Button
                Accessible.name: "Close participants"
            }
            Text {
                x: 16; y: 64
                text: (win.meeting ? "In this meeting (" : "In this call (") + win.people.length + ")"
                font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                color: theme.textSecondary
            }
            Column {
                x: 8; y: 88; width: parent.width - 16
                Repeater {
                    model: win.people
                    Item {
                        required property var modelData
                        width: parent.width; height: 48
                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 32; name: modelData.name; photoId: modelData.id }
                        Column {
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 96
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: modelData.name + (modelData.you ? " (You)" : "")
                                font.family: theme.font; font.pixelSize: theme.base
                                color: theme.text
                            }
                            Text {
                                visible: !!modelData.role
                                text: (modelData.role || "").charAt(0).toUpperCase() + (modelData.role || "").slice(1)
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.textSecondary
                            }
                        }
                        Text {
                            visible: !!modelData.hand
                            anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter
                            text: "\u270B"; font.pixelSize: 16
                        }
                        FluentIcon {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            name: modelData.mutedNow ? "mic-off-24" : "mic-24"; size: 20
                            color: theme.textStrong
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + (modelData.hand ? ", hand raised" : "") + (modelData.mutedNow ? ", muted" : "")
                    }
                }
            }
        }
    }

    component Divider: Rectangle {
        width: 17; height: 32
        color: "transparent"
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle { anchors.centerIn: parent; width: 1; height: 32; color: theme.divider }
    }

    // View: Teams' layout menu.
    MenuPopup {
        id: viewMenu
        x: parent ? parent.width - width : 0; y: parent ? parent.height + 4 : 0
        width: 240
        items: (win.meeting ? [
            { label: "Gallery", icon: "gallery-20", checked: win.layout === "gallery" },
            { label: "Speaker", icon: "speaker-view-20", checked: win.layout === "speaker" },
            { separator: true }] : [])
            .concat([
            { label: win.visibility === Window.FullScreen ? "Exit full screen" : "Full screen", icon: "full-screen-maximize-20" },
            { label: win.incomingVideoOff ? "Turn on incoming video" : "Turn off incoming video", icon: "video-off-20" }])
        onPicked: i => {
            const l = items[i].label
            if (l === "Gallery") win.layout = "gallery"
            else if (l === "Speaker") win.layout = "speaker"
            else if (l.indexOf("full screen") >= 0 || l === "Full screen") win.toggleFullScreen()
            else win.incomingVideoOff = !win.incomingVideoOff
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
    function closeDialPadForTest() { dialPad.close() }
    function pressForTest(keys) { for (const k of keys) dialPad.press(k) }

    component BarButton: Rectangle {
        id: bb
        property string icon
        property string label
        property bool checked: false
        property color iconColor: theme.text
        /// A count beside the icon (People: how many are in the meeting).
        property int badge: 0
        /// Show the count as Teams' red alert badge (raised hands).
        property bool badgeAlert: false
        signal clicked()
        width: Math.max(56, bbLabel.implicitWidth + 12); height: 52; radius: theme.radius
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: bb.checked ? theme.pane : (bbHover.hovered && bb.enabled ? theme.pane : "transparent")
        Column {
            anchors.centerIn: parent; spacing: 3
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon {
                name: bb.icon; size: 20; color: bb.iconColor; anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    visible: bb.badge > 0
                    x: bb.badgeAlert ? parent.width - 6 : parent.width + 2; y: bb.badgeAlert ? -6 : -2
                    width: Math.max(16, bbText.implicitWidth + (bb.badgeAlert ? 8 : 0)); height: 16; radius: 8
                    color: bb.badgeAlert ? theme.danger : "transparent"
                    Text {
                        id: bbText
                        anchors.centerIn: parent
                        text: bb.badge
                        font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                        color: bb.badgeAlert ? "white" : theme.text
                    }
                }
            }
            Text {
                id: bbLabel
                text: bb.label
                color: theme.text
                font.family: theme.font; font.pixelSize: theme.small
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
        HoverHandler { id: bbHover; cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (bb.enabled) bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: bb.label
    }
}
