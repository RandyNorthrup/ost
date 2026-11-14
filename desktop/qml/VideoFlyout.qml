import QtQuick
import QtQuick.Window
import QtQuick.Controls
import com.ost.desktop

// Teams' Camera ▾ flyout (video-button-configure-popover, measured in a
// call on winpc, 2026-11-14): 359.3 wide, content 326 at 16.7 — your live
// preview (326 x 180, mirrored unless Mirror my video is off) while it's
// open; "Camera" (12 px) with the cameras as radios (34.3 px rows); a
// divider; "Backgrounds" (12 px) over a row of 77 x 48 tiles 6 apart
// (None, the blur tile, Teams' first two catalog backgrounds); a divider;
// Adjust brightness and Soft focus (14 px #424242 labels, Fluent switches,
// 36 px rows); a divider and "More video effects and settings". Teams'
// Avatars tab isn't offered: OST has no avatars (TASK-0140), so the tab
// strip above "Camera" is left out. Picking a camera moves a running
// call's video to it at once.
Popup {
    id: root
    /// The call's camera is on (the preview is then the call's own video).
    property bool cameraOn: false
    signal moreVideoSettings()
    width: 359.3
    height: col.implicitHeight + 27.4
    padding: 0
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    property var cameras: []
    property string current: ""
    property bool previewing: false
    onOpened: {
        const d = JSON.parse(backend.videoDevices())
        cameras = d.devices || []
        current = d.current || ""
        videoEffects.load()
        // Teams previews the camera in the flyout while video is off.
        previewing = !cameraOn && cameras.length > 0 && backend.setCameraPreview(true)
    }
    onClosed: if (previewing) { previewing = false; backend.setCameraPreview(false) }

    Column {
        id: col
        x: 16.7; y: 16.7; width: 326
        Rectangle {
            width: 326; height: 180; radius: 4
            color: theme.pane
            clip: true
            VideoFrame {
                id: preview
                anchors.fill: parent
                visible: hasFrame
                source: root.opened && (root.cameraOn || root.previewing) ? "self" : ""
                radius: 4
                transform: Scale { origin.x: preview.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
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
        Item { width: 326; height: 10 }
        Text {
            width: 326; height: 16; verticalAlignment: Text.AlignVCenter
            text: "Camera"
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        Repeater {
            model: root.cameras
            Item {
                id: row
                required property var modelData
                readonly property bool chosen: root.current === modelData.path
                width: 326; height: 34.3
                FluentIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; name: row.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: row.chosen ? theme.brand : theme.textSecondary }
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
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 10 }
        Text {
            width: 326; height: 16; verticalAlignment: Text.AlignVCenter
            text: "Backgrounds"
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        Item { width: 326; height: 10 }
        Row {
            spacing: 6
            height: 50
            EffectTile {
                width: 77; height: 48
                kind: "none"; label: "None"; accessibleName: "No background effect"
                selected: videoEffects.background === "none"
                onPicked: videoEffects.setBackground("none")
            }
            EffectTile {
                width: 77; height: 48
                kind: "blur"; label: videoEffects.blurLabel
                blurKind: videoEffects.blurKind
                selected: videoEffects.background === "blur"
                onPicked: videoEffects.setBackground("blur")
                onBlurPicked: kind => videoEffects.setBlur(kind)
            }
            Repeater {
                model: videoEffects.catalog.slice(0, 2)
                EffectTile {
                    required property var modelData
                    width: 77; height: 48
                    thumb: modelData.thumb; animated: modelData.animated
                    label: modelData.name; accessibleName: modelData.name + " background effect"
                    selected: videoEffects.background === modelData.id
                    onPicked: videoEffects.setBackground(modelData.id)
                }
            }
        }
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 10.6 }
        FlyoutSwitch {
            label: "Adjust brightness"
            checked: videoEffects.brightness
            onToggled: videoEffects.setBrightness(!checked)
        }
        FlyoutSwitch {
            label: "Soft focus"
            checked: videoEffects.softFocus
            onToggled: videoEffects.setSoftFocus(!checked)
        }
        Item { width: 326; height: 10 }
        Rectangle { width: 326; height: 1 / Screen.devicePixelRatio; color: theme.divider }
        Item { width: 326; height: 8.7 }
        Item {
            width: 326; height: 32
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

    // A 14 px #424242 label and a Fluent switch (40 x 20 indicator at the
    // row's end): on, brand with a white thumb; off, a #616161 outline.
    component FlyoutSwitch: Item {
        id: fs
        property string label
        property bool checked: false
        signal toggled()
        width: 326; height: 36
        Text {
            y: 8.7; height: 18.7; verticalAlignment: Text.AlignVCenter
            text: fs.label
            font.family: theme.font; font.pixelSize: 14
            color: theme.textStrong
        }
        Rectangle {
            x: 286; y: 8; width: 40; height: 20; radius: 10
            color: fs.checked ? (swHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
            border.color: fs.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (fs.checked ? 20.67 : 0.67) + 9 - 7.2
                color: fs.checked ? "white" : theme.textSecondary
            }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: fs.toggled() }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: fs.label
        Accessible.checked: fs.checked
        Accessible.onToggleAction: fs.toggled()
    }
}
