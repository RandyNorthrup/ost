import QtQuick
import QtQuick.Window

// A channel post's conversation in a window of its own: Teams' "Open
// conversation in new window" (measured on winpc, 2026-11-09, in OST Test
// Team > General): 588 x 493, titled "<team> | <channel>", with Teams'
// child-window title row over the post view (PostThread).
Window {
    id: win
    property string channelId: ""
    property string rootId: ""
    property string teamId: ""
    property string teamName: ""
    property string channelName: ""
    property string myName: ""
    property bool pinned: false
    signal agentStoreRequested(string channelId)
    readonly property alias post: view.post
    readonly property alias thread: view.thread
    readonly property alias replies: view.replies
    function send() { view.send() }
    function toggleFind() { view.toggleFind() }
    title: teamName + " | " + channelName
    width: 588; height: 493
    color: theme.channelPage
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    // Test hooks.
    function composeForTest() { return view.composeForTest() }
    function hostForTest() { return view.hostForTest() }
    function postItemForTest() { return view.postItemForTest() }
    function flickForTest() { return view.flickForTest() }
    function findPaneForTest() { return view.findPaneForTest() }
    function moreMenuForTest() { view.moreMenuForTest() }

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    PostThread {
        id: view
        anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        channelId: win.channelId; rootId: win.rootId
        teamId: win.teamId; teamName: win.teamName
        channelName: win.channelName; myName: win.myName
        onAgentStoreRequested: id => win.agentStoreRequested(id)
    }
}
