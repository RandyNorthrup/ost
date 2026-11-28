import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Teams' "Activity in other accounts and orgs" (MTMA hub v2; measured on
// winpc 2026-11-22 with OST Test 2 added to ost-test1): at the bottom of
// the app bar, a 52 x 48 tile (radius 8, the PersonAlert glyph 24 #616161,
// filled brand while hovered or open) with a red count of the other
// accounts' activity; it opens a 380 wide flyout beside the bar, its
// bottom on the tile's: the title (14/600, 16 in, a NeutralStroke2 rule
// under it), the Unread / Channels / Chats pills and Filter, then each other
// account as an accordion (picture with its count, name 14/600, address
// 12, Account settings ···) over its recent activity and chats (unread
// ones bold with a dot; a missed call has Call and Chat), and "Scroll to see
// more" while there is more below. Picking one opens it in that account's
// window. Each account's window publishes its own summary (Main.qml's
// hubPublisher, backend.publishHub); this reads the others'.
//
// An org pinned from it ("Pin this org", at most two) gets a tile of its
// own above the hub's (Teams' launch tile: the org's 28 px square
// initial, its count) and leaves the hub; the tile opens the same
// flyout for that org alone, under its header (picture, name, address,
// Tenant settings: Switch / Unpin this org). This account's own org,
// pinned from another account's window, is the "Current org" tile.
Item {
    id: root
    width: 68; height: 48 * (1 + pinned.length)
    /// [{profile, upn, name, org, objectId, running, missed, items, pinned}]
    property var accounts: []
    /// The pinned orgs, in pin order (another account's entry, or this
    /// one's {current: true, …}).
    property var pinned: []
    /// The accounts the hub itself lists (pinned orgs have their own tile).
    readonly property var hubAccounts: accounts.filter(a => !a.pinned)
    readonly property int missed: hubAccounts.reduce((n, a) => n + (a.missed || 0), 0)
    readonly property bool open: (flyout.opened && !flyout.tenant) || simpleFlyout.opened
    property string pill: ""        // "unread" | "channels" | "chats"
    property string filter: ""      // "mention" | "tagMention" | "followed"
    property var hiddenOrgs: []     // the Orgs filter's unticked ones (profiles)
    property var collapsed: []      // accordions closed (profiles)
    function refresh() {
        try { accounts = JSON.parse(backend.otherAccountsHubJson()) } catch (e) { accounts = [] }
        try { pinned = JSON.parse(backend.pinnedOrgsJson()) } catch (e) { pinned = [] }
        // (an open org flyout follows its account's latest summary)
        if (flyout.tenant) {
            const t = pinned.find(p => p.upn === flyout.tenant.upn)
            if (t) flyout.tenant = t
            else flyout.close()
        }
    }
    function show() { if (simple) { simpleFlyout.openBeside(); return } refresh(); flyout.tenant = null; flyout.openBeside() }
    function showOrg(account) { refresh(); flyout.tenant = account; flyout.openBeside() }
    function hide() { flyout.close(); simpleFlyout.close() }
    function pinOrg(account, on) {
        backend.setOrgPinned(account.upn, on)
        refresh()
    }
    // (--pin-org)
    function pinFirstForTest() { const a = hubAccounts[0]; if (a) pinOrg(a, true); return a ? a.upn : "" }
    function unpinAllForTest() { pinned.forEach(p => backend.setOrgPinned(p.upn, false)); refresh() }
    function orgFlyoutForTest(i) { const p = pinned[i || 0]; if (p) showOrg(p); return !!p }
    function tenantMenuForTest() { tenantMenu.open() }
    function pinStateForTest() {
        return { tiles: pinned.map((p, i) => ({ upn: p.upn, org: p.org, current: !!p.current, missed: p.missed || 0, y: i * 48 })),
                 hubAccounts: hubAccounts.map(a => a.upn), hubMissed: missed, height: root.height,
                 flyout: flyout.opened ? { tenant: flyout.tenant ? flyout.tenant.upn : "", x: Math.round(flyout.x), y: Math.round(flyout.y), w: Math.round(flyout.width), h: Math.round(flyout.height),
                     items: flyout.tenant ? root.shown(flyout.tenant.items).length : -1, empty: emptyState.visible } : null }
    }
    // (--setj-hub)
    function filterForTest() { filterMenu.open() }
    function orgsForTest() { orgsMenu.open() }
    function orgMenuForTest() { orgMenu.account = hubAccounts[0] || {}; orgMenu.y = 113.33 + 48 + 2; orgMenu.open(); switchMenu.open() }
    function closeMenusForTest() { switchMenu.close(); orgMenu.close(); orgsMenu.close(); filterMenu.close() }
    function stateForTest() {
        return { open: flyout.opened, x: Math.round(flyout.x), y: Math.round(flyout.y), w: Math.round(flyout.width), h: Math.round(flyout.height), missed: missed, footer: footer.visible,
            accounts: accounts.map(a => ({ profile: a.profile, upn: a.upn, running: a.running, missed: a.missed, items: (a.items || []).length, shown: shown(a.items).length, first: (a.items || []).slice(0, 4).map(i => (i.unread ? "*" : "") + i.kind + ":" + i.title + " / " + (i.subtitle || "") + " @" + when(i.time)) })) }
    }
    function pickFirstChatForTest() {
        const a = accounts[0]
        const it = a ? (a.items || []).find(i => i.kind === "chat") : null
        if (it) pick(a, it)
        return it ? it.title : ""
    }
    Component.onCompleted: refresh()
    // Each account's window rewrites its summary as its activity changes.
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }

    // The items a pill and the filter leave.
    function shown(items) {
        return (items || []).filter(i =>
            (root.pill !== "unread" || i.unread)
            && (root.pill !== "channels" || i.channel)
            && (root.pill !== "chats" || (i.kind === "chat" && !i.channel))
            && (!root.filter || (i.kind === "activity" && (root.filter === "followed" ? i.activity === "reply" : i.activity === root.filter))))
    }
    function when(t) {
        const d = new Date(t), now = new Date()
        if (isNaN(d.getTime())) return ""
        // Teams: the time within the last day, else the date.
        return now - d < 24 * 3600 * 1000 ? theme.time(d) : theme.dateNoYear(d)
    }
    function pick(account, item) {
        flyout.close()
        if (item.kind === "chat") backend.openInAccount(account.profile, item.id, item.title)
        else if (item.thread) backend.openInAccount(account.profile, item.thread, item.subtitle || item.actorName || "")
        else if (item.actorOid) backend.openInAccount(account.profile, "chatwith:" + item.actorOid, item.actorName || "")
        else backend.switchAccount(account.profile)
    }

    // ---- the pinned orgs' tiles (Teams' launch tile, measured on winpc
    // 2026-11-22: 52 x 48 at 8, radius 8, white while open; the org's
    // colourful 28 px square initial (radius 4) at 12, 10; its count at
    // 30, 4; the tooltip the org's name, or "Current org") ----
    Repeater {
        model: root.pinned
        Rectangle {
            id: pinTile
            required property var modelData
            required property int index
            readonly property bool isOpen: flyout.opened && !!flyout.tenant && flyout.tenant.upn === modelData.upn
            readonly property string orgName: modelData.personal ? qsTr("Personal") : (modelData.org || modelData.upn || "")
            readonly property string tip: modelData.current ? qsTr("Current org") : orgName
            x: 8; y: index * 48; width: 52; height: 48; radius: 8
            color: isOpen ? theme.surface : pinHover.hovered ? theme.hover : "transparent"
            Avatar {
                x: 12; y: 10; size: 28
                name: pinTile.orgName
                initialsText: pinTile.orgName.charAt(0).toUpperCase()
                colorful: true; square: true; squareRadius: 4
            }
            Rectangle {
                id: pinBadge
                visible: (pinTile.modelData.missed || 0) > 0
                x: 30; y: 4
                width: Math.max(16, pinCount.implicitWidth + 8); height: 16; radius: 8
                color: theme.hc("#D13438", "#FFFFFF")
                Text { id: pinCount; anchors.centerIn: parent; text: pinTile.modelData.missed || 0; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(pinBadge, "#FFFFFF") }
            }
            HoverHandler { id: pinHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pinTile.isOpen ? flyout.close() : root.showOrg(pinTile.modelData) }
            Accessible.role: Accessible.Button
            Accessible.name: tip + ((modelData.missed || 0) > 0 ? " " + modelData.missed : "")
            activeFocusOnTab: true
            Keys.onSpacePressed: root.showOrg(modelData)
            Keys.onReturnPressed: root.showOrg(modelData)
            // Its tooltip, after the tile.
            Rectangle {
                visible: pinHover.hovered && !pinTile.isOpen
                parent: root.Window.contentItem
                readonly property point at: pinTile.mapToItem(root.Window.contentItem, root.width - 8, 0)
                x: at.x + 2; y: at.y + pinTile.height / 2 - height / 2
                z: 20
                width: pinTip.implicitWidth + 22; height: 26; radius: 4
                color: theme.menu; border.color: theme.divider; border.width: 0.67
                Text { id: pinTip; anchors.centerIn: parent; text: pinTile.tip; color: theme.text; font.family: theme.font; font.pixelSize: 12 }
            }
        }
    }

    // ---- the app bar tile ----
    Rectangle {
        id: tile
        x: 8; y: root.height - 48; width: 52; height: 48; radius: 8
        color: root.open ? theme.surface : tileHover.hovered ? theme.hover : "transparent"
        FluentIcon {
            x: 14; y: 12; size: 24
            name: root.open || tileHover.hovered ? "person-alert-24-filled" : "person-alert-24"
            color: theme.onFill(tile, root.open || tileHover.hovered ? theme.brand : theme.textSecondary)
        }
        Rectangle {
            id: countBadge
            visible: root.missed > 0
            x: 26; y: 0
            width: Math.max(16, countText.implicitWidth + 8); height: 16; radius: 8
            color: theme.hc("#D13438", "#FFFFFF")
            Text { id: countText; anchors.centerIn: parent; text: root.missed; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(countBadge, "#FFFFFF") }
        }
        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.open ? (flyout.close(), simpleFlyout.close()) : root.show() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Activity in other accounts and orgs") + (root.missed > 0 ? " " + root.missed : "")
        activeFocusOnTab: true
        Keys.onSpacePressed: root.show()
        Keys.onReturnPressed: root.show()
    }
    // Teams' tooltip, after the tile.
    Rectangle {
        visible: tileHover.hovered && !root.open
        parent: root.Window.contentItem
        readonly property point at: tile.mapToItem(root.Window.contentItem, root.width - 8, 0)
        x: at.x + 2; y: at.y + tile.height / 2 - height / 2
        z: 20
        width: tipText.implicitWidth + 22; height: 26; radius: 4
        color: theme.menu; border.color: theme.divider; border.width: 0.67
        Text { id: tipText; anchors.centerIn: parent; text: qsTr("Activity in other accounts and orgs"); color: theme.text; font.family: theme.font; font.pixelSize: 12 }
    }


    // ---- a personal account's flyout (Teams for personal use, Teams
    // desktop 26304 with OST Personal 2, 2026-11-27/28): simpler than a
    // work account's: 340 wide, its bottom on the tile's; the title
    // (14/600, 16 in) over a rule; each other account as one row (the
    // org's 32 px square initial with its count, the org's name 14/600 and
    // the address 12, Switch and Pin), then a line per kind of activity
    // waiting there ("Unread chat messages", with its glyph in a 24 px
    // circle). Switch, or a line, opens that account's window. ----
    readonly property bool simple: backend.personalAccount
    /// The kinds of activity an account has waiting, as Teams words them.
    function kinds(a) {
        const items = (a.items || []).filter(i => i.unread)
        const out = []
        if (items.some(i => i.kind === "chat")) out.push({ icon: "chat-20", label: qsTr("Unread chat messages") })
        if (items.some(i => i.kind === "activity" && i.activity === "mention")) out.push({ icon: "mention-20", label: qsTr("Mentions") })
        if (items.some(i => i.kind === "call" || i.activity === "missedCall")) out.push({ icon: "call-missed-20", label: qsTr("Missed calls") })
        if (!out.length && (a.missed || 0) > 0) out.push({ icon: "alert-20", label: qsTr("New activity") })
        return out
    }
    function simpleStateForTest() { return { open: simpleFlyout.opened, w: Math.round(simpleFlyout.width), h: Math.round(simpleFlyout.height), rows: hubAccounts.map(a => ({ upn: a.upn, org: a.org, kinds: kinds(a).map(k => k.label) })) } }
    Popup {
        id: simpleFlyout
        parent: root.Window.contentItem
        width: 340; padding: 0
        // At most ~0.7 of the window, as the work flyout; more scrolls.
        readonly property real maxHeight: Math.max(200, root.Window.height * 0.702)
        height: Math.min(simpleCol.implicitHeight, maxHeight)
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        function openBeside() {
            root.refresh()
            const p = root.mapToItem(root.Window.contentItem, 0, 0)
            x = p.x + root.width + 2
            open()
            y = Math.max(0, p.y + root.height - height)
        }
        onHeightChanged: if (opened) { const p = root.mapToItem(root.Window.contentItem, 0, 0); y = Math.max(0, p.y + root.height - height) }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Flickable {
        implicitHeight: simpleCol.implicitHeight
        contentHeight: simpleCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: simpleCol
            width: 340
            Item {
                width: parent.width; height: 54
                Text { x: 16.67; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Activity in other accounts and orgs"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
            }
            Rectangle { width: parent.width; height: 0.67; color: theme.divider }
            Repeater {
                model: root.hubAccounts
                Column {
                    id: sa
                    required property var modelData
                    readonly property string orgName: modelData.personal ? qsTr("Personal") : (modelData.org || modelData.upn || "")
                    width: simpleCol.width
                    Item {
                        width: parent.width; height: 64
                        Avatar {
                            x: 16; y: 20; size: 32
                            name: sa.orgName
                            initialsText: sa.orgName.charAt(0).toUpperCase()
                            colorful: true; square: true; squareRadius: 4
                        }
                        Rectangle {
                            id: saBadge
                            visible: (sa.modelData.missed || 0) > 0
                            x: 36; y: 14
                            width: Math.max(16, saCount.implicitWidth + 8); height: 16; radius: 8
                            color: theme.hc("#D13438", "#FFFFFF")
                            Text { id: saCount; anchors.centerIn: parent; text: sa.modelData.missed || 0; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(saBadge, "#FFFFFF") }
                        }
                        Text { x: 64; y: 17; width: 150; elide: Text.ElideRight; text: sa.orgName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { x: 64; y: 35; width: 150; elide: Text.ElideRight; text: sa.modelData.upn || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        Rectangle {
                            id: switchBtn
                            x: 222; y: 21; width: 56; height: 30; radius: 4
                            color: swh.hovered ? theme.rowHover : theme.surface
                            border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 1
                            Text { anchors.centerIn: parent; text: qsTr("Switch"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(switchBtn, theme.text) }
                            HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { simpleFlyout.close(); backend.switchAccount(sa.modelData.profile) } }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Switch to %1").arg(sa.orgName)
                        }
                        HubIconButton {
                            x: 287; y: 20
                            icon: "pin-20"; label: qsTr("Pin this org")
                            onClicked: root.pinOrg(sa.modelData, true)
                        }
                    }
                    Repeater {
                        model: root.kinds(sa.modelData)
                        Rectangle {
                            id: kindRow
                            required property var modelData
                            x: 9; width: sa.width - 18; height: 42; radius: 4
                            color: krh.hovered ? theme.rowHover : "transparent"
                            Rectangle {
                                x: 11; anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24; radius: 12
                                color: theme.pick("#EBEBFF", "#2F2F4A", "#000000")
                                FluentIcon { anchors.centerIn: parent; name: kindRow.modelData.icon; size: 14; color: theme.brand }
                            }
                            Text { x: 47; anchors.verticalCenter: parent.verticalCenter; text: kindRow.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(kindRow, theme.text) }
                            HoverHandler { id: krh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { simpleFlyout.close(); backend.switchAccount(sa.modelData.profile) } }
                            Accessible.role: Accessible.Button
                            Accessible.name: kindRow.modelData.label
                        }
                    }
                    Item { width: 1; height: 6 }
                }
            }
        }
        }
    }

    // ---- the flyout ----
    Popup {
        id: flyout
        /// A pinned org's flyout (its account's entry), else the hub's.
        property var tenant: null
        // The hub's title (rule at 56.67) or the org's header (72.67, a
        // NeutralStroke1 rule); the pills 16 under it, the list 40 under those.
        readonly property real top: tenant ? 72.67 : 56.67
        readonly property real listTop: top + 56.67
        parent: root.Window.contentItem
        width: 380; padding: 0
        // At most ~0.7 of the window; taller content scrolls over a footer.
        readonly property real maxHeight: Math.max(200, root.Window.height * 0.702)
        readonly property real contentH: emptyState.visible ? 362.67 : list.contentHeight
        readonly property bool scrolls: listTop + contentH > maxHeight
        height: scrolls ? maxHeight : listTop + contentH
        onClosed: { tenantMenu.close(); tenant = null }
        onTenantChanged: tenantMenu.close()
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        function openBeside() {
            const p = root.mapToItem(root.Window.contentItem, 0, 0)
            x = p.x + root.width + 2
            open()
            y = Math.max(0, p.y + root.height - height)
        }
        onHeightChanged: if (opened) { const p = root.mapToItem(root.Window.contentItem, 0, 0); y = Math.max(0, p.y + root.height - height) }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Item {
            id: body
            // The title, a rule under it.
            Text {
                visible: !flyout.tenant
                x: 16.67; y: 16.67; height: 24
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Activity in other accounts and orgs")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading
            }
            // A pinned org's header (Teams' hub-tenant-header, measured on
            // winpc 2026-11-22: padding 16; the org's 32 px square initial
            // with its count at 20, 0; the name 14/600 and the address
            // 12/20 NeutralForeground3 at 60; Tenant settings ···).
            Item {
                visible: !!flyout.tenant
                width: parent.width; height: 72.67
                readonly property var t: flyout.tenant || ({})
                readonly property string orgName: t.org || t.upn || ""
                Avatar {
                    x: 16; y: 20; size: 32
                    name: parent.orgName
                    initialsText: parent.orgName.charAt(0).toUpperCase()
                    colorful: true; square: true; squareRadius: 4
                }
                Rectangle {
                    id: orgBadge
                    visible: (parent.t.missed || 0) > 0
                    x: 36; y: 16
                    width: Math.max(16, orgCount.implicitWidth + 8); height: 16; radius: 8
                    color: theme.hc("#D13438", "#FFFFFF")
                    Text { id: orgCount; anchors.centerIn: parent; text: orgBadge.parent.t.missed || 0; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(orgBadge, "#FFFFFF") }
                }
                Text { x: 60; y: 16; width: 258.67; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: parent.orgName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
                Text { x: 60; y: 36; width: 258.67; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: parent.t.upn || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                HubIconButton {
                    id: tenantSettings
                    x: 338.67; y: 24.67
                    icon: "more-horizontal-20"; label: qsTr("Tenant settings")
                    down: tenantMenu.opened
                    onClicked: tenantMenu.opened ? tenantMenu.close() : tenantMenu.open()
                }
            }
            Rectangle { y: flyout.top; width: parent.width; height: 0.67; color: flyout.tenant ? theme.stroke : theme.divider }
            // The pills and Filter.
            Row {
                x: 16.67; y: flyout.top + 16.67
                spacing: 8
                Repeater {
                    model: [{ key: "unread", label: qsTr("Unread") }, { key: "channels", label: qsTr("Channels") }, { key: "chats", label: qsTr("Chats") }]
                    Rectangle {
                        id: pillBox
                        required property var modelData
                        readonly property bool on: root.pill === modelData.key
                        width: pillText.implicitWidth + 17.33; height: 24; radius: 12
                        color: on ? theme.pick("#4F52B2", "#4F52B2", "#1AEBFF") : pillHover.hovered ? theme.menuHover : "transparent"
                        border.width: 0.67; border.color: on ? "transparent" : theme.stroke
                        Text { id: pillText; anchors.centerIn: parent; text: pillBox.modelData.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(pillBox, pillBox.on ? "#FFFFFF" : theme.text) }
                        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pill = pillBox.on ? "" : pillBox.modelData.key }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.checked: on
                    }
                }
            }
            HubIconButton {
                id: filterButton
                x: 339.33; y: flyout.top + 16.67
                icon: "filter-20"; label: qsTr("Filter")
                down: filterMenu.opened
                onClicked: filterMenu.opened ? filterMenu.close() : filterMenu.open()
            }
            // The accounts and their activity.
            ListView {
                id: list
                x: 0; y: flyout.listTop
                width: parent.width; height: flyout.height - y - (flyout.scrolls ? 36.67 : 0)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                model: flyout.tenant ? [flyout.tenant] : root.hubAccounts.filter(a => root.hiddenOrgs.indexOf(a.profile) < 0)
                delegate: Column {
                    id: acct
                    required property var modelData
                    readonly property bool closed: !flyout.tenant && root.collapsed.indexOf(modelData.profile) >= 0
                    readonly property var items: root.shown(modelData.items)
                    width: list.width
                    // The accordion header, Account settings beside it.
                    Item {
                        visible: !flyout.tenant
                        width: parent.width; height: visible ? 48 : 0
                    Item {
                        x: 12.67; width: 320.67; height: 48
                        FluentIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 14; name: acct.closed ? "chevron-right-16" : "chevron-down-16"; color: theme.text }
                        Avatar { x: 22; y: 8; size: 32; name: acct.modelData.name || acct.modelData.upn; photoId: acct.modelData.objectId || "" }
                        Rectangle {
                            id: acctBadge
                            visible: (acct.modelData.missed || 0) > 0
                            x: 40.4; y: 4
                            width: Math.max(16, acctCount.implicitWidth + 8); height: 16; radius: 8
                            color: theme.hc("#D13438", "#FFFFFF")
                            Text { id: acctCount; anchors.centerIn: parent; text: acct.modelData.missed || 0; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(acctBadge, "#FFFFFF") }
                        }
                        Text { x: 66; y: 4; width: 250.67; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: acct.modelData.name || acct.modelData.upn; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { x: 66; y: 24; width: 250.67; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: acct.modelData.upn; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        TapHandler {
                            onTapped: {
                                const l = root.collapsed.filter(p => p !== acct.modelData.profile)
                                if (!acct.closed) l.push(acct.modelData.profile)
                                root.collapsed = l
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: (acct.modelData.name || "") + ", " + (acct.modelData.upn || "")
                    }
                    HubIconButton {
                        id: acctSettings
                        x: 333.33; y: 16.8
                        icon: "more-horizontal-20"; label: qsTr("Account settings")
                        down: orgMenu.opened && orgMenu.account === acct.modelData
                        onClicked: {
                            orgMenu.account = acct.modelData
                            const p = acctSettings.mapToItem(body, 0, acctSettings.height)
                            orgMenu.y = p.y + 2
                            orgMenu.open()
                        }
                    }
                    }
                    // Its activity and chats.
                    Repeater {
                        model: acct.closed ? [] : acct.items
                        HubEntry {
                            required property var modelData
                            x: 12.67; width: 352.67
                            entry: modelData
                            onPicked: root.pick(acct.modelData, modelData)
                            onCallBack: { flyout.close(); backend.openInAccount(acct.modelData.profile, "callback:" + modelData.actorOid, modelData.actorName || "") }
                            onChatWith: { flyout.close(); backend.openInAccount(acct.modelData.profile, "chatwith:" + modelData.actorOid, modelData.actorName || "") }
                        }
                    }
                    Text {
                        visible: !acct.closed && acct.items.length === 0
                        x: 12.67; width: 352.67; height: 40
                        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("You're all caught up!")
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                }
            }
            // "Scroll to see more" while there is more below.
            Item {
                id: footer
                visible: flyout.scrolls
                y: parent.height - 36.67; width: parent.width; height: 36.67
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                Row {
                    visible: !list.atYEnd
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text { text: qsTr("Scroll to see more"); font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1; font.underline: moreHover.hovered }
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "arrow-down-16"; color: theme.brandForeground1 }
                    HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: list.contentY = Math.min(list.contentHeight - list.height, list.contentY + list.height * 0.8) }
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Scroll to see more")
                }
            }

            // Filter: Teams' "Filter by" popover (240 wide, at the flyout's
            // right edge under the button).
            Popup {
                id: filterMenu
                x: body.width - 240; y: filterButton.y + filterButton.height + 1.33
                width: 240; padding: 0
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                contentItem: Column {
                    Text { x: 12; height: 52; verticalAlignment: Text.AlignVCenter; text: qsTr("Filter by"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
                    Repeater {
                        model: [{ key: "mention", label: qsTr("Mentions") }, { key: "tagMention", label: qsTr("Tag mentions") }, { key: "followed", label: qsTr("Followed threads") }]
                        HubMenuRow {
                            required property var modelData
                            label: modelData.label; checkable: true; checked: root.filter === modelData.key
                            onClicked: { root.filter = checked ? "" : modelData.key; filterMenu.close() }
                        }
                    }
                    HubMenuRow {
                        id: orgsRow
                        label: qsTr("Orgs"); submenu: true; checkable: true
                        onClicked: orgsMenu.opened ? orgsMenu.close() : orgsMenu.open()
                        Popup {
                            id: orgsMenu
                            x: orgsRow.width + 2; y: 0
                            width: 240; padding: 4
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            contentItem: Column {
                                Repeater {
                                    model: root.accounts
                                    HubMenuRow {
                                        required property var modelData
                                        width: 232
                                        label: modelData.personal ? qsTr("Personal") : (modelData.org || modelData.upn); checkable: true
                                        checked: root.hiddenOrgs.indexOf(modelData.profile) < 0
                                        onClicked: {
                                            const l = root.hiddenOrgs.filter(p => p !== modelData.profile)
                                            if (checked) l.push(modelData.profile)
                                            root.hiddenOrgs = l
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Nothing left to list (every other account's org pinned):
            // Teams' no-results state.
            Item {
                id: emptyState
                visible: !flyout.tenant && list.count === 0
                y: flyout.listTop; width: parent.width; height: 362.67
                Image {
                    x: (parent.width - 100) / 2; y: 53.33; width: 100; height: 100; sourceSize: Qt.size(200, 200)
                    source: "../assets/illustrations/search-exclamation-l-standard.svg"
                }
                Text {
                    y: 180; width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("We couldn't find any results.")
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
            }
            // A pinned org's Tenant settings: Switch and Unpin this org
            // (240 wide at the flyout's right edge, under the button).
            Popup {
                id: tenantMenu
                x: body.width - 240; y: 24.67 + 23.33 + 2
                width: 240; padding: 0.67
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                contentItem: Column {
                    HubMenuRow {
                        width: 238.67; icon: "arrow-right-20"; label: qsTr("Switch")
                        disabled: !!flyout.tenant && !!flyout.tenant.current
                        onClicked: { const p = flyout.tenant.profile; tenantMenu.close(); flyout.close(); backend.switchAccount(p) }
                    }
                    HubMenuRow {
                        width: 238.67; icon: "pin-off-20"; label: qsTr("Unpin this org", "nova:k7lm8c4le")
                        onClicked: { const t = flyout.tenant; tenantMenu.close(); flyout.close(); root.pinOrg(t, false) }
                    }
                }
            }
            // Account settings: the account's organisations, each with
            // Switch and Pin this org.
            Popup {
                id: orgMenu
                property var account: ({})
                x: body.width - 240
                width: 240; padding: 0.67
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                contentItem: Column {
                    Rectangle {
                        id: orgRow
                        width: 238.67; height: 48; radius: 4
                        color: orgHover.hovered || switchMenu.opened ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                        Avatar {
                            x: 8.67; anchors.verticalCenter: parent.verticalCenter
                            size: 20
                            name: orgMenu.account.org || orgMenu.account.upn || "?"
                            initialsText: name.charAt(0).toUpperCase()
                            colorful: true; square: true; squareRadius: 2
                        }
                        Text { x: 40.67; width: 157.33; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: orgMenu.account.org || orgMenu.account.upn || ""; font.family: theme.font; font.pixelSize: 14; color: orgHover.hovered ? theme.brand : theme.textStrong }
                        FluentIcon { x: 210; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "chevron-right-20"; color: orgHover.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: orgHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: switchMenu.opened ? switchMenu.close() : switchMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More actions for %1").arg(orgMenu.account.org || "")
                        Popup {
                            id: switchMenu
                            x: orgRow.width + 2; y: 0
                            width: 240; padding: 0.67
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            contentItem: Column {
                                HubMenuRow {
                                    width: 238.67; icon: "arrow-right-20"; label: qsTr("Switch")
                                    onClicked: { switchMenu.close(); orgMenu.close(); flyout.close(); backend.switchAccount(orgMenu.account.profile) }
                                }
                                // Its own app bar tile; off at two pinned orgs.
                                HubMenuRow {
                                    width: 238.67; icon: "pin-20"; label: qsTr("Pin this org", "nova:k1e9r4gnf")
                                    disabled: root.pinned.length >= 2
                                    disabledTip: qsTr("Maximum tenants are pinned. Unpin one to add another.")
                                    onClicked: { switchMenu.close(); orgMenu.close(); root.pinOrg(orgMenu.account, true) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A subtle 24 x 23.33 icon button (Filter, Account settings).
    component HubIconButton: Rectangle {
        id: ib
        property string icon
        property string label
        property bool down: false
        signal clicked()
        width: 24; height: 23.33; radius: 4
        color: ib.down || ibHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: ib.icon; color: theme.onFill(ib, ib.down || ibHover.hovered ? theme.brand : theme.textStrong) }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        activeFocusOnTab: true
        Keys.onSpacePressed: clicked()
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // A 40 px menu row: an icon or check room of 40, the label, a chevron
    // for a submenu.
    component HubMenuRow: Rectangle {
        id: mr
        property string icon: ""
        property string label
        property bool checkable: false
        property bool checked: false
        property bool submenu: false
        /// Shown but not usable (its tooltip says why).
        property bool disabled: false
        property string disabledTip: ""
        readonly property bool lit: mrHover.hovered && !disabled
        readonly property color ink: disabled ? theme.disabled : theme.onFill(mr, lit ? theme.brand : theme.textStrong)
        signal clicked()
        width: 238.67; height: 40; radius: 4
        color: lit ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
        FluentIcon {
            visible: mr.icon.length > 0 || (mr.checkable && mr.checked && !mr.submenu)
            x: 12.67; anchors.verticalCenter: parent.verticalCenter; size: 20
            name: mr.icon.length > 0 ? mr.icon : "checkmark-20"
            color: mr.ink
        }
        Text { x: mr.icon.length > 0 ? 38.67 : 40.67; width: parent.width - x - (mr.submenu ? 36 : 12); anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: mr.label; font.family: theme.font; font.pixelSize: 14; color: mr.ink }
        FluentIcon { visible: mr.submenu; x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "chevron-right-20"; color: theme.onFill(mr, theme.textStrong) }
        HoverHandler { id: mrHover; cursorShape: mr.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !mr.disabled; onTapped: mr.clicked() }
        ToolTip.visible: mr.disabled && mrHover.hovered && mr.disabledTip.length > 0
        ToolTip.text: mr.disabledTip
        Accessible.role: mr.checkable ? Accessible.CheckBox : Accessible.MenuItem
        Accessible.name: label
        Accessible.description: disabled ? disabledTip : ""
        Accessible.checked: checked
    }
    // One activity or chat (Teams' list entry: 8 in; a 6 px dot column, the
    // 32 px picture 8 after it, the text 8 after that, the time at the right).
    component HubEntry: Rectangle {
        id: en
        property var entry: ({})
        signal picked()
        signal callBack()
        signal chatWith()
        readonly property bool call: entry.activity === "missedCall" && !!entry.actorOid
        readonly property real textW: width - 62 - 8 - timeText.implicitWidth - 8
        height: Math.max(36, textCol.height) + 16 + (call ? 5 : 0)
        color: enHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
        Rectangle { visible: !!en.entry.unread; x: 9; y: 8 + 16 - 2; width: 4; height: 4; radius: 2; color: theme.onFill(en, theme.text) }
        Item {
            x: 22; y: 8; width: 32; height: 32
            // A meeting's calendar disc, else the person, group or app.
            Rectangle {
                visible: !!en.entry.meeting
                anchors.fill: parent; radius: 16
                color: theme.pick("#C5CBFA", "#3D3E78", "#000000")
                FluentIcon { anchors.centerIn: parent; size: 20; name: "calendar-ltr-20"; color: theme.onFill(parent, theme.brand) }
            }
            Avatar {
                visible: !en.entry.meeting
                size: 32
                name: en.entry.avatarName || en.entry.title || "?"
                photoId: en.entry.photoId || ""
                group: !!en.entry.group
                square: !!en.entry.square
            }
            // An activity's kind, on a white disc at the corner.
            Rectangle {
                visible: en.entry.kind === "activity"
                x: 17; y: 17; width: 18; height: 18; radius: 9
                color: theme.surface; border.width: 0.67; border.color: theme.surface
                Text { visible: !!en.entry.emoji; anchors.centerIn: parent; text: en.entry.emoji || ""; font.pixelSize: 12 }
                FluentIcon {
                    visible: !en.entry.emoji
                    anchors.centerIn: parent; size: 16
                    name: en.entry.activity === "missedCall" ? "call-missed-16" : en.entry.activity === "voicemail" ? "voicemail-16-filled" : en.entry.activity === "addedToTeam" ? "people-team-16" : en.entry.activity === "mention" || en.entry.activity === "tagMention" ? "mention-16" : en.entry.activity === "app" ? "apps-20" : "chat-20"
                    color: theme.brand
                }
            }
        }
        Column {
            id: textCol
            x: 62; y: 8
            width: en.textW
            spacing: en.call ? 10 : 2
            Text {
                width: parent.width
                text: en.entry.title || ""
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; font.weight: en.entry.unread ? Font.Bold : Font.Normal
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                visible: !en.call && !!en.entry.subtitle
                width: parent.width
                text: en.entry.subtitle || ""
                wrapMode: Text.Wrap; maximumLineCount: en.entry.kind === "chat" ? 2 : 1; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: en.entry.kind === "chat" ? theme.textStrong : theme.textSecondary
            }
            // A missed call's Call and Chat.
            Row {
                visible: en.call
                spacing: 8
                Repeater {
                    model: [qsTr("Call"), qsTr("Chat")]
                    Rectangle {
                        id: callButton
                        required property string modelData
                        required property int index
                        width: 65; height: 24; radius: 4
                        color: cbHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                        border.width: 0.67; border.color: theme.stroke
                        Text { anchors.centerIn: parent; text: callButton.modelData; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(callButton, theme.text) }
                        HoverHandler { id: cbHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: callButton.index === 0 ? en.callBack() : en.chatWith() }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                    }
                }
            }
        }
        Text {
            id: timeText
            anchors.right: parent.right; anchors.rightMargin: 8; y: 8
            text: root.when(en.entry.time)
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        HoverHandler { id: enHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: en.picked() }
        Accessible.role: Accessible.ListItem
        Accessible.name: [en.entry.title, en.entry.subtitle, timeText.text, en.entry.unread ? (en.entry.channel ? qsTr("Unread channel messages") : qsTr("Unread chat messages")) : ""].filter(s => !!s).join(", ")
    }
}
