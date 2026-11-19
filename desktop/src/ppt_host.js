// PowerPoint Live's host, as Teams' bundled PowerPoint bootstrapper is
// (ppt-1js-bootstrapper PreviewSessionLoader / FrameContainerContext;
// docs/spec/content-sharing.md §3): the slide show page is form-posted into
// a frame named slideshowframe-pptframe-<host session>, then the two talk
// in JSON messages with a numeric m_type, only with that frame's origin.
// The call window (PptLiveStage.qml) passes the form and relays slide
// moves through the content-sharing session.
(() => {
    new QWebChannel(qt.webChannelTransport, ch => {
        const ost = ch.objects.ost;
        let cfg = {};
        try { cfg = JSON.parse(ost.config || "{}"); } catch (e) { ost.log("bad config"); return; }
        const id = "pptframe-" + cfg.hostSessionId;
        const pods = cfg.pods;
        const podsOrigin = new URL(pods).origin;
        const frame = document.createElement("iframe");
        frame.id = id;
        frame.name = "slideshowframe-" + id;
        frame.title = cfg.fileName || "PowerPoint";
        frame.setAttribute("allow", "autoplay " + pods + "; microphone *" + (cfg.presenter ? "; focus-without-user-activation " + pods : ""));
        frame.setAttribute("sandbox", "allow-same-origin allow-scripts allow-popups allow-popups-to-escape-sandbox allow-forms");
        frame.style.cssText = "border:0;width:100%;height:100%;display:block";
        document.body.appendChild(frame);
        const form = document.createElement("form");
        form.id = "frameform-" + id;
        form.method = "post";
        form.target = frame.name;
        form.action = pods + "slideshow.aspx";
        for (const [k, v] of cfg.fields || []) {
            const i = document.createElement("input");
            i.type = "hidden"; i.name = k; i.value = String(v);
            form.appendChild(i);
        }
        document.body.appendChild(form);
        form.submit();
        ost.event("posted", "{}");

        let ready = false;
        let pending = null;
        // Cameo: the presenter's camera into the slide show (Teams'
        // VideoFrameToPptForCameo), from OST's loopback feed.
        const cameo = { url: "", key: "", width: 0, height: 0, ws: null, sent: "", bounds: false, frames: 0, layout: cfg.layout || "ContentOnly" };
        const cameoFrame = buf => {
            if (!frame.contentWindow) return;
            const v = new DataView(buf);
            const w = v.getUint32(0, true), h = v.getUint32(4, true);
            const px = w && h ? buf.slice(8) : new ArrayBuffer(0);
            const meta = '{"sharedArrayBuffer": false, "width": ' + w + ', "height": ' + h + ', "format": "BGRA"}';
            frame.contentWindow.postMessage({ bufferMetadata: meta, arrayBuffer: px }, podsOrigin, [px]);
            cameo.frames++;
            if (cameo.frames === 1 || cameo.frames % 300 === 0) ost.log("cameo frames " + cameo.frames + " " + w + "x" + h);
        };
        const cameoWant = () => {
            const want = JSON.stringify({ key: cameo.key, width: cameo.width, height: cameo.height });
            if (cameo.ws && cameo.ws.readyState === 1 && want !== cameo.sent) { cameo.ws.send(want); cameo.sent = want; ost.log("cameo wants " + want); }
        };
        const cameoSet = (url, key) => {
            if (!url || !key) {
                if (cameo.ws) { cameo.ws.close(); cameo.ws = null; }
                if (cameo.key) { cameoFrame(new ArrayBuffer(8)); post({ m_type: 64, m_bufferName: "" }); }
                cameo.key = ""; cameo.sent = "";
                return;
            }
            // New Teams' slide show opens the camera it is named (UpdateBufferInfoForCameo):
            // OST's stream (ppt_cameo_stream.js), drawn from the frames below. Teams
            // names it after PPTSharingLayoutChanged "Cameo" (46), so it goes out once
            // the layout has (see layoutChanged).
            const starting = !cameo.key;
            cameo.key = key;
            if (starting && ready && cameo.layout === "Cameo") post({ m_type: 64, m_bufferName: "ost-cameo" });
            if (!cameo.ws || cameo.url !== url) {
                if (cameo.ws) cameo.ws.close();
                cameo.url = url; cameo.sent = "";
                const ws = new WebSocket(url);
                ws.binaryType = "arraybuffer";
                ws.onopen = () => cameoWant();
                ws.onmessage = e => { if (e.data instanceof ArrayBuffer && ready) cameoFrame(e.data); };
                ws.onclose = () => { if (cameo.ws === ws) cameo.ws = null; };
                cameo.ws = ws;
            } else cameoWant();
        };
        const post = o => { if (frame.contentWindow) frame.contentWindow.postMessage(JSON.stringify(o), podsOrigin); };
        const now = Date.now();
        window.addEventListener("message", e => {
            if (e.source !== frame.contentWindow || e.origin !== podsOrigin) return;
            let m = e.data;
            if (typeof m === "string") { try { m = JSON.parse(m); } catch (x) { return; } }
            if (!m || typeof m.m_type !== "number") return;
            switch (m.m_type) {
                case 38: // OnSlideShowPageLoaded
                    ost.event("pageLoaded", "{}");
                    break;
                case 28: // AppReadyForPostMessage: Teams' Initialize, then its API timings.
                    post({ m_type: 0, m_id: cfg.hostSessionId, m_fEnableKeyboardNavigation: true, m_contentMetadata: null,
                           m_fileUrl: cfg.fileUrl, m_fileSize: cfg.fileSize, m_fileName: cfg.fileName, m_presentationId: cfg.snapUrl,
                           m_startingSlideId: -1, m_startingSlideIndex: cfg.startSlide || 1, m_hostName: "MSTeams", m_entryPoint: "Teams",
                           m_apiStartTime: now, m_documentClickTime: now, m_hostInitTime: now, m_fEnableAdvanceOnTap: false,
                           m_fileHost: "SharePoint Online", m_vetoAppSettingsStr: "", m_disabledTransitionsList: "",
                           m_customTransitionResourceUrl: "", m_streamUseThinEmbed: false, m_disabledChangeGates: "",
                           m_wacRegion: cfg.wacRegion, m_areThirdPartyAddInsAllowed: false, m_allowExternalMarketplace: true });
                    post({ m_type: 26, m_apiTimings: { IsPresenter: !!cfg.presenter } });
                    break;
                case 0: // Initialized: Teams' viewer API set-up.
                    ready = true;
                    post({ m_type: 79, m_theme: cfg.theme || "light" });
                    post({ m_type: 1 });
                    post({ m_type: 3 });
                    post({ m_type: 31, m_enableAdvanceOnClick: !!cfg.presenter, m_enableKeyboardNavigation: !!cfg.presenter });
                    post({ m_type: 34, m_role: cfg.presenter ? 1 : 0 });
                    post({ m_type: 47, m_enabled: false });
                    post({ m_type: 62, m_fMuted: false });
                    post({ m_type: 46, m_sharingLayoutMode: cfg.layout || "ContentOnly" });
                    post({ m_type: 76, m_status: 0 });
                    post({ m_type: 80, m_available: false });
                    post({ m_type: 75, m_presenterDisplayName: cfg.presenterName || "" });
                    post({ m_type: 111, m_count: cfg.attendees || 1 });
                    post({ m_type: 112, m_count: cfg.attendees || 1 });
                    ost.event("ready", "{}");
                    if (pending) { post(pending); pending = null; }
                    break;
                case 69: // Is the host trusted?
                    post({ m_type: 65, m_isTrusted: true });
                    break;
                case 5: // OnPositionChanged
                    ost.event("position", JSON.stringify({ slideIndex: m.m_slideIndex, slideId: m.m_slideId,
                                                         timeLineMappings: m.m_timeLineMappings || [], metadata: m.m_metadata || null }));
                    break;
                case 1:
                    ost.event("slideCount", JSON.stringify({ count: m.m_slidesCount }));
                    break;
                case 3:
                    ost.event("currentPosition", JSON.stringify({ slideIndex: m.m_slideIndex, timeLineMappings: m.m_timeLineMappings || [],
                                                                metadata: m.m_metadata || null }));
                    break;
                case 53: // AnnotationEvent: ink, laser, cursor (Teams relays them).
                    ost.event("annotation", JSON.stringify({ eventType: m.m_annotationEventType, eventJson: m.m_annotationEventJson,
                                                           strokeID: m.m_annotationStrokeID, slideID: m.m_annotationSlideID,
                                                           metadata: m.m_metadata || null }));
                    break;
                case 72: // TakeControl from PowerPoint's own button.
                    ost.event("takeControl", "{}");
                    break;
                case 48: { // OnSlideViewBoundsChanged: the size Cameo's pictures take.
                    const b = m.m_slideViewBounds || {};
                    const w = Math.round((b.right || 0) - (b.left || 0)), h = Math.round((b.bottom || 0) - (b.top || 0));
                    if (w > 0 && h > 0) cameo.bounds = true;
                    if (w > 0 && h > 0 && (w !== cameo.width || h !== cameo.height)) { cameo.width = w; cameo.height = h; cameoWant(); }
                    break;
                }
                case 66: // CameoDetectedInPresentation: the deck has a cameo (Teams' Layout ▸ Cameo needs one).
                    ost.event("cameoDetected", JSON.stringify({ detected: !!m.m_fCameoDetectedInPresentation }));
                    break;
                case 67: { // CameoFrameRequestForSlide: the cameo on this slide and its size.
                    const c = (m.m_cameoInSlide || [])[0];
                    ost.log("cameo request " + JSON.stringify(m.m_cameoInSlide || []).slice(0, 200));
                    // Without slide-view bounds yet, the cameo's own size (device pixels).
                    if (c && !cameo.bounds) {
                        const w = Math.ceil((c.m_widthInPixels || 0) * (window.devicePixelRatio || 1));
                        const h = Math.ceil((c.m_heightInPixels || 0) * (window.devicePixelRatio || 1));
                        if (w > 0 && h > 0 && (w !== cameo.width || h !== cameo.height)) { cameo.width = w; cameo.height = h; cameoWant(); }
                    }
                    break;
                }
                case 18: // Pointer moves over the frame (Teams hides its bar's auto-hide on them).
                    break;
                case 10:
                    ost.event("error", JSON.stringify({ code: m.m_code, name: m.m_errorName || "" }));
                    break;
                case 47:
                    ost.event("privateViewing", JSON.stringify({ enabled: !!m.m_enabled }));
                    break;
                case 25:
                    ost.event("goToPresenter", "{}");
                    break;
                case 49:
                    ost.event("tokenRequest", JSON.stringify({ resource: String(m.m_resourceId || "") }));
                    break;
                default:
                    ost.log("frame message " + m.m_type);
            }
        });
        // An attendee follows the presenter (Teams' GoToSlide).
        ost.goToSlide.connect(json => {
            let g = {};
            try { g = JSON.parse(json); } catch (e) { return; }
            const msg = { m_type: 9, m_slideIndex: g.slideIndex, m_timeLineMappings: g.timeLineMappings || [], m_metadata: g.metadata || null };
            if (ready) post(msg); else pending = msg;
        });
        ost.command.connect(json => { try { const o = JSON.parse(json); if (ready && typeof o.m_type === "number") post(o); } catch (e) {} });
        ost.layoutChanged.connect(mode => {
            cameo.layout = mode;
            if (!ready) return;
            post({ m_type: 46, m_sharingLayoutMode: mode });
            // Teams' order: the layout, then the camera's stream (or none).
            if (mode === "Cameo" && cameo.key) post({ m_type: 64, m_bufferName: "ost-cameo" });
        });
        // Cameo's pictures: {url, key} (the camera's frames), or {} to stop.
        ost.cameo.connect(json => { let c = {}; try { c = JSON.parse(json); } catch (e) {} cameoSet(c.url || "", c.key || ""); });
        ost.token.connect((resource, token) => { if (ready) post({ m_type: 49, m_token: token, m_resourceId: resource }); });
    });
})();
