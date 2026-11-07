import QtQuick
import QtQuick.Controls.Basic

// Teams' reaction summary (diverse-reaction-summary, measured): pills 26
// tall and 2 apart, each up to three emoticons (20 px "small") and the count
// when over one, ours with a brand border; Teams' overflow "+N" with its
// list; then the add-reaction button. The host is the Conversation (its
// pickers, menus and reaction rules).
Row {
    id: summary
    property var host
    property string messageId
    property var reactions: []
    // Channel posts show the add button even with no reactions.
    property bool addWhenEmpty: false
    spacing: 2
    readonly property var split: host.splitReactions(summary.reactions)
    readonly property bool atLimit: summary.reactions.filter(r => r.mine).length >= host.reactionLimit
    Repeater {
        model: summary.split.main
        Rectangle {
            id: pillBox
            required property var modelData
            required property int index
            readonly property bool forcedWho: host.forceWhoId === summary.messageId && index === 0
            onForcedWhoChanged: if (forcedWho) host.openWhoReacted(pillBox, summary.messageId, modelData, false)
            readonly property var variants: modelData.variants && modelData.variants.length ? modelData.variants : [modelData.key]
            width: 7 + variants.length * 20 + (modelData.count > 1 ? 4 + countText.implicitWidth : 0) + 7
            height: 26; radius: 13
            color: theme.surface
            border.color: modelData.mine ? theme.brand : theme.divider
            border.width: modelData.mine ? 1.33 : 1
            Row {
                x: 7; y: 3
                Repeater {
                    model: pillBox.variants
                    Emoticon { required property string modelData; key: modelData; named: "small"; size: 20 }
                }
            }
            Text {
                id: countText
                visible: pillBox.modelData.count > 1
                x: 7 + pillBox.variants.length * 20 + 4; anchors.verticalCenter: parent.verticalCenter
                text: pillBox.modelData.count
                font.family: theme.font; font.pixelSize: theme.small
                font.weight: pillBox.modelData.mine ? Font.DemiBold : Font.Normal
                color: theme.text
            }
            HoverHandler {
                id: pillHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: hovered ? host.hoverWhoReacted(pillBox, summary.messageId, pillBox.modelData) : host.leaveWhoReacted()
            }
            // Click toggles: removes our exact reaction, else adds
            // it in our skin tone (Teams); refused at the limit.
            readonly property bool refused: summary.atLimit && !modelData.mine
            TapHandler { onTapped: if (!pillBox.refused) host.react(summary.messageId, pillBox.modelData.mine ? pillBox.modelData.my_key : backend.emoticonToned(pillBox.modelData.key), !pillBox.modelData.mine) }
            LimitTip { visible: pillBox.refused && pillHover.hovered }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: host.openWhoReacted(pillBox, summary.messageId, pillBox.modelData, true) }
            Accessible.role: Accessible.Button
            Accessible.checked: modelData.mine
            Accessible.name: host.pillLabel(modelData)
        }
    }
    // Hidden pills: "+N", N the people behind them; hovering lists
    // them with their emoji ("More reactions").
    Rectangle {
        id: overflowBtn
        visible: summary.split.overflow.length > 0
        readonly property bool forcedWho: visible && host.forceWhoOverflowId === summary.messageId
        onForcedWhoChanged: if (forcedWho) host.openWhoReacted(overflowBtn, summary.messageId, null, false, summary.split.overflow)
        readonly property int people: summary.split.overflow.reduce((n, r) => n + r.count, 0)
        // Measured: padding 0 6, at least 26 wide.
        width: Math.max(26, overflowText.implicitWidth + 12); height: 26; radius: 13
        color: theme.surface
        border.color: theme.divider
        Text { id: overflowText; anchors.centerIn: parent; text: "+" + overflowBtn.people; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        HoverHandler {
            id: overflowHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: hovered ? host.hoverWhoReacted(overflowBtn, summary.messageId, null, summary.split.overflow) : host.leaveWhoReacted()
        }
        TapHandler { onTapped: host.openWhoReacted(overflowBtn, summary.messageId, null, true, summary.split.overflow) }
        Accessible.role: Accessible.Button
        Accessible.name: people === 1 ? "1 overflow reaction." : people + " overflow reactions."
    }
    Rectangle {
        width: 34; height: 26; radius: 13
        color: theme.surface
        border.color: theme.divider
        FluentIcon { x: 9; y: 5; size: 16; name: addHover.hovered ? "emoji-add-16-filled" : "emoji-add-16"; color: addHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: host.openReactionPicker(summary.messageId, parent) }
        Accessible.role: Accessible.Button
        Accessible.name: "More reactions"
    }
}
