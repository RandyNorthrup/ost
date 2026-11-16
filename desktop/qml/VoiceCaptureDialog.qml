import QtQuick
import QtQuick.Controls

// Teams' voice capture (Settings ▸ Recognition ▸ Create / Update; biometric-
// enrollment `ft`/`gt`, measured on winpc 2026-11-15): 600 x 374.
// - "Create your voice profile" (16/700) and the microphone picker
//   (278.7 wide).
// - "Start voice capture and read the text below out loud." (14/700) over
//   Teams' paragraph in an outlined box (16/22, 7.5 x 40 padding).
// - Teams' level meter: 13 bars (6 x 14, 14 apart) that fill with your
//   voice; "Learning your voice..." while it is checked; Teams' error text
//   when it was refused.
// - Cancel and Start voice capture → End voice capture.
// - Then Teams' completion step.
// The recording (16 kHz mono) goes to Teams' biometric service
// (Backend::voice_capture_start/end).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600
    height: finished ? done.height : 374.2
    anchors.centerIn: Overlay.overlay
    closePolicy: phase === "learning" ? Popup.NoAutoClose : Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    property bool faceEnrolled: false
    signal startFace()

    // "idle", "listening", "learning", "error"
    property string phase: "idle"
    property string errorCode: ""
    property bool finished: false
    property int level: 0
    /// For the harness: enroll this 16 kHz mono WAV instead of recording.
    property string testWav: ""

    readonly property var mics: {
        let d = { inputs: [] }
        try { d = JSON.parse(backend.audioDevices()) } catch (e) {}
        return (d.inputs || []).filter(m => m !== "default" && m !== "communications")
    }
    property int micIndex: 0

    function show() {
        phase = "idle"; errorCode = ""; finished = false; level = 0
        const chosen = backend.setting("micDevice")
        const i = mics.indexOf(chosen)
        micIndex = i >= 0 ? i : 0
        open()
    }
    onClosed: {
        if (phase === "listening") backend.voiceCaptureCancel()
        phase = "idle"
    }

    function start() {
        errorCode = ""
        if (testWav) { phase = "listening"; return }
        if (!backend.voiceCaptureStart(mics.length ? mics[micIndex] : "")) {
            phase = "error"; errorCode = "MicrophoneInitialization"; return
        }
        phase = "listening"
    }
    function end() {
        phase = "learning"
        if (testWav) backend.voiceCaptureFile(testWav)
        else backend.voiceCaptureEnd()
    }
    Connections {
        target: backend
        enabled: root.opened
        function onVoiceCaptureResult(result) {
            if (result === "COMPLETE") { root.finished = true; root.phase = "idle"; return }
            root.errorCode = result
            root.phase = "error"
        }
    }
    Timer {
        running: root.phase === "listening"
        interval: 100; repeat: true
        onTriggered: root.level = backend.micLevel()
        onRunningChanged: if (!running) root.level = 0
    }

    // Teams' words for each failure.
    readonly property string errorText: {
        switch (errorCode) {
        case "": return ""
        case "NotEnoughWords": return "Voice enrollment failed. Please carefully read the paragraph aloud to ensure proper enrollment. Skipping or skimming may cause errors."
        case "SdsTimeout": case "SdsUnavailable": return "Error: Voice Enrollment Failed. We were unable to store your voice profile. Please try again later."
        case "SdsAccessDenied": return "Error: Voice Enrollment Failed. Your access to voice enrollment is currently restricted. Please contact your IT administrator for assistance."
        case "CTSConnectionError": return "Error: Voice Enrollment Failed. We were unable to connect to enrollment service. Please try again later."
        case "MicrophoneInitialization": return "Error: Voice Enrollment Failed. Try using a different mic, and start your voice capture again."
        default: return "Couldn’t capture your voice. Try moving to a quieter area or using a different mic, and start your voice capture again."
        }
    }

    Item {
        anchors.fill: parent
        visible: !root.finished
        Text {
            x: 32; y: 3; height: 32
            verticalAlignment: Text.AlignVCenter
            text: "Create your voice profile"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        OutlineDropdown {
            x: 32.7; y: 43.2; width: 278.7; height: 30
            enabled: root.phase !== "listening" && root.phase !== "learning"
            accessibleName: "Choose microphone"
            placeholder: root.mics.length ? "Choose microphone" : "Connect a microphone"
            options: root.mics.map(m => ({ label: m }))
            current: root.micIndex
            onPicked: i => root.micIndex = i
        }
        Text {
            x: 32; y: 105.4; height: 20
            verticalAlignment: Text.AlignVCenter
            text: "Start voice capture and read the text below out loud."
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            x: 32; y: 130.2; width: 536; height: readText.height + 15
            color: "transparent"
            border.width: 0.67; border.color: theme.textSecondary
            Text {
                id: readText
                x: 40; y: 7.5; width: parent.width - 80
                wrapMode: Text.Wrap
                text: "Hi, Teams. I’m going to speak for a moment to help you get to know my voice better. You need to hear more than just a few words to be able to accurately recognize me in meetings. If I make a mistake, that’s all right you’ll let me know if I need to read this again."
                font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
        }
        // Teams' meter: 13 bars filling left to right with your level.
        Row {
            visible: root.phase === "idle" || root.phase === "listening"
            x: 37; y: 279.9; spacing: 8
            Repeater {
                model: 13
                delegate: Rectangle {
                    required property int index
                    width: 6; height: 14; radius: 3
                    color: (index + 1) / 13 <= root.level / 100 + 0.0001 && root.level > 0 ? theme.brandFill : theme.pick("#BDBDBD", "#5C5C5C", "#000000")
                }
            }
            Accessible.role: Accessible.Indicator
            Accessible.name: root.phase === "listening" ? "Learning your voice... Please wait" : ""
        }
        Row {
            visible: root.phase === "learning"
            x: 32; y: 276.9; spacing: 8
            BusyIndicator { width: 20; height: 20; running: parent.visible }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Learning your voice..."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        }
        Row {
            visible: root.phase === "error"
            x: 32; y: 274.9; width: 536; spacing: 8
            FluentIcon { name: "error-circle-20-filled"; size: 16; color: theme.pick("#C50F1F", "#DC626D", "#FFFFFF") }
            Text {
                width: 512
                text: root.errorText
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.pick("#C50F1F", "#DC626D", "#FFFFFF")
            }
        }
        Row {
            x: 600 - 47 - width; y: 312.9; spacing: 15
            SettingsParts.Button {
                enabled: root.phase !== "learning"
                label: "Cancel"
                onClicked: root.close()
            }
            SettingsParts.Button {
                enabled: root.phase !== "learning" && (root.mics.length > 0 || root.testWav !== "")
                label: root.phase === "listening" || root.phase === "learning" ? "End voice capture" : "Start voice capture"
                onClicked: root.phase === "listening" ? root.end() : root.start()
            }
        }
    }

    EnrollmentDone {
        id: done
        visible: root.finished
        voice: true
        face: root.faceEnrolled
        onClosed: root.close()
        onStartVoice: root.show()
        onStartFace: { root.close(); root.startFace() }
    }
}
