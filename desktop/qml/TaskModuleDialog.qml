import QtQuick
import QtQuick.Controls.Basic

// Teams' dialog for an app's page (task module, data-tid
// task-module-dialog), measured in Teams on the web 2026-11-16 for the
// Workflows dialog (docs/spec/app-host.md):
// - the taskInfo's width (900 there), radius 8, Teams' dialog shadow, 27
//   above the header;
// - the header (taskModuleHeader), 55.3 tall, padding 0 32: the app's
//   32 px icon (radius 28.56%, on #FAFAFA) at 32 and 11.7 down, the title
//   (h1, 20/28.57 bold) at 76; Close (32 x 55.3, the 20 px dismiss) 32
//   from the right;
// - the page (iframe-container) 90.3 down, the taskInfo's height (560),
//   full width: the app's page in OST's TeamsJS host, frameContext "task".
// An app opens it with dialog.url.open (tasks.startTask); its page closes
// it with dialog.url.submit (tasks.completeTask, the result goes back to
// the app), or Close does ("User cancelled/closed the task module.").
Popup {
    id: dlg
    property var opener: null
    property string callId: ""
    property var taskInfo: ({})
    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    property string hostThread: ""
    property string hostTeamThread: ""
    /// TeamsJS context for the page (subEntityId, chatId…).
    property var hostContext: ({})
    property string hostSessionId: ""
    signal finished(string callId, var error, var result)
    signal messageForParent(var message)
    property bool done: false
    /// Teams' header with the app's name over the dialog's title (Share to
    /// Outlook, measured on Teams on the web 2026-11-16: "Outlook" and
    /// "Share conversation over email" beside the 32 px icon at (32, 27),
    /// Close 64 from the right, the page 67 down).
    property bool subtitleHeader: false
    // Named sizes: only "large" is measured (Workflows, 900 x 560).
    function px(v, large) { return typeof v === "number" && v > 0 ? v : (Number(v) > 0 ? Number(v) : large) }
    readonly property real wantWidth: px(taskInfo.width, 900)
    readonly property real wantHeight: px(taskInfo.height, 560)
    readonly property real header: subtitleHeader ? 67 : 90.3
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true; padding: 0
    width: Math.min(wantWidth, (Overlay.overlay ? Overlay.overlay.width : wantWidth) - 32)
    height: Math.min(header + wantHeight, (Overlay.overlay ? Overlay.overlay.height : header + wantHeight) - 32)
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
    function sendToPage(m) { if (page.item) page.item.sendFrameMessage("messageForChild", [m]) }
    function finish(error, result) {
        if (done) return
        done = true
        dlg.finished(dlg.callId, error, result)
        dlg.close()
    }
    onClosed: if (!done) finish("User cancelled/closed the task module.", null)
    function stateForTest() { return JSON.stringify({ width: width, height: height, title: title.text, url: page.item ? page.item.view.url.toString() : "", events: page.item ? page.item.hostEvents : [] }) }

    contentItem: Item {
        Rectangle {
            x: 32; y: dlg.subtitleHeader ? 27 : 38.7; width: 32; height: 32; radius: 32 * 0.2856; clip: true
            color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
            Image { anchors.fill: parent; source: dlg.appIcon; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true }
            Accessible.role: Accessible.Graphic; Accessible.name: dlg.appName
        }
        Text {
            id: title
            visible: !dlg.subtitleHeader
            x: 76; y: 40.4; width: parent.width - 76 - 76
            text: dlg.taskInfo.title || dlg.appName
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            lineHeight: 28.57; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Column {
            visible: dlg.subtitleHeader
            x: 76; y: 27; width: parent.width - 76 - 76
            Text {
                width: parent.width; text: dlg.appName; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Text {
                width: parent.width; text: dlg.taskInfo.title || ""; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
        }
        Rectangle {
            id: closeBtn
            x: parent.width - 64; y: 27; width: 32; height: dlg.subtitleHeader ? 32 : 55.3; radius: 4
            color: closeHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeBtn, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Close"
        }
        Loader {
            id: page
            active: dlg.opened && !!dlg.taskInfo.url
            x: 0; y: dlg.header; width: parent.width; height: parent.height - dlg.header
            sourceComponent: WebApp {
                showHeader: false; appName: dlg.appName; appId: dlg.appId; homeTemplate: dlg.taskInfo.url || ""
                teamsHost: true; frameContext: "task"; deepNaa: false
                hostThread: dlg.hostThread; hostTeamThread: dlg.hostTeamThread; hostSessionId: dlg.hostSessionId
                hostContext: Object.assign({ entityId: "", subEntityId: "", dialogParameters: {} }, dlg.hostContext)
                onHostEvent: (name, json) => {
                    if (name === "completeTask") {
                        // dialog.url.submit: Teams hands the result back as
                        // JSON (stringified, then parsed).
                        const r = JSON.parse(json).result
                        dlg.finish(null, r === undefined ? null : JSON.parse(JSON.stringify(r)))
                    } else if (name === "messageForParent") dlg.messageForParent(JSON.parse(json).message)
                    else if (name === "updateTask") {
                        const t = JSON.parse(json).taskInfo || {}
                        dlg.taskInfo = Object.assign({}, dlg.taskInfo, { width: t.width || dlg.taskInfo.width, height: t.height || dlg.taskInfo.height })
                    }
                }
            }
        }
    }
}
