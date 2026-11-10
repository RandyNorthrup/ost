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
// - Manage team opens the Manage team page.
Item {
    id: root
    /// The team as the team list has it ({id, thread_id, name, channels, …}).
    property var team: ({})
    signal manageTeam(string teamId)
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
            { key: "link", label: "Copy link", icon: "link-20" }
        ])
        onPicked: i => {
            const k = items[i].key
            if (k === "hide-all") hideAll.open()
            else if (k === "add-member") addMembers.start(root.team.id, root.team.thread_id, root.team.name)
            else if (k === "add-channel") createChannel.start(root.team.id, root.team.name)
            else if (k === "manage") root.manageTeam(root.team.id)
            else if (k === "link") root.act("team-link")
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
    CreateChannelDialog { id: createChannel; onCreated: (id, name) => root.channelCreated(id, name) }

    // Test hooks.
    function createChannelForTest() { return createChannel }
    function addMembersForTest() { return addMembers }
    function hideAllForTest() { hideAll.open() }
    function closeAllForTest() { hideAll.close(); menu.close() }
}
