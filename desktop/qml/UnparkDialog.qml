import QtQuick
import QtQuick.Controls.Basic

// Pick up a parked call (Teams' unpark-call dialog, from its
// `unpark-call-dialog` bundle): a small notification dialog with a code
// field and Cancel / Pick up. Strings from the bundle:
// - Title "Pick up a parked call" (`unpark_call_enter_pickup_code`).
// - Field placeholder / aria "Enter park code" (`aria_label_text_for_park_code`).
// - "Cancel" (secondary) and "Pick up" (primary, disabled while the field
//   is empty; `unpark_call_pickup_button_text`), which calls
//   `startUnparkCall(code, ParkContext.Team)`.
// OST retrieves with `backend.unparkCall(code)` (a call to the team park
// server, 4:*11, carrying the pickup code).
Popup {
    id: dlg

    function start() { field.text = ""; open(); Qt.callLater(() => field.forceActiveFocus()) }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 360; padding: 24
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    contentItem: Column {
        spacing: 16
        Text {
            text: "Pick up a parked call"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
        }
        Rectangle {
            width: parent.width; height: 32; radius: 4
            color: theme.input; border.color: field.activeFocus ? theme.brand : theme.stroke
            TextField {
                id: field
                anchors.fill: parent; leftPadding: 12; rightPadding: 12
                verticalAlignment: Text.AlignVCenter
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                placeholderText: "Enter park code"
                placeholderTextColor: theme.disabled
                background: null
                inputMethodHints: Qt.ImhDigitsOnly
                Accessible.name: "Enter park code"
                onAccepted: if (text.trim()) pickUp.go()
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            component Btn: Rectangle {
                id: btn
                property string label: ""
                property bool primary: false
                property bool enabled: true
                signal go()
                width: Math.max(96, lbl.implicitWidth + 24); height: 31.33; radius: theme.radius
                opacity: enabled ? 1 : 0.5
                color: primary ? (bh.hovered && enabled ? theme.brandHover : theme.brand)
                               : (bh.hovered ? theme.rowHover : theme.input)
                border.color: primary ? "transparent" : theme.stroke
                Text {
                    id: lbl; anchors.centerIn: parent; text: btn.label
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: btn.primary ? "white" : theme.text
                }
                HoverHandler { id: bh; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: btn.enabled; onTapped: btn.go() }
                Accessible.role: Accessible.Button
                Accessible.name: btn.label
            }
            Btn { label: "Cancel"; onGo: dlg.close() }
            Btn {
                id: pickUp
                label: "Pick up"; primary: true; enabled: field.text.trim().length > 0
                onGo: { backend.unparkCall(field.text.trim()); dlg.close() }
            }
        }
    }
}
