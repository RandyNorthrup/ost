import QtQuick

// A Fluent UI System Icon in any colour. The SVGs are single-colour glyphs
// filled with #212121, so the colour is swapped in the SVG text itself:
// this renders identically on GPU, software and offscreen backends.
Image {
    id: root
    property string name
    property int size: 20
    property color color: theme.icon
    width: size
    height: size
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
    fillMode: Image.PreserveAspectFit

    property string svgText: ""
    onNameChanged: load()
    Component.onCompleted: load()

    function load() {
        if (!name) { svgText = ""; return }
        const url = Qt.resolvedUrl("../assets/icons/" + name + ".svg")
        const cached = IconCache.get(url)
        if (cached !== undefined) { svgText = cached; return }
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            // The icon may be gone by the time its file arrives.
            if (!root) return
            if (xhr.responseText) {
                IconCache.put(url, xhr.responseText)
                // A reply for a name we've since changed from (the mic
                // turning off while its "on" glyph still loads) mustn't
                // replace the newer glyph.
                if (Qt.resolvedUrl("../assets/icons/" + root.name + ".svg") === url)
                    root.svgText = xhr.responseText
            } else {
                console.warn("icon failed:", url)
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    source: svgText
        ? "data:image/svg+xml;utf8," + encodeURIComponent(svgText.replace(/#212121/g, root.color.toString()))
        : ""
}
