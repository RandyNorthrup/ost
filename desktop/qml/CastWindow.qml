import QtQuick
import QtQuick.Controls.Basic

// Teams' Cast window (Settings and more ▸ Cast; measured on winpc
// 2026-11-15, the wizard read in Teams' cast-app and its theme, 2026-11-19):
// a 626 x 713 window, always dark, under Teams' child-window title row
// ("Cast"). A #292929 band (y 32-92) with the brand Cast tile (32 px,
// #4F52B2, radius 3, the white 20 px cast glyph) 20 in and "Cast" (16.38/
// 23.4 bold in Teams; 16 here, Qt sizes are whole pixels) at 64; on
// #1F1F1F the wizard's step (12 under the band), and its footer: Back
// (52 in, from the second step), what's picked so far (the room, then the
// meeting; 12/16, right-aligned, 300 at most, 12 before the button) and
// Next / Cast (96 x 32, 52 from the right, 20.33 from the bottom, disabled
// until the step has a choice).
// The steps (Teams' CastWizard):
// 1. "Select a nearby Teams Room" (16/22, centred at 104), then, 15
//    under it: the Teams Rooms heard over Bluetooth (the same beacons as
//    Room audio's Nearby, strongest first) as 536 x 80 cards 8 apart (the
//    TV glyph in a 44 px #666666 circle 20 in, its name and its presence:
//    Available, In a call, In a conference call, In a meeting, Presenting
//    or Offline; the nearby glyph after the presence when the room is
//    adjacent, a round check at the end), one room picked by itself; while
//    none is heard "Searching for nearby Teams Rooms..." for 20 s, then
//    "Didn't find any Teams Rooms nearby that we can cast to."; with
//    Bluetooth off "Turn on Bluetooth to automatically detect nearby
//    rooms." under Teams' Bluetooth-off glyph.
// 2. "Cast and join your meeting?" with "By joining, you'll also share
//    your screen with everyone in the meeting.": "Just cast" (picked) and
//    each Teams meeting from an hour ago to an hour ahead ("Cast and
//    join", "<start> | <subject>"). Without such meetings the step is
//    left out.
// 3. "What do you want to cast?" over Teams' share tray in its Cast mode
//    (a 448-wide card, up to 480 and scrolling): "Share content" with
//    Include sound, Screen and Window (on Linux the desktop's picker then
//    asks which), and PowerPoint Live when it has recent files.
// Cast starts the cast and leaves the window open on its last step, as
// Teams' wizard does (Main.qml: a Meet now, or
// the picked meeting, joined without audio, the content shared once in,
// and the room added with its beacon's code, as Teams' cast does).
Window {
    id: win
    property bool pinned: false
    property bool searching: true
    title: qsTr("Cast")
    width: 626; height: 713
    minimumWidth: 400; minimumHeight: 400
    color: theme.hc("#1F1F1F", "#000000")
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
    /// Cast: {room: {mri, name, code}, meeting: {subject, joinUrl} | null,
    /// content: {kind: "screen" | "window" | "ppt", file}, includeSound}.
    signal cast(var spec)

    // The wizard's state.
    property string step: "rooms"
    property var nearby: ({ supported: false, radioOn: false, rooms: [] })
    property var room: null
    property var meetings: []
    property var meeting: null      // null: Just cast
    property var content: null
    property bool includeSound: false
    /// Recent PowerPoint files (Office's MRU, as the share tray lists them).
    property var pptFiles: []
    readonly property var steps: meetings.length > 0 ? ["rooms", "meetings", "content"] : ["rooms", "content"]
    readonly property int stepIndex: Math.max(0, steps.indexOf(step))
    readonly property bool lastStep: stepIndex === steps.length - 1
    readonly property bool canNext: step === "rooms" ? !!room : step === "meetings" ? true : !!content

    /// Cast was pressed (the harness's wizard part is over).
    property bool started: false
    function start() {
        step = "rooms"; room = null; meeting = null; content = null; includeSound = false; meetings = []; started = false
        searching = true; searchTimer.restart()
        refresh()
        backend.calendarAction("castMeetings", "{}")
        backend.contentRecentLoad()
        show(); raise(); requestActivate()
    }
    function refresh() {
        try { nearby = JSON.parse(backend.nearbyRooms(win.visible)) } catch (e) {}
        const list = nearby.rooms || []
        // Teams: one room heard is picked by itself; Bluetooth off or the
        // list emptied clears the choice.
        if (!nearby.supported || !nearby.radioOn || list.length === 0) room = null
        else if (list.length === 1 && !room) room = list[0]
        else if (room) room = list.find(r => r.mri === room.mri) || null
    }
    function next() {
        if (!canNext) return
        if (lastStep) {
            const spec = { room: room, meeting: meeting, content: content, includeSound: includeSound }
            console.warn("CAST start", JSON.stringify({ room: room.name, meeting: meeting ? meeting.subject : "", content: content.kind }))
            // Teams' wizard only fires the calling intent: the Cast window
            // stays open on its last step (seen on winpc 2026-11-23).
            started = true
            win.cast(spec)
            return
        }
        step = steps[stepIndex + 1]
    }
    function back() { if (stepIndex > 0) step = steps[stepIndex - 1] }
    onVisibleChanged: if (!visible) backend.nearbyRooms(false)
    Timer { id: searchTimer; interval: 20000; onTriggered: win.searching = false }
    // The rooms heard (Room audio's Nearby polls the same way).
    Timer { interval: 1000; repeat: true; running: win.visible && win.step === "rooms"; onTriggered: win.refresh() }
    Connections {
        target: backend
        function onCalendarActionDone(op, result, error) {
            if (op !== "castMeetings" || error) return
            try { win.meetings = JSON.parse(result).meetings || [] } catch (e) {}
        }
        function onCallContentJsonChanged() { win.loadRecent() }
    }
    function loadRecent() {
        try { const c = JSON.parse(backend.callContentJson || "{}"); pptFiles = ((c || {}).recent || {}).ppt || [] } catch (e) {}
    }
    // The harness: the wizard's state, and its steps by hand.
    function stateForTest() {
        return { step: step, steps: steps, searching: searching, nearby: nearby, room: room ? room.name : "", meetings: meetings.map(m => m.subject),
                 meeting: meeting ? meeting.subject : "", content: content ? content.kind : "", canNext: canNext, pptFiles: pptFiles.map(f => f.name) }
    }
    function pickForTest(kind, index) {
        if (kind === "room") room = (nearby.rooms || [])[index] || null
        else if (kind === "meeting") meeting = index < 0 ? null : meetings[index] || null
        else if (kind === "ppt") content = pptFiles[index] ? { kind: "ppt", file: pptFiles[index] } : null
        else content = { kind: kind }
    }
    function nextForTest() { next() }

    Rectangle { anchors.fill: parent; color: theme.hc("#1F1F1F", "#000000") }

    ChildWindowTitleBar {
        id: titleRow
        title: qsTr("Cast")
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    // Teams' isCastHeader: grey 700, 60 tall, 6 / 20 padding.
    Rectangle {
        y: 32; width: parent.width; height: 60
        color: theme.hc("#292929", "#000000")
        Rectangle {
            id: hcFill1
            x: 20; y: 14; width: 32; height: 32; radius: 3
            color: theme.hc("#4F52B2", "#FFFFFF")
            FluentIcon { anchors.centerIn: parent; name: "cast-20"; size: 20; color: theme.onFill(hcFill1, "#FFFFFF") }
        }
        Text {
            x: 64; y: 18.31
            text: qsTr("Cast")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 23.4; lineHeightMode: Text.FixedHeight
            color: "#FFFFFF"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
    }

    // ── the body (Teams' isCastBody: 12 under the band) ────────────────
    Item {
        id: body
        y: 104; width: parent.width
        height: footer.y - y
        clip: true

        // 1. Rooms.
        Item {
            anchors.fill: parent
            visible: win.step === "rooms"
            Text {
                id: roomsTitle
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Select a nearby Teams Room")
                font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: "#FFFFFF"
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            readonly property bool bluetooth: !!win.nearby.supported && !!win.nearby.radioOn
            readonly property var rooms: bluetooth ? (win.nearby.rooms || []) : []
            // Bluetooth off: Teams' Bluetooth-off glyph and its hint.
            Column {
                visible: !parent.bluetooth
                y: 37; width: parent.width; spacing: 8
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "bluetooth-disabled-24"; size: 24; color: "#FFFFFF" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, win.width - 40); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Turn on Bluetooth to automatically detect nearby rooms.")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: "#FFFFFF"
                }
            }
            Text {
                visible: parent.bluetooth && parent.rooms.length === 0
                anchors.horizontalCenter: parent.horizontalCenter; y: 37
                width: Math.min(implicitWidth, parent.width - 40)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: win.searching ? qsTr("Searching for nearby Teams Rooms...") : qsTr("Didn't find any Teams Rooms nearby that we can cast to.")
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: "#FFFFFF"
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            OptionList {
                visible: parent.rooms.length > 0
                y: 37; height: parent.height - 37
                model: parent.rooms
                delegate: OptionItem {
                    required property var modelData
                    header: modelData.name || ""
                    content: win.presenceLabel(modelData)
                    // Teams' presence line: Text "smaller" (10), measured
                    // near white on winpc.
                    contentSize: 10
                    contentColor: "#E8E8E8"
                    icon: "tv-20"
                    // Teams' isNearby: the room is adjacent (its beacon's
                    // proximity), not merely heard.
                    nearbyMark: !!modelData.adjacent
                    selected: !!win.room && win.room.mri === modelData.mri
                    onPicked: win.room = modelData
                }
            }
        }

        // 2. Meetings.
        Item {
            anchors.fill: parent
            visible: win.step === "meetings"
            Column {
                id: meetingsHead
                width: parent.width; spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Cast and join your meeting?")
                    font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight
                    color: "#FFFFFF"
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, win.width - 40); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("By joining, you'll also share your screen with everyone in the meeting.")
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                    color: "#ADADAD"
                }
            }
            OptionList {
                y: meetingsHead.height + 15; height: parent.height - y
                model: [null].concat(win.meetings)
                delegate: OptionItem {
                    required property var modelData
                    header: modelData ? qsTr("Cast and join") : qsTr("Just cast")
                    content: modelData ? (modelData.allDay ? "" : theme.time(new Date(modelData.start)) + " | ") + (modelData.subject || "") : ""
                    icon: modelData ? "calendar-ltr-20" : "cast-20"
                    selected: modelData ? (!!win.meeting && win.meeting.joinUrl === modelData.joinUrl) : !win.meeting
                    onPicked: win.meeting = modelData
                }
            }
        }

        // 3. Content: Teams' share tray in its Cast mode.
        Item {
            anchors.fill: parent
            visible: win.step === "content"
            Text {
                id: contentTitle
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("What do you want to cast?")
                font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: "#FFFFFF"
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            // Teams' share tray in Cast mode (measured on winpc 2026-11-23,
            // Cast with OST in room mode): a 448-wide #292929 card (radius 4)
            // 15 under the title, 244 tall with the screens and windows and
            // up to 480 (scrolling) with PowerPoint Live's files: "Share
            // content" (16 bold) 24 in with Include sound (12) and its 40 x 20
            // switch 27 from the end; "Screen" and "Window" (14/600) 82 down
            // over 144 x 80 tiles 24 apart; PowerPoint Live only when it has
            // recent files.
            Rectangle {
                id: trayCard
                anchors.horizontalCenter: parent.horizontalCenter
                y: 37; width: 448; height: Math.min(win.pptFiles.length > 0 ? 480 : 244, parent.height - y)
                radius: 4
                color: theme.hc("#292929", "#000000")
                border.width: theme.highContrast ? 1 : 0; border.color: "#FFFFFF"
                Item {
                    id: trayHead
                    width: parent.width; height: 70
                    Text {
                        x: 24; y: 34; height: 22; verticalAlignment: Text.AlignVCenter
                        text: qsTr("Share content")
                        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: "#FFFFFF"
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                    // Include sound (Teams' system-audio-checkbox; casting:
                    // the computer's sound plays in the room, not here).
                    Text {
                        anchors.right: soundSwitch.left; anchors.rightMargin: 13
                        anchors.verticalCenter: soundSwitch.verticalCenter
                        text: qsTr("Include sound")
                        font.family: theme.font; font.pixelSize: 12; color: "#FFFFFF"
                    }
                    Rectangle {
                        id: soundSwitch
                        x: parent.width - 27 - width; y: 37
                        width: 40; height: 20; radius: 10
                        color: win.includeSound ? "#7F85F5" : "transparent"
                        border.width: win.includeSound ? 0 : 1; border.color: "#ADADAD"
                        Rectangle {
                            width: 14; height: 14; radius: 7; anchors.verticalCenter: parent.verticalCenter
                            x: win.includeSound ? parent.width - width - 3 : 3
                            color: win.includeSound ? "#1F1F1F" : "#ADADAD"
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.includeSound = !win.includeSound }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: qsTr("Include sound")
                        Accessible.checked: win.includeSound
                    }
                }
                Flickable {
                    id: trayFlick
                    y: 82; width: parent.width; height: parent.height - y
                    contentHeight: trayCol.height + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: trayFlick.contentHeight > trayFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    Column {
                        id: trayCol
                        x: 24; width: parent.width - 48; spacing: 16
                        // Screen and Window (the desktop's picker asks which).
                        Row {
                            spacing: 24
                            Repeater {
                                model: [{ kind: "screen", title: qsTr("Screen"), name: qsTr("Screen %1").arg(1) },
                                        { kind: "window", title: qsTr("Window"), name: qsTr("Opens list of active windows") }]
                                Column {
                                    id: tileCol
                                    required property var modelData
                                    readonly property bool chosen: !!win.content && win.content.kind === modelData.kind
                                    spacing: 9
                                    Text { height: 20; verticalAlignment: Text.AlignVCenter; text: tileCol.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
                                    // The 144 x 80 tile; picked or hovered, a
                                    // 2 px ring 4.67 around it.
                                    Item {
                                        width: 144; height: 80
                                        Rectangle {
                                            anchors.fill: parent; anchors.margins: -4.67; radius: 4
                                            color: "transparent"
                                            border.width: tileCol.chosen || tileHover.hovered ? 2 : 0
                                            border.color: "#7F85F5"
                                        }
                                        Rectangle {
                                            anchors.fill: parent; radius: 4
                                            color: tileCol.modelData.kind === "screen" ? "#1F1F1F" : "#292929"
                                            border.width: tileCol.modelData.kind === "screen" ? 0.67 : 0; border.color: "#3D3D3D"
                                            Text {
                                                visible: tileCol.modelData.kind === "screen"
                                                anchors.centerIn: parent
                                                text: qsTr("Screen %1").arg(1)
                                                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#D6D6D6"
                                            }
                                            Image {
                                                visible: tileCol.modelData.kind === "window"
                                                x: 10; y: 3; width: 124; height: 75
                                                source: "../assets/illustrations/share-window.svg"
                                                sourceSize: Qt.size(248, 150)
                                                fillMode: Image.PreserveAspectFit
                                            }
                                        }
                                        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: win.content = { kind: tileCol.modelData.kind } }
                                        Accessible.role: Accessible.RadioButton
                                        Accessible.name: tileCol.modelData.name
                                        Accessible.checked: tileCol.chosen
                                    }
                                }
                            }
                        }
                        // PowerPoint Live and its recent files (left out
                        // without any, as in Teams' Cast tray).
                        Column {
                            visible: win.pptFiles.length > 0
                            width: parent.width; spacing: 2
                            Text { text: qsTr("PowerPoint Live"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: qsTr("See your notes, slides, and audience while you present.")
                                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: "#ADADAD"
                            }
                            Item { width: 1; height: 6 }
                            Repeater {
                                model: win.pptFiles
                                Rectangle {
                                    id: fileRow
                                    required property var modelData
                                    readonly property bool chosen: !!win.content && win.content.kind === "ppt" && !!win.content.file && win.content.file.url === modelData.url
                                    width: parent.width; height: 36; radius: 4
                                    color: chosen ? "#3D3D3D" : fileHover.hovered ? "#2E2E2E" : "transparent"
                                    border.width: chosen ? 1 : 0; border.color: "#7F85F5"
                                    Image {
                                        x: 8; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
                                        source: "../assets/icons/ft-pptx-20.svg"; sourceSize: Qt.size(40, 40)
                                    }
                                    Text {
                                        x: 40; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 48; elide: Text.ElideRight
                                        text: fileRow.modelData.name || ""
                                        font.family: theme.font; font.pixelSize: 14; color: "#FFFFFF"
                                    }
                                    HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: win.content = { kind: "ppt", file: fileRow.modelData } }
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: fileRow.modelData.name || ""
                                    Accessible.checked: fileRow.chosen
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the footer (Teams' isCastFooter) ───────────────────────────────
    Item {
        id: footer
        y: parent.height - 72.33; width: parent.width; height: 72.33
        // Back (Teams' isCastBackButton: a text button 52 in, the small
        // chevron before it).
        Rectangle {
            id: backButton
            visible: win.stepIndex > 0
            x: 52; y: 20; height: 32; width: backRow.width + 16; radius: 4
            color: backHover.hovered ? "#2E2E2E" : "transparent"
            Row {
                id: backRow
                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-left-12"; size: 12; color: "#FFFFFF" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
            }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.back() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Back")
        }
        // What's picked so far (Teams' isCastFooterSummary).
        Column {
            anchors.right: nextButton.left; anchors.rightMargin: 12
            anchors.verticalCenter: nextButton.verticalCenter
            width: Math.min(300, nextButton.x - 12 - (backButton.visible ? backButton.x + backButton.width + 12 : 12))
            Text {
                visible: win.stepIndex > 0 && !!win.room
                width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                text: win.room ? win.room.name : ""
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: "#FFFFFF"
            }
            Text {
                visible: win.steps.indexOf("meetings") >= 0 && win.stepIndex > win.steps.indexOf("meetings") && !!win.meeting
                width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                text: win.meeting ? win.meeting.subject || "" : ""
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: "#FFFFFF"
            }
        }
        // Next, or Cast on the last step.
        Rectangle {
            id: nextButton
            x: parent.width - 52 - width; y: parent.height - 20.33 - height
            width: 96; height: 32; radius: 4
            color: !win.canNext ? theme.hc("#1F1F1F", "#000000") : nextHover.hovered ? "#4F52B2" : "#5B5FC7"
            Text {
                anchors.centerIn: parent
                text: win.lastStep ? qsTr("Cast") : qsTr("Next")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: win.canNext ? "#FFFFFF" : theme.hc("#5C5C5C", "#3FF23F")
            }
            HoverHandler { id: nextHover; cursorShape: win.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: win.canNext; onTapped: win.next() }
            Accessible.role: Accessible.Button
            Accessible.name: win.lastStep ? qsTr("Cast") : qsTr("Next")
        }
    }

    // A room's presence as Cast shows it (Teams' 81744: by its activity).
    function presenceLabel(r) {
        const a = r.activity || ""
        if (a === "InACall") return qsTr("In a call")
        if (a === "InAConferenceCall") return qsTr("In a conference call")
        if (a === "InAMeeting") return qsTr("In a meeting")
        if (a === "Presenting") return qsTr("Presenting")
        if (a === "Offline" || a === "OffWork" || (!a && (r.status === "Offline" || r.status === "PresenceUnknown"))) return qsTr("Offline")
        return qsTr("Available")
    }

    // Teams' isCastOptionsList: the cards, scrolling, centred.
    component OptionList: ListView {
        x: (parent.width - 536) / 2
        width: 536
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }
    // Teams' isCastOptionListItem (measured on winpc 2026-11-23): 536 x 80,
    // radius 2, #242424 with a #0F0F0F hairline (Teams' border2; the pick
    // shows only in the check, a white ring only with keyboard focus);
    // the glyph (20) in Fluent's large avatar (44, #666666) 20 in; the
    // header (14/20, regular) at 79 and under it the line (12, or a room's
    // presence at 10 with the nearby glyph after it); the round check (16)
    // 19 from the end (brand with a check when picked).
    component OptionItem: Rectangle {
        id: oi
        property string header
        property string content
        property int contentSize: 12
        property color contentColor: "#ADADAD"
        property string icon
        property bool nearbyMark: false
        property bool selected: false
        signal picked()
        width: 536; height: 80; radius: 2
        color: oiHover.hovered ? "#2E2E2E" : "#242424"
        border.width: 0.67; border.color: "#0F0F0F"
        Rectangle {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 44; radius: 22
            color: "#666666"
            FluentIcon { anchors.centerIn: parent; name: oi.icon; size: 20; color: "#FFFFFF" }
        }
        Text {
            x: 79; y: 22; height: 20; verticalAlignment: Text.AlignVCenter
            width: parent.width - x - 44; elide: Text.ElideRight
            text: oi.header
            font.family: theme.font; font.pixelSize: 14; color: "#FFFFFF"
        }
        Row {
            x: 79; y: 42; height: 14
            spacing: 4
            Text {
                visible: oi.content !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, oi.width - 79 - 44 - (oi.nearbyMark ? 16 : 0)); elide: Text.ElideRight
                text: oi.content
                font.family: theme.font; font.pixelSize: oi.contentSize; color: oi.contentColor
            }
            FluentIcon { visible: oi.nearbyMark; anchors.verticalCenter: parent.verticalCenter; name: "cast-20"; size: 12; color: oi.contentColor }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 19; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            color: oi.selected ? "#7F85F5" : "transparent"
            border.width: oi.selected ? 0 : 1; border.color: "#D6D6D6"
            FluentIcon { anchors.centerIn: parent; visible: oi.selected; name: "checkmark-12"; size: 12; color: "#292929" }
        }
        HoverHandler { id: oiHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: oi.picked() }
        Accessible.role: Accessible.RadioButton
        Accessible.name: oi.header + (oi.content ? ", " + oi.content : "")
        Accessible.checked: oi.selected
    }
}
