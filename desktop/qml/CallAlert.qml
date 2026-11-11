import QtQuick
import QtQuick.Effects

// Teams' in-call alerts (calling-alerts; seen on winpc 2026-11-11 in a
// breakout rooms meeting): a 320 wide white card at the top of the stage
// with radius 8, the alert's text (14/20, wrapping) and Dismiss at the
// right; some lead with a 20 px glyph ("Breakout rooms have been
// created." with the rooms glyph). "We'll move you to your assigned room
// in 10 seconds." wraps to two lines.
Item {
    id: root
    property string icon: ""
    property string text
    signal dismissed()
    width: 320
    height: Math.max(41.33, body.height + 21.33)
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: theme.shadowAmbient }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: theme.shadowKey }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 8
        color: theme.surface
    }
    FluentIcon {
        visible: root.icon.length > 0
        x: 14.67; y: 10.67; size: 20
        name: root.icon
        color: theme.textStrong
    }
    Text {
        id: body
        x: root.icon.length > 0 ? 44 : 12.67; y: 10.67
        width: root.width - x - 44
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.text
        font.family: theme.font; font.pixelSize: 14
        color: root.icon.length > 0 ? theme.textSecondary : theme.text
    }
    Rectangle {
        x: root.width - 36; y: 6.67; width: 28; height: 28; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textSecondary }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss"
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.text
}
