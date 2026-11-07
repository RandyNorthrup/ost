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
    signal closePane()
    /// In a channel: reply to a post, and whether a new post is being written.
    signal sendReply(string rootId, string text)
    property bool posting: false
    // Keyboard shortcuts (Ctrl+R, Ctrl+F, Ctrl+J, Alt+P, Alt+1-9, Alt+Shift+O).
    // The chat's compose editor.
    readonly property Item input: compose.editor
    function focusCompose() { if (compose.visible) input.forceActiveFocus() }
    function openFind() { finding = true; tab = ""; findField.forceActiveFocus() }
    function jumpToNewest() { tab = ""; list.positionViewAtBeginning(); channelPosts.toEnd() }
    function toggleDetails() { participants.visible = !participants.visible }
    // A channel's tabs, as Teams lists them: Posts, Shared (its Files
    // tab), then the channel's own tabs in order (Page, Notes, apps).
    readonly property var channelTabs: {
        if (!isChannel || !backend.channelTabsJson) return []
        const r = JSON.parse(backend.channelTabsJson)
        if (r.channel !== chatId || !r.tabs) return []
        // In the channel's own order (Graph's sortOrderIndex).
        return r.tabs.filter(t => t.app !== "Files" && t.name !== "Files")
    }
    readonly property var tabNames: isChannel ? (channelTabs.length ? channelTabs.map(t => t.name) : ["Posts", "Shared"])
        // Teams (worker Ct): Storyline only in 1:1 chats.
        // Meeting chats: Chat, Shared, Recap (Teams lists Attendance, Breakout
        // Rooms, Q&A and Meeting Whiteboard after them, under "+4").
        : isSelf ? ["Chat", "Shared", "Storyline"] : isMeetingChat ? ["Chat", "Shared", "Recap"] : isGroup ? ["Chat", "Shared", "Notes", "Recap"] : ["Chat", "Shared", "Notes", "Recap", "Storyline"]
    readonly property bool isMeetingChat: chatId.indexOf("19:meeting_") === 0
    // When this chat was opened (for GIF autoplay).
    property date openedAt: new Date()
    // The header's breakpoints (Teams 7.3: the header's own width). Below
    // 720 the roster count moves into ··· as Participants; below 640 the
    // tabs become a dropdown under a 14 px title, and chat details moves
    // into ··· as "In this chat" (measured at 604: only Find stays inline);
    // below 480 Find goes too. Live roster avatars show from 834.
    function openChatMenuForTest() { chatMenu.open() }
    function funPickerForTest() { return emojiPicker }
    function customEmojiAddForTest() { return customEmojiAdd }
    function composeMediaForTest() { return compose.mediaInUse() }
    function closeChatMenuForTest() { chatMenu.close() }
    function toggleFind() { root.finding = !root.finding; if (root.finding) { root.tab = ""; findField.forceActiveFocus() } else findField.text = "" }
    readonly property bool headerNarrow: width < 640
    readonly property bool rosterInMenu: width < 720 && isGroup && !isChannel && !isSelf
    readonly property int contextInline: isChannel || pane ? 2 : width >= 640 ? 2 : width >= 480 ? 1 : 0
    // Right to left from ···: the inline context buttons (32 each), a
    // 16 px divider, then the action items.
    readonly property real contextLeft: width - 43 - 32 * contextInline
    readonly property real actionRight: contextLeft - 16
    // The meeting chat's meeting (join link, iCalUid, cancelled).
    readonly property var meeting: isMeetingChat && backend.chatMeetingJson ? JSON.parse(backend.chatMeetingJson) : null
    // Load a channel's tabs once it's known which team it's in.
    readonly property string tabsKey: isChannel && teamId && chatId ? teamId + "|" + chatId : ""
    onTabsKeyChanged: if (tabsKey) backend.channelTabsLoad(teamId, chatId, chatName)
    // The channel tab showing a web page in place (Page: the channel's
    // Loop page), when one is selected.
    readonly property var webTab: null
    function openTab(i) { if (i < tabNames.length) tab = i === 0 ? "" : tabNames[i] }
    readonly property bool composeFocused: input.activeFocus
    readonly property bool detailsOpen: participants.visible
    function attachFile() { if (compose.visible) filePicker.open() }
    function replyForTest(text) { return channelPosts.replyToNewestForTest(text) }
    // Test hooks for the compose box.
    function setComposeText(t) { root.setPlain(t) }
    function composeText() { return root.plainText() }
    // The compose box is rich text (Teams formats as you type); these read
    // and write it as plain text.
    // Teams' quick reactions: the user's defaultMessageReactions, else the
    // live default (547607).
    // With a skin tone set, Like shows in it (547607 `x`).
    readonly property var quickReactions: (backend.quickReactionsJson ? JSON.parse(backend.quickReactionsJson) : ["yes", "heart", "laugh", "surprised"])
        .map(k => root.commonKey(k) === "yes" && backend.skinTone > 0 ? "yes-tone" + backend.skinTone : k)
    // Test hook: show the hover bar on this message (--actions-test).
    property string forceBarId: ""
    // Test hook: opens the who-reacted list of this message's first pill.
    property string forceWhoId: ""
    // Test hook: opens the overflow list ("+N") of this message.
    property string forceWhoOverflowId: ""
    // The message being quoted in the compose box (Reply with quote).
    property var quoting: null
    function replyWithQuote(m) {
        quoting = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.quote_text || m.text || "" }
        input.forceActiveFocus()
    }
    // Teams edits in place; Urgent messages can't be edited.
    function startEdit(m) { if (m.importance !== "urgent") root.editingId = m.id }
    // The emoji picker inserts into whichever compose asked for it.
    property var emojiTarget: null
    function openEmojiFor(box) { emojiTarget = box; emojiPicker.parent = box; emojiPicker.open() }
    // The fun picker's picks go into the box it was opened from: GIFs and
    // stickers as pictures, emoticons as Teams' inline emoticons (as text
    // where the box sends plain text).
    function insertPicked(m) {
        const box = root.emojiTarget || compose
        if (box === compose) box.insertMedia(m)
        else if (m.kind === "emoji") box.insertText(m.unicode)
    }
    signal openChatSettings()
    signal scheduleMeeting()
    // Go to a message (a quote card's target), if it is loaded.
    // The chat's call: one going on (a start with no end), whether we're in
    // it, and Teams' 20-member limit for calls in group chats.
    // The thread's liveness entry (the chat list's liveCall) says so even
    // when the call's start isn't among the loaded messages.
    readonly property var liveCall: { const c = (backend.chatsJson ? JSON.parse(backend.chatsJson) : []).find(c => c.id === root.chatId); return c && c.liveCall ? c.liveCall : null }
    readonly property bool chatMuted: { const c = (backend.chatsJson ? JSON.parse(backend.chatsJson) : []).find(c => c.id === root.chatId); return !!(c && c.muted) }
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
    readonly property var cardKinds: ["application/vnd.microsoft.card.adaptive", "application/vnd.microsoft.card.hero", "application/vnd.microsoft.card.thumbnail"]
    // Teams' per-user reaction limit (217146, enableMultipleReactionsPerUser).
    readonly property int reactionLimit: 20
    readonly property string limitText: "You\u2019ve reached the " + reactionLimit + "-reaction limit. Remove one to add another."
    // Teams' reaction overflow (`Ze`): five pills' worth of room (36 each)
    // when the window is at least 480 wide, else three, one fewer under 360
    // when there are more; pills estimated as Teams does (`xe`).
    function pillEstimate(r) {
        if (r.count === 1) return 34
        let digits = String(r.count).length * 8
        if (r.mine) digits *= 1.0676
        return (r.kinds || 1) * 20 + 4 + digits + 14
    }
    function splitReactions(list) {
        const w = root.Window.window ? root.Window.window.width : root.width
        let slots = w >= 480 ? 5 : 3
        if (w < 360 && list.length > slots) slots -= 1
        if (slots <= 0) return { main: [], overflow: list }
        let room = slots * 36, n = 0
        for (const r of list) {
            const e = pillEstimate(r)
            room -= e
            if (room >= 0) n++
            else if (list.length - n === 1 && e + room <= ("+1").length * 8 + 14) n++
            else break
        }
        return { main: list.slice(0, n), overflow: list.slice(n) }
    }
    // A pill's name, with its skin tones when it has them (Teams' `Fe`).
    readonly property var toneWords: ["", "light", "medium light", "medium", "medium dark", "dark"]
    function pillLabel(r) {
        const name = backend.emoticonName(r.key)
        const n = r.count, s = n === 1 ? "" : "s"
        const tones = (r.variants || [r.key]).map(k => { const m = /-tone(\d)$/.exec(k); return m ? Number(m[1]) : 0 })
        if (tones.length === 1 && tones[0] === 0) return n + " " + name + " reaction" + s + "."
        if (tones.length === 1) return n + " " + name + " reaction" + s + " with " + toneWords[tones[0]] + " skin tone."
        const words = tones.map(t => t === 0 ? "no" : toneWords[t])
        return n + " " + name + " reaction" + s + " with " + words.slice(0, -1).join(", ") + " and " + words[words.length - 1] + " skin tones."
    }
    // Teams' common key: the id without its skin tone.
    function commonKey(id) { const m = /^(.{1,40})-tone\d$/.exec(id); return m ? m[1] : id }
    function jumpToMessage(id) {
        const i = (list.model || []).findIndex(m => m.id === id)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
    }
    function tonesForTest(id) { reactionPicker.tonesForTest(id) }
    function customizeForTest() { customizeReactions.open() }
    function customizeSlotForTest(i) { customizeReactions.pickForTest(i) }
    function customizeToneForTest(t) { customizeReactions.setTone(t) }
    function closeCustomizeForTest() { customizeReactions.close() }
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
    property string forceChannelBarId: ""
    function forceChannelBarForTest(id) { forceChannelBarId = id }
    function channelMenuForTest(m, context) { openMessageMenu(m, channelPosts, false, channelPosts.width - 300, 120, context) }
    function composeForTest() { return compose }
    function closePickerForTest() { reactionPicker.close() }
    function closeMessageMenuForTest() { messageMenu.close() }
    function forwardDialogForTest() { return forwardDialog }
    function reportDialogForTest() { return reportDialog }
    function openReactionPicker(messageId, anchor) {
        const m = (list.model || []).find(x => x.id === messageId)
        reactionPicker.mine = m ? (m.reactions || []).filter(r => r.mine) : []
        reactionPicker.messageId = messageId; reactionPicker.parent = anchor; reactionPicker.open()
    }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function plainText() { return input.getText(0, input.length) }
    function setPlain(t) { input.clear(); if (t) input.insert(0, root.escapeHtml(t)) }
    function attachForTest(paths) { root.pendingFiles = paths }
    function openEmojiForTest() { emojiPicker.open() }
    function formatForTest(a, b, tag) { input.select(a, b); root.wrapSelection(tag) }
    function openParticipantsForTest() { participants.visible = true }
    function findForTest(q) { root.finding = true; findField.text = q; return root.findHits.length }
    function sendForTest() { root.sendCompose() }
    function insertTextForTest(t) { compose.insertText(t) }
    onChatIdChanged: {
        openedAt = new Date()
        tab = ""; finding = false; findField.text = ""; participants.visible = false; posting = false
        if (draftChat) backend.setDraft(draftChat, root.plainText())
        editingId = ""
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
    signal editMessage(string messageId, string text)
    signal deleteMessage(string messageId)
    // Set while the compose box edits an existing message.
    property string editingId: ""

    // Newest first (the list grows upward), with Teams' grouping: a message
    // joins the previous one when the same person sent it under 5 minutes
    // later. latestMine marks your newest message for the sent tick.
    // Teams' relative dates: the time alone today, then "Yesterday 3:05 PM",
    // the weekday within a week, and the date beyond that.
    function daysAgo(d) {
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const now = new Date()
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        return Math.round((b - a) / 86400000)
    }
    function stamp(t) {
        const d = new Date(t), n = daysAgo(d), time = Qt.formatTime(d, "h:mm AP")
        if (n === 0) return time
        if (n === 1) return "Yesterday " + time
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd") + " " + time
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "M/d") + " " + time
        return Qt.formatDate(d, "M/d/yyyy") + " " + time
    }
    function dayLabel(t) {
        const d = new Date(t), n = daysAgo(d)
        if (n === 0) return "Today"
        if (n === 1) return "Yesterday"
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd")
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "MMMM d")
        return Qt.formatDate(d, "MMMM d, yyyy")
    }

    function annotate(msgs) {
        // A call's start shows only for Meet now ("… started a meeting.").
        const out = msgs.filter(m => !(m.kind === "call" && m.call_state === "started" && !m.call_huddle)).map(m => Object.assign({}, m))
        let unreadSeen = false
        for (let i = 0; i < out.length; i++) {
            const prev = i > 0 ? out[i - 1] : null, cur = out[i]
            // A day divider where the day changes (not above the very first
            // message shown), and the "Last read" line where unread begins.
            const day = new Date(cur.time).toDateString()
            cur.dayDivider = prev && new Date(prev.time).toDateString() !== day ? root.dayLabel(cur.time) : ""
            cur.lastRead = cur.first_unread === true && i > 0
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
                && !cur.dayDivider && !cur.lastRead
                && cur.sender === prev.sender && cur.mine === prev.mine && gap >= 0 && gap < 5 * 60 * 1000
        }
        // Whether the next message continues this one's group (Teams squares
        // the corners where grouped bubbles meet).
        for (let i = 0; i < out.length; i++) out[i].groupNext = i + 1 < out.length && out[i + 1].grouped === true
        // Teams' receipts: your newest message carries the sent tick until
        // it is read; the newest one the other person has read gets the eye.
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind === "message" && !out[i].send_state) { out[i].latestMine = true; break }
        }
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind === "message" && out[i].seen) { out[i].latestSeen = true; break }
        }
        return out.reverse()
    }
    color: theme.surface

    // Header
    Item {
        id: header
        width: parent.width; height: theme.headerHeight
        visible: root.chatName.length > 0
        // Where the toolbar starts (its leftmost shown item, less Teams'
        // 4 px toolbar padding): the tabs fit before it.
        readonly property real toolbarLeft: {
            let x = root.actionRight
            for (const it of [callPrimary, oneToOnePeople, joinButton, meetNow, meetingJoin, rosterCount])
                if (it && it.visible) x = Math.min(x, it.x)
            return x - 4
        }
        Text {
            visible: root.pane
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: "Chat"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        HeaderAction {
            visible: root.pane
            x: parent.width - 44; icon: "dismiss-20"; Accessible.name: "Close chat"
            onClicked: root.closePane()
        }
        Item {
        visible: !root.pane
        anchors.fill: parent
        Avatar {
            visible: !root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: root.chatName; presence: root.chatPresence
            photoId: root.chatPhotoId
            group: root.isGroup && !root.chatPhotoId
        }
        Avatar {
            visible: root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            size: 32; square: true
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
            width: Math.min(implicitWidth, root.headerNarrow && !root.isChannel ? header.toolbarLeft - x - 16 : parent.width * 0.35)
            elide: Text.ElideRight
            text: root.chatName
            font.family: theme.font; font.pixelSize: root.headerNarrow && !root.isChannel ? 14 : theme.title; font.weight: Font.Bold
            color: theme.text
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
            visible: !(root.headerNarrow && !root.isChannel)
            x: (renameButton.visible ? renameButton.x + renameButton.width : title.x + title.width) + 2
            y: 2; height: 56
            Repeater {
                model: root.tabNames
                delegate: Item {
                    id: tabItem
                    required property string modelData
                    required property int index
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
                        color: tabItem.sel ? theme.text : theme.textStrong
                    }
                    FluentIcon {
                        visible: tabItem.menuable
                        x: tabText.x + tabText.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down-12"; size: 12; color: theme.text
                    }
                    // Selected: a 3 px brand pill, inset 8 px, at the bottom.
                    Rectangle {
                        visible: tabItem.sel
                        x: 8; width: tabText.implicitWidth - 4 + (tabItem.menuable ? 20 : 0); height: 3; radius: 1.5
                        anchors.bottom: parent.bottom
                        color: theme.brand
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const t = tabItem.channelTab
                            // Teams opens website tabs in the browser; they never become the selected tab.
                            if (t && t.opens_in_browser) { if (t.website_url) Qt.openUrlExternally(t.website_url); return }
                            if (tabItem.menuable) { tabMenu.show(t, t.menu, tabItem, 0, tabItem.height); return }
                            root.tab = tabItem.index === 0 ? "" : tabItem.modelData
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
            // "+N" (tab-overflow-button, measured): 14 px #616161, padding
            // 0 2, 60.3 tall; its menu lists the tabs that didn't fit.
            Item {
                id: tabOverflow
                visible: tabsFit.hidden.length > 0
                y: -2; width: plusText.implicitWidth + 4; height: 60.3
                Text { id: plusText; x: 2; anchors.verticalCenter: parent.verticalCenter; text: "+" + tabsFit.hidden.length; font.family: theme.font; font.pixelSize: theme.base; color: plusHover.hovered ? theme.text : theme.textSecondary }
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
            visible: root.headerNarrow && !root.isChannel && !root.pane
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
            color: haHover.hovered ? theme.hover : "transparent"
            HoverHandler { id: haHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ha.clicked() }
            FluentIcon { id: haIcon; anchors.centerIn: parent; size: ha.iconSize; color: theme.textStrong }
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
            visible: !root.isSelf && !root.isGroup
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
            color: rosterHover.hovered ? theme.hover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 2
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 20; color: theme.textStrong }
                Text { id: countLabel; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.count; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.textStrong }
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
            visible: !root.isSelf
            x: root.contextLeft - 8; width: 1; height: 20
            anchors.verticalCenter: parent.verticalCenter
            color: theme.divider
        }
        HeaderAction {
            visible: root.contextInline >= 1
            x: root.contextLeft; icon: "search-20"; Accessible.name: "Find in chat"
            onClicked: root.toggleFind()
        }
        HeaderAction {
            visible: root.contextInline >= 2
            x: root.contextLeft + 32; icon: "panel-left-20"; Accessible.name: "Open chat details"
            onClicked: participants.visible = !participants.visible
        }
        // More chat options (chat-header-more-menu-trigger). Items Teams has
        // that are not built yet: Open in new window, Share screen, Move to
        // section, Remove chat history.
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
                    root.rosterInMenu ? { key: "participants", label: "Participants", icon: "people-add-20" } : null
                ].filter(i => i !== null)
                items: (moved.length ? moved.concat([{ separator: true }]) : []).concat([
                    { key: "meeting", label: "Schedule meeting", icon: "calendar-add-20" },
                    { separator: true },
                    { key: "unread", label: "Mark as unread", icon: "mail-unread-20" },
                    root.isSelf ? null : { key: "mute", label: root.chatMuted ? "Unmute" : "Mute", icon: root.chatMuted ? "alert-20" : "alert-off-20" },
                    { key: "link", label: "Copy link", icon: "link-20" }
                ]).filter(i => i !== null)
                onPicked: i => {
                    const k = items[i].key
                    if (k === "details" || k === "participants") participants.visible = !participants.visible
                    else if (k === "find") root.toggleFind()
                    else if (k === "mute") backend.setChatMuted(root.chatId, !root.chatMuted)
                    else if (k === "meeting") root.scheduleMeeting()
                    else if (k === "link") backend.copyChatLink()
                    else if (k === "unread") { const m = root.messages.filter(m => m.kind === "message").pop(); if (m) backend.markMessageUnread(m.id, m.client_message_id || "") }
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
        visible: root.isChannel && root.tab === ""
        anchors { top: findBar.visible ? findBar.bottom : header.bottom; bottom: root.posting ? compose.top : parent.bottom; left: parent.left; right: parent.right }
        anchors.bottomMargin: root.posting ? 12 : 0
        messages: root.isChannel ? root.messages : []
        myName: root.myName
        busy: root.busy
        onReply: (id, text) => root.sendReply(id, text)
        onReact: (id, key, on) => root.react(id, key, on)
        host: root
        onStartPost: { root.posting = true; input.forceActiveFocus() }
    }

    ListView {
        id: list
        visible: root.tab === "" && !root.isChannel
        anchors { top: findBar.visible ? findBar.bottom : header.bottom; bottom: compose.top; left: parent.left; right: parent.right }
        anchors.bottomMargin: 12
        clip: true
        spacing: 0
        verticalLayoutDirection: ListView.BottomToTop
        model: root.annotate(root.messages)
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
            readonly property bool mine: modelData.mine && !root.isChannel
            readonly property bool isCall: modelData.kind === "call"
            // Teams' control messages (someone added, renamed, left…).
            readonly property bool isEvent: modelData.kind === "event"
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
            readonly property bool showMeta: (!grouped || sendFailed) && !isRow
            // Day divider and "Last read" line sit above the message.
            readonly property int dividerH: (modelData.dayDivider ? 30 : 0) + (modelData.lastRead ? 36 : 0)
            // Control and call rows sit flush, as in Teams (28 / 36 px rows).
            readonly property int topPad: dividerH + (isRow ? 0 : grouped ? 2 : 12)
            readonly property int bubbleY: topPad + (!showMeta || isCall ? 0 : meta.height + 2)
            height: isRow ? topPad + (isCall ? 36 : 28)
                : editingThis ? topPad + (editLoader.item ? editLoader.item.height : 0)
                : bubbleY + bubble.height + (reactions.length > 0 ? reactionRow.height - 4.3 + 4 : 0)
            readonly property int maxBubble: root.isChannel ? Math.min(900, list.width - 144) : Math.min(640, list.width * 0.7)

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
                x: 72; width: parent.width - 144; height: 36
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0; width: lastReadText.x - 24; height: 1; color: theme.brand
                }
                Text {
                    id: lastReadText
                    anchors.centerIn: parent
                    text: "Last read"
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                    color: theme.brand
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: lastReadText.x + lastReadText.width + 24
                    width: parent.width - x; height: 1; color: theme.brand
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
                x: 38; y: msg.topPad + 8
                size: 20
                name: msg.isCall ? (msg.modelData.call_huddle ? "video-20" : msg.modelData.call_state === "missed" ? "call-missed-20" : "call-20")
                    : ({ AddMember: "person-add-20", DeleteMember: "person-arrow-left-20", TopicUpdate: "edit-20",
                         PictureUpdate: "person-circle-20", MemberJoined: "calendar-add-20", MemberLeft: "person-arrow-left-20",
                         MemberRenamed: "person-edit-20" })[msg.modelData.event ? msg.modelData.event.kind : ""] || "person-add-20"
                color: theme.textSecondary
            }
            Row {
                id: callRow
                visible: msg.isRow
                x: 72; y: msg.topPad + 10
                spacing: 12
                Text {
                    visible: msg.isCall
                    text: root.stamp(msg.modelData.time)
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Text {
                    width: Math.min(implicitWidth, msg.width - 72 - 32)
                    wrapMode: Text.Wrap
                    textFormat: msg.isCall ? Text.StyledText : Text.PlainText
                    text: {
                        if (msg.isEvent) return msg.modelData.text
                        // Meet now (Teams: "You started a meeting." /
                        // "{{initiator}} started a meeting.", then
                        // "Meeting ended" with the duration).
                        if (msg.modelData.call_state === "started")
                            return msg.mine ? "You started a meeting." : root.escapeHtml(msg.modelData.sender || root.memberName(msg.modelData.sender_mri) || "Someone") + " started a meeting."
                        if (msg.modelData.call_state === "missed") return "Call missed"
                        const s = msg.modelData.call_seconds
                        const parts = [[Math.floor(s / 3600), "h"], [Math.floor(s / 60) % 60, "m"], [s % 60, "s"]]
                            .filter(p => p[0] > 0).map(p => p[0] + p[1]).join(" ")
                        return (msg.modelData.call_huddle ? "Meeting ended" : "Call ended") + "&nbsp;<b>" + parts + "</b>"
                    }
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
            }

            Avatar {
                visible: !msg.mine && !msg.grouped && !msg.isRow
                x: 32; y: msg.bubbleY
                size: 32; name: msg.modelData.sender
                photoId: msg.modelData.sender_mri || ""
                // Teams shows the sender's presence on message avatars too.
                presence: msg.modelData.sender_mri && msg.modelData.sender_mri === root.chatPhotoId ? root.chatPresence : ""
            }
            // Name line: [failed text] sender, time, details. A failed
            // message's text replaces the details (Teams' statusMessage).
            Row {
                id: meta
                visible: msg.showMeta && !msg.editingThis
                y: msg.topPad
                spacing: 8
                x: msg.mine ? msg.width - 72 - width : 72
                Text {
                    visible: msg.sendFailed
                    text: msg.modelData.send_note || ""
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.redForeground1
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Text {
                    text: (msg.mine ? "" : msg.modelData.sender + "  ") + root.stamp(msg.modelData.time)
                        + (msg.modelData.edited && !msg.sendFailed ? "   Edited" : "")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
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
                width: msg.width - 72 - 172
                sourceComponent: ComposeBox {
                    id: editBox
                    width: editLoader.width
                    editing: true
                    quote: msg.modelData.quote || null
                    onQuoteDismissed: quote = null
                    onEmojiRequested: a => root.openEmojiFor(editBox)
                    onSettingsRequested: root.openChatSettings()
                    onSubmit: {
                        backend.editMessageRich(msg.modelData.id, editBox.formattedText(), editBox.quote ? JSON.stringify(editBox.quote) : "", JSON.stringify(editBox.mediaInUse()))
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
                readonly property bool bare: (imageOnly || bigEmoticons) && !root.isChannel
                readonly property real pad: bare ? 0 : 15.7
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
                readonly property bool inFlow: flow.length > 0 && imgs.length > 0
                readonly property bool endsInText: inFlow && flow[flow.length - 1].html !== undefined
                readonly property real picsEnd: picsTop + picsH
                readonly property string textStyle: "<style>a { color: " + theme.brand + "; text-decoration: none; } "
                    + ".mention { color: " + theme.brandForeground1 + "; } "
                    + ".mention-me { color: " + theme.mentionMe + "; font-weight: 700; } "
                    + "p, div, li, body { line-height: " + (bigEmoticons ? 50 : 20) + "px; -qt-line-height-type: fixed; }</style>"
                // Teams' lines are 20 px; big emoticons (50 px) set their own.
                readonly property bool bigEmoticons: (msg.modelData.html || "").indexOf("width=\"50\" height=\"50\"") >= 0
                readonly property real bodyH: !showBody ? 0 : bigEmoticons ? Math.max(1, body.lineCount) * 50 : Math.max(1, body.lineCount) * 20
                // A quoted reply's card sits at the top (Teams: 10.7 down, the
                // text 4 under it).
                readonly property real quoteShift: msg.modelData.quote ? 60.3
                    // A forward card sits 14.7 down; a note 4 under it, else
                    // the bubble ends 9 under it (Teams).
                    : msg.modelData.forward ? fwdCard.height + (showBody ? 12 : 8.4) : 0
                // In a flow the text's own blank line sets the gap (Teams).
                readonly property real picsTop: showBody ? body.y + bodyH + (inFlow ? 0 : 8) : (bare ? 0 : 8)
                readonly property real picsH: imgs.length > 0 ? pics.implicitHeight : 0
                readonly property real filesTop: imgs.length > 0 ? picsEnd + 8 : (showBody ? body.y + bodyH + 8 : 8)
                // Measured: a card sits 8 under the bubble's top (or the text),
                // 17.3 in, and the bubble ends 10.7 under it.
                readonly property real cardsTop: showBody ? body.y + bodyH + 8 : 8
                width: root.isChannel ? msg.maxBubble
                    : cards.length > 0 ? Math.max(cardCol.width + 2 * 17.3, showBody ? body.implicitWidth + 2 * pad : 0)
                    : Math.min(msg.maxBubble, Math.max(showBody ? body.implicitWidth + (msg.modelData.deleted && msg.mine ? 12 + undoMetrics.advanceWidth : 0) : 0, pics.implicitWidth, files.length > 0 ? fileCol.implicitWidth : 0, msg.modelData.quote ? quoteCard.width : 0, msg.modelData.forward ? fwdCard.width : 0) + 2 * pad)
                TextMetrics { id: undoMetrics; text: "Undo"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                height: cards.length > 0 ? cardsTop + cardCol.height + 10.7
                    : bare && files.length === 0 ? (bigEmoticons ? bodyH : picsH)
                    : files.length > 0 ? filesTop + fileCol.implicitHeight + 8
                    : imgs.length > 0 ? picsEnd + (endsInText || (showBody && !inFlow) ? 8.6 : 8)
                    : bodyH + 15.3 + quoteShift
                // Teams: 6 px corners, squared on the inner side where a
                // group's bubbles meet (bottom of the first, top of the rest).
                readonly property real r: root.isChannel ? theme.radius : 6
                readonly property bool joinUp: !root.isChannel && msg.grouped
                readonly property bool joinDown: !root.isChannel && msg.modelData.groupNext === true
                radius: r
                topLeftRadius: !msg.mine && joinUp ? 0 : r
                bottomLeftRadius: !msg.mine && joinDown ? 0 : r
                topRightRadius: msg.mine && joinUp ? 0 : r
                bottomRightRadius: msg.mine && joinDown ? 0 : r
                color: bare ? "transparent" : msg.sendFailed ? theme.redBackground1 : root.isChannel ? theme.surface : (msg.mine ? theme.brandTint : theme.bubble)
                border.color: msg.sendFailed ? theme.redBorder1 : root.isChannel ? theme.dividerSoft : "transparent"
                x: msg.mine ? parent.width - 72 - width : 72
                Column {
                    id: cardCol
                    visible: bubble.cards.length > 0
                    x: 17.3; y: bubble.cardsTop
                    width: bubble.cardW
                    spacing: 12
                    Repeater {
                        model: bubble.cards
                        Loader {
                            required property var modelData
                            sourceComponent: modelData.content_type === "application/vnd.microsoft.card.adaptive" ? adaptiveComp : heroComp
                            Component {
                                id: adaptiveComp
                                AdaptiveCard { content: modelData.content; cardWidth: list.width >= 720 ? 448 : 360 }
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
                        model: bubble.inFlow ? bubble.flow.map(p => p.pic !== undefined ? bubble.imgs[p.pic] : { flowText: p.html }) : bubble.imgs
                        Item {
                            id: part
                            required property var modelData
                            required property int index
                            readonly property bool isText: modelData.flowText !== undefined
                            // Teams: a picture after text or another picture
                            // sits 4 below it (the GIF's margin); text follows
                            // a picture directly.
                            readonly property real gap: bubble.inFlow && !isText && (index > 0 || bubble.showBody) ? 4 : 0
                            width: isText ? flowText.width : pic.width
                            height: gap + (isText ? Math.max(1, flowText.lineCount) * 20 : pic.height)
                            TextEdit {
                                id: flowText
                                visible: part.isText
                                width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                                readOnly: true
                                selectByMouse: true
                                persistentSelection: false
                                selectionColor: theme.selectionFill
                                selectedTextColor: theme.text
                                text: part.isText ? bubble.textStyle + theme.messageHtml(part.modelData.flowText) : ""
                                textFormat: TextEdit.RichText
                                wrapMode: TextEdit.Wrap
                                font.family: theme.font; font.pixelSize: theme.base
                                color: theme.text
                                onLinkActivated: link => Qt.openUrlExternally(link)
                                HoverHandler { cursorShape: flowText.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                            }
                        // Rounded 4 px with a hairline border, as Teams draws them.
                        Item {
                            id: pic
                            visible: !part.isText
                            y: part.gap
                            readonly property var modelData: part.isText ? ({}) : part.modelData
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
                    x: bubble.pad; y: 14.7
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
                    x: bubble.pad; y: 10.7
                    quote: msg.modelData.quote || null
                    maxWidth: msg.maxBubble - 2 * bubble.pad
                    onActivated: root.jumpToMessage(msg.modelData.quote.message_id)
                }
                // Selectable, as in Teams (a message's text can be selected and
                // copied); read-only.
                TextEdit {
                    id: body
                    visible: bubble.showBody
                    x: bubble.pad; y: bubble.bare ? 0 : 6.7 + bubble.quoteShift
                    width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: false
                    selectionColor: theme.selectionFill
                    selectedTextColor: theme.text
                    // Teams' 14/20 text (a fixed 20 px line).
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : bubble.textStyle + (msg.modelData.html ? theme.messageHtml(msg.modelData.html) : msg.modelData.text)
                    textFormat: msg.modelData.deleted ? TextEdit.PlainText : TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    // Teams' tombstone: italic, in the normal text colour.
                    font.italic: msg.modelData.deleted === true
                    color: theme.text
                    onLinkActivated: link => Qt.openUrlExternally(link)
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
                // File cards, as Teams draws them: type icon, name, and
                // share/download actions in a 48 px header.
                Column {
                    id: fileCol
                    x: bubble.pad; y: bubble.filesTop
                    spacing: 8
                    Repeater {
                        model: bubble.files
                        Rectangle {
                            id: fc
                            required property var modelData
                            readonly property string t: (modelData.file_type || "").toLowerCase()
                            width: Math.min(318, msg.maxBubble - 2 * bubble.pad); height: 48
                            radius: 8
                            color: theme.searchFill
                            border.color: theme.divider
                            FluentIcon {
                                x: 13; anchors.verticalCenter: parent.verticalCenter; size: 32
                                name: ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(fc.t) >= 0 ? "file-image-32"
                                    : ["mp4", "mov", "avi", "mkv", "webm"].indexOf(fc.t) >= 0 ? "file-video-32"
                                    : ["txt", "md", "log", "csv", "json", "xml"].indexOf(fc.t) >= 0 ? "file-text-32"
                                    : "file-32"
                                color: theme.textSecondary
                            }
                            Text {
                                x: 52; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 52 - 80
                                text: fc.modelData.name
                                elide: Text.ElideMiddle
                                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                                color: theme.text
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Qt.openUrlExternally(fc.modelData.share_url || fc.modelData.object_url) }
                            }
                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: [{ icon: "share-20", label: "Open in browser" }, { icon: "download-20", label: "Download" }]
                                    Rectangle {
                                        required property var modelData
                                        width: 32; height: 32; radius: theme.radius
                                        color: fah.hovered ? theme.rowHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                                        HoverHandler { id: fah; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: parent.modelData.icon === "download-20"
                                                ? backend.downloadFile(JSON.stringify(fc.modelData))
                                                : Qt.openUrlExternally(fc.modelData.share_url || fc.modelData.object_url)
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.label + " " + fc.modelData.name
                                    }
                                }
                            }
                            Accessible.role: Accessible.Link
                            Accessible.name: "File " + modelData.name
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
                host: root
                messageId: msg.modelData.id
                reactions: msg.reactions
                visible: msg.reactions.length > 0 && !msg.editingThis
                y: bubble.y + bubble.height - 4.3
                x: msg.mine ? bubble.x + bubble.width - 15.7 - width : bubble.x + 15.7
                z: 4
            }
            HoverHandler { id: msgHover }
            // Teams' hover bar, end-aligned on the bubble's top edge.
            HoverBar {
                id: actions
                readonly property bool can: !msg.isRow && !msg.modelData.deleted && !msg.sendPending && !msg.sendFailed && !msg.editingThis
                host: root
                message: msg.modelData
                acts: msg.mine
                    ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                    : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }]
                visible: can && (msgHover.hovered || actions.hovered || (messageMenu.opened && !messageMenu.rightClick && messageMenu.message && messageMenu.message.id === msg.modelData.id) || root.forceBarId === msg.modelData.id)
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
                readonly property string tip: msg.sendPending ? (msg.modelData.send_note || "")
                    : msg.sendFailed ? "Failed"
                    : seen ? (root.isGroup ? "Seen by everyone" : "Seen") : "Sent"
                visible: msg.mine && !msg.isRow && (msg.sendPending || msg.sendFailed || seen || (msg.modelData.latestMine === true && !msg.modelData.seen))
                name: msg.sendPending ? "circle-12" : msg.sendFailed ? "warning-12-filled" : seen ? "seen-12" : "sent-12"
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
    property bool finding: false
    property int findIndex: 0
    readonly property var findHits: {
        const q = findField.text.trim().toLowerCase()
        if (!q) return []
        const shown = root.annotate(root.messages)
        const hits = []
        for (let i = 0; i < shown.length; i++) if ((shown[i].text || "").toLowerCase().indexOf(q) >= 0) hits.push(i)
        return hits
    }
    onFindHitsChanged: { findIndex = 0; if (findHits.length) list.positionViewAtIndex(findHits[0], ListView.Center) }
    Rectangle {
        id: findBar
        visible: root.finding && root.tab === ""
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        height: visible ? 48 : 0
        color: theme.surface
        Rectangle {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(420, parent.width - 144); height: 32; radius: theme.radius
            color: theme.input
            border.color: findField.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: findField
                x: 32; width: parent.width - 150
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                Keys.onReturnPressed: root.findNext(1)
                Keys.onEscapePressed: { text = ""; root.finding = false }
                Text { visible: !findField.text; text: "Find in chat"; color: theme.textTertiary; font: findField.font }
                Accessible.name: "Find in chat"
            }
            Text {
                anchors.right: findNav.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                visible: findField.text.length > 0
                text: root.findHits.length ? (root.findIndex + 1) + " of " + root.findHits.length : "No results"
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
            }
            Row {
                id: findNav
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ icon: "chevron-left-20", d: 1, l: "Older match" }, { icon: "chevron-right-20", d: -1, l: "Newer match" }]
                    Rectangle {
                        required property var modelData
                        width: 24; height: 24; radius: theme.radius
                        color: fnh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16; color: theme.textStrong; rotation: 90 }
                        HoverHandler { id: fnh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.findNext(parent.modelData.d) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.l
                    }
                }
            }
        }
    }
    function findNext(d) {
        if (!findHits.length) return
        findIndex = (findIndex + d + findHits.length) % findHits.length
        list.positionViewAtIndex(findHits[findIndex], ListView.Center)
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
                        TapHandler { onTapped: Qt.openUrlExternally(modelData.share_url || modelData.object_url) }
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
        sourceComponent: WebApp { showHeader: false; pageOnly: true; location: root.chatName + (root.teamName ? " · " + root.teamName : ""); appName: root.webTab ? root.webTab.name : ""; home: root.webTab ? root.webTab.url : "" }
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
        else if (key === "reloadTab") root.reloadTab(t)
        else if (key === "aboutTab") aboutDialog.start(t)
    }
    signal reloadTab(var t)
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
    // About this tab (Teams' About dialog, as measured): padding 27/32/42,
    // the app's name as a 20 px semibold title and a close button; the
    // app's 36 px logo (radius 4) beside its description and developer
    // link; then the identity note (not full trust) and the privacy line.
    Popup {
        id: aboutDialog
        property var tab: null
        readonly property var about: {
            const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
            return r && tab && r.app === tab.app_id && r.about ? r.about : null
        }
        function start(t) { tab = t; backend.appAboutLoad(t.app_id); open() }
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600
        topPadding: 27; leftPadding: 32; rightPadding: 32; bottomPadding: 42
        height: Math.min(implicitHeight, (Overlay.overlay ? Overlay.overlay.height : 800) - 48)
        background: FluentSurface { depth: 64; radius: 8 }
        contentItem: Flickable {
            implicitHeight: aboutCol.implicitHeight
            contentHeight: aboutCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: aboutCol
                width: parent.width
                spacing: 16
                Item {
                    width: parent.width; height: 31.3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: aboutDialog.about ? aboutDialog.about.name : ""
                        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 32; height: 31.3; radius: 4
                        color: aboutClose.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: aboutClose; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: aboutDialog.close() }
                        Accessible.role: Accessible.Button; Accessible.name: "Close"
                    }
                }
                Row {
                    width: parent.width
                    spacing: 15
                    Image {
                        width: 36; height: 36
                        source: aboutDialog.about ? aboutDialog.about.icon : ""
                        sourceSize: Qt.size(72, 72)
                        // Teams rounds the logo's corners (4 px).
                        RoundedCorners { anchors.fill: parent; radius: 4; background: theme.menu }
                    }
                    Column {
                        width: parent.width - 36 - 15
                        spacing: 0
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            // Teams' converted description; its own links keep
                            // the browser default (#0000EE), as Teams shows them.
                            textFormat: Text.RichText
                            text: aboutDialog.about ? aboutDialog.about.description : ""
                            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                            linkColor: "#0000EE"
                            onLinkActivated: link => { if (/^https:/.test(link)) Qt.openUrlExternally(link) }
                        }
                        Text {
                            visible: !!aboutDialog.about && !!aboutDialog.about.developer && !!aboutDialog.about.developer_url
                            textFormat: Text.StyledText
                            text: aboutDialog.about ? "<a href=\"" + aboutDialog.about.developer_url + "\">" + aboutDialog.about.developer + "</a>" : ""
                            font.family: theme.font; font.pixelSize: theme.base
                            linkColor: theme.brandLink
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
                Column {
                    visible: !!aboutDialog.about && aboutDialog.about.needs_identity
                    width: parent.width
                    Text { width: parent.width; wrapMode: Text.Wrap; text: (aboutDialog.about ? aboutDialog.about.name : "") + " needs access to:"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.text }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Team member's email addresses and information that can identify your team and organization name. Data may be sent to a third-party service"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                Text {
                    visible: !!aboutDialog.about && !!aboutDialog.about.privacy_url && !!aboutDialog.about.terms_url
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: aboutDialog.about ? "By using this tab, you agree to the developer's <a href=\"" + aboutDialog.about.privacy_url + "\">privacy policy</a> and <a href=\"" + aboutDialog.about.terms_url + "\">terms of use</a>." : ""
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    linkColor: theme.brandLink
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }
    }
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
    function tabMenuForTest(name) { const t = root.channelTabs.find(x => x.name === name); return t ? t.menu.map(e => e.enabled ? e.key : e.key + "(off)") : [] }
    function tabMenuShowForTest(name) { const i = root.tabNames.indexOf(name); const t = root.channelTabs[i]; if (t) tabMenu.show(t, t.menu, tabs.children[i], 0, 56) }
    function tabMenuCloseForTest() { tabMenu.close() }
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
    function addFiles(urls) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    // Send what's in the compose box: text, files, or both.
    function sendCompose() {
        backend.setReplyQuote(root.quoting ? JSON.stringify(root.quoting) : "")
        backend.setNextImportance(compose.importance)
        if (root.pendingFiles.length > 0) {
            backend.sendFiles(root.pendingFiles.join("\n"), root.plainText())
            root.pendingFiles = []
        } else if (compose.mediaInUse().length > 0) {
            // Picked emoticons, GIFs and stickers go in Teams' own form.
            backend.sendRichMedia(input.getFormattedText(0, input.length), JSON.stringify(compose.mediaInUse()))
        } else if (root.plainText().trim().length > 0) {
            // Formatted text goes as Teams HTML; plain text as before.
            const html = input.getFormattedText(0, input.length)
            if (/font-weight:\s*[6-9]00|font-style:\s*italic|text-decoration:[^;"]*(underline|line-through)|<ul|<ol|href="mention[-:]/.test(html)) backend.sendRich(html)
            else root.send(root.plainText())
        }
        compose.clear()
        root.quoting = null
        compose.formatting = false
        compose.importance = ""
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
    // The message ··· menu (Teams' registry order; the hover bar's own
    // actions are left out when it opens from there, kept on right-click).
    function messageMenuItems(m, rightClick, context) {
        const own = m.mine === true
        const out = []
        const save = m.saved
            ? { key: "unsave", label: "Unsave this message", icon: "bookmark-20-filled", keys: "S" }
            : { key: "save", label: "Save this message", icon: "bookmark-20", keys: "S" }
        const translate = m.translated
            ? { key: "original", label: m.translated_from ? "See original message (" + m.translated_from + ")" : "See original message", icon: "translate-20" }
            : { key: "translate", label: "Translate", icon: "translate-20" }
        // Channel posts and replies (measured in a classic channel; Edit and
        // Reply with quote are on the hover bar). Share to Outlook, Open
        // conversation in new window and Immersive Reader are not built yet.
        if (context === "post" || context === "reply") {
            if (rightClick && own) out.push({ key: "edit", label: "Edit", icon: "edit-20", keys: "E" })
            if (rightClick && !own) out.push({ key: "reply", label: "Reply with quote", icon: "quote-reply-20", keys: "Q" })
            out.push({ key: "forward", label: "Forward", icon: "share-forward-20", keys: "F" })
            if (context === "post") out.push(m.following
                ? { key: "unfollow", label: "Unfollow thread", icon: "chat-multiple-minus-20" }
                : { key: "follow", label: "Follow thread", icon: "chat-multiple-20" })
            out.push({ key: "copy-link", label: "Copy link", icon: "link-20" })
            out.push(save)
            if (own) out.push({ key: "delete", label: "Delete", icon: "delete-menu-20", keys: "Del" })
            if (context === "post") out.push(m.pinned
                ? { key: "unpin", label: "Unpin for everyone", icon: "pin-off-20", keys: "P" }
                : { key: "pin", label: "Pin for everyone", icon: "pin-20", keys: "P" })
            out.push({ separator: true })
            if (context === "post") out.push({ key: "unread", label: "Mark as unread", icon: "mail-unread-20", keys: "U" })
            out.push(translate)
            out.push({ separator: true })
            out.push({ key: "more", label: "More actions", chevron: true, enabled: false })
            return out
        }
        // Core items, in Teams' registry order.
        if (rightClick || own) out.push({ key: "reply", label: "Reply with quote", icon: "quote-reply-20", keys: "Q" })
        if (rightClick && own) out.push({ key: "edit", label: "Edit", icon: "edit-20", keys: "E" })
        out.push({ key: "forward", label: "Forward", icon: "share-forward-20", keys: "F" })
        out.push({ key: "copy-link", label: "Copy link", icon: "link-20" })
        out.push(save)
        if (own) out.push({ key: "delete", label: "Delete", icon: "delete-menu-20", keys: "Del" })
        out.push(m.pinned
            ? { key: "unpin", label: "Unpin for everyone", icon: "pin-off-20", keys: "P" }
            : { key: "pin", label: "Pin for everyone", icon: "pin-20", keys: "P" })
        // Read by N of M: your messages in group chats, once the readers
        // are known; disabled when nobody has read it.
        const r = root.readersFor(m.id)
        if (own && root.isGroup && r) out.push(r.total === 0
            ? { key: "read", label: "No receipt info available", icon: "read-receipt-20", enabled: false }
            : { key: "read", label: "Read by " + r.readers.length + " of " + r.total, icon: "read-receipt-20", chevron: r.readers.length > 0, enabled: r.readers.length > 0 })
        // Secondary items.
        out.push({ separator: true })
        out.push({ key: "unread", label: "Mark as unread", icon: "mail-unread-20", keys: "U" })
        // Chats: the Translation submenu.
        out.push({ key: "translation", label: "Translation", icon: "translate-20", chevron: true })
        // Report this message: someone else's, with its own divider.
        if (!own) {
            out.push({ separator: true })
            out.push({ key: "report", label: "Report this message", icon: "report-message-20" })
        }
        // More actions: the rest of the secondary items and apps' actions;
        // disabled while that list is empty.
        out.push({ separator: true })
        out.push({ key: "more", label: "More actions", chevron: true, enabled: false })
        return out
    }
    function readersFor(id) {
        const r = backend.messageReadersJson ? JSON.parse(backend.messageReadersJson) : null
        return r && r.message_id === id ? r : null
    }
    // Whether the ··· menu is open for this message (keeps its hover bar up).
    function menuOpenFor(id, context) { return forceChannelBarId === id || messageMenu.opened && !messageMenu.rightClick && !!messageMenu.message && messageMenu.message.id === id && messageMenu.context === context }
    function openMessageMenu(m, anchor, rightClick, px, py, context) {
        if (m.mine && root.isGroup) backend.loadMessageReaders(m.id)
        messageMenu.message = m
        messageMenu.rightClick = rightClick
        messageMenu.context = context || "chat"
        messageMenu.items = messageMenuItems(m, rightClick, messageMenu.context)
        messageMenu.parent = anchor
        messageMenu.x = rightClick ? px : anchor.width - messageMenu.implicitWidth
        messageMenu.y = py
        messageMenu.open()
    }
    MenuPopup {
        id: messageMenu
        property var message: null
        property bool rightClick: false
        property string context: "chat"
        labelInset: 32; separatorHeight: 8.6
        chevronSize: 20; chevronMargin: 5.6; keysMargin: 8
        margins: 8
        header: rightClick ? reactionStrip : null
        // The readers' list arrives after the menu opens.
        Connections {
            target: backend
            function onMessageReadersJsonChanged() {
                if (messageMenu.opened && messageMenu.message) messageMenu.items = root.messageMenuItems(messageMenu.message, messageMenu.rightClick, messageMenu.context)
            }
        }
        onPicked: i => {
            const it = items[i], m = message
            if (it.key === "reply") root.replyWithQuote(m)
            else if (it.key === "edit") root.startEdit(m)
            else if (it.key === "delete") root.deleteMessage(m.id)
            else if (it.key === "forward") { forwardDialog.message = m; forwardDialog.open() }
            else if (it.key === "report") { backend.reportResult = ""; reportDialog.message = m; reportDialog.open() }
            else if (it.key === "copy-link") backend.copyMessageLink(JSON.stringify({ id: m.id, sender: m.sender || "", text: m.text || "", root_id: m.root_id || "" }), JSON.stringify({ team_id: root.teamId, team_name: root.teamName, channel_name: root.isChannel ? root.chatName : "" }))
            else if (it.key === "save" || it.key === "unsave") backend.setMessageSaved(m.id, it.key === "save")
            else if (it.key === "pin" || it.key === "unpin") backend.setMessagePinned(m.id, it.key === "pin")
            else if (it.key === "unread") backend.markMessageUnread(m.id, m.client_message_id || "")
            else if (it.key === "follow" || it.key === "unfollow") backend.setThreadFollowing(m.id, it.key === "follow")
            else if (it.key === "translate" || it.key === "original") backend.translateMessage(m.id, it.key === "translate")
            else if (it.key === "translation") {
                translationMenu.message = m
                translationMenu.items = [m.translated
                    ? { key: "original", label: m.translated_from ? "See original message (" + m.translated_from + ")" : "See original message", icon: "translate-20" }
                    : { key: "translate", label: "Translate", icon: "translate-20" }]
                translationMenu.parent = messageMenu.parent; translationMenu.x = messageMenu.x + messageMenu.width; translationMenu.y = messageMenu.y; translationMenu.open()
            }
            else if (it.key === "read") { readersMenu.items = root.readersFor(m.id).readers.map(x => ({ key: x.mri, label: x.name })); readersMenu.parent = messageMenu.parent; readersMenu.x = messageMenu.x + messageMenu.width; readersMenu.y = messageMenu.y; readersMenu.open() }
        }
    }
    ReportDialog { id: reportDialog }
    ForwardDialog {
        id: forwardDialog
        onForwardTo: (targets, note) => backend.forwardMessage(message.id, JSON.stringify(targets), note)
    }
    // Translation ▸: Translate, or See original message.
    MenuPopup {
        id: translationMenu
        property var message: null
        margins: 8
        onPicked: i => backend.translateMessage(message.id, items[i].key === "translate")
    }
    // Read by N of M's readers: one row per reader; a click opens a 1:1
    // chat with them.
    MenuPopup {
        id: readersMenu
        margins: 8
        onPicked: i => backend.openChatWith(items[i].key.replace(/^8:orgid:/, ""), items[i].label)
    }
    // The right-click menu's reaction strip: the quick reactions and More
    // reactions, 31.3 tall.
    Component {
        id: reactionStrip
        Row {
            height: 31.3
            x: 2
            Repeater {
                model: root.quickReactions
                Item {
                    id: stripBtn
                    required property string modelData
                    width: 32; height: 31
                    Emoticon {
                        anchors.centerIn: parent; key: stripBtn.modelData; named: "medium"; size: 20
                        scale: stripHover.hovered ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                    }
                    readonly property bool pressedNow: messageMenu.message ? (messageMenu.message.reactions || []).some(r => r.mine && r.my_key === stripBtn.modelData) : false
                    PressedLine { visible: stripBtn.pressedNow }
                    HoverHandler { id: stripHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const m = messageMenu.message
                            const mine = (m.reactions || []).filter(r => r.mine).length
                            const on = !stripBtn.pressedNow
                            if (on && mine >= root.reactionLimit) return
                            messageMenu.close(); root.react(m.id, stripBtn.modelData, on)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: backend.emoticonName(modelData)
                }
            }
            BarButton { icon: "emoji-add-20"; tip: "More reactions"; onClicked: { const m = messageMenu.message; const a = messageMenu.parent; messageMenu.close(); root.openReactionPicker(m.id, a) } }
        }
    }
    // Teams' reaction picker, opened from the hover bar or a message's
    // add-reaction button.
    // Above its anchor, start-aligned, kept inside the window (Teams: the
    // picker opened from the hover bar sits over the bar, 8 before it).
    // Who reacted: hovering a pill opens it after 300 ms (below, 4 off,
    // centred); leaving the pill and the list closes it.
    WhoReacted {
        id: whoReacted
        onRemoveMine: (id, key) => root.react(id, key, false)
        onHoveredChanged: if (!hovered && !focus) whoCloseTimer.restart()
    }
    property var whoPending: null
    Timer {
        id: whoOpenTimer
        interval: 300
        onTriggered: if (root.whoPending) root.openWhoReacted(root.whoPending.pill, root.whoPending.id, root.whoPending.reaction, false, root.whoPending.overflow)
    }
    Timer {
        id: whoCloseTimer
        interval: 200
        onTriggered: if (whoReacted.opened && !whoReacted.hovered && !whoReacted.focus) whoReacted.close()
    }
    function hoverWhoReacted(pill, id, reaction, overflow) {
        whoCloseTimer.stop()
        whoPending = { pill: pill, id: id, reaction: reaction, overflow: overflow || [] }
        whoOpenTimer.restart()
    }
    function leaveWhoReacted() {
        whoOpenTimer.stop()
        whoPending = null
        if (whoReacted.opened && !whoReacted.focus) whoCloseTimer.restart()
    }
    function openWhoReacted(pill, id, reaction, withFocus, overflow) {
        whoOpenTimer.stop()
        whoReacted.close()
        whoReacted.parent = pill
        whoReacted.messageId = id
        whoReacted.reaction = reaction
        // The overflow list: everyone behind "+N", pill by pill.
        const users = []
        if (!reaction) for (const r of Array.from(overflow || [])) for (const u of Array.from(r.users)) users.push(u)
        whoReacted.overflowUsers = users
        whoReacted.focus = withFocus
        whoReacted.x = (pill.width - whoReacted.width) / 2
        whoReacted.y = pill.height + 4.3
        whoReacted.open()
    }
    ReactionPicker {
        id: reactionPicker
        x: -8
        y: -height - 4
        margins: 8
        onPicked: (key, on) => { if (!on || mine.length < root.reactionLimit || mine.some(r => r.key === root.commonKey(key))) root.react(messageId, key, on) }
        onCustomize: customizeReactions.open()
        onAddCustomEmoji: customEmojiAdd.start()
    }
    CustomizeReactions {
        id: customizeReactions
    }
    FunPicker {
        id: emojiPicker
        parent: compose
        x: parent ? parent.width - width : 0; y: -height - 8
        // Emoticons show in the compose box as Teams' own 20 px picture;
        // custom emoji ("{name};{documentId}") as their cached picture.
        onPickedEmoji: id => {
            const sep = id.indexOf(";")
            if (sep > 0) {
                const name = id.slice(0, sep), doc = id.slice(sep + 1), file = backend.emoticonUrl(id, 20)
                if (!file) { (root.emojiTarget || compose).insertText(":" + name + ":"); return }
                root.insertPicked({ src: file, kind: "custom", id: id, title: name, url: backend.customEmojiSendUrl(doc) })
                return
            }
            root.insertPicked({
                src: "https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/" + id + "/default/20_f.png",
                kind: "emoji", id: id, title: backend.emoticonName(id), unicode: backend.emoticonUnicode(id) })
        }
        onAddCustomEmoji: customEmojiAdd.start()
        onPickedGif: g => root.insertPicked({ src: g.preview, kind: "gif", url: g.url, width: g.width, height: g.height, title: g.title })
        onPickedSticker: st => root.insertPicked({ src: st.preview, kind: "sticker", url: st.url, title: st.title })
        onPickedCaptioned: m => root.insertPicked(m)
        onCustomize: customizeReactions.open()
    }
    // Teams' Add emoji flow (file, resize, "Name your emoji").
    CustomEmojiAdd { id: customEmojiAdd }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }

    // The chat's compose (Teams' simplified compose; ComposeBox). It sits
    // 72 in on each side, 6 above the bottom, its hint row included.
    ComposeBox {
        id: compose
        visible: root.chatName.length > 0 && (!root.isChannel || root.posting)
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: root.pane ? 12 : 72; anchors.rightMargin: root.pane ? 12 : 72; anchors.bottomMargin: 6
        placeholder: root.isChannel ? "Start a post" : "Type a message"
        quote: root.quoting
        files: root.pendingFiles
        onQuoteDismissed: root.quoting = null
        onFileRemoved: path => root.pendingFiles = root.pendingFiles.filter(p => p !== path)
        onEmojiRequested: a => root.openEmojiFor(compose)
        onAttachRequested: filePicker.open()
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
        // A team is mentioned by its thread id, its General channel's.
        teamMention: {
            if (!root.isChannel || !root.teamId) return null
            const t = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === root.teamId)
            const general = t ? (t.channels.find(c => c.name === "General") || t.channels[0]) : null
            return general ? { id: general.id, name: root.teamName, groupId: root.teamId } : null
        }
        readonly property var roster: backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []
        memberCount: roster.length
        mentionables: roster.filter(m => !m.me).map(m => ({ mri: m.mri, name: m.name, mail: m.mail }))
        urgentAllowed: !root.isGroup || (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson).length : 0) <= 20
        onScheduleMeetingRequested: root.scheduleMeeting()
        onCancelled: { root.quoting = null; root.pendingFiles = []; root.posting = false; if (root.draftChat) backend.setDraft(root.draftChat, "") }
        Connections {
            target: compose.editor
            function onTextChanged() { draftSave.restart() }
        }
    }
}
