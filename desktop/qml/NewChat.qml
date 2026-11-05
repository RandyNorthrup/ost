import QtQuick
import QtQuick.Controls.Basic

// New chat, as in Teams: a "To:" row where each person you pick becomes a
// removable chip, an optional group name (the chevron at the right), and
// a compose box. Sending with one person and no name opens (or starts)
// your 1:1 chat with them; with more people, or a name, it starts a
// group chat.
Rectangle {
    id: root
    property var people: []
    /// Picked so far: [{ id, name }].
    property var picked: []
    property bool naming: false
    property alias nameText: nameField.text
    property alias messageText: message.text
    signal search(string query)
    /// One person, no name: open your 1:1 chat (and send `text`, if any).
    signal chosen(string oid, string name, string text)
    /// Several people, or a name: start a group chat.
    signal group(string oids, string topic, string text)
    signal cancelled()
    color: theme.surface

    onVisibleChanged: if (visible) { picked = []; naming = false; field.text = ""; nameField.text = ""; message.text = ""; field.forceActiveFocus() }

    function pick(p) {
        if (!picked.some(x => x.id === p.id)) picked = picked.concat([{ id: p.id, name: p.name }])
        field.text = ""
        root.search("")
        field.forceActiveFocus()
    }
    function unpick(id) { picked = picked.filter(x => x.id !== id) }
    function submit() {
        const text = message.text.trim()
        if (picked.length === 0) return
        if (picked.length === 1 && !nameField.text.trim()) root.chosen(picked[0].id, picked[0].name, text)
        else root.group(picked.map(p => p.id).join(","), nameField.text.trim(), text)
    }

    // Group name (shown with the chevron).
    Rectangle {
        id: nameRow
        visible: root.naming
        width: parent.width; height: visible ? 48 : 0
        color: theme.surface
        Text {
            id: nameLabel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            text: "Group name:"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
        TextField {
            id: nameField
            anchors { left: nameLabel.right; leftMargin: 8; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            placeholderText: "Enter a group name"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            background: Item {}
            Keys.onEscapePressed: root.cancelled()
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    Rectangle {
        id: toRow
        anchors.top: nameRow.bottom
        width: parent.width; height: Math.max(theme.headerHeight, chips.height + 16)
        color: theme.surface
        Text {
            id: toLabel
            x: 20; y: (theme.headerHeight - height) / 2
            text: "To:"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
        Flow {
            id: chips
            anchors { left: toLabel.right; leftMargin: 8; right: chevron.left; rightMargin: 8 }
            y: 8
            spacing: 6
            Repeater {
                model: root.picked
                Rectangle {
                    required property var modelData
                    height: 32; radius: theme.radius
                    width: chipRow.implicitWidth + 12
                    color: theme.searchFill
                    Row {
                        id: chipRow
                        x: 4; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Avatar { anchors.verticalCenter: parent.verticalCenter; size: 24; name: modelData.name; photoId: modelData.id }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 10
                            color: xh.hovered ? theme.rowHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textStrong }
                            HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.unpick(modelData.id) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + modelData.name
                        }
                    }
                }
            }
            TextField {
                id: field
                width: root.picked.length ? 200 : chips.width
                height: 32
                placeholderText: root.picked.length ? "" : "Enter name, chat, channel or tag"
                placeholderTextColor: theme.textSecondary
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                background: Item {}
                focus: true
                onTextEdited: debounce.restart()
                Keys.onEscapePressed: root.cancelled()
                Keys.onReturnPressed: {
                    if (field.text.length > 0 && root.people.length > 0) root.pick(root.people[0])
                    else if (root.picked.length > 0) message.forceActiveFocus()
                }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Backspace && field.text.length === 0 && root.picked.length > 0) {
                        root.unpick(root.picked[root.picked.length - 1].id); e.accepted = true
                    }
                }
                Component.onCompleted: forceActiveFocus()
                Accessible.name: "To"
            }
        }
        Rectangle {
            id: chevron
            anchors.right: parent.right; anchors.rightMargin: 16
            y: (theme.headerHeight - height) / 2
            width: 32; height: 32; radius: theme.radius
            color: cvh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-16"; size: 16; color: theme.textStrong; rotation: root.naming ? 180 : 0 }
            HoverHandler { id: cvh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.naming = !root.naming; if (root.naming) nameField.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: root.naming ? "Hide group name" : "Add group name"
        }
        Timer { id: debounce; interval: 300; onTriggered: root.search(field.text) }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // Search results while typing.
    ListView {
        id: results
        visible: field.text.length > 0
        anchors { top: toRow.bottom; left: parent.left; right: parent.right; bottom: compose.top; topMargin: 4 }
        clip: true
        model: visible ? root.people : []
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
            TapHandler { onTapped: root.pick(person.modelData) }
            Accessible.role: Accessible.Button
            Accessible.name: "Add " + person.modelData.name
        }
    }
    Text {
        visible: field.text.length >= 2 && root.people.length === 0
        anchors.centerIn: parent
        text: "No people found"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }
    Text {
        visible: field.text.length === 0 && root.picked.length > 1
        anchors.centerIn: parent
        text: "You're starting a new conversation with " + root.picked.map(p => p.name).join(", ")
        width: parent.width - 160; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }

    // Compose
    Rectangle {
        id: compose
        visible: root.picked.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 72; rightMargin: 72; bottomMargin: 24 }
        height: visible ? Math.max(44, message.contentHeight + 24) : 0
        radius: theme.radius
        color: theme.input
        border.color: theme.stroke
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1; color: message.activeFocus ? theme.brand : "transparent" }
        TextArea {
            id: message
            anchors { left: parent.left; right: sendButton.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
            placeholderText: "Type a message"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            wrapMode: TextArea.Wrap
            background: Item {}
            Keys.onReturnPressed: e => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else root.submit() }
            Keys.onEscapePressed: root.cancelled()
            Accessible.name: "Type a message"
        }
        Rectangle {
            id: sendButton
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: 32; height: 32; radius: theme.radius
            color: sbh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: message.text.trim() ? "send-20-filled" : "send-20"; size: 20; color: message.text.trim() ? theme.brand : theme.textStrong }
            HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.submit() }
            Accessible.role: Accessible.Button
            Accessible.name: "Send"
        }
    }
}
