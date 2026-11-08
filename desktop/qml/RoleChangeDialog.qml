import QtQuick
import QtQuick.Controls

// Teams' "Change role?" confirmation before Make an attendee / Make a
// presenter (confirm-demote-dialog / confirm-promote-dialog, measured on
// winpc 2026-11-08). It is the older dialog style: 600 wide, radius 8,
// padding 27 / 32 / 32 over a 75 % #252424 backdrop; an 18 px bold title
// (25.71 line); the text (14/20, #0F0F0F) from y 60.7, wrapping at 536;
// Cancel and Change (96 x 31.33, 8 apart) 20 below it at the right.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    /// Making someone an attendee while they share their screen: Teams
    /// warns that they can't start sharing again.
    property bool presenting: false
    signal confirmed()
    width: 600; height: body.y + body.height + 20 + 31.33 + 32
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.75) }

    Text {
        x: 32; y: 27; height: 25.71; verticalAlignment: Text.AlignVCenter
        text: "Change role?"
        font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
        color: theme.text
    }
    Text {
        id: body
        x: 32; y: 60.7; width: 536
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.presenting
            ? "The person sharing now will be able to continue, but they won't be able to start again"
            : "A participant's role determines whether they can share content, mute others, and more."
        font.family: theme.font; font.pixelSize: 14
        color: theme.pick("#0F0F0F", theme.text)
    }
    Row {
        x: root.width - 32 - width; y: body.y + body.height + 20
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
            Text { anchors.centerIn: parent; text: "Change"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.close(); root.confirmed() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Change"
        }
    }
}
