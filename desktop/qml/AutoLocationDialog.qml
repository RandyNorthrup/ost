import QtQuick
import QtQuick.Controls

// Teams' "Why set my work location automatically?" dialog (Settings ▸
// Privacy ▸ Manage my work location ▸ "Learn about automatically setting a
// work location"; measured on winpc 2026-11-15): 600 wide, radius 8,
// centred on the window; Teams' illustration across the top (598.67 x
// 319.33, inset by the 0.67 border); the title (20/28 semibold) 24.67 in
// and 24 under the picture; two paragraphs (14/20) 16 and 20 apart; then
// the buttons (31.33 tall, 8 apart) 36 under the text at the bottom right,
// 24.67 from the edges. With the setting off: "Not now" (96) and the
// primary "Set my location automatically"; with it on: "Got it" (96,
// primary).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    /// The automatic work location is on now.
    property bool settingOn: false
    /// "Set my location automatically" was chosen.
    signal turnOn()
    width: 600; height: buttons.y + buttons.height + 24.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    Item {
        x: 0.67; y: 0.67; width: 598.67; height: 319.33
        clip: true
        // Rounded top corners, as the dialog's.
        Rectangle {
            anchors.fill: parent; anchors.bottomMargin: -8
            radius: 7.33; color: "transparent"
            clip: true
            Image {
                width: 598.67; height: 319.33
                source: "../assets/illustrations/work-location-auto.png"
                fillMode: Image.PreserveAspectCrop
                smooth: true; mipmap: true
            }
        }
        Accessible.role: Accessible.Graphic
        Accessible.name: "An office building on a desk"
    }
    Text {
        id: title
        x: 24.67; y: 343.9; width: 550.67
        text: "Why set my work location automatically?"
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Text {
        id: para1
        x: 24.67; y: title.y + title.height + 16; width: 550.67
        text: "Each time you connect to your organization's networks or devices, your profile card will show you're in the office."
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Text {
        id: para2
        x: 24.67; y: para1.y + para1.height + 20; width: 550.67
        text: "Your admin provides this option to help everyone better connect with each other when in the office. You can turn this on or off in Settings."
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Row {
        id: buttons
        x: root.width - 24.67 - width; y: para2.y + para2.height + 36
        spacing: 8
        component DialogButton: Rectangle {
            id: db
            property string label
            property bool primary: false
            signal clicked()
            width: Math.max(96, dbText.implicitWidth + 24); height: 31.33; radius: 4
            color: primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill) : (dbHover.hovered ? theme.menuHover : theme.surface)
            border.color: theme.stroke; border.width: primary ? 0 : 0.67
            Text { id: dbText; anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(db, db.primary ? theme.textOnBrand : theme.text) }
            HoverHandler { id: dbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: db.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: label
            Accessible.onPressAction: db.clicked()
        }
        DialogButton { visible: !root.settingOn; label: "Not now"; onClicked: root.close() }
        DialogButton { visible: !root.settingOn; primary: true; label: "Set my location automatically"; onClicked: { root.close(); root.turnOn() } }
        DialogButton { visible: root.settingOn; primary: true; label: "Got it"; onClicked: root.close() }
    }
}
