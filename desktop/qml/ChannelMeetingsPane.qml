import QtQuick
import QtQuick.Controls.Basic

// Teams' channel Meetings pane (View meetings in the channel header's
// meeting menu and its ··· menu; measured in Teams on the web as OST Test 2,
// OST Test Team ▸ General, 2026-11-27), on the right with a line on its
// left:
// - the header (61): "Meetings" (14/20 semibold) 20 in, 16 down; Close
//   (32) 16 from the right;
// - the filters (45 tall, pills 24 tall from 12 in, 4 down, 8 apart; see
//   Pill): Date ▾ (Today, Yesterday, This week, This month, or a From / To
//   range) and Organizer ▾ (a people search over the team);
// - the meetings, oldest first, grouped by month ("December 2026", 12/17
//   #616161, 12 in, 8 above): a row per meeting (a #F0F0F0 line under it):
//   the date tile (40 x 40, 17 in, 15 down, a #D1D1D1 border, radius 4,
//   the day 14/20 semibold and the month 10/14 #616161), the subject
//   (14/20) at 73, then "Tuesday 2:00 PM - 2:30 PM", the place and
//   "{organizer} invited you" (12/16 #616161, 22 and 20 apart); at its
//   top right Edit (your own meetings), Chat with participants (24, white,
//   bordered) and More options (Copy link). A meeting opens its details. "Now" is a brand
//   line (2) with a ring (12) before the first meeting still to come;
// - none: the calendar picture, "Could not find meetings" and "Could not
//   find meetings in this channel";
// - "Send feedback" (12/20 #616161) with thumbs up and down at the bottom
//   right.
// The meetings are the team's group calendar narrowed to the channel
// (api::channel_meetings). Its width is Teams' end slot's (Theme's
// endSlotWidth).
Rectangle {
    id: pane
    property string teamId: ""
    property string channelId: ""
    /// The team's members ({mri, name, mail}, the roster's order): the
    /// Organizer suggestions and who invited you.
    property var roster: []
    signal closed()
    signal openChat(var meeting)
    signal openMeeting(var meeting)
    /// Edit (your own meeting): its form.
    signal editMeeting(var meeting)
    color: theme.surface

    property string dateKey: ""          // today | yesterday | week | month | custom
    property date customFrom: new Date()
    property date customTo: new Date()
    /// Bumped on each Apply (a new custom range with the same key).
    property int customGen: 0
    property var organizer: null
    property bool loading: false
    property bool failed: false
    property var meetings: []
    property int pastCount: 0
    property int generation: 0
    /// This pane's own requests (the main window's and a pop-out's panes
    /// share backend.channelActionResult).
    readonly property string instanceKey: Math.random().toString(36).slice(2)

    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    // Teams' date filter ranges (getDateRange): local days, the week from
    // Sunday, a custom range to the end of its To day.
    function range() {
        const t = dayStart(new Date())
        const add = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
        switch (dateKey) {
        case "today": return [t, add(t, 1)]
        case "yesterday": return [add(t, -1), t]
        case "week": { const s = add(t, -t.getDay()); return [s, add(s, 7)] }
        case "month": return [new Date(t.getFullYear(), t.getMonth(), 1), new Date(t.getFullYear(), t.getMonth() + 1, 1)]
        case "custom": return [dayStart(customFrom), add(dayStart(customTo), 1)]
        }
        return null
    }
    function load() {
        if (!teamId || !channelId) return
        loading = true; failed = false; generation++
        const r = range()
        const arg = { organizer: organizer ? organizer.mri : "", gen: generation, pane: instanceKey }
        if (r) { arg.from = r[0].getTime(); arg.to = r[1].getTime() }
        backend.channelAction("channel-meetings", teamId, channelId, JSON.stringify(arg))
        // The team's members once per channel, not on every filter change.
        if (!roster.length) backend.channelAction("channel-organizers", teamId, channelId, "")
    }
    onVisibleChanged: if (visible) load()
    onChannelIdChanged: { dateKey = ""; organizer = null; meetings = []; roster = []; if (visible) load() }
    onDateKeyChanged: if (visible) load()
    onCustomGenChanged: if (visible) load()
    onOrganizerChanged: if (visible) load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            let r = {}
            try { r = JSON.parse(backend.channelActionResult || "{}") } catch (e) { return }
            if (r.channel !== pane.channelId) return
            if (r.op === "channel-organizers" && r.ok && r.data) pane.roster = r.data.people || []
            if (r.op !== "channel-meetings") return
            // Only the answer to the latest request (filters changed while
            // an earlier one ran).
            if (r.ok && r.data && (r.data.gen !== pane.generation || r.data.pane !== pane.instanceKey)) return
            if (!r.ok && !pane.loading) return
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
    /// You set the meeting up (its SkypeTeamsProperties uid; a group
    /// calendar says isOrganizer for every member).
    function isMine(m) {
        const mri = String(m.organizer_mri || "").toLowerCase()
        return !!mri && mri === String(backend.userMri || "").toLowerCase()
    }
    // "{organizer} invited you": the person who set the meeting up (a
    // group calendar names the team as its organizer), none for your own.
    /// Who set the meeting up, from the team's members ({name, mail}).
    function organizerOf(m) {
        const mri = String(m.organizer_mri || "").toLowerCase()
        return mri ? pane.roster.find(x => String(x.mri || "").toLowerCase() === mri) || null : null
    }
    /// The meeting with its person organizer, for its page (a group
    /// calendar names the team as the organizer; Teams' page tracks the
    /// person).
    function withOrganizer(m) {
        const p = organizerOf(m)
        return p ? Object.assign({}, m, { organizer_name: p.name, organizer_address: p.mail || m.organizer_address, group_address: m.organizer_address }) : m
    }
    function invitedBy(m) {
        const mri = String(m.organizer_mri || "").toLowerCase()
        if (mri && mri === String(backend.userMri || "").toLowerCase()) return ""
        const p = mri ? pane.roster.find(x => String(x.mri || "").toLowerCase() === mri) : null
        const name = p ? p.name : (!mri && !m.is_organizer ? m.organizer_name : "")
        return name ? qsTr("%1 invited you").arg(name) : ""
    }
    /// Copy link: the meeting's join link as plain text, as Teams desktop
    /// copies it (clicked on testpc2 as OST Test 2, 2026-11-27: the
    /// clipboard held only the meetup-join URL, no HTML).
    function copyLink(m) {
        if (!m || !m.join_url) return
        backend.copyHtml("", m.join_url)
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

    // Teams' filter pills (search-filter-pill; Teams on the web, OST Test 2,
    // 2026-11-27): 24 tall, round; off #E8EBFA with the name (12/16) 12 in,
    // a 12 px chevron 3 after it and 11 to the right; on brand with the
    // choice (12/16 semibold, white) 12 in and 6 after it, or for a person
    // their 20 px picture 2 in (32 wide), then Clear (18 wide, a 12 px ×).
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property string choice: ""
        /// A person picked: their picture instead of a label.
        property var person: null
        readonly property bool active: !!choice || !!person
        property string name: ""
        signal clicked()
        signal cleared()
        readonly property real faceWidth: person ? 32 : active ? 12 + choiceText.implicitWidth + 6 : 12 + offText.implicitWidth + 3 + 12 + 11
        height: 24; radius: 12
        width: faceWidth + (active ? 18 : 0)
        color: active ? (pillHover.hovered || clearHover.hovered ? theme.brandHover : theme.brand)
                      : pillHover.hovered ? theme.pick("#DCE0FA", "#3D3E66", "#1AEBFF") : theme.pick("#E8EBFA", "#2F2F4A", "#000000")
        readonly property color ink: active ? "#FFFFFF" : theme.textStrong
        Item {
            width: pill.faceWidth; height: parent.height
            Text { id: offText; visible: !pill.active; x: 12; anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(pill, pill.ink) }
            FluentIcon { visible: !pill.active; x: 12 + offText.implicitWidth + 3; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(pill, pill.ink) }
            Text { id: choiceText; visible: !!pill.choice && !pill.person; x: 12; anchors.verticalCenter: parent.verticalCenter; text: pill.choice; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(pill, pill.ink) }
            Avatar { visible: !!pill.person; x: 2; anchors.verticalCenter: parent.verticalCenter; size: 20; name: pill.person ? pill.person.name : ""; photoId: pill.person ? pill.person.mri : "" }
            HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pill.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: pill.name
        }
        Item {
            visible: pill.active
            x: pill.faceWidth; width: 18; height: parent.height
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: theme.onFill(pill, pill.ink) }
            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pill.cleared() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Clear")
        }
    }
    readonly property var dateNames: ({ today: qsTr("Today"), yesterday: qsTr("Yesterday"), week: qsTr("This week"), month: qsTr("This month") })
    /// The custom range as Teams' pill writes it ("Nov 1, 2026 - Nov 27, 2026").
    function rangeLabel() {
        return qsTr("%1 - %2").arg(Qt.formatDate(customFrom, "MMM d, yyyy")).arg(Qt.formatDate(customTo, "MMM d, yyyy"))
    }
    readonly property string dateChoice: dateKey === "custom" ? rangeLabel() : dateKey ? dateNames[dateKey] : ""
    Row {
        id: filters
        x: 12; y: 61 + 4; spacing: 8
        Pill {
            id: datePill
            label: qsTr("Date"); choice: pane.dateChoice
            name: pane.dateKey ? qsTr("Date %1.").arg(pane.dateChoice) : qsTr("Date filter")
            onClicked: { datePop.x = filters.x + datePill.x; datePop.open() }
            onCleared: pane.dateKey = ""
        }
        Pill {
            id: organizerPill
            label: qsTr("Organizer"); person: pane.organizer
            name: pane.organizer ? qsTr("%1 filter").arg(pane.organizer.name) : qsTr("Organizer filter")
            onClicked: { organizerPop.x = Math.min(filters.x + organizerPill.x, pane.width - organizerPop.width - 4); organizerPop.open() }
            onCleared: pane.organizer = null
        }
    }

    // Date ▾ (Teams' date filter dialog, 254 x 337 under the pill, its
    // left edge on the pill's): Today, Yesterday, This week, This month
    // (32 tall, 14 px 16 in; the one chosen #F5F5F5 with a checkmark), a
    // line, From / To (12 px) with their date fields (222 x 32, #F5F5F5,
    // nothing after today), then Clear and Apply. A custom range runs from
    // the start of From to the end of To (Teams' getDateRange).
    Popup {
        id: datePop
        y: filters.y + 24
        width: 254; height: 337; padding: 0
        property bool fromSet: false
        property date fromDate: new Date()
        property date toDate: new Date()
        readonly property bool changed: fromSet && (pane.dateKey !== "custom" || pane.dayStart(fromDate).getTime() !== pane.dayStart(pane.customFrom).getTime() || pane.dayStart(toDate).getTime() !== pane.dayStart(pane.customTo).getTime())
        onAboutToShow: {
            fromSet = pane.dateKey === "custom"
            fromDate = pane.dateKey === "custom" ? pane.customFrom : new Date()
            toDate = pane.dateKey === "custom" ? pane.customTo : new Date()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 1; y: 7; width: parent.width - 2
            Repeater {
                model: ["today", "yesterday", "week", "month"]
                Rectangle {
                    id: preset
                    required property string modelData
                    readonly property bool chosen: pane.dateKey === modelData
                    width: parent.width; height: 32
                    color: presetHover.hovered || chosen ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: pane.dateNames[preset.modelData]; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(preset, theme.textStrong) }
                    FluentIcon { visible: preset.chosen; x: parent.width - 22 - 20; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-20"; size: 20; color: theme.onFill(preset, theme.textStrong) }
                    HoverHandler { id: presetHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { pane.dateKey = preset.chosen ? "" : preset.modelData; datePop.close() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: pane.dateNames[modelData]
                    Accessible.selected: chosen
                }
            }
        }
        Rectangle { x: 1; y: 145; width: parent.width - 2; height: 1; color: theme.divider }
        Text { x: 16; y: 163; text: qsTr("From"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        DatePickerField {
            x: 16; y: 182; width: 222
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            empty: !datePop.fromSet; placeholder: qsTr("Select a date")
            date: datePop.fromDate; maxDate: datePop.toDate
            onPicked: d => { datePop.fromDate = d; datePop.fromSet = true }
        }
        Text { x: 16; y: 226; text: qsTr("To"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        DatePickerField {
            x: 16; y: 245; width: 222
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            date: datePop.toDate; minDate: datePop.fromSet ? datePop.fromDate : new Date(1900, 0, 1); maxDate: new Date()
            onPicked: d => datePop.toDate = d
        }
        Rectangle {
            id: clearButton
            x: 76; y: 289; width: 58; height: 32; radius: 4
            readonly property bool usable: datePop.fromSet || !!pane.dateKey
            color: usable && clearHover2.hovered ? theme.hover : "transparent"
            Text { anchors.centerIn: parent; text: qsTr("Clear"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(clearButton, parent.usable ? theme.brand : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
            HoverHandler { id: clearHover2; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.usable; onTapped: { datePop.fromSet = false; datePop.toDate = new Date(); pane.dateKey = ""; datePop.close() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Clear the Selected Date Range")
        }
        Rectangle {
            id: applyButton
            x: 142; y: 289; width: 96; height: 32; radius: 4
            readonly property bool usable: datePop.changed
            color: usable ? (applyHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E", "#000000")
            Text { anchors.centerIn: parent; text: qsTr("Apply"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(applyButton, parent.usable ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
            HoverHandler { id: applyHover; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler {
                enabled: parent.usable
                onTapped: { pane.customFrom = datePop.fromDate; pane.customTo = datePop.toDate; pane.dateKey = "custom"; pane.customGen++; datePop.close() }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Apply the Selected Date Range")
        }
    }

    // Organizer ▾ (Teams' people picker, 254 wide under the pill):
    // "Filter by person" (230 x 33, #F5F5F5) and, before anything is
    // typed, the team's members but you (the thread's roster in its own
    // order), then the people the team's profile search finds (15, you
    // with "(You)"); rows 50 tall (their 32 px picture 12 in, the name 14
    // and address 12 at 60, what was typed in bold).
    Popup {
        id: organizerPop
        y: filters.y + 24
        width: 254; padding: 0
        // At most what the pane has below it; the rest scroll.
        readonly property real listHeight: Math.min(people.length * 50, Math.max(150, pane.height - y - 66.7 - 24))
        height: 66.7 + (people.length ? listHeight + 8 : 0)
        onOpened: { who.text = ""; who.forceActiveFocus() }
        readonly property var people: {
            const q = who.text.trim().toLowerCase()
            const me = String(backend.userMri || "").toLowerCase()
            if (!q) return pane.roster.filter(p => String(p.mri || "").toLowerCase() !== me)
            try {
                const r = JSON.parse(backend.findPeopleJson || "{}")
                return r.keyword && r.keyword.toLowerCase() === q ? r.people || [] : []
            } catch (e) { return [] }
        }
        function pick(p) { pane.organizer = { mri: p.mri, name: p.name }; close() }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Rectangle {
            x: 12.7; y: 16.7; width: 230; height: 33.3; radius: 4
            color: theme.pick("#F5F5F5", "#141414", "#000000")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: who.activeFocus ? 2 : 0.67; color: who.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: who
                x: 14.6; width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                clip: true
                onTextChanged: { personList.currentIndex = 0; if (text.trim()) whoTimer.restart() }
                Keys.onReturnPressed: if (organizerPop.people.length) organizerPop.pick(organizerPop.people[Math.max(0, personList.currentIndex)])
                Keys.onDownPressed: personList.currentIndex = Math.min(personList.currentIndex + 1, organizerPop.people.length - 1)
                Keys.onUpPressed: personList.currentIndex = Math.max(personList.currentIndex - 1, 0)
                Keys.onEscapePressed: organizerPop.close()
                Text { visible: !who.text; text: qsTr("Filter by person"); font: who.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Filter by person")
            }
            Timer { id: whoTimer; interval: 250; onTriggered: backend.findPeople(pane.channelId, who.text) }
        }
        ListView {
            id: personList
            x: 16.7; y: 54; width: 222; height: organizerPop.listHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: organizerPop.people
            currentIndex: 0
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                    id: personRow
                    required property var modelData
                    required property int index
                    readonly property bool me: String(modelData.mri || "").toLowerCase() === String(backend.userMri || "").toLowerCase()
                    width: 222; height: 50; radius: 4
                    color: personHover.hovered || (personList.currentIndex === index && who.text.trim() !== "") ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: personRow.modelData.name || ""; photoId: personRow.modelData.mri || "" }
                    Text {
                        x: 60; y: 7; width: parent.width - 68
                        textFormat: Text.StyledText; elide: Text.ElideRight
                        text: personRow.me ? ("%1 " + qsTr("(You)", "autosuggest:k9m83y7y2")).arg(pane.boldPrefix(personRow.modelData.name || "", who.text)) : pane.boldPrefix(personRow.modelData.name || "", who.text)
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(personRow, theme.textStrong)
                    }
                    Text {
                        x: 60; y: 27.5; width: parent.width - 68
                        textFormat: Text.StyledText; elide: Text.ElideRight
                        text: pane.boldPrefix(personRow.modelData.mail || "", who.text)
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(personRow, theme.textSecondary)
                    }
                    HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: organizerPop.pick(personRow.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: (modelData.name || "") + ", " + (modelData.mail || "")
                }
        }
    }
    function escaped(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    // The typed start of each word in bold.
    function boldPrefix(t, q) {
        q = String(q || "").trim()
        const e = escaped(t)
        if (!q) return e
        const re = new RegExp("(^|[\\s.@-])(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi")
        return e.replace(re, "$1<b>$2</b>")
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
                HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.openMeeting(pane.withOrganizer(card.m)) }
                Rectangle {
                    x: 17; y: 15; width: 40; height: 40; radius: 4
                    color: "transparent"; border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 1; height: 22; verticalAlignment: Text.AlignVCenter; text: card.m.start ? new Date(card.m.start).getDate() : ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 23; text: card.m.start ? Qt.formatDate(new Date(card.m.start), "MMM").toUpperCase() : ""; font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                }
                Text {
                    x: 73; y: 13; width: (editButton.visible ? editButton.x : chatButton.visible ? chatButton.x : moreButton.x) - 8 - 73; elide: Text.ElideRight
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
                // Your own meeting: Edit (calv2-edit-button, 65 x 24,
                // outlined, Edit 16 at 11 and "Edit" 12/16 semibold at 33),
                // 8 before Chat with participants.
                Rectangle {
                    id: editButton
                    visible: pane.isMine(card.m) && !card.m.cancelled
                    x: chatButton.x - 8 - width; y: 13; width: 65; height: 24; radius: 4
                    color: editHover.hovered ? theme.hover : theme.surface
                    border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    FluentIcon { x: 11; anchors.verticalCenter: parent.verticalCenter; name: "edit-20"; size: 16; color: theme.onFill(editButton, theme.textStrong) }
                    Text { x: 33; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Edit"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(editButton, theme.textStrong) }
                    HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pane.editMeeting(pane.withOrganizer(card.m)) }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Edit %1").arg(card.m.subject || "")
                }
                Rectangle {
                    id: chatButton
                    visible: !!card.m.join_url
                    x: moreButton.x - 8 - width; y: 13; width: 24; height: 24; radius: 4
                    color: chatHover.hovered ? theme.hover : theme.surface
                    border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    FluentIcon { anchors.centerIn: parent; name: "chat-20"; size: 16; color: theme.onFill(chatButton, theme.textStrong) }
                    HoverHandler { id: chatHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pane.openChat(card.m) }
                    ToolTip.visible: chatHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Chat with participants")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Chat with participants")
                }
                // More options (32 x 25 at the right, 17 in): Teams' card
                // menu in contextual search keeps only Copy link (a meeting
                // with a join link that isn't cancelled; seen the same for
                // its organizer and an attendee).
                Rectangle {
                    id: moreButton
                    readonly property var items: !!card.m.join_url && !card.m.cancelled ? [{ key: "copy", label: qsTr("Copy link"), icon: "link-20" }] : []
                    visible: items.length > 0
                    x: card.width - 17 - width; y: 13; width: 32; height: 25; radius: 4
                    color: moreHover.hovered || moreMenu.opened ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 16; color: theme.onFill(moreButton, theme.textStrong) }
                    HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: moreMenu.open() }
                    ToolTip.visible: moreHover.hovered && !moreMenu.opened; ToolTip.delay: 500; ToolTip.text: qsTr("More options")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("More options")
                    MenuPopup {
                        id: moreMenu
                        // (Teams: 160 wide, its end on the button's, just under it.)
                        x: moreButton.width + 1 - width; y: moreButton.height + 5
                        minRowWidth: 150
                        items: moreButton.items
                        onPicked: i => { if (moreButton.items[i].key === "copy") pane.copyLink(card.m) }
                    }
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

    /// Test hook (--meetings-pane-test): open the Date or Organizer
    /// popup, a meeting's More options, or close them; what's shown.
    function forTest(what, arg) {
        if (what === "date") datePill.clicked()
        else if (what === "organizer") organizerPill.clicked()
        else if (what === "type") who.text = arg
        else if (what === "pick") { const p = organizerPop.people.find(x => x.name === arg); if (p) organizerPop.pick(p) }
        else if (what === "week") dateKey = "week"
        else if (what === "range") { customFrom = new Date(arg); customTo = new Date(); dateKey = "custom"; customGen++ }
        else if (what === "clear") { dateKey = ""; organizer = null }
        else if (what === "close") { datePop.close(); organizerPop.close() }
        return {
            width: width, dateChoice: dateChoice, organizer: organizer ? organizer.name : "",
            people: organizerPop.opened ? organizerPop.people.map(p => p.name) : [],
            meetings: meetings.map(m => [m.subject, m.start, isMine(m), !!m.join_url, invitedBy(m)])
        }
    }
}
