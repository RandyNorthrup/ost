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

    // Owners' items for a channel other than General (Teams: Recommend for
    // everyone / Stop recommending, then Archive channel and Delete
    // channel); an archived channel has Teams' short menu.
    readonly property bool teamOwner: { const t = JSON.parse(backend.teamsJson || "[]").find(t => t.id === root.teamId); return !!t && t.owner === true }
    readonly property bool ownedChannel: (root.channel.owner === true || teamOwner) && root.channel.general !== true
    readonly property var archivedItems: [
        { key: "window", label: "Open in new window", icon: "open-window-20" },
        { key: "manage", label: "Manage channel", icon: "settings-20" },
        { key: "link", label: "Copy link", icon: "link-20" },
        { key: "restore", label: "Restore channel", icon: "arrow-clockwise-20" },
        { key: "delete", label: "Delete channel", icon: "delete-20" }
    ]
    readonly property var ownerItems: ownedChannel ? [
        root.channel.recommended
            ? { key: "unrecommend", label: "Stop recommending for everyone", icon: "sparkle-20" }
            : { key: "recommend", label: "Recommend for everyone", icon: "sparkle-20" },
        { separator: true },
        { key: "archive", label: "Archive channel", icon: "archive-20" },
        { key: "delete", label: "Delete channel", icon: "delete-20" }
    ] : []
    MenuPopup {
        id: menu
        margins: 8
        items: root.channel.archived === true ? root.archivedItems : (root.manageMode
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
        ], root.manageMode ? [] : [{ key: "workflows", label: "Workflows", icon: "workflows-20" }], root.ownerItems).filter(i => i !== null)
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
            else if (k === "recommend" || k === "unrecommend" || k === "restore") root.act(k)
            else if (k === "archive") archiveDialog.start(root.channel)
            else if (k === "delete") deleteDialog.start(root.channel)
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

    // Teams' channel dialogs (measured 2026-11-09): 600 wide, padding 20 30
    // 32, the title 18/28 semibold, the text 14/20, Cancel and the action
    // (96 x 31.3) at the end.
    component ChannelDialog: Popup {
        id: cd
        property var channel: ({})
        property string titleText
        property string actionText
        default property alias body: bodyCol.data
        signal accepted()
        function start(c) { channel = c; open() }
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600; padding: 0
        height: bodyCol.y + bodyCol.implicitHeight + 8 + 31.3 + 32.7
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Text {
            x: 30.7; y: 22.7; width: 508.8
            wrapMode: Text.Wrap
            text: cd.titleText
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Component.onCompleted: bodyCol.y = Qt.binding(() => y + height + 10)
        }
        Column { id: bodyCol; x: 30.7; width: 538.7 }
        Row {
            x: parent.width - 30.7 - width; y: cd.height - 32.7 - 31.3
            spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: cdCancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cdCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: cd.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: cdOkHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: cd.actionText; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: cdOkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { cd.close(); cd.accepted() } }
                Accessible.role: Accessible.Button; Accessible.name: cd.actionText
            }
        }
    }
    ChannelDialog {
        id: archiveDialog
        property bool readOnly: false
        titleText: "Archive the " + (channel.name || "") + " channel?"
        actionText: "Archive"
        onOpened: readOnly = false
        onAccepted: backend.channelAction("archive", root.teamId, channel.id, JSON.stringify({ readOnly: readOnly }))
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: "This will freeze all conversations in the channel. You can restore the channel any time."
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
        }
        Item {
            width: parent.width; height: 36
            Rectangle {
                x: 8; y: 10; width: 16; height: 16; radius: 2
                color: archiveDialog.readOnly ? theme.brand : "transparent"
                border.color: archiveDialog.readOnly ? theme.brand : theme.textSecondary; border.width: 0.67
                FluentIcon { visible: archiveDialog.readOnly; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: "white" }
            }
            Text { x: 36; y: 8; text: "Make the SharePoint folder read-only for team members"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: archiveDialog.readOnly ? theme.text : theme.textSecondary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: archiveDialog.readOnly = !archiveDialog.readOnly }
            Accessible.role: Accessible.CheckBox
            Accessible.checked: archiveDialog.readOnly
            Accessible.name: "Make the SharePoint folder read-only for team members"
        }
    }
    ChannelDialog {
        id: deleteDialog
        titleText: "Delete the " + (channel.name || "") + " channel from the " + root.teamName + " team"
        actionText: "Delete"
        onAccepted: backend.channelAction("delete-channel", root.teamId, channel.id, "")
        readonly property string site: { const t = JSON.parse(backend.teamsJson || "[]").find(t => t.id === root.teamId); return t ? t.site_url || "" : "" }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            textFormat: Text.StyledText
            readonly property string esc: (deleteDialog.channel.name || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            text: "Are you sure you want to delete the <b>" + esc + "</b> channel? All conversations will be deleted. "
                + (deleteDialog.site ? "<a href=\"" + deleteDialog.site + "/Shared%20Documents/" + encodeURI(deleteDialog.channel.name || "") + "\">Your files are still accessible here</a>." : "")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
            linkColor: theme.brandForeground1
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    // Test hooks.
    function openNotifyForTest() { menu.open(); notifyFlyout.parent = menu.contentItem; notifyFlyout.x = -notifyFlyout.width + 4; notifyFlyout.y = 60; notifyFlyout.open() }
    function customizeForTest() { notifyDialog.start(root.channel) }
    function editForTest() { editDialog.start(root.channel) }
    function emailForTest() { emailDialog.start(root.channel) }
    function closeAllForTest() { notifyFlyout.close(); menu.close(); notifyDialog.close(); editDialog.close(); emailDialog.close(); archiveDialog.close(); deleteDialog.close() }
    function archiveForTest() { archiveDialog.start(root.channel) }
    function deleteForTest() { deleteDialog.start(root.channel) }
}
