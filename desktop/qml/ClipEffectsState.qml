import QtQuick

// What the clip recorder's effects are set to, as Microsoft Stream's
// camera (OneCamera, inside Teams' recorder) keeps it: the backdrop, the
// filter, frame and board, the drawer that is open, and the canvas items
// (text, drawings, stickers and photos) with their undo history.
// Canvas items live in picture coordinates (the 760.9 x 428 picture);
// Stream works on a 1280 x 720 canvas, so its sizes are scaled by `k`.
QtObject {
    id: fx
    readonly property real pictureWidth: 760.9
    readonly property real pictureHeight: 428
    readonly property real k: pictureWidth / 1280

    /// The open drawer: "", "backdrop", "stickers", "filter", "frame",
    /// "board", "draw", "photo", or a text menu: "font", "color",
    /// "stroke", "background".
    property string drawer: ""
    function toggle(name) { drawer = drawer === name ? "" : name }

    /// {kind: "none" | "blur" | "image" | "video", url, name, upload}.
    /// Stock pictures are stretched over the picture; uploads are fitted
    /// inside it over a darkened copy that covers it (Stream's backdrop
    /// layout).
    property var backdrop: ({ kind: "none" })
    readonly property bool cutout: backdrop.kind === "image" || backdrop.kind === "video"
    /// Where the cut-out person stands over an image or video backdrop
    /// (Stream's presenter mode): offset in picture px, scale, angle.
    property var pip: ({ x: 0, y: 0, s: 1, a: 0 })

    property int filter: -1
    property int frame: -1
    property int board: -1
    /// The camera's share of the split screen (Stream's default 0.5).
    property real boardRatio: 0.5

    // ---- Draw ----
    /// The colour slider (0–100 as 0–1): black, the hue wheel 360 to 0,
    /// white. Stream starts at 0.45 (hsl(198, 100 %, 50 %)).
    property real inkValue: 0.45
    property int inkWidth: 4
    function inkColor(n) {
        const t = 1 - n
        return Qt.hsla((360 * t % 360) / 360, 1, t > 0.99 ? 0 : t < 0.01 ? 1 : 0.5, 1)
    }
    /// The stroke being drawn ({points, color, width}) or null.
    property var liveInk: null

    // ---- Canvas items ----
    /// [{kind: "text" | "ink" | "image", cx, cy (centre), w, h (unscaled
    /// box), s (scale), sx (stretch across), a (degrees), flip, …}]:
    /// text {text, style, fill, stroke, shadow, bg, align}; ink {d (an
    /// SVG path in the box), color, width}; image {src, sticker}.
    property var items: []
    property int selected: -1
    /// The text being typed into (an index), or -1.
    property int editing: -1
    property var undoStack: []
    property var redoStack: []
    readonly property bool hasHistory: undoStack.length > 0 || redoStack.length > 0 || items.length > 0

    function snapshot() { return JSON.stringify(items) }
    function record() { undoStack = undoStack.concat([snapshot()]); redoStack = [] }
    function commit(list) { record(); items = list }
    function patch(i, p, recordIt) {
        if (i < 0 || i >= items.length) return
        if (recordIt) record()
        const list = items.slice()
        list[i] = Object.assign({}, list[i], p)
        items = list
    }
    function add(item) {
        commit(items.concat([Object.assign({ s: 1, sx: 1, a: 0, flip: false }, item)]))
        selected = items.length - 1
    }
    function remove(i) {
        if (i < 0) return
        commit(items.filter((_, j) => j !== i))
        selected = -1
        if (editing === i) editing = -1
    }
    function duplicate(i) {
        if (i < 0) return
        const c = Object.assign({}, items[i])
        // Stream's copy lands 10 px right and down (on its 1280 canvas).
        c.cx += 10 * k; c.cy += 10 * k
        add(c)
    }
    function flip(i) { if (i >= 0) patch(i, { flip: !items[i].flip }, true) }
    function forward(i) {
        if (i < 0 || i >= items.length - 1) return
        const list = items.slice(); const t = list[i]; list[i] = list[i + 1]; list[i + 1] = t
        commit(list); selected = i + 1
    }
    function backward(i) {
        if (i <= 0) return
        const list = items.slice(); const t = list[i]; list[i] = list[i - 1]; list[i - 1] = t
        commit(list); selected = i - 1
    }
    function undo() {
        if (!undoStack.length) return
        redoStack = redoStack.concat([snapshot()])
        items = JSON.parse(undoStack[undoStack.length - 1])
        undoStack = undoStack.slice(0, -1)
        selected = -1; editing = -1
    }
    function redo() {
        if (!redoStack.length) return
        undoStack = undoStack.concat([snapshot()])
        items = JSON.parse(redoStack[redoStack.length - 1])
        redoStack = redoStack.slice(0, -1)
        selected = -1; editing = -1
    }
    /// Clear video canvas: every item goes (undoable).
    function clearCanvas() {
        if (!items.length) return
        commit([]); selected = -1; editing = -1
    }

    // ---- Text (Stream's text styles; sizes on its 1280 canvas) ----
    readonly property var colors: [
        { name: qsTr("Gray white"), value: "#fcfcfc" },
        { name: qsTr("Black"), value: "#000000" },
        { name: qsTr("Blue"), value: Qt.hsla(214 / 360, 0.65, 0.5, 1).toString() },
        { name: qsTr("Red"), value: Qt.hsla(0, 0.78, 0.46, 1).toString() },
        { name: qsTr("Gold"), value: Qt.hsla(46 / 360, 0.96, 0.59, 1).toString() },
        { name: qsTr("Maroon"), value: Qt.hsla(352 / 360, 0.83, 0.26, 1).toString() }
    ]
    readonly property var textStyles: [
        { id: "classic", name: qsTr("Classic"), family: "Arial", fill: "#fcfcfc", stroke: "", shadow: false, px: 15, py: 6, radius: 4 },
        { id: "compact", name: qsTr("Compact"), family: "Impact", fill: "#ffffff", stroke: "#000000", shadow: false, px: 8, py: 6, radius: 4 },
        { id: "modern", name: qsTr("Modern"), family: "Century Gothic", fill: "#ffffff", stroke: "", shadow: false, px: 20, py: 6, radius: 8 },
        { id: "traditional", name: qsTr("Traditional"), family: "Georgia", fill: "#000000", stroke: "", shadow: false, px: 20, py: 6, radius: 0 },
        { id: "personal", name: qsTr("Personal"), family: "Segoe Print", fill: "#ffffff", stroke: "", shadow: true, shadowColor: Qt.hsla(343 / 360, 0.92, 0.28, 1).toString(), px: 8, py: 6, radius: 4 },
        { id: "typewriter", name: qsTr("Typewriter"), family: "Courier New", fill: "#ffffff", stroke: "", shadow: false, px: 32, py: 6, radius: 100 }
    ]
    function textStyle(id) { return textStyles.find(s => s.id === id) || textStyles[0] }
    /// A new text item, Stream's IText at creation: 68 px, centred, the
    /// Classic style, no background.
    function newText(text) {
        const st = textStyles[0]
        return { kind: "text", text: text, style: st.id, fill: st.fill, stroke: st.stroke, shadow: st.shadow ? st.shadowColor : "", bg: "", align: "center",
                 cx: pictureWidth / 2, cy: pictureHeight / 2, w: 10, h: 68 * k, s: 1, sx: 1, a: 0, flip: false }
    }

    function resetAll() {
        drawer = ""
        backdrop = { kind: "none" }
        pip = { x: 0, y: 0, s: 1, a: 0 }
        filter = -1; frame = -1; board = -1; boardRatio = 0.5
        items = []; selected = -1; editing = -1; undoStack = []; redoStack = []
        liveInk = null
    }
}
