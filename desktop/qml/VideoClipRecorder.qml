import QtQuick
import QtQuick.Controls.Basic
import QtMultimedia
import com.ost.desktop

// Teams' Record video clip (Microsoft Stream's recorder inside Teams'
// dialog), measured on winpc 2026-11-14:
// - 800 x 584, rounded 8. A 56 px header: the title (16/600 at 16, 17) and
//   Close (32 x 31.3 at 756, 12.3); the picture 760.9 x 428 at (19.6, 56),
//   rounded 8; the tools (64 tall) under it; then a #FAFAFA strip (36):
//   "Only people in this chat can view your clip. By creating a clip,
//   you're consenting to be recorded." and "Privacy statement" (12 px).
// - Tools, centred, 51.3 tall with a 20 px icon over a 10 px label: Camera
//   (59, then its 24 px settings chevron), Mic (56 + 24), Screen (56).
//   Camera's menu: None, the cameras and Mirror video; Mic's: None and the
//   microphones (rows of 14 px text, 32 tall, two lines for long names).
// - Three modes: the camera ("Record a video clip"); camera off with the
//   mic on, "Record audio" (a 108 px white circle with the microphone on
//   #E6E6E6); and Screen (pressed, or nothing on): "Screen recording",
//   Teams' screen picture, "You'll pick a screen, window, or tab. …" and
//   "Start screen recording". Under the start button and the pill lies
//   their big soft shadow. What the picture shows is what is recorded
//   (ClipFrames), 1280 x 720.
// - "Start recording" (156.6 x 50, brand, round, a 4.67 white ring) at
//   (321.7, 411) starts at once (no countdown). While recording, the pill
//   (211.3 x 60 at 294.3, 406: #D6D6D6 at 65 %, the white ring): Stop and
//   review (40, brand), Pause / Resume, the time left of 5:00 (16 px) and,
//   after a line, Record again; Record again (32 x 31.3) at the bottom left
//   and Next (brand) at the bottom right; Mic and Screen greyed. The title
//   reads "Recording in progress" or "Recording paused".
// - Review your clips: the clip (647.1 x 364 at 76.4, 57.1, rounded 8),
//   Play/Pause (32) and the filmstrip (563.1 x 32, rounded 10) under it,
//   the playhead's time ("0:02:95") over it, "0:02 / 0:21" (16/600) below;
//   Download recording beside Close; Back, the tools (Delete clip) and
//   Continue along the bottom (no strip).
// - Close asks "Close your recording?" / "This will delete your recording
//   clips." with Close recording (brand) and Cancel, over the recorder
//   whitened at 95 %.
Popup {
    id: rec
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 800; height: 584
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.NoAutoClose
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// The chat the clip is for (its members may watch it).
    property string chatId: ""
    /// The recording is done: {path, thumb, width, height, duration}.
    signal finished(var clip)

    /// "setup", "recording", "paused" or "review".
    property string stage: "setup"
    property bool cameraOn: true
    property bool micOn: true
    property bool screenOn: false
    property bool mirror: false
    property string cameraId: ""
    property string micId: ""
    // The chosen microphone (a stable value: re-binding a session's device
    // reopens it).
    property var micDevice: devices.defaultAudioInput
    onMicIdChanged: {
        const c = devices.audioInputs.find(d => d.id == micId)
        micDevice = c || devices.defaultAudioInput
        if (wantFrames) prepareFrames()
    }
    readonly property bool screenMode: screenOn || (!cameraOn && !micOn)
    readonly property bool audioMode: !screenMode && !cameraOn
    readonly property int limitMs: 5 * 60 * 1000
    /// Time recorded so far (paused time excluded).
    property real recordedMs: 0
    property bool confirmClose: false
    property url clipPath: ""
    property string thumbPath: ""
    property var frames: []
    property int clipW: 0
    property int clipH: 0

    function cacheFile(name) {
        return backend.recorderFile(name)
    }
    function reset() {
        if (stage === "recording" || stage === "paused") { discardOnStop = true; engineStop() }
        screen.active = false
        player.stop()
        player.source = ""
        stage = "setup"
        recordedMs = 0
        shots = []
        thumbPath = ""
        clipPath = ""
        confirmClose = false
    }
    function openFor(chat) {
        chatId = chat
        cameraOn = true
        screenOn = false
        reset()
        open()
    }
    function clock(ms) {
        const s = Math.max(0, Math.ceil(ms / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function startRecording() {
        // Screen recording starts once a screen or window is picked.
        if (screenMode && !screen.active) { waitingForScreen = true; screen.active = true; return }
        shots = []
        thumbPath = ""
        recordedMs = 0
        recordedBefore = 0
        segmentStart = 0
        const file = cacheFile("recording-" + Date.now() + ".mp4")
        // The camera and the screen are recorded straight from the device
        // (at full frame rate); Record audio records its picture.
        engine = audioMode ? "frames" : screenMode ? "screen" : "camera"
        if (engine === "frames") {
            if (!framesReady) prepareFrames()
            if (!frames.start(file)) { console.warn("RECORDER couldn't start"); return }
            framesReady = false
        } else {
            const r = engine === "screen" ? screenRecorder : camRecorder
            r.outputLocation = "file://" + file
            r.record()
        }
        stage = "recording"
        frameTimer.restart()
        firstFrame.restart()
    }
    property bool waitingForScreen: false
    // Record audio's session is set up while it shows (its microphone
    // open), so recording starts at once.
    property bool framesReady: false
    function prepareFrames() { framesReady = frames.prepare(micId, micOn && !testSilent, 1280, 720) }
    readonly property bool wantFrames: opened && audioMode && stage === "setup"
    onWantFramesChanged: if (wantFrames) prepareFrames(); else if (stage === "setup" && framesReady) { frames.release(); framesReady = false }
    onMicOnChanged: if (wantFrames) prepareFrames()
    onTestSilentChanged: if (wantFrames) prepareFrames()
    /// What records: "camera", "screen" or "frames" (Record audio).
    property string engine: ""
    function enginePause() { if (engine === "frames") frames.pause(); else (engine === "screen" ? screenRecorder : camRecorder).pause() }
    function engineResume() { if (engine === "frames") frames.resume(); else (engine === "screen" ? screenRecorder : camRecorder).record() }
    function engineStop() { if (engine === "frames") frames.stop(); else (engine === "screen" ? screenRecorder : camRecorder).stop() }
    function recorded(path) {
        screen.active = false
        if (discardOnStop) {
            discardOnStop = false
            backend.removeRecorderFile(path)
            // Record again: straight into a new recording.
            if (stage === "recording" || stage === "paused") startRecording()
            return
        }
        if (stage === "review") {
            clipPath = "file://" + String(path).replace(/^file:\/\//, "")
            player.source = clipPath
            player.pause()
        }
    }
    function stopAndReview() {
        frameTimer.stop()
        stage = "review"
        engineStop()
    }
    function recordAgain() {
        frameTimer.stop()
        discardOnStop = true
        engineStop()
    }
    property bool discardOnStop: false
    property var shots: []
    function grabFrame(first) {
        const file = cacheFile("frame-" + Date.now() + "-" + shots.length + ".jpg")
        canvas.grabToImage(r => {
            if (r.saveToFile(file)) {
                rec.shots = rec.shots.concat(["file://" + file])
                if (first || !rec.thumbPath) rec.thumbPath = file
            }
        }, Qt.size(1280, 720))
    }
    Timer {
        id: frameTimer
        interval: 2000; repeat: true
        triggeredOnStart: false
        onTriggered: if (rec.stage === "recording") rec.grabFrame(false)
    }
    Timer { id: firstFrame; interval: 600; onTriggered: if (rec.stage === "recording") rec.grabFrame(true) }
    // The time recorded (the encoder reports it only now and then): counted
    // while recording, not while paused.
    property real segmentStart: 0
    property real recordedBefore: 0
    Timer {
        interval: 100; repeat: true
        running: rec.stage === "recording"
        onRunningChanged: if (running) rec.segmentStart = Date.now(); else if (rec.segmentStart > 0) { rec.recordedBefore += Date.now() - rec.segmentStart; rec.segmentStart = 0 }
        onTriggered: {
            rec.recordedMs = rec.recordedBefore + (Date.now() - rec.segmentStart)
            if (rec.recordedMs >= rec.limitMs) rec.stopAndReview()
        }
    }

    MediaDevices { id: devices }
    // The camera's picture (shown, and so recorded, in camera mode).
    CaptureSession {
        camera: Camera {
            id: camera
            active: rec.opened && rec.cameraOn && !rec.screenMode && rec.stage !== "review"
            cameraDevice: {
                const list = devices.videoInputs
                const c = list.find(d => d.id == rec.cameraId)
                return c || devices.defaultVideoInput
            }
        }
        audioInput: AudioInput {
            muted: !rec.micOn || rec.testSilent
            device: rec.micDevice
        }
        recorder: MediaRecorder {
            id: camRecorder
            mediaFormat { fileFormat: MediaFormat.MPEG4; videoCodec: MediaFormat.VideoCodec.H264; audioCodec: MediaFormat.AudioCodec.AAC }
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState && rec.engine === "camera") rec.recorded(String(actualLocation))
            onErrorOccurred: (e, s) => { console.warn("RECORDER camera", s); rec.stage = "setup" }
        }
        videoOutput: camPreview
    }
    // The screen (or window) being recorded.
    CaptureSession {
        screenCapture: ScreenCapture {
            id: screen
            active: false
            onErrorOccurred: (e, s) => { console.warn("RECORDER screen", s); rec.waitingForScreen = false; active = false }
        }
        audioInput: AudioInput {
            muted: !rec.micOn || rec.testSilent
            device: rec.micDevice
        }
        recorder: MediaRecorder {
            id: screenRecorder
            mediaFormat { fileFormat: MediaFormat.MPEG4; videoCodec: MediaFormat.VideoCodec.H264; audioCodec: MediaFormat.AudioCodec.AAC }
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState && rec.engine === "screen") rec.recorded(String(actualLocation))
            onErrorOccurred: (e, s) => { console.warn("RECORDER screen", s); rec.stage = "setup" }
        }
        videoOutput: screenPreview
    }
    MediaPlayer {
        id: player
        videoOutput: review
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) {
            const r = metaData.value(MediaMetaData.Resolution)
            if (r) { rec.clipW = r.width; rec.clipH = r.height }
        }
    }

    // ---- Header ----
    Text {
        x: 16; y: 17; height: 22; verticalAlignment: Text.AlignVCenter
        text: rec.stage === "review" ? "Review your clips" : rec.stage === "recording" ? "Recording in progress" : rec.stage === "paused" ? "Recording paused" : rec.screenMode ? "Screen recording" : rec.audioMode ? "Record audio" : "Record a video clip"
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
    }
    component HeadButton: Rectangle {
        id: hb
        property string icon
        property string label
        signal clicked()
        y: 12.3; width: 32; height: 31.3; radius: 4
        color: hbHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: hb.icon; size: 20; color: theme.textStrong }
        HoverHandler { id: hbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        ToolTip.visible: hbHover.hovered; ToolTip.delay: 500; ToolTip.text: hb.label
        Accessible.role: Accessible.Button
        Accessible.name: hb.label
    }
    HeadButton {
        visible: rec.stage === "review"
        x: 696; icon: "arrow-download-20"; label: "Download recording"
        onClicked: backend.saveRecording(String(rec.clipPath))
    }
    Rectangle { visible: rec.stage === "review"; x: 741.7; y: 18; width: 0.67; height: 20; color: theme.divider }
    HeadButton {
        x: 756; icon: "dismiss-20"; label: "Close camera"
        onClicked: {
            if (rec.stage === "setup") { rec.reset(); rec.close() }
            else rec.confirmClose = true
        }
    }

    // Screen recording starts with the first picture of what was picked
    // (the desktop's own picker comes first).
    Connections {
        target: screenPreview.videoSink
        function onVideoFrameChanged() { if (rec.waitingForScreen) { rec.waitingForScreen = false; rec.startRecording() } }
    }
    // ---- The picture (recorded as shown) ----
    Rectangle {
        id: canvas
        visible: rec.stage !== "review"
        x: 19.6; y: 56; width: 760.9; height: 428
        color: rec.screenMode && rec.stage !== "setup" || (!rec.screenMode && !rec.audioMode) ? "black" : "#E6E6E6"
        clip: true
        VideoOutput {
            id: camPreview
            anchors.fill: parent
            visible: !rec.screenMode && !rec.audioMode
            fillMode: VideoOutput.PreserveAspectFit
            transform: Scale { origin.x: camPreview.width / 2; xScale: rec.mirror ? -1 : 1 }
        }
        VideoOutput {
            id: screenPreview
            anchors.fill: parent
            visible: rec.screenMode && rec.stage !== "setup"
            fillMode: VideoOutput.PreserveAspectFit
        }
        // Record audio: the microphone in a white circle.
        Rectangle {
            visible: rec.audioMode
            x: 400 - 19.6 - 54; y: 264 - 56 - 54; width: 108; height: 108; radius: 54
            color: "#FCFCFC"
            FluentIcon { anchors.centerIn: parent; name: "mic-20"; size: 48; color: "#252525" }
        }
        // Screen recording, before it starts.
        Column {
            visible: rec.screenMode && rec.stage === "setup"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 178.9 - 56
            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 70; height: 73.3; source: "../assets/illustrations/screen-recording.svg"; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(140, 140) }
            Text {
                width: 684.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "You’ll pick a screen, window, or tab. Recording will start automatically. For optimal quality, ensure this tab is in view while recording."
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: "#242424"
            }
        }
        ClipFrames {
            id: frames
            onRecorded: ms => {}
            // (Later: the recording may be replaced from here, and this runs
            // inside its own recorder's signal.)
            onStopped: path => Qt.callLater(rec.recorded, path)
            onFailed: m => { console.warn("RECORDER error", m); rec.stage = "setup" }
            Component.onDestruction: release()
        }
    }
    // The pill's big soft shadow (Teams' box-shadow -5 -5 250 #4D4D4D).
    Canvas {
        visible: rec.stage !== "review"
        x: canvas.x; y: canvas.y; width: canvas.width; height: canvas.height
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = 400 - x - 5, cy = 436 - y - 5
            const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, 300)
            g.addColorStop(0, "rgba(77, 77, 77, 0.22)")
            g.addColorStop(0.45, "rgba(77, 77, 77, 0.08)")
            g.addColorStop(1, "rgba(77, 77, 77, 0)")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }
    RoundedCorners { visible: rec.stage !== "review"; x: canvas.x; y: canvas.y; width: canvas.width; height: canvas.height; radius: 8; background: theme.surface }
    // Start recording / Start screen recording.
    Rectangle {
        visible: rec.stage === "setup"
        anchors.horizontalCenter: canvas.horizontalCenter
        y: 411 - 4.67
        width: startRow.implicitWidth + 32 + 9.33; height: 50 + 9.33; radius: height / 2
        color: "white"
        Rectangle {
            anchors.fill: parent; anchors.margins: 4.67; radius: height / 2
            color: startHover.hovered ? theme.brandHover : theme.brand
            Row {
                id: startRow
                anchors.centerIn: parent; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "record-20"; size: 20; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rec.screenMode ? "Start screen recording" : "Start recording"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            }
        }
        HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rec.startRecording() }
        Accessible.role: Accessible.Button
        Accessible.name: rec.screenMode ? "Start screen recording" : "Start recording"
    }
    // The recording pill.
    component PillButton: Rectangle {
        id: pb
        property string icon
        property string label
        property bool primary: false
        signal clicked()
        width: 40; height: 40; radius: 20
        color: primary ? (pbHover.hovered ? theme.brandHover : theme.brand) : pbHover.hovered ? Qt.rgba(1, 1, 1, 0.5) : "transparent"
        FluentIcon { anchors.centerIn: parent; name: pb.icon; size: 20; color: pb.primary ? "white" : theme.textStrong }
        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        ToolTip.visible: pbHover.hovered; ToolTip.delay: 300; ToolTip.text: pb.label
        Accessible.role: Accessible.Button
        Accessible.name: pb.label
    }
    Rectangle {
        visible: rec.stage === "recording" || rec.stage === "paused"
        x: 294.3; y: 406; width: 211.3; height: 60; radius: 30
        color: Qt.rgba(214 / 255, 214 / 255, 214 / 255, 0.65)
        border.color: "white"; border.width: 4.67
        PillButton {
            x: 309 - 294.3; y: 10
            primary: rec.stage === "recording"
            icon: "stop-20-filled"; label: "Stop and review"
            onClicked: rec.stopAndReview()
        }
        PillButton {
            x: 349 - 294.3; y: 10
            primary: rec.stage === "paused"
            icon: rec.stage === "paused" ? "record-20-filled" : "pause-20"
            label: rec.stage === "paused" ? "Resume" : "Pause Video Recording"
            onClicked: {
                if (rec.stage === "paused") { rec.engineResume(); rec.stage = "recording"; frameTimer.start() }
                else { rec.enginePause(); rec.stage = "paused"; frameTimer.stop() }
            }
        }
        Text {
            x: 397 - 294.3; y: 19.3; height: 21.3; verticalAlignment: Text.AlignVCenter
            text: rec.clock(rec.limitMs - rec.recordedMs)
            font.family: theme.font; font.pixelSize: 16; color: theme.text
            Accessible.role: Accessible.StaticText
        }
        Rectangle { x: 442.3 - 294.3; y: 15; width: 0.67; height: 30; color: theme.pick("#8A8886", "#ADADAD") }
        PillButton {
            x: 451 - 294.3; y: 10
            icon: "arrow-counterclockwise-20"; label: "Record again"
            onClicked: rec.recordAgain()
        }
    }

    // ---- The tools ----
    component Tool: Rectangle {
        id: tl
        property string icon
        property string label
        property string spoken: label
        property bool off: false
        property bool enabledTool: true
        property real toolWidth: 56
        property bool leftHalf: false
        signal clicked()
        width: toolWidth; height: 51.3
        radius: 4
        topRightRadius: leftHalf ? 0 : 4; bottomRightRadius: leftHalf ? 0 : 4
        color: tl.off ? theme.pick("#F5F5F5", "#292929") : tlHover.hovered && tl.enabledTool ? theme.menuHover : "transparent"
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 6; name: tl.icon; size: 20; color: tl.enabledTool ? theme.text : theme.disabled }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 25.7; height: 20; verticalAlignment: Text.AlignVCenter; text: tl.label; font.family: theme.font; font.pixelSize: 10; color: tl.enabledTool ? theme.text : theme.disabled }
        HoverHandler { id: tlHover; cursorShape: tl.enabledTool ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (tl.enabledTool) tl.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tl.spoken
    }
    component Chevron: Rectangle {
        id: cv
        property string label
        property bool enabledTool: true
        signal clicked()
        width: 24; height: 51.3
        topRightRadius: 4; bottomRightRadius: 4
        color: cvHover.hovered && cv.enabledTool ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "chevron-down-12"; size: 12; color: cv.enabledTool ? theme.textStrong : theme.disabled }
        HoverHandler { id: cvHover; cursorShape: cv.enabledTool ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (cv.enabledTool) cv.clicked() }
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: cv.label
    }
    readonly property bool live: stage === "recording" || stage === "paused"
    Row {
        visible: rec.stage !== "review"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 494
        Tool {
            id: camTool
            toolWidth: 59; leftHalf: true
            icon: rec.cameraOn ? "video-20" : "video-off-20"
            label: "Camera"; spoken: rec.cameraOn ? "Camera is on" : "Camera is off"
            off: !rec.cameraOn
            onClicked: rec.cameraOn = !rec.cameraOn
        }
        Chevron {
            id: camMenuBtn
            label: "Change Camera settings"
            enabledTool: !rec.live
            onClicked: camMenu.popupAt(camMenuBtn)
        }
        Tool {
            toolWidth: 56; leftHalf: true
            icon: rec.micOn ? "mic-20" : "mic-off-20"
            label: "Mic"; spoken: rec.micOn ? "Mic is on" : "Mic is off"
            enabledTool: !rec.live
            onClicked: rec.micOn = !rec.micOn
        }
        Chevron {
            id: micMenuBtn
            label: "Change Mic settings"
            enabledTool: !rec.live
            onClicked: micMenu.popupAt(micMenuBtn)
        }
        Tool {
            icon: rec.screenMode ? "share-screen-stop-20-filled" : "share-screen-start-20"
            label: "Screen"; spoken: "Share screen"
            off: rec.screenMode
            enabledTool: !rec.live
            onClicked: rec.screenOn = !rec.screenMode
        }
    }
    MenuPopup {
        id: camMenu
        function popupAt(btn) { const p = btn.mapToItem(rec.contentItem, 0, 0); x = p.x; y = p.y - height - 4; open() }
        readonly property var cams: devices.videoInputs
        items: [{ label: "None", checked: !rec.cameraOn }].concat(cams.map(c => ({ label: c.description, checked: rec.cameraOn && (rec.cameraId ? c.id == rec.cameraId : c.isDefault) }))).concat([{ separator: true }, { label: "Mirror video", checked: rec.mirror }])
        onPicked: i => {
            if (i === 0) rec.cameraOn = false
            else if (i <= cams.length) { rec.cameraId = String(cams[i - 1].id); rec.cameraOn = true }
            else rec.mirror = !rec.mirror
        }
    }
    MenuPopup {
        id: micMenu
        function popupAt(btn) { const p = btn.mapToItem(rec.contentItem, 0, 0); x = p.x; y = Math.max(8, p.y - height - 4); open() }
        readonly property var mics: devices.audioInputs
        items: [{ label: "None", checked: !rec.micOn }].concat(mics.map(m => ({ label: m.description, checked: rec.micOn && (rec.micId ? m.id == rec.micId : m.isDefault) })))
        onPicked: i => {
            if (i === 0) rec.micOn = false
            else { rec.micId = String(mics[i - 1].id); rec.micOn = true }
        }
    }
    // Record again and Next, while recording.
    component SquareButton: Rectangle {
        id: sq
        property string icon
        property string label
        property bool primary: false
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: primary ? (sqHover.hovered ? theme.brandHover : theme.brand) : sqHover.hovered ? theme.menuHover : theme.surface
        border.color: primary ? "transparent" : theme.stroke; border.width: primary ? 0 : 0.67
        FluentIcon { anchors.centerIn: parent; name: sq.icon; size: 20; color: sq.primary ? "white" : theme.text }
        HoverHandler { id: sqHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sq.clicked() }
        ToolTip.visible: sqHover.hovered; ToolTip.delay: 500; ToolTip.text: sq.label
        Accessible.role: Accessible.Button
        Accessible.name: sq.label
    }
    SquareButton { visible: rec.live; x: 16; y: 500.3; icon: "arrow-counterclockwise-20"; label: "Record again"; onClicked: rec.recordAgain() }
    SquareButton { visible: rec.live; x: 752; y: 500.3; primary: true; icon: "chevron-right-20"; label: "Next. Continue to review step."; onClicked: rec.stopAndReview() }

    // The consent strip.
    Rectangle {
        visible: rec.stage !== "review"
        y: 548; width: parent.width; height: 36
        color: theme.pick("#FAFAFA", "#1F1F1F")
        bottomLeftRadius: 8; bottomRightRadius: 8
        Row {
            x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 16; color: theme.textStrong }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Only people in this chat can view your clip. By creating a clip, you’re consenting to be recorded. <a href=\"https://go.microsoft.com/fwlink/p/?linkid=857875\">Privacy statement</a>"
                textFormat: Text.StyledText; linkColor: theme.brandForeground1
                font.family: theme.font; font.pixelSize: 12; color: theme.text
                onLinkActivated: l => Qt.openUrlExternally(l)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }
    }

    // ---- Review ----
    Rectangle {
        visible: rec.stage === "review"
        x: 76.4; y: 57.1; width: 647.1; height: 364; radius: 8
        color: "black"
        VideoOutput { id: review; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
        RoundedCorners { anchors.fill: parent; radius: 8; background: theme.surface }
    }
    Item {
        visible: rec.stage === "review"
        anchors.fill: parent
        readonly property real frac: player.duration > 0 ? player.position / player.duration : 0
        SquareButton {
            x: 98.4; y: 442.9; height: 32
            icon: player.playbackState === MediaPlayer.PlayingState ? "pause-20" : "play-20"
            label: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
            onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
        }
        // The filmstrip.
        Rectangle {
            id: strip
            x: 134.4; y: 442.9; width: 563.1; height: 32; radius: 10
            color: "black"
            clip: true
            Row {
                x: 3; y: 3
                Repeater {
                    model: 10
                    Image {
                        required property int index
                        width: (strip.width - 6) / 10; height: 26
                        fillMode: Image.PreserveAspectCrop
                        source: rec.shots.length ? rec.shots[Math.min(rec.shots.length - 1, Math.floor(index * rec.shots.length / 10))] : ""
                        asynchronous: true
                    }
                }
            }
            Rectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.color: theme.pick("#242424", "#ADADAD"); border.width: 2 }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function seek(mx) { if (player.duration > 0) player.position = Math.max(0, Math.min(1, mx / width)) * player.duration }
                onPressed: m => seek(m.x)
                onPositionChanged: m => { if (pressed) seek(m.x) }
            }
            Accessible.role: Accessible.Slider
            Accessible.name: "Use the left and right arrow keys to seek, seekbar"
        }
        // The playhead and its time (m:ss:cc).
        Rectangle { x: strip.x + strip.width * parent.frac - 1.5; y: strip.y - 4; width: 3; height: strip.height + 8; radius: 1.5; color: theme.brand }
        Rectangle { x: strip.x + strip.width * parent.frac - 7; y: strip.y - 11; width: 14; height: 14; radius: 7; color: theme.brand }
        Rectangle {
            x: strip.x + strip.width * parent.frac - width / 2; y: 400
            width: headTime.implicitWidth + 16; height: 28; radius: 4
            color: theme.surface; border.color: theme.stroke; border.width: 0.67
            Text {
                id: headTime; anchors.centerIn: parent
                text: { const ms = player.position; return Math.floor(ms / 60000) + ":" + String(Math.floor(ms / 1000) % 60).padStart(2, "0") + ":" + String(Math.floor(ms / 10) % 100).padStart(2, "0") }
                font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 482.9; height: 20
            text: rec.clock(player.position) + " / " + rec.clock(player.duration)
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        SquareButton { x: 16; y: 536.3; icon: "chevron-left-20"; label: "Back"; onClicked: { player.stop(); rec.reset() } }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 526
            Tool {
                toolWidth: 71.9; icon: "delete-20"; label: "Delete clip"; spoken: "Delete this clip. Your recording will be lost."
                onClicked: { backend.removeRecorderFile(String(rec.clipPath)); rec.reset() }
            }
        }
        SquareButton {
            x: 752; y: 536.3; primary: true; icon: "chevron-right-20"; label: "Continue"
            onClicked: {
                player.stop()
                rec.finished({ path: String(rec.clipPath), thumb: rec.thumbPath ? "file://" + rec.thumbPath : "", width: rec.clipW || 1280, height: rec.clipH || 720, duration: player.duration })
                rec.stage = "setup"
                rec.close()
            }
        }
    }

    // ---- Close your recording? ----
    Rectangle {
        visible: rec.confirmClose
        anchors.fill: parent; radius: 8
        color: Qt.rgba(1, 1, 1, 0.95)
        MouseArea { anchors.fill: parent }
        Column {
            x: 285.7; y: 243; spacing: 0
            Text { height: 28; text: "Close your recording?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Item { width: 1; height: 16 }
            Text { height: 20; text: "This will delete your recording clips."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 16 }
            Row {
                spacing: 8
                Rectangle {
                    width: closeText.implicitWidth + 24; height: 31.3; radius: 4
                    color: closeRecHover.hovered ? theme.brandHover : theme.brand
                    Text { id: closeText; anchors.centerIn: parent; text: "Close recording"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                    HoverHandler { id: closeRecHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { backend.removeRecorderFile(String(rec.clipPath)); rec.reset(); rec.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Close recording"
                }
                Rectangle {
                    width: 96; height: 31.3; radius: 4
                    color: cancelRecHover.hovered ? theme.menuHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    HoverHandler { id: cancelRecHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: rec.confirmClose = false }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
    }

    // Test hooks (--recorder-test). `testSilent` records without the
    // microphone, so a test never captures the room.
    property bool testSilent: false
    function pickCameraForTest(name) { const c = devices.videoInputs.find(d => d.description === name); if (c) { cameraId = String(c.id); cameraOn = true } }
    function pauseForTest() { enginePause(); stage = "paused"; frameTimer.stop() }
    function resumeForTest() { engineResume(); stage = "recording"; frameTimer.start() }
    function continueForTest() { player.stop(); finished({ path: String(clipPath), thumb: thumbPath ? "file://" + thumbPath : "", width: clipW || 1280, height: clipH || 720, duration: player.duration }); stage = "setup"; close() }
    function stateForTest() { return { stage: stage, cameraOn: cameraOn, micOn: micOn, recordedMs: recordedMs, clip: String(clipPath), frames: shots.length, screen: screenMode, audio: audioMode, thumb: thumbPath, cams: devices.videoInputs.map(c => c.description), mics: devices.audioInputs.length, duration: player.duration, size: [clipW, clipH] } }
    function openCamMenuForTest() { camMenu.popupAt(camMenuBtn) }
    function openMicMenuForTest() { micMenu.popupAt(micMenuBtn) }
    function closeMenusForTest() { camMenu.close(); micMenu.close() }
}
