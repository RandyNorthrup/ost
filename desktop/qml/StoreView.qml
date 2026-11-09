import QtQuick
import QtQuick.Controls.Basic

// Teams' Store (measured on winpc 2026-11-09; docs/spec/store.md §4), built
// from Teams' own data: the store content doc's collections over the
// ranked catalog, with ECS settings (api::store_content). CSS px:
// - The header (60 tall): "Store" 18/24 bold at 16, then the tabs Home,
//   Featured ▾ and Categories ▾ (14/20, 12 x 10 padding, the selected one
//   underlined in brand); Featured and Categories open menus of
//   collections with Teams' icons (Featured in groups split by dividers).
// - The banner (276 tall, lavender): "Do more in Teams" 40/56 semibold,
//   "Discover agents and apps that can help you tackle any task." 14/20,
//   and a 530 x 48 pill search "Search agents and apps".
// - The feed: Teams' feed collections in feedOrder, 90 in: the title
//   18/24 bold at 26, its description 14/20 #424242 at 54, "See all"
//   (14/16 semibold, brand) at the right, then up to nine apps three to a
//   row from 92: 330 x 128 cards (104 without ratings) 16 apart, radius
//   12, hover fill, a 52 squircle icon at (16, 16), the name 16/20
//   semibold at (84, 21), the description 14/20 in two lines at 45 and
//   the rating 12/16 at 91.
// - See all, a menu entry and search open a page: Back (32) with the
//   title 30/36 semibold and description 16/22, then every app (cards
//   with the developer 12/16 under the name), or for a category group
//   each of its collections as on the feed.
Item {
    id: root
    property var reply: ({})
    property bool busy: false
    signal load()
    /// Open a native app (planner, onenote, people) in OST.
    signal openApp(string key)

    readonly property var feedCols: reply.feed || []
    readonly property var featuredNav: reply.featured || []
    readonly property var categoryNav: reply.categories || []
    readonly property var native_: ({ "Planner": "planner", "OneNote": "onenote", "People": "people", "Whiteboard": "whiteboard", "Clipchamp": "clipchamp", "Help": "help" })
    /// The page shown over the home: a collection id, or "search".
    property string page: ""
    readonly property var pageData: { const p = backend.storePageJson ? JSON.parse(backend.storePageJson) : null; return p && p.id === page ? p : null }
    readonly property string query: search.text.trim()
    readonly property var found: { const r = backend.storeSearchJson ? JSON.parse(backend.storeSearchJson) : null; return r && r.query === query ? r : null }
    property string tab: "home"

    onVisibleChanged: if (visible && !feedCols.length && !busy) load()
    function openPage(id) { page = id; menu.close(); backend.storePageLoad(id); pageFlick.contentY = 0 }
    function home() { page = ""; tab = "home"; search.text = ""; feedFlick.contentY = 0 }
    Timer { id: searchDelay; interval: 300; onTriggered: if (root.query) { root.page = "search"; backend.storeSearch(root.query) } else if (root.page === "search") root.page = "" }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Header.
    Item {
        id: header
        width: parent.width; height: 60
        Text { x: 16; y: 17.7; height: 24; verticalAlignment: Text.AlignVCenter; text: "Store"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Row {
            x: 72.4; y: 0; height: 59.3
            Repeater {
                model: [{ k: "home", l: "Home" }, { k: "featured", l: "Featured", menu: true }, { k: "categories", l: "Categories", menu: true }]
                Item {
                    id: tabItem
                    required property var modelData
                    readonly property bool selected: root.tab === modelData.k
                    width: tabRow.implicitWidth + 20; height: 59.3
                    Row {
                        id: tabRow
                        x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { anchors.verticalCenter: parent.verticalCenter; text: tabItem.modelData.l; font.family: theme.font; font.pixelSize: 14; color: tabItem.selected ? theme.text : theme.textSecondary }
                        FluentIcon { visible: !!tabItem.modelData.menu; anchors.verticalCenter: parent.verticalCenter; name: menu.opened && menu.kind === tabItem.modelData.k ? "chevron-up-16" : "chevron-down-16"; size: 16; color: theme.textSecondary }
                    }
                    Rectangle { visible: tabItem.selected; anchors.bottom: parent.bottom; x: 10; width: parent.width - 20; height: 3; radius: 1.5; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (!tabItem.modelData.menu) { root.home(); return }
                            menu.kind = tabItem.modelData.k
                            menu.x = tabItem.x + 72.4
                            menu.open()
                        }
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: tabItem.modelData.l
                    Accessible.selected: tabItem.selected
                }
            }
        }
    }

    // Featured / Categories menus.
    Popup {
        id: menu
        property string kind: "featured"
        y: header.height + 1
        padding: 4
        width: 256
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        readonly property var groups: kind === "featured" ? root.featuredNav : [root.categoryNav]
        contentItem: Column {
            Repeater {
                model: menu.groups
                Column {
                    id: grp
                    required property var modelData
                    required property int index
                    width: 248
                    Rectangle { visible: grp.index > 0; x: -4; width: 256; height: 1; color: theme.dividerSoft }
                    Item { visible: grp.index > 0; width: 1; height: 4 }
                    Repeater {
                        model: grp.modelData
                        Rectangle {
                            id: mi
                            required property var modelData
                            width: 248; height: 32; radius: 4
                            color: miHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { visible: !!mi.modelData.icon; x: 6; anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.icon + "-20"; size: 20; color: theme.textSecondary }
                            Text { x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40; elide: Text.ElideRight; text: mi.modelData.title; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            HoverHandler { id: miHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.tab = menu.kind; root.openPage(mi.modelData.id) } }
                            Accessible.role: Accessible.MenuItem; Accessible.name: mi.modelData.title
                        }
                    }
                }
            }
        }
    }

    // An app card. `full` (pages) adds the developer under the name.
    component AppCard: Item {
        id: card
        property var app
        property bool full: false
        /// The collection hides ratings (your org's apps).
        property bool noRatings: false
        readonly property bool rated: !noRatings && (app.count || 0) > 0
        width: 330; height: full ? 148 : (rated ? 128 : 104)
        Rectangle { anchors.fill: parent; radius: 12; color: cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent" }
        Item {
            x: 16; y: 16; width: 52; height: 52
            Rectangle { anchors.fill: parent; color: theme.quoteFill }
            Image { anchors.fill: parent; source: card.app.icon || ""; sourceSize: Qt.size(104, 104); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true }
            RoundedCorners { anchors.fill: parent; squircle: true; background: cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : theme.surface }
            // You have it: Teams' check in a 24 px white circle on the
            // icon's corner.
            FluentSurface {
                visible: !!card.app.installed
                x: 29; y: 32; width: 24; height: 24; radius: 12; depth: 4
                color: theme.surface
                FluentIcon { anchors.centerIn: parent; name: "checkmark-16"; size: 16; color: theme.text }
                Accessible.role: Accessible.Graphic; Accessible.name: "Added"
            }
        }
        Text { x: 84; y: 21; width: card.width - 84 - 16; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: card.app.name; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Text { visible: card.full; x: 84; y: 42; width: card.width - 100; height: 16; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: card.app.developer || ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Text {
            x: 84; y: card.full ? 70 : 45; width: card.width - 100
            rightPadding: 40
            maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            text: card.app.short || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Row {
            visible: card.rated
            x: 84; y: card.full ? 116 : 91; height: 16; spacing: 3
            FluentIcon { name: "star-16-filled"; size: 16; color: theme.brandFill }
            Text { height: 16; verticalAlignment: Text.AlignVCenter; textFormat: Text.StyledText; text: "<b>" + (card.app.average_text || "") + "</b> (" + (card.app.count_text || "") + " ratings)"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        }
        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: details.show(card.app.id) }
        Accessible.role: Accessible.ListItem
        Accessible.name: card.app.name + ". " + (card.app.short || "")
    }

    // A feed collection: its header and up to nine apps.
    component Section: Item {
        id: sec
        property var col
        width: Math.min(1038, root.width - 174)
        height: 92 + appsFlow.height + 27
        Text { y: 26; height: 24; verticalAlignment: Text.AlignVCenter; text: sec.col.title; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Text { visible: !!sec.col.description; y: 54; height: 20; verticalAlignment: Text.AlignVCenter; width: parent.width - 120; elide: Text.ElideRight; text: sec.col.description || ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14; y: 26; height: 16; verticalAlignment: Text.AlignVCenter
            text: "See all"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandForeground1
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openPage(sec.col.id) }
            Accessible.role: Accessible.Button; Accessible.name: "See all " + sec.col.title
        }
        Flow {
            id: appsFlow
            x: 2; y: 92; width: parent.width; spacing: 16
            Repeater { model: sec.col.apps.slice(0, 9); AppCard { required property var modelData; app: modelData; noRatings: !!sec.col.no_ratings } }
        }
    }

    // Home.
    Flickable {
        id: feedFlick
        visible: !root.page
        anchors { fill: parent; topMargin: header.height + 0.7 }
        contentHeight: feedCol.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: feedCol
            width: parent.width
            Rectangle {
                width: parent.width; height: 276
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: theme.dark ? "#2B2B40" : "#E8EBFA" }
                    GradientStop { position: 0.5; color: theme.dark ? "#262636" : "#F3F2FA" }
                    GradientStop { position: 1.0; color: theme.dark ? "#2B2B40" : "#E8EBFA" }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 60; height: 56; verticalAlignment: Text.AlignVCenter; text: "Do more in Teams"; font.family: theme.font; font.pixelSize: 40; font.weight: Font.DemiBold; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 116; height: 20; verticalAlignment: Text.AlignVCenter; text: "Discover agents and apps that can help you tackle any task."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 168; width: Math.min(530, root.width - 80); height: 48; radius: 24
                    color: theme.surface
                    border.width: search.activeFocus ? 0 : 0.67; border.color: theme.stroke
                    Rectangle { visible: search.activeFocus; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - 40; height: 2; color: theme.brand }
                    FluentIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
                    TextField {
                        id: search
                        x: 44; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter
                        placeholderText: "Search agents and apps"; placeholderTextColor: theme.textSecondary
                        background: null
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        onTextChanged: searchDelay.restart()
                        Keys.onEscapePressed: text = ""
                        Accessible.name: "Search agents and apps"
                    }
                }
            }
            Text {
                visible: !!root.reply.error
                x: 90; topPadding: 24
                text: "We couldn't load the Store. " + (root.reply.error || "")
                font.family: theme.font; font.pixelSize: 14; color: theme.danger
            }
            Repeater {
                model: root.feedCols
                Item { required property var modelData; width: feedCol.width; height: s.height; Section { id: s; x: 90; col: parent.modelData } }
            }
        }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.busy && !root.page; visible: running }

    // A page: See all, a menu entry, or search results.
    Flickable {
        id: pageFlick
        visible: !!root.page
        anchors { fill: parent; topMargin: header.height + 0.7 }
        contentHeight: pageCol.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: pageCol
            x: 45.5; width: Math.min(1050, root.width - 90)
            Item {
                width: parent.width; height: 140
                Rectangle {
                    x: 0; y: 63; width: 32; height: 32; radius: 4
                    color: backHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.textSecondary }
                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.home() }
                    Accessible.role: Accessible.Button; Accessible.name: "Back"
                }
                Text {
                    x: 40; y: 61; height: 36; verticalAlignment: Text.AlignVCenter
                    text: root.page === "search" ? "Search results for \"" + root.query + "\"" + (root.found && root.found.results ? " (" + root.found.results.length + ")" : "") : (root.pageData && root.pageData.title ? root.pageData.title : "")
                    font.family: theme.font; font.pixelSize: 30; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Text { visible: root.page !== "search" && !!(root.pageData && root.pageData.description); x: 40; y: 109; height: 22; verticalAlignment: Text.AlignVCenter; text: root.pageData && root.pageData.description ? root.pageData.description : ""; font.family: theme.font; font.pixelSize: 16; color: theme.text }
            }
            Text {
                visible: root.page === "search" ? !root.found || !!root.found.loading : !root.pageData || !!root.pageData.loading
                x: 40; topPadding: 24; text: "Loading…"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            Flow {
                x: 40; width: parent.width - 40; spacing: 10
                Repeater {
                    model: root.page === "search" ? (root.found && root.found.results ? root.found.results : []) : (root.pageData && root.pageData.apps ? root.pageData.apps : [])
                    AppCard { required property var modelData; app: modelData; full: true; noRatings: root.page !== "search" && !!(root.pageData && root.pageData.no_ratings) }
                }
            }
            Repeater {
                model: root.page !== "search" && root.pageData && root.pageData.sections ? root.pageData.sections : []
                Item { required property var modelData; width: pageCol.width; height: gs.height; Section { id: gs; x: 40; col: parent.modelData } }
            }
        }
    }

    // An app's details: Teams' app details dialog.
    AppDetailsDialog {
        id: details
        offerOpen: true
        onShareApp: id => storeShare.start(id)
        // Apps OST has natively open here; the rest in Teams on the web.
        onOpenApp: (id, name) => {
            const k = root.native_[name] || ""
            if (k) root.openApp(k)
            else Qt.openUrlExternally("https://teams.microsoft.com/l/app/" + encodeURIComponent(id))
        }
    }
    ShareForm { id: storeShare }

    // Test harness hooks
    function searchForTest(q) { search.text = q }
    function detailsForTest(name) {
        for (const c of root.feedCols) for (const a of c.apps) if (a.name === name) { details.show(a.id); return true }
        return false
    }
    function menuForTest(kind) { menu.kind = kind; menu.x = kind === "featured" ? 134 : 240; menu.open() }
    function closeMenuForTest() { menu.close() }
}
