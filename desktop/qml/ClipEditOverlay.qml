import QtQuick
import QtQuick.Controls.Basic

// Over the clip recorder's picture, not recorded: what edits the canvas
// items, as Stream's camera shows it (measured on winpc 2026-11-20).
// - The selected item: a 2 px #974CFF frame 4 px out, white round handles
//   at the corners and the sides' middles, and a turn handle above.
//   The handles hide while recording (Stream's showDragHandles(false)).
// - The right-hand dock (33.3 wide, rgba(177,177,177,.48), rounded 12,
//   a #D1D1D1 hairline, 32 px buttons): Delete, Flip, Duplicate, Forward,
//   Backward for drawings, stickers and photos; Font, Color, Stroke (or
//   Shadow) and Background for text.
// - Effects ▸ Text: an input centred on the picture (384 x 66, 57.6 px,
//   "Start typing..."); the first key makes the text item, typed into in
//   place.
// - Draw: strokes are drawn while its drawer is open (crosshair).
Item {
    id: ov
    required property var fx
    required property var canvasItems
    /// Recording (the handles hide).
    property bool recording: false
    property bool textEntry: false
    signal openMenu(string name)

    readonly property var sel: fx.selected >= 0 && fx.selected < fx.items.length ? fx.items[fx.selected] : null
    readonly property var selItem: sel && canvasItems.count > fx.selected ? canvasItems.itemAt(fx.selected) : null

    // ---- Draw ----
    MouseArea {
        anchors.fill: parent
        enabled: ov.fx.drawer === "draw"
        visible: enabled
        cursorShape: Qt.CrossCursor
        property var pts: []
        function path(p) {
            // Fabric's PencilBrush: quadratic curves through the midpoints.
            if (p.length < 2) return p.length ? "M " + p[0].x + " " + p[0].y + " L " + (p[0].x + 0.01) + " " + p[0].y : ""
            let d = "M " + p[0].x + " " + p[0].y
            for (let i = 1; i < p.length - 1; i++) {
                const mx = (p[i].x + p[i + 1].x) / 2, my = (p[i].y + p[i + 1].y) / 2
                d += " Q " + p[i].x + " " + p[i].y + " " + mx + " " + my
            }
            const l = p[p.length - 1]
            return d + " L " + l.x + " " + l.y
        }
        onPressed: m => {
            pts = [Qt.point(m.x, m.y)]
            ov.fx.liveInk = { d: path(pts), color: ov.fx.inkColor(ov.fx.inkValue).toString(), width: ov.fx.inkWidth }
        }
        onPositionChanged: m => {
            if (!pressed) return
            pts = pts.concat([Qt.point(m.x, m.y)])
            ov.fx.liveInk = { d: path(pts), color: ov.fx.liveInk.color, width: ov.fx.liveInk.width }
        }
        onReleased: {
            const live = ov.fx.liveInk
            ov.fx.liveInk = null
            if (!live || !pts.length) return
            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
            for (const p of pts) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y) }
            const pad = live.width * ov.fx.k / 2 + 1
            x0 -= pad; y0 -= pad; x1 += pad; y1 += pad
            const local = pts.map(p => Qt.point(p.x - x0, p.y - y0))
            ov.fx.add({ kind: "ink", d: path(local), color: live.color, width: live.width, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, w: x1 - x0, h: y1 - y0 })
            // A stroke isn't left selected while drawing goes on.
            ov.fx.selected = -1
            pts = []
        }
    }

    // ---- Text ----
    function startText() {
        fx.selected = -1
        fx.editing = -1
        entry.text = ""
        textEntry = true
        entry.forceActiveFocus()
    }
    function endText() {
        if (textEntry) textEntry = false
        if (fx.editing >= 0) {
            const i = fx.editing
            fx.editing = -1
            if (i < fx.items.length && !String(fx.items[i].text).trim().length) {
                // An empty text goes without trace.
                const list = fx.items.filter((_, j) => j !== i)
                fx.items = list
                fx.undoStack = fx.undoStack.slice(0, -1)
                fx.selected = -1
            }
        }
        editor.focus = false
    }
    Rectangle {
        id: entryBox
        visible: ov.textEntry
        width: 384; height: 66
        anchors.centerIn: parent
        color: "transparent"
        border.color: "#000000"; border.width: 2; radius: 2
        Rectangle { anchors.fill: parent; anchors.margins: 2; color: "transparent"; border.color: "#FFFFFF"; border.width: 1 }
        TextInput {
            id: entry
            anchors.fill: parent; anchors.margins: 3
            clip: true
            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
            font.family: "Arial"; font.pixelSize: 57.6
            color: "#FFFFFF"
            Text {
                anchors.fill: parent
                visible: !entry.text.length
                text: qsTr("Start typing...")
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font: entry.font; color: "#242424"; elide: Text.ElideNone
            }
            onTextChanged: if (text.length && ov.textEntry) {
                // The first key: Stream's text item, typed into from here.
                ov.textEntry = false
                ov.fx.add(ov.fx.newText(text))
                ov.fx.editing = ov.fx.selected
                editor.text = text
                editor.cursorPosition = text.length
                editor.forceActiveFocus()
            }
            Keys.onEscapePressed: ov.endText()
        }
    }
    // The text being typed into (keys only: the canvas shows the text).
    TextEdit {
        id: editor
        width: 1; height: 1; opacity: 0
        enabled: ov.fx.editing >= 0
        onTextChanged: if (ov.fx.editing >= 0 && ov.fx.editing < ov.fx.items.length && ov.fx.items[ov.fx.editing].text !== text) {
            const list = ov.fx.items.slice()
            list[ov.fx.editing] = Object.assign({}, list[ov.fx.editing], { text: text })
            ov.fx.items = list
        }
        Keys.onEscapePressed: ov.endText()
    }
    /// Test hook: Effects ▸ Text, then typing `t` (a first key, then the rest).
    function typeForTest(t) {
        if (fx.editing < 0) { startText(); entry.text = t.slice(0, 1); t = t.slice(1) }
        editor.text = editor.text + t
        editor.cursorPosition = editor.text.length
    }
    function editText(i) {
        if (i < 0 || fx.items[i].kind !== "text") return
        fx.selected = i
        fx.editing = i
        editor.text = fx.items[i].text
        editor.cursorPosition = editor.text.length
        editor.forceActiveFocus()
    }
    // The caret, at the end of the text.
    Rectangle {
        visible: ov.fx.editing >= 0 && !!ov.selItem && caretBlink.on
        width: 1.5; height: 68 * ov.fx.k
        color: ov.sel && ov.sel.fill ? ov.sel.fill : "white"
        x: ov.sel && ov.selItem ? ov.sel.cx + ov.selItem.boxW * ov.sel.s / 2 + 1 : 0
        y: ov.sel && ov.selItem ? ov.sel.cy + ov.selItem.boxH * ov.sel.s / 2 - height - 3 : 0
        Timer { id: caretBlink; property bool on: true; interval: 530; repeat: true; running: ov.fx.editing >= 0; onTriggered: on = !on }
    }

    // ---- The selection ----
    component Handle: Rectangle {
        id: hd
        property string kind
        signal dragged(point p, point start)
        signal began()
        width: 12; height: 12; radius: 6
        color: "#FFFFFF"; border.color: "#DDDDDD"; border.width: 1
        HoverHandler { cursorShape: hd.kind === "turn" ? Qt.CrossCursor : hd.kind === "side" ? Qt.SizeHorCursor : Qt.SizeFDiagCursor }
        DragHandler {
            target: null
            onActiveChanged: if (active) hd.began()
            onCentroidChanged: if (active) {
                const p = ov.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                const s = ov.mapFromItem(null, centroid.scenePressPosition.x, centroid.scenePressPosition.y)
                hd.dragged(p, s)
            }
        }
    }
    Item {
        id: frame
        visible: !!ov.sel && !!ov.selItem && !ov.recording
        readonly property real pad: 4
        readonly property real sw: ov.sel && ov.selItem ? ov.selItem.boxW * ov.sel.s * ov.sel.sx : 0
        readonly property real sh: ov.sel && ov.selItem ? ov.selItem.boxH * ov.sel.s : 0
        x: ov.sel ? ov.sel.cx - sw / 2 - pad : 0
        y: ov.sel ? ov.sel.cy - sh / 2 - pad : 0
        width: sw + 2 * pad; height: sh + 2 * pad
        rotation: ov.sel ? ov.sel.a : 0
        property var start: null
        function begin() { start = Object.assign({}, ov.sel); ov.fx.record() }
        function setSel(p) {
            const list = ov.fx.items.slice()
            list[ov.fx.selected] = Object.assign({}, list[ov.fx.selected], p)
            ov.fx.items = list
        }
        Rectangle { anchors.fill: parent; color: "transparent"; border.color: "#974CFF"; border.width: 2 }
        // The turn handle and its stem.
        Rectangle { x: parent.width / 2 - 0.5; y: -24; width: 1; height: 24; color: "#974CFF" }
        Handle {
            kind: "turn"; x: frame.width / 2 - 6; y: -30
            onBegan: frame.begin()
            onDragged: (p, s) => {
                const a = Math.atan2(p.y - frame.start.cy, p.x - frame.start.cx) * 180 / Math.PI + 90
                frame.setSel({ a: a })
            }
        }
        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1], [0, 0.5], [1, 0.5]]
            delegate: Handle {
                required property var modelData
                kind: modelData[1] === 0.5 ? "side" : "corner"
                x: modelData[0] * frame.width - 6; y: modelData[1] * frame.height - 6
                onBegan: frame.begin()
                onDragged: (p, s) => {
                    const c = Qt.point(frame.start.cx, frame.start.cy)
                    if (kind === "corner") {
                        const d0 = Math.hypot(s.x - c.x, s.y - c.y), d1 = Math.hypot(p.x - c.x, p.y - c.y)
                        if (d0 > 1) frame.setSel({ s: Math.max(0.05, frame.start.s * d1 / d0) })
                    } else {
                        // Along the item's own (turned) across axis.
                        const r = frame.start.a * Math.PI / 180, ux = Math.cos(r), uy = Math.sin(r)
                        const d0 = Math.abs((s.x - c.x) * ux + (s.y - c.y) * uy), d1 = Math.abs((p.x - c.x) * ux + (p.y - c.y) * uy)
                        if (d0 > 1) frame.setSel({ sx: Math.max(0.05, frame.start.sx * d1 / d0) })
                    }
                }
            }
        }
    }

    // ---- The dock ----
    component DockButton: Rectangle {
        id: db
        property string icon
        property string label
        property bool off: false
        property bool first: false
        property bool last: false
        default property alias content: slot.data
        signal clicked()
        width: 32; height: 32
        topLeftRadius: first ? 11 : 4; topRightRadius: first ? 11 : 4
        bottomLeftRadius: last ? 11 : 4; bottomRightRadius: last ? 11 : 4
        color: dbHover.hovered && !off ? Qt.rgba(1, 1, 1, 0.5) : "transparent"
        FluentIcon { visible: !!db.icon; anchors.centerIn: parent; name: db.icon; size: 20; color: "#242424"; opacity: db.off ? 0.4 : 1 }
        Item { id: slot; anchors.fill: parent }
        HoverHandler { id: dbHover; cursorShape: db.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { onTapped: if (!db.off) db.clicked() }
        ToolTip.visible: dbHover.hovered; ToolTip.delay: 500; ToolTip.text: db.label
        Accessible.role: Accessible.Button
        Accessible.name: db.label
    }
    Rectangle {
        id: dock
        visible: !!ov.sel
        readonly property bool isText: !!ov.sel && ov.sel.kind === "text"
        x: 750.7 - 19.6; width: 33.3
        height: col.height + 1.3
        y: ov.height / 2 - height / 2
        radius: 12
        color: Qt.rgba(177 / 255, 177 / 255, 177 / 255, 0.48)
        border.color: "#D1D1D1"; border.width: 0.67
        Column {
            id: col
            x: 0.67; y: 0.67
            // Text: Font, Color, Stroke (Shadow), Background.
            DockButton {
                visible: dock.isText; first: true
                label: qsTr("Font menu.")
                onClicked: ov.openMenu("font")
                Text { anchors.centerIn: parent; text: "Aa"; font.family: ov.sel ? ov.fx.textStyle(ov.sel.style).family : "Arial"; font.pixelSize: 16; color: "#242424"; style: Text.Normal }
            }
            DockButton {
                visible: dock.isText
                label: qsTr("Color menu.")
                onClicked: ov.openMenu("color")
                Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; color: ov.sel && ov.sel.fill ? ov.sel.fill : "white"; border.color: "#D1D1D1"; border.width: 0.67 }
            }
            DockButton {
                visible: dock.isText
                label: ov.sel && ov.fx.textStyle(ov.sel.style).shadow ? qsTr("Shadow menu.") : qsTr("Stroke menu.")
                onClicked: ov.openMenu("stroke")
                Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; color: "transparent"; border.width: 5; border.color: ov.sel && (ov.sel.stroke || ov.sel.shadow) ? (ov.sel.stroke || ov.sel.shadow) : "#BDBDBD" }
            }
            DockButton {
                visible: dock.isText; last: true
                label: qsTr("Background menu.")
                onClicked: ov.openMenu("background")
                Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 4; color: ov.sel && ov.sel.bg ? ov.sel.bg : "transparent"; border.color: "#BDBDBD"; border.width: ov.sel && ov.sel.bg ? 0 : 1.5 }
            }
            // Drawings, stickers, photos.
            DockButton { visible: !dock.isText; first: true; icon: "delete-20"; label: qsTr("Delete menu."); onClicked: ov.fx.remove(ov.fx.selected) }
            DockButton { visible: !dock.isText; icon: "flip-horizontal-20"; label: qsTr("Flip menu."); onClicked: ov.fx.flip(ov.fx.selected) }
            DockButton { visible: !dock.isText; icon: "copy-add-20"; label: qsTr("Duplicate menu."); onClicked: ov.fx.duplicate(ov.fx.selected) }
            DockButton { visible: !dock.isText; icon: "arrow-up-20"; label: qsTr("Forward menu."); off: ov.fx.selected >= ov.fx.items.length - 1; onClicked: ov.fx.forward(ov.fx.selected) }
            DockButton { visible: !dock.isText; last: true; icon: "arrow-down-20"; label: qsTr("Backward menu."); off: ov.fx.selected <= 0; onClicked: ov.fx.backward(ov.fx.selected) }
        }
    }
}
