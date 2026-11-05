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
    signal reply(string rootId, string text)
    signal startPost()
    signal react(string messageId, string key, bool on)
    /// The post whose reply box is open.
    property string replying: ""
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
                    height: card.post ? postBody.y + postBody.height + 56 : 44
                    Avatar {
                        id: av
                        visible: !!card.post
                        x: 18; y: 16; size: 32
                        name: card.post ? card.post.sender : ""
                        photoId: card.post ? card.post.sender_mri : ""
                    }
                    Row {
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
                        visible: !!card.post
                        x: 18; y: 64; width: card.width - 36
                        message: card.post
                    }
                    // Reactions, then add reaction.
                    Row {
                        visible: !!card.post
                        x: 18; y: postBody.y + postBody.height + 16
                        spacing: 4
                        Repeater {
                            model: card.post ? card.post.reactions : []
                            Rectangle {
                                required property var modelData
                                width: rp.implicitWidth + 16; height: 26; radius: 13
                                color: modelData.mine ? theme.brandTint : theme.surface
                                border.color: modelData.mine ? theme.brand : theme.stroke
                                Row {
                                    id: rp
                                    anchors.centerIn: parent; spacing: 4
                                    Text { text: parent.parent.modelData.emoji; font.pixelSize: 14 }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.modelData.count
                                        font.family: theme.font; font.pixelSize: theme.small
                                        color: theme.text
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.react(card.post.id, modelData.key, !modelData.mine) }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.count + " " + modelData.key + " reaction" + (modelData.mine ? ", including yours" : "")
                            }
                        }
                        Rectangle {
                            width: 34; height: 26; radius: 13
                            color: arh.hovered ? theme.rowHover : theme.surface
                            border.color: theme.divider
                            FluentIcon { anchors.centerIn: parent; name: "emoji-add-20"; size: 16; color: theme.textStrong }
                            HoverHandler { id: arh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: reactMenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Add reaction"
                            Popup {
                                id: reactMenu
                                y: -height - 4
                                padding: 4
                                background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
                                contentItem: Row {
                                    Repeater {
                                        model: [["like", "👍"], ["heart", "❤️"], ["laugh", "😆"], ["surprised", "😮"], ["sad", "😢"], ["angry", "😡"]]
                                        Rectangle {
                                            required property var modelData
                                            width: 32; height: 32; radius: theme.radius
                                            color: qh.hovered ? theme.rowHover : "transparent"
                                            Text { anchors.centerIn: parent; text: parent.modelData[1]; font.pixelSize: 18 }
                                            HoverHandler { id: qh; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    const mine = (card.post.reactions || []).some(r => r.key === parent.modelData[0] && r.mine)
                                                    root.react(card.post.id, parent.modelData[0], !mine)
                                                    reactMenu.close()
                                                }
                                            }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: "React with " + modelData[0]
                                        }
                                    }
                                }
                            }
                        }
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
                // Replies
                Repeater {
                    model: card.shown
                    Item {
                        id: rep
                        required property var modelData
                        required property int index
                        width: card.width
                        height: repBody.y + repBody.height + 5
                        // One divider above the replies, none between them.
                        Rectangle {
                            visible: rep.index === 0 && card.replies.length === card.shown.length
                            width: parent.width; height: 1; color: theme.dividerSoft
                        }
                        Avatar {
                            x: 18; y: 12; size: 20
                            name: rep.modelData.sender; photoId: rep.modelData.sender_mri
                        }
                        Row {
                            x: 50; y: 11
                            spacing: 8
                            Text { text: rep.modelData.sender; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                            Text { text: root.conversationStamp(rep.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        MessageText {
                            id: repBody
                            x: 50; y: 31; width: card.width - 68
                            message: rep.modelData
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

    // A message's text, as the chat draws it (the engine's safe HTML).
    component MessageText: Text {
        property var message
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: !message ? "" : message.deleted ? "This message has been deleted."
            : "<style>a { color: " + theme.brand + "; text-decoration: none; }</style>" + (message.html || message.text)
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
