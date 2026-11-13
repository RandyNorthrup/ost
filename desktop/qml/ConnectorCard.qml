import QtQuick
import QtQuick.Controls.Basic

// Teams' Office 365 connector card
// (application/vnd.microsoft.teams.card.o365connector), measured on winpc
// 2026-11-12 ("OST TEST 116"): a 3 px bar in the card's themeColor
// (radius 4 4 0 0) on top of a white frame (0.67 #E0E0E0, radius 4), 452
// wide; from 16.7 in, all NeutralForeground2:
// - the title 16/22 semibold 26.7 from the top, the text 14/20 at 56.7;
// - each section: activityTitle 14/20 semibold, activitySubtitle and
//   activityText 14/20, then its facts (the name semibold, the value 10
//   after the widest name), lines 30 apart;
// 26.6 under the last line. Teams showed no button for an OpenUri
// potentialAction, so neither does OST.
Item {
    id: card
    property var content: ({})
    property real cardWidth: 452
    width: cardWidth
    height: frame.y + frame.height
    readonly property var sections: content && content.sections ? content.sections : []
    // The lines in order: {text, bold, gap} or {fact: [name, value], gap};
    // 8 above the text and each section's first line, 10 within a section.
    readonly property var lines: {
        const out = []
        if (content.text) out.push({ text: content.text, bold: false, gap: 8 })
        for (const s of sections) {
            const sec = []
            if (s.activityTitle) sec.push({ text: s.activityTitle, bold: true })
            if (s.activitySubtitle) sec.push({ text: s.activitySubtitle, bold: false })
            if (s.activityText) sec.push({ text: s.activityText, bold: false })
            if (s.title) sec.push({ text: s.title, bold: true })
            if (s.text) sec.push({ text: s.text, bold: false })
            for (const f of (s.facts || [])) sec.push({ fact: [String(f.name || ""), String(f.value || "")] })
            sec.forEach((l, i) => { l.gap = i === 0 ? 8 : 10; out.push(l) })
        }
        return out
    }
    readonly property string theme_: String(content.themeColor || "").replace(/^#/, "")
    TextMetrics { id: factMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: "" }
    readonly property real nameWidth: {
        let w = 0
        for (const l of lines) if (l.fact) { factMetrics.text = l.fact[0]; w = Math.max(w, factMetrics.advanceWidth) }
        return w
    }

    Rectangle {
        id: frame
        width: card.cardWidth
        height: body.y + body.height + 26.6
        radius: 4
        color: theme.surface
        border.color: theme.pick("#E0E0E0", "#3D3D3D"); border.width: 0.67
        Text {
            id: title
            visible: !!card.content.title
            x: 16.7; y: 26.7; width: card.cardWidth - 33.4; wrapMode: Text.Wrap
            text: card.content.title || ""
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong
        }
        Column {
            id: body
            x: 16.7; y: title.visible ? title.y + title.height : 26.7 - 8
            width: card.cardWidth - 33.4
            Repeater {
                model: card.lines
                Item {
                    required property var modelData
                    width: body.width; height: modelData.gap + Math.max(20, (modelData.fact ? val.height : line.height))
                    Text {
                        id: line
                        y: modelData.gap
                        visible: !modelData.fact
                        width: parent.width; wrapMode: Text.Wrap
                        text: modelData.text || ""
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; font.weight: modelData.bold ? Font.DemiBold : Font.Normal; color: theme.textStrong
                    }
                    Text {
                        visible: !!modelData.fact
                        y: modelData.gap
                        text: modelData.fact ? modelData.fact[0] : ""
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
                    }
                    Text {
                        id: val
                        visible: !!modelData.fact
                        y: modelData.gap
                        x: card.nameWidth + 10; width: parent.width - x; wrapMode: Text.Wrap
                        text: modelData.fact ? modelData.fact[1] : ""
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                    }
                }
            }
        }
    }
    // The theme colour bar over the frame's top edge.
    Rectangle {
        visible: /^[0-9a-fA-F]{6}$/.test(card.theme_)
        width: card.cardWidth; height: 3
        topLeftRadius: 4; topRightRadius: 4
        color: "#" + card.theme_
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: content.title || content.summary || ""
}
