import QtQuick
import QtMultimedia
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
        dark: mode === "dark" || mode === "highContrast" || (mode === "system" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)
        classic: mode === "classic"
        highContrast: mode === "highContrast"
    }
    // The app's theme (call windows keep their own, see callsDark).
    readonly property QtObject appTheme: theme
    /// Teams' "Always use dark theme for calls and meetings" (its
    /// isCallingWindowDarkTheme, kept on this device); only in Light.
    property bool darkCallSetting: backend.setting("darkCallTheme") === "true"
    readonly property bool callsDark: darkCallSetting && !theme.dark && !theme.classic
    /// Teams' App bar settings (its appBar client preferences, kept on this
    /// device): app names under the icons, and folding the bar away after
    /// you pick an app.
    property bool appBarNames: backend.setting("appBarShowNames") === "true"
    property bool appBarAutoCollapse: backend.setting("appBarAutoCollapse") === "true"
    // Teams' "Green screen settings": Settings ▸ Devices at Green Screen,
    // in the main window.
    function showGreenScreenSettings() {
        rail.current = "settings"
        settingsView.showGreenScreen()
        window.show(); window.raise(); window.requestActivate()
    }
    // The Editor card's Editor settings... / Manage languages...: Settings ▸
    // General at Editor spellcheck, or its Manage spellcheck languages page.
    function showEditorSettings(manage) {
        rail.current = "settings"
        settingsView.showEditor(manage)
        window.show(); window.raise(); window.requestActivate()
    }
    // Your video effects (Camera ▾, pre-join, the Video effects pane).
    VideoEffectsState { id: videoEffects }
    // Teams' Filters: its Custom Filters app, hosted out of sight.
    VideoFilterHost {
        id: videoFilterHost
        z: -100
        effectId: videoEffects.filter
        appUrl: videoEffects.filters.url || ""
    }
    // Teams desktop's shortcuts: Ctrl+E search, Ctrl+G go to a chat.
    Shortcut { sequence: "Ctrl+E"; onActivated: titleBar.focusSearch() }
    Shortcut { sequence: "Ctrl+G"; onActivated: titleBar.focusSearch() }
    Shortcut { sequence: "Alt+Left"; onActivated: window.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: window.goForward() }
    // Rail apps, as in Teams desktop.
    // Teams' keyboard shortcut profile (Settings ▸ General; the synced
    // keyboardShortcutsSettings.shortcutProfile): "default" (Teams only),
    // "chats_alt" (Teams + Slack), "meetings_alt" (Teams + Zoom) or
    // "chats_meetings_alt" (combined), with Teams' Windows desktop key maps.
    readonly property var syncedProps: backend.settingsJson ? (JSON.parse(backend.settingsJson).props || {}) : ({})
    readonly property string shortcutProfile: {
        let v = syncedProps.keyboardShortcutsSettings
        if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { v = null } }
        return (v && v.shortcutProfile) || "default"
    }
    readonly property bool slackShortcuts: shortcutProfile === "chats_alt" || shortcutProfile === "chats_meetings_alt"
    readonly property bool zoomShortcuts: shortcutProfile === "meetings_alt" || shortcutProfile === "chats_meetings_alt"
    Connections { target: backend; function onSignedInChanged() { if (backend.signedIn) { backend.loadSettings(); backend.loadUrlPreviewPolicy(); backend.loadWorkLocationPolicy(); backend.loadPremium() } } }
    // Settings ▸ General ▸ Starting chats (Teams' synced
    // userPersonalSettings.messagingSettings.alwaysPopOutNewChat): a new
    // chat in the main window, or in Teams' "New Message" window; once
    // sent, the chat opens in its own chat window.
    readonly property bool newChatInWindow: ((syncedProps.userPersonalSettings || {}).messagingSettings || {}).alwaysPopOutNewChat === true
    /// Settings ▸ General ▸ "Use Enter or Spacebar to show content" (Teams'
    /// synced messagingSettings.disableAutomaticConvSwitchOnKeyboardNav):
    /// in the chat list, Activity, @mentions and the quick views Up / Down
    /// only move, and Enter or Space opens.
    /// Settings ▸ Accessibility ▸ "Turn on single pointer controls" (kept
    /// on this device, as Teams' clientPreferences): Start reordering.
    property bool singlePointReordering: backend.setting("singlePointReordering") === "true"
    readonly property bool enterToShow:((syncedProps.userPersonalSettings || {}).messagingSettings || {}).disableAutomaticConvSwitchOnKeyboardNav === true
    /// Teams' "Viewing chats, teams, and channels": Separate gives Teams its
    /// own app on the rail (simpleCollabUserSettings' adaptive rail without
    /// the unified app); collabPane says which list Chat shows then.
    readonly property bool splitView: { const s = syncedProps.simpleCollabUserSettings || {}; return s.hasUserEnabledAdaptiveRailForDesktop === true && s.hasUserEnabledUnifiedAppForDesktop === false }
    property string collabPane: "chats"
    function openCollab(pane) { collabPane = pane; rail.current = "chat" }
    // Opening a channel shows the Teams app, a chat Chat.
    Connections {
        target: backend
        function onCurrentChatIdChanged() { if (window.splitView && backend.currentChatId) window.collabPane = backend.currentChatId.endsWith("@thread.tacv2") ? "teams" : "chats" }
    }
    property var newChatWin: null
    property string popOutChatName: ""
    function startNewChat() {
        if (!window.newChatInWindow) { rail.current = "chat"; window.composing = true; return }
        if (window.newChatWin) { window.newChatWin.raise(); window.newChatWin.requestActivate(); return }
        const c = Qt.createComponent("NewChatWindow.qml")
        const w = c.createObject(null, { people: Qt.binding(() => backend.peopleJson ? JSON.parse(backend.peopleJson) : []) })
        w.search.connect(q => backend.newChatPeople(q))
        // The message goes from the chat's compose box (the main window's
        // conversation, which opens the chat too), then the chat window opens.
        w.chosen.connect((oid, name, message) => { window.popOutChatName = name; w.close(); backend.openChatWith(oid, name); if (message) conversation.adoptAndSend(JSON.parse(message)) })
        w.group.connect((oids, topic, message) => { window.popOutChatName = topic || "Group chat"; window.newGroupMessage = message; w.close(); backend.createGroupChat(oids, topic, "") })
        w.scheduleMeetingWith.connect(attendees => { w.close(); rail.current = "calendar"; calendarView.newMeetingWith(attendees, "", "") })
        w.closing.connect(() => { window.newChatWin = null; w.destroy() })
        window.newChatWin = w
        w.show()
    }
    Connections {
        target: backend
        function onCurrentChatIdChanged() {
            if (!window.popOutChatName || !backend.currentChatId) return
            window.openChatWindow(backend.currentChatId, backend.currentChatName || window.popOutChatName, "", "")
            window.popOutChatName = ""
        }
    }
    // Settings ▸ General ▸ Opening content in OST windows: New window.
    Connections { target: backend; function onOpenChatWindowRequested(id, name) { window.openChatWindow(id, name, "", "") } }
    // Teams + Slack: Ctrl+Shift+1… the app bar's apps, Ctrl+; shortcuts,
    // Ctrl+K Go to, Ctrl+. the info pane, Ctrl+Alt+A unread, Ctrl+Alt+U
    // channels.
    Repeater {
        model: window.slackShortcuts ? ["activity", "chat", "calendar", "calls", "onedrive"] : []
        Item { required property string modelData; required property int index
            Shortcut { sequence: "Ctrl+Shift+" + (index + 1); onActivated: rail.current = modelData } }
    }
    Shortcut { enabled: window.slackShortcuts; sequence: "Ctrl+;"; onActivated: shortcutsDialog.open() }
    Shortcut { enabled: window.slackShortcuts; sequence: "Ctrl+K"; onActivated: titleBar.focusSearch() }
    // Teams + Zoom: Ctrl+U the message pane, Alt+H the chat list, Alt+A mute,
    // Alt+V video, Alt+Y raise hand, Alt+S share, Alt+Q / Ctrl+Shift+E leave,
    // Ctrl+Shift+V / Ctrl+Shift+A answer with video / audio.
    Shortcut { enabled: window.zoomShortcuts; sequence: "Ctrl+U"; onActivated: { rail.current = "chat"; conversation.focusCompose() } }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Alt+H"; onActivated: rail.current = "chat" }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Alt+A"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected") backend.toggleMute() }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Alt+V"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected" && backend.callCanVideo) backend.toggleCamera() }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Alt+Y"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected") callWindow.runControl("RaiseHandsButton") }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Alt+S"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected") callWindow.runControl("ShareButton") }
    Shortcut { enabled: window.zoomShortcuts; sequences: ["Alt+Q", "Ctrl+Shift+E"]; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "connected") callWindow.leaveAsked() }
    Shortcut { enabled: window.zoomShortcuts; sequence: "Ctrl+Shift+V"; context: Qt.ApplicationShortcut; onActivated: if (backend.callState === "ringing") backend.acceptCall(backend.callVideoOffered) }
    Shortcut { sequence: "Ctrl+1"; onActivated: rail.current = "activity" }
    // Separate view: Teams takes Ctrl+3 and the rest move down one.
    Shortcut { sequence: "Ctrl+2"; onActivated: window.splitView ? window.openCollab("chats") : rail.current = "chat" }
    Shortcut { sequence: "Ctrl+3"; onActivated: window.splitView ? window.openCollab("teams") : rail.current = "calendar" }
    Shortcut { sequence: "Ctrl+4"; onActivated: rail.current = window.splitView ? "calendar" : "calls" }
    Shortcut { sequence: "Ctrl+5"; onActivated: rail.current = window.splitView ? "calls" : "onedrive" }
    Shortcut { sequence: "Ctrl+6"; enabled: window.splitView; onActivated: rail.current = "onedrive" }
    Shortcut { sequence: "Ctrl+,"; onActivated: rail.current = "settings" }
    Shortcut { sequence: "Ctrl+N"; onActivated: { chatList.draftsOpen = false; chatList.mentionsOpen = false; window.startNewChat() } }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: window.pinned = !window.pinned }
    // The rest of Teams' shortcuts that OST supports (listed by Ctrl+.).
    Shortcut { sequence: "Ctrl+."; onActivated: if (window.slackShortcuts) { if (conversation.visible) conversation.toggleDetails() } else shortcutsDialog.open() }
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
    // Teams' Mark all as read (Shift+Esc) and Collapse all sections (Alt+Q)
    // are the chat list header's commands: they act while the list shows.
    // Shift+Esc asks first (enableMAARConfirmDialog) until "Don't ask
    // again" (clientPreferences simpleCollab.skipMarkAllAsReadConfirmDialog,
    // kept on this device).
    Shortcut { sequence: "Shift+Esc"; enabled: chatList.visible; onActivated: window.shiftEscMarkAll() }
    Shortcut { sequence: "Alt+Q"; enabled: chatList.visible && !window.zoomShortcuts; onActivated: chatList.collapseAll() }
    function shiftEscMarkAll() {
        if (backend.setting("skipMarkAllAsReadConfirmDialog") === "true") backend.markAllRead(chatList.markAllAppType)
        else markAllDialog.open()
    }
    // Teams' SimpleCollabMarkAllAsReadConfirmDialog: a plain Fluent dialog
    // (600 wide). Its title passes the entities as "entitiesToBeMarked" to
    // a string that wants "entities", so Teams shows none there.
    ConfirmDialog {
        id: markAllDialog
        dialogWidth: 600
        title: "Are you sure you want to mark all as read?"
        body: "This will mark all your " + chatList.markAllEntities + " as read. This action can't be undone."
        confirmText: "Confirm"
        checkText: "Don't ask again"
        onConfirmed: { if (checked) backend.setSetting("skipMarkAllAsReadConfirmDialog", "true"); backend.markAllRead(chatList.markAllAppType) }
        onCancelled: if (checked) backend.setSetting("skipMarkAllAsReadConfirmDialog", "true")
    }
    Shortcut { sequence: "Ctrl+Alt+Z"; onActivated: chatList.clearFilters() }
    Shortcut { sequence: "Ctrl+Alt+C"; onActivated: { rail.current = "chat"; chatList.setChip("chats") } }
    Shortcut { sequence: "Ctrl+Alt+A"; onActivated: { rail.current = "chat"; chatList.setChip(window.slackShortcuts ? "unread" : "channels") } }
    Shortcut { sequence: "Ctrl+Alt+U"; onActivated: { rail.current = "chat"; chatList.setChip(window.slackShortcuts ? "channels" : "unread") } }
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
    Shortcut { sequence: "Ctrl+Shift+H"; context: Qt.ApplicationShortcut; onActivated: if (["calling", "connecting", "connected", "lobby"].indexOf(backend.callState) >= 0) { if (backend.callState === "connected") callWindow.leaveAsked(); else backend.hangUp() } }
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
    // Zoom (Teams' Settings and more ▸ Zoom, measured on winpc 2026-11-15):
    // 60% to 400% in 5% steps, Ctrl+- / Ctrl+= and Ctrl+0 to reset to
    // 100%. The whole window scales (popups too): its root item is drawn
    // scaled and laid out at the window's size divided by the zoom. Kept
    // across restarts (local setting "zoomPercent").
    property int zoomPercent: { const v = parseInt(backend.setting("zoomPercent")); return v >= 60 && v <= 400 ? v : 100 }
    readonly property real zoom: zoomPercent / 100
    function setZoom(p) {
        zoomPercent = Math.max(60, Math.min(400, Math.round(p / 5) * 5))
        backend.setSetting("zoomPercent", String(zoomPercent))
    }
    function zoomIn() { setZoom(zoomPercent + 5) }
    function zoomOut() { setZoom(zoomPercent - 5) }
    function zoomReset() { setZoom(100) }
    function applyZoom() {
        contentItem.transformOrigin = Item.TopLeft
        contentItem.scale = zoom
        contentItem.width = width / zoom
        contentItem.height = height / zoom
    }
    onZoomChanged: applyZoom()
    onWidthChanged: Qt.callLater(applyZoom)
    onHeightChanged: Qt.callLater(applyZoom)
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; context: Qt.WindowShortcut; onActivated: window.zoomIn() }
    Shortcut { sequence: "Ctrl+-"; context: Qt.WindowShortcut; onActivated: window.zoomOut() }
    Shortcut { sequence: "Ctrl+0"; context: Qt.WindowShortcut; onActivated: window.zoomReset() }
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
        function onCallSharingChanged() {
            backend.syncCallPresence()
            // Include sound: the computer's sound goes with the screen.
            backend.setShareSound(backend.callSharing && callWindow.shareIncludeSound)
            // Presenter mode and give control follow the share.
            backend.presentingSharingChanged()
        }
        function onCallCameraOnChanged() { backend.presentingCameraChanged() }
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
    Component.onCompleted: { refreshTaskbarBadge(); backend.installLinkHandler(); Qt.callLater(applyZoom) }

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
    // --presend-test[=<chat name>] with --shots=<dir>: Teams' pre-send
    // checks in that chat (default OST Test 2): each case is put in the
    // compose box and Send pressed with the box in dry-run, so nothing can
    // go; logs PRESEND <case> <banner> <text kept> and captures
    // presend-<case>.png while the banner shows.
    Timer {
        readonly property var args: Qt.application.arguments
        running: args.some(a => a.startsWith("--presend-test")) && backend.signedIn && chatList.chats.length > 1
        interval: 1500; repeat: true
        property int step: 0
        property var chat: null
        onTriggered: {
            const dir = (args.find(a => a.startsWith("--shots=")) || "--shots=/tmp/presend").slice(8) + "/"
            const want = (args.find(a => a.startsWith("--presend-test=")) || "--presend-test=OST Test 2").slice(15)
            const c = conversation.composeForTest()
            const cases = [
                ["empty", () => {}],
                // (insert() reads HTML, which drops plain spaces.)
                ["spaces", () => c.editor.insert(0, "&nbsp; &nbsp;")],
                ["too-large", () => c.insertText("OST presend " + "x".repeat(91000))],
                ["schedule-past", () => { c.insertText("OST presend past"); c.scheduleAt = Date.now() - 60000 }],
                ["clip-uploading", () => { c.insertText("OST presend clip"); c.clip = { uploading: true, path: "", thumb: "", width: 1280, height: 720, duration: 3 } }],
                ["bot-mention", () => { c.sendTo = "channel"; c.insertText("OST presend "); c.editor.insert(c.editor.cursorPosition, '<a href="mention:28:00000000-0000-0000-0000-000000000000">Bot</a>&nbsp;') }],
                ["fine", () => c.insertText("OST presend fine")]
            ]
            if (step === 0) {
                chat = chatList.chats.find(x => x.name === want) || null
                if (!chat) { console.warn("PRESEND no chat", want); Qt.quit(); return }
                backend.selectChat(chat.id, chat.name)
                step = 1; return
            }
            const i = Math.floor((step - 1) / 2)
            if (i >= cases.length) {
                c.dryRun = false; c.clear(); c.scheduleAt = 0; c.clip = null; c.sendTo = ""
                backend.setDraft(chat.id, ""); Qt.quit(); return
            }
            if ((step - 1) % 2 === 0) {
                c.dryRun = true; c.clear(); c.scheduleAt = 0; c.clip = null; c.sendTo = ""; c.bannerText = ""
                cases[i][1]()
                c.trySubmit()
                console.warn("PRESEND", cases[i][0], JSON.stringify(c.bannerText), "kept", c.plainText().length)
                window.contentItem.grabToImage(r => r.saveToFile(dir + "presend-" + cases[i][0] + ".png"))
            }
            step++
        }
    }
    // --draft-roam-test=<out|in|conflict>[,<chat name>] with --shots=<dir>
    // (run with OST_ROAM_DRAFTS=1, as Teams roams drafts only where
    // enableRoamMessageDraft is on). In that chat (default OST Test 2):
    // out: type a draft with a mention, capture it, wait for it to roam,
    //   switch chats (the Drafts view) and back, then clear it (it is
    //   deleted from the service);
    // in: wait for another device's draft to come in, capture the box and
    //   the Drafts view; --draft-roam-clear then clears it;
    // conflict: type a draft of OST's own, wait for the other device's one
    //   to show as a conflict, capture the banner and "Saved draft", then
    //   Discard it (or "Use this version" with --draft-roam-use) and clear.
    // Logs DRAFTROAM lines; nothing is sent.
    Timer {
        readonly property var args: Qt.application.arguments
        readonly property var opts: (args.find(a => a.startsWith("--draft-roam-test=")) || "").slice(18).split(",")
        running: opts[0].length > 0 && backend.signedIn && chatList.chats.length > 1
        interval: 2000; repeat: true
        property int step: 0
        property var chat: null
        onTriggered: {
            const mode = opts[0], want = opts[1] || "OST Test 2"
            const dir = (args.find(a => a.startsWith("--shots=")) || "--shots=/tmp/draftroam").slice(8) + "/"
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(dir + "draft-roam-" + mode + "-" + tag + ".png"))
            const log = (tag, x) => console.warn("DRAFTROAM", mode, tag, JSON.stringify(x))
            const c = conversation.composeForTest()
            const kept = () => JSON.parse(backend.draftJson(chat.id) || "null")
            if (step === 0) {
                chat = chatList.chats.find(x => x.name === want) || null
                if (!chat) { log("no chat", want); Qt.quit(); return }
                backend.selectChat(chat.id, chat.name)
            } else if (mode === "out") {
                if (step === 2) {
                    c.clearForTest(); c.insertText("OST draft roam test ")
                    c.insertMentionOf({ mri: backend.userMri, name: "OST Test 1" })
                    c.insertText("with a mention")
                    conversation.saveDraft(chat.id)
                } else if (step === 3) { log("typed", kept()); cap("typed") }
                // A change: the same draft again (PUT).
                else if (step === 4) { c.insertText(" and a change"); conversation.saveDraft(chat.id) }
                else if (step === 6) {
                    const other = chatList.chats.find(x => x.id !== chat.id)
                    backend.selectChat(other.id, other.name); chatList.openDrafts()
                } else if (step === 7) { log("listed", (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).find(x => x.id === chat.id)); cap("drafts") }
                else if (step === 8) { chatList.draftsOpen = false; backend.selectChat(chat.id, chat.name) }
                else if (step === 9) { log("back", c.plainText()); cap("back") }
                else if (step === 10) { c.clear(); conversation.saveDraft(chat.id) }
                else if (step === 13) { log("cleared", kept()); Qt.quit() }
            } else if (mode === "in") {
                if (step >= 2 && step < 20 && (c.plainText().trim() || step === 19)) {
                    log("box", c.plainText()); log("kept", kept()); cap("box")
                    chatList.openDrafts(); step = 20
                } else if (step === 21) {
                    log("listed", (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).find(x => x.id === chat.id)); cap("drafts")
                } else if (step === 22) {
                    chatList.draftsOpen = false; backend.selectChat(chat.id, chat.name)
                } else if (step === 23) {
                    if (args.indexOf("--draft-roam-clear") >= 0) { c.clear(); conversation.saveDraft(chat.id) }
                } else if (step === 25) { log("end", kept()); Qt.quit() }
            } else if (mode === "conflict") {
                if (step === 2) { c.clearForTest(); c.insertText("OST draft roam conflict, this device's"); conversation.saveDraft(chat.id) }
                else if (step >= 3 && step < 30 && (c.draftConflict || step === 29)) {
                    log("banner", c.draftConflict); log("conflict", c.conflictDraft); cap("banner")
                    step = 29
                } else if (step === 30) c.viewConflict()
                else if (step >= 3 && step < 30) {
                    // Opening the chat again reads the service's drafts.
                    const other = chatList.chats.find(x => x.id !== chat.id)
                    if (step % 3 === 0) backend.selectChat(other.id, other.name)
                    else if (step % 3 === 1) backend.selectChat(chat.id, chat.name)
                } else if (step === 31) cap("dialog")
                else if (step === 32) { c.conflictDialogForTest().close(); c.conflictResolved(args.indexOf("--draft-roam-use") >= 0) }
                else if (step === 33) { log("resolved", kept()); log("box", c.plainText()); cap("resolved") }
                else if (step === 34) { c.clear(); conversation.saveDraft(chat.id) }
                else if (step === 37) { log("cleared", kept()); Qt.quit() }
            }
            step++
        }
    }
    // --draft-format-test: in "OST group test" (or --open-chat=<id>), type
    // a draft with every format (bold, italic, underline, strike, inline
    // code, a heading, a quote, lists, a link, a mention, an emoticon, a
    // code block and a table), switch to another chat and back, capture it
    // and check the box's HTML came back as typed. Nothing is sent; the
    // draft stays for the second run. --draft-format-restart: the second
    // run, after a restart: open the chat, capture, check the box against
    // the kept draft, then clear the draft.
    Timer {
        running: Qt.application.arguments.indexOf("--draft-format-test") >= 0 && backend.signedIn && chatList.chats.length > 1
        interval: 2000; repeat: true
        property int step: 0
        property var chat: null
        property string typed: ""
        onTriggered: {
            const restart = Qt.application.arguments.indexOf("--draft-format-restart") >= 0
            const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (tag, x) => console.warn("DRAFT-FORMAT", tag, JSON.stringify(x))
            // Code blocks get a new id on every export.
            const same = h => String(h || "").replace(/codeBlockEditor-[0-9a-f-]+/g, "codeBlockEditor-id")
            const c = conversation.composeForTest()
            if (step === 0) {
                chat = chatList.chats.find(x => want ? x.id === want : x.name === "OST group test") || null
                if (!chat) { log("no chat", want || "OST group test"); Qt.quit(); return }
                backend.selectChat(chat.id, chat.name)
            } else if (!restart) {
                if (step === 2) {
                    c.clearForTest(); c.formatting = true
                    c.formatLineForTest("OST draft format test", "heading", "2")
                    c.formatLineForTest("Bold words", "bold", "")
                    c.formatLineForTest("Italic words", "italic", "")
                    c.formatLineForTest("Underlined words", "underline", "")
                    c.formatLineForTest("Struck words", "strike", "")
                    c.formatLineForTest("inline code", "code", "")
                    c.formatLineForTest("Highlighted", "bg", "#FDD472")
                    // Typed for real, so the spaces are as typed.
                    c.formatLineForTest("Spaces:", "", ""); c.focusEditor(); draftTyper.typeText("  two  spaces")
                    c.formatLineForTest("A quoted line", "quote", "")
                    c.formatLineForTest("A bullet", "ul", "")
                    c.formatLineForTest("A numbered item", "ol", "")
                    c.formatLineForTest("", "link", "https://example.com/\tAn example link")
                    c.formatLineForTest("Mention: ", "", "")
                    c.insertMentionOf({ mri: backend.userMri, name: "OST Test 1" })
                    c.insertMedia({ src: "https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/smile/default/20_f.png", kind: "emoji", id: "smile", title: "Smile", unicode: "\u{1F642}" })
                    c.formatLineForTest("", "codeblock", "")
                    c.insertText("let x = 1;")
                    c.formatLineForTest("A table:", "", "")
                    c.tableForTest(2, 2)
                    c.tableFillForTest(["A1", "B1", "A2", "B2"])
                } else if (step === 3) {
                    typed = same(c.exportForTest())
                    log("typed", typed); cap("typed")
                } else if (step === 4) {
                    const other = chatList.chats.find(x => x.id !== chat.id)
                    backend.selectChat(other.id, other.name)
                } else if (step === 5) {
                    const d = (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).find(x => x.id === chat.id)
                    log("listed", d ? d.text : null)
                    log("other chat's box empty", conversation.composeText() === "")
                    cap("other")
                } else if (step === 6) backend.selectChat(chat.id, chat.name)
                else if (step === 7) {
                    const back = same(c.exportForTest())
                    log("same after switching", back === typed)
                    if (back !== typed) log("came back", back)
                    log("regions", c.richRegions)
                    cap("back")
                } else if (step === 8) { conversation.saveDraft(chat.id); Qt.quit() }
            } else {
                if (step === 3) {
                    const kept = JSON.parse(backend.draftJson(chat.id) || "{}")
                    const back = same(c.exportForTest())
                    log("kept", kept.html ? same(kept.html) : null)
                    log("same after restart", !!kept.html && back === same(kept.html))
                    if (back !== same(kept.html)) log("came back", back)
                    log("media", kept.media)
                    log("regions", c.richRegions)
                    cap("restart")
                } else if (step === 4) {
                    c.clear(); backend.setDraft(chat.id, "")
                    log("cleared", !(backend.draftsJson ? JSON.parse(backend.draftsJson) : []).some(x => x.id === chat.id))
                    Qt.quit()
                }
            }
            step++
        }
    }
    KeyTyper { id: draftTyper }
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
    // --search-communities-test[=<words>]: the results page's Communities
    // tab (Viva Engage's CommunitySearchTeams); logs SEARCH-COMMUNITIES.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--search-communities-test")) && chatList.chats.length > 1
        interval: 3500; repeat: true
        property int step: 0
        onTriggered: {
            const arg = (Qt.application.arguments.find(a => a.startsWith("--search-communities-test=")) || "").slice(26) || "OST"
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            if (step === 0) window.openSearch(arg)
            else if (step === 2) searchView.setTab("communities")
            else if (step === 4) { const p = searchView.page; console.warn("SEARCH-COMMUNITIES", JSON.stringify({ rows: searchView.rowsForTest().map(r => r.t), error: searchView.result ? searchView.result.error : null, n: p ? (p.communities || []).length : null, tabs: searchView.shownTabs })); cap("sp-communities") }
            else if (step === 5) Qt.quit()
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
                                            JSON.stringify(searchView.page && searchView.page.files ? searchView.page.files.hits.slice(0, 8).map(h => [h.file_name, h.file_action, h.file_by, h.file_when, searchView.filePlace(h).join(" › ")]) : null))
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
        running: window.shotPath.length > 0 && Qt.application.arguments.indexOf("--draft-format-test") < 0 && !window.callTest && !window.typingTest && !window.reactTest && !window.editTest && !window.newChatTest && Qt.application.arguments.indexOf("--search-test") < 0 && Qt.application.arguments.indexOf("--channel-test") < 0 && Qt.application.arguments.indexOf("--emoji-test") < 0 && Qt.application.arguments.indexOf("--format-test") < 0 && Qt.application.arguments.indexOf("--table-test") < 0 && Qt.application.arguments.indexOf("--hovercard-test") < 0 && Qt.application.arguments.indexOf("--chat-shot") < 0 && Qt.application.arguments.indexOf("--header-test") < 0 && Qt.application.arguments.indexOf("--status-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--pause-test")) && Qt.application.arguments.indexOf("--settings-test") < 0 && Qt.application.arguments.indexOf("--settings-pages-test") < 0 && Qt.application.arguments.indexOf("--calendar-test") < 0 && Qt.application.arguments.indexOf("--group-test") < 0 && Qt.application.arguments.indexOf("--keys-test") < 0 && Qt.application.arguments.indexOf("--mentions-test") < 0 && Qt.application.arguments.indexOf("--join-test") < 0 && Qt.application.arguments.indexOf("--event-card-test") < 0 && Qt.application.arguments.indexOf("--group-call-test") < 0 && Qt.application.arguments.indexOf("--meet-now-test") < 0 && Qt.application.arguments.indexOf("--mute-test") < 0 && Qt.application.arguments.indexOf("--video-call-test") < 0 && Qt.application.arguments.indexOf("--meeting-chat-test") < 0 && Qt.application.arguments.indexOf("--breakpoints-test") < 0 && Qt.application.arguments.indexOf("--fun-picker-test") < 0 && Qt.application.arguments.indexOf("--attach-test") < 0 && Qt.application.arguments.indexOf("--copilot-test") < 0 && Qt.application.arguments.indexOf("--attach-link-test") < 0 && Qt.application.arguments.indexOf("--thread-attach-test") < 0 && Qt.application.arguments.indexOf("--picker-bar-test") < 0 && Qt.application.arguments.indexOf("--filecard-test") < 0 && Qt.application.arguments.indexOf("--videoclip-test") < 0 && Qt.application.arguments.indexOf("--recorder-test") < 0 && Qt.application.arguments.indexOf("--recorder-edit-test") < 0 && Qt.application.arguments.indexOf("--teleprompter-test") < 0 && Qt.application.arguments.indexOf("--video-effects-test") < 0 && Qt.application.arguments.indexOf("--video-filters-test") < 0 && Qt.application.arguments.indexOf("--green-screen-test") < 0 && Qt.application.arguments.indexOf("--leave-confirm-test") < 0 && Qt.application.arguments.indexOf("--shortcut-profile-test") < 0 && Qt.application.arguments.indexOf("--new-chat-window-test") < 0 && Qt.application.arguments.indexOf("--chatlist-keys-test") < 0 && Qt.application.arguments.indexOf("--translation-test") < 0 && Qt.application.arguments.indexOf("--regional-test") < 0 && Qt.application.arguments.indexOf("--editor-test") < 0 && Qt.application.arguments.indexOf("--appearance-test") < 0 && Qt.application.arguments.indexOf("--collab-test") < 0 && Qt.application.arguments.indexOf("--notif-test") < 0 && Qt.application.arguments.indexOf("--accounts-test") < 0 && Qt.application.arguments.indexOf("--privacy-test") < 0 && Qt.application.arguments.indexOf("--calls-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--cards-test")) && !Qt.application.arguments.some(a => a.startsWith("--recognition-test=")) && Qt.application.arguments.indexOf("--recognition-states") < 0 && Qt.application.arguments.indexOf("--about-test") < 0 && Qt.application.arguments.indexOf("--room-audio-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--link-preview-test")) && Qt.application.arguments.indexOf("--fileviewer-test") < 0 && Qt.application.arguments.indexOf("--poll-test") < 0 && Qt.application.arguments.indexOf("--media-order-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--custom-emoji")) && Qt.application.arguments.indexOf("--onedrive-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--onedrive-rows-test")) && !Qt.application.arguments.some(a => a.startsWith("--version-history-test")) && !Qt.application.arguments.some(a => a.startsWith("--details-test")) && Qt.application.arguments.indexOf("--preview-test") < 0 && Qt.application.arguments.indexOf("--sortview-test") < 0 && Qt.application.arguments.indexOf("--zip-test") < 0 && Qt.application.arguments.indexOf("--files-links-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--picker-test")) && Qt.application.arguments.indexOf("--folder-bar-test") < 0 && Qt.application.arguments.indexOf("--quick-access-test") < 0 && Qt.application.arguments.indexOf("--picker-views-test") < 0 && Qt.application.arguments.indexOf("--comments-test") < 0 && Qt.application.arguments.indexOf("--bell-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--folder-extras-test")) && Qt.application.arguments.indexOf("--planner-test") < 0 && Qt.application.arguments.indexOf("--apps-test") < 0 && Qt.application.arguments.indexOf("--channel-files-test") < 0 && Qt.application.arguments.indexOf("--store-test") < 0 && Qt.application.arguments.indexOf("--webapp-test") < 0 && Qt.application.arguments.indexOf("--loop-test") < 0 && Qt.application.arguments.indexOf("--tab-menu-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--tab-drag-test=")) && Qt.application.arguments.indexOf("--delete-undo-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--open-chat=")) && window.appDetailsTest.length === 0 && Qt.application.arguments.indexOf("--chatlist-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--share-test")) && !Qt.application.arguments.some(a => a.startsWith("--file-actions-test")) && Qt.application.arguments.indexOf("--open-file-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--sharefile-test")) && !Qt.application.arguments.some(a => a.startsWith("--search-grid-test")) && !Qt.application.arguments.some(a => a.startsWith("--search-communities-test")) && Qt.application.arguments.indexOf("--meeting-details-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--attendance-test=")) && !Qt.application.arguments.some(a => a.startsWith("--remove-history-")) && !Qt.application.arguments.some(a => a.startsWith("--embedded-apps-test")) && Qt.application.arguments.indexOf("--test-call-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--events-test")) && Qt.application.arguments.indexOf("--call-notes-test") < 0 && Qt.application.arguments.indexOf("--phone-audio-test") < 0 && Qt.application.arguments.indexOf("--preheat-test") < 0 && !Qt.application.arguments.some(a => a.startsWith("--e2ee-setting-test"))
        onTriggered: {
            if (!backend.hasCredentials) {
                if (!backend.signInPage) {
                    if (!backend.busy) backend.beginSignIn()
                } else if (!window.signInShot) {
                    window.signInShot = true
                    console.warn("SIGNIN-PAGE", backend.signInPage.length > 0)
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

    // OST's update check (About OST's line), as Teams checks: soon after
    // start, then daily.
    Timer {
        interval: 20000; running: true; repeat: true
        onTriggered: { backend.checkForUpdates(); interval = 24 * 3600 * 1000 }
    }
    // Teams' notification banners: messages, meetings that started, the
    // test banner, and the incoming call, in the corner Settings picks.
    NotificationBanners {
        id: banners
        onOpenChat: (chatId, chatName) => backend.openFromNotification(chatId, chatName)
        onJoinMeeting: (chatId, chatName) => backend.joinFromNotification(chatId, chatName)
        onOpenSettings: {
            rail.current = "settings"; settingsView.page = "notifications"
            window.show(); window.raise(); window.requestActivate()
        }
        onAcceptCall: video => backend.acceptCall(video)
        onDeclineCall: backend.declineCall()
        // Ignore: stop ringing here; the call isn't declined.
        onIgnoreCall: backend.setRinger(false)
    }
    Connections { target: backend; function onBannerRequested(json) { banners.add(json) } }
    // Teams' ringtone while a call rings (Settings ▸ Calls ▸ Choose a
    // ringtone for you; Ring by default), on the speaker and on the
    // secondary ringer when one is chosen, again and again.
    readonly property string ringtoneName: {
        let s = {}
        try { s = JSON.parse(backend.settingsJson || "{}") } catch (e) {}
        const list = (((s.mt || {}).voice || {}).ringtoneSettings || {}).assignments
        const own = list && list.ringToneAssignments ? list.ringToneAssignments.find(a => a.type === "Regular") : null
        return own && own.value ? own.value : "Ring"
    }
    MediaDevices { id: ringDevices }
    function outputNamed(name) {
        return ringDevices.audioOutputs.find(d => d.description === name || d.id == name) || null
    }
    MediaPlayer {
        id: ringer
        source: "../assets/sounds/" + window.ringtoneName.toLowerCase() + ".mp3"
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput { device: window.outputNamed(backend.setting("speakerDevice")) || ringDevices.defaultAudioOutput }
        onErrorOccurred: (e, msg) => console.warn("RINGER error", source, msg)
        onPlayingChanged: console.info("RINGER", playing ? "playing" : "stopped", source)
    }
    MediaPlayer {
        id: secondRinger
        source: ringer.source
        loops: MediaPlayer.Infinite
        readonly property var device: window.outputNamed(backend.setting("secondaryRinger"))
        audioOutput: AudioOutput { device: secondRinger.device || ringDevices.defaultAudioOutput }
    }
    Connections {
        target: backend
        function onRingerOnChanged() {
            if (backend.ringerOn) {
                ringer.play()
                if (secondRinger.device) secondRinger.play()
            } else { ringer.stop(); secondRinger.stop() }
        }
    }
    // The incoming call is a banner while it rings.
    readonly property bool ringing: backend.callState === "ringing"
    onRingingChanged: {
        if (ringing) banners.add({ id: "call", kind: "call", title: backend.callPeer, senderMri: backend.callPeerId, video: backend.callVideoOffered, silent: true })
        else banners.dismiss("call")
    }
    // A video call is often known only after it starts ringing.
    Connections {
        target: backend
        function onCallVideoOfferedChanged() {
            if (window.ringing) banners.add({ id: "call", kind: "call", title: backend.callPeer, senderMri: backend.callPeerId, video: backend.callVideoOffered, silent: true })
        }
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
        onGreenScreenSettings: window.showGreenScreenSettings()
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
            window.roomOnJoin = audio === "room" && !!room
            window.phoneOnJoin = audio === "phone"
            if (meetNow) backend.channelMeetNow(meetChannel, subject.trim() || "Meeting")
            // Teams' Join now on the call its pre-join preheated.
            else backend.joinMeetingFromPrejoin(joinUrl, subject, micOn, withAudio)
        }
        // Cancel, Escape or closing the window without joining: Teams
        // leaves the call its pre-join preheated.
        onCancelled: backend.cancelPrejoin()
        onVisibleChanged: if (!visible) Qt.callLater(() => { if (!preJoin.visible && backend.callState === "") backend.cancelPrejoin() })
        // The switches still count in the lobby: they apply once admitted.
        onMicOnChanged: if (lobby) window.muteOnJoin = !micOn
        onCameraOnChanged: if (lobby) window.cameraOnJoin = cameraOn
        onLeaveLobby: backend.hangUp()
    }
    // Joining with a connected room device (Teams' BYOD Room audio):
    // once connected, Teams opens the shared display on the room's screen
    // (a second display; with one display it opens nothing) and says
    // "Connected to a room device".
    property bool roomOnJoin: false
    // Joining with the mic off (pre-join switch): mute once connected.
    property bool muteOnJoin: false
    // "Don't use audio": no sound either way once connected.
    property bool noAudioOnJoin: false
    // "Phone audio": once connected Teams offers Call me or the dial-in
    // numbers (its useTriggerCallMeDialogOnMount).
    property bool phoneOnJoin: false
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
            if (backend.callState === "connected" && window.roomOnJoin) {
                window.roomOnJoin = false
                callWindow.roomDeviceJoined = true
                callWindow.showRoomNotice()
                if (Qt.application.screens.length > 1) callWindow.roomMode = true
            }
            if (backend.callState === "ended" || backend.callState === "") {
                callWindow.roomDeviceJoined = false
                callWindow.roomNoticeCounted = false
            }
            if (backend.callState === "connected" && window.noAudioOnJoin) {
                window.noAudioOnJoin = false
                backend.useNoAudio()
            }
            if (backend.callState === "connected" && window.phoneOnJoin) {
                window.phoneOnJoin = false
                callWindow.openPhoneAudio()
            }
            if (backend.callState === "ended" || backend.callState === "") window.phoneOnJoin = false
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
        onGreenScreenSettings: window.showGreenScreenSettings()
        visible: ["calling", "connecting", "connected", "ended"].indexOf(backend.callState) >= 0 || retryReason !== ""
        onRejoin: window.rejoinMeeting()
        controlsOptions: { const o = {}; (backend.callControlsJson ? JSON.parse(backend.callControlsJson).options : []).forEach(x => o[x.name] = x); return o }
        controlsPeople: backend.callControlsJson ? JSON.parse(backend.callControlsJson) : ({})
        onLoadControls: backend.loadMeetingControls()
        onSetMeetingOption: (name, value) => backend.setMeetingOption(name, JSON.stringify(value))
        onApplyMeetingOptions: changes => backend.setMeetingOptions(JSON.stringify(changes))
        peer: backend.callPeer
        testCall: backend.callTest
        copilotAllowed: { const c = backend.composeCopilotJson ? JSON.parse(backend.composeCopilotJson) : {}; return !!c.meeting }
        testReport: backend.callTestReport ? JSON.parse(backend.callTestReport) : []
        onTestCallClosed: { backend.callTest = false; backend.callState = "" }
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
        onStartShare: kind => backend.startShare(kind)
        presentingState: backend.callPresentingJson ? JSON.parse(backend.callPresentingJson) : ({ mode: "ContentOnly", control: {} })
        onSetPresenterMode: mode => backend.setPresenterMode(mode)
        onSetPresenterBackground: json => backend.setPresenterBackground(json)
        onSetShareOptimize: on => backend.setShareOptimize(on)
        onScreenControl: (action, arg) => backend.screenControl(action, arg)
        onShareIncludeSoundChanged: if (backend.callSharing) backend.setShareSound(shareIncludeSound)
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
        adhocMeeting: backend.callAdhocMeeting
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
        // The test call's results stay until Close (Teams' Post EchoBot
        // Calling Screen).
        running: backend.callState === "ended" && !backend.callTest
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
                (banners.callCardItem() || banners.contentItem).grabToImage(r => {
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
    // --call-encryption: with --call-test (or --call-out) in a 1:1 call,
    // 4 s after it connects open the encryption card under the bar's shield
    // (Teams' Encryption status) and capture it (`-encryption.png`); logs
    // ENCRYPTION lines (end-to-end encrypted or not, the numbers).
    Timer {
        id: encryptionTest
        running: Qt.application.arguments.indexOf("--call-encryption") >= 0 && backend.callState === "connected"
        interval: 4000
        onTriggered: {
            callWindow.encryptionCardForTest()
            console.warn("ENCRYPTION e2ee", callWindow.e2ee, "numbers", JSON.stringify(callWindow.e2eeNumbers))
            encryptionShot.start()
        }
    }
    Timer {
        id: encryptionShot
        interval: 800
        onTriggered: {
            const card = callWindow.encryptionCardItemForTest()
            console.warn("ENCRYPTION card", card.x, card.y, card.width, card.height)
            callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-encryption.png")))
        }
    }
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
    // What breakoutMain was before the move under way, for a move that
    // fails (we stay where we were).
    property var breakoutUndo: null
    // The room last moved to (the harness joins it again once closed).
    property var lastBreakoutRoom: null
    function goToBreakoutRoom(room) {
        breakoutMove.stop()
        if (!room || window.breakoutMain) return
        window.lastBreakoutRoom = room
        window.breakoutUndo = { main: null }
        window.breakoutMain = JSON.parse(backend.currentMeeting())
        console.warn("BREAKOUT moving to", room.name)
        // Teams carries your mic state into the room (and back).
        window.muteOnJoin = backend.callMuted
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
        window.breakoutUndo = { main: main }
        window.breakoutMain = null
        const url = window.breakoutRoomState && window.breakoutRoomState.main_join_url || main.url
        console.warn("BREAKOUT back to", main.title)
        window.muteOnJoin = backend.callMuted
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
            window.muteOnJoin = backend.callMuted
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
        // A room (or the main meeting) couldn't be joined: we're still in
        // the meeting we came from (an organizer's held main meeting comes
        // back), and the window says why.
        function onMeetingMoveFailed(title, text) {
            console.warn("BREAKOUT move failed:", title, text)
            callWindow.showBreakoutAlert(text || title)
            if (callWindow.heldMeeting) { window.resumeHeldMeeting(); return }
            window.breakoutMain = window.breakoutUndo ? window.breakoutUndo.main : null
            window.breakoutUndo = null
        }
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
    // --breakout-watch-rejoin: back in the main meeting after a room,
    // join that (closed) room again 15 s later: the move fails and the
    // main meeting goes on.
    Timer {
        running: Qt.application.arguments.indexOf("--breakout-watch") >= 0 && backend.callState !== ""
        interval: 1500; repeat: true
        property string last: ""
        property int n: 0
        property int backFor: 0
        property bool rejoined: false
        onTriggered: {
            if (Qt.application.arguments.indexOf("--breakout-watch-rejoin") >= 0 && !rejoined && window.lastBreakoutRoom
                    && !window.breakoutMain && backend.callState === "connected" && ++backFor === 10) {
                rejoined = true
                console.warn("BREAKOUTWATCH rejoining the closed room", window.lastBreakoutRoom.name, "from", backend.callPeer)
                window.goToBreakoutRoom(window.lastBreakoutRoom)
            }
            const phase = JSON.stringify([callWindow.breakoutAlert ? callWindow.breakoutAlert.text : "", callWindow.roomToJoin,
                                          !!window.breakoutMain, callWindow.canReturnToMain, backend.callState,
                                          window.breakoutRoomState ? window.breakoutRoomState.closed : null, backend.callPeer])
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
        // --breakout-wait=<s>: stay that long with the rooms open (after
        // "opened") before going on, for the other side to act.
        property real holdUntil: 0
        onTriggered: {
            if (Date.now() < holdUntil) return
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
                // --breakout-manual: nobody is moved automatically (people
                // get "Join room") and they may return to the main meeting.
                5: () => { if (Qt.application.arguments.indexOf("--breakout-manual") >= 0) callWindow.breakoutRun("settings", { auto_move: false, allow_return: true }) },
                6: () => { log("created"); shot("manage") },
                7: () => t("assign"),
                8: () => shot("assign"),
                9: () => { t("close"); t("settings") },
                10: () => shot("settings"),
                11: () => t("back"),
                12: () => callWindow.breakoutRun("open", { threads: callWindow.breakoutRooms.map(r => r.thread) }),
                20: () => {
                    log("opened"); shot("open")
                    const wait = parseInt((Qt.application.arguments.find(a => a.startsWith("--breakout-wait=")) || "").slice(16)) || 0
                    if (wait > 0) { console.warn("BREAKOUTTEST waiting", wait); holdUntil = Date.now() + wait * 1000 }
                },
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
                // --breakout-join-unopened: add "Room 2" (never opened) and
                // Join it from its menu: the join fails and the main meeting
                // is back, its window saying why.
                50: () => { if (Qt.application.arguments.indexOf("--breakout-join-unopened") >= 0) callWindow.breakoutRun("add", { name: "Room 2" }) },
                53: () => {
                    const room = callWindow.breakoutRooms.find(r => r.name === "Room 2")
                    if (Qt.application.arguments.indexOf("--breakout-join-unopened") >= 0 && room) { console.warn("BREAKOUTTEST joining the unopened room", room.open); callWindow.joinRoomAsOrganizer(room) }
                },
                55: () => { if (Qt.application.arguments.indexOf("--breakout-join-unopened") >= 0) { console.warn("BREAKOUTTEST soon after the unopened room", backend.callHeldMeetingJson || "none", backend.callState, backend.callPeer, "alert", callWindow.breakoutAlert ? callWindow.breakoutAlert.text : ""); shot("unopened-join-alert") } },
                58: () => { if (Qt.application.arguments.indexOf("--breakout-join-unopened") >= 0) { console.warn("BREAKOUTTEST after the unopened room", backend.callHeldMeetingJson || "none", backend.callState, backend.callPeer, "role", callWindow.myRole, "people", JSON.stringify(callWindow.people.map(p => p.name)), "alert", callWindow.breakoutAlert ? callWindow.breakoutAlert.text : "", "status", backend.statusText); shot("unopened-join") } },
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
                newChat.setMessage("OST test 27: group chat started from OST")
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
    property string nmcWas: ""
    readonly property bool joinRaise: Qt.application.arguments.indexOf("--join-raise") >= 0
    property bool speechShot: false
    property bool deniedOne: false
    property var admitted: null
    property int retryShotAt: 0
    property bool rejoined: false
    property int admittedAt: 0
    property int shareTrayShared: 0
    // --join-present / --join-take-control (TASK-0210).
    property int presentStarted: 0
    property int presentAccepted: 0
    property int presentGiven: 0
    property int controlAsked: 0
    property int controlGot: 0
    property var controlKeys: []
    Timer {
        id: controlKeyTimer
        interval: 100; repeat: true
        onTriggered: {
            if (window.controlKeys.length === 0) { stop(); return }
            const k = window.controlKeys[0]
            window.controlKeys = window.controlKeys.slice(1)
            backend.controlKey(k[0], k[1], k[2], false)
        }
    }
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
                // --join-lobby-data (TASK-0213): once admitted, use the
                // meeting's data channel as it came back after the media
                // moved: live captions on (someone speaks), then take
                // control of whoever presents (as --join-take-control),
                // then captions off. JOIN lobby-data lines; -lobby-*.png.
                if (admittedAt && st === "connected" && Qt.application.arguments.indexOf("--join-lobby-data") >= 0) {
                    const a = step - admittedAt
                    const grab = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-lobby-" + n + ".png")))
                    const caps = () => JSON.parse(backend.callCaptionsJson || "[]")
                    const cst = callWindow.controlState
                    const log = t => console.warn("JOIN lobby-data", t, "a", a, "captionsOn", backend.callCaptionsOn, "captions", caps().length,
                                                  "last", JSON.stringify(caps().slice(-1)).slice(0, 160),
                                                  "presenter", callWindow.shareId, "control", JSON.stringify(cst))
                    if (a === 2) { callWindow.side = ""; callWindow.recordControl("ClosedCaptionsButton"); log("captions asked") }
                    else if (a === 14) { log("captions"); grab("captions") }
                    else if (a > 14 && !window.controlAsked && cst.capable && callWindow.presenting) {
                        window.controlAsked = step; log("capable"); grab("control-capable")
                        callWindow.runControl("ScreensharingControlButton")
                    }
                    else if (window.controlAsked && step === window.controlAsked + 1) { callWindow.requestControlDialogForTest().confirmed(); callWindow.requestControlDialogForTest().close() }
                    else if (window.controlAsked && step === window.controlAsked + 2) log("control asked")
                    else if (cst.state === "controlling" && !window.controlGot) { window.controlGot = step; log("controlling"); grab("controlling") }
                    else if (window.controlGot && step === window.controlGot + 1) {
                        backend.controlMouse(0, 0, false, 0.5, 0.5, 0)
                        backend.controlMouse(2, 0, true, 0.5, 0.5, 0)
                        backend.controlMouse(2, 0, false, 0.5, 0.5, 0)
                    }
                    else if (window.controlGot && step === window.controlGot + 2) {
                        // "OST TEST", as --join-take-control types it.
                        window.controlKeys = [[0x01000020, 50, false], [0x4f, 32, false], [0x4f, 32, true], [0x53, 39, false], [0x53, 39, true], [0x54, 28, false], [0x54, 28, true], [0x01000020, 50, true],
                                              [0x20, 65, false], [0x20, 65, true],
                                              [0x01000020, 50, false], [0x54, 28, false], [0x54, 28, true], [0x45, 26, false], [0x45, 26, true], [0x53, 39, false], [0x53, 39, true], [0x54, 28, false], [0x54, 28, true], [0x01000020, 50, true]]
                        controlKeyTimer.start()
                        log("typing")
                    }
                    else if (window.controlGot && step === window.controlGot + 5) { grab("control-typed"); callWindow.runControl("ScreensharingControlButton"); log("released") }
                    else if (window.controlGot && step === window.controlGot + 7) { log("after release"); callWindow.recordControl("ClosedCaptionsButton") }
                    else if (step % 5 === 0) log("wait")
                }
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
            } else if (step >= 8 && step <= Math.min(100, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-share-tray") >= 0) {
                // --join-share-tray: Teams' share tray (TASK-0185): Share
                // opens it, Include sound on, Window (the desktop's picker
                // for windows: pick one within a minute), sharing with the
                // computer's sound mixed in, then Stop sharing. Logs JOIN
                // share lines; pictures -tray, -tray-sound, -sharing.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png")))
                const log = t => console.warn("JOIN share", t, "sharing", backend.callSharing, "sound", backend.callShareSound, "include", callWindow.shareIncludeSound, "tray", callWindow.shareTrayForTest().visible)
                if (step === 8) { callWindow.side = ""; callWindow.runControl("ShareButton") }
                else if (step === 9) { log("tray"); shot("tray") }
                else if (step === 10) callWindow.shareTrayForTest().includeSound = true
                else if (step === 11) { log("include"); shot("tray-sound") }
                // --join-share-sound: no picker (a desktop without one to
                // drive): the computer's sound alone, as Include sound
                // sends it, for 40 s.
                else if (step === 12 && Qt.application.arguments.indexOf("--join-share-sound") >= 0) { callWindow.shareTrayForTest().close(); backend.setShareSound(true); log("sound only") }
                else if (step === 32 && Qt.application.arguments.indexOf("--join-share-sound") >= 0) { backend.setShareSound(false); log("sound off") }
                else if (step === 12) callWindow.shareTrayForTest().share("window")
                else if (step > 12 && !window.shareTrayShared && backend.callSharing) { window.shareTrayShared = step; log("started") }
                else if (window.shareTrayShared && step === window.shareTrayShared + 3) { log("sharing"); shot("sharing") }
                else if (window.shareTrayShared && step === window.shareTrayShared + 20) { log("stopping"); callWindow.runControl("ShareButton") }
                else if (window.shareTrayShared && step === window.shareTrayShared + 22) log("stopped")
                else if (step % 5 === 0) log("wait")
            } else if (step >= 8 && step <= Math.min(400, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-present") >= 0) {
                // --join-present (TASK-0210): present as Teams. With
                // --join-present-mode=<Weatherperson|SideBySide|NewsAnchor>
                // the camera goes on and the tray's presenter mode is
                // picked (--join-present-bg=<aplBackground_0nn> adds a
                // background); Window opens the desktop's picker (pick a
                // harmless window within a minute). While sharing: the
                // Sharing control bar (expanded, then minimized), control
                // requests accepted (--join-present-accept) or Give control
                // to the first viewer who can take it (--join-present-give),
                // the Layout switched at the end (--join-present-switch=
                // <mode>), then Stop sharing. Logs JOIN present lines;
                // pictures -present-*.png.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-present-" + n + ".png")))
                const barShot = n => { const b = callWindow.sharingBarForTest(); if (b) b.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-present-" + n + ".png"))) }
                const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
                const mode = arg("--join-present-mode")
                const log = t => console.warn("JOIN present", t, "sharing", backend.callSharing, "camera", backend.callCameraOn, "state", backend.callPresentingJson,
                                              "bar", !!callWindow.sharingBarForTest(), "expanded", callWindow.sharingBarForTest() ? callWindow.sharingBarForTest().expanded : false,
                                              "minimized", callWindow.visibility === Window.Minimized)
                const st = callWindow.controlState
                if (step === 8) { callWindow.side = ""; if (mode && !backend.callCameraOn) backend.toggleCamera() }
                // Content from camera's drill-down, captured on the way.
                else if (step === 9) { callWindow.runControl("ShareButton"); callWindow.shareTrayForTest().drill = "camera" }
                else if (step === 10) shot("tray-camera")
                else if (step === 11) callWindow.shareTrayForTest().drill = ""
                else if (step === 12) { if (mode) callWindow.shareTrayForTest().pickMode(mode); if (arg("--join-present-bg")) callWindow.shareTrayForTest().drill = "backgrounds" }
                else if (step === 13) { log("tray"); shot(arg("--join-present-bg") ? "tray-backgrounds" : "tray") }
                else if (step === 14 && arg("--join-present-bg")) { const b = arg("--join-present-bg"); callWindow.shareTrayForTest().pickBackground({ id: b, url: callWindow.shareTrayForTest().backgroundUrl(b, false), name: "" }) }
                else if (step === 15 && arg("--join-present-bg")) { shot("tray-background-picked"); callWindow.shareTrayForTest().drill = "" }
                else if (step === 16) callWindow.shareTrayForTest().share(Qt.application.arguments.indexOf("--join-present-screen") >= 0 ? "screen" : "window")
                else if (step > 16 && !window.presentStarted && backend.callSharing) { window.presentStarted = step; log("started") }
                else if (window.presentStarted && step === window.presentStarted + 1) { log("bar"); barShot("bar") }
                else if (window.presentStarted && step === window.presentStarted + 8) { log("bar minimized"); barShot("bar-min") }
                // The bar's Layout menu, open (pinned, expanded).
                else if (window.presentStarted && mode && step === window.presentStarted + 10) { const b = callWindow.sharingBarForTest(); if (b) { b.pinned = true; b.expanded = true; b.openLayoutMenuForTest() } }
                else if (window.presentStarted && mode && step === window.presentStarted + 11) barShot("bar-layout")
                else if (window.presentStarted && mode && step === window.presentStarted + 12) { const b = callWindow.sharingBarForTest(); if (b) b.closeMenusForTest() }
                else if (window.presentStarted && step > window.presentStarted + 8 && step < 9 + window.joinStay) {
                    // A request comes in: accept it.
                    if (Qt.application.arguments.indexOf("--join-present-accept") >= 0 && st.request && !window.presentAccepted) {
                        window.presentAccepted = step; log("request from " + st.request); shot("request")
                        callWindow.screenControl("accept", "")
                    }
                    // Give control to the first viewer who can take it.
                    if (Qt.application.arguments.indexOf("--join-present-give") >= 0 && !window.presentGiven && (st.controllable || []).length > 0) {
                        window.presentGiven = step; log("give to " + st.controllable[0])
                        const b = callWindow.sharingBarForTest(); if (b) { b.expanded = true; b.pinned = true }
                        callWindow.screenControl("give", st.controllable[0])
                    }
                    if (window.presentGiven && step === window.presentGiven + 2) barShot("bar-given")
                    if (arg("--join-present-switch") && step === 1 + window.joinStay) { callWindow.setPresenterMode(arg("--join-present-switch")); log("switched") }
                    if (step % 5 === 0) log("wait")
                }
                else if (window.presentStarted && step === 9 + window.joinStay) { log("stopping"); callWindow.runControl("ShareButton") }
                else if (window.presentStarted && step === 11 + window.joinStay) log("stopped")
                else if (step % 5 === 0) log("wait")
            } else if (step >= 8 && step <= Math.min(400, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-take-control") >= 0) {
                // --join-take-control (TASK-0210): someone else presents;
                // once their screen can be controlled the bar shows Take
                // control: ask (Teams' "Request control?"), and once given
                // control click the middle of their picture and type
                // "OST TEST" there, then Stop control. Captures the stage
                // whenever their presenter mode is on (-control-stage.png).
                // Logs JOIN control lines; pictures -control-*.png.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-control-" + n + ".png")))
                const st = callWindow.controlState
                const log = t => console.warn("JOIN control", t, "presenter", callWindow.shareId, "state", backend.callPresentingJson, "bar", callWindow.ubar.bar.indexOf("ScreensharingControlButton") >= 0)
                if (step === 8) callWindow.side = ""
                else if (!window.controlAsked && st.capable && callWindow.presenting) {
                    window.controlAsked = step; log("capable"); shot("capable")
                    callWindow.runControl("ScreensharingControlButton")
                }
                else if (window.controlAsked && step === window.controlAsked + 1) { shot("request-dialog"); callWindow.requestControlDialogForTest().confirmed(); callWindow.requestControlDialogForTest().close() }
                else if (window.controlAsked && step === window.controlAsked + 2) { log("asked"); shot("waiting") }
                else if (st.state === "controlling" && !window.controlGot) { window.controlGot = step; log("controlling"); shot("controlling") }
                else if (window.controlGot && step === window.controlGot + 1) {
                    backend.controlMouse(0, 0, false, 0.5, 0.5, 0)
                    backend.controlMouse(2, 0, true, 0.5, 0.5, 0)
                    backend.controlMouse(2, 0, false, 0.5, 0.5, 0)
                }
                else if (window.controlGot && step === window.controlGot + 2) {
                    // "OST TEST": Shift for the capitals, then each key.
                    const keys = [[0x01000020, 50, false], [0x4f, 32, false], [0x4f, 32, true], [0x53, 39, false], [0x53, 39, true], [0x54, 28, false], [0x54, 28, true], [0x01000020, 50, true],
                                  [0x20, 65, false], [0x20, 65, true],
                                  [0x01000020, 50, false], [0x54, 28, false], [0x54, 28, true], [0x45, 26, false], [0x45, 26, true], [0x53, 39, false], [0x53, 39, true], [0x54, 28, false], [0x54, 28, true], [0x01000020, 50, true]]
                    // As typed: one key event every 100 ms.
                    window.controlKeys = keys
                    controlKeyTimer.start()
                    log("typing")
                }
                else if (window.controlGot && step === window.controlGot + 5) { shot("typed"); callWindow.runControl("ScreensharingControlButton"); log("released") }
                else if (window.controlGot && step === window.controlGot + 7) { log("after release"); shot("released") }
                if (callWindow.presenting && step % 10 === 0) {
                    log("wait")
                    console.warn("JOIN control composite", JSON.stringify(callWindow.presenterCompositeForTest()))
                    shot("stage-" + step)
                }
            } else if (step >= 8 && step <= Math.min(400, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-event") >= 0) {
                // --join-event: a town hall or webinar (TASK-0184): the bar and
                // green room as joined, Q&A (--join-event-qna), Start meeting
                // with its confirmation (--join-event-start), the live bar,
                // then End event with its confirmation (--join-event-end) near
                // the end. Needs --join-stay=90 or more. Logs JOIN event lines;
                // pictures -event-*.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-event-" + n + ".png")))
                const has = f => Qt.application.arguments.indexOf(f) >= 0
                const log = t => console.warn("JOIN event", t, backend.callEventJson, "role", callWindow.myRole, "bar", JSON.stringify(callWindow.ubar.bar),
                                              "end", JSON.stringify(callWindow.ubar.end), "attendees", callWindow.attendeeCount, "side", callWindow.side)
                const endAt = 11 + window.joinStay - 14
                if (step === 8) { callWindow.side = ""; log("joined"); shot("green") }
                else if (step === 9 && has("--join-event-qna")) callWindow.runControl("YammerQnaButton")
                else if (step === 18 && has("--join-event-qna")) { log("qna"); shot("qna") }
                else if (step === 19) { callWindow.side = "people" }
                else if (step === 20) { log("people"); shot("people"); callWindow.side = "" }
                else if (step === 21 && has("--join-event-start")) { callWindow.runControl("StagingRoomStartMeetingButton"); log("start asked") }
                else if (step === 22 && has("--join-event-start")) { shot("start-dialog"); callWindow.startEventForTest() }
                else if (step === 23 && has("--join-event-start")) { log("starting"); shot("starting") }
                else if (step === 32) { log("after start"); shot("live") }
                else if (step === endAt && has("--join-event-end")) { callWindow.runControl("StagingRoomEndMeetingButton"); log("end asked") }
                else if (step === endAt + 1 && has("--join-event-end")) { shot("end-dialog"); callWindow.endEventForTest() }
                else if (step === endAt + 8 && has("--join-event-end")) { log("ended"); shot("ended") }
                else if (step === 11 + window.joinStay) log("end")
                else if (step > 23 && step % 5 === 0) log("wait")
            } else if (step >= 8 && step <= Math.min(100, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-copilot") >= 0) {
                // --join-copilot: Copilot in the meeting (TASK-0188, a
                // Copilot-licensed account): the bar's Copilot, Teams'
                // "Start transcription to use Copilot" alert, Start (the
                // spoken-language confirmation, then the transcript), the
                // Copilot pane with the Microsoft 365 Copilot app told the
                // meeting. With --join-copilot-stop the transcript is
                // stopped again at the end. Needs --join-stay=60 or more.
                // Logs JOIN copilot lines; pictures -copilot-*.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-copilot-" + n + ".png")))
                const log = t => console.warn("JOIN copilot", t, "bar", callWindow.ubar.bar.indexOf("MeetingCollabButton") >= 0, "more", callWindow.ubar.more.indexOf("MeetingCollabButton") >= 0,
                                              "allowed", callWindow.copilotAllowed, "ai", callWindow.aiAvailable, "side", callWindow.side, "ask", callWindow.copilotAskForTest().visible,
                                              "transcribing", callWindow.transcribing, "launch", !!callWindow.copilotLaunch, "events", JSON.stringify(callWindow.copilotEventsForTest()))
                if (step === 8) { callWindow.side = ""; log("start"); shot("bar") }
                else if (step === 9) callWindow.runControl("MeetingCollabButton")
                else if (step === 10) { log("asked"); shot("ask") }
                else if (step === 11 && callWindow.copilotAskForTest().visible) callWindow.copilotStartForTest()
                else if (step === 12) { shot("language"); console.warn("JOIN copilot language confirmed", callWindow.confirmRecordDialogForTest()) }
                else if (step === 20) { log("pane"); shot("pane") }
                else if (step === 30) { log("pane later"); shot("pane-later") }
                else if (step === 50) { log("pane answer"); shot("pane-answer") }
                else if (step === 9 + window.joinStay && Qt.application.arguments.indexOf("--join-copilot-stop") >= 0 && callWindow.transcribing) callWindow.recorderCommand("stopTranscription", "", false)
                else if (step === 11 + window.joinStay) log("end")
                else if (step > 12 && step % 5 === 0) log("wait")
            } else if (step >= 8 && step <= 44 && Qt.application.arguments.indexOf("--join-new-controls") >= 0) {
                // --join-new-controls: Teams' New meeting controls (turned on
                // for the test, put back after): the bar at 1280, More with
                // View ▸ / Join info ▸ / Settings ▸, React (raise and lower
                // your hand), a control's right-click menu, Unpin People
                // (bar and More), Reset, then 700 (overflow) and 460 (the
                // compact bar). Needs --join-stay=80 or more.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-nmc-" + n + ".png")))
                const log = t => console.warn("JOIN nmc", t, callWindow.width, "compact", callWindow.compactBar, JSON.stringify(callWindow.ubar))
                if (step === 8) {
                    window.nmcWas = backend.setting("newMeetingControls")
                    backend.setSetting("newMeetingControls", "true"); callWindow.newControls = true
                    callWindow.side = ""; callWindow.width = 1280
                }
                else if (step === 9) { log("wide"); shot("wide") }
                else if (step === 10) callWindow.newMoreForTest()
                else if (step === 11) { shot("more"); console.warn("JOIN nmc more grid", JSON.stringify(callWindow.newGridItems.map(e => e.label)), "list", JSON.stringify(callWindow.newListItems.map(e => e.label || "|"))) }
                else if (step === 12) callWindow.newMoreSubForTest(0)
                else if (step === 13) shot("more-view")
                else if (step === 14) callWindow.newMoreSubForTest(1)
                else if (step === 15) shot("more-joininfo")
                else if (step === 16) callWindow.newMoreSubForTest(2)
                else if (step === 17) { shot("more-settings"); console.warn("JOIN nmc settings", JSON.stringify(callWindow.newListItems[2].submenu.map(e => e.label || "|"))) }
                else if (step === 18) { callWindow.closeMenusForTest(); callWindow.runControl("ReactionButton") }
                else if (step === 19) shot("react")
                else if (step === 20) callWindow.toggleHand()
                else if (step === 22) { shot("react-raised"); console.warn("JOIN nmc hand", callWindow.handRaised, backend.callHandRaised) }
                else if (step === 23) callWindow.toggleHand()
                else if (step === 25) { console.warn("JOIN nmc hand lowered", !backend.callHandRaised); callWindow.closeMenusForTest(); callWindow.controlMenuForTest("ChatButton") }
                else if (step === 26) { shot("arrange-chat"); console.warn("JOIN nmc arrange", JSON.stringify(callWindow.arrangeMenuForTest().items.map(e => e.label || "|"))) }
                else if (step === 27) { callWindow.closeMenusForTest(); callWindow.arrangeForTest("unpin", "RosterButton") }
                else if (step === 28) { log("unpinned"); shot("unpinned"); callWindow.newMoreForTest() }
                else if (step === 29) shot("unpinned-more")
                else if (step === 30) { callWindow.closeMenusForTest(); callWindow.arrangeForTest("reset", "") }
                else if (step === 31) { log("reset"); callWindow.width = 700 }
                else if (step === 33) { log("700"); shot("700"); callWindow.newMoreForTest() }
                else if (step === 34) shot("700-more")
                else if (step === 35) { callWindow.closeMenusForTest(); callWindow.width = 460 }
                else if (step === 37) { log("460"); shot("460") }
                else if (step === 38) callWindow.width = 1280
                else if (step === 40) {
                    backend.setSetting("newMeetingControls", window.nmcWas); callWindow.newControls = window.nmcWas === "true"
                    log("restored")
                }
                else if (step === 41) shot("restored")
            } else if (step >= 8 && step <= Math.min(80, 11 + window.joinStay) && Qt.application.arguments.indexOf("--join-nmc-drag") >= 0) {
                // --join-nmc-drag (TASK-0208): the new controls (on for the
                // test, put back after) at 856 wide, as Teams on winpc:
                // drag Chat right past People (reorder), Chat onto More
                // (unpin), Chat from More's grid back onto the bar (pin),
                // People over Mic (not allowed), Copilot and Escape
                // (cancelled); each captured mid-drag and after the drop.
                // Then (steps 40–70) it waits for a real drag from outside:
                // the log gives Chat's and More's screen points. JOIN drag
                // lines; -drag-*.png. Needs --join-stay=150.
                const shot = n => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-drag-" + n + ".png")))
                const bar = () => callWindow.ubar.bar.filter(n => n !== "|").join(",")
                const at = n => callWindow.centerForTest(n)
                const log = t => console.warn("JOIN drag", t, "zone", callWindow.dragZone, "bar", bar(), "grid", JSON.stringify(callWindow.newGridItems.map(e => e.label)),
                                              "saved", backend.setting("meetingControlsLayouts"))
                const p = (q, dx, dy) => Qt.point(q.x + dx, q.y + dy)
                if (step === 8) {
                    window.nmcWas = backend.setting("newMeetingControls")
                    backend.setSetting("newMeetingControls", "true"); callWindow.newControls = true
                    callWindow.arrangeForTest("reset", ""); callWindow.side = ""; callWindow.width = 856
                }
                else if (step === 9) { log("start"); shot("start") }
                else if (step === 10) { const c = at("ChatButton"); callWindow.dragForTest("ChatButton", "bar", [c, p(c, 20, 0), p(c, 70, 0)], false) }
                else if (step === 11) { log("reorder over People"); shot("reorder") }
                else if (step === 12) callWindow.dragEndForTest(true)
                else if (step === 13) { log("reordered"); shot("reordered") }
                else if (step === 14) { const c = at("ChatButton"), m = at("MoreButton"); callWindow.dragForTest("ChatButton", "bar", [c, p(c, 10, 0), m], false) }
                else if (step === 15) { log("over More"); shot("unpin") }
                else if (step === 16) callWindow.dragEndForTest(true)
                else if (step === 17) { log("unpinned"); callWindow.newMoreForTest() }
                else if (step === 18) shot("unpinned-more")
                else if (step === 19) { const g = callWindow.gridCenterForTest("ChatButton"); const r = at("RosterButton"); callWindow.dragForTest("ChatButton", "grid", [g, p(g, -10, -10), p(r, -10, 0)], false) }
                else if (step === 20) { log("pin over People"); shot("pin") }
                else if (step === 21) { callWindow.dragEndForTest(true); callWindow.closeMenusForTest() }
                else if (step === 22) { log("pinned"); shot("pinned") }
                else if (step === 23) { const r = at("RosterButton"), m = at("MicrophoneButton"); callWindow.dragForTest("RosterButton", "bar", [r, p(r, -10, 0), m], false) }
                else if (step === 24) { log("over Mic"); shot("blocked") }
                else if (step === 25) callWindow.dragEndForTest(true)
                else if (step === 26) { log("after blocked drop"); const c = at("MeetingCollabButton").x ? at("MeetingCollabButton") : at("OrganizerControlButton"); callWindow.dragForTest(callWindow.ubar.bar.indexOf("MeetingCollabButton") >= 0 ? "MeetingCollabButton" : "OrganizerControlButton", "bar", [c, p(c, -60, 0)], false) }
                else if (step === 27) { log("before Escape"); callWindow.dragEndForTest("escape") }
                else if (step === 28) { log("escaped"); shot("escaped") }
                else if (step === 30) { callWindow.arrangeForTest("reset", ""); log("reset") }
                else if (step === 32) {
                    const g = n => { const c = at(n); const s = callWindow.contentItem.mapToGlobal(c.x, c.y); return Math.round(s.x) + "," + Math.round(s.y) }
                    console.warn("JOIN drag screen", "chat", g("ChatButton"), "people", g("RosterButton"), "more", g("MoreButton"), "copilot", g("MeetingCollabButton"))
                }
                else if (step >= 34 && step <= 70 && step % 4 === 0) log("real")
                else if (step === 71) { log("after real"); callWindow.arrangeForTest("reset", "") }
                else if (step === 72) { backend.setSetting("newMeetingControls", window.nmcWas); callWindow.newControls = window.nmcWas === "true"; log("restored") }
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

    // --cal-test (docs/desktop.md): the calendar as Teams lays it out, its
    // card, event page, form and dialogs, and the calendar's actions on
    // test events. Pictures cal-*.png in --shots=<dir>; CALTEST lines.
    Timer {
        id: calTest
        readonly property var args: Qt.application.arguments
        // "~" stands for a space (handy over ssh).
        function arg(k, d) { const a = args.find(x => x.startsWith("--" + k + "=")); return a ? a.slice(k.length + 3).replace(/~/g, " ") : (d === undefined ? "" : d) }
        readonly property string dir: arg("shots", "/tmp/act") + "/"
        running: args.indexOf("--cal-test") >= 0 && backend.signedIn && (step > 0 || backend.calendarJson.length > 2)
        interval: 3000; repeat: true
        property int step: 0
        onRunningChanged: console.warn("CALTEST running", running)
        Component.onCompleted: console.warn("CALTEST ready", args.indexOf("--cal-test"), backend.signedIn, backend.calendarJson.length)
        property string done: ""
        function cap(tag) { window.contentItem.grabToImage(r => r.saveToFile(dir + "cal-" + tag + ".png")); console.warn("CALTEST shot", tag) }
        function ev(subject) { return JSON.parse(backend.calendarJson).find(e => e.subject === subject) }
        property var conn: Connections {
            target: backend
            function onCalendarActionDone(op, result, error) { calTest.done = op + (error ? " ERROR " + error : " ok"); console.warn("CALTEST action", op, error ? "ERROR " + error : "ok", (result || "").slice(0, 400)) }
        }
        onTriggered: {
            const d = arg("cal-date")
            if (step === 0) {
                rail.current = "calendar"
                if (arg("cal-view")) calendarView.view = arg("cal-view")
                if (d) calendarView.start = calendarView.startFor(new Date(d + "T12:00:00"))
            } else if (arg("cal-respond") && step === 2) {
                // --cal-respond=<subject>|<Accept|Tentative|Decline|Follow>|<series 0/1>|<note>
                const p = arg("cal-respond").split("|"), e = ev(p[0])
                console.warn("CALTEST respond", p[0], !!e, e ? e.response : "")
                if (e) { calendarView.cardForTest(p[0]); calendarView.respondForTest(p[1], p[2] === "1", p[3] || "") }
            } else if (arg("cal-respond") && step === 8) {
                const p = arg("cal-respond").split("|"), e = ev(p[0])
                console.warn("CALTEST answered", p[0], e ? e.response : "gone"); calendarView.cardForTest(p[0])
            } else if (arg("cal-respond") && step === 9) cap("answered")
            else if (arg("cal-respond") && step === 10) Qt.quit()
            else if (arg("cal-schedule") && step === 2) {
                // --cal-schedule=<title> with --cal-attendee, --cal-channel=Team/Channel,
                // --cal-start=<ISO>, --cal-minutes, --cal-repeat=<index> --cal-until=<date>,
                // --cal-location, --cal-body; --cal-save-only captures without sending.
                const ch = arg("cal-channel").split("/")
                const s = new Date(arg("cal-start", new Date(Date.now() + 86400000).toISOString()))
                if (ch.length === 2) { const t = (JSON.parse(backend.teamsJson || "[]")).find(t => t.name === ch[0]); const c = t ? t.channels.find(c => c.name === ch[1]) : null; calendarView.newChannelMeeting(t ? t.id : "", ch[0], c ? c.id : "", ch[1]) }
                else calendarView.newMeeting()
                const f = calendarView.formForTest
                f.typeTitleForTest(arg("cal-schedule"))
                f.setTimesForTest(s, new Date(s.getTime() + parseInt(arg("cal-minutes", "30")) * 60000))
                if (arg("cal-attendee")) f.addAttendeeForTest(arg("cal-attendee"), arg("cal-attendee"))
                if (arg("cal-location")) f.setLocationForTest(arg("cal-location"))
                if (arg("cal-body")) f.typeBodyForTest(arg("cal-body"))
            } else if (arg("cal-schedule") && step === 3 && arg("cal-repeat")) {
                calendarView.formForTest.pickRepeatForTest(parseInt(arg("cal-repeat")))
            } else if (arg("cal-schedule") && step === 4 && arg("cal-repeat")) {
                cap("recurrence"); calendarView.formForTest.saveRecurrenceForTest(arg("cal-until") ? new Date(arg("cal-until") + "T00:00:00") : null)
            } else if (arg("cal-schedule") && step === 5) cap("form-filled")
            else if (arg("cal-schedule") && step === 6) { if (args.indexOf("--cal-save-only") < 0) calendarView.formForTest.submitForTest(); else Qt.quit() }
            else if (arg("cal-schedule") && step === 12) { const e = ev(arg("cal-schedule")); console.warn("CALTEST scheduled", arg("cal-schedule"), !!e, e ? JSON.stringify({ join: !!e.join_url, channel: e.channel_id, attendees: e.attendees.length, type: e.event_type }) : ""); if (e) calendarView.cardForTest(e.subject) }
            else if (arg("cal-schedule") && step === 13) cap("scheduled")
            else if (arg("cal-schedule") && step === 14) Qt.quit()
            else if (arg("cal-cancel") && step === 2) {
                // --cal-cancel=<subject> [--cal-cancel-note=<text>]: the event page's Cancel meeting.
                console.warn("CALTEST cancel page", calendarView.pageForTest(arg("cal-cancel")))
            } else if (arg("cal-cancel") && step === 3) { calendarView.formForTest.openCancelForTest(); }
            else if (arg("cal-cancel") && step === 4) { cap("cancel"); calendarView.formForTest.confirmCancelForTest(arg("cal-cancel-note")) }
            else if (arg("cal-cancel") && step === 9) { console.warn("CALTEST cancelled", !ev(arg("cal-cancel")) || ev(arg("cal-cancel")).is_cancelled); Qt.quit() }
            else if (!arg("cal-respond") && !arg("cal-schedule") && !arg("cal-cancel")) {
                // Pictures: the views, the card and page of --cal-peek, the form and dialogs.
                const peek = arg("cal-peek")
                const seq = [
                    () => cap((calendarView.view) + "-view"),
                    () => { calendarView.view = "week" }, () => cap("week-view"),
                    () => { calendarView.view = "day" }, () => cap("day-view"),
                    () => { calendarView.view = "month"; if (d) calendarView.start = calendarView.startFor(new Date(d + "T12:00:00")) }, () => cap("month-view"),
                    () => { calendarView.view = "workweek"; if (d) calendarView.start = calendarView.startFor(new Date(d + "T12:00:00")) },
                    () => console.warn("CALTEST peek", peek, calendarView.cardForTest(peek)), () => cap("peek"),
                    () => { calendarView.detailsForTest.close(); console.warn("CALTEST page", calendarView.pageForTest(peek)) }, () => cap("page"),
                    () => { calendarView.formForTest.openRsvpNoteForTest() }, () => cap("rsvp-note"),
                    () => { calendarView.formOpen = false; calendarView.newMeeting() }, () => cap("form"),
                    () => { calendarView.formOpen = false; calendarView.meetNowForTest.openFresh() }, () => cap("meetnow"),
                    () => { calendarView.meetNowForTest.close(); calendarView.joinIdForTest.openFresh() }, () => cap("joinid"),
                    () => { calendarView.joinIdForTest.close(); Qt.quit() }
                ]
                if (step >= 1 && step - 1 < seq.length) seq[step - 1]()
            }
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
            const want = (Qt.application.arguments.find(a => a.startsWith("--custom-emoji-name=")) || "--custom-emoji-name=ost-test").slice(20)
            const mine = () => org().find(e => e.shortcut === want)
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
            else if (step >= 5 && step <= 8 && !mine() && !add.busyForTest) { if (add.nameForTest !== want) add.setNameForTest(want); console.warn("CUSTOM add pressed", add.addForTest()) }
            else if (step === 9) { console.warn("CUSTOM result", backend.customEmojiResult, JSON.stringify(org())); cap("added") }
            else if (step === 10) { conversation.openEmojiForTest(); p.tab = "emoji" }
            else if (step === 11) p.tab = "emoji"
            else if (step === 12) { const e = mine(); if (e) backend.emoticonUrl(e.id, 20) }
            else if (step === 13) cap("picker")
            // --custom-emoji-nosend: stop at the picker (nothing posted).
            else if (step === 14 && Qt.application.arguments.indexOf("--custom-emoji-nosend") >= 0) { p.close(); Qt.quit() }
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

    // --copilot-test: Write with Copilot in OST group test (or, with
    // --copilot-channel, OST Test Team > OST test channel 2): the button,
    // the popover with an empty box, a harmless test draft, Rewrite (its
    // loading and answer), Proofread, Adjust ▸ Concise and the menu, Custom
    // ("add a cheerful good morning"), Previous, then Replace; the box is
    // cleared at the end and nothing is sent. Logs COPILOT lines; pictures
    // copilot-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--copilot-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 1500; repeat: true
        property int step: 0
        property int waited: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-copilot-" + tag + ".png")))
            const log = (...a) => console.warn("COPILOT", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const chan = Qt.application.arguments.indexOf("--copilot-channel") >= 0
            const box = conversation.composeForTest()
            const pop = box ? box.copilotForTest() : null
            const settle = () => { const st = pop.stateForTest(); if (st.busy && waited++ < 40) return false; waited = 0; return true }
            switch (step) {
            case 0:
                if (chan) {
                    const team = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => t.name === "OST Test Team")
                    const ch = team ? team.channels.find(c => c.name === "OST test channel 2") : null
                    if (!ch) return
                    backend.selectChat(ch.id, ch.name)
                } else { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name) }
                break
            case 2: log("state", backend.composeCopilotJson, "button", box.toolModel.map(t => t.id)); box.clearForTest(); box.openCopilot(null); break
            case 3: log("empty", pop.stateForTest()); cap("empty"); pop.close(); break
            case 4: conversation.setComposeText("hey team can we meet tmrw at 10 to go over the test plan thx"); break
            case 5: box.openCopilot(null); break
            case 6: log("ready", pop.stateForTest()); cap("ready"); pop.actForTest("rewrite"); break
            case 7: cap("loading"); log("loading", pop.stateForTest()); break
            case 8: if (!settle()) return; log("rewrite", pop.stateForTest().answers); cap("rewrite"); pop.actForTest("proofread"); break
            case 9: if (!settle()) return; log("proofread", pop.stateForTest().answers.slice(-1)); cap("proofread"); pop.actForTest("concise"); break
            case 10: if (!settle()) return; log("concise", pop.stateForTest().answers.slice(-1)); pop.actForTest("menu"); break
            case 11: cap("menu"); pop.actForTest("custom", "add a cheerful good morning"); break
            case 12: if (!settle()) return; log("custom", pop.stateForTest()); cap("custom"); pop.actForTest("prev"); break
            case 13: log("prev", pop.stateForTest().index); cap("prev"); pop.actForTest("replace"); break
            case 14: log("replaced", box.plainText(), "open", pop.opened); cap("replaced"); break
            case 15: box.clearForTest(); conversation.setComposeText(""); break
            case 16: Qt.quit(); return
            }
            step++
        }
    }

    // --attach-link-test: in OST group test, a suggested file (the Attach
    // popover's first) into the compose box, its card's Link settings
    // ("People currently in this chat", applied: the link is made), then,
    // with --attach-link-send, sent as "OST TEST 173 link settings from
    // OST". Logs ATTACHLINK lines; pictures attach-link-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--attach-link-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2000; repeat: true
        property int step: 0
        property int waited: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-attach-link-" + tag + ".png")))
            const log = (...a) => console.warn("ATTACHLINK", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const m = conversation.attachMenuForTest(), ca = conversation.cloudAttachForTest()
            switch (step) {
            case 0: { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name); break }
            case 2: conversation.attachFile(); break
            case 4: { const st = m.stateForTest(); if (st.loading && waited++ < 10) return; waited = 0; log("menu", st); cap("menu"); break }
            case 5: { const h = m.hits[0]; log("pick", h || null); if (!h) { Qt.quit(); return } m.close(); m.picked(h); break }
            case 6: { const st = ca.stateForTest(); if (st.some(c => c.loading) && waited++ < 20) return; waited = 0; log("card", st); cap("card"); break }
            case 7: ca.openLink(ca.pending[0].key); break
            case 9: { const d = ca.linkDialogForTest(); log("dialog", d.view, d.chatMode); cap("dialog"); d.pendScope = 4; d.pendEdit = true; break }
            case 10: { const d = ca.linkDialogForTest(); cap("dialog-chat"); d.linkChosen(4, true, "", ""); d.close(); break }
            case 11: { const st = ca.stateForTest(); if (st.some(c => c.linking) && waited++ < 20) return; waited = 0; log("linked", st); cap("linked"); break }
            case 12: if (Qt.application.arguments.indexOf("--attach-link-send") < 0) { ca.clear(); Qt.quit(); return } conversation.setComposeText("OST TEST 173 link settings from OST"); break
            case 13: conversation.sendForTest(); break
            case 17: log("sent; status", backend.statusText); cap("sent"); Qt.quit(); return
            }
            step++
        }
    }

    // --thread-attach-test: OST Test Team > General's newest post in its
    // thread view: Attach there opens Teams' Attach popover (with Browse
    // Teams and Channels) and the cloud file picker. Nothing is sent. Logs
    // THREADATTACH lines; pictures thread-attach-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--thread-attach-test") >= 0 && backend.signedIn && !!backend.teamsJson
        interval: 2000; repeat: true
        property int step: 0
        property var view: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-thread-attach-" + tag + ".png")))
            const log = (...a) => console.warn("THREADATTACH", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            switch (step) {
            case 0: {
                const team = JSON.parse(backend.teamsJson).find(t => t.name === "OST Test Team")
                const ch = team ? team.channels.find(c => c.name === "General") : null
                if (!ch) return
                backend.selectChat(ch.id, ch.name); break
            }
            case 3: {
                const post = (conversation.messages || []).filter(p => !p.deleted && p.kind !== "call").slice(-1)[0]
                log("post", post ? post.id : null)
                if (!post) { Qt.quit(); return }
                conversation.openPostView(post.id); break
            }
            case 5: { view = conversation.postViewForTest(); log("view", !!view); if (!view) { Qt.quit(); return } view.composeForTest().attachRequested(view.composeForTest().attachButton()); break }
            case 7: { const m = view.cloudAttachForTest().menu; log("menu", m.stateForTest()); cap("menu"); break }
            case 8: { const ca = view.cloudAttachForTest(); ca.closeMenu(); ca.picker.entry = "home"; ca.picker.open(); break }
            case 10: { const p = view.cloudAttachForTest().picker; log("picker", p.stateForTest()); cap("picker"); p.close(); break }
            case 11: Qt.quit(); return
            }
            step++
        }
    }

    // --picker-bar-test: the cloud file picker's My files with its command
    // bar, the Upload and view menus, Compact List and Tiles, and Create a
    // folder (opened, a colour picked, closed: nothing is made). Logs
    // PICKERBAR lines; pictures picker-bar-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--picker-bar-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-picker-bar-" + tag + ".png")))
            const log = (...a) => console.warn("PICKERBAR", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const p = conversation.cloudPickerForTest()
            switch (step) {
            case 0: { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name); break }
            case 2: p.entry = "myfiles"; p.open(); break
            case 4: log("list", p.stateForTest()); cap("list"); break
            case 5: p.openForTest("view:compact"); break
            case 6: cap("compact"); break
            case 7: p.openForTest("view:tiles"); break
            case 8: cap("tiles"); break
            case 9: p.openForTest("view:list"); p.openForTest("people"); break
            case 11: log("people", p.stateForTest()); cap("people"); break
            case 12: p.openForTest("myfiles"); break
            case 14: p.openForTest("newfolder"); break
            case 15: cap("newfolder"); break
            case 16: p.newFolderColor = 5; break
            case 17: cap("newfolder-blue"); break
            case 18: p.closeDialogsForTest(); p.close(); break
            case 19: Qt.quit(); return
            }
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

    // --teleprompter-test: the recorder's Script (Teams' teleprompter): a
    // script typed in, then read (scrolling, the word marked), the scroll
    // speed and a larger font. Logs PROMPT lines.
    Timer {
        running: Qt.application.arguments.indexOf("--teleprompter-test") >= 0 && chatList.chats.length > 1
        interval: 1500; repeat: true
        property int step: 0
        property var rec: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("PROMPT", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const text = "Hello everyone, this is a short update on the OST project.\nWe finished the video clip recorder today, and the editing works as it does in Teams.\nNext we will build the effects."
            switch (step) {
            case 0: { const c = chatList.chats.find(x => x.name === "OST Test 2"); backend.selectChat(c.id, c.name); break }
            case 2: rec = conversation.clipRecorderForTest(); rec.testSilent = true; rec.openFor(backend.currentChatId); rec.cameraOn = false; break
            case 3: log("open", rec.teleprompterForTest(true)); break
            case 4: cap("empty"); rec.teleprompterForTest(true, text); break
            case 5: cap("typed"); log("typed", rec.teleprompterForTest(true, undefined, true)); break
            case 8: log("playing", rec.teleprompterForTest(true)); cap("playing"); break
            case 9: log("paused", rec.teleprompterForTest(true, undefined, false)); break
            case 10: log("positions", rec.teleprompterSpeedForTest(true)); break
            case 11: cap("speed"); break
            case 12: rec.teleprompterSpeedForTest(false); rec.teleprompterFontForTest(2); break
            case 13: log("font", rec.teleprompterForTest(true)); cap("font"); break
            case 14: rec.teleprompterFontForTest(-2); rec.teleprompterForTest(false); break
            case 15: Qt.quit(); return
            }
            step++
        }
    }
    // --recorder-edit-test: in the OST Test 2 chat, Record audio (silently),
    // then the review's editing: Split, Trim, Record more, Rearrange and
    // Music; --recorder-edit-send=<text> then continues and sends the
    // rendered clip. Logs RECEDIT lines.
    Timer {
        running: Qt.application.arguments.indexOf("--recorder-edit-test") >= 0 && chatList.chats.length > 1
        interval: 1500; repeat: true
        property int step: 0
        property int waited: 0
        property var rec: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("RECEDIT", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const sendArg = Qt.application.arguments.find(a => a.startsWith("--recorder-edit-send="))
            switch (step) {
            case 0: { const c = chatList.chats.find(x => x.name === "OST Test 2"); if (!c) { log("no chat"); Qt.quit(); return } backend.selectChat(c.id, c.name); break }
            case 2: rec = conversation.clipRecorderForTest(); rec.testSilent = true; rec.openFor(backend.currentChatId); rec.cameraOn = false; break
            case 4: rec.startRecording(); break
            case 10: rec.stopAndReview(); break
            case 12: log("review", rec.editForTest()); cap("review"); break
            case 13: rec.seekForTest(4000); break
            case 14: log("canSplit", rec.editForTest().canSplit); rec.splitAtPlayhead(); break
            case 15: log("split", rec.editForTest()); cap("split"); break
            case 16: rec.selected = 0; rec.trimForTest(1000, 3000); break
            case 17: cap("trim"); break
            case 18: rec.confirmTrimForTest(); log("trimmed", rec.editForTest()); rec.stage = "setup"; break
            case 19: rec.startRecording(); break
            case 23: rec.stopAndReview(); break
            case 25: log("more", rec.editForTest()); cap("more"); rec.selected = 2; rec.moveSelected(-1); break
            case 26: log("rearranged", rec.editForTest()); rec.musicPanelForTest(true); break
            case 27: cap("music"); break
            case 28: rec.pickSongForTest(0, 0); break
            case 29: log("player", rec.playerForTest()); break
            case 30: log("music", rec.editForTest().music); log("player", rec.playerForTest()); cap("withmusic"); break
            case 31:
                if (!sendArg) { step = 99; return }
                rec.continueForTest(); break
            case 32: {
                const c = conversation.composeForTest().clip
                log("compose", c ? { rendering: c.rendering, uploading: c.uploading, path: c.path, id: c.id, error: c.error } : null)
                if (!c || !c.id) { if (c && c.error) { log("failed", c.error); Qt.quit(); return } if (waited++ < 60) return; log("timeout"); Qt.quit(); return }
                cap("stored")
                conversation.insertTextForTest(decodeURIComponent(sendArg.slice(sendArg.indexOf("=") + 1)))
                break
            }
            case 33: conversation.sendForTest(); break
            case 37: { const m = conversation.messages.filter(m => (m.videos || []).length > 0).pop(); log("sent", m ? { text: m.text, videos: m.videos } : null); cap("sent"); break }
            case 39: Qt.quit(); return
            case 100: rec.confirmClose = true; break
            case 101: Qt.quit(); return
            }
            step++
        }
    }
    // --recorder-test: in the OST Test 2 chat, Record video clip without the
    // camera or the room's sound: Record audio (the microphone picture,
    // recorded silently), Screen, the device menus, recording, paused,
    // review and Close's question (--recorder-camera: in camera mode on
    // linuxlt's test camera A). --recorder-send instead continues: the
    // clip goes into the compose box, is stored, and is sent with
    // --recorder-send=<text>. Logs RECORDER lines.
    Timer {
        running: Qt.application.arguments.indexOf("--recorder-test") >= 0 && chatList.chats.length > 1
        interval: 2000; repeat: true
        property int step: 0
        property int waited: 0
        property var rec: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("RECORDER", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const sendArg = Qt.application.arguments.find(a => a.startsWith("--recorder-send"))
            if (step === 0) {
                const c = chatList.chats.find(x => x.name === "OST Test 2")
                if (!c) { log("no chat"); Qt.quit(); return }
                backend.selectChat(c.id, c.name)
            } else if (step === 2) {
                rec = conversation.clipRecorderForTest()
                rec.testSilent = true
                rec.openFor(backend.currentChatId)
                rec.cameraOn = false
            } else if (step === 4) { log("audio", rec.stateForTest()); cap("audio") }
            else if (step === 5) rec.screenOn = true
            else if (step === 6) { log("screen", rec.stateForTest()); cap("screen") }
            else if (step === 7) { rec.screenOn = false; rec.openCamMenuForTest() }
            else if (step === 8) cap("cammenu")
            else if (step === 9) { rec.closeMenusForTest(); rec.openMicMenuForTest() }
            else if (step === 10) cap("micmenu")
            else if (step === 11) {
                rec.closeMenusForTest()
                // --recorder-camera: camera mode on the test camera (never
                // the laptop's own).
                if (Qt.application.arguments.indexOf("--recorder-camera") >= 0 && !rec.cameraOn) {
                    rec.pickCameraForTest("OST test camera A")
                    return
                }
                // --recorder-screen: screen mode (the desktop's own picker).
                if (Qt.application.arguments.indexOf("--recorder-screen") >= 0) rec.screenOn = true
                rec.startRecording()
            }
            // (Screen recording waits for the desktop's picker.)
            else if (step === 12 && rec.stage !== "recording") { if (waited++ < 60) return; log("never started", rec.stateForTest()); Qt.quit(); return }
            else if (step === 14) { log("recording", rec.stateForTest()); cap("recording") }
            else if (step === 15) rec.pauseForTest()
            else if (step === 16) { log("paused", rec.stateForTest()); cap("paused") }
            else if (step === 17) rec.resumeForTest()
            else if (step === 19) rec.stopAndReview()
            else if (step === 21) { log("review", rec.stateForTest()); cap("review") }
            else if (step === 22) { if (sendArg) rec.continueForTest(); else rec.confirmClose = true }
            else if (step === 23) { if (!sendArg) { cap("confirm"); step = 99; return } log("compose", conversation.composeForTest().clip); cap("compose") }
            else if (step === 24) {
                const c = conversation.composeForTest().clip
                if (!c || !c.id) { if (c && c.error) { log("upload failed", c.error); Qt.quit(); return } if (waited++ < 30) return; log("upload timeout"); Qt.quit(); return }
                log("stored", c); cap("stored")
                const text = sendArg.indexOf("=") > 0 ? decodeURIComponent(sendArg.slice(sendArg.indexOf("=") + 1)) : ""
                if (text) conversation.insertTextForTest(text)
            } else if (step === 25) conversation.sendForTest()
            else if (step === 29) { const m = conversation.messages.filter(m => (m.videos || []).length > 0).pop(); log("sent", m ? { text: m.text, videos: m.videos, mine: m.mine } : null); cap("sent") }
            else if (step === 30) Qt.quit()
            else if (step === 100) Qt.quit()
            step++
        }
    }
    // --videoclip-test: in the OST Test 2 chat, OST TEST 135's video clip
    // (recorded in Teams): its card, playing, the speed and options menus,
    // Quality ▸ 480p, Keyboard shortcuts, the ··· menu and the end screen;
    // --videoclip-download also downloads it. Logs VIDEOCLIP lines.
    Timer {
        running: Qt.application.arguments.indexOf("--videoclip-test") >= 0 && chatList.chats.length > 1
        interval: 2500; repeat: true
        property int step: 0
        property int waited: 0
        property var card: null
        function find(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) { const f = find(kids[i], name); if (f) return f }
            return null
        }
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("VIDEOCLIP", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            if (step === 0) {
                const c = chatList.chats.find(x => x.name === "OST Test 2")
                if (!c) { log("no chat"); Qt.quit(); return }
                backend.selectChat(c.id, c.name)
            } else if (step === 2) {
                const m = conversation.messages.filter(m => (m.videos || []).length > 0).pop()
                if (!m) { if (waited++ < 10) return; log("no clip message"); Qt.quit(); return }
                log("message", { text: m.text, flow: m.flow, videos: m.videos })
                conversation.jumpToMessage(m.id)
                card = { id: m.videos[0].id }
            } else if (step === 4) {
                card = find(window.contentItem, "videoClip-" + card.id)
                if (!card) { log("no card"); Qt.quit(); return }
                const p = card.mapToItem(window.contentItem, 0, 0)
                log("card", { x: p.x, y: p.y, w: card.width, h: card.height, state: card.stateForTest() })
                cap("preview")
            } else if (step === 5) card.play()
            else if (step === 8) { log("playing", card.stateForTest()); cap("playing") }
            else if (step === 9) { card.pauseForTest(); card.seekForTest(0.3) }
            else if (step === 10) { log("paused", card.stateForTest()); cap("paused") }
            else if (step === 11) card.openSpeedForTest()
            else if (step === 12) cap("speed")
            else if (step === 13) { card.closeMenusForTest(); card.openOptionsForTest() }
            else if (step === 14) cap("options")
            else if (step === 15) { card.closeMenusForTest(); card.openQualityForTest() }
            else if (step === 16) { log("qualities", card.stateForTest().qualities); cap("quality") }
            else if (step === 17) { card.closeMenusForTest(); card.setQuality("video_480p") }
            else if (step === 20) { log("480p", card.stateForTest()); card.pauseForTest() }
            else if (step === 21) card.showShortcutsForTest(true)
            else if (step === 22) cap("shortcuts")
            else if (step === 23) { card.showShortcutsForTest(false); card.openClipMenuForTest() }
            else if (step === 24) cap("menu")
            else if (step === 25) { card.closeMenusForTest(); card.seekForTest(0.95); card.resumeForTest() }
            else if (step === 28) { log("end", card.stateForTest()); cap("ended") }
            // --videoclip-download: the ··· menu's Download video too.
            else if (step === 29 && Qt.application.arguments.indexOf("--videoclip-download") >= 0) backend.videoClipDownload(card.clip.url)
            else if (step === 32) { log("status", backend.statusText); Qt.quit() }
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

    // --chatlist-keys-test: the chat list's Up / Down (Teams opens each
    // chat as you arrive), then with "Use Enter or Spacebar to show
    // content" on (synced, put back after) Down only moves and Enter opens.
    // Logs CLKEYS lines.
    Timer {
        running: Qt.application.arguments.indexOf("--chatlist-keys-test") >= 0 && backend.signedIn && chatList.chats.length > 2 && backend.settingsJson.length > 0
        interval: 2000; repeat: true
        property int step: 0
        property bool before: false
        onTriggered: {
            const log = (...a) => console.warn("CLKEYS", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const key = k => { chatList.forceActiveFocus(); if (k === "down") chatList.moveFocus(1); else if (k === "enter") chatList.openFocused() }
            switch (step) {
            case 0: before = chatList.enterToOpen; rail.current = "chat"; { const c = chatList.navItems[0]; backend.selectChat(c.id, c.name) } break
            case 1: log("start", backend.currentChatName, "enterToOpen", chatList.enterToOpen); key("down"); break
            case 2: log("down opens", backend.currentChatName, chatList.focusId === backend.currentChatId); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-auto.png"))); settingsView.setPropForTest("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", true); break
            case 4: log("enterToOpen", chatList.enterToOpen); key("down"); break
            case 5: log("down only moves", backend.currentChatName, "focus", chatList.focusId === backend.currentChatId); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-moved.png"))); key("enter"); break
            case 6: log("enter opens", backend.currentChatName, chatList.focusId === backend.currentChatId); settingsView.setPropForTest("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", before); break
            case 8: log("back", chatList.enterToOpen); Qt.quit(); return
            }
            step++
        }
    }

    // --new-chat-window-test: Settings ▸ General ▸ Starting chats on New
    // window (synced), Ctrl+N's window captured with a person picked (never
    // sent), then the window closed and the setting put back. Logs NEWWIN
    // lines.
    Timer {
        running: Qt.application.arguments.indexOf("--new-chat-window-test") >= 0 && backend.signedIn && backend.settingsJson.length > 0
        interval: 2500; repeat: true
        property int step: 0
        property bool before: false
        onTriggered: {
            const log = (...a) => console.warn("NEWWIN", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            switch (step) {
            case 0: before = window.newChatInWindow; rail.current = "settings"; settingsView.pageForTest("general"); break
            case 2: settingsView.setPropForTest("userPersonalSettings", "messagingSettings.alwaysPopOutNewChat", true); break
            case 4: window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-setting.png"))); log("in window", window.newChatInWindow, typeof window.syncedProps.userPersonalSettings, JSON.stringify((window.syncedProps.userPersonalSettings || {}).messagingSettings || null).slice(0, 300)); window.startNewChat(); break
            case 5: backend.searchPeople("OST Test 2"); break
            case 7: log("window", !!window.newChatWin); if (window.newChatWin) window.newChatWin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-window.png"))); break
            case 8: if (window.newChatWin) window.newChatWin.close(); settingsView.setPropForTest("userPersonalSettings", "messagingSettings.alwaysPopOutNewChat", before); break
            case 11: log("back", window.newChatInWindow); Qt.quit(); return
            }
            step++
        }
    }

    // --shortcut-profile-test: Settings ▸ General's Keyboard shortcuts
    // card, the Teams + Slack profile picked (synced) and read back, then
    // Teams only again. Logs KBPROFILE lines.
    Timer {
        running: Qt.application.arguments.indexOf("--shortcut-profile-test") >= 0 && backend.signedIn && backend.settingsJson.length > 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const log = (...a) => console.warn("KBPROFILE", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            switch (step) {
            case 0: rail.current = "settings"; settingsView.pageForTest("general"); log("start", window.shortcutProfile); break
            case 1: settingsView.scrollForTest(); break
            case 2: window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-kb.png"))); settingsView.setPropForTest("keyboardShortcutsSettings", "shortcutProfile", "chats_alt"); break
            case 5: log("slack", window.shortcutProfile, window.slackShortcuts, window.zoomShortcuts); backend.loadSettings(); break
            case 7: log("reloaded", window.shortcutProfile); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-kb-slack.png"))); settingsView.setPropForTest("keyboardShortcutsSettings", "shortcutProfile", "default"); break
            case 10: backend.loadSettings(); break
            case 12: log("back", window.shortcutProfile); Qt.quit(); return
            }
            step++
        }
    }

    // --about-test: About OST after a real update check, then with an
    // update shown (set locally): ABOUT lines and pictures.
    // --link-preview-test[=<text>]: in "OST group test", type a link into
    // compose as keys (Teams' AutoLink on Space), log the preview (LINKPREVIEW)
    // and the card's place, capture it; with --link-preview-send, send it and
    // log the sent message's preview, then remove it from the sent message
    // with --link-preview-remove. Pictures in /tmp/act.
    KeyTyper { id: linkTyper }
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--link-preview-test")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const arg = Qt.application.arguments.find(a => a.startsWith("--link-preview-test="))
            const text = arg ? arg.split("=").slice(1).join("=") : "OST link preview test https://www.rust-lang.org/ "
            const c = conversation.composeForTest()
            const mine = () => (conversation.messages || []).filter(m => m.mine && m.url_preview).pop()
            const removeOnly = Qt.application.arguments.indexOf("--link-preview-remove-only") >= 0
            // --link-preview-privacy: with Optional connected experiences off
            // (set, then restored), no card in compose or on messages.
            if (Qt.application.arguments.indexOf("--link-preview-privacy") >= 0) {
                if (st === 0) { backend.changeSetting("prop", "controllerConnectedServicesEnabled", JSON.stringify("false")); const ch = chatList.chats.find(x => x.name === "OST group test"); rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
                else if (st === 2) { conversation.focusCompose(); linkTyper.typeText(text) }
                else if (st === 4) { console.warn("LINKPREVIEW privacy-off compose", JSON.stringify(c.urlPreview), "shown", c.previewShown, "send", JSON.stringify(c.previewForSend()), "messages shown", conversation.previewsShown); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-privacy.png")) }
                else if (st === 5) { c.clear(); backend.changeSetting("prop", "controllerConnectedServicesEnabled", JSON.stringify("true")) }
                else if (st === 7) { console.warn("LINKPREVIEW privacy restored", conversation.previewsShown); Qt.quit() }
                return
            }
            if (st === 0) { const ch = chatList.chats.find(x => x.name === "OST group test"); rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
            else if (removeOnly) {
                // Remove the preview from your newest message that has one.
                if (st === 2) { const m = mine(); console.warn("LINKPREVIEW removing", m ? m.id : "none"); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-before-remove.png")); if (m) backend.removeUrlPreview(JSON.stringify(m)) }
                else if (st === 5) { const m = mine(); console.warn("LINKPREVIEW after remove", m ? m.id : "gone"); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-removed.png")) }
                else if (st > 5) Qt.quit()
            }
            else if (st === 1) { conversation.focusCompose(); linkTyper.typeText(text) }
            else if (st === 3) { console.warn("LINKPREVIEW compose", c.formattedText(), JSON.stringify(c.urlPreview), "shown", c.previewShown, "send", c.previewForSend()); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-compose.png")) }
            else if (st === 4 && Qt.application.arguments.indexOf("--link-preview-send") >= 0) conversation.sendCompose()
            else if (st === 7 && Qt.application.arguments.indexOf("--link-preview-send") >= 0) { const m = mine(); console.warn("LINKPREVIEW sent", m ? m.id + " " + JSON.stringify(m.url_preview) : "none"); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-sent.png")) }
            else if (st === 8 && Qt.application.arguments.indexOf("--link-preview-remove") >= 0) { const m = mine(); if (m) backend.removeUrlPreview(JSON.stringify(m)) }
            else if (st === 11 && Qt.application.arguments.indexOf("--link-preview-remove") >= 0) { const m = mine(); console.warn("LINKPREVIEW after remove", m ? m.id : "gone"); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/link-removed.png")) }
            else if (st > 12 || (st > 4 && Qt.application.arguments.indexOf("--link-preview-send") < 0)) { c.clear(); Qt.quit() }
        }
    }
    // --app-card-test[=<text>] with --shots=<dir>: in "OST group test", type a
    // link to a site with a Teams app (default a Wikipedia page) into
    // compose as keys, log the app's card (APPCARD compose) and capture
    // app-card-compose.png; --app-card-collapse collapses it first
    // (app-card-collapsed.png); --app-card-send sends it and logs the sent
    // message's card or preview (APPCARD sent, app-card-sent.png).
    // --app-card-messages only captures the chat's newest messages
    // (app-card-messages.png) and logs their link cards.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--app-card-test") || a === "--app-card-messages") && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const args = Qt.application.arguments
            const dir = (args.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const arg = args.find(a => a.startsWith("--app-card-test="))
            const text = arg ? arg.split("=").slice(1).join("=") : "OST app card test https://en.wikipedia.org/wiki/Lighthouse "
            const c = conversation.composeForTest()
            const linkCards = () => (conversation.messages || []).filter(m => (m.cards || []).some(k => k.link_card) || m.url_preview).slice(-3)
            if (st === 0) { const ch = chatList.chats.find(x => x.name === "OST group test"); rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
            else if (args.indexOf("--app-card-messages") >= 0) {
                if (st === 3) { conversation.jumpToNewest(); for (const m of linkCards()) console.warn("APPCARD message", m.id, JSON.stringify((m.cards || []).map(k => ({ link: k.link_card, app: k.app_name, type: k.content_type, title: (k.content || {}).title }))), "preview", JSON.stringify(m.url_preview || null)); shot("app-card-messages") }
                else if (st > 3) Qt.quit()
            }
            else if (st === 1) { conversation.focusCompose(); linkTyper.typeText(text) }
            else if (st === 4) { console.warn("APPCARD compose", JSON.stringify(c.appCard), "shown", c.appCardShown, "preview", JSON.stringify(c.urlPreview)); shot("app-card-compose") }
            else if (st === 5 && args.indexOf("--app-card-collapse") >= 0) c.setAppCard({ collapsed: true })
            else if (st === 6 && args.indexOf("--app-card-collapse") >= 0) { console.warn("APPCARD collapsed", c.appCardCollapsedShown, JSON.stringify(c.shownPreview)); shot("app-card-collapsed") }
            else if (st === 7 && args.indexOf("--app-card-send") >= 0) { console.warn("APPCARD send", c.appCardForSend().length > 0, c.previewForSend()); conversation.sendCompose() }
            else if (st === 10 && args.indexOf("--app-card-send") >= 0) { conversation.jumpToNewest(); const m = linkCards().pop(); console.warn("APPCARD sent", m ? m.id + " " + JSON.stringify((m.cards || []).map(k => ({ link: k.link_card, app: k.app_name, type: k.content_type }))) + " preview " + JSON.stringify(m.url_preview || null) : "none"); shot("app-card-sent") }
            else if (st > 11 || (st > 7 && args.indexOf("--app-card-send") < 0)) { c.clear(); Qt.quit() }
        }
    }
    // --smart-reply-test[=<chat name>] with --shots=<dir>: open that chat
    // (default "OST Test 1", for OST Test 2's profile), log the suggested
    // replies Teams' rules show (SMARTREPLY) and capture smart-replies.png,
    // then the feedback form (smart-feedback.png) and, when a file is
    // suggested, Share a file's attach menu (smart-share-file.png).
    // --smart-reply-fake puts a set with every kind on the newest message
    // first (to draw the chips the tenant's features turn off).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--smart-reply-test")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const args = Qt.application.arguments
            const dir = (args.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            const arg = args.find(a => a.startsWith("--smart-reply-test="))
            const name = arg ? arg.split("=").slice(1).join("=") : "OST Test 1"
            const log = (...a) => console.warn("SMARTREPLY", ...a)
            if (st === 0) { const ch = chatList.chats.find(x => x.name === name); rail.current = "chat"; if (ch) backend.selectChat(ch.id, ch.name); else log("no chat", name) }
            else if (st === 4) {
                if (args.indexOf("--smart-reply-fake") >= 0) {
                    const m = (conversation.messages || []).filter(x => x.kind === "message").pop()
                    const t = new Date().toISOString()
                    const at = k => ({ title: k.title, value: k.value || k.title, kind: k.kind, time: t, target: m ? m.id : "", start_time: k.start || "", end_time: k.end || "" })
                    conversation.setSmartRepliesForTest({ target: m ? m.id : "", timestamp: t, feedback: true, replies: [
                        at({ title: "Share file", value: "0", kind: "file_sharing" }), at({ title: "Sure!", kind: "reply" }), at({ title: "Sounds good", kind: "reply" }), at({ title: "Not right now", kind: "reply" })] })
                }
                log("shown", JSON.stringify(conversation.smartRepliesForTest())); shot("smart-replies")
            }
            else if (st === 5) { const b = conversation.smartReplyFeedbackButtonForTest(); if (b.visible) conversation.smartReplyFeedbackForTest().openFor(b); log("feedback", b.visible, JSON.stringify(conversation.smartReplyFeedbackForTest().categories)) }
            else if (st === 6) shot("smart-feedback")
            else if (st === 7) { conversation.smartReplyFeedbackForTest().close(); log("share file", conversation.clickSuggestionForTest("file_sharing")) }
            else if (st === 8) shot("smart-share-file")
            else if (st === 9 && args.indexOf("--smart-reply-fake") >= 0) {
                const m = (conversation.messages || []).filter(x => x.kind === "message").pop()
                const t = new Date().toISOString()
                conversation.closeAttachForTest()
                conversation.setSmartRepliesForTest({ target: m ? m.id : "", timestamp: t, feedback: true, replies: [
                    { title: "Schedule a meeting", value: "Schedule a meeting", kind: "meeting", time: t, target: m ? m.id : "", start_time: "", end_time: "" },
                    { title: "Sure!", value: "Sure!", kind: "reply", time: t, target: m ? m.id : "", start_time: "", end_time: "" }] })
            }
            else if (st === 10 && args.indexOf("--smart-reply-fake") >= 0) { log("meeting", JSON.stringify(conversation.smartRepliesForTest())); shot("smart-meeting") }
            else if (st > 10 || (st > 8 && args.indexOf("--smart-reply-fake") < 0)) Qt.quit()
        }
    }
    // --premium-test: Teams Premium as it stands for the account (PREMIUM
    // line with the mode and days left), the title bar's button, then each
    // page of the Premium dialog in turn (offer, pending, active, home,
    // licensed, benefits scrolled half way, cancel). Pictures in /tmp/act.
    Timer {
        running: Qt.application.arguments.indexOf("--premium-test") >= 0 && backend.signedIn
        interval: 1500; repeat: true
        property int step: 0
        readonly property var pages: ["offer", "pending", "active", "home", "licensed", "benefits", "cancel"]
        onTriggered: {
            const st = step++
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/premium-" + n + ".png"))
            if (st === 2) { console.warn("PREMIUM", backend.premiumJson, "mode", titleBar.premiumMode, "days", titleBar.premiumDaysLeft); shot("titlebar") }
            else if (st === 3) titleBar.moreMenuForTest(true)
            else if (st === 4) shot("menu")
            else if (st >= 5 && st < 5 + pages.length * 2) {
                const i = Math.floor((st - 5) / 2), pg = pages[i]
                if ((st - 5) % 2 === 0) { titleBar.moreMenuForTest(false); premiumDialog.page = pg; if (!premiumDialog.opened) premiumDialog.open() }
                else { if (pg === "benefits") premiumDialog.contentItem.parent && 0; shot(pg) }
            }
            else if (st > 5 + pages.length * 2) { premiumDialog.close(); Qt.quit() }
        }
    }
    // --zoom-test: hold 150% for 12 s (for a screen capture), open the
    // menu at that zoom, then reset to 100% and quit.
    Timer {
        running: Qt.application.arguments.indexOf("--zoom-test") >= 0 && backend.signedIn
        interval: 1000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            if (st === 0) window.setZoom(150)
            else if (st === 2) titleBar.moreMenuForTest(true)
            else if (st === 12) { console.warn("ZOOM", window.zoomPercent, window.contentItem.scale, window.contentItem.width, window.contentItem.height); titleBar.moreMenuForTest(false); window.zoomReset() }
            else if (st > 13) Qt.quit()
        }
    }
    // --menu-test: Settings and more as Teams': the menu (MENU lines with
    // each row's place), Zoom in twice then reset, Get the mobile app,
    // Unlock Teams Premium (when offered), Downloads and Cast (searching,
    // then after 20 s nothing found). Pictures in /tmp/act.
    Timer {
        running: Qt.application.arguments.indexOf("--menu-test") >= 0 && backend.signedIn
        interval: 1500; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/menu-" + n + ".png"))
            if (st === 1) {
                const m = titleBar.moreMenuForTest(true)
                const rows = []
                const walk = it => { for (let i = 0; i < it.children.length; i++) { const c = it.children[i]; if (!c.visible) continue; if (c.label !== undefined && c.label) { const p = c.mapToItem(m, 0, 0); rows.push([c.label, Math.round(p.y * 100) / 100, Math.round(c.height * 100) / 100]) } walk(c) } }
                walk(m)
                const mp = m.mapToItem(null, 0, 0)
                console.warn("MENU box", Math.round(mp.x * 100) / 100, Math.round(mp.y * 100) / 100, m.width, m.height, "premium", backend.premiumJson, "rows", JSON.stringify(rows))
            }
            else if (st === 2) shot("open")
            else if (st === 3) { window.zoomIn(); window.zoomIn() }
            else if (st === 4) { console.warn("MENU zoom", window.zoomPercent, window.contentItem.scale, window.contentItem.width); shot("zoom110") }
            else if (st === 5) { window.zoomReset(); titleBar.moreMenuForTest(false); mobileAppDialog.open() }
            else if (st === 6) shot("mobile")
            else if (st === 7) { mobileAppDialog.close(); premiumDialog.openFor("offer") }
            else if (st === 8) shot("premium")
            else if (st === 9) { premiumDialog.close(); downloadsFlyout.open() }
            else if (st === 10) { console.warn("MENU downloads", backend.downloadsJson); shot("downloads") }
            else if (st === 11) { downloadsFlyout.close(); castWindow.start() }
            else if (st === 12) castWindow.contentItem.grabToImage(r => r.saveToFile("/tmp/act/menu-cast.png"))
            else if (st === 27) { console.warn("MENU cast after 20 s, searching", castWindow.searching); castWindow.contentItem.grabToImage(r => r.saveToFile("/tmp/act/menu-cast-none.png")) }
            else if (st > 28) Qt.quit()
        }
    }
    // --chatlist-menu-test with --shots=<dir>: the chat list's ··· menu (CHATLIST
    // menu rows), its Mark all as read options, Shift+Esc's confirmation
    // (opened and closed again: nothing is marked), and the list's width:
    // Teams' default for the window, a drag to 400 and below 280 (clamped),
    // ArrowRight on the divider, the kept vw, and a double-click reset.
    // The width setting is put back as it was.
    Timer {
        running: Qt.application.arguments.indexOf("--chatlist-menu-test") >= 0 && backend.signedIn
        interval: 1500; repeat: true
        property int step: 0
        property string keptVw: ""
        onTriggered: {
            const st = step++
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "chatlist-" + n + ".png"))
            const r2 = v => Math.round(v * 100) / 100
            const rowsOf = m => {
                const out = []
                const walk = it => { for (let i = 0; i < it.children.length; i++) { const c = it.children[i]; if (!c.visible) continue; if (c.modelData !== undefined && c.modelData && (c.modelData.label || c.modelData.separator)) { const q = c.mapToItem(m.contentItem, 0, 0); out.push([c.modelData.separator ? "|" : c.modelData.label, r2(q.y), r2(c.height), c.modelData.keys || "", c.modelData.split ? "split" : ""]) } else walk(c) } }
                walk(m.contentItem)
                return out
            }
            if (st === 0) { keptVw = backend.setting("listWidthVw") || ""; backend.setSetting("listWidthVw", ""); chatList.widthVw = -1 }
            else if (st === 1) console.warn("CHATLIST width", window.width, chatList.width, "default", chatList.defaultWidth, "max", chatList.maxWidth)
            else if (st === 2) shot("default")
            else if (st === 3) chatList.openListMenuForTest()
            else if (st === 4) {
                const m = chatList.listMenuForTest()
                const p = m.contentItem.mapToItem(null, 0, 0)
                console.warn("CHATLIST menu", r2(p.x), r2(p.y), r2(m.width), r2(m.height), JSON.stringify(rowsOf(m)))
                shot("menu")
            }
            else if (st === 5) chatList.openMarkAllSubmenuForTest()
            else if (st === 6) {
                const sm = chatList.listMenuForTest().subMenu
                if (sm) { const p = sm.contentItem.mapToItem(null, 0, 0); console.warn("CHATLIST markall", r2(p.x), r2(p.y), r2(sm.width), JSON.stringify(rowsOf(sm))) }
                shot("menu-markall")
            }
            else if (st === 7) { chatList.listMenuForTest().close(); window.shiftEscMarkAll() }
            else if (st === 8) {
                const p = markAllDialog.contentItem.mapToItem(null, 0, 0)
                console.warn("CHATLIST dialog", markAllDialog.opened, r2(markAllDialog.width), r2(markAllDialog.height), markAllDialog.title, "|", markAllDialog.body)
                shot("maar-dialog")
            }
            else if (st === 9) markAllDialog.checked = true
            else if (st === 10) shot("maar-dialog-checked")
            else if (st === 11) markAllDialog.close()
            else if (st === 12) { console.warn("CHATLIST skip setting", JSON.stringify(backend.setting("skipMarkAllAsReadConfirmDialog"))); chatList.setWidthPx(400) }
            else if (st === 13) { console.warn("CHATLIST drag 400 ->", chatList.width, "vw", r2(chatList.widthVw)); shot("wide") }
            else if (st === 14) chatList.setWidthPx(200)
            else if (st === 15) { console.warn("CHATLIST drag 200 ->", chatList.width); chatList.setWidthPx(chatList.width + 20) }
            else if (st === 16) console.warn("CHATLIST arrow right ->", chatList.width, "kept", backend.setting("listWidthVw"))
            else if (st === 17) chatList.resetWidth()
            else if (st === 18) { console.warn("CHATLIST reset ->", chatList.width, "kept", backend.setting("listWidthVw")); shot("reset") }
            else if (st === 19) { backend.setSetting("listWidthVw", keptVw); console.warn("CHATLIST restored", JSON.stringify(keptVw)); Qt.quit() }
        }
    }
    // --new-chat-form-test with --shots=<dir>: Teams' new chat form before
    // picking anyone (the suggestions and the note), after picking the
    // first suggestion you have a chat with (its messages under the To
    // row), with the group name open, and with two people (the note). It
    // never sends: the form is closed at the end (NEWCHAT lines).
    Timer {
        running: Qt.application.arguments.indexOf("--new-chat-form-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "newchat-" + n + ".png"))
            const r2 = v => Math.round(v * 100) / 100
            if (st === 0) { rail.current = "chat"; window.composing = true }
            else if (st === 2) {
                const p = newChat.mapToItem(null, 0, 0)
                console.warn("NEWCHAT empty at", r2(p.x), r2(p.y), r2(newChat.width), r2(newChat.height), "suggesting", newChat.suggesting,
                    "history", newChat.history, "compose y", r2(newChat.composeBox().y), r2(newChat.composeBox().height))
                // Teams' rows: name | second line [| Guest].
                console.warn("NEWCHAT suggestions", JSON.stringify(newChat.suggestions.map(x => x.name + " | " + (x.sub || "") + (x.guest ? " | Guest" : ""))))
                shot("empty")
            }
            else if (st === 3) {
                const s1 = newChat.suggestions.find(x => newChat.chatWith(x.id)) || newChat.suggestions[0]
                if (s1) newChat.pick(s1)
            }
            else if (st === 5) {
                console.warn("NEWCHAT picked", JSON.stringify(newChat.picked), "history", newChat.history, newChat.existingChat, "current", backend.currentChatId)
                shot("picked")
            }
            else if (st === 6) { newChat.naming = true }
            else if (st === 7) shot("group")
            else if (st === 8) {
                newChat.naming = false
                const s2 = newChat.suggestions.find(x => !/\(You\)$/.test(x.name)) || newChat.suggestions[0]
                if (s2) newChat.pick(s2)
            }
            else if (st === 9) { console.warn("NEWCHAT two", JSON.stringify(newChat.picked.map(x => x.name)), "history", newChat.history); shot("two") }
            else if (st === 10) { window.composing = false; console.warn("NEWCHAT closed", window.composing) }
            else if (st === 11) Qt.quit()
        }
    }
    // --team-live=<action> with --shots=<dir>: live team actions, only on
    // teams named "OST TEST…" and only adding OST Test 2 or "OST Guest…":
    // create:<name> (Create team from scratch, public), join:<name> (Join a
    // team: search it, Join), add:<team>:<person> (Add member), delete:<team>
    // (Delete, the checkbox ticked). TEAMLIVE lines; teamlive-*.png.
    Timer {
        readonly property string spec: (Qt.application.arguments.find(a => a.startsWith("--team-live=")) || "").slice(12)
        running: spec.length > 0 && backend.signedIn && backend.teamsJson.length > 2
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const dir = ((Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8)) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "teamlive-" + n + ".png"))
            const log = (...a) => console.warn("TEAMLIVE", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const parts = spec.split(":"), action = parts[0], name = parts[1] || "", who = parts[2] || ""
            const team = () => JSON.parse(backend.teamsJson || "[]").find(t => t.name === name)
            if (!name.startsWith("OST TEST") || (action === "add" && who !== "OST Test 2" && !who.startsWith("OST Guest"))) { log("refused", spec); Qt.quit(); return }
            if (action === "create") {
                if (st === 0) { rail.current = "chat"; createTeamDialog.startScratch(false) }
                else if (st === 1) { createTeamDialog.setNameForTest(name); createTeamDialog.isPublic = true; createTeamDialog.setFirstChannelForTest("OST TEST channel") }
                else if (st === 2) { shot("create-form"); log("body", JSON.stringify(createTeamDialog.bodyForTest())); createTeamDialog.create() }
                else if (st === 8) { const t = team(); log("created", t ? t.thread_id : "not listed yet", "open", backend.currentChatName, backend.currentChatId); shot("created") }
                else if (st === 12) { const t = team(); log("listed", !!t, t ? JSON.stringify(t.channels.map(c => c.name)) : "", "add members open", window.newTeamMembersForTest().opened, "open", backend.currentChatName); shot("created-later"); window.newTeamMembersForTest().close() }
                else if (st === 13) Qt.quit()
            } else if (action === "join") {
                if (st === 0) { rail.current = "chat"; window.openTeamPage("join") }
                else if (st === 2) joinTeamPage.searchForTest(name)
                else if (st === 5) { log("found", JSON.stringify(joinTeamPage.results.map(t => [t.name, t.private]))); shot("join-search"); const t = joinTeamPage.results.find(t => t.name === name); if (t) joinTeamPage.join(t) }
                else if (st === 9) { log("state", JSON.stringify(joinTeamPage.joinState), "listed", !!team(), "open", backend.currentChatName); shot("joined") }
                else if (st === 12) { log("listed later", !!team()); Qt.quit() }
            } else if (action === "add") {
                const am = chatList.teamMenuForTest().addMembersForTest()
                if (st === 0) { const t = team(); if (!t) { log("no team"); Qt.quit(); return } chatList.teamMenuForTest().team = t; am.start(t.id, t.thread_id, t.name) }
                else if (st === 2) am.searchForTest(who)
                else if (st === 5) { const r = am.results; log("results", JSON.stringify(r.map(x => x.name))); const p = r.find(x => x.name === who); if (p) am.pick(p); shot("add-picked") }
                else if (st === 6) { am.add() }
                else if (st === 10) { log("outcome", JSON.stringify(am.outcome)); shot("add-done") }
                else if (st === 11) { am.close(); Qt.quit() }
            } else if (action === "delete") {
                if (st === 0) { const t = team(); if (!t) { log("no team"); Qt.quit(); return } chatList.openTeamMenu(t, chatList, 120, 300) }
                else if (st === 1) { shot("delete-menu"); chatList.teamMenuForTest().menu.close(); chatList.teamMenuForTest().teamActionForTest().start("delete", name) }
                else if (st === 2) { chatList.teamMenuForTest().teamActionForTest().checked = true; shot("delete-dialog") }
                else if (st === 3) { const d = chatList.teamMenuForTest().teamActionForTest(); d.confirmed(true); d.close() }
                else if (st === 9) { log("still listed", !!team()); shot("deleted"); Qt.quit() }
            }
        }
    }
    // --leave-test=<chat name> with --shots=<dir>: only for a test chat
    // whose name starts "OST TEST". Its list menu (with Leave), Teams'
    // "Leave this chat?", then Leave; logs whether the list still has it
    // (LEAVE lines; leave-*.png). With --leave-remove-others it first
    // removes everyone else (so nobody is left in the test chat).
    Timer {
        readonly property string target: (Qt.application.arguments.find(a => a.startsWith("--leave-test=")) || "").slice(13)
        running: target.length > 0 && backend.signedIn && chatList.chats.length > 0
        interval: 3000; repeat: true
        property int step: 0
        property var chat: null
        onTriggered: {
            const st = step++
            const dir = ((Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8)) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "leave-" + n + ".png"))
            const log = (...a) => console.warn("LEAVE", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const others = () => (backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []).filter(m => !m.me)
            if (st === 0) {
                chat = chatList.chats.find(c => c.name === target)
                if (!chat || !target.startsWith("OST TEST")) { log("no test chat", target); Qt.quit(); return }
                rail.current = "chat"; backend.selectChat(chat.id, chat.name)
            }
            else if (st === 2) {
                log("members", JSON.stringify((backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []).map(m => m.name)))
                if (Qt.application.arguments.indexOf("--leave-remove-others") >= 0) for (const m of others()) { log("remove", m.name); backend.removeChatMember(m.mri) }
            }
            else if (st === 5) { log("left with", JSON.stringify(others().map(m => m.name))); chatList.openRowMenuForTest(chat.id); const r = chatList.rowsForTest[chat.id]; log("menu", r ? JSON.stringify(r.menuItemsForTest().map(i => i.label || "-")) : "no row") }
            else if (st === 6) shot("menu")
            else if (st === 7) { chatList.closeRowMenuForTest(); const r = chatList.rowsForTest[chat.id]; if (r) r.leaveForTest().open() }
            else if (st === 8) shot("dialog")
            else if (st === 9) { const r = chatList.rowsForTest[chat.id]; if (r) { r.leaveForTest().close(); backend.leaveChat(chat.id) } }
            else if (st === 12) { log("still listed", chatList.chats.some(c => c.id === chat.id), "open", backend.currentChatName); shot("after") }
            else if (st === 13) Qt.quit()
        }
    }
    // --list-keys-test with --shots=<dir>: Teams' list keys in Activity,
    // @mentions and Followed threads: Down opens the next row as you arrive
    // (the focus ring on it); then with "Use Enter or Spacebar to show
    // content" on (synced, put back after) Down only moves and Enter opens.
    // LISTKEYS lines; listkeys-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--list-keys-test") >= 0 && backend.signedIn && backend.settingsJson.length > 0 && backend.activityJson.length > 2
        interval: 2500; repeat: true
        property int step: 0
        property bool before: false
        onTriggered: {
            const st = step++
            const dir = ((Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8)) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "listkeys-" + n + ".png"))
            const log = (...a) => console.warn("LISTKEYS", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const press = (view, key) => { view.forceActiveFocus(); view.keysForTest().handle({ key: key, modifiers: 0, accepted: false }, view.selectedId !== undefined ? view.selectedId : view.selectedKey) }
            const views = [["activity", activityView, () => { rail.current = "activity" }],
                           ["mentions", mentionsView, () => { rail.current = "chat"; chatList.openMentions() }],
                           ["followed", quickView, () => { rail.current = "chat"; chatList.openQuick("followed") }]]
            // Rounds of 4 steps: the three lists as they are, the setting
            // on, the three lists again, the setting back.
            const round = Math.floor(st / 4), phase = st % 4
            if (st === 0) before = window.enterToShow
            if (round === 3) { if (phase === 0) settingsView.setPropForTest("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", !before); return }
            if (round === 7) {
                if (phase === 0) { settingsView.setPropForTest("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", before); log("put back", before) }
                else if (phase === 2) { log("back", window.enterToShow); Qt.quit() }
                return
            }
            const [name, view, open] = views[round < 3 ? round : round - 4]
            const sel = () => view.selectedId !== undefined ? view.selectedId : view.selectedKey
            const tag = name + (window.enterToShow ? "-enter" : "-auto")
            if (phase === 0) { open(); log(tag, "open", "enterToShow", window.enterToShow, "rows", view.keysForTest().items.length) }
            else if (phase === 1) { press(view, Qt.Key_Down); press(view, Qt.Key_Down); log(tag, "down x2: focus", view.keysForTest().focusKey, "selected", sel(), "ring", view.keysForTest().keyboardNav, "chat", backend.currentChatName) }
            else if (phase === 2) { shot(tag); press(view, Qt.Key_Return); log(tag, "enter: selected", sel(), "same as focus", sel() === view.keysForTest().focusKey, "chat", backend.currentChatName) }
        }
    }
    // --reorder-test=<section name|teams> with --shots=<dir>: Teams'
    // reordering in that section (or Teams and channels). Settings ▸
    // Accessibility with "Turn on single pointer controls" turned on; the
    // second row's menu (Start reordering); Move Up, then Move Down (back
    // as it was); then a drag of the first row below the second (the
    // overlay and drop line captured mid-drag), and a drag back. Each step
    // logs REORDER lines with the order shown and, after the server
    // answers, the order it keeps. The setting is put back at the end.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--reorder-test=")) && backend.signedIn && chatList.folders.length > 0 && chatList.folders[0].id !== ""
        interval: 2500; repeat: true
        property int step: 0
        property string group: ""
        property bool before: false
        property var start: []
        onTriggered: {
            const st = step++
            const arg = k => { const a = Qt.application.arguments.find(a => a.startsWith(k + "=")); return a ? a.slice(k.length + 1) : "" }
            const dir = (arg("--shots") || "/tmp/act") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "reorder-" + n + ".png"))
            const log = (...a) => console.warn("REORDER", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const names = () => {
                if (group === "teams") return chatList.teams.map(t => t.name)
                const f = chatList.folders.find(f => f.id === group)
                return f ? f.items.map(id => (chatList.chats.find(c => c.id === id) || { name: id }).name) : []
            }
            const rowOf = k => chatList.dragRows[group + "|" + k]
            const scene = (it, dy) => it.mapToItem(null, it.width / 2, dy)
            if (st === 0) {
                const want = arg("--reorder-test")
                const f = chatList.folders.find(f => f.title === want)
                group = want === "teams" ? "teams" : f ? f.id : ""
                if (!group) { log("no such section", want); Qt.quit(); return }
                rail.current = "settings"; settingsView.pageForTest("accessibility")
                before = window.singlePointReordering
                backend.setSetting("singlePointReordering", "true"); window.singlePointReordering = true
            }
            else if (st === 1) shot("setting")
            else if (st === 2) {
                rail.current = "chat"
                start = chatList.groupOrder(group)
                log("start", group, names(), JSON.stringify(start))
                if (start.length < 2) { log("needs two rows"); Qt.quit(); return }
                const it = rowOf(start[1])
                if (it) chatList.scrollIntoViewForTest(it)
            }
            else if (st === 3) {
                // The second row's menu, with Start reordering.
                if (group === "teams") { const t = chatList.teams.find(t => t.thread_id === start[1]); chatList.openTeamMenu(t, rowOf(start[1]), 60, 30); log("menu", JSON.stringify(chatList.teamMenuForTest().menu.items.map(i => i.label || "-"))) }
                else { chatList.openRowMenuForTest(start[1]); const r = chatList.rowsForTest[start[1]]; log("menu", r ? JSON.stringify(r.menuItemsForTest().map(i => i.label || "-")) : "no row") }
            }
            else if (st === 4) shot("menu")
            else if (st === 5) {
                if (group === "teams") chatList.teamMenuForTest().menu.close(); else chatList.closeRowMenuForTest()
                chatList.startReorder(group, start[1])
            }
            else if (st === 6) { log("reordering", chatList.reorderKey, "focused", chatList.reorderButtonFocused); shot("mode") }
            else if (st === 7) { chatList.reorderStep(-1); log("moved up", names()) }
            else if (st === 9) {
                log("kept", names(), "still reordering", chatList.reorderKey === start[1]); shot("moved-up")
                // --reorder-only-up: leave it moved (to compare with Teams;
                // the same run again moves it back when there are two).
                if (Qt.application.arguments.indexOf("--reorder-only-up") >= 0) {
                    chatList.stopReorder()
                    backend.setSetting("singlePointReordering", before ? "true" : "false"); window.singlePointReordering = before
                    step = 30
                }
            }
            else if (st === 32) Qt.quit()
            else if (st === 10) chatList.reorderStep(1)
            else if (st === 12) { log("back", names(), JSON.stringify(chatList.groupOrder(group)) === JSON.stringify(start)); chatList.stopReorder() }
            else if (st === 13) {
                // Drag the first row below the second.
                const a = rowOf(start[0])
                if (!a) { log("rows not shown"); return }
                chatList.dragStart(group, start[0], { name: names()[0], kind: group === "teams" ? "team" : "chat", photoId: group === "teams" ? "team:" + (chatList.teams.find(t => t.thread_id === start[0]) || {}).id : "" }, a, Qt.point(a.width / 2, a.dragHeight / 2))
                chatList.dragMove(scene(a, a.dragHeight / 2))
            }
            else if (st === 14) { const b = rowOf(start[1]); chatList.dragMove(scene(b, b.dragHeight * 0.8)); log("dragging", JSON.stringify(chatList.dropAt)) }
            else if (st === 15) shot("drag")
            else if (st === 16) { chatList.dragEnd(); log("dropped", names()) }
            else if (st === 18) {
                log("kept", names())
                const now = chatList.groupOrder(group)
                const a = rowOf(now[1])
                if (a) { chatList.dragStart(group, now[1], { name: "", kind: "chat" }, a, Qt.point(a.width / 2, a.dragHeight / 2)); chatList.dragMove(scene(a, a.dragHeight / 2)) }
            }
            else if (st === 19) { const now = chatList.groupOrder(group); const b = rowOf(now[0]); if (b) chatList.dragMove(scene(b, 2)); log("dragging back", JSON.stringify(chatList.dropAt)); chatList.dragEnd() }
            else if (st === 21) {
                log("back", names(), JSON.stringify(chatList.groupOrder(group)) === JSON.stringify(start))
                backend.setSetting("singlePointReordering", before ? "true" : "false"); window.singlePointReordering = before
                shot("end")
            }
            else if (st === 22) Qt.quit()
        }
    }
    // --new-chat-compose-test with --shots=<dir> --new-chat-to=<name>[,<name>…]
    // [--new-chat-name=<group name>] [--new-chat-text=<text>]
    // [--new-chat-file=<path>] [--new-chat-urgent] [--new-chat-send]:
    // the new chat form's compose box as a conversation's: the people
    // picked from Teams' suggestions (or its search), bold + italic text,
    // a file from this device, "+" (Teams' short list) and Set delivery
    // options ▸ Important (or Urgent), then, only with --new-chat-send,
    // Send: the chat is made and the message goes from its compose box.
    // NEWCHATSEND lines; newchat-compose-*.png.
    Timer {
        running: Qt.application.arguments.indexOf("--new-chat-compose-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property var want: []
        onTriggered: {
            const st = step++
            const arg = k => { const a = Qt.application.arguments.find(a => a.startsWith(k + "=")); return a ? a.slice(k.length + 1) : "" }
            const dir = (arg("--shots") || "/tmp/act") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "newchat-compose-" + n + ".png"))
            const box = newChat.composeBox()
            if (st === 0) { want = arg("--new-chat-to").split(",").filter(s => s); rail.current = "chat"; window.composing = true }
            else if (st === 2 || st === 4 || st === 6) {
                // Pick each from the suggestions; search for the rest.
                for (const n of want.slice()) {
                    const s = newChat.suggestions.find(x => x.name === n)
                    if (s) { newChat.pick(s); want = want.filter(w => w !== n) }
                }
                if (want.length) { newChat.search(want[0]); newChat.setFieldForTest(want[0]) }
                console.warn("NEWCHATSEND picked", JSON.stringify(newChat.picked), "left", JSON.stringify(want))
            }
            else if (st === 7) {
                if (want.length) { console.warn("NEWCHATSEND couldn't find", JSON.stringify(want)); Qt.quit(); return }
                newChat.setFieldForTest("")
                const name = arg("--new-chat-name")
                if (name) { newChat.naming = true; newChat.nameText = name }
                const text = arg("--new-chat-text") || "OST new chat compose test"
                box.setHtml("<b>" + text + "</b> <i>formatted from the new chat form</i>")
                const f = arg("--new-chat-file")
                if (f) newChat.attachForTest([f])
                newChat.plusForTest()
            }
            else if (st === 8) shot("plus")
            else if (st === 9) {
                box.closePlusForTest()
                box.importance = Qt.application.arguments.indexOf("--new-chat-urgent") >= 0 ? "urgent" : "high"
                console.warn("NEWCHATSEND message", newChat.message())
            }
            else if (st === 10) shot("ready")
            else if (st === 11) {
                if (Qt.application.arguments.indexOf("--new-chat-send") < 0) { window.composing = false; console.warn("NEWCHATSEND not sent"); Qt.quit(); return }
                box.trySubmit()
                console.warn("NEWCHATSEND sent", "composing", window.composing)
            }
            else if (st === 16) {
                const last = conversation.messages.slice(-2).map(m => ({ id: m.id, text: (m.text || "").slice(0, 80), html: (m.html || "").slice(0, 200), files: (m.files || []).map(f => f.name), importance: m.importance || "" }))
                console.warn("NEWCHATSEND chat", backend.currentChatId, backend.currentChatName, JSON.stringify(last))
                shot("sent")
            }
            else if (st === 17) Qt.quit()
        }
    }
    // --tab-dropdown-test with --open-chat=<id> --size=<narrow> --shots=<dir>:
    // under 640 the tabs fold into Teams' dropdown under the title; logs
    // TABDROPDOWN (the header width, the button, the menu's rows) and
    // captures the header and the open menu.
    Timer {
        running: Qt.application.arguments.indexOf("--tab-dropdown-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=/tmp/act").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "tabdropdown-" + n + ".png"))
            const r2 = v => Math.round(v * 100) / 100
            if (st === 3) { console.warn("TABDROPDOWN header", r2(conversation.width), "narrow", conversation.narrowTitle, "shown", conversation.tabDropdownShownForTest(), "tabs", JSON.stringify(conversation.tabNames)); shot("header") }
            else if (st === 4) {
                const m = conversation.tabDropdownForTest()
                const rows = []
                const walk = it => { for (let i = 0; i < it.children.length; i++) { const c = it.children[i]; if (!c.visible) continue; if (c.modelData !== undefined && c.modelData && (c.modelData.label || c.modelData.separator)) { const q = c.mapToItem(m.contentItem, 0, 0); rows.push([c.modelData.separator ? "|" : c.modelData.label, r2(q.y), c.modelData.checked ? "checked" : "", c.modelData.split ? "split" : "", c.modelData.enabled === false ? "disabled" : ""]) } else walk(c) } }
                walk(m.contentItem)
                Qt.callLater(() => { const p = m.contentItem.mapToItem(null, 0, 0); console.warn("TABDROPDOWN menu", r2(p.x), r2(p.y), r2(m.width), r2(m.height), JSON.stringify(rows)) })
            }
            else if (st === 5) shot("menu")
            else if (st === 6) Qt.quit()
        }
    }
    // --work-location-test: Settings ▸ Privacy's Manage my work location
    // with the work-location detection policy (WORKLOC lines): the card,
    // its "Why set my work location automatically?" dialog, then Manage
    // stationary location and its building list. Pictures in /tmp/act.
    Timer {
        running: Qt.application.arguments.indexOf("--work-location-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/workloc-" + n + ".png"))
            if (st === 0) { rail.current = "settings"; settingsView.pageForTest("privacy") }
            else if (st === 2) { console.warn("WORKLOC card", settingsView.workLocationForTest("")); shot("card") }
            else if (st === 3) settingsView.workLocationForTest("dialog")
            else if (st === 4) shot("dialog")
            else if (st === 5) { settingsView.workLocationForTest("closeDialog"); settingsView.pageForTest("privacy", "stationary"); backend.loadBuildings() }
            else if (st === 7) { console.warn("WORKLOC stationary", backend.buildingsJson); shot("stationary") }
            else if (st === 8) settingsView.workLocationForTest("list")
            else if (st === 9) shot("list")
            // --work-location-off: turn the automatic work location off,
            // then read it back from the chat service.
            else if (st === 10 && Qt.application.arguments.indexOf("--work-location-off") >= 0) { settingsView.pageForTest("privacy"); settingsView.workLocationForTest("off") }
            else if (st === 13 && Qt.application.arguments.indexOf("--work-location-off") >= 0) backend.loadSettings()
            else if (st === 15 && Qt.application.arguments.indexOf("--work-location-off") >= 0) { console.warn("WORKLOC after off", JSON.stringify((JSON.parse(backend.settingsJson).props || {}).placesSettings), JSON.parse(settingsView.workLocationForTest("")).autoOn); shot("off") }
            else if (st > 9 && (st > 15 || Qt.application.arguments.indexOf("--work-location-off") < 0)) Qt.quit()
        }
    }
    // --everyone-test[=<chat>]: in a big group chat ("OST large chat test",
    // 54 people), type "@Everyone" as keys, log the picker, pick it with
    // Return and log and capture Teams' "# people will be notified" banner,
    // then clear compose. Pictures in /tmp/act.
    KeyTyper { id: everyoneTyper }
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--everyone-test")) && backend.signedIn
        interval: 1000; repeat: true
        property int step: 0
        property int waited: 0
        onTriggered: {
            const st = step++
            const arg = Qt.application.arguments.find(a => a.startsWith("--everyone-test="))
            const name = arg ? arg.split("=").slice(1).join("=") : "OST large chat test"
            const c = conversation.composeForTest()
            if (st === 0) { const ch = chatList.chats.find(x => x.name === name); console.warn("EVERYONE chat", ch ? ch.id : "missing"); if (!ch) { Qt.quit(); return } rail.current = "chat"; backend.selectChat(ch.id, ch.name) }
            else if (st >= 1 && st < 6) { if (c.memberCount > 0) { console.warn("EVERYONE roster after", st, "s"); step = 6 } else if (st === 5) step = 1 + (waited++ < 40 ? 0 : 5) }
            else if (st === 6) { console.warn("EVERYONE members", c.memberCount, "others", c.everyoneOthers, "allowed", c.everyoneAllowed); conversation.focusCompose(); everyoneTyper.typeText("@Everyone") }
            else if (st === 9) window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/everyone-picker.png"))
            else if (st === 10) { everyoneTyper.typeText("\n") }
            else if (st === 11) { console.warn("EVERYONE banner", JSON.stringify(c.bannerText), "danger", c.bannerDanger, "compose", c.formattedText()); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/everyone-banner.png")) }
            else if (st === 15) { console.warn("EVERYONE after 3 s", JSON.stringify(c.bannerText)); c.clear() }
            else if (st > 16) Qt.quit()
        }
    }
    // --room-audio-test: the pre-join screen with a connected room device
    // (Teams' BYOD Room audio): what it found and picked, the Room audio
    // card's geometry, then its room picker open; screenshots in /tmp/act.
    Timer {
        running: Qt.application.arguments.indexOf("--room-audio-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property bool roomShot: false
        onTriggered: {
            const st = step++
            const card = () => {
                const col = preJoin.contentItem.children
                const out = []
                const walk = it => { for (let i = 0; i < it.children.length; i++) { const c = it.children[i]; if (c.Accessible && (c.Accessible.role === Accessible.RadioButton) && c.visible) { const p = c.mapToItem(null, 0, 0); out.push([c.Accessible.name, Math.round(p.y * 10) / 10, Math.round(c.height * 10) / 10]) } walk(c) } }
                walk(preJoin.contentItem)
                return out
            }
            // --room-audio-test --manage-devices: Settings ▸ Devices ▸ Manage devices.
            if (Qt.application.arguments.indexOf("--manage-devices") >= 0) {
                if (st === 0) { rail.current = "settings"; settingsView.pageForTest("devices", "connected") }
                else if (st === 1) window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/manage-devices.png"))
                else Qt.quit()
                return
            }
            if (st === 0) { const a = Qt.application.arguments.find(x => x.startsWith("--room-audio-join=")); preJoin.openMeetNow(a ? a.split("=")[1] : "", "OST room audio test") }
            else if (st === 1) { console.warn("ROOMS", backend.roomDevices(), "audio", preJoin.audio, "room", JSON.stringify(preJoin.room), "canJoin", preJoin.canJoin, "mic", backend.setting("micDevice"), "speaker", backend.setting("speakerDevice")); console.warn("CARDS", JSON.stringify(card())); preJoin.contentItem.grabToImage(r => r.saveToFile("/tmp/act/room-prejoin.png")) }
            else if (st === 2) { preJoin.roomPickerForTest() }
            else if (st === 3) preJoin.contentItem.grabToImage(r => r.saveToFile("/tmp/act/room-picker.png"))
            else if (st === 4) { preJoin.room = null; console.warn("CLEARED canJoin", preJoin.canJoin); preJoin.contentItem.grabToImage(r => r.saveToFile("/tmp/act/room-none.png")) }
            else if (st === 5) { preJoin.audio = "computer"; console.warn("CARDS-COMPUTER", JSON.stringify(card())) }
            // --room-audio-test=join: join with the room device (muted), the
            // call's notice, then leave.
            else if (st === 6 && Qt.application.arguments.some(x => x.startsWith("--room-audio-join="))) { preJoin.pickRoom(preJoin.rooms.select); preJoin.close(); preJoin.join(false, true, false); interval = 4000 }
            else if (st >= 7 && st < 20 && Qt.application.arguments.some(x => x.startsWith("--room-audio-join="))) {
                console.warn("CALL", backend.callState, "roomJoined", callWindow.roomDeviceJoined, "notice body", callWindow.roomNoticeBody, "dismissed", callWindow.roomNoticeDismissed, "count", backend.setting("byodSdmUfdTriggerCount"), "screens", Qt.application.screens.length, "roomMode", callWindow.roomMode)
                if (backend.callState === "connected" && !roomShot) { roomShot = true; callWindow.contentItem.grabToImage(r => r.saveToFile("/tmp/act/room-call.png")) }
                else if (roomShot && backend.callState === "connected") backend.hangUp()
                else if (roomShot && backend.callState !== "connected") { console.warn("LEFT", backend.callState); step = 30 }
            }
            else if (st > 6) Qt.quit()
        }
    }
    Timer {
        running: Qt.application.arguments.indexOf("--about-test") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const st = step++
            if (st === 0) { rail.current = "settings"; settingsView.pageForTest("about"); backend.checkForUpdates() }
            else if (st === 2) { console.warn("ABOUT", backend.updateJson, JSON.stringify(settingsView.cardRowsForTest("Version"))); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/about-latest.png")) }
            else if (st === 3) backend.updateJson = JSON.stringify({ state: "available", checkedAt: Date.now(), latest: "0.2.0", url: "https://github.com/RandyNorthrup/ost/releases" })
            else if (st === 4) { console.warn("ABOUT", backend.updateJson); window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/about-update.png")) }
            else if (st > 5) Qt.quit()
        }
    }

    // --recognition-states: Settings ▸ Recognition in each of Teams'
    // states (set locally, nothing sent), as CARDS and CARDROWS lines.
    Timer {
        running: Qt.application.arguments.indexOf("--recognition-states") >= 0 && backend.signedIn
        interval: 1500; repeat: true
        property int step: 0
        readonly property var states: [
            { loaded: true },
            { loaded: true, passiveVoice: true },
            { loaded: true, voice: true },
            { loaded: true, voice: true, passiveVoice: true, face: true }]
        onTriggered: {
            const st = step++
            if (st === 0) { rail.current = "settings"; settingsView.pageForTest("recognition") }
            else if (st < 4) {}
            else if (st - 3 <= states.length * 2) {
                const k = st - 3
                const i = Math.floor((k - 1) / 2)
                if (k % 2 === 1) backend.recognitionJson = JSON.stringify(states[i])
                else {
                    console.warn("CARDS recognition-" + i, JSON.stringify(settingsView.cardsForTest()))
                    console.warn("CARDROWS voice-" + i, JSON.stringify(settingsView.cardRowsForTest("Voice Recognition")))
                    console.warn("CARDROWS face-" + i, JSON.stringify(settingsView.cardRowsForTest("Face Recognition")))
                    window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/recst-" + i + ".png"))
                }
            } else Qt.quit()
        }
    }

    // --recognition-test=<photo.jpg>,<voice.wav>: Settings ▸ Recognition,
    // then Teams' face capture fed that photo and the voice capture fed that
    // 16 kHz WAV, through to the completion step; pictures of each step and
    // CARDS lines. Enrolls those profiles (remove them afterwards).
    Timer {
        id: recognitionTest
        readonly property var files: (Qt.application.arguments.find(a => a.startsWith("--recognition-test=")) || "").slice(19).split(",")
        running: files[0] !== "" && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property int wait: 0
        function shot(n) { window.contentItem.grabToImage(r => r.saveToFile("/tmp/act/rec-" + n + ".png")) }
        onTriggered: {
            const face = settingsView.faceDialogForTest(), voice = settingsView.voiceDialogForTest()
            const st = step++
            if (st === 0) { rail.current = "settings"; settingsView.pageForTest("recognition") }
            else if (st === 2) { console.warn("CARDS recognition", JSON.stringify(settingsView.cardsForTest()), backend.recognitionJson); shot("page") }
            else if (st === 3) { face.testPhoto = files[0]; settingsView.startRecognition("face") }
            else if (st === 4) shot("face")
            else if (st === 5) { face.started = true; face.countdownForTest() }
            else if (st === 6) shot("face-count")
            else if (st >= 7 && st < 40 && !face.finished) { if (st % 4 === 0) console.warn("RECOG face", face.pose, face.error, face.learning) }
            else if (st >= 7 && st < 60 && face.finished && wait === 0) { wait = st; shot("face-done") }
            else if (wait && st === wait + 1) { face.close(); voice.testWav = files[1]; settingsView.startRecognition("voice") }
            else if (wait && st === wait + 2) shot("voice")
            else if (wait && st === wait + 3) voice.start()
            else if (wait && st === wait + 4) voice.end()
            else if (wait && st > wait + 4 && st < wait + 30 && !voice.finished) { if (st % 3 === 0) console.warn("RECOG voice", voice.phase, voice.errorCode) }
            else if (wait && voice.finished && st < wait + 40) { shot("voice-done"); voice.close(); backend.loadRecognition(); step = 200 }
            else if (st === 202) { console.warn("CARDS recognition-after", JSON.stringify(settingsView.cardsForTest()), backend.recognitionJson); shot("page-after") }
            else if (st >= 204 || st === 60) Qt.quit()
        }
    }

    // --notif-banner-live-test: the first real chat banner is answered from the
    // banner: BANNER-LIVE logs it, 4 s later it reacts with a heart and
    // sends a quick reply naming --notif-banner-live-test=<text>.
    Connections {
        target: backend
        enabled: Qt.application.arguments.some(a => a.startsWith("--notif-banner-live-test"))
        property bool done: false
        function onBannerRequested(json) {
            const t = JSON.parse(json)
            console.warn("BANNER-LIVE", json)
            if (done || t.kind !== "standard" || !t.quickReply) return
            done = true
            liveBannerTimer.chat = t.chatId
            liveBannerTimer.message = t.messageId
            liveBannerTimer.banner = t.id
            liveBannerTimer.start()
        }
    }
    Timer {
        id: liveBannerTimer
        property string chat
        property string message
        property string banner
        interval: 4000
        onTriggered: {
            const text = (Qt.application.arguments.find(a => a.startsWith("--notif-banner-live-test=")) || "").slice(25) || "OST quick reply"
            backend.bannerReact(chat, message, "heart")
            backend.bannerReply(chat, text)
            banners.dismiss(banner)
            console.warn("BANNER-LIVE answered", chat, message)
        }
    }

    // --notif-banner-test: Teams' notification banners, step by step every 3 s
    // (photograph the screen at each BANNERS line): an incoming call, a
    // chat message with its quick reply, an @mention and a meeting that started
    // (BR, Comfy); then the same Compact in the top left, then the top
    // right. BANNERS lines give each card's place in the window. Puts the
    // position and size settings back as they were.
    Timer {
        id: bannerTest
        running: Qt.application.arguments.some(a => a === "--notif-banner-test" || a === "--notif-banner-test=hold")
        interval: 3000; repeat: true
        property int step: 0
        property string corner0
        property string size0
        function fill() {
            banners.add({ id: "call", kind: "call", title: "OST Test 2", senderMri: "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5", silent: true })
            banners.add({ id: "t1", kind: "standard", title: "OST Test 2", text: "Here is a longer message that needs two lines to show all of it in the banner, and then some more", chatId: "19:x@unq.gbl.spaces", messageId: "1", senderMri: "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5", senderName: "OST Test 2", quickReply: true, seconds: 300, silent: true })
            banners.add({ id: "t2", kind: "msn", title: "OST group test", text: "OST Test 2 started a meeting", chatId: "19:y@thread.v2", senderMri: "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5", senderName: "OST Test 2", seconds: 300, silent: true, actions: [{ id: "join", label: "Join" }, { id: "message", label: "Message" }] })
        }
        function report(tag) {
            const cards = []
            for (let i = 0; i < banners.contentItem.children.length; i++) {
                const col = banners.contentItem.children[i]
                for (let j = 0; j < (col.children ? col.children.length : 0); j++) {
                    const c = col.children[j]
                    if (c.toast) cards.push([c.toast.id, Math.round(c.mapToItem(banners.contentItem, 0, 0).x * 10) / 10, Math.round(c.mapToItem(banners.contentItem, 0, 0).y * 10) / 10, c.width, c.height])
                }
            }
            console.warn("BANNERS", tag, banners.corner, banners.compact, banners.width, banners.height, JSON.stringify(cards))
            banners.contentItem.grabToImage(r => r.saveToFile("/tmp/act/banner-" + tag + ".png"))
        }
        onTriggered: {
            const st = step++
            const clear = () => { for (const id of Object.keys(banners.toasts)) banners.dismiss(id) }
            // --notif-banner-test=hold: show them (BR, Comfy) and report every
            // 3 s for 45 s, for clicking at them.
            if (Qt.application.arguments.indexOf("--notif-banner-test=hold") >= 0 && st > 0) {
                if (st < 16) { report("hold-" + st); return }
                clear(); backend.setSetting("notificationCorner", corner0); backend.setSetting("notificationSize", size0); Qt.quit(); return
            }
            if (st === 0) {
                corner0 = backend.setting("notificationCorner"); size0 = backend.setting("notificationSize")
                backend.setSetting("notificationCorner", "BR"); backend.setSetting("notificationSize", "COMFY")
                fill()
            } else if (st === 1) report("br-comfy")
            else if (st === 2) banners.add({ id: "t3", kind: "standard", title: "OST Test 2 @mentioned you", subtitle: "OST group test", text: "@OST Test 1 have a look", urgent: true, chatId: "19:y@thread.v2", messageId: "2", senderMri: "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5", senderName: "OST Test 2", seconds: 300, silent: true })
            else if (st === 3) report("br-comfy-3")
            else if (st === 4) { clear(); backend.setSetting("notificationCorner", "TL"); backend.setSetting("notificationSize", "COMPACT"); fill() }
            else if (st === 5) report("tl-compact")
            else if (st === 6) { clear(); backend.setSetting("notificationCorner", "BL"); fill() }
            else if (st === 7) report("bl-compact")
            else if (st === 8) { clear(); backend.setSetting("notificationCorner", "TR"); backend.setSetting("notificationSize", "COMFY"); fill() }
            else if (st === 9) report("tr-comfy")
            else if (st === 10) { clear(); backend.setSetting("notificationCorner", corner0); backend.setSetting("notificationSize", size0) }
            else Qt.quit()
        }
    }

    // --cards-test: every Settings page's cards as CARDS lines (geometry
    // compared with Teams'). Changes nothing.
    Timer {
        running: Qt.application.arguments.some(a => a === "--cards-test" || a.startsWith("--cards-test=")) && backend.signedIn && backend.orgName.length > 0
        interval: 1500; repeat: true
        property int step: 0
        readonly property var keys: settingsView.pages.map(p => p.key).concat(["about"])
        onTriggered: {
            const i = Math.floor(step / 2)
            if (i >= keys.length) {
                // General again, its Editor card once its options load.
                if (step === 2 * keys.length) settingsView.pageForTest("general")
                else if (step === 2 * keys.length + 6) { console.warn("CARDS general-late", JSON.stringify(settingsView.cardsForTest())); settingsView.scrollToForTest(1700); }
                else if (step === 2 * keys.length + 7) window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-editor.png")))
                else if (step > 2 * keys.length + 8) { Qt.quit(); return }
                step++; return
            }
            if (step % 2 === 0) { rail.current = "settings"; settingsView.pageForTest(keys[i]) }
            else {
                console.warn("CARDS", keys[i], JSON.stringify(settingsView.cardsForTest()))
                // --cards-test=<title>: that card's rows too.
                const rows = (Qt.application.arguments.find(a => a.startsWith("--cards-test=")) || "").slice(13)
                if (rows) console.warn("CARDROWS", keys[i], JSON.stringify(settingsView.cardRowsForTest(rows)))
            }
            step++
        }
    }

    // --test-call-test: Settings ▸ Devices ▸ Make a test call (TASK-0141):
    // the Devices page, Teams' test call in the call window (the Echo
    // bot's prompt, your recording played back), then the results screen,
    // its Device settings pane and Close. Leaves the call itself after
    // 120 s if the bot hasn't ended it. Logs TESTCALL lines; pictures
    // -devices, -call, -report, -report-devices.
    Timer {
        running: Qt.application.arguments.indexOf("--test-call-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        property int ended: -1
        function shot(n) { window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png"))) }
        function callShot(n) { callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png"))) }
        onTriggered: {
            console.warn("TESTCALL", step, "state", backend.callState, "test", backend.callTest, "muted", backend.callMuted, "camera", backend.callCameraOn, "report", backend.callTestReport)
            if (step === 0) { rail.current = "settings"; settingsView.pageForTest("devices") }
            else if (step === 1) shot("devices")
            else if (step === 2) backend.makeTestCall()
            else if (step === 10) callShot("call")
            else if (step === 60 && backend.callState !== "ended" && backend.callState !== "") { console.warn("TESTCALL leaving"); backend.hangUp() }
            if (step > 2 && ended < 0 && backend.callState === "ended") ended = step
            if (ended >= 0) {
                if (step === ended + 1) callShot("report")
                else if (step === ended + 2) callWindow.testReportForTest().showDevices = true
                else if (step === ended + 3) callShot("report-devices")
                else if (step === ended + 4) { callWindow.testReportForTest().closed(); }
                else if (step === ended + 5) { console.warn("TESTCALL closed, state", JSON.stringify(backend.callState), "window", callWindow.visible); Qt.quit(); return }
            }
            if (step > 90) { console.warn("TESTCALL gave up"); Qt.quit(); return }
            step++
        }
    }

    // --calls-test: Settings ▸ Calls (captured top and lower), the greeting
    // language list and the custom greeting dialog (nothing saved).
    Timer {
        running: Qt.application.arguments.indexOf("--calls-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        function shot(n) { window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png"))) }
        onTriggered: {
            if (step === 0) { rail.current = "settings"; settingsView.pageForTest("calls") }
            else if (step === 1) shot("calls-top")
            else if (step === 2) settingsView.scrollToForTest(330)
            else if (step === 3) shot("calls-lower")
            else if (step === 4) settingsView.scrollForTest()
            else if (step === 5) shot("calls-bottom")
            else if (step === 6) { const d = settingsView.greetingDialogForTest(); d.oof = false; d.show("") }
            else if (step === 7) shot("greeting")
            else if (step === 8) { settingsView.greetingDialogForTest().close(); settingsView.pageForTest("accessibility") }
            else if (step === 9) { shot("accessibility"); }
            else if (step === 10) settingsView.pageForTest("about")
            else if (step === 11) { shot("about"); console.warn("CALLS notices", backend.thirdPartyNoticesUrl()) }
            else { Qt.quit(); return }
            step++
        }
    }

    // --privacy-test: Settings ▸ Privacy and its Manage priority access /
    // Manage blocked people pages; adds OST Test 2 to priority access, then
    // removes them again. Logs PRIVACY lines.
    Timer {
        running: Qt.application.arguments.indexOf("--privacy-test") >= 0 && backend.signedIn && backend.orgName.length > 0
        interval: 3000; repeat: true
        property int step: 0
        readonly property string test2: "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5"
        function shot(n) { window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png"))) }
        onTriggered: {
            if (step === 0) { rail.current = "settings"; settingsView.pageForTest("privacy") }
            else if (step === 1) shot("privacy")
            else if (step === 2) settingsView.pageForTest("privacy", "priority")
            else if (step === 3) { shot("priority-empty"); backend.channelAction("people-list-add", "", "", JSON.stringify({ list: "priority", mri: test2 })) }
            else if (step === 4) { console.warn("PRIVACY after add", backend.channelActionResult) }
            else if (step === 5) { shot("priority-one"); backend.channelAction("people-list-remove", "", "", JSON.stringify({ list: "priority", mri: test2 })) }
            else if (step === 6) { console.warn("PRIVACY after remove", backend.channelActionResult); settingsView.pageForTest("privacy", "blocked") }
            else if (step === 7) shot("blocked")
            else if (step === 8) settingsView.pageForTest("privacy")
            else if (step === 9) shot("privacy-top")
            else if (step === 10) settingsView.scrollForTest()
            else if (step === 11) shot("privacy-lower")
            // Optional connected experiences off: the fun picker without GIPHY.
            else if (step === 12) { backend.changeSetting("prop", "controllerConnectedServicesEnabled", JSON.stringify("false")); const c = chatList.chats.find(c => c.name === "OST group test"); rail.current = "chat"; backend.selectChat(c.id, c.name) }
            else if (step === 14) conversation.openEmojiForTest()
            else if (step === 15) { console.warn("PRIVACY gifsOn", conversation.funPickerForTest().gifsOn); shot("fun-no-gifs") }
            else if (step === 16) { conversation.funPickerForTest().close(); backend.changeSetting("prop", "controllerConnectedServicesEnabled", JSON.stringify("true")) }
            else if (step === 17) console.warn("PRIVACY gifsOn after", conversation.funPickerForTest().gifsOn)
            else if (step > 17) { Qt.quit(); return }
            step++
        }
    }

    // --e2ee-setting-test[=on|off]: Settings ▸ Privacy's End-to-end
    // encrypted calls card: logs E2EE lines (your choice and whether the
    // tenant allows it) and captures it (`-e2ee-card.png`); `=on` / `=off`
    // saves that choice (where Teams keeps it), reloads the settings and
    // logs what the service now holds (`-e2ee-card-saved.png`).
    Timer {
        readonly property string arg: (Qt.application.arguments.find(a => a.startsWith("--e2ee-setting-test")) || "")
        running: arg.length > 0 && backend.signedIn && backend.orgName.length > 0
        interval: 3000; repeat: true
        property int step: 0
        readonly property string want: arg.indexOf("=") > 0 ? arg.split("=")[1] : ""
        function shot(n) { window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + n + ".png"))) }
        function state() { const mt = settingsView.mt; return "on " + (mt.useEndToEndEncryption === true) + " allowed " + (mt.e2eeAllowedByAdmin === true) }
        onTriggered: {
            if (step === 0) { rail.current = "settings"; settingsView.pageForTest("privacy") }
            else if (step === 1) settingsView.scrollForTest()
            else if (step === 2) { console.warn("E2EE card", state()); shot("e2ee-card") }
            else if (step === 3) { if (want === "on" || want === "off") backend.changeSetting("mt", "useEndToEndEncryption", JSON.stringify(want === "on")); else { Qt.quit(); return } }
            else if (step === 5) backend.loadSettings()
            else if (step === 7) { console.warn("E2EE saved", state(), "wanted", want); shot("e2ee-card-saved") }
            else if (step > 7) { Qt.quit(); return }
            step++
        }
    }

    // --accounts-test: Settings ▸ Accounts and orgs (captured; nothing
    // pressed). Logs ACCOUNTS lines.
    Timer {
        running: Qt.application.arguments.indexOf("--accounts-test") >= 0 && backend.signedIn && backend.orgName.length > 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            if (step === 0) { rail.current = "settings"; settingsView.pageForTest("accounts") }
            else if (step === 1) { console.warn("ACCOUNTS", backend.userName, backend.userMail, backend.orgName); window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-accounts.png"))) }
            else { Qt.quit(); return }
            step++
        }
    }

    // --notif-test: Settings ▸ Notifications and activity's Posts in all
    // shown channels, meeting chat, Calendar and Presence rows; the Calendar
    // invites choice changed and put back; Manage status notifications.
    // Logs NOTIF lines.
    Timer {
        running: Qt.application.arguments.indexOf("--notif-test") >= 0 && backend.signedIn && backend.settingsJson.length > 0
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const log = (...a) => console.warn("NOTIF", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const props = () => JSON.parse(backend.settingsJson).props || {}
            const cal = () => { const g = props().userGraphSettings || {}; const a = g["ef56c0de-36fc-4ef8-b417-3d82ba9d073c"] || {}; return [(a.toastSettings || {}).privateMeetingCreated, (a.activityGenerationSettings || {}).privateMeetingCreated] }
            switch (step) {
            case 0: rail.current = "settings"; settingsView.pageForTest("notifications"); break
            case 1: { const u = props().userPersonalSettings || {}; log("chat", u.chatSettings, "posts", (u.activityGenerationSettings || {}).Visible_ChannelNewMessage_v2, "calendar", cal()); settingsView.scrollForTest(); break }
            case 2: cap("bottom"); backend.changeSetting("prop", "userGraphSettings", JSON.stringify({ "ef56c0de-36fc-4ef8-b417-3d82ba9d073c": { toastSettings: { privateMeetingCreated: true } } })); break
            case 4: backend.loadSettings(); break
            case 6: log("calendar after", cal()); backend.changeSetting("prop", "userGraphSettings", JSON.stringify({ "ef56c0de-36fc-4ef8-b417-3d82ba9d073c": { toastSettings: { privateMeetingCreated: false } } })); break
            case 8: backend.loadSettings(); settingsView.pageForTest("notifications", "status"); break
            case 10: log("calendar restored", cal()); cap("status"); break
            case 11: Qt.quit(); return
            }
            step++
        }
    }

    // --collab-test: Settings ▸ Chats and channels' "Viewing chats, teams,
    // and channels", then Separate: Chat's list, the Teams app's, a channel
    // opened from it; back to Combined. Logs COLLAB lines.
    Timer {
        running: Qt.application.arguments.indexOf("--collab-test") >= 0 && backend.signedIn && chatList.chats.length > 2
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const log = (...a) => console.warn("COLLAB", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const set = unified => backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ hasUserEnabledAdaptiveRailForDesktop: true, hasUserEnabledUnifiedAppForDesktop: unified }))
            switch (step) {
            case 0: rail.current = "settings"; settingsView.pageForTest("chats"); break
            case 1: cap("settings"); set(false); break
            case 3: log("split", window.splitView); window.openCollab("chats"); break
            case 4: log("chat pane", chatList.pane, chatList.pillDefs.map(p => p.label), chatList.sections.map(s => s.folder.kind)); cap("chats"); break
            case 5: window.openCollab("teams"); break
            case 6: log("teams pane", chatList.pane, chatList.pillDefs.map(p => p.label), chatList.sections.map(s => s.folder.kind)); cap("teams"); break
            case 7: { const t = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).find(t => (t.channels || []).length); const ch = t.channels[0]; window.openCollab("chats"); backend.selectChat(ch.id, ch.name); break }
            case 9: log("after channel", window.collabPane); cap("channel"); break
            case 10: set(true); break
            case 12: log("restored split", window.splitView, chatList.pane); Qt.quit(); return
            }
            step++
        }
    }

    // --appearance-test: Settings ▸ Appearance (Theme with "Always use dark
    // theme for calls and meetings", App bar), then app names in the rail,
    // auto collapse after picking an app, and a dark pre-join (Meet now,
    // never joined) in the Light theme. Settings are put back. Logs
    // APPEARANCE lines.
    Timer {
        running: Qt.application.arguments.indexOf("--appearance-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        property var before: null
        onTriggered: {
            const log = (...a) => console.warn("APPEARANCE", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = (tag, w) => (w || window).contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            switch (step) {
            case 0: before = [window.appBarNames, window.appBarAutoCollapse, window.darkCallSetting]; rail.current = "settings"; settingsView.pageForTest("appearance"); break
            case 2: cap("settings"); break
            case 3: window.appBarNames = true; rail.current = "chat"; break
            case 4: cap("names"); window.appBarAutoCollapse = true; break
            case 5: rail.pick("calendar"); break
            case 6: log("collapsed after pick", rail.collapsed); cap("collapsed"); rail.collapsed = false; rail.current = "chat"; window.appBarAutoCollapse = false; window.appBarNames = false; break
            case 7: window.darkCallSetting = true; log("light", !theme.dark, "callsDark", window.callsDark); preJoin.openMeetNow("", "OST appearance test"); break
            case 10: cap("prejoin-dark", preJoin); break
            case 11: preJoin.cancel(); window.appBarNames = before[0]; window.appBarAutoCollapse = before[1]; window.darkCallSetting = before[2]; before.push(backend.themeMode); backend.setSetting("theme", "classic"); break
            case 13: log("classic", theme.classic, String(theme.titleBar)); cap("classic"); break
            case 14: backend.setSetting("theme", before[3]); log("restored", before); break
            case 15: Qt.quit(); return
            }
            step++
        }
    }

    // --editor-test: Teams' Editor in the compose box of "OST group test"
    // (never sent): misspellings squiggled, the card on the first, its first
    // suggestion applied, Ignore all on another; the box is cleared. Logs
    // EDITOR lines.
    Timer {
        running: Qt.application.arguments.indexOf("--editor-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2000; repeat: true
        property int step: 0
        property string before: ""
        onTriggered: {
            const log = (...a) => console.warn("EDITOR", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const c = conversation.composeForTest()
            const words = () => c.critiques.map(x => x.word + "@" + x.start + "→" + x.suggestions.slice(0, 3).join("/"))
            switch (step) {
            case 0: { const g = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(g.id, g.name); break }
            case 2: c.setPlain("Thsi is a tset of teh speling"); break
            case 6: log("critiques", words()); cap("squiggles"); break
            case 7: c.critiqueCardForTest(0); break
            case 8: cap("card"); break
            case 9: { const cr = c.critiques[0]; c.closeCardForTest(); c.applySuggestion(cr, cr.suggestions[0]); break }
            case 12: log("fixed", c.plainText(), words()); cap("fixed"); break
            case 13: { const t = c.critiques.find(x => x.word === "teh"); if (t) backend.editorIgnoreWord(t.word); break }
            case 14: log("ignored teh", words()); break
            case 15: c.setPlain(""); break
            case 16: log("cleared", JSON.stringify(c.plainText())); before = backend.setting("editorCritiques"); showEditorSettings(true); break
            case 18: cap("manage-empty"); backend.editorSetLanguages('["en-us"]'); break
            case 21: log("settings", JSON.parse(backend.editorSettingsJson()).languages); cap("manage"); break
            case 22: showEditorSettings(false); break
            case 25: log("options", backend.editorCategoriesJson("en-us").slice(0, 200)); cap("options"); break
            case 26: backend.setSetting("editorCritiques", JSON.stringify({ "en-us": { "d1cf9ade-e82a-45aa-98b8-9ee16a0dc132": "0", "19a112ec-21fd-432a-9d1f-195e5e94a00b": "1" } })); break
            case 27: cap("options-changed"); break
            case 28: backend.setSetting("editorCritiques", before); backend.editorSetLanguages("[]"); break
            case 31: log("restored", JSON.parse(backend.editorSettingsJson()).languages, backend.setting("editorCritiques")); Qt.quit(); return
            }
            step++
        }
    }

    // --regional-test: Settings ▸ General's Language and regional formats:
    // Follow OS on, then off with English (United Kingdom), yyyy-MM-dd and
    // 01:01 - 23:59 chosen, then Save and restart; after the restart the
    // formats are in effect (chat list and a chat captured), then your
    // settings are put back. Logs REGIONAL lines.
    Timer {
        running: Qt.application.arguments.indexOf("--regional-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST Test 2")
        interval: 2500; repeat: true
        property int step: 0
        readonly property bool restarted: backend.setting("regionalTest") !== ""
        onTriggered: {
            const log = (...a) => console.warn("REGIONAL", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const keys = ["regionalFollowOs", "appLanguage", "regionalDateFormat", "regionalTimeFormat"]
            const card = () => settingsView.regionalForTest()
            if (!restarted) {
                switch (step) {
                case 0: log("in effect", theme.regional); rail.current = "settings"; settingsView.pageForTest("general"); break
                case 2: settingsView.scrollToRegionalForTest(); break
                case 3: cap("follow"); break
                case 4: card().followOs = false; break
                case 5: cap("off"); break
                case 6: card().appLanguage = "en-gb"; card().dateFormat = "yyyy-MM-dd"; card().timeFormat = "hh:mm tt"; break
                case 7: log("chosen", card().appLanguage, card().dateFormat, card().timeFormat, "changed", card().changed); cap("chosen"); break
                case 8: backend.setSetting("regionalTest", JSON.stringify(keys.map(k => backend.setting(k)))); card().followOs = false; backend.saveRegionalAndRestart(false, "en-gb", "yyyy-MM-dd", "hh:mm tt"); return
                }
            } else {
                switch (step) {
                case 0: log("after restart", theme.regional, "now", theme.dateTime(new Date()), theme.dateMaybeYear(new Date(2025, 2, 4)), theme.time(new Date(2026, 0, 31, 16, 9))); break
                case 1: { const c = chatList.chats.find(c => c.name === "OST Test 2"); backend.selectChat(c.id, c.name); break }
                case 3: cap("after-chat"); break
                case 4: rail.current = "settings"; settingsView.pageForTest("general"); break
                case 5: settingsView.scrollToRegionalForTest(); break
                case 6: cap("after-settings"); break
                case 7: { const before = JSON.parse(backend.setting("regionalTest")); keys.forEach((k, i) => backend.setSetting(k, before[i])); backend.setSetting("regionalTest", ""); log("restored", keys.map(k => backend.setting(k))); break }
                case 8: Qt.quit(); return
                }
            }
            step++
        }
    }

    // --translation-test: Settings ▸ General's Translation card, then the
    // chat with OST Test 2 (German OST TEST 139): Ask me shows "Translate |
    // Never translate German"; Never translate German hides it and adds the
    // chip; Auto-translate translates it by itself and See original brings
    // the suggestion back. Your settings are put back. Logs TRANSLATION lines.
    Timer {
        running: Qt.application.arguments.indexOf("--translation-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST Test 2")
        interval: 2500; repeat: true
        property int step: 0
        property var before: null
        onTriggered: {
            const log = (...a) => console.warn("TRANSLATION", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const msg = () => (backend.messagesJson ? JSON.parse(backend.messagesJson) : []).find(m => (m.text || "").indexOf("OST TEST 139") >= 0 || m.id === "1794701380280")
            const show = m => m ? { text: (m.text || "").slice(0, 60), suggest: m.suggest_translation, name: m.suggest_translation_name, translated: m.translated, from: m.translated_from } : null
            switch (step) {
            case 0: before = ["translationTarget", "translationMode", "translationKnown"].map(k => backend.setting(k)); ["translationTarget", "translationMode", "translationKnown"].forEach(k => backend.setSetting(k, "")); rail.current = "settings"; settingsView.pageForTest("general"); break
            case 2: settingsView.scrollToTranslationForTest(); log("settings", backend.translationSettingsJson(), "languages", JSON.parse(backend.translationLanguagesJson()).length); break
            case 3: cap("settings"); settingsView.openTranslationTargetForTest(true); break
            case 4: cap("languages"); break
            case 5: { settingsView.openTranslationTargetForTest(false); rail.current = "chat"; const c = chatList.chats.find(c => c.name === "OST Test 2"); backend.selectChat(c.id, c.name); break }
            case 6: log("ask", show(msg())); cap("ask"); break
            case 7: conversation.neverTranslate(msg().suggest_translation); break
            case 8: log("never", backend.translationSettingsJson(), show(msg())); cap("never"); break
            case 9: rail.current = "settings"; settingsView.pageForTest("general"); break
            case 10: settingsView.scrollToTranslationForTest(); break
            case 11: log("languages", JSON.parse(backend.translationLanguagesJson()).slice(0, 3)); cap("chips"); backend.setSetting("translationKnown", ""); backend.setSetting("translationMode", "ALWAYS_TRANSLATE"); break
            case 12: rail.current = "chat"; break
            case 15: log("auto", show(msg())); cap("auto"); break
            case 16: backend.translateMessage(msg().id, false); break
            case 17: log("original", show(msg())); cap("original"); break
            case 18: ["translationTarget", "translationMode", "translationKnown"].forEach((k, i) => backend.setSetting(k, before[i])); log("restored", backend.translationSettingsJson()); break
            case 19: Qt.quit(); return
            }
            step++
        }
    }

    // --leave-confirm-test: Settings ▸ General's Meeting and Time zone
    // cards, then "Ask me to confirm when I leave a meeting" on in a Meet
    // now in "OST group test": Leave asks (captured), then the call is
    // left; the setting is put back. Logs LEAVE lines.
    Timer {
        running: Qt.application.arguments.indexOf("--leave-confirm-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2500; repeat: true
        property int step: 0
        property string before: ""
        onTriggered: {
            const log = (...a) => console.warn("LEAVE", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            switch (step) {
            case 0: before = backend.setting("leaveConfirmation"); backend.setSetting("leaveConfirmation", "true"); rail.current = "settings"; settingsView.pageForTest("general"); break
            case 1: settingsView.scrollForTest(); break
            case 2: window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-general.png"))); break
            case 3: { rail.current = "chat"; const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name); break }
            case 4: backend.meetNow(); break
            case 9: log("call", backend.callState, "meeting", callWindow.meeting); callWindow.leaveAsked(); break
            case 10: callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-ask.png"))); log("still in call", backend.callState); break
            case 11: callWindow.leave(); break
            case 13: log("after", backend.callState); backend.setSetting("leaveConfirmation", before); break
            case 14: Qt.quit(); return
            }
            step++
        }
    }

    // --green-screen-test: Settings ▸ Devices' Video settings with the
    // camera on: Green Screen on (the detected colour, then a picked one),
    // with a background; then everything back. Logs GREEN lines.
    Timer {
        running: Qt.application.arguments.indexOf("--green-screen-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        property var before: null
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("GREEN", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const fx = videoEffects
            switch (step) {
            case 0: before = { gs: fx.greenScreen, c: fx.greenScreenColor, b: fx.background }; fx.setGreenScreen(false); fx.setGreenScreenColor(""); window.showGreenScreenSettings(); break
            case 3: cap("devices"); break
            case 4: fx.setBackground("blur"); fx.setGreenScreen(true); settingsView.pageForTest("devices"); break
            case 7: log("detected", fx.detectedColor); cap("green-detected"); break
            case 8: fx.setGreenScreenColor(backend.previewColorAt(0.05, 0.5)); log("picked", fx.greenScreenColor); break
            case 10: cap("green-picked"); break
            case 11: fx.setGreenScreen(before.gs); fx.setGreenScreenColor(before.c); fx.setBackground(before.b); rail.current = "chat"; break
            case 13: log("done"); Qt.quit(); return
            }
            step++
        }
    }

    // --video-filters-test: Teams' Filters (its Custom Filters app, hosted
    // by VideoFilterHost) in a Meet now's pre-join (never joined): the
    // camera on, the Sweet style, then the Crystal frame, then None. Logs
    // VFILTER lines.
    Timer {
        running: Qt.application.arguments.indexOf("--video-filters-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        property string before: ""
        onTriggered: {
            const cap = tag => preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("VFILTER", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const fx = videoEffects
            const pick = name => (fx.filters.filters || []).find(f => f.name === name)
            switch (step) {
            case 0: before = fx.filter; fx.setFilter(""); fx.setBackground("none"); preJoin.openMeetNow("", "OST filters test"); break
            case 1: preJoin.cameraOn = true; preJoin.effectsOpen = true; fx.load(); break
            case 3: log("filters", (fx.filters.filters || []).length, fx.filters.url, fx.quickFilters.map(f => f.name)); cap("none"); break
            case 4: fx.setFilter(pick("Sweet").id); break
            case 9: videoFilterHost.probe(3); break
            case 12: log("host ready", videoFilterHost.ready); cap("sweet"); break
            case 13: fx.setFilter(pick("Crystal").id); break
            case 17: log("host ready", videoFilterHost.ready); cap("crystal"); break
            case 18: preJoin.effectsPaneOpen = true; break
            case 19: cap("pane"); break
            case 20: preJoin.effectsPaneOpen = false; fx.setFilter(""); break
            case 21: cap("nofilter"); break
            case 22: preJoin.cameraOn = false; preJoin.cancel(); fx.setFilter(before); break
            case 23: log("done"); Qt.quit(); return
            }
            step++
        }
    }

    // --video-effects-test: Teams' video effects on the camera. Before
    // joining (a Meet now's pre-join, never joined): the camera on, the
    // effects picker with None, Standard blur, Portrait blur, a catalog
    // picture and an animated background, Adjust brightness and Soft focus,
    // then the "More video effects" pane. With --video-effects-call it then
    // starts a Meet now in "OST group test" with the camera on, opens
    // Camera ▾ and the Video effects and settings pane (both tabs), adds
    // /tmp/ost-bg-test.jpg with Add new (and the too small
    // /tmp/ost-bg-small.png), opens Show all, removes the upload and
    // hangs up (--video-effects-hold: after two minutes with a catalog
    // picture behind you). The effects are put back as they were. Logs VFX
    // lines.
    Timer {
        running: Qt.application.arguments.indexOf("--video-effects-test") >= 0 && backend.signedIn && chatList.chats.some(c => c.name === "OST group test")
        interval: 2000; repeat: true
        property int step: 0
        property int holdSteps: 0
        property var before: null
        onTriggered: {
            const capPre = tag => preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const capCall = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-" + tag + ".png")))
            const log = (...a) => console.warn("VFX", ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const fx = videoEffects
            const pic = () => fx.catalog.find(e => !e.animated)
            const anim = () => fx.catalog.find(e => e.animated)
            const inCall = Qt.application.arguments.indexOf("--video-effects-call") >= 0
            // --video-effects-hold: stay two minutes in the call with a
            // catalog picture behind you (to watch from another client).
            const hold = Qt.application.arguments.indexOf("--video-effects-hold") >= 0
            switch (step) {
            case 0: before = { b: fx.background, k: fx.blurKind, br: fx.brightness, sf: fx.softFocus, m: fx.mirror }; log("before", before); fx.setBackground("none"); fx.setBrightness(false); fx.setSoftFocus(false); preJoin.openMeetNow("", "OST effects test"); break
            case 1: preJoin.cameraOn = true; preJoin.effectsOpen = true; fx.load(); break
            case 3: log("catalog", fx.catalog.length, fx.catalog.slice(0, 2)); capPre("none"); break
            case 4: fx.setBackground("blur"); break
            case 6: capPre("blur"); break
            case 7: fx.setBlur("portrait"); break
            case 9: capPre("portrait"); break
            case 10: fx.setBlur("standard"); fx.setBackground(pic().id); log("picture", pic().name); break
            case 14: capPre("picture"); break
            case 15: fx.setBackground(anim().id); log("animated", anim().name); break
            case 19: capPre("animated"); break
            case 20: capPre("animated2"); break
            case 21: fx.setBackground("none"); fx.setBrightness(true); break
            case 23: capPre("brightness"); break
            case 24: fx.setBrightness(false); fx.setSoftFocus(true); break
            case 26: capPre("softfocus"); break
            case 27: fx.setSoftFocus(false); fx.setBackground("blur"); preJoin.effectsPaneOpen = true; break
            case 29: capPre("pane"); break
            case 30: preJoin.effectsPaneOpen = false; preJoin.cameraOn = false; break
            case 31: capPre("cameraoff"); break
            case 32: preJoin.cancel(); if (!inCall) step = 61; break
            case 33: { const c = chatList.chats.find(c => c.name === "OST group test"); backend.selectChat(c.id, c.name); break }
            case 34: backend.meetNow(); break
            case 40: log("call", backend.callState); if (!callWindow.cameraOn) callWindow.runControl("VideoButton"); break
            case 43: callWindow.videoOptionsForTest(); break
            case 45: capCall("flyout"); break
            case 46: callWindow.videoFlyoutForTest().close(); callWindow.side = "video"; break
            case 48: capCall("callpane"); break
            case 49: callWindow.videoEffectsPaneForTest().tab = "settings"; break
            case 50: capCall("settings"); break
            case 51: { const pane = callWindow.videoEffectsPaneForTest(); pane.tab = "effects"; log("add", pane.addForTest("/tmp/ost-bg-test.jpg"), fx.background) } break
            case 52: capCall("added"); break
            case 53: callWindow.videoOptionsForTest(); break
            case 54: capCall("uploadflyout"); break
            case 55: callWindow.videoFlyoutForTest().close(); log("upload too small", callWindow.videoEffectsPaneForTest().addForTest("/tmp/ost-bg-small.png")); break
            case 56: capCall("toosmall"); break
            case 57: callWindow.videoEffectsPaneForTest().showAll = true; break
            case 58: capCall("showall"); break
            case 59: { const u = fx.uploads[fx.uploads.length - 1]; log("uploads", fx.uploads.length); callWindow.videoEffectsPaneForTest().notice = fx.removeUpload(u.id) } break
            case 60: capCall("removed"); log("after remove", fx.uploads.length, fx.background); if (hold) { callWindow.side = ""; fx.setBackground(pic().id); log("holding with", pic().name) } break
            case 61: if (hold && holdSteps++ < 60) return; if (inCall) backend.hangUp(); break
            case 62: fx.setBlur(before.k); fx.setBackground(before.b); fx.setBrightness(before.br); fx.setSoftFocus(before.sf); fx.setMirror(before.m); break
            case 64: log("after", backend.callState, { b: fx.background, k: fx.blurKind }); Qt.quit(); return
            }
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
            else if (step === 7 && Qt.application.arguments.indexOf("--meet-unmute") >= 0 && backend.callMuted) backend.toggleMute()
            else if (step >= 9 && step <= 21) console.warn("MEETNOW media muted", backend.callMuted, "camera", backend.callCameraOn, "sharing", backend.callSharing)
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
            // --webapp-stay: keep the views open (to inspect them with
            // QTWEBENGINE_REMOTE_DEBUGGING).
            else if (step === 8) { console.warn("WEBAPP second view open"); if (Qt.application.arguments.indexOf("--webapp-stay") < 0) Qt.quit() }
            step++
        }
    }

    // --embedded-apps-test[=<list>]: Teams' embedded first-party apps as OST
    // hosts them (TASK-0038, docs/spec/app-host.md), one after another, about
    // 40 s each: whiteboard, shifts, clipchamp (the app bar's personal apps),
    // copilot (the chat list's row), office (ost-open-test.docx from My
    // files with the "Teams" choice, the device setting put back after),
    // settings (Files and links), sto (Share to Outlook on your newest
    // message in --embed-chat, default OST group test; closed without
    // sending, which discards the draft) and ir (Immersive Reader on the
    // newest message). EMBED lines: each app's host events (TeamsJS
    // initialize, appLoaded, success, failure…) or the dialog's state;
    // pictures embed-<item>.png. Quits unless --embed-stay.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--embedded-apps-test")) && backend.signedIn && chatList.chats.length > 1
        interval: 5000; repeat: true
        property var items: ((Qt.application.arguments.find(a => a.startsWith("--embedded-apps-test=")) || "").slice(21) || "whiteboard,shifts,clipchamp,copilot,settings,office,sto,ir").split(",")
        property int idx: 0
        property int tick: 0
        property string before: ""
        readonly property string chatId: (Qt.application.arguments.find(a => a.startsWith("--embed-chat=")) || "").slice(13) || "19:ef213c7c46cf4036b11608300e96fee4@thread.v2"
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-embed-" + tag + ".png")))
            const item = items[idx]
            const next = () => { idx++; tick = -1; if (idx >= items.length && Qt.application.arguments.indexOf("--embed-stay") < 0) Qt.quit() }
            if (idx >= items.length) return
            const hosted = ["whiteboard", "clipchamp", "shifts"].indexOf(item)
            // --embed-message=<text>: the newest message with that text (a
            // card's message for the reader's card text), else your newest.
            const want = (Qt.application.arguments.find(a => a.startsWith("--embed-message=")) || "").slice(16)
            const newest = () => { const ms = conversation.messageHostForTest().messages || []; for (let i = ms.length - 1; i >= 0; i--) if (ms[i].id && !ms[i].deleted && (want ? (ms[i].text || "").indexOf(want) >= 0 : ms[i].mine)) return ms[i]; return null }
            if (hosted >= 0) {
                if (tick === 0) rail.openApp(item)
                else if (tick === 8) {
                    const v = hostedApps.itemAt(hosted).item
                    console.warn("EMBED", item, JSON.stringify({ events: v ? v.hostEvents : null, header: v ? v.headerShown : null, tab: v && v.personalTab ? v.personalTab.entity_id : "" }))
                    cap(item); next()
                }
            } else if (item === "copilot") {
                if (tick === 0) { rail.current = "chat"; chatList.openCopilot() }
                else if (tick === 9) { const v = copilotView.item; console.warn("EMBED copilot", JSON.stringify({ events: v ? v.hostEvents : null })); cap(item); next() }
            } else if (item === "settings") {
                if (tick === 0) { rail.current = "settings"; settingsView.pageForTest("files") }
                else if (tick === 1) { cap(item); next() }
            } else if (item === "office") {
                const f = (oneDrive.driveData.items || []).find(i => i.name === "ost-open-test.docx")
                if (tick === 0) { before = backend.setting("fileOpenIn"); backend.setSetting("fileOpenIn", "teams"); rail.current = "onedrive"; oneDrive.open("myfiles") }
                else if (tick === 2) { console.warn("EMBED office file", !!f); if (f) backend.openFile(f.web_url, f.name, JSON.stringify(f)) }
                else if (tick === 10) {
                    const v = officeView.item
                    console.warn("EMBED office", JSON.stringify({ rail: rail.current, app: window.officeFile ? window.officeFile.appName : "", events: v ? v.hostEvents : null, frame: v ? JSON.parse(v.hostStateForTest()).params : null }))
                    cap(item); backend.setSetting("fileOpenIn", before); next()
                }
            } else if (item === "sto" || item === "ir") {
                if (tick === 0) { rail.current = "chat"; chatList.copilotOpen = false; const c = chatList.chats.find(c => c.id === chatId); if (c) backend.selectChat(c.id, c.name) }
                else if (tick === 3) {
                    const m = newest(); const h = conversation.messageHostForTest()
                    console.warn("EMBED", item, "message", !!m, m && item === "ir" ? JSON.stringify({ cards: (m.cards || []).length, reader: (m.reader_html || "").slice(0, 400) }) : "")
                    if (m && item === "sto") h.shareToOutlookForTest.start(m)
                    else if (m) h.openImmersiveReader(m)
                } else if (tick === 9) {
                    const h = conversation.messageHostForTest()
                    if (item === "sto") {
                        const d = h.shareToOutlookForTest.dialog
                        console.warn("EMBED sto", JSON.stringify({ events: h.shareToOutlookForTest.events, dialog: d ? JSON.parse(d.stateForTest()).events : null }))
                    } else console.warn("EMBED ir", h.immersiveReaderForTest.stateForTest())
                    cap(item)
                } else if (tick === 10) {
                    const h = conversation.messageHostForTest()
                    if (item === "sto") h.shareToOutlookForTest.close(); else h.immersiveReaderForTest.close()
                } else if (tick === 12) {
                    const h = conversation.messageHostForTest()
                    console.warn("EMBED", item, "closed", item === "sto" ? JSON.stringify(h.shareToOutlookForTest.events) : h.immersiveReaderForTest.opened)
                    next()
                }
            } else next()
            tick++
        }
    }

    // --events-test[=create]: the Events app (docs/spec/events.md) from
    // View more apps: Discover, Manage, Create event and the New event
    // form, logging EVENTS lines (each page's state) and capturing
    // events-{discover,manage,create,form}.png. With =create it also saves
    // a draft named "OST TEST 209 draft <time>" (nobody invited, so nobody
    // is told), shows its page (events-draft.png), cancels it (the draft
    // is deleted) and reloads Manage. Quits unless --events-stay.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--events-test")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const cap = tag => window.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-events-" + tag + ".png")))
            const ev = eventsView.item
            const log = tag => console.warn("EVENTS", tag, ev ? ev.stateForTest() : "no view")
            // =townhall: the same with Teams' Town hall template (TASK-0184),
            // the draft named "OST TEST 184 town hall draft <time>".
            const townHall = Qt.application.arguments.indexOf("--events-test=townhall") >= 0
            const live = Qt.application.arguments.indexOf("--events-test=create") >= 0 || townHall
            switch (step) {
            case 0: rail.openApp("events"); break
            case 3: log("discover"); cap("discover"); break
            case 4: ev.openTab("manage"); break
            case 6: log("manage"); cap("manage"); break
            case 7: ev.startCreate(); break
            case 8: log("create"); cap("create"); break
            case 9: ev.startForm(ev.templates[townHall ? 2 : 0]); break
            case 10: if (townHall) ev.openOptionsForTest(); cap("form"); break
            case 11: if (!live) { log("done"); if (Qt.application.arguments.indexOf("--events-stay") < 0) Qt.quit(); step = 1000; return } ev.saveForTest((townHall ? "OST TEST 184 town hall draft " : "OST TEST 209 draft ") + Qt.formatTime(new Date(), "hh:mm")); break
            case 12: cap("save"); ev.confirmSaveForTest(); break
            case 16: log("saved"); cap("draft"); break
            case 17: ev.cancelCurrentForTest(); break
            case 19: log("cancelled"); ev.openTab("manage"); backend.loadCalendar(new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 19) + "Z", new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 19) + "Z"); break
            case 22: log("manage after"); cap("manage-after"); break
            // Test cleanup: a cancelled event stays in your calendar as
            // "Canceled: <title>" (as in Teams); the test's are removed.
            case 23: for (const c of (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).filter(c => /^Canceled: OST TEST (209|184 town hall draft)/.test(c.subject))) { console.warn("EVENTS removing", c.subject); backend.deleteEvent(c.id) } break
            case 25: if (Qt.application.arguments.indexOf("--events-stay") < 0) Qt.quit(); break
            }
            step++
        }
    }

    // --call-notes-test: a solo Teams meeting of your own (a calendar
    // event "OST TEST 209 notes OST" with nobody invited, made now for 30
    // minutes; OST has no calendar Meet now), joined with camera, mic and
    // audio off, then the call window's Notes: the meeting's notes as Teams
    // gets or makes them (MEETINGNOTES lines: the pane's state every 5 s),
    // captured as call-notes-{open,ready,end}.png; then it leaves, logs the
    // call state and deletes the event. --call-notes-stay keeps the call
    // two minutes longer (to open the notes from another client).
    Timer {
        running: Qt.application.arguments.indexOf("--call-notes-test") >= 0 && backend.signedIn
        interval: 5000; repeat: true
        property int step: 0
        property int held: 0
        property var ev: null
        readonly property string subject: "OST TEST 209 notes OST"
        onTriggered: {
            const capCall = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-call-notes-" + tag + ".png")))
            const log = tag => console.warn("MEETINGNOTES", tag, backend.callState, callWindow.meetingNotesPaneForTest.stateForTest())
            const stay = Qt.application.arguments.indexOf("--call-notes-stay") >= 0
            if (step === 0) {
                // One left from an earlier run is reused (and deleted after).
                const old = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(x => x.subject === subject && x.join_url)
                const s = new Date(); s.setSeconds(0, 0); const e = new Date(s.getTime() + 30 * 60000)
                if (!old) backend.createEvent(subject, s.toISOString(), e.toISOString(), "", true)
            } else if (step >= 1 && step <= 8 && !ev) {
                ev = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(x => x.subject === subject && x.join_url) || null
                if (!ev) { step++; return }
                console.warn("MEETINGNOTES event made", !!ev.join_url)
                window.muteOnJoin = true; window.noAudioOnJoin = true; window.cameraOnJoin = false
                backend.joinMeeting(ev.join_url, subject)
                step = 9; return
            } else if (step === 9 && !ev) { console.warn("MEETINGNOTES no event"); Qt.quit() }
            else if (step === 12) { log("joined"); callWindow.runControl("MeetingDetailsButton") }
            else if (step === 13) { log("open"); capCall("open") }
            else if (step > 13 && step < 30) { log("t" + step); if (step === 22) capCall("ready") }
            else if (step === 30 && stay && held++ < 24) return
            else if (step === 31) { capCall("end"); backend.hangUp() }
            else if (step === 33) { console.warn("MEETINGNOTES after", backend.callState); if (ev && ev.id) backend.deleteEvent(ev.id) }
            else if (step === 34) backend.loadCalendar(new Date(Date.now() - 86400000).toISOString().slice(0, 19) + "Z", new Date(Date.now() + 86400000).toISOString().slice(0, 19) + "Z")
            else if (step === 36) { console.warn("MEETINGNOTES event still there", (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).some(x => x.subject === subject)); Qt.quit() }
            step++
        }
    }

    // --phone-audio-test: Teams' phone audio in a solo meeting of your own
    // (a calendar event "OST TEST 187 phone OST" with nobody invited, now
    // for 30 minutes): the pre-join window's Phone audio (PHONE prejoin
    // lines, phone-prejoin{,-selected}.png), joining with it (camera and
    // computer audio off), "Use phone for audio" as it opens by itself
    // (phone-dialog.png), a number typed and left (phone-number.png; Call
    // me is never pressed), Dial in manually (phone-dialin.png), More with
    // Call me and Facilitator ▸ (phone-more.png) and Meeting info's dial-in
    // block (phone-info.png); then it leaves, logs the call state and
    // deletes the event. --phone-audio-invalid-call also has the meeting
    // call +1 000 000 0000 (a number no phone has; area code 000 doesn't
    // exist) and logs the meeting's answer. --phone-audio-facilitator turns
    // Facilitator on (Teams' alert, then the transcript), captures More ▸
    // Facilitator ▸ and turns it off again.
    Timer {
        running: Qt.application.arguments.indexOf("--phone-audio-test") >= 0 && backend.signedIn
        interval: 5000; repeat: true
        property int step: 0
        property var ev: null
        // --phone-audio-subject=<title>: an existing meeting of yours
        // instead (kept afterwards).
        readonly property string given: (Qt.application.arguments.find(a => a.startsWith("--phone-audio-subject=")) || "").slice(22)
        readonly property string subject: given || "OST TEST 187 phone OST"
        readonly property bool invalidCall: Qt.application.arguments.indexOf("--phone-audio-invalid-call") >= 0
        readonly property bool facilitator: Qt.application.arguments.indexOf("--phone-audio-facilitator") >= 0
        onTriggered: {
            const capCall = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-phone-" + tag + ".png")))
            const capPre = tag => preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-phone-" + tag + ".png")))
            const dlg = () => callWindow.phoneDialogForTest()
            const log = tag => console.warn("PHONE", tag, backend.callState, backend.callPhoneJson, dlg().showing ? dlg().stateForTest() : "")
            if (step === 0) {
                const old = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(x => x.subject === subject && x.join_url)
                const s = new Date(); s.setSeconds(0, 0); const e = new Date(s.getTime() + 30 * 60000)
                if (!old && !given) backend.createEvent(subject, s.toISOString(), e.toISOString(), "", true)
                if (given) backend.loadCalendar(new Date(Date.now() - 86400000).toISOString().slice(0, 19) + "Z", new Date(Date.now() + 86400000).toISOString().slice(0, 19) + "Z")
            } else if (step >= 1 && step <= 8 && !ev) {
                ev = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(x => x.subject === subject && x.join_url) || null
                if (!ev) { step++; return }
                console.warn("PHONE event", subject, given ? "(kept)" : "(made)")
                preJoin.openFor(ev.join_url, subject, ev.start_utc, ev.end_utc)
                step = 9; return
            } else if (step === 9 && !ev) { console.warn("PHONE no event"); Qt.quit() }
            else if (step === 11) { console.warn("PHONE prejoin", backend.prejoinPhoneJson, preJoin.audio); capPre("prejoin") }
            else if (step === 12) { preJoin.audio = "phone"; console.warn("PHONE prejoin selected", preJoin.audio) }
            else if (step === 13) capPre("prejoin-selected")
            else if (step === 14) { window.cameraOnJoin = false; preJoin.close(); preJoin.join(false, false, false) }
            else if (step === 18) { log("joined"); capCall("dialog") }
            else if (step === 19) { dlg().typeForTest("4255550100"); log("typed") }
            else if (step === 20) { dlg().blurForTest(); log("left the box"); capCall("number") }
            else if (step === 21) { dlg().view = "dialIn"; log("dial in") }
            else if (step === 22) capCall("dialin")
            else if (step === 23) { dlg().close(); callWindow.moreSubmenuForTest("FacilitatorButton") }
            else if (step === 24) { capCall("more"); console.warn("PHONE more", JSON.stringify(callWindow.barMoreItems.map(i => i.label || "|"))) }
            else if (step === 25) { callWindow.closeMoreForTest(); callWindow.runControl("MeetingInfoButton") }
            else if (step === 27) { capCall("info"); console.warn("PHONE info", backend.callMeetingInfoJson.length > 0 ? JSON.stringify(JSON.parse(backend.callMeetingInfoJson).dial) : "") }
            else if (step === 28 && invalidCall) { callWindow.runControl("MeetingInfoButton"); callWindow.openPhoneAudio(); dlg().typeForTest("+1 000 000 0000"); log("invalid typed"); dlg().callMe() }
            else if (step > 28 && step < 37 && invalidCall) { log("invalid t" + step); if (step === 30) capCall("calling"); if (step === 36) capCall("call-result") }
            else if (step === 37 && facilitator) { dlg().close(); callWindow.facilitatorAction("FacilitatorToggle"); console.warn("PHONE facilitator on asked", callWindow.aiFacilitator) }
            else if (step === 38 && facilitator) { capCall("facilitator-ask"); callWindow.copilotAskForTest().visible = false; callWindow.recordStartForTest("transcription") }
            else if (step === 39 && facilitator) callWindow.confirmRecordDialogForTest()
            else if (step === 44 && facilitator) { console.warn("PHONE facilitator", callWindow.aiFacilitator, backend.callAiFacilitatorVoice, backend.callRecordingState); callWindow.moreSubmenuForTest("FacilitatorButton") }
            else if (step === 45 && facilitator) { capCall("facilitator-on"); callWindow.closeMoreForTest(); callWindow.facilitatorAction("FacilitatorToggle") }
            else if (step === 48 && facilitator) { console.warn("PHONE facilitator after off", callWindow.aiFacilitator); callWindow.moreSubmenuForTest("FacilitatorButton") }
            else if (step === 49 && facilitator) { capCall("facilitator-off"); callWindow.closeMoreForTest() }
            else if (step === 50) { log("leaving"); dlg().close(); backend.hangUp() }
            else if (step === 52) { console.warn("PHONE after", backend.callState); if (ev && ev.id && !given) backend.deleteEvent(ev.id) }
            else if (step === 53) backend.loadCalendar(new Date(Date.now() - 86400000).toISOString().slice(0, 19) + "Z", new Date(Date.now() + 86400000).toISOString().slice(0, 19) + "Z")
            else if (step === 55) { console.warn("PHONE event still there", (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).some(x => x.subject === subject)); Qt.quit() }
            step++
        }
    }

    // --preheat-test: Teams' pre-join preheat (TASK-0215; docs/spec/
    // call-and-meeting-window.md §1.8k). The meeting is --join-url=<link>
    // (--preheat-subject=<title> names it), else a solo meeting of yours
    // made now for 30 minutes ("OST TEST 215 preheat", deleted at the end).
    // The pre-join window opens (its call is joined hidden); PREHEAT lines
    // log its Phone audio state every 2 s until known (-preheat-prejoin.png,
    // then -preheat-phone.png). Then:
    // --preheat-cancel cancels (the call is left), --preheat-join joins
    // (muted; held in a lobby it waits up to 2 minutes to be let in),
    // --preheat-expire waits 70 s (Teams leaves the preheated call after a
    // minute) and joins afresh; --join-stay=<s> stays, then it leaves
    // (-preheat-call.png). --preheat-host instead joins at once and, for
    // --join-stay, logs who the roster and the lobby show (a preheated
    // pre-join must show in neither) and, with --preheat-host-admit, lets
    // in whoever waits; then it leaves.
    Timer {
        running: Qt.application.arguments.indexOf("--preheat-test") >= 0 && backend.signedIn
        interval: 2000; repeat: true
        property int step: 0
        property var ev: null
        property int doneAt: -1
        property int joinedAt: -1
        function arg(n) { return Qt.application.arguments.indexOf(n) >= 0 }
        readonly property string given: window.joinUrl
        readonly property string subject: (Qt.application.arguments.find(a => a.startsWith("--preheat-subject=")) || "").slice(18) || "OST TEST 215 preheat"
        onTriggered: {
            const capPre = tag => preJoin.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-preheat-" + tag + ".png")))
            const capCall = tag => callWindow.contentItem.grabToImage(r => r.saveToFile(window.shotPath.replace(".png", "-preheat-" + tag + ".png")))
            const log = (...a) => console.warn("PREHEAT", "t=" + step * 2, ...a.map(x => typeof x === "string" ? x : JSON.stringify(x)))
            const names = () => JSON.parse(backend.callRosterJson || "[]").map(p => p.name || p.displayName || p.id)
            const lobby = () => JSON.parse(backend.callLobbyJson || "[]").map(p => p.name)
            const host = arg("--preheat-host")
            if (step === 0) {
                if (given) ev = { join_url: given, subject: subject, id: "" }
                else {
                    const s = new Date(); s.setSeconds(0, 0); const e = new Date(s.getTime() + 30 * 60000)
                    backend.createEvent(subject, s.toISOString(), e.toISOString(), "", true)
                }
            } else if (!ev && step <= 8) {
                const found = (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).find(x => x.subject === subject && x.join_url)
                if (found) { ev = found; log("event made", subject) }
                if (step === 8 && !ev) { log("no event"); Qt.quit() }
                step++; return
            } else if (ev && step < 100 && !window.preheatOpened) {
                window.preheatOpened = true
                log(host ? "host joining" : "opening pre-join", ev.subject)
                preJoin.openFor(ev.join_url, ev.subject, ev.start_utc, ev.end_utc)
                window.preheatOpenedAt = step
                if (host) { preJoin.close(); preJoin.join(false, true, false); joinedAt = step }
            } else if (host && doneAt < 0) {
                if (step % 2 === 0) log("host", backend.callState, "roster", names(), "lobby", lobby())
                if (arg("--preheat-host-admit") && backend.callState === "connected") {
                    const l = JSON.parse(backend.callLobbyJson || "[]")
                    if (l.length) { log("admitting", l[0].name); backend.admitFromLobby(l[0].id, l[0].name, false) }
                }
                if (step === joinedAt + 5 + window.joinStay) { log("host leaving"); backend.hangUp(); doneAt = step }
            } else if (joinedAt < 0 && doneAt < 0) {
                const t = step - window.preheatOpenedAt
                if (t <= 12 || t % 5 === 0) log("prejoin phone", backend.prejoinPhoneJson, "audio", preJoin.audio)
                if (t === 2) capPre("prejoin")
                if (t === 9) capPre("phone")
                const joinAt = arg("--preheat-expire") ? 36 : 10
                if (arg("--preheat-cancel") && t === 10) { log("cancelling"); preJoin.cancel(); doneAt = step }
                else if ((arg("--preheat-join") || arg("--preheat-expire")) && t === joinAt) {
                    log("joining", arg("--preheat-expire") ? "after the preheat expired" : "the preheated call")
                    preJoin.close(); preJoin.join(false, true, false); joinedAt = step
                }
            } else if (joinedAt >= 0 && doneAt < 0) {
                const t = step - joinedAt
                if (t % 3 === 0) log("joined", backend.callState, "muted", backend.callMuted, "roster", names())
                if (t === 4) capCall("call")
                // Held in the lobby: wait to be let in (2 minutes at most).
                if (backend.callState === "lobby" && t < 60) { step++; joinedAt++; return }
                if (t === 6 + window.joinStay) { log("leaving", backend.callState); backend.hangUp(); doneAt = step }
            } else if (doneAt >= 0) {
                // Never quit while still in a call: leave first.
                if (backend.callState !== "" && backend.callState !== "ended") {
                    if ((step - doneAt) % 5 === 4) { log("still in the call", backend.callState, "- leaving"); backend.hangUp() }
                    step++; return
                }
                const t = step - doneAt
                if (t === 3) log("after", "state", JSON.stringify(backend.callState), "prejoin visible", preJoin.visible)
                if (t === 4 && ev && ev.id && !given) backend.deleteEvent(ev.id)
                if (t === 6) backend.loadCalendar(new Date(Date.now() - 86400000).toISOString().slice(0, 19) + "Z", new Date(Date.now() + 86400000).toISOString().slice(0, 19) + "Z")
                if (t === 8) { if (!given) log("event still there", (backend.calendarJson ? JSON.parse(backend.calendarJson) : []).some(x => x.subject === subject)); Qt.quit() }
            }
            step++
        }
    }
    property bool preheatOpened: false
    property int preheatOpenedAt: 0

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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST send test" }).name); openedAt = Date.now(); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST actions test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST who reacted test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST tones test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST customize test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST react test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST edit test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST compose test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST delivery test" }).name); return }
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
        readonly property var pages: ["general", "appearance", "chats", "notifications", "accounts", "privacy", "accessibility", "devices", "calls", "files", "apppermissions", "about"]
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

    // --app-permissions-test --shots=<dir>: Settings ▸ App permissions (its
    // apps, Teams' rule), Bookable desks opened (ap-open). Logs APPPERMS.
    Timer {
        running: Qt.application.arguments.indexOf("--app-permissions-test") >= 0 && backend.signedIn && !!backend.teamsJson
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + n + ".png"))
            if (step === 0) rail.current = "settings"
            else if (step === 1) settingsView.pageForTest("apppermissions")
            else if (step === 4) { console.warn("APPPERMS", JSON.stringify(settingsView.appPermsForTest())); shot("ap-list") }
            else if (step === 5) settingsView.openAppPermForTest("Bookable desks")
            else if (step === 6) shot("ap-open")
            else if (step === 7) Qt.quit()
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
            else if (step === 6) { if (Qt.application.arguments.indexOf("--workflows-stay") >= 0) return; workflowsDialog.close(); Qt.quit() }
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
    // capture it once it has loaded (chat.png) and quit. --jump=<text>
    // brings the newest loaded message containing <text> into view first.
    Timer {
        running: Qt.application.arguments.indexOf("--chat-shot") >= 0 && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const id = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12)
            const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
            const jump = (Qt.application.arguments.find(a => a.startsWith("--jump=")) || "").slice(7)
            if (backend.currentChatId !== id) { backend.selectChat(id, "OST chat"); return }
            if (step === 1 && jump) {
                const m = (backend.messagesJson ? JSON.parse(backend.messagesJson) : []).filter(m => JSON.stringify(m).indexOf(jump) >= 0).pop()
                console.warn("chat-shot jump:", jump, m ? m.id : "not loaded")
                if (m) conversation.jumpToMessage(m.id)
            }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST agent test" }).name); return }
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

    // --add-tab-test with --open-chat=<chat or channel id> --shots=<dir>:
    // Teams' Add a tab: the header, "+" (a channel's menu first, then Apps),
    // the picker (logs its grid and collections; See all), Website's
    // configuration (an invalid URL, then --add-tab-url=<url>, if given,
    // saved with --add-tab-name=<name>, posting unless --add-tab-nopost),
    // the header with the new tab and its menu; with --add-tab-remove the
    // tab is removed again. Captures add-tab-<step>.png and quits.
    Timer {
        running: Qt.application.arguments.indexOf("--add-tab-test") >= 0 && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property int saveWait: 0
        property bool appSaved: false
        property string added: ""
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const has = k => Qt.application.arguments.indexOf(k) >= 0
            const id = arg("--open-chat")
            const dir = (arg("--shots") || ".") + "/"
            const url = arg("--add-tab-url"), name = arg("--add-tab-name") || "Website"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "add-tab-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                const cc = chatList.chats.find(c => c.id === id); backend.selectChat(id, ch ? ch.name : (cc ? cc.name : "")); return
            }
            const s = tabPicker.store
            if (step === 0) { console.warn("ADDTAB tabs", JSON.stringify(conversation.tabNames), "meeting", backend.chatMeetingJson); shot("header") }
            else if (step === 1) { if (conversation.isChannel) { conversation.addTabMenuForTest(); } else conversation.addTab() }
            else if (step === 2) { shot(conversation.isChannel ? "menu" : "picker-loading"); if (conversation.isChannel) { conversation.addTabMenuForTest().close(); tabPicker.showTabs(id, "channel", conversation.teamThread) } }
            else if (step > 2 && step < 14) {
                if ((!s || s.loading) && step < 13) { step++; return }
                console.warn("ADDTAB picker", JSON.stringify(s ? { grid: (s.installed || []).map(a => a.name), collections: (s.collections || []).map(x => x.title + " (" + x.apps.length + "): " + x.apps.slice(0, 3).map(a => a.name).join(", ")), error: s.error || "" } : null))
                shot("picker"); step = 14; return
            }
            else if (step === 15) tabPicker.gridAll = true
            else if (step === 16) shot("picker-all")
            else if (step === 17) {
                tabPicker.gridAll = false
                // --add-tab-app=<name>: that app's own configuration page
                // instead (in OST's TeamsJS host), logged and captured
                // after 20 s; nothing is saved.
                const want = arg("--add-tab-app")
                const web = (s && s.installed || []).find(a => want ? a.name === want : a.id === "com.microsoft.teamspace.tab.web")
                if (!web) { console.warn("ADDTAB no", want || "Website", "in the grid"); Qt.quit(); return }
                tabPicker.pickTabApp(web)
            }
            else if (step === 18) shot("config")
            else if (step === 26 && arg("--add-tab-app") && !appSaved) { console.warn("ADDTAB app config", tabConfig.stateForTest()); shot("config-app"); step++; return }
            // --add-tab-save: wait (up to 3 minutes) until the page reports
            // a valid setup (pick its item yourself, e.g. over the DevTools
            // port), then Save as Teams; then the result, the tabs and the
            // new tab as for a website (--add-tab-remove removes it).
            else if (step === 27 && arg("--add-tab-app") && has("--add-tab-save") && !appSaved) {
                if (!tabConfig.appValid && saveWait++ < 72) return
                console.warn("ADDTAB app save", tabConfig.stateForTest()); appSaved = true; if (has("--add-tab-nopost")) tabConfig.setPost(false); tabConfig.save(); step = 24; return
            }
            else if (step === 27 && arg("--add-tab-app") && !appSaved) { tabConfig.close(); Qt.quit(); return }
            else if (step > 18 && step < 26 && arg("--add-tab-app") && !appSaved) { step++; return }
            else if (step > 23 && step < 27 && appSaved) { if (tabConfig.saving && saveWait++ < 120) return; step = 27; return }
            else if (step === 19) tabConfig.fillForTest(name, "http://example")
            else if (step === 20) { console.warn("ADDTAB invalid", tabConfig.stateForTest()); shot("config-invalid") }
            else if (step === 21) { tabConfig.fillForTest(name, url || "https://example.com") }
            else if (step === 22) { console.warn("ADDTAB valid", tabConfig.stateForTest()); shot("config-valid"); if (!url) { tabConfig.close(); Qt.quit(); return } }
            else if (step === 23) { if (has("--add-tab-nopost")) tabConfig.setPost(false); tabConfig.save() }
            else if (step === 27) {
                console.warn("ADDTAB result", backend.channelTabResult)
                const r = JSON.parse(backend.channelTabResult || "{}")
                added = r.ok ? r.tab : ""
                console.warn("ADDTAB tabs after", JSON.stringify(conversation.tabNames), JSON.stringify(conversation.channelTabs.map(t => ({ id: t.id, name: t.name, kind: t.kind, menu: t.context_menu.map(m => m.key) }))))
                shot("added")
            }
            else if (step === 28) { const t = conversation.channelTabs.find(t => t.id === added); if (t) conversation.tabMenuShowForTest(t.name) }
            else if (step === 29) shot("added-menu")
            else if (step === 30) { conversation.tabMenuCloseForTest(); if (!has("--add-tab-remove") || !added) { Qt.quit(); return } const t = conversation.channelTabs.find(t => t.id === added); if (t) conversation.tabDialogForTest("remove", t.name) }
            else if (step === 31) shot("remove-dialog")
            else if (step === 32) { const t = conversation.channelTabs.find(t => t.id === added); if (t) conversation.tabChangeForTest("remove", t.name, "") }
            else if (step === 35) { conversation.tabDialogCloseForTest(); console.warn("ADDTAB removed", backend.channelTabResult, JSON.stringify(conversation.tabNames)); shot("removed") }
            else if (step === 36) Qt.quit()
            step++
        }
    }

    // --meeting-tab-test=<tab name> with --open-chat=<meeting chat id>
    // --shots=<dir>: a meeting chat's tabs and "+N" (logged, captured),
    // then that tab opened (Breakout Rooms, Q&A, Meeting Whiteboard),
    // captured after 10 and 25 s (meeting-tab-*.png); quits.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--meeting-tab-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const id = arg("--open-chat"), which = arg("--meeting-tab-test").replace(/_/g, " ").replace("QnA", "Q&A")
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "meeting-tab-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST meeting tab test" }).name); return }
            if (step === 1) { console.warn("MEETINGTAB tabs", JSON.stringify(conversation.tabNames), "meeting", backend.chatMeetingJson); shot("header") }
            else if (step === 2) conversation.overflowMenuForTest()
            else if (step === 3) shot("overflow")
            else if (step === 4) { conversation.closeOverflowForTest(); conversation.tab = which }
            else if (step === 8) { const h = conversation.meetingAppTabForTest(); console.warn("MEETINGTAB breakout", backend.meetingBreakoutJson, "host", h ? h.hostStateForTest() : ""); shot("open-10s") }
            else if (step === 14) { const h = conversation.meetingAppTabForTest(); console.warn("MEETINGTAB host", h ? h.hostStateForTest() : ""); shot("open-25s") }
            else if (step === 15) { if (Qt.application.arguments.indexOf("--meeting-tab-stay") < 0) Qt.quit(); return }
            step++
        }
    }

    // --add-tab-choice=<newList|existingList|existingPage> with
    // --open-chat=<channel id> --shots=<dir>: a channel's "+" choice as
    // Teams: New list / Existing list add the Lists tab and open its page
    // (ADDTAB choice result, tabs, the page's host events after 20 s);
    // Existing page needs --add-tab-link=<Loop link>: the link looked up
    // (the card), then Confirm. --add-tab-remove removes the new tab.
    // Pictures add-tab-choice-*.png; quits (--add-tab-stay keeps it open).
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--add-tab-choice=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property string added: ""
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const has = k => Qt.application.arguments.indexOf(k) >= 0
            const id = arg("--open-chat"), which = arg("--add-tab-choice"), link = arg("--add-tab-link")
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "add-tab-choice-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                backend.selectChat(id, ch ? ch.name : ""); return
            }
            const dlg = conversation.existingPageDialogForTest()
            if (step === 1) { console.warn("ADDTAB choice tabs", JSON.stringify(conversation.tabNames)); conversation.addTabMenuForTest() }
            else if (step === 2) { shot("menu"); conversation.addTabMenuForTest().close(); conversation.addTabChoice(which) }
            else if (step === 3 && which === "existingPage") { shot("page-dialog"); dlg.fillForTest(link); dlg.next() }
            else if (step === 5 && which === "existingPage") { console.warn("ADDTAB choice page", dlg.stateForTest()); shot("page-card"); dlg.next() }
            else if (step === 8) {
                const r = JSON.parse(backend.channelTabResult || "{}")
                added = r.ok ? r.tab : ""
                console.warn("ADDTAB choice result", backend.channelTabResult)
                console.warn("ADDTAB choice tabs after", JSON.stringify(conversation.channelTabs.map(t => ({ id: t.id, name: t.name, kind: t.kind }))), "open", conversation.tab)
                shot("added")
            }
            else if (step === 16) { const h = conversation.hostedTabForTest(); console.warn("ADDTAB choice host", h ? h.hostStateForTest() : "none"); shot("page-20s") }
            else if (step === 17) { if (has("--add-tab-stay")) return; if (!has("--add-tab-remove") || !added) { Qt.quit(); return } const t = conversation.channelTabs.find(t => t.id === added); if (t) conversation.tabChangeForTest("remove", t.name, "") }
            else if (step === 20) { console.warn("ADDTAB choice removed", backend.channelTabResult, JSON.stringify(conversation.tabNames)); Qt.quit() }
            step++
        }
    }

    // --tab-cleanup=<name|name…> with --open-chat=<chat or channel id>:
    // remove those tabs (Teams' Remove: the thread property to null), one
    // every 5 s, logging TABCLEANUP lines; quits.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--tab-cleanup=")) && backend.signedIn
        interval: 5000; repeat: true
        property int step: 0
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const id = arg("--open-chat"), names = arg("--tab-cleanup").split("|")
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                backend.selectChat(id, ch ? ch.name : ""); return
            }
            if (step === 0) { step++; return }
            const left = names.filter(n => conversation.channelTabs.some(t => t.name === n))
            console.warn("TABCLEANUP", backend.channelTabResult, "left", JSON.stringify(left))
            if (!left.length || step > 30) { Qt.quit(); return }
            conversation.tabChangeForTest("remove", left[0], "")
            step++
        }
    }

    // --task-dialog-test=<findmeetingtime|createaplanner|remindme> with
    // --open-chat=<chat id> --shots=<dir>: the workflow suggestion's
    // Workflows dialog (Teams' task module) in OST's TeamsJS host: its
    // state and host events after 15 and 30 s (TASKDIALOG lines,
    // task-dialog-*.png), then Close (the dialog answers "User
    // cancelled/closed the task module."); nothing is submitted.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--task-dialog-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const id = arg("--open-chat"), page = arg("--task-dialog-test")
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "task-dialog-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST dialog test" }).name); return }
            if (step === 1) conversation.openWorkflowDialog(page, { title: "OST test" })
            else if (step === 7) { console.warn("TASKDIALOG 15s", conversation.workflowDialog ? conversation.workflowDialog.stateForTest() : "none"); shot("15s") }
            else if (step === 13) { console.warn("TASKDIALOG 30s", conversation.workflowDialog ? conversation.workflowDialog.stateForTest() : "none"); shot("30s") }
            else if (step === 14) { if (conversation.workflowDialog) conversation.workflowDialog.close() }
            else if (step === 15) { console.warn("TASKDIALOG closed", !conversation.workflowDialog); Qt.quit() }
            step++
        }
    }

    // --chat-tab-test=<Notes|Recap|Storyline> with --open-chat=<chat id>
    // --shots=<dir>: a chat's tabs (CHATTAB line), then that tab, logged
    // and captured after 10 and 25 s (chat-tab-<tab>-*.png); Notes logs its
    // state and its page's address and title; Recap in a meeting chat
    // also captures its Mentions and Transcript pages and More options;
    // quits.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--chat-tab-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const id = arg("--open-chat"), which = arg("--chat-tab-test")
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "chat-tab-" + which.toLowerCase() + "-" + n + ".png"))
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST chat tab test" }).name); return }
            const notes = conversation.notesTabForTest(), recap = conversation.recapTabForTest(), story = conversation.storylineTabForTest()
            const web = which === "Storyline" ? story : null
            const page = () => web && web.view ? { url: String(web.view.url).slice(0, 160), title: web.view.title, progress: web.view.loadProgress, host: web.hostStateForTest() }
                : notes ? { state: notes.state_, file: notes.pageUrl.split("?")[0] } : null
            if (step === 1) { console.warn("CHATTAB tabs", JSON.stringify(conversation.tabNames)); shot("header") }
            else if (step === 2) conversation.tab = which
            else if (step === 6) { console.warn("CHATTAB open-10s", which, backend.chatNotesJson ? backend.chatNotesJson.slice(0, 300) : "", JSON.stringify(page())); shot("open-10s") }
            else if (step === 12) { console.warn("CHATTAB open-25s", which, backend.chatNotesJson ? backend.chatNotesJson.slice(0, 300) : "", JSON.stringify(page())); shot("open-25s") }
            // Notes' other pages, drawn from a set state (nothing is sent).
            else if (step >= 13 && step <= 18 && notes) {
                const st = ["preparing", "deleted", "failed"][Math.floor((step - 13) / 2)]
                if (step % 2 === 1) notes.stateForTest = st
                else shot(st)
            }
            else if (step === 13 && recap && recap.meeting) recap.pillForTest("Mentions")
            else if (step === 14 && recap && recap.meeting) shot("mentions")
            else if (step === 15 && recap && recap.meeting) recap.pillForTest("Transcript")
            else if (step === 16 && recap && recap.meeting) shot("transcript")
            else if (step === 17 && recap && recap.meeting) recap.moreForTest()
            else if (step === 18 && recap && recap.meeting) shot("more")
            else if (step === 19) Qt.quit()
            step++
        }
    }

    // --loop-delete-file=<drive id>|<item id>: delete a test Loop page's
    // file (to its site's recycle bin), log LOOPTEST deleted, quit.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--loop-delete-file=")) && backend.signedIn
        interval: 3000; repeat: true
        property int step: 0
        onTriggered: {
            const v = (Qt.application.arguments.find(a => a.startsWith("--loop-delete-file=")) || "").slice("--loop-delete-file=".length).split("|")
            if (step === 0 && v.length === 2) backend.driveDelete(v[0], v[1])
            else if (step === 3) { console.warn("LOOPTEST deleted", v[1] || ""); Qt.quit() }
            step++
        }
    }

    // --loop-test=<notes|page|newpage> with --open-chat=<chat or channel
    // id> --shots=<dir>: a Loop page in OST's Loop page host
    // (docs/spec/loop-host.md). notes: the chat's Notes tab; page: the
    // channel's Page tab named --loop-tab=<name>; newpage: the channel's
    // "+" › New page (the tab, then Loop makes the page). LOOPTEST lines:
    // the host's state and events every 5 s until the page is drawn (or
    // 90 s), its text; pictures loop-<which>-{open,ready}.png. With
    // --loop-type=<text> it types the text at the end of the page as real
    // keys, reads the page back, then deletes it again with Backspace
    // (loop-<which>-{typed,removed}.png). --loop-remove: a new page's tab
    // is removed and its file deleted (to the recycle bin) afterwards.
    // Quits unless --loop-stay.
    Timer {
        running: Qt.application.arguments.some(a => a.startsWith("--loop-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property int readyAt: -1
        property string typed: ""
        property string added: ""
        property var created: null
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const has = k => Qt.application.arguments.indexOf(k) >= 0
            const id = arg("--open-chat"), which = arg("--loop-test"), text = arg("--loop-type")
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "loop-" + which + "-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                const chat = chatList.chats.find(c => c.id === id)
                // A channel opens once its team is known (else it would
                // open as a chat).
                if (which !== "notes" && !ch) return
                backend.selectChat(id, ch ? ch.name : chat ? chat.name : "OST Loop test"); return
            }
            if (which !== "notes" && !conversation.isChannel) return
            const view = which === "notes" ? conversation.notesTabForTest() : conversation.pageTabForTest()
            const loop = view && view.loopForTest ? view.loopForTest() : null
            const state = () => loop ? JSON.parse(loop.stateForTest()) : { state: "none" }
            if (step === 1) {
                console.warn("LOOPTEST tabs", JSON.stringify(conversation.tabNames))
                if (which === "notes") conversation.tab = "Notes"
                else if (which === "page") conversation.tab = arg("--loop-tab")
                else { conversation.addTabChoice("newPage") }
            } else if (step === 3) { console.warn("LOOPTEST open", conversation.tab, JSON.stringify(state())); shot("open") }
            else if (step > 3 && readyAt < 0) {
                const s = state()
                if (step % 2 === 0) console.warn("LOOPTEST state", conversation.tab, JSON.stringify(s))
                if (which === "newpage" && !added) {
                    const r = JSON.parse(backend.channelTabResult || "{}")
                    if (r.op === "add" && r.ok) { added = r.tab; console.warn("LOOPTEST tab added", r.tab) }
                }
                if (s.state === "ready" || s.state === "error" || step > 40) {
                    readyAt = step
                    shot("ready")
                    if (loop) loop.textForTest(t => console.warn("LOOPTEST text", JSON.stringify(String(t).slice(0, 300))))
                }
            } else if (readyAt >= 0 && step === readyAt + 4) {
                if (which === "newpage") console.warn("LOOPTEST tabs after", JSON.stringify(conversation.channelTabs.filter(t => t.kind === "ChannelPage").map(t => ({ id: t.id, name: t.name, link: t.content_url.split("?")[0] }))))
                if (text && loop && state().state === "ready") { typed = text; loop.typeForTest(text) }
            } else if (readyAt >= 0 && step === readyAt + 7 && typed) {
                loop.textForTest(t => console.warn("LOOPTEST typed", String(t).indexOf(typed) >= 0 ? "found" : "missing", JSON.stringify(String(t).slice(0, 300))))
                shot("typed")
            } else if (readyAt >= 0 && step === readyAt + 8 && typed) {
                // The page again from the service: the typing was saved.
                loop.reload()
            } else if (readyAt >= 0 && step === readyAt + 14 && typed) {
                loop.textForTest(t => console.warn("LOOPTEST reloaded", String(t).indexOf(typed) >= 0 ? "found" : "missing", JSON.stringify(String(t).slice(0, 300))))
                shot("reloaded")
            } else if (readyAt >= 0 && step === readyAt + 15 && typed) {
                loop.typeForTest("\b".repeat(typed.length))
            } else if (readyAt >= 0 && step === readyAt + 18 && typed) {
                loop.textForTest(t => console.warn("LOOPTEST removed", String(t).indexOf(typed) >= 0 ? "still there" : "gone", JSON.stringify(String(t).slice(0, 300))))
                shot("removed")
                loop.reload()
            } else if (readyAt >= 0 && step === readyAt + 24 && typed) {
                loop.textForTest(t => console.warn("LOOPTEST removed after reload", String(t).indexOf(typed) >= 0 ? "still there" : "gone", JSON.stringify(String(t).slice(0, 300))))
            } else if (readyAt >= 0 && step === readyAt + 25) {
                console.warn("LOOPTEST final", JSON.stringify(state()))
                if (which === "newpage" && has("--loop-remove") && added) {
                    const t = conversation.channelTabs.find(t => t.id === added)
                    if (t) conversation.tabChangeForTest("remove", t.name, "")
                    const ev = view && view.createdForTest ? view.createdForTest() : null
                    if (ev && ev.driveId && ev.itemId) { console.warn("LOOPTEST deleting the new page's file"); backend.driveDelete(ev.driveId, ev.itemId) }
                }
            } else if (readyAt >= 0 && step === readyAt + 29) {
                console.warn("LOOPTEST done", backend.channelTabResult)
                if (!has("--loop-stay")) Qt.quit()
            }
            step++
        }
    }

    // --app-host-test[=<tab name>] with --open-chat=<channel id>
    // --shots=<dir>: a channel's app tab (default Notes) in OST's TeamsJS
    // host (docs/spec/app-host.md): the host's events (APPHOST lines) and
    // pictures after 15, 35 and 55 s, then the tab's Reload, Expand, Open
    // in new window and App permissions (app-host-*.png); quits, unless
    // --app-host-stay (to inspect the views over DevTools).
    Timer {
        running: Qt.application.arguments.some(a => a === "--app-host-test" || a.startsWith("--app-host-test=")) && backend.signedIn
        interval: 2500; repeat: true
        property int step: 0
        property var popped: null
        onTriggered: {
            const arg = k => (Qt.application.arguments.find(a => a.startsWith(k + "=")) || "").slice(k.length + 1)
            const id = arg("--open-chat"), which = arg("--app-host-test") || "Notes"
            const dir = (arg("--shots") || ".") + "/"
            const shot = n => window.contentItem.grabToImage(r => r.saveToFile(dir + "app-host-" + n + ".png"))
            if (backend.currentChatId !== id) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === id)
                backend.selectChat(id, ch ? ch.name : "OST app host test"); return
            }
            const host = conversation.hostedTabForTest()
            const state = () => host ? host.hostStateForTest() : "no host"
            if (step === 1) { console.warn("APPHOST tabs", JSON.stringify(conversation.channelTabs.map(t => ({ name: t.name, kind: t.kind, hosted: !!t.content_template })))); conversation.tab = which }
            else if (step === 6) { console.warn("APPHOST 15s", state()); shot("15s") }
            else if (step === 14) { console.warn("APPHOST 35s", state()); shot("35s") }
            else if (step === 22) { console.warn("APPHOST 55s", state()); console.warn("APPHOST menu", JSON.stringify(conversation.tabMenuForTest(which))); shot("55s") }
            else if (step === 23) conversation.tabActionForTest(which, "reloadTab")
            else if (step === 31) { console.warn("APPHOST reloaded", state()); shot("reloaded") }
            else if (step === 32) conversation.tabActionForTest(which, "expandTab")
            else if (step === 36) { console.warn("APPHOST expanded", conversation.tabExpanded, state()); shot("expanded") }
            else if (step === 37) { conversation.tabExpanded = false; const t = conversation.channelTabs.find(t => t.name === which); if (t) popped = conversation.popOutTab(t) }
            else if (step === 49 && popped) {
                const h = popped.hostedForTest()
                console.warn("APPHOST window", popped.width + "x" + popped.height, popped.title, h ? h.hostStateForTest() : "no host")
                popped.contentItem.grabToImage(r => r.saveToFile(dir + "app-host-window.png"))
            }
            else if (step === 50 && popped) { popped.close(); popped = null }
            else if (step === 51) conversation.tabActionForTest(which, "devicePermissions")
            else if (step === 53) shot("permissions")
            else if (step === 54 && Qt.application.arguments.indexOf("--app-host-stay") < 0) Qt.quit()
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
                backend.selectChat(id, ch ? ch.name : (chatList.chats.find(c => c.id === id) || { name: "OST agent test" }).name); return
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
                backend.selectChat(id, ch ? ch.name : (chatList.chats.find(c => c.id === id) || { name: "OST mention test" }).name); return
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST rename test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST menu test" }).name); return }
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
            if (step === 0 && backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST forward test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST pin test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST translate test" }).name); return }
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
            if (backend.currentChatId !== id) { backend.selectChat(id, (chatList.chats.find(c => c.id === id) || { name: "OST report test" }).name); return }
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
            id: hcFill1
            x: 251.33; y: 12.67; width: 24; height: 20; radius: 4
            color: toastClose.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
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
        zoomPercent: window.zoomPercent
        onZoomIn: window.zoomIn()
        onZoomOut: window.zoomOut()
        onZoomReset: window.zoomReset()
        readonly property var premium: backend.premiumJson ? JSON.parse(backend.premiumJson) : ({})
        premiumMode: premium.mode || (premium.starting ? "offer" : "")
        premiumDaysLeft: premium.daysLeft || 0
        onOpenPremium: kind => premiumDialog.openFor(kind)
        onOpenCast: castWindow.start()
        onOpenDownloads: downloadsFlyout.open()
        onOpenMobileApp: mobileAppDialog.open()
    }
    // Settings and more's dialogs and windows.
    PremiumDialog { id: premiumDialog; onFeedbackRequested: window.openFeedback("problem", "Teams Premium", ""); onHelpRequested: window.openHelp() }
    MobileAppDialog { id: mobileAppDialog }
    DownloadsFlyout { id: downloadsFlyout; x: window.contentItem.width - 13.33 - width; y: 60 }
    CastWindow { id: castWindow; visible: false }

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
                : "Your status message is showing in chat and channels when people message or @mention you until " + theme.dateTime(end) + "."
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
        color: theme.pick("#F5F5F5", "#292929", "#000000")
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
            Text { id: bannerActionText; anchors.centerIn: parent; text: "Change settings"; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(bannerAction, theme.text) }
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
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(bannerDismiss, theme.textStrong) }
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

    // The browser sign-in's silent renewal (Teams on the web's MSAL does the
    // same in a hidden frame): at start, then every 12 hours, well inside
    // its refresh token's 24 hours.
    WebEngineView {
        id: renewView
        visible: false
        width: 1; height: 1
        // The shared profile exists once everything is complete (WebApp).
        property bool ready: false
        Component.onCompleted: { profile = webAppsProfile.instance(); ready = true }
        url: ready && backend.renewPage ? backend.renewPage : "about:blank"
        onNavigationRequested: req => {
            const u = req.url.toString()
            if (backend.signInNavigated(u, true)) req.reject()
            else if (u.indexOf("https://") !== 0 && u !== "about:blank") req.reject()
        }
        onPermissionRequested: p => p.deny()
    }
    Timer {
        interval: 12 * 3600 * 1000; repeat: true
        running: backend.hasCredentials
        onTriggered: backend.renewSignIn()
    }
    SignIn {
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        z: 5
        visible: !backend.hasCredentials
        page: backend.signInPage
        webProfile: webAppsProfile
        busy: backend.busy
        error: backend.statusText
        onSignIn: backend.beginSignIn()
    }

    AppRail {
        id: rail
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: parent.left }
        showNames: window.appBarNames
        autoCollapse: window.appBarAutoCollapse
        split: window.splitView
        collabPane: window.collabPane
        onCollabPicked: pane => window.openCollab(pane)
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
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        suggested: backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({ query: "", items: [] })
        chats: chatList.chats
        myMri: backend.userMri
        myName: backend.userName
        onSearch: q => backend.newChatPeople(q)
        // One person you have a chat with: Teams shows that chat under the
        // To row; its own compose box sends there.
        onPreviewChat: (id, name) => { if (id && backend.currentChatId !== id) backend.selectChat(id, name) }
        onEmojiRequested: box => conversation.openEmojiFor(box)
        // The message goes from the chat's own compose box once it is open
        // (a new group chat: once it is made).
        onChosen: (oid, name, message) => {
            window.composing = false
            backend.openChatWith(oid, name)
            if (message) conversation.adoptAndSend(JSON.parse(message))
        }
        onGroup: (oids, topic, message) => { window.composing = false; window.newGroupMessage = message; backend.createGroupChat(oids, topic, "") }
        onScheduleMeetingWith: attendees => { window.composing = false; rail.current = "calendar"; calendarView.newMeetingWith(attendees, "", "") }
        onCancelled: window.composing = false
    }
    /// A new group chat's first message, sent once the chat is made.
    property string newGroupMessage: ""
    Connections {
        target: backend
        function onGroupChatCreated(id) {
            if (!window.newGroupMessage) return
            const m = JSON.parse(window.newGroupMessage)
            window.newGroupMessage = ""
            if (conversation.chatId === id) conversation.adoptAndSend(m)
            else console.warn("NEWCHAT group message not sent: chat", id, "isn't open")
        }
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

    Connections {
        target: backend
        function onCalendarActionDone(op, result, error) { calendarView.actionDone(op, result, error) }
    }
    CalendarView {
        id: calendarView
        visible: rail.current === "calendar"
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
        events: backend.calendarJson ? JSON.parse(backend.calendarJson) : []
        teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        people: backend.peopleJson ? JSON.parse(backend.peopleJson) : []
        me: ({ name: backend.userName, mail: backend.userMail, mri: backend.userMri })
        onCalendarAction: (op, args) => backend.calendarAction(op, args)
        onSearchPeople: q => backend.searchPeople(q)
        // Join with an ID: Teams' meeting link for the ID and passcode.
        onJoinWithId: (id, pass) => backend.calendarAction("joinById", JSON.stringify({ meetingId: id, passcode: pass }))
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
        visible: ["chat", "calls", "calendar", "activity", "settings", "onedrive", "planner", "people", "onenote", "add", "whiteboard", "clipchamp", "shifts", "office", "help", "communities", "search", "events"].indexOf(rail.current) < 0
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
    // Whiteboard, Shifts and Clipchamp are the apps' personal pages in
    // Teams' app host (TeamsJS), as Teams opens them from the app bar
    // (docs/spec/app-host.md "Personal apps"): Whiteboard under Teams' app
    // header, Shifts and Clipchamp full screen.
    Repeater {
        id: hostedApps
        model: [
            { key: "whiteboard", name: "Whiteboard", icon: "board-20", color: "#0F6CBD", appId: "95de633a-083e-42f5-b444-a4295d8e9314" },
            { key: "clipchamp", name: "Clipchamp", icon: "video", color: "#8764B8", appId: "com.microsoftstream.embed.skypeteamstab" },
            { key: "shifts", name: "Shifts", icon: "calendar-clock-20", color: "#5B5FC7", appId: "42f6c1da-a241-483a-a3cc-4f5be9185951" },
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
            sourceComponent: modelData.appId ? personalAppComp : webAppComp
            Component { id: webAppComp; WebApp { appName: modelData.name; appIcon: modelData.icon; appColor: modelData.color; home: modelData.url } }
            Component { id: personalAppComp; WebApp { appName: modelData.name; appId: modelData.appId; teamsHost: true; personalApp: true } }
        }
    }
    // A Word, Excel or PowerPoint file in Office for the web, as Teams'
    // "Teams" choice opens it: the Office app's page in Teams' host, full
    // screen beside the app bar, the file in its context's subEntityId
    // (api::office_open). Each file opens afresh.
    property var officeFile: null
    property string officeFrom: ""
    function openInTeams(url, name, itemJson) {
        let item = {}
        try { item = JSON.parse(itemJson || "{}") } catch (e) {}
        backend.appHostRequest("", "", "", "", "officeOpen", "office:" + Date.now(), JSON.stringify({ url: url, driveId: item.drive_id || "", itemId: item.id || "" }))
    }
    Connections {
        target: backend
        function onOpenInTeamsRequested(url, name, itemJson) { window.openInTeams(url, name, itemJson) }
        function onAppHostReply(id, json) {
            if (id.indexOf("office:") !== 0) return
            const r = JSON.parse(json)
            if (r.error) { window.showToast({ text: r.error, intent: "error" }); return }
            if (rail.current !== "office") window.officeFrom = rail.current
            window.officeFile = r
            rail.officeLabel = r.appName
            rail.openApp("office")
        }
    }
    Loader {
        id: officeView
        visible: rail.current === "office"
        active: false
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        sourceComponent: officeComp
        Component {
            id: officeComp
            WebApp {
                // The page's Close (navigateBack): back where the file was
                // opened, and the app leaves the app bar (Teams).
                onHostEvent: (name, json) => {
                    if (name !== "navigateBack") return
                    rail.opened = rail.opened.filter(k => k !== "office")
                    rail.current = window.officeFrom || "chat"
                    Qt.callLater(() => { window.officeFile = null })
                }
                appName: window.officeFile.appName; appId: window.officeFile.appId
                teamsHost: true; personalApp: true; personalFullScreen: true
                hostContext: ({ entityId: window.officeFile.entityId, subEntityId: window.officeFile.subEntityId, isFullScreen: true })
                officeSource: window.officeFile.serviceName + "." + window.officeFile.ctx
            }
        }
        // A new file: a new host.
        Connections {
            target: window
            function onOfficeFileChanged() { officeView.active = false; officeView.active = !!window.officeFile }
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
        // Teams writes "is:<tab>" for each tab but Communities (measured on
        // winpc 2026-11-13: the box keeps just the words).
        onTabChanged2: t => titleBar.setSearchText(query + (t === "all" || !window.searchTabWords[t] ? "" : " is:" + window.searchTabWords[t]))
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
    // Teams' Events app, drawn natively from the virtual events service
    // (docs/spec/events.md); made when first opened and kept.
    Loader {
        id: eventsView
        property bool opened: false
        visible: rail.current === "events"
        onVisibleChanged: if (visible) opened = true
        active: opened
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        sourceComponent: EventsView {
            onPinToggled: on => { backend.setSetting("eventsAppPinned", on ? "true" : "false"); rail.pinned = on ? ["events"] : [] }
            onViewMeetings: rail.current = "calendar"
            onToast: d => window.showToast(d)
            onJoinEvent: (url, title, start, end) => preJoin.openFor(url, title, start, end)
            onOpenEventChat: (id, title) => { rail.current = "chat"; window.composing = false; backend.selectChat(id, title) }
        }
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
        // Schedule a meeting: Teams' form with this channel filled in.
        w.scheduleMeeting.connect(() => { rail.current = "calendar"; calendarView.newChannelMeeting(w.teamId, w.teamName, w.channelId, w.channelName) })
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
    // A new or joined team: back to the chat with its first channel open
    // once the team list has it (found by thread, else group id, else
    // name: the create answer may carry neither id).
    property var pendingTeam: null
    function teamReady(groupId, threadId, created, name) {
        window.teamPage = ""
        chatList.yourTeamsOpen = false
        window.pendingTeam = { thread: threadId || "", group: groupId || "", name: name || "", created: !!created, tries: 0 }
        backend.reloadTeams()
    }
    // Teams, once a team is made (winpc 2026-11-16): "Add members to
    // {team}" with Skip / Add, then its first channel opens.
    Connections {
        target: backend
        function onTeamsJsonChanged() {
            const p = window.pendingTeam
            if (!p) return
            const t = JSON.parse(backend.teamsJson || "[]").find(t => (p.thread && t.thread_id === p.thread) || (p.group && t.id === p.group) || (!p.thread && !p.group && p.name && t.name === p.name))
            if (!t) { if (++p.tries < 6) pendingTeamRetry.restart(); return }
            window.pendingTeam = null
            const first = (t.channels || []).find(c => c.id === t.thread_id) || (t.channels || [])[0]
            backend.selectChat(t.thread_id, first ? first.name : "General")
            if (p.created) { newTeamMembers.afterCreate = true; newTeamMembers.start(t.id, t.thread_id, t.name) }
        }
    }
    Timer { id: pendingTeamRetry; interval: 3000; onTriggered: if (window.pendingTeam) backend.reloadTeams() }
    AddMembersDialog { id: newTeamMembers; onClosed: afterCreate = false }
    function newTeamMembersForTest() { return newTeamMembers }
    CreateTeamDialog {
        id: createTeamDialog
        onMoreOptions: window.openTeamPage("create")
        onCreated: (g, t) => window.teamReady(g, t, true, createTeamDialog.lastName)
    }
    CreateTeamPage {
        id: createTeamPage
        visible: window.teamPage === "create" && rail.current === "chat"
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: rail.right; right: parent.right }
        onBack: window.teamPage = ""
        onTeamCreated: (g, t) => window.teamReady(g, t, true)
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
        pane: window.splitView ? window.collabPane : "combined"
        enterToOpen: window.enterToShow
        singlePointReordering: window.singlePointReordering
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
        // The new chat form selects nothing but its own row.
        currentId: window.composing ? "" : backend.currentChatId
        onChatSelected: (id, name) => { window.composing = false; copilotOpen = false; draftsOpen = false; mentionsOpen = false; quickOpen = ""; window.manage = null; window.manageTeamId = ""; yourTeamsOpen = false; backend.selectChat(id, name) }
        onNewChat: { copilotOpen = false; draftsOpen = false; mentionsOpen = false; yourTeamsOpen = false; window.startNewChat() }
        onOpenCopilot: { window.composing = false; draftsOpen = false; mentionsOpen = false; yourTeamsOpen = false; quickOpen = ""; window.manage = null; window.manageTeamId = ""; copilotOpen = true }
        onOpenYourTeams: window.openYourTeams("teams")
        onOpenChatWindow: (id, name, photo, presence) => window.openChatWindow(id, name, photo, presence)
        onManageChatApps: (id, name) => { window.composing = false; draftsOpen = false; mentionsOpen = false; window.manage = null; window.manageTeamId = ""; yourTeamsOpen = false; if (backend.currentChatId !== id) backend.selectChat(id, name); conversation.manageApps = true }
        onChatWorkflows: (id, name) => workflowsDialog.startChat(id, name)
        onMarkAllRead: appType => backend.markAllRead(appType)
        onCustomizeView: { window.composing = false; rail.current = "settings" }
        windowWidth: window.width
        composing: window.composing
        onOpenComposing: window.composing = true
        draftIds: (backend.draftsJson ? JSON.parse(backend.draftsJson) : []).map(d => d.id)
        onOpenDrafts: { window.composing = false; copilotOpen = false; mentionsOpen = false; yourTeamsOpen = false; quickOpen = ""; draftsOpen = true }
        hasMentions: mentionsView.mentions.length > 0
        onOpenMentions: { window.composing = false; copilotOpen = false; draftsOpen = false; yourTeamsOpen = false; quickOpen = ""; mentionsOpen = true; mentionsView.selectedId = "" }
        onOpenQuick: kind => { window.composing = false; copilotOpen = false; draftsOpen = false; mentionsOpen = false; yourTeamsOpen = false; window.manage = null; window.manageTeamId = ""; quickOpen = kind; quickView.selectedKey = "" }
        onOpenCommunities: rail.openApp("communities")
    }
    // Copilot from the chat list's top row, as Teams hosts it (docs/spec/
    // app-host.md "Copilot"): the Microsoft 365 Copilot app (b5abf2ae…)'s
    // personal page in Teams' app host beside the list, full screen and
    // server-rendered (Teams posts its first page the app's token), with
    // Teams' launch payload for the list's entry point.
    Loader {
        id: copilotView
        property bool opened: false
        visible: rail.current === "chat" && chatList.copilotOpen
        onVisibleChanged: if (visible) opened = true
        active: opened
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        sourceComponent: WebApp {
            appName: "Copilot"; appId: "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162"
            teamsHost: true; personalApp: true; ssr: true
            runtimeSupports: ({ appPerformanceMetrics: {}, copilot: { eligibility: {} } })
            frameAllow: "clipboard-write *; media-playback-while-not-visible 'none'; local-network-access *; display-capture *;"
            hostContext: ({ subEntityId: JSON.stringify({ hostSettings: { enableDeeplinks: "true", focusOnLoad: "Compose" },
                launchOptionPayload: Qt.btoa(JSON.stringify({ id: "", scenario: "Default", chatType: "", properties: {}, version: 1, referral: { cmmid: "cmmnxawun8n" },
                    callerInfo: { scope: "None", entryPoint: "SimpleCollabList" }, serverVariants: [] })) }) })
        }
    }
    // Another chat opened from anywhere closes Copilot's page.
    Connections { target: backend; function onCurrentChatIdChanged() { chatList.copilotOpen = false } }
    MentionsView {
        id: mentionsView
        visible: rail.current === "chat" && chatList.mentionsOpen
        anchors { top: appBanner.bottom; bottom: statusBar.top; left: chatList.right; right: parent.right }
        items: backend.activityJson ? JSON.parse(backend.activityJson) : []
        myName: backend.userName
        enterToOpen: window.enterToShow
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
        enterToOpen: window.enterToShow
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
        onFeedbackRequested: (kind, area, context) => window.openFeedback(kind, area, context)
        myPresence: titleBar.presence
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right; right: parent.right }
    }
    ActivityView {
        id: activityView
        visible: rail.current === "activity"
        anchors { top: appBanner.bottom; bottom: parent.bottom; left: rail.right }
        items: backend.activityJson ? JSON.parse(backend.activityJson) : []
        enterToOpen: window.enterToShow
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
        onManageApps: window.manageConversationApps(agentStore.channel)
    }
    // Manage your apps from an in-context Store: the chat's apps, or the
    // channel's team's.
    function manageConversationApps(channel) {
        if (channel && conversation.teamId) window.openManageTeam(conversation.teamId, "apps")
        else conversation.manageApps = true
    }
    // Teams' Add a tab (the header's "+"): the picker, then the app's tab
    // configuration (Back returns to the picker).
    AgentStore {
        id: tabPicker
        onOpenApp: id => { tabPicker.close(); appDetails.show(id, { id: tabPicker.conversationId, channel: tabPicker.channel }) }
        onGetMoreApps: rail.current = "add"
        onManageApps: window.manageConversationApps(tabPicker.channel)
        onPickTabApp: app => {
            tabPicker.close()
            tabConfig.start(app, tabPicker.conversationId, tabPicker.channel ? conversation.teamId : "", tabPicker.channel)
        }
    }
    TabConfigDialog {
        id: tabConfig
        onBack: tabPicker.reopen()
        onAbout: app => tabConfigAbout.start({ app_id: app.id, name: app.name })
    }
    TabAboutDialog { id: tabConfigAbout }
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
        // Sent from a chat shown in the new chat form: the form is done.
        onComposeSent: if (window.composing) window.composing = false
        onToastRequested: d => window.showToast(d)
        onOpenFileRequested: f => fileViewer.show(f)
        onOpenAppDetails: id => appDetails.show(id)
        onShareApp: id => appShare.start(id)
        // Meeting details: the meeting in the calendar.
        onOpenMeetingDetails: (url, ical, start) => { rail.current = "calendar"; calendarView.showMeeting(url, ical, start) }
        onOpenAppById: id => window.openAppById(id, "")
        onOpenAgentStore: (id, isChannel) => agentStore.show(id, isChannel)
        onOpenTabPicker: (id, kind, team) => tabPicker.showTabs(id, kind, team)
        teamThread: {
            const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
            const t = teams.find(t => t.channels.some(c => c.id === backend.currentChatId))
            return t ? (t.thread_id || "") : ""
        }
        // A channel's Meet now: Teams' pre-join, titled for the channel.
        onChannelMeetNow: preJoin.openMeetNow(conversation.chatId, "Meeting in \"" + conversation.chatName + "\"")
        onOpenChannelWindow: id => window.openChannelWindow(id)
        onChannelWorkflows: id => window.openWorkflows(id)
        onManageChannel: id => window.openManageChannel(id)
        myName: backend.userName
        visible: (rail.current === "chat" && !chatList.draftsOpen && !chatList.copilotOpen && (!chatList.mentionsOpen || mentionsView.selectedId.length > 0) && (!chatList.quickOpen || quickView.selectedKey.length > 0) && !manageChannel.visible && !manageTeam.visible && !yourTeams.visible && !window.teamPage)
            || (rail.current === "activity" && activityView.selectedId.length > 0)
        chatId: backend.currentChatId
        anchors { top: appBanner.bottom; bottom: statusBar.top; right: findPane.left
            left: conversation.tabExpanded || conversation.channelAttendance ? rail.right : rail.current === "activity" ? activityView.right : chatList.right
            leftMargin: rail.current === "chat" && (chatList.mentionsOpen || !!chatList.quickOpen) ? mentionsView.paneWidth : 0 }
        chatName: backend.currentChatName
        // A group chat you left (Teams keeps it listed): its roster without
        // you, the box disabled with Teams' words.
        readonly property bool notMember: { const m = backend.chatMembersJson ? JSON.parse(backend.chatMembersJson) : []; return m.length > 0 && !m.some(x => x.me) && backend.currentChatId.endsWith("@thread.v2") }
        composeDisabled: notMember
        composeDisabledText: notMember ? "You can't send messages because you are not a member of the chat." : ""
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
        onOpenPrivacySettings: { settingsView.page = "privacy"; rail.current = "settings" }
        // A suggested reply's meeting: Teams' scheduling form for the chat.
        onScheduleMeetingWith: (attendees, startIso, endIso) => { rail.current = "calendar"; calendarView.newMeetingWith(attendees, startIso, endIso) }
        // From a channel's header: the form with the channel filled in.
        onScheduleMeeting: {
            rail.current = "calendar"
            if (conversation.isChannel) {
                const ch = (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).reduce((a, t) => a.concat(t.channels || []), []).find(c => c.id === conversation.chatId)
                calendarView.newChannelMeeting(conversation.teamId, conversation.teamName, conversation.chatId, ch ? ch.name : backend.currentChatName)
            } else calendarView.newMeeting()
        }
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
