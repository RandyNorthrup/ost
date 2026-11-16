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
    // Keyboard: Up / Down move through the chats and channels shown (a
    // focus ring on the row). Teams opens each as you arrive; with Settings
    // ▸ General's "Use Enter or Spacebar to show content" on, Enter or Space
    // opens it.
    property bool enterToOpen: false
    property string focusId: ""
    /// The ring shows while you use the keyboard (not after a click).
    property bool keyboardNav: false
    readonly property var navItems: {
        const out = []
        for (const sec of root.sections) {
            if (!sec.folder.expanded) continue
            for (const r of sec.rows) {
                if (r.type === "chat" && r.chat) out.push({ id: r.chat.id, name: r.chat.name })
                else if (r.type === "channel" && r.channel) out.push({ id: r.channel.id, name: r.channel.name })
            }
        }
        return out
    }
    function moveFocus(step) {
        const items = navItems
        if (items.length === 0) return
        keyboardNav = true
        let i = items.findIndex(x => x.id === (focusId || currentId))
        i = i < 0 ? (step > 0 ? 0 : items.length - 1) : Math.max(0, Math.min(items.length - 1, i + step))
        focusId = items[i].id
        if (!enterToOpen) chatSelected(items[i].id, items[i].name)
        const row = rowsForTest[focusId]
        if (row) {
            const y = row.mapToItem(listCol, 0, 0).y
            if (y < list.contentY) list.contentY = y
            else if (y + row.height > list.contentY + list.height) list.contentY = y + row.height - list.height
        }
    }
    function openFocused() {
        const it = navItems.find(x => x.id === focusId)
        if (it) chatSelected(it.id, it.name)
    }
    Keys.onUpPressed: moveFocus(-1)
    Keys.onDownPressed: moveFocus(1)
    Keys.onReturnPressed: openFocused()
    Keys.onEnterPressed: openFocused()
    Keys.onSpacePressed: openFocused()
    onCurrentIdChanged: if (!activeFocus) focusId = ""
    // A click on a row hands the list the keyboard (Up / Down from there).
    onChatSelected: (id, name) => { focusId = id; if (!activeFocus) forceActiveFocus() }
    onActiveFocusChanged: if (!activeFocus) keyboardNav = false
    signal newChat()

    // ---- Reordering (spec §5.3, measured on winpc 2026-11-16) ----
    // Chats and channels in Favorites and your own sections (Custom order),
    // and teams in Teams and channels, move by drag and drop: the row
    // follows the pointer (white at 0.75, a 0.67 px black edge, radius 4,
    // shadow 16, the grabbing cursor), its own place shows at half opacity,
    // and a 2 px NeutralForeground1 line (inset 2.875) marks where it will
    // go: the bottom of the row it would follow, or the top of the first.
    // Teams fold up while a team moves. Esc cancels. Dropped, the order is
    // saved where Teams keeps it: a section's ReorderItems, the teamsOrder
    // user property. Channels move only into sections, not within a team.
    // Settings ▸ Accessibility ▸ "Turn on single pointer controls" adds
    // Start reordering to the item menus: Move Up and Move Down on the row
    // (24 x 23.3, 56 and 32 from its end; Move Up takes the focus), each
    // press saving the order, until you click elsewhere.
    property bool singlePointReordering: false
    function sectionReorderable(f) {
        return !!f && !!f.id && (f.kind === "Favorites" || isUsers(f)) && (f.sort || "UserDefinedCustomOrder") === "UserDefinedCustomOrder" && !filtered
    }
    readonly property bool teamsReorderable: !filtered && root.teams.length > 1
    /// Draggable rows by "group|key" (group: a section id, or "teams").
    property var dragRows: ({})
    function registerDrag(group, key, item) { if (group && key) dragRows[group + "|" + key] = item }
    function unregisterDrag(group, key, item) { if (dragRows[group + "|" + key] === item) delete dragRows[group + "|" + key] }
    function groupOrder(group) {
        if (group === "teams") return root.teams.map(t => t.thread_id)
        const f = folders.find(f => f.id === group)
        return f ? f.items.slice() : []
    }
    // The group's rows on show, in order: [{key, y, h}] in the list's
    // coordinates.
    function shownRows(group, except) {
        const out = []
        for (const k of groupOrder(group)) {
            if (k === except) continue
            const it = dragRows[group + "|" + k]
            if (!it || !it.visible) continue
            const p = it.mapToItem(listCol, 0, 0)
            out.push({ key: k, y: p.y, h: it.dragHeight })
        }
        return out
    }
    /// The drag: {group, key, name, kind, photoId, group chat, h, grabY}.
    property var drag: null
    property bool dragCancelled: false
    property real dragX: 0
    property real dragY: 0
    /// Where it would go: {order, lineY} (null: back where it was).
    property var dropAt: null
    function dragStart(group, key, info, item, press) {
        stopReorder()
        dragCancelled = false
        dropAt = null
        drag = Object.assign({ group: group, key: key, h: item.dragHeight, grabY: press.y }, info)
    }
    function dragMove(scene) {
        if (!drag) return
        const p = root.mapFromItem(null, scene.x, scene.y)
        dragX = p.x; dragY = p.y
        // Near the list's ends it scrolls.
        const ly = list.mapFromItem(null, scene.x, scene.y).y
        if (ly < 24) list.contentY = Math.max(0, list.contentY - 12)
        else if (ly > list.height - 24) list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + 12)
        if (dragCancelled) return
        const y = listCol.mapFromItem(null, scene.x, scene.y).y
        const rows = shownRows(drag.group, drag.key)
        if (rows.length === 0) { dropAt = null; return }
        const idx = rows.filter(r => r.y + r.h / 2 < y).length
        const order = groupOrder(drag.group).filter(k => k !== drag.key)
        const at = idx < rows.length ? order.indexOf(rows[idx].key) : order.indexOf(rows[rows.length - 1].key) + 1
        order.splice(at, 0, drag.key)
        const same = JSON.stringify(order) === JSON.stringify(groupOrder(drag.group))
        dropAt = same ? null : { order: order, lineY: idx === 0 ? rows[0].y : rows[idx - 1].y + rows[idx - 1].h - 2 }
    }
    function dragEnd() {
        if (drag && !dragCancelled && dropAt) commitOrder(drag.group, dropAt.order)
        drag = null; dropAt = null; dragCancelled = false
    }
    function commitOrder(group, order) {
        console.warn("REORDER", group, JSON.stringify(order))
        if (group === "teams") backend.reorderTeams(JSON.stringify(order))
        else backend.folderAction("reorder", JSON.stringify({ id: group, order: order }))
    }
    Shortcut {
        sequence: "Esc"
        enabled: !!root.drag && !root.dragCancelled
        onActivated: { root.dragCancelled = true; root.dropAt = null }
    }
    // Start reordering.
    property string reorderGroup: ""
    property string reorderKey: ""
    function startReorder(group, key) { reorderGroup = group; reorderKey = key }
    function stopReorder() { reorderGroup = ""; reorderKey = "" }
    function reorderStep(d) {
        const o = groupOrder(reorderGroup)
        const i = o.indexOf(reorderKey), j = i + d
        if (i < 0 || j < 0 || j >= o.length) return
        o.splice(i, 1); o.splice(j, 0, reorderKey)
        commitOrder(reorderGroup, o)
    }
    function reordering(group, key) { return reorderGroup === group && reorderKey === key && !!key }
    // Teams fold up while one moves (dragged, or Start reordering).
    readonly property bool teamsFolded: (!!drag && drag.group === "teams") || reorderGroup === "teams"
    // A click elsewhere in the list ends Start reordering (the window's
    // other clicks move the focus off its buttons, which ends it too).
    TapHandler {
        enabled: root.reorderKey !== ""
        acceptedButtons: Qt.AllButtons
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        gesturePolicy: TapHandler.DragThreshold
        onTapped: reorderFocusCheck.restart()
    }
    property bool reorderButtonFocused: false
    Timer { id: reorderFocusCheck; interval: 400; onTriggered: if (!root.reorderButtonFocused && root.reorderKey) root.stopReorder() }
    // The row following the pointer.
    Item {
        id: dragOverlay
        visible: !!root.drag && !root.dragCancelled
        z: 50
        x: 16; y: root.drag ? root.dragY - root.drag.grabY : 0
        width: list.width - 32; height: root.drag ? root.drag.h : 32
        FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface; opacity: 0.75 }
        Rectangle { anchors.fill: parent; radius: 4; color: "transparent"; border.width: 0.67; border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF") }
        FluentIcon {
            visible: !!root.drag && root.drag.kind === "team"
            x: 2.7; y: (parent.height - 12) / 2; name: "chevron-right-12"; size: 12; color: theme.textSecondary
        }
        Avatar {
            visible: !!root.drag && root.drag.kind !== "channel"
            x: 16.7; y: (parent.height - 20) / 2; size: 20
            square: !!root.drag && root.drag.kind === "team"
            name: root.drag ? root.drag.name : ""
            initialsText: root.drag && root.drag.kind === "team" ? root.drag.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
            photoId: root.drag ? root.drag.photoId || "" : ""
            group: !!root.drag && !!root.drag.groupChat
        }
        Text {
            x: root.drag && root.drag.kind === "channel" ? 16.7 : 48.7
            y: (parent.height - height) / 2
            width: parent.width - x - 48
            text: root.drag ? root.drag.name : ""
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textStrong
        }
        FluentIcon { x: parent.width - 32; y: (parent.height - 20) / 2; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
    }
    function scrollIntoViewForTest(item) { const y = item.mapToItem(listCol, 0, 0).y; list.contentY = Math.max(0, Math.min(y - 120, list.contentHeight - list.height)) }
    function dragStateForTest() { return { drag: root.drag, dropAt: root.dropAt, cancelled: root.dragCancelled } }
    signal openDrafts()
    /// Mark all as read for Teams' app type: "unified", "chat", "channel",
    /// "split_channel" or "engage_community".
    signal markAllRead(string appType)
    /// The ··· menu's Customize view (Teams opens Settings).
    signal customizeView()
    /// Teams' new chat form is open: its "New message" row leads the Chats
    /// section, selected, and nothing else is.
    property bool composing: false
    signal openComposing()
    /// Copilot (the row at the list's top) is open, and opening it.
    property bool copilotOpen: false
    signal openCopilot()
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
            } else if ((r.op === "notify-on" || r.op === "notify-off") && !r.ok) {
                backend.toast("Something went wrong on our end. Please try again.", "error")
            }
        }
    }
    /// See all your teams.
    property bool yourTeamsOpen: false
    signal openYourTeams()
    color: theme.pane
    width: listWidth
    // ---- Width (Teams' MID_NAV slot, module 708731) ----
    // Teams' default by window width: 280 from 640, 320 from 1280, 360 from
    // 1500. Dragging the divider (or ArrowLeft / ArrowRight on it, 20 px a
    // step) sets a width kept as a share of the window (vw), clamped to
    // 280-400 and to the window less the app bar (68) and the main area's
    // minimum (320); the CSS clamp lets the minimum win. Double-click puts
    // the default back. Teams keeps the dragged width on the device
    // (localStorage teams-layout-slot-size-persistence, per window type);
    // OST in its device settings ("listWidthVw").
    property real windowWidth: 1280
    readonly property real defaultWidth: windowWidth >= 1500 ? 360 : windowWidth >= 1280 ? 320 : 280
    /// The dragged width as vw, or -1 (never dragged).
    property real widthVw: { const v = parseFloat(backend.setting("listWidthVw")); return isNaN(v) ? -1 : v }
    readonly property real maxWidth: Math.min(400, windowWidth - theme.railWidth - 320)
    function clampWidth(px) { return Math.max(280, Math.min(px, maxWidth)) }
    readonly property real listWidth: clampWidth(widthVw >= 0 ? widthVw * windowWidth / 100 : defaultWidth)
    function setWidthPx(px) {
        widthVw = clampWidth(px) / windowWidth * 100
        widthSave.restart()
    }
    function resetWidth() { widthVw = defaultWidth / windowWidth * 100; widthSave.restart() }
    // Teams saves the size a moment after the drag ends.
    Timer { id: widthSave; interval: 500; onTriggered: backend.setSetting("listWidthVw", String(Math.round(root.widthVw * 1e5) / 1e5)) }

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
        // Teams leaves out lobby and breakout room chats, chats you left,
        // empty one-on-ones and chats you hid, unless open (api::chat's
        // unlisted); chats nothing has been said in are listed.
        if ((c.unlisted || c.hidden) && c.id !== root.currentId) return false
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
        : teams.map(t => ({ id: t.id, thread_id: t.thread_id, name: t.name, new: t.new, expanded: t.expanded !== false,
                            channels: (t.channels || []).filter(ch => channelShown(t, ch)) }))
               .filter(t => t.channels.length > 0 && (!unreadOn || t.channels.some(c => c.unread)))
    function folderInPane(f) {
        if (pane === "chats") return f.kind !== "TeamsAndChannels" && f.kind !== "EngageCommunities"
        if (pane === "teams") return f.kind === "QuickViews" || f.kind === "TeamsAndChannels" || f.kind === "EngageCommunities"
        return true
    }
    readonly property var sections: folders.filter(f => folderInPane(f)).map(f => {
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
            // Teams' new chat form: "New message" (compose icon) leads the
            // section, selected, while the form is open.
            if (root.composing && !filtered) rows.unshift({ type: "newMessage" })
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

    // ---- ··· More list options ----
    // Teams' mode: the unified list, the Chat app's or the Teams app's
    // (split view).
    readonly property string appMode: pane === "chats" ? "chat" : pane === "teams" ? "channel" : "unified"
    readonly property var markAllSubmenu: appMode === "unified"
        ? [{ label: "All", appType: "unified" }, { label: "All chats", appType: "chat" }, { label: "All channels", appType: "channel" }]
            .concat(hasCommunities ? [{ label: "All communities", appType: "engage_community" }] : [])
        : appMode === "channel" && hasCommunities
        ? [{ label: "All", appType: "split_channel" }, { label: "All channels", appType: "channel" }, { label: "All communities", appType: "engage_community" }]
        : []
    readonly property var listMenuItems: {
        const mark = { key: "markAll", label: "Mark all as read", icon: "glasses-20", keys: "Shift+Esc" }
        if (markAllSubmenu.length) { mark.split = true; mark.submenu = markAllSubmenu; mark.splitLabel = "Mark all as read options" }
        const out = [mark,
            { key: "collapseAll", label: "Collapse all sections", icon: "arrow-collapse-all-20", keys: "Alt+Q" },
            { separator: true },
            { key: "customize", label: "Customize view", icon: "settings-20" }]
        if (appMode !== "chat") {
            out.push({ separator: true }, { key: "yourTeams", label: "Your teams and channels", icon: "people-team-20" })
            if (hasCommunities) out.push({ key: "yourCommunities", label: "Your communities", icon: "people-community-20" })
        }
        return out
    }
    /// Teams' app type for Mark all as read here (the menu's main part and
    /// Shift+Esc): the whole list, or the split view's app.
    readonly property string markAllAppType: appMode === "channel" ? "split_channel" : appMode
    function listMenuPicked(key) {
        if (key === "markAll") root.markAllRead(root.markAllAppType)
        else if (key === "collapseAll") root.collapseAll()
        else if (key === "customize") root.customizeView()
        else if (key === "yourTeams") root.openYourTeams()
        else if (key === "yourCommunities") root.openCommunities()
    }
    /// Collapse all sections (Alt+Q): every folder of this app, as Teams'
    /// setConversationFoldersExpandedState.
    function collapseAll() { backend.folderAction("collapseAll", "{}") }
    function openListMenuForTest() { listMenu.open() }
    function openMarkAllSubmenuForTest() { listMenu.openSubmenuForTest(0) }
    function listMenuForTest() { return listMenu }
    /// Shift+Esc's confirmation: what it marks, by the selected filter
    /// (Teams' tR: the Chats pill or the Chat app "chats", the Channels
    /// pill or the Teams app "channels", otherwise all three).
    readonly property string markAllEntities: category === "chats" || appMode === "chat" ? "chats"
        : category === "channels" || appMode === "channel" ? "channels" : "chats, channels, and communities"

    // ---- The divider (Teams' resize handle, role slider "Resize left
    // panel", 280-400) ----
    Item {
        id: resizeHandle
        x: root.width - 4; width: 4; height: root.height
        z: 10
        activeFocusOnTab: false
        HoverHandler { cursorShape: Qt.SplitHCursor }
        property real startWidth: 0
        DragHandler {
            id: resizeDrag
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            cursorShape: Qt.SplitHCursor
            onActiveChanged: if (active) resizeHandle.startWidth = root.width
            onTranslationChanged: if (active) root.setWidthPx(resizeHandle.startWidth + translation.x)
        }
        TapHandler {
            onDoubleTapped: root.resetWidth()
            onTapped: resizeHandle.forceActiveFocus()
        }
        Keys.onLeftPressed: root.setWidthPx(root.width - 20)
        Keys.onRightPressed: root.setWidthPx(root.width + 20)
        Rectangle { anchors.fill: parent; visible: resizeHandle.activeFocus || resizeDrag.active; color: theme.brand; opacity: 0.6 }
        Accessible.role: Accessible.Slider
        Accessible.name: "Resize left panel"
        Accessible.description: Math.round(root.width) + "px"
    }

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
        FluentIcon { id: hbIcon; anchors.centerIn: parent; size: hb.iconSize; color: theme.onFill(hb, hb.iconColor) }
    }

    // Header: "Chat", then more / filter / new message (with its menu).
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            x: 32; y: 19
            text: root.pane === "teams" ? "Teams" : "Chat"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        HeaderButton {
            id: moreList
            x: root.width - 126; y: 15; icon: "more-20"; Accessible.name: "More list options"
            onClicked: listMenu.open()
            // Teams' ··· More list options ($L, measured on Teams web
            // 2026-11-16): below-start, 248 wide; Mark all as read (a split
            // item in the unified list: All / All chats / All channels /
            // All communities), Collapse all sections | Customize view |
            // Your teams and channels, Your communities. The Chat-only list
            // has no split and stops after Customize view.
            MenuPopup {
                id: listMenu
                y: parent.height + 4
                submenuMinWidth: 0
                // Teams' menu measures 248 (its Segoe text is a little wider).
                minRowWidth: 240
                items: root.listMenuItems
                onPicked: i => root.listMenuPicked(root.listMenuItems[i].key)
                onSubPicked: (i, j) => root.markAllRead(root.listMenuItems[i].submenu[j].appType)
            }
        }
        HeaderButton {
            x: root.width - 94; y: 15; icon: "search-20"; Accessible.name: "Show filter text box"
            onClicked: { root.filtering = !root.filtering; if (root.filtering) filterField.forceActiveFocus(); else { filterField.text = "" } }
        }
        HeaderButton {
            x: root.width - 62; y: 14; width: 26; icon: "compose-20"
            Accessible.name: "New message"
            onClicked: root.newChat()
        }
        HeaderButton {
            x: root.width - 36; y: 14; width: 20; icon: "chevron-down-12"; iconSize: 12; Accessible.name: "New items"
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
    // Separate view: Chat has Unread / Chats / Meeting chats, the Teams app
    // Unread / Channels / Communities (Teams, measured).
    readonly property var pillDefs: [
        { key: "unread", label: "Unread", keys: "Ctrl+Alt+U" },
        { key: "channels", label: "Channels", keys: "Ctrl+Alt+A" },
        { key: "chats", label: "Chats", keys: "Ctrl+Alt+C" },
        { key: "meetings", label: "Meeting chats", keys: "Ctrl+Alt+B" }
    ].concat(hasCommunities ? [{ key: "communities", label: "Communities", keys: "" }] : [])
     .filter(p => pane === "chats" ? ["unread", "chats", "meetings"].indexOf(p.key) >= 0
                : pane === "teams" ? ["unread", "channels", "communities"].indexOf(p.key) >= 0 : true)
    onPaneChanged: { category = ""; unreadOn = false }
    function pillOn(k) { return k === "unread" ? unreadOn : category === k }
    FontMetrics { id: pillMetrics; font.family: theme.font; font.pixelSize: 12 }
    function pillWidth(label) { return Math.ceil(pillMetrics.advanceWidth(label)) + 18 }
    // Pills that fit in the first row (the list's width less 70); the chosen ones first in
    // priority, the rest in order.
    readonly property var pillRows: {
        const room = root.width - 70
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
            color: theme.onFill(pill, pill.on ? "white" : theme.textStrong)
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
        x: root.width - 38; y: 65; width: 24; height: 24; radius: 4
        icon: root.moreFiltersOpen ? "chevron-up-16" : "chevron-down-16"; iconSize: 16
        iconColor: root.moreFiltersOpen ? theme.brand : theme.textStrong
        onClicked: root.moreFiltersOpen = !root.moreFiltersOpen
        ToolTip.visible: false
        Accessible.name: root.moreFiltersOpen ? "Fewer filters" : "More filters"
    }
    // "Show filter text box": filter the list by name.
    Rectangle {
        visible: root.filtering
        x: 32; y: 65; width: root.width - 48; height: 32; radius: theme.radius
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
            id: hcFill1
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: theme.radius
            color: clh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.onFill(hcFill1, theme.textStrong) }
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
            // Copilot: a single row above Quick views (Teams'
            // list-item-metaos-copilot, measured 32 tall at the list's top),
            // which opens Copilot beside the list as Teams hosts it.
            ListRow {
                visible: !root.filtered && root.pane !== "teams"
                height: visible ? 32 : 0
                label: "Copilot"; icon: "mo-copilot"
                selected: root.copilotOpen
                onClicked: root.openCopilot()
            }
            Item { width: 1; height: !root.filtered && root.pane !== "teams" ? 4 : 0 }
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
                                : modelData.type === "newMessage" ? newMessageComp
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
                    x: (list.width - width) / 2; width: 200; height: 204
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
        // Where the dragged row would go (Teams' 2 px line).
        Rectangle {
            id: dropLine
            visible: !!root.dropAt
            z: 5
            x: 16 + 2.875; width: list.width - 32 - 5.75; height: 2
            y: root.dropAt ? root.dropAt.lineY : 0
            color: theme.text
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
    Component {
        id: newMessageComp
        ListRow { label: "New message"; icon: "compose-20"; selected: root.composing; onClicked: root.openComposing() }
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
    /// Teams' "Separate" view (Settings ▸ Chats and channels): the list is
    /// Chat's chats ("chats") or the Teams app's teams and channels
    /// ("teams"); "combined" holds both. Its own preview setting; time
    /// stamps always shown (Teams greys the switch on).
    property string pane: "combined"
    readonly property bool split: pane !== "combined"
    readonly property bool previews: split ? collab.hasUserEnabledMessagePreviewsForSplitApp !== false : collab.hasUserEnabledMessagePreviews === true
    readonly property bool timestamps: split || collab.hasUserEnabledShowTimeStamps === true
    readonly property bool filtersShown: collab.hasUserDisabledShowingFilterAtTop !== true
    Connections { target: backend; function onSignedInChanged() { if (backend.signedIn) backend.loadSettings() } }
    function stamp(t) {
        if (!t) return ""
        const d = new Date(t), n = new Date()
        if (isNaN(d.getTime())) return ""
        if (d.toDateString() === n.toDateString()) return theme.time(d)
        return d.getFullYear() === n.getFullYear() ? theme.dateNoYear(d) : theme.dateShortYear(d)
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
        Component.onCompleted: { if (chat && chat.id) root.rowsForTest[chat.id] = row; reg() }
        Component.onDestruction: { if (chat && root.rowsForTest[chat.id] === row) delete root.rowsForTest[chat.id]; if (regGroup) root.unregisterDrag(regGroup, regKey, row) }
        // Reordering: in Favorites or one of your sections (Custom order).
        readonly property string dragGroup: row.section && root.sectionReorderable(row.section) ? row.section.id : ""
        readonly property real dragHeight: height
        property string regGroup: ""
        property string regKey: ""
        function reg() {
            if (regGroup) root.unregisterDrag(regGroup, regKey, row)
            regGroup = dragGroup; regKey = chat && chat.id ? chat.id : ""
            if (regGroup) root.registerDrag(regGroup, regKey, row)
        }
        onDragGroupChanged: reg()
        readonly property bool dragged: !!root.drag && root.drag.group === dragGroup && root.drag.key === chat.id && !root.dragCancelled
        opacity: dragged ? 0.5 : 1
        readonly property bool reorderingThis: root.reordering(dragGroup, chat.id)
        DragHandler {
            target: null
            enabled: row.dragGroup !== "" && !root.reorderKey
            dragThreshold: 4
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: {
                if (active) root.dragStart(row.dragGroup, row.chat.id, { name: row.chat.name || "", kind: "chat",
                    photoId: row.chat.peerMri || (row.chat.isGroup === true && !root.isMeeting(row.chat) ? "chat:" + row.chat.id : ""),
                    groupChat: row.chat.isGroup === true && !row.chat.peerMri }, row, centroid.pressPosition)
                else root.dragEnd()
            }
            onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
        }
        ReorderButtons { visible: row.reorderingThis; anchors.verticalCenter: parent.verticalCenter }
        readonly property bool selected: !root.draftsOpen && !root.mentionsOpen && !root.quickOpen && chat.id === root.currentId
        readonly property bool unread: chat.unread === true && !selected
        readonly property bool twoLine: root.previews
        width: list.width; height: twoLine ? 52 : 32
        Rectangle {
            id: hcFill2
            x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
            color: row.selected ? theme.selected : (hover.hovered ? theme.rowHover : "transparent")
            // Fluent's keyboard focus ring.
            border.color: theme.text; border.width: root.activeFocus && root.keyboardNav && root.focusId === row.chat.id ? 2 : 0
        }
        Avatar {
            visible: !row.chat.muted
            x: 32; y: row.twoLine ? 8 : 6
            size: row.twoLine ? 36 : 20; name: row.chat.name || ""
            // A group chat: Teams' merged picture of its members (the
            // group glyph until it arrives; meeting chats keep theirs).
            photoId: row.chat.peerMri || (row.chat.isGroup === true && !root.isMeeting(row.chat) ? "chat:" + row.chat.id : "")
            group: row.chat.isGroup === true && !row.chat.peerMri
            meeting: root.isMeeting(row.chat)
            presence: row.chat.presence || ""
        }
        // Muted: Teams swaps the picture for a 20 px #E6E6E6 circle with the
        // regular AlertOff icon (16, NeutralForeground3) at 2, 2.
        Rectangle {
            visible: !!row.chat.muted
            x: 32; y: row.twoLine ? 8 : 6; width: row.twoLine ? 36 : 20; height: width; radius: width / 2
            color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
            FluentIcon { anchors.centerIn: parent; name: "alert-off-20"; size: row.twoLine ? 20 : 16; color: theme.textSecondary }
        }
        // The last activity (Show time stamps), where ··· goes on hover.
        Text {
            id: rowStamp
            visible: root.timestamps && !row.showMore && !row.reorderingThis && text.length > 0
            anchors.right: parent.right; anchors.rightMargin: 28
            y: row.twoLine ? 10 : 8
            text: root.stamp(row.chat.time)
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: theme.onFill(hcFill2, row.unread ? theme.text : theme.textSecondary)
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
            color: theme.onFill(hcFill2, row.unread ? theme.text : theme.textSecondary)
        }
        Text {
            x: row.twoLine ? 80 : 64; y: row.twoLine ? 8.7 : 6
            width: (row.showMore ? moreButton.x - 10 : rowStamp.visible ? rowStamp.x - 8 : liveIcon.visible ? liveIcon.x - 14 : unreadDot.visible ? unreadDot.x - 14 : parent.width - 40) - x
            text: row.chat.name || ""
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            // Teams: bold only when unread; the open chat is just darker.
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: theme.onFill(hcFill2, row.selected || row.unread ? theme.text : theme.textSecondary)
        }
        // A call going on in the chat (Teams: the regular sound-wave 14 in
        // NeutralForeground3 at 244, 9 in the 288-wide row).
        FluentIcon {
            id: liveIcon
            visible: !!row.chat.liveCall && !row.showMore && !row.reorderingThis
            x: parent.width - 60; y: row.twoLine ? 29 : 9
            name: "live-roster-14"; size: 14
            color: theme.onFill(hcFill2, theme.textSecondary)
        }
        // Unread: bold name plus a brand dot; muted chats keep the bold
        // name but not the dot (they don't count toward badges).
        Rectangle {
            id: unreadDot
            visible: row.unread && !row.chat.muted && !row.showMore && !row.reorderingThis
            width: 8; height: 8; radius: 4
            x: parent.width - 16 - 8 - 12
            y: row.twoLine ? 30 : (parent.height - height) / 2
            color: theme.brand
        }
        readonly property bool showMore: (hover.hovered || rowMenu.opened) && !row.reorderingThis
        Rectangle {
            id: moreButton
            visible: row.showMore
            x: parent.width - 16 - 32; y: row.twoLine ? 14.3 : 4.3; width: 24; height: 23.3; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: moreHover.hovered ? "more-horizontal-20-filled" : "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, theme.textStrong) }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.openMenu(parent.x, parent.y + parent.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More chat options"
        }
        HoverHandler { id: hover }
        TapHandler { onTapped: if (!moreHover.hovered) { root.keyboardNav = false; root.chatSelected(row.chat.id, row.chat.name) } }
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
                // Teams: with single pointer controls on, in a section you
                // can reorder.
                root.singlePointReordering && row.dragGroup ? { key: "reorder", label: "Start reordering", icon: "arrow-sort-20", endIcon: "accessibility-20" } : null,
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
                !row.chat.isSelf && !root.isMeeting(row.chat) && !row.canLeave ? { key: "removeHistory", label: "Remove chat history", icon: "delete-20" } : null,
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
                else if (k === "reorder") root.startReorder(row.dragGroup, row.chat.id)
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
        function menuItemsForTest() { return rowMenu.items }
        function leaveForTest() { return leaveAsk }
        function removeHistoryForTest() { return removeHistoryAsk }
        // Teams' "Remove chat history?" (600 wide).
        ConfirmDialog {
            id: removeHistoryAsk
            width: 600
            title: "Remove chat history?"
            body: "This will remove the chat from your list and search. It affects you only."
            confirmText: "Remove"
            onConfirmed: backend.removeChatHistory(row.chat.id)
        }
        LeaveChatDialog {
            id: leaveAsk
            onConfirmed: removeHistory => { backend.leaveChat(row.chat.id); if (removeHistory) backend.removeChatHistory(row.chat.id) }
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
            chatReport.meeting = { title: d.title || chatReport.meeting.title, start: d.start ? Qt.formatDate(new Date(d.start), "MMM d") + ", " + theme.time(d.start) : "", organizer: d.organizer || "" }
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
        onStartReordering: (group, id) => root.startReorder(group, id)
    }
    function openChannelMenu(channel, team, anchor, px, py, group) {
        channelMenu.reorderGroup = root.singlePointReordering && group ? group : ""
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
        canReorder: root.singlePointReordering && root.teamsReorderable
        onStartReordering: id => root.startReorder("teams", id)
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
        Component.onCompleted: { if (channel && channel.id && !root.rowsForTest[channel.id]) root.rowsForTest[channel.id] = chRow; reg() }
        Component.onDestruction: { if (channel && root.rowsForTest[channel.id] === chRow) delete root.rowsForTest[channel.id]; if (regGroup) root.unregisterDrag(regGroup, regKey, chRow) }
        width: list.width; height: 28
        Rectangle {
            x: 16; width: parent.width - 32; height: 28; radius: theme.radius
            color: chRow.selected ? theme.selected : (chHover.hovered ? theme.rowHover : "transparent")
            border.color: theme.text; border.width: root.activeFocus && root.keyboardNav && root.focusId === chRow.channel.id ? 2 : 0
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
        TapHandler { onTapped: { root.keyboardNav = false; root.chatSelected(chRow.channel.id, chRow.channel.name) } }
        // Reordering: in Favorites or one of your sections (a channel
        // doesn't move within its team, as in Teams).
        readonly property string dragGroup: chRow.section && root.sectionReorderable(chRow.section) ? chRow.section.id : ""
        readonly property real dragHeight: height
        property string regGroup: ""
        property string regKey: ""
        function reg() {
            if (regGroup) root.unregisterDrag(regGroup, regKey, chRow)
            regGroup = dragGroup; regKey = channel && channel.id ? channel.id : ""
            if (regGroup) root.registerDrag(regGroup, regKey, chRow)
        }
        onDragGroupChanged: reg()
        opacity: !!root.drag && root.drag.group === dragGroup && root.drag.key === channel.id && !root.dragCancelled ? 0.5 : 1
        readonly property bool reorderingThis: root.reordering(dragGroup, channel.id)
        DragHandler {
            target: null
            enabled: chRow.dragGroup !== "" && !root.reorderKey
            dragThreshold: 4
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: active ? root.dragStart(chRow.dragGroup, chRow.channel.id, { name: chRow.channel.name + " (" + chRow.team.name + ")", kind: "channel" }, chRow, centroid.pressPosition) : root.dragEnd()
            onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
        }
        ReorderButtons { visible: chRow.reorderingThis; anchors.verticalCenter: parent.verticalCenter }
        // Its menu: ··· on hover (and while open), or a right-click (Teams'
        // channel row menu, as in the channel's header).
        readonly property bool menuOpen: channelMenu.menu.opened && channelMenu.channel.id === chRow.channel.id
        Rectangle {
            id: chMore
            visible: (chHover.hovered || chRow.menuOpen) && !chRow.reorderingThis
            x: parent.width - 16 - 8 - 24; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: theme.radius
            color: chMoreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(chMore, chRow.menuOpen ? theme.brand : theme.textStrong) }
            HoverHandler { id: chMoreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openChannelMenu(chRow.channel, chRow.team, chMore, 0, chMore.height + 4, chRow.dragGroup) }
            Accessible.role: Accessible.Button
            Accessible.name: "More options for " + chRow.channel.name
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: point => root.openChannelMenu(chRow.channel, chRow.team, chRow, point.position.x, point.position.y, chRow.dragGroup)
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Channel " + chRow.channel.name + " in " + chRow.team.name + (chRow.unread ? ", unread" : "")
    }

    // Start reordering's Move Up and Move Down (Teams' subtle 24 x 23.3
    // buttons, 56 and 32 from the row's end; arrow icons NeutralForeground2).
    component ReorderButtons: Row {
        id: rb
        z: 3
        x: parent.width - 16 - 56
        readonly property bool anyFocus: upButton.activeFocus || downButton.activeFocus
        onAnyFocusChanged: {
            root.reorderButtonFocused = anyFocus
            // Focus gone elsewhere (a click in the window): done. (A move
            // rebuilds the row, whose new buttons take the focus at once.)
            if (!anyFocus) reorderFocusCheck.restart()
        }
        onVisibleChanged: if (visible) Qt.callLater(() => upButton.forceActiveFocus())
        Component.onCompleted: if (visible) Qt.callLater(() => upButton.forceActiveFocus())
        ReorderButton { id: upButton; up: true }
        ReorderButton { id: downButton; up: false }
    }
    component ReorderButton: Rectangle {
        id: rbButton
        property bool up: true
        width: 24; height: 23.3; radius: 4
        color: rbHover.hovered ? theme.hover : "transparent"
        border.width: activeFocus ? 2 : 0; border.color: theme.text
        activeFocusOnTab: true
        FluentIcon { anchors.centerIn: parent; name: rbButton.up ? "arrow-up-20" : "arrow-down-20"; size: 20; color: theme.onFill(rbButton, theme.textStrong) }
        HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { rbButton.forceActiveFocus(); root.reorderStep(rbButton.up ? -1 : 1) } }
        Keys.onReturnPressed: root.reorderStep(rbButton.up ? -1 : 1)
        Keys.onSpacePressed: root.reorderStep(rbButton.up ? -1 : 1)
        Accessible.role: Accessible.Button
        Accessible.name: rbButton.up ? "Move Up" : "Move Down"
    }

    // Teams' "New" badge: brand pill, 10/14 semibold.
    component NewBadge: Rectangle {
        id: hcFill3
        width: newText.implicitWidth + 12; height: 18; radius: 9
        color: theme.brandFill
        Text { id: newText; anchors.centerIn: parent; text: "New"; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, "white") }
    }

    // A team and its shown channels.
    component TeamRows: Column {
        id: teamRows
        property var team
        property bool userOpen: teamRows.team.expanded !== false
        // Teams fold up while one is being moved.
        readonly property bool open: userOpen && !root.teamsFolded
        // Bold only while collapsed (Teams: not an expanded branch).
        readonly property bool unread: !open && teamRows.team.channels.some(c => c.unread)
        width: list.width
        Item {
            id: teamHeader
            width: list.width; height: 32
            // Reordering in Teams and channels.
            readonly property real dragHeight: height
            readonly property string key: teamRows.team.thread_id || ""
            Component.onCompleted: if (key) root.registerDrag("teams", key, teamHeader)
            Component.onDestruction: if (key) root.unregisterDrag("teams", key, teamHeader)
            opacity: !!root.drag && root.drag.group === "teams" && root.drag.key === key && !root.dragCancelled ? 0.5 : 1
            readonly property bool reorderingThis: root.reordering("teams", key)
            DragHandler {
                target: null
                enabled: root.teamsReorderable && !root.reorderKey && teamHeader.key !== ""
                dragThreshold: 4
                grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: active ? root.dragStart("teams", teamHeader.key, { name: teamRows.team.name, kind: "team", photoId: "team:" + teamRows.team.id }, teamHeader, centroid.pressPosition) : root.dragEnd()
                onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
            }
            ReorderButtons { visible: teamHeader.reorderingThis; anchors.verticalCenter: parent.verticalCenter }
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
            TapHandler { onTapped: teamRows.userOpen = !teamRows.userOpen }
            // Its menu: "More team options" (24 x 23.3, 8 from the row's
            // end) on hover, or a right-click (Teams' team menu).
            readonly property bool menuOpen: teamMenu.menu.opened && teamMenu.team.id === teamRows.team.id
            Rectangle {
                id: teamMore
                visible: (teamHover.hovered || parent.menuOpen) && !teamHeader.reorderingThis
                x: parent.width - 16 - 8 - 24; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 23.3; radius: theme.radius
                color: teamMoreHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(teamMore, teamMore.parent.menuOpen ? theme.brand : theme.textStrong) }
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
            id: hcFill4
            visible: sh.userSection && shHover.hovered
            x: parent.width - 16 - 32; y: 2; width: 24; height: 23.3; radius: 4
            color: smHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill4, theme.textStrong) }
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
