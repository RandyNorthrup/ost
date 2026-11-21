import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Loop's formatting toolbar ("commanding surface") as Teams draws it for a
// Loop page or component (docs/spec/loop-host.md): Loop hands its commands
// to the host's CommandingSurfaceTreeViewProvider (loop_host.js) and Teams
// draws them in its own page over the frame, as its CommandingSurfaceV9
// in the legacy style (Teams 26304: 425275 the provider, 577697 the
// surface, 836862 the icons):
// - a Fluent popover (radius 16, NeutralBackground1, shadow 8, padding 8,
//   200 to 320 wide) whose top-left corner is Loop's point (the frame's
//   corner plus Loop's clientX / clientY), below and start-aligned, moved
//   above when there's no room below;
// - the top bar: a row (padding 0 4, spread out) of 32 x 32 subtle buttons
//   with 16 px glyphs, toggles (Bold, Italic…) as checkable buttons, a
//   command with its own commands a menu button, then Teams' "More" toggle
//   (FFXCMore) that shows or hides the rest; each button's tooltip is the
//   command's name;
// - the rest (expanded: right-click, Shift+F10, or More): a menu divider,
//   then Loop's command groups as Fluent menu groups (a 12 px semibold
//   header when the group has a title, 32 px items with 20 px glyphs and
//   the shortcut at the end, checkmarks for toggles, submenus beside), a
//   divider between groups.
// Picking a command runs it in Loop and closes the surface, giving the
// focus back to the page; Escape closes it too. Selecting text shows the
// top bar alone and leaves the focus in the page; a right-click or
// Shift+F10 shows it all and moves the focus to its first button.
// The glyphs are Teams' own (assets/icons/loop-commanding.json, by Loop's
// icon names). The commands' names come from Loop.
Popup {
    id: pop
    /// Loop's display: {seq, top, main, mini, focus, position, align}.
    property var surface: null
    property bool mini: true
    /// Loop's point in the parent's coordinates.
    property real anchorX: 0
    property real anchorY: 0
    signal exec(string key, int seq)
    signal dismissed(int seq)
    /// The web view to give the focus back to.
    property Item view: null

    padding: 8
    margins: 4
    focus: !!surface && !!surface.focus
    closePolicy: Popup.NoAutoClose
    width: Math.min(320, Math.max(200, implicitContentWidth + leftPadding + rightPadding))
    background: FluentSurface { depth: 8; radius: 16; color: theme.menu }

    // Teams' icons (by Loop's names: FFXCBold…), read once when a surface
    // is first shown.
    property var icons: ({})
    function loadIcons() {
        const k = "loop-commanding-icons"
        let m = IconCache.get(k)
        if (m === undefined) {
            const x = new XMLHttpRequest()
            x.open("GET", Qt.resolvedUrl("../assets/icons/loop-commanding.json"), false)
            x.send()
            try { m = JSON.parse(x.responseText) } catch (e) { m = {}; console.warn("LOOPHOST commanding icons unreadable") }
            IconCache.put(k, m)
        }
        icons = m
    }
    function iconSource(name, color) {
        const svg = icons[name]
        return svg ? "data:image/svg+xml;utf8," + encodeURIComponent(svg.replace(/#212121/g, color.toString())) : ""
    }
    // An icon name that is an emoji (Teams draws those as text).
    function isEmoji(name) { return !!name && name.indexOf("FFX") !== 0 && name.length <= 12 && /[^\x00-\x7f]/.test(name) }

    // Teams' rendering of Loop's lists: inline groups flatten into the top
    // bar; in a menu they're groups with a header and dividers between.
    function topItems(list) {
        let out = []
        for (const c of list || []) {
            if (c.inline && c.sub) out = out.concat(topItems(c.sub))
            else if (c.id === "divider") out.push({ kind: "divider" })
            else out.push({ kind: c.sub ? "menu" : "button", cmd: c })
        }
        return out
    }
    function menuRows(list) {
        let out = []
        const l = list || []
        for (let i = 0; i < l.length; i++) {
            const c = l[i]
            if (c.inline && c.sub) {
                if (c.title) out.push({ kind: "header", text: c.title })
                out = out.concat(menuRows(c.sub))
                if (i < l.length - 1) out.push({ kind: "divider" })
            } else out.push({ kind: "item", cmd: c })
        }
        return out
    }
    function anyOf(list, f) { return (list || []).some(c => f(c) || (c.inline && c.sub && anyOf(c.sub, f))) }

    readonly property var top: surface && surface.top.length ? topItems(surface.top).concat([{ kind: "more" }]) : []
    readonly property var rows: surface && !mini ? menuRows(surface.main) : []
    readonly property bool rowChecks: anyOf(surface ? surface.main : [], c => c.toggle)
    readonly property bool rowIcons: anyOf(surface ? surface.main : [], c => !!c.icon)

    // Keyboard: the focused button (top bar) or row (the rest), as Teams'
    // arrow navigation: left / right in the top bar, up / down in the menu,
    // down from the top bar to the menu. Disabled buttons stay focusable
    // (Fluent's disabledFocusable).
    property string area: "top"
    property int cur: 0
    property bool keyboard: false
    readonly property var topFocusable: top.map((t, i) => t.kind === "divider" ? -1 : i).filter(i => i >= 0)
    readonly property var rowFocusable: rows.map((r, i) => r.kind === "item" ? i : -1).filter(i => i >= 0)

    function show(d, ax, ay) {
        if (!Object.keys(icons).length) loadIcons()
        closeSubs()
        surface = d
        mini = !!d.mini
        anchorX = ax; anchorY = ay
        area = top.length ? "top" : "main"
        cur = area === "top" ? (topFocusable[0] || 0) : (rowFocusable[0] || 0)
        keyboard = !!d.focus
        if (!opened) open()
        place()
        if (d.focus) bodyItem.forceActiveFocus()
    }
    function hide() {
        closeSubs()
        surface = null
        close()
    }
    // Picking or Escape: Loop runs the command (or not) and closes it.
    function pick(cmd) {
        if (!cmd || cmd.disabled || !surface) return
        const s = surface.seq
        hide()
        if (view) view.forceActiveFocus()
        exec(cmd.key, s)
    }
    // Escape gives the focus back to the page; a click elsewhere keeps it
    // where it went.
    function dismiss(keepFocus) {
        if (!surface) return
        const s = surface.seq
        hide()
        if (view && !keepFocus) view.forceActiveFocus()
        dismissed(s)
    }
    function toggleMore() { mini = !mini; Qt.callLater(place) }

    // Below the point, start-aligned; above it when it doesn't fit below
    // (Fluent's fallback), kept in the window by the margins.
    function place() {
        if (!parent) return
        x = anchorX
        const w = parent.Window.window
        const p = parent.mapToItem(null, anchorX, anchorY)
        const h = implicitHeight
        y = surface && surface.position === "above" ? anchorY - h
            : w && p.y + h > w.height - margins && p.y - h >= margins ? anchorY - h : anchorY
    }
    onImplicitHeightChanged: if (opened) place()

    // Clicking anywhere else in OST (or into the page with the surface
    // focused, Teams' closeOnIframeFocus) closes it.
    Connections {
        target: pop.parent ? pop.parent.Window.window : null
        function onActiveFocusItemChanged() {
            if (!pop.opened || !pop.surface) return
            const f = pop.parent.Window.window.activeFocusItem
            if (!f || pop.within(f)) return
            if (f === pop.view && !pop.surface.focus) return
            pop.dismiss(true)
        }
    }
    // An item in the surface or one of its submenus (their popup items).
    function within(item) {
        const roots = [pop.contentItem.parent].concat(subs.map(s => s.contentItem.parent))
        for (let i = item; i; i = i.parent) if (roots.indexOf(i) >= 0) return true
        return false
    }

    // Submenus (a top-bar menu button's or a row's own commands): Fluent
    // menus with the same surface, below the button or beside the row.
    property var subs: []
    function closeSubs(from) {
        const keep = from === undefined ? 0 : from
        const l = subs.slice()
        while (l.length > keep) { const s = l.pop(); s.close(); s.destroy() }
        subs = l
    }
    function openSub(cmd, item, level, below, byKeys) {
        closeSubs(level)
        if (!item || !pop.parent) return
        const m = subMenu.createObject(pop.parent, { cmd: cmd, level: level, byKeys: !!byKeys })
        const p = item.mapToItem(pop.parent, 0, 0)
        m.x = below ? p.x : p.x + item.width + 12
        m.y = below ? p.y + item.height + 4 : p.y - 8
        subs = subs.concat([m])
        m.open()
        if (byKeys) m.contentItem.forceActiveFocus()
    }
    Component {
        id: subMenu
        Popup {
            id: sm
            property var cmd: null
            property int level: 0
            property bool byKeys: false
            property int cur: 0
            padding: 8
            margins: 4
            closePolicy: Popup.NoAutoClose
            focus: byKeys
            width: Math.min(320, Math.max(200, implicitContentWidth + leftPadding + rightPadding))
            background: FluentSurface { depth: 8; radius: 16; color: theme.menu }
            readonly property var focusable: smRows.rows.map((r, i) => r.kind === "item" ? i : -1).filter(i => i >= 0)
            contentItem: Rows {
                id: smRows
                rows: pop.menuRows(sm.cmd ? sm.cmd.sub : [])
                checks: pop.anyOf(sm.cmd ? sm.cmd.sub : [], c => c.toggle)
                iconsShown: pop.anyOf(sm.cmd ? sm.cmd.sub : [], c => !!c.icon)
                current: sm.byKeys ? sm.focusable[sm.cur] : -1
                level: sm.level + 1
                Keys.onPressed: e => {
                    const f = sm.focusable
                    if (e.key === Qt.Key_Down) sm.cur = (sm.cur + 1) % f.length
                    else if (e.key === Qt.Key_Up) sm.cur = (sm.cur + f.length - 1) % f.length
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Escape) {
                        const back = sm.level > 0 ? pop.subs[sm.level - 1].contentItem : bodyItem
                        pop.closeSubs(sm.level)
                        back.forceActiveFocus()
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || e.key === Qt.Key_Right) smRows.activateRow(f[sm.cur], e.key === Qt.Key_Right)
                    else return
                    e.accepted = true
                }
            }
        }
    }

    // ---- what is drawn -------------------------------------------------
    // A glyph: Teams' icon by name (16 px in the top bar, 20 in menus), an
    // emoji as text, with the command's colour and background if it has
    // them (font and highlight colours).
    component Glyph: Item {
        id: glyph
        property string name
        property string tint: ""
        property string fill: ""
        property color color
        property int size: 16
        width: size; height: size
        Rectangle { anchors.fill: parent; radius: 4; color: glyph.fill || "transparent"; visible: !!glyph.fill }
        Image {
            visible: !pop.isEmoji(glyph.name)
            anchors.fill: parent
            sourceSize: Qt.size(glyph.size * 2, glyph.size * 2)
            source: visible && glyph.name ? pop.iconSource(glyph.name, glyph.tint || glyph.color) : ""
        }
        Text {
            visible: pop.isEmoji(glyph.name)
            anchors.centerIn: parent
            text: glyph.name
            font.pixelSize: 18
        }
    }

    // The rest of the surface, a submenu: Fluent menu rows.
    component Rows: Item {
        id: rowsCol
        property var rows: []
        property bool checks: false
        property bool iconsShown: false
        property int current: -1
        property int level: 0
        // The widest row's natural width (the surface is sized to it).
        property real naturalWidth: 0
        onRowsChanged: naturalWidth = 0
        implicitWidth: naturalWidth
        implicitHeight: rowsColumn.implicitHeight
        function activateRow(i, openOnly) {
            const r = rows[i]
            if (!r || r.kind !== "item" || r.cmd.disabled) return
            const it = rep.itemAt(i)
            if (r.cmd.sub) { if (it) pop.openSub(r.cmd, it, level, false, true) }
            else if (!openOnly) pop.pick(r.cmd)
        }
        Column {
            id: rowsColumn
            width: parent.width
            Repeater {
                id: rep
                model: rowsCol.rows
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var cmd: modelData.cmd || null
                    readonly property bool hot: rowHover.hovered || rowsCol.current === index
                    readonly property bool off: !!cmd && cmd.disabled
                    width: rowsCol.width
                    implicitWidth: modelData.kind === "item" ? 6 + (rowsCol.checks ? 20 : 0) + (rowsCol.iconsShown ? 24 : 0) + label.implicitWidth
                                                               + (keysText.text ? 8 + keysText.implicitWidth : 0) + (cmd && cmd.sub ? 24 : 0) + 6
                                 : modelData.kind === "header" ? head.implicitWidth + 16 : 0
                    onImplicitWidthChanged: rowsCol.naturalWidth = Math.max(rowsCol.naturalWidth, implicitWidth)
                    Component.onCompleted: rowsCol.naturalWidth = Math.max(rowsCol.naturalWidth, implicitWidth)
                    height: modelData.kind === "divider" ? 9 : 32
                    // Divider: 1 px, 4 above and below, out to 3 px from the edges.
                    Rectangle {
                        visible: row.modelData.kind === "divider"
                        x: -5; width: parent.width + 10; y: 4; height: 1
                        color: theme.divider
                    }
                    Text {
                        id: head
                        visible: row.modelData.kind === "header"
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text || ""
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: theme.textSecondary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                    Rectangle {
                        id: rowFace
                        visible: row.modelData.kind === "item"
                        anchors.fill: parent
                        radius: 4
                        color: theme.highContrast && row.hot && !row.off ? theme.hcHighlight : "transparent"
                        border.width: rowsCol.current === row.index && pop.keyboard ? 2 : 0
                        border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
                        readonly property color fg: row.off ? theme.disabled : theme.highContrast && row.hot ? "#000000" : row.hot ? theme.text : theme.textStrong
                        FluentIcon {
                            visible: rowsCol.checks && !!row.cmd && row.cmd.toggle && row.cmd.checked
                            x: 6; anchors.verticalCenter: parent.verticalCenter
                            size: 16; name: "checkmark-16"; color: rowFace.fg
                        }
                        Glyph {
                            visible: rowsCol.iconsShown && !!row.cmd && !!row.cmd.icon
                            x: 6 + (rowsCol.checks ? 20 : 0); anchors.verticalCenter: parent.verticalCenter
                            size: 20
                            name: row.cmd ? row.cmd.icon : ""
                            tint: row.cmd ? row.cmd.iconColor : ""
                            fill: row.cmd ? row.cmd.iconBackground : ""
                            color: row.off ? theme.disabled : theme.highContrast && row.hot ? "#000000" : row.hot ? theme.brand : theme.icon
                        }
                        Text {
                            id: label
                            x: 6 + (rowsCol.checks ? 20 : 0) + (rowsCol.iconsShown ? 24 : 0); anchors.verticalCenter: parent.verticalCenter
                            text: row.cmd ? row.cmd.name : ""
                            font.family: theme.font; font.pixelSize: 14
                            color: rowFace.fg
                        }
                        Text {
                            id: keysText
                            anchors.right: parent.right; anchors.rightMargin: 6 + (row.cmd && row.cmd.sub ? 24 : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.cmd ? (row.cmd.shortcut || row.cmd.secondary) : ""
                            font.family: theme.font; font.pixelSize: 12
                            color: row.off ? theme.disabled : theme.highContrast && row.hot ? "#000000" : row.hot ? theme.textStrong : theme.textSecondary
                        }
                        FluentIcon {
                            visible: !!row.cmd && !!row.cmd.sub
                            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            size: 20; name: "chevron-right-20"; color: rowFace.fg
                        }
                    }
                    // Hovering a row opens its submenu, or closes another's.
                    HoverHandler {
                        id: rowHover
                        enabled: row.modelData.kind === "item"
                        onHoveredChanged: {
                            if (!hovered) return
                            const open = pop.subs[rowsCol.level]
                            if (row.cmd && row.cmd.sub && !row.off) { if (!open || open.cmd !== row.cmd) pop.openSub(row.cmd, row, rowsCol.level, false, false) }
                            else pop.closeSubs(rowsCol.level)
                        }
                    }
                    TapHandler {
                        enabled: row.modelData.kind === "item" && !row.off
                        onTapped: rowsCol.activateRow(row.index, false)
                    }
                    Accessible.role: row.modelData.kind === "item" ? (row.cmd && row.cmd.toggle ? Accessible.CheckBox : Accessible.MenuItem) : Accessible.NoRole
                    Accessible.name: row.cmd ? (row.cmd.aria || row.cmd.name) : ""
                    Accessible.checkable: !!row.cmd && row.cmd.toggle
                    Accessible.checked: !!row.cmd && row.cmd.checked
                    Accessible.onPressAction: rowsCol.activateRow(row.index, false)
                }
            }
        }
    }

    contentItem: Item {
        id: bodyItem
        implicitWidth: Math.max(pop.top.length ? topRow.naturalWidth + 8 : 0, pop.rows.length ? menuRowsItem.naturalWidth : 0)
        implicitHeight: body.implicitHeight
        Accessible.role: Accessible.Dialog
        Column {
            id: body
            width: parent.width
            // The top bar.
            Item {
                id: topBar
                visible: pop.top.length > 0
                width: body.width
                height: 32
                Row {
                    id: topRow
                    x: 4
                    readonly property real naturalWidth: pop.top.reduce((a, t) => a + (t.kind === "divider" ? 9 : 32), 0)
                    readonly property int gaps: Math.max(0, pop.top.length - 1)
                    // Spread out (space-between) across the bar.
                    spacing: gaps > 0 ? Math.max(0, (topBar.width - 8 - naturalWidth) / gaps) : 0
                    Accessible.role: Accessible.MenuBar
                    Repeater {
                        id: topRep
                        model: pop.top
                        delegate: Item {
                            id: tb
                            required property var modelData
                            required property int index
                            readonly property var cmd: modelData.cmd || null
                            readonly property bool isMore: modelData.kind === "more"
                            readonly property bool checked: isMore ? !pop.mini : !!cmd && cmd.toggle && cmd.checked
                            readonly property bool off: !!cmd && cmd.disabled
                            readonly property bool focused: pop.keyboard && pop.area === "top" && pop.cur === index
                            width: modelData.kind === "divider" ? 9 : 32; height: 32
                            Rectangle {
                                visible: tb.modelData.kind === "divider"
                                x: 4; y: 6; width: 1; height: 20
                                color: theme.divider
                            }
                            Rectangle {
                                visible: tb.modelData.kind !== "divider"
                                anchors.fill: parent
                                radius: 4
                                color: tb.off ? "transparent"
                                    : press.pressed ? theme.pick("#E0E0E0", "#2E2E2E", "#1AEBFF")
                                    : tbHover.hovered ? theme.pick("#F5F5F5", "#383838", "#1AEBFF")
                                    : tb.checked ? theme.pick("#EBEBEB", "#333333", "#1AEBFF") : "transparent"
                                border.width: tb.focused ? 2 : 0
                                border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
                                Glyph {
                                    anchors.centerIn: parent
                                    size: 16
                                    name: tb.isMore ? "FFXCMore" : tb.cmd ? tb.cmd.icon : ""
                                    tint: tb.cmd ? tb.cmd.iconColor : ""
                                    fill: tb.cmd ? tb.cmd.iconBackground : ""
                                    color: tb.off ? theme.disabled
                                        : theme.highContrast && (tbHover.hovered || tb.checked) ? "#000000"
                                        : press.pressed ? theme.pick("#4F52B2", "#7579EB", "#000000")
                                        : tbHover.hovered || tb.checked ? theme.brand : theme.icon
                                }
                            }
                            HoverHandler { id: tbHover; enabled: tb.modelData.kind !== "divider" }
                            TapHandler {
                                id: press
                                enabled: tb.modelData.kind !== "divider" && !tb.off
                                onTapped: pop.activateTop(tb.index, false)
                            }
                            // Fluent's tooltip: above, 12/16, padding 4 11 6.
                            ToolTip {
                                visible: tbHover.hovered && !tb.off && tb.modelData.kind !== "divider" && !pop.subs.length
                                delay: 300
                                y: -height - 4
                                x: (tb.width - width) / 2
                                topPadding: 4; bottomPadding: 6; leftPadding: 11; rightPadding: 11
                                background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
                                contentItem: Text {
                                    text: tb.isMore ? qsTr("More") : tb.cmd ? tb.cmd.name : ""
                                    font.family: theme.font; font.pixelSize: 12; color: theme.text
                                }
                            }
                            Accessible.role: tb.isMore || (tb.cmd && tb.cmd.toggle) ? Accessible.CheckBox : tb.cmd && tb.cmd.sub ? Accessible.ButtonMenu : Accessible.MenuItem
                            Accessible.name: tb.isMore ? qsTr("More") : tb.cmd ? (tb.cmd.aria || tb.cmd.name) : ""
                            Accessible.checkable: tb.isMore || (!!tb.cmd && tb.cmd.toggle)
                            Accessible.checked: tb.checked
                            Accessible.onPressAction: pop.activateTop(tb.index, false)
                        }
                    }
                }
            }
            // A menu divider under the top bar, then Loop's groups.
            Item {
                visible: pop.top.length > 0 && pop.rows.length > 0
                width: body.width; height: 9
                Rectangle { x: -5; width: parent.width + 10; y: 4; height: 1; color: theme.divider }
            }
            Flickable {
                id: menuFlick
                visible: pop.rows.length > 0
                width: body.width
                // As tall as fits in the window (Fluent's autoSize).
                height: Math.min(menuRowsItem.implicitHeight, Math.max(64, (pop.parent && pop.parent.Window.window ? pop.parent.Window.window.height : 800) - 32 - 9 - 40))
                contentHeight: menuRowsItem.implicitHeight
                clip: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                Rows {
                    id: menuRowsItem
                    width: menuFlick.width
                    rows: pop.rows
                    checks: pop.rowChecks
                    iconsShown: pop.rowIcons
                    current: pop.keyboard && pop.area === "main" ? pop.cur : -1
                    level: 0
                }
            }
        }
        Keys.onPressed: e => {
            pop.keyboard = true
            const tf = pop.topFocusable, rf = pop.rowFocusable
            if (e.key === Qt.Key_Escape || e.key === Qt.Key_Backtab || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier))) pop.dismiss()
            else if (e.key === Qt.Key_Tab) {}
            else if (pop.area === "top" && (e.key === Qt.Key_Right || e.key === Qt.Key_Left) && tf.length) {
                const k = tf.indexOf(pop.cur), n = tf.length
                pop.cur = tf[(k + (e.key === Qt.Key_Right ? 1 : n - 1)) % n]
            } else if (e.key === Qt.Key_Down) {
                if (pop.area === "top") { if (rf.length) { pop.area = "main"; pop.cur = rf[0] } }
                else if (rf.length) { const k = rf.indexOf(pop.cur); pop.cur = rf[(k + 1) % rf.length] }
            } else if (e.key === Qt.Key_Up) {
                if (pop.area === "main" && rf.length) {
                    const k = rf.indexOf(pop.cur)
                    if (k <= 0 && tf.length) { pop.area = "top"; pop.cur = tf[0] }
                    else pop.cur = rf[(k + rf.length - 1) % rf.length]
                }
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || (pop.area === "main" && e.key === Qt.Key_Right)) {
                if (pop.area === "top") pop.activateTop(pop.cur, true)
                else menuRowsItem.activateRow(pop.cur, e.key === Qt.Key_Right)
            } else return
            e.accepted = true
        }
    }
    function activateTop(i, byKeys) {
        const t = top[i]
        if (!t) return
        if (t.kind === "more") toggleMore()
        else if (t.kind === "menu") { if (!(t.cmd && t.cmd.disabled)) openSub(t.cmd, topRep.itemAt(i), 0, true, byKeys) }
        else if (t.kind === "button") pick(t.cmd)
    }
    onClosed: closeSubs()

    // The harness (--loop-test --loop-format): what is shown, and a
    // command picked by Loop's id as a click would.
    function stateForTest() {
        const names = l => (l || []).map(c => c.sub ? { id: c.id, name: c.name, inline: c.inline, sub: names(c.sub) } : { id: c.id, name: c.name, icon: c.icon, checked: c.checked })
        return { open: opened, mini: mini, x: x, y: y, width: width, height: height, top: surface ? names(surface.top) : [], main: surface && !mini ? names(surface.main) : [],
                 iconsMissing: top.concat(rows).filter(t => t.cmd && t.cmd.icon && !isEmoji(t.cmd.icon) && !icons[t.cmd.icon]).map(t => t.cmd.icon) }
    }
    // (`id` may also be "icon:<Loop icon name>", e.g. Create Loop
    // component's FFXCCreateLoopComponent.)
    function pickForTest(id) {
        const hit = c => id.indexOf("icon:") === 0 ? c.icon === id.slice(5) : c.id === id
        const find = l => { for (const c of l || []) { if (hit(c) && !c.sub) return c; const f = c.sub ? find(c.sub) : null; if (f) return f } return null }
        const c = surface ? find(surface.top) || find(surface.main) : null
        if (c) pick(c)
        return !!c
    }
}
