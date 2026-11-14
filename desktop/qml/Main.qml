import QtQuick
import QtQuick.Window
import QtWebEngine
import QtQuick.Dialogs
import com.ost.desktop

Window {
    id: window
    // --size=WxH (test harness): start at that size, e.g. to line up with a
    // reference capture of Teams.
    readonly property var startSize: {
        const a = Qt.application.arguments.find(x => x.startsWith("--size="))
        const m = a ? a.slice(7).match(/^(\d+)x(\d+)$/) : null
        return m ? [parseInt(m[1]), parseInt(m[2])] : [1280, 800]
    }
    width: startSize[0]
    height: startSize[1]
    // Teams desktop won't shrink below 800 px wide (measured on winpc).
    minimumWidth: Math.min(800, startSize[0])
    minimumHeight: Math.min(600, startSize[1])
    visible: true
    // As Teams titles its window (and so its taskbar button): the app,
    // what's open in it, then the product: "Chat | OST group test | OST",
    // "Chat | OST Test Team | General | OST", "Calendar | OST".
    title: {
        const app = rail.apps.concat(rail.extraApps).find(a => a.key === rail.current)
        const item = rail.current !== "chat" || !conversation.visible || !backend.currentChatName ? ""
            : conversation.isChannel && conversation.teamName ? conversation.teamName + " | " + backend.currentChatName
            : backend.currentChatName
        return [app ? app.label : "", item, "OST"].filter(Boolean).join(" | ")
    }
    color: theme.surface
    // Teams desktop draws its own title bar and window buttons.
    flags: (backend.systemFrame ? Qt.Window : (Qt.Window | Qt.FramelessWindowHint))
        | (pinned ? Qt.WindowStaysOnTopHint : 0)

    // Light or dark, as chosen in Settings > Appearance (default: the
    // system's, like Teams' "Follow operating system theme"). --theme=dark
    // forces one for captures.
    // The one web profile every embedded page shares (apps, channel
    // Pages): signed in once, stored on disk. Qt allows one profile per
    // storage name, so the views all take this one.
    WebEngineProfilePrototype {
        id: webAppsProfile
        storageName: "ost-apps"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpCacheType: WebEngineProfile.DiskHttpCache
    }
    Theme {
        id: theme
        readonly property string forced: (Qt.application.arguments.find(a => a.startsWith("--theme=")) || "").slice(8)
        readonly property string mode: forced || backend.themeMode
        dark: mode === "dark" || (mode === "system" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)
    }
    // Teams desktop's shortcuts: Ctrl+E search, Ctrl+G go to a chat.
    Shortcut { sequence: "Ctrl+E"; onActivated: titleBar.focusSearch() }
    Shortcut { sequence: "Ctrl+G"; onActivated: titleBar.focusSearch() }
    Shortcut { sequence: "Alt+Left"; onActivated: window.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: window.goForward() }
    // Rail apps, as in Teams desktop.
    Shortcut { sequence: "Ctrl+1"; onActivated: rail.current = "activity" }
    Shortcut { sequence: "Ctrl+2"; onActivated: rail.current = "chat" }
    Shortcut { sequence: "Ctrl+3"; onActivated: rail.current = "calendar" }
    Shortcut { sequence: "Ctrl+4"; onActivated: rail.current = "calls" }
    Shortcut { sequence: "Ctrl+5"; onActivated: rail.current = "onedrive" }
    Shortcut { sequence: "Ctrl+,"; onActivated: rail.current = "settings" }
    Shortcut { sequence: "Ctrl+N"; onActivated: { rail.current = "chat"; chatList.draftsOpen = false; chatList.mentionsOpen = false; window.composing = true } }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: window.pinned = !window.pinned }
    // The rest of Teams' shortcuts that OST supports (listed by Ctrl+.).
    Shortcut { sequence: "Ctrl+."; onActivated: shortcutsDialog.open() }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: { rail.current = "chat"; chatList.openFilter() } }
    Shortcut { sequence: "Ctrl+R"; onActivated: { rail.current = "chat"; conversation.focusCompose() } }
    Shortcut { sequence: "Ctrl+F"; onActivated: if (conversation.visible) conversation.openFind() }
    // Help (F1) and Feedback ▸ Report a problem (Ctrl+Alt+Shift+R), as Teams.
    Shortcut { sequence: "F1"; onActivated: window.openHelp() }
    Shortcut { sequence: "Ctrl+Alt+Shift+R"; onActivated: window.openFeedback("problem", window.feedbackArea(), "") }
    // Help (F1): Teams' Help window, one at a time.
    property var helpWindow: null
    function openHelp() {
        if (helpWindow) { helpWindow.raise(); helpWindow.requestActivate(); return helpWindow }
        helpWindow = Qt.createComponent("HelpWindow.qml").createObject(null)
        helpWindow.closing.connect(() => { const w = helpWindow; helpWindow = null; if (w) w.destroy() })
        helpWindow.show()
        helpWindow.requestActivate()
        return helpWindow
    }
    // Where Report a problem was sent from (the view in front).
    function feedbackArea() {
        const names = { chat: "Chat", activity: "Activity", calendar: "Calendar", calls: "Calls", onedrive: "OneDrive", settings: "Settings", people: "People", planner: "Planner", onenote: "OneNote", add: "Apps" }
        return names[rail.current] || rail.current || "OST"
    }
    // Feedback ▸ Report a problem / Give a compliment: Teams' feedback
    // window, sent to OST's GitHub (FeedbackWindow.qml).
    property var feedbackWindow: null
    function openFeedback(kind, area, context) {
        if (feedbackWindow) feedbackWindow.close()
        const c = Qt.createComponent("FeedbackWindow.qml")
        feedbackWindow = c.createObject(null, { kind: kind, area: area, context: context, captureTarget: window.contentItem })
        feedbackWindow.closing.connect(() => { const w = feedbackWindow; feedbackWindow = null; if (w) w.destroy() })
        feedbackWindow.show()
        feedbackWindow.requestActivate()
        return feedbackWindow
    }
    Connections {
        target: backend
        function onFeedbackRequested(kind, area, context) { window.openFeedback(kind, area, context) }
    }
    Shortcut { sequence: "Ctrl+J"; onActivated: if (conversation.visible) conversation.jumpToNewest() }
    Shortcut { sequence: "Alt+P"; onActivated: if (conversation.visible) conversation.toggleDetails() }
    Shortcut { sequence: "Alt+Shift+O"; onActivated: if (conversation.visible) conversation.attachFile() }
    Shortcut { sequence: "Shift+Esc"; onActivated: backend.markAllRead() }
    Shortcut { sequence: "Ctrl+Alt+Z"; onActivated: chatList.clearFilters() }
    Shortcut { sequence: "Ctrl+Alt+C"; onActivated: { rail.current = "chat"; chatList.setChip("chats") } }
    Shortcut { sequence: "Ctrl+Alt+A"; onActivated: { rail.current = "chat"; chatList.setChip("channels") } }
    Shortcut { sequence: "Ctrl+Alt+U"; onActivated: { rail.current = "chat"; chatList.setChip("unread") } }
    Shortcut { sequence: "Ctrl+Alt+B"; onActivated: { rail.current = "chat"; chatList.setChip("meetings") } }
    Shortcut { sequence: "Ctrl+Alt+Z"; onActivated: { rail.current = "chat"; chatList.clearFilters() } }
    Repeater {
        model: 5
        Item {
            required property int index
            Shortcut { sequence: "Alt+" + (index + 1); onActivated: if (conversation.visible) conversation.openTab(index) }
        }
    }
    Shortcut { sequence: "Alt+N"; onActivated: { rail.current = "calendar"; calendarView.newMeeting() } }
    Shortcut { sequence: "Alt+Shift+A"; onActivated: if (conversation.visible && !backend.callState) backend.startCall() }
    Shortcut { sequence: "Alt+Shift+V"; onActivated: if (conversation.visible && !backend.callState) backend.startVideoCall() }
    // Call keys work from the call window and the toast too.
    Shortcut { sequence: "Ctrl+Shift+M"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected") backend.toggleMute() }
    Shortcut { sequence: "Ctrl+Shift+H"; context: Qt.ApplicationShortcut; onActivated: if (["calling", "connecting", "connected", "lobby"].indexOf(backend.callState) >= 0) backend.hangUp() }
    Shortcut { sequence: "Ctrl+Shift+S"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "ringing") backend.acceptCall(false) }
    Shortcut { sequence: "Ctrl+Shift+A"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "ringing") backend.acceptCall(backend.callVideoOffered) }
    Shortcut { sequence: "Ctrl+Shift+D"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "ringing") backend.declineCall() }
    Shortcut { sequence: "Ctrl+Shift+O"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected" && backend.callCanVideo) backend.toggleCamera() }
    KeyboardShortcuts { id: shortcutsDialog }
    // For --keys-test (needs access to these by name).
    property alias kShortcuts: shortcutsDialog
    property alias kRail: rail
    property alias kChatList: chatList
    property alias kConversation: conversation
    property alias kBackend: backend
    readonly property bool backendReady: backend.signedIn && chatList.chats.length > 0
    Loader {
        active: Qt.application.arguments.indexOf("--keys-test") >= 0
        source: "KeysTest.qml"
        onLoaded: item.win = window
    }
    // Pin window on top.
    property bool pinned: false
    // Settings > General > On close, keep the application running: closing
    // only hides the window; opening OST again brings it back.
    onClosing: close => {
        if (backend.setting("keepRunning") !== "false" && !window.reallyQuit) { close.accepted = false; window.hide() }
    }
    property bool reallyQuit: Qt.application.arguments.length > 1

    Connections {
        target: backend
        function onStatusNoteResultChanged() {
            const r = JSON.parse(backend.statusNoteResult || "{}")
            titleBar.statusNoteSaved(!!r.ok, r.message || "", !!r.pinned, r.html || "")
        }
    }
    // Calls and sharing set presence, as Teams' calling client state does.
    Connections {
        target: backend
        function onCallStateChanged() { backend.syncCallPresence() }
        function onCallSharingChanged() { backend.syncCallPresence() }
    }
    // Bring the main window back (tray, or a second launch of OST).
    function showRaised() {
        window.show(); window.raise(); window.requestActivate()
    }
    // The tray, as Teams' (docs/spec/tray-and-lifecycle.md): the logo with
    // the presence badge; the account row, the status submenu (with Reset
    // Status), Help › Collect Support Files, and Quit, the only real quit.
    readonly property string myPresence: titleBar.presence
    readonly property string trayKind: {
        const p = myPresence.toLowerCase()
        return (p === "available" || p === "availableidle") ? "available"
            : (p === "away" || p === "berightback") ? "away"
            : (p === "busy" || p === "busyidle" || p === "inacall" || p === "inameeting" || p === "inaconferencecall") ? "busy"
            : (p === "donotdisturb" || p === "presenting" || p === "focusing" || p === "urgentinterruptionsonly") ? "dnd"
            : p === "outofoffice" ? "oof" : p === "offline" ? "offline" : "unknown"
    }
    function trayStatusLabel(p) {
        const s = titleBar.statuses.find(x => x.key.toLowerCase() === (p || "").toLowerCase())
        return s ? (s.key === "Away" ? "Away" : s.key === "Offline" ? "Offline" : s.label) : (p || "Available")
    }
    // The tray (desktop/src/tray.rs): kept current from here; it calls
    // back for Show and Quit.
    readonly property bool trayShown: backend.signedIn && (Qt.application.arguments.length <= 1 || Qt.application.arguments.indexOf("--tray") >= 0)
    function refreshTray() {
        if (trayShown)
            backend.updateTray(trayKind, trayStatusLabel(myPresence), backend.userName + (backend.orgName ? " | " + backend.orgName : ""))
    }
    // Teams' taskbar badge (Windows' overlay on its taskbar button): the
    // app bar's badges added up (Activity, Chat), else your presence.
    readonly property int taskbarCount: !backend.signedIn ? 0
        : chatList.chats.filter(c => c.unread && !c.muted).length + backend.activityUnread
    function refreshTaskbarBadge() { backend.setTaskbarBadge(taskbarCount, backend.signedIn ? trayKind : "") }
    onTaskbarCountChanged: refreshTaskbarBadge()
    Component.onCompleted: { refreshTaskbarBadge(); backend.installLinkHandler() }

    // Settings ▸ Files and links ▸ "Always ask where to save downloaded
    // file": a download asks for its place (the download folder and the
    // file's name suggested).
    FileDialog {
        id: saveAsDialog
        property int pending: 0
        title: "Save as"
        fileMode: FileDialog.SaveFile
        onAccepted: backend.saveAsAnswer(pending, decodeURIComponent(String(selectedFile)))
        onRejected: backend.saveAsAnswer(pending, "")
    }
    Connections {
        target: backend
        function onSaveAsRequested(id, name, folder) {
            saveAsDialog.pending = id
            saveAsDialog.currentFolder = "file://" + folder
            saveAsDialog.selectedFile = "file://" + folder + "/" + name
            saveAsDialog.open()
        }
    }
    onTrayShownChanged: refreshTray()
    onTrayKindChanged: { refreshTray(); refreshTaskbarBadge() }
    onMyPresenceChanged: refreshTray()
    Connections {
        target: backend
        function onUserNameChanged() { window.refreshTray() }
        function onOrgNameChanged() { window.refreshTray() }
        function onTrayShow() { window.showRaised() }
        function onTrayQuit() { window.reallyQuit = true; Qt.quit() }
    }

    // Back/forward through the apps and chats you visited, as Teams does.
    property var navStack: []
    property int navIndex: -1
    property bool navApplying: false
    function navCurrent() {
        return { view: rail.current, chatId: backend.currentChatId, chatName: backend.currentChatName }
    }
    function navRecord() {
        if (navApplying) return
        const cur = navCurrent()
        const top = navIndex >= 0 ? navStack[navIndex] : null
        if (top && top.view === cur.view && (cur.view !== "chat" || top.chatId === cur.chatId)) return
        const stack = navStack.slice(0, navIndex + 1)
        stack.push(cur)
        navStack = stack.slice(-50)
        navIndex = navStack.length - 1
    }
    function navApply(i) {
        const e = navStack[i]
        if (!e) return
        navApplying = true
        navIndex = i
        rail.current = e.view
        if (e.view === "chat" && e.chatId && e.chatId !== backend.currentChatId) backend.selectChat(e.chatId, e.chatName)
        navApplying = false
    }
    function goBack() { if (conversation.channelAttendance) { conversation.channelAttendance = null; return } if (navIndex > 0) navApply(navIndex - 1) }
    function goForward() { if (navIndex < navStack.length - 1) navApply(navIndex + 1) }
    Connections {
        target: backend
        function onCurrentChatIdChanged() { window.navRecord() }
    }

    // --nav-test: visit calls, calendar, then go back twice and forward
    // once, logging each step (checks the history stack).
    Timer {
        running: Qt.application.arguments.indexOf("--nav-test") >= 0 && backend.signedIn
        interval: 1500
        property int step: 0
        property int chatTries: 0
        repeat: true
        onTriggered: {
            const steps = [
                () => rail.current = "calls",
                () => rail.current = "calendar",
                () => window.goBack(),
                () => window.goBack(),
                () => window.goForward(),
            ]
            if (step < steps.length) { steps[step](); console.warn("NAV", step, rail.current, window.navIndex, window.navStack.length, titleBar.canGoBack, titleBar.canGoForward); step++ }
            else Qt.quit()
        }
    }

    // --app-details=<appId>: Teams' app details dialog for an app: the page,
    // scrolled (sticky header), languages, All reviews (Sort), Permissions,
    // Write a review and Report review (never submitted), then an app from
    // More like this and Back. --share-app: the Share form for the app,
    // "OST group test" picked; --share-app-send then shares it there.
    // --open-chat: OST group test, where shared apps' cards are.
    readonly property string appDetailsTest: (Qt.application.arguments.find(a => a.startsWith("--app-details=")) || "").slice(14)
    Timer {
        running: window.appDetailsTest.length > 0 && backend.signedIn && chatList.chats.length > 0
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const d = appDetails
            const grab = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-app-" + n + ".png")))
            const log = n => console.warn("APPDETAILS", step, n, d.view, d.d ? JSON.stringify({ name: d.d.name, rating: d.d.rating, installs: d.d.installs, reviews: d.d.reviews_count, langs: d.d.languages.length, caps: d.d.capabilities.length, perms: d.d.permissions.length }) : backend.appDetailsJson.slice(0, 200), "similar", d.similar.map(a => a.name).join("|"), "reviews", d.revs ? d.revs.reviews.length + "/" + d.revs.count : "-")
            const share = Qt.application.arguments.indexOf("--share-app") >= 0
            const plan = share ? {
                0: () => { appShare.start(window.appDetailsTest) },
                2: () => { grab("share"); appShare.typeForTest("OST group test") },
                4: () => { grab("share-suggest"); console.warn("SHARE picked", appShare.pickFirstForTest(), JSON.stringify(appShare.picked)) },
                5: () => grab("share-picked"),
                6: () => { if (Qt.application.arguments.indexOf("--share-app-send") >= 0 && appShare.picked.length === 1 && appShare.picked[0].id === "19:ef213c7c46cf4036b11608300e96fee4@thread.v2") appShare.shareForTest(); else console.warn("SHARE not sent") },
                9: () => { console.warn("SHARE state", backend.shareState, backend.sharedConversation()); grab("share-done") },
                10: () => Qt.quit()
            } : {
                0: () => d.show(window.appDetailsTest),
                3: () => { log("main"); grab("main") },
                4: () => d.scrollForTest(560), 5: () => { log("scrolled"); grab("scrolled") },
                6: () => d.scrollForTest(100000), 7: () => { d.languagesForTest(); grab("bottom") },
                8: () => { d.languagesForTest(); d.viewForTest("reviews") }, 10: () => { log("reviews"); grab("reviews") },
                11: () => d.sortMenuForTest(), 12: () => { grab("sort"); d.sortMenuForTest_.close() },
                13: () => d.viewForTest("permissions"), 14: () => grab("permissions"),
                15: () => d.viewForTest("write"), 16: () => grab("write"),
                17: () => { d.view = "reviews" }, 18: () => { if (d.revs && d.revs.reviews.length) d.showReport(d.revs.reviews[0]) }, 19: () => grab("report"),
                20: () => { d.view = "main" }, 21: () => { if (d.similar.length) d.openSimilar(d.similar[1] ? d.similar[1].id : d.similar[0].id) },
                24: () => { log("similar"); grab("similar") }, 25: () => d.back(), 26: () => { log("back"); d.close() },
                27: () => { if (Qt.application.arguments.indexOf("--open-chat") >= 0) { rail.current = "chat"; backend.selectChat("19:ef213c7c46cf4036b11608300e96fee4@thread.v2", "OST group test") } },
                31: () => grab("chat"),
                32: () => Qt.quit()
            }
            if (plan[step]) plan[step]()
            step++
        }
    }
    // --meeting-details-test: the "OST calendar test" meeting chat's header
    // (Join, roster, Meeting details), then Meeting details: the meeting in
    // the calendar.
    Timer {
        running: Qt.application.arguments.indexOf("--meeting-details-test") >= 0 && backend.signedIn && chatList.chats.length > 1
        interval: 3000
        property int step: 0
        repeat: true
        onTriggered: {
            const grab = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-md-" + n + ".png")))
            const c = chatList.chats.find(x => (x.name || "").indexOf("OST calendar test") === 0)
            const plan = {
                0: () => { rail.current = "chat"; if (c) backend.selectChat(c.id, c.name) },
                3: () => { console.warn("MD meeting", backend.chatMeetingJson.slice(0, 300), "shown", conversation.meetingDetailsShown, conversation.meetingDetailsInline); grab("header") },
                4: () => { const m = JSON.parse(backend.chatMeetingJson || "{}"); console.warn("MD start", m.start); conversation.openMeetingDetails(m.join_url || "", m.ical_uid || "", m.start || "") },
                8: () => { console.warn("MD calendar", rail.current, JSON.stringify(calendarView.pendingMeeting)); grab("calendar") },
                9: () => { rail.current = "chat"; const g = chatList.chats.find(x => x.name === "OST group test"); if (g) backend.selectChat(g.id, g.name) },
                11: () => conversation.openChatMenuForTest(), 12: () => grab("chatmenu"),
                13: () => { conversation.closeChatMenuForTest(); Qt.quit() }
            }
            if (plan[step]) plan[step]()
            step++
        }
    }
    // --chatlist-test: the list with the server's sections; each pill (and
    // More filters); a chat's menu and Move to section ▸; then, on
    // ost-test1's own sections only: OST group test into a new section
    // "OST test section", rename it, remove it; Hide and Unhide OST group test.
    Timer {
        running: Qt.application.arguments.indexOf("--chatlist-test") >= 0 && backend.signedIn && chatList.chats.length > 1 && backend.foldersJson.length > 2
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const grab = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-cl-" + n + ".png")))
            const g = "19:ef213c7c46cf4036b11608300e96fee4@thread.v2"
            const log = n => console.warn("CHATLIST", step, n, JSON.stringify(chatList.sections.map(s => s.folder.title + ":" + s.rows.length)), "pills", JSON.stringify(chatList.pillRows.first.map(p => p.key)), "/", JSON.stringify(chatList.pillRows.second.map(p => p.key)))
            const folders = () => JSON.parse(backend.foldersJson).folders
            const test = () => folders().find(f => (f.kind === "UserCreated" || f.kind === "UserDefined") && (f.title === "OST test section" || f.title === "OST renamed section"))
            const plan = {
                // Clean up test sections a failed run left (ost-test1's own).
                0: () => { rail.current = "chat"; for (const f of folders()) if ((f.kind === "UserCreated" || f.kind === "UserDefined") && /^(OST (test|renamed) section|UserCreated)$/.test(f.title)) backend.folderAction("delete", JSON.stringify({ id: f.id })) },
                1: () => { log("start"); grab("list") },
                2: () => { chatList.setChip("unread"); log("unread") }, 3: () => grab("unread"),
                4: () => { chatList.setChip("unread"); chatList.setChip("channels"); log("channels") }, 5: () => grab("channels"),
                6: () => { chatList.setChip("chats"); log("chats") }, 7: () => { chatList.moreFiltersOpen = true; grab("chats-more") },
                8: () => { chatList.setChip("meetings"); log("meetings") }, 9: () => grab("meetings"),
                10: () => { chatList.clearFilters(); chatList.moreFiltersOpen = false },
                11: () => chatList.openRowMenuForTest(g), 12: () => grab("menu"), 13: () => chatList.closeRowMenuForTest(),
                14: () => { if (!test()) backend.folderAction("create", JSON.stringify({ name: "OST test section", item: g, from: "" })) },
                18: () => { log("created"); console.warn("CHATLIST section", JSON.stringify(test())); grab("section") },
                19: () => { const t = test(); if (t) backend.folderAction("rename", JSON.stringify({ id: t.id, name: "OST renamed section" })) },
                22: () => { log("renamed"); console.warn("CHATLIST renamed", JSON.stringify(test())); grab("renamed") },
                23: () => { const t = test(); if (t) backend.folderAction("collapse", JSON.stringify({ id: t.id })) },
                25: () => { console.warn("CHATLIST collapsed", JSON.stringify(test())); const t = test(); if (t) backend.folderAction("delete", JSON.stringify({ id: t.id })) },
                28: () => { log("removed"); console.warn("CHATLIST gone", !test()) },
                29: () => backend.setChatHidden(g, true), 32: () => { log("hidden"); grab("hidden"); console.warn("CHATLIST hidden", JSON.stringify(chatList.chats.find(c => c.id === g))) },
                33: () => backend.setChatHidden(g, false), 36: () => { log("unhidden"); console.warn("CHATLIST unhidden", JSON.stringify(chatList.chats.find(c => c.id === g))) },
                37: () => Qt.quit()
            }
            if (plan[step]) plan[step]()
            step++
        }
    }
    // --draft-test: type into the first chat, switch to the second, check
    // the draft is listed, switch back and check the text came back; then
    // clear it again.
    Timer {
        running: Qt.application.arguments.indexOf("--draft-test") >= 0 && backend.signedIn && chatList.chats.length > 1
        interval: 2000
        property int step: 0
        repeat: true
        onTriggered: {
            const a = chatList.chats[0], b = chatList.chats[1]
            const conv = conversation
            if (step === 0) { backend.selectChat(a.id, a.name) }
            else if (step === 1) { conv.setComposeText("OST draft test") }
            else if (step === 2) { backend.selectChat(b.id, b.name) }
            else if (step === 3) {
                const d = backend.draftsJson ? JSON.parse(backend.draftsJson) : []
                console.warn("DRAFT listed", d.some(x => x.id === a.id && x.text === "OST draft test"), "compose now", JSON.stringify(conv.composeText()))
                chatList.openDrafts()
            }
            else if (step === 4) {
                window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-drafts.png")))
                backend.selectChat(a.id, a.name); chatList.draftsOpen = false; chatList.mentionsOpen = false
            }
            else if (step === 5) {
                console.warn("DRAFT restored", JSON.stringify(conv.composeText()))
                conv.setComposeText(""); backend.setDraft(a.id, "")
            }
            else { console.warn("DRAFT cleared", backend.draftsJson); Qt.quit() }
            step++
        }
    }

    // --send-file=<path>: attach a file in the open chat and send it, then
    // download the newest received attachment (end-to-end files check).
    Timer {
        readonly property string path: (Qt.application.arguments.find(a => a.startsWith("--send-file=")) || "").slice(12)
        running: path.length > 0 && backend.signedIn && chatList.chats.length > 0
        interval: 3000
        property int step: -1
        repeat: true
        onTriggered: {
            if (step === -1) {
                const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
                const c = chatList.chats.find(c => c.id === want) || chatList.chats[0]
                backend.selectChat(c.id, c.name)
            } else if (step === 0) {
                conversation.attachForTest([path]); conversation.setComposeText("OST test 24: file sent from OST")
                conversation.sendForTest()
            } else if (step === 4) {
                const msgs = JSON.parse(backend.messagesJson)
                const withFile = msgs.filter(m => (m.files || []).length > 0)
                const last = withFile[withFile.length - 1]
                console.warn("FILES sent", last ? last.text : "none", last ? JSON.stringify(last.files.map(f => f.name)) : "", "status", backend.statusText)
                if (last) backend.downloadFile(JSON.stringify(last.files[0]))
            } else if (step === 6) {
                console.warn("FILES download", backend.statusText)
                Qt.quit()
            }
            step++
        }
    }

    // --filter-test: try each chip and a name filter, logging what shows.
    Timer {
        running: Qt.application.arguments.indexOf("--filter-test") >= 0 && chatList.chats.length > 0 && chatList.teams.length > 0
        interval: 800
        property int step: 0
        repeat: true
        onTriggered: {
            const log = tag => console.warn("FILTER", tag, "fav", chatList.favorites.length, "chats", chatList.others.length, "teams", chatList.shownTeams.length,
                                             "channels", chatList.shownTeams.reduce((n, t) => n + t.channels.length, 0))
            const steps = [
                () => log("none"),
                () => { chatList.chipFilter = "unread"; log("unread") },
                () => { chatList.chipFilter = "channels"; log("channels") },
                () => { chatList.chipFilter = "chats"; log("chats") },
                () => { chatList.chipFilter = ""; chatList.nameFilter = "ost test team"; log("name=ost test team") },
                () => { chatList.nameFilter = "randy"; log("name=randy") },
                () => { chatList.nameFilter = ""; log("cleared"); Qt.quit() },
            ]
            steps[step++]()
        }
    }

    // --status-test: open the profile menu and its status choices, set Busy,
    // then reset (capturing the menu). With --shots-only it stops after the
    // captures and changes nothing.
    Timer {
        running: Qt.application.arguments.indexOf("--status-test") >= 0 && backend.signedIn && backend.userMail.length > 0
        interval: 3000
        property int step: 0
        repeat: true
        onTriggered: {
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png")))
            if (step === 0) titleBar.openProfileForTest()
            else if (step === 1) shot("profile")
            else if (step === 2) titleBar.profilePageForTest("duration")
            else if (step === 3) shot("duration")
            else if (step === 4) titleBar.profilePageForTest("note")
            else if (step === 5) shot("note")
            else if (step === 6 && Qt.application.arguments.indexOf("--shots-only") >= 0) Qt.quit()
            else if (step === 6) { titleBar.closeProfileForTest(); backend.setMyStatusUntil("Busy", "OneHour", "") }
            else if (step === 8) { console.warn("STATUS after busy", titleBar.presence); backend.setMyStatus("Reset") }
            else if (step === 10) { console.warn("STATUS reset", titleBar.presence); backend.setStatusNote("OST test 42 status note", true, "OneHour", "") }
            else if (step === 12) { console.warn("STATUS note", backend.statusNoteResult); backend.setStatusNote("", false, "Never", "") }
            else if (step === 14) { console.warn("STATUS note cleared", backend.statusNoteResult); Qt.quit() }
            step++
        }
    }

    // --calendar-test: schedule a Teams meeting tomorrow 3 PM in the test
    // account's calendar, then report whether it came back with a link.
    Timer {
        running: Qt.application.arguments.indexOf("--calendar-test") >= 0 && backend.signedIn
        interval: 4000
        property int step: 0
        repeat: true
        onTriggered: {
            if (step === 0) {
                rail.current = "calendar"
                const s = new Date(); s.setDate(s.getDate() + 1); s.setHours(15, 0, 0, 0)
                const e = new Date(s.getTime() + 30 * 60000)
                calendarView.start = calendarView.startFor(s)
                backend.createEvent("OST calendar test: created from OST", s.toISOString().replace(/\.\d+Z$/, "Z"), e.toISOString().replace(/\.\d+Z$/, "Z"), "", true)
            } else if (step === 2) {
                const evs = JSON.parse(backend.calendarJson || "[]")
                const ev = evs.find(e => e.subject === "OST calendar test: created from OST")
                console.warn("CALENDAR created", !!ev, "teams link", !!(ev && ev.join_url), "status", backend.statusText)
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath.replace(".png", "-cal.png")); Qt.quit() })
            }
            step++
        }
    }

    // --feedback-test: Settings and more with Feedback ▸, then Report a
    // problem filled in with a screenshot (captures each; logs the issue
    // address Submit would open), then Give a compliment.
    Timer {
        running: Qt.application.arguments.indexOf("--feedback-test") >= 0 && chatList.chats.length > 1
        interval: 2000
        property int step: 0
        property var fw: null
        repeat: true
        onTriggered: {
            const cap = (item, tag) => item.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) titleBar.feedbackMenuForTest()
            else if (step === 1) cap(window.contentItem, "fb-menu")
            else if (step === 2) { titleBar.feedbackMenuForTest(); fw = window.openFeedback("problem", "Settings and more", "") }
            else if (step === 3) cap(fw.contentItem, "fb-empty")
            else if (step === 4) { fw.fillForTest("Search shows nothing for OST test\nSecond line", 0, 0); fw.captureForTest() }
            else if (step === 5) {
                cap(fw.contentItem, "fb-filled")
                console.warn("FEEDBACK files", JSON.stringify(fw.files), "ready", fw.ready)
                const url = backend.feedbackIssueUrl(JSON.stringify({ kind: "problem", text: "Search shows nothing for OST test", area: "Settings and more", share_logs: true, contact: true, files: fw.files }))
                console.warn("FEEDBACK url", url.length, url.slice(0, 400))
                console.warn("FEEDBACK logs", decodeURIComponent((url.split("&logs=")[1] || "").replace(/\+/g, " ")).slice(-600))
            }
            else if (step === 6) { fw.close(); fw = window.openFeedback("compliment", "Settings and more", "") }
            else if (step === 7) { cap(fw.contentItem, "fb-compliment"); console.warn("FEEDBACK ideas", backend.feedbackLink("ideas")) }
            else if (step === 8) { fw.close(); Qt.quit() }
            step++
        }
    }
    // --help-test: Help (F1): home, its lower half, a category, an article,
    // a search, and the Help app in place; captures each.
    Timer {
        running: Qt.application.arguments.indexOf("--help-test") >= 0 && chatList.chats.length > 1
        interval: 1500
        property int step: 0
        property var hw: null
        repeat: true
        onTriggered: {
            const cap = (item, tag) => item.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) hw = window.openHelp()
            else if (step === 2) { cap(hw.contentItem, "help-home"); console.warn("HELP library", JSON.stringify(hw.viewForTest().library.map(c => [c.title, c.articles.length]))) }
            else if (step === 3) { const f = hw.viewForTest().children.find(c => c.contentY !== undefined); if (f) f.contentY = 620 }
            else if (step === 4) cap(hw.contentItem, "help-home2")
            else if (step === 5) hw.viewForTest().openForTest({ page: "category", id: "chat" })
            else if (step === 6) cap(hw.contentItem, "help-category")
            else if (step === 7) hw.viewForTest().openForTest({ page: "article", id: "chat/find-in-a-chat" })
            else if (step === 8) cap(hw.contentItem, "help-article")
            else if (step === 9) hw.viewForTest().openForTest({ page: "search", q: "share screen" })
            else if (step === 10) { cap(hw.contentItem, "help-search"); console.warn("HELP search", JSON.stringify(hw.viewForTest().results.map(a => a.title))) }
            else if (step === 11) { hw.close(); rail.openApp("help") }
            else if (step === 13) cap(window.contentItem, "help-app")
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --search-page-test[=<words>]: Teams' results page: All, each tab,
    // a Type filter, then the first message opened; captures each.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--search-page-test")) && chatList.chats.length > 1
        interval: 3500
        property int step: 0
        repeat: true
        onTriggered: {
            const arg = (Qt.application.arguments.find(a => a.startsWith("--search-page-test=")) || "").slice(19) || "OST test"
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = tag => { const p = searchView.page; console.warn("SEARCH", tag, JSON.stringify({ rows: searchView.rowsForTest().map(r => r.t), loading: searchView.result ? searchView.result.loading : null, error: searchView.result ? searchView.result.error : null,
                                   order: p ? p.order : null, n: p ? { m: p.messages.hits.length, mt: p.messages.total, f: p.files.hits.length, c: p.chats.length, ch: p.channels.length, e: p.events.length, i: p.images.hits.length, pe: p.people.length } : null })) }
            const tabs = ["messages", "files", "people", "channels", "groupchats", "meetings", "images"]
            if (step === 0) window.openSearch(arg)
            else if (step === 2) { log("all"); cap("sp-all") }
            else if (step >= 3 && step < 3 + tabs.length * 2) {
                const i = Math.floor((step - 3) / 2), t = tabs[i]
                if ((step - 3) % 2 === 0) searchView.setTab(t)
                else { log(t); cap("sp-" + t) }
            }
            else if (step === 17) { searchView.setTab("messages"); searchView.kind = "chat"; searchView.run() }
            else if (step === 18) { log("type-chat"); cap("sp-type-chat") }
            else if (step === 19) { const r = searchView.rowsForTest().find(r => r.t === "message"); if (r) searchView.preview = r.h }
            else if (step === 22) { cap("sp-preview"); console.warn("SEARCH preview", JSON.stringify(searchView.preview ? { id: searchView.preview.id, thread: searchView.preview.thread } : null)) }
            else if (step === 23) { searchView.kind = ""; searchView.run() }
            else if (step === 25) { const r = searchView.rowsForTest().find(r => r.t === "message" && String(r.h.thread).endsWith("@thread.tacv2")); console.warn("SEARCH channel hit", !!r); if (r) searchView.preview = r.h }
            else if (step === 28) cap("sp-preview-channel")
            else if (step === 29) { const r = searchView.rowsForTest().find(r => r.t === "message"); if (r) searchView.openHit(r.h) }
            else if (step === 31) { cap("sp-open"); console.warn("SEARCH open", backend.currentChatName, JSON.stringify(conversation.findMark)) }
            else if (step === 32) Qt.quit()
            step++
        }
    }
    // --search-grid-test[=<words>]: Files in List view, then Grid view
    // (with its thumbnails), then a card's ··· menu; captures each and puts
    // the list back.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--search-grid-test")) && chatList.chats.length > 1
        interval: 3000
        property int step: 0
        repeat: true
        onTriggered: {
            const arg = (Qt.application.arguments.find(a => a.startsWith("--search-grid-test=")) || "").slice(19) || "OST"
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = tag => console.warn("GRID", tag, searchView.fileLayout, JSON.stringify(searchView.rowsForTest().map(r => r.t)),
                                            JSON.stringify(searchView.page && searchView.page.files ? searchView.page.files.hits.slice(0, 8).map(h => [h.file_name, h.file_action, h.file_by, h.file_when]) : null))
            if (step === 0) { searchView.setFileLayout("list"); window.openSearch(arg) }
            else if (step === 2) searchView.setTab("files")
            else if (step === 4) { log("list"); cap("grid-list") }
            else if (step === 5) searchView.setFileLayout("grid")
            else if (step === 9) { log("grid"); cap("grid-grid") }
            else if (step === 10) searchView.openGridMenuForTest()
            else if (step === 11) cap("grid-menu")
            else if (step === 12) { searchView.closeGridMenuForTest(); searchView.setFileLayout("list") }
            else if (step === 13) Qt.quit()
            step++
        }
    }
    // --share-test[=<file name>]: OneDrive's share dialog for a search
    // result (default ost-attachment-test.txt): the form, suggestions for
    // "OST Te", Link settings, Manage Access (People, Links) and an Access
    // summary; captures each ("-share-<view>.png"). Nothing is changed.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--share-test")) && chatList.chats.length > 1
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--share-test=")) || "").slice(13) || "ost-attachment-test.txt"
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-share-" + tag + ".png")))
            const log = tag => console.warn("SHARE", tag, JSON.stringify(oneDriveShare.stateForTest()).slice(0, 1500))
            if (step === 0) window.openSearch(want.replace(/\.[^.]*$/, ""))
            else if (step === 2) searchView.setTab("files")
            else if (step === 4) {
                const h = (searchView.page && searchView.page.files ? searchView.page.files.hits : []).find(h => h.file_name === want)
                console.warn("SHARE hit", JSON.stringify(h ? { site: h.file_site, list: h.file_list, id: h.id } : null))
                if (h) oneDriveShare.openFor({ site: h.file_site, list: h.file_list, item: h.id }, h.file_name, h.file_type)
            }
            else if (step === 6) { log("main"); cap("main") }
            else if (step === 7) oneDriveShare.typeForTest("OST Te")
            else if (step === 9) { log("suggest"); cap("suggest") }
            else if (step === 10) { oneDriveShare.typeForTest(""); oneDriveShare.openSettings() }
            else if (step === 11) { log("settings"); cap("settings") }
            else if (step === 12) oneDriveShare.showForTest("manage", "people")
            else if (step === 13) cap("people")
            else if (step === 14) oneDriveShare.showForTest("manage", "links")
            else if (step === 15) cap("links")
            else if (step === 16) oneDriveShare.showForTest("access")
            else if (step === 17) cap("access")
            // --share-send: Send it to OST Test 2 ("OST test 107"), then
            // Stop sharing; captures each step.
            else if (step === 18 && Qt.application.arguments.indexOf("--share-send") >= 0) { oneDriveShare.showForTest("main"); oneDriveShare.typeForTest("OST Test 2") }
            else if (step === 20 && Qt.application.arguments.indexOf("--share-send") >= 0) { oneDriveShare.pickForTest("OST Test 2"); oneDriveShare.messageForTest("OST test 107: shared from OST") }
            else if (step === 21 && Qt.application.arguments.indexOf("--share-send") >= 0) { cap("picked"); oneDriveShare.send() }
            else if (step === 24 && Qt.application.arguments.indexOf("--share-send") >= 0) { log("sent"); cap("invited"); oneDriveShare.showForTest("manage", "people") }
            else if (step === 25 && Qt.application.arguments.indexOf("--share-send") >= 0) { log("shared"); cap("shared") }
            else if (step === 26 && Qt.application.arguments.indexOf("--share-send") >= 0) backend.shareAction("stop", JSON.stringify(oneDriveShare.item), "{}")
            else if (step === 29 && Qt.application.arguments.indexOf("--share-send") >= 0) { log("stopped"); cap("stopped") }
            else if (step === 18 || step === 30) { oneDriveShare.close(); Qt.quit() }
            step++
        }
    }
    // --sharefile-test[=<file name>]: Teams' "Share this file" for a search
    // result (default ost-share-test.txt): the dialog, suggestions for
    // "OST T", OST Test 2 picked (the access bar), Link settings; with
    // --sharefile-send it shares it to OST Test 2 with a chat link ("OST
    // test 109"). Captures "-sharefile-<step>.png".
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--sharefile-test")) && chatList.chats.length > 1
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--sharefile-test=")) || "").slice(17) || "ost-share-test.txt"
            const send = Qt.application.arguments.indexOf("--sharefile-send") >= 0
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-sharefile-" + tag + ".png")))
            const sf = searchView.shareFileForTest()
            const log = tag => console.warn("SHAREFILE", tag, JSON.stringify(sf.stateForTest()))
            if (step === 0) window.openSearch(want.replace(/\.[^.]*$/, ""))
            else if (step === 2) searchView.setTab("files")
            else if (step === 4) {
                const h = (searchView.page && searchView.page.files ? searchView.page.files.hits : []).find(h => h.file_name === want)
                console.warn("SHAREFILE hit", !!h)
                if (h) sf.openFor({ site: h.file_site, list: h.file_list, item: h.id }, h.file_name, h.file_type, h.file_url || h.url)
            }
            else if (step === 6) { log("open"); cap("open") }
            else if (step === 7) sf.typeForTest("OST T")
            else if (step === 9) { log("suggest"); cap("suggest") }
            else if (step === 10) sf.pickForTest("OST Test 2")
            else if (step === 12) { log("picked"); cap("picked") }
            else if (step === 13 && !send) { sf.noteForTest("Formatted note"); sf.formatForTest("bold") }
            else if (step === 14 && !send) { log("format"); cap("format") }
            else if (step === 15 && !send) Qt.quit()
            else if (step === 13) { sf.linkForTest(4, true); sf.noteForTest("OST test 110: shared from OST, formatted"); sf.formatForTest("bold"); console.warn("SHAREFILE note", sf.noteHtmlForTest()) }
            else if (step === 14) { log("ready"); cap("ready"); sf.share() }
            else if (step === 18) { log("shared"); cap("shared") }
            else if (step === 19) Qt.quit()
            step++
        }
    }
    property var findTestWindow: null
    // --find-test[=files] (with --open-chat=<id>, --find=<keywords>): Find in
    // chat: before a search, the results, the first one opened, the Date
    // and From filters, Attachment on, then Files; captures each.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--find-test")) && chatList.chats.length > 1
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const arg = n => (Qt.application.arguments.find(a => a.startsWith("--" + n + "=")) || "").slice(n.length + 3)
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const filesFirst = Qt.application.arguments.indexOf("--find-test=files") >= 0
            const log = tag => console.warn("FIND", tag, JSON.stringify({ shown: findPane.shown, chips: findPane.chipKeysForTest(), rows: findPane.rows.length,
                                                                          result: findPane.result ? { total: findPane.result.total, more: findPane.result.more, loading: findPane.result.loading, error: findPane.result.error, terms: findPane.result.terms } : null,
                                                                          first: findPane.hits.length ? findPane.hits[0] : null, mark: conversation.findMark }))
            if (step === 0) {
                const want = arg("open-chat")
                if (want.indexOf("@thread.tacv2") > 0) backend.selectChat(want, "General")
                else { const c = chatList.chats.find(c => c.id === want) || chatList.chats[1]; backend.selectChat(c.id, c.name) }
            }
            else if (step === 1) { conversation.openFind() }
            else if (step === 2) { log("idle"); cap("find-idle") }
            else if (step === 3) { if (filesFirst) findPane.files = true; findPane.runForTest(arg("find") || "OST test") }
            else if (step === 5) { log("results"); cap("find-results") }
            else if (step === 6) { if (findPane.hits.length && !filesFirst) findPane.jumpTo(findPane.hits[0], findPane.terms) }
            else if (step === 8) { log("jump"); cap("find-jump") }
            else if (step === 9) { findPane.datePopForTest() }
            else if (step === 10) { cap("find-date") }
            else if (step === 11) { findPane.pickDateForTest("week") }
            else if (step === 13) { log("week"); cap("find-week") }
            else if (step === 14) { findPane.fromPopForTest() }
            else if (step === 15) { cap("find-from") }
            else if (step === 16) { findPane.closePopsForTest(); if (!filesFirst) findPane.toggleForTest("attachment") }
            else if (step === 18) { log("attachment"); cap("find-attachment") }
            else if (step === 19) { findPane.files = !filesFirst; findPane.run() }
            else if (step === 21) { log("files"); cap("find-files") }
            else if (step === 22) { findPane.runForTest("zzqqxxnotfound") }
            else if (step === 24) { log("none"); cap("find-none") }
            else if (step === 25) {
                // Find in post (--find-post=<post id>, in a channel).
                const root = arg("find-post")
                if (!root) { Qt.quit(); return }
                findTestWindow = conversation.openThreadWindow({ id: root })
                findTestWindow.toggleFind()
            }
            else if (step === 27) { findTestWindow.findPaneForTest().runForTest(arg("find") || "OST") }
            else if (step === 29) {
                const p = findTestWindow.findPaneForTest()
                console.warn("FIND post", JSON.stringify({ rows: p.rows.length, result: p.result ? { total: p.result.total, loading: p.result.loading, error: p.result.error } : null, first: p.hits.length ? p.hits[0] : null }))
                findTestWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-find-post.png")))
            }
            else if (step === 30) { const p = findTestWindow.findPaneForTest(); if (p.hits.length) p.jumpTo(p.hits[0], p.terms) }
            else if (step === 32) { findTestWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-find-post-open.png"))) }
            else if (step === 33) { findTestWindow.close(); Qt.quit() }
            step++
        }
    }

    // --header-test: Shared tab, a placeholder tab, find, participants;
    // captures each.
    Timer {
        running: Qt.application.arguments.indexOf("--header-test") >= 0 && chatList.chats.length > 1
        interval: 1500
        property int step: 0
        repeat: true
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { const c = chatList.chats.find(c => c.id === want) || chatList.chats[1]; backend.selectChat(c.id, c.name) }
            else if (step === 1) { conversation.tab = "Shared" }
            else if (step === 2) { cap("shared") }
            else if (step === 3) { conversation.tab = "Recap" }
            else if (step === 4) { cap("recap") }
            else if (step === 5) { conversation.tab = ""; conversation.openFind(); findPane.runForTest("ost test"); console.warn("HEADER find 'OST test'", findPane.shown) }
            else if (step === 6) { cap("find") }
            else if (step === 7) { conversation.finding = false; conversation.openParticipantsForTest() }
            else if (step === 8) { window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath.replace(".png", "-people.png")); Qt.quit() }) }
            step++
        }
    }

    // --format-test: send "OST test 26: bold and plain" with "bold" in
    // bold, then report how the sent message came back.
    Timer {
        running: Qt.application.arguments.indexOf("--format-test") >= 0 && chatList.chats.length > 1
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (step === 0) { const c = chatList.chats.find(c => c.id === want) || chatList.chats[1]; backend.selectChat(c.id, c.name) }
            else if (step === 1) {
                conversation.setComposeText("OST test 26: bold and plain")
                conversation.formatForTest(13, 17, "b")
                conversation.sendForTest()
            } else if (step === 3) {
                const msgs = JSON.parse(backend.messagesJson)
                const m = msgs.filter(m => m.mine).pop()
                console.warn("FORMAT", m ? m.text : "none", "html", m ? m.html : "")
                Qt.quit()
            }
            step++
        }
    }

    // --table-test --open-chat=<id> [--table-send]: in the compose box, the
    // formatting bar's Insert table grid (3x2 hovered), a 3x2 table filled
    // by Tab, Insert column or row and Delete menus, a row added and the
    // export logged; --table-send sends it as "OST TEST 112" and captures
    // how it shows.
    Timer {
        running: Qt.application.arguments.indexOf("--table-test") >= 0 && chatList.chats.length > 1
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const send = Qt.application.arguments.indexOf("--table-send") >= 0
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("TABLE", tag, JSON.stringify(x))
            if (step === 0) { const ch = chatList.chats.find(c => c.id === want); if (!ch) { log("no chat", want); Qt.quit(); return } backend.selectChat(ch.id, ch.name) }
            const c = conversation.composeForTest()
            if (step === 2) { c.formatting = true; c.clearForTest() }
            else if (step === 3) c.formatBarForTest().openOverflowForTest()
            else if (step === 4) c.formatBarForTest().tableGridForTest(3, 2)
            else if (step === 5) cap("grid")
            else if (step === 6) { c.formatBarForTest().closeTablePopupsForTest(); c.tableForTest(3, 2) }
            else if (step === 7) { c.tableFillForTest(["OST TEST 112", "b", "c", "1", "2", "3"]); log("state", c.richState) }
            else if (step === 8) cap("table")
            else if (step === 9) { c.formatBarForTest().openOverflowForTest(); c.formatBarForTest().tableMenuForTest(true) }
            else if (step === 10) cap("insert-menu")
            else if (step === 11) c.formatBarForTest().tableMenuForTest(false)
            else if (step === 12) cap("delete-menu")
            else if (step === 13) { c.formatBarForTest().closeTablePopupsForTest(); c.tableOpForTest("table-row-below"); c.tableOpForTest("table-del-row") }
            else if (step === 14) log("export", c.exportForTest())
            else if (step === 15 && !send) { c.clearForTest(); Qt.quit() }
            else if (step === 15) conversation.sendForTest()
            else if (step === 18) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); log("sent", m ? { text: m.text, html: m.html } : null); cap("sent") }
            else if (step === 19) Qt.quit()
            step++
        }
    }

    // --hovercard-test: in the 1:1 chat with OST Test 2, the title hovered
    // (the compact card opens ~640 ms later), captured, left (it closes
    // 500 ms later), then hovered again and Profile › (the full card).
    Timer {
        running: Qt.application.arguments.indexOf("--hovercard-test") >= 0 && chatList.chats.length > 1
        interval: 1500; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("HOVERCARD", tag, JSON.stringify(x))
            if (step === 0) { const ch = chatList.chats.find(c => c.name === "OST Test 2"); if (!ch) { log("no chat", ""); Qt.quit(); return } backend.selectChat(ch.id, ch.name) }
            else if (step === 2) conversation.hoverTitleForTest(true)
            else if (step === 3) log("open after 1.5 s", hoverCard.opened)
            else if (step === 4) { log("card", { name: hoverCard.displayName, loaded: hoverCard.card.displayName || "", loading: !!hoverCard.card.loading, error: hoverCard.card.error || "", availability: hoverCard.availability, mail: hoverCard.card.mail || "", x: hoverCard.x, y: hoverCard.y, h: hoverCard.height }); cap("card") }
            else if (step === 5) conversation.hoverTitleForTest(false)
            else if (step === 6) log("open after leaving", hoverCard.opened)
            else if (step === 7) conversation.hoverTitleForTest(true)
            else if (step === 9) { hoverCard.full("profile"); }
            else if (step === 10) { log("full card", { open: profileCard.opened, tab: profileCard.tab }); cap("full"); profileCard.close() }
            else if (step === 11) Qt.quit()
            step++
        }
    }

    // --chat-shot --open-chat=<id>: open that chat and capture it once its
    // messages are in (renderer comparisons).
    Timer {
        running: Qt.application.arguments.indexOf("--chat-shot") >= 0 && chatList.chats.length > 1
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (step === 0) { const c = chatList.chats.find(c => c.id === want) || chatList.chats[0]; backend.selectChat(c.id, c.name) }
            else if (step === 3) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath))
            else if (step === 4) Qt.quit()
            step++
        }
    }

    // --emoji-test: open the emoji picker in the open chat and capture it.
    Timer {
        running: Qt.application.arguments.indexOf("--emoji-test") >= 0 && chatList.chats.length > 1
        interval: 2000
        property bool opened: false
        repeat: true
        onTriggered: {
            if (!backend.currentChatId) { backend.selectChat(chatList.chats[1].id, chatList.chats[1].name); return }
            if (opened) return
            opened = true
            conversation.openEmojiForTest()
            capEmoji.start()
        }
    }
    Timer { id: capEmoji; interval: 1500; onTriggered: window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath.replace(".png", "-emoji.png")); Qt.quit() }) }

    // --settings-test: switch the theme and back, read the receipts
    // setting from Teams, list audio devices.
    Timer {
        running: Qt.application.arguments.indexOf("--settings-test") >= 0 && backend.signedIn
        interval: 1500
        property int step: 0
        property string before: ""
        repeat: true
        onTriggered: {
            if (step === 0) { before = backend.themeMode; backend.setSetting("theme", "dark") }
            else if (step === 1) {
                console.warn("SETTINGS theme", backend.themeMode, "dark", theme.dark, "saved", backend.setting("theme"))
                backend.setSetting("theme", before)
                backend.loadReadReceipts()
            } else if (step === 2) {
                const d = JSON.parse(backend.audioDevices())
                console.warn("SETTINGS restored", backend.themeMode, "receipts", backend.readReceipts, "mics", d.inputs.length, "speakers", d.outputs.length)
                Qt.quit()
            }
            step++
        }
    }

    // --activity-watch: log each change to the feed (live-update check).
    Connections {
        target: backend
        enabled: Qt.application.arguments.indexOf("--activity-watch") >= 0
        function onActivityJsonChanged() {
            const items = backend.activityJson ? JSON.parse(backend.activityJson) : []
            console.warn("ACTIVITY-FEED", items.length, items.length ? items[0].title : "", "badge", backend.activityUnread)
        }
    }

    // --activity-test: open the reaction item, capture, report.
    Timer {
        running: Qt.application.arguments.indexOf("--activity-test") >= 0 && backend.activityJson.length > 2
        interval: 3000
        property int step: 0
        repeat: true
        onTriggered: {
            const items = JSON.parse(backend.activityJson)
            if (step === 0) {
                rail.current = "activity"
                const r = items.find(i => i.kind === "reaction")
                if (r) activityView.openItem(r)
            } else if (step === 1) {
                const r = JSON.parse(backend.activityJson).find(i => i.kind === "reaction")
                console.warn("ACTIVITY open", activityView.selectedId === (r ? r.id : "?"), "chat", backend.currentChatId, "unread now", r ? r.unread : "?", "badge", backend.activityUnread)
                window.contentItem.grabToImage(g => { g.saveToFile(window.shotPath.replace(".png", "-open.png")); Qt.quit() })
            }
            step++
        }
    }

    // Resize from the edges when we draw our own frame.
    component Edge: MouseArea {
        property int edges
        enabled: !backend.systemFrame && window.visibility !== Window.Maximized
        z: 1000
        hoverEnabled: true
        onPressed: window.startSystemResize(edges)
    }
    Edge { edges: Qt.LeftEdge; x: 0; y: 6; width: 4; height: parent.height - 12; cursorShape: Qt.SizeHorCursor }
    Edge { edges: Qt.RightEdge; x: parent.width - 4; y: 6; width: 4; height: parent.height - 12; cursorShape: Qt.SizeHorCursor }
    Edge { edges: Qt.TopEdge; x: 6; y: 0; width: parent.width - 12; height: 4; cursorShape: Qt.SizeVerCursor }
    Edge { edges: Qt.BottomEdge; x: 6; y: parent.height - 4; width: parent.width - 12; height: 4; cursorShape: Qt.SizeVerCursor }
    Edge { edges: Qt.TopEdge | Qt.LeftEdge; x: 0; y: 0; width: 6; height: 6; cursorShape: Qt.SizeFDiagCursor }
    Edge { edges: Qt.TopEdge | Qt.RightEdge; x: parent.width - 6; y: 0; width: 6; height: 6; cursorShape: Qt.SizeBDiagCursor }
    Edge { edges: Qt.BottomEdge | Qt.LeftEdge; x: 0; y: parent.height - 6; width: 6; height: 6; cursorShape: Qt.SizeBDiagCursor }
    Edge { edges: Qt.BottomEdge | Qt.RightEdge; x: parent.width - 6; y: parent.height - 6; width: 6; height: 6; cursorShape: Qt.SizeFDiagCursor }
    FontLoader { source: "../assets/fonts/selawk.ttf" }
    FontLoader { source: "../assets/fonts/selawksb.ttf" }
    FontLoader { source: "../assets/fonts/selawkb.ttf" }
    FontLoader { source: "../assets/fonts/selawksl.ttf" }
    FontLoader { source: "../assets/fonts/CascadiaMono-Regular.ttf" }

    Backend {
        id: backend
        // --assume-focused: captures run offscreen, where nothing has focus.
        windowActive: window.active || Qt.application.arguments.indexOf("--assume-focused") >= 0
        onWindowActiveChanged: if (windowActive) markCurrentRead()
        Component.onCompleted: start()
        onActivateRequested: { window.show(); window.raise(); window.requestActivate() }
    }

    // OST_SCREENSHOT=<file.png>: render, optionally open a chat, save, quit.
    // Used for pixel comparison against the reference client.
    property bool sentTest: false
    property bool jumped: false
    property bool signInShot: false
    // Positional arguments (never flags): <shot.png> [send text] [awaited text].
    readonly property var positional: Qt.application.arguments.slice(1).filter(a => !a.startsWith("--"))
    readonly property string shotPath: positional.length > 0 ? positional[0] : ""
    Timer {
        id: shotTimer
        interval: 15000
        running: window.shotPath.length > 0 && !window.callTest && !window.typingTest && !window.reactTest && !window.editTest && !window.newChatTest && Qt.application.arguments.indexOf("--search-test") < 0 && Qt.application.arguments.indexOf("--channel-test") < 0 && Qt.application.arguments.indexOf("--emoji-test") < 0 && Qt.application.arguments.indexOf("--format-test") < 0 && Qt.application.arguments.indexOf("--table-test") < 0 && Qt.application.arguments.indexOf("--hovercard-test") < 0 && Qt.application.arguments.indexOf("--chat-shot") < 0 && Qt.application.arguments.indexOf("--header-test") < 0 && Qt.application.arguments.indexOf("--status-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--pause-test")) && Qt.application.arguments.indexOf("--settings-test") < 0 && Qt.application.arguments.indexOf("--settings-pages-test") < 0 && Qt.application.arguments.indexOf("--calendar-test") < 0 && Qt.application.arguments.indexOf("--group-test") < 0 && Qt.application.arguments.indexOf("--keys-test") < 0 && Qt.application.arguments.indexOf("--mentions-test") < 0 && Qt.application.arguments.indexOf("--join-test") < 0 && Qt.application.arguments.indexOf("--event-card-test") < 0 && Qt.application.arguments.indexOf("--group-call-test") < 0 && Qt.application.arguments.indexOf("--meet-now-test") < 0 && Qt.application.arguments.indexOf("--mute-test") < 0 && Qt.application.arguments.indexOf("--video-call-test") < 0 && Qt.application.arguments.indexOf("--meeting-chat-test") < 0 && Qt.application.arguments.indexOf("--breakpoints-test") < 0 && Qt.application.arguments.indexOf("--fun-picker-test") < 0 && Qt.application.arguments.indexOf("--attach-test") < 0 && Qt.application.arguments.indexOf("--filecard-test") < 0 && Qt.application.arguments.indexOf("--fileviewer-test") < 0 && Qt.application.arguments.indexOf("--poll-test") < 0 && Qt.application.arguments.indexOf("--media-order-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--custom-emoji")) && Qt.application.arguments.indexOf("--onedrive-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--onedrive-rows-test")) && !Qt.application.arguments.some(a => a.startsWith("--version-history-test")) && !Qt.application.arguments.some(a => a.startsWith("--details-test")) && Qt.application.arguments.indexOf("--preview-test") < 0 && Qt.application.arguments.indexOf("--sortview-test") < 0 && Qt.application.arguments.indexOf("--zip-test") < 0 && Qt.application.arguments.indexOf("--files-links-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--picker-test")) && Qt.application.arguments.indexOf("--folder-bar-test") < 0 && Qt.application.arguments.indexOf("--quick-access-test") < 0 && Qt.application.arguments.indexOf("--picker-views-test") < 0 && Qt.application.arguments.indexOf("--comments-test") < 0 && Qt.application.arguments.indexOf("--bell-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--folder-extras-test")) && Qt.application.arguments.indexOf("--planner-test") < 0 && Qt.application.arguments.indexOf("--apps-test") < 0 && Qt.application.arguments.indexOf("--channel-files-test") < 0 && Qt.application.arguments.indexOf("--store-test") < 0 && Qt.application.arguments.indexOf("--webapp-test") < 0 && Qt.application.arguments.indexOf("--loop-test") < 0 && Qt.application.arguments.indexOf("--tab-menu-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--tab-drag-test=")) && Qt.application.arguments.indexOf("--delete-undo-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--open-chat=")) && window.appDetailsTest.length === 0 && Qt.application.arguments.indexOf("--chatlist-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--share-test")) && !Qt.application.arguments.some(a => a.startsWith("--file-actions-test")) && Qt.application.arguments.indexOf("--open-file-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--sharefile-test")) && !Qt.application.arguments.some(a => a.startsWith("--search-grid-test")) && Qt.application.arguments.indexOf("--meeting-details-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--attendance-test=")) && !Qt.application.arguments.some(a => a.startsWith("--remove-history-"))
        onTriggered: {
            if (!backend.hasCredentials) {
                if (!backend.signInCode) {
                    if (!backend.busy) backend.beginSignIn()
                } else if (!window.signInShot) {
                    window.signInShot = true
                    console.warn("SIGNIN-CODE", backend.signInCode)
                    window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-signin.png")))
                }
                interval = 2000
                restart()
                return
            }
            if (!backend.signedIn) { interval = 2000; restart(); return }
            interval = 15000
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            // Push test: wait (unselected) for a chat to turn unread, capture
            // it, then open it and capture once the awaited text is shown.
            const waitText = window.positional.length > 2 ? window.positional[2] : ""
            if (waitText) {
                interval = 1000
                if (!backend.currentChatId) {
                    const hit = chats.find(c => c.unread)
                    if (hit) {
                        console.warn("PUSH-UNREAD", hit.name)
                        window.contentItem.grabToImage(r => {
                            r.saveToFile(window.shotPath.replace(".png", "-unread.png"))
                            backend.selectChat(hit.id, hit.name)
                        })
                    }
                    restart()
                    return
                }
                if (backend.messagesJson.indexOf(waitText) < 0) { restart(); return }
                console.warn("PUSH-SHOWN")
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                return
            }
            if (chats.length > 0 && !backend.currentChatId) {
                // --open-chat=<id> picks the chat to capture; else the first.
                const want = Qt.application.arguments.find(a => a.startsWith("--open-chat="))
                // Channels are picked by id too (named "General" etc.).
                const id = want ? want.slice(12) : ""
                const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
                const ch = id.endsWith("@thread.tacv2") ? teams.reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id) : null
                const pick = ch ? ch : want ? (chats.find(c => c.id === id) || chats[0]) : chats[0]
                backend.selectChat(pick.id, pick.name)
                restart()
                return
            }
            const sendText = window.positional.length > 1 ? window.positional[1] : ""
            if (sendText && !window.sentTest) {
                window.sentTest = true
                backend.sendMessage(sendText)
                restart()
                return
            }
            // --reply-test takes over once the channel is open.
            if (Qt.application.arguments.indexOf("--reply-test") >= 0) return
            // --tab=<name>: open that tab of the chat or channel first, and
            // give a web tab time to load.
            const wantTab = (Qt.application.arguments.find(a => a.startsWith("--tab=")) || "").slice(6)
            if (wantTab && conversation.tab !== wantTab) {
                if (conversation.tabNames.indexOf(wantTab) < 0) { restart(); return }
                conversation.tab = wantTab
                interval = 12000; restart(); return
            }
            // --jump=<text>: bring the newest message containing <text> into
            // view first.
            const jump = (Qt.application.arguments.find(a => a.startsWith("--jump=")) || "").slice(7)
            if (jump && !window.jumped) {
                const m = (backend.messagesJson ? JSON.parse(backend.messagesJson) : []).filter(m => JSON.stringify(m).indexOf(jump) >= 0).pop()
                if (m) { window.jumped = true; conversation.jumpToMessage(m.id); restart(); return }
            }
            console.warn("shot: signedIn", backend.signedIn, "chats", backend.chatsJson.length, "status", backend.statusText, "tabs", JSON.stringify(conversation.tabNames))
            window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
        }
    }

    IncomingCall {
        id: incomingCall
        visible: backend.callState === "ringing" && !ignored
        peer: backend.callPeer
        videoOffered: backend.callVideoOffered
        onAcceptVideo: backend.acceptCall(true)
        onAcceptAudio: backend.acceptCall(false)
        onDecline: backend.declineCall()
        // Ignore: stop ringing here; the call isn't declined.
        onIgnore: backend.setRinger(false)
    }
    // Teams' Rejoin: back into the meeting last joined.
    function rejoinMeeting() { backend.rejoinMeeting() }
    // The service ended the call for a reason Teams shows a screen for:
    // in the lobby the pre-join window turns into it, in the meeting the
    // meeting window does.
    Connections {
        target: backend
        function onCallEndReasonChanged() {
            const r = backend.callEndReason
            if (!r) return
            console.info("call ended:", r)
            if (preJoin.lobby || (preJoin.visible && r !== "removed")) preJoin.retryReason = r
            else callWindow.retryReason = r
        }
    }
    // In the lobby, the meeting's own times fill the pre-join date line.
    Connections {
        target: backend
        function onCallMeetingInfoJsonChanged() {
            if (!preJoin.lobby || preJoin.timesKnown || !backend.callMeetingInfoJson) return
            const i = JSON.parse(backend.callMeetingInfoJson)
            preJoin.setTimes(i.start, i.end)
        }
    }
    PreJoin {
        id: preJoin
        // Held in the lobby: Teams shows this screen again until we're let in.
        lobby: backend.callState === "lobby"
        presenterConnected: backend.callLobbyPresenter
        userName: backend.userName
        onLobbyChanged: if (lobby) { show(); raise(); if (!timesKnown) backend.loadMeetingInfo() } else if (visible && !retryReason) close()
        // Rejoin (nobody let us in): straight back into the lobby, as Teams.
        onRejoin: window.rejoinMeeting()
        onJoin: (micOn, withAudio, cameraOn) => {
            window.muteOnJoin = !micOn
            window.noAudioOnJoin = !withAudio
            window.cameraOnJoin = !!cameraOn
            if (meetNow) backend.channelMeetNow(meetChannel, subject.trim() || "Meeting")
            else backend.joinMeeting(joinUrl, subject)
        }
        // The switches still count in the lobby: they apply once admitted.
        onMicOnChanged: if (lobby) window.muteOnJoin = !micOn
        onCameraOnChanged: if (lobby) window.cameraOnJoin = cameraOn
        onLeaveLobby: backend.hangUp()
    }
    // Joining with the mic off (pre-join switch): mute once connected.
    property bool muteOnJoin: false
    // "Don't use audio": no sound either way once connected.
    property bool noAudioOnJoin: false
    // Joining with the camera on (pre-join switch): turn it on once
    // connected.
    property bool cameraOnJoin: false
    Connections {
        target: backend
        function onCallStateChanged() {
            if (backend.callState === "connected" && window.muteOnJoin) {
                window.muteOnJoin = false
                if (!backend.callMuted) backend.toggleMute()
            }
            if (backend.callState === "connected" && window.cameraOnJoin) {
                window.cameraOnJoin = false
                if (!backend.callCameraOn) backend.toggleCamera()
            }
            if (backend.callState === "connected" && window.noAudioOnJoin) {
                window.noAudioOnJoin = false
                backend.useNoAudio()
            }
        }
    }
    Connections {
        target: backend
        function onMeetingActionFailed(action) { callWindow.meetingActionFailed(action) }
        function onChatBubble(mri, name, text) {
            callWindow.showChatBubble(mri, name, text)
            if (Qt.application.arguments.indexOf("--join-chat-bubble") >= 0) {
                console.warn("JOIN chat bubble", name, text)
                bubbleShot.restart()
            }
        }
        function onMeetingReaction(mri, name) {
            callWindow.showReaction(mri, name)
            // --join-watch-reaction: capture the first reaction from someone else.
            if (Qt.application.arguments.indexOf("--join-watch-reaction") >= 0 && mri.toLowerCase() !== backend.userMri.toLowerCase())
                reactionShot.restart()
        }
    }
    // --join-ai: the bar with the AI indicator, then its menu, captured
    // whenever the meeting's AI state changes (named by state).
    property string aiLogged: ""
    Timer {
        id: aiShot
        property string tag: ""
        property int phase: 0
        interval: 700; repeat: true
        onTriggered: {
            const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-ai-" + tag + "-" + n + ".png")))
            if (phase === 0) grab("bar")
            else if (phase === 1) callWindow.aiPopoverForTest()
            else if (phase === 2) grab("menu")
            else { callWindow.aiPopoverCloseForTest(); stop() }
            phase++
        }
    }
    Timer { id: nsiPopShot; interval: 600; onTriggered: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-nsi-popover.png"))) }
    Timer { id: bubbleShot; interval: 600; onTriggered: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-bubble.png"))) }
    Timer { id: reactionShot; interval: 400; onTriggered: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-their-reaction.png"))) }
    CallWindow {
        id: callWindow
        visible: ["calling", "connecting", "connected", "ended"].indexOf(backend.callState) >= 0 || retryReason !== ""
        onRejoin: window.rejoinMeeting()
        controlsOptions: { const o = {}; (backend.callControlsJson ? JSON.parse(backend.callControlsJson).options : []).forEach(x => o[x.name] = x); return o }
        controlsPeople: backend.callControlsJson ? JSON.parse(backend.callControlsJson) : ({})
        onLoadControls: backend.loadMeetingControls()
        onSetMeetingOption: (name, value) => backend.setMeetingOption(name, JSON.stringify(value))
        onApplyMeetingOptions: changes => backend.setMeetingOptions(JSON.stringify(changes))
        peer: backend.callPeer
        selfName: backend.userName
        state: backend.callState
        muted: backend.callMuted
        hasAudio: backend.callHasAudio
        onLeave: { window.breakoutLeaving = true; window.breakoutMain = null; backend.hangUp() }
        onToggleMute: backend.toggleMute()
        canVideo: backend.callCanVideo
        cameraOn: backend.callCameraOn
        onToggleCamera: backend.toggleCamera()
        canShare: backend.callCanShare
        sharing: backend.callSharing
        onToggleShare: backend.toggleShare()
        held: backend.callHeld
        heldByPeer: backend.callHeldByPeer
        onToggleHold: backend.toggleHold()
        handRaised: backend.callHandRaised
        onToggleHand: backend.toggleHand()
        optionsUrl: backend.callOptionsUrl
        chatUrl: backend.callChatUrl
        onOpenApp: key => { rail.openApp(key); window.raise(); window.requestActivate() }
        canDtmf: backend.callCanDtmf
        onDtmf: key => backend.sendDtmf(key)
        onDeviceSettings: { rail.current = "settings"; window.raise(); window.requestActivate() }
        directory: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearchPeople: q => backend.searchPeople(q)
        onTransfer: (oid, name) => backend.transferCall(oid)
        // Consult, as Teams' chat consult: hold the caller and open a chat
        // with the person in the call's Chat pane; Transfer finishes it.
        onConsult: (oid, name) => {
            if (!backend.callHeld) backend.toggleHold()
            backend.openChatWith(oid, name)
            callWindow.side = "chat"
        }
        onClosing: if (backend.callState !== "ended") backend.hangUp()
        meeting: backend.callMeeting
        roster: backend.callRosterJson ? JSON.parse(backend.callRosterJson) : []
        videoKeys: backend.callVideoJson ? JSON.parse(backend.callVideoJson) : ({})
        onIncomingVideoOffChanged: backend.setIncomingVideo(!incomingVideoOff)
        shareId: backend.callShareMri
        onVideoWidthsChanged: backend.setVideoWidths(JSON.stringify(videoWidths))
        chatMembers: backend.callChatMembersJson ? JSON.parse(backend.callChatMembersJson) : []
        speakerId: backend.callSpeakerMri
        speakingIds: JSON.parse(backend.callSpeakingJson || "[]")
        mutedRemotely: backend.callMutedRemotely
        lobby: backend.callLobbyJson ? JSON.parse(backend.callLobbyJson) : []
        onAdmitLobby: (id, name, notBot) => backend.admitFromLobby(id, name, notBot)
        onDenyLobby: (id, name) => backend.denyFromLobby(id, name)
        onAdmitAllLobby: backend.admitAllFromLobby()
        onEndMeeting: backend.endMeeting()
        onParticipantAction: (action, id, name, stateId) => backend.participantAction(action, id, name, stateId)
        onLeaveOnAllDevices: backend.leaveOnAllDevices()
        locked: backend.callMeetingLocked
        networkStrength: backend.callNetworkStrength || "Good"
        scheduled: backend.callScheduled
        attendeeRestrictions: backend.callAttendeeRestrictions
        aiIndicator: backend.callAiIndicator
        aiAvailable: backend.callAiAvailable
        aiFacilitator: backend.callAiFacilitator
        aiOn: backend.callAiOn
        recordingState: backend.callRecordingState
        recordingTip: backend.callRecordingTip
        meetingInfo: backend.callMeetingInfoJson ? JSON.parse(backend.callMeetingInfoJson) : null
        onLoadMeetingInfo: backend.loadMeetingInfo()
        transcript: backend.callTranscriptJson ? JSON.parse(backend.callTranscriptJson) : []
        onLoadTranscript: backend.loadTranscript()
        captionsOn: backend.callCaptionsOn
        captions: backend.callCaptionsJson ? JSON.parse(backend.callCaptionsJson) : []
        captionsLanguage: backend.callCaptionsLanguage || backend.setting("spokenLanguage") || "en-us"
        accessibility: backend.callAccessibilityJson ? JSON.parse(backend.callAccessibilityJson) : ({})
        captionStyles: { const s = backend.setting("captionStyles"); try { return s ? JSON.parse(s) : {} } catch (e) { return {} } }
        onSetCaptions: on => backend.setCaptions(on)
        onSetCaptionsLanguage: code => backend.setCaptionsLanguage(code)
        timerData: backend.callTimerJson ? JSON.parse(backend.callTimerJson) : null
        callHealth: backend.callHealthJson ? JSON.parse(backend.callHealthJson) : ({})
        onRefreshCallHealth: backend.callHealthRefresh()
        everyonePresents: backend.callEveryonePresents
        onTimerAction: (name, arg) => backend.meetingTimer(name, arg)
        onTimerChime: backend.timerChime()
        rttOn: backend.callRttOn
        rttInitiator: backend.callRttInitiator
        privacyUrl: backend.callPrivacyUrl
        onStartRtt: backend.startRtt()
        onUpdateAccessibility: patch => backend.updateCallAccessibility(patch)
        onSaveCaptionStyles: styles => { backend.setSetting("captionStyles", JSON.stringify(styles)); captionStyles = styles }
        showMutedNotice: backend.setting("showMutedNotice") !== "false"
        speakingWhileMuted: backend.callSpeakingWhileMuted
        notificationsMuted: backend.callNotificationsMuted
        chatBubblesSuppressed: backend.callChatBubblesSuppressed
        onSetChatBubblesSuppressed: on => backend.callChatBubblesSuppressed = on
        onSetNotificationsMuted: on => backend.callNotificationsMuted = on
        onSetShowMutedNotice: on => { backend.setSetting("showMutedNotice", on ? "true" : "false"); showMutedNotice = on }
        onCopyMeetingJoinInfo: backend.copyMeetingJoinInfo()
        onRecorderCommand: (command, language, audioOnly) => backend.recorderCommand(command, language, audioOnly)
        lockNotices: backend.callLockNotices
        onMeetingAction: action => backend.meetingAction(action)
        onSetAttendeeRestrictions: bits => backend.setAttendeeRestrictions(bits)
        onDownloadAttendance: backend.downloadAttendanceList()
        onMuteAll: backend.muteAll()
        onSendReaction: name => backend.sendReaction(name)
        inviteUrl: backend.callInviteUrl
        selfId: backend.userMri
        // Chat: the 1:1 chat with the person in the call, or the meeting chat.
        onOpenChat: {
            if (backend.callMeeting) { backend.selectChat(backend.callThreadId, backend.callPeer); return }
            const oid = backend.callPeerId.replace(/^8:orgid:/, "")
            if (oid) backend.openChatWith(oid, backend.callPeer)
        }
        chatPane.chatName: backend.currentChatName
        chatPane.chatId: backend.currentChatId
        chatPane.myName: backend.userName
        chatPane.messages: conversation.messages
        chatPane.busy: backend.busy
        chatPane.typingText: backend.typingText
        chatPane.typingAvatar: backend.typingAvatar
        chatPane.typingAvatarId: backend.typingAvatarId
        chatPane.isGroup: backend.currentChatId.endsWith("@thread.v2") || backend.currentChatId.indexOf("meeting_") >= 0
        chatPane.onSend: text => backend.sendMessage(text)
        chatPane.onTyping: backend.userTyping()
        chatPane.onReact: (id, key, on) => backend.toggleReaction(id, key, on)
    }
    // Ring while a call is incoming.
    Connections {
        target: backend
        function onCallStateChanged() { backend.setRinger(backend.callState === "ringing") }
    }

    // "Call ended" shows briefly, then the call window closes.
    Timer {
        running: backend.callState === "ended"
        interval: 2000
        onTriggered: backend.callState = ""
    }

    // --call-test: capture the toast, answer, capture the call, hang up.
    readonly property bool callOut: Qt.application.arguments.indexOf("--call-out") >= 0
    readonly property bool callTest: callOut || Qt.application.arguments.indexOf("--call-test") >= 0 || Qt.application.arguments.indexOf("--hold-test") >= 0 || Qt.application.arguments.some(a => a.indexOf("--transfer-test=") === 0) || Qt.application.arguments.indexOf("--call-panes") >= 0
    property string favName: ""
    readonly property bool callPanes: Qt.application.arguments.indexOf("--call-panes") >= 0
    // --remote-hangup: stay in the call until the caller ends it.
    readonly property bool remoteHangup: Qt.application.arguments.indexOf("--remote-hangup") >= 0 || Qt.application.arguments.indexOf("--hold-test") >= 0 || Qt.application.arguments.some(a => a.indexOf("--transfer-test=") === 0)
    Connections {
        target: backend
        enabled: window.callTest
        function onCallStateChanged() {
            console.warn("CALL-STATE", backend.callState)
            if (backend.callState === "ringing") {
                callTestTimer.step = "ring"; callTestTimer.restart()
            } else if (backend.callState === "connected") {
                // --camera-on: turn the camera on once connected.
                if (Qt.application.arguments.indexOf("--camera-on") >= 0 && backend.callCanVideo && !backend.callCameraOn) backend.toggleCamera()
                callTestTimer.step = "talk"; callTestTimer.interval = Qt.application.arguments.indexOf("--camera-on") >= 0 ? 15000 : 8000; callTestTimer.restart()
            } else if (backend.callState === "ended" && (window.remoteHangup || window.callOut)) {
                quitTimer.start()
            }
        }
    }
    Timer {
        id: callTestTimer
        property string step
        interval: 4000
        onTriggered: {
            if (step === "ring") {
                incomingCall.contentItem.grabToImage(r => {
                    r.saveToFile(window.shotPath.replace(".png", "-toast.png"))
                    // --accept-video: answer with video when it's offered.
                    backend.acceptCall(Qt.application.arguments.indexOf("--accept-video") >= 0 && backend.callVideoOffered)
                })
            } else if (step === "talk" && window.callPanes) {
                // --call-panes: open Chat, then People, capturing each.
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-call.png")))
                callWindow.side = "chat"; callWindow.openChat()
                step = "chat"; interval = 5000; restart()
            } else if (step === "chat") {
                callWindow.contentItem.grabToImage(r => {
                    r.saveToFile(window.shotPath.replace(".png", "-chatpane.png"))
                    callWindow.side = "people"
                    callTestTimer.step = "people"; callTestTimer.interval = 1500; callTestTimer.restart()
                })
            } else if (step === "people") {
                callWindow.contentItem.grabToImage(r => {
                    r.saveToFile(window.shotPath.replace(".png", "-people.png"))
                    backend.hangUp()
                    quitTimer.start()
                })
            } else if (step === "talk") {
                console.warn("CALL video frame shown", callWindow.remoteVideoShown, "can video", backend.callCanVideo, "camera", backend.callCameraOn)
                callWindow.contentItem.grabToImage(r => {
                    r.saveToFile(window.shotPath.replace(".png", "-call.png"))
                    if (!window.remoteHangup) {
                        backend.hangUp()
                        quitTimer.start()
                    }
                })
            }
        }
    }
    Timer { id: quitTimer; interval: 3000; onTriggered: Qt.quit() }
    // In a test call, capture the stage once someone's shared screen shows.
    Connections {
        target: callWindow
        enabled: window.callTest
        function onShareShownChanged() {
            console.warn("CALL share shown", callWindow.shareShown)
            if (callWindow.shareShown) shareShot.start()
        }
    }
    // Without a capture path, --open-chat=<id> [--tab=<name>] just opens
    // that chat or channel (and tab) and leaves OST running.
    Timer {
        running: window.shotPath.length === 0 && backend.signedIn && !opened
            && Qt.application.arguments.some(a => a.startsWith("--open-chat="))
        property bool opened: false
        interval: 2000; repeat: true
        onTriggered: {
            const id = Qt.application.arguments.find(a => a.startsWith("--open-chat=")).slice(12)
            if (backend.currentChatId !== id) {
                const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
                const ch = teams.reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
                const pick = ch || chats.find(c => c.id === id)
                if (pick) backend.selectChat(pick.id, pick.name)
                return
            }
            const tab = (Qt.application.arguments.find(a => a.startsWith("--tab=")) || "").slice(6)
            if (tab && conversation.tabNames.indexOf(tab) < 0) return
            if (tab) conversation.tab = tab
            opened = true
        }
    }
    // --loop-test --loop-steps=<file>: a Page view (Loop, page only), run
    // through the steps in the file, to test the Page tab's insert row on
    // a scratch page of the test account's own.
    Loader {
        id: loopTest
        active: Qt.application.arguments.indexOf("--loop-test") >= 0 && backend.signedIn
        z: 100
        anchors.fill: parent
        sourceComponent: WebApp { pageOnly: true; showHeader: false; home: "https://loop.cloud.microsoft/" }
    }
    function loopJs(code) { loopTest.item.view.runJavaScript(code, r => console.warn("LOOP", JSON.stringify(r))) }
    // Steps from the file OST_LOOP_STEPS names: one JS snippet a line, or
    // "SHOT name", or "INSERT command"; one every 5 s.
    Timer {
        running: loopTest.status === Loader.Ready
        interval: 5000; repeat: true
        property var steps: null
        property int i: 0
        onTriggered: {
            if (!steps) {
                const x = new XMLHttpRequest(); x.open("GET", "file://" + Qt.application.arguments.find(a => a.startsWith("--loop-steps=")).slice(13), false); x.send()
                steps = x.responseText.split("\n").filter(l => l.trim())
            }
            if (i >= steps.length) { Qt.quit(); return }
            const st = steps[i++]
            console.warn("LOOP step", st.slice(0, 80))
            if (st.startsWith("SHOT ")) window.loopShot(st.slice(5))
            else if (st.startsWith("INSERT ")) loopTest.item.insertOnPage(st.slice(7))
            else if (st.startsWith("TYPE ")) { loopTest.item.view.forceActiveFocus(); loopTest.item.typeForTest(st.slice(5).replace("<END>", "\u0001").replace("<RET>", "\n")) }
            else window.loopJs(st)
        }
    }
    function loopShot(name) { window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + name + ".png"))) }
    // --tab-menu-test: in the channel --open-chat names (with test tabs
    // "OST tab A" and "OST tab B"): log every tab's menu, capture the Notes
    // menu and the Rename and Remove dialogs, then rename A, move it next
    // to B, and remove both, logging the tabs after each step.
    Timer {
        running: Qt.application.arguments.indexOf("--tab-menu-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const names = JSON.stringify(conversation.tabNames)
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png")))
            if (step === 0) {
                if (names.indexOf("OST tab A") < 0) return
                for (const t of conversation.tabNames) console.warn("TABS menu", t, JSON.stringify(conversation.tabMenuForTest(t)))
                conversation.tab = "Notes"
            }
            else if (step === 1) conversation.tabMenuShowForTest("Notes")
            else if (step === 2) shot("menu")
            else if (step === 3) { conversation.tabMenuCloseForTest(); conversation.tabDialogForTest("rename", "OST tab A") }
            else if (step === 4) shot("rename")
            else if (step === 5) { conversation.tabDialogCloseForTest(); conversation.tabDialogForTest("remove", "OST tab A") }
            else if (step === 6) shot("remove")
            else if (step === 7) { conversation.tabDialogCloseForTest(); conversation.tabAboutForTest("Notes") }
            else if (step === 8) { console.warn("TABS about", conversation.tabAboutStateForTest()); shot("about") }
            else if (step === 9) { conversation.tabAboutCloseForTest(); conversation.tabChangeForTest("rename", "OST tab A", "OST tab A2") }
            else if (step === 10) {
                console.warn("TABS renamed", names)
                const n = conversation.tabNames
                conversation.tabChangeForTest(n.indexOf("OST tab A2") < n.indexOf("OST tab B") ? "right" : "left", "OST tab A2")
            }
            else if (step === 11) { console.warn("TABS moved", names); conversation.tabChangeForTest("remove", "OST tab A2") }
            else if (step === 12) { console.warn("TABS removed A", names); conversation.tabChangeForTest("remove", "OST tab B") }
            else if (step === 13) { console.warn("TABS removed B", names); Qt.quit() }
            step++
        }
    }
    // --attendance-test=<meeting chat id> [--attendance-channel=<channel
    // id>,<post id>]: Teams' Attendance card and view: capture the meeting
    // chat's cards, open the newest meeting's report (the tab), its picker,
    // download the report; then the channel meeting's post view, its card
    // and the channel report.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--attendance-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = Qt.application.arguments.find(a => a.startsWith("--attendance-test=")).slice(18)
            const chan = (Qt.application.arguments.find(a => a.startsWith("--attendance-channel=")) || "").slice(21).split(",")
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-att-" + n + ".png")))
            const msgs = () => backend.messagesJson ? JSON.parse(backend.messagesJson) : []
            if (step === 0) { backend.selectChat(id, "OST calendar test: created from OST") }
            else if (step === 3) {
                const ends = msgs().filter(m => m.kind === "call" && m.call_id && m.call_state !== "started")
                console.warn("ATT can", conversation.canSeeAttendance, "meeting", backend.chatMeetingJson.slice(0, 300), "ends", JSON.stringify(ends.map(m => [m.call_id, m.call_state, m.call_seconds])))
                shot("chat")
            }
            else if (step === 4) {
                const ends = msgs().filter(m => m.kind === "call" && m.call_id && m.call_state !== "started")
                if (ends.length) conversation.openAttendance(ends[ends.length - 1].call_id)
            }
            else if (step === 6) { const v = conversation.attendanceViewForTest(); console.warn("ATT view", conversation.tab, JSON.stringify(conversation.tabNames), v ? v.callId : "-", backend.attendanceJson.slice(0, 600)); shot("view") }
            else if (step === 7) { const v = conversation.attendanceViewForTest(); if (v) v.openPickerForTest() }
            else if (step === 8) shot("picker")
            else if (step === 9) { const v = conversation.attendanceViewForTest(); if (v) { v.children.forEach(c => c.close && c.close()); backend.downloadAttendanceReport(v.thread, v.organizer, v.callId) } }
            else if (step === 11) console.warn("ATT download", backend.statusText)
            else if (step === 12) { if (chan.length === 2) backend.selectChat(chan[0], "General"); else Qt.quit() }
            else if (step === 15) conversation.openPostView(chan[1])
            else if (step === 18) shot("post")
            else if (step === 19) { const pv = conversation.postViewForTest ? conversation.postViewForTest() : null; console.warn("ATT post view", !!pv) }
            else if (step === 20) conversation.channelAttendance = { organizer: (backend.userMri || "").replace("8:orgid:", ""), message: chan[1], call: "" }
            else if (step === 22) { console.warn("ATT channel", backend.attendanceJson.slice(0, 400)); shot("channel") }
            else if (step === 23) Qt.quit()
            step++
        }
    }
    // Breakout rooms, as a participant (Teams desktop, measured on winpc
    // 2026-11-11). When the room you're assigned opens, Teams shows "Join
    // room" first on the bar and "We'll move you to your assigned room in
    // 10 seconds.", then moves you: it joins the room and leaves the main
    // meeting once the room answers. When the organizer closes the room
    // (the room's chat is restricted), "We'll move you back to the main
    // meeting in 10 seconds." and back; if the room's call ends first,
    // back at once after the room's jitter. "Return" goes back early when
    // the organizer allows it, and the organizer's Join on a room's menu
    // goes there too.
    property var breakoutMain: null
    property bool breakoutLeaving: false
    readonly property var breakoutRooms: backend.callBreakoutJson ? JSON.parse(backend.callBreakoutJson) : []
    readonly property var breakoutRoomState: backend.callBreakoutRoomJson ? JSON.parse(backend.callBreakoutRoomJson) : null
    readonly property var assignedOpenRoom: breakoutRooms.find(r => r.open) || null
    readonly property int breakoutMoveSeconds: 10
    function goToBreakoutRoom(room) {
        breakoutMove.stop()
        if (!room || window.breakoutMain) return
        window.breakoutMain = JSON.parse(backend.currentMeeting())
        console.warn("BREAKOUT moving to", room.name)
        backend.moveMeeting(room.join_url, room.name)
    }
    // Back to the main meeting held for a room: its time carries on.
    function resumeHeldMeeting() {
        callWindow.nextConnectedAt = Date.now() - (callWindow.heldElapsedBase + callWindow.mainHeldSeconds) * 1000
        backend.leaveRoom(true)
    }
    function goBackToMainMeeting() {
        breakoutReturn.stop()
        // A room joined over the held main meeting: resume it.
        if (callWindow.heldMeeting) { window.resumeHeldMeeting(); return }
        const main = window.breakoutMain
        if (!main) return
        window.breakoutMain = null
        const url = window.breakoutRoomState && window.breakoutRoomState.main_join_url || main.url
        console.warn("BREAKOUT back to", main.title)
        backend.moveMeeting(url, main.title)
    }
    onAssignedOpenRoomChanged: {
        if (window.breakoutMain || backend.callState !== "connected") return
        const room = assignedOpenRoom
        if (!room) { breakoutMove.stop(); return }
        if (breakoutMove.running && breakoutMove.room && breakoutMove.room.join_url === room.join_url) return
        breakoutMove.room = room
        if (room.auto_move) {
            callWindow.showBreakoutAlert("We'll move you to your assigned room in " + breakoutMoveSeconds + " seconds.")
            breakoutMove.interval = breakoutMoveSeconds * 1000 + room.move_jitter_ms
            breakoutMove.restart()
        } else {
            callWindow.showBreakoutAlert("You've been assigned to " + room.name)
        }
    }
    onBreakoutRoomStateChanged: {
        if (!(window.breakoutMain || callWindow.heldMeeting) || !breakoutRoomState || !breakoutRoomState.closed || breakoutReturn.running) return
        callWindow.showBreakoutAlert("We'll move you back to the main meeting in " + breakoutMoveSeconds + " seconds.")
        breakoutReturn.interval = breakoutMoveSeconds * 1000 + breakoutRoomState.move_jitter_ms
        breakoutReturn.restart()
    }
    Binding { target: callWindow; property: "roomToJoin"; value: !!window.assignedOpenRoom && !window.breakoutMain }
    Binding {
        target: callWindow; property: "canReturnToMain"
        value: !!window.breakoutMain && !!window.breakoutRoomState && window.breakoutRoomState.allow_return && !window.breakoutRoomState.closed
    }
    Timer { id: breakoutMove; property var room: null; onTriggered: window.goToBreakoutRoom(room) }
    Timer { id: breakoutReturn; onTriggered: window.goBackToMainMeeting() }
    Connections {
        target: callWindow
        function onJoinBreakoutRoom() { window.goToBreakoutRoom(window.assignedOpenRoom) }
        function onReturnToMainMeeting() { window.goBackToMainMeeting() }
        // Teams holds the organizer's main meeting while they're in a room.
        function onJoinRoomAsOrganizer(room) {
            callWindow.heldElapsedBase = callWindow.seconds
            backend.joinRoomHoldingMain(room.join_url, room.name)
        }
        function onLeaveRoom(resume) { breakoutReturn.stop(); if (resume) window.resumeHeldMeeting(); else backend.leaveRoom(false) }
    }
    Connections {
        target: backend
        function onCallStateChanged() {
            // The room ended under the held main meeting: back to it.
            if (backend.callState === "ended" && callWindow.heldMeeting) { window.resumeHeldMeeting(); return }
            if (!window.breakoutMain) return
            if (backend.callState === "ended" && !window.breakoutLeaving) {
                // The room ended (closed rooms end for everyone): back
                // after the room's jitter.
                breakoutReturn.interval = Math.max(1, window.breakoutRoomState ? window.breakoutRoomState.move_jitter_ms : 0)
                breakoutReturn.restart()
            } else if (backend.callState === "") {
                window.breakoutLeaving = false
            }
        }
        function onBreakoutActionDone(action, error) { callWindow.breakoutDone(action, error) }
    }
    // --remove-history-check=<chat id>: open the chat and log the messages
    // shown (after Remove chat history only the newer ones).
    Timer {
        readonly property string target: (Qt.application.arguments.find(a => a.startsWith("--remove-history-check=")) || "").slice(23)
        running: target.length > 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            step++
            const channel = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === target)
            if (step === 2) backend.selectChat(target, (chatList.chats.find(c => c.id === target) || channel || {}).name || "")
            else if (step === 5) {
                console.warn("RMHIST check", JSON.stringify((JSON.parse(backend.messagesJson || "[]")).map(m => (m.text || m.content || "").slice(0, 60))), "layout", conversation.channelLayout, "threads", conversation.threadsLayout, "banner", appBanner.kind)
                window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rmhist-check.png")))
            }
            else if (step === 7) Qt.quit()
        }
    }
    // --remove-history-test=<chat id>: open the chat, show Teams' "Remove
    // chat history?" from its header menu, remove it, and log whether the
    // list still shows it and which chat is open ("-rmhist-<n>.png").
    Timer {
        readonly property string target: (Qt.application.arguments.find(a => a.startsWith("--remove-history-test=")) || "").slice(22)
        running: target.length > 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const grab = n => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rmhist-" + n + ".png")))
            const listed = () => chatList.chats.some(c => c.id === target && !c.hidden)
            step++
            if (step === 2) { console.warn("RMHIST listed", listed()); backend.selectChat(target, (chatList.chats.find(c => c.id === target) || {}).name || "") }
            else if (step === 4) { console.warn("RMHIST open", backend.currentChatId, "messages", (JSON.parse(backend.messagesJson || "[]")).length); grab("chat"); conversation.removeHistoryForTest().open() }
            else if (step === 5) grab("dialog")
            else if (step === 6) { conversation.removeHistoryForTest().close(); backend.removeChatHistory(target) }
            else if (step === 9) { console.warn("RMHIST after listed", listed(), "open", backend.currentChatId); grab("after") }
            else if (step === 30) { console.warn("RMHIST later listed", listed()); Qt.quit() }
        }
    }
    // --breakout-watch (with --join-test, as a participant): capture the
    // call window ("-watch-<n>.png") and log whenever the breakout phase
    // changes (the alert, Join room, in a room, Return, closed).
    Timer {
        running: Qt.application.arguments.indexOf("--breakout-watch") >= 0 && backend.callState !== ""
        interval: 1500; repeat: true
        property string last: ""
        property int n: 0
        onTriggered: {
            const phase = JSON.stringify([callWindow.breakoutAlert ? callWindow.breakoutAlert.text : "", callWindow.roomToJoin,
                                          !!window.breakoutMain, callWindow.canReturnToMain, backend.callState,
                                          window.breakoutRoomState ? window.breakoutRoomState.closed : null])
            if (phase === last) return
            last = phase; n++
            console.warn("BREAKOUTWATCH", n, phase, "bar", JSON.stringify(callWindow.ubar.bar.slice(0, 3)))
            const k = n
            callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-watch-" + k + ".png")))
        }
    }
    // --breakout-test (with --join-test, as the organizer): once someone
    // else is in the meeting, walk Teams' Rooms pane — create one room
    // (automatic), the Assign dialog, Settings, open the rooms, an
    // announcement ("OST test 100: …"), Rename, close the rooms, Remove
    // rooms — capturing each step ("-rooms-<n>.png") and logging the rooms.
    Timer {
        running: Qt.application.arguments.indexOf("--breakout-test") >= 0 && backend.callState === "connected"
        interval: 3000; repeat: true
        property int step: -1
        onTriggered: {
            const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rooms-" + n + ".png")))
            const heldShot = n => { const w = callWindow.heldWindowForTest(); if (w) w.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rooms-" + n + ".png"))) }
            const joinTest = Qt.application.arguments.indexOf("--breakout-join") >= 0
            const log = t => console.warn("BREAKOUTTEST", t, JSON.stringify(callWindow.breakoutRooms))
            const lobby = JSON.parse(backend.callLobbyJson || "[]")
            if (lobby.length) { console.warn("BREAKOUTTEST admitting", lobby[0].name); backend.admitFromLobby(lobby[0].id, lobby[0].name, false); return }
            // --breakout-solo: don't wait for anyone (rooms without people).
            if (step < 0) { if (callWindow.people.some(p => !p.you) || Qt.application.arguments.indexOf("--breakout-solo") >= 0) step = 0; return }
            step++
            const t = callWindow.roomsForTest
            ;({
                1: () => { t("pane"); },
                2: () => shot("create"),
                3: () => callWindow.createBreakoutRooms(1, "automatic"),
                6: () => { log("created"); shot("manage") },
                7: () => t("assign"),
                8: () => shot("assign"),
                9: () => { t("close"); t("settings") },
                10: () => shot("settings"),
                11: () => t("back"),
                12: () => callWindow.breakoutRun("open", { threads: callWindow.breakoutRooms.map(r => r.thread) }),
                20: () => { log("opened"); shot("open") },
                21: () => t("announce"),
                22: () => shot("announce"),
                23: () => { t("close"); callWindow.breakoutRun("announce", { message: "OST test 100: breakout announcement from OST" }) },
                25: () => t("rename"),
                26: () => shot("rename"),
                27: () => { t("close"); t("csv") },
                28: () => shot("csv"),
                29: () => t("close"),
                // --breakout-join: the organizer's Join on the room's menu
                // (the main meeting held), then Leave room.
                30: () => { if (joinTest) { console.warn("BREAKOUTTEST joining"); callWindow.joinRoomAsOrganizer(callWindow.breakoutRooms[0]) } },
                36: () => { if (joinTest) { console.warn("BREAKOUTTEST in room", backend.callHeldMeetingJson, backend.callState, JSON.stringify(callWindow.leaveItems)); shot("joined"); heldShot("held") } },
                38: () => { if (joinTest) callWindow.leaveRoom(true) },
                43: () => { if (joinTest) { console.warn("BREAKOUTTEST resumed", backend.callHeldMeetingJson || "none", backend.callState, backend.callPeer, "role", callWindow.myRole, "people", JSON.stringify(callWindow.people.map(p => p.name)), "time", callWindow.seconds, "bar", JSON.stringify(callWindow.ubar.bar)); shot("resumed") } },
                46: () => callWindow.breakoutRun("close", { threads: callWindow.breakoutRooms.map(r => r.thread) }),
                49: () => { log("closed"); shot("closed") },
                60: () => { log("later"); shot("later"); t("remove") },
                61: () => shot("remove"),
                62: () => { t("close"); callWindow.breakoutRun("delete_all", {}) },
                65: () => { log("removed"); shot("removed") },
                66: () => console.warn("BREAKOUTTEST done")
            }[step] || (() => {}))()
        }
    }
    Connections {
        target: backend
        enabled: Qt.application.arguments.indexOf("--breakout-test") >= 0
        function onBreakoutActionDone(action, error) { console.warn("BREAKOUTTEST action", action, error || "ok") }
    }
    // --join-lobby-chat (with --join-test, as the organizer): once someone
    // waits in the lobby, capture the toast (its chat button), open the
    // Lobby tab, send "OST test 97: lobby chat from OST" and capture the
    // tab, logging the lobby thread and its messages.
    Timer {
        running: Qt.application.arguments.indexOf("--join-lobby-chat") >= 0 && backend.callState === "connected"
        interval: 2000; repeat: true
        property int step: -1
        onTriggered: {
            const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-lobbychat-" + n + ".png")))
            const lobby = callWindow.lobby || []
            if (step < 0) { if (lobby.length === 1) { console.warn("LOBBYCHAT waiting", JSON.stringify(lobby), "available", callWindow.lobbyChatAvailable, "role", callWindow.myRole, "toast chat", callWindow.lobbyToastForTest().chatShown); shot("toast"); step = 0 } return }
            step++
            if (step === 1) callWindow.openLobbyChat()
            else if (step === 4) { console.warn("LOBBYCHAT thread", backend.callLobbyThread, "tab", callWindow.chatTab, "shown", callWindow.lobbyTabShown); shot("tab") }
            else if (step === 5) { const p = callWindow.lobbyPaneForTest(); p.insertTextForTest("OST test 97: lobby chat from OST"); p.sendForTest() }
            else if (step === 9) { console.warn("LOBBYCHAT messages", JSON.stringify(callWindow.lobbyMessages.map(m => [m.kind, m.text, m.sender]))); shot("sent") }
            else if (step === 10) { callWindow.chatTab = "everyone"; }
            else if (step === 11) { shot("everyone"); callWindow.chatTab = "lobby"; callWindow.side = "people" }
            else if (step === 12) { shot("people"); console.warn("LOBBYCHAT stage people", JSON.stringify(callWindow.people.map(p => p.name))) }
        }
    }
    // --delete-undo-test: in the chat --open-chat names, delete your newest
    // message "OST test 40…", capture the tombstone, undo, and log the
    // message's state at each step.
    Timer {
        running: Qt.application.arguments.indexOf("--delete-undo-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        property string id: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST Test 1 (You)"); return }
            const msgs = backend.messagesJson ? JSON.parse(backend.messagesJson) : []
            const target = msgs.filter(m => m.mine && /OST test 40/.test(m.text || "")).pop()
                || (this.id ? msgs.find(m => m.id === this.id) : null)
            const state = target ? JSON.stringify({ id: target.id, deleted: target.deleted, text: (target.text || "").slice(0, 30) }) : "none"
            if (step === 0) { if (!target) return; this.id = target.id; console.warn("DELETE before", state); backend.deleteMessage(target.id) }
            else if (step === 1) { console.warn("DELETE after", state); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-tomb.png"))) }
            else if (step === 2) backend.undoDeleteMessage(this.id)
            else if (step === 3) { console.warn("DELETE undone", state); Qt.quit() }
            step++
        }
    }
    // --share-test: once connected, share a screen (the desktop's picker
    // asks what), keep it up for 30 s, then stop.
    readonly property bool shareTest: Qt.application.arguments.indexOf("--share-test") >= 0
    Connections {
        target: backend
        enabled: window.shareTest
        function onCallStateChanged() { if (backend.callState === "connected") shareStart.start() }
        function onCallSharingChanged() {
            console.warn("CALL sharing", backend.callSharing)
            if (backend.callSharing) shareStop.start()
        }
        function onCallCanShareChanged() { console.warn("CALL can share", backend.callCanShare) }
    }
    Timer { id: shareStart; interval: 5000; onTriggered: { console.warn("SHARE start, can share", backend.callCanShare); backend.toggleShare() } }
    Timer {
        id: shareStop; interval: 30000
        onTriggered: {
            callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-sharing.png")))
            console.warn("SHARE stop"); backend.toggleShare()
        }
    }
    Timer { id: shareShot; interval: 3000; onTriggered: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-share.png"))) }
    // --call-out: open the first chat and call it.
    Timer {
        running: window.callOut && backend.signedIn && !backend.callState
        interval: 4000
        onTriggered: {
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            if (!backend.currentChatId && chats.length > 0) {
                // --open-chat=<id> picks whom to call; else the first chat.
                const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
                const c = chats.find(c => c.id === want || c.name === want) || chats[0]
                backend.selectChat(c.id, c.name); restart(); return
            }
            if (window.outStarted) return
            window.outStarted = true
            backend.startCall()
            callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-calling.png")))
            if (window.cancelRing) cancelRingTimer.start()
        }
    }
    property bool outStarted: false
    // --cancel-ring: with --call-out, hang up while the callee is still ringing.
    readonly property bool cancelRing: Qt.application.arguments.indexOf("--cancel-ring") >= 0
    Timer { id: cancelRingTimer; interval: 8000; onTriggered: backend.hangUp() }

    // --edit-test: send two messages, edit the first and delete the second,
    // capture when both show.
    readonly property bool editTest: Qt.application.arguments.indexOf("--edit-test") >= 0
    property int editStep: 0
    Timer {
        running: window.editTest && backend.signedIn
        interval: 3000; repeat: true
        onTriggered: {
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            if (!backend.currentChatId && chats.length > 0) { backend.selectChat(chats[0].id, chats[0].name); return }
            const msgs = backend.messagesJson ? JSON.parse(backend.messagesJson) : []
            const find = t => msgs.filter(m => m.mine && m.text.indexOf(t) >= 0).pop()
            if (window.editStep === 0) { backend.sendMessage("OST test 14: this will be edited"); window.editStep = 1; return }
            if (window.editStep === 1) { const m = find("OST test 14"); if (m) { backend.editMessage(m.id, "OST test 14: edited from OST"); window.editStep = 2 } return }
            if (window.editStep === 2) { backend.sendMessage("OST test 15: this will be deleted"); window.editStep = 3; return }
            if (window.editStep === 3) { const m = find("OST test 15"); if (m) { backend.deleteMessage(m.id); window.editStep = 4 } return }
            const edited = msgs.find(m => m.mine && m.edited && m.text.indexOf("edited from OST") >= 0)
            const deleted = msgs.find(m => m.mine && m.deleted)
            console.warn("EDIT-STATE", !!edited, !!deleted)
            if (edited && deleted) { window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() }); stop() }
        }
    }

    // --new-chat-test: search "Randy", capture the picker, open the chat.
    readonly property bool newChatTest: Qt.application.arguments.indexOf("--new-chat-test") >= 0
    property int newChatStep: 0
    Timer {
        running: window.newChatTest && backend.signedIn
        interval: 3000; repeat: true
        onTriggered: {
            if (window.newChatStep === 0) { window.composing = true; backend.searchPeople("Randy"); window.newChatStep = 1; return }
            const people = backend.peopleJson ? JSON.parse(backend.peopleJson) : []
            if (window.newChatStep === 1 && people.length > 0) {
                console.warn("PEOPLE", people.map(p => p.name + " <" + p.mail + ">").join(", "))
                const p = people.find(p => (p.mail || "").toLowerCase() === "randy@scnetsolutions.com") || people[0]
                window.newChatStep = 2
                window.contentItem.grabToImage(r => {
                    r.saveToFile(window.shotPath.replace(".png", "-picker.png"))
                    window.composing = false
                    backend.openChatWith(p.id, p.name)
                })
                return
            }
            if (window.newChatStep === 2 && backend.messagesJson && backend.messagesJson.length > 2) {
                console.warn("OPENED", backend.currentChatId)
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            }
        }
    }

    // --group-test: pick Randy in New chat, name the group, send a first
    // message; capture the form and the new group chat.
    Timer {
        running: Qt.application.arguments.indexOf("--group-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { window.composing = true; backend.searchPeople("Randy"); step = 1; return }
            const people = backend.peopleJson ? JSON.parse(backend.peopleJson) : []
            if (step === 1 && people.length > 0) {
                const p = people.find(p => (p.mail || "").toLowerCase() === "randy@scnetsolutions.com") || people[0]
                newChat.pick(p)
                newChat.naming = true
                newChat.nameText = "OST group test"
                newChat.messageText = "OST test 27: group chat started from OST"
                step = 2
                return
            }
            if (step === 2) {
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath.replace(".png", "-form.png")); newChat.submit() })
                step = 3
                return
            }
            if (step === 3 && backend.currentChatId.indexOf("@thread") >= 0 && backend.messagesJson.indexOf("OST test 27") >= 0) {
                console.warn("GROUP", backend.currentChatId.length > 0, backend.currentChatName)
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            }
        }
    }

    // --reply-test (with --open-chat=<channel>): reply in the newest
    // post's thread, capture once the reply shows.
    Timer {
        running: Qt.application.arguments.indexOf("--reply-test") >= 0 && backend.signedIn && backend.currentChatId.endsWith("@thread.tacv2")
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0 && backend.messagesJson.length > 2) { console.warn("REPLY sent", conversation.replyForTest("OST channel test 3: reply from OST")); step = 1; return }
            if (step === 1 && backend.messagesJson.indexOf("OST channel test 3") >= 0) {
                const m = JSON.parse(backend.messagesJson).find(m => m.text.indexOf("OST channel test 3") >= 0)
                console.warn("REPLY shown, is a reply:", m.root_id !== m.id)
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            }
        }
    }

    // --mentions-test: open Quick views > Mentions, capture, open the
    // newest mention, capture.
    Timer {
        running: Qt.application.arguments.indexOf("--mentions-test") >= 0 && backend.signedIn && mentionsView.mentions.length > 0 && chatList.chats.length > 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { chatList.openMentions(); console.warn("MENTIONS", mentionsView.mentions.length, "quick view shown", chatList.hasMentions) }
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-list.png")))
            else if (step === 2) mentionsView.openMention(mentionsView.shown[0])
            else if (step === 4) { console.warn("MENTION opened", backend.currentChatId.length > 0, conversation.visible); window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() }); stop() }
            step++
        }
    }

    // --join-test: join the "OST calendar test" meeting from the calendar,
    // stay 20 s (--join-stay=<s> more), capture the call window, leave.
    // --join-view: walk Teams' View menu options in a joined meeting,
    // capturing the stage after each (with --join-test --join-stay=…).
    Timer {
        running: (Qt.application.arguments.indexOf("--join-view") >= 0 || Qt.application.arguments.indexOf("--join-pages") >= 0)
            && backend.callState === "connected" && backend.callRosterJson.length > 4
        interval: 3000; repeat: true
        property int step: 0
        // --join-pages: the gallery's pages (gallery size 4, then page 2).
        readonly property var plan: Qt.application.arguments.indexOf("--join-pages") >= 0 ? [
            ["pages-16", () => {}],
            ["pages-4", () => { callWindow.gallerySize = 4 }],
            ["pages-4-next", () => { callWindow.galleryPage = 1 }],
            ["pages-4-back", () => { callWindow.galleryPage = 0 }]
        ] : [
            ["gallery", () => {}],
            ["menu", () => callWindow.viewMenuForTest(-1)],
            ["menu-size", () => callWindow.viewMenuForTest(4)],
            ["menu-more", () => callWindow.viewMenuForTest(6)],
            ["speaker-side", () => { callWindow.closeMenusForTest(); callWindow.layout = "speaker" }],
            ["speaker-top", () => { callWindow.galleryAtTop = true }],
            ["speaker-menu", () => callWindow.viewMenuForTest(4)],
            ["gallery-me-out", () => { callWindow.closeMenusForTest(); callWindow.galleryAtTop = false; callWindow.layout = "gallery"; callWindow.meInGallery = false }],
            ["gallery-hide-me", () => { callWindow.meInGallery = true; callWindow.hideMe = true }],
            ["videos-off", () => { callWindow.hideMe = false; callWindow.incomingVideoOff = true }],
            ["videos-on", () => { callWindow.incomingVideoOff = false }],
            ["room", () => { callWindow.roomMode = true }],
            ["room-off", () => { callWindow.roomMode = false }],
            ["presenting", () => {}],
            ["popout", () => { callWindow.contentPoppedOut = callWindow.presenting }],
            ["popin", () => { callWindow.contentPoppedOut = false }],
            ["focus", () => { callWindow.layout = callWindow.presenting ? "focus" : callWindow.layout }],
            ["unfocus", () => { callWindow.layout = "gallery" }]
        ]
        // Even ticks act, odd ticks capture what that action left.
        onTriggered: {
            const i = Math.floor(step / 2)
            if (i >= plan.length) { stop(); backend.hangUp(); quitLater.start(); return }
            if (step % 2 === 0) {
                plan[i][1]()
            } else {
                const name = plan[i][0]
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-view-" + name + ".png")))
                if (name === "room" && callWindow.roomWindow)
                    callWindow.roomWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-view-room-window.png")))
                console.warn("VIEW", name, "layout", callWindow.layout, "share", backend.callShareMri, "videos", backend.callVideoJson)
            }
            step++
        }
    }
    Timer { id: quitLater; interval: 2000; onTriggered: Qt.quit() }
    // --open-channel=<id>: open that channel, capture the window after 10 s
    // and 20 s (its live roster logged), then quit.
    Timer {
        readonly property string id: (Qt.application.arguments.find(a => a.startsWith("--open-channel=")) || "").slice(15)
        running: id.length > 0 && backend.signedIn && !!backend.teamsJson
        interval: 2000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) {
                const ch = JSON.parse(backend.teamsJson).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                if (!ch) { console.warn("OPENCHANNEL not found"); return }
                backend.selectChat(ch.id, ch.name)
            } else if (step === 5 || step === 10) {
                console.warn("OPENCHANNEL live roster", backend.chatLiveRosterJson)
                window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-channel" + step + ".png")))
            } else if (step === 11 && Qt.application.arguments.indexOf("--open-channel-details") >= 0) console.warn("OPENCHANNEL details", conversation.seeDetailsForTest())
            else if (step === 14 && Qt.application.arguments.indexOf("--open-channel-details") >= 0) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-postview.png")))
            else if (step === 15 && Qt.application.arguments.indexOf("--open-channel-details") >= 0) { conversation.postViewRoot = ""; Qt.callLater(() => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-back.png")))) }
            else if (step === 17 && Qt.application.arguments.indexOf("--open-channel-details") >= 0) Qt.quit()
            else if (step === 11 && Qt.application.arguments.indexOf("--open-channel-join") < 0 && Qt.application.arguments.indexOf("--open-channel-details") < 0) Qt.quit()
            // --open-channel-join: Join the live meeting from its post (the
            // pre-join screen), join without audio, check who's in, leave.
            else if (step === 11) console.warn("OPENCHANNEL join", conversation.joinLiveMeetingForTest())
            else if (step === 13) { console.warn("OPENCHANNEL prejoin", preJoin.visible, preJoin.subject, preJoin.joinUrl.slice(0, 80)); preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-prejoin.png"))) }
            else if (step === 14) { preJoin.audio = "none"; preJoin.close(); preJoin.join(false, false, false) }
            else if (step === 20) { console.warn("OPENCHANNEL in call", backend.callState, backend.callRosterJson.slice(0, 300)); callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-call.png"))) }
            else if (step === 22) backend.hangUp()
            else if (step === 25) Qt.quit()
            step++
        }
    }
    // --open-chat=<name>: open that chat, capture it after 10 s (and 20 s),
    // then quit.
    Timer {
        readonly property string name: (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
        running: name.length > 0 && backend.signedIn && chatList.chats.some(c => c.name.indexOf(name) === 0)
        interval: 2000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { const c = chatList.chats.find(c => c.name.indexOf(name) === 0); backend.selectChat(c.id, c.name) }
            else if (step === 5 || step === 10) {
                console.warn("OPENCHAT live roster", backend.chatLiveRosterJson)
                window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-chat" + step + ".png")))
            } else if (step === 7) {
                // Switch away: the watched call is left.
                const other = chatList.chats.find(c => c.name.indexOf(name) !== 0)
                console.warn("OPENCHAT switching to", other ? other.name : "none")
                if (other) backend.selectChat(other.id, other.name)
            } else if (step === 11) Qt.quit()
            step++
        }
    }
    readonly property bool joinRaise: Qt.application.arguments.indexOf("--join-raise") >= 0
    property bool speechShot: false
    property bool deniedOne: false
    property var admitted: null
    property int retryShotAt: 0
    property bool rejoined: false
    property int admittedAt: 0
    readonly property int joinStay: Math.round(parseInt((Qt.application.arguments.find(a => a.startsWith("--join-stay=")) || "--join-stay=0").slice(12)) / 2)
    // --join-url=<link>: the test meeting's link when it isn't in the
    // calendar's loaded week.
    readonly property string joinUrl: (Qt.application.arguments.find(a => a.startsWith("--join-url=")) || "").slice(11)
    Timer {
        running: Qt.application.arguments.indexOf("--join-test") >= 0 && backend.signedIn
                 && (window.joinUrl.length > 0 || backend.calendarJson.indexOf("OST calendar test") >= 0)
        interval: 2000; repeat: true
        property int step: 0
        onTriggered: {
            if (step >= 1 && step <= 5 && Qt.application.arguments.indexOf("--lobby-screen") >= 0) {
                // --lobby-screen: the pre-join screen as Teams shows it in
                // the lobby (both texts), captured, then cancelled.
                const grab = n => preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png")))
                if (step === 1) preJoin.lobby = true
                else if (step === 2) grab("lobby")
                else if (step === 3) preJoin.presenterConnected = false
                else if (step === 4) grab("lobby-nostart")
                else Qt.quit()
            } else if (step === 0) {
                const ev = window.joinUrl.length > 0
                    ? { join_url: window.joinUrl, subject: "OST calendar test: created from OST" }
                    : JSON.parse(backend.calendarJson).find(e => e.subject.indexOf("OST calendar test") === 0 && e.join_url)
                console.warn("JOIN event found", !!ev)
                calendarView.joinMeeting(ev.join_url, ev.subject)
                // --join-prejoin-camera: turn the camera on in pre-join.
                if (Qt.application.arguments.indexOf("--join-prejoin-camera") >= 0) preJoin.cameraOn = true
            } else if (step === 1) {
                if (Qt.application.arguments.indexOf("--join-noaudio") >= 0) preJoin.audio = "room"
                preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-prejoin.png")))
            } else if (step === 2) {
                // --join-noaudio: pick Room audio (capture), then Don't use audio.
                if (Qt.application.arguments.indexOf("--join-noaudio") >= 0) preJoin.audio = "none"
                // --join-muted: switch the mic off in pre-join.
                const noAudio = preJoin.audio === "none"
                const cam = preJoin.cameraOn
                preJoin.close(); preJoin.join(!noAudio && Qt.application.arguments.indexOf("--join-muted") < 0, !noAudio, cam)
            } else if (step >= 3 && step <= 153 + window.joinStay && Qt.application.arguments.indexOf("--join-lobby-wait") >= 0) {
                // --join-lobby-wait: held in the lobby (a second account):
                // capture the waiting screen, wait to be admitted (or
                // denied), capture the meeting, then leave.
                const st = backend.callState
                if (step % 5 === 3) console.warn("JOIN lobby-wait state", st, "visible", preJoin.visible, "lobby", preJoin.lobby)
                if (st === "lobby" && step % 5 === 0) preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-inlobby.png")))
                else if (st === "connected" && !admittedAt) { admittedAt = step; console.warn("JOIN lobby-wait admitted at step", step) }
                else if (admittedAt && step === admittedAt + 3) callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-admitted.png")))
                else if ((admittedAt && step === admittedAt + 5 + window.joinStay) || step === 150 + window.joinStay) { console.warn("JOIN lobby-wait leaving", st); backend.hangUp() }
                else if (st === "ended" || st === "" || st === "idle") { if (step > 4) { console.warn("JOIN lobby-wait done", st); Qt.quit() } }
                // Denied or timed out (the retry screen), or out of time: done.
                else if (backend.callEndReason || step === 153 + window.joinStay) { console.warn("JOIN lobby-wait ending", st, backend.callEndReason); if (st === "lobby" || st === "connected") backend.hangUp(); Qt.quit() }
            } else if (step === 6) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-alone.png")))
                console.warn("JOIN lobby", backend.callLobbyJson)
            } else if (step === 8 && Qt.application.arguments.indexOf("--join-camera") >= 0) {
                // --join-camera: turn the camera on in the meeting.
                backend.toggleCamera()
            } else if (step >= 8 && step <= 24 && Qt.application.arguments.indexOf("--join-people") >= 0) {
                // --join-people: the participant menu on the first guest:
                // capture it, Pin (capture), Unpin, Spotlight (capture),
                // Stop spotlighting, Make an attendee, Make a presenter.
                const g = callWindow.others.find(p => p.guest)
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-people-" + n + ".png")))
                if (!g) { if (step === 8) console.warn("JOIN people: no guest"); }
                else if (step === 8) callWindow.side = "people"
                else if (step === 9) callWindow.participantMenuForTest(g.id)
                else if (step === 10) { shot("menu"); console.warn("JOIN people menu for", g.name) }
                else if (step === 11) { callWindow.closeMenusForTest(); callWindow.pinnedId = g.id }
                else if (step === 12) shot("pinned")
                else if (step === 13) { callWindow.pinnedId = ""; callWindow.participantAction("spotlight", g.id, g.name, "") }
                else if (step === 16) { shot("spotlight"); console.warn("JOIN people spotlight", JSON.stringify(callWindow.spotlighted.map(p => [p.name, p.spotlight]))) }
                else if (step === 17) callWindow.participantAction("unspotlight", g.id, g.name, (callWindow.roster.find(p => p.id === g.id) || {}).spotlight || "")
                else if (step === 19) { console.warn("JOIN people after unspotlight", callWindow.spotlighted.length); callWindow.participantAction("attendee", g.id, g.name, "") }
                else if (step === 21) { console.warn("JOIN people role", (callWindow.roster.find(p => p.id === g.id) || {}).role); callWindow.participantAction("presenter", g.id, g.name, "") }
                else if (step === 23) console.warn("JOIN people role back", (callWindow.roster.find(p => p.id === g.id) || {}).role)
            } else if (step >= 8 && step <= 64 && Qt.application.arguments.indexOf("--join-more") >= 0) {
                // --join-more: the People pane's More actions: capture the
                // menu, disable then allow mic for attendees, lower all
                // hands, save the attendance list, lock the meeting (held
                // ~60 s so the other side can be checked), then unlock.
                // (A capture lands a frame later: close nothing in the same
                // step.)
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-more-" + n + ".png")))
                const log = t => console.warn("JOIN more", t, JSON.stringify({ items: callWindow.moreItems.map(i => i.k), locked: backend.callMeetingLocked, restrictions: backend.callAttendeeRestrictions, hands: callWindow.hands }))
                if (step === 8) { callWindow.side = "people"; log("start") }
                else if (step === 9) callWindow.moreMenuForTest()
                else if (step === 10) shot("menu")
                else if (step === 11) { callWindow.closeMenusForTest(); console.warn("JOIN more rows", callWindow.peopleRowsForTest()) }
                else if (step === 12) { shot("pane"); callWindow.runMoreAction("restrictMic") }
                else if (step === 13) shot("micdlg")
                else if (step === 14) callWindow.confirmOpenDialogForTest()
                else if (step === 16) { log("mic restricted"); callWindow.moreMenuForTest() }
                else if (step === 17) shot("menu-restricted")
                else if (step === 18) { callWindow.closeMenusForTest(); callWindow.runMoreAction("allowMic") }
                else if (step === 19) shot("allowdlg")
                else if (step === 20) callWindow.confirmOpenDialogForTest()
                else if (step === 22) { log("mic allowed"); callWindow.runMoreAction("lowerHands") }
                else if (step === 23) shot("handsdlg")
                else if (step === 24) callWindow.confirmOpenDialogForTest()
                else if (step === 26) { log("hands lowered"); callWindow.runMoreAction("attendance") }
                else if (step === 27) callWindow.runMoreAction("lock")
                else if (step === 28) shot("lockdlg")
                else if (step === 29) callWindow.confirmOpenDialogForTest()
                else if (step === 31) { log("locked"); shot("locked") }
                // While locked: Make an attendee / Make a presenter, each
                // after Teams' "Change role?".
                else if (step === 33 || step === 38) {
                    const g = callWindow.others.find(p => p.name === "OST Guest 2")
                    if (g) callWindow.askRoleForTest(step === 33 ? "attendee" : "presenter", g.id, g.name)
                }
                else if (step === 34 || step === 39) shot(step === 34 ? "demotedlg" : "promotedlg")
                else if (step === 35 || step === 40) callWindow.confirmOpenDialogForTest()
                else if (step === 37 || step === 42) console.warn("JOIN more role", JSON.stringify(callWindow.others.map(p => [p.name, p.role])))
                else if (step === 60) callWindow.runMoreAction("unlock")
                else if (step === 61) shot("unlockdlg")
                else if (step === 62) callWindow.confirmOpenDialogForTest()
                else if (step === 64) { log("unlocked"); shot("unlocked") }
            } else if (step >= 8 && step <= 20 && Qt.application.arguments.indexOf("--join-bar") >= 0) {
                // --join-bar: the bar from Teams' layout config: wide (with
                // the Mic tooltip), then narrowed to 700 so controls move
                // into More (captured open), then back.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-bar-" + n + ".png")))
                const log = t => console.warn("JOIN bar", t, callWindow.width, JSON.stringify(callWindow.ubar))
                if (step === 8) { callWindow.side = "people"; log("wide"); callWindow.tipForTest("MicrophoneButton") }
                else if (step === 9) shot("wide")
                else if (step === 10) callWindow.width = 700
                else if (step === 12) { log("narrow"); shot("narrow"); callWindow.runControl("MoreButton") }
                else if (step === 13) shot("narrow-more")
                else if (step === 14) { callWindow.closeMenusForTest(); callWindow.width = 900 }
                else if (step === 16) { log("900"); shot("900") }
                else if (step === 17) callWindow.width = 1280
                else if (step === 19) { log("restored"); shot("restored") }
            } else if (step >= 8 && step <= 30 && Qt.application.arguments.indexOf("--join-keys") >= 0) {
                // --join-keys: log the state each step while keys are sent
                // from outside (Teams' call shortcuts).
                if (step === 8) { callWindow.raise(); callWindow.requestActivate() }
                console.warn("JOIN keys", step, JSON.stringify({ muted: backend.callMuted, hand: callWindow.handRaised, camera: backend.callCameraOn, state: backend.callState, talk: callWindow.talkHeld }))
            } else if (step >= 8 && step <= 24 && Qt.application.arguments.indexOf("--join-video-flyout") >= 0) {
                // --join-video-flyout: Camera ▾ with the preview (captured),
                // then the camera on and switched to the second camera and
                // back (captured), then off.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-video-" + n + ".png")))
                if (step === 8) callWindow.videoOptionsForTest()
                else if (step === 10) { shot("flyout"); console.warn("JOIN video devices", backend.videoDevices()) }
                else if (step === 11) callWindow.closeMenusForTest()
                else if (step === 12) backend.toggleCamera()
                else if (step === 15) { shot("on-a"); console.warn("JOIN video camera on", backend.callCameraOn) }
                else if (step === 16) backend.setCameraDevice("/dev/video21")
                else if (step === 19) shot("on-b")
                else if (step === 20) backend.setCameraDevice("/dev/video20")
                else if (step === 22) { shot("on-a2"); backend.toggleCamera() }
                else if (step === 23) callWindow.audioOptionsForTest()
                else if (step === 24) shot("audio-flyout")
            } else if (step >= 9 && step <= 60 && Qt.application.arguments.indexOf("--join-record") >= 0) {
                // --join-record: Record and transcribe from the More menu:
                // start transcription (dialog), stop it, start recording
                // (dialog), stop it; the menu and dialogs captured, the
                // recorder's state logged as the roster reports it.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rec-" + n + ".png")))
                const st = () => console.warn("JOIN rec", step, "state", JSON.stringify(backend.callRecordingState), backend.callRecordingTip)
                const plan = {
                    9: () => callWindow.recordMenuForTest(), 10: () => grab("menu-idle"), 11: () => callWindow.closeMoreForTest(),
                    12: () => callWindow.recordControl("TranscriptButton"), 13: () => grab("dialog-transcription"),
                    14: () => console.warn("JOIN rec confirm", callWindow.confirmRecordDialogForTest()),
                    22: () => { st(); callWindow.recordMenuForTest() }, 23: () => grab("menu-transcribing"), 24: () => callWindow.closeMoreForTest(),
                    25: () => callWindow.recordControl("RecordingButton"), 26: () => grab("dialog-recording-only"), 27: () => callWindow.cancelRecordDialogForTest(),
                    28: () => callWindow.recordControl("TranscriptButton"), 29: () => grab("dialog-stop-transcription"),
                    30: () => console.warn("JOIN rec confirm", callWindow.confirmRecordDialogForTest()),
                    38: () => { st(); callWindow.recordControl("RecordingButton") }, 39: () => grab("dialog-recording"),
                    40: () => console.warn("JOIN rec confirm", callWindow.confirmRecordDialogForTest()),
                    50: () => { st(); callWindow.recordMenuForTest() }, 51: () => grab("menu-recording"), 52: () => callWindow.closeMoreForTest(),
                    53: () => callWindow.recordControl("RecordingButton"), 54: () => grab("dialog-stop-recording"),
                    55: () => console.warn("JOIN rec confirm", callWindow.confirmRecordDialogForTest()),
                    60: () => st()
                }
                if (plan[step]) plan[step]()
                else if (step % 4 === 0) st()
            } else if (step >= 9 && step <= Math.min(46, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-captions") >= 0) {
                // --join-captions: Language and speech ▸ Show live captions,
                // the empty window, live captions (a guest speaks from
                // outside), the settings menu, Caption styles at Large,
                // then captions off.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-cc-" + n + ".png")))
                const st = () => console.warn("JOIN captions", step, "on", backend.callCaptionsOn, "n", JSON.parse(backend.callCaptionsJson || "[]").length,
                                               "acc", backend.callAccessibilityJson.slice(0, 120))
                const plan = {
                    9: () => callWindow.moreSubmenuForTest("LanguageSpeechMenuControl"), 10: () => grab("menu-off"), 11: () => callWindow.closeMoreForTest(),
                    12: () => callWindow.recordControl("ClosedCaptionsButton"),
                    14: () => { st(); grab("empty") },
                    28: () => { st(); grab("live") },
                    30: () => callWindow.captionSettingsForTest(), 31: () => grab("settings"), 32: () => callWindow.closeCaptionSettingsForTest(),
                    33: () => callWindow.side = "captionStyles",
                    34: () => callWindow.saveCaptionStyles(Object.assign({}, callWindow.captionStyles, { fontSize: "Large" })),
                    35: () => grab("large"),
                    36: () => callWindow.saveCaptionStyles(Object.assign({}, callWindow.captionStyles, { fontSize: "Medium" })),
                    37: () => { callWindow.side = ""; callWindow.moreSubmenuForTest("LanguageSpeechMenuControl") }, 38: () => grab("menu-on"), 39: () => callWindow.closeMoreForTest(),
                    40: () => callWindow.recordControl("ClosedCaptionsButton"),
                    44: () => { st(); grab("off") }
                }
                if (plan[step]) plan[step]()
                else if (step % 3 === 0) st()
            } else if (step >= 9 && step <= Math.min(50, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-transcript-start") >= 0) {
                // --join-transcript-start: stop a running transcript, start
                // one (Teams then opens the Transcript pane for you), then
                // stop it again; the pane captured once it opened.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-ts-" + n + ".png")))
                const st = () => console.warn("JOIN tstart", step, "state", backend.callRecordingState, "side", JSON.stringify(callWindow.side))
                const plan = {
                    9: () => { st(); if (callWindow.transcribing) { callWindow.recordControl("TranscriptButton"); callWindow.confirmRecordDialogForTest() } },
                    18: () => { st(); callWindow.side = ""; callWindow.recordControl("TranscriptButton") },
                    19: () => console.warn("JOIN tstart confirm", callWindow.confirmRecordDialogForTest()),
                    30: () => { st(); grab("opened") },
                    34: () => { callWindow.recordControl("TranscriptButton"); console.warn("JOIN tstart stop", callWindow.confirmRecordDialogForTest()) },
                    44: () => { st(); grab("stopped") }
                }
                if (plan[step]) plan[step]()
                else if (step % 3 === 0) st()
            } else if (step >= 9 && step <= Math.min(40, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-transcript") >= 0) {
                // --join-transcript: More ▸ Record and transcribe ▸ Show
                // transcript, the pane captured with the stored history,
                // then again after live speech, scrolled up (Go to current),
                // and the menu with Hide transcript checked.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-tr-" + n + ".png")))
                const rows = () => { const t = backend.callTranscriptJson ? JSON.parse(backend.callTranscriptJson) : []
                    console.warn("JOIN transcript", step, "rows", t.length, "speech", t.filter(e => e.kind === "speech").length,
                                 "last", JSON.stringify(t.slice(-2))) }
                const plan = {
                    9: () => callWindow.recordMenuForTest(), 10: () => grab("menu-closed"), 11: () => callWindow.closeMoreForTest(),
                    12: () => callWindow.recordControl("TranscriptPanelButton"),
                    16: () => { rows(); grab("history") },
                    30: () => { rows(); grab("live") },
                    32: () => callWindow.transcriptScrollTopForTest(), 33: () => grab("scrolled"),
                    35: () => callWindow.recordMenuForTest(), 36: () => grab("menu-open"), 37: () => callWindow.closeMoreForTest(),
                    40: () => rows()
                }
                if (plan[step]) plan[step]()
                else if (step % 3 === 0) rows()
            } else if (step >= 9 && step <= Math.min(26, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-captions-popout") >= 0) {
                // --join-captions-popout: captions on, popped out into their
                // own window (captured), popped back in, off.
                const pw = callWindow.captionsPopoutForTest()
                const plan = {
                    9: () => callWindow.recordControl("ClosedCaptionsButton"),
                    13: () => callWindow.captionsPoppedOut = true,
                    17: () => console.warn("JOIN popout", pw.visible, pw.width, pw.height, pw.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-popout.png")))),
                    18: () => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-popout-main.png"))),
                    20: () => pw.popIn(),
                    22: () => { console.warn("JOIN popped in", pw.visible, callWindow.captionsPoppedOut); callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-popin.png"))) },
                    24: () => callWindow.recordControl("ClosedCaptionsButton")
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(40, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-muted-speech") >= 0) {
                // --join-muted-speech: joined muted while speech plays into
                // the mic: Teams' "Your microphone is muted" shows; Close
                // hides it until the next time.
                console.warn("JOIN speech", step, "muted", callWindow.muted, "speaking", backend.callSpeakingWhileMuted,
                             "shown", callWindow.speakingNoticeShown)
                if (callWindow.speakingNoticeShown && !window.speechShot) {
                    window.speechShot = true
                    callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-speech.png")))
                }
                if (step === 24 && callWindow.speakingNoticeShown) callWindow.speakingNoticeClosed = true
                // Accessibility ▸ Muted notification off, then on again.
                if (step === 28) callWindow.accessibilityPaneForTest().mutedNoticeToggled(false)
                if (step === 29 || step === 33) console.warn("JOIN speech setting", backend.setting("showMutedNotice"), callWindow.showMutedNotice)
                if (step === 32) callWindow.accessibilityPaneForTest().mutedNoticeToggled(true)
            } else if (step >= 9 && step <= Math.min(60, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-rtt") >= 0) {
                // --join-rtt: Language and speech ▸ Turn on RTT for this
                // call, its dialog, the card, typing (a line ended by Enter,
                // one by 3 s idle), the "…" menu and the pop-out; someone
                // else's RTT is typed in Teams meanwhile.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rtt-" + n + ".png")))
                const box = () => callWindow.captionsWindowForTest().rttBoxForTest
                const rows = () => console.warn("JOIN rtt", step, "on", backend.callRttOn, "initiator", backend.callRttInitiator,
                                                "rows", backend.callCaptionsJson)
                const pw = callWindow.captionsPopoutForTest()
                const plan = {
                    9: () => callWindow.moreSubmenuForTest("LanguageSpeechMenuControl"), 10: () => grab("menu"),
                    11: () => { callWindow.closeMoreForTest(); callWindow.recordControl("RealTimeTextButton") },
                    12: () => grab("dialog"),
                    13: () => { const d = callWindow.rttAskForTest(); d.close(); d.confirmed() },
                    15: () => { grab("card"); rows() },
                    16: () => box().typeForTest("Hello from OST"),
                    17: () => { grab("typing"); rows() },
                    18: () => box().enterForTest(),
                    19: () => { grab("ended"); rows() },
                    20: () => box().typeForTest("Idle line"),
                    23: () => { grab("idle"); rows() },
                    24: () => callWindow.captionSettingsForTest(), 25: () => grab("overflow"),
                    26: () => callWindow.closeCaptionSettingsForTest(),
                    27: () => { box().typeForTest("   "); box().enterForTest() },
                    28: () => { grab("spaces"); console.warn("JOIN rtt bar", box().barForTest()) },
                    29: () => callWindow.moreSubmenuForTest("LanguageSpeechMenuControl"), 30: () => grab("menu-on"),
                    31: () => callWindow.closeMoreForTest(),
                    32: () => callWindow.captionsPoppedOut = true,
                    34: () => console.warn("JOIN rtt popout", pw.visible, pw.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-rtt-popout.png")))),
                    36: () => pw.popIn(),
                    // Kept in the box while Teams (the same account) types.
                    37: () => { box().typeForTest("Will be cleared"); box().holdForTest() },
                    60: () => rows()
                }
                if (plan[step]) plan[step]()
                else if (step > 36 && step % 4 === 0) {
                    rows(); grab("live-" + step)
                    console.warn("JOIN rtt box", JSON.stringify(box().textForTest()), "bar", box().barForTest())
                }
            } else if (step >= 9 && step <= Math.min(52, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-timer-remote") >= 0) {
                // --join-timer-remote: watch while Teams (winpc) resumes and
                // pauses it, then a 10 s timer runs out here: "Time's up!",
                // the red count, Cancel timer for everyone.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-timer-" + n + ".png")))
                const ts = callWindow.timerStripForTest()
                console.warn("JOIN timerr", step, "visible", ts.visible, "state", ts.timerState, "display", ts.display, "over", ts.overTime)
                const plan = {
                    9: () => { if (!callWindow.timerVisible) callWindow.toggleTimer() },
                    14: () => grab("remote-a"), 20: () => grab("remote-b"),
                    24: () => ts.action("startWith", 10000),
                    32: () => grab("overtime"),
                    34: () => ts.action("cancelOverTime", 0), 37: () => grab("after"),
                    38: () => ts.action("startWith", 90000), 41: () => ts.action("pause", 0)
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(52, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-timer") >= 0) {
                // --join-timer: the meeting timer as received, its popover,
                // then resume, pause, +1 min, cancel, a new 1:30 timer and
                // pause, each sent to Teams (winpc shows the same).
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-timer-" + n + ".png")))
                const ts = callWindow.timerStripForTest()
                const log = n => console.warn("JOIN timer", step, n, "visible", ts.visible, "state", ts.timerState, "display", ts.display, "seq", callWindow.timerData ? callWindow.timerData.sequence : -1)
                const act = (n, a) => { log("act " + n); ts.action(n, a || 0) }
                const plan = {
                    9: () => { if (!callWindow.timerVisible) callWindow.toggleTimer(); log("start") }, 10: () => grab("strip"),
                    11: () => ts.openControls(), 12: () => grab("popover"), 13: () => ts.popupForTest.close(),
                    14: () => act("resume"), 17: () => { log("resumed"); grab("running") },
                    19: () => act("pause"), 22: () => { log("paused"); grab("paused") },
                    24: () => act("add", 1), 27: () => { log("added"); grab("added") },
                    29: () => act("cancel"), 32: () => { log("cancelled"); grab("cancelled") },
                    33: () => ts.openControls(), 34: () => grab("setup"), 35: () => ts.popupForTest.close(),
                    36: () => act("startWith", 90000), 39: () => { log("new"); grab("new") },
                    42: () => act("pause"), 45: () => log("end")
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(70, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-call-health-share") >= 0) {
                // --join-call-health-share: Call health open, then share
                // (the desktop's picker asks what: the kitty OST-share-test
                // window), the Screen Sharing card and page, stop sharing.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-health-" + n + ".png")))
                const pane = callWindow.callHealthPaneForTest()
                const log = n => console.warn("JOIN health", step, n, pane.page, "sharing", backend.callSharing, backend.callHealthJson)
                const plan = {
                    9: () => callWindow.recordControl("CallHealth"),
                    10: () => backend.toggleShare(),
                    // The picker waits for a person: a minute to choose.
                    55: () => { log("root-share"); grab("root-share") },
                    56: () => pane.pageForTest("ScreenSharing"), 57: () => { log("share"); grab("share-on") },
                    58: () => { if (backend.callSharing) backend.toggleShare() },
                    61: () => { pane.pageForTest(""); log("off"); grab("share-off") }
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(60, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-call-health") >= 0) {
                // --join-call-health: More ▸ Settings ▸ Call health muted,
                // then the camera on (the v4l2loopback test camera), each
                // detail page, the mic on (Guest audio is what's heard)
                // and off again, camera off.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-health-" + n + ".png")))
                const pane = callWindow.callHealthPaneForTest()
                const log = n => console.warn("JOIN health", step, n, pane.page, backend.callHealthJson)
                const plan = {
                    9: () => callWindow.moreSubmenuForTest("SettingsMenuControl"), 10: () => grab("menu"),
                    11: () => { callWindow.closeMenusForTest(); callWindow.recordControl("CallHealth") },
                    13: () => { log("root"); grab("root") },
                    14: () => { backend.setCameraDevice("/dev/video20"); backend.toggleCamera() },
                    26: () => { log("camera"); grab("root-camera") },
                    27: () => pane.pageForTest("Network"), 28: () => { log("net"); grab("network") },
                    29: () => pane.pageForTest("Audio"), 30: () => grab("audio"),
                    31: () => pane.pageForTest("Video"), 32: () => { log("video"); grab("video") },
                    33: () => pane.pageForTest("ScreenSharing"), 34: () => grab("share"),
                    35: () => { pane.pageForTest(""); backend.toggleMute() },
                    50: () => { log("mic"); grab("root-mic") },
                    51: () => pane.pageForTest("Audio"), 52: () => { log("audio-mic"); grab("audio-mic") },
                    53: () => backend.toggleMute(),
                    54: () => { backend.toggleCamera(); pane.pageForTest("") },
                    56: () => { log("off"); grab("root-off") }
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(18, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-report-person") >= 0) {
                // --join-report-person: a guest's ··· menu, Report, Teams'
                // "Report this person" dialog, then Cancel. Never sends.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-reportp-" + n + ".png")))
                const g = callWindow.others.find(p => p.guest)
                const d = callWindow.meetingReportForTest()
                const plan = {
                    9: () => { callWindow.side = "people" },
                    10: () => { if (g) callWindow.participantMenuForTest(g.id); else console.warn("JOIN reportp: no guest") },
                    11: () => grab("menu"),
                    12: () => { callWindow.closeMenusForTest(); if (g) callWindow.openPersonReport(g.id, g.name) },
                    13: () => grab("dialog"),
                    14: () => { console.warn("JOIN reportp", d.personMode, JSON.stringify(d.person), d.width, d.height, JSON.stringify(d.chosen)); d.close() }
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(18, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-report") >= 0) {
                // --join-report: More ▸ Report a concern, its picker, a
                // participant chosen, then Cancel. Never sends a report.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-report-" + n + ".png")))
                const d = callWindow.meetingReportForTest()
                const plan = {
                    9: () => callWindow.runControl("ReportMeetingButton"), 11: () => grab("dialog"),
                    12: () => d.openListForTest(), 13: () => grab("list"),
                    14: () => d.chooseFirstForTest(), 15: () => grab("chosen"),
                    16: () => { console.warn("JOIN report people", JSON.stringify(d.people), "meeting", JSON.stringify(d.meeting)); d.close() }
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(30, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-help") >= 0) {
                // --join-help: More ▸ Help: the window, its app header and
                // menu, Settings and more, pinned on top and back; then the
                // menu's About and Share app (in the Help window).
                const hw = callWindow.helpWindowForTest()
                const grab = n => hw.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-help-" + n + ".png")))
                const plan = {
                    9: () => callWindow.runControl("MeetingHelpButton"),
                    14: () => grab("window"),
                    15: () => hw.appForTest.moreMenuForTest(), 16: () => grab("appmenu"),
                    17: () => { hw.appForTest.moreMenuForTest(); hw.titleBarForTest.settingsMenuForTest() }, 18: () => grab("settings"),
                    19: () => { hw.titleBarForTest.togglePin(); console.warn("JOIN help pinned", hw.pinned, (hw.flags & Qt.WindowStaysOnTopHint) !== 0) },
                    20: () => { hw.titleBarForTest.togglePin(); console.warn("JOIN help pinned", hw.pinned, hw.appForTest.tileUrl.slice(0, 80)) },
                    21: () => hw.appForTest.aboutForTest().show(hw.appForTest.appId), 24: () => grab("about"),
                    25: () => { hw.appForTest.aboutForTest().close(); hw.appForTest.shareFormForTest().start(hw.appForTest.appId) }, 27: () => grab("share"),
                    28: () => { hw.appForTest.shareFormForTest().close(); hw.close() }
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= Math.min(27, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-accessibility") >= 0) {
                // --join-accessibility: More ▸ Settings ▸, then the
                // Accessibility pane.
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-acc-" + n + ".png")))
                const plan = {
                    9: () => callWindow.moreSubmenuForTest("SettingsMenuControl"), 10: () => grab("menu"), 11: () => callWindow.closeMoreForTest(),
                    12: () => callWindow.recordControl("AccessibilitySettingsButton"), 14: () => grab("pane"),
                    15: () => { callWindow.recordControl("MuteNotificationsButton"); console.warn("JOIN notifications muted", backend.callNotificationsMuted) },
                    16: () => callWindow.moreSubmenuForTest("SettingsMenuControl"), 17: () => grab("menu-muted"), 18: () => callWindow.closeMoreForTest(),
                    19: () => { callWindow.recordControl("MuteNotificationsButton"); console.warn("JOIN notifications muted", backend.callNotificationsMuted) },
                    20: () => callWindow.runControl("MeetingHelpButton"),
                    21: () => console.warn("JOIN help", callWindow.helpWindowForTest().visible, callWindow.helpWindowForTest().width, callWindow.helpUrl("helpappmeetings").slice(0, 120)),
                    26: () => console.warn("JOIN help grab", callWindow.helpWindowForTest().contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-acc-help.png"))), callWindow.helpWindowForTest().visible),
                    27: () => callWindow.helpWindowForTest().close()
                }
                if (plan[step]) plan[step]()
            } else if (step >= 9 && step <= 16 && Qt.application.arguments.indexOf("--join-audio-pane") >= 0) {
                // --join-audio-pane: More > Audio settings, captured at the
                // top and the end; then music mode on (captured, and the
                // encoder retunes), then off again.
                const pane = callWindow.audioPaneForTest()
                const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-audio-" + n + ".png")))
                if (step === 9) callWindow.runControl("AudioSettingsButton")
                else if (step === 10) grab("top")
                else if (step === 11) pane.scrollToEndForTest()
                else if (step === 12) grab("end")
                else if (step === 13) { pane.setMusic(true); console.warn("JOIN audio music on, ns", pane.noiseSuppression) }
                else if (step === 14) { pane.scrollToEndForTest(); grab("music") }
                else if (step === 15) { pane.setMusic(false); console.warn("JOIN audio music off, ns", pane.noiseSuppression) }
                else grab("after")
            } else if (step === 9 && Qt.application.arguments.indexOf("--join-info") >= 0) {
                // --join-info: open More > Meeting info, capture it (step
                // 11), press Copy join info and capture again (step 12).
                callWindow.runControl("MeetingInfoButton")
            } else if (step === 11 && Qt.application.arguments.indexOf("--join-info") >= 0) {
                console.warn("JOIN info", backend.callMeetingInfoJson.slice(0, 400))
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-info.png")))
                backend.copyMeetingJoinInfo()
            } else if (step >= 8 && step < 12 + window.joinStay && Qt.application.arguments.indexOf("--join-ai") >= 0) {
                const st = [backend.callAiIndicator, backend.callAiAvailable, backend.callAiOn, backend.callAiFacilitator, backend.callRecordingState, backend.callRecordingTip].join(",")
                if (st !== window.aiLogged) {
                    console.warn("JOIN ai", step, "indicator,available,on,facilitator,recording,tip =", st)
                    window.aiLogged = st
                    aiShot.tag = (backend.callAiOn ? "on" : "off") + step
                    aiShot.phase = 0
                    aiShot.restart()
                }
            } else if (step >= 8 && step <= 60 && Qt.application.arguments.indexOf("--join-nsi") >= 0) {
                // --join-nsi: log the network strength each step while loss
                // is applied from outside; capture the bars and popover once
                // it isn't Good.
                console.warn("JOIN nsi", step, backend.callNetworkStrength, callWindow.nsiShown)
                if (callWindow.nsiShown && !callWindow.nsiCaptured) {
                    callWindow.nsiCaptured = true
                    callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-nsi-tile.png")))
                    callWindow.networkPopoverForTest()
                    nsiPopShot.start()
                }
            } else if (step === 9 && Qt.application.arguments.indexOf("--join-compact") >= 0) {
                // --join-compact: minimise the meeting window, capture the
                // compact view (step 12), then restore (step 14).
                callWindow.minimizeForTest()
            } else if (step === 12 && Qt.application.arguments.indexOf("--join-compact") >= 0) {
                console.warn("JOIN compact visibility", callWindow.visibility, "shown", callWindow.compactViewForTest().visible)
                callWindow.compactViewForTest().contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-compact.png")))
            } else if (step === 14 && Qt.application.arguments.indexOf("--join-compact") >= 0) {
                callWindow.compactViewForTest().restore()
            } else if (step === 15 && Qt.application.arguments.indexOf("--join-compact") >= 0) {
                console.warn("JOIN restored visibility", callWindow.visibility, "compact", callWindow.compactViewForTest().visible)
            } else if (step === 10 && Qt.application.arguments.indexOf("--join-leave-all") >= 0) {
                // --join-leave-all: open Leave's menu, capture it, then
                // (step 12) Leave on all my devices.
                callWindow.leaveMenuForTest()
            } else if (step === 11 && Qt.application.arguments.indexOf("--join-leave-all") >= 0) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-leavemenu.png")))
                console.warn("JOIN leave items", JSON.stringify(callWindow.leaveItems))
            } else if (step === 12 && Qt.application.arguments.indexOf("--join-leave-all") >= 0) {
                backend.leaveOnAllDevices()
            } else if ((step === 10 || step === 16) && Qt.application.arguments.indexOf("--join-mute-cycle") >= 0) {
                // --join-mute-cycle: unmute, then (step 16) mute again.
                console.warn("JOIN toggle mute, muted", backend.callMuted)
                backend.toggleMute()
            } else if (step === 16 && Qt.application.arguments.indexOf("--join-camera-off") >= 0) {
                // --join-camera-off: and off again.
                console.warn("JOIN camera off")
                backend.toggleCamera()
            } else if (step === 7 && Qt.application.arguments.indexOf("--join-admit") >= 0) {
                // --join-admit: admit the first person waiting in the lobby.
                const lobby = JSON.parse(backend.callLobbyJson || "[]")
                console.warn("JOIN admitting", JSON.stringify(lobby))
                // --join-admit-notbot: as if "This isn't a bot" was ticked.
                if (lobby.length) backend.admitFromLobby(lobby[0].id, lobby[0].name, Qt.application.arguments.indexOf("--join-admit-notbot") >= 0)
            } else if (step === 10 && Qt.application.arguments.indexOf("--join-react") >= 0) {
                // --join-react: send a Like, capture once it's back (step 12).
                backend.sendReaction("like")
            } else if (step === 12 && Qt.application.arguments.indexOf("--join-react") >= 0) {
                console.warn("JOIN reactions", JSON.stringify(callWindow.reactions))
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-react.png")))
            } else if (step === 7 && Qt.application.arguments.indexOf("--join-mute-all") >= 0) {
                // --join-mute-all: admit each guest waiting (Admit all leaves
                // suspected ones), then (step 10) Mute all.
                JSON.parse(backend.callLobbyJson || "[]").forEach(p => backend.admitFromLobby(p.id, p.name, false))
            } else if (step === 10 && Qt.application.arguments.indexOf("--join-mute-all") >= 0) {
                console.warn("JOIN before mute all", backend.callRosterJson, "can", callWindow.canMuteAll)
                callWindow.side = "people"
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-muteall-before.png")))
                backend.muteAll()
            } else if (step === 11 && Qt.application.arguments.indexOf("--join-mute-all") >= 0) {
                console.warn("JOIN after mute all", backend.callRosterJson, "can", callWindow.canMuteAll)
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-muteall-after.png")))
            } else if (step >= 7 && step <= 7 + window.joinStay && Qt.application.arguments.indexOf("--join-deny-wait") >= 0) {
                // --join-deny-wait (with --join-stay): deny the first person
                // who waits in the lobby, then stay until the time is up.
                const lobby = JSON.parse(backend.callLobbyJson || "[]")
                if (lobby.length && !window.deniedOne) { window.deniedOne = true; console.warn("JOIN deny-wait denying", JSON.stringify(lobby[0])); backend.denyFromLobby(lobby[0].id, lobby[0].name) }
                else if (step === 7 + window.joinStay) { console.warn("JOIN deny-wait leaving"); backend.hangUp() }
            } else if (step >= 8 && step <= 40 && Qt.application.arguments.indexOf("--join-controls") >= 0) {
                // --join-controls: Teams' Controls menu and Meeting options
                // dialog (organizers): capture the menu, the dialog at three
                // sections; with --join-controls-toggle, turn "Enable lobby"
                // off and back on through the menu, logging the options.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-controls-" + n + ".png")))
                const opt = n => { const o = callWindow.controlsOptions[n]; return o ? o.currentValue : "?" }
                if (step === 8) callWindow.runControl("OrganizerControlButton")
                else if (step === 10) { shot("menu"); console.warn("JOIN controls items", JSON.stringify(callWindow.controlsItems.map(i => [i.label || i.heading || "-", i.checked, i.enabled]))) }
                else if (step === 11) { callWindow.closeMenusForTest(); callWindow.openMeetingOptions() }
                else if (step === 13) shot("dialog-access")
                else if (step === 14) callWindow.optionsDialogForTest().scrollTo(3)
                else if (step === 15) shot("dialog-participation")
                else if (step === 16) callWindow.optionsDialogForTest().scrollTo(5)
                else if (step === 17) shot("dialog-copilot")
                else if (step === 18) callWindow.optionsDialogForTest().close()
                // --join-controls-people: the co-organizer picker: capture
                // Roles, remove the co-organizer and Apply, pick them again
                // from the list and Apply, logging what's saved each time.
                else if (Qt.application.arguments.indexOf("--join-controls-people") >= 0 && step >= 19 && step <= 36) {
                    const dlg = callWindow.optionsDialogForTest()
                    const picker = () => dlg.pickerForTest("CoOrganizers")
                    const saved = () => JSON.stringify((callWindow.controlsOptions.CoOrganizers || {}).selectedPeople)
                    if (step === 19) { callWindow.openMeetingOptions() }
                    else if (step === 21) { dlg.scrollTo(1) }
                    else if (step === 22) { shot("roles"); console.warn("JOIN people saved", saved(), "invitees", JSON.stringify(callWindow.controlsPeople.invitees), "names", JSON.stringify(callWindow.controlsPeople.people), "candidates", JSON.stringify(dlg.candidates("CoOrganizers"))) }
                    else if (step === 23) { picker().unpick(0) }
                    else if (step === 24) { picker().openForTest(); }
                    else if (step === 25) { shot("roles-removed"); console.warn("JOIN people dirty", dlg.dirty, "note", dlg.planningNote) }
                    else if (step === 26) { dlg.tryApply() }
                    else if (step === 29) { console.warn("JOIN people after remove", saved()); picker().typeForTest("OST") }
                    else if (step === 30) { shot("roles-search"); const m = picker().matches; console.warn("JOIN people matches", JSON.stringify(m)); if (m.length) picker().pick(m[0]) }
                    else if (step === 31) { shot("roles-picked") }
                    else if (step === 32) { dlg.tryApply() }
                    else if (step === 35) { console.warn("JOIN people after re-add", saved()); shot("roles-saved") }
                    else if (step === 36) { dlg.close() }
                }
                else if (step === 20 && Qt.application.arguments.indexOf("--join-controls-toggle") >= 0) { console.warn("JOIN controls lobby before", opt("AutoAdmittedUsers")); callWindow.pickControl("AutoAdmittedUsers") }
                else if (step === 24) console.warn("JOIN controls lobby after toggle", opt("AutoAdmittedUsers"))
                else if (step === 25 && Qt.application.arguments.indexOf("--join-controls-toggle") >= 0) callWindow.pickControl("AutoAdmittedUsers")
                else if (step === 29) console.warn("JOIN controls lobby after second toggle", opt("AutoAdmittedUsers"))
                else if (step === 40) { console.warn("JOIN controls leaving"); backend.hangUp() }
            } else if (step === 42 && Qt.application.arguments.indexOf("--join-controls") >= 0) {
                Qt.quit()
            } else if (step >= 3 && step <= 3 + window.joinStay && Qt.application.arguments.indexOf("--join-retry-watch") >= 0) {
                // --join-retry-watch (with --join-stay): wait while someone
                // in Teams admits, denies or removes us; capture Teams'
                // retry screen when the service ends the call for a reason,
                // then (--join-retry-rejoin) press Rejoin once.
                const reason = backend.callEndReason
                if (step % 5 === 3) console.warn("JOIN retry-watch", backend.callState, reason)
                if (reason && !window.retryShotAt) { window.retryShotAt = step; console.warn("JOIN retry-watch reason", reason, "prejoin", preJoin.retryReason, "call", callWindow.retryReason) }
                else if (window.retryShotAt && step === window.retryShotAt + 2) {
                    const w = preJoin.retryReason ? preJoin : callWindow
                    w.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-retry-" + reason + ".png")))
                } else if (window.retryShotAt && step === window.retryShotAt + 4 && Qt.application.arguments.indexOf("--join-retry-rejoin") >= 0 && !window.rejoined) {
                    window.rejoined = true; window.retryShotAt = 0
                    console.warn("JOIN retry-watch rejoining")
                    if (preJoin.retryReason) { preJoin.retryReason = ""; preJoin.rejoin() } else { callWindow.retryReason = ""; callWindow.rejoin() }
                } else if (step === 3 + window.joinStay) { console.warn("JOIN retry-watch leaving"); backend.hangUp(); Qt.callLater(Qt.quit) }
            } else if (step >= 7 && step <= 7 + window.joinStay && Qt.application.arguments.indexOf("--join-admit-remove") >= 0) {
                // --join-admit-remove (with --join-stay): admit the first
                // person who waits in the lobby, remove them from the
                // meeting 16 s later, then stay until the time is up.
                const lobby = JSON.parse(backend.callLobbyJson || "[]")
                if (lobby.length && !window.admitted) { window.admitted = { id: lobby[0].id, name: lobby[0].name, at: step }; console.warn("JOIN admit-remove admitting", lobby[0].name); backend.admitFromLobby(lobby[0].id, lobby[0].name, false) }
                else if (window.admitted && step === window.admitted.at + 8) { console.warn("JOIN admit-remove removing", window.admitted.name); backend.denyFromLobby(window.admitted.id, window.admitted.name) }
                else if (step === 7 + window.joinStay) { console.warn("JOIN admit-remove leaving"); backend.hangUp() }
            } else if (step === 8 + window.joinStay && (Qt.application.arguments.indexOf("--join-admit-remove") >= 0 || Qt.application.arguments.indexOf("--join-deny-wait") >= 0)) {
                Qt.quit()
            } else if (step === 8 + window.joinStay && Qt.application.arguments.indexOf("--join-deny-wait") >= 0) {
                Qt.quit()
            } else if (step === 7 && Qt.application.arguments.indexOf("--join-deny") >= 0) {
                // --join-deny: deny the last person waiting in the lobby.
                const lobby = JSON.parse(backend.callLobbyJson || "[]")
                console.warn("JOIN denying", JSON.stringify(lobby))
                if (lobby.length) backend.denyFromLobby(lobby[lobby.length - 1].id, lobby[lobby.length - 1].name)
            } else if (window.joinRaise && step === 8) {
                // --join-raise: raise your hand, then lower it.
                backend.toggleHand()
            } else if (window.joinRaise && step === 11) {
                console.warn("JOIN hand raised", backend.callHandRaised, "hands", callWindow.hands.length, "status", backend.statusText)
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-raised.png")))
            } else if (window.joinRaise && step === 16) {
                backend.toggleHand()
            } else if (window.joinRaise && step === 19) {
                console.warn("JOIN hand lowered", !backend.callHandRaised, "hands", callWindow.hands.length, "status", backend.statusText)
            } else if (step === 12 + window.joinStay) {
                console.warn("JOIN state", backend.callState, "audio", backend.callHasAudio, "muted", backend.callMuted, "window muted", callWindow.muted, "hasAudio", callWindow.hasAudio, "roster", backend.callRosterJson.length, "status", backend.statusText)
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-meeting.png")))
                callWindow.side = "people"
            } else if (step === 13 + window.joinStay) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-people.png")))
                // --join-end: open Leave's menu (captured next), then End meeting.
                if (Qt.application.arguments.indexOf("--join-end") >= 0) callWindow.leaveMenuForTest()
                // --join-invite: open Share invite (captured next).
                if (Qt.application.arguments.indexOf("--join-invite") >= 0) callWindow.inviteForTest()
                // --join-audio-options: open the Mic options (captured next).
                if (Qt.application.arguments.indexOf("--join-audio-options") >= 0) callWindow.audioOptionsForTest()
            } else if (step === 14 + window.joinStay && Qt.application.arguments.indexOf("--join-invite") >= 0) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-invite.png")))
            } else if (step === 15 + window.joinStay && Qt.application.arguments.indexOf("--join-invite") >= 0) {
                backend.hangUp()
            } else if (step === 14 + window.joinStay && Qt.application.arguments.indexOf("--join-audio-options") >= 0) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-audio.png")))
            } else if (step === 15 + window.joinStay && Qt.application.arguments.indexOf("--join-audio-options") >= 0) {
                backend.hangUp()
            } else if (step === 14 + window.joinStay) {
                if (Qt.application.arguments.indexOf("--join-end") >= 0) {
                    callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-leavemenu.png")))
                    backend.endMeeting()
                } else backend.hangUp()
            }
            else if (step === 16 + window.joinStay) { Qt.quit() }
            step++
        }
    }

    // --event-card-test: capture the test meeting's card; then create
    // "OST event test", edit it (title and start) and delete it.
    Timer {
        running: Qt.application.arguments.indexOf("--event-card-test") >= 0 && backend.signedIn && backend.calendarJson.indexOf("OST calendar test") >= 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const has = t => backend.calendarJson.indexOf(t) >= 0
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { rail.current = "calendar"; const s = new Date(); s.setDate(s.getDate() + 1); calendarView.start = calendarView.startFor(s) }
            else if (step === 1) console.warn("CARD shown", calendarView.cardForTest("OST calendar test: created from OST"))
            else if (step === 2) cap("card")
            else if (step === 3) {
                const s = new Date(); s.setDate(s.getDate() + 1); s.setHours(10, 0, 0, 0)
                backend.createEvent("OST event test", calendarView.iso(s), calendarView.iso(new Date(s.getTime() + 1800000)), "", false)
            } else if (step === 5) { console.warn("CARD created", has("\"OST event test\"")); calendarView.cardForTest("OST event test") }
            else if (step === 6) { calendarView.editForTest("OST event test (edited)") }
            else if (step === 7) { cap("edit"); calendarView.saveForTest() }
            else if (step === 9) {
                const ev = JSON.parse(backend.calendarJson).find(e => e.subject === "OST event test (edited)")
                console.warn("CARD edited", !!ev, ev ? new Date(ev.start_utc).getHours() + ":" + new Date(ev.start_utc).getMinutes() : "")
                calendarView.cardForTest("OST event test (edited)")
            } else if (step === 10) { calendarView.deleteForTest() }
            else if (step === 11) { cap("delete"); calendarView.confirmDeleteForTest() }
            else if (step === 13) { console.warn("CARD deleted", !has("OST event test")); Qt.quit() }
            step++
        }
    }

    // --group-call-test: call the "OST group test" chat, stay 50 s,
    // capture the call window and People, hang up.
    Timer {
        running: Qt.application.arguments.indexOf("--group-call-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            else if (step === 1) backend.startCall()
            else if (step === 20) {
                console.warn("GROUPCALL state", backend.callState, "meeting", backend.callMeeting, "roster", backend.callRosterJson)
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-group.png")))
                callWindow.side = "people"
            } else if (step === 21) callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-grouppeople.png")))
            else if (step === 22) backend.hangUp()
            else if (step === 24) Qt.quit()
            step++
        }
    }

    // --custom-emoji-test=<png>: add "ost-test" for the org from <png>,
    // capture the dialog and the picker's Custom section, send it in "OST
    // group test" in a message and react to that message with it.
    // --custom-emoji-delete: delete "ost-test" for the org.
    Timer {
        readonly property string png: (Qt.application.arguments.find(a => a.startsWith("--custom-emoji-test=")) || "").slice(20)
        readonly property bool deleting: Qt.application.arguments.indexOf("--custom-emoji-delete") >= 0
        running: (png.length > 0 || deleting) && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const org = () => backend.customEmojiJson ? JSON.parse(backend.customEmojiJson) : []
            const mine = () => org().find(e => e.shortcut === "ost-test")
            const add = conversation.customEmojiAddForTest(), p = conversation.funPickerForTest()
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name); backend.loadCustomEmoji() }
            else if (step === 2 && deleting) {
                const e = mine(); console.warn("CUSTOM delete", e ? e.id : "none")
                if (e) backend.deleteCustomEmoji(e.id)
            }
            else if (step === 5 && deleting) { backend.loadCustomEmoji() }
            else if (step === 7 && deleting) { console.warn("CUSTOM after delete", JSON.stringify(org().map(e => e.shortcut))); Qt.quit() }
            else if (deleting) {}
            else if (step === 2) { console.warn("CUSTOM before", org().length); add.startWith("file://" + png) }
            else if (step === 4) { console.warn("CUSTOM name", add.nameForTest); cap("dialog") }
            else if (step === 5) console.warn("CUSTOM add pressed", add.addForTest())
            else if (step === 9) { console.warn("CUSTOM result", backend.customEmojiResult, JSON.stringify(org())); cap("added") }
            else if (step === 10) { conversation.openEmojiForTest(); p.tab = "emoji" }
            else if (step === 11) p.tab = "emoji"
            else if (step === 12) { const e = mine(); if (e) backend.emoticonUrl(e.id, 20) }
            else if (step === 13) cap("picker")
            else if (step === 14) { const e = mine(); p.close(); conversation.insertTextForTest("OST test 58: our custom emoji "); if (e) p.pickedEmoji(e.id) }
            else if (step === 15) { console.warn("CUSTOM compose", JSON.stringify(conversation.composeMediaForTest())); conversation.sendForTest() }
            else if (step === 20) {
                const e = mine(), msgs = JSON.parse(backend.messagesJson || "[]")
                const m = msgs.filter(m => (m.text || "").indexOf("OST test 58") >= 0).pop()
                console.warn("CUSTOM sent", m ? m.id + " " + m.text : "not found")
                if (m && e) backend.toggleReaction(m.id, e.id, true)
            }
            else if (step === 26) { cap("timeline"); }
            else if (step === 27) Qt.quit()
            step++
        }
    }

    // --attach-test: in "OST group test", Teams' Attach: the popover (and a
    // search with no results), the cloud file picker's Home, Navigation
    // Pane, My files, People, Meetings and Media, then ost-share-test.txt
    // picked into the compose box; --attach-send sends it as "OST TEST
    // 119". --attach-channel does it in OST Test Team > OST layout test,
    // opening the picker with Browse Teams and Channels ("OST TEST 121").
    // Logs ATTACH lines.
    Timer {
        running: Qt.application.arguments.indexOf("--attach-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        property int waited: 0
        onTriggered: {
            const m = conversation.attachMenuForTest(), p = conversation.cloudPickerForTest()
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("ATTACH", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const chan = Qt.application.arguments.indexOf("--attach-channel") >= 0
            if (step === 0) {
                if (chan) {
                    const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.name === "OST Test Team")
                    const ch = team ? team.channels.find(c => c.name === "OST layout test") : null
                    if (!ch) return
                    backend.selectChat(ch.id, ch.name)
                } else { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            }
            else if (step === 2) conversation.attachFile()
            else if (step === 4) { log("menu", m.stateForTest()); cap("menu") }
            else if (step === 5) m.searchForTest("ost-share")
            else if (step === 7) { log("search", m.stateForTest()); cap("noresults") }
            else if (step === 8) { m.close(); if (chan) m.browseChannels(); else { p.entry = "home"; p.open() } }
            else if (step === 10) { log("home", p.stateForTest()); cap("home") }
            else if (step === 11) p.openForTest("nav")
            else if (step === 12) cap("nav")
            else if (step === 13) { p.openForTest("nav"); p.openForTest("people") }
            else if (step === 15) { log("people", p.stateForTest()); cap("people") }
            else if (step === 16) p.openForTest("meetings")
            else if (step === 18) { log("meetings", p.stateForTest()); cap("meetings") }
            else if (step === 19) p.openForTest("media")
            else if (step === 21) { log("media", p.stateForTest()); cap("media") }
            else if (step === 22) p.openForTest("myfiles")
            else if (step === 24) { log("myfiles", p.stateForTest()); cap("myfiles") }
            else if (step === 25) log("picked", p.pickForTest("ost-share-test.txt"))
            else if (step === 26) { log("selected", p.stateForTest().selected); cap("picked") }
            else if (step === 27) p.attachForTest()
            else if (step === 30) { const c = conversation.cloudForTest(); if (c.some(x => x.loading) && waited++ < 20) return; log("compose", c); cap("compose") }
            else if (step === 31) { if (Qt.application.arguments.indexOf("--attach-send") < 0) Qt.quit(); else { conversation.setComposeText(chan ? "OST TEST 121 cloud file in a channel from OST" : "OST TEST 119 cloud file from OST"); } }
            else if (step === 32) conversation.sendForTest()
            else if (step === 36) { log("sent; status", backend.statusText); cap("sent"); Qt.quit() }
            step++
        }
    }

    // --filecard-test: in OST Test Team > OST layout test, OST TEST 121's
    // file card (Teams' head, location and preview; hovered), its ··· menu,
    // Copy link ("Link copied") and Share this file. --filecard-live also
    // adds the file to OneDrive Favorites, reads the menu (Unfavorite) and
    // takes it off again, then Undo and off once more: it ends as it began.
    // Logs FILECARD lines.
    Timer {
        running: Qt.application.arguments.indexOf("--filecard-test") >= 0 && backend.signedIn && !!backend.teamsJson
        interval: 2500; repeat: true
        property int step: 0
        property int waited: 0
        property var file: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("FILECARD", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const live = Qt.application.arguments.indexOf("--filecard-live") >= 0
            if (step === 0) {
                const team = JSON.parse(backend.teamsJson).find(t => t.name === "OST Test Team")
                const ch = team ? team.channels.find(c => c.name === "OST layout test") : null
                if (!ch) return
                backend.selectChat(ch.id, ch.name)
            } else if (step === 3) {
                const m = conversation.messages.filter(m => (m.files || []).some(f => f.name === "ost-share-test.txt")).pop()
                if (!m) { if (waited++ < 10) return; log("no file message"); Qt.quit(); return }
                file = m.files.find(f => f.name === "ost-share-test.txt")
                log("file", file)
            } else if (step === 5) { log("card", conversation.fileCardForTest(file.object_url)); cap("card") }
            else if (step === 6) conversation.hoverFileCardForTest(file.object_url, true)
            else if (step === 7) cap("hover")
            else if (step === 8) { conversation.hoverFileCardForTest(file.object_url, false); conversation.openFileCardMenuForTest(file.object_url) }
            else if (step === 10) { log("menu", conversation.fileCardMenuForTest(), conversation.fileCardKnownForTest(file.object_url) ? conversation.fileCardKnownForTest(file.object_url).favorite : null); cap("menu") }
            else if (step === 11) { conversation.closeFileCardMenuForTest(); conversation.fileCardActForTest(file, "Copy link") }
            else if (step === 14) { log("copied", conversation.copyLinkStateForTest()); cap("copied") }
            else if (step === 15) { conversation.closeCopyLinkForTest(); conversation.fileCardActForTest(file, "Share") }
            else if (step === 17) cap("share")
            else if (step === 18) { conversation.closeCardShareForTest(); if (!live) { Qt.quit(); return } toast.toastData = null; conversation.fileCardActForTest(file, "Favorite") }
            else if (step === 19) { if (!toast.toastData && waited++ < 12) return; waited = 0; log("favorite toast", toast.toastData ? toast.toastData.text : null); cap("fav-toast") }
            else if (step === 20) conversation.openFileCardMenuForTest(file.object_url)
            else if (step === 22) { log("menu after", conversation.fileCardMenuForTest().items); cap("menu-unfav") }
            else if (step === 23) { conversation.closeFileCardMenuForTest(); toast.toastData = null; conversation.fileCardActForTest(file, "Unfavorite") }
            else if (step === 24) { if (!toast.toastData && waited++ < 12) return; waited = 0; log("unfavorite toast", toast.toastData ? [toast.toastData.text, toast.toastData.action] : null); cap("unfav-toast") }
            else if (step === 25) { const d = toast.toastData; toast.toastData = null; if (d && d.onAction) d.onAction() }
            else if (step === 26) { if (!toast.toastData && waited++ < 12) return; waited = 0; log("undo toast", toast.toastData ? toast.toastData.text : null, "known", conversation.fileCardKnownForTest(file.object_url).favorite) }
            else if (step === 27) { toast.toastData = null; conversation.fileCardActForTest(file, "Unfavorite") }
            else if (step === 28) { if (!toast.toastData && waited++ < 12) return; log("end", toast.toastData ? toast.toastData.text : null, "known", conversation.fileCardKnownForTest(file.object_url).favorite); Qt.quit() }
            step++
        }
    }

    // --fileviewer-test: in OST Test Team > OST layout test, open OST TEST
    // 121's file in Teams' viewer, its ··· menu, then Esc; then
    // ost-open-test.docx (My files) as PDF pages. Logs FILEVIEWER lines.
    Timer {
        running: Qt.application.arguments.indexOf("--fileviewer-test") >= 0 && backend.signedIn && !!backend.teamsJson
        interval: 2500; repeat: true
        property int step: 0
        property int waited: 0
        property var file: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("FILEVIEWER", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            if (step === 0) {
                const team = JSON.parse(backend.teamsJson).find(t => t.name === "OST Test Team")
                const ch = team ? team.channels.find(c => c.name === "OST layout test") : null
                if (!ch) return
                backend.selectChat(ch.id, ch.name)
            } else if (step === 3) {
                const m = conversation.messages.filter(m => (m.files || []).some(f => f.name === "ost-share-test.txt")).pop()
                if (!m) { if (waited++ < 10) return; log("no file message"); Qt.quit(); return }
                file = m.files.find(f => f.name === "ost-share-test.txt")
                conversation.openFileRequested(file)
            } else if (step === 4) { if (fileViewer.loading && waited++ < 20) return; waited = 0; log("text", fileViewer.stateForTest()); cap("text") }
            else if (step === 5) conversation.openFileCardMenu(file, fileViewer.moreButtonForTest(), 4)
            else if (step === 6) { log("menu", conversation.fileCardMenuForTest()); cap("menu") }
            else if (step === 7) conversation.closeFileCardMenuForTest()
            else if (step === 8) fileViewer.close()
            else if (step === 9) { log("closed", fileViewer.stateForTest().open); cap("closed")
                fileViewer.show({ name: "ost-open-test.docx", file_type: "docx", object_url: "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com/Documents/ost-open-test.docx", location: "", site_url: "" }) }
            else if (step === 10) { if (fileViewer.loading && waited++ < 30) return; log("docx", fileViewer.stateForTest()) }
            else if (step === 12) { cap("docx"); }
            else if (step === 13) { fileViewer.close(); Qt.quit() }
            step++
        }
    }

    // --poll-test: in "OST group test", the newest Polls card (OST TEST 126):
    // its refresh (for its author), the sender line, a capture; with
    // --poll-vote=<choice> it votes ("0" Red, "1" Blue) and captures Teams'
    // response bar and, once the bot edits its results, the results.
    // Logs POLL lines.
    Timer {
        running: Qt.application.arguments.indexOf("--poll-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        property int waited: 0
        property var poll: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("POLL", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const voteArg = Qt.application.arguments.find(a => a.startsWith("--poll-vote="))
            const card = m => (m.cards || []).findIndex(c => c.content && (c.content.actions || []).some(a => a.title === "Submit Vote"))
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            else if (step === 2) {
                const m = conversation.messages.filter(m => card(m) >= 0).pop()
                if (!m) { if (waited++ < 10) return; log("no poll"); Qt.quit(); return }
                poll = m; waited = 0
                conversation.jumpToNewest()
                log("poll", { id: m.id, sender: m.sender, via: m.on_behalf_of, bot: m.sender_mri, index: card(m) })
            } else if (step === 5) {
                log("state", conversation.cardStateForTest(poll.id)); cap("poll")
            } else if (step === 6) { if (!voteArg) { Qt.quit(); return } log("vote", conversation.cardActionForTest(poll.id, card(poll), "Submit Vote", { choice: voteArg.split("=")[1] })) }
            else if (step === 7) { log("busy", conversation.cardStateForTest(poll.id)); cap("busy") }
            else if (step === 9) { log("after", conversation.cardStateForTest(poll.id)); cap("voted") }
            else if (step === 14) {
                const results = conversation.messages.filter(m => (m.cards || []).some(c => JSON.stringify(c.content || {}).indexOf("responses") >= 0 || JSON.stringify(c.content || {}).indexOf("response\"") >= 0)).pop()
                log("results", results ? { id: results.id, edited: results.edited, text: JSON.stringify(results.cards[0].content).match(/\d+ responses?/) } : null)
                cap("results")
            }
            else if (step === 15) Qt.quit()
            step++
        }
    }

    // --fun-picker-test: in "OST group test", open the fun picker and capture
    // each tab; then put in an emoticon, a trending GIF and a captioned
    // sticker and send them (--fun-send), logging the outcome.
    Timer {
        running: Qt.application.arguments.indexOf("--fun-picker-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const p = conversation.funPickerForTest()
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            else if (step === 2) conversation.openEmojiForTest()
            else if (step === 4) { console.warn("FUN trending", p.trending.length, "stickers", p.catalog.stickers.length); cap("all") }
            else if (step === 5) p.tab = "emoji"
            else if (step === 6) cap("emoji")
            else if (step === 7) p.tab = "gifs"
            else if (step === 8) { cap("gifs"); p.gifCategoryForTest(1) }
            else if (step === 11) { console.warn("FUN reactions", p.gifResults.length); cap("gif-results") }
            else if (step === 12) p.tab = "stickers"
            else if (step === 13) cap("stickers")
            else if (step === 14) p.openPack = "Clippy"
            else if (step === 16) cap("pack")
            else if (step === 17) p.editForTest("OfficeDrama_HighFive", "OST TEST 57")
            else if (step === 19) cap("editor")
            else if (step === 20) { if (Qt.application.arguments.indexOf("--fun-send") < 0) Qt.quit(); else p.finishEditForTest() }
            else if (step === 21) { conversation.openEmojiForTest() }
            else if (step === 22) { p.pickedEmoji("surprised"); p.close() }
            else if (step === 23) { conversation.openEmojiForTest() }
            else if (step === 25) { p.chooseGif(p.trending[0]); }
            else if (step === 27) { console.warn("FUN compose media", JSON.stringify(conversation.composeMediaForTest())); cap("compose") }
            else if (step === 28) conversation.sendForTest()
            else if (step === 34) { console.warn("FUN sent; status", backend.statusText); cap("sent"); Qt.quit() }
            step++
        }
    }

    // --media-order-test: in "OST group test", send text, a trending GIF and
    // more text (Teams keeps the GIF between them), capturing it sent.
    Timer {
        running: Qt.application.arguments.indexOf("--media-order-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const p = conversation.funPickerForTest()
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            else if (step === 2) conversation.insertTextForTest("OST TEST 58 before the GIF")
            else if (step === 3) conversation.openEmojiForTest()
            else if (step === 4) p.tab = "gifs"
            else if (step === 6) { p.chooseGif(p.trending[0]) }
            else if (step === 7) conversation.insertTextForTest("and after it")
            else if (step === 8) { console.warn("ORDER compose media", JSON.stringify(conversation.composeMediaForTest())); cap("compose") }
            else if (step === 9) conversation.sendForTest()
            else if (step === 14) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("ORDER sent", JSON.stringify({ html: m.html, after: m.html_after, media: m.media, edit_media: m.edit_media })); cap("sent") }
            else if (step === 16) Qt.quit()
            step++
        }
    }

    // --breakpoints-test: in the group chat (and then the meeting chat), size
    // the window so the header is 892, 781, 681, 604 and 460 wide, capturing
    // the header and its ··· menu each time.
    Timer {
        running: Qt.application.arguments.indexOf("--breakpoints-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 1500; repeat: true
        property int step: 0
        readonly property var widths: [892, 781, 681, 604, 460]
        onTriggered: {
            const n = widths.length
            const chat = step < 4 * n + 2 ? "OST group test" : "Randy Northrup"
            const k = step < 4 * n + 2 ? step - 2 : step - (4 * n + 4)
            if (step === 0 || step === 4 * n + 2) { const c = chatList.chats.find(c => c.name === chat); backend.selectChat(c.id, c.name) }
            else if (k >= 0 && k < 4 * n) {
                const i = Math.floor(k / 4), phase = k % 4
                const tag = (chat === "Randy Northrup" ? "oo-" : "gr-") + widths[i]
                if (phase === 0) window.width = widths[i] + (window.width - conversation.width)
                else if (phase === 1) { console.warn("BP", tag, "header", conversation.width); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png"))) }
                else if (phase === 2) conversation.openChatMenuForTest()
                else window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath.replace(".png", "-" + tag + "-menu.png")); conversation.closeChatMenuForTest() })
            }
            else if (step > 8 * n + 6) Qt.quit()
            step++
        }
    }

    // --meeting-chat-test: open the OST calendar test meeting chat, capture
    // its header, Join as the header does, capture again, hang up.
    Timer {
        running: Qt.application.arguments.indexOf("--meeting-chat-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.id.indexOf("19:meeting_") === 0)
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const cap = (w, tag) => w.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { const c = chatList.chats.find(c => c.id.indexOf("19:meeting_") === 0); backend.selectChat(c.id, c.name) }
            else if (step === 3) { console.warn("MEETINGCHAT meeting", backend.chatMeetingJson, "tabs", JSON.stringify(conversation.tabNames)); cap(window, "header") }
            else if (step === 4) { const m = JSON.parse(backend.chatMeetingJson); backend.joinMeeting(m.join_url, m.subject) }
            else if (step === 10) { console.warn("MEETINGCHAT state", backend.callState, "thread", backend.callThreadId === backend.currentChatId); cap(window, "joined") }
            else if (step === 11) backend.hangUp()
            else if (step === 14) { console.warn("MEETINGCHAT after", backend.callState); Qt.quit() }
            step++
        }
    }

    // --video-call-test: in the chat with Randy, capture the header, place a
    // Video call (answered on the other side), capture the call window with
    // the camera state, hang up after ~30 s and log the remembered choice.
    Timer {
        running: Qt.application.arguments.indexOf("--video-call-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "Randy Northrup")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const cap = (w, tag) => w.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { const c = chatList.chats.find(c => c.name === "Randy Northrup"); backend.selectChat(c.id, c.name) }
            else if (step === 2) { console.warn("VIDEOCALL choice before", backend.headerCallVideo); cap(window, "header") }
            else if (step === 3) backend.startVideoCall()
            else if (step === 4) console.warn("VIDEOCALL choice now", backend.headerCallVideo, "state", backend.callState)
            else if (step === 16) { console.warn("VIDEOCALL state", backend.callState, "camera", backend.callCameraOn, "canVideo", backend.callCanVideo); cap(callWindow, "call") }
            else if (step === 18) cap(window, "header-after")
            else if (step === 20) backend.hangUp()
            else if (step === 23) { console.warn("VIDEOCALL after", backend.callState, "choice", backend.headerCallVideo); Qt.quit() }
            step++
        }
    }

    // --mute-test: mute "OST group test", check the server says so after a
    // reload, capture the row, open its menu, then unmute and check again.
    Timer {
        running: Qt.application.arguments.indexOf("--mute-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const c = chatList.chats.find(c => c.name === "OST group test")
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) { console.warn("MUTE before", c.muted); backend.setChatMuted(c.id, true) }
            else if (step === 1) cap("optimistic")
            else if (step === 4) { console.warn("MUTE after reload", c.muted); backend.refresh() }
            else if (step === 6) { console.warn("MUTE server", c.muted); cap("muted"); chatList.openRowMenuForTest(c.id) }
            else if (step === 7) cap("menu")
            else if (step === 8) { chatList.closeRowMenuForTest(); backend.setChatMuted(c.id, false) }
            else if (step === 10) backend.refresh()
            else if (step === 12) { console.warn("MUTE unmuted", c.muted); cap("unmuted"); Qt.quit() }
            step++
        }
    }

    // --meet-now-test: Meet now in "OST group test" (with --meet-join, join
    // its ongoing call instead), stay 50 s (capturing the header before and
    // in the call, and the call window), log the call state, hang up.
    Timer {
        running: Qt.application.arguments.indexOf("--meet-now-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-header.png")))
            else if (step === 2) { if (Qt.application.arguments.indexOf("--meet-join") >= 0) backend.joinGroupCall(); else backend.meetNow() }
            else if (step === 6) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-incall.png")))
            else if (step === 8) { console.warn("MEETNOW state", backend.callState, "meeting", backend.callMeeting, "thread", backend.callThreadId, "roster", backend.callRosterJson); callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-meetnow.png"))) }
            else if (step === 22) backend.hangUp()
            else if (step === 26) { console.warn("MEETNOW after", backend.callState); Qt.quit() }
            step++
        }
    }

    // --open-file-test: Settings ▸ Files and links' "Always open Word,
    // PowerPoint, and Excel files in", then ost-open-test.docx opened with
    // Desktop app chosen (by its drive item, then by its address); the
    // setting is put back afterwards.
    Timer {
        running: Qt.application.arguments.indexOf("--open-file-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string before: ""
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const f = (oneDrive.driveData.items || []).find(i => i.name === "ost-open-test.docx")
            if (step === 0) { before = backend.setting("fileOpenIn"); console.warn("OPENFILE app", JSON.stringify(backend.officeAppName()), "setting", JSON.stringify(before)); rail.current = "settings"; settingsView.pageForTest("files") }
            else if (step === 1) cap("settings")
            else if (step === 2) { backend.setSetting("fileOpenIn", "desktop"); rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 4) { console.warn("OPENFILE item", !!f); if (f) backend.openFile(f.web_url, f.name, JSON.stringify(f)) }
            else if (step === 7 && f) backend.openFile(f.web_url, f.name, "")
            else if (step === 10) { backend.setSetting("fileOpenIn", before); console.warn("OPENFILE restored", JSON.stringify(backend.setting("fileOpenIn"))); Qt.quit() }
            step++
        }
    }

    // --file-actions-test: Teams' file menu on ost-share-test.txt in My
    // files (its Open submenu, Rename, Delete?, Move to into Attachments)
    // without changing anything; --file-actions-live also duplicates it
    // (and deletes the copy), renames it and back, copies it to
    // Attachments (and deletes the copy), moves it there and back;
    // --file-actions-link makes its Copy link (and deletes that link).
    Timer {
        running: Qt.application.arguments.indexOf("--file-actions-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var it: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--file-actions-live") >= 0
            const linkTest = Qt.application.arguments.indexOf("--file-actions-link") >= 0
            const fa = oneDrive.fileActions
            const d = oneDrive.driveData
            const find = n => (d.items || []).find(i => i.name === n)
            const log = (tag, x) => console.warn("FILEACT", tag, JSON.stringify(x === undefined ? fa.stateForTest() : x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !(d.items || []).length) return
            else if (step === 2) {
                it = find("ost-share-test.txt")
                log("items", (d.items || []).map(i => i.name))
                if (!it) { Qt.quit(); return }
                log("menu", fa.menuForTest(it)); log("folder menu", fa.menuForTest(find("Attachments") || {}))
                fa.popupForTest(it)
            }
            else if (step === 3) cap("menu")
            else if (step === 4) fa.submenuForTest()
            else if (step === 5) cap("submenu")
            else if (step === 6) { fa.closeAllForTest(); fa.actForTest(it, "Rename") }
            else if (step === 7) { log("rename"); cap("rename") }
            else if (step === 8) { fa.closeAllForTest(); fa.actForTest(it, "Delete") }
            else if (step === 9) { log("delete"); cap("delete") }
            else if (step === 10) { fa.closeAllForTest(); fa.actForTest(it, "Move to") }
            else if (step === 11) { log("move"); cap("move") }
            else if (step === 12) log("into", fa.pickerIntoForTest("Attachments"))
            else if (step === 13) { log("move into"); cap("move-into") }
            else if (step === 14) { fa.closeAllForTest(); if (linkTest) fa.actForTest(it, "Copy link") }
            else if (step === 16 && linkTest) { log("link", fa.linkForTest()); cap("link") }
            else if (step === 17 && linkTest) fa.copyForTest()
            else if (step === 18 && linkTest) cap("link-copied")
            else if (step === 19 && linkTest) {
                const l = fa.linkForTest(); fa.closeAllForTest()
                if (l.share_id) backend.shareAction("unlink", JSON.stringify(l.ref), JSON.stringify({ kind: l.kind, share_id: l.share_id }))
            }
            else if (step === 20 && !live) Qt.quit()
            else if (step === 21) fa.actForTest(it, "Duplicate")
            else if (step === 22) { log("duplicating"); cap("duplicating") }
            else if (step === 26) { log("duplicated"); log("copy there", !!find("ost-share-test Copy.txt")); cap("duplicated") }
            else if (step === 27) oneDrive.deleteForTest("ost-share-test Copy.txt")
            else if (step === 29) { fa.actForTest(it, "Rename"); fa.renameForTest("ost-share-test-ost") }
            else if (step === 31) { log("renamed"); log("renamed there", !!find("ost-share-test-ost.txt")); cap("renamed") }
            else if (step === 32) { const r = find("ost-share-test-ost.txt"); if (r) { fa.actForTest(r, "Rename"); fa.renameForTest("ost-share-test") } }
            else if (step === 34) { it = find("ost-share-test.txt"); log("renamed back", !!it); if (it) fa.actForTest(it, "Copy to") }
            else if (step === 36) log("copy into", fa.pickerIntoForTest("Attachments"))
            else if (step === 38) cap("copy-picker")
            else if (step === 39) fa.pickerDoneForTest()
            else if (step === 44) { log("copied"); const a = find("Attachments"); if (a) oneDrive.openFolder(a.name, a.drive_id, a.id) }
            else if (step === 45) { log("in Attachments", (d.items || []).map(i => i.name)); oneDrive.deleteForTest("ost-share-test.txt") }
            else if (step === 47) { log("copy deleted", !find("ost-share-test.txt")); oneDrive.open("myfiles") }
            else if (step === 48) { it = find("ost-share-test.txt"); if (it) fa.actForTest(it, "Move to") }
            else if (step === 50) log("move into", fa.pickerIntoForTest("Attachments"))
            else if (step === 52) fa.pickerDoneForTest()
            else if (step === 57) { log("moved"); log("gone from My files", !find("ost-share-test.txt")); const a = find("Attachments"); if (a) oneDrive.openFolder(a.name, a.drive_id, a.id) }
            else if (step === 58) { it = find("ost-share-test.txt"); log("in Attachments", !!it); if (it) fa.actForTest(it, "Move to") }
            else if (step === 60) { log("picker at My files"); cap("move-back") }
            else if (step === 61) fa.pickerDoneForTest()
            else if (step === 66) { log("moved back"); oneDrive.open("myfiles") }
            else if (step === 67) { log("back in My files", !!find("ost-share-test.txt")); Qt.quit() }
            step++
        }
    }

    // --folder-extras-test: a folder's menu (Request files, Folder color ▸)
    // on Attachments; --folder-extras-live also colours it Light blue then
    // back to Yellow, and makes a file request "OST test 114" (then removes
    // its link).
    Timer {
        running: Qt.application.arguments.indexOf("--folder-extras-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string share: ""
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--folder-extras-live") >= 0
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const find = n => (d.items || []).find(i => i.name === n)
            const log = (tag, x) => console.warn("FOLDERX", tag, JSON.stringify(x))
            const it = find("Attachments")
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { log("menu", fa.menuForTest(it)); log("color now", it.folder_color); fa.popupForTest(it) }
            else if (step === 3) cap("menu")
            else if (step === 4) { fa.closeAllForTest(); if (!live) Qt.quit() }
            else if (step === 5) fa.colorForTest(it, "13")
            else if (step === 8) { log("colored", it.folder_color); cap("blue"); oneDrive.setViewForTest("tiles") }
            else if (step === 9) cap("blue-tiles")
            else if (step === 10) { oneDrive.setViewForTest("list"); fa.colorForTest(it, "0") }
            else if (step === 13) { log("back to yellow", it.folder_color || "(none)"); fa.fileRequestForTest(it, "OST test 114") }
            else if (step === 16) { const st = fa.fileRequestStateForTest(); log("request", st); share = st.share_id; cap("request") }
            else if (step === 17) { fa.closeAllForTest(); if (share) backend.shareAction("unlink", JSON.stringify(fa.ref(it)), JSON.stringify({ kind: 6, share_id: share })) }
            // Add shortcut ▸ Shortcuts and ▸ My files for ost-share-test.txt
            // (the shortcuts are removed by the runner afterwards).
            else if (step === 18) { log("file menu", fa.menuForTest(find("ost-share-test.txt"))); fa.shortcutForTest(find("ost-share-test.txt"), "shortcuts") }
            else if (step === 20) { log("shortcut", fa.stateForTest().toast); fa.shortcutForTest(find("ost-share-test.txt"), "myfiles") }
            else if (step === 22) { log("shortcut my files", fa.stateForTest().toast); cap("shortcut") }
            else if (step === 23) Qt.quit()
            step++
        }
    }

    // --picker-views-test: the Copy to picker's view switch: List, Compact
    // List, then Tiles in My files and in Recordings (videos).
    Timer {
        running: Qt.application.arguments.indexOf("--picker-views-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const st = () => fa.pickerStateForTest()
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 1) { const it = (d.items || []).find(i => i.name === "ost-share-test.txt"); if (!it) return; fa.actForTest(it, "Copy to") }
            else if (step === 2 && st().loading) return
            else if (step === 2) cap("list")
            else if (step === 3) fa.pickerViewForTest("compact")
            else if (step === 4) cap("compact")
            else if (step === 5) fa.pickerViewForTest("tiles")
            else if (step === 6) cap("tiles")
            else if (step === 7) console.warn("PVIEW into", fa.pickerIntoForTest("Recordings"))
            else if (step === 8 && st().loading) return
            else if (step === 9) cap("tiles-videos")
            else if (step === 10) { fa.pickerViewForTest("list"); cap("list-videos") }
            else if (step === 11) fa.pickerNavForTest(true, true)
            else if (step === 12) cap("rail")
            else if (step === 13) fa.pickerNavForTest(false, false)
            else if (step === 14) cap("browse-folded")
            else if (step === 15) { fa.pickerNavForTest(false, true); fa.closeAllForTest(); Qt.quit() }
            step++
        }
    }

    // --quick-access-test: Teams' Quick access in the OneDrive pane and the
    // Copy to picker (pinned, then recent libraries), opening one; with
    // --quick-access-live, OST Test Team is pinned and unpinned again.
    Timer {
        running: Qt.application.arguments.indexOf("--quick-access-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("QUICK", tag, JSON.stringify(x))
            const live = Qt.application.arguments.indexOf("--quick-access-live") >= 0
            const fa = oneDrive.fileActions, d = oneDrive.driveData
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 1 && !fa.quickForTest().length) return
            else if (step === 1) { log("pane", fa.quickForTest()); cap("pane") }
            else if (step === 2) log("open", oneDrive.openQuickForTest("OST Test Team"))
            else if (step === 3 && !(d.items || []).length) return
            else if (step === 3) { log("in library", { trail: oneDrive.trail.map(t => t.name), items: (d.items || []).length }); cap("library") }
            else if (step === 4) oneDrive.open("myfiles")
            else if (step === 5) { const it = (d.items || []).find(i => i.name === "ost-share-test.txt"); if (!it) return; fa.actForTest(it, "Copy to") }
            else if (step === 6) cap("picker")
            else if (step === 7 && !live) { fa.closeAllForTest(); Qt.quit() }
            else if (step === 7) log("pin", fa.pinForTest("OST Test Team", true))
            else if (step === 9 && fa.quickForTest().indexOf("OST Test Team (pinned)") < 0) return
            else if (step === 9) { log("pinned", fa.quickForTest()); cap("pinned") }
            else if (step === 10) log("unpin", fa.pinForTest("OST Test Team", false))
            else if (step === 12 && fa.quickForTest().indexOf("OST Test Team (pinned)") >= 0) return
            else if (step === 12) { log("unpinned", fa.quickForTest()); cap("unpinned"); fa.closeAllForTest() }
            else if (step === 13) Qt.quit()
            step++
        }
    }

    // --folder-bar-test: in My files › Recordings with nothing selected,
    // Teams' folder bar (Share, Copy link, Download, Open in OneDrive), the
    // trail under it and the list at 144.67; then a row selected (the trail
    // stays) and Share for the folder opened and closed.
    Timer {
        running: Qt.application.arguments.indexOf("--folder-bar-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("FOLDERBAR", tag, JSON.stringify(x))
            const d = oneDrive.driveData
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 1) {
                const r = (d.items || []).find(i => i.name === "Recordings")
                if (!r) return
                log("root", oneDrive.folderBarForTest()); cap("root")
                oneDrive.openFolder(r.name, r.drive_id, r.id)
            }
            else if (step === 2 && !oneDrive.folderBarForTest().length) return
            else if (step === 2) { log("sub", oneDrive.folderBarForTest()); cap("sub") }
            else if (step === 3) { const it = (d.items || [])[0]; oneDrive.selectedIds = [it.id] }
            else if (step === 4) { log("selected", { bar: oneDrive.barForTest(), folder: oneDrive.folderBarForTest() }); cap("selected") }
            else if (step === 5) { oneDrive.selectedIds = []; oneDrive.folderBarRunForTest("Share") }
            else if (step === 6) { log("share", oneDrive.fileActions.shareOpenForTest()); cap("share") }
            else if (step === 7) { oneDrive.fileActions.closeAllForTest(); Qt.quit() }
            step++
        }
    }

    // --bell-test: the Details pane's bell on ost-share-test.txt switched
    // off, then back on; after each the pane reloads and logs what
    // SharePoint says (it ends on, as it began).
    Timer {
        running: Qt.application.arguments.indexOf("--bell-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("BELL", tag, JSON.stringify(x))
            const st = () => { const s = oneDrive.detailsForTest(); return { loading: s.loading, notify: s.notify, error: s.notifyError } }
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { oneDrive.selectForTest([it.name]); fa.actForTest(it, "Details") }
            else if ((step === 3 || step === 7 || step === 11) && st().loading) return
            else if (step === 3) log("before", st())
            else if (step === 4 || step === 8) oneDrive.detailsBellForTest()
            else if (step === 6 || step === 10) { log(step === 6 ? "set off" : "set on", st()); oneDrive.detailsReloadForTest() }
            else if (step === 7) log("reloaded off", st())
            else if (step === 11) { log("reloaded on", st()); Qt.quit() }
            step++
        }
    }

    // --picker-test: the Copy to picker on ost-share-test.txt: My files,
    // Shared, Favorites, People, Meetings, More places…, a search in My
    // files and in all files, the date filter's menu and Last 7 days, and
    // a result's Location opened; --picker-live also makes "OST picker test"
    // with New folder (opened, then deleted).
    Timer {
        running: Qt.application.arguments.indexOf("--picker-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--picker-live") >= 0
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("PICKER", tag, JSON.stringify(x))
            const st = () => fa.pickerStateForTest()
            // Each place is logged and captured once it has loaded, then
            // the next is opened a step later (the capture is async).
            const settled = () => !st().loading
            const places = ["mine", "shared", "favorites", "people", "meetings", "more"]
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) fa.actForTest(it, "Copy to")
            else if (step >= 3 && step < 15) {
                const k = Math.floor((step - 3) / 2), p = places[k]
                if ((step - 3) % 2 === 0) { if (!settled()) return; log(p, st()); cap(p) }
                else if (k + 1 < places.length) fa.pickerPlaceForTest(places[k + 1])
                else fa.pickerPlaceForTest("mine")
            }
            else if (step === 15) fa.pickerSearchForTest("Recordings", false)
            else if (step === 16 && !settled()) return
            else if (step === 16) { log("search mine", st()); cap("search") }
            else if (step === 17) fa.pickerSearchForTest("ost", true)
            else if (step === 18 && !settled()) return
            else if (step === 18) { log("search all", st()); cap("search-all") }
            else if (step === 19) fa.pickerDatesMenuForTest(true)
            else if (step === 20) cap("dates-menu")
            else if (step === 21) { fa.pickerDatesMenuForTest(false); fa.pickerDatesForTest("last7Days") }
            else if (step === 22 && !settled()) return
            else if (step === 22) { log("last 7 days", st()); cap("search-7days") }
            else if (step === 23) log("location", fa.pickerLocationForTest("OST threads test"))
            else if (step === 24 && !settled()) return
            else if (step === 24) { log("location opened", st()); cap("location") }
            else if (step === 25) fa.pickerPlaceForTest("mine")
            else if (step === 26 && !live) { fa.closeAllForTest(); Qt.quit() }
            else if (step === 26 && !settled()) return
            else if (step === 26) fa.pickerNewFolderForTest("OST picker test")
            else if (step === 27 && !settled()) return
            else if (step === 27) { log("new folder", st()); cap("new-folder") }
            else if (step === 28) { fa.closeAllForTest(); oneDrive.open("myfiles") }
            else if (step === 29 && !oneDrive.deleteForTest("OST picker test")) return
            else if (step === 29) log("delete", true)
            else if (step === 31) oneDrive.open("myfiles")
            else if (step === 32 && !(d.items || []).length) return
            else if (step === 32) { log("gone", !(d.items || []).some(i => i.name === "OST picker test")); Qt.quit() }
            step++
        }
    }

    // --files-links-test: Settings ▸ Files and links (the two new rows);
    // a web link opened with Microsoft Edge chosen (run with a stand-in
    // microsoft-edge on PATH that records its URL); a download with "Always
    // ask where to save" on, answered with /tmp/ostdl/chosen.txt. Restores
    // both settings.
    Timer {
        id: filesLinksTest
        running: Qt.application.arguments.indexOf("--files-links-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string askBefore: ""
        property string browserBefore: ""
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("FILESLINKS", tag, JSON.stringify(x))
            if (step === 0) { askBefore = backend.setting("askDownloadLocation"); browserBefore = backend.setting("linkBrowser"); log("browsers", JSON.parse(backend.webBrowsers())); rail.current = "settings"; settingsView.pageForTest("files") }
            else if (step === 1) cap("page")
            else if (step === 2) { backend.setSetting("linkBrowser", "edge"); Qt.openUrlExternally("https://example.com/ost-link-test") }
            else if (step === 3) { backend.setSetting("askDownloadLocation", "true"); rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 5 && !(oneDrive.driveData.items || []).some(i => i.name === "ost-share-test.txt")) return
            else if (step === 5) { const it = (oneDrive.driveData.items || []).find(i => i.name === "ost-share-test.txt"); log("download", !!it); backend.driveDownload(JSON.stringify(it)) }
            else if (step === 8) { backend.setSetting("askDownloadLocation", askBefore); backend.setSetting("linkBrowser", browserBefore); log("restored", [backend.setting("askDownloadLocation"), backend.setting("linkBrowser")]); Qt.quit() }
            step++
        }
    }
    Connections {
        target: backend
        enabled: Qt.application.arguments.indexOf("--files-links-test") >= 0
        function onSaveAsRequested(id, name, folder) {
            console.warn("FILESLINKS", "asked", JSON.stringify([id, name, folder]))
            saveAsDialog.close()
            backend.saveAsAnswer(id, "/tmp/ostdl/chosen.txt")
        }
    }

    // --zip-test: Download of the Notebooks folder (Notebooks.zip) and of
    // ost-share-test.txt with ost-open-test.docx (OneDrive_1_….zip), both
    // made by OneDrive's media service, into the download folder.
    Timer {
        running: Qt.application.arguments.indexOf("--zip-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const find = n => (d.items || []).find(i => i.name === n)
            const log = (tag, x) => console.warn("ZIP", tag, JSON.stringify(x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !find("Notebooks")) return
            else if (step === 2) { log("folder menu", fa.menuForTest(find("Notebooks"))); fa.actForTest(find("Notebooks"), "Download") }
            else if (step === 3) log("folder progress", fa.stateForTest().toast)
            else if (step === 7) { log("folder done", fa.stateForTest().toast); oneDrive.selectForTest(["ost-share-test.txt", "ost-open-test.docx"]); fa.actMany(oneDrive.selection, "Download") }
            else if (step === 8) log("two progress", fa.stateForTest().toast)
            else if (step === 12) { log("two done", fa.stateForTest().toast); Qt.quit() }
            step++
        }
    }

    // --sortview-test: My files sorted by Modified (the header's arrow),
    // Compact List, Tiles, then Details with nothing selected (the folder's
    // activity).
    Timer {
        running: Qt.application.arguments.indexOf("--sortview-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = oneDrive.driveData
            const log = (tag, x) => console.warn("SORTVIEW", tag, JSON.stringify(x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !(d.items || []).length) return
            else if (step === 2) { log("modified asc", oneDrive.sortForTest("modified", true)); log("size desc", oneDrive.sortForTest("size", false)); log("modified", oneDrive.sortForTest("modified", true)) }
            else if (step === 3) cap("sorted")
            else if (step === 4) { oneDrive.sortForTest("", true); oneDrive.setViewForTest("compact") }
            else if (step === 5) cap("compact")
            else if (step === 6) oneDrive.setViewForTest("tiles")
            else if (step === 8) cap("tiles")
            else if (step === 9) { oneDrive.setViewForTest("list"); oneDrive.folderDetailsForTest() }
            else if (step === 11 && oneDrive.detailsForTest().loading) return
            else if (step === 11) { log("folder details", oneDrive.detailsForTest()); cap("folder-details") }
            else if (step === 12) Qt.quit()
            step++
        }
    }

    // --preview-test: Preview of ost-share-test.txt (text) from its menu,
    // then Previous to ost-open-test.docx (Office, as PDF pages).
    Timer {
        running: Qt.application.arguments.indexOf("--preview-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("PREVIEW", tag, JSON.stringify(x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { log("menu", fa.menuForTest(it)); fa.actForTest(it, "Preview") }
            else if (step === 4) { log("text", oneDrive.previewForTest()); cap("text") }
            else if (step === 5) oneDrive.previewStepForTest(-1)
            else if (step === 6 && oneDrive.previewForTest().loading) return
            else if (step === 6) { log("docx", oneDrive.previewForTest()); cap("docx") }
            else if (step === 7) { oneDrive.previewCloseForTest(); Qt.quit() }
            step++
        }
    }

    // --details-test: the Details pane for ost-share-test.txt in My files
    // (from its menu), its activity and More details, the narrow list;
    // --details-live also switches its bell off and back on.
    Timer {
        running: Qt.application.arguments.indexOf("--details-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--details-live") >= 0
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("DETAILS", tag, JSON.stringify(x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { log("menu", fa.menuForTest(it)); oneDrive.selectForTest([it.name]); fa.actForTest(it, "Details") }
            else if (step === 4 && oneDrive.detailsForTest().loading) return
            else if (step === 4) { log("pane", oneDrive.detailsForTest()); cap("pane") }
            else if (step === 5) oneDrive.detailsScrollForTest(100000)
            else if (step === 6) { cap("pane-bottom"); oneDrive.detailsScrollForTest(0) }
            else if (step === 7 && !live) Qt.quit()
            // A test comment, shown as its card, then deleted (with the one
            // posted while researching, "OST test 111").
            else if (step === 7) oneDrive.detailsCommentForTest("OST test 112")
            else if (step === 10) oneDrive.detailsReloadForTest()
            else if (step === 13) { log("with comments", oneDrive.detailsForTest().groups.slice(0, 3)); cap("comment") }
            else if (step === 14) log("delete 112", oneDrive.detailsDeleteCommentForTest("OST test 112"))
            else if (step === 15) log("delete 111", oneDrive.detailsDeleteCommentForTest("OST test 111"))
            else if (step === 17) oneDrive.detailsReloadForTest()
            else if (step === 20) { log("after delete", oneDrive.detailsForTest().groups.slice(0, 3)); Qt.quit() }
            step++
        }
    }

    // --comments-test: on ost-share-test.txt's Details pane, a test comment
    // is posted, edited ("• Edited") and replied to (the reply under it),
    // the edit box shown, then the comment deleted (with the one made in
    // Teams while researching, "OST comment test 1 edited").
    Timer {
        running: Qt.application.arguments.indexOf("--comments-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("COMMENTS", tag, JSON.stringify(x))
            const cs = () => oneDrive.detailsCommentsForTest()
            const has = t => cs().some(c => c.indexOf(t) >= 0)
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { oneDrive.selectForTest([it.name]); fa.actForTest(it, "Details") }
            else if (step === 3 && oneDrive.detailsForTest().loading) return
            else if (step === 3) { log("before", cs()); oneDrive.detailsCommentForTest("OST comment test 2") }
            else if (step === 4 && !has("OST comment test 2")) return
            else if (step === 4) log("edit", oneDrive.detailsEditCommentForTest("OST comment test 2", "OST comment test 2 edited"))
            else if (step === 5 && !has("OST comment test 2 edited")) return
            else if (step === 5) log("reply", oneDrive.detailsReplyForTest("OST comment test 2 edited", "OST reply test 2"))
            else if (step === 6 && !has("OST reply test 2")) return
            else if (step === 6) { log("after", cs()); oneDrive.detailsScrollForTest(330) }
            else if (step === 7) cap("comments")
            else if (step === 8) log("start edit", oneDrive.detailsStartEditForTest("OST comment test 2 edited"))
            else if (step === 9) cap("editing")
            else if (step === 10) { log("delete 2", oneDrive.detailsDeleteCommentForTest("OST comment test 2 edited")); }
            else if (step === 11) log("delete 1", oneDrive.detailsDeleteCommentForTest("OST comment test 1 edited"))
            else if (step === 12 && (has("OST comment test 2") || has("OST comment test 1"))) return
            else if (step === 12) { log("cleaned", cs()); Qt.quit() }
            step++
        }
    }

    // --version-history-test: Version history of ost-share-test.txt in My
    // files (the menu entry, the dialog); --version-history-live also
    // restores its oldest version (a new version) and deletes that oldest
    // one (to the recycle bin), as Teams' Restore and Delete Version do.
    Timer {
        running: Qt.application.arguments.indexOf("--version-history-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string oldest: ""
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--version-history-live") >= 0
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const it = (d.items || []).find(i => i.name === "ost-share-test.txt")
            const log = (tag, x) => console.warn("VERSIONS", tag, JSON.stringify(x))
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !it) return
            else if (step === 2) { log("menu", fa.menuForTest(it)); oneDrive.selectForTest([it.name]); log("bar", oneDrive.barForTest()); fa.actForTest(it, "Version history") }
            else if (step === 4) { const v = fa.versionsForTest(); log("list", v); oldest = v.list.length ? v.list[v.list.length - 1].split(" | ")[0] : ""; cap("versions") }
            else if (step === 5 && !live) Qt.quit()
            else if (step === 5) log("restore " + oldest, fa.versionRunForTest(oldest, "Restore"))
            else if (step === 8) { log("after restore", fa.versionsForTest()); cap("restored") }
            else if (step === 9) log("delete " + oldest, fa.versionRunForTest(oldest, "Delete Version"))
            else if (step === 14) { log("after delete", fa.versionsForTest()); cap("deleted"); Qt.quit() }
            step++
        }
    }

    // --onedrive-rows-test: Teams' OneDrive rows in My files (Modified
    // wording, Sharing, the New mark, Activity), a hovered row, the
    // selection bar for one file, one folder and two files, its ··· menu and
    // Delete? for two; --onedrive-rows-live also duplicates ost-share-test.txt
    // and ost-open-test.docx together (deleting the copies), and moves both
    // into Attachments and back.
    Timer {
        running: Qt.application.arguments.indexOf("--onedrive-rows-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const live = Qt.application.arguments.indexOf("--onedrive-rows-live") >= 0
            const d = oneDrive.driveData, fa = oneDrive.fileActions
            const find = n => (d.items || []).find(i => i.name === n)
            const log = (tag, x) => console.warn("ROWS", tag, JSON.stringify(x))
            const two = ["ost-share-test.txt", "ost-open-test.docx"]
            if (step === 0) { rail.current = "onedrive"; oneDrive.open("myfiles") }
            else if (step === 2 && !find(two[0])) return // still loading
            else if (step === 2) { log("rows", oneDrive.rowsForTest()); oneDrive.hoverForTest = (d.items || []).findIndex(i => i.name === two[0]) }
            else if (step === 3) cap("rows")
            else if (step === 4) { oneDrive.hoverForTest = -1; log("one", oneDrive.selectForTest([two[0]])); log("bar", oneDrive.barForTest()) }
            else if (step === 5) cap("one")
            else if (step === 6) oneDrive.barRunForTest("")
            else if (step === 7) cap("one-more")
            else if (step === 8) { oneDrive.barCloseForTest(); oneDrive.barRunForTest("Open") }
            else if (step === 9) cap("one-open")
            else if (step === 10) { oneDrive.barCloseForTest(); oneDrive.selectForTest(["Attachments"]); log("folder bar", oneDrive.barForTest()) }
            else if (step === 11) cap("folder")
            else if (step === 12) { log("two", oneDrive.selectForTest(two)); log("two bar", oneDrive.barForTest()) }
            else if (step === 13) cap("two")
            else if (step === 14) oneDrive.barRunForTest("")
            else if (step === 15) cap("two-more")
            else if (step === 16) { oneDrive.barCloseForTest(); oneDrive.barRunForTest("Delete") }
            else if (step === 17) { log("delete", fa.stateForTest()); cap("two-delete") }
            else if (step === 18) { fa.closeAllForTest(); if (!live) Qt.quit() }
            else if (step === 19) { oneDrive.selectForTest(two); fa.actMany(oneDrive.selection, "Duplicate") }
            else if (step === 20) { log("duplicating", fa.stateForTest()); cap("duplicating") }
            else if (step === 25) { log("duplicated", fa.stateForTest()); log("copies", ["ost-share-test Copy.txt", "ost-open-test Copy.docx"].map(n => !!find(n))); cap("duplicated") }
            else if (step === 26) { oneDrive.selectForTest(["ost-share-test Copy.txt", "ost-open-test Copy.docx"]); fa.actMany(oneDrive.selection, "Delete") }
            else if (step === 27) { log("delete copies", fa.stateForTest()); cap("delete-copies") }
            else if (step === 28) fa.closeAllForTest() // the dialog's own Delete is the user's; delete directly:
            else if (step === 29) { ["ost-share-test Copy.txt", "ost-open-test Copy.docx"].forEach(n => oneDrive.deleteForTest(n)) }
            else if (step === 32) { log("copies gone", ["ost-share-test Copy.txt", "ost-open-test Copy.docx"].map(n => !find(n))); oneDrive.selectForTest(two); fa.actMany(oneDrive.selection, "Move to") }
            else if (step === 34) log("into", fa.pickerIntoForTest("Attachments"))
            else if (step === 36) fa.pickerDoneForTest()
            else if (step === 37) { log("moving", fa.stateForTest()); cap("moving") }
            else if (step === 42) { log("moved", fa.stateForTest()); log("gone", two.map(n => !find(n))); const a = find("Attachments"); if (a) oneDrive.openFolder(a.name, a.drive_id, a.id) }
            else if (step === 43) { log("in Attachments", oneDrive.rowsForTest()); log("pick", oneDrive.selectForTest(two)); fa.actMany(oneDrive.selection, "Move to") }
            else if (step === 45) fa.pickerDoneForTest()
            else if (step === 50) { log("moved back", fa.stateForTest()); oneDrive.open("myfiles") }
            else if (step === 53) { log("back", two.map(n => !!find(n))); log("rows after", oneDrive.rowsForTest()); Qt.quit() }
            step++
        }
    }

    // --onedrive-test: Home, My files (into Microsoft Teams Chat Files),
    // Shared and Libraries, capturing each; make and delete a test folder.
    Timer {
        running: Qt.application.arguments.indexOf("--onedrive-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = oneDrive.driveData
            if (step === 0) rail.current = "onedrive"
            else if (step === 1) { console.warn("DRIVE home", (d.items || []).length, d.error || ""); cap("home"); oneDrive.open("myfiles") }
            else if (step === 2) { console.warn("DRIVE myfiles", (d.items || []).map(i => i.name).join(", "), d.error || ""); cap("myfiles"); oneDrive.newFolderForTest("OST drive test") }
            else if (step === 4) { console.warn("DRIVE folder made", (d.items || []).some(i => i.name === "OST drive test")); cap("folder") }
            else if (step === 5) console.warn("DRIVE folder deleted request", oneDrive.deleteForTest("OST drive test"))
            else if (step === 7) {
                console.warn("DRIVE folder gone", !(d.items || []).some(i => i.name === "OST drive test"))
                const f = (d.items || []).find(i => i.is_folder); if (f) oneDrive.openFolder(f.name, f.drive_id, f.id)
            }
            else if (step === 8) { console.warn("DRIVE inside", (d.items || []).map(i => i.name).join(", ")); cap("inside"); oneDrive.open("shared") }
            else if (step === 9) { console.warn("DRIVE shared", (d.items || []).length, d.error || ""); cap("shared"); oneDrive.open("libraries") }
            else if (step === 14) { oneDrive.open("recycle") }
            else if (step === 15) { console.warn("DRIVE recycle", d.deleted ? d.deleted.length : -1, d.error || ""); cap("recycle"); console.warn("DRIVE restore one test folder", oneDrive.restoreTestFolders()) }
            else if (step === 17) { oneDrive.open("myfiles") }
            else if (step === 18) {
                console.warn("DRIVE restored into My files", (d.items || []).some(i => i.name === "OST drive test"))
                const f = (d.items || []).find(i => i.name === "Microsoft Teams Chat Files"); if (f) oneDrive.openFolder(f.name, f.drive_id, f.id)
            }
            else if (step === 19) { const f = (d.items || []).find(i => !i.is_folder); window.favName = f ? f.name : ""; if (f) oneDrive.favorite(f.drive_id, f.id, true) }
            else if (step === 20) { oneDrive.open("favorites") }
            else if (step === 21) {
                const f = (d.items || []).find(i => i.name === window.favName)
                console.warn("DRIVE favorite shown", !!f, d.error || ""); cap("favorites")
                if (f) oneDrive.favorite(f.drive_id, f.id, false)
            }
            else if (step === 23) { oneDrive.open("myfiles") }
            else if (step === 24) { const n = oneDrive.deleteForTest("OST drive test"); console.warn("DRIVE delete restored folder", n) }
            else if (step === 26) { oneDrive.open("recycle") }
            else if (step === 27) { console.warn("DRIVE purge test folders", oneDrive.purgeTestFolders()) }
            else if (step === 29) { oneDrive.open("recycle") }
            else if (step === 30) { console.warn("DRIVE test folders left in recycle bin", (d.deleted || []).filter(x => x.name === "OST drive test").length, d.error || ""); oneDrive.open("media") }
            else if (step === 31) { console.warn("DRIVE media", (d.items || []).length, d.error || ""); oneDrive.open("people") }
            else if (step === 32) { console.warn("DRIVE people", (d.people || []).map(p => p.name + ":" + p.items.length).join(", "), d.error || ""); cap("people"); oneDrive.open("meetings") }
            else if (step === 33) { console.warn("DRIVE meetings", (d.items || []).length, d.error || ""); Qt.quit() }
            else if (step === 11) {
                console.warn("DRIVE libraries", (d.libraries || []).map(l => l.site + "/" + l.name).join(", "), d.error || ""); cap("libraries")
                const l = (d.libraries || []).find(l => l.site === "OST Test Team"); if (l) { oneDrive.trail = []; oneDrive.openFolder(l.site + " · " + l.name, l.drive_id, "") }
            }
            else if (step === 13) { console.warn("DRIVE library", (d.items || []).map(i => i.name).join(", "), d.error || ""); cap("library") }
            step++
        }
    }

    // --hold-test: in a call, hold and resume, send dial-pad tones, and
    // capture when the other side holds; stays until they hang up.
    Connections {
        target: backend
        enabled: Qt.application.arguments.indexOf("--hold-test") >= 0
        function onCallStateChanged() { if (backend.callState === "connected") holdTest.start() }
        function onCallHeldByPeerChanged() {
            console.warn("HOLD held by peer", backend.callHeldByPeer)
            callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", backend.callHeldByPeer ? "-peerheld.png" : "-peerresumed.png")))
        }
    }
    Timer {
        id: holdTest
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 1) { console.warn("HOLD can dtmf", backend.callCanDtmf); backend.toggleHold() }
            else if (step === 2) { console.warn("HOLD held", backend.callHeld, backend.statusText); cap("held") }
            else if (step === 7) { backend.toggleHold() }
            else if (step === 8) { console.warn("HOLD resumed", !backend.callHeld, backend.statusText) }
            else if (step === 9) { callWindow.dialPadForTest(); callWindow.pressForTest("123#") }
            else if (step === 10) { cap("dialpad"); callWindow.closeDialPadForTest(); console.warn("HOLD tones sent") }
            step++
        }
    }

    // --transfer-test=<oid>: once a call connects, transfer it to that
    // person and log what happens; stays until the call ends.
    readonly property string transferTarget: {
        const a = Qt.application.arguments.find(x => x.indexOf("--transfer-test=") === 0)
        return a ? a.split("=")[1] : ""
    }
    Connections {
        target: backend
        enabled: window.transferTarget.length > 0
        function onCallStateChanged() {
            console.warn("XFER state", backend.callState)
            if (backend.callState === "connected") xferTimer.start()
            if (backend.callState === "ended") quitTimer.start()
        }
        function onStatusTextChanged() { console.warn("XFER status", backend.statusText) }
    }
    // --consult: consult first (hold, chat with them), then Transfer from
    // the consult banner.
    readonly property bool consultFirst: Qt.application.arguments.indexOf("--consult") >= 0
    Timer {
        id: xferTimer
        interval: 5000
        property int step: 0
        onTriggered: {
            const cap = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (!window.consultFirst) { cap("before"); backend.transferCall(window.transferTarget); return }
            if (step === 0) { callWindow.consultForTest(window.transferTarget, "OST Test 1"); step = 1; restart() }
            else if (step === 1) { console.warn("XFER consulting", !!callWindow.consulting, "held", backend.callHeld, "chat", backend.currentChatName); cap("consult"); step = 2; restart() }
            else if (step === 2) { callWindow.transferFromConsultForTest() }
        }
    }

    // --apps-test: People (add a contact, favorite it, delete it) and
    // OneNote (open the first notebook, add a page, delete it), capturing.
    Timer {
        running: Qt.application.arguments.indexOf("--apps-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const people = peopleApp.data_.contacts || []
            if (step === 0) rail.openApp("people")
            else if (step === 2) { console.warn("APPS contacts", people.length, peopleApp.data_.error || "", "busy", peopleApp.busy); cap("people-empty") }
            else if (step === 3) { peopleApp.addForTest("OST", "People test", "ost-people-test@example.com") }
            else if (step === 5) { const c = peopleApp.find("OST People test"); console.warn("APPS contact added", !!c); if (c) peopleApp.favorite(c.id, true) }
            else if (step === 7) { const c = peopleApp.find("OST People test"); console.warn("APPS favorite", !!c && c.favorite); peopleApp.view = "favorites"; cap("people-favorites") }
            else if (step === 8) { peopleApp.view = "all"; cap("people-all"); const c = peopleApp.find("OST People test"); if (c) peopleApp.remove(c.id) }
            else if (step === 10) { console.warn("APPS contact deleted", !peopleApp.find("OST People test"), "rail extras", rail.opened.join(",")); rail.openApp("onenote") }
            else if (step === 12) { console.warn("APPS notebooks", oneNote.notebooks.map(n => n.name).join(", "), oneNote.error); cap("onenote"); if (oneNote.notebooks.length) oneNote.openNotebook(oneNote.notebooks[0]) }
            else if (step === 15) { console.warn("APPS sections", oneNote.sections.map(s => s.name).join(", ")); if (oneNote.section) oneNote.newPageForTest("OST OneNote page", "Written from OST.\nSecond line.") }
            else if (step === 19) { console.warn("APPS page shown", !!oneNote.page && oneNote.page.title, "html", oneNote.html.indexOf("Written from OST") >= 0); cap("onenote-page") }
            else if (step === 20) { if (oneNote.page) oneNote.removePage(oneNote.page.id) }
            else if (step === 22) { console.warn("APPS page deleted", !oneNote.pages.some(p => p.title === "OST OneNote page")); Qt.quit() }
            step++
        }
    }

    // --channel-files-test: OST Test Team's General channel, Shared tab:
    // make a folder, capture, delete it.
    Timer {
        running: Qt.application.arguments.indexOf("--channel-files-test") >= 0 && backend.signedIn && backend.teamsJson.length > 2
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const cf = conversation.channelFilesForTest()
            if (step === 0) {
                const team = JSON.parse(backend.teamsJson).find(t => t.name === "OST Test Team")
                const ch = team && (team.channels || []).find(c => c.name === "General")
                console.warn("CF channel", !!ch)
                if (ch) { rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
            } else if (step === 2) conversation.tab = "Shared"
            else if (step === 4) { console.warn("CF folder", cf.here ? cf.here.name : "-", "items", cf.items.length, cf.error, "busy", cf.busy, "empty shown", cf.emptyShownForTest()); cap("shared") }
            // --channel-files-share: Share instead (OneDrive's dialog), captured.
            else if (step === 5 && Qt.application.arguments.indexOf("--channel-files-share") >= 0) { console.warn("CF share ids", JSON.stringify(cf.here ? [cf.here.sp_site, cf.here.sp_list, cf.here.sp_item] : null)); cf.shareForTest() }
            else if (step === 6 && Qt.application.arguments.indexOf("--channel-files-share") >= 0) cap("share")
            else if (step === 7 && Qt.application.arguments.indexOf("--channel-files-share") >= 0) Qt.quit()
            else if (step === 5) cf.newFolderForTest("OST channel test")
            else if (step === 6) { console.warn("CF made", cf.items.some(i => i.name === "OST channel test")); cap("made"); cf.deleteForTest("OST channel test") }
            else if (step === 8) { console.warn("CF deleted", !cf.items.some(i => i.name === "OST channel test")); Qt.quit() }
            step++
        }
    }

    // --store-test: open the Store and capture Home, scrolled; the Featured
    // and Categories menus; a See all page; a category page; a search for
    // "planner"; then Polls' details. Logs what loaded and quits.
    Timer {
        running: Qt.application.arguments.indexOf("--store-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) rail.current = "add"
            else if (step < 12 && (store.busy || !store.feedCols.length) && !store.reply.error) { step++; return }
            else if (step < 13) {
                console.warn("STORE feed", JSON.stringify(store.feedCols.map(c => c.title + ": " + c.apps.slice(0, 4).map(a => a.name).join(", "))))
                console.warn("STORE menus", JSON.stringify({ featured: store.featuredNav.map(g => g.map(n => n.title + "/" + n.icon)), categories: store.categoryNav.map(n => n.title + "/" + n.icon) }), store.reply.error || "")
                cap("home"); step = 13; return
            }
            else if (step === 14) store.menuForTest("featured")
            else if (step === 15) cap("featured")
            else if (step === 16) { store.closeMenuForTest(); store.menuForTest("categories") }
            else if (step === 17) cap("categories")
            else if (step === 18) { store.closeMenuForTest(); store.openPage("popularapps") }
            else if (step === 20) { console.warn("STORE page", store.pageData ? store.pageData.title + " " + (store.pageData.apps || []).length : null); cap("seeall") }
            else if (step === 21) { const c = store.categoryNav[0]; if (c) store.openPage(c.id) }
            else if (step === 23) { console.warn("STORE group", store.pageData ? store.pageData.title + ": " + (store.pageData.sections || []).map(x => x.title).join(", ") : null); cap("group") }
            else if (step === 24) store.searchForTest("planner")
            else if (step === 26) { console.warn("STORE search", store.found ? (store.found.results || []).slice(0, 5).map(a => a.name).join(", ") : null); cap("search") }
            else if (step === 27) { store.home(); console.warn("STORE details", store.detailsForTest("Polls")) }
            else if (step === 29) cap("details")
            else if (step === 30) Qt.quit()
            step++
        }
    }

    // --webapp-test: open Whiteboard from View more apps; capture once the
    // page has loaded (its sign-in page when not signed in).
    Timer {
        running: Qt.application.arguments.indexOf("--webapp-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) rail.openApp(Qt.application.arguments.indexOf("--webapp-help") >= 0 ? "help" : "whiteboard")
            else if (step === 5) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-webapp.png")))
            // A second view (another app) shares the profile.
            else if (step === 6) rail.openApp("clipchamp")
            else if (step === 8) { console.warn("WEBAPP second view open"); Qt.quit() }
            step++
        }
    }

    // --planner-test: open Planner from View more apps; add a private task,
    // complete it; create a plan in OST Test Team, add a task, delete the
    // plan; capturing along the way.
    Timer {
        running: Qt.application.arguments.indexOf("--planner-test") >= 0 && backend.signedIn && backend.teamsJson.length > 2
        interval: 3000; repeat: true
        property int step: 0
        property var made: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const d = planner.plannerData, has = t => (d.tasks || []).some(x => x.title === t)
            if (step === 0) rail.openApp("planner")
            else if (step === 1) { console.warn("PLAN mytasks", (d.tasks || []).length, d.error || ""); cap("mytasks"); planner.filter = "all"; planner.addForTest("OST planner test task") }
            else if (step === 3) { console.warn("PLAN task added", has("OST planner test task")); cap("added"); planner.completeForTest("OST planner test task") }
            else if (step === 5) { console.warn("PLAN task completed (gone from open tasks)", !has("OST planner test task")); console.warn("PLAN create", planner.createPlanForTest("OST planner test plan")) }
            else if (step === 7) planner.open("plans")
            else if (step === 8) {
                const p = (d.plans || []).find(p => p.title === "OST planner test plan")
                console.warn("PLAN plans", (d.plans || []).map(p => p.title).join(", "), "made", !!p, "status", backend.statusText, d.error || ""); cap("plans")
                made = p; if (p) planner.open("plan", p)
            }
            else if (step === 10 && made) { planner.addToPlan(JSON.stringify(made), "OST plan task") }
            else if (step === 12 && made) { console.warn("PLAN plan task", has("OST plan task")); cap("plan"); planner.board = true }
            else if (step === 13) { cap("board") }
            else if (step === 14) {
                // Clean up every test plan (earlier runs' too).
                planner.open("plans")
            }
            else if (step === 16) {
                const left = (d.plans || []).filter(p => p.title === "OST planner test plan")
                console.warn("PLAN deleting test plans", left.length)
                for (const p of left) planner.deletePlan(p.id)
            }
            else if (step === 19) { planner.open("plans") }
            else if (step === 21) { console.warn("PLAN test plans left", (d.plans || []).filter(p => p.title === "OST planner test plan").length); cap("cleaned"); Qt.quit() }
            step++
        }
    }

    // --search-test: type "Ran" into search and capture the suggestions.
    Timer {
        running: Qt.application.arguments.indexOf("--search-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int n: 0
        onTriggered: {
            if (n++ === 0) { titleBar.typeSearch("Ran"); return }
            if (backend.peopleJson && backend.peopleJson.length > 2) {
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            }
        }
    }

    // --channel-test: open OST Test Team > General, post, capture when shown.
    // --title-test: the window title for an app, a chat and a channel
    // (Teams' taskbar label), logged as TITLE lines; reads only.
    Timer {
        running: Qt.application.arguments.indexOf("--title-test") >= 0 && backend.signedIn && chatList.chats.length > 1 && backend.teamsJson.length > 2
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const teams = JSON.parse(backend.teamsJson)
            const team = teams.find(t => t.name === "OST Test Team")
            const group = chatList.chats.find(c => c.name === "OST group test")
            if (step === 0) console.warn("TITLE start", window.title)
            else if (step === 1) backend.selectChat(group.id, group.name)
            else if (step === 2) console.warn("TITLE chat", window.title)
            else if (step === 3) { const ch = team.channels.find(c => c.name === "General"); backend.selectChat(ch.id, ch.name) }
            else if (step === 4) console.warn("TITLE channel", window.title)
            else if (step === 5) rail.current = "calendar"
            else if (step === 6) console.warn("TITLE calendar", window.title)
            else if (step === 7) { rail.current = "chat"; Qt.quit() }
            step++
        }
    }
    Timer {
        running: Qt.application.arguments.indexOf("--channel-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const team = teams.find(t => t.name === "OST Test Team")
            if (!team) return
            const ch = team.channels.find(c => c.name === "General")
            if (step === 0) { backend.selectChat(ch.id, ch.name); step = 1; return }
            if (step === 1) { backend.sendMessage("OST channel test 1: first post from OST"); step = 2; return }
            if (backend.messagesJson.indexOf("OST channel test 1") >= 0) {
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            }
        }
    }

    // --react-test: open the first chat, add a heart to the newest message
    // from someone else, capture once it shows.
    readonly property bool reactTest: Qt.application.arguments.indexOf("--react-test") >= 0
    property bool reacted: false
    Timer {
        running: window.reactTest && backend.signedIn
        interval: 3000; repeat: true
        onTriggered: {
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            if (!backend.currentChatId && chats.length > 0) { backend.selectChat(chats[0].id, chats[0].name); return }
            const msgs = backend.messagesJson ? JSON.parse(backend.messagesJson) : []
            const target = msgs.filter(m => !m.mine && m.kind === "message").pop()
            if (!target) return
            const heart = (target.reactions || []).find(r => r.key === "heart" && r.mine)
            if (heart) {
                console.warn("REACT-SHOWN", target.text)
                window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
                stop()
            } else if (!window.reacted) {
                window.reacted = true
                backend.toggleReaction(target.id, "heart", true)
            }
        }
    }

    // --typing-test: open the first chat, send typing for 12 s, then
    // capture the first incoming typing indicator.
    readonly property bool typingTest: Qt.application.arguments.indexOf("--typing-test") >= 0
    property int typingTicks: 0
    Timer {
        running: window.typingTest && backend.signedIn
        interval: 2000; repeat: true
        onTriggered: {
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            if (!backend.currentChatId && chats.length > 0) { backend.selectChat(chats[0].id, chats[0].name); return }
            if (window.typingTicks++ < 6) { backend.userTyping(); console.warn("TYPING-SENT") }
        }
    }
    Connections {
        target: backend
        enabled: window.typingTest
        function onTypingTextChanged() {
            if (!backend.typingText) return
            console.warn("TYPING-SHOWN", backend.typingText)
            window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
        }
    }

    // --send-test=<text> with --open-chat=<id>: send <text> once the chat
    // is open, then log (and capture as send-<n>.png in --shots=<dir>) each
    // send-state change of that message; with --delete-failed,
    // delete it once it has failed. Quits 45 s after sending.
    readonly property string sendTestText: (Qt.application.arguments.find(a => a.startsWith("--send-test=")) || "").slice(12)
    property string sendTestCmid: ""
    property string sendTestLast: "-"
    property int sendTestShots: 0
    Timer {
        running: window.sendTestText.length > 0 && backend.signedIn && !window.sendTestCmid
        interval: 4000; repeat: true
        property bool sent: false
        property real openedAt: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST send test"); openedAt = Date.now(); return }
            // --send-delay=<ms>: wait that long after opening the chat.
            const delay = parseInt((Qt.application.arguments.find(a => a.startsWith("--send-delay=")) || "--send-delay=0").slice(13))
            if (sent || Date.now() - openedAt < delay) return
            sent = true
            console.warn("SEND-TEST sending", new Date().toISOString())
            // --quote-newest: quote the newest message from someone else.
            if (Qt.application.arguments.indexOf("--quote-newest") >= 0) {
                const q = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.mine && !m.deleted).pop()
                if (q) backend.setReplyQuote(JSON.stringify({ message_id: q.id, sender_mri: q.sender_mri, sender_name: q.sender, preview: q.quote_text || q.text }))
            }
            backend.sendMessage(window.sendTestText)
            sendTestQuit.start()
        }
    }
    Timer { id: sendTestQuit; interval: 45000; onTriggered: Qt.quit() }
    Connections {
        target: backend
        enabled: window.sendTestText.length > 0
        function onMessagesJsonChanged() {
            const all = JSON.parse(backend.messagesJson || "[]")
            const m = window.sendTestCmid ? all.find(x => x.client_message_id === window.sendTestCmid)
                : all.find(x => x.mine && x.text === window.sendTestText && x.send_state === "sending")
            if (!m) return
            window.sendTestCmid = m.client_message_id
            const st = (m.send_state || "delivered") + " | " + (m.send_note || "") + " | id " + m.id + " | retry " + m.can_retry
            if (st === window.sendTestLast) return
            window.sendTestLast = st
            const n = window.sendTestShots++
            console.warn("SEND-TEST", n, new Date().toISOString(), st)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            Qt.callLater(() => window.contentItem.grabToImage(r => r.saveToFile(dir + "send-" + n + ".png")))
            if (m.send_state === "failed" && Qt.application.arguments.indexOf("--delete-failed") >= 0)
                deleteFailedLater.start()
        }
    }
    Timer {
        id: deleteFailedLater; interval: 4000
        onTriggered: { console.warn("SEND-TEST deleting", window.sendTestCmid); backend.deleteFailedMessage(window.sendTestCmid) }
    }
    // A settled capture of the failed message, once its icons have loaded.
    Timer {
        running: window.sendTestLast.indexOf("failed") === 0; interval: 2500
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            window.contentItem.grabToImage(r => r.saveToFile(dir + "send-failed-settled.png"))
        }
    }

    // --actions-test with --open-chat=<id> --shots=<dir>: the hover bar on
    // the newest message from someone else and on your newest, the reaction
    // picker, and a compose quote; captured as actions-<step>.png.
    Timer {
        running: Qt.application.arguments.indexOf("--actions-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "actions-" + n + ".png"))
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.deleted)
            const theirs = msgs.filter(m => !m.mine).pop(), mine = msgs.filter(m => m.mine).pop()
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST actions test"); return }
            if (step === 0 && theirs) conversation.forceBarId = theirs.id
            else if (step === 1) shot("bar-theirs")
            else if (step === 2 && mine) conversation.forceBarId = mine.id
            else if (step === 3) shot("bar-mine")
            else if (step === 4) { conversation.forceBarId = ""; conversation.openReactionPicker(theirs.id, conversation) }
            else if (step === 6) shot("picker")
            else if (step === 7) { conversation.closePickerForTest(); conversation.replyWithQuote(theirs) }
            else if (step === 8) shot("quote")
            else if (step === 9) { conversation.quoting = null; conversation.openMessageMenu(mine, conversation, false, 0, 200) }
            else if (step === 10) shot("menu-mine")
            else if (step === 11) conversation.openMessageMenu(mine, conversation, true, 600, 300)
            else if (step === 12) shot("menu-rightclick")
            else if (step === 13) Qt.quit()
            step++
        }
    }

    // --who-reacted-test with --open-chat=<id> --shots=<dir>: the newest
    // reacted message's who-reacted list, captured as who-reacted.png.
    Timer {
        running: Qt.application.arguments.indexOf("--who-reacted-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST who reacted test"); return }
            const m = JSON.parse(backend.messagesJson || "[]").filter(m => (m.reactions || []).length > 0).pop()
            if (!m) return
            if (step === 0) { console.warn("WHO-TEST", m.id, JSON.stringify(m.reactions)); conversation.jumpToMessage(m.id) }
            else if (step === 1) conversation.forceWhoId = m.id
            else if (step === 2) window.contentItem.grabToImage(r => r.saveToFile(dir + "who-reacted.png"))
            else if (step === 3) Qt.quit()
            step++
        }
    }

    // --tones-test with --open-chat=<id> --shots=<dir>: the reaction picker
    // on the newest reacted message with no skin tone and with tone 3 (local
    // only, nothing is saved), the hover bar in tone 3, and the six tones of
    // Hands celebrating; captured as tones-<step>.png. Nothing is sent.
    Timer {
        running: Qt.application.arguments.indexOf("--tones-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "tones-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST tones test"); return }
            const m = JSON.parse(backend.messagesJson || "[]").filter(m => (m.reactions || []).length > 0).pop()
            if (!m) return
            if (step === 0) { conversation.jumpToMessage(m.id); conversation.openReactionPicker(m.id, conversation) }
            else if (step === 2) shot("picker-none")
            else if (step === 3) { console.warn("TONES-TEST quick before", backend.quickReactionsJson); backend.skinTone = 3 }
            else if (step === 4) shot("picker-tone3")
            else if (step === 5) conversation.tonesForTest("handsinair")
            else if (step === 6) shot("chooser")
            else if (step === 7) { conversation.closePickerForTest(); conversation.forceBarId = m.id; console.warn("TONES-TEST toned yes", backend.emoticonToned("yes"), backend.emoticonToned("fire")) }
            else if (step === 8) shot("bar")
            else if (step === 9) Qt.quit()
            step++
        }
    }

    // --customize-test with --open-chat=<id> --shots=<dir>: the Customize
    // reactions dialog, its slot picker and tone 3 (not saved), captured as
    // customize-<step>.png. With --customize-save=<tone> it then saves the
    // four defaults in that tone and logs the result.
    Timer {
        running: Qt.application.arguments.indexOf("--customize-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const save = (Qt.application.arguments.find(a => a.startsWith("--customize-save=")) || "").slice(17)
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "customize-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST customize test"); return }
            if (step === 0) conversation.customizeForTest()
            else if (step === 1) shot("dialog")
            else if (step === 2) conversation.customizeSlotForTest(0)
            else if (step === 3) shot("slot-picker")
            else if (step === 4) { conversation.closePickerForTest(); conversation.customizeToneForTest(3) }
            else if (step === 5) shot("tone3")
            else if (step === 6) {
                if (!save) { conversation.closeCustomizeForTest(); Qt.quit(); return }
                conversation.customizeToneForTest(Number(save))
                backend.saveReactionPrefs(JSON.stringify(["yes", "heart", "laugh", "surprised"].map(k => backend.emoticonInTone(k, Number(save)))), Number(save))
            }
            else if (step === 8) { console.warn("CUSTOMIZE-TEST", backend.reactionPrefsResult, backend.quickReactionsJson, backend.skinTone); Qt.quit() }
            step++
        }
    }

    // --react-test=<client id>[,<id>...] with --open-chat=<id> --shots=<dir>:
    // add those reactions to the newest reacted message, capture
    // react-on.png (and the overflow list when there is one) and log the
    // pills, then remove them again and log them.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--react-test=")) && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        property string target: ""
        property bool hold: false
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const keys = (Qt.application.arguments.find(a => a.startsWith("--react-test=")) || "").slice(13).split(",")
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST react test"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]")
            if (!target) { const m = msgs.filter(m => (m.reactions || []).length > 0).pop(); if (!m) return; target = m.id; conversation.jumpToMessage(m.id) }
            const m = msgs.find(m => m.id === target)
            // Keys starting with "-" are only removed (cleanup).
            if (keys[0].startsWith("-")) {
                if (step === 0) { console.warn("REACT-TEST remove only", keys); keys.forEach(k => backend.toggleReaction(target, k.slice(1), false)) }
                else if (step === 4) { console.warn("REACT-TEST after remove", JSON.stringify(m.reactions.map(r => [r.key, r.my_key, r.count]))); Qt.quit() }
                step++
                return
            }
            if (step === 0) { console.warn("REACT-TEST add", keys); keys.forEach(k => backend.toggleReaction(target, k, true)) }
            else if (step === 2) { conversation.jumpToMessage(target); console.warn("REACT-TEST after add", JSON.stringify(m.reactions.map(r => [r.key, r.my_key, r.variants, r.count]))); window.contentItem.grabToImage(r => r.saveToFile(dir + "react-on.png")) }
            else if (step === 3) conversation.forceWhoOverflowId = target
            else if (step === 4) window.contentItem.grabToImage(r => r.saveToFile(dir + "react-overflow.png"))
            else if (step === 5 && Qt.application.arguments.indexOf("--react-hold") >= 0 && !hold) { hold = true; console.warn("REACT-TEST holding 90 s"); interval = 90000; return }
            else if (step === 5) { interval = 4000; conversation.forceWhoOverflowId = ""; const mine = m.reactions.filter(r => r.mine && keys.indexOf(r.my_key) >= 0); console.warn("REACT-TEST remove", mine.map(r => r.my_key)); mine.forEach(r => backend.toggleReaction(target, r.my_key, false)) }
            else if (step === 7) { console.warn("REACT-TEST after remove", JSON.stringify(m.reactions.map(r => [r.key, r.my_key, r.count]))); Qt.quit() }
            step++
        }
    }

    // --edit-test=<suffix> with --open-chat=<id> --shots=<dir>: edit your
    // newest message in place: capture edit-open.png, append the suffix in
    // bold, capture edit-typed.png, press Done and log the message after.
    // With --edit-cancel it cancels instead (Discard draft) and captures it.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--edit-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string target: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const suffix = (Qt.application.arguments.find(a => a.startsWith("--edit-test=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const cancel = Qt.application.arguments.indexOf("--edit-cancel") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "edit-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST edit test"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]")
            if (!target) { const m = msgs.filter(m => m.mine && m.kind === "message" && !m.deleted).pop(); if (!m) return; target = m.id; conversation.jumpToMessage(m.id); conversation.startEdit(m); return }
            const box = conversation.editBoxForTest()
            if (step === 0) shot("open")
            else if (step === 1 && box) { const e = box.editor; e.cursorPosition = e.length; e.insert(e.length, "<b>" + suffix + "</b>") }
            else if (step === 2) shot("typed")
            else if (step === 3 && box) { if (cancel) box.discardForTest(); else box.submit() }
            else if (step === 4) shot(cancel ? "discard" : "done")
            else if (step === 5 && cancel && box) box.confirmDiscardForTest()
            else if (step === 7) { const m = msgs.find(m => m.id === target); console.warn("EDIT-TEST after", JSON.stringify({ text: m.text, html: m.html, after: m.html_after, media: (m.media || []).length, edited: m.edited, quote: !!m.quote })); shot("after"); Qt.quit() }
            step++
        }
    }

    // --compose-send-test=<text> with --open-chat=<id> --shots=<dir>: type
    // <text> into the compose, bold its first word, capture compose-typed.png
    // (with the hint) and send it through the compose; log the newest message.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--compose-send-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const text = (Qt.application.arguments.find(a => a.startsWith("--compose-send-test=")) || "").slice(20)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST compose test"); return }
            if (step === 0) { conversation.setPlain(text); conversation.formatForTest(0, text.indexOf(" "), "b"); conversation.focusCompose() }
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(dir + "compose-typed.png"))
            else if (step === 2) conversation.sendForTest()
            else if (step === 4) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("COMPOSE-TEST newest", JSON.stringify({ html: m.html, state: m.send_state })); Qt.quit() }
            step++
        }
    }

    // --channel-bar-test with --open-chat=<channel id> --shots=<dir>: the
    // newest post's hover bar and ··· menu, then the newest reply's;
    // captured as channel-<step>.png. Nothing is changed.
    Timer {
        running: Qt.application.arguments.indexOf("--channel-bar-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "channel-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "General"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message")
            const posts = msgs.filter(m => !m.root_id || m.root_id === m.id), replies = msgs.filter(m => m.root_id && m.root_id !== m.id)
            const post = posts.find(p => replies.some(r => r.root_id === p.id)) || posts.pop(), reply = replies.filter(r => r.root_id === post.id).pop()
            if (step === 0) conversation.forceChannelBarForTest(post.id)
            else if (step === 1) shot("post-bar")
            else if (step === 2) conversation.channelMenuForTest(post, "post")
            else if (step === 3) shot("post-menu")
            else if (step === 4 && reply) { conversation.closeMessageMenuForTest(); conversation.forceChannelBarForTest(reply.id) }
            else if (step === 5) shot("reply-bar")
            else if (step === 6 && reply) conversation.channelMenuForTest(reply, "reply")
            else if (step === 7) shot("reply-menu")
            else if (step === 8) Qt.quit()
            step++
        }
    }

    // --channel-edit-test=<text> with --open-chat=<channel id> --shots=<dir>:
    // open the in-place editor on your newest reply (captured), then save
    // <text> as its content and log the reply after.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--channel-edit-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var target: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const text = (Qt.application.arguments.find(a => a.startsWith("--channel-edit-test=")) || "").slice(20)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "General"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message")
            if (!target) { target = msgs.filter(m => m.mine && m.root_id && m.root_id !== m.id && !m.deleted).pop(); if (!target) return }
            if (step === 0) conversation.startEdit(target)
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(dir + "channel-edit-open.png"))
            else if (step === 2) { conversation.editingId = ""; backend.editMessageRich(target.id, "<p>" + text + "</p>", "", "") }
            else if (step === 4) { const m = msgs.find(m => m.id === target.id); console.warn("CHANNEL-EDIT after", JSON.stringify({ text: m.text, edited: m.edited })); window.contentItem.grabToImage(r => r.saveToFile(dir + "channel-edit-after.png")) }
            else if (step === 5) Qt.quit()
            step++
        }
    }

    // --follow-test with --open-chat=<channel id>: unfollow the newest post
    // with replies, log its state, follow it again and log it.
    Timer {
        running: Qt.application.arguments.indexOf("--follow-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        property string target: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (backend.currentChatId !== id) { backend.selectChat(id, "General"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message")
            if (!target) { const p = msgs.filter(m => (!m.root_id || m.root_id === m.id) && msgs.some(r => r.root_id === m.id && r.id !== m.id)).pop(); if (!p) return; target = p.id }
            const post = msgs.find(m => m.id === target)
            if (step === 0) { console.warn("FOLLOW-TEST before", post.following); backend.setThreadFollowing(target, false) }
            else if (step === 2) { console.warn("FOLLOW-TEST after unfollow", post.following); backend.setThreadFollowing(target, true) }
            else if (step === 4) { console.warn("FOLLOW-TEST after follow", post.following); Qt.quit() }
            step++
        }
    }

    // --delivery-test=<text> with --open-chat=<id> --shots=<dir>: the "+"
    // flyout and delivery options (captured), then <text> sent Important
    // through the compose; logs the newest message.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--delivery-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const text = (Qt.application.arguments.find(a => a.startsWith("--delivery-test=")) || "").slice(16)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "delivery-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST delivery test"); return }
            if (step === 0) conversation.composeForTest().plusForTest()
            else if (step === 1) shot("plus")
            else if (step === 2) conversation.composeForTest().deliveryForTest()
            else if (step === 3) shot("options")
            else if (step === 4) { conversation.composeForTest().importance = "high"; conversation.setPlain(text) }
            else if (step === 5) shot("compose")
            else if (step === 6) conversation.sendForTest()
            else if (step === 8) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("DELIVERY-TEST newest", JSON.stringify({ text: m.text, importance: m.importance, state: m.send_state })); shot("sent"); Qt.quit() }
            step++
        }
    }

    // --tab-link-test=<tab name> with --open-chat=<channel id>: Copy link
    // to that tab, then stay 20 s (so the clipboard can be read) and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-link-test=")) && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-link-test=")) || "").slice(16)
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0 && conversation.tabNames.indexOf(name) < 0) return
            if (step === 0) console.warn("TABLINK copied", conversation.tabActionForTest(name, "copyLink"))
            else if (step === 6) Qt.quit()
            step++
        }
    }

    // --tab-perms-test=<tab name> with --open-chat=<channel id>
    // --shots=<dir>: open the tab's App permissions, capture it, turn its
    // first permission off and on again (logging what OST would allow),
    // and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-perms-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property string app: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-perms-test=")) || "").slice(17)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0 && conversation.tabNames.indexOf(name) < 0) return
            const p = backend.appPermissionsJson ? JSON.parse(backend.appPermissionsJson) : null
            if (step === 0) conversation.tabActionForTest(name, "devicePermissions")
            else if (step === 2) { console.warn("TABPERMS", JSON.stringify(p)); window.contentItem.grabToImage(r => r.saveToFile(dir + "tabperms.png")); app = p ? p.app : "" }
            else if (step === 3 && p && p.items && p.items.length) { backend.setAppPermission(app, p.items[0].kind, false); console.warn("TABPERMS off ->", backend.appPermission(app, p.items[0].kind)) }
            else if (step === 4) window.contentItem.grabToImage(r => r.saveToFile(dir + "tabperms-off.png"))
            else if (step === 5 && p && p.items && p.items.length) { backend.setAppPermission(app, p.items[0].kind, true); console.warn("TABPERMS on ->", backend.appPermission(app, p.items[0].kind)) }
            else if (step === 6) Qt.quit()
            step++
        }
    }

    // Going elsewhere in the app collapses an expanded tab, as Teams'
    // routing does.
    Connections {
        target: rail
        function onCurrentChanged() { conversation.tabExpanded = false; conversation.channelAttendance = null }
    }

    // --tab-window-test=<tab name> with --open-chat=<channel id>
    // --shots=<dir>: open that tab, expand it (expanded.png), collapse it
    // (collapsed.png), reload it, open it in a new window (window.png,
    // logging the window's header actions), close that and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-window-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var popout: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-window-test=")) || "").slice(18)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0 && conversation.tabNames.indexOf(name) < 0) return
            const t = conversation.channelTabs.find(x => x.name === name)
            if (!t) return
            if (step === 0) { conversation.tab = name; console.warn("TABWIN menu", JSON.stringify(t.menu.map(e => e.key))) }
            else if (step === 2 && t.menu.some(e => e.key === "expandTab")) conversation.tabActionForTest(name, "expandTab")
            else if (step === 4) { console.warn("TABWIN about", (backend.appAboutJson || "").slice(0, 300)); console.warn("TABWIN expanded", conversation.tabExpanded, chatList.visible, conversation.x); window.contentItem.grabToImage(r => r.saveToFile(dir + "expanded.png")) }
            else if (step === 5) conversation.tabExpanded = false
            else if (step === 6) { console.warn("TABWIN collapsed", conversation.tabExpanded, chatList.visible, conversation.x); window.contentItem.grabToImage(r => r.saveToFile(dir + "collapsed.png")); if (t.menu.some(e => e.key === "reloadTab")) conversation.tabActionForTest(name, "reloadTab") }
            else if (step === 8 && t.menu.some(e => e.key === "popOut")) { popout = conversation.popOutTab(t) }
            else if (step === 11 && popout) { console.warn("TABWIN window", popout.title, popout.width, popout.height, JSON.stringify(popout.actionsForTest())); popout.contentItem.grabToImage(r => r.saveToFile(dir + "window.png")) }
            else if (step === 12 && popout && popout.tab.can_converse) popout.act("conversation")
            else if (step === 16 && popout) popout.contentItem.grabToImage(r => r.saveToFile(dir + "window-conversation.png"))
            else if (step === 17 && popout) popout.close()
            else if (step === 18) Qt.quit()
            step++
        }
    }

    // --tab-conversation-test=<tab name> with --open-chat=<channel id>
    // --shots=<dir>: open the tab, Show tab conversation (tabconv.png),
    // reply in it (tabconv-sent.png, logged) and quit; with
    // --tab-conversation-start, press Start conversation first if the tab
    // has none.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-conversation-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-conversation-test=")) || "").slice(24)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0 && conversation.tabNames.indexOf(name) < 0) return
            const conv = tabConversation.conversationForTest()
            if (step === 0) conversation.tab = name
            else if (step === 1) { console.warn("TABCONV tab", JSON.stringify(conversation.currentTab ? { id: conversation.currentTab.id, can: conversation.currentTab.can_converse, root: conversation.currentTab.conversation, icon: !!conversation.currentTab.icon } : null)); conversation.tabConversationTab = conversation.currentTab }
            else if (step === 2 && Qt.application.arguments.indexOf("--tab-conversation-start") >= 0 && !tabConversation.rootId) tabConversation.startForTest()
            else if (step === 5) { console.warn("TABCONV shown", tabConversation.visible, tabConversation.rootId, JSON.stringify(conv.messages.map(m => m.text + (m.files && m.files.length ? " [" + m.files.map(f => f.file_type + ":" + f.item_id).join(",") + "]" : "")))); window.contentItem.grabToImage(r => r.saveToFile(dir + "tabconv.png")) }
            else if (step === 6 && tabConversation.rootId) { conv.insertTextForTest("OST TEST 72 reply in the Notes tab's conversation"); conv.sendForTest() }
            else if (step === 10) { console.warn("TABCONV after", JSON.stringify(conv.messages.map(m => m.text + " " + (m.send_state || "")))); window.contentItem.grabToImage(r => r.saveToFile(dir + "tabconv-sent.png")) }
            else if (step === 11) Qt.quit()
            step++
        }
    }

    // --tab-conversation-start-test=<tab name> with --open-chat=<channel>
    // --shots=<dir>: open the tab in a window as if it had no conversation
    // yet, Show tab conversation (start-empty.png), Start conversation, and
    // log and capture the conversation that follows (start-done.png).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-conversation-start-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var w: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-conversation-start-test=")) || "").slice(30)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            const t = conversation.channelTabs.find(x => x.name === name)
            if (step === 0) { if (!t || !conversation.teamName) return; console.warn("TABSTART before", t.conversation); w = conversation.popOutTab(Object.assign({}, t, { conversation: "" })) }
            else if (step === 2) w.act("conversation")
            else if (step === 4) w.contentItem.grabToImage(r => r.saveToFile(dir + "start-empty.png"))
            else if (step === 5) w.startConversationForTest()
            else if (step === 12) { console.warn("TABSTART after", t ? t.conversation : "", backend.channelTabResult); w.contentItem.grabToImage(r => r.saveToFile(dir + "start-done.png")) }
            else if (step === 13) w.close()
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --channel-meet-test with --open-chat=<channel id> --shots=<dir>:
    // press the channel's Meet now (prejoin.png), join with Don't use
    // audio, stay 20 s (meet.png), hang up and quit once the call has
    // ended (each state logged).
    Timer {
        running: Qt.application.arguments.indexOf("--channel-meet-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0) { if (!conversation.teamName) return; conversation.channelMeetNow() }
            else if (step === 1) { console.warn("CHMEET prejoin", preJoin.visible, preJoin.meetNow, preJoin.subject); preJoin.contentItem.grabToImage(r => r.saveToFile(dir + "prejoin.png")) }
            else if (step === 2) { preJoin.audio = "none"; preJoin.close(); preJoin.join(false, false, false) }
            else if (step >= 3 && step <= 9) console.warn("CHMEET state", backend.callState, backend.callThreadId, backend.callPeer)
            else if (step === 10) { console.warn("CHMEET in call", backend.callState, "link", backend.callInviteUrl); window.contentItem.grabToImage(r => r.saveToFile(dir + "meet.png")) }
            // --join-stay=<s>: stay that long before leaving.
            else if (step < 11 + Math.round(window.joinStay * 2 / 3)) { if (step % 10 === 0) console.warn("CHMEET staying", backend.callState) }
            else if (step === 11 + Math.round(window.joinStay * 2 / 3)) backend.hangUp()
            else if (backend.callState !== "" && backend.callState !== "ended") { console.warn("CHMEET leaving", backend.callState); return }
            else { console.warn("CHMEET left", backend.callState); Qt.quit() }
            step++
        }
    }

    // --manage-channel-test with --open-chat=<channel id> --shots=<dir>
    // [--manage-moderation=0|1|2]: open Manage channel (mc-settings.png, the
    // General setting logged), optionally pick a moderation choice and log
    // what it reads back, then Analytics (mc-analytics.png, the data
    // logged), the More options menu (mc-menu.png) and quit.
    Timer {
        running: Qt.application.arguments.indexOf("--manage-channel-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const pick = (Qt.application.arguments.find(a => a.startsWith("--manage-moderation=")) || "").slice(20)
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { window.openManageChannel(id); if (!window.manage) return }
            else if (step === 2) { console.warn("MANAGE general", manageChannel.generalSetting); shot("mc-settings") }
            else if (step === 3 && pick !== "") backend.channelAction("moderation", window.manage.teamId, id, pick)
            else if (step === 6 && pick !== "") { manageChannel.loadModeration() }
            else if (step === 8) { console.warn("MANAGE general now", manageChannel.generalSetting); manageChannel.tab = "analytics" }
            else if (step === 11) { const a = manageChannel.analyticsForTest(); console.warn("MANAGE analytics", a.failed, JSON.stringify(a.result)); shot("mc-analytics") }
            else if (step === 12) { const m = manageChannel.menuForTest(); m.show(manageChannel, manageChannel.width - 7 - m.menu.implicitWidth, 42.2) }
            else if (step === 13) shot("mc-menu")
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --channel-moderation-test=<channel id> --shots=<dir> [--moderation-on]:
    // Manage channel ▸ Moderation for a channel other than General
    // (cm-off.png, the settings logged); with --moderation-on, turn it On
    // (cm-on.png), the moderators card (cm-card.png), the channel
    // moderation list (cm-options.png), Add or remove moderators
    // (cm-dialog.png) searching "OST" (cm-search.png, the results logged),
    // then Off again (cm-after.png, logged); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--channel-moderation-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--channel-moderation-test=")) || "").slice(26)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const on = Qt.application.arguments.indexOf("--moderation-on") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { window.openManageChannel(id); if (!window.manage) return }
            const m = manageChannel.moderationForTest()
            if (step === 2) { console.warn("MOD settings", JSON.stringify(m.settings), "owners", JSON.stringify(m.owners)); shot("cm-off") }
            else if (step === 3) { if (!on) Qt.quit(); else m.change({ post: 1, replies: true, pins: true, bots: true, connectors: true, reset: true }) }
            else if (step === 5) { console.warn("MOD on", JSON.stringify(m.settings), JSON.stringify(m.moderators)); shot("cm-on") }
            else if (step === 6) m.openCardForTest()
            else if (step === 7) shot("cm-card")
            else if (step === 8) { m.closeAllForTest(); m.openOptionsForTest() }
            else if (step === 9) shot("cm-options")
            else if (step === 10) { m.closeAllForTest(); m.dialogForTest().start() }
            else if (step === 11) shot("cm-dialog")
            else if (step === 12) m.dialogForTest().searchForTest("OST")
            else if (step === 14) { const d = m.dialogForTest(); console.warn("MOD search", d.searched, JSON.stringify(d.results)); shot("cm-search") }
            else if (step === 15) { m.closeAllForTest(); m.change({ post: 0, replies: true, pins: true, bots: true, connectors: true, reset: true }) }
            else if (step === 17) { console.warn("MOD after", JSON.stringify(m.settings)); shot("cm-after") }
            else if (step === 18) Qt.quit()
            step++
        }
    }

    // --post-composer-test=<channel id> --shots=<dir> [--post-send]: Post in
    // channel (pc-open.png), a subject and body (pc-subject.png), sent with
    // --post-send; then Announcement with Navy blue, a headline,
    // subheading and body (pc-announce.png, pc-schemes.png), sent with
    // --post-send (pc-sent.png after); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--post-composer-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--post-composer-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const send = Qt.application.arguments.indexOf("--post-send") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            const c = conversation.composeForTest()
            if (step === 1) { conversation.posting = true; c.focusSubject() }
            else if (step === 2) shot("pc-open")
            else if (step === 3) { c.subject = "OST TEST 76 subject"; c.insertText("OST TEST 76 body from OST's post composer") }
            else if (step === 4) shot("pc-subject")
            else if (step === 5) { if (send) c.submit(); else { c.clear(); c.resetPost() } }
            else if (step === 8) { conversation.posting = true; c.focusSubject() }
            else if (step === 9) { c.announcement = true; c.bannerTheme = "6"; c.headline = "OST TEST 77 announcement"; c.subject = "OST subheading"; c.insertText("OST TEST 77 body") }
            else if (step === 10) shot("pc-announce")
            else if (step === 11) c.openSchemesForTest()
            else if (step === 12) shot("pc-schemes")
            else if (step === 13) { c.closeSchemesForTest(); if (send) c.submit(); else { c.clear(); c.resetPost(); conversation.posting = false } }
            else if (step === 18) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => /OST TEST 7[67]/.test(m.text || "")); console.warn("POSTS", JSON.stringify(m.map(m => ({ id: m.id, subject: m.subject, announcement: m.announcement, state: m.send_state })))); shot("pc-sent") }
            else if (step === 19) Qt.quit()
            step++
        }
    }

    // --banner-test=<channel id> --banner-file=<png> --shots=<dir>
    // [--post-send]: Announcement, Upload an image with the file (bn-empty,
    // bn-crop), zoomed 1.2 and Done (bn-composer), a headline and body,
    // sent with --post-send (bn-sent; the post logged); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--banner-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--banner-test=")) || "").slice(14)
            const file = (Qt.application.arguments.find(a => a.startsWith("--banner-file=")) || "").slice(14)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const send = Qt.application.arguments.indexOf("--post-send") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            const c = conversation.composeForTest()
            const d = c.bannerDialogForTest()
            if (step === 1) { conversation.posting = true; c.focusSubject(); c.announcement = true }
            else if (step === 2) d.start()
            else if (step === 3) shot("bn-empty")
            else if (step === 4) d.setSourceForTest("file://" + file)
            else if (step === 5) { d.zoom = 1.2; d.panX = 40 }
            else if (step === 6) shot("bn-crop")
            else if (step === 7) d.finish()
            else if (step === 8) { c.headline = "OST TEST 79 picture"; c.insertText("OST TEST 79 body from OST"); console.warn("BANNER", c.bannerImage, c.bannerImageW, c.bannerImageH) }
            else if (step === 9) shot("bn-composer")
            else if (step === 10) { if (send) c.submit(); else { c.clear(); c.resetPost(); conversation.posting = false } }
            else if (step === 16) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => /OST TEST 7[89]/.test(m.text || "")); console.warn("BANNERPOST", JSON.stringify(m.map(m => ({ id: m.id, announcement: m.announcement, state: m.send_state })))); shot("bn-sent") }
            else if (step === 17) Qt.quit()
            step++
        }
    }

    // --posts-top-test=<channel id> --shots=<dir>: See new posts at top
    // (top-list.png), Post in channel there (top-compose.png),
    // Announcement (top-announce.png), then back to new posts at the
    // bottom; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--posts-top-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--posts-top-test=")) || "").slice(17)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => (t.channels || []).some(c => c.id === id))
            if (!team) return
            if (backend.currentChatId !== id) { backend.selectChat(id, "General"); return }
            const c = conversation.composeForTest()
            if (step === 0) backend.channelAction("posts-at-top", team.id, id, "")
            else if (step === 3) { console.warn("TOP", backend.channelPostsAtTop); shot("top-list") }
            else if (step === 4) { conversation.posting = true; c.focusSubject() }
            else if (step === 5) { const cp = conversation.channelPostsForTest(); console.warn("TOPLAYOUT", c.atTop, c.post, c.y, c.height, c.boxHeight, cp.composerY, cp.composerHeight, cp.posting, cp.headerHeightForTest()); shot("top-compose") }
            else if (step === 6) { c.announcement = true }
            else if (step === 7) shot("top-announce")
            else if (step === 8) { c.resetPost(); conversation.posting = false; backend.channelAction("posts-at-bottom", team.id, id, "") }
            else if (step === 11) { console.warn("TOP after", backend.channelPostsAtTop); Qt.quit() }
            step++
        }
    }

    // --compose-rules-test=<channel id> --shots=<dir>: Teams' Everyone
    // limits (logged for 3, 51, 251 and 1,001 people, group and meeting),
    // and an announcement without a headline (cr-banner.png, not sent).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--compose-rules-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--compose-rules-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "General"); return }
            const c = conversation.composeForTest()
            if (step === 0) {
                const r = [[3, false], [51, false], [251, false], [251, true], [1001, true]].map(x => x[0] + (x[1] ? "m" : "g") + ":" + JSON.stringify(c.everyoneRowForTest(x[0], x[1])))
                console.warn("EVERYONE", r.join(" "))
                conversation.posting = true; c.announcement = true; c.insertText("body without a headline")
            }
            else if (step === 1) { c.trySubmit(); console.warn("BANNER", c.bannerText); Qt.callLater(() => window.contentItem.grabToImage(r => r.saveToFile(dir + "cr-banner.png"))) }
            else if (step === 4) { console.warn("BANNER after", JSON.stringify(c.bannerText)); c.clear(); c.resetPost(); conversation.posting = false }
            else if (step === 5) Qt.quit()
            step++
        }
    }

    // --manage-team-test=<team group id> --shots=<dir>: Manage team's
    // Channels (mt-channels.png, the rows logged), Analytics
    // (mt-analytics.png), the team row's menu (mt-menu.png); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--manage-team-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--manage-team-test=")) || "").slice(19)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === id)
            if (!team) return
            if (step === 0) window.openManageTeam(id, "channels")
            else if (step === 2) { console.warn("MTEAM rows", JSON.stringify(manageTeam.rowsForTest().map(c => [c.name, c.last_active, c.channel_type, c.shown]))); shot("mt-channels") }
            else if (step === 3) manageTeam.tab = "analytics"
            else if (step === 6) { const a = manageTeam.analyticsForTest(); console.warn("MTEAM analytics", a.failed, JSON.stringify(a.result).slice(0, 300)); shot("mt-analytics") }
            else if (step === 7) { window.manageTeamId = ""; const m = chatList.teamMenuForTest(); chatList.openTeamMenu(team, chatList, 250, 400) }
            else if (step === 8) { console.warn("MTEAM menu", JSON.stringify(chatList.teamMenuForTest().menu.items.map(i => i.label || "-"))); shot("mt-menu") }
            else if (step === 9) Qt.quit()
            step++
        }
    }

    // --create-channel-test=<team group id> --shots=<dir> [--create-name=<name>]:
    // Create a channel from the team menu (cc-empty.png, cc-types.png,
    // cc-filled.png); with --create-name, creates it as Standard / Posts and
    // logs the result; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--create-channel-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--create-channel-test=")) || "").slice(22)
            const name = (Qt.application.arguments.find(a => a.startsWith("--create-name=")) || "").slice(14)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === id)
            if (!team) return
            const d = chatList.teamMenuForTest().createChannelForTest()
            if (step === 0) d.start(team.id, team.name)
            else if (step === 1) shot("cc-empty")
            else if (step === 2) d.fillForTest(name || "OST harness channel", "", "PostReply", false)
            else if (step === 3) { d.contentItem.children[1].children[0]; shot("cc-filled-notype") }
            else if (step === 4) d.fillForTest(name || "OST harness channel", (Qt.application.arguments.find(a => a.startsWith("--create-type=")) || "--create-type=Standard").slice(14), "PostReply", false)
            else if (step === 5) shot("cc-filled")
            else if (step === 6) { if (name) d.create(); else d.close() }
            else if (step === 10) console.warn("CREATE", backend.channelActionResult)
            else if (step === 11) shot("cc-member-step")
            else if (step === 12) { console.warn("MEMBER STEP", d.memberStepForTest().opened); d.memberStepForTest().close() }
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --add-members-test=<team group id> --shots=<dir>: Add members to the
    // team (am-empty.png); search "ran" (am-search.png, logged), pick the
    // first; search "ost" and pick the group (am-picked.png, its people
    // logged), its role menu (am-role.png); a guest address and its name
    // editor (am-guest.png); Cancel (nothing is added); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--add-members-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--add-members-test=")) || "").slice(19)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === id)
            if (!team) return
            const d = chatList.teamMenuForTest().addMembersForTest()
            if (step === 0) d.start(team.id, team.thread_id, team.name)
            else if (step === 1) { console.warn("AM members", JSON.stringify(d.members)); shot("am-empty") }
            else if (step === 2) d.searchForTest("ran")
            else if (step === 4) { console.warn("AM search", JSON.stringify(d.results)); shot("am-search") }
            else if (step === 5) d.pickFirstForTest()
            else if (step === 6) d.searchForTest("ost")
            else if (step === 8) { console.warn("AM search2", JSON.stringify(d.results)); d.pickFirstForTest() }
            else if (step === 10) { console.warn("AM staged", JSON.stringify(d.staged)); shot("am-picked") }
            else if (step === 11) d.searchForTest("guest@example.com")
            else if (step === 13) shot("am-guest-option")
            else if (step === 14) { d.pickFirstForTest(); }
            else if (step === 15) shot("am-guest")
            else if (step === 16) { d.close(); console.warn("AM closed", d.opened) }
            else if (step === 17) Qt.quit()
            step++
        }
    }

    // --tags-test=<team group id> --shots=<dir> [--tags-edit]: Manage team
    // ▸ Tags (tg-list.png, the list logged), a row's menu (tg-menu.png), the
    // first tag (tg-tag.png, its people logged), Edit tag (tg-edit.png),
    // Add people searching "OST" (tg-add.png), Create a copy (tg-copy.png)
    // and Delete (tg-delete.png), all cancelled. With --tags-edit the tag's
    // description is set to "OST tag description" (tg-edited.png, logged)
    // and cleared again; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tags-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var tag: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--tags-test=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const edit = Qt.application.arguments.indexOf("--tags-edit") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { window.openManageTeam(id, "tags"); step++; return }
            const v = manageTeam.tagsForTest(), d = v.dialogForTest()
            if (step === 2) { console.warn("TAGS list", JSON.stringify(v.list)); tag = v.list && v.list.tags[0]; shot("tg-list") }
            else if (step === 3) { const m = v.rowMenuForTest(); m.tag = tag; m.parent = v; m.x = v.width - 200; m.y = 160; m.open() }
            else if (step === 4) shot("tg-menu")
            else if (step === 5) { v.rowMenuForTest().close(); v.show(tag) }
            else if (step === 7) { console.warn("TAGS people", JSON.stringify(v.people)); shot("tg-tag") }
            else if (step === 8) d.startEdit(v.open)
            else if (step === 9) shot("tg-edit")
            else if (step === 10) { d.close(); d.startAdd(v.open, v.people); d.searchForTest("OST") }
            else if (step === 12) { console.warn("TAGS search", JSON.stringify(d.results), d.searched); shot("tg-add") }
            else if (step === 13) { d.close(); d.startCopy(v.open, v.people) }
            else if (step === 14) shot("tg-copy")
            else if (step === 15) { d.close(); d.startDelete(v.open) }
            else if (step === 16) shot("tg-delete")
            else if (step === 17) { d.close(); if (!edit) Qt.quit(); else { d.startEdit(v.open); d.fillForTest(v.open.name, "OST tag description"); d.submit() } }
            else if (step === 20) { console.warn("TAGS edited", JSON.stringify(v.open)); shot("tg-edited") }
            else if (step === 21) { d.startEdit(v.open); d.fillForTest(v.open.name, ""); d.submit() }
            else if (step === 24) { console.warn("TAGS reverted", JSON.stringify(v.open)); Qt.quit() }
            step++
        }
    }

    // --team-actions-test=<team group id> --shots=<dir> [--team-leave]
    // [--team-archive]: the team menu (ta-menu.png), Teams' Archive, Leave
    // and Delete confirmations (ta-archive.png, ta-leave.png, ta-delete.png
    // with its checkbox ticked), all cancelled. --team-leave says Yes to
    // Leave (the last owner: ta-lastowner.png). --team-archive archives the
    // team (logged) and restores it; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--team-actions-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--team-actions-test=")) || "").slice(20)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const leave = Qt.application.arguments.indexOf("--team-leave") >= 0
            const archive = Qt.application.arguments.indexOf("--team-archive") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const team = teams.find(t => t.id === id)
            if (!team) return
            const tm = chatList.teamMenuForTest(), d = tm.teamActionForTest()
            if (step === 0) { tm.team = team; tm.show(chatList, 120, 200) }
            else if (step === 1) shot("ta-menu")
            else if (step === 2) { tm.menu.close(); d.start("archive", team.name) }
            else if (step === 3) shot("ta-archive")
            else if (step === 4) { d.close(); d.start("leave", team.name) }
            else if (step === 5) shot("ta-leave")
            else if (step === 6) { d.close(); d.start("delete", team.name); d.checked = true }
            else if (step === 7) shot("ta-delete")
            else if (step === 8) { d.close(); if (leave) { tm.team = team; backend.channelAction("team-leave", team.id, team.thread_id, "") } }
            else if (step === 10) { console.warn("TEAM leave", backend.channelActionResult); if (leave) shot("ta-lastowner") }
            else if (step === 11) { d.close(); if (!archive) Qt.quit(); else backend.channelAction("team-archive", team.id, team.thread_id, JSON.stringify({ readOnly: false })) }
            else if (step === 16) console.warn("TEAM archived", backend.channelActionResult, JSON.stringify((JSON.parse(backend.teamsJson || "[]").find(t => t.id === id) || {}).archived))
            else if (step === 17) backend.channelAction("team-restore", team.id, team.thread_id, "")
            else if (step === 22) { console.warn("TEAM restored", backend.channelActionResult, JSON.stringify((JSON.parse(backend.teamsJson || "[]").find(t => t.id === id) || {}).archived)); Qt.quit() }
            step++
        }
    }

    // --your-teams-test=<team group id> --shots=<dir>: See all your teams ▸
    // Your teams and channels: Teams (yt-teams, the 3 more and Sort menus,
    // no matches, Z-A), Pending invites (yt-pending), Analytics (yt-analytics,
    // Last Thirty Days), then Manage team ▸ Analytics ▸ Analytics across
    // teams (yt-across); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--your-teams-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--your-teams-test=")) || "").slice(18)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const rows = () => JSON.stringify(yourTeams.rowsForTest().map(t => [t.name, t.role, t.people, (t.channels || []).length, t["public"], t.team_type]))
            if (step === 0) chatList.openYourTeams()
            else if (step === 2) { console.warn("YT rows", rows()); shot("yt-teams") }
            else if (step === 3) yourTeams.openMoreForTest()
            else if (step === 4) shot("yt-more")
            else if (step === 5) { yourTeams.closeMenusForTest(); yourTeams.openSortForTest() }
            else if (step === 6) shot("yt-sort")
            else if (step === 7) { yourTeams.closeMenusForTest(); yourTeams.openCreateMenuForTest() }
            else if (step === 8) shot("yt-create")
            else if (step === 9) { yourTeams.closeMenusForTest(); yourTeams.setQueryForTest("zzqq") }
            else if (step === 10) shot("yt-nomatch")
            else if (step === 11) { yourTeams.setQueryForTest(""); for (const k of ["za", "type", "membership", "visibility", "az"]) { yourTeams.sort = k; console.warn("YT sort", k, rows()) } }
            else if (step === 12) { yourTeams.filter = "OWNED"; console.warn("YT owned", rows()); shot("yt-owned") }
            else if (step === 13) { yourTeams.filter = "HIDDEN"; console.warn("YT hidden", rows()); yourTeams.filter = "SHOWN"; console.warn("YT shown", rows()); yourTeams.filter = "ARCHIVED"; console.warn("YT archived", rows()); yourTeams.filter = "" }
            else if (step === 14) yourTeams.tab = "pending"
            else if (step === 16) { console.warn("YT invitations", JSON.stringify(yourTeams.invitations)); shot("yt-pending") }
            else if (step === 17) yourTeams.tab = "analytics"
            else if (step === 20) { const a = yourTeams.analyticsForTest(); console.warn("YT analytics", a.failed, a.start, a.end, JSON.stringify(a.rows).slice(0, 600)); shot("yt-analytics") }
            else if (step === 21) yourTeams.analyticsForTest().period = "last-thirty-days"
            else if (step === 24) { const a = yourTeams.analyticsForTest(); console.warn("YT analytics30", a.start, a.end); shot("yt-analytics30") }
            else if (step === 25) window.openManageTeam(id, "analytics")
            else if (step === 28) manageTeam.acrossTeams()
            else if (step === 31) { console.warn("YT across", yourTeams.visible, yourTeams.tab, chatList.yourTeamsOpen); shot("yt-across") }
            else if (step === 32) Qt.quit()
            step++
        }
    }

    // --create-team-test=<team group id> --shots=<dir>: Create team and
    // Join a team, every view, nothing submitted: the scratch dialog
    // (ct-scratch, ct-scratch2 with a name, ct-naming, ct-type), the Create
    // team page (ct-templates), a template's details (ct-tpl), its create
    // form (ct-tplform), Customize channels (ct-custom), the discard question
    // (ct-discard), From another team (ct-another) and its form (ct-clone),
    // From group (ct-group), Join a team (jt-empty) and a search (jt-search);
    // the bodies Create would send are logged; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--create-team-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--create-team-test=")) || "").slice(19)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const d = createTeamDialog
            if (step === 0) chatList.openYourTeams()
            else if (step === 1) yourTeams.createTeam()
            else if (step === 2) shot("ct-scratch")
            else if (step === 3) { d.setNameForTest("OST draft"); d.setFirstChannelForTest("") ; d.openNamingForTest() }
            else if (step === 4) shot("ct-naming")
            else if (step === 5) { d.setFirstChannelForTest("General"); console.warn("CT scratch", JSON.stringify(d.bodyForTest()), d.canCreate) ; d.setNameForTest(""); d.nameTouched = true; shot("ct-scratch2") }
            else if (step === 6) d.page = "type"
            else if (step === 7) shot("ct-type")
            else if (step === 8) { d.page = "form"; d.close(); window.openTeamPage("create") }
            else if (step === 11) { console.warn("CT templates", createTeamPage.templates.length, JSON.stringify(createTeamPage.templates.slice(0, 2))); shot("ct-templates") }
            else if (step === 12) createTeamPage.templateDialogForTest().start(createTeamPage.templates[0])
            else if (step === 15) { console.warn("CT template", JSON.stringify(createTeamPage.templateDialogForTest().details).slice(0, 800)); shot("ct-tpl") }
            else if (step === 16) { const t = createTeamPage.templateDialogForTest().details; createTeamPage.templateDialogForTest().close(); d.startTemplate({ id: t.id, name: t.name, locale: t.locale, visibility: t.visibility, channels: t.channels, app_ids: t.app_ids }) }
            else if (step === 17) { d.setNameForTest("OST draft"); shot("ct-tplform") }
            else if (step === 18) d.customizeForTest()
            else if (step === 19) shot("ct-custom")
            else if (step === 20) { d.page = "form"; console.warn("CT template body", JSON.stringify(d.bodyForTest())); d.discardForTest() }
            else if (step === 21) shot("ct-discard")
            else if (step === 22) { d.close(); createTeamPage.view = "another" }
            else if (step === 23) shot("ct-another")
            else if (step === 24) d.startClone(createTeamPage.ownedTeams.find(t => t.id === id) || createTeamPage.ownedTeams[0])
            else if (step === 25) { console.warn("CT clone body", JSON.stringify(d.bodyForTest())); shot("ct-clone") }
            else if (step === 26) { d.close(); createTeamPage.view = "group" }
            else if (step === 27) shot("ct-group")
            else if (step === 28) window.openTeamPage("join")
            else if (step === 30) shot("jt-empty")
            else if (step === 31) joinTeamPage.searchForTest("Secure")
            else if (step === 33) shot("jt-search")
            else if (step === 34) { window.teamPage = ""; Qt.quit() }
            step++
        }
    }

    // --chat-menu-test=<chat id> --shots=<dir>: the chat's menu (cm-menu),
    // Open in new window (cm-window), Manage apps (cm-apps), Set workflows
    // (cm-workflows), the Remove chat history question (cm-remove,
    // cancelled), the chat's header menu (cm-header, its items logged) and,
    // for a meeting chat, Report a concern (cm-report,
    // closed unsent); the people tagged for Notify when available are logged.
    // Nothing is changed; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--chat-menu-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property var win: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--chat-menu-test=")) || "").slice(17)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const row = chatList.rowsForTest[id]
            const chat = chatList.chats.find(c => c.id === id) || {}
            if (step === 0) { if (!row) return; row.openMenu(40, 30) }
            else if (step === 1) { console.warn("CM tagged", JSON.stringify(chatList.notifyTagged)); shot("cm-menu") }
            else if (step === 2) { row.closeMenuForTest(); win = window.openChatWindow(id, chat.name, chat.peerMri || "", "") }
            else if (step === 5) { console.warn("CM window", win.messages.length); win.contentItem.grabToImage(r => r.saveToFile(dir + "cm-window.png")) }
            else if (step === 6) { win.close(); chatList.manageChatApps(id, chat.name) }
            else if (step === 9) { console.warn("CM apps", JSON.stringify(conversation.chatAppsForTest().apps.map(a => [a.name, a.state, a.id]))); shot("cm-apps") }
            else if (step === 10) workflowsDialog.startChat(id, chat.name)
            else if (step === 13) { console.warn("CM workflows", workflowsDialog.url.replace(/userId=[^&]*/, "userId=X").replace(/tenantId=[^&]*/, "tenantId=X")); shot("cm-workflows") }
            else if (step === 14) { workflowsDialog.close(); row.removeHistoryForTest().open() }
            else if (step === 15) shot("cm-remove")
            else if (step === 16) { row.removeHistoryForTest().close(); backend.selectChat(id, chat.name) }
            else if (step === 19) conversation.chatMenuForTest().open()
            else if (step === 20) { console.warn("CM header", JSON.stringify(conversation.chatMenuForTest().items.map(i => i.separator ? "|" : i.label + (i.keys ? " " + i.keys : "")))); shot("cm-header") }
            else if (step === 21) { conversation.chatMenuForTest().close(); if (chatList.isMeeting(chat)) chatList.reportMeetingChat(id); else Qt.quit() }
            else if (step === 24) { const d = chatList.chatReportForTest(); console.warn("CM report", JSON.stringify(d.meeting), JSON.stringify(d.people), d.chatIcal ? "ical" : "no-ical"); shot("cm-report") }
            else if (step === 25) { chatList.chatReportForTest().close(); Qt.quit() }
            step++
        }
    }

    // --quick-views-test --shots=<dir>: Quick views ▸ Followed threads
    // (qv-followed, then its first thread picked: qv-followed-open) and
    // Saved (qv-saved); the rows are logged. Nothing is changed; quit.
    Timer {
        running: Qt.application.arguments.indexOf("--quick-views-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { console.warn("QV team order", JSON.stringify(JSON.parse(backend.teamsJson || "[]").map(t => t.name))); chatList.openQuick("followed") }
            else if (step === 2) { console.warn("QV followed", JSON.stringify(quickView.itemsForTest())); shot("qv-followed") }
            else if (step === 3) { const i = quickView.itemsForTest()[0]; if (i) { quickView.selectedKey = quickView.key(i); quickView.openItem(i) } }
            else if (step === 5) shot("qv-followed-open")
            else if (step === 6) chatList.openQuick("saved")
            else if (step === 9) { console.warn("QV saved", JSON.stringify(quickView.itemsForTest())); shot("qv-saved") }
            else if (step === 10) Qt.quit()
            step++
        }
    }

    // --members-test=<team group id> --shots=<dir>: Manage team ▸ Members
    // (mb-members.png, the roster logged), then Pending requests
    // (mb-pending.png, logged); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--members-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--members-test=")) || "").slice(15)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) window.openManageTeam(id, "members")
            else if (step === 3) { console.warn("MEMBERS", JSON.stringify(manageTeam.membersForTest().members)); shot("mb-members") }
            else if (step === 4) manageTeam.tab = "pending"
            else if (step === 5) manageTeam.tab = "apps"
            else if (step === 9) { console.warn("APPS", JSON.stringify(manageTeam.appsForTest().apps).slice(0, 600)); shot("mb-apps") }
            else if (step === 10) { manageTeam.appsForTest().webhookForTest().start() }
            else if (step === 11) shot("mb-webhook")
            else if (step === 12) { manageTeam.appsForTest().webhookForTest().close(); shot("mb-apps2") }
            else if (step === 13) manageTeam.tab = "pending"
            else if (step === 15) { console.warn("PENDING", manageTeam.pendingForTest().loaded, JSON.stringify(manageTeam.pendingForTest().requests)); shot("mb-pending") }
            else if (step === 16) Qt.quit()
            step++
        }
    }

    // --team-settings-test=<team group id> --shots=<dir> [--settings-write]:
    // Manage team ▸ Settings with every section open (ts-all.png, the
    // settings logged), Edit team details (ts-edit.png) and Change picture
    // (ts-picture.png), both cancelled. With --settings-write: upload custom
    // apps off then on again (logged), the description set to "Test team for
    // the OST desktop client (safe to delete)." (logged), a team code
    // generated (ts-code.png, logged) and removed; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--team-settings-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--team-settings-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const write = Qt.application.arguments.indexOf("--settings-write") >= 0
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { window.openManageTeam(id, "settings"); step++; return }
            const v = manageTeam.settingsForTest()
            // --team-picture-default: Remove + Save (Teams' default picture), then quit.
            // --team-picture-file=<png>: upload that picture instead.
            const picFile = (Qt.application.arguments.find(a => a.startsWith("--team-picture-file=")) || "").slice(20)
            if (Qt.application.arguments.indexOf("--team-picture-default") >= 0 || picFile) {
                const t = (JSON.parse(backend.teamsJson || "[]").find(t => t.id === id) || {})
                if (step === 2) backend.channelAction("team-picture", t.id, t.thread_id, JSON.stringify({ path: picFile }))
                else if (step === 5) { console.warn("TSET picture", backend.channelActionResult); shot("ts-picture-after") }
                else if (step === 6) Qt.quit()
                step++
                return
            }
            const team = (JSON.parse(backend.teamsJson || "[]").find(t => t.id === id) || {})
            if (step === 3) { console.warn("TSET", JSON.stringify(v.settings).slice(0, 400), JSON.stringify(v.tags), v.code); v.openAllForTest() }
            else if (step === 4) shot("ts-all")
            else if (step === 5) v.editDialogForTest().start(team)
            else if (step === 6) shot("ts-edit")
            else if (step === 7) { v.editDialogForTest().close(); v.pictureDialogForTest().start() }
            else if (step === 8) shot("ts-picture")
            else if (step === 9) { v.pictureDialogForTest().close(); if (!write) Qt.quit(); else v.change("userSettings", { uploadCustomApp: false }) }
            else if (step === 11) { console.warn("TSET custom off", v.user.uploadCustomApp); v.change("userSettings", { uploadCustomApp: true }) }
            else if (step === 13) { console.warn("TSET custom on", v.user.uploadCustomApp); const d = v.editDialogForTest(); d.start(team); d.setDescriptionForTest("Test team for the OST desktop client (safe to delete)."); d.done() }
            else if (step === 16) { console.warn("TSET description", team.description); backend.channelAction("team-code", team.id, team.thread_id, "generate") }
            else if (step === 18) { console.warn("TSET code", v.code); shot("ts-code") }
            else if (step === 22) backend.channelAction("team-code", team.id, team.thread_id, "remove")
            else if (step === 24) { console.warn("TSET code removed", JSON.stringify(v.code)); Qt.quit() }
            step++
        }
    }

    // --settings-pages-test --shots=<dir>: every Settings page (st-<page>, and
    // st-<page>-2 scrolled down) and General ▸ Out of office (st-oof);
    // logs what the synced settings read. Changes nothing; quit.
    Timer {
        running: Qt.application.arguments.indexOf("--settings-pages-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        readonly property var pages: ["general", "appearance", "chats", "notifications", "accounts", "privacy", "accessibility", "devices", "calls", "files", "about"]
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) rail.current = "settings"
            const i = Math.floor((step - 1) / 3), k = (step - 1) % 3
            if (step >= 1 && i < pages.length) {
                if (k === 0) settingsView.pageForTest(pages[i])
                else if (k === 1) shot("st-" + pages[i])
                else { settingsView.scrollForTest(); shot("st-" + pages[i] + "-2") }
            } else if (step === 1 + pages.length * 3) { console.warn("ST settings", backend.settingsJson.slice(0, 1500)); settingsView.pageForTest("general", "oof") }
            else if (step === 2 + pages.length * 3) shot("st-oof")
            else if (step === 3 + pages.length * 3) Qt.quit()
            step++
        }
    }

    // --pause-test --shots=<dir>: Pause notifications: the flyout and its
    // menu (pz-menu), 10 minutes (paused; pz-paused with the banner, and
    // the edit menu pz-edit), Custom's dialog (pz-custom) and its calendar
    // (pz-calendar), cancelled; then Resume (pz-resumed). Logs what the
    // flyout says. Changes only ost-test1's own status, and puts it back.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--pause-test")) && backend.signedIn && backend.userMail.length > 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const log = n => console.warn("PZ", n, "presence", titleBar.presence, "until", backend.myStatusEnds, "paused", titleBar.paused, "banner", window.dndBanner)
            // --pause-test=hold: pause 10 minutes and quit; =resume: resume and quit.
            const mode = (Qt.application.arguments.find(a => a.startsWith("--pause-test=")) || "").slice(13)
            if (mode === "hold") { if (step === 1) titleBar.pauseForTest("10 minutes"); else if (step === 4) { log("held"); Qt.quit() } step++; return }
            // =work: Set work location: the menu (wl-menu), Office (wl-office
            // and its menu wl-office-menu), Remote (wl-remote), then clear.
            if (mode === "work") {
                const lg = n => console.warn("WL", n, backend.myWorkLocation)
                if (step === 1) { lg("start"); titleBar.pauseForTest("flyout") }
                else if (step === 2) titleBar.pauseForTest("work")
                else if (step === 3) shot("wl-menu")
                else if (step === 4) titleBar.pauseForTest("Office")
                else if (step === 7) { lg("office"); titleBar.pauseForTest("flyout") }
                else if (step === 8) shot("wl-office")
                else if (step === 9) titleBar.pauseForTest("work")
                else if (step === 10) shot("wl-office-menu")
                else if (step === 11) titleBar.pauseForTest("Remote")
                else if (step === 14) { lg("remote"); titleBar.pauseForTest("flyout") }
                else if (step === 15) shot("wl-remote")
                else if (step === 16) titleBar.pauseForTest("clear")
                else if (step === 19) { lg("cleared"); Qt.quit() }
                step++; return
            }
            // =note-on: a pinned status message until today's end and a
            // 10-minute pause; =note-off: clear both.
            if (mode === "note-on" || mode === "note-off") {
                if (step === 1) backend.setStatusNote(mode === "note-on" ? "OST test 81 pinned status message" : "", mode === "note-on", "Today", "")
                else if (step === 2) titleBar.pauseForTest(mode === "note-on" ? "10 minutes" : "resume")
                else if (step === 5) { console.warn("NB", mode, backend.myNoteJson, window.noteBanner, window.dndBanner); shot("nb-" + mode) }
                else if (step === 6) Qt.quit()
                step++; return
            }
            // =oof-on: OST's Out of office on, "OST test 83 out of office",
            // for a period from now to tomorrow; =oof-off: off with the
            // message cleared (as before the tests).
            if (mode === "oof-on" || mode === "oof-off") {
                const o = settingsView.oofForTest()
                if (step === 1) { rail.current = "settings"; settingsView.pageForTest("general", "oof") }
                else if (step === 3) { console.warn("OOF before", JSON.stringify(o.setting)); o.on = mode === "oof-on"; o.typeForTest(mode === "oof-on" ? "OST test 83 out of office" : ""); o.period = mode === "oof-on"; console.warn("OOF canSave", o.canSave); shot(mode) }
                else if (step === 4) { if (o.canSave) o.save(o.value()) }
                else if (step === 7) backend.loadSettings()
                else if (step === 9) { console.warn("OOF after", JSON.stringify(JSON.parse(backend.settingsJson).mt.oof), backend.settingsError); Qt.quit() }
                step++; return
            }
            // =list-prefs: previews and time stamps on (cl-previews), filters
            // off (cl-nofilters), then all three back as they were.
            if (mode === "list-prefs") {
                const set = (k, v) => backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ [k]: v }))
                if (step === 1) { rail.current = "chat"; set("hasUserEnabledMessagePreviews", true) }
                else if (step === 3) set("hasUserEnabledShowTimeStamps", true)
                else if (step === 5) shot("cl-previews")
                else if (step === 6) set("hasUserDisabledShowingFilterAtTop", true)
                else if (step === 8) shot("cl-nofilters")
                else if (step === 9) set("hasUserDisabledShowingFilterAtTop", false)
                else if (step === 11) set("hasUserEnabledShowTimeStamps", false)
                else if (step === 13) set("hasUserEnabledMessagePreviews", false)
                else if (step === 15) backend.loadSettings()
                else if (step === 17) { console.warn("CL after", JSON.stringify(chatList.collab), backend.settingsError); shot("cl-back"); }
                else if (step === 18) Qt.quit()
                step++; return
            }
            // =profile:<mri>: open that person's profile card (pc-overview),
            // its Profile (pc-profile), Organization (pc-org) and LinkedIn
            // (pc-linkedin) tabs.
            if (mode.indexOf("profile:") === 0) {
                if (step === 1) backend.requestProfile(mode.slice(8))
                else if (step === 4) { console.warn("PC", backend.profileCardJson.slice(0, 600)); shot("pc-overview") }
                else if (step === 5) profileCard.tab = "profile"
                else if (step === 6) shot("pc-profile")
                else if (step === 7) profileCard.tab = "organization"
                else if (step === 8) shot("pc-org")
                else if (step === 9) profileCard.tab = "linkedin"
                else if (step === 10) shot("pc-linkedin")
                else if (step === 11) { profileCard.close(); Qt.quit() }
                step++; return
            }
            // =landing: mark the 1:1 with Randy unread, open it (lr-open).
            // =compact: Message density Compact (cp-compact), then Comfy again.
            if (mode === "compact") {
                const c = chatList.chats.find(c => (c.peerMri || "").indexOf("5050c9d6") >= 0)
                if (step === 1) { if (!c) { step = 0; return } rail.current = "chat"; backend.selectChat(c.id, c.name); backend.changeSetting("prop", "messageDensity", JSON.stringify("COMPACT")) }
                else if (step === 5) shot("cp-compact")
                else if (step === 6) backend.changeSetting("prop", "messageDensity", JSON.stringify("COMFY"))
                else if (step === 8) { console.warn("CP", JSON.parse(backend.settingsJson).props.messageDensity); Qt.quit() }
                step++; return
            }
            // =threads: open "OST threads test" (th-channel), its first thread
            // with a reply (th-pane).
            if (mode === "threads") {
                if (step === 1) { const t = JSON.parse(backend.teamsJson || "[]").find(t => t.name === "OST Test Team"); const c = t && t.channels.find(c => c.name === "OST threads test"); if (!c) { step = 0; return } rail.current = "chat"; backend.selectChat(c.id, c.name) }
                else if (step === 5) { console.warn("TH layout", conversation.channelLayout, conversation.threadsLayout, JSON.stringify(conversation.threadStarters(conversation.messages).map(m => [m.text, m.thread_replies, !!m.shared_in_main, m.thread_title || ""]))); shot("th-channel") }
                else if (step === 6) conversation.toggleThreads()
                else if (step === 8) { console.warn("TH list", threadsPane.shown, JSON.stringify(threadsPane.threads.map(t => [t.text, t.thread_replies, t.following, t.thread_last_text]))); shot("th-list") }
                else if (step === 9) { const s = threadsPane.threads[0]; if (s) threadsPane.openThread(s.id) }
                else if (step === 12) { console.warn("TH pane", threadsPane.rootId, threadsPane.shown, conversation.openThreadRoot); shot("th-pane") }
                else if (step === 13 && Qt.application.arguments.indexOf("--threads-send") >= 0) backend.sendThreadReply(threadsPane.channelId, threadsPane.rootId, "<p>" + Qt.application.arguments.find(a => a.startsWith("--threads-text=")).slice(15) + "</p>", "[]", "", Qt.application.arguments.indexOf("--threads-channel") >= 0)
                else if (step === 14 && Qt.application.arguments.some(a => a.startsWith("--threads-html="))) { backend.setNextPost(JSON.stringify({ threads: true })); backend.sendRich(decodeURIComponent(Qt.application.arguments.find(a => a.startsWith("--threads-html=")).slice(15))) }
                else if (step === 14 && Qt.application.arguments.some(a => a.startsWith("--threads-subject="))) { conversation.composeBox.formatting = true; conversation.composeBox.subject = Qt.application.arguments.find(a => a.startsWith("--threads-subject=")).slice(18); const body = Qt.application.arguments.find(a => a.startsWith("--threads-root=")); conversation.input.text = body ? body.slice(15) : "" }
                else if (step === 15 && Qt.application.arguments.some(a => a.startsWith("--threads-code"))) {
                    const mode = (Qt.application.arguments.find(a => a.startsWith("--threads-code=")) || "=rust").split("=")[1]
                    const c = conversation.composeBox, ed = conversation.input; c.formatting = true
                    const lines = mode === "short" ? ["let x = 1; // hi"] : ["use std::io;", "fn main() {", "    let mut s = String::new();", "    io::stdin().read_line(&mut s).unwrap();", "}"]
                    // (insert() of HTML into an empty code line resets its
                    // format, which typing doesn't: start under a plain line.)
                    ed.insert(0, "Code:")
                    for (const l of lines) { ed.cursorPosition = ed.length; c.format("codeblock", ""); ed.cursorPosition = ed.length; ed.insert(ed.length, c.escapeHtml(l).replace(/ /g, "&nbsp;")) }
                    if (mode === "rust") c.format("lang", "rust")
                    c.refreshRichState()
                    console.warn("TH code", mode, JSON.stringify(c.richRegions))
                }
                
                // Leave no draft behind.
                else if (step === 19 && (Qt.application.arguments.some(a => a.startsWith("--threads-code")) || Qt.application.arguments.indexOf("--threads-clear") >= 0)) { conversation.composeBox.clear(); conversation.composeBox.resetPost(); conversation.composeBox.formatting = false; backend.setDraft(backend.currentChatId, "") }
                else if (step === 16 && Qt.application.arguments.some(a => a.startsWith("--threads-subject="))) shot("th-subject")
                else if (step === 16 && Qt.application.arguments.some(a => a.startsWith("--threads-code"))) shot("th-code")
                else if (step === 18 && Qt.application.arguments.some(a => a.startsWith("--threads-subject=")) && Qt.application.arguments.some(a => a.startsWith("--threads-root="))) conversation.sendCompose()
                else if (step === 14 && Qt.application.arguments.some(a => a.startsWith("--threads-root="))) { conversation.input.text = Qt.application.arguments.find(a => a.startsWith("--threads-root=")).slice(15); conversation.sendCompose() }
                else if (step === 15 && Qt.application.arguments.indexOf("--threads-unread") >= 0) { const t = threadsPane.threads.find(t => t.id === threadsPane.rootId); backend.setThreadRead(t.id, "unread", t.thread_last_id) }
                else if (step === 17) threadsPane.closed()
                else if (step === 20) { console.warn("TH sent", JSON.stringify(conversation.threadStarters(conversation.messages).map(m => [m.text, m.thread_replies, !!m.shared_in_main, m.thread_read_to, m.thread_bookmark, m.thread_unread]))); shot("th-sent") }
                else if (step === 21 && Qt.application.arguments.indexOf("--threads-unread") >= 0) { const s = threadsPane.threads[0]; threadsPane.channelId = backend.currentChatId; threadsPane.openThread(s.id) }
                else if (step === 24) { console.warn("TH reopened", threadsPane.rootId); shot("th-reopen") }
                else if (step === 25) Qt.quit()
                step++; return
            }
            // =schedule: in "OST group test", open Schedule message (sc-popup),
            // schedule "OST TEST 91" for tomorrow 8:00 AM (sc-compose,
            // sc-pending), then --schedule-cancel cancels it (sc-cancelled).
            if (mode === "schedule") {
                const c = conversation.composeBox, has = f => Qt.application.arguments.indexOf(f) >= 0
                const mine = () => JSON.parse(backend.scheduledJson || "[]").filter(x => /OST TEST 9[0-9]/.test(x.message.text || ""))
                if (step === 1) { const ch = JSON.parse(backend.chatsJson || "[]").find(x => x.name === "OST group test"); if (!ch) { step = 0; return } rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
                else if (step === 5) { console.warn("SC pending before", backend.scheduledJson); c.scheduleAt = c.nextEight() + (c.nextEight() - Date.now() < 3600000 ? 86400000 : 0); conversation.input.text = "OST TEST 94 scheduled from OST"; shot("sc-compose") }
                else if (step === 6 && has("--schedule-send")) conversation.sendCompose()
                else if (step === 6 && has("--schedule-popup")) c.openScheduleForTest(c)
                else if (step === 8 && has("--schedule-popup")) shot("sc-popup")
                else if (step === 12) { console.warn("SC pending", backend.scheduledJson); shot("sc-pending") }
                else if (step === 13 && has("--schedule-edit")) { const it = conversation.scheduledItems[0]; if (it) conversation.startEdit(it) }
                else if (step === 15 && has("--schedule-edit")) shot("sc-edit")
                else if (step === 16 && has("--schedule-edit")) { const x = mine()[0]; if (x) backend.editScheduled(x.id, x.message.client_message_id || "", "<p>OST TEST 94 scheduled from OST, edited</p>", "[]", String(x.send_at_ms + 1800000)); conversation.editingId = "" }
                else if (step === 21) { console.warn("SC edited", JSON.stringify(mine().map(x => [x.message.text, new Date(x.send_at_ms).toString()]))); shot("sc-edited") }
                else if (step === 22 && has("--schedule-cancel")) { for (const x of mine()) backend.cancelScheduled(x.id) }
                else if (step === 27) { console.warn("SC after", backend.scheduledJson); shot("sc-cancelled") }
                else if (step === 28) { c.scheduleAt = 0; c.clear(); backend.setDraft(backend.currentChatId, ""); Qt.quit() }
                step++; return
            }
            // =chat:<name>[|<text>]: open that chat, jump to the first message
            // containing <text>, and shot it (chat-open).
            if (mode.startsWith("chat:")) {
                const [name, text] = mode.slice(5).split("|")
                if (step === 1) { const c = JSON.parse(backend.chatsJson || "[]").find(c => c.name === name); if (!c) { if (++chatTries > 60) Qt.quit(); step = 0; return } console.warn("CHAT id", c.id); rail.current = "chat"; backend.selectChat(c.id, c.name) }
                else if (step === 7 && text) { const m = conversation.messages.find(m => (m.text || "").indexOf(text) >= 0 || (m.html || "").indexOf(text) >= 0); console.warn("CHAT jump", m ? m.id : "none"); if (m) conversation.jumpToMessage(m.id) }
                else if (step === 9) { console.warn("CHAT kinds", JSON.stringify(conversation.messages.filter(m => (m.text || m.html || "").indexOf(text || "~") >= 0).slice(0, 6).map(m => [m.kind, (m.text || "").slice(0, 80)]))); shot("chat-open") }
                else if (step === 10) Qt.quit()
                step++; return
            }
            // =livecall: log the chats' live calls.
            if (mode === "livecall") {
                if (step === 10) { console.warn("LIVE chats", JSON.parse(backend.chatsJson || "[]").length); for (const c of JSON.parse(backend.chatsJson || "[]")) if (c.liveCall) console.warn("LIVE", c.name, JSON.stringify(c.liveCall)) }
                else if (step === 11) Qt.quit()
                step++; return
            }
            // =layouts: log every channel's layout.
            if (mode === "layouts") {
                if (step === 3) { console.warn("LAY", JSON.stringify(JSON.parse(backend.teamsJson || "[]").map(t => [t.name, (t.channels || []).map(c => [c.name, c.layout, c.id.slice(0, 16)])]))); Qt.quit() }
                step++; return
            }
            // =followed: log Quick views ▸ Followed threads' rows.
            if (mode === "followed") {
                if (step === 1) backend.channelAction("quick-followed", "", "", "")
                else if (step === 4) { const r = JSON.parse(backend.channelActionResult || "{}"); console.warn("FT", JSON.stringify((r.data || []).map(i => [i.parent_preview, i.thread_id.slice(0, 12)]).slice(0, 6))); Qt.quit() }
                step++; return
            }
            if (mode === "landing") {
                const c = chatList.chats.find(c => (c.peerMri || "").indexOf("5050c9d6") >= 0)
                if (step === 1) { if (!c) { step = 0; return } backend.setChatUnread(c.id, true) }
                else if (step === 6) { rail.current = "chat"; backend.selectChat(c.id, c.name) }
                else if (step === 10) { console.warn("LR", JSON.stringify(JSON.parse(backend.messagesJson || "[]").filter(m => m.first_unread).map(m => m.id))); shot("lr-open") }
                else if (step === 16) Qt.quit()
                step++; return
            }
            if (mode === "wl-office" || mode === "wl-clear") { if (step === 1) titleBar.pauseForTest(mode === "wl-office" ? "Office" : "clear"); else if (step === 4) { console.warn("WL", mode, backend.myWorkLocation); Qt.quit() } step++; return }
            if (mode === "resume") { if (step === 1) titleBar.pauseForTest("resume"); else if (step === 4) { log("resumed"); Qt.quit() } step++; return }
            if (step === 1) { log("start"); titleBar.pauseForTest("flyout") }
            else if (step === 2) titleBar.pauseForTest("menu")
            else if (step === 3) { console.warn("PZ dbg", titleBar.pauseForTest("dbg")); shot("pz-menu") }
            else if (step === 4) titleBar.pauseForTest("10 minutes")
            else if (step === 7) { log("paused"); titleBar.pauseForTest("flyout") }
            else if (step === 8) shot("pz-paused")
            else if (step === 9) titleBar.pauseForTest("edit")
            else if (step === 10) shot("pz-edit")
            else if (step === 11) titleBar.pauseForTest("custom")
            else if (step === 12) shot("pz-custom")
            else if (step === 13) titleBar.pauseForTest("calendar")
            else if (step === 14) shot("pz-calendar")
            else if (step === 15) titleBar.pauseForTest("close")
            else if (step === 16) titleBar.pauseForTest("resume")
            else if (step === 19) { log("resumed"); titleBar.pauseForTest("flyout") }
            else if (step === 20) shot("pz-resumed")
            else if (step === 21) { titleBar.pauseForTest("close"); Qt.quit() }
            step++
        }
    }

    // --tab-drag-test=<tab>,<onto>[,drop] --open-chat=<channel> --shots=<dir>:
    // pick up the tab, hold it over Shared (td-fixed) and over <onto>
    // (td-over), then drop it there (saved) or cancel; log the tabs; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-drag-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const a = (Qt.application.arguments.find(a => a.startsWith("--tab-drag-test=")) || "").slice(16).split(",")
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) { if (conversation.tabNames.indexOf(a[0]) < 0) return; console.warn("TD before", JSON.stringify(conversation.tabNames)); conversation.tabDragForTest("start", a[0]) }
            else if (step === 1) { console.warn("TD fixed over", conversation.tabDragForTest("over", "Shared"), "canDrop", conversation.tabDragCanDrop) }
            else if (step === 2) shot("td-fixed")
            else if (step === 3) { console.warn("TD over", conversation.tabDragForTest("over", a[1]), "canDrop", conversation.tabDragCanDrop) }
            else if (step === 4) shot("td-over")
            else if (step === 5) conversation.tabDragForTest(a[2] === "drop" ? "drop" : "cancel")
            else if (step === 6) { console.warn("TD after", JSON.stringify(conversation.tabNames)); shot("td-after") }
            else if (step === 9) { console.warn("TD reloaded", JSON.stringify(conversation.tabNames), backend.channelTabsJson.length); Qt.quit() }
            step++
        }
    }

    // --channel-op=<op> --channel-team=<team group id> --channel-name=<name>
    // [--channel-arg=<arg>]: run one channel action on the named channel of
    // that team and log the result; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--channel-op=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith("--" + k + "=")) || "").slice(k.length + 3)
            const team = (JSON.parse(backend.teamsJson || "[]").find(t => t.id === arg("channel-team")))
            if (!team) return
            const ch = (team.channels || []).find(c => c.name === arg("channel-name"))
            if (step === 0) { if (!ch) { console.warn("CHANNEL-OP no channel", arg("channel-name")); Qt.quit(); return } backend.channelAction(arg("channel-op"), team.id, ch.id, arg("channel-arg")) }
            else if (step === 3) { console.warn("CHANNEL-OP", backend.channelActionResult); Qt.quit() }
            step++
        }
    }

    // --channel-owner-test=<team group id> --shots=<dir>: on the OST test
    // channels: the owner menu (co-menu.png) and the Archive / Delete
    // dialogs (co-archive.png, co-delete.png); then Restore "OST test
    // channel 2", Recommend / Stop recommending "OST test channel", Archive
    // and Restore it, create "OST test channel 4" and Delete it, logging
    // each result and what the team list then says; quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--channel-owner-test=")) && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        property string made: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--channel-owner-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.id === id)
            if (!team) return
            const ch = n => team.channels.find(c => c.name === n) || {}
            const log = tag => console.warn("OWNER", tag, backend.channelActionResult, JSON.stringify(team.channels.map(c => [c.name, c.archived, c.recommended])))
            const m = chatList.channelMenuForTest()
            if (step === 0) { chatList.openChannelMenu(ch("OST test channel"), team, chatList, 250, 300) }
            else if (step === 1) { console.warn("OWNER menu", JSON.stringify(m.menu.items.map(i => i.label || "-"))); shot("co-menu") }
            else if (step === 2) { m.closeAllForTest(); m.channel = ch("OST test channel"); m.archiveForTest() }
            else if (step === 3) shot("co-archive")
            else if (step === 4) { m.closeAllForTest(); m.deleteForTest() }
            else if (step === 5) shot("co-delete")
            else if (step === 6) { m.closeAllForTest(); backend.channelAction("restore", team.id, ch("OST test channel 2").id || "19:e1974817d2fe48858ad1cb8f9df219bb@thread.tacv2", "") }
            else if (step === 9) { log("restore 2"); backend.channelAction("archive", team.id, ch("OST test channel").id, "{}") }
            else if (step === 12) { log("archive 1"); backend.channelAction("restore", team.id, ch("OST test channel").id, "") }
            else if (step === 15) { log("restore 1"); backend.channelAction("create-channel", team.id, ch("General").id, JSON.stringify({ name: "OST test channel 4", type: "Standard", layout: "PostReply" })) }
            else if (step === 17) { log("create 4"); const r = JSON.parse(backend.channelActionResult); made = r.data ? r.data.id : ""; if (made) backend.channelAction("delete-channel", team.id, made, "") }
            else if (step === 19) { log("delete 4"); backend.channelAction("hide-all", team.id, ch("General").id, "") }
            else if (step === 22) { log("hide-all"); team.channels.forEach(c => backend.channelAction("show", team.id, c.id, "")) }
            else if (step === 25) { log("show all"); Qt.quit() }
            step++
        }
    }

    // --row-menu-test=<channel id> --shots=<dir>: with
    // OST group test open, the channel row's ··· menu (rowmenu.png); quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--row-menu-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--row-menu-test=")) || "").slice(16)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => (t.channels || []).some(c => c.id === id))
            if (!team) return
            if (step === 0) backend.selectChat("19:ef213c7c46cf4036b11608300e96fee4@thread.v2", "OST group test")
            else if (step === 2) { const m = chatList.channelMenuForTest(); chatList.openChannelMenu(team.channels.find(c => c.id === id), team, chatList, 200, 400); console.warn("ROWMENU", backend.currentChatId, chatList.currentId, JSON.stringify(m.menu.items.map(i => i.label || "-"))) }
            else if (step === 3) window.contentItem.grabToImage(r => r.saveToFile(dir + "rowmenu.png"))
            else if (step === 4) Qt.quit()
            step++
        }
    }

    // --workflows-test with --open-chat=<channel id> --shots=<dir>: open
    // the channel's Workflows (wf.png after 15 s) and quit.
    Timer {
        running: Qt.application.arguments.indexOf("--workflows-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (step === 0) { window.openWorkflows(id); if (!workflowsDialog.opened) return }
            else if (step === 5) { console.warn("WORKFLOWS", workflowsDialog.url, !!workflowsDialog.about); window.contentItem.grabToImage(r => r.saveToFile(dir + "wf.png")) }
            else if (step === 6) { workflowsDialog.close(); Qt.quit() }
            step++
        }
    }

    // --channel-window-test with --open-chat=<channel id> --shots=<dir>:
    // open the channel in a new window (cwin.png), move the main window to
    // another chat, post from the window (cwin-posted.png, logged), quit.
    Timer {
        running: Qt.application.arguments.indexOf("--channel-window-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var w: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => { if (w) w.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png")) }
            if (step === 0) { w = window.openChannelWindow(id); if (!w) return }
            else if (step === 3) { console.warn("CWIN", w.title, w.messages.length); shot("cwin") }
            else if (step === 4) backend.selectChat("19:ef213c7c46cf4036b11608300e96fee4@thread.v2", "OST group test")
            else if (step === 5) { w.postsForTest().startPost(); w.composeForTest().insertText("OST TEST 73 post from OST's channel window") }
            else if (step === 6) w.composeForTest().submit()
            else if (step === 11) { const p = w.messages.filter(m => (m.text || "").indexOf("OST TEST 73") >= 0); console.warn("CWIN posted", p.length, p.length ? p[0].id + " " + (p[0].send_state || "") : "", "main", backend.currentChatId); shot("cwin-posted") }
            else if (step === 12) w.close()
            else if (step === 13) Qt.quit()
            step++
        }
    }

    // --channel-visibility-test=hide|show with --open-chat=<channel id>:
    // hide or show the channel, log the list after 15 s and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--channel-visibility-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const op = (Qt.application.arguments.find(a => a.startsWith("--channel-visibility-test=")) || "").slice(26)
            const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => (t.channels || []).some(c => c.id === id))
            if (!team) return
            const ch = team.channels.find(c => c.id === id)
            if (step === 0) { console.warn("CVIS before", ch.shown); backend.channelAction(op, team.id, id, "") }
            else if (step === 5) backend.channelAction("notify-load", team.id, id, "")
            else if (step === 6) { console.warn("CVIS after", ch.shown, backend.channelActionResult); Qt.quit() }
            step++
        }
    }

    // --channel-actions-test with --open-chat=<channel id>: Manage
    // notifications All, then back to @mentions and replies; Hide, then
    // Show; Copy link (held 20 s for wl-paste). Each state is logged from
    // the reloaded team list.
    Timer {
        running: Qt.application.arguments.indexOf("--channel-actions-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (!conversation.teamName) return
            const c = () => JSON.stringify({ notify: conversation.channelInfo.notify, shown: conversation.channelInfo.shown })
            const act = (op, arg) => backend.channelAction(op, conversation.teamId, id, arg || "")
            if (step === 0) { console.warn("CACT start", c()); act("notify", "all") }
            else if (step === 2) { console.warn("CACT after all", c(), backend.channelActionResult); act("notify", "mentions") }
            else if (step === 4) { console.warn("CACT after mentions", c(), backend.channelActionResult); act("hide") }
            else if (step === 6) { console.warn("CACT after hide", c(), backend.channelActionResult); act("show") }
            else if (step === 8) { console.warn("CACT after show", c(), backend.channelActionResult); act("copy-link", conversation.chatName); console.warn("CACT copied") }
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --channel-menu-test with --open-chat=<channel id> --shots=<dir>: the
    // channel header's ··· (cmenu.png), Manage notifications (cnotify.png),
    // Customize (ccustom.png), Edit channel (cedit.png) and Get email
    // address (cemail.png); then quit.
    Timer {
        running: Qt.application.arguments.indexOf("--channel-menu-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            const cm = conversation.channelMenuForTest2()
            if (step === 0) { if (!conversation.teamName) return; console.warn("CMENU channel", JSON.stringify(conversation.channelInfo)); cm.show(conversation, conversation.width - 43 + 32 + 6.3 - cm.menu.implicitWidth, 61 + 4.9 - 14) }
            else if (step === 1) shot("cmenu")
            else if (step === 2) cm.openNotifyForTest()
            else if (step === 3) shot("cnotify")
            else if (step === 4) { cm.closeAllForTest(); cm.customizeForTest() }
            else if (step === 6) shot("ccustom")
            else if (step === 7) { cm.closeAllForTest(); cm.editForTest() }
            else if (step === 8) shot("cedit")
            else if (step === 9) { cm.closeAllForTest(); cm.emailForTest() }
            else if (step === 11) { console.warn("CMENU email", backend.channelActionResult); shot("cemail") }
            else if (step === 12) { cm.closeAllForTest(); Qt.quit() }
            step++
        }
    }

    // --thread-window-view=<post id> with --open-chat=<channel id>
    // --shots=<dir>: open that post's window, capture it at the top
    // (view-top.png) and with the newest reply's hover bar up (view-bar.png).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--thread-window-view=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var w: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const rootId = (Qt.application.arguments.find(a => a.startsWith("--thread-window-view=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (step === 0) {
                if (backend.currentChatId !== id) {
                    const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                    if (ch) backend.selectChat(ch.id, ch.name)
                    return
                }
                if (!conversation.teamName) return
                w = conversation.openThreadWindow({ id: rootId, root_id: rootId })
            }
            else if (step === 3) { w.flickForTest().contentY = 0; w.contentItem.grabToImage(r => r.saveToFile(dir + "view-top.png")) }
            else if (step === 4) { const r = w.replies[w.replies.length - 1]; if (r) w.hostForTest().forceChannelBarId = r.id; w.flickForTest().contentY = w.flickForTest().contentHeight - w.flickForTest().height }
            else if (step === 5) w.contentItem.grabToImage(r => r.saveToFile(dir + "view-bar.png"))
            else if (step === 6) { w.close(); const p = conversation.messages.find(m => m.id === rootId); if (p) conversation.openMessageMenu(p, conversation, false, conversation.width - 400, 150, "post") }
            else if (step === 7) window.contentItem.grabToImage(r => r.saveToFile(dir + "view-postmenu.png"))
            else if (step === 8) Qt.quit()
            step++
        }
    }

    // --thread-window-test=<post id> with --open-chat=<channel id>
    // --shots=<dir>: open that post's conversation in a new window
    // (thread.png), its More channel options (thread-menu.png); move the
    // main window to another chat, then reply from the window, react to the
    // reply and edit it (each logged; thread-*.png), and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--thread-window-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var w: null
        property string replyId: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const rootId = (Qt.application.arguments.find(a => a.startsWith("--thread-window-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => { if (w) w.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png")) }
            if (step === 0) {
                if (backend.currentChatId !== id) {
                    const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                    if (ch) backend.selectChat(ch.id, ch.name)
                    return
                }
                if (!conversation.teamName) return
                w = conversation.openThreadWindow({ id: rootId, root_id: rootId })
            }
            const t = w ? w.thread : []
            if (step === 3) { console.warn("THREADWIN", w.title, w.width, w.height, t.length, JSON.stringify(t.map(m => m.text))); shot("thread") }
            else if (step === 4) w.moreMenuForTest()
            else if (step === 5) shot("thread-menu")
            else if (step === 6) { w.contentItem.forceActiveFocus(); const g = JSON.parse(backend.chatsJson || "[]").find(c => c.title === "OST group test" || c.name === "OST group test"); backend.selectChat(g ? g.id : "19:ef213c7c46cf4036b11608300e96fee4@thread.v2", "OST group test") }
            else if (step === 8) { console.warn("THREADWIN main now", backend.currentChatId); w.composeForTest().insertText("OST TEST 71 reply from OST's thread window") }
            else if (step === 9) w.send()
            else if (step === 14) {
                const r = t.filter(m => m.mine && (m.text || "").indexOf("OST TEST 71") >= 0).pop()
                console.warn("THREADWIN replied", t.length, r ? r.id + " " + (r.send_state || "") : "none")
                replyId = r ? r.id : ""
                shot("thread-sent")
            }
            else if (step === 15 && replyId) w.hostForTest().react(replyId, "yes", true)
            else if (step === 19) { const r = t.find(m => m.id === replyId); console.warn("THREADWIN reacted", r ? JSON.stringify((r.reactions || []).map(x => x.key + ":" + x.count)) : "none"); shot("thread-reacted") }
            else if (step === 20 && replyId) backend.editMessageRich(replyId, "<p>OST TEST 71 reply from OST's thread window (edited)</p>", "", "[]")
            else if (step === 24) { const r = t.find(m => m.id === replyId); console.warn("THREADWIN edited", r ? r.text + " edited=" + r.edited : "none", "main", backend.currentChatId); shot("thread-edited") }
            else if (step === 25 && replyId) { const r = t.find(m => m.id === replyId); w.hostForTest().openMessageMenu(r, w.contentItem, false, 100, 100, "reply") }
            else if (step === 26) shot("thread-reply-menu")
            else if (step === 27) { w.hostForTest().messageMenu.close(); w.close() }
            else if (step === 28) Qt.quit()
            step++
        }
    }

    // --tab-shot=<tab name> with --open-chat=<channel id> --shots=<dir>:
    // open that channel tab, capture it after 12 s (tab.png) and quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-shot=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--tab-shot=")) || "").slice(11)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels), []).find(c => c.id === id)
                if (ch) backend.selectChat(ch.id, ch.name)
                return
            }
            if (step === 0 && conversation.tabNames.indexOf(name) < 0) return
            if (step === 0) conversation.tab = name
            else if (step === 4) window.contentItem.grabToImage(r => r.saveToFile(dir + "tab.png"))
            else if (step === 5) Qt.quit()
            step++
        }
    }

    // --status-mention-test --shots=<dir>: type "OST status mention @OST"
    // in Set status message, pick the suggestion, capture, save, log the
    // result, then clear the note and quit.
    Timer {
        running: Qt.application.arguments.indexOf("--status-mention-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (step === 0) titleBar.profilePageForTest("note")
            else if (step === 1) titleBar.noteTypeForTest("OST status mention @OST")
            else if (step === 2) { console.warn("NOTEM people", backend.peopleJson, titleBar.noteHtmlForTest().length); window.contentItem.grabToImage(r => r.saveToFile(dir + "note-picker.png")) }
            else if (step === 3) console.warn("NOTEM picked", titleBar.notePickForTest(), titleBar.noteHtmlForTest())
            else if (step === 4) { window.contentItem.grabToImage(r => r.saveToFile(dir + "note-picked.png")); titleBar.noteSaveForTest() }
            else if (step === 6) { console.warn("NOTEM saved", backend.statusNoteResult); titleBar.profilePageForTest("main") }
            else if (step === 7) window.contentItem.grabToImage(r => r.saveToFile(dir + "note-flyout.png"))
            else if (step === 30) { console.warn("NOTEM presence", backend.myNoteJson); titleBar.profilePageForTest("main") }
            else if (step === 31) window.contentItem.grabToImage(r => r.saveToFile(dir + "note-flyout-polled.png"))
            // (Teams on winpc can be checked meanwhile.)
            else if (step === 34) backend.setStatusNote("", false, "Never", "")
            else if (step === 36) { console.warn("NOTEM cleared", backend.statusNoteResult); Qt.quit() }
            step++
        }
    }

    // --chat-shot with --open-chat=<id> --shots=<dir>: open the chat,
    // capture it once it has loaded (chat.png) and quit.
    Timer {
        running: Qt.application.arguments.indexOf("--chat-shot") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST chat"); return }
            if (step === 2) window.contentItem.grabToImage(r => r.saveToFile(dir + "chat.png"))
            else if (step === 3) Qt.quit()
            step++
        }
    }

    // --agent-add-test=<app name> with --open-chat=<id> --shots=<dir>: open
    // the agent Store, open that app's details from it and press Add, as a
    // user would; logs the result and quits.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--agent-add-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--agent-add-test=")) || "").slice(17)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "agentadd-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST agent test"); return }
            const s = agentStore.store
            if (step === 0) agentStore.show(id, conversation.isChannel)
            else if (step < 12 && (!s || s.loading)) { step++; return }
            else if (step < 13) {
                let app = null
                for (const c of (s.collections || [])) for (const a of c.apps) if (!app && a.name === name) app = a
                console.warn("AGENTADD found", JSON.stringify(app ? { id: app.id, name: app.name } : null))
                if (!app) { Qt.quit(); return }
                agentStore.openApp(app.id); step = 13; return
            }
            else if (step === 15) shot("details")
            else if (step === 16) appDetails.addOrOpen()
            else if (step === 20) { console.warn("AGENTADD result", backend.appAddedJson); shot("after") }
            else if (step === 21) { aboutBot.close(); Qt.quit() }
            step++
        }
    }

    // --agent-store-test with --open-chat=<id> --shots=<dir>: the @ picker
    // (its Add agent row), then Teams' agent Store: overview, scrolled,
    // See all, a search for "poll"; logs what loaded, then quits.
    Timer {
        running: Qt.application.arguments.indexOf("--agent-store-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "agents-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).flatMap(t => t.channels).find(c => c.id === id)
                backend.selectChat(id, ch ? ch.name : "OST agent test"); return
            }
            const c = conversation.composeForTest()
            const s = agentStore.store
            if (step === 0) { if (conversation.isChannel) conversation.posting = true; c.focusEditor(); c.mentionForTest("@") }
            else if (step === 1) shot("picker")
            else if (step === 2) { c.clearForTest(); agentStore.show(id, conversation.isChannel) }
            else if (step > 2 && step < 13) {
                // Wait for the Store (up to ~25 s), then log and capture it.
                if ((!s || s.loading) && step < 12) { step++; return }
                console.warn("AGENTS loaded", JSON.stringify(s ? { installed: (s.installed || []).map(a => a.name), collections: (s.collections || []).map(x => x.title + " (" + x.apps.length + "): " + x.apps.slice(0, 3).map(a => a.name).join(", ")), error: s.error || "" } : null))
                shot("overview"); step = 14; return
            }
            else if (step === 14) agentStore.scrollForTest(600)
            else if (step === 15) shot("scrolled")
            else if (step === 16) { agentStore.seeAll = agentStore.collections[0] || null }
            else if (step === 17) shot("seeall")
            else if (step === 18) { agentStore.seeAll = null; agentStore.searchForTest("poll") }
            else if (step === 21) { const f = agentStore.found; console.warn("AGENTS search", JSON.stringify(f ? (f.results || []).map(a => a.name) : null)); shot("search") }
            else if (step === 22) { agentStore.close(); Qt.quit() }
            step++
        }
    }

    // --mention-test=<query> with --open-chat=<id> --shots=<dir>: type a
    // message with "@<query>", capture the picker, pick the first row (or
    // row --mention-pick=<n>),
    // capture, send it and log the newest message.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--mention-test=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const q = (Qt.application.arguments.find(a => a.startsWith("--mention-test=")) || "").slice(15)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "mention-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).flatMap(t => t.channels).find(c => c.id === id)
                backend.selectChat(id, ch ? ch.name : "OST mention test"); return
            }
            const c = conversation.composeForTest()
            const text = (Qt.application.arguments.find(a => a.startsWith("--mention-text=")) || "--mention-text=OST test 54: mention for ").slice(15)
            if (step === 0) { if (conversation.isChannel) conversation.posting = true; conversation.setPlain(text); c.focusEditor(); c.mentionForTest("@" + q) }
            else if (step === 1) { shot("picker"); console.warn("MENTION-TEST targets", JSON.stringify(c.channelMention), JSON.stringify(c.teamMention), JSON.stringify(c.tagMentions), conversation.chatName, conversation.teamId) }
            else if (step === 2) c.pickMentionForTest(parseInt((Qt.application.arguments.find(a => a.startsWith("--mention-pick=")) || "--mention-pick=0").slice(15)))
            else if (step === 3) { c.insertText("check"); shot("picked"); console.warn("MENTION-TEST editor", c.formattedText().replace(/\n/g, " ").slice(-400)) }
            else if (step === 4) conversation.sendForTest()
            else if (step === 6) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("MENTION-TEST newest", JSON.stringify({ html: m.html, state: m.send_state })); Qt.quit() }
            step++
        }
    }

    // --share-contact-test=<query> with --open-chat=<id> --shots=<dir>:
    // "@", Share someone's contact info, pick the first match, OK, add
    // text, capture each step, send and log the newest message.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--share-contact-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const q = (Qt.application.arguments.find(a => a.startsWith("--share-contact-test=")) || "").slice(21)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "share-" + n + ".png"))
            if (backend.currentChatId !== id) { const c0 = chatList.chats.find(c => c.id === id); backend.selectChat(id, c0 ? c0.name : "OST share test"); return }
            const c = conversation.composeForTest()
            const d = c.shareContactForTest()
            if (step === 0) { c.focusEditor(); c.mentionForTest("@") }
            else if (step === 1) shot("picker")
            else if (step === 2) c.pickShareForTest()
            else if (step === 3) d.typeForTest(q)
            else if (step === 5) shot("results")
            else if (step === 6) d.pickFirstForTest()
            else if (step === 7) shot("picked")
            else if (step === 8) d.okForTest()
            else if (step === 9) { c.insertText("OST TEST 65 shared from OST"); shot("compose"); console.warn("SHARE-TEST editor", c.formattedText().replace(/\n/g, " ").slice(-500)) }
            else if (step === 10) conversation.sendForTest()
            else if (step === 13) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("SHARE-TEST newest", JSON.stringify({ html: m.html, state: m.send_state })); shot("sent") }
            else if (step === 14) Qt.quit()
            step++
        }
    }

    // --add-people-test=<query> with --open-chat=<id> --shots=<dir>: open
    // the roster flyout, capture it, open Add, type the query, capture the
    // matches, pick the first, choose 3 days, capture, then Cancel (nobody
    // is added unless --add-people-confirm is given).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--add-people-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const q = (Qt.application.arguments.find(a => a.startsWith("--add-people-test=")) || "").slice(18)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "add-" + n + ".png"))
            if (backend.currentChatId !== id) { const c0 = chatList.chats.find(c => c.id === id); backend.selectChat(id, c0 ? c0.name : "OST add test"); return }
            const d = conversation.addPeopleForTest()
            if (step === 1) conversation.openParticipantsForTest()
            else if (step === 2) shot("roster")
            else if (step === 3) conversation.openAddPeople()
            else if (step === 4) d.typeForTest(q)
            else if (step === 6) shot("matches")
            else if (step === 7) { d.pickFirstForTest(); d.history = 1; d.days = 3 }
            else if (step === 8) shot("picked")
            else if (step === 9) { if (Qt.application.arguments.indexOf("--add-people-confirm") >= 0) d.finish(); else d.close() }
            else if (step === 12) { console.warn("ADD-TEST members", backend.chatMembersJson); Qt.quit() }
            step++
        }
    }

    // --remove-member-test=<mail> with --open-chat=<id> --shots=<dir>: open
    // the roster, capture it with that member's remove button shown, open
    // Teams' remove dialog, capture, Remove, log the roster after.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--remove-member-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const mail = (Qt.application.arguments.find(a => a.startsWith("--remove-member-test=")) || "").slice(21).toLowerCase()
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "remove-" + n + ".png"))
            if (backend.currentChatId !== id) { const c0 = chatList.chats.find(c => c.id === id); backend.selectChat(id, c0 ? c0.name : "OST remove test"); return }
            const roster = JSON.parse(backend.chatMembersJson || "[]")
            const m = roster.find(x => (x.mail || "").toLowerCase() === mail)
            const d = conversation.memberRemoveDialogForTest()
            if (step === 1) conversation.openParticipantsForTest()
            else if (step === 2) shot("roster")
            else if (step === 3) { if (!m) { console.warn("REMOVE-TEST not in the chat"); Qt.quit() } else d.start({ mri: m.mri, name: m.name }) }
            else if (step === 4) shot("dialog")
            else if (step === 5) d.confirm()
            else if (step === 8) { console.warn("REMOVE-TEST members", backend.chatMembersJson); shot("after") }
            else if (step === 9) Qt.quit()
            step++
        }
    }

    // --format-bar-test=<label> with --open-chat=<id> --shots=<dir>: open the
    // formatting bar, capture it and its More options, build a message with
    // a highlight, a colour, Large, a quote, inline code and a code block
    // through the bar's commands, capture it, send it (with --format-send)
    // and log what went out.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--format-bar-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const label = (Qt.application.arguments.find(a => a.startsWith("--format-bar-test=")) || "").slice(18)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "fmt-" + n + ".png"))
            if (backend.currentChatId !== id) { const c0 = chatList.chats.find(c => c.id === id); backend.selectChat(id, c0 ? c0.name : "OST format test"); return }
            const c = conversation.composeForTest()
            const bar = c.formatBarForTest()
            // --format-skip=quote,codeblock leaves those out.
            const skip = (Qt.application.arguments.find(a => a.startsWith("--format-skip=")) || "--format-skip=").slice(14).split(",")
            const line = (t, op, arg) => { if (skip.indexOf(op) < 0) { console.warn("FMT-TEST", op); c.formatLineForTest(t, op, arg) } }
            if (step === 0) { c.clear(); c.formatting = true; c.focusEditor() }
            else if (step === 1) shot("bar")
            else if (step === 2) bar.openOverflowForTest()
            else if (step === 3) shot("more")
            else if (step === 4) line(label + " highlighted", "bg", "#FDD472")
            else if (step === 5) line("red text", "fg", "#B6424C")
            else if (step === 6) line("large text", "size", "24")
            else if (step === 7) line("a quote", "quote", "")
            else if (step === 8) line("inline code", "code", "")
            else if (step === 9) line("Heading two", "heading", "2")
            else if (step === 10) { line("", "codeblock", ""); if (skip.indexOf("codeblock") < 0) c.insertText("let x = 1;") }
            else if (step === 11) { shot("compose"); console.warn("FMT-TEST export", c.formattedText()) }
            else if (step === 12) { if (Qt.application.arguments.indexOf("--format-send") >= 0) conversation.sendForTest(); else Qt.quit() }
            else if (step === 16) { const m = JSON.parse(backend.messagesJson || "[]").filter(m => m.mine).pop(); console.warn("FMT-TEST sent", JSON.stringify({ html: m.html, flow: m.flow })); shot("sent") }
            else if (step === 17) Qt.quit()
            step++
        }
    }

    // --rename-test=<name> with --open-chat=<id>: rename the group chat,
    // log the chat list's name for it, then quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--rename-test=")) && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const name = (Qt.application.arguments.find(a => a.startsWith("--rename-test=")) || "").slice(14)
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST rename test"); return }
            if (step === 0) backend.renameChat(name)
            else if (step === 2) { const c = JSON.parse(backend.chatsJson || "[]").find(c => c.id === id); console.warn("RENAME-TEST", c ? c.name : "?", backend.currentChatName); Qt.quit() }
            step++
        }
    }

    // --menu-actions-test with --open-chat=<id> --shots=<dir>: in a test
    // chat, save the newest message from someone else, unsave saved ones,
    // pin then unpin it, load your newest message's readers, open the menu
    // (captured), and mark the first one unread; each step logged.
    Timer {
        running: Qt.application.arguments.indexOf("--menu-actions-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST menu test"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.deleted)
            const theirs = msgs.filter(m => !m.mine).pop(), mine = msgs.filter(m => m.mine).pop()
            if (step === 0) { console.warn("MENU-TEST save", theirs.id); backend.setMessageSaved(theirs.id, true) }
            else if (step === 1) { const sv = msgs.filter(m => m.saved && m.id !== theirs.id); console.warn("MENU-TEST unsave", sv.map(m => m.id)); sv.forEach(m => backend.setMessageSaved(m.id, false)) }
            else if (step === 2) { console.warn("MENU-TEST pin", theirs.id); backend.setMessagePinned(theirs.id, true) }
            else if (step === 4) { console.warn("MENU-TEST pinned now", msgs.filter(m => m.pinned).map(m => m.id)); backend.setMessagePinned(theirs.id, false) }
            else if (step === 6) { console.warn("MENU-TEST pinned after unpin", msgs.filter(m => m.pinned).map(m => m.id)); backend.loadMessageReaders(mine.id) }
            else if (step === 7) { console.warn("MENU-TEST readers", backend.messageReadersJson); conversation.openMessageMenu(mine, conversation, false, 0, 150) }
            else if (step === 8) window.contentItem.grabToImage(r => r.saveToFile(dir + "menu-full-mine.png"))
            else if (step === 9) { conversation.closeMessageMenuForTest(); conversation.openMessageMenu(theirs, conversation, true, 500, 150) }
            else if (step === 10) window.contentItem.grabToImage(r => r.saveToFile(dir + "menu-full-theirs.png"))
            else if (step === 11) { conversation.closeMessageMenuForTest(); console.warn("MENU-TEST unread", theirs.id); backend.markMessageUnread(theirs.id, theirs.client_message_id || "") }
            else if (step === 13) { console.warn("MENU-TEST saved now", msgs.filter(m => m.saved).map(m => m.id)); Qt.quit() }
            step++
        }
    }

    // --forward-test with --open-chat=<id> --shots=<dir>: forward the newest
    // message from someone else to them (through Teams' forward), capturing
    // the dialog, the toast and the forwarded card in their 1:1.
    Timer {
        running: Qt.application.arguments.indexOf("--forward-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        property var who: null
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "fwd-" + n + ".png"))
            const d = conversation.forwardDialogForTest()
            if (step === 0 && backend.currentChatId !== id) { backend.selectChat(id, "OST forward test"); return }
            const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.deleted)
            if (step === 0) { who = msgs.filter(m => !m.mine && !m.forward).pop(); if (!who) return; d.message = who; d.open() }
            else if (step === 1) d.typeForTest(who.sender.split(" ")[0])
            else if (step === 2) shot("suggest")
            else if (step === 3) { if (!d.pickForTest(who.sender_mri.replace(/^8:orgid:/, ""))) { console.warn("FWD-TEST intended person not offered; stopping"); Qt.quit() } }
            else if (step === 4) shot("picked")
            else if (step === 5) { console.warn("FWD-TEST forwarding", who.id, JSON.stringify(d.picked)); d.forwardForTest() }
            else if (step === 6) { console.warn("FWD-TEST toast", backend.toastJson); shot("toast") }
            else if (step === 7) backend.openChatWith(who.sender_mri.replace(/^8:orgid:/, ""), who.sender)
            else if (step === 9) { const f = JSON.parse(backend.messagesJson || "[]").filter(m => m.forward); console.warn("FWD-TEST forwards in 1:1", f.length, f.length ? JSON.stringify(f[f.length - 1].forward).slice(0, 200) : ""); shot("card") }
            else if (step === 10) Qt.quit()
            step++
        }
    }

    // --pin-banner-test with --open-chat=<id> --shots=<dir>: capture the
    // pinned banner, then unpin from it and capture again.
    Timer {
        running: Qt.application.arguments.indexOf("--pin-banner-test") >= 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        property string pinned: ""
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST pin test"); return }
            if (step === 0 && !backend.pinnedJson) return
            if (step === 0) { pinned = JSON.parse(backend.pinnedJson).id; console.warn("PIN-TEST banner", backend.pinnedJson); window.contentItem.grabToImage(r => r.saveToFile(dir + "pin-banner.png")) }
            else if (step === 1) { console.warn("PIN-TEST unpin", pinned); backend.setMessagePinned(pinned, false) }
            else if (step === 3) { console.warn("PIN-TEST banner after", JSON.stringify(backend.pinnedJson)); window.contentItem.grabToImage(r => r.saveToFile(dir + "pin-after.png")) }
            else if (step === 4) Qt.quit()
            step++
        }
    }

    // --translate-test=<message id> with --open-chat=<id> --shots=<dir>:
    // translate the message, capture, show the original, capture.
    Timer {
        readonly property string target: (Qt.application.arguments.find(a => a.startsWith("--translate-test=")) || "").slice(17)
        running: target.length > 0 && backend.signedIn
        interval: 4000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST translate test"); return }
            const m = () => JSON.parse(backend.messagesJson || "[]").find(x => x.id === target)
            if (step === 0 && !m()) return
            if (step === 0) backend.translateMessage(target, true)
            else if (step === 2) { console.warn("TRANSLATE-TEST", JSON.stringify({ text: m().text, translated: m().translated, failed: m().translation_failed })); window.contentItem.grabToImage(r => r.saveToFile(dir + "translated.png")) }
            else if (step === 3) backend.translateMessage(target, false)
            else if (step === 4) { console.warn("TRANSLATE-TEST original", m().text); Qt.quit() }
            step++
        }
    }

    // --report-dialog-test with --open-chat=<id> --shots=<dir>: open the
    // report dialog on the newest message from someone else, capture it
    // and close it. Nothing is reported.
    Timer {
        running: Qt.application.arguments.indexOf("--report-dialog-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST report test"); return }
            const theirs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.mine && !m.deleted).pop()
            if (step === 0 && !theirs) return
            const d = conversation.reportDialogForTest()
            if (step === 0) { d.message = theirs; d.open() }
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(dir + "report.png"))
            else if (step === 2) { d.close(); Qt.quit() }
            step++
        }
    }

    // --toast-test --shots=<dir>: show Teams' toast and capture it.
    Timer {
        running: Qt.application.arguments.indexOf("--toast-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            if (step === 0) backend.toastJson = JSON.stringify({ id: 1, text: "Message forwarded", intent: "success" })
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(dir + "toast.png"))
            else Qt.quit()
            step++
        }
    }

    // --typing-watch[=<dir>]: log each change of the typing line (and
    // capture it there as typing-<n>.png) while someone types live.
    readonly property string typingWatch: {
        const a = Qt.application.arguments.find(a => a.startsWith("--typing-watch"))
        return a === undefined ? "" : (a.indexOf("=") > 0 ? a.slice(a.indexOf("=") + 1) : ".")
    }
    property int typingShots: 0
    Connections {
        target: backend
        enabled: window.typingWatch.length > 0
        function onTypingTextChanged() {
            const n = window.typingShots++
            console.warn("TYPING-WATCH", n, new Date().toISOString(), JSON.stringify(backend.typingText))
            window.contentItem.grabToImage(r => r.saveToFile(window.typingWatch + "/typing-" + n + ".png"))
        }
    }

    // Teams' in-app toast (measured): a 288 wide card, radius 8, 83 from the
    // window's left and 16 from its bottom. A 16 px intent icon at (12.67,
    // 14.67), the title (14/20 semibold, wrapping in 202.67) at (36.67,
    // 12.67), dismiss (24 x 20) at (251.33, 12.67); 46 tall for one line
    // (65.33 for two). An action ("Undo", 14 px #4F52B2) sits 11 under the
    // title, the card then 12.67 deeper. Success stays 5 s, errors 2 s.
    // `toastData`: {text, intent, action?, onAction?} (onAction a function).
    Item {
        id: toast
        property var toastData: null
        visible: toastData !== null
        z: 200
        x: 83; y: window.height - 16 - height
        width: 288
        height: Math.max(46, 12.67 + toastTitle.height + (toastAction.visible ? 11 + 20 : 0) + 12.67)
        FluentSurface { anchors.fill: parent; depth: 16; radius: 8; color: theme.surface }
        FluentIcon {
            x: 12.67; y: 14.67; size: 16
            name: toast.toastData && toast.toastData.intent === "error" ? "error-circle-20-filled" : "checkmark-circle-20-filled"
            color: toast.toastData && toast.toastData.intent === "error" ? theme.redForeground1 : theme.successFg
        }
        Text {
            id: toastTitle
            x: 36.67; y: 12.67; width: 202.67
            wrapMode: Text.Wrap
            text: toast.toastData ? toast.toastData.text : ""
            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            id: toastAction
            visible: !!(toast.toastData && toast.toastData.action)
            x: 36.67; y: toastTitle.y + toastTitle.height + 11; height: 20
            verticalAlignment: Text.AlignVCenter
            text: visible ? toast.toastData.action : ""
            font.family: theme.font; font.pixelSize: theme.base
            font.underline: toastActionHover.hovered
            color: theme.brandLink
            HoverHandler { id: toastActionHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    const d = toast.toastData
                    toast.toastData = null
                    if (d && typeof d.onAction === "function") d.onAction()
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: text
        }
        Rectangle {
            x: 251.33; y: 12.67; width: 24; height: 20; radius: 4
            color: toastClose.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: toastClose; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: toast.toastData = null }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss"
        }
        Timer { id: toastTimer; onTriggered: toast.toastData = null }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: toastData ? toastData.text : ""
        Connections {
            target: backend
            function onToastJsonChanged() { if (backend.toastJson) window.showToast(JSON.parse(backend.toastJson)) }
        }
    }
    function showToast(d) {
        toast.toastData = d
        toastTimer.interval = d.intent === "error" ? 2000 : 5000
        toastTimer.restart()
    }

    // Your status message as the presence service reports it.
    Connections {
        target: backend
        function onMyNoteJsonChanged() {
            const n = backend.myNoteJson ? JSON.parse(backend.myNoteJson) : {}
            titleBar.statusNote = n.text || ""; titleBar.statusNoteHtml = n.html || ""; titleBar.statusNotePinned = !!n.pinned
        }
    }
    TitleBar {
        id: titleBar
        width: parent.width
        z: 10
        userName: backend.userName
        presence: {
            const me = chatList.chats.find(c => c.isSelf)
            return me && me.presence ? me.presence : "Available"
        }
        onSignOut: backend.signOut()
        chats: chatList.chats
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearchPeople: q => backend.searchPeople(q)
        onOpenChat: (id, name) => { rail.current = "chat"; window.composing = false; backend.selectChat(id, name) }
        onOpenPerson: (oid, name) => { rail.current = "chat"; window.composing = false; backend.openChatWith(oid, name) }
        onSearchSubmitted: text => window.openSearch(text)
        canGoBack: window.navIndex > 0 || !!conversation.channelAttendance
        canGoForward: window.navIndex < window.navStack.length - 1
        onGoBack: window.goBack()
        onGoForward: window.goForward()
        onToggleRail: rail.collapsed = !rail.collapsed
        onOpenSettings: rail.current = "settings"
        onOpenShortcuts: shortcutsDialog.open()
        onOpenHelp: window.openHelp()
        onOpenFeedback: kind => window.openFeedback(kind, "Settings and more", "")
        onSuggestFeature: Qt.openUrlExternally(backend.feedbackLink("ideas"))
        userMail: backend.userMail
        orgName: backend.orgName
        onSetStatus: st => backend.setMyStatus(st)
        onSetStatusUntil: (st, dur) => backend.setMyStatusUntil(st, dur, "")
        onSetStatusNote: (msg, pinned, clearAfter) => backend.setStatusNote(msg, pinned, clearAfter, "")
        statusUntil: backend.myStatusEnds
        workLocation: backend.myWorkLocation
        onSetWorkLocation: loc => backend.setWorkLocationToday(loc)
        onPauseUntil: iso => backend.setMyStatusUntil("DoNotDisturb", "Custom", iso)
        onOpenNotificationSettings: { settingsView.page = "notifications"; rail.current = "settings" }
        onOpenOutOfOffice: { settingsView.page = "general"; settingsView.subPage = "oof"; rail.current = "settings" }
        pinned: window.pinned
        onTogglePin: window.pinned = !window.pinned
        windowButtons: !backend.systemFrame
    }

    // Teams' app banner under the title bar (measured on winpc 2026-11-09):
    // full width, 36 tall, #F5F5F5; info (20, filled, #616161) at 12; the
    // text 14/20 at 40; then its action as a small secondary button (12/16,
    // padding 3 x 8, 23.3 tall) and Dismiss (24 x 23.3, a 20 px glyph) 12
    // from the right. Teams' presence job shows "Your status is set to do
    // not disturb…" whenever your status becomes Do not disturb and takes it
    // away when it changes again; Change settings opens Privacy's priority
    // access.
    property string bannerAvailability: ""
    // A person's profile card, from their picture anywhere it opens one.
    ProfileCard {
        id: profileCard
        onStartChat: (mri, name) => { rail.current = "chat"; window.composing = false; backend.openChatWith(mri.replace("8:orgid:", ""), name) }
        onStartCall: (mri, name, video) => { rail.current = "chat"; window.composing = false; window.pendingCall = video ? "video" : "audio"; backend.openChatWith(mri.replace("8:orgid:", ""), name) }
        onQuickMessage: (mri, name, text) => { window.pendingQuickMessage = text; backend.openChatWith(mri.replace("8:orgid:", ""), name) }
    }
    Connections { target: backend; function onProfileRequested(mri) { profileCard.show(mri) } }
    // The compact card hovering a picture or name opens.
    HoverCard {
        id: hoverCard
        fullCard: profileCard
        onStartChat: (mri, name) => profileCard.startChat(mri, name)
        onStartCall: (mri, name, video) => profileCard.startCall(mri, name, video)
        onQuickMessage: (mri, name, text) => profileCard.quickMessage(mri, name, text)
        Component.onCompleted: theme.hoverCard = hoverCard
    }
    // Started from a profile card: call or send once the 1:1 chat is open.
    property string pendingCall: ""
    property string pendingQuickMessage: ""
    Connections {
        target: backend
        function onCurrentChatIdChanged() {
            if (!backend.currentChatId) return
            if (window.pendingCall) { const v = window.pendingCall === "video"; window.pendingCall = ""; Qt.callLater(() => v ? backend.startVideoCall() : backend.startCall()) }
            if (window.pendingQuickMessage) { const t = window.pendingQuickMessage; window.pendingQuickMessage = ""; Qt.callLater(() => backend.sendMessage(t)) }
        }
    }
    // Settings ▸ Notifications ▸ Flash taskbar when notifications are received.
    Connections { target: backend; function onFlashRequested() { if (!window.active) window.alert(0) } }
    property bool dndBanner: false
    // Which of the two banners came last.
    property string bannerOrder: ""
    onDndBannerChanged: if (dndBanner) bannerOrder = "dnd"
    onNoteBannerChanged: if (noteBanner) bannerOrder = "note"
    readonly property string myAvailability: titleBar.presence
    onMyAvailabilityChanged: {
        const dnd = myAvailability.toLowerCase() === "donotdisturb"
        if (dnd !== (bannerAvailability.toLowerCase() === "donotdisturb")) dndBanner = dnd
        bannerAvailability = myAvailability
    }
    // Teams' other presence banner ("presence-statusmessage-banner"): when
    // your status message changes and it is pinned ("Show when people
    // message me"), "Your status message is showing in chat and channels
    // when people message or @mention you[ until {time}]."; no action;
    // dismissed when the message stops being pinned.
    property bool noteBanner: false
    property string noteBannerText: ""
    property string lastNoteKey: ""
    readonly property var myNote: backend.myNoteJson ? JSON.parse(backend.myNoteJson) : null
    onMyNoteChanged: {
        const n = myNote || {}
        const key = (n.html || n.text || "") + "|" + (n.expiry || "")
        if (key === lastNoteKey) return
        lastNoteKey = key
        if ((n.text || n.html) && n.pinned) {
            const end = n.expiry ? new Date(n.expiry) : null
            noteBannerText = !end || end.getFullYear() >= 9999
                ? "Your status message is showing in chat and channels when people message or @mention you."
                : "Your status message is showing in chat and channels when people message or @mention you until " + Qt.formatDateTime(end, "M/d/yyyy h:mm AP") + "."
            noteBanner = true
        } else noteBanner = false
    }
    // Teams' threads-layout channel banner (its ThreadedChannelInfoBanner):
    // in a threads channel's main view, "A channel owner set this channel
    // to a threads layout." and "Learn how threads work", 4rem tall, until
    // dismissed on this device or until you've sent there (the service's
    // ThreadedChannelInteraction).
    readonly property var espActions: backend.espActionsJson ? JSON.parse(backend.espActionsJson) : null
    property bool threadsBannerDismissed: backend.setting("threadedChannelLearnMoreBannerDismissed") !== ""
    readonly property bool threadsBanner: rail.current === "chat" && conversation.visible && conversation.threadsLayout
        && !threadsBannerDismissed && !!espActions && espActions.indexOf("ThreadedChannelInteraction") < 0
    Rectangle {
        id: appBanner
        anchors { top: titleBar.bottom; left: parent.left; right: parent.right }
        // The newest banner shows (Teams' shell keeps one at a time).
        readonly property string kind: window.dndBanner && (!window.noteBanner || window.bannerOrder === "dnd") ? "dnd" : window.noteBanner ? "note" : window.threadsBanner ? "threads" : ""
        readonly property bool shown: kind !== "" && backend.hasCredentials
        height: shown ? (kind === "threads" ? 64 : 36) : 0
        visible: shown
        color: theme.pick("#F5F5F5", "#292929")
        z: 9
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "info-20-filled"; size: 20; color: theme.textSecondary }
        Text {
            x: 40; anchors.verticalCenter: parent.verticalCenter
            width: bannerAction.x - 12 - x; elide: Text.ElideRight
            textFormat: appBanner.kind === "threads" ? Text.RichText : Text.PlainText
            text: appBanner.kind === "note" ? window.noteBannerText
                : appBanner.kind === "threads" ? "A channel owner set this channel to a threads layout. <a href=\"https://go.microsoft.com/fwlink/?linkid=2311967\" style=\"text-decoration:none; color:" + theme.brandForeground1 + "\">Learn how threads work</a>"
                : "Your status is set to do not disturb. You'll only get notifications for urgent messages and from your priority contacts."
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
            onLinkActivated: url => Qt.openUrlExternally(url)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Rectangle {
            id: bannerAction
            visible: appBanner.kind === "dnd"
            anchors.right: bannerDismiss.left; anchors.rightMargin: visible ? 12 : 0; anchors.verticalCenter: parent.verticalCenter
            width: visible ? bannerActionText.implicitWidth + 16 : 0; height: 23.3; radius: 4
            color: bannerActionHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { id: bannerActionText; anchors.centerIn: parent; text: "Change settings"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            HoverHandler { id: bannerActionHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { settingsView.page = settingsView.pages.some(p => p.key === "privacy") ? "privacy" : "notifications"; rail.current = "settings" } }
            Accessible.role: Accessible.Button
            Accessible.name: "Change settings"
        }
        Rectangle {
            id: bannerDismiss
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 23.3; radius: 4
            color: bannerDismissHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: bannerDismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    if (appBanner.kind === "note") window.noteBanner = false
                    else if (appBanner.kind === "threads") { backend.setSetting("threadedChannelLearnMoreBannerDismissed", new Date().toISOString()); window.threadsBannerDismissed = true }
                    else window.dndBanner = false
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss"
        }
    }

    SignIn {
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        z: 5
        visible: !backend.hasCredentials
        code: backend.signInCode
        url: backend.signInUrl
        busy: backend.busy
        error: backend.statusText
        onSignIn: backend.beginSignIn()
    }

    AppRail {
        id: rail
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: parent.left }
        // Muted chats don't count toward the badge (Teams' doesContributeToBadgeCount).
        noneChosen: !!window.teamPage && rail.current === "chat"
        unreadChats: chatList.chats.filter(c => c.unread && !c.muted).length
        unreadActivity: backend.activityUnread
        // --view=<app> opens that rail app (for captures).
        Component.onCompleted: {
            const v = Qt.application.arguments.find(a => a.startsWith("--view="))
            if (v) current = v.substring(7)
            window.navRecord()
        }
        onCurrentChanged: {
            window.navRecord()
            if (current === "calls") backend.loadCalls()
            if (current === "activity") backend.markActivityRead()
        }
    }

    property bool composing: Qt.application.arguments.indexOf("--new-chat") >= 0
    NewChat {
        id: newChat
        visible: window.composing && rail.current === "chat"
        z: 3
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: chatList.right; right: parent.right }
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearch: q => backend.searchPeople(q)
        onChosen: (oid, name, text) => {
            window.composing = false
            backend.openChatWith(oid, name)
            if (text) backend.sendMessage(text)
        }
        onGroup: (oids, topic, text) => { window.composing = false; backend.createGroupChat(oids, topic, text) }
        onCancelled: window.composing = false
    }

    CallsView {
        visible: rail.current === "calls"
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        calls: backend.callsJson ? JSON.parse(backend.callsJson) : []
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearchPeople: q => backend.searchPeople(q)
        onOpenChatWith: (mri, name) => {
            const c = chatList.chats.find(c => c.peerMri === mri)
            rail.current = "chat"
            if (c) backend.selectChat(c.id, c.name)
            else if ((mri || "").startsWith("8:orgid:")) backend.openChatWith(mri.slice(8), name)
        }
        // Call someone: open your 1:1 chat with them and place the call.
        onCallPerson: (oid, name) => {
            if (!oid) return
            rail.current = "chat"
            window.callAfterOpen = true
            backend.openChatWith(oid, name)
        }
    }

    CalendarView {
        id: calendarView
        visible: rail.current === "calendar"
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        events: backend.calendarJson ? JSON.parse(backend.calendarJson) : []
        onRangeChanged: (s, e) => backend.loadCalendar(s, e)
        onCreateEvent: (subject, s, e, who, teams) => backend.createEvent(subject, s, e, who, teams)
        onDeleteEvent: id => backend.deleteEvent(id)
        onUpdateEvent: (id, subject, s, e) => backend.updateEvent(id, subject, s, e)
        // Chat: the meeting's chat thread (from its join link).
        onOpenMeetingChat: (url, subject) => {
            const m = /meetup-join\/([^/?]+)/.exec(url)
            if (!m) return
            rail.current = "chat"
            backend.selectChat(decodeURIComponent(m[1]), subject)
        }
        // Join: Teams' pre-join window first, then the meeting.
        onJoinMeeting: (url, subject) => {
            if (url.indexOf("/l/meetup-join/") < 0) { Qt.openUrlExternally(url); return }
            const ev = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(e => e.join_url === url)
            preJoin.openFor(url, subject, ev ? ev.start_utc : "", ev ? ev.end_utc : "")
        }
    }

    // Apps not built yet: an honest placeholder instead of the chat.
    Rectangle {
        visible: ["chat", "calls", "calendar", "activity", "settings", "onedrive", "planner", "people", "onenote", "add", "whiteboard", "clipchamp", "help", "communities", "search"].indexOf(rail.current) < 0
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        color: theme.surface
        Text {
            anchors.centerIn: parent
            text: "This app isn't available in OST yet."
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
    }
    // Teams' embedded web apps, created when first opened and kept (so
    // a whiteboard stays where you left it).
    Repeater {
        model: [
            { key: "whiteboard", name: "Whiteboard", icon: "board-20", color: "#0F6CBD", url: "https://whiteboard.cloud.microsoft/" },
            { key: "clipchamp", name: "Clipchamp", icon: "video", color: "#8764B8", url: "https://app.clipchamp.com/" },
            // Communities (Viva Engage), as Teams embeds it.
            { key: "communities", name: "Communities", icon: "people-community-20", color: "#0F6CBD", url: "https://engage.cloud.microsoft/main/discover" }
        ]
        Loader {
            required property var modelData
            property bool opened: false
            visible: rail.current === modelData.key
            onVisibleChanged: if (visible) opened = true
            active: opened
            anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
            sourceComponent: WebApp { appName: modelData.name; appIcon: modelData.icon; appColor: modelData.color; home: modelData.url }
        }
    }
    // Teams' search results page (Enter in the title bar's search).
    readonly property var searchTabWords: ({ messages: "Messages", files: "Files", people: "People", channels: "Channels", groupchats: "Group chats", meetings: "Meetings", images: "Images" })
    function openSearch(text) {
        // "is:Messages" picks the tab, as in Teams.
        let tab = "all", q = String(text)
        const m = q.match(/\bis:(messages|files|people|channels|groupchats|group chats|meetings|images)\b/i)
        if (m) { tab = m[1].toLowerCase().replace(" ", ""); q = q.replace(m[0], "") }
        q = q.trim()
        if (!q) return
        rail.current = "search"
        searchView.search(q, tab)
    }
    function chatsJsonList() { try { return JSON.parse(backend.chatsJson || "[]") } catch (e) { return [] } }
    SearchView {
        id: searchView
        visible: rail.current === "search"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        chats: chatList.chats
        teams: { try { return JSON.parse(backend.teamsJson || "[]") } catch (e) { return [] } }
        members: { try { return JSON.parse(backend.chatMembersJson || "[]") } catch (e) { return [] } }
        onTabChanged2: t => titleBar.setSearchText(query + (t === "all" ? "" : " is:" + window.searchTabWords[t]))
        onOpenChat: (id, name, messageId, terms) => {
            rail.current = "chat"; window.composing = false
            backend.selectChat(id, name)
            if (messageId) conversation.showFound(messageId, terms, "")
        }
        onOpenChannel: (id, name, messageId, postId, terms) => {
            rail.current = "chat"; window.composing = false
            backend.selectChat(id, name)
            if (messageId) conversation.showFound(messageId, terms, postId && postId !== messageId ? postId : "")
        }
        onOpenPerson: (mri, name) => { rail.current = "chat"; window.composing = false; backend.openChatWith(String(mri).split(":").pop(), name) }
        onOpenChatWindow: (id, name) => {
            if (String(id).endsWith("@thread.tacv2")) window.openChannelWindow(id)
            else window.openChatWindow(id, name, "", "")
        }
        onOpenMeeting: e => {
            // Chat: the meeting's chat (its thread is in the join link);
            // Edit: the calendar.
            const t = decodeURIComponent(String(e.join_url || "")).match(/19:meeting_[^/@]+@thread\.v2/)
            if (t && (!e.is_organizer || new Date(e.end) < new Date())) { rail.current = "chat"; backend.selectChat(t[0], e.subject) }
            else rail.current = "calendar"
        }
    }
    // The Help app: OST's help, in place (as Teams shows its Help app).
    Loader {
        id: helpApp
        property bool opened: false
        visible: rail.current === "help"
        onVisibleChanged: if (visible) opened = true
        active: opened
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        sourceComponent: HelpView {}
    }
    StoreView {
        id: store
        visible: rail.current === "add"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        reply: backend.storeJson ? JSON.parse(backend.storeJson) : ({})
        busy: backend.storeBusy
        onLoad: backend.storeLoad()
        onOpenApp: key => rail.openApp(key)
    }
    PeopleView {
        id: peopleApp
        visible: rail.current === "people"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        data_: backend.contactsJson ? JSON.parse(backend.contactsJson) : ({})
        busy: backend.contactsBusy
        onLoad: backend.contactsLoad()
        onAdd: json => backend.contactsAdd(json)
        onFavorite: (id, on) => backend.contactsFavorite(id, on)
        onRemove: id => backend.contactsDelete(id)
    }
    OneNoteView {
        id: oneNote
        visible: rail.current === "onenote"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        reply: backend.onenoteJson ? JSON.parse(backend.onenoteJson) : ({})
        busy: backend.onenoteBusy
        onLoad: (v, id) => backend.onenoteLoad(v, id)
        onCreate: (kind, parent, name, text) => backend.onenoteCreate(kind, parent, name, text)
        onRemovePage: id => backend.onenoteDeletePage(id)
    }
    PlannerView {
        id: planner
        visible: rail.current === "planner"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        plannerData: backend.plannerJson ? JSON.parse(backend.plannerJson) : ({})
        busy: backend.plannerBusy
        teams: (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).map(t => ({ id: t.id, name: t.name }))
        onLoad: (v, p) => backend.plannerLoad(v, p)
        onAdd: (title, due) => backend.plannerAdd(title, due)
        onComplete: json => backend.plannerComplete(json)
        onRemove: json => backend.plannerDelete(json)
        onCreatePlan: (g, t, title) => backend.plannerCreatePlan(g, t, title)
        onAddToPlan: (p, title) => backend.plannerAddToPlan(p, title)
        onDeletePlan: id => backend.plannerDeletePlan(id)
    }
    // A message's file, as Teams opens it: over the chat list and the
    // conversation, right of the app bar.
    FileViewer {
        id: fileViewer
        z: 50
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        onMenuRequested: (f, anchor) => conversation.openFileCardMenu(f, anchor, 4)
    }
    Connections { target: rail; function onCurrentChanged() { fileViewer.close() } }
    Connections { target: backend; function onCurrentChatIdChanged() { fileViewer.close() } }

    OneDriveView {
        id: oneDrive
        visible: rail.current === "onedrive"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        driveData: backend.driveJson ? JSON.parse(backend.driveJson) : ({})
        busy: backend.driveBusy
        userName: backend.userName
        onLoad: (v, d, i) => backend.driveLoad(v, d, i)
        onDownload: json => backend.driveDownload(json)
        onUpload: (d, f, paths) => backend.driveUpload(d, f, paths)
        onNewFolder: (d, p, name) => backend.driveNewFolder(d, p, name)
        onRemove: (d, i) => backend.driveDelete(d, i)
        onFavorite: (d, i, on) => backend.driveFavorite(d, i, on)
        onRestore: ids => backend.driveRestore(ids)
        onPurge: ids => backend.drivePurge(ids)
    }
    // A channel in a window of its own (its menu's Open in new window), one
    // per channel: opening it again brings it forward.
    Component { id: channelWindowComponent; ChannelWindow {} }
    property var channelWindows: ({})
    function openChannelWindow(channelId) {
        const open = window.channelWindows[channelId]
        if (open) { open.raise(); open.requestActivate(); return open }
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const team = teams.find(t => (t.channels || []).some(c => c.id === channelId))
        if (!team) return null
        const ch = team.channels.find(c => c.id === channelId)
        const w = channelWindowComponent.createObject(null, { channelId: channelId, teamId: team.id, teamName: team.name, channelName: ch.name })
        const all = Object.assign({}, window.channelWindows); all[channelId] = w; window.channelWindows = all
        w.meetNow.connect((id, name) => preJoin.openMeetNow(id, "Meeting in \"" + name + "\""))
        w.scheduleMeeting.connect(() => { rail.current = "calendar"; calendarView.newMeeting() })
        w.manageChannel.connect(id => window.openManageChannel(id))
        w.closing.connect(() => { const rest = Object.assign({}, window.channelWindows); delete rest[channelId]; window.channelWindows = rest; w.destroy() })
        w.show()
        return w
    }
    // A chat in a window of its own (its menu's Open in new window), one per
    // chat: opening it again brings it forward.
    Component { id: chatWindowComponent; ChatWindow {} }
    property var chatWindows: ({})
    // A chat's Share screen (Ctrl+Shift+E): call the chat, and share once
    // the call connects (Teams' share picker).
    property bool shareWhenConnected: false
    function callAndShare() { shareWhenConnected = true; backend.startCall() }
    Connections {
        target: backend
        function onCallStateChanged() {
            if (backend.callState === "connected" && window.shareWhenConnected) {
                window.shareWhenConnected = false
                if (backend.callCanShare && !backend.callSharing) backend.toggleShare()
            } else if (backend.callState === "ended" || backend.callState === "") window.shareWhenConnected = false
        }
    }
    function openChatWindow(chatId, name, photoId, presence) {
        const open = window.chatWindows[chatId]
        if (open) { open.raise(); open.requestActivate(); return open }
        const w = chatWindowComponent.createObject(null, { chatId: chatId, chatName: name, photoId: photoId || "", presence: presence || "" })
        const all = Object.assign({}, window.chatWindows); all[chatId] = w; window.chatWindows = all
        w.startCall.connect(id => { backend.selectChat(id, name); backend.startCall() })
        w.startVideoCall.connect(id => { backend.selectChat(id, name); backend.startVideoCall() })
        w.shareScreen.connect(id => { backend.selectChat(id, name); window.callAndShare() })
        w.reportConcern.connect(id => chatList.reportMeetingChat(id))
        w.closing.connect(() => { const rest = Object.assign({}, window.chatWindows); delete rest[chatId]; window.chatWindows = rest; w.destroy() })
        w.show()
        return w
    }
    // Manage channel: Teams' page in the conversation's place, for the
    // channel (selected in the list) until another chat is picked.
    property var manage: null
    function openManageChannel(channelId) {
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const team = teams.find(t => (t.channels || []).some(c => c.id === channelId))
        if (!team) return
        const ch = team.channels.find(c => c.id === channelId)
        rail.current = "chat"
        window.composing = false; chatList.draftsOpen = false; chatList.mentionsOpen = false
        if (backend.currentChatId !== channelId) backend.selectChat(channelId, ch.name)
        window.manageTeamId = ""; chatList.yourTeamsOpen = false; chatList.quickOpen = ""
        window.manage = { teamId: team.id, teamName: team.name, channelId: channelId }
        window.raise(); window.requestActivate()
    }
    Connections {
        target: backend
        function onCurrentChatIdChanged() { if (window.manage && backend.currentChatId !== window.manage.channelId) window.manage = null }
    }
    // Manage team: Teams' page in the conversation's place.
    property string manageTeamId: ""
    function openManageTeam(teamId, tab) {
        rail.current = "chat"
        window.composing = false; chatList.draftsOpen = false; chatList.mentionsOpen = false
        window.manage = null
        chatList.yourTeamsOpen = false; chatList.quickOpen = ""
        window.manageTeamId = teamId
        manageTeam.tab = tab || "channels"
        window.raise(); window.requestActivate()
    }
    Connections {
        target: backend
        function onCurrentChatIdChanged() { window.manageTeamId = ""; chatList.yourTeamsOpen = false }
    }
    // Your teams and channels (See all your teams).
    function openYourTeams(tab) {
        rail.current = "chat"
        window.composing = false; chatList.draftsOpen = false; chatList.mentionsOpen = false
        window.manage = null; window.manageTeamId = ""
        chatList.yourTeamsOpen = true; chatList.quickOpen = ""
        yourTeams.tab = tab || "teams"
        window.raise(); window.requestActivate()
    }
    YourTeams {
        id: yourTeams
        visible: chatList.yourTeamsOpen && !window.manageTeamId && !window.manage && rail.current === "chat" && !chatList.draftsOpen && !chatList.mentionsOpen && !window.teamPage
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        onManageTeam: id => window.openManageTeam(id, "channels")
        onManageTags: id => window.openManageTeam(id, "tags")
        onOpenChannel: (id, name) => { chatList.yourTeamsOpen = false; backend.selectChat(id, name) }
        onCreateTeam: createTeamDialog.startScratch()
        onJoinTeam: window.openTeamPage("join")
    }
    // Create team / Join a team: Teams' pages in the list's and the
    // conversation's place, and its Create a team dialog.
    property string teamPage: ""
    function openTeamPage(which) {
        rail.current = "chat"
        window.teamPage = which
        if (which === "create") createTeamPage.load()
        else joinTeamPage.load()
    }
    // A new or joined team: back to the chat with its General open once the
    // team list has it.
    property string pendingTeamThread: ""
    function teamReady(groupId, threadId) {
        window.teamPage = ""
        chatList.yourTeamsOpen = false
        window.pendingTeamThread = threadId || ""
        backend.reloadTeams()
    }
    Connections {
        target: backend
        function onTeamsJsonChanged() {
            if (!window.pendingTeamThread) return
            const t = JSON.parse(backend.teamsJson || "[]").find(t => t.thread_id === window.pendingTeamThread)
            if (t) { window.pendingTeamThread = ""; backend.selectChat(t.thread_id, "General") }
        }
    }
    CreateTeamDialog {
        id: createTeamDialog
        onMoreOptions: window.openTeamPage("create")
        onCreated: (g, t) => window.teamReady(g, t)
    }
    CreateTeamPage {
        id: createTeamPage
        visible: window.teamPage === "create" && rail.current === "chat"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        onBack: window.teamPage = ""
        onTeamCreated: (g, t) => window.teamReady(g, t)
    }
    JoinTeamPage {
        id: joinTeamPage
        visible: window.teamPage === "join" && rail.current === "chat"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        onBack: window.teamPage = ""
        onCreateTeam: createTeamDialog.startScratch()
        onJoined: (g, t) => window.teamReady(g, t)
    }
    ManageTeam {
        id: manageTeam
        visible: !!window.manageTeamId && rail.current === "chat" && !chatList.draftsOpen && !chatList.mentionsOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        teamId: window.manageTeamId
        onOpenChannel: (id, name) => { window.manageTeamId = ""; backend.selectChat(id, name) }
        onManageChannel: id => { window.manageTeamId = ""; window.openManageChannel(id) }
        onManageChannelAnalytics: id => { window.manageTeamId = ""; window.openManageChannel(id); manageChannel.tab = "analytics" }
        onOpenChannelWindow: id => window.openChannelWindow(id)
        onChannelWorkflows: id => window.openWorkflows(id)
        onGetMoreApps: { window.manageTeamId = ""; rail.current = "add" }
        // Analytics ▸ Analytics across teams: Your teams and channels' Analytics.
        onAcrossTeams: window.openYourTeams("analytics")
        myPresence: window.myPresence
        // Tags ▸ Chat with group: a new chat with the tag's people.
        onChatWithPeople: people => {
            window.manageTeamId = ""
            window.composing = true
            Qt.callLater(() => { newChat.picked = people })
        }
    }
    ManageChannel {
        id: manageChannel
        visible: !!window.manage && rail.current === "chat" && !chatList.draftsOpen && !chatList.mentionsOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        teamId: window.manage ? window.manage.teamId : ""
        teamName: window.manage ? window.manage.teamName : ""
        channelId: window.manage ? window.manage.channelId : ""
        myPresence: window.myPresence
        onGoToChannel: window.manage = null
        onOpenInNewWindow: id => window.openChannelWindow(id)
        onManageChannel: id => window.openManageChannel(id)
        // All Channels / Analytics across channels: the team's analytics.
        onTeamAnalytics: id => window.openManageTeam(id, "analytics")
    }
    // A channel's Workflows (Teams' dialog with the Workflows app).
    WorkflowsDialog { id: workflowsDialog }
    function openWorkflows(channelId) {
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const team = teams.find(t => (t.channels || []).some(c => c.id === channelId))
        if (!team) return
        const ch = team.channels.find(c => c.id === channelId)
        workflowsDialog.start(channelId, ch.name, team.id, team.name)
    }
    ChatList {
        id: chatList
        onOpenChannelWindow: id => window.openChannelWindow(id)
        onChannelWorkflows: id => window.openWorkflows(id)
        onManageChannel: (id, name) => window.openManageChannel(id)
        onManageTeam: id => window.openManageTeam(id, "channels")
        onManageTags: id => window.openManageTeam(id, "tags")
        // An expanded tab takes the list's place (Teams' Expand tab), as
        // does a channel meeting's Attendance view.
        visible: rail.current === "chat" && !conversation.tabExpanded && !conversation.channelAttendance && !window.teamPage
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right }
        chats: backend.chatsJson ? JSON.parse(backend.chatsJson) : []
        teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        currentId: backend.currentChatId
        onChatSelected: (id, name) => { window.composing = false; draftsOpen = false; mentionsOpen = false; quickOpen = ""; window.manage = null; window.manageTeamId = ""; yourTeamsOpen = false; backend.selectChat(id, name) }
        onNewChat: { draftsOpen = false; mentionsOpen = false; yourTeamsOpen = false; window.composing = true }
        onOpenYourTeams: window.openYourTeams("teams")
        onOpenChatWindow: (id, name, photo, presence) => window.openChatWindow(id, name, photo, presence)
        onManageChatApps: (id, name) => { window.composing = false; draftsOpen = false; mentionsOpen = false; window.manage = null; window.manageTeamId = ""; yourTeamsOpen = false; if (backend.currentChatId !== id) backend.selectChat(id, name); conversation.manageApps = true }
        onChatWorkflows: (id, name) => workflowsDialog.startChat(id, name)
        onMarkAllRead: backend.markAllRead()
        draftIds: (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).map(d => d.id)
        onOpenDrafts: { window.composing = false; mentionsOpen = false; yourTeamsOpen = false; quickOpen = ""; draftsOpen = true }
        hasMentions: mentionsView.mentions.length > 0
        onOpenMentions: { window.composing = false; draftsOpen = false; yourTeamsOpen = false; quickOpen = ""; mentionsOpen = true; mentionsView.selectedId = "" }
        onOpenQuick: kind => { window.composing = false; draftsOpen = false; mentionsOpen = false; yourTeamsOpen = false; window.manage = null; window.manageTeamId = ""; quickOpen = kind; quickView.selectedKey = "" }
        onOpenCommunities: rail.openApp("communities")
    }
    MentionsView {
        id: mentionsView
        visible: rail.current === "chat" && chatList.mentionsOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        items: backend.activityJson ? JSON.parse(backend.activityJson) : []
        myName: backend.userName
        // A mention opens its chat beside the list.
        onOpenMention: item => {
            selectedId = item.id
            if (item.unread) backend.markActivityItemRead(item.id)
            if (item.thread_id) {
                const c = chatList.chats.find(c => c.id === item.thread_id)
                backend.selectChat(item.thread_id, c ? c.name : (item.context || item.actor_name || "Chat"))
            }
        }
    }
    // Quick views ▸ Followed threads / Saved: the list, and the picked
    // item's chat or channel beside it.
    QuickListView {
        id: quickView
        kind: chatList.quickOpen || "followed"
        visible: rail.current === "chat" && !!chatList.quickOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        onOpenItem: item => {
            const c = chatList.chats.find(c => c.id === item.thread_id)
            backend.selectChat(item.thread_id, c ? c.name : quickView.titleOf(item))
        }
    }
    DraftsView {
        id: draftsView
        visible: rail.current === "chat" && chatList.draftsOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        drafts: backend.draftsJson ? JSON.parse(backend.draftsJson) : []
        onOpenDraft: (id, name) => { chatList.draftsOpen = false; backend.selectChat(id, name) }
    }
    // While your newest message in the open chat is still unread, re-check
    // the other person's read horizon now and then (push covers most cases).
    Timer {
        interval: 20000; repeat: true
        running: backend.windowActive && backend.currentChatId.length > 0 && rail.current === "chat" && (() => {
            const msgs = backend.messagesJson ? JSON.parse(backend.messagesJson) : []
            const mine = msgs.filter(m => m.mine && m.kind === "message")
            return mine.length > 0 && !mine[mine.length - 1].seen
        })()
        onTriggered: backend.refreshReceipts()
    }
    SettingsView {
        id: settingsView
        visible: rail.current === "settings"
        onShowShortcuts: shortcutsDialog.open()
        myPresence: titleBar.presence
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
    }
    ActivityView {
        id: activityView
        visible: rail.current === "activity"
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right }
        items: backend.activityJson ? JSON.parse(backend.activityJson) : []
        onMarkAllRead: {
            for (const it of items) if (it.unread) backend.markActivityItemRead(it.id)
            backend.markActivityRead()
        }
        // An item opens its chat or channel beside the feed.
        onOpenItem: item => {
            selectedId = item.id
            backend.markActivityItemRead(item.id)
            if (item.thread_id) {
                const c = chatList.chats.find(c => c.id === item.thread_id)
                backend.selectChat(item.thread_id, c ? c.name : (item.actor_name || "Chat"))
            } else if ((item.actor_mri || "").startsWith("8:orgid:")) {
                backend.openChatWith(item.actor_mri.slice(8), item.actor_name)
            }
        }
        onChatWith: item => {
            if (!(item.actor_mri || "").startsWith("8:orgid:")) return
            rail.current = "chat"
            backend.openChatWith(item.actor_mri.slice(8), item.actor_name)
        }
        onCallBack: item => {
            if (!(item.actor_mri || "").startsWith("8:orgid:")) return
            rail.current = "chat"
            backend.openChatWith(item.actor_mri.slice(8), item.actor_name)
            window.callAfterOpen = true
        }
    }
    // "Call" from a missed call: place the call once the chat is open.
    property bool callAfterOpen: false
    Connections {
        target: backend
        function onCurrentChatIdChanged() {
            if (window.callAfterOpen && backend.currentChatId) { window.callAfterOpen = false; backend.startCall() }
        }
    }
    // Teams' app details and Share form for apps shared in chats.
    AppDetailsDialog {
        id: appDetails
        offerOpen: true
        onShareApp: id => appShare.start(id)
        onOpenApp: (id, name) => window.openAppById(id, name)
        onBackToStore: agentStore.open()
        onAddedTo: r => {
            if (r.notificationOnly) aboutBot.open()
            else if (r.bot && backend.currentChatId === r.conversation) conversation.mentionBot(r.name, "28:" + r.bot)
        }
    }
    ShareForm { id: appShare }
    OneDriveShare { id: oneDriveShare }
    // Teams' in-context Store behind the @ picker's "Add agent". An app's
    // details open in its place; their Back returns to it, and Add puts
    // the app in the conversation.
    AgentStore {
        id: agentStore
        onOpenApp: id => { agentStore.close(); appDetails.show(id, { id: agentStore.conversationId, channel: agentStore.channel }) }
        onGetMoreApps: rail.current = "add"
    }
    // Teams' "About this bot" after adding a bot that only notifies; other
    // bots start an @mention in the compose box, as Teams does.
    AboutBotDialog { id: aboutBot }
    /// Open an app OST has (by Teams app id or name); the rest in Teams on
    /// the web.
    function openAppById(id, name) {
        const byId = { "5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83": "help" }
        const byName = { "Planner": "planner", "OneNote": "onenote", "People": "people", "Whiteboard": "whiteboard", "Clipchamp": "clipchamp", "Help": "help" }
        const links = backend.appLinksJson ? JSON.parse(backend.appLinksJson) : ({})
        const key = byId[id] || byName[name || (links[id] ? links[id].name : "")] || ""
        if (key) rail.openApp(key)
        else Qt.openUrlExternally("https://teams.microsoft.com/l/app/" + encodeURIComponent(id))
    }
    Conversation {
        id: conversation
        onToastRequested: d => window.showToast(d)
        onOpenFileRequested: f => fileViewer.show(f)
        onOpenAppDetails: id => appDetails.show(id)
        onShareApp: id => appShare.start(id)
        // Meeting details: the meeting in the calendar.
        onOpenMeetingDetails: (url, ical, start) => { rail.current = "calendar"; calendarView.showMeeting(url, ical, start) }
        onOpenAppById: id => window.openAppById(id, "")
        onOpenAgentStore: (id, isChannel) => agentStore.show(id, isChannel)
        // A channel's Meet now: Teams' pre-join, titled for the channel.
        onChannelMeetNow: preJoin.openMeetNow(conversation.chatId, "Meeting in \"" + conversation.chatName + "\"")
        onOpenChannelWindow: id => window.openChannelWindow(id)
        onChannelWorkflows: id => window.openWorkflows(id)
        onManageChannel: id => window.openManageChannel(id)
        myName: backend.userName
        visible: (rail.current === "chat" && !chatList.draftsOpen && (!chatList.mentionsOpen || mentionsView.selectedId.length > 0) && (!chatList.quickOpen || quickView.selectedKey.length > 0) && !manageChannel.visible && !manageTeam.visible && !yourTeams.visible && !window.teamPage)
            || (rail.current === "activity" && activityView.selectedId.length > 0)
        chatId: backend.currentChatId
        anchors { top: appBanner.bottom; bottom: statusBar.top; right: findPane.left
            left: conversation.tabExpanded || conversation.channelAttendance ? rail.right : rail.current === "activity" ? activityView.right : chatList.right
            leftMargin: rail.current === "chat" && (chatList.mentionsOpen || !!chatList.quickOpen) ? mentionsView.paneWidth : 0 }
        chatName: backend.currentChatName
        isChannel: backend.currentChatId.endsWith("@thread.tacv2")
        isSelf: backend.currentChatId === "48:notes"
        isGroup: backend.currentChatId.endsWith("@thread.v2") || backend.currentChatId.indexOf("meeting_") >= 0
        teamName: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const t = teams.find(t => t.channels.some(c => c.id === backend.currentChatId))
            return t ? t.name : ""
        }
        teamId: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const t = teams.find(t => t.channels.some(c => c.id === backend.currentChatId))
            return t ? t.id : ""
        }
        scheduled: { try { return JSON.parse(backend.scheduledJson || "[]") } catch (e) { return [] } }
        channelLayout: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            for (const t of teams) { const c = (t.channels || []).find(c => c.id === backend.currentChatId); if (c) return c.layout || "" }
            return ""
        }
        onJoinMeetingRequested: (url, title) => preJoin.openFor(url, title, "", "")
        onOpenThread: rootId => {
            threadsPane.channelId = backend.currentChatId
            threadsPane.openThread(rootId)
        }
        threadsOpen: threadsPane.shown
        openThreadRoot: threadsPane.shown ? threadsPane.rootId : ""
        onToggleThreads: {
            if (threadsPane.shown) { threadsPane.listOpen = false; threadsPane.rootId = ""; return }
            threadsPane.channelId = backend.currentChatId
            threadsPane.rootId = ""
            threadsPane.listOpen = true
        }
        chatPhotoId: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.peerMri ? c.peerMri : ""
        }
        myPresence: window.myPresence
        chatPresence: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.presence ? c.presence : ""
        }
        peerNote: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.peerNote ? c.peerNote : null
        }
        messages: backend.messagesJson ? JSON.parse(backend.messagesJson) : []
        busy: backend.busy
        onSend: text => backend.sendMessage(text)
        onCall: backend.startCall()
        onVideoCall: backend.startVideoCall()
        onTyping: backend.userTyping()
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onEditMessage: (id, text) => backend.editMessage(id, text)
        onOpenChatSettings: { settingsView.page = "chats"; rail.current = "settings" }
        onScheduleMeeting: { rail.current = "calendar"; calendarView.newMeeting() }
        onOpenInNewWindow: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId) || {}
            window.openChatWindow(backend.currentChatId, backend.currentChatName, c.peerMri || "", c.presence || "")
        }
        onShareScreen: window.callAndShare()
        onReportConcern: chatList.reportMeetingChat(backend.currentChatId)
        onDeleteMessage: id => backend.deleteMessage(id)
        onSendReply: (id, text) => backend.sendReply(id, text)
        onGetMoreApps: rail.current = "add"
        typingText: backend.typingText
        typingAvatar: backend.typingAvatar
        typingAvatarId: backend.typingAvatarId
    }

    // A channel tab's conversation, beside the channel (Teams' end slot).
    // A Threads-layout channel's open thread, beside it.
    ThreadsPane {
        id: threadsPane
        // Open on its list (Open threads) or a thread.
        property bool listOpen: false
        readonly property bool shown: conversation.visible && conversation.threadsLayout && (!!rootId || listOpen) && channelId === backend.currentChatId
        visible: shown
        anchors { top: appBanner.bottom; bottom: statusBar.top; right: parent.right }
        width: shown ? 360 : 0
        host: conversation
        teamId: conversation.teamId; teamName: conversation.teamName
        myName: backend.userName
        onClosed: { rootId = ""; listOpen = false }
        onJumpTo: id => conversation.jumpToMessage(id)
        onPopOut: id => conversation.openThreadWindow({ id: id, root_id: id })
    }
    // Find in chat / channel (Teams' pane on the right).
    FindPane {
        id: findPane
        readonly property bool shown: conversation.visible && conversation.finding && conversation.tab === ""
        visible: shown
        anchors { top: appBanner.bottom; bottom: statusBar.top; right: tabConversation.left }
        width: shown ? 360 : 0
        chatId: backend.currentChatId
        isChannel: conversation.isChannel
        channelGroup: conversation.isChannel ? conversation.teamId : ""
        members: { try { return JSON.parse(backend.chatMembersJson || "[]") } catch (e) { return [] } }
        onShownChanged: if (shown) focusField()
        onClosed: conversation.finding = false
        onJumpTo: (hit, terms) => conversation.showFound(hit.id, terms, conversation.isChannel && hit.parent_id ? hit.parent_id : "")
    }
    TabConversationPane {
        id: tabConversation
        readonly property bool shown: conversation.visible && !!conversation.tabConversationTab
        visible: shown
        anchors { top: appBanner.bottom; bottom: statusBar.top; right: threadsPane.left }
        width: shown ? 360 : 0
        // The tab as now listed (its conversation appears once started).
        tab: conversation.tabConversationTab ? (conversation.channelTabs.find(t => t.id === conversation.tabConversationTab.id) || conversation.tabConversationTab) : null
        teamId: conversation.teamId; teamName: conversation.teamName
        channelId: conversation.chatId
        myName: backend.userName
        channelTabs: conversation.channelTabs
        onClosed: conversation.tabConversationTab = null
        onOpenTab: id => { const t = conversation.channelTabs.find(x => x.id === id); if (t) conversation.tab = t.name }
    }

    Rectangle {
        id: statusBar
        anchors { left: chatList.right; right: parent.right; bottom: parent.bottom }
        height: backend.statusText ? 24 : 0
        visible: height > 0
        color: theme.unreadTint
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: backend.statusText
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.danger
        }
    }
}
