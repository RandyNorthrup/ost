import QtQuick
import QtQuick.Window

// A bot's (agent's) picture, as Teams draws it on the call stage
// (`agent-avatar`, read from Teams desktop on winpc in the Echo test call,
// 2026-11-18): a Fluent square avatar — 4 px corners, overflow hidden,
// Fluent's shadow4 (0 0 2px rgba(0,0,0,.12), 0 2px 4px rgba(0,0,0,.14)) —
// holding the picture as a squircle (border-radius 50% with corner-shape
// squircle, i.e. a superellipse of exponent 4) on #FAFAFA with a 1 px
// rgba(0,0,0,.05) outline inside its edge. A bot without its own picture
// (the Echo bot) gets Teams' default bot image.
Item {
    id: root
    property int size: 200
    property url source: "../assets/illustrations/default-bot.png"
    width: size
    height: size

    // The superellipse |x|^4 + |y|^4 = 1 over the box, inset by `inset`.
    function squircle(ctx, w, h, inset) {
        const a = w / 2 - inset, b = h / 2 - inset, cx = w / 2, cy = h / 2
        const steps = 96
        for (let i = 0; i <= steps; i++) {
            const t = 2 * Math.PI * i / steps
            const c = Math.cos(t), s = Math.sin(t)
            const x = cx + a * Math.sign(c) * Math.sqrt(Math.abs(c))
            const y = cy + b * Math.sign(s) * Math.sqrt(Math.abs(s))
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.closePath()
    }

    // The square's shadow, outside its 4 px rounded edge only (a CSS box
    // shadow isn't drawn under the box).
    Canvas {
        id: shadow
        readonly property real pad: 8
        x: -pad; y: -pad
        width: root.width + 2 * pad; height: root.height + 2 * pad
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const p = pad, w = root.width, h = root.height
            ctx.fillStyle = "#000000"
            ctx.shadowColor = Qt.rgba(0, 0, 0, 0.12); ctx.shadowBlur = 2; ctx.shadowOffsetX = 0; ctx.shadowOffsetY = 0
            ctx.beginPath(); ctx.roundedRect(p, p, w, h, 4, 4); ctx.fill()
            ctx.shadowColor = Qt.rgba(0, 0, 0, 0.14); ctx.shadowBlur = 4; ctx.shadowOffsetY = 2
            ctx.beginPath(); ctx.roundedRect(p, p, w, h, 4, 4); ctx.fill()
            ctx.shadowColor = "transparent"; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath(); ctx.roundedRect(p, p, w, h, 4, 4); ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }
    }
    Image {
        id: src
        visible: false
        source: root.source
        asynchronous: true
        sourceSize.width: Math.ceil(root.width * Math.max(1, Screen.devicePixelRatio))
        sourceSize.height: Math.ceil(root.height * Math.max(1, Screen.devicePixelRatio))
        // The pixels reach the canvas a moment after Ready; paint again then.
        onStatusChanged: { pic.requestPaint(); if (status === Image.Ready) repaint.restart() }
    }
    Timer { id: repaint; interval: 50; onTriggered: pic.requestPaint() }
    // Painted at twice the size and scaled down, so the edge stays smooth.
    Canvas {
        id: pic
        readonly property real oversample: 2
        width: root.width * oversample; height: root.height * oversample
        scale: 1 / oversample
        transformOrigin: Item.TopLeft
        smooth: true
        antialiasing: true
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height, k = oversample
            ctx.save()
            ctx.beginPath(); root.squircle(ctx, w, h, 0); ctx.clip()
            ctx.fillStyle = "#FAFAFA"; ctx.fillRect(0, 0, w, h)
            if (src.status === Image.Ready) ctx.drawImage(src, 0, 0, w, h)
            ctx.restore()
            // Fluent's outline: 1 px, offset -1 (inside the edge).
            ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.05); ctx.lineWidth = k
            ctx.beginPath(); root.squircle(ctx, w, h, k / 2); ctx.stroke()
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.ignored: true
}
