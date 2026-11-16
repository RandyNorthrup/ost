import QtQuick

// Teams' trust badge for a screened guest (measured on winpc in the
// meeting People pane, the lobby toast and the admit dialog): a dark pill,
// 24 tall, with the person-question glyph and "Unverified" in 12/600 white.
Rectangle {
    id: hcFill1
    width: badgeRow.x + badgeRow.implicitWidth + 6
    height: 24; radius: 4
    color: theme.pick("#242424", "#FFFFFF", "#000000")
    Row {
        id: badgeRow
        x: 4; anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        FluentIcon { name: "person-unverified-16-filled"; size: 16; color: theme.onFill(hcFill1, theme.pick("#FFFFFF", "#242424", "#FFFFFF")); anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Unverified"
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: theme.onFill(hcFill1, theme.pick("#FFFFFF", "#242424", "#FFFFFF"))
        }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: "Unverified"
}
