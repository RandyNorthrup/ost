import QtQuick

// Teams' Device settings pane as the test call results show it (Show
// Device Settings; calling-right-side-panel "Device settings", measured on
// winpc 2026-11-16): a 58 tall header with "Device settings" (16/700),
// then "Audio Settings" (14/600): Speaker and Microphone (12 px labels
// over 308 x 30 dropdowns), Noise suppression with its switch and the
// Background noise only / Voice isolation choice; "Video Settings":
// Camera, Mirror my video, Adjust brightness and Soft focus (rows 52
// apart). Everything 22.7 in. Teams' Spatial audio row (between
// Microphone and Noise suppression) is left out: OST can't render
// spatial audio (as in Settings ▸ Devices).
Rectangle {
    id: pane
    color: theme.pane
    implicitHeight: 714
    Accessible.role: Accessible.Pane
    Accessible.name: "Device settings"

    property var audio: ({ inputs: [], outputs: [] })
    property var cameras: []
    property string camera: ""
    property bool noise: backend.setting("noiseSuppression") !== "off"
    function reload() {
        audio = JSON.parse(backend.audioDevices())
        try { const v = JSON.parse(backend.videoDevices()); cameras = v.devices || []; camera = v.current || "" } catch (e) { cameras = [] }
    }
    onVisibleChanged: if (visible) reload()

    component Label: Text {
        x: 22.7; height: 17.1
        font.family: theme.font; font.pixelSize: 12
        color: theme.textSecondary
    }
    component Heading: Text {
        x: 22.7; height: 20
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    component SwitchLine: Item {
        id: sl
        property string label
        property bool on
        signal toggled(bool on)
        x: 22.7; width: 308.1; height: 36
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sl.label
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        SettingsParts.Toggle {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            stateLabel: false
            on: sl.on; accessibleName: sl.label
            onToggled: v => sl.toggled(v)
        }
    }

    Text {
        x: 20.7; y: 20.7
        text: "Device settings"
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    Heading { y: 86; text: "Audio Settings" }
    Label { y: 122; text: "Speaker" }
    OutlineDropdown {
        x: 22.7; y: 144.1; width: 308.1; height: 30
        readonly property var values: ["default"].concat(pane.audio.outputs)
        options: values.map(v => ({ label: v === "default" ? (pane.audio.defaultOutput || "Default") : v }))
        current: Math.max(0, values.indexOf(backend.setting("speakerDevice") || "default"))
        accessibleName: "Speaker"
        onPicked: i => backend.setSetting("speakerDevice", values[i])
    }
    Label { y: 190.1; text: "Microphone" }
    OutlineDropdown {
        x: 22.7; y: 212.3; width: 308.1; height: 30
        readonly property var values: ["default"].concat(pane.audio.inputs)
        options: values.map(v => ({ label: v === "default" ? (pane.audio.defaultInput || "Default") : v }))
        current: Math.max(0, values.indexOf(backend.setting("micDevice") || "default"))
        accessibleName: "Microphone"
        onPicked: i => backend.setSetting("micDevice", values[i])
    }
    SwitchLine {
        y: 258.3; label: "Noise suppression"; on: pane.noise
        onToggled: v => { pane.noise = v; backend.setNoiseSuppression(v) }
    }
    SettingsParts.RadioRow {
        x: 22.7; y: 294.3; width: 308.1
        label: "Background noise only"; checked: true; usable: pane.noise
    }
    SettingsParts.RadioRow {
        x: 22.7; y: 326.3; width: 308.1
        label: "Voice isolation"; checked: false; usable: false
    }

    Heading { y: 383.2; text: "Video Settings" }
    Label { y: 419.2; text: "Camera" }
    OutlineDropdown {
        x: 22.7; y: 441.3; width: 308.1; height: 30
        options: pane.cameras.map(c => ({ label: c.name }))
        current: Math.max(0, pane.cameras.findIndex(c => c.path === pane.camera))
        accessibleName: "Camera"
        onPicked: i => { const c = pane.cameras[i]; if (c) { pane.camera = c.path; backend.setCameraDevice(c.path) } }
    }
    SwitchLine { y: 487.3; label: "Mirror my video"; on: videoEffects.mirror; onToggled: v => videoEffects.setMirror(v) }
    SwitchLine { y: 539.3; label: "Adjust brightness"; on: videoEffects.brightness; onToggled: v => videoEffects.setBrightness(v) }
    SwitchLine { y: 590.3; label: "Soft focus"; on: videoEffects.softFocus; onToggled: v => videoEffects.setSoftFocus(v) }
}
