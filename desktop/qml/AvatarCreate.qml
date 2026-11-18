import QtQuick
import QtQuick.Controls

// Teams' "create your avatar" (module 710235, data-tid avatar-fre),
// shown where avatars go until you have one (measured in the pre-join
// picker on winpc 2026-11-17): the Avatars app's welcome picture (200 x
// 179, fitted) beside "Create your avatar in just a few steps." (14 px, 16
// down) and "Create your avatar" (a Fluent button, 31.3 high, 20 from the
// right, at the foot). In the side pane it is a centred column 60 down.
// Teams' button opens the Avatars app's builder (a deep link to its
// "Customize Avatar" tab), or the app in the Store when it isn't added.
Item {
    id: root
    property bool sidePanel: false
    signal create()
    implicitHeight: sidePanel ? 60 + picture.height + 30 + 16 + 30 + 32 : 179

    // The picture the Avatars app shows for this (its own asset).
    readonly property url pictureUrl: "https://mesh.public.onecdn.static.microsoft/mesh/avatars/prod/assets/FRE_Image_SidePanel%201-BWxeRQ7k.png"

    Image {
        id: picture
        x: root.sidePanel ? (root.width - width) / 2 : 0
        y: root.sidePanel ? 60 : 0
        width: 200; height: 179
        source: root.pictureUrl
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        Accessible.role: Accessible.Graphic
        Accessible.name: "Avatar FRE image"
    }
    Text {
        id: line
        x: root.sidePanel ? 30 : 200
        y: root.sidePanel ? picture.y + picture.height + 30 : 16
        width: root.sidePanel ? root.width - 60 : root.width - 200 - 20
        horizontalAlignment: root.sidePanel ? Text.AlignHCenter : Text.AlignLeft
        wrapMode: Text.Wrap
        text: "Create your avatar in just a few steps."
        font.family: theme.font; font.pixelSize: 14
        color: theme.pick("#252423", "#FFFFFF", "#FFFFFF")
    }
    Rectangle {
        id: button
        x: root.sidePanel ? (root.width - width) / 2 : root.width - 20 - width
        y: root.sidePanel ? line.y + line.height + 30 : 124.6
        width: label.implicitWidth + 40; height: 31.3; radius: 4
        color: buttonHover.hovered ? theme.rowHover : theme.input
        border.color: theme.stroke
        Text { id: label; anchors.centerIn: parent; text: "Create your avatar"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(button, theme.text) }
        HoverHandler { id: buttonHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.create() }
        Accessible.role: Accessible.Button
        Accessible.name: "Create your avatar"
    }
}
