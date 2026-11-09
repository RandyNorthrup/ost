import QtQuick
import QtQuick.Controls.Basic

// A channel tab's conversation, beside the channel (Teams' end-slot
// conversation pane, measured on winpc 2026-11-09): 360 wide, a 0.67 px
// #E0E0E0 line on its left.
// - Header (end-slot-conversation-header): 61 tall, padding 0 20, a
//   #E0E0E0 line under it; "Conversation" (16/22 semibold) and Close
//   (32 x 21.3) at the end.
// - Before anyone has talked (platform-entity-no-conversation-layout,
//   centred): the 40 px chat glyph; 30 below it "Go ahead and start
//   talking!" (16/22 semibold); 15 below "Whatever you post here will also
//   show up in the main channel." (14/20, 340 wide, centred); 15 below the
//   brand "Start conversation" button (31.3 tall, padding 5 12). Starting
//   posts the tab's link in the channel and makes that post the tab's
//   conversation (TabsApi: start_conversation).
// - Then the conversation: the thread as a chat (the post first), with
//   "Reply in thread".
Rectangle {
    id: pane
    /// The tab (backend Tab: id, name, conversation, icon…).
    property var tab: null
    property string teamId: ""
    property string teamName: ""
    property string channelId: ""
    property string myName: ""
    property var channelTabs: []
    signal closed()
    signal openTab(string tabId)
    color: theme.surface

    property string startedRoot: ""
    property bool starting: false
    property bool failed: false
    readonly property string rootId: tab ? (tab.conversation || (startedFor === tab.id ? startedRoot : "")) : ""
    property string startedFor: ""
    readonly property string threadKey: rootId ? channelId + ";messageid=" + rootId : ""
    // The backend keeps the thread loaded and live while the pane shows it.
    property string openedChannel: ""
    property string openedRoot: ""
    onThreadKeyChanged: {
        if (openedRoot) backend.closeThreadWindow(openedChannel, openedRoot)
        openedChannel = channelId; openedRoot = rootId
        if (rootId) backend.openThreadWindow(channelId, rootId)
    }
    onTabChanged: { starting = false; failed = false }
    Component.onDestruction: if (openedRoot) backend.closeThreadWindow(openedChannel, openedRoot)
    Connections {
        target: backend
        function onChannelTabResultChanged() {
            const r = JSON.parse(backend.channelTabResult || "{}")
            if (r.op !== "converse" || !pane.tab || r.tab !== pane.tab.id) return
            pane.starting = false
            if (r.ok && r.root) { pane.startedFor = r.tab; pane.startedRoot = r.root } else pane.failed = true
        }
    }
    function start() {
        if (!tab || starting) return
        starting = true; failed = false
        backend.channelTabChange("converse", teamId, channelId, tab.id, "")
    }
    function startForTest() { start() }
    function conversationForTest() { return thread }

    Rectangle { width: 0.67; height: parent.height; color: theme.divider; z: 5 }

    // Before the conversation starts.
    Item {
        visible: !pane.rootId
        anchors.fill: parent
        Item {
            id: header
            width: parent.width; height: 61
            Text {
                x: 20.7; anchors.verticalCenter: parent.verticalCenter
                text: "Conversation"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 21.3; radius: 4
                color: closeHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.closed() }
                Accessible.role: Accessible.Button; Accessible.name: "Close"
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: header.height / 2
            width: 340
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "chat-20"; size: 40; color: theme.text }
            Item { width: 1; height: 30 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pane.failed ? "We couldn't start the conversation." : "Go ahead and start talking!"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Item { width: 1; height: 15 }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Whatever you post here will also show up in the main channel."
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Item { width: 1; height: 15 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: startLabel.implicitWidth + 24 + 2; height: 31.3; radius: 4
                color: pane.starting ? theme.pick("#F0F0F0", "#141414") : startHover.hovered ? theme.brandHover : theme.brandFill
                Text {
                    id: startLabel
                    anchors.centerIn: parent
                    text: "Start conversation"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: pane.starting ? theme.disabled : "white"
                }
                HoverHandler { id: startHover; cursorShape: pane.starting ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { enabled: !pane.starting; onTapped: pane.start() }
                Accessible.role: Accessible.Button; Accessible.name: "Start conversation"
            }
        }
    }

    // The conversation, as a chat.
    Conversation {
        id: thread
        visible: !!pane.rootId
        anchors.fill: parent
        anchors.leftMargin: 0.67
        pane: true
        paneTitle: "Conversation"; paneTitleSemibold: true; paneTitleX: 20; paneCloseRight: 52
        chatName: "Conversation"
        chatId: pane.threadKey
        threadRoot: pane.rootId
        threadChannel: pane.channelId
        isGroup: true
        teamId: pane.teamId; teamName: pane.teamName
        myName: pane.myName
        linkedTabs: pane.channelTabs
        messages: {
            const all = backend.threadWindowsJson ? JSON.parse(backend.threadWindowsJson) : {}
            return all[pane.threadKey] || []
        }
        onClosePane: pane.closed()
        onOpenLinkedTab: id => pane.openTab(id)
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onDeleteMessage: id => backend.deleteMessage(id)
        onEditMessage: (id, text) => backend.editMessage(id, text)
    }
}
