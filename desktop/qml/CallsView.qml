import QtQuick
import QtQuick.Controls.Basic

// The Calls app, laid out as Teams desktop's (measured at 1x): a header
// with the Calls tile, the Personal tab and View contacts; then three
// panes: dial (find someone and call), History, and Speed dial.
Item {
    id: root
    property var calls: []
    /// People search results for the dial box ([{id, name, mail, job_title}]).
    property var people: []
    signal openChatWith(string mri, string name)
    signal callPerson(string oid, string name)
    signal searchPeople(string query)

    property string filter: "all"   // all | missed | incoming | outgoing
    readonly property var filterLabels: ({ all: "All", missed: "Missed", incoming: "Incoming", outgoing: "Outgoing" })
    readonly property var shown: calls.filter(c => {
        const missed = c.state !== "accepted"
        if (root.filter === "missed") return missed && c.direction === "incoming"
        if (root.filter === "incoming") return c.direction === "incoming"
        if (root.filter === "outgoing") return c.direction === "outgoing"
        return true
    })
    property bool historyOpen: true
    property bool speedDialShown: true
    // Speed dial: people you call often (kept on this device).
    property var speedDial: { try { return JSON.parse(backend.setting("speedDial") || "[]") } catch (e) { return [] } }
    function saveSpeedDial(list) { speedDial = list; backend.setSetting("speedDial", JSON.stringify(list)) }
    property bool addingSpeedDial: false

    function duration(c) {
        if (!c.connect_time || !c.end_time) return ""
        const s = Math.max(0, Math.round((new Date(c.end_time) - new Date(c.connect_time)) / 1000))
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
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
    function oidOf(mri) { return (mri || "").replace(/^8:orgid:/, "") }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Header: tile, title, Personal tab, View contacts, speed dial toggle.
    Item {
        id: header
        width: parent.width; height: 61
        Rectangle {
            x: 28; y: 14; width: 32; height: 32; radius: theme.radius
            color: theme.brandFill
            FluentIcon { anchors.centerIn: parent; name: "call-filled"; size: 20; color: "white" }
        }
        Text {
            x: 60; anchors.verticalCenter: parent.verticalCenter
            text: "Calls"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Item {
            x: 124; y: 3; width: 68; height: 54
            Text {
                anchors.centerIn: parent
                text: "Personal"
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: theme.text
            }
            Rectangle { anchors.bottom: parent.bottom; x: 8; width: parent.width - 16; height: 3; radius: 1.5; color: theme.brand }
            Accessible.role: Accessible.PageTab
            Accessible.name: "Personal"
        }
        Rectangle {
            x: parent.width - 186; y: 15; width: 139; height: 31; radius: theme.radius
            color: vch.hovered ? theme.rowHover : theme.input
            border.color: theme.stroke
            Row {
                anchors.centerIn: parent
                spacing: 8
                Text { text: "View contacts"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "share-20"; size: 16; color: theme.textStrong }
            }
            HoverHandler { id: vch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Qt.openUrlExternally("https://outlook.office.com/people/") }
            Accessible.role: Accessible.Button
            Accessible.name: "View contacts"
        }
        Rectangle {
            x: parent.width - 43; y: 15; width: 32; height: 31; radius: theme.radius
            color: sdt.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "people"; size: 20; color: root.speedDialShown ? theme.brand : theme.textStrong }
            HoverHandler { id: sdt; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.speedDialShown = !root.speedDialShown }
            Accessible.role: Accessible.Button
            Accessible.name: root.speedDialShown ? "Close speed dial" : "Open speed dial"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // Dial: find someone, then call.
    Item {
        id: dial
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left }
        width: 380
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        property var chosen: null
        Rectangle {
            id: nameBox
            x: 16; y: 11; width: 347; height: 40; radius: theme.radius
            color: theme.input
            border.color: theme.stroke
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: nameField.activeFocus ? 2 : 1; color: nameField.activeFocus ? theme.brand : theme.textStrong }
            TextInput {
                id: nameField
                x: 12; width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                onTextEdited: { dial.chosen = null; if (text.trim().length > 1) searchDelay.restart() }
                Text { visible: !nameField.text; text: "Type a name"; color: theme.textTertiary; font: nameField.font }
                Accessible.name: "Type a name"
            }
            Timer { id: searchDelay; interval: 300; onTriggered: root.searchPeople(nameField.text.trim()) }
        }
        // Matches while typing.
        Rectangle {
            visible: nameField.activeFocus && nameField.text.trim().length > 1 && !dial.chosen && root.people.length > 0
            z: 10
            x: 16; y: nameBox.y + nameBox.height + 2; width: nameBox.width
            height: Math.min(240, pplCol.implicitHeight + 8); radius: 8
            color: theme.menu
            border.color: theme.dividerSoft
            Column {
                id: pplCol
                x: 4; y: 4; width: parent.width - 8
                Repeater {
                    model: root.people.slice(0, 5)
                    Rectangle {
                        required property var modelData
                        width: pplCol.width; height: 44; radius: theme.radius
                        color: ph.hovered ? theme.rowHover : "transparent"
                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                        Column {
                            x: 46; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                            Text { text: parent.parent.modelData.mail || parent.parent.modelData.job_title || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { dial.chosen = parent.modelData; nameField.text = parent.modelData.name } }
                    }
                }
            }
        }
        Rectangle {
            x: 16; y: 82; width: 347; height: 32; radius: theme.radius
            readonly property bool ready: dial.chosen !== null
            color: ready ? (cbh.hovered ? theme.brandHover : theme.brandFill) : (theme.dark ? "#2E2E2E" : "#F0F0F0")
            Row {
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 16; color: parent.parent.ready ? "white" : theme.disabled }
                Text { text: "Call"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: parent.parent.ready ? "white" : theme.disabled }
            }
            HoverHandler { id: cbh; cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.ready; onTapped: root.callPerson(dial.chosen.id, dial.chosen.name) }
            Accessible.role: Accessible.Button
            Accessible.name: "Call"
        }
        // The speaker calls use, as Teams shows at the bottom of this pane.
        Rectangle {
            id: deviceRow
            x: 16; y: parent.height - 52; height: 36; radius: theme.radius
            width: Math.min(300, deviceText.implicitWidth + 64)
            color: dvh.hovered ? theme.rowHover : "transparent"
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "headset-20"; size: 20; color: theme.textStrong }
            Text {
                id: deviceText
                x: 36; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 230); elide: Text.ElideRight
                text: { const d = backend.setting("speakerDevice"); return d && d !== "default" ? d : "Default speaker" }
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textStrong }
            HoverHandler { id: dvh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { deviceMenu.devices = JSON.parse(backend.audioDevices()).outputs; deviceMenu.open() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Speaker: " + deviceText.text
            MenuPopup {
                id: deviceMenu
                property var devices: []
                width: 320
                y: -height - 4
                items: [{ label: "Default speaker" }].concat(devices.map(d => ({ label: d, checked: backend.setting("speakerDevice") === d })))
                onPicked: i => {
                    const v = i === 0 ? "default" : devices[i - 1]
                    backend.setSetting("speakerDevice", v)
                    deviceText.text = i === 0 ? "Default speaker" : v
                }
            }
        }
    }

    // History
    Item {
        id: history
        anchors { top: header.bottom; bottom: parent.bottom; left: dial.right; right: speedPane.visible ? speedPane.left : parent.right }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Item {
            id: histHead
            width: parent.width; height: 48
            Rectangle {
                x: 17; y: 8; width: 88; height: 35; radius: theme.radius
                color: hhh.hovered ? theme.rowHover : "transparent"
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: root.historyOpen ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.text }
                Text { x: 26; anchors.verticalCenter: parent.verticalCenter; text: "History"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.text }
                HoverHandler { id: hhh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.historyOpen = !root.historyOpen }
                Accessible.role: Accessible.Button
                Accessible.name: "History"
            }
            // The filter, as Teams' brand pill.
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 58; y: 13
                height: 25; radius: 12.5
                width: pillText.implicitWidth + 38
                color: pfh.hovered ? theme.brandHover : theme.brandFill
                Text { id: pillText; x: 12; anchors.verticalCenter: parent.verticalCenter; text: root.filterLabels[root.filter]; font.family: theme.font; font.pixelSize: theme.base; color: "white" }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: "white" }
                HoverHandler { id: pfh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: filterMenu.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Show " + root.filterLabels[root.filter]
                MenuPopup {
                    id: filterMenu
                    width: 180; y: parent.height + 4
                    items: ["all", "missed", "incoming", "outgoing"].map(k => ({ label: root.filterLabels[k], checked: root.filter === k }))
                    onPicked: i => root.filter = ["all", "missed", "incoming", "outgoing"][i]
                }
            }
        }
        ListView {
            id: list
            visible: root.historyOpen
            anchors { top: histHead.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property string k: root.kind(modelData)
                width: list.width; height: 51
                color: rh.hovered ? theme.rowHover : "transparent"
                Avatar {
                    x: 26; anchors.verticalCenter: parent.verticalCenter
                    size: 32; name: row.modelData.peer_name || "?"; photoId: row.modelData.peer_mri || ""
                }
                Column {
                    x: 64; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 64 - 140
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.peer_name || "Unknown"
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                        color: theme.text
                    }
                    Row {
                        spacing: 4
                        FluentIcon {
                            anchors.verticalCenter: parent.verticalCenter; size: 16
                            name: row.k === "missed" ? "call-missed-16" : row.k === "outgoing" ? "call-outbound-16" : "call-inbound-16"
                            color: row.k === "missed" ? "#BC2F32" : theme.textSecondary
                        }
                        Text {
                            text: (row.k === "missed" ? "Missed incoming" : row.k === "outgoing" ? "Outgoing" : "Incoming")
                                + (root.duration(row.modelData) ? " · " + root.duration(row.modelData) : "")
                            font.family: theme.font; font.pixelSize: theme.small; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                            color: row.k === "missed" ? "#BC2F32" : theme.textSecondary
                        }
                    }
                }
                Text {
                    visible: !rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    text: root.when(row.modelData.start_time)
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                    color: theme.textStrong
                }
                // On hover: chat, and call back.
                Row {
                    visible: rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        width: 31; height: 31; radius: theme.radius
                        color: mah.hovered ? theme.selected : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "chat-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openChatWith(row.modelData.peer_mri, row.modelData.peer_name) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Chat with " + row.modelData.peer_name
                    }
                    Rectangle {
                        width: 64; height: 23; radius: theme.radius
                        anchors.verticalCenter: parent.verticalCenter
                        color: cbh2.hovered ? theme.rowHover : theme.input
                        border.color: theme.stroke
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 14; color: theme.text }
                            Text { text: "Call"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                        }
                        HoverHandler { id: cbh2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.callPerson(root.oidOf(row.modelData.peer_mri), row.modelData.peer_name) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Call " + row.modelData.peer_name
                    }
                }
                HoverHandler { id: rh }
                Accessible.role: Accessible.ListItem
                Accessible.name: (row.modelData.peer_name || "Unknown") + ", " + row.k + ", " + root.when(row.modelData.start_time)
            }
            Text {
                visible: root.shown.length === 0
                x: 26; y: 12
                text: root.calls.length === 0 ? "Your calls will show up here." : "No calls match this filter."
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }
        }
    }

    // Speed dial
    Item {
        id: speedPane
        visible: root.speedDialShown
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 360
        Text { x: 20.7; y: 14.6; text: "Speed dial"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
        Rectangle {
            x: 308; y: 10.7; width: 32; height: 31; radius: theme.radius
            color: sah.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "people-add-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: sah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.addingSpeedDial = true; addField.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Add contact to speed dial"
        }
        // Adding: search and pick someone.
        Rectangle {
            id: addBox
            visible: root.addingSpeedDial
            x: 20; y: 52; width: parent.width - 40; height: 32; radius: theme.radius
            color: theme.input
            border.color: addField.activeFocus ? theme.brand : theme.stroke
            TextInput {
                id: addField
                x: 10; width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                onTextEdited: if (text.trim().length > 1) addDelay.restart()
                Keys.onEscapePressed: { text = ""; root.addingSpeedDial = false }
                Text { visible: !addField.text; text: "Add someone"; color: theme.textTertiary; font: addField.font }
            }
            Timer { id: addDelay; interval: 300; onTriggered: root.searchPeople(addField.text.trim()) }
        }
        Column {
            id: addResults
            visible: root.addingSpeedDial && addField.text.trim().length > 1
            x: 20; y: 88; width: parent.width - 40
            Repeater {
                model: root.people.slice(0, 5)
                Rectangle {
                    required property var modelData
                    width: addResults.width; height: 40; radius: theme.radius
                    color: arh.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                    Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    HoverHandler { id: arh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const p = parent.modelData
                            if (!root.speedDial.some(s => s.id === p.id)) root.saveSpeedDial(root.speedDial.concat([{ id: p.id, name: p.name }]))
                            addField.text = ""; root.addingSpeedDial = false
                        }
                    }
                }
            }
        }
        ListView {
            id: speedList
            visible: !root.addingSpeedDial && root.speedDial.length > 0
            x: 8; y: 52; width: parent.width - 16; height: parent.height - y
            clip: true
            model: root.speedDial
            delegate: Rectangle {
                id: sd
                required property var modelData
                width: speedList.width; height: 48; radius: theme.radius
                color: sdh.hovered ? theme.rowHover : "transparent"
                Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: sd.modelData.name; photoId: sd.modelData.id }
                Text { x: 54; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 140; elide: Text.ElideRight; text: sd.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Row {
                    visible: sdh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: [{ icon: "call-20", l: "Call" }, { icon: "dismiss-12", l: "Remove from speed dial" }]
                        Rectangle {
                            required property var modelData
                            width: 32; height: 32; radius: theme.radius
                            color: sbh.hovered ? theme.selected : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: parent.modelData.icon === "dismiss-12" ? 12 : 20; color: theme.textStrong }
                            HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: parent.modelData.icon === "call-20" ? root.callPerson(sd.modelData.id, sd.modelData.name)
                                    : root.saveSpeedDial(root.speedDial.filter(s => s.id !== sd.modelData.id))
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.l + " " + sd.modelData.name
                        }
                    }
                }
                HoverHandler { id: sdh }
            }
        }
        // Empty: as Teams says it, with an Add button.
        Column {
            visible: !root.addingSpeedDial && root.speedDial.length === 0
            anchors.centerIn: parent
            spacing: 12
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "people"; size: 48; color: theme.brand }
            Text {
                width: 260; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "Add people to speed dial for quick access."
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 31; radius: theme.radius
                color: abh.hovered ? theme.rowHover : theme.input
                border.color: theme.stroke
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 16; color: theme.text }
                    Text { text: "Add"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                }
                HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.addingSpeedDial = true; addField.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Add people to speed dial"
            }
        }
    }
}
