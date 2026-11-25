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
    /// "fluidThread" (a chat's Notes), "channelPages" (a channel's Page),
    /// "meetingNotes" (the call window's Notes), "compose" (a Loop
    /// component made in the compose box; `channel` is the conversation)
    /// or "message" (a Loop component in a message).
    property string kind: "fluidThread"
    /// The component's title as Loop reports it (Loop components).
    property string componentTitle: ""
    /// The component's app icon (its ComponentProperties.iconUrl, for a
    /// host header) and whether it is known yet: "pending", "known" (the
    /// address, or "" for none) or "failed".
    property string iconUrl: ""
    property string iconState: "pending"
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
    /// The component's title as Teams reads it when it is sent
    /// (requestTitle; "" when it has none or isn't drawn).
    signal titleText(string title)
    function requestTitle() { if (root.state_ === "ready") bridge.askTitle(); else root.titleText("") }
    /// The component's serialized content (Teams' getSerializedContentRef:
    /// ComponentSerializable.serialize()), as an event's highlights are
    /// published; ok false when it has none or isn't drawn.
    signal serialized(bool ok, string content)
    function requestSerialized() { if (root.state_ === "ready") bridge.askSerialized(); else root.serialized(false, "") }
    signal failed(string message)
    readonly property string hostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    property string channelJs: ""
    property bool hostLoading: false
    property bool started: false
    /// The made page (a new one): componentUrl, driveId, itemId.
    property var createdInfo: null

    function reload() {
        surface.hide()
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
    function evalForTest(js, cb) { if (backend.testHarness()) web.runJavaScript(js, cb) }
    // The harness types into the page as a person would (real keys), at
    // the end of its canvas, and reads its text back (--loop-test).
    KeyTyper { id: typer }
    function typeForTest(text) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument;"
            + " const c = d && ([...d.querySelectorAll('[contenteditable=true]')].pop() || d.querySelector('.scriptor-edit-context, [role=textbox]')); if (!c) return false; c.focus(); return true })()", ok => {
                if (!ok) { console.warn("LOOPHOST type: no canvas"); return }
                web.forceActiveFocus()
                typer.typeText("\u0001" + text)
            })
    }
    // The component's title ("Add a title": Loop's first editable line).
    function typeTitleForTest(text) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument;"
            + " const c = d && d.querySelector('[contenteditable=true]'); if (!c) return false; c.focus(); return true })()", ok => {
                if (!ok) { console.warn("LOOPHOST type: no title"); return }
                web.forceActiveFocus()
                typer.typeText(text)
            })
    }
    // Keys as they are typed, where the page's focus is (no Ctrl+End).
    function keysForTest(keys) { web.forceActiveFocus(); typer.typeText(keys) }
    // A link pasted where the page's cursor is, as the browser hands a
    // paste to the page (text and HTML), without the system clipboard.
    function pasteForTest(url) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument; const a = d && d.activeElement;"
            + " if (!a) return 'no focus'; const t = new f.contentWindow.DataTransfer(); const u = " + JSON.stringify(url) + ";"
            + " t.setData('text/plain', u); t.setData('text/html', '<a href=\"' + u.replace(/\"/g, '&quot;') + '\">' + u.replace(/</g, '&lt;') + '</a>');"
            + " const e = new f.contentWindow.ClipboardEvent('paste', { clipboardData: t, bubbles: true, cancelable: true }); a.dispatchEvent(e); return 'pasted ' + e.defaultPrevented })()",
            r => console.warn("LOOPHOST paste", r))
    }
    // `text` selected with the mouse, as a person drags across it (from its
    // end to its start with `backwards`: a press outside a selection, as
    // one inside it would drag the selected text).
    function selectByMouseForTest(text, backwards) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument; if (!d) return null;"
            + " const w = d.createTreeWalker(d.body, NodeFilter.SHOW_TEXT); let n; const t = " + JSON.stringify(text) + ";"
            + " while ((n = w.nextNode())) { const i = n.nodeValue.indexOf(t); if (i >= 0) { const r = d.createRange(); r.setStart(n, i); r.setEnd(n, i + t.length);"
            + " const b = r.getBoundingClientRect(), o = f.getBoundingClientRect(); return [o.left + b.left, o.top + b.top, b.width, b.height] } } return null })()", r => {
                if (!r) { console.warn("LOOPHOST select: text not found"); return }
                const z = web.zoomFactor, y = (r[1] + r[3] / 2) * z
                web.forceActiveFocus()
                if (backwards) typer.drag((r[0] + r[2]) * z + 3, y, r[0] * z, y)
                else typer.drag(r[0] * z + 1, y, (r[0] + r[2]) * z + 2, y)
            })
    }
    // Bold text in the page holding `text` (the harness's check).
    function boldForTest(text, cb) {
        web.runJavaScript("(() => { const f = document.querySelector('iframe'); const d = f && f.contentDocument; if (!d) return 'no page';"
            + " const w = d.createTreeWalker(d.body, NodeFilter.SHOW_TEXT); let n; const t = " + JSON.stringify(text) + ";"
            + " while ((n = w.nextNode())) if (n.nodeValue.indexOf(t) >= 0) { const el = n.parentElement; return el.tagName + ' ' + f.contentWindow.getComputedStyle(el).fontWeight } return 'not found' })()", cb)
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
        signal askTitle()
        signal askSerialized()
        /// To the host's commanding surface: {op: "exec", key, seq} or
        /// {op: "dismiss", seq}.
        signal commanding(string json)
        function request(kind, id, json) {
            // Only what the Loop host may ask.
            if (["token", "people"].indexOf(kind) < 0) return
            backend.loopHostRequest(kind, root.hostId + ":" + id, json)
        }
        function event(name, json) {
            root.events = root.events.concat([name])
            let d = {}
            try { d = JSON.parse(json) } catch (e) {}
            if (name === "error") console.warn("LOOPHOST", root.kind, "error", d.stage || "", (d.message || "").slice(0, 200))
            else if (name !== "commanding" && name !== "commandingDismiss") console.info("LOOPHOST", root.kind, name, name === "nested" || name === "code" || name === "commandingExecuted" ? json.slice(0, 200) : "")
            // Loop's formatting toolbar, drawn by OST over the page.
            if (name === "commanding") { surface.show(d, d.x * web.zoomFactor, d.y * web.zoomFactor); return }
            if (name === "commandingDismiss") { surface.hide(); return }
            if (name === "title") { root.componentTitle = d.title || ""; return }
            if (name === "icon") { console.info("LOOPHOST", root.kind, "icon", d.url ? d.url.split("?")[0].slice(0, 200) : d.failed ? "failed" : "none"); if (d.url || root.iconUrl === "") { root.iconUrl = d.url || ""; root.iconState = d.failed ? "failed" : "known" } return }
            if (name === "titleText") { root.titleText(String(d.title || "")); return }
            if (name === "serialized") { if (!d.ok) console.warn("LOOPHOST serialize", d.message || "nothing"); root.serialized(!!d.ok, String(d.content || "")); return }
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
                // Teams titles a Loop component's frame "Loop component".
                c.iframeTitle = root.kind === "compose" || root.kind === "message" ? qsTr("Loop component") : ""
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
        // The clipboard for Loop's own pages (Microsoft's hosts) only.
        onPermissionRequested: p => {
            if (p.permissionType === WebEnginePermission.PermissionType.ClipboardReadWrite && backend.loopClipboardAllowed(p.origin.toString())) p.grant()
            else p.deny()
        }
    }

    // Loop's formatting toolbar ("commanding surface"), as Teams draws it
    // over the frame (LoopCommandingSurface.qml).
    LoopCommandingSurface {
        id: surface
        view: web
        onExec: (key, seq) => bridge.commanding(JSON.stringify({ op: "exec", key: key, seq: seq }))
        onDismissed: seq => bridge.commanding(JSON.stringify({ op: "dismiss", seq: seq }))
    }
    function commandingForTest() { return surface.stateForTest() }
    function commandingPickForTest(id) { return surface.pickForTest(id) }

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
