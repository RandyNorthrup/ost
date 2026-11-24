import QtQuick
import QtQuick.Controls.Basic

// The right column's panes of Outlook's event form, in Tracking's place
// (Teams desktop on winpc, 2026-11-24, CSS px): a white card 351 wide
// (radius 8, Fluent's depth-2 shadow), the title 16/500 (32 tall) at 20,
// 10 and Close (32 x 32) 10 from the right.
// - "Graphics" (the body's Insert emoji, images and stickers): four tabs
//   74 x 52 at 20, 64.67, 79 apart (All, Emoji, Stock images, Stickers;
//   24 px glyphs, a brand bar under the picked one); "Find something fun"
//   (311 x 32 at 20, 128.67, a 0.67 #D1D1D1 edge, radius 4, the 14 px
//   search glyph 8.67 in); All: "Emoji" and "Stock images" 14 px headings
//   with "View more" (brand) at the right, twelve emoji (28 px in 40 x 40
//   cells, 42.14 apart, seven a row) and four stock pictures (141.5 x 98
//   in two columns); Emoji: the categories and their emoji; Stock images
//   and Stickers: Microsoft's content service's pictures. A pick goes in
//   the body at the cursor (an emoji as text, a picture inline).
// - "Accessibility checker" (Check for accessibility issues): Outlook's
//   three checks of the body (inline images without alt text, tables
//   without a header row, text whose colour contrast is too low), each an
//   issue with its explanation (and Add alt text / Add header row), then
//   "No issues were found" (17/300) and "Your content passes all checks for
//   accessibility issues." (12) or "Some issues were found" and "Fix the
//   issues listed above, then check for accessibility issues again.", and
//   Check again (102.28 x 31.33).
FluentSurface {
    id: pane
    /// "graphics" or "accessibility".
    property string mode: "graphics"
    /// The event form (MeetingForm): its body and its requests.
    property var form: null
    property Item editor: null
    signal closed()
    depth: 2; radius: 8; color: theme.surface
    width: 351; height: 510

    Text {
        x: 20; y: 10; height: 32; verticalAlignment: Text.AlignVCenter
        text: pane.mode === "graphics" ? qsTr("Graphics") : qsTr("Accessibility checker")
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Medium; color: theme.textSecondary
        Accessible.role: Accessible.Heading
    }
    Rectangle {
        x: pane.width - 10 - 32; y: 10; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pane.closed() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }

    // ── Graphics ────────────────────────────────────────────────────
    property int tab: 0
    property string query: ""
    /// The content service's answers by "<pivot>|<search>".
    property var found: ({})
    property var pending: ({})
    function ask(pivot, top) {
        const key = pivot + "|" + query
        if (found[key] || pending[key] || !form) return
        const p = Object.assign({}, pending); p[key] = true; pending = p
        form.calendarCall("graphics", { pivot: pivot, search: query, top: top, key: key })
    }
    function answer(r, error) {
        const key = (r && r.key) || ""
        const p = Object.assign({}, pending); delete p[key]; pending = p
        if (error || !key) return
        const f = Object.assign({}, found); f[key] = r.items || []; found = f
    }
    function items(pivot) { return found[pivot + "|" + query] || [] }
    onTabChanged: if (mode === "graphics") { if (tab === 0 || tab === 2) ask("Stock Images", tab === 0 ? 4 : 30); if (tab === 3) ask("Stickers", 30) }
    onQueryChanged: queryTimer.restart()
    Timer { id: queryTimer; interval: 350; onTriggered: pane.tabChanged() }
    onVisibleChanged: if (visible && mode === "graphics") tabChanged()
    onModeChanged: if (visible && mode === "graphics") tabChanged()
    // The emoji as the compose box's picker lists them (its categories).
    EmojiPicker { id: emojiData; visible: false }
    readonly property var featured: ["🙂", "😂", "❤️", "🎉", "😯", "🐶", "😺", "👍", "👐", "✅", "✈️", "🍕"]
    function emojiMatches() {
        const q = query.trim().toLowerCase()
        const all = []
        for (const c of emojiData.categories) for (const e of c.items) if (!q || e[1].indexOf(q) >= 0) all.push(e[0])
        return all
    }
    /// The size a pick goes in at (its own, fitted: a sticker 120 wide,
    /// a picture 400), by its address.
    property var sizes: ({})
    function pickPicture(it) {
        if (!form) return
        const max = tab === 3 ? 120 : 400, w = it.width || max, h = it.height || max, k = Math.min(1, max / w)
        const m = Object.assign({}, sizes); m[it.url] = [Math.round(w * k), Math.round(h * k)]; sizes = m
        form.calendarCall("graphicsFile", { url: it.url })
    }

    Item {
        visible: pane.mode === "graphics"
        anchors.fill: parent
        Repeater {
            model: [["image-20", qsTr("All")], ["emoji-20", qsTr("Emoji")], ["briefcase-20", qsTr("Stock images")], ["sticker-20", qsTr("Stickers")]]
            Item {
                id: gtab
                required property var modelData
                required property int index
                x: 20 + index * 79; y: 64.67; width: 74; height: 52
                FluentIcon { x: 25; y: 12; name: gtab.modelData[0]; size: 24; color: pane.tab === gtab.index ? theme.text : theme.textStrong }
                Rectangle { visible: pane.tab === gtab.index; x: 17; y: 46; width: 40; height: 3; radius: 1.5; color: theme.brand }
                HoverHandler { id: gtabHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.tab = gtab.index }
                ToolTip.visible: gtabHover.hovered
                ToolTip.text: gtab.modelData[1]
                Accessible.role: Accessible.PageTab
                Accessible.name: gtab.modelData[1]
                Accessible.selected: pane.tab === gtab.index
            }
        }
        Rectangle {
            x: 20; y: 128.67; width: 311; height: 32; radius: 4
            color: theme.surface; border.width: 0.67; border.color: findInput.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 8.67; y: 9; name: "search-16"; size: 14; color: theme.textSecondary }
            TextInput {
                id: findInput
                x: 22.67; width: 287.67; height: 30.67; y: 0.67
                verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                onTextChanged: pane.query = text
                Accessible.name: qsTr("Find something fun")
                Text { visible: !findInput.text; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Find something fun"); font: findInput.font; color: theme.textSecondary }
            }
        }
        Flickable {
            x: 20; y: 172.67; width: 321; height: pane.height - y - 10
            clip: true; contentHeight: gCol.height + 12
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Column {
                id: gCol
                width: 311; spacing: 0
                // All: Emoji and Stock images, each with View more.
                Item {
                    visible: pane.tab === 0
                    width: 311; height: visible ? 32 : 0
                    Text { x: 5; y: 13; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Emoji"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { anchors.right: parent.right; anchors.rightMargin: 0; y: 13.67; height: 18.67; verticalAlignment: Text.AlignVCenter; text: qsTr("View more"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                           TapHandler { onTapped: pane.tab = 1 } HoverHandler { cursorShape: Qt.PointingHandCursor } }
                }
                Flow {
                    visible: pane.tab === 0 || pane.tab === 1
                    width: 311; spacing: 2; topPadding: pane.tab === 0 ? 13 : 4
                    Repeater {
                        model: pane.tab === 0 ? (pane.query ? pane.emojiMatches().slice(0, 12) : pane.featured) : pane.tab === 1 ? pane.emojiMatches() : []
                        Rectangle {
                            id: ecell
                            required property string modelData
                            width: 40.14; height: 40; radius: 4
                            color: ecellHover.hovered ? theme.rowHover : "transparent"
                            Text { anchors.centerIn: parent; text: ecell.modelData; font.family: theme.font; font.pixelSize: 28 }
                            HoverHandler { id: ecellHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: if (pane.form) pane.form.insertEmoji(ecell.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: ecell.modelData
                        }
                    }
                }
                Item {
                    visible: pane.tab === 0
                    width: 311; height: visible ? 44 : 0
                    Text { x: 5; y: 20; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Stock images"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { anchors.right: parent.right; y: 20.67; height: 18.67; verticalAlignment: Text.AlignVCenter; text: qsTr("View more"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                           TapHandler { onTapped: pane.tab = 2 } HoverHandler { cursorShape: Qt.PointingHandCursor } }
                }
                Flow {
                    visible: pane.tab === 0 || pane.tab === 2 || pane.tab === 3
                    width: 311; spacing: 4; topPadding: 12
                    Repeater {
                        model: pane.tab === 3 ? pane.items("Stickers") : pane.tab === 0 ? pane.items("Stock Images").slice(0, 4) : pane.tab === 2 ? pane.items("Stock Images") : []
                        Rectangle {
                            id: pcell
                            required property var modelData
                            readonly property bool sticker: pane.tab === 3
                            width: sticker ? 101 : 141.5; height: sticker ? 101 : 98.15; radius: 4
                            color: pcellHover.hovered ? theme.rowHover : "transparent"
                            clip: true
                            Image {
                                anchors.fill: parent; anchors.margins: pcell.sticker ? 8 : 0
                                source: pcell.modelData.thumb; asynchronous: true
                                fillMode: pcell.sticker ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                            }
                            HoverHandler { id: pcellHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: pane.pickPicture(pcell.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: pcell.modelData.description
                        }
                    }
                }
            }
        }
    }

    // ── Accessibility checker ───────────────────────────────────────
    /// The issues found: 0 images without alt text, 1 tables without a
    /// header row, 2 text contrast too low.
    property var errors: []
    function contrast(a, b) {
        const lum = c => {
            const ch = [c.r, c.g, c.b].map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))
            return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
        }
        const l1 = lum(a), l2 = lum(b)
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
    }
    function check() {
        if (!form) return
        const html = form.bodyHtml()
        const out = []
        // Inline images must have alt text (not decorative ones).
        const imgs = html.match(/<img\b[^>]*>/gi) || []
        if (imgs.some(t => !/role\s*=\s*"presentation"/i.test(t) && !/\balt\s*=\s*"[^"]+"/i.test(t))) out.push(0)
        // Tables must use header rows.
        const tables = html.match(/<table\b[\s\S]*?<\/table>/gi) || []
        if (tables.some(t => !/<th\b/i.test(t))) out.push(1)
        // Text color contrast is too low (4.5:1 under 14 pt bold / 18 pt, 3:1 above).
        const spans = html.match(/<span\b[^>]*style="[^"]*"[^>]*>/gi) || []
        const low = spans.some(s => {
            const c = /(?:^|[\s;"])color:\s*(#[0-9a-f]{6})/i.exec(s)
            if (!c) return false
            const bg = /background-color:\s*(#[0-9a-f]{6})/i.exec(s)
            const size = /font-size:\s*(\d+)(pt|px)/i.exec(s)
            const pt = size ? (size[2] === "px" ? 0.75 * +size[1] : +size[1]) : 12
            const bold = /font-weight:\s*(600|700|800|900|bold)/i.test(s)
            const need = (bold ? pt >= 14 : pt >= 18) ? 3 : 4.5
            return pane.contrast(Qt.color(c[1]), Qt.color(bg ? bg[1] : "#ffffff")) < need
        })
        if (low) out.push(2)
        errors = out
    }
    Flickable {
        visible: pane.mode === "accessibility"
        x: 20; y: 64.67; width: 311; height: pane.height - y - 10
        clip: true; contentHeight: accCol.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: accCol
            width: 311; spacing: 0
            Repeater {
                model: [[qsTr("Inline images must have alt text"), qsTr("Alt text is used by screen readers to describe inline images to people who can't see the screen. Good alt text helps visually impaired people understand the information shown in inline images."), qsTr("Add alt text")],
                        [qsTr("Tables must use header rows"), qsTr("Header rows are used by screen readers to describe the information inside a table to people who can't see the screen. Header rows help visually impaired people understand which column a cell belongs to."), qsTr("Add header row")],
                        [qsTr("Text color contrast is too low"), qsTr("Text becomes difficult to read when its color is too similar to the color behind it. Increasing contrast makes text easier to read, especially when viewing documents in bright light. You can increase the contrast by changing the color of the font or by changing the color behind it."), ""]]
                Column {
                    id: issue
                    required property var modelData
                    required property int index
                    visible: pane.errors.indexOf(index) >= 0
                    width: 311; spacing: 4
                    bottomPadding: 16
                    Text { width: 311; wrapMode: Text.Wrap; text: issue.modelData[0]; font.family: theme.font; font.pixelSize: 17; font.weight: Font.Light; color: theme.textSecondary; lineHeight: 32.67; lineHeightMode: Text.FixedHeight }
                    Text { width: 311; wrapMode: Text.Wrap; text: issue.modelData[1]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary; lineHeight: 16; lineHeightMode: Text.FixedHeight }
                    Item { width: 1; height: 4 }
                    Rectangle {
                        visible: !!issue.modelData[2]
                        width: fixText.implicitWidth + 24; height: 31.33; radius: 4
                        color: fixHover.hovered ? theme.rowHover : theme.surface; border.width: 0.67; border.color: theme.stroke
                        Text { id: fixText; anchors.centerIn: parent; text: issue.modelData[2]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        HoverHandler { id: fixHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: issue.index === 0 ? altDialog.open() : pane.addHeaderRow() }
                        Accessible.role: Accessible.Button
                        Accessible.name: issue.modelData[2]
                    }
                    Rectangle { width: 311; height: 1; color: theme.dividerSoft }
                }
            }
            Text {
                width: 311; wrapMode: Text.Wrap
                text: pane.errors.length ? qsTr("Some issues were found") : qsTr("No issues were found")
                font.family: theme.font; font.pixelSize: 17; font.weight: Font.Light; color: theme.textSecondary
                topPadding: 4; lineHeight: 32.67; lineHeightMode: Text.FixedHeight
            }
            Text {
                width: 311; wrapMode: Text.Wrap
                text: pane.errors.length ? qsTr("Fix the issues listed above, then check for accessibility issues again.") : qsTr("Your content passes all checks for accessibility issues.")
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                height: Math.max(26, implicitHeight); verticalAlignment: Text.AlignTop; topPadding: 4
            }
            Item { width: 1; height: 4 }
            Rectangle {
                width: 102.28; height: 31.33; radius: 4
                color: againHover.hovered ? theme.rowHover : theme.surface; border.width: 0.67; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: qsTr("Check again"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: againHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.check() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Check again")
            }
        }
    }
    /// Add header row: the first row of each table without one becomes its
    /// header.
    function addHeaderRow() {
        if (!form || !editor) return
        let html = form.bodyHtml()
        html = html.replace(/<table\b[\s\S]*?<\/table>/gi, t => /<th\b/i.test(t) ? t : t.replace(/<tr\b([^>]*)>([\s\S]*?)<\/tr>/i, (all, attrs, cells) => "<tr" + attrs + ">" + cells.replace(/<td\b/gi, "<th").replace(/<\/td>/gi, "</th>") + "</tr>"))
        form.setBody(html); form.markDirty(); check()
    }
    // Add alt text: the description for the pictures that have none.
    Popup {
        id: altDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        onOpened: { altInput.text = ""; altInput.forceActiveFocus() }
        contentItem: Column {
            spacing: 12
            Text { text: qsTr("Alt text"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { width: 432; wrapMode: Text.Wrap; text: qsTr("Inline images must have alt text"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            Rectangle {
                width: 432; height: 32; radius: 4; color: theme.surface; border.width: 0.67; border.color: altInput.activeFocus ? theme.brand : theme.stroke
                TextInput { id: altInput; x: 10; width: 412; height: 32; verticalAlignment: TextInput.AlignVCenter; clip: true; font.family: theme.font; font.pixelSize: 14; color: theme.text; Accessible.name: qsTr("Alt text") }
            }
            Row {
                anchors.right: parent.right; spacing: 8
                Rectangle {
                    width: 96; height: 32; radius: 4; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                    TapHandler {
                        onTapped: {
                            const alt = altInput.text.trim().replace(/"/g, "&quot;")
                            if (alt && pane.form) {
                                const html = pane.form.bodyHtml().replace(/<img\b(?![^>]*\balt\s*=\s*"[^"]+")([^>]*)>/gi, (all, rest) => "<img alt=\"" + alt + "\"" + rest.replace(/\balt\s*=\s*""/i, "") + ">")
                                pane.form.setBody(html); pane.form.markDirty(); pane.check()
                            }
                            altDialog.close()
                        }
                    }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Save")
                }
                Rectangle {
                    width: 96; height: 32; radius: 4; color: theme.surface; border.width: 0.67; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    TapHandler { onTapped: altDialog.close() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
                }
            }
        }
    }
}
