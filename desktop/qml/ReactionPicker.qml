import QtQuick
import QtQuick.Controls.Basic

// Teams' reaction picker (reaction-picker-root, measured in the client):
// 317 x 372. It has:
// - "Find something fun" search (242 x 32, NeutralBackground3, 16 in);
// - one scrolling list of sections from 56 to 320: Recent, then Teams'
//   emoticon categories. Each heading is 14 px medium, over a 290 px grid of
//   46 px buttons, six a row, with the 30 px emoticon in each. A 5 px grey dot
//   marks emoticons with skin tones;
// - under a divider, the category tabs (27.3 x 43.3). The selected one is
//   NeutralBackground1Pressed with its icon in brand.
// Emoticons with skin tones show in the preferred tone; right-clicking one
// opens the six tones (a 309.3 x 79.3 surface, padding 16, over the cell).
// One you already reacted with is "Undo {name}" and removes it.
// Picking an emoticon emits picked(key, on) and closes.
Popup {
    id: root
    property string messageId
    // Our reactions on the message (pills with mine set).
    property var mine: []
    // Choosing a default reaction (Customize): no customize button, no undo.
    property bool customizing: false
    signal picked(string key, bool on)
    signal customize()
    readonly property var toneNames: ["no", "light", "medium light", "medium", "medium dark", "dark"]
    function commonKey(id) { const m = /^(.{1,40})-tone\d$/.exec(id); return m ? m[1] : id }
    function toneOf(id) { const m = /-tone(\d)$/.exec(id); return m ? Number(m[1]) : 0 }
    function shown(e) { backend.skinTone; return e.diverse ? backend.emoticonToned(e.id) : e.id }
    function label(e, id) { return e.diverse ? e.description + " with " + toneNames[toneOf(id)] + " skin tone" : e.description }
    function myReaction(id) { return root.customizing ? undefined : root.mine.find(r => r.key === root.commonKey(id)) }
    // Test hook: the tones of an emoticon, as if its cell in Recent's first
    // row were right-clicked.
    function tonesForTest(id) {
        const e = root.byId[id]
        if (!e) return
        tonePicker.cell = null; tonePicker.emoticon = e
        tonePicker.x = 16 + 7.6; tonePicker.y = 56 + 10 + 22 + 15 + 46 - 65.4
        tonePicker.open()
    }
    function choose(id) {
        const r = myReaction(id)
        root.picked(r ? r.my_key : id, !r)
        tonePicker.close(); root.close()
    }
    width: 317; height: 372; padding: 0
    modal: false; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    readonly property var catalog: {
        backend.emoticonsVersion
        const t = root.opened ? backend.emoticonCatalogJson() : ""
        return t ? JSON.parse(t) : []
    }
    readonly property var byId: {
        const m = {}
        for (const c of catalog) for (const e of c.emoticons) m[e.id] = e
        return m
    }
    readonly property var recent: {
        const ids = backend.recentReactionsJson ? JSON.parse(backend.recentReactionsJson) : []
        return ids.map(id => root.byId[id] || { id: id, description: backend.emoticonName(id), diverse: false })
    }
    property string query: ""
    readonly property var sections: {
        if (query.trim().length > 0) {
            const q = query.trim().toLowerCase()
            const hits = []
            for (const c of catalog) for (const e of c.emoticons) {
                if (e.description.toLowerCase().indexOf(q) >= 0
                        || (e.keywords || []).some(k => k.toLowerCase().indexOf(q) >= 0)
                        || (e.shortcuts || []).some(k => k.toLowerCase().indexOf(q) >= 0))
                    hits.push(e)
            }
            return [{ id: "search", title: "", emoticons: hits }]
        }
        return [{ id: "recent", title: "Recent", emoticons: recent }].concat(catalog)
    }
    onOpened: { query = ""; search.text = ""; list.positionViewAtBeginning(); search.forceActiveFocus() }

    // Search (256.7 wide without the customize button).
    Rectangle {
        x: 16; y: 16; width: root.customizing ? 256.7 : 242; height: 32; radius: 4
        color: theme.inputFilled
        TextInput {
            id: search
            x: 10; width: parent.width - 10 - 32; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            clip: true
            onTextChanged: root.query = text
            Text {
                visible: !search.text
                text: "Find something fun"
                font: search.font; color: theme.textSecondary
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Search for emoji, GIFs or stickers"
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
    }

    // Customize default reactions (customize-reactions-trigger): 32 x 32 at
    // (269.7, 15.7).
    Rectangle {
        visible: !root.customizing
        x: 269.7; y: 15.7; width: 32; height: 32; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: custHover.hovered ? "emoji-edit-20-filled" : "emoji-edit-20"; color: custHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: custHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { root.close(); root.customize() } }
        ToolTip {
            visible: custHover.hovered; delay: 500
            y: parent.height + 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: "Customize default reactions"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Customize default reactions"
    }

    ListView {
        id: list
        x: 0; y: 56; width: root.width; height: 320 - 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.sections
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // The tab of the section at the top.
        onContentYChanged: {
            const i = indexAt(10, contentY + 4)
            if (i >= 0 && root.query.trim().length === 0) tabs.current = i
        }
        delegate: Item {
            id: section
            required property var modelData
            required property int index
            readonly property int rows: Math.ceil(modelData.emoticons.length / 6)
            readonly property real topGap: index === 0 ? 10 : 2
            width: list.width
            height: topGap + (modelData.title ? 20 + 2 : 0) + 15 + rows * 46 + 20
            Text {
                visible: !!section.modelData.title
                x: 16; y: section.topGap; height: 20; verticalAlignment: Text.AlignVCenter
                text: section.modelData.title
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.Medium; color: theme.text
                Accessible.role: Accessible.Heading
            }
            Grid {
                x: 16; y: section.topGap + (section.modelData.title ? 22 : 0) + 15
                columns: 6
                Repeater {
                    model: section.modelData.emoticons
                    Rectangle {
                        id: cell
                        required property var modelData
                        readonly property string shownId: root.shown(modelData)
                        width: 46; height: 46; radius: 4
                        color: cellHover.hovered || (tonePicker.opened && tonePicker.emoticon === modelData && tonePicker.cell === cell) ? theme.menuHover : "transparent"
                        Emoticon { x: 8; y: 8; key: cell.shownId; named: "medium"; size: 30 }
                        Rectangle {
                            visible: cell.modelData.diverse === true
                            x: 40.3; y: 0.6; width: 5; height: 5; radius: 2.5
                            color: "#B9B9B9"
                        }
                        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.choose(cell.shownId) }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            enabled: cell.modelData.diverse === true
                            onTapped: tonePicker.openAt(cell, cell.modelData)
                        }
                        ToolTip {
                            visible: cellHover.hovered; delay: 1500
                            y: cell.height + 4; padding: 8
                            background: FluentSurface { depth: 16; radius: 4 }
                            contentItem: Text { text: cell.modelData.description; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: (root.myReaction(cell.shownId) ? "Undo " : "") + root.label(cell.modelData, cell.shownId)
                    }
                }
            }
        }
    }

    // The skin tones of one emoticon (measured: 309.3 x 79.3, padding 16,
    // radius 4; 7.6 right of the cell and 65.4 above its top, so it covers
    // the cell's top edge).
    Popup {
        id: tonePicker
        property var emoticon: null
        property Item cell: null
        width: 309.3; height: 79.3; padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
        function openAt(c, e) {
            cell = c; emoticon = e
            const p = c.mapToItem(root.contentItem, 0, 0)
            x = Math.min(p.x + 7.6, root.width - width)
            y = p.y - 65.4
            open()
        }
        Row {
            x: 16.7; y: 16.7
            Repeater {
                model: tonePicker.emoticon ? 6 : 0
                Rectangle {
                    id: toneCell
                    required property int index
                    readonly property string toneId: tonePicker.emoticon ? (index === 0 ? tonePicker.emoticon.id : tonePicker.emoticon.id + "-tone" + index) : ""
                    width: 46; height: 46; radius: 4
                    color: toneHover.hovered ? theme.menuHover : "transparent"
                    Emoticon { x: 8; y: 8; key: toneCell.toneId; named: "medium"; size: 30 }
                    HoverHandler { id: toneHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.choose(toneCell.toneId) }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: tonePicker.emoticon ? root.label(tonePicker.emoticon, toneCell.toneId) : ""
                }
            }
        }
    }

    Rectangle { x: 9; y: 320; width: 300; height: 1; color: theme.divider }
    Row {
        id: tabs
        property int current: 0
        visible: root.query.trim().length === 0
        x: 8.7; y: 324.3
        Repeater {
            model: root.query.trim().length === 0 ? root.sections : []
            Rectangle {
                id: tab
                required property var modelData
                required property int index
                readonly property bool selected: tabs.current === index
                width: 27.3; height: 43.3; radius: 4
                color: selected ? theme.pressed : "transparent"
                CategoryIcon {
                    x: 3.6; y: 11.7
                    categoryId: tab.modelData.id
                    color: tab.selected || tabHover.hovered ? theme.brand : theme.textSecondary
                }
                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { list.positionViewAtIndex(tab.index, ListView.Beginning); tabs.current = tab.index } }
                ToolTip {
                    visible: tabHover.hovered; delay: 500
                    y: -height - 4; padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: tab.modelData.title; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.title
                Accessible.selected: selected
            }
        }
    }

    // A category's single-colour icon: the top half of Teams' 20 x 40 sprite,
    // recoloured.
    component CategoryIcon: Item {
        id: ci
        property string categoryId
        property color color
        width: 20; height: 20; clip: true
        property string svg: ""
        readonly property string file: { backend.emoticonsVersion; return backend.emoticonCategoryIcon(categoryId) }
        onFileChanged: if (file) {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() { if (xhr.readyState === XMLHttpRequest.DONE) ci.svg = xhr.responseText }
            xhr.open("GET", file); xhr.send()
        }
        Image {
            width: 20; height: 40
            sourceSize: Qt.size(40, 80)
            source: ci.svg ? "data:image/svg+xml;utf8," + encodeURIComponent(ci.svg.replace(/"black"/g, "\"" + ci.color.toString() + "\"")) : ""
        }
    }
}
