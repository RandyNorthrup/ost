import QtQuick

/// A SharePoint library's tile, as Quick access draws it: the site's acronym
/// on its site colour (SharePoint's generated site logo), radius 4.
Rectangle {
    property string acronym
    property string tint
    property int size: 20
    width: size; height: size; radius: 4
    color: tint || "#7a7574"
    Text {
        anchors.centerIn: parent
        text: parent.acronym
        color: "white"
        font.family: theme.font; font.pixelSize: Math.round(parent.size * 0.4); font.weight: Font.DemiBold
    }
}
