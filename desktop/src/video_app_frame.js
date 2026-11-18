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
        // A stream that isn't drained yet drops the new frame.
        if (w.desiredSize !== null && w.desiredSize <= 0) return;
        try {
            const f = new VideoFrame(d.data, { format: "NV12", codedWidth: d.width, codedHeight: d.height, timestamp: d.timestamp });
            w.write(f).catch(() => {});
        } catch (x) {}
    }, true);
})();
