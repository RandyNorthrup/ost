import QtQuick
import QtQuick.Controls.Basic

// Fluent's DatePicker as Teams uses it (Pause notifications until, measured
// on winpc 2026-11-09):
// - the field: an outline input, 32 tall, radius 4, the date as M/d/yy
//   (14 px, 12 in) and calendar-ltr (20, #616161) 10 from the right;
// - its popup, left-aligned under the field: white, radius 4, shadow16,
//   440 x 241: the day picker (the month 14/28 semibold at 22, 16.7;
//   previous / next month 28 x 28 at 152 and 180; weekday letters 12/20 in
//   28 x 24 cells from 12, 44; days 24 x 24 from 14, 70 every 28; today a
//   20 px brand circle with white semibold digits; the chosen day #DCE0FA
//   with a brand 0.67 border, radius 4; other months' days #707070; days
//   outside min / max #BDBDBD and inert), a divider, and the month picker
//   (the year 14 semibold in a 140 x 28 button at 232.7, 12 that switches
//   to the years; previous / next year at 372.7 and 400.7; months 40 x 40
//   from 232.7, 44 every 52 across and 56 down; "Go to today" 12 px at
//   353.6, 211, greyed while today's month is shown).
Item {
    id: root
    property date date: new Date()
    property date minDate: new Date(1900, 0, 1)
    property date maxDate: new Date(2999, 11, 31)
    signal picked(date date)
    /// How the field writes the date, and Fluent's filled-darker look
    /// (Schedule message: #F5F5F5, the underline only).
    property string format: "M/d/yy"
    property bool filled: false
    implicitWidth: 277.3; implicitHeight: 32

    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    function inRange(d) { return dayStart(d) >= dayStart(minDate) && dayStart(d) <= dayStart(maxDate) }
    function monthInRange(y, m) { return new Date(y, m + 1, 0) >= dayStart(minDate) && new Date(y, m, 1) <= dayStart(maxDate) }
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    Rectangle {
        id: field
        anchors.fill: parent; radius: 4
        color: root.filled ? theme.pick("#F5F5F5", "#141414") : theme.surface
        border.color: root.filled ? "transparent" : fieldHover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: popup.opened ? 2 : 0.67; color: popup.opened ? theme.brand : theme.textSecondary }
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(root.date, root.format)
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "calendar-ltr-20"; size: 20; color: theme.textSecondary }
        HoverHandler { id: fieldHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: popup.opened ? popup.close() : popup.open() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: "Date, " + Qt.formatDate(root.date, root.format)
    }

    Popup {
        id: popup
        y: root.height + 0.67
        padding: 0
        width: 441.3; height: 242.3
        // What the pickers show (not the chosen date until a day is picked).
        property int year: root.date.getFullYear()
        property int month: root.date.getMonth()
        property bool years: false
        onAboutToShow: { year = root.date.getFullYear(); month = root.date.getMonth(); years = false }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

        // Day picker.
        Item {
            x: 0.67; y: 0.67; width: 220; height: 241
            Text { x: 22; y: 16.7; height: 18.7; verticalAlignment: Text.AlignVCenter; text: root.monthNames[popup.month] + " " + popup.year; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            NavButton { x: 152; y: 12; icon: "arrow-up-16"; enabled: root.monthInRange(popup.month === 0 ? popup.year - 1 : popup.year, (popup.month + 11) % 12); label: "Go to previous month"
                onClicked: { if (popup.month === 0) { popup.month = 11; popup.year-- } else popup.month-- } }
            NavButton { x: 180; y: 12; icon: "arrow-down-16"; enabled: root.monthInRange(popup.month === 11 ? popup.year + 1 : popup.year, (popup.month + 1) % 12); label: "Go to next month"
                onClicked: { if (popup.month === 11) { popup.month = 0; popup.year++ } else popup.month++ } }
            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                Text { required property string modelData; required property int index; x: 12 + 28 * index; y: 44; width: 28; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: modelData; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            }
            Repeater {
                // The weeks that hold this month's days, from Sunday.
                model: {
                    const first = new Date(popup.year, popup.month, 1)
                    const start = new Date(popup.year, popup.month, 1 - first.getDay())
                    const days = new Date(popup.year, popup.month + 1, 0).getDate()
                    const weeks = Math.ceil((first.getDay() + days) / 7)
                    const out = []
                    for (let i = 0; i < weeks * 7; i++) out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i))
                    return out
                }
                Rectangle {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool usable: root.inRange(modelData)
                    readonly property bool today: root.sameDay(modelData, new Date())
                    readonly property bool chosen: root.sameDay(modelData, root.date)
                    x: 14 + 28 * (index % 7); y: 70 + 28 * Math.floor(index / 7); width: 24; height: 24; radius: 4
                    color: chosen ? theme.pick("#DCE0FA", "#2F2F4A") : dayHover.hovered && usable ? theme.menuHover : "transparent"
                    border.color: chosen ? theme.brand : "transparent"; border.width: chosen ? 0.67 : 0
                    Rectangle { visible: day.today; anchors.centerIn: parent; width: 20; height: 20; radius: 10; color: theme.brand }
                    Text {
                        anchors.centerIn: parent
                        text: day.modelData.getDate()
                        font.family: theme.font; font.pixelSize: 12; font.weight: day.today ? Font.DemiBold : Font.Normal
                        color: day.today ? "white" : !day.usable ? theme.disabled : day.modelData.getMonth() !== popup.month ? theme.pick("#707070", "#ADADAD") : theme.text
                    }
                    HoverHandler { id: dayHover; cursorShape: day.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: day.usable; onTapped: { root.picked(day.modelData); popup.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: day.modelData.getDate() + ", " + root.monthNames[day.modelData.getMonth()] + ", " + day.modelData.getFullYear()
                }
            }
        }
        Rectangle { x: 220.67; y: 0.67; width: 1; height: 241; color: theme.dividerSoft }

        // Month picker (or the years).
        Item {
            x: 0.67; y: 0.67; width: 440; height: 241
            Rectangle {
                x: 232.7; y: 12; width: 140; height: 28; radius: 4
                color: yearHover.hovered && !popup.years ? theme.menuHover : "transparent"
                Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: popup.years ? (popup.year - popup.year % 10) + " - " + (popup.year - popup.year % 10 + 9) : popup.year; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: yearHover; cursorShape: popup.years ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { enabled: !popup.years; onTapped: popup.years = true }
                Accessible.role: Accessible.Button
                Accessible.name: popup.year + ", change year"
            }
            NavButton { x: 372.7; y: 12; icon: "arrow-up-16"; label: popup.years ? "Previous decade" : "Go to previous year"
                enabled: popup.years ? popup.year - popup.year % 10 - 1 >= root.minDate.getFullYear() : popup.year - 1 >= root.minDate.getFullYear()
                onClicked: popup.year -= popup.years ? 10 : 1 }
            NavButton { x: 400.7; y: 12; icon: "arrow-down-16"; label: popup.years ? "Next decade" : "Go to next year"
                enabled: popup.years ? popup.year - popup.year % 10 + 10 <= root.maxDate.getFullYear() : popup.year + 1 <= root.maxDate.getFullYear()
                onClicked: popup.year += popup.years ? 10 : 1 }
            Repeater {
                model: 12
                Rectangle {
                    id: cell
                    required property int index
                    readonly property int yearShown: popup.year - popup.year % 10 + index
                    readonly property bool usable: popup.years ? yearShown >= root.minDate.getFullYear() && yearShown <= root.maxDate.getFullYear() : root.monthInRange(popup.year, index)
                    visible: !popup.years || index < 10
                    x: 232.7 + 52 * (index % 4); y: 44 + 56 * Math.floor(index / 4); width: 40; height: 40; radius: 4
                    color: cellHover.hovered && usable ? theme.menuHover : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: popup.years ? cell.yearShown : root.monthNames[cell.index].slice(0, 3)
                        font.family: theme.font; font.pixelSize: 12
                        color: cell.usable ? theme.textStrong : theme.disabled
                    }
                    HoverHandler { id: cellHover; cursorShape: cell.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: cell.usable; onTapped: { if (popup.years) { popup.year = cell.yearShown; popup.years = false } else popup.month = cell.index } }
                    Accessible.role: Accessible.Button
                    Accessible.name: popup.years ? String(cell.yearShown) : root.monthNames[cell.index]
                }
            }
            Text {
                id: goToday
                readonly property bool usable: !(popup.year === new Date().getFullYear() && popup.month === new Date().getMonth()) || popup.years
                x: 353.6; y: 211; height: 30; verticalAlignment: Text.AlignVCenter
                text: "Go to today"
                font.family: theme.font; font.pixelSize: 12
                color: usable ? theme.text : theme.disabled
                HoverHandler { cursorShape: goToday.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: goToday.usable; onTapped: { const t = new Date(); popup.year = t.getFullYear(); popup.month = t.getMonth(); popup.years = false } }
                Accessible.role: Accessible.Button
                Accessible.name: "Go to today"
            }
        }
    }
    function openForTest() { popup.open() }

    component NavButton: Rectangle {
        id: nb
        property string icon
        property string label
        signal clicked()
        width: 28; height: 28; radius: 4
        color: nbHover.hovered && enabled ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: nb.icon; size: 16; color: nb.enabled ? theme.textSecondary : theme.disabled }
        HoverHandler { id: nbHover; cursorShape: nb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: nb.enabled; onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
