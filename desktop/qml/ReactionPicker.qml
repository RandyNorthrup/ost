import QtQuick
import QtQuick.Controls.Basic

// Teams' reaction picker (reaction-picker-root, measured in the client):
// 317 x 372, the emoji panel on a Fluent surface (depth 16, radius 4).
// Picking an emoticon emits picked(key, on) and closes.
Popup {
    id: root
    property string messageId
    // Our reactions on the message (pills with mine set).
    property var mine: []
    // Choosing a default reaction (Customize): no customize button, no undo.
    property bool customizing: false
    signal picked(string key, bool on)
    signal customize()
    width: 317; height: 372; padding: 0
    modal: false; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
    onOpened: panel.reset()
    // Test hook (the tones of an emoticon in Recent's first row).
    function tonesForTest(id) { panel.tonesForTest(id) }
    contentItem: EmojiPanel {
        id: panel
        active: root.opened
        messageId: root.messageId
        mine: root.mine
        customizing: root.customizing
        onPicked: (key, on) => root.picked(key, on)
        onCustomize: root.customize()
        onDone: root.close()
    }
}
