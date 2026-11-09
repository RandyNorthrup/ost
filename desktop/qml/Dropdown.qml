import QtQuick
import QtQuick.Controls

// Teams' Fluent dropdown as its dialogs and panes draw it (measured in the
// Record and transcribe dialogs and the Caption styles pane on winpc):
// 30 tall, white with a #D1D1D1 hairline and a NeutralStrokeAccessible
// bottom line, the value at 12 (14/20), a 20 px chevron; its list opens
// below (above when there's no room), 32 px rows, scrolling past 300.
// options: [[value, label]]; `label` is what it shows.
Rectangle {
    id: dd
    property string label
    property var options: []
    property string accessibleName
    signal picked(string code)
    height: 30; radius: 4
    color: theme.surface
    border.color: theme.stroke; border.width: 0.67
    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 0.67; color: theme.textSecondary }
    Text {
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 52; elide: Text.ElideRight
        text: dd.label
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textStrong }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: list.visible ? list.close() : list.open() }
    Accessible.role: Accessible.ComboBox
    Accessible.name: dd.accessibleName
    Popup {
        id: list
        parent: Overlay.overlay
        padding: 4
        width: dd.width + 1.33
        height: Math.min(300, col.implicitHeight + 8)
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onAboutToShow: {
            const p = dd.mapToItem(Overlay.overlay, 0, 0)
            x = p.x - 0.67
            const below = p.y + dd.height + 2.67
            y = below + height <= Overlay.overlay.height ? below : p.y - height - 2.67
        }
        Flickable {
            anchors.fill: parent
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: col
                width: parent.width
                Repeater {
                    model: dd.options
                    Rectangle {
                        id: opt
                        required property var modelData
                        width: col.width; height: 32; radius: 4
                        color: oh.hovered ? theme.menuHover : "transparent"
                        Text {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16; elide: Text.ElideRight
                            text: opt.modelData[1]
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.text
                        }
                        HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { list.close(); dd.picked(opt.modelData[0]) } }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: opt.modelData[1]
                    }
                }
            }
        }
    }
}
