import QtQuick
import QtQuick.Controls.Basic

// The Chat pane: header, filter chips, collapsible sections, chat rows.
Rectangle {
    id: root
    property var chats: []
    property string currentId
    signal chatSelected(string id, string name)
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
            FluentIcon { name: "compose-20"; size: 20 }
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
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool selected: modelData.id === root.currentId
            width: list.width; height: 32
            Rectangle {
                x: 16; width: parent.width - 32; height: 32; radius: theme.radius
                color: row.selected ? theme.surface : (hover.hovered ? "#EBEBEB" : "transparent")
            }
            Avatar { x: 32; anchors.verticalCenter: parent.verticalCenter; size: 20; name: row.modelData.name }
            Text {
                x: 64; width: parent.width - 64 - 40
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: theme.base
                font.weight: row.selected ? Font.DemiBold : Font.Normal
                color: theme.text
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
