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
    // Straight to Microsoft's page, as Teams.
    onVisibleChanged: if (visible && !page && !busy) Qt.callLater(root.signIn)
    Component.onCompleted: if (visible && !page && !busy) Qt.callLater(root.signIn)

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
            if (backend.signInNavigated(u)) req.reject()
            else if (u.indexOf("https://") !== 0 && u !== "about:blank") req.reject()
        }
        onPermissionRequested: p => p.deny()
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
                text: root.busy ? "Signing in…" : "Sign in to OST"
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
                Text { anchors.centerIn: parent; text: "Sign in"; color: theme.onFill(parent, theme.textOnBrand); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                HoverHandler { id: tryHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.signIn() }
                Accessible.role: Accessible.Button
                Accessible.name: "Sign in"
            }
        }
    }
}
