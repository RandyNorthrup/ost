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
    /// A pop-out that keeps the tabs row (Teams' Chat app window).
    property bool windowTabs: false
    /// The chat menu's Manage apps: the chat's apps in place of its
    /// messages (Teams keeps the Chat tab chosen) until a tab is picked.
    property bool manageApps: false
    signal getMoreApps()
    /// The side pane's title ("Chat"; a tab's conversation says
    /// "Conversation").
    property string paneTitle: qsTr("Chat")
    /// The pane header's measures: the call window's chat (title 16 bold at
    /// 16, close 44 from the end) or a tab's conversation (16/22 semibold
    /// at 20, close 32 x 21.3 at 20 from the end).
    property bool paneTitleSemibold: false
    property real paneTitleX: 16
    property real paneCloseRight: 44
    property int paneTitleSize: 16
    /// The pane header's buttons before Close, left to right, 32 apart
    /// (Teams' meeting chat: Add a chat as a tab, Open in new window, More
    /// meeting chat options): [{key, icon, tip}]; those in
    /// `paneActionsOn` (their menu open) show in brand.
    property var paneActions: []
    property var paneActionsOn: []
    signal paneAction(string key, Item button)
    /// Press a pane header button (test harness).
    function paneActionForTest(key) {
        for (let i = 0; i < paneActRepeater.count; i++) if (paneActions[i].key === key) paneAction(key, paneActRepeater.itemAt(i))
    }
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
    /// A bot message's suggested action picked (Action.Compose: its text
    /// goes to the compose box; in a threads channel, the message's thread).
    signal suggestedAction(var message, var action)
    /// A picture clicked (Teams' viewer).
    signal openImageViewer(var images, int index, var message)
    /// The harness: the posts list's picture cut ({id, limit, full, ranges}).
    function postImagesForTest() { return channelPosts.imagesForTest() }
    /// An agent's meeting (createMeeting): "schedule" or "edit".
    signal agentMeeting(string op, var message, var entry, var command)
    function scheduleAgentMeeting(m, e, c) { root.agentMeeting("schedule", m, e, c) }
    function editAgentMeeting(m, c) { root.agentMeeting("edit", m, null, c) }
    /// Like / dislike picked on bot messages, by message id.
    property var botFeedback: ({})
    function composeReady() { return compose.visible }
    /// The harness: the newest bot message's suggested actions and
    /// feedback, then (pick) its first action as a click would.
    function suggestionsForTest(pick) {
        const m = (root.messages || []).filter(x => (x.suggested || []).length > 0 || x.feedback_loop).pop()
        if (!m) return { found: false }
        const pickable = (m.suggested || []).filter(a => a.kind !== "odsl")
        if (pick && pickable.length) root.suggestedAction(m, pickable[0])
        return { found: true, id: m.id, sender: m.sender, app: m.sender_app || "", ai: !!m.ai_agent, actions: (m.suggested || []).map(a => a.title), feedback: !!m.feedback_loop }
    }
    // Teams' "see more" (SeeMoreRules): in chats and threads only an
    // agent's long message is cut; in a posts channel's list every long
    // post and reply (ChannelPosts).
    readonly property SeeMoreRules seeMore: SeeMoreRules {}
    property var seeMoreOpen: ({})
    /// The harness: the message whose reasoning shows opened.
    property string reasoningOpenForTest: ""
    /// The cut content's full heights seen (the harness's report).
    property var seeMoreFull: ({})
    readonly property string threadKind: isChannel ? "channel" : isMeetingChat ? "meeting" : "chat"
    function seeMoreForTest() {
        if (postsLayout) return { layout: "posts", items: channelPosts.seeMoreStateForTest() }
        return { layout: threadsLayout ? "threads" : "chat", items: (root.messages || []).filter(m => !m.event && m.kind === "message").map(m => {
            const limit = seeMore.chatLimit(m, threadKind, !m.root_id || m.root_id === m.id), full = root.seeMoreFull[m.id] || 0
            return { id: m.id, sender: m.sender, text: String(m.text || "").slice(0, 40), limit: limit, full: full, cut: limit > 0 && full > limit, open: root.seeMoreOpen[m.id] === true }
        }) }
    }
    /// See more / See less: Teams keeps the button where it is on the
    /// screen (its scroll compensation), so the list moves by the change.
    function toggleSeeMore(id, button) {
        const before = button.mapToItem(list.contentItem, 0, 0).y
        const o = Object.assign({}, root.seeMoreOpen)
        if (o[id]) delete o[id]; else o[id] = true
        root.seeMoreOpen = o
        list.forceLayout()
        const after = button.mapToItem(list.contentItem, 0, 0).y
        list.contentY = list.contentY + after - before
        list.returnToBounds()
    }
    function seeMoreShowForTest(id) { if (postsLayout) channelPosts.seeMoreShowByIdForTest(id); else jumpToMessage(id) }
    function seeMoreToggleForTest(id) {
        if (postsLayout) return channelPosts.seeMoreToggleByIdForTest(id)
        const o = Object.assign({}, root.seeMoreOpen)
        if (o[id]) delete o[id]; else o[id] = true
        root.seeMoreOpen = o
        Qt.callLater(() => jumpToMessage(id))
        return true
    }
    function composeTextForTest() { return compose.visible ? compose.exportForTest() : "" }
    // In a posts channel Teams opens the post's reply with the mention.
    function applyPostSuggestion(m, action) { channelPosts.applySuggestion(m.root_id || m.id, action) }
    function postReplyForTest() { return channelPosts.replyStateForTest }
    function postAskForTest(text) { channelPosts.askForTest(text) }
    function clearPostReplyForTest() { channelPosts.clearReplies() }
    function applySuggestion(action) {
        compose.focusEditor()
        if (action.quote) root.replyWithQuote(action.quote)
        for (const m of (action.mentions || [])) compose.insertMentionOf({ mri: m.mri, name: m.name, whole: true, appId: m.appId || "" })
        if (action.text) compose.insertText(String(action.text).replace(/&/g, "&amp;").replace(/</g, "&lt;"))
    }
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
            // A Channel Agent's own add: Teams shows no row in a threads
            // channel (its posts layout says "… has been added to the
            // channel.").
            if (m.event && m.event.kind === "AgentAdded") continue
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
    /// (By default the conversation's own tabs: "I added a tab" posts.)
    property var linkedTabs: channelTabs
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
        // Teams' banner messages for one member (their =1 forms).
        if (n.pinned && n.text) return qsTr("3 or more members are out of office or have a status message.", "messaging:k5uuqna1t_mf", 1).arg(chatName).arg(n.text)
        if (n.ooo) return qsTr("3 or more chat members are out of office and may not respond", "messaging:k6ffnk3uq_mf", 1).arg(chatName)
        return ""
    }
    readonly property bool peerNoteShown: peerNoteText !== "" && compose.visible && !dismissedPeerNotes[chatId + "|" + peerNoteText]
    property bool composeNoteMuted: false
    property bool composeDisabled: false
    /// What the disabled box says (Teams, a chat you left: "You can't send
    /// messages because you are not a member of the chat.").
    property string composeDisabledText: ""
    /// Only Format and Send in the compose (Teams' lobby chat).
    property bool composeTextOnly: false
    /// No compose at all (people waiting read the lobby chat only).
    property bool readOnly: false
    /// No pictures beside others' messages.
    property bool noAvatars: false
    /// No header (the host draws its own).
    property bool hideHeader: false
    /// The compose's gutter in a pane (Followed threads' thread: 32).
    property real paneComposeGut: 12
    /// A thread pane's "{N} replies" divider under the first message
    /// (Followed threads' thread has none).
    property bool threadRepliesDivider: true
    /// The thread compose's "Send to" over a one-row compose.
    property bool composeSendToInline: false
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
    // Teams' "React to the last message" (Ctrl+Alt+R; 74041 ca): the
    // newest message is focused and its hover bar shown with the first
    // quick reaction focused. Returns the message's id ("" for none).
    function reactToLatest() {
        if (!list.visible || !list.model || !list.model.findIndex) return ""
        const i = list.model.findIndex(m => m.kind !== "call" && m.kind !== "event" && !m.deleted && !m.scheduled_at)
        if (i < 0) return ""
        list.positionViewAtIndex(i, ListView.Contain)
        const id = list.model[i].id
        forceBarId = id
        Qt.callLater(() => { const it = list.itemAtIndex(i); if (it && it.focusReactions) it.focusReactions() })
        return id
    }
    function toggleDetails() { participants.visible = !participants.visible }
    // A channel's tabs, as Teams lists them: Posts, Shared (its Files
    // tab), then the channel's own tabs in order (Page, Notes, apps).
    // A chat's own tabs (its `tab::` thread properties, after Teams' built-in
    // ones) come the same way, keyed by the chat.
    readonly property var channelTabs: {
        if (!backend.channelTabsJson) return []
        const r = JSON.parse(backend.channelTabsJson)
        if (r.channel !== chatId || !r.tabs) return []
        // Only a chat's own tabs in a chat, a channel's in a channel.
        if ((r.kind === "channel") !== isChannel) return []
        if (!isChannel) return r.tabs
        // In the channel's own order (Graph's sortOrderIndex); a dropped
        // tab shows in its new place until the list reloads.
        // Teams hides a Page tab without a page that someone else made.
        const tabs = r.tabs.filter(t => t.app !== "Files" && t.name !== "Files"
            && !(t.kind === "ChannelPage" && !t.content_url && t.creator && t.creator !== backend.userMri))
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
        const name = tabLabel(i)
        tabAnnounce(i === 0 || movable.indexOf(i) === 0 ? qsTr("Grabbed %1. First draggable tab.").arg(name)
            : i === tabNames.length - 1 ? qsTr("Grabbed %1. Last draggable tab.").arg(name) : qsTr("Grabbed %1").arg(name))
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
        if (over === 0) tabAnnounce(qsTr("Moved to beginning of draggable tabs"))
        else if (over === n - 1) tabAnnounce(qsTr("Moved to end of draggable tabs"))
        else {
            const rest = tabNames.map((x, k) => tabLabel(k)).filter((x, k) => k !== over), right = i < over
            tabAnnounce(qsTr("Moved after %1 and before %2").arg(right ? rest[i] : rest[over - 1]).arg(right ? rest[i + 1] : rest[over]))
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
        tabAnnounce(qsTr("Tab dropped"))
    }
    function tabDragCancel() {
        tabDragCancelled = true
        tabDragAnimate = false
        tabDragFrom = -1; tabDragOver = -1
        tabAnnounce(qsTr("Cancelled", "framework:k6wkmzkga"))
    }
    Shortcut { sequence: "Escape"; enabled: root.tabDragFrom >= 0; onActivated: root.tabDragCancel() }
    // The tabs' names are keys (`tab` holds one, and tests and the tab
    // checks compare them); OST's own tabs show in the app language, a
    // channel's or chat's own tabs by their name.
    readonly property int builtInTabCount: isChannel ? (channelTabs.length ? (threadsLayout ? 1 : 0) : 2) : tabNames.length - channelTabs.length
    function tabLabel(i) {
        const n = tabNames[i] || ""
        if (i < 0 || i >= builtInTabCount) return n
        return ({ Conversation: qsTr("Conversation"), Posts: qsTr("Posts"), Shared: qsTr("Shared"), Chat: qsTr("Chat"), Notes: qsTr("Notes"),
                  Recap: qsTr("Recap"), Storyline: qsTr("Storyline"), Attendance: qsTr("Attendance"), "Breakout Rooms": qsTr("Breakout Rooms"),
                  "Q&A": qsTr("Q&A"), "Meeting Whiteboard": qsTr("Meeting Whiteboard") })[n] || n
    }
    function tabLabelOf(name) { const i = tabNames.indexOf(name); return i >= 0 ? tabLabel(i) : name }
    readonly property var tabNames: isChannel ? (channelTabs.length ? channelTabs.map((t, i) => i === 0 && threadsLayout ? "Conversation" : t.name) : [threadsLayout ? "Conversation" : "Posts", "Shared"])
        // Teams (worker Ct): Storyline only in 1:1 chats (and your own
        // notes chat, which has Notes but no Recap; Teams on the web,
        // 2026-11-16). Then the chat's own tabs (its thread properties),
        // in their order.
        : (isSelf ? ["Chat", "Shared", "Notes", "Storyline"] : isMeetingChat ? meetingTabNames : isGroup ? ["Chat", "Shared", "Notes", "Recap"] : ["Chat", "Shared", "Notes", "Recap", "Storyline"])
            .concat(channelTabs.map(t => t.name))
    readonly property bool isMeetingChat: chatId.indexOf("19:meeting_") === 0
    // A meeting chat's tabs (chat-app `Zv`, measured on winpc 2026-11-16):
    // Chat, Shared, Recap, then Attendance (organizers, once the meeting
    // has a report), Breakout Rooms (the organizer, chattabs.breakoutrooms:
    // not for a cancelled meeting, a room's own chat or a town hall), Q&A
    // (a scheduled meeting: Teams' isScheduledMeeting, it has an iCalUid; Meet now has none) and Meeting
    // Whiteboard; whatever doesn't fit goes under "+N".
    readonly property bool hasAttendanceReport: canSeeAttendance && (attendanceTab || messages.some(m => m.kind === "call" && m.call_state === "ended"))
    readonly property bool showBreakoutRooms: !!meeting && !!myOid && meeting.organizer_id === myOid && !meeting.cancelled
        && meeting.scenario !== "breakoutRoom" && meeting.meeting_type !== "Broadcast"
    readonly property bool showQna: !!meeting && !!meeting.ical_uid
    readonly property var meetingTabNames: ["Chat", "Shared", "Recap"]
        .concat(hasAttendanceReport ? ["Attendance"] : [])
        .concat(showBreakoutRooms ? ["Breakout Rooms"] : [])
        .concat(showQna ? ["Q&A"] : [])
        .concat(["Meeting Whiteboard"])
    // Q&A and Meeting Whiteboard are pages Teams embeds (hwc-iframe):
    // the meeting as base64 "0#{thread}#0".
    readonly property string meetingIdB64: isMeetingChat ? Qt.btoa("0#" + chatId + "#0") : ""
    function newGuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16) })
    }
    function qnaUrl() {
        const tid = meeting && meeting.tenant_id ? meeting.tenant_id : backend.tenantId()
        return "https://web.yammer.com/teamsmeeting/teams-meeting/" + Qt.btoa(JSON.stringify({ _type: "TeamsMeeting", id: meetingIdB64 }))
            + "?client=teams&qnaAppType=native&meetingTenantId=" + encodeURIComponent(tid || "")
            + "&entryPoint=chatTab&appSessionId=" + newGuid()
    }
    function whiteboardUrl() {
        const tid = meeting && meeting.tenant_id ? meeting.tenant_id : backend.tenantId()
        return "https://app.whiteboard.microsoft.com/meeting?embed=1&meetingTitle=" + encodeURIComponent(chatName).replace(/%20/g, "+")
            + "&tabStartTime=" + Date.now() + "&correlationId=" + newGuid() + "&culture=en-us&enableReactApp=1"
            + "&isInitiator=" + (meeting && meeting.organizer_id === myOid ? 1 : 0) + "&isEduUser=0&meetingId=" + encodeURIComponent(meetingIdB64)
            + "&teamsEnvV2=prod&client=TeamsModern&userRole=Member&isEU=false&userId=" + encodeURIComponent(myOid)
            + "&userTenantId=" + encodeURIComponent(backend.tenantId() || tid || "") + "&isNAAEnabled=true"
    }
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
    function tabDropdownForTest() { tabDropdownMenu.open(); return tabDropdownMenu }
    function tabDropdownShownForTest() { return tabDropdown.visible }
    function funPickerForTest() { return msgHost.emojiPicker }
    function customEmojiAddForTest() { return msgHost.customEmojiAdd }
    function composeMediaForTest() { return compose.mediaInUse() }
    function closeChatMenuForTest() { chatMenu.close() }
    function toggleFind() { root.finding = !root.finding; if (root.finding) root.tab = "" }
    readonly property bool headerNarrow: width < 640
    /// Under 640 the title is 14 px and the tabs fold into a dropdown under
    /// it (Teams' isDropdownAtSmallViewports): chats, and channels in the
    /// main view ("Posts ⌄", a Threads channel's "Conversation ⌄"; measured
    /// on Teams web 2026-11-16 at a 612 px header).
    readonly property bool narrowTitle: headerNarrow && (!isChannel || (!pane && !popout))
    /// Where the narrow title (and its dropdown) must end.
    readonly property real narrowTitleEnd: isChannel ? (channelMeet.visible ? channelMeet.x - 4 : header.width - 160) : header.toolbarLeft
    readonly property bool rosterInMenu: width < 720 && isGroup && !isChannel && !isSelf
    // A Threads-layout channel's Open threads button sits before Find; under
    // 640 its channel details move to the ··· menu (Teams, measured).
    readonly property int contextInline: pane ? 2 : threadsLayout ? (width >= 640 ? 2 : 1) : isChannel ? 2 : width >= 640 ? 2 : width >= 480 ? 1 : 0
    readonly property int threadsButton: threadsLayout && !pane && tab === "" ? 1 : 0
    // Open Copilot (chat-copilot-button, TASK-0260; measured on winpc
    // 2026-11-23): the first of a chat's context buttons, before Find, for
    // Teams' bizChat experience (a Microsoft 365 Copilot licence and the
    // chat's or meeting chat's flag; never for a channel's own header, nor
    // in a thread pane). Alt+C toggles it; the pane (CopilotPane, the
    // window's) shows `copilotRequest`, and it closes when another chat
    // opens or Find or the details pane take its place.
    readonly property var copilotState: { try { return JSON.parse(backend.composeCopilotJson || "{}") } catch (e) { return {} } }
    readonly property int copilotButton: !pane && !isChannel && !readOnly && chatId !== "" && (isMeetingChat ? !!copilotState.meetingChat : !!copilotState.chat) ? 1 : 0
    property bool copilotOpen: false
    onCopilotButtonChanged: if (!copilotButton) { copilotOpen = false; copilotHistoryOpen = false }
    // More chat options ▸ View Copilot history (Teams' chat-app IC,
    // viewSummaryHistory: shown where the chat's Copilot is, as its first
    // item): Teams' history-only Copilot (personalCopilot, isHistoryOnly)
    // in the Copilot pane's place. Copilot, Find and the details pane each
    // take its place.
    property bool copilotHistoryOpen: false
    onCopilotOpenChanged: if (copilotOpen) copilotHistoryOpen = false
    onCopilotHistoryOpenChanged: if (copilotHistoryOpen) { copilotOpen = false; finding = false; participants.visible = false }
    function toggleCopilot() {
        if (!copilotButton) return
        copilotOpen = !copilotOpen
        if (copilotOpen) { finding = false; participants.visible = false; copilotUnread = unreadTime() }
        console.info("COPILOT chat pane", copilotOpen, isMeetingChat ? "meeting" : "chat")
    }
    onFindingChanged: if (finding) { copilotOpen = false; copilotHistoryOpen = false }
    // The chat's unread time when Copilot opened (Teams'
    // unreadMessageTime, only while the chat had unread messages): the
    // message before the first unread one.
    property real copilotUnread: 0
    function unreadTime() {
        const ms = root.messages || []
        const i = ms.findIndex(m => m.first_unread === true)
        if (i < 0) return 0
        const prev = i > 0 ? ms[i - 1] : null
        return prev ? new Date(prev.time).getTime() : new Date(ms[i].time).getTime() - 1
    }
    // A meeting chat's Copilot reads the meeting: its latest recap card's
    // recording and meeting (with the transcript when it has one).
    readonly property var copilotRequest: {
        if (!copilotButton) return null
        if (isMeetingChat) {
            const m = (root.messages || []).filter(m => m.kind === "call" && m.call_state === "ended" && !!m.recap).pop()
            const ref = m ? root.recapRef(m, m.recap) : { thread_id: root.chatId, subject: root.chatTopic || root.chatName, tenant_id: (root.meeting || {}).tenant_id || backend.tenantId(),
                                                          organizer_id: (root.meeting || {}).organizer_id || "", ical_uid: (root.meeting || {}).ical_uid || "" }
            return { kind: "meeting", chat: root.chatId, recap: ref, transcript: !!(m && m.recap.transcript), live: !!root.liveCall }
        }
        return root.copilotUnread > 0 ? { kind: "chat", chat: root.chatId, unread: root.copilotUnread } : { kind: "chat", chat: root.chatId }
    }
    Shortcut { sequence: "Alt+C"; enabled: root.visible && root.copilotButton > 0 && root.chatName.length > 0; onActivated: root.toggleCopilot() }
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
    readonly property real contextLeft: width - 43 - 32 * (contextInline + threadsButton + copilotButton)
    // A meeting chat's Meeting details (inline from 640 wide, else in ···);
    // not while the tabs are hidden (a pop-out without its tab row: Teams'
    // chat header gives it only with enableChatHeaderMeetingDetailsButton
    // or areTabsHidden false).
    readonly property bool meetingDetailsShown: isMeetingChat && !!meeting && !!meeting.ical_uid && !meeting.cancelled && (!popout || windowTabs)
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
        out.push({ label: qsTr("New section"), icon: "folder-add-20", newSection: true })
        return out
    }
    SectionDialog { id: headerSectionDialog; existing: root.folderList.map(f => f.title) }
    /// Teams' Meeting details (calendar.meetingDetails) for this chat's meeting.
    signal openMeetingDetails(string joinUrl, string icalUid, string start)
    /// A channel meeting's calendar card: the meeting's own page.
    signal openMeetingPage(string joinUrl, string start)
    // The meeting chat's meeting (join link, iCalUid, cancelled): the main
    // window's chat's from the backend, a pop-out's its own (looked up for
    // its chat, as the main window's is for the chat shown there).
    readonly property var meeting: !isMeetingChat ? null
        : popout ? windowMeeting
        : backend.chatMeetingJson ? JSON.parse(backend.chatMeetingJson) : null
    property var windowMeeting: null
    // Its members (with presence) the same way: the roster count, @mentions,
    // urgent messages.
    readonly property var chatMembers: popout ? windowMembers
        : backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []
    property var windowMembers: []
    function loadWindowChat() {
        windowMeeting = null; windowMembers = []
        if (!popout) return
        if (isMeetingChat) backend.eventsRequest("chatMeeting", "convmeeting:" + chatId, JSON.stringify({ thread: chatId }))
        if (chatId.indexOf("19:") === 0 && !isChannel) backend.eventsRequest("chatMembers", "convmembers:" + chatId, JSON.stringify({ thread: chatId }))
    }
    Connections {
        target: root.popout ? backend : null
        function onEventsReply(id, json) {
            const meeting = id === "convmeeting:" + root.chatId
            if (!meeting && id !== "convmembers:" + root.chatId) return
            let v = null
            try { v = JSON.parse(json) } catch (e) {}
            if (v && v.error) { console.warn(meeting ? "meeting unavailable:" : "chat members unavailable:", v.error); return }
            if (meeting) root.windowMeeting = v
            else root.windowMembers = Array.isArray(v) ? v : []
        }
    }
    // Teams' Attendance card shows to the meeting's organizer and
    // co-organizers (not for town halls), under each meeting's end.
    readonly property string myOid: backend.userOid
    readonly property bool canSeeAttendance: !!meeting && meeting.meeting_type !== "Broadcast" && !!myOid
        && (meeting.organizer_id === myOid || (meeting.co_organizer_ids || []).indexOf(myOid) >= 0)
    property bool attendanceTab: false
    property string attendanceCall: ""
    function openAttendance(call) { attendanceCall = call; attendanceTab = true; tab = "Attendance" }
    // A channel meeting's report, over the channel (Teams' channel
    // Attendance view): {organizer, message, call}.
    property var channelAttendance: null
    // Load a channel's tabs once it's known which team it's in.
    // (By the id itself: while the conversation switches, isChannel can
    // still hold the last one's.)
    readonly property string tabsKey: chatId.endsWith("@thread.tacv2") && teamId ? teamId + "|" + chatId : ""
    onTabsKeyChanged: if (tabsKey) backend.channelTabsLoad(teamId, chatId, chatName)
    // A chat's own tabs (Add a tab's): its thread properties.
    readonly property string chatTabsKey: !isChannel && !isSelf && !pane && !popout && chatId.indexOf("19:") === 0 ? chatId : ""
    onChatTabsKeyChanged: if (chatTabsKey) backend.chatTabsLoad(chatId)
    /// Teams' "+" (Add a tab): chats, meeting chats and channels.
    readonly property bool canAddTab: !pane && (!popout || windowTabs) && !isSelf && chatId.indexOf("19:") === 0
    /// The channel's team thread (its General channel), for the picker.
    property string teamThread: ""
    // The tab picker and the Website configuration (Main.qml's).
    signal openTabPicker(string conversationId, string kind, string teamThread)
    /// A tab's Settings (Teams' updateTab): its app's configuration page,
    /// to set the tab up again.
    signal updateTabRequested(var tab)
    /// Bumped when a tab's settings change, so its page is framed afresh
    /// at its new address (Teams posts beforeUnload / load to it).
    property int tabRevision: 0
    // A channel's Page tab: the channel's Loop page in Loop's own page
    // container, as Teams hosts it (ChannelPageTab, docs/spec/loop-host.md).
    readonly property var webTab: channelTabs.find(t => t.name === tab && t.kind === "ChannelPage") || null
    // New pages this OST added (their pages are made when they open), and
    // whether the tab being added is one.
    property var newPageTabs: []
    property bool pendingNewPage: false
    function openTab(i) { if (i < tabNames.length) tab = i === 0 ? "" : tabNames[i] }
    // A tab picked from "+N": a website tab opens in the browser, as
    // Teams opens it; any other becomes the open tab.
    function openTabAt(i) {
        const t = channelTabs.find(x => x.name === tabNames[i])
        if (t && t.opens_in_browser) { if (t.website_url) backend.openExternal(t.website_url); return }
        manageApps = false
        tab = i === 0 ? "" : tabNames[i]
    }
    // "+": a channel's menu, or a chat's Add a tab picker.
    function addTab() {
        if (isChannel) { addTabMenu.open(); return }
        openTabPicker(chatId, isMeetingChat ? "meeting" : "chat", "")
    }
    function addTabMenuForTest() { addTabMenu.open(); return addTabMenu }
    // A channel's Add a tab choice (Teams' extraAddTabActions): New list
    // and Existing list add a Lists tab at once, which its page then sets
    // up; Existing page asks for the page's link; Apps opens the picker.
    function addTabChoice(key) {
        if (key === "apps") root.openTabPicker(root.chatId, "channel", root.teamThread)
        else if (key === "newList" || key === "existingList") backend.addListTab(root.teamId, root.chatId, key === "existingList")
        else if (key === "existingPage") existingPageDialog.start(root.teamId, root.chatId)
        // New page: Teams adds an "Untitled page" tab at once and opens it;
        // Loop's page container makes the page.
        else if (key === "newPage") { root.pendingNewPage = true; backend.addNewPageTab(root.teamId, root.chatId) }
    }
    // A tab just added opens, as Teams opens it (not a website tab, which
    // opens in the browser).
    property string pendingOpenTab: ""
    onChannelTabsChanged: if (pendingOpenTab) {
        const t = channelTabs.find(x => x.id === pendingOpenTab)
        if (t) { pendingOpenTab = ""; if (!t.opens_in_browser) { manageApps = false; tab = t.name } }
    }
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
    /// Settings ▸ Privacy (an app link card's settings button).
    signal openPrivacySettings()
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
        if (m) { root.openAppDetails(decodeURIComponent(m[1])); return }
        // Teams' settings deep links, /l/settings/<page>[/<sub-page>]
        // (async-apps-settings onBeforeDeeplinkParsed): the page, General
        // when unknown; manage-vip-contacts is Privacy's only sub-page link.
        const s = /^https:\/\/teams\.microsoft\.com\/l\/settings(?:\/([^/?#]*))?(?:\/([^/?#]*))?/i.exec(link)
        if (s) {
            const pages = ["about", "accounts", "appearance", "accessibility", "calendar", "calls", "chats_and_channels", "general", "meetings", "notifications", "people_setting", "privacy", "benefits", "captions_and_transcription", "devices", "recognition", "files_and_links", "phonelink", "app_permissions", "teams_insider", "localization", "teams_labs"]
            const pg = pages.find(p => p === (s[1] || "general").toLowerCase()) || "general"
            const sub = pg === "privacy" && (s[2] || "").toLowerCase() === "manage-vip-contacts" ? "privacy_manage_vip_contacts" : ""
            window.launchSettings(sub || pg)
            return
        }
        backend.openExternal(link)
    }
    signal scheduleMeeting()
    /// A clip's "Reply with a video clip": record one for this chat (only
    /// offered once OST can record clips).
    signal replyWithVideoClip()
    readonly property bool canRecordClips: !root.popout && !root.threadRoot && !root.pane
    onReplyWithVideoClip: { root.clipBox = compose; clipRecorder.openFor(root.chatId) }
    // Teams' recorder; its clip goes into the compose box and is stored at
    // once (Teams uploads it as the recorder closes).
    /// The compose box the recorder fills: the chat's own, or a message's
    /// edit box (Teams' edit box ▸ Actions and apps ▸ Record video clip).
    property Item clipBox: compose
    VideoClipRecorder {
        id: clipRecorder
        onFinished: clip => {
            const box = root.clipBox || compose
            box.clip = Object.assign({}, clip, { uploading: true, id: "", url: "", rendering: !!clip.spec })
            // An edited clip is made into one file first (Teams' recorder
            // does the same before it hands the clip over).
            if (clip.spec) backend.renderClip(JSON.stringify(clip.spec))
            else backend.videoClipUpload(chatId, clip.path, clip.thumb)
        }
    }
    /// A clip taken out of a box (its recordings deleted).
    function dropClip(box) {
        if (!box || !box.clip) return
        if (box.clip.path) backend.removeRecorderFile(box.clip.path)
        if (box.clip.spec) for (const sg of box.clip.spec.segments) backend.removeRecorderFile(sg.path)
        box.clip = null
    }
    function retryClip(box) {
        root.clipBox = box
        box.clip = Object.assign({}, box.clip, { uploading: true, error: "", rendering: !box.clip.path })
        if (box.clip.path) backend.videoClipUpload(root.chatId, box.clip.path, box.clip.thumb)
        else backend.renderClip(JSON.stringify(box.clip.spec))
    }
    Connections {
        target: backend
        function onClipRendered(json) {
            const box = root.clipBox || compose
            if (!box.clip || !box.clip.rendering) return
            const r = JSON.parse(json)
            if (r.error) { console.warn("CLIP render failed", r.error); box.clip = Object.assign({}, box.clip, { uploading: false, rendering: false, error: r.error }); return }
            // The parts' recordings are no longer needed.
            for (const sg of box.clip.spec.segments) backend.removeRecorderFile(sg.path)
            box.clip = Object.assign({}, box.clip, { rendering: false, path: r.path, duration: r.duration })
            backend.videoClipUpload(root.chatId, r.path, box.clip.thumb)
        }
    }
    Connections {
        target: backend
        function onVideoClipUploaded(path, json) {
            const box = root.clipBox || compose
            if (!box.clip || box.clip.path !== path) return
            const r = JSON.parse(json)
            if (r.error) { console.warn("CLIP upload failed", r.error); box.clip = Object.assign({}, box.clip, { uploading: false, error: r.error }); return }
            box.clip = Object.assign({}, box.clip, { uploading: false, id: r.id, url: r.url })
            console.info("CLIP stored", box === compose ? "compose" : "edit")
            if (box === compose && root.sendAfterClip) { root.sendAfterClip = false; root.sendCompose() }
        }
    }
    /// A new conversation's message waits for its clip to be stored.
    property bool sendAfterClip: false
    /// The new chat form's message, once its chat is open here: what was
    /// written ({text, html, media}), its delivery option, files from this
    /// device, cloud files and a recorded clip go as from this chat's own
    /// compose box (Teams makes the chat as the first message goes).
    function adoptAndSend(p) {
        compose.setDraftState({ text: p.text || "", html: p.html || "", media: p.media || [] })
        compose.importance = p.importance || ""
        root.pendingFiles = p.files || []
        cloudAttach.pending = p.cloud || []
        if (p.clip) {
            compose.clip = Object.assign({}, p.clip, { uploading: true, id: "", url: "", rendering: !!p.clip.spec && !p.clip.path })
            root.sendAfterClip = true
            if (compose.clip.rendering) backend.renderClip(JSON.stringify(compose.clip.spec))
            else backend.videoClipUpload(root.chatId, compose.clip.path, compose.clip.thumb)
            return
        }
        root.sendCompose()
    }
    function sendAfterClipForTest() { return root.sendAfterClip }
    function clipRecorderForTest() { return clipRecorder }
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
        title: qsTr("Remove chat history?")
        body: qsTr("This will remove the chat from your list and search. It affects you only.")
        confirmText: qsTr("Remove")
        onConfirmed: backend.removeChatHistory(root.chatId)
    }
    // Go to a message (a quote card's target), if it is loaded.
    // The chat's call: one going on (a start with no end), whether we're in
    // it, and Teams' 20-member limit for calls in group chats.
    // The thread's liveness entry (the chat list's liveCall) says so even
    // when the call's start isn't among the loaded messages.
    /// This chat's entry in the chat list (read once per list update).
    readonly property var chatEntry: (backend.chatsJson ? JSON.parse(backend.chatsJson) : []).find(c => c.id === root.chatId) || null
    readonly property var liveCall: chatEntry && chatEntry.liveCall ? chatEntry.liveCall : null
    readonly property bool chatMuted: !!(chatEntry && chatEntry.muted)
    /// An event's or meeting's group chat (Teams' backroom chat): "event", "meeting" or "".
    readonly property string backroom: chatEntry && chatEntry.backroom ? chatEntry.backroom : ""
    readonly property bool chatIsCreator: !!(chatEntry && chatEntry.isCreator)
    /// The chat's Recap (Teams' recap card: View recap, the transcript chip
    /// and the recording open the meeting's Recap view).
    signal openEventHighlights(string title, real startMs)
    // A recap card's recap (Teams' intelligent recap window), from its
    // ended row's message: the recording and the meeting.
    function recapRef(m, recap) {
        const rec = (recap.recordings || [])[0] || {}
        // A meeting chat (an event's group chat too) is the meeting's own
        // thread; its organizer is the meeting's (what Teams' recap
        // sharing names).
        const mt = root.meeting || {}
        return { thread_id: root.chatId.indexOf("19:meeting_") === 0 ? root.chatId : "", ical_uid: recap.ical_uid || mt.ical_uid || "", organizer_id: mt.organizer_id || "",
                 tenant_id: mt.tenant_id || backend.tenantId(), call_id: m.call_id || "",
                 drive_id: rec.drive_id || "", item_id: rec.item_id || "", file_url: rec.odb_url || "", subject: recap.subject || root.chatTopic || root.chatName,
                 start_ms: new Date(recap.start || 0).getTime(), end_ms: new Date(recap.end || recap.start || 0).getTime(),
                 recap_type: recap.transcript && (recap.recordings || []).length ? "RecordingAndTranscript" : recap.transcript ? "Transcript" : "Recording" }
    }
    function openRecap(m, recap, part) {
        // (Teams' Shared files list the meeting's attendance report.)
        const w = recapWindow.createObject(null, { recap: root.recapRef(m, recap), startTab: part === "transcript" ? "transcript" : "", hasAttendance: root.hasAttendanceReport || !!m.call_id })
        w.goToChat.connect(() => {})
        // Its Attendance opens the meeting chat in a window of its own on
        // the report, as from Meeting Recaps (Teams on winpc 2026-11-23,
        // OST TEST 240 recap meeting's card: openAttendanceTabInMeetingRecapOfChat
        // while the recap is in a window), not in this chat (TASK-0261).
        w.openAttendance.connect(() => root.attendanceOf(w.recap.thread_id || root.chatId, w.recap.subject || root.chatTopic || root.chatName))
        // Its toasts (Share's "Prompt copied", Manage's expiration) show as the app's.
        w.toast.connect(d => root.toastRequested(d))
        w.show(); w.raise(); w.requestActivate()
        root.lastRecapWindow = w
        console.info("RECAPCARD open", part || "recap")
    }
    // A recap opened from elsewhere (Events' Highlights ▸ View recap): the
    // meeting's thread and recording; the window looks up the rest.
    function openRecapRef(ref, tab) {
        // (Its Shared files list Attendance when the meeting has a report,
        // as Teams' meetingThreadProperties.hasAttendanceReport: looked up
        // once the window knows the meeting's organizer.)
        const w = recapWindow.createObject(null, { recap: Object.assign({ tenant_id: backend.tenantId(), ical_uid: "", organizer_id: "", call_id: "", file_url: "" }, ref), startTab: tab || "", findAttendance: true })
        w.toast.connect(d => root.toastRequested(d))
        w.openAttendance.connect(() => root.attendanceOf(w.recap.thread_id || "", w.recap.subject || ""))
        w.show(); w.raise(); w.requestActivate()
        root.lastRecapWindow = w
        console.info("RECAPCARD open", tab || "highlights")
    }
    property var lastRecapWindow: null
    Component { id: recapWindow; RecapWindow {} }
    // A recap window's Attendance (opened from Meeting Recaps' Home): the
    // meeting's chat in a window of its own on its Attendance report, as
    // Teams' openAttendanceTabInMeetingRecapOfChat (Main's ChatWindow),
    // whatever the main window shows.
    signal openChatForAttendance(string threadId, string title)
    function attendanceOf(thread, title) {
        if (thread) root.openChatForAttendance(thread, title)
    }
    // Share on the card: Teams' menu (Share recap access, Copy link).
    function openRecapShare(m, recap, anchor) {
        recapShareMenu.ref = root.recapRef(m, recap)
        recapShareMenu.popup(anchor, 0, anchor.height + 4)
    }
    Menu {
        id: recapShareMenu
        property var ref: null
        MenuItem { text: qsTr("Share recap access"); onTriggered: recapShare.openFor(recapShareMenu.ref) }
        MenuItem { text: qsTr("Copy link"); onTriggered: recapShare.copyLink(recapShareMenu.ref) }
    }
    RecapShareDialog { id: recapShare }
    function recapShareForTest() { return recapShare }
    function openRecapTab(part) {
        const i = root.tabNames.indexOf("Recap")
        if (i >= 0) root.tab = "Recap"
        console.info("RECAPCARD open", part || "recap", i >= 0)
    }
    readonly property string chatTopic: chatEntry && chatEntry.topic ? chatEntry.topic : ""
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
    Component.onCompleted: { if (!root.pane) watchTimer.restart(); loadWindowChat() }
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
    readonly property bool callsDisabled: root.chatMembers.length > 20
    // A member's name by MRI: call events name people only by MRI, and
    // Teams shows them by their roster name.
    function memberName(mri) {
        const m = root.chatMembers.find(p => (p.mri || "").toLowerCase() === String(mri || "").toLowerCase())
        return m ? m.name : ""
    }
    // Card types drawn natively (Teams' supported set, so far).
    /// Link previews show (Teams): Optional connected experiences on and
    /// your messaging policy allowing them.
    readonly property bool previewsShown: { const st = backend.settingsJson ? JSON.parse(backend.settingsJson) : {}; return (st.props || {}).controllerConnectedServicesEnabled !== "false" && !backend.urlPreviewsBlocked }
    readonly property var cardKinds: ["application/vnd.microsoft.card.adaptive", "application/vnd.microsoft.card.hero", "application/vnd.microsoft.card.thumbnail",
        "application/vnd.microsoft.teams.card.list", "application/vnd.microsoft.teams.card.o365connector", "application/vnd.microsoft.card.fluidEmbedCard"]
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
        loadWindowChat()
        qnaTabLoader.url = ""; whiteboardTabLoader.url = ""
        landing = true
        manageApps = false
        tabExpanded = false
        tabConversationTab = null
        openedAt = new Date()
        tab = ""; finding = false; findMark = { id: "", terms: [] }; seekId = ""; participants.visible = false; posting = false
        // (Teams closes a chat's Copilot when another chat opens.)
        copilotOpen = false; copilotHistoryOpen = false; copilotUnread = 0
        editingId = ""
        // A thread view keeps its reply's draft as Teams does (its post's
        // reply chain, "{channel};messageid={post}"), roamed with it.
        if (draftChat) root.saveDraft(draftChat)
        draftChat = root.threadRoot ? root.threadChannel + ";messageid=" + root.threadRoot : chatId
        root.loadDraft()
    }
    // The chat's kept draft into the box, and another device's different
    // one (Teams' roamed-draft conflict) onto its banner.
    function loadDraft() {
        const kept = draftChat ? backend.draftJson(draftChat) : ""
        const d = kept ? JSON.parse(kept) : null
        compose.setDraftState(d)
        compose.conflictDraft = d && d.conflict ? d.conflict : null
        compose.draftConflict = !!(d && d.conflict)
        draftShown = draftKey(compose.draftState())
    }
    // A draft changed on another device (Teams' roamed drafts): the box
    // takes it if you haven't typed since it loaded.
    Connections {
        target: backend
        function onDraftArrived(chat) {
            if (!root.draftChat || chat !== root.draftChat) return
            if (root.draftKey(compose.draftState()) !== root.draftShown) {
                const kept = backend.draftJson(chat)
                const d = kept ? JSON.parse(kept) : null
                compose.conflictDraft = d && d.conflict ? d.conflict : null
                compose.draftConflict = !!(d && d.conflict)
                return
            }
            root.loadDraft()
            console.warn("DRAFT arrived", chat, JSON.stringify(compose.draftState().text))
        }
    }
    // The draft as this box last loaded or saved it. Only a box changed
    // since then writes the chat's draft, so another view of the same chat
    // (a call's chat pane) never puts back an older copy.
    property string draftShown: ""
    function draftKey(d) { return JSON.stringify([d.text, d.html.replace(/codeBlockEditor-[0-9a-f-]+/g, ""), d.media, d.loop]) }
    // The compose box kept as the chat's draft, formatting and all (Teams
    // keeps a draft's formatting when you switch chats and restart).
    function saveDraft(chat) {
        const d = compose.draftState()
        const key = draftKey(d)
        if (key === draftShown) return
        backend.saveDraft(chat, d.text, d.html, JSON.stringify(d.media))
        draftShown = key
    }
    // Keep the draft current while typing (so it survives a quit).
    Timer {
        id: draftSave
        interval: 1000
        onTriggered: if (root.draftChat) root.saveDraft(root.draftChat)
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
        teamId: root.teamId; teamName: root.teamName; chatName: root.chatName; isSelfChat: root.isSelf
        defaultBox: compose
        onQuoteRequested: m => root.replyWithQuote(m)
        onReactRequested: (id, key, on) => root.react(id, key, on)
        onDeleteRequested: id => root.deleteMessage(id)
        onOpenChatSettings: root.openChatSettings()
        canPopOut: root.isChannel && !root.pane
        onThreadWindowRequested: m => root.openThreadWindow(m)
        canRecordClip: root.canRecordClips
        onRecordClipRequestedFor: box => { root.clipBox = box; clipRecorder.openFor(root.chatId) }
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
        w.joinMeeting.connect((url, title) => root.joinMeetingRequested(url, title))
        w.openMeetingDetails.connect((url, start) => root.openMeetingPage(url, start))
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
        const d = new Date(t), n = daysAgo(d), time = theme.time(d)
        if (n === 0) return time
        if (n === 1) return qsTr("Yesterday %1").arg(time)
        if (n > 1 && n < 7) return theme.fmtDate(d, "dddd") + " " + time
        if (d.getFullYear() === new Date().getFullYear()) return theme.dateNoYear(d) + " " + time
        return theme.date(d) + " " + time
    }
    function dayLabel(t) { return msgHost.dayLabel(t) }

    function annotate(msgs) {
        // A call's start shows only for Meet now ("… started a meeting.").
        // An event's or meeting's group chat shows it too ("{title} has started.").
        const out = msgs.filter(m => !(m.kind === "call" && m.call_state === "started" && !m.call_huddle && !root.backroom)).map(m => Object.assign({}, m))
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
            color: theme.hc("#2F2F4A", "#000000")
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
                font.family: theme.font; font.pixelSize: root.paneTitleSize; font.weight: root.paneTitleSemibold ? Font.DemiBold : Font.Bold
                color: theme.text
            }
            Repeater {
                id: paneActRepeater
                model: root.paneActions
                HeaderAction {
                    id: paneAct
                    required property var modelData
                    required property int index
                    x: parent.width - root.paneCloseRight - 32 * (root.paneActions.length - index)
                    icon: modelData.icon
                    iconColor: root.paneActionsOn.indexOf(modelData.key) >= 0 ? theme.brand : root.hdrStrong
                    onClicked: root.paneAction(modelData.key, paneAct)
                    ToolTip.visible: paneActHover.hovered && !!modelData.tip; ToolTip.delay: 500; ToolTip.text: modelData.tip || ""
                    HoverHandler { id: paneActHover }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.tip || ""
                }
            }
            HeaderAction {
                x: parent.width - root.paneCloseRight; icon: "dismiss-20"; Accessible.name: qsTr("Close %1").arg(root.paneTitle.toLowerCase())
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
            // More tabs than fit (several private chats): the row scrolls
            // sideways (wheel or drag) and keeps the chosen tab in view.
            Flickable {
                id: paneTabsFlick
                x: 8; width: parent.width - 16; height: 46.5
                contentWidth: paneTabsRow.width; contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                clip: true
                function showChosen() {
                    for (let i = 0; i < paneTabsRepeater.count; i++) {
                        const t = paneTabsRepeater.itemAt(i)
                        if (!t || !t.chosen) continue
                        if (t.x < contentX) contentX = t.x
                        else if (t.x + t.width > contentX + width) contentX = Math.min(t.x + t.width - width, Math.max(0, contentWidth - width))
                    }
                }
                Connections { target: root; function onPaneTabChanged() { Qt.callLater(paneTabsFlick.showChosen) } }
                onContentWidthChanged: Qt.callLater(showChosen)
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: ev => {
                        const d = ev.angleDelta.x !== 0 ? -ev.angleDelta.x : -ev.angleDelta.y
                        paneTabsFlick.contentX = Math.max(0, Math.min(paneTabsFlick.contentWidth - paneTabsFlick.width, paneTabsFlick.contentX + d / 2))
                    }
                }
            Row {
                id: paneTabsRow
                Repeater {
                    id: paneTabsRepeater
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
                            // A private chat tab: its picture first.
                            Avatar {
                                visible: !!ptab.modelData.person
                                anchors.verticalCenter: parent.verticalCenter
                                size: 20; name: ptab.modelData.label; photoId: ptab.modelData.photoId || ""
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ptab.modelData.label
                                font.family: theme.font; font.pixelSize: 14; font.weight: ptab.chosen ? Font.DemiBold : Font.Normal
                                color: ptab.chosen ? theme.text : theme.textStrong
                            }
                            Rectangle {
                                id: hcFill1
                                visible: ptab.modelData.badge !== undefined
                                anchors.verticalCenter: parent.verticalCenter
                                width: badgeText.implicitWidth + 12; height: 20; radius: 10
                                color: (ptab.modelData.count || 0) > 0 ? theme.pick("#E8EBFA", "#2F2F4A", "#000000") : theme.pick("#F0F0F0", "#2E2E2E", "#000000")
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: ptab.modelData.badge || ""
                                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: theme.onFill(hcFill1, (ptab.modelData.count || 0) > 0 ? theme.brandForeground1 : theme.textSecondary)
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
        }
        Item {
        visible: !root.pane
        anchors.fill: parent
        Avatar {
            visible: !root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: root.chatName; presence: root.chatPresence
            // A group chat: Teams' merged picture of its members (32 px).
            photoId: root.chatPhotoId || (root.isGroup && !root.isMeetingChat && root.chatId.indexOf("19:") === 0 ? "chat:" + root.chatId : "")
            opensProfile: !root.isGroup
            group: root.isGroup && !root.chatPhotoId
            // Teams: the calendar glyph filling a 32 px #C5CBFA circle.
            meeting: root.isMeetingChat
            meetingGlyph: 32
            meetingIcon: root.backroom ? "calendar-lock-20" : "meeting-chat-20"
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
            y: root.narrowTitle ? 10 : (parent.height - height) / 2
            height: root.narrowTitle ? 20 : implicitHeight
            lineHeight: root.narrowTitle ? 20 : 1; lineHeightMode: root.narrowTitle ? Text.FixedHeight : Text.ProportionalHeight
            // Long names elide so the tabs and actions keep their place.
            // Narrow: Teams' title (and the tab dropdown under it) ends where
            // the toolbar starts (measured: 220.2 px at a 452 px header).
            width: Math.max(0, Math.min(implicitWidth, root.narrowTitle ? root.narrowTitleEnd - x : parent.width * 0.35))
            elide: Text.ElideRight
            text: root.chatName
            font.family: theme.font; font.pixelSize: root.narrowTitle ? 14 : theme.title; font.weight: Font.Bold
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
            FluentIcon { anchors.centerIn: parent; name: renamePopup.opened || renameHover.hovered ? "edit-16-filled" : "edit-16"; size: 16; color: theme.onFill(renameButton, theme.textStrong) }
            HoverHandler { id: renameHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: renamePopup.open() }
            ToolTip {
                visible: renameHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: qsTr("Name group chat"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Name group chat")
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
                readonly property string error: nameField.text.length > 250 ? qsTr("Your group name can't be longer than %1 characters.").arg(250)
                    : nameField.text.indexOf(":") >= 0 ? qsTr("'%1' is not a valid character in group names.").arg(":") : ""
                Text { x: 16; y: 16; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Group name"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    x: 16; y: 40; width: parent.width - 32; height: 32; radius: 4
                    color: theme.surface
                    border.color: nameField.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: nameField.activeFocus ? 2 : 0.67; color: nameField.activeFocus ? theme.brand : theme.textSecondary }
                    TextInput {
                        id: nameField
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        Text { visible: !nameField.text; text: qsTr("Type a group name"); font: nameField.font; color: theme.textSecondary }
                        Keys.onReturnPressed: if (!renamePopup.error && nameField.text.trim()) { backend.renameChat(nameField.text); renamePopup.close() }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Group name")
                    }
                }
                Text { id: renameError; visible: !!renamePopup.error; x: 16; y: 76; text: renamePopup.error; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground1 }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    y: parent.height - 16 - 32
                    spacing: 8
                    Rectangle {
                        id: hcFill2
                        width: 96; height: 32; radius: 4
                        color: rcHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                        HoverHandler { id: rcHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: renamePopup.close() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Cancel")
                    }
                    Rectangle {
                        id: hcFill3
                        readonly property bool can: !renamePopup.error && nameField.text.trim().length > 0
                        width: 96; height: 32; radius: 4
                        color: !can ? theme.bgDisabled : rsHover.hovered ? theme.brandHover : theme.brandFill
                        Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, parent.can ? "white" : theme.disabledStrong) }
                        HoverHandler { id: rsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.can; onTapped: { backend.renameChat(nameField.text); renamePopup.close() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Save")
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
            const w = names.map((n, i) => (i === selIdx ? tabFontSel : tabFont).advanceWidth(root.tabLabel(i)) + 12 + 20 * (i === selIdx && !!root.channelTabs.find(t => t.name === n && t.menu.length > 0)))
            // The "+" (Add a tab, 32 wide) follows the tabs and "+N".
            const avail = (root.isChannel ? header.width - 160 : root.pane ? header.width - 48 : header.toolbarLeft) - tabs.x - 2 - 10 - (root.canAddTab ? 32 : 0)
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
            visible: !root.narrowTitle && (!root.popout || root.windowTabs)
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
                        text: root.tabLabel(tabItem.index)
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
                        color: root.liveBand ? theme.hc("#FFFFFF", "#000000") : theme.brand
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const t = tabItem.channelTab
                            // Teams opens website tabs in the browser; they never become the selected tab.
                            if (t && t.opens_in_browser) { if (t.website_url) backend.openExternal(t.website_url); return }
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
                    Accessible.name: tabText.text
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
                    text: root.tabDragFrom >= 0 ? root.tabLabel(root.tabDragFrom) : ""
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
                Accessible.name: qsTr("%1 more tabs.").arg(tabsFit.hidden.length)
                // A tab with a menu has it beside its row (Teams'
                // tab-item-with-submenu: the name, then a chevron).
                function ownTab(i) { return root.channelTabs.find(t => t.name === root.tabNames[i]) || null }
                MenuPopup {
                    id: tabOverflowMenu
                    x: 5; y: parent.height + 5
                    items: tabsFit.hidden.map(i => {
                        const t = tabOverflow.ownTab(i)
                        const m = t && t.context_menu.length ? t.context_menu.map(e => e.key === "divider" ? { separator: true } : { label: e.label, icon: tabMenu.icons[e.key] || "", enabled: e.enabled }) : null
                        return m ? { label: root.tabLabel(i), submenu: m } : { label: root.tabLabel(i) }
                    })
                    onPicked: k => root.openTabAt(tabsFit.hidden[k])
                    onSubPicked: (k, s) => { const t = tabOverflow.ownTab(tabsFit.hidden[k]); if (t) root.tabAction(t.context_menu[s].key, t) }
                }
            }
            // "+" (add-tab-button, Teams' Add a tab, measured on winpc
            // 2026-11-16): 32 x 60.3 after the tabs and "+N", padding 5,
            // the 20 px AddSquare in #424242; hovered (or its menu open)
            // the filled glyph in brand. A chat (or meeting chat) opens the
            // Add a tab picker; a channel a menu first.
            Item {
                id: addTabButton
                visible: root.canAddTab
                y: -2; width: 32; height: 60.3
                readonly property bool lit: addTabHover.hovered || addTabMenu.opened
                FluentIcon {
                    anchors.centerIn: parent
                    name: addTabButton.lit ? "add-square-20-filled" : "add-square-20"; size: 20
                    color: addTabButton.lit && !root.liveBand ? theme.brand : root.hdrStrong
                }
                HoverHandler { id: addTabHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.addTab() }
                ToolTip.visible: addTabHover.hovered && !addTabMenu.opened
                ToolTip.delay: 500
                ToolTip.text: qsTr("Add a tab")
                Accessible.role: Accessible.PageTab
                Accessible.name: qsTr("Add a tab")
                // A channel's Add a tab menu (add-tab-menu-item-*): New page,
                // Existing page, New list, Existing list, Apps; 1 below the
                // button, 128.7 wide.
                MenuPopup {
                    id: addTabMenu
                    x: 0; y: parent.height + 1
                    items: [
                        { label: qsTr("New page"), icon: "loop-page-20" },
                        { label: qsTr("Existing page"), icon: "link-20" },
                        { label: qsTr("New list"), icon: "lists-new-20" },
                        { label: qsTr("Existing list"), icon: "table-link-20" },
                        { label: qsTr("Apps"), icon: "apps-20" }
                    ]
                    onPicked: i => root.addTabChoice(["newPage", "existingPage", "newList", "existingList", "apps"][i])
                }
            }
        }
        // Below 640: the tabs as a dropdown under the title (Teams'
        // tab-overflow-button, module 454179): the open tab's name, 12 px
        // #424242 (brand while open), and a 12 px chevron 4 after it. Its
        // menu (max 300 tall in Teams, which scrolls) has Teams' order:
        // a channel's Add a tab choices (New page, Existing page, New list,
        // Existing list, Apps) and a divider; the fixed tabs; a divider
        // (only without those choices); the tabs you can move, each with
        // its menu beside it (a split item); and, without the choices, "Add
        // a tab". The open tab is checked (Fluent's check column).
        Item {
            id: tabDropdown
            visible: root.narrowTitle && !root.pane && !root.popout && root.narrowTitleEnd - title.x >= ddRow.implicitWidth
            x: title.x; y: 28; width: ddRow.implicitWidth; height: 17.3
            Row {
                id: ddRow
                anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.tab === "" ? root.tabLabel(0) : root.tabLabelOf(root.tab); font.family: theme.font; font.pixelSize: 12; color: tabDropdownMenu.opened ? theme.brand : theme.textStrong }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: tabDropdownMenu.opened ? theme.brand : theme.textStrong }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: tabDropdownMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: root.tab === "" ? root.tabLabel(0) : root.tabLabelOf(root.tab)
            function ownTab(i) { return root.channelTabs.find(t => t.name === root.tabNames[i]) || null }
            readonly property var entries: {
                const sel = root.tab === "" ? 0 : root.tabNames.indexOf(root.tab)
                const fixed = [], movable = []
                for (let i = 0; i < root.tabNames.length; i++) {
                    const t = tabDropdown.ownTab(i)
                    const draggable = root.isChannel ? root.tabIsDraggable(i) : !!t && t.draggable !== false
                    // The open tab's own menu, else a movable tab's
                    // right-click menu (Teams web: Shared, a fixed tab, has
                    // none in the dropdown).
                    const m = !t ? [] : i === sel && t.menu && t.menu.length ? t.menu : draggable ? (t.context_menu || []) : []
                    const e = { kind: "tab", index: i, tab: t, menu: m, item: { label: root.tabLabel(i), checked: i === sel } }
                    if (m.length) {
                        e.item.split = true
                        e.item.splitLabel = qsTr("More menu")
                        e.item.submenu = m.map(x => x.key === "divider" ? { separator: true } : { label: x.label, icon: tabMenu.icons[x.key] || "", enabled: x.enabled })
                    }
                    (draggable ? movable : fixed).push(e)
                }
                const out = []
                const choices = root.canAddTab && root.isChannel
                if (choices) {
                    out.push({ kind: "add", key: "newPage", item: { label: qsTr("New page"), icon: "loop-page-20" } },
                             { kind: "add", key: "existingPage", item: { label: qsTr("Existing page"), icon: "link-20" } },
                             { kind: "add", key: "newList", item: { label: qsTr("New list"), icon: "lists-new-20" } },
                             { kind: "add", key: "existingList", item: { label: qsTr("Existing list"), icon: "table-link-20" } },
                             { kind: "add", key: "apps", item: { label: qsTr("Apps"), icon: "apps-20" } },
                             { kind: "sep", item: { separator: true } })
                }
                out.push(...fixed)
                if (fixed.length && (movable.length || root.canAddTab) && !choices) out.push({ kind: "sep", item: { separator: true } })
                out.push(...movable)
                if (root.canAddTab && !choices) out.push({ kind: "add", key: "addTab", item: { label: qsTr("Add a tab"), icon: "add-20" } })
                return out
            }
            MenuPopup {
                id: tabDropdownMenu
                y: parent.height + 1
                checkColumn: true
                submenuMinWidth: 0
                items: tabDropdown.entries.map(e => e.item)
                onPicked: k => {
                    const e = tabDropdown.entries[k]
                    if (e.kind === "tab") root.openTabAt(e.index)
                    else if (e.kind === "add" && e.key !== "addTab") root.addTabChoice(e.key)
                    else if (e.key === "addTab") root.addTab()
                }
                onSubPicked: (k, j) => {
                    const e = tabDropdown.entries[k]
                    if (e.tab && e.menu[j]) root.tabAction(e.menu[j].key, e.tab)
                }
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
            FluentIcon { id: haIcon; anchors.centerIn: parent; size: ha.iconSize; color: theme.onFill(ha, ha.iconColor) }
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
            Accessible.name: backend.headerCallVideo ? qsTr("Video call") : qsTr("Audio call")
        }
        HeaderAction {
            visible: callPrimary.visible
            x: oneToOnePeople.x - 24; width: 24; height: 31.3
            icon: "chevron-down-16"; iconSize: 16
            Accessible.name: qsTr("More call options")
            onClicked: callMenu.open()
            MenuPopup {
                id: callMenu
                x: parent.width - 4.6 - width; y: parent.height + 4.9
                items: [{ label: qsTr("Video call"), icon: "video-20", keys: "Alt+Shift+V" }, { label: qsTr("Audio call"), icon: "call-20", keys: "Alt+Shift+A" }]
                onPicked: i => i === 0 ? root.videoCall() : root.call()
            }
        }
        HeaderAction {
            id: oneToOnePeople
            // Teams' channel header has no people button.
            visible: !root.isSelf && !root.isGroup && !root.isChannel
            x: root.isChannel ? parent.width - 151 : root.actionRight - 28; width: 28
            icon: "people-add-20"
            Accessible.name: root.isChannel ? qsTr("View participants") : qsTr("Start a group chat")
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
                GradientStop { position: 0; color: theme.hc("#AD00FF", "#FFFFFF") }
                GradientStop { position: 0.3225; color: theme.hc("#2200FF", "#FFFFFF") }
                GradientStop { position: 0.5689; color: theme.hc("#AB9EFF", "#FFFFFF") }
                GradientStop { position: 0.8007; color: theme.hc("#3EB0F0", "#FFFFFF") }
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
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "live-roster-20-filled"; size: 20; color: theme.onFill(liveRoster, theme.brand) }
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
                            color: theme.pick("#EBEBEB", "#333333", "#000000")
                            Text { anchors.centerIn: parent; text: "+" + joinButton.hidden; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.pick("#616161", "#ADADAD", "#FFFFFF") }
                        }
                    }
                    HoverHandler { id: rosterPillHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: participants.visible = !participants.visible }
                    ToolTip {
                        visible: rosterPillHover.hovered; delay: 500
                        y: parent.height + 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: qsTr("View participants"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("View participants")
                }
                Rectangle { visible: !root.inThisCall; width: 0.67; height: 32; color: theme.stroke }
                Rectangle {
                    id: hcFill4
                    visible: !root.inThisCall
                    width: joinText.implicitWidth + 20; height: 32
                    topRightRadius: 4; bottomRightRadius: 4
                    color: joinHover.hovered ? theme.hover : theme.surface
                    Text { id: joinText; anchors.centerIn: parent; text: qsTr("Join"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, joinHover.hovered ? theme.brand : theme.textStrong) }
                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: backend.callState === ""; onTapped: backend.joinGroupCall() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Join")
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
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: meetHover.hovered && !root.callsDisabled ? "video-20-filled" : "video-20"; size: 20; color: theme.onFill(meetNow, root.callsDisabled ? theme.disabled : meetHover.hovered ? theme.brand : theme.textStrong) }
                Text { visible: meetNow.wide; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Meet now"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(meetNow, root.callsDisabled ? theme.disabled : meetHover.hovered ? theme.brand : theme.textStrong) }
            }
            HoverHandler { id: meetHover; cursorShape: root.callsDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !root.callsDisabled && backend.callState === ""; onTapped: backend.meetNow() }
            ToolTip {
                visible: meetHover.hovered && (!meetNow.wide || root.callsDisabled); delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: root.callsDisabled ? qsTr("Calls aren't available in chats with more than %1 people").arg(20) : qsTr("Meet now"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Meet now")
        }
        Rectangle {
            id: hcFill5
            visible: meetNow.visible
            x: rosterCount.leftEdge - 28; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 36; radius: 4
            color: chevHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-16"; size: 16; color: theme.onFill(hcFill5, root.callsDisabled ? theme.disabled : theme.textStrong) }
            HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: groupCallMenu.open() }
            ToolTip {
                visible: chevHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: qsTr("More call options"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More call options")
            MenuPopup {
                id: groupCallMenu
                x: parent.width - width; y: parent.height + 4
                items: [{ label: qsTr("Audio call"), icon: "call-20", enabled: !root.callsDisabled }]
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
            Accessible.name: qsTr("Meeting duration %1").arg(text)
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
                color: theme.pick("#EBEBEB", "#333333", "#000000")
                Text { anchors.centerIn: parent; text: "+" + bandRoster.hidden; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#616161", "#ADADAD", "#FFFFFF") }
            }
        }
        Rectangle {
            id: meetingJoin
            visible: root.isMeetingChat && !!root.meeting && !root.meeting.cancelled
            readonly property bool can: !root.inThisCall && backend.callState === ""
            x: rosterCount.leftEdge - 8 - width; anchors.verticalCenter: parent.verticalCenter
            width: meetingJoinText.implicitWidth + 16; height: 31.3; radius: 4
            color: !can ? theme.bgDisabled : meetingJoinHover.hovered ? theme.brandHover : theme.brandFill
            Text { id: meetingJoinText; anchors.centerIn: parent; text: qsTr("Join"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(meetingJoin, meetingJoin.can ? "white" : theme.disabledStrong) }
            HoverHandler { id: meetingJoinHover; cursorShape: meetingJoin.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: meetingJoin.can; onTapped: backend.joinMeeting(root.meeting.join_url, root.meeting.subject || root.chatName) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Join")
        }
        // Group chats: the roster count (chat-header-participant-count):
        // PeopleAdd and the bold 12 px member count.
        Rectangle {
            visible: root.isGroup && !root.isChannel && !root.isSelf && !root.rosterInMenu
            readonly property int count: root.chatMembers.length
            id: rosterCount
            // Where the call controls end: the roster's left edge, or the
            // action area's right edge when the roster is in ···.
            readonly property real leftEdge: visible ? x : root.actionRight
            x: root.actionRight - width; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(28, 4 + 20 + 2 + countLabel.implicitWidth + 4); height: 32; radius: 4
            color: rosterHover.hovered && !root.liveBand ? theme.hover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 2
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 20; color: theme.onFill(rosterCount, root.hdrStrong) }
                Text { id: countLabel; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.count; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.onFill(rosterCount, root.hdrStrong) }
            }
            HoverHandler { id: rosterHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: participants.visible = !participants.visible }
            ToolTip {
                visible: rosterHover.hovered; delay: 500
                y: parent.height + 4; padding: 8
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text { text: qsTr("View and add participants"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("View and add participants") + ", " + qsTr("%1 participants").arg(count)
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
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: channelMeetHover.hovered && !channelMeet.blocked ? "video-20-filled" : "video-20"; size: 20; color: theme.onFill(channelMeet, channelMeet.blocked ? theme.disabled : channelMeetHover.hovered ? theme.brand : root.hdrStrong) }
                Text { visible: root.channelMeetWide; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Meet now"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(channelMeet, channelMeet.blocked ? theme.disabled : channelMeetHover.hovered ? theme.brand : root.hdrStrong) }
            }
            HoverHandler { id: channelMeetHover; cursorShape: channelMeet.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !channelMeet.blocked; onTapped: root.channelMeetNow() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Meet now")
        }
        HeaderAction {
            id: channelMeetMore
            visible: channelMeet.visible
            x: channelMeet.x + channelMeet.width; width: 20; height: 32
            icon: "chevron-down-16"; iconSize: 16
            iconColor: channelMeetMenu.opened ? theme.brand : root.hdrStrong
            onClicked: channelMeetMenu.open()
            Accessible.name: qsTr("More channel meeting options")
            // Meet now / Schedule a meeting (161.8 wide, its end 4.5 inside
            // the chevron's, 4.5 below it).
            MenuPopup {
                id: channelMeetMenu
                x: parent.width - 4.5 - width; y: parent.height + 4.5
                items: [
                    { key: "meet", label: qsTr("Meet now"), icon: "video-20", enabled: !channelMeet.blocked },
                    { key: "schedule", label: qsTr("Schedule a meeting"), icon: "calendar-add-20" }
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
            ToolTip.text: open ? qsTr("Hide tab conversation") : qsTr("Show tab conversation")
            HoverHandler { id: tabConvHover }
            Accessible.name: open ? qsTr("Hide tab conversation") : qsTr("Show tab conversation")
        }
        // Meeting details (chat-meeting-details): 32 x 31.3, TextBulletList,
        // after the roster count (measured on winpc).
        HeaderAction {
            visible: root.meetingDetailsInline
            x: root.contextLeft - 16 - 32; icon: "text-bullet-list-20"; Accessible.name: qsTr("Meeting details")
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
            ToolTip.text: root.threadsOpen ? qsTr("Close threads") : qsTr("Open threads")
            HoverHandler { id: threadsHover }
            Accessible.name: root.threadsOpen ? qsTr("Close threads") : qsTr("Open threads")
        }
        // Open / Close Copilot (chat-copilot-button): Copilot's mark, filled
        // brand while its pane shows.
        HeaderAction {
            visible: root.copilotButton > 0
            x: root.contextLeft
            icon: root.copilotOpen ? "copilot-filled-48" : "ai-copilot"
            iconColor: root.copilotOpen ? theme.brand : root.hdrStrong
            onClicked: root.toggleCopilot()
            ToolTip.visible: copilotHover.hovered; ToolTip.delay: 500
            ToolTip.text: (root.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot")) + " (Alt+C)"
            HoverHandler { id: copilotHover }
            Accessible.name: root.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot")
        }
        // In a channel, Find and Channel details show only on Posts (Teams).
        HeaderAction {
            visible: root.contextInline >= 1 && !(root.isChannel && root.tab !== "")
            x: root.contextLeft + 32 * (root.threadsButton + root.copilotButton); icon: "search-20"; Accessible.name: root.isChannel ? qsTr("Find in channel") : qsTr("Find in chat")
            iconColor: root.finding ? theme.brand : root.hdrStrong
            onClicked: root.toggleFind()
        }
        HeaderAction {
            visible: root.contextInline >= 2 && !(root.isChannel && root.tab !== "")
            x: root.contextLeft + 32 * (1 + root.threadsButton + root.copilotButton); icon: root.isChannel ? "panel-right-expand-20" : "panel-left-20"; Accessible.name: root.isChannel ? qsTr("Open channel details") : qsTr("Open chat details")
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
            Accessible.name: qsTr("More channel options")
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
            x: parent.width - 43; icon: "more-horizontal-20"; Accessible.name: qsTr("More chat options")
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
                    root.contextInline < 1 ? { key: "find", label: qsTr("Find in chat"), icon: "search-20" } : null,
                    root.contextInline < 2 ? { key: "details", label: qsTr("In this chat"), icon: "panel-left-20", keys: "Alt+P" } : null,
                    root.rosterInMenu ? { key: "participants", label: qsTr("Participants"), icon: "people-add-20" } : null,
                    root.meetingDetailsShown && !root.meetingDetailsInline ? { key: "meetingDetails", label: qsTr("Meeting details"), icon: "text-bullet-list-20" } : null
                ].filter(i => i !== null)
                readonly property bool calls: !root.isSelf && !root.isMeetingChat
                items: (moved.length ? moved.concat([{ separator: true }]) : []).concat([
                    root.copilotButton ? { key: "copilotHistory", label: qsTr("View Copilot history"), icon: "history-copilot-20" } : null,
                    root.copilotButton ? { separator: true } : null,
                    root.popout ? null : { key: "window", label: qsTr("Open in new window"), icon: "open-window-20", keys: "Ctrl+O" },
                    root.popout ? null : { separator: true },
                    calls ? { key: "meeting", label: qsTr("Schedule meeting"), icon: "calendar-add-20" } : null,
                    calls ? { key: "share", label: qsTr("Share screen"), icon: "share-screen-start-20", keys: "Ctrl+Shift+E" } : null,
                    calls ? { separator: true } : null,
                    { key: "unread", label: qsTr("Mark as unread"), icon: "glasses-off-20" },
                    { key: "move", label: qsTr("Move to section"), icon: "star-20", submenu: root.moveTargets() },
                    root.sectionHolder ? { key: "removeFrom", label: qsTr("Remove from section"), icon: "star-off-20" } : null,
                    root.isSelf ? null : { key: "mute", label: root.chatMuted ? qsTr("Unmute") : qsTr("Mute"), icon: root.chatMuted ? "alert-20" : "alert-off-20" },
                    { key: "link", label: qsTr("Copy link"), icon: "link-20" },
                    root.isSelf ? null : { separator: true },
                    root.isSelf ? null : root.isMeetingChat ? { key: "report", label: qsTr("Report a concern"), icon: "shield-error-20" } : { key: "removeHistory", label: qsTr("Remove chat history"), icon: "delete-20" }
                ]).filter(i => i !== null)
                onPicked: i => {
                    const k = items[i].key
                    if (k === "details" || k === "participants") participants.visible = !participants.visible
                    else if (k === "find") root.toggleFind()
                    else if (k === "copilotHistory") root.copilotHistoryOpen = true
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
        text: qsTr("Select a chat to start messaging")
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
        members: root.chatMembers
        onJoinMeeting: (url, title) => root.joinMeetingRequested(url, title)
        onSeeDetails: rootId => root.openPostView(rootId)
        onOpenMeetingDetails: (url, start) => root.openMeetingPage(url, start)
        busy: root.busy
        onReply: (id, text) => root.sendReply(id, text)
        onReact: (id, key, on) => root.react(id, key, on)
        host: msgHost
        posting: root.posting
        onStartPost: { root.posting = true; compose.focusSubject() }
        onOpenImage: (list, i, m) => root.openImageViewer(list, i, m)
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
            // The list grows upward, so the message above is created later
            // and would paint over this one's hover bar (which sits on the
            // bubble's top edge, over the message above). Teams' bar is
            // always on top: raise the message while its bar shows.
            z: actions.visible ? 2 : 1
            function focusReactions() { actions.focusReactions() }
            readonly property bool reactionsFocused: actions.activeFocus
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
            readonly property real repliesDivH: root.threadPane && root.threadRepliesDivider && modelData.id === root.threadRoot && repliesCount > 0 ? 28 : 0
            readonly property int repliesCount: root.threadPane ? root.messages.filter(m => m.id !== root.threadRoot && m.kind === "message").length : 0
            // A reply also sent to the channel: "Replied in thread: {first
            // message}" in the channel, "Also sent to channel" in the thread.
            readonly property bool scheduledMsg: !!modelData.scheduled_at
            readonly property string sharedHead: !modelData.shared_in_main || modelData.id === modelData.root_id ? ""
                : root.threadsLayout ? "thread" : root.threadPane ? "channel" : ""
            // Teams' Attendance card under an ended meeting (28 down, 49.3).
            // Teams' recap card (the call's recordings or transcript) takes
            // the place of the attendance card: the row 28, the card 14
            // under it, 162 tall.
            readonly property bool recapCard: isCall && modelData.call_state === "ended" && !!modelData.recap
            readonly property bool attendanceCard: isCall && root.isMeetingChat && root.canSeeAttendance && !recapCard
                && modelData.call_state !== "started" && modelData.call_state !== "missed" && !!modelData.call_id
            height: isRow ? topPad + (isCall ? (recapCard ? 28 + 14 + 162 : attendanceCard ? 28 + 49.3 : 36) : 28)
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
                    text: qsTr("Last read")
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
                Accessible.name: qsTr("Last read")
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
                         MemberRenamed: "person-edit-20", AddCustomApp: "apps-20", AgentAdded: "apps-20", DeleteCustomApp: "apps-20",
                         RecordingStarted: "record-20", RecordingStopped: "record-stop-20", RecordingSaved: "cloud-arrow-up-20",
                         Transcript: "slide-text-20", NotesCreated: "document-edit-20" })[msg.modelData.event ? msg.modelData.event.kind : ""] || "person-add-20"
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
                    // The chat's Notes row: its "Notes" opens the Notes tab
                    // (Teams' FileAdd row, an inline link in the row's colour).
                    readonly property bool notesRow: msg.isEvent && !!msg.modelData.event && msg.modelData.event.kind === "NotesCreated"
                    textFormat: msg.recordingRow || unverified.length > 0 || notesRow ? Text.RichText : msg.isCall || msg.appAdded ? Text.StyledText : Text.PlainText
                    linkColor: theme.brandForeground1
                    // A saved recording's "Remove expiration" opens it (Teams
                    // opens its player's About panel, which is web content).
                    onLinkActivated: link => { if (link === "ost:notes-tab") root.tab = "Notes"; else backend.openExternal(link) }
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    text: {
                        if (msg.recordingRow) {
                            const e = msg.modelData.event
                            const t = root.escapeHtml(msg.modelData.text)
                            return e.kind === "RecordingSaved" && e.value && e.link ? t + " <a href=\"" + e.link.replace(/"/g, "&quot;") + "\" style=\"text-decoration: none; color: " + theme.brandForeground1 + "\">" + qsTr("Remove expiration", "messaging:kads6v9uz") + "</a>" : t
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
                        if (notesRow) return qsTr("%1 have been created in this chat.", "messaging:kctkghgyc").arg("<a href=\"ost:notes-tab\" style=\"text-decoration: none; color: " + theme.textSecondary + "\">" + qsTr("Notes", "messaging:k9lem59qr") + "</a>")
                        if (msg.isEvent) return msg.modelData.text
                        // Meet now (Teams: "You started a meeting." /
                        // "{{initiator}} started a meeting.", then
                        // "Meeting ended" with the duration).
                        // An event's or meeting's group chat (Teams' backroom
                        // chat, measured 2026-11-20 in "Event group: OST TEST
                        // 217 town hall 2"): "{title} has started." and
                        // "{title} has ended. {duration}".
                        const brTitle = root.backroom ? root.escapeHtml(root.chatTopic || root.chatName) : ""
                        if (brTitle && msg.modelData.call_state === "started")
                            return root.backroom === "event" ? qsTr("%1 has started.", "messaging:k15ntfp7n").arg(brTitle) : qsTr("%1 has started.", "messaging:kd3dbdxsw").arg(brTitle)
                        if (msg.modelData.call_state === "started")
                            return msg.mine ? qsTr("You started a meeting.") : qsTr("%1 started a meeting.").arg(root.escapeHtml(msg.modelData.sender || root.memberName(msg.modelData.sender_mri) || qsTr("Someone")))
                        if (msg.modelData.call_state === "missed") return qsTr("Call missed")
                        const s = msg.modelData.call_seconds
                        // Teams leaves out whole days ("d.hh:mm:ss" reads as
                        // its hours): a 25h 28m meeting shows "1h 28m 28s".
                        // Teams' tmp_calling_duration_mf ("11m", "11Min.", "١١د").
                        const parts = root.escapeHtml(backend.durationText("call", s))
                        // A meeting chat says "Meeting ended: {duration}" (seen in OST
                        // calendar test on winpc, 2026-11-10).
                        if (brTitle) return (root.backroom === "event" ? qsTr("%1 has ended.", "messaging:kqok16p0").arg(brTitle) : qsTr("%1 has ended.", "messaging:k3flolqwp").arg(brTitle)) + "&nbsp;<b>" + parts + "</b>"
                        if (root.isMeetingChat) return qsTr("Meeting ended:") + "&nbsp;<b>" + parts + "</b>"
                        return (msg.modelData.call_huddle ? qsTr("Meeting ended", "messaging:k1wmbpk3x") : qsTr("Call ended", "messaging:k4276a36f")) + "&nbsp;<b>" + parts + "</b>"
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
            Loader {
                active: msg.recapCard
                x: root.gutContent; y: msg.topPad + 28 + 14
                sourceComponent: RecapCard {
                    width: Math.min(646, list.width - root.gutContent - 32)
                    // Teams: a group chat with a topic (an event group) is titled by its
                    // topic, a meeting by its subject.
                    recap: root.backroom && root.chatTopic ? Object.assign({}, msg.modelData.recap, { subject: root.chatTopic }) : msg.modelData.recap
                    fallbackTitle: root.chatTopic || root.chatName
                    // Teams: Highlights for a town hall's or webinar's
                    // organizers (its event group chat's creator here).
                    highlights: root.backroom === "event" && root.chatIsCreator
                    onOpenRecap: t => root.openRecap(msg.modelData, recap, t)
                    onOpenHighlights: root.openEventHighlights(recap.subject || root.chatTopic || root.chatName, new Date(recap.start || 0).getTime())
                    onShare: anchor => root.openRecapShare(msg.modelData, recap, anchor)
                }
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
                photoId: (msg.modelData.sender_mri || "") + (msg.modelData.sender_app ? "#" + msg.modelData.sender_app : "")
                // A bot: its app's icon in a square with 4 px corners (Teams).
                // An AI agent (a Channel Agent): its logo in a circle on
                // NeutralBackground2, with "Available" (Teams' agent-avatar,
                // measured on winpc 2026-11-21).
                square: String(msg.modelData.sender_mri || "").startsWith("28:") && !msg.modelData.ai_agent
                squareRadius: 4
                photoBackground: msg.modelData.ai_agent ? theme.pick("#FAFAFA", "#1F1F1F", "#000000") : "transparent"
                opensProfile: !square && !msg.modelData.ai_agent
                // Teams shows the sender's presence on message avatars too.
                presence: msg.modelData.ai_agent ? "Available" : msg.modelData.sender_mri && msg.modelData.sender_mri === root.chatPhotoId ? root.chatPresence : ""
            }
            Text {
                visible: msg.groupedEdited
                x: msg.mine ? bubble.x + bubble.width - width : bubble.x
                y: msg.topPad + 2; height: 16
                text: qsTr("Edited")
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
                    visible: msg.sendFailed && msg.modelData.send_note === qsTr("Message didn't send. Check your connection or try again later.", "messaging:k15klm2m")
                    text: qsTr("Report a problem")
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
                    // (An AI agent's name stands alone: its tag and the time
                    // follow as their own items.)
                    readonly property bool agentTag: !!msg.modelData.ai_agent && !root.compact && !msg.mine
                    text: agentTag ? root.senderLabel(msg.modelData)
                        : root.compact
                        ? "<b><font color=\"" + theme.text + "\">" + root.senderLabel(msg.modelData).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font></b>&nbsp;&nbsp;" + root.stamp(msg.modelData.time) + (msg.modelData.edited && !msg.sendFailed ? "&nbsp;&nbsp;&nbsp;" + qsTr("Edited") : "") + (root.cardUpdated(msg.modelData.id) ? "&nbsp;&nbsp;&nbsp;" + qsTr("Updated") : "")
                        : (msg.mine ? "" : root.senderLabel(msg.modelData) + "  ") + root.stamp(msg.modelData.time)
                        + (msg.modelData.edited && !msg.sendFailed ? "   " + qsTr("Edited") : "")
                        + (root.cardUpdated(msg.modelData.id) ? "   " + qsTr("Updated") : "")
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
                // Teams' "AI agent" tag on an AI bot's messages (its
                // message-disclaimer, measured on winpc 2026-11-21: 10 px
                // NeutralForeground3 in a 17.3 tall outline, radius 4, 2 px
                // padding, 4 after the name; the tooltip "AI-generated
                // content may be incorrect"), then the time.
                Item {
                    visible: metaText.agentTag
                    width: agentTagBox.width - 4; height: 16
                    Rectangle {
                        id: agentTagBox
                        x: -4; y: -0.65
                        width: agentTagText.implicitWidth + 4 + 1.34; height: 17.3; radius: 4
                        color: "transparent"
                        border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                        Text { id: agentTagText; anchors.centerIn: parent; text: qsTr("AI agent", "messaging:k6gdrts20"); font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                        HoverHandler { id: agentTagHover }
                        ToolTip.visible: agentTagHover.hovered; ToolTip.delay: 500
                        ToolTip.text: qsTr("AI-generated content may be incorrect", "messaging:kd2tqw453")
                        Accessible.role: Accessible.StaticText; Accessible.name: agentTagText.text
                    }
                }
                Text {
                    visible: metaText.agentTag
                    text: root.stamp(msg.modelData.time) + (msg.modelData.edited ? "   " + qsTr("Edited") : "") + (root.cardUpdated(msg.modelData.id) ? "   " + qsTr("Updated") : "")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                // Teams' delivery option label: IMPORTANT / URGENT, 12 px
                // semibold, RedForeground3, 8 after the time (measured).
                Text {
                    visible: msg.modelData.importance === "high" || msg.modelData.importance === "urgent"
                    text: msg.modelData.importance === "urgent" ? qsTr("Urgent").toUpperCase() : qsTr("IMPORTANT")
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                    color: theme.redForeground3
                    Accessible.role: Accessible.StaticText
                    Accessible.name: msg.modelData.importance === "urgent" ? qsTr("Urgent message.") : qsTr("Important message.")
                }
                // Teams' translation suggestion (Ask me before translating, or
                // the original of a message it auto-translated): "Translate |
                // Never translate German", 12 px BrandForeground1 links 8
                // apart around a 20 px NeutralStroke3 rule (measured).
                Row {
                    visible: (msg.modelData.suggest_translation || "") !== ""
                    spacing: 8
                    Text {
                        id: suggestTranslate
                        text: qsTr("Translate")
                        font.family: theme.font; font.pixelSize: theme.small
                        font.underline: suggestTrHover.hovered
                        color: theme.brand
                        HoverHandler { id: suggestTrHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.translateMessage(msg.modelData.id, true) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Translate")
                        Accessible.onPressAction: backend.translateMessage(msg.modelData.id, true)
                    }
                    Rectangle { width: 1; height: 20; y: suggestTranslate.y + 3.3; color: theme.quoteBorder }
                    Text {
                        text: qsTr("Never translate %1").arg(msg.modelData.suggest_translation_name || "")
                        font.family: theme.font; font.pixelSize: theme.small
                        font.underline: neverTrHover.hovered
                        color: theme.brand
                        HoverHandler { id: neverTrHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.neverTranslate(msg.modelData.suggest_translation) }
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Accessible.onPressAction: root.neverTranslate(msg.modelData.suggest_translation)
                    }
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
                        contentItem: Text { text: msg.modelData.translated_from ? qsTr("Translated from %1").arg(msg.modelData.translated_from) : qsTr("Translated"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: msg.modelData.translated_from ? qsTr("Translated from %1").arg(msg.modelData.translated_from) : qsTr("Translated")
                }
                Row {
                    visible: msg.modelData.translation_failed === true
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "error-circle-20-filled"; size: 16; color: theme.redForeground1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Failed to translate"); font.family: theme.font; font.pixelSize: theme.small; color: theme.redForeground1 }
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
                        contentItem: Text { text: qsTr("Saved by you. Others won't see that it was saved."); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.name: qsTr("Saved by you. Others won't see that it was saved.")
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
                    // Teams' edit box also attaches files, makes a Loop
                    // component, sets the delivery option and records a
                    // clip (TASK-0263), all sent with Done.
                    chatTitle: root.chatTopic || root.chatName
                    editTeamId: root.teamId; editTeamName: root.teamName
                    deliveryOptions: !msg.scheduledMsg
                    canRecordClip: root.canRecordClips && !msg.scheduledMsg
                    onRecordClipRequested: { root.clipBox = editBox; clipRecorder.openFor(root.chatId) }
                    onClipRemoved: root.dropClip(editBox)
                    onClipRetry: root.retryClip(editBox)
                    onSubmit: {
                        if (msg.scheduledMsg) backend.editScheduled(msg.modelData.draft_id, msg.modelData.client_message_id || "", editBox.formattedText(), JSON.stringify(editBox.mediaInUse()), String(Math.round(editBox.scheduleAt)))
                        else {
                            if (editBox.editWaiting) return
                            backend.editMessageWith(msg.modelData.id, editBox.formattedText(), editBox.quote ? JSON.stringify(editBox.quote) : "", JSON.stringify(editBox.mediaInUse()), editBox.editExtras())
                            editBox.editSent()
                        }
                        root.editingId = ""
                    }
                    onCancelled: { root.dropClip(editBox); root.editingId = "" }
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
                // The sender's link preview (Teams' url-preview, measured on
                // winpc 2026-11-15): 6 under the text, the bubble ending
                // 14.6 under it. Shown with Optional connected experiences
                // on and the messaging policy allowing previews.
                readonly property var urlPreview: msg.modelData.url_preview && !msg.modelData.deleted && root.previewsShown && files.length === 0 && cards.length === 0 && !hasPics ? msg.modelData.url_preview : null
                // Cards (Adaptive Cards rendered natively; Teams' frame).
                readonly property var cards: (msg.modelData.cards || []).filter(c => root.cardKinds.indexOf(c.content_type) >= 0)
                // Teams' app link card sits 15.67 in and the bubble ends 8.67
                // under it (measured, OST TEST 168a).
                readonly property bool linkCardFirst: cards.length > 0 && cards[0].link_card === true
                // A Loop component fills the bubble (Teams: 616.7 in a 648 bubble).
                readonly property bool loopCard: cards.some(c => c.content_type === "application/vnd.microsoft.card.fluidEmbedCard")
                readonly property real cardW: loopCard ? msg.maxBubble - 2 * 15.7
                    : list.width >= 720 ? (cards.some(c => c.content_type !== "application/vnd.microsoft.card.adaptive") ? 452 : 448) : 360
                // Text shows unless the message is only a picture, only files
                // or only cards.
                readonly property bool showBody: !imageOnly && !(inFlow && !(msg.modelData.html || "").length) && (msg.modelData.deleted || ((msg.modelData.text || "").length > 0 && !(cards.length > 0 && !(msg.modelData.html || "").length)))
                // Pictures where they were written, with the text between
                // them (Teams keeps the order): [{pic} | {html}].
                readonly property var flow: msg.modelData.flow || []
                readonly property bool inFlow: flow.length > 0
                readonly property bool endsInText: inFlow && flow[flow.length - 1].html !== undefined
                readonly property real picsEnd: picsTop + picsH
                readonly property string textStyle: "<style>a { color: " + theme.link + "; text-decoration: none; } "
                    + ".mention { color: " + theme.brandForeground1 + "; } "
                    + ".mention-me { color: " + theme.mentionMe + "; font-weight: 700; } "
                    + "p, div, li, body { line-height: " + (bigEmoticons ? 50 : 20) + "px; -qt-line-height-type: fixed; } "
                    // Teams sets paragraphs with no space between them (a Channel
                    // Agent's welcome, measured 2026-11-21: <p>s 20 apart).
                    + "p { margin-top: 0px; margin-bottom: 0px; } "
                    // Measured (winpc, "OST TEST 70"): headings 18 light / 14 bold
                    // / 12 bold on 25.7 / 20 / 17.1 lines, 3 above and below;
                    // inline code Cascadia Mono in a box (CodeBoxes draws it,
                    // behind the text).
                    + "code { font-family: '" + theme.mono + "'; } "
                    + "p.h1 { font-size: 18px; font-weight: 300; line-height: 26px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; } "
                    + "p.h2 { font-size: 14px; font-weight: 700; line-height: 20px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; } "
                    + "p.h3 { font-size: 12px; font-weight: 700; line-height: 17px; -qt-line-height-type: fixed; margin-top: 3px; margin-bottom: 3px; }</style>"
                // Teams' lines are 20 px; big emoticons (50 px) set their own.
                readonly property bool bigEmoticons: (msg.modelData.html || "").indexOf("width=\"50\" height=\"50\"") >= 0
                // Bigger text, headings, rules and tables set their own heights.
                readonly property bool richBody: /line-height:|<h[123]>|<hr|<table|<ol|<ul/.test(msg.modelData.html || "")
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
                // The text, pictures and an agent's command cards end here,
                // before and after the see-more cut.
                readonly property real rawEnd: hasPics ? picsEnd : body.y + bodyH
                readonly property real odslCardsH: odslCards.shown ? odslCards.height : 0
                readonly property real textEnd: rawEnd + odslCardsH + seeExtra
                readonly property real filesTop: hasPics || showBody ? textEnd + 8 : 8
                // Measured: a card sits 8 under the bubble's top (or the text),
                // 17.3 in, and the bubble ends 10.7 under it.
                readonly property real cardsTop: botCard ? 0 : showBody ? textEnd + 8 : 8
                // A bot's suggested actions ("@agent") and its like / dislike
                // (Teams, a Channel Agent's welcome measured on winpc
                // 2026-11-21): a 31.3 row 8 under the text.
                readonly property var suggested: (msg.modelData.suggested || []).filter(a => a.kind !== "odsl")
                // Under whatever the message holds (a Channel Agent's answer
                // carries a quote and a Loop page too).
                readonly property bool hasActions: !msg.mine && !msg.modelData.deleted && !bare && !botCard
                    && (suggested.length > 0 || !!msg.modelData.feedback_loop || actionsRow.shown)
                readonly property real actionsH: hasActions ? Math.max(31.3, actionsRow.implicitHeight) + 8 : 0
                // An agent's ODSL statements (its reasoning, or Teams' note
                // that some can't be shown): 8 under the actions.
                readonly property bool hasOdsl: !msg.mine && !msg.modelData.deleted && !bare && !botCard && odslBlock.shown
                readonly property real odslH: hasOdsl ? odslBlock.height + 8 : 0
                // Where the content ends (the actions and statements follow).
                readonly property real contentEnd: cards.length > 0 ? cardsTop + cardCol.height
                    : files.length > 0 ? filesTop + fileCol.implicitHeight
                    : hasPics ? textEnd
                    : urlPreview ? textEnd + 6 + 96
                    : textEnd
                // An agent's long message (SeeMoreRules; measured on winpc
                // 2026-11-22, a Channel Agent's welcome in a threads channel):
                // its text cut at 220 under an 80 px fade with "See more"
                // over the bottom; open, "See less" 8 under the text. The
                // actions follow the box.
                readonly property real fullText: showBody ? rawEnd + odslCardsH - body.y : bodyH
                readonly property real seeLimit: root.postsLayout || !showBody ? 0 : root.seeMore.chatLimit(msg.modelData, root.threadKind, !msg.modelData.root_id || msg.modelData.root_id === msg.modelData.id)
                readonly property bool seeCut: seeLimit > 0 && fullText > seeLimit
                readonly property bool seeOpen: root.seeMoreOpen[msg.modelData.id] === true
                onFullTextChanged: if (seeLimit > 0) root.seeMoreFull[msg.modelData.id] = fullText
                readonly property real seeExtra: !seeCut ? 0 : seeOpen ? 8 + seeButton.height : seeLimit - fullText
                width: root.postsLayout ? msg.maxBubble
                    : botCard ? cardCol.width
                    : cards.length > 0 ? Math.max(cardCol.width + 2 * (linkCardFirst ? 15.67 : 17.3), showBody ? Math.min(msg.maxBubble, body.implicitWidth + 2 * pad) : 0)
                    : hasCode || odslCards.shown ? msg.maxBubble
                    : Math.min(msg.maxBubble, Math.max(urlPreview ? 460 + 2 * pad : 0, hasActions ? actionsRow.implicitWidth : 0, hasOdsl ? odslBlock.wanted : 0, msg.sharedHead ? sharedRow.implicitWidth : 0, msg.scheduledMsg ? scheduleLine.implicitWidth : 0, subjectLine.visible ? subjectLine.implicitWidth : 0, showBody ? body.implicitWidth + (msg.modelData.deleted && msg.mine ? 12 + undoMetrics.advanceWidth : 0) : 0, pics.implicitWidth, files.length > 0 ? fileCol.implicitWidth : 0, msg.modelData.quote ? quoteCard.width : 0, msg.modelData.forward ? fwdCard.width : 0) + 2 * pad)
                TextMetrics { id: undoMetrics; text: qsTr("Undo"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                height: botCard ? cardCol.height
                    : cards.length > 0 ? cardsTop + cardCol.height + (linkCardFirst ? 8.67 : 10.7) + actionsH + odslH
                    : bare && files.length === 0 ? (bigEmoticons ? bodyH : picsH)
                    : files.length > 0 ? filesTop + fileCol.implicitHeight + 8 + actionsH + odslH
                    : hasPics ? textEnd + (endsInText || (showBody && !inFlow) ? 8.6 : 8) + actionsH + odslH
                    : urlPreview ? textEnd + 6 + 96 + (root.compact ? 2 : 14.6) + actionsH + odslH
                    : root.compact ? textEnd + 2 + actionsH + odslH
                    : textEnd + 8.6 + actionsH + odslH
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
                color: msg.scheduledMsg ? theme.pick("#FAFAFA", "#1F1F1F", "#000000") : bare || (root.compact && !msg.sendFailed) ? "transparent" : msg.sendFailed ? theme.redBackground1 : root.postsLayout ? theme.surface : (msg.mine ? theme.brandTint : theme.bubble)
                border.color: msg.scheduledMsg ? theme.pick("#D1D1D1", "#666666", "#FFFFFF") : msg.sendFailed ? theme.redBorder1 : root.postsLayout ? theme.dividerSoft
                    : root.threadsLayout && root.openThreadRoot === msg.modelData.id ? theme.brand : bare || root.compact ? "transparent" : theme.transparentStroke
                x: root.compact ? 64 : msg.mine ? parent.width - root.gutR - width : root.gutContent
                Text {
                    id: scheduleLine
                    visible: msg.scheduledMsg
                    x: bubble.pad; y: 6.6 + bubble.subjectH; height: 17.1
                    verticalAlignment: Text.AlignVCenter
                    text: msg.scheduledMsg ? qsTr("Sending on %1 at %2").arg(theme.fmtDate(new Date(msg.modelData.scheduled_at), "dddd, MMM d")).arg(theme.time(new Date(msg.modelData.scheduled_at))) : ""
                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(bubble, theme.textSecondary)
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
                    color: theme.onFill(bubble, theme.text)
                    Accessible.role: Accessible.Heading
                }
                Row {
                    id: sharedRow
                    visible: !!msg.sharedHead
                    x: bubble.pad; y: 10 + bubble.subjectH
                    spacing: 4
                    FluentIcon { name: msg.sharedHead === "thread" ? "chat-multiple-20" : "channel-arrow-left-20"; size: 16; color: theme.onFill(bubble, theme.textSecondary) }
                    Text {
                        height: 16; verticalAlignment: Text.AlignVCenter
                        textFormat: Text.RichText
                        text: msg.sharedHead === "thread"
                            ? qsTr("Replied in thread: <0>%1</0>").replace("<0>", "<a href=\"thread\" style=\"text-decoration: none; color: " + theme.brandForeground1 + "\">").replace("</0>", "</a>").arg(root.escapeHtml(msg.modelData.thread_title || ""))
                            : qsTr("Also sent to channel")
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(bubble, theme.textSecondary)
                        onLinkActivated: root.openThread(msg.modelData.root_id)
                        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    }
                }
                // Several cards stack 8 apart (Teams, OST TEST 122).
                Column {
                    id: cardCol
                    visible: bubble.cards.length > 0
                    x: bubble.botCard ? 0 : bubble.linkCardFirst || bubble.loopCard ? 15.67 : 17.3; y: bubble.cardsTop
                    width: bubble.cardW
                    spacing: 8
                    Repeater {
                        model: bubble.cards
                        Loader {
                            id: cardLoader
                            required property var modelData
                            required property int index
                            sourceComponent: modelData.link_card ? linkComp
                                : modelData.content_type === "application/vnd.microsoft.card.fluidEmbedCard" ? loopComp
                                : modelData.content_type === "application/vnd.microsoft.card.adaptive" ? adaptiveComp
                                : modelData.content_type === "application/vnd.microsoft.teams.card.list" ? listComp
                                : modelData.content_type === "application/vnd.microsoft.teams.card.o365connector" ? connectorComp : heroComp
                            // A Loop component (Teams' FluidEmbedCard, measured
                            // 2026-11-20): Loop's own component in Teams' card,
                            // its file's name in the header.
                            Component {
                                id: loopComp
                                LoopCard {
                                    id: msgLoop
                                    mode: "message"
                                    width: bubble.cardW
                                    componentUrl: String((modelData.content || {}).componentUrl || "")
                                    Component.onCompleted: backend.loopHostRequest("pageName", "msgloop:" + msg.modelData.id, JSON.stringify({ url: componentUrl }))
                                    Connections {
                                        target: backend
                                        function onLoopHostReply(id, json) {
                                            if (id !== "msgloop:" + msg.modelData.id) return
                                            let r = {}
                                            try { r = JSON.parse(json) } catch (e) {}
                                            if (r.name) msgLoop.name = r.name
                                        }
                                    }
                                }
                            }
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
                            // An app's link card (Teams' app link unfurling,
                                // OST TEST 168a): the app's name and icon over
                                // its card.
                            Component {
                                id: linkComp
                                AppLinkCard {
                                    appCard: modelData
                                    width: list.width >= 720 ? 452 : 360
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
                                    id: hc
                                    readonly property string cardKey: msg.modelData.id + ":" + cardLoader.index
                                    readonly property var footerState: root.cardFooters[cardKey] || null
                                    content: modelData.content
                                    thumbnail: modelData.content_type === "application/vnd.microsoft.card.thumbnail"
                                    cardWidth: list.width >= 720 ? 452 : 360
                                    bottomExtra: footerState ? 28.67 : 0
                                    onImBack: t => root.send(t)
                                    // A messageBack button goes to the bot (Teams).
                                    onMessageBack: b => root.cardAction(msg.modelData, cardLoader.index, b, {})
                                    CardResponseBar {
                                        visible: !!hc.footerState
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        busy: !!hc.footerState && hc.footerState.busy === true
                                        text: hc.footerState ? hc.footerState.text : ""
                                        error: !!hc.footerState && hc.footerState.error === true
                                        onDismissed: root.setCardFooter(hc.cardKey, null)
                                    }
                                }
                            }
                        }
                    }
                }
                // Inline pictures, scaled to fit the bubble (as in Teams).
                // In a flow, the text between them too.
                Column {
                    id: pics
                    // In the see-more cut with the text.
                    parent: cutBox
                    x: bubble.pad; y: bubble.picsTop
                    spacing: bubble.inFlow ? 0 : 4
                    Repeater {
                        model: bubble.inFlow ? bubble.flow.map(p => p.pic !== undefined ? bubble.imgs[p.pic] : p.video !== undefined ? { flowVideo: (msg.modelData.videos || [])[p.video] || {} } : p.quote !== undefined ? { flowQuote: p.quote } : p.code ? { flowCode: p.code } : p.loop_url ? { flowLoop: p.loop_url } : { flowText: p.html }) : bubble.imgs
                        Item {
                            id: part
                            required property var modelData
                            required property int index
                            readonly property bool isText: modelData.flowText !== undefined
                            readonly property bool isQuote: modelData.flowQuote !== undefined
                            readonly property bool isCode: modelData.flowCode !== undefined
                            readonly property bool isVideo: modelData.flowVideo !== undefined
                            // A Loop link unfurled in place (an agent's Loop
                            // page): Loop's card across the text's width, 9
                            // above and 7 below (measured on winpc 2026-11-22).
                            readonly property bool isLoop: modelData.flowLoop !== undefined
                            readonly property bool isPic: !isText && !isQuote && !isCode && !isVideo && !isLoop
                            readonly property bool richText: isText && /line-height:|<h[123]>|<hr|<table/.test(modelData.flowText)
                            // Teams: a picture after text or another picture
                            // sits 4 below it (the GIF's margin); text follows
                            // a picture directly; a code card 6 under text.
                            readonly property real gap: !bubble.inFlow ? 0 : isVideo ? 2 : isPic && (index > 0 || bubble.showBody) ? 4 : isCode && (index > 0 || bubble.showBody) ? 6 : 0
                            width: isText ? flowText.width : isQuote ? quoteBox.width : isCode ? codeCard.width : isVideo ? (clipCard.item ? 2 + clipCard.item.width : 0) : isLoop ? msg.maxBubble - 2 * bubble.pad : pic.width
                            height: gap + (isText ? (richText ? flowText.contentHeight : Math.max(1, flowText.lineCount) * 20)
                                : isQuote ? 7 + quoteBox.height + 7 : isCode ? codeCard.height : isVideo ? (clipCard.item ? clipCard.item.height + 2 : 0) : isLoop ? 9 + 372 + 7 : pic.height)
                            Loader {
                                active: part.isLoop
                                y: 9
                                width: msg.maxBubble - 2 * bubble.pad
                                sourceComponent: LoopCard {
                                    id: embedLoop
                                    mode: "embed"
                                    width: msg.maxBubble - 2 * bubble.pad
                                    componentUrl: String(part.modelData.flowLoop || "")
                                    onPinRequested: backend.setMessagePinned(msg.modelData.id, true)
                                    Component.onCompleted: backend.loopHostRequest("pageName", "embedloop:" + msg.modelData.id + ":" + part.index, JSON.stringify({ url: componentUrl }))
                                    Connections {
                                        target: backend
                                        function onLoopHostReply(id, json) {
                                            if (id !== "embedloop:" + msg.modelData.id + ":" + part.index) return
                                            let r = {}
                                            try { r = JSON.parse(json) } catch (e) {}
                                            if (r.name) embedLoop.name = r.name
                                        }
                                    }
                                }
                            }
                            // A video clip (Teams' video message), its player
                            // made only for clips; Teams gives it 2 px
                            // margins (top, bottom and start).
                            Loader {
                                id: clipCard
                                x: 2; y: part.gap
                                active: part.isVideo
                                sourceComponent: VideoClipCard {
                                    clip: part.modelData.flowVideo
                                    maxWidth: msg.maxBubble - 2 * bubble.pad - 2
                                    background: bubble.bare ? root.color : bubble.color
                                    canReply: root.canRecordClips
                                    onReplyWithClip: root.replyWithVideoClip()
                                }
                            }
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
                                border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                                Rectangle { x: 3; y: 3; width: 2.67; height: parent.height - 6; radius: 1.5; color: theme.pick("#D1D1D1", "#666666", "#000000") }
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
                                    Loader {
                                        z: -1
                                        active: part.isQuote && /<code/.test(part.modelData.flowQuote)
                                        sourceComponent: CodeBoxes { edit: quoteText }
                                    }
                                }
                            }
                            // Teams' code block (CodeCard).
                            CodeCard {
                                id: codeCard
                                visible: part.isCode
                                y: part.gap
                                code: part.isCode ? part.modelData.flowCode : ({})
                                width: part.isCode ? msg.maxBubble - 2 * bubble.pad : 0
                                height: part.isCode ? implicitHeight : 0
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
                                color: theme.onFill(bubble, theme.text)
                                onLinkActivated: link => root.openLink(link)
                                HoverHandler { cursorShape: flowText.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                                Loader {
                                    z: -1
                                    active: part.isText && /<code/.test(part.modelData.flowText)
                                    sourceComponent: CodeBoxes { edit: flowText }
                                }
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
                                color: theme.hc("#CC000000", "#000000")
                                FluentIcon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; name: "play-20-filled"; size: 24; color: "white" }
                            }
                            TapHandler { enabled: pic.fun; onTapped: pic.playing = !pic.playing }
                            // A picture opens Teams' viewer on the message's pictures.
                            TapHandler {
                                enabled: !pic.fun && !!pic.modelData.local_path
                                onTapped: {
                                    const list = bubble.imgs.filter(x => !x.kind)
                                    root.openImageViewer(list, Math.max(0, list.indexOf(pic.modelData)), msg.modelData)
                                }
                            }
                            HoverHandler { enabled: !pic.fun && !!pic.modelData.local_path; cursorShape: Qt.PointingHandCursor }
                            HoverHandler { enabled: pic.fun; cursorShape: Qt.PointingHandCursor }
                            Accessible.role: pic.fun ? Accessible.Button : Accessible.Graphic
                            Accessible.name: pic.fun ? (pic.modelData.alt || "") : qsTr("Image")
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
                SuggestedActionsRow {
                    id: actionsRow
                    visible: bubble.hasActions
                    // 8 under the text, or under its see-more box (Teams
                    // keeps the actions out of the cut).
                    x: bubble.pad; y: bubble.contentEnd + 8
                    message: msg.modelData
                    host: root
                    maxWidth: msg.maxBubble - 2 * bubble.pad
                }
                OdslBlock {
                    id: odslBlock
                    visible: bubble.hasOdsl
                    x: bubble.pad; y: bubble.contentEnd + bubble.actionsH + 8
                    width: bubble.width - 2 * bubble.pad
                    message: msg.modelData
                    rules: root.seeMore
                    openReasoning: root.reasoningOpenForTest === msg.modelData.id
                }
                // An agent's long text, cut at its see-more limit (a TextEdit
                // doesn't clip its own text; this does, at the bubble's origin
                // so the text keeps its place).
                Item {
                    id: cutBox
                    width: bubble.width
                    height: bubble.seeCut && !bubble.seeOpen ? body.y + bubble.seeLimit : bubble.height
                    clip: bubble.seeCut && !bubble.seeOpen
                // An agent's command cards (a plan, tasks, questions), right
                // after the text, inside its cut (OdslCards).
                OdslCards {
                    id: odslCards
                    visible: shown && !msg.mine && !msg.modelData.deleted && !bubble.bare
                    x: bubble.pad; y: bubble.rawEnd
                    width: msg.maxBubble - 2 * bubble.pad
                    message: msg.modelData
                    host: root
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
                    text: msg.modelData.deleted ? qsTr("This message has been deleted.")
                        : bubble.textStyle + root.marked(msg.modelData.id, msg.modelData.html ? theme.messageHtml(msg.modelData.html) : msg.modelData.text)
                    textFormat: msg.modelData.deleted ? TextEdit.PlainText : TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    // Teams' tombstone: italic, in the normal text colour.
                    font.italic: msg.modelData.deleted === true
                    color: theme.onFill(bubble, theme.text)
                    onLinkActivated: link => root.openLink(link)
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    Accessible.name: msg.modelData.text
                    // Inline code's box, behind the text.
                    Loader {
                        z: -1
                        active: bubble.showBody && !msg.modelData.deleted && /<code/.test(msg.modelData.html || "")
                        sourceComponent: CodeBoxes { edit: body }
                    }
                }
                }
                // Teams' see-more for an agent's message (349533 `cs`, measured
                // on winpc 2026-11-22): cut, an 80 px fade from clear to the
                // bubble's colour at the bottom of the 220 and, over it, a
                // 39.3 box in the bubble's colour holding "See more" 8 down;
                // open, the box follows the text with "See less". The button
                // is a transparent Fluent button (96 x 31.3 at least, 14/20
                // regular brand, no side padding) whose 14 px chevron shows
                // 6 after the text on hover; Teams keeps it in place.
                Rectangle {
                    visible: bubble.seeCut && !bubble.seeOpen
                    x: bubble.pad; y: body.y + bubble.seeLimit - 80
                    width: bubble.width - 2 * bubble.pad; height: 80
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 1; color: bubble.color }
                    }
                }
                Rectangle {
                    visible: bubble.seeCut
                    x: bubble.pad
                    y: bubble.seeOpen ? body.y + bubble.fullText : body.y + bubble.seeLimit - height
                    width: bubble.width - 2 * bubble.pad; height: 8 + seeButton.height
                    color: bubble.color
                    Item {
                        id: seeButton
                        y: 8
                        width: Math.max(96, seeRow.implicitWidth); height: 31.33
                        Row {
                            id: seeRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bubble.seeOpen ? qsTr("See less", "meetingCollaboration:ka3s29all") : qsTr("See more", "meetingCollaboration:k6i9a4r05")
                                font.family: theme.font; font.pixelSize: 14
                                color: theme.onFill(bubble, theme.brand)
                            }
                            Item {
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                FluentIcon {
                                    anchors.verticalCenter: parent.verticalCenter; size: 14
                                    name: bubble.seeOpen ? "chevron-up-20" : "chevron-down-20"
                                    color: theme.onFill(bubble, theme.brand)
                                    opacity: seeHover.hovered || seeButton.activeFocus ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] } }
                                }
                            }
                        }
                        HoverHandler { id: seeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.toggleSeeMore(msg.modelData.id, seeButton) }
                        activeFocusOnTab: true
                        Keys.onSpacePressed: root.toggleSeeMore(msg.modelData.id, seeButton)
                        Keys.onReturnPressed: root.toggleSeeMore(msg.modelData.id, seeButton)
                        Accessible.role: Accessible.Button
                        Accessible.name: bubble.seeOpen ? qsTr("See less", "meetingCollaboration:ka3s29all") : qsTr("See more", "meetingCollaboration:k6i9a4r05")
                        Accessible.onPressAction: root.toggleSeeMore(msg.modelData.id, seeButton)
                    }
                }
                // Undo, 12 px after the tombstone text (14 px semibold brand), for
                // your own message deleted in this session; never for Urgent
                // (Teams 4584).
                Text {
                    visible: msg.modelData.deleted === true && msg.mine && msg.modelData.importance !== "urgent"
                    x: body.x + body.contentWidth + 12; y: body.y
                    text: qsTr("Undo")
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.onFill(bubble, theme.brandLink)
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.undoDeleteMessage(msg.modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Undo")
                }
                UrlPreviewCard {
                    visible: !!bubble.urlPreview
                    x: bubble.pad; y: bubble.showBody ? body.y + bubble.bodyH + 6 : 8
                    preview: bubble.urlPreview
                    clickable: true
                    removable: msg.mine
                    onRemoveRequested: backend.removeUrlPreview(JSON.stringify(msg.modelData))
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
                                border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
                                border.width: 0.67
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 4 }
                                Image {
                                    x: 11.2; y: 7.1; width: 38; height: 38
                                    source: fc.linked ? fc.linked.icon : ""
                                    sourceSize: Qt.size(76, 76)
                                    RoundedCorners { anchors.fill: parent; radius: 4; background: theme.surface }
                                }
                                // A website tab's card ends with the Open glyph (it
                                // opens in the browser; seen on winpc 2026-11-16).
                                FluentIcon {
                                    id: tabCardOpen
                                    visible: !!fc.linked && !!fc.linked.opens_in_browser
                                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                    name: "open-20"; size: 20; color: theme.textStrong
                                }
                                Text {
                                    x: 60.7; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 60.7 - (tabCardOpen.visible ? 44 : 8)
                                    elide: Text.ElideRight
                                    text: fc.modelData.name
                                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                                HoverHandler { id: tabLinkHover; enabled: fc.tabLink; cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: fc.tabLink; onTapped: { const i = fc.linked && !root.pane ? root.tabNames.indexOf(fc.linked.name) : -1; if (i > 0) root.openTabAt(i); else root.openLinkedTab(fc.modelData.item_id) } }
                                ToolTip.visible: fc.tabLink && tabLinkHover.hovered
                                ToolTip.delay: 500
                                ToolTip.text: fc.modelData.name
                                Accessible.role: Accessible.Link
                                Accessible.name: qsTr("Tab %1").arg(fc.modelData.name)
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
                Accessible.name: qsTr("You were mentioned.")
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
                    // Teams' reply summary divider (messages_replySummary*).
                    text: msg.repliesCount === 1 ? qsTr("%1 reply", "messaging:kdmfi556l").arg(msg.repliesCount) : qsTr("%1 replies", "messaging:k7ju1u9nn").arg(msg.repliesCount)
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
                    text: qsTr("%n replies", "messaging:k5c0r4z0x_mf", msg.modelData.thread_replies || 0)
                    // Bold while the thread has unread replies (Teams).
                    font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
                    font.weight: (msg.modelData.thread_unread || 0) > 0 ? Font.Bold : Font.Normal
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openThread(msg.modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1, open thread").arg(text)
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Last reply %1").arg(root.stamp(msg.modelData.thread_last)); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            }
            HoverBar {
                id: actions
                readonly property bool can: !msg.isRow && !msg.modelData.deleted && !msg.sendPending && !msg.sendFailed && !msg.editingThis
                host: msgHost
                message: msg.modelData
                // A reply also sent to the channel: Reply in thread (its
                // thread), no Edit (Teams).
                acts: msg.scheduledMsg ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }] : (root.threadsLayout ? [{ key: "thread", icon: "chat-multiple-20", tip: qsTr("Reply in thread") }] : []).concat(msg.sharedHead === "thread" ? [] : msg.mine
                    ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }]
                    : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }])
                onThreadRequested: m => root.openThread(m.root_id || m.id)
                onKeyboardDone: root.focusCompose()
                onActiveFocusChanged: if (!activeFocus && root.forceBarId === msg.modelData.id) root.forceBarId = ""
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
                Accessible.name: msg.modelData.importance === "urgent" ? qsTr("Urgent message.", "messaging:kdf8pu9nr") : qsTr("Important badge")
            }
            // Sent tick on your newest message, "Seen" eye on the newest one
            // the other person has read.
            // Pending messages show the Circle ("Sending..." / "Retrying..."),
            // failed ones the red warning ("Failed"); each icon has Teams'
            // tooltip.
            FluentIcon {
                id: statusIcon
                readonly property bool seen: msg.modelData.latestSeen === true
                readonly property string tip: msg.scheduledMsg ? qsTr("Scheduled") : msg.sendPending ? (msg.modelData.send_note || "")
                    : msg.sendFailed ? qsTr("Failed")
                    : seen ? (root.isGroup ? qsTr("Seen by everyone") : qsTr("Seen")) : qsTr("Sent")
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
                        { key: "retry", icon: "arrow-clockwise-16", tip: qsTr("Retry"), name: qsTr("Retry"), show: msg.modelData.can_retry === true },
                        { key: "delete", icon: "delete-16", tip: qsTr("Delete"), name: qsTr("Delete this message"), show: true }
                    ].filter(b => b.show)
                    Rectangle {
                        id: failBtn
                        required property var modelData
                        width: 24; height: 24; radius: 4
                        color: failHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon {
                            anchors.centerIn: parent; size: 16; name: failBtn.modelData.icon
                            color: theme.onFill(failBtn, failBtn.modelData.key === "delete" ? theme.redForeground1 : theme.textStrong)
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
    // What Teams shows for the set (701487 `E6`/`W`/`Zw`, 79624 `vr`): text
    // replies for the newest message (someone else's); in a 1:1, a file or
    // meeting suggestion for one of the newest three (no file suggestion
    // when you shared a file among them); a workflow suggestion only for
    // the person it's for, on the newest message. Edited messages keep only
    // suggestions made after the edit.
    readonly property var smartReplyItems: {
        const set = root.smartReplies
        if (!set || !root.smartRepliesOn || root.isChannel || root.pane) return { special: [], text: [], feedback: false }
        const msgs = root.messages.filter(m => m.kind === "message")
        const newest = msgs[msgs.length - 1]
        if (!newest) return { special: [], text: [], feedback: false }
        const top3 = msgs.slice(-3)
        const oneOnOne = !root.isGroup && !String(root.chatId).startsWith("48:")
        const fresh = (r, m) => !!m && !m.mine && !m.deleted && !(m.edited && m.edit_ms && m.edit_ms > Date.parse(r.time))
        const forNewest = r => r.target === newest.id && fresh(r, newest)
        const forTop3 = r => fresh(r, top3.find(m => m.id === r.target))
        const text = set.replies.filter(r => r.kind === "reply" && forNewest(r)).slice(0, 3)
        let special = []
        const files = set.replies.filter(r => r.kind === "file_sharing")
        const meetings = set.replies.filter(r => r.kind === "meeting")
        const workflows = set.replies.filter(r => r.kind === "workflow")
        if (files.length) {
            if (oneOnOne && forTop3(files[0]) && !top3.some(m => m.mine && (m.files || []).length > 0)) special = [files[0]]
        } else if (workflows.length) {
            const w = workflows.find(r => r.target === newest.id)
            let v = null
            try { v = w ? JSON.parse(w.value) : null } catch (e) {}
            if (v && v.toolExecutorName === backend.userName && ["schedule_meeting", "create_planner_task", "remind_me"].indexOf(v.recommendedToolName) >= 0)
                special = [Object.assign({}, w, { workflow: v })]
        } else if (meetings.length) {
            special = meetings.filter(r => oneOnOne ? forTop3(r) : forNewest(r))
        }
        return { special: special, text: text, feedback: set.feedback === true && (special.length + text.length) > 0 }
    }
    readonly property bool smartRepliesShown: smartReplyRow.visible
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
    // A suggestion chip (Teams' small Fluent button with the cardButton and
    // smartAction styles): 24 tall, radius 4, a 1 px BrandForeground1 edge,
    // 12/600 brand text, padding 0 14, 4 either side; a 20 px icon 4 before
    // the text on the file, meeting and workflow chips.
    component SuggestionChip: Item {
        id: chipItem
        property string label
        property string icon: ""
        property string iconSource: ""
        property string tip: ""
        signal clicked()
        width: chipRow.implicitWidth + 28 + 8; height: 24
        Rectangle {
            id: hcFill7
            x: 4; width: parent.width - 8; height: 24; radius: 4
            color: chipTap.pressed ? theme.pick("#E8EBFA", "#2B2B40", "#1AEBFF") : chipHover.hovered ? theme.pick("#EBEBEB", "#383838", "#1AEBFF") : theme.surface
            border.width: 1
            border.color: chipHover.hovered || chipTap.pressed ? theme.brandHover : theme.brand
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 4
                FluentIcon {
                    visible: chipItem.icon.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    name: chipItem.icon; size: 20
                    color: theme.onFill(hcFill7, chipHover.hovered || chipTap.pressed ? theme.brandHover : theme.brand)
                }
                Image {
                    visible: chipItem.iconSource.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    source: chipItem.iconSource
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chipItem.label
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill7, chipHover.hovered || chipTap.pressed ? theme.brandHover : theme.brand)
                }
            }
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: chipTap; onTapped: chipItem.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: chipItem.label
        }
        ToolTip {
            visible: chipHover.hovered && chipItem.tip.length > 0; delay: 500
            y: -height - 4; padding: 0
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text {
                leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                text: chipItem.tip; font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
        }
    }
    Row {
        id: smartReplyRow
        visible: (root.smartReplyItems.special.length + root.smartReplyItems.text.length) > 0 && compose.visible && root.typingText.length === 0
        anchors.right: compose.right
        y: compose.y - 8 - height
        height: 24
        Accessible.role: Accessible.ToolBar
        Accessible.name: qsTr("Suggested reply")
        Repeater {
            model: root.smartReplyItems.special
            SuggestionChip {
                id: special
                required property var modelData
                readonly property var wf: modelData.workflow || null
                label: modelData.kind === "file_sharing" ? qsTr("Share a file")
                    : wf ? (wf.recommendedToolName === "schedule_meeting" ? qsTr("Would you like to schedule a meeting?")
                        : wf.recommendedToolName === "create_planner_task" ? qsTr("Would you like to create a Planner task?") : qsTr("Would you like a reminder to follow up?"))
                    : modelData.value
                icon: modelData.kind === "file_sharing" ? "document-20" : modelData.kind === "meeting" ? "calendar-add-20" : ""
                iconSource: wf ? backend.cardImage("https://res.cdn.office.net/teamsappdata/app-assets/ring0/c3a1996d-db0f-4857-a6ea-7aabf0266b00/c3a1996d-db0f-4857-a6ea-7aabf0266b00_largeImage.png?v=2.1.5") : ""
                tip: wf ? ((wf.prefilledInputs || {}).title || (wf.prefilledInputs || {}).message || "") : ""
                onClicked: root.smartSuggestionClicked(modelData, special)
            }
        }
        Repeater {
            model: root.smartReplyItems.text
            SuggestionChip {
                required property var modelData
                label: modelData.title
                onClicked: { root.send(modelData.value); root.smartReplies = null }
            }
        }
        // Teams' suggested-reply feedback (sr-feedback-trigger): a 24 px
        // transparent icon button, LightbulbFilament, its tooltip
        // "Suggested reply feedback", opening the feedback form above it.
        Item {
            id: srFeedback
            visible: root.smartReplyItems.feedback
            width: 24; height: 24
            Rectangle {
                anchors.fill: parent; radius: 4
                color: fbHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "transparent") : "transparent"
                FluentIcon {
                    anchors.centerIn: parent
                    name: fbHover.hovered || srFeedbackForm.opened ? "lightbulb-filament-20-filled" : "lightbulb-filament-20"; size: 20
                    color: fbHover.hovered || srFeedbackForm.opened ? theme.brandHover : theme.textStrong
                }
            }
            HoverHandler { id: fbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: srFeedbackForm.opened ? srFeedbackForm.close() : srFeedbackForm.openFor(srFeedback) }
            ToolTip {
                visible: fbHover.hovered && !srFeedbackForm.opened; delay: 500
                y: -height - 4; x: parent.width - width; padding: 0
                background: FluentSurface { depth: 16; radius: 4 }
                contentItem: Text {
                    leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                    text: qsTr("Suggested reply feedback"); font.family: theme.font; font.pixelSize: 12; color: theme.text
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Suggested reply feedback")
        }
    }
    SmartReplyFeedback {
        id: srFeedbackForm
        kinds: root.smartReplies ? root.smartReplies.replies.map(r => r.kind).filter((k, i, a) => a.indexOf(k) === i) : []
        onSubmitted: (categories, comment, attach) => {
            const set = root.smartReplies || { replies: [] }
            const m = root.newestMessage
            let r = {}
            try { r = JSON.parse(backend.smartReplyFeedbackUrl(JSON.stringify({ categories: categories, comment: comment, kinds: kinds,
                attach: attach, suggestions: set.replies.map(r => r.title || r.value), last_message: m ? (m.html || m.text || "") : "" }))) } catch (e) {}
            if (r.url) backend.openExternal(r.url)
            // The details (and your message, when attached) stay on this
            // device in a file you review and drop in yourself.
            if (r.folder) backend.openLocalPath(r.folder)
            root.toastRequested({ text: qsTr("Finish on GitHub: review the details in the folder that opened, drop them in if you want, and select Create.") })
        }
    }
    /// A file, meeting or workflow suggestion was chosen (Teams' To / Mo / Us).
    signal scheduleMeetingWith(string attendees, string startIso, string endIso)
    function smartSuggestionClicked(r, chip) {
        if (r.kind === "file_sharing") {
            // Teams: the attach menu, above the chip at its end.
            root.openAttach(chip, true)
        } else if (r.kind === "meeting") {
            const members = root.chatMembers
            root.scheduleMeetingWith(members.filter(p => !p.me && p.mail).map(p => p.mail).join(", "), r.start_time || "", r.end_time || "")
        } else if (r.workflow) {
            // Teams' Workflows dialog for the suggested action (chat-app
            // 139267: launchTaskModule with the Workflows template, 800 x
            // 600, the prefilled inputs as the launch's subEntityId).
            const pages = { schedule_meeting: "findmeetingtime", create_planner_task: "createaplanner", remind_me: "remindme" }
            const page = pages[r.workflow.recommendedToolName]
            if (page) root.openWorkflowDialog(page, r.workflow.prefilledInputs)
        }
    }
    // Installed apps' compose actions from "+" (api::compose_apps): a
    // search command opens Teams' panel, an action its task module (the
    // app's fetchTask answer or the command's own taskInfo), whose submit
    // goes back as submitAction; the app's cards go into the box (Teams'
    // InputExtension card), its messages show as a toast.
    ComposeAppPanel {
        id: appPanel
        conversation: root.chatId
        onCommandPicked: c => root.runComposeCommand(appPanel.app, c, appPanel.anchorItem)
        onResultPicked: a => root.insertAppAttachment(appPanel.app, a)
    }
    property var appTask: null
    function runComposeCommand(app, cmd, anchor) {
        console.info("COMPOSEAPP command", app.name, cmd ? cmd.id + " " + cmd.type : "(list)")
        if (!cmd || cmd.type === "query") { appPanel.openFor(app, cmd, anchor); return }
        root.appTask = { app: app, cmd: cmd }
        if (cmd.fetchTask) backend.composeAppRequest("invoke", "compose-app-task", JSON.stringify({ bot: app.botId, appId: app.id, kind: "fetchTask", command: cmd.id, args: {}, conversation: root.chatId }))
        else if (cmd.taskInfo && cmd.taskInfo.url) root.openAppTask(app, cmd, cmd.taskInfo)
    }
    function insertAppAttachment(app, a) {
        if (!a || !a.contentType) return
        compose.appCard = { url: "", app_id: String(app.id), app_name: String(app.name || ""), app_icon: String(app.icon || ""), content_type: a.contentType, content: a.content || {}, anonymous: false, fromApp: true }
        compose.focusEditor()
    }
    function appAnswer(json) {
        let r = {}
        try { r = JSON.parse(json) } catch (e) {}
        const t = root.appTask
        if (!t) return
        console.info("COMPOSEAPP answer", JSON.stringify(Object.keys(r)), r.task ? r.task.type : "", r.composeExtension ? r.composeExtension.type : "")
        if (r.error || r.errorCode) { root.toastRequested({ text: qsTr("Unable to reach app. Please try again.") }); return }
        if (r.task && r.task.type === "continue" && r.task.value) { root.openAppTask(t.app, t.cmd, r.task.value); return }
        if (r.task && r.task.type === "message") { root.toastRequested({ text: String(r.task.value || "") }); return }
        const ce = r.composeExtension
        if (ce && ce.type === "message" && ce.text) { root.toastRequested({ text: String(ce.text) }); return }
        if (ce && (ce.type === "result" || ce.type === "botMessagePreview")) {
            const a = ce.type === "botMessagePreview" ? ((ce.activityPreview || {}).attachments || [])[0] : (ce.attachments || [])[0]
            root.insertAppAttachment(t.app, a)
        }
    }
    Connections {
        target: backend
        function onComposeAppReply(id, json) {
            if (id === "compose-app-task" || id === "compose-app-submit") root.appAnswer(json)
        }
    }
    function openAppTask(app, cmd, info) {
        const c = Qt.createComponent("TaskModuleDialog.qml")
        if (c.status !== Component.Ready) { console.warn("app task", c.errorString()); return }
        const d = c.createObject(root, { appId: String(app.id), appName: String(app.name || ""), appIcon: String(app.icon || ""), taskInfo: info, hostThread: root.chatId })
        d.finished.connect((callId, error, result) => {
            console.info("COMPOSEAPP task closed", error ? String(error) : "submitted")
            if (!error && result !== undefined && result !== null)
                backend.composeAppRequest("invoke", "compose-app-submit", JSON.stringify({ bot: app.botId, appId: app.id, kind: "submitAction", command: cmd.id, args: { data: result }, conversation: root.chatId }))
            Qt.callLater(() => d.destroy())
        })
        root.appTaskDialog = d
        d.open()
    }
    property var appTaskDialog: null
    function composeAppsForTest() { return { apps: compose.composeApps, panel: appPanel, task: root.appTaskDialog } }
    property var workflowDialog: null
    function openWorkflowDialog(page, prefilled) {
        const c = Qt.createComponent("TaskModuleDialog.qml")
        if (c.status !== Component.Ready) { console.warn("workflow dialog", c.errorString()); return }
        const d = c.createObject(root, {
            appId: "25b07509-bc6a-4a53-b683-9beb24e55570", appName: "Workflows",
            appIcon: "https://res.cdn.office.net/teamsappdata/app-assets/ring0/c3a1996d-db0f-4857-a6ea-7aabf0266b00/c3a1996d-db0f-4857-a6ea-7aabf0266b00_largeImage.png?v=2.1.5",
            taskInfo: { width: 800, height: 600,
                        url: "https://automations.teams.cloud.microsoft/webapps/workflows/prod/suggestedAction/" + page + "?theme={theme}&locale={locale}&ringId={ringId}" },
            hostThread: root.chatId,
            // Teams' launch input (chat-app 142420): Microsoft-owned, with
            // its own valid domains, which its NAA broker trusts.
            microsoftOwned: true,
            validDomains: ["automations.teams.cloud.microsoft", "flow.microsoft.com", "preview.flow.microsoft.com", "*.consent.azure-apihub.net",
                           "*.consent.azure-apim.net", "make.powerautomate.com", "make.preview.powerautomate.com", "make.preprod.powerautomate.com",
                           "make.gov.powerautomate.us", "make.high.powerautomate.us", "make.powerautomate.appsplatform.us"],
            hostContext: Object.assign({ chatId: root.chatId }, prefilled ? { subEntityId: JSON.stringify(prefilled) } : {}) })
        d.finished.connect(() => { if (root.workflowDialog === d) root.workflowDialog = null; Qt.callLater(() => d.destroy()) })
        root.workflowDialog = d
        d.open()
    }
    function smartRepliesForTest() { return { set: root.smartReplies, chips: root.smartReplyItems.text.map(c => c.title), special: root.smartReplyItems.special.map(c => c.kind + ":" + (c.title || c.value)), feedback: root.smartReplyItems.feedback, shown: smartReplyRow.visible } }
    function smartReplyFeedbackForTest() { return srFeedbackForm }
    function setSmartRepliesForTest(set) { root.smartReplies = set }
    function closeAttachForTest() { cloudAttach.closeMenu() }
    /// Click the first suggestion chip of this kind; its label, or "".
    function clickSuggestionForTest(kind) {
        for (let i = 0; i < smartReplyRow.children.length; i++) {
            const c = smartReplyRow.children[i]
            if (c.modelData && c.modelData.kind === kind && c.visible) { root.smartSuggestionClicked(c.modelData, c); return c.label }
        }
        return ""
    }
    function smartReplyFeedbackButtonForTest() { return srFeedback }

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
                        color: theme.hc("#C8C6C4", "#000000")
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
        movedItems: root.contextInline < 2 && root.threadsButton ? [{ key: "details", label: qsTr("Open channel details"), icon: "panel-right-expand-20", keys: "Alt+P" }] : []
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
            FluentIcon { anchors.centerIn: parent; name: "arrow-minimize-20-filled"; size: 20; color: theme.onFill(collapseButton, theme.text) }
            HoverHandler { id: collapseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.tabExpanded = false }
            ToolTip.visible: collapseHover.hovered
            ToolTip.delay: 500
            ToolTip.text: qsTr("Collapse tab")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Collapse tab")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    // Open tab in new window: the tab in a window of its own.
    Component { id: tabWindowComponent; TabWindow {} }
    function popOutTab(t) {
        const w = tabWindowComponent.createObject(null, { tab: t, teamId: root.teamId, channelId: root.chatId, teamName: root.teamName, channelName: root.chatName, teamThread: root.teamThread })
        w.closing.connect(() => w.destroy())
        w.show()
        return w
    }
    // Reload tab: Teams renders the tab again (its own state goes).
    function reloadTabView(t) {
        if (t.kind === "StaticExtension") channelFiles.reset()
        else if (t.kind === "ChannelPage" && webTabLoader.item) webTabLoader.item.reload()
        else if (hostedTabLoader.item && hostedTabLoader.shown && hostedTabLoader.shown.id === t.id) hostedTabLoader.item.reload()
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
                Text { text: qsTr("Files"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.files.length === 0
                    text: qsTr("Start sharing files in this chat, and they will appear here")
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.files
                    Rectangle {
                        id: hcFill8
                        required property var modelData
                        width: sharedCol.width; height: 52; radius: theme.radius
                        color: sfh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 32; color: theme.onFill(hcFill8, theme.textSecondary) }
                        Column {
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill8, theme.text) }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill8, theme.textSecondary) }
                        }
                        Rectangle {
                            id: hcFill9
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: sdh.hovered ? theme.selected : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "download-20"; size: 20; color: theme.onFill(hcFill9, theme.textStrong) }
                            HoverHandler { id: sdh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.downloadFile(JSON.stringify(parent.parent.modelData)) }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Download %1").arg(parent.modelData.name)
                        }
                        HoverHandler { id: sfh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openFile(modelData.share_url || modelData.object_url, modelData.name, "") }
                    }
                }
                Item { width: 1; height: 16 }
                Text { text: qsTr("Links"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.links.length === 0
                    text: qsTr("Start sharing links in this chat, and they will appear here")
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.links
                    Rectangle {
                        id: hcFill10
                        required property var modelData
                        width: sharedCol.width; height: 44; radius: theme.radius
                        color: slh.hovered ? theme.rowHover : "transparent"
                        Column {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24
                            Text { width: parent.width; text: parent.parent.modelData.url; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill10, theme.brand) }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill10, theme.textSecondary) }
                        }
                        HoverHandler { id: slh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openExternal(modelData.url) }
                    }
                }
            }
        }
    }
    // A channel's Page: Teams' header and the page in Loop's own page
    // container (one per tab; a New page OST just added makes its page).
    function pageTabForTest() { return webTabLoader.item }
    Loader {
        id: webTabLoader
        readonly property string key: root.webTab ? root.chatId + "|" + root.webTab.id : ""
        property var shown: null
        onKeyChanged: { active = false; shown = root.webTab; active = !!key }
        active: false
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: ChannelPageTab {
            tab: webTabLoader.shown
            channel: root.chatId
            location: root.chatName + (root.teamName ? " · " + root.teamName : "")
            // A Page tab without a page: Teams makes it (yours, or one with
            // no maker named).
            create: !!webTabLoader.shown && !webTabLoader.shown.content_url
                    && (root.newPageTabs.indexOf(webTabLoader.shown.id) >= 0 || !webTabLoader.shown.creator || webTabLoader.shown.creator === backend.userMri)
            onPageCreated: root.reloadTabs()
        }
    }
    // A channel's app tab (Notes, other apps' tabs): the app's own page,
    // framed and answered as Teams hosts it (OST's TeamsJS host,
    // docs/spec/app-host.md), filling the tab under the channel's header.
    // A chat's own app tabs (another app added with "+") too.
    readonly property var hostedTab: channelTabs.find(t => t.name === tab && (t.kind === "Extension" || t.kind === "OneNote") && !!t.content_template) || null
    function reloadTabs() { if (isChannel) backend.channelTabsLoad(teamId, chatId, chatName); else backend.chatTabsLoad(chatId) }
    function hostedTabForTest() { return hostedTabLoader.item }
    function messageHostForTest() { return msgHost }
    Loader {
        id: hostedTabLoader
        // One host per tab: a new one when the channel or the tab changes.
        readonly property string key: root.hostedTab ? root.chatId + "|" + root.hostedTab.id + "|" + root.tabRevision : ""
        property var shown: null
        onKeyChanged: { active = false; shown = root.hostedTab; active = !!key }
        active: false
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: WebApp {
            showHeader: false; teamsHost: true
            appName: hostedTabLoader.shown.name; appId: hostedTabLoader.shown.app_id
            hostContext: ({ entityId: hostedTabLoader.shown.entity_id, subEntityId: "" })
            hostThread: root.chatId; hostTeamThread: root.teamThread; hostTabId: hostedTabLoader.shown.id
            location: root.chatName + (root.teamName ? " · " + root.teamName : "")
            homeTemplate: hostedTabLoader.shown.content_template
            // The app set its tab up (Notes, once its section is made):
            // read the channel's tabs again, as Teams' list updates.
            // (Its page may rename it, e.g. Lists: the tab stays open under
            // its new name, as in Teams.)
            onHostEvent: (name, json) => { if (name === "tabSaved") { root.pendingOpenTab = hostedTabLoader.shown ? hostedTabLoader.shown.id : ""; root.reloadTabs() } }
        }
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
    // A meeting chat's Breakout Rooms tab (native, as Teams draws it).
    function breakoutTabForTest() { return breakoutTabLoader.item }
    Loader {
        id: breakoutTabLoader
        active: root.isMeetingChat && root.tab === "Breakout Rooms" && !!root.meeting
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: BreakoutTab { thread: root.chatId; organizer: root.meeting ? root.meeting.organizer_id : "" }
    }
    // Q&A (Viva Engage's meeting Q&A) and Meeting Whiteboard: the pages
    // Teams embeds there, filling the tab (hwc-iframe), signed in with
    // OST's web profile.
    function meetingAppTabForTest() { return qnaTabLoader.item || whiteboardTabLoader.item }
    Loader {
        id: qnaTabLoader
        property string url: ""
        active: root.isMeetingChat && root.tab === "Q&A"
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        onActiveChanged: if (active && !url) url = root.qnaUrl()
        sourceComponent: WebApp { showHeader: false; appName: "Q&A"; appId: "5db56dd0-534d-467b-aeda-d622bee2574a"; location: root.chatName; home: qnaTabLoader.url
            teamsHost: true; deepNaa: false; hostThread: root.chatId; hostContext: ({ entityId: "", subEntityId: "" }) }
    }
    Loader {
        id: whiteboardTabLoader
        property string url: ""
        active: root.isMeetingChat && root.tab === "Meeting Whiteboard"
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        onActiveChanged: if (active && !url) url = root.whiteboardUrl()
        sourceComponent: WebApp { showHeader: false; appName: "Whiteboard"; appId: "95de633a-083e-42f5-b444-a4295d8e9314"; location: root.chatName; home: whiteboardTabLoader.url
            teamsHost: true; deepNaa: false; frameContext: "meetingStage"; hostThread: root.chatId; hostContext: ({ entityId: "", subEntityId: "" })
            // The meeting's own board (Teams' fluidboard), with Teams'
            // parameters; Whiteboard's changeWhiteboardUrl is kept for it.
            meetingBoard: root.meeting ? { organizer: root.meeting.organizer_id || "", title: root.chatName, params: {
                tabStart: Date.now(), correlation: root.newGuid(), initiator: root.meeting.organizer_id === root.myOid, meetingId: root.meetingIdB64,
                user: root.myOid, tenant: backend.tenantId() || "" } } : null }
    }
    // The built-in chat tabs (docs/spec/chat-tabs.md). Notes: the chat's
    // Loop page under Teams' own header; Recap: drawn by Teams; Storyline:
    // Viva Engage's page, which Teams embeds (hwc-iframe), for the person
    // you chat with (your own in your notes chat).
    readonly property bool builtInTab: !root.isChannel && !root.webTab && !root.channelTabs.some(t => t.name === root.tab)
    function notesTabForTest() { return notesTabLoader.item }
    function recapTabForTest() { return recapTabLoader.item }
    function storylineTabForTest() { return storylineTabLoader.item }
    Loader {
        id: notesTabLoader
        active: root.builtInTab && root.tab === "Notes" && !root.isMeetingChat
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: ChatNotesTab { chat: root.chatId; location: root.chatName }
    }
    Loader {
        id: recapTabLoader
        active: root.builtInTab && root.tab === "Recap"
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        sourceComponent: RecapTab {
            meeting: root.isMeetingChat
            hasAttendance: root.hasAttendanceReport
            onOpenAttendance: root.openAttendance("")
        }
    }
    // The person whose storyline it is: the other one in a 1:1 chat
    // (19:{oid}_{oid}@unq.gbl.spaces), you in your notes chat.
    readonly property string storylineOid: isSelf ? myOid
        : chatId.endsWith("@unq.gbl.spaces") ? (chatId.slice(3, -"@unq.gbl.spaces".length).split("_").find(o => o !== myOid) || "") : ""
    function storylineUrl() {
        return "https://engage.cloud.microsoft/teams-branded-exp/officeusers/" + storylineOid
            + "/storyline?hostappname=TeamsModern&appsessionid=" + newGuid()
    }
    Loader {
        id: storylineTabLoader
        property string url: ""
        property string forOid: ""
        active: root.builtInTab && root.tab === "Storyline" && !!root.storylineOid
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        onActiveChanged: if (active && (!url || forOid !== root.storylineOid)) { forOid = root.storylineOid; url = root.storylineUrl() }
        sourceComponent: WebApp { showHeader: false; appName: "Storyline"; appId: "683f3525-d193-4a67-8d91-22093beab1ca"; location: root.chatName; home: storylineTabLoader.url
            teamsHost: true; hostThread: root.chatId; hostContext: ({ entityId: "storyline", subEntityId: "" }) }
    }

    // A channel tab's menu, exactly as Teams builds it (the backend gives
    // each tab its chevron menu and right-click menu; docs/spec/channel-tabs.md).
    MenuPopup {
        id: tabMenu
        property var tab: null
        property var entries: []
        readonly property var icons: ({
            popOut: "window-new-20", expandTab: "arrow-maximize-20", reloadTab: "arrow-clockwise-20",
            goToWebsite: "globe-20", copyLink: "link-20", renameTab: "edit-20", updateTab: "settings-20",
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
        else if (key === "goToWebsite") { if (t.website_url) backend.openExternal(t.website_url) }
        else if (key === "renameTab") renameDialog.start(t)
        else if (key === "updateTab") root.updateTabRequested(t)
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
                        id: hcFill11
                        width: 96; height: 31.3; radius: 4
                        color: aboutHover.hovered ? theme.menuHover : "transparent"
                        Text { anchors.centerIn: parent; text: qsTr("About"); font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill11, theme.brandLink) }
                        HoverHandler { id: aboutHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.tabAction("aboutTab", renameDialog.visible ? renameDialog.tab : removeDialog.tab) }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("About")
                    }
                    Rectangle {
                        id: hcFill12
                        width: 32; height: 31.3; radius: 4
                        color: closeHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill12, theme.textStrong) }
                        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: td.close() }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close %1").arg(td.title)
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
        Text { anchors.centerIn: parent; text: pb.label; color: theme.onFill(pb, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
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
            if (t === "") return qsTr("Name is required")
            if (v.length > 128) return qsTr("Tab name cannot exceed %1 characters.").arg(128)
            const others = root.channelTabs.filter(x => tab && x.id !== tab.id).map(x => x.name.trim().toLowerCase())
            if (others.indexOf(t.toLowerCase()) >= 0) return qsTr("You already have a tab with that name. Try a different one.")
            return ""
        }
        title: qsTr("Rename %1").arg(tab ? tab.name : "")
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
            Text { text: qsTr("Tab name"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Text { anchors.right: parent.right; text: renameDialog.error; font.family: theme.font; font.pixelSize: theme.base; color: theme.danger; Accessible.role: Accessible.AlertMessage }
        }
        Item { width: 1; height: 10 }
        Rectangle {
            width: parent.width; height: 32; radius: 4; color: theme.inputFilled; border.color: theme.transparentStroke
            TextInput {
                id: renameField
                x: 12; width: parent.width - 12 - 40; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                selectByMouse: true
                Keys.onReturnPressed: renameDialog.save()
                Keys.onEnterPressed: renameDialog.save()
                Accessible.name: qsTr("Tab name")
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
            PrimaryButton { anchors.right: parent.right; label: qsTr("Save"); enabled: !renameDialog.error && !renameDialog.saving; onClicked: renameDialog.save() }
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
        title: page ? qsTr("Want to remove this page?") : qsTr("Want to remove this tab?")
        function start(t) { tab = t; removing = false; failure = ""; open() }
        Item { width: 1; height: 20 }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: removeDialog.page ? qsTr("The page will be removed, not deleted. You can still access it from Microsoft Loop.")
                : qsTr("The %1 tab will be permanently removed.").arg(removeDialog.tab ? removeDialog.tab.name : "")
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
                label: removeDialog.removing ? qsTr("Removing") : qsTr("Remove")
                enabled: !removeDialog.removing
                onClicked: { removeDialog.removing = true; backend.channelTabChange("remove", root.teamId, root.chatId, removeDialog.tab.id, "") }
            }
        }
    }
    // About this tab (Teams' About dialog).
    TabAboutDialog { id: aboutDialog }
    // A channel's Existing page (Teams' Add an existing page).
    ExistingPageDialog { id: existingPageDialog; onNewPage: root.addTabChoice("newPage") }
    function existingPageDialogForTest() { return existingPageDialog }
    // A tab change's outcome: close its dialog, or show Teams' failure text.
    Connections {
        target: backend
        function onChannelTabResultChanged() {
            const r = JSON.parse(backend.channelTabResult || "{}")
            if (r.op === "rename" && renameDialog.tab && r.tab === renameDialog.tab.id) {
                if (r.ok) { if (root.tab === renameDialog.tab.name) root.tab = renameField.text.trim(); renameDialog.close() }
                else { renameDialog.saving = false; renameDialog.failure = qsTr("Unable to save %1 tab configuration.").arg(renameDialog.tab.name) }
            } else if (r.op === "add" && r.ok && r.conversation === root.chatId && r.tab && root.visible) {
                // A New page's tab: its page is made when it opens.
                if (root.pendingNewPage) { root.newPageTabs = root.newPageTabs.concat([r.tab]); root.pendingNewPage = false }
                root.pendingOpenTab = r.tab
            } else if (r.op === "remove" && removeDialog.tab && r.tab === removeDialog.tab.id) {
                if (r.ok) { if (root.tab === removeDialog.tab.name) root.tab = ""; removeDialog.close() }
                else { removeDialog.removing = false; removeDialog.failure = qsTr("We couldn't remove your tab. Please try later.") }
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
        Text { id: dbText; anchors.centerIn: parent; text: db.label; color: theme.onFill(db, db.primary ? "white" : theme.text); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
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
    function tabMenuShowForTest(name) {
        const i = root.tabNames.indexOf(name), t = root.channelTabs.find(x => x.name === name)
        // The open tab's chevron menu; a tab that can't be opened (a website
        // tab) has its right-click menu.
        if (t) tabMenu.show(t, t.menu.length && !t.opens_in_browser ? t.menu : t.context_menu, tabRepeater.itemAt(i) || header, 0, 56)
    }
    function overflowMenuForTest() { tabOverflowMenu.open() }
    function closeOverflowForTest() { tabOverflowMenu.close() }
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
        onVisibleChanged: if (visible) { root.copilotOpen = false; root.copilotHistoryOpen = false }
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
            const roster = root.chatMembers
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
            text: root.isChannel ? qsTr("People in the channel") : qsTr("People (%1)").arg(participants.members.length)
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
                    color: prowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
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
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, theme.text)
                    }
                    Text {
                        visible: !!prow.modelData.me
                        x: 54; y: 25; height: 16; verticalAlignment: Text.AlignVCenter
                        text: qsTr("You")
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(prow, theme.text)
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
                        ToolTip.text: qsTr("Remove")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Remove %1").arg(prow.modelData.name)
                    }
                    ToolTip.visible: prowHover.hovered && !removeHover.hovered && !prow.modelData.me
                    ToolTip.text: prow.modelData.name
                    ToolTip.delay: 600
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: prow.modelData.name + (prow.modelData.me ? ", " + qsTr("You") : "")
                }
            }
        }
        Rectangle {
            visible: participants.canAdd
            x: 16.7; y: rows.y + rows.height + 7; width: 218; height: 0.67
            color: theme.pick("#E0E0E0", "#3D3D3D", "#000000")
        }
        // Add people (chat-add-members): person-add at 24.3, the label at 60.3.
        Rectangle {
            id: addRow
            visible: participants.canAdd
            x: 2.7; y: rows.y + rows.height + 12.6
            width: 246; height: 31.3; radius: 4
            color: addHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
            FluentIcon { x: 21.6; anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 20; color: theme.onFill(addRow, theme.textStrong) }
            Text { x: 57.6; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add people"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(addRow, theme.text) }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { participants.visible = false; root.openAddPeople() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add people")
        }
    }
    // Leave (leave-chat-btn): person-arrow-left at 24.3, 32 tall.
    Rectangle {
        id: leaveRow
        parent: participants
        visible: participants.canLeave
        x: 2.7; y: addRow.y + addRow.height
        width: 246; height: 32; radius: 4
        color: leaveHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
        FluentIcon { x: 21.6; anchors.verticalCenter: parent.verticalCenter; name: "person-arrow-left-20"; size: 20; color: theme.onFill(leaveRow, theme.textStrong) }
        Text { x: 57.6; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Leave"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(leaveRow, theme.text) }
        HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { participants.visible = false; memberRemoveDialog.startLeave(participants.members.find(m => m.me)) } }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Leave")
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
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Text {
            x: 24.7; y: 24.7; width: 550; height: 28; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            text: memberRemoveDialog.leaving ? qsTr("Leave the conversation?") : qsTr("Remove %1 from the conversation?").arg(memberRemoveDialog.member ? memberRemoveDialog.member.name : "")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: 24.7; y: 59.3; height: 20; verticalAlignment: Text.AlignVCenter
            text: memberRemoveDialog.leaving ? qsTr("You'll still have access to the chat history.") : qsTr("They'll still have access to the chat history.")
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
        }
        Row {
            x: 375.3; y: 88.7; spacing: 8
            Rectangle {
                id: hcFill13
                width: 96; height: 31.3; radius: 4
                color: rCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill13, theme.text) }
                HoverHandler { id: rCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: memberRemoveDialog.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: hcFill14
                width: 96; height: 31.3; radius: 4
                color: rOkHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: memberRemoveDialog.leaving ? qsTr("Leave") : qsTr("Remove"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill14, "white") }
                HoverHandler { id: rOkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: memberRemoveDialog.confirm() }
                Accessible.role: Accessible.Button
                Accessible.name: memberRemoveDialog.leaving ? qsTr("Leave") : qsTr("Remove")
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
    // Files picked from OneDrive or SharePoint, with Teams' Attach popover,
    // cloud file picker and their cards' Link settings (CloudAttach).
    readonly property alias pendingCloud: cloudAttach.pending
    readonly property bool hasFiles: pendingFiles.length > 0 || cloudAttach.hasFiles
    /// What the backend sends: local paths, then "cloud:" and each read
    /// cloud file.
    function fileLines() {
        return pendingFiles.concat(cloudAttach.lines()).join("\n")
    }
    function clearFiles() { pendingFiles = []; cloudAttach.clear() }
    /// Files from the Attach popover or the cloud file picker into the
    /// compose box (Teams reads each for its card).
    function attachCloud(list) { cloudAttach.attach(list) }
    /// Teams' Attach popover over the Attach button.
    function openAttach(anchor, alignEnd) {
        cloudAttach.context = root.messages.filter(m => m.kind !== "call" && !m.deleted).slice(-3).reverse()
            .map(m => ({ id: m.id, text: m.text || "", sender: String(m.sender_mri || "").replace(/^8:orgid:/, ""), time: m.time }))
        cloudAttach.openMenu(anchor || compose, alignEnd)
    }
    CloudAttach {
        id: cloudAttach
        chatId: root.threadChannel || root.chatId
        channel: root.isChannel
        teamName: root.teamName
        teamId: root.teamId
        onUploadRequested: filePicker.open()
        onFailed: text => compose.showBanner(text, false, 3000)
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
    /// Teams' "Never translate German": the language joins "Never translate
    /// messages in these languages" (Settings ▸ General ▸ Translation).
    function neverTranslate(code) {
        if (!code) return
        const s = JSON.parse(backend.translationSettingsJson())
        if (s.known.indexOf(code) < 0) backend.setSetting("translationKnown", JSON.stringify(s.known.concat([code])))
    }
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
            // Invoke, messageBack and a plain Action.Submit go to the bot
            // (Teams: a plain submit is a messageBack); sign-in and task
            // modules aren't built yet.
            if (mtype && mtype !== "invoke" && mtype !== "messageback") { console.warn("card: Action.Submit " + mtype + " isn't sent", JSON.stringify(a.data || {})); return }
        } else if (t !== "action.execute" && t !== "messageback") return
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
            // The bot couldn't be reached (the service answered with an
            // error): Teams' red bar under the card (OST TEST 169, winpc).
            if (error) root.setCardFooter(key, { error: true, text: qsTr("Unable to reach app. Please try again.") })
            else if (v && v.kind === "message") root.setCardFooter(key, { text: v.message })
            else if (v && v.kind === "error") root.setCardFooter(key, { error: true, text: v.message })
            else root.setCardFooter(key, { text: qsTr("Your response was sent to the app") })
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
                    if (root.cardPending) root.toastRequested({ text: qsTr("Something went wrong. Try again."), intent: "error" })
                    root.cardPending = null
                    return
                }
                const m = Object.assign({}, root.cardItems); m[v.url] = { item: v.item, favorite: v.favorite }; root.cardItems = m
                if (cardMenu.opened && root.cardMenuFile && root.cardMenuFile.object_url === v.url) cardMenu.items = root.cardMenuItems(root.cardMenuFile)
                const p = root.cardPending
                if (p && p.file.object_url === v.url) { root.cardPending = null; root.fileCardAct(p.file, p.label) }
            } else if (kind === "card_favorite") {
                if (error || !v) { root.toastRequested({ text: qsTr("Something went wrong. Try again."), intent: "error" }); return }
                const m = Object.assign({}, root.cardItems)
                if (m[v.url]) { m[v.url] = Object.assign({}, m[v.url], { favorite: v.on }); root.cardItems = m }
                const file = root.cardFileFor(v.url)
                root.toastRequested(v.on ? { text: qsTr("Added \"%1\" to OneDrive Favorites").arg(v.name), intent: "success" }
                    : { text: qsTr("Removed from OneDrive Favorites"), intent: "success", action: qsTr("Undo"),
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
        return [{ act: "Open in Browser", label: qsTr("Open in Browser"), icon: "globe-20" }, { act: "Download", label: qsTr("Download"), icon: "arrow-download-20" },
                { act: "Share", label: qsTr("Share"), icon: "share-20" }, { act: "Copy link", label: qsTr("Copy link"), icon: "link-20" },
                fav ? { act: "Unfavorite", label: qsTr("Unfavorite"), icon: "star-20-filled" } : { act: "Favorite", label: qsTr("Favorite"), icon: "star-20" }]
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
        if (label === "Open in Browser") { backend.openExternal(file.share_url || file.object_url); return }
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
        onPicked: i => { if (root.cardMenuFile) root.fileCardAct(root.cardMenuFile, items[i].act) }
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
    function attachMenuForTest() { return cloudAttach.menu }
    function cloudPickerForTest() { return cloudAttach.picker }
    function cloudForTest() { return cloudAttach.stateForTest() }
    function cloudAttachForTest() { return cloudAttach }
    function addFiles(urls) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    // Send what's in the compose box: text, files, or both.
    function sendCompose() {
        // The first link's preview goes with the message (Teams'
        // properties.links), shown or removed.
        backend.setNextUrlPreview(compose.previewForSend())
        backend.setNextAppCard(compose.appCardForSend())
        backend.setNextLoop(compose.loopForSend())
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
        // A recorded clip goes once it is stored (Teams shows
        // "Processing..." until then).
        if (compose.clip && !compose.clip.id) return
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
        if (compose.clip) {
            const c = compose.clip
            backend.sendWithClip(JSON.stringify({ id: c.id, url: c.url, duration: c.duration, width: c.width, height: c.height }), input.getFormattedText(0, input.length), JSON.stringify(compose.mediaInUse()))
            compose.clip = null
        } else if (root.hasFiles) {
            // Formatted text (or a mention) goes with the files as Teams
            // HTML, as without files.
            const fhtml = compose.formattedText()
            if (root.plainText().trim() && /<(b|i|u|s|ul|ol|h[123]|hr|blockquote|pre|code|span|a|table)[ >]|margin-left/.test(fhtml)) backend.sendFilesHtml(root.fileLines(), fhtml)
            else backend.sendFiles(root.fileLines(), root.plainText())
            root.clearFiles()
        } else if (compose.mediaInUse().length > 0) {
            // Picked emoticons, GIFs and stickers go in Teams' own form.
            backend.sendRichMedia(input.getFormattedText(0, input.length), JSON.stringify(compose.mediaInUse()))
        } else if (compose.loop || (compose.appCard && compose.appCard.fromApp)) {
            // A Loop component goes as Teams' HTML (the text, then the
            // FluidEmbedCard span), even with no text.
            backend.sendRich(root.plainText().trim().length > 0 ? compose.formattedText() : "")
        } else if (root.plainText().trim().length > 0) {
            // Formatted text goes as Teams HTML; plain text as before.
            // Formatting goes as Teams HTML; plain text as before.
            const html = compose.formattedText()
            if (/<(b|i|u|s|ul|ol|h[123]|hr|blockquote|pre|code|span|a|table)[ >]|margin-left/.test(html)) backend.sendRich(html)
            else root.send(root.plainText())
        }
        // The component is the message's now: Teams names its file.
        if (compose.loop) compose.loopSent()
        compose.clear()
        root.quoting = null
        compose.formatting = false
        compose.importance = ""
        compose.resetPost()
        root.posting = false
        root.composeSent()
    }
    /// The main compose box sent (the new chat form closes on it).
    signal composeSent()
    // Teams' pinned-message banner (pinned-message-banner, measured): over
    // the top of the list, 40 tall, NeutralBackground2 with shadow 8 and a
    // NeutralStroke3 bottom line. Pin icon (20) at 20.7, the sender (12),
    // the preview (12 semibold) 15 after it, the date (12 semibold) at the
    // right, then ··· (View in chat, Unpin for everyone). Clicking it goes
    // to the message.
    readonly property var pinnedBanner: backend.pinnedJson ? JSON.parse(backend.pinnedJson) : null
    function pinnedStamp(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return theme.time(d)
        return d.getFullYear() === now.getFullYear() ? theme.dateNoYear(d) : theme.date(d)
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
            Accessible.name: root.pinnedBanner ? qsTr("Pinned message banner. Message from %1 sent on %2, %3").arg(root.pinnedBanner.sender).arg(root.pinnedStamp(root.pinnedBanner.time)).arg(root.pinnedBanner.text) : ""
        }
        BarButton {
            id: pinMore
            x: parent.width - 32 - 2; y: 4; height: 31.3
            icon: "more-horizontal-20"; tip: qsTr("Pinned options")
            onClicked: { pinMenu.parent = pinMore; pinMenu.x = pinMore.width - pinMenu.implicitWidth; pinMenu.y = pinMore.height; pinMenu.open() }
        }
        MenuPopup {
            id: pinMenu
            margins: 8
            items: [{ key: "view", label: qsTr("View in chat"), icon: "open-20" }, { key: "unpin", label: qsTr("Unpin for everyone"), icon: "pin-off-20" }]
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
        // The body keeps its selection while the menu has the keyboard.
        function popup(anchor, px, py) { parent = anchor; x = px; y = py; if (target) target.persistentSelection = true; open() }
        onClosed: if (target) target.persistentSelection = false
        margins: 8
        items: [{ key: "copy", label: qsTr("Copy"), keys: "Ctrl+C" }, { key: "all", label: qsTr("Select all"), keys: "Ctrl+A" }]
        onPicked: i => { if (!target) return; if (items[i].key === "copy") target.copy(); else target.selectAll() }
    }
    FileDialog {
        id: filePicker
        title: qsTr("Upload from this device")
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
            id: hcFill15
            x: parent.width - 28.67; y: 0.67; width: 28; height: 28; radius: 4
            color: closeNoteHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(hcFill15, theme.textStrong) }
            HoverHandler { id: closeNoteHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    const d = Object.assign({}, root.dismissedPeerNotes)
                    d[root.chatId + "|" + root.peerNoteText] = true
                    root.dismissedPeerNotes = d
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close notification")
        }
    }
    // The chat's compose (Teams' simplified compose; ComposeBox). It sits
    // 72 in on each side, 6 above the bottom, its hint row included.
    ComposeBox {
        id: compose
        // Link previews: Optional connected experiences on, your messaging
        // policy allowing them, and not in your notes to self.
        previewsAllowed: root.previewsShown && root.chatId !== "48:notes"
        chatId: root.chatId
        // (Names a sent Loop component without a title.)
        chatTitle: root.chatTopic || root.chatName
        // Teams' "Saved draft": Discard or "Use this version".
        onConflictResolved: useIt => { if (root.draftChat) { root.saveDraft(root.draftChat); backend.resolveDraftConflict(root.draftChat, useIt) } }
        // The app card's settings button: Settings ▸ Privacy (Teams).
        onAppCardSettingsRequested: root.openPrivacySettings()
        onAppCardPermissionsRequested: id => root.openAppDetails(id)
        visible: root.chatName.length > 0 && (!root.isChannel || root.posting || root.threadsLayout) && ["Attendance", "Breakout Rooms", "Q&A", "Meeting Whiteboard", "Notes", "Recap", "Storyline"].indexOf(root.tab) < 0 && !root.channelTabs.some(t => t.name === root.tab && !root.isChannel) && !root.readOnly
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
        anchors.leftMargin: post ? postGut : root.pane ? root.paneComposeGut : root.composeGut
        anchors.rightMargin: post ? postGut : root.pane ? root.paneComposeGut : root.composeGut

        onCloseRequested: { compose.resetPost(); compose.clear(); root.posting = false }
        // Under 480 px Teams' compose is compact: its tools on their own row.
        compact: !root.pane && root.width < 480
        sendTo: root.threadPane ? "thread" : ""
        sendToInline: root.composeSendToInline
        threadSubject: root.threadsLayout
        tierWidth: root.width
        // Teams offers it in chats and channels, not in your own chat or a
        // thread's reply box.
        scheduleAllowed: !root.isSelf && !root.threadRoot && !root.pane
        placeholder: root.composeDisabled ? root.composeDisabledText : root.threadRoot ? qsTr("Reply in thread") : root.threadsLayout ? qsTr("Message in %1").arg(root.chatName) : qsTr("Type a message")
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
        // Loop components from the chat's or channel's own box.
        loopHost: !root.popout && !root.threadRoot && !root.pane
        onComposeAppCommand: (app, cmd, anchor) => root.runComposeCommand(app, cmd, anchor)
        onGetMoreAppsRequested: root.getMoreApps()
        // A suggested app's Permissions: its details.
        onAppPermissionsRequested: id => root.openAppDetails(id)
        onCloudRemoved: key => cloudAttach.remove(key)
        onCloudLinkRequested: key => cloudAttach.openLink(key)
        onAttachRequested: a => root.openAttach(a)
        // Record video clip: in a chat's or channel's own compose box.
        canRecordClip: root.canRecordClips
        onRecordClipRequested: { root.clipBox = compose; clipRecorder.openFor(root.chatId) }
        onClipRemoved: {
            if (compose.clip) {
                if (compose.clip.path) backend.removeRecorderFile(compose.clip.path)
                if (compose.clip.spec) for (const sg of compose.clip.spec.segments) backend.removeRecorderFile(sg.path)
            }
            compose.clip = null
        }
        onClipRetry: {
            compose.clip = Object.assign({}, compose.clip, { uploading: true, error: "", rendering: !compose.clip.path })
            if (compose.clip.path) backend.videoClipUpload(root.chatId, compose.clip.path, compose.clip.thumb)
            else backend.renderClip(JSON.stringify(compose.clip.spec))
        }
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
        readonly property var roster: root.chatMembers
        memberCount: roster.length
        meetingChat: root.isMeetingChat
        mentionables: roster.filter(m => !m.me).map(m => ({ mri: m.mri, name: m.name, mail: m.mail }))
        urgentAllowed: !root.isGroup || root.chatMembers.length <= 20
        onScheduleMeetingRequested: root.scheduleMeeting()
        onCancelled: { root.quoting = null; root.clearFiles(); compose.resetPost(); root.posting = false; if (root.draftChat) backend.setDraft(root.draftChat, "") }
        Connections {
            target: compose.editor
            function onTextChanged() { draftSave.restart() }
        }
        // A Loop component put in or taken out (a box with one keeps no
        // draft).
        onLoopChanged: draftSave.restart()
        onLoopLinkRequested: (fileRef, fileName, scope, edit) => cloudAttach.openLoopLink(compose, fileRef, fileName, scope, edit)
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
    function postViewForTest() { return postViewLoader.item }
    Loader {
        id: postViewLoader
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
            onJoinMeeting: (url, title) => root.joinMeetingRequested(url, title)
            onOpenMeetingDetails: (url, start) => root.openMeetingPage(url, start)
        }
    }
}
