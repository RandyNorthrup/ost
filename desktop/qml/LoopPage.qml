import QtQuick
import QtWebEngine
import QtWebChannel
import com.ost.desktop

// A Loop page as Teams hosts it (docs/spec/loop-host.md): Loop's own page
// container (Microsoft's, from res.cdn.office.net) in a same-origin frame
// of a host page that has Teams' origin, loaded with Fluid's container
// loader and Teams' host services (loop_host.js, in the page's main world),
// its tokens Teams' own from OST's sign-in through a bridge in an isolated
// world (loop_bridge.js). Used by a chat's Notes, a channel's Pages and
// the call window's meeting notes.
Item {
    id: root
    /// "fluidThread" (a chat's Notes), "channelPages" (a channel's Page) or
    /// "meetingNotes" (the call window's Notes).
    property string kind: "fluidThread"
    /// The page's link (its `nav` names the file); empty with `create`.
    property string componentUrl: ""
    /// Make a new page in `channel`'s folder (a channel's New page) and
    /// report its link (created).
    property bool create: false
    property string channel: ""
    /// A meeting's notes made here are named after the meeting (`title`).
    property string title: ""
    /// "loading", "ready" (rendered) or "error".
    property string state_: "loading"
    property string error: ""
    readonly property string hostId: "loop" + Math.floor(Math.random() * 1e9).toString(36) + Date.now().toString(36)
    /// What the host did (framed, code, rendered, created, connected,
    /// closed, error…), for the harness.
    property var events: []
    signal created(string componentUrl)
    signal failed(string message)
    readonly property string hostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    property string channelJs: ""
    property bool hostLoading: false
    property bool started: false
    /// The made page (a new one): componentUrl, driveId, itemId.
    property var createdInfo: null

    function reload() {
        state_ = "loading"; error = ""; events = []
        started = false
        web.loadHtml("", "about:blank")
        // A page this host made loads as the page it now is.
        if (create && createdInfo && createdInfo.componentUrl) { create = false; componentUrl = createdInfo.componentUrl }
        start()
    }
    function start() {
        if (started || !channelJs || (!componentUrl && !create)) return
        started = true
        backend.loopHostRequest("config", hostId + ":cfg", JSON.stringify({ kind: root.kind, mode: root.create ? "create" : "load", channel: root.channel, title: root.title }))
    }
    function stateForTest() { return JSON.stringify({ state: root.state_, error: root.error, events: root.events, url: root.componentUrl.split("?")[0] }) }
    function evalForTest(js, cb) { web.runJavaScript(js, cb) }
    // The harness types into the page as a person would (real keys), at
    // the end of its canvas, and reads its text back (--loop-test).
    KeyTyper { id: typer }
    function typeForTest(text) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument;"
            + " const c = d && [...d.querySelectorAll('[contenteditable=true]')].pop(); if (!c) return false; c.focus(); return true })()", ok => {
                if (!ok) { console.warn("LOOPHOST type: no canvas"); return }
                web.forceActiveFocus()
                typer.typeText("\u0001" + text)
            })
    }
    function textForTest(cb) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument; return d ? d.body.innerText.slice(0, 2000) : '' })()", cb)
    }

    QtObject {
        id: bridge
        WebChannel.id: "ost"
        property string config: ""
        readonly property string theme: root.hostTheme
        signal reply(string id, string json)
        function request(kind, id, json) {
            // Only what the Loop host may ask.
            if (["token"].indexOf(kind) < 0) return
            backend.loopHostRequest(kind, root.hostId + ":" + id, json)
        }
        function event(name, json) {
            root.events = root.events.concat([name])
            let d = {}
            try { d = JSON.parse(json) } catch (e) {}
            if (name === "error") console.warn("LOOPHOST", root.kind, "error", d.stage || "", (d.message || "").slice(0, 200))
            else console.info("LOOPHOST", root.kind, name)
            if (name === "rendered") root.state_ = "ready"
            else if (name === "error" || (name === "closed" && d.errorType)) { root.error = d.message || d.errorType || "error"; root.state_ = "error"; root.failed(root.error) }
            else if (name === "created" && d.componentUrl) { root.createdInfo = d; root.created(d.componentUrl) }
        }
    }
    WebChannel { id: channel; registeredObjects: [bridge] }
    Connections {
        target: backend
        function onLoopHostReply(id, json) {
            if (id === root.hostId + ":cfg") {
                let c = {}
                try { c = JSON.parse(json) } catch (e) {}
                if (c.error) { root.error = c.error; root.state_ = "error"; root.failed(c.error); return }
                c.mode = root.create ? "create" : "load"
                c.componentUrl = root.componentUrl
                c.theme = root.hostTheme
                c.iframeTitle = ""
                bridge.config = JSON.stringify(c)
                root.hostLoading = true
                web.loadHtml(backend.loopHostPage(), "https://teams.cloud.microsoft/")
            } else if (id.indexOf(root.hostId + ":") === 0) {
                bridge.reply(id.slice(root.hostId.length + 1), json)
            }
        }
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        settings.javascriptCanOpenWindows: true
        settings.javascriptCanAccessClipboard: true
        settings.javascriptCanPaste: true
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        webChannel: channel
        webChannelWorld: WebEngineScript.ApplicationWorld
        onLoadingChanged: req => {
            if (!root.hostLoading || req.status !== WebEngineView.LoadSucceededStatus) return
            root.hostLoading = false
            web.runJavaScript(root.channelJs + "\n" + backend.loopBridgeScript(), WebEngineScript.ApplicationWorld)
            web.runJavaScript(backend.loopHostScript(), WebEngineScript.MainWorld)
        }
        // The host page itself, then only the page's own frames (srcdoc,
        // https); links open in the browser.
        onNavigationRequested: req => {
            const u = req.url.toString()
            if (req.isMainFrame) {
                if (root.hostLoading || u === "about:blank") return
                req.reject()
                if (u.indexOf("https://") === 0) Qt.openUrlExternally(u)
                return
            }
            if (!/^(https:|about:|blob:|data:)/.test(u)) req.reject()
        }
        onNewWindowRequested: req => {
            const u = req.requestedUrl.toString()
            if (u.indexOf("https://") === 0) Qt.openUrlExternally(u)
        }
        onPermissionRequested: p => {
            if (p.permissionType === WebEnginePermission.PermissionType.ClipboardReadWrite) p.grant()
            else p.deny()
        }
    }

    // Covered until the page is drawn (Teams shows its loading page
    // meanwhile); the view itself stays shown so it keeps rendering.
    Rectangle { anchors.fill: parent; color: theme.surface; visible: root.state_ !== "ready" }
    Component.onCompleted: {
        web.profile = webAppsProfile.instance()
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            root.channelJs = x.responseText
            root.start()
        }
        x.open("GET", "qrc:///qtwebchannel/qwebchannel.js")
        x.send()
    }
    onComponentUrlChanged: start()
}
