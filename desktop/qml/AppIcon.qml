import QtQuick
import QtQuick.Window

// An app icon in Teams' squircle, on a #FAFAFA ground while it loads
// (Teams' app icon in a tab's header: a 32 px <img> with border-radius 50%
// and corner-shape superellipse(2), i.e. the curve |x|^4 + |y|^4 = 1).
Rectangle {
    id: root
    property url source
    radius: width / 2.6
    color: pic.visible ? "transparent" : theme.pick("#FAFAFA", "#1F1F1F")

    Image {
        id: src
        visible: false
        source: root.source
        asynchronous: true
        sourceSize.width: Math.ceil(root.width * 2 * Math.max(1, Screen.devicePixelRatio))
        sourceSize.height: Math.ceil(root.height * 2 * Math.max(1, Screen.devicePixelRatio))
        onStatusChanged: { pic.requestPaint(); if (status === Image.Ready) repaint.restart() }
    }
    Timer { id: repaint; interval: 50; onTriggered: pic.requestPaint() }
    // Painted at twice the size and scaled down, so it stays sharp on
    // scaled screens (as Avatar does).
    Canvas {
        id: pic
        readonly property real oversample: 2
        width: root.width * oversample; height: root.height * oversample
        scale: 1 / oversample
        transformOrigin: Item.TopLeft
        smooth: true
        antialiasing: true
        visible: src.status === Image.Ready
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (src.status !== Image.Ready) return
            ctx.beginPath()
            const a = width / 2, b = height / 2, steps = 96
            for (let i = 0; i <= steps; i++) {
                const t = 2 * Math.PI * i / steps, c = Math.cos(t), s = Math.sin(t)
                const x = a + a * Math.sign(c) * Math.sqrt(Math.abs(c)), y = b + b * Math.sign(s) * Math.sqrt(Math.abs(s))
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.closePath()
            ctx.clip()
            ctx.drawImage(src, 0, 0, width, height)
        }
    }
}
