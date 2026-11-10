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
    color: theme.pick("#FFFFFF", "#292929")

    function loadModeration() {
        generalSetting = -1
        if (general) backend.channelAction("moderation-load", teamId, channelId, "")
    }
    onChannelIdChanged: { tab = "settings"; loadModeration(); detailsOpen = true; moderationOpen = true }
    onGeneralChanged: loadModeration()
    Component.onCompleted: loadModeration()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== page.channelId) return
            if (r.op === "moderation-load" && r.ok) page.generalSetting = r.data.general
            else if (r.op === "moderation") {
                page.savingModeration = false
                if (r.ok) page.generalSetting = r.data.general
                else { page.loadModeration(); backend.toast("Something went wrong on our end. Please try again.", "error") }
            }
        }
    }

    // Header.
    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.pick("#FFFFFF", "#292929")
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
            text: page.channel.general ? "General" : (page.channel.name || "")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 24; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: title.x + title.width + 2; y: 2; height: 56.3
            Repeater {
                model: [["settings", "Settings"], ["analytics", "Analytics"]]
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
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: channelMenu.menu.opened ? theme.brand : theme.textStrong }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: channelMenu.show(moreButton, moreButton.width - channelMenu.menu.implicitWidth, moreButton.height) }
            Accessible.role: Accessible.Button
            Accessible.name: "More options"
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
        contentHeight: page.tab === "settings" ? settings.height + 40 : analytics.implicitHeight
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
                label: "Channel details"; hint: "Edit channel name, description, and layout"
                open: page.detailsOpen
                onToggled: page.detailsOpen = !page.detailsOpen
                Item {
                    width: parent.width; height: 144.4
                    Text {
                        x: 38; y: 0
                        width: Math.min(380, parent.width - 38); elide: Text.ElideRight
                        text: page.channel.general ? "General" : (page.channel.name || "")
                        font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold
                        lineHeight: 36; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Rectangle {
                        x: 38; y: 66
                        width: layoutText.implicitWidth + 16; height: 25.3; radius: 4
                        color: theme.pick("#E6E6E6", "#3D3D3D")
                        border.color: theme.stroke; border.width: 0.67
                        Text { id: layoutText; anchors.centerIn: parent; text: page.channel.layout === "Conversational" ? "Threads" : "Posts"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    }
                    Rectangle {
                        x: 38; y: 106.3
                        width: 96; height: 31.3; radius: 4
                        color: editHover.hovered ? theme.brandHover : theme.brandFill
                        Text { anchors.centerIn: parent; text: "Edit"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                        HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: editDialog.start(page.channel) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Edit channel name, description"
                    }
                }
            }
            Section {
                id: moderation
                label: "Moderation"; hint: "Set channel moderation preferences"
                open: page.moderationOpen
                onToggled: page.moderationOpen = !page.moderationOpen
                ChannelModeration {
                    id: channelModeration
                    visible: !page.general
                    teamId: page.teamId
                    channelId: page.general ? "" : page.channelId
                    channelType: page.channel.channel_type || "Standard"
                    canChange: !!(page.team && page.team.owner)
                    myMri: backend.userMri || ""
                    myPresence: page.myPresence
                }
                Item {
                    visible: page.general
                    width: parent.width; height: 148.7
                    Text { x: 38; y: 2; text: "General Channel:"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Column {
                        x: 38; y: 24
                        spacing: -4
                        Radio { value: 0; label: "Anyone can post messages" }
                        Radio { value: 1; label: "Anyone can post; show alert that posting will notify everyone (recommended for large teams)" }
                        Radio { value: 2; label: "Only owners can post messages" }
                    }
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
            width: parent.width; height: 44; radius: 4
            color: secHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: sec.open ? "chevron-down-20" : "chevron-right-20"; size: 20; color: theme.text }
            Text { id: secLabel; x: 38; anchors.verticalCenter: parent.verticalCenter; text: sec.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text { x: secLabel.x + secLabel.implicitWidth + 30; anchors.verticalCenter: parent.verticalCenter; text: sec.hint; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
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
            border.color: rb.chosen ? theme.brandFill : theme.textSecondary; border.width: 0.67
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

    // Test hooks.
    function analyticsForTest() { return analytics }
    function menuForTest() { return channelMenu }
    function moderationForTest() { return channelModeration }
}
