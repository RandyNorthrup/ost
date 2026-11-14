import QtQuick
import QtQuick.Window

// Starting a chat in a window of its own (Settings ▸ General ▸ Starting
// chats: New window; measured on winpc, 2026-11-14): Teams' child window,
// 588 x 493, titled "New Message", with the new chat's To: row, its "You're
// starting a new conversation" note and the compose box. Once you send,
// the chat opens in its own chat window.
Window {
    id: win
    property bool pinned: false
    property var people: []
    signal search(string query)
    signal chosen(string oid, string name, string text)
    signal group(string oids, string topic, string text)
    title: "New Message"
    width: 588; height: 493
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    NewChat {
        id: form
        anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        people: win.people
        onSearch: q => win.search(q)
        onChosen: (oid, name, text) => win.chosen(oid, name, text)
        onGroup: (oids, topic, text) => win.group(oids, topic, text)
        onCancelled: win.close()
    }
    function formForTest() { return form }
}
