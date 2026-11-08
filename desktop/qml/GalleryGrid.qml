import QtQuick

// Teams' gallery: 16:9 tiles as large as the space allows for the best
// column count, rows centred (the last one too).
Item {
    id: gallery
    /// The call window (tiles read its state).
    property var call
    /// Who to show, in order.
    property var people: []
    /// Tiles for the shared display window (Optimize for room).
    property bool forRoom: false
    readonly property int count: people.length
    // The column count giving the largest 16:9 tiles. Plain numbers: Qt
    // 6.10's QML compiler crashes on an object literal returned here.
    readonly property int cols: {
        let bestCols = 1, bestW = 0
        for (let c = 1; c <= count; c++) {
            const w = Math.min(width / c, height / Math.ceil(count / c) * 16 / 9)
            if (w > bestW + 0.01) { bestW = w; bestCols = c }
        }
        return bestCols
    }
    readonly property int rows: Math.max(1, Math.ceil(count / cols))
    readonly property real tileW: Math.min(width / cols, height / rows * 16 / 9)
    readonly property real tileH: tileW * 9 / 16
    Repeater {
        model: gallery.visible ? gallery.people : []
        MeetingTile {
            required property var modelData
            required property int index
            readonly property int row: Math.floor(index / gallery.cols)
            readonly property int inRow: row === gallery.rows - 1 ? gallery.count - row * gallery.cols : gallery.cols
            call: gallery.call
            person: modelData
            forRoom: gallery.forRoom
            x: (gallery.width - inRow * gallery.tileW) / 2 + (index % gallery.cols) * gallery.tileW
            y: (gallery.height - gallery.rows * gallery.tileH) / 2 + row * gallery.tileH
            width: gallery.tileW; height: gallery.tileH
        }
    }
}
