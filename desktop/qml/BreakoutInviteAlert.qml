import QtQuick
import QtQuick.Effects

// Teams' breakout room invite (calling alert `ufd_BreakoutRoomInvite`,
// breakoutRoomParticipantsService handleConfirmationDialog), shown when a
// room you're assigned to opens and the organizer doesn't move people
// automatically. Measured in Teams desktop on winpc, 2026-11-18 (DOM, the
// call window 1280 x 680): a 320 x 116.67 card centred over the stage, 8
// below its top (10.67 under the bar); NeutralBackground2 (#FAFAFA) with a
// 0.67 NeutralStroke3 (#F0F0F0) border, radius 8, shadow 4 (0 0.6 1.8 0.11,
// 0 3.2 7.2 0.13), no Dismiss. "Join breakout room?" (12/20 regular,
// NeutralForeground1) at 12 in; "You've been assigned to "Room 1"." (14/20,
// NeutralForeground3) 8 below, wrapping in 296.67; then, 4 below, Later
// (white, 0.67 NeutralStroke1) and Join room (brand), 143.33 x 31.33 each,
// 8 apart, 14/20 semibold, radius 4, 12 from the bottom.
Item {
    id: root
    property string roomName
    signal later()
    signal join()
    width: 320
    height: buttons.y + 31.33 + 12.67
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: theme.shadowAmbient }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: theme.shadowKey }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 8
        color: theme.quoteFill
        border.color: theme.quoteBorder; border.width: 0.67
    }
    Text {
        id: title
        x: 12.67; y: 12.67; width: root.width - 25.33; height: 20
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: qsTr("Join breakout room?")
        font.family: theme.font; font.pixelSize: 12
        color: theme.text
    }
    Text {
        id: body
        x: 12.67; y: 40.67; width: 296.67
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: qsTr("You've been assigned to \"%1\".").arg(root.roomName)
        font.family: theme.font; font.pixelSize: 14
        color: theme.textSecondary
    }
    Row {
        id: buttons
        x: 12.67; y: body.y + body.height + 12
        spacing: 8
        component InviteButton: Rectangle {
            id: ib
            property string label
            property bool primary: false
            signal clicked()
            width: 143.33; height: 31.33; radius: 4
            color: primary ? (ibHover.hovered ? theme.brandHover : theme.brandFill)
                           : (ibHover.hovered ? theme.menuHover : theme.surface)
            border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
            Text {
                anchors.centerIn: parent
                text: ib.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.onFill(ib, ib.primary ? theme.textOnBrand : theme.text)
            }
            HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ib.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: ib.label
            Accessible.onPressAction: ib.clicked()
        }
        InviteButton { label: qsTr("Later"); onClicked: root.later() }
        InviteButton { label: qsTr("Join room"); primary: true; onClicked: root.join() }
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: title.text + " " + body.text
}
