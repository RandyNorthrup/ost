import QtQuick
import QtQuick.Controls.Basic

// Teams' in-context Store for "Add agent to the chat / channel"
// (in-context-store-dialog), measured on winpc 2026-11-09 in OST group test
// (docs/spec/store.md §3). CSS px:
// - 901.3 x 647.3, radius 8, white, Teams' dialog shadow.
// - The search box ("Search for agents and bots") 836 x 32 at (32, 32),
//   #F5F5F5, radius 4, a 20 px search icon 10 from its right; brand focus
//   line.
// - Scrolling under it (32 in, 4 from the right): the bots already in the
//   conversation as 100 x 96 tiles (48 px icon, name 12/16), centred, 20
//   above and below; "Add a new agent or bot" (16/16 semibold #424242)
//   between #E0E0E0 rules; then each collection: a 78 px header (title
//   12/16 semibold 32 down, "See all" 12/16 semibold brand at the right,
//   26 down) and its first three apps as 834 x 86 cards 98 apart (12
//   padding, radius 4, shadow 0 0 2 / 0 2 4): a 32 px squircle icon at
//   (19, 14.5), the name 14/20 bold at (61, 12) with the agent sparkle
//   (20), the short description 12/16 at 33 and the rating at 59 (16 px
//   brand star, bold average, "(N ratings)").
// - See all: the title 12/24 semibold at 32, then every app as 848 x 122
//   cards 134 apart with the developer under the name.
// - The footer: Close (96, outline) and Get more apps (brand) at 594.7,
//   right-aligned 32 in; Back (96) at the left in See all.
//
// The same Store is Teams' Add a tab picker (`mode: "tab"`, the header's
// "+", measured on winpc 2026-11-16, docs/spec/add-a-tab.md): "Search for
// apps"; the grid holds your apps that have a tab here, most recently used
// first: 4 tiles and "See all" (a 49.3 px outlined box with the 16 px grid
// icon), which shows them all, 8 to a row, with "See less"; "Add a new
// app"; the Tab collections. A grid app opens its tab configuration
// (pickTabApp); a collection's app opens its details. Footer (both
// Stores): Manage your apps (32 x 31.3, 32 in) under a 0.67 px rule.
Popup {
    id: root
    /// The conversation the agents would join, and whether it's a channel.
    property string conversationId: ""
    property bool channel: false
    /// "agent" (Add agent) or "tab" (Add a tab).
    property string mode: "agent"
    /// For tabs: "chat", "meeting" or "channel", and a channel's team thread.
    property string kind: "chat"
    property string teamThread: ""
    readonly property bool tabs: mode === "tab"
    signal openApp(string appId)
    signal getMoreApps()
    signal manageApps()
    /// Add a tab: one of your apps was picked from the grid.
    signal pickTabApp(var app)
    modal: true; focus: true
    // Teams' picker: 901.3 x 647.3 in the main window; in a 946 x 593
    // pop-out 900 x 565 at 23, 14 (winpc, 2026-11-21).
    width: Math.min(901.3, (parent ? parent.width : 901.3) - 46)
    height: Math.min(647.3, (parent ? parent.height : 647.3) - 28)
    anchors.centerIn: Overlay.overlay
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }

    readonly property var store: { const s = backend.agentStoreJson ? JSON.parse(backend.agentStoreJson) : null; return s && s.conversation === conversationId && (s.mode || "agent") === mode ? s : null }
    readonly property var collections: store && store.collections ? store.collections : []
    readonly property var installed: store && store.installed ? store.installed : []
    /// The collection shown by See all, or null for the overview.
    property var seeAll: null
    /// The search shown (Teams' "Search results for" view).
    readonly property string query: search.text.trim()
    readonly property var found: { const r = backend.agentSearchJson ? JSON.parse(backend.agentSearchJson) : null; return r && r.query === query && (r.mode || "agent") === mode ? r : null }
    Timer {
        id: searchDelay; interval: 300
        onTriggered: if (root.query) {
            if (root.tabs) backend.tabStoreSearch(root.conversationId, root.kind, root.query)
            else backend.agentStoreSearch(root.conversationId, root.channel, root.query)
        }
    }
    /// The grid shows everything (See all) or its first four.
    property bool gridAll: false
    // Teams' InContextStoreGridAppsRenderer: a "See all" tile once there
    // are more than 5 apps (inContextStoreAppsMinCount 7, less 3 off the
    // desktop view: 4 shown, as on winpc).
    readonly property int gridFirst: 4
    readonly property var gridItems: {
        const a = installed
        if (!tabs || a.length - 1 <= gridFirst) return a
        return gridAll ? a.concat([{ seeLess: true, name: qsTr("See less") }]) : a.slice(0, gridFirst).concat([{ seeAll: true, name: qsTr("See all") }])
    }

    function show(id, isChannel) {
        mode = "agent"
        conversationId = id; channel = isChannel; seeAll = null; search.text = ""; gridAll = false
        backend.agentStoreLoad(id, isChannel)
        open(); search.forceActiveFocus()
    }
    /// Teams' Add a tab picker for a conversation: `k` "chat", "meeting" or
    /// "channel" (with its team's thread).
    function showTabs(id, k, team) {
        mode = "tab"; kind = k; teamThread = team || ""
        conversationId = id; channel = k === "channel"; seeAll = null; search.text = ""; gridAll = false
        backend.tabStoreLoad(id, teamThread, k)
        open(); search.forceActiveFocus()
    }
    /// Back from a tab's configuration: the picker as it was.
    function reopen() { open(); search.forceActiveFocus() }

    // A squircle app icon on #FAFAFA, as Teams draws app tiles.
    component AppIcon: Item {
        id: ai
        property string src
        property color background: theme.surface
        Rectangle { anchors.fill: parent; color: theme.quoteFill }
        Image { anchors.fill: parent; source: ai.src; sourceSize: Qt.size(ai.width * 2, ai.height * 2); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true }
        RoundedCorners { anchors.fill: parent; squircle: true; background: ai.background }
    }

    // An app card; `full` adds the developer line (See all).
    component AppCard: Item {
        id: card
        property var app
        property bool full: false
        width: full ? 848 : 834; height: full ? 122 : 86
        FluentSurface { anchors.fill: parent; depth: 4; radius: 4; color: cardHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface }
        AppIcon { x: 19; y: 14.5; width: 32; height: 32; src: card.app.icon || ""; background: cardHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface }
        Row {
            x: 61; y: 12; height: 20; spacing: 0
            Text { height: 20; verticalAlignment: Text.AlignVCenter; text: card.app.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text; elide: Text.ElideRight; width: Math.min(implicitWidth, card.width - 120) }
            // The agent mark: a 20 px box holding Fluent's Sparkle (regular)
            // at 12 px (measured on winpc).
            Item {
                visible: !!card.app.agent
                width: 20; height: 20
                FluentIcon { anchors.centerIn: parent; name: "sparkle-20"; size: 12; color: theme.textSecondary }
                Accessible.role: Accessible.Graphic; Accessible.name: qsTr("Includes an agent and uses AI")
            }
        }
        Text { visible: card.full; x: 61; y: 33; height: 16; verticalAlignment: Text.AlignVCenter; width: card.width - 80; elide: Text.ElideRight; text: card.app.developer || ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        // The short description: beside the icon under the name, or (See
        // all) across the card under the developer.
        Text { x: card.full ? 19 : 61; y: card.full ? 61 : 33; height: 16; verticalAlignment: Text.AlignVCenter; width: card.width - x - 40 - 12; elide: Text.ElideRight; text: card.app.short || ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Row {
            visible: (card.app.count || 0) > 0
            x: 19; y: card.full ? 87 : 59; height: 16; spacing: 3
            FluentIcon { y: 0; name: "star-16-filled"; size: 16; color: theme.brandFill }
            Text { height: 16; verticalAlignment: Text.AlignVCenter; textFormat: Text.StyledText; text: "<b>" + (card.app.average_text || "") + "</b> (" + (card.app.count_text || "") + " ratings)"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        }
        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openApp(card.app.id) }
        Accessible.role: Accessible.ListItem
        Accessible.name: card.app.name
    }

    // Search box.
    Rectangle {
        id: searchBox
        x: 32; y: 32; width: root.width - 64; height: 32; radius: 4
        visible: !root.seeAll
        color: theme.inputFilled; border.color: theme.transparentStroke
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: search.activeFocus ? 2 : 0; color: theme.brand }
        TextField {
            id: search
            anchors { left: parent.left; right: searchIcon.left; top: parent.top; bottom: parent.bottom }
            leftPadding: 12; rightPadding: 2
            placeholderText: root.tabs ? qsTr("Search for apps") : qsTr("Search for agents and bots")
            placeholderTextColor: theme.textTertiary
            background: null
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            onTextChanged: { flick.contentY = 0; searchDelay.restart() }
            Accessible.name: placeholderText
        }
        // The search icon, or a clear button while there is a query.
        Item {
            id: searchIcon
            anchors.right: parent.right; anchors.rightMargin: root.query ? 12.7 : 10
            anchors.verticalCenter: parent.verticalCenter
            width: root.query ? 24 : 20; height: root.query ? 23.3 : 20
            Rectangle { id: hcFill1; anchors.fill: parent; radius: 4; visible: !!root.query && clearHover.hovered; color: theme.menuHover }
            FluentIcon { anchors.centerIn: parent; name: root.query ? "dismiss-20" : "search-20"; size: 20; color: theme.onFill(hcFill1, root.query ? theme.textSecondary : theme.pick("#616161", "#ADADAD", "#FFFFFF")) }
            HoverHandler { id: clearHover; enabled: !!root.query; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !!root.query; onTapped: { search.text = ""; search.forceActiveFocus() } }
            Accessible.role: root.query ? Accessible.Button : Accessible.Graphic
            Accessible.name: root.query ? qsTr("Clear search") : qsTr("Search")
        }
    }

    Flickable {
        id: flick
        x: 32; y: root.seeAll ? 32 : 74
        width: root.width - 36; height: root.height - 73.3 - y
        contentHeight: body.height + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: body
            width: root.width - 64
            // Search results.
            Column {
                visible: !root.seeAll && !!root.query
                width: parent.width
                Item { width: 1; height: 15.6 }
                Item {
                    width: parent.width - 18; height: 36
                    Text {
                        id: resultsTitle
                        anchors.horizontalCenter: parent.horizontalCenter; y: -2.7; height: 21.3; verticalAlignment: Text.AlignVCenter
                        text: root.found && root.found.results ? qsTr("Search results for \"%1\" %2").arg(root.query).arg("(" + root.found.results.length + ")") : qsTr("Search results for \"%1\"").arg(root.query)
                        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textSecondary
                    }
                    Rectangle { y: 9; x: 0; width: resultsTitle.x - 12; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                    Rectangle { y: 9; x: resultsTitle.x + resultsTitle.width + 12; width: parent.width - x; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                }
                Repeater {
                    model: root.found && root.found.results ? root.found.results : []
                    Item {
                        required property var modelData
                        width: 852; height: 134
                        AppCard { x: 2; y: 2; full: true; width: 836; app: parent.modelData }
                    }
                }
            }
            // The overview.
            Column {
                visible: !root.seeAll && !root.query
                width: parent.width
                Item {
                    visible: root.installed.length > 0
                    // The grid's margin: 2rem above and below, 1.6rem on the
                    // right; tiles 104 x 100 centred, 8 to a row.
                    width: parent.width; height: visible ? gridFlow.height + 40 : 0
                    Flow {
                        id: gridFlow
                        // Teams' scroll area is 850 wide with a 16 px gutter.
                        readonly property real area: root.width - 51.3 - 16
                        readonly property int perRow: Math.max(1, Math.floor(area / 104))
                        readonly property int count: root.gridItems.length
                        width: Math.min(count, perRow) * 104
                        x: (area - width) / 2
                        y: 20
                        Repeater {
                            model: root.gridItems
                            Item {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property bool more: !!modelData.seeAll || !!modelData.seeLess
                                // A short last row is centred, as Teams' flex wrap.
                                readonly property int row: Math.floor(index / gridFlow.perRow)
                                readonly property int lastRowCount: gridFlow.count - row * gridFlow.perRow
                                width: 104; height: 100
                                readonly property int lastRow: Math.floor((gridFlow.count - 1) / gridFlow.perRow)
                                transform: Translate { x: tile.lastRow > 0 && tile.row === tile.lastRow && tile.lastRowCount < gridFlow.perRow ? (gridFlow.perRow - tile.lastRowCount) * 52 : 0 }
                                Rectangle {
                                    id: hcFill2
                                    x: 2; y: 2; width: 100; height: 96; radius: 6
                                    color: tileHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                                    AppIcon { visible: !tile.more; x: 26; y: 8; width: 48; height: 48; src: tile.modelData.icon || ""; background: parent.color }
                                    // See all / See less: the 16 px grid icon in a
                                    // 49.3 px outlined box (radius 4, padding 16).
                                    Rectangle {
                                        visible: tile.more
                                        x: 25.3; y: 7.3; width: 49.3; height: 49.3; radius: 4
                                        color: theme.surface
                                        border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                                        FluentIcon { anchors.centerIn: parent; name: "grid-16"; size: 16; color: theme.text }
                                    }
                                    Text { x: 14; y: 62; width: 72; height: 32; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: tile.modelData.name; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill2, theme.text) }
                                    HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (tile.modelData.seeAll) root.gridAll = true
                                            else if (tile.modelData.seeLess) root.gridAll = false
                                            else if (root.tabs) root.pickTabApp(tile.modelData)
                                            else root.openApp(tile.modelData.id)
                                        }
                                    }
                                    Accessible.role: Accessible.MenuItem
                                    Accessible.name: tile.modelData.name
                                }
                            }
                        }
                    }
                }
                // "Add a new agent or bot" ("Add a new app" for tabs)
                Item {
                    width: parent.width - 18; height: 18
                    Text { id: addNew; anchors.centerIn: parent; text: root.tabs ? qsTr("Add a new app") : qsTr("Add a new agent or bot"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textSecondary }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: addNew.x - 12; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: addNew.x + addNew.width + 12; width: parent.width - x; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                }
                Text {
                    visible: !!root.store && !!root.store.loading
                    topPadding: 24; width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Loading…"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text {
                    visible: !!root.store && !!root.store.error
                    topPadding: 24; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: qsTr("Something went wrong. Try again later."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Repeater {
                    model: root.collections
                    Column {
                        id: col
                        required property var modelData
                        width: parent.width
                        Item {
                            width: parent.width; height: 78
                            Text { y: 32; height: 16; verticalAlignment: Text.AlignVCenter; text: col.modelData.title; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; y: 26; height: 16; verticalAlignment: Text.AlignVCenter
                                text: qsTr("See all"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brandForeground1
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { root.seeAll = col.modelData; flick.contentY = 0 } }
                                Accessible.role: Accessible.Button; Accessible.name: qsTr("See all") + " " + col.modelData.title
                            }
                        }
                        Repeater {
                            model: col.modelData.apps.slice(0, 3)
                            Item {
                                required property var modelData
                                width: 850; height: 98
                                AppCard { x: 2; y: 2; app: parent.modelData }
                            }
                        }
                    }
                }
            }
            // See all.
            Column {
                visible: !!root.seeAll
                width: parent.width
                Text { height: 54; verticalAlignment: Text.AlignTop; text: root.seeAll ? root.seeAll.title : ""; lineHeight: 24; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Repeater {
                    model: root.seeAll ? root.seeAll.apps : []
                    Item {
                        required property var modelData
                        width: 864; height: 134
                        AppCard { x: 2; y: 2; full: true; app: parent.modelData }
                    }
                }
            }
        }
    }

    // Footer: a 0.67 px rule at 574.7, then (outside See all) Manage your
    // apps at the left (in-context-store-manage-apps-btn, 32 x 31.3).
    Rectangle { x: 0; y: root.height - 72.6; width: root.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
    Rectangle {
        id: hcFill6
        visible: !root.seeAll
        x: 32; y: root.height - 52.7; width: 32; height: 31.3; radius: 4
        color: manageHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "apps-list-20"; size: 20; color: theme.onFill(hcFill6, theme.textStrong) }
        HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { root.close(); root.manageApps() } }
        ToolTip.visible: manageHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Manage your apps")
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Manage your apps")
    }
    Rectangle {
        id: hcFill3
        visible: !!root.seeAll
        x: 32; y: root.height - 52.7; width: 96; height: 31.3; radius: 4
        color: backHover.hovered ? theme.menuHover : "transparent"
        Row {
            anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-left-20"; size: 20; color: theme.onFill(hcFill3, theme.text) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, theme.text) }
        }
        HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { root.seeAll = null; flick.contentY = 0 } }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 32
        y: root.height - 52.7; spacing: 10
        Rectangle {
            id: hcFill4
            width: 96; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : theme.surface
            border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
            Text { anchors.centerIn: parent; text: qsTr("Close"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
        Rectangle {
            id: hcFill5
            width: 118.8; height: 31.3; radius: 4
            color: moreHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: qsTr("Get more apps"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill5, theme.textOnBrand) }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.getMoreApps() } }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Get more apps")
        }
    }

    function scrollForTest(dy) { flick.contentY = Math.min(flick.contentHeight - flick.height, flick.contentY + dy) }
    function searchForTest(q) { search.text = q }
}
