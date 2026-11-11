import QtQuick

// Teams' call retry screen (calling-retry-screen): what the meeting window
// shows when the service ended the call for a reason, measured on winpc
// 2026-11-10 (denied from the lobby, CSS px in a 1266 x 673 window):
// - the page #F5F5F5; one column centred in the window under its title
//   bar: the alert (the title line, then the description 15 under it),
//   30 px, then the buttons;
// - the title line: the icon (24 px, Fluent regular) 15 px before the
//   title, 18/600 #252423, line 25.7;
// - the description (removed from the meeting, measured too): 14/400
//   #252423, line 20;
// - the buttons 8 apart: Dismiss (96 min x 31.3, padding 5/12, 14/600
//   #242424, a 0.67 px #D1D1D1 border, radius 4, transparent), then the
//   retry button when the call can be rejoined (Rejoin: the same size,
//   #5B5FC7, white).
// The texts and buttons per reason are Teams' (calling.* strings):
// - deniedFromLobby: prohibited icon, "Sorry, but you were denied access
//   to the meeting.", Dismiss;
// - notAdmittedForLongTime: "Sorry, no one has responded to your request
//   to join. Please try again.", Rejoin and Dismiss;
// - removed: "Removed from the meeting", "Someone just removed you from
//   the meeting. You can try to rejoin.", Rejoin and Dismiss.
Rectangle {
    id: rs
    /// "deniedFromLobby", "notAdmittedForLongTime" or "removed".
    property string reason: ""
    signal retry()
    signal dismiss()
    color: theme.pane

    readonly property var spec: ({
        deniedFromLobby: { icon: "prohibited-20", title: "Sorry, but you were denied access to the meeting.", description: "", retry: "" },
        notAdmittedForLongTime: { icon: "", title: "Sorry, no one has responded to your request to join. Please try again.", description: "", retry: "Rejoin" },
        removed: { icon: "", title: "Removed from the meeting", description: "Someone just removed you from the meeting. You can try to rejoin.", retry: "Rejoin" }
    })[reason] || { icon: "", title: "", description: "", retry: "" }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, implicitWidth)
        spacing: 30
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 15
                FluentIcon {
                    visible: rs.spec.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    name: rs.spec.icon; size: 24; color: theme.text
                }
                Text {
                    id: title
                    text: rs.spec.title
                    font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                    lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    wrapMode: Text.Wrap
                    width: Math.min(implicitWidth, rs.width - 80)
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
            }
            Text {
                visible: text !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: rs.spec.description
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
                horizontalAlignment: Text.AlignHCenter
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            RetryButton { text: "Dismiss"; onClicked: rs.dismiss() }
            RetryButton { visible: rs.spec.retry !== ""; text: rs.spec.retry; primary: true; onClicked: rs.retry() }
        }
    }

    component RetryButton: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, label.implicitWidth + 24); height: 31.3; radius: 4
        color: primary ? (h.hovered ? theme.brandHover : theme.brandFill) : (h.hovered ? theme.menuHover : "transparent")
        border.color: primary ? "transparent" : theme.pick("#D1D1D1", "#666666"); border.width: 0.67
        Text {
            id: label
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: btn.primary ? theme.textOnBrand : theme.pick("#242424", "#FFFFFF")
        }
        HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
