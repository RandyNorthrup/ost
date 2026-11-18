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
    // The blank camera-less picture (a VideoFrame copies what it's made of).
    let blank = null;
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
                    const t = performance.now();
                    // NV12, after 20 bytes the host page fills in (its
                    // message head to OST), so the frame is copied once.
                    const w = f.displayWidth, h = f.displayHeight;
                    if (f.format !== "NV12") continue;
                    const data = new ArrayBuffer(20 + w * h * 3 / 2);
                    await f.copyTo(data, { rect: { x: 0, y: 0, width: w, height: h }, layout: [{ offset: 20, stride: w }, { offset: 20 + w * h, stride: w }] });
                    if (window.__ostCost) window.__ostCost.frameOut += performance.now() - t;
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
        if (!w || !(d.header instanceof ArrayBuffer)) return;
        try {
            // Teams' camera-less frame: the header rows over a blank picture.
            const size = d.width * d.height * 3 / 2;
            if (!blank || blank.byteLength !== size) {
                blank = new ArrayBuffer(size);
                const px = new Uint8Array(blank);
                px.fill(16, 0, d.width * d.height);
                px.fill(128, d.width * d.height);
            }
            new Uint8Array(blank).set(new Uint8Array(d.header), 0);
            d.data = blank;
            const t = performance.now();
            const f = new VideoFrame(d.data, { format: "NV12", codedWidth: d.width, codedHeight: d.height, timestamp: d.timestamp });
            w.write(f).catch(() => {});
            if (window.__ostCost) window.__ostCost.frameIn += performance.now() - t;
        } catch (x) {}
    }, true);
    // Test runs (--avatar-test): what the page asks its Unity player to do
    // (object, method, the argument's start), the player's own log, what
    // it renders and loads, sent to the host page's log (the app replaces
    // the console with its telemetry buffer).
    if (window.__ostDebug) {
        const log = text => window.parent.postMessage({ ostTexture: "log", text: (Date.now() % 1000000) + " " + String(text).slice(0, 300) }, HOST_ORIGIN);
        let verboseUntil = 0;
        // Where the page's main thread goes (ms per 5 s): Unity's main loop,
        // the app's Render() calls, GL readbacks and waits, frame copies.
        const cost = { loop: 0, render: 0, readback: 0, wait: 0, frameIn: 0, frameOut: 0 };
        setInterval(() => { log("cost ms/5s " + Object.entries(cost).map(([k, v]) => k + " " + Math.round(v)).join(", ")); for (const k in cost) cost[k] = 0 }, 5000);
        window.__ostCost = cost;
        for (const P of [window.WebGL2RenderingContext && WebGL2RenderingContext.prototype].filter(Boolean)) {
            const g = P.getBufferSubData, w = P.clientWaitSync, f = P.finish, rp = P.readPixels;
            P.getBufferSubData = function () { const t = performance.now(); try { return g.apply(this, arguments) } finally { cost.readback += performance.now() - t } };
            P.readPixels = function () { const t = performance.now(); try { return rp.apply(this, arguments) } finally { cost.readback += performance.now() - t } };
            P.clientWaitSync = function () { const t = performance.now(); try { return w.apply(this, arguments) } finally { cost.wait += performance.now() - t } };
            P.finish = function () { const t = performance.now(); try { return f.apply(this, arguments) } finally { cost.wait += performance.now() - t } };
            // GL uploads (calls, ms per 5 s), to see what the player does after a reaction.
            const up = { tex: 0, texMs: 0, buf: 0, bufMs: 0, draws: 0 };
            for (const k of ["texImage2D", "texSubImage2D", "texImage3D", "texSubImage3D", "compressedTexImage2D", "compressedTexSubImage2D", "texStorage2D"]) {
                const o = P[k]; if (typeof o !== "function") continue;
                P[k] = function () { const t = performance.now(); try { return o.apply(this, arguments) } finally { up.tex++; up.texMs += performance.now() - t } };
            }
            for (const k of ["bufferData", "bufferSubData"]) {
                const o = P[k]; if (typeof o !== "function") continue;
                P[k] = function () { const t = performance.now(); try { return o.apply(this, arguments) } finally { up.buf++; up.bufMs += performance.now() - t } };
            }
            for (const k of ["drawElements", "drawArrays", "drawElementsInstanced", "drawArraysInstanced"]) {
                const o = P[k]; if (typeof o !== "function") continue;
                P[k] = function () { up.draws++; return o.apply(this, arguments) };
            }
            setInterval(() => { log("gl uploads/5s tex " + up.tex + " (" + Math.round(up.texMs) + "ms) buf " + up.buf + " (" + Math.round(up.bufMs) + "ms) draws " + up.draws); for (const k in up) up[k] = 0 }, 5000);
            // Shader programs the player builds (and when they finish linking).
            const lp = P.linkProgram, gpp = P.getProgramParameter, cs = P.compileShader;
            const linking = new Map();
            let links = 0, done = 0, compiles = 0;
            P.compileShader = function () { compiles++; return cs.apply(this, arguments) };
            P.linkProgram = function (prog) { links++; linking.set(prog, performance.now()); return lp.apply(this, arguments) };
            P.getProgramParameter = function (prog, pname) { const v = gpp.apply(this, arguments); if (linking.has(prog) && (pname === 0x91B1 || pname === this.LINK_STATUS) && v) { const ms = performance.now() - linking.get(prog); linking.delete(prog); done++; if (ms > 200) log("program linked after " + Math.round(ms) + "ms") } return v };
            setInterval(() => { if (links || compiles) log("gl programs: " + compiles + " shaders compiled, " + links + " linked, " + done + " ready, " + linking.size + " pending"); links = 0; compiles = 0; done = 0 }, 5000);
        }
        // Requests the player gives up on (its UnityWebRequest timeouts abort them).
        { const ab = AbortController.prototype.abort; AbortController.prototype.abort = function (...a) { log("abort " + String(new Error().stack || "").split("\n").slice(2, 5).map(x => x.trim().slice(0, 60)).join(" < ")); return ab.apply(this, a) } }
        { const st0 = window.setTimeout; window.setTimeout = function (fn, ms, ...r) { if (typeof fn === "function" && ms >= 1000 && /isTimedOut/.test(String(fn))) log("request timeout set " + ms + "ms"); return st0.call(window, fn, ms, ...r) } }
        // Unity's main loop: how often it runs, and anything it throws.
        {
            // Unity's main loop runs on animation frames, or on timers once
            // the player sets a frame rate: count both, and what it throws.
            const raf = window.requestAnimationFrame.bind(window), st = window.setTimeout.bind(window);
            let rafTicks = 0, timerTicks = 0, gaps = [], last = 0;
            const tick = (kind, cb, arg) => { const n = performance.now(); if (last) gaps.push(n - last); last = n; if (kind === "raf") rafTicks++; else timerTicks++; const t0 = performance.now(); try { return cb(arg) } catch (e) { log("unity loop threw " + String(e && e.message || e).slice(0, 200)); throw e } finally { cost.loop += performance.now() - t0 } };
            window.requestAnimationFrame = cb => raf(t => cb && cb.name === "Browser_mainLoop_runner" ? tick("raf", cb, t) : cb(t));
            window.setTimeout = function (fn, ms, ...rest) { if (typeof fn === "function" && fn.name === "Browser_mainLoop_runner") return st(() => tick("timer", fn), ms); return st(fn, ms, ...rest) };
            setInterval(() => { const mx = gaps.length ? Math.round(Math.max(...gaps)) : 0; log("unity loop raf " + rafTicks + " timer " + timerTicks + " /5s, max gap " + mx + "ms"); rafTicks = 0; timerTicks = 0; gaps = [] }, 5000);
        }
        addEventListener("error", e => log("page error " + String(e.message || e.error).slice(0, 200) + " @" + (e.filename || "").slice(-60) + ":" + e.lineno), true);
        addEventListener("unhandledrejection", e => log("page rejection " + String(e.reason && (e.reason.stack || e.reason.message) || e.reason).slice(0, 240)));
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
            // The page's main thread blocked for long (a long frame).
            try { new PerformanceObserver(l => { for (const e of l.getEntries()) if (e.duration > 150) log("longtask " + Math.round(e.duration) + "ms at " + Math.round(performance.timeOrigin + e.startTime)) }).observe({ type: "longtask", buffered: false }) } catch (e) { log("longtask " + e) }
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
                I.Render = function () { nr++; const t = performance.now(); try { return r.apply(this, arguments) } finally { cost.render += performance.now() - t } };
                I.UpdateVisemeData = function () { nv++; return v.apply(this, arguments) };
                // Every other call into the renderer (resolution, mood, camera…).
                for (const k of Object.keys(I)) { if (k === "Render" || k === "UpdateVisemeData" || k === "ResetVisemeData" || typeof I[k] !== "function") continue; const fn = I[k]; I[k] = function (...a) { log("interop " + k + " " + JSON.stringify(a).slice(0, 160)); return fn.apply(this, a) } }
                setInterval(() => { log("renders " + nr + "/5s visemes " + nv + "/5s"); nr = 0; nv = 0 }, 5000);
            }
            // What it loads from now on (emote animations and the like),
            // with each asset's size and encoding.
            const f = window.fetch;
            window.fetch = function (input) {
                const url = String((input && input.url) || input).slice(0, 200);
                return f.apply(this, arguments).then(r => {
                    log("fetch " + r.status + " " + url + " type " + r.headers.get("content-type") + " enc " + r.headers.get("content-encoding") + " len " + r.headers.get("content-length"));
                    if (/\/assets\//.test(url)) r.clone().arrayBuffer().then(b => { const u8 = new Uint8Array(b, 0, Math.min(16, b.byteLength)); log("asset bytes " + b.byteLength + " head " + String.fromCharCode(...u8).replace(/[^ -~]/g, ".") + " " + url.slice(-40)) });
                    return r;
                }, e => { log("fetch failed " + url + " " + e); throw e });
            };
            // The player's WebGL context, to compare with Teams' WebView2.
            try {
                const c = document.querySelector("canvas");
                const gl = c && (c.getContext("webgl2") || c.getContext("webgl"));
                if (gl) {
                    const dbg = gl.getExtension("WEBGL_debug_renderer_info");
                    log("gl " + gl.getParameter(gl.VERSION) + " | " + gl.getParameter(gl.SHADING_LANGUAGE_VERSION) + " | " + (dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : "?"));
                    log("gl attrs " + JSON.stringify(gl.getContextAttributes()));
                    const ext = gl.getSupportedExtensions().join(",");
                    for (let i = 0; i < ext.length; i += 250) log("gl ext " + i + " " + ext.slice(i, i + 250));
                    log("gl limits vu " + gl.getParameter(gl.MAX_VERTEX_UNIFORM_VECTORS) + " fu " + gl.getParameter(gl.MAX_FRAGMENT_UNIFORM_VECTORS) + " vtex " + gl.getParameter(gl.MAX_VERTEX_TEXTURE_IMAGE_UNITS) + " ubo " + gl.getParameter(gl.MAX_UNIFORM_BLOCK_SIZE) + " vub " + gl.getParameter(gl.MAX_VERTEX_UNIFORM_BLOCKS) + " attrs " + gl.getParameter(gl.MAX_VERTEX_ATTRIBS));
                    log("gl max tex " + gl.getParameter(gl.MAX_TEXTURE_SIZE) + " uniforms " + gl.getParameter(gl.MAX_VERTEX_UNIFORM_VECTORS) + " ua " + navigator.userAgent);
                }
            } catch (e) { log("gl " + e) }
            // The page's storage (Unity's persistent files live in IndexedDB).
            const storage = when => {
                try {
                    if (indexedDB.databases) indexedDB.databases().then(d => {
                        log("idb " + when + " " + JSON.stringify(d));
                        // Unity's files (IDBFS: a FILE_DATA store keyed by path).
                        for (const db of d) {
                            const r = indexedDB.open(db.name);
                            r.onerror = () => log("idb " + when + " open " + db.name + " failed " + r.error);
                            r.onsuccess = () => {
                                const h = r.result, names = [...h.objectStoreNames];
                                log("idb " + when + " " + db.name + " stores " + names.join(","));
                                for (const st of ["avatar_settings", "scene_manager", "pinned_emotes"]) if (names.indexOf(st) >= 0) { const g = h.transaction(st).objectStore(st).getAll(); g.onsuccess = () => log("idb " + when + " " + st + " " + JSON.stringify(g.result).slice(0, 280)) }
                                if (names.indexOf("FILE_DATA") >= 0) {
                                    const k = h.transaction("FILE_DATA").objectStore("FILE_DATA").getAllKeys();
                                    k.onsuccess = () => { const ks = k.result.map(String); log("idbfs " + when + " " + ks.length + " files " + ks.slice(0, 40).join(" ").slice(0, 280)) };
                                }
                                h.close();
                            };
                        }
                    }, e => log("idb " + when + " failed " + e));
                    const FS = u.Module && u.Module.FS;
                    const walk = (p, n) => { try { for (const e of FS.readdir(p)) { if (e === "." || e === "..") continue; const q = p + "/" + e; const st = FS.stat(q); if (FS.isDir(st.mode)) { if (n < 4) walk(q, n + 1) } else log("fs " + when + " " + q + " " + st.size) } } catch (x) { log("fs " + when + " " + p + " " + x) } };
                    if (FS) walk("/idbfs", 0); else log("fs " + when + " no FS");
                } catch (x) { log("storage " + when + " " + x) }
            };
            setTimeout(() => storage("start"), 10000);
            const send = u.SendMessage.bind(u);
            u.SendMessage = (o, m, a) => { if (/Emote/.test(m)) { verboseUntil = Date.now() + 8000; setTimeout(() => storage("emote+5s"), 5000) } if (!/Viseme|Render/.test(m)) log("unity " + o + "." + m + " " + String(a === undefined ? "" : a).slice(0, 200)); return send(o, m, a) };
        }, 500);
    }
})();
