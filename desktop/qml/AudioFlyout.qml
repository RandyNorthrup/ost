import QtQuick
import QtQuick.Controls

// Teams' in-call audio options (audio-button-configure-popover, measured on
// winpc), opened from the Mic chevron: "Speaker" with the output devices as
// radios and the volume slider, a divider, then "Microphone" with the input
// devices and the level meter. 315.3 wide, padding 16, scrolling within the
// window. Picking a device moves the call to it at once.
Popup {
    id: root
    property bool muted: false
    signal toggleMute()
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
    onOpened: {
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
            Rectangle { width: 268; height: 0.67; color: theme.divider }
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
