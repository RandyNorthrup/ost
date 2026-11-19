import QtQuick
import QtQuick.Effects

// Give / take control's alerts.
// - The sharer's request (Teams' ufd_SharingIncomingControlRequest, an
//   alert window of its own while you share; measured 2026-11-16): a
//   280 x 91.3 #FAFAFA card, radius 8: "Presenter mode" (12 px #242424 at
//   12 / 6), "{name} is requesting control." (12 px #616161 at 12 / 28),
//   then Deny (outlined) and Give control (#5B5FC7) — 124 x 23.3 at y 56,
//   8 apart. "{name} has control." offers Take control the same way.
// - The viewer's notices ("You have been given screen control", "Your
//   request for control wasn't accepted.", "The person sharing took
//   control back.", "Screen control has been stopped") on Teams' in-call
//   alert card (CallAlert: 320 wide, 14/20, Dismiss at the end).
Item {
    id: root
    /// {kind: "request" | "has" | "note", text, mri}
    property var alert: null
    signal give()
    signal deny()
    signal takeBack()
    signal dismissed()
    visible: !!alert
    readonly property bool card: !!alert && (alert.kind === "request" || alert.kind === "has")
    width: card ? 280 : 320
    height: card ? 91.33 : note.height + 21.33
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: theme.shadowAmbient }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: theme.shadowKey }
    Rectangle { id: surface; anchors.fill: parent; radius: 8; color: root.card ? theme.pick("#FAFAFA", "#292929", "#000000") : theme.surface }
    // The sharer's card.
    Text {
        visible: root.card
        x: 12; y: 6; width: 256; height: 16; verticalAlignment: Text.AlignVCenter
        text: qsTr("Presenter mode")
        font.family: theme.font; font.pixelSize: 12; color: theme.text
    }
    Text {
        visible: root.card
        x: 12; y: 28; width: 256; height: 16; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.alert ? root.alert.text : ""
        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
    }
    Row {
        visible: root.card
        x: 12; y: 56
        spacing: 8
        CardButton { visible: !!root.alert && root.alert.kind === "request"; label: qsTr("Deny"); onClicked: root.deny() }
        CardButton { visible: !!root.alert && root.alert.kind === "request"; label: qsTr("Give control"); primary: true; onClicked: root.give() }
        CardButton { visible: !!root.alert && root.alert.kind === "has"; label: qsTr("Take control"); primary: true; onClicked: root.takeBack() }
    }
    // The viewer's notice.
    Text {
        id: note
        visible: !root.card
        x: 12.67; y: 10.67
        width: root.width - x - 44
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.alert ? root.alert.text : ""
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    Rectangle {
        id: hcFill1
        visible: !root.card
        x: root.width - 36; y: 6.67; width: 28; height: 28; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textSecondary) }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Dismiss")
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.alert ? root.alert.text : ""

    component CardButton: Rectangle {
        id: cb
        property string label
        property bool primary: false
        signal clicked()
        width: 124; height: 23.33; radius: 4
        color: primary ? (cbHover.hovered ? theme.pick("#4F52B2", "#4F52B2", "#1AEBFF") : theme.pick("#5B5FC7", "#5B5FC7", "#1AEBFF"))
                       : (cbHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.pick("#FFFFFF", "#292929", "#000000"))
        border.width: primary ? 0 : 0.67
        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Text {
            anchors.centerIn: parent
            text: cb.label
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: cb.primary ? "#FFFFFF" : theme.text
        }
        HoverHandler { id: cbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: cb.label
        Accessible.onPressAction: cb.clicked()
    }
}
