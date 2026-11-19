import QtQuick
import QtQuick.Controls.Basic

// Teams' Meeting Recaps app, where Events' View audio recaps goes
// (measured in Teams desktop 26304 on winpc 2026-11-18, 1280 x 680; the
// data from Teams' meeting artifacts service, api::recaps):
// - the header (white, 61 tall): the app's tile (28, #5B5FC7, radius 4),
//   "Meeting Recaps" 16 bold, the tabs Home and Audio recaps (14/20, the
//   chosen one semibold with the brand line), Pin to app bar (outlined,
//   140 x 30) on the right;
// - Home (#F5F5F5): "Good evening, {first name}" (32/40 semibold, 116 in,
//   59 under the header), the filter pills All / Mentions / Missed /
//   Followed (32 tall, radius 16; All chosen: brand tint), Search for
//   meetings (280 x 30) and the list / grid switch on the right; then a
//   white card (radius 8) of days ("Friday, November 6", 14 semibold with a
//   caret) with their meetings: a 104 x 60 date tile (#E8EBFA, the day and
//   weekday), the subject 14 semibold, "Friday, November 6 · 3:00 PM -
//   3:30 PM, OST Test 1" 12 #616161, the headphones and Recap (outlined,
//   24 tall) on the right; "Loading more meetings..." while it loads;
// - Audio recaps: your audio recaps, else "Get started on your first audio
//   recap" (18 semibold), "Catch up on meetings with AI-generated audio
//   recaps—they’ll appear here." (14, #424242) and Generate audio recap
//   (primary, 188 x 31).
Rectangle {
    id: root
    color: theme.pick("#F5F5F5", "#141414", "#000000")
    property string tab: "home"
    property var days: []
    property int next: 0
    property bool loading: false
    property var podcasts: null
    property string filter: "all"
    property string query: ""
    property bool grid: false
    signal openRecap(string threadId, string title)
    signal toast(var d)
    function openTab(t) { tab = t; if (t === "audio") loadPodcasts(); else if (days.length === 0) loadMore() }
    property int seq: 0
    property var pending: ({})
    function call(kind, payload, cb) {
        const id = "recaps" + (++seq)
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
    function loadMore() {
        if (loading || next >= 56) return
        loading = true
        call("recapMeetings", { from: next }, v => { loading = false; if (!v.error) { days = days.concat(v.days || []); next = v.next || next + 14 } })
    }
    function loadPodcasts() { call("podcasts", {}, v => { podcasts = v.error ? [] : (v.items || []) }) }
    function greeting() {
        const h = new Date().getHours()
        return (h < 12 ? "Good morning, " : h < 18 ? "Good afternoon, " : "Good evening, ") + String(backend.userName || "").split(" ")[0]
    }
    function line(m) {
        const a = new Date(m.start), b = new Date(m.end)
        return Qt.formatDate(a, "dddd, MMMM d") + " · " + theme.time(a) + " - " + theme.time(b) + (m.organizer ? ", " + m.organizer : "")
    }
    Component.onCompleted: openTab(tab)

    // ---- header ----
    Rectangle {
        id: header
        width: parent.width; height: 61; color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        Rectangle { x: 20; y: 16; width: 28; height: 28; radius: 4; color: "#5B5FC7"
            FluentIcon { anchors.centerIn: parent; name: "arrow-counterclockwise-20"; size: 18; color: "white" } }
        Text { x: 56; anchors.verticalCenter: parent.verticalCenter; text: "Meeting Recaps"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
        Row {
            x: 184; y: 8
            Repeater {
                model: [["home", "Home"], ["audio", "Audio recaps"]]
                Item {
                    required property var modelData
                    readonly property bool chosen: root.tab === modelData[0]
                    width: tl.implicitWidth + 24; height: 44
                    Text { id: tl; x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: parent.chosen ? Font.DemiBold : Font.Normal; color: parent.chosen ? theme.text : theme.textStrong }
                    Rectangle { visible: parent.chosen; x: 12; width: tl.implicitWidth; height: 3; radius: 2; anchors.bottom: parent.bottom; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openTab(parent.modelData[0]) }
                    Accessible.role: Accessible.PageTab; Accessible.name: modelData[1]; Accessible.selected: chosen
                }
            }
        }
    }

    // ---- Home ----
    Flickable {
        id: home
        visible: root.tab === "home"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: homeCard.y + homeCard.height + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onAtYEndChanged: if (atYEnd && visible) root.loadMore()
        Text { x: 48; y: 40; text: root.greeting(); font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold; color: theme.text }
        Row {
            x: 48; y: 108; spacing: 8
            Repeater {
                model: [["all", "All"], ["mentions", "Mentions"], ["missed", "Missed"], ["followed", "Followed"]]
                Rectangle {
                    required property var modelData
                    readonly property bool chosen: root.filter === modelData[0]
                    height: 32; radius: 16; width: pl.implicitWidth + 24
                    color: chosen ? theme.brandTint : theme.surface; border.color: chosen ? theme.pick("#C5CBFA", "#444791", "#FFFFFF") : theme.stroke; border.width: 1
                    Text { id: pl; anchors.centerIn: parent; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    TapHandler { onTapped: root.filter = parent.modelData[0] }
                    Accessible.role: Accessible.RadioButton; Accessible.name: modelData[1]; Accessible.checked: chosen
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 48; y: 109; spacing: 8
            Rectangle { width: 280; height: 30; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                TextInput { id: search; x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                    onTextChanged: root.query = text
                    Text { visible: !search.text; text: "Search for meetings"; font: search.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText; Accessible.name: "Search for meetings" } }
            Rectangle { width: 36; height: 32; radius: 4; color: !root.grid ? theme.brandTint : "transparent"; border.color: theme.stroke; border.width: 1
                FluentIcon { anchors.centerIn: parent; name: "text-bullet-list-20"; size: 20; color: !root.grid ? theme.brand : theme.textStrong }
                TapHandler { onTapped: root.grid = false }
                Accessible.role: Accessible.Button; Accessible.name: "List view" }
            Rectangle { width: 36; height: 32; radius: 4; color: root.grid ? theme.brandTint : "transparent"; border.color: theme.stroke; border.width: 1
                FluentIcon { anchors.centerIn: parent; name: "grid-20"; size: 20; color: root.grid ? theme.brand : theme.textStrong }
                TapHandler { onTapped: root.grid = true }
                Accessible.role: Accessible.Button; Accessible.name: "Grid view" }
        }
        Rectangle {
            id: homeCard
            x: 48; y: 157; width: parent.width - 96; height: Math.max(home.height - y - 12, homeCol.height + 24)
            radius: 8; color: theme.surface; border.color: theme.dividerSoft; border.width: 1
            Column {
                id: homeCol
                x: 16; y: 12; width: parent.width - 32
                Repeater {
                    model: root.days
                    Column {
                        id: dayCol
                        required property var modelData
                        property bool open: true
                        readonly property var items: modelData.meetings.filter(m => !root.query || m.subject.toLowerCase().indexOf(root.query.toLowerCase()) >= 0)
                        visible: items.length > 0
                        width: homeCol.width
                        Item {
                            width: parent.width; height: 48
                            Row { anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                FluentIcon { name: dayCol.open ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: Qt.formatDate(new Date(dayCol.modelData.day + "T12:00:00"), "dddd, MMMM d"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text } }
                            TapHandler { onTapped: dayCol.open = !dayCol.open }
                        }
                        Repeater {
                            model: dayCol.open ? dayCol.items : []
                            Item {
                                id: row
                                required property var modelData
                                width: dayCol.width; height: 80
                                Rectangle { x: 40; y: 10; width: 104; height: 60; radius: 6; color: theme.pick("#E8EBFA", "#2F2F4A", "#000000")
                                    Rectangle { x: 4; y: 4; width: 36; height: 38; radius: 4; color: theme.surface; border.color: theme.dividerSoft
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 3; text: new Date(row.modelData.start).getDate(); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 22; text: Qt.formatDate(new Date(row.modelData.start), "ddd").toUpperCase(); font.family: theme.font; font.pixelSize: 9; color: theme.brand } } }
                                Column { x: 156; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 156 - 120
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.subject; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                    Text { width: parent.width; elide: Text.ElideRight; text: root.line(row.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                                Row { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                                    FluentIcon { name: "headphones-20"; size: 20; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle { width: 50; height: 24; radius: 4; color: rh.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 1
                                        Text { anchors.centerIn: parent; text: "Recap"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                                        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.openRecap(row.modelData.threadId, row.modelData.subject) }
                                        Accessible.role: Accessible.Button; Accessible.name: "Recap" } }
                                Rectangle { anchors.bottom: parent.bottom; x: 24; width: parent.width - 48; height: 1; color: theme.dividerSoft }
                            }
                        }
                    }
                }
                Column {
                    visible: root.loading
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 24; spacing: 8
                    BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: root.loading; width: 32; height: 32 }
                    Text { text: "Loading more meetings..."; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                }
            }
        }
    }

    // ---- Audio recaps ----
    Item {
        visible: root.tab === "audio"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        Column {
            visible: !!root.podcasts && root.podcasts.length === 0
            anchors.centerIn: parent; anchors.verticalCenterOffset: -20
            spacing: 0
            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 100; height: 100; source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/v2/sparkle-l-standard.svg"; sourceSize: Qt.size(200, 200); asynchronous: true }
            Item { width: 1; height: 24 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Get started on your first audio recap"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: theme.text }
            Item { width: 1; height: 12 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; width: 400; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                   text: "Catch up on meetings with AI-generated audio recaps—they’ll appear here."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
            Item { width: 1; height: 24 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 188; height: 31; radius: 4; color: gh.hovered ? theme.brandHover : theme.brandFill
                Row { anchors.centerIn: parent; spacing: 6
                    FluentIcon { name: "add-20"; size: 16; color: theme.textOnBrand; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Generate audio recap"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand } }
                HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
                // Teams picks a meeting for it from Home's list.
                TapHandler { onTapped: root.openTab("home") }
                Accessible.role: Accessible.Button; Accessible.name: "Generate audio recap"
            }
        }
        ListView {
            visible: !!root.podcasts && root.podcasts.length > 0
            anchors.fill: parent; anchors.margins: 48
            model: root.podcasts || []
            spacing: 8
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 64; radius: 8; color: theme.surface; border.color: theme.dividerSoft
                FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "headphones-20"; size: 24; color: theme.brand }
                Text { x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 72; elide: Text.ElideRight
                       text: modelData.title || modelData.meetingTitle || modelData.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            }
        }
        BusyIndicator { anchors.centerIn: parent; running: root.podcasts === null; visible: running; width: 32; height: 32 }
    }
    function stateForTest() { return JSON.stringify({ tab: tab, days: days.length, meetings: days.reduce((n, d) => n + d.meetings.length, 0), podcasts: podcasts ? podcasts.length : null, loading: loading }) }
}
