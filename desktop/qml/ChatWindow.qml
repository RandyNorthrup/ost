import QtQuick
import QtQuick.Window

// A chat in a window of its own: Teams' Open in new window from the chat's
// menu (measured on winpc, 2026-11-09, with OST group test).
// - 588 x 493, titled with the chat's name, Teams' child-window title row.
// - The chat's header (61, white, a #E0E0E0 line under it): the picture (32)
//   at 20, the name (18/25.7 bold) at 62 with Name group chat for groups;
//   at the right Meet now and its chevron, Find in chat and More chat
//   options; no tab row.
// - The chat and its compose as in the main window; what's written here is
//   sent to this chat whatever the main window shows (the backend keeps the
//   chat loaded and live under "win:<chat>").
Window {
    id: win
    property string chatId: ""
    property string chatName: ""
    property string photoId: ""
    property string presence: ""
    property bool pinned: false
    signal startCall(string chatId)
    signal startVideoCall(string chatId)
    readonly property string key: "win:" + chatId
    readonly property var messages: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[key] || []
    }
    title: chatName
    width: 588; height: 493
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    Component.onCompleted: backend.openChatWindow(chatId)
    onClosing: backend.closeChatWindow(chatId)

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    Conversation {
        id: chat
        anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        popout: true
        chatId: win.chatId
        chatName: win.chatName
        isGroup: win.chatId.endsWith("@thread.v2") || win.chatId.indexOf("meeting_") >= 0
        chatPhotoId: win.photoId
        chatPresence: win.presence
        myName: backend.userName
        messages: win.messages
        onCall: win.startCall(win.chatId)
        onVideoCall: win.startVideoCall(win.chatId)
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onEditMessage: (id, text) => backend.editMessage(id, text)
        onDeleteMessage: id => backend.deleteMessage(id)
    }

    // Test hooks.
    function conversationForTest() { return chat }
}
