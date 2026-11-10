import QtQuick
import QtQuick.Controls.Basic

// Fluent's Dropdown, outline appearance (Pause notifications until's Time):
// 32 tall, radius 4, a 0.67 NeutralStroke1 border with a NeutralStrokeAccessible
// bottom (2 px brand while open), the value 14 px 12 in, chevron-down (20,
// #616161) 10 from the right. Its listbox opens below: Fluent's surface
// (radius 4, shadow16, padding 4), options 32 tall with the chosen one's
// check (16) 6 in and the text at 30; disabled options greyed and inert.
Item {
    id: root
    /// [{label, disabled?}]
    property var options: []
    property int current: 0
    property string accessibleName: ""
    /// Shown (#616161) while nothing is chosen.
    property string placeholder: ""
    signal picked(int index)
    implicitWidth: 277.3; implicitHeight: 32

    Rectangle {
        anchors.fill: parent; radius: 4
        color: theme.surface
        border.color: hover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: list.opened ? 2 : 0.67; color: list.opened ? theme.brand : theme.textSecondary }
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 52; elide: Text.ElideRight
            text: root.options.length && root.current >= 0 ? root.options[root.current].label : root.placeholder
            font.family: theme.font; font.pixelSize: 14; color: root.current >= 0 ? theme.text : theme.textSecondary
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: list.opened ? list.close() : list.open() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: root.accessibleName + (root.options.length && root.current >= 0 ? ", " + root.options[root.current].label : "")
    }
    Popup {
        id: list
        y: root.height + 2; width: root.width
        padding: 4
        height: Math.min(view.contentHeight, 300) + 8
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onOpened: view.positionViewAtIndex(Math.max(0, root.current), ListView.Center)
        contentItem: ListView {
            id: view
            clip: true
            model: root.options
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: opt
                required property var modelData
                required property int index
                readonly property bool usable: !modelData.disabled
                width: view.width; height: 32; radius: 4
                color: optHover.hovered && usable ? theme.menuHover : "transparent"
                FluentIcon { visible: opt.index === root.current; x: 6; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                Text { x: 30; anchors.verticalCenter: parent.verticalCenter; text: opt.modelData.label; font.family: theme.font; font.pixelSize: 14; color: opt.usable ? theme.text : theme.disabled }
                HoverHandler { id: optHover; cursorShape: opt.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: opt.usable; onTapped: { root.picked(opt.index); list.close() } }
                Accessible.role: Accessible.ListItem
                Accessible.name: opt.modelData.label
            }
        }
    }
}
