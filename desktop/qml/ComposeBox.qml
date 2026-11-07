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
    // Teams' delivery option for the next message: "", "high" or "urgent";
    // offered outside channels, Urgent only up to 20 members.
    property string importance: ""
    property bool deliveryOptions: true
    property bool urgentAllowed: true
    signal scheduleMeetingRequested()
    // People who can be @mentioned here (the chat's members): [{mri, name, mail}].
    property var mentionables: []
    // Whether the picker also searches the directory (1:1 chats and
    // channels; group chats suggest their members, as Teams does).
    property bool mentionDirectory: true
    // Everyone (group chats): the conversation id, and how many are in it
    // (Teams: up to 250; two or fewer get plain text).
    property string everyoneId: ""
    // In a channel: the channel and its team, mentionable as Teams' channel
    // picker offers them ({id, name}; the team's id is its thread id).
    property var channelMention: null
    property var teamMention: null
    property int memberCount: 0
    // The Enter setting: "send" (Teams' Default) or "newline".
    property string enterKey: backend.setting("enterKey") || "send"
    readonly property alias editor: input
    readonly property bool empty: input.length === 0 && files.length === 0 && !quote
    // Once the text wraps the box stays multiline until it is empty again
    // (Teams 461103 / 458473).
    property bool grown: false
    // Editing always uses the multiline layout (Teams, measured).
    readonly property bool multiline: editing || formatting || files.length > 0 || !!quote || grown
    // The delivery header ("IMPORTANT!") is 26 tall above the editor.
    readonly property real headerH: importance ? 26 : 0
    readonly property real boxHeight: headerH + (multiline
        ? (formatting ? 43 : 0) + editorArea.height + 44.7
        : Math.max(45.3, input.contentHeight + 18 + 7.3))
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
    function clear() { input.clear(); media = [] }
    // One of your messages to edit: its edit form keeps the emoticons,
    // custom emoji and pictures (as Teams' edit does); else its text.
    function setMessage(m) {
        media = m.edit_media || []
        setHtml(m.edit_html || m.html || escapeHtml(m.text || ""))
    }
    function insertText(t) { input.insert(input.cursorPosition, t); input.forceActiveFocus() }
    // What the fun picker put in: [{src, kind, id, title, unicode, url, width,
    // height}], each shown as an <img> with that src and sent in Teams' form.
    property var media: []
    function insertMedia(m) {
        media = media.concat([m])
        // As the compose box shows them: emoticons in the line (20), GIFs
        // fitted to 444 x 250 (as sent), stickers at 180.
        let w = 20, h = 20
        if (m.kind === "gif") {
            const s = Math.min(1, 444 / Math.max(1, m.width), 250 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        } else if (m.kind === "sticker") { w = 180; h = 180 }
        else if (m.kind === "image") {
            const s = Math.min(1, 240 / Math.max(1, m.width), 180 / Math.max(1, m.height))
            w = Math.floor(m.width * s); h = Math.round(m.height * s)
        }
        input.insert(input.cursorPosition, "<img src=\"" + m.src + "\" width=\"" + w + "\" height=\"" + h + "\">")
        input.forceActiveFocus()
    }
    // The picked items still in the text.
    function mediaInUse() {
        const html = input.getFormattedText(0, input.length)
        return media.filter(m => html.indexOf(m.src) >= 0)
    }
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

        // The delivery option header (measured): 14/20 bold uppercase,
        // DarkOrange foreground for Important, 16 in, 26 tall.
        Text {
            visible: !!root.importance
            x: 16.7; y: 3; height: 20; verticalAlignment: Text.AlignVCenter
            text: root.importance === "urgent" ? "URGENT!" : "IMPORTANT!"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
            color: root.importance === "urgent" ? theme.redForeground3 : theme.pick("#DA3B01", "#E9835E")
        }
        // The formatting bar.
        Item {
            id: formatBar
            visible: root.formatting
            x: 0; y: root.headerH; width: parent.width; height: 43
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
            y: root.headerH + (root.formatting ? 43 : 0.67)
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
                onTextChanged: { if (length > 0) root.typed(); else root.grown = false; root.checkMention() }
                onCursorPositionChanged: root.checkMention()
                onLineCountChanged: if (lineCount > 1) root.grown = true
                onActiveFocusChanged: if (activeFocus) root.enterKey = backend.setting("enterKey") || "send"
                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    if (event.key === Qt.Key_B) { root.wrapSelection("b"); event.accepted = true }
                    else if (event.key === Qt.Key_I) { root.wrapSelection("i"); event.accepted = true }
                    else if (event.key === Qt.Key_U) { root.wrapSelection("u"); event.accepted = true }
                    else if (event.key === Qt.Key_X && (event.modifiers & Qt.ShiftModifier)) { root.formatting = !root.formatting; event.accepted = true }
                    else if (event.key === Qt.Key_I && (event.modifiers & Qt.ShiftModifier) && root.deliveryOptions) { root.importance = root.importance === "high" ? "" : "high"; event.accepted = true }
                }
                Keys.onReturnPressed: event => { if (mentionPicker.opened) { mentionPicker.pick(); return } root.enterPressed(event) }
                Keys.onEnterPressed: event => { if (mentionPicker.opened) { mentionPicker.pick(); return } root.enterPressed(event) }
                Keys.onTabPressed: event => { if (mentionPicker.opened) mentionPicker.pick(); else event.accepted = false }
                Keys.onUpPressed: event => { if (mentionPicker.opened) mentionPicker.move(-1); else event.accepted = false }
                Keys.onDownPressed: event => { if (mentionPicker.opened) mentionPicker.move(1); else event.accepted = false }
                Keys.onEscapePressed: event => { if (mentionPicker.opened) mentionPicker.close(); else event.accepted = false }
                Accessible.role: Accessible.EditableText
                Accessible.name: root.placeholder
            }
            TapHandler { onTapped: input.forceActiveFocus() }
        }

        // The toolbar buttons (side in single-line, bottom in multiline).
        Row {
            id: sideTools
            visible: !root.multiline
            x: parent.width - width - 6.7; y: root.headerH + 6.7
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
        { id: "FilePicker", icon: "attach-20", label: "Attach files (Alt+Shift+O)", hidden: root.editing },
        { id: "message-extension-flyout-command", icon: "add-20", label: "Actions and apps", hidden: root.editing }
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
        else if (id === "message-extension-flyout-command") { plusFlyout.anchorItem = item; plusFlyout.open() }
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

    // "+" Actions and apps (measured): 341.3 wide, a search box, then Teams'
    // own items as 36 px rows (20 px icon 8 in, the label at 40). Installed
    // apps' actions are not built yet.
    Popup {
        id: plusFlyout
        property Item anchorItem: null
        parent: Overlay.overlay
        width: 341.3; padding: 0
        height: 62.7 + itemsCol.height + 14.7
        x: anchorItem ? Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width) : 0
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 8 : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onOpened: { search.text = ""; search.forceActiveFocus() }
        readonly property var items: [
            { key: "delivery", label: "Set delivery options", icon: "important-20", hidden: !root.deliveryOptions },
            { key: "meeting", label: "Schedule meeting", icon: "calendar-add-20" }
        ].filter(i => !i.hidden && i.label.toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0)
        Rectangle {
            x: 14.7; y: 17.3; width: 310; height: 30.7; radius: 4
            color: theme.surface
            border.color: search.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0.67; color: search.activeFocus ? theme.brand : theme.textSecondary }
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
            TextInput {
                id: search
                x: 34.6; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !search.text; text: "Search for apps"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search for apps"
            }
        }
        Column {
            id: itemsCol
            x: 14.7; y: 62.7
            Repeater {
                model: plusFlyout.items
                Rectangle {
                    required property var modelData
                    width: 310; height: 36; radius: 4
                    color: rowHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 8; y: 8; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            plusFlyout.close()
                            if (parent.modelData.key === "delivery") { deliveryPopup.anchorItem = plusFlyout.anchorItem; deliveryPopup.open() }
                            else root.scheduleMeetingRequested()
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }
    }
    // Delivery options (measured): 317.3 x 161.3; 48 px options with a 16 px
    // icon at (16, 18.3), the title 14/18.7 and description 12/16 at 40.7,
    // the selected one NeutralBackground1Hover with a checkmark at 284.
    Popup {
        id: deliveryPopup
        property Item anchorItem: null
        parent: Overlay.overlay
        width: 317.3; height: 161.3; padding: 0
        x: anchorItem ? Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width + 50) : 0
        y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 8 : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 0.7; y: 8.7
            Repeater {
                model: [
                    { key: "", title: "Standard", desc: "Message will be sent as usual", icon: "chat-20", color: "", name: "Standard Message Delivery" },
                    { key: "high", title: "Important", desc: "Message will be marked as important", icon: "important-20", color: "#C4314B", name: "Mark message as important" },
                    { key: "urgent", title: "Urgent", desc: root.urgentAllowed ? "Recipient notified every 2 min for 20 min" : "Unavailable in chats with more than 20 people", icon: "alert-urgent-20", color: "#C4314B", name: "Mark message as urgent and repeatedly notify recipient every 2 minutes for 20 minutes" }
                ]
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool selected: root.importance === modelData.key
                    readonly property bool enabledNow: modelData.key !== "urgent" || root.urgentAllowed
                    width: 316; height: 48
                    color: selected || (optHover.hovered && enabledNow) ? theme.menuHover : "transparent"
                    FluentIcon {
                        x: opt.modelData.key === "urgent" ? 20 : 16; y: 16; size: 16
                        name: opt.modelData.icon
                        color: !opt.enabledNow ? theme.disabled : opt.modelData.color || theme.text
                    }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 6.6; text: opt.modelData.title; font.family: theme.font; font.pixelSize: 14; color: opt.enabledNow ? theme.text : theme.disabled }
                    Text { x: opt.modelData.key === "urgent" ? 44.7 : 40.7; y: 25.3; text: opt.modelData.desc; font.family: theme.font; font.pixelSize: 12; color: opt.enabledNow ? theme.text : theme.disabled }
                    FluentIcon { visible: opt.selected; x: 284; y: 16; name: "checkmark-20"; size: 16; color: theme.text }
                    HoverHandler { id: optHover; cursorShape: opt.enabledNow ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: opt.enabledNow; onTapped: { root.importance = opt.modelData.key; deliveryPopup.close(); input.forceActiveFocus() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                }
            }
        }
    }
    // @mentions (930187, measured): typing "@" at a word start opens Teams'
    // picker over the caret; picking inserts the name, each word its own
    // mention token in BrandForeground1, then a space.
    property int mentionAt: -1
    property string mentionQuery: ""
    function checkMention() {
        const pos = input.cursorPosition
        const before = input.getText(0, pos)
        const at = before.lastIndexOf("@")
        const q = at >= 0 ? before.slice(at + 1) : ""
        const ok = at >= 0 && (at === 0 || /\s/.test(before[at - 1])) && !/[\n\u2029]/.test(q) && q.length <= 40 && (q.match(/ /g) || []).length <= 2
        if (!ok) { mentionAt = -1; if (mentionPicker.opened) mentionPicker.close(); return }
        mentionAt = at; mentionQuery = q
        if (q.trim().length >= 2 && root.mentionDirectory) backend.searchPeople(q.trim())
        if (!mentionPicker.opened) mentionPicker.open()
        mentionPicker.current = 0
    }
    function insertMention(person) {
        if (mentionAt < 0) return
        if (person.kind === "share") {
            // Teams' "Share someone's contact info": the "@" and what
            // follows it go; the dialog puts the cards in.
            shareAt = mentionAt; shareEnd = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            shareContact.start()
            return
        }
        if (person.kind === "team" || person.kind === "channel") {
            const at1 = mentionAt, end1 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at1, end1)
            input.insert(at1, '<a href="mention-' + person.kind + ':' + person.mri + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">' + escapeHtml(person.name) + '</a>&nbsp;')
            input.cursorPosition = at1 + person.name.length + 1
            input.forceActiveFocus()
            return
        }
        if (person.everyone) {
            const at0 = mentionAt, end0 = input.cursorPosition
            mentionAt = -1; mentionPicker.close()
            input.remove(at0, end0)
            input.insert(at0, root.memberCount > 2 ? '<a href="mention-everyone:' + root.everyoneId + '" style="color:' + theme.brandForeground1 + '; text-decoration:none">Everyone</a>&nbsp;' : "Everyone&nbsp;")
            input.cursorPosition = at0 + 9
            input.forceActiveFocus()
            return
        }
        const words = String(person.name || "").split(/\s+/).filter(w => w)
        const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
        const html = words.map(w => '<a href="mention:' + person.mri + '" ' + style + '>' + escapeHtml(w) + '</a>').join("&nbsp;") + "&nbsp;"
        const at = mentionAt, end = input.cursorPosition
        mentionAt = -1
        mentionPicker.close()
        input.remove(at, end)
        input.insert(at, html)
        input.cursorPosition = at + words.join(" ").length + 1
        mentionPicker.close()
        input.forceActiveFocus()
    }
    Popup {
        id: mentionPicker
        parent: Overlay.overlay
        width: 300; padding: 0
        height: Math.min(310.3, 43.2 + rowsCol.height + 8)
        closePolicy: Popup.CloseOnPressOutside
        focus: false
        property int current: 0
        readonly property var people: {
            const q = root.mentionQuery.trim().toLowerCase()
            const fromRoster = root.mentionables.filter(p => !q || (p.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q)) || (p.name || "").toLowerCase().startsWith(q) || (p.mail || "").toLowerCase().startsWith(q))
            const found = q.length >= 2 && root.mentionDirectory ? (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).map(p => ({ mri: "8:orgid:" + p.id, name: p.name, mail: p.mail || p.email || "" })) : []
            const out = []
            // A channel's team and the channel itself (Teams' channel
            // picker): by a word of their name, or by "team" / "channel".
            const words = n => (n || "").toLowerCase().split(/\s+/)
            const t = root.teamMention, c = root.channelMention
            if (q && t && (words(t.name).some(w => w.startsWith(q)) || t.name.toLowerCase().startsWith(q) || "team".startsWith(q)))
                out.push({ kind: "team", mri: t.id, name: t.name, mail: "Team", photoId: t.groupId })
            if (q && c && (words(c.name).some(w => w.startsWith(q)) || c.name.toLowerCase().startsWith(q) || "channel".startsWith(q)))
                out.push({ kind: "channel", mri: c.id, name: c.name, mail: "Channel", photoId: t ? t.groupId : "" })
            for (const p of fromRoster) out.push(p)
            for (const p of found) if (!out.some(o => o.mri === p.mri)) out.push(p)
            // Everyone, in group chats up to 250 people.
            if (root.everyoneId && root.memberCount <= 250 && (!q || "everyone".startsWith(q)))
                out.push({ everyone: true, name: "Everyone", mail: "Notify everyone in the chat" })
            const rows = out.slice(0, 20)
            // Always last (Teams): share someone's contact card.
            rows.push({ kind: "share", name: "Share someone\u2019s contact info", mail: "" })
            return rows
        }
        function move(d) { if (people.length) current = (current + d + people.length) % people.length }
        function pick() { if (people.length) root.insertMention(people[Math.max(0, Math.min(current, people.length - 1))]); else close() }
        readonly property rect caret: input.cursorRectangle
        x: { const p = input.mapToItem(Overlay.overlay, input.positionToRectangle(Math.max(0, root.mentionAt)).x, 0); return Math.min(Overlay.overlay.width - width - 8, Math.max(8, p.x)) }
        y: { const p = input.mapToItem(Overlay.overlay, 0, input.positionToRectangle(Math.max(0, root.mentionAt)).y); return Math.max(8, p.y - height - 1) }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text {
            x: 20.7; y: 10.7; height: 20; verticalAlignment: Text.AlignVCenter
            text: "Suggestions"
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
        }
        Column {
            id: rowsCol
            x: 0.7; y: 43.2
            Repeater {
                model: mentionPicker.people
                Rectangle {
                    id: prow
                    required property var modelData
                    required property int index
                    width: 298.7; height: modelData.kind === "share" ? 49.3 : 47.3
                    color: index === mentionPicker.current ? theme.pick("#E6E6E6", "#3D3D3D") : prowHover.hovered ? theme.menuHover : "transparent"
                    Avatar { visible: !prow.modelData.everyone && !prow.modelData.kind; x: 19.6; y: 7.6; size: 32; name: prow.modelData.name; photoId: prow.modelData.mri || "" }
                    // A team or channel: the team's picture, a 4 px square.
                    Avatar {
                        visible: prow.modelData.kind === "team" || prow.modelData.kind === "channel"
                        x: 19.6; y: 7.6; size: 32; square: true
                        readonly property string team: root.teamMention ? root.teamMention.name : ""
                        name: team
                        initialsText: team.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: prow.modelData.photoId ? "team:" + prow.modelData.photoId : ""
                    }
                    FluentIcon { visible: !!prow.modelData.everyone; x: 25.6; y: 13.6; name: "people-20"; size: 20; color: theme.textStrong }
                    // Share someone's contact info: the contact card icon (20).
                    FluentIcon { visible: prow.modelData.kind === "share"; x: 19.6; y: 14.6; name: "contact-card-20"; size: 20; color: theme.textStrong }
                    // The typed part in bold (Teams).
                    Text { x: prow.modelData.kind === "share" ? 59 : 59.6; y: prow.modelData.kind === "share" ? 14.7 : 5.6; height: 20; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; textFormat: prow.modelData.kind === "share" ? Text.PlainText : Text.StyledText; text: prow.modelData.kind === "share" ? prow.modelData.name : root.boldMatch(prow.modelData.name, root.mentionQuery.trim()); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { visible: !!prow.modelData.mail; x: 59.6; y: 25.6; height: 16; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; text: prow.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                    HoverHandler { id: prowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.insertMention(prow.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.mail ? " " + modelData.mail : "")
                    Accessible.selected: index === mentionPicker.current
                }
            }
        }
    }
    // `name` with the word that starts with `q` bold for its first
    // q.length letters.
    function boldMatch(name, q) {
        const n = String(name || "")
        if (!q) return escapeHtml(n)
        const lower = n.toLowerCase(), ql = q.toLowerCase()
        let i = lower.startsWith(ql) ? 0 : lower.indexOf(" " + ql)
        if (i > 0) i++
        if (i < 0) return escapeHtml(n)
        return escapeHtml(n.slice(0, i)) + "<b>" + escapeHtml(n.slice(i, i + q.length)) + "</b>" + escapeHtml(n.slice(i + q.length))
    }
    // Share someone's contact info: where the "@" was, and the dialog.
    property int shareAt: -1
    property int shareEnd: -1
    ShareContactDialog {
        id: shareContact
        onAccepted: people => {
            const at = root.shareAt, end = root.shareEnd
            if (at < 0) return
            input.remove(at, Math.max(at, Math.min(end, input.length)))
            const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
            const icon = Qt.resolvedUrl("../assets/icons/contact-card-inline-" + (theme.dark ? "dark" : "light") + ".svg")
            const html = people.map(p => '<img src="' + icon + '" width="20" height="20"><a href="mention-contact:' + p.mri + '" ' + style + '>' + escapeHtml(p.name) + '</a>&nbsp;').join("")
            input.insert(at, html)
            input.cursorPosition = at + people.reduce((n, p) => n + 1 + p.name.length + 1, 0)
            root.shareAt = -1
            input.forceActiveFocus()
        }
        onClosed: input.forceActiveFocus()
    }
    function shareContactForTest() { return shareContact }
    function pickShareForTest() { insertMention({ kind: "share" }) }
    function mentionForTest(text) { input.insert(input.cursorPosition, text); input.cursorPosition = input.length }
    function pickMentionForTest() { mentionPicker.pick() }

    function deliveryForTest() { deliveryPopup.anchorItem = sideTools; deliveryPopup.open() }
    function plusForTest() { plusFlyout.anchorItem = sideTools; plusFlyout.open() }

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
