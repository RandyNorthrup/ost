import QtQuick

// What Teams draws under a shared app's card in a chat (measured on winpc
// 2026-11-09, scratchpad ab/chatcard-dump.txt): "Privacy | Terms of use |
// Permissions" (10/14, NeutralForeground2, 1 x 10 dividers 8 either side),
// then Open (brand, 60 wide), View details (outline) and a share button,
// 31 tall. The links come from the app's definition.
Item {
    id: root
    property string appId
    signal details()
    signal permissions()
    signal share()
    signal openApp()
    width: parent ? parent.width : 324
    height: 72

    readonly property var links: { const m = backend.appLinksJson ? JSON.parse(backend.appLinksJson) : ({}); return m[appId] || null }
    Component.onCompleted: if (!links && appId) backend.appLinksLoad(appId)

    component SmallLink: Text {
        id: sl
        property string url
        signal activated()
        height: 14
        font.family: theme.font; font.pixelSize: 10; color: theme.textStrong
        font.underline: slHover.hovered
        HoverHandler { id: slHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (sl.url) Qt.openUrlExternally(sl.url); sl.activated() } }
        Accessible.role: Accessible.Link
        Accessible.name: text
    }
    Row {
        y: 10; height: 14; spacing: 8
        SmallLink { visible: !!root.links && !!root.links.privacy; text: "Privacy"; url: root.links ? root.links.privacy : "" }
        Rectangle { visible: !!root.links && !!root.links.privacy; y: 2; width: 1; height: 10; color: theme.stroke }
        SmallLink { visible: !!root.links && !!root.links.terms; text: "Terms of use"; url: root.links ? root.links.terms : "" }
        Rectangle { visible: !!root.links && !!root.links.terms; y: 2; width: 1; height: 10; color: theme.stroke }
        SmallLink { text: "Permissions"; onActivated: root.permissions() }
    }
    Row {
        y: 41; spacing: 8
        Rectangle {
            width: 60; height: 31.33; radius: 4
            color: openHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Open"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: openHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openApp() }
            Accessible.role: Accessible.Button; Accessible.name: "Open"
        }
        Row {
            spacing: 0
            Rectangle {
                width: 101; height: 31.33; radius: 4
                color: vdHover.hovered ? theme.menuHover : "transparent"
                border.width: 0.67; border.color: vdHover.hovered ? theme.strokeHover : theme.stroke
                Text { anchors.centerIn: parent; text: "View details"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: vdHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.details() }
                Accessible.role: Accessible.Button; Accessible.name: "View details"
            }
            Rectangle {
                width: 32; height: 31.33; radius: 4
                color: shHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "share-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: shHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.share() }
                Accessible.role: Accessible.Button; Accessible.name: "Share"
            }
        }
    }
}
