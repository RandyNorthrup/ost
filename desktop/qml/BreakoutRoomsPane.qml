import QtQuick
import QtQuick.Controls

// Teams' Rooms pane for a meeting's organizer (breakout rooms; measured on
// winpc 2026-11-11, the pane 360 wide on #F5F5F5 under a 58 tall header):
// - "Create breakout rooms" (no rooms yet): "Choose the number of rooms
//   you want to create." (14/20 light) over a 288.8 x 32 spin field at
//   28.9, 109; "Assign participants" (14/600) at 171; three radio cards
//   305.33 x 80 at 20.67 (207, 295, 383; #FAFAFA, #F0F0F0 edge, radius 4,
//   shadow 2) — "Automatically assign …", "Manually assign people to
//   rooms", "Let people choose their rooms" (14/600, #616161 until
//   picked); "Create rooms" (brand, 305.33 x 31.33) at 493, an "or"
//   divider at 534.3 and "Import from CSV" at 560.3.
// - "Breakout rooms": a white card (#E6E6E6 edge, padding 16) at 20.67,
//   77, 319.33 wide — "Unassigned (n)" with their avatars over a brand
//   "Assign participants", or the 24 px star and "All participants have
//   been assigned" (12/600 #707070) over a plain one; then "Open rooms" /
//   "Close rooms" (24 tall) and the room actions toolbar (five 24 x 24
//   buttons from 188, 32 apart: Add room, Import from CSV, Make an
//   announcement, Remove rooms, Rooms settings); then the rooms, 54 tall
//   rows from 272.7 — a 12 px chevron at 23.7 when people are in it, the
//   name and "(n)" (14/20) at 46.7, "Open" (#0B5A08) or "Closed"
//   (#616161) under it, the room's menu at the end on hover; an expanded
//   room lists its people (38 tall: 28 px avatar, name at 102.7, "In
//   room" 12/16 at the end).
// - "Settings" (the toolbar's last button): back at 15.7, 16.7; cards for
//   "Assign presenters to manage rooms" (with a presenter search) and
//   "Set a time limit" (hours and minutes), then switches for
//   "Automatically move people to rooms", "Let people choose their own
//   rooms" and "Let people return to the main meeting", and Save.
Rectangle {
    id: root
    /// The meeting's rooms: [{name, thread, open, invitees: [mri]}].
    property var rooms: []
    /// Everyone else in the main meeting: [{id, name, role, guest}].
    property var people: []
    /// Names by MRI (people who left the main meeting for a room).
    property var names: ({})
    /// {allow_select, room_duration, allow_return, auto_move, managers}
    property var settings: ({})
    property bool busy: false
    signal closed()
    signal createRooms(int count, string mode)
    signal importCsv()
    signal assignParticipants()
    signal openRooms()
    signal closeRooms()
    signal addRoom()
    signal announce()
    signal removeRooms()
    signal saveSettings(var settings)
    /// A room's menu: "join", "open", "rename", "close" or "delete".
    signal roomAction(string action, var room)
    color: theme.pane

    property bool settingsOpen: false
    readonly property string view: rooms.length === 0 ? "create" : settingsOpen ? "settings" : "manage"
    onViewChanged: if (view === "settings") settingsForm.load()
    readonly property var assignedIds: rooms.reduce((a, r) => a.concat(r.invitees || []), [])
    readonly property var unassigned: people.filter(p => assignedIds.indexOf(p.id) < 0)
    readonly property bool anyOpen: rooms.some(r => r.open)
    readonly property bool anyAssigned: rooms.some(r => (r.invitees || []).length > 0)
    function nameOf(id) {
        const p = people.find(x => x.id === id)
        return p ? p.name : (names[id] || "")
    }
    function inMain(id) { return people.some(p => p.id === id) }

    // Pieces.
    component PlainButton: Rectangle {
        id: pb
        property string label
        property bool primary: false
        property bool small: false
        signal clicked()
        height: small ? 24 : 31.33; radius: 4
        color: !pb.enabled ? theme.bgDisabled
             : primary ? (pbHover.hovered ? theme.brandHover : theme.brandFill)
             : (pbHover.hovered ? theme.menuHover : theme.surface)
        border.color: !pb.enabled ? (primary ? "transparent" : theme.divider) : primary ? "transparent" : theme.stroke
        border.width: 0.67
        Text {
            anchors.centerIn: parent
            text: pb.label
            font.family: theme.font; font.pixelSize: 14; font.weight: pb.small ? Font.Normal : Font.DemiBold
            color: !pb.enabled ? theme.disabled : pb.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: pbHover; enabled: pb.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: pb.enabled; onTapped: pb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: pb.label
    }
    component ToolButton24: Rectangle {
        id: tb
        property string icon
        property string tip
        signal clicked()
        width: 24; height: 24; radius: 4
        color: !tb.enabled ? theme.bgDisabled : tbHover.hovered ? theme.menuHover : theme.surface
        border.color: tb.enabled ? theme.stroke : theme.divider; border.width: 0.67
        FluentIcon { anchors.centerIn: parent; name: tb.icon; size: 16; color: tb.enabled ? theme.text : theme.disabled }
        HoverHandler { id: tbHover; cursorShape: tb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tb.enabled; onTapped: tb.clicked() }
        ToolTip.visible: tbHover.hovered; ToolTip.text: tb.tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: tb.tip
    }
    component Switch40: Item {
        id: sw
        property bool checked: false
        signal toggled(bool on)
        width: 40; height: 20
        Rectangle {
            anchors.fill: parent; radius: 10
            color: sw.checked ? (swHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
            border.color: sw.checked ? "transparent" : theme.textSecondary; border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? 22.8 : 2.8
                color: sw.checked ? "white" : theme.textSecondary
            }
        }
        HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { sw.checked = !sw.checked; sw.toggled(sw.checked) } }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: sw.checked
    }
    component Header: Item {
        id: hd
        property string title
        property bool back: false
        signal backClicked()
        y: 3; width: root.width; height: 58
        Rectangle {
            visible: hd.back
            x: 15.67; y: 13.67; width: 32; height: 30; radius: 4
            color: backHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-left-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: hd.backClicked() }
            Accessible.role: Accessible.Button
            Accessible.name: "Back to breakout rooms panel"
        }
        Text {
            x: hd.back ? 47.67 : 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: hd.title
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            visible: !hd.back
            x: root.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // ---- Create breakout rooms ----
    Item {
        id: createView
        visible: root.view === "create"
        anchors.fill: parent
        property int count: 2
        property string mode: "automatic"
        // Teams spreads everyone but the organizer evenly.
        readonly property int assignable: root.people.length
        readonly property int minPer: Math.floor(assignable / Math.max(1, count))
        readonly property int maxPer: Math.ceil(assignable / Math.max(1, count))
        Header { title: "Create breakout rooms" }
        Flickable {
            y: 61; width: parent.width; height: parent.height - y
            contentHeight: 640; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                x: 28.9; y: 20; width: 288.8; height: 20
                verticalAlignment: Text.AlignVCenter
                text: "Choose the number of rooms you want to create."
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Light
                color: theme.text
            }
            Rectangle {
                x: 28.9; y: 48; width: 288.8; height: 32; radius: 4
                color: theme.surface
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: countInput.activeFocus ? 2 : 0.67; color: countInput.activeFocus ? theme.brand : theme.textSecondary }
                TextInput {
                    id: countInput
                    x: 10; width: 250.8; height: 32
                    verticalAlignment: TextInput.AlignVCenter
                    text: String(createView.count)
                    validator: IntValidator { bottom: 1; top: 50 }
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    selectByMouse: true
                    onTextEdited: { const n = parseInt(text); if (n >= 1 && n <= 50) createView.count = n }
                    Accessible.role: Accessible.SpinBox
                    Accessible.name: "Choose the number of rooms you want to create."
                }
                Column {
                    x: 264.8; y: 0
                    Repeater {
                        model: [{ icon: "chevron-up-16", step: 1, name: "Increment value" }, { icon: "chevron-down-16", step: -1, name: "Decrement value" }]
                        Rectangle {
                            required property var modelData
                            width: 24; height: 16; radius: 4
                            color: stepHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: modelData.icon; size: 14; color: theme.textSecondary }
                            HoverHandler { id: stepHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: createView.count = Math.max(1, Math.min(50, createView.count + modelData.step)) }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                        }
                    }
                }
            }
            Text {
                x: 20.67; y: 110; height: 20
                verticalAlignment: Text.AlignVCenter
                text: "Assign participants"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.text
            }
            Repeater {
                model: [
                    { key: "automatic", label: createView.minPer === createView.maxPer
                        ? "Automatically assign " + createView.minPer + (createView.minPer === 1 ? " person" : " people") + " to each room"
                        : "Automatically assign " + createView.minPer + " - " + createView.maxPer + " people to each room" },
                    { key: "manual", label: "Manually assign people to rooms" },
                    { key: "selfselect", label: "Let people choose their rooms" }
                ]
                Item {
                    required property var modelData
                    required property int index
                    readonly property bool picked: createView.mode === modelData.key
                    x: 20.67; y: 146 + index * 88; width: 305.33; height: 80
                    Rectangle {
                        anchors.fill: parent; radius: 4
                        color: theme.quoteFill
                        border.color: theme.quoteBorder; border.width: 0.67
                    }
                    Rectangle {
                        x: 18.67; y: 32; width: 16; height: 16; radius: 8
                        color: "transparent"
                        border.color: parent.picked ? theme.brand : theme.textSecondary; border.width: 0.67
                        Rectangle { visible: parent.parent.picked; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
                    }
                    Text {
                        x: 59.67; width: 227; anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: parent.picked ? theme.text : theme.textSecondary
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: createView.mode = modelData.key }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: picked
                    Accessible.name: modelData.label
                }
            }
            PlainButton {
                x: 20.67; y: 432; width: 305.33
                primary: true
                enabled: !root.busy
                label: "Create rooms"
                onClicked: root.createRooms(createView.count, createView.mode)
            }
            Item {
                x: 20.67; y: 473.3; width: 305.33; height: 16
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 0.67; color: theme.divider }
                Rectangle {
                    anchors.centerIn: parent; width: orText.width + 16; height: 16; color: theme.pane
                    Text { id: orText; anchors.centerIn: parent; text: "or"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                }
            }
            PlainButton {
                x: 20.67; y: 499.3; width: 305.33
                enabled: !root.busy
                label: "Import from CSV"
                onClicked: root.importCsv()
            }
        }
    }

    // ---- Breakout rooms ----
    Item {
        id: manageView
        visible: root.view === "manage"
        anchors.fill: parent
        property var expanded: ({})
        Header { title: "Breakout rooms" }
        Flickable {
            y: 61; width: parent.width; height: parent.height - y
            contentHeight: roomsColumn.y + roomsColumn.height + 20; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Rectangle {
                id: assignCard
                x: 20.67; y: 16; width: 319.33
                height: root.unassigned.length ? 186 : 144.67
                color: theme.surface
                border.color: theme.cardStroke; border.width: 0.67
                // Everyone assigned: the star and the plain button.
                FluentIcon {
                    visible: !root.unassigned.length
                    x: 16.67; y: 32.67; size: 24; name: "star-emphasis-24"; color: theme.textTertiary
                }
                Text {
                    visible: !root.unassigned.length
                    x: 52.67; y: 36.67; height: 16
                    verticalAlignment: Text.AlignVCenter
                    text: "All participants have been assigned"
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.textTertiary
                }
                // People still to place.
                Text {
                    visible: root.unassigned.length > 0
                    x: 16.67; y: 16.67; height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: "Unassigned (" + root.unassigned.length + ")"
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    color: theme.text
                }
                Row {
                    visible: root.unassigned.length > 0
                    x: 16.67; y: 52; spacing: 4
                    Repeater {
                        model: root.unassigned.slice(0, 8)
                        Avatar { required property var modelData; size: 32; name: modelData.name; photoId: modelData.id }
                    }
                }
                PlainButton {
                    x: 24.67; y: root.unassigned.length ? 108 : 88.67; width: 270
                    primary: root.unassigned.length > 0
                    label: "Assign participants"
                    onClicked: root.assignParticipants()
                }
            }
            PlainButton {
                id: openClose
                x: 20.67; y: assignCard.y + assignCard.height + 17; width: openCloseText.advanceWidth + 25.33
                small: true
                label: root.anyOpen ? "Close rooms" : "Open rooms"
                // Teams opens only rooms with people in them.
                enabled: !root.busy && (root.anyOpen || root.anyAssigned)
                onClicked: root.anyOpen ? root.closeRooms() : root.openRooms()
                TextMetrics { id: openCloseText; font.family: theme.font; font.pixelSize: 14; text: openClose.label }
            }
            Row {
                x: 188; y: openClose.y; spacing: 8
                Accessible.role: Accessible.ToolBar
                Accessible.name: "Room action buttons"
                ToolButton24 { icon: "add-16"; tip: "Add room"; enabled: !root.busy; onClicked: root.addRoom() }
                ToolButton24 { icon: "arrow-upload-16"; tip: "Import from CSV"; enabled: !root.busy && !root.anyOpen; onClicked: root.importCsv() }
                ToolButton24 { icon: "megaphone-16"; tip: "Make an announcement"; enabled: root.anyOpen; onClicked: root.announce() }
                ToolButton24 { icon: "delete-16"; tip: "Remove rooms"; enabled: !root.busy && !root.anyOpen; onClicked: root.removeRooms() }
                ToolButton24 { icon: "settings-16"; tip: "Rooms settings"; enabled: !root.anyOpen; onClicked: root.settingsOpen = true }
            }
            Column {
                id: roomsColumn
                y: openClose.y + 34
                width: root.width
                Accessible.role: Accessible.Tree
                Accessible.name: "Breakout rooms"
                Repeater {
                    model: root.rooms
                    Column {
                        id: roomBlock
                        required property var modelData
                        readonly property var invitees: modelData.invitees || []
                        readonly property bool isOpen: !!manageView.expanded[modelData.thread] && invitees.length > 0
                        width: root.width
                        Item {
                            width: root.width; height: 54
                            HoverHandler { id: rowHover }
                            TapHandler {
                                onTapped: if (roomBlock.invitees.length) {
                                    const e = Object.assign({}, manageView.expanded)
                                    e[roomBlock.modelData.thread] = !e[roomBlock.modelData.thread]
                                    manageView.expanded = e
                                }
                            }
                            FluentIcon {
                                visible: roomBlock.invitees.length > 0
                                x: 23; y: 21; size: 12
                                name: roomBlock.isOpen ? "chevron-down-12" : "chevron-right-12"
                                color: theme.textSecondary
                            }
                            Row {
                                x: 46.67; y: 9; spacing: 6
                                Text { text: roomBlock.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                                Text {
                                    text: "(" + roomBlock.invitees.length + ")"
                                    font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                                    Accessible.name: roomBlock.invitees.length === 1 ? "1 participant." : roomBlock.invitees.length + " participants."
                                }
                            }
                            Text {
                                x: 46.67; y: 30
                                text: roomBlock.modelData.open ? "Open" : "Closed"
                                font.family: theme.font; font.pixelSize: 14
                                color: roomBlock.modelData.open ? theme.greenForeground2 : theme.textSecondary
                                Accessible.name: roomBlock.modelData.open ? "Room is Open." : "Room is Closed."
                            }
                            Rectangle {
                                visible: rowHover.hovered || roomMenu.visible
                                x: root.width - 46; y: 11; width: 32; height: 32; radius: 4
                                color: moreHover.hovered ? theme.menuHover : "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: roomMenu.open() }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Open room options"
                                MenuPopup {
                                    id: roomMenu
                                    x: -96; y: parent.height + 4
                                    items: [
                                        { label: "Join", enabled: roomBlock.modelData.open },
                                        { separator: true },
                                        { label: "Open", enabled: !roomBlock.modelData.open && roomBlock.invitees.length > 0 },
                                        { label: "Rename" },
                                        { label: "Close", enabled: roomBlock.modelData.open },
                                        { separator: true },
                                        { label: "Delete", enabled: !roomBlock.modelData.open }
                                    ]
                                    onPicked: i => root.roomAction(["join", "", "open", "rename", "close", "", "delete"][i], roomBlock.modelData)
                                }
                            }
                            Accessible.role: Accessible.TreeItem
                            Accessible.name: roomBlock.modelData.name
                        }
                        Repeater {
                            model: roomBlock.isOpen ? roomBlock.invitees : []
                            Item {
                                required property string modelData
                                width: root.width; height: 38
                                Avatar { x: 64.67; y: 5; size: 28; name: root.nameOf(parent.modelData); photoId: parent.modelData }
                                Text {
                                    x: 102.67; anchors.verticalCenter: parent.verticalCenter
                                    width: 180; elide: Text.ElideRight
                                    text: root.nameOf(parent.modelData)
                                    font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                                }
                                Text {
                                    // In the room: no longer in the main meeting.
                                    visible: roomBlock.modelData.open && !root.inMain(parent.modelData)
                                    anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                                    text: "In room"
                                    font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Settings ----
    Item {
        id: settingsForm
        visible: root.view === "settings"
        anchors.fill: parent
        property bool managersOn: false
        property var managers: []
        property bool limitOn: false
        property int hours: 0
        property int minutes: 0
        property bool autoMove: true
        property bool allowSelect: false
        property bool allowReturn: false
        function load() {
            const s = root.settings || {}
            managers = s.managers || []
            managersOn = managers.length > 0
            limitOn = (s.room_duration || 0) > 0
            hours = Math.floor((s.room_duration || 0) / 60)
            minutes = (s.room_duration || 0) % 60
            autoMove = s.auto_move !== false
            allowSelect = !!s.allow_select
            allowReturn = !!s.allow_return
        }
        readonly property var presenters: root.people.filter(p => ["presenter", "organizer", "coorganizer"].indexOf((p.role || "").toLowerCase()) >= 0)
        Header { title: "Settings"; back: true; onBackClicked: root.settingsOpen = false }
        Flickable {
            y: 61; width: parent.width; height: parent.height - y
            contentHeight: 500; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Rectangle {
                x: 20.67; y: 16; width: 319.33; height: 132.67; radius: 4
                color: theme.surface
                border.color: theme.cardStroke; border.width: 0.67
                Text {
                    x: 16.67; y: 16.67; width: 230; height: 56
                    verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    text: "Assign presenters to manage rooms"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Switch40 {
                    x: 254.67; y: 34.67
                    checked: settingsForm.managersOn
                    Accessible.name: "Assign presenters to manage rooms"
                    onToggled: on => { settingsForm.managersOn = on; if (!on) settingsForm.managers = [] }
                }
                Rectangle {
                    x: 16.67; y: 83.33; width: 286; height: 32; radius: 4
                    color: settingsForm.managersOn ? theme.surface : theme.bgDisabled
                    border.color: settingsForm.managersOn ? theme.stroke : theme.divider; border.width: 0.67
                    Text {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; width: 240; elide: Text.ElideRight
                        text: settingsForm.managers.length ? settingsForm.managers.map(m => root.nameOf(m.mri)).join(", ") : "Search for presenters"
                        font.family: theme.font; font.pixelSize: 14
                        color: settingsForm.managersOn && settingsForm.managers.length ? theme.text : theme.disabled
                    }
                    FluentIcon { x: 260; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: settingsForm.managersOn ? theme.textSecondary : theme.disabled }
                    TapHandler { enabled: settingsForm.managersOn; onTapped: presenterMenu.open() }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: "Search for presenters"
                    MenuPopup {
                        id: presenterMenu
                        y: parent.height + 4
                        items: settingsForm.presenters.length
                            ? settingsForm.presenters.map(p => ({ label: p.name, checked: settingsForm.managers.some(m => m.mri === p.id) }))
                            : [{ label: "There are no assigned presenters to select from in the meeting at the moment.", enabled: false }]
                        onPicked: i => {
                            const p = settingsForm.presenters[i]
                            if (!p) return
                            const has = settingsForm.managers.some(m => m.mri === p.id)
                            settingsForm.managers = has ? settingsForm.managers.filter(m => m.mri !== p.id)
                                                        : settingsForm.managers.concat([{ mri: p.id, role: "Admin" }])
                        }
                    }
                }
            }
            Rectangle {
                x: 20.67; y: 158.67; width: 319.33; height: 152; radius: 4
                color: theme.surface
                border.color: theme.cardStroke; border.width: 0.67
                Text {
                    id: limitLabel
                    x: 24.67; y: 24.33; height: 18.67
                    verticalAlignment: Text.AlignVCenter
                    text: "Set a time limit"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Item {
                    x: 117.33; y: 21.67; width: 24; height: 24
                    FluentIcon { anchors.centerIn: parent; name: "info-16"; size: 16; color: theme.textStrong }
                    HoverHandler { id: infoHover }
                    ToolTip.visible: infoHover.hovered
                    ToolTip.text: "We'll move everyone back to the main meeting when the time expires."
                    Accessible.role: Accessible.Button
                    Accessible.name: "information"
                }
                Switch40 {
                    x: 254.67; y: 24.33
                    checked: settingsForm.limitOn
                    Accessible.name: "Set a time limit"
                    onToggled: on => { settingsForm.limitOn = on; if (on && !settingsForm.hours && !settingsForm.minutes) settingsForm.minutes = 30 }
                }
                Repeater {
                    model: [{ unit: "hours", y: 63.33, max: 23 }, { unit: "minutes", y: 104.67, max: 59 }]
                    Rectangle {
                        required property var modelData
                        readonly property int value: modelData.unit === "hours" ? settingsForm.hours : settingsForm.minutes
                        x: 17.33; y: modelData.y; width: 284.67; height: 30; radius: 4
                        color: settingsForm.limitOn ? theme.surface : theme.bgDisabled
                        border.color: settingsForm.limitOn ? theme.stroke : theme.divider; border.width: 0.67
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            text: parent.value + " " + (modelData.unit === "hours" ? (parent.value === 1 ? "hour" : "hours") : (parent.value === 1 ? "minute" : "minutes"))
                            font.family: theme.font; font.pixelSize: 14
                            color: settingsForm.limitOn ? theme.text : theme.disabled
                        }
                        FluentIcon { x: 258; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: settingsForm.limitOn ? theme.textSecondary : theme.disabled }
                        TapHandler { enabled: settingsForm.limitOn; onTapped: unitMenu.open() }
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: modelData.unit === "hours" ? "Set hours limit" : "Set minutes limit"
                        MenuPopup {
                            id: unitMenu
                            y: parent.height + 4
                            height: Math.min(implicitHeight, 300)
                            items: Array.from({ length: (modelData.unit === "hours" ? 24 : 12) }, (_, i) => {
                                const v = modelData.unit === "hours" ? i : i * 5
                                return { label: v + " " + (modelData.unit === "hours" ? (v === 1 ? "hour" : "hours") : (v === 1 ? "minute" : "minutes")) }
                            })
                            onPicked: i => { if (modelData.unit === "hours") settingsForm.hours = i; else settingsForm.minutes = i * 5 }
                        }
                    }
                }
            }
            Repeater {
                model: [
                    { key: "autoMove", label: "Automatically move people to rooms", y: 320.67 },
                    { key: "allowSelect", label: "Let people choose their own rooms", y: 356.67 },
                    { key: "allowReturn", label: "Let people return to the main meeting", y: 402.67 }
                ]
                Item {
                    required property var modelData
                    x: 20.67; y: modelData.y; width: 319.33; height: 36
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 250; wrapMode: Text.Wrap
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Switch40 {
                        x: 271.33; y: 8
                        checked: settingsForm[modelData.key]
                        Accessible.name: modelData.label
                        onToggled: on => settingsForm[modelData.key] = on
                    }
                }
            }
            PlainButton {
                x: 244; y: 448.67; width: 96
                primary: true
                enabled: !root.busy
                label: "Save"
                onClicked: {
                    root.saveSettings({
                        allow_select: settingsForm.allowSelect,
                        allow_return: settingsForm.allowReturn,
                        auto_move: settingsForm.autoMove,
                        room_duration: settingsForm.limitOn ? settingsForm.hours * 60 + settingsForm.minutes : 0,
                        managers: settingsForm.managersOn ? settingsForm.managers : []
                    })
                    root.settingsOpen = false
                }
            }
        }
    }
}
