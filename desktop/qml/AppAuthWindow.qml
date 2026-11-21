import QtQuick
import QtQuick.Window
import QtWebEngine

// An app's sign-in window for a link card (Teams' app-based link "Sign in",
// module 961755): `window.open(url, "appAuthWindow", "width=W, height=H")`
// with W and H from the address's own width / height parameters. When it
// closes, the link is asked again (Teams re-queries the app, network-only).
Window {
    id: win
    property string url: ""
    signal finished()
    readonly property var size_: {
        const q = s => { const m = new RegExp("[?&]" + s + "=(\\d+)").exec(url); return m ? parseInt(m[1]) : 0 }
        return [q("width") || 600, q("height") || 535]
    }
    width: size_[0]; height: size_[1]
    title: view.title
    color: theme.surface
    flags: Qt.Window
    onClosing: win.finished()
    WebEngineView {
        id: view
        anchors.fill: parent
        url: win.url.indexOf("https://") === 0 ? win.url : ""
        settings.javascriptCanOpenWindows: false
        Component.onCompleted: profile = webAppsProfile.instance()
    }
}
