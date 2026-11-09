import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// A channel post's conversation in a window of its own: Teams' "Open
// conversation in new window" (measured on winpc, 2026-11-09, in OST Test
// Team > General).
// - The window opens 588 x 493, titled "<team> | <channel>", with Teams'
//   child-window title row.
// - Header (entity-header: 61 tall, #FAFAFA, a 0.67 px #E0E0E0 line under
//   it, padding 0 7 0 20): the team's picture (32) at 20; the channel's
//   name (14/20 semibold) at 62, 9.7 down; "Post by {author}" (12/16,
//   #616161) under it, 31.7 down. At the right a 1 px #F0F0F0 line (from
//   18 down) and More channel options (32 x 31.3): Find in post (Ctrl+F),
//   then Follow / Unfollow thread. While finding, Find in post's toggle
//   (brand) shows before it.
// - The thread on #FAFAFA, 7 from the top and 30 in: one 526-wide card
//   (radius 8, Fluent shadow 4). The post: the author's 32 px picture at
//   (18, 16), the name (14/20) at 60, 13.4 down, the time (12/17.14,
//   #616161) under it at 33.4 (then "Edited"), the text at (18, 64), and
//   its reactions 17 under the text with the add button. A 0.67 px #F0F0F0
//   line, then each reply: a 20 px picture at (18, 8), the name (12/17.14)
//   at 50, 8 down, the time under it (25.1 down, then "Edited"), the text
//   at (50, 42.2), 8 below it.
// - "Reply in thread": Teams' compose, 28 in, 26.7 above the bottom.
// The window stays on its thread (the backend keeps it loaded and live)
// whatever the main window shows.
Window {
    id: win
    property string channelId: ""
    property string rootId: ""
    property string teamId: ""
    property string teamName: ""
    property string channelName: ""
    property string myName: ""
    property bool pinned: false
    readonly property string threadKey: channelId + ";messageid=" + rootId
    /// The post and its replies, oldest first.
    readonly property var thread: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return (all[threadKey] || []).filter(m => m.kind !== "call")
    }
    readonly property var post: thread.find(m => m.id === rootId) || null
    readonly property var replies: thread.filter(m => m.id !== rootId)
    // Find in post: the messages whose text has the words.
    property bool finding: false
    readonly property var findHits: {
        const q = findField.text.trim().toLowerCase()
        if (!finding || !q) return []
        return thread.filter(m => (m.text || "").toLowerCase().indexOf(q) >= 0).map(m => m.id)
    }
    title: teamName + " | " + channelName
    width: 588; height: 493
    color: theme.channelPage
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    Component.onCompleted: backend.openThreadWindow(channelId, rootId)
    onClosing: backend.closeThreadWindow(channelId, rootId)

    // Test hooks.
    function composeForTest() { return compose }
    function hostForTest() { return thost }
    function postItemForTest() { return postItem }
    function flickForTest() { return flick }
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

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }

    // Header
    Rectangle {
        id: header
        anchors.top: titleRow.bottom
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
            text: win.post ? "Post by " + win.post.sender : ""
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        Row {
            id: toolbar
            anchors.right: parent.right; anchors.rightMargin: 11
            y: 14.2
            spacing: 0
            Rectangle {
                width: 1; height: 61 - 18; y: 18 - 14.2
                color: theme.pick("#F0F0F0", "#3D3D3D")
            }
            Item { width: 7; height: 1 }
            // Find in post, while finding (brand, as the side pane's toggle).
            Rectangle {
                visible: win.finding
                width: 32; height: 32; radius: 4
                color: findToggleHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "search-20"; size: 20; color: theme.brand }
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
    function toggleFind() { finding = !finding; if (finding) findField.forceActiveFocus(); else findField.text = "" }

    // Find in post: OST's find bar, as in the channel (Teams' find pane is
    // TASK-0051).
    Rectangle {
        id: findBar
        visible: win.finding
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        height: visible ? 48 : 0
        color: theme.surface
        Rectangle {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32; height: 32; radius: theme.radius
            color: theme.input
            border.color: findField.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: findField
                x: 32; width: parent.width - 120
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                Keys.onEscapePressed: win.toggleFind()
                Text { visible: !findField.text; text: "Find in post"; color: theme.textTertiary; font: findField.font }
                Accessible.name: "Find in post"
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                visible: findField.text.length > 0
                text: win.findHits.length ? win.findHits.length + (win.findHits.length === 1 ? " result" : " results") : "No results"
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
            }
        }
    }

    // The thread
    Flickable {
        id: flick
        anchors { top: findBar.bottom; left: parent.left; right: parent.right; bottom: compose.top; bottomMargin: 38.8 }
        clip: true
        contentHeight: card.height + 7 + 3
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Opens at the newest reply.
        onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
        FluentSurface {
            id: card
            x: 30; y: 7
            width: win.width - 62
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
                    readonly property bool hit: !!m && win.findHits.indexOf(m.id) >= 0
                    height: !m ? 64 : editing ? (postEdit.item ? postEdit.item.height : 0) + 8 : postBody.y + postBody.height + 17 + 26 + 8.7
                    Rectangle { anchors.fill: parent; visible: postItem.hit; radius: 8; color: theme.pick("#FFF4CE", "#463100") }
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
                        name: postItem.m ? postItem.m.sender : ""
                        photoId: postItem.m ? postItem.m.sender_mri : ""
                    }
                    Text {
                        visible: !postItem.editing
                        x: 60; y: 13.4
                        text: postItem.m ? postItem.m.sender : (win.thread.length ? "" : "Loading…")
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
                    MessageText {
                        id: postBody
                        visible: !!postItem.m && !postItem.editing
                        x: 18; y: 64; width: card.width - 36
                        message: postItem.m
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
                        readonly property bool hit: win.findHits.indexOf(modelData.id) >= 0
                        width: card.width
                        height: editing ? (repEdit.item ? repEdit.item.height : 0) + 8
                            : 42.2 + repBody.height + ((modelData.reactions || []).length > 0 ? 8 + 26 : 0) + 8.1
                        z: repHover.hovered || repBar.hovered ? 2 : 1
                        Rectangle { anchors.fill: parent; visible: rep.hit; color: theme.pick("#FFF4CE", "#463100") }
                        Rectangle {
                            visible: !!rep.mark
                            x: 4; y: 8; width: 4; height: 20; radius: 2
                            color: rep.mark ? rep.mark.color : "transparent"
                        }
                        Avatar {
                            visible: !rep.editing
                            x: 18; y: 8; size: 20
                            name: rep.modelData.sender; photoId: rep.modelData.sender_mri
                        }
                        Text {
                            visible: !rep.editing
                            x: 50; y: 8
                            text: rep.modelData.sender
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Row {
                            visible: !rep.editing
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
                            visible: !rep.editing
                            x: 50; y: 42.2; width: card.width - 70
                            message: rep.modelData
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
                            visible: !rep.modelData.deleted && !rep.editing
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
            Accessible.name: win.post ? "Post by " + win.post.sender : "Post"
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
        anchors.leftMargin: 28; anchors.rightMargin: 30; anchors.bottomMargin: 8.7 // its box 26.7 above the bottom (the hint row is 18)
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
        Component.onCompleted: focusEditor()
    }
    signal agentStoreRequested(string channelId)
    property var pendingFiles: []
    function send() {
        if (win.pendingFiles.length) {
            backend.sendThreadFiles(channelId, rootId, win.pendingFiles.join("\n"), compose.plainText())
            win.pendingFiles = []
        } else {
            backend.sendThreadReply(channelId, rootId, compose.formattedText(), JSON.stringify(compose.mediaInUse()), compose.quote ? JSON.stringify(compose.quote) : "")
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
