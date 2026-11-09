import QtQuick

// The title row of Teams' child windows (title-bar of the Help window and
// the captions pop-out; measured on winpc, 2026-11-09): 32 tall on the
// window chrome (#EBEBEB), a 0.67
// rgba(0,0,0,0.06) line under it; the title (12/16) 8 in, 7.67 down; at
// the right "Settings and more" (24 x 23.33, 4.42 down, radius 4) whose
// menu offers "Pin window on top" / "Unpin window" (Ctrl+Shift+T). Teams'
// menu also has Zoom (tracked with the main window's, docs/parity) and
// "Report a problem" (feedback to Microsoft, which OST doesn't send).
// `leading` holds buttons before the title (the captions' Pop in);
// `trailing` buttons go before Settings and more (the captions' pin).
Rectangle {
    id: root
    property string title: ""
    /// The window kept on top.
    property bool pinned: false
    property alias leading: lead.data
    property alias trailing: trail.data
    readonly property real leadingWidth: lead.width
    signal togglePin()
    function settingsMenuForTest() { menu.parent = more; menu.x = more.width - menu.implicitWidth; menu.y = more.height + 4; menu.open() }
    width: parent ? parent.width : 0
    height: 32
    // Teams' window chrome (#EBEBEB, measured).
    color: theme.chrome

    Row { id: lead; height: parent.height }
    Text {
        x: lead.width + 8; y: 7.67; height: 16
        width: Math.min(implicitWidth, trail.x - x - 8)
        elide: Text.ElideRight
        text: root.title
        font.family: theme.font; font.pixelSize: 12
        color: theme.text
    }
    Row {
        id: trail
        anchors.right: more.left; y: 4.42
        height: 23.33
    }
    Rectangle {
        id: more
        anchors.right: parent.right; anchors.rightMargin: 8; y: 4.42
        width: 24; height: 23.33; radius: 4
        color: moreHover.hovered || menu.opened ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textSecondary }
        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.settingsMenuForTest() }
        Accessible.role: Accessible.Button
        Accessible.name: "Settings and more"
    }
    MenuPopup {
        id: menu
        items: [{ label: root.pinned ? "Unpin window" : "Pin window on top", icon: "pin-20", keys: "Ctrl+Shift+T" }]
        onPicked: root.togglePin()
    }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.togglePin() }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: Qt.rgba(0, 0, 0, 0.06) }
}
