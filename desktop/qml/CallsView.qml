import QtQuick
import QtQuick.Controls.Basic

// The Calls app, laid out as Teams desktop's (measured at 1x): a header
// with the Calls tile, the Personal tab and View contacts; then three
// panes: dial (find someone and call), History, and Speed dial (or a
// call's Details while one is open).
//
// History as Teams' call history table (calls-main-app, read on winpc
// 2026-11-27 with the same account): each row is named as Teams names it
// (a group call by its chat's topic, else its other people; a call with
// one person by them), says Outgoing / Incoming / Missed incoming ("… from
// <caller>" on a group call), and has the time or date with the duration
// under it. Hovering shows ··· (and Call on a 1:1 row); clicking opens
// Details.
Item {
    id: root
    property var calls: []
    /// People search results for the dial box ([{id, name, mail, job_title}]).
    property var people: []
    /// Your MRI (Teams shows "you" where the log names you).
    property string myMri: ""
    /// A person's presence by MRI (empty when unknown).
    property var presenceFor: function(mri) { return "" }
    /// Whether a person is already one of your contacts (Teams then leaves
    /// out Add contact).
    property var isContact: function(mri) { return false }
    signal openChatWith(string mri, string name)
    signal callPerson(string oid, string name)
    signal searchPeople(string query)
    /// A group call's chat (by thread), a 1:1 chat with `mri`, or (a group
    /// call outside a chat) a new chat with its people ([{mri, name}]).
    signal openChat(string mri, string name, string threadId, var people)
    /// Call back: the person, or the group call's chat.
    signal startCall(string mri, string name, string threadId, bool video)
    signal quickMessage(string mri, string name, string threadId, string text)
    signal addContact(var person)
    signal showOrg(string mri)
    signal toast(string text)

    /// The type filter: "" (Teams' All), missed, incoming, outgoing or
    /// voicemail.
    property string filter: ""
    readonly property var filterLabels: ({
        "": qsTr("All", "calling:kd8zny4lf"), missed: qsTr("Missed", "calling:k7xmrv4yl"), incoming: qsTr("Incoming", "calling:k2j3ykqvs"),
        outgoing: qsTr("Outgoing", "calling:kbaldu462"), voicemail: qsTr("Voicemail", "calling:k936zg0bf")
    })
    /// Filter mode (Teams' Filter button): the name box and its type.
    property bool filtering: false
    property string nameFilter: ""
    property string filterType: ""
    readonly property var shown: calls.filter(c => {
        const t = root.filtering ? root.filterType : root.filter
        if (t === "missed" && !root.isMissed(c)) return false
        if (t === "incoming" && !(c.direction === "incoming" && !root.isMissed(c))) return false
        if (t === "outgoing" && c.direction !== "outgoing") return false
        // (no voicemail in the Calls history without Teams Phone)
        if (t === "voicemail") return false
        if (root.filtering && root.nameFilter.trim()) {
            // Teams matches the person the call resolves to (not a group
            // call's chat name), ignoring spaces, brackets, - and +.
            const strip = s => String(s || "").toLocaleLowerCase().replace(/[ ()\-+]/g, "")
            if (!c.peer_name) return false
            if (strip(c.peer_name).indexOf(strip(root.nameFilter.trim())) < 0) return false
        }
        return true
    })
    property bool historyOpen: true
    property bool speedDialShown: true
    // Speed dial: people you call often (kept on this device).
    property var speedDial: { try { return JSON.parse(backend.setting("speedDial") || "[]") } catch (e) { return [] } }
    function saveSpeedDial(list) { speedDial = list; backend.setSetting("speedDial", JSON.stringify(list)) }
    property bool addingSpeedDial: false
    /// The call whose Details are open (its message id), "" for none.
    property string selectedId: ""
    readonly property var selected: selectedId ? (calls.find(c => c.message_id === selectedId) || null) : null

    function isMissed(c) { return c.direction === "incoming" && String(c.state).toLowerCase() === "missed" }
    function kind(c) { return isMissed(c) ? "missed" : c.direction }
    function oidOf(mri) { return (mri || "").replace(/^8:orgid:/, "") }
    /// Teams' duration (durationInMs as whole seconds, cut off, not rounded):
    /// none under a second, and none on a missed call.
    function duration(c) {
        if (isMissed(c) || !c.duration_ms || c.duration_ms < 1000) return ""
        // "1h 5m" (no minutes when 0), "5m 3s", "3s"
        // (call_history_call_duration_long_mf / _short_mf).
        return backend.durationText("history", Math.floor(c.duration_ms / 1000))
    }
    /// Teams' friendly date (438547): the time today, Yesterday, the
    /// weekday after the day eight days ago (Teams showed Saturday for six
    /// days ago and the date for eight), else the date.
    function when(iso) {
        const d = new Date(iso), now = new Date()
        if (d.toDateString() === now.toDateString()) return theme.time(d)
        const y = new Date(now); y.setDate(now.getDate() - 1)
        if (d.toDateString() === y.toDateString()) return qsTr("Yesterday", "framework:k94p81d45")
        const week = new Date(now); week.setDate(now.getDate() - 8); week.setHours(23, 59, 59, 999)
        if (d > week) return theme.fmtDate(d, "dddd")
        return theme.date(d)
    }
    /// A group call's people: the others (Teams' participantList).
    function people_(c) { return c.participants || [] }
    /// Teams' name-length limit for a group call's people (446636), by the
    /// history pane's width breakpoints.
    function nameLimit(w) {
        return w >= 1680 ? 110 : w >= 1440 ? 77 : w >= 1280 ? 68 : w >= 720 ? 60 : w >= 640 ? 50 : w >= 480 ? 25 : 10
    }
    /// The row's name and its full form (519822 YD / 185731): a group call
    /// by its chat's topic, its one other person, or their given names
    /// while they fit the limit, then ", +N".
    function names(c, w) {
        const unknown = qsTr("Unknown user", "calling:kbs1wcsq5")
        if (!c.is_group) { const n = c.peer_name || unknown; return { display: n, title: n } }
        if (c.title) return { display: c.title, title: c.title }
        const ps = people_(c)
        if (ps.length === 1) { const n = ps[0].name || unknown; return { display: n, title: n } }
        const limit = nameLimit(w)
        let display = "", title = "", over = 0
        ps.forEach((p, i) => {
            const first = p.given || p.name || unknown, full = p.name || unknown
            const last = i === ps.length - 1
            if (over || display.length > limit || (i && (display + ", " + first).length > limit)) {
                title += (last ? " and " : ", ") + full; over += 1; return
            }
            if (display) { display += ", " + first; title += (last ? " and " : ", ") + full }
            else { display = first; title = full }
        })
        if (over) display += ", +" + over
        return { display: display, title: title }
    }
    /// The second line (519822 Hi): "Transferred by …" on a call someone
    /// transferred to you; else Outgoing, Incoming, Missed incoming, a group
    /// call's "… from <caller>".
    function description(c) {
        if (c.transferor_mri) {
            const by = c.transferor_name || qsTr("Unknown user", "calling:kbs1wcsq5")
            return isMissed(c) ? qsTr("Missed transfer by %1", "calling:ka1jmib24").arg(by) : qsTr("Transferred by %1", "calling:k35zdx258").arg(by)
        }
        const caller = c.is_group ? (c.originator_name || "") : ""
        if (c.direction === "outgoing") return qsTr("Outgoing", "calling:kbaldu462")
        if (isMissed(c)) return caller ? qsTr("Missed incoming from %1", "calling:k6vhphwyh").arg(caller) : qsTr("Missed incoming", "calling:k36wdsx6g")
        return caller ? qsTr("Incoming from %1", "calling:k232pknp6").arg(caller) : qsTr("Incoming", "calling:k2j3ykqvs")
    }
    function icon(c) { return isMissed(c) ? "call-missed-16" : c.direction === "outgoing" ? "call-outbound-16" : "call-inbound-16" }
    /// Who the pictures show: a group call's others, else the person.
    function faces(c) {
        if (c.is_group && people_(c).length > 0) return people_(c).map(p => ({ mri: p.mri, name: p.name || "?" }))
        return [{ mri: c.peer_mri || "", name: c.peer_name || "?" }]
    }
    function isSelf(c) { return !!root.myMri && c.peer_mri === root.myMri }
    /// The person (or chat) Call back, Chat and the Details buttons reach.
    function chatTarget(c) {
        return c.is_group ? { mri: "", name: names(c, history.width).title, thread: c.thread_id || "", people: people_(c) }
            : { mri: c.peer_mri || "", name: c.peer_name || "", thread: "", people: [] }
    }
    function openDetails(c) {
        root.selectedId = c.message_id
        if (c.unread && c.activity_id) backend.markCallRead(c.activity_id)
    }
    // The row's ··· menu (Teams' call history row menu jt): a 1:1 row has
    // Call back, Chat, Remove from view, Add to speed dial, Add contact and
    // Report call; a group call's Chat, Remove from view and Report call.
    function menuItems(c) {
        const its = []
        if (!c.is_group && c.peer_mri && !isSelf(c)) its.push({ key: "callback", label: qsTr("Call back", "calling:k5hbq9mjl") })
        its.push({ key: "chat", label: qsTr("Chat", "calling:kbjiypjsi") })
        its.push({ key: "remove", label: qsTr("Remove from view", "calling:k7kzq6d1n") })
        if (!c.is_group && c.peer_mri && !isSelf(c)) {
            if (!root.speedDial.some(s => s.id === oidOf(c.peer_mri))) its.push({ key: "speeddial", label: qsTr("Add to speed dial", "calling:kblargjnx") })
            if (!root.isContact(c.peer_mri)) its.push({ key: "contact", label: qsTr("Add contact", "calling:k8q1n3jdg") })
        }
        its.push({ key: "report", label: qsTr("Report call", "calling:kjwuxd0j") })
        return its
    }
    function act(key, c) {
        const t = chatTarget(c)
        if (key === "callback") root.startCall(t.mri, t.name, t.thread, false)
        else if (key === "chat") root.openChat(t.mri, t.name, t.thread, t.people)
        else if (key === "remove") { if (root.selectedId === c.message_id) root.selectedId = ""; backend.removeCall(c.message_id) }
        else if (key === "speeddial") root.saveSpeedDial(root.speedDial.concat([{ id: oidOf(c.peer_mri), name: c.peer_name }]))
        else if (key === "contact") root.addContact({ mri: c.peer_mri, name: c.peer_name })
        else if (key === "report") reportDialog.start(c)
    }

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
            id: hcFillMore
            x: parent.width - 81; y: 15; width: 32; height: 31; radius: theme.radius
            color: mot.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFillMore, theme.textStrong) }
            HoverHandler { id: mot; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: callsMore.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More calls options")
            MenuPopup {
                id: callsMore
                width: 240
                y: parent.height + 4
                items: [{ label: qsTr("Pick up a parked call"), icon: "call-park-20" }]
                onPicked: i => { if (i === 0) unparkDialog.start() }
            }
        }
        Rectangle {
            id: hcFill3
            x: parent.width - 43; y: 15; width: 32; height: 31; radius: theme.radius
            color: sdt.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "people"; size: 20; color: theme.onFill(hcFill3, root.speedDialShown ? theme.brand : theme.textStrong) }
            HoverHandler { id: sdt; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.speedDialShown = !root.speedDialShown }
            Accessible.role: Accessible.Button
            Accessible.name: root.speedDialShown ? qsTr("Close speed dial") : qsTr("Open speed dial")
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
                Text { visible: !nameField.text; text: qsTr("Type a name"); color: theme.textTertiary; font: nameField.font }
                Accessible.name: qsTr("Type a name")
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
                        id: hcFill4
                        required property var modelData
                        width: pplCol.width; height: 44; radius: theme.radius
                        color: ph.hovered ? theme.rowHover : "transparent"
                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                        Column {
                            x: 46; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill4, theme.text) }
                            Text { text: parent.parent.modelData.mail || parent.parent.modelData.job_title || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill4, theme.textSecondary) }
                        }
                        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { dial.chosen = parent.modelData; nameField.text = parent.modelData.name } }
                    }
                }
            }
        }
        Rectangle {
            id: hcFill5
            x: 16; y: 82; width: 347; height: 32; radius: theme.radius
            readonly property bool ready: dial.chosen !== null
            color: ready ? (cbh.hovered ? theme.brandHover : theme.brandFill) : (theme.dark ? theme.hc("#2E2E2E", "#000000") : theme.hc("#F0F0F0", "#000000"))
            Row {
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 16; color: theme.onFill(hcFill5, parent.parent.ready ? "white" : theme.disabled) }
                Text { text: qsTr("Call", "calling:ka2l734dq"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill5, parent.parent.ready ? "white" : theme.disabled) }
            }
            HoverHandler { id: cbh; cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.ready; onTapped: root.callPerson(dial.chosen.id, dial.chosen.name) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Call", "calling:ka2l734dq")
        }
        // The speaker calls use, as Teams shows at the bottom of this pane.
        Rectangle {
            id: deviceRow
            x: 16; y: parent.height - 52; height: 36; radius: theme.radius
            width: Math.min(300, deviceText.implicitWidth + 64)
            color: dvh.hovered ? theme.rowHover : "transparent"
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "headset-20"; size: 20; color: theme.onFill(deviceRow, theme.textStrong) }
            Text {
                id: deviceText
                x: 36; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 230); elide: Text.ElideRight
                text: { const d = backend.setting("speakerDevice"); return d && d !== "default" ? d : qsTr("Default speaker") }
                font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(deviceRow, theme.text)
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(deviceRow, theme.textStrong) }
            HoverHandler { id: dvh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { deviceMenu.devices = JSON.parse(backend.audioDevices()).outputs; deviceMenu.open() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Speaker: %1").arg(deviceText.text)
            MenuPopup {
                id: deviceMenu
                property var devices: []
                width: 320
                y: -height - 4
                items: [{ label: qsTr("Default speaker") }].concat(devices.map(d => ({ label: d, checked: backend.setting("speakerDevice") === d })))
                onPicked: i => {
                    const v = i === 0 ? "default" : devices[i - 1]
                    backend.setSetting("speakerDevice", v)
                    deviceText.text = i === 0 ? qsTr("Default speaker") : v
                }
            }
        }
    }

    // A call's pictures: one person, or a group call's first two people
    // side by side in one circle (Teams' group avatar: each picture's
    // middle, a 1 px gap between).
    component CallFaces: Item {
        id: cf
        property var faces: []
        property int size: 32
        property string presence: ""
        property color background: theme.surface
        width: size; height: size
        Avatar {
            visible: cf.faces.length < 2
            size: cf.size
            name: cf.faces.length ? cf.faces[0].name : "?"
            photoId: cf.faces.length ? cf.faces[0].mri : ""
            presence: cf.presence
        }
        Repeater {
            model: cf.faces.length >= 2 ? 2 : 0
            Item {
                required property int index
                x: index === 0 ? 0 : cf.size / 2 + 0.5
                width: cf.size / 2 - 0.5; height: cf.size
                clip: true
                Avatar {
                    x: -cf.size / 4 + (parent.index === 0 ? 0 : -0.5)
                    size: cf.size; square: true; squareRadius: 0; ring: false
                    name: cf.faces[parent.index].name
                    photoId: cf.faces[parent.index].mri
                }
            }
        }
        RoundedCorners {
            visible: cf.faces.length >= 2
            anchors.fill: parent
            radius: cf.size / 2
            background: cf.background
        }
    }

    // History
    Item {
        id: history
        anchors { top: header.bottom; bottom: parent.bottom; left: dial.right; right: sidePane.visible ? sidePane.left : parent.right }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Item {
            id: histHead
            width: parent.width; height: 48
            Rectangle {
                id: hcFill6
                visible: !root.filtering
                x: 17; y: 8; width: 88; height: 35; radius: theme.radius
                color: hhh.hovered ? theme.rowHover : "transparent"
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: root.historyOpen ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.onFill(hcFill6, theme.text) }
                Text { x: 26; anchors.verticalCenter: parent.verticalCenter; text: qsTr("History"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.onFill(hcFill6, theme.text) }
                HoverHandler { id: hhh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.historyOpen = !root.historyOpen }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("History")
            }
            // The type filter, as Teams' brand pill: its menu lists the
            // other choices (All, Missed, Incoming, Outgoing, Voicemail
            // without the current one).
            Rectangle {
                id: hcFill7
                visible: !root.filtering
                anchors.right: filterButton.left; anchors.rightMargin: 12; y: 13
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
                    readonly property var keys: ["", "missed", "incoming", "outgoing", "voicemail"].filter(k => k !== root.filter)
                    items: keys.map(k => ({ label: root.filterLabels[k] }))
                    onPicked: i => root.filter = keys[i]
                }
            }
            Rectangle {
                id: filterButton
                visible: !root.filtering
                anchors.right: parent.right; anchors.rightMargin: 16; y: 8
                width: 32; height: 32; radius: theme.radius
                color: fbh.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "filter-20"; size: 20; color: theme.onFill(filterButton, theme.textStrong) }
                HoverHandler { id: fbh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.filtering = true; root.filterType = ""; nameBoxField.text = ""; nameBoxField.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Filter", "calling:kbw1hyjb6")
            }
            // Filter mode: "Filter by name or number", its type (··· or the
            // chosen type's chip) and X.
            Rectangle {
                id: filterBox
                visible: root.filtering
                x: 20; y: 8; height: 32; radius: theme.radius
                width: parent.width - 20 - (typeChip.visible ? typeChip.width + 8 : 40) - 48
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF")
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: nameBoxField.activeFocus ? 2 : 0; radius: 1; color: theme.brand }
                TextInput {
                    id: nameBoxField
                    x: 12; width: parent.width - 24
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                    clip: true
                    onTextChanged: root.nameFilter = text
                    Keys.onEscapePressed: closeFilter.go()
                    Text { visible: !nameBoxField.text; text: qsTr("Filter by name or number", "calling:k24cfd7mn"); color: theme.textSecondary; font: nameBoxField.font }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Filter by name or number", "calling:k24cfd7mn")
                }
            }
            Rectangle {
                id: typeMore
                visible: root.filtering && !root.filterType
                anchors.left: filterBox.right; anchors.leftMargin: 8; y: 8
                width: 32; height: 32; radius: theme.radius
                color: tmh.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(typeMore, theme.brand) }
                HoverHandler { id: tmh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: typeMenu.open() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("More actions", "calling:k8bpyqfoc")
                MenuPopup {
                    id: typeMenu
                    width: 160; y: parent.height + 4
                    x: parent.width - width
                    readonly property var keys: ["outgoing", "incoming", "missed", "voicemail"]
                    items: keys.map(k => ({ label: root.filterLabels[k] }))
                    onPicked: i => root.filterType = keys[i]
                }
            }
            Rectangle {
                id: typeChip
                visible: root.filtering && !!root.filterType
                anchors.left: filterBox.right; anchors.leftMargin: 4; y: 12
                height: 24; radius: 12
                width: chipText.implicitWidth + 40
                color: theme.pick("#EBEBEB", "#3D3D3D", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF")
                Text { id: chipText; x: 10; anchors.verticalCenter: parent.verticalCenter; text: root.filterLabels[root.filterType] || ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(typeChip, theme.text) }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-16"; size: 16; color: theme.onFill(typeChip, theme.text) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.filterType = "" }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Remove filter %1", "calling:kvl9rc3x").arg(root.filterLabels[root.filterType] || "")
            }
            Rectangle {
                id: closeFilter
                visible: root.filtering
                anchors.right: parent.right; anchors.rightMargin: 16; y: 8
                width: 32; height: 32; radius: theme.radius
                color: cfh.hovered ? theme.rowHover : "transparent"
                function go() { root.filtering = false; root.filterType = ""; nameBoxField.text = "" }
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeFilter, theme.textStrong) }
                HoverHandler { id: cfh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: closeFilter.go() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close", "calling:k36hz6ymy")
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
                required property int index
                function openMenu() { rowMenu.open() }
                function closeMenu() { rowMenu.close() }
                readonly property string k: root.kind(modelData)
                readonly property bool missed: k === "missed"
                readonly property bool unread: missed && !!modelData.unread
                readonly property bool open: root.selectedId === modelData.message_id
                readonly property bool hot: rh.hovered || rowMenu.opened || root.testHover === index
                readonly property var label: root.names(modelData, history.width)
                readonly property bool oneToOne: !modelData.is_group && !!modelData.peer_mri && !root.isSelf(modelData)
                width: list.width; height: 51
                color: hot ? theme.rowHover : open ? theme.pick("#F0F0F0", "#2E2E2E", "#1AEBFF") : "transparent"
                // An unread missed call's red dot.
                Rectangle {
                    visible: row.unread
                    x: 9; anchors.verticalCenter: parent.verticalCenter
                    width: 4; height: 4; radius: 2
                    color: theme.redForeground1
                }
                CallFaces {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    size: 32
                    faces: root.faces(row.modelData)
                    // (a single picture has the person's presence, as Teams)
                    presence: root.faces(row.modelData).length === 1 && !root.isSelf(row.modelData) ? root.presenceFor(root.faces(row.modelData)[0].mri) : ""
                    background: row.color.a > 0 ? row.color : theme.surface
                }
                Column {
                    x: 64; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 64 - (row.hot ? (row.oneToOne ? 130 : 60) : 100)
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: row.label.display
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: row.unread ? Font.Bold : Font.Normal
                        color: theme.onFill(row, theme.text)
                    }
                    Row {
                        width: parent.width
                        spacing: 4
                        FluentIcon {
                            anchors.verticalCenter: parent.verticalCenter; size: 16
                            name: root.icon(row.modelData)
                            color: theme.onFill(row, row.missed ? theme.redForeground1 : theme.textSecondary)
                        }
                        Text {
                            width: parent.width - 20; elide: Text.ElideRight
                            text: root.description(row.modelData)
                            font.family: theme.font; font.pixelSize: theme.small; font.weight: row.unread ? Font.Bold : Font.Normal
                            color: theme.onFill(row, row.missed ? theme.redForeground1 : theme.textSecondary)
                        }
                    }
                }
                // The time or date, the duration under it.
                Column {
                    visible: !row.hot
                    anchors.right: parent.right; anchors.rightMargin: 30; anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.right: parent.right
                        text: root.when(row.modelData.start_time)
                        font.family: theme.font; font.pixelSize: theme.small; font.weight: row.unread ? Font.Bold : Font.Normal
                        color: theme.onFill(row, theme.textStrong)
                    }
                    Text {
                        anchors.right: parent.right
                        visible: text.length > 0
                        text: root.duration(row.modelData)
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.onFill(row, theme.textStrong)
                    }
                }
                // (not when the press was on ··· or Call)
                TapHandler { onTapped: if (!mah.hovered && !cbh2.hovered) root.openDetails(row.modelData) }
                // On hover: ··· (and Call on a 1:1 row).
                Row {
                    visible: row.hot
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Rectangle {
                        id: hcFill8
                        width: 32; height: 32; radius: theme.radius
                        anchors.verticalCenter: parent.verticalCenter
                        color: mah.hovered || rowMenu.opened ? theme.selected : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill8, mah.hovered || rowMenu.opened ? theme.brand : theme.textStrong) }
                        HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rowMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More actions", "calling:k8bpyqfoc")
                        MenuPopup {
                            id: rowMenu
                            width: 190
                            x: parent.width - width; y: parent.height + 2
                            readonly property var entries: root.menuItems(row.modelData)
                            items: entries.map(e => ({ label: e.label }))
                            onPicked: i => root.act(entries[i].key, row.modelData)
                        }
                    }
                    Rectangle {
                        id: hcFill9
                        visible: row.oneToOne
                        width: 64; height: 24; radius: theme.radius
                        anchors.verticalCenter: parent.verticalCenter
                        color: cbh2.hovered ? theme.rowHover : theme.input
                        border.color: theme.stroke
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-20"; size: 16; color: theme.onFill(hcFill9, theme.text) }
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
                Accessible.name: [row.label.display, root.description(row.modelData), root.when(row.modelData.start_time), root.duration(row.modelData)].filter(s => s).join(", ")
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

    // The right pane: a call's Details while one is open, else Speed dial.
    Item {
        id: sidePane
        visible: root.speedDialShown || !!root.selected
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 360
    }

    // Details (Teams' history item summary): the call's people and their
    // buttons (Chat, Organization on a 1:1 call, Video call, Audio call),
    // Send a quick message, then the call's timeline card.
    Item {
        id: details
        visible: !!root.selected
        anchors.fill: sidePane
        readonly property var c: root.selected
        readonly property var label: c ? root.names(c, history.width) : ({ display: "", title: "" })
        readonly property bool oneToOne: !!c && !c.is_group
        // The buttons as Teams enables them (800087): no chat without
        // someone to chat with; no calls to yourself.
        readonly property bool self_: !!c && root.isSelf(c)
        readonly property bool canChat: !!c && (c.is_group ? (c.participants || []).length > 0 : !!c.peer_mri)
        // (a group call outside a chat has no conversation to call or write
        // into from here: its Chat starts a new chat with its people; a
        // meeting's chat is joined from the meeting, not rung)
        readonly property bool canCall: !!c && !self_ && (c.is_group ? (c.participants || []).length > 0 && !!c.thread_id && !String(c.thread_id).startsWith("19:meeting_") : !!c.peer_mri)
        // Teams' quick message: hidden on a 1:1 call to yourself and in a
        // chat you're no longer in.
        // (on a group call the log may name you as its person; the message
        // goes to its chat, so that doesn't matter there)
        readonly property bool canMessage: canChat && (c.is_group ? !!c.thread_id && !!c.member : !self_)
        // A draft is for this call's person or chat only.
        onCChanged: quick.text = ""
        Text { x: 20; y: 15; text: qsTr("Details", "calling:k62e0gpus"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
        Rectangle {
            id: detClose
            x: parent.width - 48; y: 10; width: 32; height: 32; radius: theme.radius
            color: dch.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(detClose, theme.textStrong) }
            HoverHandler { id: dch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.selectedId = "" }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Details, close", "calling:k16hlkex8")
        }
        CallFaces {
            id: detFaces
            x: 20; y: 60
            size: 72
            faces: details.c ? root.faces(details.c) : []
            presence: details.oneToOne && !details.self_ ? root.presenceFor(details.c.peer_mri) : ""
        }
        Text {
            // (Teams wraps "OST Test 3, OST Test 2" after the comma, keeping
            // each name whole)
            x: 112; anchors.verticalCenter: detFaces.verticalCenter
            width: 150
            wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
            text: details.c && details.c.is_group && !details.c.title && (details.c.participants || []).length > 1
                ? details.c.participants.map(p => (p.name || qsTr("Unknown user", "calling:kbs1wcsq5")).replace(/ /g, "\u00a0")).join(", ") : details.label.display
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
        }
        Row {
            id: detButtons
            x: 14; y: 145; spacing: 0
            Repeater {
                model: [
                    { key: "chat", icon: "chat-20", label: qsTr("Show conversation", "calling:k1ktufzdp"), on: details.canChat, show: true },
                    { key: "org", icon: "org-20", label: qsTr("View organization", "calling:kbk5n6bov"), on: details.oneToOne && !details.self_ && !!(details.c && details.c.peer_mri), show: details.oneToOne },
                    { key: "video", icon: "video-20", label: qsTr("Video call", "messaging:k64tfj4by"), on: details.canCall, show: true },
                    { key: "call", icon: "call-20", label: qsTr("Audio call", "messaging:k3d71c6wb"), on: details.canCall, show: true }
                ].filter(b => b.show)
                Rectangle {
                    id: detBtn
                    required property var modelData
                    width: 32; height: 32; radius: theme.radius
                    color: dbh.hovered && modelData.on ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: detBtn.modelData.icon; size: 20; color: theme.onFill(detBtn, detBtn.modelData.on ? theme.textStrong : theme.disabled) }
                    HoverHandler { id: dbh; cursorShape: detBtn.modelData.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        enabled: detBtn.modelData.on
                        onTapped: {
                            const t = root.chatTarget(details.c)
                            if (detBtn.modelData.key === "chat") root.openChat(t.mri, t.name, t.thread, t.people)
                            else if (detBtn.modelData.key === "org") root.showOrg(details.c.peer_mri)
                            else root.startCall(t.mri, t.name, t.thread, detBtn.modelData.key === "video")
                        }
                    }
                    ToolTip.visible: dbh.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.ignored: false
                }
            }
        }
        Item {
            id: quickRow
            visible: details.canMessage
            x: 20; y: 188; width: parent.width - 40; height: 32
            Rectangle {
                id: quickBox
                width: parent.width - 40; height: 32; radius: theme.radius
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF")
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: quick.activeFocus ? 2 : 0; color: theme.brand }
                TextInput {
                    id: quick
                    x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    Keys.onReturnPressed: quickSend.go()
                    Text { visible: !quick.text; text: qsTr("Send a quick message", "calling:kburm40mp"); font: quick.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Send a quick message", "calling:kburm40mp")
                }
            }
            Rectangle {
                id: quickSend
                anchors.right: parent.right; width: 32; height: 32; radius: theme.radius
                color: qsh.hovered && quick.text.trim() ? theme.rowHover : "transparent"
                function go() {
                    const t = quick.text.trim()
                    if (!t || !details.c) return
                    const target = root.chatTarget(details.c)
                    quick.text = ""
                    root.quickMessage(target.mri, target.name, target.thread, t)
                }
                FluentIcon { anchors.centerIn: parent; name: "send-20"; size: 20; color: theme.onFill(quickSend, quick.text.trim() ? theme.brand : theme.textSecondary) }
                HoverHandler { id: qsh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: quickSend.go() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Send")
            }
        }
        Rectangle {
            id: detDivider
            x: 20; y: details.canMessage ? 232 : 192; width: parent.width - 40; height: 1; color: theme.dividerSoft
        }
        // The timeline card: the day, the call (direction, time, who made
        // or answered it), when it ended, and its total time.
        Rectangle {
            id: timeline
            x: 20; y: detDivider.y + 22; width: parent.width - 40
            height: tlCol.implicitHeight + 16
            radius: 4
            color: theme.surface
            border.color: theme.dividerSoft
            readonly property var c: details.c
            readonly property bool missed: !!c && root.isMissed(c)
            readonly property bool ended: !!c && !missed && (c.duration_ms || 0) >= 1000
            readonly property string who: !c || missed ? "" : c.direction === "outgoing" ? qsTr("Made by you", "calling:k4mnmp1a7") : qsTr("Answered by you", "calling:k9ru9m10s")
            Column {
                id: tlCol
                x: 12; y: 8; width: parent.width - 24
                Item {
                    width: parent.width; height: 38
                    Text { anchors.verticalCenter: parent.verticalCenter; text: timeline.c ? theme.longDate(new Date(timeline.c.start_time)) : ""; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.text }
                }
                Item {
                    width: parent.width; height: 32
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: timeline.c ? root.icon(timeline.c) : ""; size: 16; color: timeline.missed ? theme.redForeground1 : theme.textStrong }
                    Text {
                        x: 22; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 110; elide: Text.ElideRight
                        text: timeline.c ? root.description(timeline.c) : ""
                        font.family: theme.font; font.pixelSize: theme.base; color: timeline.missed ? theme.redForeground1 : theme.text
                    }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: timeline.c ? theme.time(new Date(timeline.c.start_time)) : ""; font.family: theme.font; font.pixelSize: theme.base; color: timeline.missed ? theme.redForeground1 : theme.text }
                }
                Item {
                    visible: !!timeline.who
                    width: parent.width; height: 28
                    Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: timeline.who; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
                }
                Item {
                    visible: timeline.ended
                    width: parent.width; height: 32
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-end"; size: 16; color: theme.textStrong }
                    Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Call ended", "calling:kdi32uxe1"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: timeline.c && timeline.c.end_time ? theme.time(new Date(timeline.c.end_time)) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                Rectangle { visible: timeline.ended; width: parent.width; height: 1; color: theme.dividerSoft }
                Item {
                    visible: timeline.ended
                    width: parent.width; height: 40
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Total call time", "calling:k8fmyxpa1"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: timeline.c ? root.duration(timeline.c) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
            }
        }
    }
    // Speed dial
    Item {
        id: speedPane
        visible: root.speedDialShown && !root.selected
        anchors.fill: sidePane
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
            spacing: 12
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "people"; size: 48; color: theme.brand }
            Text {
                width: 260; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: qsTr("Add people to speed dial for quick access.")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
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
    // Report call: Teams' "Report a concern" (report-call-dialog, read on
    // winpc 2026-11-27): 600 wide, radius 8, content 25 in; the title
    // (20/28 semibold) and Close; the call as a card (its picture, name,
    // direction, date and duration on #F5F5F5); "Enter an explanation
    // (optional)" (at most 250 characters, a brand underline, the counter
    // under it); Teams' notice; Cancel and Report. Sending says "Report was
    // sent".
    Popup {
        id: reportDialog
        property var call: null
        property bool sending: false
        property bool failed: false
        function start(c) { call = c; sending = false; failed = false; why.text = ""; open(); why.forceActiveFocus() }
        modal: true; focus: true
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: 600; padding: 0
        height: repCol.implicitHeight + 50
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Connections {
            target: backend
            function onCallActionDone(op, ok) {
                if (op !== "report" || !reportDialog.sending) return
                reportDialog.sending = false
                if (!ok) { reportDialog.failed = true; return }
                reportDialog.close()
                root.toast(qsTr("Report was sent", "calling:k8i8e9itj"))
            }
        }
        Column {
            id: repCol
            x: 25; y: 25; width: 550; spacing: 0
            Item {
                width: parent.width; height: 44
                Text { height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Report a concern", "calling:kdl06hw7q"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Rectangle {
                    id: repClose
                    anchors.right: parent.right; y: -2; width: 32; height: 32; radius: 4
                    color: rch.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(repClose, theme.textStrong) }
                    HoverHandler { id: rch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: reportDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close", "calling:k36hz6ymy")
                }
            }
            Rectangle {
                id: repCard
                width: parent.width; height: 64; radius: 4
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF")
                readonly property var c: reportDialog.call
                CallFaces {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    size: 32
                    faces: repCard.c ? root.faces(repCard.c) : []
                    background: repCard.color
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56 - 110
                    Text { width: parent.width; elide: Text.ElideRight; text: repCard.c ? root.names(repCard.c, history.width).display : ""; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                    Row {
                        spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: repCard.c ? root.icon(repCard.c) : ""; color: theme.textSecondary }
                        Text { text: repCard.c ? root.description(repCard.c) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
                    }
                }
                Column {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.right: parent.right; text: repCard.c ? root.when(repCard.c.start_time) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
                    Text { anchors.right: parent.right; visible: text.length > 0; text: repCard.c ? root.duration(repCard.c) : ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
                }
            }
            Item { width: 1; height: 16 }
            Rectangle {
                width: parent.width; height: 100; radius: 4
                color: theme.surface
                border.color: theme.hc("transparent", "#FFFFFF")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: why.activeFocus ? 2 : 1; color: why.activeFocus ? theme.brand : theme.textStrong }
                TextEdit {
                    id: why
                    x: 12; y: 10; width: parent.width - 24; height: parent.height - 20
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    onTextChanged: if (text.length > 250) { const p = cursorPosition; text = text.slice(0, 250); cursorPosition = Math.min(p, 250) }
                    Text { visible: !why.text; text: qsTr("Enter an explanation (optional)", "calling:kixgls6v"); font: why.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Enter an explanation (optional)", "calling:kixgls6v")
                }
            }
            Item { width: 1; height: 8 }
            Text { height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("%1/%2 maximum characters", "calling:k75hylk33").arg(why.text.length).arg(250); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
            Item { width: 1; height: 20 }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("Information about this call will be shared with Microsoft to improve the accuracy of detection, and to enhance protection for you and our services against suspicious calls.", "calling:k96fgoyli")
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            Row {
                visible: reportDialog.failed
                topPadding: 8; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "warning-12-filled"; size: 16; color: theme.redForeground1 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Failed to submit report. Please try again.", "calling:k8r0elqd8"); font.family: theme.font; font.pixelSize: theme.base; color: theme.redForeground1 }
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                Rectangle {
                    id: repCancel
                    width: 96; height: 32; radius: 4
                    color: rcah.hovered && !reportDialog.sending ? theme.menuHover : theme.surface; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: qsTr("Cancel", "calling:k9przwwus"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(repCancel, reportDialog.sending ? theme.disabled : theme.text) }
                    HoverHandler { id: rcah; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !reportDialog.sending; onTapped: reportDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel", "calling:k9przwwus")
                }
                Rectangle {
                    id: repSend
                    width: 96; height: 32; radius: 4
                    color: reportDialog.sending ? theme.bgDisabled : rsh.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Report", "calling:k3325pm06"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(repSend, reportDialog.sending ? theme.disabled : "white") }
                    HoverHandler { id: rsh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: !reportDialog.sending && !!reportDialog.call
                        onTapped: {
                            const c = reportDialog.call
                            reportDialog.sending = true; reportDialog.failed = false
                            // Teams names the other person, none on a group call.
                            backend.reportCall(c.message_id, c.is_group ? "" : (c.peer_mri || ""), why.text)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Report", "calling:k3325pm06")
                }
            }
        }
    }
    UnparkDialog { id: unparkDialog }
    function openUnparkForTest() { unparkDialog.start() }

    // --calls-history-test (Main.qml): the rows as shown, and the states to capture.
    property int testHover: -1
    function rowsForTest() {
        return shown.map(c => [names(c, history.width).display, description(c), when(c.start_time), duration(c), c.unread ? "unread" : "", c.message_id].filter(s => s).join(" | "))
    }
    property var testRow: null
    function menuForTest(i) { testHover = i; list.positionViewAtIndex(i, ListView.Contain); testRow = list.itemAtIndex(i); if (testRow) testRow.openMenu(); return menuItems(shown[i]).map(e => e.label) }
    function closeMenusForTest() { if (testRow) testRow.closeMenu(); testRow = null; testHover = -1 }
    function detailsForTest(i) { openDetails(shown[i]) }
    function quickForTest() { return quick.text }
    function setQuickForTest(t) { quick.text = t }
    function sendQuickForTest() { quickSend.go() }
    function detailsButtonsForTest() { return { chat: details.canChat, call: details.canCall, message: details.canMessage } }
    function filterForTest(text, type) { filtering = true; nameBoxField.text = text; filterType = type }
    function unfilterForTest() { closeFilter.go() }
    function reportForTest(i) { reportDialog.start(shown[i]) }
    function closeReportForTest() { reportDialog.close() }
    function findForTest(re) { return shown.findIndex(c => new RegExp(re).test([names(c, history.width).display, description(c)].join(" | "))) }

}
