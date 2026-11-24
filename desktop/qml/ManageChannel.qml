import QtQuick
import QtQuick.Controls.Basic

// Manage channel (a channel's menu ▸ Manage channel), in the conversation's
// place as Teams shows it (measured on winpc, 2026-11-09):
// - Header (61, white, a #E0E0E0 line under it, padding 0 7 0 20): the
//   team's picture (32, radius 4) 14.2 down; the channel (18/24 bold) at
//   60; tabs Settings and Analytics 2 after it (14/20 with 8 each side, 600
//   and #242424 when chosen with a 3 px brand pill under the name, else
//   #424242); More options (32 x
//   24) at the right: Go to channel, Open in new window | Manage
//   notifications ▸, Move to section ▸, Hide | Edit channel, Manage
//   channel, Copy link, Get email address.
// - Settings: sections 48 in from each side, 20 down, each a 44 tall
//   header (a 20 px chevron at 10, the name 14/20 semibold at 38, what it
//   holds 30 after in #616161) and a #E0E0E0 line after it.
//   - Channel details: the name (28/36 semibold), its layout in a grey pill
//     (Posts / Threads), Edit (brand, 96 x 31.3) opening Edit channel.
//   - Moderation (General): "General Channel:" and Teams' three choices
//     (16 px radios 8 in a 32 box; names 14/20, #616161 unless chosen),
//     saved as the team's spaceAdminSettings when picked. Other channels:
//     ChannelModeration (Channel moderation On/Off, moderators, who can
//     post, members' permissions).
// - Analytics: AnalyticsView.
Rectangle {
    id: page
    property string teamId: ""
    property string teamName: ""
    property string channelId: ""
    property string tab: "settings"
    property string myPresence: ""
    readonly property var team: {
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        return teams.find(t => t.id === page.teamId) || null
    }
    readonly property var channel: page.team ? (page.team.channels || []).find(c => c.id === page.channelId) || ({ id: page.channelId }) : ({ id: page.channelId })
    readonly property bool general: channel.general === true
    property int generalSetting: -1
    property bool savingModeration: false
    signal goToChannel(string channelId)
    signal openInNewWindow(string channelId)
    signal manageChannel(string channelId)
    signal teamAnalytics(string teamId)
    signal workflows(string channelId)
    color: theme.pick("#FFFFFF", "#292929", "#000000")

    function loadModeration() {
        generalSetting = -1
        if (general) backend.channelAction("moderation-load", teamId, channelId, "")
    }
    readonly property int channelType: channel.channel_type || 0
    onChannelIdChanged: { tab = channelType > 0 ? "members" : "settings"; loadModeration(); detailsOpen = true; moderationOpen = true; loadMembers() }
    onChannelTypeChanged: if (channelType > 0 && tab === "settings") { tab = "members"; loadMembers() }
    // Members (private and shared channels): the channel's people (Graph)
    // and, shared, the teams it's shared with and its sent invites.
    property var members: []
    property var sharedTeams: []
    property var sentInvites: []
    function loadMembers() {
        if (!channelId || channelType === 0) return
        backend.channelAction("channel-members", teamId, channelId, "")
        if (channelType === 2) backend.channelAction("shared-with", teamId, channelId, "")
    }
    onGeneralChanged: loadModeration()
    Component.onCompleted: loadModeration()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== page.channelId) return
            if (r.op === "channel-members" && r.ok) page.members = r.data.members || []
            else if (r.op === "shared-with" && r.ok) {
                page.sharedTeams = (r.data.teams && r.data.teams.linkedTeams) || []
                // Declined, approved and withdrawn ones drop off, as in Teams.
                page.sentInvites = ((r.data.invitations && r.data.invitations.invitations) || []).filter(i => i.state === "Sent" || i.state === "Pending")
            }
            else if (["channel-add-members", "share-team-owner", "share-own-team", "channel-invitation"].indexOf(r.op) >= 0 && r.ok) page.loadMembers()
            else if (r.op === "moderation-load" && r.ok) page.generalSetting = r.data.general
            else if (r.op === "moderation") {
                page.savingModeration = false
                if (r.ok) page.generalSetting = r.data.general
                else { page.loadModeration(); backend.toast(qsTr("Something went wrong on our end. Please try again."), "error") }
            }
        }
    }

    // Header.
    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.pick("#FFFFFF", "#292929", "#000000")
        Avatar {
            x: 20; y: 14.2
            size: 32; square: true; squareRadius: 4
            name: page.teamName
            initialsText: page.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: page.teamId ? "team:" + page.teamId : ""
        }
        Text {
            id: title
            x: 60; y: 17.2
            width: Math.min(implicitWidth, parent.width * 0.35); elide: Text.ElideRight
            text: page.channel.general ? qsTr("General") : (page.channel.name || "")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 24; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: title.x + title.width + 2; y: 2; height: 56.3
            Repeater {
                // Teams' tabs (measured 2026-11-20): a private channel's
                // Members, Settings, Analytics; a shared one's Members,
                // Invites and requests, Settings.
                model: page.channelType === 2 ? [["members", qsTr("Members")], ["invites", qsTr("Invites and requests")], ["settings", qsTr("Settings")]]
                    : page.channelType === 1 ? [["members", qsTr("Members")], ["settings", qsTr("Settings")], ["analytics", qsTr("Analytics")]]
                    : [["settings", qsTr("Settings")], ["analytics", qsTr("Analytics")]]
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
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, channelMenu.menu.opened ? theme.brand : theme.textStrong) }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: channelMenu.show(moreButton, moreButton.width - channelMenu.menu.implicitWidth, moreButton.height) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More options")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    ChannelMenu {
        id: channelMenu
        manageMode: true
        channel: page.channel
        teamId: page.teamId; teamName: page.teamName
        onGoToChannel: page.goToChannel(page.channelId)
        onOpenInNewWindow: page.openInNewWindow(page.channelId)
        onManageChannel: page.tab = "settings"
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: page.tab === "settings" ? settings.height + 40 : page.tab === "members" ? membersTab.height + 40 : page.tab === "invites" ? invitesTab.height + 40 : analytics.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Settings.
        Column {
            id: settings
            visible: page.tab === "settings"
            x: 48; y: 20; width: flick.width - 96
            Section {
                id: details
                label: qsTr("Channel details"); hint: qsTr("Edit channel name, description, and layout")
                open: page.detailsOpen
                onToggled: page.detailsOpen = !page.detailsOpen
                Item {
                    width: parent.width; height: 144.4
                    Text {
                        x: 38; y: 0
                        width: Math.min(380, parent.width - 38); elide: Text.ElideRight
                        text: page.channel.general ? qsTr("General") : (page.channel.name || "")
                        font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold
                        lineHeight: 36; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Rectangle {
                        x: 38; y: 66
                        width: layoutText.implicitWidth + 16; height: 25.3; radius: 4
                        color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                        border.color: theme.stroke; border.width: 0.67
                        Text { id: layoutText; anchors.centerIn: parent; text: page.channel.layout === "Conversational" ? qsTr("Threads") : qsTr("Posts"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    }
                    Rectangle {
                        id: hcFill1
                        x: 38; y: 106.3
                        width: 96; height: 31.3; radius: 4
                        color: editHover.hovered ? theme.brandHover : theme.brandFill
                        Text { anchors.centerIn: parent; text: qsTr("Edit"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, "white") }
                        HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: editDialog.start(page.channel) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Edit channel name, description, and layout")
                    }
                }
            }
            Section {
                id: moderation
                label: qsTr("Moderation"); hint: qsTr("Set channel moderation preferences")
                open: page.moderationOpen
                onToggled: page.moderationOpen = !page.moderationOpen
                ChannelModeration {
                    id: channelModeration
                    visible: !page.general
                    teamId: page.teamId
                    channelId: page.general ? "" : page.channelId
                    channelType: ["Standard", "Private", "Shared"][page.channel.channel_type || 0] || "Standard"
                    canChange: !!(page.team && page.team.owner)
                    myMri: backend.userMri || ""
                    myPresence: page.myPresence
                }
                Item {
                    visible: page.general
                    width: parent.width; height: 148.7
                    Text { x: 38; y: 2; text: qsTr("General Channel:"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Column {
                        x: 38; y: 24
                        spacing: -4
                        Radio { value: 0; label: qsTr("Anyone can post messages") }
                        Radio { value: 1; label: qsTr("Anyone can post; show alert that posting will notify everyone (recommended for large teams)") }
                        Radio { value: 2; label: qsTr("Only owners can post messages") }
                    }
                }
            }
        }

        // Members (Teams, measured on winpc 2026-11-20): the action 20 in
        // ("+ Add member" for a private channel; a shared one's "Share with
        // people" split button whose chevron offers Share with people, Share
        // with a team, Share with a team you own), "Search members" at the
        // right; then Owners (n), Members (n) ("Members and guests" in a
        // private channel) and, shared, Teams (n), each a section with
        // Name / Title / Location / Tags / Channel role columns.
        Column {
            id: membersTab
            visible: page.tab === "members"
            x: 20; y: 20; width: flick.width - 40
            spacing: 12
            Item {
                width: parent.width; height: 32
                Rectangle {
                    id: shareAction
                    height: 32; radius: 4
                    width: actionRow.implicitWidth + 16
                    color: actHover.hovered ? theme.hover : "transparent"
                    Row {
                        id: actionRow
                        x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: page.channelType === 2 ? "share-20" : "add-20"; color: theme.onFill(shareAction, theme.text) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: page.channelType === 2 ? qsTr("Share with people") : qsTr("Add member"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(shareAction, theme.text) }
                    }
                    HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.share("people") }
                    Accessible.role: Accessible.Button
                    Accessible.name: page.channelType === 2 ? qsTr("Share with people") : qsTr("Add member")
                }
                Rectangle {
                    id: shareChevron
                    visible: page.channelType === 2
                    x: shareAction.width; width: 24; height: 32; radius: 4
                    color: chevHover.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 16; name: "chevron-down-20"; color: theme.onFill(shareChevron, theme.textStrong) }
                    HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { shareMenu.parent = shareAction; shareMenu.x = 0; shareMenu.y = shareAction.height + 4; shareMenu.open() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("More ways to share")
                }
                MenuPopup {
                    id: shareMenu
                    items: [{ key: "people", label: qsTr("Share with people") }, { key: "team", label: qsTr("Share with a team") }, { key: "own", label: qsTr("Share with a team you own") }]
                    onPicked: i => page.share(items[i].key)
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 280; height: 32; radius: 4
                    color: theme.input; border.width: 0.67; border.color: memberSearch.activeFocus ? theme.brand : theme.stroke
                    TextInput {
                        id: memberSearch
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        Text { visible: !memberSearch.text; text: qsTr("Search members"); font: memberSearch.font; color: theme.textSecondary }
                        Accessible.name: qsTr("Search members")
                    }
                }
            }
            Repeater {
                model: {
                    const q = memberSearch.text.trim().toLowerCase()
                    const m = page.members.filter(x => !q || (x.name || "").toLowerCase().indexOf(q) >= 0)
                    const out = [[qsTr("Owners (%1)").arg(m.filter(x => x.owner).length), m.filter(x => x.owner)],
                                 [(page.channelType === 2 ? qsTr("Members (%1)") : qsTr("Members and guests (%1)")).arg(m.filter(x => !x.owner).length), m.filter(x => !x.owner)]]
                    if (page.channelType === 2) out.push([qsTr("Teams (%1)").arg(page.sharedTeams.length), page.sharedTeams.map(t => ({ name: t.displayName, team: true, host: t.isHostTeam, count: t.memberCount }))])
                    return out
                }
                Column {
                    id: memSec
                    required property var modelData
                    required property int index
                    property bool open: index === 0
                    width: membersTab.width
                    Rectangle {
                        width: parent.width; height: 44; radius: 4
                        color: msHover.hovered ? theme.hover : "transparent"
                        FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: memSec.open ? "chevron-down-20" : "chevron-right-20"; size: 20; color: theme.text }
                        Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: memSec.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        HoverHandler { id: msHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: memSec.open = !memSec.open }
                        Accessible.role: Accessible.Button
                        Accessible.name: memSec.modelData[0]
                    }
                    Item {
                        visible: memSec.open && memSec.modelData[1].length > 0
                        width: parent.width; height: visible ? 40 : 0
                        Repeater {
                            model: [[qsTr("Name"), 0], [qsTr("Title"), 0.18], [qsTr("Location"), 0.36], [qsTr("Tags"), 0.54], [qsTr("Channel role"), 0.72]]
                            Text { required property var modelData; x: 22 + (memSec.width - 44) * modelData[1]; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                        }
                    }
                    Repeater {
                        model: memSec.open ? memSec.modelData[1] : []
                        Item {
                            id: mrow
                            required property var modelData
                            width: memSec.width; height: 52
                            Avatar { x: 22; anchors.verticalCenter: parent.verticalCenter; size: 32; name: mrow.modelData.name || ""; photoId: mrow.modelData.team ? "" : (mrow.modelData.mri || ""); square: !!mrow.modelData.team; squareRadius: 4 }
                            Text { x: 64; anchors.verticalCenter: parent.verticalCenter; width: (memSec.width - 44) * 0.18 + 22 - 64 + 120; elide: Text.ElideRight; text: mrow.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            Text {
                                x: 22 + (memSec.width - 44) * 0.72; anchors.verticalCenter: parent.verticalCenter
                                text: mrow.modelData.team ? (mrow.modelData.host ? qsTr("Host team") : qsTr("Member team")) : mrow.modelData.owner ? qsTr("Owner") : mrow.modelData.guest ? qsTr("Guest") : qsTr("Member")
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                            Rectangle { anchors.bottom: parent.bottom; x: 16; width: parent.width - 32; height: 0.67; color: theme.divider }
                        }
                    }
                }
            }
        }
        // Invites and requests (a shared channel): "Sent invites (n team(s))"
        // with each invited team owner and when the invite expires.
        Column {
            id: invitesTab
            visible: page.tab === "invites"
            x: 20; y: 20; width: flick.width - 40
            Item {
                width: parent.width; height: 44
                FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.text }
                Text {
                    x: 38; anchors.verticalCenter: parent.verticalCenter
                    text: page.sentInvites.length === 1 ? qsTr("Sent invites (1 team)") : qsTr("Sent invites (%1 teams)").arg(page.sentInvites.length)
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
            }
            Item {
                visible: page.sentInvites.length > 0
                width: parent.width; height: 40
                Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                Text { x: 22 + (parent.width - 44) * 0.34; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Expires in"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
            }
            Repeater {
                model: page.sentInvites
                Item {
                    id: irow
                    required property var modelData
                    readonly property var person: page.names[modelData.inviteeMri || ""] ? ({ name: page.names[modelData.inviteeMri] }) : null
                    width: invitesTab.width; height: 52
                    Avatar { x: 22; anchors.verticalCenter: parent.verticalCenter; size: 32; name: irow.person ? irow.person.name : ""; photoId: irow.modelData.inviteeMri || "" }
                    Text { x: 64; anchors.verticalCenter: parent.verticalCenter; text: irow.person ? irow.person.name : (irow.modelData.inviteeMri || ""); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text {
                        x: 22 + (parent.width - 44) * 0.34 + 16; anchors.verticalCenter: parent.verticalCenter
                        text: { const d = Math.ceil(((Date.parse(irow.modelData.systemExpirationDateTime) || Date.now()) - Date.now()) / 86400000); return d > 0 ? qsTr("%1 days").arg(d) : "" }
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    // An invite the team owner accepted waits for this
                    // channel's owner (Teams' approve / deny).
                    Row {
                        visible: irow.modelData.state === "Pending"
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: [["deny", qsTr("Deny")], ["approve", qsTr("Approve")]]
                            Rectangle {
                                id: ab
                                required property var modelData
                                width: 96; height: 31.3; radius: 4
                                color: modelData[0] === "approve" ? (abh.hovered ? theme.brandHover : theme.brandFill) : (abh.hovered ? theme.menuHover : theme.surface)
                                border.color: modelData[0] === "approve" ? "transparent" : theme.stroke; border.width: 0.67
                                Text { anchors.centerIn: parent; text: ab.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(ab, ab.modelData[0] === "approve" ? theme.textOnBrand : theme.text) }
                                HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: backend.channelAction("channel-invitation", page.teamId, page.channelId, JSON.stringify({ id: irow.modelData.id, action: ab.modelData[0] })) }
                                Accessible.role: Accessible.Button
                                Accessible.name: ab.modelData[1]
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; x: 16; width: parent.width - 32; height: 0.67; color: theme.divider }
                }
            }
        }

        AnalyticsView {
            id: analytics
            visible: page.tab === "analytics"
            width: flick.width
            teamId: page.teamId
            channelId: page.tab === "analytics" ? page.channelId : ""
            channels: page.team ? page.team.channels || [] : []
            onPickChannel: id => page.manageChannel(id)
            onTeamAnalytics: page.teamAnalytics(page.teamId)
        }
    }
    property bool detailsOpen: true
    property bool moderationOpen: true

    // A section: its header row and, open, what it holds; a line after it.
    component Section: Column {
        id: sec
        property string label
        property string hint
        property bool open: true
        default property alias body: bodyCol.data
        signal toggled()
        width: parent ? parent.width : 0
        Rectangle {
            id: hcFill2
            width: parent.width; height: 44; radius: 4
            color: secHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: sec.open ? "chevron-down-20" : "chevron-right-20"; size: 20; color: theme.onFill(hcFill2, theme.text) }
            Text { id: secLabel; x: 38; anchors.verticalCenter: parent.verticalCenter; text: sec.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
            Text { x: secLabel.x + secLabel.implicitWidth + 30; anchors.verticalCenter: parent.verticalCenter; text: sec.hint; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill2, theme.textSecondary) }
            HoverHandler { id: secHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sec.toggled() }
            Accessible.role: Accessible.Button
            Accessible.name: sec.label
        }
        Column { id: bodyCol; visible: sec.open; width: parent.width }
        Item { width: 1; height: sec.open ? 13 : 0 }
        Rectangle { width: parent.width; height: 1; color: theme.divider }
    }
    component Radio: Item {
        id: rb
        property int value
        property string label
        readonly property bool chosen: page.generalSetting === value
        width: 32 + 4 + Math.min(500, rbText.implicitWidth) + 8; height: rbText.height + 16
        Rectangle {
            x: 8; y: 10; width: 16; height: 16; radius: 8
            color: "transparent"
            border.color: rb.chosen ? theme.checkedFill : theme.textSecondary; border.width: 0.67
            Rectangle { visible: rb.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brandFill }
        }
        Text {
            id: rbText
            x: 36; y: 8
            width: Math.min(496, implicitWidth); wrapMode: Text.Wrap
            text: rb.label
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: rb.chosen ? theme.text : theme.textSecondary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: page.generalSetting >= 0 && !page.savingModeration
            onTapped: {
                if (rb.chosen) return
                page.savingModeration = true
                page.generalSetting = rb.value
                backend.channelAction("moderation", page.teamId, page.channelId, String(rb.value))
            }
        }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: chosen
        Accessible.name: label
    }

    ChannelEditDialog { id: editDialog; teamId: page.teamId }
    // Names for invited people (the directory, as the rest of OST knows
    // them).
    readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    onSentInvitesChanged: if (sentInvites.length) backend.resolveNames(JSON.stringify(sentInvites.map(i => i.inviteeMri).filter(m => !!m)))
    // Share with people (or, private, Add member), Share with a team, Share
    // with a team you own.
    function share(kind) {
        const thread = page.team ? page.team.thread_id || "" : ""
        if (kind === "people") { shareMembers.shareMode = page.channelType === 2; shareMembers.startChannel(page.teamId, thread, page.teamName, page.channelId, page.channel.name || "") }
        else shareDialog.start(kind, page.channel, page.teamId, thread)
    }
    AddMembersDialog { id: shareMembers; parent: Overlay.overlay; onFinished: page.loadMembers() }
    ShareChannelDialog { id: shareDialog; sharedTeamIds: page.sharedTeams.map(t => t.groupId) }

    // Test hooks.
    function analyticsForTest() { return analytics }
    function menuForTest() { return channelMenu }
    function moderationForTest() { return channelModeration }
}
