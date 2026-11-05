import QtQuick
import QtQuick.Window

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
    /// A Teams meeting: Teams' meeting toolbar, the roster and its stage.
    property bool meeting: false
    /// The meeting's participants (from the roster): [{id, name, role}].
    property var roster: []
    /// Your own MRI, to tell you apart in the roster.
    property string selfId: ""
    readonly property var others: roster.filter(p => p.id !== selfId)
    // People pane rows: you first, then everyone else.
    readonly property var people: meeting
        ? [{ name: selfName || "You", id: "me", you: true, mutedNow: muted || !hasAudio,
             role: (roster.find(p => p.id === selfId) || {}).role || "" }]
          .concat(others.map(p => ({ name: p.name, id: p.id, you: false, mutedNow: p.server_muted, role: p.role })))
        : [{ name: selfName || "You", id: "me", you: true, mutedNow: muted || !hasAudio },
           { name: peer, id: backend.callPeerId, you: false, mutedNow: false }]
    /// The open side pane: "", "chat" or "people".
    property string side: ""
    signal openChat()

    width: 1024; height: 640
    minimumWidth: 720; minimumHeight: 420
    color: theme.surface
    title: peer + " | OST"

    property int seconds: 0
    Timer {
        interval: 1000; repeat: true
        running: win.visible && win.state === "connected"
        onTriggered: win.seconds = Math.floor((Date.now() - win.connectedAt) / 1000)
    }
    onStateChanged: if (state === "connected") { connectedAt = Date.now(); seconds = 0 }

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
                badge: win.roster.length > 1 ? win.roster.length : 0
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton { icon: "hand-left-24"; label: "Raise"; enabled: false }
            BarButton { icon: "emoji-24"; label: "React"; enabled: false }
            BarButton { icon: "grid"; label: "View"; enabled: false }
            BarButton { icon: "shield-task-24"; label: "Controls"; enabled: false }
            BarButton { icon: "notepad-24"; label: "Notes"; enabled: false }
            BarButton { icon: "conference-room-24"; label: "Rooms"; enabled: false }
            BarButton { icon: "apps-add"; label: "Apps"; enabled: false }
            BarButton { icon: "more-24"; label: "More"; enabled: false }
            Divider {}
            BarButton { icon: "video-off"; label: "Camera"; enabled: false }
            BarButton {
                icon: win.muted ? "mic-off-24" : "mic-24"; label: "Mic"
                enabled: win.hasAudio
                checked: !win.muted
                onClicked: win.toggleMute()
            }
            BarButton { icon: "share-screen"; label: "Share"; enabled: false }
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
            BarButton { icon: "call-transfer"; label: "Transfer"; enabled: false }
            BarButton { icon: "consult"; label: "Consult"; enabled: false }
            Divider {}
            BarButton { icon: "dialpad"; label: "Dial pad"; enabled: false }
            BarButton { icon: "pause"; label: "Hold"; enabled: false }
            Divider {}
            BarButton {
                icon: "chat-24"; label: "Chat"; checked: win.side === "chat"
                onClicked: { win.side = win.side === "chat" ? "" : "chat"; if (win.side === "chat") win.openChat() }
            }
            BarButton {
                icon: "people"; label: "People"; checked: win.side === "people"
                onClicked: win.side = win.side === "people" ? "" : "people"
            }
            BarButton { icon: "grid"; label: "View"; enabled: false }
            BarButton { icon: "apps-add"; label: "Apps"; enabled: false }
            BarButton { icon: "more-24"; label: "More"; enabled: false }
            Divider {}
            BarButton { icon: "video-off"; label: "Camera"; enabled: false }
            BarButton {
                icon: win.muted ? "mic-off-24" : "mic-24"; label: "Mic"
                enabled: win.hasAudio
                checked: !win.muted
                onClicked: win.toggleMute()
            }
            BarButton { icon: "share-screen"; label: "Share"; enabled: false }
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
            anchors.fill: parent; anchors.margins: 8
            columns: Math.ceil(Math.sqrt(win.others.length))
            readonly property int rowsN: Math.ceil(win.others.length / columns)
            spacing: 8
            Repeater {
                model: win.meeting ? win.others : []
                Rectangle {
                    required property var modelData
                    width: (tiles.width - (tiles.columns - 1) * tiles.spacing) / tiles.columns
                    height: (tiles.height - (tiles.rowsN - 1) * tiles.spacing) / tiles.rowsN
                    radius: 6
                    color: "#FFFFFF"; opacity: 0.9
                    border.color: theme.dividerSoft
                    Avatar { anchors.centerIn: parent; size: Math.min(144, parent.height * 0.45); name: parent.modelData.name; photoId: parent.modelData.id }
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
        Column {
            visible: !win.meeting
            anchors.centerIn: parent
            spacing: 24
            Avatar { size: 144; name: win.peer; photoId: backend.callPeerId; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.state === "calling" ? "Calling…"
                    : win.state === "connecting" ? "Connecting…"
                    : win.state === "ended" ? "Call ended"
                    : !win.hasAudio ? "Connected without audio" : ""
                visible: text.length > 0
                color: theme.text
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
        }
        // Their name chip, bottom left
        Rectangle {
            visible: !win.meeting
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
            Avatar { anchors.centerIn: parent; size: 64; name: win.selfName || "You"; photoId: "me" }
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
                        FluentIcon {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            name: modelData.mutedNow ? "mic-off-24" : "mic-24"; size: 20
                            color: theme.textStrong
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + (modelData.mutedNow ? ", muted" : "")
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

    component BarButton: Rectangle {
        id: bb
        property string icon
        property string label
        property bool checked: false
        property color iconColor: theme.text
        /// A count beside the icon (People: how many are in the meeting).
        property int badge: 0
        signal clicked()
        width: 56; height: 52; radius: theme.radius
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: bb.checked ? theme.pane : (bbHover.hovered && bb.enabled ? theme.pane : "transparent")
        Column {
            anchors.centerIn: parent; spacing: 3
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon {
                name: bb.icon; size: 20; color: bb.iconColor; anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    visible: bb.badge > 0
                    x: parent.width + 2; y: -2
                    text: bb.badge
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                    color: theme.text
                }
            }
            Text {
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
