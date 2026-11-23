import QtQuick
import QtQuick.Controls.Basic

// Teams' code block (code-block-editor-deserialized), in a message: a 32 px
// header (code icon, the language 12/16 #616161, Copy), then the code in
// Cascadia Mono 14/24 with line numbers, 8/12 in; rounded 8.
Item {
    id: codeCard
    /// The flow's code part ({name, lang, text}).
    property var code: ({})
    readonly property var lines: String(code.text || "").split("\n")
    implicitHeight: 32 - 0.8 + codeBody.height
    Rectangle {
        width: parent.width; height: 40
        radius: 8
        color: theme.surface
        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        FluentIcon { x: 10.7; y: 6; name: "code-block-20"; size: 20; color: theme.textSecondary }
        Text {
            x: 36.7; y: 8.7; height: 16; verticalAlignment: Text.AlignVCenter
            text: codeCard.code.name || qsTr("Plain Text")
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
        Rectangle {
            id: hcFill6
            x: parent.width - 6.2 - 24; y: 5.5; width: 24; height: 23.3; radius: 4
            color: copyHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "copy-20"; size: 20; color: theme.onFill(hcFill6, theme.textStrong) }
            HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.copyText(codeCard.code.text || "") }
            ToolTip.visible: copyHover.hovered
            ToolTip.text: qsTr("Copy")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Copy code")
        }
    }
    Rectangle {
        id: codeBody
        y: 32 - 0.8
        width: parent.width
        height: 8 + 4 + codeCard.lines.length * 24 + 4 + 8 + 1.3
        radius: 8
        color: theme.surface
        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        // Square top corners where it meets the header.
        Rectangle { x: 0.67; y: 0.67; width: parent.width - 1.3; height: 8; color: theme.surface }
        Column {
            x: 12; y: 12
            Repeater {
                model: codeCard.lines
                Item {
                    required property var modelData
                    required property int index
                    width: codeBody.width - 24; height: 24
                    Text {
                        width: 30; height: 24; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                        text: index + 1
                        font.family: theme.mono; font.pixelSize: 14; color: theme.pick("#8A8886", "#ADADAD", "#FFFFFF")
                    }
                    Text {
                        x: 42.7; width: parent.width - 42.7; height: 24; verticalAlignment: Text.AlignVCenter
                        text: parent.modelData
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: theme.mono; font.pixelSize: 14; color: theme.text
                    }
                }
            }
        }
    }
}
