import QtQuick

// The device store's quantity dropdown (measured on winpc 2026-11-20): 112
// x 31.3, #F5F5F5, radius 4, the number 14/20 at 12 and a 20 px chevron;
// its list offers 1 to 9 and "10+", which turns it into a number box
// ("quantity input box").
Rectangle {
    id: root
    property int value: 1
    property bool typing: false
    signal picked(int value)
    width: 112; height: 31.3; radius: 4
    color: theme.inputFilled
    Text {
        visible: !root.typing
        x: 12; anchors.verticalCenter: parent.verticalCenter
        text: root.value; font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    TextInput {
        id: input
        visible: root.typing
        x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
        font.family: theme.font; font.pixelSize: 14; color: theme.text
        validator: IntValidator { bottom: 1; top: 999 }
        onEditingFinished: { const n = parseInt(text); if (n > 0) root.picked(n) }
        Accessible.role: Accessible.EditableText; Accessible.name: qsTr("quantity input box")
    }
    FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textStrong }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: !root.typing; onTapped: { list.parent = root; list.y = root.height + 2; list.open() } }
    MenuPopup {
        id: list
        items: [1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => ({ label: String(n) })).concat([{ label: qsTr("10+") }])
        onPicked: i => {
            if (i < 9) { root.typing = false; root.picked(i + 1) }
            else { root.typing = true; input.text = "10"; input.forceActiveFocus(); input.selectAll() }
        }
    }
    Accessible.role: Accessible.ComboBox; Accessible.name: qsTr("quantity dropdown selector")
}
