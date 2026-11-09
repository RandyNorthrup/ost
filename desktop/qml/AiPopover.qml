import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' "Meeting AI" menu (calling-agents-control-ubar-indicator-popover,
// opened from the bar's AI indicator; measured in Teams in a meeting,
// 2026-11-08): a Fluent popover 313.33 wide, padding 16 (+0.67 border),
// with a menu group 280 wide — "Meeting AI" (12/20, 600, #616161, a 32 px
// header with 8 px padding), the read-only note "You don't have access to
// AI in this meeting." (36 tall, #F5F5F5 with a #D1D1D1 hairline, 12/16
// text 12 px in), then Copilot, Facilitator and Intelligent recap as
// switch rows (32 tall, padding 6, a 20 px glyph, the label at 32, a
// 40 x 20 switch 4 px from the end).
//
// Teams shows the note and keeps the switches disabled for people without
// a Copilot licence (showReadOnlyMeetingAiControls); OST offers no Copilot
// of its own, so it is always in that state. The switches still say what
// runs: Copilot while the meeting's transcript runs with AI enabled,
// Facilitator while it runs with the Facilitator enabled, Intelligent
// recap with Copilot.
Popup {
    id: root
    property bool aiOn: false
    property bool facilitatorEnabled: false
    parent: Overlay.overlay
    padding: 0
    width: 313.33
    height: col.implicitHeight + 33.33
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }

    readonly property bool copilotChecked: aiOn
    readonly property bool facilitatorChecked: aiOn && facilitatorEnabled

    component SwitchRow: Item {
        id: row
        property string icon
        property real iconSize: 20
        property string label
        property bool checked: false
        width: 280; height: 32
        FluentIcon { x: 6; y: 6; name: row.icon; size: 20; color: theme.disabled }
        Text {
            x: 32; y: 6; width: 192; height: 20
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.label
            font.family: theme.font; font.pixelSize: 14
            color: theme.disabled
        }
        // Fluent's MenuItemSwitch indicator, disabled (Teams'
        // disabledMenuItemSwitchIndicator): #F0F0F0 with a #E0E0E0 hairline
        // and the 14.4 px thumb #BDBDBD, at the start (its 18 px box 0.67
        // in) or, checked, the end (20.67 in).
        Rectangle {
            x: 230; y: 6; width: 40; height: 20; radius: 10
            color: theme.bgDisabled
            border.width: 1 / Screen.devicePixelRatio
            border.color: theme.divider
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                x: (row.checked ? 20.67 : 0.67) + 9 - 7.2
                anchors.verticalCenter: parent.verticalCenter
                color: theme.disabled
            }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: row.label
        Accessible.checkable: true
        Accessible.checked: row.checked
    }

    Column {
        id: col
        x: 16.67; y: 16.67; width: 280
        spacing: 4
        Text {
            width: 280; height: 32
            leftPadding: 8; rightPadding: 8
            verticalAlignment: Text.AlignVCenter
            text: "Meeting AI"
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: theme.textSecondary
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            width: 280; height: 36; radius: 4
            color: theme.pane
            border.width: 1 / Screen.devicePixelRatio; border.color: theme.stroke
            Text {
                x: 12.67; anchors.verticalCenter: parent.verticalCenter
                width: 280 - 25.33
                elide: Text.ElideRight
                text: "You don't have access to AI in this meeting."
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: "You don't have access to AI in this meeting."
        }
        Column {
            width: 280
            SwitchRow { icon: "ai-copilot"; label: "Copilot"; checked: root.copilotChecked }
            SwitchRow { icon: "ai-facilitator"; label: "Facilitator"; checked: root.facilitatorChecked }
            SwitchRow { icon: "ai-recap"; label: "Intelligent recap"; checked: root.copilotChecked }
        }
    }
}
