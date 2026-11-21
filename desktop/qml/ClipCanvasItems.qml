import QtQuick
import QtQuick.Shapes

// The clip recorder's canvas items, drawn into its picture (and so into
// the clip) in stacking order: text, drawings, stickers and photos, as
// Stream's Fabric canvas draws them over the filtered picture and under
// the frame. Selecting, moving and the handles are ClipEditOverlay's.
Item {
    id: canvasLayer
    required property var fx
    /// Items take clicks and drags (not while drawing).
    property bool interactive: true
    signal itemPressed(int index)
    signal itemDoubleClicked(int index)

    readonly property int count: rep.count
    function itemAt(i) { return rep.itemAt(i) }
    /// The topmost item at (x, y), or -1.
    function hit(x, y) {
        for (let i = rep.count - 1; i >= 0; i--) {
            const d = rep.itemAt(i)
            if (d && d.contains(d.mapFromItem(canvasLayer, x, y))) return i
        }
        return -1
    }

    component TextBody: Item {
        id: tb
        property var it
        readonly property var st: canvasLayer.fx.textStyle(it.style)
        readonly property real fontPx: 68 * canvasLayer.fx.k
        // Fabric's line height: the font size x 1.13.
        readonly property real lineH: fontPx * 1.13
        readonly property var lines: String(it.text).split("\n")
        property real maxW: 0
        implicitWidth: Math.max(maxW, 2)
        implicitHeight: lines.length * lineH
        function measure() {
            let m = 0
            for (let i = 0; i < lineRep.count; i++) { const r = lineRep.itemAt(i); if (r) m = Math.max(m, r.lineW) }
            maxW = m
        }
        Repeater {
            id: lineRep
            model: tb.lines
            delegate: Item {
                id: lineItem
                required property string modelData
                required property int index
                readonly property real lineW: metrics.advanceWidth
                onLineWChanged: Qt.callLater(tb.measure)
                Component.onCompleted: Qt.callLater(tb.measure)
                y: index * tb.lineH
                width: tb.maxW; height: tb.lineH
                readonly property real lx: tb.it.align === "left" ? 0 : tb.it.align === "right" ? tb.maxW - lineW : (tb.maxW - lineW) / 2
                TextMetrics { id: metrics; font: label.font; text: lineItem.modelData }
                // The background: a rounded box per line, padded by the style.
                Rectangle {
                    visible: !!tb.it.bg && lineItem.modelData.length > 0
                    x: lineItem.lx - tb.st.px * canvasLayer.fx.k; y: -tb.st.py * canvasLayer.fx.k
                    width: lineItem.lineW + 2 * tb.st.px * canvasLayer.fx.k; height: tb.lineH + 2 * tb.st.py * canvasLayer.fx.k
                    radius: Math.min(tb.st.radius * canvasLayer.fx.k, height / 2)
                    color: tb.it.bg || "transparent"
                }
                // Personal's shadow: 2 px to the right.
                Text {
                    visible: !!tb.it.shadow
                    x: lineItem.lx + 2 * canvasLayer.fx.k; height: tb.lineH; verticalAlignment: Text.AlignVCenter
                    text: lineItem.modelData; font: label.font; color: tb.it.shadow || "transparent"
                }
                Text {
                    id: label
                    x: lineItem.lx; height: tb.lineH; verticalAlignment: Text.AlignVCenter
                    text: lineItem.modelData
                    font.family: tb.st.family; font.pixelSize: tb.fontPx
                    color: tb.it.fill
                    visible: !tb.it.stroke
                }
                // With a stroke: the glyphs filled, then outlined over (Fabric
                // paints the fill first), 3 px on Stream's canvas.
                Shape {
                    visible: !!tb.it.stroke
                    x: lineItem.lx; width: lineItem.lineW; height: tb.lineH
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: tb.it.fill
                        strokeColor: tb.it.stroke || "transparent"
                        strokeWidth: 3 * canvasLayer.fx.k
                        joinStyle: ShapePath.RoundJoin
                        PathText {
                            text: lineItem.modelData
                            font: label.font
                            y: (tb.lineH - metrics.height) / 2
                        }
                    }
                }
            }
        }
    }

    Repeater {
        id: rep
        // By count: an item changed in place keeps its delegate (a sticker
        // isn't reloaded while it is dragged).
        model: canvasLayer.fx.items.length
        delegate: Item {
            id: obj
            required property int index
            readonly property var it: canvasLayer.fx.items[index] || ({ kind: "", cx: 0, cy: 0, w: 0, h: 0, s: 1, sx: 1, a: 0 })
            readonly property real boxW: it.kind === "text" ? textBody.item ? textBody.item.implicitWidth : 2 : it.w
            readonly property real boxH: it.kind === "text" ? textBody.item ? textBody.item.implicitHeight : 2 : it.h
            x: it.cx - boxW / 2; y: it.cy - boxH / 2
            width: boxW; height: boxH
            transform: [
                Scale { origin.x: obj.width / 2; origin.y: obj.height / 2; xScale: obj.it.s * obj.it.sx * (obj.it.flip ? -1 : 1); yScale: obj.it.s },
                Rotation { origin.x: obj.width / 2; origin.y: obj.height / 2; angle: obj.it.a }
            ]
            Loader {
                id: textBody
                active: obj.it.kind === "text"
                sourceComponent: TextBody { it: obj.it }
            }
            Shape {
                visible: obj.it.kind === "ink"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: obj.it.color || "transparent"
                    strokeWidth: (obj.it.width || 4) * canvasLayer.fx.k
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: obj.it.kind === "ink" ? obj.it.d : "" }
                }
            }
            Image {
                visible: obj.it.kind === "image"
                anchors.fill: parent
                source: obj.it.kind === "image" ? obj.it.src : ""
                // Sharp in the 1280 x 720 recording.
                sourceSize: Qt.size(Math.max(64, obj.it.w * 2), Math.max(64, obj.it.h * 2))
                fillMode: Image.Stretch
                smooth: true; mipmap: true
                asynchronous: true
                onStatusChanged: if (status === Image.Ready && obj.it.fit) canvasLayer.fitImage(obj.index, implicitWidth, implicitHeight)
            }
            TapHandler {
                enabled: canvasLayer.interactive
                gesturePolicy: TapHandler.WithinBounds
                onPressedChanged: if (pressed) canvasLayer.itemPressed(obj.index)
                onDoubleTapped: canvasLayer.itemDoubleClicked(obj.index)
            }
            DragHandler {
                id: drag
                enabled: canvasLayer.interactive
                target: null
                property point start
                onActiveChanged: {
                    if (active) { canvasLayer.itemPressed(obj.index); start = Qt.point(obj.it.cx, obj.it.cy); canvasLayer.fx.record() }
                }
                onTranslationChanged: if (active) {
                    // (Translation is in the item's own, scaled and turned
                    // coordinates: take the scene's.)
                    const d = drag.centroid.scenePosition, p = drag.centroid.scenePressPosition
                    const k = canvasLayer.mapFromItem(null, d.x, d.y), k0 = canvasLayer.mapFromItem(null, p.x, p.y)
                    const list = canvasLayer.fx.items.slice()
                    list[obj.index] = Object.assign({}, list[obj.index], { cx: drag.start.x + k.x - k0.x, cy: drag.start.y + k.y - k0.y })
                    canvasLayer.fx.items = list
                }
            }
        }
    }
    /// A sticker or photo's box once its picture's size is known: Stream
    /// scales it to its width (and taller pictures to their height).
    function fitImage(i, nw, nh) {
        const it = fx.items[i]
        if (!it || !it.fit || nw <= 0 || nh <= 0) return
        let w = it.fit, h = w * nh / nw
        if (nh > 720) { h = it.fitTall; w = h * nw / nh }
        const list = fx.items.slice()
        list[i] = Object.assign({}, it, { w: w, h: h, fit: 0 })
        fx.items = list
    }

    // The stroke being drawn (the recording shows it as it is drawn).
    Shape {
        visible: !!canvasLayer.fx.liveInk
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: canvasLayer.fx.liveInk ? canvasLayer.fx.liveInk.color : "transparent"
            strokeWidth: (canvasLayer.fx.liveInk ? canvasLayer.fx.liveInk.width : 4) * canvasLayer.fx.k
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: canvasLayer.fx.liveInk ? canvasLayer.fx.liveInk.d : "" }
        }
    }
}
