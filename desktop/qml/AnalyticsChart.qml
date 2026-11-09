import QtQuick

// One of Teams' analytics charts (Highcharts in Teams; measured on winpc,
// 2026-11-09, and read from its chart options):
// - The plot 10 from the top and right, its left after the y labels (11 px,
//   right-aligned 15 before it); 37 under it for the dates (11 px, centred
//   on their day, every floor(n/10)th past ten days), 75 with a legend.
// - y from 0 to at least 10, whole numbers, a line every ~72 px (2s at 225,
//   5s at 187), in the theme's lighter brand (#E8EBFA); the x axis line
//   #CCD6EB.
// - "spline": Highcharts' smoothed line (2 px) with 4 px dots; "column" and
//   "stacked": columns 0.6 x 0.8 of a day, a 1 px white edge; Teams' series
//   colours (brand, lighter brand, secondary, black, tertiary).
// - A legend (stacked only) at the bottom left: 10 x 25 swatches, bold 12 px
//   names 5 after them, 20 between; a name toggles its series.
// - Hover: Teams' shared tooltip (dark, white text) with the day and each
//   series' number.
// series: [{ name, points: [{ name, y }] }]
Item {
    id: chart
    property string kind: "spline"
    property var series: []
    property bool legend: kind === "stacked"
    property string description: ""
    property var hidden: ({})
    property int hover: -1

    readonly property var colors: theme.dark
        ? ["#9399F5", "#2F2F4A", "#7A80EB", "#FFFFFF", "#5B5FC7", "#242424"]
        : ["#5B5FC7", "#E8EBFA", "#9092C1", "#242424", "#A5A7CF", "#FAFAFA"]
    readonly property color ink: theme.dark ? "#FFFFFF" : "#242424"
    readonly property color grid: theme.dark ? "#2F2F4A" : "#E8EBFA"
    readonly property string fontFamily: "Arial"

    readonly property int count: series.reduce((n, s) => Math.max(n, (s.points || []).length), 0)
    readonly property var categories: { const s = series.find(s => (s.points || []).length === count); return s ? s.points.map(p => p.name) : [] }
    // Highcharts' y axis: 0 to the data's top (at least the soft max 10),
    // whole-number ticks about 72 px apart.
    readonly property real dataMax: {
        let m = 0
        for (let i = 0; i < count; i++) {
            let sum = 0
            for (let k = 0; k < series.length; k++) {
                if (hidden[k]) continue
                const p = (series[k].points || [])[i]
                const y = p ? (p.y || 0) : 0
                if (kind === "stacked") sum += y; else m = Math.max(m, y)
            }
            if (kind === "stacked") m = Math.max(m, sum)
        }
        return m
    }
    readonly property real plotTop: 10
    readonly property real plotBottom: height - (legend ? 75 : 37)
    readonly property real plotH: Math.max(1, plotBottom - plotTop)
    readonly property real tickStep: {
        const top = Math.max(10, dataMax)
        const raw = top * 72 / plotH
        const mag = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
        if (mag < 1) return 1
        const norm = raw / mag
        const mult = mag === 1 ? [1, 2, 5, 10] : [1, 2, 2.5, 5, 10]
        for (let i = 0; i < mult.length - 1; i++)
            if (norm <= (mult[i] + mult[i + 1]) / 2) return mult[i] * mag
        return 10 * mag
    }
    readonly property real yMax: Math.ceil(Math.max(10, dataMax) / tickStep) * tickStep
    readonly property var ticks: { const t = []; for (let v = 0; v <= yMax + 1e-9; v += tickStep) t.push(v); return t }
    property real labelWidth: 14
    readonly property real plotLeft: 10 + labelWidth + 15.1
    readonly property real plotRight: width - 10
    readonly property real plotW: Math.max(1, plotRight - plotLeft)
    readonly property real catW: count ? plotW / count : plotW
    readonly property int labelEvery: count > 10 ? Math.floor(count / 10) : 1

    function yOf(v) { return plotBottom - (v / yMax) * plotH }
    function xOf(i) { return plotLeft + catW * (i + 0.5) }

    onSeriesChanged: { hidden = ({}); canvas.requestPaint() }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onHiddenChanged: canvas.requestPaint()
    onHoverChanged: canvas.requestPaint()
    onPlotLeftChanged: canvas.requestPaint()
    Connections { target: theme; function onDarkChanged() { canvas.requestPaint() } }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.font = "11px " + chart.fontFamily
            // y labels decide where the plot starts.
            let lw = 0
            for (const t of chart.ticks) lw = Math.max(lw, ctx.measureText(String(t)).width)
            if (Math.abs(lw - chart.labelWidth) > 0.5) { chart.labelWidth = lw; return }
            // Grid and y labels.
            ctx.lineWidth = 1
            ctx.fillStyle = chart.ink
            ctx.textBaseline = "middle"
            ctx.textAlign = "right"
            for (const t of chart.ticks) {
                const y = Math.round(chart.yOf(t)) + 0.5
                ctx.strokeStyle = chart.grid
                ctx.beginPath(); ctx.moveTo(chart.plotLeft, y); ctx.lineTo(chart.plotRight, y); ctx.stroke()
                ctx.fillText(String(t), chart.plotLeft - 15.1, y)
            }
            // The x axis line.
            ctx.strokeStyle = "#CCD6EB"
            const by = Math.round(chart.plotBottom) + 0.5
            ctx.beginPath(); ctx.moveTo(chart.plotLeft, by); ctx.lineTo(chart.plotRight, by); ctx.stroke()
            // Dates.
            ctx.textAlign = "center"; ctx.textBaseline = "top"
            for (let i = 0; i < chart.count; i += chart.labelEvery)
                ctx.fillText(chart.categories[i] || "", chart.xOf(i), chart.plotBottom + 9)
            // The series.
            if (chart.kind === "spline") {
                for (let k = 0; k < chart.series.length; k++) {
                    if (chart.hidden[k]) continue
                    const pts = (chart.series[k].points || []).map((p, i) => ({ x: chart.xOf(i), y: chart.yOf(p.y || 0) }))
                    const c = chart.colors[k % chart.colors.length]
                    ctx.strokeStyle = c; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"
                    ctx.beginPath()
                    for (let i = 0; i < pts.length; i++) {
                        if (i === 0) { ctx.moveTo(pts[0].x, pts[0].y); continue }
                        const a = chart.control(pts, i - 1), b = chart.control(pts, i)
                        ctx.bezierCurveTo(a.rx, a.ry, b.lx, b.ly, pts[i].x, pts[i].y)
                    }
                    ctx.stroke()
                    ctx.fillStyle = c
                    for (let i = 0; i < pts.length; i++) {
                        const r = i === chart.hover ? 5 : 4
                        ctx.beginPath(); ctx.arc(pts[i].x, pts[i].y, r, 0, 2 * Math.PI); ctx.fill()
                    }
                }
            } else {
                const groupW = chart.catW * (1 - 2 * 0.2)
                const barW = Math.round(groupW * (1 - 2 * 0.1))
                const bases = []
                for (let k = 0; k < chart.series.length; k++) {
                    if (chart.hidden[k]) continue
                    const c = chart.colors[k % chart.colors.length]
                    const pts = chart.series[k].points || []
                    for (let i = 0; i < pts.length; i++) {
                        const v = pts[i].y || 0
                        if (v <= 0) continue
                        const base = chart.kind === "stacked" ? (bases[i] || 0) : 0
                        const y0 = Math.round(chart.yOf(base)), y1 = Math.round(chart.yOf(base + v))
                        const x = Math.round(chart.xOf(i) - barW / 2)
                        ctx.fillStyle = i === chart.hover ? Qt.lighter(c, 1.1) : c
                        ctx.fillRect(x, y1, barW, y0 - y1)
                        ctx.strokeStyle = "#FFFFFF"; ctx.lineWidth = 1
                        ctx.strokeRect(x + 0.5, y1 + 0.5, barW - 1, y0 - y1 - 1)
                        if (chart.kind === "stacked") bases[i] = base + v
                    }
                }
            }
        }
    }
    // Highcharts' spline control points (smoothing 1.5) for point i.
    function control(pts, i) {
        const p = pts[i], prev = pts[i - 1], next = pts[i + 1]
        if (!prev || !next) return { lx: p.x, ly: p.y, rx: p.x, ry: p.y }
        const s = 1.5, d = s + 1
        const lx = (s * p.x + prev.x) / d, rx = (s * p.x + next.x) / d
        let ly = (s * p.y + prev.y) / d, ry = (s * p.y + next.y) / d
        if (rx !== lx) {
            const corr = ((ry - ly) * (rx - p.x)) / (rx - lx) + p.y - ry
            ly += corr; ry += corr
        }
        // No overshoot past the neighbours.
        if (ly > prev.y && ly > p.y) { ly = Math.max(prev.y, p.y); ry = 2 * p.y - ly }
        else if (ly < prev.y && ly < p.y) { ly = Math.min(prev.y, p.y); ry = 2 * p.y - ly }
        if (ry > next.y && ry > p.y) { ry = Math.max(next.y, p.y); ly = 2 * p.y - ry }
        else if (ry < next.y && ry < p.y) { ry = Math.min(next.y, p.y); ly = 2 * p.y - ry }
        return { lx: lx, ly: ly, rx: rx, ry: ry }
    }

    // The legend.
    Row {
        visible: chart.legend
        x: 18; y: chart.height - 47
        spacing: 20
        Repeater {
            model: chart.series
            Item {
                id: li
                required property var modelData
                required property int index
                readonly property bool off: !!chart.hidden[index]
                width: 15 + liText.implicitWidth; height: 25
                Rectangle { width: 10; height: 25; color: li.off ? "#CCCCCC" : chart.colors[li.index % chart.colors.length] }
                Text {
                    id: liText
                    x: 15; y: 12
                    text: li.modelData.name
                    font.family: chart.fontFamily; font.pixelSize: 12; font.bold: true
                    color: li.off ? (theme.dark ? "#2F2F4A" : "#E8EBFA") : liHover.hovered ? (theme.dark ? "#ACB3FA" : "#383966") : chart.ink
                }
                HoverHandler { id: liHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { const h = Object.assign({}, chart.hidden); h[li.index] = !h[li.index]; chart.hidden = h } }
                Accessible.role: Accessible.CheckBox
                Accessible.checked: !li.off
                Accessible.name: li.modelData.name
            }
        }
    }

    // Hover: the day under the pointer and Teams' shared tooltip.
    HoverHandler {
        id: hoverer
        onPointChanged: {
            const p = point.position
            if (p.x < chart.plotLeft || p.x > chart.plotRight || p.y < chart.plotTop || p.y > chart.plotBottom || !chart.count) { chart.hover = -1; return }
            chart.hover = Math.min(chart.count - 1, Math.floor((p.x - chart.plotLeft) / chart.catW))
        }
        onHoveredChanged: if (!hovered) chart.hover = -1
    }
    Rectangle {
        id: tip
        visible: chart.hover >= 0
        readonly property real anchorX: chart.hover >= 0 ? chart.xOf(chart.hover) : 0
        x: Math.max(0, Math.min(chart.width - width, anchorX + 12 + width > chart.width ? anchorX - width - 12 : anchorX + 12))
        y: Math.max(0, chart.plotTop + 10)
        width: tipCol.implicitWidth + 16; height: tipCol.implicitHeight + 16
        radius: 3
        color: chart.ink
        border.width: 1; border.color: chart.colors[0]
        Column {
            id: tipCol
            x: 8; y: 8
            Text { text: chart.hover >= 0 ? (chart.categories[chart.hover] || "") : ""; font.family: chart.fontFamily; font.pixelSize: 10; color: theme.dark ? "#292929" : "#FFFFFF" }
            Repeater {
                model: chart.series
                Text {
                    required property var modelData
                    required property int index
                    visible: !chart.hidden[index]
                    textFormat: Text.StyledText
                    readonly property var pt: chart.hover >= 0 ? (modelData.points || [])[chart.hover] : null
                    text: "<font color=\"" + chart.colors[index % chart.colors.length] + "\">●</font> " + modelData.name + ": <b>" + (pt ? (pt.y || 0) : 0) + "</b>"
                    font.family: chart.fontFamily; font.pixelSize: 12
                    color: theme.dark ? "#292929" : "#FFFFFF"
                }
            }
        }
    }

    Accessible.role: Accessible.Chart
    Accessible.name: description
}
