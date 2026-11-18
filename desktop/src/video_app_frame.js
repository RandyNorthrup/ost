// WebView2's texture streams, in a video app's frame on OST's TeamsJS host
// (docs/spec/call-and-meeting-window.md, Avatars). Teams desktop runs video
// apps such as Avatars on WebView2, whose `chrome.webview.getTextureStream`
// gives the app the stream Teams feeds and `registerTextureStream` takes
// the stream the app draws; TeamsJS uses them when the host supports
// `video.mediaStream`. Here the stream's frames come from the host page
// (app_host.js) by postMessage and the app's frames go back the same way.
// Runs in the app's own world, in frames of the app's origin under OST's
// host page only.
(() => {
    const APP_ORIGINS = ["https://mesh.public.onecdn.static.microsoft"];
    const HOST_ORIGIN = "https://teams.cloud.microsoft";
    if (!APP_ORIGINS.includes(location.origin)) return;
    const ancestors = location.ancestorOrigins ? Array.from(location.ancestorOrigins) : [];
    if (ancestors[0] !== HOST_ORIGIN || window.parent === window) return;
    if (!window.MediaStreamTrackGenerator || !window.MediaStreamTrackProcessor) return;
    const inputs = new Map();
    const webview = {
        async getTextureStream(streamId) {
            const generator = new MediaStreamTrackGenerator({ kind: "video" });
            inputs.set(streamId, generator.writable.getWriter());
            return new MediaStream([generator]);
        },
        async registerTextureStream(streamId, track) {
            const reader = new MediaStreamTrackProcessor({ track }).readable.getReader();
            for (;;) {
                const { value: f, done } = await reader.read();
                if (done) return;
                try {
                    const data = new ArrayBuffer(f.allocationSize());
                    await f.copyTo(data);
                    window.parent.postMessage({ ostTexture: "out", streamId, timestamp: f.timestamp, width: f.displayWidth, height: f.displayHeight,
                        format: f.format, data }, HOST_ORIGIN, [data]);
                } catch (e) {
                } finally {
                    f.close();
                }
            }
        },
        async unregisterTextureStream(streamId) {
            const w = inputs.get(streamId);
            inputs.delete(streamId);
            if (w) try { await w.close() } catch (e) {}
        }
    };
    window.chrome = window.chrome || {};
    window.chrome.webview = Object.assign(window.chrome.webview || {}, webview);
    addEventListener("message", e => {
        const d = e.data;
        if (e.source !== window.parent || e.origin !== HOST_ORIGIN || !d || d.ostTexture !== "in") return;
        const w = inputs.get(d.streamId);
        if (!w || !(d.data instanceof ArrayBuffer)) return;
        try {
            const f = new VideoFrame(d.data, { format: "NV12", codedWidth: d.width, codedHeight: d.height, timestamp: d.timestamp });
            w.write(f).catch(() => {});
        } catch (x) {}
    }, true);
    // Test runs (--avatar-test): what the page asks its Unity player to do
    // (object, method, the argument's start), the player's own log, what
    // it renders and loads, sent to the host page's log (the app replaces
    // the console with its telemetry buffer).
    if (window.__ostDebug) {
        const log = text => window.parent.postMessage({ ostTexture: "log", text: String(text).slice(0, 300) }, HOST_ORIGIN);
        let verboseUntil = 0;
        // What the page and its Unity player log about emotes and failures
        // (whatever console the page installs later).
        for (const k of ["log", "info", "warn", "error", "debug"]) {
            let cur = console[k];
            Object.defineProperty(console, k, { configurable: true,
                get() { return (...a) => { try { const t = a.map(x => typeof x === "string" ? x : (x && x.message) || String(x)).join(" "); if (Date.now() < verboseUntil || /emote|anim|fail|error|exception|abort|shader/i.test(t)) log(k + ": " + JSON.stringify(t).slice(0, 280)) } catch (e) {} return cur.apply(console, a) } },
                set(v) { cur = v } });
        }
        addEventListener("message", e => { const d = e.data; if (e.source === window.parent && d && typeof d.func === "string" && d.func.indexOf("meeting.") === 0) log("frame got " + d.func + " " + JSON.stringify(d.args || [])) }, true);
        const hook = setInterval(() => {
            const u = document._MeshGlobals && document._MeshGlobals.UnityHost && document._MeshGlobals.UnityHost.unityInstance;
            if (!u || !u.SendMessage) return;
            clearInterval(hook);
            log("unity ready");
            // The Unity player's own log (it goes to the app's telemetry
            // buffer, not the console).
            const h = document._MeshGlobals.LogAndErrorHandler;
            if (h) for (const k of ["globalHandleLog", "globalHandleWarning", "globalHandleError"]) {
                const orig = h[k];
                if (typeof orig !== "function") continue;
                h[k] = function (...a) { try { log("U." + k.slice(12) + " " + a.map(x => typeof x === "string" ? x : (x && x.message) || JSON.stringify(x)).join(" | ").slice(0, 280)) } catch (e) {} return orig.apply(this, a) };
            }
            // How often the app renders and applies visemes (Teams: about 30
            // renders a second).
            const I = u.Module && u.Module.AvatarRendererInterop;
            if (I) {
                let nr = 0, nv = 0;
                const r = I.Render, v = I.UpdateVisemeData;
                I.Render = function () { nr++; return r.apply(this, arguments) };
                I.UpdateVisemeData = function () { nv++; return v.apply(this, arguments) };
                setInterval(() => { log("renders " + nr + "/5s visemes " + nv + "/5s"); nr = 0; nv = 0 }, 5000);
            }
            // What it loads from now on (emote animations and the like).
            const f = window.fetch;
            window.fetch = function (input) {
                const url = String((input && input.url) || input).slice(0, 200);
                return f.apply(this, arguments).then(r => { log("fetch " + r.status + " " + url); return r }, e => { log("fetch failed " + url + " " + e); throw e });
            };
            const send = u.SendMessage.bind(u);
            u.SendMessage = (o, m, a) => { if (/Emote/.test(m)) verboseUntil = Date.now() + 8000; if (!/Viseme|Render/.test(m)) log("unity " + o + "." + m + " " + String(a === undefined ? "" : a).slice(0, 200)); return send(o, m, a) };
        }, 500);
    }
})();
