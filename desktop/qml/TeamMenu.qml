import QtQuick
import QtQuick.Controls.Basic

// A team's ··· menu on its row in the chat list (Teams' team context menu,
// measured on winpc 2026-11-09; docs/spec/chat-list-and-header.md §5.6):
// Hide all channels | Add member, Add channel, Manage team, Manage tags,
// Copy link, Archive | Leave, Delete. It opens above the button, its left
// edge on the button's.
// - Add member opens Add members to {team}.
// - Add channel opens Create a channel.
// - Hide all channels asks first ("Hide all channels in {team}?", 600 wide)
//   and then hides them through Teams' provisioning service.
// - Copy link copies Teams' team link.
// - Archive / Restore team (owners), Leave, Delete (owners) with Teams'
//   confirmations (TeamActionDialog).
// - Manage team opens the Manage team page; Manage tags its Tags tab.
Item {
    id: root
    /// The team as the team list has it ({id, thread_id, name, channels, …}).
    property var team: ({})
    signal manageTeam(string teamId)
    signal manageTags(string teamId)
    signal channelCreated(string channelId, string name)
    readonly property alias menu: menu
    readonly property var general: (team.channels || []).find(c => c.general) || ({ id: team.thread_id, name: "General" })
    readonly property bool anyShown: (team.channels || []).some(c => c.shown !== false)

    function show(anchor, px, py) {
        menu.parent = anchor
        menu.x = px; menu.y = py
        menu.open()
    }
    function act(op) { backend.channelAction(op, root.team.id, root.team.thread_id, "") }

    MenuPopup {
        id: menu
        margins: 8
        items: (root.anyShown ? [{ key: "hide-all", label: "Hide all channels", icon: "eye-off-20" }, { separator: true }] : []).concat(root.team.archived ? [] : [{ key: "add-member", label: "Add member", icon: "person-add-20" }]).concat([
            { key: "add-channel", label: "Add channel", icon: "channel-add-20" },
            { key: "manage", label: "Manage team", icon: "settings-20" },
            { key: "tags", label: "Manage tags", icon: "tag-20" },
            { key: "link", label: "Copy link", icon: "link-20" }
        ]).concat(!root.team.owner ? [] : root.team.archived
            ? [{ key: "restore", label: "Restore team", icon: "archive-arrow-back-20" }]
            : [{ key: "archive", label: "Archive", icon: "archive-20" }]
        ).concat(root.team.archived ? [] : [{ separator: true }, { key: "leave", label: "Leave", icon: "person-arrow-left-20" }]
        ).concat(root.team.owner && !root.team.archived ? [{ key: "delete", label: "Delete", icon: "delete-20" }] : [])
        onPicked: i => {
            const k = items[i].key
            if (k === "hide-all") hideAll.open()
            else if (k === "add-member") addMembers.start(root.team.id, root.team.thread_id, root.team.name)
            else if (k === "add-channel") createChannel.start(root.team.id, root.team.name)
            else if (k === "manage") root.manageTeam(root.team.id)
            else if (k === "tags") root.manageTags(root.team.id)
            else if (k === "link") root.act("team-link")
            else if (k === "archive") teamAction.start("archive", root.team.name)
            else if (k === "restore") root.act("team-restore")
            else if (k === "leave") teamAction.start("leave", root.team.name)
            else if (k === "delete") teamAction.start("delete", root.team.name)
        }
    }

    // Teams' confirmation (600 wide, the text 554.7 wide).
    ConfirmDialog {
        id: hideAll
        width: 600
        title: "Hide all channels in " + (root.team.name || "") + "?"
        body: "Channels will be removed from custom sections they're in, and if they're shared channels, hidden from teams they're shared with."
        confirmText: "Hide"
        onConfirmed: root.act("hide-all")
    }

    AddMembersDialog { id: addMembers }
    TeamActionDialog {
        id: teamAction
        onConfirmed: checked => {
            if (kind === "archive") backend.channelAction("team-archive", root.team.id, root.team.thread_id, JSON.stringify({ readOnly: checked }))
            else if (kind === "leave") backend.channelAction("team-leave", root.team.id, root.team.thread_id, "")
            else if (kind === "delete") backend.channelAction("team-delete", root.team.id, root.team.thread_id, "")
        }
    }
    // Leaving: Teams' answer for the last owner, a toast for other failures.
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== root.team.thread_id) return
            if (r.op === "team-leave") {
                const code = r.ok ? r.data.code : "failed"
                if (code === "OperationDeniedAsMemberIsLastAdminInTeam") teamAction.start("lastOwner", root.team.name)
                else if (code) backend.toast("Leaving the team failed", "error")
            } else if ((r.op === "team-archive" || r.op === "team-restore" || r.op === "team-delete") && !r.ok) {
                backend.toast("Something went wrong on our end. Please try again.", "error")
            }
        }
    }
    CreateChannelDialog { id: createChannel; onCreated: (id, name) => root.channelCreated(id, name) }

    // Test hooks.
    function createChannelForTest() { return createChannel }
    function addMembersForTest() { return addMembers }
    function teamActionForTest() { return teamAction }
    function hideAllForTest() { hideAll.open() }
    function closeAllForTest() { hideAll.close(); menu.close() }
}
