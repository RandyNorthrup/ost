import QtQuick
import QtQuick.Controls.Basic

// A meeting chat's Breakout Rooms tab (Teams' pre-meeting room
// assignment, chattabs.breakoutrooms), for the meeting's organizer.
// Measured on winpc 2026-11-16 at 892 x 571 (CSS px, docs/spec/add-a-tab.md):
// - no fill of its own (the window's #EBEBEB), padding 14 0 0 21;
// - "Assign participants" (174 x 31.3, its people icon, 14/600; off and
//   #F0F0F0 / #BDBDBD until there are rooms) at (21, 14);
// - the room actions, 32 x 32, 5 apart and 20 from the right: Add room
//   and Remove (off until there are rooms), Room settings;
// - with no rooms, centred on the area right of the padding: the picture
//   (220 x 142.3) at 138.1, "Create breakout rooms" (24/32 bold) at
//   312.4, "See your rooms and set them up the way you want, all right
//   here." (16/22.86) at 360.4, Create rooms (brand, 110.3 x 31.3) at
//   415.3 and Import from CSV (outline, 132.9 x 31.3) at 462.6;
// - Create rooms asks "How many rooms do you need?" (a number, 2 at
//   first) in a 600-wide dialog ("Create rooms", 20/28 semibold; Cancel
//   and Add rooms).
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
    readonly property bool busy: !!state_ && !!state_.busy
    readonly property bool hasRooms: rooms.length > 0
    function act(action, args) { backend.meetingBreakoutAction(thread, organizer, action, JSON.stringify(args || {})) }
    onThreadChanged: if (thread && organizer) act("refresh")
    Component.onCompleted: if (thread && organizer) act("refresh")

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
        enabled: root.hasRooms && !root.busy
        onClicked: assignNote.open()
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 20; y: 14; spacing: 5
        Accessible.role: Accessible.ToolBar; Accessible.name: qsTr("Room action buttons")
        ToolButton32 { icon: "add-20"; tip: qsTr("Add room"); enabled: root.hasRooms && !root.busy; onClicked: root.act("add", { name: "Room " + (root.rooms.length + 1) }) }
        ToolButton32 { icon: "delete-20"; tip: qsTr("Remove rooms"); enabled: root.hasRooms && !root.busy; onClicked: root.act("delete_all") }
        ToolButton32 { icon: "settings-20"; tip: qsTr("Rooms settings"); enabled: !root.busy; onClicked: settingsNote.open() }
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
        Button31 { anchors.horizontalCenter: parent.horizontalCenter; y: 462.6; width: 132.9; label: qsTr("Import from CSV"); enabled: !root.busy; onClicked: csvNote.open() }
    }

    // The rooms.
    ListView {
        visible: root.hasRooms
        x: 21; y: 61.3; width: parent.width - 41; height: parent.height - y - 20
        clip: true; spacing: 8
        model: root.rooms
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width; height: 48; radius: 4
            color: theme.surface; border.width: 0.67; border.color: theme.cardStroke
            FluentIcon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "people-team-20"; size: 20; color: theme.textStrong }
            Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                text: (modelData.participants || []).length + ((modelData.participants || []).length === 1 ? " participant" : " participants")
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
            }
            Accessible.role: Accessible.ListItem; Accessible.name: modelData.name
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
    // What OST doesn't do in this tab yet says so.
    component Note: Popup {
        id: note
        property string text
        anchors.centerIn: Overlay.overlay
        modal: true; width: 420; padding: 24
        background: FluentSurface { depth: 64; radius: 8 }
        contentItem: Column {
            spacing: 16
            Text { width: parent.width; wrapMode: Text.Wrap; text: note.text; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Button31 { anchors.right: parent.right; width: 96; label: qsTr("OK"); primary: true; onClicked: note.close() }
        }
    }
    Note { id: assignNote; text: qsTr("Assign participants from the meeting window's Breakout rooms pane.") }
    Note { id: settingsNote; text: qsTr("Change room settings from the meeting window's Breakout rooms pane.") }
    Note { id: csvNote; text: qsTr("Import rooms from CSV from the meeting window's Breakout rooms pane.") }

    function createForTest(n) { createDialog.start(); createDialog.count = n }
}
