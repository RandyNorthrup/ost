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
    /// A bot's Action.Compose for a post: its reply opens with the mention.
    property var pendingSuggestion: null
    function applySuggestion(postId, action) { replying = postId; pendingSuggestion = { id: postId, action: action } }
    /// The harness: the open reply box's plain text and whether it holds a mention.
    property string replyStateForTest: ""
    signal clearReplies()
    /// A picture clicked: Teams' viewer on the message's pictures.
    signal openImage(var images, int index, var message)
    /// The harness: types the text into the open reply box and sends it.
    signal askForTest(string text)
    onClearReplies: { replying = ""; replyStateForTest = "" }
    function toEnd() { list.positionViewAtEnd() }
    /// Bring a post into view (Find in channel); whether it's loaded.
    function showPost(id) {
        const i = (root.posts || []).findIndex(p => p.id === id)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
        return i >= 0
    }
    /// The terms Find marks in a message.
    property var findMark: ({ id: "", terms: [] })
    function markFor(id) { return id && findMark && findMark.id === id ? findMark.terms : [] }
    function headerHeightForTest() { return list.headerItem ? list.headerItem.height : -1 }
    /// For the test harness: reply to the newest post.
    function replyToNewestForTest(text) {
        if (root.posts.length === 0) return false
        root.reply(root.posts[root.posts.length - 1].id, text)
        return true
    }
    // A second's tick for live meetings' times.
    property int clock: 0
    Timer { running: root.visible && root.posts.some(p => p.post && p.post.kind === "call"); interval: 1000; repeat: true; onTriggered: root.clock++ }
    /// Time since a meeting started, as Teams shows it: mm:ss, h:mm:ss.
    function elapsedText(iso) {
        if (!iso) return ""
        const s = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000))
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
        const two = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + two(m) : two(m)) + ":" + two(sec)
    }
    /// Posts whose earlier replies are shown.
    property var expanded: ({})
    /// Long posts and replies opened with "see more" (by message id).
    property var seeMoreOpen: ({})
    readonly property SeeMoreRules seeMore: SeeMoreRules {}
    /// "see more" / "see less": Teams keeps the link where it is on the
    /// screen (its scroll compensation), so the list moves by the change.
    function toggleSeeMore(id, link) {
        const before = link.mapToItem(list.contentItem, 0, 0).y
        const o = Object.assign({}, root.seeMoreOpen)
        if (o[id]) delete o[id]; else o[id] = true
        root.seeMoreOpen = o
        list.forceLayout()
        const after = link.mapToItem(list.contentItem, 0, 0).y
        list.contentY = list.contentY + after - before
        list.returnToBounds()
    }
    /// The text heights seen (the harness's report; not bound to).
    property var seeMoreFull: ({})
    /// The harness: what the posts list cuts ({id, reply, limit, full, cut,
    /// open} for each post and reply shown).
    function seeMoreStateForTest() {
        const out = []
        const item = (m, reply) => {
            const limit = seeMore.postLimit(m, reply), full = root.seeMoreFull[m.id] || 0
            out.push({ id: m.id, reply: reply, text: String(m.text || "").slice(0, 40), limit: limit, full: full, cut: limit > 0 && full > limit, open: root.seeMoreOpen[m.id] === true })
        }
        for (const g of root.posts) {
            if (g.post) item(g.post, false)
            for (const r of g.replies) item(r, true)
        }
        return out
    }
    /// The harness: each post with pictures, its cut and picture places.
    function imagesForTest() {
        const out = []
        for (let i = 0; i < list.count; i++) {
            const it = list.itemAtIndex(i)
            if (!it) continue
            const find = (o, depth) => {
                if (!o || depth > 12) return
                if (o.picRanges !== undefined && o.message && (o.message.images || []).length) out.push({ id: o.message.id, ranges: o.picRanges, height: o.height, sizes: (o.message.images || []).map(x => [x.width, x.height]) })
                for (const c of o.children || []) find(c, depth + 1)
            }
            find(it, 0)
        }
        return out
    }
    function seeMoreShowByIdForTest(id) {
        const i = root.posts.findIndex(g => g.id === id || g.replies.some(r => r.id === id))
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
        return i >= 0
    }
    function seeMoreToggleByIdForTest(id) {
        if (!seeMoreShowByIdForTest(id)) return false
        const o = Object.assign({}, root.seeMoreOpen)
        if (o[id]) delete o[id]; else o[id] = true
        root.seeMoreOpen = o
        Qt.callLater(() => seeMoreShowByIdForTest(id))
        return true
    }
    /// A narrow window (Teams' channel and thread windows, measured on
    /// winpc 2026-11-09): cards 30 in from each side, names over times
    /// (the post's time 20 under its name, a reply's 17.1 under).
    property bool compact: false

    /// The channel's name (a Meet now's post reads `Meeting in "<name>"`).
    property string channelName: ""
    /// Who is in the live channel meeting (watched by the Conversation).
    property var liveRoster: []
    /// The channel's members ({mri, name}): call events carry no name, so
    /// a meeting's post shows its author's member name, as Teams does.
    property var members: []
    // Test hook: "See details" on the newest ended meeting's post.
    function seeDetailsForTest() {
        const p = root.posts.filter(g => g.post && g.post.kind === "call" && g.events.length && ![g.post].concat(g.events).some(e => e.call_state === "started" && e.call_active)).pop()
        if (!p) return ""
        root.seeDetails(p.id)
        return p.id
    }
    // Test hook: Join the newest live meeting's post.
    function joinLiveForTest() {
        const p = root.posts.filter(g => g.post && g.post.kind === "call" && [g.post].concat(g.events).some(e => e.call_state === "started" && e.call_active)).pop()
        if (!p) return false
        root.joinMeeting(p.post.meeting_join_url, p.post.meeting_title || qsTr("Meeting in \"%1\"").arg(root.channelName))
        return true
    }
    readonly property var peopleNames: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    function senderOf(m) {
        if (!m) return ""
        if (m.sender) return m.sender
        const p = root.members.find(x => (x.mri || "").toLowerCase() === String(m.sender_mri || "").toLowerCase())
        return p ? p.name : (root.peopleNames[m.sender_mri] || "")
    }
    // Meeting posts name their author only by MRI: resolve those names.
    onPostsChanged: {
        const want = root.posts.filter(g => g.post && g.post.kind === "call" && !g.post.sender && g.post.sender_mri && !root.peopleNames[g.post.sender_mri]).map(g => g.post.sender_mri)
        if (want.length) backend.resolveNames(JSON.stringify(Array.from(new Set(want))))
    }
    /// Join a channel meeting (Teams opens its pre-join screen).
    signal joinMeeting(string url, string title)
    /// "See details" under an ended meeting's post: its thread.
    signal seeDetails(string rootId)
    // Teams' channel meetings (measured on winpc 2026-11-10): the meeting's
    // callStarted event is the post; a rejoin's start, posted as a root
    // linked to it (linked_root), and the thread's call events fold into
    // it instead of showing as replies.
    readonly property var posts: {
        const byRoot = {}, order = []
        for (const m of root.messages) {
            // A layout change and a Channel Agent's add aren't posts: Teams
            // shows no row for either in a posts channel (seen on winpc
            // 2026-11-22, "OST TEST 206 agent H").
            if (m.event && (m.event.kind === "ModalityUpdate" || m.event.kind === "AgentAdded")) continue
            const r = m.kind === "call" && m.linked_root ? m.linked_root : (m.root_id || m.id)
            const meetingPost = m.kind === "call" && m.id === r && !!m.meeting_join_url
            if (m.kind === "call" && !meetingPost && !byRoot[r]) continue
            if (!byRoot[r]) { byRoot[r] = { id: r, post: null, replies: [], events: [], last: 0 }; order.push(r) }
            const g = byRoot[r]
            if (m.kind === "call") { if (meetingPost) g.post = m; else g.events.push(m) }
            else if (m.id === r) g.post = m; else g.replies.push(m)
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
            // A channel meeting's post: live while a start (its own or a
            // rejoin's) has no end; then its subject says "ended".
            readonly property bool meeting: !!post && post.kind === "call"
            readonly property var liveStart: !meeting ? null : [post].concat(modelData.events).filter(e => e.call_state === "started" && e.call_active).pop() || null
            readonly property bool live: !!liveStart
            readonly property string meetingTitle: !meeting ? "" : (post.meeting_title || qsTr("Meeting in \"%1\"").arg(root.channelName))
            readonly property string subjectText: meeting ? meetingTitle + (live ? "" : " ended") : (post && post.subject ? post.subject : "")
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
                    height: !card.post ? 44 : postEdit.active ? (postEdit.item ? postEdit.item.height : 0) + 8 : postBody.y + postBody.height + postActions.extra + 51
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
                        name: card.post ? root.senderOf(card.post) : ""
                        photoId: card.post ? card.post.sender_mri + (card.post.sender_app ? "#" + card.post.sender_app : "") : ""
                        opensProfile: true
                    }
                    Text {
                        visible: !postEdit.active
                        x: card.post ? 60 : 18; y: !card.post ? 14 : root.compact ? 13.4 : 22
                        text: card.post ? root.senderOf(card.post) : qsTr("Earlier post")
                        font.family: theme.font; font.pixelSize: theme.base
                        lineHeight: root.compact ? 20 : 1; lineHeightMode: root.compact ? Text.FixedHeight : Text.ProportionalHeight
                        color: card.post ? theme.text : theme.textSecondary
                        HoverHandler { enabled: !!card.post && (card.post.sender_mri || "").indexOf("8:orgid:") === 0; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !!card.post && (card.post.sender_mri || "").indexOf("8:orgid:") === 0; onTapped: backend.requestProfile(card.post.sender_mri) }
                        Row {
                            visible: !!card.post
                            x: root.compact ? 0 : parent.implicitWidth + 10
                            y: root.compact ? 20 : 2
                            spacing: root.compact ? 8 : 10
                            // Teams' "AI agent" tag (an AI bot's post).
                            Rectangle {
                                visible: !!card.post && !!card.post.ai_agent
                                width: postAgentTag.implicitWidth + 5.34; height: 17.3; radius: 4; y: -0.65
                                color: "transparent"
                                border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                                Text { id: postAgentTag; anchors.centerIn: parent; text: qsTr("AI agent", "messaging:k6gdrts20"); font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                                HoverHandler { id: postAgentHover }
                                ToolTip.visible: postAgentHover.hovered; ToolTip.delay: 500
                                ToolTip.text: qsTr("AI-generated content may be incorrect", "messaging:kd2tqw453")
                            }
                            Text {
                                text: card.post ? root.conversationStamp(card.post.time) : ""
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.textSecondary
                            }
                            Text {
                                visible: !!card.post && card.post.edited === true
                                text: qsTr("Edited")
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
                                    color: theme.onFill(bannerBox, bannerBox.colors[1])
                                    Accessible.role: Accessible.Heading
                                }
                            }
                        }
                        Text {
                            visible: !!card.post && !!card.subjectText
                            width: parent.width; wrapMode: Text.Wrap
                            bottomPadding: 16
                            textFormat: Text.RichText
                            text: card.subjectText ? theme.markTerms(card.subjectText.replace(/&/g, "&amp;").replace(/</g, "&lt;"), root.markFor(card.post.id)) : ""
                            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                            color: theme.text
                            Accessible.role: Accessible.Heading
                        }
                    }
                    // The text, cut with "see more" when it's long (Teams:
                    // 200 px for a post; SeeMoreRules). The cut text expands
                    // on a click too.
                    Item {
                        id: postBody
                        // The text, its pictures and an agent's command cards.
                        readonly property real contentH: postText.height + (postCards.shown ? postCards.height : 0)
                        readonly property real limit: card.post && !card.meeting ? seeMore.cutAt(card.post, false, postText.picRanges) : 0
                        readonly property bool cut: limit > 0 && contentH > limit
                        readonly property bool open: !!card.post && root.seeMoreOpen[card.post.id] === true
                        readonly property real full: contentH
                        onFullChanged: if (card.post) root.seeMoreFull[card.post.id] = full
                        visible: postText.visible
                        x: 18; y: 64 + postHead.height; width: card.width - 36
                        height: card.meeting ? 0 : !cut ? contentH : (open ? contentH : limit) + 20
                        Item {
                            width: parent.width
                            height: postBody.cut && !postBody.open ? postBody.limit : postBody.contentH
                            clip: postBody.cut && !postBody.open
                            PostBody {
                                id: postText
                                visible: !!card.post && !postEdit.active && !card.meeting
                                width: parent.width
                                message: card.post
                                mark: root.markFor(card.post ? card.post.id : "")
                                onOpenImage: (list, i) => root.openImage(list, i, card.post)
                            }
                            OdslCards {
                                id: postCards
                                visible: shown && !!card.post && !card.post.mine && !card.post.deleted
                                y: postText.height
                                width: parent.width
                                message: card.post || ({})
                                host: root.host
                            }
                            TapHandler { enabled: postBody.cut && !postBody.open; onTapped: root.toggleSeeMore(card.post.id, postLink) }
                        }
                        SeeMoreLink {
                            id: postLink
                            visible: postBody.cut
                            y: parent.height - 20
                            expanded: postBody.open
                            onToggled: root.toggleSeeMore(card.post.id, postLink)
                        }
                    }
                    // A bot's suggested actions ("@agent") and its like /
                    // dislike (SuggestedActionsRow): measured on winpc
                    // 2026-11-22 in a posts channel, 16 in and 8 under the
                    // text, the reactions 16 under the 31.3 row.
                    // An agent's ODSL statements (its reasoning), 8 under the
                    // actions (OdslBlock).
                    OdslBlock {
                        id: postOdsl
                        readonly property real extra: visible ? height + 8 : 0
                        visible: !!card.post && !postEdit.active && !card.post.mine && !card.post.deleted && shown
                        x: 18; y: postBody.y + postBody.height + (postActions.visible ? Math.max(31.3, postActions.height) + 8 : 0) + 8
                        width: card.width - 36
                        message: card.post || ({})
                        rules: root.seeMore
                    }
                    SuggestedActionsRow {
                        id: postActions
                        readonly property real extra: (visible ? Math.max(31.3, height) + 8 : 0) + postOdsl.extra
                        visible: !!card.post && !postEdit.active && !card.post.mine && !card.post.deleted && shown
                        x: 16; y: postBody.y + postBody.height + 8
                        message: card.post || ({})
                        host: root.host
                        maxWidth: card.width - 36
                    }
                    // Teams' reaction summary, 17 under the body; posts show the
                    // add button even with no reactions.
                    ReactionSummary {
                        visible: !!card.post && !postEdit.active
                        x: 18; y: postBody.y + postBody.height + postActions.extra + 17
                        host: root.host
                        messageId: card.post ? card.post.id : ""
                        reactions: card.post ? (card.post.reactions || []) : []
                    }
                    // Edit in place.
                    Loader {
                        id: postEdit
                        active: !!card.post && !!root.host && root.host.editingId === card.post.id
                        x: 0; y: 0; width: card.width
                        // (A post: Teams' post composer.)
                        sourceComponent: card.post && card.post.kind !== "call" ? postEditComponent : editComponent
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
                            ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }]
                            : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }]
                        x: card.width - 10 - width; y: 11; z: 5
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !!card.post && !!root.host
                        onTapped: point => root.host.openMessageMenu(card.post, card, true, point.position.x, point.position.y, "post")
                    }
                }
                // A live channel meeting's banner (channel-ongoing-meeting-
                // banner): the card's width, 70 tall, #333357, radius 4, 2
                // under the reactions; a 32 px #5B5FC7 tile with the video
                // glyph 20 in, the title (14/600) 10 after it, then from the
                // right: Join (96 x 32), the people in it (28 px, 18 apart)
                // 15 before it, the time since it started 15 before them.
                Item {
                    visible: card.live
                    width: card.width; height: visible ? 68 : 0
                    Rectangle {
                        y: -6; width: parent.width; height: 70; radius: 4
                        color: theme.hc("#333357", "#000000")
                        Rectangle {
                            id: hcFill1
                            x: 20; y: 19; width: 32; height: 32; radius: 4
                            color: theme.hc("#5B5FC7", "#FFFFFF")
                            FluentIcon { anchors.centerIn: parent; name: "video-20-filled"; size: 20; color: theme.onFill(hcFill1, "white") }
                        }
                        Text {
                            x: 62; anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, elapsed.x - 15 - x); elide: Text.ElideRight
                            text: card.meetingTitle
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: "white"
                        }
                        Text {
                            id: elapsed
                            x: people.x - 15 - width; anchors.verticalCenter: parent.verticalCenter
                            text: { root.clock; return card.liveStart ? root.elapsedText(card.liveStart.call_started_at) : "" }
                            font.family: theme.font; font.pixelSize: 14
                            color: "white"
                            Accessible.role: Accessible.StaticText
                            Accessible.name: qsTr("Meeting duration %1").arg(text)
                        }
                        Row {
                            id: people
                            readonly property var shownPeople: root.liveRoster.slice(0, 5)
                            x: joinButton.x - 15 - width; anchors.verticalCenter: parent.verticalCenter
                            width: shownPeople.length ? (shownPeople.length - 1) * 18 + 28 : 0
                            spacing: -10
                            Repeater {
                                model: people.shownPeople
                                Avatar { required property var modelData; size: 28; name: modelData.name || "?"; photoId: modelData.id }
                            }
                        }
                        Rectangle {
                            id: joinButton
                            readonly property bool can: backend.callState === ""
                            x: parent.width - 20 - width; anchors.verticalCenter: parent.verticalCenter
                            width: 96; height: 32; radius: 4
                            color: !can ? theme.bgDisabled : jh.hovered ? theme.brandHover : theme.hc("#5B5FC7", "#FFFFFF")
                            Text { anchors.centerIn: parent; text: qsTr("Join"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(joinButton, joinButton.can ? "white" : theme.disabled) }
                            HoverHandler { id: jh; enabled: joinButton.can; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: joinButton.can; onTapped: root.joinMeeting(card.post.meeting_join_url, card.meetingTitle) }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Join %1").arg(card.meetingTitle)
                        }
                    }
                }
                // An ended meeting's "See details" (response-summary-button,
                // 12 px brand, 18 in and 12 down in a 40.7 row): its thread.
                Item {
                    visible: card.meeting && !card.live && card.modelData.events.length > 0 && card.replies.length === 0
                    width: card.width; height: visible ? 40.7 : 0
                    Rectangle { width: parent.width; height: 0.67; color: theme.quoteBorder }
                    Text {
                        x: 21.7; y: 12.7
                        text: qsTr("See details")
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.brand
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.seeDetails(card.modelData.id) }
                        Accessible.role: Accessible.Button
                        Accessible.name: text
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
                                    name: rep.modelData.sender; photoId: rep.modelData.sender_mri + (rep.modelData.sender_app ? "#" + rep.modelData.sender_app : "")
                                    opensProfile: true
                                }
                                Text {
                                    visible: !rep.editing
                                    x: 50; y: root.compact ? 0 : 1.4
                                    text: rep.modelData.sender; font.family: theme.font; font.pixelSize: theme.small; color: theme.text
                                    HoverHandler { enabled: (rep.modelData.sender_mri || "").indexOf("8:orgid:") === 0; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { enabled: (rep.modelData.sender_mri || "").indexOf("8:orgid:") === 0; onTapped: backend.requestProfile(rep.modelData.sender_mri) }
                                    Row {
                                        x: root.compact ? 0 : parent.implicitWidth + 8; y: root.compact ? 17.1 : 0
                                        spacing: 8
                                        Text { text: root.conversationStamp(rep.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                        Text { visible: rep.modelData.edited === true; text: qsTr("Edited"); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                                    }
                                }
                                // Cut at 80 (a Channel Agent's at 140), as
                                // Teams' posts list (SeeMoreRules).
                                Item {
                                    id: repBody
                                    readonly property real contentH: repText.height + (repCards.shown ? repCards.height : 0)
                                    readonly property real limit: seeMore.cutAt(rep.modelData, true, repText.picRanges)
                                    readonly property bool cut: limit > 0 && contentH > limit
                                    readonly property bool open: root.seeMoreOpen[rep.modelData.id] === true
                                    readonly property real full: contentH
                                    onFullChanged: root.seeMoreFull[rep.modelData.id] = full
                                    visible: !rep.editing
                                    x: 50; y: root.compact ? 34.2 : 20; width: card.width - 70
                                    height: !cut ? contentH : (open ? contentH : limit) + 20
                                    Item {
                                        width: parent.width
                                        height: repBody.cut && !repBody.open ? repBody.limit : repBody.contentH
                                        clip: repBody.cut && !repBody.open
                                        PostBody {
                                            id: repText
                                            width: parent.width
                                            message: rep.modelData
                                            mark: root.markFor(rep.modelData ? rep.modelData.id : "")
                                            onOpenImage: (list, i) => root.openImage(list, i, rep.modelData)
                                        }
                                        OdslCards {
                                            id: repCards
                                            visible: shown && !rep.modelData.mine && !rep.modelData.deleted
                                            y: repText.height
                                            width: parent.width
                                            message: rep.modelData
                                            host: root.host
                                        }
                                        TapHandler { enabled: repBody.cut && !repBody.open; onTapped: root.toggleSeeMore(rep.modelData.id, repLink) }
                                    }
                                    SeeMoreLink {
                                        id: repLink
                                        visible: repBody.cut
                                        y: parent.height - 20
                                        expanded: repBody.open
                                        onToggled: root.toggleSeeMore(rep.modelData.id, repLink)
                                    }
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
                                        ? [{ key: "edit", icon: "edit-20", tip: qsTr("Edit") }]
                                        : [{ key: "reply", icon: "quote-reply-20", tip: qsTr("Reply with quote") }]
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
                        size: 20; name: root.myName || qsTr("You"); photoId: "me"
                    }
                    Text {
                        visible: !card.open
                        x: 50; anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Reply in thread")
                        font.family: theme.font; font.pixelSize: theme.base
                        color: theme.textSecondary
                    }
                    MouseArea {
                        visible: !card.open
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.replying = card.modelData.id; replyBox.input.forceActiveFocus() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Reply in thread")
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
                        // A bot's suggested action for this post (Teams opens
                        // the post's reply with its mention: 763654 `eo`,
                        // showReplyCompose then setCopilotAtMention).
                        Connections {
                            target: root
                            function onClearReplies() { replyInput.clearBox() }
                            function onAskForTest(text) {
                                if (!card.open) return
                                replyInput.insert(replyInput.length, root.escapeForTest(text))
                                replyInput.submit()
                            }
                            function onPendingSuggestionChanged() {
                                const p = root.pendingSuggestion
                                if (!p || p.id !== card.modelData.id) return
                                root.pendingSuggestion = null
                                const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
                                const esc = s => String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                replyInput.textFormat = TextEdit.RichText
                                replyInput.rich = true
                                replyInput.insert(replyInput.cursorPosition, (p.action.mentions || []).map(m => '<a href="' + (m.appId ? "mention-bot:" + m.mri + "|" + m.appId : "mention:" + m.mri) + '" ' + style + '>' + esc(m.name) + '</a>&nbsp;').join("") + (p.action.text ? esc(p.action.text) : ""))
                                replyInput.cursorPosition = replyInput.length
                                replyInput.forceActiveFocus()
                            }
                        }
                        TextArea {
                            id: replyInput
                            /// Holds a mention (rich text, sent as the editor's HTML).
                            property bool rich: false
                            onTextChanged: if (card.open) root.replyStateForTest = JSON.stringify({ post: card.modelData.id, text: getText(0, length), mention: rich && text.indexOf('href="mention') >= 0 })
                            anchors { left: parent.left; right: sendReply.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
                            placeholderText: qsTr("Reply in thread")
                            placeholderTextColor: theme.textSecondary
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.text
                            wrapMode: TextArea.Wrap
                            background: Item {}
                            function submit() {
                                if (!getText(0, length).trim()) return
                                if (rich) backend.sendThreadReply(backend.currentChatId, card.modelData.id, text, "[]", "", false)
                                else root.reply(card.modelData.id, text.trim())
                                clearBox()
                                root.replying = ""
                            }
                            function clearBox() { text = ""; rich = false; textFormat = TextEdit.PlainText }
                            Keys.onReturnPressed: e => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else submit() }
                            Keys.onEscapePressed: { clearBox(); root.replying = "" }
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
            Accessible.role: Accessible.Grouping
            Accessible.name: card.post ? qsTr("Post by %1").arg(card.post.sender) : qsTr("Replies")
        }
        }
    }

    Text {
        visible: root.posts.length === 0 && !root.busy
        anchors.centerIn: list
        text: qsTr("No posts yet. Start the conversation.")
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
                    id: hcFill2
                    x: 46; y: 12; width: parent.width - 74; height: 31.3; radius: 4
                    color: startHover.hovered ? theme.rowHover : "transparent"
                    Text {
                        x: 12.7; anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Post in channel")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.onFill(hcFill2, theme.textStrong)
                    }
                    HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startPost() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Post in channel")
                }
                // The post types: Post (chosen) and Announcement.
                Rectangle {
                    id: hcFill3
                    x: 12; y: 68; width: 96; height: 30; radius: 4
                    color: postTypeHover.hovered ? theme.rowHover : theme.pick("#EBEBEB", "#3D3D3D", "#000000")
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: postTypeHover.hovered ? "channel-20-filled" : "channel-20"; color: theme.onFill(hcFill3, theme.brandForeground1) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Post"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, theme.brandForeground1) }
                    }
                    HoverHandler { id: postTypeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startPost() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Post")
                }
                Rectangle {
                    id: hcFill4
                    x: 123.5; y: 68; width: 147.5; height: 30; radius: 4
                    color: annTypeHover.hovered ? theme.rowHover : theme.surface
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: annTypeHover.hovered ? "fmt-announcement-filled" : "fmt-announcement"; color: theme.onFill(hcFill4, annTypeHover.hovered ? theme.brand : theme.text) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Announcement"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
                    }
                    HoverHandler { id: annTypeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.startAnnouncement() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Announcement")
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
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "compose-20"; size: 20; color: theme.onFill(postButton, "white") }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Post in channel"); color: theme.onFill(postButton, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.startPost() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Post in channel")
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
            // (Teams' edit box: Attach files and Actions and apps too,
            // TASK-0263.)
            chatTitle: root.host ? root.host.chatName : ""
            editTeamId: root.host ? root.host.teamId : ""
            editTeamName: root.host ? root.host.teamName : ""
            onSubmit: {
                backend.editMessageWith(message.id, formattedText(), quote ? JSON.stringify(quote) : "", JSON.stringify(mediaInUse()), editExtras())
                editSent()
                root.host.editingId = ""
            }
            onCancelled: root.host.editingId = ""
        }
    }
    // A post's edit: Teams' post composer in the card's place (measured on
    // winpc 2026-11-24, TASK-0265): its subject, Change permissions and
    // Post in other channels; Post saves it.
    Component {
        id: postEditComponent
        ComposeBox {
            id: pbox
            property var message: null
            editing: true
            post: true
            onMessageChanged: if (message) { setMessage(message); focusEditor() }
            onEmojiRequested: a => root.host.openEmojiFor(pbox)
            onSettingsRequested: root.host.openChatSettings()
            canRecordClip: root.host ? root.host.canRecordClip : false
            onRecordClipRequested: if (root.host) root.host.recordClipFor(pbox)
            chatTitle: root.host ? root.host.chatName : ""
            editTeamId: root.host ? root.host.teamId : ""
            editTeamName: root.host ? root.host.teamName : ""
            onSubmit: {
                backend.editMessageWith(message.id, formattedText(), "", JSON.stringify(mediaInUse()), editExtras())
                editSent()
                root.host.editingId = ""
            }
            onCancelled: root.host.editingId = ""
        }
    }
    function escapeForTest(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;") }
    function highlight(m) { return root.host ? root.host.highlight(m) : null }
    function conversationStamp(t) { return root.host ? root.host.conversationStamp(t) : "" }
}
