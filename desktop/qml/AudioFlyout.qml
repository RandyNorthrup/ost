import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' in-call audio options (audio-button-configure-popover, measured on
// winpc), opened from the Mic chevron: "Speaker" with the output devices as
// radios and the volume slider, a divider, then "Microphone" with the input
// devices and the level meter. 315.3 wide, padding 16, scrolling within the
// window. Picking a device moves the call to it at once. Then, as Teams
// shows them with working audio devices (measured in Teams in a call,
// 2026-11-08): a divider, "Noise suppression" with its switch (a 36 px row,
// the 40 x 20 switch at the right edge), a divider and "More audio
// settings". Teams' "Isolate your voice" needs Microsoft's voice profile,
// which other clients can't use, so it isn't offered.
Popup {
    id: root
    property bool muted: false
    signal toggleMute()
    signal moreAudioSettings()
    width: 315.3
    height: Math.min(col.implicitHeight + 33.3, maxHeight)
    property real maxHeight: 576
    padding: 0
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    property var devices: ({ inputs: [], outputs: [] })
    property string mic: ""
    property string speaker: ""
    property int volume: 100
    property int level: 0
    property bool noiseSuppression: true
    property bool musicMode: false
    property bool musicInFlyout: false
    onOpened: {
        musicMode = backend.setting("musicMode") === "on"
        musicInFlyout = backend.setting("musicModeInFlyout") === "on"
        noiseSuppression = backend.setting("noiseSuppression") !== "off"
        devices = JSON.parse(backend.audioDevices())
        mic = backend.setting("micDevice") || ""
        speaker = backend.setting("speakerDevice") || ""
        volume = backend.speakerVolume()
        flick.contentY = 0
    }
    // The meter follows the microphone while the flyout is open.
    Timer { running: root.opened; interval: 100; repeat: true; onTriggered: root.level = root.muted ? 0 : backend.micLevel() }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 33.3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            x: 16.7; y: 16.7; width: 268

            Label12 { text: "Speaker" }
            Repeater {
                // Each speaker; with none chosen, the system's default is.
                model: root.devices.outputs || []
                DeviceRow {
                    required property var modelData
                    name: modelData
                    chosen: (root.speaker || root.devices.defaultOutput || "") === modelData
                    onPicked: { root.speaker = modelData; backend.setSetting("speakerDevice", modelData) }
                }
            }
            // Volume: the speaker button, then a 233 px track with a 16 px thumb.
            Item {
                width: 268; height: 31.3
                Rectangle {
                    x: -6; width: 32; height: 31.3; radius: 4
                    color: spkHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "flyout-speaker-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: spkHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.volume = root.volume > 0 ? 0 : 100; backend.setSpeakerVolume(root.volume) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.volume > 0 ? "Mute speaker" : "Unmute speaker"
                }
                Item {
                    id: slider
                    x: 19; width: 249; height: 24; y: 3.6
                    readonly property real trackX: 8
                    readonly property real trackW: 233
                    Rectangle { x: slider.trackX; y: 11; width: slider.trackW; height: 2; radius: 8; color: theme.textSecondary }
                    Rectangle { x: slider.trackX; y: 11; width: slider.trackW * root.volume / 100; height: 2; radius: 8; color: theme.brand }
                    Rectangle {
                        x: slider.trackX + slider.trackW * root.volume / 100 - 8; y: 4
                        width: 16; height: 16; radius: 8
                        color: theme.brand
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setFrom(mx) {
                            root.volume = Math.round(Math.max(0, Math.min(1, (mx - slider.trackX) / slider.trackW)) * 100)
                            backend.setSpeakerVolume(root.volume)
                        }
                        onPressed: m => setFrom(m.x)
                        onPositionChanged: m => { if (pressed) setFrom(m.x) }
                    }
                    Accessible.role: Accessible.Slider
                    Accessible.name: "Speaker Volume control"
                }
            }
            Item { width: 268; height: 10 }
            Rectangle { width: 268; height: 1 / Screen.devicePixelRatio; color: theme.divider }
            Item { width: 268; height: 14.7 }

            Label12 { text: "Microphone" }
            Repeater {
                model: root.devices.inputs || []
                DeviceRow {
                    required property var modelData
                    name: modelData
                    chosen: (root.mic || root.devices.defaultInput || "") === modelData
                    onPicked: { root.mic = modelData; backend.setSetting("micDevice", modelData) }
                }
            }
            // The mic button (mute) and Teams' 17-bar level meter.
            Item {
                width: 268; height: 31.3
                Rectangle {
                    width: 32; height: 31.3; radius: 4
                    color: micHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: root.muted ? "flyout-mic-off-16" : "flyout-mic-16"; size: 16; color: theme.textStrong }
                    HoverHandler { id: micHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.toggleMute() }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.muted ? "Unmute" : "Mute"
                }
                Repeater {
                    model: 17
                    Rectangle {
                        required property int index
                        x: 35 + index * 14.2; anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 16; radius: 3
                        // Lit up to the level, as Teams' scalable meter does.
                        color: (index + 1) / 17 <= root.level / 100 ? theme.brand : theme.stroke
                    }
                }
            }
            Item { width: 268; height: 10.7 }
            Rectangle { width: 268; height: 1 / Screen.devicePixelRatio; color: theme.divider }
            Item { width: 268; height: 14.7 }
            // Noise suppression (Fluent Switch with its label before it).
            Item {
                width: 268; height: 36
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Noise suppression"
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                Rectangle {
                    id: nsSwitch
                    x: 268 - 40.3; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 20; radius: 10
                    color: root.noiseSuppression ? (nsHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
                    border.color: root.noiseSuppression ? "transparent" : theme.textStrong
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.noiseSuppression ? parent.width - width - 3 : 3
                        color: root.noiseSuppression ? "white" : theme.textStrong
                    }
                }
                HoverHandler { id: nsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        root.noiseSuppression = !root.noiseSuppression
                        backend.setNoiseSuppression(root.noiseSuppression)
                    }
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Noise suppression"
                Accessible.checked: root.noiseSuppression
            }
            // High fidelity music mode, when "Display in the microphone
            // dropdown menu" is on (Teams: right after noise suppression,
            // its switch row, "Recommended for studio environment." 30
            // down, then 10 before the divider).
            Item {
                visible: root.musicInFlyout
                width: 268; height: 46
                Text {
                    y: 8.67; height: 18.67
                    verticalAlignment: Text.AlignVCenter
                    text: "High fidelity music mode"
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                Rectangle {
                    x: 268 - 40.3; y: 8; width: 40; height: 20; radius: 10
                    color: root.musicMode ? (mmHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
                    border.color: root.musicMode ? "transparent" : theme.textStrong
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.musicMode ? parent.width - width - 3 : 3
                        color: root.musicMode ? "white" : theme.textStrong
                    }
                    HoverHandler { id: mmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            // As the pane: music mode on turns noise
                            // suppression off; off brings it back.
                            const on = !root.musicMode
                            if (on) { backend.setSetting("noiseSuppressionBeforeMusic", root.noiseSuppression ? "on" : "off"); root.noiseSuppression = false; backend.setNoiseSuppression(false) }
                            root.musicMode = on
                            backend.setMusicMode(on, backend.setting("musicModeEcho") !== "off")
                            if (!on) { root.noiseSuppression = backend.setting("noiseSuppressionBeforeMusic") !== "off"; backend.setNoiseSuppression(root.noiseSuppression) }
                        }
                    }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: "High fidelity music mode"
                    Accessible.checked: root.musicMode
                }
                Text {
                    y: 30; width: 268; height: 16
                    text: "Recommended for studio environment."
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.textStrong
                }
            }
            Item { width: 268; height: root.musicInFlyout ? 10 : 5.3 }
            Rectangle { width: 268; height: 1 / Screen.devicePixelRatio; color: theme.divider }
            Item { width: 268; height: 13.3 }
            // More audio settings (a subtle button at the content's edge).
            Item {
                width: 268; height: 31
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "More audio settings"
                    font.family: theme.font; font.pixelSize: 14
                    color: masHover.hovered ? theme.text : theme.textStrong
                }
                HoverHandler { id: masHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.close(); root.moreAudioSettings() } }
                Accessible.role: Accessible.Button
                Accessible.name: "More audio settings"
            }
        }
    }

    component Label12: Text {
        width: 268; height: 16; verticalAlignment: Text.AlignVCenter
        font.family: theme.font; font.pixelSize: 12
        color: theme.text
    }
    // One device: Teams' radio (20 px, brand when chosen, #616161 not) and
    // its name wrapping at 234 px, 5 px down; rows are the text plus 10.
    component DeviceRow: Item {
        id: dr
        property string name
        property bool chosen: false
        signal picked()
        width: 268; height: Math.max(24.3, label.contentHeight) + 10
        FluentIcon { x: -2; y: 6; name: dr.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: dr.chosen ? theme.brand : theme.textSecondary }
        Text {
            id: label
            x: 26; y: 5; width: 234
            wrapMode: Text.Wrap
            text: dr.name
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: dr.chosen ? theme.text : theme.textSecondary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dr.picked() }
        Accessible.role: Accessible.RadioButton
        Accessible.name: dr.name
        Accessible.checked: dr.chosen
    }
}
