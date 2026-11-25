import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// A channel post's conversation: Teams' post view. It fills the channel's
// pane ("See details", inPane) or a window of its own (ThreadWindow,
// Teams' "Open conversation in new window"), measured on winpc
// (2026-11-09 window, 2026-11-10 pane, OST Test Team > General).
// - Header (entity-header: 61 tall, a 0.67 px #E0E0E0 line under it,
//   padding 0 7 0 20): the team's picture (32) at 20; the channel's name
//   (14/20 semibold) at 62, 9.7 down; "Post by {author}" (12/16, #616161)
//   under it, 31.7 down. At the right, in the pane: Go to channel (a text
//   button, 31.3 tall) and Open in new window (32), then a 1 px #F0F0F0 line
//   (from 18 down), Find in post (32) and More (32); in the window only the
//   line and More: Find in post (Ctrl+F), then Follow / Unfollow thread.
//   While finding, Find in post's toggle is brand.
// - Open Copilot (Teams' channel-copilot-button in its channel L2 header,
//   measured on winpc 2026-11-23, TASK-0263, OST Test Team > General and
//   OST test channel): after the line, before Find in post (pane: Go to
//   channel, Open in new window, line, Copilot W-107, Find W-75, More
//   W-43). Find in post shows only where the header is at least 640 wide,
//   else it is More's first item (a 588 wide window; the pane with
//   Copilot open). Open, Copilot's 360 pane (CopilotPane) sits at the
//   right and the post narrows beside it (a window too narrow for both:
//   the pane covers it); the button turns brand and filled ("Close
//   Copilot"), Alt+C toggles it, and Go to channel closes both. The app is
//   told the post as a channel thread (ChannelL2) whose reference names
//   the team, the channel and the post.
// - The thread on the channel page, 7 from the top: in the pane the post
//   and its replies centred at the channel's card width, in the window one
//   card 30 in (radius 8, Fluent shadow 4). The post: the author's 32 px
//   picture at (18, 16), the name (14/20) at 60, 13.4 down, the time
//   (12/17.14, #616161) under it at 33.4 (then "Edited"), the subject
//   (18/25.7 semibold) and text at (18, 64), its reactions 17 under the
//   text with the add button. A 0.67 px #F0F0F0 line, then each reply: a
//   20 px picture at (18, 8), the name (12/17.14) at 50, 8 down, the time
//   under it (25.1 down, then "Edited"), the text at (50, 42.2), 8 below
//   it. A channel meeting's post is its call start (subject `Meeting in
//   "<channel>"`, "… ended" once over); its call ends show as Teams' rows:
//   the video glyph (20, #616161) at (18, 16), the time and "Meeting ended:
//   <b>duration</b>" (12/16) at 54, 14 down.
// - "Reply in thread": Teams' compose at the bottom.
// - From Followed threads (`slice`, measured on winpc 2026-11-24, TASK-0265)
//   the view is the 512 wide place beside the list: no Find in post, and
//   Copilot is More's first item ("Copilot", Alt+C) until it is open (then
//   the button, brand, before More); More is Copilot and Follow/Unfollow
//   thread. Elsewhere More is Find in post (when it isn't inline), Follow
//   / Unfollow thread and View Copilot history (Teams' viewSummaryHistory:
//   its own Copilot's history for the post, in the Copilot pane's place),
//   with no divider. The header's second line is the post's subject
//   ("Post by {author}" without one). Under 640 wide the card is 30 in.
// - A Threads channel's followed thread (`chatThread`, winpc 2026-11-24):
//   this header (its second line the first message) over the thread as a
//   chat (Main's followedChat); More adds Mark as unread and Copy link.
// - A channel meeting's post: the header's second line is the meeting's
//   title, and its calendar card (ScheduledMeetingCard) sits over the text.
// The view stays on its thread (the backend keeps it loaded and live).
Item {
    id: win
    property string channelId: ""
    property string rootId: ""
    property string teamId: ""
    property string teamName: ""
    property string channelName: ""
    property string myName: ""
    /// In the channel's pane (Teams' post view) rather than a window.
    property bool inPane: false
    /// Opened from Followed threads.
    property bool slice: false
    /// A Threads-layout channel's thread (from Followed threads): only the
    /// header here; Main shows the thread as a chat under it (Teams'
    /// message pane with the "Send to" compose).
    property bool chatThread: false
    signal goToChannel()
    /// A channel meeting's calendar card: Join, and its details.
    signal joinMeeting(string url, string title)
    signal openMeetingDetails(string url, string start)
    signal popOut()
    /// A meeting end's Attendance card: the meeting's organizer, its post
    /// and the call.
    signal openAttendance(string organizer, string message, string call)
    readonly property string threadKey: channelId + ";messageid=" + rootId
    /// The post and its replies, oldest first.
    readonly property var thread: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[threadKey] || []
    }
    readonly property var post: thread.find(m => m.id === rootId) || null
    /// The header's second line, as Teams' channelDrillDownHeaderBaseData
    /// takes it: a meeting's title (`properties.meeting`), else the post's
    /// title or subject; a Threads channel's thread names its first
    /// message; otherwise "Post by {author}".
    readonly property string headerTitle: {
        if (!post) return ""
        const t = post.meeting_title || post.subject || ""
        if (t) return t
        if (chatThread) return String(post.text || "").split("\n")[0]
        return qsTr("Post by %1").arg(senderOf(post))
    }
    readonly property var scheduledMeeting: post ? post.scheduled_meeting || null : null
    readonly property bool copilotAvailable: { try { return !!JSON.parse(backend.composeCopilotJson || "{}").channelPost } catch (e) { return false } }
    property bool copilotOpen: false
    onRootIdChanged: copilotOpen = false
    onCopilotAvailableChanged: if (!copilotAvailable) copilotOpen = false
    onCopilotOpenChanged: if (copilotOpen) { finding = false; viewingFound = false; historyOpen = false }
    /// View Copilot history's pane (in Copilot's place).
    property bool historyOpen: false
    onHistoryOpenChanged: if (historyOpen) { copilotOpen = false; finding = false; viewingFound = false }
    function toggleCopilot() {
        if (!copilotAvailable) return
        copilotOpen = !copilotOpen
        console.info("COPILOT post view", copilotOpen)
    }
    /// The post as Copilot's pane names it: the team's thread, the channel,
    /// the post, the team's group.
    readonly property var copilotRequest: {
        if (!copilotOpen || !rootId) return null
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const t = teams.find(t => t.id === win.teamId) || teams.find(t => (t.channels || []).some(c => c.id === win.channelId)) || {}
        return { kind: "channel", thread: { teamId: t.thread_id || "", channelId: win.channelId, replyChainId: win.rootId, groupId: t.id || win.teamId,
                                            tenantId: backend.tenantId(), teamInReference: true } }
    }
    // Copilot's pane beside the post, or over all of it when there is no
    // room for both.
    readonly property bool copilotCovers: (copilotOpen || historyOpen) && width - 360 < 320
    readonly property real paneW: (copilotOpen || historyOpen) && !copilotCovers ? 360 : 0
    readonly property real viewW: width - paneW
    readonly property bool findInline: viewW >= 640
    // Teams shows a channel meeting's Attendance card to its organizer
    // (the join link's Oid).
    readonly property string meetingOrganizer: {
        const u = post ? (post.meeting_join_url || "") : ""
        let d = u
        try { d = decodeURIComponent(u) } catch (e) {}
        const m = d.match(/"Oid"\s*:\s*"([0-9a-fA-F-]{36})"/)
        return m ? m[1].toLowerCase() : ""
    }
    readonly property bool canSeeAttendance: meetingOrganizer !== "" && meetingOrganizer === backend.userOid
    // Replies: messages, and a meeting's call ends (its starts fold into
    // the post).
    readonly property var replies: thread.filter(m => m.id !== rootId && !(m.kind === "call" && m.call_state === "started"))
    // A channel meeting's post: live while a start has no end.
    readonly property bool meetingPost: !!post && post.kind === "call"
    readonly property bool meetingLive: meetingPost && thread.some(m => m.kind === "call" && m.call_state === "started" && m.call_active)
    readonly property string postSubject: !post ? "" : meetingPost
        ? (meetingLive ? (post.meeting_title || qsTr("Meeting in \"%1\"").arg(channelName)) : qsTr("%1 ended").arg(post.meeting_title || qsTr("Meeting in \"%1\"").arg(channelName)))
        : (post.subject || "")
    // Call events name people only by MRI.
    readonly property var peopleNames: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    function senderOf(m) { return !m ? "" : m.sender || peopleNames[m.sender_mri] || "" }
    onPostChanged: if (post && !post.sender && post.sender_mri && !peopleNames[post.sender_mri]) backend.resolveNames(JSON.stringify([post.sender_mri]))
    // The card: the channel's width in the pane, 30 in in the window.
    readonly property real cardW: inPane ? Math.min(1100, viewW - 2 * (viewW >= 640 ? 88 : 30)) : viewW - 62
    readonly property real cardX: inPane ? (viewW - cardW) / 2 : 30
    // Find in post: Teams' find pane over the window (under its title
    // row). A result opens in the thread with the terms marked; Escape goes
    // back to the results.
    property bool finding: false
    property bool viewingFound: false
    property var findMark: ({ id: "", terms: [] })
    function markFor(id) { return id && findMark.id === id ? findMark.terms : [] }
    function showFound(id, terms) {
        findMark = { id: id, terms: terms || [] }
        viewingFound = true
        Qt.callLater(() => {
            if (id === rootId) { flick.contentY = 0; return }
            const i = replies.findIndex(m => m.id === id)
            const item = i >= 0 ? replyRepeater.itemAt(i) : null
            if (item) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, item.mapToItem(card, 0, 0).y + card.y - flick.height / 3))
        })
    }
    Rectangle { anchors.fill: parent; color: theme.channelPage }
    property string openedKey: ""
    function reopen() {
        if (openedKey) { const p = openedKey.split(";messageid="); backend.closeThreadWindow(p[0], p[1]) }
        openedKey = channelId && rootId ? threadKey : ""
        if (openedKey) backend.openThreadWindow(channelId, rootId)
    }
    onThreadKeyChanged: reopen()
    Component.onCompleted: reopen()
    Component.onDestruction: if (openedKey) { const p = openedKey.split(";messageid="); backend.closeThreadWindow(p[0], p[1]) }

    // Test hooks.
    function composeForTest() { return compose }
    function hostForTest() { return thost }
    function postItemForTest() { return postItem }
    function flickForTest() { return flick }
    function findPaneForTest() { return findPane }
    function moreMenuForTest() { moreMenu.parent = moreButton; moreMenu.x = moreButton.width - moreMenu.implicitWidth; moreMenu.y = moreButton.height; moreMenu.open() }

    // The thread's message actions: its own menus and pickers, here.
    MessageHost {
        id: thost
        messages: win.thread
        isChannel: true
        teamId: win.teamId; teamName: win.teamName; chatName: win.channelName
        defaultBox: compose
        onQuoteRequested: m => { compose.quote = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.quote_text || m.text || "" }; compose.focusEditor() }
        onReactRequested: (id, key, on) => backend.toggleReaction(id, key, on)
        onDeleteRequested: id => backend.deleteMessage(id)
    }


    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        width: win.viewW; height: 61
        color: theme.channelPage
        Avatar {
            x: 20; y: 14.2
            size: 32; square: true; squareRadius: 2
            name: win.teamName
            initialsText: win.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: win.teamId ? "team:" + win.teamId : ""
        }
        Text {
            x: 62; y: 9.7
            width: toolbar.x - x - 8; elide: Text.ElideRight
            text: win.channelName
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            x: 62; y: 31.7
            width: toolbar.x - x - 8; elide: Text.ElideRight
            text: win.headerTitle
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        Row {
            id: toolbar
            anchors.right: parent.right; anchors.rightMargin: 11
            y: 14.2
            spacing: 0
            // The pane's Go to channel (close-l2-view-button: 14/20
            // #424242, padding 12) and Open in new window (btn-l2-popout).
            Rectangle {
                id: hcFill1
                visible: win.inPane
                width: goText.implicitWidth + 24; height: 31.3; radius: 4
                color: goHover.hovered ? theme.hover : "transparent"
                Text { id: goText; anchors.centerIn: parent; text: qsTr("Go to channel"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill1, theme.textStrong) }
                HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.goToChannel() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Go to channel")
            }
            Rectangle {
                id: hcFill2
                visible: win.inPane
                width: 32; height: 31.3; radius: 4
                color: popHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "open-window-20"; size: 20; color: theme.onFill(hcFill2, theme.textStrong) }
                HoverHandler { id: popHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.popOut() }
                ToolTip.visible: popHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Open in new window")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Open in new window")
            }
            Item { visible: win.inPane; width: 8; height: 1 }
            Rectangle {
                width: 1; height: 61 - 18; y: 18 - 14.2
                color: theme.pick("#F0F0F0", "#3D3D3D", "#000000")
            }
            Item { width: 7; height: 1 }
            // Open / Close Copilot (channel-copilot-button).
            Rectangle {
                id: copilotButton
                visible: win.copilotAvailable && (!win.slice || win.copilotOpen)
                width: 32; height: 32; radius: 4
                color: copilotHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: win.copilotOpen ? "copilot-filled-48" : "ai-copilot"; size: 20; color: theme.onFill(copilotButton, win.copilotOpen ? theme.brand : theme.textStrong) }
                HoverHandler { id: copilotHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.toggleCopilot() }
                ToolTip.visible: copilotHover.hovered; ToolTip.delay: 500
                ToolTip.text: (win.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot")) + " (Alt+C)"
                Accessible.role: Accessible.Button; Accessible.name: win.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot")
            }
            // Find in post: where the header is wide enough; otherwise
            // only while finding (brand, as the side pane's toggle).
            Rectangle {
                id: hcFill3
                visible: !win.slice && (win.finding || win.findInline)
                width: 32; height: 32; radius: 4
                color: findToggleHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "search-20"; size: 20; color: theme.onFill(hcFill3, win.finding ? theme.brand : theme.textStrong) }
                HoverHandler { id: findToggleHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.toggleFind() }
                ToolTip.visible: findToggleHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Find in post")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Find in post")
            }
            Rectangle {
                id: moreButton
                width: 32; height: 31.3; radius: 4
                color: moreHover.hovered || moreMenu.opened ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, moreMenu.opened ? theme.brand : theme.textStrong) }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.moreMenuForTest() }
                ToolTip.visible: moreHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("More channel options")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("More channel options")
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    MenuPopup {
        id: moreMenu
        margins: 8
        // (A Threads channel's thread adds Mark as unread and Copy link.)
        items: (win.slice ? (win.copilotAvailable && !win.copilotOpen ? [{ key: "copilot", label: qsTr("Copilot"), icon: "ai-copilot", keys: "Alt+C" }] : [])
                : win.findInline ? [] : [{ key: "find", label: qsTr("Find in post"), icon: "search-20", keys: "Ctrl+F" }]).concat([
            win.post && (win.post.following || (win.slice && win.post.follow_explicit !== false))
                ? { key: "unfollow", label: qsTr("Unfollow thread"), icon: "chat-multiple-minus-20" }
                : { key: "follow", label: qsTr("Follow thread"), icon: "chat-multiple-20" }
        ]).concat(win.chatThread ? [{ key: "unread", label: qsTr("Mark as unread"), icon: "glasses-off-20" }, { key: "link", label: qsTr("Copy link"), icon: "link-20" }] : [])
          .concat(win.slice || !win.copilotAvailable ? [] : [{ key: "history", label: qsTr("View Copilot history"), icon: "history-20" }])
        onPicked: i => {
            const k = items[i].key
            if (k === "find") win.toggleFind()
            else if (k === "copilot") win.toggleCopilot()
            else if (k === "history") win.historyOpen = true
            else if (k === "unread") { const last = win.thread.filter(m => m.kind === "message" && !m.deleted).pop(); if (last) backend.setThreadRead(win.rootId, "unread", last.id) }
            else if (k === "link") { if (win.post) backend.copyMessageLink(JSON.stringify({ id: win.post.id, sender: win.post.sender || "", text: win.post.text || "", root_id: win.post.id }), JSON.stringify({ team_id: win.teamId, team_name: win.teamName, channel_name: win.channelName })) }
            else if (win.post) backend.setThreadFollowing(win.post.id, k === "follow")
        }
    }
    Shortcut { sequence: "Ctrl+F"; enabled: !win.slice; onActivated: win.toggleFind() }
    Shortcut { sequence: "Alt+C"; enabled: win.visible && win.copilotAvailable && !!win.rootId; onActivated: win.toggleCopilot() }
    function toggleFind() { if (finding && viewingFound) { viewingFound = false; return } finding = !finding; viewingFound = false; if (finding) { copilotOpen = false; historyOpen = false } if (!finding) findMark = { id: "", terms: [] } }
    function copilotForTest() { return copilotPane }
    function moreItemsForTest() { const r = moreMenu.opened ? moreMenu.items.map(i => [i.label, i.keys || ""]) : null; moreMenu.close(); return r }
    CopilotPane {
        id: copilotPane
        z: 6
        open: win.copilotOpen && !!win.rootId
        request: win.copilotRequest
        x: win.copilotCovers ? 0 : win.width - width; y: 0
        width: !open ? 0 : win.copilotCovers ? win.width : 360
        height: win.height
        onClosed: win.copilotOpen = false
        onOpenLink: url => win.openCopilotLink(url)
    }
    CopilotHistoryPane {
        id: historyPane
        z: 6
        visible: win.historyOpen && !!win.rootId
        x: win.copilotCovers ? 0 : win.width - width; y: 0
        width: !visible ? 0 : win.copilotCovers ? win.width : 360
        height: win.height
        onClosed: win.historyOpen = false
    }
    function historyForTest() { return historyPane }
    /// A Source the app opened: a message of this post scrolls to it (the
    /// pane stays); anything else goes where the window's links go.
    function openCopilotLink(url) {
        const m = /^https:\/\/teams\.microsoft\.com\/l\/message\/([^/?#]+)\/([0-9]+)/.exec(url)
        const id = m && decodeURIComponent(m[1]) === win.channelId ? m[2] : ""
        const here = !!id && (id === win.rootId || win.replies.some(r => r.id === id))
        console.info("COPILOT post source", here ? "here" : "elsewhere", m ? m[2] : "")
        if (here) { win.showFound(id, []); return }
        if (typeof window !== "undefined" && window.openCopilotLink) window.openCopilotLink(url)
        else Qt.openUrlExternally(url)
    }

    FindPane {
        id: findPane
        z: 5
        visible: win.finding && !win.viewingFound
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom }
        windowed: true
        isChannel: true
        chatId: win.channelId
        postRoot: win.rootId
        channelGroup: win.teamId
        onVisibleChanged: if (visible) focusField()
        onClosed: { win.finding = false; win.viewingFound = false; win.findMark = { id: "", terms: [] } }
        onJumpTo: (hit, terms) => win.showFound(hit.id, terms)
    }
    Shortcut { sequence: "Escape"; enabled: win.finding && win.viewingFound; onActivated: win.viewingFound = false }

    // The thread
    Flickable {
        id: flick
        visible: !win.chatThread
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: compose.top; bottomMargin: 38.8; rightMargin: win.paneW }
        clip: true
        contentHeight: card.height + 7 + 3
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Opens at the newest reply.
        onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
        FluentSurface {
            id: card
            x: win.cardX; y: 7
            width: win.cardW
            height: col.height
            depth: 4; radius: 8
            color: theme.surface
            Column {
                id: col
                width: parent.width
                // The post
                Item {
                    id: postItem
                    width: parent.width
                    readonly property var m: win.post
                    readonly property bool editing: !!m && thost.editingId === m.id
                    readonly property var mark: editing ? null : thost.highlight(m)
                    height: !m ? 64 : editing ? (postEdit.item ? postEdit.item.height : 0) + 8 : postBody.y + postBody.height + 17 + 26 + 8.7
                    Rectangle {
                        visible: !!postItem.mark
                        x: 4; y: 16; width: 4; height: 32; radius: 2
                        color: postItem.mark ? postItem.mark.color : "transparent"
                    }
                    // Its badge, inside the card here (24 px, 12 from the end).
                    Item {
                        visible: !!postItem.mark && postItem.mark.icon !== ""
                        x: card.width - 36; y: 20; z: 6
                        width: 24; height: 24
                        FluentSurface { anchors.fill: parent; depth: 4; radius: 12; color: postItem.mark ? postItem.mark.color : "transparent" }
                        FluentIcon { x: 4; y: 4.5; size: 16; name: postItem.mark ? postItem.mark.icon : ""; color: "white" }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: postItem.mark ? postItem.mark.tip : ""
                    }
                    Avatar {
                        visible: !!postItem.m && !postItem.editing
                        x: 18; y: 16; size: 32
                        name: postItem.m ? win.senderOf(postItem.m) : ""
                        photoId: postItem.m ? postItem.m.sender_mri : ""
                    }
                    Text {
                        visible: !postItem.editing
                        x: 60; y: 13.4
                        text: postItem.m ? win.senderOf(postItem.m) : (win.thread.length ? "" : qsTr("Loading…"))
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: postItem.m ? theme.text : theme.textSecondary
                    }
                    Row {
                        visible: !!postItem.m && !postItem.editing
                        x: 60; y: 33.4
                        spacing: 8
                        Text {
                            text: postItem.m ? thost.conversationStamp(postItem.m.time) : ""
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                            color: theme.textSecondary
                        }
                        Text {
                            visible: !!postItem.m && postItem.m.edited === true
                            y: 0.5
                            text: qsTr("Edited")
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.textSecondary
                        }
                    }
                    // The post's subject (as in the channel: 18/600, 16 under).
                    Text {
                        id: postSubject
                        visible: !!postItem.m && !postItem.editing && !!win.postSubject
                        x: 18; y: 64; width: card.width - 36
                        wrapMode: Text.Wrap; bottomPadding: 16
                        textFormat: Text.RichText
                        text: win.postSubject ? theme.markTerms(win.postSubject.replace(/&/g, "&amp;").replace(/</g, "&lt;"), win.markFor(postItem.m ? postItem.m.id : "")) : ""
                        font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                        color: theme.text
                        Accessible.role: Accessible.Heading
                    }
                    // A channel meeting's calendar card (2 left of the text,
                    // 4 wider, 12 above it).
                    ScheduledMeetingCard {
                        id: meetingCard
                        visible: !!win.scheduledMeeting && !postItem.editing
                        x: 16; y: 64 + (postSubject.visible ? postSubject.height : 0)
                        width: card.width - 32; height: visible ? implicitHeight : 0
                        meeting: win.scheduledMeeting
                        organizer: !!win.scheduledMeeting && !!win.scheduledMeeting.organizer_id && (backend.userMri || "").toLowerCase().indexOf(win.scheduledMeeting.organizer_id.toLowerCase()) >= 0
                        onJoin: win.joinMeeting(win.scheduledMeeting.join_url, win.scheduledMeeting.title)
                        onOpenDetails: win.openMeetingDetails(win.scheduledMeeting.join_url, win.scheduledMeeting.start)
                    }
                    PostBody {
                        id: postBody
                        visible: !!postItem.m && !postItem.editing && !win.meetingPost
                        height: win.meetingPost ? 0 : implicitHeight
                        x: 18; y: 64 + (postSubject.visible ? postSubject.height : 0) + (meetingCard.visible ? meetingCard.height + 12 : 0); width: card.width - 36
                        message: postItem.m
                        mark: win.markFor(postItem.m ? postItem.m.id : "")
                    }
                    ReactionSummary {
                        visible: !!postItem.m && !postItem.editing
                        x: 18; y: postBody.y + postBody.height + 17
                        host: thost
                        messageId: postItem.m ? postItem.m.id : ""
                        reactions: postItem.m ? (postItem.m.reactions || []) : []
                    }
                    Loader {
                        id: postEdit
                        active: postItem.editing
                        x: 0; y: 0; width: card.width
                        // (A post: Teams' post composer.)
                        sourceComponent: win.meetingPost ? editComponent : postEditComponent
                        onLoaded: item.message = postItem.m
                    }
                    HoverHandler { id: postHover }
                    HoverBar {
                        id: postBar
                        visible: !!postItem.m && !postItem.m.deleted && !postItem.editing
                            && (postHover.hovered || postBar.hovered || thost.menuOpenFor(postItem.m.id, "post"))
                        host: thost
                        message: postItem.m || ({})
                        context: "post"
                        acts: postItem.m && postItem.m.mine
                            ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }]
                            : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }]
                        x: card.width - 10 - width; y: 11; z: 5
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !!postItem.m
                        onTapped: point => thost.openMessageMenu(postItem.m, postItem, true, point.position.x, point.position.y, "post")
                    }
                }
                Rectangle {
                    visible: win.replies.length > 0
                    width: parent.width; height: 0.67
                    color: theme.pick("#F0F0F0", "#3D3D3D", "#000000")
                }
                // The replies
                Repeater {
                    id: replyRepeater
                    model: win.replies
                    // A reply, under a day divider where the day changes
                    // (Teams' timestamp-divider: 16 tall, the day 12/16
                    // #424242 in the middle).
                    Column {
                        id: repSlot
                        required property var modelData
                        required property int index
                        readonly property var prev: index === 0 ? win.post : win.replies[index - 1]
                        readonly property string divider: prev && new Date(prev.time).toDateString() !== new Date(modelData.time).toDateString() ? thost.dayLabel(modelData.time) : ""
                        width: card.width
                        z: rep.z
                        Item {
                            visible: repSlot.divider !== ""
                            width: card.width; height: visible ? 16 : 0
                            Text {
                                anchors.centerIn: parent
                                text: repSlot.divider
                                font.family: theme.font; font.pixelSize: 12
                                lineHeight: 16; lineHeightMode: Text.FixedHeight
                                color: theme.textStrong
                            }
                            Accessible.role: Accessible.Separator
                            Accessible.name: repSlot.divider
                        }
                    Item {
                        id: rep
                        readonly property var modelData: repSlot.modelData
                        readonly property bool editing: thost.editingId === modelData.id
                        readonly property var mark: editing ? null : thost.highlight(modelData)
                        width: card.width
                        readonly property bool callRow: modelData.kind === "call"
                        // Teams' Attendance card under the end, at the text (54), 32 down.
                        readonly property bool attendanceCard: callRow && win.canSeeAttendance && modelData.call_state !== "missed" && modelData.call_state !== "started" && !!modelData.call_id
                        height: callRow ? (attendanceCard ? 32 + 49.3 + 12 : 52) : editing ? (repEdit.item ? repEdit.item.height : 0) + 8
                            : 42.2 + repBody.height + ((modelData.reactions || []).length > 0 ? 8 + 26 : 0) + 8.1
                        // A call's end (Teams' call row).
                        FluentIcon {
                            visible: rep.callRow
                            x: 18; y: 16; size: 20; name: "video-20"; color: theme.textSecondary
                        }
                        Text {
                            visible: rep.callRow
                            x: 54; y: 14
                            textFormat: Text.StyledText
                            text: {
                                if (!rep.callRow) return ""
                                const m = rep.modelData, s = m.call_seconds || 0
                                const parts = backend.durationText("call", s)
                                return theme.time(new Date(m.time)) + "&nbsp;&nbsp;&nbsp;" + (m.call_state === "missed" ? qsTr("Call missed") : qsTr("Meeting ended:") + "&nbsp;<b>" + parts + "</b>")
                            }
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        AttendanceCard {
                            visible: rep.attendanceCard
                            x: 54; y: 32
                            onClicked: win.openAttendance(win.meetingOrganizer, win.rootId, rep.modelData.call_id)
                        }
                        z: repHover.hovered || repBar.hovered ? 2 : 1
                        Rectangle {
                            visible: !!rep.mark
                            x: 4; y: 8; width: 4; height: 20; radius: 2
                            color: rep.mark ? rep.mark.color : "transparent"
                        }
                        Avatar {
                            visible: !rep.editing && !rep.callRow
                            x: 18; y: 8; size: 20
                            name: rep.modelData.sender; photoId: rep.modelData.sender_mri
                        }
                        Text {
                            visible: !rep.editing && !rep.callRow
                            x: 50; y: 8
                            text: rep.modelData.sender
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Row {
                            visible: !rep.editing && !rep.callRow
                            x: 50; y: 25.1
                            spacing: 8
                            Text {
                                text: thost.conversationStamp(rep.modelData.time)
                                font.family: theme.font; font.pixelSize: 12
                                lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                                color: theme.textSecondary
                            }
                            Text {
                                visible: rep.modelData.edited === true
                                y: 0.5
                                text: qsTr("Edited")
                                font.family: theme.font; font.pixelSize: 12
                                lineHeight: 16; lineHeightMode: Text.FixedHeight
                                color: theme.textSecondary
                            }
                        }
                        PostBody {
                            id: repBody
                            visible: !rep.editing && !rep.callRow
                            x: 50; y: 42.2; width: card.width - 70
                            message: rep.modelData
                            mark: win.markFor(rep.modelData ? rep.modelData.id : "")
                        }
                        ReactionSummary {
                            visible: !rep.editing && (rep.modelData.reactions || []).length > 0
                            x: 50; y: repBody.y + repBody.height + 8
                            host: thost
                            messageId: rep.modelData.id
                            reactions: rep.modelData.reactions || []
                        }
                        Loader {
                            id: repEdit
                            active: rep.editing
                            x: 0; y: 0; width: card.width
                            sourceComponent: editComponent
                            onLoaded: item.message = rep.modelData
                        }
                        HoverHandler { id: repHover }
                        HoverBar {
                            id: repBar
                            visible: !rep.modelData.deleted && !rep.editing && !rep.callRow
                                && (repHover.hovered || repBar.hovered || thost.menuOpenFor(rep.modelData.id, "reply"))
                            host: thost
                            message: rep.modelData
                            context: "reply"
                            acts: rep.modelData.mine
                                ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }]
                                : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }]
                            // Flush with the card's end, 28 above the reply
                            // (its bottom 4 into it), as measured.
                            x: rep.width - width; y: -28; z: 5
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: point => thost.openMessageMenu(rep.modelData, rep, true, point.position.x, point.position.y, "reply")
                        }
                    }
                    }
                }
            }
            Accessible.role: Accessible.Grouping
            Accessible.name: win.post ? qsTr("Post by %1").arg(win.senderOf(win.post)) : qsTr("Post")
        }
    }

    // The in-place editor for the post or a reply (Teams' compose).
    Component {
        id: editComponent
        ComposeBox {
            id: box
            property var message: null
            editing: true
            onMessageChanged: if (message) { quote = message.quote || null; setMessage(message); focusEditor() }
            onQuoteDismissed: quote = null
            onEmojiRequested: a => thost.openEmojiFor(box)
            // (Teams' edit box: Attach files and Actions and apps too,
            // TASK-0263.)
            chatId: win.channelId
            chatTitle: win.channelName
            editTeamId: win.teamId; editTeamName: win.teamName
            onSubmit: {
                backend.editMessageWith(message.id, formattedText(), quote ? JSON.stringify(quote) : "", JSON.stringify(mediaInUse()), editExtras())
                editSent()
                thost.editingId = ""
            }
            onCancelled: thost.editingId = ""
        }
    }

    // A post's edit: Teams' post composer (TASK-0265).
    Component {
        id: postEditComponent
        ComposeBox {
            id: pbox
            property var message: null
            editing: true
            post: true
            onMessageChanged: if (message) { setMessage(message); focusEditor() }
            onEmojiRequested: a => thost.openEmojiFor(pbox)
            chatId: win.channelId
            chatTitle: win.channelName
            editTeamId: win.teamId; editTeamName: win.teamName
            onSubmit: {
                backend.editMessageWith(message.id, formattedText(), "", JSON.stringify(mediaInUse()), editExtras())
                editSent()
                thost.editingId = ""
            }
            onCancelled: thost.editingId = ""
        }
    }

    // Reply in thread
    ComposeBox {
        id: compose
        visible: !win.chatThread
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: win.inPane ? Math.max(28, win.cardX - 12) : 28; anchors.rightMargin: win.paneW + (win.inPane ? Math.max(30, win.cardX - 12) : 30)
        anchors.bottomMargin: 8.7 // its box 26.7 above the bottom (the hint row is 18)
        placeholder: qsTr("Reply in thread")
        deliveryOptions: false
        mentionDirectory: false
        channelMention: ({ id: win.channelId, name: win.channelName })
        canAddAgent: true
        onAddAgentRequested: agentStoreRequested(win.channelId)
        teamMention: {
            if (!win.teamId) return null
            const t = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === win.teamId)
            const general = t ? (t.channels.find(c => c.name === "General") || t.channels[0]) : null
            return general ? { id: general.id, name: win.teamName, groupId: win.teamId } : null
        }
        tagMentions: {
            const all = backend.teamTagsJson ? JSON.parse(backend.teamTagsJson) : {}
            return teamMention ? (all[teamMention.id] || []) : []
        }
        files: win.pendingFiles
        onFileRemoved: path => win.pendingFiles = win.pendingFiles.filter(p => p !== path)
        // Teams' Attach popover, as in the channel (its suggestions, Attach
        // cloud files, Browse Teams and Channels, Upload from this device).
        chatId: win.channelId
        cloudFiles: cloudAttach.pending
        onCloudRemoved: key => cloudAttach.remove(key)
        onCloudLinkRequested: key => cloudAttach.openLink(key)
        onQuoteDismissed: quote = null
        onEmojiRequested: a => thost.openEmojiFor(compose)
        onAttachRequested: a => win.openAttach(a)
        onSubmit: win.send()
        onCancelled: { quote = null; win.pendingFiles = []; cloudAttach.clear() }
        Component.onCompleted: if (!win.inPane) focusEditor()
    }
    signal agentStoreRequested(string channelId)
    property var pendingFiles: []
    CloudAttach {
        id: cloudAttach
        chatId: win.channelId
        channel: true
        teamName: win.teamName
        teamId: win.teamId
        onUploadRequested: filePicker.open()
        onFailed: text => compose.showBanner(text, false, 3000)
    }
    function openAttach(anchor) {
        cloudAttach.context = win.thread.filter(m => m.kind !== "call" && !m.deleted).slice(-3).reverse()
            .map(m => ({ id: m.id, text: m.text || "", sender: String(m.sender_mri || "").replace(/^8:orgid:/, ""), time: m.time }))
        cloudAttach.openMenu(anchor || compose)
    }
    function cloudAttachForTest() { return cloudAttach }
    function send() {
        if (win.pendingFiles.length || cloudAttach.hasFiles) {
            backend.sendThreadFiles(channelId, rootId, win.pendingFiles.concat(cloudAttach.lines()).join("\n"), compose.plainText())
            win.pendingFiles = []
            cloudAttach.clear()
        } else {
            backend.sendThreadReply(channelId, rootId, compose.formattedText(), JSON.stringify(compose.mediaInUse()), compose.quote ? JSON.stringify(compose.quote) : "", false)
        }
        compose.quote = null
        compose.clear()
    }
    FileDialog {
        id: filePicker
        title: qsTr("Upload from this device")
        fileMode: FileDialog.OpenFiles
        onAccepted: win.pendingFiles = win.pendingFiles.concat(selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
    }
}
