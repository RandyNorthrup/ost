import QtQuick
import QtQuick.Controls.Basic

// Teams' chat list section dialogs (strings from its simpleCollab
// namespace; the Fluent dialog frame as OST's other dialogs):
// - Create: "Create a new section", "Enter a section name", Create.
//   A name in use: "This section name already exists."
// - Rename: "Rename section", "The section will be renamed in both Chat
//   and Channels.", Save.
// - Remove: "Remove {name}?", "The items in this section will still be
//   available in your list.", "The section will be removed in both Chat and
//   Channels.", Remove.
Popup {
    id: root
    /// Section titles in use.
    property var existing: []
    /// "create", "rename" or "remove".
    property string mode: "create"
    property var section: null
    /// Create: the conversation to move into the new section, and where
    /// it was.
    property string item: ""
    property string from: ""
    modal: true; focus: true
    width: 480
    padding: 24
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }

    function create(item_, from_) { mode = "create"; section = null; item = item_ || ""; from = from_ || ""; field.text = ""; open(); field.forceActiveFocus() }
    function rename(s) { mode = "rename"; section = s; field.text = s ? s.title : ""; open(); field.selectAll(); field.forceActiveFocus() }
    function remove(s) { mode = "remove"; section = s; open() }

    readonly property string name: field.text.trim()
    readonly property bool taken: mode !== "remove" && name.length > 0
        && existing.some(t => t.toLowerCase() === name.toLowerCase())
        && !(mode === "rename" && section && section.title.toLowerCase() === name.toLowerCase())
    readonly property bool canConfirm: mode === "remove" || (name.length > 0 && !taken && !(mode === "rename" && section && section.title === name))
    function confirm() {
        if (!canConfirm) return
        if (mode === "create") backend.folderAction("create", JSON.stringify({ name: root.name, item: root.item, from: root.from }))
        else if (mode === "rename") backend.folderAction("rename", JSON.stringify({ id: root.section.id, name: root.name }))
        else backend.folderAction("delete", JSON.stringify({ id: root.section.id }))
        close()
    }

    contentItem: Column {
        spacing: 0
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.mode === "create" ? qsTr("Create a new section") : root.mode === "rename" ? qsTr("Rename section") : qsTr("Remove %1?").arg(root.section ? root.section.title : "")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Item { width: 1; height: root.mode === "create" ? 0 : 8 }
        Text {
            visible: root.mode !== "create"
            width: parent.width; wrapMode: Text.Wrap
            text: root.mode === "rename" ? qsTr("The section will be renamed in both Chat and Channels.") : qsTr("The section will be removed in both Chat and Channels.")
            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
        }
        Item { width: 1; height: root.mode === "remove" ? 12 : 0 }
        Text {
            visible: root.mode === "remove"
            width: parent.width; wrapMode: Text.Wrap
            text: qsTr("The items in this section will still be available in your list.")
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Item { width: 1; height: root.mode === "remove" ? 0 : 16 }
        Rectangle {
            visible: root.mode !== "remove"
            width: parent.width; height: 32; radius: 4
            color: theme.inputFilled; border.color: theme.transparentStroke
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: field.activeFocus ? 2 : 0.67; color: field.activeFocus ? theme.brand : theme.textSecondary }
            TextField {
                id: field
                anchors.fill: parent; leftPadding: 10
                maximumLength: 50
                placeholderText: qsTr("Enter a section name")
                placeholderTextColor: theme.textTertiary
                background: null
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                Keys.onReturnPressed: root.confirm()
                Accessible.name: qsTr("Section name")
            }
        }
        Text {
            visible: root.taken
            topPadding: 4
            text: qsTr("This section name already exists.")
            font.family: theme.font; font.pixelSize: 12; color: theme.redForeground1
        }
        Item { width: 1; height: 24 }
        Row {
            anchors.right: parent.right
            spacing: 8
            Rectangle {
                id: hcFill1
                width: 96; height: 32; radius: 4
                color: cancelHover.hovered ? theme.menuHover : theme.surface
                border.width: 0.67; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: hcFill2
                width: 96; height: 32; radius: 4
                color: !root.canConfirm ? theme.bgDisabled : okHover.hovered ? theme.brandHover : theme.brandFill
                Text {
                    anchors.centerIn: parent
                    text: root.mode === "create" ? qsTr("Create") : root.mode === "rename" ? qsTr("Save") : qsTr("Remove")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill2, root.canConfirm ? theme.textOnBrand : theme.disabled)
                }
                HoverHandler { id: okHover; cursorShape: root.canConfirm ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: root.confirm() }
                Accessible.role: Accessible.Button
                Accessible.name: root.mode === "create" ? qsTr("Create") : root.mode === "rename" ? qsTr("Save") : qsTr("Remove")
            }
        }
    }
}
