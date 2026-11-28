import QtQuick
import QtQuick.Window

// One of Teams' own apps in a window of its own: the app bar menu's "Open
// in new window" on Chat, Teams, Activity, Calls or Events (Teams' ECS
// core.allowedCoreAppsPopOut: simple collab, chat, channel, activity,
// calling, events; TASK-0241).
// - Teams' child-window title row titled with the app's name; no app bar.
// - Chat (Teams): its chat (team and channel) list and, beside it, the chat picked there (kept live
//   by the backend under "win:<chat>", whatever the main window shows).
// - Activity: the feed and, beside it, the item's chat.
// - Calls and Events: the app's page as in the main window; what they open
//   (a chat, a meeting) goes to the main window.
Window {
    id: win
    /// The app: "chat", "activity", "calls" or "events".
    property string app: "chat"
    property string appName: ""
    property bool pinned: false
    /// The main window shows chats and channels apart (Teams' split view).
    property bool splitView: false
    /// The main window has mentions (the list's Mentions quick view).
    property bool hasMentions: false
    property int mentionsUnread: 0
    /// The list's Copilot row (as the main window's).
    property bool showCopilot: false
    /// New chats always open in a window (the list leaves out New message in new window).
    property bool newChatInWindow: false
    /// The list's pills, sections and quick views as shown (harness wlist).
    function listForTest() {
        const l = side.item
        if (!l || !l.pillRows) return null
        return { chat: win.chatId, pills: l.pillRows.first.map(p => p.label), more: l.pillRows.second.map(p => p.label),
                 sections: l.sections.map(s => [s.folder ? s.folder.kind : s.kind, (s.rows || []).filter(r => r.type === "slice").map(r => r.label)]) }
    }
    /// The chat shown beside the list or the feed.
    property string chatId: ""
    property string chatName: ""
    signal openInMain(string kind, var data)
    readonly property string key: "win:" + chatId
    readonly property var messages: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[key] || []
    }
    readonly property var chats: backend.chatsJson ? JSON.parse(backend.chatsJson) : []
    title: appName
    // 946 x 593, as Teams opens them (measured on winpc 2026-11-20).
    width: 946; height: 593
    minimumWidth: 588; minimumHeight: 400
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    readonly property bool isChannel: chatId.endsWith("@thread.tacv2")
    function closeShown() { if (!chatId) return; if (isChannel) backend.closeChannelWindow(chatId); else backend.closeChatWindow(chatId) }
    function showChat(id, name) {
        if (id === chatId) return
        closeShown()
        chatId = id; chatName = name || ""
        if (!id) return
        if (isChannel) backend.openChannelWindow(id); else backend.openChatWindow(id)
    }
    onClosing: closeShown()

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }

    Item {
        id: body
        anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

        Loader {
            id: side
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            active: win.app === "chat" || win.app === "teams" || win.app === "activity"
            sourceComponent: win.app === "activity" ? activitySide : chatSide
        }
        Component {
            id: chatSide
            ChatList {
                // Teams' Chat window has the whole list (chats, teams and
                // channels), 280 wide.
                // (Split view's Chat window: chats only; Teams: teams and channels.)
                pane: win.app === "teams" ? "teams" : win.splitView ? "chats" : "combined"
                chats: win.chats
                teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
                currentId: win.chatId
                windowWidth: win.width
                onChatSelected: (id, name) => win.showChat(id, name)
                draftIds: (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).map(d => d.id)
                hasMentions: win.hasMentions
                mentionsUnread: win.mentionsUnread
                showCopilot: win.showCopilot
                onOpenCopilot: win.openInMain("copilot", {})
                onOpenMentions: win.openInMain("mentions", {})
                onOpenDrafts: win.openInMain("drafts", {})
                onOpenQuick: kind => win.openInMain("quick", { kind: kind })
                onNewChat: win.openInMain("newChat", {})
                // New items ▸ (the list's own New channel and New section
                // open here; the rest in the main window).
                newChatInWindow: win.newChatInWindow
                onNewChatWindow: win.openInMain("newChatWindow", {})
                onNewStorylinePost: win.openInMain("storyline", {})
                onJoinTeam: win.openInMain("joinTeam", {})
                onNewTeam: win.openInMain("newTeam", {})
                onOpenCommunities: win.openInMain("communities", {})
                onOpenChatWindow: (id, name, photo, presence) => win.openInMain("chatWindow", { id: id, name: name, photo: photo, presence: presence })
            }
        }
        Component {
            id: activitySide
            ActivityView {
                // Teams' Activity window keeps the feed 280 wide.
                width: 280
                items: backend.activityJson ? JSON.parse(backend.activityJson) : []
                onMarkAllRead: {
                    for (const it of items) if (it.unread) backend.markActivityItemRead(it.id)
                    backend.markActivityRead()
                }
                onNotificationSettings: win.openInMain("notificationSettings", {})
                onOpenItem: item => {
                    selectedId = item.id
                    backend.markActivityItemRead(item.id)
                    if (item.kind === "missedCall" || item.kind === "voicemail") {
                        win.openInMain("callsHistory", { filter: item.kind === "voicemail" ? "voicemail" : "missed" })
                        return
                    }
                    if (item.thread_id) {
                        const c = win.chats.find(c => c.id === item.thread_id)
                        win.showChat(item.thread_id, c ? c.name : (item.actor_name || ""))
                    } else if ((item.actor_mri || "").startsWith("8:orgid:")) {
                        win.openInMain("chatWith", { oid: item.actor_mri.slice(8), name: item.actor_name })
                    }
                }
                onChatWith: item => { if ((item.actor_mri || "").startsWith("8:orgid:")) win.openInMain("chatWith", { oid: item.actor_mri.slice(8), name: item.actor_name }) }
                onCallBack: item => { if ((item.actor_mri || "").startsWith("8:orgid:")) win.openInMain("callBack", { oid: item.actor_mri.slice(8), name: item.actor_name }) }
            }
        }
        // The chat beside the list or the feed.
        // More chat options ▸ View Copilot history, at the window's right.
        CopilotHistoryPane {
            id: history
            visible: chat.visible && chat.copilotHistoryOpen
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: visible ? 360 : 0
            onClosed: chat.copilotHistoryOpen = false
        }
        Conversation {
            id: chat
            visible: side.active && win.chatId !== ""
            anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: history.left }
            popout: true
            // Teams' Chat window keeps the chat's tabs row.
            windowTabs: true
            chatId: win.chatId
            chatName: win.chatName
            // (A 19:uni01_… one-on-one the chat list knows as such isn't.)
            isGroup: (win.chatId.endsWith("@thread.v2") || win.chatId.indexOf("meeting_") >= 0) && ((JSON.parse(backend.chatsJson || "[]").find(c => c.id === win.chatId) || {}).isGroup !== false)
            isChannel: win.isChannel
            myName: backend.userName
            messages: win.messages
            onCall: win.openInMain("call", { id: win.chatId, name: win.chatName })
            onVideoCall: win.openInMain("videoCall", { id: win.chatId, name: win.chatName })
            // Teams' "+" (Add a tab) beside the tabs: its picker opens in
            // this window, as Teams' does.
            onOpenTabPicker: (id, kind, team) => tabPicker.showTabs(id, kind, team)
            onUpdateTabRequested: t => tabConfig.startUpdate(t, chat.chatId, chat.teamId, chat.isChannel)
            onReact: (id, key, on) => backend.toggleReaction(id, key, on)
            onEditMessage: (id, text) => backend.editMessage(id, text)
            onDeleteMessage: id => backend.deleteMessage(id)
        }

        Loader {
            anchors.fill: parent
            active: win.app === "calls"
            sourceComponent: CallsView {
                calls: backend.callsJson ? JSON.parse(backend.callsJson) : []
                people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
                onSearchPeople: q => backend.searchPeople(q)
                onOpenChatWith: (mri, name) => win.openInMain("chatWithMri", { mri: mri, name: name })
                onCallPerson: (oid, name) => win.openInMain("callBack", { oid: oid, name: name })
            }
        }
        Loader {
            anchors.fill: parent
            id: eventsLoader
            active: win.app === "events"
            sourceComponent: EventsView {
                onToast: d => win.openInMain("toast", d)
                onJoinEvent: (url, title, start, end) => win.openInMain("joinEvent", { url: url, title: title, start: start, end: end })
                onOpenEventChat: (id, title) => win.openInMain("chat", { id: id, name: title })
                onViewMeetings: win.openInMain("calendar", {})
            }
        }
    }

    // Teams' Add a tab in this window: the picker, then the app's tab
    // configuration (Back returns to the picker). An app's details, Get
    // more apps and Manage apps go to the main window.
    AgentStore {
        id: tabPicker
        onOpenApp: id => { tabPicker.close(); win.openInMain("appDetails", { id: id, conversation: tabPicker.conversationId, channel: tabPicker.channel }) }
        onGetMoreApps: { tabPicker.close(); win.openInMain("store", {}) }
        onManageApps: { tabPicker.close(); win.openInMain("manageApps", { channel: tabPicker.channel }) }
        onPickTabApp: app => {
            tabPicker.close()
            tabConfig.start(app, tabPicker.conversationId, tabPicker.channel ? chat.teamId : "", tabPicker.channel)
        }
    }
    TabConfigDialog {
        id: tabConfig
        teamThread: chat.isChannel ? chat.teamThread : ""
        onBack: tabPicker.reopen()
        onSaved: chat.reloadTabs()
        onUpdated: tabId => { chat.tabRevision++; chat.reloadTabs() }
        onAbout: app => win.openInMain("appDetails", { id: app.id })
    }

    // Test hooks.
    function sideForTest() { return side.item }
    function conversationForTest() { return chat }
    function tabPickerForTest() { return tabPicker }
    function eventsForTest() { return eventsLoader.item }

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
