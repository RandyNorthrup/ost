// Cameo's camera inside PowerPoint Live's slide show, as the host provides
// it (docs/spec/content-sharing.md §3). New Teams' slide show
// (hostExperience "react-web-client") ignores frames posted as array
// buffers: on UpdateBufferInfoForCameo (m_type 64) it opens the camera it is
// named itself, with getUserMedia({video: {deviceId}}) — on Teams desktop a
// stream the host registers (WebView2's stream renderer). OST does the same
// for its own device id: this script, run in PowerPoint's frame only, answers
// getUserMedia for "ost-cameo" with a stream drawn from the frames the host
// already posts ({bufferMetadata, arrayBuffer}, BGRA), and passes every
// other request through untouched.
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
        if (!d || typeof d !== "object" || d.bufferMetadata === undefined || !d.arrayBuffer || !ctx) return;
        let m;
        try { m = JSON.parse(d.bufferMetadata); } catch (x) { return; }
        const w = m.width | 0, h = m.height | 0;
        if (!w || !h || d.arrayBuffer.byteLength < w * h * 4) return;
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        const src = new Uint8Array(d.arrayBuffer, 0, w * h * 4);
        const px = new Uint8ClampedArray(w * h * 4);
        // BGRA to RGBA, opaque (the posted buffer is left as it is).
        for (let i = 0; i < px.length; i += 4) { px[i] = src[i + 2]; px[i + 1] = src[i + 1]; px[i + 2] = src[i]; px[i + 3] = 255; }
        ctx.putImageData(new ImageData(px, w, h), 0, 0);
    }, true);
    const md = navigator.mediaDevices;
    if (!md || !md.getUserMedia) return;
    const wants = c => {
        const v = c && c.video;
        if (!v || typeof v !== "object") return false;
        const id = v.deviceId;
        return id === DEVICE || (id && (id.exact === DEVICE || id.ideal === DEVICE || (Array.isArray(id.exact) && id.exact.includes(DEVICE))));
    };
    const gum = md.getUserMedia.bind(md);
    md.getUserMedia = c => wants(c) ? Promise.resolve(ensure()) : gum(c);
    const enumerate = md.enumerateDevices.bind(md);
    md.enumerateDevices = () => enumerate().then(list => list.concat([{ deviceId: DEVICE, groupId: DEVICE, kind: "videoinput", label: "OST camera", toJSON() { return this; } }]));
})();
