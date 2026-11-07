import QtQuick
import QtQuick.Controls.Basic

// The Chat pane, laid out as Teams desktop's (measured from its DOM at 1x):
// header, filter chips, then Quick views, Favorites, Chats and Teams and
// channels as collapsible groups of 32 px rows.
Rectangle {
    id: root
    property var chats: []
    property var teams: []
    property string currentId
    /// Chat ids with an unsent draft (Quick views > Drafts).
    property var draftIds: []
    property bool draftsOpen: false
    /// Quick views > Mentions: shown once someone has @mentioned you.
    property bool hasMentions: false
    property bool mentionsOpen: false
    signal openMentions()
    signal chatSelected(string id, string name)
    signal newChat()
    signal openDrafts()
    signal markAllRead()
    color: theme.pane
    width: theme.listWidth

    // Filters: a chip ("unread", "channels", "chats") and/or a name filter.
    property string chipFilter: ""
    property string nameFilter: ""
    property bool filtering: false
    readonly property bool filtered: chipFilter.length > 0 || nameFilter.length > 0
    // Keyboard shortcuts (Ctrl+Shift+F, Ctrl+Alt+U/C/A/Z).
    function openFilter() { filtering = true; filterField.forceActiveFocus() }
    function setChip(c) { chipFilter = chipFilter === c ? "" : c }
    function clearFilters() { chipFilter = ""; nameFilter = ""; filterField.text = ""; filtering = false }
    function nameMatches(n) { return !nameFilter || (n || "").toLowerCase().indexOf(nameFilter) >= 0 }
    function chatShown(c) {
        // Teams doesn't list chats nothing has been said in, unless open.
        if (c.empty && c.id !== root.currentId) return false
        if (chipFilter === "channels") return false
        if (chipFilter === "unread" && !c.unread) return false
        return nameMatches(c.name)
    }
    readonly property var favorites: chats.filter(c => c.favorite && chatShown(c))
        .sort((a, b) => (a.favoriteRank ?? 1e9) - (b.favoriteRank ?? 1e9))
    readonly property var others: chats.filter(c => !c.favorite && chatShown(c))
    // Teams with the channels that pass the filters.
    readonly property var shownTeams: (chipFilter === "chats" || chipFilter === "unread") ? []
        : teams.map(t => ({ id: t.id, name: t.name,
                            channels: nameMatches(t.name) ? t.channels : t.channels.filter(ch => nameMatches(ch.name)) }))
               .filter(t => nameMatches(t.name) || t.channels.length > 0)
    property bool quickOpen: true
    property bool favOpen: true
    property bool chatsOpen: true
    property bool teamsOpen: true

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    component HeaderButton: Rectangle {
        id: hb
        property alias icon: hbIcon.name
        property int iconSize: 20
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: hbHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        FluentIcon { id: hbIcon; anchors.centerIn: parent; size: hb.iconSize; color: theme.textStrong }
    }

    // Header: "Chat", then more / filter / new message (with its menu).
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            x: 32; y: 19
            text: "Chat"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        HeaderButton {
            id: moreList
            x: 194; y: 15; icon: "more-20"; Accessible.name: "More list options"
            onClicked: listMenu.open()
            MenuPopup {
                id: listMenu
                y: parent.height + 4
                items: [{ label: "Mark all as read", icon: "checkmark-12" }, { separator: true },
                        { label: "Collapse all groups" }, { label: "Expand all groups" }]
                onPicked: i => {
                    if (i === 0) root.markAllRead()
                    else if (i === 2) { root.quickOpen = false; root.favOpen = false; root.chatsOpen = false; root.teamsOpen = false }
                    else if (i === 3) { root.quickOpen = true; root.favOpen = true; root.chatsOpen = true; root.teamsOpen = true }
                }
            }
        }
        HeaderButton {
            x: 226; y: 15; icon: "search-20"; Accessible.name: "Show filter text box"
            onClicked: { root.filtering = !root.filtering; if (root.filtering) filterField.forceActiveFocus(); else { filterField.text = "" } }
        }
        HeaderButton {
            x: 258; y: 14; width: 26; icon: "compose-20"
            Accessible.name: "New message"
            onClicked: root.newChat()
        }
        HeaderButton {
            x: 284; y: 14; width: 20; icon: "chevron-down-12"; iconSize: 12; Accessible.name: "New items"
            onClicked: newMenu.open()
            MenuPopup {
                id: newMenu
                x: -200; y: parent.height + 4
                items: [{ label: "New chat", icon: "compose-20", keys: "Ctrl+N" }]
                onPicked: root.newChat()
            }
        }
    }

    // Filter chips: 24 px pills with a 1 px neutral border, 4 px apart.
    Row {
        id: chips
        visible: !root.filtering
        x: 32; y: 69
        spacing: 4
        Repeater {
            model: ["Unread", "Channels", "Chats"]
            delegate: Rectangle {
                id: chip
                required property string modelData
                readonly property bool on: root.chipFilter === modelData.toLowerCase()
                height: 24; radius: 12
                width: chipText.implicitWidth + 16
                // An active chip takes the brand tint, as Fluent's toggles do.
                color: on ? theme.brandTint : (chipHover.hovered ? theme.rowHover : "transparent")
                border.color: on ? theme.brand : (chipHover.hovered ? theme.strokeHover : theme.stroke)
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.chipFilter = chip.on ? "" : chip.modelData.toLowerCase() }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData
                    font.family: theme.font; font.pixelSize: theme.small
                    color: chip.on ? theme.brand : theme.textStrong
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData
                Accessible.checked: on
            }
        }
    }
    // "Show filter text box": filter the list by name.
    Rectangle {
        visible: root.filtering
        x: 32; y: 65; width: 272; height: 32; radius: theme.radius
        color: theme.input
        border.color: filterField.activeFocus ? theme.brand : theme.stroke
        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
        TextInput {
            id: filterField
            x: 32; width: parent.width - 64
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            onTextChanged: root.nameFilter = text.trim().toLowerCase()
            Keys.onEscapePressed: { text = ""; root.filtering = false }
            Text { visible: !filterField.text; text: "Filter by name"; color: theme.textTertiary; font: filterField.font }
            Accessible.name: "Filter by name"
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: theme.radius
            color: clh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textStrong }
            HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { filterField.text = ""; root.filtering = false } }
            Accessible.role: Accessible.Button
            Accessible.name: "Close filter"
        }
    }
    HeaderButton {
        x: 282; y: 65; width: 24; height: 24; icon: "chevron-down-12"; iconSize: 12; Accessible.name: "More filters"
        onClicked: filterMenu.open()
        MenuPopup {
            id: filterMenu
            x: -220; y: parent.height + 4
            items: [
                { label: "Unread", checked: root.chipFilter === "unread" },
                { label: "Channels", checked: root.chipFilter === "channels" },
                { label: "Chats", checked: root.chipFilter === "chats" },
                { separator: true },
                { label: "Clear filters" },
            ]
            onPicked: i => {
                const keys = ["unread", "channels", "chats"]
                if (i < 3) root.chipFilter = root.chipFilter === keys[i] ? "" : keys[i]
                else { root.chipFilter = ""; root.nameFilter = ""; root.filtering = false }
            }
        }
    }

    ListView {
        id: list
        y: 106
        width: parent.width - 1
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        header: Column {
            width: list.width
            // Quick views > Drafts
            SectionHeader { visible: !root.filtered; label: "Quick views"; open: root.quickOpen; onToggled: root.quickOpen = !root.quickOpen }
            Item { width: 1; height: root.quickOpen && !root.filtered ? 4 : 0 }
            ListRow {
                visible: root.quickOpen && !root.filtered && root.hasMentions
                label: "Mentions"; icon: "mention-20"
                selected: root.mentionsOpen
                onClicked: root.openMentions()
            }
            ListRow {
                visible: root.quickOpen && !root.filtered
                label: "Drafts"; icon: "drafts-20"
                selected: root.draftsOpen
                onClicked: root.openDrafts()
            }
            // A hairline 12 px below, then the next group 4.6 px after it.
            Item { width: 1; height: root.filtered ? 0 : 12 }
            Rectangle { visible: !root.filtered; x: 16; width: list.width - 32; height: 1; color: theme.divider }
            Item { width: 1; height: root.filtered ? 0 : 4 }
            SectionHeader { visible: root.favorites.length > 0 || !root.filtered; label: "Favorites"; open: root.favOpen; onToggled: root.favOpen = !root.favOpen }
            Item { width: 1; height: root.favOpen && root.favorites.length > 0 ? 4 : 0 }
            Repeater {
                model: root.favOpen ? root.favorites : []
                ChatRow { required property var modelData; chat: modelData }
            }
            Item { width: 1; height: 8 }
            SectionHeader { visible: root.others.length > 0 || !root.filtered; label: "Chats"; open: root.chatsOpen; onToggled: root.chatsOpen = !root.chatsOpen }
            Item { width: 1; height: root.chatsOpen && root.others.length > 0 ? 4 : 0 }
        }
        model: root.chatsOpen ? root.others : []
        delegate: ChatRow { required property var modelData; chat: modelData }
        footer: Column {
            width: list.width
            visible: root.shownTeams.length > 0
            Item { width: 1; height: 8 }
            SectionHeader { label: "Teams and channels"; open: root.teamsOpen; onToggled: root.teamsOpen = !root.teamsOpen }
            Item { width: 1; height: root.teamsOpen ? 4 : 0 }
            Repeater {
                model: root.teamsOpen ? root.shownTeams : []
                Column {
                    id: team
                    required property var modelData
                    property bool open: true
                    width: list.width
                    // Team row: chevron, team picture, name.
                    Item {
                        width: list.width; height: 32
                        Rectangle {
                            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                            color: teamHover.hovered ? theme.rowHover : "transparent"
                        }
                        FluentIcon {
                            x: 18; y: 10
                            name: team.open ? "chevron-down-12" : "chevron-right-12"; size: 12
                            color: theme.textSecondary
                        }
                        Avatar {
                            x: 32; y: 6
                            size: 20; square: true
                            name: team.modelData.name
                            initialsText: team.modelData.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                            photoId: "team:" + team.modelData.id
                        }
                        Text {
                            x: 64; width: parent.width - 64 - 24; y: 6
                            text: team.modelData.name
                            elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.textSecondary
                        }
                        HoverHandler { id: teamHover }
                        TapHandler { onTapped: team.open = !team.open }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Team " + team.modelData.name + (team.open ? ", expanded" : ", collapsed")
                    }
                    Repeater {
                        model: team.open ? team.modelData.channels : []
                        Item {
                            id: channel
                            required property var modelData
                            readonly property bool selected: modelData.id === root.currentId
                            width: list.width; height: 28
                            Rectangle {
                                x: 16; width: parent.width - 32; height: 28; radius: theme.radius
                                color: channel.selected ? theme.selected : (chHover.hovered ? theme.rowHover : "transparent")
                            }
                            Text {
                                x: 64; width: parent.width - 64 - 24; y: 4
                                text: channel.modelData.name
                                elide: Text.ElideRight
                                font.family: theme.font; font.pixelSize: theme.base
                                color: channel.selected ? theme.text : theme.textSecondary
                            }
                            HoverHandler { id: chHover }
                            TapHandler { onTapped: root.chatSelected(channel.modelData.id, channel.modelData.name) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Channel " + channel.modelData.name + " in " + team.modelData.name
                        }
                    }
                }
            }
            Item {
                visible: root.teamsOpen
                width: list.width; height: 28
                Text {
                    x: 31; y: 4
                    text: "See all your teams"
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.brand
                }
            }
            Item { width: 1; height: 8 }
        }
    }

    // Test hooks: a chat row's menu, by chat id.
    property var rowsForTest: ({})
    function openRowMenuForTest(id) { const r = rowsForTest[id]; if (r) r.openMenu(r.width - 50, 30) }
    function closeRowMenuForTest() { for (const k in rowsForTest) if (rowsForTest[k].menuOpen) rowsForTest[k].closeMenu() }

    // One chat in a group: picture with presence, name, unread dot.
    component ChatRow: Item {
        id: row
        property var chat
        readonly property bool menuOpen: rowMenu.opened
        function closeMenu() { rowMenu.close() }
        Component.onCompleted: root.rowsForTest[chat.id] = row
        readonly property bool selected: !root.draftsOpen && !root.mentionsOpen && chat.id === root.currentId
        readonly property bool unread: chat.unread === true && !selected
        width: list.width; height: 32
        Rectangle {
            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
            color: row.selected ? theme.selected : (hover.hovered ? theme.rowHover : "transparent")
        }
        Avatar {
            visible: !row.chat.muted
            x: 32; y: 6
            size: 20; name: row.chat.name
            photoId: row.chat.peerMri || ""
            group: row.chat.isGroup === true && !row.chat.peerMri
            presence: row.chat.presence || ""
        }
        // Muted: Teams swaps the picture for a 20 px #E6E6E6 circle with the
        // regular AlertOff icon (16, NeutralForeground3) at 2, 2.
        Rectangle {
            visible: !!row.chat.muted
            x: 32; y: 6; width: 20; height: 20; radius: 10
            color: theme.pick("#E6E6E6", "#3D3D3D")
            FluentIcon { x: 2; y: 2; name: "alert-off-20"; size: 16; color: theme.textSecondary }
        }
        Text {
            x: 64; width: parent.width - 64 - 40; y: 6
            text: row.chat.name
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            // Teams: bold only when unread; the open chat is just darker.
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: row.selected || row.unread ? theme.text : theme.textSecondary
        }
        // A call going on in the chat (Teams: the regular sound-wave 14 in
        // NeutralForeground3 at 244, 9 in the 288-wide row).
        FluentIcon {
            visible: !!row.chat.liveCall && !row.showMore
            x: parent.width - 60; y: 9
            name: "live-roster-14"; size: 14
            color: theme.textSecondary
        }
        // Unread: bold name plus a brand dot, as in Teams; muted chats keep
        // the bold name but not the dot (they don't count toward badges).
        Rectangle {
            visible: row.unread && !row.chat.muted && !row.showMore
            width: 8; height: 8; radius: 4
            x: parent.width - 16 - 8 - 12
            anchors.verticalCenter: parent.verticalCenter
            color: theme.brand
        }
        // On hover (or with its menu open), Teams' ··· "More options" at
        // 258, 6 in the 288-wide row.
        readonly property bool showMore: hover.hovered || rowMenu.opened
        Rectangle {
            visible: row.showMore
            x: parent.width - 46 - 4; y: 2; width: 28; height: 28; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: moreHover.hovered ? "more-horizontal-20-filled" : "more-horizontal-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.openMenu(parent.x, parent.y + parent.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More options"
        }
        HoverHandler { id: hover }
        TapHandler { onTapped: if (!moreHover.hovered) root.chatSelected(row.chat.id, row.chat.name) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => row.openMenu(ev.position.x, ev.position.y) }
        // The chat's menu (Teams' chat list ···, measured on winpc): Mark as
        // read / unread, Mute / Unmute, Copy link — the items OST has so far,
        // in Teams' order (Open in new window, Move to section, Manage apps,
        // Set workflows, Remove chat history and Hide are still to come).
        function openMenu(px, py) {
            rowMenu.items = [
                { key: row.unread ? "read" : "unread", label: row.unread ? "Mark as read" : "Mark as unread", icon: row.unread ? "glasses-20" : "mail-unread-20" },
                // Not for your own chat.
                row.chat.isSelf ? null : { key: row.chat.muted ? "unmute" : "mute", label: row.chat.muted ? "Unmute" : "Mute", icon: row.chat.muted ? "alert-20" : "alert-off-20" },
                { key: "link", label: "Copy link", icon: "link-20" }
            ].filter(i => i !== null)
            rowMenu.x = Math.min(px, row.width - rowMenu.implicitWidth - 8)
            rowMenu.y = py
            rowMenu.open()
        }
        MenuPopup {
            id: rowMenu
            separatorHeight: 8.6
            onPicked: i => {
                const k = items[i].key
                if (k === "read" || k === "unread") backend.setChatUnread(row.chat.id, k === "unread")
                else if (k === "mute" || k === "unmute") backend.setChatMuted(row.chat.id, k === "mute")
                else if (k === "link") backend.copyLinkOfChat(row.chat.id, row.chat.name)
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: row.chat.name + (row.unread ? ", unread" : "") + (row.chat.muted ? ", muted" : "") + (row.chat.liveCall ? ", call in progress" : "")
    }

    // A row with an icon instead of a picture (Quick views).
    component ListRow: Item {
        id: lr
        property string label
        property string icon
        property bool selected: false
        signal clicked()
        width: list.width; height: 32
        Rectangle {
            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
            color: lr.selected ? theme.selected : (lrHover.hovered ? theme.rowHover : "transparent")
        }
        FluentIcon { x: 32; y: 6; name: lr.icon; size: 20; color: theme.textSecondary }
        Text {
            x: 64; y: 6
            text: lr.label
            font.family: theme.font; font.pixelSize: theme.base
            color: lr.selected ? theme.text : theme.textSecondary
        }
        HoverHandler { id: lrHover }
        TapHandler { onTapped: lr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: lr.label
    }

    // Group header: 12 px chevron and label, 28 px tall.
    component SectionHeader: Item {
        id: sh
        property string label
        property bool open: true
        signal toggled()
        width: list.width; height: 28
        FluentIcon {
            x: 18; y: 8
            name: sh.open ? "chevron-down-12" : "chevron-right-12"; size: 12
            color: theme.textSecondary
        }
        Text {
            x: 32; y: 4
            text: sh.label
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
        TapHandler { onTapped: sh.toggled() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.Button
        Accessible.name: sh.label + (sh.open ? ", expanded" : ", collapsed")
    }
}
