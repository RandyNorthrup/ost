import QtQuick

/// A SharePoint library's tile, as Quick access draws it: the site's acronym
/// on its site colour (SharePoint's generated site logo), radius 4.
Rectangle {
    id: hcFill1
    property string acronym
    property string tint
    property int size: 20
    width: size; height: size; radius: 4
    color: tint || theme.hc("#7a7574", "#000000")
    Text {
        anchors.centerIn: parent
        text: parent.acronym
        color: theme.onFill(hcFill1, "white")
        font.family: theme.font; font.pixelSize: Math.round(parent.size * 0.4); font.weight: Font.DemiBold
    }
}
