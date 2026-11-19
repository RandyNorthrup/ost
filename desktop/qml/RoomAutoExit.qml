import QtQuick

// Room mode: Teams Rooms' auto exit at a meeting's end
// (RigelAutoExitMeetingManager and MeetingRoomAutoExitDialogRenderer, read
// in the Teams Rooms build of Teams, MSTeams-Rooms 26198.304 from the
// Teams Rooms on Windows 5.7.112 package, and Teams desktop 26304). It
// applies while nobody but the room is left (InCallRemoteParticipants 0)
// and the meeting's scheduled end has passed; then, after 5 minutes
// (1 for an ad-hoc meeting), the dialog shows "About to leave meeting ..."
// (meetingRoomConsole meeting_room_auto_exit_dialog_title) with a progress
// bar filling over 15 s (autoExitDialogProgressBarCompletionTimeInMs) and
// Snooze / Leave now. Leave now, or the bar filling up, leaves the
// meeting; Snooze hides it for 15 minutes. It goes away when someone
// comes back.
// Layout (its makeStyles): the surface 45% x 27% of the screen, square
// corners; a column of the title (size largest, bold, one line, grow 1),
// the large progress bar (grow 1.1) and the buttons (grow 0.8, at the
// end); two large buttons, Leave now with the brand background and 0.8rem
// either side.
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
        console.warn("ROOMEXIT applies", applies, "end", new Date(endMs).toISOString(), "adhoc", adhoc, "at", new Date().toISOString())
        if (applies) startTimer.restart()
        else { startTimer.stop(); snoozeTimer.stop(); shown = false }
    }
    Timer { id: startTimer; interval: root.adhoc ? 60000 : 300000; onTriggered: root.shown = true }
    Timer { id: snoozeTimer; interval: 900000; onTriggered: if (root.applies) root.shown = true }

    readonly property int completion: 15000
    property int progress: 0
    onShownChanged: {
        progress = 0
        console.warn("ROOMEXIT", shown ? "shown" : "hidden", "at", new Date().toISOString())
    }
    // --room-exit-shot: the dialog captured 5 s after it shows.
    Timer {
        running: root.shown && Qt.application.arguments.indexOf("--room-exit-shot") >= 0
        interval: 5000
        onTriggered: root.grabToImage(r => r.saveToFile("/tmp/act/room-exit.png"))
    }
    Timer {
        interval: 25; repeat: true
        running: root.shown && root.progress < root.completion
        onTriggered: {
            root.progress += 25
            if (root.progress >= root.completion) {
                console.warn("ROOMEXIT progress full: leaving at", new Date().toISOString())
                root.shown = false; root.leave()
            }
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
        width: Math.round(parent.width * 0.45); height: Math.round(parent.height * 0.27)
        color: theme.surface
        Column {
            id: col
            objectName: "meeting-room-auto-exit-dialog-content"
            anchors.fill: parent
            anchors.margins: 24
            readonly property real share: (height - titleText.implicitHeight - 4 - 40) / 2.9
            Item {
                width: parent.width; height: titleText.implicitHeight + col.share * 1.0
                Text {
                    id: titleText
                    objectName: "auto-exit-text"
                    width: parent.width
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: "About to leave meeting ..."
                    font.family: theme.font; font.pixelSize: 32; font.weight: Font.Bold
                    color: theme.text
                }
            }
            Item {
                width: parent.width; height: 4 + col.share * 1.1
                Rectangle {
                    objectName: "progress-bar"
                    width: parent.width; height: 4; radius: 2
                    color: theme.stroke
                    Rectangle { width: parent.width * Math.min(1, root.progress / root.completion); height: parent.height; radius: 2; color: theme.brand }
                }
            }
            Item {
                width: parent.width; height: 40 + col.share * 0.8
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    component ExitButton: Rectangle {
                        id: eb
                        property string label
                        property bool brandFill: false
                        signal clicked()
                        width: Math.max(96, ebText.implicitWidth + 32); height: 40; radius: 4
                        color: brandFill ? (ebHover.hovered ? theme.brandHover : theme.brandFill)
                                         : (ebHover.hovered ? theme.menuHover : theme.surface)
                        border.color: brandFill ? "transparent" : theme.stroke; border.width: 1
                        Text {
                            id: ebText
                            anchors.centerIn: parent
                            text: eb.label
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                            color: theme.onFill(eb, theme.text)
                        }
                        HoverHandler { id: ebHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: eb.clicked() }
                        Accessible.role: Accessible.Button
                        Accessible.name: eb.label
                        Accessible.onPressAction: eb.clicked()
                    }
                    ExitButton { label: "Snooze"; onClicked: { root.shown = false; snoozeTimer.restart() } }
                    Item { width: 8; height: 1 }
                    ExitButton { label: "Leave now"; brandFill: true; onClicked: { root.shown = false; root.leave() } }
                    Item { width: 8; height: 1 }
                }
            }
        }
    }
}
