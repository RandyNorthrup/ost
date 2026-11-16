import QtQuick
import QtQuick.Controls

// Settings and more ▸ Downloads. Teams shows WebView2's downloads hub here
// (edge://downloads-hub, measured on winpc 2026-11-15): a 360-wide flyout
// 13.33 from the window's right and 12 under the title bar (radius 8, the
// depth-16 shadow). The header: "Downloads" (16 semibold) 4 in and 8 down,
// then Open downloads folder, Search downloads, More options (Clear all
// download history) and Close (32 px buttons, 20 px glyphs) from 216, 36
// apart. Each download (344 wide, 8 in, 4 apart): the file's icon (20) 8
// in, its name (14/20, 2 lines) at 32, then "Open file" (12/16 link)
// under it, or for a file that is gone the name struck through and
// "Removed" (12/16, 56% black); on hover Open containing folder and Delete
// file (24 px) at the right. Empty: "When you download files from the web,
// they'll show up here." (14/20) 20 in. Search swaps the title for Back
// and a "Search all files" box. Clearing asks "Remove all download
// history?" first. The list is OST's own downloads (api::downloads).
Popup {
    id: root
    padding: 0
    width: 360
    height: Math.min(body.implicitHeight, parent ? parent.height - y - 12 : 600)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    readonly property var items: backend.downloadsJson ? JSON.parse(backend.downloadsJson) : []
    property bool searching: false
    property string query: ""
    readonly property var shown: items.filter(d => !query || d.name.toLowerCase().indexOf(query.toLowerCase()) >= 0)
    // 86% and 56% black on white, as opaque colours (icons take no alpha).
    readonly property color ink: theme.pick("#242424", "#DBDBDB", "#FFFFFF")
    readonly property color ink2: theme.pick("#707070", "#8F8F8F")
    readonly property color linkInk: theme.pick("#235CCF", "#7EB2FF", "#FFFF00")
    onOpened: { searching = false; query = ""; backend.downloadsAction("load", "") }
    background: FluentSurface { depth: 16; radius: 8; color: theme.surface }

    function typeIcon(name) {
        const t = String(name || "").split(".").pop().toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" || t === "csv" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" ? "one" : t === "loop" || t === "fluid" ? "loop" : t === "txt" ? "txt"
                : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-20"
    }

    component HubButton: Rectangle {
        id: hb
        property string icon
        property string label
        property real glyph: 20
        signal clicked()
        width: 32; height: 32; radius: 7.2
        color: hbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: hb.icon; size: hb.glyph; color: theme.onFill(hb, root.ink) }
        HoverHandler { id: hbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        ToolTip.visible: hbh.hovered; ToolTip.delay: 500; ToolTip.text: hb.label
        Accessible.role: Accessible.Button
        Accessible.name: hb.label
        Accessible.onPressAction: hb.clicked()
    }

    contentItem: Item {
        Column {
            id: body
            width: root.width
            // Header.
            Item {
                width: parent.width; height: 50
                Text {
                    visible: !root.searching
                    x: 16; y: 8; height: 33.33; verticalAlignment: Text.AlignVCenter
                    text: "Downloads"
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    color: root.ink
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                HubButton { visible: root.searching; x: 4; y: 8.67; icon: "arrow-left-20"; label: "Back"; onClicked: { root.searching = false; root.query = "" } }
                Rectangle {
                    visible: root.searching
                    x: 40; y: 9.33; width: 316; height: 30.67; radius: 7.2
                    color: theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1; color: theme.hc("#2169EB", "#1AEBFF"); visible: searchField.activeFocus }
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: root.ink2 }
                    TextInput {
                        id: searchField
                        x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                        onTextEdited: root.query = text
                        Text { visible: !searchField.text; text: "Search all files"; font: searchField.font; color: root.ink2 }
                        Keys.onEscapePressed: { root.searching = false; root.query = "" }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Search all files"
                    }
                }
                Row {
                    visible: !root.searching
                    x: 216; y: 9; spacing: 4
                    HubButton { icon: "folder-20"; label: "Open downloads folder"; onClicked: backend.downloadsAction("folder", "") }
                    HubButton { icon: "search-20"; label: "Search downloads"; onClicked: { root.searching = true; searchField.text = ""; searchField.forceActiveFocus() } }
                    HubButton { id: moreBtn; icon: "more-horizontal-20"; label: "More options"; onClicked: hubMenu.open() }
                    HubButton { icon: "dismiss-20"; label: "Close"; onClicked: root.close() }
                }
                // More options: Clear all download history.
                Popup {
                    id: hubMenu
                    x: 150; y: 41; width: 205; padding: 4
                    background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
                    contentItem: Rectangle {
                        id: hcFill1
                        implicitHeight: 36; radius: 4
                        color: clearHover.hovered ? theme.rowHover : "transparent"
                        FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "delete-20"; size: 20; color: theme.onFill(hcFill1, root.ink) }
                        Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: "Clear all download history"; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill1, root.ink) }
                        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { hubMenu.close(); clearConfirm.open() } }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: "Clear all download history"
                    }
                }
            }
            Text {
                visible: root.items.length === 0
                x: 20; width: 320
                text: "When you download files from the web, they'll show up here."
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.AlertMessage
                Accessible.name: text
            }
            Item { visible: root.items.length === 0; width: 1; height: 22 }
            Repeater {
                model: root.shown
                Item {
                    id: row
                    required property var modelData
                    width: root.width; height: card.height + 4
                    Rectangle {
                        id: card
                        x: 8; y: 4; width: 344
                        height: 8 + nameText.height + 4 + 16 + 12
                        radius: 4
                        color: rowHover.hovered ? theme.rowHover : "transparent"
                        readonly property bool actions: rowHover.hovered && row.modelData.exists
                        FluentIcon { x: 8; y: 8; name: root.typeIcon(row.modelData.name); size: 20 }
                        Text {
                            id: nameText
                            x: 32; y: 8; width: card.actions ? 236 : 304
                            text: row.modelData.name
                            wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.strikeout: !row.modelData.exists
                            color: theme.onFill(card, root.ink)
                        }
                        Text {
                            x: 32; y: nameText.y + nameText.height + 4
                            text: row.modelData.exists ? "Open file" : "Removed"
                            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                            font.underline: row.modelData.exists && openHover.hovered
                            color: theme.onFill(card, row.modelData.exists ? root.linkInk : root.ink2)
                            HoverHandler { id: openHover; enabled: row.modelData.exists; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: row.modelData.exists; onTapped: backend.downloadsAction("open", row.modelData.path) }
                            Accessible.role: row.modelData.exists ? Accessible.Link : Accessible.StaticText
                            Accessible.name: text
                        }
                        Row {
                            visible: card.actions
                            x: 272; anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            HubButton { width: 24; height: 24; radius: 4; icon: "folder-20"; label: "Open containing folder"; onClicked: backend.downloadsAction("folder", row.modelData.path) }
                            HubButton { width: 24; height: 24; radius: 4; icon: "delete-20"; label: "Delete file"; onClicked: backend.downloadsAction("delete", row.modelData.path) }
                        }
                        HoverHandler { id: rowHover }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: row.modelData.name + (row.modelData.exists ? "" : ", removed")
                    }
                }
            }
            Item { visible: root.items.length > 0; width: 1; height: 12 }
        }
    }

    // "Remove all download history?" (measured: 358 x 200, radius 8, 1 in
    // and 40 down; the title 20/28 at 23, 46 down; the text 14/20 56% black
    // 36 under it; Remove all (#2169EB) and Cancel (32 tall) at the bottom
    // right; Close at the top right).
    Popup {
        id: clearConfirm
        x: 1; y: 40; width: 358; height: 200; padding: 0
        modal: true
        background: FluentSurface { depth: 28; radius: 8; color: theme.surface }
        HubButton { x: 318; y: 6; icon: "dismiss-20"; label: "Close"; onClicked: clearConfirm.close() }
        Text {
            x: 22; y: 46; width: 314
            text: "Remove all download history?"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: root.ink
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            x: 22; y: 82; width: 322
            text: "You can still get to the files from the downloads folder."
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.ink2
        }
        Row {
            x: 358 - 16 - width; y: 148
            spacing: 8
            Rectangle {
                id: hcFill2
                width: 88.7; height: 32; radius: 4; color: removeHover.hovered ? theme.hc("#1D5FD6", "#1AEBFF") : theme.hc("#2169EB", "#FFFFFF")
                Text { anchors.centerIn: parent; text: "Remove all"; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill2, "#FFFFFF") }
                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { clearConfirm.close(); backend.downloadsAction("clear", "") } }
                Accessible.role: Accessible.Button
                Accessible.name: "Remove all"
            }
            Rectangle {
                id: hcFill3
                width: 66; height: 32; radius: 4; color: cancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill3, root.ink) }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: clearConfirm.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
        }
    }
}
