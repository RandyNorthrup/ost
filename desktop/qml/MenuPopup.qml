import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Teams' flyout menu (Fluent Menu), as measured in the client:
// - surface: padding 4, radius 4, shadow 16, sized to its widest item;
// - items: 32 tall with a gap of 2, padding 6, radius 4; a 20 px icon,
//   then a 4 px gap, then the label (14/20, NeutralForeground2);
//   hover NeutralBackground1Hover; disabled items #BDBDBD and inert;
// - dividers: 1 px, 4 above and below.
// items: [{ label, icon?, iconColor?, chevron?, dot?, keys?, checked?, endCheck?, separator?,
// heading?, enabled?, submenu?, danger? }] (danger: a red row, colorPaletteRedForeground1 on
// colorPaletteRedBackground1 when hovered, as the recap templates' Delete) (heading: a group's title row, not pickable) (endCheck: Teams' 16 px check at the row's end, 6 in,
// as on More ▸ Record and transcribe ▸ Hide transcript; toggle: a Fluent
// switch row, 36 tall, its 40 x 20 track 8 in and the label at 60, as the
// RTT captions menu's "Live Captions": picking it leaves the menu open);
// picking an enabled row emits picked(index) and closes. A row
// with a submenu (a list of items) opens it beside the list on hover;
// picking there emits subPicked(index, subIndex). A `split` row with a
// submenu is Fluent's MenuSplitGroup (Teams' Mark all as read): the label
// part picks the row, and a 32 px chevron part after a 1 x 20 divider
// opens the submenu on hover or click.
// Teams' calendar menus add: `persist` rows that keep the menu open when
// picked (the Filter menu's checkboxes); `group` label rows (14/400, 8 in:
// "I'm the organizer"); `secondary` text at the row's end (Time scale's
// "30 minutes", 12 px #616161); `tag` {fill, stroke} for a category's tag
// glyph at 30 with the label at 56; `outlined` rows (a 0.67 #BDBDBD edge:
// "Filter applied"); and `radioColumn` menus (the view menu: a 16 px
// check 6 in, icons at 26, labels at 52).
// The keyboard, as Teams' Fluent menus take it (measured in Teams,
// 2026-11-27): the menu takes the focus when it opens, on its first row
// (no outline after a click). Down / Up move and wrap; Home / PageUp and
// End / PageDown go to the first and last row; a letter goes to the next
// row whose label starts with it (a row is picked by its own `keys`: the
// message menu's Q, E, F, S, Del, the text menu's Ctrl+C). Enter / Space pick (or open a row's
// submenu); Right opens a submenu on its first row (on a split row it
// first moves to the chevron part) and Left or Esc closes it again. Esc
// closes the menu and Tab / Shift+Tab close it too; the focus goes back to
// where it was. Hovering a row moves the keyboard there as well. The
// outline (2 px strokeFocus2, 2 px outside the row) shows once a key was
// used. Separators, headings and group labels are skipped; disabled rows
// are stops but can't be picked (Fluent's disabledFocusable).
Popup {
    id: root
    property var items: []
    signal picked(int index)
    signal subPicked(int index, int subIndex)
    /// A pick in a submenu's own submenu (the new controls' More ▸ View ▸
    /// Gallery size ▸).
    signal subSubPicked(int index, int subIndex, int subSubIndex)
    /// A row with `flyout: true` (a chevron) opens its owner's own popup
    /// beside it on hover, as a submenu would (Teams' Manage notifications):
    /// row is the row item, to place it by; -1 when another row is hovered.
    signal flyoutRequested(int index, Item row)
    /// Teams' View menu style: padding 16, the check mark at the row's end
    /// (16 px, 6 from the right), labels of rows without an icon at 10, and
    /// dividers spanning the surface with 10 px either side.
    property bool viewStyle: false
    /// Teams' new meeting controls' menus (More's list, its submenus and
    /// the controls' right-click menu): View's style with padding 12.67
    /// and 20.67 px dividers; a submenu that would leave the window ends
    /// level with its row's bottom instead.
    property bool newStyle: false
    /// OneDrive's (Fabric) context menu, as Teams' Files apps draw it: no
    /// padding, rows 36 tall with no gap, a 16 px icon 8 in, the label at
    /// 32, a 12 px chevron 8 from the right, 1 px dividers with 4 above and
    /// below; a fixed width (`fabricWidth`).
    property bool fabric: false
    property real fabricWidth: 216.67
    readonly property bool hasIcons: items.some(i => !!i.icon || i.checked !== undefined)
    // Per-menu metrics (defaults: Teams' tab and status menus). The message
    // menu uses label 32, dividers 8.6, a 20 px chevron 5.6 from the right
    // and shortcut letters 8 from the right.
    property real labelInset: -1
    property real separatorHeight: newStyle ? 20.67 : viewStyle ? 16.67 : fabric ? 9 : 5
    property int chevronSize: viewStyle ? 16 : 12
    property real chevronMargin: viewStyle ? 6 : 8
    property real keysMargin: 6
    // An optional strip above the items (the right-click reactions), with a
    // divider under it.
    property Component header: null
    readonly property real labelX: labelInset >= 0 ? labelInset : fabric ? 32 : hasIcons ? 30 : 6
    /// Fluent menus without hasIcons: only rows with an icon leave room
    /// for it (Teams' Pause notifications: "10 minutes" at 6,
    /// "Notifications settings" at 30).
    property bool perItemIcons: false
    /// Item rows this tall (Teams' Write with Copilot Adjust menu: 38);
    /// 0 keeps the default.
    property real rowHeight: 0
    /// A radio column's label (52 after icons; 28 in Teams' post composer
    /// menus, which have none) and the rows' gap (none in those menus).
    property real radioLabelX: 52
    property real rowSpacing: fabric ? 0 : 2
    function rowLabelX(i) { return radioColumn ? radioLabelX : i.tag ? 56 : checkColumn ? (i.icon ? 54 : 30) : perItemIcons ? (i.icon ? 30 : 6) : labelX }
    /// OneDrive's viewer menus (Preview's Share ▾ and ···): a dark Fabric
    /// callout, #1B1A19, padding 4, rows 36 tall with radius 2, #F3F2F1.
    property bool darkCallout: false
    padding: darkCallout ? 4 : newStyle ? 12.67 : viewStyle ? 16.67 : fabric ? 0 : 4
    /// Rows at least this wide (Teams' More menu and its submenus: 230).
    property real minRowWidth: 0
    /// Labels too long for the widest menu wrap (Fluent's MenuItem, as
    /// Teams desktop's New items ▸ "New message in new window"): the row
    /// grows by a line, its icon and keys stay with the first line.
    property bool wrapLabels: false
    /// Fluent's hasCheckmarks (Teams' tab dropdown): every row keeps a
    /// check column (the 16 px check 8 in), so icons sit at 30 and their
    /// labels at 54, and rows without an icon have their label at 30.
    property bool checkColumn: false
    /// Teams' calendar view menu: the check 6 in, icons at 26, labels at 52.
    property bool radioColumn: false
    /// Submenus' minimum row width; -1: as wide as this menu (Teams' More
    /// menu), 0: their own width (a split row's submenu, Teams' Mark all
    /// as read options).
    property real submenuMinWidth: -1
    implicitWidth: fabric ? fabricWidth : Math.min(290, Math.max(widest.value, minRowWidth)) + 2 * padding
    /// The pointer is over the menu (for menus that open on hover).
    readonly property bool hovered: surfaceHover.hovered
    background: FluentSurface { depth: 16; radius: 4; color: root.darkCallout ? theme.hc("#1B1A19", "#000000") : theme.menu; HoverHandler { id: surfaceHover } }
    // advanceWidth() is a call, not a property: a menu measured before
    // Selawik finished loading kept the fallback font's narrower widths and
    // elided its labels. Measure again each time the menu opens.
    property int measureRev: 0
    QtObject {
        id: widest
        readonly property real value: {
            root.measureRev
            let w = 0
            for (const i of root.items) {
                if (i.separator) continue
                let row = (i.toggle ? 60 : root.rowLabelX(i)) + metrics.advanceWidth(i.label || "") + (i.toggle ? 8 : 6)
                // A split row (Teams' Mark all as read): the keys 8.7 after
                // the label, then 8.6 to the 31 px chevron part.
                if (i.split) row += -6 + (i.keys ? 8.7 + keyMetrics.advanceWidth(i.keys) : 0) + 8.6 + 31
                else if (i.keys) row += 24 + keyMetrics.advanceWidth(i.keys)
                if (!i.split && (i.chevron || i.submenu || i.flyout)) row += root.chevronSize + root.chevronMargin
                if (i.endCheck !== undefined) row += 16 + 6
                if (i.endIcon) row += 4 + 20 + 8 - 6
                if (i.secondary) row += 6 + keyMetrics.advanceWidth(i.secondary) + 2
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
    /// Take the keyboard while open (see above); false leaves the keys
    /// (and the focus) where they are.
    property bool keyboardNavigation: true
    focus: keyboardNavigation
    /// The keyboard's row (the pointer's too), and on a split row its part
    /// ("chevron": the submenu part).
    property int current: -1
    property string currentPart: ""
    /// Draw the focus outline (a key was used; or opened from the keyboard,
    /// as an owner's Enter on its trigger sets it after open()).
    property bool focusRing: false
    /// The menu a submenu belongs to (null for a menu of its own).
    property var ownerMenu: null
    // The item that had the focus before the menu took it.
    property var restoreFocusItem: null
    function isStop(it) { return !!it && !it.separator && !it.heading && !it.group }
    /// The keyboard's stops in order: [{ i, part }].
    function stops() {
        const s = []
        for (let i = 0; i < items.length; i++) {
            const it = items[i]
            if (!isStop(it)) continue
            s.push({ i: i, part: "" })
            if (it.split && it.submenu) s.push({ i: i, part: "chevron" })
        }
        return s
    }
    function rowAt(i) { return rowsRepeater.itemAt(i) }
    // Whether the item is inside this menu itself, or in it or its open
    // submenu.
    function ownsDirectly(item) {
        const box = contentItem ? contentItem.parent : null
        for (let p = item; p; p = p.parent) if (p === box) return true
        return false
    }
    function owns(item) { return ownsDirectly(item) || (!!subMenu && subMenu.owns(item)) }
    // The keys are in this menu (not in its submenu): only then its row
    // shows the outline.
    readonly property bool keysHere: opened && !!contentItem && ownsDirectly(contentItem.Window.activeFocusItem)
    // The keyboard's row has the real focus (a screen reader follows it),
    // while the menu has the keyboard; the menu's Keys get the keys from it.
    function focusCurrent() {
        if (!opened || !keyboardNavigation || !contentItem) return
        const w = contentItem.Window.window
        const a = w ? w.activeFocusItem : null
        if (!a || !ownsDirectly(a)) return
        const r = rowAt(current)
        const target = !r ? contentItem : currentPart === "chevron" && r.chevronItem ? r.chevronItem : r.focusItem
        if (target !== a) target.forceActiveFocus()
    }
    // Take the keyboard back (from a submenu, or as a row is hovered).
    function takeKeys() {
        if (!opened || !keyboardNavigation) return
        const w = contentItem.Window.window
        if (!(w && w.activeFocusItem && ownsDirectly(w.activeFocusItem))) contentItem.forceActiveFocus()
        focusCurrent()
    }
    onCurrentChanged: focusCurrent()
    onCurrentPartChanged: focusCurrent()
    onOpened: focusCurrent()
    function goTo(stop) {
        if (!stop) return
        if (subMenu && subMenu.opened && stop.i !== subIndex) { subMenu.close(); subIndex = -1 }
        if (hasFlyout) root.flyoutRequested(-1, null)
        current = stop.i
        currentPart = stop.part
    }
    // Enter / Space (and Right on a submenu row): the row's tap.
    function activate(i, part) {
        const it = items[i]
        if (!isStop(it) || it.enabled === false) return
        if (it.split && part === "chevron") { if (it.submenu) hoverRow(i, rowAt(i), "chevron", true); return }
        if ((it.submenu || it.flyout) && !it.split) { hoverRow(i, rowAt(i), "", true); return }
        if (it.toggle || it.persist) { picked(i); return }
        close(); picked(i)
    }
    // A key press, and a row's `keys` text, as "ctrl+shift+c".
    function chordOf(e) {
        const m = []
        if (e.modifiers & Qt.ControlModifier) m.push("ctrl")
        if (e.modifiers & Qt.AltModifier) m.push("alt")
        if (e.modifiers & Qt.ShiftModifier) m.push("shift")
        if (e.modifiers & Qt.MetaModifier) m.push("meta")
        const k = (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) || (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) ? String.fromCharCode(e.key).toLowerCase()
            : e.key >= Qt.Key_F1 && e.key <= Qt.Key_F35 ? "f" + (e.key - Qt.Key_F1 + 1)
            : e.key === Qt.Key_Delete ? "del" : (e.text || "").toLowerCase()
        return m.sort().concat([k]).join("+")
    }
    function chordOfKeys(text) {
        const p = text.toLowerCase().split("+").map(x => x.trim())
        const k = p.pop()
        return p.map(x => x === "control" ? "ctrl" : x).sort().concat([k === "delete" ? "del" : k]).join("+")
    }
    function ownRow(e) {
        const c = chordOf(e)
        return items.findIndex(t => isStop(t) && t.enabled !== false && typeof t.keys === "string" && t.keys.length > 0 && chordOfKeys(t.keys) === c)
    }
    function handlesKey(e) {
        if (e.key !== Qt.Key_Escape && ownRow(e) >= 0) return true
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        switch (e.key) {
        case Qt.Key_Escape: case Qt.Key_Up: case Qt.Key_Down: case Qt.Key_Left: case Qt.Key_Right:
        case Qt.Key_Home: case Qt.Key_End: case Qt.Key_PageUp: case Qt.Key_PageDown:
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: case Qt.Key_Tab: case Qt.Key_Backtab:
            return true
        }
        return e.text.length === 1 && e.text.trim().length === 1
    }
    function keyPressed(e) {
        const rtl = Qt.application.layoutDirection === Qt.RightToLeft
        const forward = rtl ? Qt.Key_Left : Qt.Key_Right, back = rtl ? Qt.Key_Right : Qt.Key_Left
        if (e.key === Qt.Key_Escape) { close(); return }
        // A row's own key (the message menu's Q, E, F, S, P, U and Del, the
        // text menu's Ctrl+C): that row is picked.
        const own = ownRow(e)
        if (own >= 0) { current = own; currentPart = ""; activate(own, ""); return }
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            let top = root
            while (top.ownerMenu) top = top.ownerMenu
            const backwards = e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier)
            const prev = top.restoreFocusItem
            top.close()
            // Teams: Tab goes on to what follows the trigger.
            if (!backwards && prev && prev.Window.window) {
                const next = prev.nextItemInFocusChain(true)
                if (next && next !== prev) next.forceActiveFocus(Qt.TabFocusReason)
            }
            return
        }
        focusRing = true
        const s = stops()
        if (!s.length) return
        const k = s.findIndex(t => t.i === current && t.part === currentPart)
        const it = items[current]
        switch (e.key) {
        case Qt.Key_Down: goTo(s[k < 0 ? 0 : (k + 1) % s.length]); return
        case Qt.Key_Up: goTo(s[k < 0 ? s.length - 1 : (k - 1 + s.length) % s.length]); return
        case Qt.Key_Home: case Qt.Key_PageUp: goTo(s[0]); return
        case Qt.Key_End: case Qt.Key_PageDown: goTo(s[s.length - 1]); return
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: if (k >= 0) activate(current, currentPart); return
        }
        if (e.key === forward) {
            if (!it || it.enabled === false) return
            if (it.split) { if (currentPart !== "chevron") { if (it.submenu) currentPart = "chevron" } else activate(current, "chevron") }
            else if (it.submenu || it.flyout || it.chevron) activate(current, "")
            return
        }
        if (e.key === back) {
            if (it && it.split && currentPart === "chevron") currentPart = ""
            else if (ownerMenu) close()
            return
        }
        // Typeahead: the next row (after this one, wrapping) whose label
        // starts with the letter.
        const ch = e.text.toLowerCase()
        const rows = s.filter(t => t.part === "")
        const from = rows.findIndex(t => t.i === current)
        for (let n = 1; n <= rows.length; n++) {
            const t = rows[(from + n) % rows.length]
            if ((items[t.i].label || "").charAt(0).toLowerCase() === ch) { goTo(t); return }
        }
    }
    function restoreFocus() {
        const p = restoreFocusItem
        restoreFocusItem = null
        if (!p || !keyboardNavigation) return
        const w = p.Window.window
        if (!w) return
        // A pick that moved the focus on purpose keeps it.
        const a = w.activeFocusItem
        if (a && a !== w.contentItem && a.visible && !owns(a)) return
        if (p.visible && p.enabled) p.forceActiveFocus()
    }
    onAboutToShow: {
        measureRev++
        const s = stops()
        current = s.length ? s[0].i : -1
        currentPart = s.length ? s[0].part : ""
        focusRing = false
        if (!ownerMenu) {
            const w = (root.parent && root.parent.Window.window) || (contentItem && contentItem.Window.window)
            const a = w ? w.activeFocusItem : null
            restoreFocusItem = a && !owns(a) ? a : null
        }
    }
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
                ownerMenu: root,
                viewStyle: Qt.binding(() => root.viewStyle),
                newStyle: Qt.binding(() => root.newStyle),
                fabric: Qt.binding(() => root.fabric),
                darkCallout: Qt.binding(() => root.darkCallout),
                fabricWidth: Qt.binding(() => root.darkCallout ? root.fabricWidth : 232),
                minRowWidth: Qt.binding(() => root.submenuMinWidth >= 0 ? root.submenuMinWidth : root.width - 2 * root.padding) })
            subMenu.picked.connect(i => {
                const s = root.subIndex, it = subMenu.items[i]
                if (!(it && it.persist)) root.close()
                root.subPicked(s, i)
            })
            // Left or Esc in the submenu: the keyboard is back on its row.
            subMenu.closed.connect(() => root.takeKeys())
            subMenu.subPicked.connect((i, j) => {
                const s = root.subIndex, it = subMenu.items[i] && subMenu.items[i].submenu ? subMenu.items[i].submenu[j] : null
                if (!(it && it.persist)) root.close()
                root.subSubPicked(s, i, j)
            })
        }
        return subMenu
    }
    readonly property bool hasFlyout: items.some(i => i && i.flyout === true)
    function hoverRow(i, rowItem, part, viaKeys) {
        const it0 = items[i]
        // Fluent: the hovered row takes the focus (back from a submenu).
        if (isStop(it0)) { current = i; currentPart = part === "chevron" && it0.split ? "chevron" : "" }
        if (!viaKeys) takeKeys()
        // A split row's label part never opens its submenu.
        if (it0 && it0.split && part !== "chevron") {
            if (subMenu) subMenu.close()
            subIndex = -1
            return
        }
        if (it0 && it0.flyout === true && it0.enabled !== false) {
            if (subMenu) subMenu.close()
            subIndex = -1
            root.flyoutRequested(i, rowItem)
            return
        }
        if (hasFlyout) root.flyoutRequested(-1, null)
        if (!subMenu && !(it0 && it0.submenu)) return
        const sub = submenu()
        const it = items[i]
        if (!it || !it.submenu || it.enabled === false) { sub.close(); subIndex = -1; return }
        subIndex = i
        const p = rowItem.mapToItem(root.contentItem, 0, 0)
        sub.items = it.submenu
        // Beside the list, or to its left (More, at the window's right).
        // OneDrive's submenus sit 4 px off the list, 4 below the row's top.
        sub.x = root.submenuLeft ? -sub.width : root.contentItem.width + (root.fabric ? 4 : 0)
        // Fluent flips a submenu that would leave the window to the left.
        if (!root.submenuLeft) {
            const ww = root.contentItem.Window.width
            const right = root.contentItem.mapToItem(null, sub.x, 0).x + sub.implicitWidth
            if (ww > 0 && right > ww) sub.x = -sub.implicitWidth - root.padding
        }
        sub.y = p.y + (root.fabric ? 4 : 0)
        if (root.newStyle) {
            // Fluent flips a submenu that won't fit below: its bottom level
            // with the row's bottom (Teams' More ▸ View, ▸ Settings).
            const win = root.contentItem.Window.window
            const top = root.contentItem.mapToItem(null, 0, p.y).y
            if (win && top + sub.implicitHeight > win.height)
                sub.y = p.y + rowItem.height - sub.implicitHeight
        }
        sub.open()
        // Opened from the keyboard: the outline on its first row.
        if (viaKeys || root.focusRing) sub.focusRing = true
        // Once laid out with its rows (its size can lag the new items),
        // keep it on screen: flipped left past the window's right, lifted
        // to end above the window's bottom.
        Qt.callLater(() => {
            if (!sub.opened) return
            const win = root.contentItem.Window.window
            if (!win) return
            if (!root.submenuLeft) {
                const right = root.contentItem.mapToItem(null, sub.x, 0).x + sub.width
                if (right > win.width) sub.x = -sub.width - root.padding
            }
            const top = root.contentItem.mapToItem(null, 0, sub.y).y
            if (top + sub.height > win.height) sub.y = Math.max(-top + sub.y + 8, sub.y - (top + sub.height - win.height) - 8)
        })
    }
    onClosed: {
        if (subMenu) subMenu.close()
        if (!ownerMenu) restoreFocus()
    }
    // A persistent pick changes the rows (a checkbox): an open submenu
    // shows its row's new list.
    onItemsChanged: {
        if (subMenu && subMenu.opened && subIndex >= 0) {
            const it = items[subIndex]
            if (it && it.submenu) subMenu.items = it.submenu
            else { subMenu.close(); subIndex = -1 }
        }
        // The rows are made again: the keyboard's row gets the focus back.
        if (opened) Qt.callLater(focusCurrent)
    }
    /// Open row `i`'s submenu as hovering it would (tests).
    function openSubmenuForTest(i) {
        const rows = contentItem.children.filter(c => c.index === i)
        if (rows.length) hoverRow(i, rows[0], "chevron")
    }
    contentItem: Column {
        spacing: root.rowSpacing
        focus: true
        // The menu's keys come first: a window's Shortcut (Escape) doesn't
        // take them while it is open.
        Keys.onShortcutOverride: e => { if (root.keyboardNavigation && root.handlesKey(e)) e.accepted = true }
        Keys.onPressed: e => { if (root.keyboardNavigation && root.handlesKey(e)) { e.accepted = true; root.keyPressed(e) } }
        Loader {
            active: !!root.header
            visible: active
            width: root.width - 2 * root.padding
            sourceComponent: root.header
        }
        Item {
            visible: !!root.header
            width: root.width - 2 * root.padding; height: root.separatorHeight
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: -root.padding; width: root.width; height: 1; color: theme.divider }
        }
        Repeater {
            id: rowsRepeater
            model: root.items
            Item {
                id: row
                required property var modelData
                required property int index
                // What the keyboard focuses: the row's accessible item, or
                // a split row's chevron part. A disabled row can't take the
                // focus there, so the row itself does, named for it.
                readonly property Item chevronItem: splitPart
                readonly property Item focusItem: row.on ? hcFill1 : row
                Accessible.role: Accessible.MenuItem
                Accessible.name: row.modelData.label || ""
                Accessible.ignored: row.on || !root.isStop(row.modelData)
                readonly property bool on: modelData.enabled !== false && !modelData.heading && !modelData.group
                readonly property color ink: !on ? theme.disabled : modelData.danger ? theme.redForeground1 : root.darkCallout ? theme.hc("#F3F2F1", "#FFFFFF") : mh.hovered ? theme.text : theme.textStrong
                width: root.width - 2 * root.padding
                // A divider takes 1 px plus 4 above and below (the column's
                // 2 px gaps count towards those).
                height: modelData.separator ? root.separatorHeight : modelData.outlined ? 33.33 : root.rowHeight > 0 && !modelData.heading ? root.rowHeight : modelData.toggle || root.fabric ? 36
                    : root.wrapLabels ? Math.max(32, rowLabel.implicitHeight + 12) : 32
                readonly property bool wrapped: height > 32 && root.wrapLabels
                Rectangle {
                    visible: !!row.modelData.separator
                    anchors.verticalCenter: parent.verticalCenter
                    // One physical pixel (Teams' 0.67 CSS px at 150 %); thinner
                    // vanishes at a fractional y on a 100 % display.
                    x: -root.padding; width: root.width; height: root.viewStyle ? Math.max(0.67, 1 / Screen.devicePixelRatio) : 1; color: theme.divider
                }
                // A group's heading (Teams' Controls: "Allow all
                // participants to:", 12/600 #616161, 32 tall, 8 px in).
                Text {
                    visible: !!row.modelData.heading
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.heading || ""
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.textSecondary
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                // A group's label (Teams' calendar Filter > Meetings: "I'm the
                // organizer", 14/400 #242424, 8 px in).
                Text {
                    visible: !!row.modelData.group
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.group || ""
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Rectangle {
                    id: hcFill1
                    visible: !row.modelData.separator && !row.modelData.heading && !row.modelData.group
                    anchors.fill: parent; radius: root.darkCallout ? 2 : root.fabric ? 0 : 4
                    color: (mh.hovered || (root.subIndex === row.index && (row.modelData.outlined || (!!row.modelData.submenu && !!root.subMenu && root.subMenu.visible)))) && row.on && !row.modelData.toggle && !row.modelData.split ? (root.darkCallout ? theme.hc("#323130", "#1AEBFF") : row.modelData.danger ? theme.redBackground1 : theme.menuHover) : "transparent"
                    border.width: row.modelData.outlined ? 0.67 : 0
                    border.color: theme.hc("#BDBDBD", "#FFFFFF")
                    // A split row: the label part and the chevron part
                    // highlight on their own (Fluent's MenuSplitGroup).
                    Rectangle {
                        visible: !!row.modelData.split
                        width: parent.width - 31; height: parent.height; radius: 4
                        color: mh.hovered && !splitHover.hovered && row.on ? theme.menuHover : "transparent"
                    }
                    Rectangle {
                        id: splitPart
                        visible: !!row.modelData.split
                        anchors.right: parent.right
                        width: 31; height: parent.height; radius: 4
                        color: (splitHover.hovered || root.subIndex === row.index) && row.on ? theme.menuHover : "transparent"
                        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.divider }
                        FluentIcon {
                            anchors.centerIn: parent; anchors.horizontalCenterOffset: 0.5
                            name: "chevron-right-16"; size: 16; color: theme.onFill(hcFill1, row.ink)
                        }
                        HoverHandler {
                            id: splitHover; cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onHoveredChanged: if (hovered) root.hoverRow(row.index, row, "chevron")
                        }
                        TapHandler { enabled: row.on; onTapped: root.hoverRow(row.index, row, "chevron") }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: row.modelData.splitLabel || ""
                    }
                    // The keyboard's outline (Fluent's focus stroke: 2 px
                    // strokeFocus2, 2 px outside the row or the split part).
                    Rectangle {
                        readonly property bool chevronPart: !!row.modelData.split && root.currentPart === "chevron"
                        visible: root.focusRing && root.keysHere && root.current === row.index
                        x: (chevronPart ? parent.width - 31 : 0) - 2; y: -2
                        width: (chevronPart ? 31 : row.modelData.split ? parent.width - 31 : parent.width) + 4
                        height: parent.height + 4
                        radius: 4; color: "transparent"
                        border.width: 2; border.color: theme.dark || theme.highContrast ? "#FFFFFF" : "#000000"
                    }
                    // A switch row's track and knob.
                    Rectangle {
                        visible: !!row.modelData.toggle
                        x: 8; y: 8; width: 40; height: 20; radius: 10
                        color: row.modelData.checked ? (mh.hovered ? theme.brandHover : theme.checkedFill) : "transparent"
                        border.color: row.modelData.checked ? "transparent" : (mh.hovered ? theme.text : theme.textStrong)
                        border.width: 0.67
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            x: row.modelData.checked ? parent.width - width - 3 : 3
                            color: row.modelData.checked ? theme.hc("white", "#1AEBFF") : (mh.hovered ? theme.text : theme.textStrong)
                        }
                    }
                    FluentIcon {
                        visible: !!row.modelData.icon
                        x: root.radioColumn ? 26 : root.checkColumn ? 30 : root.fabric ? 8 : 6; y: row.wrapped ? 6 : (parent.height - height) / 2; size: root.fabric ? 16 : 20
                        name: row.modelData.icon || ""
                        // Teams' new-controls menus turn a hovered row's
                        // glyph brand (Fluent's MenuItem icon hover).
                        color: theme.onFill(hcFill1, row.modelData.iconColor ? row.modelData.iconColor
                                            : row.modelData.checked || (root.newStyle && mh.hovered && row.on) ? theme.brand : row.ink)
                    }
                    FluentIcon {
                        visible: !root.viewStyle && (!row.modelData.icon || root.checkColumn || root.radioColumn) && !row.modelData.toggle && row.modelData.checked === true
                        x: root.radioColumn ? 6 : 8; anchors.verticalCenter: parent.verticalCenter; size: 16
                        name: "checkmark-12"; color: theme.onFill(hcFill1, row.ink)
                    }
                    // An icon at the row's end (Teams' Start reordering
                    // carries the accessibility figure, 8 from the edge).
                    FluentIcon {
                        visible: !!row.modelData.endIcon
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; size: 20
                        name: row.modelData.endIcon || ""; color: theme.onFill(hcFill1, row.ink)
                    }
                    FluentIcon {
                        visible: row.modelData.endCheck === true
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 8.67; size: 16
                        name: "view-check-16"; color: theme.onFill(hcFill1, row.ink)
                    }
                    FluentIcon {
                        visible: root.viewStyle && !row.modelData.toggle && row.modelData.checked === true
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 8; size: 16
                        name: "view-check-16"; color: theme.onFill(hcFill1, row.ink)
                    }
                    // A category's tag: its fill and outline glyphs at 30.
                    Item {
                        visible: !!row.modelData.tag
                        x: 30; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
                        FluentIcon { anchors.fill: parent; name: "tag-20-filled"; size: 20; color: row.modelData.tag ? row.modelData.tag.fill : "transparent" }
                        FluentIcon { anchors.fill: parent; name: "tag-20"; size: 20; color: row.modelData.tag ? row.modelData.tag.stroke : "transparent" }
                    }
                    Text {
                        id: secondaryText
                        visible: !!row.modelData.secondary
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.secondary || ""
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.onFill(hcFill1, row.on ? theme.textSecondary : theme.disabled)
                    }
                    Text {
                        id: rowLabel
                        x: row.modelData.toggle ? 60 : root.viewStyle && !row.modelData.icon ? 10 : root.rowLabelX(row.modelData); y: row.wrapped ? 6 : (parent.height - height) / 2
                        width: parent.width - x - 6 - (secondaryText.visible ? secondaryText.implicitWidth + 8 : 0)
                            - (root.wrapLabels && row.modelData.keys ? 24 + keysText.implicitWidth : 0)
                        elide: root.wrapLabels ? Text.ElideNone : Text.ElideRight
                        wrapMode: root.wrapLabels ? Text.Wrap : Text.NoWrap
                        lineHeight: root.wrapLabels ? 20 : 1; lineHeightMode: root.wrapLabels ? Text.FixedHeight : Text.ProportionalHeight
                        text: row.modelData.label || ""
                        font.family: theme.font; font.pixelSize: theme.base
                        color: theme.onFill(hcFill1, row.modelData.toggle ? theme.text : row.ink)
                    }
                    // A colour dot before the chevron (OneDrive's Folder color).
                    Rectangle {
                        visible: !!row.modelData.dot
                        anchors.right: parent.right; anchors.rightMargin: root.chevronMargin + root.chevronSize + 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12; radius: 6
                        color: row.modelData.dot || "transparent"
                    }
                    FluentIcon {
                        visible: (!!row.modelData.chevron || !!row.modelData.submenu || !!row.modelData.flyout) && row.modelData.chevron !== false && !row.modelData.split
                        anchors.right: parent.right; anchors.rightMargin: root.chevronMargin; anchors.verticalCenter: parent.verticalCenter
                        name: root.viewStyle ? "view-chevron-16" : "chevron-right-" + root.chevronSize; size: root.chevronSize; color: theme.onFill(hcFill1, row.ink)
                    }
                    Text {
                        id: keysText
                        // Before a check row's 16 px check (6 either side).
                        anchors.right: parent.right; y: row.wrapped ? 6 + (20 - height) / 2 : (parent.height - height) / 2
                        anchors.rightMargin: row.modelData.split ? 31 + 8.6 : root.keysMargin + (row.modelData.endCheck !== undefined ? 22 : 0)
                        text: row.modelData.keys || ""
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.onFill(hcFill1, row.on ? theme.textSecondary : theme.disabled)
                    }
                    HoverHandler {
                        id: mh; cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onHoveredChanged: if (hovered && !splitHover.hovered) root.hoverRow(row.index, row)
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
                        onTapped: (ev) => {
                            // A split row's chevron part has its own tap.
                            if (row.modelData.split && ev.position.x > hcFill1.width - 31) return
                            if ((row.modelData.submenu || row.modelData.flyout) && !row.modelData.split) { root.hoverRow(row.index, row); return }
                            if (row.modelData.toggle || row.modelData.persist) { root.picked(row.index); return }
                            root.close(); root.picked(row.index)
                        }
                    }
                    Accessible.role: row.modelData.toggle ? Accessible.CheckBox : Accessible.MenuItem
                    Accessible.checkable: !!row.modelData.toggle
                    Accessible.checked: !!row.modelData.toggle && row.modelData.checked === true
                    Accessible.name: row.modelData.label || ""
                    enabled: row.on
                }
            }
        }
    }
}
