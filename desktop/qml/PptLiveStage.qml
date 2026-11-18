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
    // Attendees follow the presenter's Nav updates (not their own).
    onStateObjChanged: {
        const s = stateObj
        if (mine || !s || s.slideIndex === undefined) return
        if (s.requestingParticipantId && s.requestingParticipantId === bridge.participantId) return
        bridge.goToSlide(JSON.stringify({ slideIndex: s.slideIndex, timeLineMappings: s.timeLineMappings || [], metadata: s.metadata || null }))
    }
    onLayoutChanged: bridge.layoutChanged(layout)

    QtObject {
        id: bridge
        WebChannel.id: "ost"
        property string config: ""
        property string participantId: ""
        signal goToSlide(string json)
        signal layoutChanged(string mode)
        signal token(string resource, string token)
        signal command(string json)
        function event(name, json) {
            console.info("PPTLIVE " + name)
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
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            root.channelJs = x.responseText
            root.start()
        }
        x.open("GET", "qrc:///qtwebchannel/qwebchannel.js")
        x.send()
    }
}
