import QtQuick

// A channel post's or reply's content as Teams' posts list draws it: the
// text, and its pictures where they were written (Teams 26304's message
// body; measured on winpc 2026-11-22 with "OST TEST 246 image post", an
// 800 x 450 picture between two runs of text):
// - a picture sits in its own line, 2 px around it (the lazy-image
//   wrapper's margin), rounded 6 with a 0.67 #F0F0F0 edge, drawn
//   "contain"; its size by Teams' image kinds (async-entry 537457 / 78926:
//   180 = 18rem, 2 = 812 / 406):
//   - standard (at least 180 tall, less than twice as wide as tall or
//     tall): 180 tall at its own ratio;
//   - ultra-wide / thin (twice as wide as tall; thin under 180 tall): its
//     own size unless wider than 620 or taller than 480, then scaled to
//     fit both (--calculatedWideImageWidth), at most 180 tall;
//   - super-small (under 180 tall): its own size;
//   - none wider than the text;
// - a GIF or sticker: as the chat draws it (its own size, up to 404 wide);
// - a Loop link unfurled in place: Loop's card (as an agent's answer);
// - quotes and code blocks: the chat's boxes.
// Clicking a picture opens Teams' viewer (ImageLightbox) on the message's
// pictures. `picRanges` lists each picture's top and bottom (with its
// wrapper's margin) for "see more" (Teams' enableImageAwareSeeMoreTruncation:
// a cut through a picture moves to its bottom).
Column {
    id: root
    property var message: null
    property var mark: []
    signal openImage(var images, int index)
    readonly property var imgs: message ? (message.images || []).concat(message.media || []) : []
    readonly property var flow: message ? (message.flow || []) : []
    readonly property bool inFlow: flow.length > 0
    // The parts in order: {text} | {pic} | {loop} | {quote} | {code}.
    readonly property var parts: {
        const out = []
        if (!message) return out
        if (message.deleted) return [{ deleted: true }]
        // The text before the first picture (all of it without pictures).
        if ((message.html || "") !== "") out.push({ html: message.html, plain: "" })
        else if (!inFlow && imgs.length === 0 && (message.text || "") !== "") out.push({ html: "", plain: message.text })
        if (inFlow) {
            for (const p of flow) {
                if (p.pic !== undefined) out.push({ pic: imgs[p.pic], index: p.pic })
                else if (p.loop_url) out.push({ loop: p.loop_url })
                else if (p.quote !== undefined) out.push({ quote: p.quote })
                else if (p.code) out.push({ code: p.code })
                else if (p.html !== undefined && p.html !== "") out.push({ html: p.html })
            }
        } else {
            imgs.forEach((im, i) => out.push({ pic: im, index: i }))
        }
        return out
    }
    /// [[top, bottom]] of each picture, in the body's coordinates.
    readonly property var picRanges: {
        const out = []
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && it.isPic) out.push([it.y + 2, it.y + it.height])
        }
        return out
    }
    function picSize(p) {
        const w0 = p.width > 0 ? p.width : 240, h0 = p.height > 0 ? p.height : 160
        const maxW = Math.max(1, root.width - 4)
        let w = w0, h = h0
        if (p.kind) {
            // A GIF or sticker, as the chat draws it.
            w = Math.min(404, maxW, w0); h = Math.floor(w * h0 / w0)
            return [w, h]
        }
        const small = h0 < 180
        if (w0 === 1 && h0 === 1) { w = 1; h = 1 }
        else if (h0 / w0 >= 2 || (!small && w0 / h0 < 2)) { h = 180; w = 180 * w0 / h0 }
        else if (w0 / h0 >= 2) {
            const b = w0 / 10, y = h0 / 10
            if (b > 62 || y > 48) { const s = Math.min(62 / b, 18 / y); w = Math.round(b * s * 100) / 10; h = w * h0 / w0 }
            if (h > 180) { h = 180; w = 180 * w0 / h0 }
        }
        if (w > maxW) { h = h * maxW / w; w = maxW }
        return [w, h]
    }

    Repeater {
        id: rep
        model: root.parts
        Item {
            id: part
            required property var modelData
            required property int index
            readonly property bool isPic: modelData.pic !== undefined
            readonly property var size: isPic ? root.picSize(modelData.pic || {}) : [0, 0]
            width: root.width
            height: modelData.deleted ? delText.height
                : isPic ? size[1] + 4
                : modelData.loop !== undefined ? 9 + 372 + 7
                : modelData.quote !== undefined ? 7 + quoteLoader.height + 7
                : modelData.code !== undefined ? (codeLoader.item ? codeLoader.item.height + 6 : 0)
                // Teams draws each line 20 tall (the last one too).
                : Math.max(txt.height, txt.lineCount * 20)
            MessageText {
                id: delText
                visible: !!part.modelData.deleted
                width: parent.width
                message: part.modelData.deleted ? root.message : null
            }
            MessageText {
                id: txt
                visible: part.modelData.html !== undefined
                width: parent.width
                message: part.modelData.html !== undefined ? ({ html: part.modelData.html || "", text: part.modelData.plain || "" }) : null
                mark: root.mark
            }
            Item {
                id: picBox
                visible: part.isPic
                x: 2; y: 2
                width: part.size[0]; height: part.size[1]
                readonly property var p: part.isPic ? part.modelData.pic || {} : ({})
                Image {
                    visible: !picBox.p.kind
                    anchors.fill: parent
                    source: picBox.p.kind ? "" : (picBox.p.local_path || "")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                AnimatedImage {
                    visible: !!picBox.p.kind
                    anchors.fill: parent
                    source: picBox.p.kind ? picBox.p.url : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    playing: false
                }
                RoundedCorners { anchors.fill: parent; radius: 6; background: theme.surface }
                Rectangle { anchors.fill: parent; color: "transparent"; radius: 6; border.width: 0.67; border.color: theme.pick("#F0F0F0", "#333333", "#FFFFFF") }
                HoverHandler { enabled: part.isPic && !picBox.p.kind; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: part.isPic && !picBox.p.kind
                    onTapped: {
                        const list = root.imgs.filter(x => !x.kind)
                        root.openImage(list, Math.max(0, list.indexOf(picBox.p)))
                    }
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: picBox.p.kind ? (picBox.p.alt || "") : qsTr("Image")
            }
            Loader {
                active: part.modelData.loop !== undefined
                y: 9
                width: parent.width
                sourceComponent: LoopCard {
                    id: postLoop
                    mode: "embed"
                    width: part.width
                    componentUrl: String(part.modelData.loop || "")
                    onPinRequested: backend.setMessagePinned(root.message.id, true)
                    Component.onCompleted: backend.loopHostRequest("pageName", "postloop:" + root.message.id + ":" + part.index, JSON.stringify({ url: componentUrl }))
                    Connections {
                        target: backend
                        function onLoopHostReply(id, json) {
                            if (id !== "postloop:" + root.message.id + ":" + part.index) return
                            let r = {}
                            try { r = JSON.parse(json) } catch (e) {}
                            if (r.name) postLoop.name = r.name
                        }
                    }
                }
            }
            Loader {
                id: quoteLoader
                active: part.modelData.quote !== undefined
                y: 7
                sourceComponent: Rectangle {
                    width: Math.min(part.width, quoteText.implicitWidth + 31.3)
                    height: quoteText.contentHeight + 15.3
                    radius: 4
                    color: theme.surface
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    Rectangle { x: 3; y: 3; width: 2.67; height: parent.height - 6; radius: 1.5; color: theme.pick("#D1D1D1", "#666666", "#000000") }
                    MessageText {
                        id: quoteText
                        x: 15.7; y: 7.7
                        width: Math.min(part.width - 31.3, implicitWidth)
                        message: ({ html: part.modelData.quote || "", text: "" })
                    }
                }
            }
            Loader {
                id: codeLoader
                active: part.modelData.code !== undefined
                y: 6
                width: parent.width
                sourceComponent: CodeCard { width: part.width; height: implicitHeight; code: part.modelData.code || ({}) }
            }
        }
    }
}
