import QtQuick

// A content-sharing session on the meeting stage, as Teams' stage shows it
// (docs/spec/content-sharing.md): Microsoft Whiteboard (whiteboard-renderer:
// the board's Whiteboard page as a TeamsJS app in the meetingStage frame
// context, measured 2026-11-18 at 1029 x 541 in a 1035-wide stage beside
// the side gallery), PowerPoint Live (PowerPoint for the web's slide show)
// and Excel Live (Excel's meeting stage page). Presenter and viewers host
// the same page; the presenter's frame reports the board, viewers get it
// from the session's state.
Item {
    id: root
    /// The session (content_sharing::Session as JSON).
    property var session: null
    /// The presenter's own board address (call_content_json's board).
    property string board: ""
    /// Teams' meetingType for the call (content_sharing::meeting_type).
    property int meetingType: 0
    property string thread: ""
    property string title: ""
    readonly property bool mine: !!session && !!session.mine
    readonly property string kind: session && session.content ? (session.content.type || "") : ""
    readonly property var stateObj: {
        if (!session || !session.state) return ({})
        try { return JSON.parse(session.state) || ({}) } catch (e) { return ({}) }
    }
    /// The board Whiteboard reported (presenter): the call window sends it
    /// to the session and keeps it for the meeting.
    signal boardReported(string url, var passThrough)

    // The frame's address: the session's board with Teams' stage
    // parameters (89637 `Tm`: meetingType, meetingTenantId, and a viewer's
    // participantTimestamp), then the renderer's.
    function frameUrl() {
        if (kind === "whiteboard" || kind === "annotation") {
            // A viewer waits for the presenter's board (the state's url),
            // with the session's own parameters added (Teams'
            // appendSearchParams): opening the session's address alone
            // would start a new board.
            let base = mine ? (board || (session.content.url || "")) : (stateObj.url || "")
            if (!base) return ""
            if (!mine && session.content.url) {
                const have = {}
                const q = base.indexOf("?")
                if (q >= 0) base.slice(q + 1).split("&").forEach(p => have[p.split("=")[0]] = true)
                const cu = String(session.content.url)
                const cq = cu.indexOf("?")
                const extra = cq < 0 ? [] : cu.slice(cq + 1).split("&").filter(p => p && !have[p.split("=")[0]])
                if (extra.length) base += (q >= 0 ? "&" : "?") + extra.join("&")
            }
            const extra = { meetingType: String(meetingType), meetingTenantId: backend.tenantId() }
            if (!mine) extra.participantTimestamp = String(Date.now())
            return backend.contentBoardFrameUrl(base, mine, JSON.stringify(extra))
        }
        // Excel Live (calling-app): the session's page without its
        // subEntityId (that goes in the TeamsJS context), with isPresenter
        // and shareToStageId.
        if (kind === "extensible_app") {
            const u = String(session.content.url || "")
            if (!u) return ""
            const q = u.indexOf("?")
            const params = q < 0 ? [] : u.slice(q + 1).split("&").filter(p => p.split("=")[0] !== "subEntityId")
            params.push("isPresenter=" + (mine ? "true" : "false"), "shareToStageId=" + encodeURIComponent(session.sessionId || ""))
            return (q < 0 ? u : u.slice(0, q)) + "?" + params.join("&")
        }
        return ""
    }
    readonly property string excelSubEntity: {
        if (kind !== "extensible_app") return ""
        const m = /[?&]subEntityId=([^&]*)/.exec(String(session.content.url || ""))
        return m ? decodeURIComponent(m[1]) : ""
    }
    readonly property string excelContext: {
        if (kind !== "extensible_app") return ""
        let c = {}
        try { c = JSON.parse(session.content.extensibleAppContext || "{}") } catch (e) {}
        if (stateObj.extensibleAppContext) c = Object.assign(c, stateObj.extensibleAppContext)
        c.correlationId = session.correlationId
        return JSON.stringify(c)
    }
    // Excel Live: the session's context goes to the app whenever it changes
    // (Teams' onExtensibleAppContextChanged, first when the page loads).
    function pushExcelContext() {
        if (kind === "extensible_app" && boardLoader.item && excelContext)
            boardLoader.item.sendFrameMessage("onExtensibleAppContextChanged", [excelContext])
    }
    onExcelContextChanged: pushExcelContext()
    // The board's address for viewers who already loaded the frame:
    // Teams' whiteboardUrlChanged [url, passThrough].
    property string sentUrl: ""
    /// The address the frame loaded (later boards are posted to it).
    property string loadedUrl: ""
    function pushBoard(force) {
        if (mine || !boardLoader.item || !stateObj.url || (stateObj.url === sentUrl && !force)) return
        sentUrl = stateObj.url
        boardLoader.item.sendFrameMessage("whiteboardUrlChanged", stateObj.passThrough !== undefined && stateObj.passThrough !== null
                                          ? [stateObj.url, stateObj.passThrough] : [stateObj.url])
    }
    onStateObjChanged: pushBoard()

    Rectangle { anchors.fill: parent; color: theme.surface; radius: 4 }
    Loader {
        id: boardLoader
        anchors.fill: parent
        // One frame per session (a new session reloads).
        property string key: root.session ? root.session.correlationId + ":" + root.kind : ""
        onKeyChanged: { active = false; root.sentUrl = ""; root.loadedUrl = key !== "" ? root.frameUrl() : ""; active = root.loadedUrl !== "" }
        active: false
        sourceComponent: WebApp {
            showHeader: false
            appName: root.kind === "extensible_app" ? "Excel" : "Whiteboard"
            appId: root.kind === "extensible_app" ? "1c256a65-83a6-4b5c-9ccf-78f8afb6f1e8" : "95de633a-083e-42f5-b444-a4295d8e9314"
            location: root.title
            home: root.loadedUrl
            teamsHost: true
            deepNaa: false
            frameContext: "meetingStage"
            hostThread: root.thread
            hostContext: ({ entityId: "", subEntityId: root.excelSubEntity })
            extensibleAppContext: root.excelContext
            onHostEvent: (name, json) => {
                if (name === "whiteboardUrl" && root.mine) {
                    let r = {}
                    try { r = JSON.parse(json) } catch (e) {}
                    if (r.url) root.boardReported(r.url, r.passThrough)
                } else if (name === "readyForUrl") root.pushBoard(true)
                else if (name === "appLoaded" || name === "success") root.pushExcelContext()
            }
        }
    }
    // PowerPoint Live: PowerPoint for the web's slide show.
    property string presenterName: ""
    property int attendees: 1
    property string pptLayout: "ContentOnly"
    property string pptCameoKey: ""
    /// The deck PowerPoint shows has a cameo.
    readonly property bool pptCameoDetected: pptLoader.item ? pptLoader.item.cameoDetected : false
    signal pptNavigated(string state)
    /// Test hook: the presenter's next slide (Teams' Next).
    function pptNextForTest() { if (pptLoader.item) pptLoader.item.next() }
    Loader {
        id: pptLoader
        anchors.fill: parent
        property string key: root.kind === "ppt" && root.session ? root.session.correlationId : ""
        onKeyChanged: { active = false; active = key !== "" }
        active: false
        sourceComponent: PptLiveStage {
            session: root.session
            presenterName: root.presenterName
            attendees: root.attendees
            layout: root.pptLayout
            cameoKey: root.pptCameoKey
            onNavigated: state => root.pptNavigated(state)
            onTakeControlRequested: backend.contentTakeControl(root.session.correlationId)
        }
    }
    // Teams' "Loading…" while the session has no board yet.
    Text {
        visible: !boardLoader.active && !pptLoader.active
        anchors.centerIn: parent
        text: root.session ? "Loading…" : ""
        color: theme.textSecondary
        font.family: theme.font; font.pixelSize: 14
    }
    Connections {
        target: root
        function onBoardChanged() { if (!boardLoader.active && boardLoader.key !== "" && root.frameUrl() !== "") { root.loadedUrl = root.frameUrl(); boardLoader.active = true } }
        function onSessionChanged() { if (!boardLoader.active && boardLoader.key !== "" && root.frameUrl() !== "") { root.loadedUrl = root.frameUrl(); boardLoader.active = true } }
    }
}
