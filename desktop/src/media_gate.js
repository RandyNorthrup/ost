// Cameras for embedded web pages (every page in OST's web profile, every
// frame, from document creation, in the page's own world).
//
// Qt WebEngine's Chromium finds cameras by opening every /dev/video* node
// (V4L2) — not through PipeWire or the camera portal, as OST itself does —
// whenever a page lists its media devices or asks for a camera, and it does
// so before the permission is decided: a hosted app that only lists devices
// (Teams' Avatars app, as it starts) opened the laptop's camera for a moment
// with every camera off (TASK-0334). Teams grants a hosted app its camera,
// microphone and speakers together (the app's Media permission), so here:
// - enumerateDevices() goes to Chromium only once this page holds the camera
//   or microphone (a stream it was given, or a permission it was granted);
//   before that it gets the answer Chromium gives a page without permission,
//   one entry per kind with no id or label, and nothing is opened;
// - devicechange listeners wait (kept here) until then too: adding one makes
//   Chromium list the devices at once;
// - getUserMedia() asking for video is refused (NotAllowedError, as a refusal
//   reads) unless the app's Media permission is on: the view marks its pages
//   (window.__ostMediaApp, WebApp.qml); OST's permission handler still
//   decides every request that gets through (WebApp.qml decidePermission).
// Microphone-only requests don't touch cameras and go through as they are.
// Each window (realm) has its own MediaDevices: the page's, and those of
// frames a page makes and reaches into before any script of ours runs there
// (an about:blank frame it lists devices in), gated as the page reaches them.
(() => {
    const LOG = typeof __OST_MEDIA_LOG !== "undefined" && __OST_MEDIA_LOG;
    const install = (win, how) => {
        let md;
        try {
            if (win.__ostMediaGate || !win.MediaDevices || !win.navigator.mediaDevices) return;
            md = win.navigator.mediaDevices;
            Object.defineProperty(win, "__ostMediaGate", { value: true });
        } catch (e) {
            return;
        }
        // (The console as it is now: pages may silence theirs later.)
        const warn = win.console.warn.bind(win.console);
        const log = (what, answer) => { if (LOG) warn("OSTMEDIA " + win.location.origin + " " + what + " -> " + answer) };
        log("installed " + how, String(win.location.href).slice(0, 80));
        const proto = win.MediaDevices.prototype;
        const enumerate = proto.enumerateDevices;
        const getUserMedia = proto.getUserMedia;
        // This page was given a stream from a camera or microphone.
        let given = false;
        const state = name => win.navigator.permissions.query({ name }).then(s => s.state, () => "prompt");
        const holds = () => given ? Promise.resolve(true)
            : Promise.all([state("camera"), state("microphone")]).then(s => s.includes("granted"));
        // Listening for devicechange makes Chromium list the devices at once
        // (to compare later lists with), so a page's devicechange listeners
        // are kept here until it holds the camera or microphone, then handed
        // to Chromium (Teams' Avatars app listens as it starts).
        const et = win.EventTarget.prototype;
        const held = [];
        let heldHandler = null;
        let open = false;
        const ondc = Object.getOwnPropertyDescriptor(proto, "ondevicechange");
        const release = () => {
            if (open) return;
            open = true;
            for (const a of held.splice(0)) et.addEventListener.apply(md, a);
            if (heldHandler && ondc && ondc.set) ondc.set.call(md, heldHandler);
            heldHandler = null;
            log("devicechange listeners", "handed over");
        };
        const own = (name, value) => Object.defineProperty(md, name, { value, writable: true, configurable: true });
        own("addEventListener", function (type, listener, options) {
            if (this === md && type === "devicechange" && !open) {
                if (listener && !held.some(a => a[1] === listener)) held.push([type, listener, options]);
                log("addEventListener devicechange", "held");
                return;
            }
            return et.addEventListener.apply(this, arguments);
        });
        own("removeEventListener", function (type, listener) {
            if (this === md && type === "devicechange" && !open) {
                const i = held.findIndex(a => a[1] === listener);
                if (i >= 0) held.splice(i, 1);
                return;
            }
            return et.removeEventListener.apply(this, arguments);
        });
        if (ondc && ondc.set) {
            Object.defineProperty(md, "ondevicechange", {
                configurable: true,
                get() { return open ? ondc.get.call(md) : heldHandler; },
                set(v) { if (open) ondc.set.call(md, v); else { heldHandler = typeof v === "function" ? v : null; log("ondevicechange", "held"); } }
            });
        }
        // A page that already holds them (a permission granted before).
        holds().then(ok => { if (ok) release(); });
        // Chromium's answer to a page without permission (each kind once, no
        // id, group or label).
        const placeholder = () => ["audioinput", "videoinput", "audiooutput"].map(kind => {
            const p = kind === "audiooutput" || !win.InputDeviceInfo ? win.MediaDeviceInfo.prototype : win.InputDeviceInfo.prototype;
            const fields = { deviceId: "", kind, label: "", groupId: "" };
            const o = Object.create(p);
            for (const [k, v] of Object.entries(fields)) Object.defineProperty(o, k, { value: v, enumerable: true });
            Object.defineProperty(o, "toJSON", { value: () => Object.assign({}, fields) });
            if (p !== win.MediaDeviceInfo.prototype) Object.defineProperty(o, "getCapabilities", { value: () => ({}) });
            return o;
        });
        const wantsVideo = c => !!(c && c.video);
        // The app's Media permission is on (WebApp.qml marks the view's
        // frames; a frame made by script goes by its maker's mark).
        const appAllows = () => window.__ostMediaApp === true || win.__ostMediaApp === true;
        const denied = () => new win.DOMException("Permission denied", "NotAllowedError");
        const wrap = (name, fn) => {
            Object.defineProperty(fn, "name", { value: name });
            Object.defineProperty(proto, name, { value: fn, writable: true, configurable: true, enumerable: true });
        };
        wrap("enumerateDevices", function () {
            if (this !== md) return enumerate.apply(this, arguments);
            return holds().then(ok => {
                log("enumerateDevices", ok ? "devices" : "placeholder");
                if (ok) release();
                return ok ? enumerate.call(md) : placeholder();
            });
        });
        wrap("getUserMedia", function (constraints) {
            if (this !== md) return getUserMedia.apply(this, arguments);
            if (wantsVideo(constraints) && !appAllows()) {
                log("getUserMedia video", "refused");
                return Promise.reject(denied());
            }
            log("getUserMedia " + (wantsVideo(constraints) ? "video" : "audio"), "asked");
            return getUserMedia.call(md, constraints).then(s => { given = true; release(); return s; });
        });
        // The old callback forms.
        for (const name of ["getUserMedia", "webkitGetUserMedia"]) {
            const old = win.navigator[name];
            if (typeof old !== "function") continue;
            Object.defineProperty(win.navigator, name, {
                configurable: true, writable: true,
                value: function (constraints, ok, fail) {
                    if (wantsVideo(constraints) && !appAllows()) {
                        log(name + " video", "refused");
                        if (typeof fail === "function") win.setTimeout(() => fail(denied()), 0);
                        return;
                    }
                    return old.call(win.navigator, constraints, s => { given = true; release(); if (typeof ok === "function") ok(s) }, fail);
                }
            });
        }
        // Frames this window makes: gated when the page first reaches their
        // window or document.
        const hooks = [["HTMLIFrameElement", "contentWindow", w => w], ["HTMLIFrameElement", "contentDocument", d => d && d.defaultView],
                       ["HTMLFrameElement", "contentWindow", w => w], ["HTMLObjectElement", "contentWindow", w => w]];
        for (const [type, prop, toWin] of hooks) {
            const T = win[type];
            const d = T && Object.getOwnPropertyDescriptor(T.prototype, prop);
            if (!d || !d.get) continue;
            Object.defineProperty(T.prototype, prop, {
                configurable: true, enumerable: d.enumerable,
                get() {
                    const v = d.get.call(this);
                    try { const w = toWin(v); if (w) install(w, "child"); } catch (e) {}
                    return v;
                }
            });
        }
    };
    install(window, "page");
})();
