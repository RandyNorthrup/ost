import QtQuick
import QtQuick.Controls

// Teams' "Your custom greeting" (Settings ▸ Calls, measured on winpc
// 2026-11-14): 500 x 264.67, padding 24.67, radius 8. The 20/28 title,
// then an outlined text area (449.33 x 116.67, at 25.33, 71.33) with
// "Type your custom greeting message here", then Cancel and Save (96 x
// 31.33, 8 apart). Save is off until the text changes; an emptied text
// saves too (no greeting).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 500; height: 264.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string initial: ""
    signal saved(string text)
    readonly property bool ready: area.text !== initial && (area.text.trim().length > 0 || area.text === "")
    function show(text) { initial = text || ""; area.text = initial; open(); area.forceActiveFocus(); area.cursorPosition = area.length }

    Text {
        x: 24.67; y: 24.67; width: root.width - 49.33; height: 28
        verticalAlignment: Text.AlignVCenter
        text: "Your custom greeting"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Rectangle {
        x: 25.33; y: 71.33; width: 449.33; height: 116.67; radius: 4
        color: theme.surface
        border.color: theme.stroke; border.width: 0.67
        Rectangle {
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 2; height: area.activeFocus ? 2 : 0.67
            color: area.activeFocus ? theme.brand : theme.textSecondary
        }
        Flickable {
            id: flick
            x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
            contentHeight: area.contentHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: area
                width: flick.width
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                selectByMouse: true
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < flick.contentY) flick.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height) flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Type your custom greeting message here"
                Text {
                    visible: !area.text.length
                    text: "Type your custom greeting message here"
                    font: area.font; color: theme.textSecondary
                }
            }
        }
    }
    Row {
        x: root.width - 24.67 - width; y: root.height - 24.67 - 31.33; spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: !root.ready ? theme.pick("#F0F0F0", "#141414") : saveHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ready ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: saveHover; cursorShape: root.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (root.ready) { root.close(); root.saved(area.text) } }
            Accessible.role: Accessible.Button
            Accessible.name: "Save"
        }
    }
}
