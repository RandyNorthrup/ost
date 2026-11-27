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
//     (12/16 #424242: its subject, else its preview; a deleted post's or a
//     channel meeting's after Teams' 16 px delete / calendar glyph, 6
//     before the text; an unread thread's channel and root line bold
//     (700) with a 4 px #242424 dot 22 in, its bottom on the root line's top;
//     TASK-0272); then the newest reply: its writer's 20 px picture,
//     "Name: text" (14/20, up to two lines).
//   - Saved: the chat or channel (14/20); then the writer's picture and
//     "Name: text" (14/20, up to two lines); Unsave this message (filled
//     bookmark) and More options at the right.
//   Followed threads shows Unfollow thread and More options on hover in the
//   time's place.
// - Until something is picked: Teams' picture (192, centred in the rest)
//   and "When you select a thread, it'll show up here" / "When you select a
//   saved item, it'll show up here." (16 bold) 212 under its top.
// Picking a row opens its chat or channel beside the list; a channel's
// post opens as Teams' single-thread view there (Main's PostThread,
// TASK-0265). With that view's Copilot open the list takes the chat list's
// place (`compact`, measured on winpc 2026-11-24): 320 wide, "Return to
// list" (32 x 31.3, 20 in, 14.3 down) before the title (at 64) and a line
// under the header (4 in, 60 down).
// Reminders (Teams' REMINDERS slice over 48:reminders; measured on Teams
// on the web 2026-11-27): the pills Due / Upcoming / Completed (any
// together; none picked shows all), rows 93 tall: the sender's picture
// (36, round) at 32, 14 down; their name (14/20) 12 down and the message
// (14/20, one line) 34 down at 80; 58 down the due chip (20 tall, radius
// 4, 6 in, brandBackground2 with the 16 px alarm and 12/600 brand text:
// the time today or month/day else, "Due …" once due, "Completed");
// on hover Mark as completed (a circle check) and More options (Edit
// reminder ▸, Remove reminder, Go to conversation) at the end, 10 down;
// "You have no new reminders." with none.
Rectangle {
    id: root
    /// "followed", "saved" or "reminders".
    property string kind: "followed"
    property var items: []
    property bool loaded: false
    property string selectedKey: ""
    property string chip: ""
    signal openItem(var item)
    property bool compact: false
    readonly property real paneWidth: compact ? 320 : 380
    signal backRequested()
    readonly property bool followed: kind === "followed"
    readonly property bool reminders: kind === "reminders"
    /// The Reminders pills turned on.
    property var pills: []
    readonly property var reminderItems: { try { return JSON.parse(backend.remindersJson || "[]") } catch (e) { return [] } }
    function reminderState(r) { return r.completed > 0 ? "completed" : r.is_due ? "due" : "upcoming" }
    function dueLabel(r) {
        if (r.completed > 0) return qsTr("Completed")
        const d = new Date(r.due)
        const t = d.toDateString() === new Date().toDateString() ? theme.time(d) : (d.getMonth() + 1) + "/" + d.getDate()
        return r.is_due ? qsTr("Due %1").arg(t) : t
    }
    readonly property var teams: backend.teamsJson ? JSON.parse(backend.teamsJson) : []
    // (Teams drops a thread whose conversation it doesn't know — its slice
    // item needs one — so a followed thread of a channel you're no longer
    // in, or one that was deleted, isn't listed.)
    readonly property var shown: reminders ? reminderItems.filter(r => !pills.length || pills.indexOf(reminderState(r)) >= 0) : items.filter(i => (!chip
        || (chip === "unread" ? i.unread : chip === "channels" ? i.channel : !i.channel))
        && (!followed || !i.channel || !teams.length || !!channelOf(i.thread_id)))
    color: theme.surface
    // Up / Down / Home / End through the rows, as Teams' (ListKeys).
    property alias enterToOpen: keys.enterToOpen
    ListKeys {
        id: keys
        owner: root
        view: list
        items: root.shown
        keyOf: i => root.key(i)
        onOpen: item => { root.selectedKey = root.key(item); root.openItem(item) }
    }
    Keys.onPressed: e => keys.handle(e, root.selectedKey)
    function keysForTest() { return keys }

    // (kind, not followed: kind's change handler runs before followed
    // is updated.)
    function load() {
        if (kind === "reminders") { backend.loadReminders(); return }
        backend.channelAction(kind === "followed" ? "quick-followed" : "quick-saved", "", "", "")
    }
    onVisibleChanged: if (visible) { selectedKey = ""; load(); forceActiveFocus() }
    onKindChanged: { items = []; loaded = false; chip = ""; pills = []; selectedKey = ""; if (visible) load() }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === (root.kind === "followed" ? "quick-followed" : "quick-saved")) { root.loaded = true; root.items = r.ok ? r.data || [] : [] }
            else if ((r.op === "quick-unsave" && !root.followed) || (r.op === "quick-unfollow" && root.followed)) root.load()
        }
    }
    function key(i) { return i.thread_id + "|" + (followed ? i.reply_chain : i.message_id) }
    // A reminder's ··· ▸ Edit reminder presets (as the message menu's).
    ReminderPresets { id: presets }
    // A channel's name and its team (picture) from the team list.
    function channelOf(id) {
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === id); if (c) return { team: t, name: c.general ? qsTr("General") : c.name } }
        return null
    }
    function titleOf(i) { if (!i.channel) return i.topic; const c = channelOf(i.thread_id); return c ? c.name : i.topic }
    function stamp(t) {
        const d = new Date(t), now = new Date()
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (days === 0) return theme.time(d)
        if (days === 1) return qsTr("Yesterday")
        if (days > 1 && days < 7) return theme.fmtDate(d, "dddd")
        return theme.dateNoYear(d)
    }
    function esc(t) { return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    Rectangle {
        id: pane
        width: root.paneWidth; height: parent.height
        color: theme.surface
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Rectangle {
            id: backButton
            visible: root.compact
            x: 20; y: 14.3; width: 32; height: 31.3; radius: 4
            color: backHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.onFill(backButton, backHover.hovered ? theme.brand : theme.textStrong) }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.backRequested() }
            ToolTip.visible: backHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Return to list")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Return to list")
        }
        Rectangle { visible: root.compact; x: 4; y: 60; width: parent.width - 4; height: 0.67; color: theme.divider }
        Text {
            x: root.compact ? 64 : 32; y: 19
            text: root.followed ? qsTr("Followed threads") : root.reminders ? qsTr("Reminders") : qsTr("Saved")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: 32; y: 69.5
            spacing: 4
            Repeater {
                model: root.followed ? [{ key: "unread", label: qsTr("Unread") }, { key: "channels", label: qsTr("Channels") }, { key: "chats", label: qsTr("Chats") }]
                    : root.reminders ? [{ key: "due", label: qsTr("Due") }, { key: "upcoming", label: qsTr("Upcoming") }, { key: "completed", label: qsTr("Completed") }]
                    : [{ key: "channels", label: qsTr("Channels") }, { key: "chats", label: qsTr("Chats") }]
                delegate: Rectangle {
                    id: qchip
                    required property var modelData
                    readonly property bool on: root.reminders ? root.pills.indexOf(modelData.key) >= 0 : root.chip === modelData.key
                    height: 23.3; radius: height / 2
                    width: chipText.implicitWidth + 16
                    color: on ? theme.hc(theme.brandTint, theme.hcHighlight) : (qch.hovered ? theme.rowHover : "transparent")
                    border.color: on ? theme.brand : theme.stroke; border.width: 0.67
                    HoverHandler { id: qch; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (!root.reminders) { root.chip = qchip.on ? "" : qchip.modelData.key; return }
                            const p = root.pills.filter(k => k !== qchip.modelData.key)
                            root.pills = qchip.on ? p : p.concat([qchip.modelData.key])
                        }
                    }
                    Text { id: chipText; anchors.centerIn: parent; text: qchip.modelData.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(qchip, qchip.on ? theme.brand : theme.textStrong) }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData.label
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
                readonly property bool rem: root.reminders
                function toggle() {
                    if (root.followed) backend.channelAction("quick-unfollow", "", "", JSON.stringify({ thread: row.modelData.thread_id, chain: row.modelData.reply_chain }))
                    else backend.channelAction("quick-unsave", "", "", JSON.stringify({ thread: row.modelData.thread_id, chain: row.modelData.reply_chain, message: row.modelData.message_id }))
                }
                width: list.width; height: rem ? 93 + 4 : bodyY + body.height + 14.6
                Rectangle {
                    id: hcFill1
                    x: 8; width: parent.width - 16; height: parent.height - 4; radius: theme.radius
                    color: row.sel ? theme.selected : rh.hovered ? theme.pane : "transparent"
                }
                Rectangle {
                    visible: keys.ringOn(row.modelData)
                    z: 2
                    x: 8; width: parent.width - 16; height: parent.height - 4; radius: theme.radius
                    color: "transparent"; border.width: 2; border.color: theme.text
                }
                // Followed threads: an unread thread's 4 px dot left of the
                // picture (Teams' unread indicator).
                Rectangle {
                    objectName: "followedUnreadDot"
                    visible: root.followed && row.modelData.unread === true
                    x: 22; y: 28; width: 4; height: 4; radius: 2
                    color: theme.onFill(hcFill1, theme.text)
                }
                Avatar {
                    visible: !row.rem
                    x: 32; y: 12; size: 36; square: !!row.modelData.channel; squareRadius: 4
                    name: row.ch ? row.ch.team.name : (row.modelData.topic || "?")
                    initialsText: row.ch ? (row.ch.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
                    photoId: row.ch ? "team:" + row.ch.team.id : ""
                    group: !row.modelData.channel
                }
                Row {
                    visible: !row.rem
                    x: 80; y: 10; spacing: 6
                    Text { text: root.titleOf(row.modelData); font.weight: root.followed && row.modelData.unread ? Font.Bold : Font.Normal; width: Math.min(implicitWidth, root.paneWidth - 190, root.paneWidth - 80 - 32 - 64 - (repliesLabel.visible ? repliesLabel.implicitWidth + 6 : 0)); elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.text) }
                    Text {
                        id: repliesLabel
                        visible: root.followed
                        anchors.verticalCenter: parent.verticalCenter
                        text: "· " + row.modelData.replies + (row.modelData.replies === 1 ? " reply" : " replies")
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill1, theme.textStrong)
                    }
                }
                Text {
                    visible: root.followed && !rh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 32; y: 10
                    text: root.stamp(row.modelData.time)
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 19; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.textStrong)
                }
                // The root post's line: its subject, else its preview, after
                // Teams' glyph for a deleted post or a channel meeting's.
                Item {
                    id: parentLine
                    objectName: "followedParentLine"
                    visible: root.followed
                    readonly property string iconName: row.modelData.parent_icon === "meeting" ? "calendar-20" : row.modelData.parent_icon === "deleted" ? "delete-20" : ""
                    readonly property string lineText: row.modelData.parent_subject || row.modelData.parent_preview || ""
                    readonly property Item iconItem: parentIcon
                    readonly property Item textItem: parentText
                    x: 80; y: 32; width: parent.width - 80 - 32; height: 16
                    FluentIcon {
                        id: parentIcon
                        visible: parentLine.iconName !== ""
                        size: 16; name: parentLine.iconName
                        color: theme.onFill(hcFill1, theme.textStrong)
                    }
                    Text {
                        id: parentText
                        x: parentIcon.visible ? 16 + 6 : 0; width: parent.width - x
                        text: parentLine.lineText
                        elide: Text.ElideRight; maximumLineCount: 1
                        font.weight: root.followed && row.modelData.unread ? Font.Bold : Font.Normal
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.textStrong)
                    }
                }
                Avatar { visible: !row.rem; x: 80; y: row.bodyY + 1.8; size: 20; name: row.modelData.sender || "?"; photoId: row.modelData.sender_mri || "" }
                // A reminder: who wrote it, the message and the due chip.
                Avatar { visible: row.rem; x: 32; y: 14; size: 36; name: row.modelData.sender || "?"; photoId: row.modelData.sender_mri || "" }
                Text {
                    visible: row.rem
                    x: 80; y: 12; width: parent.width - 80 - 100
                    text: row.modelData.sender || ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.text)
                }
                Text {
                    visible: row.rem
                    x: 80; y: 34; width: parent.width - 80 - 32
                    text: row.modelData.preview || ""
                    elide: Text.ElideRight; maximumLineCount: 1
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.text)
                }
                Rectangle {
                    id: dueChip
                    visible: row.rem
                    x: 80; y: 58; height: 20; radius: 4
                    width: 6 + 16 + 4 + dueText.implicitWidth + 6
                    color: theme.pick("#E8EBFA", "#3D3E78", "#000000")
                    border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                    FluentIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; name: "clock-alarm-16"; size: 16; color: theme.onFill(dueChip, theme.brandLink) }
                    Text { id: dueText; x: 6 + 16 + 4; anchors.verticalCenter: parent.verticalCenter; text: row.rem ? root.dueLabel(row.modelData) : ""; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(dueChip, theme.brandLink) }
                }
                Row {
                    visible: row.rem && rh.hovered
                    x: parent.width - 16 - 8 - width; y: 10; spacing: 8
                    Rectangle {
                        id: hcFillDone
                        visible: row.rem && !(row.modelData.completed > 0)
                        width: 24; height: 24; radius: 4
                        color: doneHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: doneHover.hovered ? "checkmark-circle-20-filled" : "checkmark-circle-20"; size: 20; color: theme.onFill(hcFillDone, theme.text) }
                        HoverHandler { id: doneHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.completeReminder(row.modelData.thread_id, row.modelData.message_id, row.modelData.reply_chain || "") }
                        ToolTip.visible: doneHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Mark as completed")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Mark as completed")
                    }
                    Rectangle {
                        id: hcFillRemMore
                        width: 24; height: 24; radius: 4
                        color: remMoreHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFillRemMore, theme.text) }
                        HoverHandler { id: remMoreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const t = presets.times(new Date())
                                remMenu.times = t
                                remMenu.items = [{ key: "edit", label: qsTr("Edit reminder"), submenu: presets.submenu(t, false) },
                                                 { key: "remove", label: qsTr("Remove reminder") },
                                                 { key: "open", label: qsTr("Go to conversation") }]
                                remMenu.open()
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More options")
                        MenuPopup {
                            id: remMenu
                            property var times: null
                            y: parent.height + 4
                            chevronSize: 20; chevronMargin: 5.6
                            submenuMinWidth: 162
                            onPicked: i => {
                                const m = row.modelData
                                if (items[i].key === "remove") backend.removeReminderAt(m.thread_id, m.message_id, m.reply_chain || "")
                                else if (items[i].key === "open") { root.selectedKey = root.key(m); root.openItem(m) }
                            }
                            onSubPicked: (i, j) => {
                                const m = row.modelData, k = items[i].submenu[j].key, t = remMenu.times
                                const at = presets.at(k, t)
                                if (at) backend.setReminderAt(m.thread_id, m.message_id, m.reply_chain || "", at.getTime())
                                else if (k === "custom") { remCustom.item = m; remCustom.open() }
                            }
                        }
                    }
                }
                Text {
                    id: body
                    visible: !row.rem
                    x: 80; y: row.bodyY + 2; width: parent.width - 80 - 52
                    // The writer's picture sits at the start of the first line.
                    text: "<span>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>" + root.esc(row.modelData.sender) + ": " + root.esc(row.modelData.preview)
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.onFill(hcFill1, theme.text)
                }
                // Saved: Unsave and More options; Followed threads: on hover,
                // Unfollow thread and More options.
                Row {
                    visible: !row.rem && (!root.followed || rh.hovered)
                    x: root.paneWidth - 88; y: 9.6; spacing: 8
                    Rectangle {
                        id: hcFill2
                        width: 24; height: 23.3; radius: 4
                        color: actHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: root.followed ? "followed-threads-20" : "bookmark-20-filled"; size: 20; color: theme.onFill(hcFill2, theme.text) }
                        HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: row.toggle() }
                        Accessible.role: Accessible.Button
                        Accessible.name: root.followed ? qsTr("Unfollow thread") : qsTr("Unsave this message")
                    }
                    Rectangle {
                        id: hcFill3
                        width: 24; height: 23.3; radius: 4
                        color: moreHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill3, theme.text) }
                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rowMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More options")
                        MenuPopup {
                            id: rowMenu
                            y: parent.height + 4
                            items: [{ key: "open", label: root.followed ? qsTr("Go to thread") : qsTr("Go to message") }, { key: "toggle", label: root.followed ? qsTr("Unfollow thread") : qsTr("Unsave this message") }]
                            onPicked: i => items[i].key === "open" ? root.openItem(row.modelData) : row.toggle()
                        }
                    }
                }
                HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { keys.clicked(row.modelData); root.selectedKey = root.key(row.modelData); root.openItem(row.modelData) } }
                Accessible.role: Accessible.Button
                Accessible.name: row.rem ? (row.modelData.sender || "") + ": " + (row.modelData.preview || "") + ", " + root.dueLabel(row.modelData)
                    : root.titleOf(row.modelData) + ", " + (row.modelData.sender || "") + ": " + (row.modelData.preview || "")
            }
        }
        Text {
            visible: root.reminders && root.shown.length === 0
            x: 32; y: 120; width: parent.width - 64
            wrapMode: Text.Wrap
            text: qsTr("You have no new reminders.")
            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
        }
    }
    CustomReminderDialog {
        id: remCustom
        property var item: null
        due: item && item.due > Date.now() ? new Date(item.due) : null
        onAdded: when => backend.setReminderAt(item.thread_id, item.message_id, item.reply_chain || "", when.getTime())
    }

    Item {
        id: hint
        visible: !root.selectedKey
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Image {
            x: (parent.width - 192) / 2; y: 220; width: 192; height: 192
            source: root.followed ? "../assets/illustrations/followed-threads.png" : root.reminders ? "../assets/illustrations/reminders.svg" : "../assets/illustrations/saved-items.png"
            sourceSize: Qt.size(384, 384)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            width: parent.width; y: 432; horizontalAlignment: Text.AlignHCenter
            text: root.followed ? qsTr("When you select a thread, it'll show up here") : root.reminders ? qsTr("When you select a reminder, it'll show up here.") : qsTr("When you select a saved item, it'll show up here.")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 24; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }

    // Test hooks.
    function itemsForTest() { return root.items }
}
