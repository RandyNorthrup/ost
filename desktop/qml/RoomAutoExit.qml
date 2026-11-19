import QtQuick

// Room mode: Teams Rooms' auto exit at a meeting's end
// (RigelAutoExitMeetingManager and its dialog in Teams' bundles 89637 and
// calling-app). It applies while nobody but the room is left
// (InCallRemoteParticipants 0) and the meeting's scheduled end has passed;
// then, after 5 minutes (1 for an ad-hoc meeting), the dialog shows
// "About to leave the meeting..." with a progress bar filling over 15 s
// (autoExitDialogProgressBarCompletionTimeInMs) and Snooze / Leave now.
// Leave now, or the bar filling up, leaves the meeting; Snooze hides it
// for 15 minutes. It goes away when someone comes back.
Item {
    id: root
    // Room mode, in a meeting.
    property bool active: false
    // Nobody else is in the meeting.
    property bool alone: false
    // The meeting's scheduled end (ms since the epoch), 0 if unknown.
    property real endMs: 0
    property bool adhoc: false
    signal leave()

    property real now: Date.now()
    Timer { interval: 1000; running: root.active; repeat: true; onTriggered: root.now = Date.now() }
    readonly property bool applies: active && alone && endMs > 0 && now >= endMs
    property bool shown: false
    onAppliesChanged: {
        if (applies) startTimer.restart()
        else { startTimer.stop(); snoozeTimer.stop(); shown = false }
    }
    Timer { id: startTimer; interval: root.adhoc ? 60000 : 300000; onTriggered: root.shown = true }
    Timer { id: snoozeTimer; interval: 900000; onTriggered: if (root.applies) root.shown = true }

    readonly property int completion: 15000
    property int progress: 0
    onShownChanged: progress = 0
    Timer {
        interval: 25; repeat: true
        running: root.shown && root.progress < root.completion
        onTriggered: {
            root.progress += 25
            if (root.progress >= root.completion) { root.shown = false; root.leave() }
        }
    }

    anchors.fill: parent
    visible: shown
    z: 20
    Rectangle { anchors.fill: parent; color: "#66000000" }
    MouseArea { anchors.fill: parent }
    Rectangle {
        objectName: "meeting-room-auto-exit-dialog-body"
        anchors.centerIn: parent
        width: 480; height: col.height + 48
        radius: 8
        color: theme.surface
        Column {
            id: col
            x: 24; y: 24; width: parent.width - 48
            spacing: 24
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: "About to leave the meeting..."
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold
                color: theme.text
            }
            Rectangle {
                width: parent.width; height: 4; radius: 2
                color: theme.stroke
                Rectangle { width: parent.width * Math.min(1, root.progress / root.completion); height: parent.height; radius: 2; color: theme.brand }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                component ExitButton: Rectangle {
                    id: eb
                    property string label
                    property bool primary: false
                    signal clicked()
                    width: 140; height: 40; radius: 4
                    color: primary ? (ebHover.hovered ? theme.brandHover : theme.brandFill)
                                   : (ebHover.hovered ? theme.menuHover : theme.surface)
                    border.color: primary ? "transparent" : theme.stroke; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: eb.label
                        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                        color: theme.onFill(eb, eb.primary ? theme.textOnBrand : theme.text)
                    }
                    HoverHandler { id: ebHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: eb.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: eb.label
                    Accessible.onPressAction: eb.clicked()
                }
                ExitButton { label: "Snooze"; onClicked: { root.shown = false; snoozeTimer.restart() } }
                ExitButton { label: "Leave now"; primary: true; onClicked: { root.shown = false; root.leave() } }
            }
        }
    }
}
