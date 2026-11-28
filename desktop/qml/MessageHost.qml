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
    /// An edit box here may record a video clip (its "+"); the recorder
    /// fills the box that asked.
    property bool canRecordClip: false
    signal recordClipRequestedFor(Item box)
    function recordClipFor(box) { recordClipRequestedFor(box) }
    /// The conversation's id (Share to Outlook), and whether it is your
    /// notes-to-self chat.
    property string chatId: backend.currentChatId
    property bool isSelfChat: chatId.indexOf("48:notes") === 0
    /// Share to Outlook's draft body: "SingleMessage" in a Threads-layout
    /// channel (Teams' `kn`: ConvUX), else Teams leaves it out.
    property string stoBodyType: ""
    /// The compose box the fun picker inserts into by default.
    property var defaultBox: null
    /// Test hook: keep the ··· menu's hover bar of this message up.
    property string forceChannelBarId: ""
    /// Posts offer "Open conversation in new window" (not in that window).
    property bool canPopOut: false
    /// Ask Copilot (Teams' ask-copilot: a Microsoft 365 Copilot licence,
    /// the conversation's Copilot side pane): the view sets it where its
    /// Copilot pane can open, and opens it on askCopilotRequested.
    property bool canAskCopilot: false
    signal askCopilotRequested(var message)
    /// Forward ▸ Multiple messages (Teams' forward multiselect): which
    /// contexts the view can select messages in ("chat", "post", "reply").
    property var multiselectContexts: []
    signal multiselectRequested(var message, string context)
    signal threadWindowRequested(var post)
    signal quoteRequested(var message)
    signal reactRequested(string messageId, string key, bool on)
    signal deleteRequested(string messageId)
    function replyWithQuote(m) { root.quoteRequested(m) }
    /// Quick views ▸ Discover's cards: their ··· adds "Don't show …"
    /// (`discoverHide`: "POST", "AUTHOR" or "CHANNEL").
    property bool discoverActions: false
    property string authorName: ""
    signal discoverHide(string kind)
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
    readonly property string limitText: qsTr("You’ve reached the %1-reaction limit. Remove one to add another.").arg(reactionLimit)
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
    readonly property var toneWords: ["", qsTr("light"), qsTr("medium light"), qsTr("medium"), qsTr("medium dark"), qsTr("dark")]
    function pillLabel(r) {
        const name = backend.emoticonName(r.key)
        const n = r.count
        const tones = (r.variants || [r.key]).map(k => { const m = /-tone(\d)$/.exec(k); return m ? Number(m[1]) : 0 })
        if (tones.length === 1 && tones[0] === 0) return qsTr("%n %1 reactions.", "", n).arg(name)
        if (tones.length === 1) return qsTr("%n %1 reactions with %2 skin tone.", "", n).arg(name).arg(toneWords[tones[0]])
        const words = tones.map(t => t === 0 ? qsTr("no") : toneWords[t])
        return qsTr("%n %1 reactions with %2 and %3 skin tones.", "", n).arg(name).arg(words.slice(0, -1).join(", ")).arg(words[words.length - 1])
    }
    // Teams' common key: the id without its skin tone.
    function commonKey(id) { const m = /^(.{1,40})-tone\d$/.exec(id); return m ? m[1] : id }
    function openReactionPicker(messageId, anchor) {
        const m = (root.messages || []).find(x => x.id === messageId)
        reactionPicker.mine = m ? (m.reactions || []).filter(r => r.mine) : []
        reactionPicker.messageId = messageId; reactionPicker.parent = anchor; reactionPicker.open()
    }
    // Forward: Teams' split item where messages can be selected (Forward,
    // then a chevron part, "Forward options", opening This message /
    // Multiple messages); a plain item elsewhere.
    function forwardItem(m, context) {
        const it = { key: "forward", label: qsTr("Forward"), icon: "share-forward-20", keys: "F" }
        if ((root.multiselectContexts || []).indexOf(context) < 0) return it
        return Object.assign(it, { split: true, splitLabel: qsTr("Forward options"), submenu: [
            { key: "forward-one", label: qsTr("This message") },
            { key: "forward-many", label: qsTr("Multiple messages") }] })
    }
    // Remind me ▸ (Teams' reminder item, 629737 `Tn`): ReminderPresets'
    // submenu; Edit reminder, with Remove reminder, once one is set. Not in
    // your notes to self (enableRemindersSliceForSelfChat is off).
    ReminderPresets { id: presets }
    function reminderItem(m) {
        if (root.isSelfChat) return null
        const t = presets.times(new Date())
        const set = (m.reminder_due || 0) > 0
        return { key: "reminder", label: set ? qsTr("Edit reminder") : qsTr("Remind me"), icon: "clock-alarm-20", submenu: presets.submenu(t, set), times: t }
    }
    // The message ··· menu (Teams' registry order; the hover bar's own
    // actions are left out when it opens from there, kept on right-click).
    function messageMenuItems(m, rightClick, context) {
        // A scheduled message (Teams: Delete, which cancels it, and
        // Translation; translating it before it's sent isn't built).
        if (m.scheduled_at) return [{ key: "delete-scheduled", label: qsTr("Delete"), icon: "delete-menu-20", keys: "Del" }]
        const own = m.mine === true
        const out = []
        const save = m.saved
            ? { key: "unsave", label: qsTr("Unsave this message"), icon: "bookmark-20-filled", keys: "S" }
            : { key: "save", label: qsTr("Save this message"), icon: "bookmark-20", keys: "S" }
        const translate = m.translated
            ? { key: "original", label: m.translated_from ? qsTr("See original message (%1)").arg(m.translated_from) : qsTr("See original message"), icon: "translate-20" }
            : { key: "translate", label: qsTr("Translate"), icon: "translate-20" }
        // A Discover card's post (Teams web 2026-11-27, OST Test 2): Forward,
        // Follow thread, Copy post link, Save this message, Don't show this
        // post again, Don't show posts from {author}, Don't show posts from
        // {channel} | Share to Outlook, Translate, Immersive Reader | Report
        // this message | More actions.
        if (context === "discover") {
            out.push({ key: "forward", label: qsTr("Forward"), icon: "share-forward-20", keys: "F" })
            out.push(m.following
                ? { key: "unfollow", label: qsTr("Unfollow thread"), icon: "chat-multiple-minus-20" }
                : { key: "follow", label: qsTr("Follow thread"), icon: "chat-multiple-20" })
            out.push({ key: "copy-link", label: qsTr("Copy post link"), icon: "link-20" })
            out.push(save)
            out.push({ key: "discover-post", label: qsTr("Don't show this post again"), icon: "eye-off-20" })
            if (!own) out.push({ key: "discover-author", label: qsTr("Don't show posts from %1").arg(m.sender || root.authorName), icon: "discover-hide-person-20" })
            out.push({ key: "discover-channel", label: qsTr("Don't show posts from %1").arg(root.chatName), icon: "discover-hide-channel-20" })
            out.push({ separator: true })
            out.push({ key: "share-outlook", label: qsTr("Share to Outlook"), icon: "mail-20" })
            out.push(translate)
            out.push({ key: "immersive-reader", label: qsTr("Immersive Reader"), icon: "read-aloud-20" })
            if (!own) {
                out.push({ separator: true })
                out.push({ key: "report", label: qsTr("Report this message"), icon: "report-message-20" })
            }
            out.push({ separator: true })
            out.push({ key: "more", label: qsTr("More actions"), chevron: true })
            return out
        }
        // Channel posts and replies (measured in a classic channel; Edit and
        // Reply with quote are on the hover bar).
        if (context === "post" || context === "reply") {
            if (rightClick && own) out.push({ key: "edit", label: qsTr("Edit"), icon: "edit-20", keys: "E" })
            if (rightClick && !own) out.push({ key: "reply", label: qsTr("Reply with quote"), icon: "quote-reply-20", keys: "Q" })
            out.push(root.forwardItem(m, context))
            if (context === "post") out.push(m.following
                ? { key: "unfollow", label: qsTr("Unfollow thread"), icon: "chat-multiple-minus-20" }
                : { key: "follow", label: qsTr("Follow thread"), icon: "chat-multiple-20" })
            out.push({ key: "copy-link", label: qsTr("Copy link"), icon: "link-20" })
            out.push(save)
            const remindPost = root.reminderItem(m)
            if (remindPost) out.push(remindPost)
            if (own) out.push({ key: "delete", label: qsTr("Delete"), icon: "delete-menu-20", keys: "Del" })
            if (context === "post") out.push(m.pinned
                ? { key: "unpin", label: qsTr("Unpin for everyone"), icon: "pin-off-20", keys: "P" }
                : { key: "pin", label: qsTr("Pin for everyone"), icon: "pin-20", keys: "P" })
            if (root.canAskCopilot && root.askableText(m)) out.push({ key: "ask-copilot", label: qsTr("Ask Copilot"), icon: "ai-copilot" })
            if (context === "post" && root.canPopOut) out.push({ key: "popout", label: qsTr("Open conversation in new window"), icon: "window-new-20" })
            out.push({ separator: true })
            // The secondary items in Teams' registry order (Mark as unread
            // for a post only, Share to Outlook, Translate, Immersive
            // Reader): the first three here, the rest under More actions
            // (seen on Teams web 2026-11-27 as OST Test 2: a post's Immersive
            // Reader is under More actions, a reply's on the menu).
            const secondary = []
            if (context === "post") secondary.push({ key: "unread", label: qsTr("Mark as unread"), icon: "mail-unread-20", keys: "U" })
            secondary.push({ key: "share-outlook", label: qsTr("Share to Outlook"), icon: "mail-20" })
            secondary.push(translate)
            secondary.push({ key: "immersive-reader", label: qsTr("Immersive Reader"), icon: "read-aloud-20" })
            for (const it of secondary.slice(0, 3)) out.push(it)
            // Report this message: someone else's, with its own divider.
            if (!own) {
                out.push({ separator: true })
                out.push({ key: "report", label: qsTr("Report this message"), icon: "report-message-20" })
            }
            // More actions ▸: the rest (apps' actions aren't listed yet), off
            // when there is none, as Teams has it with an empty list.
            const more = secondary.slice(3)
            out.push({ separator: true })
            out.push({ key: "more", label: qsTr("More actions"), chevron: true, enabled: more.length > 0, more: more })
            return out
        }
        // Core items, in Teams' registry order. A personal account's
        // (Teams free, teams.live.com 2026-11-28): Reply, Edit, Forward,
        // Copy link, Delete, Pin for everyone, Mark as unread, Translation;
        // no Save, Remind me, Share to Outlook or More actions.
        const personal = backend.personalAccount
        if (rightClick || own) out.push({ key: "reply", label: personal ? qsTr("Reply") : qsTr("Reply with quote"), icon: personal ? "arrow-reply-20" : "quote-reply-20", keys: "Q" })
        if (rightClick && own) out.push({ key: "edit", label: qsTr("Edit"), icon: "edit-20", keys: "E" })
        out.push(root.forwardItem(m, "chat"))
        out.push({ key: "copy-link", label: qsTr("Copy link"), icon: "link-20" })
        if (!personal) out.push(save)
        const remind = personal ? null : root.reminderItem(m)
        if (remind) out.push(remind)
        if (own) out.push({ key: "delete", label: qsTr("Delete"), icon: "delete-menu-20", keys: "Del" })
        out.push(m.pinned
            ? { key: "unpin", label: qsTr("Unpin for everyone"), icon: "pin-off-20", keys: "P" }
            : { key: "pin", label: qsTr("Pin for everyone"), icon: "pin-20", keys: "P" })
        // Ask Copilot (core, after Pin): a delivered message with text.
        if (root.canAskCopilot && root.askableText(m)) out.push({ key: "ask-copilot", label: qsTr("Ask Copilot"), icon: "ai-copilot" })
        // Read by N of M: your messages in group chats, once the readers
        // are known; disabled when nobody has read it.
        const r = root.readersFor(m.id)
        if (own && root.isGroup && r) out.push(r.total === 0
            ? { key: "read", label: qsTr("No receipt info available"), icon: "read-receipt-20", enabled: false }
            : { key: "read", label: qsTr("Read by %1 of %2").arg(r.readers.length).arg(r.total), icon: "read-receipt-20", chevron: r.readers.length > 0, enabled: r.readers.length > 0 })
        // Secondary items.
        out.push({ separator: true })
        out.push({ key: "unread", label: qsTr("Mark as unread"), icon: "mail-unread-20", keys: "U" })
        // Share to Outlook (measured on Teams on the web: after Mark as
        // unread; not in your notes-to-self chat, where Teams cancels it).
        if (!root.isSelfChat && !personal) out.push({ key: "share-outlook", label: qsTr("Share to Outlook"), icon: "mail-20" })
        // Chats: the Translation submenu.
        out.push({ key: "translation", label: qsTr("Translation"), icon: "translate-20", chevron: true })
        // Report this message: someone else's, with its own divider.
        if (!own) {
            out.push({ separator: true })
            out.push({ key: "report", label: qsTr("Report this message"), icon: "report-message-20" })
        }
        // More actions ▸: Immersive Reader (then apps' actions, not built).
        if (personal) return out
        out.push({ separator: true })
        out.push({ key: "more", label: qsTr("More actions"), chevron: true })
        return out
    }
    function readersFor(id) {
        const r = backend.messageReadersJson ? JSON.parse(backend.messageReadersJson) : null
        return r && r.message_id === id ? r : null
    }
    // Whether the ··· menu is open for this message (keeps its hover bar up).
    // (Closing too: Esc puts the focus back on its ···, which keeps the bar
    // up from then on.)
    function menuOpenFor(id, context) { return forceChannelBarId === id || (messageMenu.opened || messageMenu.closing) && !messageMenu.rightClick && !!messageMenu.message && messageMenu.message.id === id && messageMenu.context === context }
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
        splitChevronSize: 20
        // Teams' Remind me and Forward submenus: 170 wide, no icons.
        submenuMinWidth: 162
        onSubPicked: (i, j) => root.messageSubPicked(items[i], items[i].submenu[j], message)
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
            else if (it.key === "delete-scheduled") backend.cancelScheduled(m.draft_id)
            else if (it.key === "forward") root.forwardOne(m)
            else if (it.key === "ask-copilot") root.askCopilotRequested(m)
            else if (it.key === "report") { backend.reportResult = ""; reportDialog.message = m; reportDialog.open() }
            else if (it.key === "copy-link") backend.copyMessageLink(JSON.stringify({ id: m.id, sender: m.sender || "", text: m.text || "", root_id: m.root_id || "" }), JSON.stringify({ team_id: root.teamId, team_name: root.teamName, channel_name: root.isChannel ? root.chatName : "", conversation: root.discoverActions ? root.chatId : "" }))
            else if (it.key === "save" || it.key === "unsave") backend.setMessageSaved(m.id, it.key === "save")
            else if (it.key === "pin" || it.key === "unpin") backend.setMessagePinned(m.id, it.key === "pin")
            else if (it.key === "unread") backend.markMessageUnread(m.id, m.client_message_id || "")
            else if (it.key === "follow" || it.key === "unfollow") backend.setThreadFollowing(m.id, it.key === "follow")
            else if (it.key === "popout") root.threadWindowRequested(m)
            else if (it.key === "translate" || it.key === "original") backend.translateMessage(m.id, it.key === "translate")
            else if (it.key === "translation") {
                translationMenu.message = m
                translationMenu.items = [m.translated
                    ? { key: "original", label: m.translated_from ? qsTr("See original message (%1)").arg(m.translated_from) : qsTr("See original message"), icon: "translate-20" }
                    : { key: "translate", label: qsTr("Translate"), icon: "translate-20" }]
                translationMenu.parent = messageMenu.parent; translationMenu.x = messageMenu.x + messageMenu.width; translationMenu.y = messageMenu.y; translationMenu.open()
            }
            else if (it.key === "share-outlook") shareToOutlook.start(m)
            else if (it.key === "immersive-reader") root.openImmersiveReader(m)
            else if (it.key === "discover-post") root.discoverHide("POST")
            else if (it.key === "discover-author") root.discoverHide("AUTHOR")
            else if (it.key === "discover-channel") root.discoverHide("CHANNEL")
            else if (it.key === "more") {
                moreActionsMenu.message = m
                moreActionsMenu.items = it.more || [{ key: "immersive-reader", label: qsTr("Immersive Reader"), icon: "read-aloud-20" }]
                moreActionsMenu.parent = messageMenu.parent; moreActionsMenu.x = messageMenu.x - moreActionsMenu.implicitWidth; moreActionsMenu.y = messageMenu.y + messageMenu.height - 40; moreActionsMenu.open()
            }
            else if (it.key === "read") { readersMenu.items = root.readersFor(m.id).readers.map(x => ({ key: x.mri, label: x.name })); readersMenu.parent = messageMenu.parent; readersMenu.x = messageMenu.x + messageMenu.width; readersMenu.y = messageMenu.y; readersMenu.open() }
        }
    }
    ReportDialog { id: reportDialog }
    function forwardOne(m) { forwardDialog.messages = []; forwardDialog.message = m; forwardDialog.open() }
    /// Forward several selected messages (Next in the selection footer).
    function forwardMany(list) {
        if (!list || !list.length) return
        forwardDialog.messages = list
        forwardDialog.message = list[0]
        forwardDialog.open()
    }
    signal forwarded()
    // Remind me: set (or move) the reminder, or remove it; Teams flips the
    // message's marker at once and says "A reminder has been set."
    function setReminder(m, due) { backend.setMessageReminder(m.id, m.root_id || "", Math.round(due.getTime())) }
    function removeReminder(m) { backend.removeMessageReminder(m.id, m.root_id || "") }
    function messageSubPicked(it, sub, m) {
        if (it.key === "forward") {
            if (sub.key === "forward-one") root.forwardOne(m)
            else root.multiselectRequested(m, messageMenu.context)
            return
        }
        if (it.key !== "reminder") return
        const at = presets.at(sub.key, it.times)
        if (at) root.setReminder(m, at)
        else if (sub.key === "remove") root.removeReminder(m)
        else if (sub.key === "custom") { customReminder.message = m; customReminder.open() }
    }
    CustomReminderDialog {
        id: customReminder
        property var message: null
        due: message && (message.reminder_due || 0) > Date.now() ? new Date(message.reminder_due) : null
        onAdded: when => root.setReminder(message, when)
    }
    readonly property alias customReminderForTest: customReminder
    // The text Ask Copilot hands on (Teams' `ca`): line breaks for <br>
    // and block ends, a quote as `Name: "preview" rest`, a channel post's
    // subject first; empty for messages Teams doesn't offer it on.
    function askableText(m) {
        if (!m || m.deleted || m.send_state || m.kind && m.kind !== "message") return ""
        if ((m.media || []).some(x => x.kind === "audio") || (m.videos || []).length > 0) return ""
        const html = String(m.html || "")
            .replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|li|h[1-6]|pre|blockquote|tr)>/gi, "\n")
        const plain = html.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&").replace(/\n{2,}/g, "\n").trim()
        let text = plain || String(m.text || "").trim()
        if (m.quote && m.quote.text) {
            const name = m.quote.sender && m.quote.sender !== "Display Name" ? m.quote.sender + ": " : ""
            text = name + "\"" + m.quote.text + "\" " + text
        }
        if (m.subject) text = "[Subject: " + m.subject + "] " + text
        return text.trim()
    }
    ForwardDialog {
        id: forwardDialog
        onForwardTo: (targets, note) => {
            if (several) backend.forwardMessages(JSON.stringify(shownMessages.map(m => m.id)), JSON.stringify(targets), note)
            else backend.forwardMessage(message.id, JSON.stringify(targets), note)
            root.forwarded()
        }
    }
    // More actions ▸: Immersive Reader (Teams' L2 items; apps' message
    // actions aren't listed yet).
    MenuPopup {
        id: moreActionsMenu
        property var message: null
        margins: 8
        onPicked: i => { if (items[i].key === "immersive-reader") root.openImmersiveReader(message) }
    }
    // Immersive Reader: Teams' chunks for a message (message-actions.md
    // §10): "<sender> <date> <time> <br/>", the subject when there is one,
    // then the message's HTML; a message with cards gives its raw HTML with
    // each card as text (reader_html, app-host.md "Immersive Reader").
    function openImmersiveReader(m) {
        const d = new Date(m.time || m.timestamp || Date.now())
        const chunks = [{ content: (m.sender || "") + " " + d.toLocaleDateString(Qt.locale("en_US"), "M/d/yyyy") + " " + d.toLocaleTimeString(Qt.locale("en_US"), "h:mm:ss AP") + " <br/>", mimeType: "text/html" }]
        if (m.subject) chunks.push({ content: "<br/>" + m.subject + "<br/>", mimeType: "text/html" })
        chunks.push({ content: m.reader_html || m.html || m.content || m.text || "", mimeType: "text/html" })
        immersiveReader.launch(chunks)
    }
    ImmersiveReader { id: immersiveReader }
    readonly property alias immersiveReaderForTest: immersiveReader
    readonly property alias shareToOutlookForTest: shareToOutlook
    // Share to Outlook: Teams' Outlook dialog (task module) on a draft the
    // middle tier makes of the conversation; closing it discards the draft.
    ShareToOutlookDialog { id: shareToOutlook; threadId: root.chatId; bodyType: root.stoBodyType }
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
    // reactions, 31.3 tall. They are the menu's first keyboard stops (Teams
    // desktop: the menu opens on Like, Down goes through them to Reply with
    // quote, Enter / Space react).
    Component {
        id: reactionStrip
        Row {
            id: strip
            height: 31.3
            x: 2
            readonly property var keyItems: {
                const a = []
                for (let i = 0; i < stripRepeater.count; i++) a.push(stripRepeater.itemAt(i))
                return a.concat([stripMore])
            }
            Repeater {
                id: stripRepeater
                model: root.quickReactions
                Item {
                    id: stripBtn
                    required property string modelData
                    width: 32; height: 31
                    // Fluent's keyboard outline (strokeFocus2, 2 px), once a
                    // key was used (none on the first stop after a click).
                    Rectangle {
                        visible: stripBtn.activeFocus && messageMenu.focusRing
                        anchors.fill: parent; radius: 4; color: "transparent"
                        border.width: 2; border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
                    }
                    function activate() {
                        const m = messageMenu.message
                        const mine = (m.reactions || []).filter(r => r.mine).length
                        const on = !stripBtn.pressedNow
                        if (on && mine >= root.reactionLimit) return
                        messageMenu.close(); root.react(m.id, stripBtn.modelData, on)
                    }
                    Emoticon {
                        anchors.centerIn: parent; key: stripBtn.modelData; named: "medium"; size: 20
                        scale: stripHover.hovered ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                    }
                    readonly property bool pressedNow: messageMenu.message ? (messageMenu.message.reactions || []).some(r => r.mine && r.my_key === stripBtn.modelData) : false
                    PressedLine { visible: stripBtn.pressedNow }
                    HoverHandler { id: stripHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: stripBtn.activate() }
                    Accessible.role: Accessible.Button
                    Accessible.name: backend.emoticonName(modelData)
                }
            }
            BarButton { id: stripMore; focusRingShown: activeFocus && messageMenu.focusRing; icon: "emoji-add-20"; tip: qsTr("More reactions"); onClicked: { const m = messageMenu.message; const a = messageMenu.parent; messageMenu.close(); root.openReactionPicker(m.id, a) } }
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
        const important = { color: red, icon: "badge-important-16", tip: qsTr("Important") }
        const urgent = { color: red, icon: "badge-urgent-16", tip: qsTr("Urgent") }
        if (m.pinned) return { color: theme.pick("#237B4B", "#92C353"), icon: "badge-pin-16", tip: qsTr("Pinned") }
        const k = m.mention_kind || ""
        if (k === "me") return m.importance === "high" ? important : m.importance === "urgent" ? urgent : { color: orange, icon: "badge-mention-16", tip: qsTr("%1 mentioned you.").arg(m.sender || "") }
        if (k === "everyone") return { color: orange, icon: "badge-everyone-16", tip: qsTr("%1 mentioned Everyone", "messaging:kbf6tsfba").arg(m.sender || "") }
        if (m.importance === "high") return important
        if (m.importance === "urgent") return urgent
        if (k === "channel") return { color: orange, icon: "badge-channel-16", tip: qsTr("Channel message") }
        if (k === "team") return { color: orange, icon: "badge-team-16", tip: qsTr("Team message") }
        if (m.mine) return { color: theme.brand, icon: "", tip: "" }
        return null
    }
    // Teams' grouping of a channel thread's replies (its worker's 92502
    // `d`): a reply joins the one before it ("bottom" attached: no avatar,
    // name or time) when the same person (and app) sent both under 5
    // minutes apart, the one before isn't deleted, and both are ordinary
    // messages. The first reply after the post never joins it. `list` is
    // the thread's replies in order, `i` the reply's place in it.
    function replyAttached(list, i) {
        if (!list || i <= 0 || i >= list.length) return false
        const a = list[i], e = list[i - 1]
        if (!a || !e || e.deleted) return false
        if ((a.sender_mri || a.sender || "") !== (e.sender_mri || e.sender || "")) return false
        if ((a.sender_app || "") !== (e.sender_app || "")) return false
        if ((a.kind || "message") !== "message" || (e.kind || "message") !== "message") return false
        const ta = new Date(a.time).getTime(), te = new Date(e.time).getTime()
        if (!ta || !te) return false
        return ta - te <= 5 * 60 * 1000
    }
    // Teams' relative dates, as in chats.
    function conversationStamp(t) {
        const d = new Date(t), now = new Date()
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        const time = theme.time(d)
        if (days === 0) return time
        if (days === 1) return qsTr("Yesterday") + " " + time
        if (days > 1 && days < 7) return theme.fmtDate(d, "dddd") + " " + time
        if (d.getFullYear() === now.getFullYear()) return theme.dateNoYear(d) + " " + time
        return theme.date(d) + " " + time
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
        if (n === 0) return qsTr("Today")
        if (n === 1) return qsTr("Yesterday")
        if (n > 1 && n < 7) return theme.fmtDate(d, "dddd")
        if (d.getFullYear() === new Date().getFullYear()) return theme.fmtDate(d, "MMMM d")
        return theme.fmtDate(d, "MMMM d, yyyy")
    }
}
