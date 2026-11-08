import QtQuick
import QtQuick.Effects

// Teams' "You've been muted" notification (ufd_MicMutedRemotely, measured
// on Teams web 2026-11-08; the same notice family as RoomNotice on winpc):
// 320 wide on NeutralBackground2 with a NeutralStroke3 edge and radius 8.
// The filled mic-off glyph (20) and a 12 px title at 12/12, dismiss (16,
// NeutralForeground3) at the right; "You have been muted." 14/20
// NeutralForeground3 at 12, 41; a full-width primary Unmute button (32
// tall, radius 4, 14/600) at 12, 73.
Item {
    id: root
    signal dismissed()
    signal unmute()
    width: 320; height: 117.3
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: Qt.rgba(0, 0, 0, 0.11) }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: Qt.rgba(0, 0, 0, 0.13) }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 8
        color: theme.quoteFill
        border.color: theme.quoteBorder; border.width: 0.67
    }
    FluentIcon { x: 12.7; y: 12.7; name: "mic-off-20-filled"; size: 20; color: theme.text }
    Text {
        x: 40.7; y: 12.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "You've been muted"
        font.family: theme.font; font.pixelSize: 12
        color: theme.text
    }
    Item {
        x: 290.7; y: 14.7; width: 16; height: 16
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textSecondary }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss"
    }
    Text {
        x: 12.7; y: 40.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "You have been muted."
        font.family: theme.font; font.pixelSize: 14
        color: theme.textSecondary
    }
    Rectangle {
        x: 12.7; y: 72.7; width: parent.width - 25.3; height: 32
        radius: 4
        color: unmuteHover.hovered ? theme.brandHover : theme.brandFill
        Text {
            anchors.centerIn: parent
            text: "Unmute"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.textOnBrand
        }
        HoverHandler { id: unmuteHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.unmute() }
        Accessible.role: Accessible.Button
        Accessible.name: "Unmute"
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: "You've been muted"
}
