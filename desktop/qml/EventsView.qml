import QtQuick
import QtQuick.Controls.Basic

// Teams' Events app, drawn natively as Teams draws it itself (it is not a
// hosted page): docs/spec/events.md, measured in Teams on the web as
// ost-test1 on 2026-11-16 in a 1212 x 752 window (app area 1144 wide from
// x 68, its header 61 tall at y 84). The data is the virtual events
// service's (api::events through backend.eventsRequest).
// - Header (#FAFAFA): the app's 32 px tile (#5B5FC7, radius 4, a 20 px
//   white ticket) 20 in and 14 down, "Events" 20/28.57 semibold #616161
//   at 60; the Discover and Manage tabs (44 tall, text 10 in, 14/20,
//   semibold #242424 when chosen with the brand line, else #424242) from
//   136; on the right Pin app, Filters (Discover only) and Create event
//   (outlined, white, #D1D1D1), 32 tall, 8 apart, 20 from the edge.
// - Discover: the sticky intro card (#F5F5F5, #D1D1D1, radius 16, 17 in,
//   32 from the top and sides), the lists or the empty state (128 px
//   picture, "No events have been scheduled yet" 16/22 bold, the hint
//   14/20 in 450, Create event 155 x 38), then "Get started with a
//   template" (16/22 semibold) and the template cards (517 x 317 at 1144:
//   two columns 16 apart, radius 24, card shadow; the picture panel
//   #FAFAFA radius 16, 163 tall, 12 in; title 16/22 semibold, text 14/20,
//   feature chips 24 tall #F5F5F5).
// - Manage: Connect apps (right), Drafts (n), Published and Past with up to
//   four event cards each (351 x 303, radius 24: the promo picture 109
//   tall, the title 16/22 semibold, the time 14/20 #616161, Organizer and
//   Online 12/16, Edit and ···), or the empty state and the templates.
// - Create event: "Create" with a back arrow, "Choose what you're
//   organizing" and Create from scratch plus the templates in three
//   columns (347 x 292, 20 apart); a choice opens the New event form.
// - The form: Save and continue (primary, top right), the welcome card,
//   and four cards (white, radius 16, 25 in): Add event details (Name,
//   Start/End date and time, Location, Description), Who's planning the
//   event?, Who can attend? (Public / Your organization / Specific people
//   and groups, Turn on registration?) and Set up experience and options
//   (capacity, Optimize for large audience, Attendee participation tiles,
//   Enable green room). Save asks "Save as a draft and continue?" and
//   makes the draft (POST events), then shows it with "Draft event
//   created".
Rectangle {
    id: root
    color: theme.pick("#FAFAFA", "#141414", "#000000")
    /// "discover" or "manage".
    property string tab: "discover"
    /// "" (the tab), "create" (choose a template), "form" (New event) or
    /// "event" (an event's page).
    property string page: ""
    property var discoverData: null
    property var manageData: null
    property var features: null
    property var current: null
    property string loadError: ""
    property bool filtersOpen: false
    property bool myEvents: false
    property string dateRange: ""
    property bool welcome: true
    property bool pinned: backend.setting("eventsAppPinned") === "true"
    signal pinToggled(bool on)
    signal viewMeetings()
    signal toast(var d)
    /// The event page's Join: its meeting's pre-join.
    signal joinEvent(string url, string title, string start, string end)
    /// The event page's chat button: the event meeting's chat.
    signal openEventChat(string chatId, string title)
    /// Copy join details: the title, time and join link (Teams' own text
    /// wasn't captured).
    function joinDetails(ev) {
        return (ev.title || "") + "\n" + whenText(ev.start, ev.end, true) + "\n\nJoin: " + (ev.join_url || "")
    }

    readonly property string cdn: "https://teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/"
    readonly property var templates: [
        { key: "scratch", title: "Create from scratch", text: "Mix and match capabilities as you go", img: "webp/192/design-l-standard-192x192.webp", chips: [], type: "Webinar" },
        { key: "webinar", title: "Webinar", text: "Best for interactive trainings, product demos, or thought leadership sessions", img: "webp/192/person-presentation-l-standard-192x192.webp", chips: ["Registration", "Video on demand", "Waitlist", "Green room"], type: "Webinar" },
        { key: "townhall", title: "Town hall", text: "Reach a large audience with a professional produced broadcast", img: "v2/person-video-live-l-standard.svg", chips: ["Up to 10K attendees", "Green room", "Video on demand", "HD video stream"], type: "Townhall" },
        { key: "allhands", title: "All hands", text: "Share organization updates and engage employees at scale", img: "v2/web-meet-l-standard.svg", chips: ["Moderated Q&A", "Real-time reactions", "Green room", "Video on demand"], type: "Townhall" },
        { key: "training", title: "Training", text: "Teach, onboard, or upskill with an interactive session", img: "v2/book-pencil-l-standard.svg", chips: ["Breakout rooms", "Polls", "Live captions", "Registration", "Video on demand"], type: "Webinar" },
        { key: "ama", title: "Ask me anything", text: "Open Q&A sessions with moderated audience questions", img: "v2/chat-multiple-l-standard.svg", chips: ["Moderated Q&A", "Polls", "Green room", "Producer controls"], type: "Webinar" },
        { key: "community", title: "Community event", text: "Bring a community together for virtual experiences", img: "webp/192/people-house-l-standard-192x192.webp", chips: ["Registration", "Event chat", "Highlights", "Green room", "Waitlist"], type: "Webinar" }
    ]

    // Requests to the events service, answered by events_reply.
    property var pending: ({})
    property int seq: 0
    function call(kind, payload, cb) {
        const id = "events" + (++seq)
        const p = Object.assign({}, pending); p[id] = cb; pending = p
        backend.eventsRequest(kind, id, JSON.stringify(payload || {}))
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            const cb = root.pending[id]
            if (!cb) return
            const p = Object.assign({}, root.pending); delete p[id]; root.pending = p
            let v = {}
            try { v = JSON.parse(json) } catch (e) { v = { error: "Bad reply" } }
            cb(v)
        }
    }
    function range() {
        if (!dateRange) return {}
        const now = new Date(), start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        let end = new Date(start)
        if (dateRange === "today") end.setDate(end.getDate() + 1)
        else if (dateRange === "thisWeek") { start.setDate(start.getDate() - start.getDay()); end = new Date(start); end.setDate(end.getDate() + 7) }
        else if (dateRange === "thisMonth") { start.setDate(1); end = new Date(start.getFullYear(), start.getMonth() + 1, 1) }
        return { from: start.toISOString(), to: end.toISOString() }
    }
    function reload() {
        loadError = ""
        if (tab === "discover") call("discover", Object.assign({ myEvents: myEvents }, range()), v => { if (v.error) loadError = v.error; else discoverData = v })
        else call("manage", {}, v => { if (v.error) loadError = v.error; else manageData = v })
    }
    function openTab(t) { tab = t; page = ""; filtersOpen = false; reload() }
    function startCreate() { page = "create"; filtersOpen = false }
    /// Calendar ▸ New ▸ Webinar / Town hall: the form with that template.
    function startFormKey(key) { const t = templates.find(x => x.key === key); if (t) { filtersOpen = false; startForm(t) } }
    function startForm(t) {
        const now = new Date(), s = new Date(now)
        // Teams' default: the next half hour, for 30 minutes.
        s.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0)
        const e = new Date(s.getTime() + 30 * 60000)
        form.reset(t, s, e)
        page = "form"
        if (!features) call("features", {}, v => { if (!v.error) features = v })
    }
    function openEvent(card) { current = card; page = "event"; call("overview", { id: card.id }, v => { if (!v.error && v.card) current = Object.assign({}, v.card, { access: v.access, inviteOnly: v.inviteOnly, registration: v.registration }) }) }
    Component.onCompleted: reload()
    onVisibleChanged: if (visible && page === "") reload()
    function stateForTest() {
        return JSON.stringify({ tab: tab, page: page, error: loadError, discover: discoverData ? { now: (discoverData.now || []).length, upcoming: (discoverData.upcoming || []).length, past: (discoverData.past || []).length } : null,
                                manage: manageData ? { drafts: manageData.drafts ? manageData.drafts.total : 0, published: manageData.published ? manageData.published.total : 0, past: manageData.past ? manageData.past.total : 0,
                                                       draftTitles: manageData.drafts ? manageData.drafts.items.map(i => i.title) : [] } : null,
                                current: current ? { id: current.id, title: current.title, state: current.state } : null })
    }

    // ---- shared parts ----
    component Btn: Rectangle {
        id: b
        property string text
        property string icon
        property bool primary: false
        property bool outlined: false
        property bool usable: true
        property int fontSize: 14
        property real pad: 12
        signal clicked()
        height: 32; radius: 4
        implicitWidth: (icon ? 20 + (text ? 6 : 0) : 0) + bt.implicitWidth + pad * 2
        width: implicitWidth
        color: !usable ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : outlined ? (bh.hovered ? theme.menuHover : theme.surface) : (bh.hovered ? theme.hover : "transparent")
        border.width: outlined && usable ? 1 : 0
        border.color: theme.stroke
        Row {
            anchors.centerIn: parent
            spacing: 6
            FluentIcon { visible: !!b.icon; name: b.icon; size: 20; anchors.verticalCenter: parent.verticalCenter; color: !b.usable ? theme.disabled : b.primary ? theme.textOnBrand : theme.textStrong }
            Text {
                id: bt
                text: b.text; visible: !!b.text
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: b.fontSize; font.weight: b.fontSize >= 14 ? Font.DemiBold : Font.Normal
                color: !b.usable ? theme.disabledStrong : b.primary ? theme.textOnBrand : outlined ? theme.text : theme.textStrong
            }
        }
        HoverHandler { id: bh; cursorShape: b.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: b.usable; onTapped: b.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: b.text
        Accessible.onPressAction: if (b.usable) b.clicked()
    }
    component Chip: Rectangle {
        property alias text: ct.text
        height: 24; radius: 12; width: ct.implicitWidth + 16
        color: theme.pick("#F5F5F5", "#292929", "#000000")
        border.width: theme.highContrast ? 1 : 0; border.color: theme.stroke
        Text { id: ct; anchors.centerIn: parent; font.family: theme.font; font.pixelSize: 12; color: theme.text }
    }
    // A template card (the tab pages' and Create's).
    component TemplateCard: Item {
        id: tc
        required property var modelData
        property real imageHeight: 163
        signal picked()
        FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
        Rectangle {
            x: 12; y: 12; width: parent.width - 24; height: tc.imageHeight; radius: 16
            color: theme.pick("#FAFAFA", "#141414", "#000000")
            Image { anchors.centerIn: parent; width: 88; height: 88; source: root.cdn + tc.modelData.img; asynchronous: true; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(176, 176) }
        }
        Text {
            id: tt
            x: 20; y: tc.imageHeight + 24; width: parent.width - 40
            text: tc.modelData.title; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: 20; y: tt.y + 34; width: parent.width - 40
            text: tc.modelData.text; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
        }
        Flow {
            x: 12; y: tt.y + 92; width: parent.width - 24; spacing: 8
            Repeater { model: tc.modelData.chips; Chip { required property var modelData; text: modelData } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tc.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: tc.modelData.key === "scratch" ? tc.modelData.title : tc.modelData.title + " template, " + tc.modelData.text
    }
    // An event card (Manage's and Discover's lists).
    component EventCard: Item {
        id: ec
        required property var modelData
        width: 351; height: 303
        FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
        Rectangle {
            x: 12; y: 12; width: parent.width - 24; height: 109; radius: 16; clip: true
            color: ec.modelData.primary_color || "#5B5FC7"
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                source: { theme.dark; backend.emoticonsVersion; return ec.modelData.promo_image ? backend.cardImage(ec.modelData.promo_image) : "" }
            }
        }
        Text { x: 20; y: 131; width: parent.width - 40; text: ec.modelData.title; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        // Teams' card header (meet-app, measured 2026-11-18): a published
        // event shows a red "Live" badge (record glyph) from its start to
        // its end, or "in N mins" (clock, brand on #E8EBFA, rounded down
        // to 5, at least 5) in the hour before; the date follows it.
        property real now: Date.now()
        Timer { interval: 30000; running: ec.published; repeat: true; onTriggered: ec.now = Date.now() }
        readonly property bool published: ec.modelData.state === "Published"
        readonly property real startMs: ec.modelData.start ? new Date(ec.modelData.start).getTime() : 0
        readonly property real endMs: ec.modelData.end ? new Date(ec.modelData.end).getTime() : 0
        readonly property bool live: published && now >= startMs && now < endMs
        readonly property int soonMinutes: Math.floor((startMs - now) / 60000)
        readonly property bool soon: published && !live && soonMinutes >= 0 && soonMinutes <= 59
        // Teams' card actions: Join from 5 minutes before the start to the end.
        readonly property bool joinable: published && !!ec.modelData.join_url && now >= startMs - 300000 && now <= endMs
        Rectangle {
            id: ecBadge
            visible: ec.live || ec.soon
            x: 20; y: 160; height: 16; radius: 8
            width: ecBadgeRow.implicitWidth + (ec.live ? 10 : 6)
            color: ec.live ? "#D13438" : theme.pick("#E8EBFA", "#2F2F4A", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: theme.text
            Row {
                id: ecBadgeRow
                x: ec.live ? 4 : 2; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: ec.live ? "record-20" : "clock-12-filled"; size: ec.live ? 10 : 12
                             color: ec.live ? "#FFFFFF" : theme.brand }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ec.live ? "Live" : "in " + Math.max(5, Math.floor(ec.soonMinutes / 5) * 5) + " mins"
                       font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: ec.live ? "#FFFFFF" : theme.brand }
            }
        }
        Text { x: ecBadge.visible ? ecBadge.x + ecBadge.width + 4 : 20; y: ecBadge.visible ? 158 : 157; text: root.whenText(ec.modelData.start, ec.modelData.end, false); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        Column {
            x: 20; y: 187; spacing: 4
            Row { spacing: 4; visible: !!ec.modelData.role
                FluentIcon { name: "person-16"; size: 16; color: theme.textSecondary }
                Text { text: ec.modelData.role; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
            Row { spacing: 4
                FluentIcon { name: "location-20"; size: 16; color: theme.textSecondary }
                Text { text: ec.modelData.location || "Online"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
        }
        Btn { x: 20; y: 259; height: 24; text: "Edit"; icon: "edit-16"; outlined: true; fontSize: 12; pad: 8; visible: ec.modelData.state === "Draft" || (ec.published && !ec.joinable && /organizer/i.test(ec.modelData.role || "")); onClicked: root.openEvent(ec.modelData) }
        // Join (64 x 23, brand, the video glyph), Copy event page link and
        // More (24 x 23).
        Row {
            visible: ec.joinable
            x: 20; y: 261; spacing: 8
            Btn { height: 23; width: 64; primary: true; icon: "video-16"; text: "Join"; fontSize: 12; pad: 8; onClicked: root.joinEvent(ec.modelData.join_url, ec.modelData.title, ec.modelData.start, ec.modelData.end) }
            Btn { height: 23; width: 24; outlined: true; icon: "link-16"; text: ""; pad: 2; onClicked: { backend.copyText(ec.modelData.site_url || ec.modelData.join_url); root.toast({ text: "Copied", intent: "success" }) }
                  Accessible.name: "Copy event page link" }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openEvent(ec.modelData) }
        Accessible.role: Accessible.Button
        Accessible.name: "Event, " + ec.modelData.title + ", " + root.whenText(ec.modelData.start, ec.modelData.end, false)
    }
    // "Monday, Nov 16, 3:30 PM - 4:00 PM" (long: "Monday, November 16, …").
    function whenText(s, e, full) {
        if (!s) return ""
        const a = new Date(s), b = new Date(e || s)
        return Qt.formatDate(a, full ? "dddd, MMMM d" : "dddd, MMM d") + ", " + theme.time(a) + " - " + theme.time(b)
    }

    // ---- header ----
    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.pick("#FAFAFA", "#141414", "#000000")
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        Rectangle {
            x: 20; y: 14; width: 32; height: 32; radius: 4; color: "#5B5FC7"
            FluentIcon { anchors.centerIn: parent; name: "ticket-diagonal-20"; size: 20; color: "white" }
        }
        Text { x: 60; y: 15.7; text: "Events"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.textSecondary }
        Row {
            x: 136; y: 8
            Repeater {
                model: [["discover", "Discover"], ["manage", "Manage"]]
                Item {
                    required property var modelData
                    readonly property bool chosen: root.tab === modelData[0] && root.page === ""
                    width: tabText.implicitWidth + 20; height: 44
                    Text {
                        id: tabText
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]
                        font.family: theme.font; font.pixelSize: 14; font.weight: parent.chosen ? Font.DemiBold : Font.Normal
                        color: parent.chosen ? theme.text : theme.textStrong
                    }
                    Rectangle { visible: parent.chosen; x: 10; width: tabText.implicitWidth; height: 3; radius: 2; anchors.bottom: parent.bottom; anchors.bottomMargin: 0; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openTab(modelData[0]) }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData[1]
                    Accessible.selected: chosen
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 20; y: 14; spacing: 8
            Btn { icon: root.pinned ? "pin-off-20" : "pin-20"; text: root.pinned ? "Unpin app" : "Pin app"; onClicked: { root.pinned = !root.pinned; root.pinToggled(root.pinned) } }
            Btn { visible: root.tab === "discover" && root.page === ""; icon: "filter-20"; text: "Filters"; onClicked: root.filtersOpen = !root.filtersOpen }
            Btn { icon: "calendar-add-20"; text: "Create event"; outlined: true; onClicked: root.startCreate() }
        }
    }

    // ---- the tabs ----
    Flickable {
        id: tabPage
        visible: root.page === ""
        anchors { top: header.bottom; left: parent.left; right: filters.visible ? filters.left : parent.right; bottom: parent.bottom }
        contentHeight: tabCol.y + tabCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real inner: width - 32 - 46
        readonly property var lists: root.tab === "discover"
            ? (root.discoverData ? (root.discoverData.filtered !== undefined ? [["Results", root.discoverData.filtered]] : [["Happening now", root.discoverData.now || []], ["Upcoming", root.discoverData.upcoming || []], ["Past", root.discoverData.past || []]]) : [])
            : (root.manageData ? [["Drafts", root.manageData.drafts], ["Published", root.manageData.published], ["Past", root.manageData.past]] : [])
        readonly property bool empty: root.tab === "discover"
            ? lists.every(l => l[1].length === 0)
            : !!root.manageData && (root.manageData.drafts.total + root.manageData.published.total + root.manageData.past.total) === 0
        Column {
            id: tabCol
            x: 32; y: root.tab === "discover" ? 168 : 32
            width: tabPage.inner
            spacing: 0
            // Manage: Connect apps on the right.
            Item {
                visible: root.tab === "manage"
                width: parent.width; height: 64
            }
            Text { visible: !!root.loadError; text: "Couldn't load events. " + root.loadError; font.family: theme.font; font.pixelSize: 14; color: theme.danger; width: parent.width; wrapMode: Text.Wrap }
            // The empty state.
            Column {
                visible: tabPage.empty && (root.tab === "manage" ? !!root.manageData : !!root.discoverData)
                width: parent.width
                Item { width: 1; height: root.tab === "discover" ? 24 : 0 }
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; source: root.cdn + "v2/calendar-add-l-standard.svg"; sourceSize: Qt.size(256, 256); asynchronous: true }
                Item { width: 1; height: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.tab === "discover" && (root.myEvents || root.dateRange) ? "No events match your filters." : "No events have been scheduled yet"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: 450; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: "Customize everything from registration to how you want attendees to interact. We’ll walk you through each step."
                       font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 16 }
                Btn { anchors.horizontalCenter: parent.horizontalCenter; width: 155; height: 38; primary: true; text: "Create event"; onClicked: root.startCreate() }
                Item { width: 1; height: 32 }
            }
            // The lists.
            Repeater {
                model: tabPage.empty ? [] : tabPage.lists
                Column {
                    required property var modelData
                    readonly property var items: Array.isArray(modelData[1]) ? modelData[1] : ((modelData[1] && modelData[1].items) || [])
                    readonly property int total: Array.isArray(modelData[1]) ? items.length : ((modelData[1] && modelData[1].total) || 0)
                    width: tabCol.width
                    Item { width: 1; height: 26 }
                    Text { text: modelData[0] === "Drafts" && total ? "Drafts (" + total + ")" : modelData[0]; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 32; verticalAlignment: Text.AlignVCenter }
                    Item { width: 1; height: 16 }
                    Row {
                        visible: items.length === 0
                        spacing: 12; leftPadding: 0; height: 47
                        FluentIcon { name: "calendar-clock-20"; size: 20; color: theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0] + " events will show up here."; font.family: theme.font; font.pixelSize: 16; color: theme.textSecondary }
                    }
                    Flow {
                        visible: items.length > 0
                        width: parent.width; spacing: 16; leftPadding: 2; topPadding: 0
                        Repeater { model: items; EventCard {} }
                    }
                    Item { width: 1; height: items.length ? 30 : 0 }
                }
            }
            // Get started with a template.
            Column {
                visible: tabPage.empty
                width: parent.width
                Text { x: 8; text: "Get started with a template"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
                Item { width: 1; height: 8 }
                Flow {
                    x: 8; width: parent.width - 16; spacing: 16
                    Repeater {
                        model: root.templates.slice(1)
                        TemplateCard { width: (tabCol.width - 32) / 2; height: 317; onPicked: root.startForm(modelData) }
                    }
                }
            }
        }
        // Manage's Connect apps (Teams' integrations dialog isn't built).
        // Discover's intro card stays at the top while the page scrolls.
        Rectangle {
            id: intro
            visible: root.tab === "discover"
            x: 32; width: tabPage.inner; height: 136
            y: Math.max(32, tabPage.contentY)
            z: 2; radius: 16
            color: theme.pick("#F5F5F5", "#292929", "#000000")
            border.color: theme.stroke; border.width: 1
            Text { x: 17; y: 13; text: "Introducing an app for all things events!"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 17; y: 39; width: parent.width - 34; wrapMode: Text.Wrap; maximumLineCount: 2
                   text: "Discover what's happening in your org and plan your own professional events, all in one place. You can still access your meetings and audio recaps."
                   font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Btn { x: 17; y: 99; height: 24; fontSize: 12; pad: 8; outlined: true; text: "View meetings"; onClicked: root.viewMeetings() }
        }
    }

    // ---- Filters (Discover) ----
    Rectangle {
        id: filters
        visible: root.filtersOpen && root.page === "" && root.tab === "discover"
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 352
        color: theme.surface
        Rectangle { width: 1; height: parent.height; color: theme.divider }
        property bool mine: root.myEvents
        property string range: root.dateRange
        onVisibleChanged: if (visible) { mine = root.myEvents; range = root.dateRange }
        Text { x: 25; y: 22; text: "Filters"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Btn { x: parent.width - 56; y: 20; icon: "dismiss-20"; text: ""; pad: 6; onClicked: root.filtersOpen = false; Accessible.name: "Close filters" }
        Rectangle { x: 1; y: 72; width: parent.width - 1; height: 1; color: theme.divider }
        Text { x: 25; y: 93; text: "My events"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 25; y: 119; text: "Events you're invited to or registered for"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        SettingsParts.Toggle { x: parent.width - 72; y: 101; stateLabel: false; on: filters.mine; accessibleName: "My events"; onToggled: v => filters.mine = v }
        Rectangle { x: 1; y: 155; width: parent.width - 1; height: 1; color: theme.divider }
        Text { x: 25; y: 176; text: "Date range"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Grid {
            x: 25; y: 204; columns: 2; columnSpacing: 0; rowSpacing: 0
            Repeater {
                model: [["today", "Today"], ["thisWeek", "This week"], ["thisMonth", "This month"]]
                Item {
                    required property var modelData
                    width: 141; height: 36
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
                                border.color: filters.range === modelData[0] ? theme.brand : theme.textSecondary
                                Rectangle { visible: filters.range === modelData[0]; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand } }
                    Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    TapHandler { onTapped: filters.range = modelData[0] }
                    Accessible.role: Accessible.RadioButton; Accessible.name: modelData[1]; Accessible.checked: filters.range === modelData[0]
                }
            }
        }
        Rectangle { x: 1; y: parent.height - 57; width: parent.width - 1; height: 1; color: theme.divider }
        Text {
            x: 17; y: parent.height - 38; text: "Clear all"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
            TapHandler { onTapped: { filters.mine = false; filters.range = "" } }
        }
        Btn { x: parent.width - 216; y: parent.height - 44; width: 96; outlined: true; text: "Cancel"; onClicked: root.filtersOpen = false }
        Btn { x: parent.width - 112; y: parent.height - 44; width: 96; primary: true; text: "Apply"
              onClicked: { root.myEvents = filters.mine; root.dateRange = filters.range; root.filtersOpen = false; root.discoverData = null; root.reload() } }
    }

    // ---- Create: choose what you're organizing ----
    Flickable {
        id: createPage
        visible: root.page === "create"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: createGrid.y + createGrid.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Btn { x: 24; y: 32; icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.page = ""; Accessible.name: "Go back" }
        Text { x: 71; y: 34; text: "Create"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 24; y: 90; text: "Choose what you're organizing"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Flow {
            id: createGrid
            x: 24; y: 134; width: createPage.width - 24 - 38; spacing: 20
            Repeater {
                model: root.templates
                TemplateCard { width: (createGrid.width - 40) / 3; height: 292.4; imageHeight: 106.4; onPicked: root.startForm(modelData) }
            }
        }
    }

    // ---- New event ----
    Flickable {
        id: form
        visible: root.page === "form"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: formCol.y + formCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        property var template: root.templates[0]
        property date start: new Date()
        property date end: new Date()
        property string access: "Organization"
        property bool registration: false
        property bool greenRoom: false
        property bool mic: true
        property bool camera: true
        property bool react: true
        property bool chat: true
        property bool qna: true
        property int capacity: 0
        property bool large: false
        property var open: [true, false, false, false]
        property bool saving: false
        // A town hall streams to a large audience by default (3,000
        // view-only attendees, green room on); its tiles are Mic and Camera
        // (off, "Selected capacity does not support this engagement
        // feature.") and Q&A, then "Manage what attendees see".
        readonly property bool townHall: template.type === "Townhall"
        property string attendeeView: "Off"
        function reset(t, s, e) {
            const th = t.type === "Townhall"
            template = t; start = s; end = e; access = "Organization"; registration = false; greenRoom = th
            mic = !th; camera = !th; react = true; chat = true; qna = true; capacity = th ? 3000 : 0; large = th; attendeeView = "Off"
            open = [true, false, false, false]; nameField.text = "New event"; description.text = ""; contentY = 0
        }
        function toggle(i) { const o = open.slice(); o[i] = !o[i]; open = o }
        function setTime(d, hm) { const x = new Date(d); x.setHours(hm[0], hm[1], 0, 0); return x }
        function payload() {
            return { eventType: template.type, title: nameField.text.trim(), description: description.text ? "<p>" + description.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>") + "</p>" : "",
                     start: start.toISOString(), end: end.toISOString(), access: access, registration: registration, greenRoom: greenRoom,
                     allowMic: mic, allowCamera: camera, reactions: react, chat: chat, qna: qna,
                     capacity: townHall ? capacity : large ? 10000 : capacity, baseExperience: !townHall && large,
                     largeAudience: townHall && large, attendeeView: attendeeView }
        }
        readonly property var times: {
            const out = []
            for (let m = 0; m < 24 * 60; m += 30) out.push([Math.floor(m / 60), m % 60])
            return out
        }
        function timeLabel(hm) { const d = new Date(2000, 0, 1, hm[0], hm[1]); return theme.time(d) }
        Btn { x: 24; y: 32; icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.page = "create"; Accessible.name: "Go back" }
        Text { x: 64; y: 34; text: form.townHall && form.template.key === "townhall" ? "New town hall" : "New event"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Btn { anchors.right: parent.right; anchors.rightMargin: 22; y: 32; primary: true; icon: "save-20"; text: "Save and continue"; usable: nameField.text.trim().length > 0 && !form.saving; onClicked: saveDialog.open() }
        Column {
            id: formCol
            x: 20; y: 88; width: form.width - 44
            spacing: 16
            // The welcome card.
            Rectangle {
                visible: root.welcome
                x: 2; width: parent.width; height: 162; radius: 16
                color: theme.pick("#F5F5F5", "#292929", "#000000"); border.color: theme.divider; border.width: 1
                Text { x: 25; y: 30; text: "Welcome! Let's walk through creating your first event."; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Btn { x: parent.width - 57; y: 25; icon: "dismiss-20"; text: ""; pad: 6; onClicked: root.welcome = false; Accessible.name: "Dismiss welcome banner" }
                Row {
                    x: 25; y: 73; spacing: 16
                    Repeater {
                        model: [["webp/128/editor-l-standard-128x128.webp", "1. Fill out details", "Add the who, where, when and decide on the kind of experience you want."],
                                ["webp/128/expressions-l-standard-128x128.webp", "2. Personalize event page", "Add branding and get a preview of exactly what attendees will see."],
                                ["webp/128/share-l-standard-128x128.webp", "3. Spread the word", "Help people discover your event by sharing to the Events app and more."]]
                        Item {
                            required property var modelData
                            width: (formCol.width - 50 - 32) / 3; height: 64
                            Image { width: 64; height: 64; source: root.cdn + modelData[0]; sourceSize: Qt.size(128, 128); asynchronous: true }
                            Text { x: 80; width: parent.width - 80; text: modelData[1]; font.family: theme.font; font.pixelSize: 16; color: theme.text }
                            Text { x: 80; y: 30; width: parent.width - 80; text: modelData[2]; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                        }
                    }
                }
            }
            // 1. Add event details.
            Section {
                index: 0; title: "Add event details"
                Column {
                    width: parent.width; spacing: 0
                    Item { width: 1; height: 22 }
                    Row { spacing: 2
                        Label { text: "Name" }
                        Text { text: "*"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.redForeground3 } }
                    Item { width: 1; height: 12 }
                    Rectangle {
                        width: parent.width; height: 40; radius: 4; color: theme.input; border.color: nameField.activeFocus ? theme.brand : theme.stroke; border.width: 1
                        TextInput { id: nameField; x: 19; width: parent.width - 38; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 16; color: theme.text; clip: true; selectByMouse: true; Accessible.name: "Name" }
                    }
                    Item { width: 1; height: 24 }
                    Row {
                        spacing: 16
                        readonly property real w: (parent.width - 48 - 48) / 4
                        Column { spacing: 12
                            Label { text: "Start date" }
                            DatePickerField { width: parent.parent.w; height: 32; format: theme.regional.shortDate; date: form.start; onPicked: d => { const len = form.end - form.start; const s = new Date(d); s.setHours(form.start.getHours(), form.start.getMinutes()); form.start = s; form.end = new Date(s.getTime() + len) } } }
                        Column { spacing: 12
                            Label { text: "Start time" }
                            Dropdown { width: parent.parent.w; height: 32; label: theme.time(form.start); accessibleName: "Start time"
                                       options: form.times.map(t => [t[0] + ":" + t[1], form.timeLabel(t)])
                                       onPicked: c => { const len = form.end - form.start; form.start = form.setTime(form.start, c.split(":").map(Number)); form.end = new Date(form.start.getTime() + len) } } }
                        Column { spacing: 12
                            Label { text: "End date" }
                            DatePickerField { width: parent.parent.w; height: 32; format: theme.regional.shortDate; date: form.end; minDate: form.start; onPicked: d => { const e = new Date(d); e.setHours(form.end.getHours(), form.end.getMinutes()); form.end = e } } }
                        Column { spacing: 12
                            Label { text: "End time" }
                            Dropdown { width: parent.parent.w; height: 32; label: theme.time(form.end); accessibleName: "End time"
                                       options: form.times.map(t => [t[0] + ":" + t[1], form.timeLabel(t)])
                                       onPicked: c => form.end = form.setTime(form.end, c.split(":").map(Number)) } }
                    }
                    Item { width: 1; height: 22 }
                    Label { text: "Location" }
                    Item { width: 1; height: 8 }
                    Rectangle {
                        width: parent.width; height: 34; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                        Rectangle {
                            x: 13; anchors.verticalCenter: parent.verticalCenter; height: 20; radius: 10; width: chipRow.implicitWidth + 12
                            color: theme.brandTint
                            Row { id: chipRow; x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                Rectangle { width: 20; height: 20; radius: 10; color: theme.brandFill
                                    FluentIcon { anchors.centerIn: parent; name: "video-16"; size: 12; color: theme.textOnBrand } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Teams Online Meeting"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1 } }
                        }
                    }
                    Item { width: 1; height: 18 }
                    Label { text: "Description" }
                    Item { width: 1; height: 12 }
                    Rectangle {
                        width: parent.width; height: 137; radius: 6; color: theme.input; border.color: theme.divider; border.width: 1
                        TextEdit {
                            id: description
                            x: 13; y: 13; width: parent.width - 26; height: parent.height - 26
                            wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true; clip: true
                            Text { visible: !description.text && !description.activeFocus; text: "Add a description to share with attendees"; font: description.font; color: theme.textSecondary }
                            Accessible.name: "Description"
                        }
                    }
                }
            }
            // 2. Who's planning the event?
            Section {
                index: 1; title: "Who's planning the event?"
                Column {
                    width: parent.width
                    Item { width: 1; height: 16 }
                    Label { text: "Send invites as" }
                    Item { width: 1; height: 12 }
                    Rectangle { width: parent.width; height: 32; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: backend.userName + " on behalf of " + (nameField.text.trim() || "New event"); font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                    Text { text: "Invites sent from Event mailbox. Co-organizers have full access to manage the event."; font.family: theme.font; font.pixelSize: 12; color: theme.text; height: 16 }
                    Item { width: 1; height: 16 }
                    Label { text: "Organizers" }
                    Item { width: 1; height: 10 }
                    Rectangle {
                        height: 32; radius: 16; width: orgRow.implicitWidth + 10; color: theme.pick("#F5F5F5", "#292929", "#000000")
                        Row { id: orgRow; x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Avatar { size: 28; name: backend.userName; photoId: backend.userMri }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: backend.userName; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong } }
                    }
                    Item { width: 1; height: 16 }
                }
            }
            // 3. Who can attend?
            Section {
                index: 2; title: "Who can attend?"
                summary: (form.access === "Public" ? "Public" : form.access === "Private" ? "Specific people and groups" : "Your organization") + "     Registration " + (form.registration ? "On" : "Off")
                Column {
                    width: parent.width
                    Item { width: 1; height: 26 }
                    Row {
                        spacing: 16
                        Repeater {
                            model: [["Public", "Public", "Anyone can view the event page, register, or join the event.", "globe-20"],
                                    ["Organization", "Your organization", "Anyone in your org can view the event page, register, or join the event.", "building-20"],
                                    ["Private", "Specific people and groups", "Only people and groups you choose from your org can view the event page and join the event.", "people-20"]]
                            Item {
                                id: opt
                                required property var modelData
                                readonly property bool chosen: form.access === modelData[0]
                                width: (formCol.width - 50 - 32) / 3; height: 114
                                FluentSurface { anchors.fill: parent; depth: 2; radius: 12; color: theme.surface; borderColor: opt.chosen ? theme.brand : theme.stroke }
                                Rectangle { x: 17; y: 17; width: 36; height: 36; radius: 18; color: opt.chosen ? theme.brandTint : theme.pick("#F5F5F5", "#292929", "#000000")
                                    FluentIcon { anchors.centerIn: parent; name: opt.modelData[3]; size: 17; color: opt.chosen ? theme.brand : theme.textStrong } }
                                Text { x: 65; y: 17; width: parent.width - 102; text: opt.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                Text { x: 65; y: 39; width: parent.width - 102; text: opt.modelData[2]; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                                Rectangle { x: parent.width - 37; y: 18; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1; border.color: opt.chosen ? theme.brand : theme.textSecondary
                                    Rectangle { visible: opt.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand } }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: form.access = opt.modelData[0] }
                                Accessible.role: Accessible.RadioButton; Accessible.name: opt.modelData[1]; Accessible.checked: opt.chosen
                            }
                        }
                    }
                    Item { width: 1; height: 28 }
                    Item {
                        width: parent.width; height: 40
                        Text { text: "Turn on registration?"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 24; width: parent.width - 80; elide: Text.ElideRight; text: "Attendees will need to register before they can view all event details."; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                        SettingsParts.Toggle { anchors.right: parent.right; anchors.rightMargin: 8; y: 8; stateLabel: false; on: form.registration; accessibleName: "Turn on registration?"; onToggled: v => form.registration = v }
                    }
                    Item { width: 1; height: 12 }
                }
            }
            // 4. Set up experience and options.
            Section {
                index: 3; title: "Set up experience and options"
                summary: form.townHall ? (form.large ? "Optimize for large audience · " : "") + Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) + " attendees"
                    : (form.large ? "10,000" : form.capacity ? Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) : "1,000") + " attendees"
                Column {
                    width: parent.width
                    Item { width: 1; height: 16 }
                    Label { text: "Set your max event capacity" }
                    Text { y: 4; text: "We'll use this info to suggest the best settings for your audience"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong; height: 18 }
                    Item { width: 1; height: 12 }
                    Row {
                        spacing: 24; height: 36
                        Dropdown {
                            width: 250; height: 32; anchors.verticalCenter: parent.verticalCenter; accessibleName: "Set your max event capacity"
                            label: form.townHall ? (options.find(o => o[0] === String(form.capacity)) || options[1])[1]
                                : (form.large ? "10,000" : form.capacity ? Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) : "1,000") + " attendees"
                            // A town hall offers 1,000, 3,000 and the view-only 10,000
                            // (measured 2026-11-17).
                            options: form.townHall ? [["1000", "1,000 attendees"], ["3000", "3,000 attendees"], ["10000", "10,000 attendees (View only, with Q&A)"]]
                                : [["0", "1,000 attendees"]].concat(((root.features || {}).eventCapacity || { eventCapacityOptions: [] }).eventCapacityOptions
                                .filter(o => o.isAvailableForUserLicense && !o.isBaseEventExperience).map(o => [String(o.capacity), Number(o.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) + " attendees"]))
                            onPicked: c => { form.capacity = Number(c); if (!form.townHall) form.large = false }
                        }
                        Row {
                            spacing: 8; anchors.verticalCenter: parent.verticalCenter
                            SettingsParts.Toggle { stateLabel: false; on: form.large; accessibleName: "Optimize for large audience"
                                onToggled: v => { form.large = v; if (form.townHall) { form.capacity = v ? 3000 : 1000; form.mic = !v; form.camera = !v } } }
                            Text { text: "Optimize for large audience"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                    }
                    Item { width: 1; height: 16 }
                    Label { text: "Attendee participation" }
                    Item { width: 1; height: 16 }
                    Grid {
                        columns: 3; spacing: 8
                        Repeater {
                            // A streaming town hall: Mic and Camera unavailable, then Q&A;
                            // an interactive one: Mic, Camera, React, "During event" (chat), Q&A.
                            model: form.townHall && form.large
                                ? [["mic", "Mic", "mic-20", "mic-off-20", true], ["camera", "Camera", "video-20", "video-off-20", true], ["qna", "Q&A", "chat-bubbles-question-20", "chat-bubbles-question-20"]]
                                : [["mic", "Mic", "mic-20", "mic-off-20"], ["camera", "Camera", "video-20", "video-off-20"], ["react", "React", "emoji-20", "emoji-20"],
                                   ["chat", form.townHall ? "During event" : "Chat", "chat-20", "chat-bubbles-off-20"], ["qna", "Q&A", "chat-bubbles-question-20", "chat-bubbles-question-20"]]
                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool on: form[modelData[0]]
                                // Unavailable at this capacity (Teams' tooltip: "Selected capacity
                                // does not support this engagement feature.").
                                readonly property bool unavailable: !!modelData[4]
                                opacity: unavailable ? 0.3 : 1
                                ToolTip.visible: unavailable && tileHover.hovered; ToolTip.text: "Selected capacity does not support this engagement feature."
                                width: 132; height: 75; radius: 12; color: theme.surface; border.color: theme.divider; border.width: 1
                                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 16; name: tile.on ? tile.modelData[2] : tile.modelData[3]; size: 20; color: tile.on ? theme.brand : theme.textSecondary }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 41.5; text: tile.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: tile.on ? theme.text : theme.textSecondary }
                                HoverHandler { id: tileHover; cursorShape: tile.unavailable ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                TapHandler { enabled: !tile.unavailable; onTapped: form[tile.modelData[0]] = !tile.on }
                                Accessible.role: Accessible.CheckBox; Accessible.name: tile.modelData[1]; Accessible.checked: tile.on
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                    // A town hall's "Manage what attendees see" (Off, On, On with
                    // preview): who and what attendees see is brought on screen.
                    Item {
                        visible: form.townHall; width: 412; height: visible ? 80 : 0
                        Text { text: "Manage what attendees see"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 26; text: "Control the layout, content, and people seen on screen."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Dropdown {
                            x: 1; y: 49; width: 410; height: 30; accessibleName: "Manage what attendees see"
                            options: [["Off", "Off"], ["On", "On"], ["Preview", "On with preview"]]
                            label: (options.find(o => o[0] === form.attendeeView) || options[0])[1]
                            onPicked: v => form.attendeeView = v
                        }
                    }
                    Item { visible: form.townHall; width: 1; height: visible ? 16 : 0 }
                    Item {
                        width: 412; height: 68
                        Text { text: "Enable green room"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 28; width: 334; wrapMode: Text.Wrap; text: "Check audio, video, and screen setup before event starts."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        SettingsParts.Toggle { x: 352; y: 8; stateLabel: false; on: form.greenRoom; accessibleName: "Enable green room"; onToggled: v => form.greenRoom = v }
                    }
                    Item { width: 1; height: 16 }
                }
            }
        }
    }
    component Label: Text { font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; height: 20 }
    // One of the form's cards: its header toggles it.
    component Section: Item {
        id: sec
        property int index
        property string title
        property string summary: ""
        default property alias content: body.data
        width: formCol.width; height: form.open[index] ? body.y + body.childrenRect.height + 25 : 82
        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
        Text { x: 25; y: 27; text: sec.title; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Text { visible: !!sec.summary; anchors.right: parent.right; anchors.rightMargin: 57; y: 33; text: sec.summary; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        FluentIcon { x: parent.width - 51; y: 31; name: form.open[sec.index] ? "chevron-up-20" : "chevron-down-20"; size: 20; color: theme.textStrong }
        Item {
            x: 25; y: 25; width: parent.width - 50; height: 32
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: form.toggle(sec.index) }
            Accessible.role: Accessible.Button; Accessible.name: sec.title
        }
        Item { id: body; visible: form.open[sec.index]; x: 25; y: 57; width: parent.width - 50; height: childrenRect.height }
    }

    // "Save as a draft and continue?" (save-event-dialog), 600 wide.
    Popup {
        id: saveDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 600
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property bool pin: true
        onOpened: pin = !root.pinned
        contentItem: Column {
            spacing: 0
            Text { text: "Save as a draft and continue?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 28 }
            Item { width: 1; height: 8 }
            Text { text: "Attendees can't view the event until after you publish it."; font.family: theme.font; font.pixelSize: 14; color: theme.text; height: 20 }
            Item { width: 1; height: 15 }
            Text { text: "These settings will be locked after saving"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                Repeater {
                    model: [["people-20", "Invites from:", "Event mailbox"], ["filter-20", "Optimize for large audience:", form.large ? "On" : "Off"]]
                    Rectangle {
                        required property var modelData
                        height: 32; radius: 16; width: pr.implicitWidth + 24; color: theme.surface; border.color: theme.divider; border.width: 1
                        Row { id: pr; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            FluentIcon { name: modelData[0]; size: 20; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    }
                }
            }
            Item { width: 1; height: 12 }
            Rectangle {
                visible: !root.pinned
                width: 550; height: 42; radius: 4; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000"); border.color: theme.divider; border.width: 1
                Rectangle { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 2; color: "#5B5FC7"
                    FluentIcon { anchors.centerIn: parent; name: "calendar-add-20"; size: 14; color: "white" } }
                Text { x: 37; anchors.verticalCenter: parent.verticalCenter; text: "Get back to events you're organizing faster"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Rectangle { width: 16; height: 16; radius: 2; anchors.verticalCenter: parent.verticalCenter
                        color: saveDialog.pin ? theme.brandFill : "transparent"; border.width: 1; border.color: saveDialog.pin ? theme.brandFill : theme.textSecondary
                        FluentIcon { visible: saveDialog.pin; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Pin the Events app"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    TapHandler { onTapped: saveDialog.pin = !saveDialog.pin }
                }
            }
            Item { width: 1; height: 8 }
            Row {
                anchors.right: parent.right; spacing: 13
                Btn { width: 96; outlined: true; text: "Cancel"; onClicked: saveDialog.close() }
                Btn { primary: true; text: "Save and continue"; usable: !form.saving
                      onClicked: {
                          form.saving = true
                          const pinIt = !root.pinned && saveDialog.pin
                          root.call("create", form.payload(), v => {
                              form.saving = false
                              saveDialog.close()
                              if (v.error) { root.toast({ text: "Couldn't save the event. " + v.error, intent: "error" }); return }
                              if (pinIt) { root.pinned = true; root.pinToggled(true) }
                              root.toast({ text: "Draft event created", intent: "success" })
                              root.manageData = null
                              if (v.card) root.openEvent(v.card); else root.openTab("manage")
                          })
                      } }
            }
        }
    }

    // ---- An event's page (overview) ----
    Flickable {
        id: eventPage
        visible: root.page === "event" && !!root.current
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: 600
        clip: true
        readonly property var ev: root.current || ({})
        readonly property bool draft: ev.state === "Draft"
        readonly property real w: Math.min(966, width - 64)
        readonly property real x0: (width - w) / 2
        Rectangle {
            visible: eventPage.draft
            x: eventPage.x0; y: 16; width: eventPage.w; height: 119; radius: 16
            color: theme.pick("#F5F5F5", "#292929", "#000000"); border.color: theme.divider; border.width: 1
            Image { x: 28; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48; source: root.cdn + "webp/128/editor-l-standard-128x128.webp"; sourceSize: Qt.size(96, 96) }
            Text { x: 85; y: 24; width: parent.width - 120; text: "This event is a draft. Publish when you’re ready to share with attendees."; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; elide: Text.ElideRight }
            Text { x: 85; y: 50; width: parent.width - 360; wrapMode: Text.Wrap; text: "Only organizers and presenters you’ve invited can view this event. Organizers have permission to make edits."; font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            // Publish event (172 x 40, 24 from the card's right).
            Btn { anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; height: 40; fontSize: 16
                  primary: true; icon: "rocket-20"; text: "Publish event"; onClicked: publishDialog.openFor(root.current) }
        }
        Item {
            id: evHead
            x: eventPage.x0; y: eventPage.draft ? 167 : 32; width: eventPage.w; height: 32
            Btn { icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.openTab(root.tab); Accessible.name: "Go back" }
            Text { x: 39; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 120; elide: Text.ElideRight; text: eventPage.ev.title || ""; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Btn {
                id: evMore; anchors.right: parent.right; icon: "more-horizontal-20"; text: ""; pad: 6
                Accessible.name: "More options"
                onClicked: { evMenu.parent = evMore; evMenu.x = evMore.width - evMenu.implicitWidth; evMenu.y = evMore.height + 4; evMenu.open() }
            }
        }
        Rectangle {
            x: eventPage.x0; y: evHead.y + 90; width: eventPage.w * 0.6; height: 197; radius: 16; clip: true
            color: eventPage.ev.primary_color || "#5B5FC7"
            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                    source: { backend.emoticonsVersion; return eventPage.ev.promo_image ? backend.cardImage(eventPage.ev.promo_image) : "" } }
        }
        Item {
            x: eventPage.x0; y: evHead.y + 303; width: eventPage.w * 0.6; height: 72
            FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
            Text { x: 21; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 42; elide: Text.ElideRight; text: eventPage.ev.title || ""; font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.text }
        }
        Item {
            x: eventPage.x0 + eventPage.w * 0.6 + 24; y: evHead.y + 90; width: eventPage.w * 0.4 - 24; height: 250
            FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
            Column {
                x: 21; y: 21; width: parent.width - 42; spacing: 18
                // A published event that hasn't started: "Upcoming" (brand on
                // #E8EBFA, 22 tall, pill).
                Rectangle { visible: eventPage.ev.state === "Published" && new Date(eventPage.ev.start) > new Date(); height: 22; radius: 11; width: upc.implicitWidth + 16
                    color: theme.pick("#E8EBFA", "#2F2F4A", "#000000"); border.color: theme.pick("#C5CBFA", "#444791", "#FFFFFF"); border.width: 1
                    Text { id: upc; anchors.centerIn: parent; text: "Upcoming"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brand } }
                Rectangle { visible: eventPage.ev.state === "Canceled"; height: 24; radius: 12; width: cxl.implicitWidth + 20; color: "transparent"; border.color: theme.danger
                    Text { id: cxl; anchors.centerIn: parent; text: "Canceled"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.danger } }
                Row { spacing: 8; FluentIcon { name: "calendar-clock-20"; size: 20; color: theme.brand }
                      Text { text: root.whenText(eventPage.ev.start, eventPage.ev.end, true); font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                Row { spacing: 8; FluentIcon { name: "location-20"; size: 20; color: theme.brand }
                      Text { text: eventPage.ev.location || "Online"; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                Row { spacing: 8; FluentIcon { name: "people-20"; size: 20; color: theme.brand }
                      Text { text: eventPage.ev.access === "Public" ? "Anyone can view and join." : eventPage.ev.inviteOnly ? "Only people and groups you choose can view and join." : "Anyone in your org can view and join."; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                // Join (the meeting's pre-join; disabled while a draft) with its
                // menu (Copy join link, Copy join details), then the event chat.
                Row {
                    width: parent.width; height: 32; spacing: 8
                    readonly property bool can: eventPage.ev.state !== "Canceled" && !eventPage.draft && !!eventPage.ev.join_url
                    Rectangle {
                        width: parent.width - 40; height: 32; radius: 4; color: parent.can ? (joinHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#333333", "#000000")
                        Row { anchors.centerIn: parent; anchors.horizontalCenterOffset: -12; spacing: 6
                            FluentIcon { name: "video-20"; size: 20; color: parent.parent.parent.can ? theme.textOnBrand : theme.disabled }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Join"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.parent.parent.can ? theme.textOnBrand : theme.disabled } }
                        Rectangle { x: parent.width - 25; y: 0; width: 1; height: 32; color: theme.pick("#FFFFFF", "#141414", "#000000"); opacity: 0.5 }
                        FluentIcon { x: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: parent.parent.can ? theme.textOnBrand : theme.disabled }
                        HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.parent.can; onTapped: (ev) => {
                            if (ev.position.x > parent.width - 25) { joinMenu.parent = parent; joinMenu.x = parent.width - joinMenu.implicitWidth; joinMenu.y = 36; joinMenu.open() }
                            else root.joinEvent(eventPage.ev.join_url, eventPage.ev.title, eventPage.ev.start, eventPage.ev.end) } }
                        Accessible.role: Accessible.Button; Accessible.name: "Join"
                    }
                    Btn { width: 32; outlined: true; icon: "chat-20"; text: ""; pad: 6; usable: parent.can; Accessible.name: "Chat with participants"
                          onClicked: { const m = decodeURIComponent(eventPage.ev.join_url).match(/19:meeting_[^/]+@thread\.v2/); if (m) root.openEventChat(m[0], eventPage.ev.title) } }
                }
            }
        }
        MenuPopup {
            id: joinMenu
            items: [{ key: "link", label: "Copy join link", icon: "copy-20" }, { key: "details", label: "Copy join details", icon: "text-align-justify-20" }]
            onPicked: i => { backend.copyText(i.key === "link" ? eventPage.ev.join_url : root.joinDetails(eventPage.ev)); root.toast({ text: "Copied", intent: "success" }) }
        }
        MenuPopup {
            id: evMenu
            items: eventPage.ev.state === "Canceled" ? [] : [{ key: "cancel", label: "Cancel", icon: "calendar-cancel-20" }]
            onPicked: i => cancelDialog.open()
        }
    }
    // "Ready to publish your event?" (800 wide, radius 8, padding 24;
    // measured 2026-11-17): the settings that lock on publishing as chips,
    // then Cancel and Publish event (rocket). Publishing is
    // `PATCH events/{id}` {state: Published}; the People & emails lists
    // are read first so OST can say who will be invited.
    Popup {
        id: publishDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 800
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var ev: ({})
        property var people: null
        property bool busy: false
        function openFor(e) { ev = e || {}; people = null; open(); root.call("people", { id: ev.id }, v => { if (!v.error) people = v }) }
        contentItem: Column {
            spacing: 0
            Text { text: "Ready to publish your event?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 28 }
            Item { width: 1; height: 13 }
            Text { width: 752; wrapMode: Text.Wrap; text: "Invites will be sent to attendees. You can add more attendees and share the event after it's published."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 15 }
            Text { text: "These settings can’t be changed after publishing"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                Repeater {
                    model: [["people-community-20", "Who can view and join:", publishDialog.ev.access === "Public" ? "Public" : publishDialog.ev.inviteOnly ? "Specific people" : "Your organization"],
                            ["clipboard-20", "Registration:", publishDialog.ev.registration ? "On" : "Off"]]
                    Rectangle {
                        required property var modelData
                        height: 32; radius: 16; width: pubr.implicitWidth + 24; color: theme.surface; border.color: theme.divider; border.width: 1
                        Row { id: pubr; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            FluentIcon { name: modelData[0]; size: 20; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    }
                }
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                Btn { width: 96; outlined: true; text: "Cancel"; onClicked: publishDialog.close() }
                Btn { primary: true; icon: "rocket-20"; text: "Publish event"; usable: !publishDialog.busy
                      onClicked: {
                          publishDialog.busy = true
                          root.call("publish", { id: publishDialog.ev.id }, v => {
                              publishDialog.busy = false; publishDialog.close()
                              if (v.error) { root.toast({ text: "Couldn't publish the event. " + v.error, intent: "error" }); return }
                              root.current = Object.assign({}, root.current, { state: v.state || "Published" })
                              root.manageData = null
                              publishedDialog.openWith(v)
                          })
                      } }
            }
        }
    }
    // "Success! Your event has been published" (measured in Teams desktop
    // 2026-11-18: 800 x 454, padding 24, radius 8): the title 20/600 and
    // "Help your attendees discover it:" centred; on the left a preview of
    // the event's card (369 x 309, radius 24) with "Here's what attendees
    // will see." under it; on the right "Show event in Events app"
    // (Teams' isDiscoverable: PATCH events/{id} with the eTag) and the
    // copy buttons (369 x 31.33, outlined): Copy join details, Copy event
    // page link and, for a town hall, Copy embed code (Teams' town hall
    // player in an iframe).
    Popup {
        id: publishedDialog
        parent: Overlay.overlay
        modal: true; padding: 0
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 800; height: 454.4
        property bool discoverable: false
        property bool toggling: false
        property string embedCode: ""
        readonly property var ev: root.current || ({})
        function openWith(v) { discoverable = !!v.isDiscoverable; embedCode = v.embedCode || ""; open() }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Item {
            Text { x: 24; y: 24.7; width: 752; horizontalAlignment: Text.AlignHCenter; text: "Success! Your event has been published"
                   font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 24; y: 52.7; width: 752; horizontalAlignment: Text.AlignHCenter; text: "Help your attendees discover it:"
                   font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Btn { x: 743.3; y: 24.7; width: 32; height: 31.3; icon: "dismiss-20"; text: ""; pad: 6; onClicked: publishedDialog.close(); Accessible.name: "Close" }
            // The attendees' view of the card.
            Item {
                x: 25; y: 93; width: 369; height: 309
                FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
                Rectangle {
                    x: 12; y: 12; width: 345; height: 115; radius: 16; clip: true
                    color: publishedDialog.ev.primary_color || "#5B5FC7"
                    Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                            source: { theme.dark; backend.emoticonsVersion; return publishedDialog.ev.promo_image ? backend.cardImage(publishedDialog.ev.promo_image) : "" } }
                }
                Text { x: 19.7; y: 136.8; width: 329; elide: Text.ElideRight; text: publishedDialog.ev.title || ""
                       font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Text { x: 19.7; y: 162.8; text: root.whenText(publishedDialog.ev.start, publishedDialog.ev.end, false); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Row { x: 19.7; y: 192.8; spacing: 4
                    FluentIcon { name: "person-16"; size: 16; color: theme.textSecondary }
                    Text { text: "By " + backend.userName; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                Row { x: 19.7; y: 212.8; spacing: 4
                    FluentIcon { name: "location-20"; size: 16; color: theme.textSecondary }
                    Text { text: publishedDialog.ev.location || "Online"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                Row { x: 19.7; y: 265.4; spacing: 8
                    Btn { height: 23.3; width: 64; primary: true; icon: "video-16"; text: "Join"; fontSize: 12; pad: 8; usable: false }
                    Btn { height: 23.3; width: 24; outlined: true; icon: "link-16"; text: ""; pad: 2; usable: false } }
            }
            Text { x: 24.7; y: 413.8; width: 369.3; horizontalAlignment: Text.AlignHCenter; text: "Here’s what attendees will see."
                   font.family: theme.font; font.pixelSize: 10; color: theme.text }
            // Show event in Events app.
            Rectangle { x: 406; y: 97; width: 28; height: 28; radius: 4; color: theme.brandFill
                FluentIcon { anchors.centerIn: parent; name: "people-community-20"; size: 20; color: "white" } }
            Text { x: 444; y: 92.7; text: "Show event in Events app"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 444; y: 108.7; text: "Attendees with access can view"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            SettingsParts.Toggle {
                x: 727; y: 101; stateLabel: false; on: publishedDialog.discoverable; accessibleName: "Show event in Events app"
                onToggled: v => {
                    if (publishedDialog.toggling) return
                    publishedDialog.toggling = true
                    publishedDialog.discoverable = v
                    root.call("discoverable", { id: publishedDialog.ev.id, on: v }, r => {
                        publishedDialog.toggling = false
                        if (r.error) { root.toast({ text: "Couldn't change it. " + r.error, intent: "error" }); publishedDialog.discoverable = !v; return }
                        publishedDialog.discoverable = !!r.isDiscoverable
                    })
                }
            }
            Column {
                x: 406; y: 289.8; spacing: 10
                Repeater {
                    model: publishedDialog.embedCode ? [["document-20", "Copy join details", "details"], ["link-20", "Copy event page link", "page"], ["code-20", "Copy embed code", "embed"]]
                                                     : [["document-20", "Copy join details", "details"], ["link-20", "Copy event page link", "page"]]
                    Btn { required property var modelData; width: 369.3; height: 31.3; outlined: true; icon: modelData[0]; text: modelData[1]
                          onClicked: {
                              const ev = publishedDialog.ev
                              backend.copyText(modelData[2] === "page" ? (ev.site_url || "") : modelData[2] === "embed" ? publishedDialog.embedCode : root.joinDetails(ev))
                              root.toast({ text: "Copied", intent: "success" })
                          } }
                }
            }
        }
    }
    function publishCurrentForTest() { if (current) call("publish", { id: current.id }, v => { console.warn("EVENTS publish", JSON.stringify(v)); if (!v.error) current = Object.assign({}, current, { state: v.state }) }) }
    // "Cancel event?" (one-events-cancel-event-dialog).
    Popup {
        id: cancelDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property bool busy: false
        contentItem: Column {
            spacing: 8
            Text { text: "Cancel event?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { width: 432; wrapMode: Text.Wrap; text: "Once canceled, you cannot uncancel. Attendees will be notified by email."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 12 }
            Btn { anchors.right: parent.right; primary: true; text: "Cancel event"; usable: !cancelDialog.busy
                  onClicked: {
                      cancelDialog.busy = true
                      root.call("cancel", { id: root.current.id }, v => {
                          cancelDialog.busy = false; cancelDialog.close()
                          if (v.error) { root.toast({ text: "Couldn't cancel the event. " + v.error, intent: "error" }); return }
                          root.current = Object.assign({}, root.current, { state: "Canceled" })
                          root.manageData = null
                      })
                  } }
        }
    }
    function cancelCurrentForTest() { if (current) call("cancel", { id: current.id }, v => { console.warn("EVENTS cancel", JSON.stringify(v)); current = Object.assign({}, current, { state: v.error ? current.state : "Canceled" }) }) }
    function openOptionsForTest() { form.open = [false, false, false, true]; form.contentY = 0 }
    function saveForTest(name) { nameField.text = name; saveDialog.open() }
    function confirmSaveForTest() { saveDialog.contentItem.children[saveDialog.contentItem.children.length - 1].children[1].clicked() }
}
