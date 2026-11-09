import QtQuick

// Teams' analytics dashboard for a channel (Manage channel ▸ Analytics;
// measured on winpc 2026-11-09, read from its channel-dashboard code):
// - "Select a channel" (All Channels and the team's channels) and "Time
//   period" (Last Seven / Thirty / Ninety Days) at 30, 50 down, two 31.3
//   tall dropdowns 10 apart; the period's dates ("10/30/2026 - 11/5/2026",
//   semibold, 35 tall) after them; "Analytics across channels" (brand,
//   31.3) under them at the right.
// - From 152.7 down, 20 in: Summary (Active users, Meetings) and Engagement
//   (Posts, Replies, Reactions, Mentions) side by side, 10 apart; then the
//   Active users (line), Meetings (columns) and Engagement (stacked
//   columns) charts, each the full width. Cards #FAFAFA, radius 4, padding
//   12; the title 14/20 bold 26 down; numbers 28/36 over 14/20 names, spread
//   across; "No Data Available" centred when there's nothing.
// - Charts min(40% of the window's height, 300) tall.
// Picking All Channels or Analytics across channels opens the team's.
Item {
    id: av
    property string teamId: ""
    property string channelId: ""
    /// The whole team (Manage team ▸ Analytics): All Channels, Active
    /// guests, "Analytics across teams"; `channelId` is then the team's
    /// General (the request goes through it).
    property bool teamScope: false
    signal acrossTeams()
    property var channels: []
    property string period: "last-seven-days"
    property var result: null
    property bool loading: false
    property bool failed: false
    signal pickChannel(string channelId)
    signal teamAnalytics()
    implicitHeight: cards.y + cards.implicitHeight + 20

    readonly property real chartHeight: Math.min(Math.floor((Window.window ? Window.window.height : 700) * 0.4), 300)
    readonly property var periods: [["last-seven-days", "Last Seven Days"], ["last-thirty-days", "Last Thirty Days"], ["last-ninety-days", "Last Ninety Days"]]

    function load() {
        if (!teamId || !channelId) return
        loading = true; failed = false
        backend.channelAction("analytics", teamId, channelId, JSON.stringify({ period: period, team: teamScope }))
    }
    onChannelIdChanged: { result = null; load() }
    onPeriodChanged: load()
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "analytics" || r.channel !== av.channelId) return
            if (r.ok && r.data && (!!r.data.team !== av.teamScope || r.data.period !== av.period)) return
            av.loading = false
            av.failed = !r.ok
            av.result = r.ok ? r.data.analytics : null
        }
    }

    readonly property var metrics: result ? result.metrics || {} : {}
    function total(name) { const m = metrics[name]; return m && m.value !== null && m.value !== undefined ? m.value : undefined }
    function points(name) {
        const m = metrics[name]
        return m ? m.series.map(p => ({ name: dayLabel(p[0]), y: p[1] })) : []
    }
    function dayLabel(iso) { const d = new Date(iso); return isNaN(d) ? iso : (d.getMonth() + 1) + "/" + d.getDate() }
    function dateLabel(iso) { const d = new Date(iso); return isNaN(d) ? "" : (d.getMonth() + 1) + "/" + d.getDate() + "/" + d.getFullYear() }

    // Teams' error bar (MessageBar, intent error) over the page.
    Rectangle {
        id: errorBar
        visible: av.failed
        x: 20; y: 0; width: av.width - 20 - av.rightGutter; height: visible ? 36 : 0
        radius: 4
        color: theme.pick("#FDF3F4", "#3F1011")
        border.color: theme.pick("#EEACB2", "#6E0811"); border.width: 0.67
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-circle-20-filled"; size: 20; color: theme.pick("#BC2F32", "#DC626D") }
        Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: "We are sorry - We've run into an issue"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Rectangle {
            x: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 4
            color: dismissHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: av.failed = false }
            Accessible.role: Accessible.Button; Accessible.name: "Dismiss"
        }
    }

    // Teams' team page is 14 wider on the right (no channel gutter).
    readonly property real rightGutter: teamScope ? 34 : 48
    readonly property real controlsW: width - 40 - rightGutter
    // Measured: the period's dates take 192.5 (channel) / 197.1 (team).
    readonly property real dateW: teamScope ? 197.1 : 192.5
    readonly property real dropW: Math.max(120, (controlsW - 20 - dateW) / 2)
    Text { x: 30; y: 30; text: "Select a channel"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
    Dropdown {
        x: 30; y: 50; width: av.dropW; height: 31.3
        options: [["", "All Channels"]].concat(av.channels.map(c => [c.id, c.general ? "General" : c.name]))
        label: { const o = options.find(o => o[0] === (av.teamScope ? "" : av.channelId)); return o ? o[1] : "" }
        accessibleName: "Channel Dropdown"
        onPicked: code => code === "" ? (av.teamScope ? null : av.teamAnalytics()) : (av.teamScope || code !== av.channelId ? av.pickChannel(code) : null)
    }
    Text { x: 30 + av.dropW + 10; y: 30; text: "Time period"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
    Dropdown {
        x: 30 + av.dropW + 10; y: 50; width: av.dropW; height: 31.3
        options: av.periods
        label: av.periods.find(p => p[0] === av.period)[1]
        accessibleName: "Time period"
        onPicked: code => av.period = code
    }
    Text {
        visible: !!av.result && !!av.result.start && !!av.result.end
        x: 30 + 2 * (av.dropW + 10); y: 46.3; height: 35
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.StyledText
        text: av.result ? "<b>" + av.dateLabel(av.result.start) + "</b> - <b>" + av.dateLabel(av.result.end) + "</b>" : ""
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Rectangle {
        id: acrossButton
        x: 30 + av.controlsW - width; y: 91.3
        width: acrossText.implicitWidth + 24; height: 31.3; radius: 4
        color: acrossHover.hovered ? theme.brandHover : theme.brandFill
        Text { id: acrossText; anchors.centerIn: parent; text: av.teamScope ? "Analytics across teams" : "Analytics across channels"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
        HoverHandler { id: acrossHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: av.teamScope ? av.acrossTeams() : av.teamAnalytics() }
        Accessible.role: Accessible.Button; Accessible.name: acrossText.text
    }

    component Card: Rectangle {
        id: card
        property string title
        property bool empty: true
        property real bodyHeight: 0
        default property alias body: bodyItem.data
        radius: 4
        color: theme.quoteFill
        height: 72 + (av.loading && !av.result ? 40 : empty ? 40 : bodyHeight) + 12
        Text { x: 12; y: 26; text: card.title; font.family: theme.font; font.pixelSize: 14; font.bold: true; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: card.title }
        Text {
            visible: card.empty && !(av.loading && !av.result)
            anchors.horizontalCenter: parent.horizontalCenter; y: 82
            text: "No Data Available"
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        // Loading: Teams' skeleton.
        Rectangle {
            visible: av.loading && !av.result
            x: 12; y: 82; width: Math.min(200, parent.width - 24); height: 20; radius: 4
            color: theme.pick("#E6E6E6", "#3D3D3D")
            SequentialAnimation on opacity { running: parent.visible; loops: Animation.Infinite; NumberAnimation { to: 0.4; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
        }
        Item { id: bodyItem; visible: !card.empty; x: 12; y: 71.3; width: parent.width - 24; height: card.bodyHeight }
    }
    // Teams' stat (a 28/36 number over a 14/20 name), spread across the card.
    component Stats: Item {
        id: stats
        property var items: []
        height: 56
        readonly property var widths: items.map((it, i) => Math.max(statMeasure.itemAt(i) ? statMeasure.itemAt(i).implicitWidth : 0, 0))
        readonly property real gap: items.length > 1 ? (width - widths.reduce((a, b) => a + b, 0)) / (items.length - 1) : 0
        Repeater {
            id: statMeasure
            model: stats.items
            Column {
                required property var modelData
                required property int index
                x: stats.widths.slice(0, index).reduce((a, b) => a + b, 0) + index * stats.gap
                Text { text: Number(modelData[0]).toLocaleString(Qt.locale("en_US"), "f", 0); font.family: theme.font; font.pixelSize: 28; lineHeight: 36; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { text: modelData[1]; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Accessible.role: Accessible.StaticText
                Accessible.name: modelData[0] + " " + modelData[1]
            }
        }
    }

    Column {
        id: cards
        x: 20; y: 152.7; width: av.width - 20 - av.rightGutter
        spacing: 10
        Row {
            width: parent.width; spacing: 10
            Card {
                id: summary
                width: (parent.width - 10) / 2
                title: "Summary"
                readonly property var items: (av.teamScope
                    ? [[av.total("activeUsers"), "Active users"], [av.total("guests"), "Active guests"], [av.total("meetingsOrganized"), "Meetings"]]
                    : [[av.total("activeUsers"), "Active users"], [av.total("meetingsOrganized"), "Meetings"]]).filter(i => i[0] !== undefined)
                empty: items.length === 0
                bodyHeight: 56
                height: Math.max(implicitHeightOf(summary), implicitHeightOf(engagement))
                Stats { width: parent.width; items: summary.items }
            }
            Card {
                id: engagement
                width: (parent.width - 10) / 2
                title: "Engagement"
                readonly property var items: [[av.total("postMessages"), "Posts"], [av.total("replyMessages"), "Replies"], [av.total("reactions"), "Reactions"], [av.total("mentions"), "Mentions"]].filter(i => i[0] !== undefined)
                empty: items.length === 0
                bodyHeight: 56
                height: Math.max(implicitHeightOf(summary), implicitHeightOf(engagement))
                Stats { width: parent.width; items: engagement.items }
            }
        }
        Card {
            id: activeCard
            width: parent.width
            title: "Active users"
            readonly property var pts: av.points("activeUsers")
            empty: pts.length === 0
            bodyHeight: av.chartHeight
            AnalyticsChart { y: 0.7; width: parent.width; height: av.chartHeight; kind: "spline"; series: [{ name: "Active users", points: activeCard.pts }]; description: "Chart Showing Timeseries of active users" }
        }
        Card {
            id: meetingsCard
            width: parent.width
            title: "Meetings"
            readonly property var pts: av.points("meetingsOrganized")
            empty: pts.length === 0
            bodyHeight: av.chartHeight
            AnalyticsChart { y: 0.7; width: parent.width; height: av.chartHeight; kind: "column"; series: [{ name: "Meetings", points: meetingsCard.pts }]; description: "Chart Showing Timeseries of meeting" }
        }
        Card {
            id: engagementCard
            width: parent.width
            title: "Engagement"
            readonly property var all: [["Posts", av.points("postMessages")], ["Replies", av.points("replyMessages")], ["Mentions", av.points("mentions")], ["Reactions", av.points("reactions")]]
            empty: all.every(s => s[1].length === 0)
            bodyHeight: av.chartHeight
            AnalyticsChart { y: 0.7; width: parent.width; height: av.chartHeight; kind: "stacked"; series: engagementCard.all.map(s => ({ name: s[0], points: s[1] })); description: "Chart Showing Timeseries of Engagement like reactions, posts etc." }
        }
    }
    // A summary card's own height (the two side by side share the taller).
    function implicitHeightOf(c) { return 72 + (av.loading && !av.result ? 40 : c.empty ? 40 : c.bodyHeight) + 12 }

    // Test hooks.
    function cardsForTest() { return [summary, engagement, activeCard, meetingsCard, engagementCard] }
}
