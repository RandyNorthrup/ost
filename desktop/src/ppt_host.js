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
                    ost.event("currentPosition", JSON.stringify({ slideIndex: m.m_slideIndex }));
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
        ost.layoutChanged.connect(mode => { if (ready) post({ m_type: 46, m_sharingLayoutMode: mode }); });
        ost.token.connect((resource, token) => { if (ready) post({ m_type: 49, m_token: token, m_resourceId: resource }); });
    });
})();
