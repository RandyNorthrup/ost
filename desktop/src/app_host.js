// OST's TeamsJS host: Teams' host side of the TeamsJS protocol, for the
// app page in this host page's frame (docs/spec/app-host.md).
//
// This runs in an isolated world of the host page, which OST loads with
// Teams' own origin (https://teams.cloud.microsoft), as Teams frames app
// pages: the app sits in an iframe with Teams' attributes, posts TeamsJS
// requests to its parent (or, from frames nested in it, NAA requests to
// the top window), and gets Teams' answers by postMessage, from Teams'
// origin. The page's main world and the app's frames can't see this
// world; native calls (tokens, saving a tab) go to OST over its web
// channel object `ost`. Tokens pass through here and are never logged.
(() => {
    if (window.__ostAppHost) return;
    window.__ostAppHost = true;
    // Teams' runtime answer to initialize (measured from Teams on the web
    // 2026-11-16, apiVersion 4).
    const RUNTIME = {
        apiVersion: 4,
        hostVersionsInfo: { adaptiveCardSchemaVersion: { majorVersion: 1, minorVersion: 5 } },
        canParentManageNAATrustedOrigins: true,
        isDeeplyNestedAuthSupported: true,
        isNAAChannelRecommended: true,
        supports: {
            app: { notifySuccessResponse: {} }, appInstallDialog: {}, appEntity: {}, call: {}, chat: {}, clipboard: {},
            conversations: {}, copilot: {}, dialog: { url: { bot: {}, parentCommunication: {} }, card: { bot: {} }, update: {} },
            externalAppAuthentication: {}, externalAppAuthenticationForCEA: {}, externalAppCardActions: {},
            externalAppCardActionsForCEA: {}, externalAppCardActionsForDA: {}, externalAppCommands: {}, files: {},
            hostEntity: {}, interactive: {}, logs: {}, marketplace: {}, media: {}, meeting: {},
            messageChannels: { telemetry: {}, dataLayer: {} }, monetization: {}, nestedAppAuth: {}, otherAppStateChange: {},
            pages: { appButton: {}, backStack: {}, config: {}, fullTrust: {}, tabs: {}, currentApp: {} }, people: {},
            permissions: {}, remoteCamera: {}, sharing: { history: {} }, stageView: { self: {} }, store: {},
            teams: { fullTrust: { joinedTeams: {} } }, teamsCore: {}, thirdPartyCloudStorage: {}, webStorage: {}, shortcutRelay: {}
        }
    };
    // Teams' shortcuts as it lists them to apps (shortcutRelay, measured
    // for Storyline).
    const HOST_SHORTCUTS = ["ctrl+.", "alt+/", "ctrl+alt+e", "ctrl+/", "ctrl+shift+/", "ctrl+alt+g", "alt+shift+n", "ctrl+shift+f", "ctrl+shift+,",
        "ctrl+f1", "ctrl+alt+shift+r", "alt+q", "ctrl+\\", "ctrl+shift+1", "ctrl+shift+2", "ctrl+shift+3", "ctrl+shift+4", "ctrl+shift+5",
        "ctrl+shift+6", "ctrl+shift+7", "ctrl+shift+8", "ctrl+shift+9", "alt+shift+l", "alt+shift+m", "ctrl+alt+t", "ctrl+shift+f6", "ctrl+f6",
        "ctrl+alt+f", "shift+esc", "f", "p", "del", "s", "r", "t", "e", "u", "q", "alt+j", "ctrl+alt+r", "alt+p", "alt+c", "alt+r", "alt+1",
        "alt+2", "alt+3", "alt+4", "alt+5", "alt+6", "alt+7", "alt+8", "alt+9", "meta+shift+y", "ctrl+alt+z", "ctrl+alt+u", "ctrl+alt+q",
        "ctrl+alt+b", "ctrl+alt+a", "ctrl+alt+c", "alt+pagedown", "alt+pageup", "ctrl+alt+down", "ctrl+alt+up", "ctrl+shift+a", "ctrl+shift+a",
        "ctrl+shift+a", "ctrl+shift+s", "ctrl+shift+d", "ctrl+shift+d", "ctrl+shift+j", "ctrl+shift+r", "alt+shift+a", "alt+shift+v",
        "ctrl+shift+e", "ctrl+shift+space", "ctrl+shift+m", "ctrl+shift+u", "ctrl+shift+o", "ctrl+shift+y", "ctrl+shift+k", "alt+shift+c",
        "ctrl+shift+l", "ctrl+alt+shift+s", "ctrl+shift+h", "ctrl+space", "alt+shift++", "alt+shift+=", "alt+shift+-", "alt+shift+_",
        "alt+shift+0", "ctrl+alt+shift+1", "shift+esc", "ctrl+alt+k", "ctrl+alt+u", "ctrl+alt+m", "ctrl+alt+c", "alt+t", "alt+l",
        "ctrl+alt+shift+2", "ctrl+alt+shift+8", "ctrl+f", "ctrl+alt+w", "ctrl+alt+q", "ctrl+alt+enter", "ctrl+shift+enter"];
    // What frames nested in the app may ask the top window (Teams lets
    // them do NAA only).
    const NESTED_FUNCS = new Set(["nestedAppAuth.execute"]);
    // Teams' {placeholder} names that differ from the context's keys.
    const ALIASES = { upn: "userPrincipalName", tenantId: "tid", trackingId: "appSessionId" };
    const now = () => performance.timeOrigin + performance.now();
    const origin = u => { try { return new URL(u).origin.toLowerCase() } catch (e) { return "" } };

    new QWebChannel(qt.webChannelTransport, channel => {
        const ost = channel.objects.ost;
        const cfg = JSON.parse(ost.config);
        const ctx = Object.assign({}, cfg.context);
        let frame = null;
        let handlers = new Set();
        let unloadWaiter = null;
        const trusted = new Set();
        const pending = new Map();
        let seq = 0;
        // (The address may reach here with its braces percent-encoded.)
        // A placeholder the context has no value for stays as it is (Teams
        // left `{groupId}` and `{channelType}` in OneNote's configuration
        // address in a chat).
        // Before the query the value goes in as it is (Lists'
        // `https://{teamSiteDomain}{teamSitePath}/_layouts/…` became
        // `https://<tenant>.sharepoint.com/sites/OSTTestTeam/_layouts/…` in
        // Teams' load event); in the query it is URI-encoded.
        const fill = url => {
            const s = String(url || "");
            const q = s.indexOf("?");
            return s.replace(/(?:\{|%7B)(\w+)(?:\}|%7D)/gi, (m, k, at) => {
                const key = ALIASES[k] || k;
                if (!(key in ctx)) return m;
                const v = ctx[key];
                const text = v === undefined || v === null ? "" : String(v);
                return q >= 0 && at > q ? encodeURIComponent(text) : text;
            });
        };
        // Native calls answer by id.
        ost.reply.connect((id, json) => {
            const f = pending.get(id);
            if (f) { pending.delete(id); f(json); }
        });
        const native = (kind, payload) => new Promise(resolve => {
            const id = cfg.hostId + ":" + (++seq);
            pending.set(id, resolve);
            ost.request(kind, id, JSON.stringify(payload));
        });
        // Teams' answer (its sendResponseMessage): the request's id, its
        // uuid, the result and the app's origin.
        const respond = (source, to, d, args) => {
            const uuid = d.uuid !== undefined && d.uuid !== null ? String(d.uuid) : d.uuidAsString;
            try { source.postMessage({ id: d.id, uuidAsString: uuid, args, origin: to, monotonicTimestamp: now() }, to) } catch (e) {}
        };
        // Teams' requests to the app (events): func and args.
        const send = (func, args) => {
            if (!frame || !frame.contentWindow) return;
            const msg = { func, monotonicTimestamp: now() };
            if (args !== undefined) msg.args = args;
            try { frame.contentWindow.postMessage(msg, "*") } catch (e) {}
        };
        const context = () => Object.assign({}, ctx, { frameContext: cfg.frameContext });

        // Load another address in the frame as Teams does for its cached
        // app frames: beforeUnload, then (after readyToUnload) load with
        // the new entity and address; an app that handles neither is
        // simply navigated.
        const relaunch = (entityId, template) => {
            ctx.entityId = entityId || ctx.entityId;
            cfg.url = template || cfg.url;
            const contentUrl = fill(cfg.url);
            const go = () => {
                if (handlers.has("load")) send("load", [{ entityId: ctx.entityId, contentUrl }]);
                else frame.src = contentUrl;
            };
            if (handlers.has("beforeUnload")) {
                unloadWaiter = go;
                send("beforeUnload");
                setTimeout(() => { if (unloadWaiter === go) { unloadWaiter = null; go() } }, 5000);
            } else go();
        };
        ost.relaunchRequested.connect((entityId, template) => relaunch(entityId, template));
        // Teams' Save in the tab configuration dialog: `settings.save` with
        // `[{}]`; the page answers settings.save.success (or .failure)
        // after setting its settings (TeamsJS answers for a page that
        // registered no save handler).
        ost.saveRequested.connect(() => send("settings.save", [{}]));
        // A dialog this app opened (tasks.startTask) closed: Teams answers
        // the request with [error, result].
        const tasks = new Map();
        ost.taskFinished.connect((callId, json) => {
            const t = tasks.get(callId);
            if (!t) return;
            tasks.delete(callId);
            let r = {};
            try { r = JSON.parse(json) } catch (e) {}
            respond(t.source, t.from, t.d, [r.error === undefined ? null : r.error, r.result]);
        });
        // A message for the app's frame from Teams (messageForChild,
        // messageForParent between a dialog and its opener).
        ost.frameMessage.connect((func, json) => { let a = []; try { a = JSON.parse(json) } catch (e) {} send(func, a) });
        ost.themeChanged.connect(() => { ctx.theme = ost.theme; if (handlers.has("themeChange")) send("themeChange", [ost.theme]) });

        const handle = async (d, source, from, nested) => {
            const f = d.func;
            const args = Array.isArray(d.args) ? d.args : [];
            switch (f) {
            case "initialize":
                // A new document in the frame: its handlers start afresh.
                handlers = new Set();
                // Teams offers deeply nested NAA to some apps only (Notes,
                // Storyline: yes; meeting Q&A and Whiteboard: no).
                respond(source, from, d, [cfg.frameContext, cfg.hostClientType, "2.0.0", JSON.stringify(Object.assign({}, RUNTIME,
                    { canParentManageNAATrustedOrigins: cfg.deepNaa !== false, isDeeplyNestedAuthSupported: cfg.deepNaa !== false }))]);
                ost.event("initialize", JSON.stringify({ version: String(args[0] || "") }));
                return;
            case "getContext":
                respond(source, from, d, [context()]);
                return;
            case "authentication.getUser":
                respond(source, from, d, [true, { loginHint: ctx.loginHint, oid: ctx.userObjectId, tid: ctx.tid, upn: ctx.userPrincipalName, dataResidency: "public" }]);
                return;
            case "registerHandler":
                if (typeof args[0] === "string") handlers.add(args[0]);
                return;
            case "readyToUnload":
                if (unloadWaiter) { const g = unloadWaiter; unloadWaiter = null; g(); }
                return;
            case "appInitialization.appLoaded":
                ost.event("appLoaded", "{}");
                return;
            case "appInitialization.success":
                respond(source, from, d, [null]);
                ost.event("success", "{}");
                return;
            case "appInitialization.failure":
            case "appInitialization.expectedFailure":
                respond(source, from, d, [null]);
                ost.event("failure", JSON.stringify({ reason: String((args[0] && args[0].reason) || args[0] || "") }));
                return;
            case "nestedAppAuth.execute": {
                const r = await native("naa", { request: typeof d.data === "string" ? d.data : "", origin: from, requestedTrust: trusted.has(from), nested });
                respond(source, from, d, [null, r]);
                return;
            }
            case "nestedAppAuth.manageNAATrustedOrigins": {
                const req = args[0] || {};
                const list = Array.isArray(req.appOrigins) ? req.appOrigins : [];
                const action = String(req.action || "").trim().toUpperCase();
                if (action === "ADD") {
                    let n = 0;
                    for (const o of list) { const x = origin(o); if (x) { trusted.add(x); n++ } }
                    respond(source, from, d, [{ status: n === list.length && n > 0 ? "success" : "limited" }]);
                } else if (action === "DELETE") {
                    const deleted = list.filter(o => trusted.delete(origin(o)));
                    respond(source, from, d, [{ status: deleted.length === list.length ? "success" : "limited", deleted }]);
                }
                return;
            }
            case "authentication.getAuthToken": {
                const opts = args[0] && typeof args[0] === "object" && !Array.isArray(args[0]) ? args[0] : { resources: args[0], claims: args[1], silent: args[2] };
                const r = JSON.parse(await native("sso", { resources: opts.resources || [], claims: opts.claims || [], silent: !!opts.silent, teamSiteDomain: ctx.teamSiteDomain || "" }));
                respond(source, from, d, r.token ? [true, r.token] : [false, r.error || "FailedToGetToken"]);
                return;
            }
            case "settings.setSettings": {
                const s = args[0] || {};
                if (cfg.frameContext === "content") {
                    // A content page setting its tab up (the Notes page once
                    // it has made the channel's section): Teams saves the
                    // tab, answers, then loads the new address.
                    const r = JSON.parse(await native("saveTab", { settings: s }));
                    respond(source, from, d, r.ok ? [true] : [false, { errorCode: 500, message: r.error || "" }]);
                    if (r.ok) { ost.event("tabSaved", JSON.stringify({ entityId: String(s.entityId || "") })); relaunch(s.entityId, s.contentUrl); }
                } else {
                    cfg.settings = s;
                    respond(source, from, d, [true]);
                    ost.event("settings", JSON.stringify(s));
                }
                return;
            }
            case "settings.getSettings":
                respond(source, from, d, [cfg.settings || { entityId: ctx.entityId, contentUrl: fill(cfg.url) }]);
                return;
            case "settings.setValidityState":
                ost.event("validity", JSON.stringify({ valid: !!args[0] }));
                return;
            case "executeDeepLink":
                respond(source, from, d, [true]);
                ost.event("openLink", JSON.stringify({ url: String(args[0] || "") }));
                return;
            case "conversations.closeConversation":
                return;
            case "getChatMembers": {
                // In a chat: its members' sign-in names (measured
                // `[{members: [{upn}, …]}]`).
                if (!ctx.chatId) return;
                const r = JSON.parse(await native("chatMembers", {}));
                respond(source, from, d, [{ members: (r.upns || []).map(u => ({ upn: u })) }]);
                return;
            }
            case "copilot.eligibility.getEligibilityInfo":
                // Teams' answer for the signed-in user (measured for the
                // Workflows dialog).
                respond(source, from, d, [{ cohort: "bcais", ageGroup: null, isCopilotEnabledRegion: true, isCopilotEligible: ctx.userLicenseType === "Copilot",
                    isOptedOutByAdmin: false, userClassification: { persona: "other" }, featureSet: { uxFeatures: [], serverFeatures: [] },
                    settings: { conversationSettings: { isOptionalConnectedExperiencesEnabled: null } } }]);
                return;
            case "settings.save.success":
                ost.event("saveSuccess", JSON.stringify(cfg.settings || {}));
                return;
            case "settings.save.failure":
                ost.event("saveFailure", JSON.stringify({ reason: String(args[0] || "") }));
                return;
            case "tasks.startTask": {
                // A dialog (dialog.url.open / tasks.startTask): Teams shows
                // it and answers when it closes.
                const info = args[0] && typeof args[0] === "object" ? args[0] : {};
                const callId = cfg.hostId + ":task:" + (++seq);
                tasks.set(callId, { source, from, d });
                ost.event("startTask", JSON.stringify({ callId, taskInfo: info }));
                return;
            }
            case "tasks.completeTask":
                // From a dialog's own page: its result (dialog.url.submit).
                ost.event("completeTask", JSON.stringify({ result: args[0] === undefined ? null : args[0] }));
                return;
            case "tasks.updateTask":
                ost.event("updateTask", JSON.stringify({ taskInfo: args[0] || {} }));
                return;
            case "messageForParent":
                ost.event("messageForParent", JSON.stringify({ message: args[0] === undefined ? null : args[0] }));
                return;
            case "messageForChild":
                ost.event("messageForChild", JSON.stringify({ message: args[0] === undefined ? null : args[0] }));
                return;
            case "loadingCallback":
                // Meeting Whiteboard: whether the board loaded (Teams logs
                // it and answers).
                respond(source, from, d, []);
                ost.event("loading", JSON.stringify({ success: args[0] === true, error: typeof args[1] === "string" ? args[1].slice(0, 200) : "" }));
                return;
            case "changeWhiteboardUrl": {
                // Meeting Whiteboard reports the meeting's board: Teams
                // keeps it for the meeting (without the board's proof
                // token) and answers.
                respond(source, from, d, []);
                const url = typeof args[0] === "string" ? args[0] : "";
                if (cfg.meetingBoard && url) {
                    const r = JSON.parse(await native("saveBoard", { url, organizer: cfg.meetingBoard.organizer || "" }));
                    ost.event("boardSaved", JSON.stringify({ ok: !!r.ok }));
                }
                return;
            }
            case "readyForUrl":
                // Meeting Whiteboard's custom message: Teams answers, then
                // passes the meeting's board content (none yet).
                respond(source, from, d, []);
                if (handlers.has("updateBoardContentFromTeams")) send("updateBoardContentFromTeams", ["[]", ""]);
                return;
            case "shortcutRelay.getHostShortcuts":
                // Teams' own keyboard shortcuts, which the app passes up.
                respond(source, from, d, [{ shortcuts: HOST_SHORTCUTS, overridableShortcuts: [] }]);
                return;
            default:
                // Not answered, as Teams leaves what it doesn't handle; the
                // name only, never the arguments.
                ost.log("unhandled " + String(f).slice(0, 80));
            }
        };

        addEventListener("message", e => {
            const d = e.data;
            if (!d || typeof d !== "object" || typeof d.func !== "string" || !frame) return;
            const fromFrame = e.source === frame.contentWindow;
            let nested = false;
            if (!fromFrame) { try { nested = !!e.source && e.source !== window && e.source.top === window } catch (x) { nested = false } }
            if (!fromFrame && !nested) return;
            if (nested && (cfg.deepNaa === false || !NESTED_FUNCS.has(d.func))) return;
            const from = origin(e.origin);
            if (!from.startsWith("https://")) return;
            handle(d, e.source, from, nested);
        });

        // The app's frame, as Teams' hwc-iframe.
        frame = document.createElement("iframe");
        frame.id = "cacheable-iframe:" + cfg.appId;
        frame.setAttribute("data-tid", "hwc-iframe");
        frame.name = "embedded-page-container";
        frame.title = cfg.title || "";
        frame.setAttribute("sandbox", "allow-storage-access-by-user-activation allow-scripts allow-same-origin allow-top-navigation-to-custom-protocols allow-forms allow-popups allow-popups-to-escape-sandbox allow-pointer-lock allow-modals allow-downloads");
        frame.setAttribute("allow", "clipboard-write *; media-playback-while-not-visible 'none'; local-network-access *; camera *; microphone *; encrypted-media *; speaker-selection *;");
        frame.setAttribute("allowfullscreen", "true");
        frame.setAttribute("data-appid", cfg.appId);
        frame.setAttribute("data-sessionid", ctx.appSessionId || "");
        frame.style.cssText = "border: 0px; width: 100%; height: 100%; visibility: visible;";
        frame.src = fill(cfg.url);
        document.body.appendChild(frame);
        ost.event("framed", JSON.stringify({ origin: origin(frame.src) }));
    });
})();
