import QtQuick
import QtQuick.Controls

// Teams' "Lock the meeting?" / "Unlock the meeting" dialog
// (confirm-meeting-lock-dialog, measured on winpc 2026-11-08): 430 wide,
// radius 8, padding 24; the 20/28 semibold title; a 250 tall illustration
// (the scene 380.66 x 204 centred, the lock 117.27 x 180 over it); the
// text (14/20, wrapping at 380.67); then Cancel and Lock / Unlock (96 x
// 31.33, 8 apart) at the bottom right.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    /// The meeting is locked now: the dialog offers Unlock.
    property bool locked: false
    signal confirmed()
    width: 430; height: text.y + text.height + 20 + 31.33 + 24.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    Text {
        x: 24.67; y: 24.67; height: 28; verticalAlignment: Text.AlignVCenter
        text: root.locked ? "Unlock the meeting" : "Lock the meeting?"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Image {
        x: 24.67; y: 95.66; width: 380.66; height: 204.01
        source: "../assets/dialogs/meeting-lock-background.svg"
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Image {
        x: 156.36; y: 107.67; width: 117.27; height: 180
        source: root.locked ? "../assets/dialogs/meeting-unlock.svg" : "../assets/dialogs/meeting-lock.svg"
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Text {
        id: text
        x: 24.67; y: 322.67; width: 380.67
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.locked ? "People will be able to join."
                          : "No one else will be able to join, but invitees can still access the meeting chat, the recording, and other meeting info."
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Row {
        x: root.width - 24.67 - width; y: text.y + text.height + 20
        spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: okHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: root.locked ? "Unlock" : "Lock"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.confirmed() } }
            Accessible.role: Accessible.Button
            Accessible.name: root.locked ? "Unlock" : "Lock"
        }
    }
}
