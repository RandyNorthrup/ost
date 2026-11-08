import QtQuick
import QtQuick.Window
import QtWebEngine
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
    Shortcut { sequence: "Ctrl+J"; onActivated: if (conversation.visible) conversation.jumpToNewest() }
    Shortcut { sequence: "Alt+P"; onActivated: if (conversation.visible) conversation.toggleDetails() }
    Shortcut { sequence: "Alt+Shift+O"; onActivated: if (conversation.visible) conversation.attachFile() }
    Shortcut { sequence: "Shift+Esc"; onActivated: backend.markAllRead() }
    Shortcut { sequence: "Ctrl+Alt+Z"; onActivated: chatList.clearFilters() }
    Shortcut { sequence: "Ctrl+Alt+C"; onActivated: { rail.current = "chat"; chatList.setChip("chats") } }
    Shortcut { sequence: "Ctrl+Alt+A"; onActivated: { rail.current = "chat"; chatList.setChip("channels") } }
    Shortcut { sequence: "Ctrl+Alt+U"; onActivated: { rail.current = "chat"; chatList.setChip("unread") } }
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
    Shortcut { sequence: "Ctrl+Shift+H"; context: Qt.ApplicationShortcut; onActivated: if (["calling", "connecting", "connected"].indexOf(backend.callState) >= 0) backend.hangUp() }
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
            titleBar.statusNoteSaved(!!r.ok, r.message || "", !!r.pinned)
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
    onTrayShownChanged: refreshTray()
    onTrayKindChanged: refreshTray()
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
    function goBack() { if (navIndex > 0) navApply(navIndex - 1) }
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
            else if (step === 5) { conversation.tab = ""; console.warn("HEADER find 'OST test'", conversation.findForTest("ost test")) }
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
        running: window.shotPath.length > 0 && !window.callTest && !window.typingTest && !window.reactTest && !window.editTest && !window.newChatTest && Qt.application.arguments.indexOf("--search-test") < 0 && Qt.application.arguments.indexOf("--channel-test") < 0 && Qt.application.arguments.indexOf("--emoji-test") < 0 && Qt.application.arguments.indexOf("--format-test") < 0 && Qt.application.arguments.indexOf("--header-test") < 0 && Qt.application.arguments.indexOf("--status-test") < 0 && Qt.application.arguments.indexOf("--calendar-test") < 0 && Qt.application.arguments.indexOf("--group-test") < 0 && Qt.application.arguments.indexOf("--keys-test") < 0 && Qt.application.arguments.indexOf("--mentions-test") < 0 && Qt.application.arguments.indexOf("--join-test") < 0 && Qt.application.arguments.indexOf("--event-card-test") < 0 && Qt.application.arguments.indexOf("--group-call-test") < 0 && Qt.application.arguments.indexOf("--meet-now-test") < 0 && Qt.application.arguments.indexOf("--mute-test") < 0 && Qt.application.arguments.indexOf("--video-call-test") < 0 && Qt.application.arguments.indexOf("--meeting-chat-test") < 0 && Qt.application.arguments.indexOf("--breakpoints-test") < 0 && Qt.application.arguments.indexOf("--fun-picker-test") < 0 && Qt.application.arguments.indexOf("--media-order-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--custom-emoji")) && Qt.application.arguments.indexOf("--onedrive-test") < 0 && Qt.application.arguments.indexOf("--planner-test") < 0 && Qt.application.arguments.indexOf("--apps-test") < 0 && Qt.application.arguments.indexOf("--channel-files-test") < 0 && Qt.application.arguments.indexOf("--store-test") < 0 && Qt.application.arguments.indexOf("--webapp-test") < 0 && Qt.application.arguments.indexOf("--loop-test") < 0 && Qt.application.arguments.indexOf("--tab-menu-test") < 0 && Qt.application.arguments.indexOf("--delete-undo-test") < 0
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
    PreJoin {
        id: preJoin
        onJoin: (micOn, withAudio) => {
            window.muteOnJoin = !micOn
            window.noAudioOnJoin = !withAudio
            backend.joinMeeting(joinUrl, subject)
        }
    }
    // Joining with the mic off (pre-join switch): mute once connected.
    property bool muteOnJoin: false
    // "Don't use audio": no sound either way once connected.
    property bool noAudioOnJoin: false
    Connections {
        target: backend
        function onCallStateChanged() {
            if (backend.callState === "connected" && window.muteOnJoin) {
                window.muteOnJoin = false
                if (!backend.callMuted) backend.toggleMute()
            }
            if (backend.callState === "connected" && window.noAudioOnJoin) {
                window.noAudioOnJoin = false
                backend.useNoAudio()
            }
        }
    }
    Connections {
        target: backend
        function onMeetingReaction(mri, name) {
            callWindow.showReaction(mri, name)
            // --join-watch-reaction: capture the first reaction from someone else.
            if (Qt.application.arguments.indexOf("--join-watch-reaction") >= 0 && mri.toLowerCase() !== backend.userMri.toLowerCase())
                reactionShot.restart()
        }
    }
    Timer { id: reactionShot; interval: 400; onTriggered: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-their-reaction.png"))) }
    CallWindow {
        id: callWindow
        visible: ["calling", "connecting", "connected", "ended"].indexOf(backend.callState) >= 0
        peer: backend.callPeer
        selfName: backend.userName
        state: backend.callState
        muted: backend.callMuted
        hasAudio: backend.callHasAudio
        onLeave: backend.hangUp()
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
        lobby: backend.callLobbyJson ? JSON.parse(backend.callLobbyJson) : []
        onAdmitLobby: (id, name, notBot) => backend.admitFromLobby(id, name, notBot)
        onDenyLobby: (id, name) => backend.denyFromLobby(id, name)
        onAdmitAllLobby: backend.admitAllFromLobby()
        onEndMeeting: backend.endMeeting()
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
        running: Qt.application.arguments.indexOf("--join-view") >= 0 && backend.callState === "connected" && backend.callRosterJson.length > 4
        interval: 3000; repeat: true
        property int step: 0
        readonly property var plan: [
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
    readonly property bool joinRaise: Qt.application.arguments.indexOf("--join-raise") >= 0
    readonly property int joinStay: Math.round(parseInt((Qt.application.arguments.find(a => a.startsWith("--join-stay=")) || "--join-stay=0").slice(12)) / 2)
    Timer {
        running: Qt.application.arguments.indexOf("--join-test") >= 0 && backend.signedIn && backend.calendarJson.indexOf("OST calendar test") >= 0
        interval: 2000; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) {
                const ev = JSON.parse(backend.calendarJson).find(e => e.subject.indexOf("OST calendar test") === 0 && e.join_url)
                console.warn("JOIN event found", !!ev)
                calendarView.joinMeeting(ev.join_url, ev.subject)
            } else if (step === 1) {
                if (Qt.application.arguments.indexOf("--join-noaudio") >= 0) preJoin.audio = "room"
                preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-prejoin.png")))
            } else if (step === 2) {
                // --join-noaudio: pick Room audio (capture), then Don't use audio.
                if (Qt.application.arguments.indexOf("--join-noaudio") >= 0) preJoin.audio = "none"
                // --join-muted: switch the mic off in pre-join.
                const noAudio = preJoin.audio === "none"
                preJoin.close(); preJoin.join(!noAudio && Qt.application.arguments.indexOf("--join-muted") < 0, !noAudio)
            } else if (step === 6) {
                callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-alone.png")))
                console.warn("JOIN lobby", backend.callLobbyJson)
            } else if (step === 8 && Qt.application.arguments.indexOf("--join-camera") >= 0) {
                // --join-camera: turn the camera on in the meeting.
                backend.toggleCamera()
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
                console.warn("JOIN state", backend.callState, "audio", backend.callHasAudio, "muted", backend.callMuted, "roster", backend.callRosterJson.length, "status", backend.statusText)
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
            else if (step === 15) Qt.quit()
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
            else if (step === 5) cf.newFolderForTest("OST channel test")
            else if (step === 6) { console.warn("CF made", cf.items.some(i => i.name === "OST channel test")); cap("made"); cf.deleteForTest("OST channel test") }
            else if (step === 8) { console.warn("CF deleted", !cf.items.some(i => i.name === "OST channel test")); Qt.quit() }
            step++
        }
    }

    // --store-test: open the Store, capture Home, search "planner", open
    // Whiteboard's details.
    Timer {
        running: Qt.application.arguments.indexOf("--store-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) rail.current = "add"
            else if (step === 4 && store.busy) return
            else if (step === 4) { console.warn("STORE apps", store.apps.length, "microsoft", store.microsoft.length, store.reply.error || ""); cap("home") }
            else if (step === 5) { store.searchForTest("planner") }
            else if (step === 6) { console.warn("STORE results", store.results.length, store.results.slice(0, 3).map(a => a.name).join(", ")); cap("search") }
            else if (step === 7) { store.searchForTest(""); console.warn("STORE details", store.detailsForTest("Whiteboard")) }
            else if (step === 9) cap("details")
            else if (step === 10) Qt.quit()
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

    // --mention-test=<query> with --open-chat=<id> --shots=<dir>: type a
    // message with "@<query>", capture the picker, pick the first person,
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
            else if (step === 1) { shot("picker"); console.warn("MENTION-TEST targets", JSON.stringify(c.channelMention), JSON.stringify(c.teamMention), conversation.chatName, conversation.teamId) }
            else if (step === 2) c.pickMentionForTest()
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

    // Teams' in-app toast (measured): a 288 x 46 card, radius 8, 83 from the
    // window's left and 16 from its bottom. A 16 px intent icon at (13, 15),
    // the title (14 semibold) at (37, 13), dismiss (24 x 20) at (251, 13).
    // Success stays 5 s, errors 2 s.
    Item {
        id: toast
        property var toastData: null
        visible: toastData !== null
        z: 200
        x: 83; y: window.height - 16 - height
        width: 288; height: 46
        FluentSurface { anchors.fill: parent; depth: 16; radius: 8; color: theme.surface }
        FluentIcon {
            x: 13; y: 15; size: 16
            name: toast.toastData && toast.toastData.intent === "error" ? "error-circle-20-filled" : "checkmark-circle-20-filled"
            color: toast.toastData && toast.toastData.intent === "error" ? theme.redForeground1 : theme.successFg
        }
        Text { x: 37; y: 13; height: 20; verticalAlignment: Text.AlignVCenter; text: toast.toastData ? toast.toastData.text : ""; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
        Rectangle {
            x: 251; y: 13; width: 24; height: 20; radius: 4
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
            function onToastJsonChanged() {
                if (!backend.toastJson) return
                toast.toastData = JSON.parse(backend.toastJson)
                toastTimer.interval = toast.toastData.intent === "error" ? 2000 : 5000
                toastTimer.restart()
            }
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
        canGoBack: window.navIndex > 0
        canGoForward: window.navIndex < window.navStack.length - 1
        onGoBack: window.goBack()
        onGoForward: window.goForward()
        onToggleRail: rail.collapsed = !rail.collapsed
        onOpenSettings: rail.current = "settings"
        onOpenShortcuts: shortcutsDialog.open()
        userMail: backend.userMail
        orgName: backend.orgName
        onSetStatus: st => backend.setMyStatus(st)
        onSetStatusUntil: (st, dur) => backend.setMyStatusUntil(st, dur, "")
        onSetStatusNote: (msg, pinned, clearAfter) => backend.setStatusNote(msg, pinned, clearAfter, "")
        pinned: window.pinned
        onTogglePin: window.pinned = !window.pinned
        windowButtons: !backend.systemFrame
    }

    SignIn {
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
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
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left }
        // Muted chats don't count toward the badge (Teams' doesContributeToBadgeCount).
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
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: chatList.right; right: parent.right }
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
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
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
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
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
        visible: ["chat", "calls", "calendar", "activity", "settings", "onedrive", "planner", "people", "onenote", "add", "whiteboard", "clipchamp", "help"].indexOf(rail.current) < 0
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
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
            { key: "help", name: "Help", icon: "question-circle-20", color: theme.textStrong, url: "https://support.microsoft.com/teams" }
        ]
        Loader {
            required property var modelData
            property bool opened: false
            visible: rail.current === modelData.key
            onVisibleChanged: if (visible) opened = true
            active: opened
            anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
            sourceComponent: WebApp { appName: modelData.name; appIcon: modelData.icon; appColor: modelData.color; home: modelData.url }
        }
    }
    StoreView {
        id: store
        visible: rail.current === "add"
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        reply: backend.storeJson ? JSON.parse(backend.storeJson) : ({})
        busy: backend.storeBusy
        onLoad: backend.storeLoad()
        onOpenApp: key => rail.openApp(key)
    }
    PeopleView {
        id: peopleApp
        visible: rail.current === "people"
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
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
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        reply: backend.onenoteJson ? JSON.parse(backend.onenoteJson) : ({})
        busy: backend.onenoteBusy
        onLoad: (v, id) => backend.onenoteLoad(v, id)
        onCreate: (kind, parent, name, text) => backend.onenoteCreate(kind, parent, name, text)
        onRemovePage: id => backend.onenoteDeletePage(id)
    }
    PlannerView {
        id: planner
        visible: rail.current === "planner"
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
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
    OneDriveView {
        id: oneDrive
        visible: rail.current === "onedrive"
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
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
    ChatList {
        id: chatList
        visible: rail.current === "chat"
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right }
        chats: backend.chatsJson ? JSON.parse(backend.chatsJson) : []
        teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        currentId: backend.currentChatId
        onChatSelected: (id, name) => { window.composing = false; draftsOpen = false; mentionsOpen = false; backend.selectChat(id, name) }
        onNewChat: { draftsOpen = false; mentionsOpen = false; window.composing = true }
        onMarkAllRead: backend.markAllRead()
        draftIds: (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).map(d => d.id)
        onOpenDrafts: { window.composing = false; mentionsOpen = false; draftsOpen = true }
        hasMentions: mentionsView.mentions.length > 0
        onOpenMentions: { window.composing = false; draftsOpen = false; mentionsOpen = true; mentionsView.selectedId = "" }
    }
    MentionsView {
        id: mentionsView
        visible: rail.current === "chat" && chatList.mentionsOpen
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
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
    DraftsView {
        id: draftsView
        visible: rail.current === "chat" && chatList.draftsOpen
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
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
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
    }
    ActivityView {
        id: activityView
        visible: rail.current === "activity"
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right }
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
    Conversation {
        id: conversation
        myName: backend.userName
        visible: (rail.current === "chat" && !chatList.draftsOpen && (!chatList.mentionsOpen || mentionsView.selectedId.length > 0))
            || (rail.current === "activity" && activityView.selectedId.length > 0)
        chatId: backend.currentChatId
        anchors { top: titleBar.bottom; bottom: statusBar.top; right: parent.right
            left: rail.current === "activity" ? activityView.right : chatList.right
            leftMargin: rail.current === "chat" && chatList.mentionsOpen ? mentionsView.paneWidth : 0 }
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
        chatPhotoId: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.peerMri ? c.peerMri : ""
        }
        myPresence: window.myPresence
        chatPresence: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.presence ? c.presence : ""
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
        onDeleteMessage: id => backend.deleteMessage(id)
        onSendReply: (id, text) => backend.sendReply(id, text)
        typingText: backend.typingText
        typingAvatar: backend.typingAvatar
        typingAvatarId: backend.typingAvatarId
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
