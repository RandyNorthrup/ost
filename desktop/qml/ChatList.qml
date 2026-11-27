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
    // ---- Quick views' rows (Teams' slice providers, read from Teams
    // 26304's worker; docs/spec/chat-list-and-header.md §3) ----
    // Teams hides a slice whose activityCount is 0: Mentions and Followed
    // threads count their items, Saved is 1 once you've saved a message,
    // Drafts is always 1 (listed even with nothing pending) and Discover
    // always 1 where the view shows channels. A slice is bold while its
    // unreadCount is above 0 (never Reminders), and Mentions, tag mentions
    // and Followed threads show that count in a badge (live flags
    // enableBadgingVNextBadgeCountChanges and …ForFollowedThreads).
    /// Unread mentions (Teams' mentions slice unreadCount).
    property int mentionsUnread: 0
    /// Followed threads: how many, and how many with unread replies.
    property int followedCount: 0
    property int followedUnread: 0
    /// Saved messages.
    property int savedCount: 0
    /// Followed threads and Saved as the list counts them, loaded at sign-in
    /// and whenever Teams pushes a change to 48:threads or 48:saved.
    function loadQuickCounts() {
        if (!backend.signedIn) return
        backend.channelAction("quick-followed", "", "", "")
        backend.channelAction("quick-saved", "", "", "")
    }
    Connections {
        target: backend
        function onQuickViewsVersionChanged() { root.loadQuickCounts() }
    }
    onQuickOpenChanged: loadQuickCounts()
    // Once the teams are known (a followed thread counts only where its
    // channel is), and again a little later if the service didn't answer.
    property bool quickCountsTeams: false
    onTeamsChanged: if (!quickCountsTeams && teams.length > 0) { quickCountsTeams = true; loadQuickCounts() }
    Timer { id: quickRetry; interval: 15000; onTriggered: root.loadQuickCounts() }
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
    /// Teams shows Copilot here when its ECS entry point is on, the
    /// Microsoft 365 Copilot app is installed for you and your Settings ▸
    /// Chats and channels ▸ Copilot switch is on (Main.qml decides).
    property bool showCopilot: false
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
    onSignedInChanged: if (signedIn) { backend.channelAction("notify-tagged", "", "", ""); loadQuickCounts() }
    Component.onCompleted: { syncSections(); if (signedIn) { backend.channelAction("notify-tagged", "", "", ""); loadQuickCounts() } if (backend.signedIn) backend.loadSettings() }
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
                backend.toast(qsTr("Something went wrong on our end. Please try again."), "error")
            } else if (r.op === "quick-followed" && r.ok) {
                // (Teams drops a thread whose conversation it doesn't know,
                // as Quick views ▸ Followed threads lists them.)
                const known = id => root.teams.some(t => (t.channels || []).some(c => c.id === id))
                const items = (r.data || []).filter(i => !i.channel || !root.teams.length || known(i.thread_id))
                root.followedCount = items.length
                root.followedUnread = items.filter(i => i.unread).length
            } else if ((r.op === "quick-followed" || r.op === "quick-saved") && !r.ok) {
                quickRetry.restart()
            } else if (r.op === "quick-saved" && r.ok) {
                root.savedCount = (r.data || []).length
            } else if (r.op === "quick-unsave" || r.op === "quick-unfollow") {
                root.loadQuickCounts()
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
    // Teams' filter text box (sticky filter, measured on Teams web
    // 2026-11-27): it opens above the pills, which stay; Esc or the toggle
    // closes it and drops the text. The text filters 250 ms after typing
    // stops (simpleCollabFilterTextDebouceTimeInMS), up to 100 characters.
    function openFilter() { filtering = true; filterField.forceActiveFocus() }
    function closeFilter() { filterField.text = ""; nameFilter = ""; filtering = false }
    /// The box's placeholder and name, by the list (unified, the Chat app,
    /// the Teams app).
    readonly property string filterLabel: pane === "chats" ? qsTr("Filter by person or chat name")
        : pane === "teams" ? qsTr("Filter by channel name") : qsTr("Filter by person, chat or channel name")
    Timer { id: filterDebounce; interval: 250; onTriggered: root.nameFilter = filterField.text.trim().toLowerCase() }
    /// The filter box's height and its gap (pills and the list move down by it).
    readonly property real filterBoxH: filtering ? 48 : 0
    /// Teams' pill toggle: Unread on its own, categories single-select.
    function setChip(c) {
        if (c === "unread") unreadOn = !unreadOn
        else category = category === c ? "" : c
    }
    function clearFilters() { unreadOn = false; category = ""; nameFilter = ""; filterField.text = ""; filtering = false; chipFilter = "" }
    function filterBoxForTest() { return filterBox }
    function setFilterTextForTest(t) { filterField.text = t }
    function nameMatches(n) { return !nameFilter || (n || "").toLowerCase().indexOf(nameFilter) >= 0 }
    /// The quick view open beside the list ("mentions", "drafts", "followed", "saved" or "").
    readonly property string openSlice: mentionsOpen ? "mentions" : draftsOpen ? "drafts" : quickOpen
    /// A quick view under the filters, as Teams' list (Teams web
    /// 2026-11-27): none under a category pill; with Unread only those with
    /// unread items; with text those whose name matches, and the open one.
    function sliceShown(s) {
        if (category) return false
        if (unreadOn && !(s.unread > 0)) return false
        return nameMatches(s.label) || (!!nameFilter && s.key === openSlice)
    }

    // ---- Server sections ----
    readonly property var folderData: backend.foldersJson ? JSON.parse(backend.foldersJson) : null
    readonly property var folders: folderData && folderData.folders && folderData.folders.length ? folderData.folders
        : [{ id: "", kind: "QuickViews", title: qsTr("Quick views"), expanded: true, items: [] },
           { id: "", kind: "Favorites", title: qsTr("Favorites"), expanded: true, items: [] },
           { id: "", kind: "RecentChats", title: qsTr("Chats"), expanded: true, items: [] },
           { id: "", kind: "TeamsAndChannels", title: qsTr("Teams and channels"), expanded: true, items: [] }]
    readonly property bool hasCommunities: folders.some(f => f.kind === "EngageCommunities")
    /// Conversations in Favorites or your own sections (not listed in Chats).
    readonly property var sectioned: {
        const m = {}
        for (const f of folders) if (f.kind === "Favorites" || root.isUsers(f)) for (const i of f.items) m[i] = f.id || f.kind
        return m
    }
    readonly property var userSections: folders.filter(f => root.isUsers(f))
    function isUsers(f) { return f.kind === "UserCreated" || f.kind === "UserDefined" }
    /// A section's name: Teams' own sections (whose names come from the
    /// server in English) in the app language; yours as you named them.
    function folderTitle(f) {
        switch (f.kind) {
        case "QuickViews": return qsTr("Quick views")
        case "Favorites": return qsTr("Favorites")
        case "RecentChats": return qsTr("Chats")
        case "TeamsAndChannels": return qsTr("Teams and channels")
        case "EngageCommunities": return qsTr("Communities")
        default: return f.title
        }
    }
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
        if (category === "unmuted" && c.muted) return false
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
            // In the folder's order (Mentions, Followed threads, Discover,
            // Drafts, Saved). Separate view's Chat has no Followed threads
            // (Teams' quickViewsSupportedSlicesForViewType SPLIT_CHAT;
            // seen on winpc 2026-11-21).
            const all = []
            if (root.hasMentions) all.push({ type: "slice", key: "mentions", label: qsTr("Mentions"), icon: "mention-20", unread: root.mentionsUnread, badge: root.mentionsUnread })
            if (pane !== "chats" && root.followedCount > 0) all.push({ type: "slice", key: "followed", label: qsTr("Followed threads"), icon: "followed-threads-20", unread: root.followedUnread, badge: root.followedUnread })
            all.push({ type: "slice", key: "drafts", label: qsTr("Drafts"), icon: "drafts-20", unread: 0, badge: 0 })
            if (root.savedCount > 0) all.push({ type: "slice", key: "saved", label: qsTr("Saved"), icon: "bookmark-20", unread: 0, badge: 0 })
            rows = all.filter(s => root.sliceShown(s))
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
    // The list's models: sections by key, each with its rows by key.
    ListModel { id: sectionModel }
    property var sectionByKey: ({})
    readonly property var emptySection: ({ folder: { id: "", kind: "", title: "", expanded: false, items: [] }, rows: [] })
    function rowKey(r) {
        switch (r.type) {
        case "chat": return "chat:" + r.chat.id
        case "channel": return "channel:" + r.channel.id
        case "team": return "team:" + r.team.id
        case "slice": return "slice:" + r.key
        default: return r.type
        }
    }
    function syncSections() {
        const m = {}, keys = []
        for (const s of sections) {
            const k = s.folder.id || s.folder.kind
            if (k in m) continue
            m[k] = s
            keys.push(k)
        }
        sectionByKey = m
        syncKeys(sectionModel, keys)
    }
    onSectionsChanged: syncSections()
    /// Make a ListModel of {key} rows hold `keys`, in order, with the fewest
    /// changes: a Repeater over it keeps the items of the rows that stay
    /// (moved rows keep theirs too).
    function syncKeys(model, keys) {
        const want = {}
        for (const k of keys) want[k] = true
        const cur = []
        for (let i = 0; i < model.count; i++) cur.push(model.get(i).key)
        for (let i = cur.length - 1; i >= 0; i--) if (!want[cur[i]]) { model.remove(i); cur.splice(i, 1) }
        for (let i = 0; i < keys.length; i++) {
            if (cur[i] === keys[i]) continue
            const j = cur.indexOf(keys[i], i + 1)
            if (j >= 0) { model.move(j, i, 1); cur.splice(j, 1); cur.splice(i, 0, keys[i]) }
            else { model.insert(i, { key: keys[i] }); cur.splice(i, 0, keys[i]) }
        }
    }

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    // ---- ··· More list options ----
    // Teams' mode: the unified list, the Chat app's or the Teams app's
    // (split view).
    readonly property string appMode: pane === "chats" ? "chat" : pane === "teams" ? "channel" : "unified"
    readonly property var markAllSubmenu: appMode === "unified"
        ? [{ label: qsTr("All"), appType: "unified" }, { label: qsTr("All chats"), appType: "chat" }, { label: qsTr("All channels"), appType: "channel" }]
            .concat(hasCommunities ? [{ label: qsTr("All communities"), appType: "engage_community" }] : [])
        : appMode === "channel" && hasCommunities
        ? [{ label: qsTr("All"), appType: "split_channel" }, { label: qsTr("All channels"), appType: "channel" }, { label: qsTr("All communities"), appType: "engage_community" }]
        : []
    readonly property var listMenuItems: {
        const mark = { key: "markAll", label: qsTr("Mark all as read"), icon: "glasses-20", keys: "Shift+Esc" }
        if (markAllSubmenu.length) { mark.split = true; mark.submenu = markAllSubmenu; mark.splitLabel = qsTr("Mark all as read options") }
        const out = [mark,
            { key: "collapseAll", label: qsTr("Collapse all sections"), icon: "arrow-collapse-all-20", keys: "Alt+Q" },
            { separator: true },
            { key: "customize", label: qsTr("Customize view"), icon: "settings-20" }]
        if (appMode !== "chat") {
            out.push({ separator: true }, { key: "yourTeams", label: qsTr("Your teams and channels"), icon: "people-team-20" })
            if (hasCommunities) out.push({ key: "yourCommunities", label: qsTr("Your communities"), icon: "people-community-20" })
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
    readonly property string markAllEntities: category === "chats" || appMode === "chat" ? qsTr("chats")
        : category === "channels" || appMode === "channel" ? qsTr("channels") : qsTr("chats, channels, and communities")

    // ---- New items ▾ (Teams' Nb, unified list; docs/spec/
    // chat-list-and-header.md §2.3) ----
    // New message (Ctrl+N), New message in new window (Ctrl+Shift+N; not
    // when new chats always open in a window), New channel, New storyline
    // post | Join team, New team | Join communities | New section. The Chat
    // app of the separate view has New message, the window one, New
    // storyline post | New section. Storyline and communities need Viva
    // Engage (the Communities section is there).
    signal newChatWindow()
    signal newStorylinePost()
    signal joinTeam()
    signal newTeam()
    /// New chats always open in a window (Settings: Teams' alwaysPopOutNewChat).
    property bool newChatInWindow: false
    readonly property var newItems: {
        const out = [{ key: "message", label: qsTr("New message"), icon: "compose-20", keys: "Ctrl+N" }]
        if (!newChatInWindow) out.push({ key: "messageWindow", label: qsTr("New message in new window"), icon: "open-window-20", keys: "Ctrl+Shift+N" })
        if (appMode !== "chat") out.push({ key: "channel", label: qsTr("New channel"), icon: "channel-add-nm-20" })
        if (hasCommunities) out.push({ key: "storyline", label: qsTr("New storyline post"), icon: "storyline-add-20" })
        if (appMode !== "chat") {
            out.push({ separator: true }, { key: "joinTeam", label: qsTr("Join team"), icon: "people-team-join-20" }, { key: "newTeam", label: qsTr("New team"), icon: "people-team-new-20" })
            if (hasCommunities) out.push({ separator: true }, { key: "joinCommunities", label: qsTr("Join communities"), icon: "people-community-join-20" })
        }
        out.push({ separator: true }, { key: "section", label: qsTr("New section"), icon: "section-add-20" })
        return out
    }
    function newItemPicked(key) {
        if (key === "message") root.newChat()
        else if (key === "messageWindow") root.newChatWindow()
        else if (key === "channel") newChannelDialog.startPick()
        else if (key === "storyline") root.newStorylinePost()
        else if (key === "joinTeam") root.joinTeam()
        else if (key === "newTeam") root.newTeam()
        else if (key === "joinCommunities") root.openCommunities()
        else if (key === "section") sectionDialog.create("", "")
    }
    // New channel: Teams' Create a channel with its team picker.
    CreateChannelDialog { id: newChannelDialog; onCreated: (id, name) => root.chatSelected(id, name) }
    function newChannelDialogForTest() { return newChannelDialog }
    function openNewItemsForTest() { newMenu.open() }
    function newItemsMenuForTest() { return newMenu }

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
        // Teams' divider: "Resize {direction} panel", the side it grows from.
        Accessible.name: qsTr("Resize %1 panel").arg(Qt.application.layoutDirection === Qt.RightToLeft ? qsTr("right", "framework:k1zo9i9g2") : qsTr("left", "framework:k3z7dwz65"))
        Accessible.description: Math.round(root.width) + "px"
    }

    component HeaderButton: Rectangle {
        id: hb
        property alias icon: hbIcon.name
        property int iconSize: 20
        property color iconColor: theme.textStrong
        /// Its tooltip ("" for none).
        property string tip: ""
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: hbHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        FluentIcon { id: hbIcon; anchors.centerIn: parent; size: hb.iconSize; color: theme.onFill(hb, hb.iconColor) }
        ToolTip.visible: hb.tip !== "" && hbHover.hovered
        ToolTip.delay: 600
        ToolTip.text: hb.tip
    }

    // Header: "Chat", then more / filter / new message (with its menu).
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            x: 32; y: 19
            text: root.pane === "teams" ? qsTr("Teams") : qsTr("Chat")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        HeaderButton {
            id: moreList
            x: root.width - 126; y: 15; icon: "more-20"; Accessible.name: qsTr("More list options")
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
        // Teams' filter toggle (sticky-filter-v2-button, Teams web
        // 2026-11-27): its magnifier filled and brand while the box is open;
        // "Show filter text box" (Ctrl+Shift+F) / "Close filter text box".
        HeaderButton {
            id: filterToggle
            x: root.width - 94; y: 15
            icon: root.filtering ? "list-filter-search-20-filled" : "list-filter-search-20"
            iconColor: root.filtering ? theme.brand : theme.textStrong
            tip: root.filtering ? qsTr("Close filter text box") : qsTr("Show filter text box") + " (Ctrl+Shift+F)"
            Accessible.name: root.filtering ? qsTr("Close filter text box") : qsTr("Show filter text box")
            onClicked: root.filtering ? root.closeFilter() : root.openFilter()
        }
        HeaderButton {
            x: root.width - 62; y: 14; width: 26; icon: "compose-20"
            Accessible.name: qsTr("New message")
            onClicked: root.newChat()
        }
        HeaderButton {
            id: newItems
            x: root.width - 36; y: 14; width: 20; icon: "chevron-down-12"; iconSize: 12
            tip: qsTr("New items"); Accessible.name: qsTr("New items")
            onClicked: newMenu.open()
            // Teams' New items (Nb; Teams desktop on testpc2 and Teams web,
            // 2026-11-27), below the chevron with their ends lined up.
            MenuPopup {
                id: newMenu
                x: parent.width - width; y: parent.height + 4
                wrapLabels: true
                items: root.newItems
                onPicked: i => root.newItemPicked(root.newItems[i].key)
            }
        }
    }

    // ---- Filter pills (Teams' sticky filter) ----
    // 24 tall, 4 apart, border 0.67 NeutralStroke1, 12/16 NeutralForeground2,
    // padding 8; chosen: BrandForeground2 (#444791) fill, white text.
    // Separate view: Chat has Unread / Chats / Meeting chats, the Teams app
    // Unread / Channels / Communities (Teams, measured).
    readonly property var pillDefs: [
        { key: "unread", label: qsTr("Unread"), keys: "Ctrl+Alt+U" },
        { key: "channels", label: qsTr("Channels"), keys: "Ctrl+Alt+A" },
        { key: "chats", label: qsTr("Chats"), keys: "Ctrl+Alt+C" },
        // Separate view's Chat (winpc, 2026-11-21): Unread, Chats, Unmuted,
        // then Meeting chats under More filters.
        { key: "unmuted", label: qsTr("Unmuted"), keys: "Ctrl+Alt+Q" },
        { key: "meetings", label: qsTr("Meeting chats"), keys: "Ctrl+Alt+B" }
    ].concat(hasCommunities ? [{ key: "communities", label: qsTr("Communities"), keys: "" }] : [])
     .filter(p => pane === "chats" ? ["unread", "chats", "unmuted", "meetings"].indexOf(p.key) >= 0
                : p.key === "unmuted" ? false
                : pane === "teams" ? ["unread", "channels", "communities"].indexOf(p.key) >= 0 : true)
    onPaneChanged: { category = ""; unreadOn = false; updateJump() }
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
        visible: root.filtersShown
        x: 32; y: 69 + root.filterBoxH
        spacing: 4
        Repeater { model: root.pillRows.first; Pill { required property var modelData; def: modelData } }
    }
    Row {
        visible: root.secondRow && root.filtersShown
        x: 32; y: 101 + root.filterBoxH
        spacing: 4
        Repeater { model: root.secondRow ? root.pillRows.second : []; Pill { required property var modelData; def: modelData } }
    }
    // More filters / Fewer filters: only when pills overflow.
    HeaderButton {
        visible: root.pillRows.second.length > 0 && root.filtersShown
        x: root.width - 38; y: 65 + root.filterBoxH; width: 24; height: 24; radius: 4
        icon: root.moreFiltersOpen ? "chevron-up-16" : "chevron-down-16"; iconSize: 16
        iconColor: root.moreFiltersOpen ? theme.brand : theme.textStrong
        onClicked: root.moreFiltersOpen = !root.moreFiltersOpen
        ToolTip.visible: false
        Accessible.name: root.moreFiltersOpen ? qsTr("Fewer filters") : qsTr("More filters")
    }
    // "Show filter text box" (Teams web 2026-11-27, at 360 wide): a 32 px
    // box 32 in and 16 from the end, 11 under the header, white with
    // Fluent's shadow 2 and radius 4, no icon; the text 13 in (14/20,
    // NeutralForeground4 placeholder); a 2 px brand line along its bottom
    // while it has the focus; with text, Clear filter text (24 px, a 20 px
    // dismiss, 6 from its end).
    Item {
        id: filterBox
        visible: root.filtering
        x: 32; y: 72; width: root.width - 48; height: 32
        FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: theme.input }
        Rectangle {
            visible: filterField.activeFocus
            anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
            color: theme.brand
        }
        TextInput {
            id: filterField
            x: 13; width: parent.width - x - (clearFilter.visible ? 36 : 12)
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            selectionColor: theme.brand; selectedTextColor: "white"
            clip: true
            maximumLength: 100
            onTextChanged: { if (!text) { filterDebounce.stop(); root.nameFilter = "" } else filterDebounce.restart() }
            Keys.onEscapePressed: root.closeFilter()
            Text { visible: !filterField.text; width: filterField.width; elide: Text.ElideRight; text: root.filterLabel; color: theme.textTertiary; font: filterField.font }
            Accessible.role: Accessible.EditableText
            Accessible.name: root.filterLabel
        }
        Rectangle {
            id: clearFilter
            visible: filterField.text.length > 0
            x: parent.width - 6 - width; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 4
            color: clh.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: clh.hovered ? "dismiss-20-filled" : "dismiss-20"; size: 20; color: theme.onFill(clearFilter, theme.textStrong) }
            HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { filterField.text = ""; filterField.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Clear filter text")
        }
    }

    // ---- The list ----
    Flickable {
        id: list
        y: root.filterBoxH + (!root.filtersShown ? 66 : root.secondRow ? 138 : 106)
        width: parent.width - 1
        height: parent.height - y - (root.jumpShown ? jumpBar.height : 0)
        onContentYChanged: root.updateJump()
        onHeightChanged: root.updateJump()
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
            // It stays while the list is filtered (Teams web 2026-11-27:
            // text, Unread and the Chats pill all kept it).
            ListRow {
                visible: root.showCopilot && root.pane !== "teams"
                height: visible ? 32 : 0
                label: qsTr("Copilot"); icon: "mo-copilot"
                selected: root.copilotOpen
                onClicked: root.openCopilot()
            }
            Item { width: 1; height: root.showCopilot && root.pane !== "teams" ? 4 : 0 }
            // Sections and their rows are keyed models kept in step with
            // the data (syncKeys, syncRows): an update (a chat hidden or
            // shown, a new message, presence) changes only the rows it
            // touched, instead of building every row of the list again
            // (with hundreds of chats, a burst of pushed updates rebuilt
            // the list each time and ran memory up by gigabytes).
            Repeater {
                model: sectionModel
                Column {
                    id: sec
                    required property string key
                    readonly property var modelData: root.sectionByKey[key] || root.emptySection
                    readonly property var folder: modelData.folder
                    // Each row's data and its JSON (to tell what changed),
                    // and its item, by row key; changed in place.
                    property var rowData: ({})
                    property var rowJson: ({})
                    property var rowItems: ({})
                    ListModel { id: rowModel }
                    function syncRows() {
                        // (From modelData: folder may not have caught up yet.)
                        const d = sec.modelData || root.emptySection
                        const rows = d.folder && d.folder.expanded ? d.rows : []
                        const keys = [], seen = {}
                        for (const r of rows) {
                            const k = root.rowKey(r)
                            if (seen[k]) continue
                            seen[k] = true
                            keys.push(k)
                            const j = JSON.stringify(r)
                            if (sec.rowJson[k] === j) continue
                            sec.rowJson[k] = j
                            sec.rowData[k] = r
                            if (sec.rowItems[k]) sec.rowItems[k].row = r
                        }
                        for (const k in sec.rowJson) if (!seen[k]) { delete sec.rowJson[k]; delete sec.rowData[k] }
                        root.syncKeys(rowModel, keys)
                    }
                    onModelDataChanged: syncRows()
                    // (The Jump to bar watches where Teams and channels is.)
                    readonly property bool teamsSection: folder.kind === "TeamsAndChannels"
                    onTeamsSectionChanged: if (teamsSection) root.teamsSectionItem = sec; else if (root.teamsSectionItem === sec) root.teamsSectionItem = null
                    onYChanged: if (teamsSection) root.updateJump()
                    Component.onCompleted: { syncRows(); if (teamsSection) root.teamsSectionItem = sec }
                    Component.onDestruction: if (root.teamsSectionItem === sec) root.teamsSectionItem = null
                    width: list.width
                    // Quick views end with a hairline (12 below, the next
                    // section 4 after it).
                    SectionHeader {
                        label: root.folderTitle(sec.folder)
                        open: sec.folder.expanded
                        userSection: root.isUsers(sec.folder)
                        onToggled: backend.folderAction(sec.folder.expanded ? "collapse" : "expand", JSON.stringify({ id: sec.folder.id }))
                        onMenuRequested: (px, py) => root.openSectionMenu(sec.folder, this, px, py)
                    }
                    Item { width: 1; height: sec.folder.expanded && sec.modelData.rows.length > 0 ? 4 : 0 }
                    Repeater {
                        model: rowModel
                        Loader {
                            id: rowLoader
                            required property string key
                            width: list.width
                            // Set once here; syncRows hands it new data.
                            property var row: sec.rowData[key]
                            property var section: sec.folder
                            Component.onCompleted: sec.rowItems[key] = rowLoader
                            Component.onDestruction: if (sec.rowItems[key] === rowLoader) delete sec.rowItems[key]
                            sourceComponent: !row ? null
                                : row.type === "chat" ? chatRowComp
                                : row.type === "channel" ? channelRowComp
                                : row.type === "team" ? teamComp
                                : row.type === "slice" ? sliceComp
                                : row.type === "seeAllTeams" ? seeAllComp
                                : row.type === "newMessage" ? newMessageComp
                                : joinCommunitiesComp
                        }
                    }
                    Item { width: 1; height: sec.folder.kind === "QuickViews" ? 12 : 8 }
                    Rectangle { visible: sec.folder.kind === "QuickViews"; x: 16; width: list.width - 32; height: 1; color: theme.divider }
                    Item { width: 1; height: sec.folder.kind === "QuickViews" ? 4 : 0 }
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
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("You're all caught up!"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Clear filters"); font.family: theme.font; font.pixelSize: 16; color: theme.brand
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.clearFilters() }
                    Accessible.role: Accessible.Link; Accessible.name: qsTr("Clear filters")
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

    // ---- Jump to Teams and channels (Teams' left-rail-teams-and-channels-
    // jumper, enableSimpleCollabLeftRailTeamsAndChannelsJumper; measured on
    // Teams web 2026-11-27 at 360 wide) ----
    // In the unified list, while the Teams and channels section is below
    // what the list shows (Teams' observer: not in view and not above it),
    // a 42 px toolbar "Jump to" sits under the list: a 2 px rule (16 in;
    // 1 px 5 % black over 1 px 10 % black) and the section's name as a
    // 40 px button (14/20 NeutralForeground2, 32 in; bold NeutralForeground1
    // while a channel there is unread; brand with a 16 px arrow down 4
    // after it on hover). The list ends above it. Clicking it opens the
    // section if it's collapsed and scrolls it to the top.
    property Item teamsSectionItem: null
    onTeamsSectionItemChanged: updateJump()
    property bool jumpShown: false
    function updateJump() {
        const s = teamsSectionItem
        if (pane !== "combined" || !s || !s.visible) { jumpShown = false; return }
        // The bar takes the list's bottom while it shows, so it hides only
        // once the section is in the smaller view (no flicker either way).
        const below = s.y >= list.contentY + list.height
        if (jumpShown !== below) jumpShown = below
    }
    readonly property bool teamsUnread: shownTeams.some(t => t.channels.some(c => c.unread))
    property bool pendingJump: false
    function jumpToTeams() {
        const s = teamsSectionItem
        if (!s) return
        if (!s.folder.expanded && s.folder.id) { pendingJump = true; jumpTimer.restart(); backend.folderAction("expand", JSON.stringify({ id: s.folder.id })) }
        scrollToTeams()
        root.forceActiveFocus()
    }
    function scrollToTeams() {
        const s = teamsSectionItem
        if (s) list.contentY = Math.max(0, Math.min(s.y, list.contentHeight - list.height))
    }
    // An opened section's rows arrive with the folders' answer: scroll once more.
    Timer { id: jumpTimer; interval: 3000; onTriggered: root.pendingJump = false }
    Connections { target: listCol; function onHeightChanged() { if (root.pendingJump) root.scrollToTeams(); root.updateJump() } }
    function jumpBarForTest() { return jumpBar }
    Item {
        id: jumpBar
        visible: root.jumpShown
        anchors.bottom: parent.bottom
        width: parent.width - 1; height: 42
        Accessible.role: Accessible.ToolBar
        Accessible.name: qsTr("Jump to")
        Column {
            x: 16; width: parent.width - 32
            Rectangle { width: parent.width; height: 1; color: theme.pick("#0D000000", "#0DFFFFFF", "#FFFFFF") }
            Rectangle { width: parent.width; height: 1; color: theme.pick("#1A000000", "#1AFFFFFF", "#FFFFFF") }
        }
        Item {
            id: jumpButton
            x: 16; y: 2; width: parent.width - 32; height: 40
            Text {
                id: jumpText
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - x - 36)
                elide: Text.ElideRight
                text: root.folderTitle({ kind: "TeamsAndChannels" })
                font.family: theme.font; font.pixelSize: theme.base
                font.weight: root.teamsUnread ? Font.DemiBold : Font.Normal
                color: jumpHover.hovered ? theme.brand : root.teamsUnread ? theme.text : theme.textSecondary
            }
            FluentIcon {
                visible: jumpHover.hovered
                x: jumpText.x + jumpText.width + 4; anchors.verticalCenter: parent.verticalCenter
                name: "arrow-down-20"; size: 16; color: theme.brand
            }
            HoverHandler { id: jumpHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.jumpToTeams() }
            Accessible.role: Accessible.Button
            Accessible.name: jumpText.text
            Accessible.onPressAction: root.jumpToTeams()
        }
    }

    Component { id: chatRowComp; ChatRow { chat: parent && parent.row ? parent.row.chat : ({}); section: parent ? parent.section : null } }
    Component { id: channelRowComp; ChannelRow { channel: parent && parent.row ? parent.row.channel : ({}); team: parent && parent.row ? parent.row.team : ({}); section: parent ? parent.section : null; indent: 32 } }
    Component { id: teamComp; TeamRows { team: parent && parent.row ? parent.row.team : ({ name: "", channels: [] }) } }
    Component {
        id: sliceComp
        ListRow {
            label: parent.row.label; icon: parent.row.icon
            unread: parent.row.unread > 0; badge: parent.row.badge || 0; marks: true
            selected: parent.row.key === "mentions" ? root.mentionsOpen : parent.row.key === "drafts" ? root.draftsOpen : root.quickOpen === parent.row.key
            onClicked: parent.row.key === "mentions" ? root.openMentions() : parent.row.key === "drafts" ? root.openDrafts() : root.openQuick(parent.row.key)
        }
    }
    Component {
        id: newMessageComp
        ListRow { label: qsTr("New message"); icon: "compose-20"; selected: root.composing; onClicked: root.openComposing() }
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
                x: 31; y: 4; text: qsTr("See all your teams"); font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openYourTeams() }
                Accessible.role: Accessible.Link; Accessible.name: qsTr("See all your teams")
            }
        }
    }
    Component {
        id: joinCommunitiesComp
        Item {
            width: list.width; height: 28
            Text {
                x: 31; y: 4; text: qsTr("Join communities"); font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openCommunities() }
                Accessible.role: Accessible.Link; Accessible.name: qsTr("Join communities")
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
        items: [{ label: qsTr("Rename section"), icon: "rename-20" }, { label: qsTr("Remove section"), icon: "delete-20" }]
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
    /// Group chats' member counts, by chat id (loaded as menus open).
    readonly property var memberCounts: backend.chatMemberCountsJson ? JSON.parse(backend.chatMemberCountsJson) : ({})
    function previewOf(c) {
        if (!c.preview) return ""
        if (c.previewSystem) return c.preview
        const mine = !!c.sender && c.sender === backend.userName
        return mine ? qsTr("You: %1").arg(c.preview) : (c.isGroup && c.sender ? c.sender + ": " + c.preview : c.preview)
    }

    // One chat in a section: picture with presence, name, unread dot.
    component ChatRow: Item {
        id: row
        property var chat
        property var section: null
        readonly property bool menuOpen: !!row.rowMenu && row.rowMenu.opened
        function closeMenu() { if (row.rowMenu) row.rowMenu.close() }
        // The row's menu, its Manage notifications flyout and its dialogs
        // are made the first time they're needed: with hundreds of chats
        // listed, five popups on every row made each row (and each update
        // that built rows) cost megabytes.
        property var rowMenu: null
        property var chatNotifyFlyout: null
        property var chatNotifyDialog: null
        property var removeHistoryAsk: null
        property var leaveAsk: null
        function made(name, comp) { if (!row[name]) row[name] = comp.createObject(row); return row[name] }
        function menu() { return made("rowMenu", rowMenuComp) }
        function flyout() { return made("chatNotifyFlyout", chatNotifyFlyoutComp) }
        function notifyDialog() { return made("chatNotifyDialog", chatNotifyDialogComp) }
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
            meetingIcon: row.chat.backroom ? "calendar-lock-20" : "meeting-chat-20"
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
            // One line, as Teams (a message's line breaks read as spaces).
            text: (root.previewOf(row.chat) || "").replace(/\s*\n\s*/g, " ")
            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
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
            FilterMarks { query: root.nameFilter }
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
        readonly property bool showMore: (hover.hovered || row.menuOpen) && !row.reorderingThis
        Rectangle {
            id: moreButton
            visible: row.showMore
            x: parent.width - 16 - 32; y: row.twoLine ? 14.3 : 4.3; width: 24; height: 23.3; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: moreHover.hovered ? "more-horizontal-20-filled" : "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, theme.textStrong) }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.openMenu(parent.x, parent.y + parent.height) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More chat options")
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
        readonly property var members: root.memberCounts[row.chat.id]
        // Leave: a member of a group chat of at least 3 (not a meeting chat
        // you created).
        readonly property bool canLeave: !!row.chat.isGroup && !row.chat.peerMri && (row.members || 0) >= 3 && !(root.isMeeting(row.chat) && row.chat.isCreator)
        function destinations() {
            const out = []
            const fav = root.favoritesFolder
            if (fav && fav.id && fav.id !== row.holder) out.push({ id: fav.id, label: qsTr("Favorites") })
            for (const s of root.userSections) if (s.id !== row.holder) out.push({ id: s.id, label: s.title })
            return out
        }
        function openMenu(px, py) {
            if (row.chat.isGroup && !row.chat.peerMri && row.members === undefined) backend.chatMemberCountsLoad(row.chat.id)
            const dest = destinations()
            const sub = dest.map(d => ({ label: d.label, to: d.id }))
            if (sub.length) sub.push({ separator: true })
            sub.push({ label: qsTr("New section"), icon: "folder-add-20", newSection: true })
            const oneOnOne = !!row.chat.peerMri && !row.chat.isSelf
            const tagged = oneOnOne && root.notifyTagged[row.chat.peerMri.toLowerCase()]
            const rowMenu = row.menu()
            rowMenu.items = [
                { key: "window", label: qsTr("Open in new window"), icon: "open-window-20" },
                // Teams: with single pointer controls on, in a section you
                // can reorder.
                root.singlePointReordering && row.dragGroup ? { key: "reorder", label: qsTr("Start reordering"), icon: "arrow-sort-20", endIcon: "accessibility-20" } : null,
                { separator: true },
                { key: row.unread ? "read" : "unread", label: row.unread ? qsTr("Mark as read") : qsTr("Mark as unread"), icon: row.unread ? "glasses-20" : "glasses-off-20" },
                // A group chat you're in: Teams' Manage notifications ▸
                // (granular chat settings) in place of Mute, before Move to
                // section (measured on winpc 2026-11-20).
                row.groupNotify ? { key: "notify", label: qsTr("Manage notifications"), icon: "alert-20", flyout: true } : null,
                { key: "move", label: qsTr("Move to section"), icon: "star-20", submenu: sub },
                row.holder ? { key: "removeFrom", label: qsTr("Remove from section"), icon: "star-off-20" } : null,
                row.groupNotify || row.chat.isSelf ? null : { key: row.chat.muted ? "unmute" : "mute", label: row.chat.muted ? qsTr("Unmute") : qsTr("Mute"), icon: row.chat.muted ? "alert-20" : "alert-off-20" },
                oneOnOne ? { key: tagged ? "notifyOff" : "notifyOn", label: tagged ? qsTr("Turn off notifications") : qsTr("Notify when available"), icon: "notify-available-20" } : null,
                row.chat.isSelf ? null : { key: "apps", label: qsTr("Manage apps"), icon: "manage-apps-20" },
                row.chat.isSelf ? null : { key: "workflows", label: qsTr("Set workflows"), icon: "workflows-20" },
                { key: "link", label: qsTr("Copy link"), icon: "link-20" },
                { separator: true },
                !row.chat.isSelf && !root.isMeeting(row.chat) && !row.canLeave ? { key: "removeHistory", label: qsTr("Remove chat history"), icon: "delete-20" } : null,
                row.canLeave ? { key: "leave", label: qsTr("Leave"), icon: "door-arrow-left-20" } : null,
                { key: row.chat.hidden ? "unhide" : "hide", label: row.chat.hidden ? qsTr("Unhide") : qsTr("Hide"), icon: row.chat.hidden ? "eye-20" : "eye-off-20" },
                root.isMeeting(row.chat) ? { separator: true } : null,
                root.isMeeting(row.chat) ? { key: "report", label: qsTr("Report a concern"), icon: "shield-error-20" } : null
            ].filter(i => i !== null)
            rowMenu.x = Math.min(px, row.width - rowMenu.implicitWidth - 8)
            rowMenu.y = py
            rowMenu.open()
        }
        // Teams shows Manage notifications for a group chat (not a meeting
        // or one-on-one chat) when granular chat settings are on.
        readonly property bool groupNotify: !!row.chat.isGroup && !row.chat.peerMri && !row.chat.isSelf && !root.isMeeting(row.chat)
        Component {
            id: rowMenuComp
            MenuPopup {
                id: rowMenu
                separatorHeight: 8.6
                onFlyoutRequested: (i, r) => {
                    if (i < 0 || !r) { if (row.chatNotifyFlyout) row.chatNotifyFlyout.close(); return }
                    const p = r.mapToItem(rowMenu.contentItem, 0, 0)
                    const chatNotifyFlyout = row.flyout()
                    chatNotifyFlyout.parent = rowMenu.contentItem
                    chatNotifyFlyout.x = rowMenu.width - 8
                    chatNotifyFlyout.y = p.y - 4
                    chatNotifyFlyout.load()
                    chatNotifyFlyout.open()
                }
                onClosed: if (row.chatNotifyFlyout) row.chatNotifyFlyout.close()
                onPicked: i => {
                    const k = items[i].key
                    if (k === "read" || k === "unread") backend.setChatUnread(row.chat.id, k === "unread")
                    else if (k === "mute" || k === "unmute") backend.setChatMuted(row.chat.id, k === "mute")
                    else if (k === "link") backend.copyLinkOfChat(row.chat.id, row.chat.name)
                    else if (k === "removeFrom") backend.folderAction("remove", JSON.stringify({ item: row.chat.id, from: row.holder }))
                    else if (k === "hide" || k === "unhide") backend.setChatHidden(row.chat.id, k === "hide")
                    else if (k === "leave") row.made("leaveAsk", leaveAskComp).open()
                    else if (k === "window") root.openChatWindow(row.chat.id, row.chat.name, row.chat.peerMri || "", row.chat.presence || "")
                    else if (k === "apps") root.manageChatApps(row.chat.id, row.chat.name)
                    else if (k === "workflows") root.chatWorkflows(row.chat.id, row.chat.name)
                    else if (k === "removeHistory") row.made("removeHistoryAsk", removeHistoryAskComp).open()
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
        }
        // Manage notifications ▸ (Teams' conversation notification settings
        // popover): "Select what content notifies you", All new messages and
        // Mute ("Customized" after the current one when you changed its
        // parts), a line, Customize.
        Component {
            id: chatNotifyFlyoutComp
            Popup {
                id: chatNotifyFlyout
                padding: 4
                width: 290 + 8
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                property var state_: null
                function load() { state_ = null; backend.channelAction("chat-notify-load", "", row.chat.id, "") }
                Connections {
                    target: backend
                    enabled: chatNotifyFlyout.visible
                    function onChannelActionResultChanged() {
                        const r = JSON.parse(backend.channelActionResult || "{}")
                        if (r.op === "chat-notify-load" && r.channel === row.chat.id && r.ok) chatNotifyFlyout.state_ = r.data
                    }
                }
                readonly property string current: state_ ? state_.preset : (row.chat.muted ? "mute" : "all")
                readonly property var choices: [
                    { mode: "all", icon: "alert-on-20", label: qsTr("All new messages"), hint: qsTr("New messages, all @mentions, and replies to followed threads") },
                    { mode: "mute", icon: "alert-off-20", label: qsTr("Mute"), hint: qsTr("You'll still be notified for personal mentions and replies to followed threads") }
                ]
                contentItem: Column {
                    spacing: 2
                    Text {
                        width: 290; height: 32
                        leftPadding: 8; rightPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Select what content notifies you")
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: theme.textSecondary
                    }
                    Repeater {
                        model: chatNotifyFlyout.choices
                        Rectangle {
                            id: nChoice
                            required property var modelData
                            readonly property bool current: chatNotifyFlyout.current === modelData.mode
                            width: 290; height: 64; radius: 4
                            color: nHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { visible: nChoice.current; x: 4; y: 8; size: 16; name: "checkmark-16"; color: theme.onFill(nChoice, theme.textStrong) }
                            FluentIcon { x: 24; y: 6; size: 20; name: nChoice.modelData.icon; color: theme.onFill(nChoice, nHover.hovered ? theme.text : theme.textStrong) }
                            Column {
                                x: 50; y: 6; width: 232
                                Row {
                                    spacing: 4
                                    Text { text: nChoice.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(nChoice, nHover.hovered ? theme.text : theme.textStrong) }
                                    // Teams' "Customized" label after the
                                    // current preset.
                                    Rectangle {
                                        visible: nChoice.current && !!chatNotifyFlyout.state_ && chatNotifyFlyout.state_.customized
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: custText.implicitWidth + 8; height: 18; radius: 4
                                        color: "transparent"; border.color: theme.divider; border.width: 0.67
                                        Text { id: custText; anchors.centerIn: parent; text: qsTr("Customized"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                                    }
                                }
                                Text { width: 232; wrapMode: Text.Wrap; text: nChoice.modelData.hint; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(nChoice, theme.textSecondary) }
                            }
                            HoverHandler { id: nHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { chatNotifyFlyout.close(); row.closeMenu(); if (!nChoice.current) backend.channelAction("chat-notify", "", row.chat.id, nChoice.modelData.mode) } }
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: nChoice.current
                            Accessible.name: modelData.label
                        }
                    }
                    Item {
                        width: 290; height: 5
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: -5; width: 300; height: 0.67; color: theme.divider }
                    }
                    Rectangle {
                        id: nCustom
                        width: 290; height: 32; radius: 4
                        color: nCustomHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { x: 24; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "options-20"; color: theme.onFill(nCustom, nCustomHover.hovered ? theme.text : theme.textStrong) }
                        Text { x: 48; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Customize"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(nCustom, nCustomHover.hovered ? theme.text : theme.textStrong) }
                        HoverHandler { id: nCustomHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { chatNotifyFlyout.close(); row.closeMenu(); row.notifyDialog().start({ id: row.chat.id, name: row.chat.name, muted: !!row.chat.muted }) } }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: qsTr("Customize")
                    }
                }
            }
        }
        Component { id: chatNotifyDialogComp; ChannelNotifyDialog { chat: true; onOpenNotificationSettings: window.launchSettings("notifications") } }
        function notifyFlyoutForTest() { const m = row.menu(), f = row.flyout(); m.open(); f.parent = m.contentItem; f.x = m.width - 8; f.y = 60; f.load(); f.open() }
        function notifyCustomizeForTest() { row.notifyDialog().start({ id: row.chat.id, name: row.chat.name, muted: !!row.chat.muted }) }
        function closeMenuForTest() { row.closeMenu() }
        function menuItemsForTest() { return row.rowMenu ? row.rowMenu.items : [] }
        function leaveForTest() { return row.made("leaveAsk", leaveAskComp) }
        function removeHistoryForTest() { return row.made("removeHistoryAsk", removeHistoryAskComp) }
        // Teams' "Remove chat history?" (600 wide).
        Component {
            id: removeHistoryAskComp
            ConfirmDialog {
                width: 600
                title: qsTr("Remove chat history?")
                body: qsTr("This will remove the chat from your list and search. It affects you only.")
                confirmText: qsTr("Remove")
                onConfirmed: backend.removeChatHistory(row.chat.id)
            }
        }
        Component {
            id: leaveAskComp
            LeaveChatDialog {
                onConfirmed: removeHistory => { backend.leaveChat(row.chat.id); if (removeHistory) backend.removeChatHistory(row.chat.id) }
            }
        }
        Accessible.role: Accessible.Button
        // Teams' chat item support texts (Unread message, Muted, Meeting in progress).
        Accessible.name: [row.chat.name || ""].concat(row.unread ? [qsTr("Unread message", "simpleCollab:k6punc3yb")] : [], row.chat.muted ? [qsTr("Muted", "simpleCollab:k6txiz02a")] : [], row.chat.liveCall ? [qsTr("Meeting in progress", "simpleCollab:kaxe10mlq")] : []).join(", ")
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
        onReported: backend.toastJson = JSON.stringify({ id: Date.now(), text: qsTr("Your report was sent"), intent: "success" })
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "meeting-chat-report-info" || !r.ok || !r.data || !chatReport.opened) return
            const d = r.data
            chatReport.chatIcal = d.ical || ""
            chatReport.meeting = { title: d.title || chatReport.meeting.title, start: d.start ? theme.fmtDate(new Date(d.start), "MMM d") + ", " + theme.time(d.start) : "", organizer: d.organizer || "" }
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
            FilterMarks { query: root.nameFilter }
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
            Accessible.name: qsTr("More options for %1").arg(chRow.channel.name)
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: point => root.openChannelMenu(chRow.channel, chRow.team, chRow, point.position.x, point.position.y, chRow.dragGroup)
        }
        Accessible.role: Accessible.Button
        // Teams' channel item: name, type name (Channel) and Unread.
        Accessible.name: [chRow.channel.name, qsTr("Channel", "simpleCollab:k3vac73tj")].concat(chRow.unread ? [qsTr("Unread", "simpleCollab:k213k6al8")] : []).join(", ")
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
        Accessible.name: rbButton.up ? qsTr("Move Up") : qsTr("Move Down")
    }

    // Teams' "New" badge: brand pill, 10/14 semibold.
    component NewBadge: Rectangle {
        id: hcFill3
        width: newText.implicitWidth + 12; height: 18; radius: 9
        color: theme.brandFill
        Text { id: newText; anchors.centerIn: parent; text: qsTr("New"); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, "white") }
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
                FilterMarks { query: root.nameFilter }
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
                Accessible.name: qsTr("More team options")
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => root.openTeamMenu(teamRows.team, parent, point.position.x, point.position.y)
            }
            Accessible.role: Accessible.Button
            // Teams' team header: name and type name (Team); Teams' open state is
            // aria-expanded, which Qt's Accessible lacks, so it is spoken here.
            Accessible.name: [teamRows.team.name, qsTr("Team", "simpleCollab:k2af5wske")].join(", ") + (teamRows.open ? qsTr(", expanded") : qsTr(", collapsed"))
        }
        Repeater {
            model: teamRows.open ? teamRows.team.channels : []
            ChannelRow { required property var modelData; channel: modelData; team: teamRows.team }
        }
    }

    // A row with an icon instead of a picture (Quick views).
    // A row of its own (Copilot, a quick view, New message). A quick view
    // with unread items is bold (700, NeutralForeground1) and its count
    // shows in Teams' badge (measured on Teams web 2026-11-27: a 16 px
    // circle 12 in from the row's end, 10/600 white on the brand).
    component ListRow: Item {
        id: lr
        property string label
        property string icon
        property bool selected: false
        property bool unread: false
        property int badge: 0
        /// Mark the filter's text in the label.
        property bool marks: false
        signal clicked()
        width: list.width; height: 32
        Rectangle {
            id: lrFill
            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
            color: lr.selected ? theme.selected : (lrHover.hovered ? theme.rowHover : "transparent")
        }
        FluentIcon { x: 32; y: 6; name: lr.icon; size: 20; color: theme.onFill(lrFill, lr.selected || lr.unread ? theme.text : theme.textSecondary) }
        Text {
            x: 64; y: 6
            width: Math.min(implicitWidth, (lrBadge.visible ? lrBadge.x - 8 : parent.width - 24) - x)
            elide: Text.ElideRight
            text: lr.label
            font.family: theme.font; font.pixelSize: theme.base
            font.weight: lr.unread ? Font.Bold : Font.Normal
            color: theme.onFill(lrFill, lr.selected || lr.unread ? theme.text : theme.textSecondary)
            FilterMarks { query: lr.marks ? root.nameFilter : "" }
        }
        Rectangle {
            id: lrBadge
            visible: lr.badge > 0
            height: 16; radius: 8
            width: Math.max(16, lrBadgeText.implicitWidth + 8)
            x: parent.width - 16 - 12 - width; y: 8
            color: theme.brandFill
            Text {
                id: lrBadgeText
                anchors.centerIn: parent
                text: lr.badge > 99 ? "99+" : String(lr.badge)
                font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                color: theme.onFill(lrBadge, "white")
            }
        }
        HoverHandler { id: lrHover }
        TapHandler { onTapped: lr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: lr.badge > 0 ? lr.label + ", " + qsTr("%n unread", "", lr.badge) : lr.label
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
            Accessible.name: qsTr("More section options")
        }
        HoverHandler { id: shHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (!smHover.hovered) sh.toggled() }
        TapHandler { acceptedButtons: Qt.RightButton; enabled: sh.userSection; onTapped: ev => sh.menuRequested(ev.position.x, ev.position.y) }
        Accessible.role: Accessible.Button
        Accessible.name: sh.label + (sh.open ? qsTr(", expanded") : qsTr(", collapsed"))

    }
}
