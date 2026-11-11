import QtQuick
import QtQuick.Controls

// Teams' "Assign participants to breakout rooms" (measured on winpc
// 2026-11-11): a 700 wide Fluent dialog, padding 24.67. The title
// (20/28 semibold), "Manually assign each person to a room, or choose
// Shuffle to assign everyone randomly."; a filled "Find participants"
// search (650.67 x 32); "Select a room ⌄" (for the ticked people;
// disabled until someone is) and "Shuffle ⌄" (121 wide: Everyone, Only
// unassigned people); a table — a select-all box, "Name ↑", "Room" with
// the rooms glyph — whose rows hold a box, a 24 px avatar, the name and
// the person's room ("Unassigned ⌄", a menu of Unassigned and the
// rooms); at the foot the people glyph and "n (m unassigned)" (14/600),
// then Cancel and Save (disabled until something changes).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 700; height: 501.33
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// [{name, thread, invitees}]
    property var rooms: []
    /// [{id, name}] — everyone who can be placed.
    property var people: []
    /// The rooms' people when saved: [{thread, participants: [mri]}] for
    /// the rooms that changed.
    signal saved(var changes)

    property var assignment: ({})
    property var original: ({})
    property var ticked: []
    property string query: ""
    function show() {
        const a = {}
        for (const r of rooms) for (const id of (r.invitees || [])) a[id] = r.thread
        assignment = a; original = Object.assign({}, a)
        ticked = []; query = ""; search.text = ""
        open()
    }
    readonly property var shown: people.filter(p => !query || p.name.toLowerCase().indexOf(query.toLowerCase()) >= 0)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property int unassignedCount: people.filter(p => !assignment[p.id]).length
    readonly property bool changed: people.some(p => (assignment[p.id] || "") !== (original[p.id] || ""))
    function roomName(thread) { const r = rooms.find(x => x.thread === thread); return r ? r.name : "Unassigned" }
    function place(ids, thread) {
        const a = Object.assign({}, assignment)
        for (const id of ids) { if (thread) a[id] = thread; else delete a[id] }
        assignment = a
    }
    // Teams' Shuffle: spread people evenly over the rooms at random.
    function shuffle(onlyUnassigned) {
        const a = Object.assign({}, assignment)
        const pool = people.filter(p => !onlyUnassigned || !a[p.id]).map(p => p.id)
        for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]] }
        const counts = rooms.map(r => onlyUnassigned ? people.filter(p => a[p.id] === r.thread).length : 0)
        for (const id of pool) {
            const k = counts.indexOf(Math.min(...counts))
            a[id] = rooms[k].thread; counts[k]++
        }
        assignment = a
    }
    function save() {
        const changes = []
        for (const r of rooms) {
            const before = people.filter(p => original[p.id] === r.thread).map(p => p.id).sort()
            const after = people.filter(p => assignment[p.id] === r.thread).map(p => p.id).sort()
            // Keep anyone assigned who isn't in the meeting now.
            const others = (r.invitees || []).filter(id => !people.some(p => p.id === id))
            if (JSON.stringify(before) !== JSON.stringify(after)) changes.push({ thread: r.thread, participants: others.concat(after) })
        }
        close(); saved(changes)
    }

    component Box: Rectangle {
        id: bx
        property bool checked: false
        property bool mixed: false
        signal toggled()
        width: 16; height: 16; radius: 2
        color: checked ? theme.brandFill : "transparent"
        border.color: checked ? theme.brandFill : theme.textStrong; border.width: 0.67
        FluentIcon { visible: bx.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand }
        Rectangle { visible: bx.mixed && !bx.checked; anchors.centerIn: parent; width: 8; height: 8; radius: 1; color: theme.brandFill }
        TapHandler { onTapped: bx.toggled() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: bx.checked
    }
    component DropButton: Rectangle {
        id: dbn
        property string label
        property string icon: ""
        property bool bordered: true
        property bool strong: false
        signal clicked()
        height: 31.33; radius: 4
        width: (icon ? 28 : 0) + dbText.implicitWidth + 24 + (bordered ? 24 : 0)
        color: dbHover.hovered && dbn.enabled ? theme.menuHover : bordered ? theme.surface : "transparent"
        border.color: bordered ? theme.stroke : "transparent"; border.width: 0.67
        FluentIcon { visible: dbn.icon.length > 0; x: bordered ? 12 : 0; anchors.verticalCenter: parent.verticalCenter; name: dbn.icon; size: 20; color: dbn.enabled ? theme.textStrong : theme.disabled }
        Text {
            id: dbText
            x: (dbn.icon ? 28 : 0) + (dbn.bordered ? 12 : 0); anchors.verticalCenter: parent.verticalCenter
            text: dbn.label
            font.family: theme.font; font.pixelSize: 14; font.weight: dbn.strong ? Font.DemiBold : Font.Normal
            color: dbn.enabled ? theme.text : theme.disabled
        }
        FluentIcon { x: dbText.x + dbText.implicitWidth + 6; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: dbn.enabled ? theme.textStrong : theme.disabled }
        HoverHandler { id: dbHover; cursorShape: dbn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: dbn.enabled; onTapped: dbn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: dbn.label
    }

    Text {
        x: 24.67; y: 24.67; width: 650.67; height: 28
        verticalAlignment: Text.AlignVCenter
        text: "Assign participants to breakout rooms"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Text {
        x: 24.67; y: 60.67; width: 650.67
        textFormat: Text.StyledText
        text: "Manually assign each person to a room, or choose <b>Shuffle</b> to assign everyone randomly."
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Rectangle {
        x: 24.67; y: 88.67; width: 650.67; height: 32; radius: 4
        color: theme.inputFilled
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
        TextInput {
            id: search
            x: 40; width: parent.width - 52; height: 32
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectByMouse: true
            onTextEdited: root.query = text
            Accessible.role: Accessible.EditableText
            Accessible.name: "Find participants"
            Text {
                visible: !search.text.length
                anchors.verticalCenter: parent.verticalCenter
                text: "Find participants"
                font: search.font; color: theme.textSecondary
            }
        }
    }
    DropButton {
        id: selectRoom
        x: 24.67; y: 128; bordered: false
        label: "Select a room"
        enabled: root.ticked.length > 0
        onClicked: selectRoomMenu.open()
        MenuPopup {
            id: selectRoomMenu
            y: parent.height + 4
            items: [{ label: "Unassigned" }].concat(root.rooms.map(r => ({ label: r.name })))
            onPicked: i => { root.place(root.ticked, i === 0 ? "" : root.rooms[i - 1].thread); root.ticked = [] }
        }
    }
    DropButton {
        x: 675.33 - width; y: 128
        icon: "arrow-shuffle-20"; label: "Shuffle"; strong: true
        enabled: root.rooms.length > 0 && root.people.length > 0
        onClicked: shuffleMenu.open()
        MenuPopup {
            id: shuffleMenu
            y: parent.height + 4
            items: [{ label: "Everyone" }, { label: "Only unassigned people", enabled: root.unassignedCount > 0 }]
            onPicked: i => root.shuffle(i === 1)
        }
    }
    // The table.
    Item {
        id: table
        x: 24.67; y: 167.33; width: 650.67; height: 222
        Item {
            width: parent.width; height: 33.33
            Box {
                x: 13.33; anchors.verticalCenter: parent.verticalCenter
                checked: root.shown.length > 0 && root.shown.every(p => root.ticked.indexOf(p.id) >= 0)
                mixed: root.ticked.length > 0
                onToggled: root.ticked = checked ? [] : root.shown.map(p => p.id)
                Accessible.name: "Select all"
            }
            Row {
                x: 52; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { text: "Name"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-up-12"; size: 12; color: theme.text }
            }
            Row {
                x: 357.33; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "call-rooms"; size: 20; color: theme.textStrong }
                Text { text: "Room"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
        }
        ListView {
            y: 33.33; width: parent.width; height: parent.height - y
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                required property var modelData
                width: table.width; height: 36
                Rectangle { anchors.fill: parent; color: rowHover.hovered ? theme.menuHover : "transparent" }
                HoverHandler { id: rowHover }
                Box {
                    x: 13.33; anchors.verticalCenter: parent.verticalCenter
                    checked: root.ticked.indexOf(parent.modelData.id) >= 0
                    onToggled: root.ticked = checked ? root.ticked.filter(x => x !== parent.modelData.id) : root.ticked.concat([parent.modelData.id])
                    Accessible.name: parent.modelData.name
                }
                Avatar { x: 52; anchors.verticalCenter: parent.verticalCenter; size: 24; name: parent.modelData.name; photoId: parent.modelData.id }
                Text {
                    x: 86; anchors.verticalCenter: parent.verticalCenter; width: 260; elide: Text.ElideRight
                    text: parent.modelData.name
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                DropButton {
                    x: 351.33; anchors.verticalCenter: parent.verticalCenter; bordered: false
                    label: root.roomName(root.assignment[parent.modelData.id] || "")
                    onClicked: personMenu.open()
                    MenuPopup {
                        id: personMenu
                        y: parent.height + 4
                        items: [{ label: "Unassigned" }].concat(root.rooms.map(r => ({ label: r.name })))
                        onPicked: i => root.place([parent.parent.modelData.id], i === 0 ? "" : root.rooms[i - 1].thread)
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.dividerSoft }
            }
        }
    }
    Row {
        x: 41.33; y: 397.33; spacing: 8
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-20-filled"; size: 20; color: theme.textStrong }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.people.length + " (" + root.unassignedCount + " unassigned)"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
        }
    }
    Row {
        x: 475.33; y: 445.33; spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: !root.changed ? theme.bgDisabled : saveHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.changed ? theme.textOnBrand : theme.disabled }
            HoverHandler { id: saveHover; cursorShape: root.changed ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: root.changed; onTapped: root.save() }
            Accessible.role: Accessible.Button
            Accessible.name: "Save"
        }
    }
}
