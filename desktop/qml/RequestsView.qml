import QtQuick
import QtQuick.Controls.Basic

// Teams free's chat requests beside the chat list (the chat list's
// "Requests" row; measured on Teams 26304 for OST Personal 2 on testpc2,
// 2026-11-28):
// - a 380 px pane: "Requests" (16/22 bold) at 32, 19 and a hairline 60
//   down; one 60 px row per request from 72: the sender's picture (36) at
//   32, their name (14/20, bold while unread) at 80, the time (12/16,
//   NeutralForeground2) 32 from the right, and a 4 px dot 22 in while
//   unread; the open one on a selected fill (16 in, radius 4);
// - until one is picked, the rest of the window shows Teams' picture and
//   "Select a chat request item to accept or block." (16/22 bold) under
//   it; a picked request opens beside the pane as Teams' request
//   (ChatRequestView: "… wants to chat with you", Block and Accept).
Rectangle {
    id: root
    color: theme.surface
    /// The requests (chat list entries with `request`), newest first.
    property var requests: []
    property string selectedId: ""
    readonly property real paneWidth: 380
    signal openRequest(string id, string name)

    readonly property var ordered: requests.slice().sort((a, b) => String(b.time || "").localeCompare(String(a.time || "")))
    function stamp(t) {
        if (!t) return ""
        const d = new Date(t), n = new Date()
        if (isNaN(d.getTime())) return ""
        if (d.toDateString() === n.toDateString()) return theme.time(d)
        return d.getFullYear() === n.getFullYear() ? theme.dateNoYear(d) : theme.dateShortYear(d)
    }

    Item {
        id: pane
        width: root.paneWidth; height: parent.height
        Text {
            x: 32; y: 19
            text: qsTr("Requests")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle { y: 60; width: parent.width; height: 0.67; color: theme.divider }
        ListView {
            id: list
            y: 72; width: parent.width; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.ordered
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool sel: modelData.id === root.selectedId
                width: list.width; height: 60
                Rectangle {
                    id: fill
                    x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
                    color: row.sel ? theme.selected : rh.hovered ? theme.rowHover : "transparent"
                }
                Rectangle {
                    visible: row.modelData.unread === true && !row.sel
                    x: 22; y: 28; width: 4; height: 4; radius: 2
                    color: theme.onFill(fill, theme.text)
                }
                // (A group's request: its merged picture, under the name of
                // whoever added you.)
                Avatar {
                    x: 32; y: 12; size: 36
                    name: row.modelData.name || ""
                    photoId: row.modelData.peerMri || (row.modelData.isGroup ? "chat:" + row.modelData.id : "")
                    group: row.modelData.isGroup === true && !row.modelData.peerMri
                    presence: row.modelData.presence || ""
                }
                Text {
                    x: 80; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 32 - timeText.implicitWidth - 12
                    elide: Text.ElideRight
                    text: row.modelData.inviterName || row.modelData.name || ""
                    font.family: theme.font; font.pixelSize: 14
                    font.weight: row.modelData.unread === true && !row.sel ? Font.Bold : Font.Normal
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.onFill(fill, theme.text)
                }
                Text {
                    id: timeText
                    anchors.right: parent.right; anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stamp(row.modelData.time)
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.onFill(fill, theme.textStrong)
                }
                HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openRequest(row.modelData.id, row.modelData.name || "") }
                Accessible.role: Accessible.ListItem
                Accessible.name: (row.modelData.inviterName || row.modelData.name || "") + ", " + timeText.text + (row.modelData.unread === true ? ", " + qsTr("Unread") : "")
            }
        }
    }
    Rectangle { x: root.paneWidth; width: 0.67; height: parent.height; color: theme.divider }
    // Nothing picked yet: Teams' empty state in the rest.
    Item {
        visible: !root.selectedId
        x: root.paneWidth + 1; width: parent.width - x; height: parent.height
        Image {
            id: pic
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(16, parent.height / 2 - height + 20)
            source: "../assets/illustrations/chat-request.svg"
            sourceSize: Qt.size(160, 160)
            width: 160; height: 160
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: pic.y + pic.height + 52
            width: Math.min(parent.width - 48, 480)
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: qsTr("Select a chat request item to accept or block.")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }
}
