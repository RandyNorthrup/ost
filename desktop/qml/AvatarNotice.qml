import QtQuick
import QtQuick.Controls

// Teams' avatars retirement notice (module 811151; ECS
// enableAvatarRetirementNotice, avatarRetirementLinkUrl; measured in the
// pre-join picker on winpc 2026-11-17): a Fluent warning message bar
// (#FFF9F5, 1 px #FDCFB4, radius 4) with the 20 px Warning glyph 12.7 in,
// "Changes are coming to Avatars in Teams" (14/600) over its text and a
// "Learn more" link, and Dismiss (24 x 24) at its top right. Dismissing it
// hides it until it is shown again (Teams keeps that in the component).
Item {
    id: root
    property bool dismissed: false
    visible: !dismissed
    implicitHeight: visible ? box.height + 16 : 0
    readonly property color fill: theme.pick("#FFF9F5", "#4A1E04", "#000000")
    readonly property color edge: theme.pick("#FDCFB4", "#8A3707", "#FFFFFF")

    Rectangle {
        id: box
        x: 16; y: 8; width: root.width - 32
        height: textCol.implicitHeight + 21.3
        radius: 4
        color: root.fill; border.color: root.edge; border.width: 1
        FluentIcon { x: 12.7; y: 10.7; name: "warning-20-filled"; size: 20; color: theme.pick("#BC4B09", "#FAB28B", "#FFFFFF") }
        Column {
            id: textCol
            x: 40.7; y: 10.7; width: box.width - 40.7 - 49
            Text {
                width: parent.width
                text: qsTr("Changes are coming to Avatars in Teams")
                wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
            }
            Text {
                width: parent.width
                text: qsTr("Avatars will remain available and supported through April 2027. If your organization uses Avatars, please watch for additional guidance.")
                wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14
                color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
            }
            Text {
                height: 20; verticalAlignment: Text.AlignVCenter
                text: qsTr("Learn more")
                font.family: theme.font; font.pixelSize: 14
                font.underline: true
                color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally("https://aka.ms/AvatarsUpdate") }
                Accessible.role: Accessible.Link
                Accessible.name: qsTr("Learn more about the Avatars retirement update")
            }
        }
        Rectangle {
            id: dismiss
            x: box.width - 36; y: 10.7
            width: 24; height: 24; radius: 4
            color: dismissHover.hovered ? Qt.rgba(0, 0, 0, 0.05) : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.dismissed = true }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Dismiss")
        }
    }
}
