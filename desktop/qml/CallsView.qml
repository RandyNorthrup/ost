import QtQuick
import QtQuick.Controls.Basic

// The Calls app: a left pane (title, "Type a name" search, speed dial)
// and the History table, in the same chrome as Chat.
Item {
    id: root
    property var calls: []
    signal openChatWith(string mri, string name)

    property string filter: "all"   // all | missed | incoming | outgoing
    readonly property var shown: calls.filter(c => {
        const missed = c.state !== "accepted"
        if (root.filter === "missed") return missed && c.direction === "incoming"
        if (root.filter === "incoming") return c.direction === "incoming"
        if (root.filter === "outgoing") return c.direction === "outgoing"
        return true
    })

    function duration(c) {
        if (!c.connect_time || !c.end_time) return ""
        const s = Math.max(0, Math.round((new Date(c.end_time) - new Date(c.connect_time)) / 1000))
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
        const two = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + "h " + m + "m" : (m > 0 ? m + "m " + sec + "s" : sec + "s")
    }
    function when(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "h:mm AP")
        const y = new Date(now); y.setDate(now.getDate() - 1)
        if (d.toDateString() === y.toDateString()) return "Yesterday"
        return Qt.formatDate(d, "M/d")
    }
    function kind(c) {
        if (c.direction === "incoming" && c.state !== "accepted") return "missed"
        return c.direction
    }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Left pane
    Rectangle {
        id: pane
        width: theme.listWidth; height: parent.height
        color: theme.pane
        Text {
            x: 32; y: 20
            text: "Calls"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            x: 32; y: 64; width: parent.width - 64; height: 32; radius: theme.radius
            color: theme.surface
            border.color: theme.divider
            FluentIcon { x: 8; name: "dialpad-20"; size: 16; anchors.verticalCenter: parent.verticalCenter }
            Text {
                x: 32; anchors.verticalCenter: parent.verticalCenter
                text: "Type a name or number"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }
        }
        Text {
            x: 32; y: 120
            text: "Speed dial"
            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
            color: theme.text
        }
        Text {
            x: 32; y: 146; width: parent.width - 64
            wrapMode: Text.WordWrap
            text: "People you call often will show up here."
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.textSecondary
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.divider }
    }

    // History
    Item {
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Text {
            id: title
            x: 24; y: 20
            text: "History"
            font.family: theme.font; font.pixelSize: theme.title; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            id: chips
            x: 24; y: 60
            spacing: 4
            Repeater {
                model: [["all", "All"], ["missed", "Missed"], ["incoming", "Incoming"], ["outgoing", "Outgoing"]]
                Rectangle {
                    required property var modelData
                    readonly property bool on: root.filter === modelData[0]
                    width: chipText.implicitWidth + 20; height: 26; radius: 13
                    color: on ? theme.brandTint : theme.surface
                    border.color: on ? theme.brand : theme.stroke
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: parent.modelData[1]
                        font.family: theme.font; font.pixelSize: theme.small
                        color: parent.on ? theme.brand : theme.text
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.filter = parent.modelData[0] }
                }
            }
        }
        // Column headings
        Row {
            id: heads
            x: 24; y: 104
            Repeater {
                model: [["Name", 300], ["Type", 160], ["Duration", 120], ["Date", 120]]
                Text {
                    required property var modelData
                    width: modelData[1]
                    text: modelData[0]
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
            }
        }
        Rectangle { x: 24; y: 124; width: parent.width - 48; height: 1; color: theme.dividerSoft }

        ListView {
            x: 24; y: 125; width: parent.width - 48; height: parent.height - y
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property string k: root.kind(modelData)
                width: ListView.view.width; height: 52
                color: hover.hovered ? theme.pane : "transparent"
                Avatar {
                    x: 0; anchors.verticalCenter: parent.verticalCenter
                    size: 32; name: row.modelData.peer_name || "?"
                }
                Text {
                    x: 44; width: 300 - 52; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.peer_name || row.modelData.peer_mri
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base
                    font.weight: row.k === "missed" ? Font.DemiBold : Font.Normal
                    color: row.k === "missed" ? theme.danger : theme.text
                }
                Row {
                    x: 300; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    FluentIcon {
                        name: row.k === "missed" ? "call-missed-16" : row.k === "incoming" ? "call-inbound-16" : "call-outbound-16"
                        size: 16
                        color: row.k === "missed" ? theme.danger : theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: row.k === "missed" ? "Missed" : row.k === "incoming" ? "Incoming" : "Outgoing"
                        font.family: theme.font; font.pixelSize: theme.base
                        color: row.k === "missed" ? theme.danger : theme.text
                    }
                }
                Text {
                    x: 460; anchors.verticalCenter: parent.verticalCenter
                    text: root.duration(row.modelData)
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
                Text {
                    x: 580; anchors.verticalCenter: parent.verticalCenter
                    text: root.when(row.modelData.start_time)
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
                // Hover action: open the chat with this person.
                FluentIcon {
                    visible: hover.hovered && row.modelData.peer_mri.length > 0
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    name: "chat-20"; size: 20
                    TapHandler { onTapped: root.openChatWith(row.modelData.peer_mri, row.modelData.peer_name) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Chat with " + row.modelData.peer_name
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
                HoverHandler { id: hover }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: root.shown.length === 0
            text: root.calls.length === 0 ? "No calls yet" : "No calls match this filter"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
    }
}
