// Cameo's camera inside PowerPoint Live's slide show, as the host provides
// it (docs/spec/content-sharing.md §3). New Teams' slide show
// (hostExperience "react-web-client", its enableCameoInT2 setting on)
// ignores frames posted as array buffers: on UpdateBufferInfoForCameo
// (m_type 64) it opens the stream it is named with WebView2's
// `chrome.webview.getTextureStream(id)` (seen on Teams desktop 2026-11-18:
// 64 with "20712-247", getTextureStream gave a live 640 × 480 track). OST
// provides that one function for its own id, "ost-cameo": a stream drawn
// from the frames the host already posts ({bufferMetadata, arrayBuffer},
// BGRA). Nothing else of WebView2 is imitated; PowerPoint uses only
// getTextureStream from it. This runs in PowerPoint's frame only.
(() => {
    if (!/\.officeapps\.live\.com$/.test(location.hostname) || window.__ostCameoStream) return;
    window.__ostCameoStream = true;
    const DEVICE = "ost-cameo";
    let canvas = null, ctx = null, stream = null;
    const ensure = () => {
        if (stream) return stream;
        canvas = document.createElement("canvas");
        canvas.width = 640; canvas.height = 360;
        ctx = canvas.getContext("2d");
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        stream = canvas.captureStream(15);
        return stream;
    };
    window.addEventListener("message", e => {
        const d = e.data;
        if (!d || typeof d !== "object" || d.bufferMetadata === undefined || !d.arrayBuffer) return;
        let m;
        try { m = JSON.parse(d.bufferMetadata); } catch (x) { return; }
        const w = m.width | 0, h = m.height | 0;
        if (!w || !h || d.arrayBuffer.byteLength < w * h * 4) return;
        ensure();
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        const src = new Uint8Array(d.arrayBuffer, 0, w * h * 4);
        const px = new Uint8ClampedArray(w * h * 4);
        // BGRA to RGBA, opaque (the posted buffer is left as it is).
        for (let i = 0; i < px.length; i += 4) { px[i] = src[i + 2]; px[i + 1] = src[i + 1]; px[i + 2] = src[i]; px[i + 3] = 255; }
        ctx.putImageData(new ImageData(px, w, h), 0, 0);
    }, true);
    const chrome = window.chrome || (window.chrome = {});
    const webview = chrome.webview || (chrome.webview = {});
    if (!webview.getTextureStream) {
        webview.getTextureStream = id => id === DEVICE
            ? Promise.resolve(ensure())
            : Promise.reject(new Error("No texture stream " + id));
    }
})();
