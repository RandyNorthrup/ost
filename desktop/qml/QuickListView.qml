import QtQuick
import QtQuick.Controls.Basic

// Quick views ▸ Followed threads and Saved, as Teams desktop lays them out
// (measured on winpc 2026-11-09): a 380 px list beside the conversation's
// place.
// - The title (16/22 bold) at 32, 19; the filter pills (12/16, 23.3 tall,
//   4 apart) 69.5 down: Unread, Channels, Chats (Followed threads) or
//   Channels, Chats (Saved).
// - Rows from 104.8, the picture (36, radius 4; the chat's or the team's)
//   at 32 and, 48 after it:
//   - Followed threads: the channel (14/20) and "· N replies" (12/16
//     #424242), the time at the right (12, #424242); the root post's line
//     (12/16 #424242); then the newest reply: its writer's 20 px picture,
//     "Name: text" (14/20, up to two lines).
//   - Saved: the chat or channel (14/20); then the writer's picture and
//     "Name: text" (14/20, up to two lines); Unsave this message (filled
//     bookmark) and More options at the right.
//   Followed threads shows Unfollow thread and More options on hover in the
//   time's place.
// - Until something is picked: Teams' picture (192, centred in the rest)
//   and "When you select a thread, it'll show up here" / "When you select a
//   saved item, it'll show up here." (16 bold) 212 under its top.
// Picking a row opens its chat or channel beside the list.
Rectangle {
    id: root
    /// "followed" or "saved".
    property string kind: "followed"
    property var items: []
    property bool loaded: false
    property string selectedKey: ""
    property string chip: ""
    signal openItem(var item)
    readonly property real paneWidth: 380
    readonly property bool followed: kind === "followed"
    readonly property var teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
    readonly property var shown: items.filter(i => !chip
        || (chip === "unread" ? i.unread : chip === "channels" ? i.channel : !i.channel))
    color: theme.surface

    // (kind, not followed: kind's change handler runs before followed
    // is updated.)
    function load() { backend.channelAction(kind === "followed" ? "quick-followed" : "quick-saved", "", "", "") }
    onVisibleChanged: if (visible) { selectedKey = ""; load() }
    onKindChanged: { items = []; loaded = false; chip = ""; selectedKey = ""; if (visible) load() }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === (root.kind === "followed" ? "quick-followed" : "quick-saved")) { root.loaded = true; root.items = r.ok ? r.data || [] : [] }
            else if ((r.op === "quick-unsave" && !root.followed) || (r.op === "quick-unfollow" && root.followed)) root.load()
        }
    }
    function key(i) { return i.thread_id + "|" + (followed ? i.reply_chain : i.message_id) }
    // A channel's name and its team (picture) from the team list.
    function channelOf(id) {
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === id); if (c) return { team: t, name: c.general ? "General" : c.name } }
        return null
    }
    function titleOf(i) { if (!i.channel) return i.topic; const c = channelOf(i.thread_id); return c ? c.name : i.topic }
    function stamp(t) {
        const d = new Date(t), now = new Date()
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (days === 0) return Qt.formatTime(d, "h:mm AP")
        if (days === 1) return "Yesterday"
        if (days > 1 && days < 7) return Qt.formatDate(d, "dddd")
        return Qt.formatDate(d, "M/d")
    }
    function esc(t) { return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    Rectangle {
        id: pane
        width: root.paneWidth; height: parent.height
        color: theme.surface
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Text {
            x: 32; y: 19
            text: root.followed ? "Followed threads" : "Saved"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: 32; y: 69.5
            spacing: 4
            Repeater {
                model: root.followed ? ["Unread", "Channels", "Chats"] : ["Channels", "Chats"]
                delegate: Rectangle {
                    id: qchip
                    required property string modelData
                    readonly property bool on: root.chip === modelData.toLowerCase()
                    height: 23.3; radius: height / 2
                    width: chipText.implicitWidth + 16
                    color: on ? theme.brandTint : (qch.hovered ? theme.rowHover : "transparent")
                    border.color: on ? theme.brand : theme.stroke; border.width: 0.67
                    HoverHandler { id: qch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.chip = qchip.on ? "" : qchip.modelData.toLowerCase() }
                    Text { id: chipText; anchors.centerIn: parent; text: qchip.modelData; font.family: theme.font; font.pixelSize: 12; color: qchip.on ? theme.brand : theme.textStrong }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData
                    Accessible.checked: on
                }
            }
        }
        ListView {
            id: list
            y: 104.8 - 12
            width: parent.width - 1; height: parent.height - y
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool sel: root.selectedKey === root.key(modelData)
                readonly property var ch: modelData.channel ? root.channelOf(modelData.thread_id) : null
                readonly property real bodyY: root.followed ? 52.7 : 30.7
                function toggle() {
                    if (root.followed) backend.channelAction("quick-unfollow", "", "", JSON.stringify({ thread: row.modelData.thread_id, chain: row.modelData.reply_chain }))
                    else backend.channelAction("quick-unsave", "", "", JSON.stringify({ thread: row.modelData.thread_id, chain: row.modelData.reply_chain, message: row.modelData.message_id }))
                }
                width: list.width; height: bodyY + body.height + 14.6
                Rectangle {
                    x: 8; width: parent.width - 16; height: parent.height - 4; radius: theme.radius
                    color: row.sel ? theme.selected : rh.hovered ? theme.pane : "transparent"
                }
                Avatar {
                    x: 32; y: 12; size: 36; square: !!row.modelData.channel; squareRadius: 4
                    name: row.ch ? row.ch.team.name : (row.modelData.topic || "?")
                    initialsText: row.ch ? (row.ch.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
                    photoId: row.ch ? "team:" + row.ch.team.id : ""
                    group: !row.modelData.channel
                }
                Row {
                    x: 80; y: 10; spacing: 6
                    Text { text: root.titleOf(row.modelData); width: Math.min(implicitWidth, 190); elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Text {
                        visible: root.followed
                        anchors.verticalCenter: parent.verticalCenter
                        text: "· " + row.modelData.replies + (row.modelData.replies === 1 ? " reply" : " replies")
                        font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                    }
                }
                Text {
                    visible: root.followed && !rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 32; y: 10
                    text: root.stamp(row.modelData.time)
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 19; lineHeightMode: Text.FixedHeight; color: theme.textStrong
                }
                Text {
                    visible: root.followed
                    x: 80; y: 32; width: parent.width - 80 - 32
                    text: row.modelData.parent_preview
                    elide: Text.ElideRight; maximumLineCount: 1
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong
                }
                Avatar { x: 80; y: row.bodyY + 1.8; size: 20; name: row.modelData.sender || "?"; photoId: row.modelData.sender_mri || "" }
                Text {
                    id: body
                    x: 80; y: row.bodyY + 2; width: parent.width - 80 - 52
                    // The writer's picture sits at the start of the first line.
                    text: "<span>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>" + root.esc(row.modelData.sender) + ": " + root.esc(row.modelData.preview)
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                // Saved: Unsave and More options; Followed threads: on hover,
                // Unfollow thread and More options.
                Row {
                    visible: !root.followed || rh.hovered
                    x: 292; y: 9.6; spacing: 8
                    Rectangle {
                        width: 24; height: 23.3; radius: 4
                        color: actHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: root.followed ? "followed-threads-20" : "bookmark-20-filled"; size: 20; color: theme.text }
                        HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: row.toggle() }
                        Accessible.role: Accessible.Button
                        Accessible.name: root.followed ? "Unfollow thread" : "Unsave this message"
                    }
                    Rectangle {
                        width: 24; height: 23.3; radius: 4
                        color: moreHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.text }
                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rowMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options"
                        MenuPopup {
                            id: rowMenu
                            y: parent.height + 4
                            items: [{ key: "open", label: root.followed ? "Go to thread" : "Go to message" }, { key: "toggle", label: root.followed ? "Unfollow thread" : "Unsave this message" }]
                            onPicked: i => items[i].key === "open" ? root.openItem(row.modelData) : row.toggle()
                        }
                    }
                }
                HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.selectedKey = root.key(row.modelData); root.openItem(row.modelData) } }
                Accessible.role: Accessible.Button
                Accessible.name: root.titleOf(row.modelData) + ", " + (row.modelData.sender || "") + ": " + (row.modelData.preview || "")
            }
        }
    }

    Item {
        id: hint
        visible: !root.selectedKey
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Image {
            x: (parent.width - 192) / 2; y: 220; width: 192; height: 192
            source: root.followed ? "../assets/illustrations/followed-threads.png" : "../assets/illustrations/saved-items.png"
            sourceSize: Qt.size(384, 384)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            width: parent.width; y: 432; horizontalAlignment: Text.AlignHCenter
            text: root.followed ? "When you select a thread, it'll show up here" : "When you select a saved item, it'll show up here."
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 24; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }

    // Test hooks.
    function itemsForTest() { return root.items }
}
