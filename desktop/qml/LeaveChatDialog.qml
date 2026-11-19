import QtQuick
import QtQuick.Controls

// Teams' "Leave this chat?" for a group chat (measured on winpc
// 2026-11-16, OST group test, then Cancel): 600 x 221.7, radius 8,
// padding 25; the title 20/28 semibold; "This chat will stay in your list
// but you can hide it anytime or remove chat history now." 14/20 at 71;
// a "Remove chat history" checkbox (16 at 33, 111; its label 14/20
// NeutralForeground3 at 61, 109; "This will remove the chat from your
// list and search. It affects you only." 12/16 at 61, 134); Cancel and
// Leave (96 x 31.3) at 375 / 479, 166. Leaving keeps the chat in your list
// (Teams' words); ticked, its history goes too.
Popup {
    id: root
    signal confirmed(bool removeHistory)
    property bool removeHistory: false
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 221.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    onAboutToShow: removeHistory = false
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    contentItem: Item {
        Text {
            x: 25; y: 25; width: 551
            text: qsTr("Leave this chat?")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            x: 25; y: 71; width: 551
            wrapMode: Text.Wrap
            text: qsTr("This chat will stay in your list but you can hide it anytime or remove chat history now.")
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item {
            id: check
            x: 25; y: 103; width: 551; height: 51
            Rectangle {
                id: box
                x: 8; y: 8; width: 16; height: 16; radius: 2
                color: root.removeHistory ? theme.brand : "transparent"
                border.color: root.removeHistory ? theme.brand : theme.textSecondary; border.width: 0.67
                FluentIcon { visible: root.removeHistory; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: theme.onFill(box, "white") }
            }
            Text {
                x: 36; y: 6
                text: qsTr("Remove chat history")
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: root.removeHistory ? theme.text : theme.textSecondary
            }
            Text {
                x: 36; y: 31
                text: qsTr("This will remove the chat from your list and search. It affects you only.")
                font.family: theme.font; font.pixelSize: 12
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.textSecondary
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.removeHistory = !root.removeHistory }
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.removeHistory
            Accessible.name: qsTr("Remove chat history")
        }
        DialogButton { x: 375; y: 166; label: qsTr("Cancel"); onClicked: root.close() }
        DialogButton { x: 479; y: 166; label: qsTr("Leave"); primary: true; onClicked: { root.close(); root.confirmed(root.removeHistory) } }
    }
    component DialogButton: Rectangle {
        id: btn
        property string label
        property bool primary: false
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
        border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
        Text { anchors.centerIn: parent; text: btn.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(btn, btn.primary ? theme.textOnBrand : theme.text) }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
