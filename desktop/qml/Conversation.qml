import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// The open chat: header with tabs and actions, message list, compose box.
Rectangle {
    id: root
    property string chatName
    property var messages: []
    property bool busy
    signal send(string text)
    signal call()
    signal videoCall()
    property string chatPresence: ""
    /// Your own presence (the roster shows it on your row).
    property string myPresence: ""
    property string typingText: ""
    /// The typer whose avatar the typing indicator shows.
    property string typingAvatar: ""
    property string typingAvatarId: ""
    /// Channel conversations (posts) look different from chats in Teams.
    property bool isChannel: false
    property string teamName: ""
    /// The channel's team (its picture is the header's).
    property string teamId: ""
    /// The other person's id in a 1:1 chat, for the header picture.
    property string chatPhotoId: ""
    /// A group chat (a grey people picture, as in Teams).
    property bool isGroup: false
    /// Your name, for the participants list.
    property string myName: ""
    /// The open chat's id; unsent text is kept per chat as a draft.
    property string chatId: ""
    property string draftChat: ""
    /// Shown as a side pane (in the call window): a plain "Chat" header
    /// with a close button instead of the title, tabs and actions.
    property bool pane: false
    /// A chat in its own window (the chat menu's Open in new window): no
    /// tab row, and the compose sends to this chat rather than the open one.
    property bool popout: false
    /// The chat menu's Manage apps: the chat's apps in place of its
    /// messages (Teams keeps the Chat tab chosen) until a tab is picked.
    property bool manageApps: false
    signal getMoreApps()
    /// The side pane's title ("Chat"; a tab's conversation says
    /// "Conversation").
    property string paneTitle: "Chat"
    /// The pane header's measures: the call window's chat (title 16 bold at
    /// 16, close 44 from the end) or a tab's conversation (16/22 semibold
    /// at 20, close 32 x 21.3 at 20 from the end).
    property bool paneTitleSemibold: false
    property real paneTitleX: 16
    property real paneCloseRight: 44
    /// A channel post's thread shown as a chat (a tab's conversation): its
    /// root post. Sends reply in that thread; no draft or typing is kept.
    property string threadRoot: ""
    /// A Threads-layout channel's thread pane: "{N} replies" under the
    /// first message, and the compose's "Send to:".
    property bool threadPane: false
    /// The thread pane's "Last read" line: before the first reply after
    /// this id (where the thread was read to when it
    /// opened; 0 for none).
    property real threadLastReadAfter: 0
    property string threadChannel: ""
    /// The channel's layout: "PostReply" (Posts) or "Conversational"
    /// (Threads: a chat of thread starters, each thread in the side pane).
    property string channelLayout: ""
    readonly property bool threadsLayout: isChannel && channelLayout === "Conversational" && !threadRoot
    readonly property bool postsLayout: isChannel && !threadsLayout
    signal openThread(string rootId)
    // Threads layout (measured on winpc 2026-11-10): the conversation shows
    // each thread's first message as a chat bubble; under one with replies
    // "{N} reply/replies  Last reply {time}" with the last replier's 20 px
    // picture, opening the thread beside it.
    // A reply also sent to the channel shows there too, in its place, with
    // "Replied in thread: {first message}".
    function threadStarters(all) {
        const byRoot = {}
        for (const m of all) {
            const r = m.root_id || m.id
            if (!byRoot[r]) byRoot[r] = { root: null, replies: [] }
            if (m.id === r) byRoot[r].root = m; else byRoot[r].replies.push(m)
        }
        const out = []
        for (const m of all) {
            const r = m.root_id || m.id
            const g = byRoot[r]
            if (m.id === r) {
                const last = g.replies.length ? g.replies[g.replies.length - 1] : null
                // Unread: replies after the bookmark (Mark as unread) or,
                // without one, after where you read to (yours count too, as
                // in Teams).
                const after = m.thread_bookmark > 0 ? m.thread_bookmark : (m.thread_read_to || 0)
                const unread = after > 0 ? g.replies.filter(x => Number(x.id) > after).length : 0
                out.push(Object.assign({}, m, { thread_unread: unread, thread_replies: g.replies.length, thread_last: last ? last.time : "", thread_last_sender: last ? last.sender : "", thread_last_mri: last ? last.sender_mri : "", thread_last_text: last ? last.text : "", thread_last_id: last ? last.id : "", thread_last_mine: last ? !!last.mine : false, thread_repliers: g.replies.map(x => ({ name: x.sender, mri: x.sender_mri })) }))
            } else if (m.shared_in_main) {
                out.push(Object.assign({}, m, { thread_title: g.root ? (g.root.text || "").split("\n")[0] : "" }))
            }
        }
        return out
    }
    /// Channel tabs a message may link (a tab conversation's first post
    /// links its tab): [{id, name, icon}].
    property var linkedTabs: []
    signal openLinkedTab(string tabId)
    signal closePane()
    /// The call chat pane's tabs ([{key, label, badge, count, tip}]) and the
    /// one shown; picking one asks the call window to switch.
    property var paneTabs: []
    property string paneTab: ""
    signal paneTabPicked(string key)
    /// A standing note on the compose box and whether you can type (Teams'
    /// lobby chat banners).
    property string composeNote: ""
    /// A 1:1 peer's status: {text, html, pinned, ooo} (null when none).
    property var peerNote: null
    property var dismissedPeerNotes: ({})
    // Teams' banner over the compose box of a 1:1 (measured on winpc
    // 2026-11-11): the peer's status message when they set it to show when
    // people message them ("Status of {name}: {message}"), else "{name} is
    // out of office and may not respond".
    readonly property string peerNoteText: {
        const n = peerNote
        if (!n || isGroup || isChannel || isSelf) return ""
        if (n.pinned && n.text) return "Status of " + chatName + ": " + n.text
        if (n.ooo) return chatName + " is out of office and may not respond"
        return ""
    }
    readonly property bool peerNoteShown: peerNoteText !== "" && compose.visible && !dismissedPeerNotes[chatId + "|" + peerNoteText]
    property bool composeNoteMuted: false
    property bool composeDisabled: false
    /// Only Format and Send in the compose (Teams' lobby chat).
    property bool composeTextOnly: false
    /// No compose at all (people waiting read the lobby chat only).
    property bool readOnly: false
    /// No pictures beside others' messages.
    property bool noAvatars: false
    /// No header (the host draws its own).
    property bool hideHeader: false
    /// Teams' empty chat header (chat-pencil illustration and a title),
    /// shown while there are no messages; "" for none.
    property string emptyTitle: ""
    /// In a channel: reply to a post, and whether a new post is being written.
    signal sendReply(string rootId, string text)
    property bool posting: false
    // Keyboard shortcuts (Ctrl+R, Ctrl+F, Ctrl+J, Alt+P, Alt+1-9, Alt+Shift+O).
    // The chat's compose editor.
    readonly property Item input: compose.editor
    readonly property Item composeBox: compose
    function focusCompose() { if (compose.visible) input.forceActiveFocus() }
    function openFind() { finding = true; tab = "" }
    function jumpToNewest() { tab = ""; list.positionViewAtBeginning(); channelPosts.toEnd() }
    function toggleDetails() { participants.visible = !participants.visible }
    // A channel's tabs, as Teams lists them: Posts, Shared (its Files
    // tab), then the channel's own tabs in order (Page, Notes, apps).
    readonly property var channelTabs: {
        if (!isChannel || !backend.channelTabsJson) return []
        const r = JSON.parse(backend.channelTabsJson)
        if (r.channel !== chatId || !r.tabs) return []
        // In the channel's own order (Graph's sortOrderIndex); a dropped
        // tab shows in its new place until the list reloads.
        const tabs = r.tabs.filter(t => t.app !== "Files" && t.name !== "Files")
        const p = tabOrderPending
        if (p && p.channel === chatId) tabs.sort((a, b) => p.ids.indexOf(a.id) - p.ids.indexOf(b.id))
        return tabs
    }
    // Dragging a channel tab into a new place, as Teams (dnd-kit sortable;
    // measured on winpc 2026-11-09):
    // - only tabs that can move (not Posts or Shared) can be picked up;
    // - the tab leaves an empty slot and a card follows the pointer: white,
    //   radius 4, Fluent shadow8, padding 10, its name 14/20, 48 tall,
    //   from the tab's top;
    // - the movable tabs between slide aside (250 ms); fixed tabs stay;
    // - over a fixed tab the card shows Prohibited (12) at the press point
    //   + (10, 22), and a drop there does nothing; Esc cancels;
    // - a drop saves only the moved tab's order (as Move left/right).
    // Screen readers hear Teams' "Grabbed …", "Moved after … and before …",
    // "Tab dropped" and "Cancelled".
    property var tabOrderPending: null
    Connections { target: backend; function onChannelTabsJsonChanged() { root.tabOrderPending = null } }
    property int tabDragFrom: -1
    property int tabDragOver: -1
    property bool tabDragAnimate: false
    property bool tabDragCancelled: false
    property real tabDragX: 0
    property real tabDragY: 0
    property point tabDragPress: Qt.point(0, 0)
    readonly property bool tabDragCanDrop: tabDragOver < 0 || tabIsDraggable(tabDragOver)
    function tabIsDraggable(i) { const t = channelTabs[i]; return !!t && !!t.draggable && tabNames[i] === t.name }
    function tabW(i) { const it = tabRepeater.itemAt(i); return it && it.visible ? it.width : 0 }
    function tabShift(i) {
        const f = tabDragFrom, o = tabDragOver
        if (f < 0 || o < 0 || o === f) return 0
        if (i === f) {
            let s = 0
            if (o > f) for (let k = f + 1; k <= o; k++) s += tabW(k)
            else for (let k = o; k < f; k++) s -= tabW(k)
            return s
        }
        if (!tabIsDraggable(i)) return 0
        if (f < o && i > f && i <= o) return -tabW(f)
        if (o < f && i >= o && i < f) return tabW(f)
        return 0
    }
    function tabAnnounce(text) { tabs.Accessible.announce(text) }
    function tabDragStart(i, press) {
        tabDragCancelled = false
        tabDragPress = press
        tabDragAnimate = true
        tabDragFrom = i; tabDragOver = i
        const it = tabRepeater.itemAt(i)
        tabDragX = it.x; tabDragY = 0
        const movable = tabNames.map((n, k) => k).filter(k => tabIsDraggable(k))
        const name = tabNames[i]
        tabAnnounce(i === 0 || movable.indexOf(i) === 0 ? "Grabbed " + name + ". First draggable tab."
            : i === tabNames.length - 1 ? "Grabbed " + name + ". Last draggable tab." : "Grabbed " + name)
    }
    function tabDragMove(i, t) {
        if (tabDragCancelled || tabDragFrom < 0) return
        const it = tabRepeater.itemAt(i)
        tabDragX = it.x + t.x; tabDragY = t.y
        // Over: the tab (where it was laid out) under the pointer.
        const px = it.x + tabDragPress.x + t.x
        let over = -1
        for (let k = 0; k < tabNames.length; k++) {
            const o = tabRepeater.itemAt(k)
            if (o && o.visible && px >= o.x && px < o.x + o.width) { over = k; break }
        }
        if (over === tabDragOver) return
        tabDragOver = over
        if (over < 0) return
        const n = tabNames.length
        if (over === 0) tabAnnounce("Moved to beginning of draggable tabs")
        else if (over === n - 1) tabAnnounce("Moved to end of draggable tabs")
        else {
            const rest = tabNames.filter((x, k) => k !== over), right = i < over
            tabAnnounce("Moved after " + (right ? rest[i] : rest[over - 1]) + " and before " + (right ? rest[i + 1] : rest[over]))
        }
    }
    function tabDragEnd() {
        const f = tabDragFrom, o = tabDragOver
        if (tabDragCancelled || f < 0) { tabDragCancelled = false; return }
        tabDragAnimate = false
        if (o >= 0 && o !== f && tabIsDraggable(o) && tabIsDraggable(f)) {
            const movable = tabNames.map((n, k) => k).filter(k => tabIsDraggable(k))
            const ids = channelTabs.map(t => t.id)
            const moved = ids.splice(f, 1)[0]
            ids.splice(o, 0, moved)
            tabOrderPending = { channel: chatId, ids: ids }
            backend.channelTabChange("to", teamId, chatId, moved, String(movable.indexOf(o)))
        }
        tabDragFrom = -1; tabDragOver = -1
        tabAnnounce("Tab dropped")
    }
    function tabDragCancel() {
        tabDragCancelled = true
        tabDragAnimate = false
        tabDragFrom = -1; tabDragOver = -1
        tabAnnounce("Cancelled")
    }
    Shortcut { sequence: "Escape"; enabled: root.tabDragFrom >= 0; onActivated: root.tabDragCancel() }
    readonly property var tabNames: isChannel ? (channelTabs.length ? channelTabs.map((t, i) => i === 0 && threadsLayout ? "Conversation" : t.name) : [threadsLayout ? "Conversation" : "Posts", "Shared"])
        // Teams (worker Ct): Storyline only in 1:1 chats.
        // Meeting chats: Chat, Shared, Recap (Teams lists Attendance, Breakout
        // Rooms, Q&A and Meeting Whiteboard after them, under "+4").
        // Attendance joins them once its card is opened (Teams moves it out
        // of "+4" then).
        : isSelf ? ["Chat", "Shared", "Storyline"] : isMeetingChat ? ["Chat", "Shared", "Recap"].concat(attendanceTab ? ["Attendance"] : []) : isGroup ? ["Chat", "Shared", "Notes", "Recap"] : ["Chat", "Shared", "Notes", "Recap", "Storyline"]
    readonly property bool isMeetingChat: chatId.indexOf("19:meeting_") === 0
    // Teams' conversation margins by pane width (measured on winpc at
    // 452-892 px): each row starts 14 in under 480 px, else 32; its icon
    // or avatar sits at the row start (+6 for event icons), its content 40
    // in; on the right, 28 under 480, 32 under 720, 72 from 720. The
    // compose box keeps 14 / 32 / 72 on both sides.
    // Settings ▸ Chats ▸ Message density: Compact (measured on winpc
    // 2026-11-10): no bubbles, every message on the left; a group starts
    // with the 36 px picture at 16 (yours too, with a 2 x 32 brand bar at 4)
    // and "Name  time" (12/16) at 64; the text (14/20) 17 under it.
    readonly property bool compact: { const s = backend.settingsJson ? JSON.parse(backend.settingsJson) : {}; return !isChannel && !pane && (s.props || {}).messageDensity === "COMPACT" }
    readonly property real gutL: width < 480 ? 14 : 32
    // Without pictures (a lobby's view of the organizers' messages) the
    // bubbles start 16.7 in from the row (Teams' waiting-side Lobby pane).
    readonly property real gutContent: noAvatars ? gutL + 16.7 : gutL + 40
    readonly property real gutR: width < 480 ? 28 : width < 720 ? 32 : 72
    readonly property real composeGut: width < 480 ? 14 : width < 720 ? 32 : 72
    // While a meeting is live, Teams draws its chat's header in the dark
    // palette (entity-header, measured on winpc): #2F2F4A, white title,
    // icons and tab line, 75 % white for the other tabs, no hover fill.
    readonly property bool liveBand: isMeetingChat && callGoing && !pane
    readonly property color hdrText: liveBand ? "#FFFFFF" : theme.text
    readonly property color hdrStrong: liveBand ? "#FFFFFF" : theme.textStrong
    readonly property color hdrSoft: liveBand ? Qt.rgba(1, 1, 1, 0.75) : theme.textSecondary
    /// When the live meeting started (its newest "started" call event).
    readonly property var liveSince: {
        if (!liveBand) return null
        const s = messages.filter(m => m.kind === "call" && m.call_state === "started")
        return s.length ? new Date(s[s.length - 1].time) : null
    }
    // When this chat was opened (for GIF autoplay).
    property date openedAt: new Date()
    // The header's breakpoints (Teams 7.3: the header's own width). Below
    // 720 the roster count moves into ··· as Participants; below 640 the
    // tabs become a dropdown under a 14 px title, and chat details moves
    // into ··· as "In this chat" (measured at 604: only Find stays inline);
    // below 480 Find goes too. Live roster avatars show from 834.
    function openChatMenuForTest() { chatMenu.open() }
    function funPickerForTest() { return msgHost.emojiPicker }
    function customEmojiAddForTest() { return msgHost.customEmojiAdd }
    function composeMediaForTest() { return compose.mediaInUse() }
    function closeChatMenuForTest() { chatMenu.close() }
    function toggleFind() { root.finding = !root.finding; if (root.finding) root.tab = "" }
    readonly property bool headerNarrow: width < 640
    readonly property bool rosterInMenu: width < 720 && isGroup && !isChannel && !isSelf
    // A Threads-layout channel's Open threads button sits before Find; under
    // 640 its channel details move to the ··· menu (Teams, measured).
    readonly property int contextInline: pane ? 2 : threadsLayout ? (width >= 640 ? 2 : 1) : isChannel ? 2 : width >= 640 ? 2 : width >= 480 ? 1 : 0
    readonly property int threadsButton: threadsLayout && !pane && tab === "" ? 1 : 0
    /// Whether this channel's threads pane is open (Main), and its toggle.
    property bool threadsOpen: false
    /// The chat's scheduled messages (backend.scheduledJson), shown after
    /// the rest as Teams shows them: a grey bubble, "Sending on {day} at
    /// {time}", the clock (Scheduled).
    property var scheduled: []
    readonly property var scheduledItems: root.pane ? [] : root.scheduled.map(s => Object.assign({}, s.message, { id: "scheduled:" + s.id, draft_id: s.id, scheduled_at: s.send_at_ms, mine: true, kind: "message", reactions: [] }))
    /// The thread the threads pane shows (its first message is outlined).
    property string openThreadRoot: ""
    signal toggleThreads()
    // Right to left from ···: the inline context buttons (32 each), a
    // 16 px divider, then the action items.
    readonly property real contextLeft: width - 43 - 32 * (contextInline + threadsButton)
    // A meeting chat's Meeting details (inline from 640 wide, else in ···).
    readonly property bool meetingDetailsShown: isMeetingChat && !!meeting && !!meeting.ical_uid && !meeting.cancelled
    readonly property bool meetingDetailsInline: meetingDetailsShown && width >= 640
    readonly property real actionRight: contextLeft - 16 - (meetingDetailsInline ? 32 : 0)
    // Move to section ▸ (Teams' chat ···): Favorites and your sections the
    // chat isn't in, a divider, New section.
    readonly property var folderList: backend.foldersJson ? (JSON.parse(backend.foldersJson).folders || []) : []
    readonly property string sectionHolder: { const f = folderList.find(f => (f.kind === "Favorites" || f.kind === "UserCreated" || f.kind === "UserDefined") && f.items.indexOf(chatId) >= 0); return f ? f.id : "" }
    function moveTargets() {
        const out = folderList.filter(f => (f.kind === "Favorites" || f.kind === "UserCreated" || f.kind === "UserDefined") && f.id !== sectionHolder)
            .map(f => ({ label: f.title, to: f.id }))
        if (out.length) out.push({ separator: true })
        out.push({ label: "New section", icon: "folder-add-20", newSection: true })
        return out
    }
    SectionDialog { id: headerSectionDialog; existing: root.folderList.map(f => f.title) }
    /// Teams' Meeting details (calendar.meetingDetails) for this chat's meeting.
    signal openMeetingDetails(string joinUrl, string icalUid, string start)
    // The meeting chat's meeting (join link, iCalUid, cancelled).
    readonly property var meeting: isMeetingChat && backend.chatMeetingJson ? JSON.parse(backend.chatMeetingJson) : null
    // Teams' Attendance card shows to the meeting's organizer and
    // co-organizers (not for town halls), under each meeting's end.
    readonly property string myOid: (backend.userMri || "").replace("8:orgid:", "")
    readonly property bool canSeeAttendance: !!meeting && meeting.meeting_type !== "Broadcast" && !!myOid
        && (meeting.organizer_id === myOid || (meeting.co_organizer_ids || []).indexOf(myOid) >= 0)
    property bool attendanceTab: false
    property string attendanceCall: ""
    function openAttendance(call) { attendanceCall = call; attendanceTab = true; tab = "Attendance" }
    // A channel meeting's report, over the channel (Teams' channel
    // Attendance view): {organizer, message, call}.
    property var channelAttendance: null
    // Load a channel's tabs once it's known which team it's in.
    readonly property string tabsKey: isChannel && teamId && chatId ? teamId + "|" + chatId : ""
    onTabsKeyChanged: if (tabsKey) backend.channelTabsLoad(teamId, chatId, chatName)
    // The channel tab showing its page in place, as Teams embeds it: the
    // Page (the channel's Loop page), signed in with OST's web profile
    // (scope decision 2026-11-07: what Teams embeds may be embedded).
    // Notes (OneNote's officeunihost page) needs a TeamsJS host first
    // (TASK-0053).
    readonly property var webTab: channelTabs.find(t => t.name === tab && t.content_url && t.kind === "ChannelPage") || null
    function openTab(i) { if (i < tabNames.length) tab = i === 0 ? "" : tabNames[i] }
    readonly property bool composeFocused: input.activeFocus
    readonly property bool detailsOpen: participants.visible
    function attachFile() { if (compose.visible) root.openAttach(compose.attachButton()) }
    function replyForTest(text) { return channelPosts.replyToNewestForTest(text) }
    // Test hooks for the compose box.
    function setComposeText(t) { root.setPlain(t) }
    function composeText() { return root.plainText() }
    // The compose box is rich text (Teams formats as you type); these read
    // and write it as plain text.
    // Test hook: show the hover bar on this message (--actions-test).
    property string forceBarId: ""
    // The message being quoted in the compose box (Reply with quote).
    property var quoting: null
    function replyWithQuote(m) {
        quoting = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.quote_text || m.text || "" }
        input.forceActiveFocus()
    }
    signal openChatSettings()
    /// Teams' app details for an app (a shared app's card, or a
    /// teams.microsoft.com/l/app/ link).
    signal openAppDetails(string appId)
    /// Teams' Share form for an app (a shared app's card).
    signal shareApp(string appId)
    /// Open an app OST has (a shared app's card ▸ Open).
    signal openAppById(string appId)
    /// Teams' "Add agent to the chat / channel" Store for a conversation.
    signal openAgentStore(string conversationId, bool channel)
    /// Links in messages: Teams opens its app links as the app's details.
    function openLink(link) {
        const m = /^https:\/\/teams\.microsoft\.com\/l\/app\/([0-9A-Za-z._-]+)/.exec(link)
        if (m) root.openAppDetails(decodeURIComponent(m[1]))
        else Qt.openUrlExternally(link)
    }
    signal scheduleMeeting()
    /// The header's More chat options: Open in new window (Ctrl+O), Share
    /// screen (Ctrl+Shift+E: a call to the chat, sharing once it connects)
    /// and a meeting chat's Report a concern.
    signal openInNewWindow()
    signal shareScreen()
    signal reportConcern()
    readonly property bool chatShortcuts: visible && !isChannel && !pane && !popout && chatName.length > 0
    Shortcut { sequence: "Ctrl+O"; enabled: root.chatShortcuts; onActivated: root.openInNewWindow() }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: root.chatShortcuts && !root.isSelf && !root.isMeetingChat; onActivated: root.shareScreen() }
    function chatMenuForTest() { return chatMenu }
    function removeHistoryForTest() { return removeHistoryAsk }
    // Teams' "Remove chat history?" (as the chat list's).
    ConfirmDialog {
        id: removeHistoryAsk
        width: 600
        title: "Remove chat history?"
        body: "This will remove the chat from your list and search. It affects you only."
        confirmText: "Remove"
        onConfirmed: backend.removeChatHistory(root.chatId)
    }
    // Go to a message (a quote card's target), if it is loaded.
    // The chat's call: one going on (a start with no end), whether we're in
    // it, and Teams' 20-member limit for calls in group chats.
    // The thread's liveness entry (the chat list's liveCall) says so even
    // when the call's start isn't among the loaded messages.
    readonly property var liveCall: { const c = (backend.chatsJson ? JSON.parse(backend.chatsJson) : []).find(c => c.id === root.chatId); return c && c.liveCall ? c.liveCall : null }
    readonly property bool chatMuted: { const c = (backend.chatsJson ? JSON.parse(backend.chatsJson) : []).find(c => c.id === root.chatId); return !!(c && c.muted) }
    // Watching the chat's call while we aren't in it (Teams subscribes to
    // its conversation without joining): who is in it, for the header.
    readonly property var liveRosterPeople: JSON.parse(backend.chatLiveRosterJson || "[]")
    // A channel's live meeting (its newest start with no end): watched the
    // same way, for its post's banner.
    readonly property var channelLiveMeeting: !root.isChannel ? null
        : root.messages.filter(m => m.kind === "call" && m.call_state === "started" && m.call_active && m.call_conversation_url).pop() || null
    readonly property var watchTarget: root.liveCall && root.liveCall.conversation_url
        ? { url: root.liveCall.conversation_url, id: root.liveCall.call_id || "" }
        : root.channelLiveMeeting ? { url: root.channelLiveMeeting.call_conversation_url, id: root.channelLiveMeeting.call_id || "" } : null
    readonly property string watchKey: root.watchTarget && !root.inThisCall && !root.pane
        ? root.chatId + "|" + root.watchTarget.url : ""
    onWatchKeyChanged: watchTimer.restart()
    Component.onCompleted: if (!root.pane) watchTimer.restart()
    Timer {
        id: watchTimer; interval: 300
        onTriggered: if (!root.pane) root.watchKey
            ? backend.watchChatCall(root.chatId, root.watchTarget.url, root.watchTarget.id)
            : backend.watchChatCall("", "", "")
    }
    /// Join a meeting through Teams' pre-join screen.
    signal joinMeetingRequested(string url, string title)
    /// Teams' post view (a channel post's thread): opened from "See
    /// details" under an ended meeting's post.
    function openPostView(rootId) { root.postViewRoot = rootId }
    /// The post open in Teams' post view, over the channel ("" for none).
    property string postViewRoot: ""
    function joinLiveMeetingForTest() { return channelPosts.joinLiveForTest() }
    function seeDetailsForTest() { return channelPosts.seeDetailsForTest() }
    readonly property bool callGoing: !!root.liveCall || root.messages.some(m => m.kind === "call" && m.call_state === "started" && m.call_active)
    readonly property bool inThisCall: backend.callState !== "" && backend.callThreadId === root.chatId
    readonly property bool callsDisabled: (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson).length : 0) > 20
    // A member's name by MRI: call events name people only by MRI, and
    // Teams shows them by their roster name.
    function memberName(mri) {
        const m = (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []).find(p => (p.mri || "").toLowerCase() === String(mri || "").toLowerCase())
        return m ? m.name : ""
    }
    // Card types drawn natively (Teams' supported set, so far).
    readonly property var cardKinds: ["application/vnd.microsoft.card.adaptive", "application/vnd.microsoft.card.hero", "application/vnd.microsoft.card.thumbnail",
        "application/vnd.microsoft.teams.card.list", "application/vnd.microsoft.teams.card.o365connector"]
    function jumpToMessage(id) {
        const i = (list.model || []).findIndex(m => m.id === id)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
    }
    function tonesForTest(id) { msgHost.reactionPicker.tonesForTest(id) }
    function customizeForTest() { msgHost.customizeReactions.open() }
    function customizeSlotForTest(i) { msgHost.customizeReactions.pickForTest(i) }
    function customizeToneForTest(t) { msgHost.customizeReactions.setTone(t) }
    function closeCustomizeForTest() { msgHost.customizeReactions.close() }
    // Test hook: the in-place editor, while one is open.
    function editBoxForTest() {
        for (let i = 0; i < list.count; i++) {
            const d = list.itemAtIndex(i)
            if (d && d.editingThis) return d.editBoxForTest()
        }
        return null
    }
    // Test hooks for channel posts: show a message's hover bar; open its
    // ··· menu (post or reply).
    function forceChannelBarForTest(id) { msgHost.forceChannelBarId = id }
    function channelMenuForTest(m, context) { openMessageMenu(m, channelPosts, false, channelPosts.width - 300, 120, context) }
    function composeForTest() { return compose }
    function hoverTitleForTest(on) { if (on) theme.hoverCard.hoverEnter(root.chatPhotoId, title, root.chatName, root.chatPresence); else theme.hoverCard.hoverLeave() }
    function channelPostsForTest() { return channelPosts }
    /// Start an @mention of a bot just added here (Teams puts "@{bot}" in
    /// the compose box).
    function mentionBot(name, mri) { compose.focusEditor(); compose.insertMentionOf({ mri: mri, name: name }) }
    function closePickerForTest() { msgHost.reactionPicker.close() }
    function closeMessageMenuForTest() { msgHost.messageMenu.close() }
    function forwardDialogForTest() { return msgHost.forwardDialog }
    function reportDialogForTest() { return msgHost.reportDialog }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function plainText() { return input.getText(0, input.length) }
    function setPlain(t) { input.clear(); if (t) input.insert(0, root.escapeHtml(t)) }
    function attachForTest(paths) { root.pendingFiles = paths }
    function openEmojiForTest() { msgHost.emojiPicker.open() }
    function formatForTest(a, b, tag) { input.select(a, b); root.wrapSelection(tag) }
    function openParticipantsForTest() { participants.visible = true }
    function sendForTest() { root.sendCompose() }
    function chatAppsForTest() { return chatApps }
    function insertTextForTest(t) { compose.insertText(t) }
    onChatIdChanged: {
        smartReplies = null
        if (chatId && !isChannel) backend.loadSmartReplies(chatId)
        postViewRoot = ""
        channelAttendance = null
        attendanceTab = false; attendanceCall = ""
        landing = true
        manageApps = false
        tabExpanded = false
        tabConversationTab = null
        openedAt = new Date()
        tab = ""; finding = false; findMark = { id: "", terms: [] }; seekId = ""; participants.visible = false; posting = false
        editingId = ""
        // A thread pane keeps no draft (its channel's draft is the channel's).
        if (root.threadRoot) { draftChat = ""; root.setPlain(""); return }
        if (draftChat) backend.setDraft(draftChat, root.plainText())
        root.setPlain(chatId ? backend.draftFor(chatId) : "")
        draftChat = chatId
    }
    // Keep the draft current while typing (so it survives a quit).
    Timer {
        id: draftSave
        interval: 1000
        onTriggered: if (root.draftChat) backend.setDraft(root.draftChat, root.plainText())
    }
    /// Your own notes chat: Teams drops the call and people buttons and
    /// shows only the Chat, Shared and Storyline tabs.
    property bool isSelf: false
    signal typing()
    signal react(string messageId, string key, bool on)
    // The message actions' host (menus, pickers, who reacted, edit state).
    MessageHost {
        id: msgHost
        messages: root.messages
        isGroup: root.isGroup; isChannel: root.isChannel
        teamId: root.teamId; teamName: root.teamName; chatName: root.chatName
        defaultBox: compose
        onQuoteRequested: m => root.replyWithQuote(m)
        onReactRequested: (id, key, on) => root.react(id, key, on)
        onDeleteRequested: id => root.deleteMessage(id)
        onOpenChatSettings: root.openChatSettings()
        canPopOut: root.isChannel && !root.pane
        onThreadWindowRequested: m => root.openThreadWindow(m)
    }
    // Open conversation in new window: the post's thread in a window of
    // its own, one per post (opening it again brings that one forward).
    Component { id: threadWindowComponent; ThreadWindow {} }
    property var threadWindows: ({})
    function openThreadWindow(m) {
        const rootId = m.root_id || m.id
        const key = root.chatId + ";" + rootId
        const open = root.threadWindows[key]
        if (open) { open.raise(); open.requestActivate(); return open }
        const w = threadWindowComponent.createObject(null, { channelId: root.chatId, rootId: rootId, teamId: root.teamId, teamName: root.teamName, channelName: root.chatName, myName: root.myName })
        const all = Object.assign({}, root.threadWindows); all[key] = w; root.threadWindows = all
        w.agentStoreRequested.connect(id => root.openAgentStore(id, true))
        w.closing.connect(() => { const rest = Object.assign({}, root.threadWindows); delete rest[key]; root.threadWindows = rest; w.destroy() })
        w.show()
        return w
    }
    property alias editingId: msgHost.editingId
    property alias forceWhoId: msgHost.forceWhoId
    property alias forceWhoOverflowId: msgHost.forceWhoOverflowId
    readonly property alias quickReactions: msgHost.quickReactions
    function startEdit(m) { msgHost.startEdit(m) }
    function openEmojiFor(box) { msgHost.openEmojiFor(box) }
    function openReactionPicker(id, anchor) { msgHost.openReactionPicker(id, anchor) }
    function openMessageMenu(m, anchor, rightClick, px, py, context) { msgHost.openMessageMenu(m, anchor, rightClick, px, py, context) }
    function commonKey(id) { return msgHost.commonKey(id) }
    signal editMessage(string messageId, string text)
    signal deleteMessage(string messageId)
    // Set while the compose box edits an existing message.

    // Newest first (the list grows upward), with Teams' grouping: a message
    // joins the previous one when the same person sent it under 5 minutes
    // later. latestMine marks your newest message for the sent tick.
    // Teams' relative dates: the time alone today, then "Yesterday 3:05 PM",
    // the weekday within a week, and the date beyond that.
    function daysAgo(d) { return msgHost.daysAgo(d) }
    function stamp(t) {
        const d = new Date(t), n = daysAgo(d), time = Qt.formatTime(d, "h:mm AP")
        if (n === 0) return time
        if (n === 1) return "Yesterday " + time
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd") + " " + time
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "M/d") + " " + time
        return Qt.formatDate(d, "M/d/yyyy") + " " + time
    }
    function dayLabel(t) { return msgHost.dayLabel(t) }

    function annotate(msgs) {
        // A call's start shows only for Meet now ("… started a meeting.").
        const out = msgs.filter(m => !(m.kind === "call" && m.call_state === "started" && !m.call_huddle)).map(m => Object.assign({}, m))
        let unreadSeen = false, lastReadPlaced = false
        for (let i = 0; i < out.length; i++) {
            const prev = i > 0 ? out[i - 1] : null, cur = out[i]
            // A day divider where the day changes (not above the very first
            // message shown), and the "Last read" line where unread begins.
            const day = new Date(cur.time).toDateString()
            cur.dayDivider = prev && new Date(prev.time).toDateString() !== day ? root.dayLabel(cur.time) : ""
            cur.lastRead = root.threadPane
                ? root.threadLastReadAfter > 0 && !lastReadPlaced && cur.id !== root.threadRoot && Number(cur.id) > root.threadLastReadAfter
                : cur.first_unread === true && i > 0
            lastReadPlaced = lastReadPlaced || cur.lastRead
            // Unread when the chat opened, or arrived since (Teams autoplays
            // GIFs only in those; the rest show still with a play button).
            unreadSeen = unreadSeen || cur.first_unread === true
            cur.autoplay = unreadSeen || new Date(cur.time) > root.openedAt
            if (!prev) continue
            const gap = new Date(cur.time) - new Date(prev.time)
            // Channel posts each get their own card and header; a divider
            // also starts a new group.
            const row = k => k === "call" || k === "event"
            cur.grouped = !root.isChannel && !row(cur.kind) && !row(prev.kind)
                && !cur.dayDivider && !cur.lastRead && !cur.scheduled_at && !prev.scheduled_at
                && cur.sender === prev.sender && cur.mine === prev.mine && gap >= 0 && gap < 5 * 60 * 1000
        }
        // Whether the next message continues this one's group (Teams squares
        // the corners where grouped bubbles meet).
        for (let i = 0; i < out.length; i++) out[i].groupNext = i + 1 < out.length && out[i + 1].grouped === true
        // Teams' receipts: your newest message carries the sent tick until
        // it is read; the newest one the other person has read gets the eye.
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind === "message" && !out[i].send_state && !out[i].scheduled_at) { out[i].latestMine = true; break }
        }
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind === "message" && out[i].seen) { out[i].latestSeen = true; break }
        }
        return out.reverse()
    }
    color: theme.surface

    TeamAppsView {
        id: chatApps
        visible: root.manageApps && !root.isChannel
        z: 5
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        chatId: visible ? root.chatId : ""
        onGetMoreApps: root.getMoreApps()
        Rectangle { anchors.fill: parent; z: -1; color: theme.surface }
    }

    // Header
    Item {
        id: header
        width: parent.width; height: root.hideHeader ? 0 : theme.headerHeight + (root.pane && root.paneTabs.length ? 47.2 : 0)
        visible: root.chatName.length > 0 && !root.tabExpanded && !root.hideHeader
        Rectangle {
            visible: root.liveBand
            anchors.fill: parent
            color: "#2F2F4A"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
        }
        // Where the toolbar starts (its leftmost shown item, less Teams'
        // 4 px toolbar padding): the tabs fit before it.
        readonly property real toolbarLeft: {
            let x = root.actionRight
            for (const it of [liveDuration, bandRoster, callPrimary, oneToOnePeople, joinButton, meetNow, meetingJoin, rosterCount])
                if (it && it.visible) x = Math.min(x, it.x)
            return x - 4
        }
        Item {
            visible: root.pane
            width: parent.width; height: theme.headerHeight
            Text {
                x: root.paneTitleX; anchors.verticalCenter: parent.verticalCenter
                text: root.paneTitle
                font.family: theme.font; font.pixelSize: 16; font.weight: root.paneTitleSemibold ? Font.DemiBold : Font.Bold
                color: theme.text
            }
            HeaderAction {
                x: parent.width - root.paneCloseRight; icon: "dismiss-20"; Accessible.name: "Close " + root.paneTitle.toLowerCase()
                onClicked: root.closePane()
            }
        }
        // The call chat pane's tabs (Teams' Everyone | Lobby, measured on
        // winpc 2026-11-11): a 46.5 row 8 in, a 0.67 #E0E0E0 line under it;
        // tabs padding 12 10, 14/20 #424242 (600 #242424 chosen) with a 3 px
        // brand bar 12 in from each side at the bottom; Lobby's count badge
        // 8 after it (20 tall, 12/600, pill: #4F52B2 on #E8EBFA, or #616161
        // on #F0F0F0 at 0).
        Item {
            visible: root.pane && root.paneTabs.length > 0
            y: theme.headerHeight
            width: parent.width; height: 47.2
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio); color: theme.divider }
            Row {
                x: 8
                Repeater {
                    model: root.paneTabs
                    Item {
                        id: ptab
                        required property var modelData
                        readonly property bool chosen: root.paneTab === modelData.key
                        width: ptRow.implicitWidth + 24; height: 46.5
                        Row {
                            id: ptRow
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ptab.modelData.label
                                font.family: theme.font; font.pixelSize: 14; font.weight: ptab.chosen ? Font.DemiBold : Font.Normal
                                color: ptab.chosen ? theme.text : theme.textStrong
                            }
                            Rectangle {
                                visible: ptab.modelData.badge !== undefined
                                anchors.verticalCenter: parent.verticalCenter
                                width: badgeText.implicitWidth + 12; height: 20; radius: 10
                                color: (ptab.modelData.count || 0) > 0 ? theme.pick("#E8EBFA", "#2F2F4A") : theme.pick("#F0F0F0", "#2E2E2E")
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: ptab.modelData.badge || ""
                                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: (ptab.modelData.count || 0) > 0 ? theme.brandForeground1 : theme.textSecondary
                                }
                            }
                        }
                        Rectangle {
                            visible: ptab.chosen
                            anchors.bottom: parent.bottom; x: 12; width: parent.width - 24; height: 3; radius: 1.5
                            color: theme.brand
                        }
                        HoverHandler { id: ptH; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.paneTabPicked(ptab.modelData.key) }
                        ToolTip.visible: ptH.hovered && !!ptab.modelData.tip; ToolTip.delay: 500; ToolTip.text: ptab.modelData.tip || ""
                        Accessible.role: Accessible.PageTab
                        Accessible.name: ptab.modelData.label + (ptab.modelData.badge ? " " + ptab.modelData.badge : "")
                        Accessible.selected: ptab.chosen
                    }
                }
            }
        }
        Item {
        visible: !root.pane
        anchors.fill: parent
        Avatar {
            visible: !root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: root.chatName; presence: root.chatPresence
            photoId: root.chatPhotoId
            opensProfile: !root.isGroup
            group: root.isGroup && !root.chatPhotoId
            // Teams: the calendar glyph filling a 32 px #C5CBFA circle.
            meeting: root.isMeetingChat
            meetingGlyph: 32
        }
        Avatar {
            visible: root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            size: 32; square: true; squareRadius: 2
            name: root.teamName
            initialsText: root.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: root.teamId ? "team:" + root.teamId : ""
        }
        // Title, tabs and actions at Teams desktop's measured positions.
        Text {
            id: title
            x: 61
            // Below 640 Teams sets the title 14/700 (line 20) at 10, the
            // tab dropdown under it.
            y: root.headerNarrow && !root.isChannel ? 10 : (parent.height - height) / 2
            height: root.headerNarrow && !root.isChannel ? 20 : implicitHeight
            lineHeight: root.headerNarrow && !root.isChannel ? 20 : 1; lineHeightMode: root.headerNarrow && !root.isChannel ? Text.FixedHeight : Text.ProportionalHeight
            // Long names elide so the tabs and actions keep their place.
            // Narrow: Teams' title (and the tab dropdown under it) ends where
            // the toolbar starts (measured: 220.2 px at a 452 px header).
            width: Math.max(0, Math.min(implicitWidth, root.headerNarrow && !root.isChannel ? header.toolbarLeft - x : parent.width * 0.35))
            elide: Text.ElideRight
            text: root.chatName
            font.family: theme.font; font.pixelSize: root.headerNarrow && !root.isChannel ? 14 : theme.title; font.weight: Font.Bold
            color: root.hdrText
            // A 1:1 chat's title opens the person's card on hover, as their
            // picture does (Teams).
            HoverHandler {
                enabled: !root.isGroup && !root.isChannel && (root.chatPhotoId || "").indexOf("8:orgid:") === 0
                onHoveredChanged: if (theme.hoverCard) { if (hovered) theme.hoverCard.hoverEnter(root.chatPhotoId, title, root.chatName, root.chatPresence); else theme.hoverCard.hoverLeave() }
            }
        }
        // Name group chat (chat-title-name-group-chat): group chats only,
        // 4 after the title.
        Rectangle {
            id: renameButton
            visible: root.isGroup && !root.isChannel && !root.pane && !root.isMeetingChat
            x: title.x + title.width + 4; anchors.verticalCenter: parent.verticalCenter
            width: 21.3; height: 21.3; radius: 4
            color: renameHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: renamePopup.opened || renameHover.hovered ? "edit-16-filled" : "edit-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: renameHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: renamePopup.open() }
            ToolTip {
                visible: renameHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: "Name group chat"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Name group chat"
            // The rename popover (Teams: below the title, 40rem, "Group
            // name", Cancel / Save, Teams' two validation messages).
            Popup {
                id: renamePopup
                x: -title.width - 4; y: parent.height + 9
                width: 400; padding: 0
                height: 16 + 20 + 4 + 32 + (renameError.visible ? 4 + 16 : 0) + 16 + 32 + 16
                focus: true
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                onOpened: { nameField.text = root.chatName; nameField.selectAll(); nameField.forceActiveFocus() }
                readonly property string error: nameField.text.length > 250 ? "Your group name can't be longer than 250 characters."
                    : nameField.text.indexOf(":") >= 0 ? "':' is not a valid character in group names." : ""
                Text { x: 16; y: 16; height: 20; verticalAlignment: Text.AlignVCenter; text: "Group name"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    x: 16; y: 40; width: parent.width - 32; height: 32; radius: 4
                    color: theme.surface
                    border.color: nameField.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: nameField.activeFocus ? 2 : 0.67; color: nameField.activeFocus ? theme.brand : theme.textSecondary }
                    TextInput {
                        id: nameField
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        Text { visible: !nameField.text; text: "Type a group name"; font: nameField.font; color: theme.textSecondary }
                        Keys.onReturnPressed: if (!renamePopup.error && nameField.text.trim()) { backend.renameChat(nameField.text); renamePopup.close() }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Group name"
                    }
                }
                Text { id: renameError; visible: !!renamePopup.error; x: 16; y: 76; text: renamePopup.error; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground1 }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    y: parent.height - 16 - 32
                    spacing: 8
                    Rectangle {
                        width: 96; height: 32; radius: 4
                        color: rcHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                        Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        HoverHandler { id: rcHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: renamePopup.close() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Cancel"
                    }
                    Rectangle {
                        readonly property bool can: !renamePopup.error && nameField.text.trim().length > 0
                        width: 96; height: 32; radius: 4
                        color: !can ? theme.bgDisabled : rsHover.hovered ? theme.brandHover : theme.brandFill
                        Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.disabledStrong }
                        HoverHandler { id: rsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.can; onTapped: { backend.renameChat(nameField.text); renamePopup.close() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Save"
                    }
                }
            }
        }
        // Which tabs fit before the toolbar (Teams' Fluent overflow): all of
        // them, or as many as fit from the left with the selected one kept
        // and "+N" after them (10 px kept free, as Fluent's overflow does).
        FontMetrics { id: tabFont; font.family: theme.font; font.pixelSize: theme.base }
        FontMetrics { id: tabFontSel; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        QtObject {
          id: tabsFit
          readonly property var shown: {
            const names = root.tabNames
            const selIdx = Math.max(0, names.indexOf(root.tab))
            const w = names.map((n, i) => (i === selIdx ? tabFontSel : tabFont).advanceWidth(n) + 12 + 20 * (i === selIdx && !!root.channelTabs.find(t => t.name === n && t.menu.length > 0)))
            const avail = (root.isChannel ? header.width - 160 : root.pane ? header.width - 48 : header.toolbarLeft) - tabs.x - 2 - 10
            if (w.reduce((a, b) => a + b, 0) <= avail) return names.map((n, i) => i)
            const plus = tabFont.advanceWidth("+" + names.length) + 4
            let budget = avail - plus - w[selIdx]
            const shown = [selIdx]
            for (let i = 0; i < names.length; i++) {
                if (i === selIdx) continue
                if (w[i] > budget) break
                budget -= w[i]; shown.push(i)
            }
            return shown.sort((a, b) => a - b)
          }
          readonly property var hidden: root.tabNames.map((n, i) => i).filter(i => shown.indexOf(i) < 0)
        }
        Row {
            id: tabs
            visible: !(root.headerNarrow && !root.isChannel) && !root.popout
            x: (renameButton.visible ? renameButton.x + renameButton.width : title.x + title.width) + 2
            y: 2; height: 56
            Repeater {
                id: tabRepeater
                model: root.tabNames
                delegate: Item {
                    id: tabItem
                    required property string modelData
                    required property int index
                    // Dragging: the picked-up tab's slot is empty; the
                    // others slide aside.
                    opacity: root.tabDragFrom === index ? 0 : 1
                    transform: Translate {
                        x: root.tabShift(tabItem.index)
                        Behavior on x { enabled: root.tabDragAnimate; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    DragHandler {
                        target: null
                        enabled: root.isChannel && root.tabIsDraggable(tabItem.index)
                        onActiveChanged: active ? root.tabDragStart(tabItem.index, centroid.pressPosition) : root.tabDragEnd()
                        onTranslationChanged: if (active) root.tabDragMove(tabItem.index, translation)
                    }
                    readonly property bool sel: root.tab === modelData || (index === 0 && root.tab === "")
                    // Teams: the selected tab shows a chevron when it has a
                    // menu; any tab with a right-click menu opens it there.
                    readonly property var channelTab: root.channelTabs.find(t => t.name === modelData) || null
                    readonly property bool menuable: sel && !!channelTab && channelTab.menu.length > 0
                    // 6 px padding each side of the label.
                    width: tabText.implicitWidth + 12 + (menuable ? 20 : 0); height: parent.height
                    // Tabs that don't fit go under "+N".
                    visible: tabsFit.shown.indexOf(index) >= 0
                    Text {
                        id: tabText
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.family: theme.font; font.pixelSize: theme.base
                        font.weight: tabItem.sel ? Font.DemiBold : Font.Normal
                        color: tabItem.sel ? root.hdrText : root.liveBand ? root.hdrSoft : theme.textStrong
                    }
                    FluentIcon {
                        visible: tabItem.menuable
                        x: tabText.x + tabText.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down-12"; size: 12; color: root.hdrText
                    }
                    // Selected: a 3 px brand pill, inset 8 px, at the bottom.
                    Rectangle {
                        visible: tabItem.sel
                        x: 8; width: tabText.implicitWidth - 4 + (tabItem.menuable ? 20 : 0); height: 3; radius: 1.5
                        anchors.bottom: parent.bottom
                        color: root.liveBand ? "#FFFFFF" : theme.brand
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const t = tabItem.channelTab
                            // Teams opens website tabs in the browser; they never become the selected tab.
                            if (t && t.opens_in_browser) { if (t.website_url) Qt.openUrlExternally(t.website_url); return }
                            if (tabItem.menuable) { tabMenu.show(t, t.menu, tabItem, 0, tabItem.height); return }
                            root.manageApps = false; root.tab = tabItem.index === 0 ? "" : tabItem.modelData
                        }
                    }
                    // A website tab's tooltip: its address and the open-in-new-window icon.
                    HoverHandler { id: tabHover }
                    ToolTip {
                        visible: tabHover.hovered && !!tabItem.channelTab && tabItem.channelTab.opens_in_browser && !!tabItem.channelTab.website_url
                        delay: 500
                        y: tabItem.height + 4
                        padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Row {
                            spacing: 4
                            Text { text: tabItem.channelTab ? tabItem.channelTab.website_url : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                            FluentIcon { name: "window-new-20"; size: 16; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !!tabItem.channelTab && tabItem.channelTab.context_menu.length > 0
                        onTapped: (ev) => tabMenu.show(tabItem.channelTab, tabItem.channelTab.context_menu, tabItem, ev.position.x, ev.position.y)
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData
                    Accessible.selected: sel
                }
            }
            // The dragged tab's card (above).
            FluentSurface {
                id: tabDragCard
                visible: root.tabDragFrom >= 0
                parent: header
                z: 1000
                x: tabs.x + root.tabDragX; y: tabs.y + root.tabDragY
                width: Math.min(150, tabDragText.implicitWidth + 20); height: 48
                depth: 8; radius: 4; color: theme.surface
                Text {
                    id: tabDragText
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    text: root.tabDragFrom >= 0 ? root.tabNames[root.tabDragFrom] || "" : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                FluentIcon {
                    visible: !root.tabDragCanDrop
                    x: root.tabDragPress.x + 10; y: root.tabDragPress.y + 22
                    name: "prohibited-12"; size: 12; color: theme.text
                }
            }
            // "+N" (tab-overflow-button, measured): 14 px #616161, padding
            // 0 2, 60.3 tall; its menu lists the tabs that didn't fit.
            Item {
                id: tabOverflow
                visible: tabsFit.hidden.length > 0
                y: -2; width: plusText.implicitWidth + 4; height: 60.3
                Text { id: plusText; x: 2; anchors.verticalCenter: parent.verticalCenter; text: "+" + tabsFit.hidden.length; font.family: theme.font; font.pixelSize: theme.base; color: plusHover.hovered ? root.hdrText : root.hdrSoft }
                HoverHandler { id: plusHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: tabOverflowMenu.open() }
                Accessible.role: Accessible.Button
                Accessible.name: tabsFit.hidden.length + " more tabs."
                MenuPopup {
                    id: tabOverflowMenu
                    x: 5; y: parent.height + 5
                    items: tabsFit.hidden.map(i => ({ label: root.tabNames[i] }))
                    onPicked: k => { const i = tabsFit.hidden[k]; root.tab = i === 0 ? "" : root.tabNames[i] }
                }
            }
        }
        // Below 640: the tabs as a dropdown under the title (Teams'
        // tab-overflow-button with the open tab's name, 12 px #424242 and a
        // 12 px chevron 4 after it; a menu of the tabs, the open one checked).
        Item {
            id: tabDropdown
            visible: root.headerNarrow && !root.isChannel && !root.pane && !root.popout && header.toolbarLeft - title.x >= ddRow.implicitWidth
            x: title.x; y: 28; width: ddRow.implicitWidth; height: 17.3
            Row {
                id: ddRow
                anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.tab === "" ? (root.tabNames[0] || "") : root.tab; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textStrong }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: tabDropdownMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: root.tab === "" ? (root.tabNames[0] || "") : root.tab
            MenuPopup {
                id: tabDropdownMenu
                y: parent.height + 4
                items: root.tabNames.map((n, i) => ({ label: n, checked: (root.tab === "" ? 0 : root.tabNames.indexOf(root.tab)) === i }))
                onPicked: i => root.tab = i === 0 ? "" : root.tabNames[i]
            }
        }
        component HeaderAction: Rectangle {
            id: ha
            property alias icon: haIcon.name
            property int iconSize: 20
            signal clicked()
            width: 32; height: 32; radius: theme.radius
            anchors.verticalCenter: parent.verticalCenter
            color: haHover.hovered && !root.liveBand ? theme.hover : "transparent"
            HoverHandler { id: haHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ha.clicked() }
            property color iconColor: root.hdrStrong
            FluentIcon { id: haIcon; anchors.centerIn: parent; size: ha.iconSize; color: ha.iconColor }
        }
        // 1:1: Teams' sticky call button (default-chat-call-audio-button /
        // -video-button, 24 x 31.3): the last choice placed from here, audio
        // by default; its chevron (24 x 31.3, "More call options") has Video
        // call and Audio call with their shortcuts, in a 171.8-wide menu
        // ending 4.6 left of the chevron's right edge.
        HeaderAction {
            id: callPrimary
            visible: !root.isSelf && !root.isChannel && !root.isGroup
            x: oneToOnePeople.x - 48; width: 24; height: 31.3
            icon: backend.headerCallVideo ? "video-20" : "call-20"
            onClicked: backend.headerCallVideo ? root.videoCall() : root.call()
            Accessible.name: backend.headerCallVideo ? "Video call" : "Audio call"
        }
        HeaderAction {
            visible: callPrimary.visible
            x: oneToOnePeople.x - 24; width: 24; height: 31.3
            icon: "chevron-down-16"; iconSize: 16
            Accessible.name: "More call options"
            onClicked: callMenu.open()
            MenuPopup {
                id: callMenu
                x: parent.width - 4.6 - width; y: parent.height + 4.9
                items: [{ label: "Video call", icon: "video-20", keys: "Alt+Shift+V" }, { label: "Audio call", icon: "call-20", keys: "Alt+Shift+A" }]
                onPicked: i => i === 0 ? root.videoCall() : root.call()
            }
        }
        HeaderAction {
            id: oneToOnePeople
            // Teams' channel header has no people button.
            visible: !root.isSelf && !root.isGroup && !root.isChannel
            x: root.isChannel ? parent.width - 151 : root.actionRight - 28; width: 28
            icon: "people-add-20"
            Accessible.name: root.isChannel ? "View participants" : "Start a group chat"
            onClicked: participants.visible = !participants.visible
        }
        // Group chats' call control (Teams 944031 `Ln`): Meet now (a huddle;
        // the video icon and its text from 834 wide, 101.8 x 32) and its
        // chevron (28 x 36) with Audio call; Join while the chat has a call.
        // Above 20 members both are disabled with Teams' tooltip.
        // While the chat has a call (Teams' audio drop-in pill, measured on
        // winpc): a 1 px gradient frame (262.6 deg: #3EB0F0 19.9 %, #AB9EFF
        // 43.1 %, #2200FF 67.8 %, #AD00FF), radius 6, 34 tall, holding the
        // live roster button ("View participants": the brand sound-wave 20
        // at 6, then 24 px avatars at 32, padding 4 6), a 0.67 px
        // NeutralStroke1 divider and Join (14 semibold, padding 6 10); in
        // the call, only the roster.
        Rectangle {
            id: joinButton
            visible: root.isGroup && !root.isChannel && !root.isSelf && !root.isMeetingChat && (root.callGoing || root.inThisCall)
            readonly property var starts: root.messages.filter(m => m.kind === "call" && m.call_state === "started" && m.call_active)
            // Who is in the call: the roster while we're in it, otherwise who
            // started it. Teams shows at most 5, then a "+N" avatar.
            readonly property var callers: {
                const out = []
                if (root.inThisCall) {
                    for (const p of (backend.callRosterJson ? JSON.parse(backend.callRosterJson) : []))
                        if (p.active) out.push({ mri: p.id, name: p.name || root.memberName(p.id) })
                } else if (root.liveRosterPeople.length > 0) {
                    for (const p of root.liveRosterPeople)
                        out.push({ mri: p.id, name: p.name || root.memberName(p.id) })
                } else if (root.liveCall && root.liveCall.initiator) {
                    out.push({ mri: root.liveCall.initiator, name: root.liveCall.initiator_name || root.memberName(root.liveCall.initiator) })
                } else {
                    const seen = {}
                    for (const m of starts) if (m.sender_mri && !seen[m.sender_mri]) { seen[m.sender_mri] = true; out.push({ mri: m.sender_mri, name: m.sender || root.memberName(m.sender_mri) }) }
                }
                return out
            }
            readonly property int hidden: Math.max(0, callers.length - 5)
            x: rosterCount.leftEdge - 8 - width; anchors.verticalCenter: parent.verticalCenter
            width: pillRow.width + 2; height: 34; radius: 6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#AD00FF" }
                GradientStop { position: 0.3225; color: "#2200FF" }
                GradientStop { position: 0.5689; color: "#AB9EFF" }
                GradientStop { position: 0.8007; color: "#3EB0F0" }
            }
            Row {
                id: pillRow
                x: 1; y: 1
                Rectangle {
                    id: liveRoster
                    width: 6 + 20 + 6 + (avatars.visible ? avatars.width + 6 : 0); height: 32
                    topLeftRadius: 4; bottomLeftRadius: 4
                    topRightRadius: root.inThisCall ? 4 : 0; bottomRightRadius: root.inThisCall ? 4 : 0
                    color: rosterPillHover.hovered ? theme.hover : theme.surface
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "live-roster-20-filled"; size: 20; color: theme.brand }
                    Row {
                        id: avatars
                        // Teams shows the avatars only from 834 wide.
                        visible: root.width >= 834
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        // Each overlaps the next by 10 (margin-right -10).
                        spacing: -10
                        Repeater {
                            model: joinButton.callers.slice(0, 5)
                            Avatar { required property var modelData; size: 24; name: modelData.name || "?"; photoId: modelData.mri }
                        }
                        Rectangle {
                            visible: joinButton.hidden > 0
                            width: 24; height: 24; radius: 12
                            // Fluent's neutral avatar: NeutralBackground6,
                            // NeutralForeground3, 10 px semibold at size 24.
                            color: theme.pick("#EBEBEB", "#333333")
                            Text { anchors.centerIn: parent; text: "+" + joinButton.hidden; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.pick("#616161", "#ADADAD") }
                        }
                    }
                    HoverHandler { id: rosterPillHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: participants.visible = !participants.visible }
                    ToolTip {
                        visible: rosterPillHover.hovered; delay: 500
                        y: parent.height + 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: "View participants"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "View participants"
                }
                Rectangle { visible: !root.inThisCall; width: 0.67; height: 32; color: theme.stroke }
                Rectangle {
                    visible: !root.inThisCall
                    width: joinText.implicitWidth + 20; height: 32
                    topRightRadius: 4; bottomRightRadius: 4
                    color: joinHover.hovered ? theme.hover : theme.surface
                    Text { id: joinText; anchors.centerIn: parent; text: "Join"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: joinHover.hovered ? theme.brand : theme.textStrong }
                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: backend.callState === ""; onTapped: backend.joinGroupCall() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Join"
                }
            }
        }
        Rectangle {
            id: meetNow
            visible: root.isGroup && !root.isChannel && !root.isSelf && !root.isMeetingChat && !joinButton.visible
            readonly property bool wide: root.width >= 834
            x: rosterCount.leftEdge - 28 - width; anchors.verticalCenter: parent.verticalCenter
            width: wide ? 101.8 : 32; height: 32; radius: 4
            color: meetHover.hovered && !root.callsDisabled ? theme.hover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: meetHover.hovered && !root.callsDisabled ? "video-20-filled" : "video-20"; size: 20; color: root.callsDisabled ? theme.disabled : meetHover.hovered ? theme.brand : theme.textStrong }
                Text { visible: meetNow.wide; anchors.verticalCenter: parent.verticalCenter; text: "Meet now"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.callsDisabled ? theme.disabled : meetHover.hovered ? theme.brand : theme.textStrong }
            }
            HoverHandler { id: meetHover; cursorShape: root.callsDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !root.callsDisabled && backend.callState === ""; onTapped: backend.meetNow() }
            ToolTip {
                visible: meetHover.hovered && (!meetNow.wide || root.callsDisabled); delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: root.callsDisabled ? "Calls aren't available in chats with more than 20 people" : "Meet now"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Meet now"
        }
        Rectangle {
            visible: meetNow.visible
            x: rosterCount.leftEdge - 28; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 36; radius: 4
            color: chevHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-16"; size: 16; color: root.callsDisabled ? theme.disabled : theme.textStrong }
            HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: groupCallMenu.open() }
            ToolTip {
                visible: chevHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: "More call options"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "More call options"
            MenuPopup {
                id: groupCallMenu
                x: parent.width - width; y: parent.height + 4
                items: [{ label: "Audio call", icon: "call-20", enabled: !root.callsDisabled }]
                onPicked: root.call()
            }
        }
        // Meeting chats: Teams' Join (chat-join-button, measured on winpc):
        // primary, 43.1 x 31.3, padding 5 8, 14 semibold white on brand,
        // 8 before the roster count; hidden when the meeting is cancelled,
        // disabled while you're in it.
        Text {
            id: liveDuration
            visible: root.liveBand && !!root.liveSince
            property int tick: 0
            Timer { running: liveDuration.visible; interval: 1000; repeat: true; onTriggered: liveDuration.tick++ }
            x: (bandRoster.visible ? bandRoster.x : meetingJoin.visible ? meetingJoin.x - 8 : rosterCount.leftEdge) - 7 - width
            anchors.verticalCenter: parent.verticalCenter
            text: {
                tick
                if (!root.liveSince) return ""
                const t = Math.max(0, Math.floor((Date.now() - root.liveSince.getTime()) / 1000))
                const two = n => (n < 10 ? "0" : "") + n
                return two(Math.floor(t / 3600)) + ":" + two(Math.floor(t / 60) % 60) + ":" + two(t % 60)
            }
            font.family: theme.font; font.pixelSize: 12
            color: "#FFFFFF"
            Accessible.name: "Meeting duration " + text
        }
        // The live roster in a meeting's band (chat-live-roster, measured on
        // winpc): who is in the meeting besides you, 32 px avatars 22 apart
        // (the last one's 10 px overhang is the row's right padding), 7
        // after the duration and 8 before Join; at most 5, then +N. From
        // 834 wide, while you aren't in the meeting.
        Row {
            id: bandRoster
            readonly property var people: root.liveRosterPeople
            readonly property int hidden: Math.max(0, people.length - 5)
            visible: root.liveBand && root.width >= 834 && people.length > 0 && !root.inThisCall
            x: (meetingJoin.visible ? meetingJoin.x - 8 : rosterCount.leftEdge) - width
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(people.length, 5) * 22 + (hidden > 0 ? 22 : 0) + 10
            spacing: -10
            Repeater {
                model: bandRoster.people.slice(0, 5)
                Avatar { required property var modelData; size: 32; name: modelData.name || "?"; photoId: modelData.id }
            }
            Rectangle {
                visible: bandRoster.hidden > 0
                width: 32; height: 32; radius: 16
                // Fluent's neutral avatar (NeutralBackground6 / Foreground3).
                color: theme.pick("#EBEBEB", "#333333")
                Text { anchors.centerIn: parent; text: "+" + bandRoster.hidden; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#616161", "#ADADAD") }
            }
        }
        Rectangle {
            id: meetingJoin
            visible: root.isMeetingChat && !!root.meeting && !root.meeting.cancelled
            readonly property bool can: !root.inThisCall && backend.callState === ""
            x: rosterCount.leftEdge - 8 - width; anchors.verticalCenter: parent.verticalCenter
            width: meetingJoinText.implicitWidth + 16; height: 31.3; radius: 4
            color: !can ? theme.bgDisabled : meetingJoinHover.hovered ? theme.brandHover : theme.brandFill
            Text { id: meetingJoinText; anchors.centerIn: parent; text: "Join"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: meetingJoin.can ? "white" : theme.disabledStrong }
            HoverHandler { id: meetingJoinHover; cursorShape: meetingJoin.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: meetingJoin.can; onTapped: backend.joinMeeting(root.meeting.join_url, root.meeting.subject || root.chatName) }
            Accessible.role: Accessible.Button
            Accessible.name: "Join"
        }
        // Group chats: the roster count (chat-header-participant-count):
        // PeopleAdd and the bold 12 px member count.
        Rectangle {
            visible: root.isGroup && !root.isChannel && !root.isSelf && !root.rosterInMenu
            readonly property int count: (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []).length
            id: rosterCount
            // Where the call controls end: the roster's left edge, or the
            // action area's right edge when the roster is in ···.
            readonly property real leftEdge: visible ? x : root.actionRight
            x: root.actionRight - width; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(28, 4 + 20 + 2 + countLabel.implicitWidth + 4); height: 32; radius: 4
            color: rosterHover.hovered && !root.liveBand ? theme.hover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 2
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 20; color: root.hdrStrong }
                Text { id: countLabel; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.count; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: root.hdrStrong }
            }
            HoverHandler { id: rosterHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: participants.visible = !participants.visible }
            ToolTip {
                visible: rosterHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: "View and add participants"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "View and add participants, " + count + " participants"
        }
        Rectangle {
            id: channelMeet
            visible: root.isChannel && !root.pane
            x: root.channelMeetLeft; anchors.verticalCenter: parent.verticalCenter
            width: root.channelMeetWide ? 97.17 : 32; height: 32; radius: 4
            readonly property bool blocked: backend.callState !== ""
            color: channelMeetHover.hovered && !blocked ? theme.hover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: channelMeetHover.hovered && !channelMeet.blocked ? "video-20-filled" : "video-20"; size: 20; color: channelMeet.blocked ? theme.disabled : channelMeetHover.hovered ? theme.brand : root.hdrStrong }
                Text { visible: root.channelMeetWide; anchors.verticalCenter: parent.verticalCenter; text: "Meet now"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: channelMeet.blocked ? theme.disabled : channelMeetHover.hovered ? theme.brand : root.hdrStrong }
            }
            HoverHandler { id: channelMeetHover; cursorShape: channelMeet.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !channelMeet.blocked; onTapped: root.channelMeetNow() }
            Accessible.role: Accessible.Button
            Accessible.name: "Meet now"
        }
        HeaderAction {
            id: channelMeetMore
            visible: channelMeet.visible
            x: channelMeet.x + channelMeet.width; width: 20; height: 32
            icon: "chevron-down-16"; iconSize: 16
            iconColor: channelMeetMenu.opened ? theme.brand : root.hdrStrong
            onClicked: channelMeetMenu.open()
            Accessible.name: "More channel meeting options"
            // Meet now / Schedule a meeting (161.8 wide, its end 4.5 inside
            // the chevron's, 4.5 below it).
            MenuPopup {
                id: channelMeetMenu
                x: parent.width - 4.5 - width; y: parent.height + 4.5
                items: [
                    { key: "meet", label: "Meet now", icon: "video-20", enabled: !channelMeet.blocked },
                    { key: "schedule", label: "Schedule a meeting", icon: "calendar-add-20" }
                ]
                onPicked: i => items[i].key === "meet" ? root.channelMeetNow() : root.scheduleMeeting()
            }
        }
        HeaderAction {
            id: tabConvButton
            visible: !root.pane && !!root.currentTab && root.currentTab.can_converse === true
            readonly property bool open: !!root.tabConversationTab && root.tabConversationTab.id === (root.currentTab ? root.currentTab.id : "")
            x: root.channelMeetLeft - 32; height: 31.3
            icon: open ? "chat-20-filled" : "chat-20"
            iconColor: open ? theme.brand : root.hdrStrong
            onClicked: root.tabConversationTab = open ? null : root.currentTab
            ToolTip.visible: tabConvHover.hovered; ToolTip.delay: 500
            ToolTip.text: open ? "Hide tab conversation" : "Show tab conversation"
            HoverHandler { id: tabConvHover }
            Accessible.name: open ? "Hide tab conversation" : "Show tab conversation"
        }
        // Meeting details (chat-meeting-details): 32 x 31.3, TextBulletList,
        // after the roster count (measured on winpc).
        HeaderAction {
            visible: root.meetingDetailsInline
            x: root.contextLeft - 16 - 32; icon: "text-bullet-list-20"; Accessible.name: "Meeting details"
            onClicked: root.openMeetingDetails(root.meeting.join_url, root.meeting.ical_uid, root.meeting.start || "")
        }
        Rectangle {
            visible: !root.isSelf
            // (On a channel's other tabs the context buttons go, and it sits
            // just before ···.)
            x: root.isChannel && root.tab !== "" ? root.width - 43 - 8 : root.contextLeft - 8; width: 1; height: 20
            anchors.verticalCenter: parent.verticalCenter
            color: theme.divider
        }
        // Open / Close threads (thread-list-pane-toggle-button): ChatMultiple,
        // filled brand while the pane shows.
        HeaderAction {
            visible: root.threadsButton > 0
            x: root.contextLeft
            icon: root.threadsOpen ? "chat-multiple-20-filled" : "chat-multiple-20"
            iconColor: root.threadsOpen ? theme.brand : root.hdrStrong
            onClicked: root.toggleThreads()
            ToolTip.visible: threadsHover.hovered; ToolTip.delay: 500
            ToolTip.text: root.threadsOpen ? "Close threads" : "Open threads"
            HoverHandler { id: threadsHover }
            Accessible.name: root.threadsOpen ? "Close threads" : "Open threads"
        }
        // In a channel, Find and Channel details show only on Posts (Teams).
        HeaderAction {
            visible: root.contextInline >= 1 && !(root.isChannel && root.tab !== "")
            x: root.contextLeft + 32 * root.threadsButton; icon: "search-20"; Accessible.name: root.isChannel ? "Find in channel" : "Find in chat"
            iconColor: root.finding ? theme.brand : root.hdrStrong
            onClicked: root.toggleFind()
        }
        HeaderAction {
            visible: root.contextInline >= 2 && !(root.isChannel && root.tab !== "")
            x: root.contextLeft + 32 * (1 + root.threadsButton); icon: root.isChannel ? "panel-right-expand-20" : "panel-left-20"; Accessible.name: root.isChannel ? "Open channel details" : "Open chat details"
            onClicked: participants.visible = !participants.visible
        }
        // More channel options (more-apps-button-tid, 32 x 31.3, ··· at the
        // end): the channel's menu (ChannelMenu), its end 6.3 past the
        // button's, 4.9 below it.
        HeaderAction {
            id: channelMore
            visible: root.isChannel && !root.pane
            x: parent.width - 43; height: 31.3
            icon: "more-horizontal-20"
            iconColor: channelMenu.menu.opened ? theme.brand : root.hdrStrong
            Accessible.name: "More channel options"
            onClicked: channelMenu.show(channelMore, channelMore.width + 6.3 - channelMenu.menu.implicitWidth, channelMore.height + 4.9)
        }
        // More chat options (chat-header-more-menu-trigger), as Teams
        // (measured on winpc 2026-11-09): Open in new window (Ctrl+O) |
        // Schedule meeting, Share screen (Ctrl+Shift+E) | Mark as unread,
        // Move to section ▸, Remove from section, Mute, Copy link | Remove
        // chat history. Meeting chats: no Schedule meeting or Share screen,
        // and Report a concern in Remove chat history's place; your own
        // chat: no Schedule meeting, Share screen, Mute or last group.
        HeaderAction {
            id: chatMore
            visible: !root.isChannel && !root.pane
            x: parent.width - 43; icon: "more-horizontal-20"; Accessible.name: "More chat options"
            onClicked: chatMenu.open()
            MenuPopup {
                id: chatMenu
                x: parent.width / 2 - width / 2; y: parent.height + 4
                margins: 8
                // Narrow headers put what didn't fit first (Teams' "Sidepane
                // Features": chat details as "In this chat", then Find), then
                // the action items that moved (Participants), a divider, and
                // the chat's own items.
                readonly property var moved: [
                    root.contextInline < 1 ? { key: "find", label: "Find in chat", icon: "search-20" } : null,
                    root.contextInline < 2 ? { key: "details", label: "In this chat", icon: "panel-left-20", keys: "Alt+P" } : null,
                    root.rosterInMenu ? { key: "participants", label: "Participants", icon: "people-add-20" } : null,
                    root.meetingDetailsShown && !root.meetingDetailsInline ? { key: "meetingDetails", label: "Meeting details", icon: "text-bullet-list-20" } : null
                ].filter(i => i !== null)
                readonly property bool calls: !root.isSelf && !root.isMeetingChat
                items: (moved.length ? moved.concat([{ separator: true }]) : []).concat([
                    root.popout ? null : { key: "window", label: "Open in new window", icon: "open-window-20", keys: "Ctrl+O" },
                    root.popout ? null : { separator: true },
                    calls ? { key: "meeting", label: "Schedule meeting", icon: "calendar-add-20" } : null,
                    calls ? { key: "share", label: "Share screen", icon: "share-screen-start-20", keys: "Ctrl+Shift+E" } : null,
                    calls ? { separator: true } : null,
                    { key: "unread", label: "Mark as unread", icon: "glasses-off-20" },
                    { key: "move", label: "Move to section", icon: "star-20", submenu: root.moveTargets() },
                    root.sectionHolder ? { key: "removeFrom", label: "Remove from section", icon: "star-off-20" } : null,
                    root.isSelf ? null : { key: "mute", label: root.chatMuted ? "Unmute" : "Mute", icon: root.chatMuted ? "alert-20" : "alert-off-20" },
                    { key: "link", label: "Copy link", icon: "link-20" },
                    root.isSelf ? null : { separator: true },
                    root.isSelf ? null : root.isMeetingChat ? { key: "report", label: "Report a concern", icon: "shield-error-20" } : { key: "removeHistory", label: "Remove chat history", icon: "delete-20" }
                ]).filter(i => i !== null)
                onPicked: i => {
                    const k = items[i].key
                    if (k === "details" || k === "participants") participants.visible = !participants.visible
                    else if (k === "find") root.toggleFind()
                    else if (k === "meetingDetails") root.openMeetingDetails(root.meeting.join_url, root.meeting.ical_uid, root.meeting.start || "")
                    else if (k === "mute") backend.setChatMuted(root.chatId, !root.chatMuted)
                    else if (k === "meeting") root.scheduleMeeting()
                    else if (k === "link") backend.copyChatLink()
                    else if (k === "unread") { const m = root.messages.filter(m => m.kind === "message").pop(); if (m) backend.markMessageUnread(m.id, m.client_message_id || "") }
                    else if (k === "window") root.openInNewWindow()
                    else if (k === "share") root.shareScreen()
                    else if (k === "removeFrom") backend.folderAction("remove", JSON.stringify({ item: root.chatId, from: root.sectionHolder }))
                    else if (k === "report") root.reportConcern()
                    else if (k === "removeHistory") removeHistoryAsk.open()
                }
                onSubPicked: (i, j) => {
                    const t = items[i].submenu[j]
                    if (t.newSection) headerSectionDialog.create(root.chatId, root.sectionHolder)
                    else if (t.to) backend.folderAction("move", JSON.stringify({ item: root.chatId, to: t.to, from: root.sectionHolder }))
                }
            }
        }
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

    ChannelPosts {
        id: channelPosts
        visible: root.postsLayout && root.tab === ""
        findMark: root.findMark
        anchors { top: header.bottom; bottom: root.posting && !newestAtTop ? compose.top : parent.bottom; left: parent.left; right: parent.right }
        anchors.bottomMargin: root.posting && !newestAtTop ? 12 : 0
        // See new posts at top: the composer opens in the list's top card.
        newestAtTop: backend.channelPostsAtTop
        composerHeight: compose.boxHeight + compose.bannerShownH
        myPresence: root.myPresence
        onStartAnnouncement: { root.posting = true; compose.announcement = true; compose.focusSubject() }
        messages: root.isChannel ? root.messages : []
        myName: root.myName
        channelName: root.chatName
        liveRoster: root.liveRosterPeople
        members: backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []
        onJoinMeeting: (url, title) => root.joinMeetingRequested(url, title)
        onSeeDetails: rootId => root.openPostView(rootId)
        busy: root.busy
        onReply: (id, text) => root.sendReply(id, text)
        onReact: (id, key, on) => root.react(id, key, on)
        host: msgHost
        posting: root.posting
        onStartPost: { root.posting = true; compose.focusSubject() }
    }
    // Behind the post composer: the channel's page colour.
    Rectangle {
        visible: channelPosts.visible && root.posting && !channelPosts.newestAtTop
        anchors { top: channelPosts.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        color: theme.channelPage
    }

    // Settings ▸ Chats ▸ When I open a chat, take me to: the last read
    // message (Teams' default; its "Last read" line at the top of the view
    // when there's more than fits) or the newest.
    readonly property bool landOnLastRead: { const s = backend.settingsJson ? JSON.parse(backend.settingsJson) : {}; const m = (((s.props || {}).userPersonalSettings || {}).messagingSettings || {}); return m.navigateToLastReadMessage !== false }
    property bool landing: false
    ListView {
        id: list
        visible: root.tab === "" && (!root.isChannel || root.threadsLayout)
        onCountChanged: if (root.landing && count > 0) {
            root.landing = false
            if (!root.landOnLastRead) return
            const i = model.findIndex(m => m.lastRead === true)
            if (i >= 0) Qt.callLater(() => list.positionViewAtIndex(i, ListView.End))
        }
        // Read-only (a lobby's view): the messages start at the top, as
        // Teams' waiting-side Lobby pane lists them.
        anchors { top: header.bottom; bottom: root.readOnly ? undefined : root.peerNoteShown ? peerNoteBar.top : compose.top; left: parent.left; right: parent.right }
        height: Math.min(contentHeight + 12, root.height - header.height - 12)
        anchors.bottomMargin: 12
        clip: true
        spacing: 0
        verticalLayoutDirection: ListView.BottomToTop
        model: root.annotate((root.threadsLayout ? root.threadStarters(root.messages) : root.messages).concat(root.scheduledItems))
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Scrolling up to the oldest messages loads the page before them (as
        // Teams pages back); the message at the top stays where it was.
        property string keepId: ""
        property real keepOffset: 0
        function topIndex() { return indexAt(width / 2, contentY + 1) }
        onContentYChanged: {
            const i = topIndex()
            if (i >= 0 && i >= count - 3 && backend.messagesHasOlder && !backend.messagesLoadingOlder && keepId === "") {
                const m = model[i]
                const item = itemAtIndex(i)
                if (m && item) { keepId = m.id; keepOffset = item.y - contentY }
                backend.loadOlderMessages()
            }
        }
        onModelChanged: if (keepId !== "") Qt.callLater(() => {
            const i = model.findIndex(m => m.id === keepId)
            if (i >= 0) {
                positionViewAtIndex(i, ListView.Beginning)
                const item = itemAtIndex(i)
                if (item) contentY = item.y - keepOffset
            }
            keepId = ""
        })
        delegate: Item {
            id: msg
            required property var modelData
            // In channels every post is a left-aligned card, yours included.
            readonly property bool mine: modelData.mine && !root.postsLayout
            readonly property bool isCall: modelData.kind === "call"
            // Teams' control messages (someone added, renamed, left…).
            readonly property bool isEvent: modelData.kind === "event"
            readonly property bool appAdded: isEvent && !!modelData.event && modelData.event.kind === "AddCustomApp"
            // Meeting recording rows (Teams: the time first, like call rows).
            readonly property bool recordingRow: isEvent && !!modelData.event && modelData.event.kind.indexOf("Recording") === 0
            readonly property bool isRow: isCall || isEvent
            readonly property var reactions: modelData.reactions || []
            // Being edited in place (Teams: the compose replaces the bubble,
            // 172 in from the list's start and 72 from its end).
            readonly property bool editingThis: root.editingId.length > 0 && root.editingId === modelData.id
            width: list.width
            // Grouped messages (same sender, within minutes) drop the
            // name/time line and avatar, and sit 2 px under the previous.
            readonly property bool grouped: modelData.grouped === true
            // Teams' send states for your messages: pending (Sending /
            // Retrying) shows the Circle icon; failed shows its text over the
            // bubble, a red bubble, Retry and Delete to its left.
            readonly property bool sendPending: modelData.send_state === "sending" || modelData.send_state === "retrying"
            readonly property bool sendFailed: modelData.send_state === "failed"
            // The name line shows for a failed message even within a group.
            readonly property bool showMeta: (!grouped || sendFailed) && !isRow && !scheduledMsg
            // Day divider and "Last read" line sit above the message.
            readonly property int dividerH: (modelData.dayDivider ? 30 : 0) + (modelData.lastRead ? 36 : 0)
            // Control and call rows sit flush, as in Teams (28 / 36 px rows).
            readonly property int topPad: dividerH + (isRow ? 0 : grouped ? 2 : 12)
            // A grouped message that was edited: Teams puts "Edited" (12 px
            // #616161) over its bubble, 2 under the group's previous one and
            // 3 above its own (OST TEST 126's results, edited by Polls).
            readonly property bool groupedEdited: !root.compact && !isRow && !showMeta && grouped && modelData.edited === true && !modelData.deleted
            readonly property int bubbleY: root.compact && !isRow ? topPad + (showMeta ? 26 : 2) : topPad + (groupedEdited ? 21 : !showMeta || isCall ? 0 : meta.height + 2)
            // A thread starter's replies line (Threads layout), 28 tall.
            readonly property real threadLineH: root.threadsLayout && (modelData.thread_replies || 0) > 0 ? 30 : 0
            // A thread pane's "{N} replies" divider under its first message
            // (Teams: a 28 tall item, the 12 px label 12 down).
            readonly property real repliesDivH: root.threadPane && modelData.id === root.threadRoot && repliesCount > 0 ? 28 : 0
            readonly property int repliesCount: root.threadPane ? root.messages.filter(m => m.id !== root.threadRoot && m.kind === "message").length : 0
            // A reply also sent to the channel: "Replied in thread: {first
            // message}" in the channel, "Also sent to channel" in the thread.
            readonly property bool scheduledMsg: !!modelData.scheduled_at
            readonly property string sharedHead: !modelData.shared_in_main || modelData.id === modelData.root_id ? ""
                : root.threadsLayout ? "thread" : root.threadPane ? "channel" : ""
            // Teams' Attendance card under an ended meeting (28 down, 49.3).
            readonly property bool attendanceCard: isCall && root.isMeetingChat && root.canSeeAttendance
                && modelData.call_state !== "started" && modelData.call_state !== "missed" && !!modelData.call_id
            height: isRow ? topPad + (isCall ? (attendanceCard ? 28 + 49.3 : 36) : 28)
                : editingThis ? topPad + (editLoader.item ? editLoader.item.height : 0)
                : bubbleY + bubble.height + (reactions.length > 0 ? reactionRow.height - 4.3 + 4 : 0) + threadLineH + repliesDivH
            readonly property int maxBubble: root.postsLayout ? Math.min(900, list.width - 144) : root.compact ? list.width - 64 - root.gutR : Math.min(640, list.width * 0.7)

            // Measured from Teams: the label's centre 22 px below the
            // previous message, 28 px above the next header's.
            Text {
                visible: !!msg.modelData.dayDivider
                y: 22 - height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: msg.modelData.dayDivider || ""
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                Accessible.role: Accessible.Separator
            }
            Item {
                visible: msg.modelData.lastRead === true
                y: msg.modelData.dayDivider ? 30 : 0
                x: root.gutContent; width: parent.width - root.gutContent - root.gutR; height: 36
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0; width: lastReadText.x - 24; height: 0.67; color: theme.brand
                }
                // Teams' last-read-line: 12/16 bold brand between 0.67 px
                // brand lines (measured 2026-11-10).
                Text {
                    id: lastReadText
                    anchors.centerIn: parent
                    text: "Last read"
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    color: theme.brand
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: lastReadText.x + lastReadText.width + 24
                    width: parent.width - x; height: 0.67; color: theme.brand
                }
                Accessible.role: Accessible.Separator
                Accessible.name: "Last read"
            }

            // Call events: an icon, the time and "Call ended 3m 9s" / "Call missed".
            // Teams' control and call rows (measured): a 20 px icon at x 38 and
            // y 8 in NeutralForeground3, the 12 px text from x 72, y 10. A
            // call row reads time, then "Call ended" and the bold duration
            // ({h}h {m}m {s}s, zero parts left out); a missed call has none.
            FluentIcon {
                visible: msg.isRow
                x: root.gutL + 6; y: msg.topPad + 8
                size: 20
                // A meeting chat's calls are meetings (Teams: the video icon).
                name: msg.isCall ? (msg.modelData.call_huddle || root.isMeetingChat ? "video-20" : msg.modelData.call_state === "missed" ? "call-missed-20" : "call-20")
                    : ({ AddMember: "person-add-20", DeleteMember: "person-arrow-left-20", TopicUpdate: "edit-20", ModalityUpdate: "edit-20",
                         PictureUpdate: "person-circle-20", MemberJoined: "calendar-add-20", LobbyJoined: "calendar-add-20", MemberLeft: "person-arrow-left-20",
                         MemberRenamed: "person-edit-20", AddCustomApp: "apps-20", DeleteCustomApp: "apps-20",
                         RecordingStarted: "record-20", RecordingStopped: "record-stop-20", RecordingSaved: "cloud-arrow-up-20",
                         Transcript: "slide-text-20" })[msg.modelData.event ? msg.modelData.event.kind : ""] || "person-add-20"
                // Recording started is brand (Teams).
                color: msg.recordingRow && msg.modelData.event.kind === "RecordingStarted" ? theme.brand : theme.textSecondary
            }
            Row {
                id: callRow
                visible: msg.isRow
                x: root.gutContent; y: msg.topPad + 10
                spacing: 12
                Text {
                    visible: msg.isCall || msg.recordingRow
                    text: root.stamp(msg.modelData.time)
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Text {
                    width: Math.min(implicitWidth, msg.width - root.gutContent - root.gutR)
                    wrapMode: Text.Wrap
                    // Unverified visitors' names carry Teams' 16 px badge.
                    readonly property var unverified: msg.isEvent && msg.modelData.event ? (msg.modelData.event.unverified || []) : []
                    textFormat: msg.recordingRow || unverified.length > 0 ? Text.RichText : msg.isCall || msg.appAdded ? Text.StyledText : Text.PlainText
                    linkColor: theme.brandForeground1
                    // A saved recording's "Remove expiration" opens it (Teams
                    // opens its player's About panel, which is web content).
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    text: {
                        if (msg.recordingRow) {
                            const e = msg.modelData.event
                            const t = root.escapeHtml(msg.modelData.text)
                            return e.kind === "RecordingSaved" && e.value && e.link ? t + " <a href=\"" + e.link.replace(/"/g, "&quot;") + "\" style=\"text-decoration: none; color: " + theme.brandForeground1 + "\">Remove expiration</a>" : t
                        }
                        // "{name} added <b>{app}</b> here." (Teams bolds the app).
                        if (msg.appAdded) {
                            const t = msg.modelData.text, v = msg.modelData.event.value, i = t.lastIndexOf(v)
                            return root.escapeHtml(t.slice(0, i)) + "<b>" + root.escapeHtml(v) + "</b>" + root.escapeHtml(t.slice(i + v.length))
                        }
                        if (msg.isEvent && unverified.length > 0) {
                            let t = root.escapeHtml(msg.modelData.text)
                            const badge = "&nbsp;<img src=\"../assets/icons/person-unverified-16-" + (theme.dark ? "dark" : "light") + ".svg\" width=\"16\" height=\"16\" style=\"vertical-align: middle\">"
                            for (const n of unverified) { const e = root.escapeHtml(n), i = t.indexOf(e); if (i >= 0) t = t.slice(0, i + e.length) + badge + t.slice(i + e.length) }
                            return t
                        }
                        if (msg.isEvent) return msg.modelData.text
                        // Meet now (Teams: "You started a meeting." /
                        // "{{initiator}} started a meeting.", then
                        // "Meeting ended" with the duration).
                        if (msg.modelData.call_state === "started")
                            return msg.mine ? "You started a meeting." : root.escapeHtml(msg.modelData.sender || root.memberName(msg.modelData.sender_mri) || "Someone") + " started a meeting."
                        if (msg.modelData.call_state === "missed") return "Call missed"
                        const s = msg.modelData.call_seconds
                        // Teams leaves out whole days ("d.hh:mm:ss" reads as
                        // its hours): a 25h 28m meeting shows "1h 28m 28s".
                        const parts = [[Math.floor(s / 3600) % 24, "h"], [Math.floor(s / 60) % 60, "m"], [s % 60, "s"]]
                            .filter(p => p[0] > 0).map(p => p[0] + p[1]).join(" ")
                        // A meeting chat says "Meeting ended: {duration}" (seen in OST
                        // calendar test on winpc, 2026-11-10).
                        if (root.isMeetingChat) return "Meeting ended:&nbsp;<b>" + parts + "</b>"
                        return (msg.modelData.call_huddle ? "Meeting ended" : "Call ended") + "&nbsp;<b>" + parts + "</b>"
                    }
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
            }

            AttendanceCard {
                visible: msg.attendanceCard
                x: root.gutContent; y: msg.topPad + 28
                onClicked: root.openAttendance(msg.modelData.call_id)
            }
            Rectangle {
                visible: root.compact && msg.mine && !msg.grouped && !msg.isRow
                x: 4; y: msg.topPad + 10; width: 2; height: 32; radius: 1
                color: theme.brand
            }
            Avatar {
                visible: (!msg.mine || root.compact) && !msg.grouped && !msg.isRow && !root.noAvatars
                x: root.compact ? 16 : root.gutL; y: root.compact ? msg.topPad + 8 : msg.bubbleY
                size: root.compact ? 36 : 32; name: msg.modelData.sender
                photoId: msg.modelData.sender_mri || ""
                // A bot: its app's icon in a square with 4 px corners (Teams).
                square: String(msg.modelData.sender_mri || "").startsWith("28:")
                squareRadius: 4
                opensProfile: !square
                // Teams shows the sender's presence on message avatars too.
                presence: msg.modelData.sender_mri && msg.modelData.sender_mri === root.chatPhotoId ? root.chatPresence : ""
            }
            Text {
                visible: msg.groupedEdited
                x: msg.mine ? bubble.x + bubble.width - width : bubble.x
                y: msg.topPad + 2; height: 16
                text: "Edited"
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
            }
            // Name line: [failed text] sender, time, details. A failed
            // message's text replaces the details (Teams' statusMessage).
            Row {
                id: meta
                visible: msg.showMeta && !msg.editingThis
                y: root.compact ? msg.topPad + 9.3 : msg.topPad
                spacing: 8
                x: root.compact ? 64 : msg.mine ? msg.width - root.gutR - width : root.gutContent
                Text {
                    visible: msg.sendFailed
                    text: msg.modelData.send_note || ""
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.redForeground1
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                // Teams adds "Report a problem" to the 404 text
                // (CONVERSATION_DELETED; docs/spec/send-pipeline.md): OST's
                // feedback window, sent to OST's GitHub.
                Text {
                    visible: msg.sendFailed && (msg.modelData.send_note || "").indexOf("Message didn't send.") === 0
                    text: "Report a problem"
                    font.family: theme.font; font.pixelSize: theme.small
                    font.underline: reportHover.hovered
                    color: theme.brandLink
                    HoverHandler { id: reportHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.requestFeedback("problem", "Chat", "Message didn't send (CONVERSATION_DELETED)") }
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
                Text {
                    id: metaText
                    // Compact: the name semibold in NeutralForeground1, as Teams.
                    textFormat: root.compact ? Text.StyledText : Text.PlainText
                    text: root.compact
                        ? "<b><font color=\"" + theme.text + "\">" + root.senderLabel(msg.modelData).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font></b>&nbsp;&nbsp;" + root.stamp(msg.modelData.time) + (msg.modelData.edited && !msg.sendFailed ? "&nbsp;&nbsp;&nbsp;Edited" : "") + (root.cardUpdated(msg.modelData.id) ? "&nbsp;&nbsp;&nbsp;Updated" : "")
                        : (msg.mine ? "" : root.senderLabel(msg.modelData) + "  ") + root.stamp(msg.modelData.time)
                        + (msg.modelData.edited && !msg.sendFailed ? "   Edited" : "")
                        + (root.cardUpdated(msg.modelData.id) ? "   Updated" : "")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                    // The sender's name opens their profile card, as in Teams.
                    readonly property bool person: (!msg.mine || root.compact) && (msg.modelData.sender_mri || "").indexOf("8:orgid:") === 0
                    TextMetrics { id: senderMetrics; font: metaText.font; text: msg.modelData.sender || "" }
                    HoverHandler { id: senderHover; enabled: metaText.person; cursorShape: senderHover.point.position.x <= senderMetrics.advanceWidth ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: metaText.person; onTapped: ev => { if (ev.position.x <= senderMetrics.advanceWidth) { if (theme.hoverCard) theme.hoverCard.close(); backend.requestProfile(msg.modelData.sender_mri) } } }
                    // Hovering the name opens the compact card, as in Teams.
                    Item {
                        id: senderSpot
                        width: senderMetrics.advanceWidth; height: parent.height
                        HoverHandler {
                            enabled: metaText.person
                            onHoveredChanged: if (theme.hoverCard) { if (hovered) theme.hoverCard.hoverEnter(msg.modelData.sender_mri, senderSpot, msg.modelData.sender); else theme.hoverCard.hoverLeave() }
                        }
                    }
                }
                // Teams' delivery option label: IMPORTANT / URGENT, 12 px
                // semibold, RedForeground3, 8 after the time (measured).
                Text {
                    visible: msg.modelData.importance === "high" || msg.modelData.importance === "urgent"
                    text: msg.modelData.importance === "urgent" ? "URGENT" : "IMPORTANT"
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                    color: theme.redForeground3
                    Accessible.role: Accessible.StaticText
                    Accessible.name: msg.modelData.importance === "urgent" ? "Urgent message." : "Important message."
                }
                // Translated: Teams' icon with "Translated from …" (click: See
                // original message). Failed: the error icon and its text.
                FluentIcon {
                    visible: msg.modelData.translated === true
                    anchors.verticalCenter: parent.verticalCenter
                    name: "translate-16"; size: 16; color: theme.textSecondary
                    HoverHandler { id: trHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.translateMessage(msg.modelData.id, false) }
                    ToolTip {
                        visible: trHover.hovered; delay: 500
                        y: -height - 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: msg.modelData.translated_from ? "Translated from " + msg.modelData.translated_from : "Translated"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: msg.modelData.translated_from ? "Translated from " + msg.modelData.translated_from : "Translated"
                }
                Row {
                    visible: msg.modelData.translation_failed === true
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "error-circle-20-filled"; size: 16; color: theme.redForeground1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Failed to translate"; font.family: theme.font; font.pixelSize: theme.small; color: theme.redForeground1 }
                }
                // Saved by you: Teams' magenta bookmark at the line's end.
                FluentIcon {
                    visible: msg.modelData.saved === true
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bookmark-16-filled"; size: 16; color: theme.savedFg
                    HoverHandler { id: savedHover }
                    ToolTip {
                        visible: savedHover.hovered; delay: 500
                        y: -height - 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: "Saved by you. Others won't see that it was saved."; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.name: "Saved by you. Others won't see that it was saved."
                }
            }
            function editBoxForTest() { return editLoader.item }
            Loader {
                id: editLoader
                active: msg.editingThis
                x: 172; y: msg.topPad
                width: msg.width - root.gutR - 172
                sourceComponent: ComposeBox {
                    id: editBox
                    width: editLoader.width
                    editing: true
                    quote: msg.modelData.quote || null
                    // A scheduled message keeps its time ("Select Done to
                    // deliver on …"), which can be changed here.
                    scheduleAt: msg.modelData.scheduled_at || 0
                    onQuoteDismissed: quote = null
                    onEmojiRequested: a => root.openEmojiFor(editBox)
                    onSettingsRequested: root.openChatSettings()
                    onSubmit: {
                        if (msg.scheduledMsg) backend.editScheduled(msg.modelData.draft_id, msg.modelData.client_message_id || "", editBox.formattedText(), JSON.stringify(editBox.mediaInUse()), String(Math.round(editBox.scheduleAt)))
                        else backend.editMessageRich(msg.modelData.id, editBox.formattedText(), editBox.quote ? JSON.stringify(editBox.quote) : "", JSON.stringify(editBox.mediaInUse()))
                        root.editingId = ""
                    }
                    onCancelled: root.editingId = ""
                    Component.onCompleted: { setMessage(msg.modelData); focusEditor() }
                }
            }
            Rectangle {
                id: bubble
                visible: !msg.isRow && !msg.editingThis
                y: msg.bubbleY
                // Inline pictures, then GIFs and stickers.
                readonly property var imgs: (msg.modelData.images || []).concat(msg.modelData.media || [])
                readonly property bool imageOnly: imgs.length > 0 && msg.modelData.text === "Image"
                // A picture on its own, or big emoticons, show bare, without
                // the bubble (as in Teams).
                // A bot's card alone (OST TEST 126, Polls): Teams draws the card
                // itself, with no bubble around it.
                readonly property bool botCard: !msg.mine && !root.postsLayout && cards.length > 0 && !showBody
                    && (msg.modelData.files || []).length === 0 && (msg.modelData.images || []).length === 0 && String(msg.modelData.sender_mri || "").startsWith("28:")
                readonly property bool bare: (imageOnly || bigEmoticons || botCard) && !root.postsLayout
                readonly property real pad: bare || root.compact ? 0 : 15.7
                readonly property var files: msg.modelData.files || []
                // Cards (Adaptive Cards rendered natively; Teams' frame).
                readonly property var cards: (msg.modelData.cards || []).filter(c => root.cardKinds.indexOf(c.content_type) >= 0)
                readonly property real cardW: list.width >= 720 ? (cards.some(c => c.content_type !== "application/vnd.microsoft.card.adaptive") ? 452 : 448) : 360
                // Text shows unless the message is only a picture, only files
                // or only cards.
                readonly property bool showBody: !imageOnly && !(inFlow && !(msg.modelData.html || "").length) && (msg.modelData.deleted || ((msg.modelData.text || "").length > 0 && !(cards.length > 0 && !(msg.modelData.html || "").length)))
                // Pictures where they were written, with the text between
                // them (Teams keeps the order): [{pic} | {html}].
                readonly property var flow: msg.modelData.flow || []
                readonly property bool inFlow: flow.length > 0
                readonly property bool endsInText: inFlow && flow[flow.length - 1].html !== undefined
                readonly property real picsEnd: picsTop + picsH
                readonly property string textStyle: "<style>a { color: " + theme.brand + "; text-decoration: none; } "
                    + ".mention { color: " + theme.brandForeground1 + "; } "
                    + ".mention-me { color: " + theme.mentionMe + "; font-weight: 700; } "
                    + "p, div, li, body { line-height: " + (bigEmoticons ? 50 : 20) + "px; -qt-line-height-type: fixed; } "
                    // Measured (winpc, "OST TEST 70"): headings 18 light / 14 bold
                    // / 12 bold on 25.7 / 20 / 17.1 lines, 3 above and below;
                    // inline code Cascadia Mono on white (Teams also draws a
                    // hairline box, which Qt's rich text can't).
                    + "code { font-family: '" + theme.mono + "'; background-color: " + theme.surface + "; } "
                    + "p.h1 { font-size: 18px; font-weight: 300; line-height: 26px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; } "
                    + "p.h2 { font-size: 14px; font-weight: 700; line-height: 20px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; } "
                    + "p.h3 { font-size: 12px; font-weight: 700; line-height: 17px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; }</style>"
                // Teams' lines are 20 px; big emoticons (50 px) set their own.
                readonly property bool bigEmoticons: (msg.modelData.html || "").indexOf("width=\"50\" height=\"50\"") >= 0
                // Bigger text, headings, rules and tables set their own heights.
                readonly property bool richBody: /line-height:|<h[123]>|<hr|<table/.test(msg.modelData.html || "")
                readonly property real bodyH: !showBody ? 0 : bigEmoticons ? Math.max(1, body.lineCount) * 50 : richBody ? body.contentHeight : Math.max(1, body.lineCount) * 20
                // A quoted reply's card sits at the top (Teams: 10.7 down, the
                // text 4 under it).
                // A Threads-layout message's subject (Teams: an h2, 18/600 on
                // a 25.7 line, 8 under it; measured "OST TEST 88").
                readonly property real subjectH: !root.postsLayout && (msg.modelData.subject || "").length > 0 ? 33.7 : 0
                readonly property real quoteShift: subjectH + (msg.modelData.quote ? 60.3
                    // A forward card sits 14.7 down; a note 4 under it, else
                    // the bubble ends 9 under it (Teams).
                    : msg.modelData.forward ? fwdCard.height + (showBody ? 12 : 8.4)
                    // The shared-reply line: 16 tall, 3.3 down, the text 8
                    // under it (Teams).
                    : msg.sharedHead ? 28
                    // "Sending on …": 12 px on a 17.1 line 6.6 down, the
                    // text 21.1 lower than usual (Teams).
                    : msg.scheduledMsg ? 21.1 : 0)
                // In a flow the text's own blank line sets the gap (Teams).
                readonly property real picsTop: showBody ? body.y + bodyH + (inFlow ? 0 : 8) : (bare ? 0 : 8)
                readonly property bool hasPics: imgs.length > 0 || inFlow
                // A code card spans the bubble (Teams).
                readonly property bool hasCode: flow.some(p => !!p.code)
                readonly property real picsH: hasPics ? pics.implicitHeight : 0
                readonly property real filesTop: hasPics ? picsEnd + 8 : (showBody ? body.y + bodyH + 8 : 8)
                // Measured: a card sits 8 under the bubble's top (or the text),
                // 17.3 in, and the bubble ends 10.7 under it.
                readonly property real cardsTop: botCard ? 0 : showBody ? body.y + bodyH + 8 : 8
                width: root.postsLayout ? msg.maxBubble
                    : botCard ? cardCol.width
                    : cards.length > 0 ? Math.max(cardCol.width + 2 * 17.3, showBody ? body.implicitWidth + 2 * pad : 0)
                    : hasCode ? msg.maxBubble
                    : Math.min(msg.maxBubble, Math.max(msg.sharedHead ? sharedRow.implicitWidth : 0, msg.scheduledMsg ? scheduleLine.implicitWidth : 0, subjectLine.visible ? subjectLine.implicitWidth : 0, showBody ? body.implicitWidth + (msg.modelData.deleted && msg.mine ? 12 + undoMetrics.advanceWidth : 0) : 0, pics.implicitWidth, files.length > 0 ? fileCol.implicitWidth : 0, msg.modelData.quote ? quoteCard.width : 0, msg.modelData.forward ? fwdCard.width : 0) + 2 * pad)
                TextMetrics { id: undoMetrics; text: "Undo"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                height: botCard ? cardCol.height
                    : cards.length > 0 ? cardsTop + cardCol.height + 10.7
                    : bare && files.length === 0 ? (bigEmoticons ? bodyH : picsH)
                    : files.length > 0 ? filesTop + fileCol.implicitHeight + 8
                    : hasPics ? picsEnd + (endsInText || (showBody && !inFlow) ? 8.6 : 8)
                    : root.compact ? bodyH + 2 + quoteShift
                    : bodyH + 15.3 + quoteShift
                // Teams: 6 px corners, squared on the inner side where a
                // group's bubbles meet (bottom of the first, top of the rest).
                readonly property real r: root.postsLayout ? theme.radius : 6
                readonly property bool joinUp: !root.postsLayout && msg.grouped
                readonly property bool joinDown: !root.postsLayout && msg.modelData.groupNext === true
                radius: r
                topLeftRadius: !msg.mine && joinUp ? 0 : r
                bottomLeftRadius: !msg.mine && joinDown ? 0 : r
                topRightRadius: msg.mine && joinUp ? 0 : r
                bottomRightRadius: msg.mine && joinDown ? 0 : r
                // A scheduled message: #FAFAFA with a #D1D1D1 hairline (Teams).
                color: msg.scheduledMsg ? theme.pick("#FAFAFA", "#1F1F1F") : bare || (root.compact && !msg.sendFailed) ? "transparent" : msg.sendFailed ? theme.redBackground1 : root.postsLayout ? theme.surface : (msg.mine ? theme.brandTint : theme.bubble)
                border.color: msg.scheduledMsg ? theme.pick("#D1D1D1", "#666666") : msg.sendFailed ? theme.redBorder1 : root.postsLayout ? theme.dividerSoft
                    : root.threadsLayout && root.openThreadRoot === msg.modelData.id ? theme.brand : "transparent"
                x: root.compact ? 64 : msg.mine ? parent.width - root.gutR - width : root.gutContent
                Text {
                    id: scheduleLine
                    visible: msg.scheduledMsg
                    x: bubble.pad; y: 6.6 + bubble.subjectH; height: 17.1
                    verticalAlignment: Text.AlignVCenter
                    text: "Sending on " + (msg.scheduledMsg ? Qt.formatDate(new Date(msg.modelData.scheduled_at), "dddd, MMM d") + " at " + Qt.formatTime(new Date(msg.modelData.scheduled_at), "h:mm AP") : "")
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                }
                Text {
                    id: subjectLine
                    visible: bubble.subjectH > 0
                    x: bubble.pad; y: root.compact ? 0 : 6.7
                    width: Math.min(implicitWidth, msg.maxBubble - 2 * bubble.pad)
                    height: 25.7; verticalAlignment: Text.AlignVCenter
                    text: msg.modelData.subject || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                    color: theme.text
                    Accessible.role: Accessible.Heading
                }
                Row {
                    id: sharedRow
                    visible: !!msg.sharedHead
                    x: bubble.pad; y: 10 + bubble.subjectH
                    spacing: 4
                    FluentIcon { name: msg.sharedHead === "thread" ? "chat-multiple-20" : "channel-arrow-left-20"; size: 16; color: theme.textSecondary }
                    Text {
                        height: 16; verticalAlignment: Text.AlignVCenter
                        textFormat: Text.RichText
                        text: msg.sharedHead === "thread"
                            ? "Replied in thread: <a href=\"thread\" style=\"text-decoration: none; color: " + theme.brandForeground1 + "\">" + root.escapeHtml(msg.modelData.thread_title || "") + "</a>"
                            : "Also sent to channel"
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                        onLinkActivated: root.openThread(msg.modelData.root_id)
                        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    }
                }
                // Several cards stack 8 apart (Teams, OST TEST 122).
                Column {
                    id: cardCol
                    visible: bubble.cards.length > 0
                    x: bubble.botCard ? 0 : 17.3; y: bubble.cardsTop
                    width: bubble.cardW
                    spacing: 8
                    Repeater {
                        model: bubble.cards
                        Loader {
                            id: cardLoader
                            required property var modelData
                            required property int index
                            sourceComponent: modelData.content_type === "application/vnd.microsoft.card.adaptive" ? adaptiveComp
                                : modelData.content_type === "application/vnd.microsoft.teams.card.list" ? listComp
                                : modelData.content_type === "application/vnd.microsoft.teams.card.o365connector" ? connectorComp : heroComp
                            Component {
                                id: adaptiveComp
                                AdaptiveCard {
                                    id: ac
                                    // A bot's card: what its actions and refresh
                                    // returned replaces it (cardOverrides), and
                                    // Teams' response bar sits under it.
                                    readonly property string cardKey: msg.modelData.id + ":" + cardLoader.index
                                    readonly property var override: root.cardOverrides[cardKey] || null
                                    readonly property var footerState: root.cardFooters[cardKey] || null
                                    onAction: (a, inputs) => root.cardAction(msg.modelData, cardLoader.index, a, inputs)
                                    Component.onCompleted: root.maybeRefreshCard(msg.modelData, cardLoader.index, modelData.content)
                                    CardResponseBar {
                                        visible: !!ac.footerState
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        busy: !!ac.footerState && ac.footerState.busy === true
                                        text: ac.footerState ? ac.footerState.text : ""
                                        error: !!ac.footerState && ac.footerState.error === true
                                        onDismissed: root.setCardFooter(ac.cardKey, null)
                                    }
                                    // A shared app's card (Teams' app-store link preview):
                                    // 16 from the top and Teams' links and buttons under it.
                                    readonly property string sharedApp: String(modelData.app_id).toUpperCase() === "08648EF4-F8B6-45DA-AB44-74F21AABD840"
                                        && modelData.content && modelData.content.selectAction ? String(modelData.content.selectAction.id || "") : ""
                                    content: override || modelData.content
                                    cardWidth: sharedApp ? 356 : (list.width >= 720 ? 448 : 360)
                                    bottomExtra: footerState ? 28.67 : 0
                                    topInset: sharedApp ? 16 : 26
                                    hostsLinks: true
                                    footer: sharedApp ? appCardFooter : null
                                    Component {
                                        id: appCardFooter
                                        AppCardFooter {
                                            appId: ac.sharedApp
                                            onDetails: root.openAppDetails(ac.sharedApp)
                                            onPermissions: root.openAppDetails(ac.sharedApp)
                                            onShare: root.shareApp(ac.sharedApp)
                                            onOpenApp: root.openAppById(ac.sharedApp)
                                        }
                                    }
                                    // Tapping the card opens the app's details, as Teams.
                                    onOpenLink: link => root.openLink(link)
                                }
                            }
                            Component {
                                id: listComp
                                ListCard {
                                    content: modelData.content
                                    cardWidth: list.width >= 720 ? 452 : 360
                                    onImBack: t => root.send(t)
                                }
                            }
                            Component {
                                id: connectorComp
                                ConnectorCard {
                                    content: modelData.content
                                    cardWidth: list.width >= 720 ? 452 : 360
                                }
                            }
                            Component {
                                id: heroComp
                                HeroCard {
                                    content: modelData.content
                                    thumbnail: modelData.content_type === "application/vnd.microsoft.card.thumbnail"
                                    cardWidth: list.width >= 720 ? 452 : 360
                                    onImBack: t => root.send(t)
                                }
                            }
                        }
                    }
                }
                // Inline pictures, scaled to fit the bubble (as in Teams).
                // In a flow, the text between them too.
                Column {
                    id: pics
                    x: bubble.pad; y: bubble.picsTop
                    spacing: bubble.inFlow ? 0 : 4
                    Repeater {
                        model: bubble.inFlow ? bubble.flow.map(p => p.pic !== undefined ? bubble.imgs[p.pic] : p.quote !== undefined ? { flowQuote: p.quote } : p.code ? { flowCode: p.code } : { flowText: p.html }) : bubble.imgs
                        Item {
                            id: part
                            required property var modelData
                            required property int index
                            readonly property bool isText: modelData.flowText !== undefined
                            readonly property bool isQuote: modelData.flowQuote !== undefined
                            readonly property bool isCode: modelData.flowCode !== undefined
                            readonly property bool isPic: !isText && !isQuote && !isCode
                            readonly property bool richText: isText && /line-height:|<h[123]>|<hr|<table/.test(modelData.flowText)
                            // Teams: a picture after text or another picture
                            // sits 4 below it (the GIF's margin); text follows
                            // a picture directly; a code card 6 under text.
                            readonly property real gap: !bubble.inFlow ? 0 : isPic && (index > 0 || bubble.showBody) ? 4 : isCode && (index > 0 || bubble.showBody) ? 6 : 0
                            width: isText ? flowText.width : isQuote ? quoteBox.width : isCode ? codeCard.width : pic.width
                            height: gap + (isText ? (richText ? flowText.contentHeight : Math.max(1, flowText.lineCount) * 20)
                                : isQuote ? 7 + quoteBox.height + 7 : isCode ? codeCard.height : pic.height)
                            // Teams' quote: white, a #D1D1D1 hairline, rounded
                            // 4, 7/15 in, a 2.67 bar 3 in; 7 above and below.
                            Rectangle {
                                id: quoteBox
                                visible: part.isQuote
                                y: 7
                                width: part.isQuote ? Math.min(msg.maxBubble - 2 * bubble.pad, quoteText.implicitWidth + 30 + 1.3) : 0
                                height: part.isQuote ? quoteText.contentHeight + 14 + 1.3 : 0
                                radius: 4
                                color: theme.surface
                                border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                                Rectangle { x: 3; y: 3; width: 2.67; height: parent.height - 6; radius: 1.5; color: theme.pick("#D1D1D1", "#666666") }
                                TextEdit {
                                    id: quoteText
                                    x: 15.7; y: 7.7
                                    width: Math.min(msg.maxBubble - 2 * bubble.pad - 31.3, implicitWidth)
                                    readOnly: true; selectByMouse: true
                                    selectionColor: theme.selectionFill; selectedTextColor: theme.text
                                    text: part.isQuote ? bubble.textStyle + theme.messageHtml(part.modelData.flowQuote) : ""
                                    textFormat: TextEdit.RichText; wrapMode: TextEdit.Wrap
                                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                                    onLinkActivated: link => root.openLink(link)
                                }
                            }
                            // Teams' code block (code-block-editor-deserialized):
                            // a 32 px header (code icon, the language 12/16
                            // #616161, Copy), then the code in Cascadia Mono
                            // 14/24 with line numbers, 8/12 in; rounded 8.
                            Item {
                                id: codeCard
                                visible: part.isCode
                                y: part.gap
                                readonly property var code: part.isCode ? part.modelData.flowCode : ({})
                                readonly property var lines: part.isCode ? String(code.text || "").split("\n") : []
                                width: part.isCode ? msg.maxBubble - 2 * bubble.pad : 0
                                height: part.isCode ? 32 - 0.8 + codeBody.height : 0
                                Rectangle {
                                    width: parent.width; height: 40
                                    radius: 8
                                    color: theme.surface
                                    border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                                    FluentIcon { x: 10.7; y: 6; name: "code-block-20"; size: 20; color: theme.textSecondary }
                                    Text {
                                        x: 36.7; y: 8.7; height: 16; verticalAlignment: Text.AlignVCenter
                                        text: codeCard.code.name || "Plain Text"
                                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                                    }
                                    Rectangle {
                                        x: parent.width - 6.2 - 24; y: 5.5; width: 24; height: 23.3; radius: 4
                                        color: copyHover.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "copy-20"; size: 20; color: theme.textStrong }
                                        HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: backend.copyText(codeCard.code.text || "") }
                                        ToolTip.visible: copyHover.hovered
                                        ToolTip.text: "Copy"
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Copy code"
                                    }
                                }
                                Rectangle {
                                    id: codeBody
                                    y: 32 - 0.8
                                    width: parent.width
                                    height: 8 + 4 + codeCard.lines.length * 24 + 4 + 8 + 1.3
                                    radius: 8
                                    color: theme.surface
                                    border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                                    // Square top corners where it meets the header.
                                    Rectangle { x: 0.67; y: 0.67; width: parent.width - 1.3; height: 8; color: theme.surface }
                                    Column {
                                        x: 12; y: 12
                                        Repeater {
                                            model: codeCard.lines
                                            Item {
                                                required property var modelData
                                                required property int index
                                                width: codeBody.width - 24; height: 24
                                                Text {
                                                    width: 30; height: 24; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                                                    text: index + 1
                                                    font.family: theme.mono; font.pixelSize: 14; color: theme.pick("#8A8886", "#ADADAD")
                                                }
                                                Text {
                                                    x: 42.7; width: parent.width - 42.7; height: 24; verticalAlignment: Text.AlignVCenter
                                                    text: parent.modelData
                                                    textFormat: Text.PlainText
                                                    elide: Text.ElideRight
                                                    font.family: theme.mono; font.pixelSize: 14; color: theme.text
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            TextEdit {
                                id: flowText
                                visible: part.isText
                                width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                                readOnly: true
                                selectByMouse: true
                                persistentSelection: false
                                selectionColor: theme.selectionFill
                                selectedTextColor: theme.text
                                text: part.isText ? bubble.textStyle + root.marked(msg.modelData.id, theme.messageHtml(part.modelData.flowText)) : ""
                                textFormat: TextEdit.RichText
                                wrapMode: TextEdit.Wrap
                                font.family: theme.font; font.pixelSize: theme.base
                                color: theme.text
                                onLinkActivated: link => root.openLink(link)
                                HoverHandler { cursorShape: flowText.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                            }
                        // Rounded 4 px with a hairline border, as Teams draws them.
                        Item {
                            id: pic
                            visible: part.isPic
                            y: part.gap
                            readonly property var modelData: part.isPic ? part.modelData : ({})
                            // A GIF or sticker (fun picker) rather than an AMS picture.
                            readonly property bool fun: !!modelData.kind
                            // Teams' image component scales anything wider
                            // than 404 down to 404.
                            readonly property real maxW: fun ? Math.min(404, msg.maxBubble - 2 * bubble.pad) : msg.maxBubble - 2 * bubble.pad
                            readonly property real w0: modelData.width > 0 ? modelData.width : 240
                            readonly property real h0: modelData.height > 0 ? modelData.height : 160
                            width: Math.min(maxW, w0); height: fun ? Math.floor(width * h0 / w0) : width * h0 / w0
                            // GIFs and stickers play when the message was new
                            // (Teams' shouldAutoPlayGifs); clicking plays or stops.
                            property bool playing: msg.modelData.autoplay === true
                            Image {
                                visible: !pic.fun
                                anchors.fill: parent
                                source: pic.fun ? "" : (pic.modelData.local_path || "")
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            AnimatedImage {
                                id: funImage
                                visible: pic.fun
                                anchors.fill: parent
                                source: pic.fun ? pic.modelData.url : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                playing: pic.playing && status === AnimatedImage.Ready
                                paused: !pic.playing
                            }
                            RoundedCorners {
                                anchors.fill: parent
                                radius: pic.fun ? 6 : theme.radius
                                background: bubble.bare ? root.color : bubble.color
                            }
                            Rectangle { visible: !pic.fun || pic.modelData.kind === "sticker"; anchors.fill: parent; color: "transparent"; border.color: theme.dividerSoft; radius: pic.fun ? 6 : theme.radius }
                            // Teams' play button over a still GIF or sticker: a
                            // 48 px circle, black at 80 %, white play icon.
                            Rectangle {
                                visible: pic.fun && !pic.playing && funImage.status === AnimatedImage.Ready
                                anchors.centerIn: parent
                                width: 48; height: 48; radius: 24
                                color: "#CC000000"
                                FluentIcon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; name: "play-20-filled"; size: 24; color: "white" }
                            }
                            TapHandler { enabled: pic.fun; onTapped: pic.playing = !pic.playing }
                            HoverHandler { enabled: pic.fun; cursorShape: Qt.PointingHandCursor }
                            Accessible.role: pic.fun ? Accessible.Button : Accessible.Graphic
                            Accessible.name: pic.fun ? (pic.modelData.alt || "") : "Image"
                        }
                        }
                    }
                }
                // Right-click: the same menu at the pointer, with the reaction
                // strip on top (Teams' right-click menu).
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: actions.can
                    onTapped: ev => {
                        // With text selected, the text's own menu (as Teams
                        // falls back to the native one).
                        if (body.selectedText.length > 0) { textMenu.target = body; textMenu.popup(bubble, ev.position.x, ev.position.y); return }
                        root.openMessageMenu(msg.modelData, bubble, true, ev.position.x, ev.position.y)
                    }
                }
                ForwardCard {
                    id: fwdCard
                    visible: !!msg.modelData.forward
                    x: bubble.pad; y: 14.7 + bubble.subjectH
                    forward: msg.modelData.forward || null
                    maxWidth: msg.maxBubble - 2 * bubble.pad
                    onOpenOriginal: {
                        const f = msg.modelData.forward
                        if (f.thread_id === root.chatId) root.jumpToMessage(f.message_id)
                        else if (f.thread_id) backend.selectChat(f.thread_id, "")
                    }
                }
                QuoteCard {
                    id: quoteCard
                    visible: !!msg.modelData.quote
                    x: bubble.pad; y: 10.7 + bubble.subjectH
                    quote: msg.modelData.quote || null
                    maxWidth: msg.maxBubble - 2 * bubble.pad
                    onActivated: root.jumpToMessage(msg.modelData.quote.message_id)
                }
                // Selectable, as in Teams (a message's text can be selected and
                // copied); read-only.
                TextEdit {
                    id: body
                    visible: bubble.showBody
                    x: bubble.pad; y: bubble.bare ? 0 : root.compact ? bubble.quoteShift : 6.7 + bubble.quoteShift
                    width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: false
                    selectionColor: theme.selectionFill
                    selectedTextColor: theme.text
                    // Teams' 14/20 text (a fixed 20 px line).
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : bubble.textStyle + root.marked(msg.modelData.id, msg.modelData.html ? theme.messageHtml(msg.modelData.html) : msg.modelData.text)
                    textFormat: msg.modelData.deleted ? TextEdit.PlainText : TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    // Teams' tombstone: italic, in the normal text colour.
                    font.italic: msg.modelData.deleted === true
                    color: theme.text
                    onLinkActivated: link => root.openLink(link)
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    Accessible.name: msg.modelData.text
                }
                // Undo, 12 px after the tombstone text (14 px semibold brand), for
                // your own message deleted in this session; never for Urgent
                // (Teams 4584).
                Text {
                    visible: msg.modelData.deleted === true && msg.mine && msg.modelData.importance !== "urgent"
                    x: body.x + body.contentWidth + 12; y: body.y
                    text: "Undo"
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.brandLink
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.undoDeleteMessage(msg.modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Undo"
                }
                // File cards (FileCard: Teams' card with its location, Share
                // and More actions over the preview) and channel tab links.
                Column {
                    id: fileCol
                    x: bubble.pad; y: bubble.filesTop
                    spacing: 8
                    Repeater {
                        model: bubble.files
                        Item {
                            id: fc
                            required property var modelData
                            readonly property string t: (modelData.file_type || "").toLowerCase()
                            readonly property bool tabLink: t === "deeplink"
                            readonly property var linked: tabLink ? root.linkedTabs.find(x => x.id === modelData.item_id) || null : null
                            width: tabLink ? tabCard.width : fileCard.width
                            height: tabLink ? tabCard.height : fileCard.height
                            FileCard {
                                id: fileCard
                                visible: !fc.tabLink
                                width: Math.min(320, msg.maxBubble - 2 * bubble.pad)
                                file: fc.modelData
                                thumbnail: {
                                    root.thumbsRev
                                    return fc.tabLink ? "" : backend.fileThumbnail(fc.modelData.object_url || "")
                                }
                                onOpenRequested: root.openFileRequested(fc.modelData)
                                onShareRequested: root.fileCardAct(fc.modelData, "Share")
                                onMenuRequested: anchor => root.openFileCardMenu(fc.modelData, anchor)
                                Component.onCompleted: if (!fc.tabLink) root.cardViewsForTest[fc.modelData.object_url] = fileCard
                            }
                            // A channel tab's link (Teams' deep-link-chiclet, measured
                            // in a tab's conversation): white, radius 4, a #F0F0F0
                            // line and a soft shadow, padding 7 3 7 11; the app's
                            // icon (38, radius 4) and the tab's name (14 semibold)
                            // 11.5 after it. Clicking opens the tab.
                            Rectangle {
                                id: tabCard
                                visible: fc.tabLink
                                width: Math.min(318, msg.maxBubble - 2 * bubble.pad)
                                height: 52.3
                                radius: 4
                                color: theme.surface
                                border.color: theme.pick("#F0F0F0", "#3D3D3D")
                                border.width: 0.67
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 4 }
                                Image {
                                    x: 11.2; y: 7.1; width: 38; height: 38
                                    source: fc.linked ? fc.linked.icon : ""
                                    sourceSize: Qt.size(76, 76)
                                    RoundedCorners { anchors.fill: parent; radius: 4; background: theme.surface }
                                }
                                Text {
                                    x: 60.7; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 60.7 - 8
                                    elide: Text.ElideRight
                                    text: fc.modelData.name
                                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                                HoverHandler { id: tabLinkHover; enabled: fc.tabLink; cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: fc.tabLink; onTapped: root.openLinkedTab(fc.modelData.item_id) }
                                ToolTip.visible: fc.tabLink && tabLinkHover.hovered
                                ToolTip.delay: 500
                                ToolTip.text: fc.modelData.name
                                Accessible.role: Accessible.Link
                                Accessible.name: "Tab " + fc.modelData.name
                            }
                        }
                    }
                }
            }
            // Teams marks a message that @mentions you with an "@" beside it.
            Text {
                visible: msg.modelData.mentions_me === true
                x: msg.mine ? bubble.x - width - 8 : bubble.x + bubble.width + 8
                y: bubble.y + (Math.min(bubble.height, 40) - height) / 2
                text: "@"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                color: theme.mentionMe
                Accessible.name: "Mentions you"
            }
            // Teams' reaction summary: overlapping the bubble's bottom edge by
            // 4, 15.7 in from its start (at its end on your messages).
            ReactionSummary {
                id: reactionRow
                host: msgHost
                messageId: msg.modelData.id
                reactions: msg.reactions
                visible: msg.reactions.length > 0 && !msg.editingThis
                y: bubble.y + bubble.height - 4.3
                x: msg.mine ? bubble.x + bubble.width - 15.7 - width : bubble.x + 15.7
                z: 4
            }
            HoverHandler { id: msgHover }
            // Teams' hover bar, end-aligned on the bubble's top edge.
            Item {
                visible: msg.repliesDivH > 0
                y: msg.height - 16; height: 16
                // Across the pane, 14 in from each side.
                x: 14; width: parent.width - 28
                // Fluent's Divider: 0.67 NeutralStroke2 lines 20 from the label.
                Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: Math.max(8, (parent.width - divLabel.implicitWidth) / 2 - 20); height: 1; color: theme.divider }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; width: Math.max(8, (parent.width - divLabel.implicitWidth) / 2 - 20); height: 1; color: theme.divider }
                Text {
                    id: divLabel
                    anchors.centerIn: parent
                    text: msg.repliesCount + (msg.repliesCount === 1 ? " reply" : " replies")
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    Accessible.role: Accessible.Separator
                }
            }
            // "{N} reply/replies  Last reply {time}" under a thread starter,
            // with the last replier's picture; opens the thread.
            Row {
                visible: msg.threadLineH > 0
                y: msg.height - 26
                x: msg.mine ? bubble.x + bubble.width - width : bubble.x
                spacing: 8
                Avatar { anchors.verticalCenter: parent.verticalCenter; size: 20; name: msg.modelData.thread_last_sender || ""; photoId: msg.modelData.thread_last_mri || "" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: msg.modelData.thread_replies + (msg.modelData.thread_replies === 1 ? " reply" : " replies")
                    // Bold while the thread has unread replies (Teams).
                    font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
                    font.weight: (msg.modelData.thread_unread || 0) > 0 ? Font.Bold : Font.Normal
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openThread(msg.modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: text + ", open thread"
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Last reply " + root.stamp(msg.modelData.thread_last); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            }
            HoverBar {
                id: actions
                readonly property bool can: !msg.isRow && !msg.modelData.deleted && !msg.sendPending && !msg.sendFailed && !msg.editingThis
                host: msgHost
                message: msg.modelData
                // A reply also sent to the channel: Reply in thread (its
                // thread), no Edit (Teams).
                acts: msg.scheduledMsg ? [{ key: "edit", icon: "edit-20", tip: "Edit" }] : (root.threadsLayout ? [{ key: "thread", icon: "chat-multiple-20", tip: "Reply in thread" }] : []).concat(msg.sharedHead === "thread" ? [] : msg.mine
                    ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                    : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }])
                onThreadRequested: m => root.openThread(m.root_id || m.id)
                visible: can && (msgHover.hovered || actions.hovered || (msgHost.messageMenu.opened && !msgHost.messageMenu.rightClick && msgHost.messageMenu.message && msgHost.messageMenu.message.id === msg.modelData.id) || root.forceBarId === msg.modelData.id)
                z: 5
                y: bubble.y - height
                x: bubble.x + bubble.width - width
            }
            // The delivery option's badge: a 16 px red icon 4 from the bubble,
            // on its start side for your messages (measured), 12 down.
            FluentIcon {
                visible: !msg.isRow && !msg.editingThis && (msg.modelData.importance === "high" || msg.modelData.importance === "urgent")
                name: msg.modelData.importance === "urgent" ? "alert-urgent-20-filled" : "important-20-filled"
                size: 16; color: theme.redForeground3
                x: msg.mine ? bubble.x - 4 - 16 : bubble.x + bubble.width + 4
                y: bubble.y + 12
                Accessible.name: msg.modelData.importance === "urgent" ? "Urgent badge" : "Important badge"
            }
            // Sent tick on your newest message, "Seen" eye on the newest one
            // the other person has read.
            // Pending messages show the Circle ("Sending..." / "Retrying..."),
            // failed ones the red warning ("Failed"); each icon has Teams'
            // tooltip.
            FluentIcon {
                id: statusIcon
                readonly property bool seen: msg.modelData.latestSeen === true
                readonly property string tip: msg.scheduledMsg ? "Scheduled" : msg.sendPending ? (msg.modelData.send_note || "")
                    : msg.sendFailed ? "Failed"
                    : seen ? (root.isGroup ? "Seen by everyone" : "Seen") : "Sent"
                visible: msg.mine && !msg.isRow && !msg.editingThis && (msg.scheduledMsg || msg.sendPending || msg.sendFailed || seen || (msg.modelData.latestMine === true && !msg.modelData.seen))
                name: msg.scheduledMsg ? "clock-12" : msg.sendPending ? "circle-12" : msg.sendFailed ? "warning-12-filled" : seen ? "seen-12" : "sent-12"
                size: 12; color: msg.sendFailed ? theme.redForeground1 : theme.brand
                x: bubble.x + bubble.width + 8
                y: bubble.y + bubble.height - 14
                HoverHandler { id: statusHover }
                ToolTip {
                    visible: statusHover.hovered; delay: 500
                    y: statusIcon.height + 4
                    padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: statusIcon.tip; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.name: tip
            }
            // A failed message's Retry and Delete, to the bubble's left
            // (Teams' comfy layout: icon-only, transparent; Delete in red).
            Row {
                visible: msg.sendFailed
                spacing: 4
                x: bubble.x - 8 - width
                y: bubble.y + Math.max(0, (Math.min(bubble.height, 36) - 24) / 2)
                Repeater {
                    model: [
                        { key: "retry", icon: "arrow-clockwise-16", tip: "Retry", name: "Retry", show: msg.modelData.can_retry === true },
                        { key: "delete", icon: "delete-16", tip: "Delete", name: "Delete this message", show: true }
                    ].filter(b => b.show)
                    Rectangle {
                        id: failBtn
                        required property var modelData
                        width: 24; height: 24; radius: 4
                        color: failHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon {
                            anchors.centerIn: parent; size: 16; name: failBtn.modelData.icon
                            color: failBtn.modelData.key === "delete" ? theme.redForeground1 : theme.textStrong
                        }
                        HoverHandler { id: failHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: failBtn.modelData.key === "retry"
                                ? backend.retryFailedMessage(msg.modelData.client_message_id)
                                : backend.deleteFailedMessage(msg.modelData.client_message_id)
                        }
                        ToolTip {
                            visible: failHover.hovered; delay: 500
                            y: parent.height + 4
                            padding: 8
                            background: FluentSurface { depth: 16; radius: 4 }
                            contentItem: Text { text: failBtn.modelData.tip; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name
                    }
                }
            }
        }
    }

    // Suggested replies (Teams' smart replies; api::smart_replies): the
    // service's newest set, for its target message only while that is the
    // chat's newest (not yours, not deleted, not edited since), when
    // Settings ▸ Chats ▸ Suggested replies is on. Teams' row (142420
    // "smart-replies-renderer", read from its code and Griffel CSS; the
    // test account Teams runs as gets none to measure): right-aligned
    // above the compose box, small Fluent buttons (24 tall, radius 4) with
    // a 1 px BrandForeground1 edge, 12 px semibold brand text, padding 0
    // 14, 4 either side; hover NeutralBackground3Hover with the brand-hover
    // text and edge, pressed BrandBackground2; as many as fit, 3 at most.
    // Clicking one sends it.
    property var smartReplies: null
    readonly property bool smartRepliesOn: {
        const s = backend.settingsJson ? JSON.parse(backend.settingsJson) : {}
        const v = ((s.props || {}).suggestedRepliesSettings || {}).suggestionsEnabled
        return v !== false
    }
    readonly property var newestMessage: { for (let i = root.messages.length - 1; i >= 0; i--) { const m = root.messages[i]; if (m.kind === "message") return m } return null }
    readonly property var smartReplyChips: {
        const set = root.smartReplies, m = root.newestMessage
        if (!set || !m || !root.smartRepliesOn || root.isChannel || root.pane || m.mine || m.deleted || m.id !== set.target) return []
        return set.replies.filter(r => r.kind === "reply").slice(0, 3)
    }
    Connections {
        target: backend
        function onSmartRepliesReady(chatId, json) { if (chatId === root.chatId) root.smartReplies = JSON.parse(json) }
    }
    // The service writes suggestions a moment after a message lands: ask on
    // opening the chat and again shortly after someone else's message.
    onNewestMessageChanged: if (newestMessage && !newestMessage.mine && !isChannel) { smartReplyRetry.count = 0; smartReplyRetry.restart() }
    Timer {
        id: smartReplyRetry
        property int count: 0
        interval: count === 0 ? 2500 : 5000
        onTriggered: { backend.loadSmartReplies(root.chatId); if (++count < 3 && !(root.smartReplies && root.newestMessage && root.smartReplies.target === root.newestMessage.id)) restart() }
    }
    Row {
        id: smartReplyRow
        visible: root.smartReplyChips.length > 0 && compose.visible && root.typingText.length === 0
        anchors.right: compose.right
        y: compose.y - 8 - height
        height: 24
        layoutDirection: Qt.RightToLeft
        Accessible.role: Accessible.ToolBar
        Accessible.name: "Suggested replies"
        Repeater {
            model: root.smartReplyChips
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool fits: x >= 0
                width: chipText.implicitWidth + 28 + 8; height: 24
                color: "transparent"
                Rectangle {
                    x: 4; width: parent.width - 8; height: 24; radius: 4
                    color: chipTap.pressed ? theme.pick("#E8EBFA", "#2B2B40") : chipHover.hovered ? theme.pick("#EBEBEB", "#383838") : theme.surface
                    border.width: 1
                    border.color: chipHover.hovered || chipTap.pressed ? theme.brandHover : theme.brand
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.title
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: chipHover.hovered || chipTap.pressed ? theme.brandHover : theme.brand
                    }
                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: chipTap; onTapped: { root.send(chip.modelData.value); root.smartReplies = null } }
                    Accessible.role: Accessible.Button
                    Accessible.name: chip.modelData.title
                }
            }
        }
    }
    function smartRepliesForTest() { return { set: root.smartReplies, chips: root.smartReplyChips.map(c => c.title), shown: smartReplyRow.visible } }

    // Typing indicator, as Teams draws it (chat-pane gutter box): the
    // latest typer's avatar, 16 px into the compose box and 24 px above it,
    // its bottom tucked under the box (declared before it, so drawn below);
    // then in a group chat the label ("X and Y are typing", 12 px, one line,
    // margin 0 0 4 12); then the pulsing dots. A 1:1 chat shows the avatar
    // and dots only; the label is then for screen readers.
    Row {
        id: typingRow
        visible: root.typingText.length > 0
        x: compose.x + 16; y: compose.y - 24
        height: 32
        Accessible.role: Accessible.StaticText
        Accessible.name: root.typingText
        Avatar { size: 32; name: root.typingAvatar; photoId: root.typingAvatarId }
        Text {
            visible: root.isGroup
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
            leftPadding: 12
            width: Math.min(implicitWidth, compose.width - 32 - 12 - 4 - 3 * 6 - 2 * 3 - 32)
            text: root.typingText
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: 12
            color: theme.text
        }
        Item {
            width: 6 + 3 * 6 + 2 * 3; height: parent.height
            Row {
                x: 6; anchors.verticalCenter: parent.verticalCenter
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
    }

    // The open tab: "" is Chat (or Posts); others replace the messages.
    property string tab: ""

    // Find in chat: matches among the loaded messages, newest first.
    /// Find in chat's pane is open (Main hosts it).
    property bool finding: false
    // A message found by Find in chat: it's brought into view (older pages
    // load until it's there) and the search terms are marked in it, as
    // Teams does.
    property var findMark: ({ id: "", terms: [] })
    property string seekId: ""
    property int seekTries: 0
    // (A channel reply shows in its post: `inPost` is the post.)
    function showFound(id, terms, inPost) {
        findMark = { id: id, terms: terms || [] }
        seekId = inPost || id; seekTries = 0
        seek()
    }
    function seek() {
        if (!seekId) return
        if (root.postsLayout) { if (channelPosts.showPost(seekId)) { seekId = ""; return } }
        else {
            const i = (list.model || []).findIndex(m => m.id === seekId)
            if (i >= 0) { list.positionViewAtIndex(i, ListView.Center); seekId = ""; return }
        }
        if (backend.messagesHasOlder && seekTries < 40) {
            seekTries++
            if (!backend.messagesLoadingOlder) backend.loadOlderMessages()
        } else seekId = ""
    }
    onMessagesChanged: if (seekId) Qt.callLater(seek)
    function marked(id, html) { return id && id === findMark.id ? theme.markTerms(html, findMark.terms) : html }

    // An expanded tab (Teams' Expand tab, measured on winpc 2026-11-09):
    // the chat list goes and the channel's header gives way to the tab's
    // own (entity-header: 61 tall, white, a 0.67 px #E0E0E0 line under it,
    // padding 0 7 0 20): the app's icon (32, round) at 20, the tab's name
    // (18/25.7 bold) 20 after it, and "Collapse tab" (30 x 44, the filled
    // 20 px minimize arrow) at the right. Teams expands by routing to the
    // tab full screen, so leaving the tab or the channel collapses it.
    property bool tabExpanded: false
    property var expandedTab: null
    property var expandedAbout: null
    onTabChanged: { tabExpanded = false; tabConversationTab = null; manageApps = false }
    // A channel tab's conversation (Teams' btn-tab-conversation, measured
    // on winpc 2026-11-09): for app and website tabs, a 32 x 31.3 button
    // just before Meet now, "Show tab conversation" / "Hide tab
    // conversation" (the filled icon in brand while open); the pane opens
    // beside the channel (Main hosts it).
    readonly property var currentTab: isChannel && tab ? (channelTabs.find(t => t.name === tab) || null) : null
    property var tabConversationTab: null
    // Teams' channel Meet now (channel-meet-header-main-btn, measured on
    // winpc 2026-11-09): the video icon and "Meet now" (14 semibold), 97.2
    // wide from 834, else the icon alone (32); its chevron (20 x 32, a 16 px
    // glyph) ends 16 before Find on Posts, or before ··· on other tabs.
    readonly property bool channelMeetWide: width >= 834
    readonly property real channelMeetRight: (isChannel && tab !== "" ? width - 43 : contextLeft) - 16
    readonly property real channelMeetLeft: channelMeetRight - 20 - (channelMeetWide ? 97.17 : 32)
    signal channelMeetNow()
    // The open channel as the team list has it (its menu's state).
    readonly property var channelInfo: {
        if (!isChannel) return ({})
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === root.chatId); if (c) return c }
        return ({ id: root.chatId, name: root.chatName })
    }
    signal openChannelWindow(string channelId)
    signal manageChannel(string channelId)
    signal channelWorkflows(string channelId)
    ChannelMenu {
        id: channelMenu
        channel: root.channelInfo
        teamId: root.teamId; teamName: root.teamName
        newestPost: { const posts = root.messages.filter(m => m.kind === "message" && (!m.root_id || m.root_id === m.id)); return posts.length ? posts[posts.length - 1].id : "" }
        postsAtBottom: !backend.channelPostsAtTop
        movedItems: root.contextInline < 2 && root.threadsButton ? [{ key: "details", label: "Open channel details", icon: "panel-right-expand-20", keys: "Alt+P" }] : []
        onOpenDetails: participants.visible = !participants.visible
        onOpenInNewWindow: root.openChannelWindow(root.chatId)
        onManageChannel: root.manageChannel(root.chatId)
        onWorkflows: root.channelWorkflows(root.chatId)
    }
    function channelMenuForTest2() { return channelMenu }
    function expandTab(t) {
        expandedTab = t
        expandedAbout = null
        tabExpanded = true
        takeExpandedAbout()
        if (t.app_id && !expandedAbout) backend.appAboutLoad(t.app_id)
    }
    function takeExpandedAbout() {
        const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
        if (r && root.expandedTab && r.app === root.expandedTab.app_id && r.about) root.expandedAbout = r.about
    }
    Connections {
        target: backend
        enabled: root.tabExpanded && !root.expandedAbout
        function onAppAboutJsonChanged() { root.takeExpandedAbout() }
    }
    Rectangle {
        id: expandedHeader
        visible: root.tabExpanded
        width: parent.width; height: theme.headerHeight
        color: theme.surface
        AppIcon {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32
            source: (root.expandedTab && root.expandedTab.icon) || (root.expandedAbout ? root.expandedAbout.icon : "")
        }
        Text {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, collapseButton.x - x - 8)
            elide: Text.ElideRight
            text: root.expandedTab ? root.expandedTab.name : ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            id: collapseButton
            anchors.right: parent.right; anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 44; radius: 4
            color: collapseHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "arrow-minimize-20-filled"; size: 20; color: theme.text }
            HoverHandler { id: collapseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.tabExpanded = false }
            ToolTip.visible: collapseHover.hovered
            ToolTip.delay: 500
            ToolTip.text: "Collapse tab"
            Accessible.role: Accessible.Button
            Accessible.name: "Collapse tab"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    // Open tab in new window: the tab in a window of its own.
    Component { id: tabWindowComponent; TabWindow {} }
    function popOutTab(t) {
        const w = tabWindowComponent.createObject(null, { tab: t, teamId: root.teamId, channelId: root.chatId, teamName: root.teamName, channelName: root.chatName })
        w.closing.connect(() => w.destroy())
        w.show()
        return w
    }
    // Reload tab: Teams renders the tab again (its own state goes).
    function reloadTabView(t) {
        if (t.kind === "StaticExtension") channelFiles.reset()
        else if (t.kind === "ChannelPage" && webTabLoader.item) webTabLoader.item.reload()
    }

    function channelFilesForTest() { return channelFiles }
    // A channel's Shared tab: its folder in the team's SharePoint library.
    ChannelFiles {
        id: channelFiles
        visible: root.isChannel && root.tab === "Shared"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        teamId: root.teamId
        channelId: root.isChannel ? root.chatId : ""
        channelName: root.chatName
        reply: backend.channelFilesJson ? JSON.parse(backend.channelFilesJson) : ({})
        busy: backend.channelFilesBusy
        onLoad: (t, c, d, i) => backend.channelFilesLoad(t, c, d, i)
        onChange: (op, d, i, arg) => backend.channelFilesChange(op, d, i, arg)
    }
    // Shared: the files and links in this chat.
    Item {
        id: sharedPane
        visible: (root.tab === "Shared" && !root.isChannel) || root.tab === "Files"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        readonly property var files: root.messages.reduce((a, m) => a.concat((m.files || []).map(f => Object.assign({ from: m.sender, time: m.time }, f))), []).reverse()
        readonly property var links: root.messages.reduce((a, m) => {
            const found = (m.html || "").match(/href="(https?:[^"]+)"/g) || []
            return a.concat(found.map(h => ({ url: h.slice(6, -1).replace(/&amp;/g, "&"), from: m.sender, time: m.time })))
        }, []).reverse()
        Flickable {
            anchors.fill: parent
            contentHeight: sharedCol.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sharedCol
                x: 32; y: 20; width: parent.width - 64
                spacing: 8
                Text { text: "Files"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.files.length === 0
                    text: "Files shared in this chat appear here."
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.files
                    Rectangle {
                        required property var modelData
                        width: sharedCol.width; height: 52; radius: theme.radius
                        color: sfh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 32; color: theme.textSecondary }
                        Column {
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: sdh.hovered ? theme.selected : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "download-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: sdh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.downloadFile(JSON.stringify(parent.parent.modelData)) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Download " + parent.modelData.name
                        }
                        HoverHandler { id: sfh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openFile(modelData.share_url || modelData.object_url, modelData.name, "") }
                    }
                }
                Item { width: 1; height: 16 }
                Text { text: "Links"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.links.length === 0
                    text: "Links shared in this chat appear here."
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.links
                    Rectangle {
                        required property var modelData
                        width: sharedCol.width; height: 44; radius: theme.radius
                        color: slh.hovered ? theme.rowHover : "transparent"
                        Column {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24
                            Text { width: parent.width; text: parent.parent.modelData.url; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        HoverHandler { id: slh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
                    }
                }
            }
        }
    }
    // A channel tab that is a web page (Page): shown in place, signed in
    // with OST's web profile, as Teams shows it.
    Loader {
        id: webTabLoader
        active: !!root.webTab
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: WebApp { showHeader: false; pageOnly: true; location: root.chatName + (root.teamName ? " · " + root.teamName : ""); appName: root.webTab ? root.webTab.name : ""; appId: root.webTab ? (root.webTab.app_id || "") : ""; home: root.webTab ? root.webTab.content_url : "" }
    }
    // A meeting chat's Attendance tab.
    function attendanceViewForTest() { return attendanceTabLoader.item || (channelAttendanceLoader.item ? channelAttendanceLoader.item.children[0] : null) }
    Loader {
        id: attendanceTabLoader
        active: root.isMeetingChat && root.tab === "Attendance" && !!root.meeting
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: AttendanceView {
            thread: root.chatId; organizer: root.meeting.organizer_id; message: ""
            initialCall: root.attendanceCall
        }
    }
    // Tabs OST can't offer say so.
    Column {
        visible: !root.webTab && ["Notes", "Recap", "Storyline"].indexOf(root.tab) >= 0
        anchors.centerIn: parent
        spacing: 8
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "info-16"; size: 32; color: theme.textSecondary }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tab + " isn't available in OST yet."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
    }

    // A channel tab's menu, exactly as Teams builds it (the backend gives
    // each tab its chevron menu and right-click menu; docs/spec/channel-tabs.md).
    MenuPopup {
        id: tabMenu
        property var tab: null
        property var entries: []
        readonly property var icons: ({
            popOut: "window-new-20", expandTab: "arrow-maximize-20", reloadTab: "arrow-clockwise-20",
            goToWebsite: "globe-20", copyLink: "link-20", renameTab: "edit-20",
            devicePermissions: "shield-keyhole-20", aboutTab: "info-20", moveLeft: "arrow-left-20",
            moveRight: "arrow-right-20", removeTab: "delete-20"
        })
        items: entries.map(e => e.key === "divider" ? { separator: true } : { label: e.label, icon: icons[e.key] || "", enabled: e.enabled })
        function show(t, list, anchor, px, py) {
            tab = t; entries = list
            parent = anchor; x = px; y = py
            open()
        }
        onPicked: i => root.tabAction(entries[i].key, tab)
    }
    function tabAction(key, t) {
        if (key === "copyLink") backend.copyTabLink(root.teamId, root.chatId, JSON.stringify(t))
        else if (key === "goToWebsite") { if (t.website_url) Qt.openUrlExternally(t.website_url) }
        else if (key === "renameTab") renameDialog.start(t)
        else if (key === "removeTab") removeDialog.start(t)
        else if (key === "moveLeft") backend.channelTabChange("left", root.teamId, root.chatId, t.id, "")
        else if (key === "moveRight") backend.channelTabChange("right", root.teamId, root.chatId, t.id, "")
        else if (key === "reloadTab") root.reloadTabView(t)
        else if (key === "expandTab") root.expandTab(t)
        else if (key === "popOut" || key === "popOutChannelPage") root.popOutTab(t)
        else if (key === "aboutTab") aboutDialog.start(t)
        else if (key === "devicePermissions") appPermissions.show(t.app_id)
    }
    // Teams' App permissions for a tab's app.
    AppPermissionsDialog { id: appPermissions }
    // Teams' platform dialog (Fluent Dialog, as measured): 600 wide,
    // padding 24, radius 8, shadow 64; a header row of the title, "About"
    // and a close button; content below.
    component TabDialog: Popup {
        id: td
        property string title
        default property alias body: tdBody.data
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 24; width: 600
        background: FluentSurface { depth: 64; radius: 8 }
        contentItem: Column {
            Item { width: 1; height: 19.4 }
            Item {
                width: parent.width; height: 31.3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: td.title
                    font.family: theme.font; font.pointSize: 12.285; font.weight: Font.DemiBold; color: theme.text // 16.38 px
                }
                Row {
                    anchors.right: parent.right
                    Rectangle {
                        width: 96; height: 31.3; radius: 4
                        color: aboutHover.hovered ? theme.menuHover : "transparent"
                        Text { anchors.centerIn: parent; text: "About"; font.family: theme.font; font.pixelSize: theme.base; color: theme.brandLink }
                        HoverHandler { id: aboutHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.tabAction("aboutTab", renameDialog.visible ? renameDialog.tab : removeDialog.tab) }
                        Accessible.role: Accessible.Button; Accessible.name: "About"
                    }
                    Rectangle {
                        width: 32; height: 31.3; radius: 4
                        color: closeHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: td.close() }
                        Accessible.role: Accessible.Button; Accessible.name: "Close " + td.title
                    }
                }
            }
            Column { id: tdBody; width: parent.width }
        }
    }
    component PrimaryButton: Rectangle {
        id: pb
        property string label
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: !enabled ? theme.disabled : pbh.hovered ? theme.brandHover : theme.brandFill
        Text { anchors.centerIn: parent; text: pb.label; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        HoverHandler { id: pbh; cursorShape: pb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: pb.enabled; onTapped: pb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // Rename: "Rename {name}", "Tab name", the field with its validity icon,
    // Teams' errors (empty, over 128, already used), Save.
    TabDialog {
        id: renameDialog
        property var tab: null
        property bool saving: false
        property string failure: ""
        readonly property string error: {
            const v = renameField.text, t = v.trim()
            if (t === "") return "Name is required"
            if (v.length > 128) return "Tab name cannot exceed 128 characters."
            const others = root.channelTabs.filter(x => tab && x.id !== tab.id).map(x => x.name.trim().toLowerCase())
            if (others.indexOf(t.toLowerCase()) >= 0) return "You already have a tab with that name. Try a different one."
            return ""
        }
        title: "Rename " + (tab ? tab.name : "")
        function start(t) { tab = t; saving = false; failure = ""; renameField.text = t.name; open() }
        function save() {
            if (error || saving) return
            saving = true
            backend.channelTabChange("rename", root.teamId, root.chatId, tab.id, renameField.text.trim())
        }
        onOpened: { renameField.forceActiveFocus(); renameField.cursorPosition = renameField.text.length }
        Item { width: 1; height: 20 }
        Item {
            width: parent.width; height: 20
            Text { text: "Tab name"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Text { anchors.right: parent.right; text: renameDialog.error; font.family: theme.font; font.pixelSize: theme.base; color: theme.danger; Accessible.role: Accessible.AlertMessage }
        }
        Item { width: 1; height: 10 }
        Rectangle {
            width: parent.width; height: 32; radius: 4; color: theme.inputFilled
            TextInput {
                id: renameField
                x: 12; width: parent.width - 12 - 40; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                selectByMouse: true
                Keys.onReturnPressed: renameDialog.save()
                Keys.onEnterPressed: renameDialog.save()
                Accessible.name: "Tab name"
            }
            // Fluent's focus indicator: a 2 px brand line along the bottom.
            Rectangle {
                visible: renameField.activeFocus
                anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
                color: theme.brand
            }
            FluentIcon {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                name: renameDialog.error ? "error-circle-20-filled" : "presence-available-20-regular"; size: 20
                color: renameDialog.error ? theme.danger : theme.brandLink
            }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            visible: !!renameDialog.failure
            text: renameDialog.failure
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        Item { width: 1; height: 20 }
        Item {
            width: parent.width; height: 31.3
            PrimaryButton { anchors.right: parent.right; label: "Save"; enabled: !renameDialog.error && !renameDialog.saving; onClicked: renameDialog.save() }
        }
    }
    // Remove: "Want to remove this tab?" (a Page: "...this page?"), Remove
    // (then "Removing").
    TabDialog {
        id: removeDialog
        property var tab: null
        property bool removing: false
        property string failure: ""
        readonly property bool page: !!tab && tab.kind === "ChannelPage"
        title: page ? "Want to remove this page?" : "Want to remove this tab?"
        function start(t) { tab = t; removing = false; failure = ""; open() }
        Item { width: 1; height: 20 }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: removeDialog.page ? "The page will be removed, not deleted. You can still access it from Microsoft Loop."
                : "The " + (removeDialog.tab ? removeDialog.tab.name : "") + " tab will be permanently removed."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            visible: !!removeDialog.failure
            text: removeDialog.failure
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        Item { width: 1; height: 20 }
        Item {
            width: parent.width; height: 31.3
            PrimaryButton {
                anchors.right: parent.right
                label: removeDialog.removing ? "Removing" : "Remove"
                enabled: !removeDialog.removing
                onClicked: { removeDialog.removing = true; backend.channelTabChange("remove", root.teamId, root.chatId, removeDialog.tab.id, "") }
            }
        }
    }
    // About this tab (Teams' About dialog).
    TabAboutDialog { id: aboutDialog }
    // A tab change's outcome: close its dialog, or show Teams' failure text.
    Connections {
        target: backend
        function onChannelTabResultChanged() {
            const r = JSON.parse(backend.channelTabResult || "{}")
            if (r.op === "rename" && renameDialog.tab && r.tab === renameDialog.tab.id) {
                if (r.ok) { if (root.tab === renameDialog.tab.name) root.tab = renameField.text.trim(); renameDialog.close() }
                else { renameDialog.saving = false; renameDialog.failure = "Unable to save " + renameDialog.tab.name + " tab configuration." }
            } else if (r.op === "remove" && removeDialog.tab && r.tab === removeDialog.tab.id) {
                if (r.ok) { if (root.tab === removeDialog.tab.name) root.tab = ""; removeDialog.close() }
                else { removeDialog.removing = false; removeDialog.failure = "We couldn't remove your tab. Please try later." }
            }
        }
    }
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal clicked()
        width: dbText.implicitWidth + 32; height: 32; radius: theme.radius
        opacity: enabled ? 1 : 0.5
        color: primary ? (dbh.hovered ? theme.brandHover : theme.brandFill) : (dbh.hovered ? theme.rowHover : theme.input)
        border.color: primary ? "transparent" : theme.stroke
        Text { id: dbText; anchors.centerIn: parent; text: db.label; color: db.primary ? "white" : theme.text; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        HoverHandler { id: dbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (db.enabled) db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // Test hooks for the tab menu.
    // Drags tab `name` (start), over tab `name` (over), and drop / cancel.
    function tabDragForTest(kind, name) {
        if (kind === "start") { const i = tabNames.indexOf(name); const it = tabRepeater.itemAt(i); tabDragStart(i, Qt.point(it.width / 2, 28)); return i }
        if (kind === "over") { const f = tabDragFrom, a = tabRepeater.itemAt(f), b = tabRepeater.itemAt(tabNames.indexOf(name)); tabDragMove(f, Qt.point(b.x + b.width / 2 - (a.x + tabDragPress.x), 1)); return tabDragOver }
        if (kind === "drop") { tabDragEnd(); return 0 }
        tabDragCancel(); return 0
    }
    function tabMenuForTest(name) { const t = root.channelTabs.find(x => x.name === name); return t ? t.menu.map(e => e.enabled ? e.key : e.key + "(off)") : [] }
    function tabMenuShowForTest(name) { const i = root.tabNames.indexOf(name); const t = root.channelTabs[i]; if (t) tabMenu.show(t, t.menu, tabs.children[i], 0, 56) }
    function tabMenuCloseForTest() { tabMenu.close() }
    function tabActionForTest(name, key) { const t = root.channelTabs.find(x => x.name === name); if (t) root.tabAction(key, t); return t ? JSON.stringify({ website: t.website_url || "" }) : "" }
    function tabAboutForTest(name) { const t = root.channelTabs.find(x => x.name === name); if (t) aboutDialog.start(t); return !!t }
    function tabAboutCloseForTest() { aboutDialog.close() }
    function tabAboutStateForTest() { return JSON.stringify({ visible: aboutDialog.visible, opened: aboutDialog.opened, w: aboutDialog.width, h: aboutDialog.height, json: (backend.appAboutJson || "").slice(0, 120) }) }
    function tabDialogCloseForTest() { renameDialog.close(); removeDialog.close() }
    function tabDialogForTest(kind, name) { const t = root.channelTabs.find(x => x.name === name); if (!t) return false; if (kind === "rename") renameDialog.start(t); else removeDialog.start(t); return true }
    function tabChangeForTest(op, name, arg) { const t = root.channelTabs.find(x => x.name === name); if (t) backend.channelTabChange(op, root.teamId, root.chatId, t.id, arg || ""); return !!t }

    // Participants (Teams' roster flyout, measured on winpc): "People (n)",
    // you first with "You" under your name, each 48 tall with a 32 px
    // picture and presence; then a divider and Add people.
    Item {
        id: participants
        visible: false
        z: 50
        anchors { top: header.bottom; right: parent.right; topMargin: 4; rightMargin: 16 }
        width: 251.3
        height: Math.min(root.height - header.height - 16, (canLeave ? leaveRow.y + leaveRow.height : canAdd ? addRow.y + addRow.height : rows.y + rows.height) + 16.7)
        // Leave shows once there are more than two people (Teams).
        readonly property bool canLeave: canAdd && members.length > 2
        // Teams offers Add people in group chats.
        readonly property bool canAdd: root.isGroup && !root.isChannel
        FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
        // The chat's roster (thread members), you first; channels fall back
        // to the people seen in the posts.
        readonly property var members: {
            const roster = backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []
            if (roster.length > 0) {
                const me = roster.filter(m => m.me).map(m => ({ name: m.name || root.myName, mri: m.mri, me: true }))
                return me.concat(roster.filter(m => !m.me).map(m => ({ name: m.name, mri: m.mri, mail: m.mail, presence: m.presence || "" })))
            }
            const seen = {}, out = []
            if (root.myName) { out.push({ name: root.myName, mri: "me", me: true }); seen.me = true }
            for (const m of root.messages) {
                if (m.mine || !m.sender_mri || !m.sender || seen[m.sender_mri]) continue
                seen[m.sender_mri] = true
                out.push({ name: m.sender, mri: m.sender_mri })
            }
            return out
        }
        Text {
            x: 15.7; y: 17.7; height: 16; verticalAlignment: Text.AlignVCenter
            text: root.isChannel ? "People in this channel" : "People (" + participants.members.length + ")"
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary
        }
        Column {
            id: rows
            x: 6.7; y: 37.7
            Repeater {
                model: participants.members
                Rectangle {
                    id: prow
                    required property var modelData
                    width: 242; height: 48; radius: 4
                    color: prowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    Avatar {
                        x: 12; y: 7; size: 32
                        name: prow.modelData.name
                        photoId: prow.modelData.mri
                        opensProfile: !prow.modelData.me
                        presence: prow.modelData.me ? root.myPresence : prow.modelData.presence || (prow.modelData.mri === root.chatPhotoId ? root.chatPresence : "")
                    }
                    Text {
                        x: 54; y: prow.modelData.me ? 5 : 13; height: 20; verticalAlignment: Text.AlignVCenter
                        width: 176; elide: Text.ElideRight
                        text: prow.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Text {
                        visible: !!prow.modelData.me
                        x: 54; y: 25; height: 16; verticalAlignment: Text.AlignVCenter
                        text: "You"
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    HoverHandler { id: prowHover }
                    // Remove (chat-header-remove-user-button): an X on hover,
                    // for others in a group chat.
                    Rectangle {
                        id: removeBtn
                        visible: participants.canAdd && !prow.modelData.me && (prowHover.hovered || removeHover.hovered)
                        x: 198.2; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: 4
                        color: "transparent"
                        FluentIcon { anchors.centerIn: parent; name: removeHover.hovered ? "dismiss-20-filled" : "dismiss-20"; size: 20; color: removeHover.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { participants.visible = false; memberRemoveDialog.start(prow.modelData) } }
                        ToolTip.visible: removeHover.hovered
                        ToolTip.text: "Remove"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove " + prow.modelData.name
                    }
                    ToolTip.visible: prowHover.hovered && !removeHover.hovered && !prow.modelData.me
                    ToolTip.text: prow.modelData.name
                    ToolTip.delay: 600
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: prow.modelData.name + (prow.modelData.me ? ", You" : "")
                }
            }
        }
        Rectangle {
            visible: participants.canAdd
            x: 16.7; y: rows.y + rows.height + 7; width: 218; height: 0.67
            color: theme.pick("#E0E0E0", "#3D3D3D")
        }
        // Add people (chat-add-members): person-add at 24.3, the label at 60.3.
        Rectangle {
            id: addRow
            visible: participants.canAdd
            x: 2.7; y: rows.y + rows.height + 12.6
            width: 246; height: 31.3; radius: 4
            color: addHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
            FluentIcon { x: 21.6; anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 20; color: theme.textStrong }
            Text { x: 57.6; anchors.verticalCenter: parent.verticalCenter; text: "Add people"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { participants.visible = false; root.openAddPeople() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Add people"
        }
    }
    // Leave (leave-chat-btn): person-arrow-left at 24.3, 32 tall.
    Rectangle {
        id: leaveRow
        parent: participants
        visible: participants.canLeave
        x: 2.7; y: addRow.y + addRow.height
        width: 246; height: 32; radius: 4
        color: leaveHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
        FluentIcon { x: 21.6; anchors.verticalCenter: parent.verticalCenter; name: "person-arrow-left-20"; size: 20; color: theme.textStrong }
        Text { x: 57.6; anchors.verticalCenter: parent.verticalCenter; text: "Leave"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { participants.visible = false; memberRemoveDialog.startLeave(participants.members.find(m => m.me)) } }
        Accessible.role: Accessible.Button
        Accessible.name: "Leave"
    }
    function openAddPeople() {
        addPeople.members = participants.members.map(m => m.mri)
        addPeople.start()
    }
    AddPeopleDialog {
        id: addPeople
        onAccepted: (people, days) => backend.addChatMembers(JSON.stringify(people.map(p => p.mri)), days)
    }
    function addPeopleForTest() { return addPeople }
    // Teams' remove-user-dialog: 600 wide, radius 8; the title 20/28
    // semibold at 24.7, the note at 59.3, Cancel and Remove at 88.7.
    Popup {
        id: memberRemoveDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 144.7; padding: 0
        anchors.centerIn: Overlay.overlay
        closePolicy: Popup.CloseOnEscape
        property var member: null
        // Leaving (yourself): Teams' "Leave the conversation?".
        property bool leaving: false
        function start(m) { member = m; leaving = false; open() }
        function startLeave(m) { member = m; leaving = true; open() }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: "#66000000" }
        Text {
            x: 24.7; y: 24.7; width: 550; height: 28; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            text: memberRemoveDialog.leaving ? "Leave the conversation?" : "Remove " + (memberRemoveDialog.member ? memberRemoveDialog.member.name : "") + " from the conversation?"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: 24.7; y: 59.3; height: 20; verticalAlignment: Text.AlignVCenter
            text: memberRemoveDialog.leaving ? "You'll still have access to the chat history." : "They'll still have access to the chat history."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
        }
        Row {
            x: 375.3; y: 88.7; spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: rCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: rCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: memberRemoveDialog.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: rOkHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: memberRemoveDialog.leaving ? "Leave" : "Remove"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: rOkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: memberRemoveDialog.confirm() }
                Accessible.role: Accessible.Button
                Accessible.name: memberRemoveDialog.leaving ? "Leave" : "Remove"
            }
        }
        function confirm() {
            const m = member
            close()
            if (m) backend.removeChatMember(m.mri)
        }
    }
    function memberRemoveDialogForTest() { return memberRemoveDialog }

    function wrapSelection(tag) { compose.wrapSelection(tag) }
    // Files picked to send with the next message (local paths).
    property var pendingFiles: []
    // Files picked from OneDrive or SharePoint ({key, name, kind, loading,
    // file, thumbnail}); each is read for its card first.
    property var pendingCloud: []
    readonly property bool hasFiles: pendingFiles.length > 0 || pendingCloud.some(c => !!c.file)
    /// What the backend sends: local paths, then "cloud:" and each read
    /// cloud file.
    function fileLines() {
        return pendingFiles.concat(pendingCloud.filter(c => !!c.file).map(c => "cloud:" + JSON.stringify(c.file))).join("\n")
    }
    function clearFiles() { pendingFiles = []; pendingCloud = [] }
    readonly property string attachTag: "conv-attach-" + Math.floor(Math.random() * 1e9) + ":"
    /// Files from the Attach popover or the cloud file picker into the
    /// compose box (Teams reads each for its card).
    function attachCloud(list) {
        for (const f of list) {
            const key = f.web_url
            if (!key || pendingCloud.some(c => c.key === key)) continue
            pendingCloud = pendingCloud.concat([{ key: key, name: f.name, kind: f.kind || "", loading: true }])
            backend.driveAction(attachTag + encodeURIComponent(key) + ":attach_prepare",
                JSON.stringify({ name: f.name, web_url: f.web_url, drive_id: f.drive_id || "", id: f.id || "", kind: f.kind || "" }), "{}")
        }
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.attachTag) || !op.endsWith(":attach_prepare")) return
            const key = decodeURIComponent(op.slice(root.attachTag.length, op.length - ":attach_prepare".length))
            if (error) {
                root.pendingCloud = root.pendingCloud.filter(c => c.key !== key)
                compose.showBanner("Couldn't attach the file. Please try again.", false, 3000)
                return
            }
            const v = JSON.parse(result)
            root.pendingCloud = root.pendingCloud.map(c => c.key === key ? Object.assign({}, c, { loading: false, file: v.file, thumbnail: v.thumbnail }) : c)
        }
    }
    /// Teams' Attach popover over the Attach button.
    function openAttach(anchor) {
        attachMenu.anchorItem = anchor || compose
        attachMenu.channel = root.isChannel
        attachMenu.chatId = root.threadChannel || root.chatId
        attachMenu.context = root.messages.filter(m => m.kind !== "call" && !m.deleted).slice(-3).reverse()
            .map(m => ({ id: m.id, text: m.text || "", sender: String(m.sender_mri || "").replace(/^8:orgid:/, ""), time: m.time }))
        attachMenu.open()
    }
    AttachMenu {
        id: attachMenu
        onAttachCloud: { cloudPicker.entry = "home"; cloudPicker.open() }
        onBrowseChannels: { cloudPicker.entry = { team: root.teamName, team_id: root.teamId, channel_id: root.threadChannel || root.chatId }; cloudPicker.open() }
        onUpload: filePicker.open()
        onPicked: f => root.attachCloud([f])
    }
    CloudPicker {
        id: cloudPicker
        onAttached: files => root.attachCloud(files)
    }
    // Bot cards' actions (api::bot_invoke, docs/spec/messages-and-composer.md
    // "Bot card actions"): an invoke Action.Submit or an Action.Execute goes
    // to the message's bot; a card's refresh runs once a session for the
    // people it names. What comes back replaces the card (shown "Updated")
    // or fills Teams' response bar under it.
    property var cardOverrides: ({})
    property var cardFooters: ({})
    property var cardRefreshed: ({})
    readonly property string cardInvokeTag: "conv-invoke-" + Math.floor(Math.random() * 1e9) + ":"
    function senderLabel(m) { return m.on_behalf_of ? m.on_behalf_of + " via " + (m.sender || "") : (m.sender || "") }
    function cardUpdated(id) { for (const k in root.cardOverrides) if (k.indexOf(id + ":") === 0) return true; return false }
    function setCardFooter(key, state) { const f = Object.assign({}, root.cardFooters); if (state) f[key] = state; else delete f[key]; root.cardFooters = f }
    function cardTarget(m) {
        return { thread_id: root.chatId, server_message_id: m.id, client_message_id: m.client_message_id || "",
                 bot_mri: m.sender_mri || "", app_id: "", message_type: "RichText/Media_Card" }
    }
    function cardAction(m, index, a, inputs) {
        const t = String(a.type || "").toLowerCase()
        const key = m.id + ":" + index
        if (t === "action.submit") {
            const ms = a.data && a.data.msteams ? a.data.msteams : null
            const mtype = ms ? String(ms.type || "").toLowerCase() : ""
            if (mtype === "imback") { root.send(String(ms.value || a.title || "")); return }
            if (mtype !== "invoke") { console.warn("card: Action.Submit without an invoke isn't sent", JSON.stringify(a.data || {})); return }
        } else if (t !== "action.execute") return
        if (!String(m.sender_mri || "").startsWith("28:")) return
        root.setCardFooter(key, { busy: true, text: "" })
        backend.cardInvoke(root.cardInvokeTag + key, JSON.stringify(root.cardTarget(m)), JSON.stringify(a), JSON.stringify(inputs || {}), false)
    }
    function maybeRefreshCard(m, index, content) {
        const r = content && content.refresh
        if (!r || !r.action || !String(m.sender_mri || "").startsWith("28:")) return
        const key = m.id + ":" + index
        if (root.cardRefreshed[key]) return
        // Teams refreshes for the people the card names (all, if it names none).
        const ids = r.userIds || []
        if (ids.length && ids.indexOf(backend.userMri) < 0) return
        const done = Object.assign({}, root.cardRefreshed); done[key] = true; root.cardRefreshed = done
        backend.cardInvoke(root.cardInvokeTag + "refresh:" + key, JSON.stringify(root.cardTarget(m)), JSON.stringify(r.action), "{}", true)
    }
    Connections {
        target: backend
        function onCardInvokeDone(op, result, error) {
            if (!op.startsWith(root.cardInvokeTag)) return
            let key = op.slice(root.cardInvokeTag.length)
            const refresh = key.startsWith("refresh:")
            if (refresh) key = key.slice("refresh:".length)
            const v = result ? JSON.parse(result) : null
            if (v && v.kind === "card") {
                const o = Object.assign({}, root.cardOverrides); o[key] = v.card; root.cardOverrides = o
                if (!refresh) root.setCardFooter(key, null)
                return
            }
            if (refresh) return
            if (error) root.setCardFooter(key, { error: true, text: "Something went wrong. Please try again." })
            else if (v && v.kind === "message") root.setCardFooter(key, { text: v.message })
            else if (v && v.kind === "error") root.setCardFooter(key, { error: true, text: v.message })
            else root.setCardFooter(key, { text: "Your response was sent to the app" })
        }
    }
    /// Run a card's action by its title, with the given inputs (tests).
    function cardActionForTest(id, index, title, inputs) {
        const m = root.messages.find(x => x.id === id)
        if (!m || !m.cards || !m.cards[index]) return "no card"
        const content = root.cardOverrides[id + ":" + index] || m.cards[index].content
        const a = (content.actions || []).find(x => x.title === title)
        if (!a) return "no action " + title
        root.cardAction(m, index, a, inputs)
        return "sent"
    }
    function cardStateForTest(id) {
        const out = {}
        for (const k in root.cardOverrides) if (k.indexOf(id + ":") === 0) out[k] = "override"
        for (const k in root.cardFooters) if (k.indexOf(id + ":") === 0) out[k + ":footer"] = root.cardFooters[k]
        return out
    }

    // A message's file card (FileCard): Teams' ··· menu (Open in Browser,
    // Download, Share, Copy link, Favorite / Unfavorite), Share this file,
    // Copy link's "Link copied" and the favorites toasts. The file is looked
    // up as a Files item when its menu opens (card_item: its SharePoint
    // address and whether it is a favorite).
    signal toastRequested(var data)
    /// Open a message's file in Teams' viewer (Main's FileViewer).
    signal openFileRequested(var file)
    property int thumbsRev: 0
    property var cardItems: ({})
    property var cardMenuFile: null
    property var cardPending: null
    readonly property string cardTag: "conv-card-" + Math.floor(Math.random() * 1e9) + ":"
    Connections {
        target: backend
        function onThumbnailReady(url) { root.thumbsRev++ }
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.cardTag)) return
            const kind = op.slice(root.cardTag.length)
            const v = result ? JSON.parse(result) : null
            if (kind === "card_item") {
                if (error || !v) {
                    if (root.cardPending) root.toastRequested({ text: "Something went wrong. Try again.", intent: "error" })
                    root.cardPending = null
                    return
                }
                const m = Object.assign({}, root.cardItems); m[v.url] = { item: v.item, favorite: v.favorite }; root.cardItems = m
                if (cardMenu.opened && root.cardMenuFile && root.cardMenuFile.object_url === v.url) cardMenu.items = root.cardMenuItems(root.cardMenuFile)
                const p = root.cardPending
                if (p && p.file.object_url === v.url) { root.cardPending = null; root.fileCardAct(p.file, p.label) }
            } else if (kind === "card_favorite") {
                if (error || !v) { root.toastRequested({ text: "Something went wrong. Try again.", intent: "error" }); return }
                const m = Object.assign({}, root.cardItems)
                if (m[v.url]) { m[v.url] = Object.assign({}, m[v.url], { favorite: v.on }); root.cardItems = m }
                const file = root.cardFileFor(v.url)
                root.toastRequested(v.on ? { text: "Added \"" + v.name + "\" to OneDrive Favorites", intent: "success" }
                    : { text: "Removed from OneDrive Favorites", intent: "success", action: "Undo",
                        onAction: () => { if (file) root.setCardFavorite(file, true) } })
            }
        }
    }
    function cardFileFor(url) {
        for (const m of root.messages) for (const f of (m.files || [])) if (f.object_url === url) return f
        return root.cardMenuFile && root.cardMenuFile.object_url === url ? root.cardMenuFile : null
    }
    function cardMenuItems(file) {
        const known = root.cardItems[file.object_url]
        const fav = !!known && known.favorite
        return [{ label: "Open in Browser", icon: "globe-20" }, { label: "Download", icon: "arrow-download-20" },
                { label: "Share", icon: "share-20" }, { label: "Copy link", icon: "link-20" },
                fav ? { label: "Unfavorite", icon: "star-20-filled" } : { label: "Favorite", icon: "star-20" }]
    }
    function lookUpCard(file) {
        if (file.object_url) backend.driveAction(root.cardTag + "card_item", "{}", JSON.stringify({ url: file.object_url }))
    }
    /// Teams' menu, its top-right under the ··· button.
    /// `gap`: room under the button (the viewer's menu sits 4 below it).
    function openFileCardMenu(file, anchor, gap) {
        root.cardMenuFile = file
        cardMenu.items = root.cardMenuItems(file)
        const p = anchor.mapToItem(root, anchor.width, anchor.height + (gap || 0))
        cardMenu.x = Math.max(0, p.x - cardMenu.implicitWidth)
        cardMenu.y = p.y + cardMenu.implicitHeight > root.height ? Math.max(0, p.y - anchor.height - cardMenu.implicitHeight) : p.y
        cardMenu.open()
        root.lookUpCard(file)
    }
    function setCardFavorite(file, on) {
        const known = root.cardItems[file.object_url]
        const site = file.site_url || (known && known.item ? known.item.sp_site : "")
        backend.driveAction(root.cardTag + "card_favorite", "{}", JSON.stringify({ url: file.object_url, site: site, name: file.name, on: on }))
    }
    function fileCardAct(file, label) {
        if (label === "Open in Browser") { Qt.openUrlExternally(file.share_url || file.object_url); return }
        if (label === "Download") { backend.downloadFile(JSON.stringify(file)); return }
        if (label === "Favorite" || label === "Unfavorite") { root.setCardFavorite(file, label === "Favorite"); return }
        // Share and Copy link need the file's SharePoint address.
        const known = root.cardItems[file.object_url]
        if (!known) { root.cardPending = { file: file, label: label }; root.lookUpCard(file); return }
        const it = known.item
        if (label === "Share") cardShare.openFor({ site: it.sp_site, list: it.sp_list, item: it.sp_item }, file.name, file.file_type, file.object_url)
        else if (label === "Copy link") cardActions.copyLinkNow(it)
    }
    MenuPopup {
        id: cardMenu
        minRowWidth: 172
        onPicked: i => { if (root.cardMenuFile) root.fileCardAct(root.cardMenuFile, items[i].label) }
    }
    ShareFileDialog { id: cardShare }
    FileActions { id: cardActions; anchors.fill: parent; z: -1 }
    property var cardViewsForTest: ({})
    function openFileCardMenuForTest(url) {
        const v = root.cardViewsForTest[url]
        if (v) root.openFileCardMenu(v.file, v.moreButtonForTest())
        return !!v
    }
    function fileCardForTest(url) {
        const v = root.cardViewsForTest[url]
        if (!v) return null
        const p = v.mapToItem(root, 0, 0)
        return { x: p.x, y: p.y, width: v.width, height: v.height, preview: v.hasPreview, location: v.file.location, name: v.file.name }
    }
    function hoverFileCardForTest(url, on) { const v = root.cardViewsForTest[url]; if (v) v.hoverForTest = on }
    function fileCardMenuForTest() { return { open: cardMenu.opened, items: cardMenu.items.map(i => i.label), x: cardMenu.x, y: cardMenu.y, width: cardMenu.width } }
    function fileCardActForTest(file, label) { root.fileCardAct(file, label) }
    function fileCardKnownForTest(url) { return root.cardItems[url] || null }
    function closeFileCardMenuForTest() { cardMenu.close() }
    function copyLinkStateForTest() { return cardActions.copyLinkStateForTest() }
    function closeCopyLinkForTest() { cardActions.closeCopyLinkForTest() }
    function closeCardShareForTest() { cardShare.close() }
    function attachMenuForTest() { return attachMenu }
    function cloudPickerForTest() { return cloudPicker }
    function cloudForTest() { return pendingCloud.map(c => ({ name: c.name, loading: !!c.loading, link: c.file ? c.file.link_description : "", thumb: !!c.thumbnail })) }
    function addFiles(urls) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    // Send what's in the compose box: text, files, or both.
    function sendCompose() {
        if (root.popout) {
            // A chat window sends to its own chat.
            if (root.hasFiles) {
                backend.sendChatWindowFiles(root.chatId, root.fileLines(), root.plainText())
                root.clearFiles()
            } else if (root.plainText().trim().length > 0 || compose.mediaInUse().length > 0) {
                backend.sendChatWindowMessage(root.chatId, compose.formattedText(), JSON.stringify(compose.mediaInUse()), root.quoting ? JSON.stringify(root.quoting) : "")
            }
            compose.clear()
            root.quoting = null
            compose.formatting = false
            return
        }
        if (root.threadRoot) {
            // A thread pane replies in its thread.
            if (root.hasFiles) {
                backend.sendThreadFiles(root.threadChannel, root.threadRoot, root.fileLines(), root.plainText())
                root.clearFiles()
            } else if (root.plainText().trim().length > 0 || compose.mediaInUse().length > 0) {
                backend.sendThreadReply(root.threadChannel, root.threadRoot, compose.formattedText(), JSON.stringify(compose.mediaInUse()), root.quoting ? JSON.stringify(root.quoting) : "", compose.sendTo === "channel")
            }
            // Teams goes back to "thread only" after each reply.
            if (root.threadPane) compose.sendTo = "thread"
            compose.clear()
            root.quoting = null
            compose.formatting = false
            return
        }
        // Teams' tracked action: a message sent in a threads channel's main
        // view (it ends the threads-layout banner).
        if (root.threadsLayout && !root.pane) backend.recordEngagementAction("ThreadedChannelInteraction")
        backend.setReplyQuote(root.quoting ? JSON.stringify(root.quoting) : "")
        backend.setNextImportance(compose.importance)
        // A scheduled message goes to Teams' drafts instead (not with files).
        backend.setNextSchedule(compose.scheduleAt > 0 && !root.hasFiles ? String(Math.round(compose.scheduleAt)) : "")
        compose.scheduleAt = 0
        // A new channel post: Teams' subject, headline and banner colour.
        backend.setNextPost(compose.post && !root.hasFiles
            ? compose.postFields() : root.threadsLayout ? JSON.stringify({ threads: true, subject: compose.formatting ? compose.subject : "" }) : "")
        if (root.hasFiles) {
            backend.sendFiles(root.fileLines(), root.plainText())
            root.clearFiles()
        } else if (compose.mediaInUse().length > 0) {
            // Picked emoticons, GIFs and stickers go in Teams' own form.
            backend.sendRichMedia(input.getFormattedText(0, input.length), JSON.stringify(compose.mediaInUse()))
        } else if (root.plainText().trim().length > 0) {
            // Formatted text goes as Teams HTML; plain text as before.
            // Formatting goes as Teams HTML; plain text as before.
            const html = compose.formattedText()
            if (/<(b|i|u|s|ul|ol|h[123]|hr|blockquote|pre|code|span|a|table)[ >]|margin-left/.test(html)) backend.sendRich(html)
            else root.send(root.plainText())
        }
        compose.clear()
        root.quoting = null
        compose.formatting = false
        compose.importance = ""
        compose.resetPost()
        root.posting = false
    }
    // Teams' pinned-message banner (pinned-message-banner, measured): over
    // the top of the list, 40 tall, NeutralBackground2 with shadow 8 and a
    // NeutralStroke3 bottom line. Pin icon (20) at 20.7, the sender (12),
    // the preview (12 semibold) 15 after it, the date (12 semibold) at the
    // right, then ··· (View in chat, Unpin for everyone). Clicking it goes
    // to the message.
    readonly property var pinnedBanner: backend.pinnedJson ? JSON.parse(backend.pinnedJson) : null
    function pinnedStamp(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        return d.getFullYear() === now.getFullYear() ? Qt.formatDate(d, "M/d") : Qt.formatDate(d, "M/d/yyyy")
    }
    Item {
        id: pinBanner
        visible: !!root.pinnedBanner && list.visible
        z: 6
        x: 0; y: list.y; width: list.width; height: 40
        FluentSurface { anchors.fill: parent; depth: 8; radius: 0; color: theme.quoteFill }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.quoteBorder }
        Item {
            x: 12; y: 4; width: parent.width - 12 - 2 - 32; height: 31.3
            FluentIcon { x: 8.7; y: 5.7; name: "pin-20"; size: 20; color: theme.textStrong }
            Text { id: pinWho; x: 41.7; anchors.verticalCenter: parent.verticalCenter; text: root.pinnedBanner ? root.pinnedBanner.sender : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong }
            Text {
                x: pinWho.x + pinWho.implicitWidth + 15; anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, pinWhen.x - x - 12); elide: Text.ElideRight
                text: root.pinnedBanner ? root.pinnedBanner.text : ""
                font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold; color: theme.textStrong
            }
            Text {
                id: pinWhen
                anchors.right: parent.right; anchors.rightMargin: 8.6; anchors.verticalCenter: parent.verticalCenter
                text: root.pinnedBanner ? root.pinnedStamp(root.pinnedBanner.time) : ""
                font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold; color: theme.textStrong
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.jumpToMessage(root.pinnedBanner.id) }
            Accessible.role: Accessible.Button
            Accessible.name: root.pinnedBanner ? "Pinned message banner. Message from " + root.pinnedBanner.sender + " sent on " + root.pinnedStamp(root.pinnedBanner.time) + ", " + root.pinnedBanner.text : ""
        }
        BarButton {
            id: pinMore
            x: parent.width - 32 - 2; y: 4; height: 31.3
            icon: "more-horizontal-20"; tip: "Pinned options"
            onClicked: { pinMenu.parent = pinMore; pinMenu.x = pinMore.width - pinMenu.implicitWidth; pinMenu.y = pinMore.height; pinMenu.open() }
        }
        MenuPopup {
            id: pinMenu
            margins: 8
            items: [{ key: "view", label: "View in chat", icon: "open-20" }, { key: "unpin", label: "Unpin for everyone", icon: "pin-off-20" }]
            onPicked: i => {
                if (items[i].key === "view") root.jumpToMessage(root.pinnedBanner.id)
                else backend.setMessagePinned(root.pinnedBanner.id, false)
            }
        }
    }
    // The menu for selected message text.
    MenuPopup {
        id: textMenu
        property var target: null
        function popup(anchor, px, py) { parent = anchor; x = px; y = py; open() }
        margins: 8
        items: [{ key: "copy", label: "Copy", keys: "Ctrl+C" }, { key: "all", label: "Select all", keys: "Ctrl+A" }]
        onPicked: i => { if (!target) return; if (items[i].key === "copy") target.copy(); else target.selectAll() }
    }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }

    // Teams' empty chat header (its "lobby-chat-new-chat" kind, measured
    // on winpc 2026-11-11): the chat-pencil illustration (about 120), then
    // the title 16/700 #242424 centred 50 under it, in the middle of the
    // message area while the chat has no messages.
    Column {
        visible: root.emptyTitle !== "" && root.messages.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: header.height + Math.max(16, (compose.y - header.height - height) / 2)
        width: parent.width - 32
        spacing: 50
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 120; height: 120
            source: "../assets/illustrations/chat-pencil-l-standard.svg"
            sourceSize: Qt.size(240, 240)
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.emptyTitle
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
    // The peer's status bar (Teams' compose notification, 29.33 tall over
    // the compose box at its width): #E6E6E6 with a #E0E0E0 edge, radius
    // 4, 16 in; the text 12/17.14 #424242; a 28 x 28 "Close notification"
    // with the 16 px dismiss at the end.
    Rectangle {
        id: peerNoteBar
        visible: root.peerNoteShown
        x: compose.x; width: compose.width; height: 29.33
        y: compose.y - height
        radius: 4
        color: theme.peerNoteFill
        border.color: theme.divider; border.width: 0.67
        Text {
            x: 16.67; width: parent.width - 16.67 - 36; anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.peerNoteText
            font.family: theme.font; font.pixelSize: 12
            color: theme.textStrong
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 28.67; y: 0.67; width: 28; height: 28; radius: 4
            color: closeNoteHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: closeNoteHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    const d = Object.assign({}, root.dismissedPeerNotes)
                    d[root.chatId + "|" + root.peerNoteText] = true
                    root.dismissedPeerNotes = d
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Close notification"
        }
    }
    // The chat's compose (Teams' simplified compose; ComposeBox). It sits
    // 72 in on each side, 6 above the bottom, its hint row included.
    ComposeBox {
        id: compose
        visible: root.chatName.length > 0 && (!root.isChannel || root.posting || root.threadsLayout) && root.tab !== "Attendance" && !root.readOnly
        // New posts at the top: in the list's top card, scrolling with it.
        readonly property bool atTop: post && channelPosts.newestAtTop
        anchors { left: parent.left; right: parent.right }
        // One binding for its place (an anchor would win over y): at the
        // bottom, or in the list's top card.
        y: atTop ? channelPosts.y + channelPosts.composerY : parent.height - height - bottomGap
        readonly property real bottomGap: post ? 27.7 : 6
        // Teams' post composer (a new channel post) lines up with the post
        // cards, 27.7 above the bottom.
        post: root.postsLayout && !root.threadRoot && !root.pane
        readonly property real postGut: (root.width - Math.min(1100, root.width - 2 * (root.width > 480 ? 88 : 16))) / 2
        anchors.leftMargin: post ? postGut : root.pane ? 12 : root.composeGut
        anchors.rightMargin: post ? postGut : root.pane ? 12 : root.composeGut

        onCloseRequested: { compose.resetPost(); compose.clear(); root.posting = false }
        // Under 480 px Teams' compose is compact: its tools on their own row.
        compact: !root.pane && root.width < 480
        sendTo: root.threadPane ? "thread" : ""
        threadSubject: root.threadsLayout
        tierWidth: root.width
        // Teams offers it in chats and channels, not in your own chat or a
        // thread's reply box.
        scheduleAllowed: !root.isSelf && !root.threadRoot && !root.pane
        placeholder: root.composeDisabled ? "" : root.threadRoot ? "Reply in thread" : root.threadsLayout ? "Message in " + root.chatName : "Type a message"
        noteText: root.composeNote
        textOnly: root.composeTextOnly
        noteMuted: root.composeNoteMuted
        enabled: !root.composeDisabled
        quote: root.quoting
        files: root.pendingFiles
        onQuoteDismissed: root.quoting = null
        onFileRemoved: path => root.pendingFiles = root.pendingFiles.filter(p => p !== path)
        onEmojiRequested: a => root.openEmojiFor(compose)
        cloudFiles: root.pendingCloud
        onCloudRemoved: key => root.pendingCloud = root.pendingCloud.filter(c => c.key !== key)
        onAttachRequested: a => root.openAttach(a)
        onSettingsRequested: root.openChatSettings()
        onTyped: root.typing()
        onSubmit: root.sendCompose()
        // Teams: not in channels; Urgent only in chats up to 20 people.
        deliveryOptions: !root.isChannel
        // Teams suggests only the members in group chats and channels.
        mentionDirectory: !root.isGroup && !root.isChannel
        everyoneId: root.isGroup ? root.chatId : ""
        channelMention: root.isChannel ? { id: root.chatId, name: root.chatName } : null
        canAddPeople: root.isGroup && !root.isChannel
        onAddPeopleRequested: root.openAddPeople()
        canAddAgent: root.isGroup || root.isChannel
        onAddAgentRequested: root.openAgentStore(root.chatId, root.isChannel)
        // A team is mentioned by its thread id, its General channel's.
        teamMention: {
            if (!root.isChannel || !root.teamId) return null
            const t = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === root.teamId)
            const general = t ? (t.channels.find(c => c.name === "General") || t.channels[0]) : null
            return general ? { id: general.id, name: root.teamName, groupId: root.teamId } : null
        }
        tagMentions: {
            const all = backend.teamTagsJson ? JSON.parse(backend.teamTagsJson) : {}
            return teamMention ? (all[teamMention.id] || []) : []
        }
        readonly property var roster: backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []
        memberCount: roster.length
        meetingChat: root.isMeetingChat
        mentionables: roster.filter(m => !m.me).map(m => ({ mri: m.mri, name: m.name, mail: m.mail }))
        urgentAllowed: !root.isGroup || (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson).length : 0) <= 20
        onScheduleMeetingRequested: root.scheduleMeeting()
        onCancelled: { root.quoting = null; root.clearFiles(); compose.resetPost(); root.posting = false; if (root.draftChat) backend.setDraft(root.draftChat, "") }
        Connections {
            target: compose.editor
            function onTextChanged() { draftSave.restart() }
        }
    }
    // A channel meeting's Attendance view, over the channel (Teams leaves
    // the header band empty above its toolbar).
    Loader {
        id: channelAttendanceLoader
        anchors.fill: parent
        z: 51
        active: !!root.channelAttendance && root.isChannel && !root.pane
        sourceComponent: Rectangle {
            color: theme.surface
            AttendanceView {
                y: header.height; width: parent.width; height: parent.height - y
                thread: root.chatId; organizer: root.channelAttendance.organizer
                message: root.channelAttendance.message; initialCall: root.channelAttendance.call
            }
            Shortcut { sequence: "Escape"; onActivated: root.channelAttendance = null }
        }
    }
    // Teams' post view (an ended meeting's "See details"): the post's
    // thread over the channel, with Go to channel and Open in new window.
    Loader {
        anchors.fill: parent
        z: 50
        active: root.postViewRoot !== "" && root.isChannel && !root.pane
        sourceComponent: PostThread {
            inPane: true
            channelId: root.chatId; rootId: root.postViewRoot
            teamId: root.teamId; teamName: root.teamName
            channelName: root.chatName; myName: root.myName
            onGoToChannel: root.postViewRoot = ""
            onPopOut: { const id = root.postViewRoot; root.postViewRoot = ""; root.openThreadWindow({ id: id, root_id: id }) }
            onAgentStoreRequested: id => root.openAgentStore(id, true)
            onOpenAttendance: (organizer, message, call) => root.channelAttendance = { organizer: organizer, message: message, call: call }
        }
    }
}
