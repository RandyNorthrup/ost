import QtQuick
import QtQuick.Window
import QtQuick.Controls
import com.ost.desktop

// Teams' Camera ▾ flyout (video-button-configure, measured in Teams in a
// call, 2026-11-08): content 326 wide with padding 16 — your live preview
// (326 x 183, mirrored) while it's open, "Camera" (12 px) with the cameras
// as radios (36 px rows), a divider and "More video effects and settings".
// Teams' Backgrounds picker and "Adjust brightness" need its own video
// effects, which OST doesn't have yet (TASK-0064), so they aren't offered.
// Picking a camera moves a running call's video to it at once.
Popup {
    id: root
    /// The call's camera is on (the preview is then the call's own video).
    property bool cameraOn: false
    signal moreVideoSettings()
    width: 358.7
    height: col.implicitHeight + 33.3
    padding: 0
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    property var cameras: []
    property string current: ""
    property bool previewing: false
    onOpened: {
        const d = JSON.parse(backend.videoDevices())
        cameras = d.devices || []
        current = d.current || ""
        // Teams previews the camera in the flyout while video is off.
        previewing = !cameraOn && cameras.length > 0 && backend.setCameraPreview(true)
    }
    onClosed: if (previewing) { previewing = false; backend.setCameraPreview(false) }

    Column {
        id: col
        x: 16.7; y: 16.7; width: 326
        Rectangle {
            width: 326; height: 183; radius: 4
            color: theme.pane
            clip: true
            VideoFrame {
                id: preview
                anchors.fill: parent
                visible: hasFrame
                source: root.opened && (root.cameraOn || root.previewing) ? "self" : ""
                radius: 4
                transform: Scale { origin.x: preview.width / 2; xScale: -1 }
                Timer { interval: 33; repeat: true; running: root.opened; onTriggered: preview.refresh() }
            }
            Text {
                visible: !preview.visible
                anchors.centerIn: parent
                text: root.cameras.length === 0 ? "No camera is connected" : "Starting your camera…"
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
        }
        Item { width: 326; height: 4 }
        Text {
            width: 326; height: 16; verticalAlignment: Text.AlignVCenter
            text: "Camera"
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        Item { width: 326; height: 4 }
        Repeater {
            model: root.cameras
            Item {
                id: row
                required property var modelData
                readonly property bool chosen: root.current === modelData.path
                width: 326; height: 36
                FluentIcon { x: -2; anchors.verticalCenter: parent.verticalCenter; name: row.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: row.chosen ? theme.brand : theme.textSecondary }
                Text {
                    x: 26; anchors.verticalCenter: parent.verticalCenter; width: 300
                    elide: Text.ElideRight
                    text: row.modelData.name
                    font.family: theme.font; font.pixelSize: 14
                    color: row.chosen ? theme.text : theme.textSecondary
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (row.chosen) return
                        root.current = row.modelData.path
                        backend.setCameraDevice(row.modelData.path)
                        // The flyout's preview follows the new camera.
                        if (root.previewing) { backend.setCameraPreview(false); backend.setCameraPreview(true) }
                    }
                }
                Accessible.role: Accessible.RadioButton
                Accessible.name: row.modelData.name
                Accessible.checked: row.chosen
            }
        }
        Item { width: 326; height: 7.3 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 13.3 }
        Item {
            width: 326; height: 31
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "More video effects and settings"
                font.family: theme.font; font.pixelSize: 14
                color: mvHover.hovered ? theme.text : theme.textStrong
            }
            HoverHandler { id: mvHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.moreVideoSettings() } }
            Accessible.role: Accessible.Button
            Accessible.name: "More video effects and settings"
        }
    }
}
