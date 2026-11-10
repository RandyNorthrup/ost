import QtQuick
import QtQuick.Controls.Basic

// Teams' hover bar (message-actions-container, measured in the client): a
// 32 px popover, white with Fluent's shadow16. Inside: 7 px in, the quick
// reactions (32 x 31 buttons, the emoticon 20 px at 6, growing to 1.2x on
// hover; pressed ones underlined), More reactions, a divider (8 px, its 1 px
// line 21 px tall), the contextual actions, More options; 6 px after. The
// host is the Conversation.
Item {
    id: bar
    property var host
    property var message: ({})
    readonly property var reactions: message && message.reactions ? message.reactions : []
    // Contextual actions: [{key: "edit"|"reply", icon, tip}].
    property var acts: []
    /// A scheduled message has no reactions (Teams: Edit and More only).
    readonly property bool reactionsShown: !(message && message.scheduled_at)
    /// "thread": Reply in thread (a Threads-layout channel).
    signal threadRequested(var message)
    // Which menu ··· opens: "chat", "post" or "reply" (Teams' ChatMessage,
    // ChannelPost and ChannelReply).
    property string context: "chat"
    readonly property bool hovered: barHover.hovered
    readonly property var quick: host.quickReactions
    height: 32
    width: 7 + (reactionsShown ? (quick.length + 1) * 32 + 8 : 0) + acts.length * 32 + 32 + 6
    FluentSurface { anchors.fill: parent; depth: 16; radius: 4 }
    HoverHandler { id: barHover }
    Accessible.role: Accessible.ToolBar
    Accessible.name: "Reactions and message actions"
    Row {
        x: 7
        Repeater {
            model: bar.reactionsShown ? bar.quick : []
            Item {
                id: quickBtn
                required property string modelData
                // Pressed when we reacted with exactly this id
                // (Teams: aria-pressed, a 14 x 2 underline).
                readonly property var mineAlready: bar.reactions.find(r => r.mine && r.my_key === modelData)
                width: 32; height: 31
                Emoticon {
                    anchors.centerIn: parent
                    key: quickBtn.modelData; named: "medium"; size: 20
                    scale: quickHover.hovered ? 1.2 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }
                }
                PressedLine { visible: !!quickBtn.mineAlready }
                HoverHandler { id: quickHover; cursorShape: Qt.PointingHandCursor }
                // At the limit only removing is allowed, and the
                // tooltip says why (Teams 348213).
                readonly property bool refused: !mineAlready && bar.reactions.filter(r => r.mine).length >= host.reactionLimit
                TapHandler { onTapped: if (!quickBtn.refused) host.react(bar.message.id, quickBtn.mineAlready ? quickBtn.mineAlready.my_key : quickBtn.modelData, !quickBtn.mineAlready) }
                ToolTip {
                    visible: quickHover.hovered; delay: 500
                    y: -height - 4; padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: quickBtn.refused ? host.limitText : backend.emoticonName(quickBtn.modelData); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.Button
                Accessible.name: backend.emoticonName(modelData)
                Accessible.checked: !!mineAlready
            }
        }
        BarButton {
            visible: bar.reactionsShown
            icon: "emoji-add-20"; tip: "More reactions"
            // Pressed when we reacted with something not offered
            // above.
            pressed: bar.reactions.some(r => r.mine && host.quickReactions.indexOf(r.my_key) < 0)
            onClicked: host.openReactionPicker(bar.message.id, bar)
        }
        Item {
            visible: bar.reactionsShown
            width: 8; height: 32
            Rectangle { x: 4; y: 5; width: 1; height: 21; color: theme.divider }
        }
        Repeater {
            model: bar.acts
            BarButton {
                required property var modelData
                icon: modelData.icon; tip: modelData.tip
                onClicked: modelData.key === "edit" ? host.startEdit(bar.message) : modelData.key === "thread" ? bar.threadRequested(bar.message) : host.replyWithQuote(bar.message)
            }
        }
        BarButton { id: moreButton; icon: "more-horizontal-20"; tip: "More options"; height: 32; onClicked: host.openMessageMenu(bar.message, moreButton, false, 0, moreButton.height, bar.context) }
    }
}
