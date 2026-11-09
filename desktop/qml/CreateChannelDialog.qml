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
// the new channel.
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
        { key: "Standard", label: "Standard", hint: "Everyone on the team has access.", icon: "people-team-20", tile: "#BDD99B" },
        { key: "Shared", label: "Shared", hint: "People or teams in your org or outside your org can have access.", icon: "channel-share-20", tile: "#A6E9ED" },
        { key: "Private", label: "Private", hint: "Specific people on the team have access.", icon: "lock-closed-20", tile: "#FFDDB3" }
    ]
    readonly property var chosenType: types.find(t => t.key === type) || null
    readonly property string nameError: {
        const n = name.trim()
        if (!n) return ""
        if (n.startsWith("_") || n.startsWith(".")) return "Channel name cannot start with an underscore (_) or a period (.)"
        if (/[~#%&*{}+\/\\:<>?|'"]/.test(n) || n.indexOf("..") >= 0) return "We don't support these characters: ~#%&*{}+/\\:<>?|'\".."
        if (n.endsWith(".")) return "Channel name cannot end with a period (.)"
        if (/https?:\/\/|www\./i.test(n)) return "Links are not allowed in the channel name"
        if (n.toLowerCase() === "general") return "General can only be used for the first-created channel in a team. Try another name."
        return ""
    }
    readonly property bool nameGood: name.trim().length > 0 && !nameError
    readonly property bool canCreate: nameGood && !!type && !creating

    function start(tid, tname) {
        teamId = tid; teamName = tname
        name = ""; description = ""; type = ""; recommend = false; layout = "Conversational"
        creating = false; failure = ""
        open()
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
            if (r.ok) { dlg.close(); dlg.created(r.data.id, r.data.name) }
            else dlg.failure = /409|conflict|already/i.test(r.error || "") ? "Channel name is already taken." : "Something went wrong on our end. Please try again."
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; padding: 24
    height: Overlay.overlay ? Overlay.overlay.height : 680
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    component Label: Row {
        property string text
        property bool required: false
        Text { text: parent.text; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { visible: parent.required; leftPadding: 4; text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#D13438", "#DC626D") }
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
        border.color: lcHover.hovered ? theme.textSecondary : theme.pick("#D1D1D1", "#666666"); border.width: 0.67
        Image {
            x: 8.6; y: 6.6; width: 140; height: 80
            source: "../assets/illustrations/channel-layout-" + lc.picture + (theme.dark ? "-dark" : "") + ".svg"
            sourceSize: Qt.size(280, 160)
        }
        Rectangle {
            visible: lc.isNew
            x: 17; y: 2; height: 20; radius: 10
            width: newText.implicitWidth + 12
            color: theme.brandFill
            Text { id: newText; anchors.centerIn: parent; text: "New"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: "white" }
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
            text: "Create a channel"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        Column {
            x: 2.7; y: 42.7; width: 546.7
            spacing: 0
            Label { text: "Channel name"; required: true }
            Item { width: 1; height: 3 }
            Rectangle {
                width: parent.width; height: 32; radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F")
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
                    Text { visible: !nameField.text; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Letters, numbers, and spaces are allowed"; font: nameField.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Channel name"
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
            Label { text: "Description" }
            Item { width: 1; height: 3 }
            Rectangle {
                width: parent.width; height: Math.max(55.3, descField.contentHeight + 20); radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F")
                TextEdit {
                    id: descField
                    x: 12; y: 10; width: parent.width - 24
                    text: dlg.description
                    onTextChanged: if (text !== dlg.description) dlg.description = text
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    Text { visible: !descField.text; text: "Help others find the right channel by providing a description"; font: descField.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Description"
                }
            }
            Item { width: 1; height: 18 }
            Row {
                height: 21.3
                Label { text: "Choose a channel type"; required: true; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 32; height: 21.3; radius: 4
                    color: infoHover.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview") }
                    ToolTip.visible: infoHover.hovered; ToolTip.delay: 300; ToolTip.text: "Learn more about channel types"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Learn more about channel types"
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
                    text: dlg.chosenType ? dlg.chosenType.label + " — " + dlg.chosenType.hint.replace(/\.$/, "") : "Select"
                    font.family: theme.font; font.pixelSize: 14
                    color: dlg.chosenType ? theme.text : theme.pick("#707070", "#ADADAD")
                }
                FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: typeList.opened ? typeList.close() : typeList.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Choose a channel type"
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
                                FluentIcon { visible: dlg.type === opt.modelData.key; x: 6; y: 16; size: 16; name: "checkmark-16"; color: theme.text }
                                Rectangle {
                                    x: 28; y: 8; width: 32; height: 32; radius: 5
                                    color: opt.modelData.tile
                                    FluentIcon { anchors.centerIn: parent; size: 20; name: opt.modelData.icon; color: "#242424" }
                                }
                                Text { x: 67; y: 6; text: opt.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                Text { x: 67; y: 26; width: parent.width - 75; elide: Text.ElideRight; text: opt.modelData.hint; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
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
                        x: 8; y: 10; width: 16; height: 16; radius: 2
                        color: dlg.recommend ? theme.brand : "transparent"
                        border.color: dlg.recommend ? theme.brand : theme.textSecondary; border.width: 0.67
                        FluentIcon { visible: dlg.recommend; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: "white" }
                    }
                    Text { id: recText; x: 36; y: 8; text: "Recommend that people show this channel in their channel lists"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: dlg.recommend ? theme.text : theme.textSecondary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.recommend = !dlg.recommend }
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: dlg.recommend
                    Accessible.name: recText.text
                }
            }
            Item { width: 1; height: 16 }
            Text { text: "Layout"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { text: "Channel owners can change this at any time"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 10 }
            Row {
                spacing: 12
                LayoutCard { key: "Conversational"; picture: "conversational"; label: "Threads"; hint: "Looks like chat with replies on the side in threads. Good for back-and-forth discussions."; isNew: true }
                LayoutCard { key: "PostReply"; picture: "post-reply"; label: "Posts"; hint: "Posts reorder by most recent reply. Good for forums and announcements." }
            }
            Text {
                visible: !!dlg.failure
                topPadding: 12
                text: dlg.failure
                font.family: theme.font; font.pixelSize: 12; color: theme.danger
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: -2
            y: parent.height - 31.3 - 8.7
            spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: cancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: !dlg.canCreate ? theme.pick("#F0F0F0", "#141414") : createHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Create"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: dlg.canCreate ? "white" : theme.disabled }
                HoverHandler { id: createHover; cursorShape: dlg.canCreate ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: dlg.canCreate; onTapped: dlg.create() }
                Accessible.role: Accessible.Button; Accessible.name: "Create"
            }
        }
    }

    // Test hooks.
    function fillForTest(n, t, l, rec) { name = n; type = t; layout = l; recommend = !!rec }
}
