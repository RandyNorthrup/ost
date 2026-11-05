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

    Theme { id: theme }
    Shortcut { sequence: "Ctrl+Alt+G"; onActivated: titleBar.focusSearch() }
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
        running: window.shotPath.length > 0 && !window.callTest && !window.typingTest && !window.reactTest && !window.editTest && !window.newChatTest && Qt.application.arguments.indexOf("--search-test") < 0 && Qt.application.arguments.indexOf("--channel-test") < 0
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
                backend.selectChat(chats[0].id, chats[0].name)
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
            console.warn("shot: signedIn", backend.signedIn, "chats", backend.chatsJson.length, "status", backend.statusText)
            window.contentItem.grabToImage(r => { r.saveToFile(window.shotPath); Qt.quit() })
        }
    }

    IncomingCall {
        id: incomingCall
        visible: backend.callState === "ringing"
        peer: backend.callPeer
        videoOffered: backend.callVideoOffered
        onAcceptVideo: backend.acceptCall(true)
        onAcceptAudio: backend.acceptCall(false)
        onDecline: backend.declineCall()
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
        onClosing: if (backend.callState !== "ended") backend.hangUp()
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
    readonly property bool callTest: callOut || Qt.application.arguments.indexOf("--call-test") >= 0
    // --remote-hangup: stay in the call until the caller ends it.
    readonly property bool remoteHangup: Qt.application.arguments.indexOf("--remote-hangup") >= 0
    Connections {
        target: backend
        enabled: window.callTest
        function onCallStateChanged() {
            console.warn("CALL-STATE", backend.callState)
            if (backend.callState === "ringing") {
                callTestTimer.step = "ring"; callTestTimer.restart()
            } else if (backend.callState === "connected") {
                callTestTimer.step = "talk"; callTestTimer.interval = 8000; callTestTimer.restart()
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
                    backend.acceptCall(false)
                })
            } else if (step === "talk") {
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
    // --call-out: open the first chat and call it.
    Timer {
        running: window.callOut && backend.signedIn && !backend.callState
        interval: 4000
        onTriggered: {
            const chats = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
            if (!backend.currentChatId && chats.length > 0) { backend.selectChat(chats[0].id, chats[0].name); restart(); return }
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
        onSignOut: backend.signOut()
        chats: chatList.chats
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearchPeople: q => backend.searchPeople(q)
        onOpenChat: (id, name) => { rail.current = "chat"; window.composing = false; backend.selectChat(id, name) }
        onOpenPerson: (oid, name) => { rail.current = "chat"; window.composing = false; backend.openChatWith(oid, name) }
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
        // --view=<app> opens that rail app (for captures).
        Component.onCompleted: {
            const v = Qt.application.arguments.find(a => a.startsWith("--view="))
            if (v) current = v.substring(7)
        }
        onCurrentChanged: if (current === "calls") backend.loadCalls()
    }

    property bool composing: Qt.application.arguments.indexOf("--new-chat") >= 0
    NewChat {
        visible: window.composing && rail.current === "chat"
        z: 3
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: chatList.right; right: parent.right }
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        onSearch: q => backend.searchPeople(q)
        onChosen: (oid, name) => { window.composing = false; backend.openChatWith(oid, name) }
        onCancelled: window.composing = false
    }

    CallsView {
        visible: rail.current === "calls"
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        calls: backend.callsJson ? JSON.parse(backend.callsJson) : []
        onOpenChatWith: (mri, name) => {
            const c = chatList.chats.find(c => c.peerMri === mri)
            if (c) backend.selectChat(c.id, c.name)
            rail.current = "chat"
        }
    }

    CalendarView {
        visible: rail.current === "calendar"
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        events: backend.calendarJson ? JSON.parse(backend.calendarJson) : []
        onRangeChanged: (s, e) => backend.loadCalendar(s, e)
    }

    // Apps not built yet: an honest placeholder instead of the chat.
    Rectangle {
        visible: ["chat", "calls", "calendar"].indexOf(rail.current) < 0
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        color: theme.surface
        Text {
            anchors.centerIn: parent
            text: "This app isn't available in OST yet."
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
    }
    ChatList {
        id: chatList
        visible: rail.current === "chat"
        anchors { top: titleBar.bottom; bottom: parent.bottom; left: rail.right }
        chats: backend.chatsJson ? JSON.parse(backend.chatsJson) : []
        teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        currentId: backend.currentChatId
        onChatSelected: (id, name) => { window.composing = false; backend.selectChat(id, name) }
        onNewChat: window.composing = true
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
    Conversation {
        visible: rail.current === "chat"
        anchors { top: titleBar.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        chatName: backend.currentChatName
        isChannel: backend.currentChatId.endsWith("@thread.tacv2")
        teamName: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const t = teams.find(t => t.channels.some(c => c.id === backend.currentChatId))
            return t ? t.name : ""
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
        typingText: backend.typingText
    }

    Rectangle {
        id: statusBar
        anchors { left: chatList.right; right: parent.right; bottom: parent.bottom }
        height: backend.statusText ? 24 : 0
        visible: height > 0
        color: "#FDF3F4"
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: backend.statusText
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.danger
        }
    }
}
