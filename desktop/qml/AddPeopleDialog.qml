import QtQuick
import QtQuick.Controls

// Teams' Add (chat-add-participant-popup, measured on winpc): add people
// to a group chat and choose how much of its history they see.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 402
    height: buttons.y + 31.3 + 16.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
    Overlay.modal: Rectangle { color: "transparent" }

    /// MRIs already in the chat (not offered).
    property var members: []
    /// Teams' history choice: -1 none, 1 the past `days` days, 0 all.
    property int history: -1
    property int days: 1
    /// people, and days as add_chat_members takes them (< 0 none, 0 all).
    signal accepted(var people, int days)

    function start() {
        picker.reset()
        history = -1; days = 1
        open()
        picker.focusField()
    }

    Text {
        x: 16.7; y: 16.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "Add"
        font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6")
    }
    // The history choice: 12 px labels at 44.7, 20 apart; the chosen one
    // in the text colour, the others secondary.
    Column {
        id: choices
        x: 16.7; y: picker.y + picker.height + 4
        Repeater {
            model: [{ v: -1, t: "Don't include chat history" }, { v: 1, t: "Include history from the past number of days:" }, { v: 0, t: "Include all chat history" }]
            Item {
                required property var modelData
                width: 368.7; height: 20
                readonly property bool on: root.history === modelData.v
                Rectangle {
                    x: 0; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 8
                    color: "transparent"
                    border.color: parent.on ? theme.brand : theme.pick("#616161", "#ADADAD"); border.width: 1
                    Rectangle { visible: parent.parent.on; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
                }
                Text {
                    id: label
                    x: 28; anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.t
                    font.family: theme.font; font.pixelSize: 12
                    color: parent.on ? theme.text : theme.textSecondary
                }
                // The number of days (1 to 999), a small grey box.
                Rectangle {
                    visible: parent.modelData.v === 1
                    x: label.x + label.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(20, daysField.implicitWidth + 8); height: 18.7; radius: 2
                    color: theme.pick("#F0F0F0", "#2E2E2E")
                    TextInput {
                        id: daysField
                        anchors.centerIn: parent
                        text: String(root.days)
                        validator: IntValidator { bottom: 1; top: 999 }
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                        onTextEdited: { const n = parseInt(text); if (n >= 1 && n <= 999) { root.days = n; root.history = 1 } }
                        Accessible.name: "Number of days"
                    }
                }
                TapHandler { onTapped: root.history = parent.modelData.v }
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.t
                Accessible.checked: on
            }
        }
    }
    Row {
        id: buttons
        x: 185.3; y: choices.y + choices.height + 16
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
            color: !can ? theme.pick("#F0F0F0", "#141414") : addHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Add"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: addHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: root.finish() }
            Accessible.role: Accessible.Button
            Accessible.name: "Add"
        }
    }
    PeopleTagPicker {
        id: picker
        x: 16.7; y: 43.3 - 0.6
        placeholder: "Enter a name, email, or tag"
        exclude: root.members
    }
    function finish() {
        const p = picker.picked
        close()
        accepted(p, history === 1 ? days : history)
    }
    // Test hooks.
    function typeForTest(t) { picker.typeForTest(t) }
    function pickFirstForTest() { picker.pickFirstForTest() }
}
