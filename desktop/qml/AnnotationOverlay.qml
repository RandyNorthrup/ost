import QtQuick
import QtQuick.Window

// Teams' annotation window while you annotate your shared screen
// (annotation-app's CallingAnnotationContainer; docs/spec/content-sharing.md
// §4): a transparent, frameless, always-on-top window over the whole
// screen, kept out of what's shared, hosting Whiteboard's annotation board
// (screenSharer=1, the shared screen's size). Whiteboard's toolbar asks for
// "click-through" (startClickThroughMode [toolbar]): then only its toolbar
// takes the pointer and the rest goes to the windows below, as Teams'
// window shrinking to the toolbar does.
Window {
    id: win
    title: "OST annotation"
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    /// The board's address with Teams' parameters.
    property string frameUrl: ""
    property string thread: ""
    property string meetingTitle: ""
    signal boardReported(string url, var passThrough)
    property bool layered: false
    Component.onCompleted: {
        const s = screen || Qt.application.screens[0]
        x = s.virtualX; y = s.virtualY; width = s.width; height = s.height
        layered = backend.prepareAnnotationOverlay(title)
    }
    onVisibleChanged: if (visible) { backend.excludeWindowFromCapture(title); backend.setWindowInputRegion(title, 0, 0, 0, 0) }
    WebApp {
        id: board
        anchors.fill: parent
        transparentPage: true
        showHeader: false
        appName: "Whiteboard"
        appId: "95de633a-083e-42f5-b444-a4295d8e9314"
        location: win.meetingTitle
        home: win.frameUrl
        teamsHost: true
        deepNaa: false
        frameContext: "meetingStage"
        hostThread: win.thread
        hostContext: ({ entityId: "", subEntityId: "" })
        onHostEvent: (name, json) => {
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            if (name === "whiteboardUrl" && r.url) win.boardReported(r.url, r.passThrough)
            // Whiteboard's click-through: only its toolbar keeps the pointer.
            else if (name === "startClickThroughMode") {
                const t = r.toolbar || {}
                backend.setWindowInputRegion(win.title, Math.round(t.x || 0), Math.round(t.y || 0), Math.round(t.width || 0), Math.round(t.height || 0))
            } else if (name === "stopClickThroughMode") backend.setWindowInputRegion(win.title, 0, 0, 0, 0)
        }
    }
}
