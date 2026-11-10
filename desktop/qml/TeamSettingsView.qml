import QtQuick
import QtQuick.Controls.Basic

// Manage team ▸ Settings (Teams' tab, measured on winpc 2026-11-09;
// docs/spec/chat-list-and-header.md §5.6.6). Sections 72 in, 20.3 down,
// 774 wide; each header 64 tall (a 20 px chevron at 10, the title 14/20
// semibold and what it holds 14/20 under it at 38) with a line after the
// open body. Bodies start 64 under the header's top, 39 in:
// - Team details (open): the name (21/30 bold), the description (12/16),
//   the privacy chip (32 x 24, #E6E6E6, the lock), Edit (brand) opening Edit
//   team details, "Team picture" (14/20 light), the picture (64, radius 4)
//   and Change picture.
// - Member permissions, Guest permissions, @mentions: checkboxes (16 px in
//   32 boxes, labels 14/20 at 71, rows 42 apart; private channels indented
//   25 under create and update channels).
// - Team code: Generate, or the code with Full screen, Reset and Remove;
//   "Note: guests won't be able to join with a team code".
// - Fun stuff: Giphy (Enable Giphy for this team; the G / PG filter),
//   Stickers and memes (Enable stickers and memes, Allow memes to be
//   uploaded).
// - Tags: Apps, and a Shifts switch for automatic tags.
// Everything but the details and tags is the team thread's
// spaceAdminSettings, written back whole on each change as Teams does.
Item {
    id: view
    property string teamId: ""
    property string teamThread: ""
    property var team: ({})
    property var settings: null
    property var tags: null
    property string code: ""
    property bool codeLoaded: false
    property var open: ({ details: true })
    property bool saving: false
    readonly property bool owner: !!team.owner
    readonly property var user: settings && settings.userSettings ? settings.userSettings : ({})
    readonly property var guest: settings && settings.guestSettings ? settings.guestSettings : ({})

    function load() { if (teamThread) backend.channelAction("team-settings-load", teamId, teamThread, "") }
    function change(section, fields) {
        if (!owner || saving) return
        saving = true
        // Show it at once.
        const s = JSON.parse(JSON.stringify(settings || {}))
        s[section] = Object.assign({}, s[section] || {}, fields)
        settings = s
        const c = {}; c[section] = fields
        backend.channelAction("team-settings", teamId, teamThread, JSON.stringify(c))
    }
    function toggle(key) { const o = Object.assign({}, open); o[key] = !o[key]; open = o }
    onTeamThreadChanged: { settings = null; tags = null; code = ""; codeLoaded = false; open = ({ details: true }); load() }
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== view.teamThread) return
            if (r.op === "team-settings-load" && r.ok) {
                view.settings = r.data.settings; view.tags = r.data.tags
                view.code = r.data.code || ""; view.codeLoaded = true
            } else if (r.op === "team-settings") {
                view.saving = false
                if (r.ok) view.settings = r.data.settings
                else { backend.toast("Something went wrong on our end. Please try again.", "error"); view.load() }
            } else if (r.op === "team-tag-settings") {
                if (r.ok) view.tags = r.data.tags
                else backend.toast("Something went wrong on our end. Please try again.", "error")
            } else if (r.op === "team-code") {
                if (r.ok) view.code = r.data.code || ""
                else backend.toast("Something went wrong on our end. Please try again.", "error")
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            x: 72; y: 20.3; width: Math.min(774, view.width - 144)

            Section {
                key: "details"; title: "Team details"; hint: "Edit team name, description, privacy, and picture"
                Item {
                    width: parent.width; height: 414.7 - 64
                    Text {
                        x: 39; y: 0; width: 276.8; elide: Text.ElideRight
                        text: view.team.name || ""
                        font.family: theme.font; font.pixelSize: 21; font.weight: Font.Bold
                        lineHeight: 30; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Text {
                        x: 39; y: 35; width: 276.8; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: view.team.description || ""
                        font.family: theme.font; font.pixelSize: 12
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Rectangle {
                        x: 39; y: 70; width: 32; height: 24
                        color: theme.pick("#E6E6E6", "#3D3D3D")
                        FluentIcon { anchors.centerIn: parent; name: view.team["public"] ? "globe-20" : "lock-closed-20"; size: 20; color: theme.textSecondary }
                        Accessible.role: Accessible.StaticText
                        Accessible.name: view.team["public"] ? "Public Team" : "Private Team"
                    }
                    Btn { visible: view.owner; x: 39; y: 124; text: "Edit"; primary: true; onClicked: editDialog.start(view.team) }
                    Text {
                        x: 39; y: 190.3
                        text: "Team picture"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.Light
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Avatar {
                        x: 39; y: 220.3; size: 64; square: true; squareRadius: 4
                        name: view.team.name || ""
                        initialsText: (view.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: view.teamId ? "team:" + view.teamId : ""
                    }
                    Rectangle {
                        visible: view.owner
                        x: 31; y: 294.3; width: picRow.implicitWidth + 24; height: 31.3; radius: 4
                        color: picHover.hovered ? theme.menuHover : "transparent"
                        Row {
                            id: picRow
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            FluentIcon { name: "arrow-upload-20"; size: 20; color: theme.textStrong }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Change picture"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
                        }
                        HoverHandler { id: picHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: pictureDialog.start() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Change picture"
                    }
                }
            }

            Section {
                key: "members"; title: "Member permissions"; hint: "Enable channel creation, adding apps, and more"
                Checks {
                    model: [
                        ["Allow members to create and update channels", view.user.createTopic !== false, s => view.change("userSettings", { createTopic: s, updateTopic: s }), 0],
                        ["Allow members to create private channels", view.user.createPrivateSpace !== false, s => view.change("userSettings", { createPrivateSpace: s }), 1],
                        ["Allow members to delete and restore channels", view.user.deleteTopic !== false, s => view.change("userSettings", { deleteTopic: s }), 0],
                        ["Allow members to add and remove apps", view.user.installApp !== false, s => view.change("userSettings", { installApp: s, uninstallApp: s }), 0],
                        ["Allow members to upload custom apps", view.user.uploadCustomApp !== false, s => view.change("userSettings", { uploadCustomApp: s }), 0],
                        ["Allow members to create, update, and remove tabs", view.user.createTab !== false, s => view.change("userSettings", { createTab: s, deleteTab: s }), 0],
                        ["Allow members to create, update, and remove connectors", view.user.createIntegration !== false, s => view.change("userSettings", { createIntegration: s, updateIntegration: s, deleteIntegration: s }), 0],
                        ["Allow members to create, edit, and delete tags", !!view.tags && !view.tags.only_owners, s => backend.channelAction("team-tag-settings", view.teamId, view.teamThread, JSON.stringify({ onlyOwners: !s })), 0],
                        ["Give members the option to delete their messages", view.user.deleteEnabled !== false, s => view.change("userSettings", { deleteEnabled: s }), 0],
                        ["Give members the option to edit their messages", view.user.editEnabled !== false, s => view.change("userSettings", { editEnabled: s }), 0]
                    ]
                }
            }
            Section {
                key: "guests"; title: "Guest permissions"; hint: "Enable channel creation"
                Checks {
                    model: [
                        ["Allow guests to create and update channels", view.guest.createTopic === true, s => view.change("guestSettings", { createTopic: s, updateTopic: s }), 0],
                        ["Allow guests to delete channels", view.guest.deleteTopic === true, s => view.change("guestSettings", { deleteTopic: s }), 0]
                    ]
                }
            }
            Section {
                key: "mentions"; title: "@mentions"; hint: "Choose who can use team, channel, and group @mentions"
                Checks {
                    rowHeight: 62
                    model: [
                        ["Show members the option to @team or @[team name] (this will send a notification to everyone on the team)", view.user.teamMention !== false, s => view.change("userSettings", { teamMention: s }), 0],
                        ["Give members the option to @channel or @[channel name]. This will notify everyone who's shown the mentioned channel in their channel lists.", view.user.channelMention !== false, s => view.change("userSettings", { channelMention: s }), 0]
                    ]
                }
            }
            Section {
                key: "code"; title: "Team code"
                hint: view.team["public"] ? "Share this code so people can join the team directly - you won't get join requests for public teams" : "Share this code so people can join the team directly - you won't get join requests"
                Item {
                    width: parent.width; height: view.code ? 228 - 64 : 160.3 - 64
                    Btn { visible: view.codeLoaded && !view.code && view.owner; x: 39; y: 10; text: "Generate"; primary: true; onClicked: backend.channelAction("team-code", view.teamId, view.teamThread, "generate") }
                    // The code (Teams: 28/36, then Full screen and Reset, Remove and Copy).
                    Text {
                        visible: !!view.code
                        x: 39; y: 0
                        text: view.code
                        font.family: theme.font; font.pixelSize: 28
                        lineHeight: 36; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Grid {
                        visible: !!view.code
                        x: 31; y: 34; columns: 2; columnSpacing: 8; rowSpacing: 18.7
                        Plain { icon: "arrow-maximize-20"; text: "Full screen"; tip: "Show team code full screen"; onClicked: codeFull.open() }
                        Plain { visible: view.owner; icon: "arrow-clockwise-20"; text: "Reset"; tip: "Resetting team code will generate a new join code"; onClicked: backend.channelAction("team-code", view.teamId, view.teamThread, "generate") }
                        Plain { visible: view.owner; icon: "delete-20"; text: "Remove"; tip: "Removing team code will delete the current code and prevent future user from joining this team with a code"; onClicked: backend.channelAction("team-code", view.teamId, view.teamThread, "remove") }
                        Plain { icon: "copy-20"; text: "Copy"; onClicked: backend.copyText(view.code) }
                    }
                    Text {
                        x: 39; y: view.code ? 140 : 61.3
                        text: "Note: guests won't be able to join with a team code"
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                }
            }
            Section {
                key: "fun"; title: "Fun stuff"; hint: "Allow memes, GIFs, or stickers"
                Item {
                    width: parent.width; height: 337.3 - 64
                    Text { x: 39; y: 5; text: "Giphy"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Check { x: 39; y: 30; label: "Enable Giphy for this team"; checked: view.user.giphyEnabled !== false; onToggled: s => view.change("userSettings", { giphyEnabled: s }) }
                    Text { x: 69; y: 77; text: "Filter out inappropriate content using one of the settings below:"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Rectangle {
                        id: rating
                        x: 69.7; y: 105.7; width: 296.1; height: 30; radius: 4
                        readonly property bool on: view.user.giphyEnabled !== false && view.owner
                        color: ratingHover.hovered && on ? theme.menuHover : "transparent"
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            text: view.user.giphyRating === 0 ? "G (based on the GIPHY Content Rating)" : "PG (based on the GIPHY Content Rating)"
                            font.family: theme.font; font.pixelSize: 14
                            color: rating.on ? theme.text : theme.disabled
                        }
                        FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: rating.on ? theme.textSecondary : theme.disabled }
                        HoverHandler { id: ratingHover; enabled: rating.on; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: rating.on; onTapped: ratingMenu.open() }
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: "Filter out inappropriate content using one of the settings below:"
                        Popup {
                            id: ratingMenu
                            y: rating.height + 2; width: rating.width; height: 74; padding: 4
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            Column {
                                spacing: 2
                                Repeater {
                                    model: [[0, "G (based on the GIPHY Content Rating)"], [1, "PG (based on the GIPHY Content Rating)"]]
                                    Rectangle {
                                        id: ropt
                                        required property var modelData
                                        width: rating.width - 8; height: 32; radius: 4
                                        color: roptHover.hovered ? theme.menuHover : "transparent"
                                        Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: ropt.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: (view.user.giphyRating === 0) === (ropt.modelData[0] === 0) ? Font.Bold : Font.Normal; color: theme.text }
                                        HoverHandler { id: roptHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { ratingMenu.close(); view.change("userSettings", { giphyRating: ropt.modelData[0] }) } }
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: ropt.modelData[1]
                                    }
                                }
                            }
                        }
                    }
                    Text { x: 39; y: 149.3; text: "Stickers and memes"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Check { x: 39; y: 174.3; label: "Enable stickers and memes"; checked: view.user.stickersEnabled !== false; onToggled: s => view.change("userSettings", { stickersEnabled: s }) }
                    Check { x: 39; y: 216.3; label: "Allow memes to be uploaded"; checked: view.user.customMemesEnabled !== false; onToggled: s => view.change("userSettings", { customMemesEnabled: s }) }
                }
            }
            Section {
                key: "tags"; title: "Tags"; hint: "Automatically apply tags from other apps"
                Item {
                    width: parent.width; height: 131 - 64
                    Text { x: 39; y: 0; text: "Apps"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                    Item {
                        id: shifts
                        x: 39; y: 26; width: 88.8; height: 26
                        readonly property bool on: !!view.tags && (view.tags.disallowed_sources || []).indexOf("Shifts") < 0
                        Rectangle {
                            y: 3; width: 38; height: 20; radius: 10
                            color: shifts.on ? theme.brandFill : "transparent"
                            border.color: shifts.on ? theme.brandFill : theme.textSecondary; border.width: 1
                            Rectangle { x: shifts.on ? 22 : 4; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: shifts.on ? "white" : theme.textSecondary }
                        }
                        Text { x: 50; y: 3; text: "Shifts"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        HoverHandler { enabled: view.owner; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: view.owner && !!view.tags; onTapped: backend.channelAction("team-tag-settings", view.teamId, view.teamThread, JSON.stringify({ shifts: !shifts.on })) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.checked: on
                        Accessible.name: "Automatically apply tags from other apps. Shifts"
                    }
                }
            }
        }
    }

    EditTeamDialog { id: editDialog; teamId: view.teamId; teamThread: view.teamThread }
    TeamPictureDialog { id: pictureDialog; teamId: view.teamId; teamThread: view.teamThread; teamName: view.team.name || "" }
    // The code, full screen.
    Popup {
        id: codeFull
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Overlay.overlay ? Overlay.overlay.width : 800; height: Overlay.overlay ? Overlay.overlay.height : 600
        modal: true
        background: Rectangle { color: theme.surface }
        Text { anchors.centerIn: parent; text: view.code; font.family: theme.font; font.pixelSize: 96; font.weight: Font.Bold; color: theme.text }
        FluentIcon {
            x: parent.width - 48; y: 16; name: "dismiss-20"; size: 20; color: theme.textStrong
            TapHandler { onTapped: codeFull.close() }
        }
    }

    // A section.
    component Section: Column {
        id: sec
        property string key
        property string title
        property string hint
        default property alias body: bodyCol.data
        readonly property bool expanded: !!view.open[key]
        width: parent ? parent.width : 0
        Rectangle {
            width: parent.width; height: 64; radius: 4
            color: secHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: sec.expanded ? "chevron-down-20" : "chevron-right-20"; size: 20; color: theme.text }
            Text { x: 38; y: 12; width: parent.width - 50; elide: Text.ElideRight; text: sec.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { x: 38; y: 32; width: parent.width - 50; elide: Text.ElideRight; text: sec.hint; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            HoverHandler { id: secHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: view.toggle(sec.key) }
            Accessible.role: Accessible.Button
            Accessible.name: sec.title + ", " + sec.hint
        }
        Column { id: bodyCol; visible: sec.expanded; width: parent.width }
        Rectangle { width: parent.width; height: 0.67; color: theme.divider }
    }
    // Checkbox rows: [label, checked, set(bool), indent].
    component Checks: Column {
        id: checks
        property var model: []
        property real rowHeight: 42
        width: parent ? parent.width : 0
        bottomPadding: 13
        Repeater {
            model: checks.model
            Item {
                required property var modelData
                width: checks.width; height: checks.rowHeight
                Check {
                    x: 39 + 25 * parent.modelData[3]; y: 0
                    width: parent.width - x - 40
                    label: parent.modelData[0]
                    checked: !!parent.modelData[1]
                    onToggled: s => parent.modelData[2](s)
                }
            }
        }
    }
    component Check: Item {
        id: cb
        property string label
        property bool checked: false
        signal toggled(bool on)
        width: 32 + Math.min(488, cbText.implicitWidth) + 12; height: Math.max(42, cbText.height + 12)
        readonly property bool on: view.owner && !!view.settings
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 2
            color: cb.checked ? (cb.on ? theme.brandFill : theme.disabled) : "transparent"
            border.color: cb.checked ? color : cb.on ? theme.textSecondary : theme.disabled
            border.width: 0.67
            FluentIcon { visible: cb.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand }
        }
        Text {
            id: cbText
            x: 32; y: 6
            width: Math.min(488, implicitWidth); wrapMode: Text.Wrap
            text: cb.label
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: cb.on ? theme.text : theme.textSecondary
        }
        HoverHandler { enabled: cb.on; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: cb.on; onTapped: cb.toggled(!cb.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: checked
        Accessible.name: label
    }
    component Plain: Rectangle {
        id: pb
        property string icon
        property string text
        property string tip: ""
        signal clicked()
        width: pbRow.implicitWidth + 24; height: 31.3; radius: 4
        color: pbHover.hovered ? theme.menuHover : "transparent"
        Row {
            id: pbRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { name: pb.icon; size: 20; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
        }
        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        ToolTip.visible: pb.tip.length > 0 && pbHover.hovered
        ToolTip.text: pb.tip
        ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, btnText.implicitWidth + 24); height: 31.3; radius: 4
        color: primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
        Text { id: btnText; anchors.centerIn: parent; text: btn.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: btn.primary ? theme.textOnBrand : theme.text }
        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function editDialogForTest() { return editDialog }
    function pictureDialogForTest() { return pictureDialog }
    function openAllForTest() { open = ({ details: true, members: true, guests: true, mentions: true, code: true, fun: true, tags: true }) }
}
