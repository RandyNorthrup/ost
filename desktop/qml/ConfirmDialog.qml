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
// - `stacked` (Teams' RTT dialog, 320 x 204): the buttons fill the width,
//   Cancel above the primary action, 8 apart.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: dialogWidth > 0 ? dialogWidth : stacked ? 320 : 400; height: buttons.y + buttons.height + 24.67
    /// A width of its own (Fluent's DialogSurface without one: 600).
    property real dialogWidth: 0
    /// A Fluent checkbox at the start of the buttons' row (Teams'
    /// DialogActions position "start"), as Mark all as read's "Don't ask
    /// again"; `checked` holds it.
    property string checkText: ""
    property bool checked: false
    onAboutToShow: checked = false
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string title: qsTr("End the meeting?")
    property string body: qsTr("You'll end the meeting for everyone.")
    property string confirmText: qsTr("End")
    /// The dismissing button ("Close" in Teams' Discard draft message).
    property string cancelText: qsTr("Cancel")
    /// A glyph before the title ("alert-warning-16-filled").
    property string titleIcon: ""
    property bool fixedButtons: false
    property bool stacked: false
    /// Teams' breakout rooms dialogs ("Delete Room 1?", "Remove rooms?")
    /// carry a 32 x 31.33 Close at the title's end.
    property bool closeButton: false
    signal confirmed()
    /// Cancel (not Esc).
    signal cancelled()

    Rectangle {
        id: hcFill1
        visible: root.closeButton
        x: root.width - 24.67 - 32; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close")
    }

    FluentIcon {
        visible: root.titleIcon.length > 0
        x: 24.67; y: 33.67; size: 16
        name: root.titleIcon
        color: theme.text
    }
    Text {
        x: root.titleIcon.length > 0 ? 50.67 : 24.67; y: 24.67; height: 28
        width: root.width - x - 24.67 - (root.closeButton ? 40 : 0)
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
    // The checkbox: a 16 px square 8 in, its label at 36 (secondary text,
    // primary once ticked), centred on the buttons.
    Item {
        visible: root.checkText.length > 0
        x: 24.67 - 8; width: checkLabel.implicitWidth + 36 + 8; height: 32
        y: buttons.y + (Math.min(buttons.height, 31.33) - height) / 2
        Rectangle {
            id: checkBox
            x: 8; y: 8; width: 16; height: 16; radius: 2
            color: root.checked ? theme.brandFill : "transparent"
            border.color: root.checked ? theme.brandFill : theme.textSecondary; border.width: 0.67
            FluentIcon { visible: root.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(checkBox, "white") }
        }
        Text {
            id: checkLabel
            x: 36; anchors.verticalCenter: parent.verticalCenter
            text: root.checkText
            font.family: theme.font; font.pixelSize: 14
            color: root.checked ? theme.text : theme.textSecondary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.checked = !root.checked }
        Accessible.role: Accessible.CheckBox
        Accessible.name: root.checkText
        Accessible.checked: root.checked
    }
    TextMetrics { id: confirmMetrics; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; text: root.confirmText }
    Grid {
        id: buttons
        x: root.width - 24.67 - width
        y: 58.67 + Math.max(32, bodyText.height + 4) + 6
        columns: root.stacked ? 1 : 2
        spacing: 8
        component DialogButton: Rectangle {
            id: db
            property string label
            property bool primary: false
            signal clicked()
            readonly property real labelWidth: root.fixedButtons ? 72 : Math.ceil(confirmMetrics.advanceWidth * 100) / 100
            width: root.stacked ? root.width - 49.33 : primary && !root.fixedButtons ? Math.max(96, labelWidth + 25.33) : 96
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
                color: theme.onFill(db, db.primary ? theme.textOnBrand : theme.text)
            }
            HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: db.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: db.label
        }
        DialogButton {
            label: root.cancelText
            height: Math.max(31.33, confirmButton.height)
            onClicked: { root.close(); root.cancelled() }
        }
        DialogButton {
            id: confirmButton
            label: root.confirmText
            primary: true
            onClicked: { root.close(); root.confirmed() }
        }
    }
}
