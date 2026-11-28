import QtQuick
import QtQuick.Controls.Basic

// A row's or card's pick while messages are being picked to forward
// (Teams' multiselect-list-item-wrapper, 763654): over the whole item, a
// click anywhere toggles it; the 16 px checkbox (radius 2, a 1 px #616161
// border, brand and a check once picked, #E0E0E0 when it can't be picked)
// `checkX` in, centred on it; a blocked one says why in a tooltip that
// follows the pointer (15 under it). In a channel's posts and post view the
// box sits 13 in from the card's edge (Teams desktop 26304, 2026-11-27).
Item {
    id: root
    /// The ForwardSelection.
    property var selection: null
    property var message: null
    property real checkX: 13
    readonly property string reason: selection && selection.selecting ? selection.reason(message) : "none"
    readonly property bool checked: !!selection && !!message && selection.selectedIds.indexOf(message.id) >= 0
    visible: !!selection && selection.selecting && reason !== "none"
    z: 20
    Rectangle {
        x: root.checkX; y: (root.height - height) / 2
        width: 16; height: 16; radius: 2
        color: root.checked ? theme.brand : "transparent"
        border.width: 1; border.color: root.checked ? theme.brand : (root.reason !== "" ? theme.pick("#E0E0E0", "#3D3D3D", theme.disabled) : theme.textSecondary)
        FluentIcon { visible: root.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
    }
    // (A MouseArea, not a TapHandler: it takes the click, so the links,
    // pictures and meeting cards under it don't act while picking.)
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.reason === "" || root.checked ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: m => { if (m.button === Qt.LeftButton) root.selection.toggle(root.message) }
        onWheel: w => { w.accepted = false }
    }
    ToolTip {
        visible: hover.containsMouse && root.reason !== "" && !root.checked; delay: 300
        x: hover.mouseX + 15; y: hover.mouseY + 15; padding: 8
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Text { text: root.reason; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
    }
    Accessible.role: Accessible.CheckBox
    Accessible.name: qsTr("Select message")
    Accessible.description: root.selection ? qsTr("%1 selected").arg(root.selection.selectedIds.length) : ""
    Accessible.checked: checked
    Accessible.onToggleAction: root.selection.toggle(root.message)
}
