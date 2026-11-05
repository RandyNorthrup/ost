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

    // Newest first (the list grows upward), with Teams' grouping: a message
    // joins the previous one when the same person sent it under 5 minutes
    // later. latestMine marks your newest message for the sent tick.
    function annotate(msgs) {
        const out = msgs.map(m => Object.assign({}, m))
        for (let i = 1; i < out.length; i++) {
            const prev = out[i - 1], cur = out[i]
            const gap = new Date(cur.time) - new Date(prev.time)
            cur.grouped = cur.sender === prev.sender && cur.mine === prev.mine && gap >= 0 && gap < 5 * 60 * 1000
        }
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine) { out[i].latestMine = true; break }
        }
        return out.reverse()
    }
    color: theme.surface

    // Header
    Item {
        id: header
        width: parent.width; height: theme.headerHeight
        visible: root.chatName.length > 0
        Avatar { x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32; name: root.chatName }
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
            width: list.width
            // Grouped messages (same sender, within minutes) drop the
            // name/time line and avatar, and sit 2 px under the previous.
            readonly property bool grouped: modelData.grouped === true
            readonly property int topPad: grouped ? 2 : 12
            readonly property int bubbleY: topPad + (grouped ? 0 : meta.height + 2)
            height: bubbleY + bubble.height
            readonly property int maxBubble: Math.min(640, list.width * 0.7)

            Avatar {
                visible: !msg.mine && !msg.grouped
                x: 32; y: msg.bubbleY
                size: 32; name: msg.modelData.sender
            }
            Text {
                id: meta
                visible: !msg.grouped
                y: msg.topPad
                text: (msg.mine ? "" : msg.modelData.sender + "  ") + Qt.formatTime(new Date(msg.modelData.time), "h:mm AP")
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                x: msg.mine ? parent.width - 72 - implicitWidth : 72
            }
            Rectangle {
                id: bubble
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
                    text: msg.modelData.text
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                    textFormat: Text.PlainText
                }
            }
            // Teams shows the sent/read tick on your latest message only.
            FluentIcon {
                visible: msg.mine && msg.modelData.latestMine === true
                name: "sent-12"; size: 12; color: theme.brand
                x: bubble.x + bubble.width + 8
                y: bubble.y + bubble.height - 14
            }
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
            Keys.onReturnPressed: event => {
                if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                root.send(input.text); input.text = ""
            }
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
