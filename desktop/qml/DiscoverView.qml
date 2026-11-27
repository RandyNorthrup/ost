import QtQuick
import QtQuick.Controls.Basic

// Quick views ▸ Discover: Teams' feed of suggested channel posts (its
// discover surface; measured on Teams web as OST Test 2, 2026-11-27, at
// 1600 x 900; read from Teams 26304's discover-surface bundles).
// - The header: 61 tall with a 1 px #E0E0E0 line under it, padding 8 10 8
//   32; "Discover" (18/25.7 bold); Settings (32 px, the gear) at the end.
// - The feed on white, its cards 910 wide at most (the runway: 1058 less
//   74 either side, and 14 for the scroll bar), 12 under the header and 24
//   apart; each card has Fluent's shadow 2 and radius 4:
//   - its header (32 tall, a 1 px #F0F0F0 line under it, 16 in): why it's
//     there (12/16 #616161: "From your channels", "You engage with this
//     channel", …) and at the end, 8 in, "Is this useful?" (12/16) with Yes
//     and No (12/16 brand, 4 either side). Yes: "Thanks for your
//     feedback."; No: the same with "Tell us why" (Teams' feedback form);
//   - the post as a channel's: the author's 32 px picture at (18, 16), the
//     name (14/20) at 60, 14 down, the time (12/17.1 #616161) 10 after it,
//     the team › channel (12/16 #424242, a link to the channel) 34 down; the
//     subject and text at (18, 64); the reactions 17 under it (the add
//     button even with none); the hover bar's ··· adds Don't show this post
//     again, Don't show posts from {author}, Don't show posts from
//     {channel};
//   - its replies under a #F0F0F0 line (the last three, as in the channel):
//     a 20 px picture at 18, the name and time (12/17.1) at 50, the text 20
//     down;
//   - "Reply in thread" (14/600 #616161, your 20 px picture at 18) under a
//     #F0F0F0 line, opening the channel's reply box in the card.
// - Hidden ("Don't show …"): the card gives way to "This post has been
//   hidden" with what you won't see again and Undo (57 tall).
// - More loads as you near the end (pages of 10); at the end Teams'
//   picture (150 x 118) 78 under the last card and "You’re all caught up"
//   (14/20) 12 under it. With nothing: "No suggested posts at the moment.";
//   a failure: "We ran into a problem getting your suggested posts." and
//   Try again.
Rectangle {
    id: root
    color: theme.surface
    property string myName: ""
    /// Open a channel (the team › channel link).
    signal openChannel(string channelId, string name)
    /// Tell us why: Teams' feedback form.
    signal tellUsWhy()

    // ---- The feed ----
    property var items: []
    property string continuation: ""
    property string traceId: ""
    property string logicalId: ""
    property bool loading: false
    property bool failed: false
    property bool loaded: false
    /// The latest feed request (its answer echoes it).
    property int feedReq: 0
    /// Feedback given, by feedbackId: "yes", "no" or "tell".
    property var feedback: ({})
    /// Hidden cards, by feedbackId: {kind: "POST"|"AUTHOR"|"CHANNEL", name}.
    property var hidden: ({})
    readonly property bool ended: loaded && !loading && !failed && !continuation
    function load(more) {
        if (loading || (more && !continuation)) return
        loading = true; failed = false
        if (!more) { closeThreads(); items = []; cardModel.clear(); continuation = ""; feedback = ({}); hidden = ({}) }
        feedReq++
        backend.channelAction("discover-feed", "", "", JSON.stringify({ continuation: more ? continuation : "", req: feedReq }))
    }
    ListModel { id: cardModel }
    /// A picture clicked: Teams' viewer on the message's pictures.
    signal openImage(var images, int index, var message)
    /// Each post loads (and stays live) as a thread does.
    property var opened: []
    function closeThreads() {
        for (const k of opened) backend.closeThreadWindow(k.channel, k.post)
        opened = []
    }
    onVisibleChanged: if (visible) load(false); else { closeThreads(); loading = false }
    Component.onDestruction: closeThreads()
    readonly property var threads: backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : ({})
    readonly property var teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
    function channelName(item) {
        if (item.channel_name) return item.channel_name
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === item.channel_id); if (c) return c.name }
        return ""
    }
    function teamOf(item) { return teams.find(t => t.thread_id === item.team_thread || t.id === item.team_group_id) || null }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "discover-feed") {
                // Only the latest load's answer counts (an older visit's, or
                // one after Discover closed, changes nothing).
                const page = r.data || {}
                if (r.ok && page.req !== root.feedReq) return
                if (!root.visible || !root.loading) return
                root.loading = false
                if (!r.ok) { root.failed = true; return }
                const seen = {}
                for (const i of root.items) seen[i.feedback_id] = true
                const fresh = (page.items || []).filter(i => !seen[i.feedback_id])
                root.items = root.items.concat(fresh)
                for (const i of fresh) cardModel.append({ json: JSON.stringify(i) })
                root.continuation = fresh.length ? page.continuation || "" : ""
                root.traceId = page.trace_id || root.traceId
                root.logicalId = page.logical_id || root.logicalId
                root.loaded = true
                // (A post already open elsewhere, a thread window or the post
                // view, stays that view's: Discover neither opens nor closes it.)
                const o = root.opened.slice()
                const live = root.threads
                for (const i of fresh) {
                    if ((i.channel_id + ";messageid=" + i.post_id) in live) continue
                    backend.openThreadWindow(i.channel_id, i.post_id); o.push({ channel: i.channel_id, post: i.post_id })
                }
                root.opened = o
            } else if (r.op === "discover-exclude" || r.op === "discover-include") {
                // Changes answer in order: a failed one is put back.
                const p = root.pendingPrefs.length ? root.pendingPrefs[0] : null
                if (!p || p.op !== r.op) return
                root.pendingPrefs = root.pendingPrefs.slice(1)
                if (!r.ok) {
                    p.undo()
                    backend.toast(qsTr("Something went wrong on our end. Please try again."), "error")
                }
                root.sendHead()
            } else if (r.op === "discover-feedback") {
                console.info("DISCOVER feedback", r.ok)
            } else if (r.op === "discover-excluded") {
                settings.loading = false
                settings.failed = !r.ok
                settings.list = r.ok ? r.data || [] : []
            }
        }
    }
    function sendFeedback(item, useful) {
        const f = Object.assign({}, feedback); f[item.feedback_id] = useful ? "yes" : "no"; feedback = f
        backend.channelAction("discover-feedback", "", "", JSON.stringify({ item: item, trace_id: traceId, logical_id: logicalId, useful: useful, position: Math.max(0, items.findIndex(i => i.feedback_id === item.feedback_id)) }))
    }
    /// Preference changes sent and not yet answered, oldest first, each
    /// with how to put the screen back if it fails.
    property var pendingPrefs: []
    // One at a time (the backend answers each call on its own, and a
    // result names no request), so each answer is the head's.
    function sendPref(op, args, undo) {
        pendingPrefs = pendingPrefs.concat([{ op: op, args: args, undo: undo }])
        if (pendingPrefs.length === 1) sendHead()
    }
    function sendHead() {
        const p = pendingPrefs[0]
        if (p) backend.channelAction(p.op, "", "", JSON.stringify(p.args))
    }
    /// Why a card is hidden: its own "Don't show …", or another card's
    /// author or channel rule that covers it (Teams hides every post they
    /// cover, each with its own hidden card).
    function hiddenFor(item) {
        const own = hidden[item.feedback_id]
        if (own) return own
        for (const i of items) {
            const h = hidden[i.feedback_id]
            if (!h) continue
            if (h.kind === "CHANNEL" && i.channel_id === item.channel_id) return Object.assign({ owner: i }, h)
            if (h.kind === "AUTHOR" && i.author_id && i.author_id === item.author_id) return Object.assign({ owner: i }, h)
        }
        return null
    }
    function setHidden(item, h) {
        const n = Object.assign({}, hidden)
        if (h) n[item.feedback_id] = h; else delete n[item.feedback_id]
        hidden = n
    }
    function hide(item, kind) {
        const h = { kind: kind, name: kind === "AUTHOR" ? item.author_name : kind === "CHANNEL" ? channelName(item) : "" }
        setHidden(item, h)
        sendPref("discover-exclude", excludeArgs(item, kind), () => setHidden(item, null))
    }
    function undoHide(item) {
        const via = hiddenFor(item)
        if (via && via.owner) item = via.owner
        const h = hidden[item.feedback_id]
        if (!h) return
        setHidden(item, null)
        sendPref("discover-include", excludeArgs(item, h.kind), () => setHidden(item, h))
    }
    function excludeArgs(item, kind) {
        return kind === "AUTHOR" ? { kind: kind, id: "8:orgid:" + item.author_id, name: item.author_name }
            : kind === "CHANNEL" ? { kind: kind, id: "uri://channel/" + item.team_group_id + "/" + item.channel_id }
            : { kind: kind, id: item.post_id, feedback_id: item.feedback_id }
    }
    function reasonText(r) {
        switch (r) {
        case "POST_POPULARITY": return qsTr("Trending")
        case "AUTHOR_YOU_COLLABORATE_WITH": return qsTr("Author in your network")
        case "AUTHOR_POPULARITY": return qsTr("This author is popular")
        case "CHANNEL_YOU_ENGAGE_WITH": return qsTr("You engage with this channel")
        case "CHANNEL_POPULARITY": return qsTr("This channel is popular")
        case "CHANNEL_YOU_VISIT": return qsTr("You visit this channel")
        case "AUTHOR_YOU_INTERACT_WITH": return qsTr("You interact with this author")
        case "ACTIVE_AUTHOR": return qsTr("This author is active")
        default: return qsTr("From your channels")
        }
    }
    function itemsForTest() { return items }
    function scrollToTopForTest() { flick.contentY = 0 }
    function scrollToEndForTest() { flick.contentY = Math.max(0, flick.contentHeight - flick.height) }
    function openFirstMenuForTest() {
        const c = cardsRepeater.itemAt(0)
        if (c && c.post) c.openMenuForTest()
    }
    function firstMenuForTest() { const c = cardsRepeater.itemAt(0); return c ? c.menuItemsForTest() : [] }
    function closeMenusForTest() { const c = cardsRepeater.itemAt(0); if (c) c.closeMenuForTest() }
    function settingsForTest() { return settings }

    // ---- Header ----
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            x: 32; y: 16
            text: qsTr("Discover")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            id: gear
            x: parent.width - 10 - 32; y: 14; width: 32; height: 32; radius: 4
            color: gearHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: gearHover.hovered ? "settings-20-filled" : "settings-20"; size: 20; color: theme.onFill(gear, theme.textStrong) }
            HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: settings.start() }
            ToolTip.visible: gearHover.hovered; ToolTip.delay: 600; ToolTip.text: qsTr("Settings")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Settings")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.divider }
    }

    // ---- The feed ----
    Flickable {
        id: flick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        contentHeight: feedCol.height + 12 + 24
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Near the end: the next page.
        onContentYChanged: if (contentY + height > contentHeight - 600) root.load(true)
        readonly property real cardW: Math.max(320, Math.min(910, width - 28 - 148))
        Column {
            id: feedCol
            x: (flick.width - flick.cardW) / 2; y: 12
            width: flick.cardW
            spacing: 24
            // (A ListModel the pages are appended to: the cards already
            // shown, and a reply being written in one, stay as they are.)
            Repeater {
                id: cardsRepeater
                model: cardModel
                DiscoverCard { required property string json; required property int index; item: JSON.parse(json); position: index; width: flick.cardW }
            }
            // The end of the feed.
            Item {
                visible: root.ended && root.items.length > 0
                width: parent.width; height: visible ? 54 + 118 + 12 + 20 : 0
                Image {
                    x: (parent.width - 150) / 2; y: 54
                    width: 150; height: 118
                    source: "../assets/illustrations/discover-caught-up.svg"
                    sourceSize: Qt.size(300, 236)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 54 + 118 + 12
                    text: qsTr("You’re all caught up")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
            }
        }
    }
    Column {
        visible: (root.loaded && root.items.length === 0 && !root.loading) || (root.failed && root.items.length === 0)
        anchors.centerIn: flick
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.failed ? qsTr("We ran into a problem getting your suggested posts.") : qsTr("No suggested posts at the moment.")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            id: retry
            visible: root.failed
            anchors.horizontalCenter: parent.horizontalCenter
            width: retryText.implicitWidth + 24; height: 32; radius: 4
            color: retryHover.hovered ? theme.rowHover : theme.surface
            border.color: theme.stroke; border.width: 1
            Text { id: retryText; anchors.centerIn: parent; text: qsTr("Try again"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(retry, theme.text) }
            HoverHandler { id: retryHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.load(false) }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Try again")
        }
    }
    BusyIndicator { anchors.centerIn: flick; running: root.loading && root.items.length === 0; visible: running }

    // ---- A card ----
    component DiscoverCard: Item {
        id: card
        property var item: ({})
        property int position: 0
        readonly property string key: item.channel_id + ";messageid=" + item.post_id
        readonly property var thread: root.threads[key] || []
        readonly property var post: thread.find(m => m.id === item.post_id) || null
        // (A send retried under one client message id shows once, as the
        // later copy: Teams keys messages by clientmessageid.)
        readonly property var replies: {
            const out = [], at = {}
            for (const m of thread) {
                if (m.id === item.post_id || m.deleted || m.kind === "system") continue
                const k = m.client_message_id || m.id
                if (k in at) out[at[k]] = m
                else { at[k] = out.length; out.push(m) }
            }
            return out
        }
        readonly property var shownReplies: replies.length <= 3 ? replies : replies.slice(replies.length - 3)
        readonly property var hiddenAs: root.hiddenFor(item)
        readonly property string fb: root.feedback[item.feedback_id] || ""
        property bool replying: false
        /// Reply with quote's message ({message_id, sender_mri, sender_name, preview}).
        property var quote: null
        onReplyingChanged: if (!replying) quote = null
        height: hiddenAs ? hiddenCard.height : surface.height
        function openMenuForTest() { cardHost.openMessageMenu(post, card, false, 0, 50, "discover") }
        function closeMenuForTest() { cardHost.messageMenu.close() }
        function menuItemsForTest() { return cardHost.messageMenu.items.map(i => i.separator ? "|" : i.label) }
        MessageHost {
            id: cardHost
            messages: card.thread
            isChannel: true
            chatId: card.item.channel_id
            teamId: card.item.team_group_id; teamName: card.item.team_name; chatName: root.channelName(card.item)
            discoverActions: true
            authorName: card.item.author_name || ""
            onDiscoverHide: kind => root.hide(card.item, kind)
            onReactRequested: (id, key, on) => backend.toggleReaction(id, key, on)
            onDeleteRequested: id => backend.deleteMessage(id)
            onQuoteRequested: m => { card.quote = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.quote_text || m.text || "" }; card.replying = true; replyInput.forceActiveFocus() }
        }
        // Hidden: Teams' blocked item (Teams web 2026-11-27): 57 tall,
        // padding 8 12 8 16; "This post has been hidden" (14/20 bold) over
        // what you won't see (12/17.1), Undo (96 x 32) at the end.
        FluentSurface {
            id: hiddenCard
            visible: !!card.hiddenAs
            width: parent.width; height: 57
            depth: 2; radius: 4; color: theme.surface
            Column {
                x: 16; y: 9.9
                width: parent.width - 16 - undo.width - 24
                Text {
                    text: qsTr("This post has been hidden")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    // (The author's or channel's name in bold, as Teams'.)
                    textFormat: Text.StyledText
                    readonly property string who: card.hiddenAs ? "<b>" + String(card.hiddenAs.name || "").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>" : ""
                    text: !card.hiddenAs ? ""
                        : card.hiddenAs.kind === "AUTHOR" ? qsTr("You won't see posts from the") + " " + who + " " + qsTr("again in Discover.")
                        : card.hiddenAs.kind === "CHANNEL" ? qsTr("You won't see posts from the") + " " + who + " " + qsTr("channel again in Discover.")
                        : qsTr("You won't see this post again in Discover.")
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
            }
            Rectangle {
                id: undo
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                width: 96; height: 32; radius: 4
                color: undoHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.stroke; border.width: 1
                Text { anchors.centerIn: parent; text: qsTr("Undo"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(undo, theme.text) }
                HoverHandler { id: undoHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.undoHide(card.item) }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Undo")
            }
        }
        FluentSurface {
            id: surface
            visible: !card.hiddenAs
            width: parent.width; height: col.height
            depth: 2; radius: 4; color: theme.surface
            Column {
                id: col
                width: parent.width
                // The card's header: why it's here, and Is this useful?
                Item {
                    width: parent.width; height: 32
                    Text {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: feedbackRow.x - x - 8; elide: Text.ElideRight
                        text: root.reasonText(card.item.reason)
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                    Row {
                        id: feedbackRow
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.fb === "" ? qsTr("Is this useful?") : card.fb === "tell" ? qsTr("Thanks for helping us improve!") : qsTr("Thanks for your feedback.")
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Repeater {
                            model: card.fb === "" ? [{ key: "yes", label: qsTr("Yes") }, { key: "no", label: qsTr("No") }]
                                : card.fb === "no" ? [{ key: "tell", label: qsTr("Tell us why") }] : []
                            Text {
                                required property var modelData
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                leftPadding: 4; rightPadding: 4
                                text: modelData.label
                                font.family: theme.font; font.pixelSize: 12; lineHeight: 18; lineHeightMode: Text.FixedHeight
                                font.underline: fbHover.hovered
                                color: fbHover.hovered ? theme.brandHover : theme.brandForeground1
                                HoverHandler { id: fbHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (modelData.key === "tell") { const f = Object.assign({}, root.feedback); f[card.item.feedback_id] = "tell"; root.feedback = f; root.tellUsWhy() }
                                        else root.sendFeedback(card.item, modelData.key === "yes")
                                    }
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.key === "tell" ? qsTr("Thanks for your feedback.") + " " + modelData.label : qsTr("Is this useful?") + " " + modelData.label
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
                }
                // The post.
                Item {
                    id: postItem
                    width: parent.width
                    readonly property var m: card.post
                    readonly property bool editing: !!m && cardHost.editingId === m.id
                    height: !m ? 64 : postBody.y + postBody.height + 17 + 26 + 6
                    Avatar {
                        x: 18; y: 16; size: 32
                        name: postItem.m ? postItem.m.sender || card.item.author_name : card.item.author_name || ""
                        photoId: postItem.m ? postItem.m.sender_mri : (card.item.author_id ? "8:orgid:" + card.item.author_id : "")
                        opensProfile: true
                    }
                    Row {
                        x: 60; y: 14
                        spacing: 10
                        Text {
                            text: postItem.m ? postItem.m.sender || card.item.author_name : (card.item.author_name || (card.thread.length ? "" : qsTr("Loading…")))
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Text {
                            visible: !!postItem.m
                            y: 2
                            text: postItem.m ? cardHost.conversationStamp(postItem.m.time) : ""
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                            color: theme.textSecondary
                        }
                        Text {
                            visible: !!postItem.m && postItem.m.edited === true
                            y: 2
                            text: qsTr("Edited")
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                            color: theme.textSecondary
                        }
                    }
                    // The team › channel, which opens the channel.
                    Row {
                        id: where
                        x: 60; y: 34
                        Text {
                            rightPadding: 6
                            text: card.item.team_name || ""
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            font.underline: whereHover.hovered
                            color: theme.textStrong
                        }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 10; color: theme.textStrong }
                        Text {
                            leftPadding: 6; rightPadding: 6
                            text: root.channelName(card.item)
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            font.underline: whereHover.hovered
                            color: theme.textStrong
                        }
                        HoverHandler { id: whereHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openChannel(card.item.channel_id, root.channelName(card.item)) }
                        Accessible.role: Accessible.Link
                        Accessible.name: (card.item.team_name || "") + ", " + root.channelName(card.item)
                    }
                    Text {
                        id: postSubject
                        visible: !!postItem.m && !!postItem.m.subject
                        x: 18; y: 64; width: card.width - 36
                        wrapMode: Text.Wrap; bottomPadding: 16
                        text: postItem.m ? postItem.m.subject || "" : ""
                        font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                        color: theme.text
                        Accessible.role: Accessible.Heading
                    }
                    PostBody {
                        id: postBody
                        onOpenImage: (list, i) => root.openImage(list, i, postItem.m)
                        visible: !!postItem.m
                        x: 18; y: 64 + (postSubject.visible ? postSubject.height : 0); width: card.width - 36
                        message: postItem.m
                    }
                    ReactionSummary {
                        visible: !!postItem.m
                        x: 18; y: postBody.y + postBody.height + 17
                        host: cardHost
                        addWhenEmpty: true
                        messageId: postItem.m ? postItem.m.id : ""
                        reactions: postItem.m ? (postItem.m.reactions || []) : []
                    }
                    HoverHandler { id: postHover }
                    HoverBar {
                        id: postBar
                        visible: !!postItem.m && !postItem.m.deleted
                            && (postHover.hovered || postBar.hovered || cardHost.menuOpenFor(postItem.m.id, "discover"))
                        host: cardHost
                        message: postItem.m || ({})
                        context: "discover"
                        acts: []
                        x: card.width - 10 - width; y: 11; z: 5
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !!postItem.m
                        onTapped: point => cardHost.openMessageMenu(postItem.m, postItem, true, point.position.x, point.position.y, "discover")
                    }
                }
                // Its replies (the last three).
                Item {
                    visible: card.shownReplies.length > 0
                    width: parent.width
                    height: visible ? replyCol.height + 8 : 0
                    Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                    Column {
                        id: replyCol
                        y: 1 + 8
                        width: parent.width
                        Repeater {
                            model: card.shownReplies
                            Item {
                                id: rep
                                required property var modelData
                                required property int index
                                // Teams groups a run of replies from one person (no
                                // second picture and name).
                                readonly property bool cont: index > 0 && card.shownReplies[index - 1].sender_mri === modelData.sender_mri
                                width: card.width
                                height: (cont ? 0 : 20) + repBody.height + ((modelData.reactions || []).length > 0 ? 8 + 26 : 0) + (cont ? 8 : 12)
                                Avatar {
                                    visible: !rep.cont
                                    x: 18; y: 0; size: 20
                                    name: rep.modelData.sender || ""; photoId: rep.modelData.sender_mri || ""
                                    opensProfile: true
                                }
                                Row {
                                    visible: !rep.cont
                                    x: 50; y: 1.4
                                    spacing: 8
                                    Text { text: rep.modelData.sender || ""; font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight; color: theme.text }
                                    Text { text: cardHost.conversationStamp(rep.modelData.time); font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                                    Text { visible: rep.modelData.edited === true; text: qsTr("Edited"); font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                                }
                                PostBody {
                                    id: repBody
                                    onOpenImage: (list, i) => root.openImage(list, i, rep.modelData)
                                    x: 50; y: rep.cont ? 0 : 20; width: card.width - 70
                                    message: rep.modelData
                                }
                                ReactionSummary {
                                    visible: (rep.modelData.reactions || []).length > 0
                                    x: 50; y: repBody.y + repBody.height + 8
                                    host: cardHost
                                    messageId: rep.modelData.id
                                    reactions: rep.modelData.reactions || []
                                }
                                HoverHandler { id: repHover }
                                HoverBar {
                                    id: repBar
                                    visible: !rep.modelData.deleted && (repHover.hovered || repBar.hovered || cardHost.menuOpenFor(rep.modelData.id, "reply"))
                                    host: cardHost
                                    message: rep.modelData
                                    context: "reply"
                                    acts: rep.modelData.mine ? [] : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }]
                                    x: rep.width - width - 10; y: -3.7 - height; z: 5
                                }
                            }
                        }
                    }
                }
                // Reply in thread, and the reply box.
                Item {
                    width: parent.width
                    height: card.replying ? Math.max(44, replyInput.contentHeight + 22) + 12 + (card.quote ? 32 : 0) : 48
                    Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                    Avatar {
                        x: 18; y: card.replying ? (parent.height - height) / 2 : 17.5
                        size: 20; name: root.myName || qsTr("You"); photoId: "me"
                    }
                    Text {
                        visible: !card.replying
                        x: 48; y: 16.6
                        text: qsTr("Reply in thread")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: replyHover.hovered ? theme.brand : theme.textSecondary
                    }
                    MouseArea {
                        id: replyHoverArea
                        visible: !card.replying
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { card.replying = true; replyInput.forceActiveFocus() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Reply in thread")
                    }
                    HoverHandler { id: replyHover }
                    // Reply with quote: the quoted message over the box, with
                    // its dismiss.
                    Rectangle {
                        id: quoteStrip
                        visible: card.replying && !!card.quote
                        x: 48; y: 6; width: card.width - 48 - 18; height: 28; radius: 4
                        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                        Rectangle { width: 3; height: parent.height; radius: 1.5; color: theme.textTertiary }
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 12 - 32
                            elide: Text.ElideRight
                            text: card.quote ? (card.quote.sender_name ? card.quote.sender_name + ": " : "") + String(card.quote.preview || "").replace(/\s+/g, " ") : ""
                            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                        }
                        Rectangle {
                            id: quoteClose
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 4
                            color: qch.hovered ? theme.hover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(quoteClose, theme.textStrong) }
                            HoverHandler { id: qch; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: card.quote = null }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Remove quote")
                        }
                    }
                    Rectangle {
                        visible: card.replying
                        x: 48; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: card.quote ? 16 : 0
                        width: card.width - 48 - 18; height: Math.max(44, replyInput.contentHeight + 22)
                        radius: theme.radius
                        color: theme.input
                        border.color: theme.stroke
                        Rectangle {
                            anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1
                            color: replyInput.activeFocus ? theme.brand : "transparent"
                        }
                        TextArea {
                            id: replyInput
                            anchors { left: parent.left; right: sendReply.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
                            placeholderText: qsTr("Reply in thread")
                            placeholderTextColor: theme.textSecondary
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.text
                            wrapMode: TextArea.Wrap
                            background: Item {}
                            function submit() {
                                const t = getText(0, length).trim()
                                if (!t) return
                                const esc = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>")
                                // Teams' size check (maxMessageContentSize): the reply stays.
                                if (backend.composeTooLarge("<p>" + esc + "</p>", "[]")) { backend.toast(qsTr("Message is too large to send."), "error"); return }
                                backend.sendThreadReply(card.item.channel_id, card.item.post_id, "<p>" + esc + "</p>", "[]", card.quote ? JSON.stringify(card.quote) : "", false)
                                text = ""
                                card.replying = false
                            }
                            Keys.onReturnPressed: e => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else submit() }
                            Keys.onEscapePressed: { text = ""; card.replying = false }
                            Accessible.name: qsTr("Reply in thread")
                        }
                        Rectangle {
                            id: sendReply
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 32; height: 32; radius: theme.radius
                            color: srh.hovered ? theme.rowHover : "transparent"
                            FluentIcon {
                                anchors.centerIn: parent
                                name: replyInput.length > 0 ? "send-20-filled" : "send-20"; size: 20
                                color: theme.onFill(sendReply, replyInput.length > 0 ? theme.brand : theme.textStrong)
                            }
                            HoverHandler { id: srh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: replyInput.submit() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Send reply")
                        }
                    }
                }
            }
        }
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Post by %1").arg(card.item.author_name || "")
    }

    // ---- Settings (Teams' discover-surface-up-dialog): what you've left out ----
    Popup {
        id: settings
        property var list: []
        property bool loading: false
        property bool failed: false
        /// Removed in this visit (shown as "{name} Removed").
        property var removed: ({})
        function start() {
            list = []; removed = ({}); loading = true; failed = false
            open()
            backend.channelAction("discover-excluded", "", "", "")
        }
        // (Teams web 2026-11-27: 600 wide, padding 32, radius 8; "Don't show
        // post from" 20/28 semibold with Close at its end; the text 15
        // under it, 14/20.)
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600; padding: 32
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        readonly property var channels: list.filter(e => e.kind === "CHANNEL")
        readonly property var people: list.filter(e => e.kind === "AUTHOR")
        /// An excluded channel's team and name ({team, teamId, channel}).
        function channelOf(e) {
            const m = /^uri:\/\/channel\/[^/]+\/(.+)$/.exec(e.id || "")
            const id = m ? m[1] : ""
            for (const t of root.teams) { const c = (t.channels || []).find(c => c.id === id); if (c) return { team: t.name || "", teamId: t.id, channel: c.name } }
            return { team: "", teamId: "", channel: id }
        }
        contentItem: Column {
            spacing: 0
            Item {
                width: parent.width; height: 32
                Text {
                    y: 2
                    text: qsTr("Don't show post from")
                    font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading
                }
                Rectangle {
                    id: closeSettings
                    anchors.right: parent.right; width: 32; height: 32; radius: 4; y: 0
                    color: closeHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeSettings, theme.textStrong) }
                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: settings.close() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
                }
            }
            Item { width: 1; height: 8 + 15 }
            Text {
                visible: settings.failed
                width: parent.width; wrapMode: Text.Wrap
                text: qsTr("We ran into a problem getting your settings.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Text {
                visible: !settings.loading && !settings.failed && settings.list.length === 0
                width: parent.width; wrapMode: Text.Wrap
                text: qsTr("You haven't specified anything. Go to post options to specify if you are not interested in a post.")
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
            }
            // The lists scroll inside the window's height.
            Flickable {
                visible: settings.list.length > 0
                width: parent.width
                height: !visible ? 0 : Math.min(groups.height, Math.max(120, (Overlay.overlay ? Overlay.overlay.height : 600) - 64 - 32 - 23 - 48))
                contentHeight: groups.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: groups
                    width: parent.width
                    // Teams' accordion (discover-user-pref-accordion, Teams web
                    // 2026-11-27): "People (N)" and "Channels (N)" (14/600 after
                    // a 20 px caret, 30 tall), each open with its list 10 in:
                    // rows 48 tall, the picture (32; a team's square, radius 4),
                    // the team's name over the channel's (14/20, the channel
                    // light) or the person's name, and Remove (a 32 px dismiss)
                    // at the end. Removed rows leave the list.
                    Repeater {
                        model: [{ key: "people", title: qsTr("People (%1)").arg(settings.people.filter(e => !settings.removed[e.id]).length), rows: settings.people },
                                { key: "channels", title: qsTr("Channels (%1)").arg(settings.channels.filter(e => !settings.removed[e.id]).length), rows: settings.channels }]
                        Column {
                            id: group
                            required property var modelData
                            property bool open: true
                            width: parent.width
                            Item {
                                width: parent.width; height: 30
                                FluentIcon { x: 0; anchors.verticalCenter: parent.verticalCenter; name: "caret-down-20-filled"; size: 20; color: theme.text; rotation: group.open ? 0 : -90 }
                                Text {
                                    x: 20; anchors.verticalCenter: parent.verticalCenter
                                    text: group.modelData.title
                                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: group.open = !group.open }
                                Accessible.role: Accessible.Button
                                Accessible.name: group.modelData.title
                            }
                            Repeater {
                                model: group.open ? group.modelData.rows.filter(e => !settings.removed[e.id]) : []
                                Item {
                                    id: pref
                                    required property var modelData
                                    readonly property bool channel: modelData.kind === "CHANNEL"
                                    readonly property var where: channel ? settings.channelOf(modelData) : null
                                    readonly property string label: channel ? (where ? where.channel : "") : modelData.name
                                    x: 10; width: group.width - 10; height: 48
                                    Avatar {
                                        x: 0; y: 8; size: 32; square: pref.channel
                                        name: pref.channel ? (pref.where ? pref.where.team : "") : pref.modelData.name || ""
                                        initialsText: pref.channel && pref.where ? pref.where.team.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
                                        photoId: pref.channel ? (pref.where ? "team:" + pref.where.teamId : "") : pref.modelData.id
                                    }
                                    Column {
                                        x: 42; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 42 - 40
                                        Text {
                                            visible: pref.channel
                                            width: parent.width; elide: Text.ElideRight
                                            text: pref.where ? pref.where.team : ""
                                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight
                                            text: pref.label
                                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                            font.weight: pref.channel ? Font.ExtraLight : Font.Normal
                                            color: theme.text
                                        }
                                    }
                                    Rectangle {
                                        id: prefButton
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 32; height: 32; radius: 4
                                        color: prefHover.hovered ? theme.hover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: prefHover.hovered ? "dismiss-20-filled" : "dismiss-20"; size: 20; color: theme.onFill(prefButton, theme.textStrong) }
                                        HoverHandler { id: prefHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                const id = pref.modelData.id
                                                const r = Object.assign({}, settings.removed); r[id] = true; settings.removed = r
                                                root.sendPref("discover-include", { kind: pref.modelData.kind, id: id, name: pref.modelData.name || "" },
                                                              () => { const b = Object.assign({}, settings.removed); delete b[id]; settings.removed = b })
                                            }
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: qsTr("Remove %1").arg(pref.label)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
