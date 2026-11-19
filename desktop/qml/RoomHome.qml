import QtQuick

// Room mode: what a Teams Rooms device shows between meetings, in place of
// the app. Teams Rooms' front-of-room home (meeting-room-front-of-room-home
// in Teams' bundles): the room info panel (meeting-room-info: the date
// above the clock, then the room's name with the cast icon), and the hint
// that people join the room from their own device; while an invitation
// rings (Teams Rooms' manual accept, when it didn't auto-accept) a card to
// answer it. A meeting the room is in shows in the call window.
Rectangle {
    id: root
    property string roomName
    // The ringing invitation: who invites the room, and whether it's a
    // meeting.
    property bool ringing: false
    property string caller
    property bool meeting: false
    signal accept()
    signal decline()
    color: theme.pane

    property date now: new Date()
    Timer { interval: 1000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    Column {
        id: info
        objectName: "meeting-room-info"
        x: 64; y: 64
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
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "cast-20"; size: 20; color: theme.text }
            Text {
                text: root.roomName
                font.family: theme.font; font.pixelSize: 20
                color: theme.text
            }
        }
    }

    Text {
        anchors.left: info.left
        anchors.bottom: parent.bottom; anchors.bottomMargin: 64
        width: parent.width - 128
        wrapMode: Text.Wrap
        text: "Add this room to a meeting with your personal device"
        font.family: theme.font; font.pixelSize: 16
        color: theme.textSecondary
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
                text: root.meeting ? "Inviting this room to a meeting" : "Incoming call"
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
                RingButton { label: "Decline"; onClicked: root.decline() }
                RingButton { label: "Accept"; primary: true; onClicked: root.accept() }
            }
        }
    }
}
