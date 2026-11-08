import QtQuick
import QtQuick.Controls

// Teams' confirmation dialog (Fluent Dialog), as measured on winpc: radius
// 8, padding 24, over a 40 % black backdrop. A 20/28 semibold title (with
// an optional 16 px glyph and 10 px gap before it, as the attendee
// mic/camera dialogs show a warning); the text from y 60.67 (14/20,
// wrapping) in a block at least 32 tall; then, 6 below it, Cancel and the
// primary action (96 wide, or as wide as its label; `fixedButtons` keeps
// them 96 and wraps their labels, as Teams' 410-wide attendee dialogs do).
// - "End the meeting?", "Lower all hands?": 400 x 152.67.
// - "Disable mic for attendees?": 410 x 204.67, "Disable mics" on two lines.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 400; height: buttons.y + buttons.height + 24.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string title: "End the meeting?"
    property string body: "You'll end the meeting for everyone."
    property string confirmText: "End"
    /// A glyph before the title ("alert-warning-16-filled").
    property string titleIcon: ""
    property bool fixedButtons: false
    signal confirmed()

    FluentIcon {
        visible: root.titleIcon.length > 0
        x: 24.67; y: 33.67; size: 16
        name: root.titleIcon
        color: theme.text
    }
    Text {
        x: root.titleIcon.length > 0 ? 50.67 : 24.67; y: 24.67; height: 28
        width: root.width - x - 24.67
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.title
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Text {
        id: bodyText
        x: 24.67; y: 60.67; width: root.width - 49.33
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.body
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    TextMetrics { id: confirmMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: root.confirmText }
    Row {
        id: buttons
        x: root.width - 24.67 - width
        y: 58.67 + Math.max(32, bodyText.height + 4) + 6
        spacing: 8
        component DialogButton: Rectangle {
            id: db
            property string label
            property bool primary: false
            signal clicked()
            readonly property real labelWidth: root.fixedButtons ? 72 : Math.ceil(confirmMetrics.advanceWidth * 100) / 100
            width: primary && !root.fixedButtons ? Math.max(96, labelWidth + 25.33) : 96
            height: label.length > 0 ? Math.max(31.33, dbText.height + 11.33) : 31.33
            radius: 4
            color: primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill)
                           : (dbHover.hovered ? theme.menuHover : theme.surface)
            border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
            Text {
                id: dbText
                anchors.centerIn: parent
                width: db.width - 24.67
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                text: db.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: db.primary ? theme.textOnBrand : theme.text
            }
            HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: db.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: db.label
        }
        DialogButton {
            label: "Cancel"
            height: Math.max(31.33, confirmButton.height)
            onClicked: root.close()
        }
        DialogButton {
            id: confirmButton
            label: root.confirmText
            primary: true
            onClicked: { root.close(); root.confirmed() }
        }
    }
}
