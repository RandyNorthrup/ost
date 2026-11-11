import QtQuick
import QtQuick.Effects

// Teams' lobby notification (ufd_lobby, measured on winpc): shown at the
// top of the stage while people wait and the People pane is closed. One
// person: their name (with the Unverified badge for a screened guest), then
// Deny and Admit, or Deny and View Lobby for a suspected bot. More: the
// first name, " +n" and View Lobby only. The bell mutes these for the rest
// of the meeting (an 8 s confirmation with Undo); the cross hides it until
// the lobby changes.
Item {
    id: root
    /// Who waits: [{id, name, suspected}].
    property var lobby: []
    /// The People pane is open (Teams dismisses the toast then).
    property bool rosterOpen: false
    property bool muted: false
    signal admit(string id, string name)
    signal deny(string id, string name)
    signal viewLobby()
    /// Teams' lobby chat (organizers, one person waiting who isn't a
    /// suspected bot): the chat button before Deny opens it.
    property bool chatAvailable: false
    signal chatLobby()
    readonly property bool chatShown: chatAvailable && lobby.length === 1 && !first.suspected

    /// The lobby as it was when the toast was dismissed; it comes back when
    /// someone new arrives or leaves.
    property string dismissedFor: ""
    readonly property string signature: lobby.map(p => p.id).join(",")
    readonly property bool confirming: muteTimer.running
    readonly property bool showing: lobby.length > 0 && !rosterOpen && !muted && dismissedFor !== signature
    visible: showing || confirming
    width: 320
    height: confirming ? 63.3 : 121.2
    readonly property var first: lobby.length ? lobby[0] : ({ id: "", name: "", suspected: false })

    function mute() { muted = true; muteTimer.restart() }
    function undoMute() { muted = false; muteTimer.stop() }
    function resetForCall() { muted = false; dismissedFor = ""; muteTimer.stop() }
    // Teams: temporal notifications close after 8 s (Ufd.temporalStackTimeout).
    Timer { id: muteTimer; interval: 8000 }

    // The surface: #FAFAFA, 0.67 #F0F0F0 edge, radius 8, and Teams'
    // drop-shadow(0 0.6px 1.8px .11) drop-shadow(0 3.2px 7.2px .13).
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: Qt.rgba(0, 0, 0, 0.11) }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: Qt.rgba(0, 0, 0, 0.13) }
    Rectangle {
        id: surface
        width: parent.width; height: parent.height
        radius: 8
        color: theme.quoteFill
        border.color: theme.quoteBorder; border.width: 0.67
    }

    // The waiting notification.
    Item {
        visible: !root.confirming
        anchors.fill: parent
        FluentIcon { x: 12; y: 12; name: "people-team-20-filled"; size: 16; color: theme.text }
        Text {
            x: 36; y: 12; height: 20; verticalAlignment: Text.AlignVCenter
            text: "Waiting in the lobby"
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        ToastButton { x: 263.1; y: 14; icon: "alert-snooze-20"; label: "Mute lobby notifications"; onClicked: root.mute() }
        ToastButton { x: 290.6; y: 14; icon: "dismiss-20"; label: "Dismiss"; onClicked: root.dismissedFor = root.signature }

        // Who: the first name, their badge, and " +n" for the others.
        Row {
            x: 12; y: 40; height: 24.5
            spacing: 0
            Text {
                id: firstName
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 294.7 - (badge.visible ? badge.width + 4 : 0) - (more.visible ? more.implicitWidth : 0))
                elide: Text.ElideRight
                text: root.first.name
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
            Item { visible: badge.visible; width: 4; height: 1 }
            UnverifiedBadge { id: badge; visible: !!root.first.suspected; anchors.verticalCenter: parent.verticalCenter }
            Text {
                id: more
                visible: root.lobby.length > 1
                anchors.verticalCenter: parent.verticalCenter
                text: " +" + (root.lobby.length - 1)
                font.family: theme.font; font.pixelSize: 14
                color: theme.textSecondary
            }
        }

        // The actions (Teams' lobby-popup buttons, 8 apart, sharing the width).
        Row {
            id: actions
            x: 12; y: 76.5
            spacing: 8
            readonly property var buttons: root.lobby.length > 1
                ? [{ t: "View Lobby", primary: true, act: "view" }]
                : root.first.suspected
                    ? [{ t: "Deny", primary: false, act: "deny" }, { t: "View Lobby", primary: true, act: "view" }]
                    : [{ t: "Deny", primary: false, act: "deny" }, { t: "Admit", primary: true, act: "admit" }]
            // "Send message to lobby participants" (measured on winpc
            // 2026-11-11): 32 x 31.3, white, a NeutralStroke1 edge, radius
            // 4, the chat glyph (20, filled on hover).
            Rectangle {
                visible: root.chatShown
                width: 32; height: 31.3; radius: 4
                color: ch.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                FluentIcon { anchors.centerIn: parent; name: ch.hovered ? "chat-20-filled" : "chat-20"; size: 20; color: ch.hovered ? theme.brand : theme.text }
                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.chatLobby() }
                Accessible.role: Accessible.Button
                Accessible.name: "Send message to lobby participants"
            }
            Repeater {
                model: actions.buttons
                Rectangle {
                    required property var modelData
                    width: (294.7 - (root.chatShown ? 40 : 0) - 8 * (actions.buttons.length - 1)) / actions.buttons.length
                    height: 31.3; radius: 4
                    color: modelData.primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
                    border.color: modelData.primary ? "transparent" : theme.stroke; border.width: 0.67
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: parent.modelData.primary ? "white" : theme.text
                    }
                    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const a = parent.modelData.act
                            if (a === "view") root.viewLobby()
                            else if (a === "deny") root.deny(root.first.id, root.first.name)
                            else root.admit(root.first.id, root.first.name)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.t
                }
            }
        }
    }

    // "Lobby notifications are muted for the rest of the meeting. Undo"
    Item {
        visible: root.confirming
        anchors.fill: parent
        FluentIcon { x: 12; y: 21; name: "alert-snooze-20"; size: 20; color: theme.textSecondary }
        Text {
            x: 40; y: 11.7; width: 252.7 - 2
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: "Lobby notifications are muted for the rest of the meeting. <a href=\"undo\" style=\"color:" + theme.brandLink + "\">Undo</a>"
            linkColor: theme.brandLink
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
            onLinkActivated: root.undoMute()
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        ToastButton { x: 290.6; y: 15; icon: "dismiss-20"; label: "Dismiss"; onClicked: muteTimer.stop() }
    }

    // Teams' alert buttons: a 16 px target with a 20 px glyph in #616161.
    component ToastButton: Item {
        id: tb
        property string icon
        property string label
        signal clicked()
        width: 16; height: 16
        FluentIcon { anchors.centerIn: parent; name: tb.icon; size: 20; color: theme.textSecondary }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tb.label
    }
}
