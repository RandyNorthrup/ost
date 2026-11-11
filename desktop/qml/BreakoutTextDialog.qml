import QtQuick
import QtQuick.Controls

// Teams' breakout rooms dialogs with one text box (measured on winpc
// 2026-11-11), padding 24.67, radius 8:
// - "Rename Room 1?" (500 x 200): the 20/28 title with a 32 x 31.33
//   Close at its end, a filled (#F5F5F5) box holding the room's name at
//   y 94.67, then Cancel and Rename (disabled until the name changes).
// - "Announcement" (450 x 154.67): no Close; an underlined box ("Make an
//   announcement") at 61.33, then Cancel and Send (disabled while empty).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: rename ? 500 : 450; height: rename ? 200 : 154.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property bool rename: true
    property string title
    property string initial: ""
    property string placeholder: ""
    property string confirmText: rename ? "Rename" : "Send"
    signal confirmed(string text)
    readonly property bool ready: field.text.trim().length > 0 && (!rename || field.text.trim() !== initial)
    function show() { field.text = initial; open(); field.forceActiveFocus(); field.selectAll() }

    Text {
        x: 24.67; y: 24.67; width: root.width - 49.33 - (root.rename ? 40 : 0); height: root.rename ? 31.33 : 28
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.title
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Rectangle {
        visible: root.rename
        x: root.width - 56.67; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    Rectangle {
        x: 24.67; y: root.rename ? 94.67 : 61.33; width: root.width - 49.33; height: 32; radius: 4
        color: root.rename ? theme.inputFilled : theme.surface
        border.color: root.rename ? "transparent" : theme.stroke; border.width: 0.67
        Rectangle {
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 2; height: field.activeFocus ? 2 : (root.rename ? 0 : 0.67)
            color: field.activeFocus ? theme.brand : theme.textSecondary
        }
        TextInput {
            id: field
            x: 12; width: parent.width - 24; height: 32
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectByMouse: true; clip: true
            onAccepted: if (root.ready) { root.close(); root.confirmed(text.trim()) }
            Accessible.role: Accessible.EditableText
            Accessible.name: root.rename ? root.title : "Make an announcement"
            Text {
                visible: !field.text.length
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                font: field.font; color: theme.textSecondary
            }
        }
    }
    Row {
        x: root.width - 24.67 - width; y: root.height - 24.67 - 31.33; spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: !root.ready ? theme.bgDisabled : okHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: root.confirmText; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ready ? theme.textOnBrand : theme.disabled }
            HoverHandler { id: okHover; cursorShape: root.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: root.ready; onTapped: { root.close(); root.confirmed(field.text.trim()) } }
            Accessible.role: Accessible.Button
            Accessible.name: root.confirmText
        }
    }
}
