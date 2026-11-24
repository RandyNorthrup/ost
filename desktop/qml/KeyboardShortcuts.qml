import QtQuick
import QtQuick.Controls.Basic

// Keyboard shortcuts (Ctrl+.), laid out as Teams desktop's dialog
// (measured at 1x): a 900 px card with the title, "Use shortcuts from other
// apps" (the profile dropdown, Apply, and View options once another profile
// is picked), a filter box, and collapsible sections of action / key pills
// in two columns. It lists only the shortcuts OST implements, under Teams'
// section names. Picking a profile previews its keys (the changed rows
// highlighted, or brought to the top); Apply saves it as Teams does, in the
// synced keyboardShortcutsSettings.shortcutProfile (measured on winpc
// 2026-11-19).
Popup {
    id: root
    modal: true
    anchors.centerIn: parent
    width: Math.min(900, parent.width - 32)
    height: Math.min(583, parent.height - 32)
    padding: 0
    onOpened: { filter.text = ""; chosen = window.shortcutProfile; filter.forceActiveFocus() }
    background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }

    // Each row: [action, keys, Teams' command id].
    readonly property var sections: [
        { title: qsTr("General"), items: [
            [qsTr("Show keyboard shortcuts"), "Ctrl+.", "ShowShortcuts"], [qsTr("Open Search"), "Ctrl+E", "GoToPowerBar"],
            [qsTr("Go to a specific chat or channel"), "Ctrl+G", "SlashCommandGoto"], [qsTr("Start new chat"), "Ctrl+N", "StartNewChat"],
            [qsTr("Open filter"), "Ctrl+Shift+F", "OpenFilter"], [qsTr("Open Settings"), "Ctrl+,", "OpenSettings"],
            [qsTr("Toggle pin window on top"), "Ctrl+Shift+T", "TogglePinWindow"] ] },
        { title: qsTr("Navigation"), items: [
            [qsTr("Go to compose box"), "Ctrl+R", "Compose"], [qsTr("Go back"), "Alt+Left", "GoBack"], [qsTr("Go forward"), "Alt+Right", "GoForward"],
            [qsTr("Open 1st app on app bar"), "Ctrl+1", "AppbarShortcut0"], [qsTr("Open 2nd app on app bar"), "Ctrl+2", "AppbarShortcut1"],
            [qsTr("Open 3rd app on app bar"), "Ctrl+3", "AppbarShortcut2"], [qsTr("Open 4th app on app bar"), "Ctrl+4", "AppbarShortcut3"],
            [qsTr("Open 5th app on app bar"), "Ctrl+5", "AppbarShortcut4"] ] },
        { title: qsTr("Compose"), items: [
            [qsTr("Start new line"), "Shift+Enter", "NewLine"], [qsTr("Attach file"), "Alt+Shift+O", "UploadFile"],
            [qsTr("Apply bold style"), "Ctrl+B", "Bold"], [qsTr("Apply italic style"), "Ctrl+I", "Italic"],
            [qsTr("Apply underline style"), "Ctrl+U", "Underline"], [qsTr("Apply strikethrough style"), "Ctrl+Alt+X", "Strikethrough"],
            [qsTr("Undo", "shortcut:k94ba4q11"), "Ctrl+Z", "Undo"], [qsTr("Redo"), "Ctrl+Y", "Redo"], [qsTr("Cut"), "Ctrl+X", "Cut"], [qsTr("Copy"), "Ctrl+C", "CopyMessage"],
            [qsTr("Paste"), "Ctrl+V", "Paste"], [qsTr("Select all"), "Ctrl+A", "SelectAll"] ] },
        { title: qsTr("Messaging"), items: [
            [qsTr("Find in current chat or channel"), "Ctrl+F", "SlashCommandSearchIn"], [qsTr("React to the last message"), "Ctrl+Alt+R", "ReactToLastMessage"],
            [qsTr("Jump to last read or newest message"), "Ctrl+J", "UnreadThreadNavigation"],
            [qsTr("Mark all as read"), "Shift+Esc", "MarkAllAsRead"], [qsTr("Clear all filters"), "Ctrl+Alt+Z", "SimpleCollabClearAllFilters"],
            [qsTr("See all chat conversations"), "Ctrl+Alt+C", "SimpleCollabToggleChatsFilter"], [qsTr("See all channel conversations"), "Ctrl+Alt+A", "SimpleCollabToggleChannelsFilter"],
            [qsTr("See all unread items"), "Ctrl+Alt+U", "SimpleCollabToggleUnreadFilter"], [qsTr("Toggle details pane"), "Alt+P", "ToggleInfoPane"],
            [qsTr("Open 1st tab on chat header"), "Alt+1", "FocusChatHeaderTabOne"], [qsTr("Open 2nd tab on chat header"), "Alt+2", "FocusChatHeaderTabTwo"],
            [qsTr("Open 3rd tab on chat header"), "Alt+3", "FocusChatHeaderTabThree"], [qsTr("Open 4th tab on chat header"), "Alt+4", "FocusChatHeaderTabFour"],
            [qsTr("Open 5th tab on chat header"), "Alt+5", "FocusChatHeaderTabFive"] ] },
        { title: qsTr("Meetings, Calls and Calendar"), items: [
            [qsTr("Toggle mute"), "Ctrl+Shift+M", "ToggleMuteCurrentCall"], [qsTr("Toggle video"), "Ctrl+Shift+O", "ToggleVideoCurrentCall"],
            [qsTr("Leave meeting or call"), "Ctrl+Shift+H", "LeaveCall"],
            [qsTr("Announce active speaker (screen reader)"), "Ctrl+Alt+Shift+S", "AnnounceActiveSpeaker"],
            [qsTr("Start audio call"), "Alt+Shift+A", "StartAudioCallInChat"], [qsTr("Accept audio call"), "Ctrl+Shift+S", "AcceptIncomingCallWithAudio"],
            [qsTr("Accept video call"), "Ctrl+Shift+A", "AcceptIncomingCallWithVideo"], [qsTr("Decline call"), "Ctrl+Shift+D", "RejectIncomingCall"],
            [qsTr("Schedule a meeting"), "Alt+N", "ScheduleMeeting"] ] }
    ]
    // Teams' Windows desktop profiles (async-entry Z: L, N, V): the keys
    // they give each command.
    readonly property var slackKeys: ({
        AppbarShortcut0: "Ctrl+Shift+1", AppbarShortcut1: "Ctrl+Shift+2", AppbarShortcut2: "Ctrl+Shift+3",
        AppbarShortcut3: "Ctrl+Shift+4", AppbarShortcut4: "Ctrl+Shift+5",
        ShowShortcuts: "Ctrl+;", GoToPowerBar: "Ctrl+G", SlashCommandGoto: "Ctrl+K", ToggleInfoPane: "Ctrl+.",
        ReactToLastMessage: "Ctrl+Shift+\\", SimpleCollabToggleUnreadFilter: "Ctrl+Alt+A",
        SimpleCollabToggleChannelsFilter: "Ctrl+Alt+U" })
    readonly property var zoomKeys: ({
        AcceptIncomingCallWithVideo: "Ctrl+Shift+V", AcceptIncomingCallWithAudio: "Ctrl+Shift+A",
        ToggleMuteCurrentCall: "Alt+A", ToggleVideoCurrentCall: "Alt+V", AnnounceActiveSpeaker: "Ctrl+2", LeaveCall: "Alt+Q" })
    function profileKeys(p) {
        if (p === "chats_alt") return slackKeys
        if (p === "meetings_alt") return zoomKeys
        if (p === "chats_meetings_alt") return Object.assign({}, slackKeys, zoomKeys)
        return ({})
    }
    readonly property var profiles: ["default", "chats_alt", "meetings_alt", "chats_meetings_alt"]
    // The profile being looked at (Apply saves it).
    property string chosen: "default"
    readonly property var chosenKeys: profileKeys(chosen)
    // How many of the listed shortcuts a profile changes.
    function changeCount(p) {
        const k = profileKeys(p)
        let n = 0
        for (const s of sections) for (const i of s.items) if (k[i[2]] && k[i[2]] !== i[1]) n++
        return n
    }
    function keysOf(item) { return chosenKeys[item[2]] || item[1] }
    function changed(item) { return !!chosenKeys[item[2]] && chosenKeys[item[2]] !== item[1] }
    // View options (Teams' defaults: highlight on, bring to top off).
    property bool highlightChanges: true
    property bool changesFirst: false
    signal applyProfile(string profile)

    property var collapsed: ({})
    function matches(item) {
        const q = filter.text.trim().toLowerCase()
        return !q || item[0].toLowerCase().indexOf(q) >= 0 || keysOf(item).toLowerCase().indexOf(q) >= 0
    }
    function shownItems(sec) {
        const all = sec.items.filter(i => root.matches(i))
        if (!changesFirst) return all
        return all.filter(i => changed(i)).concat(all.filter(i => !changed(i)))
    }

    contentItem: Item {
        Text {
            x: 25; y: 28
            text: qsTr("Keyboard shortcuts")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            id: hcFill1
            x: parent.width - 49; y: 28; width: 32; height: 31; radius: theme.radius
            color: xh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
            HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        // Teams' "Use shortcuts from other apps" (shortcut-profile-dropdown,
        // 224 x 30; Apply 62 x 31; View options 32 x 31).
        Text {
            x: 23; y: 66; height: 24
            text: qsTr("Use shortcuts from other apps")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 24; lineHeightMode: Text.FixedHeight
            verticalAlignment: Text.AlignVCenter
            color: theme.text
        }
        OutlineDropdown {
            id: profileBox
            x: 23; y: 90; width: 224; height: 30
            options: root.profiles.map(p => p === "default"
                ? { label: qsTr("OST only"), sublabel: qsTr("Default"), display: "OST only (default)" }
                : { label: p === "chats_alt" ? qsTr("OST + Slack shortcuts") : p === "meetings_alt" ? qsTr("OST + Zoom shortcuts") : qsTr("OST + combined shortcuts"),
                    sublabel: root.changeCount(p) + " available changes" })
            current: Math.max(0, root.profiles.indexOf(root.chosen))
            accessibleName: qsTr("Use shortcuts from other apps")
            onPicked: i => root.chosen = root.profiles[i]
        }
        Rectangle {
            id: applyBtn
            readonly property bool usable: root.chosen !== window.shortcutProfile
            x: 258; y: 90; width: 62; height: 31; radius: 4
            color: !usable ? theme.bgDisabled : applyHover.hovered ? theme.brandHover : theme.brand
            border.color: theme.highContrast ? theme.text : "transparent"; border.width: 0.67
            Text {
                anchors.centerIn: parent
                text: qsTr("Apply")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: applyBtn.usable ? theme.hc("#FFFFFF", "#000000") : theme.disabled
            }
            HoverHandler { id: applyHover; cursorShape: applyBtn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: applyBtn.usable; onTapped: root.applyProfile(root.chosen) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Apply")
        }
        Rectangle {
            id: viewBtn
            visible: root.chosen !== "default"
            x: 328; y: 90; width: 32; height: 31; radius: 4
            color: viewMenu.opened || viewHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "options-20"; size: 20; color: theme.onFill(viewBtn, theme.textStrong) }
            HoverHandler { id: viewHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: viewMenu.opened ? viewMenu.close() : viewMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("View options")
            // Teams' View options menu: 300 wide under the button, ending at
            // its right; two 52 px rows (icon 20 at 6, text 207 wide at 30,
            // a switch).
            Popup {
                id: viewMenu
                x: viewBtn.width - width; y: viewBtn.height
                width: 300; padding: 4
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                contentItem: Column {
                    spacing: 2
                    Repeater {
                        model: [
                            { icon: "highlight-20", text: qsTr("Highlight shortcuts from other apps"), key: "highlight" },
                            { icon: "arrow-sort-20", text: qsTr("Bring shortcuts from other apps to top"), key: "top" }
                        ]
                        Rectangle {
                            id: vrow
                            required property var modelData
                            readonly property bool on: modelData.key === "highlight" ? root.highlightChanges : root.changesFirst
                            width: 291; height: 52; radius: 4
                            color: vrowHover.hovered ? theme.menuHover : theme.surface
                            FluentIcon { x: 6; y: 6; name: vrow.modelData.icon; size: 20; color: theme.onFill(vrow, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                            Text {
                                x: 30; y: 6; width: 207
                                wrapMode: Text.Wrap; text: vrow.modelData.text
                                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.onFill(vrow, theme.pick("#424242", "#D6D6D6", "#FFFFFF"))
                            }
                            SettingsParts.Toggle {
                                x: 241; y: 6
                                stateLabel: false
                                on: vrow.on
                                accessibleName: vrow.modelData.text
                                onToggled: v => { if (vrow.modelData.key === "highlight") root.highlightChanges = v; else root.changesFirst = v }
                            }
                            HoverHandler { id: vrowHover }
                            TapHandler { onTapped: { if (vrow.modelData.key === "highlight") root.highlightChanges = !root.highlightChanges; else root.changesFirst = !root.changesFirst } }
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: vrow.modelData.text
                            Accessible.checked: vrow.on
                        }
                    }
                }
            }
        }
        // Filter shortcuts
        Rectangle {
            x: parent.width - 23 - width; y: 90
            width: 280; height: 31; radius: theme.radius
            color: theme.input
            border.color: filter.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: filter
                x: 34; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                Keys.onEscapePressed: text ? text = "" : root.close()
                Text { visible: !filter.text; text: qsTr("Filter shortcuts"); font: filter.font; color: theme.textSecondary }
                Accessible.name: qsTr("Filter shortcuts")
            }
        }
        Flickable {
            id: flick
            x: 25; y: 131
            width: parent.width - 50; height: parent.height - y - 16
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: col
                width: flick.width - 12
                spacing: 8
                Repeater {
                    model: root.sections
                    Column {
                        id: sec
                        required property var modelData
                        readonly property var shown: root.shownItems(modelData)
                        readonly property bool open: root.collapsed[modelData.title] !== true
                        visible: shown.length > 0
                        width: col.width
                        Item {
                            width: parent.width; height: 44
                            FluentIcon {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                name: sec.open ? "chevron-down-16" : "chevron-right-12"; size: sec.open ? 16 : 12
                                color: theme.textStrong
                            }
                            Text {
                                x: 30; anchors.verticalCenter: parent.verticalCenter
                                text: sec.modelData.title
                                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                                color: theme.text
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    const c = Object.assign({}, root.collapsed)
                                    c[sec.modelData.title] = sec.open
                                    root.collapsed = c
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: sec.open ? qsTr("%1, expanded").arg(sec.modelData.title) : qsTr("%1, collapsed").arg(sec.modelData.title)
                        }
                        Grid {
                            visible: sec.open
                            columns: 2
                            columnSpacing: 24
                            Repeater {
                                model: sec.shown
                                Item {
                                    id: srow
                                    required property var modelData
                                    // A profile's change, highlighted as Teams
                                    // does (colorBrandBackground2Hover, 600).
                                    readonly property bool marked: root.highlightChanges && root.changed(modelData)
                                    readonly property color markFill: theme.pick("#DCE0FA", "#383966", "#000000")
                                    width: (sec.width - 24) / 2; height: 44
                                    Text {
                                        x: 18; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - pill.width - 36
                                        wrapMode: Text.Wrap; maximumLineCount: 2
                                        textFormat: srow.marked ? Text.RichText : Text.PlainText
                                        text: srow.marked ? "<span style=\"background-color:" + srow.markFill + "\"><b>" + srow.modelData[0] + "</b></span>" : srow.modelData[0]
                                        font.family: theme.font; font.pixelSize: theme.base
                                        color: theme.text
                                    }
                                    Rectangle {
                                        id: pill
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 141; height: 32; radius: 16
                                        color: theme.searchFill; border.color: theme.transparentStroke
                                        Text {
                                            anchors.centerIn: parent
                                            textFormat: srow.marked ? Text.RichText : Text.PlainText
                                            text: srow.marked
                                                ? root.keysOf(srow.modelData).split("+").map(k => "<span style=\"background-color:" + srow.markFill + "\"><b>" + k.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b></span>").join(" + ")
                                                : root.keysOf(srow.modelData).split("+").join(" + ")
                                            font.family: theme.font; font.pixelSize: theme.base
                                            color: theme.text
                                        }
                                    }
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: modelData[0] + ": " + root.keysOf(modelData)
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: root.sections.every(s => !s.items.some(i => root.matches(i)))
                    text: qsTr("No shortcuts match")
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
            }
        }
    }
}
