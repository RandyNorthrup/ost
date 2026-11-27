import QtQuick

// Teams' External badge (a person outside your org on Teams free, a phone
// number): 24 tall, radius 4, NeutralForeground3 (#616161) filled, the
// people-error 16 glyph 4 in and "External" 12/600 4 after it, white on the
// fill (measured on testpc2's Teams 26304 beside "OST Personal 2", 2026-11-27).
Rectangle {
    id: badge
    width: row.width + 8; height: 24; radius: 4
    color: theme.pick("#616161", "#ADADAD", "#FFFFFF")
    Row {
        id: row
        x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 4
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "people-error-16-filled"; size: 16; color: theme.pick("#FFFFFF", "#000000", "#000000") }
        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("External"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#FFFFFF", "#000000", "#000000") }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: qsTr("External")
}
