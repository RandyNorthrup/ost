import QtQuick
import QtCore
import QtMultimedia
import QtQuick.Window
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
    property var progressHandlers: ({})
    function call(kind, payload, cb, onProgress) {
        const id = "recaps" + (++seq)
        const p = Object.assign({}, pending); p[id] = cb; pending = p
        if (onProgress) { const h = Object.assign({}, progressHandlers); h[id + ":progress"] = onProgress; progressHandlers = h }
        backend.eventsRequest(kind, id, JSON.stringify(payload || {}))
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            // An update of a request still going (Generate's recap as it's made).
            const progress = root.progressHandlers[id]
            if (progress) { let u = {}; try { u = JSON.parse(json) } catch (e) {} progress(u); return }
            if (root.progressHandlers[id + ":progress"]) { const h = Object.assign({}, root.progressHandlers); delete h[id + ":progress"]; root.progressHandlers = h }
            const cb = root.pending[id]
            if (!cb) return
            const p = Object.assign({}, root.pending); delete p[id]; root.pending = p
            let v = {}
            try { v = JSON.parse(json) } catch (e) { v = { error: "Bad reply" } }
            cb(v)
        }
    }
    // Teams' meeting recap list (useMeetingRecapList, meetingRecapList with
    // maxDays 30): today and the 30 days before it, read a few days at a
    // time; "Loaded all meetings in the last 30 days." once all are in.
    readonly property int maxDays: 30
    readonly property bool allLoaded: next > maxDays && !loading
    function loadMore() {
        if (loading || next > maxDays) return
        loading = true
        call("recapMeetings", { from: next, days: Math.min(14, maxDays + 1 - next) }, v => {
            loading = false
            if (v.error) return
            days = days.concat(v.days || []); next = v.next || next + 14
            // The Generate dialog lists the whole 30 days.
            if (genDialog.opened) loadMore()
        })
    }
    function loadPodcasts() { call("podcasts", {}, v => { podcasts = v.error ? [] : (v.items || []); autoPlayIfMade(); chapterProgress() }) }
    function greeting() {
        const h = new Date().getHours()
        return (h < 12 ? qsTr("Good morning, %1") : h < 18 ? qsTr("Good afternoon, %1") : qsTr("Good evening, %1")).arg(String(backend.userName || "").split(" ")[0])
    }
    function line(m) {
        const a = new Date(m.start), b = new Date(m.end)
        return theme.fmtDate(a, "dddd, MMMM d") + " · " + theme.time(a) + " - " + theme.time(b) + (m.organizer ? ", " + m.organizer : "")
    }
    Component.onCompleted: openTab(tab)

    // ---- header ----
    Rectangle {
        id: header
        width: parent.width; height: 61; color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        Rectangle { x: 20; y: 16; width: 28; height: 28; radius: 4; color: "#5B5FC7"
            FluentIcon { anchors.centerIn: parent; name: "arrow-counterclockwise-20"; size: 18; color: "white" } }
        Text { x: 56; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Meeting Recaps"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
        Row {
            x: 184; y: 8
            Repeater {
                model: [["home", qsTr("Home", "meetingRecap:k3msryzhw")], ["audio", qsTr("Audio recaps")]]
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
                model: [["all", qsTr("All")], ["mentions", qsTr("Mentions")], ["missed", qsTr("Missed")], ["followed", qsTr("Followed")]]
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
                    Text { visible: !search.text; text: qsTr("Search for meetings"); font: search.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Search for meetings") } }
            Rectangle { width: 36; height: 32; radius: 4; color: !root.grid ? theme.brandTint : "transparent"; border.color: theme.stroke; border.width: 1
                FluentIcon { anchors.centerIn: parent; name: "text-bullet-list-20"; size: 20; color: !root.grid ? theme.brand : theme.textStrong }
                TapHandler { onTapped: root.grid = false }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("List view") }
            Rectangle { width: 36; height: 32; radius: 4; color: root.grid ? theme.brandTint : "transparent"; border.color: theme.stroke; border.width: 1
                FluentIcon { anchors.centerIn: parent; name: "grid-20"; size: 20; color: root.grid ? theme.brand : theme.textStrong }
                TapHandler { onTapped: root.grid = true }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Grid view") }
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
                                Text { text: theme.fmtDate(new Date(dayCol.modelData.day + "T12:00:00"), "dddd, MMMM d"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text } }
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
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 22; text: theme.fmtDate(new Date(row.modelData.start), "ddd").toUpperCase(); font.family: theme.font; font.pixelSize: 9; color: theme.brand } } }
                                Column { x: 156; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 156 - 120
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.subject; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                    Text { width: parent.width; elide: Text.ElideRight; text: root.line(row.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                                Row { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                                    FluentIcon { name: "headphones-20"; size: 20; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle { width: 50; height: 24; radius: 4; color: rh.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 1
                                        Text { anchors.centerIn: parent; text: qsTr("Recap"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                                        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.openRecap(row.modelData.threadId, row.modelData.subject) }
                                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Recap") } }
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
                    Text { text: qsTr("Loading more meetings..."); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                }
                // Teams' end of the list (12/16 #616161, 16 in, 16 above).
                Text { visible: root.allLoaded; topPadding: 16; text: qsTr("Loaded all meetings in the last 30 days."); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
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
            // Teams' empty state (audio recap 26304): its no-podcast picture
            // (128), the title 18 bold 12 under it, the text 16 above and
            // below, Generate audio recap.
            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/podcast/no-podcast.png"; asynchronous: true }
            Item { width: 1; height: 12 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Get started on your first audio recap"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Item { width: 1; height: 16 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; width: 400; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                   text: qsTr("Catch up on meetings with AI-generated audio recaps—they’ll appear here."); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
            Item { width: 1; height: 24 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 188; height: 31; radius: 4; color: gh.hovered ? theme.brandHover : theme.brandFill
                Row { anchors.centerIn: parent; spacing: 6
                    FluentIcon { name: "add-20"; size: 16; color: theme.textOnBrand; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: qsTr("Generate audio recap"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand } }
                HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: genDialog.openNow() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Generate audio recap")
            }
        }
        // Your audio recaps (Teams 26304, measured on winpc 2026-11-22):
        // a 279 wide list pane (#F5F5F5) with Generate audio recap (primary,
        // 240 x 32, 20 from the top) over the recaps, 75 tall rows (the
        // title 14, "Couldn't generate" in red or "Generating...", the date
        // M/d at the right; the chosen row white), then "Includes audio
        // recaps generated in the last 60 days" (12); the chosen recap on
        // the right: its title (20/600), the day, "AI generated" with Like
        // and Dislike; Chapters / Transcript pills over its chapters; the
        // player bar at the bottom. A recap that couldn't be made shows
        // "We couldn't generate the audio recap" and why.
        Item {
            id: recapsPanes
            visible: !!root.podcasts && root.podcasts.length > 0
            anchors.fill: parent
            readonly property var chosen: (root.podcasts || []).find(p => p.id === root.chosenPodcast) || (root.podcasts || [])[0] || null
            readonly property string chosenState: chosen ? root.podcastState(chosen) : ""
            Rectangle {
                id: recapList
                width: 279; height: parent.height; color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
                Rectangle {
                    x: 20; y: 12; width: 240; height: 32; radius: 4; color: lgh.hovered ? theme.brandHover : theme.brandFill
                    Row { anchors.centerIn: parent; spacing: 6
                        FluentIcon { name: "add-20"; size: 16; color: theme.textOnBrand; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("Generate audio recap"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand } }
                    HoverHandler { id: lgh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: genDialog.openNow() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Generate audio recap")
                }
                Rectangle { x: 0; y: 55; width: parent.width - 1; height: 1; color: theme.dividerSoft }
                ListView {
                    x: 4; y: 60; width: parent.width - 9; height: parent.height - 60; clip: true; spacing: 2
                    model: root.podcasts || []
                    footer: Text { x: 16; topPadding: 12; width: 240; wrapMode: Text.Wrap; text: qsTr("Includes audio recaps generated in the last 60 days"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    delegate: Rectangle {
                        id: prow
                        required property var modelData
                        readonly property bool on: recapsPanes.chosen && recapsPanes.chosen.id === modelData.id
                        readonly property string st: root.podcastState(modelData)
                        width: ListView.view.width; height: 75; radius: 4
                        color: on ? theme.surface : prh.hovered ? theme.hover : "transparent"
                        Text { x: 16; y: on ? 25 : 14; width: parent.width - 80; elide: Text.ElideRight; text: prow.st === "generating" ? qsTr("Generating...") : (prow.modelData.title || qsTr("No title available"))
                               font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { visible: prow.st === "failed"; x: 16; y: 44; text: qsTr("Couldn't generate"); font.family: theme.font; font.pixelSize: 14; color: theme.danger }
                        // A made recap's length ("5m 38s"; what's left of it
                        // once the chosen one has been started).
                        Text { visible: prow.st === "done" && root.recapLength(prow.modelData) > 0; x: 16; y: prow.on ? 45 : 34; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                               text: prow.on && root.playPos > 0 && recapAudio.duration > 0 ? qsTr("%1 left").arg(root.fmtLength(root.recapLength(prow.modelData) - root.playPos)) : root.fmtLength(root.recapLength(prow.modelData)) }
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; y: on ? 26 : 14; text: Qt.formatDate(new Date(prow.modelData.createdDateTime || Date.now()), "M/d"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        HoverHandler { id: prh }
                        TapHandler { onTapped: { root.autoPlayId = ""; root.chosenPodcast = prow.modelData.id } }
                        Accessible.role: Accessible.ListItem; Accessible.name: prow.modelData.title || qsTr("No title available")
                    }
                }
            }
            Item {
                x: recapList.width + 32; y: 0; width: parent.width - x - 32; height: parent.height
                readonly property var p: recapsPanes.chosen
                visible: !!p
                // The recap's header (Teams 26304 podcast detail page,
                // measured on winpc 2026-11-22): the title (16/600), the
                // day (12, secondary), "AI generated" (12 on #F5F5F5, radius
                // 4) with Like and Dislike (32 x 25, 16 px glyphs), ··· at
                // the right (Learn more, Delete); a line, then Chapters /
                // Transcript (31.3 tall, radius 16; the chosen one #E8EBFA
                // with #4F52B2 600 text).
                Item {
                    visible: recapsPanes.chosenState !== "failed"
                    width: parent.width; height: 188
                    readonly property var p: parent.p
                    Text { y: 16; width: Math.max(0, (listenRow.visible ? listenRow.x : recapMore.x) - 12); elide: Text.ElideRight
                           text: recapsPanes.chosenState === "generating" ? qsTr("Generating...") : (parent.p ? parent.p.title || qsTr("No title available") : "")
                           font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                    // Listen on mobile (Teams' podcast QR button, measured on
                    // winpc 2026-11-22: a transparent button 31.3 tall, its
                    // 20 px phone glyph 5.67 in, the label 14/600 #424242
                    // only when the app is at least 1280 wide) and, for the
                    // first 14 days after it was first shown, Teams' "New"
                    // badge (36.7 x 20, round, brand, 12/600 white); for a
                    // recap being made or made.
                    Row {
                        id: listenRow
                        visible: root.canListenOnMobile(recapsPanes.chosen)
                        anchors.right: recapMore.left; y: 10; height: 31.3
                        Rectangle {
                            id: listenBtn
                            width: listenLabel.visible ? 5.67 + 20 + 6 + listenLabel.implicitWidth + 5.67 : 37.33; height: 31.3; radius: 4
                            color: lmh.hovered ? theme.hover : "transparent"
                            FluentIcon { x: 5.67; anchors.verticalCenter: parent.verticalCenter; name: "phone-20"; size: 20; color: lmh.hovered ? theme.brand : theme.textStrong }
                            Text { id: listenLabel; visible: root.width >= 1280; x: 31.67; anchors.verticalCenter: parent.verticalCenter
                                   text: qsTr("Listen on mobile", "podcast:k5w096s5l"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: lmh.hovered ? theme.brand : theme.textStrong }
                            HoverHandler { id: lmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.openListenOnMobile(recapsPanes.chosen) }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Listen on mobile", "podcast:k5w096s5l")
                        }
                        Rectangle {
                            visible: root.listenBadgeShown
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(20, newT.implicitWidth + 12.67); height: 20; radius: 10
                            color: theme.pick("#5B5FC7", "#7F85F5", "#1AEBFF")
                            Text { id: newT; anchors.centerIn: parent; text: qsTr("New", "calling:k5oxq4sbb"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#FFFFFF", "#000000", "#000000") }
                            Accessible.role: Accessible.StaticText; Accessible.name: qsTr("New", "calling:k5oxq4sbb")
                        }
                    }
                    Rectangle { id: recapMore; visible: recapsPanes.chosenState === "done"; anchors.right: parent.right; y: 10; width: 32; height: 31.3; radius: 4; color: rmh.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: rmh }
                        TapHandler { onTapped: { recapMenu.parent = recapMore; recapMenu.x = recapMore.width - recapMenu.implicitWidth; recapMenu.y = recapMore.height + 4; recapMenu.open() } }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Context menu button") }
                    Text { y: 44.7; text: parent.p ? new Date(parent.p.createdDateTime || Date.now()).toLocaleDateString(Qt.locale(), "dddd, MMMM d, yyyy") : ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Row { y: 75.3; spacing: 0
                        Rectangle { width: aiT.implicitWidth + 12; height: 25; radius: 4; color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                            Text { id: aiT; anchors.centerIn: parent; text: qsTr("AI generated"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                        Item { width: 15; height: 1 }
                        Repeater { model: [["thumb-like-20", qsTr("Like")], ["thumb-dislike-20", qsTr("Dislike")]]
                            Rectangle { required property var modelData; width: 32; height: 25; radius: 4; color: lkh.hovered ? theme.hover : "transparent"
                                FluentIcon { anchors.centerIn: parent; name: modelData[0]; size: 16; color: theme.text }
                                HoverHandler { id: lkh }
                                Accessible.role: Accessible.Button; Accessible.name: qsTr("AI-generated content may be incorrect.") + " " + modelData[1] } } }
                    Rectangle { x: -32; y: 110.5; width: parent.width + 64; height: 1; color: theme.pick("#F0F0F0", "#2E2E2E", "#FFFFFF") }
                    Row { y: 133; spacing: 8
                        Repeater { model: [["chapters", qsTr("Chapters")], ["transcript", qsTr("Transcript")]]
                            Rectangle { required property var modelData
                                readonly property bool on: root.detailTab === modelData[0]
                                height: 31.3; radius: 16; width: pT.implicitWidth + 25.3
                                color: on ? theme.pick("#E8EBFA", "#2B2B40", "#000000") : tbh.hovered ? theme.hover : "transparent"
                                Text { id: pT; anchors.centerIn: parent; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: parent.on ? Font.DemiBold : Font.Normal
                                       color: parent.on ? theme.pick("#4F52B2", "#7F85F5", "#FFFFFF") : theme.textStrong }
                                HoverHandler { id: tbh }
                                TapHandler { onTapped: root.openDetailTab(modelData[0]) }
                                Accessible.role: Accessible.PageTab; Accessible.name: modelData[1] } } }
                    Column { y: 188; spacing: 12
                        Repeater {
                            model: recapsPanes.chosenState === "generating" ? 5 : 0
                            Rectangle { required property int index; width: index % 2 ? 400 : 608; height: 35; radius: 4; color: theme.pick("#E6E6E6", "#333333", "#000000") } } }
                }
                // Chapters (Teams' chapter list): grouped by meeting; the first
                // and last chapters without a meeting stand alone (Intro,
                // Outro: 18/600 with their start at the right); a meeting's
                // group opens with its name (18/600), "date · start - end,
                // organizer" (12) and Recap, then its chapters (31.3 rows:
                // a 12 px brand play glyph, the title 14 (the one playing
                // 600 brand), its start "mm:ss" at the right).
                ListView {
                    id: chapterList
                    visible: recapsPanes.chosenState === "done" && root.detailTab === "chapters"
                    x: 0; y: 188.5; width: parent.width; height: parent.height - y - 146; clip: true; spacing: 0
                    model: root.chapterItems
                    delegate: Rectangle {
                        id: chRow
                        required property var modelData
                        readonly property bool head: modelData.kind !== "chapter"
                        readonly property bool current: modelData.idx >= 0 && root.currentChapter === modelData.idx
                        width: ListView.view.width
                        height: modelData.kind === "meeting" ? 53.3 : modelData.kind === "standalone" ? (modelData.last ? 29.3 : 53.3) : 31.3
                        color: "transparent"
                        Rectangle { y: chRow.modelData.kind === "meeting" ? 0 : 0; width: parent.width; height: chRow.modelData.kind === "meeting" ? 41.3 : 29.3; radius: 4
                                    color: chh2.hovered ? theme.pick("#FAFAFA", "#2E2E2E", "#000000") : "transparent"
                            FluentIcon { x: 8.7; y: chRow.modelData.kind === "meeting" ? 14.7 : 8.7; size: 12; color: theme.brand
                                         name: chRow.current && recapAudio.playbackState === MediaPlayer.PlayingState ? "pause-20-filled" : "play-20-filled" }
                            Column { x: 44.7; y: chRow.head ? 2.7 : 4.7; width: parent.width - 44.7 - (chRow.modelData.kind === "meeting" ? 90 : 60)
                                Text { width: parent.width; elide: Text.ElideRight; text: chRow.modelData.title || ""; font.family: theme.font
                                       font.pixelSize: chRow.head ? 18 : 14; font.weight: chRow.head || chRow.current ? Font.DemiBold : Font.Normal
                                       color: chRow.current && !chRow.head ? theme.brand : theme.text }
                                Text { visible: chRow.modelData.kind === "meeting"; width: parent.width; elide: Text.ElideRight; topPadding: 4; text: chRow.modelData.subtitle || ""
                                       font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                            Text { visible: chRow.modelData.kind !== "meeting"; anchors.right: parent.right; y: chRow.head ? 6.6 : 6.7; text: root.fmtClock(chRow.modelData.startMs)
                                   font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                            Rectangle { visible: chRow.modelData.kind === "meeting" && !!chRow.modelData.threadId; anchors.right: parent.right; y: 8.7; width: 74; height: 24; radius: 4
                                        color: rch.hovered ? theme.hover : theme.surface; border.color: theme.stroke; border.width: 1
                                Text { anchors.centerIn: parent; text: qsTr("Recap"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                                HoverHandler { id: rch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.openRecap(chRow.modelData.threadId, chRow.modelData.title) }
                                Accessible.role: Accessible.Button; Accessible.name: qsTr("Recap") }
                            HoverHandler { id: chh2; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.playChapter(chRow.modelData.idx >= 0 ? chRow.modelData.idx : chRow.modelData.first) }
                        }
                        Accessible.role: Accessible.Button; Accessible.name: modelData.title || ""
                    }
                }
                // Transcript (Teams' podcast transcript: the caption file's
                // cues, its voices named "Speaker 1", "Speaker 2" in order;
                // "Speaker n · mm:ss" (12, #707070) where the speaker changes,
                // 12 above it; each line 14/20).
                ListView {
                    visible: recapsPanes.chosenState === "done" && root.detailTab === "transcript"
                    x: 0; y: 200.5; width: parent.width; height: parent.height - y - 146; clip: true; spacing: 0
                    model: root.transcriptCues
                    header: Text { visible: root.transcriptState !== "ready"; height: visible ? implicitHeight : 0; width: 600; wrapMode: Text.Wrap; bottomPadding: 12
                                   text: root.transcriptState === "loading" ? qsTr("Loading...") : qsTr("The transcript isn't available."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    delegate: Column {
                        id: cue
                        required property var modelData
                        required property int index
                        readonly property bool current: root.playPos >= modelData.start && root.playPos < modelData.end
                        width: ListView.view.width
                        Item { visible: !!cue.modelData.speaker && cue.index > 0; width: 1; height: 12 }
                        Text { visible: !!cue.modelData.speaker; width: parent.width; text: cue.modelData.speaker + " · " + root.fmtClock(cue.modelData.start)
                               font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                        Item { visible: !!cue.modelData.speaker; width: 1; height: 2 }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: cue.modelData.text; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                               color: cue.current ? theme.brand : theme.text
                               TapHandler { onTapped: root.seekTo(cue.modelData.start) } }
                    }
                }
                Column {
                    visible: recapsPanes.chosenState === "failed"
                    anchors.centerIn: parent; spacing: 16
                    Image { anchors.horizontalCenter: parent.horizontalCenter; width: 160; height: 160; asynchronous: true; source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/webp/192/warning-l-standard-192x192.webp" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("We couldn't generate the audio recap"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; width: 420; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                           text: parent.parent.p && root.noInsightPodcast(parent.parent.p) ? qsTr("None of the selected meetings have enough information. Select different meetings and try again.") : qsTr("Something went wrong. Try again later.")
                           font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                }
                // The player bar.
                Rectangle {
                    visible: recapsPanes.chosenState !== "failed"
                    x: -32; width: parent.width + 64; height: 130; anchors.bottom: parent.bottom
                    color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                    id: playerBar
                    readonly property bool can: recapsPanes.chosenState === "done" && !!recapsPanes.chosen && (!!recapsPanes.chosen.fullAudioFile || root.chapterPlaying >= 0 || root.hasChapters(recapsPanes.chosen))
                    // The recap's own length (Teams counts the chapters, not the file).
                    readonly property real total: recapsPanes.chosen && root.recapLength(recapsPanes.chosen) > 0 ? root.recapLength(recapsPanes.chosen) : recapAudio.duration
                    Text { x: 32; y: 24; width: parent.width - 64; elide: Text.ElideRight
                           text: recapsPanes.chosenState === "generating" ? qsTr("Generating...") : root.currentChapter >= 0 && root.chapterRows[root.currentChapter] ? root.chapterRows[root.currentChapter].title : (recapsPanes.chosen ? recapsPanes.chosen.title || "" : "")
                           font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Rectangle { id: track; x: 32; y: 54; width: parent.width - 200; height: 4; radius: 2; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                        Rectangle { width: playerBar.total > 0 ? parent.width * Math.min(1, root.playPos / playerBar.total) : 0; height: parent.height; radius: 2; color: theme.brandFill }
                        TapHandler { enabled: playerBar.can && playerBar.total > 0; onTapped: ev => root.seekTo(playerBar.total * ev.position.x / track.width) } }
                    Text { anchors.right: parent.right; anchors.rightMargin: 32; y: 46; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                           text: playerBar.can && playerBar.total > 0 ? root.fmtClock(root.playPos) + " / " + root.fmtClock(playerBar.total) : "--:-- / --:--" }
                    Row { anchors.horizontalCenter: parent.horizontalCenter; y: 76; spacing: 28
                        Text { anchors.verticalCenter: parent.verticalCenter; text: recapAudio.playbackRate + "x"; font.family: theme.font; font.pixelSize: 12; color: playerBar.can ? theme.text : theme.disabledStrong
                               TapHandler { enabled: playerBar.can; onTapped: root.nextSpeed() }
                               Accessible.role: Accessible.Button; Accessible.name: qsTr("Playback speed") }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "skip-back-10-20"; size: 20; color: playerBar.can ? theme.textStrong : theme.disabledStrong
                                     TapHandler { enabled: playerBar.can; onTapped: root.seekTo(Math.max(0, root.playPos - 10000)) }
                                     Accessible.role: Accessible.Button; Accessible.name: qsTr("Skip back 10 seconds") }
                        Rectangle { width: 36; height: 36; radius: 18
                            color: playerBar.can ? theme.brandFill : theme.pick("#C7C7C7", "#5C5C5C", "#3FF23F")
                            FluentIcon { anchors.centerIn: parent; name: recapAudio.playbackState === MediaPlayer.PlayingState ? "pause-20" : "play-20"; size: 20; color: "#FFFFFF" }
                            TapHandler { enabled: playerBar.can; onTapped: root.playChosen() }
                            Accessible.role: Accessible.Button; Accessible.name: recapAudio.playbackState === MediaPlayer.PlayingState ? qsTr("Pause") : qsTr("Play") }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "skip-forward-10-20"; size: 20; color: playerBar.can ? theme.textStrong : theme.disabledStrong
                                     TapHandler { enabled: playerBar.can; onTapped: root.seekTo(root.playPos + 10000) }
                                     Accessible.role: Accessible.Button; Accessible.name: qsTr("Skip forward 10 seconds") } }
                }
            }
        }
        BusyIndicator { anchors.centerIn: parent; running: root.podcasts === null; visible: running; width: 32; height: 32 }
    }
    // The chosen recap's audio: a made recap's fullAudioFile, streamed; a
    // recap being made a chapter at a time (below).
    MediaPlayer { id: recapAudio; audioOutput: AudioOutput {} }
    onChosenPodcastChanged: { recapAudio.stop(); recapAudio.source = ""; chapterPlaying = -1; chapterWait = ""; transcriptCues = []; transcriptState = ""; if (detailTab === "transcript") loadTranscript() }
    function playChosen(then) {
        if (!then && recapAudio.playbackState === MediaPlayer.PlayingState) { recapAudio.pause(); return }
        const p = recapsPanes.chosen
        if (chapterPlaying >= 0 || (byChapter(p) && hasChapters(p))) {
            // Playing by chapter: go on, or start where it stands.
            if (!then && recapAudio.source.toString() && recapAudio.mediaStatus !== MediaPlayer.EndOfMedia) { recapAudio.play(); return }
            if (!then && chapterWait === "") { startChapter(Math.max(0, chapterPlaying), 0); return }
            if (!then || !p || byChapter(p)) return
            // A made recap plays from its full file once a place is picked.
            chapterPlaying = -1; chapterWait = ""; recapAudio.stop(); recapAudio.source = ""
        }
        if (recapAudio.source.toString()) { if (then) then(); recapAudio.play(); return }
        if (!p || !p.fullAudioFile) return
        call("driveStreamUrl", { url: p.fullAudioFile.fileUrl }, v => { console.warn("RECAPS play", v.error || "", !!v.url); if (v.url) { recapAudio.source = v.url; recapAudio.play(); if (then) pendingSeek = then } })
    }
    property var pendingSeek: null
    Connections { target: recapAudio; function onMediaStatusChanged() {
        if (root.pendingSeek && recapAudio.seekable) { const f = root.pendingSeek; root.pendingSeek = null; f() }
        if (recapAudio.mediaStatus === MediaPlayer.EndOfMedia && root.chapterPlaying >= 0) root.chapterEnded()
    } }
    // Playing by chapter (Teams' PodcastPlaybackManager: every chapter has
    // its own audio, an HLS stream of the recap's file that grows while the
    // chapter is made, played from its start): a chapter plays, then the
    // next one that hasn't failed; one whose audio isn't there yet is waited
    // for, as is a chapter still being made when its audio runs out, and the
    // next chapter while the recap is still being made. OST plays a recap
    // being made this way (each chapter's stream served to the player with
    // its site's token); a made recap plays from its full audio file.
    /// The chapter playing (its index), -1 when playing the full file.
    property int chapterPlaying: -1
    /// What playing by chapter waits for: "" nothing, "audio" the chapter's
    /// audio, "current" the chapter being made, "next" the next chapter.
    property string chapterWait: ""
    readonly property real playPos: chapterPlaying >= 0 ? (chapterRows[chapterPlaying] ? chapterRows[chapterPlaying].startMs : 0) + recapAudio.position : recapAudio.position
    /// A recap still being made plays by chapter (its fullAudioFile is
    /// named from the start, before it's written).
    function byChapter(p) { return !!p && (!!p.generating || !p.fullAudioFile) }
    /// Teams' hasChapters: a chapter being made or made.
    function hasChapters(p) { return !!p && (p.chapters || []).some(c => c.status === "InProgress" || c.status === "Completed") }
    function chapterAudio(p, i) { const c = p && p.chapters ? p.chapters[i] : null; return c && c.status !== "Failed" && c.audioFile && c.audioFile.fileUrl ? c.audioFile.fileUrl : "" }
    function startChapter(i, offsetMs) {
        const p = recapsPanes.chosen
        const chs = p && p.chapters ? p.chapters : []
        while (i < chs.length && chs[i].status === "Failed") i++
        if (i >= chs.length) { chapterWait = p && p.generating ? "next" : ""; return }
        chapterPlaying = i
        recapAudio.stop(); recapAudio.source = ""
        const u = chapterAudio(p, i)
        if (!u) { chapterWait = "audio"; console.info("RECAPS chapter wait", i); return }
        chapterWait = ""
        const key = p.id
        call("recapChapterAudio", { url: u }, v => {
            if (!recapsPanes.chosen || recapsPanes.chosen.id !== key || chapterPlaying !== i) return
            console.info("RECAPS chapter", i, v.error || "", !!v.url)
            if (!v.url) return
            recapAudio.source = v.url; recapAudio.play()
            if (offsetMs > 0) pendingSeek = () => recapAudio.setPosition(offsetMs)
        })
    }
    function chapterEnded() {
        const p = recapsPanes.chosen
        const c = p && p.chapters ? p.chapters[chapterPlaying] : null
        // Its audio ran out before the chapter was made: wait for it.
        if (c && p.generating && c.status !== "Completed" && c.status !== "Failed") { chapterWait = "current"; return }
        nextChapter()
    }
    function nextChapter() {
        const p = recapsPanes.chosen
        const chs = p && p.chapters ? p.chapters : []
        for (let k = chapterPlaying + 1; k < chs.length; k++) if (chs[k].status !== "Failed") { startChapter(k, 0); return }
        // The last one known: the next may still come.
        chapterWait = p && p.generating ? "next" : ""
    }
    // The recap changed (an update while it's made, or made): go on where
    // playing by chapter waited.
    function chapterProgress() {
        if (chapterPlaying < 0 || chapterWait === "") return
        const p = recapsPanes.chosen
        const chs = p && p.chapters ? p.chapters : []
        const c = chs[chapterPlaying]
        if (chapterWait === "audio") { if (!c || chapterAudio(p, chapterPlaying) || c.status === "Failed" || !p.generating) startChapter(chapterPlaying, 0) }
        else if (chapterWait === "current") { if (!c || c.status === "Completed" || c.status === "Failed" || !p.generating) nextChapter() }
        else if (chapterWait === "next") nextChapter()
    }
    /// "chapters" or "transcript".
    property string detailTab: "chapters"
    function openDetailTab(t) { detailTab = t; if (t === "transcript" && transcriptState === "") loadTranscript() }
    /// The chosen recap's chapters with their place in the full audio
    /// (durations in seconds, added up) and their meeting's name.
    readonly property var chapterRows: {
        const p = recapsPanes.chosen
        let at = 0
        return (p && p.chapters ? p.chapters : []).map(c => {
            // Durations come in seconds (milliseconds when that's absurd).
            const n = Math.max(0, Number(c.duration || 0))
            const d = n > 36000 ? n : n * 1000
            const m = c.meetings && c.meetings.length ? c.meetings[0] : null
            const row = { title: c.title || "", description: c.description || "", startMs: at, endMs: at + d,
                          meeting: m ? m.meetingName || "" : "", meetingKey: m ? m.meetingId || m.callId || m.threadId || "no-meeting" : "",
                          meetingInfo: m }
            at += d
            return row
        })
    }
    /// The chapter list as Teams groups it (its chapter list `ar`): by
    /// meeting; a first or last chapter without a meeting stands alone
    /// (Intro, Outro); each meeting group opens with the meeting.
    readonly property var chapterItems: {
        const out = []
        let lastKey = null
        chapterRows.forEach((c, i) => {
            const key = c.meetingKey || (i === 0 ? "intro" : i === chapterRows.length - 1 ? "outro" : "standalone-" + i)
            if (!c.meetingKey) { out.push({ kind: "standalone", idx: i, title: c.title, startMs: c.startMs, last: i === chapterRows.length - 1 }); lastKey = key; return }
            if (key !== lastKey) {
                const m = c.meetingInfo || {}
                out.push({ kind: "meeting", idx: -1, first: i, title: m.meetingName || c.meeting, threadId: m.threadId || "", subtitle: meetingLine(m) })
                lastKey = key
            }
            out.push({ kind: "chapter", idx: i, title: c.title, startMs: c.startMs })
        })
        return out
    }
    /// "Today · 1:00 PM - 1:30 PM, organizer" (Teams' friendly date and
    /// times with the meeting's organizer).
    function meetingLine(m) {
        if (!m || !m.meetingStartTime) return ""
        const a = new Date(m.meetingStartTime), b = new Date(m.meetingEndTime || m.meetingStartTime)
        const t = x => x.toLocaleTimeString(Qt.locale(), "h:mm AP")
        const s = friendlyDay(a) + " · " + t(a) + " - " + t(b)
        return m.organizer ? s + ", " + m.organizer : s
    }
    function friendlyDay(d) {
        const day = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
        const diff = Math.round((day(new Date()) - day(d)) / 86400000)
        return diff === 0 ? qsTr("Today") : diff === 1 ? qsTr("Yesterday") : d.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
    }
    /// A recap's length in ms (its duration, else its chapters' sum).
    function recapLength(p) {
        const n = Number(p.duration || 0)
        if (n > 0) return n > 36000 ? n : n * 1000
        let s = 0
        for (const c of (p.chapters || [])) { const d = Number(c.duration || 0); s += d > 36000 ? d : d * 1000 }
        return s
    }
    function fmtLength(ms) { const s = Math.max(0, Math.round(ms / 1000)); return qsTr("%1m %2s").arg(Math.floor(s / 60)).arg(s % 60) }
    /// "mm:ss" as Teams marks chapters and transcript lines.
    function fmtClock(ms) { const s = Math.max(0, Math.floor(ms / 1000)); return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0") }
    readonly property int currentChapter: { if (chapterPlaying >= 0) return chapterPlaying; const t = root.playPos; return chapterRows.findIndex(c => t >= c.startMs && t < c.endMs) }
    function playChapter(i) {
        const c = chapterRows[i]
        if (!c) return
        if (currentChapter === i && recapAudio.playbackState === MediaPlayer.PlayingState) { recapAudio.pause(); return }
        const p = recapsPanes.chosen
        if (byChapter(p)) { startChapter(i, 0); return }
        playChosen(() => recapAudio.setPosition(c.startMs))
    }
    function seekTo(ms) {
        const p = recapsPanes.chosen
        if (byChapter(p) && chapterRows.length) {
            // Still being made: within the chapter playing, else from the
            // chapter there.
            const r = chapterRows[chapterPlaying]
            if (r && ms >= r.startMs && (ms < r.endMs || r.endMs <= r.startMs) && recapAudio.source.toString()) { recapAudio.setPosition(ms - r.startMs); return }
            const k = chapterRows.findIndex(c => ms >= c.startMs && ms < c.endMs)
            if (k >= 0) startChapter(k, ms - chapterRows[k].startMs)
            return
        }
        if (recapAudio.source.toString() && chapterPlaying < 0) recapAudio.setPosition(ms); else playChosen(() => recapAudio.setPosition(ms))
    }
    function nextSpeed() { const s = [1, 1.25, 1.5, 1.75, 2, 0.75]; recapAudio.playbackRate = s[(s.indexOf(recapAudio.playbackRate) + 1) % s.length] }
    function fmtTime(ms) { const s = Math.max(0, Math.floor(ms / 1000)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
    // The transcript: the recap's caption file (WebVTT), read as Teams'
    // useTranscriptData does.
    property var transcriptCues: []
    property string transcriptState: ""
    function loadTranscript() {
        const p = recapsPanes.chosen
        if (!p || !p.captionFile || !p.captionFile.fileUrl) { transcriptState = "none"; return }
        transcriptState = "loading"
        const id = p.id
        call("podcastCaptions", { url: p.captionFile.fileUrl }, v => {
            if (!recapsPanes.chosen || recapsPanes.chosen.id !== id) return
            if (v.error || !v.text) { transcriptState = "none"; return }
            transcriptCues = parseVtt(v.text)
            transcriptState = transcriptCues.length ? "ready" : "none"
        })
    }
    function parseVtt(text) {
        const ms = t => { const m = t.trim().match(/(?:(\d+):)?(\d+):(\d+)[.,](\d+)/); return m ? ((Number(m[1] || 0) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000 + Number(m[4]) : 0 }
        // Teams names the voices "Speaker 1", "Speaker 2"… in the order they
        // first speak, and marks the speaker only where it changes; each
        // line of a cue is its own line.
        const out = []
        const hosts = {}
        let n = 1, lastSpeaker = ""
        for (const block of text.replace(/\r/g, "").split(/\n\s*\n/)) {
            const lines = block.split("\n").map(l => l.trim()).filter(l => l.length)
            const ti = lines.findIndex(l => l.indexOf("-->") > 0)
            if (ti < 0) continue
            const [a, b] = lines[ti].split("-->")
            let body = lines.slice(ti + 1).join("\n")
            let label = ""
            const v = body.match(/^<v\s+([^>]+)>([\s\S]*?)(<\/v>)?$/)
            if (v) {
                const name = v[1].trim()
                if (!hosts[name]) hosts[name] = n++
                label = qsTr("Speaker %1").arg(hosts[name])
                body = v[2]
            }
            const start = ms(a), end = ms(b.trim().split(/\s+/)[0])
            const parts = body.replace(/<[^>]+>/g, "").split("\n").map(l => l.trim()).filter(l => l)
            parts.forEach((t, i) => {
                const show = i === 0 && label && label !== lastSpeaker
                out.push({ start: start, end: end, speaker: show ? label : "", text: t })
            })
            if (label) lastSpeaker = label
        }
        return out
    }
    // ··· (Teams: Learn more, Delete; Delete asks first, then deletePodcasts).
    MenuPopup {
        id: recapMenu
        items: [{ key: "learn", label: qsTr("Learn more") }, { key: "delete", label: qsTr("Delete") }]
        onPicked: i => {
            if (items[i].key === "learn") recapLearn.open()
            else recapDelete.open()
        }
    }
    // Learn more (Teams' dialog, 676 wide: the title, a close button and
    // three paragraphs).
    Popup {
        id: recapLearn
        parent: Overlay.overlay
        modal: true; padding: 24.67
        anchors.centerIn: Overlay.overlay
        width: 676
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        contentItem: Column {
            spacing: 8
            Item { width: parent.width; height: 28
                Text { text: qsTr("Learn more"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4; color: lmx.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: lmx }
                    TapHandler { onTapped: recapLearn.close() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Close") } }
            Text { width: parent.width; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text
                   text: qsTr("Audio recap is available for Teams Enterprise users with Microsoft Copilot license. This feature captures and summarizes key topics discussed in your Teams meetings based on transcripts from the selected time period. Summaries are provided in audio formats, enabling efficient review of the highlights without going through individual recaps.")
                         + "\n\n" + qsTr("Audio recap is capable of processing a maximum of eight (8) meetings with transcription.")
                         + "\n\n" + qsTr("Transcriptions of Teams meetings are retained by default for 90 days unless manually deleted earlier by the meeting organizer. The generated audio recap is exclusively accessible to you and will expire after 60 days. You can manage your audio recaps in OneDrive, where you have the option to delete any audio recap that is no longer needed. Please note that once an audio recap is deleted from OneDrive, it will no longer be available on your Teams audio recap listing page.") }
        }
    }
    ConfirmDialog {
        id: recapDelete
        title: qsTr("Delete audio recap?")
        body: qsTr("Are you sure you want to delete this audio recap? The audio recap will also be deleted on your OneDrive.")
        confirmText: qsTr("Delete")
        onConfirmed: {
            const p = recapsPanes.chosen
            if (!p) return
            root.call("podcastDelete", { ids: [p.id] }, v => { root.toast(v.error ? { text: qsTr("Couldn't delete the audio recap."), intent: "error" } : { text: qsTr("Audio recap deleted"), intent: "success" }); root.chosenPodcast = ""; root.loadPodcasts() })
        }
    }
    function chooseDoneForTest() {
        const p = (podcasts || []).find(x => podcastState(x) === "done")
        if (p) chosenPodcast = p.id
        return p ? (p.title || "") + " " + JSON.stringify(Object.keys(p)) + " audio " + String(p.fullAudioFile ? p.fullAudioFile.fileUrl : "").split("?")[0] + " captions " + String(p.captionFile ? p.captionFile.fileUrl : "").split("?")[0] : "none"
    }
    function recapDetailForTest() {
        return JSON.stringify({ tab: detailTab, chapters: chapterRows.map(c => c.title + " @" + fmtTime(c.startMs)), transcript: transcriptState, cues: transcriptCues.length,
                                playing: recapAudio.playbackState === MediaPlayer.PlayingState, position: Math.round(root.playPos / 1000), duration: Math.round(recapAudio.duration / 1000), chapter: currentChapter })
    }
    /// The recap shown on the right (an id; the newest when unset).
    property string chosenPodcast: ""
    // Listen on mobile is offered for a recap that has an id and is being
    // made or made (Teams' Ks: status InProgress or Completed).
    function canListenOnMobile(p) {
        if (!p || !p.id || String(p.id).indexOf("generating-") === 0) return false
        const st = (p.status || p.generationStatus || "").toString().toLowerCase()
        return st === "inprogress" || st === "in_progress" || st === "completed"
    }
    // Teams' "New" badge (ECS calling showListenOnPhoneNewBadge, default on;
    // listenOnPhoneBadgeExpirationDays, default 14): the day it was first
    // shown is kept (Teams' listenOnPhoneNewBadgeStartDateTime) and the
    // badge stays while ceil(days since) <= the limit.
    Settings { id: podcastLocal; location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation) + "/podcast.ini"; category: "podcast"; property string listenOnPhoneNewBadgeStartDateTime: "" }
    function ecsValue(key, dflt) { const v = backend.ecsSetting("calling", key); if (!v) return dflt; try { return JSON.parse(v) } catch (e) { return dflt } }
    readonly property bool listenBadgeShown: {
        if (ecsValue("showListenOnPhoneNewBadge", true) !== true) return false
        const start = podcastLocal.listenOnPhoneNewBadgeStartDateTime
        if (!start) return true
        const days = Math.ceil(Math.abs(Date.now() - Date.parse(start)) / 86400000)
        return days <= Number(ecsValue("listenOnPhoneBadgeExpirationDays", 14) || 0)
    }
    // (Teams starts counting the first time a recap's header is shown.)
    readonly property bool recapHeaderShown: tab === "audio" && !!recapsPanes.chosen
    onRecapHeaderShownChanged: if (recapHeaderShown && listenBadgeShown && !podcastLocal.listenOnPhoneNewBadgeStartDateTime) podcastLocal.listenOnPhoneNewBadgeStartDateTime = new Date().toISOString()
    function openListenOnMobile(p) {
        if (!p || !p.id) return
        qrDialog.rows = ""; qrDialog.open()
        call("podcastQr", { id: p.id }, v => { qrDialog.rows = v.rows || "" })
    }
    // Listen on mobile's dialog (Teams' Vs, measured on winpc 2026-11-22:
    // 600 wide, padding 24, radius 8; "Listen on mobile" 20/28 semibold
    // with Close (32 x 31.3); 8 below, the scan hint 14/20; 20 below, the
    // code: a 130 px picture, white, 0.67 #D1D1D1 edge, radius 20, 10 in,
    // holding qrcode-svg's 200 px code of the recap's meetingpodcast link).
    Popup {
        id: qrDialog
        property string rows: ""
        parent: Overlay.overlay
        modal: true; padding: 24
        anchors.centerIn: Overlay.overlay
        width: Math.min(600, (parent ? parent.width : 600) - 48)
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        contentItem: Column {
            spacing: 8
            Item { width: parent.width; height: 31.3
                Text { text: qsTr("Listen on mobile", "podcast:kb4eg203w"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 31.3; radius: 4; color: qrx.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: qrx; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: qrDialog.close() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Close") } }
            Text { width: parent.width; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                   text: qsTr("Scan the following code with your mobile camera or with a QR reader app. On Android work profile, use the work camera to scan the QR code.") }
            Item { width: parent.width; height: 142
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 12
                    width: 130; height: 130; radius: 20; color: "#FFFFFF"
                    border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Canvas {
                        id: qrCanvas
                        anchors.fill: parent; anchors.margins: 10.67
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.fillStyle = "#FFFFFF"; ctx.fillRect(0, 0, width, height)
                            const rows = qrDialog.rows ? qrDialog.rows.split("\n") : []
                            const n = rows.length
                            if (!n) return
                            const m = width / n
                            ctx.fillStyle = "#000000"
                            for (let y = 0; y < n; y++)
                                for (let x = 0; x < rows[y].length; x++)
                                    if (rows[y][x] === "1") ctx.fillRect(x * m, y * m, m, m)
                        }
                        Connections { target: qrDialog; function onRowsChanged() { qrCanvas.requestPaint() } }
                    }
                    Accessible.role: Accessible.Graphic; Accessible.name: qsTr("QR Code")
                }
            }
        }
    }
    // A recap just made plays by itself from the start, once, unless
    // another one was picked meanwhile (Teams' auto-play after Generate:
    // the recap seen generating plays when its chapters come).
    property string autoPlayId: ""
    function autoPlayIfMade() {
        const p = recapsPanes.chosen
        if (!autoPlayId || !p || p.id !== autoPlayId) return
        // Still being made: from its first chapters on (Teams' autoPlay on
        // HAS_CHAPTERS, the moment a chapter is being made or made).
        if (byChapter(p) && hasChapters(p) && podcastState(p) === "done") {
            autoPlayId = ""
            console.info("RECAPS auto-play", p.id, "chapters", JSON.stringify((p.chapters || []).map(c => [c.status, !!(c.audioFile && c.audioFile.fileUrl)])))
            startChapter(0, 0)
            return
        }
        if (podcastState(p) !== "done" || !p.fullAudioFile || !(p.chapters || []).length) return
        autoPlayId = ""
        console.info("RECAPS auto-play", p.id)
        playChosen(() => recapAudio.setPosition(0))
    }
    /// A recap's state as its row shows it: "generating", "failed" or "done".
    // (Teams' order: failed, then has chapters, then being made: a recap
    // being made shows and plays its chapters once it has any.)
    function podcastState(p) {
        const st = (p.status || p.generationStatus || "").toString().toLowerCase()
        if (st === "failed") return "failed"
        if (hasChapters(p)) return "done"
        if (p.generating || st === "inprogress" || st === "in_progress" || st === "notstarted") return "generating"
        return "done"
    }
    function noInsightPodcast(p) { return /NoValidMeeting(Insight|Found)/.test(p.statusMessage || "") }
    function stateForTest() { return JSON.stringify({ tab: tab, days: days.length, meetings: days.reduce((n, d) => n + d.meetings.length, 0), podcasts: podcasts ? podcasts.length : null, loading: loading }) }
    // Generate audio recap (Teams 26304, measured on winpc 2026-11-19): a
    // dialog (the window less 32 each side): Style (Executive, Newscast,
    // Casual, each with its description) and Language, "Select up to 8
    // meetings" (an info tip "Select up to eight meetings."), All / Missed /
    // Mentions / Followed and Search for meetings, the meetings you have a
    // transcript of from the last 30 days (Teams' calendar-three-people
    // picture and "No meetings were transcribed" when there are none), and
    // Generate (off until a meeting is picked; at most 8).
    Popup {
        id: genDialog
        parent: Overlay.overlay
        modal: true; padding: 37
        x: 32; y: 17
        width: parent.width - 64; height: parent.height - 34
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property string style: "Executive"
        property var picked: []
        property string chip: "All"
        property string filterText: ""
        readonly property var styles: [["Executive", qsTr("Two speakers. Essential info with minimal commentary."), qsTr("Executive")], ["Newscast", qsTr("One speaker. Fast and concise."), qsTr("Newscast")],
                                       ["Casual", qsTr("Two speakers. Extra color and commentary. Longest format."), qsTr("Casual", "podcast:kbrsoygmx")]]
        readonly property var meetings: {
            const cutoff = Date.now() - 30 * 86400000
            let out = []
            // (Teams' meetingRecapList: the meeting artifacts of each day,
            // named by their threadInfo.subject, merged with the Copilot
            // catch-up recommendations, which only add their counts here:
            // a recommendation without a calendar event isn't listed.)
            for (const d of root.days) for (const m of (d.meetings || [])) if (m.transcript && Date.parse(m.start) >= cutoff) out.push(m)
            if (filterText) out = out.filter(m => (m.subject || "").toLowerCase().indexOf(filterText.toLowerCase()) >= 0)
            return out
        }
        function openNow() {
            genDialog.picked = []; genDialog.chip = "All"; genDialog.filterText = ""; genSearch.text = ""; genDialog.collapsed = []; genDialog.open()
            if (!root.loading) root.loadMore()
            root.call("recapCatchUp", {}, v => { if (!v.error) genDialog.catchUp = v })
        }
        /// The weeks (Teams' grouping by the start of the week, newest
        /// first: "This week", "Last week", else the week's first day).
        readonly property var groups: {
            const weekStart = d => { const x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate() - x.getDay()); return x }
            const thisWeek = weekStart(new Date()).getTime(), lastWeek = thisWeek - 7 * 86400000
            const out = []
            // Teams' ka: the meetings by day; this week's days and last
            // week's each make one group, an older day its own ("Friday,
            // November 6", with the year when it isn't this year's; seen on
            // winpc 2026-11-22).
            for (const m of meetings) {
                const d = new Date(Date.parse(m.start))
                const day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
                const w = weekStart(day).getTime()
                const key = w === thisWeek ? "this-week" : w === lastWeek ? "last-week" : String(day.getTime())
                let g = out.find(x => x.key === key)
                if (!g) {
                    const label = key === "this-week" ? qsTr("This week") : key === "last-week" ? qsTr("Last week")
                                : day.toLocaleDateString(Qt.locale(), day.getFullYear() === new Date().getFullYear() ? "dddd, MMMM d" : "dddd, MMMM d, yyyy")
                    g = { key: key, label: label, items: [], at: key === "this-week" ? thisWeek + 7 * 86400000 : key === "last-week" ? thisWeek : day.getTime() }; out.push(g)
                }
                g.items.push(m)
            }
            out.sort((a, b) => b.at - a.at)
            return out
        }
        property var collapsed: []
        property var catchUp: ({})
        property var thumbs: ({})
        function subtitle(m) {
            const a = new Date(Date.parse(m.start)), b = new Date(Date.parse(m.end))
            const t = x => x.toLocaleTimeString(Qt.locale(), "h:mm AP")
            const s = root.friendlyDay(a) + " · " + t(a) + " - " + t(b)
            return m.organizer ? s + " , " + m.organizer : s
        }
        function wantThumb(r) {
            if (!r || !r.itemId || thumbs[r.itemId] !== undefined) return
            const t = Object.assign({}, thumbs); t[r.itemId] = ""; thumbs = t
            root.call("recordingThumb", { driveId: r.driveId, itemId: r.itemId }, v => { if (v.path) { const u = Object.assign({}, genDialog.thumbs); u[r.itemId] = "file://" + v.path; genDialog.thumbs = u } })
        }
        contentItem: Column {
            spacing: 0
            Item { width: parent.width; height: 34
                Text { x: -13; text: qsTr("Generate audio recap"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Rectangle { anchors.right: parent.right; anchors.rightMargin: -12; y: -12; width: 32; height: 32; radius: 4; color: gdx.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: gdx; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: genDialog.close() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Generated audio recaps") } }
            Item { width: 1; height: 18 }
            Row {
                spacing: 20
                Column { spacing: 8; width: (genDialog.availableWidth - 20) / 2
                    Text { text: qsTr("Style"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    ComboBox { width: parent.width; model: genDialog.styles.map(s => s[2]); currentIndex: 0; onActivated: i => genDialog.style = genDialog.styles[i][0]; Accessible.name: qsTr("Style")
                               delegate: ItemDelegate { required property int index; width: parent ? parent.width : 300
                                   contentItem: Column { Text { text: genDialog.styles[index][2]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                                         Text { text: genDialog.styles[index][1]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } } } } }
                Column { spacing: 8; width: (genDialog.availableWidth - 20) / 2
                    Text { text: qsTr("Language"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    ComboBox { width: parent.width; model: [qsTr("English (US)")]; Accessible.name: qsTr("Language") } }
            }
            Item { width: 1; height: 24 }
            Row { spacing: 6
                Text { text: qsTr("Select up to %1 meetings").arg(8); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                FluentIcon { name: "info-16"; size: 16; color: theme.textStrong; ToolTip.visible: gi.hovered; ToolTip.text: qsTr("Select up to eight meetings."); HoverHandler { id: gi } } }
            Item { width: 1; height: 12 }
            Item { width: parent.width; height: 32
                Row { spacing: 8
                    Repeater { model: [["All", qsTr("All")], ["Missed", qsTr("Missed")], ["Mentions", qsTr("Mentions")], ["Followed", qsTr("Followed")]]
                        Rectangle { required property var modelData
                            height: 32; radius: 16; width: chT.implicitWidth + 32
                            color: genDialog.chip === modelData[0] ? theme.pick("#EBEBFF", "#2B2B40", "#000000") : theme.surface
                            border.color: genDialog.chip === modelData[0] ? theme.brand : theme.stroke; border.width: 1
                            Text { id: chT; anchors.centerIn: parent; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; color: genDialog.chip === modelData[0] ? theme.brandForeground1 : theme.text }
                            TapHandler { onTapped: genDialog.chip = modelData[0] }
                            Accessible.role: Accessible.Button; Accessible.name: modelData[1] } } }
                // "✕ n/8 selected" (a pill, 31.3 tall, 0.67 #D1D1D1) clears
                // the picks.
                Rectangle { visible: genDialog.picked.length > 0; anchors.right: genSearchBox.left; anchors.rightMargin: 12; anchors.verticalCenter: genSearchBox.verticalCenter
                            width: selRow.implicitWidth + 24; height: 31.3; radius: height / 2; color: selH.hovered ? theme.hover : theme.surface; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    Row { id: selRow; anchors.centerIn: parent; spacing: 8
                        FluentIcon { name: "dismiss-16"; size: 16; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("%1/%2 selected").arg(genDialog.picked.length).arg(8); font.family: theme.font; font.pixelSize: 14; color: theme.text; anchors.verticalCenter: parent.verticalCenter } }
                    HoverHandler { id: selH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: genDialog.picked = [] }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("%1/%2 selected").arg(genDialog.picked.length).arg(8) }
                Rectangle { id: genSearchBox; anchors.right: parent.right; width: 280; height: 32; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                    TextInput { id: genSearch; x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; clip: true; font.family: theme.font; font.pixelSize: 14; color: theme.text
                                onTextChanged: genDialog.filterText = text
                                Text { visible: !parent.text; text: qsTr("Search for meetings"); font: parent.font; color: theme.textSecondary } } } }
            Item { width: 1; height: 12 }
            Rectangle {
                width: parent.width; height: genDialog.availableHeight - 34 - 18 - 56 - 24 - 20 - 12 - 32 - 12 - 76
                radius: 8; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                Column {
                    visible: genDialog.meetings.length === 0
                    anchors.centerIn: parent; spacing: 24
                    Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; asynchronous: true
                            source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/png/128/calendar-three-people-l-standard-128x128.png" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("No meetings were transcribed"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
                }
                // The meetings grouped (Teams' podcast meeting list: an
                // accordion, "This week", "Last week", then each older day,
                // newest first), each row a square checkbox,
                // the title (14/600) over "date · start - end , organizer"
                // (12), its task and mention chips, the recording's
                // thumbnail and View recap.
                ListView {
                    id: genList
                    visible: genDialog.meetings.length > 0
                    anchors.fill: parent; anchors.margins: 12; clip: true; spacing: 0
                    model: genDialog.groups
                    // Teams' end of the list (16 8 16 16 around 12/16 #616161).
                    footer: Text { visible: root.allLoaded; height: visible ? implicitHeight : 0; x: 4; topPadding: 16; bottomPadding: 16
                                   text: qsTr("Loaded all meetings in the last 30 days."); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    delegate: Column {
                        id: grp
                        required property var modelData
                        readonly property bool open: genDialog.collapsed.indexOf(modelData.key) < 0
                        width: ListView.view.width
                        // The week's header (Fluent accordion, 44 tall: a
                        // 13 px filled caret at 10, the label 14/600 at 31).
                        Item { width: parent.width; height: 44
                            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: grp.open ? "caret-down-12-filled" : "caret-right-12-filled"; size: 13; color: theme.text }
                            Text { x: 31; anchors.verticalCenter: parent.verticalCenter; text: grp.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            TapHandler { onTapped: { const c = genDialog.collapsed.filter(k => k !== grp.modelData.key); if (grp.open) c.push(grp.modelData.key); genDialog.collapsed = c } }
                            Accessible.role: Accessible.Button; Accessible.name: grp.modelData.label }
                        Repeater {
                            model: grp.open ? grp.modelData.items : []
                            // A meeting (measured on winpc 2026-11-22: 72.7
                            // tall from x 12; the checkbox in a 32 px column;
                            // the title 14/600 and the subtitle 12 #616161 at
                            // 50; the chips from the row's middle (24 tall on
                            // #F5F5F5: a 16 px brand glyph and the count
                            // 12/600 #424242); the recording's thumbnail 84 x
                            // 48 at the right; a 0.67 line under it; picked:
                            // #F5F5F5, radius 4).
                            Rectangle {
                                id: mrow
                                required property var modelData
                                required property int index
                                readonly property bool on: genDialog.picked.indexOf(modelData.threadId) >= 0
                                readonly property bool blocked: !on && genDialog.picked.length >= 8
                                readonly property var counts: genDialog.catchUp[modelData.threadId] || null
                                x: 12; width: grp.width - 24; height: 72.7; radius: 4
                                color: on || mrh.hovered ? theme.pick("#F5F5F5", "#292929", "#000000") : "transparent"
                                Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 2
                                    color: mrow.on ? theme.brandFill : "transparent"; border.width: 1; border.color: mrow.on ? theme.brandFill : mrow.blocked ? theme.disabledStrong : theme.textSecondary
                                    FluentIcon { visible: mrow.on; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" } }
                                Column { x: 50; anchors.verticalCenter: parent.verticalCenter; width: parent.width / 2 - 50
                                    Text { width: parent.width; elide: Text.ElideRight; text: mrow.modelData.subject; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; lineHeight: 20; lineHeightMode: Text.FixedHeight }
                                    Text { width: parent.width; elide: Text.ElideRight; text: genDialog.subtitle(mrow.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary; lineHeight: 16; lineHeightMode: Text.FixedHeight } }
                                Row {
                                    x: parent.width / 2 + 10; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    Repeater {
                                        model: mrow.counts ? [["mention", mrow.counts.mentionEventCount], ["task", mrow.counts.actionItemCount]].filter(c => c[1] > 0) : []
                                        Rectangle { required property var modelData
                                            anchors.verticalCenter: parent.verticalCenter; height: 24; radius: 4; width: chipRow.implicitWidth + 16; color: theme.pick("#F5F5F5", "#292929", "#000000")
                                            Row { id: chipRow; x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                                FluentIcon { name: modelData[0] === "mention" ? "mention-16" : "checkmark-circle-16"; size: 16; anchors.verticalCenter: parent.verticalCenter; color: theme.brand }
                                                Text { text: String(modelData[1]); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter } }
                                            ToolTip.visible: chh.hovered
                                            ToolTip.text: modelData[0] === "mention" ? qsTr("%n mention(s) of you", "", modelData[1]) : qsTr("%n tasks for people to follow up on", "", modelData[1])
                                            HoverHandler { id: chh } } }
                                }
                                Image { visible: !!source.toString(); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 84; height: 48; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                        source: genDialog.thumbs[(mrow.modelData.recording || {}).itemId || ""] || "" }
                                HoverHandler { id: mrh; cursorShape: mrow.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                TapHandler { enabled: !mrow.blocked; onTapped: { const p = genDialog.picked.filter(t => t !== mrow.modelData.threadId); if (!mrow.on) p.push(mrow.modelData.threadId); genDialog.picked = p } }
                                Component.onCompleted: genDialog.wantThumb(modelData.recording)
                                Accessible.role: Accessible.CheckBox; Accessible.name: modelData.subject; Accessible.checked: on
                                Rectangle { visible: mrow.index < grp.modelData.items.length - 1; width: parent.width; height: 0.67; anchors.bottom: parent.bottom; color: theme.dividerSoft }
                            }
                        }
                    }
                }
            }
            Item { width: 1; height: 31 }
            Item { width: parent.width; height: 45
                Text { visible: genDialog.picked.length > 8; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Select up to %1 meetings (%2 selected)").arg(8).arg(genDialog.picked.length); font.family: theme.font; font.pixelSize: 14; color: theme.danger }
                Rectangle { anchors.right: parent.right; anchors.rightMargin: -12; width: 200; height: 39; radius: 4
                    readonly property bool usable: genDialog.picked.length > 0 && genDialog.picked.length <= 8
                    color: !usable ? theme.bgDisabled : genH.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Generate"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: parent.usable ? theme.textOnBrand : theme.disabledStrong }
                    HoverHandler { id: genH; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: parent.usable; onTapped: root.generate() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Generate") } }
        }
    }
    function generateDialogForTest(on) { if (on) genDialog.openNow(); else genDialog.close() }
    // Generate (Teams' RecapHome generateAndPopoutPodcast): the dialog
    // closes and Audio recaps shows the new recap at the top of its list as
    // "Generating..." (chosen, its chapters' placeholders and the player
    // bar's "Generating..."); the recap is made from the picked meetings
    // over AugLoop, then the list reloads and shows how it went.
    function generate() {
        const rows = genDialog.meetings.filter(m => genDialog.picked.indexOf(m.threadId) >= 0)
        if (rows.length === 0 || rows.length > 8) return
        genDialog.close()
        const temp = { id: "generating-" + Date.now(), generating: true, createdDateTime: new Date().toISOString() }
        podcasts = [temp].concat(podcasts || [])
        chosenPodcast = temp.id
        // It plays by itself (Teams' triggerAutoPlay), unless another recap
        // is picked meanwhile.
        autoPlayId = temp.id
        tab = "audio"
        console.info("RECAPS generate", rows.length, genDialog.style)
        let made = temp.id
        call("podcastGenerate", { meetings: rows, style: genDialog.style, language: "en-US" }, v => {
            console.info("RECAPS generated", v.status || "", v.message || "", v.error || "", v.podcast && v.podcast.id ? v.podcast.id : "")
            root.lastGenerated = v
            // The new recap stays chosen; one not started yet plays once
            // made, unless another one was picked while it was being made.
            const newId = v.podcast && v.podcast.id ? v.podcast.id : ""
            const pickedOther = root.chosenPodcast !== temp.id && root.chosenPodcast !== made
            if (!pickedOther) root.chosenPodcast = newId
            if (pickedOther || v.status !== "COMPLETED") root.autoPlayId = ""
            else if (root.autoPlayId) root.autoPlayId = newId
            root.loadPodcasts()
        }, v => {
            // The recap as it's made, in the new row's place (with its id,
            // its chapters and their audio as they come).
            const pod = v.podcast || {}
            if (!pod.id) return
            const i = (root.podcasts || []).findIndex(x => x.id === made || x.id === pod.id)
            if (i < 0) return
            console.info("RECAPS progress", v.status || "", JSON.stringify((pod.chapters || []).map(c => [c.status, !!(c.audioFile && c.audioFile.fileUrl)])))
            const chosen = root.chosenPodcast === made
            if (root.autoPlayId === made) root.autoPlayId = pod.id
            made = pod.id
            const list = root.podcasts.slice()
            list[i] = Object.assign({}, pod, { generating: true, createdDateTime: pod.createdDateTime || temp.createdDateTime })
            if (chosen) root.chosenPodcast = pod.id
            root.podcasts = list
            root.autoPlayIfMade()
            root.chapterProgress()
        })
    }
    property var lastGenerated: null
    function pickForTest(subjects, style) {
        genDialog.picked = genDialog.meetings.filter(m => subjects.some(s => (m.subject || "").indexOf(s) === 0)).map(m => m.threadId)
        if (style) genDialog.style = style
        return genDialog.picked.length
    }
    function generateForTest() { generate() }
    function genMeetingsForTest() { return genDialog.groups.map(g => ({ group: g.label, rows: g.items.map(m => [m.subject, genDialog.subtitle(m), genDialog.catchUp[m.threadId] || null, !!(m.recording && m.recording.itemId), genDialog.thumbs[(m.recording || {}).itemId || ""] ? "thumb" : ""]) })) }
    function audioPlayerStateForTest() { const p = recapsPanes.chosen; return JSON.stringify({ chosen: p ? (p.title || "") : null, state: p ? podcastState(p) : "", rows: (podcasts || []).map(x => podcastState(x)),
                                                                                       playing: recapAudio.playbackState === MediaPlayer.PlayingState, position: Math.round(root.playPos / 1000), autoPlay: autoPlayId,
                                                                                       chapter: chapterPlaying, chapterWait: chapterWait, chapterStates: p ? (p.chapters || []).map(c => c.status) : [],
                                                                                       listen: listenRow.visible, listenWidth: listenBtn.width, badge: listenBadgeShown, badgeSince: podcastLocal.listenOnPhoneNewBadgeStartDateTime }) }
    function openListenForTest() { openListenOnMobile(recapsPanes.chosen) }
    function closeListenForTest() { qrDialog.close() }
    function listenDialogForTest() { return JSON.stringify({ open: qrDialog.opened, modules: qrDialog.rows ? qrDialog.rows.split("\n").length : 0, width: qrDialog.width }) }
}
