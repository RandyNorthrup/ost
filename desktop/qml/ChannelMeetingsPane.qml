import QtQuick
import QtQuick.Controls.Basic

// Teams' channel Meetings pane (View meetings in the channel header's
// meeting menu and its ··· menu; measured in Teams on the web as OST Test 2,
// OST Test Team ▸ General, 2026-11-27), on the right with a line on its
// left:
// - the header (61): "Meetings" (14/20 semibold) 20 in, 16 down; Close
//   (32) 16 from the right;
// - the filters (45 tall, pills 24 tall from 12 in, 4 down, 8 apart,
//   #E8EBFA, 12/16 text 12 in and a 12 px chevron): Date ▾ (Today,
//   Yesterday, This week, This month) and Organizer ▾ (the team's people);
// - the meetings, oldest first, grouped by month ("December 2026", 12/17
//   #616161, 12 in, 8 above): a row per meeting (a #F0F0F0 line under it):
//   the date tile (40 x 40, 17 in, 15 down, a #D1D1D1 border, radius 4,
//   the day 14/20 semibold and the month 10/14 #616161), the subject
//   (14/20) at 73, then "Tuesday 2:00 PM - 2:30 PM", the place and
//   "{organizer} invited you" (12/16 #616161, 22 and 20 apart); Chat with
//   participants (24, white, bordered) at its top right. "Now" is a brand
//   line (2) with a ring (12) before the first meeting still to come;
// - none: the calendar picture, "Could not find meetings" and "Could not
//   find meetings in this channel";
// - "Send feedback" (12/20 #616161) with thumbs up and down at the bottom
//   right.
// The meetings are the team's group calendar narrowed to the channel
// (api::channel_meetings).
Rectangle {
    id: pane
    property string teamId: ""
    property string channelId: ""
    /// The team's people, for the Organizer filter ({mri, name}).
    property var people: []
    signal closed()
    signal openChat(var meeting)
    signal openMeeting(var meeting)
    color: theme.surface

    property string dateKey: ""
    property var organizer: null
    property bool loading: false
    property bool failed: false
    property var meetings: []
    property int pastCount: 0
    property int generation: 0

    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function range() {
        const t = dayStart(new Date())
        const add = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
        switch (dateKey) {
        case "today": return [t, add(t, 1)]
        case "yesterday": return [add(t, -1), t]
        case "week": { const s = add(t, -t.getDay()); return [s, add(s, 7)] }
        case "month": return [new Date(t.getFullYear(), t.getMonth(), 1), new Date(t.getFullYear(), t.getMonth() + 1, 1)]
        }
        return null
    }
    function load() {
        if (!teamId || !channelId) return
        loading = true; failed = false; generation++
        const r = range()
        const arg = { organizer: organizer ? organizer.mri : "", gen: generation }
        if (r) { arg.from = r[0].getTime(); arg.to = r[1].getTime() }
        backend.channelAction("channel-meetings", teamId, channelId, JSON.stringify(arg))
        // The team's people once per channel (organizer names and the
        // Organizer filter), not again on every filter change.
        if (!people.length) backend.channelAction("channel-audience", teamId, channelId, "")
    }
    onVisibleChanged: if (visible) load()
    onChannelIdChanged: { dateKey = ""; organizer = null; meetings = []; people = []; if (visible) load() }
    onDateKeyChanged: if (visible) load()
    onOrganizerChanged: if (visible) load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            let r = {}
            try { r = JSON.parse(backend.channelActionResult || "{}") } catch (e) { return }
            if (r.channel !== pane.channelId) return
            if (r.op === "channel-audience" && r.ok && r.data) pane.people = r.data.people || []
            if (r.op !== "channel-meetings") return
            // Only the answer to the latest request (filters changed while
            // an earlier one ran).
            if (r.ok && r.data && r.data.gen !== pane.generation) return
            pane.loading = false
            pane.failed = !r.ok
            pane.meetings = r.ok && r.data ? (r.data.meetings || []) : []
            pane.pastCount = r.ok && r.data ? (r.data.past || 0) : 0
        }
    }

    /// The rows: month headings, the meetings, and "now" before the first
    /// one still to come.
    readonly property var rows: {
        const out = []
        let last = ""
        pane.meetings.forEach((m, i) => {
            const d = new Date(m.start)
            const g = Qt.formatDate(d, "MMMM yyyy")
            if (g !== last) { out.push({ heading: g }); last = g }
            if (i === pane.pastCount) out.push({ now: true })
            out.push(m)
        })
        if (pane.meetings.length && pane.pastCount >= pane.meetings.length) out.push({ now: true })
        return out
    }
    // "{organizer} invited you": the person who set the meeting up (a
    // group calendar names the team as its organizer), none for your own.
    function invitedBy(m) {
        const mri = String(m.organizer_mri || "").toLowerCase()
        if (mri && mri === String(backend.userMri || "").toLowerCase()) return ""
        const p = mri ? pane.people.find(x => String(x.mri || "").toLowerCase() === mri) : null
        const name = p ? p.name : (!mri && !m.is_organizer ? m.organizer_name : "")
        return name ? qsTr("%1 invited you").arg(name) : ""
    }
    /// Whether the meeting is in your own calendar (its details can open
    /// there).
    function inMyCalendar(m) {
        // By iCalUId alone: Graph gives each occurrence its own, while a
        // series shares its join link.
        if (!m || !m.ical_uid) return false
        let mine = []
        try { mine = JSON.parse(backend.calendarJson || "[]") } catch (e) {}
        return mine.some(e => e.ical_uid === m.ical_uid)
    }
    function timeText(m) {
        const s = new Date(m.start), e = new Date(m.end)
        if (isNaN(s) || isNaN(e)) return ""
        return qsTr("%1 %2 - %3").arg(Qt.formatDate(s, "dddd")).arg(theme.time(s)).arg(theme.time(e))
    }

    Rectangle { z: 3; width: 0.67; height: parent.height; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }

    Text {
        x: 20; y: 16; height: 28; verticalAlignment: Text.AlignVCenter
        text: qsTr("Meetings")
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
    }
    Rectangle {
        id: closeButton
        x: pane.width - 48; y: 14; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeButton, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pane.closed() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close Meetings")
    }
    Rectangle { y: 61; width: parent.width; height: 1; color: theme.divider }

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool active: false
        signal clicked()
        height: 24; radius: 12
        width: pillText.implicitWidth + 12 + 4 + 12 + 12
        color: pill.active ? theme.brandFill : pillHover.hovered ? theme.pick("#DCE0FA", "#3D3E66", "#1AEBFF") : theme.pick("#E8EBFA", "#2F2F4A", "#000000")
        Text { id: pillText; x: 12; anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(pill, pill.active ? "white" : theme.textStrong) }
        FluentIcon { x: pillText.x + pillText.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(pill, pill.active ? "white" : theme.textStrong) }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        Accessible.role: Accessible.Button
    }
    readonly property var dateNames: ({ today: qsTr("Today"), yesterday: qsTr("Yesterday"), week: qsTr("This week"), month: qsTr("This month") })
    Row {
        id: filters
        x: 12; y: 61 + 4; spacing: 8
        Pill {
            id: datePill
            label: pane.dateKey ? pane.dateNames[pane.dateKey] : qsTr("Date")
            active: !!pane.dateKey
            onClicked: dateMenu.open()
            Accessible.name: qsTr("Date filter")
            MenuPopup {
                id: dateMenu
                y: parent.height + 4
                minRowWidth: 244
                items: ["today", "yesterday", "week", "month"].map(k => ({ key: k, label: pane.dateNames[k], checked: pane.dateKey === k }))
                onPicked: i => pane.dateKey = pane.dateKey === items[i].key ? "" : items[i].key
            }
        }
        Pill {
            id: organizerPill
            label: pane.organizer ? pane.organizer.name : qsTr("Organizer")
            active: !!pane.organizer
            onClicked: organizerMenu.open()
            Accessible.name: qsTr("Organizer filter")
            MenuPopup {
                id: organizerMenu
                y: parent.height + 4
                minRowWidth: 244
                items: pane.people.map(p => ({ key: p.mri, label: p.name, checked: !!pane.organizer && pane.organizer.mri === p.mri }))
                onPicked: i => { const p = pane.people[i]; pane.organizer = pane.organizer && pane.organizer.mri === p.mri ? null : { mri: p.mri, name: p.name } }
            }
        }
    }
    Rectangle { y: 61 + 45; width: parent.width; height: 1; color: theme.divider }

    ListView {
        id: list
        anchors { top: parent.top; topMargin: 61 + 45 + 1; left: parent.left; right: parent.right; bottom: footer.top }
        clip: true
        visible: pane.meetings.length > 0
        model: pane.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool heading: !!modelData.heading
            readonly property bool now: !!modelData.now
            width: list.width
            height: heading ? 8 + 17 + 4 : now ? 12 : 109
            Text {
                visible: row.heading
                x: 12; y: 8; height: 17
                text: row.modelData.heading || ""
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
            }
            Item {
                visible: row.now
                anchors.fill: parent
                Rectangle { y: 0; width: 12; height: 12; radius: 6; color: "transparent"; border.width: 2; border.color: theme.brand }
                Rectangle { x: 12; y: 5; width: parent.width - 12; height: 2; color: theme.brand }
                Accessible.role: Accessible.Separator
                Accessible.name: qsTr("Now")
            }
            Item {
                id: card
                visible: !row.heading && !row.now
                anchors.fill: parent
                readonly property var m: row.modelData
                Rectangle { anchors.fill: parent; color: cardHover.hovered ? theme.rowHover : "transparent" }
                HoverHandler { id: cardHover; cursorShape: pane.inMyCalendar(card.m) ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: pane.openMeeting(card.m) }
                Rectangle {
                    x: 17; y: 15; width: 40; height: 40; radius: 4
                    color: "transparent"; border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 1; height: 22; verticalAlignment: Text.AlignVCenter; text: card.m.start ? new Date(card.m.start).getDate() : ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 23; text: card.m.start ? Qt.formatDate(new Date(card.m.start), "MMM").toUpperCase() : ""; font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                }
                Text {
                    x: 73; y: 13; width: parent.width - 73 - 90; elide: Text.ElideRight
                    text: card.m.cancelled ? qsTr("Canceled: %1").arg(card.m.subject || qsTr("Untitled event")) : (card.m.subject || qsTr("Untitled event"))
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong
                    font.strikeout: !!card.m.cancelled
                }
                Column {
                    x: 73; y: 37; spacing: 6
                    Text { text: pane.timeText(card.m); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    Text { visible: !!card.m.location; width: card.width - 73 - 20; elide: Text.ElideRight; text: card.m.location || ""; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    Text { visible: !!text; text: pane.invitedBy(card.m); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                }
                Rectangle {
                    id: chatButton
                    visible: !!card.m.join_url
                    x: card.width - 81; y: 13; width: 24; height: 24; radius: 4
                    color: chatHover.hovered ? theme.hover : theme.surface
                    border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    FluentIcon { anchors.centerIn: parent; name: "chat-20"; size: 16; color: theme.onFill(chatButton, theme.textStrong) }
                    HoverHandler { id: chatHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pane.openChat(card.m) }
                    ToolTip.visible: chatHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Chat with participants")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Chat with participants")
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.pick("#F0F0F0", "#2E2E2E", "#FFFFFF") }
                Accessible.role: Accessible.ListItem
                Accessible.name: (card.m.subject || "") + ", " + pane.timeText(card.m)
            }
        }
    }

    Column {
        visible: !pane.loading && pane.meetings.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: 118
        width: Math.min(parent.width - 40, 240)
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 220; sourceSize: Qt.size(440, 440)
            source: "../assets/illustrations/calendar-clock-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard.svg"
        }
        Item { width: 1; height: 10 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: pane.failed ? qsTr("Something went wrong") : qsTr("Could not find meetings")
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.textStrong
        }
        Item { width: 1; height: 10 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 208; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: qsTr("Could not find meetings in this channel")
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
    }
    BusyIndicator { visible: pane.loading && pane.meetings.length === 0; running: visible; anchors.centerIn: parent; width: 32; height: 32 }

    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 36
        Row {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Send feedback"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "thumb-like-16"; size: 16; color: theme.textSecondary; Accessible.role: Accessible.Button; Accessible.name: qsTr("This was helpful") }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "thumb-dislike-16"; size: 16; color: theme.textSecondary; Accessible.role: Accessible.Button; Accessible.name: qsTr("Didn't help") }
        }
    }
}
