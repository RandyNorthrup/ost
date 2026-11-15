import QtQuick
import QtQuick.Controls.Basic

// Fluent's Combobox with a search icon, as Teams' "Translate messages into
// this language" (measured on winpc 2026-11-14): 294 x 32, the outline
// dropdown's border and underline, a 16 px search icon 8 in, the value at
// 28 and the chevron 10 from the right. Opening it empties the field so you
// can type to filter; its listbox (Fluent's surface, padding 4, 340 tall)
// opens below, or above when there is no room, with 50 px options: the
// chosen one's check (16) 6 in, the name at 28 (14 px) over a second name
// (12 px, NeutralForeground2).
Item {
    id: root
    /// [{key, label, sublabel}]
    property var options: []
    property string current: ""
    property string accessibleName: ""
    /// Shown (NeutralForeground2) while nothing is chosen.
    property string placeholder: ""
    property real listHeight: 340
    signal picked(string key)
    implicitWidth: 294; implicitHeight: 32

    readonly property var currentOption: options.find(o => o.key === current) || null
    readonly property var shown: {
        const q = field.text.trim().toLowerCase()
        if (!list.opened || q === "") return options
        return options.filter(o => o.label.toLowerCase().indexOf(q) >= 0 || (o.sublabel || "").toLowerCase().indexOf(q) >= 0)
    }

    function openList() {
        if (list.opened) return
        // Below when it fits, else above (as Teams' listbox flips).
        const w = root.Window.window
        const below = root.mapToItem(null, 0, root.height).y
        list.y = (w && below + root.listHeight + 2 > w.height && root.mapToItem(null, 0, 0).y > root.listHeight + 2) ? -root.listHeight - 2 : root.height + 2
        field.text = ""
        list.open()
        field.forceActiveFocus()
    }

    function closeList() { list.close() }

    Rectangle {
        anchors.fill: parent; radius: 4
        color: theme.surface
        border.color: !root.enabled ? theme.pick("#E0E0E0", "#424242") : hover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: list.opened || field.activeFocus ? 2 : 0.67; color: list.opened || field.activeFocus ? theme.brand : root.enabled ? theme.textSecondary : theme.pick("#E0E0E0", "#424242") }
        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-16"; size: 16; color: root.enabled ? theme.text : theme.disabled }
        TextInput {
            id: field
            x: 28; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 28 - 40
            clip: true
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectByMouse: true
            selectionColor: theme.brand
            Accessible.role: Accessible.ComboBox
            Accessible.name: root.accessibleName
            Accessible.description: root.currentOption ? root.currentOption.label : ""
            onTextEdited: if (!list.opened) root.openList()
            Keys.onDownPressed: { if (!list.opened) root.openList(); else view.currentIndex = Math.min(view.count - 1, view.currentIndex + 1) }
            Keys.onUpPressed: view.currentIndex = Math.max(0, view.currentIndex - 1)
            Keys.onReturnPressed: if (list.opened && view.currentIndex >= 0 && view.currentIndex < root.shown.length) { root.picked(root.shown[view.currentIndex].key); list.close() }
            Keys.onEscapePressed: list.close()
            // The chosen language while the list is shut.
            Text {
                visible: !list.opened && field.text === ""
                width: parent.width; elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentOption ? root.currentOption.label : root.placeholder
                font: field.font; color: !root.enabled ? theme.disabled : root.currentOption ? theme.text : theme.textSecondary
            }
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: root.enabled ? theme.textSecondary : theme.disabled }
        HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
        TapHandler { onTapped: list.opened ? list.close() : root.openList() }
    }
    Popup {
        id: list
        width: root.width
        height: root.listHeight
        padding: 4
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onOpened: {
            const i = root.shown.findIndex(o => o.key === root.current)
            view.currentIndex = i
            view.positionViewAtIndex(Math.max(0, i), ListView.Center)
        }
        onClosed: field.text = ""
        contentItem: ListView {
            id: view
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: opt
                required property var modelData
                required property int index
                width: view.width; height: 50; radius: 4
                color: optHover.hovered || view.currentIndex === index ? theme.menuHover : "transparent"
                FluentIcon { visible: opt.modelData.key === root.current; x: 6; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                Column {
                    x: 28; y: 6; width: parent.width - 36
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: opt.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Text { width: parent.width; elide: Text.ElideRight; text: opt.modelData.sublabel || ""; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                }
                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.picked(opt.modelData.key); list.close() } }
                Accessible.role: Accessible.ListItem
                Accessible.name: opt.modelData.label + ", " + (opt.modelData.sublabel || "")
            }
        }
    }
}
