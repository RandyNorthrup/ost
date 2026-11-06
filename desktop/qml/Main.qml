import QtQuick
import QtQuick.Window
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
    minimumWidth: Math.min(960, startSize[0])
    minimumHeight: Math.min(600, startSize[1])
    visible: true
    title: backend.currentChatName ? backend.currentChatName + " | OST" : "OST"
    color: theme.surface
    // Teams desktop draws its own title bar and window buttons.
    flags: (backend.systemFrame ? Qt.Window : (Qt.Window | Qt.FramelessWindowHint))
        | (pinned ? Qt.WindowStaysOnTopHint : 0)

    // Light or dark, as chosen in Settings > Appearance (default: the
    // system's, like Teams' "Follow operating system theme"). --theme=dark
    // forces one for captures.
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
    // then reset (capturing the menu).
    Timer {
        running: Qt.application.arguments.indexOf("--status-test") >= 0 && backend.signedIn && backend.userMail.length > 0
        interval: 1500
        property int step: 0
        repeat: true
        onTriggered: {
            if (step === 0) titleBar.openProfileForTest()
            else if (step === 1) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-profile.png")))
            else if (step === 2) { backend.setMyStatus("Busy") }
            else if (step === 4) { console.warn("STATUS after busy", titleBar.presence); backend.setMyStatus("Reset") }
            else if (step === 6) { console.warn("STATUS reset"); Qt.quit() }
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
    property bool signInShot: false
    readonly property string shotPath: Qt.application.arguments.length > 1 ? Qt.application.arguments[1] : ""
    Timer {
        id: shotTimer
        interval: 15000
        running: window.shotPath.length > 0 && !window.callTest && !window.typingTest && !window.reactTest && !window.editTest && !window.newChatTest && Qt.application.arguments.indexOf("--search-test") < 0 && Qt.application.arguments.indexOf("--channel-test") < 0 && Qt.application.arguments.indexOf("--emoji-test") < 0 && Qt.application.arguments.indexOf("--format-test") < 0 && Qt.application.arguments.indexOf("--header-test") < 0 && Qt.application.arguments.indexOf("--status-test") < 0 && Qt.application.arguments.indexOf("--calendar-test") < 0 && Qt.application.arguments.indexOf("--group-test") < 0 && Qt.application.arguments.indexOf("--keys-test") < 0 && Qt.application.arguments.indexOf("--mentions-test") < 0 && Qt.application.arguments.indexOf("--join-test") < 0 && Qt.application.arguments.indexOf("--event-card-test") < 0 && Qt.application.arguments.indexOf("--group-call-test") < 0 && Qt.application.arguments.indexOf("--onedrive-test") < 0 && Qt.application.arguments.indexOf("--planner-test") < 0 && Qt.application.arguments.indexOf("--apps-test") < 0 && Qt.application.arguments.indexOf("--channel-files-test") < 0 && Qt.application.arguments.indexOf("--store-test") < 0 && Qt.application.arguments.indexOf("--webapp-test") < 0
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
            const waitText = Qt.application.arguments.length > 3 ? Qt.application.arguments[3] : ""
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
            const sendText = Qt.application.arguments.length > 2 ? Qt.application.arguments[2] : ""
            if (sendText && !window.sentTest) {
                window.sentTest = true
                backend.sendMessage(sendText)
                restart()
                return
            }
            // --reply-test takes over once the channel is open.
            if (Qt.application.arguments.indexOf("--reply-test") >= 0) return
            console.warn("shot: signedIn", backend.signedIn, "chats", backend.chatsJson.length, "status", backend.statusText)
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
            } else if (step === 14 + window.joinStay) { backend.hangUp() }
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
            else if (step === 6) Qt.quit()
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
        unreadChats: chatList.chats.filter(c => c.unread).length
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
        chatPresence: {
            const c = chatList.chats.find(c => c.id === backend.currentChatId)
            return c && c.presence ? c.presence : ""
        }
        messages: backend.messagesJson ? JSON.parse(backend.messagesJson) : []
        busy: backend.busy
        onSend: text => backend.sendMessage(text)
        onCall: backend.startCall()
        onTyping: backend.userTyping()
        onReact: (id, key, on) => backend.toggleReaction(id, key, on)
        onEditMessage: (id, text) => backend.editMessage(id, text)
        onDeleteMessage: id => backend.deleteMessage(id)
        onSendReply: (id, text) => backend.sendReply(id, text)
        typingText: backend.typingText
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
