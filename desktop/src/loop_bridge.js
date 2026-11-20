// OST's bridge for the Loop page host (loop_host.js): it runs in an
// isolated world of the host page, holds the web channel to OST (object
// `ost`) and passes the host's native calls (tokens) and events between it
// and the page's main world by window messages from this same window only.
// Tokens pass through here and are never logged.
(() => {
    if (window.__ostLoopBridge) return;
    window.__ostLoopBridge = true;
    let ost = null;
    let hello = false;
    const post = m => window.postMessage(Object.assign({ ostLoop: true }, m), location.origin);
    const sendConfig = () => { if (ost && hello) post({ dir: "config", json: ost.config }) };
    addEventListener("message", e => {
        const d = e.data;
        if (e.source !== window || !d || d.ostLoop !== true) return;
        if (d.dir === "hello") { hello = true; sendConfig() }
        else if (d.dir === "request" && ost && typeof d.id === "string" && typeof d.kind === "string") ost.request(d.kind, d.id, String(d.payload || "{}"));
        else if (d.dir === "event" && ost && typeof d.name === "string") ost.event(d.name, String(d.json || "{}"));
    });
    new QWebChannel(qt.webChannelTransport, channel => {
        ost = channel.objects.ost;
        ost.reply.connect((id, json) => post({ dir: "reply", id, json }));
        ost.themeChanged.connect(() => post({ dir: "theme", theme: ost.theme }));
        ost.askTitle.connect(() => post({ dir: "titleText" }));
        sendConfig();
    });
})();
