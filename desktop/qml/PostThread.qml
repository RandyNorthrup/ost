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
    signal goToChannel()
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
    // Teams shows a channel meeting's Attendance card to its organizer
    // (the join link's Oid).
    readonly property string meetingOrganizer: {
        const u = post ? (post.meeting_join_url || "") : ""
        let d = u
        try { d = decodeURIComponent(u) } catch (e) {}
        const m = d.match(/"Oid"\s*:\s*"([0-9a-fA-F-]{36})"/)
        return m ? m[1].toLowerCase() : ""
    }
    readonly property bool canSeeAttendance: meetingOrganizer !== "" && meetingOrganizer === (backend.userMri || "").replace("8:orgid:", "").toLowerCase()
    // Replies: messages, and a meeting's call ends (its starts fold into
    // the post).
    readonly property var replies: thread.filter(m => m.id !== rootId && !(m.kind === "call" && m.call_state === "started"))
    // A channel meeting's post: live while a start has no end.
    readonly property bool meetingPost: !!post && post.kind === "call"
    readonly property bool meetingLive: meetingPost && thread.some(m => m.kind === "call" && m.call_state === "started" && m.call_active)
    readonly property string postSubject: !post ? "" : meetingPost
        ? (post.meeting_title || "Meeting in \"" + channelName + "\"") + (meetingLive ? "" : " ended")
        : (post.subject || "")
    // Call events name people only by MRI.
    readonly property var peopleNames: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    function senderOf(m) { return !m ? "" : m.sender || peopleNames[m.sender_mri] || "" }
    onPostChanged: if (post && !post.sender && post.sender_mri && !peopleNames[post.sender_mri]) backend.resolveNames(JSON.stringify([post.sender_mri]))
    // The card: the channel's width in the pane, 30 in in the window.
    readonly property real cardW: inPane ? Math.min(1100, width - 2 * (width > 480 ? 88 : 16)) : width - 62
    readonly property real cardX: inPane ? (width - cardW) / 2 : 30
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
        width: parent.width; height: 61
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
            text: win.post ? "Post by " + win.senderOf(win.post) : ""
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
                visible: win.inPane
                width: goText.implicitWidth + 24; height: 31.3; radius: 4
                color: goHover.hovered ? theme.hover : "transparent"
                Text { id: goText; anchors.centerIn: parent; text: "Go to channel"; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.goToChannel() }
                Accessible.role: Accessible.Button; Accessible.name: "Go to channel"
            }
            Rectangle {
                visible: win.inPane
                width: 32; height: 31.3; radius: 4
                color: popHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "open-window-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: popHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.popOut() }
                ToolTip.visible: popHover.hovered; ToolTip.delay: 500; ToolTip.text: "Open in new window"
                Accessible.role: Accessible.Button; Accessible.name: "Open in new window"
            }
            Item { visible: win.inPane; width: 8; height: 1 }
            Rectangle {
                width: 1; height: 61 - 18; y: 18 - 14.2
                color: theme.pick("#F0F0F0", "#3D3D3D")
            }
            Item { width: 7; height: 1 }
            // Find in post: always in the pane; in the window while finding
            // (brand, as the side pane's toggle).
            Rectangle {
                visible: win.finding || win.inPane
                width: 32; height: 32; radius: 4
                color: findToggleHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "search-20"; size: 20; color: win.finding ? theme.brand : theme.textStrong }
                HoverHandler { id: findToggleHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.toggleFind() }
                ToolTip.visible: findToggleHover.hovered; ToolTip.delay: 500; ToolTip.text: "Find in post"
                Accessible.role: Accessible.Button; Accessible.name: "Find in post"
            }
            Rectangle {
                id: moreButton
                width: 32; height: 31.3; radius: 4
                color: moreHover.hovered || moreMenu.opened ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: moreMenu.opened ? theme.brand : theme.textStrong }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.moreMenuForTest() }
                ToolTip.visible: moreHover.hovered; ToolTip.delay: 500; ToolTip.text: "More channel options"
                Accessible.role: Accessible.Button; Accessible.name: "More channel options"
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    MenuPopup {
        id: moreMenu
        margins: 8
        items: [
            { key: "find", label: "Find in post", icon: "search-20", keys: "Ctrl+F" },
            { separator: true },
            win.post && win.post.following
                ? { key: "unfollow", label: "Unfollow thread", icon: "chat-multiple-minus-20" }
                : { key: "follow", label: "Follow thread", icon: "chat-multiple-20" }
        ]
        onPicked: i => {
            const k = items[i].key
            if (k === "find") win.toggleFind()
            else if (win.post) backend.setThreadFollowing(win.post.id, k === "follow")
        }
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: win.toggleFind() }
    function toggleFind() { if (finding && viewingFound) { viewingFound = false; return } finding = !finding; viewingFound = false; if (!finding) findMark = { id: "", terms: [] } }

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
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: compose.top; bottomMargin: 38.8 }
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
                        text: postItem.m ? win.senderOf(postItem.m) : (win.thread.length ? "" : "Loading…")
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
                            text: "Edited"
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
                    MessageText {
                        id: postBody
                        visible: !!postItem.m && !postItem.editing && !win.meetingPost
                        height: win.meetingPost ? 0 : implicitHeight
                        x: 18; y: 64 + (postSubject.visible ? postSubject.height : 0); width: card.width - 36
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
                        sourceComponent: editComponent
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
                            ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                            : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }]
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
                    color: theme.pick("#F0F0F0", "#3D3D3D")
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
                                const parts = [[Math.floor(s / 3600) % 24, "h"], [Math.floor(s / 60) % 60, "m"], [s % 60, "s"]]
                                    .filter(p => p[0] > 0).map(p => p[0] + p[1]).join(" ")
                                return Qt.formatTime(new Date(m.time), "h:mm AP") + "&nbsp;&nbsp;&nbsp;" + (m.call_state === "missed" ? "Call missed" : "Meeting ended:&nbsp;<b>" + parts + "</b>")
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
                                text: "Edited"
                                font.family: theme.font; font.pixelSize: 12
                                lineHeight: 16; lineHeightMode: Text.FixedHeight
                                color: theme.textSecondary
                            }
                        }
                        MessageText {
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
                                ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                                : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }]
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
            Accessible.name: win.post ? "Post by " + win.senderOf(win.post) : "Post"
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
            onSubmit: { backend.editMessageRich(message.id, formattedText(), quote ? JSON.stringify(quote) : "", JSON.stringify(mediaInUse())); thost.editingId = "" }
            onCancelled: thost.editingId = ""
        }
    }

    // Reply in thread
    ComposeBox {
        id: compose
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: win.inPane ? Math.max(28, win.cardX - 12) : 28; anchors.rightMargin: win.inPane ? Math.max(30, win.cardX - 12) : 30
        anchors.bottomMargin: 8.7 // its box 26.7 above the bottom (the hint row is 18)
        placeholder: "Reply in thread"
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
        onQuoteDismissed: quote = null
        onEmojiRequested: a => thost.openEmojiFor(compose)
        onAttachRequested: filePicker.open()
        onSubmit: win.send()
        onCancelled: { quote = null; win.pendingFiles = [] }
        Component.onCompleted: if (!win.inPane) focusEditor()
    }
    signal agentStoreRequested(string channelId)
    property var pendingFiles: []
    function send() {
        if (win.pendingFiles.length) {
            backend.sendThreadFiles(channelId, rootId, win.pendingFiles.join("\n"), compose.plainText())
            win.pendingFiles = []
        } else {
            backend.sendThreadReply(channelId, rootId, compose.formattedText(), JSON.stringify(compose.mediaInUse()), compose.quote ? JSON.stringify(compose.quote) : "", false)
        }
        compose.quote = null
        compose.clear()
    }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: win.pendingFiles = win.pendingFiles.concat(selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
    }
}
