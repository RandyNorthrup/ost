import QtQuick
import QtQuick.Controls.Basic

// The Calendar app, laid out as Teams desktop's (measured from it at 1x):
// a 235 px side pane with the month and your calendars; a toolbar (Today,
// previous/next, the range, the view, New); and the day grid at 80 px per
// hour with half-hour lines, today's column marked and a now-line.
Item {
    id: root
    property var events: []
    /// The first day shown (local midnight).
    property date start: mondayOf(new Date())
    /// "workweek" (Mon-Fri), "week" (Sun-Sat) or "day".
    property string view: "workweek"
    property bool paneShown: true
    property bool showCalendar: true
    signal rangeChanged(string startUtc, string endUtc)
    signal createEvent(string subject, string startUtc, string endUtc, string attendees, bool teamsMeeting)

    readonly property int hourHeight: 80
    readonly property int gutter: 49
    readonly property int days: view === "day" ? 1 : view === "week" ? 7 : 5

    function mondayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - (m.getDay() + 6) % 7)
        return m
    }
    function sundayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - m.getDay())
        return m
    }
    function startFor(d) {
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        return view === "day" ? day : view === "week" ? sundayOf(day) : mondayOf(day)
    }
    function dayAt(i) { const d = new Date(start); d.setDate(d.getDate() + i); return d }
    function shift(n) { const d = new Date(start); d.setDate(d.getDate() + n * (view === "day" ? 1 : 7)); start = d }
    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function iso(d) { return d.toISOString().replace(/\.\d+Z$/, "Z") }
    function emitRange() {
        const end = new Date(start); end.setDate(end.getDate() + days)
        rangeChanged(iso(start), iso(end))
    }
    onStartChanged: emitRange()
    onViewChanged: start = startFor(start)
    Component.onCompleted: emitRange()
    readonly property string rangeLabel: {
        const a = start, b = dayAt(days - 1)
        if (days === 1) return Qt.formatDate(a, "dddd, MMMM d, yyyy")
        if (a.getMonth() === b.getMonth()) return Qt.formatDate(a, "MMMM d") + "–" + b.getDate() + ", " + b.getFullYear()
        return Qt.formatDate(a, "MMM d") + " – " + Qt.formatDate(b, "MMM d, yyyy")
    }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Side pane: title, month, calendars.
    Rectangle {
        id: pane
        visible: root.paneShown
        width: visible ? 235 : 0; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.edge }
        Text {
            x: 16; y: 19
            text: "Calendar"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        // The month: pick a day to show its week.
        Item {
            id: month
            x: 8; y: 78; width: 219; height: 230
            property date shown: new Date(root.start.getFullYear(), root.start.getMonth(), 1)
            readonly property date first: { const d = new Date(shown); d.setDate(1 - d.getDay()); return d }
            // Only the weeks this month needs, as Teams shows it.
            readonly property int weeks: {
                const last = new Date(shown.getFullYear(), shown.getMonth() + 1, 0)
                return Math.ceil((first.getDay() + (last - first) / 86400000 + 1) / 7)
            }
            Text {
                x: 24; y: 0
                text: Qt.formatDate(month.shown, "MMMM yyyy")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: theme.text
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; y: -4
                Repeater {
                    model: [{ icon: "chevron-left-20", d: -1, l: "Previous month" }, { icon: "chevron-right-20", d: 1, l: "Next month" }]
                    Rectangle {
                        required property var modelData
                        width: 28; height: 28; radius: theme.radius
                        color: mh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16; color: theme.textStrong; rotation: 90 }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const d = new Date(month.shown); d.setMonth(d.getMonth() + parent.modelData.d); month.shown = d } }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.l
                    }
                }
            }
            Row {
                y: 28
                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    Text { required property string modelData; width: 28; horizontalAlignment: Text.AlignHCenter; text: modelData; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
            }
            Grid {
                y: 48
                columns: 7
                Repeater {
                    model: month.weeks * 7
                    Item {
                        required property int index
                        readonly property date day: { const d = new Date(month.first); d.setDate(d.getDate() + index); return d }
                        readonly property bool inMonth: day.getMonth() === month.shown.getMonth()
                        readonly property bool today: root.sameDay(day, new Date())
                        // The shown week's whole row is highlighted.
                        readonly property bool inRange: root.view === "day" ? root.sameDay(day, root.start)
                            : day >= root.sundayOf(root.start) && day < root.dayAt(root.days + (root.view === "workweek" ? 1 : 0))
                        width: 28; height: 28
                        Rectangle { visible: parent.inRange; anchors.fill: parent; color: theme.brandTint }
                        Rectangle {
                            visible: parent.today
                            anchors.centerIn: parent; width: 22; height: 22; radius: 11
                            color: theme.brandFill
                        }
                        Text {
                            anchors.centerIn: parent
                            text: parent.day.getDate()
                            font.family: theme.font; font.pixelSize: theme.small
                            font.weight: parent.today ? Font.DemiBold : Font.Normal
                            color: parent.today ? "white" : parent.inMonth ? theme.text : theme.textTertiary
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.start = root.startFor(parent.day) }
                        Accessible.role: Accessible.Button
                        Accessible.name: Qt.formatDate(day, "dddd, MMMM d")
                    }
                }
            }
        }
        // My calendars.
        Column {
            x: 16; y: 340; width: parent.width - 32
            spacing: 6
            Text { text: "My calendars"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Item {
                width: parent.width; height: 28
                Rectangle {
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 2
                    color: root.showCalendar ? theme.brandFill : "transparent"
                    border.color: root.showCalendar ? "transparent" : theme.textStrong
                    FluentIcon { visible: root.showCalendar; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                }
                Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: "Calendar"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                TapHandler { onTapped: root.showCalendar = !root.showCalendar }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Calendar"
                Accessible.checked: root.showCalendar
            }
        }
    }

    component NavButton: Rectangle {
        id: nb
        property alias icon: nbIcon.name
        property string tip
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: nbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { id: nbIcon; anchors.centerIn: parent; size: 20; color: theme.textStrong }
        HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }

    // Toolbar
    Item {
        id: bar
        anchors { left: pane.right; right: parent.right }
        height: 61
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            NavButton { icon: "panel-left-20"; tip: root.paneShown ? "Hide navigation" : "Show navigation"; onClicked: root.paneShown = !root.paneShown }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: todayRow.implicitWidth + 20; height: 32; radius: theme.radius
                color: todayHover.hovered ? theme.rowHover : "transparent"
                Row {
                    id: todayRow
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "calendar"; size: 16; color: theme.textStrong }
                    Text { text: "Today"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.start = root.startFor(new Date()) }
                Accessible.role: Accessible.Button
                Accessible.name: "Go to today"
            }
            NavButton { icon: "chevron-left-20"; onClicked: root.shift(-1); tip: "Previous" }
            NavButton { icon: "chevron-right-20"; onClicked: root.shift(1); tip: "Next" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rangeLabel
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: theme.text
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: viewRow.implicitWidth + 20; height: 32; radius: theme.radius
                color: vh.hovered ? theme.rowHover : "transparent"
                Row {
                    id: viewRow
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "calendar"; size: 16; color: theme.textStrong }
                    Text { text: ({ day: "Day", workweek: "Work week", week: "Week" })[root.view]; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textStrong }
                }
                HoverHandler { id: vh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: viewMenu.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "View"
                MenuPopup {
                    id: viewMenu
                    width: 180; y: parent.height + 4
                    items: [{ label: "Day", checked: root.view === "day" }, { label: "Work week", checked: root.view === "workweek" }, { label: "Week", checked: root.view === "week" }]
                    onPicked: i => root.view = ["day", "workweek", "week"][i]
                }
            }
            // New: schedule an event (a Teams meeting by default).
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: newRow.implicitWidth + 28; height: 32; radius: theme.radius
                color: nh.hovered ? theme.brandHover : theme.brandFill
                Row {
                    id: newRow
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 16; color: "white" }
                    Text { text: "New"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                }
                HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: newEvent.openAt(null) }
                Accessible.role: Accessible.Button
                Accessible.name: "New meeting"
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // Day headers
    Item {
        id: heads
        anchors { top: bar.bottom; left: pane.right; right: parent.right }
        height: 48
        Repeater {
            model: root.days
            Item {
                required property int index
                readonly property date day: root.dayAt(index)
                readonly property bool today: root.sameDay(day, new Date())
                x: root.gutter + index * (heads.width - root.gutter) / root.days
                width: (heads.width - root.gutter) / root.days; height: heads.height
                Rectangle { visible: parent.today; width: parent.width; height: 3; color: theme.brand }
                Text {
                    x: 12; y: 6
                    text: parent.day.getDate()
                    font.family: theme.font; font.pixelSize: 20
                    color: parent.today ? theme.brand : theme.text
                }
                Text {
                    x: 12; y: 30
                    text: Qt.formatDate(parent.day, "ddd")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: parent.today ? theme.brand : theme.textSecondary
                }
                Rectangle { x: 0; width: 1; height: parent.height; color: theme.dividerSoft }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // The grid
    Flickable {
        id: grid
        anchors { top: heads.bottom; bottom: parent.bottom; left: pane.right; right: parent.right }
        contentHeight: 24 * root.hourHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Open near now, as Teams does.
        Component.onCompleted: {
            const n = new Date()
            contentY = Math.max(0, Math.min(contentHeight - height, (n.getHours() - 1) * root.hourHeight))
        }
        readonly property real colW: (width - root.gutter) / root.days
        // Hour labels and lines, half-hour lines fainter.
        Repeater {
            model: 24
            Item {
                required property int index
                y: index * root.hourHeight; width: grid.width; height: root.hourHeight
                Text {
                    visible: index > 0
                    x: root.gutter - 8 - implicitWidth; y: -implicitHeight / 2
                    text: (index % 12 === 0 ? 12 : index % 12) + " " + (index < 12 ? "AM" : "PM")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: theme.divider }
                Rectangle { x: root.gutter; y: root.hourHeight / 2; width: parent.width - root.gutter; height: 1; color: theme.dividerSoft }
            }
        }
        Repeater {
            model: root.days
            Rectangle {
                required property int index
                x: root.gutter + index * grid.colW; width: 1; height: grid.contentHeight
                color: theme.dividerSoft
            }
        }
        // Click an empty slot to schedule there (half-hour slots).
        MouseArea {
            x: root.gutter; width: grid.width - root.gutter; height: grid.contentHeight
            onClicked: m => {
                const col = Math.floor(m.x / grid.colW)
                const slot = Math.floor(m.y / (root.hourHeight / 2))
                const d = root.dayAt(col); d.setHours(0, slot * 30, 0, 0)
                newEvent.openAt(d)
            }
        }
        // Events
        Repeater {
            model: root.showCalendar ? root.events.filter(e => !e.is_all_day) : []
            Rectangle {
                id: ev
                required property var modelData
                readonly property date s: new Date(modelData.start_utc)
                readonly property date e: new Date(modelData.end_utc)
                readonly property int col: Math.floor((new Date(s.getFullYear(), s.getMonth(), s.getDate()) - root.start) / 86400000)
                visible: col >= 0 && col < root.days
                x: root.gutter + col * grid.colW + 2
                width: grid.colW - 6
                y: (s.getHours() + s.getMinutes() / 60) * root.hourHeight + 1
                height: Math.max(20, (e - s) / 3600000 * root.hourHeight - 2)
                radius: theme.radius
                color: theme.brandTint
                Rectangle { width: 4; height: parent.height; radius: 2; color: theme.brand }
                Column {
                    x: 10; y: 4; width: parent.width - 14
                    Text { width: parent.width; elide: Text.ElideRight; text: ev.modelData.subject || "(No title)"; font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold; color: theme.text }
                    Text { visible: ev.height > 36; width: parent.width; elide: Text.ElideRight; text: ev.modelData.organizer || ev.modelData.location || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: details.show(ev.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: (modelData.subject || "Event") + ", " + Qt.formatTime(s, "h:mm AP")
            }
        }
        // Now
        Item {
            id: now
            property date t: new Date()
            Timer { interval: 60000; running: true; repeat: true; onTriggered: now.t = new Date() }
            readonly property int col: Math.floor((new Date(t.getFullYear(), t.getMonth(), t.getDate()) - root.start) / 86400000)
            visible: col >= 0 && col < root.days
            y: (t.getHours() + t.getMinutes() / 60) * root.hourHeight
            Rectangle { x: root.gutter; width: grid.width - root.gutter; height: 1; color: theme.brand; opacity: 0.35 }
            Rectangle { x: root.gutter + now.col * grid.colW; width: grid.colW; height: 2; y: -0.5; color: theme.brand }
            Rectangle { x: root.gutter + now.col * grid.colW - 5; y: -5; width: 10; height: 10; radius: 5; color: theme.brand }
        }
    }

    // Event details, with Join for Teams meetings (opens the meeting link).
    Popup {
        id: details
        property var ev: ({})
        function show(e) { ev = e; open() }
        anchors.centerIn: parent
        width: 380; padding: 20
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 8
            Text { width: 340; wrapMode: Text.Wrap; text: details.ev.subject || "(No title)"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Text {
                text: details.ev.start_utc ? Qt.formatDateTime(new Date(details.ev.start_utc), "dddd, MMMM d  h:mm AP") + " – " + Qt.formatTime(new Date(details.ev.end_utc), "h:mm AP") : ""
                font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong
            }
            Text { visible: !!details.ev.location; text: details.ev.location || ""; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
            Text { visible: !!details.ev.organizer; text: "Organizer: " + (details.ev.organizer || ""); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            Rectangle {
                visible: !!details.ev.join_url
                width: 100; height: 32; radius: theme.radius
                color: jh.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Join"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                HoverHandler { id: jh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Qt.openUrlExternally(details.ev.join_url); details.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Join meeting"
            }
        }
    }

    // New meeting: title, attendees, start and length, Teams meeting.
    Popup {
        id: newEvent
        property date at: new Date()
        function openAt(d) {
            let s = d
            if (!s) { s = new Date(); s.setMinutes(s.getMinutes() < 30 ? 30 : 60, 0, 0) }
            at = s
            title.text = ""; who.text = ""; length.currentIndex = 1; teamsBox.on = true
            open(); title.forceActiveFocus()
        }
        anchors.centerIn: parent
        width: 420; padding: 20
        modal: true
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 12
            Text { text: "New meeting"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            component Field: Rectangle {
                property alias input: fi
                property string hint
                width: 380; height: 32; radius: theme.radius
                color: theme.input; border.color: fi.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: fi
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !fi.text; text: parent.parent.hint; color: theme.textTertiary; font: fi.font }
                }
            }
            Field { id: titleField; hint: "Add title"; property alias text: titleField.input.text }
            Field { id: whoField; hint: "Invite people (e-mail addresses, comma separated)"; property alias text: whoField.input.text }
            Text {
                text: Qt.formatDateTime(newEvent.at, "dddd, MMMM d, h:mm AP")
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Length"; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
                ComboBox { id: length; model: ["15 minutes", "30 minutes", "1 hour", "2 hours"]; width: 160 }
            }
            Row {
                spacing: 8
                Rectangle {
                    id: teamsBox
                    property bool on: true
                    width: 16; height: 16; radius: 2
                    color: on ? theme.brandFill : "transparent"; border.color: on ? "transparent" : theme.textStrong
                    FluentIcon { visible: teamsBox.on; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                    TapHandler { onTapped: teamsBox.on = !teamsBox.on }
                }
                Text { text: "Teams meeting"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 90; height: 32; radius: theme.radius
                    color: sh.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: "Save"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const mins = [15, 30, 60, 120][length.currentIndex]
                            const end = new Date(newEvent.at.getTime() + mins * 60000)
                            root.createEvent(title.text, root.iso(newEvent.at), root.iso(end), who.text, teamsBox.on)
                            newEvent.close()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Save"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius
                    color: ch.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: newEvent.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
        // Short names for the two text fields.
        property alias title: titleField.input
        property alias who: whoField.input
    }
    property alias title: newEvent.title
    property alias who: newEvent.who
}
