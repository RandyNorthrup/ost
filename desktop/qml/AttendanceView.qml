import QtQuick
import QtQuick.Controls

// Teams' Attendance view (meeting-attendance-view-wrapper): what its
// Attendance card opens, a meeting chat's Attendance tab or a channel
// meeting's report. Measured on winpc 2026-11-11 (CSS px):
// - a 48 px toolbar (white, a 0.67 #E0E0E0 line under it), 12 in:
//   the meeting picker (#F5F5F5, radius 4, 31.3 tall, the date 14 at 12,
//   the chevron (20, #616161) 10 from the end), then More (96 x 31.3, the
//   filter glyph 20 at 18, "More" 14/600 #424242; brand while hovered or
//   open), and Download at the right (the download glyph 20, "Download"
//   14 5 after it);
// - the report, 20 in: four summary cards in two columns 10 apart (93.3
//   tall, a 0.67 #E0E0E0 border, radius 9, padding 14 24: the value
//   32/600 line 40 with its units 20/600, the label 14 #424242 under it),
//   24 under them "Participants" 16/600 (24 above, 16 below), then the
//   table (a 0.67 #E0E0E0 border, radius 8, 16 above the header): the
//   header row 32 (12/16 #616161: Name, First join, Last leave, In-meeting
//   duration, Role), rows 50 with a line under each, 24 in: the picture
//   (32) and the name 14/20 with the email 12/16 10 after it, the rest
//   14/20; the Name column 276 of 788.7, the others even.
// - the picker's list: white, radius 4, padding 4, the menu shadow; each
//   day a group ("November 11", 12/600 #616161, padding 8 6, 32 tall),
//   its meetings 32 tall (padding 6 8, radius 4: a check (16) on the
//   chosen one, "6:47 AM - 1 attendees" 14 at 32); a line between days.
// - More: a popover (247.9 wide, padding 16, radius 4) with "Number of
//   participants" 12/600, "Show greater than" 14 and a number box (91 x
//   24, #F5F5F5, radius 4, 12 px), then Apply (full width, 31.3); it keeps
//   the meetings with more attendees than that and picks the first.
Rectangle {
    id: root
    color: theme.surface
    /// The meeting chat's thread (or the channel), its organizer's object
    /// id and a channel meeting's post id ("" for a meeting chat).
    property string thread
    property string organizer
    property string message
    /// The call to show first (the card's); "" for the newest.
    property string initialCall: ""
    /// Meetings with more attendees than this (More's filter).
    property int minAttendees: 0

    readonly property var att: backend.attendanceJson ? JSON.parse(backend.attendanceJson) : ({})
    readonly property bool mine: att.key === thread + "|" + message
    readonly property var reports: mine ? (att.reports || []).filter(r => (r.attendeeCount || 0) > minAttendees) : []
    readonly property string callId: mine ? (att.callId || "") : ""
    readonly property var report: mine && att.report ? att.report : null
    readonly property var current: reports.find(r => r.callId === callId) || null

    function load(call) { backend.loadAttendance(thread, organizer, message, call || "") }
    Component.onCompleted: if (thread && organizer) load(initialCall)

    function time(iso) { return iso ? Qt.formatTime(new Date(iso), "h:mm AP") : "" }
    // "35m 1s", "1h 7m 42s": the parts that aren't zero (seconds when all are).
    function duration(sec) {
        const s = Math.max(0, Math.round(sec || 0))
        const parts = [[Math.floor(s / 3600), "h"], [Math.floor(s / 60) % 60, "m"], [s % 60, "s"]].filter(p => p[0] > 0)
        return parts.length ? parts : [[0, "s"]]
    }
    function durationText(sec) { return duration(sec).map(p => p[0] + p[1]).join(" ") }
    // Big numbers with small units, as Teams' summary cards.
    function big(parts) {
        return parts.map(p => "<span style=\"font-size:32px\">" + p[0] + "</span><span style=\"font-size:20px\">" + p[1] + "</span>").join("<span style=\"font-size:20px\">&nbsp;</span>")
    }
    function bigTime(iso) {
        const t = time(iso), i = t.lastIndexOf(" ")
        return "<span style=\"font-size:32px\">" + t.slice(0, i) + "</span><span style=\"font-size:20px\">&nbsp;" + t.slice(i + 1) + "</span>"
    }
    function pickerLabel(r) {
        if (!r) return ""
        return Qt.formatDateTime(new Date(r.startTimeUtc), "dddd, MMMM d, yyyy h:mm AP") + " - " + time(r.endTimeUtc)
    }
    // The picker's rows: a day header, then that day's meetings.
    readonly property var pickerRows: {
        const rows = []
        let day = ""
        for (const r of reports) {
            const d = Qt.formatDate(new Date(r.startTimeUtc), "MMMM d")
            if (d !== day) { if (day) rows.push({ kind: "line" }); rows.push({ kind: "day", text: d }); day = d }
            rows.push({ kind: "meeting", report: r, text: time(r.startTimeUtc) + " - " + r.attendeeCount + " attendees" })
        }
        return rows
    }

    // The toolbar.
    Rectangle {
        id: bar
        width: parent.width; height: 48
        color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio); color: theme.divider }
        Rectangle {
            id: pickerBtn
            x: 12; y: 8.3
            width: pickLabel.implicitWidth + 12 + 8 + 20 + 10; height: 31.3; radius: 4
            color: theme.pick("#F5F5F5", "#292929")
            Text {
                id: pickLabel
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: root.pickerLabel(root.current)
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
            Rectangle { visible: picker.opened; anchors.bottom: parent.bottom; x: 0; width: parent.width; height: 2; color: theme.brand }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: picker.opened ? picker.close() : picker.open() }
            Accessible.role: Accessible.ComboBox
            Accessible.name: pickLabel.text
        }
        Rectangle {
            id: moreBtn
            x: pickerBtn.x + pickerBtn.width; y: 8.3
            width: Math.max(96, moreRow.implicitWidth + 24); height: 31.3; radius: 4
            color: "transparent"
            readonly property bool lit: moreH.hovered || filterPop.opened
            Row {
                id: moreRow
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { name: "filter-20"; size: 20; color: moreBtn.lit ? theme.brand : theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "More"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: moreBtn.lit ? theme.brand : theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
            }
            HoverHandler { id: moreH; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { filterBox.text = String(root.minAttendees); filterPop.open() } }
            Accessible.role: Accessible.Button
            Accessible.name: "More"
        }
        Rectangle {
            id: dl
            anchors.right: parent.right; anchors.rightMargin: 12
            y: 14; width: 96; height: 20; radius: 4
            color: "transparent"
            visible: root.current !== null
            Row {
                x: 4; spacing: 0
                FluentIcon { name: "arrow-download-20"; size: 20; color: dlH.hovered ? theme.brand : theme.text }
                Text { leftPadding: 5; text: "Download"; font.family: theme.font; font.pixelSize: 14; color: dlH.hovered ? theme.brand : theme.text; height: 20; verticalAlignment: Text.AlignVCenter }
            }
            HoverHandler { id: dlH; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.downloadAttendanceReport(root.thread, root.organizer, root.callId) }
            Accessible.role: Accessible.Button
            Accessible.name: "Download"
        }
    }

    // The report.
    Flickable {
        id: flick
        y: bar.height; width: parent.width; height: parent.height - bar.height
        contentHeight: body.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: body
            x: 20; y: 20
            width: flick.width - 40
            spacing: 0
            Text {
                visible: root.mine && !!root.att.error
                text: "The attendance report isn't available right now."
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
            // The summary.
            Grid {
                visible: root.report !== null
                columns: 2; columnSpacing: 10; rowSpacing: 10
                readonly property real cardW: (body.width - 10) / 2
                Repeater {
                    model: root.report ? [
                        { value: "<span style=\"font-size:32px\">" + (root.report.summary.attendeeCount || 0) + "</span>", label: "Attended" },
                        { value: root.bigTime(root.report.summary.startTime) + "<span style=\"font-size:32px\">&nbsp;-&nbsp;</span>" + root.bigTime(root.report.summary.endTime), label: "Start and end time" },
                        { value: root.big(root.duration(root.report.summary.duration)), label: "Meeting duration" },
                        { value: root.big(root.duration(root.report.summary.averageAttendeeDuration)), label: "Average attendance time" }
                    ] : []
                    Rectangle {
                        required property var modelData
                        width: parent.cardW; height: 93.3; radius: 9
                        color: theme.surface
                        border.color: theme.divider; border.width: 0.67
                        Text {
                            x: 24.7; y: 13.3
                            textFormat: Text.RichText
                            text: parent.modelData.value
                            font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        Text {
                            x: 24.7; y: 54.7
                            text: parent.modelData.label
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.textStrong
                        }
                    }
                }
            }
            Item { visible: root.report !== null; width: 1; height: 24 + 24 }
            Text {
                visible: root.report !== null
                text: "Participants"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Item { visible: root.report !== null; width: 1; height: 16 }
            // The table.
            Rectangle {
                id: table
                visible: root.report !== null
                width: body.width
                // Teams' table box is at least 320 tall.
                height: Math.max(320, 16 + 32 + 0.67 + rows.height + 16)
                radius: 8
                color: theme.surface
                border.color: theme.divider; border.width: 0.67
                readonly property real inner: width - 48
                readonly property real nameW: inner * 276 / 788.7
                readonly property real colW: (inner - nameW) / 4
                function colX(i) { return 24 + (i === 0 ? 0 : nameW + (i - 1) * colW) }
                Repeater {
                    model: ["Name", "First join", "Last leave", "In-meeting duration", "Role"]
                    Text {
                        required property string modelData
                        required property int index
                        x: table.colX(index); y: 16 + 8
                        width: (index === 0 ? table.nameW : table.colW) - 16
                        elide: Text.ElideRight
                        text: modelData
                        font.family: theme.font; font.pixelSize: 12
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                }
                Rectangle { x: 0.67; y: 48; width: parent.width - 1.33; height: 0.67; color: theme.divider }
                Column {
                    id: rows
                    x: 0.67; y: 48.67
                    width: parent.width - 1.33
                    Repeater {
                        model: root.report ? (root.report.participants || []) : []
                        Rectangle {
                            id: prow
                            required property var modelData
                            width: rows.width; height: 50
                            color: rowH.hovered ? theme.menuHover : "transparent"
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                            Avatar {
                                x: table.colX(0) - 0.67; y: 7.7
                                size: 32; name: prow.modelData.displayName || ""
                                photoId: prow.modelData.mri || ""
                            }
                            Column {
                                x: table.colX(0) - 0.67 + 42; y: 5.7
                                width: table.nameW - 16 - 42
                                Text { width: parent.width; elide: Text.ElideRight; text: prow.modelData.displayName || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                Text { width: parent.width; elide: Text.ElideRight; text: prow.modelData.emailAddress || prow.modelData.upn || ""; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                            }
                            Repeater {
                                model: [root.time(prow.modelData.joinTime), root.time(prow.modelData.leaveTime), root.durationText(prow.modelData.durationInSeconds), prow.modelData.role || ""]
                                Text {
                                    required property string modelData
                                    required property int index
                                    x: table.colX(index + 1) - 0.67; y: 14.7
                                    width: table.colW - 16; elide: Text.ElideRight
                                    text: modelData
                                    font.family: theme.font; font.pixelSize: 14
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                            }
                            HoverHandler { id: rowH }
                            Accessible.role: Accessible.Row
                            Accessible.name: (modelData.displayName || "") + ", " + root.time(modelData.joinTime) + ", " + root.time(modelData.leaveTime) + ", " + root.durationText(modelData.durationInSeconds) + ", " + (modelData.role || "")
                        }
                    }
                }
            }
        }
    }

    // The meeting picker's list.
    Popup {
        id: picker
        parent: pickerBtn
        y: pickerBtn.height + 2.4
        width: pickerBtn.width
        height: Math.min(529.3, pickList.contentHeight + 8)
        padding: 4
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        ListView {
            id: pickList
            anchors.fill: parent
            clip: true
            interactive: contentHeight > height
            model: root.pickerRows
            delegate: Item {
                id: prow2
                required property var modelData
                width: ListView.view.width
                height: modelData.kind === "line" ? 2.7 : modelData.kind === "day" ? 34 : 34
                Rectangle { visible: prow2.modelData.kind === "line"; y: 1; width: parent.width; height: 0.67; color: theme.divider }
                Text {
                    visible: prow2.modelData.kind === "day"
                    x: 6; y: 8
                    text: prow2.modelData.text || ""
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.textSecondary
                }
                Rectangle {
                    visible: prow2.modelData.kind === "meeting"
                    width: parent.width; height: 32; radius: 4
                    color: optH.hovered ? theme.menuHover : "transparent"
                    readonly property bool chosen: prow2.modelData.report ? prow2.modelData.report.callId === root.callId : false
                    FluentIcon { visible: parent.chosen; x: 6; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                    Text {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        text: prow2.modelData.text || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    HoverHandler { id: optH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { picker.close(); root.load(prow2.modelData.report.callId) } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: prow2.modelData.text || ""
                }
            }
        }
    }

    // More: the attendee-count filter.
    Popup {
        id: filterPop
        parent: moreBtn
        y: moreBtn.height
        x: -16
        width: 247.9
        padding: 16
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Number of participants"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
            Row {
                spacing: 9.9
                height: 24
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Show greater than"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    width: 91; height: 24; radius: 4
                    color: theme.pick("#F5F5F5", "#292929")
                    TextInput {
                        id: filterBox
                        x: 8; width: parent.width - 16; height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                        validator: IntValidator { bottom: 0; top: 100000 }
                        selectByMouse: true
                        Keys.onUpPressed: text = String(Math.min(100000, (parseInt(text) || 0) + 1))
                        Keys.onDownPressed: text = String(Math.max(0, (parseInt(text) || 0) - 1))
                        Keys.onReturnPressed: applyFilter()
                        Accessible.name: "Show greater than"
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 31.3; radius: 4
                color: applyH.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: "Apply"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: applyH; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.applyFilter() }
                Accessible.role: Accessible.Button
                Accessible.name: "Apply"
            }
        }
    }
    function applyFilter() {
        minAttendees = Math.max(0, parseInt(filterBox.text) || 0)
        filterPop.close()
        // Teams picks the first meeting left.
        if (reports.length && !reports.some(r => r.callId === callId)) load(reports[0].callId)
    }
    function openPickerForTest() { picker.open() }
}
