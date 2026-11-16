import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

// Teams' Write with Copilot (compose-copilot-container), measured on winpc
// 2026-11-16 in OST group test and OST Test Team > OST test channel 2
// (docs/spec/messages-and-composer.md §17 "Write with Copilot").
// - A Fluent popover over the compose box: 602 wide (no wider than the
//   box), #FAFAFA, radius 4, padding 16, Teams' 16 px shadow. In a chat its
//   right edge is the box's and its bottom 6 above the box; in a new post
//   it starts 8.7 into the card, its bottom on the toolbar's top.
// - The command row at 16.7, 16.7: Rewrite (99), Proofread (114.1) and
//   Adjust (108.1, with a 12 px chevron) as 31.3 px outline buttons 10
//   apart (white, 0.67 #D1D1D1, radius 4, a 20 px icon and 14/600 #242424;
//   #F0F0F0 / #E0E0E0 / #BDBDBD while disabled), Close (32 x 31.3) at the
//   right.
// - Under it a white card (radius 4, the 2 px shadow) at 16.7, 58:
//   "Copilot can rewrite and adjust your messages to make them even better.
//   Type a message to get started." with an empty box (the buttons off),
//   else "Choose an option above for Copilot to improve your message."
//   (14/20, padding 12 16).
// - Asking: the card goes; "Generating a response" (12 #616161) and
//   Teams' typing dots, centred, the popover 108 tall; the buttons are off
//   until the answer is complete.
// - The answer: what was asked (12/16 light: "Rewrite", "Proofread this
//   message", "Make it concise", "Make it sound casual", the Custom words),
//   the rewrite (14/20), then Replace (96 x 31.3, brand), and with more
//   than one answer Previous / "n of m" / Next; at the right "AI-generated
//   content may be incorrect" (10/14 #707070) and the thumbs (20 px
//   buttons, 16 px glyphs).
// - Adjust's menu (180 wide, its bottom on the button): Custom, a line,
//   "Make it" (Concise, Longer), a line, "Make it sound" (Casual,
//   Professional, Confident, Enthusiastic). Custom turns the three buttons
//   into 32 px icons and puts a "Make it..." box (400.7 x 32) with an
//   arrow (Custom rewrite) beside them.
// Every request rewrites the draft as it was when the first was asked.
// Replace puts the shown answer in the box and closes; closing forgets
// the answers, as Teams does.
Popup {
    id: pop
    /// The ComposeBox and its box.
    property Item compose: null
    property Item box: null
    property Item toolbar: null
    property bool postMode: false
    property bool proofread: true
    /// The conversation: its thread and "Chat" / "Channel".
    property string threadId: ""
    property string contextType: "Chat"
    signal replaced(string html)

    parent: Overlay.overlay
    padding: 0
    width: box ? Math.min(602, box.width) : 602
    height: content.height
    // Placed when it opens and as it grows (mapToItem isn't a binding).
    function place() {
        if (!box) return
        const b = box.mapToItem(Overlay.overlay, 0, 0)
        x = postMode ? b.x + 8.7 : b.x + box.width - width
        y = postMode && toolbar ? toolbar.mapToItem(Overlay.overlay, 0, 0).y - height : b.y - 6 - height
    }
    onHeightChanged: if (opened) place()
    onAboutToShow: place()
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 16; radius: 4; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000") }

    readonly property color ink: theme.pick("#242424", "#FFFFFF", "#FFFFFF")
    readonly property color soft: theme.pick("#616161", "#ADADAD", "#FFFFFF")
    // The session: what was asked ({label, html, text, done, error}), the
    // answer shown, the draft every request rewrites.
    property var answers: []
    property int index: -1
    property string draft: ""
    property bool custom: false
    property int seq: 0
    readonly property string tag: "copilot-" + Math.floor(Math.random() * 1e9) + ":"
    readonly property bool hasText: !!compose && compose.plainText().trim().length > 0
    property bool empty: true
    readonly property var shown: index >= 0 && index < answers.length ? answers[index] : null
    readonly property bool busy: answers.some(a => !a.done)

    function openFor() {
        answers = []; index = -1; draft = ""; custom = false
        empty = !compose || compose.plainText().trim().length === 0
        // Teams selects the draft when nothing is selected.
        if (!empty && compose.editor.selectionStart === compose.editor.selectionEnd) compose.editor.selectAll()
        open()
    }
    onClosed: { answers = []; index = -1; custom = false; if (compose) compose.focusEditor() }

    /// Ask Copilot: `label` is what the answer is headed with.
    function ask(label, tone, length) {
        if (empty || busy) return
        if (!draft) {
            const e = compose.editor
            // A selection rewrites only what's selected.
            draft = e.selectionStart !== e.selectionEnd && (e.selectionEnd - e.selectionStart) < e.length
                ? "<p>" + compose.escapeHtml(e.selectedText) + "</p>" : compose.formattedText()
        }
        seq++
        const id = tag + seq
        answers = answers.concat([{ id: id, label: label, html: "", text: "", done: false, error: "" }])
        index = answers.length - 1
        backend.composeCopilotRewrite(id, JSON.stringify({ user_text: draft, tone: tone, length: length,
            thread_id: threadId || backend.currentChatId, context_type: contextType }))
    }
    function adjust(key) {
        const m = ({ concise: ["Make it concise", "default", "short"], longer: ["Make it longer", "default", "long"],
                     casual: ["Make it sound casual", "casual", "medium"], professional: ["Make it sound professional", "professional", "medium"],
                     confident: ["Make it sound confident", "confident", "medium"], enthusiastic: ["Make it sound enthusiastic", "enthusiastic", "medium"] })[key]
        if (key === "custom") { custom = true; Qt.callLater(() => customField.forceActiveFocus()); return }
        if (m) ask(m[0], m[1], m[2])
    }
    function askCustom() {
        const t = customField.text.trim()
        if (!t) return
        customField.text = ""
        ask(t, t, "medium")
    }
    function replace() {
        if (!shown || !shown.done || shown.error) return
        const html = shown.html.replace(/^<GENERATED_MESSAGE>/, "")
        close()
        replaced(html)
    }
    Connections {
        target: backend
        function onComposeCopilotUpdate(request, html, text, done, error) {
            if (request.indexOf(pop.tag) !== 0) return
            pop.answers = pop.answers.map(a => a.id === request ? Object.assign({}, a, { html: html || a.html, text: text || a.text, done: done, error: error }) : a)
        }
    }

    Item {
        id: content
        width: pop.width
        height: pop.shown && !pop.shown.done && !pop.shown.text ? 108 : 58 + card.height + 16.7

        // The command row.
        Row {
            x: 16.7; y: pop.custom ? 17 : 16.7
            spacing: 10
            CmdButton { label: pop.custom ? "" : "Rewrite"; icon: "copilot-rewrite-20"; tip: "Rewrite"; w: 99; on: !pop.empty && !pop.busy; onClicked: pop.ask("Rewrite", "default", "medium") }
            CmdButton { visible: pop.proofread; label: pop.custom ? "" : "Proofread"; icon: "copilot-proofread-20"; tip: "Proofread"; w: 114.1; on: !pop.empty && !pop.busy; onClicked: pop.ask("Proofread this message", "proofread_scenario", "medium") }
            CmdButton { id: adjustButton; label: pop.custom ? "" : "Adjust"; icon: "copilot-adjust-20"; tip: "Adjust"; w: 108.1; chevron: !pop.custom; on: !pop.empty && !pop.busy; onClicked: adjustMenu.open() }
            // Custom: "Make it..." and its arrow.
            Rectangle {
                visible: pop.custom
                width: 400.7; height: 32; radius: 4
                color: theme.surface
                border.width: 0.67; border.color: customField.activeFocus ? theme.pick("#B3B3B3", "#757575", "#FFFFFF") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                Rectangle {
                    anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33
                    height: customField.activeFocus ? 2 : 0.67; radius: 1
                    color: customField.activeFocus ? theme.brand : theme.pick("#616161", "#ADADAD", "#FFFFFF")
                }
                TextInput {
                    id: customField
                    x: 12; width: 400.7 - 12 - 34; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14; color: pop.ink; clip: true
                    selectByMouse: true
                    Keys.onReturnPressed: pop.askCustom()
                    Keys.onEnterPressed: pop.askCustom()
                    Text { visible: !customField.text; text: "Make it..."; font: customField.font; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Make it..."
                }
                Item {
                    x: 370; y: 6; width: 20; height: 20
                    readonly property bool ready: !!customField.text.trim() && !pop.busy
                    FluentIcon { anchors.centerIn: parent; size: 16; name: "copilot-send-16"; color: parent.ready ? theme.pick("#424242", "#D6D6D6", "#FFFFFF") : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
                    HoverHandler { enabled: parent.ready; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: parent.ready; onTapped: pop.askCustom() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Custom rewrite"
                }
            }
        }
        Rectangle {
            id: closeButton
            x: pop.width - 16.7 - 32; y: 16.7; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 20; name: closeHover.hovered ? "dismiss-20-filled" : "dismiss-20"; color: theme.onFill(closeButton, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pop.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }

        // Asking.
        Row {
            visible: !!pop.shown && !pop.shown.done && !pop.shown.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: 64.4; spacing: 8
            Text { text: "Generating a response"; font.family: theme.font; font.pixelSize: 12; color: pop.soft; lineHeight: 16; lineHeightMode: Text.FixedHeight }
            TypingDots { anchors.verticalCenter: parent.verticalCenter }
        }

        // The card.
        Rectangle {
            id: card
            visible: !(pop.shown && !pop.shown.done && !pop.shown.text)
            x: 16.7; y: 58; width: pop.width - 33.4
            height: visible ? (pop.shown ? answerCol.height + 24 : hint.height + 24) : 0
            radius: 4; color: theme.surface
            FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 4 }
            Text {
                id: hint
                visible: !pop.shown
                x: 16; y: 12; width: parent.width - 32
                wrapMode: Text.Wrap
                text: pop.empty ? "Copilot can rewrite and adjust your messages to make them even better. Type a message to get started."
                                : "Choose an option above for Copilot to improve your message."
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: pop.ink
            }
            Column {
                id: answerCol
                visible: !!pop.shown
                x: 16; y: 12; width: parent.width - 32
                spacing: 0
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: pop.shown ? pop.shown.label : ""
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.Light; color: pop.ink
                }
                Item { width: 1; height: 12 }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: pop.shown && pop.shown.done && !pop.shown.error ? Text.RichText : Text.PlainText
                    text: !pop.shown ? "" : pop.shown.error ? "Something went wrong. Please try again." : pop.shown.done ? pop.shown.html.replace(/^<GENERATED_MESSAGE>/, "").replace(/<p>/g, "").replace(/<\/p>/g, "<br>").replace(/(<br>)+$/, "") : pop.shown.text
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: pop.ink
                }
                Item { width: 1; height: 16 }
                Item {
                    width: parent.width; height: 31.3
                    Rectangle {
                        id: replaceButton
                        readonly property bool on: !!pop.shown && pop.shown.done && !pop.shown.error
                        width: 96; height: 31.3; radius: 4
                        color: on ? (replaceHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E", "#000000")
                        Text {
                            anchors.centerIn: parent; text: "Replace"
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.onFill(replaceButton, parent.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F"))
                        }
                        HoverHandler { id: replaceHover; enabled: parent.on; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.on; onTapped: pop.replace() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Replace"
                    }
                    // Previous / n of m / Next.
                    Row {
                        visible: pop.answers.length > 1
                        x: 111; spacing: 10
                        PagerButton { icon: "chevron-left-20"; tip: "Previous response"; on: pop.index > 0 && !pop.busy; onClicked: pop.index-- }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (pop.index + 1) + " of " + pop.answers.length
                            font.family: theme.font; font.pixelSize: 12; color: pop.ink
                        }
                        PagerButton { icon: "chevron-right-20"; tip: "Next response"; on: pop.index < pop.answers.length - 1 && !pop.busy; onClicked: pop.index++ }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: -0.6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "AI-generated content may be incorrect"
                            font.family: theme.font; font.pixelSize: 10; color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
                        }
                        Thumb { icon: "copilot-like-20"; tip: "Content is correct"; key: "like" }
                        Thumb { icon: "copilot-dislike-20"; tip: "Content is incorrect"; key: "dislike" }
                    }
                }
            }
        }
    }

    // Adjust.
    MenuPopup {
        id: adjustMenu
        parent: adjustButton
        x: 0; y: -implicitHeight
        rowHeight: 38; separatorHeight: 8.67; perItemIcons: true; minRowWidth: 170.7; labelInset: -1
        items: [
            { label: "Custom", icon: "copilot-custom-20" },
            { separator: true },
            { heading: "Make it" },
            { label: "Concise" }, { label: "Longer" },
            { separator: true },
            { heading: "Make it sound" },
            { label: "Casual" }, { label: "Professional" }, { label: "Confident" }, { label: "Enthusiastic" }
        ]
        onPicked: i => pop.adjust(["custom", "", "", "concise", "longer", "", "", "casual", "professional", "confident", "enthusiastic"][i])
    }

    component CmdButton: Rectangle {
        id: cb
        property string label: ""
        property string icon: ""
        property string tip: ""
        property real w: 99
        property bool chevron: false
        property bool on: true
        signal clicked()
        width: label ? w : 32; height: 31.3; radius: 4
        color: !on ? theme.pick("#F0F0F0", "#2E2E2E", "#000000") : cbHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : theme.surface
        border.width: 0.67
        border.color: !on ? theme.pick("#E0E0E0", "#3D3D3D", "#3FF23F") : cbHover.hovered ? theme.pick("#C7C7C7", "#757575", "#FFFFFF") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        readonly property color fg: on ? pop.ink : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")
        FluentIcon {
            x: cb.label ? 12.6 : 6; anchors.verticalCenter: parent.verticalCenter; size: 20
            name: cbHover.hovered && cb.on ? cb.icon + "-filled" : cb.icon
            color: theme.onFill(cb, cb.fg)
        }
        Text {
            visible: !!cb.label
            x: 36.6; anchors.verticalCenter: parent.verticalCenter
            text: cb.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(cb, cb.fg)
        }
        FluentIcon { visible: cb.chevron; x: 83.4; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "chevron-down-12"; color: theme.onFill(cb, cb.fg) }
        HoverHandler { id: cbHover; enabled: cb.on; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: cb.on; onTapped: cb.clicked() }
        ToolTip.visible: !cb.label && cbHover.hovered; ToolTip.delay: 500; ToolTip.text: cb.tip
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    // Teams' typing balls (its typing-balls sprite, as the chat's typing
    // indicator draws them).
    component TypingDots: Row {
        spacing: 3
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 6; height: 6; radius: 3
                color: theme.hc("#C8C6C4", "#000000")
                SequentialAnimation on color {
                    running: pop.opened
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 200 }
                    ColorAnimation { to: theme.brand; duration: 200 }
                    ColorAnimation { to: "#C8C6C4"; duration: 200 }
                    PauseAnimation { duration: (2 - index) * 200 + 200 }
                }
            }
        }
    }
    component PagerButton: Rectangle {
        id: pb
        property string icon
        property string tip
        property bool on: true
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: pbHover.hovered && on ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: pb.icon; color: theme.onFill(pb, pb.on ? theme.pick("#424242", "#D6D6D6", "#FFFFFF") : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
        HoverHandler { id: pbHover; enabled: pb.on; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: pb.on; onTapped: pb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    /// Thumbs: on, and filled, once picked for the answer shown.
    property var thumbs: ({})
    component Thumb: Rectangle {
        id: th
        property string icon
        property string tip
        property string key
        readonly property bool picked: !!pop.shown && pop.thumbs[pop.shown.id] === key
        width: 20; height: 20; radius: 4
        color: thHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 16; name: th.picked || thHover.hovered ? th.icon + "-filled" : th.icon; color: theme.onFill(th, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: thHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                if (!pop.shown) return
                const t = Object.assign({}, pop.thumbs); t[pop.shown.id] = th.picked ? "" : th.key; pop.thumbs = t
            }
        }
        ToolTip.visible: thHover.hovered; ToolTip.delay: 500; ToolTip.text: th.key === "like" ? "Like" : "Dislike"
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }

    /// Tests: the popover's state, and its actions by name.
    function stateForTest() {
        return { empty: empty, custom: custom, busy: busy, index: index, answers: answers.map(a => ({ label: a.label, text: a.text, done: a.done, error: a.error, html: a.html })),
                 x: x, y: y, w: width, h: height, draft: draft }
    }
    function actForTest(what, arg) {
        if (what === "rewrite") ask("Rewrite", "default", "medium")
        else if (what === "proofread") ask("Proofread this message", "proofread_scenario", "medium")
        else if (what === "custom") { adjust("custom"); customField.text = arg || ""; askCustom() }
        else if (what === "menu") adjustMenu.open()
        else if (what === "prev") { if (index > 0) index-- }
        else if (what === "replace") replace()
        else adjust(what)
    }
}
