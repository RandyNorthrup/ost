import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtWebEngine
import QtWebChannel
import com.ost.desktop

// A web app Teams embeds (Whiteboard, Clipchamp, Help), shown in place as
// Teams shows it: the app's header (Teams' entity header when the app's id
// is known; else icon and name, Reload, Open in browser), then the page. Pages keep their sign-in in OST's own web profile (one for the
// whole app, in Main.qml; stored on disk, like Teams'), only https pages load, and pop-ups (sign-in)
// open in a window of their own.
Item {
    id: root
    property string appName
    property string appIcon
    property color appColor: theme.brand
    property url home
    /// The app's own header (icon, name, Reload, Open in browser); off for
    /// a channel tab, which Teams shows bare under the channel's tabs.
    property bool showHeader: true
    /// A channel's Page: show only the Loop page itself (its toolbar and
    /// canvas), as Teams draws it, without the Loop app around it.
    property bool pageOnly: false
    readonly property alias view: web
    // ---- Personal apps (docs/spec/app-host.md "Personal apps") ---------
    // An app opened from the app bar (Whiteboard, Shifts, Clipchamp,
    // Copilot, the Office apps): Teams frames the app's personal tab (its
    // definition's staticTabs) in its host, with Teams' app header unless
    // the app is full screen.
    property bool personalApp: false
    /// The personal tab to open (else the app's first).
    property string personalEntity: ""
    /// The personal tab's subEntityId (a deep link's context).
    property string personalSubEntity: ""
    /// The tab Teams opens (from the definition): entity_id, content_url…
    property var personalTab: null
    property bool personalFullScreen: false
    /// Server-rendered app (Copilot): Teams posts its first page a form
    /// with the app's token (app_host.js).
    property bool ssr: false
    /// The frame's `allow` list when it differs from Teams' default.
    property string frameAllow: ""
    /// Capabilities Teams adds to its runtime answer for this app.
    property var runtimeSupports: null
    /// The host's shortcuts for shortcutRelay.getHostShortcuts, where the
    /// window's differ from the main window's (the meeting window's).
    property var hostShortcuts: null
    /// TeamsJS hostClientType ("desktop", as Teams desktop).
    property string hostClientType: "desktop"
    /// An Office file's page: "<serviceName>.<ctx>" of who opened it.
    property string officeSource: ""
    readonly property bool headerShown: showHeader && !personalFullScreen

    Rectangle { anchors.fill: parent; color: theme.surface }

    /// The app's Teams id: Teams' own app header (entity-header) then,
    /// with the app's tile from its definition and its "…" menu.
    property string appId: ""
    // The tile and name from the app's definition (kept once read: other
    // About dialogs share the backend's slot).
    property string tileUrl: ""
    /// Teams' "Present now" in a personal app's header
    /// (personal_app_header_present_button_title; ECS
    /// enablePersonalAppsSimplifiedHeaderPresentButton, on): share the app
    /// in the call, or start a meeting and share it.
    property bool presentNow: personalApp && appId.length > 0
    signal presentRequested()
    Connections {
        target: backend
        enabled: root.appId.length > 0 && root.tileUrl.length === 0
        function onAppAboutJsonChanged() {
            const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
            if (r && r.app === root.appId && r.about && r.about.icon) root.tileUrl = r.about.icon
        }
    }
    onAppIdChanged: if (appId.length > 0) backend.appAboutLoad(appId)
    function moreMenuForTest() { teamsMore.openMenu() }
    /// Test hook: the page's visibility and size as Chromium sees them.
    function stateForTest(cb) { web.runJavaScript("JSON.stringify({v: document.visibilityState, w: innerWidth, h: innerHeight, f: !!document.querySelector('iframe')})", r => cb(String(r))) }
    /// Make the page draw a new frame. The view's last picture goes black
    /// when the call window's video tiles go away (seen with the Avatars
    /// panel when the last other person left: the page itself was still
    /// visible and drawn, and its next frame showed again).
    function refreshFrame() { web.runJavaScript("document.body.style.opacity = '0.999'; setTimeout(() => document.body.style.opacity = '', 200)") }
    /// Reload the page (Teams' Reload tab): a hosted app is framed again.
    function reload() { if (root.teamsHost) root.startHost(); else web.reload() }

    // ---- Teams' app host (TeamsJS), docs/spec/app-host.md --------------
    // Teams frames an embedded app's page in its own page and answers its
    // TeamsJS calls (initialize, getContext, nestedAppAuth…) by
    // postMessage, from Teams' origin. With teamsHost OST does the same: it
    // loads a host page with Teams' origin (https://teams.cloud.microsoft),
    // frames `home` in it as Teams' hwc-iframe, and answers from a script
    // in an isolated world (app_host.js), which calls OST through this
    // web channel for tokens and for saving the tab.
    /// Host `home` as a TeamsJS app.
    property bool teamsHost: false
    /// The tab's (or dialog's) part of the app's context: entityId,
    /// subEntityId…; OST adds the user's, the channel's and the team's.
    property var hostContext: ({})
    /// TeamsJS frameContext: content (a tab), settings (its configuration
    /// page), remove, task (a dialog), sidePanel, meetingStage.
    property string frameContext: "content"
    /// Whether frames nested in the app may use NAA (Teams' runtime
    /// isDeeplyNestedAuthSupported: on for Notes and Storyline, off for
    /// meeting Q&A and Whiteboard).
    property bool deepNaa: true
    /// Where the tab lives: its channel (or chat) thread, its team's thread
    /// and its id (the app saving its settings rewrites it there).
    property string hostThread: ""
    property string hostTeamThread: ""
    property string hostTabId: ""
    /// What the hosted app did (TeamsJS initialize, appLoaded, success,
    /// failure, settings, validity, openLink…), as (name, JSON).
    signal hostEvent(string name, string json)
    readonly property string hostId: "h" + Math.floor(Math.random() * 1e9).toString(36) + Date.now().toString(36)
    /// The app's session (getContext's appSessionId, the frame's
    /// data-sessionid): new for each host unless given (Teams' Workflows
    /// dialog uses the channel's id).
    property string hostSessionId: ""
    readonly property string appSessionId: hostSessionId || newGuid()
    /// A meeting chat's Whiteboard: {organizer, title, params}. Teams opens
    /// the meeting's own board (its fluidboard address, with Teams'
    /// parameters) and keeps the board Whiteboard reports.
    property var meetingBoard: null
    /// A video app (Avatars): its frames' socket and origin (app_host.js).
    property var videoApp: null
    /// A script for the app's own frames (in their world, from the start).
    property string frameScript: ""
    /// Ask the hosted configuration page to save (Teams' Save).
    function requestSave() { hostBridge.saveRequested() }
    /// Answer a dialog this app opened (tasks.startTask): `error` (null, or
    /// Teams' "User cancelled/closed the task module.") and its result.
    function finishTask(callId, error, result) { hostBridge.taskFinished(callId, JSON.stringify({ error: error, result: result })) }
    /// Post Teams' event `func` with `args` to the app's frame.
    function sendFrameMessage(func, args) { hostBridge.frameMessage(func, JSON.stringify(args || [])) }
    // The dialog this app has open (tasks.startTask), if any.
    property var openTask: null
    Connections {
        target: root
        function onHostEvent(name, json) { root.taskEvent(name, json) }
    }
    function taskEvent(name, json) {
        if (name === "startTask") {
            const r = JSON.parse(json)
            const info = r.taskInfo || {}
            // A page (dialog.url); adaptive-card dialogs aren't drawn.
            if (!info.url || String(info.url).indexOf("https://") !== 0) { root.finishTask(r.callId, "User cancelled/closed the task module.", null); return }
            // (Made at run time: the dialog hosts a WebApp itself.)
            const c = Qt.createComponent("TaskModuleDialog.qml")
            if (c.status !== Component.Ready) { console.warn("APPHOST dialog", c.errorString()); root.finishTask(r.callId, "User cancelled/closed the task module.", null); return }
            const d = c.createObject(root, { opener: root, callId: r.callId, taskInfo: info, appId: root.appId, appName: root.appName, appIcon: root.tileUrl,
                                             hostThread: root.hostThread, hostTeamThread: root.hostTeamThread })
            d.finished.connect((callId, error, result) => { root.finishTask(callId, error, result); if (root.openTask === d) root.openTask = null; Qt.callLater(() => d.destroy()) })
            d.messageForParent.connect(m => root.sendFrameMessage("messageForParent", [m]))
            root.openTask = d
            d.open()
        } else if (name === "messageForChild" && root.openTask) {
            root.openTask.sendToPage(JSON.parse(json).message)
        }
    }
    property var hostEvents: []
    /// TeamsJS's theme names.
    readonly property string hostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    property bool hostLoading: false
    property string channelJs: ""
    function newGuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 3 | 8)).toString(16)
        })
    }
    // The address the frame loads: `home`, or the meeting's board.
    property string hostUrl: ""
    /// A hosted app's address as stored, placeholders kept (a `url`
    /// property can't hold `https://{teamSiteDomain}{teamSitePath}/…`,
    /// Lists' address); else `home`.
    property string homeTemplate: ""
    readonly property string hostAddress: homeTemplate || home.toString()
    function startHost() {
        // A personal app: its personal tab from the app's definition first.
        if (root.personalApp && !root.personalTab) {
            backend.appHostRequest(root.appId, "", "", "", "personalTab", root.hostId + ":tab", JSON.stringify({ entity: root.personalEntity }))
            return
        }
        const address = root.personalTab && !root.homeTemplate ? root.personalTab.content_url : root.hostAddress
        if (!address) return
        root.hostUrl = address
        if (root.meetingBoard)
            backend.appHostRequest(root.appId, root.hostThread, root.hostTeamThread, root.hostTabId, "board", root.hostId + ":board",
                                   JSON.stringify({ organizer: root.meetingBoard.organizer || "", title: root.meetingBoard.title || "" }))
        else
            backend.appHostRequest(root.appId, root.hostThread, root.hostTeamThread, root.hostTabId, "context", root.hostId + ":ctx", JSON.stringify({ mySite: root.ssr }))
    }
    function loadHostPage(ctx) {
        // A personal app's context: its tab's entity, full screen or not;
        // the server-rendering host feature for Copilot (measured).
        const personal = root.personalTab ? { entityId: root.personalTab.entity_id, subEntityId: root.personalSubEntity, isFullScreen: root.personalFullScreen } : {}
        const c = Object.assign({}, ctx, personal, root.hostContext, {
            appSessionId: root.appSessionId, appLaunchId: newGuid(), theme: hostBridge.theme,
            appId: root.appId, hostClientType: root.hostClientType })
        if (root.ssr) c.hostFeatures = Object.assign({}, c.hostFeatures || {}, { serverSideRendering: true })
        // An Office file's page: Teams names who opened it (measured
        // `source=TEAMS-WEB.teamsSdk_<app>_ns.rwc.content` on the web; Teams
        // desktop's platform is TEAMS-ELECTRON) and the app session.
        let url = root.hostUrl || root.hostAddress
        if (root.officeSource && url.indexOf("source=") < 0)
            url += (url.indexOf("?") < 0 ? "?" : "&") + "source=" + encodeURIComponent("TEAMS-ELECTRON." + root.officeSource + ".content") + "&appSessionId=" + c.appSessionId
        hostBridge.config = JSON.stringify({ hostId: root.hostId, url: url, appId: root.appId, title: root.appName,
                                             frameContext: root.frameContext, hostClientType: root.hostClientType, deepNaa: root.deepNaa, context: c,
                                             ssr: root.ssr, allow: root.frameAllow, supports: root.runtimeSupports, shortcuts: root.hostShortcuts,
                                             meetingBoard: root.meetingBoard ? { organizer: root.meetingBoard.organizer || "" } : null,
                                             video: root.videoApp })
        root.hostLoading = true
        web.loadHtml(backend.appHostPage(root.appName), "https://teams.cloud.microsoft/")
    }
    function hostStateForTest() {
        // The frame's address without its values (they may hold links).
        const full = root.hostUrl || root.hostAddress
        const q = full.indexOf("?")
        const u = { frame: q < 0 ? full : full.slice(0, q), params: q < 0 ? [] : full.slice(q + 1).split("&").map(p => p.split("=")[0]) }
        return JSON.stringify({ events: root.hostEvents, url: web.url.toString(), frame: u.frame || "", params: u.params || [] })
    }
    /// Point the hosted frame at another entity and address, as Teams
    /// moves its cached frame (beforeUnload, then load).
    function relaunchHost(entityId, template) { hostBridge.relaunchRequested(entityId, template) }
    QtObject {
        id: hostBridge
        WebChannel.id: "ost"
        property string config: ""
        readonly property string theme: root.hostTheme
        signal reply(string id, string json)
        signal relaunchRequested(string entityId, string template)
        signal saveRequested()
        signal taskFinished(string callId, string json)
        signal frameMessage(string func, string json)
        function request(kind, id, json) {
            if (id.indexOf(root.hostId + ":") !== 0) return
            backend.appHostRequest(root.appId, root.hostThread, root.hostTeamThread, root.hostTabId, kind, id, json)
        }
        function event(name, json) {
            root.hostEvents = root.hostEvents.concat([name])
            console.info("APPHOST " + root.appName + " " + name)
            root.hostEvent(name, json)
        }
        function log(text) { console.info("APPHOST " + root.appName + " " + text) }
    }
    WebChannel { id: hostChannel; registeredObjects: [hostBridge] }
    Connections {
        target: backend
        enabled: root.teamsHost
        function onAppHostReply(id, json) {
            if (id === root.hostId + ":tab") {
                let r = {}
                try { r = JSON.parse(json) } catch (e) {}
                if (!r.tab) {
                    console.warn("APPHOST " + root.appName + " personal tab: " + (r.error || "none"))
                    root.hostEvents = root.hostEvents.concat(["failure"])
                    return
                }
                // (The address without its values: placeholders only.)
                console.info("APPHOST " + root.appName + " personal tab " + r.tab.entity_id + " " + String(r.tab.content_url).split("?")[0] + (r.fullScreen ? " full screen" : ""))
                root.personalFullScreen = !!r.fullScreen
                root.personalTab = r.tab
                root.startHost()
            } else if (id === root.hostId + ":ctx") {
                let ctx = {}
                try {
                    const r = JSON.parse(json)
                    ctx = r.context || {}
                    // Teams' allow list for deeply nested NAA, when known.
                    if (typeof r.deepNaa === "boolean") root.deepNaa = r.deepNaa
                } catch (e) {}
                root.loadHostPage(ctx)
            } else if (id === root.hostId + ":board") {
                // The meeting's board, with Teams' parameters (else the
                // address OST was given, where Whiteboard makes one).
                let r = {}
                try { r = JSON.parse(json) } catch (e) {}
                if (r.url) root.hostUrl = backend.meetingBoardFrameUrl(r.url, JSON.stringify(root.meetingBoard.params || {}))
                console.info("APPHOST " + root.appName + " board " + (r.url ? "meeting's" : "none: " + (r.error || "")))
                backend.appHostRequest(root.appId, root.hostThread, root.hostTeamThread, root.hostTabId, "context", root.hostId + ":ctx", "{}")
            } else if (id.indexOf(root.hostId + ":") === 0) hostBridge.reply(id, json)
        }
    }

    Rectangle {
        id: header
        visible: root.headerShown
        width: parent.width
        height: !root.headerShown ? 0 : root.appId.length > 0 ? 61 : 52
        color: theme.surface
        // OST's header for apps it hosts without a Teams id.
        Row {
            visible: root.appId.length === 0
            x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 10
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: root.appIcon || "apps"; size: 22; color: root.appColor }
            Text { anchors.verticalCenter: parent.verticalCenter; text: root.appName; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        }
        Row {
            visible: root.appId.length === 0
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 4
            HeaderButton { icon: "arrow-clockwise-20"; label: "Reload"; onClicked: web.reload() }
            HeaderButton { icon: "open-20"; label: "Open in browser"; onClicked: Qt.openUrlExternally(web.url) }
        }
        // Teams' app header (entity-header, measured on winpc for Help,
        // 2026-11-09): 61 tall with a 0.67 #E0E0E0 line; the app's tile
        // (32, round, on #FAFAFA) 20 in and 14.17 down; its name (18/25.71
        // bold) at 72; "More <app> actions" (32 x 31.33, 7 from the right,
        // 14.5 down): Reload app (About and Share app: TASK-0072).
        Item {
            visible: root.appId.length > 0
            anchors.fill: parent
            Rectangle {
                x: 20; y: 14.17; width: 32; height: 32; radius: 16
                color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                // The tile, clipped round as Teams' image is; painted at twice
                // the size so it stays sharp on scaled screens.
                Canvas {
                    id: tile
                    width: 64; height: 64; scale: 0.5
                    anchors.centerIn: parent
                    readonly property string src: root.tileUrl
                    onSrcChanged: if (src) loadImage(src)
                    onImageLoaded: requestPaint()
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        if (!src || !isImageLoaded(src)) return
                        c.beginPath(); c.arc(32, 32, 32, 0, 2 * Math.PI); c.clip()
                        c.drawImage(src, 0, 0, 64, 64)
                    }
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: root.appName
            }
            Text {
                x: 72; y: 17.31; height: 25.71
                verticalAlignment: Text.AlignVCenter
                text: root.appName
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            // Present now (measured on Teams desktop, the Avatars app,
            // 2026-11-17): 116.4 x 32 against the menu (its left corners
            // rounded 4), the share glyph (20) 6 in and "Present now"
            // (14/600 #424242) at 32.
            Rectangle {
                id: presentButton
                visible: root.presentNow
                anchors.right: teamsMore.left; y: 14.2
                width: 116.4; height: 32
                topLeftRadius: 4; bottomLeftRadius: 4
                color: presentHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "share-screen-start-20"; size: 20; color: theme.onFill(presentButton, presentHover.hovered ? theme.brand : theme.textStrong) }
                Text {
                    x: 32; anchors.verticalCenter: parent.verticalCenter
                    text: "Present now"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(presentButton, presentHover.hovered ? theme.brand : theme.textStrong)
                }
                HoverHandler { id: presentHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.presentRequested() }
                Accessible.role: Accessible.Button
                Accessible.name: "Present now"
            }
            Rectangle {
                id: teamsMore
                anchors.right: parent.right; anchors.rightMargin: 7; y: 14.5
                width: 32; height: 31.33; radius: 4
                color: tmHover.hovered || appMenu.opened ? theme.menuHover : "transparent"
                function openMenu() {
                    appMenu.x = teamsMore.width - appMenu.implicitWidth
                    appMenu.y = teamsMore.height + 0.17
                    appMenu.open()
                }
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20
                             color: theme.onFill(teamsMore, appMenu.opened ? theme.brand : theme.textStrong) }
                HoverHandler { id: tmHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: teamsMore.openMenu() }
                Accessible.role: Accessible.Button
                Accessible.name: "More " + root.appName + " actions"
                // Teams' order: Reload app, a divider, About, Share app.
                MenuPopup {
                    id: appMenu
                    items: [{ label: "Reload app", icon: "arrow-clockwise-20" }, { separator: true },
                            { label: "About", icon: "info-20" }, { label: "Share app", icon: "share-20" }]
                    onPicked: i => {
                        if (i === 0) root.reload()
                        else if (i === 2) aboutDialog.show(root.appId)
                        else if (i === 3) shareForm.start(root.appId)
                    }
                }
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width
            height: root.appId.length > 0 ? 0.67 : 1
            color: root.appId.length > 0 ? theme.pick("#E0E0E0", "#3D3D3D", "#000000") : theme.dividerSoft
        }
    }

    property bool ready: false
    // Page tabs: hide the Loop app's frame (its top bar, side panel, help
    // button and first-run tour) on Loop's own pages only, so the page
    // shows as Teams draws it.
    readonly property string pageOnlyScript: "if (location.hostname === 'loop.cloud.microsoft') {"
        + " const s = document.createElement('style');"
        + " s.textContent = 'header:not(main header), aside, [role=\"banner\"], [role=\"complementary\"], button[aria-label=\"Help\"],"
        + " [role=\"dialog\"][aria-label=\"Loop Introductory Tour\"] { display: none !important }"
        // The page's own toolbar stays laid out but unseen (a strip at
        // the top right), so its panels (sharing) still have an anchor.
        + " main header { position: absolute !important; top: 0 !important; right: 0 !important; height: 1px !important;"
        + " overflow: hidden !important; opacity: 0 !important; pointer-events: none !important }"
        // The page fills the tab, edge to edge, as in Teams.
        + " main, [role=\"main\"] { position: fixed !important; inset: 0 !important; margin: 0 !important; width: auto !important;"
        + " max-width: none !important; height: auto !important; border-radius: 0 !important; box-shadow: none !important; border: 0 !important; z-index: 10 }';"
        + " document.documentElement.appendChild(s);"
        // Close the recent-pages panel and the first-run tour as a person
        // would (Loop keeps both closed afterwards), and hide Loop's
        // template gallery (Teams offers its insert row instead).
        + " const hideUp = (el, keep) => { let a = el; while (a.parentElement && !a.parentElement.contains(keep)) a = a.parentElement; a.style.display = 'none'; };"
        + " let n = 0; const t = setInterval(() => {"
        + "  document.querySelector('button[aria-label=\"Close sidebar\"][aria-expanded=\"true\"]')?.click();"
        + "  document.querySelector('[role=\"dialog\"] button[aria-label=\"Close Dialog\"]')?.click();"
        + "  const canvas = document.querySelector('[role=\"textbox\"][aria-label=\"Canvas\"]');"
        + "  if (canvas) for (const b of document.querySelectorAll('button')) {"
        + "   const label = b.textContent.trim();"
        + "   if (label === 'Template Gallery' || label.startsWith('Blank page')) hideUp(b, canvas); }"
        + "  if (++n > 40) clearInterval(t); }, 500); }"
    // Insert at the end of the page what Teams' row offers, through
    // Loop's own "/" commands, typed as real keys (Loop answers only
    // real typing). The "..." button just opens Loop's insert menu.
    function insertOnPage(command) {
        web.runJavaScript("(() => { const c = document.querySelector('[role=\"textbox\"][aria-label=\"Canvas\"]');"
            + " if (!c) return false; c.focus(); return true; })()", ok => {
                if (!ok) return
                web.forceActiveFocus()
                // To the end of the page, a new line, and Loop's insert menu.
                typer.typeText("\u0001\n/")
                insertTimer.command = command
                insertTimer.step = 0
                insertTimer.restart()
            })
    }
    KeyTyper { id: typer }
    function typeForTest(t) { typer.typeText(t) }
    Timer {
        id: insertTimer
        property string command
        property int step: 0
        interval: 600
        onTriggered: {
            if (!command) return
            if (step === 0) { typer.typeText(command); step = 1; restart() }
            else { typer.typeText("\n"); step = 0 }
        }
    }
    /// Where the page is shared (for Shared locations), e.g. "General · Team".
    property string location: ""
    Component.onCompleted: {
        web.profile = webAppsProfile.instance()
        if (root.frameScript) {
            const script = WebEngine.script()
            script.name = "ost-app-frame"
            script.sourceCode = root.frameScript
            script.injectionPoint = WebEngineScript.DocumentCreation
            script.worldId = WebEngineScript.MainWorld
            script.runsOnSubFrames = true
            web.userScripts.insert(script)
        }
        if (root.teamsHost) {
            // Qt's web channel client, from Qt's own resources.
            const x = new XMLHttpRequest()
            x.onreadystatechange = () => {
                if (x.readyState !== XMLHttpRequest.DONE) return
                root.channelJs = x.responseText
                root.startHost()
            }
            x.open("GET", "qrc:///qtwebchannel/qwebchannel.js")
            x.send()
        } else web.url = root.home
        ready = true
    }
    // Another page for the same view (a different channel's Page).
    onHomeChanged: if (ready) { if (root.teamsHost) { if (root.channelJs && !root.homeTemplate) root.startHost() } else web.url = root.home }
    onHomeTemplateChanged: if (ready && root.teamsHost && root.channelJs) root.startHost()

    // A channel's Page, as Teams heads it: the Loop page's icon and name
    // (which opens it in Loop), then Shared locations, Copy component and
    // See who has access.
    Rectangle {
        id: pageHeader
        visible: root.pageOnly
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        height: root.pageOnly ? 48 : 0; color: theme.surface
        Row {
            x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Image { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: web.icon; sourceSize: Qt.size(40, 40) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: web.title && web.title !== "Microsoft Loop" ? web.title.replace(/ - Loop$/, "") : root.appName
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally(root.home) }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 4
            PageButton { icon: "apps"; tip: "Shared locations"; onClicked: locations.open() }
            PageButton { icon: "select-object-20"; tip: "Copy component"; onClicked: { copier.text = root.home; copier.selectAll(); copier.copy() } }
            PageButton { icon: "people-checkmark-20"; tip: "See who has access"
                onClicked: web.runJavaScript("[...document.querySelectorAll('button')].find(b => b.getAttribute('aria-label') === 'Share' || b.textContent.trim() === 'Share')?.click()") }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        TextEdit { id: copier; visible: false }
        Popup {
            id: locations
            x: parent.width - width - 16; y: parent.height
            padding: 12
            background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
            contentItem: Column {
                spacing: 6
                Text { text: "Shared locations"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text { text: root.location; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
            }
        }
    }
    // Teams' insert row at the foot of a Page.
    Row {
        visible: root.pageOnly && web.loadProgress === 100
        z: 2
        anchors { left: parent.left; leftMargin: 40; bottom: parent.bottom; bottomMargin: 24 }
        spacing: 12
        InsertButton { icon: "table-20"; label: "Table"; onClicked: root.insertOnPage("table") }
        InsertButton { icon: "text-bullets-20"; label: "Bulleted list"; onClicked: root.insertOnPage("bulleted list") }
        InsertButton { icon: "task-list-square-20"; label: "Checklist"; onClicked: root.insertOnPage("checklist") }
        InsertButton { icon: "checkmark-circle-20"; label: "Task list"; onClicked: root.insertOnPage("task list") }
        InsertButton { icon: "vote-20"; label: "Voting table"; onClicked: root.insertOnPage("voting table") }
        InsertButton { icon: "more-20"; label: ""; onClicked: root.insertOnPage("") }
    }
    WebEngineView {
        id: web
        anchors { top: pageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        // The profile and first page are set once everything is complete:
        // the prototype's instance() isn't ready while bindings first run.
        settings.javascriptCanOpenWindows: true
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        // The host's channel lives in the isolated world its script runs
        // in; app frames never see it.
        webChannel: root.teamsHost ? hostChannel : null
        webChannelWorld: WebEngineScript.ApplicationWorld
        onLoadingChanged: req => {
            if (root.pageOnly && req.status === WebEngineView.LoadSucceededStatus) web.runJavaScript(root.pageOnlyScript)
            if (root.teamsHost && root.hostLoading && req.status === WebEngineView.LoadSucceededStatus) {
                root.hostLoading = false
                web.runJavaScript(root.channelJs + "\n" + backend.appHostScript(), WebEngineScript.ApplicationWorld)
            }
        }
        // https only (and the host page OST itself loads); frames inside a
        // hosted app may also be about:, blob: or data: documents.
        onNavigationRequested: req => {
            const u = req.url.toString()
            if (root.teamsHost && root.hostLoading && req.isMainFrame) return
            if (root.teamsHost && !req.isMainFrame && /^(about:|blob:|data:)/.test(u)) return
            if (u.indexOf("https://") !== 0 && u !== "about:blank") req.reject()
        }
        // Sign-in and other pop-ups get a window of their own.
        onNewWindowRequested: req => {
            const w = popup.createObject(null, {})
            req.openIn(w.view)
        }
        // Camera, microphone, location, notifications: as the app's App
        // permissions allow (Teams' device permissions, kept on this
        // device); anything else, or an app OST doesn't know, refused.
        onPermissionRequested: p => {
            const kind = ({ [WebEnginePermission.PermissionType.MediaAudioCapture]: "media",
                            [WebEnginePermission.PermissionType.MediaVideoCapture]: "media",
                            [WebEnginePermission.PermissionType.MediaAudioVideoCapture]: "media",
                            [WebEnginePermission.PermissionType.Geolocation]: "geolocation",
                            [WebEnginePermission.PermissionType.Notifications]: "notifications" })[p.permissionType] || ""
            if (root.appId && kind && backend.appPermission(root.appId, kind)) p.grant()
            else p.deny()
        }
    }

    Component {
        id: popup
        Window {
            id: pw
            readonly property alias view: pv
            width: 520; height: 680
            visible: true
            title: pv.title || root.appName
            color: theme.surface
            WebEngineView {
                id: pv
                anchors.fill: parent
                profile: web.profile
                onNavigationRequested: req => {
                    if (req.url.toString().indexOf("https://") !== 0 && req.url.toString() !== "about:blank") req.reject()
                }
                onWindowCloseRequested: pw.destroy()
                onPermissionRequested: p => p.deny()
            }
            onClosing: destroy()
        }
    }

    component PageButton: Rectangle {
        id: pb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: pbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: pb.icon; size: 20; color: theme.onFill(pb, theme.textStrong) }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        ToolTip.visible: pbh.hovered; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component InsertButton: Rectangle {
        id: ib
        property string icon
        property string label
        signal clicked()
        width: ibRow.implicitWidth + 32; height: 40; radius: 6
        color: ibh.hovered ? theme.rowHover : theme.surface; border.color: theme.stroke
        Row { id: ibRow; anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: ib.icon; size: 20; color: theme.onFill(ib, theme.textStrong) }
            Text { visible: !!ib.label; anchors.verticalCenter: parent.verticalCenter; text: ib.label; font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.onFill(ib, theme.text) }
        }
        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label || "More"
    }
    component HeaderButton: Rectangle {
        id: hb
        property string icon
        property string label
        signal clicked()
        width: hbRow.implicitWidth + 16; height: 32; radius: theme.radius
        color: hbh.hovered ? theme.rowHover : "transparent"
        Row { id: hbRow; anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: hb.icon; size: 18; color: theme.onFill(hb, theme.textStrong) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: hb.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hb, theme.text) }
        }
        HoverHandler { id: hbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // The app header's About and Share app (in this app's window, as Teams).
    AppDetailsDialog { id: aboutDialog; onShareApp: id => shareForm.start(id) }
    ShareForm { id: shareForm }
    function aboutForTest() { return aboutDialog }
    function shareFormForTest() { return shareForm }
}
