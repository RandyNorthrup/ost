import QtQuick
import QtQuick.Controls.Basic

// Manage channel ▸ Settings ▸ Moderation for a channel other than General
// (Teams' channel settings, measured on winpc 2026-11-09 on "OST test
// channel"; docs/spec/chat-list-and-header.md §7.7.1). Laid out from the
// section's body, 38 in like the other sections:
// - "Channel moderation" (12/16) and its dropdown 26 down (355 x 31.3,
//   filled-darker #F5F5F5, radius 4, the value 14/20 semibold at 12): On or
//   Off. Its list opens 2 under it (355 wide, padding 4, 32 tall rows 2
//   apart, the names at 32, the chosen one bold). Changing it writes Teams'
//   defaults with only moderators (On) or everyone (Off) starting posts.
// - Off: "Who can start a new post?" 72.4 down and Teams' two radios
//   (Everyone can start a new post, Everyone except guests can start a new
//   post), 32 apart from 98.4.
// - On:
//   - "Who are the moderators?" 72.4 down; who they are (14/20, brand) 104.7
//     down: Team owners (Channel owners in private and shared channels) and
//     up to two added moderators by name (15 letters, then "..."), "+ N"
//     for the rest. Hovering it shows them above, grouped (Team owners,
//     Moderators), each with their picture (32) and name (12/16); a name
//     opens a chat with them. Manage (96 x 31.3) 260 in opens Add or remove
//     moderators.
//   - "Who can start a new post?" 144.7 down, "Only moderators" (14/20)
//     170.7 down.
//   - "Team member permissions" (14/20 semibold) 205.7 down and three
//     checkboxes 42 apart from 235.7: Allow members to reply to channel
//     messages, Allow members to pin channel messages, Allow bots to submit
//     channel messages.
// Only team owners and moderators can change them; for anyone else they
// show disabled. Each change is written at once (channelSettings).
Item {
    id: root
    property string teamId: ""
    property string channelId: ""
    property string channelType: "Standard"
    property bool canChange: true
    property string myMri: ""
    property string myPresence: ""
    // {post, replies, pins, bots, connectors} once loaded.
    property var settings: null
    property var owners: []
    property var moderators: []
    property bool saving: false
    readonly property bool loaded: settings !== null
    readonly property bool moderated: loaded && settings.post === 1
    readonly property bool privateLike: channelType === "Private" || channelType === "Shared"
    readonly property string ownersLabel: privateLike ? "Channel owners" : "Team owners"
    width: parent ? parent.width : 0
    height: !loaded ? 72 : moderated ? 358.7 : 169.4

    function load() {
        settings = null; owners = []; moderators = []
        if (channelId) backend.channelAction("channel-settings-load", teamId, channelId, "")
    }
    function change(fields) {
        if (!canChange || saving) return
        saving = true
        // Show it at once, as Teams does, and settle on what was written.
        settings = Object.assign({}, settings, fields)
        backend.channelAction("channel-settings", teamId, channelId, JSON.stringify(fields))
    }
    onChannelIdChanged: load()
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== root.channelId) return
            if (r.op === "channel-settings-load" && r.ok) {
                root.settings = r.data.settings
                root.owners = r.data.owners || []
                root.moderators = r.data.moderators || []
            } else if (r.op === "channel-settings") {
                root.saving = false
                if (r.ok) {
                    root.settings = r.data.settings
                    root.moderators = r.data.moderators || []
                } else {
                    root.load()
                    backend.toast("Something went wrong on our end. Please try again.", "error")
                }
            } else if (r.op === "moderators" && r.ok) {
                root.moderators = r.data.moderators || []
                if (r.data.error) backend.toast(r.data.error, "error")
            }
        }
    }

    // Teams' summary of who moderates: the owners' group, then up to two
    // added moderators by name, then "+ N".
    readonly property string summary: {
        const names = moderators.map(m => m.name).filter(n => n).map(n => n.length > 15 ? n.substring(0, 15) + "..." : n)
        const s = [ownersLabel].concat(names.slice(0, 2)).join(", ")
        return names.length > 2 ? s + " + " + (names.length - 2) : s
    }

    component Caption: Text {
        x: 38
        font.family: theme.font; font.pixelSize: 12
        lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.text
    }

    Caption { y: 0; text: "Channel moderation" }

    // The dropdown (Fluent filled-darker).
    Rectangle {
        id: dropdown
        x: 38; y: 26; width: 355; height: 31.3; radius: 4
        color: !root.canChange || !root.loaded ? theme.bgDisabled : theme.inputFilled
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: !root.loaded ? "" : root.moderated ? "On" : "Off"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: root.canChange ? theme.text : theme.disabled
        }
        FluentIcon {
            x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down-20"; size: 20
            color: root.canChange ? theme.textSecondary : theme.disabled
        }
        // The brand line while it's open (Fluent's focus underline).
        Rectangle {
            visible: options.opened
            anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
            color: theme.brand
        }
        HoverHandler { enabled: root.canChange && root.loaded; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: root.canChange && root.loaded
            onTapped: options.opened ? options.close() : options.open()
        }
        Accessible.role: Accessible.ComboBox
        Accessible.name: "Channel moderation"
        Accessible.description: !root.loaded ? "" : root.moderated ? "On" : "Off"
    }
    Popup {
        id: options
        parent: dropdown
        y: dropdown.height + 2; width: 355; padding: 4
        height: 74
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            spacing: 2
            Repeater {
                model: [["On", true], ["Off", false]]
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool chosen: root.moderated === modelData[1]
                    width: 347; height: 32; radius: 4
                    color: optHover.hovered ? theme.menuHover : "transparent"
                    Text {
                        x: 28; anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData[0]
                        font.family: theme.font; font.pixelSize: 14; font.weight: opt.chosen ? Font.Bold : Font.Normal
                        color: theme.text
                    }
                    HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            options.close()
                            if (!opt.chosen) root.change({ post: opt.modelData[1] ? 1 : 0, replies: true, pins: true, bots: true, connectors: true, reset: true })
                        }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: opt.modelData[0]
                    Accessible.selected: opt.chosen
                }
            }
        }
    }

    // Off: who can start a post.
    Item {
        visible: root.loaded && !root.moderated
        width: parent.width; height: parent.height
        Caption { y: 72.4; text: "Who can start a new post?" }
        Column {
            x: 38; y: 98.4
            Radio { label: "Everyone can start a new post"; chosen: root.loaded && root.settings.post === 0; onPicked: root.change({ post: 0 }) }
            Radio { label: "Everyone except guests can start a new post"; chosen: root.loaded && root.settings.post === 2; onPicked: root.change({ post: 2 }) }
        }
    }

    // On: the moderators, who can post, and members' permissions.
    Item {
        visible: root.moderated
        width: parent.width; height: parent.height
        Caption { y: 72.4; text: "Who are the moderators?" }
        Text {
            id: who
            x: 38; y: 104.7
            width: Math.min(implicitWidth, 236); elide: Text.ElideRight
            text: root.summary
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.brandFill
            HoverHandler {
                id: whoHover
                onHoveredChanged: hovered ? hoverTimer.restart() : closeTimer.restart()
            }
            Accessible.role: Accessible.Button
            Accessible.name: root.summary
        }
        Timer { id: hoverTimer; interval: 250; onTriggered: if (whoHover.hovered) whoCard.open() }
        Timer { id: closeTimer; interval: 250; onTriggered: if (!whoHover.hovered && !cardHover.hovered) whoCard.close() }
        Rectangle {
            visible: root.canChange
            x: 298; y: 98.4; width: 96; height: 31.3; radius: 4
            color: manageHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Manage"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: moderatorsDialog.start() }
            Accessible.role: Accessible.Button
            Accessible.name: "Manage"
        }
        Caption { y: 144.7; text: "Who can start a new post?" }
        Text {
            x: 38; y: 170.7
            text: "Only moderators"
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            x: 38; y: 205.7
            text: root.privateLike ? "Channel member permissions" : "Team member permissions"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Column {
            x: 38; y: 235.7
            spacing: 10
            Check { label: "Allow members to reply to channel messages"; checked: root.moderated && root.settings.replies; onToggled: on => root.change({ replies: on }) }
            Check { label: "Allow members to pin channel messages"; checked: root.moderated && root.settings.pins; onToggled: on => root.change({ pins: on }) }
            Check { label: "Allow bots to submit channel messages"; checked: root.moderated && root.settings.bots; onToggled: on => root.change({ bots: on }) }
        }
    }

    // Who moderates, on hover (Teams' popover above the summary).
    Popup {
        id: whoCard
        parent: who
        x: 0; y: -height - 4
        padding: 0
        width: Math.max(121.6, cardCol.implicitWidth + 12)
        height: cardCol.implicitHeight + 32
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        HoverHandler {
            id: cardHover
            onHoveredChanged: if (!hovered) closeTimer.restart()
        }
        Column {
            id: cardCol
            y: 16
            spacing: 8
            Repeater {
                model: [[root.ownersLabel, root.owners], ["Moderators", root.moderators]].filter(g => g[1].length > 0)
                Column {
                    id: group
                    required property var modelData
                    spacing: 4
                    Text {
                        x: 12; height: 20; verticalAlignment: Text.AlignVCenter
                        text: group.modelData[0]
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.text
                    }
                    Repeater {
                        model: group.modelData[1]
                        Rectangle {
                            id: person
                            required property var modelData
                            width: Math.max(cardCol.width, personName.x + personName.implicitWidth + 12); height: 40; radius: 4
                            color: personHover.hovered ? theme.menuHover : "transparent"
                            Avatar {
                                x: 10.7; y: 4; size: 32
                                name: person.modelData.name || "?"
                                photoId: person.modelData.mri
                                presence: person.modelData.mri.toLowerCase() === root.myMri.toLowerCase() ? root.myPresence : ""
                            }
                            Text {
                                id: personName
                                x: 47.7; anchors.verticalCenter: parent.verticalCenter
                                text: person.modelData.name
                                font.family: theme.font; font.pixelSize: 12
                                color: theme.text
                            }
                            HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    whoCard.close()
                                    backend.openChatWith(person.modelData.mri.replace(/^8:orgid:/, ""), person.modelData.name)
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: person.modelData.name
                        }
                    }
                }
            }
        }
    }

    ModeratorsDialog {
        id: moderatorsDialog
        teamId: root.teamId
        channelId: root.channelId
        ownersLabel: root.ownersLabel
        ownersCount: root.owners.length
        owners: root.owners
        moderators: root.moderators
    }

    component Radio: Item {
        id: rb
        property string label
        property bool chosen: false
        signal picked()
        width: 32 + rbText.implicitWidth + 12; height: 32
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 8
            color: "transparent"
            border.color: !root.canChange ? theme.disabled : rb.chosen ? theme.brandFill : theme.textSecondary
            border.width: 0.67
            Rectangle {
                visible: rb.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5
                color: root.canChange ? theme.brandFill : theme.disabled
            }
        }
        Text {
            id: rbText
            x: 32; y: 6
            text: rb.label
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.canChange ? theme.text : theme.disabled
        }
        HoverHandler { enabled: root.canChange; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.canChange && !root.saving; onTapped: if (!rb.chosen) rb.picked() }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: chosen
        Accessible.name: label
    }
    component Check: Item {
        id: cb
        property string label
        property bool checked: false
        signal toggled(bool on)
        width: 32 + cbText.implicitWidth + 12; height: 32
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 2
            color: cb.checked ? (root.canChange ? theme.brandFill : theme.disabled) : "transparent"
            border.color: cb.checked ? color : root.canChange ? theme.textSecondary : theme.disabled
            border.width: 0.67
            FluentIcon { visible: cb.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand }
        }
        Text {
            id: cbText
            x: 32; y: 6
            text: cb.label
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.canChange ? theme.text : theme.disabled
        }
        HoverHandler { enabled: root.canChange; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.canChange && !root.saving; onTapped: cb.toggled(!cb.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: checked
        Accessible.name: label
    }

    // Test hooks.
    function dialogForTest() { return moderatorsDialog }
    function openOptionsForTest() { options.open() }
    function openCardForTest() { whoCard.open() }
    function closeAllForTest() { options.close(); whoCard.close(); moderatorsDialog.close() }
}
