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
    property string chatPresence: ""
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
        : isSelf ? ["Chat", "Shared", "Storyline"] : ["Chat", "Shared", "Notes", "Recap", "Storyline"]
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
    readonly property var quickReactions: backend.quickReactionsJson ? JSON.parse(backend.quickReactionsJson) : ["like", "heart", "laugh", "surprised"]
    // Test hook: show the hover bar on this message (--actions-test).
    property string forceBarId: ""
    // The message being quoted in the compose box (Reply with quote).
    property var quoting: null
    function replyWithQuote(m) {
        quoting = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.text || "" }
        input.forceActiveFocus()
    }
    function startEdit(m) { root.editingId = m.id; root.setPlain(m.text); input.forceActiveFocus() }
    // Go to a message (a quote card's target), if it is loaded.
    function jumpToMessage(id) {
        const i = (list.model || []).findIndex(m => m.id === id)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
    }
    function closePickerForTest() { reactionPicker.close() }
    function openReactionPicker(messageId, anchor) { reactionPicker.messageId = messageId; reactionPicker.parent = anchor; reactionPicker.open() }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function plainText() { return input.getText(0, input.length) }
    function setPlain(t) { input.clear(); if (t) input.insert(0, root.escapeHtml(t)) }
    function attachForTest(paths) { root.pendingFiles = paths }
    function openEmojiForTest() { emojiPicker.open() }
    function formatForTest(a, b, tag) { input.select(a, b); root.wrapSelection(tag) }
    function openParticipantsForTest() { participants.visible = true }
    function findForTest(q) { root.finding = true; findField.text = q; return root.findHits.length }
    function sendForTest() { root.sendCompose() }
    onChatIdChanged: {
        tab = ""; finding = false; findField.text = ""; participants.visible = false; posting = false
        if (draftChat && !editingId) backend.setDraft(draftChat, root.plainText())
        editingId = ""
        root.setPlain(chatId ? backend.draftFor(chatId) : "")
        draftChat = chatId
    }
    // Keep the draft current while typing (so it survives a quit).
    Timer {
        id: draftSave
        interval: 1000
        onTriggered: if (root.draftChat && !root.editingId) backend.setDraft(root.draftChat, root.plainText())
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
        const out = msgs.map(m => Object.assign({}, m))
        for (let i = 0; i < out.length; i++) {
            const prev = i > 0 ? out[i - 1] : null, cur = out[i]
            // A day divider where the day changes (not above the very first
            // message shown), and the "Last read" line where unread begins.
            const day = new Date(cur.time).toDateString()
            cur.dayDivider = prev && new Date(prev.time).toDateString() !== day ? root.dayLabel(cur.time) : ""
            cur.lastRead = cur.first_unread === true && i > 0
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
            x: 61; anchors.verticalCenter: parent.verticalCenter
            // Long names elide so the tabs and actions keep their place.
            width: Math.min(implicitWidth, parent.width * 0.35)
            elide: Text.ElideRight
            text: root.chatName
            font.family: theme.font; font.pixelSize: theme.title; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            id: tabs
            x: title.x + title.width + 2
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
                    // Tabs that would run under the header actions are hidden
                    // (opacity, so the row's layout doesn't depend on it).
                    readonly property bool fits: tabs.x + x + width <= header.width
                        - (root.pane ? 48 : root.isSelf ? 115 : root.isChannel ? 160 : 207)
                    opacity: fits ? 1 : 0
                    enabled: fits
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
        HeaderAction {
            visible: !root.isSelf && !root.isChannel
            x: parent.width - 199; width: 24
            icon: "call-20"
            onClicked: root.call()
            Accessible.name: "Audio call"
        }
        HeaderAction {
            visible: !root.isSelf && !root.isChannel
            x: parent.width - 175; width: 24
            icon: "chevron-down-16"; iconSize: 16
            Accessible.name: "More call options"
            onClicked: callMenu.open()
            MenuPopup {
                id: callMenu
                x: -200; y: parent.height + 4
                items: [{ label: "Audio call", icon: "call-20" }]
                onPicked: root.call()
            }
        }
        HeaderAction {
            visible: !root.isSelf
            x: parent.width - 151; width: 28
            icon: "people-add-20"
            Accessible.name: "View participants"
            onClicked: participants.visible = !participants.visible
        }
        Rectangle {
            visible: !root.isSelf
            x: parent.width - 116; width: 1; height: 20
            anchors.verticalCenter: parent.verticalCenter
            color: theme.divider
        }
        HeaderAction {
            x: parent.width - 107; icon: "search-20"; Accessible.name: "Find in chat"
            onClicked: { root.finding = !root.finding; if (root.finding) { root.tab = ""; findField.forceActiveFocus() } else findField.text = "" }
        }
        HeaderAction {
            x: parent.width - 75; icon: "panel-left-20"; Accessible.name: "Open chat details"
            onClicked: participants.visible = !participants.visible
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
                name: msg.isCall ? (msg.modelData.call_state === "missed" ? "call-missed-20" : "call-20")
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
                        if (msg.modelData.call_state === "missed") return "Call missed"
                        const s = msg.modelData.call_seconds
                        const parts = [[Math.floor(s / 3600), "h"], [Math.floor(s / 60) % 60, "m"], [s % 60, "s"]]
                            .filter(p => p[0] > 0).map(p => p[0] + p[1]).join(" ")
                        return "Call ended&nbsp;<b>" + parts + "</b>"
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
                visible: msg.showMeta
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
            }
            Rectangle {
                id: bubble
                visible: !msg.isRow
                y: msg.bubbleY
                readonly property var imgs: msg.modelData.images || []
                readonly property bool imageOnly: imgs.length > 0 && msg.modelData.text === "Image"
                // A picture on its own is shown bare, without the bubble.
                readonly property bool bare: imageOnly && !root.isChannel
                readonly property real pad: bare ? 0 : 15.7
                readonly property var files: msg.modelData.files || []
                // Text shows unless the message is only a picture or only files.
                readonly property bool showBody: !imageOnly && (msg.modelData.deleted || (msg.modelData.text || "").length > 0)
                readonly property real bodyH: showBody ? body.implicitHeight : 0
                // A quoted reply's card sits at the top (Teams: 10.7 down, the
                // text 4 under it).
                readonly property real quoteShift: msg.modelData.quote ? 60.3 : 0
                readonly property real picsTop: showBody ? body.y + body.implicitHeight + 8 : (bare ? 0 : 8)
                readonly property real picsH: imgs.length > 0 ? pics.implicitHeight : 0
                readonly property real filesTop: imgs.length > 0 ? picsTop + picsH + 8 : (showBody ? body.y + body.implicitHeight + 8 : 8)
                width: root.isChannel ? msg.maxBubble
                    : Math.min(msg.maxBubble, Math.max(showBody ? body.implicitWidth + (msg.modelData.deleted && msg.mine ? 12 + undoMetrics.advanceWidth : 0) : 0, pics.implicitWidth, files.length > 0 ? fileCol.implicitWidth : 0, msg.modelData.quote ? quoteCard.width : 0) + 2 * pad)
                TextMetrics { id: undoMetrics; text: "Undo"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                height: bare && files.length === 0 ? picsH
                    : files.length > 0 ? filesTop + fileCol.implicitHeight + 8
                    : imgs.length > 0 ? picsTop + picsH + (showBody ? 8.6 : 8)
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
                // Inline pictures, scaled to fit the bubble (as in Teams).
                Column {
                    id: pics
                    x: bubble.pad; y: bubble.picsTop
                    spacing: 4
                    Repeater {
                        model: bubble.imgs
                        // Rounded 4 px with a hairline border, as Teams draws them.
                        Item {
                            required property var modelData
                            readonly property real maxW: msg.maxBubble - 2 * bubble.pad
                            readonly property real w0: modelData.width > 0 ? modelData.width : 240
                            readonly property real h0: modelData.height > 0 ? modelData.height : 160
                            width: Math.min(maxW, w0); height: width * h0 / w0
                            Image {
                                anchors.fill: parent
                                source: parent.modelData.local_path || ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            RoundedCorners {
                                anchors.fill: parent
                                radius: theme.radius
                                background: bubble.bare ? root.color : bubble.color
                            }
                            Rectangle { anchors.fill: parent; color: "transparent"; border.color: theme.dividerSoft; radius: theme.radius }
                            Accessible.role: Accessible.Graphic
                            Accessible.name: "Image"
                        }
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
                Text {
                    id: body
                    visible: bubble.showBody
                    x: bubble.pad; y: 6.7 + bubble.quoteShift
                    width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                    // Teams' 14/20 text.
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : "<style>a { color: " + theme.brand + "; text-decoration: none; } "
                          + ".mention { color: " + theme.brand + "; } "
                          + ".mention-me { color: " + theme.mentionMe + "; font-weight: 700; }</style>"
                          + (msg.modelData.html || msg.modelData.text)
                    textFormat: msg.modelData.deleted ? Text.PlainText : Text.RichText
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    // Teams' tombstone: italic, in the normal text colour.
                    font.italic: msg.modelData.deleted === true
                    color: theme.text
                    linkColor: theme.brand
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    Accessible.name: msg.modelData.text
                }
                // Undo, 12 px after the tombstone text (14 px semibold brand), for
                // your own message deleted in this session.
                Text {
                    visible: msg.modelData.deleted === true && msg.mine
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
            // Teams' reaction summary (measured): pills 26 tall and 2 apart,
            // overlapping the bubble's bottom edge by 4, 15.7 in from its
            // start. A pill holds up to three emoticons (20 px "small") and
            // the count when over one; yours has a brand border. Then the
            // add-reaction button (More reactions).
            Row {
                id: reactionRow
                visible: msg.reactions.length > 0
                y: bubble.y + bubble.height - 4.3
                // Your messages' reactions sit at the bubble's end (Teams).
                x: msg.mine ? bubble.x + bubble.width - 15.7 - width : bubble.x + 15.7
                spacing: 2
                z: 4
                Repeater {
                    model: msg.reactions
                    Rectangle {
                        id: pillBox
                        required property var modelData
                        width: 7 + 20 + (modelData.count > 1 ? 4 + countText.implicitWidth : 0) + 7
                        height: 26; radius: 13
                        color: theme.surface
                        border.color: modelData.mine ? theme.brand : theme.divider
                        border.width: modelData.mine ? 1.5 : 1
                        Emoticon { x: 7; y: 3; key: pillBox.modelData.key; named: "small"; size: 20 }
                        Text {
                            id: countText
                            visible: pillBox.modelData.count > 1
                            x: 7 + 20 + 4; anchors.verticalCenter: parent.verticalCenter
                            text: pillBox.modelData.count
                            font.family: theme.font; font.pixelSize: theme.small
                            font.weight: pillBox.modelData.mine ? Font.DemiBold : Font.Normal
                            color: theme.text
                        }
                        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.react(msg.modelData.id, pillBox.modelData.key, !pillBox.modelData.mine) }
                        Accessible.role: Accessible.Button
                        Accessible.checked: modelData.mine
                        Accessible.name: modelData.count + " " + backend.emoticonName(modelData.key) + " reaction" + (modelData.count === 1 ? "." : "s.")
                    }
                }
                Rectangle {
                    width: 34; height: 26; radius: 13
                    color: theme.surface
                    border.color: theme.divider
                    FluentIcon { x: 9; y: 5; size: 16; name: addHover.hovered ? "emoji-add-16-filled" : "emoji-add-16"; color: addHover.hovered ? theme.brand : theme.textStrong }
                    HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openReactionPicker(msg.modelData.id, parent) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "More reactions"
                }
            }
            HoverHandler { id: msgHover }
            // Teams' hover bar (message-actions-container, measured in the
            // client): a 32 px popover end-aligned on the bubble's top edge,
            // white with Fluent's shadow16. Inside: 7 px in, the quick
            // reactions (32 x 31 buttons, the emoticon 20 px at 6, growing to
            // 1.2x on hover), More reactions, a divider (8 px, its 1 px line
            // 21 px tall), the contextual action (Edit on yours, Reply with
            // quote on others'), More options; 6 px after.
            Item {
                id: actions
                readonly property bool can: !msg.isRow && !msg.modelData.deleted && !msg.sendPending && !msg.sendFailed
                readonly property var quick: root.quickReactions
                readonly property var acts: msg.mine
                    ? [{ key: "edit", icon: "edit-20", tip: "Edit", name: "Edit" }]
                    : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote", name: "Reply with quote" }]
                visible: can && (msgHover.hovered || barHover.hovered || menu.visible || root.forceBarId === msg.modelData.id)
                z: 5
                height: 32
                width: 7 + (quick.length + 1) * 32 + 8 + acts.length * 32 + 32 + 6
                y: bubble.y - height
                x: bubble.x + bubble.width - width
                FluentSurface { anchors.fill: parent; depth: 16; radius: 4 }
                HoverHandler { id: barHover }
                Accessible.role: Accessible.ToolBar
                Accessible.name: "Reactions and message actions"
                Row {
                    x: 7
                    Repeater {
                        model: actions.quick
                        Item {
                            id: quickBtn
                            required property string modelData
                            readonly property bool mineAlready: msg.reactions.some(r => r.key === modelData && r.mine)
                            width: 32; height: 31
                            Emoticon {
                                anchors.centerIn: parent
                                key: quickBtn.modelData; named: "medium"; size: 20
                                scale: quickHover.hovered ? 1.2 : 1
                                Behavior on scale { NumberAnimation { duration: 100 } }
                            }
                            HoverHandler { id: quickHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.react(msg.modelData.id, quickBtn.modelData, !quickBtn.mineAlready) }
                            ToolTip {
                                visible: quickHover.hovered; delay: 500
                                y: -height - 4; padding: 8
                                background: FluentSurface { depth: 16; radius: 4 }
                                contentItem: Text { text: backend.emoticonName(quickBtn.modelData); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: backend.emoticonName(modelData)
                            Accessible.checked: mineAlready
                        }
                    }
                    BarButton { icon: "emoji-add-20"; tip: "More reactions"; onClicked: root.openReactionPicker(msg.modelData.id, actions) }
                    Item {
                        width: 8; height: 32
                        Rectangle { x: 4; y: 5; width: 1; height: 21; color: theme.divider }
                    }
                    Repeater {
                        model: actions.acts
                        BarButton {
                            required property var modelData
                            icon: modelData.icon; tip: modelData.tip
                            onClicked: modelData.key === "edit" ? root.startEdit(msg.modelData) : root.replyWithQuote(msg.modelData)
                        }
                    }
                    BarButton { icon: "more-horizontal-20"; tip: "More options"; height: 32; onClicked: menu.open() }
                }
                Menu {
                    id: menu
                    y: actions.height
                    MenuItem {
                        text: "Edit"
                        onTriggered: root.startEdit(msg.modelData)
                    }
                    MenuItem {
                        text: "Delete"
                        onTriggered: root.deleteMessage(msg.modelData.id)
                    }
                }
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

    // "Editing" strip above the compose box while editing a message.
    Rectangle {
        visible: root.editingId.length > 0
        anchors { left: compose.left; right: compose.right; bottom: compose.top; bottomMargin: 2 }
        height: 28; radius: theme.radius
        color: theme.brandTint
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: "Editing message — Enter to save, Esc to cancel"
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.text
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

    // Participants: who is in this chat.
    Rectangle {
        id: participants
        visible: false
        z: 50
        anchors { top: header.bottom; right: parent.right; topMargin: 4; rightMargin: 16 }
        width: 300; height: Math.min(400, partCol.implicitHeight + 24)
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        readonly property var members: {
            const seen = {}, out = []
            if (root.myName) { out.push({ name: root.myName + " (You)", mri: "me" }); seen.me = true }
            for (const m of root.messages) {
                if (m.mine || !m.sender_mri || seen[m.sender_mri]) continue
                seen[m.sender_mri] = true
                out.push({ name: m.sender, mri: m.sender_mri })
            }
            if (!root.isChannel && root.chatPhotoId && !seen[root.chatPhotoId] && !root.isSelf) out.push({ name: root.chatName, mri: root.chatPhotoId })
            return out
        }
        Column {
            id: partCol
            x: 12; y: 12; width: parent.width - 24
            spacing: 4
            Text {
                text: root.isChannel ? "People in this channel" : "People (" + participants.members.length + ")"
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
            Repeater {
                model: participants.members
                Item {
                    required property var modelData
                    width: partCol.width; height: 40
                    Avatar {
                        x: 0; anchors.verticalCenter: parent.verticalCenter; size: 32
                        name: parent.modelData.name.replace(/ \(You\)$/, "")
                        photoId: parent.modelData.mri
                        presence: parent.modelData.mri === root.chatPhotoId ? root.chatPresence : ""
                    }
                    Text {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44; elide: Text.ElideRight
                        text: parent.modelData.name
                        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    }
                }
            }
        }
    }

    // Format (Teams' format bar): wrap the selection in a style or a list.
    property bool formatting: false
    function wrapSelection(tag) {
        const a = input.selectionStart, b = input.selectionEnd
        if (a === b) return
        const sel = root.escapeHtml(input.getText(a, b))
        input.remove(a, b)
        const html = tag === "ul" || tag === "ol" ? "<" + tag + "><li>" + sel.replace(/<br>/g, "</li><li>") + "</li></" + tag + ">"
            : "<" + tag + ">" + sel + "</" + tag + ">"
        input.insert(a, html)
        input.forceActiveFocus()
    }
    // Files picked to send with the next message (local paths).
    property var pendingFiles: []
    function addFiles(urls) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    // Send what's in the compose box: text, files, or both.
    function sendCompose() {
        backend.setReplyQuote(root.quoting ? JSON.stringify(root.quoting) : "")
        if (root.pendingFiles.length > 0) {
            backend.sendFiles(root.pendingFiles.join("\n"), root.plainText())
            root.pendingFiles = []
        } else if (root.plainText().trim().length > 0) {
            // Formatted text goes as Teams HTML; plain text as before.
            const html = input.getFormattedText(0, input.length)
            if (/font-weight:\s*[6-9]00|font-style:\s*italic|text-decoration:[^;"]*(underline|line-through)|<ul|<ol/.test(html)) backend.sendRich(html)
            else root.send(root.plainText())
        }
        input.clear()
        root.quoting = null
        root.formatting = false
        root.posting = false
    }
    // Teams' reaction picker, opened from the hover bar or a message's
    // add-reaction button.
    // Above its anchor, start-aligned, kept inside the window (Teams: the
    // picker opened from the hover bar sits over the bar, 8 before it).
    ReactionPicker {
        id: reactionPicker
        x: -8
        y: -height - 4
        margins: 8
        onPicked: key => root.react(messageId, key, true)
    }
    // A hover-bar action: Fluent's transparent button, 32 wide; #424242 at
    // rest, brand with the filled glyph on hover.
    component BarButton: Item {
        id: bb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31
        FluentIcon { x: 6; y: 6; size: 20; name: bbHover.hovered ? bb.icon + "-filled" : bb.icon; color: bbHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: bbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        ToolTip {
            visible: bbHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: bb.tip; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    EmojiPicker {
        id: emojiPicker
        parent: compose
        x: compose.width - width; y: -height - 8
        onPicked: e => { input.insert(input.cursorPosition, e); close(); input.forceActiveFocus() }
    }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }

    // Compose box
    Rectangle {
        id: compose
        visible: root.chatName.length > 0 && (!root.isChannel || root.posting)
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: root.pane ? 12 : 72; anchors.rightMargin: root.pane ? 12 : 72; anchors.bottomMargin: root.pane ? 12 : 24
        height: Math.max(44, input.contentHeight + 24) + (root.pendingFiles.length > 0 ? pendingRow.height + 8 : 0)
            + (root.formatting ? 40 : 0) + (root.quoting ? 56 + 14 : 0)
        // The message being quoted (Teams: a card 12 in and 14 down in the
        // editor, with Remove Reference).
        QuoteCard {
            visible: !!root.quoting
            x: 12; y: (root.formatting ? 40 : 0) + 14
            quote: root.quoting
            dismissable: true
            maxWidth: compose.width - 24
            onDismissed: { root.quoting = null; input.forceActiveFocus() }
        }
        // The format bar: bold, italic, underline, strikethrough, lists.
        Row {
            visible: root.formatting
            x: 8; y: 4
            spacing: 2
            Repeater {
                model: [
                    { icon: "text-bold-20", tag: "b", label: "Bold (Ctrl+B)" },
                    { icon: "text-italic-20", tag: "i", label: "Italic (Ctrl+I)" },
                    { icon: "text-underline-20", tag: "u", label: "Underline (Ctrl+U)" },
                    { icon: "text-strike-20", tag: "s", label: "Strikethrough" },
                    { icon: "text-bullets-20", tag: "ul", label: "Bulleted list" },
                    { icon: "text-numbers-20", tag: "ol", label: "Numbered list" },
                ]
                Rectangle {
                    required property var modelData
                    width: 32; height: 32; radius: theme.radius
                    color: fbh.hovered ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                    HoverHandler { id: fbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.wrapSelection(parent.modelData.tag) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
        // Files waiting to be sent, as removable chips above the text.
        Flow {
            id: pendingRow
            visible: root.pendingFiles.length > 0
            x: 12; y: (root.formatting ? 44 : 8) + (root.quoting ? 56 + 14 : 0); width: parent.width - 24
            spacing: 8
            Repeater {
                model: root.pendingFiles
                Rectangle {
                    required property string modelData
                    height: 40; width: Math.min(300, nameText.implicitWidth + 80)
                    radius: 8
                    color: theme.searchFill
                    border.color: theme.divider
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 24; color: theme.textSecondary }
                    Text {
                        id: nameText
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 76
                        text: parent.modelData.split("/").pop()
                        elide: Text.ElideMiddle
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: theme.radius
                        color: rmh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textStrong }
                        HoverHandler { id: rmh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pendingFiles = root.pendingFiles.filter(p => p !== parent.parent.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove " + parent.modelData.split("/").pop()
                    }
                }
            }
        }
        radius: theme.radius
        color: theme.input
        border.color: input.activeFocus ? theme.brand : theme.divider
        TextArea {
            id: input
            anchors { left: parent.left; right: tools.left; bottom: parent.bottom; bottomMargin: (44 - 32) / 2 }
            anchors.leftMargin: 4
            placeholderText: root.isChannel ? "Start a post" : "Type a message"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            wrapMode: TextArea.Wrap
            background: null
            textFormat: TextEdit.RichText
            Keys.onPressed: event => {
                if (!(event.modifiers & Qt.ControlModifier)) return
                if (event.key === Qt.Key_B) { root.wrapSelection("b"); event.accepted = true }
                else if (event.key === Qt.Key_I) { root.wrapSelection("i"); event.accepted = true }
                else if (event.key === Qt.Key_U) { root.wrapSelection("u"); event.accepted = true }
                else if (event.key === Qt.Key_X && (event.modifiers & Qt.AltModifier)) { root.wrapSelection("s"); event.accepted = true }
            }
            onActiveFocusChanged: if (activeFocus) enterKey = backend.setting("enterKey") || "send"
            onTextChanged: {
                if (length > 0) root.typing()
                draftSave.restart()
            }
            // Settings > Chats and channels: Enter sends (Shift+Enter breaks the
            // line), or Enter breaks the line and Ctrl+Enter sends.
            property string enterKey: backend.setting("enterKey") || "send"
            Keys.onReturnPressed: event => {
                const sendKey = enterKey === "newline" ? (event.modifiers & Qt.ControlModifier) : !(event.modifiers & Qt.ShiftModifier)
                if (!sendKey) { event.accepted = false; return }
                if (root.editingId) { root.editMessage(root.editingId, root.plainText()); root.editingId = ""; input.clear() }
                else root.sendCompose()
            }
            Keys.onEscapePressed: {
                if (root.editingId) { root.editingId = ""; input.clear() }
                else if (root.posting) root.posting = false
            }
        }
        Row {
            id: tools
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.bottom: parent.bottom; anchors.bottomMargin: 12
            spacing: 12
            FluentIcon {
                name: "format-20"
                color: root.formatting ? theme.brand : theme.icon
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.formatting = !root.formatting }
                Accessible.role: Accessible.Button
                Accessible.name: "Format"
            }
            FluentIcon {
                id: emojiButton
                name: "emoji-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: emojiPicker.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Emoji"
            }
            FluentIcon {
                name: "attach-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: filePicker.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Attach files"
            }
            FluentIcon {
                name: "add-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: actionsMenu.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Actions and apps"
                MenuPopup {
                    id: actionsMenu
                    x: -width + 20; y: -height - 12
                    items: [{ label: "Upload from this device", icon: "attach-20" }, { label: "Emoji", icon: "emoji-20" }]
                    onPicked: i => i === 0 ? filePicker.open() : emojiPicker.open()
                }
            }
            Rectangle { width: 1; height: 20; color: theme.divider }
            FluentIcon {
                readonly property bool ready: input.length > 0 || root.pendingFiles.length > 0
                name: ready ? "send-20-filled" : "send-20"
                color: ready ? theme.brand : theme.icon
                TapHandler { onTapped: root.sendCompose() }
                Accessible.role: Accessible.Button
                Accessible.name: "Send"
            }
        }
    }
}
