import QtQuick
import QtQuick.Controls.Basic

// A shared channel's Manage channel ▸ Members ▸ Share with people ▾
// (TASK-0087; Teams measured on winpc 2026-11-20):
// - "team" (Share with a team), 600 x 599: "Share the {channel} channel.
//   Start by sending an invite to a team owner." (20/28 semibold, wrapping),
//   "This person will accept the invite on behalf of their team. If the
//   person is outside your org, type their email address." with "What's
//   shared with the invite?" (14/20), the filled picker (525 x 32, "Type a
//   name or email of a team owner") and Cancel / Send invite (96 x 31) at
//   the bottom right. Send invite: provisioning createShareWithTeamInvitations;
//   the owner accepts it in Manage teams ▸ Pending invites for one of their
//   teams.
// - "own" (Share with a team you own): your other teams that don't have it
//   yet ("Select a team", Share: linkChannelWithTeam); with none, 600 x 162
//   "The {channel} channel is already shared with all the teams you own."
//   and Close.
Popup {
    id: dlg
    property string mode: "team"
    property var channel: ({})
    property string teamId: ""
    property string teamThread: ""
    /// The teams it's already shared with (group ids).
    property var sharedTeamIds: []
    property var picked: null
    property var results: []
    property string ownTeam: ""
    property bool busy: false
    property string error: ""
    function start(m, ch, tid, thread) {
        mode = m; channel = ch; teamId = tid; teamThread = thread
        picked = null; results = []; ownTeam = ""; busy = false; error = ""
        picker.text = ""
        open()
        if (mode === "team") picker.forceActiveFocus()
    }
    readonly property var ownTeams: (backend.teamsJson ? JSON.parse(backend.teamsJson) : [])
        .filter(t => t.owner === true && !t.archived && t.id !== dlg.teamId && dlg.sharedTeamIds.indexOf(t.id) < 0)
    readonly property bool allShared: mode === "own" && ownTeams.length === 0
    function send() {
        busy = true; error = ""
        if (mode === "team") backend.channelAction("share-team-owner", teamId, channel.id, JSON.stringify({ users: [picked.mri] }))
        else { const t = ownTeams.find(t => t.id === ownTeam); backend.channelAction("share-own-team", teamId, channel.id, JSON.stringify({ team: t.id, thread: t.thread_id })) }
    }
    Timer {
        id: debounce
        interval: 300
        onTriggered: if (picker.text.trim()) backend.channelAction("add-member-search", dlg.teamId, dlg.teamThread, picker.text.trim())
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            if (!dlg.opened) return
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "add-member-search" && r.ok && r.data.query.trim() === picker.text.trim())
                dlg.results = (r.data.people || []).filter(p => !p.group && p.mri)
            else if (r.op === "share-team-owner" || r.op === "share-own-team") {
                dlg.busy = false
                if (!r.ok) { dlg.error = qsTr("We couldn't send the invite. Try sending it again later."); return }
                const errs = (r.data && r.data.errors) || []
                if (errs.length) { dlg.error = qsTr("%n invites couldn't be sent", "", errs.length); return }
                dlg.close()
            }
        }
    }
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true; width: 600; padding: 24
    height: allShared ? 162 : mode === "team" ? 599 : 300
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    contentItem: Item {
        Text {
            id: heading
            x: 1; y: dlg.allShared ? 3 : 1; width: 551; wrapMode: Text.Wrap
            text: dlg.allShared ? qsTr("The %1 channel is already shared with all the teams you own.").arg(dlg.channel.name || "")
                : dlg.mode === "team" ? qsTr("Share the %1 channel. Start by sending an invite to a team owner.").arg(dlg.channel.name || "")
                : qsTr("Share the %1 channel").arg(dlg.channel.name || "")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            id: guidance
            visible: dlg.mode === "team"
            x: 1; y: heading.y + heading.height + 8; width: 550; wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: qsTr("This person will accept the invite on behalf of their team. If the person is outside your org, type their email address.") + " <a href=\"https://go.microsoft.com/fwlink/?linkid=2201215\">" + qsTr("What’s shared with the invite?") + "</a>"
            linkColor: theme.brandForeground1
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
            onLinkActivated: l => backend.openExternal(l)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        // The team owner: Teams' filled picker.
        Column {
            visible: dlg.mode === "team"
            x: 1; y: guidance.y + guidance.height + 12; width: 551; spacing: 4
            Rectangle {
                width: parent.width; height: 32; radius: 4
                color: theme.pick("#F0F0F0", "#141414", "#000000")
                Rectangle { visible: picker.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
                TextInput {
                    id: picker
                    x: 12; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                    readOnly: !!dlg.picked
                    text: dlg.picked ? dlg.picked.name : ""
                    onTextEdited: { dlg.results = []; debounce.restart() }
                    Text { visible: !picker.text; text: qsTr("Type a name or email of a team owner"); font: picker.font; color: theme.textSecondary }
                    Accessible.name: qsTr("Type a name or email of a team owner")
                }
                FluentIcon { visible: !!dlg.picked; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "dismiss-20"; color: theme.textSecondary
                    TapHandler { onTapped: { dlg.picked = null; picker.text = ""; picker.forceActiveFocus() } } }
            }
            Repeater {
                model: dlg.picked ? [] : dlg.results.slice(0, 6)
                Rectangle {
                    id: row
                    required property var modelData
                    width: parent.width; height: 50; radius: 4
                    color: rh.hovered ? theme.menuHover : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: row.modelData.name || ""; photoId: row.modelData.mri || "" }
                    Column {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        Text { text: row.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(row, theme.text) }
                        Text { text: row.modelData.detail || row.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(row, theme.textSecondary) }
                    }
                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { dlg.picked = row.modelData; dlg.results = [] } }
                    Accessible.role: Accessible.Button
                    Accessible.name: row.modelData.name || ""
                }
            }
        }
        Dropdown {
            visible: dlg.mode === "own" && !dlg.allShared
            x: 1; y: heading.y + heading.height + 16; width: 551
            label: (dlg.ownTeams.find(t => t.id === dlg.ownTeam) || {}).name || qsTr("Select a team")
            options: dlg.ownTeams.map(t => [t.id, t.name])
            accessibleName: qsTr("Select a team")
            onPicked: code => dlg.ownTeam = code
        }
        Text { visible: !!dlg.error; anchors.bottom: buttons.top; anchors.bottomMargin: 8; x: 1; width: 551; wrapMode: Text.Wrap; text: dlg.error; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3 }
        Row {
            id: buttons
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 8
            ShareButton { text: dlg.allShared ? qsTr("Close") : qsTr("Cancel"); onClicked: dlg.close() }
            ShareButton {
                visible: !dlg.allShared
                text: dlg.mode === "team" ? qsTr("Send invite") : qsTr("Share"); primary: true
                enabled: !dlg.busy && (dlg.mode === "team" ? !!dlg.picked : dlg.ownTeam.length > 0)
                onClicked: dlg.send()
            }
        }
    }
    component ShareButton: Rectangle {
        id: sb
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, sbText.implicitWidth + 24); height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (sbh.hovered ? theme.brandHover : theme.brandFill) : (sbh.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text { id: sbText; anchors.centerIn: parent; text: sb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(sb, !sb.enabled ? theme.disabled : sb.primary ? theme.textOnBrand : theme.text) }
        HoverHandler { id: sbh; enabled: sb.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: sb.enabled; onTapped: sb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    function stateForTest() { return { mode: mode, allShared: allShared, heading: heading.text, ownTeams: ownTeams.map(t => t.name), picked: picked ? picked.name : "" } }
}
