import QtQuick
import QtQuick.Controls

// Teams' "Pause notifications until" (Pause notifications ▸ Custom,
// measured on winpc 2026-11-09): a 600 x 170 Fluent dialog, radius 8,
// padding 16, over a 40 % backdrop:
// - the title (20/28 semibold) and Close (32 x 31.3);
// - "Date" and "Time" (14/20, 24 tall) over a date picker and a time
//   dropdown, each 277.3 wide, 12 apart, from y 82;
// - Cancel and Save (96 x 31.3) at y 122.
// It starts at the next half hour (Teams' ds()); dates run from today to a
// year ahead; times are every 30 minutes, those already past today greyed;
// picking a date keeps the time unless that is past (then the next half
// hour); Save is off while the time is past. Saved: paused (Do not
// disturb) until then.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 170
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property date until: new Date()
    signal saved(date until)

    function nextSlot(d) { const ms = 30 * 60000; return new Date(Math.floor(d.getTime() / ms) * ms + ms) }
    function start() { until = nextSlot(new Date()); open() }
    readonly property date today: { const d = new Date(); d.setHours(0, 0, 0, 0); return d }
    readonly property date yearAhead: { const d = new Date(); d.setFullYear(d.getFullYear() + 1); return d }
    readonly property bool past: until.getTime() <= Date.now()
    // The day's 48 half hours.
    readonly property var slots: {
        const day = new Date(until.getFullYear(), until.getMonth(), until.getDate())
        const isToday = day.getTime() === new Date(new Date().setHours(0, 0, 0, 0)).getTime()
        const now = Date.now()
        const out = []
        for (let i = 0; i < 48; i++) {
            const t = new Date(day.getTime()); t.setMinutes(i * 30)
            out.push({ label: Qt.formatTime(t, "h:mm AP"), time: t, disabled: isToday && t.getTime() <= now })
        }
        return out
    }

    Text { x: 16.67; y: 16.67; height: 31.33; verticalAlignment: Text.AlignVCenter; text: "Pause notifications until"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Rectangle {
        x: 551.33; y: 16.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    Text { x: 16.67; y: 56; height: 24; verticalAlignment: Text.AlignVCenter; text: "Date"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
    DatePickerField {
        id: datePick
        x: 16.67; y: 82; width: 277.33
        date: root.until
        minDate: root.today; maxDate: root.yearAhead
        onPicked: d => {
            const t = new Date(d.getFullYear(), d.getMonth(), d.getDate(), root.until.getHours(), root.until.getMinutes())
            root.until = t.getTime() <= Date.now() ? root.nextSlot(new Date()) : t
        }
    }
    Text { x: 306; y: 56; height: 24; verticalAlignment: Text.AlignVCenter; text: "Time"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
    OutlineDropdown {
        x: 306; y: 82.33; width: 277.33; height: 31.67
        accessibleName: "Time"
        options: root.slots
        current: root.until.getHours() * 2 + Math.floor(root.until.getMinutes() / 30)
        onPicked: i => root.until = root.slots[i].time
    }
    Row {
        x: 383.33; y: 122; spacing: 8
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
            color: root.past ? theme.bgDisabled : saveHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.past ? theme.disabled : "white" }
            HoverHandler { id: saveHover; cursorShape: root.past ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { enabled: !root.past; onTapped: { root.close(); root.saved(root.until) } }
            Accessible.role: Accessible.Button
            Accessible.name: "Save"
        }
    }
    function datePickerForTest() { return datePick }
}
