import QtQuick
import QtQuick.Controls.Basic
import QtCore

// Teams' unified fun picker (sendMessageCommands-UnifiedFunPicker-content,
// measured on winpc): 316 x 485, NeutralBackground (#FAFAFA) with tabs
// All | Emoji | GIFs | Stickers (14 px, the open one semibold, 50 tall, from
// 2 down), over a white body (radius 6 6 0 0) from 53.
// - Search: 286 x 32 at (15, 68), #F5F5F5, radius 4, "Find something fun".
// - All: "Emoji", "GIFs" and "Stickers" headings (14 medium) with "See all"
//   (opens that tab); six recent emoticons (46 px cells), three trending
//   GIFs (89.3 x 86.3), four recent stickers (69 px tiles).
// - Emoji: Teams' emoji panel, 432.3 tall, with the org's Custom section.
// - GIFs: eight categories (139.5 x 76, the picture under 30 % black and a
//   14 px semibold white name); a category or a search shows results in two
//   140 px columns, 6 apart, with a back button before the search.
// - Stickers: Recent (eight 69 px tiles, 3 apart, #F5F5F5, radius 6), then
//   "Sticker Packs" (138 x 46 tiles) and a pack's own grid.
// - All and GIFs end with "GIFs powered by GIPHY" and "View Terms" (12 px).
// Picks: an emoticon id, a GIF {url, preview, width, height, title} or a
// sticker {id, url, preview, title}; editable stickers ask to be captioned.
Popup {
    id: root
    signal pickedEmoji(string id)
    signal pickedGif(var item)
    signal pickedSticker(var item)
    // A captioned sticker drawn here: {kind: "image", src, path, title, width, height}.
    signal pickedCaptioned(var item)
    signal customize()
    signal addCustomEmoji()
    property string tab: "all"
    width: 316; height: 485; padding: 0
    modal: false; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.pick("#FAFAFA", "#1F1F1F") }

    // Teams' sticker catalogue (shipped with OST; pictures from Teams' CDN).
    property var catalog: ({ statics: "", cdnVersion: 5, categories: [], stickers: [], popular: [], defaultRecent: [] })
    readonly property var stickerById: { const m = {}; for (const s of catalog.stickers) m[s.id] = s; return m }
    property var recentIds: []
    readonly property var recentStickers: (recentIds.length ? recentIds : catalog.defaultRecent).map(id => stickerById[id]).filter(s => !!s).slice(0, 8)
    Component.onCompleted: {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) root.catalog = JSON.parse(xhr.responseText)
        }
        xhr.open("GET", Qt.resolvedUrl("../assets/funstuff/stickers.json")); xhr.send()
    }
    function v() { return "?v=" + catalog.cdnVersion }
    function isMeme(s) { return s.category === "Meme" }
    function stickerPreview(s) {
        return isMeme(s) ? catalog.statics + "/evergreen-assets/funstuff/meme/assets/Preview/" + (s.preview || s.link) + v()
            : catalog.statics + "/evergreen-assets/funstuff/stickers/en-us/assets/" + s.category + "/Preview/" + (s.preview || s.link) + v()
    }
    function packOf(s) { return catalog.categories.find(c => c.id === s.category) }
    function stickerSendUrl(s) {
        const pack = packOf(s)
        return catalog.statics + "/evergreen-assets/stickerassets/" + s.category.toLowerCase() + (isMeme(s) ? "-500x500" : "-250x250")
            + (pack && pack.localized ? "/en-us" : "") + "/" + s.link + v()
    }
    function packIcon(c) {
        return c.id === "Meme" ? catalog.statics + "/evergreen-assets/funstuff/meme/assets/Preview/" + c.header + v()
            : catalog.statics + "/evergreen-assets/funstuff/stickers/en-us/assets/" + c.id + "/Preview/" + c.header + v()
    }
    function editable(s) { return !!s.template || isMeme(s) }
    function chooseSticker(s) {
        const ids = [s.id].concat((recentIds.length ? recentIds : catalog.defaultRecent).filter(i => i !== s.id)).slice(0, 8)
        recentIds = ids
        backend.setSetting("recent_stickers", JSON.stringify(ids))
        // Editable stickers (the pencil) open Teams' caption editor first.
        if (editable(s)) { root.tab = "stickers"; editor.start(s); return }
        root.pickedSticker({ id: s.id, url: stickerSendUrl(s), preview: stickerPreview(s), title: s.title })
        root.close()
    }
    function templateUrl(s) {
        const pack = packOf(s)
        return catalog.statics + "/evergreen-assets/stickerassets/" + s.category.toLowerCase() + (isMeme(s) ? "-500x500" : "-250x250")
            + (pack && pack.localized ? "/en-us" : "") + "/" + s.template + v()
    }
    function chooseGif(g) { root.pickedGif(g); root.close() }
    // Test hooks.
    function gifCategoryForTest(i) { const c = gifCategories[i]; gifQuery = c[1]; gifResultsOpen = true; backend.searchGifs(c[1]) }
    function editForTest(id, caption) { tab = "stickers"; editor.start(stickerById[id]); cap1.text = caption }
    function finishEditForTest() { editor.finish() }

    // GIFs: categories, the open one, and the newest results.
    readonly property var gifCategories: [
        ["Trending", "", "trending"], ["Reactions", "reactions", "reactions"], ["Greetings", "greetings", "greetings"],
        ["Perfect", "perfect", "perfect"], ["Welcome", "welcome", "welcome"], ["Congratulations", "congratulations", "congratulations"],
        ["Thank you", "thank you", "thankyou"], ["Excited", "excited", "excited"]
    ]
    property string gifQuery: ""
    property bool gifResultsOpen: false
    readonly property var gifResults: { const r = backend.funResultsJson ? JSON.parse(backend.funResultsJson) : null; return r && r.query === gifQuery ? r.items : [] }
    property var trending: []
    Connections {
        target: backend
        function onFunResultsJsonChanged() {
            const r = backend.funResultsJson ? JSON.parse(backend.funResultsJson) : null
            if (r && r.query === "" && r.items.length) root.trending = r.items
        }
    }
    property string query: ""
    onQueryChanged: if (tab === "gifs" || tab === "all") searchTimer.restart()
    Timer { id: searchTimer; interval: 300; onTriggered: { root.gifQuery = root.query.trim(); root.gifResultsOpen = root.gifQuery.length > 0 || root.gifResultsOpen; backend.searchGifs(root.gifQuery) } }
    property string openPack: ""

    onOpened: {
        tab = "all"; query = ""; search.text = ""; gifResultsOpen = false; openPack = ""; editor.sticker = null
        const saved = backend.setting("recent_stickers")
        recentIds = saved ? JSON.parse(saved) : []
        gifQuery = ""; backend.searchGifs("")
        search.forceActiveFocus()
    }
    onTabChanged: { if (tab === "emoji") emojiPanel.reset(); else search.forceActiveFocus() }

    // Tabs.
    Repeater {
        model: [["all", "All", 19.1, 40.7], ["emoji", "Emoji", 78, 59.3], ["gifs", "GIFs", 155.5, 50.9], ["stickers", "Stickers", 224.6, 72.4]]
        Item {
            id: tabItem
            required property var modelData
            readonly property bool sel: root.tab === modelData[0]
            x: modelData[2]; y: 2; width: modelData[3]; height: 50
            Text {
                id: tabLabel
                x: 10; y: 12; height: 20; verticalAlignment: Text.AlignVCenter
                text: tabItem.modelData[1]
                font.family: theme.font; font.pixelSize: 14; font.weight: tabItem.sel ? Font.DemiBold : Font.Normal
                color: tabItem.sel ? theme.text : theme.textStrong
            }
            Rectangle { visible: tabItem.sel; x: 10; y: 45; width: tabLabel.implicitWidth; height: 3; radius: 1.5; color: theme.brand }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.tab = tabItem.modelData[0]; root.openPack = ""; root.gifResultsOpen = root.query.trim().length > 0 } }
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData[1]
            Accessible.selected: sel
        }
    }

    // The white body.
    Rectangle {
        y: 53; width: root.width; height: root.height - 53; radius: 6
        color: theme.surface
        Rectangle { y: 6; width: parent.width; height: parent.height - 6; color: theme.surface }
    }

    // Back (GIF results, a sticker pack) and search.
    readonly property bool showBack: (tab === "gifs" && gifResultsOpen) || (tab === "stickers" && (openPack !== "" || !!editor.sticker))
    Rectangle {
        visible: root.tab !== "emoji" && root.showBack
        x: 15; y: 68; width: 32; height: 32; radius: 4
        color: backHover.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (root.tab === "gifs") { root.gifResultsOpen = false; search.text = "" } else if (editor.sticker) editor.sticker = null; else root.openPack = "" } }
        Accessible.role: Accessible.Button
        Accessible.name: "Back"
    }
    Rectangle {
        visible: root.tab !== "emoji"
        x: root.showBack ? 59 : 15; y: 68; width: root.showBack ? 242 : 286; height: 32; radius: 4
        color: theme.pick("#F5F5F5", "#292929")
        TextInput {
            id: search
            x: 10; width: parent.width - 10 - 34; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            clip: true
            onTextChanged: root.query = text
            Text { visible: !search.text; text: "Find something fun"; font: search.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Search for emoji, GIFs or stickers"
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
    }

    // Section heading with "See all ›" (titlerow-end-button 83.2 x 31.3).
    component Heading: Item {
        id: hd
        property string text
        property bool seeAll: true
        signal seeAllClicked()
        width: 316; height: 31.3
        Text { x: 15; y: 5.7; height: 20; verticalAlignment: Text.AlignVCenter; text: hd.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: theme.text; Accessible.role: Accessible.Heading }
        Rectangle {
            visible: hd.seeAll
            x: 224.8; width: 83.2; height: 31.3; radius: 4
            color: seeHover.hovered ? theme.hover : "transparent"
            Text { x: 12.7; y: 5.7; height: 20; verticalAlignment: Text.AlignVCenter; text: "See all"; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
            FluentIcon { x: 59; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-20"; size: 16; color: theme.textStrong }
            HoverHandler { id: seeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: hd.seeAllClicked() }
            Accessible.role: Accessible.Button
            Accessible.name: "See all " + hd.text
        }
    }

    // A sticker tile: #F5F5F5, radius 6, the picture inset 4.7; editable ones
    // carry an 18 px #575757 pencil badge.
    component StickerTile: Rectangle {
        id: st
        property var sticker
        property real size: 69
        width: size; height: size; radius: 6
        color: stHover.hovered ? theme.pick("#EBEBEB", "#333333") : theme.pick("#F5F5F5", "#292929")
        Image {
            x: 4.7; y: 4.7; width: st.size - 9.4; height: st.size - 9.4
            source: st.sticker ? root.stickerPreview(st.sticker) : ""
            fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
        }
        Rectangle {
            visible: !!st.sticker && root.editable(st.sticker)
            x: st.size - 25.4; y: st.size - 25.4; width: 18; height: 18; radius: 9
            color: "#575757"
            FluentIcon { anchors.centerIn: parent; name: "edit-20-filled"; size: 12; color: "white" }
        }
        HoverHandler { id: stHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.chooseSticker(st.sticker) }
        ToolTip {
            visible: stHover.hovered; delay: 500
            y: st.height + 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: st.sticker ? st.sticker.title : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: sticker ? sticker.title : ""
    }

    // A GIF result, cropped to its tile, radius 6, the title as tooltip.
    component GifTile: Item {
        id: gt
        property var gif
        clip: true
        AnimatedImage {
            anchors.fill: parent; anchors.margins: 0.7
            source: gt.gif ? gt.gif.preview : ""
            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
            playing: root.opened
        }
        RoundedCorners { anchors.fill: parent; radius: 6; background: theme.surface }
        HoverHandler { id: gtHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.chooseGif(gt.gif) }
        ToolTip {
            visible: gtHover.hovered; delay: 500
            x: (gt.width - width) / 2; y: gt.height / 2 - height / 2; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: gt.gif ? gt.gif.title : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: gif ? gif.title : ""
    }

    // All.
    Item {
        visible: root.tab === "all"
        y: 115; width: root.width; height: 334
        clip: true
        readonly property string q: root.query.trim().toLowerCase()
        Heading { y: 2; text: "Emoji"; onSeeAllClicked: root.tab = "emoji" }
        Row {
            x: 15; y: 35.3
            Repeater {
                model: {
                    const ids = backend.recentReactionsJson ? JSON.parse(backend.recentReactionsJson) : []
                    return ids.slice(0, 6)
                }
                Rectangle {
                    required property string modelData
                    width: 46; height: 46; radius: 4
                    color: emHover.hovered ? theme.menuHover : "transparent"
                    Emoticon { x: 8; y: 8; key: parent.modelData; named: "medium"; size: 30 }
                    HoverHandler { id: emHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.pickedEmoji(parent.modelData); root.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: backend.emoticonName(modelData)
                }
            }
        }
        Heading { y: 96.7; text: "GIFs"; onSeeAllClicked: root.tab = "gifs" }
        Repeater {
            model: (parent.q ? root.gifResults : root.trending).slice(0, 3)
            GifTile {
                required property var modelData
                required property int index
                gif: modelData
                x: [17.5, 113.3, 209.2][index]; y: 130; width: 89.3; height: 86.3
            }
        }
        Heading { y: 231.7; text: "Stickers"; onSeeAllClicked: root.tab = "stickers" }
        Row {
            x: 15; y: 265; spacing: 3
            Repeater {
                model: {
                    const q = parent.parent.q
                    const list = q ? root.catalog.stickers.filter(s => (s.title + " " + s.keywords).toLowerCase().indexOf(q) >= 0) : root.recentStickers
                    return list.slice(0, 4)
                }
                StickerTile { required property var modelData; sticker: modelData }
            }
        }
    }

    // Emoji.
    EmojiPanel {
        id: emojiPanel
        visible: root.tab === "emoji"
        active: root.opened
        compose: true
        customSection: true
        y: 52.7; width: root.width; height: 432.3
        onPicked: (key, on) => root.pickedEmoji(key)
        onCustomize: root.customize()
        onAddCustomEmoji: { root.close(); root.addCustomEmoji() }
        onDone: root.close()
    }

    // GIFs.
    Item {
        visible: root.tab === "gifs"
        y: 115; width: root.width; height: 334
        clip: true
        Grid {
            visible: !root.gifResultsOpen
            x: 15; columns: 2; columnSpacing: 6; rowSpacing: 5
            Repeater {
                model: root.gifCategories
                Item {
                    id: cat
                    required property var modelData
                    width: 139.5; height: 76
                    AnimatedImage {
                        x: 0.7; y: 0.7; width: 138.2; height: 74.7
                        source: "https://teams.public.onecdn.static.microsoft/evergreen-assets/funstuff/giphy/assets/categories_bg/" + cat.modelData[2] + ".gif"
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                        playing: root.opened && root.tab === "gifs"
                    }
                    Rectangle { x: 0.7; y: 0.7; width: 138.2; height: 74.7; color: "#4D000000" }
                    RoundedCorners { anchors.fill: parent; radius: 6; background: theme.surface }
                    Text { x: 15.7; y: 28; height: 20; verticalAlignment: Text.AlignVCenter; text: cat.modelData[0]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.gifQuery = cat.modelData[1]; root.gifResultsOpen = true; backend.searchGifs(cat.modelData[1]) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData[0]
                }
            }
        }
        // Results: two 140 px columns, each item as tall as its picture.
        Flickable {
            id: gifFlick
            visible: root.gifResultsOpen
            anchors.fill: parent
            contentHeight: Math.max(colA.height, colB.height) + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            readonly property var cols: {
                const a = [], b = []; let ha = 0, hb = 0
                for (const g of root.gifResults) {
                    const h = g.width > 0 ? 140 * g.height / g.width : 140
                    if (ha <= hb) { a.push(g); ha += h + 6 } else { b.push(g); hb += h + 6 }
                }
                return [a, b]
            }
            Column {
                id: colA
                x: 15; spacing: 6
                Repeater { model: gifFlick.cols[0]; GifTile { required property var modelData; gif: modelData; width: 140; height: modelData.width > 0 ? 140 * modelData.height / modelData.width : 140 } }
            }
            Column {
                id: colB
                x: 161; spacing: 6
                Repeater { model: gifFlick.cols[1]; GifTile { required property var modelData; gif: modelData; width: 140; height: modelData.width > 0 ? 140 * modelData.height / modelData.width : 140 } }
            }
        }
        Text {
            visible: root.gifResultsOpen && root.gifResults.length === 0 && backend.funResultsJson.indexOf("\"query\":" + JSON.stringify(root.gifQuery)) >= 0
            anchors.centerIn: parent
            text: "We didn't find any matches."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
    }

    // Stickers.
    Flickable {
        id: stickFlick
        visible: root.tab === "stickers" && !editor.sticker
        y: 115; width: root.width; height: 370
        clip: true
        contentHeight: stickersCol.height + 12
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property string q: root.query.trim().toLowerCase()
        readonly property var packStickers: root.openPack === "Popular" ? root.catalog.popular.map(id => root.stickerById[id]).filter(s => !!s)
            : root.catalog.stickers.filter(s => s.category === root.openPack)
        Column {
            id: stickersCol
            width: root.width
            // A search, or an open pack: one grid.
            Heading { visible: stickFlick.q.length === 0 && root.openPack === ""; y: 0; text: "Recent"; seeAll: false; height: 22 }
            Grid {
                visible: stickFlick.q.length === 0 && root.openPack === ""
                x: 15; columns: 4; spacing: 3
                Repeater { model: root.recentStickers; StickerTile { required property var modelData; sticker: modelData } }
            }
            Item { visible: stickFlick.q.length === 0 && root.openPack === ""; width: 1; height: 45 }
            Heading { visible: stickFlick.q.length === 0 && root.openPack === ""; text: "Sticker Packs"; onSeeAllClicked: packsAll.visible = !packsAll.visible }
            Item { visible: stickFlick.q.length === 0 && root.openPack === ""; width: 1; height: 2 }
            Grid {
                id: packGrid
                visible: stickFlick.q.length === 0 && root.openPack === ""
                x: 15; columns: 2; columnSpacing: 6; rowSpacing: 6
                Repeater {
                    model: packsAll.visible ? root.catalog.categories : root.catalog.categories.slice(0, 4)
                    Rectangle {
                        id: pack
                        required property var modelData
                        width: 138; height: 46; radius: 6
                        color: packHover.hovered ? theme.pick("#EBEBEB", "#333333") : theme.pick("#F5F5F5", "#292929")
                        Text { x: 10; y: 13; width: 88; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: pack.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Image { x: 102; y: 10; width: 26; height: 26; source: root.packIcon(pack.modelData); fillMode: Image.PreserveAspectFit; asynchronous: true }
                        FluentIcon { visible: pack.modelData.customizable; x: 116; y: 24; name: "edit-20-filled"; size: 12; color: theme.textStrong }
                        HoverHandler { id: packHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openPack = pack.modelData.id }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.title
                    }
                }
            }
            QtObject { id: packsAll; property bool visible: false }
            Heading {
                visible: stickFlick.q.length > 0 || root.openPack !== ""
                seeAll: false; height: 22
                text: root.openPack !== "" ? (root.openPack === "Popular" ? "Popular stickers and memes" : ((root.catalog.categories.find(c => c.id === root.openPack) || {}).title || "")) : ""
            }
            Grid {
                visible: stickFlick.q.length > 0 || root.openPack !== ""
                x: 15; columns: 4; spacing: 3
                Repeater {
                    model: stickFlick.q.length > 0
                        ? root.catalog.stickers.filter(s => (s.title + " " + s.keywords).toLowerCase().indexOf(stickFlick.q) >= 0)
                        : stickFlick.packStickers
                    StickerTile { required property var modelData; sticker: modelData }
                }
            }
        }
    }

    // Teams' sticker caption editor ("Edit sticker", measured in Teams): the
    // captioned template centred at 130 (scaled to 195.3 wide), the caption
    // box (286 x 94.7, #F5F5F5) at 288, Cancel and Done (138 x 31.3) at 395.3.
    // Memes take a top and a bottom caption (Impact, white with a black
    // outline); other stickers one caption in their region and font. Done
    // draws it at the template's size and hands it on for upload.
    Item {
        id: editor
        property var sticker: null
        readonly property bool meme: !!sticker && root.isMeme(sticker)
        visible: root.tab === "stickers" && !!sticker
        width: root.width; height: root.height
        function start(s) {
            sticker = s
            cap1.text = s.caption && s.caption.placeholderText ? s.caption.placeholderText : ""
            cap2.text = ""
            cap1.forceActiveFocus(); cap1.selectAll()
        }
        readonly property real nativeW: tpl.implicitWidth > 0 ? tpl.implicitWidth : 320
        readonly property real nativeH: tpl.implicitHeight > 0 ? tpl.implicitHeight : 240
        // Caption regions, in template pixels (memes: Teams' top and bottom bands).
        readonly property var region1: meme ? { "startX": 20, "startY": 20, "endX": nativeW - 20, "endY": 70 }
            : (sticker && sticker.caption && sticker.caption.region ? sticker.caption.region : { "startX": 20, "startY": 20, "endX": nativeW - 20, "endY": 70 })
        readonly property var region2: { "startX": 20, "startY": nativeH - 70, "endX": nativeW - 20, "endY": nativeH - 20 }
        readonly property var font: sticker && sticker.caption && sticker.caption.font ? sticker.caption.font : { "family": "Arial", "color": "#000000" }
        // The drawing, at the template's own size, shown scaled.
        Item {
            id: drawing
            x: (root.width - 195.3) / 2; y: 130
            width: editor.nativeW; height: editor.nativeH
            scale: 195.3 / editor.nativeW; transformOrigin: Item.TopLeft
            Image { id: tpl; source: editor.sticker ? root.templateUrl(editor.sticker) : ""; asynchronous: true; cache: true }
            component Caption: Text {
                property var region
                x: region.startX; y: region.startY; width: region.endX - region.startX; height: region.endY - region.startY
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap; fontSizeMode: Text.Fit; minimumPixelSize: 8
                font.family: editor.font.family; font.pixelSize: 200
                color: editor.font.color
                style: editor.font.border ? Text.Outline : Text.Normal; styleColor: editor.font.border || "transparent"
            }
            Caption { region: editor.region1; text: cap1.text }
            Caption { visible: editor.meme; region: editor.region2; text: cap2.text }
        }
        Rectangle {
            x: 15.3; y: 288; width: 286; height: 94.7; radius: 4
            color: theme.pick("#F5F5F5", "#292929")
            Column {
                x: 12; y: 10; width: parent.width - 24; spacing: 6
                TextInput {
                    id: cap1
                    width: parent.width
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    maximumLength: 100; clip: true
                    Text { visible: !cap1.text; text: editor.meme ? "Top Caption" : "Caption"; font: cap1.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: editor.meme ? "Top Caption" : "Caption"
                }
                TextInput {
                    id: cap2
                    visible: editor.meme
                    width: parent.width
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    maximumLength: 100; clip: true
                    Text { visible: !cap2.text; text: "Bottom caption"; font: cap2.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Bottom caption"
                }
            }
        }
        Rectangle {
            x: 15.3; y: 395.3; width: 138; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: editor.sticker = null }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            readonly property bool can: tpl.status === Image.Ready && (cap1.text.trim().length > 0 || cap2.text.trim().length > 0)
            x: 163.3; y: 395.3; width: 138; height: 31.3; radius: 4
            color: !can ? theme.bgDisabled : doneHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Done"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.disabledStrong }
            HoverHandler { id: doneHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: editor.finish() }
            Accessible.role: Accessible.Button
            Accessible.name: "Done"
        }
        function finish() {
            const caption = [cap1.text.trim(), editor.meme ? cap2.text.trim() : ""].filter(t => t).join(" ")
            const dir = String(StandardPaths.writableLocation(StandardPaths.CacheLocation)).replace(/^file:\/\//, "")
            const path = dir + "/sticker-" + Date.now() + ".png"
            const w = editor.nativeW, h = editor.nativeH
            drawing.grabToImage(r => {
                if (!r.saveToFile(path)) { console.warn("sticker not saved", path); return }
                root.pickedCaptioned({ kind: "image", src: "file://" + path, path: path, title: "Sticker image, " + caption, width: w, height: h })
                editor.sticker = null
                root.close()
            }, Qt.size(w, h))
        }
    }

    // GIPHY's credit (All and GIFs), and its terms.
    Item {
        visible: root.tab === "all" || root.tab === "gifs"
        y: 449; width: root.width; height: 36
        Text { x: 111.5; y: 10; height: 16; verticalAlignment: Text.AlignVCenter; text: "GIFs powered by GIPHY"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Text {
            id: viewTerms
            x: 241.4; y: 10; height: 16; verticalAlignment: Text.AlignVCenter
            text: "View Terms"; font.family: theme.font; font.pixelSize: 12; color: theme.brand
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: termsPopup.open() }
            Accessible.role: Accessible.Link
            Accessible.name: text
        }
        Popup {
            id: termsPopup
            x: 16; y: -height - 6; width: 284; padding: 12
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: Text {
                wrapMode: Text.Wrap; textFormat: Text.StyledText
                text: "When you search for images, your search terms are sent to GIPHY. To learn more, see GIPHY's <a href=\"https://support.giphy.com/hc/en-us/articles/360032872931-GIPHY-Privacy-Policy\">Privacy Policy</a> and <a href=\"https://support.giphy.com/hc/en-us/articles/360020027752-GIPHY-User-Terms-of-Service\">Terms of Service</a>."
                linkColor: theme.brand
                font.family: theme.font; font.pixelSize: theme.small; color: theme.text
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
