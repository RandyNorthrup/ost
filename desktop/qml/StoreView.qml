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
// Measured again on winpc 2026-11-20 (TASK-0077):
// - The header also has Devices ▾ (Teams' device store: Featured,
//   Headsets, Web cameras, Speakerphones, Desk phones & Teams displays,
//   Monitors, Teams Rooms, Room systems accessories, each with its icon)
//   and, at the right, "Your agents and apps" (a 20 px library) and
//   "Manage your apps" (a 20 px gear), 32 x 33.3, 16 from the edge; on a
//   page its search moves into the header (a 384 x 32 pill, radius 16,
//   96 from the edge).
// - A page's filter (collection-filter, a 32 px round button 96.5 from the
//   right, 64 under the description) opens Teams' filter tree: Availability
//   (Ready to add, Requires approval), Pricing (Free to add, Subscription
//   plans available), Certification (Microsoft 365 certified, Publisher
//   attested) and Supported Channel (Shared Channel, Private Channel) in a
//   column, App features (Bot, Connector, Agent, Group Chat, Meeting,
//   Messaging, Personal, Tab) beside it, each only when the page's apps
//   have it; picked options show as brand pills left of the button (a pill
//   removes its option) and the page keeps the apps that have any of them.
// - A device page: a 28 tall #F5F5F5 band with the region ("USA", its
//   tooltip "Your region is set to United States.") and the cart (a brand
//   pill with its count), then the collection's title and description and
//   its devices, 24 at a time, in 239 x 312 tiles 255 apart (the picture
//   207 x 160 on white at 16, the name 12/16 semibold, the maker 12/16, the
//   price 14/20 bold, two lines of description 12/16). Its filter offers
//   only an empty App features group (as Teams').
Item {
    id: root
    property var reply: ({})
    property bool busy: false
    signal load()
    /// Open a native app (planner, onenote, people) in OST.
    signal openApp(string key)
    signal toast(var data)
    /// The device store's cart for the market (kept on this device, as
    /// Teams keeps it): {market, items: [{id, name, price, price_text,
    /// quantity, image}]}.
    property var cart: { try { const c = JSON.parse(backend.setting("deviceStoreCart") || "{}"); return c && c.items ? c : { market: "US", items: [] } } catch (e) { return { market: "US", items: [] } } }
    function saveCart(items) {
        root.cart = { market: "US", items: items, updatedAt: new Date().toISOString() }
        backend.setSetting("deviceStoreCart", JSON.stringify(root.cart))
    }
    function addToCart(d, quantity) {
        const items = root.cart.items.slice()
        const i = items.findIndex(x => String(x.id) === String(d.id))
        if (i >= 0) items[i] = Object.assign({}, items[i], { quantity: items[i].quantity + quantity })
        else items.push({ id: String(d.id), name: d.name, price: d.price, price_text: d.price_text, quantity: quantity, image: d.image })
        saveCart(items)
    }
    readonly property int cartCount: root.cart.items.reduce((n, x) => n + x.quantity, 0)
    /// The Devices menu (Teams' device collections and icons).
    readonly property var devicesNav: [
        { id: "featured", title: qsTr("Featured"), icon: "star" },
        { id: "headsets", title: qsTr("Headsets"), icon: "headset" },
        { id: "webcameras", title: qsTr("Web cameras"), icon: "video" },
        { id: "speakerphones", title: qsTr("Speakerphones"), icon: "speaker-2" },
        { id: "deskphonesandteamsdisplays", title: qsTr("Desk phones & Teams displays"), icon: "device-meeting-room" },
        { id: "monitors", title: qsTr("Monitors"), icon: "desktop" },
        { id: "teamsrooms", title: qsTr("Teams Rooms"), icon: "surface-hub" },
        { id: "roomsystemsaccessories", title: qsTr("Room systems accessories"), icon: "device-meeting-room-remote" }
    ]
    /// A device page shown (its collection key), or "".
    property string devicePage: ""
    property var deviceData: null
    property int deviceShown: 24
    readonly property string deviceCall: "devices:" + Math.floor(Math.random() * 1e9).toString(36)
    function openDevices(key) {
        menu.close(); manage.visible = false
        page = ""; devicePage = key; deviceData = null; deviceShown = 24; tab = "devices"
        devFlick.contentY = 0
        backend.storeRequest("devices", deviceCall, JSON.stringify({ key: key }))
    }
    Connections {
        target: backend
        function onStoreReply(id, json) {
            if (id !== root.deviceCall) return
            const r = JSON.parse(json)
            if (r.key === root.devicePage || r.error) root.deviceData = r
        }
    }
    /// The app page's filter: the options picked (Teams' feature names).
    property var picked: []
    onPageChanged: picked = []
    readonly property var pageApps: root.page === "search" ? (root.found && root.found.results ? root.found.results : []) : (root.pageData && root.pageData.apps ? root.pageData.apps : [])
    readonly property var filteredApps: picked.length === 0 ? pageApps : pageApps.filter(a => (a.features || []).some(f => picked.indexOf(f) >= 0))

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
    /// Teams' Platform staticsPath (its public evergreen assets).
    readonly property string statics: "https://teams.public.onecdn.static.microsoft"
    /// Go in the quick-start dialog: use the app there (Main sets it up).
    signal useAppIn(var app, var place)

    onVisibleChanged: if (visible && !feedCols.length && !busy) load()
    // Teams marks the header tab whose menu lists the collection (Popular
    // on Teams' See all: Featured).
    function openPage(id) {
        devicePage = ""; manage.visible = false; page = id; menu.close(); backend.storePageLoad(id); pageFlick.contentY = 0
        if (root.featuredNav.some(g => g.some(n => n.id === id))) tab = "featured"
        else if (root.categoryNav.some(n => n.id === id)) tab = "categories"
    }
    function home() { devicePage = ""; manage.visible = false; page = ""; tab = "home"; search.text = ""; feedFlick.contentY = 0 }
    Timer { id: searchDelay; interval: 300; onTriggered: if (root.query) { root.devicePage = ""; root.page = "search"; backend.storeSearch(root.query) } else if (root.page === "search") root.page = "" }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Header.
    Item {
        id: header
        width: parent.width; height: 60
        Text { x: 16; y: 17.7; height: 24; verticalAlignment: Text.AlignVCenter; text: qsTr("Store"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Row {
            x: 72.4; y: 0; height: 59.3
            Repeater {
                model: [{ k: "home", l: qsTr("Home", "extensibility:k3y5ei9ay") }, { k: "featured", l: qsTr("Featured"), menu: true }, { k: "categories", l: qsTr("Categories"), menu: true }, { k: "devices", l: qsTr("Devices"), menu: true }]
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

    // The header's right side.
    Rectangle {
        visible: root.page !== "" || root.devicePage !== ""
        x: root.width - 96 - 384; y: 13.7; width: 384; height: 32; radius: 16
        color: theme.surface
        FluentSurface { anchors.fill: parent; z: -1; depth: 2; radius: 16; color: theme.surface }
        FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textStrong }
        TextField {
            id: headerSearch
            x: 44; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter
            placeholderText: qsTr("Search agents and apps"); placeholderTextColor: theme.textSecondary
            background: null; padding: 0
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            onTextEdited: search.text = text
            Keys.onEscapePressed: { text = ""; search.text = "" }
            Accessible.name: qsTr("Store Search")
        }
    }
    Repeater {
        model: [{ k: "yours", icon: "library-20", tip: qsTr("Your agents and apps"), x: 84 }, { k: "manage", icon: "settings-20", tip: qsTr("Manage your apps"), x: 48 }]
        Rectangle {
            id: hb
            required property var modelData
            x: root.width - modelData.x; y: 13; width: 32; height: 33.3; radius: 4
            color: hbHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: hb.modelData.k === "yours" && root.page === "yours" ? "library-20-filled" : hb.modelData.icon; size: 20; color: hb.modelData.k === "yours" && root.page === "yours" ? theme.brand : theme.textStrong }
            HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: hb.modelData.k === "manage" ? root.openManage() : root.openYours() }
            ToolTip.visible: hbHover.hovered; ToolTip.delay: 500; ToolTip.text: modelData.tip
            Accessible.role: Accessible.Button; Accessible.name: modelData.tip
        }
    }
    function openManage() { menu.close(); manage.visible = true; manage.load() }
    // "Your agents and apps": your apps as Store cards, with Teams' chips.
    property var yourApps: []
    property string yourChip: ""
    readonly property string yoursCall: "yours:" + Math.floor(Math.random() * 1e9).toString(36)
    function openYours() {
        menu.close(); manage.visible = false; devicePage = ""; page = "yours"; tab = ""; yourChip = ""
        backend.storeRequest("manageApps", yoursCall, JSON.stringify({ sort: "recent" }))
    }
    Connections {
        target: backend
        function onStoreReply(id, json) {
            if (id !== root.yoursCall) return
            const r = JSON.parse(json)
            root.yourApps = (r.apps || []).filter(a => a.personal).map(a => ({ id: a.id, name: a.name, developer: a.developer, icon: a.icon, installed: true, source: a.source, short: "" }))
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
        readonly property var groups: kind === "featured" ? root.featuredNav : kind === "devices" ? [root.devicesNav] : [root.categoryNav]
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
                            FluentIcon { visible: !!mi.modelData.icon; x: 6; anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.icon + "-20"; size: 20; color: theme.onFill(mi, theme.textSecondary) }
                            Text { x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40; elide: Text.ElideRight; text: mi.modelData.title; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(mi, theme.text) }
                            HoverHandler { id: miHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { if (menu.kind === "devices") root.openDevices(mi.modelData.id); else { root.tab = menu.kind; root.openPage(mi.modelData.id) } } }
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
        Rectangle { id: hcFill1; anchors.fill: parent; radius: 12; color: cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent" }
        Item {
            x: 16; y: 16; width: 52; height: 52
            Rectangle { anchors.fill: parent; color: theme.quoteFill }
            Image { anchors.fill: parent; source: card.app.icon || ""; sourceSize: Qt.size(104, 104); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true }
            RoundedCorners { anchors.fill: parent; squircle: true; background: cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : theme.surface }
            // You have it: Teams' check in a 24 px white circle on the
            // icon's corner.
            FluentSurface {
                visible: !!card.app.installed
                x: 29; y: 32; width: 24; height: 24; radius: 12; depth: 4
                color: theme.surface
                FluentIcon { anchors.centerIn: parent; name: "checkmark-16"; size: 16; color: theme.onFill(hcFill1, theme.text) }
                Accessible.role: Accessible.Graphic; Accessible.name: qsTr("Added")
            }
        }
        // The name, then Teams' marks after it (store item `Gt`): Microsoft
        // 365 certified (ShieldCheckmark) and "Includes an agent and uses
        // AI" (Sparkle), each a 16 px glyph in a 26 x 20 box (6 in, 3 down).
        Row {
            id: nameRow
            x: 84; y: 21; height: 20
            readonly property var marks: (card.app.features || []).indexOf("Certified") >= 0
                ? [{ icon: "shield-checkmark-20", tip: qsTr("Microsoft 365 certified") }].concat(card.app.agent ? [{ icon: "sparkle-20", tip: qsTr("Includes an agent and uses AI") }] : [])
                : card.app.agent ? [{ icon: "sparkle-20", tip: qsTr("Includes an agent and uses AI") }] : []
            Text { width: Math.min(implicitWidth, card.width - 84 - 16 - nameRow.marks.length * 26); height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: card.app.name; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
            Repeater {
                model: nameRow.marks
                Item {
                    required property var modelData
                    width: 26; height: 20
                    FluentIcon { x: 6; y: 3; name: parent.modelData.icon; size: 16; color: theme.onFill(hcFill1, theme.text) }
                    HoverHandler { id: markHover }
                    ToolTip.visible: markHover.hovered; ToolTip.text: modelData.tip; ToolTip.delay: 500
                    Accessible.role: Accessible.Graphic; Accessible.name: modelData.tip
                }
            }
        }
        Text { visible: card.full; x: 84; y: 42; width: card.width - 100; height: 16; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: card.app.developer || ""; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill1, theme.text) }
        Text {
            x: 84; y: card.full ? 70 : 45; width: card.width - 100
            rightPadding: 40
            maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            text: card.app.short || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill1, theme.text)
        }
        Row {
            visible: card.rated
            x: 84; y: card.full ? 116 : 91; height: 16; spacing: 3
            FluentIcon { name: "star-16-filled"; size: 16; color: theme.onFill(hcFill1, theme.brandFill) }
            Text { height: 16; verticalAlignment: Text.AlignVCenter; textFormat: Text.StyledText; text: "<b>" + (card.app.average_text || "") + "</b> (" + (card.app.count_text || "") + " ratings)"; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill1, theme.text) }
        }
        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        // Teams (store item click, enableStoreTileDesignWithoutCta): an app
        // you have opens the quick-start dialog; others their details.
        TapHandler { onTapped: card.app.installed ? quickStart.show(card.app) : details.show(card.app.id) }
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
            text: qsTr("See all"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandForeground1
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openPage(sec.col.id) }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("See all %1").arg(sec.col.title)
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
        visible: !root.page && !root.devicePage
        anchors { fill: parent; topMargin: header.height + 0.7 }
        contentHeight: feedCol.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: feedCol
            width: parent.width
            // The banner (Teams' store header): 276 tall, its artwork 300
            // tall behind the feed's start: #E8EBFA to 80% then the page
            // colour, with Teams' ribbon pictures (345 and 356 x 300, its
            // evergreen assets, the dark ones in dark and high contrast) at
            // both ends from 720 wide.
            Item {
                width: parent.width; height: 276
                Rectangle {
                    width: parent.width; height: 300
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: theme.pick("#E8EBFA", "#2B2B40", "#000000") }
                        GradientStop { position: 0.8; color: theme.pick("#E8EBFA", "#2B2B40", "#000000") }
                        GradientStop { position: 1.0; color: theme.surface }
                    }
                    Image {
                        visible: root.width >= 720
                        width: 345; height: 300
                        source: visible ? (backend.emoticonsVersion, backend.cardImage(root.statics + "/evergreen-assets/apps/store/header_ribbon_left" + (theme.dark || theme.highContrast ? "_dark" : "") + ".png")) : ""
                        asynchronous: true; smooth: true
                    }
                    Image {
                        visible: root.width >= 720
                        anchors.right: parent.right
                        width: 356; height: 300
                        source: visible ? (backend.emoticonsVersion, backend.cardImage(root.statics + "/evergreen-assets/apps/store/header_ribbon_right" + (theme.dark || theme.highContrast ? "_dark" : "") + ".png")) : ""
                        asynchronous: true; smooth: true
                    }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 60; height: 56; verticalAlignment: Text.AlignVCenter; text: qsTr("Do more in Teams"); font.family: theme.font; font.pixelSize: 40; font.weight: Font.DemiBold; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 116; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Discover agents and apps that can help you tackle any task."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                // The search: a 580 x 48 white pill with a soft shadow and
                // a 2 px brand line 12 in from each end at its foot.
                FluentSurface {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 168; width: Math.min(580, root.width - 80); height: 48; radius: 24; depth: 2
                    color: theme.surface
                    Rectangle { anchors.bottom: parent.bottom; x: 12; width: parent.width - 24; height: 2; color: theme.brand }
                    FluentIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
                    TextField {
                        id: search
                        x: 44; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter
                        placeholderText: qsTr("Search agents and apps"); placeholderTextColor: theme.textSecondary
                        background: null
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        onTextChanged: searchDelay.restart()
                        Keys.onEscapePressed: text = ""
                        Accessible.name: qsTr("Search agents and apps")
                    }
                }
            }
            Text {
                visible: !!root.reply.error
                x: 90; topPadding: 24
                text: qsTr("We couldn't load the Store. %1").arg(root.reply.error || "")
                font.family: theme.font; font.pixelSize: 14; color: theme.danger
            }
            Repeater {
                model: root.feedCols
                Item { required property var modelData; width: feedCol.width; height: s.height; Section { id: s; x: 90; col: parent.modelData } }
            }
        }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.busy && !root.page && !root.devicePage; visible: running }

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
                    id: hcFill2
                    x: 0; y: 63; width: 32; height: 32; radius: 4
                    color: backHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.onFill(hcFill2, theme.textSecondary) }
                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.home() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
                }
                Text {
                    x: 40; y: 61; height: 36; verticalAlignment: Text.AlignVCenter
                    text: root.page === "yours" ? qsTr("Your agents and apps") : root.page === "search" ? qsTr("Search results for \"%1\"").arg(root.query) + (root.found && root.found.results ? " (" + root.found.results.length + ")" : "") : (root.pageData && root.pageData.title ? root.pageData.title : "")
                    font.family: theme.font; font.pixelSize: 30; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Text { visible: root.page === "yours" || root.page !== "search" && !!(root.pageData && root.pageData.description); x: 40; y: 109; width: 580; wrapMode: Text.Wrap; lineHeight: 22; lineHeightMode: Text.FixedHeight; text: root.page === "yours" ? qsTr("See all the apps and agents you added, your org added for you, or people shared with you.") : root.pageData && root.pageData.description ? root.pageData.description : ""; font.family: theme.font; font.pixelSize: 16; color: theme.text }
            }
            // Your agents and apps' chips.
            Flow {
                visible: root.page === "yours"
                x: 40; width: parent.width - 40; spacing: 8
                Repeater {
                    model: [{ k: "you", l: qsTr("Added by you") }, { k: "created", l: qsTr("Created by you") }, { k: "org", l: qsTr("Added by your org") }, { k: "built", l: qsTr("Built for your org") }, { k: "shared", l: qsTr("Shared with you") }]
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: root.yourChip === modelData.k
                        width: chipText.implicitWidth + 32; height: 32; radius: 16
                        color: on ? theme.pick("#EBF3FC", "#2B2B40", "#1AEBFF") : (chipHover.hovered ? theme.menuHover : theme.surface)
                        border.width: 0.67; border.color: on ? theme.brand : theme.stroke
                        Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.yourChip = chip.on ? "" : chip.modelData.k }
                        Accessible.role: Accessible.CheckBox; Accessible.name: chip.modelData.l; Accessible.checked: chip.on
                    }
                }
            }
            // The filter: its picked options as pills, then the button.
            Item {
                visible: root.page !== "yours" && root.pageApps.length > 0
                width: parent.width; height: 64 + 33 + 42
                Row {
                    anchors.right: filterBtn.left; anchors.rightMargin: 8; y: 68; spacing: 8
                    Repeater {
                        model: root.picked
                        Rectangle {
                            id: pill
                            required property var modelData
                            width: pillText.implicitWidth + 15.4; height: 25; radius: 12.5; color: theme.brandFill
                            Text { id: pillText; anchors.centerIn: parent; text: root.optionLabel(pill.modelData); font.family: theme.font; font.pixelSize: 14; color: theme.textOnBrand }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.picked = root.picked.filter(x => x !== pill.modelData) }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Applied filter, %1, button, use backspace to remove the filter").arg(pillText.text)
                        }
                    }
                }
                Rectangle {
                    id: filterBtn
                    x: parent.width - 96.5 - 32 + 40; y: 64; width: 32; height: 32; radius: 16
                    color: fbHover.hovered || filterPop.opened ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "filter-20"; size: 20; color: root.picked.length ? theme.brand : theme.textStrong }
                    HoverHandler { id: fbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: filterPop.openAt(filterBtn, root.filterGroups) }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.picked.length > 1 ? qsTr("Filter (%1), %1 filters applied").arg(root.picked.length) : qsTr("Filter (%1), %1 filter applied").arg(root.picked.length)
                }
            }
            Text {
                visible: root.page === "yours" ? false : root.page === "search" ? !root.found || !!root.found.loading : !root.pageData || !!root.pageData.loading
                x: 40; topPadding: 24; text: qsTr("Loading…"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            Flow {
                x: 40; width: parent.width - 40; spacing: 10
                Repeater {
                    model: root.page === "yours" ? root.yourApps.filter(a => !root.yourChip || a.source === root.yourChip) : root.filteredApps
                    AppCard { required property var modelData; app: modelData; full: true; noRatings: root.page !== "search" && !!(root.pageData && root.pageData.no_ratings) }
                }
            }
            Repeater {
                model: root.page !== "search" && root.page !== "yours" && root.pageData && root.pageData.sections ? root.pageData.sections : []
                Item { required property var modelData; width: pageCol.width; height: gs.height; Section { id: gs; x: 40; col: parent.modelData } }
            }
        }
    }

    // The filter tree's groups for the page's apps (Teams' collection
    // filter: only the options its apps have).
    readonly property var optionLabels: ({
        Available: qsTr("Ready to add"), Blocked: qsTr("Requires approval"),
        Free: qsTr("Free to add"), Paid: qsTr("Subscription plans available"),
        Certified: qsTr("Microsoft 365 certified"), PublisherAttested: qsTr("Publisher attested"),
        SharedChannelTypeSupported: qsTr("Shared Channel"), PrivateChannelTypeSupported: qsTr("Private Channel"),
        Bot: qsTr("Bot"), Connector: qsTr("Connector"), CopilotPlugin: qsTr("Agent"), GroupChat: qsTr("Group Chat"),
        Meeting: qsTr("Meeting"), MessageExtension: qsTr("Messaging"), Personal: qsTr("Personal"), Tab: qsTr("Tab")
    })
    function optionLabel(k) { return optionLabels[k] || k }
    readonly property var filterGroups: {
        const have = {}
        for (const a of root.pageApps) for (const f of (a.features || [])) have[f] = true
        const g = (title, keys, col) => ({ title: title, col: col, options: keys.filter(k => have[k]) })
        return [
            g(qsTr("Availability"), ["Available", "Blocked"], 0),
            g(qsTr("Pricing"), ["Free", "Paid"], 0),
            g(qsTr("Certification"), ["Certified", "PublisherAttested"], 0),
            g(qsTr("Supported Channel"), ["SharedChannelTypeSupported", "PrivateChannelTypeSupported"], 0),
            g(qsTr("App features"), ["Bot", "Connector", "CopilotPlugin", "GroupChat", "Meeting", "MessageExtension", "Personal", "Tab"], 1)
        ].filter(x => x.options.length > 0)
    }
    // Teams' filter tree (store-collection-filter-tree; measured): a
    // white popover, radius 4, 12.7 in; "Filter" (14/20 bold) and "Clear"
    // (14/20 semibold, #BDBDBD until something is picked) on a 37.3 row;
    // groups in 220 wide columns, each a 34 tall bold title row with its
    // checkbox (16 px, #616161 edge, radius 2, brand when on) at 188 and its
    // options under it, a #E0E0E0 rule between groups.
    Popup {
        id: filterPop
        property var groups: []
        /// The device pages' tree: only App features, with nothing in it.
        property bool devices: false
        function openAt(btn, gs) {
            groups = gs; devices = false
            const p = btn.mapToItem(root, 0, 0)
            const cols = groups.some(g => g.col === 1) && groups.some(g => g.col === 0) ? 2 : 1
            width = 220 * cols + 25.4
            x = Math.max(8, p.x + btn.width - width); y = p.y + btn.height
            open()
        }
        function openDevices(btn) {
            groups = [{ title: qsTr("App features"), col: 1, options: [] }]; devices = true
            const p = btn.mapToItem(root, 0, 0)
            width = 245.3
            x = Math.max(8, p.x + btn.width - width); y = p.y + btn.height
            open()
        }
        property bool emptyGroupOn: false
        padding: 12.7
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            Item {
                width: filterPop.width - 25.4; height: 37.3
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Filter"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                Text {
                    readonly property bool can: root.picked.length > 0 || filterPop.emptyGroupOn
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Clear"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: can ? theme.textStrong : theme.disabled
                    HoverHandler { cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: { root.picked = []; filterPop.emptyGroupOn = false } }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Clear")
                }
            }
            Rectangle { width: filterPop.width - 25.4; height: 0.67; color: theme.divider }
            Row {
                Repeater {
                    model: [0, 1]
                    Column {
                        id: colItem
                        required property int modelData
                        readonly property var gs: filterPop.groups.filter(g => g.col === modelData || filterPop.groups.every(x => x.col === g.col))
                        visible: gs.length > 0 && (modelData === 0 || filterPop.groups.some(g => g.col === 0))
                        width: 220
                        Repeater {
                            model: colItem.modelData === 0 || filterPop.groups.some(g => g.col === 0) ? colItem.gs : []
                            Column {
                                id: grp
                                required property var modelData
                                required property int index
                                width: 212; x: 4
                                Rectangle { visible: grp.index > 0; width: parent.width; height: 0.67; color: theme.divider }
                                FilterRow {
                                    label: grp.modelData.title; bold: true
                                    checked: filterPop.devices ? filterPop.emptyGroupOn : grp.modelData.options.length > 0 && grp.modelData.options.every(o => root.picked.indexOf(o) >= 0)
                                    onToggled: {
                                        if (filterPop.devices) { filterPop.emptyGroupOn = !filterPop.emptyGroupOn; return }
                                        const all = grp.modelData.options.every(o => root.picked.indexOf(o) >= 0)
                                        root.picked = all ? root.picked.filter(x => grp.modelData.options.indexOf(x) < 0) : root.picked.concat(grp.modelData.options.filter(o => root.picked.indexOf(o) < 0))
                                    }
                                }
                                Repeater {
                                    model: grp.modelData.options
                                    FilterRow {
                                        required property var modelData
                                        label: root.optionLabel(modelData)
                                        checked: root.picked.indexOf(modelData) >= 0
                                        onToggled: root.picked = checked ? root.picked.filter(x => x !== modelData) : root.picked.concat([modelData])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    component FilterRow: Rectangle {
        id: fr
        property string label
        property bool bold: false
        property bool checked: false
        signal toggled()
        width: 212; height: 34
        color: frHover.hovered ? theme.menuHover : "transparent"
        Text { x: 0; anchors.verticalCenter: parent.verticalCenter; text: fr.label; font.family: theme.font; font.pixelSize: 14; font.weight: fr.bold ? Font.DemiBold : Font.Normal; color: theme.onFill(fr, fr.checked ? theme.text : theme.textStrong) }
        Rectangle {
            x: 184; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 2
            color: fr.checked ? theme.checkedFill : "transparent"
            border.width: fr.checked ? 0 : 0.67; border.color: theme.textSecondary
            FluentIcon { visible: fr.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand }
        }
        HoverHandler { id: frHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: fr.toggled() }
        Accessible.role: Accessible.CheckBox; Accessible.name: fr.bold ? qsTr("%1 checkbox, press spacebar to select all.").arg(fr.label) : fr.label; Accessible.checked: fr.checked
    }

    // The device store's band: the region and the cart.
    Rectangle {
        visible: root.devicePage !== ""
        y: header.height + 0.7; width: parent.width; height: 28; z: 2
        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
        Row {
            anchors.right: cartPill.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 4
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "globe-16"; size: 16; color: theme.textStrong }
            Text {
                anchors.verticalCenter: parent.verticalCenter; text: qsTr("USA"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
                HoverHandler { id: regionHover }
                TapHandler { onTapped: regionTip.visible = !regionTip.visible }
                ToolTip { id: regionTip; visible: regionHover.hovered; delay: 300; text: qsTr("Your region is set to %1.").arg(qsTr("United States")) }
            }
        }
        Rectangle {
            id: cartPill
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: cartRow.implicitWidth + 13.4; height: 24; radius: 12
            color: cartHover.hovered ? theme.brandHover : theme.brandFill
            Row { id: cartRow; anchors.centerIn: parent; spacing: 4; FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "cart-20"; size: 20; color: theme.textOnBrand } Text { anchors.verticalCenter: parent.verticalCenter; text: root.cartCount; font.family: theme.font; font.pixelSize: 12; color: theme.textOnBrand } }
            HoverHandler { id: cartHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: cartDialog.open() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Cart with total item quantity %1").arg(root.cartCount)
        }
    }
    // A device page.
    Flickable {
        id: devFlick
        visible: root.devicePage !== ""
        anchors { fill: parent; topMargin: header.height + 0.7 + 28 }
        contentHeight: devCol.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Teams shows 24 devices and more as you scroll.
        onContentYChanged: if (root.deviceData && root.deviceData.devices && contentY + height > contentHeight - 400 && root.deviceShown < root.deviceData.devices.length) root.deviceShown += 24
        Rectangle {
            width: parent.width; height: 400
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.dark ? theme.hc("#2B2B40", "#000000") : theme.hc("#E8EBFA", "#000000") }
                GradientStop { position: 1.0; color: theme.surface }
            }
        }
        Column {
            id: devCol
            x: 45.5; width: Math.min(1100, root.width - 90)
            Item {
                width: parent.width; height: devDesc.visible ? devDesc.y + devDesc.height : 96
                Rectangle {
                    id: devBack
                    x: 0; y: 62; width: 32; height: 32; radius: 4
                    color: devBackHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "chevron-left-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: devBackHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.home() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
                }
                Text {
                    x: 40; y: 60; height: 36; verticalAlignment: Text.AlignVCenter
                    text: root.deviceData && root.deviceData.title ? root.deviceData.title : (root.devicesNav.find(d => d.id === root.devicePage) || { title: "" }).title
                    font.family: theme.font; font.pixelSize: 30; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Text {
                    id: devDesc
                    visible: !!(root.deviceData && root.deviceData.description)
                    x: 40; y: 108; width: 580; wrapMode: Text.Wrap; lineHeight: 22; lineHeightMode: Text.FixedHeight
                    text: root.deviceData ? root.deviceData.description || "" : ""
                    font.family: theme.font; font.pixelSize: 16; color: theme.text
                }
            }
            Item {
                width: parent.width; height: 64 + 32 + 42
                Rectangle {
                    id: devFilterBtn
                    x: 1028 * Math.min(1, (devCol.width) / 1100); y: 64; width: 32; height: 32; radius: 16
                    color: dfHover.hovered || (filterPop.opened && filterPop.devices) ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "filter-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: dfHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: filterPop.openDevices(devFilterBtn) }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Filter (%1), %1 filter applied").arg(0)
                }
            }
            Text {
                visible: !root.deviceData || !!root.deviceData.error
                x: 40; text: root.deviceData && root.deviceData.error ? qsTr("Looks like we can't show you this link.") : qsTr("Loading…")
                font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            Flow {
                x: 42; width: parent.width - 42; spacing: 16
                Repeater {
                    model: root.deviceData && root.deviceData.devices ? root.deviceData.devices.slice(0, root.deviceShown) : []
                    DeviceTile { required property var modelData; device: modelData; onOpened: deviceDetails.show(modelData) }
                }
            }
        }
    }
    component DeviceTile: Item {
        id: tile
        property var device
        signal opened()
        width: 239; height: 312
        Rectangle { anchors.fill: parent; radius: 12; color: tileHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent" }
        Rectangle {
            x: 16; y: 16; width: 207; height: 160; radius: 4; color: "#FFFFFF"
            Image { anchors.fill: parent; source: tile.device.image || ""; fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true; sourceSize: Qt.size(414, 320) }
        }
        Text { x: 16; y: 188; width: 207; height: 16; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: tile.device.name; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 16; y: 208; width: 207; height: 16; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: tile.device.maker; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Text { x: 16; y: 232; height: 20; verticalAlignment: Text.AlignVCenter; text: tile.device.price_text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
        Text { x: 16; y: 264; width: 207; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight; lineHeight: 16; lineHeightMode: Text.FixedHeight; text: tile.device.short; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tile.opened() }
        Accessible.role: Accessible.ListItem; Accessible.name: tile.device.name + ", " + tile.device.maker + ", " + tile.device.price_text
    }
    DeviceDetailsDialog {
        id: deviceDetails
        cartIds: root.cart.items.map(x => String(x.id))
        onAddToCart: (d, q) => root.addToCart(d, q)
        onViewCart: { deviceDetails.close(); cartDialog.open() }
        onCopyLink: d => { backend.copyText("https://teams.microsoft.com/l/devices/" + encodeURIComponent(d.id) + "?market=US"); root.toast({ text: qsTr("Link copied") }) }
    }
    DeviceCartDialog {
        id: cartDialog
        cart: root.cart
        onSetQuantity: (id, q) => root.saveCart(root.cart.items.map(x => x.id === id ? Object.assign({}, x, { quantity: q }) : x))
        onRemoveItem: id => root.saveCart(root.cart.items.filter(x => x.id !== id))
        onCheckout: { cartDialog.close(); root.checkoutRequested(root.cart) }
    }
    /// Checkout: Teams opens the fulfiller's store, the Client Store app of
    /// ECS marketplace.appManifestUC (its personal tab,
    /// clientstore.unifiedcommunications.com) in its host in a dialog
    /// (DeviceStoreCart panel, frameContext content, not cached); the page
    /// reads the cart through TeamsJS marketplace.getCart.
    signal checkoutRequested(var cart)
    onCheckoutRequested: c => checkoutDialog.start(c)
    Popup {
        id: checkoutDialog
        property var teamsCart: null
        function start(c) {
            const now = new Date().toISOString()
            teamsCart = {
                cartInfo: { market: "US", intent: "TACAdminUserCheckout", locale: "en-us", id: "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, ch => { const r = Math.random() * 16 | 0; return (ch === "x" ? r : (r & 3 | 8)).toString(16) }),
                            version: { majorVersion: 1, minorVersion: 0 }, status: "Open", createdAt: c.createdAt || now, updatedAt: now },
                cartItems: c.items.map(x => ({ id: String(x.id), name: x.name, quantity: x.quantity, price: x.price, thumbnailImageUrl: x.image || "" }))
            }
            open()
        }
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: Math.min(1000, root.width - 80); height: Math.min(700, root.height - 40); padding: 0
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Loader {
            anchors.fill: parent; anchors.topMargin: 44
            active: checkoutDialog.opened
            sourceComponent: WebApp {
                showHeader: false; teamsHost: true
                appName: "Client Store"; appId: "b01e20a2-2ee3-4eb9-91d9-18fbb1c33705"
                home: "https://clientstore.unifiedcommunications.com/"
                hostContext: ({ entityId: "index0", subEntityId: "" })
                marketplaceCart: checkoutDialog.teamsCart
            }
        }
        Rectangle {
            x: parent.width - 52; y: 8; width: 32; height: 31.3; radius: 4
            color: coHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: coHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: checkoutDialog.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
    }
    // Manage your apps, over the Store.
    ManageAppsView {
        id: manage
        visible: false
        anchors.fill: parent; z: 5
        onBack: visible = false
        onGetMoreApps: { visible = false; root.home() }
        onViewDetails: id => details.show(id)
        onToast: d => root.toast(d)
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
            else backend.openExternal("https://teams.microsoft.com/l/app/" + encodeURIComponent(id))
        }
    }
    ShareForm { id: storeShare }
    // Teams' quick-start dialog ("Let's go") for an app you have.
    ContextlessDialog {
        id: quickStart
        onOpenApp: (id, name) => details.openApp(id, name)
        onUseIn: (app, place) => root.useAppIn(app, place)
    }

    // Test harness hooks
    function searchForTest(q) { search.text = q }
    /// The quick-start dialog again (a tab configuration's Back).
    function quickStartShow(app) { quickStart.show(app) }
    function quickStartForTest(name) {
        for (const c of root.feedCols) for (const a of c.apps) if (a.name === name) { quickStart.show(a); return quickStart }
        return null
    }
    function detailsForTest(name) {
        for (const c of root.feedCols) for (const a of c.apps) if (a.name === name) { details.show(a.id); return true }
        return false
    }
    function menuForTest(kind) { menu.kind = kind; menu.x = kind === "featured" ? 134 : kind === "devices" ? 358.2 : 240; menu.open() }
    function deviceDetailsForTest(i) { const d = root.deviceData && root.deviceData.devices ? root.deviceData.devices[i] : null; if (d) deviceDetails.show(d); return d ? d.name : "" }
    function deviceDetailsStateForTest() { return deviceDetails.stateForTest() }
    function closeDeviceDialogsForTest() { deviceDetails.close(); cartDialog.close(); filterPop.close() }
    function addFirstToCartForTest() { if (deviceDetails.d) root.addToCart(deviceDetails.d, 1) }
    function openCartForTest() { deviceDetails.close(); cartDialog.open() }
    function emptyCartForTest() { root.saveCart([]) }
    function deviceFilterForTest() { filterPop.openDevices(devFilterBtn) }
    function appFilterForTest() { filterPop.openAt(filterBtn, root.filterGroups); return JSON.stringify(root.filterGroups.map(g => [g.title, g.options])) }
    function pickForTest(keys) { root.picked = keys; return root.filteredApps.length + "/" + root.pageApps.length }
    function manageForTest() { return manage }
    function closeMenuForTest() { menu.close() }
}
