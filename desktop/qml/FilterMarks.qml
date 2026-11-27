import QtQuick

// The chat list's filter-text marks (Teams' "Filter by person, chat or
// channel name", measured on Teams web 2026-11-27): every match of the
// typed text in a row's name gets a colorPaletteMarigoldBackground2 fill
// (#F9E2AE, no radius or padding) and its letters turn
// colorNeutralForeground1, whatever the row's own text colour.
// Put it inside the name's Text: it draws the fills over the text's own
// letters there and the matched letters again on top.
Item {
    id: root
    /// The lower-cased filter text ("" shows nothing).
    property string query: ""
    readonly property Text label: parent as Text
    anchors.fill: parent
    readonly property var marks: {
        const out = []
        if (!label || !query) return out
        const t = label.text || "", low = t.toLowerCase()
        let i = low.indexOf(query)
        while (i >= 0 && query.length > 0) {
            out.push({ at: i, x: metrics.advanceWidth(t.substring(0, i)), w: metrics.advanceWidth(t.substring(i, i + query.length)), text: t.substring(i, i + query.length) })
            i = low.indexOf(query, i + query.length)
        }
        return out
    }
    FontMetrics { id: metrics; font: root.label ? root.label.font : Qt.font({}) }
    Repeater {
        model: root.marks
        Rectangle {
            required property var modelData
            x: modelData.x; width: Math.max(0, Math.min(modelData.w, root.width - modelData.x))
            height: root.height
            color: theme.pick("#F9E2AE", "#835B00", "#000000")
        }
    }
    // The matched letters in NeutralForeground1, over the row's own text.
    Item {
        width: root.width; height: root.height
        clip: true
        Repeater {
            model: root.marks
            Text {
                required property var modelData
                x: modelData.x
                text: modelData.text
                font: root.label ? root.label.font : Qt.font({})
                color: theme.text
            }
        }
    }
}
