import QtQuick
import QtQuick.Controls.Basic

// A channel's menu, as Teams has it in the channel's header (More channel
// options) and on its row in the chat list (measured on winpc, 2026-11-09):
// See new posts at top | Open in new window | Manage notifications ▸,
// Move to section ▸, Hide | Edit channel, Manage channel, Copy link, Get
// email address, Workflows. (Hide reads Show for a hidden channel.) On the
// Manage channel page it starts Go to channel, Open in new window and has no
// Workflows.
// Manage notifications opens Teams' flyout beside the row: "Select what
// content notifies you" (12/20 semibold #616161, padding 0 8), then All new
// messages, @mentions and replies and Mute (64 tall: the check (16) at 4,
// the icon (20) at 24, the name (14/20) and what it means (12/16 #616161,
// 232 wide) at 50), a divider and Customize (32, the icon at 24).
Item {
    id: root
    /// The channel as the team list has it: {id, name, general, notify,
    /// owner, layout, description, shown}.
    property var channel: ({})
    property string teamId: ""
    property string teamName: ""
    /// The channel's newest post (Follow all new threads starts there).
    property string newestPost: ""
    /// New posts show at the bottom (Teams' enableChannelsV2).
    property bool postsAtBottom: true
    /// The Manage channel page's More options.
    property bool manageMode: false
    /// See new posts at top / bottom: only for the channel that's open
    /// (Teams leaves it out on other channels' rows).
    property bool postsOrder: true
    /// Manage team's channel rows: no Hide / Show (the row has its own).
    property bool rowMode: false
    /// The section it's in, for Move to section.
    readonly property var folderList: backend.foldersJson ? (JSON.parse(backend.foldersJson).folders || []) : []
    readonly property string holder: { const f = folderList.find(f => (f.kind === "Favorites" || f.kind === "UserCreated" || f.kind === "UserDefined") && f.items.indexOf(root.channel.id) >= 0); return f ? f.id : "" }
    signal goToChannel()
    signal openInNewWindow()
    signal manageChannel()
    signal workflows()
    readonly property alias menu: menu

    function show(anchor, px, py) {
        menu.parent = anchor
        menu.x = px; menu.y = py
        menu.open()
    }
    function moveTargets() {
        const out = folderList.filter(f => (f.kind === "Favorites" || f.kind === "UserCreated" || f.kind === "UserDefined") && f.id !== holder)
            .map(f => ({ label: f.title, to: f.id }))
        if (out.length) out.push({ separator: true })
        out.push({ label: "New section", icon: "folder-add-20", newSection: true })
        return out
    }
    function act(op, arg) { backend.channelAction(op, root.teamId, root.channel.id, arg || "") }

    MenuPopup {
        id: menu
        margins: 8
        items: (root.manageMode
            ? [{ key: "go", label: "Go to channel", icon: "channel-20" },
               { key: "window", label: "Open in new window", icon: "open-window-20" },
               { separator: true }]
            : (root.postsOrder ? [root.postsAtBottom
                ? { key: "top", label: "See new posts at top", icon: "channel-posts-top-20" }
                : { key: "bottom", label: "See new posts at bottom", icon: "channel-posts-top-20" },
               { separator: true }] : []).concat([
               { key: "window", label: "Open in new window", icon: "open-window-20" },
               { separator: true }])).concat([
            { key: "notify", label: "Manage notifications", icon: "alert-20", flyout: true },
            { key: "move", label: "Move to section", icon: "star-20", submenu: root.moveTargets() },
            root.rowMode ? null : root.channel.shown === false
                ? { key: "show", label: "Show", icon: "eye-20" }
                : { key: "hide", label: "Hide", icon: "eye-off-20" },
            { separator: true },
            { key: "edit", label: "Edit channel", icon: "edit-20" },
            { key: "manage", label: "Manage channel", icon: "settings-20" },
            { key: "link", label: "Copy link", icon: "link-20" },
            { key: "email", label: "Get email address", icon: "mail-20" }
        ], root.manageMode ? [] : [{ key: "workflows", label: "Workflows", icon: "workflows-20" }]).filter(i => i !== null)
        onFlyoutRequested: (i, row) => {
            if (i < 0 || !row) { notifyFlyout.close(); return }
            const p = row.mapToItem(menu.contentItem, 0, 0)
            notifyFlyout.parent = menu.contentItem
            notifyFlyout.x = -notifyFlyout.width + 4
            notifyFlyout.y = p.y - 4
            notifyFlyout.open()
        }
        onClosed: notifyFlyout.close()
        onPicked: i => {
            const k = items[i].key
            if (k === "top" || k === "bottom") root.act(k === "top" ? "posts-at-top" : "posts-at-bottom")
            else if (k === "go") root.goToChannel()
            else if (k === "window") root.openInNewWindow()
            else if (k === "hide" || k === "show") root.act(k)
            else if (k === "edit") editDialog.start(root.channel)
            else if (k === "manage") root.manageChannel()
            else if (k === "link") root.act("copy-link", root.channel.name)
            else if (k === "email") emailDialog.start(root.channel)
            else if (k === "workflows") root.workflows()
        }
        onSubPicked: (i, j) => {
            const t = items[i].submenu[j]
            if (t.newSection) sectionDialog.create(root.channel.id, root.holder)
            else if (t.to) backend.folderAction("move", JSON.stringify({ item: root.channel.id, to: t.to, from: root.holder }))
        }
    }
    SectionDialog { id: sectionDialog; existing: root.folderList.map(f => f.title) }

    // Manage notifications ▸
    Popup {
        id: notifyFlyout
        padding: 4
        width: 290 + 8
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        readonly property var choices: [
            { mode: "all", icon: "alert-on-20", label: "All new messages", hint: "New messages, all @mentions, and replies to followed threads" },
            { mode: "mentions", icon: "alert-20", label: "@mentions and replies", hint: "All @mentions and replies to followed threads" },
            { mode: "mute", icon: "alert-off-20", label: "Mute", hint: "You'll still be notified for personal mentions and replies to followed threads" }
        ]
        contentItem: Column {
            spacing: 2
            Text {
                width: 290; height: 32
                leftPadding: 8; rightPadding: 8
                verticalAlignment: Text.AlignVCenter
                text: "Select what content notifies you"
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: theme.textSecondary
            }
            Repeater {
                model: notifyFlyout.choices
                Rectangle {
                    id: choice
                    required property var modelData
                    readonly property bool current: (root.channel.notify || "mentions") === modelData.mode
                    width: 290; height: 64; radius: 4
                    color: choiceHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { visible: choice.current; x: 4; y: 8; size: 16; name: "checkmark-16"; color: theme.textStrong }
                    FluentIcon { x: 24; y: 6; size: 20; name: choice.modelData.icon; color: choiceHover.hovered ? theme.text : theme.textStrong }
                    Column {
                        x: 50; y: 6; width: 232
                        Text { text: choice.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: choiceHover.hovered ? theme.text : theme.textStrong }
                        Text { width: 232; wrapMode: Text.Wrap; text: choice.modelData.hint; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    }
                    HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { notifyFlyout.close(); menu.close(); if (!choice.current) root.act("notify", choice.modelData.mode) } }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: choice.current
                    Accessible.name: modelData.label
                }
            }
            Item {
                width: 290; height: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; x: -5; width: 300; height: 0.67; color: theme.divider }
            }
            Rectangle {
                width: 290; height: 32; radius: 4
                color: customHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 24; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "options-20"; color: customHover.hovered ? theme.text : theme.textStrong }
                Text { x: 48; anchors.verticalCenter: parent.verticalCenter; text: "Customize"; font.family: theme.font; font.pixelSize: 14; color: customHover.hovered ? theme.text : theme.textStrong }
                HoverHandler { id: customHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { notifyFlyout.close(); menu.close(); notifyDialog.start(root.channel) } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: "Customize"
            }
        }
    }

    ChannelNotifyDialog { id: notifyDialog; teamId: root.teamId; teamName: root.teamName; newestPost: root.newestPost }
    ChannelEditDialog { id: editDialog; teamId: root.teamId }
    ChannelEmailDialog { id: emailDialog; teamId: root.teamId; teamName: root.teamName }

    // Test hooks.
    function openNotifyForTest() { menu.open(); notifyFlyout.parent = menu.contentItem; notifyFlyout.x = -notifyFlyout.width + 4; notifyFlyout.y = 60; notifyFlyout.open() }
    function customizeForTest() { notifyDialog.start(root.channel) }
    function editForTest() { editDialog.start(root.channel) }
    function emailForTest() { emailDialog.start(root.channel) }
    function closeAllForTest() { notifyFlyout.close(); menu.close(); notifyDialog.close(); editDialog.close(); emailDialog.close() }
}
