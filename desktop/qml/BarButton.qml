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
    /// Fluent's keyboard outline (strokeFocus2, 2 px). It only gets the
    /// focus from the keyboard (a menu it opened gives it back on Esc, as
    /// Teams' ··· More options), so by default whenever it has it.
    property bool focusRingShown: activeFocus
    width: 32; height: 31
    FluentIcon { x: 6; y: 6; size: 20; name: bbHover.hovered ? bb.icon + "-filled" : bb.icon; color: bbHover.hovered ? theme.brand : theme.textStrong }
    PressedLine { visible: bb.pressed }
    Rectangle {
        visible: bb.focusRingShown
        anchors.fill: parent; radius: 4; color: "transparent"
        border.width: 2; border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
    }
    HoverHandler { id: bbHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: bb.clicked() }
    // Focused: Enter / Space press it (its menu opens again).
    Keys.onPressed: e => {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { e.accepted = true; bb.clicked() }
    }
    // Teams shows the tooltip on keyboard focus too ("More options" after
    // its menu's Esc).
    ToolTip {
        visible: bbHover.hovered || bb.focusRingShown; delay: 500
        y: -height - 4; padding: 8
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Text { text: bb.tip; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
    }
    Accessible.role: Accessible.Button
    Accessible.name: tip
}
