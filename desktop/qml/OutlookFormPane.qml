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
//   in two columns); Emoji: Outlook's category bar and the category's
//   emoji; Stock images: category tiles, then a search's pictures;
//   Stickers (below). A pick goes in the body at the cursor (an emoji as
//   text, a stock image at its own size up to 729 px, a sticker 100 x 100).
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
    // Outlook's content picker over Microsoft's content service
    // (event_form::graphics). Emoji: a bar of categories (32 px tabs 39.86
    // apart at 20, 160.67: Smilies, Hand gestures, People, Animals, Food,
    // Travel and places, Objects and "more options" with Activities and
    // Symbols; the picked one's icon filled in brand over a 20 x 2 brand
    // bar 30 down, a 0.67 #D1D1D1 line under the bar), the category's name
    // (14/600 #616161, 206.33 down) and its emoji (the content service's
    // answer for the name, Smilies' faces and Hand gestures' hands kept),
    // seven a row from 246.33. Stock images: the service's category tiles
    // (two columns 141.5 wide and 10 apart from 177.67, each row as tall as
    // its taller picture, the picture rounded 4 with Fluent's shadow under
    // a 50 % black veil and its name in white); a tile searches for its
    // name. A search: its pictures (50) in the same two columns. Stickers
    // (100): 72 px pictures in 91 x 75.33 cells 101 and 85.33 apart.
    // Nothing found: the illustration (186.59 x 186.95), "We didn't find
    // anything" and "Try a different keyword" (bold).
    property int tab: 0
    property string query: ""
    /// The Emoji tab's category.
    property string category: "Smilies"
    /// The content service's answers by "<pivot>|<search>|<category>".
    property var found: ({})
    property var pending: ({})
    property var themes: []
    property bool themesAsked: false
    function keyOf(pivot, search, cat) { return pivot + "|" + search + "|" + (cat || "") }
    function ask(pivot, search, top, cat) {
        const key = keyOf(pivot, search, cat)
        if (found[key] || pending[key] || !form) return
        const p = Object.assign({}, pending); p[key] = true; pending = p
        form.calendarCall("graphics", { pivot: pivot, search: search, top: top, category: cat || "", key: key })
    }
    function answer(r, error) {
        const key = (r && r.key) || ""
        const p = Object.assign({}, pending); delete p[key]; pending = p
        if (error || !key) return
        const f = Object.assign({}, found); f[key] = r.items || []; found = f
    }
    function themesAnswer(r, error) { if (!error) themes = r.themes || [] }
    function items(pivot, search, cat) { return found[keyOf(pivot, search, cat)] || [] }
    function loading(pivot, search, cat) { return !!pending[keyOf(pivot, search, cat)] }
    readonly property string q: query.trim()
    function refresh() {
        if (mode !== "graphics" || !visible) return
        if (tab === 0) { if (q) ask("Emojis", q, 12, ""); ask("Stock Images", q, 4, "") }
        else if (tab === 1) ask("Emojis", q || category, 200, q ? "" : category)
        else if (tab === 2) { if (q) ask("Stock Images", q, 50, ""); else if (!themesAsked && form) { themesAsked = true; form.calendarCall("graphicsThemes", { kind: "Stock Images" }) } }
        else if (tab === 3) ask("Stickers", q, 100, "")
    }
    onTabChanged: refresh()
    onCategoryChanged: refresh()
    onQueryChanged: queryTimer.restart()
    Timer { id: queryTimer; interval: 500; onTriggered: pane.refresh() }
    onVisibleChanged: refresh()
    onModeChanged: refresh()
    // All's first emoji (Outlook's initial twelve).
    readonly property var featured: [["🙂", qsTr("Slightly smiling face")], ["😂", qsTr("Face with tears of joy")], ["❤️", qsTr("Red heart")], ["🎉", qsTr("Party popper")],
                                     ["😯", qsTr("Hushed face")], ["🐶", qsTr("Dog face")], ["😺", qsTr("Grinning cat")], ["👍", qsTr("Thumbs up")],
                                     ["👐", qsTr("Open hands")], ["✅", qsTr("Check mark button")], ["✈️", qsTr("Airplane")], ["🍕", qsTr("Pizza")]]
    readonly property var categories: [["Smilies", qsTr("Smilies"), "emoji-20"], ["Hand gestures", qsTr("Hand gestures"), "hand-right-20"], ["People", qsTr("People"), "people-20"],
                                       ["Animals", qsTr("Animals"), "animal-dog-20"], ["Food", qsTr("Food"), "food-pizza-20"], ["Travel and places", qsTr("Travel and places"), "building-20"],
                                       ["Objects", qsTr("Objects"), "lightbulb-20"]]
    readonly property var moreCategories: [["Activities", qsTr("Activities"), "sport-soccer-20"], ["Symbols", qsTr("Symbols"), "number-symbol-square-20"]]
    function categoryLabel(c) { const all = categories.concat(moreCategories); const x = all.find(e => e[0] === c); return x ? x[1] : c }
    /// What the emoji grid shows: [glyph, description].
    readonly property var emojiShown: tab === 0 ? (q ? items("Emojis", q, "").slice(0, 12).map(e => [e.glyph, e.description]) : featured)
                                     : tab === 1 ? items("Emojis", q || category, q ? "" : category).map(e => [e.glyph, e.description]) : []
    /// A picked picture goes in the body (MeetingForm.insertStockImage).
    function pickPicture(it, sticker) {
        if (form) form.calendarCall("graphicsFile", { url: it.url, sticker: sticker, alt: it.description || "" })
    }
    /// Two columns of pictures, each row as tall as its taller picture
    /// (141.5 wide, by the picture's own shape).
    function rowsOf(list, aspect) {
        const out = []
        for (let i = 0; i < list.length; i += 2) {
            const a = list[i], b = list[i + 1]
            out.push({ a: a, b: b || null, h: Math.max(141.5 * aspect(a), b ? 141.5 * aspect(b) : 0) })
        }
        return out
    }

    Rectangle { visible: pane.mode === "graphics"; x: 0; y: 52; width: pane.width; height: 0.67; color: theme.pick("#DBDBDB", "#3D3D3D", "#FFFFFF") }
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
            color: theme.surface; border.width: 0.67; border.color: findInput.activeFocus ? theme.brand : findHover.hovered ? theme.textSecondary : theme.stroke
            HoverHandler { id: findHover }
            FluentIcon { x: 8.67; y: 9; name: "search-16"; size: 14; color: theme.textSecondary }
            TextInput {
                id: findInput
                x: 22.67; width: 287.67; height: 30.67; y: 0.67
                verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true; leftPadding: 6.67; rightPadding: 6.67
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                text: pane.query
                onTextEdited: pane.query = text
                Accessible.name: qsTr("Find something fun")
                Text { visible: !findInput.text; x: 6.67; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Find something fun"); font: findInput.font; color: theme.textSecondary }
            }
        }
        // Emoji's categories (while not searching).
        Item {
            id: catBar
            visible: pane.tab === 1 && !pane.q
            x: 20; y: 160.67; width: 311; height: 32.67
            Rectangle { y: 32; width: 311; height: 0.67; color: theme.stroke }
            Repeater {
                model: pane.categories
                Item {
                    id: ctab
                    required property var modelData
                    required property int index
                    readonly property bool picked: pane.category === modelData[0]
                    x: index * 39.857; width: 32; height: 32
                    Rectangle { anchors.fill: parent; radius: 4; color: ctabHover.hovered && !ctab.picked ? theme.rowHover : "transparent" }
                    FluentIcon { x: 6; y: 6; name: ctab.picked ? ctab.modelData[2] + "-filled" : ctab.modelData[2]; size: 20; color: ctab.picked ? theme.brand : theme.textStrong }
                    Rectangle { visible: ctab.picked; x: 6; y: 30; width: 20; height: 2; radius: 1; color: theme.brand }
                    HoverHandler { id: ctabHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pane.category = ctab.modelData[0] }
                    ToolTip.visible: ctabHover.hovered
                    ToolTip.text: ctab.modelData[1]
                    Accessible.role: Accessible.PageTab
                    Accessible.name: ctab.modelData[1]
                    Accessible.selected: ctab.picked
                }
            }
            Item {
                id: moreTab
                x: 279; width: 32; height: 32
                Rectangle { anchors.fill: parent; radius: 4; color: moreHover.hovered ? theme.rowHover : "transparent" }
                FluentIcon { x: 6; y: 6; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: moreMenu.open() }
                ToolTip.visible: moreHover.hovered && !moreMenu.opened
                ToolTip.text: qsTr("More")
                Accessible.role: Accessible.PageTab
                Accessible.name: qsTr("more options")
                MenuPopup {
                    id: moreMenu
                    radioColumn: true
                    x: moreTab.width + 4 - width; y: moreTab.height + 0.67
                    items: pane.moreCategories.map(c => ({ label: c[1], icon: c[2], checked: pane.category === c[0] }))
                    onPicked: i => pane.category = pane.moreCategories[i][0]
                }
            }
        }
        Flickable {
            id: gFlick
            x: 20; y: catBar.visible ? 193.33 : 172.67; width: 321; height: pane.height - y - 10
            clip: true; contentHeight: gCol.height + 12
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Connections { target: pane; function onTabChanged() { gFlick.contentY = 0 } function onCategoryChanged() { gFlick.contentY = 0 } }
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
                // Emoji: the category's name over its emoji.
                Item {
                    visible: pane.tab === 1 && !pane.q
                    width: 311; height: visible ? 33 : 0
                    Text { y: 13; width: 293; height: 20; verticalAlignment: Text.AlignVCenter; text: pane.categoryLabel(pane.category); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary; Accessible.role: Accessible.Heading }
                }
                Flow {
                    visible: pane.tab === 0 || pane.tab === 1
                    width: 311; spacing: 2; topPadding: pane.tab === 0 ? 13 : pane.q ? 4 : 20
                    Repeater {
                        model: pane.emojiShown
                        Rectangle {
                            id: ecell
                            required property var modelData
                            width: 40.14; height: 40; radius: 4
                            color: ecellHover.hovered ? theme.rowHover : "transparent"
                            Text { anchors.centerIn: parent; text: ecell.modelData[0]; font.family: theme.font; font.pixelSize: 28 }
                            HoverHandler { id: ecellHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: if (pane.form) pane.form.insertEmoji(ecell.modelData[0]) }
                            ToolTip.visible: ecellHover.hovered && !!ecell.modelData[1]
                            ToolTip.text: ecell.modelData[1] || ""
                            Accessible.role: Accessible.Button
                            Accessible.name: ecell.modelData[1] || ecell.modelData[0]
                        }
                    }
                }
                Item {
                    visible: pane.tab === 0
                    width: 311; height: visible ? 44 : 0
                    Text { x: 5; y: 20; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Stock images"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { anchors.right: parent.right; y: 20.67; height: 18.67; verticalAlignment: Text.AlignVCenter; text: qsTr("View more"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                           TapHandler { onTapped: { pane.tab = 2 } } HoverHandler { cursorShape: Qt.PointingHandCursor } }
                }
                // Stock images' category tiles (no search).
                Column {
                    visible: pane.tab === 2 && !pane.q
                    topPadding: 5; spacing: 10
                    Repeater {
                        model: pane.tab === 2 && !pane.q ? pane.rowsOf(pane.themes, t => t.aspect || 98.46 / 141.5) : []
                        Row {
                            id: trow
                            required property var modelData
                            spacing: 10
                            Repeater {
                                model: [trow.modelData.a, trow.modelData.b].filter(x => x)
                                Item {
                                    id: tile
                                    required property var modelData
                                    width: 141.5; height: trow.modelData.h
                                    FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: "transparent" }
                                    Image {
                                        id: timg
                                        anchors.fill: parent
                                        source: tile.modelData.thumb; asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        onStatusChanged: if (status === Image.Ready && implicitWidth > 0) pane.setThemeAspect(tile.modelData.id, implicitHeight / implicitWidth)
                                    }
                                    Rectangle { anchors.fill: parent; radius: 5; color: Qt.rgba(0, 0, 0, tileHover.hovered ? 0.6 : 0.5) }
                                    Text {
                                        anchors.centerIn: parent; width: parent.width - 20
                                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                        text: tile.modelData.name; font.family: theme.font; font.pixelSize: 14; color: "white"
                                    }
                                    RoundedCorners { anchors.fill: parent; radius: 4; background: theme.surface }
                                    HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: pane.query = tile.modelData.name }
                                    ToolTip.visible: tileHover.hovered
                                    ToolTip.text: tile.modelData.name
                                    Accessible.role: Accessible.Button
                                    Accessible.name: tile.modelData.name
                                }
                            }
                        }
                    }
                }
                // Pictures: All's four, a search's, and the stickers.
                Column {
                    visible: pane.tab === 0 || (pane.tab === 2 && pane.q)
                    topPadding: pane.tab === 0 ? 12 : 5; spacing: pane.tab === 0 ? 4 : 10
                    Repeater {
                        model: pane.tab === 0 ? pane.rowsOf(pane.items("Stock Images", pane.q, "").slice(0, 4), p => 98.15 / 141.5)
                             : pane.tab === 2 && pane.q ? pane.rowsOf(pane.items("Stock Images", pane.q, ""), p => p.thumbWidth ? p.thumbHeight / p.thumbWidth : 98.15 / 141.5) : []
                        Row {
                            id: prow
                            required property var modelData
                            spacing: pane.tab === 0 ? 4 : 10
                            Repeater {
                                model: [prow.modelData.a, prow.modelData.b].filter(x => x)
                                Item {
                                    id: pcell
                                    required property var modelData
                                    width: 141.5; height: prow.modelData.h
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: pcell.modelData.thumb; asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        opacity: pcellHover.hovered ? 0.85 : 1
                                    }
                                    RoundedCorners { visible: pane.tab === 0; anchors.fill: parent; radius: 4; background: theme.surface }
                                    HoverHandler { id: pcellHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: pane.pickPicture(pcell.modelData, false) }
                                    ToolTip.visible: pcellHover.hovered && !!pcell.modelData.description
                                    ToolTip.text: pcell.modelData.description || ""
                                    Accessible.role: Accessible.Button
                                    Accessible.name: pcell.modelData.description
                                }
                            }
                        }
                    }
                }
                Grid {
                    visible: pane.tab === 3
                    topPadding: 5; columns: 3; columnSpacing: 10; rowSpacing: 10
                    Repeater {
                        model: pane.tab === 3 ? pane.items("Stickers", pane.q, "") : []
                        Item {
                            id: scell
                            required property var modelData
                            width: 91; height: 75.33
                            Rectangle { anchors.fill: parent; radius: 4; color: scellHover.hovered ? theme.rowHover : "transparent" }
                            Image { x: 9.5; width: 72; height: 72; source: scell.modelData.thumb; asynchronous: true; fillMode: Image.PreserveAspectFit }
                            HoverHandler { id: scellHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: pane.pickPicture(scell.modelData, true) }
                            Accessible.role: Accessible.Button
                            Accessible.name: scell.modelData.description
                        }
                    }
                }
            }
        }
        // Nothing found.
        Item {
            readonly property bool none: (pane.tab === 1 && pane.q && !pane.loading("Emojis", pane.q, "") && pane.found[pane.keyOf("Emojis", pane.q, "")] !== undefined && pane.emojiShown.length === 0)
                || (pane.tab === 2 && pane.q && pane.found[pane.keyOf("Stock Images", pane.q, "")] !== undefined && pane.items("Stock Images", pane.q, "").length === 0)
                || (pane.tab === 3 && pane.found[pane.keyOf("Stickers", pane.q, "")] !== undefined && pane.items("Stickers", pane.q, "").length === 0)
            visible: none
            x: 20; y: 160.67; width: 311; height: pane.height - y - 10
            Image {
                x: 62.2; y: 62.52; width: 186.59; height: 186.95
                source: "https://res.public.onecdn.static.microsoft/assets/mail/illustrations/emptySpotlight/v2/" + (theme.dark ? "dark" : "light") + ".svg"
                sourceSize: Qt.size(373, 374); asynchronous: true; fillMode: Image.PreserveAspectFit
            }
            Text { y: 249.47; width: 311; height: 18.67; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: qsTr("We didn't find anything"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            Text { y: 268.13; width: 311; height: 18.67; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: qsTr("Try a different keyword"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.textSecondary }
        }
    }
    /// A category tile's picture shape, once loaded.
    function setThemeAspect(id, a) {
        const l = themes.slice(), i = l.findIndex(t => t.id === id)
        if (i < 0 || Math.abs((l[i].aspect || 0) - a) < 0.001) return
        l[i] = Object.assign({}, l[i], { aspect: a }); themes = l
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
