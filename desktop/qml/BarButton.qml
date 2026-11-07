import QtQuick
import QtQuick.Controls.Basic

// A hover-bar action: Fluent's transparent button, 32 wide; #424242 at
// rest, brand with the filled glyph on hover.
Item {
    id: bb
    property string icon
    property string tip
    property bool pressed: false
    signal clicked()
    width: 32; height: 31
    FluentIcon { x: 6; y: 6; size: 20; name: bbHover.hovered ? bb.icon + "-filled" : bb.icon; color: bbHover.hovered ? theme.brand : theme.textStrong }
    PressedLine { visible: bb.pressed }
    HoverHandler { id: bbHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: bb.clicked() }
    ToolTip {
        visible: bbHover.hovered; delay: 500
        y: -height - 4; padding: 8
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Text { text: bb.tip; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
    }
    Accessible.role: Accessible.Button
    Accessible.name: tip
}
