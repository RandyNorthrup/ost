// The TeamsJS host's origin checks (desktop/src/app_host.js, TASK-0353),
// with Node's own test runner and no packages: `node --test desktop/tests/`.
//
// The host runs in a sandbox that stands in for its page: the web channel
// object `ost` (config, native calls, events), the app's iframe (whose
// window records what the host posts to it) and the page's message
// listener, which the tests feed with messages from chosen origins and
// windows. URL parsing is Node's own, as the browser's would be.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../src/app_host.js", import.meta.url), "utf8");

const APP = "https://tasks.office.com";
const VALID = "https://contoso.sharepoint.com";
const FOREIGN = "https://evil.example";
const DOMAINS = ["*.sharepoint.com", "outlook.office.com"];

// Load the host with `source` (app_host.js unless a test changes it).
async function host({ source = SOURCE, cfg = {} } = {}) {
    const posted = [];
    const requests = [];
    const events = [];
    const logs = [];
    const listeners = [];
    const signals = {};
    const signal = name => ({ connect: f => { signals[name] = f } });
    const config = Object.assign({
        hostId: "h1", appId: "app-1", title: "App", url: APP + "/Home/Planner", frameContext: "content",
        hostClientType: "desktop", context: { tid: "tenant", userObjectId: "user", loginHint: "u@test", userPrincipalName: "u@test", theme: "default" }
    }, cfg);
    let reply = null;
    const answers = {
        validDomains: () => JSON.stringify(DOMAINS),
        sso: () => JSON.stringify({ token: "token" }),
        naa: () => "naa-answer"
    };
    const ost = {
        config: JSON.stringify(config),
        theme: "dark",
        reply: { connect: f => { reply = f } },
        request: (kind, id, payload) => {
            requests.push({ kind, payload: plain(JSON.parse(payload)) });
            const a = answers[kind];
            setTimeout(() => reply(id, a ? a() : "{}"), 0);
        },
        event: (name, json) => events.push({ name, data: JSON.parse(json) }),
        log: text => logs.push(text),
        relaunchRequested: signal("relaunchRequested"),
        saveRequested: signal("saveRequested"),
        taskFinished: signal("taskFinished"),
        frameMessage: signal("frameMessage"),
        themeChanged: signal("themeChanged")
    };
    // The app frame's window: what the host posts to it, with the target
    // origin it names (the browser delivers only on a match).
    const appWindow = { postMessage: (data, target) => posted.push({ data: plain(data), target }) };
    const frame = {
        contentWindow: appWindow, style: {}, attributes: {}, src: "",
        setAttribute(k, v) { this.attributes[k] = v }
    };
    const sandbox = {
        qt: { webChannelTransport: {} },
        QWebChannel: function (transport, ready) { ready({ objects: { ost } }) },
        performance, URL, setTimeout, clearTimeout, console,
        addEventListener: (type, f) => { if (type === "message") listeners.push(f) },
        document: {
            createElement: tag => {
                if (tag === "iframe") return frame;
                return { setAttribute() {}, appendChild() {}, submit() {}, remove() {} };
            },
            body: { appendChild() {} }
        }
    };
    vm.createContext(sandbox);
    vm.runInContext("var window = globalThis;", sandbox);
    const win = vm.runInContext("globalThis", sandbox);
    vm.runInContext(source, sandbox, { filename: "app_host.js" });
    await settle();
    // A message as the browser hands it to the page.
    const message = (data, origin, source = appWindow) => {
        for (const f of listeners) f({ data, origin, source });
    };
    // A window nested in the app's frame (its top is the host page), and
    // one that isn't (another top-level window).
    const nestedWindow = () => ({ top: win, postMessage: (data, target) => posted.push({ data: plain(data), target, nested: true }) });
    const otherWindow = () => ({ top: {}, postMessage: (data, target) => posted.push({ data: plain(data), target, other: true }) });
    let n = 0;
    // A TeamsJS request; resolves with what the host answered (by id).
    const ask = async (func, origin, { args = [], source, extra = {} } = {}) => {
        const id = ++n;
        const before = posted.length;
        message(Object.assign({ id, uuidAsString: "u" + id, func, args }, extra), origin, source);
        await settle();
        return posted.slice(before).filter(p => p.data && p.data.id === id);
    };
    return { ask, message, posted, requests, events, logs, signals, frame, nestedWindow, otherWindow };
}

// A copy made in this realm: the sandbox's arrays and objects have its own
// prototypes, which deepStrictEqual tells apart.
function plain(x) {
    return x === undefined ? x : JSON.parse(JSON.stringify(x));
}

// Let the host's promises and timers (native answers) run.
async function settle() {
    for (let i = 0; i < 5; i++) await new Promise(r => setTimeout(r, 0));
}

// Teams' events the host sends the app (here: the theme changing).
async function eventTargets(h) {
    const before = h.posted.length;
    h.signals.themeChanged();
    await settle();
    return h.posted.slice(before).filter(p => p.data && p.data.func === "themeChange").map(p => p.target);
}

test("the app's first origin is answered, to that origin", async () => {
    const h = await host();
    assert.equal(h.frame.src, APP + "/Home/Planner");
    for (const func of ["initialize", "getContext", "authentication.getUser"]) {
        const r = await h.ask(func, APP);
        assert.equal(r.length, 1, func);
        assert.equal(r[0].target, APP, func);
        assert.equal(r[0].data.origin, APP, func);
    }
});

test("a page outside the app's domains gets no answers and no token", async () => {
    const h = await host();
    for (const func of ["initialize", "getContext", "authentication.getUser", "authentication.getAuthToken", "navigateCrossDomain",
        "nestedAppAuth.execute", "settings.getSettings"]) {
        const r = await h.ask(func, FOREIGN, { args: func === "navigateCrossDomain" ? [VALID + "/x"] : [] });
        assert.deepEqual(r, [], func);
        assert.ok(h.logs.some(l => l.startsWith("ignored " + func + " from a page outside")), func);
    }
    assert.deepEqual(h.requests.filter(q => q.kind !== "validDomains"), [], "no native call (sso, naa) for a foreign page");
    assert.equal(h.frame.src, APP + "/Home/Planner", "a foreign page can't navigate the frame");
});

test("Teams' events go to the app's current origin only", async () => {
    const h = await host();
    await h.ask("registerHandler", APP, { args: ["themeChange"] });
    assert.deepEqual(await eventTargets(h), [APP]);
    // A foreign page doesn't become the current origin.
    await h.ask("getContext", FOREIGN);
    assert.deepEqual(await eventTargets(h), [APP]);
});

test("a valid domain is answered and becomes the current origin", async () => {
    const h = await host();
    await h.ask("registerHandler", APP, { args: ["themeChange"] });
    const r = await h.ask("getContext", VALID);
    assert.equal(r.length, 1);
    assert.equal(r[0].target, VALID);
    assert.deepEqual(await eventTargets(h), [VALID]);
    // The first origin is still the app's.
    assert.equal((await h.ask("getContext", APP)).length, 1);
    assert.deepEqual(await eventTargets(h), [APP]);
});

test("look-alike and non-https origins are not the app's", async () => {
    const h = await host();
    for (const from of ["http://tasks.office.com", "https://tasks.office.com.evil.example", "https://contoso.sharepoint.com.evil.example",
        "https://a.b.sharepoint.com", "https://sharepoint.com", "https://outlook.office.com.evil.example", "null", ""]) {
        assert.deepEqual(await h.ask("getContext", from), [], from);
    }
    assert.equal((await h.ask("getContext", "https://OUTLOOK.office.com")).length, 1, "domains match without case");
});

test("getAuthToken asks OST with the asking origin", async () => {
    const h = await host();
    const r = await h.ask("authentication.getAuthToken", APP, { args: [{ resources: [APP] }] });
    assert.deepEqual(r.map(p => p.data.args), [[true, "token"]]);
    const sso = h.requests.filter(q => q.kind === "sso");
    assert.equal(sso.length, 1);
    assert.equal(sso[0].payload.origin, APP);
    // From a page on one of the app's other domains: that page's origin,
    // which OST checks before minting (sso_origin_allowed).
    await h.ask("authentication.getAuthToken", VALID, { args: [{ resources: [VALID] }] });
    assert.deepEqual(h.requests.filter(q => q.kind === "sso").map(q => q.payload.origin), [APP, VALID]);
});

test("frames nested in the app may only use nestedAppAuth, with their own origin for the broker", async () => {
    const h = await host();
    const nested = h.nestedWindow();
    // NAA's broker checks the nested page's origin itself: OST passes it on.
    const r = await h.ask("nestedAppAuth.execute", FOREIGN, { source: nested, extra: { data: "{\"request\":1}" } });
    assert.deepEqual(r.map(p => [p.target, p.data.args]), [[FOREIGN, [null, "naa-answer"]]]);
    const naa = h.requests.filter(q => q.kind === "naa");
    assert.equal(naa.length, 1);
    assert.equal(naa[0].payload.origin, FOREIGN);
    assert.equal(naa[0].payload.nested, true);
    assert.equal(naa[0].payload.requestedTrust, false);
    // Anything else from a nested frame, even on the app's origin, is dropped.
    for (const func of ["getContext", "authentication.getAuthToken", "initialize"]) assert.deepEqual(await h.ask(func, APP, { source: h.nestedWindow() }), [], func);
    // A window that isn't in the app's frame gets nothing, NAA included.
    for (const func of ["getContext", "nestedAppAuth.execute"]) assert.deepEqual(await h.ask(func, APP, { source: h.otherWindow() }), [], func);
    assert.equal(h.requests.filter(q => q.kind === "naa").length, 1);
});

test("nested NAA is off for an app without deeply nested auth", async () => {
    const h = await host({ cfg: { deepNaa: false } });
    assert.deepEqual(await h.ask("nestedAppAuth.execute", APP, { source: h.nestedWindow(), extra: { data: "{}" } }), []);
    assert.equal(h.requests.filter(q => q.kind === "naa").length, 0);
});

test("navigateCrossDomain loads only the app's valid domains", async () => {
    const h = await host();
    const go = async url => (await h.ask("navigateCrossDomain", APP, { args: [url] })).map(p => p.data.args);
    for (const url of [FOREIGN + "/", "http://contoso.sharepoint.com/x", "javascript:alert(1)", "https://user:pw@contoso.sharepoint.com/x",
        "https://contoso.sharepoint.com.evil.example/x"]) {
        assert.deepEqual(await go(url), [[false, "Url is invalid"]], url);
        assert.equal(h.frame.src, APP + "/Home/Planner", url);
    }
    assert.deepEqual(await go(VALID + "/sites/x"), [[true]]);
    assert.equal(h.frame.src, VALID + "/sites/x");
});

// The red check: the same host with its origin check taken out answers the
// foreign page, so the tests above fail without it (they don't pass merely
// because the sandbox never delivers).
test("without the origin check a foreign page would be answered (red check)", async () => {
    const gate = "const appOrigin = async from => {";
    assert.ok(SOURCE.includes(gate), "app_host.js still has its appOrigin check");
    const h = await host({ source: SOURCE.replace(gate, "const appOrigin = async from => true; const unusedOriginCheck = async from => {") });
    assert.equal((await h.ask("getContext", FOREIGN)).length, 1);
    await h.ask("authentication.getAuthToken", FOREIGN, { args: [{ resources: [FOREIGN] }] });
    assert.equal(h.requests.filter(q => q.kind === "sso").length, 1);
});
