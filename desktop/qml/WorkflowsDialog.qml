import QtQuick
import QtQuick.Controls.Basic

// Workflows (a channel's menu ▸ Workflows; Teams' dialog, measured on winpc
// 2026-11-09): 900 x 634.4, radius 8. Teams' own header: the Workflows
// app's icon (32, squircle) at (32, 38.7), "Workflows" (20/28.6 bold) at
// 76, Close (32 x 55.4) at 836, 27 down; under it, 90.4 down, the Workflows
// web app Teams embeds (automations.teams.cloud.microsoft, channel
// workflows in its modal mode), 544 tall.
Popup {
    id: dlg
    readonly property string appId: "c3a1996d-db0f-4857-a6ea-7aabf0266b00"
    property string channelId: ""
    property string channelName: ""
    property string teamId: ""
    property string teamName: ""
    /// A chat's Set workflows (Teams' chatworkflows with the chat's name
    /// and id, measured 2026-11-09).
    property string chatId: ""
    property string chatName: ""
    property var about: null
    readonly property string url: {
        if (!channelId && !chatId) return ""
        const q = (chatId ? [
            ["renderMode", "modal"], ["subContext", "chatworkflows"],
            ["chatName", chatName], ["chatId", chatId]
        ] : [
            ["renderMode", "modal"], ["subContext", "channelworkflows"],
            ["channelName", channelName], ["channelId", channelId],
            ["teamId", teamId], ["teamName", teamName]
        ]).concat([
            ["theme", theme.dark ? "dark" : "default"], ["locale", "en-us"], ["ringId", "general"],
            ["userId", (backend.userMri || "").replace(/^8:orgid:/, "")], ["tenantId", backend.tenantId()],
            ["clientType", "desktop"]
        ]).map(p => p[0] + "=" + encodeURIComponent(p[1])).join("&")
        return "https://automations.teams.cloud.microsoft/webapps/workflows/prod/home?" + q
    }
    function startChat(id, name) {
        chatId = id; chatName = name; channelId = ""
        takeAbout()
        if (!about) backend.appAboutLoad(appId)
        open()
    }
    function start(cid, cname, tid, tname) {
        chatId = ""; channelId = cid; channelName = cname; teamId = tid; teamName = tname
        takeAbout()
        if (!about) backend.appAboutLoad(appId)
        open()
    }
    function takeAbout() {
        const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
        if (r && r.app === dlg.appId && r.about) dlg.about = r.about
    }
    Connections { target: backend; enabled: !dlg.about; function onAppAboutJsonChanged() { dlg.takeAbout() } }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 900; height: 634.4; padding: 0
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    onClosed: page.active = false
    onOpened: page.active = true
    contentItem: Item {
        AppIcon {
            x: 32; y: 38.7; width: 32; height: 32
            source: dlg.about ? dlg.about.icon : ""
        }
        Text {
            x: 76; y: 40.4
            text: "Workflows"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            lineHeight: 28.6; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            x: 836; y: 27; width: 32; height: 55.4; radius: 4
            color: closeHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Close"
        }
        Loader {
            id: page
            active: false
            x: 0; y: 90.4; width: parent.width; height: parent.height - 90.4
            sourceComponent: WebApp { showHeader: false; appName: "Workflows"; appId: dlg.appId; home: dlg.url }
        }
    }
}
