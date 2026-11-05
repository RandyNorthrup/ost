import QtQuick
import QtQuick.Controls.Basic

// Quick views > Mentions, as Teams desktop lays it out (measured at 1x):
// a 380 px list of messages that @mention you, with Unread / Channels /
// Chats filters; each row has an unread dot, the sender's picture, name
// and time, and the message with your name highlighted. Picking one opens
// its chat beside the list; until then a hint fills the space.
Rectangle {
    id: root
    /// Activity items (only mentions are shown), newest first.
    property var items: []
    property string myName: ""
    property string selectedId: ""
    signal openMention(var item)
    property string chip: ""
    readonly property var mentions: items.filter(i => i.kind === "mention")
    readonly property var shown: mentions.filter(m => !chip
        || (chip === "unread" ? m.unread
            : chip === "channels" ? (m.thread_id || "").endsWith("@thread.tacv2")
            : !(m.thread_id || "").endsWith("@thread.tacv2")))
    readonly property real paneWidth: 380
    color: theme.surface

    function stamp(t) {
        const d = new Date(t), now = new Date()
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (days === 0) return Qt.formatTime(d, "h:mm AP")
        if (days === 1) return "Yesterday"
        if (days > 1 && days < 7) return Qt.formatDate(d, "dddd")
        return Qt.formatDate(d, "M/d")
    }
    function esc(t) { return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    // Your name, bold in Teams' mention colour.
    function highlighted(text) {
        const t = esc(text), n = esc(root.myName)
        if (!n) return t
        return t.split(n).join("<b><font color=\"" + theme.mentionMe + "\">" + n + "</font></b>")
    }

    Rectangle {
        id: pane
        width: root.paneWidth; height: parent.height
        color: theme.surface
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }

        Text {
            x: 32; y: 19
            text: "Mentions"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: 32; y: 69
            spacing: 4
            Repeater {
                model: ["Unread", "Channels", "Chats"]
                delegate: Rectangle {
                    id: mchip
                    required property string modelData
                    readonly property bool on: root.chip === modelData.toLowerCase()
                    height: 24; radius: 12
                    width: chipText.implicitWidth + 16
                    color: on ? theme.brandTint : (mch.hovered ? theme.rowHover : "transparent")
                    border.color: on ? theme.brand : theme.stroke
                    HoverHandler { id: mch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.chip = mchip.on ? "" : mchip.modelData.toLowerCase() }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData
                        font.family: theme.font; font.pixelSize: theme.small
                        color: mchip.on ? theme.brand : theme.textStrong
                    }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData
                    Accessible.checked: on
                }
            }
        }

        ListView {
            id: list
            y: 106
            width: parent.width - 1; height: parent.height - y
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool sel: root.selectedId === modelData.id
                width: list.width; height: 66
                Rectangle {
                    x: 8; width: parent.width - 16; height: parent.height - 4; radius: theme.radius
                    color: row.sel ? theme.selected : rh.hovered ? theme.pane : "transparent"
                }
                Rectangle {
                    visible: row.modelData.unread
                    x: 12; y: 30; width: 5; height: 5; radius: 2.5
                    color: theme.textStrong
                }
                Avatar {
                    x: 24; y: 12
                    size: 32; name: row.modelData.actor_name || "?"
                    photoId: row.modelData.actor_mri || ""
                }
                Text {
                    x: 72; y: 10; width: parent.width - 72 - 80
                    text: row.modelData.actor_name || "Someone"
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.text
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 24; y: 12
                    text: root.stamp(row.modelData.time)
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Text {
                    x: 72; y: 32; width: parent.width - 72 - 24
                    text: root.highlighted(row.modelData.preview)
                    textFormat: Text.StyledText
                    elide: Text.ElideRight; maximumLineCount: 1
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                }
                HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openMention(row.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: (row.modelData.unread ? "Unread, " : "") + (row.modelData.actor_name || "Someone") + " mentioned you: " + row.modelData.preview
            }
            Text {
                visible: root.shown.length === 0
                x: 32; y: 8
                text: root.mentions.length === 0 ? "No mentions yet" : "No mentions match"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }
        }
    }

    Column {
        anchors.centerIn: hint
        spacing: 16
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "mention-20"; size: 64; color: theme.brand }
        Text {
            text: "When you select an @mention, it'll show up here"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            color: theme.text
        }
    }
    Item { id: hint; anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom } }
}
