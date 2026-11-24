import QtQuick
import QtQuick.Controls.Basic

// Share to Outlook (a chat message's ··· ▸ Share to Outlook), as Teams does
// it (measured on Teams on the web 2026-11-16, docs/spec/app-host.md
// "Share to Outlook"): the middle tier makes a draft of the conversation
// in your mailbox (GetEmailIdForConversation), and Teams' dialog for the
// Outlook app (40517485…, 800 wide, "Outlook" over "Share conversation
// over email") frames Outlook's compose for that draft in Teams' app host
// (frameContext task; Outlook signs in with getAuthToken). Sending is
// Outlook's own; closing the dialog discards the draft, as Teams does.
Item {
    id: root
    property string threadId: ""
    property string emailId: ""
    readonly property string requestId: "sto" + Math.floor(Math.random() * 1e9).toString(36)
    property var dialog: null
    property bool busy: false
    /// For the harness: what happened (created, opened, discarded, error).
    property var events: []
    function start(m) {
        if (busy || !threadId || !m) return
        busy = true
        events = events.concat(["start"])
        backend.appHostRequest("", root.threadId, "", "", "stoCreate", root.requestId + ":create", JSON.stringify({ messageId: m.id }))
    }
    function close() { if (dialog) dialog.close() }
    Connections {
        target: backend
        function onAppHostReply(id, json) {
            if (id === root.requestId + ":discard") { root.events = root.events.concat([JSON.parse(json).ok ? "discarded" : "discard failed"]); return }
            if (id !== root.requestId + ":create") return
            root.busy = false
            const r = JSON.parse(json)
            if (!r.url) { root.events = root.events.concat(["error"]); window.showToast({ text: qsTr("Couldn't share to Outlook.") + " " + (r.error || ""), intent: "error" }); return }
            root.emailId = r.emailId
            root.events = root.events.concat(["created"])
            const c = Qt.createComponent("TaskModuleDialog.qml")
            if (c.status !== Component.Ready) { console.warn("STO dialog", c.errorString()); return }
            root.dialog = c.createObject(Overlay.overlay || root, {
                appId: "40517485-2262-4135-b174-401da4aa6f0f", appName: "Outlook", subtitleHeader: true,
                appIcon: "https://statics.teams.cdn.office.net/evergreen-assets/apps/outlook_largeimage.png",
                hostThread: root.threadId,
                taskInfo: { url: r.url, title: qsTr("Share conversation over email"), width: 800, height: 600 }
            })
            root.dialog.finished.connect(() => {
                // Closed without sending: Teams discards the draft
                // (deleteShareToOutlookEmailDraft).
                if (root.emailId) backend.appHostRequest("", "", "", "", "stoDiscard", root.requestId + ":discard", JSON.stringify({ emailId: root.emailId }))
                root.emailId = ""
                const d = root.dialog; root.dialog = null
                Qt.callLater(() => d.destroy())
            })
            root.dialog.open()
            root.events = root.events.concat(["opened"])
        }
    }
}
