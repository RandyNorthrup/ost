import QtQuick
import QtQuick.Controls.Basic

// Reminder ▸ Add email reminder: Outlook's "Email reminder" dialog (Teams
// desktop on winpc, 2026-11-24, CSS px): 660 x 600, white, radius 2, over a
// 40 % black veil; "Email reminder" 21/600 #616161 at 30, 30 (50 tall),
// Close (a 16 px brand ✕ in 32 x 32) at 598, 30; "Add an email reminder to
// stay on top of this event." 14 px at 30, 80 over a #F0F0F0 line; each
// reminder "Remind me: 15 minutes before" 14 px at 60 with its message
// under it (#8A8A8A) and Edit / Remove (16 px brand) at 574 and 606; "+ Add
// email reminder" (brand) under them. Adding or editing one: the mail glyph
// at 30, "Remind me:" and its dropdown (At time of event, 5, 15, 30
// minutes, 1, 2, 12 hours, 1 day, 1 week before), "Enter a reminder message
// here (optional)" (570 x 61.33, a 0.67 #F0F0F0 edge), a meeting's "Send to
// attendees", Save (80 x 32 brand) and Discard (87.13 x 32, #F5F5F5).
// The reminders are saved when the dialog closes (InboxReminders).
Popup {
    id: dlg
    /// A meeting (it has attendees): Send to attendees.
    property bool meeting: false
    signal saved(var list)
    parent: Overlay.overlay
    modal: true; padding: 0
    x: (parent.width - width) / 2; y: Math.max(16, (parent.height - height) / 2)
    width: 660; height: 600
    closePolicy: Popup.CloseOnEscape
    background: Rectangle { radius: 2; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property var list: []
    property var original: []
    /// The row being edited (-1 a new one, -2 none).
    property int editing: -2
    property int offset: 15
    function openFor(l) { list = (l || []).slice(); original = JSON.stringify(list); editing = -2; offset = 15; message.text = ""; toAll = false; open() }
    function finish() { close(); if (JSON.stringify(list) !== original) saved(list) }
    property bool toAll: false
    readonly property var offsets: [0, 5, 15, 30, 60, 120, 720, 1440, 10080]
    function offsetLabel(m) {
        if (m === 0) return qsTr("At time of event")
        if (m < 60) return qsTr("%n minutes before", "", m)
        if (m < 1440) return qsTr("%n hours before", "", m / 60)
        if (m < 10080) return qsTr("%n days before", "", m / 1440)
        return qsTr("%n weeks before", "", m / 10080)
    }
    function edit(i) { editing = i; const r = list[i]; offset = r.offset; message.text = r.message || ""; toAll = r.sendOption === "AllAttendees" }
    function saveRow() {
        const r = { id: editing >= 0 ? (list[editing].id || "") : "", offset: offset, message: message.text.trim(), sendOption: toAll ? "AllAttendees" : "User" }
        const l = list.slice()
        if (editing >= 0) l[editing] = r; else l.push(r)
        list = l; editing = -2; message.text = ""
    }

    Text { x: 30; y: 30; width: 568; height: 50; verticalAlignment: Text.AlignTop; text: qsTr("Email reminder"); font.family: theme.font; font.pixelSize: 21; font.weight: Font.DemiBold; color: theme.textSecondary; Accessible.role: Accessible.Heading }
    Item {
        x: 598; y: 30; width: 32; height: 32
        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.brand }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.finish() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }
    Text { x: 30; y: 80; width: 600; height: 40; text: qsTr("Add an email reminder to stay on top of this event."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
    Rectangle { x: 30; y: 138.67; width: 600; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }
    Column {
        x: 30; y: 139.33; width: 600; spacing: 0
        Repeater {
            model: dlg.list
            Item {
                id: rrow
                required property var modelData
                required property int index
                visible: dlg.editing !== index
                width: 600; height: visible ? 69.34 : 0
                FluentIcon { x: 0; y: 17.34; name: "mail-20"; size: 17; color: theme.textSecondary }
                Text { x: 30; y: 15.67; width: 506; height: 18.67; verticalAlignment: Text.AlignVCenter; text: qsTr("Remind me: %1").arg(dlg.offsetLabel(rrow.modelData.offset)); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Text { x: 30; y: 40; width: 506; height: 18.67; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: rrow.modelData.message || ""; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                Repeater {
                    model: [["edit-16", qsTr("Edit email reminder"), 544], ["delete-16", qsTr("Remove email reminder"), 576]]
                    Item {
                        id: rbtn
                        required property var modelData
                        x: modelData[2] - 8; y: 9; width: 32; height: 32
                        FluentIcon { anchors.centerIn: parent; name: rbtn.modelData[0]; size: 16; color: theme.brand }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rbtn.modelData[0] === "edit-16" ? dlg.edit(rrow.index) : dlg.list = dlg.list.filter((_, j) => j !== rrow.index) }
                        Accessible.role: Accessible.Button
                        Accessible.name: rbtn.modelData[1]
                    }
                }
            }
        }
        // Adding or editing one.
        Item {
            visible: dlg.editing !== -2
            width: 600; height: visible ? (dlg.meeting ? 199.33 : 163.33) : 0
            FluentIcon { x: 0; y: 16.34; name: "mail-20"; size: 17; color: theme.textSecondary; Accessible.name: qsTr("Email reminder") }
            Text { id: remindLabel; x: 30; y: 14.67; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Remind me:"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            Rectangle {
                id: offsetBox
                x: remindLabel.x + remindLabel.implicitWidth; y: 14.67; width: offsetText.implicitWidth + 34; height: 20
                color: theme.surface
                Text { id: offsetText; x: 6; anchors.verticalCenter: parent.verticalCenter; text: dlg.offsetLabel(dlg.offset); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { x: parent.width - 22; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                TapHandler { onTapped: offsetMenu.open() }
                MenuPopup {
                    id: offsetMenu
                    y: offsetBox.height + 5
                    items: dlg.offsets.map(m => ({ label: dlg.offsetLabel(m), checked: dlg.offset === m }))
                    onPicked: i => dlg.offset = dlg.offsets[i]
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Remind me:") + " " + offsetText.text
            }
            Rectangle {
                x: 30; y: 60; width: 570; height: 61.33; radius: 2
                color: theme.surface; border.width: 0.67; border.color: message.activeFocus ? theme.brand : theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
                TextEdit {
                    id: message
                    x: 8; y: 6; width: 554; height: 50
                    wrapMode: TextEdit.Wrap; clip: true; selectByMouse: true
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    Accessible.name: qsTr("Enter a reminder message here (optional)")
                    Text { visible: !message.text; text: qsTr("Enter a reminder message here (optional)"); font: message.font; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                }
            }
            Row {
                visible: dlg.meeting
                x: 30; y: 131.33; spacing: 8; height: 24
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 2
                    color: dlg.toAll ? theme.checkedFill : "transparent"; border.width: 0.67; border.color: dlg.toAll ? theme.checkedFill : theme.textSecondary
                    FluentIcon { visible: dlg.toAll; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Send to attendees"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                TapHandler { onTapped: dlg.toAll = !dlg.toAll }
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Send to attendees")
                Accessible.checked: dlg.toAll
            }
            Row {
                x: 30; y: dlg.meeting ? 167.33 : 131.33; spacing: 10
                Rectangle {
                    width: 80; height: 32; radius: 2; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.saveRow() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Save")
                }
                Rectangle {
                    width: 87.13; height: 32; radius: 2; color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                    Text { anchors.centerIn: parent; text: qsTr("Discard"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { dlg.editing = -2; message.text = "" } }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Discard")
                }
            }
        }
        Item {
            visible: dlg.editing === -2
            width: 600; height: 40
            FluentIcon { x: 0.67; y: 22; name: "add-16"; size: 16; color: theme.brand }
            Text { x: 24.67; y: 23; height: 14; verticalAlignment: Text.AlignVCenter; text: qsTr("Add email reminder"); font.family: theme.font; font.pixelSize: 14; color: theme.brand }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { dlg.editing = -1; dlg.offset = 15; message.text = ""; dlg.toAll = false } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add email reminder")
        }
    }
}
