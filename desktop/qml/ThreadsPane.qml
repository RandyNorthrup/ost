import QtQuick
import QtQuick.Controls.Basic

// A Threads-layout channel's threads pane beside it (Teams', measured on
// winpc 2026-11-10): 360 wide, a 0.67 px line on its left, 61 tall headers.
// - The list (Open threads): "Threads" (14/600, 25 in) and Close (57.7 from
//   the right); a row per thread with replies, newest reply first, 82.5
//   tall and 2 in: the first message's author (32, 24 in, 10 down), its
//   text (14 NeutralForeground2, 70 in, 8 down) with the newest reply's
//   time (12, 14 from the right), "{who}: {newest reply}" (14 #616161, 26
//   down), then the repliers (20 in a 24 slot, 50.5 down) and "{N}
//   replies" (12), with the followed mark (14, brand) at the end.
// - A thread: "Threads" (Go to thread list, 20 in) › the first message
//   (14/600, 100 in), then Follow / Unfollow thread, More (Mark as unread,
//   Copy link, Jump to original message, Open thread in new window) and
//   Close, 32 apart and 16.7 from the right; the thread as a chat (its
//   first message, "{N} replies", the replies) and the "Send to:" compose.
Rectangle {
    id: pane
    property string channelId: ""
    property string rootId: ""
    property string title: ""
    property string teamId: ""
    property string teamName: ""
    property string myName: ""
    /// The channel's conversation (its threads and time stamps).
    property Item host: null
    /// Threads with replies, newest reply first.
    readonly property var threads: {
        if (!host) return []
        return host.threadStarters(host.messages).filter(t => t.thread_replies > 0)
            .sort((a, b) => (b.thread_last || "").localeCompare(a.thread_last || ""))
    }
    readonly property var rootMessage: host ? host.messages.find(m => m.id === pane.rootId) || null : null
    signal closed()
    /// The thread's bots' actions, agents' meetings and pictures, handled
    /// as the conversation's.
    signal suggestedAction(var message, var action)
    signal agentMeeting(string op, var message, var entry, var command)
    signal openImageViewer(var images, int index, var message)
    signal jumpTo(string id)
    signal popOut(string rootId)
    /// A link Copilot's pane opened (its Sources).
    signal openLink(string url)
    // Open Copilot in a thread's header (Teams' CopilotFromChannelsL2Header,
    // TASK-0260; measured on winpc 2026-11-23): before More, Follow moving
    // one place left. Open, the thread takes the conversation's place (a
    // 61 tall header across: Back at 20.7, "Thread: {first message}"
    // 14/600 at 68.7, then Follow, Close Copilot and More, 32 apart and 16
    // from the right) with Copilot's pane (CopilotPane) at its right under
    // that header; closing Copilot puts the thread back in this pane.
    readonly property bool copilotAvailable: { try { return !!JSON.parse(backend.composeCopilotJson || "{}").channel } catch (e) { return false } }
    property bool copilotOpen: false
    onRootIdChanged: copilotOpen = false
    onChannelIdChanged: copilotOpen = false
    onCopilotAvailableChanged: if (!copilotAvailable) copilotOpen = false
    /// The thread as Copilot's pane names it: the team's thread, the
    /// channel, the thread's first message, the team's group.
    readonly property var copilotRequest: {
        if (!copilotOpen || !rootId) return null
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const t = teams.find(t => t.id === pane.teamId) || teams.find(t => (t.channels || []).some(c => c.id === pane.channelId)) || {}
        return { kind: "channel", thread: { teamId: t.thread_id || "", channelId: pane.channelId, replyChainId: pane.rootId, groupId: t.id || pane.teamId, tenantId: backend.tenantId() } }
    }
    color: theme.surface
    // The header's 32 px icon buttons (the conversation header's).
    component PaneAction: Rectangle {
        id: pa
        property alias icon: paIcon.name
        property color iconColor: theme.textStrong
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        anchors.verticalCenter: parent.verticalCenter
        color: paHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: paHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pa.clicked() }
        FluentIcon { id: paIcon; anchors.centerIn: parent; size: 20; color: theme.onFill(pa, pa.iconColor) }
        Accessible.role: Accessible.Button
    }
    readonly property string threadKey: rootId ? channelId + ";messageid=" + rootId : ""
    // The backend keeps the thread loaded and live while the pane shows it.
    property string openedChannel: ""
    property string openedRoot: ""
    onThreadKeyChanged: {
        if (openedRoot) backend.closeThreadWindow(openedChannel, openedRoot)
        openedChannel = channelId; openedRoot = rootId
        thread.threadLastReadAfter = 0
        if (rootId) {
            backend.openThreadWindow(channelId, rootId)
            // Opening it, Teams keeps "Last read" where it was, clears a
            // Mark as unread bookmark (chb 0) and reads to the newest
            // reply (ch) if it wasn't already.
            const t = threads.find(t => t.id === rootId)
            if (t) {
                const after = t.thread_bookmark > 0 ? t.thread_bookmark : (t.thread_read_to || 0)
                if (t.thread_unread > 0) thread.threadLastReadAfter = after
                if (t.thread_bookmark > 0) backend.setThreadRead(rootId, "clear", "")
                if (t.thread_last_id && Number(t.thread_last_id) > (t.thread_read_to || 0)) backend.setThreadRead(rootId, "read", t.thread_last_id)
            }
        }
    }
    Component.onDestruction: if (openedRoot) backend.closeThreadWindow(openedChannel, openedRoot)
    /// A suggested action's text in the open thread's reply box (once the
    /// thread's compose is there).
    function applySuggestion(action) { pendingSuggestion = action; suggestionTimer.restart() }
    property var pendingSuggestion: null
    function threadForTest() { return thread }
    function copilotForTest() { return copilot }
    Timer {
        id: suggestionTimer; interval: 150; repeat: true
        property int tries: 0
        onTriggered: {
            if (thread.visible && thread.composeReady()) { stop(); tries = 0; thread.applySuggestion(pane.pendingSuggestion); pane.pendingSuggestion = null }
            else if (++tries > 40) { stop(); tries = 0 }
        }
    }
    function openThread(id) {
        const m = host ? host.messages.find(m => m.id === id) : null
        title = m ? (m.text || "").split("\n")[0] : ""
        rootId = id
    }
    Rectangle { z: 3; visible: !pane.copilotOpen; width: 0.67; height: parent.height; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }

    Conversation {
        id: thread
        visible: !!pane.rootId
        anchors.fill: parent
        anchors.leftMargin: pane.copilotOpen ? 0 : 0.67
        anchors.rightMargin: pane.copilotOpen ? copilot.width : 0
        pane: true
        threadPane: true
        paneTitle: ""
        chatName: pane.title
        chatId: pane.threadKey
        threadRoot: pane.rootId
        threadChannel: pane.channelId
        isGroup: true
        teamId: pane.teamId; teamName: pane.teamName
        myName: pane.myName
        messages: {
            const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
            return all[pane.threadKey] || []
        }
        onClosePane: pane.closed()
        onSuggestedAction: (m, a) => pane.suggestedAction(m, a)
        onAgentMeeting: (op, m, e, c) => pane.agentMeeting(op, m, e, c)
        onOpenImageViewer: (l, i, m) => pane.openImageViewer(l, i, m)
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onDeleteMessage: id => backend.deleteMessage(id)
        onEditMessage: (id, text) => backend.editMessage(id, text)
    }

    // The header (over the conversation's own).
    Rectangle {
        z: 2
        x: 0.67; width: parent.width - 0.67; height: theme.headerHeight
        color: theme.surface
        // The list's.
        Text {
            visible: !pane.rootId
            x: 25 - 0.67; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Threads")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        PaneAction {
            visible: !pane.rootId
            x: parent.width - 57.7 + 0.67; icon: "dismiss-20"; Accessible.name: qsTr("Close threads")
            onClicked: pane.closed()
        }
        // A thread's.
        Item {
            id: threadHead
            visible: !!pane.rootId
            anchors.fill: parent
            readonly property bool following: !!pane.rootMessage && pane.rootMessage.following === true
            // (Copilot open: Back and "Thread: …" in the breadcrumb's place.)
            PaneAction {
                visible: pane.copilotOpen
                x: 20 - 0.67; height: 31.3
                icon: "arrow-left-20"; Accessible.name: qsTr("Back")
                onClicked: pane.copilotOpen = false
            }
            Text {
                visible: pane.copilotOpen
                x: 68.7 - 0.67; anchors.verticalCenter: parent.verticalCenter
                width: followButton.x - x - 12; elide: Text.ElideRight
                text: qsTr("Thread: %1").arg(pane.title)
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading
            }
            Text {
                visible: !pane.copilotOpen
                x: 20 - 0.67; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Threads")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.rootId = "" }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Go to thread list")
            }
            FluentIcon { visible: !pane.copilotOpen; x: 80 - 0.67; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-16"; size: 16; color: theme.text }
            Text {
                visible: !pane.copilotOpen
                x: 100 - 0.67; anchors.verticalCenter: parent.verticalCenter
                width: followButton.x - x - 12; elide: Text.ElideRight
                text: pane.title
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            }
            PaneAction {
                id: followButton
                x: pane.copilotOpen ? parent.width - 112 : parent.width - (pane.copilotAvailable ? 144.7 : 112.7) + 0.67; height: 31.3
                icon: threadHead.following ? "chat-multiple-minus-20" : "chat-multiple-20"
                Accessible.name: threadHead.following ? qsTr("Unfollow thread") : qsTr("Follow thread")
                onClicked: backend.setThreadFollowing(pane.rootId, !threadHead.following)
                ToolTip.visible: followHover.hovered; ToolTip.delay: 500
                ToolTip.text: Accessible.name
                HoverHandler { id: followHover }
            }
            PaneAction {
                id: copilotButton
                visible: pane.copilotAvailable
                x: pane.copilotOpen ? parent.width - 80 : parent.width - 112.7 + 0.67; height: 31.3
                icon: pane.copilotOpen ? "copilot-filled-48" : "ai-copilot"
                iconColor: pane.copilotOpen ? theme.brand : theme.textStrong
                Accessible.name: pane.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot")
                onClicked: { pane.copilotOpen = !pane.copilotOpen; console.info("COPILOT thread pane", pane.copilotOpen) }
                ToolTip.visible: copilotHover.hovered; ToolTip.delay: 500
                ToolTip.text: Accessible.name + " (Alt+C)"
                HoverHandler { id: copilotHover }
            }
            Shortcut { sequence: "Alt+C"; enabled: pane.visible && pane.copilotAvailable && !!pane.rootId; onActivated: copilotButton.clicked() }
            PaneAction {
                id: threadMore
                x: pane.copilotOpen ? parent.width - 48 : parent.width - 80.7 + 0.67; height: 31.3
                icon: "more-horizontal-20"
                iconColor: threadMenu.opened ? theme.brand : theme.textStrong
                Accessible.name: qsTr("More thread options")
                onClicked: threadMenu.open()
                MenuPopup {
                    id: threadMenu
                    x: parent.width - width; y: parent.height + 4
                    items: [
                        { key: "unread", label: qsTr("Mark as unread"), icon: "glasses-off-20" },
                        { key: "link", label: qsTr("Copy link"), icon: "link-20" },
                        { key: "jump", label: qsTr("Jump to original message"), icon: "arrow-enter-20" },
                        { key: "window", label: qsTr("Open thread in new window"), icon: "window-new-20" }
                    ]
                    onPicked: i => {
                        const k = items[i].key, m = pane.rootMessage
                        const t = pane.threads.find(t => t.id === pane.rootId)
                        if (k === "unread") { if (t && t.thread_last_id) backend.setThreadRead(pane.rootId, "unread", t.thread_last_id) }
                        else if (k === "link" && m) backend.copyMessageLink(JSON.stringify({ id: m.id, sender: m.sender || "", text: m.text || "", root_id: m.id }), JSON.stringify({ team_id: pane.teamId, team_name: pane.teamName, channel_name: pane.host ? pane.host.chatName : "" }))
                        else if (k === "jump") pane.jumpTo(pane.rootId)
                        else if (k === "window") pane.popOut(pane.rootId)
                    }
                }
            }
            PaneAction {
                visible: !pane.copilotOpen
                x: parent.width - 48.7 + 0.67; height: 31.3
                icon: "dismiss-20"; Accessible.name: qsTr("Close threads")
                onClicked: pane.closed()
            }
        }
        Rectangle { visible: pane.copilotOpen; anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
    }
    CopilotPane {
        id: copilot
        z: 1
        open: pane.copilotOpen && !!pane.rootId
        request: pane.copilotRequest
        x: parent.width - width; y: theme.headerHeight
        width: open ? 360 : 0; height: parent.height - y
        onClosed: pane.copilotOpen = false
        onOpenLink: url => pane.openLink(url)
    }

    // The list.
    ListView {
        id: list
        visible: !pane.rootId
        x: 2; y: theme.headerHeight + 4
        width: parent.width - 4; height: parent.height - y
        clip: true
        model: pane.threads
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: row
            required property var modelData
            width: list.width; height: 82.5; radius: 4
            color: rowHover.hovered ? theme.menuHover : "transparent"
            readonly property var repliers: {
                const seen = {}, out = []
                for (const r of (modelData.thread_repliers || []).slice().reverse()) {
                    const k = r.mri || r.name
                    if (seen[k]) continue
                    seen[k] = true; out.push(r)
                }
                return out.slice(0, 3)
            }
            Avatar { x: 22; y: 10; size: 32; name: row.modelData.sender || ""; photoId: row.modelData.sender_mri || "" }
            Text {
                x: 68; y: 8; width: stamp.x - x - 8; height: 20
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                text: (row.modelData.text || "").split("\n")[0]
                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(row, theme.textStrong)
            }
            Text {
                id: stamp
                anchors.right: parent.right; anchors.rightMargin: 12; y: 10; height: 16
                verticalAlignment: Text.AlignVCenter
                text: pane.host ? pane.host.stamp(row.modelData.thread_last) : ""
                font.family: theme.font; font.pixelSize: 12; color: theme.onFill(row, theme.textStrong)
            }
            Text {
                x: 68; y: 26; width: parent.width - x - 12; height: 20
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                text: (row.modelData.thread_last_mine ? qsTr("You") : row.modelData.thread_last_sender || "") + ": " + (row.modelData.thread_last_text || "").replace(/\n/g, " ")
                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(row, theme.textSecondary)
            }
            Row {
                x: 68; y: 50.5; height: 24
                spacing: 7
                Row {
                    Repeater {
                        model: row.repliers
                        Item {
                            required property var modelData
                            width: 24; height: 24
                            Avatar { anchors.centerIn: parent; size: 20; name: parent.modelData.name || ""; photoId: parent.modelData.mri || "" }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.thread_replies + (row.modelData.thread_replies === 1 ? " reply" : " replies")
                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(row, theme.textStrong)
                }
            }
            FluentIcon {
                visible: row.modelData.following === true
                anchors.right: parent.right; anchors.rightMargin: 12
                y: 55.3; name: "chat-multiple-checkmark-20-filled"; size: 14; color: theme.onFill(row, theme.brand)
            }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pane.openThread(row.modelData.id) }
            Accessible.role: Accessible.ListItem
            Accessible.name: (row.modelData.text || "") + ", " + qsTr("%n replies", "", row.modelData.thread_replies) + (row.modelData.following === true ? ", " + qsTr("Followed", "simpleCollab:k4vha2p5n") : "")
        }
    }
}
