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
    const themeFor = t => new Map(teamsTheme.themeProperties
        .filter(([k]) => t === "default" || !/color|shadow/i.test(k))
        .concat([["--ms-themeColorThemeName", t]]));
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
        setTheme(t) {
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
            hostScenarioName: cfg.kind === "channelPages" ? scenario + "_Page_ChannelTab" : scenario + "_Page_Chat",
            hostName: cfg.hostName,
            hostScenarioStartTime: Date.now(),
            loopAudience: cfg.audience,
            hostSessionId: cfg.sessionId,
            hostAppVersion: cfg.hostAppVersion,
            hostAppPlatform: cfg.hostAppPlatform
        });
        fetchEcs();

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
        reg("ResolvedUrlProvider", { get ResolvedUrlProvider() { return this }, async getResolvedUrl() { return resolvedUrl || (container && container.resolvedUrl) || undefined } });

        // The frame Teams makes for the container (OfficeWebHost's
        // sourceless iframe V2): frameborder 0, tabindex -1, an empty title,
        // filling the host (layout fixedByHost), its document
        // `<body style="margin: 0px;"><div id="componentDiv">`.
        const layoutMode = ({ fixedByHost: "fixedByHost", grow: "grow" })[vp.layoutMode] || (cfg.kind === "channelPages" ? "fixedByHost" : "growHeight");
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
        const createRequest = fileName => F.createOdspCreateContainerRequest(cfg.create.siteUrl, cfg.create.driveId, cfg.create.filePath, fileName, { scope: "default", role: "edit" });
        reg("FluidUrlResolverProvider", { get FluidUrlResolverProvider() { return this }, urlResolver, get Disposable() { return this }, dispose() {} });
        reg("FluidDocumentServiceFactoryProvider", { get FluidDocumentServiceFactoryProvider() { return this }, documentServiceFactory,
                                                     getCreateDocumentRequest: async n => createRequest(n), get Disposable() { return this }, dispose() {} });

        // Teams' code loader: the package's files from the CDN's code load
        // details, into the frame; a configurable runtime factory gets the
        // code details' config.
        let details = null;
        const loadDetails = async () => details || (details = await json(CDN + "/loop-page-container/versionless/loopPageContainerCodeLoadDetails.json"));
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
                if (name !== LOOP_PACKAGE) throw new Error("OST can't load this Loop container: " + name);
                let lib = moduleCache.get(name);
                if (!lib) {
                    const d = await loadDetails();
                    const pkg = d.fluidCodeDetailsOverride && d.fluidCodeDetailsOverride.package;
                    const umd = pkg && pkg.fluid && pkg.fluid.browser && pkg.fluid.browser.umd;
                    if (!umd || !Array.isArray(umd.files)) throw new Error("Failed to get Fluid Package");
                    if (!umd.files.every(f => f.startsWith(CDN + "/"))) throw new Error("Unsupported container files, check that CDN is on allow list");
                    await Promise.all(umd.files.map(f => f.toLowerCase().endsWith(".css") ? style(f) : script(f)));
                    lib = win[umd.library];
                    if (!lib || !lib.fluidExport) throw new Error("Entry point of loaded package not a Fluid module");
                    moduleCache.set(name, lib);
                    emit("code", { version: String(pkg.version || "") });
                }
                const factory = lib.fluidExport.ConfigurableRuntimeFactory;
                const config = codeDetails.config;
                const module = factory ? { fluidExport: { get IRuntimeFactory() { return this }, instantiateRuntime(c, e) { factory.configure(config); return factory.instantiateRuntime(c, e) } } } : lib;
                return { module, details: codeDetails };
            }
        };
        const configProvider = { getRawConfig: name => { const v = ecsValue(name, "FluidExperiences"); return v === null ? undefined : v } };
        const loader = new F.Loader({ urlResolver, documentServiceFactory, codeLoader, scope: { IFluidDependencySynthesizer: synth }, logger: fluidLogger, configProvider });

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
        const render = async component => {
            if (component.ComponentInitializer) await component.ComponentInitializer.initialize();
            const v = await (component.HTMLViewable && component.HTMLViewable.getView());
            if (!v || !v.HTMLView) throw new Error("Requested component loaded but did not provide a renderer");
            await v.HTMLView.render(div, renderOptions);
            emit("rendered", {});
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
        const entry = await container.getEntryPoint();
        let component = entry;
        const path = resolvedUrl && resolvedUrl.dataStorePath;
        if (path && path !== "/" && entry && entry.UrlRouterFetcher) {
            const router = await entry.UrlRouterFetcher.getUrlRouter();
            const r = router && await router.request({ url: path });
            if (r && r.status === 200 && r.value) component = r.value;
        }
        if (!container.closed && container.connectionState === 0) container.connect();
        await render(component);
    }
    window.__ostLoopHostDebug = () => ({ connected: container ? container.connectionState : -1, attach: container ? container.attachState : "", closed: container ? container.closed : null });
    post({ dir: "hello" });
})();
