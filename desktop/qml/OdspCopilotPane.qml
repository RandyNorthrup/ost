import QtQuick
import QtQuick.Controls.Basic
import QtWebEngine

// OneDrive's Copilot pane (Home ▸ For you ▸ Summarize / Recap this
// meeting), as Teams' OneDrive app opens it (measured on winpc 2026-11-26,
// TASK-0340): OneDrive's own chat page (`{your OneDrive}/_layouts/15/
// chat.aspx?app=OneDriveForBusiness&chatodsp={…}`) in a 400 px card at the
// files' right (12 from the top and bottom, 16 from the right), over the
// files. The page draws everything itself: its header ("Copilot", ···,
// Close), the file's chip, the prompt and Copilot's answer, the suggested
// prompts, "Message Copilot" and "AI-generated content may be incorrect".
//
// Teams' OneDrive is the page's host, as OST is here: a page of
// SharePoint's origin frames chat.aspx, and they talk over OneDrive's SDK
// messenger (identify-parent, initialize with a port, activate; then
// command / acknowledge / result). The host tells the page which file and
// prompt (showView, updateInstruction, updateHeader, updateDataSources,
// updateChatInput, updateCustomPrompts, setPrompt with autoSubmit), and
// answers its fetchAuthToken with tokens OST gets for Microsoft's
// services (backend "odspToken"). The host script runs in an isolated
// world and reaches OST through console lines carrying a nonce the page
// can't read; tokens go back through runJavaScript and are never logged.
FluentSurface {
    id: pane
    radius: 12; depth: 16; color: theme.surface
    visible: open
    property bool open: false
    /// The page's state: "", "loading", "ready" (messenger up), "asked"
    /// (the prompt sent), "failed".
    property string state_: ""
    property var source: null
    property string prompt: ""
    property string fileName: ""
    property string mySite: ""
    property string webUrl: ""
    /// Teams' configure options (chat settings, Fluent theme), from the backend.
    property var configure: ({})
    property var commandsSeen: []
    property bool framed: false
    readonly property string tag: "odspchat" + Math.floor(Math.random() * 1e9).toString(36)
    readonly property string nonce: "ostodsp" + Math.floor(Math.random() * 1e12).toString(36) + Math.floor(Math.random() * 1e12).toString(36)
    property string channelId: ""
    signal closed()

    /// Summarize / Recap: ask for the file's data source, then open the
    /// page (or, already open, tell it the new file and prompt).
    function ask(driveId, itemId, name, text) {
        fileName = name; prompt = text; open = true
        backend.eventsRequest("odspChatSource", tag, JSON.stringify({ drive_id: driveId, item_id: itemId }))
        console.info("ODSPCHAT ask")
    }
    function close() { open = false; closed() }

    // OneDrive's instruction and prompts as its host sends them (captured
    // 2026-11-26).
    readonly property string instruction: "Copilot can assist by generating content in chat, such as text, outlines, tables, summaries, drafts, or slide content. Copilot does not create, upload, send, download, or modify files, and does not provide downloadable artifacts or direct file links. When users ask to create or update a file (such as a Word document, Excel spreadsheet, PowerPoint presentation, or PDF), Copilot should provide the requested content inline in the conversation and can include brief guidance on how the user may create or apply it within their own apps. If users ask to send emails, Copilot can generate a draft (subject and body) for copy and paste. If users ask to combine or edit file content, Copilot can present the revised or combined content inline for the user to apply manually. For tabular or slide‑based requests, Copilot may present structured tables or slide outlines that are ready to paste into their respective apps. When users ask about deleting files: Files must be deleted from the \"My files\" view rather than the \"Home\" view. Shared files can only be deleted by their owner. Users may hide shared files from their own view if needed."
    function prompts() {
        const s = (t, icon) => ({ suggestionText: t, inputAreaText: t, iconRegular: { name: icon, style: "Regular" }, iconHover: { name: icon, style: "Regular" } })
        const cat = (text, icon, items, extra) => Object.assign({ nodeType: "Category", text: text, iconRegular: { name: icon, style: "Regular" }, iconHover: { name: icon, style: "Filled" },
                                                                  children: items.map(t => ({ nodeType: "ActionSet", text: t })) }, extra || {})
        return {
            zeroQueryPrompts: { headerText: "Ask a question or get started with one of these examples:",
                                promptSuggestionList: [s("Summarize this file", "Notepad"), s("Create an FAQ from this file", "ChatBubblesQuestion"), s("Suggest next steps from this file ", "ChatBubblesQuestion")] },
            promptGuide: { promptGuideMenuData: { nodeType: "Root", text: "Prompt guide", children: [
                cat("Summarize", "Notepad", ["Summarize this file", "List the 3 key points from this file", "Draft an email based on a summary of this file"], { promptCategory: "Summarize" }),
                cat("Ask", "ChatBubblesQuestion", ["Create an FAQ from this file", "Compare the differences between these files", "Suggest ways to improve the content in this file",
                                                   "Suggest the next steps from this file", "Create an FAQ in the style of a podcast from this file",
                                                   "What does this file say about [roles and responsibilities?]"])] } }
        }
    }
    function telemetry() {
        return { ChatODSPLaunchOrigin: "summarize", ChatODSPScenarios: "SummarizeAction", ChatODSPUserClickTimestamp: Date.now(),
                 ChatODSPCurrentView: "Home", ChatODSPLaunchOriginScenario: "SummarizeAction", ChatODSPChatType: "AppChat" }
    }
    function chatUrl() {
        const opts = {
            sdk: "1.0.0",
            messaging: { origin: "https://" + mySite, channelId: channelId, identifyParent: true, waitForConfiguration: true },
            authentication: { enabled: true, claimsChallenge: { enabled: true },
                              tokens: { augloop: true, msGraph: true, sharePoint: true, powerPlatform: true, ocps: true, msSubstrateTenantFeedback: true, msSubstrate: true } },
            telemetry: { sessionId: Qt.md5(String(Math.random())).slice(0, 8) + "-" + Qt.md5(String(Date.now())).slice(0, 4), hostApp: "TeamsFile.Teams.File.FileBrowser", timestamp: Date.now() }
        }
        if (webUrl) opts.webAbsoluteUrl = webUrl
        return "https://" + mySite + "/_layouts/15/chat.aspx?app=OneDriveForBusiness&chatodsp=" + encodeURIComponent(JSON.stringify(opts))
    }
    // The host's side of OneDrive's messenger (isolated world).
    function hostScript() {
        return "(() => { if (window.__ostOdsp) return; const nonce = " + JSON.stringify(nonce) + ", channelId = " + JSON.stringify(channelId) + ";"
            + " const toHost = o => console.log(nonce + JSON.stringify(o));"
            + " const f = document.createElement('iframe'); f.title = 'Copilot'; f.allow = 'clipboard-read; clipboard-write; microphone';"
            + " f.style.cssText = 'display:block;border:0;width:100%;height:100%;';"
            + " let port = null, next = 0, identify = null;"
            + " const send = data => { if (port) port.postMessage({ type: 'command', id: 'h' + (++next), data }); };"
            + " window.__ostOdsp = { send, reply: (id, data) => { if (port) port.postMessage({ type: 'result', id, data }); } };"
            + " const onPort = m => { const d = m.data; if (!d || typeof d !== 'object') return;"
            + "  if (d.type === 'command') { port.postMessage({ type: 'acknowledge', id: d.id }); const c = d.data || {};"
            // (As Teams' OneDrive: the query goes on as it is; the
            // refresh token needs nothing from the host.)
            + "   if (c.command === 'preProcessQuery') port.postMessage({ type: 'result', id: d.id, data: { result: 'success', preProcessedQuery: c.query } });"
            + "   else if (c.command === 'hydrateAadRefreshToken') port.postMessage({ type: 'result', id: d.id, data: { result: 'success' } });"
            + "   toHost({ event: 'command', id: d.id, command: c.command || '', kind: c.type || '', resource: c.resource || '' }); }"
            + "  else if (d.type === 'notification') toHost({ event: 'notification', name: (d.data && d.data.notification) || '' }); };"
            + " addEventListener('message', e => { if (e.source !== f.contentWindow) return; const d = e.data;"
            + "  if (d && d.type === 'initialize' && d.channelId === channelId && d.replyTo) { clearInterval(identify); port = d.replyTo;"
            + "   port.onmessage = onPort; port.postMessage({ type: 'activate' }); toHost({ event: 'ready' }); }"
            + "  else if (d && d.type === 'chat-pane-ready') toHost({ event: 'paneReady' }); });"
            + " f.addEventListener('load', () => { clearInterval(identify); identify = setInterval(() => { if (port) return clearInterval(identify);"
            + "  try { f.contentWindow.postMessage({ type: 'identify-parent', channelId }, location.origin); } catch (e) {} }, 250); });"
            + " f.src = " + JSON.stringify(chatUrl()) + "; document.body.appendChild(f); toHost({ event: 'framed' }); })()"
    }
    function send(data) { web.runJavaScript("window.__ostOdsp && window.__ostOdsp.send(" + JSON.stringify(data) + ")", WebEngineScript.ApplicationWorld) }
    function reply(id, data) { web.runJavaScript("window.__ostOdsp && window.__ostOdsp.reply(" + JSON.stringify(id) + ", " + JSON.stringify(data) + ")", WebEngineScript.ApplicationWorld) }
    // As Teams' OneDrive: the view, the instruction and the header first;
    // the file, the input's words, the prompts and the prompt itself once
    // the chat says it is ready.
    function sendStart() {
        send({ command: "showView", view: "chat" })
        send({ command: "updateInstruction", instruction: instruction })
        send({ command: "updateHeader", header: { hideIcon: false, showCloseButton: true, showCopilotPickerMenu: false } })
        send({ command: "updateTelemetryExtraData", telemetryExtraData: telemetry() })
        send({ command: "updateTelemetryManagerContext", context: { context: { Scenario: "ChatPane" } } })
    }
    property bool promptSent: false
    function sendPrompt() {
        if (promptSent || !source || state_ === "" || state_ === "loading") return
        promptSent = true
        send({ command: "updateDataSources", dataSources: [source] })
        send({ command: "updateChatInput", chatInput: { placeholder: "Ask a question about \"" + fileName + "\"", isDisabled: false } })
        send({ command: "updateCustomPrompts", customPrompts: prompts() })
        send({ command: "setPrompt", prompt: prompt, autoSubmit: true })
        state_ = "asked"
        console.info("ODSPCHAT prompt sent")
    }
    Timer { id: readyWait; interval: 15000; onTriggered: pane.sendPrompt() }

    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id !== pane.tag) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) { v = { error: "bad reply" } }
            if (v.error || !v.source || !v.my_site) { pane.state_ = "failed"; console.warn("ODSPCHAT source: " + (v.error || "none")); return }
            pane.source = v.source
            pane.promptSent = false
            // Already up: the new file and prompt go to the same chat.
            if (pane.state_ === "ready" || pane.state_ === "asked") { pane.state_ = "ready"; pane.sendStart(); pane.sendPrompt(); return }
            pane.mySite = v.my_site; pane.webUrl = v.web_url || ""; pane.configure = v.configure || ({})
            pane.channelId = "ChatODSP-" + Qt.md5(String(Math.random()) + Date.now()).replace(/^(.{8})(.{4})(.{4})(.{4})(.{12}).*$/, "$1-$2-$3-$4-$5")
            pane.state_ = "loading"; pane.framed = false
            web.loadHtml("<!doctype html><html lang=\"en-us\"><head><meta charset=\"utf-8\"><title>Copilot</title>"
                         + "<style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent}</style></head><body></body></html>",
                         "https://" + pane.mySite + "/_layouts/15/ostchathost.aspx")
        }
        function onAppHostReply(id, json) {
            if (id.indexOf(pane.tag + ":") !== 0) return
            const cid = id.slice(pane.tag.length + 1)
            let v = {}
            try { v = JSON.parse(json) } catch (e) { v = {} }
            pane.reply(cid, v.token ? { result: "success", authToken: v.token }
                                    : { result: "error", isExpected: false, error: { code: "tokenFailed", message: v.error || "No token" } })
        }
    }

    // The page fills the card (its own header and Close included).
    WebEngineView {
        id: web
        anchors.fill: parent
        anchors.margins: 1
        backgroundColor: "transparent"
        Component.onCompleted: profile = webAppsProfile.instance()
        onLoadingChanged: r => {
            if (r.status === WebEngineView.LoadSucceededStatus && pane.state_ === "loading" && !pane.framed) {
                pane.framed = true
                web.runJavaScript(pane.hostScript(), WebEngineScript.ApplicationWorld)
            } else if (r.status === WebEngineView.LoadFailedStatus && pane.state_ === "loading") pane.state_ = "failed"
        }
        onJavaScriptConsoleMessage: (level, message, line, sourceId) => {
            if (message.indexOf(pane.nonce) !== 0) return
            let m = {}
            try { m = JSON.parse(message.slice(pane.nonce.length)) } catch (e) { return }
            if (m.event === "ready") {
                console.info("ODSPCHAT messenger up")
                pane.state_ = "ready"
                // First the page's options, as Teams' OneDrive sends them.
                const url = pane.chatUrl()
                const opts = JSON.parse(decodeURIComponent(url.slice(url.indexOf("chatodsp=") + 9)))
                pane.send({ command: "configure", options: Object.assign({}, pane.configure, opts) })
                readyWait.restart()
            } else if (m.event === "paneReady") {
                pane.sendPrompt()
            } else if (m.event === "command") {
                if (pane.commandsSeen.indexOf(m.command) < 0) { pane.commandsSeen = pane.commandsSeen.concat([m.command]); console.info("ODSPCHAT command " + m.command + (m.kind ? " " + m.kind : "")) }
                if (m.command === "fetchAuthToken")
                    backend.appHostRequest("", "", "", "", "odspToken", pane.tag + ":" + m.id, JSON.stringify({ type: m.kind, resource: m.resource }))
                else if (m.command === "preProcessQuery" || m.command === "hydrateAadRefreshToken") return
                else if (/close|dismiss/i.test(m.command)) { pane.reply(m.id, { result: "success" }); pane.close() }
                else pane.reply(m.id, { result: "error", isExpected: true, error: { code: "unsupportedCommand", message: m.command } })
            } else if (m.event === "notification") {
                if (pane.commandsSeen.indexOf("~" + m.name) < 0) { pane.commandsSeen = pane.commandsSeen.concat(["~" + m.name]); console.info("ODSPCHAT notification " + m.name) }
                // The chat is up: the file and the prompt (Teams waits
                // for this too).
                if (m.name === "chat-loaded") { pane.sendStart(); pane.sendPrompt() }
                else if (/close|dismiss/i.test(m.name)) pane.close()
            }
        }
        // Only the host page loads in the view; the chat's links open in
        // the browser, as Teams opens them.
        onNavigationRequested: req => {
            if (!req.isMainFrame || /^(about:|data:)/.test(req.url.toString()) || /ostchathost\.aspx$/.test(req.url.toString())) return
            req.reject()
        }
        onNewWindowRequested: req => Qt.openUrlExternally(req.requestedUrl)
    }
    BusyIndicator { anchors.centerIn: parent; running: pane.open && (pane.state_ === "" || pane.state_ === "loading"); visible: running }
    Text {
        visible: pane.state_ === "failed"
        anchors.centerIn: parent; width: parent.width - 48; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
        text: qsTr("Something went wrong. Please try again.")
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    function stateForTest() { return { state: state_, commands: commandsSeen } }
}
