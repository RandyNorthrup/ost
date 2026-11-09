import QtQuick
import QtQuick.Controls.Basic

// Teams' "About this bot", shown after adding a bot that only sends
// notifications (measured on winpc 2026-11-09, adding Polls to a group
// chat): 600 wide, radius 8; the title 20/28 semibold, the text 14/20 and
// OK (brand, 96 x 32) at the bottom right.
Popup {
    id: root
    modal: true; focus: true
    width: 600; padding: 24
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }
    contentItem: Column {
        spacing: 0
        Text { text: "About this bot"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Item { width: 1; height: 8 }
        Text { width: parent.width; wrapMode: Text.Wrap; text: "This bot sends notifications only. You’re not able to chat with or @mention it."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Item { width: 1; height: 24 }
        Rectangle {
            anchors.right: parent.right
            width: 96; height: 32; radius: 4
            color: okHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "OK"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: "OK"
        }
    }
}
