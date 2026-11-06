import QtQuick
import QtQuick.Window
import QtWebEngine

// A web app Teams embeds (Whiteboard, Clipchamp, Help), shown in place as
// Teams shows it: the app's header (icon and name, Open in browser), then
// the page. Pages keep their sign-in in OST's own web profile (one for the
// whole app, in Main.qml; stored on disk, like Teams'), only https pages load, and pop-ups (sign-in)
// open in a window of their own.
Item {
    id: root
    property string appName
    property string appIcon
    property color appColor: theme.brand
    property url home
    /// The app's own header (icon, name, Reload, Open in browser); off for
    /// a channel tab, which Teams shows bare under the channel's tabs.
    property bool showHeader: true
    readonly property alias view: web

    Rectangle { anchors.fill: parent; color: theme.surface }

    Rectangle {
        id: header
        visible: root.showHeader
        width: parent.width; height: root.showHeader ? 52 : 0; color: theme.surface
        Row {
            x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 10
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: root.appIcon || "apps"; size: 22; color: root.appColor }
            Text { anchors.verticalCenter: parent.verticalCenter; text: root.appName; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        }
        Row {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 4
            HeaderButton { icon: "arrow-clockwise-20"; label: "Reload"; onClicked: web.reload() }
            HeaderButton { icon: "open-20"; label: "Open in browser"; onClicked: Qt.openUrlExternally(web.url) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    property bool ready: false
    Component.onCompleted: {
        web.profile = webAppsProfile.instance()
        web.url = root.home
        ready = true
    }
    // Another page for the same view (a different channel's Page).
    onHomeChanged: if (ready) web.url = root.home

    WebEngineView {
        id: web
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        // The profile and first page are set once everything is complete:
        // the prototype's instance() isn't ready while bindings first run.
        settings.javascriptCanOpenWindows: true
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        // https only.
        onNavigationRequested: req => {
            if (req.url.toString().indexOf("https://") !== 0 && req.url.toString() !== "about:blank") req.reject()
        }
        // Sign-in and other pop-ups get a window of their own.
        onNewWindowRequested: req => {
            const w = popup.createObject(null, {})
            req.openIn(w.view)
        }
        // Camera, microphone, location and the like: refused.
        onPermissionRequested: p => p.deny()
    }

    Component {
        id: popup
        Window {
            id: pw
            readonly property alias view: pv
            width: 520; height: 680
            visible: true
            title: pv.title || root.appName
            color: theme.surface
            WebEngineView {
                id: pv
                anchors.fill: parent
                profile: web.profile
                onNavigationRequested: req => {
                    if (req.url.toString().indexOf("https://") !== 0 && req.url.toString() !== "about:blank") req.reject()
                }
                onWindowCloseRequested: pw.destroy()
                onPermissionRequested: p => p.deny()
            }
            onClosing: destroy()
        }
    }

    component HeaderButton: Rectangle {
        id: hb
        property string icon
        property string label
        signal clicked()
        width: hbRow.implicitWidth + 16; height: 32; radius: theme.radius
        color: hbh.hovered ? theme.rowHover : "transparent"
        Row { id: hbRow; anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: hb.icon; size: 18; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: hb.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        }
        HoverHandler { id: hbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
