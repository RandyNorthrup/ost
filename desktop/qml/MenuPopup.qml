import QtQuick
import QtQuick.Controls.Basic

// Teams' flyout menu (Fluent Menu), as measured in the client:
// - surface: padding 4, radius 4, shadow 16, sized to its widest item;
// - items: 32 tall with a gap of 2, padding 6, radius 4; a 20 px icon,
//   then a 4 px gap, then the label (14/20, NeutralForeground2);
//   hover NeutralBackground1Hover; disabled items #BDBDBD and inert;
// - dividers: 1 px, 4 above and below.
// items: [{ label, icon?, iconColor?, chevron?, keys?, checked?, endCheck?, separator?,
// enabled?, submenu? }] (endCheck: Teams' 16 px check at the row's end, 6 in,
// as on More ▸ Record and transcribe ▸ Hide transcript); picking an enabled row emits picked(index) and closes. A row
// with a submenu (a list of items) opens it beside the list on hover;
// picking there emits subPicked(index, subIndex).
Popup {
    id: root
    property var items: []
    signal picked(int index)
    signal subPicked(int index, int subIndex)
    /// Teams' View menu style: padding 16, the check mark at the row's end
    /// (16 px, 6 from the right), labels of rows without an icon at 10, and
    /// dividers spanning the surface with 10 px either side.
    property bool viewStyle: false
    readonly property bool hasIcons: items.some(i => !!i.icon || i.checked !== undefined)
    // Per-menu metrics (defaults: Teams' tab and status menus). The message
    // menu uses label 32, dividers 8.6, a 20 px chevron 5.6 from the right
    // and shortcut letters 8 from the right.
    property real labelInset: -1
    property real separatorHeight: viewStyle ? 16.67 : 5
    property int chevronSize: viewStyle ? 16 : 12
    property real chevronMargin: viewStyle ? 6 : 8
    property real keysMargin: 6
    // An optional strip above the items (the right-click reactions), with a
    // divider under it.
    property Component header: null
    readonly property real labelX: labelInset >= 0 ? labelInset : hasIcons ? 30 : 6
    padding: viewStyle ? 16.67 : 4
    /// Rows at least this wide (Teams' More menu and its submenus: 230).
    property real minRowWidth: 0
    implicitWidth: Math.min(290, Math.max(widest.value, minRowWidth)) + 2 * padding
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
                if (i.chevron || i.submenu) row += root.chevronSize + root.chevronMargin
                if (i.endCheck !== undefined) row += 16 + 6
                w = Math.max(w, row)
            }
            return Math.ceil(w)
        }
    }
    FontMetrics { id: metrics; font.family: theme.font; font.pixelSize: theme.base }
    FontMetrics { id: keyMetrics; font.family: theme.font; font.pixelSize: theme.small }
    // The open submenu: beside the list (overlapping our padding), its
    // list's top level with the row's top, as Teams' View menu opens them.
    property int subIndex: -1
    /// Open submenus to the left of the list (Teams' More menu).
    property bool submenuLeft: false
    // A submenu is this same menu, made on first use (QML won't nest a
    // type inside itself).
    property var subMenu: null
    function submenu() {
        if (!subMenu) {
            // At least as wide as this menu (Teams' submenus match More's
            // 230), wider when a row needs it.
            subMenu = Qt.createComponent("MenuPopup.qml").createObject(root.contentItem, {
                viewStyle: Qt.binding(() => root.viewStyle),
                minRowWidth: Qt.binding(() => root.width - 2 * root.padding) })
            subMenu.picked.connect(i => { const s = root.subIndex; root.close(); root.subPicked(s, i) })
        }
        return subMenu
    }
    function hoverRow(i, rowItem) {
        const it0 = items[i]
        if (!subMenu && !(it0 && it0.submenu)) return
        const sub = submenu()
        const it = items[i]
        if (!it || !it.submenu || it.enabled === false) { sub.close(); subIndex = -1; return }
        subIndex = i
        const p = rowItem.mapToItem(root.contentItem, 0, 0)
        sub.items = it.submenu
        // Beside the list, or to its left (More, at the window's right).
        sub.x = root.submenuLeft ? -sub.width : root.contentItem.width
        sub.y = p.y
        sub.open()
    }
    onClosed: if (subMenu) subMenu.close()
    /// Open row `i`'s submenu as hovering it would (tests).
    function openSubmenuForTest(i) {
        const rows = contentItem.children.filter(c => c.index === i)
        if (rows.length) hoverRow(i, rows[0])
    }
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
            width: root.width - 2 * root.padding; height: root.separatorHeight
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: -root.padding; width: root.width; height: 1; color: theme.divider }
        }
        Repeater {
            model: root.items
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: modelData.enabled !== false
                readonly property color ink: !on ? theme.disabled : mh.hovered ? theme.text : theme.textStrong
                width: root.width - 2 * root.padding
                // A divider takes 1 px plus 4 above and below (the column's
                // 2 px gaps count towards those).
                height: modelData.separator ? root.separatorHeight : 32
                Rectangle {
                    visible: !!row.modelData.separator
                    anchors.verticalCenter: parent.verticalCenter
                    x: -root.padding; width: root.width; height: root.viewStyle ? 0.67 : 1; color: theme.divider
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
                        visible: !root.viewStyle && !row.modelData.icon && row.modelData.checked === true
                        x: 8; anchors.verticalCenter: parent.verticalCenter; size: 16
                        name: "checkmark-12"; color: row.ink
                    }
                    FluentIcon {
                        visible: row.modelData.endCheck === true
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 8.67; size: 16
                        name: "view-check-16"; color: row.ink
                    }
                    FluentIcon {
                        visible: root.viewStyle && row.modelData.checked === true
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 8; size: 16
                        name: "view-check-16"; color: row.ink
                    }
                    Text {
                        x: root.viewStyle && !row.modelData.icon ? 10 : root.labelX; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 6; elide: Text.ElideRight
                        text: row.modelData.label || ""
                        font.family: theme.font; font.pixelSize: theme.base
                        color: row.ink
                    }
                    FluentIcon {
                        visible: !!row.modelData.chevron || !!row.modelData.submenu
                        anchors.right: parent.right; anchors.rightMargin: root.chevronMargin; anchors.verticalCenter: parent.verticalCenter
                        name: root.viewStyle ? "view-chevron-16" : "chevron-right-" + root.chevronSize; size: root.chevronSize; color: row.ink
                    }
                    Text {
                        // Before a check row's 16 px check (6 either side).
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: root.keysMargin + (row.modelData.endCheck !== undefined ? 22 : 0)
                        text: row.modelData.keys || ""
                        font.family: theme.font; font.pixelSize: theme.small
                        color: row.on ? theme.textSecondary : theme.disabled
                    }
                    HoverHandler {
                        id: mh; cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onHoveredChanged: if (hovered) root.hoverRow(row.index, row)
                    }
                    // A row's tooltip (`tip`), 10 px after the row, centred
                    // on it, as Teams' Record and transcribe items show it.
                    ToolTip {
                        id: rowTip
                        visible: !!row.modelData.tip && mh.hovered
                        delay: 250
                        topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
                        x: row.width + 10
                        y: (row.height - implicitHeight) / 2
                        contentItem: Text {
                            text: row.modelData.tip || ""
                            font.family: theme.font; font.pixelSize: 12
                            lineHeight: 16; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        background: Item {
                            FluentSurface { anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }
                            Rectangle {
                                width: 8.48; height: 8.48; rotation: 45
                                color: theme.surface
                                x: -width / 2; y: rowTip.implicitHeight / 2 - height / 2
                            }
                        }
                    }
                    TapHandler {
                        enabled: row.on
                        onTapped: {
                            if (row.modelData.submenu) { root.hoverRow(row.index, row); return }
                            root.close(); root.picked(row.index)
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: row.modelData.label || ""
                    enabled: row.on
                }
            }
        }
    }
}
