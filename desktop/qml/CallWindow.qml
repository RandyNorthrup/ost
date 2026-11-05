import QtQuick
import QtQuick.Window

// A 1:1 call: dark stage with the other person's tile, and the Teams
// meeting bar (timer left; People, Raise, React, View, More, Camera, Mic,
// Share and Leave right).
Window {
    id: win
    property string peer
    property string state       // "connecting" | "connected" | "ended"
    property bool muted
    property bool hasAudio: true
    property real connectedAt: 0
    signal leave()
    signal toggleMute()

    width: 1024; height: 640
    minimumWidth: 640; minimumHeight: 400
    color: theme.stage
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

    // Meeting bar
    Rectangle {
        id: bar
        width: parent.width; height: 64
        color: theme.stageBar
        Row {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            FluentIcon { name: "people"; size: 20; color: theme.stageTextSecondary; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.state === "connected" ? win.clock(win.seconds)
                    : win.state === "ended" ? "Call ended" : "Connecting…"
                color: theme.stageText
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 4
            BarButton { icon: "people"; label: "People" }
            BarButton { icon: "hand"; label: "Raise" }
            BarButton { icon: "emoji"; label: "React" }
            BarButton { icon: "grid"; label: "View" }
            BarButton { icon: "more"; label: "More" }
            Rectangle { width: 1; height: 32; color: "#3D3D3D"; anchors.verticalCenter: parent.verticalCenter }
            BarButton { icon: "video-off"; label: "Camera" }
            BarButton {
                icon: win.muted ? "mic-off" : "mic"; label: "Mic"
                enabled: win.hasAudio
                onClicked: win.toggleMute()
            }
            BarButton { icon: "share-screen"; label: "Share" }
            Rectangle {
                id: leaveBtn
                width: 96; height: 32; radius: theme.radius
                anchors.verticalCenter: parent.verticalCenter
                color: leaveHover.hovered ? theme.leaveHover : theme.leave
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { name: "call-end-filled"; size: 20; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Leave"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.leave() }
                Accessible.role: Accessible.Button
                Accessible.name: "Leave"
            }
        }
    }

    // Stage: the other person's tile
    Rectangle {
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        radius: 8
        color: theme.stageTile
        Column {
            anchors.centerIn: parent
            spacing: 16
            Avatar { size: 96; name: win.peer; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.peer
                color: theme.stageText
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: win.state === "connected" && !win.hasAudio
                text: "Connected without audio"
                color: theme.stageTextSecondary
                font.family: theme.font; font.pixelSize: theme.small
            }
        }
        // Your own tile, bottom right
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
            width: 192; height: 108; radius: 8
            color: "#383838"
            Text {
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                text: "You"
                color: theme.stageText
                font.family: theme.font; font.pixelSize: theme.small
            }
            FluentIcon {
                visible: win.muted
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                name: "mic-off"; size: 16; color: theme.stageText
            }
        }
    }

    component BarButton: Rectangle {
        id: bb
        property string icon
        property string label
        signal clicked()
        width: 56; height: 52; radius: theme.radius
        color: bbHover.hovered && enabled ? theme.stageControlHover : "transparent"
        opacity: enabled ? 1 : 0.5
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Column {
            anchors.centerIn: parent; spacing: 2
            FluentIcon { name: bb.icon; size: 20; color: theme.stageText; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: bb.label; color: theme.stageText; font.family: theme.font; font.pixelSize: theme.caption; anchors.horizontalCenter: parent.horizontalCenter }
        }
        HoverHandler { id: bbHover }
        TapHandler { onTapped: if (bb.enabled) bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: bb.label
    }
}
