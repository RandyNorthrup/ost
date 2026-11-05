import QtQuick
import QtQuick.Controls.Basic

// New chat: Teams' "To:" row with a people picker. Typing searches the
// directory; choosing someone opens (or starts) your 1:1 chat with them.
Rectangle {
    id: root
    property var people: []
    signal search(string query)
    signal chosen(string oid, string name)
    signal cancelled()
    color: theme.surface

    Rectangle {
        id: toRow
        width: parent.width; height: theme.headerHeight
        color: theme.surface
        Text {
            id: toLabel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            text: "To:"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
        TextField {
            id: field
            anchors { left: toLabel.right; leftMargin: 8; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            placeholderText: "Enter name, chat, channel or tag"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            background: Item {}
            focus: true
            onTextEdited: debounce.restart()
            Keys.onEscapePressed: root.cancelled()
            Keys.onReturnPressed: if (root.people.length > 0) root.chosen(root.people[0].id, root.people[0].name)
            Component.onCompleted: forceActiveFocus()
        }
        Timer { id: debounce; interval: 300; onTriggered: root.search(field.text) }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    ListView {
        anchors { top: toRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 4 }
        clip: true
        model: root.people
        delegate: Rectangle {
            id: person
            required property var modelData
            width: ListView.view.width; height: 52
            color: hover.hovered ? theme.pane : "transparent"
            Avatar { x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32; name: person.modelData.name; photoId: person.modelData.id || "" }
            Column {
                x: 64; anchors.verticalCenter: parent.verticalCenter
                Text { text: person.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Text {
                    text: [person.modelData.job_title, person.modelData.mail].filter(t => t).join(" · ")
                    font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
                }
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.chosen(person.modelData.id, person.modelData.name) }
            Accessible.role: Accessible.Button
            Accessible.name: "Chat with " + person.modelData.name
        }
    }
    Text {
        visible: field.text.length >= 2 && root.people.length === 0
        anchors.centerIn: parent
        text: "No people found"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }
}
