import QtQuick
import QtQuick.Controls.Basic

// Teams' bar under a bot's card after one of its actions (measured on winpc
// 2026-11-13, OST TEST 126's "Submit Vote"): 28 tall plus a 0.67 #E0E0E0
// line on top, #E6E6E6 (NeutralBackground6), the card's bottom corners;
// a 20 px info icon at 16, the text (14 px #424242) at 41.33 and a 20 px
// dismiss 8 from the right. "Your response was sent to the app" when the
// bot answers with nothing, else its message or error. While the action
// runs, a small spinner stands where the icon goes.
Item {
    id: root
    property string text: ""
    property bool busy: false
    property bool error: false
    signal dismissed()
    height: 28.67
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 0.67
        color: theme.pick("#E6E6E6", "#2E2E2E")
        bottomLeftRadius: 6; bottomRightRadius: 6
    }
    Rectangle { width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
    BusyIndicator {
        visible: root.busy
        running: root.busy
        x: 14; y: 0.67 + 4; width: 20; height: 20
    }
    FluentIcon {
        visible: !root.busy
        x: 16; y: 0.67 + 4; size: 20
        name: root.error ? "error-circle-20-filled" : "info-20"
        color: root.error ? theme.redForeground1 : theme.textStrong
    }
    Text {
        x: 41.33; y: 0.67; height: 28
        width: parent.width - x - 36
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.text
        font.family: theme.font; font.pixelSize: 14
        color: theme.textStrong
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
    Rectangle {
        visible: !root.busy
        anchors.right: parent.right; anchors.rightMargin: 8
        y: 0.67 + 4; width: 20; height: 20; radius: 4
        color: dh.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: "dismiss-20"; color: theme.textStrong }
        HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
}
