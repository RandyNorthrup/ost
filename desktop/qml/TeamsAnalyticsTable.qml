import QtQuick
import QtQuick.Controls.Basic

// Your teams and channels ▸ Analytics: Teams' analytics across the teams
// you own (measured on winpc 2026-11-09, read from its teams-dashboard
// code):
// - "Time period" (14/20) 20 in and 20 down; its dropdown (Last Seven /
//   Thirty / Ninety Days, 250 x 31.3) under it; the period's dates (14
//   semibold, "10/30/2026 - 11/5/2026") 10 after it.
// - A white card (radius 4, padding 12, Fluent shadow) 91.3 down, 20 from
//   each side, holding the table: a 32.7 header row (Name, People, Active
//   users, Active guests, Posts, Replies, Type; 14 normal) and 44.7 rows,
//   each with a #E0E0E0 line. Columns 150, 100, 150, 100, 100, 100, 200
//   (scrolling sideways when the card is narrower); text 8 in.
// - Name: the team's picture (28, radius 4) and name 38 after it. Active
//   users: the number (40 wide) and Teams' 80 x 20 area sparkline (#5B5FC7
//   2 px over 30% fill; y from 0 to Highcharts' soft max 10 with its
//   padding). Type: a 14 px lock (Private), globe (Public) or building
//   (org-wide) and the word.
// - Teams asks for 40 teams at a time and the next page when the list is
//   scrolled to its end.
Item {
    id: view
    /// The joined teams (backend team list) for People and pictures.
    property var teams: []
    property bool active: false
    property string period: "last-seven-days"
    property var rows: []
    property string start: ""
    property string end: ""
    property string next: ""
    property bool loading: false
    property bool failed: false
    readonly property var periods: [["last-seven-days", "Last Seven Days"], ["last-thirty-days", "Last Thirty Days"], ["last-ninety-days", "Last Ninety Days"]]

    function load(cursor) {
        loading = true; failed = false
        backend.channelAction("cross-team-analytics", "", "", JSON.stringify({ period: period, cursor: cursor || "" }))
    }
    onActiveChanged: if (active) { rows = []; load("") }
    onPeriodChanged: if (active) { rows = []; load("") }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "cross-team-analytics") return
            if (r.ok && r.data.period !== view.period) return
            view.loading = false
            view.failed = !r.ok
            if (!r.ok) return
            const a = r.data.analytics
            view.rows = (r.data.cursor ? view.rows : []).concat(a.teams || [])
            view.start = a.start; view.end = a.end; view.next = a.next || ""
        }
    }
    function dateLabel(iso) { const d = new Date(iso); return isNaN(d) ? "" : (d.getMonth() + 1) + "/" + d.getDate() + "/" + d.getFullYear() }
    function teamOf(id) { return view.teams.find(t => t.id === id || t.thread_id === id) || null }
    function num(v) { return v === null || v === undefined ? "" : String(v) }

    Text { x: 20; y: 20; text: "Time period"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
    Dropdown {
        x: 20; y: 40; width: 250; height: 31.3
        options: view.periods
        label: view.periods.find(p => p[0] === view.period)[1]
        accessibleName: "Time period"
        onPicked: code => view.period = code
    }
    Row {
        visible: !!view.start && !!view.end
        x: 280; y: 35.7; height: 20; spacing: 10
        Text { text: view.dateLabel(view.start); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        Text { text: "-"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Text { text: view.dateLabel(view.end); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
    }
    // Teams' error bar.
    Text {
        visible: view.failed
        x: 20; y: 91.3
        text: "We are sorry - We've run into an issue"
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }

    readonly property var columns: [["Name", 150], ["People", 100], ["Active users", 150], ["Active guests", 100], ["Posts", 100], ["Replies", 100], ["Type", 200]]
    readonly property real tableWidth: 900
    FluentSurface {
        id: card
        visible: !view.failed && (view.rows.length > 0 || !view.loading)
        x: 20; y: 91.3; width: view.width - 40
        height: Math.min(view.height - y - 20, 12 + 32.7 + view.rows.length * 44.7 + 12)
        depth: 4; radius: 4; color: theme.surface
        Flickable {
            id: table
            x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
            contentWidth: view.tableWidth; contentHeight: 32.7 + view.rows.length * 44.7
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            onAtYEndChanged: if (atYEnd && view.next && !view.loading) view.load(view.next)
            // Header.
            Item {
                width: view.tableWidth; height: 32.7
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                Row {
                    Repeater {
                        model: view.columns
                        Item {
                            required property var modelData
                            width: modelData[1]; height: 32
                            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                    }
                }
                Accessible.role: Accessible.Row
            }
            Repeater {
                model: view.rows
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var team: view.teamOf(modelData.id)
                    y: 32.7 + index * 44.7
                    width: view.tableWidth; height: 44.7
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                    Accessible.role: Accessible.Row
                    Accessible.name: row.modelData.name
                    // Name.
                    Avatar {
                        x: 8; y: 8; size: 28; square: true; squareRadius: 4
                        name: row.modelData.name || ""
                        initialsText: (row.modelData.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: "team:" + row.modelData.id
                    }
                    Text {
                        x: 46; y: 12; width: 150 - 46 - 4; elide: Text.ElideRight
                        text: row.modelData.name || ""
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    component Cell: Text {
                        y: 12
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Cell { x: 158; text: row.team ? String(row.team.people || 0) : "" }
                    Cell { x: 258; text: view.num(row.modelData.active_users.value) }
                    Sparkline { x: 306; y: 9; points: (row.modelData.active_users.series || []).map(p => p[1]) }
                    Cell { x: 408; text: view.num(row.modelData.guests) }
                    Cell { x: 508; text: view.num(row.modelData.posts) }
                    Cell { x: 608; text: view.num(row.modelData.replies) }
                    Row {
                        x: 708; y: 12; spacing: 4
                        FluentIcon {
                            visible: name !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            name: row.modelData.privacy === "PRIVATE" ? "lock-closed-20" : row.modelData.privacy === "PUBLIC" ? "globe-20" : row.modelData.privacy === "ORGWIDE" ? "building-20" : ""
                            size: 14; color: theme.text
                        }
                        Cell {
                            y: 0
                            text: ({ PRIVATE: "Private", PUBLIC: "Public", ORGWIDE: "Org-wide" })[row.modelData.privacy] || ""
                        }
                    }
                }
            }
        }
    }

    // Teams' minimal area chart: 80 x 20, no axes; points spread from
    // 80/102 to 80·101/102; y from 0 to max(10, data) with Highcharts'
    // padding (a 1 drew 1.67 high in Teams).
    component Sparkline: Canvas {
        id: spark
        property var points: []
        width: 80; height: 20
        onPointsChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = spark.points.length
            if (n < 2) return
            const top = Math.max(10, Math.max.apply(null, spark.points)) * 1.2
            const x0 = 80 / 102, span = 80 * 100 / 102
            const px = i => x0 + i * span / (n - 1)
            const py = v => 20 - v / top * 20
            ctx.beginPath()
            ctx.moveTo(px(0), py(spark.points[0]))
            for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(spark.points[i]))
            ctx.lineTo(px(n - 1), 20); ctx.lineTo(px(0), 20); ctx.closePath()
            ctx.fillStyle = Qt.rgba(91 / 255, 95 / 255, 199 / 255, 0.3)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(px(0), py(spark.points[0]))
            for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(spark.points[i]))
            ctx.strokeStyle = "#5B5FC7"; ctx.lineWidth = 2
            ctx.stroke()
        }
    }
}
