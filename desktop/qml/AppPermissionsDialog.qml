import QtQuick
import QtQuick.Controls.Basic

// Teams' App permissions (a tab's ··· ▸ App permissions), measured on
// winpc 2026-11-09 for OneNote in OST Test Team: 600 wide, padding 24,
// radius 8. The header: the app's 28 px icon and its name (16/22
// semibold) 44 in, Close at the right. For apps Teams pre-approves, "This
// app has permissions enabled by default for your convenience. Adjust
// these permissions at any time. Learn more" (12/16) 49 down. Then a row
// per device permission the app asks for, 111 down: a 20 px icon, the
// title (14/20) 35 in, the subtitle (12/16, light) under it, and a switch
// at the right. Changes stay on this device, as Teams keeps them, and the
// tab's web view honours them.
Popup {
    id: root
    property string appId: ""
    readonly property var info: { const p = backend.appPermissionsJson ? JSON.parse(backend.appPermissionsJson) : null; return p && p.app === appId ? p : null }
    readonly property var icons: ({ media: "camera-20", geolocation: "location-20", notifications: "alert-20", midi: "music-note-2-20", openExternal: "open-20" })
    function show(id) { appId = id; backend.appPermissionsLoad(id); open() }
    modal: true; focus: true
    width: 600; padding: 24
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }
    contentItem: Column {
        spacing: 0
        Item {
            width: parent.width; height: 31.3
            Rectangle { width: 28; height: 28; radius: 4; color: "transparent"
                Image { anchors.fill: parent; source: root.info && root.info.icon ? root.info.icon : ""; sourceSize: Qt.size(56, 56); fillMode: Image.PreserveAspectFit; asynchronous: true } }
            Text { x: 44; y: 3; height: 22; verticalAlignment: Text.AlignVCenter; text: root.info && root.info.name ? root.info.name : ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
            Rectangle {
                anchors.right: parent.right; width: 32; height: 31.3; radius: 4
                color: closeHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textSecondary }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Close"
            }
        }
        Item { width: 1; height: 18 }
        Text {
            visible: !!root.info && !!root.info.preapproved
            width: parent.width; wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: "<style>a { color: " + theme.brandForeground1 + "; text-decoration: none; }</style>This app has permissions enabled by default for your convenience. Adjust these permissions at any time. <a href=\"https://go.microsoft.com/fwlink/?linkid=2166702&clcid=0x409\">Learn more</a>"
            linkColor: theme.brandForeground1
            onLinkActivated: link => Qt.openUrlExternally(link)
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; color: theme.text
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Item { width: 1; height: 30 }
        Text { visible: !!root.info && !!root.info.loading; text: "Loading…"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        Repeater {
            model: root.info && root.info.items ? root.info.items : []
            Item {
                id: row
                required property var modelData
                width: root.availableWidth; height: 40
                FluentIcon { x: 0; y: 2; name: root.icons[row.modelData.kind] || "shield-keyhole-20"; size: 20; color: theme.text }
                Text { x: 35; y: 0; height: 20; verticalAlignment: Text.AlignVCenter; text: row.modelData.title; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { visible: !!row.modelData.subtitle; x: 35; y: 22.5; height: 16; verticalAlignment: Text.AlignVCenter; text: row.modelData.subtitle; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Light; color: theme.text }
                // Fluent switch (40 x 20, brand when on).
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 8; y: 1
                    width: 40; height: 20; radius: 10
                    color: row.modelData.on ? (swHover.hovered ? theme.brandHover : theme.brandFill) : "transparent"
                    border.width: row.modelData.on ? 0 : 1; border.color: theme.textSecondary
                    Rectangle { width: 14; height: 14; radius: 7; anchors.verticalCenter: parent.verticalCenter; x: row.modelData.on ? parent.width - width - 3 : 3; color: row.modelData.on ? "white" : theme.textSecondary }
                    HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.setAppPermission(root.appId, row.modelData.kind, !row.modelData.on) }
                    Accessible.role: Accessible.CheckBox; Accessible.name: row.modelData.title; Accessible.checked: !!row.modelData.on
                }
            }
        }
    }
}
