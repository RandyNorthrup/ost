import QtQuick
import QtQuick.Controls.Basic

// Add members to {team} (a team's menu ▸ Add member; Teams' dialog,
// measured on winpc 2026-11-09): 600 wide, padding 24, radius 8, 483 tall.
// - "Add members to {team}" (20/28 semibold); Teams' guidance (14/20, 543.5
//   wide) ending in "Learn about adding guests" (#4F52B2, underlined).
// - The picker 128.7 down (550.7 x 33.3, #F0F0F0, radius 4, padding 0 12,
//   "Type a name or email", a brand underline and a chevron while focused).
//   Typing searches people, groups and lists (searchV2, addToTeam); the
//   matches drop under it (padding 4, 50 tall rows: picture 32 at 12, the
//   name 14/20 with what was typed in bold at 60, the alias or the group's
//   address 12/16 #616161 under it). An e-mail address that matches nobody
//   offers "Add {email} as a guest?". People already in the team aren't
//   offered.
// - Picked ones line up under it (44.7 tall rows with a #E0E0E0 line:
//   picture 32 at 8, the name and its second line at 56, the role dropdown
//   Member / Owner, Members / Owners for a group, at 384.3, Remove at 501.6).
//   A group has an expand button after its name ("Expand the list with N
//   people") that swaps it for its people. A guest reads "Add name" (brand)
//   with the address under it and a "Guest" tag; Add name edits the name in
//   place (Cancel / Save).
// - Cancel and Add (96 x 31.3) at the bottom; Add once someone is picked.
// Adding sends Teams' bulkUpdateRoledMembers (people, a group's people) and
// inviteAndAddGuest (guests); "{n} of {m} members were added" when some
// couldn't be added.
Popup {
    id: dlg
    property string teamId: ""
    property string teamThread: ""
    property string teamName: ""
    property var members: []
    // The member step after creating a private channel (Teams' "Add members
    // to the {channel} channel": the team's members only, Skip / Add, 449.3
    // tall).
    property string channelId: ""
    property string channelName: ""
    readonly property bool channelMode: channelId.length > 0
    signal finished()
    // Picked: {key, mri, object_id, name, detail, mail, group, owner, people, guest, email}.
    property var staged: []
    property var results: []
    property string searched: ""
    property bool adding: false
    property var outcome: null
    readonly property string query: picker.text.trim()
    readonly property bool emailQuery: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(query)

    function startChannel(tid, thread, tname, chId, chName) {
        channelId = chId; channelName = chName
        startCommon(tid, thread, tname)
    }
    function start(tid, thread, tname) {
        channelId = ""; channelName = ""
        startCommon(tid, thread, tname)
    }
    function startCommon(tid, thread, tname) {
        teamId = tid; teamThread = thread; teamName = tname
        staged = []; results = []; searched = ""; adding = false; outcome = null; members = []
        picker.text = ""
        open()
        picker.forceActiveFocus()
        backend.channelAction("team-members-load", teamId, teamThread, "")
    }
    function excluded(c) {
        if (c.mri && members.indexOf(c.mri.toLowerCase()) >= 0) return true
        return staged.some(s => (c.mri && s.mri === c.mri) || (c.group && s.object_id === c.object_id))
    }
    function pick(c) {
        const item = Object.assign({ key: c.group ? "g:" + c.object_id : c.mri, owner: false, people: null, guest: false }, c)
        staged = staged.concat([item])
        if (c.group) backend.channelAction("group-people", teamId, teamThread, c.object_id)
        clearSearch()
    }
    function pickGuest(email) {
        staged = staged.concat([{ key: "e:" + email.toLowerCase(), guest: true, email: email, name: "", owner: false }])
        clearSearch()
    }
    function clearSearch() {
        picker.text = ""; results = []; searched = ""
        picker.forceActiveFocus()
    }
    function update(key, fields) {
        staged = staged.map(s => s.key === key ? Object.assign({}, s, fields) : s)
    }
    function expand(key) {
        const g = staged.find(s => s.key === key)
        if (!g || !g.people) return
        const people = g.people.filter(p => !excluded(p)).map(p => Object.assign({ key: p.mri, owner: false, people: null, guest: false }, p))
        const at = staged.indexOf(g)
        staged = staged.slice(0, at).concat(people, staged.slice(at + 1))
    }
    function add() {
        const users = []
        const seen = {}
        staged.forEach(s => {
            if (s.guest) return
            const list = s.group ? (s.people || []) : [s]
            list.forEach(p => {
                if (!p.mri || seen[p.mri] || members.indexOf(p.mri.toLowerCase()) >= 0) return
                seen[p.mri] = true
                users.push({ mri: p.mri, owner: s.owner })
            })
        })
        const guests = staged.filter(s => s.guest).map(s => ({ email: s.email, name: s.name }))
        adding = true
        if (channelMode) backend.channelAction("channel-add-members", teamId, teamThread, JSON.stringify({ channel: channelId, users: users }))
        else backend.channelAction("add-members", teamId, teamThread, JSON.stringify({ users: users, guests: guests }))
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: {
            if (!dlg.query) return
            backend.channelAction(dlg.channelMode ? "tag-member-search" : "add-member-search", dlg.teamId, dlg.teamThread, dlg.query)
        }
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            if (!dlg.opened) return
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== dlg.teamThread) return
            if (r.op === "team-members-load" && r.ok) dlg.members = r.data.members || []
            else if ((r.op === "add-member-search" || (r.op === "tag-member-search" && dlg.channelMode)) && r.ok && r.data.query.trim() === dlg.query) {
                dlg.searched = r.data.query
                // Team members (the channel step) come as {mri, name, mail, detail}.
                dlg.results = (r.data.people || []).map(c => c.object_id !== undefined ? c : Object.assign({ object_id: c.mri.replace(/^8:orgid:/, ""), group: false }, c)).filter(c => !dlg.excluded(c))
            } else if (r.op === "group-people" && r.ok) {
                dlg.staged = dlg.staged.map(s => s.group && s.object_id === r.data.group ? Object.assign({}, s, { people: r.data.people || [] }) : s)
            } else if (r.op === "channel-add-members") {
                dlg.adding = false
                if (r.ok) { dlg.close(); return }
                dlg.outcome = { requested: dlg.staged.length, added: 0, failed: dlg.staged.length }
            } else if (r.op === "add-members") {
                dlg.adding = false
                if (r.ok && r.data.failed === 0) { dlg.close(); return }
                dlg.outcome = r.ok ? r.data : { requested: dlg.staged.length, added: 0, failed: dlg.staged.length }
            }
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; height: channelMode ? 449.3 : 483; padding: 24
    onClosed: if (channelMode) finished()
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            x: 0.7; y: 0.7; width: 550
            elide: Text.ElideRight
            text: dlg.channelMode ? "Add members to the " + dlg.channelName + " channel" : "Add members to " + dlg.teamName
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            visible: dlg.channelMode
            x: 0.7; y: 36; width: 543.5
            text: "Start typing a name of a person you want to add to this private channel."
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            visible: !dlg.channelMode
            x: 0.7; y: 37.3; width: 543.5
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: "Start typing a name, distribution list, or security group to add to your team. You can also add people outside your organization as guests by typing their email addresses. People outside your org will get an email letting them know they've been added. <a href=\"https://support.microsoft.com/office/add-guests-to-a-team-in-teams-fccb4fa6-f864-4508-bdde-256e7384a14f\">Learn about adding guests</a>"
            linkColor: theme.brandForeground1
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }

        // The picker.
        Rectangle {
            id: box
            x: 0; y: dlg.channelMode ? 69.3 : 128.7; width: 550.7; height: 33.3; radius: 4
            color: theme.pick("#F0F0F0", "#141414")
            Rectangle {
                visible: picker.activeFocus
                anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
                color: theme.brand
            }
            TextInput {
                id: picker
                x: 12.7; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter
                enabled: !dlg.outcome
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                selectByMouse: true
                clip: true
                onTextChanged: {
                    dlg.results = []; dlg.searched = ""
                    if (text.trim()) debounce.restart(); else debounce.stop()
                }
                Keys.onEscapePressed: event => {
                    if (text) { text = ""; event.accepted = true } else event.accepted = false
                }
                Keys.onReturnPressed: {
                    if (dlg.results.length) dlg.pick(dlg.results[0])
                    else if (dlg.emailQuery && dlg.searched) dlg.pickGuest(dlg.query)
                }
                Text {
                    visible: !picker.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Type a name or email"
                    font: picker.font
                    color: theme.textStrong
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Type a name or email"
            }
            FluentIcon {
                visible: picker.activeFocus
                x: parent.width - 32; anchors.verticalCenter: parent.verticalCenter
                name: "chevron-down-20"; size: 20; color: theme.textSecondary
            }
        }

        // Picked people.
        Flickable {
            visible: !dlg.outcome
            x: 2; y: box.y + 43.3; width: 546.7; height: dlg.channelMode ? 190 : 220
            contentHeight: stagedCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: stagedCol
                width: parent.width
                Repeater {
                    model: dlg.staged
                    StagedRow { required property var modelData; item: modelData }
                }
            }
        }

        // What happened when some couldn't be added.
        Column {
            visible: !!dlg.outcome
            x: 0.7; y: 176; width: 543.5
            spacing: 8
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: dlg.outcome ? dlg.outcome.added + " of " + dlg.outcome.requested + " members were added" : ""
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.text
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: !dlg.outcome ? "" : dlg.outcome.failed === 1 ? "1 person couldn't be added" : dlg.outcome.failed + " people couldn't be added"
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: !dlg.outcome ? "" : dlg.outcome.failed === 1 ? "There was an error." : "There were some errors."
                font.family: theme.font; font.pixelSize: 14
                color: theme.danger
            }
        }

        // Matches, over the list.
        Item {
            visible: picker.activeFocus && dlg.query.length > 0 && (dlg.results.length > 0 || (dlg.searched.length > 0 && dlg.emailQuery))
            x: 0; y: box.y + box.height
            width: 550.7; height: Math.min(260, matches.implicitHeight + 8)
            z: 5
            FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
            Flickable {
                anchors.fill: parent; anchors.margins: 4
                contentHeight: matches.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: matches
                    width: parent.width
                    Repeater {
                        model: dlg.results
                        Option {
                            required property var modelData
                            candidate: modelData
                            onChosen: dlg.pick(modelData)
                        }
                    }
                    Option {
                        visible: dlg.results.length === 0 && dlg.emailQuery
                        guestEmail: dlg.query
                        onChosen: dlg.pickGuest(dlg.query)
                    }
                }
            }
        }

        Row {
            x: 351.3; y: dlg.channelMode ? 369.4 : 403
            spacing: 8
            DialogButton { text: dlg.outcome ? "Close" : dlg.channelMode ? "Skip" : "Cancel"; onClicked: dlg.close() }
            DialogButton {
                visible: !dlg.outcome
                text: dlg.adding ? "Adding..." : "Add"; primary: true
                enabled: dlg.staged.length > 0 && !dlg.adding && dlg.staged.every(s => !s.group || s.people !== null)
                onClicked: dlg.add()
            }
        }
    }

    // What the query matched, in bold.
    function marked(text) {
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const q = query.toLowerCase()
        const i = q ? text.toLowerCase().indexOf(q) : -1
        if (i < 0) return esc(text)
        return esc(text.slice(0, i)) + "<b>" + esc(text.slice(i, i + q.length)) + "</b>" + esc(text.slice(i + q.length))
    }

    component Option: Rectangle {
        id: opt
        property var candidate: null
        property string guestEmail: ""
        signal chosen()
        width: matches.width; height: visible ? 50 : 0; radius: 4
        color: optHover.hovered ? theme.menuHover : "transparent"
        Avatar {
            visible: !!opt.candidate
            x: 12; y: 9; size: 32
            name: opt.candidate ? opt.candidate.name || "?" : "?"
            photoId: opt.candidate ? (opt.candidate.mri || "") : ""
        }
        Rectangle {
            visible: !opt.candidate
            x: 12; y: 9; width: 32; height: 32; radius: 16
            color: theme.pick("#8A8A8A", "#5C5C5C")
            FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: "white" }
        }
        Text {
            x: 60; y: opt.candidate ? 7 : 15; width: parent.width - 68; elide: Text.ElideRight
            textFormat: Text.StyledText
            text: opt.candidate ? dlg.marked(opt.candidate.name) : "Add <b>" + dlg.marked(opt.guestEmail).replace(/<\/?b>/g, "") + "</b> as a guest?"
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textStrong
        }
        Text {
            visible: !!opt.candidate
            x: 60; y: 27.5; width: parent.width - 68; elide: Text.ElideRight
            textFormat: Text.StyledText
            text: opt.candidate ? dlg.marked(opt.candidate.detail) : ""
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: opt.chosen() }
        Accessible.role: Accessible.ListItem
        Accessible.name: opt.candidate ? opt.candidate.name : "Add " + opt.guestEmail + " as a guest?"
    }

    component StagedRow: Rectangle {
        id: row
        property var item: ({})
        property bool editing: false
        readonly property int count: item.people ? item.people.length : 0
        width: stagedCol.width; height: 44.7
        color: rowHover.hovered ? theme.menuHover : "transparent"
        HoverHandler { id: rowHover }
        Avatar {
            visible: !row.item.guest
            x: 8; y: 6; size: 32
            name: row.item.name || "?"
            photoId: row.item.mri || ""
        }
        Rectangle {
            visible: !!row.item.guest
            x: 8; y: 6; width: 32; height: 32; radius: 16
            color: theme.pick("#E6E6E6", "#3D3D3D")
            FluentIcon { anchors.centerIn: parent; name: "contact-card-20"; size: 20; color: theme.textSecondary }
        }
        // Name (a guest's Add name), the group's expand button.
        Row {
            visible: !row.editing
            x: 56; y: 4; spacing: 5.7
            Text {
                id: nameText
                visible: !row.item.guest || !!row.item.name
                text: row.item.name || ""
                width: Math.min(implicitWidth, 300); elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                visible: !!row.item.guest && !row.item.name
                text: "Add name"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.brandFill
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { row.editing = true; nameEdit.text = ""; nameEdit.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Add name"
            }
            Item {
                visible: !!row.item.group && row.item.people !== null && row.count > 0
                width: 15; height: 20
                FluentIcon { anchors.centerIn: parent; name: "chevron-circle-down-12"; size: 12; color: theme.textStrong }
                HoverHandler { id: expandHover; cursorShape: Qt.PointingHandCursor }
                ToolTip.visible: expandHover.hovered
                ToolTip.text: row.count === 1 ? "Expand the list with 1 person" : "Expand the list with " + row.count + " people"
                TapHandler { onTapped: dlg.expand(row.item.key) }
                Accessible.role: Accessible.Button
                Accessible.name: ToolTip.text
            }
        }
        Text {
            visible: !row.editing
            x: 56; y: 24; width: 320; elide: Text.ElideRight
            text: row.item.guest ? row.item.email : (row.item.mail || row.item.detail || "")
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
        // A guest's name, edited in place.
        Item {
            visible: row.editing
            x: 56.6; y: 6.7; width: 236.7; height: 30.7
            TextInput {
                id: nameEdit
                x: 12; width: parent.width - 14; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                Keys.onReturnPressed: { dlg.update(row.item.key, { name: text.trim() }); row.editing = false }
                Keys.onEscapePressed: row.editing = false
                Text {
                    visible: !nameEdit.text
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; elide: Text.ElideRight
                    text: "Enter a name for " + (row.item.email || "")
                    font: nameEdit.font
                    color: theme.textTertiary
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        }
        IconButton {
            visible: row.editing
            x: 469.6; icon: "dismiss-20"; label: "Cancel"
            onClicked: row.editing = false
        }
        IconButton {
            visible: row.editing
            x: 501.6; icon: "checkmark-20"; label: "Save"
            onClicked: { dlg.update(row.item.key, { name: nameEdit.text.trim() }); row.editing = false }
        }
        // The role, or the Guest tag.
        Rectangle {
            visible: !!row.item.guest && !row.editing
            x: 458.4; y: 12.3; width: guestTag.implicitWidth + 12; height: 20; radius: 4
            color: theme.pick("#EBEBEB", "#3D3D3D")
            Text { id: guestTag; anchors.centerIn: parent; text: "Guest"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
        }
        Rectangle {
            id: roleButton
            visible: !row.item.guest
            x: 384.3; y: 7; width: 112.3; height: 30; radius: 4
            color: roleHover.hovered ? theme.menuHover : "transparent"
            border.color: roleMenu.opened ? theme.text : "transparent"; border.width: roleMenu.opened ? 2 : 0
            Text {
                anchors.right: roleChevron.left; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
                text: row.item.group ? (row.item.owner ? "Owners" : "Members") : (row.item.owner ? "Owner" : "Member")
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            FluentIcon { id: roleChevron; x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
            HoverHandler { id: roleHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: roleMenu.opened ? roleMenu.close() : roleMenu.open() }
            Accessible.role: Accessible.ComboBox
            Accessible.name: "Role"
            Popup {
                id: roleMenu
                y: roleButton.height + 4.3; x: -10.3
                width: 127.6; height: 74; padding: 4
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                Column {
                    spacing: 2
                    Repeater {
                        model: [true, false]
                        Rectangle {
                            id: roleOpt
                            required property bool modelData
                            readonly property bool chosen: !!row.item.owner === modelData
                            width: 119.6; height: 32; radius: 4
                            color: roleOptHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { visible: roleOpt.chosen; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                            Text {
                                x: 32; anchors.verticalCenter: parent.verticalCenter
                                text: row.item.group ? (roleOpt.modelData ? "Owners" : "Members") : (roleOpt.modelData ? "Owner" : "Member")
                                font.family: theme.font; font.pixelSize: 14
                                color: theme.text
                            }
                            HoverHandler { id: roleOptHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { roleMenu.close(); dlg.update(row.item.key, { owner: roleOpt.modelData }) } }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: row.item.group ? (roleOpt.modelData ? "Owners" : "Members") : (roleOpt.modelData ? "Owner" : "Member")
                        }
                    }
                }
            }
        }
        IconButton {
            visible: !row.editing
            x: 501.6; icon: "dismiss-20"; label: "Remove " + (row.item.name || row.item.email || "")
            onClicked: dlg.staged = dlg.staged.filter(s => s.key !== row.item.key)
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    component IconButton: Rectangle {
        id: ib
        property string icon
        property string label
        signal clicked()
        y: 6.3; width: 32; height: 31.3; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: 20; color: ibHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component DialogButton: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function searchForTest(q) { picker.forceActiveFocus(); picker.text = q }
    function pickFirstForTest() { if (results.length) pick(results[0]); else if (emailQuery) pickGuest(query) }
}
