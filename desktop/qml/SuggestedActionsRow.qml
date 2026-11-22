import QtQuick
import QtQuick.Controls.Basic

// A bot message's suggested actions and its like / dislike, as Teams draws
// them under the text (Teams 26304, 763654 `ja` / `$a` / `Wa` / `ba`;
// a Channel Agent's welcome measured on winpc 2026-11-21): a row 8 apart,
// 31.3 tall. Every action is a small Fluent button (12 px, padding 3 8,
// at least 64 wide, a #D1D1D1 hairline, radius 4):
// - Action.Compose that mentions an agent: "@agent"
//   (mention-project-agent-button);
// - imBack: its title wraps (at least 24 tall); the others are cut with
//   an ellipsis;
// - openUrl: the same button, with a 16 px icon for "Preferences"
//   (document text) and "Skills" (folder);
// - Action.Submit: disabled while its invoke is under way;
// - Action.ODSL (Copilot's own statements) isn't drawn here.
// Like / dislike (24 x 31.3, 16 px thumbs, #424242; filled once picked)
// open Teams' feedback form.
Row {
    id: row
    /// The message (MessageView) and the Conversation that acts on it
    /// (suggestedAction, botFeedback).
    property var message: ({})
    property var host: null
    property real maxWidth: 600
    readonly property var actions: (message.suggested || []).filter(a => a.kind !== "odsl")
    readonly property bool shown: actions.length > 0 || !!message.feedback_loop
    spacing: 8
    property string busy: ""
    Connections {
        target: backend
        function onSuggestedInvokeDone(messageId, error) { if (messageId === row.message.id) row.busy = "" }
    }

    Repeater {
        model: row.actions
        Rectangle {
            id: sugg
            required property var modelData
            required property int index
            readonly property bool wraps: modelData.kind === "imBack"
            readonly property string glyph: modelData.kind === "openUrl" ? ({ "Preferences": "document-text-16", "Skills": "folder-16" })[modelData.title] || "" : ""
            readonly property bool enabled_: row.busy !== String(index)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(64, Math.min(row.maxWidth, suggRow.implicitWidth + 16))
            height: wraps ? Math.max(24, suggText.implicitHeight + 6) + 1.34 : 23.3
            radius: 4
            color: !enabled_ ? theme.bgDisabled : suggHover.hovered ? theme.rowHover : theme.surface
            border.color: !enabled_ ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
            Row {
                id: suggRow
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { visible: sugg.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; size: 16; name: sugg.glyph; color: theme.onFill(sugg, theme.text) }
                Text {
                    id: suggText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, row.maxWidth - 16 - (sugg.glyph ? 22 : 0))
                    text: sugg.modelData.title
                    wrapMode: sugg.wraps ? Text.Wrap : Text.NoWrap
                    elide: sugg.wraps ? Text.ElideNone : Text.ElideRight
                    horizontalAlignment: sugg.wraps ? Text.AlignLeft : Text.AlignHCenter
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 12
                    color: sugg.enabled_ ? theme.onFill(sugg, theme.text) : theme.disabled
                }
            }
            HoverHandler { id: suggHover; enabled: sugg.enabled_; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: sugg.enabled_
                onTapped: {
                    if (sugg.modelData.kind === "invoke") row.busy = String(sugg.index)
                    if (row.host) row.host.suggestedAction(row.message, sugg.modelData)
                }
            }
            Accessible.role: Accessible.Button; Accessible.name: sugg.modelData.title
        }
    }
    Row {
        visible: !!row.message.feedback_loop
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: [{ k: "compliment", icon: "thumb-like-16", tip: qsTr("Like") }, { k: "problem", icon: "thumb-dislike-16", tip: qsTr("Dislike") }]
            Rectangle {
                id: thumb
                required property var modelData
                readonly property bool picked: !!row.host && row.host.botFeedback[row.message.id] === modelData.k
                width: 24; height: 31.3; radius: 4
                color: "transparent"
                FluentIcon {
                    anchors.centerIn: parent; size: 16
                    name: thumb.modelData.icon + (thumb.picked || thumbHover.hovered ? "-filled" : "")
                    color: thumb.picked ? theme.brand : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                }
                HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (!row.host) return
                        const f = Object.assign({}, row.host.botFeedback); f[row.message.id] = thumb.modelData.k; row.host.botFeedback = f
                        backend.requestFeedback(thumb.modelData.k, row.message.sender || "Bot", "Bot message " + row.message.id)
                    }
                }
                ToolTip.visible: thumbHover.hovered; ToolTip.text: thumb.modelData.tip; ToolTip.delay: 500
                Accessible.role: Accessible.Button; Accessible.name: thumb.modelData.tip
            }
        }
    }
}
