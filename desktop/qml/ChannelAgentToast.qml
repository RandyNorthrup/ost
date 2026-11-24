import QtQuick
import QtQuick.Controls.Basic

// Teams' Channel Agent toasts after Create team's "Add Channel Agent"
// (131175's hook; measured on winpc 2026-11-20 with "OST TEST 206 agent"):
// a card at the bottom left, 15 right of the app bar and 16 above the
// window's bottom: 288 wide, padding 12, radius 4, white with Fluent's
// shadow 8; a 20 px spinner (or the result's icon) at 11, the channel's
// name (14/600) at 40.7 with a dismiss X (20) at the right, the text
// (14/20) under it and "Go to channel" (14, brand) under that.
// - "Channel Agent is being added." while it is added (up to 120 s);
// - "Channel Agent has been added to this channel." once the agent's
//   welcome is in the channel (5 s);
// - "Couldn't create {channelName} agent." when it fails.
// When the tenant doesn't offer the agent Teams says nothing.
Rectangle {
    id: root
    signal goToChannel(string thread, string name)
    property string channel: ""
    property string thread: ""
    property string group: ""
    /// "progress", "done" or "error".
    property string state_: ""
    visible: state_ !== ""
    width: 288; height: col.implicitHeight + 24; radius: 4
    color: theme.surface
    border.width: theme.highContrast ? 1 : 0; border.color: theme.text
    FluentSurface { z: -1; anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }

    /// The new team's name, to find its thread once it is listed (Create
    /// team's answer can come before the team has one).
    property string teamName: ""
    function start(channel, thread, group, name) {
        root.channel = channel; root.thread = thread; root.group = group; root.teamName = name || ""
        state_ = "progress"; hide.interval = 120000; hide.restart()
        if (thread) add(); else { waitTries = 0; waitThread.restart() }
    }
    function add() { backend.channelAction("channel-agent-add", "", "", JSON.stringify({ channel: root.channel, thread: root.thread, group: root.group })) }
    // Teams' hook takes the first channel from the made team (its thread
    // is the team's); OST waits for the team to be listed (up to 2
    // minutes).
    property int waitTries: 0
    Timer {
        id: waitThread
        interval: 3000; repeat: true
        onTriggered: {
            let teams = []
            try { teams = JSON.parse(backend.teamsJson || "[]") } catch (e) {}
            const t = teams.find(x => (root.group && x.id === root.group) || (root.teamName && x.name === root.teamName))
            if (t && t.thread_id) { stop(); root.thread = t.thread_id; if (!root.group) root.group = t.id || ""; root.add(); return }
            if (++root.waitTries % 5 === 0) backend.reloadTeams()
            if (root.waitTries > 40) { stop(); root.state_ = "error"; hide.interval = 5000; hide.restart() }
        }
    }
    Timer { id: hide; onTriggered: root.state_ = "" }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "channel-agent-add" && root.state_ === "progress") {
                if (!r.ok) { root.state_ = "error"; hide.interval = 5000; hide.restart(); return }
                // Not offered in the tenant: Teams stops without a word.
                if (!r.data.added) { root.state_ = ""; return }
                backend.channelAction("channel-agent-wait", "", "", root.thread)
            } else if (r.op === "channel-agent-wait" && r.ok && r.data.welcomed && r.data.thread === root.thread) {
                root.state_ = "done"; hide.interval = 5000; hide.restart()
            }
        }
    }
    Column {
        id: col
        x: 40.7; y: 12.6; width: 198.7; spacing: 0
        Text {
            width: parent.width; elide: Text.ElideRight
            text: root.channel
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: root.state_ === "done" ? qsTr("Channel Agent has been added to this channel.")
                : root.state_ === "error" ? qsTr("Couldn't create %1 agent.").arg(root.channel)
                : qsTr("Channel Agent is being added.")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item { width: 1; height: 11 }
        Text {
            id: goLink
            visible: root.state_ !== "error"
            text: qsTr("Go to channel")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.pick("#4F52B2", "#7F85F5", "#FFFF00")
            HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
            font.underline: goHover.hovered
            TapHandler { onTapped: { root.goToChannel(root.thread, root.channel); root.state_ = "" } }
            Accessible.role: Accessible.Button; Accessible.name: text
        }
    }
    BusyIndicator {
        visible: root.state_ === "progress"; running: visible
        x: 11.3; y: 11.2; width: 22.8; height: 22.8
    }
    FluentIcon {
        visible: root.state_ === "done" || root.state_ === "error"
        x: 12.7; y: 12.6; size: 20
        name: root.state_ === "error" ? "error-circle-20-filled" : "checkmark-circle-20-filled"
        color: root.state_ === "error" ? theme.redForeground1 : theme.successFg
    }
    Rectangle {
        id: dismiss
        x: 253.3; y: 12.6; width: 20; height: 20; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.onFill(dismiss, theme.textStrong) }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.state_ = "" }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Dismiss")
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.channel
    function stateForTest() { return { state: state_, channel: channel, thread: thread } }
}
