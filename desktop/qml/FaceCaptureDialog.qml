import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtMultimedia

// Teams' face capture (Settings ▸ Recognition ▸ Start face capture / Update;
// biometric-enrollment `On`, measured on winpc 2026-11-15). A 600-wide
// dialog (757 tall, scrolling where the window is shorter):
// - "Create your face profile" (15/700) and the camera picker (278.7 x 30).
// - The preview: the camera behind a #F5F5F5 panel (522 x 334) with Teams'
//   round window (r 95.7) cut out, Teams' guide picture (88) to its right,
//   and for the side poses a green guide arc and the turned picture fading
//   in and out.
// - Three step dots, the pose's instruction (16/700) and its help (14/20).
// - Cancel and Start. After Start the poses count down by themselves:
//   3, 2, 1 (40 px, white, 2 s apart, starting 2 s in), then the photo.
//   Center, Left, Right; a refused centre photo is retried (the reason
//   shown), the side photos move on as Teams' centre-only mode does.
// - Then Teams' completion step.
// Photos go to Teams' biometric service (Backend::face_capture_submit).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600
    height: Math.min(done.visible ? done.height : 757, (parent ? parent.height : 800) - 86)
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// Voice is set up too (for the completion step).
    property bool voiceEnrolled: false
    signal startVoice()

    // "Center", "Left", "Right"
    property string pose: "Center"
    property bool started: false
    property int count: 0           // the digit on show, 0 for none
    property bool learning: false
    property string error: ""       // Teams' reason for the last refusal
    property string capturedSource: ""
    property bool finished: false

    function show() {
        pose = "Center"; started = false; count = 0; learning = false; error = ""; capturedSource = ""; finished = false
        flick.contentY = 0
        open()
    }
    onClosed: {
        countdown.stop()
        if (started && !finished) backend.faceCaptureCancel()
        started = false
    }
    Keys.onEscapePressed: close()

    readonly property var errors: ({
        MultipleFaces: qsTr("Make sure your face is the only one in the frame, then try again."),
        NoFaces: qsTr("We can’t seem to see your face. Make sure that your face matches the target lines in the frame and then try again"),
        FaceTooSmall: qsTr("Your face is too far away from the camera. Move a little closer, then try again"),
        UnexpectedHeadPose: qsTr("It looks like your face isn’t pointing in the same direction as the target line. Move your head around until it matches the line, then try again. Hint: make sure you’re moving your whole head, not just your eyes."),
        BadLighting: qsTr("Make sure you’re in a well-lit room and try again.")
    })

    MediaDevices { id: devices }
    property int cameraIndex: 0
    readonly property var cameras: devices.videoInputs
    CaptureSession {
        camera: Camera {
            id: camera
            active: root.opened && !root.finished
            cameraDevice: root.cameras.length ? root.cameras[Math.min(root.cameraIndex, root.cameras.length - 1)] : devices.defaultVideoInput
        }
        imageCapture: ImageCapture {
            id: shooter
            onImageSaved: (id, path) => {
                root.capturedSource = "file://" + path
                root.learning = true
                backend.faceCaptureSubmit(path, root.pose)
            }
            onErrorOccurred: (id, err, msg) => { console.warn("FACE capture", msg); root.error = "UnspecifiedFailure"; root.learning = false; countdown.restartPose() }
        }
        videoOutput: preview
    }
    /// For the harness: submit this photo instead of the camera's.
    property string testPhoto: ""
    function countdownForTest() { countdown.restartPose() }

    Connections {
        target: backend
        enabled: root.opened && root.started
        function onFaceCaptureResult(result) {
            root.learning = false
            root.capturedSource = ""
            // Teams' centre-only mode: a refused left photo moves on; the
            // centre and right ones (the right one stores the profile) are
            // tried again.
            if (result === "Success" || root.pose === "Left") {
                root.error = ""
                if (root.pose === "Right") { root.finished = true; return }
                root.pose = root.pose === "Center" ? "Left" : "Right"
            } else {
                root.error = result
            }
            countdown.restartPose()
        }
    }

    // Teams' countdown: 2 s, then 3, 2, 1 (2 s each), then the photo.
    Timer {
        id: countdown
        interval: 2000; repeat: true
        property int step: 0
        function restartPose() { step = 0; root.count = 0; restart() }
        onTriggered: {
            step++
            if (step <= 3) { root.count = 4 - step; return }
            root.count = 0
            stop()
            if (root.testPhoto) {
                root.learning = true
                backend.faceCaptureSubmit(root.testPhoto, root.pose)
            } else {
                shooter.captureToFile(backend.capturePath("face-" + root.pose.toLowerCase() + ".jpg"))
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        visible: !root.finished
        contentWidth: 600; contentHeight: 757
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Text {
            x: 42; y: 20.6; height: 21.43
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Create your face profile")
            font.family: theme.font; font.pixelSize: 15; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        OutlineDropdown {
            x: 42.7; y: 52.1; width: 278.7; height: 30
            enabled: !root.started
            accessibleName: qsTr("Choose camera")
            placeholder: qsTr("Choose camera")
            // Teams drops what follows " (" in a camera's name.
            options: root.cameras.map(c => ({ label: String(c.description).split(" (")[0] }))
            current: root.cameraIndex
            onPicked: i => root.cameraIndex = i
        }

        // The preview: the camera, then Teams' panel with its round window.
        Item {
            x: 32; y: 102.7; width: 522; height: 435
            VideoOutput {
                id: preview
                x: 61; y: 22; width: 400; height: 300
                fillMode: VideoOutput.PreserveAspectFit
            }
            Image {
                // The frozen photo while it is being checked.
                visible: root.capturedSource !== ""
                x: 61; y: 22; width: 400; height: 300
                source: root.capturedSource
                fillMode: Image.PreserveAspectFit
            }
            Shape {
                width: 600; height: 500
                scale: 522 / 600; transformOrigin: Item.TopLeft
                ShapePath {
                    fillColor: theme.pick("#F5F5F5", "#1F1F1F", "#FFFFFF")
                    strokeWidth: -1
                    fillRule: ShapePath.OddEvenFill
                    PathSvg { path: "M597,0 C598.656854,0 600,1.34314575 600,3 L600,384 L0,384 L0,3 C0,1.34314575 1.34314575,0 3,0 L597,0 Z M300,82 C239.248678,82 190,131.248678 190,192 C190,252.751322 239.248678,302 300,302 C360.751322,302 410,252.751322 410,192 C410,131.248678 360.751322,82 300,82 Z" }
                }
            }
            // The side poses' guide: a green arc on that side of the window
            // (Teams' 320 box: circle (271, 134) r 180, stroke 8, shown from
            // y 20 to 248; mirrored for Right), 220 across, centred on it.
            Shape {
                id: guide
                visible: root.started && root.pose !== "Center"
                readonly property bool mirrored: root.pose === "Right"
                readonly property real dx: Math.sqrt(180 * 180 - 114 * 114)
                x: 151; y: 57; width: 320; height: 320
                scale: 220 / 320; transformOrigin: Item.TopLeft
                ShapePath {
                    strokeColor: theme.pick("#9FD89F", "#359B35", "#FFFFFF")
                    strokeWidth: 8
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    startX: guide.mirrored ? 49 + guide.dx : 271 - guide.dx; startY: 20
                    PathArc {
                        x: guide.mirrored ? 49 + guide.dx : 271 - guide.dx; y: 248
                        radiusX: 180; radiusY: 180
                        direction: guide.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise
                    }
                }
            }
            Text {
                visible: root.count > 0
                x: 261 - width / 2; y: 172 - height / 2
                text: root.count
                font.family: theme.font; font.pixelSize: 40
                color: "white"
                Accessible.name: ["", qsTr("One"), qsTr("Two"), qsTr("Three")][root.count]
            }
            // Teams' guide picture; for a side pose the turned one fades in
            // and out (1.5 s).
            Image {
                x: 434; y: 171; width: 88; height: 88
                source: "../assets/biometric/face_forward.png"
                smooth: true; mipmap: true
            }
            Image {
                id: sidePicture
                visible: root.started && root.pose !== "Center"
                x: 434; y: 171; width: 88; height: 88
                source: root.pose === "Right" ? "../assets/biometric/face_right_side.png" : "../assets/biometric/face_left_side.png"
                smooth: true; mipmap: true
                SequentialAnimation on opacity {
                    running: sidePicture.visible
                    loops: 60
                    NumberAnimation { from: 0; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 1; to: 0; duration: 1500; easing.type: Easing.InOutQuad }
                }
            }
        }

        // Teams' three step dots.
        Row {
            x: 269; y: 496.7; spacing: 12
            Repeater {
                model: ["Center", "Left", "Right"]
                delegate: Rectangle {
                    required property string modelData
                    width: 8; height: 8; radius: 4
                    color: root.pose === modelData ? theme.brandFill : theme.pick("#C7C7C7", "#5C5C5C", "#000000")
                }
            }
        }
        Text {
            x: 32; y: 520.7; width: 522; height: 32
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: root.pose === "Center" ? qsTr("Look straight ahead") : root.pose === "Left" ? qsTr("Look to the left") : qsTr("Look to the right")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Column {
            x: 89.4; y: 566.7; width: 407.2; spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.pose === "Center" ? qsTr("Make sure your face is centered in the circle. Photos are automatically captured when the countdown reaches its end.<br>Click start when ready.").split("<br>")[0]
                                             : qsTr("The photo is automatically captured when the countdown reaches its end.")
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                visible: root.pose === "Center"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Make sure your face is centered in the circle. Photos are automatically captured when the countdown reaches its end.<br>Click start when ready.").split("<br>")[1]
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
        }
        // Teams' error row: why the photo was refused, or no camera.
        Row {
            readonly property string message: root.cameras.length === 0 && !camera.active
                ? qsTr("We couldn't detect a camera. Close any other apps that might be using it and try again.")
                : root.error ? (root.errors[root.error] || qsTr("Something went wrong. Please try again.")) : ""
            visible: message !== ""
            x: 32; y: 662; width: 522; spacing: 8
            FluentIcon { name: "error-circle-20-filled"; size: 16; color: theme.pick("#C50F1F", "#DC626D", "#FFFFFF") }
            Text {
                width: 498
                text: parent.message
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.pick("#C50F1F", "#DC626D", "#FFFFFF")
            }
        }
        Row {
            x: 364; y: 710.2; spacing: 15
            SettingsParts.Button {
                label: qsTr("Cancel")
                onClicked: root.close()
            }
            SettingsParts.Button {
                visible: !root.started
                enabled: camera.active || root.testPhoto !== ""
                label: qsTr("Start")
                onClicked: { root.started = true; root.error = ""; countdown.restartPose() }
            }
        }
    }

    EnrollmentDone {
        id: done
        visible: root.finished
        voice: root.voiceEnrolled
        face: true
        onClosed: root.close()
        onStartFace: root.show()
        onStartVoice: { root.close(); root.startVoice() }
    }
}
