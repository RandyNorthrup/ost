import QtQuick
import QtQuick.Controls.Basic

// Edit {team} team details (Manage team ▸ Settings ▸ Team details ▸ Edit;
// Teams' dialog, measured on winpc 2026-11-09): 600 x 600, padding 24,
// radius 8.
// - "Edit {team} team details" (20/28 semibold); "Collaborate closely with a
//   group of people inside your organization based on project, initiative,
//   or common interest." and "Learn more about teams and channels" (link)
//   36.6 down.
// - "Team name" * 86 down and its filled field (550.7 x 32, "Give your team
//   a name", a check at its end while the name is good) 106.6 down.
// - "Description" 152 down and its 77.3 tall field ("Let people know what
//   this team is all about") 172.6 down.
// - "Privacy" 274 down and its dropdown (327.6 x 30) 298.6 down: Private -
//   Only team owners can add members / Public - Anyone in your organization
//   can join.
// - Cancel / Done (96 x 31.3) at the bottom; Done once something changed.
// Done sends Teams' PATCH of the changed fields.
Popup {
    id: dlg
    property string teamId: ""
    property string teamThread: ""
    property var team: ({})
    property bool isPublic: false
    property bool saving: false
    readonly property bool changed: nameField.text.trim() !== (team.name || "") || descField.text !== (team.description || "") || isPublic !== !!team["public"]
    readonly property bool valid: nameField.text.trim().length > 0 && nameField.text.trim().length <= 256

    function start(t) {
        team = t; isPublic = !!t["public"]; saving = false
        nameField.text = t.name || ""; descField.text = t.description || ""
        open(); nameField.forceActiveFocus()
    }
    function done() {
        if (!changed || !valid) return
        const a = {}
        if (nameField.text.trim() !== (team.name || "")) a.name = nameField.text.trim()
        if (descField.text !== (team.description || "")) a.description = descField.text
        if (isPublic !== !!team["public"]) a["public"] = isPublic
        saving = true
        backend.channelAction("team-edit", teamId, teamThread, JSON.stringify(a))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "team-edit" || r.channel !== dlg.teamThread || !dlg.saving) return
            dlg.saving = false
            if (r.ok) dlg.close()
            else backend.toast("Something went wrong on our end. Please try again.", "error")
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; height: 600; padding: 24
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            y: 0.7; width: parent.width; elide: Text.ElideRight
            text: "Edit " + (dlg.team.name || "") + " team details"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            y: 36.6; width: 525.5; wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: "Collaborate closely with a group of people inside your organization based on project, initiative, or common interest. <a href=\"https://go.microsoft.com/fwlink/?linkid=2275168\">Learn more about teams and channels</a>"
            linkColor: theme.brandForeground1
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Row {
            y: 86; spacing: 4
            Text { text: "Team name"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Text { text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3 }
        }
        Rectangle {
            y: 106.6; width: 550.7; height: 32; radius: 4
            color: theme.inputFilled
            TextInput {
                id: nameField
                x: 12; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                maximumLength: 256
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Text { visible: !nameField.text; anchors.verticalCenter: parent.verticalCenter; text: "Give your team a name"; font: nameField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Team name"
            }
            FluentIcon { visible: dlg.valid; x: parent.width - 32; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-20"; size: 20; color: theme.textStrong }
            Rectangle { visible: nameField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        }
        Text { y: 152; text: "Description"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Rectangle {
            y: 172.6; width: 550.7; height: 77.3; radius: 4
            color: theme.inputFilled
            TextEdit {
                id: descField
                x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Text { visible: !descField.text; text: "Let people know what this team is all about"; font: descField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Description"
            }
            Rectangle { visible: descField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        }
        Text { y: 274; text: "Privacy"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Rectangle {
            id: privacy
            y: 298.6; width: 327.6; height: 30; radius: 4
            color: theme.inputFilled
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: dlg.isPublic ? "Public - Anyone in your organization can join" : "Private - Only team owners can add members"
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
            Rectangle { visible: privacyMenu.opened; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: privacyMenu.open() }
            Accessible.role: Accessible.ComboBox
            Accessible.name: "Privacy"
            Popup {
                id: privacyMenu
                y: privacy.height + 2; width: 328.9; height: 74; padding: 4
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                Column {
                    spacing: 2
                    Repeater {
                        model: [[false, "Private - Only team owners can add members"], [true, "Public - Anyone in your organization can join"]]
                        Rectangle {
                            id: popt
                            required property var modelData
                            width: 320.9; height: 32; radius: 4
                            color: poptHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { visible: dlg.isPublic === popt.modelData[0]; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                            Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: popt.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            HoverHandler { id: poptHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { privacyMenu.close(); dlg.isPublic = popt.modelData[0] } }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: popt.modelData[1]
                        }
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 8
            Btn { text: "Cancel"; onClicked: dlg.close() }
            Btn { text: "Done"; primary: true; enabled: dlg.changed && dlg.valid && !dlg.saving; onClicked: dlg.done() }
        }
    }

    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text { anchors.centerIn: parent; text: btn.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function setDescriptionForTest(d) { descField.text = d }
}
