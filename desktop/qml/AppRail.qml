import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Window

// Left app bar: icon-only buttons on a 44 px pitch, selected one marked by a
// 3 px brand bar and a filled brand-coloured icon.
Rectangle {
    id: root
    property string current: "chat"
    /// No app shown as chosen (Teams' Create team and Join a team pages).
    property bool noneChosen: false
    /// "Collapse app bar": the rail folds away, as in Teams.
    property bool collapsed: false
    /// Teams' "Show app names": labels under the icons (56 px items).
    property bool showNames: false
    /// Teams' "Auto collapse app bar": it folds away once you pick an app.
    property bool autoCollapse: false
    /// Teams' Separate view: a Teams app after Chat (Ctrl+3), the rest
    /// moved down one; Chat and Teams share the chat view.
    property bool split: false
    property string collabPane: "chats"
    signal collabPicked(string pane)
    /// A personal account (Teams for personal use): Teams free's own bar
    /// (personalApps), no app menus, no Store or View more apps, and its
    /// Upgrade button at the bottom.
    property bool personal: false
    /// What Upgrade shows (ECS core.isPremiumButtonInAppBarEnabled).
    property bool upgradeShown: true
    /// The room the other-accounts hub takes at the bottom.
    property real bottomReserve: 0
    signal upgradeRequested()
    /// Teams free's app bar (Teams desktop 26304 and teams.live.com,
    /// 2026-11-28; its app ids): Chat, Meet, People, Copilot, Communities,
    /// Calendar and Activity, fixed (no app menu, no Store). OST shows the
    /// ones it can open: Copilot is Teams' upsell page for an account
    /// without a Microsoft 365 plan and Communities its retirement page;
    /// Meet and Calendar (TASK-0298) and People (TASK-0295) join once
    /// their personal-account views are built (personalReady).
    readonly property var personalApps: [
        { key: "chat", icon: "chat", label: qsTr("Chat"), appId: "86fcd49b-61a2-4701-b771-54728cd291fb" },
        { key: "meet", icon: "video-24", label: qsTr("Meet"), appId: "40472f6e-248f-4599-842c-ff3ed8f0ae34" },
        { key: "people", icon: "contact-card-24", label: qsTr("People"), appId: "40472f6e-248f-4599-842c-ff3ed8f0ae35" },
        // Teams draws Copilot's colour mark, not a glyph.
        { key: "tfl-copilot", image: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/fre/monetization/copilot.png", label: qsTr("Copilot"), appId: "43a6e7fb-bd10-4c0a-b02e-6a9c86ba272a" },
        { key: "tfl-communities", icon: "people-community-24", label: qsTr("Communities"), appId: "3b95919f-59d8-4441-a975-2a8c2643c852" },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar"), appId: "ef56c0de-36fc-4ef8-b417-3d82ba9d073c" },
        { key: "activity", icon: "alert", label: qsTr("Activity"), appId: "14d6962d-6eeb-4f48-8890-de55454bb136" }
    ]
    /// The personal apps OST has a view for (false: left off the bar).
    property var personalReady: ({ meet: false, people: false, calendar: false })
    readonly property var personalEntries: personalApps.filter(a => personalReady[a.key] !== false)
    /// The app bar menu's Pin / Unpin (Events).
    signal pinRequested(string key, bool on)
    /// The app bar menu of an app Teams hosts (measured on winpc
    /// 2026-11-20: Open in new window, About, Share app, …): its window,
    /// its details, sharing it.
    signal popOutRequested(string key)
    signal aboutRequested(string key)
    signal shareRequested(string key)
    /// The apps whose personal page OST hosts as Teams does (key → app id).
    readonly property var hostedIds: ({
        whiteboard: "95de633a-083e-42f5-b444-a4295d8e9314", planner: "com.microsoft.teamspace.tab.planner",
        onenote: "0d820ecd-def2-4297-adad-78056cde7c78", clipchamp: "com.microsoftstream.embed.skypeteamstab",
        shifts: "42f6c1da-a241-483a-a3cc-4f5be9185951", avatars: "96a116ab-6847-4d22-90f3-f4dd6af74938"
    })
    /// Asked before an app is picked (Main's leaving: the multiselect
    /// speedbump while messages are being picked to forward); it calls
    /// back to go on.
    property var leaveGuard: null
    function pick(key) {
        if (leaveGuard && key !== current) { leaveGuard(() => pickNow(key)); return }
        pickNow(key)
    }
    function pickNow(key) {
        if (split && (key === "chat" || key === "teams")) collabPicked(key === "teams" ? "teams" : "chats")
        else current = key
        if (autoCollapse) collapsed = true
    }
    property int unreadChats: 0
    property int unreadActivity: 0
    color: theme.chrome
    width: collapsed ? 0 : theme.railWidth
    visible: !collapsed
    clip: true

    // Apps opened from "View more apps" join the rail, as in Teams.
    property var opened: []
    readonly property var extraApps: [
        { key: "planner", icon: "clipboard-task-list-ltr-24", label: qsTr("Planner"), keys: "" },
        { key: "people", icon: "people-20", label: qsTr("People"), keys: "" },
        { key: "onenote", icon: "notebook-20", label: qsTr("OneNote"), keys: "" },
        { key: "whiteboard", icon: "board-20", label: qsTr("Whiteboard"), keys: "" },
        { key: "clipchamp", icon: "video", label: qsTr("Clipchamp"), keys: "" },
        { key: "shifts", icon: "calendar-clock-20", label: qsTr("Shifts"), keys: "" },
        // An app from Teams' store shows its own outline icon (the
        // manifest's), tinted as the rail's glyphs are.
        { key: "avatars", icon: "person-20", iconUrl: avatarHost.app.outline || "", label: qsTr("Avatars"), keys: "" },
        { key: "help", icon: "question-circle-20", label: qsTr("Help"), keys: "" },
        { key: "events", icon: "ticket-diagonal-20", label: qsTr("Events"), keys: "" },
        { key: "recaps", icon: "arrow-counterclockwise-20", label: qsTr("Meeting Recaps"), keys: "" },
        // A Word, Excel or PowerPoint file open in Office for the web takes
        // the slot as its app (Teams' "Teams" choice).
        { key: "office", icon: "document-20", label: officeLabel || qsTr("Office", "nova:k71egteo9"), keys: "" }
    ]
    property string officeLabel: ""
    /// Your personal apps as Teams keeps them (api::app_bar: your
    /// aggregated entitlements with isAppBarPinned / appBarOrder): the bar
    /// shows the pinned ones by order, View more apps the rest. Empty until
    /// loaded; Teams' default bar shows meanwhile.
    property var barApps: []
    signal barChangeRequested(string appId, string op, int target)
    signal uninstallRequested(string appId, string name)
    signal customizeRequested()
    signal newMessageRequested(bool inWindow)
    signal blockBotRequested(string chatId, bool block)
    readonly property var coreWindowKeys: ["chat", "teams", "activity", "calls", "events"]
    /// A bot app's 1:1 chat with you, if you have one (Teams offers Block
    /// bot conversation only then; Unblock when its messaging is off).
    /// Blocks changed here since the bar loaded ({chat id: blocked}).
    property var botBlocks: ({})
    function botChat(a) {
        if (!a || !a.bot_chat) return null
        const b = botBlocks[a.bot_chat]
        return { id: a.bot_chat, messagingDisabled: b === undefined ? !!a.bot_blocked : b }
    }
    /// Teams' own apps' ids (async-entry module 318854) → OST's views.
    readonly property var coreKeys: ({
        "14d6962d-6eeb-4f48-8890-de55454bb136": "activity", "3b64df9d-7e97-4d9c-ac5c-2e0a5d8e6f40": "chat",
        "86fcd49b-61a2-4701-b771-54728cd291fb": "chat", "2a84919f-59d8-4441-a975-2a8c2643b741": "teams",
        "ef56c0de-36fc-4ef8-b417-3d82ba9d073c": "calendar", "20c3440d-c67e-4420-9f80-0e50c39693df": "calls",
        "5af6a76b-40fc-4ba1-af29-8f49b08e44fd": "onedrive", "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162": "copilot",
        "a63f7012-8cc9-42d5-99c3-e35f526fab17": "events", "7831feaf-c4c4-4669-ba64-ce4ea0b56d31": "people",
        "981bbfd0-5eb8-4393-8158-bfff69d2d6b5": "recaps", "5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83": "help",
        "ac40aa4a-fef1-4896-aea2-46d1c14dbfd5": "add"
    })
    // Teams' names for its own apps (the definitions say "Calling", "Meet").
    readonly property var coreLabels: ({
        activity: qsTr("Activity"), chat: qsTr("Chat"), teams: qsTr("Teams"), calendar: qsTr("Calendar"), calls: qsTr("Calls"),
        onedrive: qsTr("OneDrive"), events: qsTr("Events"), people: qsTr("People"), recaps: qsTr("Meeting Recaps"), copilot: qsTr("Copilot")
    })
    // The rail glyphs of the apps OST draws itself.
    readonly property var glyphs: ({
        activity: "alert", chat: "chat", teams: "people-team", calendar: "calendar", calls: "call", onedrive: "onedrive",
        events: "ticket-diagonal-20", people: "people-20", recaps: "arrow-counterclockwise-20", help: "question-circle-20"
    })
    /// The view an app opens in OST: Teams' own apps natively, the apps
    /// Teams hosts in OST's TeamsJS host (a key of hostedIds, else
    /// "app:<id>").
    function keyOf(id) {
        const l = (id || "").toLowerCase()
        if (coreKeys[l]) return coreKeys[l]
        for (const k in hostedIds) if (hostedIds[k].toLowerCase() === l) return k
        return "app:" + l
    }
    function idOf(key) {
        if (key.indexOf("app:") === 0) return key.substring(4)
        if (hostedIds[key]) return hostedIds[key]
        const own = barApps.find(a => keyOf(a.id) === key && inView(a.id))
        return own ? own.id : ""
    }
    function barApp(key) { const id = idOf(key).toLowerCase(); return id ? barApps.find(a => a.id.toLowerCase() === id) || null : null }
    // Chat and Teams are separate apps only in Teams' Separate view; the
    // unified one is "simple collab".
    function inView(id) {
        const l = id.toLowerCase()
        if (l === "3b64df9d-7e97-4d9c-ac5c-2e0a5d8e6f40") return !split
        if (l === "86fcd49b-61a2-4701-b771-54728cd291fb" || l === "2a84919f-59d8-4441-a975-2a8c2643b741") return split
        return true
    }
    function isPinnedApp(a) { return a.order !== null && a.order !== undefined }
    function entryFor(a) {
        const key = keyOf(a.id)
        const glyph = glyphs[key]
        return { key: key, appId: a.id, icon: glyph || "apps-20", iconUrl: glyph ? "" : (a.outline || a.icon || ""),
                 label: coreLabels[key] || a.name, keys: "", app: a }
    }
    /// The pinned apps on the bar, in Teams' order (Store keeps its own
    /// place after them).
    readonly property var pinnedEntries: barApps.filter(a => isPinnedApp(a) && inView(a.id) && keyOf(a.id) !== "add")
        .sort((a, b) => a.order - b.order).map(a => entryFor(a))
    /// The unpinned apps (View more apps), in Teams' order.
    readonly property var flyoutApps: barApps.filter(a => a.flyout && !isPinnedApp(a) && inView(a.id) && keyOf(a.id) !== "add")
    /// Apps pinned to the bar before your apps load (Events' Pin app).
    property var pinned: backend.setting("eventsAppPinned") === "true" ? ["events"] : []
    // Teams' default bar until your apps load.
    readonly property var defaultApps: (backend.personalAccount ? [
        // Teams for personal use's bar (Chat, Meet, People, Copilot,
        // Communities, Calendar, Activity), with the apps OST has.
        { key: "chat", icon: "chat", label: qsTr("Chat") },
        { key: "meet", icon: "video", label: qsTr("Meet") },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar") },
        { key: "activity", icon: "alert", label: qsTr("Activity") },
    ] : split ? [
        { key: "activity", icon: "alert", label: qsTr("Activity") },
        { key: "chat", icon: "chat", label: qsTr("Chat") },
        { key: "teams", icon: "people-team", label: qsTr("Teams") },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar") },
        { key: "calls", icon: "call", label: qsTr("Calls") },
        { key: "onedrive", icon: "onedrive", label: qsTr("OneDrive") },
    ] : [
        { key: "activity", icon: "alert", label: qsTr("Activity") },
        { key: "chat", icon: "chat", label: qsTr("Chat") },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar") },
        { key: "calls", icon: "call", label: qsTr("Calls") },
        { key: "onedrive", icon: "onedrive", label: qsTr("OneDrive") },
    ]).concat(extraApps.filter(a => pinned.indexOf(a.key) >= 0))
    // Teams' shortcuts: Ctrl+1 … the bar's apps in order.
    readonly property var barEntries: (personal ? personalEntries : barApps.length ? pinnedEntries : defaultApps)
        .map((a, i) => Object.assign({}, a, { keys: i < 9 ? "Ctrl+" + (i + 1) : "" }))
    /// The app opened from View more apps takes the one extra slot.
    readonly property var openedEntries: opened.concat(current !== "add" && current !== "more" ? [current] : [])
        .filter((k, i, all) => all.indexOf(k) === i && !barEntries.some(a => a.key === k))
        .map(k => { const a = barApp(k); return a ? entryFor(a) : extraApps.find(e => e.key === k) })
        .filter(e => !!e).slice(0, 1)
    /// Store's Unpin (Teams' appBar client preference isStoreUnpinned, kept
    /// on this device): Store then sits at the end of View more apps.
    property bool storeUnpinned: backend.setting("appBarStoreUnpinned") === "true"
    function setStoreUnpinned(on) { backend.setSetting("appBarStoreUnpinned", on ? "true" : "false"); storeUnpinned = on }
    readonly property var apps: personal ? barEntries : barEntries.concat(openedEntries).concat(storeUnpinned ? [] : [
        { key: "add", icon: "add-app", label: qsTr("Store"), keys: "", store: true }]).concat([
        { key: "more", icon: "more", label: qsTr("View more apps"), keys: "" },
    ])
    /// Teams' "Open 1st app on app bar" … (Ctrl+1 …).
    function pickAt(i) { if (i < barEntries.length) pick(barEntries[i].key) }
    // Teams keeps one slot for an app opened from View more apps: the
    // newest replaces the last.
    function openApp(key) {
        if (leaveGuard && key !== current) { leaveGuard(() => openAppNow(key)); return }
        openAppNow(key)
    }
    function openAppNow(key) {
        opened = barEntries.some(a => a.key === key) ? opened : [key]
        current = key
    }
    /// The app bar menu of an app, as Teams builds it (TileContextMenu,
    /// measured on winpc 2026-11-20): Open in new window | About, Share
    /// app, the app's own actions | Move up, Move down, Pin or Unpin |
    /// Uninstall | Customize app bar. View more apps' rows have no
    /// Customize app bar and no moves.
    function menuFor(entry, inBar) {
        const a = entry.app || barApp(entry.key)
        const groups = []
        // (Teams free's app bar has no app menu.)
        if (entry.key === "more" || personal) return []
        if (entry.store) return inBar
            ? [[{ key: "unpinStore", label: qsTr("Unpin"), icon: "nmc-unpin" }], [{ key: "customize", label: qsTr("Customize app bar"), icon: "nmc-settings" }]]
            : [[{ key: "pinStore", label: qsTr("Pin"), icon: "nmc-pin" }]]
        // OST opens a hosted app's page in a window of its own, and Teams'
        // own apps its ECS core.allowedCoreAppsPopOut names (simple collab,
        // chat, channel, activity, calling, events).
        if (!!hostedIds[entry.key] || entry.key.indexOf("app:") === 0 || entry.key === "copilot" || coreWindowKeys.indexOf(entry.key) >= 0)
            groups.push([{ key: "popOut", label: qsTr("Open in new window"), icon: "open-window-20" }])
        const g2 = []
        if (a && !a.core) {
            g2.push({ key: "about", label: qsTr("About"), icon: "info-20" })
            g2.push({ key: "share", label: qsTr("Share app"), icon: "share-invite-20" })
            const bc = botChat(a)
            if (bc) g2.push(bc.messagingDisabled
                ? { key: "unblockBot", label: qsTr("Unblock bot conversation"), icon: "prohibited-20" }
                : { key: "blockBot", label: qsTr("Block bot conversation"), icon: "prohibited-20" })
        }
        if (entry.key === "chat") {
            g2.push({ key: "newMessage", label: qsTr("New message"), icon: "compose-20", keys: "Ctrl+N" })
            g2.push({ key: "newMessageWindow", label: qsTr("New message in new window"), icon: "window-new-24", keys: "Ctrl+Shift+N" })
        }
        if (g2.length) groups.push(g2)
        const g3 = []
        const on = a ? isPinnedApp(a) : pinned.indexOf(entry.key) >= 0
        if (inBar && on && barApps.length) {
            const i = barEntries.findIndex(e => e.key === entry.key)
            if (i > 0) g3.push({ key: "up", label: qsTr("Move up"), icon: "arrow-up-20" })
            if (i >= 0 && i < barEntries.length - 1) g3.push({ key: "down", label: qsTr("Move down"), icon: "arrow-down-20" })
        }
        if (a || entry.key === "events")
            g3.push(on ? { key: "unpin", label: qsTr("Unpin"), icon: "nmc-unpin" } : { key: "pin", label: qsTr("Pin"), icon: "nmc-pin" })
        if (g3.length) groups.push(g3)
        if (a && a.can_uninstall) groups.push([{ key: "uninstall", label: qsTr("Uninstall"), icon: "delete-20" }])
        if (inBar) groups.push([{ key: "customize", label: qsTr("Customize app bar"), icon: "nmc-settings" }])
        return groups
    }
    function flatMenu(groups) {
        const out = []
        groups.forEach((g, i) => { if (i > 0) out.push({ separator: true }); g.forEach(e => out.push(e)) })
        return out
    }
    function runMenu(entry, k) {
        const a = entry.app || barApp(entry.key)
        const id = a ? a.id : idOf(entry.key)
        if (k === "unpinStore" || k === "pinStore") setStoreUnpinned(k === "unpinStore")
        else if (k === "popOut") popOutRequested(entry.key)
        else if (k === "about") aboutRequested(entry.key)
        else if (k === "share") shareRequested(entry.key)
        else if (k === "newMessage") newMessageRequested(false)
        else if (k === "newMessageWindow") newMessageRequested(true)
        else if (k === "customize") customizeRequested()
        else if (k === "blockBot" || k === "unblockBot") { const bc = botChat(a); if (bc) blockBotRequested(bc.id, k === "blockBot") }
        else if (k === "uninstall") uninstallRequested(id, a ? a.name : entry.label)
        else if (k === "pin" || k === "unpin") {
            if (!a) { pinRequested(entry.key, k === "pin"); return }
            barChangeRequested(id, k, 0)
        } else if (k === "up" || k === "down") {
            // Teams moves an app to its neighbour's place (reorderApp).
            const i = barEntries.findIndex(e => e.key === entry.key)
            const n = barEntries[k === "up" ? i - 1 : i + 1]
            if (n && n.app) barChangeRequested(id, "move", n.app.order)
        }
    }

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    Column {
        y: 0
        width: parent.width
        spacing: root.showNames ? 0 : 4
        Repeater {
            id: railRepeater
            model: root.apps
            delegate: Item {
                id: railItem
                required property var modelData
                readonly property bool selected: !root.noneChosen && (root.split && (modelData.key === "chat" || modelData.key === "teams")
                    ? root.current === "chat" && root.collabPane === (modelData.key === "teams" ? "teams" : "chats")
                    : root.current === modelData.key)
                width: root.width; height: root.showNames ? 56 : 40
                // With app names (Teams, measured): the chosen app's whole 68 x 56
                // item is filled, its bar 3 x 47, the label 10 px under the icon.
                Rectangle {
                    id: hcFill2
                    // High contrast fills the selected app's whole 68 x 44 item
                    // with #1AEBFF (Teams, measured), names or not.
                    visible: (root.showNames || theme.highContrast) && (parent.selected || hover.hovered && root.showNames)
                    anchors.fill: parent
                    color: parent.selected ? theme.hc(theme.surface, theme.hcHighlight) : theme.hover
                }
                Rectangle {
                    visible: parent.selected
                    width: 3; height: root.showNames ? 47 : 32; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.highContrast ? "#000000" : theme.brand
                }
                Rectangle {
                    id: hcFill1
                    visible: !root.showNames
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: theme.radius
                    color: hover.hovered && !parent.selected ? theme.hover : "transparent"
                }
                // A colour app mark (Teams free's Copilot), 24 px.
                Image {
                    visible: !!modelData.image
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.showNames ? 8 : (parent.height - height) / 2
                    width: 24; height: 24; sourceSize: Qt.size(48, 48)
                    source: modelData.image || ""
                    asynchronous: true; smooth: true
                }
                FluentIcon {
                    visible: !modelData.iconUrl && !modelData.image
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.showNames ? 8 : (parent.height - height) / 2
                    size: 24
                    name: modelData.iconUrl || modelData.image ? "" : parent.selected ? modelData.icon + "-filled" : modelData.icon
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.icon)
                }
                Image {
                    id: appOutline
                    visible: false
                    width: 20; height: 20
                    source: modelData.iconUrl || ""
                    sourceSize: Qt.size(48, 48)
                    smooth: true
                    layer.enabled: true
                }
                // (The icon's shape as a mask over the glyph colour.)
                Rectangle {
                    id: appOutlineFill
                    visible: false
                    width: 20; height: 20
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.icon)
                    layer.enabled: true
                }
                MultiEffect {
                    visible: !!modelData.iconUrl
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.showNames ? 10 : (parent.height - height) / 2
                    // Teams draws an app's outline icon 20 px (its manifest's
                    // smallImage, tinted by an SVG filter).
                    width: 20; height: 20
                    source: appOutlineFill
                    maskEnabled: true
                    maskSource: appOutline
                }
                Text {
                    visible: root.showNames && modelData.key !== "more"
                    x: 4; y: 34; width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.label
                    font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.textSecondary)
                }
                Rectangle {
                    id: hcFill3
                    readonly property int count: modelData.key === "chat" ? root.unreadChats
                        : modelData.key === "activity" ? root.unreadActivity : 0
                    visible: count > 0
                    x: parent.width / 2 + 4; y: 6
                    width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
                    color: theme.badge
                    border.color: theme.chrome; border.width: 1
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: parent.count
                        color: theme.onFill(hcFill3, "white")
                        font.family: theme.font; font.pixelSize: theme.caption; font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: modelData.key === "more" ? moreApps.open() : root.pick(modelData.key) }
                // Teams' app bar menu (TileContextMenu): beside the bar,
                // centred on the tile ("after", align center), kept in the
                // window.
                TapHandler {
                    enabled: modelData.key !== "more"
                    acceptedButtons: Qt.RightButton
                    onTapped: railItem.openMenu()
                }
                function openMenu() {
                    railMenu.entries = root.flatMenu(root.menuFor(modelData, true))
                    if (!railMenu.entries.length) return
                    railMenu.parent = root.Window.contentItem
                    const p = railItem.mapToItem(root.Window.contentItem, 0, 0)
                    railMenu.x = p.x + root.width
                    railMenu.y = Math.max(0, Math.min(p.y + railItem.height / 2 - railMenu.implicitHeight / 2, root.Window.height - railMenu.implicitHeight))
                    railMenu.open()
                }
                MenuPopup {
                    id: railMenu
                    property var entries: []
                    items: entries
                    onPicked: i => root.runMenu(modelData, entries[i].key)
                }
                function menuForTest() { openMenu(); return railMenu.entries.map(e => e.separator ? "|" : e.label) }
                function closeMenu() { railMenu.close() }
                function pickForTest(label) { const i = railMenu.entries.findIndex(e => e.label === label); if (i < 0) return false; railMenu.close(); root.runMenu(modelData, railMenu.entries[i].key); return true }
                ToolTipLabel { text: modelData.keys ? qsTr("%1 (%2)").arg(modelData.label).arg(modelData.keys) : modelData.label; shown: hover.hovered }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.keys ? qsTr("%1 (%2)").arg(modelData.label).arg(modelData.keys) : modelData.label
            }
        }
    }

    // Teams free's Upgrade (data-testid premium-upgrade-button; Teams
    // desktop 26304, 2026-11-28): the diamond at the bottom of the bar,
    // over the other-accounts hub, 68 x 44 like the apps; it opens
    // Settings ▸ Plans and upgrades and Teams' purchase offer.
    Item {
        id: upgrade
        visible: root.personal && root.upgradeShown
        width: root.width; height: 44
        y: root.height - root.bottomReserve - height - 4
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 40; radius: theme.radius
            color: uh.hovered ? theme.hover : "transparent"
        }
        FluentIcon {
            anchors.centerIn: parent
            size: 24
            name: uh.hovered ? "diamond-24-filled" : "diamond-24"
            color: uh.hovered ? theme.brand : theme.icon
        }
        HoverHandler { id: uh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.upgradeRequested() }
        ToolTipLabel { text: qsTr("Upgrade"); shown: uh.hovered }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Upgrade")
        Accessible.onPressAction: root.upgradeRequested()
    }
    function upgradeForTest() { return upgrade }

    // View more apps: Teams' flyout (measured on winpc 2026-11-20): 300
    // wide, centred on the button and kept in the window; a 268 x 32 search
    // box 15 in and 13 down; your unpinned apps in Teams' order, rows 269 x
    // 40 on a 42 px pitch (eight in view, the rest scroll), each the app's
    // colour icon (Teams' own apps a bordered glyph tile) and its name; an
    // unpinned Store last under a divider. Each row has the app's menu.
    readonly property var fallbackFlyout: [
        { key: "shifts", label: qsTr("Shifts"), icon: "calendar-clock-20" },
        { key: "planner", label: qsTr("Planner"), icon: "clipboard-task-list-ltr-24" },
        { key: "onenote", label: qsTr("OneNote"), icon: "notebook-20" },
        { key: "help", label: qsTr("Help"), icon: "question-circle-20" },
        { key: "clipchamp", label: qsTr("Clipchamp"), icon: "video" },
        { key: "whiteboard", label: qsTr("Whiteboard"), icon: "board-20" },
        { key: "events", label: qsTr("Events"), icon: "ticket-diagonal-20" },
        { key: "people", label: qsTr("People"), icon: "people-20" },
        { key: "avatars", label: qsTr("Avatars"), icon: "person-20" }
    ]
    readonly property var flyoutEntries: barApps.length
        ? flyoutApps.map(a => { const e = entryFor(a); return Object.assign(e, { tile: a.core ? "" : (a.icon || "") }) })
        : fallbackFlyout
    function openFlyout() { moreApps.open() }
    function repeaterForTest() { return railRepeater }
    function closeMenusForTest() {
        for (let i = 0; i < railRepeater.count; i++) { const it = railRepeater.itemAt(i); if (it) it.closeMenu() }
        flyoutMenu.close(); moreApps.close()
    }
    Popup {
        id: moreApps
        parent: root.Window.contentItem
        x: root.width
        // Centred on View more apps, kept in the window.
        function place() {
            let button = null
            for (let i = 0; i < railRepeater.count; i++) { const it = railRepeater.itemAt(i); if (it && it.modelData.key === "more") button = it }
            if (!button) return
            const p = button.mapToItem(root.Window.contentItem, 0, 0)
            y = Math.max(8, Math.min(p.y + button.height / 2 - height / 2, root.Window.height - height - 8))
        }
        onAboutToShow: place()
        onHeightChanged: if (visible) place()
        width: 300; padding: 0
        height: listView.y + listView.height + (storeRow.visible ? 1 + 8 + 42 : 0) + 11
        onOpened: { appSearch.text = ""; appSearch.forceActiveFocus() }
        background: FluentSurface { depth: 16; radius: 8; color: theme.menu }
        readonly property var shown: root.flyoutEntries.filter(a => !appSearch.text || a.label.toLowerCase().indexOf(appSearch.text.toLowerCase()) >= 0)
        contentItem: Item {
            // Teams' filled search box: grey, a brand line under it while
            // focused.
            Rectangle {
                x: 15; y: 13; width: 268; height: 32; radius: theme.radius
                color: theme.inputFilledDark
                Rectangle { visible: appSearch.activeFocus; anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1; color: theme.brand }
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
                TextInput {
                    id: appSearch
                    x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !appSearch.text; text: qsTr("Search apps"); color: theme.textSecondary; font: appSearch.font }
                    Keys.onEscapePressed: moreApps.close()
                    Accessible.name: qsTr("Search apps")
                }
            }
            ListView {
                id: listView
                x: 13; y: 55; width: 271
                height: Math.max(40, Math.min(count, 8) * 42 - 2)
                clip: true; spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: moreApps.shown
                delegate: FlyoutRow { required property var modelData; entry: modelData }
            }
            Rectangle { visible: storeRow.visible; x: 15; y: listView.y + listView.height + 4; width: 268; height: 1; color: theme.dividerSoft }
            FlyoutRow {
                id: storeRow
                visible: root.storeUnpinned && !appSearch.text
                x: 13; y: listView.y + listView.height + 9
                entry: ({ key: "add", icon: "add-app", label: qsTr("Store"), store: true })
            }
        }
    }
    /// The open row menu of View more apps (Teams' flyout TileContextMenu).
    MenuPopup {
        id: flyoutMenu
        property var entry: null
        property var entries: []
        parent: root.Window.contentItem
        items: entries
        onPicked: i => { const e = entry, k = entries[i].key; moreApps.close(); root.runMenu(e, k) }
    }
    function flyoutMenuForTest(key) {
        const e = flyoutEntries.find(f => f.key === key) || (key === "add" ? { key: "add", label: qsTr("Store"), store: true } : null)
        if (!e) return []
        return flatMenu(menuFor(e, false)).map(x => x.separator ? "|" : x.label)
    }
    function flyoutPickForTest(key, label) {
        const e = flyoutEntries.find(f => f.key === key) || (key === "add" ? { key: "add", label: qsTr("Store"), store: true } : null)
        if (!e) return false
        const m = flatMenu(menuFor(e, false)).find(x => x.label === label)
        if (!m) return false
        runMenu(e, m.key)
        return true
    }
    component FlyoutRow: Rectangle {
        id: row
        property var entry: ({})
        width: 269; height: 40; radius: theme.radius
        color: rowHover.hovered ? theme.rowHover : "transparent"
        // A platform app's colour icon; Teams' own apps a 28 px tile with
        // a hairline edge around the glyph.
        Rectangle {
            visible: !row.entry.tile
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 6
            color: theme.surface; border.color: theme.stroke; border.width: 1
            FluentIcon { anchors.centerIn: parent; name: row.entry.icon || "apps-20"; size: 20; color: theme.onFill(row, theme.text) }
        }
        Image {
            visible: !!row.entry.tile
            x: 6; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; sourceSize: Qt.size(48, 48)
            source: row.entry.tile || ""
            fillMode: Image.PreserveAspectFit; smooth: true
        }
        Text {
            x: 42; width: parent.width - 50; anchors.verticalCenter: parent.verticalCenter
            text: row.entry.label || ""; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(row, theme.text)
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                moreApps.close()
                if (row.entry.store) root.pick("add")
                else root.openApp(row.entry.key)
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: ev => {
                flyoutMenu.entry = row.entry
                flyoutMenu.entries = root.flatMenu(root.menuFor(row.entry, false))
                if (!flyoutMenu.entries.length) return
                const p = row.mapToItem(root.Window.contentItem, ev.position.x, ev.position.y)
                flyoutMenu.x = p.x
                flyoutMenu.y = Math.max(0, Math.min(p.y - flyoutMenu.implicitHeight / 2, root.Window.height - flyoutMenu.implicitHeight))
                flyoutMenu.open()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: entry.label || ""
    }

    // Teams' tooltip: white, hairline border, 12 px text, beside the button.
    component ToolTipLabel: Rectangle {
        property string text
        property bool shown
        visible: shown
        x: parent.width - 6; y: parent.height / 2 - height / 2 - 14
        width: tip.implicitWidth + 22; height: 26; radius: theme.radius
        color: theme.menu; z: 10
        border.color: theme.divider
        Text { id: tip; anchors.centerIn: parent; text: parent.text; color: theme.text; font.family: theme.font; font.pixelSize: theme.small }
    }
}
