import QtQuick
import QtQuick.Controls.Basic
import QtWebEngine
import com.ost.desktop

// Immersive Reader (a message's ··· ▸ More actions ▸ Immersive Reader), as
// Teams launches it (measured on Teams on the web 2026-11-16, docs/spec/
// app-host.md "Immersive Reader"): Microsoft's Immersive Reader SDK 0.8.0
// in Teams' window — a full-window white layer (position fixed, 100vw x
// 100vh, z-index 1000) framing learningtools.onenote.com's reader
// (`reader?exitCallback=ImmersiveReader-Exit&sdkPlatform=js&sdkVersion=0.8.0
// &cookiePolicy=disable&cognitiveAppId=Teams`, allow "autoplay;
// microphone"); when the reader posts ImmersiveReader-ReadyForContent the
// host posts it the content and Teams' own token for
// immersivereader.cloud.microsoft; ImmersiveReader-Exit (its back arrow)
// closes it. OST's host page has Teams' origin, as the reader's parent does
// in Teams; the script runs in an isolated world.
Popup {
    id: root
    parent: Overlay.overlay
    x: 0; y: 0
    width: parent ? parent.width : 0; height: parent ? parent.height : 0
    padding: 0; modal: true; focus: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle { color: "white" }
    property var chunks: []
    property string state_: ""
    readonly property string requestId: "ir" + Math.floor(Math.random() * 1e9).toString(36)
    function launch(c) {
        chunks = c
        state_ = "token"
        backend.appHostRequest("", "", "", "", "irToken", requestId, "{}")
    }
    function stateForTest() { return state_ }
    Connections {
        target: backend
        function onAppHostReply(id, json) {
            if (id !== root.requestId) return
            const token = JSON.parse(json).token || "anonymous"
            root.state_ = "loading"
            root.pendingToken = token
            root.open()
            web.loadHtml("<!doctype html><html lang=\"en-us\"><head><meta charset=\"utf-8\"><title>Immersive Reader</title></head><body style=\"margin:0\"></body></html>",
                         "https://teams.cloud.microsoft/")
        }
    }
    property string pendingToken: ""
    // The SDK's launch (launchAsync), from the token and content.
    function launchScript(token, chunks) {
        return "(() => { const token = " + JSON.stringify(token) + ", chunks = " + JSON.stringify(chunks) + ", start = Date.now();"
            + " const box = document.createElement('div');"
            + " box.style.cssText = 'position: fixed; width: 100vw; height: 100vh; left: 0px; top: 0px; border-width: 0px; perspective: 1px; z-index: 1000; background: white; overflow: hidden;';"
            + " const f = document.createElement('iframe'); f.allow = 'autoplay; microphone'; f.title = 'Immersive Reader Frame';"
            + " f.setAttribute('aria-modal', 'true'); f.setAttribute('allowfullscreen', '');"
            + " f.style.cssText = 'position: static; width: 100%; height: 100%; left: 0px; top: 0px; border-width: 0px;';"
            + " addEventListener('message', e => { if (e.source !== f.contentWindow || typeof e.data !== 'string') return;"
            + "  if (e.data === 'ImmersiveReader-ReadyForContent') f.contentWindow.postMessage(JSON.stringify({ messageType: 'Content', messageValue: {"
            + "   cogSvcsAccessToken: token, request: { chunks }, launchToPostMessageSentDurationInMs: Date.now() - start, sendPreferences: false,"
            + "   internalSdkUseAADBearerTokenForGcmCall: true } }), '*');"
            + "  else if (e.data === 'ImmersiveReader-Exit') document.title = 'ost-ir-exit';"
            + "  else if (e.data.indexOf('ImmersiveReader-LaunchResponse:') === 0) document.title = JSON.parse(e.data.slice(31)).success ? 'ost-ir-launched' : 'ost-ir-failed'; });"
            + " f.src = 'https://learningtools.onenote.com/learningtoolsapp/cognitive/reader?exitCallback=ImmersiveReader-Exit&sdkPlatform=js&sdkVersion=0.8.0&cookiePolicy=disable&cognitiveAppId=Teams';"
            + " box.appendChild(f); document.body.appendChild(box);"
            + " const st = document.createElement('style'); st.innerText = 'body{height:100%;overflow:hidden;}'; document.head.appendChild(st); })()"
    }
    onClosed: { web.loadHtml("", "about:blank"); state_ = ""; pendingToken = "" }
    contentItem: WebEngineView {
        id: web
        Component.onCompleted: profile = webAppsProfile.instance()
        onLoadingChanged: r => {
            if (r.status !== WebEngineView.LoadSucceededStatus || !root.pendingToken) return
            const t = root.pendingToken
            root.pendingToken = ""
            web.runJavaScript(root.launchScript(t, root.chunks), WebEngineScript.ApplicationWorld)
        }
        // Only the host page loads in the view itself.
        onNavigationRequested: req => {
            if (!req.isMainFrame || root.pendingToken || /^(about:|data:)/.test(req.url.toString())) return
            req.reject()
            if (/^https:\/\//.test(req.url.toString())) Qt.openUrlExternally(req.url)
        }
        onTitleChanged: {
            if (title === "ost-ir-exit") root.close()
            else if (title === "ost-ir-launched") root.state_ = "launched"
            else if (title === "ost-ir-failed") root.state_ = "failed"
        }
        // The reader's own links open in the browser, as elsewhere.
        onNewWindowRequested: req => Qt.openUrlExternally(req.requestedUrl)
    }
}
