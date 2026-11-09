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
    /// The post composer is open (Teams then hides Post in channel).
    property bool posting: false
    /// See new posts at top (Teams' enableChannelsV2 "false", measured on
    /// winpc 2026-11-09): newest activity first, under Teams' collapsed
    /// "Post in channel" card (post-compose-collapsed: 108 tall, radius 6,
    /// shadow 4, 15 under the header; posts 32 under it). The composer opens
    /// in the card's place; `composerHeight` is its height, `composerY`
    /// where it goes.
    property bool newestAtTop: false
    property real composerHeight: 0
    /// Your presence (the top card's avatar shows it).
    property string myPresence: ""
    readonly property real composerY: (list.contentY, list.headerItem ? list.headerItem.mapToItem(root, 0, 15).y : 15)
    signal startAnnouncement()
    // The order changed, or the composer opened at the top: show the start.
    onNewestAtTopChanged: Qt.callLater(() => newestAtTop ? list.positionViewAtBeginning() : list.positionViewAtEnd())
    onPostingChanged: if (posting && newestAtTop) Qt.callLater(list.positionViewAtBeginning)
    signal react(string messageId, string key, bool on)
    /// The post whose reply box is open.
    property string replying: ""
    function toEnd() { list.positionViewAtEnd() }
    function headerHeightForTest() { return list.headerItem ? list.headerItem.height : -1 }
    /// For the test harness: reply to the newest post.
    function replyToNewestForTest(text) {
        if (root.posts.length === 0) return false
        root.reply(root.posts[root.posts.length - 1].id, text)
        return true
    }
    /// Posts whose earlier replies are shown.
    property var expanded: ({})
    /// A narrow window (Teams' channel and thread windows, measured on
    /// winpc 2026-11-09): cards 30 in from each side, names over times
    /// (the post's time 20 under its name, a reply's 17.1 under).
    property bool compact: false

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
        out.sort((a, b) => root.newestAtTop ? b.last - a.last : a.last - b.last)
        return out
    }

    Rectangle { anchors.fill: parent; color: theme.channelPage }

    ListView {
        id: list
        // Post in channel is hidden at the top or while composing; then the
        // list goes down to the bottom.
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: root.newestAtTop || root.posting ? parent.bottom : postButton.top; bottomMargin: root.newestAtTop || root.posting ? 0 : 16 }
        clip: true
        spacing: 12
        // Newest activity at the bottom: posts sit at the top while they
        // fit, and the list opens scrolled to the end once they don't. At
        // the top: the list opens at its start.
        model: root.posts
        onCountChanged: Qt.callLater(() => root.newestAtTop ? positionViewAtBeginning() : positionViewAtEnd())
        topMargin: root.newestAtTop ? 0 : 8; bottomMargin: 8
        header: root.newestAtTop ? topCard : null
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real cardW: root.compact ? width - 62 : Math.min(1100, width - 2 * (width > 480 ? 88 : 16))
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
            x: root.compact ? 30 : (list.width - width) / 2
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
                    readonly property var mark: postEdit.active ? null : root.highlight(card.post)
                    // Teams' indicator bar: 4 x 32 at (4, 16), rounded 2.
                    Rectangle {
                        visible: !!parent.mark
                        x: 4; y: 16; width: 4; height: 32; radius: 2
                        color: parent.mark ? parent.mark.color : "transparent"
                    }
                    // Its badge: a 24 px circle centred on the card's right
                    // edge, 20 down, with a white 16 px icon (shadow 2/4).
                    Item {
                        id: nubbin
                        visible: !!parent.mark && parent.mark.icon !== ""
                        x: card.width - 12; y: 20; z: 6
                        width: 24; height: 24
                        FluentSurface { anchors.fill: parent; depth: 4; radius: 12; color: nubbin.parent.mark ? nubbin.parent.mark.color : "transparent" }
                        FluentIcon { x: 4; y: 4.5; size: 16; name: nubbin.parent.mark ? nubbin.parent.mark.icon : ""; color: "white" }
                        HoverHandler {}
                        Accessible.role: Accessible.StaticText
                        Accessible.name: nubbin.parent.mark ? nubbin.parent.mark.tip : ""
                    }
                    Avatar {
                        id: av
                        visible: !!card.post && !postEdit.active
                        x: 18; y: 16; size: 32
                        name: card.post ? card.post.sender : ""
                        photoId: card.post ? card.post.sender_mri : ""
                    }
                    Text {
                        visible: !postEdit.active
                        x: card.post ? 60 : 18; y: !card.post ? 14 : root.compact ? 13.4 : 22
                        text: card.post ? card.post.sender : "Earlier post"
                        font.family: theme.font; font.pixelSize: theme.base
                        lineHeight: root.compact ? 20 : 1; lineHeightMode: root.compact ? Text.FixedHeight : Text.ProportionalHeight
                        color: card.post ? theme.text : theme.textSecondary
                        Row {
                            visible: !!card.post
                            x: root.compact ? 0 : parent.implicitWidth + 10
                            y: root.compact ? 20 : 2
                            spacing: root.compact ? 8 : 10
                            Text {
                                text: card.post ? root.conversationStamp(card.post.time) : ""
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.textSecondary
                            }
                            Text {
                                visible: !!card.post && card.post.edited === true
                                text: "Edited"
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.textSecondary
                            }
                        }
                    }
                    // Teams' post header: an announcement's banner (680 wide at
                    // a 716 card, 244 tall, radius 4, its headline 32/40
                    // semibold centred, 12 under it) and the subject line
                    // (18/25.7 semibold, 16 under it).
                    Column {
                        id: postHead
                        visible: !!card.post && !postEdit.active
                        x: 18; y: 64; width: card.width - 36
                        readonly property var ann: card.post ? card.post.announcement || null : null
                        // A picture banner: the card's width less 32, Teams'
                        // fixed ratio (684 x 190.08 at a 716 card, whatever
                        // the picture's size; it is cropped to fill), 16 above
                        // the text.
                        Item {
                            id: bannerSlot
                            visible: !!postHead.ann
                            readonly property bool pic: !!postHead.ann && !!postHead.ann.image_url
                            readonly property real picW: parent.width + 4
                            readonly property real picH: picW * 190.08 / 684
                            width: parent.width; height: !visible ? 0 : pic ? picH + 16 : 244 + 12
                            Rectangle {
                                id: bannerBox
                                x: bannerSlot.pic ? -2 : 0
                                width: bannerSlot.pic ? bannerSlot.picW : parent.width
                                height: bannerSlot.pic ? bannerSlot.picH : 244
                                radius: bannerSlot.pic ? 0 : 4
                                readonly property var colors: bannerSlot.pic ? ["transparent", "#FFFFFF"] : theme.banner(postHead.ann ? postHead.ann.color_theme : "0")
                                color: colors[0]
                                clip: true
                                Image {
                                    visible: !!postHead.ann && !!postHead.ann.image_local
                                    anchors.fill: parent
                                    source: postHead.ann ? postHead.ann.image_local || "" : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 36 - 20
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: postHead.ann ? postHead.ann.title : ""
                                    font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold
                                    lineHeight: 40; lineHeightMode: Text.FixedHeight
                                    color: bannerBox.colors[1]
                                    Accessible.role: Accessible.Heading
                                }
                            }
                        }
                        Text {
                            visible: !!card.post && !!card.post.subject
                            width: parent.width; wrapMode: Text.Wrap
                            bottomPadding: 16
                            text: card.post ? card.post.subject || "" : ""
                            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                            color: theme.text
                            Accessible.role: Accessible.Heading
                        }
                    }
                    MessageText {
                        id: postBody
                        visible: !!card.post && !postEdit.active
                        x: 18; y: 64 + postHead.height; width: card.width - 36
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
                                    : (root.compact ? 34.2 : 20) + repBody.height + ((modelData.reactions || []).length > 0 ? 8 + 26 : 0) + 16
                                z: repHover.hovered || repBar.hovered ? 2 : 1
                                // A reply's indicator bar: 4 x 20 beside its avatar.
                                Rectangle {
                                    readonly property var mark: rep.editing ? null : root.highlight(rep.modelData)
                                    visible: !!mark
                                    x: 4; y: 0; width: 4; height: 20; radius: 2
                                    color: mark ? mark.color : "transparent"
                                }
                                Avatar {
                                    visible: !rep.editing
                                    x: 18; y: 0; size: 20
                                    name: rep.modelData.sender; photoId: rep.modelData.sender_mri
                                }
                                Text {
                                    visible: !rep.editing
                                    x: 50; y: root.compact ? 0 : 1.4
                                    text: rep.modelData.sender; font.family: theme.font; font.pixelSize: theme.small; color: theme.text
                                    Row {
                                        x: root.compact ? 0 : parent.implicitWidth + 8; y: root.compact ? 17.1 : 0
                                        spacing: 8
                                        Text { text: root.conversationStamp(rep.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                        Text { visible: rep.modelData.edited === true; text: "Edited"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                    }
                                }
                                MessageText {
                                    id: repBody
                                    visible: !rep.editing
                                    x: 50; y: root.compact ? 34.2 : 20; width: card.width - 70
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

    // New posts at the top: Teams' collapsed post composer.
    Component {
        id: topCard
        Item {
            width: list.width
            height: 15 + (root.posting ? root.composerHeight : 108) + 32
            FluentSurface {
                visible: !root.posting
                x: root.compact ? 30 : (list.width - list.cardW) / 2; y: 15
                width: list.cardW; height: 108
                depth: 4; radius: 6; color: theme.surface
                Avatar { x: 16; y: 12; size: 32; name: root.myName; photoId: backend.userMri || ""; presence: root.myPresence }
                Rectangle {
                    x: 46; y: 12; width: parent.width - 74; height: 31.3; radius: 4
                    color: startHover.hovered ? theme.rowHover : "transparent"
                    Text {
                        x: 12.7; anchors.verticalCenter: parent.verticalCenter
                        text: "Post in channel"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.textStrong
                    }
                    HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startPost() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Post in channel"
                }
                // The post types: Post (chosen) and Announcement.
                Rectangle {
                    x: 12; y: 68; width: 96; height: 30; radius: 4
                    color: postTypeHover.hovered ? theme.rowHover : theme.pick("#EBEBEB", "#3D3D3D")
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: postTypeHover.hovered ? "channel-20-filled" : "channel-20"; color: theme.brandForeground1 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Post"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandForeground1 }
                    }
                    HoverHandler { id: postTypeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startPost() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Post"
                }
                Rectangle {
                    x: 123.5; y: 68; width: 147.5; height: 30; radius: 4
                    color: annTypeHover.hovered ? theme.rowHover : theme.surface
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: annTypeHover.hovered ? "fmt-announcement-filled" : "fmt-announcement"; color: annTypeHover.hovered ? theme.brand : theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Announcement"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    }
                    HoverHandler { id: annTypeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startAnnouncement() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Announcement"
                }
            }
        }
    }

    // Post in channel
    Rectangle {
        id: postButton
        visible: !root.posting && !root.newestAtTop
        x: root.compact ? 30 : (root.width - list.cardW) / 2
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
    function highlight(m) { return root.host ? root.host.highlight(m) : null }
    function conversationStamp(t) { return root.host ? root.host.conversationStamp(t) : "" }
}
