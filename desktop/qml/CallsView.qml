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
    /// Open Settings at Teams' section id (launchSection).
    signal openSettings(string id)

    // Teams' calling settings (SettingsView's synced settings), loaded when
    // the app first shows.
    readonly property var synced: backend.settingsJson ? JSON.parse(backend.settingsJson) : ({ props: {}, mt: {} })
    readonly property var mt: synced.mt || {}
    onVisibleChanged: if (visible && !synced.loaded) backend.loadSettings()
    // Intelligent call delegation (Teams' isUserPAEligible: ECS
    // enablePersonalAttendant, a Copilot licence unless ECS
    // disablePALicenseCheck, and the policy offering it) and its status
    // (the banner's: Active when on, Inactive once set up, else Requires
    // setup).
    readonly property var paPolicy: mt.attendantPolicy || {}
    readonly property bool paEligible: backend.ecsSetting("calling", "enablePersonalAttendant") === "true"
        && (mt.copilot === true || backend.ecsSetting("calling", "disablePALicenseCheck") === "true")
        && (paPolicy.personalAttendant === "Enabled" || paPolicy.personalAttendant === "EnabledUserOverride")
    readonly property bool paOn: paEligible && (paPolicy.personalAttendant === "Enabled" || (paPolicy.personalAttendant === "EnabledUserOverride" && (mt.attendant || {}).isEnabled === true))
    readonly property bool paCompleted: (((((synced.props || {}).userPersonalSettings) || {}).callingUserSettings) || {}).paOnboardingCompleted === true
    readonly property string paStatus: paOn ? "active" : paCompleted ? "inactive" : "requiresSetup"
    property bool paOpen: false
    function dialPaneForTest() { return dialPane }
    function paPaneForTest() { return paPane }

    property string filter: "all"   // all | missed | incoming | outgoing
    readonly property var filterLabels: ({ all: qsTr("All"), missed: qsTr("Missed"), incoming: qsTr("Incoming"), outgoing: qsTr("Outgoing") })
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
        // Teams' call history: "1h 5m" (no minutes when 0), "5m 3s", "3s"
        // (call_history_call_duration_long_mf / _short_mf).
        return backend.durationText("history", s)
    }
    function when(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return theme.time(d)
        const y = new Date(now); y.setDate(now.getDate() - 1)
        if (d.toDateString() === y.toDateString()) return qsTr("Yesterday")
        return theme.dateNoYear(d)
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
            id: hcFill1
            x: 28; y: 14; width: 32; height: 32; radius: theme.radius
            color: theme.brandFill
            FluentIcon { anchors.centerIn: parent; name: "call-filled"; size: 20; color: theme.onFill(hcFill1, "white") }
        }
        Text {
            x: 60; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Calls")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Item {
            x: 124; y: 3; width: 68; height: 54
            Text {
                anchors.centerIn: parent
                text: qsTr("Personal")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: theme.text
            }
            Rectangle { anchors.bottom: parent.bottom; x: 8; width: parent.width - 16; height: 3; radius: 1.5; color: theme.brand }
            Accessible.role: Accessible.PageTab
            Accessible.name: qsTr("Personal")
        }
        Rectangle {
            id: hcFill2
            x: parent.width - 186; y: 15; width: 139; height: 31; radius: theme.radius
            color: vch.hovered ? theme.rowHover : theme.input
            border.color: theme.stroke
            Row {
                anchors.centerIn: parent
                spacing: 8
                Text { text: qsTr("View contacts"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "share-20"; size: 16; color: theme.onFill(hcFill2, theme.textStrong) }
            }
            HoverHandler { id: vch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.openExternal("https://outlook.office.com/people/") }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("View contacts")
        }
        Rectangle {
            id: hcFill3
            x: parent.width - 43; y: 15; width: 32; height: 31; radius: theme.radius
            color: sdt.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "people"; size: 20; color: theme.onFill(hcFill3, root.speedDialShown && !root.paOpen ? theme.brand : theme.textStrong) }
            HoverHandler { id: sdt; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { if (root.paOpen) { root.paOpen = false; root.speedDialShown = true } else root.speedDialShown = !root.speedDialShown } }
            Accessible.role: Accessible.Button
            Accessible.name: root.speedDialShown && !root.paOpen ? qsTr("Close speed dial") : qsTr("Open speed dial")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // Dial: find someone or a number, then call (CallsDialPane).
    Item {
        id: dial
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left }
        width: 380
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        CallsDialPane {
            id: dialPane
            anchors.fill: parent
            people: root.people
            mt: root.mt
            attendantOn: root.paOn
            onCallPerson: (oid, name) => root.callPerson(oid, name)
            onSearchPeople: q => root.searchPeople(q)
            onOpenSettings: id => root.openSettings(id)
            onUnpark: unparkDialog.start()
        }
    }

    // History
    Item {
        id: history
        anchors { top: header.bottom; bottom: parent.bottom; left: dial.right; right: speedPane.visible ? speedPane.left : paPane.visible ? paPane.left : parent.right }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        // Teams' Intelligent call delegation banner (calls-main-app's
        // PA onboarding banner, for a user it's offered to: ECS
        // enablePersonalAttendant, a Copilot licence and the policy): its
        // glyph (24 at 20), the title (14/700, 10 after it), the status
        // badge 10 after that (10/600 #616161 on #F0F0F0, 16 tall, radius
        // 4: Requires setup, Inactive once set up, Active when on) and the
        // pane toggle at the end (padding 20); 49.3 tall over a #F0F0F0
        // line (measured over CDP on winpc 2026-11-27), #EBEBEB while the
        // pane is open.
        Rectangle {
            id: paBanner
            visible: root.paEligible
            width: parent.width; height: visible ? 50 : 0
            color: root.paOpen ? theme.pick("#EBEBEB", "#2E2E2E", "#000000") : pbh.hovered ? theme.rowHover : "transparent"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#2E2E2E", "#FFFFFF") }
            Image { x: 20; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; source: "../assets/illustrations/personal-attendant-avatar.svg"; sourceSize: Qt.size(48, 48) }
            Text {
                id: paTitle
                x: 54; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Intelligent call delegation")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.onFill(paBanner, theme.text)
            }
            Rectangle {
                id: paBadge
                x: paTitle.x + paTitle.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter
                height: 16; radius: 4; width: badgeRow.implicitWidth + 8
                color: root.paStatus === "active" ? theme.pick("#F1FAF1", "#052505", "#000000") : theme.pick("#F0F0F0", "#3D3D3D", "#000000")
                border.color: root.paStatus === "active" ? theme.pick("#9FD89F", "#107C10", "#FFFFFF") : "transparent"
                Row {
                    id: badgeRow
                    anchors.centerIn: parent; spacing: 4
                    Rectangle { visible: root.paStatus !== "requiresSetup"; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: root.paStatus === "active" ? theme.pick("#107C10", "#54B054", "#FFFFFF") : theme.textSecondary }
                    Text { text: root.paStatus === "active" ? qsTr("Active") : root.paStatus === "inactive" ? qsTr("Inactive") : qsTr("Requires setup"); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.onFill(paBadge, theme.textSecondary) }
                }
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; name: root.paOpen ? "panel-right-contract-20-filled" : "panel-right-expand-20"; size: 20; color: theme.onFill(paBanner, theme.textStrong) }
            HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.paOpen = !root.paOpen }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Toggle intelligent call delegation settings panel")
            Accessible.checkable: true
            Accessible.checked: root.paOpen
        }
        Item {
            id: histHead
            y: paBanner.height
            width: parent.width; height: 48
            Rectangle {
                id: hcFill6
                x: 17; y: 8; width: 88; height: 35; radius: theme.radius
                color: hhh.hovered ? theme.rowHover : "transparent"
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: root.historyOpen ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.onFill(hcFill6, theme.text) }
                Text { x: 26; anchors.verticalCenter: parent.verticalCenter; text: qsTr("History"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.onFill(hcFill6, theme.text) }
                HoverHandler { id: hhh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.historyOpen = !root.historyOpen }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("History")
            }
            // The filter, as Teams' brand pill.
            Rectangle {
                id: hcFill7
                anchors.right: parent.right; anchors.rightMargin: 58; y: 13
                height: 25; radius: 12.5
                width: pillText.implicitWidth + 38
                color: pfh.hovered ? theme.brandHover : theme.brandFill
                Text { id: pillText; x: 12; anchors.verticalCenter: parent.verticalCenter; text: root.filterLabels[root.filter]; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill7, "white") }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(hcFill7, "white") }
                HoverHandler { id: pfh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: filterMenu.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Show %1").arg(root.filterLabels[root.filter])
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
                        text: row.modelData.peer_name || qsTr("Unknown")
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                        color: theme.onFill(row, theme.text)
                    }
                    Row {
                        spacing: 4
                        FluentIcon {
                            anchors.verticalCenter: parent.verticalCenter; size: 16
                            name: row.k === "missed" ? "call-missed-16" : row.k === "outgoing" ? "call-outbound-16" : "call-inbound-16"
                            color: theme.onFill(row, row.k === "missed" ? theme.hc("#BC2F32", "#FFFFFF") : theme.textSecondary)
                        }
                        Text {
                            text: (row.k === "missed" ? qsTr("Missed incoming") : row.k === "outgoing" ? qsTr("Outgoing") : qsTr("Incoming"))
                                + (root.duration(row.modelData) ? " · " + root.duration(row.modelData) : "")
                            font.family: theme.font; font.pixelSize: theme.small; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                            color: theme.onFill(row, row.k === "missed" ? theme.hc("#BC2F32", "#FFFFFF") : theme.textSecondary)
                        }
                    }
                }
                Text {
                    visible: !rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    text: root.when(row.modelData.start_time)
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: row.k === "missed" ? Font.Bold : Font.Normal
                    color: theme.onFill(row, theme.textStrong)
                }
                // On hover: chat, and call back.
                Row {
                    visible: rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        id: hcFill8
                        width: 31; height: 31; radius: theme.radius
                        color: mah.hovered ? theme.selected : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "chat-20"; size: 20; color: theme.onFill(hcFill8, theme.textStrong) }
                        HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openChatWith(row.modelData.peer_mri, row.modelData.peer_name) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Chat with %1").arg(row.modelData.peer_name)
                    }
                    Rectangle {
                        id: hcFill9
                        width: 64; height: 23; radius: theme.radius
                        anchors.verticalCenter: parent.verticalCenter
                        color: cbh2.hovered ? theme.rowHover : theme.input
                        border.color: theme.stroke
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 14; color: theme.onFill(hcFill9, theme.text) }
                            Text { text: qsTr("Call", "calling:ka2l734dq"); font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill9, theme.text) }
                        }
                        HoverHandler { id: cbh2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.callPerson(root.oidOf(row.modelData.peer_mri), row.modelData.peer_name) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Call %1").arg(row.modelData.peer_name)
                    }
                }
                HoverHandler { id: rh }
                Accessible.role: Accessible.ListItem
                Accessible.name: qsTr("%1, %2, %3").arg(row.modelData.peer_name || qsTr("Unknown")).arg(row.k).arg(root.when(row.modelData.start_time))
            }
            Text {
                visible: root.shown.length === 0
                x: 26; y: 12
                text: root.calls.length === 0 ? qsTr("Your calls will show up here.") : qsTr("No calls match this filter.")
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }
        }
    }

    // Speed dial
    Item {
        id: speedPane
        visible: root.speedDialShown && !root.paOpen
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 360
        Text { x: 20.7; y: 14.6; text: qsTr("Speed dial"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
        Rectangle {
            id: hcFill10
            x: 308; y: 10.7; width: 32; height: 31; radius: theme.radius
            color: sah.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "people-add-20"; size: 20; color: theme.onFill(hcFill10, theme.textStrong) }
            HoverHandler { id: sah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.addingSpeedDial = true; addField.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("add contact to speed dial")
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
                Text { visible: !addField.text; text: qsTr("Add someone"); color: theme.textTertiary; font: addField.font }
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
                    id: hcFill11
                    required property var modelData
                    width: addResults.width; height: 40; radius: theme.radius
                    color: arh.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                    Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill11, theme.text) }
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
                Text { x: 54; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 140; elide: Text.ElideRight; text: sd.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(sd, theme.text) }
                Row {
                    visible: sdh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: [{ icon: "call-20", l: qsTr("Call", "calling:ka2l734dq") }, { icon: "dismiss-12", l: qsTr("Remove from speed dial") }]
                        Rectangle {
                            id: hcFill12
                            required property var modelData
                            width: 32; height: 32; radius: theme.radius
                            color: sbh.hovered ? theme.selected : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: parent.modelData.icon === "dismiss-12" ? 12 : 20; color: theme.onFill(hcFill12, theme.textStrong) }
                            HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: parent.modelData.icon === "call-20" ? root.callPerson(sd.modelData.id, sd.modelData.name)
                                    : root.saveSpeedDial(root.speedDial.filter(s => s.id !== sd.modelData.id))
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1 %2").arg(modelData.l).arg(sd.modelData.name)
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
            // Teams' speed dial empty state (Nova speed dial): its
            // avatar-add-multiple illustration 20rem (200) tall with 3rem
            // under it, the text bold at 75% of the pane with 1rem under.
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 200; height: 200
                source: "../assets/illustrations/avatar-add-multiple-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard.svg"
                sourceSize: Qt.size(400, 400)
                fillMode: Image.PreserveAspectFit
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Add to speed dial icon")
            }
            Item { width: 1; height: 30 }
            Text {
                width: 270; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: qsTr("Add people to speed dial for quick access.")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.text
            }
            Item { width: 1; height: 10 }
            Rectangle {
                id: hcFill13
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 31; radius: theme.radius
                color: abh.hovered ? theme.rowHover : theme.input
                border.color: theme.stroke
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-add-20"; size: 16; color: theme.onFill(hcFill13, theme.text) }
                    Text { text: qsTr("Add"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill13, theme.text) }
                }
                HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.addingSpeedDial = true; addField.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Add", "calling:kdky0ihug")
            }
        }
    }
    // Intelligent call delegation's pane, in speed dial's place.
    PaPane {
        id: paPane
        visible: root.paOpen && root.paEligible
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 360
        props: root.synced.props || {}
        mt: root.mt
        onClosed: root.paOpen = false
        onOpenSettings: id => root.openSettings(id)
    }
    UnparkDialog { id: unparkDialog }
    function openUnparkForTest() { unparkDialog.start() }
    function closeUnparkForTest() { unparkDialog.close() }

}
