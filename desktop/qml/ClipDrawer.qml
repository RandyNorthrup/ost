import QtQuick
import QtQuick.Controls.Basic

// A drawer of the clip recorder's effects (Stream's .fgr-drawer, measured
// on winpc 2026-11-20): white at 95 %, rounded 8, a 0.67 hairline, padded
// 8 16 20, centred over the 800-wide recorder; its bottom is the drawer
// area's (y 507.5) plus a quarter of its own height, as Stream places it
// in small windows (the tall ones run past the dialog's foot, clipped).
// A 40 px header 6 px from the top and content: the title (20/600)
// centred, Close (32 x 40) at the right, an optional Back at the left.
Item {
    id: dr
    property string title
    property real drawerWidth: 608
    property bool showBack: false
    default property alias content: body.data
    signal closed()
    signal back()

    width: drawerWidth
    height: 8 + 6 + 40 + 6 + body.childrenRect.height + 20 + 1.33
    x: (800 - width) / 2
    y: 507.5 + height * 0.25 - height
    // Stream's 0.3 s cubic-bezier(.16, 1, .3, 1) slide and fade in.
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

    FluentSurface {
        anchors.fill: parent
        depth: 16; radius: 8
        color: theme.pick(Qt.rgba(1, 1, 1, 0.95), Qt.rgba(0.16, 0.16, 0.16, 0.95), "#000000")
        borderColor: theme.hc(Qt.rgba(1, 1, 1, 0.1), "#FFFFFF")
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }
    Item {
        id: header
        x: 16.67; y: 14.67; width: parent.width - 33.33; height: 40
        Text {
            anchors.centerIn: parent
            text: dr.title
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        DrawerButton { visible: dr.showBack; x: 0; icon: "arrow-left-20"; label: qsTr("Back"); onClicked: dr.back() }
        DrawerButton { x: parent.width - 32; icon: "dismiss-20"; label: qsTr("Close") + " " + dr.title; onClicked: dr.closed() }
    }
    Item {
        id: body
        x: 16.67; y: header.y + header.height + 6
        width: parent.width - 33.33
        height: childrenRect.height
    }
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Video editing tools: %1 menu").arg(dr.title)

    component DrawerButton: Rectangle {
        id: b
        property string icon
        property string label
        signal clicked()
        width: 32; height: 40; radius: 4
        color: bHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: b.icon; size: 20; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
        HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: b.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: b.label
    }
}
