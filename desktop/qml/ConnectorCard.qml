import QtQuick
import QtQuick.Controls.Basic

// Teams' Office 365 connector card
// (application/vnd.microsoft.teams.card.o365connector), measured on winpc
// ("OST TEST 116" 2026-11-12, "OST TEST 124" 2026-11-13): a 3 px bar in the
// card's themeColor (radius 4 4 0 0) on top of a white frame (0.67 #E0E0E0,
// radius 4), 452 wide; from 16.7 in, all NeutralForeground2:
// - the title 16/22 semibold 26.7 from the top; under it, 8 apart, the
//   text (14/20) and each section; the frame ends 16.6 under the last;
// - a section is a column 10 apart: its title (semibold); the activity
//   (an activityImage 52 x 52, stretched, with activityTitle 14/20
//   semibold, activitySubtitle and activityText 14/20 30 apart, 62 in from
//   it; the row stays, 0 tall, when the section has none); its text; its
//   images (160 x 120, stretched, 10 apart); its facts (the name semibold,
//   the value 10 after the widest name; 30 apart, 10 more under the last);
// - text is markdown unless the section says "markdown": false: bold
//   (700), italic, links (#4F52B2, no underline) and "- " lists (40 in, 14
//   above and below, 20 a line).
// Teams shows no buttons for potentialAction (OpenUri, ActionCard), so
// neither does OST.
Item {
    id: card
    property var content: ({})
    property real cardWidth: 452
    width: cardWidth
    height: frame.y + frame.height
    readonly property var sections: content && content.sections ? content.sections : []
    readonly property string theme_: String(content.themeColor || "").replace(/^#/, "")
    readonly property real inner: cardWidth - 33.4

    // Markdown as Teams renders it in these cards: paragraphs and "- " / "* "
    // lists, inline bold, italic and links.
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function inline(t, md) {
        let s = esc(t)
        if (!md) return s
        const link = theme.brandLink
        s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, (m, label, url) => "<a href=\"" + url.replace(/"/g, "%22") + "\" style=\"color:" + link + ";text-decoration:none\">" + label + "</a>")
        s = s.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/__(.+?)__/g, "<b>$1</b>")
        s = s.replace(/(^|[^*\w])\*(?!\s)(.+?)\*(?!\w)/g, "$1<i>$2</i>").replace(/(^|[^_\w])_(?!\s)(.+?)_(?!\w)/g, "$1<i>$2</i>")
        return s
    }
    /// Text that already comes as HTML (the chat service stores a connector
    /// card's markdown converted: <p>, <strong>, <em>, <a>, <ul><li>).
    function isHtml(t) { return /<\/?(p|ul|ol|li|strong|em|b|i|a|br)\b[^>]*>/i.test(String(t || "")) }
    function restyle(h) {
        const link = theme.brandLink
        return String(h).replace(/\s*\n\s*/g, " ")
            .replace(/<(\/?)strong\b[^>]*>/gi, "<$1b>").replace(/<(\/?)em\b[^>]*>/gi, "<$1i>")
            .replace(/<a\b(?![^>]*style=)([^>]*)>/gi, "<a style=\"color:" + link + ";text-decoration:none\"$1>")
            .trim()
    }
    function htmlBlocks(h) {
        const out = []
        const re = /<(ul|ol)\b[^>]*>([\s\S]*?)<\/\1>|<p\b[^>]*>([\s\S]*?)<\/p>/gi
        let at = 0, m
        const loose = t => { const x = restyle(t); if (x.replace(/<br\s*\/?>/gi, "").trim()) out.push({ para: x }) }
        while ((m = re.exec(h)) !== null) {
            loose(h.slice(at, m.index))
            if (m[1]) {
                const items = []
                const li = /<li\b[^>]*>([\s\S]*?)<\/li>/gi
                let l
                while ((l = li.exec(m[2])) !== null) items.push(restyle(l[1]))
                if (items.length) out.push({ list: items })
            } else loose(m[3])
            at = re.lastIndex
        }
        loose(h.slice(at))
        return out
    }
    /// [{para: html} | {list: [html]}]
    function blocks(t, md) {
        if (isHtml(t)) return htmlBlocks(String(t))
        const out = []
        let list = null
        for (const raw of String(t || "").split(/\r?\n/)) {
            const m = md ? /^\s*[-*]\s+(.*)$/.exec(raw) : null
            if (m) { if (!list) { list = []; out.push({ list: list }) } list.push(inline(m[1], md)); continue }
            list = null
            if (raw.trim() === "") continue
            const last = out.length ? out[out.length - 1] : null
            if (last && last.para !== undefined && !last.gap) last.para += "<br>" + inline(raw, md)
            else out.push({ para: inline(raw, md) })
        }
        return out
    }
    TextMetrics { id: factMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: "" }
    function nameWidth(facts) {
        let w = 0
        for (const f of facts) { factMetrics.text = String(f.name || ""); w = Math.max(w, factMetrics.advanceWidth) }
        return w
    }
    function open(link) { Qt.openUrlExternally(link) }

    // Markdown text: paragraphs (14/20) and lists.
    component Md: Column {
        id: md
        property string source: ""
        property bool markdown: true
        property bool strong: false
        width: parent ? parent.width : 0
        Repeater {
            model: card.blocks(md.source, md.markdown)
            Item {
                required property var modelData
                width: md.width
                height: modelData.list ? 14 + listCol.height + 14 : Math.max(1, para.lineCount) * 20
                Text {
                    id: para
                    visible: !parent.modelData.list
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: parent.modelData.para || ""
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; font.weight: md.strong ? Font.DemiBold : Font.Normal
                    color: theme.textStrong; linkColor: theme.brandLink
                    onLinkActivated: link => card.open(link)
                    HoverHandler { enabled: !!parent.hoveredLink; cursorShape: Qt.PointingHandCursor }
                }
                // Rich text lines measure under 20; Teams' are 20 each.
                Column {
                    id: listCol
                    visible: !!parent.modelData.list
                    y: 14; x: 40; width: parent.width - 40
                    Repeater {
                        model: parent.parent.modelData.list || []
                        Item {
                            required property string modelData
                            width: parent.width; height: Math.max(1, li.lineCount) * 20
                            Rectangle { x: -14; y: 8; width: 5; height: 5; radius: 2.5; color: theme.textStrong }
                            Text {
                                id: li
                                width: parent.width; wrapMode: Text.Wrap
                                textFormat: Text.RichText
                                text: parent.modelData
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                font.family: theme.font; font.pixelSize: 14; color: theme.textStrong; linkColor: theme.brandLink
                                onLinkActivated: link => card.open(link)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: frame
        width: card.cardWidth
        height: body.y + body.height + 16.6
        radius: 4
        color: theme.surface
        border.color: theme.pick("#E0E0E0", "#3D3D3D"); border.width: 0.67
        Column {
            id: body
            x: 16.7; y: 26.7
            width: card.inner
            spacing: 8
            Text {
                visible: !!card.content.title
                width: parent.width; wrapMode: Text.Wrap
                text: card.content.title || ""
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Md { visible: !!card.content.text; source: card.content.text || ""; width: parent.width }
            Repeater {
                model: card.sections
                Column {
                    id: sec
                    required property var modelData
                    readonly property bool md: modelData.markdown !== false
                    readonly property var facts: modelData.facts || []
                    readonly property var images: modelData.images || []
                    readonly property bool hasActivity: !!(modelData.activityTitle || modelData.activitySubtitle || modelData.activityText || modelData.activityImage)
                    width: body.width
                    spacing: 10
                    Md { visible: !!sec.modelData.title; source: sec.modelData.title || ""; markdown: sec.md; strong: true; width: parent.width }
                    // The activity: its picture beside its three lines (Teams
                    // keeps the row, 0 tall, in a section without one; Qt's
                    // Column skips spacing around a 0-tall item, hence 0.01).
                    Item {
                        width: parent.width
                        height: sec.hasActivity ? Math.max(sec.modelData.activityImage ? 52 : 0, actCol.height) : 0.01
                        Image {
                            visible: !!sec.modelData.activityImage
                            width: 52; height: 52
                            source: { backend.emoticonsVersion; return sec.modelData.activityImage ? backend.cardImage(sec.modelData.activityImage) : "" }
                            fillMode: Image.Stretch
                            asynchronous: true
                        }
                        Column {
                            id: actCol
                            x: sec.modelData.activityImage ? 62 : 0
                            width: parent.width - x
                            spacing: 10
                            Md { visible: !!sec.modelData.activityTitle; source: sec.modelData.activityTitle || ""; markdown: sec.md; strong: true; width: parent.width }
                            Md { visible: !!sec.modelData.activitySubtitle; source: sec.modelData.activitySubtitle || ""; markdown: sec.md; width: parent.width }
                            Md { visible: !!sec.modelData.activityText; source: sec.modelData.activityText || ""; markdown: sec.md; width: parent.width }
                        }
                    }
                    Md { visible: !!sec.modelData.text; source: sec.modelData.text || ""; markdown: sec.md; width: parent.width }
                    // Images, 160 x 120, 10 apart.
                    Flow {
                        visible: sec.images.length > 0
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: sec.images
                            Image {
                                required property var modelData
                                width: 160; height: 120
                                source: { backend.emoticonsVersion; return modelData.image ? backend.cardImage(modelData.image) : "" }
                                fillMode: Image.Stretch
                                asynchronous: true
                                Accessible.role: Accessible.Graphic
                                Accessible.name: modelData.title || ""
                            }
                        }
                    }
                    // Facts, 30 apart, 10 more under the last.
                    Column {
                        visible: sec.facts.length > 0
                        width: parent.width
                        spacing: 10
                        bottomPadding: 10
                        readonly property real names: card.nameWidth(sec.facts)
                        Repeater {
                            model: sec.facts
                            Item {
                                required property var modelData
                                width: parent.width; height: Math.max(20, val.height)
                                Text {
                                    text: String(parent.modelData.name || "")
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
                                }
                                Md {
                                    id: val
                                    x: parent.parent.names + 10; width: parent.width - x
                                    source: String(parent.modelData.value || ""); markdown: sec.md
                                }
                            }
                        }
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
