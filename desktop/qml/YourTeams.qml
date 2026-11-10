import QtQuick
import QtQuick.Controls.Basic

// Your teams and channels (the chat list's "See all your teams"), in the
// conversation's place as Teams shows it (measured on winpc 2026-11-09 and
// read from its teams-dashboard code; docs/spec/chat-list-and-header.md
// §5.6.9):
// - Header (61, white, no line under it): "Your teams and channels" (20/28
//   bold) at 20, then the tabs Teams, Pending invites and Analytics (14/20,
//   8 each side, the chosen one 600 with a 3 px brand pill under it); the
//   Create team split button (128.2 + 24 x 31.3, people-team-add icon,
//   14 semibold #424242) 7 from the right, its chevron offering Create team
//   and Join Team.
// - Teams: the filter pills All / Teams you own / 3 more (Teams you own,
//   Teams with channels hidden, Teams with channels shown, Archived Teams;
//   the menu leaves out the chosen one) 48 in and 24.3 under the header;
//   Sort (A-Z, Z-A, Team type, Membership Type, Visibility Type); Search
//   teams (280 x 32, outlined) 48 from the right. Rows from 146 down, 45 in
//   and 39 from the right, 60.7 tall with a #F0F0F0 line: the team's
//   picture (28, round), its name (14/20 semibold), then 10/14 Private |
//   N people | N channels | description with #E0E0E0 dividers; the hidden
//   mark (a 20 px eye off, 8, a 20 tall #E0E0E0 line, 8) before the role
//   when none of its channels is shown; the role (Owner, Member, Guest;
//   14/20) at the right. On hover the row is #F5F5F5 and the mark and role
//   give way to the team's ··· (its team menu). A row opens Manage team.
// - Pending invites: shared-channel invitations to your teams; Teams'
//   No_request illustration (245 x 230.7, 70 under the header) and "When
//   people invite your team to a shared channel, the invite will show up
//   here." (18/25.7 semibold) when there are none.
// - Analytics: across the teams you own (TeamsAnalyticsTable).
Rectangle {
    id: page
    property string tab: "teams"
    color: theme.pick("#FFFFFF", "#292929")
    signal manageTeam(string teamId)
    signal manageTags(string teamId)
    signal openChannel(string channelId, string name)
    signal createTeam()
    signal joinTeam()
    readonly property var allTeams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
    onVisibleChanged: if (visible) { filter = ""; sort = "az"; search.text = ""; query = "" }

    readonly property var tabs: [["teams", "Teams"], ["pending", "Pending invites"], ["analytics", "Analytics"]]

    // Header.
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            id: title
            x: 20; y: 15.5
            text: "Your teams and channels"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Row {
            x: title.x + title.implicitWidth + 2; y: 2; height: 57
            Repeater {
                model: page.tabs
                Item {
                    id: tabItem
                    required property var modelData
                    readonly property bool sel: page.tab === modelData[0]
                    width: tabText.implicitWidth + 16; height: parent.height
                    Text {
                        id: tabText
                        x: 8; y: 18.5
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
        // Create team: a split button (the action and its chevron).
        Rectangle {
            id: createMain
            x: parent.width - 7 - 24 - width; y: 14.8; width: 128.2; height: 31.3
            radius: 4
            color: createHover.hovered ? theme.rowHover : "transparent"
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-team-add-20"; size: 20; color: theme.textStrong }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Create team"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            HoverHandler { id: createHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: page.createTeam() }
            Accessible.role: Accessible.Button
            Accessible.name: "Create team"
        }
        Rectangle {
            id: createMore
            x: parent.width - 7 - 24; y: 14.8; width: 24; height: 31.3
            radius: 4
            color: createMoreHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-12"; size: 12; color: theme.textStrong }
            HoverHandler { id: createMoreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: createMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "More create team options"
            MenuPopup {
                id: createMenu
                x: parent.width - implicitWidth - 4.3; y: parent.height + 4
                minRowWidth: 128.7
                items: [{ key: "create", label: "Create team" }, { key: "join", label: "Join Team" }]
                onPicked: i => items[i].key === "create" ? page.createTeam() : page.joinTeam()
            }
        }
    }

    // ---- Teams ----
    // Teams' filter tags: "" (All), OWNED, HIDDEN, SHOWN, ARCHIVED.
    property string filter: ""
    property string sort: "az"
    property string query: ""
    readonly property var filterNames: ({ "": "All", OWNED: "Teams you own", HIDDEN: "Teams with channels hidden", SHOWN: "Teams with channels shown", ARCHIVED: "Archived Teams" })
    readonly property var sortNames: ({ az: "A-Z", za: "Z-A", type: "Team type", membership: "Membership Type", visibility: "Visibility Type" })
    function anyShown(t) { return (t.channels || []).some(c => c.shown !== false) }
    function roleName(r) { return r === "admin" ? "Owner" : r === "guest" ? "Guest" : "Member" }
    readonly property var rows: {
        let out = page.allTeams.filter(t => {
            switch (page.filter) {
            // Archived teams count everywhere (Teams marks them).
            case "OWNED": return t.role === "admin"
            case "HIDDEN": return !page.anyShown(t)
            case "SHOWN": return page.anyShown(t)
            case "ARCHIVED": return !!t.archived
            default: return true
            }
        })
        const q = page.query.trim().toLowerCase()
        if (q) out = out.filter(t => (t.name || "").toLowerCase().indexOf(q) >= 0)
        const name = t => (t.name || "").toLowerCase()
        const vis = t => t["public"] ? "Public" : "Private"
        out.sort((a, b) => {
            switch (page.sort) {
            case "za": return name(b).localeCompare(name(a))
            case "type": return (a.team_type - b.team_type) || name(a).localeCompare(name(b))
            case "membership": return page.roleName(a.role).localeCompare(page.roleName(b.role)) || name(a).localeCompare(name(b))
            case "visibility": return vis(a).localeCompare(vis(b)) || name(a).localeCompare(name(b))
            default: return name(a).localeCompare(name(b))
            }
        })
        return out
    }

    // Teams' tag buttons: the chosen one white with a #D1D1D1 line and
    // brand text, the others #F5F5F5.
    component Pill: Rectangle {
        id: pill
        property string label
        property bool chosen: false
        property bool chevron: false
        property bool menuOpen: false
        signal clicked()
        width: Math.max(96, pillRow.implicitWidth + 24); height: chosen || menuOpen ? 31.3 : 30; radius: height / 2
        y: chosen || menuOpen ? 0 : 0.7
        color: chosen || menuOpen ? theme.surface : pillHover.hovered ? theme.pick("#EBEBEB", "#3D3D3D") : theme.pick("#F5F5F5", "#333333")
        border.color: chosen || menuOpen ? theme.stroke : "transparent"; border.width: 0.67
        Row {
            id: pillRow
            anchors.centerIn: parent; spacing: 4
            Text { anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pill.chosen || pill.menuOpen ? theme.brandForeground1 : theme.text }
            FluentIcon { visible: pill.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: pill.chosen || pill.menuOpen ? theme.brandForeground1 : theme.text }
        }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: chosen ? label + ", Selected" : label
    }
    Item {
        id: teamsTab
        visible: page.tab === "teams"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        Row {
            id: pills
            x: 48; y: 24.3; spacing: 12
            Pill { label: "All"; chosen: page.filter === ""; onClicked: page.filter = "" }
            // Teams you own until another filter is chosen; then that one.
            Pill {
                readonly property string key: page.filter === "" ? "OWNED" : page.filter
                label: page.filterNames[key]
                chosen: page.filter === key
                onClicked: page.filter = key
            }
            Pill {
                label: "3 more"; chevron: true
                menuOpen: moreMenu.opened
                onClicked: moreMenu.open()
                MenuPopup {
                    id: moreMenu
                    x: 4.8; y: parent.height + 4
                    minRowWidth: 189.2
                    items: ["OWNED", "HIDDEN", "SHOWN", "ARCHIVED"].filter(k => k !== page.filter).map(k => ({ key: k, label: page.filterNames[k] }))
                    onPicked: i => page.filter = items[i].key
                }
            }
            // Sort (transparent, 14 semibold #424242).
            Rectangle {
                id: sortButton
                width: sortRow.implicitWidth + 24; height: 31.3; radius: 4
                color: sortHover.hovered ? theme.rowHover : "transparent"
                Row {
                    id: sortRow
                    anchors.centerIn: parent; spacing: 4
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Sort: " + page.sortNames[page.sort]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: sortMenu.opened ? theme.brandForeground1 : theme.textStrong }
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: sortMenu.opened ? theme.brandForeground1 : theme.textStrong }
                }
                HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sortMenu.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Sort: " + page.sortNames[page.sort] + " is selected"
                MenuPopup {
                    id: sortMenu
                    x: 4.8; y: parent.height + 4
                    minRowWidth: 128.7
                    items: [{ key: "az", label: "A-Z" }, { key: "za", label: "Z-A" }, { key: "type", label: "Team type" }, { key: "membership", label: "Membership Type" }, { key: "visibility", label: "Visibility Type" }]
                    onPicked: i => page.sort = items[i].key
                }
            }
        }
        // Search teams (Fluent outline input; Teams waits 250 ms).
        Rectangle {
            x: parent.width - 48 - width; y: 24; width: 280; height: 32; radius: 4
            color: theme.surface
            border.color: theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0.67; color: search.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: search
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                selectByMouse: true
                onTextChanged: searchTimer.restart()
                Text { visible: !search.text; text: "Search teams"; font: search.font; color: theme.pick("#707070", "#ADADAD") }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search teams"
            }
            Timer { id: searchTimer; interval: 250; onTriggered: page.query = search.text }
        }
        // Teams' "no results": its tag_not_found illustration (245, 140.2
        // under the header) and "We didn't find any matches" (18/25.7
        // semibold) 430.1 under it, both centred.
        Image {
            visible: page.rows.length === 0
            x: (parent.width - width) / 2; y: 140.2
            width: 245; height: 245
            source: "../assets/illustrations/no-matches.svg"
            sourceSize: Qt.size(490, 490)
        }
        Text {
            visible: page.rows.length === 0
            x: 20; width: parent.width - 40; y: 430.1
            horizontalAlignment: Text.AlignHCenter
            text: "We didn't find any matches"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        ListView {
            id: teamList
            x: 45; y: 146 - 61; width: parent.width - 45 - 39; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            model: page.rows
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool menuOpen: rowMenu.menu.opened && rowMenu.team.id === row.modelData.id
                readonly property bool hot: rowHover.hovered || menuOpen
                readonly property bool hidden: !page.anyShown(row.modelData)
                width: teamList.width; height: 60.7
                color: hot ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333") }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.manageTeam(row.modelData.id) }
                Accessible.role: Accessible.Row
                Accessible.name: row.modelData.name || ""
                Avatar {
                    x: 8; y: 16; size: 28
                    name: row.modelData.name || ""
                    initialsText: (row.modelData.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                    photoId: "team:" + row.modelData.id
                }
                Row {
                    x: 46; y: 10; spacing: 4
                    Text {
                        text: row.modelData.name || ""
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                        Accessible.role: Accessible.Button
                        Accessible.name: "Team " + text + ", Go to Manage team channels"
                    }
                    FluentIcon { visible: !!row.modelData.archived; anchors.verticalCenter: parent.verticalCenter; name: "archive-20"; size: 16; color: theme.text }
                }
                Row {
                    id: facts
                    x: 46; y: 30; height: 20; spacing: 8
                    component Fact: Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    component Bar: Rectangle { width: 0.67; height: 20; color: theme.divider }
                    Fact { text: row.modelData["public"] ? "Public" : "Private" }
                    Bar {}
                    Fact { text: (row.modelData.people || 0) + " people" }
                    Bar {}
                    Fact { text: (row.modelData.channels || []).length + " channels" }
                    Bar {}
                    Fact {
                        width: Math.min(implicitWidth, row.width - 46 - facts.x - 300)
                        elide: Text.ElideRight
                        text: row.modelData.description || ""
                    }
                }
                // The hidden mark (Teams' eye off and a long divider).
                // Hover shows only the ··· in their place.
                Row {
                    visible: row.hidden && !row.hot
                    x: role.x - 8 - width; y: 20; spacing: 8
                    FluentIcon { name: "eye-off-20"; size: 20; color: theme.text }
                    Rectangle { width: 0.67; height: 20; color: theme.divider }
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "All channels are hidden"
                }
                Text {
                    id: role
                    visible: !row.hot
                    x: parent.width - 8 - width; y: 20
                    text: page.roleName(row.modelData.role)
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Rectangle {
                    id: rowMore
                    visible: row.hot
                    x: parent.width - 8 - 32; y: 14.7; width: 32; height: 31.3; radius: 4
                    color: rowMoreHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: row.menuOpen ? theme.brand : theme.textStrong }
                    HoverHandler { id: rowMoreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            rowMenu.team = row.modelData
                            rowMenu.show(rowMore, rowMore.width - rowMenu.menu.implicitWidth, rowMore.height + 4)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Team " + (row.modelData.name || "") + ", More Options"
                }
            }
        }
    }
    TeamMenu {
        id: rowMenu
        onManageTeam: id => page.manageTeam(id)
        onManageTags: id => page.manageTags(id)
        onChannelCreated: (id, name) => page.openChannel(id, name)
    }

    // ---- Pending invites ----
    property var invitations: []
    property bool invitationsLoaded: false
    onTabChanged: if (tab === "pending") backend.channelAction("invitations", "", "", "")
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "invitations") return
            page.invitationsLoaded = true
            page.invitations = r.ok ? r.data || [] : []
        }
    }
    Item {
        visible: page.tab === "pending" && page.invitationsLoaded
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        Image {
            visible: page.invitations.length === 0
            x: (parent.width - width) / 2; y: 70
            width: 245; height: 230.7
            source: "../assets/illustrations/no-invites.svg"
            sourceSize: Qt.size(490, 461)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            visible: page.invitations.length === 0
            x: 20; width: parent.width - 40; y: 345.6
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "When people invite your team to a shared channel, the invite will show up here."
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        // With invitations: Teams' two sections, Needs action and Pending
        // owner approval, each a table (Shared channel, Sent by,
        // Organization for another org's channel, Expires in).
        Flickable {
            visible: page.invitations.length > 0
            anchors.fill: parent; anchors.margins: 8
            contentHeight: invCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: invCol
                width: parent.width
                spacing: 8
                Repeater {
                    model: [
                        ["Needs action", page.invitations.filter(i => ["Validating", "Sent", "Revoked"].indexOf(i.state) >= 0)],
                        ["Pending owner approval", page.invitations.filter(i => ["Validating", "Sent", "Revoked"].indexOf(i.state) < 0)]
                    ]
                    Column {
                        id: sectionCol
                        required property var modelData
                        width: invCol.width
                        Text {
                            height: 44; verticalAlignment: Text.AlignVCenter; leftPadding: 12
                            text: sectionCol.modelData[0] + " (" + sectionCol.modelData[1].length + ")"
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        Item {
                            width: sectionCol.width; height: 32
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                            Row {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                Repeater {
                                    model: [["Shared channel", 220], ["Sent by", 180], ["Organization", 160], ["Expires in", 120]]
                                    Text { required property var modelData; width: modelData[1]; text: modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                                }
                            }
                        }
                        Repeater {
                            model: sectionCol.modelData[1]
                            Item {
                                id: inv
                                required property var modelData
                                width: sectionCol.width; height: 44
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                                Row {
                                    x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                    Text { width: 220; elide: Text.ElideRight; text: inv.modelData.channel + (inv.modelData.channel_tenant && inv.modelData.channel_tenant !== backend.tenantId() ? " (External)" : ""); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                    Text { width: 180; elide: Text.ElideRight; text: inv.modelData.inviter; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                    Text { width: 160; elide: Text.ElideRight; text: inv.modelData.organization; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                    Text { width: 120; text: page.expiresIn(inv.modelData.expires); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    function expiresIn(iso) {
        const d = Math.ceil(((Date.parse(iso) || Date.now()) - Date.now()) / 86400000)
        return d <= 0 ? "" : d === 1 ? "1 day" : d + " days"
    }

    // ---- Analytics ----
    TeamsAnalyticsTable {
        id: analyticsView
        visible: page.tab === "analytics"
        active: visible
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        teams: page.allTeams
    }

    // Test hooks.
    function openMoreForTest() { moreMenu.open() }
    function openSortForTest() { sortMenu.open() }
    function openCreateMenuForTest() { createMenu.open() }
    function closeMenusForTest() { moreMenu.close(); sortMenu.close(); createMenu.close() }
    function rowsForTest() { return page.rows }
    function setQueryForTest(q) { search.text = q; page.query = q }
    function rowMenuForTest() { return rowMenu }
    function analyticsForTest() { return analyticsView }
}
