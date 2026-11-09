import QtQuick
import QtQuick.Controls.Basic

// Teams' pick-one menus beside the caption settings (Meeting spoken
// language ▸, Position ▸; Fluent MenuList of menuitemradio, measured on
// winpc, 2026-11-09): rows 32 tall with 2 between, the chosen one's 16 px
// check 6 in and 8 down, labels at 26 (14/20, NeutralForeground2); a list
// longer than 270 scrolls. `dividerAfterFirst` sets the current choice
// apart (the spoken language list leads with it, then a divider, then
// every language).
Popup {
    id: root
    /// [{label, checked}]
    property var items: []
    property bool dividerAfterFirst: false
    signal picked(int index)
    padding: 4
    implicitWidth: Math.ceil(widest.value) + 2 * padding
    implicitHeight: Math.min(270, column.implicitHeight) + 2 * padding
    background: FluentSurface { depth: 16; radius: 4 }
    QtObject {
        id: widest
        readonly property real value: root.items.reduce((w, i) => Math.max(w, 26 + metrics.advanceWidth(i.label || "") + 6), 0)
            + (column.implicitHeight > 270 ? 14 : 0)
    }
    FontMetrics { id: metrics; font.family: theme.font; font.pixelSize: theme.base }
    /// Scroll the chosen row into view (as the list opens on it).
    function ensureCheckedVisible() { flick.contentY = 0 }

    contentItem: Flickable {
        id: flick
        clip: true
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: column.implicitHeight > 270 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }
        Column {
            id: column
            width: flick.width - (column.implicitHeight > 270 ? 14 : 0)
            spacing: 2
            Repeater {
                model: root.items
                Column {
                    id: entry
                    required property var modelData
                    required property int index
                    width: column.width
                    spacing: 0
                    Rectangle {
                        width: parent.width; height: 32; radius: 4
                        color: rowHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon {
                            visible: entry.modelData.checked === true
                            x: 6; y: 8; size: 16
                            name: "view-check-16"; color: rowHover.hovered ? theme.text : theme.textStrong
                        }
                        Text {
                            x: 26; width: parent.width - 32
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: entry.modelData.label || ""
                            font.family: theme.font; font.pixelSize: theme.base
                            color: rowHover.hovered ? theme.text : theme.textStrong
                        }
                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.close(); root.picked(entry.index) } }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: entry.modelData.label || ""
                        Accessible.checked: entry.modelData.checked === true
                    }
                    // A divider 6 below the row, then 6 to the next.
                    Item {
                        visible: root.dividerAfterFirst && entry.index === 0
                        width: parent.width; height: visible ? 10.67 : 0
                        Rectangle { y: 6; x: -root.padding; width: root.width; height: 0.67; color: theme.divider }
                    }
                }
            }
        }
    }
}
