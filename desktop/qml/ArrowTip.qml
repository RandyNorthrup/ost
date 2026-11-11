import QtQuick
import QtQuick.Controls

// Fluent's tooltip with its arrow, above the item it describes (Teams'
// Meeting options lock and info buttons), measured on winpc 2026-11-11:
// white, radius 4, padding 4 11 6, text 12/16 NeutralForeground1, at most
// 240 wide, centred over the item with its bottom 10 above it (the arrow,
// a rotated 8.5 px square, in the gap).
ToolTip {
    id: tip
    property string tipText: ""
    text: tipText
    delay: 300
    x: (parent ? parent.width : 0) / 2 - width / 2
    y: -height - 10
    topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
    contentItem: Text {
        text: tip.tipText
        width: Math.min(implicitWidth, 240 - 22)
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 12
        lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    background: Item {
        FluentSurface { anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }
        Rectangle {
            width: 8.5; height: 8.5; rotation: 45
            color: theme.surface
            x: parent.width / 2 - width / 2
            y: parent.height - height / 2 - 0.5
        }
    }
}
