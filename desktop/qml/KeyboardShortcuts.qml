import QtQuick
import QtQuick.Controls.Basic

// Keyboard shortcuts (Ctrl+.), laid out as Teams desktop's dialog
// (measured at 1x): a 900 px card with the title, a filter box, and
// collapsible sections of action / key pills in two columns. It lists
// only the shortcuts OST implements, under Teams' section names.
Popup {
    id: root
    modal: true
    anchors.centerIn: parent
    width: Math.min(900, parent.width - 32)
    height: Math.min(583, parent.height - 32)
    padding: 0
    onOpened: { filter.text = ""; filter.forceActiveFocus() }
    background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }

    readonly property var sections: [
        { title: "General", items: [
            ["Show keyboard shortcuts", "Ctrl+."], ["Open Search", "Ctrl+E"],
            ["Go to a specific chat or channel", "Ctrl+G"], ["Start new chat", "Ctrl+N"],
            ["Open filter", "Ctrl+Shift+F"], ["Open Settings", "Ctrl+,"],
            ["Toggle pin window on top", "Ctrl+Shift+T"] ] },
        { title: "Navigation", items: [
            ["Go to compose box", "Ctrl+R"], ["Go back", "Alt+Left"], ["Go forward", "Alt+Right"],
            ["Open 1st app on app bar", "Ctrl+1"], ["Open 2nd app on app bar", "Ctrl+2"],
            ["Open 3rd app on app bar", "Ctrl+3"], ["Open 4th app on app bar", "Ctrl+4"],
            ["Open 5th app on app bar", "Ctrl+5"] ] },
        { title: "Compose", items: [
            ["Start new line", "Shift+Enter"], ["Attach file", "Alt+Shift+O"],
            ["Apply bold style", "Ctrl+B"], ["Apply italic style", "Ctrl+I"],
            ["Apply underline style", "Ctrl+U"], ["Apply strikethrough style", "Ctrl+Alt+X"],
            ["Undo", "Ctrl+Z"], ["Redo", "Ctrl+Y"], ["Cut", "Ctrl+X"], ["Copy", "Ctrl+C"],
            ["Paste", "Ctrl+V"], ["Select all", "Ctrl+A"] ] },
        { title: "Messaging", items: [
            ["Find in current chat or channel", "Ctrl+F"], ["Jump to newest message", "Ctrl+J"],
            ["Mark all as read", "Shift+Esc"], ["Clear all filters", "Ctrl+Alt+Z"],
            ["See all chat conversations", "Ctrl+Alt+C"], ["See all channel conversations", "Ctrl+Alt+A"],
            ["See all unread items", "Ctrl+Alt+U"], ["Toggle details pane", "Alt+P"],
            ["Open 1st tab on chat header", "Alt+1"], ["Open 2nd tab on chat header", "Alt+2"],
            ["Open 3rd tab on chat header", "Alt+3"], ["Open 4th tab on chat header", "Alt+4"],
            ["Open 5th tab on chat header", "Alt+5"] ] },
        { title: "Meetings, Calls and Calendar", items: [
            ["Toggle mute", "Ctrl+Shift+M"], ["Leave meeting or call", "Ctrl+Shift+H"],
            ["Start audio call", "Alt+Shift+A"], ["Accept audio call", "Ctrl+Shift+S"],
            ["Accept video call", "Ctrl+Shift+A"], ["Decline call", "Ctrl+Shift+D"],
            ["Schedule a meeting", "Alt+N"] ] }
    ]
    property var collapsed: ({})
    function matches(item) {
        const q = filter.text.trim().toLowerCase()
        return !q || item[0].toLowerCase().indexOf(q) >= 0 || item[1].toLowerCase().indexOf(q) >= 0
    }

    contentItem: Item {
        Text {
            x: 25; y: 32
            text: "Keyboard shortcuts"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
        }
        Rectangle {
            x: parent.width - 32 - 32; y: 24; width: 32; height: 32; radius: theme.radius
            color: xh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        // Filter shortcuts
        Rectangle {
            x: parent.width - 25 - width; y: 80
            width: 280; height: 32; radius: theme.radius
            color: theme.input
            border.color: filter.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: filter
                x: 34; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                Keys.onEscapePressed: text ? text = "" : root.close()
                Text { visible: !filter.text; text: "Filter shortcuts"; font: filter.font; color: theme.textSecondary }
                Accessible.name: "Filter shortcuts"
            }
        }
        Flickable {
            id: flick
            x: 25; y: 128
            width: parent.width - 50; height: parent.height - y - 16
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: col
                width: flick.width - 12
                spacing: 8
                Repeater {
                    model: root.sections
                    Column {
                        id: sec
                        required property var modelData
                        readonly property var shown: modelData.items.filter(i => root.matches(i))
                        readonly property bool open: root.collapsed[modelData.title] !== true
                        visible: shown.length > 0
                        width: col.width
                        Item {
                            width: parent.width; height: 44
                            FluentIcon {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                name: sec.open ? "chevron-down-16" : "chevron-right-12"; size: sec.open ? 16 : 12
                                color: theme.textStrong
                            }
                            Text {
                                x: 30; anchors.verticalCenter: parent.verticalCenter
                                text: sec.modelData.title
                                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                                color: theme.text
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    const c = Object.assign({}, root.collapsed)
                                    c[sec.modelData.title] = sec.open
                                    root.collapsed = c
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: sec.modelData.title + (sec.open ? ", expanded" : ", collapsed")
                        }
                        Grid {
                            visible: sec.open
                            columns: 2
                            columnSpacing: 24
                            Repeater {
                                model: sec.shown
                                Item {
                                    required property var modelData
                                    width: (sec.width - 24) / 2; height: 44
                                    Text {
                                        x: 18; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - pill.width - 36
                                        wrapMode: Text.Wrap; maximumLineCount: 2
                                        text: parent.modelData[0]
                                        font.family: theme.font; font.pixelSize: theme.base
                                        color: theme.text
                                    }
                                    Rectangle {
                                        id: pill
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 141; height: 32; radius: 16
                                        color: theme.searchFill
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.parent.modelData[1].split("+").join(" + ")
                                            font.family: theme.font; font.pixelSize: theme.base
                                            color: theme.text
                                        }
                                    }
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: modelData[0] + ": " + modelData[1]
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: root.sections.every(s => !s.items.some(i => root.matches(i)))
                    text: "No shortcuts match"
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
            }
        }
    }
}
