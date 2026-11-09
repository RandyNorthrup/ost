import QtQuick
import QtQuick.Controls.Basic

// About this tab (Teams' About dialog, as measured): padding 27/32/42,
// the app's name as a 20 px semibold title and a close button; the
// app's 36 px logo (radius 4) beside its description and developer
// link; then the identity note (not full trust) and the privacy line.
Popup {
    id: aboutDialog
    property var tab: null
    readonly property var about: {
        const r = backend.appAboutJson ? JSON.parse(backend.appAboutJson) : null
        return r && tab && r.app === tab.app_id && r.about ? r.about : null
    }
    function start(t) { tab = t; backend.appAboutLoad(t.app_id); open() }
    anchors.centerIn: Overlay.overlay
    modal: true; width: 600
    topPadding: 27; leftPadding: 32; rightPadding: 32; bottomPadding: 42
    height: Math.min(implicitHeight, (Overlay.overlay ? Overlay.overlay.height : 800) - 48)
    background: FluentSurface { depth: 64; radius: 8 }
    contentItem: Flickable {
        implicitHeight: aboutCol.implicitHeight
        contentHeight: aboutCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: aboutCol
            width: parent.width
            spacing: 16
            Item {
                width: parent.width; height: 31.3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: aboutDialog.about ? aboutDialog.about.name : ""
                    font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 32; height: 31.3; radius: 4
                    color: aboutClose.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: aboutClose; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: aboutDialog.close() }
                    Accessible.role: Accessible.Button; Accessible.name: "Close"
                }
            }
            Row {
                width: parent.width
                spacing: 15
                Image {
                    width: 36; height: 36
                    source: aboutDialog.about ? aboutDialog.about.icon : ""
                    sourceSize: Qt.size(72, 72)
                    // Teams rounds the logo's corners (4 px).
                    RoundedCorners { anchors.fill: parent; radius: 4; background: theme.menu }
                }
                Column {
                    width: parent.width - 36 - 15
                    spacing: 0
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        // Teams' converted description; its own links keep
                        // the browser default (#0000EE), as Teams shows them.
                        textFormat: Text.RichText
                        text: aboutDialog.about ? aboutDialog.about.description : ""
                        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                        linkColor: "#0000EE"
                        onLinkActivated: link => { if (/^https:/.test(link)) Qt.openUrlExternally(link) }
                    }
                    Text {
                        visible: !!aboutDialog.about && !!aboutDialog.about.developer && !!aboutDialog.about.developer_url
                        textFormat: Text.StyledText
                        text: aboutDialog.about ? "<a href=\"" + aboutDialog.about.developer_url + "\">" + aboutDialog.about.developer + "</a>" : ""
                        font.family: theme.font; font.pixelSize: theme.base
                        linkColor: theme.brandLink
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
            Column {
                visible: !!aboutDialog.about && aboutDialog.about.needs_identity
                width: parent.width
                Text { width: parent.width; wrapMode: Text.Wrap; text: (aboutDialog.about ? aboutDialog.about.name : "") + " needs access to:"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Bold; color: theme.text }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Team member's email addresses and information that can identify your team and organization name. Data may be sent to a third-party service"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            }
            Text {
                visible: !!aboutDialog.about && !!aboutDialog.about.privacy_url && !!aboutDialog.about.terms_url
                width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: aboutDialog.about ? "By using this tab, you agree to the developer's <a href=\"" + aboutDialog.about.privacy_url + "\">privacy policy</a> and <a href=\"" + aboutDialog.about.terms_url + "\">terms of use</a>." : ""
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                linkColor: theme.brandLink
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
