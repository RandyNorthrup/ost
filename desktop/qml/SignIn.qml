import QtQuick
import QtWebEngine

// Sign-in, as Teams: Microsoft's sign-in page (Teams on the web's sign-in,
// in OST's web profile so embedded apps share the session). Its return
// address is caught before it loads and the code is redeemed; the app loads
// once that's done. A failure shows under the page's own header area.
Rectangle {
    id: root
    /// Microsoft's sign-in page, while a sign-in is running.
    property string page
    property var webProfile
    property bool busy
    property string error
    signal signIn()
    color: theme.pane
    // Straight to Microsoft's page, as Teams: after signing out (at start-up
    // the backend begins it once it knows nobody is signed in).
    onVisibleChanged: if (visible && !page && !busy && !backend.hasCredentials) Qt.callLater(root.signIn)

    WebEngineView {
        id: signInView
        visible: root.page.length > 0
        anchors.fill: parent
        // OST's shared web profile, once it exists (see WebApp).
        property bool ready: false
        Component.onCompleted: Qt.callLater(() => { if (root.webProfile) profile = root.webProfile.instance(); ready = true })
        url: ready && root.page ? root.page : "about:blank"
        settings.javascriptCanOpenWindows: false
        onNavigationRequested: req => {
            const u = req.url.toString()
            if (backend.signInNavigated(u, false)) req.reject()
            else if (u.indexOf("https://") !== 0 && u !== "about:blank") req.reject()
        }
        onPermissionRequested: p => p.deny()
        // --seti-signin --shots=<dir> (TASK-0078): a new profile's sign-in
        // page, logged and pictured once Microsoft's page has loaded.
        onLoadingChanged: info => {
            if (Qt.application.arguments.indexOf("--seti-signin") < 0 || info.status !== WebEngineView.LoadSucceededStatus || url.toString() === "about:blank") return
            console.warn("SETI signin loaded", url.toString().split("?")[0], JSON.stringify(title))
            signInShot.restart()
        }
        Timer {
            id: signInShot
            interval: 3000
            onTriggered: {
                const dir = (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "--shots=.").slice(8) + "/"
                window.contentItem.grabToImage(r => { r.saveToFile(dir + "si-signin.png"); console.warn("SETI signin shot"); Qt.quit() })
            }
        }
    }

    // While the sign-in is redeemed, or after it failed: OST's card.
    Rectangle {
        visible: root.page.length === 0
        anchors.centerIn: parent
        width: 440
        height: content.implicitHeight + 88
        radius: 8
        color: theme.surface
        border.color: theme.dividerSoft
        Column {
            id: content
            x: 44; y: 44
            width: parent.width - 88
            spacing: 16
            Image {
                source: "../assets/logo.png"
                width: 56; height: 56
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: root.busy ? qsTr("Signing in…") : qsTr("Sign in to OST")
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                color: theme.text
            }
            Text {
                visible: root.error.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.error
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.danger
            }
            Rectangle {
                visible: !root.busy
                width: parent.width; height: 32; radius: theme.radius
                color: tryHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Sign in"); color: theme.onFill(parent, theme.textOnBrand); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                HoverHandler { id: tryHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.signIn() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Sign in")
            }
        }
    }
}
