import QtQuick
import QtWebEngine
import QtWebChannel

// PowerPoint Live on the stage (docs/spec/content-sharing.md §3): PowerPoint
// for the web's slide show (presenter view for the presenter, the slide for
// attendees) in a page of OST's own, which does what Teams' bundled
// PowerPoint bootstrapper does (ppt_host.js). The presenter's slide moves go
// out as the session's state ("Nav"); attendees follow them.
Item {
    id: root
    property var session: null
    property string presenterName: ""
    property int attendees: 1
    property string layout: "ContentOnly"
    /// The deck has a cameo (PowerPoint's CameoDetectedInPresentation).
    property bool cameoDetected: false
    /// Cameo's picture (a video frame key: "self" or the presenter's).
    property string cameoKey: ""
    readonly property bool cameoOn: started && layout === "Cameo" && cameoKey !== ""
    function updateCameo() { bridge.cameo(cameoOn ? JSON.stringify({ url: backend.cameoSocket(), key: cameoKey }) : "{}") }
    onCameoOnChanged: updateCameo()
    onCameoKeyChanged: if (cameoOn) updateCameo()
    readonly property bool mine: !!session && !!session.mine
    /// The presenter moved to a slide: Teams' Nav state (89637
    /// sendSessionUpdateInternal), as the session's new state.
    signal navigated(string state)
    function guid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16) })
    }
    property string channelJs: ""
    property var lastNav: null
    readonly property var stateObj: {
        if (!session || !session.state) return null
        try { return JSON.parse(session.state) } catch (e) { return null }
    }
    // Attendees follow the presenter's updates (not their own): Nav moves
    // the slide, DryInk draws the presenter's ink (Teams'
    // handleInboundNewDryInkEventUpdate → SetAnnotation).
    onStateObjChanged: {
        const s = stateObj
        if (mine || !s) return
        if (s.requestingParticipantId && s.requestingParticipantId === bridge.participantId) return
        if (s.newDryInkEvent && (s.updateType === "DryInk" || s.updateType === undefined)) setAnnotation(s.newDryInkEvent)
        if (s.slideIndex === undefined || (s.updateType && s.updateType !== "Nav")) return
        bridge.goToSlide(JSON.stringify({ slideIndex: s.slideIndex, timeLineMappings: s.timeLineMappings || [], metadata: s.metadata || null }))
    }
    onLayoutChanged: bridge.layoutChanged(layout)
    /// Someone's ink, laser or cursor into our slide show (Teams'
    /// SetAnnotation, m_type 53 down).
    function setAnnotation(a) {
        if (!a || a.eventType === undefined) return
        bridge.command(JSON.stringify({ m_type: 53, m_eventType: a.eventType, m_slideID: a.slideID, m_strokeID: a.strokeID,
                                        m_eventJson: a.eventJson, m_metadata: a.metadata || null }))
    }
    // The presenter's pointer, from their LiveInking messages.
    Connections {
        target: backend
        function onContentInking(from, data) {
            if (root.mine || from === bridge.participantId) return
            let a = null
            try { a = JSON.parse(data) } catch (e) { return }
            root.setAnnotation(a)
        }
    }
    // Control changed hands (Take control): PowerPoint switches roles in
    // place (Teams' updateWRSViewingNavigation: SetNavigationOptions and
    // SwitchRole), and a new presenter sends where it stands as a Nav.
    property bool started: false
    onMineChanged: {
        if (!started) return
        bridge.command(JSON.stringify({ m_type: 31, m_enableAdvanceOnClick: mine, m_enableKeyboardNavigation: mine }))
        bridge.command(JSON.stringify({ m_type: 34, m_role: mine ? 1 : 0 }))
        if (mine) { lastNav = null; bridge.command(JSON.stringify({ m_type: 3 })) }
    }
    /// Teams' takeControlPptBtn: ask for the session.
    signal takeControlRequested()
    property int annotationSeq: 0
    function presenterAnnotation(json) {
        let a = {}
        try { a = JSON.parse(json) } catch (e) { return }
        const t = a.eventType
        // Dry ink (added, erased, all erased on a slide) goes out in the
        // session state; the pointer (laser 6–9, cursor 12–13) as LiveInking.
        if (t === 0 || t === 1 || t === 2) {
            const p = root.lastNav || {}
            const stateId = root.guid()
            root.navigated(JSON.stringify({ stateId: stateId, causeId: root.guid(), updateType: "DryInk", requestingParticipantId: bridge.participantId,
                slideIndex: p.slideIndex || 0, timeLineMappings: p.timeLineMappings || [], privateViewingEnabled: false,
                newDryInkEvent: a, presentationUrlEvent: { presentationUrl: "" },
                metadata: Object.assign({}, p.metadata || {}, { PresenterId: bridge.participantId, StateId: stateId }), mediaStates: [] }))
        } else if (t >= 6 && t <= 9 || t === 12 || t === 13) backend.contentSendInking(json)
    }

    QtObject {
        id: bridge
        WebChannel.id: "ost"
        property string config: ""
        property string participantId: ""
        signal goToSlide(string json)
        signal layoutChanged(string mode)
        signal token(string resource, string token)
        signal command(string json)
        signal cameo(string json)
        function event(name, json) {
            if (name !== "annotation") console.info("PPTLIVE " + name)
            if (name === "ready") root.started = true
            if (name === "cameoDetected") { try { root.cameoDetected = !!JSON.parse(json).detected } catch (e) {} return }
            if (name === "annotation") { if (root.mine) root.presenterAnnotation(json); return }
            if (name === "takeControl") { if (!root.mine) root.takeControlRequested(); return }
            // A new presenter's position (asked when control came to us).
            if (name === "currentPosition" && root.mine && !root.lastNav) name = "position"
            if (name === "position" && root.mine) {
                let p = {}
                try { p = JSON.parse(json) } catch (e) {}
                if (root.lastNav && root.lastNav.slideIndex === p.slideIndex && JSON.stringify(root.lastNav.timeLineMappings) === JSON.stringify(p.timeLineMappings)) return
                root.lastNav = p
                const stateId = root.guid()
                root.navigated(JSON.stringify({ stateId: stateId, causeId: root.guid(), updateType: "Nav", requestingParticipantId: bridge.participantId,
                    slideIndex: p.slideIndex, timeLineMappings: p.timeLineMappings || [], privateViewingEnabled: false,
                    presentationUrlEvent: { presentationUrl: "" },
                    metadata: Object.assign({}, p.metadata || {}, { PresenterId: bridge.participantId, StateId: stateId }), mediaStates: [] }))
            } else if (name === "error") console.warn("PPTLIVE error " + json)
        }
        function log(t) { console.info("PPTLIVE " + t) }
    }
    WebChannel { id: channel; registeredObjects: [bridge] }
    WebEngineView {
        id: web
        anchors.fill: parent
        backgroundColor: "transparent"
        settings.localContentCanAccessRemoteUrls: false
        // Cameo: the slide show plays the camera's stream in a video element of its own
        // (not muted, no click first), as Teams' WebView2 lets it; Chromium's default
        // gesture rule fails that play() (ErrorVideoPlaybackFailed).
        settings.playbackRequiresUserGesture: false
        webChannel: channel
        webChannelWorld: WebEngineScript.ApplicationWorld
        property bool hostLoading: false
        onLoadingChanged: req => {
            if (hostLoading && req.status === WebEngineView.LoadSucceededStatus) {
                hostLoading = false
                web.runJavaScript(root.channelJs + "\n" + backend.pptHostScript(), WebEngineScript.ApplicationWorld)
            }
        }
        onNavigationRequested: req => {
            const u = req.url.toString()
            if (hostLoading && req.isMainFrame) return
            if (!req.isMainFrame && /^(about:|blob:|data:)/.test(u)) return
            if (u.indexOf("https://") !== 0 && u !== "about:blank") req.reject()
        }
        onPermissionRequested: p => p.deny()
    }
    /// The next slide or step (Teams' Next).
    function next() { bridge.command(JSON.stringify({ m_type: 5 })) }
    function start() {
        if (!session || !channelJs) return
        const cfg = backend.contentPptConfig(JSON.stringify(session), presenterName, attendees, theme.dark)
        try { bridge.participantId = JSON.parse(cfg).participantId || "" } catch (e) {}
        bridge.config = cfg
        web.hostLoading = true
        web.loadHtml("<!doctype html><html lang=\"en-us\"><head><meta charset=\"utf-8\"><title>PowerPoint Live</title>"
                     + "<style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent}</style></head><body></body></html>",
                     "https://teams.microsoft.com/")
    }
    Component.onCompleted: {
        web.profile = webAppsProfile.instance()
        // Cameo's camera in PowerPoint's frame (the host-provided stream).
        const cs = WebEngine.script()
        cs.name = "ost-cameo-stream"
        cs.sourceCode = backend.pptCameoStreamScript()
        cs.injectionPoint = WebEngineScript.DocumentCreation
        cs.worldId = WebEngineScript.MainWorld
        cs.runsOnSubFrames = true
        web.userScripts.insert(cs)
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            // The stage may be gone by the time the file arrives (the
            // presentation ended at once).
            if (!root || typeof root.start !== "function") return
            root.channelJs = x.responseText
            root.start()
        }
        x.open("GET", "qrc:///qtwebchannel/qwebchannel.js")
        x.send()
    }
}
