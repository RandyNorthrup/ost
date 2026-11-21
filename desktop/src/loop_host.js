// OST's Loop page host: what Teams' "OfficeWebHost" / Loop experiences
// code does to show a Loop page (a chat's Notes, a channel's Page), read
// from Teams on the web 2026-11-16 (docs/spec/loop-host.md).
//
// Teams runs Loop's page container in a same-origin srcdoc frame of its own
// page, with Teams' origin: it loads Microsoft's service-delivered ODSP
// driver and the page container's code (res.cdn.office.net/fluid/prod) into
// that frame, runs Fluid's container loader (bundled in Teams; here the
// open-source @fluidframework packages, fluid-loader.js, global OstFluid)
// with a dependency synthesizer holding Teams' host services, and renders
// the container's HTML view into the frame's #componentDiv.
//
// This script runs in the host page's main world (the Fluid objects pass
// between this window and the frame's, as in Teams). Native calls (tokens)
// go through OST's bridge in an isolated world by window messages; tokens
// are never logged.
(() => {
    if (window.__ostLoopHost) return;
    window.__ostLoopHost = true;
    const F = window.OstFluid;
    const CDN = "https://res.cdn.office.net/fluid/prod";
    const LOOP_PACKAGE = "@fluidx/loop-page-container";
    // Header names (@fluidframework/odsp-driver-definitions, container-definitions).
    const IS_SHARING_LINK_TO_REDEEM = "isSharingLinkToRedeem";
    const IS_REDEMPTION_NON_DURABLE = "isRedemptionNonDurable";
    const IS_CLP_COMPLIANT_APP = "X-CLP-Compliant-App";
    const LOAD_MODE = "loadMode";
    const uuid = () => crypto.randomUUID();

    // ---- the bridge to OST (isolated world) ----------------------------
    const pending = new Map();
    let seq = 0;
    let cfg = null;
    let rendered = null;
    let titleText = async () => "";
    const post = m => window.postMessage(Object.assign({ ostLoop: true }, m), location.origin);
    const native = (kind, payload) => new Promise(resolve => {
        const id = "l" + (++seq);
        pending.set(id, resolve);
        post({ dir: "request", id, kind, payload: JSON.stringify(payload || {}) });
    });
    const emit = (name, data) => post({ dir: "event", name, json: JSON.stringify(data || {}) });
    addEventListener("message", e => {
        const d = e.data;
        if (e.source !== window || !d || d.ostLoop !== true) return;
        if (d.dir === "reply") {
            const f = pending.get(d.id);
            if (f) { pending.delete(d.id); let v = {}; try { v = JSON.parse(d.json) } catch (x) {} f(v) }
        } else if (d.dir === "config" && !cfg) {
            try { cfg = JSON.parse(d.json) } catch (x) { return }
            start().catch(err => fail("start", err));
        } else if (d.dir === "theme" && styling) {
            styling.setTheme(d.theme);
        } else if (d.dir === "titleText") {
            titleText().then(t => emit("titleText", { title: t }), () => emit("titleText", { title: "" }));
        } else if (d.dir === "commanding") {
            let m = {};
            try { m = JSON.parse(d.json) } catch (x) { return }
            commanding.fromHost(m);
        }
    });
    const fail = (stage, err) => {
        const message = String((err && (err.message || err.errorType)) || err || "").slice(0, 300);
        console.warn("LOOPHOST failed", stage, err && err.errorType || "", message);
        emit("error", { stage, message, errorType: String(err && err.errorType || "") });
    };

    // ---- Teams' host services (its scope builder, chat-app 600116) ------
    // TokenProvider: Teams' own web-client tokens for what Loop asks
    // (SharePoint, the push channel, AugLoop, Graph), each `{token}`.
    const tokenProvider = {
        get TokenProvider() { return this },
        identityType: "Enterprise",
        async getToken(scopes, options) {
            const r = await native("token", { scopes: Array.isArray(scopes) ? scopes : [String(scopes || "")], claims: options && options.claims || "", forceRefresh: !!(options && options.forceRefresh) });
            if (!r.token) throw Object.assign(new Error(r.error || "Token unavailable"), { errorType: "authorizationError", canRetry: false });
            return { token: r.token, fromCache: !!r.fromCache };
        }
    };

    // SettingsProvider: Loop's ECS settings (ecs.office.com, client Fluid,
    // agents FluidExperiences and Segmentation), with Teams' overrides.
    let ecs = null;
    let ecsPromise = null;
    const fetchEcs = () => ecsPromise || (ecsPromise = (async () => {
        const q = new URLSearchParams();
        q.append("agents", "FluidExperiences,Segmentation");
        const audience = cfg.audience === "Development" ? "Staging" : cfg.audience;
        q.append("audience", audience); q.append("userId", cfg.user.oid); q.append("tenantId", cfg.user.tid); q.append("hostName", cfg.hostName);
        try {
            const r = await fetch("https://ecs.office.com/config/v1/Fluid/0.0.0.1?" + q.toString());
            if (r.status === 200) ecs = await r.json();
        } catch (e) { console.warn("LOOPHOST ecs", String(e && e.message || e)) }
        return ecs;
    })());
    const ecsValue = (name, ns) => {
        const v = ecs && ecs[ns] ? ecs[ns][name] : undefined;
        return v === "on" ? true : v === "off" ? false : v;
    };
    const settings = {
        get SettingsProvider() { return this },
        get audience() { return cfg.audience },
        getSetting(name, def, ns) {
            const fs = cfg.fluidSettings || {};
            if (name === "paragraphWithoutInsertionMenuExperimentEnabled") return fs.paragraphWithoutInsertionMenuExperimentEnabled;
            if (name === "scriptor.isDiscoveryFooterEnabledInDetachedStateOnly" && fs.enableDiscoveryFooterInAttachedState) return !fs.enableDiscoveryFooterInAttachedState;
            if (name === "ActivityTransport.Pipelines.Common.Mention") return 2;
            // A channel's Page: Loop draws its page header (the title).
            if (cfg.kind === "channelPages" && name === "loopPageContainer.renderHeaderByDefault") return true;
            if (name === "context.tenantId") return cfg.user.tid || def;
            const v = ecsValue(name, ns);
            return v === undefined ? def : v;
        },
        async getLiveSetting(name, def, ns) {
            if (name === "ActivityTransport.Pipelines.Common.Mention") return 2;
            await fetchEcs();
            return this.getSetting(name, def, ns);
        },
        get Disposable() { return this },
        dispose() {}
    };

    // StylingProvider: Teams' theme as CSS properties (Fluent's Teams
    // tokens and Teams' --ms-theme* names, measured for its light theme,
    // loop_theme_light.json) and its text styles per heading level. In
    // OST's dark and high-contrast themes only the type, size and spacing
    // tokens go (Teams' own colours for those themes weren't measured) and
    // the theme's name tells Loop which palette to use.
    const teamsTheme = window.__ostLoopTeamsTheme || { themeProperties: [], textStyles: [] };
    // Teams' dark and high-contrast properties (loop_theme_dark.json,
    // loop_theme_contrast.json, dumped from Teams' Loop frames 2026-11-20).
    const teamsThemes = window.__ostLoopTeamsThemes || {};
    const themeFor = t => new Map(((teamsThemes[t] || {}).themeProperties || teamsTheme.themeProperties)
        .concat([["--ms-themeColorThemeName", t === "contrast" ? "high-contrast" : t]]));
    const listeners = new Map();
    const styling = {
        get StylingProvider() { return this },
        appThemeProperties: themeFor("default"),
        appTextStyles: new Map(teamsTheme.textStyles),
        get themeProperties() { return this.appThemeProperties },
        get textStyles() { return this.appTextStyles },
        get themeName() { return undefined },
        on(ev, f) { (listeners.get(ev) || listeners.set(ev, new Set()).get(ev)).add(f); return this },
        off(ev, f) { listeners.get(ev)?.delete(f); return this },
        removeListener(ev, f) { return this.off(ev, f) },
        currentThemeName: "default",
        setTheme(t) {
            this.currentThemeName = t;
            this.appThemeProperties = themeFor(t);
            for (const f of listeners.get("themePropertiesChanged") || []) { try { f(this.themeProperties) } catch (e) {} }
            for (const f of listeners.get("themeNameChanged") || []) { try { f(t) } catch (e) {} }
        }
    };

    // NamespaceLogger: Teams logs Loop's events to its own telemetry; OST
    // keeps only errors' names, in its log.
    const persisted = {};
    const logger = {
        get NamespaceLogger() { return this },
        get PersistedProperties() { return this },
        get Disposable() { return this },
        dispose() {},
        markWebContextUnloading() {},
        addPersistedProperties(p) { Object.assign(persisted, p) },
        getPersistedProperties() { return Object.assign({}, persisted) },
        send(e) { this.sendWithNamespace(e, undefined) },
        sendWithNamespace(e) {
            if (e && e.category === "error") console.warn("LOOPHOST event", String(e.eventName || "").slice(0, 120), String(e.errorType || "").slice(0, 60));
        },
        getNamespace() { return "" }
    };
    // The Fluid loader's logger (ITelemetryBaseLogger).
    const fluidLogger = { send(e) { if (e && e.category === "error") console.warn("LOOPHOST fluid", String(e.eventName || "").slice(0, 120), String(e.errorType || "").slice(0, 60)) } };

    // CommandingSurfaceTreeViewProvider (Teams' 425275): Loop's formatting
    // toolbar ("commanding surface") drawn by the host instead of inside
    // the frame. Loop calls display(params) with the toolbar's commands and
    // where to put it (client coordinates in the frame), dismiss() to hide
    // it. Teams draws it in its own page over the frame (CommandingSurfaceV9,
    // legacy style); OST draws it natively (LoopCommandingSurface.qml): the
    // commands go there as plain data, each with a key, and come back as
    // "exec" (run the command, then dismiss as Teams does) or "dismiss".
    let frameEl = null;
    const commanding = {
        get CommandingSurfaceTreeViewProvider() { return this },
        get Disposable() { return this },
        usesCoordinates: true,
        isExpandableCommandingSurfaceEnabled: true,
        currentDisplayParams: undefined,
        commands: new Map(),
        seq: 0,
        // Each display is numbered; OST's answers name the one they're for
        // (a late "dismiss" mustn't close the next one).
        shown: 0,
        dispose() { this.currentDisplayParams = undefined; this.commands.clear() },
        // A command as data: Teams' renderer reads these fields.
        ser(c) {
            if (!c || typeof c !== "object") return null;
            const key = "k" + (++this.seq);
            this.commands.set(key, c);
            const ip = c.iconProperties && typeof c.iconProperties === "object" ? c.iconProperties : null;
            const str = v => typeof v === "string" ? v : v === undefined || v === null ? "" : String(v);
            return {
                key, id: str(c.id), name: str(c.displayName), aria: str(c.ariaLabel), title: str(c.title),
                icon: str(ip ? ip.name : typeof c.icon === "string" ? c.icon : ""), iconColor: str(ip && ip.color), iconBackground: str(ip && ip.backgroundColor),
                toggle: !!(c.toggle || c.canCheck), checked: !!c.checked, disabled: !!c.disabled,
                shortcut: str(c.shortcut), secondary: str(c.secondaryText), inline: c.isInlineSubMenu !== false,
                sub: Array.isArray(c.subMenuCommands) ? c.subMenuCommands.map(s => this.ser(s)).filter(Boolean) : null
            };
        },
        display(p) {
            if (!this.shown) console.info("LOOPHOST commanding display", Object.keys(p || {}).join(","));
            this.currentDisplayParams = p;
            this.commands.clear();
            this.seq = 0;
            const c = (p && p.coordinates) || {};
            // Teams puts the surface at the hosting element's corner (plus
            // its padding and the page's scroll) plus Loop's coordinates.
            const r = frameEl ? frameEl.getBoundingClientRect() : { left: 0, top: 0 };
            emit("commanding", {
                seq: ++this.shown,
                x: r.left + window.scrollX + (Number(c.clientX) || 0), y: r.top + window.scrollY + (Number(c.clientY) || 0),
                top: (p.topBarCommands || []).map(x => this.ser(x)).filter(Boolean),
                main: (p.mainBodyCommands || []).map(x => this.ser(x)).filter(Boolean),
                mini: !!p.mainBodyInitiallyHidden, focus: !!p.focusMode,
                position: String(p.position || "below"), align: String(p.align || "start")
            });
        },
        dismiss() {
            this.currentDisplayParams = undefined;
            emit("commandingDismiss", {});
        },
        // Teams' onDismiss: hide, tell Loop, give focus back to where it was.
        closed(p) {
            this.dismiss();
            if (!p) return;
            try { p.onDismiss && p.onDismiss() } catch (e) { console.warn("LOOPHOST commanding onDismiss", String(e && e.message || e).slice(0, 120)) }
            try { p.previousElement && p.previousElement.focus({ preventScroll: true }) } catch (e) {}
        },
        fromHost(m) {
            const p = this.currentDisplayParams;
            if (m.seq !== this.shown) return;
            if (m.op === "exec") {
                const cmd = this.commands.get(m.key);
                if (!p || !cmd || typeof cmd.execute !== "function") return;
                // Teams passes the click event; the command sees one from
                // the frame's window.
                const w = frameEl && frameEl.contentWindow || window;
                const native = new w.MouseEvent("click", { bubbles: true, cancelable: true });
                const ev = { type: "click", nativeEvent: native, target: null, currentTarget: null, detail: 1, button: 0,
                             preventDefault() { native.preventDefault() }, stopPropagation() {}, isDefaultPrevented: () => native.defaultPrevented,
                             isPropagationStopped: () => false, persist() {} };
                try { cmd.execute(ev) } catch (e) { console.warn("LOOPHOST commanding exec", String(cmd.id || ""), String(e && e.message || e).slice(0, 120)) }
                emit("commandingExecuted", { id: String(cmd.id || "") });
                this.closed(p);
            } else if (m.op === "dismiss") {
                this.closed(p);
            }
        }
    };

    // NestedLoopComponentHosting (Teams' 910716): the nested component's
    // dependency container as it is (Teams only swaps its driver when its
    // useNestedDependencyContainer setting is on: the Automation audience).
    const nestedHosting = {
        get NestedLoopComponentHosting() { return this },
        get Disposable() { return this },
        getNestedDependencyContainer(c) { return c },
        dispose() {}
    };
    // ResolvedUrlProvider (Teams' 910716): a container's resolved URL, and
    // other links resolved by the container's URL resolver (cached).
    const resolvedUrls = (containerP, resolverP) => {
        const cache = new Map();
        return {
            get ResolvedUrlProvider() { return this },
            get Disposable() { return this },
            dispose() { cache.clear() },
            async getResolvedUrl() { const c = await containerP(); return c ? c.resolvedUrl : undefined },
            async resolveUrl(url) {
                if (cache.has(url)) return cache.get(url);
                const r = await resolverP();
                if (!r) return undefined;
                try { const v = await r.resolve({ url }); cache.set(url, v); return v }
                catch (e) { console.warn("LOOPHOST ResolveDocumentUrlError", String(e && e.errorType || "")); return undefined }
            }
        };
    };
    // A container's component: its entry point, or the data store its
    // link's path names (UrlRouterFetcher), as Teams' loader routes.
    const entryOf = async c => {
        const entry = await c.getEntryPoint();
        const path = c.resolvedUrl && c.resolvedUrl.dataStorePath;
        if (path && path !== "/" && entry && entry.UrlRouterFetcher) {
            const router = await entry.UrlRouterFetcher.getUrlRouter();
            const r = router && await router.request({ url: path });
            if (r && r.status === 200 && r.value) return r.value;
        }
        return entry;
    };

    let container = null;
    let resolvedUrl = null;
    async function start() {
        if (!F) throw new Error("Fluid loader missing");
        styling.appThemeProperties = themeFor(cfg.theme || "default");
        const scenario = cfg.mode === "create" ? "Create" : "Load";
        const correlation = uuid();
        const fs = cfg.fluidSettings || {};
        const vp = fs.viewProperties || {};
        Object.assign(persisted, {
            hostCorrelationId: correlation,
            hostScenarioName: cfg.kind === "channelPages" ? scenario + "_Page_ChannelTab" : cfg.kind === "meetingNotes" ? scenario + "_Page_MeetingNotes"
                : cfg.kind === "compose" ? "Create_Component_Compose" : cfg.kind === "message" ? "Load_Component_Message" : scenario + "_Page_Chat",
            hostName: cfg.hostName,
            hostScenarioStartTime: Date.now(),
            loopAudience: cfg.audience,
            hostSessionId: cfg.sessionId,
            hostAppVersion: cfg.hostAppVersion,
            hostAppPlatform: cfg.hostAppPlatform
        });
        fetchEcs();
        // The theme OST is in when the page starts (later changes come as
        // theme messages).
        if (cfg.theme && cfg.theme !== styling.currentThemeName) styling.setTheme(cfg.theme);

        // The dependency synthesizer with Teams' providers.
        const synth = new F.DependencyContainer();
        const reg = (name, value) => synth.register(name, Promise.resolve(value));
        reg("UserContext", { get UserContext() { return this }, user: { tenantId: cfg.user.tid, id: cfg.user.oid, userIdSpace: "UserObjectId" } });
        reg("InternationalizationContext", { get InternationalizationContext() { return this }, uiLocale: cfg.locale || "en-us" });
        reg("TelemetryConfig", { get TelemetryConfig() { return this }, hostCorrelationId: correlation, hostSessionId: cfg.sessionId,
                                 scenarioStartTime: persisted.hostScenarioStartTime, disallowServiceTelemetry: false, hostAppName: "Teams", hostScenarioLifecycle: scenario });
        reg("SettingsProvider", settings);
        const pol = cfg.policy || {};
        reg("OfficePolicyProvider", {
            get OfficePolicyProvider() { return this },
            isConnectedExperienceEnabled: pol.connectedExperiences !== false,
            async getPolicy(p) {
                return pol.enableDefaultPolicyValue && pol.allowFluidCollaborate && cfg.kind === "fluidThread" && pol.enableFluidThread && p && String(p.policyId || "").includes("L_Loop")
                    ? undefined : { value: "0" };
            },
            async optionalConnectedExperiencesEnabled() { return pol.connectedExperiences !== false },
            async getEnterpriseFeedbackPolicy() { return undefined }
        });
        reg("NamespaceLogger", logger);
        reg("TokenProvider", tokenProvider);
        reg("StylingProvider", styling);
        reg("HostViewProperties", { get HostViewProperties() { return this }, viewType: vp.viewType || "Large", getViewProperties() { return Promise.resolve({ viewType: vp.viewType || "Large" }) } });
        let pageUrlResolver = null;
        reg("ResolvedUrlProvider", resolvedUrls(async () => container, async () => pageUrlResolver));
        reg("NestedLoopComponentHosting", nestedHosting);
        // Teams registers its commanding surface when its fluid settings'
        // commandingSurfaceEnabled is on (its default) and the page isn't
        // rendered in a div; without it Loop draws its own in the frame.
        if (fs.commandingSurfaceEnabled !== false && !fs.enableRenderInDiv) reg("CommandingSurfaceTreeViewProvider", commanding);
        // PresenceColorProvider (Teams' 478989): a collaborator's colour from
        // the sum of their id's character codes (upper case) mod 10 over
        // Teams' category colours; high contrast is #1aebff for everyone.
        const presenceLight = ["#B24932", "#92660D", "#56742F", "#248353", "#164279", "#37797B", "#7D2B5C", "#A22954", "#764E3B", "#993840"];
        const presenceDark = ["#F39D89", "#ECC26E", "#B5CC99", "#78C9A0", "#7FA3D0", "#96D6D8", "#CC87B1", "#E47CA1", "#BF9D8C", "#DC8990"];
        reg("PresenceColorProvider", {
            get PresenceColorProvider() { return this },
            getPresenceColorForUser(id) {
                if (!id) return "transparent";
                const t = styling.currentThemeName;
                if (t === "contrast") return "#1aebff";
                let sum = 0;
                for (const ch of String(id).toUpperCase()) sum += ch.charCodeAt(0);
                return (t === "dark" ? presenceDark : presenceLight)[sum % 10];
            }
        });
        // PeopleService (Teams' 447247 for pages): @mention suggestions from
        // the compose resolver (people only).
        reg("PeopleService", {
            get PeopleService() { return this },
            async searchForMention(query, options) {
                const r = await native("people", { query: String(query || "").replace(/^@/, ""), max: (options && options.resultCount) || 10 });
                return Array.isArray(r.people) ? r.people : [];
            },
            async onResolveSuggestions(query, options) { return this.searchForMention(query, options) }
        });

        // The frame Teams makes for the container (OfficeWebHost's
        // sourceless iframe V2): frameborder 0, tabindex -1, an empty title,
        // filling the host (layout fixedByHost), its document
        // `<body style="margin: 0px;"><div id="componentDiv">`.
        // A Loop component in compose or a message fills Teams' fixed 320 px
        // frame (its insert row at the bottom, as measured in Teams).
        const layoutMode = cfg.kind === "compose" || cfg.kind === "message" ? "fixedByHost"
            : ({ fixedByHost: "fixedByHost", grow: "grow" })[vp.layoutMode] || (cfg.kind === "channelPages" ? "fixedByHost" : "growHeight");
        const frame = document.createElement("iframe");
        frame.frameBorder = "0";
        frame.tabIndex = -1;
        frame.setAttribute("title", cfg.iframeTitle || "");
        frame.style.height = "100%"; frame.style.width = "100%";
        const loaded = new Promise(r => frame.addEventListener("load", r, { once: true }));
        frame.srcdoc = ["<!DOCTYPE html>", "<html>", "<head>", '<meta charset="utf-8" />',
                        '<link rel="preconnect" href="' + new URL(CDN).origin + '" crossorigin>', "</head>",
                        '<body style="margin: 0px;">', '<div id="componentDiv"></div>', "</body>", "</html>"].join("\n");
        document.body.appendChild(frame);
        frameEl = frame;
        await loaded;
        const win = frame.contentWindow;
        const doc = win.document;
        doc.documentElement.style.overflow = "hidden";
        document.documentElement.setAttribute("dir", "ltr");
        document.documentElement.setAttribute("lang", cfg.locale || "en-us");
        document.documentElement.setAttribute("translate", "no");
        const div = doc.getElementById("componentDiv");
        if (layoutMode === "fixedByHost") Object.assign(div.style, { position: "absolute", top: "0", bottom: "0", left: "0", right: "0" });
        emit("framed", {});

        // Scripts into the frame, as Teams' loader adds them (crossorigin
        // anonymous, in order, retried).
        const script = (url, tries = 3) => new Promise((resolve, reject) => {
            const s = doc.createElement("script");
            s.setAttribute("fetchpriority", "high");
            s.src = url; s.async = false; s.charset = "utf-8"; s.crossOrigin = "anonymous";
            s.onload = resolve;
            s.onerror = () => tries > 1 ? script(url, tries - 1).then(resolve, reject) : reject(new Error("Failed to download the script at url: " + url));
            doc.head.appendChild(s);
        });
        const style = url => new Promise((resolve, reject) => {
            const l = doc.createElement("link");
            l.rel = "stylesheet"; l.type = "text/css"; l.href = url;
            l.onload = () => resolve(); l.onerror = () => reject(new Error("Failed to download the style sheet at url: " + url));
            doc.head.appendChild(l);
        });
        const json = async url => { const r = await fetch(url); if (!r.ok) throw new Error("Failed to fetch " + url + ": " + r.status); return r.json() };

        // The ODSP driver, service-delivered (deploymentManifestOdspDriver).
        const manifest = await json(CDN + "/odsp-driver/versionless/deploymentManifestOdspDriver.json");
        win.FluidOdspDriver = win.FluidOdspDriver || {};
        win.FluidOdspDriver.scriptLoadingStarted = true;
        await script(manifest.jsBaseUrl + "/" + manifest.v1.index);
        if (typeof win.FluidOdspDriver.getDocumentServiceFactory !== "function") throw new Error("Could not load service-delivered ODSP Driver Code");
        // Teams' host storage policy (chat-app 627924).
        const hostStoragePolicy = { enableRedeemFallback: true, enableSingleRequestForShareLinkWithCreate: !!fs.composeSingleRequestForShareLinkEnabled };
        if (fs.sizeLimitEnabled) hostStoragePolicy.snapshotOptions = { mds: fs.sizeLimitValueBytes || 6291456 };
        const documentServiceFactory = win.FluidOdspDriver.getDocumentServiceFactory({ tokenProvider, logger, driverCache: undefined, hostStoragePolicy, settingsProvider: settings });

        // The URL resolver Teams uses (ODSP's share-link resolver, app name
        // "Teams"); its token fetcher asks for the site's SharePoint token.
        const siteScopes = siteUrl => [new URL(siteUrl).origin + "/files.readwrite.all"];
        const urlResolver = new F.OdspDriverUrlResolverForShareLink({
            identityType: "Enterprise",
            tokenFetcher: o => tokenProvider.getToken(siteScopes(o.siteUrl), { claims: o.claims, forceRefresh: o.refresh, siteUrl: o.siteUrl, driveId: o.driveId, itemId: o.itemId, request: o.request || null })
        }, fluidLogger, "Teams");
        pageUrlResolver = urlResolver;
        // A channel's page is made with its share link (scope default, role
        // edit); a meeting's notes without one (Teams makes the link after).
        const createRequest = fileName => cfg.create.noShareLink
            ? F.createOdspCreateContainerRequest(cfg.create.siteUrl, cfg.create.driveId, cfg.create.filePath, fileName)
            : F.createOdspCreateContainerRequest(cfg.create.siteUrl, cfg.create.driveId, cfg.create.filePath, fileName, { scope: "default", role: "edit" });
        reg("FluidUrlResolverProvider", { get FluidUrlResolverProvider() { return this }, urlResolver, get Disposable() { return this }, dispose() {} });
        reg("FluidDocumentServiceFactoryProvider", { get FluidDocumentServiceFactoryProvider() { return this }, documentServiceFactory,
                                                     getCreateDocumentRequest: async n => createRequest(n), get Disposable() { return this }, dispose() {} });

        // Teams' code loader (its 835081): the package's files from the
        // CDN's versionless code load details for its family, into the
        // frame; a configurable runtime factory gets the code details'
        // config. The families Teams loads: Loop's page container, Office's
        // container (also OneNote's meeting notes), the HTML canvas and the
        // Copilot board containers.
        const CODE_LOAD_DETAILS = {
            [LOOP_PACKAGE]: "/loop-page-container/versionless/loopPageContainerCodeLoadDetails.json",
            "@ms/office-fluid-container": "/container/versionless/officeContainerCodeLoadDetails.json",
            "@ms/onenote-meetings": "/container/versionless/officeContainerCodeLoadDetails.json",
            "@fluidx/html-canvas-container": "/html-canvas-container/versionless/htmlCanvasContainerCodeLoadDetails.json",
            "@fluidx/copilot-board-container": "/copilot-board-container/versionless/copilotBoardContainerCodeLoadDetails.json"
        };
        const detailsCache = new Map();
        const loadDetails = path => detailsCache.get(path) || detailsCache.set(path, json(CDN + path).catch(e => { detailsCache.delete(path); throw e })).get(path);
        const moduleCache = new Map();
        const codeLoader = {
            get IFluidCodeDetailsComparer() { return this },
            async compare(a, b) {
                const v = x => x && typeof x.package === "object" && x.package.version !== undefined ? (x.package.version === "0.0.1" ? "0.0.1" : Number(x.package.version)) : undefined;
                const va = v(a), vb = v(b);
                if (va === undefined || vb === undefined || a.package.name !== b.package.name) return undefined;
                return va === vb ? 0 : va === "0.0.1" ? -1 : vb === "0.0.1" ? 1 : va - vb;
            },
            async satisfies() { return true },
            async load(codeDetails) {
                const name = typeof codeDetails.package === "string" ? codeDetails.package : codeDetails.package.name;
                const path = CODE_LOAD_DETAILS[name];
                if (!path) throw new Error("Codeloader does not know how to load from this source: " + name);
                let libP = moduleCache.get(path);
                if (!libP) {
                    libP = (async () => {
                        const d = await loadDetails(path);
                        const pkg = d.fluidCodeDetailsOverride && d.fluidCodeDetailsOverride.package;
                        const umd = pkg && pkg.fluid && pkg.fluid.browser && pkg.fluid.browser.umd;
                        if (!umd || !Array.isArray(umd.files)) throw new Error("Failed to get Fluid Package");
                        if (!umd.files.every(f => f.startsWith(CDN + "/"))) throw new Error("Unsupported container files, check that CDN is on allow list");
                        await Promise.all(umd.files.map(f => f.toLowerCase().endsWith(".css") ? style(f) : script(f)));
                        const l = win[umd.library];
                        if (!l || !l.fluidExport) throw new Error("Entry point of loaded package not a Fluid module");
                        emit("code", { name, version: String(pkg.version || "") });
                        return l;
                    })();
                    moduleCache.set(path, libP);
                    libP.catch(() => moduleCache.delete(path));
                }
                const lib = await libP;
                const factory = lib.fluidExport.ConfigurableRuntimeFactory;
                const config = codeDetails.config;
                const module = factory ? { fluidExport: { get IRuntimeFactory() { return this }, instantiateRuntime(c, e) { factory.configure(config); return factory.instantiateRuntime(c, e) } } } : lib;
                return { module, details: codeDetails };
            }
        };
        const configProvider = { getRawConfig: name => { const v = ecsValue(name, "FluidExperiences"); return v === null ? undefined : v } };
        const loader = new F.Loader({ urlResolver, documentServiceFactory, codeLoader, scope: { IFluidDependencySynthesizer: synth }, logger: fluidLogger, configProvider });

        // LoopComponentLoader (Teams' 910716 / 74043): a Loop component
        // inside the page (a pasted component link, Insert › a component,
        // Create Loop component). Loop hands its own dependency container
        // (the page's providers plus the page loader's driver); the
        // component gets its own Fluid loader with that driver, OST's code
        // loader and the container wrapped with NestedLoopComponentHosting
        // and its own ResolvedUrlProvider. A link loads as Teams' existing
        // container request (ops from the cache, connected once loaded);
        // code details make a new detached container (Loop attaches it).
        reg("LoopComponentLoader", {
            get LoopComponentLoader() { return this },
            get Disposable() { return this },
            dispose() {},
            async getLoopComponent({ loopComponentRouterInput: input, dependencySynthesizer: ds, fluidRequestHeaders, requiredProviderTypes }) {
                const p = ds.synthesize({ FluidUrlResolverProvider: "FluidUrlResolverProvider", FluidDocumentServiceFactoryProvider: "FluidDocumentServiceFactoryProvider" }, {});
                const [ur, dsf] = await Promise.all([p.FluidUrlResolverProvider, p.FluidDocumentServiceFactoryProvider]);
                if (!ur || !ur.urlResolver || !dsf || !dsf.documentServiceFactory) throw new Error("Driver unavailable");
                if (!input || (input.type !== "Fluid" && !(input.type === "Data" && input.dataType === "URL"))) throw new Error("Failed to create component.");
                let nestedContainer;
                const nested = new F.DependencyContainer(ds);
                nested.register("NestedLoopComponentHosting", Promise.resolve(nestedHosting));
                nested.register("ResolvedUrlProvider", Promise.resolve(resolvedUrls(async () => nestedContainer, async () => ur.urlResolver)));
                const scope = new F.DependencyContainer(nested);
                if (!scope.has("NamespaceLogger")) scope.register("NamespaceLogger", Promise.resolve(logger));
                const nestedLoader = new F.Loader({ urlResolver: ur.urlResolver, documentServiceFactory: dsf.documentServiceFactory, codeLoader,
                                                    scope: { IFluidDependencySynthesizer: scope }, logger: fluidLogger, configProvider });
                if (input.type === "Fluid") {
                    nestedContainer = input.pendingLocalState ? await nestedLoader.rehydrateDetachedContainerFromSnapshot(input.pendingLocalState)
                        : await nestedLoader.createDetachedContainer(input.codeDetails);
                } else {
                    const href = input.data && input.data.url ? String(input.data.url.href || input.data.url) : "";
                    // Teams' check first: the link is a Fluid file.
                    let fluid = !!(input.manifestData && typeof input.manifestData === "object");
                    if (!fluid) { try { fluid = (await ur.urlResolver.resolve({ url: href }))?.type === "fluid" } catch (e) {} }
                    if (!fluid) throw new Error("Failed to create Fluid component from the provided url.");
                    const headers = Object.assign({ [LOAD_MODE]: { opsBeforeReturn: "cached", deltaConnection: "delayed" } }, fluidRequestHeaders || {});
                    nestedContainer = await nestedLoader.resolve({ url: href, headers });
                }
                const component = await entryOf(nestedContainer);
                if (!nestedContainer.closed && nestedContainer.attachState === "Attached" && nestedContainer.connectionState === 0) nestedContainer.connect();
                if (component && component.ComponentInitializer) await component.ComponentInitializer.initialize();
                emit("nested", { type: input.type, required: Array.isArray(requiredProviderTypes) ? requiredProviderTypes.map(String) : [] });
                return component;
            }
        });

        // Teams' render options (chat-app 436488) for the HTML view; a
        // channel's Page keeps Loop's own side spacing (Teams' channel page
        // renderer passes omitHorizontalSpacing).
        const renderOptions = {
            compactMargins: vp.compactMargins ?? true,
            onlyInlineComponents: fs.enableOnlyInlineComponents ?? true,
            maxHeight: vp.maxHeight,
            narrowVisualSpacingLeft: vp.narrowVisualSpacingLeft, narrowVisualSpacingRight: vp.narrowVisualSpacingRight,
            mediumVisualSpacingLeft: vp.mediumVisualSpacingLeft, mediumVisualSpacingRight: vp.mediumVisualSpacingRight,
            visualSpacingTop: vp.visualSpacingTop ?? 0, visualSpacingBottom: 0,
            layoutMode, maxContentWidth: vp.maxContentWidth
        };
        if (cfg.kind !== "channelPages") { renderOptions.visualSpacingLeft = 0; renderOptions.visualSpacingRight = 0 }
        // Teams' title read when a compose component is sent (fluid compose
        // 997266 `lt`): ComponentWithTitle.getTitleText(), else the canvas
        // component's (ComponentCanvasProvider.getCanvasComponent()).
        titleText = async () => {
            const c = rendered;
            if (!c) return "";
            let t;
            if (c.ComponentWithTitle !== undefined) t = await c.ComponentWithTitle.getTitleText();
            else if (c.ComponentCanvasProvider) {
                const g = await c.ComponentCanvasProvider.getCanvasComponent();
                if (g && g.ComponentWithTitle !== undefined) t = await g.ComponentWithTitle.getTitleText();
            }
            return String(t || "");
        };
        const render = async component => {
            rendered = component;
            if (component.ComponentInitializer) await component.ComponentInitializer.initialize();
            const v = await (component.HTMLViewable && component.HTMLViewable.getView());
            if (!v || !v.HTMLView) throw new Error("Requested component loaded but did not provide a renderer");
            await v.HTMLView.render(div, renderOptions);
            emit("rendered", {});
            // The component's title (Loop components' ComponentTitle: its
            // title, and "titleChanged" as it is typed); a compose
            // component's file is named after it when it is sent.
            const t = component.ComponentTitle;
            if (t) {
                const send = x => emit("title", { title: String(x || "").slice(0, 400) });
                if (t.title !== undefined) send(t.title);
                else if (t.titlePromise && t.titlePromise.promise) t.titlePromise.promise.then(send, () => {});
                if (typeof t.on === "function") t.on("titleChanged", send);
            }
        };
        const watch = c => {
            c.on("closed", err => emit("closed", { errorType: String(err && err.errorType || ""), message: String(err && err.message || "").slice(0, 200) }));
            c.on("connected", () => emit("connected", {}));
            c.on("disconnected", () => emit("disconnected", {}));
        };

        if (cfg.mode === "create") {
            // A new page: a detached container from Loop's code details
            // (blueprint paragraph), shown at once, then made in the
            // channel's folder (createLinkScope default, role edit).
            container = await loader.createDetachedContainer({ package: { name: LOOP_PACKAGE, version: "0.0.1", fluid: { browser: { umd: { files: [], library: "" } } } },
                                                              config: { blueprintId: cfg.create.blueprintId || "paragraph" } });
            watch(container);
            const component = await container.getEntryPoint();
            await render(component);
            await container.attach(createRequest(cfg.create.fileName));
            resolvedUrl = container.resolvedUrl;
            const url = await container.getAbsoluteUrl("/");
            emit("created", { componentUrl: url || "", itemId: resolvedUrl && resolvedUrl.itemId || "", driveId: resolvedUrl && resolvedUrl.driveId || "" });
            if (container.connectionState === 0) container.connect();
            return;
        }

        // An existing page: Teams' container request (one-way redeem of the
        // sharing link, CLP compliant), loaded paused, then connected.
        const headers = {};
        headers[IS_SHARING_LINK_TO_REDEEM] = !!fs.oneWayRedeemEnabled;
        headers[IS_REDEMPTION_NON_DURABLE] = undefined;
        if (fs.ipEnabled) headers[IS_CLP_COMPLIANT_APP] = true;
        headers[LOAD_MODE] = { opsBeforeReturn: "cached", deltaConnection: fs.startContainerInPausedState === false ? "delayed" : "none" };
        container = await loader.resolve({ url: cfg.componentUrl, headers });
        watch(container);
        resolvedUrl = container.resolvedUrl;
        const component = await entryOf(container);
        if (!container.closed && container.connectionState === 0) container.connect();
        await render(component);
    }
    window.__ostLoopHostDebug = () => ({ connected: container ? container.connectionState : -1, attach: container ? container.attachState : "", closed: container ? container.closed : null });
    post({ dir: "hello" });
})();
