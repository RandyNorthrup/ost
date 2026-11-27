import QtQuick
import QtQuick.Controls.Basic

// Teams' "Create a custom reminder" (Remind me ▸ Custom; chat-app 300780
// `nk`, measured on Teams on the web 2026-11-27): a 600 x 202 Fluent
// dialog, padding 24, radius 8:
// - the title (20/28 semibold) at 25; "Set your custom date and time"
//   (14/20) 8 under it;
// - 24 under that, the date (a 271 x 32 outline field: "Fri Nov 27 2026"
//   and the calendar icon; Fluent's day picker, from today up to
//   messageReminderCustomDatePickerMaxMonths, 24, months on) and, 8 to its
//   right, the time (271 x 32, 30-minute steps; today from the current
//   hour, the next one past the half hour);
// - 8 under them, Cancel and Add (96 x 32, 8 apart) at the end.
// It opens on the reminder already set when that is still to come, else
// now rounded up to the next half hour. A time earlier than now is put
// back to that; Add sets the reminder.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 202
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// The reminder already set (to edit), or null.
    property var due: null
    signal added(date when)

    readonly property int maxMonths: 24
    property date day: new Date()
    property int slot: 0
    // The next half hour strictly after now (at 10:00:20, 10:30).
    function nextHalfHour() {
        const d = new Date()
        d.setSeconds(0, 0)
        if (d.getMinutes() < 30) d.setMinutes(30)
        else d.setHours(d.getHours() + 1, 0)
        return d
    }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    // The time list: 30-minute steps; today it starts at the current hour
    // (the next one from half past).
    readonly property var slots: {
        const now = new Date()
        const first = sameDay(day, now) ? now.getHours() * 2 + (now.getMinutes() >= 30 ? 2 : 0) : 0
        const out = []
        for (let i = first; i < 48; i++) {
            const t = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(i / 2), (i % 2) * 30)
            out.push({ label: theme.time(t), at: t.getTime() })
        }
        return out
    }
    function choose(when) {
        day = new Date(when.getFullYear(), when.getMonth(), when.getDate())
        const i = slots.findIndex(s => s.at >= when.getTime())
        slot = Math.max(0, i)
    }
    readonly property var chosen: slots.length ? new Date(slots[Math.min(slot, slots.length - 1)].at) : nextHalfHour()
    onAboutToShow: choose(due && due.getTime() > Date.now() ? due : nextHalfHour())
    function addForTest() { add() }
    function add() {
        let when = chosen
        if (when.getTime() <= Date.now()) when = nextHalfHour()
        root.added(when)
        root.close()
    }

    Text {
        x: 25; y: 25; height: 28; verticalAlignment: Text.AlignVCenter
        text: qsTr("Create a custom reminder")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading
    }
    Text {
        x: 25; y: 61; height: 20; verticalAlignment: Text.AlignVCenter
        text: qsTr("Set your custom date and time")
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    DatePickerField {
        x: 25; y: 105; width: 271; height: 32
        format: "ddd MMM d yyyy"
        monthPicker: false
        date: root.day
        minDate: new Date()
        maxDate: { const d = new Date(); d.setMonth(d.getMonth() + root.maxMonths); return d }
        onPicked: d => {
            const t = root.chosen
            const when = new Date(d.getFullYear(), d.getMonth(), d.getDate(), t.getHours(), t.getMinutes())
            root.choose(when.getTime() <= Date.now() ? root.nextHalfHour() : when)
        }
        Accessible.name: qsTr("Set your custom due date")
    }
    OutlineDropdown {
        x: 304; y: 105; width: 271; height: 32
        options: root.slots
        current: Math.min(root.slot, root.slots.length - 1)
        accessibleName: qsTr("Set your custom due time")
        onPicked: i => root.slot = i
    }
    Row {
        x: 600 - 25 - width; y: 145; spacing: 8
        Rectangle {
            id: hcFill1
            width: 96; height: 32; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel")
            Accessible.onPressAction: root.close()
        }
        Rectangle {
            id: hcFill2
            width: 96; height: 32; radius: 4
            color: addHover.hovered ? theme.brandHover : theme.checkedFill
            Text { anchors.centerIn: parent; text: qsTr("Add"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, "white") }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.add() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add")
            Accessible.onPressAction: root.add()
        }
    }
}
