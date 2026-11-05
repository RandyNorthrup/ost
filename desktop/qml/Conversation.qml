import QtQuick
import QtQuick.Controls.Basic

// The open chat: header with tabs and actions, message list, compose box.
Rectangle {
    id: root
    property string chatName
    property var messages: []
    property bool busy
    signal send(string text)
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
            FluentIcon { name: "call-20" }
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
        spacing: 8
        verticalLayoutDirection: ListView.BottomToTop
        model: root.messages.slice().reverse()
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: msg
            required property var modelData
            readonly property bool mine: modelData.mine
            width: list.width
            height: bubble.height + meta.height + 4
            readonly property int maxBubble: Math.min(640, list.width * 0.7)

            Avatar {
                visible: !msg.mine
                x: 32; y: meta.height + 2
                size: 32; name: msg.modelData.sender
            }
            Text {
                id: meta
                text: (msg.mine ? "" : msg.modelData.sender + "  ") + Qt.formatTime(new Date(msg.modelData.time), "h:mm AP")
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                x: msg.mine ? parent.width - 72 - implicitWidth : 72
            }
            Rectangle {
                id: bubble
                y: meta.height + 2
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
            FluentIcon {
                visible: msg.mine
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
