import QtQuick
import com.ost.desktop

// Teams' box around inline code in a received message (`code`, measured
// on winpc, "OST TEST 70": padding 4, a 0.67 NeutralStroke1 border, radius
// 4, margin 0 2, on NeutralBackground1). Qt's rich text can't draw an
// inline box, so this sits behind the TextEdit's text (placed inside it,
// directly or through a Loader, with a negative z): RichText gives each
// run the room the box's sides take and finds its pieces on the laid-out
// lines. A run broken over lines gets a box per line, open where the line
// breaks, as a browser draws it.
Item {
    id: root
    required property TextEdit edit
    property var boxes: []
    property real border: 0.67
    // The text sits at fractional places (the bubble's padding is 15.7);
    // a browser puts a box's edges on device pixels, so this shifts each
    // box (its size already whole device pixels) onto the window's pixels.
    // Again as the list it is in scrolls.
    property point shift: Qt.point(0, 0)
    property Item flick: null
    property real dpr: 1
    function reshift() {
        const o = root.mapToItem(null, 0, 0)
        const off = v => Math.round(v * dpr) / dpr - v
        shift = Qt.point(off(o.x), off(o.y))
    }
    function refresh() {
        let r
        try { r = JSON.parse(helper.codeBoxes(theme.mono)) } catch (e) { return }
        dpr = r.dpr > 0 ? r.dpr : 1
        reshift()
        border = r.border
        boxes = r.boxes
        // Just given room, or not laid out for its width yet: again soon.
        if (!r.settled && retries < 20) { retries++; again.restart() }
        else if (r.settled) retries = 0
    }
    property int retries: 0
    Timer { id: again; interval: 16; onTriggered: root.refresh() }
    RichText { id: helper }
    // New text is a new document (the room is made again); a new width
    // wraps it again.
    Connections {
        target: root.edit
        function onTextChanged() { Qt.callLater(root.refresh) }
        function onWidthChanged() { Qt.callLater(root.refresh) }
        function onContentWidthChanged() { Qt.callLater(root.refresh) }
        function onContentHeightChanged() { Qt.callLater(root.refresh) }
        function onLineCountChanged() { Qt.callLater(root.refresh) }
    }
    Connections {
        target: root.flick
        enabled: root.boxes.length > 0
        function onContentYChanged() { root.reshift() }
    }
    Component.onCompleted: {
        let p = root.parent
        while (p && p.contentY === undefined) p = p.parent
        flick = p
        Qt.callLater(refresh)
    }
    Repeater {
        model: root.boxes
        Item {
            id: piece
            required property var modelData
            x: modelData.x + root.shift.x; y: modelData.y + root.shift.y
            width: modelData.w; height: modelData.h
            // An open side: the rounded box runs on past it, cut off here.
            clip: modelData.open_start || modelData.open_end
            Rectangle {
                readonly property real past: radius + root.border + 1
                x: piece.modelData.open_start ? -past : 0
                width: piece.width + (piece.modelData.open_start ? past : 0) + (piece.modelData.open_end ? past : 0)
                height: piece.height
                radius: 4
                color: theme.inlineCodeFill
                border.width: root.border
                border.color: theme.inlineCodeStroke
            }
        }
    }
}
