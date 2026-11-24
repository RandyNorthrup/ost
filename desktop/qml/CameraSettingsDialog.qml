import QtQuick
import QtQuick.Controls

// OST's camera settings: Teams' "Open camera settings" (Settings ▸ Devices
// ▸ Video settings, with "Automatically adjust camera controls" off) opens
// the camera's own settings (its driver's property page, or Windows'
// camera settings); on Linux those are the camera's V4L2 controls, listed
// here as the camera offers them (Backend camera_controls_json): picture
// (brightness, contrast, hue, saturation, sharpness, gamma, white balance,
// backlight compensation, gain, power line frequency) then camera (zoom,
// focus, exposure, iris, pan, tilt). A control the camera sets itself has
// "Auto" beside it. Changes apply at once; "Restore defaults" puts the
// camera's defaults back. A Fluent dialog (radius 8, padding 24, the 20/28
// title) as Teams' Settings dialogs.
Popup {
    id: dlg
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 560
    height: Math.min(parent ? parent.height - 80 : 640, 24 + 28 + 4 + 20 + 20 + list.contentHeight + 24 + 31.3 + 24)
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string path: ""
    property string cameraName: ""
    property var controls: []
    function reload() { controls = JSON.parse(backend.cameraControlsJson(path) || "[]") }
    function show(p, name) { path = p; cameraName = name; reload(); open() }
    function controlsForTest() { return controls }

    Text {
        id: titleText
        x: 24; y: 24; width: dlg.width - 48; height: 28
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Camera settings")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Text {
        id: nameText
        x: 24; y: titleText.y + titleText.height + 4; width: dlg.width - 48; height: 20
        text: dlg.cameraName
        elide: Text.ElideRight
        font.family: theme.font; font.pixelSize: 14
        color: theme.textSecondary
    }
    ListView {
        id: list
        x: 24; y: nameText.y + nameText.height + 20
        width: dlg.width - 48
        height: dlg.height - y - 24 - 31.3 - 24
        clip: true
        spacing: 16
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        model: dlg.controls
        Text {
            visible: dlg.controls.length === 0
            width: parent.width
            text: qsTr("This camera has no settings to change.")
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14
            color: theme.textSecondary
        }
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool manual: !modelData.auto
            width: list.width - 12
            height: 20 + 8 + (modelData.kind === "int" ? 22 : modelData.kind === "menu" ? 30 : 20)
            Text {
                width: parent.width - (autoBox.visible ? autoBox.width + 12 : 0) - 60
                text: row.modelData.name
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: row.modelData.inactive && row.modelData.kind !== "bool" ? theme.textSecondary : theme.text
            }
            Text {
                visible: row.modelData.kind === "int"
                anchors.right: autoBox.visible ? autoBox.left : parent.right
                anchors.rightMargin: autoBox.visible ? 16 : 0
                text: String(Math.round(slider.value))
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
            // "Auto": the camera sets this itself.
            Row {
                id: autoBox
                visible: row.modelData.autoId !== null && row.modelData.autoId !== undefined
                anchors.right: parent.right
                spacing: 8
                SettingsParts.Box { y: 2; checked: !!row.modelData.auto; hovered: autoHover.hovered }
                Text { text: qsTr("Auto"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                HoverHandler { id: autoHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        backend.setCameraControl(dlg.path, row.modelData.autoId, row.modelData.auto ? 0 : 1)
                        dlg.reload()
                    }
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Auto %1").arg(row.modelData.name)
                Accessible.checked: !!row.modelData.auto
            }
            Slider {
                id: slider
                visible: row.modelData.kind === "int"
                y: 28; width: parent.width; height: 22
                from: row.modelData.min; to: row.modelData.max
                stepSize: Math.max(1, row.modelData.step)
                snapMode: Slider.SnapAlways
                value: row.modelData.value
                enabled: row.manual && !row.modelData.inactive
                leftPadding: 10; rightPadding: 10
                onMoved: backend.setCameraControl(dlg.path, row.modelData.id, Math.round(value))
                onPressedChanged: if (!pressed) dlg.reload()
                background: Item {
                    x: slider.leftPadding; y: (slider.height - 4) / 2
                    width: slider.availableWidth; height: 4
                    Rectangle { anchors.fill: parent; radius: 2; color: slider.enabled ? theme.pick("#616161", "#ADADAD", "#FFFFFF") : theme.pick("#E0E0E0", "#424242", "#3FF23F") }
                    Rectangle { width: slider.visualPosition * parent.width; height: 4; radius: 2; color: slider.enabled ? theme.brandFill : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * slider.availableWidth - 10
                    y: (slider.height - 20) / 2
                    width: 20; height: 20; radius: 10
                    color: theme.surface
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: slider.enabled ? theme.brandFill : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
                }
                Accessible.name: row.modelData.name
            }
            SettingsParts.Toggle {
                visible: row.modelData.kind === "bool"
                y: 28
                on: row.modelData.value !== 0
                accessibleName: row.modelData.name
                onToggled: v => { backend.setCameraControl(dlg.path, row.modelData.id, v ? 1 : 0); dlg.reload() }
            }
            OutlineDropdown {
                visible: row.modelData.kind === "menu"
                y: 28; width: 260; height: 30
                options: (row.modelData.items || []).map(i => ({ label: i[1] }))
                current: Math.max(0, (row.modelData.items || []).findIndex(i => i[0] === row.modelData.value))
                accessibleName: row.modelData.name
                onPicked: i => { backend.setCameraControl(dlg.path, row.modelData.id, row.modelData.items[i][0]); dlg.reload() }
            }
        }
    }
    Row {
        x: dlg.width - 24 - width; y: dlg.height - 24 - 31.3; spacing: 8
        SettingsParts.Button { label: qsTr("Restore defaults"); onClicked: { backend.resetCameraControls(dlg.path); dlg.reload() } }
        SettingsParts.Button { label: qsTr("Close"); primary: true; onClicked: dlg.close() }
    }
}
