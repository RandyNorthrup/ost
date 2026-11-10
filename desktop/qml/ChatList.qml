import QtQuick
import QtQuick.Controls.Basic

// The Chat pane, laid out as Teams desktop's (measured from its DOM at 1x;
// spec docs/spec/chat-list-and-header.md):
// - the header, then the filter pills (Unread, Channels, Chats, Meeting
//   chats, Communities, in Teams' order; Unread combines with one
//   category; pills that don't fit go to a second row behind "More
//   filters", the chosen ones stay in the first);
// - the sections from the server (Teams' conversation folders), in its
//   order with its expanded state: Quick views, Favorites, your own
//   sections, Chats, Teams and channels, Communities;
// - only the channels you show; unread names in bold (a team only while
//   collapsed); "New" on teams and channels you haven't opened;
// - a chat's ··· / right-click menu as Teams' (Mark as read/unread, Move
//   to section ▸, Remove from section, Mute, Copy link, Leave, Hide).
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
    /// Quick views ▸ Followed threads / Saved ("followed", "saved" or "").
    property string quickOpen: ""
    signal openQuick(string kind)
    signal openMentions()
    signal chatSelected(string id, string name)
    signal newChat()
    signal openDrafts()
    signal markAllRead()
    /// Communities ▸ Join communities.
    signal openCommunities()
    /// The chat menu's Open in new window, Manage apps and Set workflows.
    signal openChatWindow(string chatId, string name, string photoId, string presence)
    signal manageChatApps(string chatId, string name)
    signal chatWorkflows(string chatId, string name)
    /// Notify when available: the people tagged, by lower-case MRI
    /// ({id, email}); loaded at start and after each change.
    property var notifyTagged: ({})
    readonly property bool signedIn: backend.signedIn
    onSignedInChanged: if (signedIn) backend.channelAction("notify-tagged", "", "", "")
    Component.onCompleted: { if (signedIn) backend.channelAction("notify-tagged", "", "", ""); if (backend.signedIn) backend.loadSettings() }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "notify-tagged" && r.ok) {
                const m = {}
                for (const t of r.data || []) m[t.mri] = { id: t.id, email: t.email }
                root.notifyTagged = m
            } else if ((r.op === "notify-on" || r.op === "notify-off") && r.ok) {
                backend.channelAction("notify-tagged", "", "", "")
            } else if ((r.op === "notify-on" || r.op === "notify-off" || r.op === "remove-chat-history") && !r.ok) {
                backend.toast("Something went wrong on our end. Please try again.", "error")
            }
        }
    }
    /// See all your teams.
    property bool yourTeamsOpen: false
    signal openYourTeams()
    color: theme.pane
    width: theme.listWidth

    // ---- Filters ----
    // Unread combines with one category: "channels", "chats", "meetings"
    // or "communities" (Teams' single-select category pills).
    property bool unreadOn: false
    property string category: ""
    property string nameFilter: ""
    property bool filtering: false
    property bool moreFiltersOpen: false
    /// Older callers set one chip ("unread", "channels", "chats", "").
    property string chipFilter: ""
    onChipFilterChanged: {
        if (chipFilter === "unread") { unreadOn = true; category = "" }
        else if (chipFilter === "") { unreadOn = false; category = "" }
        else { unreadOn = false; category = chipFilter }
    }
    readonly property bool filtered: unreadOn || category.length > 0 || nameFilter.length > 0
    function openFilter() { filtering = true; filterField.forceActiveFocus() }
    /// Teams' pill toggle: Unread on its own, categories single-select.
    function setChip(c) {
        if (c === "unread") unreadOn = !unreadOn
        else category = category === c ? "" : c
    }
    function clearFilters() { unreadOn = false; category = ""; nameFilter = ""; filterField.text = ""; filtering = false; chipFilter = "" }
    function nameMatches(n) { return !nameFilter || (n || "").toLowerCase().indexOf(nameFilter) >= 0 }

    // ---- Server sections ----
    readonly property var folderData: backend.foldersJson ? JSON.parse(backend.foldersJson) : null
    readonly property var folders: folderData && folderData.folders && folderData.folders.length ? folderData.folders
        : [{ id: "", kind: "QuickViews", title: "Quick views", expanded: true, items: [] },
           { id: "", kind: "Favorites", title: "Favorites", expanded: true, items: [] },
           { id: "", kind: "RecentChats", title: "Chats", expanded: true, items: [] },
           { id: "", kind: "TeamsAndChannels", title: "Teams and channels", expanded: true, items: [] }]
    readonly property bool hasCommunities: folders.some(f => f.kind === "EngageCommunities")
    /// Conversations in Favorites or your own sections (not listed in Chats).
    readonly property var sectioned: {
        const m = {}
        for (const f of folders) if (f.kind === "Favorites" || root.isUsers(f)) for (const i of f.items) m[i] = f.id || f.kind
        return m
    }
    readonly property var userSections: folders.filter(f => root.isUsers(f))
    function isUsers(f) { return f.kind === "UserCreated" || f.kind === "UserDefined" }
    readonly property var favoritesFolder: folders.find(f => f.kind === "Favorites") || null
    // Before the server answers, Favorites come from the chat list.
    function inFavorites(c) { return favoritesFolder && favoritesFolder.id ? favoritesFolder.items.indexOf(c.id) >= 0 : !!c.favorite }

    function isMeeting(c) { return !!c.meeting || (c.id || "").indexOf("19:meeting_") === 0 }
    function chatShown(c) {
        // Teams doesn't list chats nothing has been said in, or ones you
        // hid, unless open.
        if ((c.empty || c.hidden) && c.id !== root.currentId) return false
        if (category === "channels" || category === "communities") return false
        if (category === "chats" && isMeeting(c)) return false
        if (category === "meetings" && !isMeeting(c)) return false
        if (unreadOn && !c.unread) return false
        return nameMatches(c.name)
    }
    function channelShown(t, ch) {
        if (!ch.shown && ch.id !== root.currentId) return false
        if (category && category !== "channels") return false
        if (unreadOn && !ch.unread) return false
        return nameMatches(t.name) || nameMatches(ch.name)
    }
    function chatById(id) { return chats.find(c => c.id === id) }
    function channelById(id) {
        for (const t of teams) { const ch = (t.channels || []).find(c => c.id === id); if (ch) return { team: t, channel: ch } }
        return null
    }
    // The rows of a section that holds conversations (Favorites, yours).
    function heldRows(f) {
        const out = []
        for (const id of f.items) {
            const c = chatById(id)
            if (c) { if (chatShown(c)) out.push({ type: "chat", chat: c }); continue }
            const ch = channelById(id)
            if (ch && channelShown(ch.team, ch.channel)) out.push({ type: "channel", channel: ch.channel, team: ch.team })
        }
        return out
    }
    readonly property var others: chats.filter(c => !(c.id in sectioned) && !(c.isSelf && inFavorites(c)) && !inFavorites(c) && chatShown(c))
    readonly property var favorites: chats.filter(c => inFavorites(c) && chatShown(c))
    // Teams with the channels that pass the filters (team rows stay while
    // any channel does).
    readonly property var shownTeams: (category && category !== "channels") ? []
        : teams.map(t => ({ id: t.id, name: t.name, new: t.new, expanded: t.expanded !== false,
                            channels: (t.channels || []).filter(ch => channelShown(t, ch)) }))
               .filter(t => t.channels.length > 0 && (!unreadOn || t.channels.some(c => c.unread)))
    readonly property var sections: folders.map(f => {
        let rows = []
        if (f.kind === "QuickViews") {
            if (category || unreadOn || nameFilter) rows = []
            else {
                if (root.hasMentions) rows.push({ type: "slice", key: "mentions", label: "Mentions", icon: "mention-20" })
                rows.push({ type: "slice", key: "followed", label: "Followed threads", icon: "followed-threads-20" })
                if (root.draftIds.length > 0) rows.push({ type: "slice", key: "drafts", label: "Drafts", icon: "drafts-20" })
                rows.push({ type: "slice", key: "saved", label: "Saved", icon: "bookmark-20" })
            }
        } else if (f.kind === "Favorites") {
            rows = f.id ? heldRows(f) : root.favorites.map(c => ({ type: "chat", chat: c }))
        } else if (root.isUsers(f)) {
            rows = heldRows(f)
        } else if (f.kind === "RecentChats") {
            rows = root.others.map(c => ({ type: "chat", chat: c }))
        } else if (f.kind === "TeamsAndChannels") {
            rows = root.shownTeams.map(t => ({ type: "team", team: t }))
            if (rows.length && !filtered) rows.push({ type: "seeAllTeams" })
        } else if (f.kind === "EngageCommunities") {
            rows = (category && category !== "communities") || unreadOn || nameFilter ? [] : [{ type: "joinCommunities" }]
        }
        // Sections stay while unfiltered; filtered, only ones with items.
        const keep = !filtered ? (f.kind !== "QuickViews" || rows.length > 0 || true) : rows.length > 0
        return { folder: f, rows: rows, keep: keep }
    }).filter(s => s.keep)
    readonly property bool nothingShown: filtered && sections.every(s => s.rows.length === 0)

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    component HeaderButton: Rectangle {
        id: hb
        property alias icon: hbIcon.name
        property int iconSize: 20
        property color iconColor: theme.textStrong
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: hbHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        FluentIcon { id: hbIcon; anchors.centerIn: parent; size: hb.iconSize; color: hb.iconColor }
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
                        { label: "Collapse all sections" }]
                onPicked: i => {
                    if (i === 0) root.markAllRead()
                    else if (i === 2) backend.folderAction("collapseAll", "{}")
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

    // ---- Filter pills (Teams' sticky filter) ----
    // 24 tall, 4 apart, border 0.67 NeutralStroke1, 12/16 NeutralForeground2,
    // padding 8; chosen: BrandForeground2 (#444791) fill, white text.
    readonly property var pillDefs: [
        { key: "unread", label: "Unread", keys: "Ctrl+Alt+U" },
        { key: "channels", label: "Channels", keys: "Ctrl+Alt+A" },
        { key: "chats", label: "Chats", keys: "Ctrl+Alt+C" },
        { key: "meetings", label: "Meeting chats", keys: "Ctrl+Alt+B" }
    ].concat(hasCommunities ? [{ key: "communities", label: "Communities", keys: "" }] : [])
    function pillOn(k) { return k === "unread" ? unreadOn : category === k }
    FontMetrics { id: pillMetrics; font.family: theme.font; font.pixelSize: 12 }
    function pillWidth(label) { return Math.ceil(pillMetrics.advanceWidth(label)) + 18 }
    // Pills that fit in the first row (250 px); the chosen ones first in
    // priority, the rest in order.
    readonly property var pillRows: {
        const room = 250
        const w = pillDefs.map(p => pillWidth(p.label))
        const keep = pillDefs.map(() => true)
        const total = () => pillDefs.reduce((s, p, i) => s + (keep[i] ? w[i] + 4 : 0), -4)
        for (let i = pillDefs.length - 1; i >= 0 && total() > room; i--) if (!pillOn(pillDefs[i].key)) keep[i] = false
        return { first: pillDefs.filter((p, i) => keep[i]), second: pillDefs.filter((p, i) => !keep[i]) }
    }
    readonly property bool secondRow: moreFiltersOpen && pillRows.second.length > 0
    component Pill: Rectangle {
        id: pill
        property var def
        readonly property bool on: root.pillOn(def.key)
        height: 24; radius: 12
        width: root.pillWidth(def.label)
        color: on ? theme.brandForeground2 : (pillHover.hovered ? theme.rowHover : "transparent")
        border.width: 0.67
        border.color: on ? theme.brandForeground2 : (pillHover.hovered ? theme.strokeHover : theme.stroke)
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.setChip(pill.def.key) }
        Text {
            anchors.centerIn: parent
            text: pill.def.label
            font.family: theme.font; font.pixelSize: 12
            color: pill.on ? "white" : theme.textStrong
        }
        ToolTip.visible: pillHover.hovered
        ToolTip.delay: 600
        ToolTip.text: pill.def.keys ? pill.def.label + " (" + pill.def.keys + ")" : pill.def.label
        Accessible.role: Accessible.Button
        Accessible.name: pill.def.label
        Accessible.checkable: true
        Accessible.checked: pill.on
    }
    Row {
        visible: !root.filtering && root.filtersShown
        x: 32; y: 69
        spacing: 4
        Repeater { model: root.pillRows.first; Pill { required property var modelData; def: modelData } }
    }
    Row {
        visible: !root.filtering && root.secondRow && root.filtersShown
        x: 32; y: 101
        spacing: 4
        Repeater { model: root.secondRow ? root.pillRows.second : []; Pill { required property var modelData; def: modelData } }
    }
    // More filters / Fewer filters: only when pills overflow.
    HeaderButton {
        visible: !root.filtering && root.pillRows.second.length > 0 && root.filtersShown
        x: 282; y: 65; width: 24; height: 24; radius: 4
        icon: root.moreFiltersOpen ? "chevron-up-16" : "chevron-down-16"; iconSize: 16
        iconColor: root.moreFiltersOpen ? theme.brand : theme.textStrong
        onClicked: root.moreFiltersOpen = !root.moreFiltersOpen
        ToolTip.visible: false
        Accessible.name: root.moreFiltersOpen ? "Fewer filters" : "More filters"
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

    // ---- The list ----
    Flickable {
        id: list
        y: root.filtering ? 106 : !root.filtersShown ? 66 : root.secondRow ? 138 : 106
        width: parent.width - 1
        height: parent.height - y
        clip: true
        contentHeight: listCol.height + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: listCol
            width: list.width
            Repeater {
                model: root.sections
                Column {
                    id: sec
                    required property var modelData
                    required property int index
                    readonly property var folder: modelData.folder
                    width: list.width
                    // Quick views end with a hairline (12 below, the next
                    // section 4 after it).
                    SectionHeader {
                        label: sec.folder.title
                        open: sec.folder.expanded
                        userSection: root.isUsers(sec.folder)
                        onToggled: backend.folderAction(sec.folder.expanded ? "collapse" : "expand", JSON.stringify({ id: sec.folder.id }))
                        onMenuRequested: (px, py) => root.openSectionMenu(sec.folder, this, px, py)
                    }
                    Item { width: 1; height: sec.folder.expanded && sec.modelData.rows.length > 0 ? 4 : 0 }
                    Repeater {
                        model: sec.folder.expanded ? sec.modelData.rows : []
                        Loader {
                            required property var modelData
                            width: list.width
                            sourceComponent: modelData.type === "chat" ? chatRowComp
                                : modelData.type === "channel" ? channelRowComp
                                : modelData.type === "team" ? teamComp
                                : modelData.type === "slice" ? sliceComp
                                : modelData.type === "seeAllTeams" ? seeAllComp
                                : joinCommunitiesComp
                            property var row: modelData
                            property var section: sec.folder
                        }
                    }
                    Item { width: 1; height: sec.folder.kind === "QuickViews" && !root.filtered ? 12 : 8 }
                    Rectangle { visible: sec.folder.kind === "QuickViews" && !root.filtered; x: 16; width: list.width - 32; height: 1; color: theme.divider }
                    Item { width: 1; height: sec.folder.kind === "QuickViews" && !root.filtered ? 4 : 0 }
                }
            }
            // Teams' empty filter result.
            Column {
                visible: root.nothingShown
                width: list.width
                topPadding: 40
                spacing: 0
                Image {
                    x: 60; width: 200; height: 204
                    source: "../assets/illustrations/all-caught-up.svg"
                    sourceSize: Qt.size(400, 408)
                }
                Item { width: 1; height: 19 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "You're all caught up!"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Clear filters"; font.family: theme.font; font.pixelSize: 16; color: theme.brand
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.clearFilters() }
                    Accessible.role: Accessible.Link; Accessible.name: "Clear filters"
                }
            }
        }
    }

    Component { id: chatRowComp; ChatRow { chat: parent && parent.row ? parent.row.chat : ({}); section: parent ? parent.section : null } }
    Component { id: channelRowComp; ChannelRow { channel: parent && parent.row ? parent.row.channel : ({}); team: parent && parent.row ? parent.row.team : ({}); section: parent ? parent.section : null; indent: 32 } }
    Component { id: teamComp; TeamRows { team: parent && parent.row ? parent.row.team : ({ name: "", channels: [] }) } }
    Component {
        id: sliceComp
        ListRow {
            label: parent.row.label; icon: parent.row.icon
            selected: parent.row.key === "mentions" ? root.mentionsOpen : parent.row.key === "drafts" ? root.draftsOpen : root.quickOpen === parent.row.key
            onClicked: parent.row.key === "mentions" ? root.openMentions() : parent.row.key === "drafts" ? root.openDrafts() : root.openQuick(parent.row.key)
        }
    }
    // See all your teams: Teams' Your teams and channels page (the row
    // shows as chosen while it's open).
    Component {
        id: seeAllComp
        Item {
            width: list.width; height: 28
            Rectangle {
                x: 16; width: parent.width - 32; height: 28; radius: theme.radius
                color: root.yourTeamsOpen ? theme.selected : "transparent"
            }
            Text {
                x: 31; y: 4; text: "See all your teams"; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openYourTeams() }
                Accessible.role: Accessible.Link; Accessible.name: "See all your teams"
            }
        }
    }
    Component {
        id: joinCommunitiesComp
        Item {
            width: list.width; height: 28
            Text {
                x: 31; y: 4; text: "Join communities"; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openCommunities() }
                Accessible.role: Accessible.Link; Accessible.name: "Join communities"
            }
        }
    }

    // ---- Section menu and dialogs ----
    property var menuSection: null
    function openSectionMenu(f, item, px, py) {
        if (!root.isUsers(f)) return
        menuSection = f
        const p = item.mapToItem(root, px, py)
        sectionMenu.x = Math.min(p.x, root.width - sectionMenu.implicitWidth - 8)
        sectionMenu.y = p.y
        sectionMenu.open()
    }
    MenuPopup {
        id: sectionMenu
        items: [{ label: "Rename section", icon: "rename-20" }, { label: "Remove section", icon: "delete-20" }]
        onPicked: i => { if (i === 0) sectionDialog.rename(root.menuSection); else sectionDialog.remove(root.menuSection) }
    }
    SectionDialog { id: sectionDialog; existing: root.folders.map(f => f.title) }

    // Test hooks: a chat row's menu, by chat id.
    property var rowsForTest: ({})
    function openRowMenuForTest(id) { const r = rowsForTest[id]; if (r) r.openMenu(r.width - 50, 30) }
    function closeRowMenuForTest() { for (const k in rowsForTest) if (rowsForTest[k] && rowsForTest[k].menuOpen) rowsForTest[k].closeMenu() }
    function sectionDialogForTest() { return sectionDialog }

    // Settings ▸ Chats and channels list (synced; measured on winpc
    // 2026-11-10): "Show message previews" makes chat rows 52 tall with a
    // 36 px picture at 16, 8, the name at 64 and the last message (12/16
    // #616161; "You: " for yours, "Name: " in groups) under it; "Show time
    // stamps" puts the last activity (12/16 #616161: the time today, else
    // M/d) 12 from the row's right, chats and channels alike; "Filters" off
    // hides the pills and the list starts under the header.
    readonly property var collab: { const s = backend.settingsJson ? JSON.parse(backend.settingsJson) : {}; return (s.props || {}).simpleCollabUserSettings || {} }
    readonly property bool previews: collab.hasUserEnabledMessagePreviews === true
    readonly property bool timestamps: collab.hasUserEnabledShowTimeStamps === true
    readonly property bool filtersShown: collab.hasUserDisabledShowingFilterAtTop !== true
    Connections { target: backend; function onSignedInChanged() { if (backend.signedIn) backend.loadSettings() } }
    function stamp(t) {
        if (!t) return ""
        const d = new Date(t), n = new Date()
        if (isNaN(d.getTime())) return ""
        if (d.toDateString() === n.toDateString()) return Qt.formatTime(d, "h:mm AP")
        return d.getFullYear() === n.getFullYear() ? Qt.formatDate(d, "M/d") : Qt.formatDate(d, "M/d/yy")
    }
    function previewOf(c) {
        if (!c.preview) return ""
        if (c.previewSystem) return c.preview
        const mine = !!c.sender && c.sender === backend.userName
        return mine ? "You: " + c.preview : (c.isGroup && c.sender ? c.sender + ": " + c.preview : c.preview)
    }

    // One chat in a section: picture with presence, name, unread dot.
    component ChatRow: Item {
        id: row
        property var chat
        property var section: null
        readonly property bool menuOpen: rowMenu.opened
        function closeMenu() { rowMenu.close() }
        Component.onCompleted: if (chat && chat.id) root.rowsForTest[chat.id] = row
        Component.onDestruction: if (chat && root.rowsForTest[chat.id] === row) delete root.rowsForTest[chat.id]
        readonly property bool selected: !root.draftsOpen && !root.mentionsOpen && !root.quickOpen && chat.id === root.currentId
        readonly property bool unread: chat.unread === true && !selected
        readonly property bool twoLine: root.previews
        width: list.width; height: twoLine ? 52 : 32
        Rectangle {
            x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
            color: row.selected ? theme.selected : (hover.hovered ? theme.rowHover : "transparent")
        }
        Avatar {
            visible: !row.chat.muted
            x: 32; y: row.twoLine ? 8 : 6
            size: row.twoLine ? 36 : 20; name: row.chat.name || ""
            photoId: row.chat.peerMri || ""
            group: row.chat.isGroup === true && !row.chat.peerMri
            meeting: root.isMeeting(row.chat)
            presence: row.chat.presence || ""
        }
        // Muted: Teams swaps the picture for a 20 px #E6E6E6 circle with the
        // regular AlertOff icon (16, NeutralForeground3) at 2, 2.
        Rectangle {
            visible: !!row.chat.muted
            x: 32; y: row.twoLine ? 8 : 6; width: row.twoLine ? 36 : 20; height: width; radius: width / 2
            color: theme.pick("#E6E6E6", "#3D3D3D")
            FluentIcon { anchors.centerIn: parent; name: "alert-off-20"; size: row.twoLine ? 20 : 16; color: theme.textSecondary }
        }
        // The last activity (Show time stamps), where ··· goes on hover.
        Text {
            id: rowStamp
            visible: root.timestamps && !row.showMore && text.length > 0
            anchors.right: parent.right; anchors.rightMargin: 28
            y: row.twoLine ? 10 : 8
            text: root.stamp(row.chat.time)
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: row.unread ? theme.text : theme.textSecondary
        }
        // The last message (Show message previews).
        Text {
            visible: row.twoLine
            x: 80; y: 26; width: parent.width - x - 28 - (liveIcon.visible || unreadDot.visible ? 22 : 0)
            text: root.previewOf(row.chat)
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.italic: !!row.chat.previewSystem
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: row.unread ? theme.text : theme.textSecondary
        }
        Text {
            x: row.twoLine ? 80 : 64; y: row.twoLine ? 8.7 : 6
            width: (row.showMore ? moreButton.x - 10 : rowStamp.visible ? rowStamp.x - 8 : liveIcon.visible ? liveIcon.x - 14 : unreadDot.visible ? unreadDot.x - 14 : parent.width - 40) - x
            text: row.chat.name || ""
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            // Teams: bold only when unread; the open chat is just darker.
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: row.selected || row.unread ? theme.text : theme.textSecondary
        }
        // A call going on in the chat (Teams: the regular sound-wave 14 in
        // NeutralForeground3 at 244, 9 in the 288-wide row).
        FluentIcon {
            id: liveIcon
            visible: !!row.chat.liveCall && !row.showMore
            x: parent.width - 60; y: row.twoLine ? 29 : 9
            name: "live-roster-14"; size: 14
            color: theme.textSecondary
        }
        // Unread: bold name plus a brand dot; muted chats keep the bold
        // name but not the dot (they don't count toward badges).
        Rectangle {
            id: unreadDot
            visible: row.unread && !row.chat.muted && !row.showMore
            width: 8; height: 8; radius: 4
            x: parent.width - 16 - 8 - 12
            y: row.twoLine ? 30 : (parent.height - height) / 2
            color: theme.brand
        }
        readonly property bool showMore: hover.hovered || rowMenu.opened
        Rectangle {
            id: moreButton
            visible: row.showMore
            x: parent.width - 16 - 32; y: row.twoLine ? 14.3 : 4.3; width: 24; height: 23.3; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: moreHover.hovered ? "more-horizontal-20-filled" : "more-horizontal-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.openMenu(parent.x, parent.y + parent.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More chat options"
        }
        HoverHandler { id: hover }
        TapHandler { onTapped: if (!moreHover.hovered) root.chatSelected(row.chat.id, row.chat.name) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => row.openMenu(ev.position.x, ev.position.y) }
        // Teams' chat menu (measured on winpc 2026-11-09), in Teams' order:
        // Open in new window | Mark as read/unread, Move to section ▸,
        // Remove from section, Mute, Notify when available, Manage apps,
        // Set workflows, Copy link | Remove chat history, Leave, Hide;
        // meeting chats end Hide | Report a concern.
        readonly property string holder: row.chat.id in root.sectioned ? root.sectioned[row.chat.id] : (root.inFavorites(row.chat) && root.favoritesFolder ? (root.favoritesFolder.id || "Favorites") : "")
        readonly property var members: { const m = backend.chatMemberCountsJson ? JSON.parse(backend.chatMemberCountsJson) : ({}); return m[row.chat.id] }
        // Leave: a member of a group chat of at least 3 (not a meeting chat
        // you created).
        readonly property bool canLeave: !!row.chat.isGroup && !row.chat.peerMri && (row.members || 0) >= 3 && !(root.isMeeting(row.chat) && row.chat.isCreator)
        function destinations() {
            const out = []
            const fav = root.favoritesFolder
            if (fav && fav.id && fav.id !== row.holder) out.push({ id: fav.id, label: "Favorites" })
            for (const s of root.userSections) if (s.id !== row.holder) out.push({ id: s.id, label: s.title })
            return out
        }
        function openMenu(px, py) {
            if (row.chat.isGroup && !row.chat.peerMri && row.members === undefined) backend.chatMemberCountsLoad(row.chat.id)
            const dest = destinations()
            const sub = dest.map(d => ({ label: d.label, to: d.id }))
            if (sub.length) sub.push({ separator: true })
            sub.push({ label: "New section", icon: "folder-add-20", newSection: true })
            const oneOnOne = !!row.chat.peerMri && !row.chat.isSelf
            const tagged = oneOnOne && root.notifyTagged[row.chat.peerMri.toLowerCase()]
            rowMenu.items = [
                { key: "window", label: "Open in new window", icon: "open-window-20" },
                { separator: true },
                { key: row.unread ? "read" : "unread", label: row.unread ? "Mark as read" : "Mark as unread", icon: row.unread ? "glasses-20" : "glasses-off-20" },
                { key: "move", label: "Move to section", icon: "star-20", submenu: sub },
                row.holder ? { key: "removeFrom", label: "Remove from section", icon: "star-off-20" } : null,
                row.chat.isSelf ? null : { key: row.chat.muted ? "unmute" : "mute", label: row.chat.muted ? "Unmute" : "Mute", icon: row.chat.muted ? "alert-20" : "alert-off-20" },
                oneOnOne ? { key: tagged ? "notifyOff" : "notifyOn", label: tagged ? "Turn off notifications" : "Notify when available", icon: "notify-available-20" } : null,
                row.chat.isSelf ? null : { key: "apps", label: "Manage apps", icon: "manage-apps-20" },
                row.chat.isSelf ? null : { key: "workflows", label: "Set workflows", icon: "workflows-20" },
                { key: "link", label: "Copy link", icon: "link-20" },
                { separator: true },
                !row.chat.isSelf && !root.isMeeting(row.chat) ? { key: "removeHistory", label: "Remove chat history", icon: "delete-20" } : null,
                row.canLeave ? { key: "leave", label: "Leave", icon: "door-arrow-left-20" } : null,
                { key: row.chat.hidden ? "unhide" : "hide", label: row.chat.hidden ? "Unhide" : "Hide", icon: row.chat.hidden ? "eye-20" : "eye-off-20" },
                root.isMeeting(row.chat) ? { separator: true } : null,
                root.isMeeting(row.chat) ? { key: "report", label: "Report a concern", icon: "shield-error-20" } : null
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
                else if (k === "removeFrom") backend.folderAction("remove", JSON.stringify({ item: row.chat.id, from: row.holder }))
                else if (k === "hide" || k === "unhide") backend.setChatHidden(row.chat.id, k === "hide")
                else if (k === "leave") leaveAsk.open()
                else if (k === "window") root.openChatWindow(row.chat.id, row.chat.name, row.chat.peerMri || "", row.chat.presence || "")
                else if (k === "apps") root.manageChatApps(row.chat.id, row.chat.name)
                else if (k === "workflows") root.chatWorkflows(row.chat.id, row.chat.name)
                else if (k === "removeHistory") removeHistoryAsk.open()
                else if (k === "report") root.reportMeetingChat(row.chat.id)
                else if (k === "notifyOn") backend.channelAction("notify-on", "", "", JSON.stringify({ mri: row.chat.peerMri }))
                else if (k === "notifyOff") { const t = root.notifyTagged[row.chat.peerMri.toLowerCase()]; backend.channelAction("notify-off", "", "", JSON.stringify({ id: t.id, mri: row.chat.peerMri, email: t.email })) }
            }
            onSubPicked: (i, j) => {
                const s = items[i].submenu[j]
                if (s.newSection) sectionDialog.create(row.chat.id, row.holder)
                else if (s.to) backend.folderAction("move", JSON.stringify({ item: row.chat.id, to: s.to, from: row.holder }))
            }
        }
        function closeMenuForTest() { rowMenu.close() }
        function removeHistoryForTest() { return removeHistoryAsk }
        // Teams' "Remove chat history?" (600 wide).
        ConfirmDialog {
            id: removeHistoryAsk
            width: 600
            title: "Remove chat history?"
            body: "This will remove the chat from your list and search. It affects you only."
            confirmText: "Remove"
            onConfirmed: backend.channelAction("remove-chat-history", "", row.chat.id, "")
        }
        ConfirmDialog {
            id: leaveAsk
            title: "Leave this chat?"
            body: "Are you sure you want to leave " + (row.chat.name || "") + "?"
            confirmText: "Leave"
            onConfirmed: backend.leaveChat(row.chat.id)
        }
        Accessible.role: Accessible.Button
        Accessible.name: (row.chat.name || "") + (row.unread ? ", unread" : "") + (row.chat.muted ? ", muted" : "") + (row.chat.liveCall ? ", call in progress" : "")
    }

    // A meeting chat's Report a concern: Teams' "Report a security concern"
    // for the chat's meeting (its title, start and organizer) with the
    // chat's members to name; sent, "Your report was sent".
    function reportMeetingChat(chatId) {
        chatReport.chatThread = chatId
        chatReport.chatIcal = ""
        chatReport.meeting = { title: (chatById(chatId) || {}).name || "", start: "", organizer: "" }
        chatReport.people = []
        chatReport.open()
        backend.channelAction("meeting-chat-report-info", "", chatId, "")
    }
    function chatReportForTest() { return chatReport }
    MeetingReportDialog {
        id: chatReport
        person: null
        onReported: backend.toastJson = JSON.stringify({ id: Date.now(), text: "Your report was sent", intent: "success" })
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "meeting-chat-report-info" || !r.ok || !r.data || !chatReport.opened) return
            const d = r.data
            chatReport.chatIcal = d.ical || ""
            chatReport.meeting = { title: d.title || chatReport.meeting.title, start: d.start ? Qt.formatDateTime(new Date(d.start), "MMM d, h:mm AP") : "", organizer: d.organizer || "" }
            chatReport.people = d.people || []
        }
    }

    // The channel menu, shared by every channel row.
    signal openChannelWindow(string channelId)
    signal manageChannel(string channelId, string channelName)
    signal channelWorkflows(string channelId)
    ChannelMenu {
        id: channelMenu
        onOpenInNewWindow: root.openChannelWindow(channel.id)
        onManageChannel: root.manageChannel(channel.id, channel.name)
        onWorkflows: root.channelWorkflows(channel.id)
    }
    function openChannelMenu(channel, team, anchor, px, py) {
        channelMenu.channel = channel
        channelMenu.teamId = team ? team.id : ""
        channelMenu.teamName = team ? team.name : ""
        channelMenu.postsAtBottom = !backend.channelPostsAtTop
        channelMenu.postsOrder = channel.id === root.currentId
        channelMenu.show(anchor, px, py)
    }
    function channelMenuForTest() { return channelMenu }

    // The team menu, shared by every team row.
    signal manageTeam(string teamId)
    signal manageTags(string teamId)
    TeamMenu {
        id: teamMenu
        onManageTeam: id => root.manageTeam(id)
        onManageTags: id => root.manageTags(id)
        // Teams opens the new channel.
        onChannelCreated: (id, name) => root.chatSelected(id, name)
    }
    function openTeamMenu(team, anchor, px, py) {
        // The full team (with its hidden and deleted channels).
        teamMenu.team = root.teams.find(t => t.id === team.id) || team
        teamMenu.show(anchor, px, py)
    }
    function teamMenuForTest() { return teamMenu }

    // A channel row: in a team (indented under it) or in a section.
    component ChannelRow: Item {
        id: chRow
        property var channel
        property var team
        property var section: null
        property int indent: 64
        readonly property bool selected: channel.id === root.currentId
        readonly property bool unread: channel.unread === true && !selected
        width: list.width; height: 28
        Rectangle {
            x: 16; width: parent.width - 32; height: 28; radius: theme.radius
            color: chRow.selected ? theme.selected : (chHover.hovered ? theme.rowHover : "transparent")
        }
        Text {
            id: chName
            x: chRow.indent; y: 4
            width: Math.min(implicitWidth, parent.width - x - 24 - (newBadge.visible ? newBadge.width + 8 : 0))
            text: chRow.section ? chRow.channel.name + " (" + chRow.team.name + ")" : chRow.channel.name
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            font.weight: chRow.unread ? Font.DemiBold : Font.Normal
            // A hidden channel stays listed, in italics, while it's open.
            font.italic: chRow.channel.shown === false
            color: chRow.selected || chRow.unread ? theme.text : theme.textSecondary
        }
        NewBadge { id: newBadge; visible: !!chRow.channel.new; x: chName.x + chName.width + 8; anchors.verticalCenter: parent.verticalCenter }
        Text {
            visible: root.timestamps && !chHover.hovered && !chRow.menuOpen && text.length > 0
            anchors.right: parent.right; anchors.rightMargin: 28; anchors.verticalCenter: parent.verticalCenter
            text: root.stamp(chRow.channel.last_active)
            font.family: theme.font; font.pixelSize: 12
            font.weight: chRow.unread ? Font.DemiBold : Font.Normal
            color: chRow.unread ? theme.text : theme.textSecondary
        }
        HoverHandler { id: chHover }
        TapHandler { onTapped: root.chatSelected(chRow.channel.id, chRow.channel.name) }
        // Its menu: ··· on hover (and while open), or a right-click (Teams'
        // channel row menu, as in the channel's header).
        readonly property bool menuOpen: channelMenu.menu.opened && channelMenu.channel.id === chRow.channel.id
        Rectangle {
            id: chMore
            visible: chHover.hovered || chRow.menuOpen
            x: parent.width - 16 - 8 - 24; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: theme.radius
            color: chMoreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: chRow.menuOpen ? theme.brand : theme.textStrong }
            HoverHandler { id: chMoreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openChannelMenu(chRow.channel, chRow.team, chMore, 0, chMore.height + 4) }
            Accessible.role: Accessible.Button
            Accessible.name: "More options for " + chRow.channel.name
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: point => root.openChannelMenu(chRow.channel, chRow.team, chRow, point.position.x, point.position.y)
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Channel " + chRow.channel.name + " in " + chRow.team.name + (chRow.unread ? ", unread" : "")
    }

    // Teams' "New" badge: brand pill, 10/14 semibold.
    component NewBadge: Rectangle {
        width: newText.implicitWidth + 12; height: 18; radius: 9
        color: theme.brandFill
        Text { id: newText; anchors.centerIn: parent; text: "New"; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: "white" }
    }

    // A team and its shown channels.
    component TeamRows: Column {
        id: teamRows
        property var team
        property bool open: teamRows.team.expanded !== false
        // Bold only while collapsed (Teams: not an expanded branch).
        readonly property bool unread: !open && teamRows.team.channels.some(c => c.unread)
        width: list.width
        Item {
            width: list.width; height: 32
            Rectangle {
                x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                color: teamHover.hovered ? theme.rowHover : "transparent"
            }
            FluentIcon {
                x: 18; y: 10
                name: teamRows.open ? "chevron-down-12" : "chevron-right-12"; size: 12
                color: theme.textSecondary
            }
            Avatar {
                x: 32; y: 6
                size: 20; square: true
                name: teamRows.team.name
                initialsText: teamRows.team.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                photoId: "team:" + teamRows.team.id
            }
            Text {
                id: teamName
                x: 64; y: 6
                width: Math.min(implicitWidth, parent.width - 64 - 24 - (teamNew.visible ? teamNew.width + 8 : 0))
                text: teamRows.team.name
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: theme.base
                font.weight: teamRows.unread ? Font.DemiBold : Font.Normal
                color: teamRows.unread ? theme.text : theme.textSecondary
            }
            NewBadge { id: teamNew; visible: !!teamRows.team.new; x: teamName.x + teamName.width + 8; anchors.verticalCenter: parent.verticalCenter }
            HoverHandler { id: teamHover }
            TapHandler { onTapped: teamRows.open = !teamRows.open }
            // Its menu: "More team options" (24 x 23.3, 8 from the row's
            // end) on hover, or a right-click (Teams' team menu).
            readonly property bool menuOpen: teamMenu.menu.opened && teamMenu.team.id === teamRows.team.id
            Rectangle {
                id: teamMore
                visible: teamHover.hovered || parent.menuOpen
                x: parent.width - 16 - 8 - 24; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 23.3; radius: theme.radius
                color: teamMoreHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: teamMore.parent.menuOpen ? theme.brand : theme.textStrong }
                HoverHandler { id: teamMoreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openTeamMenu(teamRows.team, teamMore, 0, -teamMenu.menu.implicitHeight - 3) }
                Accessible.role: Accessible.Button
                Accessible.name: "More team options"
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => root.openTeamMenu(teamRows.team, parent, point.position.x, point.position.y)
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Team " + teamRows.team.name + (teamRows.open ? ", expanded" : ", collapsed")
        }
        Repeater {
            model: teamRows.open ? teamRows.team.channels : []
            ChannelRow { required property var modelData; channel: modelData; team: teamRows.team }
        }
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

    // Section header: 12 px chevron and label, 28 px tall; your own
    // sections have Teams' ··· "More section options" on hover.
    component SectionHeader: Item {
        id: sh
        property string label
        property bool open: true
        property bool userSection: false
        signal toggled()
        signal menuRequested(real px, real py)
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
        Rectangle {
            visible: sh.userSection && shHover.hovered
            x: parent.width - 16 - 32; y: 2; width: 24; height: 23.3; radius: 4
            color: smHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: smHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sh.menuRequested(parent.x, parent.y + parent.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More section options"
        }
        HoverHandler { id: shHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (!smHover.hovered) sh.toggled() }
        TapHandler { acceptedButtons: Qt.RightButton; enabled: sh.userSection; onTapped: ev => sh.menuRequested(ev.position.x, ev.position.y) }
        Accessible.role: Accessible.Button
        Accessible.name: sh.label + (sh.open ? ", expanded" : ", collapsed")
    }
}
