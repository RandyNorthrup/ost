import QtQuick
import QtQuick.Controls.Basic

// Teams' emoji panel, shared by the reaction picker (reaction-picker-root,
// 317 x 372) and the compose fun picker's Emoji tab (432.3 tall there). It has:
// - "Find something fun" search (242 x 32, NeutralBackground3, 16 in) and
//   Customize default reactions beside it;
// - one scrolling list of sections from 56 down to the tabs: Recent, then
//   Teams' emoticon categories. Each heading is 14 px medium, over a 290 px
//   grid of 46 px buttons, six a row, with the 30 px emoticon in each. A 5 px
//   grey dot marks emoticons with skin tones;
// - 52 above the bottom a divider, then the category tabs (27.3 x 43.3). The
//   selected one is NeutralBackground1Pressed with its icon in brand.
// Emoticons with skin tones show in the preferred tone; right-clicking one
// opens the six tones (a 309.3 x 79.3 surface, padding 16, over the cell).
// One you already reacted with is "Undo {name}" and removes it.
// Picking an emoticon emits picked(key, on) and done().
Item {
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
        tonePicker.close(); root.done()
    }
    // Asks the host to close (a pick, or Customize).
    signal done()
    // In the compose fun picker.
    property bool compose: false
    // The org's Custom section, last (with Teams' Add emoji flow).
    property bool customSection: false
    signal addCustomEmoji()
    // Whether the host is open (the catalog loads only then).
    property bool active: false
    width: 317; height: 372

    readonly property var catalog: {
        backend.emoticonsVersion
        const t = root.active ? backend.emoticonCatalogJson() : ""
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
        const all = [{ id: "recent", title: "Recent", emoticons: recent }].concat(catalog)
        // Teams' "Your org's emoji" tab (customEmoji), headed "Custom": the
        // add button first, then the org's emoji, newest first.
        if (!root.customSection) return all
        const org = (backend.customEmojiJson ? JSON.parse(backend.customEmojiJson) : []).map(e => ({ id: e.id, description: e.shortcut, diverse: false, custom: true, creator_name: e.creator_name, created_on: e.created_on }))
        return all.concat([{ id: "customEmoji", title: "Custom", tip: "Your org's emoji", custom: true, org: org, emoticons: org.length ? (backend.customEmojiCanAdd ? [{ id: "", addCell: true }] : []).concat(org) : [] }])
    }
    onActiveChanged: if (active && customSection) backend.loadCustomEmoji()
    function reset() { query = ""; search.text = ""; list.positionViewAtBeginning(); search.forceActiveFocus() }

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
        TapHandler { onTapped: { root.done(); root.customize() } }
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
        x: 0; y: 56; width: root.width; height: root.height - 52 - 56
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
            // No org emoji yet: Teams' first-time block (287 x 284).
            readonly property bool emptyCustom: modelData.custom === true && modelData.emoticons.length === 0
            width: list.width
            height: topGap + (modelData.title ? 20 + 2 : 0) + (emptyCustom ? 284 : 15 + rows * 46 + 20)
            Item {
                visible: section.emptyCustom
                x: 15; y: section.topGap + 22; width: 287; height: 284
                Text {
                    x: 33.5; y: 38; width: 220
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    // Without creation rights Teams says it found nothing.
                    text: backend.customEmojiCanAdd ? "Add your own emoji that everyone in your org can use." : "We didn't find any matches."
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                }
                Rectangle {
                    visible: backend.customEmojiCanAdd
                    x: 33.5; y: 110; width: 220; height: 32; radius: 4
                    color: addHover.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: "Add emoji"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: "white" }
                    HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.addCustomEmoji() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Add emoji"
                }
            }
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
                        readonly property bool addCell: modelData.addCell === true
                        readonly property string shownId: addCell ? "" : root.shown(modelData)
                        width: 46; height: 46; radius: 4
                        color: cellHover.hovered || (tonePicker.opened && tonePicker.emoticon === modelData && tonePicker.cell === cell) ? theme.menuHover : "transparent"
                        Emoticon { visible: !cell.addCell; x: 8; y: 8; key: cell.shownId; named: "medium"; size: 30 }
                        // Teams' add entry point (custom-emoji-upload-entrypoint): a 30 px
                        // button with AddRegular, margin 8, tooltip "Add emoji".
                        FluentIcon { visible: cell.addCell; anchors.centerIn: parent; name: "add-20"; size: 20; color: cellHover.hovered ? theme.brand : theme.textStrong }
                        Rectangle {
                            visible: cell.modelData.diverse === true
                            x: 40.3; y: 0.6; width: 5; height: 5; radius: 2.5
                            color: "#B9B9B9"
                        }
                        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: cell.addCell ? root.addCustomEmoji() : root.choose(cell.shownId) }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            enabled: cell.modelData.diverse === true || cell.modelData.custom === true
                            onTapped: ev => cell.modelData.custom ? root.openCustomMenu(cell, cell.modelData, ev.position.x, ev.position.y) : tonePicker.openAt(cell, cell.modelData)
                        }
                        ToolTip {
                            visible: cellHover.hovered; delay: cell.addCell ? 500 : 1500
                            y: cell.height + 4; padding: 8
                            background: FluentSurface { depth: 16; radius: 4 }
                            contentItem: Text {
                                text: cell.addCell ? "Add emoji" : cell.modelData.custom ? cell.modelData.description + "\nShortcut: :" + cell.modelData.description + ":" : cell.modelData.description
                                font.family: theme.font; font.pixelSize: theme.small; color: theme.text
                            }
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: cell.addCell ? "Add emoji" : (root.myReaction(cell.shownId) ? "Undo " : "") + root.label(cell.modelData, cell.shownId) + (cell.modelData.custom ? ", has context menu" : "")
                    }
                }
            }
        }
    }

    // A custom emoji's menu (custom-emoji-context-menu-popover): "Delete
    // emoji for org." and, under a divider, "Created by {who} on {date}".
    property var customTarget: null
    function openCustomMenu(cell, e, px, py) {
        customTarget = e
        const p = cell.mapToItem(root, px, py)
        const who = e.creator_name || ""
        const when = e.created_on > 0 ? Qt.formatDate(new Date(e.created_on), "M/d/yyyy") : ""
        // Delete only where the policy allows it (Teams also for tenant admins).
        const del = backend.customEmojiCanDelete ? [{ key: "delete", label: "Delete emoji for org.", icon: "delete-20" }] : []
        const info = who && when ? [{ label: "Created by " + who + " on " + when, enabled: false }] : []
        customMenu.items = del.concat(del.length && info.length ? [{ separator: true }] : []).concat(info)
        if (customMenu.items.length === 0) return
        customMenu.x = Math.min(p.x, root.width - customMenu.implicitWidth - 4); customMenu.y = p.y
        customMenu.open()
    }
    MenuPopup {
        id: customMenu
        onPicked: i => { if (items[i].key === "delete") deleteDialog.open() }
    }
    Popup {
        id: deleteDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 440; padding: 24
        anchors.centerIn: parent
        background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
        Overlay.modal: Rectangle { color: "#66000000" }
        contentItem: Column {
            spacing: 24
            Text { width: 392; wrapMode: Text.Wrap; text: "Are you sure you want to delete it?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
            Row {
                anchors.right: parent.right; spacing: 8
                Rectangle {
                    width: 96; height: 31.3; radius: 4
                    color: dcHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                    HoverHandler { id: dcHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: deleteDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
                Rectangle {
                    width: 96; height: 31.3; radius: 4
                    color: ddHover.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: "Delete"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
                    HoverHandler { id: ddHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (root.customTarget) backend.deleteCustomEmoji(root.customTarget.id); deleteDialog.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Delete"
                }
            }
        }
    }
    // Test hook.
    function deleteCustomForTest(id) { backend.deleteCustomEmoji(id) }

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
            const p = c.mapToItem(root, 0, 0)
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

    Rectangle { x: 9; y: root.height - 52; width: 300; height: 1; color: theme.divider }
    Row {
        id: tabs
        property int current: 0
        visible: root.query.trim().length === 0
        x: 8.7; y: root.height - 47.7
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
                    contentItem: Text { text: tab.modelData.tip || tab.modelData.title; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.tip || modelData.title
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
