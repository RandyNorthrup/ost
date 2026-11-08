import QtQuick
import QtQuick.Effects

// Teams' "Connected to a room device" notification (ufd_byod…, measured on
// winpc): shown at the top of the stage while Optimize for room is on, until
// dismissed. 320 x 89.3 on #FAFAFA with a 0.67 #F0F0F0 edge and radius 8;
// the display glyph (16) and a 12 px title at 12/36, dismiss at 290.7;
// the explanation 14/20 #616161 at 12.7, 41.3, 296.7 wide.
Item {
    id: root
    signal dismissed()
    width: 320; height: 89.3
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: Qt.rgba(0, 0, 0, 0.11) }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: Qt.rgba(0, 0, 0, 0.13) }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 8
        color: theme.quoteFill
        border.color: theme.quoteBorder; border.width: 0.67
    }
    FluentIcon { x: 12; y: 12; name: "room-display-16"; size: 16; color: theme.text }
    Text {
        x: 36; y: 12; height: 20; verticalAlignment: Text.AlignVCenter
        text: "Connected to a room device"
        font.family: theme.font; font.pixelSize: 12
        color: theme.text
    }
    Item {
        x: 290.7; y: 14; width: 16; height: 16
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textSecondary }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss"
    }
    Text {
        x: 12.7; y: 41.3; width: 296.7
        wrapMode: Text.WordWrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: "Your gallery appears on the display. Controls and private data stay on this device."
        font.family: theme.font; font.pixelSize: 14
        color: theme.textSecondary
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: "Connected to a room device"
}
