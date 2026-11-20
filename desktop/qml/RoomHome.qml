import QtQuick

// Room mode: what a Teams Rooms device shows between meetings, in place of
// the app. Teams Rooms' front-of-room home (meeting-room-front-of-room-home
// in Teams' bundles):
// - the room info panel (meeting-room-info): the date above the clock, then
//   the room's name with the cast icon;
// - the room's QR code (qr-code: Teams' qr_code link with the room's
//   current proximity salt, renewed every minute) with "Add this room to a
//   meeting with your personal device";
// - its calendar (front-of-room-calendar): today's meetings as cards
//   (calendar-meeting-card-details: the title, "{start} - {end}", the
//   organizer, Join for a Teams meeting; "Now" while it runs; "All day";
//   "Private Meeting"); "Available" when nothing is booked;
// - while an invitation rings (Teams Rooms' manual accept, when it didn't
//   auto-accept), a card to answer it.
// A meeting the room is in shows in the call window.
Rectangle {
    id: root
    property string roomName
    // Rows of "0"/"1" QR modules.
    property string qr
    // The calendar's events (backend.calendarJson).
    property var events: []
    // The ringing invitation: who invites the room, and whether it's a
    // meeting.
    property bool ringing: false
    property string caller
    property bool meeting: false
    signal accept()
    signal decline()
    signal join(string url, string title)
    // Ask for today's calendar (and again every 5 minutes).
    signal refreshCalendar(string startUtc, string endUtc)
    color: theme.pane

    property date now: new Date()
    Timer { interval: 1000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }
    function loadToday() {
        const d = new Date(); d.setHours(0, 0, 0, 0)
        const e = new Date(d.getTime() + 86400000)
        root.refreshCalendar(d.toISOString().slice(0, 19) + "Z", e.toISOString().slice(0, 19) + "Z")
    }
    Timer { interval: 300000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.loadToday() }

    readonly property var today: {
        const start = new Date(root.now); start.setHours(0, 0, 0, 0)
        const end = start.getTime() + 86400000
        return (root.events || []).filter(ev => !ev.is_cancelled && Date.parse(ev.end_utc) > root.now.getTime() - 60000
                && Date.parse(ev.start_utc) < end)
            .sort((a, b) => Date.parse(a.start_utc) - Date.parse(b.start_utc))
    }
    function time(iso) { return new Date(Date.parse(iso)).toLocaleTimeString(Qt.locale(), "h:mm AP") }

    Column {
        id: info
        objectName: "meeting-room-info"
        x: 64; y: 64
        width: parent.width / 2 - 96
        spacing: 4
        Text {
            text: root.now.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
            font.family: theme.font; font.pixelSize: 20
            color: theme.textSecondary
        }
        Text {
            objectName: "meeting-room-info-clock"
            text: root.now.toLocaleTimeString(Qt.locale(), "h:mm AP")
            font.family: theme.font; font.pixelSize: 64; font.weight: Font.DemiBold
            color: theme.text
        }
        Row {
            objectName: "meeting-room-info-name"
            spacing: 8
            // Teams Rooms' cast tooltip (809529, front of room): "Cast to
            // this room with:" (24) over "Teams Cast" (24 bold, the cast
            // glyph 5 before it), shown while the room's Bluetooth beacon
            // advertises it (room mode always does); Miracast would sit
            // before it, 35 apart, where the device offers it.
            FluentIcon {
                id: castIcon
                anchors.verticalCenter: parent.verticalCenter; name: "cast-20"; size: 20; color: theme.text
                HoverHandler { id: castHover }
                TapHandler { onTapped: castTip.shown = !castTip.shown }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cast to this room with:") + " " + qsTr("Teams Cast")
            }
            Text {
                text: root.roomName
                font.family: theme.font; font.pixelSize: 20
                color: theme.text
            }
        }
    }

    // The QR code (160 px, Teams' size below 1280 px wide; 144 at 1280).
    Column {
        anchors.left: info.left
        anchors.bottom: parent.bottom; anchors.bottomMargin: 64
        spacing: 12
        Rectangle {
            id: qrBox
            objectName: "qr-code"
            visible: root.qr.length > 0
            width: 160; height: 160
            color: "#FFFFFF"
            Canvas {
                id: qrCanvas
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.fillStyle = "#FFFFFF"; ctx.fillRect(0, 0, width, height)
                    const rows = root.qr.split("\n")
                    const n = rows.length
                    if (!n) return
                    const m = width / n
                    ctx.fillStyle = "#000000"
                    for (let y = 0; y < n; y++)
                        for (let x = 0; x < rows[y].length; x++)
                            if (rows[y][x] === "1") ctx.fillRect(Math.floor(x * m), Math.floor(y * m), Math.ceil(m), Math.ceil(m))
                }
                Connections { target: root; function onQrChanged() { qrCanvas.requestPaint() } }
            }
            // The app icon in the middle, as Teams puts its own (error correction H
            // keeps the code readable).
            Rectangle {
                anchors.centerIn: parent
                width: 36; height: 36; radius: 6
                color: "#FFFFFF"
                Image { anchors.centerIn: parent; width: 28; height: 28; source: "../assets/logo.png"; sourceSize: Qt.size(56, 56) }
            }
        }
        Text {
            width: 320
            wrapMode: Text.Wrap
            text: qsTr("Add this room to a meeting with your personal device")
            font.family: theme.font; font.pixelSize: 16
            color: theme.textSecondary
        }
    }

    // The calendar.
    Item {
        objectName: "front-of-room-calendar"
        x: parent.width / 2; y: 64
        width: parent.width / 2 - 64; height: parent.height - 128
        Text {
            visible: root.today.length === 0
            text: qsTr("Available")
            font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
            color: theme.text
        }
        ListView {
            anchors.fill: parent
            spacing: 12
            clip: true
            model: root.today
            delegate: Rectangle {
                id: cardItem
                required property var modelData
                readonly property bool live: Date.parse(modelData.start_utc) <= root.now.getTime()
                readonly property bool isPrivate: (modelData.sensitivity || "").toLowerCase() === "private"
                width: ListView.view.width
                height: cardCol.height + 32
                radius: 8
                color: theme.surface
                border.color: live ? theme.brand : theme.stroke; border.width: live ? 2 : 1
                Column {
                    id: cardCol
                    x: 16; y: 16; width: parent.width - 32 - (joinBtn.visible ? joinBtn.width + 16 : 0)
                    spacing: 4
                    Text {
                        objectName: "calendar-meeting-card-details-title"
                        width: parent.width
                        elide: Text.ElideRight
                        text: cardItem.isPrivate ? qsTr("Private Meeting")
                            : (cardItem.modelData.subject || qsTr("Meeting with %1").arg(cardItem.modelData.organizer || ""))
                        font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    Text {
                        objectName: "calendar-meeting-card-details-time"
                        text: (cardItem.live ? qsTr("Now") + " · " : "") + (cardItem.modelData.is_all_day ? qsTr("All day")
                            : root.time(cardItem.modelData.start_utc) + " - " + root.time(cardItem.modelData.end_utc))
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.textSecondary
                    }
                    Text {
                        objectName: "calendar-meeting-card-details-organizer"
                        visible: !cardItem.isPrivate && !!cardItem.modelData.organizer
                        text: cardItem.modelData.organizer || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.textSecondary
                    }
                }
                Rectangle {
                    id: joinBtn
                    objectName: "join-button"
                    visible: !!cardItem.modelData.join_url
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96; height: 36; radius: 4
                    color: joinHover.hovered ? theme.brandHover : theme.brandFill
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Join")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.textOnBrand
                    }
                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.join(cardItem.modelData.join_url, cardItem.modelData.subject || "") }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Join")
                    Accessible.onPressAction: root.join(cardItem.modelData.join_url, cardItem.modelData.subject || "")
                }
            }
        }
    }

    // The invitation ringing on the console.
    Rectangle {
        id: card
        visible: root.ringing
        objectName: "meeting-room-ring-indicator"
        anchors.centerIn: parent
        width: 360; height: col.height + 48
        radius: 8
        color: theme.surface
        border.color: theme.stroke; border.width: 1
        Column {
            id: col
            x: 24; y: 24; width: parent.width - 48
            spacing: 16
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.caller
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                color: theme.text
            }
            Text {
                objectName: "meeting-room-ring-indicator-text"
                width: parent.width
                wrapMode: Text.Wrap
                text: root.meeting ? qsTr("Inviting this room to a meeting") : qsTr("Incoming call")
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
            Row {
                spacing: 8
                component RingButton: Rectangle {
                    id: rb
                    property string label
                    property bool primary: false
                    signal clicked()
                    width: 152; height: 32; radius: 4
                    color: primary ? (rbHover.hovered ? theme.brandHover : theme.brandFill)
                                   : (rbHover.hovered ? theme.menuHover : theme.surface)
                    border.color: primary ? "transparent" : theme.stroke; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: rb.label
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.onFill(rb, rb.primary ? theme.textOnBrand : theme.text)
                    }
                    HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: rb.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: rb.label
                    Accessible.onPressAction: rb.clicked()
                }
                RingButton { label: qsTr("Decline"); onClicked: root.decline() }
                RingButton { label: qsTr("Accept"); primary: true; onClicked: root.accept() }
            }
        }
    }

    Rectangle {
        id: castTip
        property bool shown: false
        objectName: "meeting-room-cast-tooltip"
        visible: castHover.hovered || shown
        readonly property point at: castIcon.mapToItem(root, 0, castIcon.height)
        x: Math.min(root.width - width - 8, at.x - 12); y: at.y + 8
        z: 10
        width: tipCol.width + 24; height: tipCol.height + 24; radius: 8
        color: theme.surface
        border.width: 1; border.color: theme.stroke
        Column {
            id: tipCol
            x: 12; y: 12; spacing: 8
            Text { text: qsTr("Cast to this room with:"); font.family: theme.font; font.pixelSize: 24; color: theme.text }
            Row {
                spacing: 5
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "cast-20"; size: 20; color: theme.text }
                Text { text: qsTr("Teams Cast"); font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; color: theme.text }
            }
        }
        Timer { running: castTip.shown; interval: 5000; onTriggered: castTip.shown = false }
    }
}
