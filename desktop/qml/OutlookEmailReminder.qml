import QtQuick
import QtQuick.Controls.Basic

// Reminder ▸ Add email reminder: Outlook's "Email reminder" dialog (Teams
// desktop on winpc, 2026-11-24, CSS px): 660 x 600, white, radius 2, over a
// 40 % black veil; "Email reminder" 21/600 #616161 at 30, 30 (50 tall),
// Close (a 16 px brand ✕ in 32 x 32) at 598, 30; "Add an email reminder to
// stay on top of this event." 14 px at 30, 80 over a #F0F0F0 line; each
// reminder "Remind me: 15 minutes before" (a custom time "Remind me: Wed
// 11/25/2026 at 9:15 AM") 14 px at 60 with its message under it (#8A8A8A,
// "(No Message)" when none) and Edit / Remove (16 px brand) at 574 and 606;
// "+ Add email reminder" (brand) under them. Adding or editing one: the
// mail glyph at 30, "Remind me:" and its dropdown (a list 129.73 wide 5
// under it, rows 36 tall, the text 7.67 in, the picked one #DCDFFA: At time
// of event, 5, 15, 30 minutes, 1, 2, 12 hours, 1 day, 1 week before, a 1 px
// #F0F0F0 divider, Custom); Custom adds a date (157 x 32 at 30, 58.17, a
// calendar glyph at its end, Outlook's month under it: 220 x 296, today
// brand, past days #D1D1D1, the picked day on #F0F0F0) and a time (157 x
// 31 at 217, typed or picked from a list of half hours 120 x 180), both
// starting at the event's start and underlined #F0F0F0, and moves the rest
// 54 down; "Enter a reminder message here (optional)" (570 x 61.33, a 0.67
// #F0F0F0 edge), a meeting's "Send to attendees", Save (80 x 32 brand) and
// Discard (87.13 x 32, #F5F5F5). Each Save and Remove is saved at once
// (InboxReminders; a custom time as its minutes before the event).
Popup {
    id: dlg
    /// A meeting (it has attendees): Send to attendees.
    property bool meeting: false
    /// The event's start (Custom's times are from it).
    property date eventStart: new Date()
    signal saved(var list)
    parent: Overlay.overlay
    modal: true; padding: 0
    x: (parent.width - width) / 2; y: Math.max(16, (parent.height - height) / 2)
    width: 660; height: 600
    closePolicy: Popup.CloseOnEscape
    background: Rectangle { radius: 2; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property var list: []
    /// The row being edited (-1 a new one, -2 none).
    property int editing: -2
    property int offset: 15
    /// Custom picked: the reminder's date and time.
    property bool custom: false
    property date customAt: new Date()
    function openFor(l) { list = (l || []).slice(); editing = -2; offset = 15; custom = false; message.text = ""; toAll = false; open() }
    function finish() { close() }
    property bool toAll: false
    readonly property var offsets: [0, 5, 15, 30, 60, 120, 720, 1440, 10080]
    function presetLabel(m) {
        if (m === 0) return qsTr("At time of event")
        if (m < 60) return qsTr("%n minutes before", "", m)
        if (m < 1440) return qsTr("%n hours before", "", m / 60)
        if (m < 10080) return qsTr("%n days before", "", m / 1440)
        return qsTr("%n weeks before", "", m / 10080)
    }
    /// A reminder's time: a preset's words, else the day and time it
    /// goes ("Wed 11/25/2026 at 9:15 AM").
    function offsetLabel(m) {
        if (offsets.indexOf(m) >= 0) return presetLabel(m)
        const d = new Date(eventStart.getTime() - m * 60000)
        return qsTr("%1 at %2").arg(theme.fmtDate(d, "ddd M/d/yyyy")).arg(theme.fmtTime(d, "h:mm AP"))
    }
    function edit(i) {
        editing = i; const r = list[i]; offset = r.offset; message.text = r.message || ""; toAll = r.sendOption === "AllAttendees"
        custom = offsets.indexOf(r.offset) < 0
        if (custom) customAt = new Date(eventStart.getTime() - r.offset * 60000)
    }
    function pickCustom() { custom = true; customAt = new Date(eventStart) }
    function saveRow() {
        const m = custom ? Math.round((eventStart.getTime() - customAt.getTime()) / 60000) : offset
        const r = { id: editing >= 0 ? (list[editing].id || "") : "", offset: m, message: message.text.trim(), sendOption: toAll ? "AllAttendees" : "User" }
        const l = list.slice()
        if (editing >= 0) l[editing] = r; else l.push(r)
        list = l; editing = -2; custom = false; message.text = ""
        saved(list)
    }
    function removeRow(i) { list = list.filter((_, j) => j !== i); saved(list) }
    /// A typed time ("9:15 AM", "21:15") on Custom's day.
    function setTyped(t) {
        const m = /^\s*(\d{1,2})(?::(\d{2}))?\s*([ap])?\.?\s*m?\.?\s*$/i.exec(t)
        if (!m) return false
        let h = +m[1], mi = +(m[2] || 0)
        if (m[3]) { h = h % 12 + (m[3].toLowerCase() === "p" ? 12 : 0) }
        if (h > 23 || mi > 59) return false
        const d = new Date(customAt); d.setHours(h, mi, 0, 0); customAt = d
        return true
    }
    readonly property color underline: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")

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
    Rectangle { x: 30; y: 138.67; width: 600; height: 0.67; color: dlg.underline }
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
                Text { x: 30; y: 40; width: 506; height: 18.67; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: rrow.modelData.message || qsTr("(No Message)"); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                Repeater {
                    model: [["edit-16", qsTr("Edit email reminder"), 544], ["delete-16", qsTr("Remove email reminder"), 576]]
                    Item {
                        id: rbtn
                        required property var modelData
                        x: modelData[2] - 8; y: 9; width: 32; height: 32
                        FluentIcon { anchors.centerIn: parent; name: rbtn.modelData[0]; size: 16; color: theme.brand }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rbtn.modelData[0] === "edit-16" ? dlg.edit(rrow.index) : dlg.removeRow(rrow.index) }
                        Accessible.role: Accessible.Button
                        Accessible.name: rbtn.modelData[1]
                    }
                }
            }
        }
        // Adding or editing one.
        Item {
            id: editRow
            visible: dlg.editing !== -2
            readonly property real shift: dlg.custom ? 54 : 0
            width: 600; height: visible ? (dlg.meeting ? 199.33 : 163.33) + shift : 0
            FluentIcon { x: 0; y: 16.34; name: "mail-20"; size: 17; color: theme.textSecondary; Accessible.name: qsTr("Email reminder") }
            Text { id: remindLabel; x: 30; y: 14.67; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Remind me:"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            Rectangle {
                id: offsetBox
                x: remindLabel.x + remindLabel.implicitWidth; y: 14.67; width: offsetText.implicitWidth + 34; height: 20
                color: theme.surface
                Text { id: offsetText; x: 6; anchors.verticalCenter: parent.verticalCenter; text: dlg.custom ? qsTr("Custom") : dlg.presetLabel(dlg.offset); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { x: parent.width - 22; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                TapHandler { onTapped: offsetList.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Remind me:") + " " + offsetText.text
                // Outlook's (Fabric) dropdown list.
                Popup {
                    id: offsetList
                    y: offsetBox.height + 5; padding: 0
                    width: 129.73; height: optCol.height
                    background: FluentSurface { depth: 8; radius: 0; color: theme.surface }
                    Column {
                        id: optCol
                        width: 129.73
                        Repeater {
                            model: dlg.offsets.map(m => [m, dlg.presetLabel(m)]).concat([[-1, ""], [-2, qsTr("Custom")]])
                            Item {
                                id: opt
                                required property var modelData
                                readonly property bool divider: modelData[0] === -1
                                readonly property bool picked: modelData[0] === -2 ? dlg.custom : !dlg.custom && dlg.offset === modelData[0]
                                width: 129.73; height: divider ? 1 : 36
                                Rectangle { anchors.fill: parent; visible: !opt.divider; color: opt.picked ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : optHover.hovered ? theme.rowHover : "transparent" }
                                Rectangle { anchors.fill: parent; visible: opt.divider; color: dlg.underline }
                                Text { visible: !opt.divider; x: 7.67; height: 36; verticalAlignment: Text.AlignVCenter; text: opt.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: opt.picked ? theme.text : theme.textSecondary }
                                HoverHandler { id: optHover; enabled: !opt.divider; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    enabled: !opt.divider
                                    onTapped: { if (opt.modelData[0] === -2) dlg.pickCustom(); else { dlg.custom = false; dlg.offset = opt.modelData[0] } offsetList.close() }
                                }
                                Accessible.role: opt.divider ? Accessible.Separator : Accessible.ListItem
                                Accessible.name: opt.modelData[1]
                                Accessible.selected: opt.picked
                            }
                        }
                    }
                }
            }
            // Custom's date and time.
            Item {
                visible: dlg.custom
                x: 30; y: 58.17; width: 157; height: 32
                Text { x: 8; height: 32; verticalAlignment: Text.AlignVCenter; text: theme.fmtDate(dlg.customAt, "M/d/yyyy"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { x: 133; y: 7; name: "calendar-20"; size: 18; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                Rectangle { y: 31; width: 157; height: 1; color: dlg.underline }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { datePop.month = new Date(dlg.customAt.getFullYear(), dlg.customAt.getMonth(), 1); datePop.open() } }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Select a date")
                Popup {
                    id: datePop
                    y: 37; padding: 0; width: 220; height: 296
                    background: FluentSurface { depth: 8; radius: 0; color: theme.surface }
                    property date month: new Date()
                    readonly property date today: { const t = new Date(); t.setHours(0, 0, 0, 0); return t }
                    readonly property bool thisMonth: month.getFullYear() === today.getFullYear() && month.getMonth() === today.getMonth()
                    Text { x: 22; y: 16.67; height: 18.67; verticalAlignment: Text.AlignVCenter; text: theme.fmtDate(datePop.month, "MMMM yyyy"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
                    Repeater {
                        model: [["arrow-up-16", -1, 160, qsTr("Go to previous month")], ["arrow-down-16", 1, 188, qsTr("Go to next month")]]
                        Item {
                            id: mnav
                            required property var modelData
                            readonly property bool off: modelData[1] < 0 && datePop.thisMonth
                            x: modelData[2] - 6; y: 12; width: 24; height: 28
                            FluentIcon { anchors.centerIn: parent; name: mnav.modelData[0]; size: 12; color: mnav.off ? theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") : theme.textSecondary }
                            TapHandler { enabled: !mnav.off; onTapped: datePop.month = new Date(datePop.month.getFullYear(), datePop.month.getMonth() + mnav.modelData[1], 1) }
                            Accessible.role: Accessible.Button; Accessible.name: mnav.modelData[3]
                        }
                    }
                    Repeater {
                        model: 7
                        Text {
                            required property int index
                            x: 12 + index * 28; y: 44; width: 28; height: 28
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: Qt.locale().dayName(index, Locale.NarrowFormat); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                        }
                    }
                    Repeater {
                        model: 42
                        Item {
                            id: dcell
                            required property int index
                            readonly property date day: { const f = new Date(datePop.month); f.setDate(1 - f.getDay() + index); return f }
                            readonly property bool past: day < datePop.today
                            readonly property bool isToday: day.getTime() === datePop.today.getTime()
                            readonly property bool picked: day.toDateString() === dlg.customAt.toDateString()
                            visible: Math.floor(index / 7) < Math.ceil((datePop.month.getDay() + new Date(datePop.month.getFullYear(), datePop.month.getMonth() + 1, 0).getDate()) / 7)
                            x: 12 + (index % 7) * 28; y: 72 + Math.floor(index / 7) * 28; width: 28; height: 28
                            Rectangle { visible: dcell.picked && !dcell.isToday; anchors.fill: parent; radius: 2; color: dlg.underline }
                            Rectangle { visible: dcell.isToday; x: 2; y: 2; width: 24; height: 24; radius: 12; color: theme.brand }
                            Text {
                                anchors.centerIn: parent; text: dcell.day.getDate()
                                font.family: theme.font; font.pixelSize: 12; font.weight: dcell.isToday ? Font.DemiBold : Font.Normal
                                color: dcell.isToday ? "white" : dcell.past ? theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") : theme.textSecondary
                            }
                            TapHandler {
                                enabled: !dcell.past
                                onTapped: { const d = new Date(dcell.day); d.setHours(dlg.customAt.getHours(), dlg.customAt.getMinutes(), 0, 0); dlg.customAt = d; datePop.close() }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: theme.fmtDate(dcell.day, "d, MMMM, yyyy")
                        }
                    }
                    Text {
                        x: 164.88; y: 265; width: 39.13; height: 30; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: qsTr("Today"); font.family: theme.font; font.pixelSize: 12
                        color: datePop.thisMonth ? theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") : theme.textSecondary
                        TapHandler { enabled: !datePop.thisMonth; onTapped: datePop.month = new Date(datePop.today.getFullYear(), datePop.today.getMonth(), 1) }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Go to today")
                    }
                }
            }
            Item {
                visible: dlg.custom
                x: 217; y: 59.17; width: 157; height: 31
                TextInput {
                    id: timeInput
                    x: 8; width: 124; height: 31; verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    text: theme.fmtTime(dlg.customAt, "h:mm AP")
                    onEditingFinished: { if (!dlg.setTyped(text)) text = theme.fmtTime(dlg.customAt, "h:mm AP") }
                    Accessible.name: qsTr("Select a time")
                }
                Item {
                    x: 132; width: 22; height: 30
                    FluentIcon { x: 5; y: 9; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: timeList.open() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Select a time")
                }
                Rectangle { y: 30; width: 157; height: 1; color: dlg.underline }
                Popup {
                    id: timeList
                    y: 31; padding: 0; width: 120; height: 180
                    background: FluentSurface { depth: 8; radius: 0; color: theme.surface }
                    onOpened: times.positionViewAtIndex(Math.min(47, Math.floor((dlg.customAt.getHours() * 60 + dlg.customAt.getMinutes()) / 30)), ListView.Beginning)
                    ListView {
                        id: times
                        anchors.fill: parent; clip: true; boundsBehavior: Flickable.StopAtBounds
                        model: 48
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Item {
                            id: trow
                            required property int index
                            readonly property bool picked: dlg.customAt.getHours() * 60 + dlg.customAt.getMinutes() === index * 30
                            width: 104.67; height: 36
                            Rectangle { anchors.fill: parent; color: trow.picked ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : trowHover.hovered ? theme.rowHover : "transparent" }
                            Text { x: 10.67; height: 36; verticalAlignment: Text.AlignVCenter; text: theme.fmtTime(new Date(2000, 0, 1, Math.floor(trow.index / 2), trow.index % 2 * 30), "h:mm AP"); font.family: theme.font; font.pixelSize: 14; color: trow.picked ? theme.text : theme.textSecondary }
                            HoverHandler { id: trowHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { const d = new Date(dlg.customAt); d.setHours(Math.floor(trow.index / 2), trow.index % 2 * 30, 0, 0); dlg.customAt = d; timeList.close() } }
                            Accessible.role: Accessible.ListItem; Accessible.selected: trow.picked
                        }
                    }
                }
            }
            Rectangle {
                x: 30; y: 60 + editRow.shift; width: 570; height: 61.33; radius: 2
                color: theme.surface; border.width: 0.67; border.color: message.activeFocus ? theme.brand : dlg.underline
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
                x: 30; y: 131.33 + editRow.shift; spacing: 8; height: 24
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
                x: 30; y: (dlg.meeting ? 167.33 : 131.33) + editRow.shift; spacing: 10
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
                    TapHandler { onTapped: { dlg.editing = -2; dlg.custom = false; message.text = "" } }
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
            TapHandler { onTapped: { dlg.editing = -1; dlg.offset = 15; dlg.custom = false; message.text = ""; dlg.toAll = false } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add email reminder")
        }
    }
}
