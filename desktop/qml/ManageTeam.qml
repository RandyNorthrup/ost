import QtQuick
import QtQuick.Controls.Basic

// Manage team (a team's menu ▸ Manage team), in the conversation's place as
// Teams shows it (measured on winpc, 2026-11-09):
// - Header (61, white, a #E0E0E0 line under it, padding 0 7 0 20): the
//   team's picture (32, radius 4), its name (18/24 bold) at 60, then the
//   tabs Channels, Members, Pending requests, Settings, Analytics, Apps and
//   Tags (14/20 with 8 each side; the chosen one 600 with a 3 px brand pill
//   under its name); More options (32 x 24) at the right.
// - Channels: the filter pills All / Shown for you / 4 more (Hidden, Shared
//   from other teams, Archived, Deleted), Sort (A-Z, Z-A, Recommended first,
//   By activity, Channel type) and Add channel 24 under the header; Search
//   channels (280 x 32, #F5F5F5) under them; then a row per channel (60.7,
//   a #F0F0F0 line): its name (14/20 semibold, General with a home icon),
//   "Last active: …" and the description (10/14 #616161), Hide / Show and
//   the channel's menu at the end.
// - Analytics: the team's dashboard (AnalyticsView, team scope).
Rectangle {
    id: page
    property string teamId: ""
    property string tab: "channels"
    readonly property var team: {
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        return teams.find(t => t.id === page.teamId) || ({ id: page.teamId, name: "", channels: [] })
    }
    readonly property var general: (team.channels || []).find(c => c.general) || null
    signal openChannel(string channelId, string name)
    signal manageChannel(string channelId)
    signal openChannelWindow(string channelId)
    signal channelWorkflows(string channelId)
    signal acrossTeams()
    color: theme.pick("#FFFFFF", "#292929")
    onTeamIdChanged: { tab = "channels"; filter = "all"; sort = "az"; search.text = "" }

    readonly property var tabs: [["channels", "Channels"], ["members", "Members"], ["pending", "Pending requests"], ["settings", "Settings"], ["analytics", "Analytics"], ["apps", "Apps"], ["tags", "Tags"]]

    // Header.
    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.pick("#FFFFFF", "#292929")
        Avatar {
            x: 20; y: 14.2
            size: 32; square: true; squareRadius: 4
            name: page.team.name || ""
            initialsText: (page.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: page.teamId ? "team:" + page.teamId : ""
        }
        Text {
            id: title
            x: 60; y: 17.2
            width: Math.min(implicitWidth, parent.width * 0.3); elide: Text.ElideRight
            text: page.team.name || ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 24; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: title.x + title.width + 2; y: 2; height: 56.3
            Repeater {
                model: page.tabs
                Item {
                    id: tabItem
                    required property var modelData
                    readonly property bool sel: page.tab === modelData[0]
                    width: tabText.implicitWidth + 16; height: parent.height
                    Text {
                        id: tabText
                        x: 8; y: 16.2
                        text: tabItem.modelData[1]
                        font.family: theme.font; font.pixelSize: 14; font.weight: tabItem.sel ? Font.DemiBold : Font.Normal
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: tabItem.sel ? theme.text : theme.textStrong
                    }
                    Rectangle {
                        visible: tabItem.sel
                        x: 8; width: tabText.implicitWidth; height: 3; radius: 1.5
                        anchors.bottom: parent.bottom
                        color: theme.brand
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.tab = tabItem.modelData[0] }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData[1]
                    Accessible.selected: sel
                }
            }
        }
        Rectangle {
            id: moreButton
            x: parent.width - 39; y: 18.2; width: 32; height: 24; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: teamMenu.menu.opened ? theme.brand : theme.textStrong }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: teamMenu.show(moreButton, moreButton.width - teamMenu.menu.implicitWidth, moreButton.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More options"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    TeamMenu {
        id: teamMenu
        team: page.team
        onManageTeam: page.tab = "channels"
        onChannelCreated: (id, name) => page.openChannel(id, name)
    }
    CreateChannelDialog { id: createChannel; onCreated: (id, name) => page.openChannel(id, name) }

    // ---- Channels ----
    property string filter: "all"
    property string sort: "az"
    readonly property var filterNames: ({ all: "All", shown: "Shown for you", hidden: "Hidden", shared: "Shared from other teams", archived: "Archived", deleted: "Deleted" })
    readonly property var sortNames: ({ az: "A-Z", za: "Z-A", recommended: "Recommended first", activity: "By activity", type: "Channel type" })
    readonly property var rows: {
        const all = (team.channels || []).concat(filter === "deleted" ? (team.deleted_channels || []) : [])
        let out = all.filter(c => {
            switch (page.filter) {
            case "shown": return c.shown !== false
            case "hidden": return c.shown === false
            case "shared": return !!c.shared_in
            case "archived": return !!c.archived
            case "deleted": return (team.deleted_channels || []).some(d => d.id === c.id)
            default: return !c.archived
            }
        })
        const q = search.text.trim().toLowerCase()
        if (q) out = out.filter(c => (c.name || "").toLowerCase().indexOf(q) >= 0)
        const name = c => (c.general ? "General" : c.name || "").toLowerCase()
        const t = c => Date.parse(c.last_active || "") || 0
        out.sort((a, b) => {
            if (page.sort !== "za" && page.sort !== "activity" && page.sort !== "type") {
                // General first (Teams' A-Z and Recommended first).
                if (a.general !== b.general) return a.general ? -1 : 1
            }
            if (page.sort === "za") return name(b).localeCompare(name(a))
            if (page.sort === "activity") return t(b) - t(a)
            if (page.sort === "type") return (a.channel_type - b.channel_type) || name(a).localeCompare(name(b))
            return name(a).localeCompare(name(b))
        })
        return out
    }
    // date-fns formatDistance (en-US), as Teams words "Last active".
    function distance(iso) {
        const ms = Date.now() - (Date.parse(iso) || Date.now())
        const s = Math.round(Math.abs(ms) / 1000), m = Math.round(s / 60)
        const word = (n, w) => n + " " + w + (n === 1 ? "" : "s")
        let txt
        if (m < 1) txt = "less than a minute"
        else if (m < 45) txt = word(m, "minute")
        else if (m < 90) txt = "about 1 hour"
        else if (m < 1440) txt = "about " + word(Math.round(m / 60), "hour")
        else if (m < 2520) txt = "1 day"
        else if (m < 43200) txt = word(Math.round(m / 1440), "day")
        else if (m < 86400) txt = "about " + word(Math.round(m / 43200), "month")
        else if (m < 525600) txt = word(Math.round(m / 43200), "month")
        else {
            const y = Math.floor(m / 525600), rest = m % 525600
            txt = rest < 131400 ? "about " + word(y, "year") : rest < 394200 ? "over " + word(y, "year") : "almost " + word(y + 1, "year")
        }
        return txt + " ago"
    }

    component Pill: Rectangle {
        id: pill
        property string label
        property bool chosen: false
        property bool chevron: false
        signal clicked()
        width: pillRow.implicitWidth + 24; height: chosen ? 31.3 : 30; radius: height / 2
        y: chosen ? 0 : 0.7
        color: chosen ? theme.pick("#E8EBFA", "#2F2F4A") : pillHover.hovered ? theme.pick("#EBEBEB", "#3D3D3D") : theme.pick("#F5F5F5", "#333333")
        border.color: chosen ? theme.pick("#C5CBFA", "#444791") : "transparent"; border.width: 0.67
        Row {
            id: pillRow
            anchors.centerIn: parent; spacing: 4
            Text { anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pill.chosen ? theme.brandForeground1 : theme.text }
            FluentIcon { visible: pill.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.text }
        }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checked: chosen
    }
    Item {
        id: channelsTab
        visible: page.tab === "channels"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        Row {
            x: 28; y: 24; spacing: 12
            Pill { label: "All"; chosen: page.filter === "all"; width: 96; onClicked: page.filter = "all" }
            Pill { label: "Shown for you"; chosen: page.filter === "shown"; onClicked: page.filter = "shown" }
            Pill {
                id: morePill
                readonly property bool inMore: ["hidden", "shared", "archived", "deleted"].indexOf(page.filter) >= 0
                label: inMore ? page.filterNames[page.filter] : "4 more"; chevron: true; chosen: inMore
                width: Math.max(96, implicitWidth)
                onClicked: moreMenu.open()
                MenuPopup {
                    id: moreMenu
                    y: parent.height + 5
                    items: [{ key: "hidden", label: "Hidden" }, { key: "shared", label: "Shared from other teams" }, { key: "archived", label: "Archived" }, { key: "deleted", label: "Deleted" }]
                    onPicked: i => page.filter = items[i].key
                }
            }
        }
        // Sort.
        Rectangle {
            id: sortButton
            x: 372.5; y: 24; width: sortRow.implicitWidth + 24; height: 31.3; radius: 4
            color: sortHover.hovered ? theme.rowHover : "transparent"
            Row {
                id: sortRow
                anchors.centerIn: parent; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Sort: " + page.sortNames[page.sort]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textStrong }
            }
            HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sortMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Sort: " + page.sortNames[page.sort] + " is selected"
            MenuPopup {
                id: sortMenu
                y: parent.height + 5
                items: [{ key: "az", label: "A-Z" }, { key: "za", label: "Z-A" }, { key: "recommended", label: "Recommended first" }, { key: "activity", label: "By activity" }, { key: "type", label: "Channel type" }]
                    .map(i => Object.assign({}, i, { checked: i.key === page.sort }))
                onPicked: i => page.sort = items[i].key
            }
        }
        // Add channel (subtle, the add icon; 40 from the right).
        Rectangle {
            x: parent.width - 40 - width; y: 24; width: addRow.implicitWidth + 24; height: 31.3; radius: 4
            color: addHover.hovered ? theme.rowHover : "transparent"
            Row {
                id: addRow
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: addHover.hovered ? "add-20-filled" : "add-20"; size: 20; color: addHover.hovered ? theme.brand : theme.textStrong }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Add channel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: createChannel.start(page.teamId, page.team.name || "") }
            Accessible.role: Accessible.Button
            Accessible.name: "Add channel"
        }
        // Search channels.
        Rectangle {
            x: 28; y: 55.3; width: 280; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#333333")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0; color: theme.brand }
            TextInput {
                id: search
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !search.text; text: "Search channels"; font: search.font; color: theme.pick("#707070", "#ADADAD") }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search channels"
            }
        }
        // The channels.
        ListView {
            id: channelList
            x: 20; y: 91.3; width: parent.width - 54; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: page.rows
            delegate: Rectangle {
                id: row
                required property var modelData
                width: channelList.width; height: 60.7
                color: rowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                readonly property bool menuOpen: rowMenu.menu.opened && rowMenu.channel.id === row.modelData.id
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333") }
                HoverHandler { id: rowHover }
                Row {
                    x: 20; y: 12; spacing: 14
                    Text {
                        text: row.modelData.general ? "General" : row.modelData.name
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.openChannel(row.modelData.id, row.modelData.name) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Go to channel"
                    }
                    FluentIcon { visible: !!row.modelData.general; anchors.verticalCenter: parent.verticalCenter; name: "home-20"; size: 16; color: theme.text }
                    // Recommended (14 after the name): #F5F5F5, a #E0E0E0
                    // line, radius 4, 10/16 semibold #616161.
                    Rectangle {
                        visible: !!row.modelData.recommended
                        anchors.verticalCenter: parent.verticalCenter
                        width: recText.implicitWidth + 14; height: 20; radius: 4
                        color: theme.pick("#F5F5F5", "#333333")
                        border.color: theme.divider; border.width: 0.67
                        Text { id: recText; x: 7; y: 1; text: "Recommended"; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    }
                    FluentIcon { visible: row.modelData.channel_type === 1; anchors.verticalCenter: parent.verticalCenter; name: "lock-closed-20"; size: 16; color: theme.textSecondary }
                }
                Row {
                    x: 20; y: 33; spacing: 8
                    Text {
                        id: lastActive
                        visible: !!row.modelData.last_active
                        text: "Last active: " + page.distance(row.modelData.last_active)
                        font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                    Rectangle { visible: lastActive.visible && desc.text.length > 0; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 14; color: theme.divider }
                    Text {
                        id: desc
                        width: Math.min(implicitWidth, row.width - 380)
                        elide: Text.ElideRight
                        text: row.modelData.general ? (page.team.description || "") : (row.modelData.description || "")
                        font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                }
                // Hide / Show (Teams' small button, 64 x 24).
                Rectangle {
                    visible: page.filter !== "deleted"
                    x: parent.width - 32 - 12 - width; y: 18
                    width: Math.max(64, hideText.implicitWidth + 16); height: 24; radius: 4
                    color: hideHover.hovered ? theme.rowHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Text { id: hideText; anchors.centerIn: parent; text: row.modelData.shown === false ? "Show" : "Hide"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                    HoverHandler { id: hideHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.channelAction(row.modelData.shown === false ? "show" : "hide", page.teamId, row.modelData.id, "") }
                    Accessible.role: Accessible.Button
                    Accessible.name: hideText.text
                }
                Rectangle {
                    id: rowMore
                    visible: page.filter !== "deleted"
                    x: parent.width - 12 - 32; y: 18; width: 32; height: 24; radius: 4
                    color: rowMoreHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: row.menuOpen ? theme.brand : theme.textStrong }
                    HoverHandler { id: rowMoreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            rowMenu.channel = row.modelData
                            rowMenu.show(rowMore, rowMore.width - rowMenu.menu.implicitWidth, rowMore.height + 5)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "More section options"
                }
            }
        }
    }
    // A row's channel menu (Teams: the channel menu without posts order or
    // Hide, which the row has).
    ChannelMenu {
        id: rowMenu
        teamId: page.teamId; teamName: page.team.name || ""
        postsOrder: false
        rowMode: true
        onOpenInNewWindow: page.openChannelWindow(channel.id)
        onManageChannel: page.manageChannel(channel.id)
        onWorkflows: page.channelWorkflows(channel.id)
    }

    // ---- Analytics ----
    Flickable {
        visible: page.tab === "analytics"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width; contentHeight: analytics.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        AnalyticsView {
            id: analytics
            width: parent.width
            teamScope: true
            teamId: page.teamId
            channelId: page.tab === "analytics" && page.general ? page.general.id : ""
            channels: page.team.channels || []
            onPickChannel: id => page.manageChannelAnalytics(id)
            onAcrossTeams: page.acrossTeams()
        }
    }
    signal manageChannelAnalytics(string channelId)

    // Test hooks.
    function analyticsForTest() { return analytics }
    function rowsForTest() { return page.rows }
    function createChannelForTest() { return createChannel }
}
