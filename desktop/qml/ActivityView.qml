import QtQuick
import QtQuick.Controls.Basic

// Activity (Ctrl+1), laid out as Teams desktop's (measured at 1x): a
// 379 px list of what happened to you; the chosen item's chat opens
// beside it (Main places the conversation there).
Rectangle {
    id: root
    /// ActivityItem list, newest first.
    property var items: []
    property string selectedId: ""
    signal openItem(var item)
    signal callBack(var item)
    signal chatWith(var item)
    color: theme.pane
    width: 379

    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#EFEFEF" }

    Text {
        x: 20; y: 17
        text: "Activity"
        font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
        color: theme.text
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 14
        spacing: 0
        Repeater {
            model: [{ icon: "more-20", label: "More options" }, { icon: "search-20", label: "Filter" }]
            Rectangle {
                required property var modelData
                width: 32; height: 32; radius: theme.radius
                color: hh.hovered ? theme.hover : "transparent"
                HoverHandler { id: hh }
                FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: "#424242" }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
            }
        }
    }
    Row {
        x: 16; y: 78
        spacing: 8
        Repeater {
            model: ["Unread", "@Mentions", "Tag mentions"]
            delegate: Rectangle {
                required property string modelData
                height: 24; radius: 12
                width: chip.implicitWidth + 16
                color: "transparent"
                border.color: theme.stroke
                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: modelData
                    font.family: theme.font; font.pixelSize: theme.small
                    color: "#424242"
                }
            }
        }
    }

    // Relative time as Teams shows it in the feed: time today, M/d before.
    function when(t) {
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        return Qt.formatDate(d, "M/d")
    }

    ListView {
        id: list
        y: 111
        width: parent.width - 1; height: parent.height - y
        clip: true
        spacing: 0
        model: root.items
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: it
            required property var modelData
            readonly property bool selected: modelData.id === root.selectedId
            readonly property bool call: modelData.kind === "missedCall"
            width: list.width
            height: Math.max(64, body.y + body.height + (call ? 34 : 0) + 10)
            Rectangle {
                x: 4; width: 358; height: parent.height; radius: theme.radius
                color: it.selected ? theme.surface : (hov.hovered ? "#EBEBEB" : "transparent")
            }
            // Unread: a small dot left of the picture.
            Rectangle {
                visible: it.modelData.unread
                x: 10; y: 24; width: 5; height: 5; radius: 2.5
                color: theme.text
            }
            // People show their picture; apps (team owners, bots) an app tile.
            readonly property bool fromPerson: (modelData.actor_mri || "").startsWith("8:orgid:")
            Avatar {
                visible: it.fromPerson
                x: 20.7; y: 10.7
                size: 32; name: it.modelData.actor_name || "?"
                photoId: it.fromPerson ? it.modelData.actor_mri : ""
            }
            Rectangle {
                visible: !it.fromPerson
                x: 20.7; y: 10.7; width: 32; height: 32; radius: theme.radius
                color: theme.brand
                FluentIcon { anchors.centerIn: parent; name: "apps-20-filled"; size: 20; color: "white" }
            }
            // What happened, as a badge on the picture: the reaction itself,
            // or a coloured icon.
            Rectangle {
                x: 20.7 + 32 - 14; y: 10.7 + 32 - 14
                width: 18; height: 18; radius: 9
                color: theme.surface
                Text {
                    visible: it.modelData.emoji.length > 0
                    anchors.centerIn: parent
                    text: it.modelData.emoji
                    font.pixelSize: 12
                }
                FluentIcon {
                    visible: it.modelData.emoji.length === 0
                    anchors.centerIn: parent; size: 14
                    name: it.modelData.kind === "missedCall" ? "call-missed-16-filled"
                        : it.modelData.kind === "voicemail" ? "voicemail-16-filled"
                        : it.modelData.kind === "addedToTeam" ? "people-team-16-filled"
                        : "chat-20"
                    color: it.modelData.kind === "missedCall" ? "#D13438"
                        : it.modelData.kind === "voicemail" ? "#CA5010" : theme.brand
                }
            }
            Column {
                id: body
                x: 72.7; y: 6.7
                width: 273
                Text {
                    width: 201
                    text: it.modelData.title
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: theme.base
                    font.weight: it.modelData.unread ? Font.Bold : Font.Normal
                    color: theme.text
                }
                Text {
                    visible: text.length > 0
                    width: parent.width
                    text: it.modelData.preview
                    elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
                Text {
                    visible: text.length > 0
                    width: parent.width
                    text: it.modelData.context
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.small
                    color: "#424242"
                }
            }
            Text {
                x: 345.5 - implicitWidth; y: 6.7
                text: root.when(it.modelData.time)
                font.family: theme.font; font.pixelSize: theme.small
                color: "#424242"
            }
            // Missed calls: call back or chat, as in Teams.
            Row {
                visible: it.call
                x: 72.7; y: body.y + body.height + 8
                spacing: 8
                Repeater {
                    model: ["Call", "Chat"]
                    Rectangle {
                        required property string modelData
                        width: 65; height: 24; radius: theme.radius
                        color: bh.hovered ? theme.pane : theme.surface
                        border.color: theme.stroke
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: modelData === "Call" ? root.callBack(it.modelData) : root.chatWith(it.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                    }
                }
            }
            HoverHandler { id: hov }
            TapHandler { onTapped: root.openItem(it.modelData) }
            Accessible.role: Accessible.ListItem
            Accessible.name: it.modelData.title
        }
        Text {
            visible: root.items.length === 0
            x: 20; y: 8
            text: "Nothing new yet"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
    }
}
