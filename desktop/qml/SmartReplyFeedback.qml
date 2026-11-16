import QtQuick
import QtQuick.Controls.Basic

// Teams' suggested-reply feedback (79624 `Cs` / `$n`, read from its code
// and Griffel CSS on 2026-11-16): a popover above the lightbulb button, at
// its end, holding:
// - "Help us improve our suggestions" (14/20), then 8 under it "How would
//   you describe the suggestions we provided?" (12/16, 250 wide at most);
// - one round checkbox per category (Teams' list for the kinds shown:
//   text, files, meetings), 32 a row;
// - "What else can you tell us?" (a textarea 14 under them, 74 tall, 14 px);
// - a 12 px note about where it goes and "Attach my last message…"
//   (a square checkbox, 12 px);
// - Send (primary, small, 16 under, at the end), off until a category is
//   picked or something is typed.
// Teams sends it to Microsoft (sendSmartRepliesOCVFeedback). OST opens it
// as a GitHub issue instead (docs/spec/feedback-and-help.md), so the note
// and the checkbox say that; the suggestions and the message go only when
// the checkbox is ticked, as in Teams.
Popup {
    id: pop
    /// The kinds of suggestions shown ("reply", "file_sharing", "meeting").
    property var kinds: []
    signal submitted(var categories, string comment, bool attach)
    property Item anchorItem: null
    function openFor(item) {
        anchorItem = item
        picked = []; comment.text = ""; attachBox.checked = false
        open()
    }
    property var picked: []
    readonly property var categories: JSON.parse(backend.smartReplyFeedbackCategories(JSON.stringify(kinds)))
    readonly property bool canSend: picked.length > 0 || comment.text.trim().length > 0
    parent: Overlay.overlay
    x: anchorItem ? Math.max(8, anchorItem.mapToItem(Overlay.overlay, anchorItem.width, 0).x - width) : 0
    y: anchorItem ? Math.max(8, anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 4) : 0
    padding: 16
    // The form is 286 wide (Teams: max-width 28.6rem).
    width: 286 + 2 * padding
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4 }

    component RoundCheck: Item {
        id: rc
        property string label
        property bool checked: false
        property bool round: true
        property int fontSize: 14
        signal toggled()
        width: parent ? parent.width : 286
        height: Math.max(32, lbl.implicitHeight + 12)
        Rectangle {
            id: box
            x: 8; y: (rc.height - 16) / 2
            width: 16; height: 16; radius: rc.round ? 8 : 2
            color: rc.checked ? (rcHover.hovered ? theme.brandHover : theme.brand) : "transparent"
            border.width: rc.checked ? 0 : 1
            border.color: rcHover.hovered ? theme.text : theme.textSecondary
            FluentIcon {
                visible: rc.checked
                anchors.centerIn: parent
                name: "checkmark-12"; size: 12
                color: theme.onFill(box, theme.textOnBrand)
            }
        }
        Text {
            id: lbl
            x: 32; width: rc.width - 40
            anchors.verticalCenter: parent.verticalCenter
            text: rc.label
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: rc.fontSize
            color: theme.text
        }
        HoverHandler { id: rcHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { rc.checked = !rc.checked; rc.toggled() } }
        Accessible.role: Accessible.CheckBox
        Accessible.name: rc.label
        Accessible.checked: rc.checked
    }

    contentItem: Column {
        width: pop.availableWidth
        Text {
            width: parent.width
            text: "Help us improve our suggestions"
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item { width: 1; height: 8 }
        Text {
            width: Math.min(250, parent.width)
            text: "How would you describe the suggestions we provided?"
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item { width: 1; height: 8 }
        Column {
            width: parent.width
            Accessible.role: Accessible.Grouping
            Accessible.name: "How would you describe the suggestions we provided?"
            Repeater {
                model: pop.categories
                RoundCheck {
                    required property var modelData
                    label: modelData
                    checked: pop.picked.indexOf(modelData) >= 0
                    onToggled: pop.picked = pop.picked.indexOf(modelData) >= 0 ? pop.picked.filter(c => c !== modelData) : [modelData].concat(pop.picked)
                }
            }
        }
        Item { width: 1; height: 14 }
        Rectangle {
            width: parent.width; height: Math.max(74, comment.contentHeight + 12)
            radius: 4
            color: theme.surface
            border.width: 1; border.color: comment.activeFocus ? theme.stroke : theme.stroke
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: comment.activeFocus ? 2 : 1; color: comment.activeFocus ? theme.brand : theme.textSecondary }
            TextEdit {
                id: comment
                x: 12; y: 6; width: parent.width - 24
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                selectByMouse: true
                Text {
                    visible: !comment.text && !comment.preeditText
                    text: "What else can you tell us?"
                    font: comment.font
                    color: theme.textSecondary
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "What else can you tell us?"
            }
        }
        Item { width: 1; height: 14 }
        Text {
            width: parent.width
            text: "Your feedback opens as a public issue on GitHub (" + backend.feedbackRepo() + ")."
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        RoundCheck {
            id: attachBox
            round: false
            fontSize: 12
            label: "Attach my last message to help OST analyze my feedback. It will be public."
        }
        Item { width: 1; height: 16 }
        Item {
            width: parent.width; height: 24
            Rectangle {
                id: sendBtn
                anchors.right: parent.right
                width: Math.max(64, sendText.implicitWidth + 16); height: 24; radius: 4
                color: !pop.canSend ? theme.pick("#F0F0F0", "#141414", "#000000") : sendHover.hovered ? theme.brandHover : theme.brandFill
                border.width: pop.canSend ? 0 : 1; border.color: theme.pick("#E0E0E0", "#424242", "#3FF23F")
                Text {
                    id: sendText
                    anchors.centerIn: parent
                    text: "Send"
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: !pop.canSend ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : theme.onFill(sendBtn, theme.textOnBrand)
                }
                HoverHandler { id: sendHover; enabled: pop.canSend; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: pop.canSend
                    onTapped: { pop.submitted(pop.picked, comment.text, attachBox.checked); pop.close() }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Send"
            }
        }
    }
}
