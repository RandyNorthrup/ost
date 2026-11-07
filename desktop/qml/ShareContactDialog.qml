import QtQuick
import QtQuick.Controls

// Teams' "Share someone's contact info" (chat-share-contact-popup,
// measured on winpc): pick people by name; OK puts each one's contact card
// in the message. They aren't @mentioned or notified.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 402
    height: buttons.y + 31.3 + 24.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
    Overlay.modal: Rectangle { color: "transparent" }

    signal accepted(var people)

    function start() {
        picker.reset()
        open()
        picker.focusField()
    }

    Text {
        x: 16.7; y: 16.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "Share someone's contact info in the message"
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    Text {
        x: 24.7; y: picker.y + picker.height + 8.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "They won't be @mentioned or notified"
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    Row {
        id: buttons
        x: 177.3; y: picker.y + picker.height + 54
        spacing: 8
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            readonly property bool can: picker.picked.length > 0
            width: 96; height: 31.3; radius: 4
            color: !can ? theme.pick("#F0F0F0", "#141414") : okHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "OK"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: okHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: root.finish() }
            Accessible.role: Accessible.Button
            Accessible.name: "OK"
        }
    }
    // Last, so its matches drop over the hint and buttons.
    PeopleTagPicker {
        id: picker
        x: 16.7; y: 46.7
        placeholder: "Enter name"
    }
    function finish() { const p = picker.picked; close(); accepted(p) }
    // Test hooks.
    function typeForTest(t) { picker.typeForTest(t) }
    function pickFirstForTest() { picker.pickFirstForTest() }
    function okForTest() { finish() }
}
