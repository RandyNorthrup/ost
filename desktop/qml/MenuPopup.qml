import QtQuick
import QtQuick.Controls.Basic

// Teams' flyout menu (Fluent Menu), as measured in the client:
// - surface: padding 4, radius 4, shadow 16, sized to its widest item;
// - items: 32 tall with a gap of 2, padding 6, radius 4; a 20 px icon,
//   then a 4 px gap, then the label (14/20, NeutralForeground2);
//   hover NeutralBackground1Hover; disabled items #BDBDBD and inert;
// - dividers: 1 px, 4 above and below.
// items: [{ label, icon?, iconColor?, chevron?, keys?, checked?, separator?, enabled? }]; picking
// an enabled row emits picked(index) and closes.
Popup {
    id: root
    property var items: []
    signal picked(int index)
    readonly property bool hasIcons: items.some(i => !!i.icon || i.checked !== undefined)
    // Per-menu metrics (defaults: Teams' tab and status menus). The message
    // menu uses label 32, dividers 8.6, a 20 px chevron 5.6 from the right
    // and shortcut letters 8 from the right.
    property real labelInset: -1
    property real separatorHeight: 5
    property int chevronSize: 12
    property real chevronMargin: 8
    property real keysMargin: 6
    // An optional strip above the items (the right-click reactions), with a
    // divider under it.
    property Component header: null
    readonly property real labelX: labelInset >= 0 ? labelInset : hasIcons ? 30 : 6
    padding: 4
    implicitWidth: Math.min(290, Math.max(widest.value, 0)) + 8
    /// The pointer is over the menu (for menus that open on hover).
    readonly property bool hovered: surfaceHover.hovered
    background: FluentSurface { depth: 16; radius: 4; HoverHandler { id: surfaceHover } }
    QtObject {
        id: widest
        readonly property real value: {
            let w = 0
            for (const i of root.items) {
                if (i.separator) continue
                let row = root.labelX + metrics.advanceWidth(i.label || "") + 6
                if (i.keys) row += 24 + keyMetrics.advanceWidth(i.keys)
                if (i.chevron) row += root.chevronSize + root.chevronMargin
                w = Math.max(w, row)
            }
            return Math.ceil(w)
        }
    }
    FontMetrics { id: metrics; font.family: theme.font; font.pixelSize: theme.base }
    FontMetrics { id: keyMetrics; font.family: theme.font; font.pixelSize: theme.small }
    contentItem: Column {
        spacing: 2
        Loader {
            active: !!root.header
            visible: active
            width: root.width - 8
            sourceComponent: root.header
        }
        Item {
            visible: !!root.header
            width: root.width - 8; height: root.separatorHeight
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: -4; width: root.width; height: 1; color: theme.divider }
        }
        Repeater {
            model: root.items
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: modelData.enabled !== false
                readonly property color ink: !on ? theme.disabled : mh.hovered ? theme.text : theme.textStrong
                width: root.width - 8
                // A divider takes 1 px plus 4 above and below (the column's
                // 2 px gaps count towards those).
                height: modelData.separator ? root.separatorHeight : 32
                Rectangle {
                    visible: !!row.modelData.separator
                    anchors.verticalCenter: parent.verticalCenter
                    x: -4; width: root.width; height: 1; color: theme.divider
                }
                Rectangle {
                    visible: !row.modelData.separator
                    anchors.fill: parent; radius: 4
                    color: mh.hovered && row.on ? theme.menuHover : "transparent"
                    FluentIcon {
                        visible: !!row.modelData.icon
                        x: 6; anchors.verticalCenter: parent.verticalCenter; size: 20
                        name: row.modelData.icon || ""
                        color: row.modelData.iconColor ? row.modelData.iconColor : row.modelData.checked ? theme.brand : row.ink
                    }
                    FluentIcon {
                        visible: !row.modelData.icon && row.modelData.checked === true
                        x: 8; anchors.verticalCenter: parent.verticalCenter; size: 16
                        name: "checkmark-12"; color: row.ink
                    }
                    Text {
                        x: root.labelX; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 6; elide: Text.ElideRight
                        text: row.modelData.label || ""
                        font.family: theme.font; font.pixelSize: theme.base
                        color: row.ink
                    }
                    FluentIcon {
                        visible: !!row.modelData.chevron
                        anchors.right: parent.right; anchors.rightMargin: root.chevronMargin; anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-right-" + root.chevronSize; size: root.chevronSize; color: row.ink
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: root.keysMargin; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.keys || ""
                        font.family: theme.font; font.pixelSize: theme.small
                        color: row.on ? theme.textSecondary : theme.disabled
                    }
                    HoverHandler { id: mh; cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: row.on; onTapped: { root.close(); root.picked(row.index) } }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: row.modelData.label || ""
                    enabled: row.on
                }
            }
        }
    }
}
