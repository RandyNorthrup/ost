import QtQuick
import QtQuick.Controls

// Teams' "Invite people to join you" (share-meeting-invite-dialog, measured
// on winpc): 400 wide, padding 24, radius 8, no backdrop (a click outside
// closes it). "Copy meeting link" copies the meeting's link and shows
// "Copied to clipboard" for 2 s; "Share via default email" opens a mail with
// Teams' subject and text.
Popup {
    id: root
    property string link: ""
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    width: 400; height: 218
    padding: 0
    modal: false; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 4; radius: 8; color: theme.surface }
    property bool copied: false
    Timer { id: copiedTimer; interval: 2000; onTriggered: root.copied = false }
    onClosed: copied = false

    Text {
        x: 24; y: 24; height: 22; verticalAlignment: Text.AlignVCenter
        text: "Invite people to join you"
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
        color: theme.text
    }
    Text {
        x: 24; y: 46; height: 20; verticalAlignment: Text.AlignVCenter
        text: "Copy and share the link to invite someone."
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Rectangle {
        x: 352; y: 21; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.text }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    InviteButton {
        y: 90
        icon: root.copied ? "invite-check-16" : "invite-link-16"
        label: root.copied ? "Copied to clipboard" : "Copy meeting link"
        onClicked: {
            if (root.copied) return
            backend.copyText(root.link)
            root.copied = true
            copiedTimer.restart()
        }
    }
    InviteButton {
        y: 146
        icon: "invite-mail-16"
        label: "Share via default email"
        onClicked: Qt.openUrlExternally("mailto:?subject=" + encodeURIComponent("Join Teams meeting in progress")
            + "&body=" + encodeURIComponent("You're invited to join a Microsoft Teams meeting\r\n\r\nUse the link below to join\r\n" + root.link))
    }

    // Teams' invite options: 352 x 48, white with a 0.67 NeutralStroke1
    // edge and a depth-4 shadow, the 16 px glyph at 17.7, the label at 46.7.
    component InviteButton: Item {
        id: ib
        property string icon
        property string label
        signal clicked()
        x: 24; width: 352; height: 48
        FluentSurface { anchors.fill: parent; depth: 4; radius: 4; color: ibHover.hovered ? theme.menuHover : theme.surface; borderColor: theme.stroke }
        FluentIcon { x: 17.7; anchors.verticalCenter: parent.verticalCenter; name: ib.icon; size: 16; color: theme.text }
        Text {
            x: 46.7; anchors.verticalCenter: parent.verticalCenter
            text: ib.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
        }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ib.label
    }
}
