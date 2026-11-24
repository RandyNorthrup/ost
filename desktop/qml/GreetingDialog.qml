import QtQuick
import QtQuick.Controls

// Teams' "Your custom greeting" (Settings ▸ Calls, measured on winpc
// 2026-11-14): 500 x 264.67, padding 24.67, radius 8. The 20/28 title,
// then an outlined text area (449.33 x 116.67, at 25.33, 71.33) with
// "Type your custom greeting message here", then Cancel and Save (96 x
// 31.33, 8 apart). Save is off until the text changes; an emptied text
// saves too (no greeting).
// Intelligent call delegation's "Customize greeting message" is the same
// dialog (measured on winpc 2026-11-21): 700 x 264.67, padding 24, the
// area 650.67 x 120 at 24.67, 70.67, its placeholder Teams' example with
// your first name, at most 200 characters (trimmed), saved trimmed.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    property string title: qsTr("Your custom greeting")
    property string placeholder: qsTr("Type your custom greeting message here")
    /// The trimmed text's limit (0: none) and the line shown past it.
    property int maxLength: 0
    property string lengthError: ""
    property real boxWidth: 449.33
    property real boxHeight: 116.67
    property real boxX: 25.33
    property real boxY: 71.33
    property real pad: 24.67
    width: boxWidth + 2 * boxX; height: 264.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    property string initial: ""
    signal saved(string text)
    readonly property bool tooLong: maxLength > 0 && area.text.trim().length > maxLength
    readonly property bool ready: !tooLong && (maxLength > 0 ? area.text.trim() !== initial.trim() : area.text !== initial && (area.text.trim().length > 0 || area.text === ""))
    function show(text) { initial = text || ""; area.text = initial; open(); area.forceActiveFocus(); area.cursorPosition = area.length }

    Text {
        x: root.pad; y: root.pad; width: root.width - 2 * root.pad; height: 28
        verticalAlignment: Text.AlignVCenter
        text: root.title
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Rectangle {
        id: box
        x: root.boxX; y: root.boxY; width: root.boxWidth; height: root.boxHeight; radius: 4
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
                Accessible.name: root.title
                Accessible.description: root.tooLong ? root.lengthError : ""
                Text {
                    visible: !area.text.length
                    width: flick.width
                    wrapMode: Text.Wrap
                    text: root.placeholder
                    font: area.font; color: theme.textSecondary
                }
            }
        }
    }
    Text {
        visible: root.tooLong
        x: box.x; y: box.y + box.height + 4; width: box.width
        text: root.lengthError
        font.family: theme.font; font.pixelSize: 12; color: theme.danger
    }
    Row {
        x: root.width - root.pad - width; y: root.height - root.pad - 31.33; spacing: 8
        Rectangle {
            id: hcFill1
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.text) }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Cancel")
        }
        Rectangle {
            id: hcFill2
            width: 96; height: 31.33; radius: 4
            color: !root.ready ? theme.pick("#F0F0F0", "#141414", "#000000") : saveHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, root.ready ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
            HoverHandler { id: saveHover; cursorShape: root.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: if (root.ready) { root.close(); root.saved(root.maxLength > 0 ? area.text.trim() : area.text) } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Save")
        }
    }
}
