import QtQuick
import QtQuick.Controls.Basic

// Create a channel (a team's menu ▸ Add channel, Manage team ▸ Add channel;
// Teams' dialog, measured on winpc 2026-11-09): 600 wide, padding 24,
// radius 8, the window's height.
// - "Create a channel" (20/28 semibold).
// - "Channel name" with its red * (12/16), the field (546.7 x 32, #F5F5F5,
//   radius 4, "Letters, numbers, and spaces are allowed", a brand
//   checkmark at its end once the name is good; Teams' name rules).
// - "Description" and its field (55.3 tall, "Help others find the right
//   channel by providing a description").
// - "Choose a channel type" * with its info button (Learn more about channel
//   types), then the type dropdown ("Select"): Standard, Shared, Private,
//   each a 48 tall row with a check (16) at 6, a 32 px tile (radius 5:
//   #BDD99B people-team, #A6E9ED channel-share, #FFDDB3 lock) at 28, the
//   name (14/20) and what it means (12/16) at 67. Chosen, the dropdown reads
//   "{type} — {what it means}" and Standard adds "Recommend that people show
//   this channel in their channel lists".
// - Layout (12/16 bold), "Channel owners can change this at any time" and
//   Teams' Threads / Posts cards (Threads chosen at first).
// - Cancel and Create (96 x 31.3) 32.7 above the bottom; Create once the
//   name and type are given.
// Creating posts it as Teams does (api::channels::create_channel) and opens
// the new channel; a private one first gets Teams' member step (Add members
// to the {channel} channel: Skip / Add).
// From the chat list's New items ▸ New channel (`startPick`, Teams web
// 2026-11-27) the form starts with "Add the channel to a team" * (12/16,
// an info glyph "Every channel must be hosted by a team") over a 49 px
// button (a 1 px #D1D1D1 edge, radius 4): "Select a team" (14/600), or
// the team's 32 px picture, name (a 14 px lock for a private one) and
// "N members" (12/16 #616161), with a chevron at its end; 16 under it the
// form goes on. The button opens "Pick a team to add new channel to": Find
// teams (32 tall, #F5F5F5, a search glyph 10 from its end) and the teams
// (rows 50 tall, 2 apart: a 16 px check when chosen 7 in, the picture at
// 27, the name at 73; the chosen row #F5F5F5), then Back and Done (96 x 32).
Popup {
    id: dlg
    property string teamId: ""
    property string teamName: ""
    property string name: ""
    property string description: ""
    property string type: ""
    property bool recommend: false
    property string layout: "Conversational"
    property bool creating: false
    property string failure: ""
    signal created(string channelId, string name)

    readonly property var types: [
        { key: "Standard", label: qsTr("Standard"), hint: qsTr("Everyone on the team has access."), icon: "people-team-20", tile: "#BDD99B" },
        { key: "Shared", label: qsTr("Shared"), hint: qsTr("People or teams in your org or outside your org can have access."), icon: "channel-share-20", tile: "#A6E9ED" },
        { key: "Private", label: qsTr("Private"), hint: qsTr("Specific people on the team have access."), icon: "lock-closed-20", tile: "#FFDDB3" }
    ]
    readonly property var chosenType: types.find(t => t.key === type) || null
    readonly property string nameError: {
        const n = name.trim()
        if (!n) return ""
        if (n.startsWith("_") || n.startsWith(".")) return qsTr("Channel name cannot start with an underscore (_) or a period (.)")
        if (/[~#%&*{}+\/\\:<>?|'"]/.test(n) || n.indexOf("..") >= 0) return qsTr("We don't support these characters: ~#%&*{}+/\\:<>?|'\"..")
        if (n.endsWith(".")) return qsTr("Channel name cannot end with a period (.)")
        if (/https?:\/\/|www\./i.test(n)) return qsTr("Links are not allowed in the channel name")
        if (n.toLowerCase() === "general") return qsTr("General can only be used for the first-created channel in a team. Try another name.")
        return ""
    }
    readonly property bool nameGood: name.trim().length > 0 && !nameError
    readonly property bool canCreate: nameGood && !!type && !creating && !!teamId

    function start(tid, tname) {
        teamId = tid; teamName = tname
        pickTeam = false; picking = false
        name = ""; description = ""; type = ""; recommend = false; layout = "Conversational"
        creating = false; failure = ""
        open()
        nameField.forceActiveFocus()
    }
    /// New items ▸ New channel: the team is picked in the dialog.
    property bool pickTeam: false
    property bool picking: false
    /// The team chosen on the picker page (its thread id), before Done.
    property string pickChoice: ""
    property string teamQuery: ""
    readonly property var allTeams: (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).filter(t => !t.archived)
    readonly property var pickedTeam: allTeams.find(t => t.id === teamId) || null
    readonly property var pickList: allTeams.filter(t => !teamQuery || (t.name || "").toLowerCase().indexOf(teamQuery.toLowerCase()) >= 0)
    function startPick() {
        start("", "")
        pickTeam = true
    }
    function openPicker() { pickChoice = teamId; teamQuery = ""; findTeams.text = ""; picking = true; findTeams.forceActiveFocus() }
    function pickDone() {
        const t = allTeams.find(t => t.id === pickChoice)
        if (t) { teamId = t.id; teamName = t.name || "" }
        picking = false
        nameField.forceActiveFocus()
    }
    function create() {
        creating = true; failure = ""
        const general = ((JSON.parse(backend.teamsJson || "[]").find(t => t.id === dlg.teamId) || {}).channels || []).find(c => c.general)
        backend.channelAction("create-channel", teamId, general ? general.id : "", JSON.stringify({ name: name, description: description, type: type, layout: layout, recommend: type === "Standard" && recommend }))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "create-channel" || !dlg.creating) return
            dlg.creating = false
            if (r.ok && r.data.type === "Private") {
                // Teams' member step for a private channel, then the channel.
                dlg.close()
                const team = (JSON.parse(backend.teamsJson || "[]").find(t => t.id === dlg.teamId) || {})
                memberStep.pendingId = r.data.id; memberStep.pendingName = r.data.name
                memberStep.startChannel(dlg.teamId, team.thread_id || "", dlg.teamName, r.data.id, r.data.name)
            } else if (r.ok) { dlg.close(); dlg.created(r.data.id, r.data.name) }
            else dlg.failure = /409|conflict|already/i.test(r.error || "") ? qsTr("Channel name is already taken.") : qsTr("Something went wrong on our end. Please try again.")
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; padding: 24
    height: Overlay.overlay ? Overlay.overlay.height : 680
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    // A team as the picker shows it: its 32 px picture (radius 4), its name
    // (a 14 px lock 10 after a private one's) and "N members" under it.
    component TeamLine: Item {
        id: tl
        property var team: null
        property Item fill: null
        property bool dim: false
        width: 480; height: 36
        Avatar {
            x: 0; y: 2; size: 32; square: true
            name: tl.team ? tl.team.name || "" : ""
            initialsText: tl.team ? (tl.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
            photoId: tl.team ? "team:" + tl.team.id : ""
        }
        Row {
            x: 46; y: 0; spacing: 10
            Text {
                text: tl.team ? tl.team.name || "" : ""
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.onFill(tl.fill, tl.dim ? theme.textStrong : theme.text)
            }
            FluentIcon { visible: !!tl.team && !tl.team["public"]; anchors.verticalCenter: parent.verticalCenter; name: "lock-closed-16"; size: 14; color: theme.onFill(tl.fill, tl.dim ? theme.textStrong : theme.text) }
        }
        Text {
            x: 46; y: 20
            text: tl.team ? qsTr("%n members", "", tl.team.people || 0) : ""
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.onFill(tl.fill, tl.dim ? theme.textSecondary : theme.text)
        }
    }
    component Label: Row {
        property string text
        property bool required: false
        Text { text: parent.text; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { visible: parent.required; leftPadding: 4; text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#D13438", "#DC626D", "#FFFFFF") }
    }
    component LayoutCard: Rectangle {
        id: lc
        property string key
        property string picture
        property string label
        property string hint
        property bool isNew: false
        readonly property bool chosen: dlg.layout === key
        width: 157.3; height: 167.3; radius: 6
        color: "transparent"
        border.color: lcHover.hovered ? theme.textSecondary : theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        Image {
            x: 8.6; y: 6.6; width: 140; height: 80
            source: "../assets/illustrations/channel-layout-" + lc.picture + (theme.dark ? "-dark" : "") + ".svg"
            sourceSize: Qt.size(280, 160)
        }
        Rectangle {
            id: hcFill1
            visible: lc.isNew
            x: 17; y: 2; height: 20; radius: 10
            width: newText.implicitWidth + 12
            color: theme.brandFill
            Text { id: newText; anchors.centerIn: parent; text: qsTr("New"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, "white") }
        }
        Text { x: 8.6; y: 92.6; text: lc.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: lc.chosen ? theme.text : theme.textSecondary }
        Rectangle {
            x: 133.3; y: 92; width: 16; height: 16; radius: 8
            color: "transparent"
            border.color: lc.chosen ? theme.brand : theme.textSecondary; border.width: 0.67
            Rectangle { visible: lc.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
        }
        Text {
            x: 8.6; y: 118.6; width: 140; wrapMode: Text.Wrap
            text: lc.hint
            font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
            color: lc.chosen ? theme.text : theme.textSecondary
        }
        HoverHandler { id: lcHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.layout = lc.key }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: chosen
        Accessible.name: label
    }

    contentItem: Item {
        Text {
            x: 0.7; y: 0.7
            text: dlg.picking ? qsTr("Pick a team to add new channel to") : qsTr("Create a channel")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        Column {
            visible: !dlg.picking
            x: 2.7; y: 42.7; width: 546.7
            spacing: 0
            // New items ▸ New channel: the team first.
            Row {
                visible: dlg.pickTeam
                height: visible ? 16 : 0
                Label { text: qsTr("Add the channel to a team"); required: true }
                FluentIcon {
                    id: hostInfo
                    name: "info-16-regular"; size: 16; color: theme.text
                    HoverHandler { id: hostInfoHover }
                    ToolTip.visible: hostInfoHover.hovered; ToolTip.delay: 300; ToolTip.text: qsTr("Every channel must be hosted by a team")
                    Accessible.role: Accessible.Graphic
                    Accessible.name: qsTr("Every channel must be hosted by a team")
                }
            }
            Item { width: 1; height: dlg.pickTeam ? 4 : 0 }
            Rectangle {
                id: teamButton
                visible: dlg.pickTeam
                width: parent.width; height: visible ? 49 : 0; radius: 4
                color: teamHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 1
                Text {
                    visible: !dlg.pickedTeam
                    x: 13; anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Select a team")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(teamButton, theme.text)
                }
                TeamLine { visible: !!dlg.pickedTeam; team: dlg.pickedTeam; x: 13; y: 6; fill: teamButton }
                FluentIcon { x: parent.width - 18 - 20; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-20"; size: 20; color: theme.onFill(teamButton, theme.text) }
                HoverHandler { id: teamHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.openPicker() }
                Accessible.role: Accessible.Button
                Accessible.name: dlg.pickedTeam ? qsTr("Selected team: %1").arg(dlg.pickedTeam.name) : qsTr("Select a team")
            }
            Item { width: 1; height: dlg.pickTeam ? 16 : 0 }
            Label { text: qsTr("Channel name"); required: true }
            Item { width: 1; height: 3 }
            Rectangle {
                width: parent.width; height: 32; radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                TextInput {
                    id: nameField
                    anchors.fill: parent; leftPadding: 12; rightPadding: 34
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 50
                    text: dlg.name
                    onTextEdited: dlg.name = text
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    clip: true
                    Keys.onReturnPressed: if (dlg.canCreate) dlg.create()
                    Text { visible: !nameField.text; x: 12; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Letters, numbers, and spaces are allowed"); font: nameField.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Channel name")
                }
                FluentIcon { visible: dlg.nameGood; x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-20"; size: 20; color: theme.brand }
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: nameField.activeFocus ? 2 : 0; color: dlg.nameError ? theme.danger : theme.brand }
            }
            Text {
                visible: !!dlg.nameError
                width: parent.width; wrapMode: Text.Wrap
                text: dlg.nameError
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.danger
            }
            Item { width: 1; height: 18 }
            Label { text: qsTr("Description") }
            Item { width: 1; height: 3 }
            Rectangle {
                width: parent.width; height: Math.max(55.3, descField.contentHeight + 20); radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                TextEdit {
                    id: descField
                    x: 12; y: 10; width: parent.width - 24
                    text: dlg.description
                    onTextChanged: if (text !== dlg.description) dlg.description = text
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    Text { visible: !descField.text; text: qsTr("Help others find the right channel by providing a description"); font: descField.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Description")
                }
            }
            Item { width: 1; height: 18 }
            Row {
                height: 21.3
                Label { text: qsTr("Choose a channel type"); required: true; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    id: hcFill2
                    width: 32; height: 21.3; radius: 4
                    color: infoHover.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: theme.onFill(hcFill2, theme.textStrong) }
                    HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.openExternal("https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview") }
                    ToolTip.visible: infoHover.hovered; ToolTip.delay: 300; ToolTip.text: qsTr("Learn more about channel types")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Learn more about channel types")
                }
            }
            Item { width: 1; height: 3 }
            // The type dropdown.
            Rectangle {
                id: typeBox
                width: parent.width; height: 31.3; radius: 4
                color: theme.surface
                border.color: theme.stroke; border.width: 0.67
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: typeList.opened ? 2 : 0.67; color: typeList.opened ? theme.brand : theme.textSecondary }
                Text {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 52; elide: Text.ElideRight
                    text: dlg.chosenType ? dlg.chosenType.label + " — " + dlg.chosenType.hint.replace(/\.$/, "") : qsTr("Select")
                    font.family: theme.font; font.pixelSize: 14
                    color: dlg.chosenType ? theme.text : theme.pick("#707070", "#ADADAD", "#FFFFFF")
                }
                FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: typeList.opened ? typeList.close() : typeList.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Choose a channel type")
                Popup {
                    id: typeList
                    y: parent.height + 1.4
                    width: parent.width; height: 156; padding: 4
                    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                    contentItem: Column {
                        spacing: 2
                        Repeater {
                            model: dlg.types
                            Rectangle {
                                id: opt
                                required property var modelData
                                width: typeList.width - 8; height: 48; radius: 4
                                color: optHover.hovered ? theme.menuHover : "transparent"
                                FluentIcon { visible: dlg.type === opt.modelData.key; x: 6; y: 16; size: 16; name: "checkmark-16"; color: theme.onFill(opt, theme.text) }
                                Rectangle {
                                    id: hcFill3
                                    x: 28; y: 8; width: 32; height: 32; radius: 5
                                    color: opt.modelData.tile
                                    FluentIcon { anchors.centerIn: parent; size: 20; name: opt.modelData.icon; color: theme.onFill(hcFill3, theme.hc("#242424", "#FFFFFF")) }
                                }
                                Text { x: 67; y: 6; text: opt.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(opt, theme.text) }
                                Text { x: 67; y: 26; width: parent.width - 75; elide: Text.ElideRight; text: opt.modelData.hint; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(opt, theme.text) }
                                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { dlg.type = opt.modelData.key; typeList.close() } }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: opt.modelData.label + " " + opt.modelData.hint
                            }
                        }
                    }
                }
            }
            // Standard: recommend it for everyone's list.
            Item {
                visible: dlg.type === "Standard"
                width: parent.width; height: visible ? 42 : 0
                Item {
                    x: 0; y: 8.1; width: recText.x + recText.implicitWidth + 8; height: 36
                    Rectangle {
                        id: hcFill4
                        x: 8; y: 10; width: 16; height: 16; radius: 2
                        color: dlg.recommend ? theme.brand : "transparent"
                        border.color: dlg.recommend ? theme.brand : theme.textSecondary; border.width: 0.67
                        FluentIcon { visible: dlg.recommend; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: theme.onFill(hcFill4, "white") }
                    }
                    Text { id: recText; x: 36; y: 8; text: qsTr("Recommend that people show this channel in their channel lists"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: dlg.recommend ? theme.text : theme.textSecondary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.recommend = !dlg.recommend }
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: dlg.recommend
                    Accessible.name: recText.text
                }
            }
            Item { width: 1; height: 16 }
            Text { text: qsTr("Layout"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { text: qsTr("Channel owners can change this at any time"); font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 10 }
            Row {
                spacing: 12
                LayoutCard { key: "Conversational"; picture: "conversational"; label: qsTr("Threads"); hint: qsTr("Looks like chat with replies on the side in threads. Good for back-and-forth discussions."); isNew: true }
                LayoutCard { key: "PostReply"; picture: "post-reply"; label: qsTr("Posts"); hint: qsTr("Posts reorder by most recent reply. Good for forums and announcements.") }
            }
            Text {
                visible: !!dlg.failure
                topPadding: 12
                text: dlg.failure
                font.family: theme.font; font.pixelSize: 12; color: theme.danger
            }
        }
        // The picker page.
        Item {
            id: picker
            visible: dlg.picking
            y: 36; width: 550; height: parent.height - y - 31.3 - 8.7 - 8
            Rectangle {
                width: parent.width; height: 32; radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                TextInput {
                    id: findTeams
                    x: 13; width: parent.width - 13 - 40
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    clip: true
                    onTextChanged: dlg.teamQuery = text.trim()
                    Keys.onEscapePressed: dlg.picking = false
                    Text { visible: !findTeams.text; text: qsTr("Find teams"); font: findTeams.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Find teams")
                }
                FluentIcon { x: parent.width - 10 - 20; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: findTeams.activeFocus ? 2 : 0; color: theme.brand }
            }
            ListView {
                y: 48; width: parent.width; height: parent.height - y
                clip: true
                spacing: 2
                model: dlg.pickList
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: teamRow
                    required property var modelData
                    readonly property bool chosen: dlg.pickChoice === modelData.id
                    width: ListView.view.width; height: 50; radius: 4
                    color: chosen || rowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    FluentIcon { visible: teamRow.chosen; x: 7; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.onFill(teamRow, theme.text) }
                    TeamLine { team: teamRow.modelData; x: 27; y: 7; fill: teamRow; dim: !teamRow.chosen && !rowHover.hovered }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.pickChoice = teamRow.modelData.id; onDoubleTapped: { dlg.pickChoice = teamRow.modelData.id; dlg.pickDone() } }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: teamRow.chosen
                    Accessible.name: (teamRow.modelData.name || "") + (teamRow.modelData["public"] ? "" : " " + qsTr("Private"))
                }
            }
        }
        Row {
            visible: dlg.picking
            width: parent.width
            y: parent.height - 31.3 - 8.7
            Rectangle {
                id: backButton
                width: 96; height: 32; radius: 4
                color: backHover.hovered ? theme.rowHover : "transparent"
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-left-20"; size: 20; color: theme.onFill(backButton, theme.textStrong) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(backButton, theme.textStrong) }
                }
                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.picking = false }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
            }
            Item { width: parent.width - 96 - 96 - 25; height: 1 }
            Rectangle {
                id: doneButton
                readonly property bool on: !!dlg.pickChoice
                width: 96; height: 32; radius: 4
                color: !on ? theme.pick("#F0F0F0", "#141414", "#000000") : doneHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Done"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(doneButton, doneButton.on ? "white" : theme.disabled) }
                HoverHandler { id: doneHover; cursorShape: doneButton.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: doneButton.on; onTapped: dlg.pickDone() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Done")
            }
        }
        Row {
            visible: !dlg.picking
            anchors.right: parent.right; anchors.rightMargin: -2
            y: parent.height - 31.3 - 8.7
            spacing: 8
            Rectangle {
                id: hcFill5
                width: 96; height: 31.3; radius: 4
                color: cancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill5, theme.text) }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: hcFill6
                width: 96; height: 31.3; radius: 4
                color: !dlg.canCreate ? theme.pick("#F0F0F0", "#141414", "#000000") : createHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Create"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill6, dlg.canCreate ? "white" : theme.disabled) }
                HoverHandler { id: createHover; cursorShape: dlg.canCreate ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: dlg.canCreate; onTapped: dlg.create() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Create")
            }
        }
    }

    // The private channel's member step (outside this dialog, which has closed).
    AddMembersDialog {
        id: memberStep
        parent: Overlay.overlay
        property string pendingId: ""
        property string pendingName: ""
        onFinished: dlg.created(pendingId, pendingName)
    }

    // Test hooks.
    function memberStepForTest() { return memberStep }
    function fillForTest(n, t, l, rec) { name = n; type = t; layout = l; recommend = !!rec }
}
