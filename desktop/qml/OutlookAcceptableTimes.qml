import QtQuick
import QtQuick.Controls.Basic

// "Acceptable times" of Outlook's "If conflicts arise, let Copilot
// reschedule this event." (Teams desktop on winpc, 2026-11-24, CSS px): a
// white popover 526 x 296.67 under the row (radius 4):
// - "You and attendees will be notified if Copilot automatically
//   reschedules this event." 12 px #424242 at 16.67, 16.67;
// - "Select acceptable day(s):" 16/600 at 16.67, 47.33 over a month (the
//   month 14/600 at 26.67, 76.33, ↑ ↓ 12 px at 164.67 and 192.67; the day
//   names 12 px in 28 wide columns from 16.67, 103.67, 24 tall; the days
//   24 px in 28 px cells 28 apart; past days #BDBDBD, next month's #707070,
//   today brand; picked days on #DCE0FA, a run's ends rounded 4);
// - "Select acceptable time(s):" 16/600 at 230.67, 47.33: Morning (before
//   12:00 PM), Midday (12:00 PM - 1:00 PM), Afternoon (after 1:00 PM),
//   Custom (16 px boxes at 238.67, the labels 14 px at 262.67, 42 apart
//   from 66.67), and Custom's start → end times (105.33 x 33.33 at 262.67
//   and 404, 236.67 down; the arrow 20 px at 376).
// Morning, Midday and Afternoon are Outlook's minute ranges 0..720,
// 720..780 and 780..1440; Custom is its start..end.
Popup {
    id: pop
    property var form: null
    width: series ? 606 : 526; height: 296.67
    /// A series: weekdays instead of a month (Outlook's form, 606 wide; the
    /// times 80 further right).
    readonly property bool series: !!form && form.acceptSeries
    readonly property real tx: series ? 80 : 0
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
    property date month: new Date()
    onOpened: { const d = new Date(); month = new Date(d.getFullYear(), d.getMonth(), 1) }
    readonly property var presets: [[0, 720], [720, 780], [780, 1440]]
    function iso(d) { return form ? form.isoDay(d) : "" }
    function hasTime(t) { return !!form && form.acceptTimes.some(x => x[0] === t[0] && x[1] === t[1]) }
    readonly property var custom: form ? (form.acceptTimes.find(x => !presets.some(p => p[0] === x[0] && p[1] === x[1])) || null) : null
    function toggleTime(t) {
        if (!form) return
        const l = form.acceptTimes.filter(x => !(x[0] === t[0] && x[1] === t[1]))
        if (l.length === form.acceptTimes.length) l.push(t)
        if (l.length) form.acceptTimes = l.sort((a, b) => a[0] - b[0])
    }
    // Custom's times: from the event's start, an hour long.
    property int customFrom: form ? form.startAt.getHours() * 60 + form.startAt.getMinutes() : 540
    property int customTo: Math.min(1440, customFrom + 60)
    function toggleCustom() {
        if (!form) return
        if (custom) { const l = form.acceptTimes.filter(x => x !== custom); if (l.length) form.acceptTimes = l }
        else form.acceptTimes = form.acceptTimes.concat([[customFrom, customTo]]).sort((a, b) => a[0] - b[0])
    }
    function setCustom(a, b) {
        customFrom = a; customTo = Math.max(a + 15, b)
        if (custom && form) form.acceptTimes = form.acceptTimes.filter(x => x !== custom).concat([[customFrom, customTo]]).sort((x, y) => x[0] - y[0])
    }
    function minLabel(m) { const d = new Date(2000, 0, 1, Math.floor(m / 60), m % 60); return m >= 1440 ? theme.fmtTime(new Date(2000, 0, 1, 0, 0), "h:mm AP") : theme.fmtTime(d, "h:mm AP") }

    Text { x: 16.67; y: 16.67; width: 492.67; height: 16; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
           text: qsTr("You and attendees will be notified if Copilot automatically reschedules this event."); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
    Text { x: 16.67; y: 47.33; height: 21.33; verticalAlignment: Text.AlignVCenter; text: qsTr("Select acceptable day(s):"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
    Text { visible: !pop.series; x: 26.67; y: 76.33; height: 18.67; verticalAlignment: Text.AlignVCenter; text: theme.fmtDate(pop.month, "MMMM yyyy"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
    Repeater {
        model: [["arrow-up-16", -1, 164.67, qsTr("Go to previous month")], ["arrow-down-16", 1, 192.67, qsTr("Go to next month")]]
        Item {
            id: nav
            required property var modelData
            visible: !pop.series; x: modelData[2] - 6; y: 72.33; width: 24; height: 24
            readonly property bool off: modelData[1] < 0 && pop.month <= new Date(new Date().getFullYear(), new Date().getMonth(), 1)
            FluentIcon { anchors.centerIn: parent; name: nav.modelData[0]; size: 12; color: nav.off ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : theme.textSecondary }
            TapHandler { enabled: !nav.off; onTapped: pop.month = new Date(pop.month.getFullYear(), pop.month.getMonth() + nav.modelData[1], 1) }
            Accessible.role: Accessible.Button
            Accessible.name: nav.modelData[3]
        }
    }
    Repeater {
        model: 7
        Text {
            required property int index
            visible: !pop.series; x: 16.67 + index * 28; y: 103.67; width: 28; height: 24
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: Qt.locale().dayName(index, Locale.NarrowFormat); font.family: theme.font; font.pixelSize: 12; color: theme.text
        }
    }
    Repeater {
        model: 42
        Item {
            id: cell
            required property int index
            readonly property date day: { const f = new Date(pop.month); f.setDate(1 - f.getDay() + index); return f }
            readonly property bool inMonth: day.getMonth() === pop.month.getMonth()
            readonly property bool past: { const t = new Date(); t.setHours(0, 0, 0, 0); return day < t }
            readonly property bool today: day.toDateString() === new Date().toDateString()
            readonly property bool picked: !!pop.form && pop.form.acceptDays.indexOf(pop.iso(day)) >= 0
            readonly property bool prevPicked: { const d = new Date(day); d.setDate(d.getDate() - 1); return index % 7 > 0 && !!pop.form && pop.form.acceptDays.indexOf(pop.iso(d)) >= 0 }
            readonly property bool nextPicked: { const d = new Date(day); d.setDate(d.getDate() + 1); return index % 7 < 6 && !!pop.form && pop.form.acceptDays.indexOf(pop.iso(d)) >= 0 }
            visible: !pop.series && Math.floor(index / 7) < Math.ceil((pop.month.getDay() + new Date(pop.month.getFullYear(), pop.month.getMonth() + 1, 0).getDate()) / 7)
            x: 16.67 + (index % 7) * 28; y: 127.67 + Math.floor(index / 7) * 28; width: 28; height: 28
            Rectangle {
                visible: cell.picked
                anchors.fill: parent
                color: theme.pick("#DCE0FA", "#2F2F4A", "#1AEBFF")
                radius: !cell.prevPicked || !cell.nextPicked ? 4 : 0
                Rectangle { visible: cell.prevPicked && !cell.nextPicked; width: 6; height: parent.height; color: parent.color }
                Rectangle { visible: cell.nextPicked && !cell.prevPicked; x: parent.width - 6; width: 6; height: parent.height; color: parent.color }
            }
            Rectangle {
                visible: cell.today
                x: 2; y: 2; width: 24; height: 24; radius: 12; color: theme.brand
            }
            Text {
                anchors.centerIn: parent
                text: cell.day.getDate()
                font.family: theme.font; font.pixelSize: 12; font.weight: cell.today ? Font.DemiBold : Font.Normal
                color: cell.today ? "white" : cell.past ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : !cell.inMonth ? theme.pick("#707070", "#ADADAD", "#FFFFFF") : theme.text
            }
            TapHandler {
                enabled: !cell.past
                onTapped: {
                    const k = pop.iso(cell.day), l = pop.form.acceptDays.slice(), i = l.indexOf(k)
                    if (i >= 0) { if (l.length > 1) l.splice(i, 1) } else l.push(k)
                    pop.form.acceptDays = l.sort()
                }
            }
            Accessible.role: Accessible.CheckBox
            Accessible.name: theme.fmtDate(cell.day, "d, MMMM, yyyy")
            Accessible.checked: cell.picked
        }
    }
    // A series' weekdays (winpc 2026-11-24): seven 32 x 31.33 circles 42
    // apart from 16.67, 68.67 (S M T W T F S, 14/600); a picked one on
    // #EBEBEB (#242424), the others #424242; the series' own days stay
    // picked.
    Repeater {
        model: pop.series ? 7 : 0
        Rectangle {
            id: wd
            required property int index
            readonly property bool required: !!pop.form && pop.form.seriesWeekdays.indexOf(index) >= 0
            readonly property bool picked: required || (!!pop.form && pop.form.acceptWeekdays.indexOf(index) >= 0)
            x: 16.67 + index * 42; y: 68.67; width: 32; height: 31.33; radius: height / 2
            color: picked ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : wdHover.hovered ? theme.rowHover : "transparent"
            Text {
                anchors.centerIn: parent
                text: Qt.locale().dayName(wd.index, Locale.NarrowFormat); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: wd.picked ? theme.text : theme.textStrong
            }
            HoverHandler { id: wdHover; cursorShape: wd.required ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler {
                enabled: !wd.required
                onTapped: {
                    const l = pop.form.acceptWeekdays.slice(), i = l.indexOf(wd.index)
                    if (i >= 0) l.splice(i, 1); else l.push(wd.index)
                    pop.form.acceptWeekdays = l
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: Qt.locale().dayName(wd.index, Locale.LongFormat)
            Accessible.checked: wd.picked
            Accessible.checkable: true
        }
    }
    Text { x: 230.67 + pop.tx; y: 47.33; height: 21.33; verticalAlignment: Text.AlignVCenter; text: qsTr("Select acceptable time(s):"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
    Repeater {
        model: [qsTr("Morning (before 12:00 PM)"), qsTr("Midday (12:00 PM - 1:00 PM)"), qsTr("Afternoon (after 1:00 PM)"), qsTr("Custom")]
        Item {
            id: trow
            required property string modelData
            required property int index
            readonly property bool on: index < 3 ? pop.hasTime(pop.presets[index]) : !!pop.custom
            x: 230.67 + pop.tx; y: 66.67 + index * 42; width: 270; height: 36
            Rectangle {
                x: 8; y: 10; width: 16; height: 16; radius: 2
                color: trow.on ? theme.checkedFill : "transparent"; border.width: 0.67; border.color: trow.on ? theme.checkedFill : theme.textSecondary
                FluentIcon { visible: trow.on; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
            }
            Text { x: 32; height: 36; verticalAlignment: Text.AlignVCenter; text: trow.modelData; font.family: theme.font; font.pixelSize: 14; color: trow.on ? theme.text : theme.textSecondary }
            TapHandler { onTapped: trow.index < 3 ? pop.toggleTime(pop.presets[trow.index]) : pop.toggleCustom() }
            Accessible.role: Accessible.CheckBox
            Accessible.name: trow.modelData
            Accessible.checked: trow.on
        }
    }
    Repeater {
        model: [[262.67, true], [404, false]]
        Rectangle {
            id: tbox
            required property var modelData
            x: modelData[0] + pop.tx; y: 236.67; width: 105.33; height: 33.33; radius: 2
            color: "transparent"; border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
            opacity: pop.custom ? 1 : 0.6
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: pop.minLabel(tbox.modelData[1] ? pop.customFrom : pop.customTo); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            FluentIcon { x: 84.67; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
            TapHandler { enabled: !!pop.custom; onTapped: timeMenu.open() }
            MenuPopup {
                id: timeMenu
                y: tbox.height + 2
                items: Array.from({ length: 48 }, (_, i) => ({ label: pop.minLabel(i * 30), checked: (tbox.modelData[1] ? pop.customFrom : pop.customTo) === i * 30 }))
                onPicked: i => tbox.modelData[1] ? pop.setCustom(i * 30, Math.max(pop.customTo, i * 30 + 30)) : pop.setCustom(pop.customFrom, Math.max(i * 30, pop.customFrom + 15))
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: tbox.modelData[1] ? qsTr("Start time") : qsTr("End time")
        }
    }
    FluentIcon { x: 376 + pop.tx; y: 243.33; name: "arrow-right-20"; size: 20; color: theme.textStrong }
}
