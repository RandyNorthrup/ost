import QtQuick
import QtQuick.Controls.Basic

// Quick views > Drafts, as Teams desktop lays it out (measured at 1x): a
// 380 px white list of chats with unsent text, and a hint beside it.
Rectangle {
    id: root
    /// [{id, name, peerMri, text, time}], newest first.
    property var drafts: []
    signal openDraft(string id, string name)
    color: theme.surface

    Rectangle {
        id: pane
        width: 380; height: parent.height
        color: theme.surface
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }

        Text {
            x: 32; y: 19
            text: "Drafts"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: 32; y: 69
            spacing: 4
            Repeater {
                model: ["Channels", "Chats"]
                delegate: Rectangle {
                    required property string modelData
                    height: 24; radius: 12
                    width: chipText.implicitWidth + 16
                    color: "transparent"
                    border.color: theme.stroke
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

        ListView {
            id: list
            y: 106
            width: parent.width - 1; height: parent.height - y
            clip: true
            model: root.drafts
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: item
                required property var modelData
                width: list.width; height: 60
                Rectangle {
                    x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
                    color: itemHover.hovered ? theme.pane : "transparent"
                }
                Avatar {
                    x: 32; y: 16
                    size: 32; name: item.modelData.name || "?"
                    photoId: item.modelData.peerMri || ""
                }
                Text {
                    x: 80; y: 13; width: parent.width - 80 - 56
                    text: item.modelData.name || "Chat"
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.text
                }
                Text {
                    x: 80; y: 37; width: parent.width - 80 - 56
                    text: "You: " + item.modelData.text.replace(/\s+/g, " ")
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base; font.italic: true
                    color: theme.text
                }
                HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openDraft(item.modelData.id, item.modelData.name) }
                Accessible.role: Accessible.Button
                Accessible.name: "Draft to " + item.modelData.name
            }
            Text {
                visible: root.drafts.length === 0
                x: 32; y: 8
                text: "No drafts"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }
        }
    }

    Column {
        anchors.centerIn: hint
        spacing: 16
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "drafts-20"; size: 64; color: theme.brand }
        Text {
            text: "Select a draft to edit and send."
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            color: theme.text
        }
    }
    Item { id: hint; anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom } }
}
