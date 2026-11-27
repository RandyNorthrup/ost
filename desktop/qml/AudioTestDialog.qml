import QtQuick
import QtQuick.Controls.Basic

// Teams' "Test mic and speaker" (its audio test wizard, TestAudioWizard,
// read in Teams' calling code 2026-11-27): a Fluent dialog (600 wide,
// radius 8, no padding) of three steps.
// - Speaker: Teams' test sound loops on the chosen speaker; "Do you hear
//   the test sound?" over the speaker picker and the volume slider. "Yes,
//   I can hear it" goes on to the microphone; "No, try next speaker" marks
//   it not working and picks the next untested one ("No, I can't hear it"
//   on the last); once all are tested, "Test speakers again" and "Test
//   microphone".
// - Microphone: what you say plays back once you pause ("Speak and pause.
//   Do you hear the playback?", after "Getting your microphone ready…"),
//   the microphone picker and the level meter; Back, the same choices for
//   mics, then "Finish test".
// - Summary: "Your audio is ready for the meeting" or "There was a problem
//   with your audio", each device's result; Restart test (after a
//   problem) and Done.
// Each step is headed by Teams' picture for it (140 high on
// NeutralBackground3, its working or not-working version per theme); the
// close button sits 20 from the top and the end. Cards are padded 24 (no
// bottom), titles 20/28 semibold 12 above their content, the pickers 40
// tall, the nav bar 12 24 24 24 with the actions at the end, 8 apart.
Popup {
    id: root
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    width: 600
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    /// "speaker", "mic" or "summary".
    property string page: "speaker"
    property var devices: ({ inputs: [], outputs: [] })
    property string speaker: ""
    property string mic: ""
    /// Tested devices: name → true (working) / false (not working).
    property var testedSpeakers: ({})
    property var testedMics: ({})
    readonly property var state_: backend.audioTestJson ? JSON.parse(backend.audioTestJson) : ({})
    readonly property bool toneError: state_.tone === "error"
    readonly property bool monitorReady: state_.monitor === "ready"
    /// The microphone (or the speaker for its playback) couldn't be opened:
    /// no longer loading; another microphone can be tried.
    readonly property bool monitorFailed: state_.monitor === "error"
    /// The microphone step before the microphone is ready: Teams shows only
    /// its picture and a progress bar (no title, picker or buttons).
    readonly property bool micLoading: page === "mic" && !monitorReady && !monitorFailed && micLeft !== "error"
    property int level: 0

    function start() {
        devices = JSON.parse(backend.audioDevices())
        speaker = chosen("speakerDevice", devices.outputs || [], devices.defaultOutput)
        mic = chosen("micDevice", devices.inputs || [], devices.defaultInput)
        testedSpeakers = ({}); testedMics = ({})
        page = "speaker"
        open()
        backend.audioTestTone(true)
    }
    function chosen(setting, list, dflt) {
        const v = backend.setting(setting)
        if (v && v !== "default" && list.indexOf(v) >= 0) return v
        if (dflt && list.indexOf(dflt) >= 0) return dflt
        return list.length ? list[0] : ""
    }
    onClosed: { backend.audioTestTone(false); backend.audioTestMonitor(false) }
    onPageChanged: {
        if (!opened) return
        backend.audioTestTone(page === "speaker")
        backend.audioTestMonitor(page === "mic")
    }
    Timer { running: root.opened && root.page === "mic"; interval: 100; repeat: true; onTriggered: root.level = backend.micLevel() }

    // Teams' remaining-devices state (aN): no devices, the last untested
    // one, none untested, or more.
    function remaining(list, tested) {
        if (!list || list.length === 0) return "error"
        const left = list.filter(d => tested[d] === undefined).length
        return left === 1 ? "last" : left === 0 ? "none" : "available"
    }
    readonly property string speakerLeft: remaining(devices.outputs, testedSpeakers)
    readonly property string micLeft: remaining(devices.inputs, testedMics)
    // A step "works" (Teams' q4): devices are left to try, or the chosen
    // one was heard.
    readonly property bool speakerUsable: speakerLeft === "available" || speakerLeft === "last" || testedSpeakers[speaker] === true
    readonly property bool micUsable: micLeft === "available" || micLeft === "last" || testedMics[mic] === true
    // Each device's result (Teams' exception): heard, not heard, untested.
    function result(kind) {
        const list = kind === "speaker" ? devices.outputs || [] : devices.inputs || []
        if (list.length === 0) return "none"
        if (kind === "speaker" && toneError) return "untested"
        const t = (kind === "speaker" ? testedSpeakers : testedMics)[kind === "speaker" ? speaker : mic]
        return t === true ? "ok" : t === false ? "failed" : "untested"
    }
    readonly property bool allGood: result("speaker") === "ok" && result("mic") === "ok"

    function mark(kind, ok) {
        const key = kind === "speaker" ? "testedSpeakers" : "testedMics"
        const cur = kind === "speaker" ? speaker : mic
        const t = Object.assign({}, root[key]); t[cur] = ok; root[key] = t
        if (ok) return
        // Teams: on to the next untested device after this one (round the
        // list, past any already tested).
        const list = kind === "speaker" ? devices.outputs : devices.inputs
        const at = list.indexOf(cur)
        for (let i = 1; i < list.length; i++) {
            const next = list[(at + i) % list.length]
            if (t[next] === undefined) { pick(kind, next); return }
        }
    }
    function pick(kind, name) {
        if (kind === "speaker") {
            speaker = name
            backend.setSetting("speakerDevice", name)
            if (page === "speaker") backend.audioTestTone(true)
            contentItem.Accessible.announce(qsTr("Selected speaker %1").arg(name))
        } else {
            mic = name
            backend.setSetting("micDevice", name)
            if (page === "mic") backend.audioTestMonitor(true)
            contentItem.Accessible.announce(qsTr("Selected microphone %1").arg(name))
        }
    }
    function resetTested(kind) { if (kind === "speaker") testedSpeakers = ({}); else testedMics = ({}) }

    // The two buttons (Teams' nN, Action and Proceed) for the page.
    readonly property var actionButton: {
        if (page === "summary") return allGood ? null : { text: qsTr("Restart test"), run: () => { resetTested("speaker"); resetTested("mic"); page = "speaker" } }
        const kind = page === "speaker" ? "speaker" : "mic"
        const left = kind === "speaker" ? speakerLeft : micLeft
        if (kind === "speaker" && toneError) return null
        if (left === "error") return { text: kind === "speaker" ? qsTr("Test speakers again") : qsTr("Test mics again"), disabled: true, run: () => {} }
        if (left === "available") return { text: kind === "speaker" ? qsTr("No, try next speaker") : qsTr("No, try next mic"), run: () => mark(kind, false) }
        if (left === "last") return { text: qsTr("No, I can't hear it"), run: () => mark(kind, false) }
        return { text: kind === "speaker" ? qsTr("Test speakers again") : qsTr("Test mics again"), run: () => resetTested(kind) }
    }
    readonly property var proceedButton: {
        if (page === "summary") return { text: qsTr("Done"), run: () => close() }
        const kind = page === "speaker" ? "speaker" : "mic"
        const left = kind === "speaker" ? speakerLeft : micLeft
        const go = () => { page = kind === "speaker" ? "mic" : "summary" }
        if ((kind === "speaker" && toneError) || (left !== "available" && left !== "last"))
            return { text: kind === "speaker" ? qsTr("Test microphone") : qsTr("Finish test"), run: go }
        return { text: qsTr("Yes, I can hear it"), run: () => { mark(kind, true); go() } }
    }

    // Teams' pictures for each step, working or not, per theme.
    function picture(step, ok) {
        const t = theme.highContrast ? "hc" : theme.dark ? "dark" : "light"
        const base = "../assets/illustrations/audio-test-"
        if (step === "speaker") return base + (ok ? "speaker-ok-" + t : "speaker-fail" + (t === "hc" ? "-hc" : "")) + ".svg"
        if (step === "mic") return base + (ok ? "mic-ok-" + t : "mic-fail" + (t === "hc" ? "-hc" : "")) + ".svg"
        return base + "summary-" + (ok ? "ok-" : "fail-") + t + ".svg"
    }

    contentItem: Column {
        width: root.width
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Test Speakers and Microphones")
        Rectangle {
            width: root.width; height: 140
            topLeftRadius: 8; topRightRadius: 8
            color: theme.pick("#F5F5F5", "#141414", "#000000")
            Image {
                anchors.centerIn: parent
                width: 140; height: 140; sourceSize: Qt.size(280, 280)
                source: root.picture(root.page, root.page === "speaker" ? root.speakerUsable : root.page === "mic" ? root.micUsable : root.allGood)
                Accessible.role: Accessible.Graphic
                Accessible.name: root.page === "speaker" ? qsTr("Speaker card image") : root.page === "mic" ? qsTr("Microphone card image") : qsTr("Summary card image")
            }
            // Close (20 from the top and the end).
            Rectangle {
                x: root.width - 20 - 32; y: 20; width: 32; height: 32; radius: 4
                color: closeHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
            }
        }
        // The step (Teams' carousel slide: at least 310 tall with its
        // picture, measured on testpc1 2026-11-27).
        Item {
            width: root.width
            height: Math.max(310 - 140, root.micLoading ? 0 : card.implicitHeight)
            // Getting your microphone ready: Teams' progress bar, the
            // dialog's width right under the picture (4 tall, #E6E6E6 track).
            Item {
                visible: root.micLoading
                width: parent.width; height: 4
                clip: true
                Rectangle { anchors.fill: parent; color: theme.pick("#E6E6E6", "#3D3D3D", "#FFFFFF") }
                Rectangle {
                    id: bar; height: 4; width: parent.width * 0.33; radius: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: theme.brand }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    SequentialAnimation on x { running: bar.parent.visible; loops: Animation.Infinite
                        NumberAnimation { from: -bar.width; to: bar.parent.width; duration: 1500 } }
                }
                Accessible.role: Accessible.ProgressBar
                Accessible.name: qsTr("Getting your microphone ready…")
            }
        // The step's card (24 in, 24 down).
        Column {
            id: card
            visible: !root.micLoading
            x: 24; width: root.width - 48
            topPadding: 24
            Text {
                width: parent.width; height: 28 + 12
                verticalAlignment: Text.AlignTop; topPadding: 0
                wrapMode: Text.Wrap
                text: root.page === "speaker"
                      ? (root.speakerLeft === "error" ? qsTr("No speakers could be found")
                         : root.speakerUsable ? qsTr("Do you hear the test sound?") : qsTr("All of your speakers have been tested"))
                      : root.page === "mic"
                      ? (root.micLeft === "error" ? qsTr("No microphones could be found")
                         : root.micUsable ? qsTr("Speak and pause. Do you hear the playback?") : qsTr("All of your microphones have been tested"))
                      : root.allGood ? qsTr("Your audio is ready for the meeting") : qsTr("There was a problem with your audio")
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            // The device picker (40 tall), 6 above what follows.
            OutlineDropdown {
                visible: root.page !== "summary"
                width: parent.width; height: 40
                readonly property var list: root.page === "speaker" ? root.devices.outputs || [] : root.devices.inputs || []
                options: list.length ? list.map(n => ({ label: n })) : [{ label: root.page === "speaker" ? qsTr("No speakers are available") : qsTr("No microphones are available"), disabled: true }]
                current: Math.max(0, list.indexOf(root.page === "speaker" ? root.speaker : root.mic))
                enabled: list.length > 0
                accessibleName: root.page === "speaker" ? qsTr("Choose your preferred speaker") : qsTr("Choose your preferred microphone")
                onPicked: i => root.pick(root.page === "speaker" ? "speaker" : "mic", list[i])
            }
            Item { visible: root.page !== "summary"; width: 1; height: 6 }
            // Speaker: the volume (23 in, 9 from the end, 40 tall).
            Item {
                id: volumeRow
                visible: root.page === "speaker" && root.speakerUsable && root.speakerLeft !== "error" && !root.toneError
                // (6 above, as the picker's: Teams' slider, no glyph, the
                // card's width, measured on testpc1.)
                width: parent.width; height: visible ? 46 : 0
                property int volume: backend.speakerVolume()
                Item {
                    id: vol
                    x: 0; y: 6 + 8; width: parent.width; height: 24
                    readonly property real span: width - 10
                    Rectangle { x: 5; y: 11; width: vol.span; height: 2; radius: 8; color: theme.textSecondary }
                    Rectangle { x: 5; y: 11; width: vol.span * volumeRow.volume / 100; height: 2; radius: 8; color: theme.brand }
                    Rectangle { x: vol.span * volumeRow.volume / 100; y: 7; width: 10; height: 10; radius: 5; color: theme.brand }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setFrom(mx) { volumeRow.volume = Math.round(Math.max(0, Math.min(1, (mx - 5) / vol.span)) * 100); backend.setSpeakerVolume(volumeRow.volume) }
                        onPressed: m => setFrom(m.x)
                        onPositionChanged: m => { if (pressed) setFrom(m.x) }
                    }
                    Accessible.role: Accessible.Slider
                    Accessible.name: qsTr("Speaker Volume control")
                }
            }
            // Microphone: the level meter (40 tall, centred).
            Item {
                visible: root.page === "mic" && root.monitorReady && root.micUsable
                width: parent.width; height: visible ? 46 : 0
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 6 + 12
                    spacing: 8.2
                    Repeater {
                        model: 17
                        Rectangle {
                            required property int index
                            width: 6; height: 16; radius: 3
                            color: (index + 1) / 17 <= root.level / 100 ? theme.brand : theme.stroke
                        }
                    }
                }
            }
            // The step's note (14 px, 12 above).
            Text {
                readonly property string note: root.page === "speaker"
                    ? (root.toneError ? qsTr("Oops! We ran into an issue playing the audio sample. Please try again later.")
                       : root.speakerLeft === "error" ? qsTr("Make sure you have speakers connected to your computer.")
                       : !root.speakerUsable ? qsTr("Try testing them again, or test your microphone.") : "")
                    : root.page === "mic"
                    ? (root.micLeft === "error" || root.monitorFailed ? qsTr("Make sure you have a microphone connected to your computer.")
                       : !root.micUsable ? qsTr("Try testing them again.") : "")
                    : ""
                visible: note !== ""
                width: parent.width; topPadding: 12
                wrapMode: Text.Wrap
                text: note
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            // Summary: each device's result (the icon 8 before it).
            Repeater {
                model: root.page === "summary" ? ["speaker", "mic"] : []
                Row {
                    id: res
                    required property string modelData
                    readonly property string r: root.result(modelData)
                    readonly property bool failed: r !== "ok"
                    readonly property string name: modelData === "speaker" ? root.speaker : root.mic
                    spacing: 8
                    bottomPadding: 8
                    FluentIcon {
                        name: res.failed ? "error-circle-20-filled" : "checkmark-circle-20-filled"; size: 20
                        color: res.failed ? theme.pick("#BC2F32", "#E37D80", "#FFFF00") : theme.pick("#0E700E", "#54B054", "#3FF23F")
                        Accessible.role: Accessible.Graphic
                        Accessible.name: res.failed ? qsTr("Error") : qsTr("Success")
                    }
                    Column {
                        width: root.width - 48 - 28
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: res.failed ? (res.modelData === "speaker" ? qsTr("Speaker") : qsTr("Microphone"))
                                  : res.modelData === "speaker" ? qsTr("Speaker: %1").arg(res.name) : qsTr("Microphone: %1").arg(res.name)
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.textSecondary
                        }
                        Text {
                            readonly property string why: res.r === "none" ? (res.modelData === "speaker" ? qsTr("No speakers could be found.") : qsTr("No microphones could be found."))
                                : res.r === "failed" ? (res.modelData === "speaker" ? qsTr("You couldn't hear playback from any of your connected speakers.") : qsTr("You couldn't hear playback from any of your connected mics."))
                                : res.r === "untested" ? qsTr("You haven't tested your selected device.")
                                : !root.allGood ? (res.modelData === "speaker" ? qsTr("Your speaker is working correctly.") : qsTr("Your microphone is working correctly.")) : ""
                            visible: why !== ""
                            width: parent.width; wrapMode: Text.Wrap
                            text: why
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.textSecondary
                        }
                    }
                }
            }
        }
        }
        // The nav bar: 12 24 24 24; Back (the microphone step) at the
        // start, the action and proceed buttons at the end, 8 apart
        // (hidden while the microphone gets ready, as Teams').
        Item {
            // (Empty while loading: Teams' dialog is then 352 tall.)
            width: root.width; height: root.micLoading ? 352 - 310 : 12 + 32 + 24
            NavButton {
                visible: root.page === "mic" && !root.micLoading
                x: 24; y: 12
                text: qsTr("Back")
                onClicked: root.page = "speaker"
            }
            Row {
                visible: !root.micLoading
                anchors.right: parent.right; anchors.rightMargin: 24; y: 12
                spacing: 8
                NavButton {
                    visible: !!root.actionButton
                    text: root.actionButton ? root.actionButton.text : ""
                    enabled: !!root.actionButton && !root.actionButton.disabled
                    onClicked: root.actionButton.run()
                }
                NavButton {
                    primary: true
                    text: root.proceedButton.text
                    onClicked: root.proceedButton.run()
                }
            }
        }
    }
    // Fluent's medium button: 32 tall, at least 96 wide, 14/600; primary in
    // brand.
    component NavButton: Rectangle {
        id: nb
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, nbText.implicitWidth + 24); height: 32; radius: 4
        color: !enabled ? theme.pick("#F0F0F0", "#141414", "#000000")
               : primary ? (nbHover.hovered ? theme.brandHover : theme.brandFill)
               : nbHover.hovered ? theme.menuHover : theme.surface
        border.width: primary ? 0 : 0.67
        border.color: theme.stroke
        Text {
            id: nbText
            anchors.centerIn: parent
            text: nb.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !nb.enabled ? theme.disabled : nb.primary ? "white" : theme.text
        }
        HoverHandler { id: nbHover; enabled: nb.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: nb.enabled; onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: nb.text
    }
}
