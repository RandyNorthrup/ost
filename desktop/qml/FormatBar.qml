import QtQuick
import QtQuick.Controls.Basic

// Teams' formatting bar (simplified-formatting-toolbar, measured on winpc):
// 43 tall; 32 px buttons from x 6, y 9; groups split by a divider in an
// 8.7 gap; what doesn't fit goes into More options (newMessageCommands-
// more-options), taken from the end, with no divider before the button;
// Discard (or Cancel when editing) at the end. Highlight, font colour and
// font size open Teams' popups above their button; Insert link its link
// popover; Rich style its Heading 1-3 / Paragraph menu.
Item {
    id: root
    height: 43
    /// What applies at the cursor (RichText.state).
    property var st: ({})
    property bool editing: false
    /// The selected text (Insert link's Text to display).
    property string selectedText: ""
    signal command(string op, string arg)
    signal discardRequested()
    signal undoRequested()
    signal redoRequested()

    readonly property string styleName: st.heading === 1 ? "Heading 1" : st.heading === 2 ? "Heading 2" : st.heading === 3 ? "Heading 3" : "Paragraph"
    readonly property var groups: [
        [{ k: "bold", icon: "fmt-bold", label: "Bold", on: !!st.bold }, { k: "italic", icon: "fmt-italic", label: "Italic", on: !!st.italic },
         { k: "underline", icon: "fmt-underline", label: "Underline", on: !!st.underline }, { k: "strike", icon: "fmt-strike", label: "Strikethrough", on: !!st.strike }],
        [{ k: "ul", icon: "fmt-bullets", label: "Bulleted list", on: st.list === "ul" }, { k: "ol", icon: "fmt-numbers", label: "Numbered list", on: st.list === "ol" }],
        [{ k: "highlight", icon: "fmt-highlight", label: "Text highlight color", popup: true }, { k: "color", icon: "fmt-font-color", label: "Font color", popup: true },
         { k: "size", icon: "fmt-font-size", label: "Font size", popup: true }],
        [{ k: "quote", icon: "fmt-quote", label: "Quote", on: !!st.quote }, { k: "link", icon: "fmt-link", label: "Insert link", popup: true },
         { k: "codeblock", icon: "fmt-code-block", label: "Code block", on: !!st.codeBlock }],
        [{ k: "rich", icon: "fmt-rich-style", label: root.styleName, wide: true, popup: true, menuLabel: root.styleName },
         { k: "code", icon: "fmt-inline-code", label: "Code", menuLabel: "Code (Ctrl+Shift+C)", on: !!st.code },
         { k: "clear", icon: "fmt-clear-format", label: "Clear all formatting" }],
        [{ k: "outdent", icon: "fmt-outdent", label: "Decrease indent" }, { k: "indent", icon: "fmt-indent", label: "Increase indent" }],
        [{ k: "hr", icon: "fmt-rule", label: "Insert horizontal rule" }],
        [{ k: "undo", icon: "fmt-undo", label: "Undo typing" }, { k: "redo", icon: "fmt-redo", label: "Repeat typing" }]
    ]
    // Teams' toolbar slot: the bar is a flex row whose column gap is
    // calc(100% − 49rem) from 640 wide (38.5rem from 480, 28rem from 240;
    // rem = 10 px), so the buttons get 490 − 32 (Discard) = 458 at 640 and
    // up (measured on winpc: 458 at 746.7).
    readonly property real slot: Math.min(width >= 640 ? 490 : width >= 480 ? 385 : 280, width) - 32
    // [{item, group, x}] shown, and the groups (lists of items) that go to
    // More options.
    readonly property var layout: {
        const shown = [], over = []
        let x = 6, full = false
        for (let g = 0; g < groups.length; g++) {
            const left = []
            for (let i = 0; i < groups[g].length; i++) {
                const it = groups[g][i]
                const w = it.wide ? 100 : 32
                const gap = i === 0 && g > 0 && !full ? 8.7 : 0
                const more = g < groups.length - 1 || i < groups[g].length - 1 ? 32 : 0
                if (!full && x + gap + w + more <= 6 + slot) {
                    shown.push({ item: it, group: g, x: x + gap, divider: gap > 0 })
                    x += gap + w
                } else {
                    full = true
                    left.push(it)
                }
            }
            if (left.length) over.push(left)
        }
        return { shown: shown, over: over, moreX: x }
    }

    function act(it, button) {
        if (it.popup) {
            if (it.k === "highlight") colors.show(button, true)
            else if (it.k === "color") colors.show(button, false)
            else if (it.k === "size") sizes.show(button)
            else if (it.k === "link") link.show(button)
            else if (it.k === "rich") styles.show(button, false)
            return
        }
        if (it.k === "undo") root.undoRequested()
        else if (it.k === "redo") root.redoRequested()
        else root.command(it.k === "quote" ? "quote" : it.k, "")
    }

    Repeater {
        model: root.layout.shown
        Item {
            id: slotItem
            required property var modelData
            x: modelData.x - (modelData.divider ? 8.7 : 0); y: 9
            width: (modelData.divider ? 8.7 : 0) + (modelData.item.wide ? 100 : 32); height: 32
            Rectangle { visible: slotItem.modelData.divider; x: 4; y: 6; width: 1; height: 20; color: theme.stroke }
            Rectangle {
                id: btn
                x: slotItem.modelData.divider ? 8.7 : 0
                width: slotItem.modelData.item.wide ? 100 : 32; height: 32; radius: 4
                readonly property bool on: !!slotItem.modelData.item.on
                color: "transparent"
                FluentIcon {
                    x: slotItem.modelData.item.wide ? 6 : 6; anchors.verticalCenter: parent.verticalCenter; size: 20
                    name: slotItem.modelData.item.icon
                    color: hover.hovered || btn.on ? theme.brand : theme.textStrong
                }
                Text {
                    visible: !!slotItem.modelData.item.wide
                    x: 30; anchors.verticalCenter: parent.verticalCenter
                    text: slotItem.modelData.item.label
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.act(slotItem.modelData.item, btn) }
                ToolTip {
                    visible: hover.hovered && !slotItem.modelData.item.wide; delay: 500
                    y: -height - 4; padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: slotItem.modelData.item.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.Button
                Accessible.name: slotItem.modelData.item.label
                Accessible.checked: on
            }
        }
    }
    // More options.
    Rectangle {
        id: moreBtn
        visible: root.layout.over.length > 0
        x: root.layout.moreX; y: 9; width: 32; height: 32; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: "fmt-more"; color: moreHover.hovered || overflow.opened ? theme.brand : theme.textStrong }
        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: overflow.show() }
        Accessible.role: Accessible.Button
        Accessible.name: "More options"
    }
    // Discard draft (Cancel when editing).
    Rectangle {
        x: root.width - 6 - 32; y: 9; width: 32; height: 32; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: root.editing ? "dismiss-20" : "fmt-discard"; color: discardHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: discardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.discardRequested() }
        Accessible.role: Accessible.Button
        Accessible.name: root.editing ? "Cancel" : "Discard"
    }

    // The overflow menu: 247 wide, 8 above and below; 32 px rows (Rich
    // style 34.3), a 16 px icon at 15.7 and the label at 41.7 (14/20);
    // groups split by dividers (16.7).
    Popup {
        id: overflow
        parent: Overlay.overlay
        width: 247; padding: 0
        height: Math.min(306, menuCol.height + 16)
        // Measured: its left at the button's, its bottom at the button's top.
        function show() {
            const p = moreBtn.mapToItem(Overlay.overlay, 0, 0)
            x = Math.max(8, Math.min(Overlay.overlay.width - width - 8, p.x))
            y = Math.max(8, p.y - height)
            open()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Flickable {
            anchors.fill: parent; anchors.topMargin: 8; anchors.bottomMargin: 8
            contentHeight: menuCol.height; clip: true
            Column {
                id: menuCol
                width: 247
                Repeater {
                    model: root.layout.over
                    Column {
                        id: grp
                        required property var modelData
                        required property int index
                        Item {
                            visible: grp.index > 0
                            width: 247; height: 16.7
                            Rectangle { x: 0; y: 8; width: 247; height: 1; color: theme.stroke }
                        }
                        Repeater {
                            model: grp.modelData
                            Rectangle {
                                id: row
                                required property var modelData
                                width: 245.3; x: 0.7
                                height: modelData.wide ? 34.3 : 32
                                color: rowHover.hovered ? theme.menuHover : "transparent"
                                FluentIcon {
                                    x: 15.7; anchors.verticalCenter: parent.verticalCenter
                                    size: row.modelData.wide ? 20 : 16
                                    name: row.modelData.icon
                                    color: row.modelData.on ? theme.brand : theme.textStrong
                                }
                                Text {
                                    x: row.modelData.wide ? 45.7 : 41.7; anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.menuLabel || row.modelData.label
                                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                                }
                                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (row.modelData.k === "rich") { styles.show(row, true); return }
                                        overflow.close()
                                        root.act(row.modelData, moreBtn)
                                    }
                                }
                                Accessible.role: Accessible.MenuItem
                                Accessible.name: row.modelData.menuLabel || row.modelData.label
                            }
                        }
                    }
                }
            }
        }
    }

    // Highlight / Font color: 125.3 x 101.7 over the button; "No highlight"
    // or "Automatic" (100 x 24.3), then eight 16 px swatches, 28 apart.
    Popup {
        id: colors
        parent: Overlay.overlay
        property bool highlight: true
        width: 125.3; height: 101.7; padding: 0
        readonly property var swatches: highlight
            ? [["#DF9299", "Kobi red"], ["#F4A593", "Rose bud"], ["#FDD472", "Goldenrod"], ["#E5F18F", "Primrose"],
               ["#82CDA8", "Mantis"], ["#9DD9DB", "Regent St. blue"], ["#C7D4E8", "Periwinkle gray"], ["#EBD3E1", "Pale rose"]]
            : [["#B6424C", "Red"], ["#CD5937", "Tuscan orange"], ["#FDC030", "Sunglow"], ["#BDCB4C", "Pear"],
               ["#2B9B62", "Eucalyptus"], ["#37797B", "Faded jade"], ["#1E53A3", "Fun blue"], ["#A5397A", "Tyrian purple"]]
        function show(button, hl) {
            highlight = hl
            const p = button.mapToItem(Overlay.overlay, button.width / 2, 0)
            x = p.x - width / 2; y = p.y - height
            open()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Rectangle {
            x: 12.7; y: 8.7; width: 100; height: 24.3; radius: 4
            color: noneHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
            Text { anchors.centerIn: parent; text: colors.highlight ? "No highlight" : "Automatic"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            HoverHandler { id: noneHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { colors.close(); root.command(colors.highlight ? "bg" : "fg", "") } }
            Accessible.role: Accessible.Button
            Accessible.name: colors.highlight ? "No highlight" : "Automatic"
        }
        Repeater {
            model: colors.swatches
            Rectangle {
                required property var modelData
                required property int index
                x: 12.7 + (index % 4) * 28; y: 45 + Math.floor(index / 4) * 28
                width: 16; height: 16; radius: 4
                color: modelData[0]
                border.color: "#33252424"; border.width: 0.67
                HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { colors.close(); root.command(colors.highlight ? "bg" : "fg", parent.modelData[0]) } }
                ToolTip.visible: swHover.hovered
                ToolTip.text: modelData[1]
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData[1]
            }
        }
    }

    // Font size (compose-font-size): 104.8 wide, 8/4 in; Large, Medium,
    // Small rows 91.5 x 28, 32 apart, the label at 12.
    Popup {
        id: sizes
        parent: Overlay.overlay
        width: 104.8; height: 113.3; padding: 0
        function show(button) {
            const p = button.mapToItem(Overlay.overlay, button.width / 2, 0)
            x = p.x - width / 2; y = p.y - height
            open()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Repeater {
            model: [["Large", "24"], ["Medium", ""], ["Small", "13"]]
            Rectangle {
                required property var modelData
                required property int index
                x: 6.7; y: 10.7 + index * 32; width: 91.5; height: 28; radius: 4
                color: szHover.hovered ? theme.menuHover : "transparent"
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                HoverHandler { id: szHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { sizes.close(); root.command("size", parent.modelData[1]) } }
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData[0]
            }
        }
    }

    // Rich style: Heading 1 (18 light), Heading 2 (14 bold), Heading 3 (12
    // bold), Paragraph; 130.4 wide, rows 117 wide from 6.7, #424242.
    Popup {
        id: styles
        parent: Overlay.overlay
        width: 130.4; height: 150.3; padding: 0
        function show(item, beside) {
            const p = item.mapToItem(Overlay.overlay, 0, 0)
            // Measured beside the More menu: 1 right of the row, 58 above it.
            if (beside) { x = p.x + item.width + 1; y = p.y - 58.1 }
            else { x = p.x; y = p.y - height - 4 }
            x = Math.min(Overlay.overlay.width - width - 8, x)
            open()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Repeater {
            model: [{ t: "Heading 1", l: 1, s: 18, w: Font.Light, y: 10.7, h: 33 }, { t: "Heading 2", l: 2, s: 14, w: Font.Bold, y: 47.7, h: 28 },
                    { t: "Heading 3", l: 3, s: 12, w: Font.Bold, y: 79.7, h: 28 }, { t: "Paragraph", l: 0, s: 14, w: Font.Normal, y: 111.7, h: 28 }]
            Rectangle {
                required property var modelData
                x: 6.7; y: modelData.y; width: 117; height: modelData.h; radius: 4
                color: stHover.hovered ? theme.menuHover : "transparent"
                Text {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.t
                    font.family: theme.font; font.pixelSize: parent.modelData.s; font.weight: parent.modelData.w
                    color: theme.pick("#424242", "#D6D6D6")
                }
                HoverHandler { id: stHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { styles.close(); overflow.close(); root.command("heading", String(parent.modelData.l)) } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: modelData.t
            }
        }
    }

    // Insert link (newMessageCommands-popup-InsertHyperlink-content):
    // 303.3 x 262.7 over the button; Text to display and Address (270 x 32,
    // #F5F5F5, rounded 4); Cancel and Insert (96 x 31.3).
    Popup {
        id: link
        parent: Overlay.overlay
        width: 303.3; height: 262.7; padding: 0
        modal: false; focus: true
        function show(button) {
            const p = button.mapToItem(Overlay.overlay, button.width / 2, 0)
            x = Math.max(8, p.x - width / 2); y = Math.max(8, p.y - height)
            shown.text = root.selectedText
            address.text = ""
            open();
            const target = shown.text ? address : shown
            target.forceActiveFocus()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text { x: 16.7; y: 17.3; text: "Insert link"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Text { x: 16.7; y: 44.7; height: 20; verticalAlignment: Text.AlignVCenter; text: "Text to display"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Rectangle {
            x: 16.7; y: 68.7; width: 270; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#1F1F1F")
            TextInput {
                id: shown
                x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                Text { visible: !shown.text; text: "Text to display"; font: shown.font; color: theme.textSecondary }
            }
            Rectangle { visible: shown.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        }
        Text { x: 16.7; y: 120.7; height: 20; verticalAlignment: Text.AlignVCenter; text: "Address"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Rectangle {
            x: 16.7; y: 144.7; width: 270; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#1F1F1F")
            TextInput {
                id: address
                x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                Text { visible: !address.text; text: "Link to an existing file or web page"; font: address.font; color: theme.textSecondary }
                Keys.onReturnPressed: link.insert()
            }
            Rectangle { visible: address.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        }
        // Teams accepts web addresses; one without a scheme gets https://.
        readonly property string href: {
            const a = address.text.trim()
            if (!a) return ""
            return /^https?:\/\//i.test(a) ? a : "https://" + a
        }
        function insert() {
            if (!href) return
            close()
            root.command("link", href + "\t" + shown.text.trim())
        }
        Row {
            x: 86.7; y: 208.7; spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: lcHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: lcHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: link.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
            Rectangle {
                readonly property bool can: link.href !== ""
                width: 96; height: 31.3; radius: 4
                color: !can ? theme.pick("#F0F0F0", "#141414") : liHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Insert"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.pick("#BDBDBD", "#5C5C5C") }
                HoverHandler { id: liHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: parent.can; onTapped: link.insert() }
                Accessible.role: Accessible.Button
                Accessible.name: "Insert"
            }
        }
    }
    // Test hooks.
    function openOverflowForTest() { overflow.show() }
    function openColorsForTest(hl) { colors.show(moreBtn, hl) }
}
