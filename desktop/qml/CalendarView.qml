import QtQuick
import QtQuick.Controls.Basic

// The Calendar app, laid out as Teams' calendar (its Outlook-hosted
// calendar, measured in Teams on the web as ost-test1, 2026-11-17, at 1x;
// docs/spec/calendar.md):
// - a 235 px side pane with the month and your calendars;
// - a 61 px toolbar: Today, previous/next, the range ▾ | the view ▾, Meet
//   now ▾ (Join with an ID), New ▾ (Event, Channel meeting);
// - Day, Work week and Week: 54 px day headers, the all-day strip (18 px
//   bars 21 apart, titles centred 10/600), the grid at 80 px an hour.
//   Overlapping events share their day side by side (2.6 in, 12 free on the
//   right, 4 between); an event crossing midnight is drawn in each day. In
//   the week that holds today, today takes 30 % of the width and past days
//   11 %; the other days share the rest (a day gets at least what its
//   overlapping events need). Past days and hours outside 8–17 are #FAFAFA,
//   a day under an all-day busy event #EEEFF9;
// - Month: 28 px day names, 163 px cells, events 24 tall 26 apart from 31.6
//   down (time 12/400, title 12/600; all-day ones centred), "+N" when the
//   cell is full; multi-day events span the week's cells;
// - the peek card (392 wide) with Join ▾ / Chat, the time, location, who
//   invited you and your answer (Email organizer, a message, Accept /
//   Decline / Tentative, for a series This event / All events in the
//   series), and the expand button for the event page (MeetingForm).
Item {
    id: root
    property var events: []
    /// The first day shown (local midnight).
    property date start: mondayOf(new Date())
    /// "workweek" (Mon-Fri), "week" (Sun-Sat), "day" or "month".
    property string view: "workweek"
    property bool paneShown: true
    property bool showCalendar: true
    /// For the scheduling form: the teams list, people search results and you.
    property var teams: []
    property var people: []
    property var me: ({})
    signal rangeChanged(string startUtc, string endUtc)
    signal joinMeeting(string joinUrl, string subject)
    signal createEvent(string subject, string startUtc, string endUtc, string attendees, bool teamsMeeting)
    signal openMeetingChat(string joinUrl, string subject)
    signal deleteEvent(string id)
    signal updateEvent(string id, string subject, string startUtc, string endUtc)
    /// backend.calendarAction(op, argsJson).
    signal calendarAction(string op, string argsJson)
    signal searchPeople(string query)
    /// Join with an ID: the meeting ID and passcode.
    signal joinWithId(string meetingId, string passcode)

    readonly property int hourHeight: 80
    readonly property int gutter: 48
    readonly property int days: view === "day" ? 1 : view === "week" ? 7 : view === "month" ? 7 * monthWeeks : 5
    readonly property bool monthView: view === "month"
    /// Month view: the weeks shown (the month's, Sunday first).
    readonly property int monthWeeks: {
        const f = new Date(focusMonth.getFullYear(), focusMonth.getMonth(), 1)
        const last = new Date(f.getFullYear(), f.getMonth() + 1, 0)
        return Math.ceil((f.getDay() + last.getDate()) / 7)
    }
    property date focusMonth: new Date()
    property date now: new Date()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // ── harness ─────────────────────────────────────────────────────────
    function eventBySubject(subject) { return root.events.find(e => e.subject === subject) }
    function cardForTest(subject) {
        const e = eventBySubject(subject)
        if (!e) return false
        details.show(e, null)
        return true
    }
    function editForTest(newTitle) { openPage(details.ev); details.close(); form.typeTitleForTest(newTitle) }
    function saveForTest() { form.submitForTest() }
    function deleteForTest() { details.confirming = true }
    function confirmDeleteForTest() { root.deleteEvent(details.ev.id); details.close() }
    function pageForTest(subject) { const e = eventBySubject(subject); if (e) openPage(e); return !!e }
    function respondForTest(response, series, note) { details.respond(response, series, note) }
    property alias formForTest: form
    property alias detailsForTest: details
    property alias joinIdForTest: joinId
    property alias meetNowForTest: meetNowDialog

    /// Alt+N: schedule a meeting.
    function newMeeting() { openForm(null, [], null) }
    /// The form with people (comma-separated mails) and times filled in (a
    /// suggested reply's meeting: the chat's members, the proposed times).
    function newMeetingWith(attendees, startIso, endIso) {
        const s = startIso ? new Date(startIso) : null
        const people = (attendees || "").split(/[,;]/).map(a => a.trim()).filter(a => a.indexOf("@") > 0).map(a => ({ address: a, name: a }))
        openForm(s && !isNaN(s) ? s : null, people, null)
        const e = endIso ? new Date(endIso) : null
        if (s && e && !isNaN(e) && e > s) form.setTimesForTest(s, e)
    }
    /// Schedule a meeting from a channel's header: the form with the channel.
    function newChannelMeeting(teamId, teamName, channelId, channelName) {
        openForm(null, [], { teamId: teamId, teamName: teamName, channelId: channelId, channelName: channelName })
    }
    function openForm(at, people, channel) {
        formLayer.visible = true
        form.detail = ({})
        form.openNew(at, people, channel)
    }
    /// The event page: yours to edit, or an invitation to answer.
    function openPage(e) {
        const ev = withTeam(e)
        formLayer.visible = true
        form.detail = ({})
        form.openEvent(ev, !!ev.is_organizer)
        calendarAction("detail", JSON.stringify({ id: ev.id }))
    }
    /// A channel meeting's team and channel names, from the teams list.
    function withTeam(e) {
        if (!e || !e.channel_id) return e
        const ev = Object.assign({}, e)
        for (const t of root.teams || []) {
            const c = (t.channels || []).find(c => c.id === e.channel_id)
            if (c) { ev.team_id = t.id; ev.team_name = t.name; ev.channel_name = c.name; break }
        }
        return ev
    }
    /// backend.calendarActionDone.
    property string mtTimeZone: ""
    function actionDone(op, result, error) {
        const r = result ? JSON.parse(result) : {}
        if (op === "detail" && !error && formLayer.visible && form.event && r.id === form.event.id) form.detail = r
        else if (op === "availability" && !error) { form.freeBusy = r.freeBusy || {}; if (r.timeZone) mtTimeZone = r.timeZone }
        else if ((op === "schedule" || op === "update" || op === "cancel") && !error) formLayer.visible = false
        else if (op === "joinById" && !error && r.joinUrl) root.joinMeeting(r.joinUrl, r.subject || "Meeting")
        else if (op === "meetNow" && !error && r.joinUrl) {
            if (meetNowDialog.linkOnly) { meetNowDialog.link = r.joinUrl } else { meetNowDialog.close(); root.joinMeeting(r.joinUrl, r.subject || "Meeting") }
        }
    }

    // ── dates ───────────────────────────────────────────────────────────
    function mondayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - (m.getDay() + 6) % 7)
        return m
    }
    function sundayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - m.getDay())
        return m
    }
    function startFor(d) {
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        if (view === "month") { focusMonth = new Date(day.getFullYear(), day.getMonth(), 1); return sundayOf(focusMonth) }
        return view === "day" ? day : view === "week" ? sundayOf(day) : mondayOf(day)
    }
    function dayAt(i) { const d = new Date(start); d.setDate(d.getDate() + i); return d }
    function shift(n) {
        if (view === "month") { const m = new Date(focusMonth.getFullYear(), focusMonth.getMonth() + n, 1); start = startFor(m); return }
        const d = new Date(start); d.setDate(d.getDate() + n * (view === "day" ? 1 : 7)); start = d
    }
    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function midnight(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function iso(d) { return d.toISOString().replace(/\.\d+Z$/, "Z") }
    /// Local time with its offset, as Teams' form sends times.
    function isoLocal(d) {
        const p = n => (n < 10 ? "0" : "") + n
        const off = -d.getTimezoneOffset(), sign = off >= 0 ? "+" : "-", a = Math.abs(off)
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "T" + p(d.getHours()) + ":" + p(d.getMinutes()) + ":00" + sign + p(Math.floor(a / 60)) + ":" + p(a % 60)
    }
    function emitRange() {
        const end = new Date(start); end.setDate(end.getDate() + days)
        rangeChanged(iso(start), iso(end))
    }
    onStartChanged: emitRange()
    onViewChanged: { start = startFor(view === "month" ? (sameDay(start, startFor(start)) ? dayAt(3) : start) : (monthView ? focusMonth : start)); emitRange() }
    Component.onCompleted: emitRange()
    readonly property string rangeLabel: {
        if (monthView) return Qt.formatDate(focusMonth, "MMMM yyyy")
        const a = start, b = dayAt(days - 1)
        if (days === 1) return Qt.formatDate(a, "MMMM d, yyyy")
        if (a.getMonth() === b.getMonth()) return Qt.formatDate(a, "MMMM d") + "–" + b.getDate() + ", " + b.getFullYear()
        if (a.getFullYear() === b.getFullYear()) return Qt.formatDate(a, "MMMM d") + " – " + Qt.formatDate(b, "MMMM d, yyyy")
        return Qt.formatDate(a, "MMMM d, yyyy") + " – " + Qt.formatDate(b, "MMMM d, yyyy")
    }

    // ── events laid out ─────────────────────────────────────────────────
    function evStart(e) { return new Date(e.start_utc) }
    function evEnd(e) { return new Date(e.end_utc) }
    /// Teams' rule for the all-day strip: all-day events, and events over
    /// several days that run a full day or start or end at midnight.
    function inStrip(e) {
        if (e.is_all_day) return true
        const s = evStart(e), en = evEnd(e)
        if (sameDay(s, new Date(en - 1))) return false
        return (en - s) >= 86400000 || (s.getHours() === 0 && s.getMinutes() === 0) || (en.getHours() === 0 && en.getMinutes() === 0)
    }
    readonly property var shown: showCalendar ? events.filter(e => !e.is_cancelled || e.is_organizer === false) : []
    /// Timed pieces per day column: [{ev, s, e (minutes), lane, lanes}].
    readonly property var dayPieces: {
        const out = []
        if (monthView) return out
        for (let i = 0; i < days; i++) {
            const d0 = dayAt(i), d1 = dayAt(i + 1), list = []
            for (const e of shown) {
                if (inStrip(e)) continue
                const s = evStart(e), en = evEnd(e)
                if (en <= d0 || s >= d1) continue
                const a = Math.max(0, (s - d0) / 60000), b = Math.min(1440, (en - d0) / 60000)
                list.push({ ev: e, s: a, e: Math.max(b, a + 15), lane: 0, lanes: 1 })
            }
            // Earlier first, then shorter (Teams: A 9–10, C 9:30–10, B 9:30–11).
            list.sort((x, y) => x.s - y.s || x.e - y.e)
            let cluster = [], laneEnds = [], clusterEnd = -1
            const close = () => { for (const p of cluster) p.lanes = laneEnds.length; cluster = []; laneEnds = [] }
            for (const p of list) {
                if (p.s >= clusterEnd) { close(); clusterEnd = -1 }
                let lane = laneEnds.findIndex(t => t <= p.s)
                if (lane < 0) { lane = laneEnds.length; laneEnds.push(p.e) } else laneEnds[lane] = p.e
                p.lane = lane
                cluster.push(p)
                clusterEnd = Math.max(clusterEnd, p.e)
            }
            close()
            out.push(list)
        }
        return out
    }
    /// The all-day strip's bars: [{ev, c0, c1, row}].
    readonly property var stripBars: {
        const bars = []
        if (monthView) return bars
        const rows = []
        const list = shown.filter(inStrip).sort((a, b) => evStart(a) - evStart(b) || evEnd(b) - evEnd(a))
        for (const e of list) {
            const s = evStart(e), en = evEnd(e)
            const c0 = Math.max(0, Math.floor((midnight(s) - start) / 86400000))
            const c1 = Math.min(days - 1, Math.floor((midnight(new Date(en - 1)) - start) / 86400000))
            if (c1 < 0 || c0 > days - 1) continue
            let row = rows.findIndex(r => r < c0)
            if (row < 0) { row = rows.length; rows.push(c1) } else rows[row] = c1
            bars.push({ ev: e, c0: c0, c1: c1, row: row })
        }
        return bars
    }
    readonly property int stripRows: stripBars.reduce((m, b) => Math.max(m, b.row + 1), 0)
    readonly property real stripHeight: Math.max(42, stripRows * 21 + 4)
    /// A day under an all-day event that keeps you busy.
    function busyDay(i) { return stripBars.some(b => b.c0 <= i && b.c1 >= i && (b.ev.show_as === "busy" || b.ev.show_as === "oof")) }
    function pastDay(i) { return midnight(dayAt(i)) < midnight(now) && todayIndex >= 0 }
    readonly property int todayIndex: { for (let i = 0; i < days; i++) if (sameDay(dayAt(i), now)) return i; return -1 }
    /// Column widths: today 30 %, past days 11 %, the rest shared (each at
    /// least what its overlapping events need), as Teams lays the week out.
    readonly property var colWidths: {
        const W = Math.max(0, gridArea.width - gutter), n = days
        if (monthView) return []
        if (n === 1 || todayIndex < 0) return Array(n).fill(W / n)
        const w = Array(n).fill(0), rest = []
        let left = W
        for (let i = 0; i < n; i++) {
            if (i === todayIndex) { w[i] = W * 0.3; left -= w[i] }
            else if (i < todayIndex) { w[i] = W * 0.11; left -= w[i] }
            else rest.push(i)
        }
        const need = i => { const m = (dayPieces[i] || []).reduce((a, p) => Math.max(a, p.lanes), 1); return m > 1 ? m * 120.8 + (m - 1) * 4 + 14.6 : 0 }
        let free = rest.slice()
        for (let k = 0; k < rest.length; k++) {
            const share = left / Math.max(1, free.length)
            const big = free.filter(i => need(i) > share)
            if (!big.length) { for (const i of free) w[i] = share; break }
            for (const i of big) { w[i] = need(i); left -= w[i] }
            free = free.filter(i => big.indexOf(i) < 0)
        }
        return w
    }
    function colX(i) { let x = gutter; for (let k = 0; k < i; k++) x += colWidths[k] || 0; return x }
    function colW(i) { return colWidths[i] || 0 }

    // How an event's left bar and fill look for its show-as and your answer.
    function isTentative(e) { return e.show_as === "tentative" || (!e.is_organizer && (e.response === "notResponded" || e.response === "none" || e.response === "tentativelyAccepted")) }
    function fillOf(e) { return (e.show_as === "busy" || e.show_as === "oof" || e.show_as === "workingElsewhere") && !isTentative(e) ? theme.hc("#C7C9EE", "#000000") : theme.hc("#E1E1F6", "#000000") }
    function textOf(e) { return theme.hc(e.show_as === "busy" && !isTentative(e) ? "#323232" : "#414141", "#FFFFFF") }
    function joinable(e) { return !!e.join_url && now >= new Date(evStart(e) - 5 * 60000) && now < evEnd(e) }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // ── side pane: title, month, calendars ──────────────────────────────
    Rectangle {
        id: pane
        visible: root.paneShown
        width: visible ? 235 : 0; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.edge }
        Text { x: 16; y: 19; text: "Calendar"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Item {
            id: month
            x: 8; y: 78; width: 219; height: 230
            property date shown: new Date(root.start.getFullYear(), root.start.getMonth(), 1)
            readonly property date first: { const d = new Date(shown); d.setDate(1 - d.getDay()); return d }
            readonly property int weeks: {
                const last = new Date(shown.getFullYear(), shown.getMonth() + 1, 0)
                return Math.ceil((first.getDay() + (last - first) / 86400000 + 1) / 7)
            }
            Text { x: 24; y: 0; text: Qt.formatDate(month.shown, "MMMM yyyy"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; y: -4
                Repeater {
                    model: [{ icon: "chevron-left-20", d: -1, l: "Previous month" }, { icon: "chevron-right-20", d: 1, l: "Next month" }]
                    Rectangle {
                        id: mFill
                        required property var modelData
                        width: 28; height: 28; radius: theme.radius
                        color: mh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16; color: theme.onFill(mFill, theme.textStrong); rotation: 90 }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const d = new Date(month.shown); d.setMonth(d.getMonth() + parent.modelData.d); month.shown = d } }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.l
                    }
                }
            }
            Row {
                y: 28
                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    Text { required property string modelData; width: 28; horizontalAlignment: Text.AlignHCenter; text: modelData; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
            }
            Grid {
                y: 48
                columns: 7
                Repeater {
                    model: month.weeks * 7
                    Item {
                        required property int index
                        readonly property date day: { const d = new Date(month.first); d.setDate(d.getDate() + index); return d }
                        readonly property bool inMonth: day.getMonth() === month.shown.getMonth()
                        readonly property bool today: root.sameDay(day, root.now)
                        readonly property bool inRange: root.monthView ? false : root.view === "day" ? root.sameDay(day, root.start)
                            : day >= root.sundayOf(root.start) && day < root.dayAt(root.days + (root.view === "workweek" ? 1 : 0))
                        width: 28; height: 28
                        Rectangle { visible: parent.inRange; anchors.fill: parent; color: theme.hc("#DCE0FA", "#1AEBFF") }
                        Rectangle { id: tFill; visible: parent.today; anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: theme.brandFill }
                        Text {
                            anchors.centerIn: parent
                            text: parent.day.getDate()
                            font.family: theme.font; font.pixelSize: theme.small
                            font.weight: parent.today ? Font.DemiBold : Font.Normal
                            color: theme.onFill(tFill, parent.today ? "white" : parent.inMonth ? theme.text : theme.textSecondary)
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.start = root.startFor(parent.day) }
                        Accessible.role: Accessible.Button
                        Accessible.name: theme.longDateNoYear(day)
                    }
                }
            }
        }
        Column {
            x: 16; y: 340; width: parent.width - 32
            spacing: 6
            Text { text: "My calendars"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Item {
                width: parent.width; height: 28
                Rectangle {
                    id: hcFill3
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 2
                    color: root.showCalendar ? theme.brandFill : "transparent"
                    border.color: root.showCalendar ? "transparent" : theme.textStrong
                    FluentIcon { visible: root.showCalendar; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(hcFill3, "white") }
                }
                Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: "Calendar"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                TapHandler { onTapped: root.showCalendar = !root.showCalendar }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Calendar"
                Accessible.checked: root.showCalendar
            }
        }
    }

    component NavButton: Rectangle {
        id: nb
        property alias icon: nbIcon.name
        property string tip
        property int iconSize: 20
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: nbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { id: nbIcon; anchors.centerIn: parent; size: nb.iconSize; color: theme.onFill(nb, theme.textStrong) }
        HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component BarButton2: Rectangle {
        id: bb
        property string icon
        property string label
        property bool chevron: false
        property bool primary: false
        signal clicked()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: bbRow.implicitWidth + 20; height: 32; radius: theme.radius
        color: primary ? (bbh.hovered ? theme.brandHover : theme.brandFill) : bbh.hovered ? theme.rowHover : "transparent"
        Row {
            id: bbRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!bb.icon; anchors.verticalCenter: parent.verticalCenter; name: bb.icon; size: 16; color: theme.onFill(bb, bb.primary ? "white" : theme.textStrong) }
            Text { visible: !!bb.label; text: bb.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: bb.primary ? Font.DemiBold : Font.Normal; color: theme.onFill(bb, bb.primary ? "white" : theme.text) }
            FluentIcon { visible: bb.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(bb, bb.primary ? "white" : theme.textStrong) }
        }
        HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // ── toolbar ─────────────────────────────────────────────────────────
    Item {
        id: bar
        anchors { left: pane.right; right: parent.right }
        height: 61
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            NavButton { icon: "panel-left-20"; tip: root.paneShown ? "Hide navigation" : "Show navigation"; onClicked: root.paneShown = !root.paneShown }
            Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
            BarButton2 { icon: "calendar-ltr-20"; label: "Today"; onClicked: root.start = root.startFor(new Date()); Accessible.name: "Go to today" }
            NavButton { icon: root.monthView ? "chevron-up-20" : "chevron-left-20"; iconSize: 16; onClicked: root.shift(-1); tip: root.monthView ? "Go to previous month" : root.view === "day" ? "Go to previous day" : "Go to previous week" }
            NavButton { icon: root.monthView ? "chevron-down-20" : "chevron-right-20"; iconSize: 16; onClicked: root.shift(1); tip: root.monthView ? "Go to next month" : root.view === "day" ? "Go to next day" : "Go to next week" }
            BarButton2 {
                label: root.rangeLabel; chevron: true
                onClicked: { month.shown = new Date(root.start.getFullYear(), root.start.getMonth(), 1); root.paneShown = true }
                Accessible.name: root.rangeLabel + ", Jump to a specific date"
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            BarButton2 {
                id: viewButton
                icon: ({ day: "calendar-ltr-20", workweek: "calendar-ltr-20", week: "calendar-ltr-20", month: "calendar-ltr-20" })[root.view]
                label: ({ day: "Day", workweek: "Work week", week: "Week", month: "Month" })[root.view]
                chevron: true
                onClicked: viewMenu.open()
                Accessible.role: Accessible.ComboBox
                MenuPopup {
                    id: viewMenu
                    width: 216; y: parent.height + 4
                    items: [{ label: "Day", checked: root.view === "day" }, { label: "Work week", checked: root.view === "workweek" }, { label: "Week", checked: root.view === "week" }, { label: "Month", checked: root.view === "month" }]
                    onPicked: i => root.view = ["day", "workweek", "week", "month"][i]
                }
            }
            Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
            // Meet now ▾: Start a meeting now; the chevron: Join with an ID.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                BarButton2 { icon: "video-20"; label: "Meet now"; onClicked: meetNowDialog.openFresh(); Accessible.name: "Start an instant Teams meeting." }
                BarButton2 {
                    chevron: true; width: 28
                    onClicked: meetMenu.open()
                    Accessible.name: "More meet now options"
                    MenuPopup {
                        id: meetMenu
                        x: -120; y: parent.height + 4; width: 141
                        perItemIcons: true
                        items: [{ label: "Join with an ID", icon: "number-symbol-20" }]
                        onPicked: joinId.openFresh()
                    }
                }
            }
            // New ▾: Event; Channel meeting.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                BarButton2 { primary: true; icon: "calendar-add-20"; label: "New"; onClicked: root.openForm(null, [], null); Accessible.name: "Create a new event." }
                BarButton2 {
                    primary: true; chevron: true; width: 24
                    onClicked: newMenu.open()
                    Accessible.name: "More new options"
                    MenuPopup {
                        id: newMenu
                        x: -150; y: parent.height + 4; width: 174
                        perItemIcons: true
                        items: [{ label: "Event", icon: "calendar-ltr-20" }, { label: "Channel meeting", icon: "channel-20" }]
                        onPicked: root.openForm(null, [], null)
                    }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // ── Day / Work week / Week ──────────────────────────────────────────
    Item {
        id: gridArea
        visible: !root.monthView
        anchors { top: bar.bottom; bottom: parent.bottom; left: pane.right; right: parent.right }
        // Day headers (54) and the all-day strip.
        Item {
            id: heads
            width: parent.width; height: 54 + root.stripHeight
            Repeater {
                model: root.days
                Rectangle {
                    required property int index
                    readonly property date day: root.dayAt(index)
                    readonly property bool today: index === root.todayIndex
                    x: root.colX(index); width: root.colW(index); height: heads.height
                    color: root.busyDay(index) ? theme.hc("#EEEFF9", "#000000") : root.pastDay(index) ? theme.hc("#FAFAFA", "#000000") : theme.surface
                    Rectangle { visible: parent.today; width: parent.width; height: 3; color: theme.brand }
                    Text { x: 13; y: 8; text: parent.day.getDate(); font.family: theme.font; font.pixelSize: 20; color: parent.today ? theme.brand : theme.text }
                    Text { x: 13; y: 33; text: Qt.formatDate(parent.day, "dddd"); font.family: theme.font; font.pixelSize: theme.small; color: parent.today ? theme.brand : theme.textSecondary }
                    Rectangle { width: 1; height: parent.height; color: theme.hc("#D1D1D1", "#FFFFFF") }
                    Rectangle { y: 54; width: parent.width; height: 1; color: theme.hc("#E0E0E0", "#FFFFFF") }
                }
            }
            Repeater {
                model: root.stripBars
                Rectangle {
                    id: sb
                    required property var modelData
                    readonly property var ev: modelData.ev
                    x: root.colX(modelData.c0) + 2.6
                    width: root.colX(modelData.c1) + root.colW(modelData.c1) - 12 - x
                    y: 56 + modelData.row * 21; height: 18
                    radius: 4
                    color: root.fillOf(ev)
                    ShowAsBar { ev: sb.ev; height: parent.height }
                    Text {
                        anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 18)
                        text: sb.ev.subject || "(No title)"; elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: root.textOf(sb.ev)
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: details.show(sb.ev, sb) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (ev.subject || "Event") + ", all day event"
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.hc("#D1D1D1", "#FFFFFF") }
        }

        Flickable {
            id: grid
            anchors { top: heads.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            contentHeight: 24 * root.hourHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Component.onCompleted: contentY = Math.max(0, Math.min(contentHeight - height, (new Date().getHours() - 1) * root.hourHeight))
            // Day backgrounds: past days, hours outside 8–17 and busy days.
            Repeater {
                model: root.days
                Item {
                    required property int index
                    readonly property bool weekend: [0, 6].indexOf(root.dayAt(index).getDay()) >= 0
                    x: root.colX(index); width: root.colW(index); height: grid.contentHeight
                    Rectangle { anchors.fill: parent; color: root.busyDay(index) ? theme.hc("#EEEFF9", "#000000") : root.pastDay(index) || parent.weekend ? theme.hc("#FAFAFA", "#000000") : theme.surface }
                    Rectangle { visible: !root.busyDay(index) && !root.pastDay(index) && !parent.weekend; width: parent.width; height: 8 * root.hourHeight; color: theme.hc("#FAFAFA", "#000000") }
                    Rectangle { visible: !root.busyDay(index) && !root.pastDay(index) && !parent.weekend; y: 17 * root.hourHeight; width: parent.width; height: 7 * root.hourHeight; color: theme.hc("#FAFAFA", "#000000") }
                    Rectangle { width: 1; height: parent.height; color: theme.hc("#D1D1D1", "#FFFFFF") }
                }
            }
            Repeater {
                model: 24
                Item {
                    required property int index
                    y: index * root.hourHeight; width: grid.width; height: root.hourHeight
                    Text {
                        visible: index > 0
                        x: 10; y: 8
                        text: (index % 12 === 0 ? 12 : index % 12) + " " + (index < 12 ? "AM" : "PM")
                        font.family: theme.font; font.pixelSize: 11; color: theme.textSecondary
                    }
                    Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: theme.hc("#D1D1D1", "#FFFFFF") }
                    Row {
                        x: root.gutter; y: root.hourHeight / 2
                        spacing: 3
                        Repeater { model: Math.ceil((grid.width - root.gutter) / 6); Rectangle { width: 3; height: 1; color: theme.hc("#E0E0E0", "#3F3F3F") } }
                    }
                }
            }
            // Click an empty half hour to schedule there.
            MouseArea {
                x: root.gutter; width: grid.width - root.gutter; height: grid.contentHeight
                onClicked: m => {
                    let col = 0
                    while (col < root.days - 1 && root.gutter + m.x >= root.colX(col + 1)) col++
                    const slot = Math.floor(m.y / (root.hourHeight / 2))
                    const d = root.dayAt(col); d.setHours(0, slot * 30, 0, 0)
                    root.openForm(d, [], null)
                }
            }
            Repeater {
                id: eventRepeater
                model: {
                    const all = []
                    root.dayPieces.forEach((list, i) => list.forEach(p => all.push(Object.assign({ col: i }, p))))
                    return all
                }
                Rectangle {
                    id: evTile
                    required property var modelData
                    readonly property var ev: modelData.ev
                    readonly property real laneW: (root.colW(modelData.col) - 14.6 - 4 * (modelData.lanes - 1)) / modelData.lanes
                    readonly property bool shortOne: height < 40
                    x: root.colX(modelData.col) + 2.6 + modelData.lane * (laneW + 4)
                    width: laneW
                    y: modelData.s / 60 * root.hourHeight + 2
                    height: Math.max(17, (modelData.e - modelData.s) / 60 * root.hourHeight - 5)
                    radius: 4
                    color: root.fillOf(ev)
                    border.color: details.visible && details.ev.id === ev.id ? theme.hc("#242424", "#1AEBFF") : "transparent"
                    ShowAsBar { ev: evTile.ev; height: parent.height }
                    // Short: one line (title, location, organizer); else stacked.
                    Text {
                        visible: evTile.shortOne
                        x: 12; y: 4; width: parent.width - 16 - (joinTile.visible ? joinTile.width + 6 : 0) - (seriesIcon.visible ? 20 : 0)
                        elide: Text.ElideRight; textFormat: Text.StyledText
                        text: "<b>" + (evTile.ev.subject || "(No title)").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b> " + [evTile.ev.location, evTile.ev.is_organizer ? "" : evTile.ev.organizer].filter(x => x).join(" ").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                        font.family: theme.font; font.pixelSize: 12; color: root.textOf(evTile.ev)
                    }
                    Column {
                        visible: !evTile.shortOne
                        x: 12; y: 4; width: parent.width - 16
                        Text { width: parent.width; elide: Text.ElideRight; text: evTile.ev.subject || "(No title)"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textOf(evTile.ev) }
                        Text { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: Math.max(1, Math.floor((evTile.height - 24) / 16)); elide: Text.ElideRight; visible: !!text; text: [evTile.ev.location, evTile.ev.is_organizer ? "" : evTile.ev.organizer].filter(x => x).join(" "); font.family: theme.font; font.pixelSize: 12; color: root.textOf(evTile.ev) }
                    }
                    FluentIcon {
                        id: seriesIcon
                        visible: evTile.ev.event_type === "occurrence" || evTile.ev.event_type === "exception"
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                        name: evTile.ev.event_type === "exception" ? "arrow-repeat-all-off-16" : "arrow-repeat-all-16"; size: 16; color: root.textOf(evTile.ev)
                    }
                    // Join on the tile from five minutes before the start.
                    Rectangle {
                        id: joinTile
                        visible: root.joinable(evTile.ev)
                        anchors.right: parent.right; anchors.rightMargin: 4; y: 4
                        width: jt.implicitWidth + 16; height: 22; radius: 4
                        color: jth.hovered ? theme.rowHover : theme.surface
                        border.color: theme.hc("#D1D1D1", "#FFFFFF")
                        Text { id: jt; anchors.centerIn: parent; text: "Join"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        HoverHandler { id: jth; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.joinMeeting(evTile.ev.join_url, evTile.ev.subject || "Meeting") }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Join"
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: details.show(evTile.ev, evTile) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (ev.subject || "Event") + ", " + theme.time(root.evStart(ev)) + " to " + theme.time(root.evEnd(ev))
                }
            }
            // Now: a line across today, dashed before it, with a dot.
            Item {
                id: nowLine
                readonly property int col: root.todayIndex
                visible: col >= 0
                y: (root.now.getHours() + root.now.getMinutes() / 60) * root.hourHeight
                Row {
                    x: root.gutter; spacing: 3
                    Repeater { model: Math.max(0, Math.ceil((root.colX(Math.max(0, nowLine.col)) - root.gutter) / 6)); Rectangle { width: 3; height: 1; color: theme.brand } }
                }
                Rectangle { x: root.colX(Math.max(0, nowLine.col)); width: root.colW(Math.max(0, nowLine.col)); height: 2; y: -0.5; color: theme.brand }
                Rectangle { x: root.colX(Math.max(0, nowLine.col)) - 5; y: -5; width: 10; height: 10; radius: 5; color: theme.brand }
            }
        }
    }

    // How busy an event keeps you: a 4 px bar (busy solid, tentative and
    // unanswered hatched, free white with a brand edge).
    component ShowAsBar: Item {
        id: sab
        property var ev
        width: 4
        Rectangle {
            anchors.fill: parent; radius: 4
            visible: !root.isTentative(sab.ev)
            color: sab.ev && sab.ev.show_as === "free" ? "white" : theme.brand
            border.width: sab.ev && sab.ev.show_as === "free" ? 1 : 0; border.color: theme.brand
        }
        Canvas {
            anchors.fill: parent
            visible: root.isTentative(sab.ev)
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.fillStyle = "white"; c.fillRect(0, 0, width, height)
                c.strokeStyle = theme.brand; c.lineWidth = 1.5
                for (let y = -4; y < height + 4; y += 4) { c.beginPath(); c.moveTo(0, y + 4); c.lineTo(width, y); c.stroke() }
            }
            onHeightChanged: requestPaint()
        }
    }

    // ── Month ───────────────────────────────────────────────────────────
    Item {
        id: monthArea
        visible: root.monthView
        anchors { top: bar.bottom; bottom: parent.bottom; left: pane.right; right: parent.right }
        readonly property real cellW: width / 7
        readonly property real cellH: (height - 28) / root.monthWeeks
        readonly property int rowsPerCell: Math.max(1, Math.floor((cellH - 32 - 4) / 26))
        Repeater {
            model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            Text { required property int index; required property string modelData; x: index * monthArea.cellW + 8; y: 8; text: modelData; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
        Rectangle { y: 28; width: parent.width; height: 1; color: theme.hc("#D1D1D1", "#FFFFFF") }
        /// Per week row: bars [{ev, c0, c1, row, multi}] and, per cell, how many didn't fit.
        readonly property var weeksLaid: {
            const out = []
            if (!root.monthView) return out
            for (let w = 0; w < root.monthWeeks; w++) {
                const d0 = root.dayAt(w * 7), d7 = root.dayAt(w * 7 + 7)
                const items = []
                for (const e of root.shown) {
                    const s = root.evStart(e), en = root.evEnd(e)
                    if (en <= d0 || s >= d7) continue
                    const c0 = Math.max(0, Math.floor((root.midnight(s) - d0) / 86400000))
                    const c1 = Math.min(6, Math.floor((root.midnight(new Date(en - 1)) - d0) / 86400000))
                    items.push({ ev: e, c0: c0, c1: Math.max(c0, c1), multi: c1 > c0 || root.inStrip(e) })
                }
                // Multi-day first, then by start.
                items.sort((a, b) => (b.multi - a.multi) || (root.evStart(a.ev) - root.evStart(b.ev)) || (b.c1 - b.c0) - (a.c1 - a.c0))
                const used = Array(7).fill(0).map(() => [])
                const bars = [], hidden = Array(7).fill(0)
                for (const it of items) {
                    let row = 0
                    while (true) { let ok = true; for (let c = it.c0; c <= it.c1; c++) if (used[c][row]) ok = false; if (ok) break; row++ }
                    for (let c = it.c0; c <= it.c1; c++) used[c][row] = true
                    it.row = row
                    bars.push(it)
                }
                // A cell shows rowsPerCell rows; when it has more, the last is "+N".
                const R = monthArea.rowsPerCell
                for (let c = 0; c < 7; c++) {
                    const n = used[c].filter(x => x).length
                    const lastRow = used[c].length - 1
                    if (lastRow >= R) hidden[c] = bars.filter(b => b.c0 <= c && b.c1 >= c && b.row >= R - 1).length
                }
                out.push({ bars: bars.filter(b => { for (let c = b.c0; c <= b.c1; c++) if (hidden[c] > 0 ? b.row >= R - 1 : b.row >= R) return false; return true }), hidden: hidden })
            }
            return out
        }
        Repeater {
            model: root.monthView ? root.monthWeeks * 7 : 0
            Rectangle {
                id: cell
                required property int index
                readonly property date day: root.dayAt(index)
                readonly property bool today: root.sameDay(day, root.now)
                readonly property bool inMonth: day.getMonth() === root.focusMonth.getMonth()
                x: (index % 7) * monthArea.cellW; y: 29 + Math.floor(index / 7) * monthArea.cellH
                width: monthArea.cellW; height: monthArea.cellH
                color: theme.surface
                border.width: today ? 1 : 0; border.color: theme.brand
                Rectangle { visible: !cell.today; anchors.right: parent.right; width: 1; height: parent.height; color: theme.hc("#E0E0E0", "#FFFFFF") }
                Rectangle { visible: !cell.today; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.hc("#E0E0E0", "#FFFFFF") }
                Rectangle { id: todayDot; visible: cell.today; x: 4; y: 6; width: 22; height: 22; radius: 11; color: theme.brandFill }
                Text {
                    x: cell.today ? 4 : 8; y: 6; width: cell.today ? 22 : implicitWidth; height: cell.today ? 22 : 19
                    horizontalAlignment: cell.today ? Text.AlignHCenter : Text.AlignLeft; verticalAlignment: Text.AlignVCenter
                    text: cell.day.getDate() === 1 ? Qt.formatDate(cell.day, "MMM d") : cell.day.getDate()
                    font.family: theme.font; font.pixelSize: 14; font.weight: cell.today ? Font.DemiBold : Font.Normal
                    color: theme.onFill(todayDot, cell.today ? "white" : theme.textSecondary)
                }
                MouseArea {
                    anchors.fill: parent; z: -1
                    onClicked: { const d = new Date(cell.day); d.setHours(8, 0, 0, 0); root.openForm(d, [], null) }
                }
                // "+N": the rest of the day (opens it).
                Rectangle {
                    readonly property int n: monthArea.weeksLaid[Math.floor(cell.index / 7)] ? monthArea.weeksLaid[Math.floor(cell.index / 7)].hidden[cell.index % 7] : 0
                    visible: n > 0
                    x: 0; y: 31.6 + (monthArea.rowsPerCell - 1) * 26
                    width: parent.width - 8; height: 24; radius: 4
                    color: moreH.hovered ? theme.hc("#E0E0E0", "#1AEBFF") : theme.hc("#F0F0F0", "#000000")
                    Text { anchors.centerIn: parent; text: "+" + parent.n; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    HoverHandler { id: moreH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.view = "day"; root.start = root.startFor(cell.day) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: n + " more events from " + theme.longDate(cell.day)
                }
            }
        }
        Repeater {
            model: {
                const all = []
                monthArea.weeksLaid.forEach((w, i) => w.bars.forEach(b => all.push(Object.assign({ week: i }, b))))
                return all
            }
            Rectangle {
                id: mb
                required property var modelData
                readonly property var ev: modelData.ev
                readonly property bool allDay: root.inStrip(ev)
                x: modelData.c0 * monthArea.cellW
                width: (modelData.c1 - modelData.c0 + 1) * monthArea.cellW - 8.3
                y: 29 + modelData.week * monthArea.cellH + 31.6 + modelData.row * 26
                height: 24; radius: 4
                color: root.fillOf(ev)
                border.color: details.visible && details.ev.id === ev.id ? theme.hc("#242424", "#1AEBFF") : "transparent"
                ShowAsBar { ev: mb.ev; height: parent.height }
                Text {
                    x: mb.allDay ? Math.max(11, (parent.width - implicitWidth) / 2) : 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 11 - (mbSeries.visible ? 26 : 9))
                    elide: Text.ElideRight; textFormat: Text.StyledText
                    text: (mb.allDay ? "" : theme.time(root.evStart(mb.ev)).replace(":00", "") + " ") + "<b>" + (mb.ev.subject || "(No title)").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>"
                    font.family: theme.font; font.pixelSize: 12; color: theme.hc(mb.ev.show_as === "busy" && !root.isTentative(mb.ev) ? "#191919" : "#282828", "#FFFFFF")
                }
                FluentIcon {
                    id: mbSeries
                    visible: mb.ev.event_type === "occurrence" || mb.ev.event_type === "exception"
                    anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                    name: mb.ev.event_type === "exception" ? "arrow-repeat-all-off-16" : "arrow-repeat-all-16"; size: 16; color: theme.text
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: details.show(mb.ev, mb) }
                Accessible.role: Accessible.Button
                Accessible.name: (ev.subject || "Event") + ", " + theme.dateTime(ev.start_utc)
            }
        }
    }

    // ── the peek card ───────────────────────────────────────────────────
    property var pendingMeeting: null
    /// Show a meeting's card (from its chat's Meeting details): its week,
    /// then its card. False when the calendar doesn't have it.
    function showMeeting(joinUrl, icalUid, startIso) {
        const e = root.events.find(x => (joinUrl && x.join_url === joinUrl) || (icalUid && x.ical_uid === icalUid))
        if (e) {
            const d = new Date(e.start_utc)
            if (!isNaN(d)) root.start = root.startFor(d)
            pendingMeeting = null
            details.show(e, null)
            return true
        }
        const d = new Date(startIso || "")
        if (isNaN(d)) return false
        pendingMeeting = { joinUrl: joinUrl, icalUid: icalUid }
        root.start = root.startFor(d)
        return true
    }
    onEventsChanged: {
        if (pendingMeeting) {
            const p = pendingMeeting
            const e = root.events.find(x => (p.joinUrl && x.join_url === p.joinUrl) || (p.icalUid && x.ical_uid === p.icalUid))
            if (e) { pendingMeeting = null; details.show(e, null) }
        }
        // Keep an open card on the event's new state (after an answer).
        if (details.visible && details.ev.id) {
            const e = root.events.find(x => x.id === details.ev.id)
            if (e) details.ev = e
        }
    }
    function responseLine(r) {
        return ({ accepted: "You accepted.", tentativelyAccepted: "You tentatively accepted.", declined: "You declined.", following: "You're following." })[r] || "You didn't respond."
    }
    Popup {
        id: details
        property var ev: ({})
        property bool confirming: false
        property bool changing: false
        property bool emailOrganizer: true
        readonly property bool invite: !!ev.id && ev.is_organizer === false && ev.response_requested !== false
        readonly property bool answered: ["accepted", "tentativelyAccepted", "declined", "following"].indexOf(ev.response) >= 0
        readonly property bool series: ev.event_type === "occurrence" || ev.event_type === "exception"
        readonly property bool live: !!ev.start_utc && root.now >= new Date(root.evStart(ev) - 5 * 60000) && root.now < root.evEnd(ev)
        function show(e, item) {
            ev = e; confirming = false; changing = false; emailOrganizer = true; note.text = ""
            if (!item) { x = (root.width - width) / 2; y = 80; open(); return }
            const p = item.mapToItem(root, 0, 0)
            x = p.x - width - 8 >= 0 ? p.x - width - 8 : Math.min(root.width - width - 8, p.x + item.width + 8)
            y = Math.max(8, Math.min(root.height - implicitHeight - 8, p.y - 8))
            open()
        }
        /// Answer (Teams: RespondToCalendarEvent); a series answer goes to its series.
        function respond(response, wholeSeries, msg) {
            const id = wholeSeries && ev.series_master_id ? ev.series_master_id : ev.id
            root.calendarAction("respond", JSON.stringify({ id: id, response: response, send: emailOrganizer, note: msg !== undefined ? msg : note.text }))
            close()
        }
        width: 392; padding: 0
        background: Rectangle {
            radius: 4; color: theme.menu; border.color: theme.dividerSoft
            Rectangle { width: parent.width; height: 4; radius: 2; color: theme.brand }
        }
        contentItem: Column {
            topPadding: 17; bottomPadding: 16; leftPadding: 17; rightPadding: 17
            spacing: 0
            Item {
                width: 358; height: Math.max(36, titleText.height)
                Text {
                    id: titleText
                    width: parent.width - 32; wrapMode: Text.Wrap
                    text: details.ev.subject || "(No title)"
                    font.family: theme.font; font.pixelSize: 21; font.weight: Font.DemiBold; color: theme.text
                }
                NavButton {
                    anchors.right: parent.right; y: 2; width: 24; height: 24; iconSize: 16
                    icon: "open-20"; tip: "View event"
                    onClicked: { const e = details.ev; details.close(); root.openPage(e) }
                }
            }
            // "Now" for a meeting that's on.
            Row {
                visible: details.live
                height: 24; spacing: 4
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "clock-20"; size: 12; color: theme.brand }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Now"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brand }
            }
            Item { width: 1; height: 16 }
            Row {
                visible: !!details.ev.join_url
                spacing: 5
                CardButton {
                    primary: true; icon: "video-20"; label: "Join"
                    onClicked: { root.joinMeeting(details.ev.join_url, details.ev.subject || "Meeting"); details.close() }
                }
                CardButton {
                    icon: "chat-20"; label: "Chat"
                    onClicked: { root.openMeetingChat(details.ev.join_url, details.ev.subject || "Meeting"); details.close() }
                    Accessible.name: "Chat with participants"
                }
            }
            Item { visible: !!details.ev.join_url; width: 1; height: 16 }
            Rectangle { width: 358; height: 1; color: theme.hc("#F0F0F0", "#FFFFFF") }
            DetailRow {
                icon: "clock-20"
                text: {
                    const e = details.ev
                    if (!e.start_utc) return ""
                    const s = root.evStart(e), en = root.evEnd(e)
                    const d = Qt.formatDate(s, "ddd") + " " + Qt.formatDate(s, "M/d/yyyy")
                    let t = e.is_all_day ? d + " All day" : root.sameDay(s, new Date(en - 1)) ? d + " " + theme.time(s) + " - " + theme.time(en)
                        : d + " " + theme.time(s) + " - " + Qt.formatDate(en, "ddd") + " " + Qt.formatDate(en, "M/d/yyyy") + " " + theme.time(en)
                    return t
                }
                suffix: details.series ? "Series" : ""
            }
            DetailRow {
                icon: "location-20"
                text: details.ev.location && !(details.ev.is_online_meeting && details.ev.location === "Microsoft Teams Meeting") ? details.ev.location : "No location added"
            }
            // Who invited you (or the channel), and your answer.
            Item {
                visible: !!details.ev.id && !details.ev.is_organizer
                width: 358; height: visible ? 52 : 0
                Rectangle { y: 0; x: 34; width: 324; height: 1; color: theme.hc("#F0F0F0", "#FFFFFF") }
                Avatar { x: 0; y: 14; size: 24; name: (details.ev.channel_id ? (root.withTeam(details.ev).team_name || details.ev.organizer) : details.ev.organizer) || ""; photoId: details.ev.channel_id && root.withTeam(details.ev).team_id ? "team:" + root.withTeam(details.ev).team_id : "" }
                Text {
                    x: 36; y: 14; width: 322; elide: Text.ElideRight
                    text: details.ev.channel_id ? (root.withTeam(details.ev).team_name || details.ev.organizer) + " in the channel " + (root.withTeam(details.ev).channel_name || "") : (details.ev.organizer || "Someone") + " invited you."
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text { x: 36; y: 38; text: root.responseLine(details.ev.response); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            }
            DetailRow {
                visible: !!(details.ev.preview || "").trim()
                icon: "text-description-20"
                text: (details.ev.preview || "").replace(/_{4,}/g, "").replace(/\s+/g, " ").trim()
                lines: 5
            }
            // Your answer, as Teams' card asks for it.
            Column {
                visible: details.invite && !details.ev.is_cancelled && (!details.answered || details.changing)
                topPadding: 12; spacing: 8
                Row {
                    spacing: 12
                    FluentIcon { name: "calendar-person-20"; size: 17; color: theme.textSecondary }
                    Rectangle {
                        id: emailBox
                        width: 20; height: 20; radius: 2
                        color: details.emailOrganizer ? theme.brandFill : "transparent"
                        border.color: details.emailOrganizer ? theme.brandFill : theme.textSecondary
                        FluentIcon { visible: details.emailOrganizer; anchors.centerIn: parent; name: "checkmark-12"; size: 14; color: theme.onFill(emailBox, "white") }
                        TapHandler { onTapped: details.emailOrganizer = !details.emailOrganizer }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Email organizer"
                        Accessible.checked: details.emailOrganizer
                    }
                    Text { text: "Email organizer"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                }
                Rectangle {
                    x: 37; width: 309; height: 31
                    color: theme.surface; border.color: note.activeFocus ? theme.brand : theme.hc("#F0F0F0", "#FFFFFF")
                    TextInput {
                        id: note
                        x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                        enabled: details.emailOrganizer
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        Text { visible: !note.text; text: "Add a message (optional)"; color: theme.textSecondary; font: note.font }
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Add a message (optional)"
                }
                Row {
                    x: 37; spacing: 6
                    Repeater {
                        model: [{ r: "Accept", icon: "checkmark-20", c: "#498205" }, { r: "Decline", icon: "dismiss-20", c: "#E81123" }, { r: "Tentative", icon: "question-20", c: "#881798" }]
                        Rectangle {
                            id: rb
                            required property var modelData
                            width: rbRow.implicitWidth + 18; height: 32; radius: 2
                            color: rbh.hovered ? theme.rowHover : modelData.r === "Accept" ? theme.hc("#FAFAFA", "#000000") : theme.surface
                            border.color: theme.hc("#BDBDBD", "#FFFFFF")
                            Row {
                                id: rbRow
                                anchors.centerIn: parent; spacing: 8
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: rb.modelData.icon; size: 16; color: theme.hc(rb.modelData.c, "#FFFFFF") }
                                Text { visible: !details.series || rb.modelData.r !== "Tentative"; anchors.verticalCenter: parent.verticalCenter; text: rb.modelData.r; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                                FluentIcon { visible: details.series; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                            }
                            HoverHandler { id: rbh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: details.series ? scopeMenu.openFor(rb.modelData.r, rb) : details.respond(rb.modelData.r, false) }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.r
                        }
                    }
                }
            }
            // Answered: the answer and Change.
            Row {
                visible: details.invite && details.answered && !details.changing
                topPadding: 12; spacing: 12
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "calendar-person-20"; size: 17; color: theme.textSecondary }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter; size: 16
                    name: ({ accepted: "checkmark-20", declined: "dismiss-20", tentativelyAccepted: "question-20" })[details.ev.response] || "star-20"
                    color: theme.hc(({ accepted: "#498205", declined: "#E81123", tentativelyAccepted: "#881798" })[details.ev.response] || "#5B5FC7", "#FFFFFF")
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ({ accepted: "Accepted", declined: "Declined", tentativelyAccepted: "Tentative", following: "Following" })[details.ev.response] || ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; text: "Change"; font.family: theme.font; font.pixelSize: 14; color: theme.brand
                    TapHandler { onTapped: details.changing = true }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Change"
                }
            }
            Row {
                visible: details.ev.is_organizer === true && !details.confirming
                topPadding: 14; leftPadding: 34; spacing: 6
                CardButton { icon: "edit-20"; label: "Edit"; onClicked: { const e = details.ev; details.close(); root.openPage(e) } }
                CardButton { icon: "calendar-cancel-20"; iconColor: theme.hc("#C50F1F", "#FFFFFF"); label: details.ev.attendees && details.ev.attendees.length || details.ev.channel_id ? "Cancel" : "Delete"; onClicked: details.confirming = true }
            }
            Column {
                visible: details.confirming
                topPadding: 14; spacing: 10
                Text {
                    width: 358; wrapMode: Text.Wrap
                    text: details.ev.attendees && details.ev.attendees.length || details.ev.channel_id ? "Cancel this meeting for everyone?" : "Delete this event?"
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
                }
                Row {
                    spacing: 8
                    CardButton {
                        danger: true; label: details.ev.attendees && details.ev.attendees.length || details.ev.channel_id ? "Cancel meeting" : "Delete"
                        onClicked: {
                            const e = root.withTeam(details.ev)
                            if (e.channel_id || (e.attendees && e.attendees.length)) root.calendarAction("cancel", JSON.stringify({ event: e, teamId: e.team_id || "", note: "" }))
                            else root.deleteEvent(e.id)
                            details.close()
                        }
                    }
                    CardButton { label: "Keep it"; onClicked: details.confirming = false }
                }
            }
        }
    }
    // A series answer: this event or the whole series.
    MenuPopup {
        id: scopeMenu
        property string response
        function openFor(r, item) { response = r; parent = item; x = 0; y = item.height + 2; open() }
        width: 180
        items: [{ label: "This event" }, { label: "All events in the series" }]
        onPicked: i => details.respond(scopeMenu.response, i === 1)
    }

    component DetailRow: Item {
        id: dr
        property alias icon: drIcon.name
        property alias text: drText.text
        property string suffix: ""
        property int lines: 2
        width: 358; height: visible ? Math.max(20, drText.height) + 16 : 0
        FluentIcon { id: drIcon; x: 2; y: 10; size: 20; color: theme.textSecondary }
        Text {
            id: drText
            x: 35; y: 10; width: dr.suffix ? Math.min(implicitWidth, 250) : 314; wrapMode: Text.Wrap; maximumLineCount: dr.lines; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
        }
        Row {
            visible: !!dr.suffix
            x: drText.x + drText.width + 10; y: 12; spacing: 4
            Text { text: dr.suffix; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            FluentIcon { name: "arrow-repeat-all-16"; size: 14; color: theme.textSecondary }
        }
        Rectangle { x: 34; anchors.bottom: parent.bottom; width: 324; height: 1; color: theme.hc("#F0F0F0", "#FFFFFF") }
    }
    component CardButton: Rectangle {
        id: cb
        property string icon
        property string label
        property bool primary: false
        property bool danger: false
        property color iconColor: primary || danger ? "white" : theme.textStrong
        signal clicked()
        width: cbRow.implicitWidth + 24; height: 32; radius: 4
        color: primary ? (cbh.hovered ? theme.brandHover : theme.brandFill)
            : danger ? (cbh.hovered ? theme.hc("#BC2F32", "#1AEBFF") : theme.hc("#D13438", "#000000"))
            : (cbh.hovered ? theme.rowHover : theme.surface)
        border.color: primary || danger ? "transparent" : theme.hc("#D1D1D1", "#FFFFFF")
        Row {
            id: cbRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!cb.icon; anchors.verticalCenter: parent.verticalCenter; name: cb.icon; size: 18; color: theme.onFill(cb, cb.iconColor) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cb.label
                font.family: theme.font; font.pixelSize: theme.base; font.weight: cb.primary || cb.danger || cb.label === "Chat" ? Font.DemiBold : Font.Normal
                color: theme.onFill(cb, cb.primary || cb.danger ? "white" : theme.text)
            }
        }
        HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: cb.label
    }

    // ── Meet now: "Start a meeting now" ─────────────────────────────────
    component Dialog600: Popup {
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 24
        width: 600
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.hc("transparent", "#FFFFFF") }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    }
    component Field600: Rectangle {
        id: f6
        property alias text: f6in.text
        property alias input: f6in
        property string hint
        width: 550; height: 32; radius: 4
        color: theme.surface; border.color: f6in.activeFocus ? theme.brand : theme.hc("#D1D1D1", "#FFFFFF")
        TextInput {
            id: f6in
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
            Text { visible: !f6in.text; text: f6.hint; color: theme.textSecondary; font: f6in.font }
        }
        Accessible.role: Accessible.EditableText
        Accessible.name: hint
    }
    Dialog600 {
        id: meetNowDialog
        property bool linkOnly: false
        property string link: ""
        function openFresh() { linkOnly = false; link = ""; meetName.text = "Meeting with " + (root.me.name || ""); open() }
        contentItem: Column {
            spacing: 0
            Item {
                width: 550; height: 32
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Start a meeting now"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                NavButton { anchors.right: parent.right; icon: "dismiss-20"; tip: "Close"; onClicked: meetNowDialog.close() }
            }
            Item { width: 1; height: 16 }
            Text { text: "Meeting name"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 8 }
            Field600 { id: meetName; hint: "Meeting name" }
            Item { width: 1; height: 20 }
            Text {
                visible: !!meetNowDialog.link
                width: 550; wrapMode: Text.WrapAnywhere; text: meetNowDialog.link
                font.family: theme.font; font.pixelSize: 12; color: theme.brand
            }
            Item { visible: !!meetNowDialog.link; width: 1; height: 12 }
            Row {
                anchors.right: parent.right; spacing: 8
                CardButton { primary: true; icon: "video-20"; label: "Start meeting"; onClicked: { meetNowDialog.linkOnly = false; root.calendarAction("meetNow", JSON.stringify({ subject: meetName.text.trim() || "Meeting" })) } }
                CardButton {
                    icon: "link-20"; label: meetNowDialog.link ? "Copy link" : "Get a link to share"
                    onClicked: {
                        if (meetNowDialog.link) { textCopy.text = meetNowDialog.link; textCopy.selectAll(); textCopy.copy(); return }
                        meetNowDialog.linkOnly = true
                        root.calendarAction("meetNow", JSON.stringify({ subject: meetName.text.trim() || "Meeting" }))
                    }
                }
            }
        }
    }
    TextEdit { id: textCopy; visible: false }

    // ── Join with an ID ─────────────────────────────────────────────────
    Dialog600 {
        id: joinId
        function openFresh() { idField.text = ""; passField.text = ""; open(); idField.input.forceActiveFocus() }
        readonly property bool ready: idField.text.replace(/\s/g, "").length > 0 && passField.text.length > 0
        contentItem: Column {
            spacing: 0
            Item {
                width: 550; height: 32
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Join a meeting with an ID"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                NavButton { anchors.right: parent.right; icon: "dismiss-20"; tip: "Close"; onClicked: joinId.close() }
            }
            Item { width: 1; height: 16 }
            Row {
                spacing: 2
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Meeting ID"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                NavButton {
                    icon: "info-16"; iconSize: 12; tip: "You'll find the meeting ID with the other join info near the bottom of the meeting invite."
                    ToolTip.visible: hovered2.hovered; ToolTip.text: tip
                    HoverHandler { id: hovered2 }
                }
            }
            Item { width: 1; height: 4 }
            Field600 { id: idField; hint: "Type a meeting ID" }
            Item { width: 1; height: 18 }
            Text { text: "Meeting passcode"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 12 }
            Field600 { id: passField; hint: "Type a meeting passcode" }
            Item { width: 1; height: 16 }
            Rectangle {
                id: joinIdButton
                anchors.right: parent.right
                width: jidRow.implicitWidth + 24; height: 32; radius: 4
                color: !joinId.ready ? theme.hc("#F0F0F0", "#000000") : jidh.hovered ? theme.brandHover : theme.brandFill
                Row {
                    id: jidRow
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "video-20"; size: 16; color: joinId.ready ? theme.onFill(joinIdButton, "white") : theme.hc("#BDBDBD", "#3FF23F") }
                    Text { text: "Join Meeting"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: joinId.ready ? theme.onFill(joinIdButton, "white") : theme.hc("#BDBDBD", "#3FF23F") }
                }
                HoverHandler { id: jidh; cursorShape: joinId.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: joinId.ready; onTapped: { root.joinWithId(idField.text.replace(/\s/g, ""), passField.text.trim()); joinId.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Join Meeting"
            }
        }
    }

    // ── the scheduling form and event page (Teams' own, MeetingForm) ────
    Rectangle {
        id: formLayer
        visible: false
        anchors.fill: parent
        color: theme.surface
        z: 10
        MeetingForm {
            id: form
            anchors.fill: parent
            teams: root.teams
            people: root.people
            me: root.me
            onSearchPeople: q => root.searchPeople(q)
            onClosed: formLayer.visible = false
            onAvailabilityWanted: mails => {
                const s = form.startAt, e = form.endAt
                root.calendarAction("availability", JSON.stringify({ people: mails.map(m => [m, m]), start: root.isoLocal(s), end: root.isoLocal(e) }))
            }
            onSubmit: f => {
                const out = {
                    subject: f.subject || "", start: root.isoLocal(f.start), end: root.isoLocal(f.end), allDay: !!f.allDay,
                    attendees: f.attendees || [], location: f.location || "", bodyHtml: f.bodyHtml || "", online: !!f.online,
                    channel: f.channel && f.channel.channelId ? f.channel : null, showAs: f.showAs || "Busy",
                    editingId: f.editingId || "", sendPersonalInvites: !!f.sendPersonalInvites, timeZone: root.mtTimeZone
                }
                if (f.recurrence) {
                    const r = f.recurrence, pattern = { patternType: r.patternType }
                    for (const k of ["daily", "weekly", "monthly", "yearly"]) if (r[k]) pattern[k] = r[k]
                    const range = { startDate: root.isoLocal(root.midnight(r.range && r.range.startDate ? r.range.startDate : f.start)) }
                    if (r.range && r.range.endDate) range.endDate = root.isoLocal(root.midnight(r.range.endDate))
                    out.recurrence = { pattern: pattern, range: range }
                }
                if (out.editingId) root.calendarAction("update", JSON.stringify({ id: out.editingId, form: out }))
                else root.calendarAction("schedule", JSON.stringify({ form: out }))
            }
            onCancelMeeting: note => {
                const e = root.withTeam(form.event)
                root.calendarAction("cancel", JSON.stringify({ event: e, teamId: e.team_id || "", note: note }))
            }
            onRespond: (response, send, msg, series) => {
                const e = form.event
                const id = series && e.series_master_id ? e.series_master_id : e.id
                root.calendarAction("respond", JSON.stringify({ id: id, response: response, send: send, note: msg }))
                formLayer.visible = false
            }
            onJoin: root.joinMeeting(form.event.join_url, form.event.subject || "Meeting")
            onOpenChat: root.openMeetingChat(form.event.join_url, form.event.subject || "Meeting")
            onCopyLink: { textCopy.text = form.event.join_url || ""; textCopy.selectAll(); textCopy.copy() }
        }
    }
    // Make sure the form never covers a calendar it didn't start from.
    property alias formOpen: formLayer.visible
}
