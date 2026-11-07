import QtQuick
import QtQuick.Controls.Basic

// A channel's Posts, as Teams desktop draws them (measured at 1x): each
// post is a white card on a #FAFAFA page with the author and time, the
// post, an add-reaction button, then its replies under a divider and a
// "Reply in thread" row that opens an inline reply box. Posts are ordered
// by their latest activity, newest at the bottom, above the brand
// "Post in channel" button.
Item {
    id: root
    /// The channel's messages, oldest first (each with root_id).
    property var messages: []
    property string myName: ""
    property bool busy: false
    // The Conversation: its hover-bar rules, menus, pickers and edit state.
    property var host: null
    signal reply(string rootId, string text)
    signal startPost()
    signal react(string messageId, string key, bool on)
    /// The post whose reply box is open.
    property string replying: ""
    function toEnd() { list.positionViewAtEnd() }
    /// For the test harness: reply to the newest post.
    function replyToNewestForTest(text) {
        if (root.posts.length === 0) return false
        root.reply(root.posts[root.posts.length - 1].id, text)
        return true
    }
    /// Posts whose earlier replies are shown.
    property var expanded: ({})

    readonly property var posts: {
        const byRoot = {}, order = []
        for (const m of root.messages) {
            if (m.kind === "call") continue
            const r = m.root_id || m.id
            if (!byRoot[r]) { byRoot[r] = { id: r, post: null, replies: [], last: 0 }; order.push(r) }
            const g = byRoot[r]
            if (m.id === r) g.post = m; else g.replies.push(m)
            g.last = Math.max(g.last, parseInt(m.id) || 0)
        }
        // Replies whose post is older than the loaded page still show,
        // under a placeholder header.
        const out = order.map(r => byRoot[r])
        out.sort((a, b) => a.last - b.last)
        return out
    }

    Rectangle { anchors.fill: parent; color: theme.channelPage }

    ListView {
        id: list
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: postButton.top; bottomMargin: 16 }
        clip: true
        spacing: 12
        // Newest activity at the bottom: posts sit at the top while they
        // fit, and the list opens scrolled to the end once they don't.
        model: root.posts
        onCountChanged: Qt.callLater(positionViewAtEnd)
        topMargin: 8; bottomMargin: 8
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real cardW: Math.min(1100, width - 2 * (width > 480 ? 88 : 16))
        delegate: Item {
            id: slot
            required property var modelData
            width: list.width; height: card.height
        Rectangle {
            id: card
            readonly property var modelData: slot.modelData
            readonly property var post: modelData.post
            readonly property var replies: modelData.replies
            readonly property bool open: root.replying === modelData.id
            readonly property bool showAll: root.expanded[modelData.id] === true
            readonly property var shown: showAll || replies.length <= 3 ? replies : replies.slice(replies.length - 3)
            x: (list.width - width) / 2
            width: list.cardW
            height: col.height
            radius: 4
            color: theme.surface
            border.color: theme.cardEdge
            Column {
                id: col
                width: parent.width
                // The post
                Item {
                    width: parent.width
                    height: !card.post ? 44 : postEdit.active ? (postEdit.item ? postEdit.item.height : 0) + 8 : postBody.y + postBody.height + 51
                    Avatar {
                        id: av
                        visible: !!card.post && !postEdit.active
                        x: 18; y: 16; size: 32
                        name: card.post ? card.post.sender : ""
                        photoId: card.post ? card.post.sender_mri : ""
                    }
                    Row {
                        visible: !postEdit.active
                        x: card.post ? 60 : 18; y: card.post ? 22 : 14
                        spacing: 10
                        Text {
                            text: card.post ? card.post.sender : "Earlier post"
                            font.family: theme.font; font.pixelSize: theme.base
                            color: card.post ? theme.text : theme.textSecondary
                        }
                        Text {
                            visible: !!card.post
                            y: 2
                            text: card.post ? root.conversationStamp(card.post.time) : ""
                            font.family: theme.font; font.pixelSize: theme.small
                            color: theme.textSecondary
                        }
                        Text {
                            visible: !!card.post && card.post.edited === true
                            y: 2
                            text: "Edited"
                            font.family: theme.font; font.pixelSize: theme.small
                            color: theme.textSecondary
                        }
                    }
                    MessageText {
                        id: postBody
                        visible: !!card.post && !postEdit.active
                        x: 18; y: 64; width: card.width - 36
                        message: card.post
                    }
                    // Teams' reaction summary, 17 under the body; posts show the
                    // add button even with no reactions.
                    ReactionSummary {
                        visible: !!card.post && !postEdit.active
                        x: 18; y: postBody.y + postBody.height + 17
                        host: root.host
                        messageId: card.post ? card.post.id : ""
                        reactions: card.post ? (card.post.reactions || []) : []
                    }
                    // Edit in place.
                    Loader {
                        id: postEdit
                        active: !!card.post && !!root.host && root.host.editingId === card.post.id
                        x: 0; y: 0; width: card.width
                        sourceComponent: editComponent
                        onLoaded: item.message = card.post
                    }
                    // Teams' hover bar, inside the card 10 from its end and 11
                    // down (channel-message-action-menu, measured).
                    HoverHandler { id: postHover }
                    HoverBar {
                        id: postBar
                        visible: !!card.post && !!root.host && !card.post.deleted && !postEdit.active
                            && (postHover.hovered || postBar.hovered || root.host.menuOpenFor(card.post.id, "post"))
                        host: root.host
                        message: card.post || ({})
                        context: "post"
                        acts: card.post && card.post.mine
                            ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                            : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }]
                        x: card.width - 10 - width; y: 11; z: 5
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !!card.post && !!root.host
                        onTapped: point => root.host.openMessageMenu(card.post, card, true, point.position.x, point.position.y, "post")
                    }
                }
                // Earlier replies, collapsed.
                Item {
                    visible: card.replies.length > card.shown.length
                    width: parent.width; height: visible ? 40 : 0
                    Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                    Text {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        text: (card.replies.length - card.shown.length) + " earlier "
                            + (card.replies.length - card.shown.length === 1 ? "reply" : "replies")
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                        color: theme.brand
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const e = Object.assign({}, root.expanded); e[card.modelData.id] = true; root.expanded = e
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                    }
                }
                // Replies (response-surface, measured): a NeutralStroke3 line on
                // top, 8.7 in; each reply a 20 px avatar at 18, the name and
                // time (12 px) at 50, the text 20 down, then 16 to the next.
                Item {
                    visible: card.shown.length > 0
                    width: card.width
                    height: visible ? 8.7 + replyCol.height - 16 + 8 : 0
                    Rectangle {
                        visible: card.replies.length === card.shown.length
                        width: parent.width; height: 0.67; color: theme.quoteBorder
                    }
                    Column {
                        id: replyCol
                        y: 8.7
                        width: parent.width
                        Repeater {
                            model: card.shown
                            Item {
                                id: rep
                                required property var modelData
                                required property int index
                                readonly property bool editing: !!root.host && root.host.editingId === modelData.id
                                width: card.width
                                // Editing, Teams' compose spans the card in the reply's
                                // place, from the line above it.
                                height: editing ? (repEdit.item ? repEdit.item.height : 0) - 7.4 + 11.4
                                    : 20 + repBody.height + ((modelData.reactions || []).length > 0 ? 8 + 26 : 0) + 16
                                z: repHover.hovered || repBar.hovered ? 2 : 1
                                Avatar {
                                    visible: !rep.editing
                                    x: 18; y: 0; size: 20
                                    name: rep.modelData.sender; photoId: rep.modelData.sender_mri
                                }
                                Row {
                                    visible: !rep.editing
                                    x: 50; y: 1.4
                                    spacing: 8
                                    Text { text: rep.modelData.sender; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                                    Text { text: root.conversationStamp(rep.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                    Text { visible: rep.modelData.edited === true; text: "Edited"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                }
                                MessageText {
                                    id: repBody
                                    visible: !rep.editing
                                    x: 50; y: 20; width: card.width - 70
                                    message: rep.modelData
                                }
                                Loader {
                                    id: repEdit
                                    active: rep.editing
                                    x: 0; y: -7.4; width: card.width
                                    sourceComponent: editComponent
                                    onLoaded: item.message = rep.modelData
                                }
                                ReactionSummary {
                                    visible: !rep.editing && (rep.modelData.reactions || []).length > 0
                                    x: 50; y: repBody.y + repBody.height + 8
                                    host: root.host
                                    messageId: rep.modelData.id
                                    reactions: rep.modelData.reactions || []
                                }
                                // Hover bar: at the card's end, its bottom 3.7
                                // above the reply (measured).
                                HoverHandler { id: repHover }
                                HoverBar {
                                    id: repBar
                                    visible: !!root.host && !rep.modelData.deleted && !rep.editing
                                        && (repHover.hovered || repBar.hovered || root.host.menuOpenFor(rep.modelData.id, "reply"))
                                    host: root.host
                                    message: rep.modelData
                                    context: "reply"
                                    acts: rep.modelData.mine
                                        ? [{ key: "edit", icon: "edit-20", tip: "Edit" }]
                                        : [{ key: "reply", icon: "quote-reply-20", tip: "Reply with quote" }]
                                    x: rep.width - width; y: -3.7 - height; z: 5
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    enabled: !!root.host
                                    onTapped: point => root.host.openMessageMenu(rep.modelData, rep, true, point.position.x, point.position.y, "reply")
                                }
                            }
                        }
                    }
                }
                // Reply in thread / the reply box.
                Item {
                    width: card.width
                    height: card.open ? 74 : 47
                    Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                    Avatar {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        size: 20; name: root.myName || "You"; photoId: "me"
                    }
                    Text {
                        visible: !card.open
                        x: 50; anchors.verticalCenter: parent.verticalCenter
                        text: "Reply in thread"
                        font.family: theme.font; font.pixelSize: theme.base
                        color: theme.textSecondary
                    }
                    MouseArea {
                        visible: !card.open
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.replying = card.modelData.id; replyBox.input.forceActiveFocus() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Reply in thread"
                    }
                    Rectangle {
                        id: replyBox
                        property alias input: replyInput
                        visible: card.open
                        x: 48; anchors.verticalCenter: parent.verticalCenter
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
                            placeholderText: "Reply in thread"
                            placeholderTextColor: theme.textSecondary
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.text
                            wrapMode: TextArea.Wrap
                            background: Item {}
                            function submit() {
                                if (!text.trim()) return
                                root.reply(card.modelData.id, text.trim())
                                text = ""
                                root.replying = ""
                            }
                            Keys.onReturnPressed: e => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else submit() }
                            Keys.onEscapePressed: { text = ""; root.replying = "" }
                            Accessible.name: "Reply in thread"
                        }
                        Rectangle {
                            id: sendReply
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 32; height: 32; radius: theme.radius
                            color: srh.hovered ? theme.rowHover : "transparent"
                            FluentIcon {
                                anchors.centerIn: parent
                                name: replyInput.text.trim() ? "send-20-filled" : "send-20"; size: 20
                                color: replyInput.text.trim() ? theme.brand : theme.textStrong
                            }
                            HoverHandler { id: srh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: replyInput.submit() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Send reply"
                        }
                    }
                }
            }
            Accessible.role: Accessible.Grouping
            Accessible.name: card.post ? "Post by " + card.post.sender : "Replies"
        }
        }
    }

    Text {
        visible: root.posts.length === 0 && !root.busy
        anchors.centerIn: list
        text: "No posts yet. Start the conversation."
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }

    // Post in channel
    Rectangle {
        id: postButton
        x: (root.width - list.cardW) / 2
        anchors.bottom: parent.bottom; anchors.bottomMargin: 25
        width: pbRow.implicitWidth + 32; height: 32; radius: theme.radius
        color: pbh.hovered ? theme.brandHover : theme.brandFill
        Row {
            id: pbRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "compose-20"; size: 20; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Post in channel"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.startPost() }
        Accessible.role: Accessible.Button
        Accessible.name: "Post in channel"
    }

    // The in-place editor for a post or reply (Teams' compose).
    Component {
        id: editComponent
        ComposeBox {
            id: box
            property var message: null
            editing: true
            onMessageChanged: if (message) { quote = message.quote || null; setMessage(message); focusEditor() }
            onQuoteDismissed: quote = null
            onEmojiRequested: a => root.host.openEmojiFor(box)
            onSettingsRequested: root.host.openChatSettings()
            onSubmit: { backend.editMessageRich(message.id, formattedText(), quote ? JSON.stringify(quote) : "", JSON.stringify(mediaInUse())); root.host.editingId = "" }
            onCancelled: root.host.editingId = ""
        }
    }

    // A message's text, as the chat draws it (the engine's safe HTML).
    component MessageText: Text {
        property var message
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: !message ? "" : message.deleted ? "This message has been deleted."
            : "<style>a { color: " + theme.brand + "; text-decoration: none; } .mention { color: " + theme.brand
              + "; } .mention-me { color: " + theme.mentionMe + "; font-weight: 700; }</style>" + (message.html || message.text)
        textFormat: message && message.deleted ? Text.PlainText : Text.RichText
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: theme.base
        font.italic: !!message && message.deleted === true
        color: message && message.deleted ? theme.textSecondary : theme.text
        linkColor: theme.brand
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: parent && parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
        Accessible.name: message ? message.text : ""
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
}
