import QtQuick
import QtQuick.Controls.Basic

// Teams' team confirmations (the team menu's Archive, Leave and Delete,
// measured on winpc 2026-11-09): 600 wide, padding 20 30.7 32, radius 8;
// the title 18/28 semibold; the text (14/20, the team's name bold where
// Teams bolds it) 36 down; an optional checkbox (16 px in a 32 box, its
// label 14/20 #616161) 40 under the text; Cancel and the action (96 x 31.3,
// 8 apart) at the right, 40 under that.
// - Archive (200.7 tall): "Want to archive the {team} team?", Teams' text
//   and "Make the SharePoint site read-only for team members"; Archive.
// - Leave (128.7): "Are you sure you want to leave the {team} team?"; No /
//   Yes.
// - Delete (220.7): "Delete the {team} team", Teams' warning and "I
//   understand that everything will be deleted", which Delete team waits
//   for.
// - Pending requests' Deny all: "Deny all join requests"; Cancel / Deny all.
// - The last owner leaving: "The last owner can't leave the team", why;
//   OK.
Popup {
    id: dlg
    property string kind: "archive"
    property string teamName: ""
    property bool checked: false
    signal confirmed(bool checked)
    readonly property string esc: teamName.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    readonly property var spec: ({
        archive: {
            title: "Want to archive the " + teamName + " team?",
            body: "This will freeze all team activity, but you'll still be able to remove members and update roles. Go to <b>Manage teams</b> to restore the team.",
            check: "Make the SharePoint site read-only for team members",
            cancel: "Cancel", action: "Archive"
        },
        leave: { title: "Are you sure you want to leave the " + teamName + " team?", body: "", check: "", cancel: "No", action: "Yes" },
        "delete": {
            title: "Delete the " + teamName + " team",
            body: "Are you sure you want to delete the <b>" + esc + "</b> team? All hosted channels, conversations, files, and the Microsoft 365 group for this team will be deleted. You'll lose access to any shared channels that have been shared with the team.",
            check: "I understand that everything will be deleted",
            cancel: "Cancel", action: "Delete team"
        },
        denyAll: {
            title: "Deny all join requests",
            body: "Are you sure you want to deny all join requests for " + esc + "?",
            check: "", cancel: "Cancel", action: "Deny all"
        },
        lastOwner: {
            title: "The last owner can't leave the team",
            body: "You're the last owner of the " + esc + " team. There has to be at least one other owner for you to leave the team.",
            check: "", cancel: "", action: "OK"
        }
    })[kind]
    function start(k, name) { kind = k; teamName = name; checked = false; open() }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600
    height: buttons.y + buttons.height + 52
    topPadding: 20; leftPadding: 30.7; rightPadding: 30.7; bottomPadding: 32
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            id: titleText
            y: 0.6; width: parent.width
            wrapMode: Text.Wrap
            text: dlg.spec.title
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            id: bodyText
            visible: dlg.spec.body.length > 0
            y: titleText.y + titleText.height + 8; width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: dlg.spec.body
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item {
            id: check
            visible: dlg.spec.check.length > 0
            y: bodyText.y + bodyText.height
            width: 32 + checkText.implicitWidth + 12; height: 32
            Rectangle {
                x: 8; y: 8; width: 16; height: 16; radius: 2
                color: dlg.checked ? theme.brandFill : "transparent"
                border.color: dlg.checked ? theme.brandFill : theme.textSecondary; border.width: 0.67
                FluentIcon { visible: dlg.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand }
            }
            Text {
                id: checkText
                x: 36; y: 6
                text: dlg.spec.check
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: dlg.checked ? theme.text : theme.textSecondary
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.checked = !dlg.checked }
            Accessible.role: Accessible.CheckBox
            Accessible.checked: dlg.checked
            Accessible.name: dlg.spec.check
        }
        Row {
            id: buttons
            anchors.right: parent.right
            y: check.visible ? check.y + check.height + 8 : bodyText.visible ? bodyText.y + bodyText.height + 8 : titleText.y + titleText.height + 16
            spacing: 8
            Btn { visible: dlg.spec.cancel.length > 0; text: dlg.spec.cancel; onClicked: dlg.close() }
            Btn {
                text: dlg.spec.action; primary: true
                enabled: dlg.kind !== "delete" || dlg.checked
                onClicked: { dlg.close(); if (dlg.kind !== "lastOwner") dlg.confirmed(dlg.checked) }
            }
        }
    }

    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, btnText.implicitWidth + 24); height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
