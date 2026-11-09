import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// The message actions of a conversation view, as Teams has them: the
// hover bar's and ReactionSummary's host. It holds the quick reactions and
// the reaction limit, the ··· and right-click menus, the reaction picker,
// who reacted, the fun picker, Forward and Report, and in-place edit state.
// Conversation has one for the open chat; a thread window has its own, so
// its menus and pickers open in that window. Message actions go to the
// backend by message id (it acts where that message is shown).
Item {
    id: root
    /// The messages shown (for a message's reactions by id).
    property var messages: []
    /// Where the messages are (Copy link and the menus' rules).
    property bool isGroup: false
    property bool isChannel: false
    property string teamId: ""
    property string teamName: ""
    property string chatName: ""
    /// The compose box the fun picker inserts into by default.
    property var defaultBox: null
    /// Test hook: keep the ··· menu's hover bar of this message up.
    property string forceChannelBarId: ""
    /// Posts offer "Open conversation in new window" (not in that window).
    property bool canPopOut: false
    signal threadWindowRequested(var post)
    signal quoteRequested(var message)
    signal reactRequested(string messageId, string key, bool on)
    signal deleteRequested(string messageId)
    function replyWithQuote(m) { root.quoteRequested(m) }
    function react(id, key, on) { root.reactRequested(id, key, on) }
    signal openChatSettings()
    // The popups, for test hooks.
    readonly property alias messageMenu: messageMenu
    readonly property alias reactionPicker: reactionPicker
    readonly property alias customizeReactions: customizeReactions
    readonly property alias customEmojiAdd: customEmojiAdd
    readonly property alias emojiPicker: emojiPicker
    readonly property alias forwardDialog: forwardDialog
    readonly property alias reportDialog: reportDialog

    // Teams' quick reactions: the user's defaultMessageReactions, else the
    // live default (547607).
    // With a skin tone set, Like shows in it (547607 `x`).
    readonly property var quickReactions: (backend.quickReactionsJson ? JSON.parse(backend.quickReactionsJson) : ["yes", "heart", "laugh", "surprised"])
        .map(k => root.commonKey(k) === "yes" && backend.skinTone > 0 ? "yes-tone" + backend.skinTone : k)
    // Test hook: opens the who-reacted list of this message's first pill.
    property string forceWhoId: ""
    // Test hook: opens the overflow list ("+N") of this message.
    property string forceWhoOverflowId: ""
    property string editingId: ""
    // Teams edits in place; Urgent messages can't be edited.
    function startEdit(m) { if (m.importance !== "urgent") root.editingId = m.id }
    // The emoji picker inserts into whichever compose asked for it.
    property var emojiTarget: null
    function openEmojiFor(box) { emojiTarget = box; emojiPicker.parent = box; emojiPicker.open() }
    // The fun picker's picks go into the box it was opened from: GIFs and
    // stickers as pictures, emoticons as Teams' inline emoticons (as text
    // where the box sends plain text).
    function insertPicked(m) {
        const box = root.emojiTarget || root.defaultBox
        if (box === root.defaultBox) box.insertMedia(m)
        else if (m.kind === "emoji") box.insertText(m.unicode)
    }
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
    function openReactionPicker(messageId, anchor) {
        const m = (root.messages || []).find(x => x.id === messageId)
        reactionPicker.mine = m ? (m.reactions || []).filter(r => r.mine) : []
        reactionPicker.messageId = messageId; reactionPicker.parent = anchor; reactionPicker.open()
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
        // Reply with quote are on the hover bar). Share to Outlook and
        // Immersive Reader are not built yet.
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
            if (context === "post" && root.canPopOut) out.push({ key: "popout", label: "Open conversation in new window", icon: "window-new-20" })
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
            else if (it.key === "delete") root.deleteRequested(m.id)
            else if (it.key === "forward") { forwardDialog.message = m; forwardDialog.open() }
            else if (it.key === "report") { backend.reportResult = ""; reportDialog.message = m; reportDialog.open() }
            else if (it.key === "copy-link") backend.copyMessageLink(JSON.stringify({ id: m.id, sender: m.sender || "", text: m.text || "", root_id: m.root_id || "" }), JSON.stringify({ team_id: root.teamId, team_name: root.teamName, channel_name: root.isChannel ? root.chatName : "" }))
            else if (it.key === "save" || it.key === "unsave") backend.setMessageSaved(m.id, it.key === "save")
            else if (it.key === "pin" || it.key === "unpin") backend.setMessagePinned(m.id, it.key === "pin")
            else if (it.key === "unread") backend.markMessageUnread(m.id, m.client_message_id || "")
            else if (it.key === "follow" || it.key === "unfollow") backend.setThreadFollowing(m.id, it.key === "follow")
            else if (it.key === "popout") root.threadWindowRequested(m)
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
        parent: root.defaultBox
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
    // Teams' post indicator (763654 `L`, measured): which highlight a post
    // or reply gets, in Teams' order: pinned, mentions you (Important or
    // Urgent shown instead), @Everyone, Important, Urgent, a channel or
    // team mention, then your own. {color, icon ("" for a bar only), tip}.
    function highlight(m) {
        if (!m || m.deleted) return null
        const orange = theme.mentionMe, red = theme.danger
        const important = { color: red, icon: "badge-important-16", tip: "Important" }
        const urgent = { color: red, icon: "badge-urgent-16", tip: "Urgent" }
        if (m.pinned) return { color: theme.pick("#237B4B", "#92C353"), icon: "badge-pin-16", tip: "Pinned" }
        const k = m.mention_kind || ""
        if (k === "me") return m.importance === "high" ? important : m.importance === "urgent" ? urgent : { color: orange, icon: "badge-mention-16", tip: "Mentions you" }
        if (k === "everyone") return { color: orange, icon: "badge-everyone-16", tip: "Mentions everyone" }
        if (m.importance === "high") return important
        if (m.importance === "urgent") return urgent
        if (k === "channel") return { color: orange, icon: "badge-channel-16", tip: "Channel message" }
        if (k === "team") return { color: orange, icon: "badge-team-16", tip: "Team message" }
        if (m.mine) return { color: theme.brand, icon: "", tip: "" }
        return null
    }
    // Teams' relative dates, as in chats.
    function conversationStamp(t) {
        const d = new Date(t), now = new Date()
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        const time = Qt.formatTime(d, "h:mm AP")
        if (days === 0) return time
        if (days === 1) return "Yesterday " + time
        if (days > 1 && days < 7) return Qt.formatDate(d, "dddd") + " " + time
        if (d.getFullYear() === now.getFullYear()) return Qt.formatDate(d, "M/d") + " " + time
        return Qt.formatDate(d, "M/d/yyyy") + " " + time
    }
    // Whole days between a date and today.
    function daysAgo(d) {
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const now = new Date()
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        return Math.round((b - a) / 86400000)
    }
    // A day divider's label (Today, Yesterday, the weekday, the date).
    function dayLabel(t) {
        const d = new Date(t), n = daysAgo(d)
        if (n === 0) return "Today"
        if (n === 1) return "Yesterday"
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd")
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "MMMM d")
        return Qt.formatDate(d, "MMMM d, yyyy")
    }
}
