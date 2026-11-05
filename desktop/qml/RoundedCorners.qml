import QtQuick

// Rounds the corners of whatever it covers by painting the area outside a
// rounded rectangle in the background colour. Works on every renderer
// (no shaders), so pictures look the same everywhere.
Canvas {
    id: root
    property real radius: 4
    property color background: "white"
    onRadiusChanged: requestPaint()
    onBackgroundChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const r = Math.min(radius, width / 2, height / 2)
        ctx.fillStyle = background
        ctx.beginPath()
        // The whole box, minus the rounded rectangle (even-odd fill).
        ctx.rect(0, 0, width, height)
        ctx.moveTo(r, 0)
        ctx.lineTo(width - r, 0)
        ctx.arcTo(width, 0, width, r, r)
        ctx.lineTo(width, height - r)
        ctx.arcTo(width, height, width - r, height, r)
        ctx.lineTo(r, height)
        ctx.arcTo(0, height, 0, height - r, r)
        ctx.lineTo(0, r)
        ctx.arcTo(0, 0, r, 0, r)
        ctx.closePath()
        ctx.fillRule = Qt.OddEvenFill
        ctx.fill()
    }
}
