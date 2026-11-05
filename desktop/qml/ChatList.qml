import QtQuick
import QtQuick.Controls.Basic

// The Chat pane, laid out as Teams desktop's (measured from its DOM at 1x):
// header, filter chips, then Quick views, Favorites, Chats and Teams and
// channels as collapsible groups of 32 px rows.
Rectangle {
    id: root
    property var chats: []
    property var teams: []
    property string currentId
    /// Chat ids with an unsent draft (Quick views > Drafts).
    property var draftIds: []
    property bool draftsOpen: false
    signal chatSelected(string id, string name)
    signal newChat()
    signal openDrafts()
    color: theme.pane
    width: theme.listWidth

    readonly property var favorites: chats.filter(c => c.favorite)
        .sort((a, b) => (a.favoriteRank ?? 1e9) - (b.favoriteRank ?? 1e9))
    readonly property var others: chats.filter(c => !c.favorite)
    property bool quickOpen: true
    property bool favOpen: true
    property bool chatsOpen: true
    property bool teamsOpen: true

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: "#EFEFEF" }

    component HeaderButton: Rectangle {
        id: hb
        property alias icon: hbIcon.name
        property int iconSize: 20
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: hbHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        FluentIcon { id: hbIcon; anchors.centerIn: parent; size: hb.iconSize; color: "#424242" }
    }

    // Header: "Chat", then more / filter / new message (with its menu).
    Item {
        id: header
        width: parent.width; height: 61
        Text {
            x: 32; y: 19
            text: "Chat"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        HeaderButton { x: 194; y: 15; icon: "more-20"; Accessible.name: "More list options" }
        HeaderButton { x: 226; y: 15; icon: "search-20"; Accessible.name: "Show filter text box" }
        HeaderButton {
            x: 258; y: 14; width: 26; icon: "compose-20"
            Accessible.name: "New message"
            onClicked: root.newChat()
        }
        HeaderButton { x: 284; y: 14; width: 20; icon: "chevron-down-12"; iconSize: 12; Accessible.name: "New items" }
    }

    // Filter chips: 24 px pills with a 1 px neutral border, 4 px apart.
    Row {
        id: chips
        x: 32; y: 69
        spacing: 4
        Repeater {
            model: ["Unread", "Channels", "Chats"]
            delegate: Rectangle {
                required property string modelData
                height: 24; radius: 12
                width: chipText.implicitWidth + 16
                color: chipHover.hovered ? "#EBEBEB" : "transparent"
                border.color: chipHover.hovered ? "#C7C7C7" : theme.stroke
                HoverHandler { id: chipHover }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData
                    font.family: theme.font; font.pixelSize: theme.small
                    color: "#424242"
                }
            }
        }
    }
    HeaderButton { x: 282; y: 65; width: 24; height: 24; icon: "chevron-down-12"; iconSize: 12; Accessible.name: "More filters" }

    ListView {
        id: list
        y: 106
        width: parent.width - 1
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        header: Column {
            width: list.width
            // Quick views > Drafts
            SectionHeader { label: "Quick views"; open: root.quickOpen; onToggled: root.quickOpen = !root.quickOpen }
            Item { width: 1; height: root.quickOpen ? 4 : 0 }
            ListRow {
                visible: root.quickOpen
                label: "Drafts"; icon: "drafts-20"
                selected: root.draftsOpen
                onClicked: root.openDrafts()
            }
            // A hairline 12 px below, then the next group 4.6 px after it.
            Item { width: 1; height: 12 }
            Rectangle { x: 16; width: list.width - 32; height: 1; color: theme.divider }
            Item { width: 1; height: 4 }
            SectionHeader { label: "Favorites"; open: root.favOpen; onToggled: root.favOpen = !root.favOpen }
            Item { width: 1; height: root.favOpen && root.favorites.length > 0 ? 4 : 0 }
            Repeater {
                model: root.favOpen ? root.favorites : []
                ChatRow { required property var modelData; chat: modelData }
            }
            Item { width: 1; height: 8 }
            SectionHeader { label: "Chats"; open: root.chatsOpen; onToggled: root.chatsOpen = !root.chatsOpen }
            Item { width: 1; height: root.chatsOpen && root.others.length > 0 ? 4 : 0 }
        }
        model: root.chatsOpen ? root.others : []
        delegate: ChatRow { required property var modelData; chat: modelData }
        footer: Column {
            width: list.width
            visible: root.teams.length > 0
            Item { width: 1; height: 8 }
            SectionHeader { label: "Teams and channels"; open: root.teamsOpen; onToggled: root.teamsOpen = !root.teamsOpen }
            Item { width: 1; height: root.teamsOpen ? 4 : 0 }
            Repeater {
                model: root.teamsOpen ? root.teams : []
                Column {
                    id: team
                    required property var modelData
                    property bool open: true
                    width: list.width
                    // Team row: chevron, team picture, name.
                    Item {
                        width: list.width; height: 32
                        Rectangle {
                            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                            color: teamHover.hovered ? "#EBEBEB" : "transparent"
                        }
                        FluentIcon {
                            x: 18; y: 10
                            name: team.open ? "chevron-down-12" : "chevron-right-12"; size: 12
                            color: theme.textSecondary
                        }
                        Avatar {
                            x: 32; y: 6
                            size: 20; square: true
                            name: team.modelData.name
                            initialsText: team.modelData.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                            photoId: "team:" + team.modelData.id
                        }
                        Text {
                            x: 64; width: parent.width - 64 - 24; y: 6
                            text: team.modelData.name
                            elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.textSecondary
                        }
                        HoverHandler { id: teamHover }
                        TapHandler { onTapped: team.open = !team.open }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Team " + team.modelData.name + (team.open ? ", expanded" : ", collapsed")
                    }
                    Repeater {
                        model: team.open ? team.modelData.channels : []
                        Item {
                            id: channel
                            required property var modelData
                            readonly property bool selected: modelData.id === root.currentId
                            width: list.width; height: 28
                            Rectangle {
                                x: 16; width: parent.width - 32; height: 28; radius: theme.radius
                                color: channel.selected ? theme.surface : (chHover.hovered ? "#EBEBEB" : "transparent")
                            }
                            Text {
                                x: 64; width: parent.width - 64 - 24; y: 4
                                text: channel.modelData.name
                                elide: Text.ElideRight
                                font.family: theme.font; font.pixelSize: theme.base
                                color: channel.selected ? theme.text : theme.textSecondary
                            }
                            HoverHandler { id: chHover }
                            TapHandler { onTapped: root.chatSelected(channel.modelData.id, channel.modelData.name) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Channel " + channel.modelData.name + " in " + team.modelData.name
                        }
                    }
                }
            }
            Item {
                visible: root.teamsOpen
                width: list.width; height: 28
                Text {
                    x: 31; y: 4
                    text: "See all your teams"
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.brand
                }
            }
            Item { width: 1; height: 8 }
        }
    }

    // One chat in a group: picture with presence, name, unread dot.
    component ChatRow: Item {
        id: row
        property var chat
        readonly property bool selected: !root.draftsOpen && chat.id === root.currentId
        readonly property bool unread: chat.unread === true && !selected
        width: list.width; height: 32
        Rectangle {
            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
            color: row.selected ? theme.surface : (hover.hovered ? "#EBEBEB" : "transparent")
        }
        Avatar {
            x: 32; y: 6
            size: 20; name: row.chat.name
            photoId: row.chat.peerMri || ""
            presence: row.chat.presence || ""
        }
        Text {
            x: 64; width: parent.width - 64 - 40; y: 6
            text: row.chat.name
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            // Teams: bold only when unread; the open chat is just darker.
            font.weight: row.unread ? Font.DemiBold : Font.Normal
            color: row.selected || row.unread ? theme.text : theme.textSecondary
        }
        // Unread: bold name plus a brand dot, as in Teams.
        Rectangle {
            visible: row.unread
            width: 8; height: 8; radius: 4
            x: parent.width - 16 - 8 - 12
            anchors.verticalCenter: parent.verticalCenter
            color: theme.brand
        }
        HoverHandler { id: hover }
        TapHandler { onTapped: root.chatSelected(row.chat.id, row.chat.name) }
        Accessible.role: Accessible.Button
        Accessible.name: row.chat.name + (row.unread ? ", unread" : "")
    }

    // A row with an icon instead of a picture (Quick views).
    component ListRow: Item {
        id: lr
        property string label
        property string icon
        property bool selected: false
        signal clicked()
        width: list.width; height: 32
        Rectangle {
            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
            color: lr.selected ? theme.surface : (lrHover.hovered ? "#EBEBEB" : "transparent")
        }
        FluentIcon { x: 32; y: 6; name: lr.icon; size: 20; color: theme.textSecondary }
        Text {
            x: 64; y: 6
            text: lr.label
            font.family: theme.font; font.pixelSize: theme.base
            color: lr.selected ? theme.text : theme.textSecondary
        }
        HoverHandler { id: lrHover }
        TapHandler { onTapped: lr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: lr.label
    }

    // Group header: 12 px chevron and label, 28 px tall.
    component SectionHeader: Item {
        id: sh
        property string label
        property bool open: true
        signal toggled()
        width: list.width; height: 28
        FluentIcon {
            x: 18; y: 8
            name: sh.open ? "chevron-down-12" : "chevron-right-12"; size: 12
            color: theme.textSecondary
        }
        Text {
            x: 32; y: 4
            text: sh.label
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
        TapHandler { onTapped: sh.toggled() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.Button
        Accessible.name: sh.label + (sh.open ? ", expanded" : ", collapsed")
    }
}
