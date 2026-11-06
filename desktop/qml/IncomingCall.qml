import QtQuick
import QtQuick.Window

// The incoming-call toast, as Teams desktop shows it (measured at 1x): a
// 360 x 240 card in the screen's corner over a dark, blurred image of the
// caller, with their picture, "<name> is calling you", and wide Accept
// (with video, when offered) and Decline buttons. The close button
// ignores the call: the ringing stops here but the call isn't declined.
Window {
    id: toast
    property string peer
    property bool videoOffered
    property bool ignored: false
    signal acceptVideo()
    signal acceptAudio()
    signal decline()
    signal ignore()

    width: 360; height: 240
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: peer + " is calling you | OST"
    x: Screen.desktopAvailableWidth - width - 16
    y: Screen.desktopAvailableHeight - height - 16
    onVisibleChanged: if (visible) ignored = false

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 8
        color: "#34353A"
        clip: true
        // The caller's picture, blurred: decoded at 6 x 6 and scaled up
        // smoothly (no shaders, so it looks the same everywhere).
        Image {
            anchors.fill: parent
            source: avatar.photo
            sourceSize: Qt.size(6, 6)
            smooth: true
            fillMode: Image.PreserveAspectCrop
            opacity: 0.55
        }
        Rectangle { anchors.fill: parent; radius: 8; color: "#000000"; opacity: 0.35 }
        RoundedCorners { anchors.fill: parent; radius: 8; background: "transparent" }

        // Header: the app, and close (ignore).
        Image {
            x: 16; y: 14; width: 20; height: 20
            source: "../assets/logo.png"
            sourceSize: Qt.size(40, 40)
            smooth: true
            fillMode: Image.PreserveAspectFit
        }
        Text {
            x: 44; y: 14; height: 20
            verticalAlignment: Text.AlignVCenter
            text: "OST"
            font.family: theme.font; font.pixelSize: theme.base
            color: "white"
        }
        Rectangle {
            x: parent.width - 40; y: 10; width: 28; height: 28; radius: theme.radius
            color: ch.hovered ? "#3DFFFFFF" : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 16; color: "white" }
            HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { toast.ignored = true; toast.ignore() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Ignore"
        }

        Avatar {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter; y: 50
            size: 80; name: toast.peer; photoId: backend.callPeerId
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; y: 140
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, card.width - 32); elide: Text.ElideRight
                text: toast.peer
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: toast.videoOffered ? "is video calling you" : "is calling you"
                font.family: theme.font; font.pixelSize: theme.base
                color: "white"
            }
        }

        // Accept (video when offered, audio) and Decline.
        Row {
            x: 16; y: 192
            spacing: 10
            readonly property int count: toast.videoOffered ? 3 : 2
            readonly property real bw: (card.width - 32 - spacing * (count - 1)) / count
            Wide {
                visible: toast.videoOffered
                width: parent.bw; icon: "video-filled"; fill: theme.brandFill; fillHover: theme.brandHover
                tip: "Accept with video"
                onClicked: toast.acceptVideo()
            }
            Wide {
                width: parent.bw; icon: "call-filled-24"; fill: theme.brandFill; fillHover: theme.brandHover
                tip: "Accept with audio"
                onClicked: toast.acceptAudio()
            }
            Wide {
                width: parent.bw; icon: "call-end-filled"; fill: "#D13438"; fillHover: "#BC2F32"
                tip: "Decline"
                onClicked: toast.decline()
            }
        }
    }

    component Wide: Rectangle {
        id: wb
        property string icon
        property color fill
        property color fillHover
        property string tip
        signal clicked()
        height: 32; radius: theme.radius
        color: hov.hovered ? fillHover : fill
        FluentIcon { anchors.centerIn: parent; name: wb.icon; size: 20; color: "white" }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: wb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: wb.tip
    }
}
