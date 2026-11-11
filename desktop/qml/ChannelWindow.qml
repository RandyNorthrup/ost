import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// A channel in a window of its own: Teams' Open in new window from the
// channel's menu (measured on winpc, 2026-11-09).
// - 588 x 493, titled "<team> | <channel>", Teams' child-window title row.
// - Header (61, #FAFAFA, a #E0E0E0 line under it): the team's picture (32,
//   radius 2) at 20; the channel (18/25.7 bold) at 62; at the right Meet
//   now (its icon alone, 27.3 wide) and its chevron (20), Find in channel
//   and More channel options (32 each).
// - The posts as in the channel, compact (cards 30 in, names over times),
//   "Post in channel" under them.
// It shows that channel whatever the main window shows (the backend keeps
// it loaded and live).
Window {
    id: win
    property string channelId: ""
    property string teamId: ""
    property string teamName: ""
    property string channelName: ""
    property bool pinned: false
    property bool posting: false
    readonly property string key: "win:" + channelId
    readonly property var messages: {
        const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
        return all[key] || []
    }
    readonly property var channelInfo: {
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === win.channelId); if (c) return c }
        return ({ id: win.channelId, name: win.channelName })
    }
    signal meetNow(string channelId, string channelName)
    signal scheduleMeeting()
    signal manageChannel(string channelId)
    title: teamName + " | " + channelName
    width: 588; height: 493
    color: theme.channelPage
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    Component.onCompleted: backend.openChannelWindow(channelId)
    onClosing: backend.closeChannelWindow(channelId)

    // Find in channel: Teams' find pane over the window (as Find in post's).
    // A result opens in the posts with the terms marked; Escape goes back
    // to the results.
    property bool finding: false
    property bool viewingFound: false
    function toggleFind() { if (finding && viewingFound) { viewingFound = false; return } finding = !finding; viewingFound = false; if (!finding) host.findMark = { id: "", terms: [] } }
    Shortcut { sequence: "Escape"; enabled: win.finding && win.viewingFound; onActivated: win.viewingFound = false }
    Shortcut { sequence: "Ctrl+F"; onActivated: win.toggleFind() }

    MessageHost {
        id: host
        messages: win.messages
        isChannel: true
        teamId: win.teamId; teamName: win.teamName; chatName: win.channelName
        defaultBox: compose
        canPopOut: true
        /// The message Find opened, and the terms marked in it.
        property var findMark: ({ id: "", terms: [] })
        onQuoteRequested: m => { compose.quote = { message_id: m.id, sender_mri: m.sender_mri || "", sender_name: m.sender || "", preview: m.quote_text || m.text || "" }; win.posting = true; compose.focusEditor() }
        onReactRequested: (id, key, on) => backend.toggleReaction(id, key, on)
        onDeleteRequested: id => backend.deleteMessage(id)
        onThreadWindowRequested: m => win.openThread(m)
    }
    Component { id: threadWindowComponent; ThreadWindow {} }
    function openThread(m) {
        const w = threadWindowComponent.createObject(null, { channelId: win.channelId, rootId: m.root_id || m.id, teamId: win.teamId, teamName: win.teamName, channelName: win.channelName })
        w.closing.connect(() => w.destroy())
        w.show()
    }

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }

    component Action: Rectangle {
        id: act
        property string icon
        property int iconSize: 20
        property string tip
        property color ink: theme.textStrong
        signal clicked()
        width: 32; height: 32; radius: 4
        color: actHover.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: act.icon; size: act.iconSize; color: act.ink }
        HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: act.clicked() }
        ToolTip.visible: actHover.hovered && act.tip.length > 0; ToolTip.delay: 500; ToolTip.text: act.tip
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
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
            x: 62; y: 16.3
            width: meetButton.x - x - 8; elide: Text.ElideRight
            text: win.channelName
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Action {
            id: meetButton
            x: parent.width - 138.3; y: 14.2; width: 27.3
            icon: "video-20"; tip: "Meet now"
            enabled: backend.callState === ""
            ink: enabled ? theme.textStrong : theme.disabled
            onClicked: win.meetNow(win.channelId, win.channelName)
        }
        Action {
            id: meetMore
            x: parent.width - 111; y: 14.2; width: 20
            icon: "chevron-down-16"; iconSize: 16; tip: "More channel meeting options"
            ink: meetMenu.opened ? theme.brand : theme.textStrong
            onClicked: meetMenu.open()
            MenuPopup {
                id: meetMenu
                x: parent.width - 4.5 - width; y: parent.height + 4.5
                items: [
                    { key: "meet", label: "Meet now", icon: "video-20", enabled: backend.callState === "" },
                    { key: "schedule", label: "Schedule a meeting", icon: "calendar-add-20" }
                ]
                onPicked: i => items[i].key === "meet" ? win.meetNow(win.channelId, win.channelName) : win.scheduleMeeting()
            }
        }
        Action {
            x: parent.width - 75; y: 14.2
            icon: "search-20"; tip: "Find in channel"
            ink: win.finding ? theme.brand : theme.textStrong
            onClicked: win.toggleFind()
        }
        Action {
            id: moreButton
            x: parent.width - 43; y: 14.5; height: 31.3
            icon: "more-horizontal-20"; tip: "More channel options"
            ink: channelMenu.menu.opened ? theme.brand : theme.textStrong
            onClicked: channelMenu.show(moreButton, moreButton.width + 6.3 - channelMenu.menu.implicitWidth, moreButton.height + 4.9)
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    ChannelMenu {
        id: channelMenu
        channel: win.channelInfo
        teamId: win.teamId; teamName: win.teamName
        newestPost: { const posts = win.messages.filter(m => m.kind === "message" && (!m.root_id || m.root_id === m.id)); return posts.length ? posts[posts.length - 1].id : "" }
        postsAtBottom: !backend.channelPostsAtTop
        // Already in a window of its own.
        onOpenInNewWindow: { win.raise(); win.requestActivate() }
        onWorkflows: workflows.start(win.channelId, win.channelName, win.teamId, win.teamName)
        onManageChannel: win.manageChannel(win.channelId)
    }
    WorkflowsDialog { id: workflows }

    FindPane {
        id: findPane
        z: 5
        visible: win.finding && !win.viewingFound
        anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        windowed: true
        isChannel: true
        chatId: win.channelId
        channelGroup: win.teamId
        onVisibleChanged: if (visible) focusField()
        onClosed: { win.finding = false; win.viewingFound = false; host.findMark = { id: "", terms: [] } }
        onJumpTo: (hit, terms) => {
            host.findMark = { id: hit.id, terms: terms }
            win.viewingFound = true
            posts.showPost(hit.parent_id || hit.id)
        }
    }

    ChannelPosts {
        id: posts
        findMark: host.findMark
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: win.posting && !backend.channelPostsAtTop ? compose.top : parent.bottom }
        anchors.bottomMargin: win.posting && !backend.channelPostsAtTop ? 12 : 0
        compact: true
        messages: win.messages
        myName: backend.userName
        busy: win.messages.length === 0
        host: host
        onReply: (rootId, text) => backend.sendThreadReply(win.channelId, rootId, text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>"), "[]", "", false)
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        posting: win.posting
        onStartPost: { win.posting = true; compose.focusSubject() }
        newestAtTop: backend.channelPostsAtTop
        composerHeight: compose.boxHeight + compose.bannerShownH
        onStartAnnouncement: { win.posting = true; compose.announcement = true; compose.focusSubject() }
    }

    // A new post.
    ComposeBox {
        id: compose
        visible: win.posting
        readonly property bool atTop: backend.channelPostsAtTop
        anchors { left: parent.left; right: parent.right }
        y: atTop ? posts.y + posts.composerY : parent.height - height - 8.7
        anchors.leftMargin: 28; anchors.rightMargin: 30
        placeholder: "Type a message"
        post: true
        deliveryOptions: false
        mentionDirectory: false
        channelMention: ({ id: win.channelId, name: win.channelName })
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
        onQuoteDismissed: quote = null
        onEmojiRequested: a => host.openEmojiFor(compose)
        onSubmit: {
            backend.setNextPost(compose.postFields())
            backend.sendChannelPost(win.channelId, compose.formattedText(), JSON.stringify(compose.mediaInUse()), compose.quote ? JSON.stringify(compose.quote) : "")
            compose.quote = null; compose.clear(); compose.resetPost(); win.posting = false
        }
        onCloseRequested: { compose.resetPost(); compose.clear(); win.posting = false }
        onCancelled: { quote = null; compose.resetPost(); win.posting = false }
    }

    // Test hooks.
    function postsForTest() { return posts }
    function composeForTest() { return compose }
    function channelMenuForTest() { return channelMenu }
}
