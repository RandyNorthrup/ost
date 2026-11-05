import QtQuick
import QtQuick.Controls.Basic

// A Teams-style flyout menu: rows of optional icon, label and shortcut.
// items: [{ label, icon?, keys?, checked?, separator? }]; picking a row
// emits picked(index) and closes.
Popup {
    id: root
    property var items: []
    signal picked(int index)
    padding: 4
    width: 260
    background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
    contentItem: Column {
        Repeater {
            model: root.items
            Item {
                id: row
                required property var modelData
                required property int index
                width: root.width - 8
                height: modelData.separator ? 9 : 36
                Rectangle {
                    visible: !!row.modelData.separator
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 1; color: theme.dividerSoft
                }
                Rectangle {
                    visible: !row.modelData.separator
                    anchors.fill: parent; radius: theme.radius
                    color: mh.hovered ? theme.rowHover : "transparent"
                    FluentIcon {
                        visible: !!row.modelData.icon
                        x: 10; anchors.verticalCenter: parent.verticalCenter; size: 20
                        name: row.modelData.icon || ""
                        color: row.modelData.checked ? theme.brand : theme.textStrong
                    }
                    FluentIcon {
                        visible: !row.modelData.icon && row.modelData.checked === true
                        x: 14; anchors.verticalCenter: parent.verticalCenter; size: 12
                        name: "checkmark-12"; color: theme.text
                    }
                    Text {
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.label || ""
                        font.family: theme.font; font.pixelSize: theme.base
                        color: theme.text
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.keys || ""
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.textSecondary
                    }
                    HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.close(); root.picked(row.index) } }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: row.modelData.label || ""
                }
            }
        }
    }
}
