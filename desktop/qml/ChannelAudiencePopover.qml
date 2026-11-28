import QtQuick
import QtQuick.Controls.Basic

// The channel header's people button popover, as Teams has it (channel
// audience, data-tid channel-agents-list; measured in Teams on the web as
// OST Test 2, OST Test Team ▸ OST test channel 2, 2026-11-27): 255 wide,
// white, radius 4, padding 16.
// - "People" (12/16 semibold #616161) 14 down, 19 in; six people's 28 px
//   pictures with presence, 9.5 apart, 46 down: the channel's recent
//   contributors, then its members (api::channels::channel_people); "See
//   all" (14/20 brand) under them, which opens Manage team ▸ Members.
// - "Agents and bots (n)" and a 45 tall row per agent (its 32 px icon at
//   19, the name 14/20 at 61): the team's installed apps with a bot that
//   isn't notification-only, or agents (api::store_content::channel_agents).
// - "Teams (1)": the team's picture, name (14/20), "{n} members" (10/14
//   #616161), a 1 x 10 line and the home glyph (12).
// - A line (17 in, 221 wide), then Add agents (32 tall, the bot-add glyph
//   at 26, its text at 61), which opens the Store's Add agents.
Popup {
    id: root
    property string teamId: ""
    property string teamThread: ""
    property string channelId: ""
    property string teamName: ""
    property int teamPeople: 0
    property var people: []
    property var bots: []
    property bool loaded: false
    readonly property var presences: { try { return JSON.parse(backend.peoplePresenceJson || "{}") } catch (e) { return {} } }
    signal seeAll()
    signal addAgents()
    signal openBot(string appId)
    width: 255
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    /// A private or shared channel lists its own roster after its
    /// contributors (a standard one the team's).
    readonly property bool ownRoster: {
        for (const t of JSON.parse(backend.teamsJson || "[]")) {
            const c = (t.channels || []).find(c => c.id === root.channelId)
            if (c) return (c.channel_type || 0) > 0
        }
        return false
    }
    function load() {
        loaded = false
        backend.channelAction("channel-audience", teamId, channelId, JSON.stringify({ own: ownRoster }))
    }
    onOpened: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            let r = {}
            try { r = JSON.parse(backend.channelActionResult || "{}") } catch (e) { return }
            if (r.op !== "channel-audience" || r.channel !== root.channelId) return
            root.loaded = true
            root.people = r.ok && r.data ? (r.data.people || []) : []
            root.bots = r.ok && r.data ? (r.data.bots || []) : []
            const shown = root.people.slice(0, 6).map(p => p.mri).filter(m => !!m)
            if (shown.length) backend.loadPresences(JSON.stringify(shown))
        }
    }

    component Heading: Text {
        x: 19; height: 16
        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.textSecondary
    }
    component Row45: Rectangle {
        id: r45
        property alias hovered: r45Hover.hovered
        signal tapped()
        x: 7; width: 242; height: 45; radius: 4
        color: r45Hover.hovered ? theme.menuHover : "transparent"
        HoverHandler { id: r45Hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: r45.tapped() }
    }

    contentItem: Item {
        implicitHeight: addAgentsRow.y + addAgentsRow.height + 3
        Heading { id: peopleHead; y: 14; text: qsTr("People") }
        Row {
            id: faces
            x: 19; y: 46; spacing: 9.5
            Repeater {
                model: root.people.slice(0, 6)
                Avatar {
                    required property var modelData
                    size: 28; name: modelData.name || "?"; photoId: modelData.mri || ""
                    presence: root.presences[modelData.mri || ""] || ""
                    opensProfile: true
                }
            }
        }
        Text {
            id: seeAllLink
            x: 20; y: 95; height: 20
            text: qsTr("See all")
            font.family: theme.font; font.pixelSize: 14
            color: seeAllHover.hovered ? theme.brandHover : theme.brand
            font.underline: seeAllHover.hovered
            HoverHandler { id: seeAllHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.seeAll() } }
            Accessible.role: Accessible.Button
            Accessible.name: text
        }
        Heading { id: botsHead; y: 125; text: qsTr("Agents and bots (%1)").arg(root.bots.length) }
        Column {
            id: botRows
            y: 145
            Repeater {
                model: root.bots
                Row45 {
                    id: botRow
                    required property var modelData
                    onTapped: { root.close(); root.openBot(modelData.id) }
                    Image { x: 12; y: 7; width: 32; height: 32; sourceSize: Qt.size(64, 64); source: botRow.modelData.icon || ""; fillMode: Image.PreserveAspectFit }
                    Text { x: 54; y: 13; width: 176; elide: Text.ElideRight; text: botRow.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.name || ""
                }
            }
        }
        Heading { id: teamsHead; y: botRows.y + botRows.height + 4; text: qsTr("Teams (%1)").arg(1) }
        Row45 {
            id: teamRow
            y: teamsHead.y + 20
            onTapped: { root.close(); root.seeAll() }
            Avatar { x: 12; y: 7; size: 32; square: true; squareRadius: 4; name: root.teamName; photoId: root.teamId ? "team:" + root.teamId : "" }
            Text { x: 54; y: 7; width: 176; elide: Text.ElideRight; text: root.teamName; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
            Row {
                x: 54; y: 25; spacing: 5
                Text { id: membersText; text: qsTr("%n members", "", root.teamPeople); font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                Rectangle { anchors.verticalCenter: membersText.verticalCenter; width: 1; height: 10; color: theme.divider }
                FluentIcon { anchors.verticalCenter: membersText.verticalCenter; name: "home-20"; size: 12; color: theme.textSecondary }
            }
            Accessible.role: Accessible.MenuItem
            Accessible.name: root.teamName
        }
        Rectangle { id: line; x: 17; y: teamRow.y + teamRow.height + 7; width: 221; height: 1; color: theme.divider }
        Rectangle {
            id: addAgentsRow
            x: 3; y: line.y + 6; width: 249; height: 32; radius: 4
            color: addHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 23; anchors.verticalCenter: parent.verticalCenter; name: "bot-add-20"; size: 16; color: theme.onFill(addAgentsRow, theme.textStrong) }
            Text { x: 58; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add agents"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(addAgentsRow, theme.textStrong) }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.addAgents() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add agents")
        }
    }
}
