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
// `attendance`: a recap window's Attendance (Teams 26304 on winpc,
// 2026-11-23: openAttendanceTabInMeetingRecapOfChat, a new window while
// the recap is in one): 1283 x 730 like the recap window, titled with the
// meeting; the meeting chat's header, then straight to its Attendance
// report (no tab row, no messages or compose). Opening it again brings it
// forward; only the window's close closes it.
Window {
    id: win
    property string chatId: ""
    property string chatName: ""
    property string photoId: ""
    property string presence: ""
    property bool pinned: false
    /// Opened on the meeting chat's Attendance report.
    property bool attendance: false
    signal startCall(string chatId)
    signal startVideoCall(string chatId)
    signal shareScreen(string chatId)
    signal reportConcern(string chatId)
    readonly property string key: "win:" + chatId
    readonly property var messages: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[key] || []
    }
    title: chatName
    width: 588; height: 493
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    Component.onCompleted: {
        // (Sized once: a chat window already open keeps its size when its
        // Attendance is asked for.)
        if (attendance) { width = 1283; height = 730 }
        backend.openChatWindow(chatId)
    }
    onClosing: backend.closeChatWindow(chatId)

    /// Show the Attendance report (again, when the window is already open).
    function showAttendance() {
        attendance = true
        if (chat.meeting) chat.openAttendance("")
    }

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    // Open Copilot here too (Teams' pop-out chat header has it): its pane
    // at the window's right.
    CopilotPane {
        id: copilot
        open: chat.copilotOpen
        request: chat.copilotRequest
        ask: chat.copilotAsk
        anchors { top: titleRow.bottom; right: history.left; bottom: parent.bottom }
        width: open ? 360 : 0
        onClosed: chat.copilotOpen = false
        onOpenLink: url => {
            const m = /^https:\/\/teams\.microsoft\.com\/l\/message\/([^/?#]+)\/([0-9]+)(?:\?(.*))?/.exec(url)
            if (m && decodeURIComponent(m[1]) === win.chatId) chat.showFound(m[2], [], "")
            else if (!m) chat.openLink(url)
        }
    }
    // More chat options ▸ View Copilot history, in the same place.
    CopilotHistoryPane {
        id: history
        visible: chat.copilotHistoryOpen
        anchors { top: titleRow.bottom; right: parent.right; bottom: parent.bottom }
        width: visible ? 360 : 0
        onClosed: chat.copilotHistoryOpen = false
    }
    Conversation {
        id: chat
        anchors { top: titleRow.bottom; left: parent.left; right: copilot.left; bottom: parent.bottom }
        popout: true
        chatId: win.chatId
        chatName: win.chatName
        // (A 19:uni01_… one-on-one the chat list knows as such isn't.)
        isGroup: (win.chatId.endsWith("@thread.v2") || win.chatId.indexOf("meeting_") >= 0) && ((JSON.parse(backend.chatsJson || "[]").find(c => c.id === win.chatId) || {}).isGroup !== false)
        chatPhotoId: win.photoId
        chatPresence: win.presence
        myName: backend.userName
        messages: win.messages
        // (The report shows once the window knows the chat's meeting.)
        onMeetingChanged: if (win.attendance && meeting && !attendanceTab) openAttendance("")
        onCall: win.startCall(win.chatId)
        onVideoCall: win.startVideoCall(win.chatId)
        onShareScreen: win.shareScreen(win.chatId)
        onReportConcern: win.reportConcern(win.chatId)
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onEditMessage: (id, text) => backend.editMessage(id, text)
        onDeleteMessage: id => backend.deleteMessage(id)
    }

    // Test hooks.
    function conversationForTest() { return chat }
    function stateForTest() {
        const v = chat.attendanceViewForTest()
        return JSON.stringify({ title: win.title, w: win.width, h: win.height, attendance: win.attendance, tab: chat.tab,
                                tabRow: chat.windowTabs, meeting: chat.meeting ? chat.meeting.organizer_id || "?" : "",
                                report: v ? { y: v.mapToItem(win.contentItem, 0, 0).y, w: v.width, h: v.height } : null })
    }

    // Teams' picture viewer for this window's chat (its messages' pictures
    // and a personal chat's Photos tab), as the main window's.
    ImageLightbox {
        id: lightbox
        z: 50
        anchors.fill: parent
        onShowMessage: id => { if (chat.tab === "Photos") chat.tab = ""; chat.showFound(id, []) }
    }
    Connections {
        target: chat
        function onOpenImageViewer(list, i, m) {
            const d = new Date(m.time)
            const at = chat.daysAgo(d) === 0 ? qsTr("Today %1").arg(theme.time(d)) : chat.stamp(m.time)
            lightbox.show(list, i, m.sender || "", at, m.id)
        }
    }
}
