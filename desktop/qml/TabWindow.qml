import QtQuick
import QtQuick.Window
import QtQuick.Controls

// A channel tab in a window of its own: Teams' "Open tab in new window"
// (measured on winpc, 2026-11-09).
// - The window opens 946 x 593 with Teams' child-window title row; the
//   title is "<team> / <channel>".
// - An app tab gets Teams' tab header (entity-header, 61 tall, white, a
//   0.67 px #E0E0E0 line under it, padding 0 7 0 20): the app's icon (32,
//   round) at 20, its name (18/25.7 bold) 20 after it, and at the right the
//   header actions (30 x 44, 20 px icons, in this order): Reload tab, Go to
//   website (when the tab has a website), Copy link, About this tab, App
//   permissions (when the app asks for device permissions), after "Show
//   tab conversation" (32 x 20) for tabs that have one; it opens the tab's
//   conversation beside the tab, in this window.
// - A channel Page (popOutChannelPage) has no tab header: the page fills
//   the window under the title row, which reads the app's own name.
Window {
    id: win
    /// The tab, as the backend lists it (Tab: id, name, app_id, kind,
    /// content_url, website_url, menu).
    property var tab: ({})
    property string teamId: ""
    property string channelId: ""
    property string teamName: ""
    property string channelName: ""
    property bool pinned: false
    readonly property bool isPage: tab.kind === "ChannelPage"
    /// The header's text and icons: black in the window of its own (as
    /// measured; the channel's header uses #242424).
    readonly property color ink: theme.pick("#000000", "#FFFFFF")
    /// The app's About (name, icon), once loaded.
    property var about: null
    signal aboutRequested()
    title: isPage ? Qt.application.name : teamName + " / " + channelName
    width: 946; height: 593
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    function takeAbout() {
        const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
        if (r && r.app === win.tab.app_id && r.about) win.about = r.about
    }
    Component.onCompleted: { takeAbout(); if (tab.app_id && !about) backend.appAboutLoad(tab.app_id) }
    Connections {
        target: backend
        enabled: !win.about
        function onAppAboutJsonChanged() { win.takeAbout() }
    }

    /// The tab's menu keys (what Teams offers for this tab).
    readonly property var keys: (tab.menu || []).map(e => e.key)
    property bool conversationOpen: false
    function act(key) {
        if (key === "conversation") win.conversationOpen = !win.conversationOpen
        else if (key === "reloadTab") win.reload()
        else if (key === "goToWebsite") { if (tab.website_url) Qt.openUrlExternally(tab.website_url) }
        else if (key === "copyLink") backend.copyTabLink(win.teamId, win.channelId, JSON.stringify(win.tab))
        else if (key === "aboutTab") aboutDialog.start(win.tab)
        else if (key === "devicePermissions") appPermissions.show(win.tab.app_id)
    }
    function reload() { if (pageLoader.item) pageLoader.item.reload() }
    function actionsForTest() { return headerActions.model.map(a => a.key) }
    function startConversationForTest() { if (convPane.item) convPane.item.startForTest() }

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }

    Rectangle {
        id: header
        visible: !win.isPage
        anchors.top: titleRow.bottom
        width: parent.width; height: visible ? 61 : 0
        color: theme.surface
        AppIcon {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32
            source: win.tab.icon || (win.about ? win.about.icon : "")
        }
        Text {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, actionsRow.x - x - 8)
            elide: Text.ElideRight
            text: win.about ? win.about.name : ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: win.ink
        }
        Row {
            id: actionsRow
            anchors.right: parent.right; anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                id: headerActions
                model: [
                    { key: "conversation", icon: win.conversationOpen ? "chat-20-filled" : "chat-20", tip: win.conversationOpen ? "Hide tab conversation" : "Show tab conversation", show: win.tab.can_converse === true, w: 32, h: 20 },
                    { key: "reloadTab", icon: "arrow-clockwise-20", tip: "Reload tab" },
                    { key: "goToWebsite", icon: "globe-20", tip: "Go to website", show: !!win.tab.website_url },
                    { key: "copyLink", icon: "link-20", tip: "" },
                    { key: "aboutTab", icon: "info-20", tip: "About this tab" },
                    { key: "devicePermissions", icon: "shield-keyhole-20", tip: "App permissions", show: win.keys.indexOf("devicePermissions") >= 0 }
                ].filter(a => a.show !== false)
                Rectangle {
                    required property var modelData
                    width: modelData.w || 30; height: modelData.h || 44; radius: 4
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    color: ah.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: parent.modelData.key === "conversation" && win.conversationOpen ? theme.brand : win.ink }
                    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.act(parent.modelData.key) }
                    ToolTip.visible: ah.hovered && modelData.tip.length > 0
                    ToolTip.delay: 500
                    ToolTip.text: modelData.tip
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.tip || "Copy link"
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // The tab's content: a Page is OST's web view of it; an app tab OST
    // can't host yet says so, as it does in the channel.
    Loader {
        id: pageLoader
        active: win.isPage && !!win.tab.content_url
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: convPane.left }
        sourceComponent: WebApp { showHeader: false; pageOnly: true; location: win.channelName + (win.teamName ? " · " + win.teamName : ""); appName: win.tab.name || ""; appId: win.tab.app_id || ""; home: win.tab.content_url }
    }
    Column {
        visible: !win.isPage
        x: (convPane.x - width) / 2; anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "info-16"; size: 32; color: theme.textSecondary }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (win.tab.name || "") + " isn't available in OST yet."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
    }

    // The tab's conversation, beside it. Loaded by its URL: the pane holds
    // a Conversation, which opens this window, and QML can't compile a type
    // that (through others) contains itself.
    Loader {
        id: convPane
        active: win.conversationOpen
        visible: active
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: active ? 360 : 0
        source: Qt.resolvedUrl("TabConversationPane.qml")
        onLoaded: {
            item.tab = Qt.binding(() => win.tab)
            item.teamId = Qt.binding(() => win.teamId)
            item.teamName = Qt.binding(() => win.teamName)
            item.channelId = Qt.binding(() => win.channelId)
            item.myName = Qt.binding(() => backend.userName)
            item.channelTabs = Qt.binding(() => [win.tab])
            item.closed.connect(() => win.conversationOpen = false)
        }
    }
    TabAboutDialog { id: aboutDialog }
    AppPermissionsDialog { id: appPermissions }
}
