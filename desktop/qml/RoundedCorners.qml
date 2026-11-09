import QtQuick

// Rounds the corners of whatever it covers by painting the area outside a
// rounded rectangle in the background colour. Works on every renderer
// (no shaders), so pictures look the same everywhere.
Canvas {
    id: root
    property real radius: 4
    property color background: "white"
    /// A squircle over the whole box instead (CSS corner-shape
    /// superellipse(2) with a 50% radius: |x|^4 + |y|^4 = 1), as Teams
    /// draws app tiles.
    property bool squircle: false
    onSquircleChanged: requestPaint()
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
        if (squircle) {
            const cx = width / 2, cy = height / 2, steps = 96
            for (let i = 0; i <= steps; i++) {
                const t = i / steps * 2 * Math.PI
                const c = Math.cos(t), s = Math.sin(t)
                const x = cx + cx * Math.sign(c) * Math.sqrt(Math.abs(c))
                const y = cy + cy * Math.sign(s) * Math.sqrt(Math.abs(s))
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.closePath()
            ctx.fillRule = Qt.OddEvenFill
            ctx.fill()
            return
        }
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
