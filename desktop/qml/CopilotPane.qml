import QtQuick
import QtQuick.Controls.Basic

// Copilot beside a chat or a channel thread (Teams' Open Copilot in their
// headers, TASK-0260; measured on winpc 2026-11-23 with ost-test1's
// Microsoft 365 Copilot licence):
// - Teams' end pane, 360 wide with a 0.67 px line on its left: a 61 tall
//   white header (the Copilot mark, 20 px at 24.7; "Copilot" 14/600 at
//   49.7; Close Copilot, 32 x 31.3, 56 from the right, 14.5 down) over a
//   0.67 px #E0E0E0 line, then the Microsoft 365 Copilot app (its
//   copilotSidePanel surface) filling the rest.
// - The app itself draws its greeting, the suggested prompts ("Summarize
//   this chat", "Recap the meeting", …), the answers with their Sources,
//   copy, thumbs and "AI-generated content may be incorrect"; the host
//   tells it which conversation it reads once it is up (ChatReady:
//   contextualChatChanged and updateCapabilities) and opens what it links
//   to (a Source is a message link the host jumps to).
// `request` is what the backend's "chatCopilot" needs: kind ("chat",
// "channel" or "meeting") and the conversation; a new request (another
// conversation) starts the app again.
Rectangle {
    id: pane
    property bool open: false
    property var request: null
    /// Hide the pane's own header (an expanded thread's pane has it below
    /// the thread's header).
    property bool headerShown: true
    signal closed()
    /// A link the app opened (Sources jump to their messages).
    signal openLink(string url)
    property var launch: null
    property string requested: ""
    /// Ask Copilot on a message ({id, promptText, text, chatId}, and for a
    /// channel's post view `channel` {channelId, teamId, groupId,
    /// replyChainId, tenantId}): handed to the app as Teams' processPromptInput
    /// does (830567: the frame's updatePromptInputData with the prompt, not
    /// a draft, and the message as a client-annotated Chat annotation, or
    /// in a channel a Channel one naming the channel, team, group, reply
    /// chain and tenant), once it is up.
    property var ask: null
    property var askSent: null
    property bool appReady: false
    function askFitsRequest(a) {
        const r = pane.request
        if (!r) return false
        if (a.channel) return !!r.thread && r.thread.channelId === a.channel.channelId && r.thread.replyChainId === a.channel.replyChainId
        return r.chat === a.chatId
    }
    function sendAsk() {
        const a = pane.ask
        // Only into the conversation it was asked in.
        if (!a || !app.item || !pane.appReady || pane.askSent === a.id || !askFitsRequest(a)) return
        pane.askSent = a.id
        const now = Date.now()
        const ref = "teams-msg-" + Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2) + "-" + now
        const selected = { selectedContents: [{ "@type": "Text", selectedContent: a.text }] }
        const c = a.channel
        const annotation = c
            ? { queryAnnotationType: "Channel", id: c.channelId, text: a.text, messageAnnotationSource: "ClientAnnotated",
                messageAnnotationMetadata: Object.assign({ "@type": "Channel", channelId: c.channelId, teamId: c.teamId },
                    c.groupId ? { groupId: c.groupId } : {}, c.replyChainId ? { replyChainId: c.replyChainId } : {},
                    c.tenantId ? { tenantId: c.tenantId } : {}, { selectedContentContext: selected }) }
            : { queryAnnotationType: "Chat", id: a.chatId, text: a.text, messageAnnotationSource: "ClientAnnotated",
                messageAnnotationMetadata: { "@type": "Chat", selectedContentContext: selected } }
        app.item.sendFrameMessage("updatePromptInputData", [{
            promptText: a.promptText, isDraft: false, promptTimestamp: now,
            rawEntityData: [{ type: "Chat", data: { id: c ? c.channelId : a.chatId, referenceId: ref, name: a.text } }],
            queryAnnotations: [annotation]
        }])
        console.info("COPILOTPANE ask sent", c ? "channel" : "chat")
    }
    onAskChanged: Qt.callLater(sendAsk)
    readonly property string tag: "copilotpane-" + Math.floor(Math.random() * 1e9).toString(36)
    color: theme.surface
    visible: open

    function load() {
        const key = open && request ? JSON.stringify(request) : ""
        if (key === requested) return
        requested = key
        launch = null
        appReady = false
        if (!key) return
        const theme_ = theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
        backend.eventsRequest("chatCopilot", tag, JSON.stringify(Object.assign({ theme: theme_ }, request)))
        console.info("COPILOTPANE launch", request.kind || "chat")
    }
    onOpenChanged: load()
    onRequestChanged: Qt.callLater(load)
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id !== pane.tag) return
            let v = null
            try { v = JSON.parse(json) } catch (e) { v = null }
            pane.launch = v && !v.error ? v : null
            console.info("COPILOTPANE", v && !v.error ? "ready" : "failed " + (v ? v.error : ""))
        }
    }

    Rectangle { z: 3; width: 0.67; height: parent.height; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
    Rectangle {
        id: header
        visible: pane.headerShown
        x: 0.67; width: parent.width - 0.67; height: pane.headerShown ? theme.headerHeight : 0
        color: theme.surface
        FluentIcon { x: 24; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "copilot-color-48"; color: theme.text }
        Text {
            x: 49; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Copilot")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            id: closeButton
            x: parent.width - 56; y: 14.5; width: 32; height: 31.3; radius: theme.radius
            color: closeHover.hovered ? theme.hover : "transparent"
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pane.closed() }
            FluentIcon { anchors.centerIn: parent; size: 20; name: closeHover.hovered ? "dismiss-20-filled" : "dismiss-20"; color: theme.onFill(closeButton, theme.textStrong) }
            ToolTip.visible: closeHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Close Copilot")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close Copilot")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
    }
    BusyIndicator { anchors.centerIn: parent; running: pane.open && !pane.launch; visible: running }
    Loader {
        id: app
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 0.67 }
        active: pane.open && !!pane.launch
        onActiveChanged: if (!active) pane.appReady = false
        sourceComponent: WebApp {
            showHeader: false; teamsHost: true; deepNaa: true
            appName: "Copilot"; appId: "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162"
            frameContext: "sidePanel"
            // (As Teams hosts the app in a side pane: server-rendered, with
            // the Copilot eligibility, performance and mouse relay
            // capabilities.)
            ssr: true
            runtimeSupports: ({ appPerformanceMetrics: {}, copilot: { eligibility: {} }, mouseRelay: {} })
            // (Teams gives the pane's app a context with no conversation:
            // chatId, channelId and the team site empty, the tenant's
            // SharePoint host; measured 2026-11-23, TASK-0263. The
            // conversation goes in contextualChatChanged.)
            hostThread: ""
            hostContext: pane.launch.context
            home: pane.launch.url
            onHostEvent: (name, json) => {
                if (name === "ChatReady") {
                    sendFrameMessage("contextualChatChanged", [pane.launch.contextualChat])
                    sendFrameMessage("updateCapabilities", [pane.launch.capabilities])
                    pane.appReady = true
                    pane.sendAsk()
                } else if (name === "openLink") {
                    let u = ""
                    try { u = JSON.parse(json).url || "" } catch (e) { u = "" }
                    if (u) pane.openLink(u)
                }
            }
        }
    }
    function appForTest() { return app.item }
}
