import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' Audio settings pane (More ▸ Audio settings, "More audio
// settings" in Mic ▾; audio-settings-panel, measured in Teams on winpc,
// 2026-11-08): the 360-wide side pane, #F5F5F5, with Fluent accordion
// sections (32 px headers, a 16 px caret 4.67 in, 12 px titles 20.67 in):
// - Speaker: the output devices as radios (rows of their text + 10, the
//   20 px radio 2 px left of the column, names 26 in), then the speaker
//   button and the volume slider.
// - Microphone: the input devices, then the mic button and Teams' 17-bar
//   level meter.
// - Advanced settings: Noise suppression (and, with music mode, its
//   switch shows off), High fidelity music mode with "Recommended for
//   studio environment." and its two checkboxes.
// Teams leaves out Spatial audio where the media stack can't render it
// (isSpatialAudioAvailable) and the Background noise only / Voice
// isolation choice where voice isolation isn't supported (it needs
// Microsoft's voice profile); Noise suppression then carries the info
// button. OST is both, so it shows them the same way.
// Each section's content sits 20.67 in, 305.33 wide.
Rectangle {
    id: root
    property bool muted: false
    signal toggleMute()
    signal closed()
    color: theme.pane

    property var devices: ({ inputs: [], outputs: [] })
    property string mic: ""
    property string speaker: ""
    property int volume: 100
    property int level: 0
    property bool noiseSuppression: true
    property bool musicMode: false
    property bool musicInFlyout: false
    property bool musicEcho: true
    property var expanded: ({ speaker: true, microphone: true, advanced: true })

    function reload() {
        devices = JSON.parse(backend.audioDevices())
        mic = backend.setting("micDevice") || ""
        speaker = backend.setting("speakerDevice") || ""
        volume = backend.speakerVolume()
        noiseSuppression = backend.setting("noiseSuppression") !== "off"
        musicMode = backend.setting("musicMode") === "on"
        musicInFlyout = backend.setting("musicModeInFlyout") === "on"
        musicEcho = backend.setting("musicModeEcho") !== "off"
    }
    onVisibleChanged: if (visible) { reload(); flick.contentY = 0 }
    function scrollToEndForTest() { flick.contentY = Math.max(0, flick.contentHeight - flick.height) }
    Timer { running: root.visible; interval: 100; repeat: true; onTriggered: root.level = root.muted ? 0 : backend.micLevel() }

    // Teams: turning music mode on turns noise suppression off, and
    // turning it off brings back what noise suppression was.
    function setMusic(on) {
        if (on === musicMode) return
        if (on) { backend.setSetting("noiseSuppressionBeforeMusic", noiseSuppression ? "on" : "off"); setNoise(false) }
        musicMode = on
        backend.setMusicMode(on, musicEcho)
        if (!on) setNoise(backend.setting("noiseSuppressionBeforeMusic") !== "off")
    }
    function setNoise(on) {
        noiseSuppression = on
        backend.setNoiseSuppression(on)
    }

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 16.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Audio settings"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Close audio pane"
            Accessible.role: Accessible.Button
            Accessible.name: "Close audio pane"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: col.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            width: 326

            Banner {
                visible: (root.devices.outputs || []).length === 0
                text: "Couldn't find a speaker. Connect one, or make sure the driver for an existing device is properly installed."
            }
            Banner {
                visible: (root.devices.inputs || []).length === 0
                text: "No microphone was found, plug one in or enjoy just listening in."
            }

            SectionHeader { key: "speaker"; title: "Speaker" }
            Column {
                visible: root.expanded.speaker
                x: 20.67; width: 305.33
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
                // Volume: the speaker button 6 px left of the column, then
                // the slider (track from 27 to the column's end).
                Item {
                    width: 305.33; height: 31.33
                    Rectangle {
                        x: -6; width: 32; height: 31.33; radius: 4
                        color: spkHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "flyout-speaker-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: spkHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.volume = root.volume > 0 ? 0 : 100; backend.setSpeakerVolume(root.volume) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: root.volume > 0 ? "Mute speaker" : "Unmute speaker"
                    }
                    Item {
                        id: slider
                        x: 19; width: 286.33; height: 24; y: 3.67
                        readonly property real trackX: 8
                        readonly property real trackW: width - 16
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
                Item { width: 1; height: 16 }
            }

            SectionHeader { key: "microphone"; title: "Microphone" }
            Column {
                visible: root.expanded.microphone
                x: 20.67; width: 305.33
                Repeater {
                    model: root.devices.inputs || []
                    DeviceRow {
                        required property var modelData
                        name: modelData
                        chosen: (root.mic || root.devices.defaultInput || "") === modelData
                        onPicked: { root.mic = modelData; backend.setSetting("micDevice", modelData) }
                    }
                }
                // The mic button (mute) and Teams' 17-bar meter across the
                // column.
                Item {
                    width: 305.33; height: 31.33
                    Rectangle {
                        width: 32; height: 31.33; radius: 4
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
                            x: 35 + index * (305.33 - 41) / 16; anchors.verticalCenter: parent.verticalCenter
                            width: 6; height: 16; radius: 3
                            color: (index + 1) / 17 <= root.level / 100 ? theme.brand : theme.stroke
                        }
                    }
                }
                Item { width: 1; height: 16 }
            }

            SectionHeader { key: "advanced"; title: "Advanced settings" }
            Column {
                visible: root.expanded.advanced
                x: 20.67; width: 305.33
                // Noise suppression: its label with the info button, the
                // switch at the end (36 px row).
                SwitchRow {
                    label: "Noise suppression"
                    info: "Enable this to enhance your microphone audio quality by removing background noise. <a href=\"https://aka.ms/noisesuppression\">Learn more</a>"
                    checked: root.noiseSuppression
                    onToggled: root.setNoise(!root.noiseSuppression)
                }
                SwitchRow {
                    label: "High fidelity music mode"
                    info: "Recommended for when you play music in meetings. If enabled, this enhances the experience for the participants when they listen to shared music. <a href=\"https://go.microsoft.com/fwlink/?linkid=2168036\">Learn more</a>"
                    checked: root.musicMode
                    height: 30
                    onToggled: root.setMusic(!root.musicMode)
                }
                Text {
                    width: 305.33; height: 16
                    text: "Recommended for studio environment."
                    font.family: theme.font; font.pixelSize: 12
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    color: theme.textStrong
                }
                CheckRow {
                    label: "Display in the microphone dropdown menu"
                    checked: root.musicInFlyout
                    enabled: root.musicMode
                    onToggled: { root.musicInFlyout = !root.musicInFlyout; backend.setSetting("musicModeInFlyout", root.musicInFlyout ? "on" : "off") }
                }
                CheckRow {
                    label: "Enable echo cancellation"
                    checked: root.musicEcho
                    enabled: root.musicMode
                    onToggled: { root.musicEcho = !root.musicEcho; backend.setMusicMode(root.musicMode, root.musicEcho) }
                }
            }
        }
    }

    // A Fluent accordion header: 32 tall, the caret (down when open) 4.67
    // in and the 12 px title 20.67 in.
    component SectionHeader: Item {
        id: sh
        property string key
        property string title
        readonly property bool open: !!root.expanded[key]
        width: 326; height: 32
        FluentIcon {
            x: 4.67; y: 8; name: "accordion-caret"; size: 16; color: theme.text
            rotation: sh.open ? 0 : -90
        }
        Text {
            x: 20.67; anchors.verticalCenter: parent.verticalCenter
            text: sh.title
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                const e = Object.assign({}, root.expanded)
                e[sh.key] = !sh.open
                root.expanded = e
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: sh.title
        Accessible.checkable: true
        Accessible.checked: sh.open
    }

    // One device: Teams' radio (20 px, brand when chosen, #616161 not) and
    // its name wrapping 26 in, 5 px down; rows are the text plus 10.
    component DeviceRow: Item {
        id: dr
        property string name
        property bool chosen: false
        signal picked()
        width: 305.33; height: Math.max(24.33, label.contentHeight) + 10
        FluentIcon { x: -2; y: 6; name: dr.chosen ? "radio-on-20" : "radio-off-20"; size: 20; color: dr.chosen ? theme.brand : theme.textSecondary }
        Text {
            id: label
            x: 26; y: 5; width: 271.33
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

    // A label (with Fluent's 24 px info button after it) and a Fluent
    // switch: its 40 x 20 indicator ends at the column's edge; on, brand
    // with a white thumb; off, a #616161 outline and thumb.
    component SwitchRow: Item {
        id: sr
        property string label
        property string info: ""
        property bool checked: false
        signal toggled()
        width: 305.33; height: 36
        Row {
            y: 9
            Text {
                id: srLabel
                height: 18.67
                verticalAlignment: Text.AlignVCenter
                text: sr.label
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            InfoButton { y: -2.67; visible: sr.info.length > 0; info: sr.info }
        }
        Rectangle {
            x: 265.33; y: 8; width: 40; height: 20; radius: 10
            color: sr.checked ? (swHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
            border.color: sr.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (sr.checked ? 20.67 : 0.67) + 9 - 7.2
                color: sr.checked ? "white" : theme.textSecondary
            }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sr.toggled() }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: sr.label
        Accessible.checked: sr.checked
        Accessible.onToggleAction: sr.toggled()
    }

    // Fluent's checkbox row (32 tall, starting 7 left of the column): the
    // 16 px box 8 in with a 12 px check, the 12 px label after it. Disabled
    // (music mode off): #E0E0E0 box, #BDBDBD check and text.
    component CheckRow: Item {
        id: cr
        property string label
        property bool checked: false
        signal toggled()
        width: 305.33; height: 32
        Rectangle {
            x: 1; y: 8; width: 16; height: 16; radius: 2
            color: cr.checked && cr.enabled ? theme.brandFill : "transparent"
            border.width: cr.checked && cr.enabled ? 0 : 0.67
            border.color: cr.enabled ? theme.textSecondary : theme.divider
            FluentIcon {
                visible: cr.checked
                anchors.centerIn: parent; name: "checkmark-12"; size: 12
                color: cr.enabled ? "white" : theme.disabled
            }
        }
        Text {
            x: 29; anchors.verticalCenter: parent.verticalCenter
            text: cr.label
            font.family: theme.font; font.pixelSize: 12
            color: !cr.enabled ? theme.disabled : cr.checked ? theme.text : theme.textStrong
        }
        HoverHandler { cursorShape: cr.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: cr.enabled; onTapped: cr.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: cr.label
        Accessible.checked: cr.checked
    }

    // Fluent's InfoButton: a 24 px button with the 16 px info glyph; its
    // popover (264 wide, padding 12, 12/16 text) opens above it.
    component InfoButton: Rectangle {
        id: ib
        property string info
        width: 24; height: 24; radius: 4
        color: "transparent"
        // Regular at rest; filled and brand on hover and while open.
        FluentIcon { anchors.centerIn: parent; name: ibHover.hovered || pop.visible ? "info-16" : "info-16-regular"; size: 16; color: ibHover.hovered || pop.visible ? theme.brand : theme.textStrong }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pop.visible ? pop.close() : pop.open() }
        Accessible.role: Accessible.Button
        Accessible.name: "Information"
        Popup {
            id: pop
            parent: Overlay.overlay
            width: 264; padding: 12
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            onAboutToShow: {
                const p = ib.mapToItem(Overlay.overlay, 0, 0)
                const paneLeft = root.mapToItem(Overlay.overlay, 0, 0).x
                // Above the button, start-aligned; where that would leave
                // the pane, Teams sets it at the pane's left edge.
                x = p.x + width > paneLeft + root.width ? paneLeft + 0.67 : p.x
                y = p.y - implicitHeight - 6.24
            }
            contentItem: Text {
                text: "<style>a { color: " + theme.brandLink + "; text-decoration: none; }</style>" + ib.info
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }
    }

    // Fluent's MessageBar (info): shown when no speaker or microphone is
    // found.
    component Banner: Rectangle {
        property alias text: bannerText.text
        x: 20.67; width: 305.33; height: bannerText.implicitHeight + 16
        radius: 4
        color: theme.pane
        border.color: theme.stroke; border.width: 0.67
        Text {
            id: bannerText
            x: 12; y: 8; width: parent.width - 24
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }
}
