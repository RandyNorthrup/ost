import QtQuick
import QtQuick.Controls.Basic

// Teams' simplified compose (266342), measured on winpc. The same box is the
// chat's compose and the in-place editor of a message (Teams edits in place
// with this component).
// - The box: white, a 0.67 px NeutralStroke2 border, radius 6; focused, a
//   2 px brand line along its bottom.
// - Single-line state: the editor (padding 10 16 8 12, 14/20, min 38 tall)
//   with the side toolbar on its right: 32 px buttons 6.7 from the top, then
//   the send group (a 24 px divider 4 in, Send 8.7 in), 6.7 from the end.
// - Multiline state (the formatting bar open, a quote or files, or text over
//   one line): the editor across the box and a 44.7 px bottom toolbar with
//   the same buttons, 6 down, ending 6.7 from the right. While editing, the
//   send group is Cancel and Done.
// - The formatting bar (open with Format): 43 tall, 32 px buttons from
//   (6.7, 9.7) in groups 8.6 apart with a divider between; Discard (Cancel
//   while editing) at the end. The editor is then at least 104 tall.
// - Under the box, when it isn't empty: "Shift+Enter starts a new line."
//   (or "Enter starts a new line." with the bar open or Enter set to a new
//   line), 12/16, right-aligned 17 in; the key is a link to Settings.
// - Enter: Ctrl+Enter sends; Enter sends only with the Enter setting at its
//   default and the bar closed; Shift+Enter is a new line.
// - Cancelling an edit (or Discard) asks first: Teams' "Discard draft".
Item {
    id: root
    property bool editing: false
    property string placeholder: "Type a message"
    property var quote: null
    property var files: []
    property bool formatting: false
    // The Enter setting: "send" (Teams' Default) or "newline".
    property string enterKey: backend.setting("enterKey") || "send"
    readonly property alias editor: input
    readonly property bool empty: input.length === 0 && files.length === 0 && !quote
    // Once the text wraps the box stays multiline until it is empty again
    // (Teams 461103 / 458473).
    property bool grown: false
    // Editing always uses the multiline layout (Teams, measured).
    readonly property bool multiline: editing || formatting || files.length > 0 || !!quote || grown
    readonly property real boxHeight: multiline
        ? (formatting ? 43 : 0) + editorArea.height + 44.7
        : Math.max(45.3, input.contentHeight + 18 + 7.3)
    signal submit()
    signal cancelled()
    signal quoteDismissed()
    signal fileRemoved(string path)
    signal emojiRequested(Item anchor)
    signal attachRequested()
    signal typed()
    signal settingsRequested()
    width: 748
    height: boxHeight + 2 + 16

    function plainText() { return input.getText(0, input.length) }
    function formattedText() { return input.getFormattedText(0, input.length) }
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function setPlain(t) { input.clear(); if (t) input.insert(0, escapeHtml(t)) }
    function setHtml(h) { input.clear(); if (h) input.insert(0, h); input.cursorPosition = input.length }
    function clear() { input.clear() }
    function insertText(t) { input.insert(input.cursorPosition, t); input.forceActiveFocus() }
    function focusEditor() { input.forceActiveFocus() }
    function wrapSelection(tag) {
        const a = input.selectionStart, b = input.selectionEnd
        if (a === b) return
        const sel = escapeHtml(input.getText(a, b))
        input.remove(a, b)
        const html = tag === "ul" || tag === "ol" ? "<" + tag + "><li>" + sel.replace(/<br>/g, "</li><li>") + "</li></" + tag + ">"
            : "<" + tag + ">" + sel + "</" + tag + ">"
        input.insert(a, html)
        input.forceActiveFocus()
    }
    function requestCancel() { discardDialog.open() }

    Rectangle {
        id: box
        width: parent.width; height: root.boxHeight
        radius: 6
        color: theme.surface
        border.color: theme.divider
        border.width: 0.67
        clip: true

        // The formatting bar.
        Item {
            id: formatBar
            visible: root.formatting
            x: 0; y: 0; width: parent.width; height: 43
            Row {
                x: 6.7; y: 9.7
                spacing: 0
                Repeater {
                    model: [
                        [{ icon: "text-bold-20", tag: "b", label: "Bold" }, { icon: "text-italic-20", tag: "i", label: "Italic" },
                         { icon: "text-underline-20", tag: "u", label: "Underline" }, { icon: "text-strike-20", tag: "s", label: "Strikethrough" }],
                        [{ icon: "text-bullets-20", tag: "ul", label: "Bulleted list" }, { icon: "text-numbers-20", tag: "ol", label: "Numbered list" }]
                    ]
                    Row {
                        id: group
                        required property var modelData
                        required property int index
                        Item {
                            visible: group.index > 0
                            width: 8.6; height: 32
                            Rectangle { x: 4; y: 6; width: 1; height: 20; color: theme.stroke }
                        }
                        Repeater {
                            model: group.modelData
                            ToolButton32 {
                                required property var modelData
                                icon: modelData.icon; label: modelData.label
                                onClicked: root.wrapSelection(modelData.tag)
                            }
                        }
                    }
                }
            }
            ToolButton32 {
                x: parent.width - 6.7 - 32; y: 9.7
                icon: root.editing ? "dismiss-20" : "delete-20"
                label: root.editing ? "Cancel" : "Discard"
                onClicked: root.requestCancel()
            }
        }

        // The editor: across the box (multiline) or left of the side toolbar.
        Item {
            id: editorArea
            x: 0.67
            y: root.formatting ? 43 : 0.67
            width: root.multiline ? parent.width - 1.33 : parent.width - 1.33 - sideTools.width
            height: Math.max(root.formatting ? 104 : 38, quoteCard.visible ? 14.7 + quoteCard.height + 4 + input.contentHeight + 8 : input.contentHeight + 18)
            QuoteCard {
                id: quoteCard
                visible: !!root.quote
                x: 12.67; y: 14
                quote: root.quote
                dismissable: true
                maxWidth: editorArea.width - 28
                onDismissed: { root.quoteDismissed(); input.forceActiveFocus() }
            }
            Flow {
                id: fileChips
                visible: root.files.length > 0
                x: 12; y: (quoteCard.visible ? 14 + quoteCard.height + 4 : 10); width: parent.width - 28
                spacing: 8
                Repeater {
                    model: root.files
                    Rectangle {
                        required property string modelData
                        height: 40; width: Math.min(300, chipName.implicitWidth + 80)
                        radius: 8
                        color: theme.searchFill
                        border.color: theme.divider
                        FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 24; color: theme.textSecondary }
                        Text {
                            id: chipName
                            x: 40; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 76
                            text: parent.modelData.split("/").pop()
                            elide: Text.ElideMiddle
                            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                            color: theme.text
                        }
                        ToolButton32 {
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            icon: "dismiss-20"; label: "Remove " + parent.modelData.split("/").pop()
                            onClicked: root.fileRemoved(parent.modelData)
                        }
                    }
                }
            }
            TextEdit {
                id: input
                x: 12
                y: quoteCard.visible ? 14 + quoteCard.height + 4 : fileChips.visible ? fileChips.y + fileChips.height + 8 : 10
                width: parent.width - 12 - 16
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                selectByMouse: true
                persistentSelection: true
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                selectionColor: theme.selectionFill
                selectedTextColor: theme.text
                Text {
                    visible: input.length === 0 && !input.preeditText
                    text: root.placeholder
                    font: input.font; color: theme.textSecondary
                }
                onTextChanged: { if (length > 0) root.typed(); else root.grown = false }
                onLineCountChanged: if (lineCount > 1) root.grown = true
                onActiveFocusChanged: if (activeFocus) root.enterKey = backend.setting("enterKey") || "send"
                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    if (event.key === Qt.Key_B) { root.wrapSelection("b"); event.accepted = true }
                    else if (event.key === Qt.Key_I) { root.wrapSelection("i"); event.accepted = true }
                    else if (event.key === Qt.Key_U) { root.wrapSelection("u"); event.accepted = true }
                    else if (event.key === Qt.Key_X && (event.modifiers & Qt.ShiftModifier)) { root.formatting = !root.formatting; event.accepted = true }
                }
                Keys.onReturnPressed: event => root.enterPressed(event)
                Keys.onEnterPressed: event => root.enterPressed(event)
                Accessible.role: Accessible.EditableText
                Accessible.name: root.placeholder
            }
            TapHandler { onTapped: input.forceActiveFocus() }
        }

        // The toolbar buttons (side in single-line, bottom in multiline).
        Row {
            id: sideTools
            visible: !root.multiline
            x: parent.width - width - 6.7; y: 6.7
            Repeater { model: root.toolModel; delegate: toolDelegate }
            Item {
                width: 8.7 - 4 + 4; height: 32
                Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
            }
            Repeater { model: root.endModel; delegate: toolDelegate }
        }
        Item {
            id: bottomBar
            visible: root.multiline
            x: 0; y: parent.height - 44.7; width: parent.width; height: 44.7
            Row {
                x: parent.width - width - 6.7; y: 6
                Repeater { model: root.toolModel; delegate: toolDelegate }
                Item {
                    width: 8.7; height: 32
                    Rectangle { x: 4; y: 4; width: 1; height: 24; color: theme.stroke }
                }
                Repeater { model: root.endModel; delegate: toolDelegate }
            }
        }

        // Focused: Fluent's 2 px brand line along the bottom.
        Rectangle {
            visible: input.activeFocus
            x: 0; y: parent.height - 2; width: parent.width; height: 2
            color: theme.brand
        }
    }

    // The hint under the box.
    Row {
        visible: !root.empty
        anchors.right: parent.right; anchors.rightMargin: 17
        y: root.boxHeight + 2
        spacing: 4
        Text {
            text: root.formatting || root.enterKey === "newline" ? "Enter" : "Shift+Enter"
            font.family: theme.font; font.pixelSize: theme.small; color: theme.brandForeground1
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            HoverHandler { id: hintHover; cursorShape: Qt.PointingHandCursor }
            font.underline: hintHover.hovered
            TapHandler { onTapped: root.settingsRequested() }
            Accessible.role: Accessible.Link
            Accessible.name: "Select " + text + " to open settings"
        }
        Text {
            text: "starts a new line."
            font.family: theme.font; font.pixelSize: theme.small; color: theme.text
            lineHeight: 16; lineHeightMode: Text.FixedHeight
        }
    }

    // Toolbar items, in Teams' order (§15). Loop components and Actions and
    // apps are not built yet.
    readonly property var toolModel: [
        { id: "expand-compose", icon: "format-20", label: root.formatting ? "Hide Formatting options" : "Show Formatting options", pressed: root.formatting },
        { id: "UnifiedFunPicker", icon: "emoji-20", label: "Emoji, GIFs and Stickers" },
        { id: "FilePicker", icon: "attach-20", label: "Attach files (Alt+Shift+O)", hidden: root.editing }
    ].filter(t => !t.hidden)
    readonly property var endModel: root.editing
        ? [{ id: "discard-draft", icon: "dismiss-20", label: "Cancel" }, { id: "send", icon: "checkmark-20", label: "Done" }]
        : [{ id: "send", icon: "send-20", label: "Send", ready: !root.empty }]
    Component {
        id: toolDelegate
        ToolButton32 {
            id: tbd
            required property var modelData
            icon: modelData.id === "send" && !root.editing && modelData.ready ? "send-20-filled" : modelData.icon
            label: modelData.label
            pressedState: !!modelData.pressed
            accent: modelData.id === "send" && !root.editing && !!modelData.ready
            onClicked: root.toolClicked(modelData.id, tbd)
        }
    }
    function toolClicked(id, item) {
        if (id === "expand-compose") { formatting = !formatting; input.forceActiveFocus() }
        else if (id === "UnifiedFunPicker") root.emojiRequested(item)
        else if (id === "FilePicker") root.attachRequested()
        else if (id === "discard-draft") root.requestCancel()
        else if (id === "send") root.trySubmit()
    }
    function trySubmit() { if (!root.empty) root.submit() }
    function enterPressed(event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        const shift = event.modifiers & Qt.ShiftModifier
        if (ctrl) { root.trySubmit(); return }
        if (shift || root.enterKey === "newline" || root.formatting) { event.accepted = false; return }
        root.trySubmit()
    }

    // A 32 px Fluent subtle icon button: #424242, hover shows the filled
    // glyph in brand.
    component ToolButton32: Item {
        id: tb
        property string icon
        property string label
        property bool pressedState: false
        property bool accent: false
        signal clicked()
        width: 32; height: 32
        FluentIcon {
            anchors.centerIn: parent; size: 20
            name: tbHover.hovered || tb.pressedState ? tb.icon.replace(/-filled$/, "") + "-filled" : tb.icon
            color: tbHover.hovered || tb.pressedState || tb.accent ? theme.brand : theme.textStrong
        }
        HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        ToolTip {
            visible: tbHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: tb.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // Teams' "Discard draft" (messagedraft-discard-dialog): 600 x 156,
    // radius 8; the title 20/28 semibold at 24.7, Close, the text at 62,
    // Cancel and Discard (96 x 31.3) at y 100.
    Popup {
        id: discardDialog
        parent: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 156; padding: 0
        anchors.centerIn: Overlay.overlay
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: "#66000000" }
        Text { x: 24.7; y: 24.7; height: 28; verticalAlignment: Text.AlignVCenter; text: "Discard draft"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Rectangle {
            x: 543.3; y: 24.7; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: discardDialog.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Text { x: 22.7; y: 62; height: 32; verticalAlignment: Text.AlignVCenter; text: "You can discard your draft or cancel to keep editing"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        Row {
            x: 375.3; y: 100; spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: dCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: dCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); input.forceActiveFocus() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: discardHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Discard"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
                HoverHandler { id: discardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { discardDialog.close(); root.formatting = false; input.clear(); root.cancelled() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Discard"
            }
        }
    }
    // Test hooks.
    function discardForTest() { discardDialog.open() }
    function confirmDiscardForTest() { discardDialog.close(); root.formatting = false; input.clear(); root.cancelled() }
}
