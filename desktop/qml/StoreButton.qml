import QtQuick

// A Fluent button as the Store's dialogs draw it: 31.3 tall, radius 4,
// 14 semibold; primary in brand, else outline (#D1D1D1) on white.
Rectangle {
    id: b
    property string label
    property bool primary: false
    property string icon: ""
    signal clicked()
    implicitWidth: row.implicitWidth + 24
    width: implicitWidth; height: 31.3; radius: 4
    color: !enabled ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
    border.width: primary || !enabled ? 0 : 0.67; border.color: theme.stroke
    Row {
        id: row
        anchors.centerIn: parent; spacing: 6
        FluentIcon { visible: !!b.icon; anchors.verticalCenter: parent.verticalCenter; name: b.icon || "add-20"; size: 20; color: theme.onFill(b, b.primary ? theme.textOnBrand : theme.text) }
        Text { anchors.verticalCenter: parent.verticalCenter; text: b.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(b, !b.enabled ? theme.disabled : b.primary ? theme.textOnBrand : theme.text) }
    }
    HoverHandler { id: bh; cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: b.enabled; onTapped: b.clicked() }
    Accessible.role: Accessible.Button; Accessible.name: label
}
