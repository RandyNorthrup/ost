import QtQuick
import QtQuick.Window

// The incoming-call toast: a small dark window with the caller and
// Accept with video / Accept with audio / Decline, as in Teams.
Window {
    id: toast
    property string peer
    property bool videoOffered
    signal acceptVideo()
    signal acceptAudio()
    signal decline()

    width: 360; height: 96
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: peer + " is calling | OST"
    x: Screen.desktopAvailableWidth - width - 16
    y: Screen.desktopAvailableHeight - height - 16

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: theme.stageBar
        border.color: "#3D3D3D"

        Avatar {
            id: avatar
            x: 16; anchors.verticalCenter: parent.verticalCenter
            size: 48; name: toast.peer; photoId: backend.callPeerId
        }
        Column {
            anchors { left: avatar.right; leftMargin: 12; right: buttons.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: toast.peer
                color: theme.stageText
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                text: toast.videoOffered ? "Incoming video call" : "Incoming call"
                color: theme.stageTextSecondary
                font.family: theme.font; font.pixelSize: theme.small
            }
        }
        Row {
            id: buttons
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 8
            RoundButton {
                icon: "video-filled"; fill: theme.accept; fillHover: theme.acceptHover
                tip: "Accept with video"
                onClicked: toast.acceptVideo()
            }
            RoundButton {
                icon: "call-filled-24"; fill: theme.accept; fillHover: theme.acceptHover
                tip: "Accept with audio"
                onClicked: toast.acceptAudio()
            }
            RoundButton {
                icon: "call-end-filled"; fill: theme.leave; fillHover: theme.leaveHover
                tip: "Decline"
                onClicked: toast.decline()
            }
        }
    }

    component RoundButton: Rectangle {
        id: rb
        property string icon
        property color fill
        property color fillHover
        property string tip
        signal clicked()
        width: 40; height: 40; radius: 20
        color: hov.hovered ? fillHover : fill
        FluentIcon { anchors.centerIn: parent; name: rb.icon; size: 20; color: "white" }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: rb.tip
    }
}
