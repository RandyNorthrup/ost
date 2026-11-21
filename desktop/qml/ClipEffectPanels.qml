import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// The clip recorder's effect drawers, as Microsoft Stream's camera shows
// them inside Teams (measured on winpc 2026-11-20; Stream's chunks for the
// rest). One drawer at a time, over the picture and the tools; none of it
// is recorded.
// - Backdrops (720 wide): Search, the Images and Videos tabs, None,
//   Upload and Blur, then Images and Videos (24 each, See more: all 50),
//   Microsoft's stock content found over AugLoop (Hubble).
// - Stickers (720): Search, the category strip, then a section per
//   category (33 each, See more: 50) of Fluent emoji (Hubble).
// - Filter, Frame, Board (608): a carousel of 72 x 48 tiles after Clear;
//   Board adds the Split screen slider.
// - Draw (480): Color picker and Thickness.
// - Photo (680): Add photo (a file picker).
// - Text menus (Font, Color, Text stroke / Text shadow, Text background).
Item {
    id: panels
    required property var fx
    required property var catalog
    /// The recorder is in screen mode (Backdrop is the camera's).
    property bool screenMode: false
    signal uploadBackdrop()

    readonly property real dpx: 1

    // ---- Hubble (Backdrops, Stickers) ----
    property var bdImages: []
    property var bdVideos: []
    property var bdFound: null      // {images, videos} for a search
    property string bdMore: ""      // "images" | "videos": See more
    readonly property var stickerCats: [
        { key: "Smilies", name: qsTr("Smilies", "x.onecamera:stickerCategories.smilies") }, { key: "Animals", name: qsTr("Animals", "x.onecamera:stickerCategories.animals") }, { key: "Food", name: qsTr("Food", "x.onecamera:stickerCategories.food") },
        { key: "Objects", name: qsTr("Objects", "x.onecamera:stickerCategories.objects") }, { key: "People", name: qsTr("People", "x.onecamera:stickerCategories.people") }, { key: "Hand gestures", name: qsTr("Hand gestures", "x.onecamera:stickerCategories.handGestures") },
        { key: "Travel and places", name: qsTr("Travel and places", "x.onecamera:stickerCategories.travelAndPlaces") }, { key: "Activities", name: qsTr("Activities", "x.onecamera:stickerCategories.activities") }, { key: "Symbols", name: qsTr("Symbols", "x.onecamera:stickerCategories.symbols") }
    ]
    property var stickers: ({})     // category -> items
    property var stickersFound: null
    property string stickerMore: ""
    property int stickerCat: 0
    function loadBackdrops() {
        if (bdImages.length || bdVideos.length) return
        backend.hubbleSearch("bd-home", JSON.stringify([{ query: "", pivot: "images" }, { query: "", pivot: "videos" }]))
    }
    function loadStickers() {
        if (Object.keys(stickers).length) return
        backend.hubbleSearch("st-home", JSON.stringify(stickerCats.map(c => ({ query: "", pivot: "stickers", category: c.key }))))
    }
    Connections {
        target: backend
        function onHubbleResults(tag, json) {
            const r = JSON.parse(json)
            if (tag === "bd-home") { panels.bdImages = r[0] || []; panels.bdVideos = r[1] || [] }
            else if (tag === "bd-q:" + bdSearch.text) panels.bdFound = { images: r[0] || [], videos: r[1] || [] }
            else if (tag === "st-home" || tag === "st-q:" + stSearch.text) {
                const m = {}
                panels.stickerCats.forEach((c, i) => m[c.key] = r[i] || [])
                if (tag === "st-home") panels.stickers = m
                else panels.stickersFound = m
            }
        }
    }
    Timer {
        id: bdDebounce; interval: 500
        onTriggered: if (bdSearch.text.length) backend.hubbleSearch("bd-q:" + bdSearch.text, JSON.stringify([{ query: bdSearch.text, pivot: "images" }, { query: bdSearch.text, pivot: "videos" }]))
    }
    Timer {
        id: stDebounce; interval: 500
        onTriggered: if (stSearch.text.length) backend.hubbleSearch("st-q:" + stSearch.text, JSON.stringify(panels.stickerCats.map(c => ({ query: stSearch.text, pivot: "stickers", category: c.key }))))
    }
    Connections {
        target: panels.fx
        function onDrawerChanged() {
            // The search box takes the keys at once, as Stream's does.
            if (panels.fx.drawer === "backdrop") { panels.loadBackdrops(); bdSearch.focusField() }
            else if (panels.fx.drawer === "stickers") { panels.loadStickers(); stSearch.focusField() }
        }
    }

    // ---- Shared pieces ----
    component SearchBox: Rectangle {
        id: sb
        property alias text: field.text
        function focusField() { field.forceActiveFocus() }
        width: parent ? parent.width : 0; height: 36; radius: 8
        color: theme.pick("#FFFFFF", "#292929", "#000000")
        border.color: theme.stroke; border.width: 0.67
        TextField {
            id: field
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10
            background: null
            placeholderText: qsTr("Search...")
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            Accessible.description: qsTr("Results will update as you type.")
        }
        // Fluent's underline: brand while focused.
        Rectangle { x: 4; width: parent.width - 8; y: parent.height - 2; height: 2; radius: 1; color: field.activeFocus ? theme.brand : "transparent" }
    }
    component Tile: Rectangle {
        id: tile
        property string img
        property string label
        property bool selected: false
        property bool clearTile: false
        signal clicked()
        width: 72; height: 48; radius: 8
        color: "#656668"
        clip: true
        Image { anchors.fill: parent; visible: !!tile.img; source: tile.img; fillMode: Image.Stretch; asynchronous: true; smooth: true; opacity: status === Image.Ready ? 1 : 0.3 }
        FluentIcon { visible: tile.clearTile; anchors.centerIn: parent; name: "prohibited-20"; size: 28; color: "#242424" }
        Rectangle { anchors.fill: parent; radius: 8; color: "transparent"; border.width: tile.selected ? 2.67 : 0; border.color: theme.hc("#242424", "#1AEBFF") }
        HoverHandler { id: tHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tile.clicked() }
        ToolTip.visible: tHover.hovered; ToolTip.delay: 300; ToolTip.text: tile.label
        Accessible.role: Accessible.MenuItem
        Accessible.name: tile.label
    }
    component NavButton: Rectangle {
        id: nb
        property bool next: false
        signal clicked()
        width: 18; radius: 4
        color: theme.pick("#FFFFFF", "#292929", "#000000")
        border.color: theme.stroke; border.width: 0.67
        FluentIcon { anchors.centerIn: parent; name: nb.next ? "chevron-right-20" : "chevron-left-20"; size: 20; color: theme.text }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: nb.next ? qsTr("Next options") : qsTr("Previous options")
    }
    component Dots: Row {
        id: dots
        property int pages: 1
        property int page: 0
        visible: pages > 1
        Repeater {
            model: dots.pages
            Text { required property int index; width: 18; height: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: "•"; font.pixelSize: 24; color: index === dots.page ? theme.brand : theme.textSecondary }
        }
    }
    /// A carousel of tiles with Previous / Next and page dots.
    component Carousel: Item {
        id: car
        property alias model: rep.model
        property Component delegate
        width: parent ? parent.width : 0
        height: 55.2 + 18
        NavButton { x: 3.2; height: 55.2; onClicked: flick.contentX = Math.max(0, flick.contentX - flick.width) }
        Flickable {
            id: flick
            x: 24.4; width: parent.width - 48.8; height: 55.2
            contentWidth: row.width; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Behavior on contentX { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Row {
                id: row
                y: 3.6; padding: 2
                Repeater { id: rep; delegate: car.delegate }
            }
        }
        NavButton { next: true; x: parent.width - 21.2; height: 55.2; onClicked: flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width), flick.contentX + flick.width) }
        Dots { anchors.horizontalCenter: parent.horizontalCenter; y: 55.2; pages: Math.max(1, Math.ceil(flick.contentWidth / Math.max(1, flick.width))); page: Math.round(flick.contentX / Math.max(1, flick.width)) }
    }
    /// Fluent's slider: a brand track to the thumb, a round thumb.
    component FluentSlider: Slider {
        id: fs
        height: 32
        leftPadding: 10; rightPadding: 10
        background: Item {
            x: fs.leftPadding; y: (fs.height - 4) / 2
            width: fs.availableWidth; height: 4
            Rectangle { anchors.fill: parent; radius: 2; color: theme.pick("#616161", "#ADADAD", "#FFFFFF") }
            Rectangle { width: fs.visualPosition * parent.width; height: 4; radius: 2; color: theme.brandFill }
        }
        handle: Rectangle {
            x: fs.leftPadding + fs.visualPosition * fs.availableWidth - 10
            y: (fs.height - 20) / 2
            width: 20; height: 20; radius: 10
            color: theme.surface
            border.color: theme.stroke; border.width: 1
            Rectangle { anchors.centerIn: parent; width: fs.pressed ? 10 : 12; height: width; radius: width / 2; color: theme.brandFill }
        }
    }
    component SectionHead: Item {
        id: sh
        property string title
        property bool more: true
        signal seeMore()
        width: parent ? parent.width : 0; height: 24
        Text { y: 2; text: sh.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
        Row {
            visible: sh.more
            anchors.right: parent.right; y: 2; spacing: 4
            Text { text: qsTr("See more"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-16"; size: 16; color: theme.text }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sh.seeMore() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("See more %1").arg(sh.title)
        }
    }
    /// Stream's backdrop grid: 70 px tall pictures, rows justified to the width.
    function justify(list, width, h) {
        const rows = []
        let row = [], w = 0
        for (const it of list) {
            const nat = it.width > 0 && it.height > 0 ? h * it.width / it.height : h * 16 / 9
            // (A row takes what fits, then grows to the width, as Stream's
            // flex rows do.)
            if (row.length && w + nat + 8.67 > width) { rows.push(row); row = []; w = 0 }
            row.push({ it: it, w: nat })
            w += nat + 8.67
        }
        if (row.length) rows.push(row)
        return rows.map((r, i) => {
            const nat = r.reduce((t, c) => t + c.w, 0), gaps = r.length * 8.67
            const full = i < rows.length - 1 || nat + gaps >= width * 0.8
            const f = full ? (width - gaps) / nat : 1
            return r.map(c => ({ it: c.it, w: c.w * f }))
        })
    }
    component PictureGrid: Column {
        id: pg
        property var items: []
        signal picked(var it)
        width: parent ? parent.width : 0
        topPadding: 8
        Repeater {
            model: panels.justify(pg.items, pg.width, 70)
            delegate: Row {
                required property var modelData
                Repeater {
                    model: parent.modelData
                    delegate: Item {
                        required property var modelData
                        width: modelData.w + 8.67; height: 79.9
                        Image {
                            x: 4.33; y: 3.3; width: parent.width - 8.67; height: 70
                            source: parent.modelData.it.thumb
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0.3
                        }
                        RoundedCorners { x: 4.33; y: 3.3; width: parent.width - 8.67; height: 70; radius: 6; background: theme.pick(Qt.rgba(1, 1, 1, 0.95), Qt.rgba(0.16, 0.16, 0.16, 0.95), "#000000") }
                        HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: pg.picked(parent.modelData.it) }
                        ToolTip.visible: gh.hovered; ToolTip.delay: 500; ToolTip.text: modelData.it.name
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Add %1 backdrop.").arg(modelData.it.name)
                    }
                }
            }
        }
    }
    component StickerGrid: Flow {
        id: sg
        property var items: []
        property string category
        signal picked(var it)
        width: parent ? parent.width : 0
        topPadding: 8
        Repeater {
            model: sg.items
            delegate: Item {
                required property var modelData
                required property int index
                width: 61.7; height: 59.9
                Image {
                    id: stImg
                    x: 5.8; y: 3.4; width: 50; height: 50
                    source: parent.modelData.thumb
                    sourceSize: Qt.size(100, 100)
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                    scale: sth.hovered ? 1.03 : 1
                }
                HoverHandler { id: sth; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sg.picked(parent.modelData) }
                ToolTip.visible: sth.hovered; ToolTip.delay: 500; ToolTip.text: modelData.name
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Add %1 sticker. Sticker %2 of %3 in the category %4").arg(modelData.name).arg(index + 1).arg(sg.items.length).arg(sg.category)
            }
        }
    }

    // ---- Backdrops ----
    function applyBackdrop(it) {
        fx.backdrop = { kind: it.kind === "video" ? "video" : "image", url: it.url, name: it.name, upload: false }
        fx.pip = { x: 0, y: 0, s: 1, a: 0 }
        fx.selected = -2
    }
    ClipDrawer {
        visible: panels.fx.drawer === "backdrop"
        title: qsTr("Backdrops")
        drawerWidth: 720
        showBack: panels.bdMore !== ""
        onBack: panels.bdMore = ""
        onClosed: panels.fx.drawer = ""
        Column {
            width: parent.width
            SearchBox { id: bdSearch; onTextChanged: { panels.bdFound = null; panels.bdMore = ""; bdDebounce.restart() } }
            Item {
                width: parent.width; height: 68
                Row {
                    x: 4.4; y: 14
                    Repeater {
                        model: [qsTr("Images"), qsTr("Videos")]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: 72; height: 40; radius: 8
                            color: theme.pick(Qt.rgba(1, 1, 1, 0.5), Qt.rgba(1, 1, 1, 0.08), "#000000")
                            Text { anchors.centerIn: parent; text: parent.modelData; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panels.bdMore = parent.index === 0 ? "images" : "videos" }
                            Accessible.role: Accessible.PageTab
                            Accessible.name: qsTr("%1 tab").arg(modelData)
                        }
                    }
                }
            }
            Flickable {
                width: parent.width; height: 204
                contentHeight: bdCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Column {
                    id: bdCol
                    width: parent.width - 8
                    // None, Upload, Blur.
                    Row {
                        visible: panels.bdMore === "" && !bdSearch.text.length
                        topPadding: 8
                        Repeater {
                            model: [
                                { label: qsTr("None"), icon: "prohibited-20", act: "none" },
                                { label: qsTr("Upload"), icon: "image-add-20", act: "upload" },
                                { label: qsTr("Blur"), icon: "video-background-effect-20-filled", act: "blur" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 104.4; height: 62.7; radius: 10; color: "transparent"
                                border.width: 1.33
                                border.color: "transparent"
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 1.33; radius: 4
                                    color: abHover.hovered ? theme.menuHover : "transparent"
                                }
                                Column {
                                    anchors.centerIn: parent; spacing: 2
                                    FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 20; color: theme.text }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.family: theme.font; font.pixelSize: 16; color: theme.text }
                                }
                                HoverHandler { id: abHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (modelData.act === "none") panels.fx.backdrop = { kind: "none" }
                                        else if (modelData.act === "blur") panels.fx.backdrop = { kind: "blur" }
                                        else panels.uploadBackdrop()
                                    }
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label
                            }
                        }
                    }
                    Repeater {
                        model: [
                            { key: "images", title: qsTr("Images") },
                            { key: "videos", title: qsTr("Videos") }
                        ]
                        delegate: Column {
                            required property var modelData
                            width: bdCol.width
                            topPadding: 12
                            visible: panels.bdMore === "" || panels.bdMore === modelData.key
                            readonly property var all: panels.bdFound ? panels.bdFound[modelData.key] : modelData.key === "images" ? panels.bdImages : panels.bdVideos
                            SectionHead { title: modelData.title; more: panels.bdMore === "" && parent.all.length > 24; onSeeMore: panels.bdMore = parent.modelData.key }
                            PictureGrid {
                                items: panels.bdMore === "" ? parent.all.slice(0, 24) : parent.all
                                onPicked: it => panels.applyBackdrop(it)
                            }
                        }
                    }
                    Text {
                        visible: !!panels.bdFound && !panels.bdFound.images.length && !panels.bdFound.videos.length
                        width: parent.width; topPadding: 16; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Your search had no results. Please try again.")
                        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                }
            }
        }
    }

    // ---- Stickers ----
    function addSticker(it) {
        // Stream's sticker: 100 px wide on the picture, centred, selected;
        // the drawer closes.
        fx.add({ kind: "image", src: it.url, sticker: true, cx: fx.pictureWidth / 2, cy: fx.pictureHeight / 2, w: 100, h: 100, fit: 100, fitTall: 100 })
        fx.drawer = ""
    }
    ClipDrawer {
        visible: panels.fx.drawer === "stickers"
        title: qsTr("Stickers")
        drawerWidth: 720
        showBack: panels.stickerMore !== ""
        onBack: panels.stickerMore = ""
        onClosed: panels.fx.drawer = ""
        Column {
            width: parent.width
            SearchBox { id: stSearch; onTextChanged: { panels.stickersFound = null; panels.stickerMore = ""; stDebounce.restart() } }
            Item {
                width: parent.width; height: 68
                NavButton { x: 3.2; y: 9; height: 40; onClicked: catFlick.contentX = Math.max(0, catFlick.contentX - catFlick.width) }
                Flickable {
                    id: catFlick
                    x: 24.4; y: 5.4; width: parent.width - 48.8; height: 47.2
                    contentWidth: catRow.width; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Behavior on contentX { NumberAnimation { duration: 250 } }
                    Row {
                        id: catRow
                        padding: 2
                        Repeater {
                            model: panels.stickerCats
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: Math.max(72, catLabel.implicitWidth + 12); height: 40; radius: 8
                                y: 1.6
                                color: theme.pick(Qt.rgba(1, 1, 1, 0.5), Qt.rgba(1, 1, 1, 0.08), "#000000")
                                Text {
                                    id: catLabel
                                    anchors.centerIn: parent; text: parent.modelData.name
                                    font.family: theme.font; font.pixelSize: 14
                                    font.weight: parent.index === panels.stickerCat ? Font.DemiBold : Font.Normal
                                    color: parent.index === panels.stickerCat ? theme.text : theme.textSecondary
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { panels.stickerCat = parent.index; panels.stickerMore = parent.modelData.key } }
                                Accessible.role: Accessible.PageTab
                                Accessible.name: qsTr("%1 tab").arg(modelData.name)
                            }
                        }
                    }
                }
                NavButton { next: true; x: parent.width - 21.2; y: 9; height: 40; onClicked: catFlick.contentX = Math.min(Math.max(0, catFlick.contentWidth - catFlick.width), catFlick.contentX + catFlick.width) }
                Dots { anchors.horizontalCenter: parent.horizontalCenter; y: 52.6; pages: Math.max(1, Math.ceil(catFlick.contentWidth / Math.max(1, catFlick.width))); page: Math.round(catFlick.contentX / Math.max(1, catFlick.width)) }
            }
            Flickable {
                width: parent.width; height: 204
                contentHeight: stCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Column {
                    id: stCol
                    width: parent.width - 8
                    Repeater {
                        model: panels.stickerCats
                        delegate: Column {
                            required property var modelData
                            width: stCol.width
                            readonly property var all: (panels.stickersFound || panels.stickers)[modelData.key] || []
                            visible: all.length > 0 && (panels.stickerMore === "" || panels.stickerMore === modelData.key)
                            SectionHead { title: modelData.name; more: panels.stickerMore === "" && parent.all.length > 33; onSeeMore: panels.stickerMore = parent.modelData.key }
                            StickerGrid {
                                category: modelData.name
                                items: panels.stickerMore === "" ? parent.all.slice(0, 33) : parent.all
                                onPicked: it => panels.addSticker(it)
                            }
                        }
                    }
                    Text {
                        visible: !!panels.stickersFound && !Object.keys(panels.stickersFound).some(k => panels.stickersFound[k].length)
                        width: parent.width; topPadding: 16; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Your search had no results. Please try again.")
                        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                }
            }
        }
    }

    // ---- Filter, Frame, Board ----
    ClipDrawer {
        visible: panels.fx.drawer === "filter"
        title: qsTr("Filter")
        onClosed: panels.fx.drawer = ""
        Carousel {
            model: [{ clear: true }].concat(panels.catalog.filters)
            delegate: Tile {
                required property var modelData
                required property int index
                x: 2.4; clearTile: !!modelData.clear
                img: modelData.clear ? "" : panels.catalog.url(modelData.icon)
                label: modelData.clear ? qsTr("Clear filters") : modelData.name
                selected: panels.fx.filter === index - 1
                onClicked: panels.fx.filter = index - 1
            }
        }
    }
    ClipDrawer {
        visible: panels.fx.drawer === "frame"
        title: qsTr("Frame")
        onClosed: panels.fx.drawer = ""
        Carousel {
            model: [{ clear: true }].concat(panels.catalog.frames)
            delegate: Tile {
                required property var modelData
                required property int index
                clearTile: !!modelData.clear
                img: modelData.clear ? "" : panels.catalog.url(modelData.icon)
                label: modelData.clear ? qsTr("Clear frame") : modelData.name
                selected: panels.fx.frame === index - 1
                onClicked: panels.fx.frame = index - 1
            }
        }
    }
    ClipDrawer {
        visible: panels.fx.drawer === "board"
        title: qsTr("Board")
        onClosed: panels.fx.drawer = ""
        Column {
            width: parent.width
            Carousel {
                model: [{ clear: true }].concat(panels.catalog.boards)
                delegate: Tile {
                    required property var modelData
                    required property int index
                    clearTile: !!modelData.clear
                    img: modelData.clear ? "" : panels.catalog.url(modelData.icon)
                    label: modelData.clear ? qsTr("Clear boards") : modelData.name
                    selected: panels.fx.board === index - 1
                    onClicked: panels.fx.board = index - 1
                }
            }
            // The split, once a board is chosen.
            Column {
                width: parent.width
                topPadding: 8
                visible: panels.fx.board >= 0
                Text { text: qsTr("Split screen"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                FluentSlider {
                    width: parent.width
                    from: 0; to: 100; stepSize: 1
                    value: panels.fx.boardRatio * 100
                    onMoved: panels.fx.boardRatio = value / 100
                    Accessible.name: qsTr("The camera is %1 percent of the video viewport").arg(Math.round(value))
                    ToolTip.visible: pressed; ToolTip.text: Math.round(value) + "%"
                }
            }
        }
    }

    // ---- Draw ----
    ClipDrawer {
        visible: panels.fx.drawer === "draw"
        title: qsTr("Draw")
        drawerWidth: 480
        onClosed: panels.fx.drawer = ""
        Column {
            width: parent.width
            spacing: 4
            Text { x: 16; text: qsTr("Color picker"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            // Black, the hue wheel from 360 down to 0, white.
            Item {
                id: hue
                x: 16; width: parent.width - 32; height: 30
                Rectangle {
                    y: 10; width: parent.width; height: 10; radius: 5
                    border.color: "#FFFFFF"; border.width: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#000000" }
                        GradientStop { position: 0.07; color: Qt.hsla(1, 1, 0.5, 1) }
                        GradientStop { position: 0.22; color: Qt.hsla(300 / 360, 1, 0.5, 1) }
                        GradientStop { position: 0.36; color: Qt.hsla(240 / 360, 1, 0.5, 1) }
                        GradientStop { position: 0.5; color: Qt.hsla(180 / 360, 1, 0.5, 1) }
                        GradientStop { position: 0.64; color: Qt.hsla(120 / 360, 1, 0.5, 1) }
                        GradientStop { position: 0.78; color: Qt.hsla(60 / 360, 1, 0.5, 1) }
                        GradientStop { position: 0.93; color: Qt.hsla(0, 1, 0.5, 1) }
                        GradientStop { position: 1; color: "#FFFFFF" }
                    }
                }
                Rectangle {
                    x: panels.fx.inkValue * hue.width - 13.5; y: 1.5
                    width: 27; height: 27; radius: 13.5
                    color: panels.fx.inkColor(panels.fx.inkValue)
                    border.color: "#FFFFFF"; border.width: 3
                }
                MouseArea {
                    anchors.fill: parent
                    function pick(x) { panels.fx.inkValue = Math.max(0, Math.min(1, x / hue.width)) }
                    onPressed: m => pick(m.x)
                    onPositionChanged: m => pick(m.x)
                }
                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Color picker")
            }
            Text { x: 16; text: qsTr("Thickness"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            FluentSlider {
                x: 4; width: parent.width - 8
                from: 1; to: 60; stepSize: 1
                value: panels.fx.inkWidth
                onMoved: panels.fx.inkWidth = value
                Accessible.name: qsTr("%1 pixels").arg(Math.round(value))
                ToolTip.visible: pressed || hovered; ToolTip.text: Math.round(value) + "px"
            }
        }
    }

    // ---- Photo ----
    function addPhoto(url) {
        // As a sticker, 225 px wide on Stream's canvas (taller pictures:
        // 300 px tall), centred.
        fx.add({ kind: "image", src: url, sticker: false, cx: fx.pictureWidth / 2, cy: fx.pictureHeight / 2, w: 225 * fx.k, h: 225 * fx.k, fit: 225 * fx.k, fitTall: 300 * fx.k })
        fx.drawer = ""
    }
    FileDialog {
        id: photoDialog
        title: qsTr("Choose image file to upload")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.svg *.webp *.gif)")]
        onAccepted: { for (const f of selectedFiles) panels.addPhoto(f.toString()) }
    }
    ClipDrawer {
        visible: panels.fx.drawer === "photo"
        title: qsTr("Photo")
        drawerWidth: 680
        onClosed: panels.fx.drawer = ""
        Rectangle {
            width: parent.width; height: 360
            color: "transparent"
            border.color: theme.pick("#616161", "#ADADAD", "#FFFFFF"); border.width: 2.67
            Column {
                anchors.horizontalCenter: parent.horizontalCenter; y: 60; spacing: 6
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Add photo"); font.family: theme.font; font.pixelSize: 45; font.weight: Font.DemiBold; color: theme.text }
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "image-add-24"; size: 72; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Drop an image file or click to browse."); font.family: theme.font; font.pixelSize: 19; font.weight: Font.Bold; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("(PNG, JPG, and GIF formats supported)"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: photoDialog.open() }
            DropArea {
                anchors.fill: parent
                onDropped: d => { for (const u of d.urls) panels.addPhoto(u.toString()) }
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Choose image file to upload")
        }
    }

    // ---- Text menus ----
    readonly property var selText: fx.selected >= 0 && fx.selected < fx.items.length && fx.items[fx.selected].kind === "text" ? fx.items[fx.selected] : null
    function setText(p) { if (selText) fx.patch(fx.selected, p, true) }
    ColorDialog {
        id: customColor
        property string target
        onAccepted: {
            const c = selectedColor.toString()
            if (target === "fill") panels.setText({ fill: c })
            else if (target === "stroke") panels.strokeColor(c)
            else panels.setText({ bg: c, shadow: "" })
        }
    }
    function strokeColor(c) {
        if (!selText) return
        if (fx.textStyle(selText.style).shadow) setText({ shadow: c, stroke: "" })
        else setText({ stroke: c })
    }
    component Swatch: Rectangle {
        id: sw
        property string value
        property string label
        property bool remove: false
        property bool custom: false
        signal clicked()
        width: custom ? 60.8 : 72; height: 48; radius: 8
        color: remove || custom ? theme.pick("#FFFFFF", "#292929", "#000000") : value
        border.color: theme.stroke; border.width: remove || custom ? 0.67 : 0
        FluentIcon { visible: sw.remove; anchors.centerIn: parent; name: "prohibited-20"; size: 28; color: theme.text }
        Text { visible: sw.custom; anchors.centerIn: parent; text: qsTr("Custom"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
        HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sw.clicked() }
        ToolTip.visible: swh.hovered; ToolTip.delay: 300; ToolTip.text: sw.label
        Accessible.role: Accessible.MenuItem
        Accessible.name: sw.label
    }
    ClipDrawer {
        visible: panels.fx.drawer === "font"
        title: qsTr("Font")
        drawerWidth: 528
        onClosed: panels.fx.drawer = ""
        Flow {
            width: parent.width; spacing: 8
            Repeater {
                model: panels.fx.textStyles
                delegate: Rectangle {
                    required property var modelData
                    width: aa.implicitWidth + 32; height: 40; radius: 8
                    color: "#333333"
                    border.width: panels.selText && panels.selText.style === modelData.id ? 2 : 0
                    border.color: theme.hc("#242424", "#1AEBFF")
                    Text { id: aa; anchors.centerIn: parent; text: "Aa"; font.family: parent.modelData.family; font.pixelSize: 16; color: "#FFFFFF" }
                    HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const st = parent.modelData, t = panels.selText
                            if (!t) return
                            // The font changes the face and moves the colour
                            // between stroke and shadow as the style draws it.
                            const c = t.stroke || t.shadow
                            panels.setText({ style: st.id, stroke: st.shadow ? "" : (c || st.stroke), shadow: st.shadow ? (c || st.shadowColor) : "" })
                        }
                    }
                    ToolTip.visible: fh.hovered; ToolTip.delay: 300; ToolTip.text: modelData.name
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.name
                }
            }
        }
    }
    ClipDrawer {
        id: colorDrawer
        visible: panels.fx.drawer === "color" || panels.fx.drawer === "stroke" || panels.fx.drawer === "background"
        readonly property string which: panels.fx.drawer
        title: which === "color" ? qsTr("Color") : which === "background" ? qsTr("Text background") : panels.selText && panels.fx.textStyle(panels.selText.style).shadow ? qsTr("Text shadow") : qsTr("Text stroke")
        drawerWidth: 528
        onClosed: panels.fx.drawer = ""
        Flow {
            width: parent.width; spacing: 4.8
            Swatch {
                visible: colorDrawer.which !== "color"
                remove: true
                label: qsTr("Remove color")
                onClicked: { if (panels.fx.drawer === "background") panels.setText({ bg: "" }); else panels.setText({ stroke: "", shadow: "" }) }
            }
            Repeater {
                model: panels.fx.colors
                delegate: Swatch {
                    required property var modelData
                    value: modelData.value; label: modelData.name
                    onClicked: {
                        const w = panels.fx.drawer
                        if (w === "color") panels.setText({ fill: value })
                        else if (w === "stroke") panels.strokeColor(value)
                        else panels.setText({ bg: value, shadow: "" })
                    }
                }
            }
            Swatch {
                custom: true; label: qsTr("Custom")
                onClicked: { customColor.target = panels.fx.drawer === "color" ? "fill" : panels.fx.drawer; customColor.open() }
            }
        }
    }
}
