import QtQuick
import QtQuick.Controls.Basic

// The Calendar app in Teams' work-week layout: a toolbar (Today, previous
// and next week, the month), the day header row, and an hourly grid with
// events as tinted blocks with a brand bar, plus the red now-line.
Item {
    id: root
    property var events: []
    /// Monday 00:00 (local) of the shown week.
    property date weekStart: mondayOf(new Date())
    signal rangeChanged(string startUtc, string endUtc)

    readonly property int hourHeight: 48
    readonly property int gutter: 64
    readonly property int days: 5

    function mondayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const dow = (m.getDay() + 6) % 7   // Monday = 0
        m.setDate(m.getDate() - dow)
        return m
    }
    function dayAt(i) { const d = new Date(weekStart); d.setDate(d.getDate() + i); return d }
    function shift(weeks) { const d = new Date(weekStart); d.setDate(d.getDate() + 7 * weeks); weekStart = d }
    function emitRange() {
        const end = new Date(weekStart); end.setDate(end.getDate() + 7)
        rangeChanged(weekStart.toISOString().replace(/\.\d+Z$/, "Z"), end.toISOString().replace(/\.\d+Z$/, "Z"))
    }
    onWeekStartChanged: emitRange()
    Component.onCompleted: emitRange()

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Toolbar
    Item {
        id: bar
        width: parent.width; height: 56
        Text {
            x: 24; anchors.verticalCenter: parent.verticalCenter
            text: "Calendar"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: 150; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                width: todayText.implicitWidth + 24; height: 32; radius: theme.radius
                color: todayHover.hovered ? theme.pane : theme.surface
                border.color: theme.stroke
                Text { id: todayText; anchors.centerIn: parent; text: "Today"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.weekStart = root.mondayOf(new Date()) }
            }
            NavButton { icon: "chevron-left-20"; onClicked: root.shift(-1); tip: "Previous week" }
            NavButton { icon: "chevron-right-20"; onClicked: root.shift(1); tip: "Next week" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.weekStart, "MMMM yyyy")
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                color: theme.text
            }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            width: newText.implicitWidth + 40; height: 32; radius: theme.radius
            color: theme.brand
            opacity: 0.6
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { name: "add-20"; size: 16; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                Text { id: newText; text: "New meeting"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "New meeting (not available yet)"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // Day headers
    Row {
        id: dayHeads
        x: root.gutter; y: bar.height
        Repeater {
            model: root.days
            Item {
                required property int index
                readonly property date d: root.dayAt(index)
                readonly property bool today: d.toDateString() === new Date().toDateString()
                width: (root.width - root.gutter) / root.days; height: 64
                Text {
                    id: num
                    x: 8; y: 10
                    text: Qt.formatDate(parent.d, "dd")
                    font.family: theme.font; font.pixelSize: 24
                    font.weight: parent.today ? Font.Bold : Font.Normal
                    color: parent.today ? theme.brand : theme.text
                }
                Text {
                    x: 8; y: num.y + num.height
                    text: Qt.formatDate(parent.d, "dddd")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: parent.today ? theme.brand : theme.textSecondary
                }
                Rectangle { visible: parent.today; anchors.top: parent.top; width: parent.width; height: 3; color: theme.brand }
                Rectangle { anchors.left: parent.left; height: parent.height; width: 1; color: theme.dividerSoft }
            }
        }
    }
    Rectangle { x: 0; y: dayHeads.y + 64; width: parent.width; height: 1; color: theme.divider }

    // Hour grid
    Flickable {
        id: grid
        anchors { left: parent.left; right: parent.right; top: dayHeads.bottom; bottom: parent.bottom; topMargin: 1 }
        contentHeight: 24 * root.hourHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Component.onCompleted: contentY = 8 * root.hourHeight   // open at 8 AM

        Repeater {
            model: 24
            Item {
                required property int index
                y: index * root.hourHeight; width: grid.width; height: root.hourHeight
                Text {
                    x: 8; y: -7
                    visible: parent.index > 0
                    text: Qt.formatTime(new Date(2000, 0, 1, parent.index), "h AP")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: theme.dividerSoft }
            }
        }
        Repeater {
            model: root.days
            Rectangle {
                required property int index
                x: root.gutter + index * (grid.width - root.gutter) / root.days
                width: 1; height: grid.contentHeight; color: theme.dividerSoft
            }
        }

        // Events
        Repeater {
            model: root.events.filter(e => !e.is_all_day)
            Rectangle {
                id: ev
                required property var modelData
                readonly property date s: new Date(modelData.start_utc)
                readonly property date e: new Date(modelData.end_utc)
                readonly property int day: Math.floor((new Date(s.getFullYear(), s.getMonth(), s.getDate()) - root.weekStart) / 86400000)
                readonly property real colW: (grid.width - root.gutter) / root.days
                visible: day >= 0 && day < root.days
                x: root.gutter + day * colW + 2
                y: (s.getHours() + s.getMinutes() / 60) * root.hourHeight + 1
                width: colW - 6
                height: Math.max(22, (e - s) / 3600000 * root.hourHeight - 2)
                radius: theme.radius
                color: theme.brandTint
                clip: true
                Rectangle { width: 4; height: parent.height; color: theme.brand; radius: 2 }
                Column {
                    x: 10; y: 4; width: parent.width - 14
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: ev.modelData.subject || "(No title)"
                        font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        visible: ev.height > 36
                        text: ev.modelData.organizer
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.textSecondary
                    }
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: (ev.modelData.subject || "(No title)") + ", " + Qt.formatTime(ev.s, "h:mm AP") + " to " + Qt.formatTime(ev.e, "h:mm AP")
            }
        }

        // Now line
        Rectangle {
            readonly property date now: new Date()
            readonly property int day: Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - root.weekStart) / 86400000)
            visible: day >= 0 && day < root.days
            x: root.gutter + day * (grid.width - root.gutter) / root.days
            y: (now.getHours() + now.getMinutes() / 60) * root.hourHeight
            width: (grid.width - root.gutter) / root.days; height: 2
            color: theme.danger
            Rectangle { x: -4; y: -3; width: 8; height: 8; radius: 4; color: theme.danger }
        }
    }

    component NavButton: Rectangle {
        id: nb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: nbHover.hovered ? theme.pane : "transparent"
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        FluentIcon { anchors.centerIn: parent; name: nb.icon; size: 16 }
        HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: nb.tip
    }
}
