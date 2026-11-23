import QtQuick
import QtQuick.Controls.Basic

// A bot message's suggested actions and its like / dislike, as Teams draws
// them under the text (Teams 26304, 763654 `ja` / `$a` / `Wa` / `ba`;
// a Channel Agent's welcome measured on winpc 2026-11-21): a wrapping row,
// 8 apart both ways (a row is 31.3 tall with the thumbs). Every action is a
// small Fluent button (12 px, padding 3 8, at least 64 wide, a #D1D1D1
// hairline, radius 4):
// - Action.Compose that mentions an agent: "@agent"
//   (mention-project-agent-button);
// - imBack: its title wraps (at least 24 tall); the others are cut with
//   an ellipsis;
// - openUrl: the same button, with a 16 px icon for "Preferences"
//   (document text) and "Skills" (folder);
// - Action.Submit: disabled while its invoke is under way;
// - Action.ODSL: the agent's commands that Teams draws among the actions
//   (541316 `Xu` genericBotMention: a small button that quotes the message
//   and mentions the agent with its text, forceLineBreak ending the line;
//   `$n` createMeeting: Schedule Meeting, a primary medium button, and a
//   ··· menu with Edit and Discard meeting, both disabled once scheduled or
//   discarded; `jt` agendaTimer: start / stop in its own call only). The
//   rest (cards, reasoning) are OdslCards and OdslBlock.
// Measured on winpc 2026-11-22 ("OST TEST 246 agent"): Provide answers /
// Draft a plan 23.3 tall, then @agent on the next line; Schedule Meeting
// 31.3 tall (14/20 semibold, padding 5 12) and the ··· 32 x 31.3.
// Like / dislike (24 x 31.3, 16 px thumbs, #424242; filled once picked)
// open Teams' feedback form.
Column {
    id: row
    /// The message (MessageView) and the Conversation that acts on it
    /// (suggestedAction, botFeedback).
    property var message: ({})
    property var host: null
    property real maxWidth: 600
    spacing: 8
    property string busy: ""
    /// The service's strings for a command ({KEY: text}).
    function str(c, key, dflt) { return (c && c.strings && c.strings[key]) || dflt }
    Connections {
        target: backend
        function onSuggestedInvokeDone(messageId, error) { if (messageId === row.message.id) row.busy = "" }
    }
    /// Lines of items: {type: "action" | "odsl", a, st, si, ai} and the
    /// thumbs at the end of the last line.
    readonly property var lines: {
        const out = [[]]
        const all = row.message.suggested || []
        all.forEach((a, ai) => {
            if (a.kind !== "odsl") { out[out.length - 1].push({ type: "action", a: a, ai: ai }); return }
            (a.statements || []).forEach((st, si) => {
                const c = st.command
                if (!c || ["genericBotMention", "createMeeting", "agendaTimer"].indexOf(c.kind) < 0) return
                // The agenda timer only in its own call (Teams renders null
                // otherwise).
                if (c.kind === "agendaTimer" && (backend.callState === "" || !c.call_id)) return
                out[out.length - 1].push({ type: "odsl", c: c, st: st, si: si, ai: ai })
                if (c.kind === "genericBotMention" && c.line_break) out.push([])
            })
        })
        if (!!row.message.feedback_loop) out[out.length - 1].push({ type: "thumbs" })
        return out.filter(l => l.length > 0)
    }
    readonly property bool shown: lines.length > 0
    /// The width it wants.
    readonly property real wanted: implicitWidth
    function invoke(item, result) {
        row.busy = item.ai + ":" + item.si
        if (row.host) row.host.suggestedAction(row.message, { kind: "odsl", statement: item.st.raw, statementIndex: item.si, suggestedActionIndex: item.ai, result: result })
    }

    Repeater {
        id: lineRep
        model: row.lines
        Flow {
            id: line
            required property var modelData
            // As wide as its items (up to the row's room), so the bubble
            // grows only as far as Teams'.
            readonly property real natural: { let w = -8; for (const c of children) if (c.width > 0) w += c.width + 8; return Math.max(0, w) }
            width: Math.min(row.maxWidth, natural)
            spacing: 8
            Repeater {
                model: line.modelData
                Item {
                    id: slot
                    required property var modelData
                    // The row's items share a 31.3 line when the thumbs are in it.
                    readonly property real lineH: line.modelData.some(x => x.type === "thumbs" || (x.type === "odsl" && x.c.kind === "createMeeting")) ? 31.3 : 0
                    height: Math.max(lineH, ld.item ? ld.item.height : 0)
                    width: ld.item ? ld.item.width : 0
                    Loader {
                        id: ld
                        y: (slot.height - (item ? item.height : 0)) / 2
                        sourceComponent: slot.modelData.type === "thumbs" ? thumbsComp : slot.modelData.type === "action" ? actionComp
                            : slot.modelData.c.kind === "createMeeting" ? meetingComp : slot.modelData.c.kind === "agendaTimer" ? timerComp : mentionComp
                        property var entry: slot.modelData
                    }
                }
            }
        }
    }

    // A small Fluent button.
    component SmallButton: Rectangle {
        id: sb
        property string label
        property string glyph
        property bool wraps: false
        property bool enabled_: true
        signal clicked()
        width: Math.max(64, Math.min(row.maxWidth, sbRow.implicitWidth + 16))
        height: wraps ? Math.max(24, sbText.implicitHeight + 6) + 1.34 : 23.3
        radius: 4
        color: !enabled_ ? theme.bgDisabled : sbHover.hovered ? theme.rowHover : theme.surface
        border.color: !enabled_ ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        Row {
            id: sbRow
            anchors.centerIn: parent
            spacing: 6
            FluentIcon { visible: sb.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; size: 16; name: sb.glyph; color: theme.onFill(sb, theme.text) }
            Text {
                id: sbText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.maxWidth - 16 - (sb.glyph ? 22 : 0))
                text: sb.label
                wrapMode: sb.wraps ? Text.Wrap : Text.NoWrap
                elide: sb.wraps ? Text.ElideNone : Text.ElideRight
                horizontalAlignment: sb.wraps ? Text.AlignLeft : Text.AlignHCenter
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 12
                color: sb.enabled_ ? theme.onFill(sb, theme.text) : theme.disabled
            }
        }
        HoverHandler { id: sbHover; enabled: sb.enabled_; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: sb.enabled_; onTapped: sb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: sb.label
    }

    Component {
        id: actionComp
        SmallButton {
            readonly property var e: parent ? parent.entry : null
            readonly property var a: e ? e.a : ({})
            label: a.title || ""
            wraps: a.kind === "imBack"
            glyph: a.kind === "openUrl" ? ({ "Preferences": "document-text-16", "Skills": "folder-16" })[a.title] || "" : ""
            enabled_: !!e && row.busy !== String(e.ai)
            onClicked: {
                if (a.kind === "invoke") row.busy = String(e.ai)
                if (row.host) row.host.suggestedAction(row.message, a)
            }
        }
    }
    Component {
        id: mentionComp
        SmallButton {
            readonly property var e: parent ? parent.entry : null
            label: e ? e.c.title : ""
            onClicked: if (row.host) row.host.suggestedAction(row.message, { kind: "botMention", text: e.c.content })
        }
    }
    Component {
        id: timerComp
        // Teams' agenda timer button: "Start timer" / "Stop timer" (a
        // stopped timer offers start).
        SmallButton {
            readonly property var e: parent ? parent.entry : null
            readonly property bool start: !!e && e.c.action !== "stop"
            label: start ? qsTr("Start agenda tracker", "meetingCollaboration:k64xb8s7s") : qsTr("Cancel agenda tracker", "meetingCollaboration:k4w2r3t6u")
            enabled_: !!e && row.busy !== e.ai + ":" + e.si && e.c.status !== "submitted"
            onClicked: row.invoke(e, { action: e.c.action, callId: e.c.call_id, status: "submitted" })
        }
    }
    Component {
        id: meetingComp
        Row {
            id: meet
            readonly property var e: parent ? parent.entry : null
            readonly property var c: e ? e.c : ({})
            readonly property bool done: c.status === "SCHEDULED" || c.status === "DISCARDED" || (!!e && row.busy === e.ai + ":" + e.si)
            spacing: 8
            height: 31.3
            Rectangle {
                id: schedule
                width: scheduleText.implicitWidth + 24 + 1.34; height: 31.3; radius: 4
                color: meet.done ? theme.bgDisabled : scheduleHover.hovered ? theme.brandHover : theme.brandFill
                Text {
                    id: scheduleText
                    anchors.centerIn: parent
                    text: row.str(meet.c, "PROJECT_AGENT_SCHEDULE_MEETING_TEXT", qsTr("Schedule Meeting", "calendar:k65ljmldf"))
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: meet.done ? theme.disabled : theme.onFill(schedule, "white")
                }
                HoverHandler { id: scheduleHover; enabled: !meet.done; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !meet.done; onTapped: if (row.host) row.host.scheduleAgentMeeting(row.message, meet.e, meet.c) }
                Accessible.role: Accessible.Button; Accessible.name: scheduleText.text
            }
            Rectangle {
                id: meetMore
                width: 32; height: 31.3; radius: 4
                color: meet.done ? theme.bgDisabled : moreHover.hovered ? theme.rowHover : theme.surface
                border.color: meet.done ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                FluentIcon { anchors.centerIn: parent; size: 20; name: "more-horizontal-20"; color: meet.done ? theme.disabled : theme.onFill(meetMore, theme.text) }
                HoverHandler { id: moreHover; enabled: !meet.done; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !meet.done; onTapped: { meetMenu.parent = meetMore; meetMenu.x = 0; meetMenu.y = meetMore.height + 4; meetMenu.open() } }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("More options")
                MenuPopup {
                    id: meetMenu
                    items: [
                        { label: row.str(meet.c, "PROJECT_AGENT_EDIT_MEETING_TEXT", qsTr("Edit", "calendar:k6bnmp9rz")), icon: "edit-20" },
                        { label: row.str(meet.c, "PROJECT_AGENT_DISCARD_MEETING_TEXT", qsTr("Discard meeting", "calendar:k9xsasqe1")), icon: "calendar-cancel-20" }
                    ]
                    onPicked: i => {
                        if (i === 0) { if (row.host) row.host.editAgentMeeting(row.message, meet.c) }
                        else row.invoke(meet.e, { meetingStatus: "DISCARDED" })
                    }
                }
            }
        }
    }
    Component {
        id: thumbsComp
        Row {
            height: 31.3
            Repeater {
                model: [{ k: "compliment", icon: "thumb-like-16", tip: qsTr("Like") }, { k: "problem", icon: "thumb-dislike-16", tip: qsTr("Dislike") }]
                Rectangle {
                    id: thumb
                    required property var modelData
                    readonly property bool picked: !!row.host && (row.host.botFeedback || {})[row.message.id] === modelData.k
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
}
