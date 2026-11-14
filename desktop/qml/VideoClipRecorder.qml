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
        for (const sg of segments) backend.removeRecorderFile(sg.path)
        segments = []
        selected = -1
        playhead = 0
        music = null
        trimming = false
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
        // The screen is recorded as the picture shows it (with what is
        // drawn over it), so pausing keeps sound and picture together.
        engine = audioMode || screenMode ? "frames" : "camera"
        if (engine === "frames") {
            if (!framesReady) prepareFrames()
            if (!frames.start(file)) { console.warn("RECORDER couldn't start"); return }
            framesReady = false
        } else {
            const r = camRecorder
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
    readonly property bool wantFrames: opened && (audioMode || screenMode) && stage === "setup"
    onWantFramesChanged: if (wantFrames) prepareFrames(); else if (stage === "setup" && framesReady) { frames.release(); framesReady = false }
    onMicOnChanged: if (wantFrames) prepareFrames()
    onTestSilentChanged: if (wantFrames) prepareFrames()
    /// What records: "camera", "screen" or "frames" (Record audio).
    property string engine: ""
    function enginePause() { if (engine === "frames") frames.pause(); else camRecorder.pause() }
    function engineResume() { if (engine === "frames") frames.resume(); else camRecorder.record() }
    function engineStop() { if (engine === "frames") frames.stop(); else camRecorder.stop() }
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
            // The recording joins the clip as its last part.
            const file = "file://" + String(path).replace(/^file:\/\//, "")
            clipPath = file
            segments = segments.concat([{ path: file, length: Math.round(recordedMs), start: 0, end: Math.round(recordedMs), shots: shots.slice() }])
            selected = segments.length - 1
            seekTimeline(0)
        }
    }

    // ---- The edit (Teams' review): the parts of the recordings in order,
    // played straight from them, with the music under them. ----
    /// [{path, length (the recording's), start, end, shots}]
    property var segments: []
    property int selected: -1
    /// Where the edit is (ms from its start) and whether it plays.
    property real playhead: 0
    property bool playing: false
    property bool trimming: false
    /// The music: {id, name, artist, url, cover, path, level} or null.
    property var music: null
    readonly property real total: segments.reduce((t, sg) => t + (sg.end - sg.start), 0)
    function segStartAt(i) { let t = 0; for (let k = 0; k < i; k++) t += segments[k].end - segments[k].start; return t }
    function segAt(t) {
        let acc = 0
        for (let i = 0; i < segments.length; i++) {
            const len = segments[i].end - segments[i].start
            if (t < acc + len || i === segments.length - 1) return { i: i, offset: Math.max(0, Math.min(len, t - acc)) }
            acc += len
        }
        return { i: -1, offset: 0 }
    }
    property int playingSeg: -1
    property real pendingPos: -1
    function seekTimeline(t) {
        playhead = Math.max(0, Math.min(total, t))
        const at = segAt(playhead)
        if (at.i < 0) return
        const sg = segments[at.i]
        playingSeg = at.i
        if (String(player.source) !== sg.path) { pendingPos = sg.start + at.offset; player.source = sg.path }
        else player.position = sg.start + at.offset
        if (musicPlayer.source != "" && musicPlayer.duration > 0) musicPlayer.position = playhead % musicPlayer.duration
    }
    function togglePlay() {
        if (playing) { playing = false; player.pause(); musicPlayer.pause(); return }
        if (playhead >= total - 30) seekTimeline(0)
        playing = true
        player.play()
        if (music && music.path) { musicPlayer.position = playhead % Math.max(1, musicPlayer.duration); musicPlayer.play() }
    }
    Timer {
        interval: 30; repeat: true
        running: rec.playing && rec.stage === "review"
        onTriggered: {
            const i = rec.playingSeg
            if (i < 0 || i >= rec.segments.length) return
            const sg = rec.segments[i]
            if (player.mediaStatus === MediaPlayer.LoadingMedia || rec.pendingPos >= 0) return
            rec.playhead = rec.segStartAt(i) + Math.max(0, player.position - sg.start)
            if (player.position >= sg.end - 15 || player.mediaStatus === MediaPlayer.EndOfMedia) {
                if (i + 1 < rec.segments.length) rec.seekTimeline(rec.segStartAt(i + 1))
                else { rec.playing = false; player.pause(); musicPlayer.pause(); rec.playhead = rec.total }
            }
        }
    }
    // Split, as Teams: at the playhead, inside a part (not at its ends).
    readonly property bool canSplit: {
        if (playing || segments.length === 0) return false
        const at = segAt(playhead), sg = segments[at.i]
        return at.offset > 300 && at.offset < (sg.end - sg.start) - 300
    }
    function splitAtPlayhead() {
        if (!canSplit) return
        const at = segAt(playhead), sg = segments[at.i]
        const cut = sg.start + at.offset
        const a = Object.assign({}, sg, { end: cut }), b = Object.assign({}, sg, { start: cut })
        const list = segments.slice()
        list.splice(at.i, 1, a, b)
        segments = list
        selected = at.i + 1
    }
    function deleteSelected() {
        if (selected < 0) return
        const gone = segments[selected]
        const list = segments.filter((_, k) => k !== selected)
        // A recording no part uses any more goes.
        if (!list.some(x => x.path === gone.path)) backend.removeRecorderFile(gone.path)
        if (list.length === 0) { segments = []; player.stop(); player.source = ""; selected = -1; stage = "setup"; return }
        segments = list
        selected = Math.min(selected, list.length - 1)
        seekTimeline(segStartAt(selected))
    }
    function moveSelected(dir) {
        const j = selected + dir
        if (selected < 0 || j < 0 || j >= segments.length) return
        const list = segments.slice()
        const t = list[selected]; list[selected] = list[j]; list[j] = t
        segments = list
        selected = j
        seekTimeline(segStartAt(j))
    }
    /// The edit for the renderer (and whether there is anything to do).
    function editSpec() {
        return {
            segments: segments.map(sg => ({ path: sg.path, start_ms: sg.start, end_ms: sg.end })),
            music: music && music.path ? { path: music.path, level: music.level / 100 } : null
        }
    }
    readonly property bool untouched: segments.length === 1 && segments[0].start === 0 && segments[0].end === segments[0].length && !(music && music.path)
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
            if (rec.total + rec.recordedMs >= rec.limitMs) rec.stopAndReview()
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
        videoOutput: screenPreview
    }
    MediaPlayer {
        id: player
        videoOutput: review
        audioOutput: AudioOutput {}
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
            const r = metaData.value(MediaMetaData.Resolution)
            if (r) { rec.clipW = r.width; rec.clipH = r.height }
            if (rec.pendingPos >= 0) { position = rec.pendingPos; rec.pendingPos = -1; if (rec.playing) play(); else pause() }
        }
    }
    // The music under the preview, looping, at its level.
    MediaPlayer {
        id: musicPlayer
        source: rec.music && rec.music.path ? rec.music.path : ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput { volume: rec.music ? rec.music.level / 100 : 0 }
    }
    // A song's preview in the Music panel.
    MediaPlayer {
        id: songPreview
        property string url: ""
        audioOutput: AudioOutput {}
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
        onClicked: {
            if (rec.untouched) backend.saveRecording(rec.segments[0].path)
            else { rec.saveAfterRender = true; backend.renderClip(JSON.stringify(rec.editSpec())) }
        }
    }
    Rectangle { visible: rec.stage === "review"; x: 741.7; y: 18; width: 0.67; height: 20; color: theme.divider }
    HeadButton {
        x: 756; icon: "dismiss-20"; label: "Close camera"
        onClicked: {
            if (rec.stage === "setup" && rec.segments.length === 0) { rec.reset(); rec.close() }
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
            text: rec.clock(rec.limitMs - rec.total - rec.recordedMs)
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
        Item { width: 20; height: 51.3; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
        Tool {
            icon: "slide-text-20"; label: "Script"
            off: teleprompter.visible
            onClicked: teleprompter.visible = !teleprompter.visible
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

    // ---- Script: Teams' teleprompter (Stream's), over the picture and not
    // recorded. 701.3 x 345.3 at (49.3, 100), white at 80 %, a #D1D1D1
    // hairline, rounded 6; a move handle at the top centre, then Play, font
    // smaller / larger (24–64 by 2, 48 at first), the scroll speed (a
    // vertical slider, 50–400 words a minute, 100 at first) and Close; the
    // script at the font size on lines twice as tall, 1em in. Playing
    // scrolls it at the speed and marks the word being read. ----
    // The font size and speed stay as set (Teams keeps them on the device).
    QtObject {
        id: promptSettings
        property int fontSize: parseInt(backend.setting("teleprompterFontSize")) || 48
        property int speed: parseInt(backend.setting("teleprompterScrollSpeed")) || 100
        onFontSizeChanged: backend.setSetting("teleprompterFontSize", String(fontSize))
        onSpeedChanged: backend.setSetting("teleprompterScrollSpeed", String(speed))
    }
    property string script: ""
    onScriptChanged: teleprompter.word = 0
    Rectangle {
        id: teleprompter
        visible: false
        x: 49.3; y: 100; width: 701.3; height: 345.3; radius: 6
        color: Qt.rgba(1, 1, 1, 0.8)
        border.color: "#D1D1D1"; border.width: 0.67
        z: 5
        property bool playing: false
        property int word: 0
        readonly property var words: rec.script.split(/[ \n]/)
        onVisibleChanged: if (!visible) playing = false
        onPlayingChanged: {
            if (playing) { promptScroll.restart(); wordTimer.restart() }
            else { promptScroll.stop(); wordTimer.stop() }
        }
        Item {
            width: parent.width; height: 32
            FluentIcon {
                anchors.horizontalCenter: parent.horizontalCenter; y: 7.7; name: "re-order-dots-horizontal-20"; size: 18; color: theme.text
                DragHandler { target: teleprompter; xAxis.minimum: -40; xAxis.maximum: rec.width - 80; yAxis.minimum: 0; yAxis.maximum: rec.height - 80; cursorShape: Qt.ClosedHandCursor }
                HoverHandler { cursorShape: Qt.OpenHandCursor }
                Accessible.role: Accessible.Button
                Accessible.name: "Move the teleprompter using the keyboard arrow keys"
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 0.7; y: 0.7
                HeadButton {
                    y: 0; height: 32
                    icon: teleprompter.playing ? "pause-20" : "play-20"
                    label: teleprompter.playing ? "Pause" : "Play"
                    opacity: rec.script.length ? 1 : 0.4
                    onClicked: if (rec.script.length) teleprompter.playing = !teleprompter.playing
                }
                HeadButton { y: 0; height: 32; icon: "font-decrease-20"; label: "Decrease font size"; opacity: promptSettings.fontSize > 24 ? 1 : 0.4; onClicked: promptSettings.fontSize = Math.max(24, promptSettings.fontSize - 2) }
                HeadButton { y: 0; height: 32; icon: "font-increase-20"; label: "Increase font size"; opacity: promptSettings.fontSize < 64 ? 1 : 0.4; onClicked: promptSettings.fontSize = Math.min(64, promptSettings.fontSize + 2) }
                HeadButton { id: speedBtn; y: 0; icon: "top-speed-20"; label: "Change scroll speed"; color: speedPop.visible ? Qt.rgba(1, 1, 1, 0.2) : "transparent"; onClicked: rec.toggleSpeed(!speedPop.visible) }
                Item { width: 0.67; height: 32; Rectangle { y: 6; width: 0.67; height: 20; color: theme.divider } }
                HeadButton { y: 0; height: 32; icon: "dismiss-20"; label: "Close"; onClicked: teleprompter.visible = false }
            }
        }
        // Writing the script.
        Flickable {
            id: promptEdit
            visible: !teleprompter.playing
            x: 0.67; y: 32.7; width: parent.width - 1.33; height: parent.height - 33.3
            contentHeight: promptArea.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Rich text only for Teams' double-height lines (a block format
            // that new lines inherit); the script itself is plain text.
            // (A plain child: TextArea.flickable would add the padding twice.)
            TextArea {
                id: promptArea
                width: promptEdit.width
                textFormat: TextEdit.RichText
                property bool loading: false
                function load(t) {
                    loading = true
                    text = t ? "<div style=\"line-height:200%\">" + t.replace(/&/g, "&amp;").replace(/</g, "&lt;").split("\n").join("</div><div style=\"line-height:200%\">") + "</div>" : "<div style=\"line-height:200%\"></div>"
                    loading = false
                }
                Component.onCompleted: load(rec.script)
                onTextChanged: if (!loading) rec.script = getText(0, length).replace(/\u2029/g, "\n")
                placeholderText: "Type or paste your script here"
                placeholderTextColor: "#707070"
                wrapMode: TextEdit.Wrap
                padding: promptSettings.fontSize
                leftPadding: promptSettings.fontSize; rightPadding: promptSettings.fontSize
                topPadding: promptSettings.fontSize; bottomPadding: promptSettings.fontSize
                leftInset: 0; rightInset: 0; topInset: 0; bottomInset: 0
                textMargin: 0
                font.family: theme.font; font.pixelSize: promptSettings.fontSize
                color: "#242424"
                background: null
                selectByMouse: true
            }
        }
        // Reading it: lines twice as tall, the current word marked.
        Flickable {
            id: promptRead
            visible: teleprompter.playing
            x: 0.67; y: 32.7; width: parent.width - 1.33; height: parent.height - 33.3
            contentHeight: promptText.implicitHeight
            clip: true
            interactive: false
            Text {
                id: promptText
                width: promptRead.width
                padding: promptSettings.fontSize
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                font.family: theme.font; font.pixelSize: promptSettings.fontSize
                color: "#242424"
                text: {
                    const esc = w => w.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                    let k = 0
                    const lines = rec.script.split("\n").map(line => line.split(" ").map(w => {
                        const html = k === teleprompter.word ? "<span style=\"background-color:#242424; color:#FFFFFF\">" + esc(w) + "</span>" : esc(w)
                        k++
                        return html
                    }).join(" "))
                    return "<div style=\"line-height:200%\">" + lines.join("<br>") + "</div>"
                }
            }
            NumberAnimation on contentY {
                id: promptScroll
                running: false
                to: Math.max(0, promptRead.contentHeight - promptRead.height)
                // The whole script takes (words / speed) minutes; what is
                // left, its share of that.
                duration: {
                    const all = Math.max(1, promptRead.contentHeight - promptRead.height)
                    const left = 1 - promptRead.contentY / all
                    return Math.max(1, 60000 / promptSettings.speed * teleprompter.words.length * left)
                }
            }
        }
        // The word being read moves on as Teams times it: the minute's share
        // of the script, by each word's length (longer after punctuation).
        Timer {
            id: wordTimer
            repeat: false
            interval: {
                const w = teleprompter.words[teleprompter.word] || ""
                const unit = 60000 / promptSettings.speed * teleprompter.words.length / Math.max(1, rec.script.length)
                return Math.max(1, (w.length + 1) * unit + (/[.?!,]/.test(w) ? 5 * unit : 0))
            }
            onTriggered: if (teleprompter.word + 1 < teleprompter.words.length) { teleprompter.word++; restart() }
        }
        // Resize from the bottom right corner.
        Item {
            x: parent.width - 14; y: parent.height - 14; width: 14; height: 14
            Canvas {
                anchors.fill: parent
                onPaint: { const c = getContext("2d"); c.strokeStyle = "#616161"; c.lineWidth = 1; c.beginPath(); c.moveTo(4, 12); c.lineTo(12, 4); c.moveTo(8, 12); c.lineTo(12, 8); c.stroke() }
            }
            DragHandler {
                target: null
                property real w0: 0; property real h0: 0
                onActiveChanged: if (active) { w0 = teleprompter.width; h0 = teleprompter.height }
                onTranslationChanged: { teleprompter.width = Math.max(401.3, w0 + translation.x); teleprompter.height = Math.max(343, h0 + translation.y) }
                cursorShape: Qt.SizeFDiagCursor
            }
            HoverHandler { cursorShape: Qt.SizeFDiagCursor }
            Accessible.role: Accessible.Grip
            Accessible.name: "Resize the teleprompter container using the keyboard arrow keys while holding down ctrl"
        }
        // The scroll speed.
        Rectangle {
            id: speedPop
            visible: false
            y: 32; width: 32; height: 195.9; radius: 16
            color: "white"
            FluentSurface { z: -1; anchors.fill: parent; depth: 8; radius: 16 }
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 8; name: "add-16"; size: 16; color: theme.text }
            Slider {
                anchors.horizontalCenter: parent.horizontalCenter; y: 31.5; height: 129
                orientation: Qt.Vertical
                from: 50; to: 400
                value: promptSettings.speed
                onMoved: promptSettings.speed = Math.round(value)
                Accessible.name: "Scroll speed"
            }
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 24; name: "subtract-16"; size: 16; color: theme.text }
        }
    }

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
        id: reviewUi
        visible: rec.stage === "review"
        anchors.fill: parent
        // Trimming shows only the chosen part's recording (all of it).
        readonly property var trimSeg: rec.trimming && rec.selected >= 0 ? rec.segments[rec.selected] : null
        readonly property real stripX: 136.8
        readonly property real stripW: 560.6
        // Each part's place on the strip (3 apart), in proportion to its length.
        readonly property var layout: {
            const out = [], n = rec.segments.length, gap = 3
            const usable = stripW - gap * Math.max(0, n - 1)
            let x = stripX
            for (let i = 0; i < n; i++) {
                const len = rec.segments[i].end - rec.segments[i].start
                const w = rec.total > 0 ? usable * len / rec.total : usable
                out.push({ x: x, w: w })
                x += w + gap
            }
            return out
        }
        function timelineX(t) {
            if (trimSeg) return stripX + stripW * t / Math.max(1, trimSeg.length)
            const at = rec.segAt(t), l = layout[at.i]
            if (!l) return stripX
            const len = rec.segments[at.i].end - rec.segments[at.i].start
            return l.x + l.w * at.offset / Math.max(1, len)
        }
        readonly property real headX: trimSeg ? timelineX(player.position) : timelineX(rec.playhead)
        SquareButton {
            x: 100.8; y: 442.9; height: 32
            icon: rec.playing ? "pause-20" : "play-20"
            label: rec.playing ? "Pause" : "Play"
            onClicked: rec.togglePlay()
        }
        // The parts.
        Repeater {
            model: reviewUi.trimSeg ? [reviewUi.trimSeg] : rec.segments
            Rectangle {
                id: part
                required property var modelData
                required property int index
                readonly property var l: reviewUi.trimSeg ? ({ x: reviewUi.stripX, w: reviewUi.stripW }) : reviewUi.layout[index] || ({ x: 0, w: 0 })
                readonly property bool chosen: !reviewUi.trimSeg && index === rec.selected
                x: l.x; y: 442.9; width: l.w; height: 32; radius: 10
                color: "black"
                clip: true
                Row {
                    x: 3; y: 3
                    Repeater {
                        model: Math.max(1, Math.round((part.width - 6) / 56))
                        Image {
                            required property int index
                            width: (part.width - 6) / Math.max(1, Math.round((part.width - 6) / 56)); height: 26
                            fillMode: Image.PreserveAspectCrop
                            readonly property var shots: part.modelData.shots || []
                            source: shots.length ? shots[Math.min(shots.length - 1, Math.floor(index * shots.length / Math.max(1, Math.round((part.width - 6) / 56))))] : ""
                            asynchronous: true
                        }
                    }
                }
                Rectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.width: 2.67; border.color: part.chosen || reviewUi.trimSeg ? theme.pick("#242424", "#FFFFFF") : theme.pick("#8A8886", "#8A8886") }
                TapHandler {
                    onTapped: ev => {
                        if (reviewUi.trimSeg) { player.position = reviewUi.trimSeg.length * ev.position.x / part.width; return }
                        rec.selected = part.index
                        const len = part.modelData.end - part.modelData.start
                        rec.seekTimeline(rec.segStartAt(part.index) + len * ev.position.x / part.width)
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Video segment"
            }
        }
        // Trim: brand handles at the kept part's ends.
        Repeater {
            model: reviewUi.trimSeg ? 2 : 0
            Rectangle {
                required property int index
                readonly property real t: index === 0 ? rec.trimStart : rec.trimEnd
                x: reviewUi.timelineX(t) - (index === 0 ? 9.3 : 9.3); y: 438.2; width: 18.6; height: 41.3; radius: 4
                color: theme.brand
                DragHandler {
                    target: null; yAxis.enabled: false
                    property real from: 0
                    onActiveChanged: if (active) from = parent.t
                    onTranslationChanged: {
                        const len = reviewUi.trimSeg.length
                        const t = Math.max(0, Math.min(len, from + translation.x / reviewUi.stripW * len))
                        if (parent.index === 0) rec.trimStart = Math.min(t, rec.trimEnd - 500)
                        else rec.trimEnd = Math.max(t, rec.trimStart + 500)
                        player.position = parent.index === 0 ? rec.trimStart : rec.trimEnd
                    }
                }
                HoverHandler { cursorShape: Qt.SizeHorCursor }
                Accessible.role: Accessible.Slider
                Accessible.name: index === 0 ? "Start trim handle" : "End trim handle"
            }
        }
        // The playhead and its time (m:ss:cc).
        Rectangle { visible: !reviewUi.trimSeg || true; x: reviewUi.headX - 1.5; y: 438.9; width: 3; height: 40; radius: 1.5; color: theme.brand }
        Rectangle { x: reviewUi.headX - 6; y: 432; width: 12; height: 12; radius: 6; color: theme.brand }
        Rectangle {
            x: reviewUi.headX - width / 2; y: 400
            width: headTime.implicitWidth + 16; height: 28; radius: 4
            color: theme.surface; border.color: theme.stroke; border.width: 0.67
            Text {
                id: headTime; anchors.centerIn: parent
                text: { const ms = reviewUi.trimSeg ? player.position : rec.playhead; return Math.floor(ms / 60000) + ":" + String(Math.floor(ms / 1000) % 60).padStart(2, "0") + ":" + String(Math.floor(ms / 10) % 100).padStart(2, "0") }
                font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 482.9; height: 20
            text: reviewUi.trimSeg ? rec.clock(rec.trimEnd - rec.trimStart) + " / " + rec.clock(reviewUi.trimSeg.length) : rec.clock(rec.playhead) + " / " + rec.clock(rec.total)
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        // The tools.
        SquareButton {
            x: 16; y: 536.3
            icon: rec.trimming ? "delete-20" : "chevron-left-20"
            label: rec.trimming ? "Delete this clip. Your recording will be lost." : "Back"
            onClicked: {
                if (rec.trimming) { rec.trimming = false; rec.deleteSelected(); return }
                player.stop(); rec.playing = false; rec.reset()
            }
        }
        Row {
            visible: !rec.trimming
            anchors.horizontalCenter: parent.horizontalCenter; y: 526
            Tool {
                icon: "cut-20"; label: "Trim"
                enabledTool: rec.selected >= 0
                onClicked: { rec.playing = false; player.pause(); musicPlayer.pause(); const sg = rec.segments[rec.selected]; rec.trimStart = sg.start; rec.trimEnd = sg.end; player.source = sg.path; player.position = sg.start; rec.trimming = true }
            }
            Tool { icon: "split-vertical-20"; label: "Split"; spoken: "Split Clip"; enabledTool: rec.canSplit; onClicked: rec.splitAtPlayhead() }
            Tool { toolWidth: 71.9; icon: "delete-20"; label: "Delete clip"; spoken: "Delete this clip. Your recording will be lost."; onClicked: rec.deleteSelected() }
            Tool { toolWidth: 82; icon: "video-add-20"; label: "Record more"; onClicked: { player.pause(); rec.playing = false; musicPlayer.pause(); rec.stage = "setup" } }
            Tool {
                id: rearrangeTool
                visible: rec.segments.length > 1
                toolWidth: 70.2; icon: "arrow-swap-20"; label: "Rearrange"
                off: rearrangeMenu.opened
                onClicked: { const p = rearrangeTool.mapToItem(rec.contentItem, 0, 0); rearrangeMenu.x = p.x; rearrangeMenu.y = p.y - rearrangeMenu.height - 1; rearrangeMenu.open() }
            }
            Item { width: 20; height: 51.3; Rectangle { anchors.centerIn: parent; width: 0.67; height: 32; color: theme.divider } }
            Tool {
                toolWidth: rec.music ? Math.max(56, musicLabel.implicitWidth + 25) : 56
                icon: rec.music ? "data-bar-vertical-20" : "music-note-2-20"
                label: rec.music ? rec.music.name : "Music"
                spoken: rec.music ? "Add music Selected " + rec.music.name : "Add music"
                onClicked: { rec.playing = false; player.pause(); musicPlayer.pause(); musicPanel.visible = true }
                Text { id: musicLabel; visible: false; text: rec.music ? rec.music.name : ""; font.family: theme.font; font.pixelSize: 10 }
            }
        }
        MenuPopup {
            id: rearrangeMenu
            items: [{ label: "Move left", enabled: rec.selected > 0 }, { label: "Move right", enabled: rec.selected >= 0 && rec.selected < rec.segments.length - 1 }]
            onPicked: i => rec.moveSelected(i === 0 ? -1 : 1)
        }
        SquareButton {
            x: 752; y: 536.3; primary: true
            icon: rec.trimming ? "checkmark-20" : "chevron-right-20"
            label: rec.trimming ? "Confirm trim" : "Continue"
            onClicked: {
                if (rec.trimming) {
                    const list = rec.segments.slice()
                    list[rec.selected] = Object.assign({}, list[rec.selected], { start: Math.round(rec.trimStart), end: Math.round(rec.trimEnd) })
                    rec.segments = list
                    rec.trimming = false
                    rec.seekTimeline(rec.segStartAt(rec.selected))
                    return
                }
                rec.finishClip()
            }
        }
    }
    property real trimStart: 0
    property real trimEnd: 0
    // Continue: the edit goes to the compose box (rendered there when it
    // was edited).
    function finishClip() {
        player.stop(); musicPlayer.stop(); playing = false
        const spec = editSpec()
        const first = segments[0].shots && segments[0].shots.length ? segments[0].shots[0] : (thumbPath ? "file://" + thumbPath : "")
        const clip = { path: untouched ? segments[0].path : "", spec: untouched ? null : spec, thumb: first, width: untouched ? (clipW || 1280) : 1280, height: untouched ? (clipH || 720) : 720, duration: Math.round(total) }
        // The parts' recordings now belong to the compose box.
        segments = []
        finished(clip)
        stage = "setup"
        close()
    }

    // ---- Music (Teams' Music panel: Microsoft Stream's library) ----
    readonly property string musicBase: "https://res.public.onecdn.static.microsoft/files/odsp-web-prod_2026-10-30.005/streamcameraembed/"
    readonly property var library: [
        { name: "Chill", cover: "images/chill_bf376ec6.png", songs: [["In a dream", "Dario Comuzzi, Paolo Catoni", "in_a_dream_bebabb7f"], ["Open field", "Keir Schmidt", "open_field_ce1cac4e"], ["Rain in Japan", "Dario Comuzzi, Claudio Tristano", "rain_in_japan_1d666880"], ["Supernova", "Dario Comuzzi, Claudio Tristano", "supernova_026875ac"], ["Waves", "Keir Schmidt", "waves_49f1aea6"]] },
        { name: "Energetic", cover: "images/energetic_64845ed2.png", songs: [["Bring up the energy", "Philip Anderson", "bring_up_the_energy_4ce0710c"], ["By the shoreline", "Dario Comuzzi, Claudio Tristano", "by_the_shoreline_1ded4322"], ["Feelin' fresh", "Nancy Louise Lee", "feelin_fresh_ac86f5f0"], ["Get excited", "Joseph Capalbo", "get_excited_abc9da1a"], ["Pump it up", "Prong Praison", "pump_it_up_8c1abf13"]] },
        { name: "Fun", cover: "images/fun_8e188be4.png", songs: [["Block party", "Dario Comuzzi, Paolo Catoni", "block_party_14e4d31d"], ["Chill and wavey", "Dario Comuzzi, Paolo Catoni", "chill_and_wavey_a8d04d78"], ["Cloud walk", "Prong Praison", "cloud_walk_5d05ac98"], ["Fearless funk", "Nancy Louise Lee", "fearless_funk_e9c6e8e0"], ["Laid back vibe", "Philip Anderson", "laid_back_vibe_9c992a9d"], ["Liquid", "Philip Anderson", "liquid_afae8da8"], ["Spectra", "Joseph Capalbo", "spectra_83927b63"], ["The bounce", "Dario Comuzzi, Paolo Catoni", "the_bounce_df96a30f"]] },
        { name: "High Tech", cover: "images/high_tech_b3672869.png", songs: [["Awakenings", "Dario Comuzzi, Paolo Catoni", "awakenings_8ad3f4ed"], ["Closed circuits", "Philip Anderson", "closed_circuits_68d3b36e"], ["Cutting edge", "Philip Anderson", "cutting_edge_0b882323"], ["Isotope", "Nancy Louise Lee", "isotope_671ef6b9"], ["Tinkering", "Keir Schmidt", "tinkering_f88de5a4"]] },
        { name: "Inspiring", cover: "images/inspiring_b3672869.png", songs: [["Driving force", "Nancy Louise Lee", "driving_force_8c84bafa"], ["Morning coffee", "", "morning_coffee_91eed28f"]] }
    ]
    function pickSong(cat, song) {
        const url = musicBase + "audio/" + song[2] + ".aac"
        music = { id: song[2], name: song[0], artist: song[1], url: url, cover: musicBase + cat.cover, path: "", level: music ? music.level : 15 }
        backend.fetchMusic(url)
        songPreview.stop()
        musicPanel.visible = false
    }
    Connections {
        target: backend
        function onMusicReady(url, path) {
            if (!rec.music || rec.music.url !== url) return
            if (!path) { rec.music = null; return }
            rec.music = Object.assign({}, rec.music, { path: path })
            if (rec.stage === "review") { rec.seekTimeline(0); rec.togglePlay() }
        }
    }
    Rectangle {
        id: musicPanel
        visible: false
        x: 152; y: 240.3; width: 496; height: 323.3; radius: 8
        color: theme.surface
        FluentSurface { z: -1; anchors.fill: parent; depth: 16; radius: 8 }
        MouseArea { anchors.fill: parent }
        Text { x: 64.7; y: 24.6; width: 358.7; height: 20; horizontalAlignment: Text.AlignHCenter; text: "Music"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        HeadButton { x: 447.3; y: 14.6; height: 40; icon: "dismiss-20"; label: "Close Music"; onClicked: { songPreview.stop(); musicPanel.visible = false } }
        Row {
            x: 22.7; y: 65.6; spacing: 0
            Repeater {
                model: rec.library
                Item {
                    required property var modelData
                    required property int index
                    width: tabText.implicitWidth + 12 + (index < rec.library.length - 1 ? 30 : 0); height: 32
                    Text { id: tabText; x: 6; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: musicList.section === parent.index ? Font.DemiBold : Font.Normal; color: theme.text }
                    Rectangle { visible: musicList.section === parent.index; x: 6; y: 30; width: tabText.implicitWidth; height: 2; radius: 1; color: theme.brand }
                    TapHandler { onTapped: musicList.contentY = musicList.sectionY[parent.index] }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.name
                }
            }
        }
        Flickable {
            id: musicList
            x: 16.7; y: 108; width: 462.7; height: rec.music ? 158 : 200
            contentHeight: musicCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            property var sectionY: []
            readonly property int section: { let k = 0; for (let i = 0; i < sectionY.length; i++) if (contentY + 4 >= sectionY[i]) k = i; return k }
            Column {
                id: musicCol
                width: parent.width
                Repeater {
                    model: rec.library
                    Column {
                        id: catCol
                        required property var modelData
                        required property int index
                        width: musicCol.width
                        Component.onCompleted: Qt.callLater(() => { const ys = musicList.sectionY.slice(); ys[index] = catCol.y; musicList.sectionY = ys })
                        onYChanged: { const ys = musicList.sectionY.slice(); ys[index] = y; musicList.sectionY = ys }
                        Text { x: 2; height: 32; verticalAlignment: Text.AlignVCenter; text: catCol.modelData.name; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                        Flow {
                            width: parent.width; spacing: 16
                            topPadding: 0; bottomPadding: 16
                            Repeater {
                                model: catCol.modelData.songs
                                Item {
                                    id: song
                                    required property var modelData
                                    readonly property bool chosen: !!rec.music && rec.music.id === modelData[2]
                                    readonly property string url: rec.musicBase + "audio/" + modelData[2] + ".aac"
                                    width: 207.3; height: 55
                                    Rectangle {
                                        x: 4; y: 4; width: 46; height: 46; radius: 4
                                        clip: true
                                        Image { anchors.fill: parent; source: rec.musicBase + catCol.modelData.cover; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                        FluentIcon { anchors.centerIn: parent; name: songPreview.url === song.url && songPreview.playbackState === MediaPlayer.PlayingState ? "pause-20-filled" : "play-20-filled"; size: 20; color: "white" }
                                        TapHandler {
                                            onTapped: {
                                                if (songPreview.url === song.url && songPreview.playbackState === MediaPlayer.PlayingState) { songPreview.stop(); return }
                                                songPreview.url = song.url; songPreview.source = song.url; songPreview.play()
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Play " + song.modelData[0] + (song.modelData[1] ? " by " + song.modelData[1] : "")
                                    }
                                    Column {
                                        x: 65; anchors.verticalCenter: parent.verticalCenter; width: 86
                                        Text { width: parent.width; text: song.modelData[0]; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                        Text { width: parent.width; text: song.modelData[1]; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                                    }
                                    Rectangle {
                                        x: 171.6; y: 11.5; width: 32; height: 32; radius: 4
                                        color: song.chosen ? "transparent" : addHover.hovered ? theme.menuHover : theme.surface
                                        border.color: song.chosen ? "transparent" : theme.stroke; border.width: 0.67
                                        FluentIcon { anchors.centerIn: parent; name: song.chosen ? "data-bar-vertical-20" : "add-20"; size: 20; color: theme.text }
                                        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { enabled: !song.chosen; onTapped: rec.pickSong(catCol.modelData, song.modelData) }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Download " + song.modelData[0]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // The chosen song: its name, its level and Remove.
        Rectangle {
            visible: !!rec.music
            y: parent.height - 60; width: parent.width; height: 60
            bottomLeftRadius: 8; bottomRightRadius: 8
            color: theme.surface
            Rectangle { width: parent.width; height: 0.67; color: theme.divider }
            Text { x: 20.7; anchors.verticalCenter: parent.verticalCenter; width: 180; elide: Text.ElideRight; text: rec.music ? rec.music.name : ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
            Row {
                x: 236.7; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "speaker-2-20"; size: 20; color: theme.text }
                Slider {
                    id: levelSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110; from: 0; to: 100; stepSize: 1
                    value: rec.music ? rec.music.level : 15
                    onMoved: if (rec.music) rec.music = Object.assign({}, rec.music, { level: Math.round(value) })
                    Accessible.name: "Active song volume"
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rec.music ? rec.music.level : ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
            }
            HeadButton { x: 433.3; y: 14.4; icon: "dismiss-20"; label: "Remove music"; onClicked: { rec.music = null; musicPlayer.stop() } }
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

    property bool saveAfterRender: false
    Connections {
        target: backend
        function onClipRendered(json) {
            if (!rec.saveAfterRender) return
            rec.saveAfterRender = false
            const r = JSON.parse(json)
            if (r.path) { backend.saveRecording(r.path); backend.removeRecorderFile(r.path) }
        }
    }
    // Test hooks (--recorder-test). `testSilent` records without the
    // microphone, so a test never captures the room.
    property bool testSilent: false
    function pickCameraForTest(name) { const c = devices.videoInputs.find(d => d.description === name); if (c) { cameraId = String(c.id); cameraOn = true } }
    function pauseForTest() { enginePause(); stage = "paused"; frameTimer.stop() }
    function resumeForTest() { engineResume(); stage = "recording"; frameTimer.start() }
    function continueForTest() { finishClip() }
    function editForTest() { return { segments: segments.map(sg => ({ start: sg.start, end: sg.end, length: sg.length })), selected: selected, playhead: playhead, total: total, canSplit: canSplit, music: music, trimming: trimming } }
    function teleprompterForTest(on, text, play) { teleprompter.visible = on; if (text !== undefined) { script = text; promptArea.load(text) } if (play !== undefined) teleprompter.playing = play; return { visible: teleprompter.visible, playing: teleprompter.playing, word: teleprompter.word, words: teleprompter.words.length, fontSize: promptSettings.fontSize, speed: promptSettings.speed, contentY: promptRead.contentY } }
    function toggleSpeed(on) { speedPop.x = speedBtn.mapToItem(teleprompter, 0, 0).x; speedPop.visible = on }
    function teleprompterSpeedForTest(on) { toggleSpeed(on); return { edit: promptArea.mapToItem(teleprompter, promptArea.positionToRectangle(0).x, 0).x, read: promptText.mapToItem(teleprompter, promptText.leftPadding, 0).x, pad: [promptArea.leftPadding, promptArea.topPadding, promptArea.leftInset] } }
    function teleprompterFontForTest(d) { promptSettings.fontSize = Math.max(24, Math.min(64, promptSettings.fontSize + d)) }
    function playerForTest() { return { status: player.mediaStatus, state: player.playbackState, pos: player.position, dur: player.duration, src: String(player.source).split("/").pop(), seg: playingSeg, pending: pendingPos, playing: playing, playhead: playhead, music: musicPlayer.playbackState } }
    function seekForTest(t) { playing = false; player.pause(); seekTimeline(t) }
    function trimForTest(a, b) { selected = Math.max(0, selected); const sg = segments[selected]; trimStart = a; trimEnd = b; trimming = true }
    function confirmTrimForTest() { const list = segments.slice(); list[selected] = Object.assign({}, list[selected], { start: Math.round(trimStart), end: Math.round(trimEnd) }); segments = list; trimming = false; seekTimeline(segStartAt(selected)) }
    function pickSongForTest(cat, idx) { pickSong(library[cat], library[cat].songs[idx]) }
    function musicPanelForTest(on) { musicPanel.visible = on }
    function stateForTest() { return { stage: stage, cameraOn: cameraOn, micOn: micOn, recordedMs: recordedMs, clip: String(clipPath), segments: segments.length, frames: shots.length, screen: screenMode, audio: audioMode, thumb: thumbPath, cams: devices.videoInputs.map(c => c.description), mics: devices.audioInputs.length, duration: player.duration, size: [clipW, clipH] } }
    function openCamMenuForTest() { camMenu.popupAt(camMenuBtn) }
    function openMicMenuForTest() { micMenu.popupAt(micMenuBtn) }
    function closeMenusForTest() { camMenu.close(); micMenu.close() }
}
