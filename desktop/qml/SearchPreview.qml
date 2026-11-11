import QtQuick
import QtQuick.Controls.Basic

// A search result opened beside the results (Teams' preview pane, measured
// on winpc 2026-11-10): 40% of the page (484.8 of 1212), a 0.67 px #E0E0E0
// line on its left, a 61 px white header with a line under it:
// - a chat: its 32 px picture (20.7 in) and name (18/700, 64.7 in), More
//   chat options (··· : Go to chat, Open in new window, Mark as unread,
//   Copy link) and Close, 32 apart from 41.8 from the right; the whole chat
//   under it, at the message, with its terms marked, and its compose box;
// - a channel post: the team's square picture, the channel (14/600) and
//   the post's subject (12), Go to channel, Open in new window, ··· and
//   Close; the post's thread under it with "Send to: thread only".
Rectangle {
    id: pane
    property var hit: null
    property var terms: []
    /// Where it was said (SearchView.channelOf), and the chat's name.
    property var place: null
    property string chatName: ""
    signal closed()
    signal goTo()
    signal popOut()
    color: theme.surface
    readonly property bool channel: !!place
    readonly property string thread: hit ? hit.thread : ""
    readonly property string rootId: channel && hit ? (hit.parent_id || hit.id) : ""
    readonly property string key: !hit ? "" : channel ? thread + ";messageid=" + rootId : "win:" + thread
    readonly property var messages: {
        if (!key) return []
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[key] || []
    }
    // The backend keeps the opened conversation loaded and live.
    property string openedKey: ""
    property bool openedChannel: false
    property string openedThread: ""
    property string openedRoot: ""
    property bool marked: false
    function release() {
        if (!openedKey) return
        if (openedChannel) backend.closeThreadWindow(openedThread, openedRoot)
        else backend.closeChatWindow(openedThread)
        openedKey = ""
    }
    onKeyChanged: {
        release()
        marked = false
        if (!key) return
        openedKey = key; openedChannel = channel; openedThread = thread; openedRoot = rootId
        if (channel) backend.openThreadWindow(thread, rootId)
        else backend.openChatWindow(thread)
    }
    Component.onDestruction: release()
    onMessagesChanged: if (!marked && messages.length && hit) { marked = true; Qt.callLater(() => conv.showFound(hit.id, terms, "")) }

    Rectangle { z: 3; width: 0.67; height: parent.height; color: theme.pick("#E0E0E0", "#3D3D3D") }

    Conversation {
        id: conv
        anchors.fill: parent
        anchors.leftMargin: 0.67
        pane: true
        popout: !pane.channel
        threadPane: pane.channel
        paneTitle: ""
        chatName: pane.channel ? (pane.place ? pane.place.channel.name : "") : pane.chatName
        chatId: pane.channel ? pane.key : pane.thread
        threadRoot: pane.rootId
        threadChannel: pane.channel ? pane.thread : ""
        isGroup: pane.channel || pane.thread.endsWith("@thread.v2")
        teamId: pane.place ? pane.place.team.id : ""; teamName: pane.place ? pane.place.team.name : ""
        myName: backend.userName
        messages: pane.messages
        onClosePane: pane.closed()
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onDeleteMessage: id => backend.deleteMessage(id)
        onEditMessage: (id, text) => backend.editMessage(id, text)
    }

    // The header (over the conversation's own).
    Rectangle {
        z: 2
        x: 0.67; width: parent.width - 0.67; height: theme.headerHeight
        color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
        Avatar {
            x: 20.7 - 0.67; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: pane.channel ? (pane.place ? pane.place.team.name : "") : pane.chatName
            square: pane.channel; squareRadius: 4
            photoId: pane.channel ? (pane.place ? "team:" + pane.place.team.id : "") : (String(pane.thread).startsWith("48:") ? backend.userMri : "")
            group: !pane.channel && pane.thread.endsWith("@thread.v2")
        }
        Column {
            x: 64.7 - 0.67; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - actions.width - 16
            Text {
                width: parent.width; elide: Text.ElideRight
                text: pane.channel ? (pane.place ? pane.place.channel.name : "") : pane.chatName
                font.family: theme.font; font.pixelSize: pane.channel ? 14 : 18; font.weight: pane.channel ? Font.DemiBold : Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading
            }
            Text {
                visible: pane.channel
                width: parent.width; elide: Text.ElideRight
                text: pane.hit ? (pane.hit.subject || pane.hit.text || "") : ""
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
            }
        }
        Row {
            id: actions
            anchors.right: parent.right; anchors.rightMargin: 9.8; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                visible: pane.channel
                width: gtText.implicitWidth + 24; height: 32; radius: 4
                color: gth.hovered ? theme.hover : "transparent"
                Text { id: gtText; anchors.centerIn: parent; text: "Go to channel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: gth; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.goTo() }
                Accessible.role: Accessible.Button
                Accessible.name: "Go to channel"
            }
            component HeadButton: Rectangle {
                id: hb
                property string icon
                property string label
                signal clicked()
                width: 32; height: 31.3; radius: 4
                color: hbh.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: hb.icon; size: 20; color: theme.textStrong }
                HoverHandler { id: hbh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: hb.clicked() }
                ToolTip.visible: hbh.hovered; ToolTip.delay: 500; ToolTip.text: hb.label
                Accessible.role: Accessible.Button
                Accessible.name: hb.label
            }
            HeadButton { visible: pane.channel; icon: "open-window-20"; label: "Open in new window"; onClicked: pane.popOut() }
            HeadButton {
                id: moreButton
                icon: "more-horizontal-20"; label: pane.channel ? "More options" : "More chat options"
                onClicked: moreMenu.open()
                MenuPopup {
                    id: moreMenu
                    x: parent.width - width; y: parent.height + 4
                    items: pane.channel
                        ? [{ label: "Go to channel", icon: "channel-20" }, { label: "Open in new window", icon: "open-window-20" }, { label: "Copy link", icon: "link-20" }]
                        : [{ label: "Go to chat", icon: "chat-20" }, { label: "Open in new window", icon: "open-window-20", keys: "Ctrl+O" }, { label: "Mark as unread", icon: "mail-unread-20" }, { separator: true }, { label: "Copy link", icon: "link-20" }]
                    onPicked: i => {
                        close()
                        const l = items[i].label
                        if (l === "Go to chat" || l === "Go to channel") pane.goTo()
                        else if (l === "Open in new window") pane.popOut()
                        else if (l === "Mark as unread") backend.setChatUnread(pane.thread, true)
                        else if (l === "Copy link") backend.copyText(pane.channel
                            ? "https://teams.microsoft.com/l/message/" + encodeURIComponent(pane.thread) + "/" + pane.hit.id + "?parentMessageId=" + pane.rootId
                            : "https://teams.microsoft.com/l/message/" + encodeURIComponent(pane.thread) + "/" + pane.hit.id + "?context=%7B%22contextType%22%3A%22chat%22%7D")
                    }
                }
            }
            HeadButton { icon: "dismiss-20"; label: "Close"; onClicked: pane.closed() }
        }
    }
}
