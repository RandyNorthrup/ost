import QtQuick
import QtQuick.Controls.Basic

// The open chat: header with tabs and actions, message list, compose box.
Rectangle {
    id: root
    property string chatName
    property var messages: []
    property bool busy
    signal send(string text)
    signal call()
    property string chatPresence: ""
    property string typingText: ""
    signal typing()
    signal react(string messageId, string key, bool on)
    signal editMessage(string messageId, string text)
    signal deleteMessage(string messageId)
    // Set while the compose box edits an existing message.
    property string editingId: ""

    // Newest first (the list grows upward), with Teams' grouping: a message
    // joins the previous one when the same person sent it under 5 minutes
    // later. latestMine marks your newest message for the sent tick.
    function annotate(msgs) {
        const out = msgs.map(m => Object.assign({}, m))
        for (let i = 1; i < out.length; i++) {
            const prev = out[i - 1], cur = out[i]
            const gap = new Date(cur.time) - new Date(prev.time)
            cur.grouped = cur.kind !== "call" && prev.kind !== "call"
                && cur.sender === prev.sender && cur.mine === prev.mine && gap >= 0 && gap < 5 * 60 * 1000
        }
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind !== "call") { out[i].latestMine = true; break }
        }
        return out.reverse()
    }
    color: theme.surface

    // Header
    Item {
        id: header
        width: parent.width; height: theme.headerHeight
        visible: root.chatName.length > 0
        Avatar { x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32; name: root.chatName; presence: root.chatPresence }
        Text {
            id: title
            x: 64; anchors.verticalCenter: parent.verticalCenter
            text: root.chatName
            font.family: theme.font; font.pixelSize: theme.title; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: title.x + title.implicitWidth + 10
            height: parent.height
            spacing: 16
            Repeater {
                model: ["Chat", "Shared", "Notes", "Recap", "Storyline"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: tabText.implicitWidth; height: parent.height
                    Text {
                        id: tabText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.family: theme.font; font.pixelSize: theme.base
                        font.weight: index === 0 ? Font.DemiBold : Font.Normal
                        color: index === 0 ? theme.text : theme.textSecondary
                    }
                    Rectangle {
                        visible: index === 0
                        width: parent.width; height: 3; radius: 2
                        anchors.bottom: parent.bottom
                        color: theme.brand
                    }
                }
            }
            FluentIcon { name: "add-square-20"; size: 16; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            FluentIcon {
                name: "call-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.call() }
                Accessible.role: Accessible.Button
                Accessible.name: "Audio call"
            }
            FluentIcon { name: "chevron-down-12"; size: 12; anchors.verticalCenter: parent.verticalCenter }
            FluentIcon { name: "people-add-20" }
            Rectangle { width: 1; height: 20; color: theme.divider }
            FluentIcon { name: "search-20" }
            FluentIcon { name: "panel-left-20" }
            FluentIcon { name: "more-20" }
        }
        Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: theme.dividerSoft }
    }

    Text {
        anchors.centerIn: parent
        visible: root.chatName.length === 0
        text: "Select a chat to start messaging"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }

    ListView {
        id: list
        anchors { top: header.bottom; bottom: compose.top; left: parent.left; right: parent.right }
        anchors.bottomMargin: 12
        clip: true
        spacing: 0
        verticalLayoutDirection: ListView.BottomToTop
        model: root.annotate(root.messages)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: msg
            required property var modelData
            readonly property bool mine: modelData.mine
            readonly property bool isCall: modelData.kind === "call"
            readonly property var reactions: modelData.reactions || []
            width: list.width
            // Grouped messages (same sender, within minutes) drop the
            // name/time line and avatar, and sit 2 px under the previous.
            readonly property bool grouped: modelData.grouped === true
            readonly property int topPad: grouped ? 2 : 12
            readonly property int bubbleY: topPad + (grouped || isCall ? 0 : meta.height + 2)
            height: isCall ? topPad + callRow.height
                : bubbleY + bubble.height + (reactions.length > 0 ? reactionRow.height + 4 : 0)
            readonly property int maxBubble: Math.min(640, list.width * 0.7)

            // Call events: an icon, the time and "Call ended 3m 9s" / "Call missed".
            Row {
                id: callRow
                visible: msg.isCall
                x: 72; y: msg.topPad
                height: 24; spacing: 12
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: msg.modelData.call_state === "missed" ? "call-missed-16" : "call-20"
                    size: 16
                    color: msg.modelData.call_state === "missed" ? theme.danger : theme.icon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatTime(new Date(msg.modelData.time), "h:mm AP")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (msg.modelData.call_state === "missed") return "Call missed"
                        const s = msg.modelData.call_seconds, m = Math.floor(s / 60)
                        return "Call ended  " + (m > 0 ? m + "m " : "") + (s % 60) + "s"
                    }
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.text
                }
            }

            Avatar {
                visible: !msg.mine && !msg.grouped && !msg.isCall
                x: 32; y: msg.bubbleY
                size: 32; name: msg.modelData.sender
            }
            Text {
                id: meta
                visible: !msg.grouped && !msg.isCall
                y: msg.topPad
                text: (msg.mine ? "" : msg.modelData.sender + "  ") + Qt.formatTime(new Date(msg.modelData.time), "h:mm AP")
                    + (msg.modelData.edited ? "   Edited" : "")
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                x: msg.mine ? parent.width - 72 - implicitWidth : 72
            }
            Rectangle {
                id: bubble
                visible: !msg.isCall
                y: msg.bubbleY
                width: Math.min(msg.maxBubble, body.implicitWidth + 32)
                height: body.implicitHeight + 16
                radius: theme.radius
                color: msg.mine ? theme.brandTint : theme.pane
                x: msg.mine ? parent.width - 72 - width : 72
                Text {
                    id: body
                    x: 16; y: 8
                    width: Math.min(msg.maxBubble - 32, implicitWidth)
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : "<style>a { color: " + theme.brand + "; text-decoration: none; }</style>"
                          + (msg.modelData.html || msg.modelData.text)
                    textFormat: msg.modelData.deleted ? Text.PlainText : Text.RichText
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    font.italic: msg.modelData.deleted === true
                    color: msg.modelData.deleted ? theme.textSecondary : theme.text
                    linkColor: theme.brand
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    Accessible.name: msg.modelData.text
                }
            }
            // Reaction pills under the bubble, as in Teams; yours has a brand
            // outline. Clicking one toggles your reaction.
            Row {
                id: reactionRow
                visible: msg.reactions.length > 0
                y: bubble.y + bubble.height + 4
                x: msg.mine ? parent.width - 72 - width : 72 + 8
                spacing: 4
                Repeater {
                    model: msg.reactions
                    Rectangle {
                        required property var modelData
                        width: pill.implicitWidth + 16; height: 24; radius: 12
                        color: modelData.mine ? theme.brandTint : theme.surface
                        border.color: modelData.mine ? theme.brand : theme.stroke
                        Row {
                            id: pill
                            anchors.centerIn: parent; spacing: 4
                            Text { text: parent.parent.modelData.emoji; font.pixelSize: 14 }
                            Text {
                                visible: parent.parent.modelData.count > 1
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.count
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.text
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.react(msg.modelData.id, modelData.key, !modelData.mine) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.count + " " + modelData.key + " reaction" + (modelData.mine ? ", including yours" : "")
                    }
                }
            }
            HoverHandler { id: msgHover }
            // Hover bar: quick reactions and More, at the bubble's top edge.
            Rectangle {
                id: actions
                readonly property bool can: !msg.isCall && !msg.modelData.deleted
                visible: can && (msgHover.hovered || barHover.hovered || menu.visible)
                z: 5
                height: 32; width: actionRow.implicitWidth + 8; radius: theme.radius
                color: theme.surface
                border.color: theme.dividerSoft
                y: bubble.y - 22
                x: msg.mine ? bubble.x : Math.max(72, bubble.x + bubble.width - width)
                HoverHandler { id: barHover }
                Row {
                    id: actionRow
                    x: 4; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [["like", "👍"], ["heart", "❤️"], ["laugh", "😆"], ["surprised", "😮"], ["sad", "😢"]]
                        Rectangle {
                            required property var modelData
                            readonly property bool mineAlready: msg.reactions.some(r => r.key === modelData[0] && r.mine)
                            width: 30; height: 28; radius: theme.radius
                            color: emojiHover.hovered ? theme.pane : "transparent"
                            Text { anchors.centerIn: parent; text: parent.modelData[1]; font.pixelSize: 16 }
                            HoverHandler { id: emojiHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.react(msg.modelData.id, parent.modelData[0], !parent.mineAlready) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "React with " + modelData[0]
                        }
                    }
                    Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
                    Rectangle {
                        visible: msg.mine
                        width: 30; height: 28; radius: theme.radius
                        color: moreHover.hovered ? theme.pane : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-20"; size: 16 }
                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: menu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options"
                    }
                }
                Menu {
                    id: menu
                    y: actions.height
                    MenuItem {
                        text: "Edit"
                        onTriggered: { root.editingId = msg.modelData.id; input.text = msg.modelData.text; input.forceActiveFocus() }
                    }
                    MenuItem {
                        text: "Delete"
                        onTriggered: root.deleteMessage(msg.modelData.id)
                    }
                }
            }
            // Teams shows the sent/read tick on your latest message only.
            FluentIcon {
                visible: msg.mine && msg.modelData.latestMine === true && !msg.isCall
                name: "sent-12"; size: 12; color: theme.brand
                x: bubble.x + bubble.width + 8
                y: bubble.y + bubble.height - 14
            }
        }
    }

    // Typing indicator, as Teams draws it: the typist's avatar overlapping
    // the compose box's top-left edge with three pulsing dots (the text is
    // the accessible name).
    Item {
        id: typingRow
        visible: root.typingText.length > 0
        z: 2
        x: compose.x + 16; y: compose.y - 24
        width: 32 + 6 + 3 * 6 + 2 * 3; height: 32
        Accessible.role: Accessible.StaticText
        Accessible.name: root.typingText
        Avatar { size: 32; name: root.typingText.replace(/ is typing$/, "") }
        Row {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 6; height: 6; radius: 3
                    color: "#C8C6C4"
                    SequentialAnimation on color {
                        running: typingRow.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 200 }
                        ColorAnimation { to: theme.brand; duration: 200 }
                        ColorAnimation { to: "#C8C6C4"; duration: 200 }
                        PauseAnimation { duration: (2 - index) * 200 + 200 }
                    }
                }
            }
        }
    }

    // "Editing" strip above the compose box while editing a message.
    Rectangle {
        visible: root.editingId.length > 0
        anchors { left: compose.left; right: compose.right; bottom: compose.top; bottomMargin: 2 }
        height: 28; radius: theme.radius
        color: theme.brandTint
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: "Editing message — Enter to save, Esc to cancel"
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.text
        }
    }

    // Compose box
    Rectangle {
        id: compose
        visible: root.chatName.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: 72; anchors.rightMargin: 72; anchors.bottomMargin: 24
        height: Math.max(44, input.contentHeight + 24)
        radius: theme.radius
        color: theme.surface
        border.color: input.activeFocus ? theme.brand : theme.divider
        TextArea {
            id: input
            anchors { left: parent.left; right: tools.left; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 4
            placeholderText: "Type a message"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            wrapMode: TextArea.Wrap
            background: null
            onTextChanged: if (text.length > 0) root.typing()
            Keys.onReturnPressed: event => {
                if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                if (root.editingId) { root.editMessage(root.editingId, input.text); root.editingId = "" }
                else root.send(input.text)
                input.text = ""
            }
            Keys.onEscapePressed: if (root.editingId) { root.editingId = ""; input.text = "" }
        }
        Row {
            id: tools
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            FluentIcon { name: "format-20" }
            FluentIcon { name: "emoji-20" }
            FluentIcon { name: "attach-20" }
            FluentIcon { name: "add-20" }
            Rectangle { width: 1; height: 20; color: theme.divider }
            FluentIcon {
                name: input.text.length > 0 ? "send-20-filled" : "send-20"
                color: input.text.length > 0 ? theme.brand : theme.icon
                TapHandler { onTapped: { root.send(input.text); input.text = "" } }
            }
        }
    }
}
