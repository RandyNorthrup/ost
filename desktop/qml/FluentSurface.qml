import QtQuick
import QtQuick.Effects

// A Fluent surface with its two-layer shadow, as the Teams client's CSS
// draws it: `depth` 16 for menus (0 0 2px + 0 8px 16px), 64 for dialogs
// (0 0 8px + 0 32px 64px), 2 for cards (0 0 2px + 0 1px 2px); 0 for none.
Item {
    id: root
    property int depth: 16
    property real radius: 4
    property color color: theme.menu
    // Fluent's TransparentStroke: white in High contrast.
    property color borderColor: theme.transparentStroke
    readonly property real ambientBlur: depth === 64 ? 8 : 2
    RectangularShadow {
        visible: root.depth > 0
        anchors.fill: parent
        radius: root.radius
        blur: root.ambientBlur
        color: theme.shadowAmbient
    }
    RectangularShadow {
        visible: root.depth > 0
        anchors.fill: parent
        offset.y: root.depth / 2
        radius: root.radius
        blur: root.depth
        color: theme.shadowKey
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.color: root.borderColor
        border.width: root.borderColor.a > 0 ? 1 : 0
    }
}
