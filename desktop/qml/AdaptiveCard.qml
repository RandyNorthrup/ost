import QtQuick
import QtQuick.Controls.Basic

// A native Adaptive Cards renderer with Teams' host config (824631) and the
// frame Teams draws for cards in messages (944311), measured against cards
// rendered by the desktop client:
// - the card: NeutralCardBackground (#FAFAFA), radius 6, shadow2; content
//   16 in at the sides and bottom, 26 from the top; 448 wide in a chat at
//   least 720 wide, else 360;
// - spacing none 0 / small 8 / default 12 / medium 16 / large 20 /
//   extraLarge 24 / padding 16; a separator is a NeutralStroke1 line in the
//   middle of the spacing;
// - text sizes 12/14/14/18/24 on lines 16/20/20/24/32; weights 300/400/600;
//   colours default #242424, subtle #616161, accent BrandForeground1, good,
//   warning, attention; links BrandForeground1, bold 700;
// - containers with another style get its background and 16 padding;
// - FactSet: titles bold, 16 to the values, rows 6 apart;
// - actions: Fluent buttons (31.3 tall, padding 5 12, NeutralStroke1 border,
//   radius 4, 14/20 semibold), 8 apart, 12 under the body; a ShowCard opens
//   16 under the actions as a full-width emphasis card and its button turns
//   brand-filled.
Item {
    id: card
    property var content: ({})
    property real cardWidth: 448
    // The card's ids: shown/hidden state (Action.ToggleVisibility) and the
    // inputs' values.
    property var hidden: ({})
    property var values: ({})
    property string openShowCard: ""
    signal action(var action, var inputs)
    width: cardWidth
    height: frame.height

    readonly property var spacingPx: ({ none: 0, small: 8, default: 12, medium: 16, large: 20, extralarge: 24, padding: 16 })
    readonly property var sizePx: ({ small: 12, default: 14, medium: 14, large: 18, extralarge: 24 })
    readonly property var lineH: ({ small: 16, default: 20, medium: 20, large: 24, extralarge: 32 })
    readonly property var imagePx: ({ small: 36, medium: 54, large: 108 })
    function lc(v, d) { return v === undefined || v === null ? d : String(v).toLowerCase() }
    function spacingOf(e) { const s = lc(e.spacing, "default"); return spacingPx[s] !== undefined ? spacingPx[s] : 12 }
    function styleBg(style) {
        switch (lc(style, "default")) {
        case "emphasis": return theme.pick("#F5F5F5", "#141414")
        case "accent": return theme.pick("#F2F4FC", "#00061D")
        case "good": return theme.pick("#E9F9E8", "#052505")
        case "warning": return theme.pick("#FFF9F5", "#331C00")
        case "attention": return theme.pick("#FDF3F4", "#3B1418")
        default: return theme.pick("#FAFAFA", "#1F1F1F")
        }
    }
    function colorOf(c, subtle) {
        switch (lc(c, "default")) {
        case "accent": return theme.brandForeground1
        case "good": return theme.successFg
        case "warning": return theme.pick("#8A3707", "#F9E2AE")
        case "attention": return theme.pick("#B10E1C", "#DC626D")
        case "light": return theme.pick("#FFFFFF", "#FFFFFF")
        case "dark": return theme.pick("#242424", "#242424")
        default: return subtle ? theme.textSecondary : theme.text
        }
    }
    function weightOf(w) { const v = lc(w, "default"); return v === "bolder" ? Font.DemiBold : v === "lighter" ? Font.Light : Font.Normal }
    function shown(e) {
        if (!e) return false
        if (e.id && hidden[e.id] !== undefined) return !hidden[e.id]
        return e.isVisible !== false
    }
    function toggle(targets) {
        const h = Object.assign({}, hidden)
        for (const t of targets || []) {
            const id = typeof t === "string" ? t : t.elementId
            if (!id) continue
            const now = h[id] !== undefined ? !h[id] : false
            let vis = typeof t === "string" || t.isVisible === undefined ? !now : t.isVisible
            h[id] = !vis
        }
        hidden = h
    }
    function setValue(id, v) { if (!id) return; const o = Object.assign({}, values); o[id] = v; values = o }
    function run(a) {
        const t = lc(a.type, "")
        if (t === "action.openurl") Qt.openUrlExternally(a.url)
        else if (t === "action.showcard") openShowCard = openShowCard === (a.id || a.title) ? "" : (a.id || a.title)
        else if (t === "action.togglevisibility") toggle(a.targetElements)
        else card.action(a, values)
    }
    // Markdown as Teams' cards support it: **bold**, _italic_ / *italic*,
    // [links](url), "- " and "1. " lists, line breaks.
    function markdown(t) {
        if (t === undefined || t === null) return ""
        let s = String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2" style="color:' + theme.brandForeground1 + '">$1</a>')
        s = s.replace(/\*\*([^*]+)\*\*/g, '<b style="font-weight:700">$1</b>')
        s = s.replace(/(^|[^\w*])\*([^*\n]+)\*(?!\*)/g, '$1<i>$2</i>')
        s = s.replace(/(^|[^\w])_([^_\n]+)_(?!\w)/g, '$1<i>$2</i>')
        const lines = s.split(/\r?\n/)
        let out = "", list = ""
        for (const line of lines) {
            const ul = /^\s*[-*]\s+(.*)$/.exec(line), ol = /^\s*\d+\.\s+(.*)$/.exec(line)
            if (ul || ol) {
                const tag = ul ? "ul" : "ol"
                if (list !== tag) { if (list) out += "</" + list + ">"; out += "<" + tag + ">"; list = tag }
                out += "<li>" + (ul || ol)[1] + "</li>"
            } else {
                if (list) { out += "</" + list + ">"; list = "" }
                out += (out && !out.endsWith(">") ? "<br>" : "") + line
            }
        }
        if (list) out += "</" + list + ">"
        return out
    }

    FluentSurface {
        id: frame
        width: card.cardWidth
        height: body.y + body.height + (actions.visible ? 12 + actions.height : 0)
            + (showCardHost.visible ? 16 + showCardHost.height : 16)
        depth: 2; radius: 6
        color: card.styleBg("default")
        ElementList {
            id: body
            x: 16; y: 26; width: card.cardWidth - 32
            items: card.content && card.content.body ? card.content.body : []
            parentStyle: "default"
        }
        ActionRow {
            id: actions
            visible: !!(card.content && card.content.actions && card.content.actions.length)
            x: 16; y: body.y + body.height + 12; width: card.cardWidth - 32
            actions: card.content && card.content.actions ? card.content.actions.slice(0, 6) : []
        }
        // The open ShowCard, edge to edge.
        Rectangle {
            id: showCardHost
            readonly property var shownAction: (card.content && card.content.actions || []).find(a => card.lc(a.type, "") === "action.showcard" && (a.id || a.title) === card.openShowCard)
            visible: !!shownAction
            x: 0; y: actions.y + actions.height + 16
            width: card.cardWidth; height: visible ? sub.y + sub.height + 16 : 0
            color: card.styleBg("emphasis")
            radius: 6
            Rectangle { width: parent.width; height: 6; color: parent.color }
            ElementList {
                id: sub
                x: 16; y: 16; width: card.cardWidth - 32
                items: showCardHost.shownAction && showCardHost.shownAction.card ? (showCardHost.shownAction.card.body || []) : []
                parentStyle: "emphasis"
            }
        }
    }

    // A vertical list of elements with Teams' spacing and separators.
    component ElementList: Column {
        id: list
        property var items: []
        property string parentStyle: "default"
        Repeater {
            model: list.items
            Column {
                id: slot
                required property var modelData
                required property int index
                readonly property bool visibleNow: card.shown(modelData)
                readonly property bool firstShown: { for (let i = 0; i < index; i++) if (card.shown(list.items[i])) return false; return true }
                visible: visibleNow
                width: list.width
                Item {
                    visible: !slot.firstShown
                    width: list.width
                    height: card.spacingOf(slot.modelData) + (slot.modelData.separator === true ? 0.67 : 0)
                    Rectangle {
                        visible: slot.modelData.separator === true
                        y: card.spacingOf(slot.modelData) / 2; width: parent.width; height: 0.67
                        color: theme.stroke
                    }
                }
                Loader {
                    width: list.width
                    sourceComponent: card.componentFor(slot.modelData.type)
                    onLoaded: { item.e = slot.modelData; item.parentStyle = list.parentStyle }
                }
            }
        }
    }
    // The natural width of a column's elements (Teams' "auto" columns).
    FontMetrics { id: fmNormal; font.family: theme.font; font.pixelSize: 14 }
    FontMetrics { id: fmBold; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
    FontMetrics { id: fmLight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Light }
    function naturalWidth(items) {
        let w = 0
        for (const i of items) {
            const t = lc(i.type, "")
            if (t === "textblock") {
                // Metrics at 14 px, scaled to the block's size.
                const fm = lc(i.weight, "default") === "bolder" ? fmBold : lc(i.weight, "default") === "lighter" ? fmLight : fmNormal
                const k = (sizePx[lc(i.size, "default")] || 14) / 14
                for (const line of String(i.text || "").replace(/\*\*|_|\[|\]\([^)]*\)/g, "").split("\n")) w = Math.max(w, fm.advanceWidth(line) * k)
            } else if (t === "image") {
                w = Math.max(w, i.width && /px$/.test(String(i.width)) ? parseFloat(i.width) : (imagePx[lc(i.size, "")] || 54))
            } else if (t === "container") {
                w = Math.max(w, naturalWidth(i.items || []))
            } else if (t === "actionset") {
                w = Math.max(w, 120)
            }
        }
        return Math.ceil(w)
    }
    function componentFor(type) {
        switch (lc(type, "")) {
        case "textblock": return textBlock
        case "richtextblock": return richTextBlock
        case "image": return imageEl
        case "imageset": return imageSet
        case "container": return container
        case "columnset": return columnSet
        case "factset": return factSet
        case "actionset": return actionSet
        case "table": return table
        case "input.text": case "input.number": case "input.date": case "input.time": return textInput
        case "input.toggle": return toggleInput
        case "input.choiceset": return choiceInput
        default: return null
        }
    }

    Component {
        id: textBlock
        Text {
            property var e: ({})
            property string parentStyle
            readonly property string sz: card.lc(e.size, "default")
            width: parent ? parent.width : 0
            text: card.markdown(e.text)
            textFormat: Text.RichText
            wrapMode: e.wrap === true ? Text.Wrap : Text.NoWrap
            elide: e.wrap === true ? Text.ElideNone : Text.ElideRight
            maximumLineCount: e.maxLines > 0 ? e.maxLines : (e.wrap === true ? 100000 : 1)
            lineHeight: card.lineH[sz] || 20; lineHeightMode: Text.FixedHeight
            font.family: card.lc(e.fontType, "") === "monospace" ? "monospace" : theme.font
            font.pixelSize: card.sizePx[sz] || 14
            font.weight: card.weightOf(e.weight)
            color: card.colorOf(e.color, e.isSubtle === true)
            linkColor: theme.brandForeground1
            horizontalAlignment: card.lc(e.horizontalAlignment, "left") === "center" ? Text.AlignHCenter : card.lc(e.horizontalAlignment, "left") === "right" ? Text.AlignRight : Text.AlignLeft
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }
    Component {
        id: richTextBlock
        Text {
            property var e: ({})
            property string parentStyle
            width: parent ? parent.width : 0
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            linkColor: theme.brandForeground1
            horizontalAlignment: card.lc(e.horizontalAlignment, "left") === "center" ? Text.AlignHCenter : card.lc(e.horizontalAlignment, "left") === "right" ? Text.AlignRight : Text.AlignLeft
            text: (e.inlines || []).map(r => {
                if (typeof r === "string") return card.markdown(r)
                let t = String(r.text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                const st = []
                st.push("font-size:" + (card.sizePx[card.lc(r.size, "default")] || 14) + "px")
                st.push("color:" + card.colorOf(r.color, r.isSubtle === true))
                if (card.lc(r.weight, "") === "bolder") st.push("font-weight:600")
                if (r.italic) st.push("font-style:italic")
                if (r.strikethrough) st.push("text-decoration:line-through")
                if (r.underline) st.push("text-decoration:underline")
                if (r.highlight) st.push("background-color:" + theme.pick("#FFEDD6", "#4D2A00"))
                if (card.lc(r.fontType, "") === "monospace") st.push("font-family:monospace")
                t = '<span style="' + st.join(";") + '">' + t + "</span>"
                if (r.selectAction && card.lc(r.selectAction.type, "") === "action.openurl") t = '<a href="' + r.selectAction.url + '">' + t + "</a>"
                return t
            }).join("")
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
    Component {
        id: imageEl
        Item {
            id: img
            property var e: ({})
            property string parentStyle
            readonly property string sz: card.lc(e.size, "auto")
            readonly property real fixedW: e.width && /px$/.test(String(e.width)) ? parseFloat(e.width) : (card.imagePx[sz] || 0)
            readonly property real fixedH: e.height && /px$/.test(String(e.height)) ? parseFloat(e.height) : 0
            readonly property real boxW: fixedW > 0 ? fixedW : sz === "stretch" ? width : Math.min(width, pic.implicitWidth)
            readonly property real boxH: fixedH > 0 ? fixedH : (pic.implicitWidth > 0 ? boxW * pic.implicitHeight / pic.implicitWidth : boxW)
            width: parent ? parent.width : 0
            height: boxH
            Item {
                id: picBox
                width: img.boxW; height: img.boxH
                x: card.lc(img.e.horizontalAlignment, "left") === "center" ? (img.width - width) / 2 : card.lc(img.e.horizontalAlignment, "left") === "right" ? img.width - width : 0
                Rectangle { anchors.fill: parent; visible: !!img.e.backgroundColor; color: img.e.backgroundColor || "transparent"; radius: card.lc(img.e.style, "") === "person" ? width / 2 : 0 }
                Image {
                    id: pic
                    anchors.fill: parent
                    source: img.e.url || ""
                    fillMode: card.lc(img.e.style, "") === "person" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
                // Person images are round.
                RoundedCorners {
                    visible: card.lc(img.e.style, "") === "person"
                    anchors.fill: parent
                    radius: width / 2
                    background: card.styleBg(img.parentStyle)
                }
                TapHandler {
                    enabled: !!img.e.selectAction
                    onTapped: card.run(img.e.selectAction)
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: img.e.altText || ""
            }
        }
    }
    Component {
        id: imageSet
        Flow {
            property var e: ({})
            property string parentStyle
            width: parent ? parent.width : 0
            spacing: 10
            Repeater {
                model: e.images || []
                Image {
                    required property var modelData
                    readonly property real side: card.imagePx[card.lc(parent.e.imageSize, "medium")] || 54
                    width: side; height: side
                    source: modelData.url || ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }
        }
    }
    Component {
        id: container
        Rectangle {
            id: cont
            property var e: ({})
            property string parentStyle
            readonly property string myStyle: card.lc(e.style, parentStyle)
            readonly property bool styled: !!e.style && myStyle !== parentStyle
            readonly property real pad: styled ? 16 : 0
            width: parent ? parent.width : 0
            height: Math.max(inner.height + 2 * pad, e.minHeight ? parseFloat(e.minHeight) : 0)
            color: styled ? card.styleBg(myStyle) : "transparent"
            Image {
                visible: !!cont.e.backgroundImage
                anchors.fill: parent
                source: cont.e.backgroundImage ? (typeof cont.e.backgroundImage === "string" ? cont.e.backgroundImage : cont.e.backgroundImage.url) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            ElementList {
                id: inner
                x: cont.pad; width: cont.width - 2 * cont.pad
                y: card.lc(cont.e.verticalContentAlignment, "top") === "center" ? (cont.height - height) / 2 : card.lc(cont.e.verticalContentAlignment, "top") === "bottom" ? cont.height - height - cont.pad : cont.pad
                items: cont.e.items || []
                parentStyle: cont.myStyle
            }
            TapHandler { enabled: !!cont.e.selectAction; onTapped: card.run(cont.e.selectAction) }
        }
    }
    Component {
        id: columnSet
        Rectangle {
            id: cs
            property var e: ({})
            property string parentStyle
            readonly property string myStyle: card.lc(e.style, parentStyle)
            readonly property bool styled: !!e.style && myStyle !== parentStyle
            readonly property real pad: styled ? 16 : 0
            readonly property var cols: (e.columns || []).filter(c => card.shown(c))
            // Widths: px, auto (its content), weighted / stretch share the rest.
            readonly property real inner: width - 2 * pad
            readonly property real gaps: { let g = 0; for (let i = 1; i < cols.length; i++) g += card.spacingOf(cols[i]); return g }
            property var autoWidths: ({})
            readonly property var widths: {
                let fixed = 0, weights = 0
                const out = cols.map((c, i) => {
                    const w = c.width === undefined ? "stretch" : String(c.width).toLowerCase()
                    if (/px$/.test(w)) { const v = parseFloat(w); fixed += v; return { px: v } }
                    if (w === "auto") { const v = autoWidths[i] || 0; fixed += v; return { px: v } }
                    const wt = w === "stretch" ? 1 : (parseFloat(w) || 1); weights += wt; return { wt: wt }
                })
                const rest = Math.max(0, inner - gaps - fixed)
                return out.map(o => o.px !== undefined ? o.px : rest * o.wt / Math.max(weights, 1))
            }
            width: parent ? parent.width : 0
            height: row.height + 2 * pad
            color: styled ? card.styleBg(myStyle) : "transparent"
            Row {
                id: row
                x: cs.pad; y: cs.pad
                Repeater {
                    model: cs.cols
                    Row {
                        id: colSlot
                        required property var modelData
                        required property int index
                        Item {
                            visible: colSlot.index > 0
                            width: card.spacingOf(colSlot.modelData); height: colBox.height
                            Rectangle { visible: colSlot.modelData.separator === true; x: parent.width / 2; width: 0.67; height: parent.height; color: theme.stroke }
                        }
                        Rectangle {
                            id: colBox
                            readonly property string colStyle: card.lc(colSlot.modelData.style, cs.myStyle)
                            readonly property bool colStyled: !!colSlot.modelData.style && colStyle !== cs.myStyle
                            readonly property real cpad: colStyled ? 16 : 0
                            width: cs.widths[colSlot.index] || 0
                            height: colItems.height + 2 * cpad
                            color: colStyled ? card.styleBg(colStyle) : "transparent"
                            ElementList {
                                id: colItems
                                x: colBox.cpad; width: Math.max(0, colBox.width - 2 * colBox.cpad)
                                y: card.lc(colSlot.modelData.verticalContentAlignment, "top") === "center" ? (colBox.height - height) / 2 : card.lc(colSlot.modelData.verticalContentAlignment, "top") === "bottom" ? colBox.height - height - colBox.cpad : colBox.cpad
                                items: colSlot.modelData.items || []
                                parentStyle: colBox.colStyle
                            }
                            // Auto columns take their content's natural width.
                            readonly property real natural: card.naturalWidth(colSlot.modelData.items || [])
                            Component.onCompleted: cs.noteAuto(colSlot.index, natural)
                            onNaturalChanged: cs.noteAuto(colSlot.index, natural)
                            TapHandler { enabled: !!colSlot.modelData.selectAction; onTapped: card.run(colSlot.modelData.selectAction) }
                        }
                    }
                }
            }
            function noteAuto(i, w) { if (autoWidths[i] === w) return; const o = Object.assign({}, autoWidths); o[i] = w; autoWidths = o }
            TapHandler { enabled: !!cs.e.selectAction; onTapped: card.run(cs.e.selectAction) }
        }
    }
    Component {
        id: factSet
        Item {
            id: fs
            property var e: ({})
            property string parentStyle
            readonly property var facts: e.facts || []
            // Titles take their widest one (Teams' fact table), at most half.
            readonly property real titleW: Math.min(Math.ceil(facts.reduce((w, f) => Math.max(w, fmBold.advanceWidth(String(f.title || ""))), 0)) + 2, fs.width * 0.5)
            width: parent ? parent.width : 0
            height: col.height
            Column {
                id: col
                spacing: 6
                Repeater {
                    model: fs.facts
                    Row {
                        required property var modelData
                        spacing: 16
                        Text {
                            width: fs.titleW; wrapMode: Text.Wrap
                            text: card.markdown(modelData.title); textFormat: Text.RichText
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                        }
                        Text {
                            width: fs.width - fs.titleW - 16; wrapMode: Text.Wrap
                            text: card.markdown(modelData.value); textFormat: Text.RichText
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            linkColor: theme.brandForeground1
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
    }
    Component {
        id: actionSet
        ActionRow {
            property var e: ({})
            property string parentStyle
            width: parent ? parent.width : 0
            actions: e.actions || []
        }
    }
    // Tables (measured): a 0.67 px NeutralStroke2 frame, rows split by the
    // same line, cells padded 8; the header row bold.
    Component {
        id: table
        Rectangle {
            id: tbl
            property var e: ({})
            property string parentStyle
            readonly property var cols: e.columns || []
            readonly property bool grid: e.showGridLines !== false
            readonly property real inner: width - 1.33
            readonly property real total: cols.reduce((n, c) => n + (c.width && /px$/.test(String(c.width)) ? 0 : (parseFloat(c.width) || 1)), 0)
            readonly property real fixedPx: cols.reduce((n, c) => n + (c.width && /px$/.test(String(c.width)) ? parseFloat(c.width) : 0), 0)
            function colW(i) { const c = cols[i] || {}; if (c.width && /px$/.test(String(c.width))) return parseFloat(c.width); return (inner - fixedPx) * (parseFloat(c.width) || 1) / Math.max(total, 1) }
            width: parent ? parent.width : 0
            height: rowsCol.height + 1.33
            color: "transparent"
            border.color: grid ? theme.divider : "transparent"; border.width: 0.67
            Column {
                id: rowsCol
                x: 0.67; y: 0.67
                Repeater {
                    model: tbl.e.rows || []
                    Item {
                        id: trow
                        required property var modelData
                        required property int index
                        readonly property bool header: tbl.e.firstRowAsHeader !== false && index === 0
                        width: tbl.inner; height: cellsRow.height + (index > 0 && tbl.grid ? 0.67 : 0)
                        Rectangle { visible: trow.index > 0 && tbl.grid; width: parent.width; height: 0.67; color: theme.divider }
                        Row {
                            id: cellsRow
                            y: trow.index > 0 && tbl.grid ? 0.67 : 0
                            Repeater {
                                model: trow.modelData.cells || []
                                Item {
                                    required property var modelData
                                    required property int index
                                    width: tbl.colW(index); height: Math.max(cellItems.height + 16, 36)
                                    ElementList {
                                        id: cellItems
                                        x: 8; y: 8; width: parent.width - 16
                                        items: (parent.modelData.items || []).map(i => trow.header && card.lc(i.type, "") === "textblock" && !i.weight ? Object.assign({}, i, { weight: "Bolder" }) : i)
                                        parentStyle: tbl.parentStyle
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // Fluent inputs as Teams' card host draws them (measured): the label
    // 14/20 then 4; 32 tall (90 multiline), a 0.67 px NeutralStroke1 border
    // with a NeutralStrokeAccessible bottom, radius 4, text 12 in.
    Component {
        id: textInput
        Column {
            id: ti
            property var e: ({})
            property string parentStyle
            readonly property string kind: card.lc(e.type, "")
            width: parent ? parent.width : 0
            spacing: 4
            Text { visible: !!ti.e.label; text: (ti.e.label || "") + (ti.e.isRequired ? " *" : ""); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Rectangle {
                width: ti.width; height: ti.e.isMultiline ? 90 : 32; radius: 4
                color: theme.surface
                border.color: field.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: field.activeFocus ? 2 : 0.67; color: field.activeFocus ? theme.brand : theme.textSecondary }
                TextEdit {
                    id: field
                    x: 12; y: ti.e.isMultiline ? 6.7 : (parent.height - contentHeight) / 2
                    width: parent.width - 24 - (ti.kind === "input.date" || ti.kind === "input.time" ? 28 : 0)
                    height: ti.e.isMultiline ? parent.height - 14 : contentHeight
                    wrapMode: ti.e.isMultiline ? TextEdit.Wrap : TextEdit.NoWrap
                    clip: true
                    text: ti.e.value !== undefined ? String(ti.e.value) : ""
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onTextChanged: card.setValue(ti.e.id, text)
                    Text {
                        visible: !field.text
                        text: ti.e.placeholder || (ti.kind === "input.date" ? "Select a date..." : ti.kind === "input.time" ? "Select a time..." : "")
                        font: field.font; color: theme.textSecondary
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: ti.e.label || ti.e.placeholder || ""
                }
                FluentIcon {
                    visible: ti.kind === "input.date" || ti.kind === "input.time"
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    name: ti.kind === "input.date" ? "calendar-ltr-20" : "clock-20"; size: 20; color: theme.textStrong
                }
            }
        }
    }
    // Fluent checkbox / radio rows: 32 tall, the 16 px indicator 8 in, the
    // label at 36 in NeutralForeground3 (measured).
    Component {
        id: toggleInput
        Item {
            id: tg
            property var e: ({})
            property string parentStyle
            property bool on: e.value !== undefined ? String(e.value) === String(e.valueOn === undefined ? "true" : e.valueOn) : false
            width: parent ? parent.width : 0
            height: 32
            Rectangle {
                x: 8; y: 8; width: 16; height: 16; radius: 2
                color: tg.on ? theme.brand : theme.surface
                border.color: tg.on ? theme.brand : theme.textSecondary; border.width: 0.67
                FluentIcon { visible: tg.on; anchors.centerIn: parent; name: "checkmark-12-filled"; size: 12; color: "white" }
            }
            Text { x: 36; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; text: tg.e.title || ""; font.family: theme.font; font.pixelSize: 14; color: tg.on ? theme.text : theme.textSecondary; wrapMode: Text.Wrap }
            TapHandler { onTapped: { tg.on = !tg.on; card.setValue(tg.e.id, tg.on ? (tg.e.valueOn === undefined ? "true" : tg.e.valueOn) : (tg.e.valueOff === undefined ? "false" : tg.e.valueOff)) } }
            Accessible.role: Accessible.CheckBox
            Accessible.checked: on
            Accessible.name: e.title || ""
        }
    }
    Component {
        id: choiceInput
        Column {
            id: ch
            property var e: ({})
            property string parentStyle
            property var picked: e.value !== undefined ? String(e.value).split(",").filter(v => v) : []
            width: parent ? parent.width : 0
            spacing: 6
            readonly property bool compact: card.lc(ch.e.style, "compact") !== "expanded" && !ch.e.isMultiSelect
            Text { visible: !!ch.e.label; text: ch.e.label || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            // Compact: a Fluent dropdown.
            Rectangle {
                id: drop
                visible: ch.compact
                width: ch.width; height: 32; radius: 4
                color: theme.surface
                border.color: theme.stroke; border.width: 0.67
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 0.67; color: theme.textSecondary }
                readonly property var current: (ch.e.choices || []).find(c => String(c.value) === ch.picked[0])
                Text {
                    x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; elide: Text.ElideRight
                    text: drop.current ? drop.current.title : (ch.e.placeholder || "")
                    font.family: theme.font; font.pixelSize: 14; color: drop.current ? theme.text : theme.textSecondary
                }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textStrong }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { choiceMenu.width = drop.width; choiceMenu.open() } }
                MenuPopup {
                    id: choiceMenu
                    y: drop.height + 2
                    items: (ch.e.choices || []).map(c => ({ label: c.title || "" }))
                    onPicked: i => { const v = String(ch.e.choices[i].value); ch.picked = [v]; card.setValue(ch.e.id, v) }
                }
                Accessible.role: Accessible.ComboBox
                Accessible.name: ch.e.label || ch.e.placeholder || ""
            }
            Column {
                spacing: 8
                Repeater {
                    model: ch.compact ? [] : (ch.e.choices || [])
                    Item {
                        id: opt
                        required property var modelData
                        readonly property bool on: ch.picked.indexOf(String(modelData.value)) >= 0
                        width: ch.width; height: 32
                        Rectangle {
                            x: 8; y: 8; width: 16; height: 16
                            radius: ch.e.isMultiSelect ? 2 : 8
                            color: opt.on && ch.e.isMultiSelect ? theme.brand : theme.surface
                            border.color: opt.on ? theme.brand : theme.textSecondary; border.width: 0.67
                            Rectangle { visible: opt.on && !ch.e.isMultiSelect; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
                            FluentIcon { visible: opt.on && !!ch.e.isMultiSelect; anchors.centerIn: parent; name: "checkmark-12-filled"; size: 12; color: "white" }
                        }
                        Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: opt.modelData.title || ""; font.family: theme.font; font.pixelSize: 14; color: opt.on ? theme.text : theme.textSecondary }
                        TapHandler {
                            onTapped: {
                                const v = String(opt.modelData.value)
                                let p = ch.picked.slice()
                                if (ch.e.isMultiSelect) p = p.indexOf(v) >= 0 ? p.filter(x => x !== v) : p.concat([v])
                                else p = [v]
                                ch.picked = p
                                card.setValue(ch.e.id, p.join(","))
                            }
                        }
                        Accessible.role: ch.e.isMultiSelect ? Accessible.CheckBox : Accessible.RadioButton
                        Accessible.checked: on
                        Accessible.name: modelData.title || ""
                    }
                }
            }
        }
    }

    // A row of action buttons (Fluent secondary buttons, 8 apart).
    component ActionRow: Flow {
        id: ar
        property var actions: []
        spacing: 8
        Repeater {
            model: ar.actions
            Rectangle {
                id: btn
                required property var modelData
                readonly property bool expanded: card.lc(modelData.type, "") === "action.showcard" && card.openShowCard === (modelData.id || modelData.title)
                width: Math.min(ar.width, label.implicitWidth + 24 + 1.33); height: 31.3; radius: 4
                color: expanded ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : btnHover.hovered ? theme.menuHover : theme.surface
                border.color: expanded ? "transparent" : theme.stroke; border.width: 0.67
                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, ar.width - 24)
                    elide: Text.ElideRight
                    text: btn.modelData.title || ""
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: btn.expanded ? "white" : theme.text
                }
                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.run(btn.modelData) }
                ToolTip {
                    visible: btnHover.hovered && card.lc(btn.modelData.type, "") === "action.openurl"; delay: 500
                    y: -height - 4; padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: (btn.modelData.title || "") + "\nThis is a card action with a link"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.title || ""
                Accessible.description: card.lc(modelData.type, "") === "action.openurl" ? "This is a card action with a link" : ""
            }
        }
    }
}
