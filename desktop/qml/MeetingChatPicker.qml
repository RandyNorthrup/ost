import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Teams' "Add a chat as a tab" picker (MeetingChatPeopleTrigger, read in
// Teams' meeting-relevant-people code and measured on winpc 2026-11-27):
// a popover the meeting chat pane's width right under its header, with
// "Select a participant" (a 34 tall field, 9 px in, the brand underline
// while focused) over the meeting's people, or "No one to show here yet".
// Picking someone adds them to the field (several make a group chat);
// Enter or Tab, or closing it any way but Escape, opens the chat as a tab.
Popup {
    id: root
    /// The meeting's people you can chat with: [{id, name}].
    property var people: []
    /// Picked so far, in order.
    property var selected: []
    signal submitted(var people)
    property bool cancelled: false
    /// The list's room: what's left of the window under the field.
    property real maxListHeight: 300
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
    readonly property var shown: {
        const q = field.text.trim().toLowerCase()
        return people.filter(p => !selected.some(s => s.id === p.id) && (!q || (p.name || "").toLowerCase().indexOf(q) >= 0))
    }
    /// Open under the pane header the button sits in.
    function openFor(button) {
        const header = button.parent
        parent = header
        x = 0; y = header.height
        width = header.width
        const below = header.mapToItem(null, 0, header.height)
        const winH = header.Window.window ? header.Window.window.height : 640
        maxListHeight = Math.max(80, winH - below.y - 9 - 34 - 6 - 8 - 12)
        selected = []; field.text = ""; cancelled = false
        open()
        field.forceActiveFocus()
    }
    function pick(p) { selected = selected.concat([p]); field.text = ""; field.forceActiveFocus() }
    function submit() { close() }
    onAboutToHide: {
        // Teams: Escape cancels; any other way out opens what was picked.
        if (!cancelled && selected.length > 0) Qt.callLater(root.submitted, selected.slice())
    }
    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: { root.cancelled = true; root.close() } }

    contentItem: Column {
        width: root.width
        topPadding: 9; bottomPadding: 8
        spacing: 0
        Rectangle {
            id: box
            x: 9; width: root.width - 18; height: Math.max(34, chips.height + 8)
            radius: 4
            color: theme.input
            border.width: 0.67; border.color: theme.stroke
            Flow {
                id: chips
                x: 8; y: 4; width: parent.width - 16
                spacing: 4
                Repeater {
                    model: root.selected
                    Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        height: 24; radius: 4
                        width: chipRow.implicitWidth + 8
                        color: theme.pick("#F0F0F0", "#3D3D3D", "#000000")
                        Row {
                            id: chipRow
                            x: 4; anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Avatar { size: 16; name: chip.modelData.name; photoId: chip.modelData.id; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: chip.modelData.name; font.family: theme.font; font.pixelSize: 12; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                            FluentIcon {
                                name: "dismiss-12"; size: 12; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter
                                TapHandler { onTapped: root.selected = root.selected.filter((s, i) => i !== chip.index) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Remove %1").arg(chip.modelData.name)
                            }
                        }
                    }
                }
                TextInput {
                    id: field
                    width: Math.max(80, chips.width - (root.selected.length ? 120 : 0)); height: 24
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    clip: true
                    Text {
                        visible: !field.text && root.selected.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Select a participant")
                        font: field.font; color: theme.textSecondary
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) {
                            if (root.selected.length === 0 && root.shown.length > 0) root.pick(root.shown[0])
                            if (root.selected.length > 0) root.submit()
                            e.accepted = true
                        } else if (e.key === Qt.Key_Backspace && !field.text && root.selected.length > 0) {
                            root.selected = root.selected.slice(0, -1); e.accepted = true
                        }
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Select a participant")
                    Accessible.description: qsTr("Enter or Tab to open chat.")
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: field.activeFocus ? 2 : 0.67
                color: field.activeFocus ? theme.brand : theme.pick("#616161", "#ADADAD", "#FFFFFF")
            }
        }
        Item { width: 1; height: 6 }
        Text {
            visible: root.shown.length === 0
            x: 7; height: 32; verticalAlignment: Text.AlignVCenter
            text: root.people.length === 0 ? qsTr("No one to show here yet") : qsTr("No people found")
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        // The people (40 px rows), scrolling within the window.
        ListView {
            id: peopleList
            width: root.width
            height: Math.min(contentHeight, root.maxListHeight)
            visible: count > 0
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.shown
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: opt
                required property var modelData
                x: 4; width: peopleList.width - 8; height: 40; radius: 4
                color: optHover.hovered ? theme.menuHover : "transparent"
                Avatar { x: 8; size: 28; name: opt.modelData.name; photoId: opt.modelData.id; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    x: 44; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                    text: opt.modelData.name; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(opt.modelData) }
                Accessible.role: Accessible.ListItem
                Accessible.name: qsTr("Add %1").arg(opt.modelData.name)
            }
        }
    }
}
