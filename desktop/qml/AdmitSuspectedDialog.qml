import QtQuick
import QtQuick.Controls

// Teams' "Admit this unverified bot?" (admit-suspected-participant-dialog,
// measured on winpc): asked before admitting a guest the join shield
// flagged. Deny is the primary action; ticking "This isn't a bot" clears
// the guest's screening when they're admitted.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 264.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    property string personId: ""
    property string personName: ""
    property bool notBot: false
    signal admit(string id, string name, bool notBot)
    signal deny(string id, string name)

    function ask(id, name) { personId = id; personName = name; notBot = false; open() }

    Text {
        x: 24; y: 24.7; width: 518.7; height: 28
        verticalAlignment: Text.AlignVCenter
        text: "Admit this unverified bot?"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Rectangle {
        x: 551.3; y: 25.5; width: 24; height: 23.3; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    // Who: their avatar, name and badge.
    GuestAvatar { x: 24.7; y: 66.7; personId: root.personId }
    Row {
        x: 66.7; y: 70.7; height: 24
        spacing: 4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.personName
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        UnverifiedBadge { anchors.verticalCenter: parent.verticalCenter }
    }
    Text {
        x: 24.7; y: 114.7; width: 550.7
        wrapMode: Text.Wrap
        text: "External bots might record or transcribe your meeting and cause sensitive information to leave your org. Admit this bot only if you know and trust it."
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    // "This isn't a bot"
    Item {
        x: 24.7; y: 168.7; width: 133.6; height: 32
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 2
            color: root.notBot ? theme.brandFill : "transparent"
            border.color: root.notBot ? theme.brandFill : theme.textSecondary; border.width: 0.67
            FluentIcon { visible: root.notBot; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
        }
        Text {
            x: 36; anchors.verticalCenter: parent.verticalCenter
            text: "This isn't a bot"
            font.family: theme.font; font.pixelSize: 14
            color: theme.textSecondary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.notBot = !root.notBot }
        Accessible.role: Accessible.CheckBox
        Accessible.name: "This isn't a bot"
        Accessible.checked: root.notBot
    }
    Row {
        x: 375.3; y: 208.7
        spacing: 8
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: admitHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Admit"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: admitHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.admit(root.personId, root.personName, root.notBot) } }
            Accessible.role: Accessible.Button
            Accessible.name: "Admit"
        }
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: denyHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Deny"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            HoverHandler { id: denyHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.deny(root.personId, root.personName) } }
            Accessible.role: Accessible.Button
            Accessible.name: "Deny"
        }
    }
}
