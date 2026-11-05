import QtQuick
import QtQuick.Controls.Basic

// The Chat pane: header, filter chips, collapsible sections, chat rows.
Rectangle {
    id: root
    property var chats: []
    property var teams: []
    property string currentId
    signal chatSelected(string id, string name)
    signal newChat()
    color: theme.pane
    width: theme.listWidth

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: "#EFEFEF" }

    // Header
    Item {
        id: header
        width: parent.width; height: theme.headerHeight
        Text {
            x: 32; anchors.verticalCenter: parent.verticalCenter
            text: "Chat"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            FluentIcon { name: "more-20"; size: 20 }
            FluentIcon { name: "search-20"; size: 20 }
            FluentIcon {
                name: "compose-20"; size: 20
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.newChat() }
                Accessible.role: Accessible.Button
                Accessible.name: "New chat"
            }
            FluentIcon { name: "chevron-down-12"; size: 12; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // Filter chips
    Row {
        id: chips
        x: 32; y: header.height + 5
        spacing: 4
        Repeater {
            model: ["Unread", "Channels", "Chats"]
            delegate: Rectangle {
                required property string modelData
                height: 24; radius: 12
                width: chipText.implicitWidth + 18
                color: theme.surface
                border.color: theme.stroke
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.text
                }
            }
        }
    }
    Rectangle { y: header.height + 40; width: parent.width - 1; height: 1; color: theme.dividerSoft }

    ListView {
        id: list
        y: header.height + 41
        width: parent.width - 1
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        header: Column {
            width: list.width
            topPadding: 6
            SectionHeader { label: "Favorites" }
            SectionHeader { label: "Chats" }
        }
        model: root.chats
        footer: Column {
            width: list.width
            topPadding: 8
            visible: root.teams.length > 0
            SectionHeader { label: "Teams and channels" }
            Repeater {
                model: root.teams
                Column {
                    id: team
                    required property var modelData
                    property bool open: true
                    width: list.width
                    // Team row: chevron, coloured square initials, name.
                    Item {
                        width: list.width; height: 32
                        Rectangle {
                            x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                            color: teamHover.hovered ? "#EBEBEB" : "transparent"
                        }
                        FluentIcon {
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            name: team.open ? "chevron-down-12" : "chevron-right-12"; size: 12
                        }
                        Rectangle {
                            id: teamAvatar
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 4
                            readonly property var colors: ["#C43E1C", "#0F6CBD", "#107C10", "#8764B8", "#038387", "#CA5010"]
                            color: {
                                let h = 0
                                for (let i = 0; i < team.modelData.name.length; i++) h = (h * 31 + team.modelData.name.charCodeAt(i)) % 997
                                return colors[h % colors.length]
                            }
                            Text {
                                anchors.centerIn: parent
                                text: team.modelData.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                                color: "white"
                                font.family: theme.font; font.pixelSize: 8; font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            x: 64; width: parent.width - 64 - 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: team.modelData.name
                            elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.text
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
                            width: list.width; height: 32
                            Rectangle {
                                x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                                color: channel.selected ? theme.surface : (chHover.hovered ? "#EBEBEB" : "transparent")
                            }
                            Text {
                                x: 64; width: parent.width - 64 - 24
                                anchors.verticalCenter: parent.verticalCenter
                                text: channel.modelData.name
                                elide: Text.ElideRight
                                font.family: theme.font; font.pixelSize: theme.base
                                font.weight: channel.selected ? Font.DemiBold : Font.Normal
                                color: theme.text
                            }
                            HoverHandler { id: chHover }
                            TapHandler { onTapped: root.chatSelected(channel.modelData.id, channel.modelData.name) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Channel " + channel.modelData.name + " in " + team.modelData.name
                        }
                    }
                }
            }
            Text {
                x: 36; height: 32
                verticalAlignment: Text.AlignVCenter
                text: "See all your teams"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.brand
            }
        }
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool selected: modelData.id === root.currentId
            readonly property bool unread: modelData.unread === true && !selected
            width: list.width; height: 32
            Rectangle {
                x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                color: row.selected ? theme.surface : (hover.hovered ? "#EBEBEB" : "transparent")
            }
            Avatar {
                x: 32; anchors.verticalCenter: parent.verticalCenter
                size: 20; name: row.modelData.name
                presence: row.modelData.presence || ""
            }
            Text {
                x: 64; width: parent.width - 64 - 40
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: theme.base
                font.weight: row.selected || row.unread ? Font.DemiBold : Font.Normal
                color: theme.text
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
            TapHandler { onTapped: root.chatSelected(row.modelData.id, row.modelData.name) }
        }
    }

    component SectionHeader: Item {
        property string label
        width: list.width; height: 36
        FluentIcon { x: 18; name: "chevron-down-12"; size: 12; anchors.verticalCenter: parent.verticalCenter }
        Text {
            x: 32; anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
        }
    }
}
