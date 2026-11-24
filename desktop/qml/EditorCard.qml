import QtQuick
import QtQuick.Controls.Basic

// Teams' Editor card (measured on winpc 2026-11-14), opened by clicking a
// squiggled word in the compose box: 300 wide, radius 8, Fluent's shadow.
// - The category ("Spelling", 12 px semibold) padded 10 / 16 / 8.
// - Each suggestion is a 36 px row, 14 px semibold, padded 16.
// - The footer (padding 4 / 8) has 37.3 px icon buttons (Ignore all, Add
//   to Dictionary, More options) and the Editor mark at its right.
// More options: Editor settings... and Manage languages....
Popup {
    id: card
    /// The critique: {id, start, length, category, word, suggestions}.
    property var critique: null
    signal picked(string suggestion)
    signal ignoreAll()
    signal addToDictionary()
    width: 300
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
    contentItem: Column {
        Item {
            width: card.width; height: 38
            Text {
                x: 16; y: 10; width: parent.width - 32
                text: card.critique ? card.critique.category : ""
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
        Repeater {
            model: card.critique ? card.critique.suggestions : []
            Rectangle {
                id: hcFill1
                required property string modelData
                width: card.width; height: 36; radius: 4
                color: sugHover.hovered ? theme.menuHover : "transparent"
                Text {
                    x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32
                    elide: Text.ElideRight
                    text: parent.modelData
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill1, theme.text)
                }
                HoverHandler { id: sugHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { card.close(); card.picked(parent.modelData) } }
                Accessible.role: Accessible.Button
                Accessible.name: modelData
                Accessible.onPressAction: { card.close(); card.picked(modelData) }
            }
        }
        Item {
            width: card.width; height: 45.3
            Row {
                x: 8; y: 4
                Repeater {
                    model: [{ key: "ignore", icon: "prohibited-20", label: qsTr("Ignore all") }, { key: "dict", icon: "book-add-20", label: qsTr("Add to Dictionary") }, { key: "more", icon: "more-horizontal-20", label: qsTr("More options") }]
                    Rectangle {
                        id: footBtn
                        required property var modelData
                        width: 37.3; height: 37.3; radius: 4
                        color: footHover.hovered || (modelData.key === "more" && moreMenu.opened) ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: footBtn.modelData.icon; size: 20; color: theme.onFill(footBtn, theme.text) }
                        HoverHandler { id: footHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: card.act(footBtn.modelData.key, footBtn) }
                        ToolTip {
                            visible: footHover.hovered && !moreMenu.opened; delay: 500
                            y: -height - 4; padding: 8
                            background: FluentSurface { depth: 16; radius: 4 }
                            contentItem: Text { text: footBtn.modelData.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.onPressAction: card.act(modelData.key, footBtn)
                    }
                }
            }
            // The Editor mark (Fluent's pen sparkle standing in for the
            // Editor SDK's own artwork), 16 px, 6 in from a 28 px box.
            FluentIcon { x: card.width - 8 - 28 + 6; y: 4 + 4.7 + 6; name: "pen-sparkle-16"; size: 16; color: theme.text }
        }
    }
    function act(key, from) {
        if (key === "ignore") { close(); ignoreAll() }
        else if (key === "dict") { close(); addToDictionary() }
        else { moreMenu.x = from.x + 8; moreMenu.y = from.y - moreMenu.implicitHeight + 4; moreMenu.open() }
    }
    Popup {
        id: moreMenu
        padding: 4
        width: 171.8 + 8
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: Column {
            Repeater {
                model: [{ key: "settings", icon: "settings-20", label: qsTr("Editor settings...") }, { key: "languages", icon: "local-language-20", label: qsTr("Manage languages...") }]
                Rectangle {
                    id: hcFill2
                    required property var modelData
                    width: 171.8; height: 37.3; radius: 4
                    color: mHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: parent.modelData.icon; size: 20; color: theme.onFill(hcFill2, theme.text) }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill2, theme.text) }
                    HoverHandler { id: mHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { moreMenu.close(); card.close(); window.showEditorSettings(parent.modelData.key === "languages") } }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }
    }
}
