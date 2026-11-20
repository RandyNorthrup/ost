import QtQuick
import QtQuick.Controls.Basic

// A meeting chat's Breakout Rooms tab (Teams' pre-meeting room
// assignment, chattabs.breakoutrooms), for the meeting's organizer.
// Measured on winpc 2026-11-16 (no rooms) and 2026-11-20 (rooms), at
// 892 x 571 CSS px (docs/spec/add-a-tab.md):
// - no fill of its own (the window's #EBEBEB), padding 14 0 0 21;
// - "Assign participants" (174 x 31.3, its people icon, 14/600; off and
//   #F0F0F0 / #BDBDBD until there are rooms and people invited) at (21, 14);
// - the room actions (Room action buttons), 32 x 32, 5 apart and 20 from
//   the right: Add room, Import from CSV (only once there are rooms),
//   Remove rooms (off until there are rooms), Rooms settings; icons
//   #424242;
// - with no rooms, centred on the area right of the padding: the picture
//   (220 x 142.3) at 138.1, "Create breakout rooms" (24/32 bold) at
//   312.4, "See your rooms and set them up the way you want, all right
//   here." (16/22.86) at 360.4, Create rooms (brand, 110.3 x 31.3) at
//   415.3 and Import from CSV (outline, 132.9 x 31.3) at 462.6;
// - with rooms, cards (breakout-room-card) from (22.4, 62.73), 290 x 250,
//   16 apart, wrapping: white, radius 2, Fluent's card shadow; a 126 tall
//   #5B5FC7 band (radius 4 at the top) with the room's menu (32 x 31.33,
//   a white ··· at 238, 16: Rename, Room options, Delete); the name
//   (16/22 bold) at 20, 150; a divider (8 in) at 191; the filled person
//   (20) at 20, 210 and "n participants" (14/20) at 50, 210;
// - Create rooms asks "How many rooms do you need?" (a number, 2 at
//   first) in a 600-wide dialog ("Create rooms", 20/28 semibold; Cancel
//   and Add rooms); Remove rooms asks "Remove rooms?" ("This will delete
//   all existing rooms.", 450 wide, Close, Cancel / Remove); Import from
//   CSV with rooms first asks "Overwriting rooms and participant
//   assignment" (600 wide, Cancel / Continue); Room options opens the
//   room's Meeting options page in the browser (the backend's
//   options_url); Rooms settings opens
//   "Breakout rooms settings" (BreakoutSettingsDialog).
Rectangle {
    id: root
    /// The meeting's chat thread and its organizer (object id).
    property string thread: ""
    property string organizer: ""
    color: theme.chrome
    readonly property var state_: {
        const s = backend.meetingBreakoutJson ? JSON.parse(backend.meetingBreakoutJson) : null
        return s && s.thread === thread ? s : null
    }
    readonly property var rooms: state_ && state_.rooms ? state_.rooms : []
    /// The meeting's invitees who can be placed: [{id, name, upn, objectId, tenantId, role}].
    readonly property var people: state_ && state_.people ? state_.people : []
    readonly property bool busy: !!state_ && !!state_.busy
    readonly property bool hasRooms: rooms.length > 0
    function act(action, args) { backend.meetingBreakoutAction(thread, organizer, action, JSON.stringify(args || {})) }
    onThreadChanged: if (thread && organizer) act("refresh")
    Component.onCompleted: if (thread && organizer) act("refresh")
    function nextRoomName() {
        let n = rooms.length + 1
        while (rooms.some(r => r.name === "Room " + n)) n++
        return "Room " + n
    }
    component ToolButton32: Rectangle {
        id: tb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 32; radius: 4
        color: tbh.hovered && enabled ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: tb.icon; size: 20; color: theme.onFill(tb, tb.enabled ? theme.textStrong : theme.disabled) }
        HoverHandler { id: tbh; cursorShape: tb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tb.enabled; onTapped: tb.clicked() }
        ToolTip.visible: tbh.hovered && !!tip; ToolTip.delay: 500; ToolTip.text: tip
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
    component Button31: Rectangle {
        id: b
        property string label
        property string icon: ""
        property bool primary: false
        signal clicked()
        width: row.implicitWidth + 24; height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
        border.width: 0.67; border.color: primary ? "transparent" : !enabled ? theme.divider : theme.stroke
        Row {
            id: row
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!b.icon; anchors.verticalCenter: parent.verticalCenter; name: b.icon || "add-20"; size: 20; color: theme.onFill(b, !b.enabled ? theme.disabled : b.primary ? theme.textOnBrand : theme.text) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(b, !b.enabled ? theme.disabled : b.primary ? theme.textOnBrand : theme.text) }
        }
        HoverHandler { id: bh; cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: b.enabled; onTapped: b.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    Button31 {
        x: 21; y: 14; width: 174
        icon: "breakout-assign-20"; label: qsTr("Assign participants")
        enabled: root.hasRooms && root.people.length > 0 && !root.busy
        onClicked: assignType.start()
    }
    // Who isn't in a room yet: their pictures (32 px) 15 px after the
    // button (Teams' maxParticipantsToolbarAvatarsInPreMeeting: 4, then
    // "+n").
    readonly property var assignedIds: rooms.reduce((a, r) => a.concat((r.participants || []).map(p => (p.mri || "").toLowerCase())), [])
    readonly property var unassigned: people.filter(p => assignedIds.indexOf(p.id.toLowerCase()) < 0)
    Row {
        x: 210; y: 14; spacing: 4
        Repeater {
            model: root.unassigned.slice(0, 4)
            Avatar { required property var modelData; size: 32; name: modelData.name; photoId: modelData.id }
        }
        Rectangle {
            visible: root.unassigned.length > 4
            width: 32; height: 32; radius: 16
            color: theme.cardStroke
            Text { anchors.centerIn: parent; text: "+" + (root.unassigned.length - 4); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
        }
    }
    // Teams' first Assign participants step (assignment-type-breakout-
    // room-dialog, 600 x 508.67, padding 24): three 550.67 x 80 cards
    // (#FAFAFA, #F0F0F0 edge, radius 4, card shadow) at 108.67, 196.67,
    // 284.67 with a radio at 18.67, 32 and the choice (14/600, #616161
    // until picked) at 59.67; Cancel and Next. Automatically assigns at
    // once, Manually opens the assignment table, Let people choose turns
    // on choosing rooms.
    Popup {
        id: assignType
        property string mode: "automatic"
        function start() { mode = "automatic"; open() }
        readonly property int minPer: Math.floor(root.people.length / Math.max(1, root.rooms.length))
        readonly property int maxPer: Math.ceil(root.people.length / Math.max(1, root.rooms.length))
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 0
        width: 600; height: 508.67
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        Text {
            x: 24.67; y: 24.67; width: 550.67; height: 28
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Assign participants to breakout rooms")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Repeater {
            model: [
                { key: "automatic", label: assignType.minPer === assignType.maxPer
                    ? qsTr("Automatically assign %n people to each room", "", assignType.minPer)
                    : qsTr("Automatically assign %1 - %2 people to each room").arg(assignType.minPer).arg(assignType.maxPer) },
                { key: "manual", label: qsTr("Manually assign people to rooms") },
                { key: "selfselect", label: qsTr("Let people choose their rooms") }
            ]
            Item {
                required property var modelData
                required property int index
                readonly property bool picked: assignType.mode === modelData.key
                x: 24.67; y: 108.67 + index * 88; width: 550.67; height: 80
                FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: theme.quoteFill; borderColor: theme.quoteBorder }
                Rectangle {
                    x: 18.67; y: 32; width: 16; height: 16; radius: 8
                    color: "transparent"
                    border.color: parent.picked ? theme.brand : theme.textSecondary; border.width: 0.67
                    Rectangle { visible: parent.parent.picked; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
                }
                Text {
                    x: 59.67; width: 470; anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: modelData.label
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: parent.picked ? theme.text : theme.textSecondary
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: assignType.mode = modelData.key }
                Accessible.role: Accessible.RadioButton
                Accessible.checked: picked
                Accessible.name: modelData.label
            }
        }
        Row {
            x: 375.33; y: 452.67; spacing: 8
            Button31 { width: 96; label: qsTr("Cancel"); onClicked: assignType.close() }
            Button31 {
                width: 96; primary: true; label: qsTr("Next")
                onClicked: {
                    const mode = assignType.mode
                    assignType.close()
                    if (mode === "manual") assignRooms.show()
                    else if (mode === "automatic") root.assignAutomatically()
                    else root.act("settings", Object.assign({}, root.state_ && root.state_.settings ? root.state_.settings : {}, { allow_select: true }))
                }
            }
        }
    }
    // Automatically: everyone spread evenly over the rooms at random.
    function assignAutomatically() {
        const pool = people.map(p => p.id)
        for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]] }
        const lists = rooms.map(() => [])
        pool.forEach((id, i) => lists[i % rooms.length].push(id))
        act("assign", { total: people.length, rooms: rooms.map((r, k) => ({ thread: r.thread, participants: lists[k].map(personRecord) })) })
    }
    function personRecord(id) {
        const p = people.find(x => x.id === id)
        return p ? { mri: p.id, upn: p.upn, objectId: p.objectId, tenantId: p.tenantId, role: "admin" } : { mri: id }
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 20; y: 14; spacing: 5
        Accessible.role: Accessible.ToolBar; Accessible.name: qsTr("Room action buttons")
        ToolButton32 { icon: "add-20"; tip: qsTr("Add room"); enabled: root.hasRooms && !root.busy; onClicked: root.act("add", { name: root.nextRoomName() }) }
        ToolButton32 { visible: root.hasRooms; icon: "arrow-upload-20"; tip: qsTr("Import from CSV"); enabled: !root.busy; onClicked: root.importCsv() }
        ToolButton32 { icon: "delete-20"; tip: qsTr("Remove rooms"); enabled: root.hasRooms && !root.busy; onClicked: removeRoomsAsk.open() }
        ToolButton32 { icon: "settings-20"; tip: qsTr("Rooms settings"); enabled: !root.busy; onClicked: settingsDialog.show() }
    }
    // Import from CSV: with rooms already made, Teams asks before
    // replacing them.
    function importCsv() {
        if (hasRooms) csvOverwriteAsk.open()
        else csvDialog.open()
    }

    // No rooms yet.
    Item {
        // (A meeting without rooms may answer the list with an error.)
        visible: !root.hasRooms && !!root.state_ && (!!root.state_.loaded || root.state_.error !== undefined)
        x: 21; width: parent.width - 21; height: parent.height
        Image {
            x: (parent.width - 220) / 2; y: 138.1; width: 220; height: 142.3
            source: "../assets/illustrations/breakout-rooms-empty.svg"
            sourceSize: Qt.size(440, 285); fillMode: Image.PreserveAspectFit; smooth: true
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 312.4; text: qsTr("Create breakout rooms"); font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 360.4; text: qsTr("See your rooms and set them up the way you want, all right here."); font.family: theme.font; font.pixelSize: 16; lineHeight: 22.86; lineHeightMode: Text.FixedHeight; color: theme.text }
        Button31 { anchors.horizontalCenter: parent.horizontalCenter; y: 415.3; width: 110.3; primary: true; label: qsTr("Create rooms"); enabled: !root.busy; onClicked: createDialog.start() }
        Button31 { anchors.horizontalCenter: parent.horizontalCenter; y: 462.6; width: 132.9; label: qsTr("Import from CSV"); enabled: !root.busy; onClicked: root.importCsv() }
    }

    // The rooms, as cards.
    Flickable {
        visible: root.hasRooms
        x: 22.4; y: 62.73; width: parent.width - x - 20; height: parent.height - y
        clip: true
        contentHeight: cards.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Flow {
            id: cards
            width: parent.width
            spacing: 16
            Repeater {
                id: cardRepeater
                model: root.rooms
                Item {
                    id: card
                    required property var modelData
                    function openMenu() { roomMenu.open() }
                    readonly property int count: (modelData.participants || []).length
                    width: 290; height: 250
                    FluentSurface { anchors.fill: parent; depth: 2; radius: 2; color: theme.surface }
                    Rectangle {
                        width: parent.width; height: 126; radius: 4; color: theme.brandFill
                        Rectangle { y: 122; width: parent.width; height: 4; color: parent.color }
                    }
                    Rectangle {
                        id: menuButton
                        x: 238; y: 16; width: 32; height: 31.33; radius: 4
                        color: menuHover.hovered || roomMenu.opened ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textOnBrand }
                        HoverHandler { id: menuHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: roomMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More options")
                        MenuPopup {
                            id: roomMenu
                            y: parent.height + 4
                            items: [
                                { label: qsTr("Rename"), icon: "edit-20" },
                                { label: qsTr("Room options"), icon: "options-20" },
                                { label: qsTr("Delete"), icon: "delete-20", enabled: !root.busy }
                            ]
                            onPicked: i => {
                                if (i === 0) { roomText.thread = card.modelData.thread; roomText.title = qsTr("Rename %1?").arg(card.modelData.name); roomText.initial = card.modelData.name; roomText.show() }
                                else if (i === 1) { if (card.modelData.options_url) Qt.openUrlExternally(card.modelData.options_url) }
                                else { deleteRoomAsk.thread = card.modelData.thread; deleteRoomAsk.title = qsTr("Delete %1?").arg(card.modelData.name); deleteRoomAsk.open() }
                            }
                        }
                    }
                    Text {
                        x: 20; y: 150; width: 254; height: 22
                        text: card.modelData.name
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Rectangle { x: 8; y: 191; width: 274; height: 1; color: theme.divider }
                    FluentIcon { x: 20; y: 210; name: "person-20-filled"; size: 20; color: theme.text }
                    Text {
                        x: 50; y: 210; height: 20
                        verticalAlignment: Text.AlignVCenter
                        text: card.count === 1 ? qsTr("1 participant") : qsTr("%1 participants").arg(card.count)
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Accessible.role: Accessible.Grouping
                    Accessible.name: card.modelData.name
                }
            }
        }
    }
    Text {
        visible: !!root.state_ && !!root.state_.error && !!root.state_.loaded
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        text: qsTr("Something went wrong. Try again later.")
        font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3
    }

    // Create rooms: "How many rooms do you need?".
    Popup {
        id: createDialog
        property int count: 2
        function start() { count = 2; countInput.text = "2"; open() }
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600; padding: 24
        background: FluentSurface { depth: 64; radius: 8 }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        contentItem: Column {
            spacing: 0
            Text { text: qsTr("Create rooms"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
            Item { width: 1; height: 8.6 }
            Text { text: qsTr("How many rooms do you need?"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Rectangle {
                width: parent.width; height: 32; radius: 4
                color: theme.inputFilled; border.width: 0.67; border.color: theme.transparentStroke
                TextInput {
                    id: countInput
                    x: 10; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                    validator: IntValidator { bottom: 1; top: 50 }
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    selectByMouse: true
                    onTextEdited: { const n = parseInt(text); if (n >= 1 && n <= 50) createDialog.count = n }
                    Accessible.role: Accessible.SpinBox; Accessible.name: qsTr("How many rooms do you need?")
                }
                Rectangle { visible: countInput.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                Column {
                    anchors.right: parent.right
                    Repeater {
                        model: [{ icon: "chevron-up-16", step: 1, name: qsTr("Increment value") }, { icon: "chevron-down-16", step: -1, name: qsTr("Decrement value") }]
                        Rectangle {
                            id: step
                            required property var modelData
                            width: 24; height: 16; color: stepHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: step.modelData.icon; size: 14; color: theme.onFill(step, theme.textSecondary) }
                            HoverHandler { id: stepHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { createDialog.count = Math.max(1, Math.min(50, createDialog.count + step.modelData.step)); countInput.text = String(createDialog.count) } }
                            Accessible.role: Accessible.Button; Accessible.name: step.modelData.name
                        }
                    }
                }
            }
            Item { width: 1; height: 8 }
            Row {
                anchors.right: parent.right; spacing: 8
                Button31 { width: 96; label: qsTr("Cancel"); onClicked: createDialog.close() }
                Button31 {
                    width: 96; primary: true; label: qsTr("Add rooms")
                    onClicked: {
                        const rooms = []
                        for (let i = 1; i <= createDialog.count; i++) rooms.push({ name: "Room " + i, participants: [] })
                        root.act("create", { rooms: rooms })
                        createDialog.close()
                    }
                }
            }
        }
    }

    // Assign participants: the meeting's invitees, as Teams' pre-meeting
    // assignment places them.
    AssignRoomsDialog {
        id: assignRooms
        rooms: root.rooms.map(r => ({ name: r.name, thread: r.thread, invitees: (r.participants || []).map(p => p.mri) }))
        people: root.people.map(p => ({ id: p.id, name: p.name }))
        onSaved: changes => {
            if (!changes.length) return
            const record = id => {
                const p = root.people.find(x => x.id === id)
                return p ? { mri: p.id, upn: p.upn, objectId: p.objectId, tenantId: p.tenantId, role: "admin" } : { mri: id }
            }
            root.act("assign", { total: root.people.length, rooms: changes.map(c => ({ thread: c.thread, participants: c.participants.map(record) })) })
        }
    }
    BreakoutSettingsDialog {
        id: settingsDialog
        settings: root.state_ && root.state_.settings ? root.state_.settings : ({})
        presenters: root.people.filter(p => ["presenter", "coorganizer", "organizer"].indexOf((p.role || "").toLowerCase()) >= 0)
        onSaved: s => root.act("settings", s)
    }
    BreakoutTextDialog {
        id: roomText
        property string thread: ""
        rename: true
        onConfirmed: text => root.act("rename", { thread: thread, name: text })
    }
    ConfirmDialog {
        id: removeRoomsAsk
        dialogWidth: 450; closeButton: true
        title: qsTr("Remove rooms?")
        body: qsTr("This will delete all existing rooms.")
        confirmText: qsTr("Remove")
        onConfirmed: root.act("delete_all", {})
    }
    ConfirmDialog {
        id: deleteRoomAsk
        property string thread: ""
        dialogWidth: 500; closeButton: true
        body: ""
        confirmText: qsTr("Delete")
        onConfirmed: root.act("delete", { thread: thread })
    }
    ConfirmDialog {
        id: csvOverwriteAsk
        dialogWidth: 600
        title: qsTr("Overwriting rooms and participant assignment")
        body: qsTr("There are already rooms created with participants in them. If you import a CSV it will overwrite the current rooms and participant assignment. Are you sure to continue?")
        confirmText: qsTr("Continue")
        onConfirmed: csvDialog.open()
    }
    BreakoutCsvDialog {
        id: csvDialog
        onDownloadTemplate: root.act("csv_template", {})
        onPicked: path => root.act("import_csv", { path: path })
    }

    // Test hooks (--breakout-tab-test).
    function createForTest(n) { createDialog.start(); createDialog.count = n }
    function roomMenuForTest(i) { const c = cardRepeater.itemAt(i); if (c) c.openMenu() }
    function settingsForTest() { settingsDialog.show() }
    function removeForTest() { removeRoomsAsk.open() }
    function importForTest() { importCsv() }
    function assignForTest() { assignRooms.show() }
    function assignTypeForTest() { assignType.start() }
    function closeAllForTest() { for (const d of [assignType, settingsDialog, removeRoomsAsk, csvOverwriteAsk, csvDialog, assignRooms, createDialog]) d.close() }
}
