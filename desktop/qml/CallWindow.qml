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
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: win.state === "connected" ? win.clock(win.seconds) : "--:--"
            color: theme.text
            font.family: theme.font; font.pixelSize: 14
        }
        Row {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 0
            BarButton { icon: "call-transfer"; label: "Transfer"; enabled: false }
            BarButton { icon: "consult"; label: "Consult"; enabled: false }
            Divider {}
            BarButton { icon: "dialpad"; label: "Dial pad"; enabled: false }
            BarButton { icon: "pause"; label: "Hold"; enabled: false }
            Divider {}
            BarButton { icon: "chat-24"; label: "Chat"; enabled: false }
            BarButton { icon: "people"; label: "People"; enabled: false }
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
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
        radius: 6
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#F2F1F8" }
            GradientStop { position: 1.0; color: "#EEF6F6" }
        }
        Column {
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
        // Your own tile, bottom right
        Rectangle {
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
        signal clicked()
        width: 56; height: 52; radius: theme.radius
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: bb.checked ? theme.pane : (bbHover.hovered && bb.enabled ? theme.pane : "transparent")
        Column {
            anchors.centerIn: parent; spacing: 3
            opacity: bb.enabled ? 1 : 0.45
            FluentIcon { name: bb.icon; size: 20; color: bb.iconColor; anchors.horizontalCenter: parent.horizontalCenter }
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
