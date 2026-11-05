import QtQuick

// Top bar: app launcher, sidebar toggle, search, more, profile.
Rectangle {
    id: root
    property string userName
    color: theme.chrome
    height: theme.titleBarHeight

    component BarButton: Rectangle {
        property alias icon: glyph.name
        width: 32; height: 32; radius: theme.radius
        color: hover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hover }
        FluentIcon { id: glyph; anchors.centerIn: parent; size: 20 }
    }

    BarButton { icon: "waffle-20"; x: 18; anchors.verticalCenter: parent.verticalCenter }
    BarButton { icon: "panel-left-20"; x: 70; anchors.verticalCenter: parent.verticalCenter }

    Rectangle {
        id: search
        x: 327; width: Math.min(623, parent.width - 327 - 140)
        height: 32; radius: theme.radius
        anchors.verticalCenter: parent.verticalCenter
        color: theme.searchFill
        border.color: field.activeFocus ? theme.brand : theme.dividerSoft
        FluentIcon { name: "search-20"; size: 16; x: 28; anchors.verticalCenter: parent.verticalCenter; color: theme.textSecondary }
        TextInput {
            id: field
            x: 59; width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            Text {
                visible: !field.text && !field.activeFocus
                text: "Press Ctrl+Alt+G to go right to a chat or channel"
                color: theme.textSecondary
                font: field.font
            }
        }
    }

    BarButton { icon: "more-20"; anchors.right: avatar.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter }
    Avatar {
        id: avatar
        name: root.userName || "?"
        size: 28
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            width: 10; height: 10; radius: 5
            color: "#6BB700"; border.color: theme.chrome; border.width: 2
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: -2; anchors.bottomMargin: -2
        }
    }
}
