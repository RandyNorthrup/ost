import QtQuick
import QtQuick.Controls.Basic

// Edit channel (Teams' edit-channel dialog, measured on winpc 2026-11-09):
// 600 wide, padding 24, radius 8.
// - "Edit the <b>{name}</b> channel" (20/28 semibold, the name black).
// - General: "This is the first-created channel in the team. …" with
//   "Learn about first-created channels"; the name stays General ("Using
//   General will display the channel at the top of the team instead of
//   alphabetically."). Other channels: the name and a Description.
// - "Channel name" with its red *, the field (32, #F5F5F5, radius 4, 50
//   characters, "Letters, numbers, and spaces are allowed"), Teams' name
//   rules under it.
// - Layout ("Channel owners can change this at any time"): two cards
//   (157.3 x 167.3, 12 apart, radius 6, a 0.67 px #D1D1D1 line, padding
//   6 8): the 140 x 80 picture, the name (14/20) with the radio (16) at the
//   card's end, what it is (10/14); Threads carries "New".
// - Cancel and Save (96 x 31.3); Save once something changed.
// Saving patches the channel through the middle tier (displayName,
// description, chatModalityType), as Teams does.
Popup {
    id: dlg
    property string teamId: ""
    property var channel: ({})
    property string name: ""
    property string description: ""
    property string layout: "PostReply"
    property bool saving: false
    property string failure: ""
    readonly property bool general: channel.general === true
    readonly property string nameError: {
        const n = name.trim()
        if (general || !n) return ""
        if (n.startsWith("_") || n.startsWith(".")) return "Channel name cannot start with an underscore (_) or a period (.)"
        if (/[~#%&*{}+\/\\:<>?|'"]/.test(n) || n.indexOf("..") >= 0) return "We don't support these characters: ~#%&*{}+/\\:<>?|'\".."
        if (n.endsWith(".")) return "Channel name cannot end with a period (.)"
        if (/https?:\/\/|www\./i.test(n)) return "Links are not allowed in the channel name"
        if (n.toLowerCase() === "general") return "General can only be used for the first-created channel in a team. Try another name."
        return ""
    }
    readonly property string descriptionError: /https?:\/\/|www\./i.test(description) ? "Links are not allowed in the channel description" : ""
    readonly property bool changed: (!general && name.trim() !== (channel.name || ""))
        || (!general && description !== (channel.description || ""))
        || layout !== (channel.layout || "PostReply")
    readonly property bool canSave: changed && !saving && !nameError && !descriptionError && (general || name.trim().length > 0)

    function start(c) {
        channel = c; name = c.name || ""; description = c.description || ""
        layout = c.layout || "PostReply"; saving = false; failure = ""
        open()
    }
    function save() {
        const change = {}
        if (!general && name.trim() !== channel.name) change.displayName = name.trim()
        if (!general && description !== (channel.description || "")) change.description = description
        if (layout !== (channel.layout || "PostReply")) change.chatModalityType = layout
        saving = true; failure = ""
        backend.channelAction("edit", teamId, channel.id, JSON.stringify(change))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "edit" || r.channel !== dlg.channel.id) return
            dlg.saving = false
            if (r.ok) dlg.close()
            else dlg.failure = /409|conflict|already/i.test(r.error || "") ? "Channel name is already taken." : "Something went wrong on our end. Please try again."
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; padding: 24
    height: Math.min(implicitHeight, (Overlay.overlay ? Overlay.overlay.height : 680))
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

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

    contentItem: Column {
        spacing: 0
        Text {
            width: parent.width
            textFormat: Text.StyledText
            text: "Edit the <b>" + (dlg.channel.name || "").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b> channel"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item { width: 1; height: 10.6 }
        Text {
            visible: dlg.general
            width: parent.width - 30; wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: "This is the first-created channel in the team. It uses the team description, and it’s automatically shown for all members in their lists <a href=\"https://go.microsoft.com/fwlink/?linkid=2275168\">Learn about first-created channels</a>"
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            linkColor: theme.brandForeground1
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
        Item { width: 1; height: 4 }
        Row {
            spacing: 0
            Text { text: "Channel name"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { leftPadding: 4; text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#D13438", "#DC626D") }
        }
        Item { width: 1; height: 3 }
        Rectangle {
            width: parent.width; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#1F1F1F")
            TextInput {
                id: nameField
                anchors.fill: parent; leftPadding: 12; rightPadding: 12
                verticalAlignment: TextInput.AlignVCenter
                text: dlg.name
                readOnly: dlg.general
                maximumLength: 50
                onTextEdited: dlg.name = text
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                Text { visible: !nameField.text; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Letters, numbers, and spaces are allowed"; font: nameField.font; color: theme.textTertiary }
                Accessible.name: "Channel name"
            }
            Rectangle {
                anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: nameField.activeFocus ? 2 : 0
                color: dlg.nameError ? theme.danger : theme.brand
            }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            visible: text.length > 0
            text: dlg.nameError || (dlg.general ? "Using General will display the channel at the top of the team instead of alphabetically." : "")
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: dlg.nameError ? theme.danger : theme.text
        }
        // Other channels: a description.
        Column {
            visible: !dlg.general
            width: parent.width
            Item { width: 1; height: 20 }
            Text { text: "Description"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 3 }
            Rectangle {
                width: parent.width; height: Math.max(64, descField.contentHeight + 12); radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F")
                TextEdit {
                    id: descField
                    x: 12; y: 6; width: parent.width - 24
                    text: dlg.description
                    onTextChanged: if (text !== dlg.description) dlg.description = text
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    Text { visible: !descField.text; text: "Help others find the right channel by providing a description"; font: descField.font; color: theme.textTertiary }
                    Accessible.name: "Description"
                }
            }
            Text {
                visible: !!dlg.descriptionError
                text: dlg.descriptionError
                font.family: theme.font; font.pixelSize: 12; color: theme.danger
            }
        }
        Item { width: 1; height: 24 }
        Text { text: "Layout"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { text: "Channel owners can change this at any time"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Item { width: 1; height: 10 }
        Row {
            x: 2; spacing: 12
            LayoutCard { key: "Conversational"; picture: "conversational"; label: "Threads"; hint: "Looks like chat with replies on the side in threads. Good for back-and-forth discussions."; isNew: true }
            LayoutCard { key: "PostReply"; picture: "post-reply"; label: "Posts"; hint: "Posts reorder by most recent reply. Good for forums and announcements." }
        }
        Text {
            visible: !!dlg.failure
            topPadding: 12
            text: dlg.failure
            font.family: theme.font; font.pixelSize: 12; color: theme.danger
        }
        Item { width: 1; height: 32 }
        Row {
            anchors.right: parent.right
            spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: cancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Cancel"
            }
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: !dlg.canSave ? theme.pick("#F0F0F0", "#141414") : saveHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: dlg.canSave ? "white" : theme.disabled }
                HoverHandler { id: saveHover; cursorShape: dlg.canSave ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: dlg.canSave; onTapped: dlg.save() }
                Accessible.role: Accessible.Button; Accessible.name: "Save"
            }
        }
    }
}
