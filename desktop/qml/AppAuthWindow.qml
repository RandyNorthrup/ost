import QtQuick
import QtQuick.Window
import QtWebEngine

// An app's sign-in window for a link card (Teams' app-based link "Sign in",
// module 961755, opened by 24575 for 707715). Teams' own page opens it with
// `window.open(url, "appAuthWindow", "width=W, height=H")`, W and H taken
// from the address's own width / height parameters, after checking the
// address against the app's validDomains (434318's nL, 197100's F6).
//
// The sign-in page's TeamsJS talks to its opener by postMessage, so OST
// does it the same way: a hidden page with Teams' origin opens the window
// and answers it as Teams' auth window does:
// - only messages from the window count, and the first origin on one of
//   the app's validDomains is the only one listened to after that;
// - `initialize` gets ["authentication", "desktop"], `getContext` {};
// - `authentication.authenticate.success` (after initialize) closes it
//   with its result, which the link's app is asked again with
//   (value.state); `...failure` closes it as failed. The result goes on
//   as Teams' BotAuthResult (24575's T): an object as {type:
//   "JsonAuthResult", value: its JSON}, anything else as {type:
//   "StringAuthResult", value}.
// Closing the window is "CancelledByUser": the sign-in card stays and the
// app isn't asked again.
Window {
    id: win
    property string url: ""
    /// The app's validDomains.
    property var validDomains: []
    /// ok: signed in, with the window's result (Teams' BotAuthResult as JSON
    /// text); else why not ("CancelledByUser", "failed",
    /// "InvalidAuthUrl").
    signal finished(bool ok, string result)
    property bool done: false
    function finish(ok, result) {
        if (done) return
        done = true
        console.info("APPAUTH", ok ? "signed in" : result)
        finished(ok, result)
        if (visible) close()
    }
    readonly property var size_: {
        const q = s => { const m = new RegExp("[?&]" + s + "=(\\d+)").exec(url); return m ? parseInt(m[1]) : 0 }
        return [q("width") || 600, q("height") || 535]
    }
    width: size_[0]; height: size_[1]
    title: view.title
    color: theme.surface
    flags: Qt.Window
    onClosing: finish(false, "CancelledByUser")

    // Teams' F6: https on one of the domains, `*` for one label, without
    // case; Teams' local.teams.office.com always passes.
    readonly property string domainCheck: "const okDomain = (u, list) => { const esc = s => s.replace(/[.+?^${}()|[\\]\\\\]/g, '\\\\$&');"
        + " return list.concat(['local.teams.office.com']).some(d => { d = String(d || '').trim().replace(/^https:\\/\\//i, '').replace(/\\/$/, ''); if (!d) return false;"
        + " const w = d.split('*').map(esc).join('[^/^.]+'); return new RegExp('^https://' + w + '((/|\\\\?).*)?$', 'i').test(u) }) };"

    // The opener: Teams' side of the window, as 961755 runs it.
    readonly property string hostPage: "<!DOCTYPE html><html><head><meta charset='utf-8'></head><body><script>(() => {"
        + domainCheck
        // The address and domains come from the link's app: serialized so
        // nothing in them can end the script (backend.scriptJson).
        + " const url = " + backend.scriptJson(JSON.stringify(win.url)) + ", domains = " + backend.scriptJson(JSON.stringify(win.validDomains || [])) + ";"
        + " const say = o => console.log('OSTAUTH ' + JSON.stringify(o));"
        + " if (!okDomain(url, domains)) { say({ ok: false, result: 'InvalidAuthUrl' }); return }"
        + " const m = u => { const q = (s) => { const r = new RegExp('[?&]' + s + '=(\\\\d+)').exec(u); return r ? r[1] : '' }; return [q('width'), q('height')] };"
        + " const [w, h] = m(url);"
        + " const auth = window.open(url, 'appAuthWindow', (w ? 'width=' + w : '') + (w && h ? ', ' : '') + (h ? 'height=' + h : ''));"
        + " let origin = '', initialized = false;"
        + " window.addEventListener('message', ev => {"
        + "  if (!auth || ev.source !== auth) return;"
        + "  if (!origin) { if (!okDomain(ev.origin, domains)) return; origin = ev.origin } else if (ev.origin !== origin) return;"
        + "  const d = ev.data || {}; if (typeof d !== 'object') return;"
        + "  const reply = args => { if (d.id !== undefined) auth.postMessage({ id: d.id, args: args, origin: origin }, origin) };"
        + "  switch (d.func) {"
        + "  case 'initialize': initialized = true; reply(['authentication', 'desktop']); break;"
        + "  case 'getContext': reply([{}]); break;"
        + "  case 'authentication.authenticate.success': if (initialized) { const r = (d.args || [])[0];"
        + "   say({ ok: true, result: JSON.stringify(r && typeof r !== 'string' ? { type: 'JsonAuthResult', value: JSON.stringify(r) } : { type: 'StringAuthResult', value: r === undefined || r === null ? '' : r }) }) } break;"
        + "  case 'authentication.authenticate.failure': if (initialized) say({ ok: false, result: 'failed' }); break;"
        + "  }"
        + " });"
        + "})()</script></body></html>"

    WebEngineView {
        id: host
        width: 1; height: 1; visible: false
        onNewWindowRequested: request => request.openIn(view)
        onJavaScriptConsoleMessage: (level, message, line, source) => {
            if (message.indexOf("OSTAUTH ") !== 0) return
            let o = null
            try { o = JSON.parse(message.slice(8)) } catch (e) { return }
            win.finish(!!o.ok, String(o.result || ""))
        }
        Component.onCompleted: profile = webAppsProfile.instance()
    }
    WebEngineView {
        id: view
        anchors.fill: parent
        settings.javascriptCanOpenWindows: false
        // The page closing itself (window.close) ends the sign-in as Teams'
        // closed-window check does.
        onWindowCloseRequested: win.finish(false, "CancelledByUser")
        Component.onCompleted: profile = webAppsProfile.instance()
    }
    Component.onCompleted: if (url.indexOf("https://") === 0) host.loadHtml(hostPage, "https://teams.microsoft.com/v2/")
}
