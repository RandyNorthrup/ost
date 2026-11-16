import QtQuick
import QtWebEngine

// Teams' Filters (Frames, Styles) are Teams' Custom Filters video app: a
// web page (its videoAppContentUrl) that Teams hosts out of sight and feeds
// camera frames through TeamsJS' video API. OST hosts it the same way: this
// view loads the page with a TeamsJS host of its own (TeamsJS' frameless
// transport: window.nativeInterface / window.onNativeMessage), passes it
// camera frames as NV12 over a localhost WebSocket with a secret path
// (src/video_effects.rs) and sends the processed frames back the same way. Choosing a filter sends Teams'
// video.effectParameterChange with its id.
Item {
    id: host
    /// The chosen filter's id ("" for none).
    property string effectId: ""
    /// The app's page (from its app definition).
    property string appUrl: ""
    // Only once signed in: the app needs Teams' session.
    readonly property bool running: effectId.length > 0 && appUrl.length > 0 && backend.signedIn
    property bool ready: false
    width: 16; height: 16
    opacity: 0.01

    // The host goes in once a filter is first used (that starts OST's
    // frame socket).
    property bool hostAdded: false
    onRunningChanged: {
        ready = false
        backend.setVideoFilterActive(false)
        if (running && !hostAdded) {
            hostAdded = true
            const script = WebEngine.script()
            script.name = "ost-teamsjs-host"
            script.sourceCode = "window.ostSocket = " + JSON.stringify(backend.videoFilterSocket()) + ";\n" + host.shim
            script.injectionPoint = WebEngineScript.DocumentCreation
            script.worldId = WebEngineScript.MainWorld
            script.runsOnSubFrames = false
            web.userScripts.insert(script)
        }
        web.url = running ? appUrl : "about:blank"
    }
    /// Test hook: log what the next `n` frames look like after the app.
    function probe(n) { web.runJavaScript("window.ostProbe = " + n) }
    onEffectIdChanged: if (ready && effectId.length > 0) web.runJavaScript("window.ostSelectEffect(" + JSON.stringify(effectId) + ")")

    // The TeamsJS host, before the app's scripts run.
    // (A string: compiled QML keeps no function source to send.)
    readonly property string shim: `(function () {
        if (window.nativeInterface) return
        const log = (...a) => console.log("OSTVFX", ...a)
        const runtime = { apiVersion: 4, hostVersionsInfo: { adaptiveCardSchemaVersion: { majorVersion: 1, minorVersion: 5 } },
            isLegacyTeams: false, supports: { app: {}, appInstallDialog: {}, dialog: {}, pages: { appButton: {}, tabs: {}, config: {} },
            teamsCore: {}, video: { sharedFrame: {} } } }
        // After the SDK has registered its callback for the request.
        const send = data => setTimeout(() => window.onNativeMessage && window.onNativeMessage({ data }), 0)
        const reply = (id, args) => send({ id, args })
        let frames = false, busy = null
        window.ostReady = false
        window.ostProbe = 0
        window.ostSelectEffect = id => send({ func: "video.effectParameterChange", args: [id] })
        window.nativeInterface = {
            framelessPostMessage(json) {
                const m = JSON.parse(json)
                switch (m.func) {
                case "initialize":
                    log("initialize", JSON.stringify(m.args))
                    reply(m.id, ["sidePanel", "desktop", JSON.stringify(runtime), "2.23.0"]); break
                case "getContext":
                    reply(m.id, [{ frameContext: "sidePanel", hostClientType: "desktop", locale: "en-us", theme: "default", hostName: "Teams" }]); break
                case "video.registerForVideoFrame":
                    if (!frames) { frames = true; pump() }
                    window.ostReady = true
                    break
                case "video.videoFrameProcessed":
                    if (busy && busy.seq === m.args[0]) busy.done()
                    break
                case "video.videoEffectReadiness":
                    log("readiness", JSON.stringify(m.args)); break
                case "registerHandler":
                case "video.registerForVideoEffect":
                case "video.performance.performanceDataGenerated":
                case "video.performance.firstFrameProcessed":
                    break
                case "video.notifyError":
                    log("app error", JSON.stringify(m.args)); break
                default:
                    log("unhandled", m.func)
                    if (typeof m.id === "number") reply(m.id, [])
                }
            }
        }
        // Camera frames in, processed frames out, one at a time, over OST's
        // localhost socket.
        function pump() {
            const ws = new WebSocket(window.ostSocket)
            ws.binaryType = "arraybuffer"
            ws.onmessage = ev => {
                const buf = ev.data
                const head = new DataView(buf, 0, 16)
                const w = head.getUint32(0, true), h = head.getUint32(4, true), seq = Number(head.getBigUint64(8, true))
                const px = new Uint8ClampedArray(buf, 16)
                const probe = window.ostProbe > 0 ? px.slice() : null
                let sent = false
                const done = () => {
                    if (sent) return
                    sent = true
                    busy = null
                    if (probe) {
                        let changed = 0
                        for (let i = 0; i < px.length; i += 97) if (px[i] !== probe[i]) changed++
                        log("probe", w, h, seq, "changed samples", changed)
                        window.ostProbe--
                    }
                    if (ws.readyState === WebSocket.OPEN) ws.send(buf)
                }
                busy = { seq, done }
                send({ func: "video.newVideoFrame", args: [{ width: w, height: h, videoFrameBuffer: px, lumaStride: w, chromaStride: w,
                    lumaOffset: 0, chromaOffset: w * h, timestamp: seq }] })
                setTimeout(done, 500)
            }
            ws.onclose = () => setTimeout(pump, 500)
        }
    })()`

    WebEngineView {
        id: web
        anchors.fill: parent
        url: "about:blank"
        settings.webGLEnabled: true
        settings.localContentCanAccessRemoteUrls: false
        onJavaScriptConsoleMessage: (level, message, line, source) => {
            if (message.startsWith("OSTVFX") || level === WebEngineView.ErrorMessageLevel) console.warn("filter app:", message)
        }
        onLoadingChanged: req => { if (req.status === WebEngineView.LoadSucceededStatus) check.restart() }
    }
    // Once the app has asked for frames: choose the filter and open the
    // camera path to it.
    Timer {
        id: check
        interval: 250; repeat: true
        property int tries: 0
        onTriggered: web.runJavaScript("window.ostReady === true", ok => {
            if (ok) {
                stop()
                host.ready = true
                web.runJavaScript("window.ostSelectEffect(" + JSON.stringify(host.effectId) + ")")
                backend.setVideoFilterActive(true)
            } else if (++tries > 120) { stop(); console.warn("filter app: never asked for frames") }
        })
        onRunningChanged: if (running) tries = 0
    }
}
