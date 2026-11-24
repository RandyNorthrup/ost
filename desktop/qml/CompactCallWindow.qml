import QtQuick
import QtQuick.Window

// Teams' compact meeting view (call monitor, measured on winpc
// 2026-11-08): while the meeting window is minimised, a 521.33 x 248
// window at the screen's bottom right with
// - a 32 px title bar: Minimize, "Show only active speaker" and
//   "Maximize meeting window" (24 x 23.33, radius 4, 16 px #424242
//   glyphs, filled on hover) at 434.33, 464.33 and 494.33;
// - a 40 px toolbar: Camera, Mic, Share, Raise, React and People (32 px,
//   radius 4, 20 px glyphs at 6; the People count 14 px at 22.23) from
//   106.67, 46 apart, then Leave at 382.67;
// - the stage: tiles 170 square (inset 2) from 5.66 at y 72, name tags
//   without the name, 4 px in.
Window {
    id: cw
    /// The call window (state and actions).
    property var call
    property bool activeSpeakerOnly: false
    signal restore()
    // (Window sizes are whole logical pixels: 521.33 rounds to 521.)
    width: 521; height: 248
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: qsTr("Meeting compact view | %1").arg(call ? call.peer : "") + " | OST"
    color: theme.hc("#FFFFFF", "#000000")
    x: screen ? screen.virtualX + screen.desktopAvailableWidth - width - 6.67 : 0
    y: screen ? screen.virtualY + screen.desktopAvailableHeight - height - 35 : 0

    readonly property var people: {
        if (!call) return []
        const all = [call.selfEntry].concat(call.othersOrdered)
        if (!activeSpeakerOnly) return all.slice(0, 3)
        const sp = call.others.find(p => p.id === call.speakerId) || call.othersOrdered[0]
        return sp ? [sp] : [call.selfEntry]
    }

    // Title bar (call-monitor-titlebar): drag to move.
    Rectangle {
        width: parent.width; height: 32; color: theme.hc("#FFFFFF", "#000000")
        DragHandler { target: null; onActiveChanged: if (active) cw.startSystemMove() }
        Repeater {
            model: [
                { x: 434.33, icon: "subtract-20", tip: qsTr("Minimize"), act: "min" },
                { x: 464.33, icon: "rectangle-landscape-20", tip: qsTr("Show only active speaker"), act: "speaker" },
                { x: 494.33, icon: "picture-in-picture-exit-20", tip: qsTr("Maximize meeting window"), act: "max" }
            ]
            Rectangle {
                id: hcFill1
                required property var modelData
                x: modelData.x; y: 4.33; width: 24; height: 23.33; radius: 4
                color: tbHover.hovered ? theme.pick("#F5F5F5", "#383838", "#1AEBFF") : "transparent"
                FluentIcon {
                    anchors.centerIn: parent; size: 16
                    name: parent.modelData.icon + (tbHover.hovered ? "-filled" : "")
                    color: theme.onFill(hcFill1, theme.textStrong)
                }
                HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        const a = parent.modelData.act
                        if (a === "min") cw.showMinimized()
                        else if (a === "speaker") cw.activeSpeakerOnly = !cw.activeSpeakerOnly
                        else cw.restore()
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.tip
            }
        }
    }

    // Toolbar (ubar-toolbar-wrapper).
    Item {
        y: 32; width: parent.width; height: 40
        Repeater {
            model: cw.call ? [
                { icon: cw.call.cameraOn ? "call-camera-filled" : "call-camera-off-filled", tip: cw.call.cameraOn ? qsTr("Turn camera off") : qsTr("Turn camera on"), strong: true, act: "camera" },
                { icon: !cw.call.hasAudio ? "speaker-mute-20-filled" : cw.call.muted ? "call-mic-off-filled" : "call-mic-filled", tip: !cw.call.hasAudio ? qsTr("Turn audio on") : cw.call.muted ? qsTr("Unmute mic") : qsTr("Mute mic"), strong: true, act: "mic" },
                { icon: cw.call.sharing ? "call-share-stop-filled" : "call-share-filled", tip: qsTr("Share"), strong: true, act: "share" },
                { icon: "call-raise", tip: cw.call.handRaised ? qsTr("Lower your hand") : qsTr("Raise your hand"), act: "raise" },
                { icon: "call-react", tip: qsTr("React"), act: "react" },
                { icon: "call-people", tip: qsTr("People"), act: "people", count: cw.call.roster.filter(p => p.active !== false).length }
            ] : []
            Rectangle {
                id: hcFill2
                required property var modelData
                required property int index
                x: 106.67 + index * 46; y: 4; width: 32; height: 32; radius: 4
                color: btHover.hovered ? theme.rowHover : "transparent"
                FluentIcon {
                    x: parent.modelData.count !== undefined ? 2.23 : 6; y: 6; size: 20
                    name: parent.modelData.icon
                    color: theme.onFill(hcFill2, parent.modelData.strong || btHover.hovered ? theme.text : theme.textStrong)
                }
                Text {
                    visible: parent.modelData.count !== undefined
                    x: 22.23; y: 6; height: 20; verticalAlignment: Text.AlignVCenter
                    text: parent.modelData.count || ""
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.onFill(hcFill2, theme.textStrong)
                }
                HoverHandler { id: btHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        const a = parent.modelData.act
                        if (a === "camera") cw.call.toggleCamera()
                        // Teams' call monitor in no audio mode shows the
                        // call window instead of turning audio on.
                        else if (a === "mic" && !cw.call.hasAudio) cw.restore()
                        else if (a === "mic") cw.call.toggleMute()
                        else if (a === "share") cw.call.toggleShare()
                        else if (a === "raise") cw.call.toggleHand()
                        else { cw.call.side = a === "people" ? "people" : cw.call.side; cw.restore() }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.tip
            }
        }
        Rectangle {
            id: hcFill3
            x: 382.67; y: 4; width: 32; height: 32; radius: 4
            color: leaveHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { x: 6; y: 6; size: 20; name: "call-leave-filled"; color: theme.onFill(hcFill3, theme.hc("#B10E1C", "#FFFFFF")) }
            HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: cw.call.leave() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Leave")
        }
    }

    // Stage: up to three tiles, or the active speaker only.
    Row {
        x: 5.66; y: 72
        Repeater {
            model: cw.visible ? cw.people : []
            MeetingTile {
                required property var modelData
                call: cw.call
                person: modelData
                compact: true
                width: 170; height: 170
            }
        }
    }
}
