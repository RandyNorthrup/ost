import QtQuick
import QtQuick.Controls

// Teams' "End the meeting?" (measured on winpc): 400 x 152.7, radius 8,
// padding 24, over a 40 % black backdrop; Cancel, then End (primary).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 400; height: 152.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    signal confirmed()

    Text {
        x: 24.7; y: 24.6; height: 28; verticalAlignment: Text.AlignVCenter
        text: "End the meeting?"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Text {
        x: 24.7; y: 60.6; height: 20; verticalAlignment: Text.AlignVCenter
        text: "You'll end the meeting for everyone."
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Row {
        x: 175.3; y: 96.6
        spacing: 8
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: endHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "End"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            HoverHandler { id: endHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.confirmed() } }
            Accessible.role: Accessible.Button
            Accessible.name: "End"
        }
    }
}
