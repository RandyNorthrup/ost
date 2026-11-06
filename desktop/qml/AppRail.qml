import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Left app bar: icon-only buttons on a 44 px pitch, selected one marked by a
// 3 px brand bar and a filled brand-coloured icon.
Rectangle {
    id: root
    property string current: "chat"
    /// "Collapse app bar": the rail folds away, as in Teams.
    property bool collapsed: false
    property int unreadChats: 0
    property int unreadActivity: 0
    color: theme.chrome
    width: collapsed ? 0 : theme.railWidth
    visible: !collapsed
    clip: true

    // Apps opened from "View more apps" join the rail, as in Teams.
    property var opened: []
    readonly property var extraApps: [
        { key: "planner", icon: "clipboard-task-list-ltr-24", label: "Planner", keys: "" }
    ]
    // Teams desktop's rail, with its labels and shortcuts (Copilot left out).
    readonly property var apps: [
        { key: "activity", icon: "alert", label: "Activity", keys: "Ctrl+1" },
        { key: "chat", icon: "chat", label: "Chat", keys: "Ctrl+2" },
        { key: "calendar", icon: "calendar", label: "Calendar", keys: "Ctrl+3" },
        { key: "calls", icon: "call", label: "Calls", keys: "Ctrl+4" },
        { key: "onedrive", icon: "onedrive", label: "OneDrive", keys: "Ctrl+5" },
    ].concat(extraApps.filter(a => opened.indexOf(a.key) >= 0 || current === a.key)).concat([
        { key: "add", icon: "add-app", label: "Store", keys: "" },
        { key: "more", icon: "more", label: "View more apps", keys: "" },
    ])
    function openApp(key) {
        if (opened.indexOf(key) < 0) opened = opened.concat([key])
        current = key
    }

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    Column {
        y: 0
        width: parent.width
        spacing: 4
        Repeater {
            model: root.apps
            delegate: Item {
                required property var modelData
                readonly property bool selected: root.current === modelData.key
                width: root.width; height: 40
                Rectangle {
                    visible: parent.selected
                    width: 3; height: 32; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.brand
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: theme.radius
                    color: hover.hovered && !parent.selected ? theme.hover : "transparent"
                }
                FluentIcon {
                    anchors.centerIn: parent
                    size: 24
                    name: parent.selected ? modelData.icon + "-filled" : modelData.icon
                    color: parent.selected ? theme.brand : theme.icon
                }
                Rectangle {
                    readonly property int count: modelData.key === "chat" ? root.unreadChats
                        : modelData.key === "activity" ? root.unreadActivity : 0
                    visible: count > 0
                    x: parent.width / 2 + 4; y: 6
                    width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
                    color: theme.badge
                    border.color: theme.chrome; border.width: 1
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: parent.count
                        color: "white"
                        font.family: theme.font; font.pixelSize: theme.caption; font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: modelData.key === "more" ? moreApps.open() : root.current = modelData.key }
                ToolTipLabel { text: modelData.keys ? modelData.label + " (" + modelData.keys + ")" : modelData.label; shown: hover.hovered }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.keys ? modelData.label + " (" + modelData.keys + ")" : modelData.label
            }
        }
    }

    // View more apps: Teams' flyout with a search box and the apps. Planner
    // opens in OST; Whiteboard, Clipchamp and Help are web apps (Teams
    // embeds them), so they open in the browser.
    Popup {
        id: moreApps
        parent: root.Window.contentItem
        x: root.width + 2; y: 92
        width: 300; padding: 8
        onOpened: { appSearch.text = ""; appSearch.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        readonly property var all: [
            { key: "planner", label: "Planner", icon: "clipboard-task-list-ltr-24-filled", color: theme.brand },
            { url: "https://whiteboard.cloud.microsoft/", label: "Whiteboard", icon: "board-20", color: "#0F6CBD" },
            { url: "https://app.clipchamp.com/", label: "Clipchamp", icon: "video", color: "#8764B8" },
            { url: "https://support.microsoft.com/teams", label: "Help", icon: "question-circle-20", color: theme.textStrong }
        ]
        contentItem: Column {
            spacing: 2
            Rectangle {
                width: 284; height: 32; radius: theme.radius
                color: theme.input; border.color: appSearch.activeFocus ? theme.brand : theme.stroke
                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
                TextInput {
                    id: appSearch
                    x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !appSearch.text; text: "Search apps"; color: theme.textSecondary; font: appSearch.font }
                    Keys.onEscapePressed: moreApps.close()
                    Accessible.name: "Search apps"
                }
            }
            Item { width: 1; height: 4 }
            Repeater {
                model: moreApps.all.filter(a => !appSearch.text || a.label.toLowerCase().indexOf(appSearch.text.toLowerCase()) >= 0)
                Rectangle {
                    required property var modelData
                    width: 284; height: 40; radius: theme.radius
                    color: ah.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 22; color: modelData.color }
                    Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            moreApps.close()
                            if (modelData.key) root.openApp(modelData.key)
                            else Qt.openUrlExternally(modelData.url)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
    }

    // Teams' tooltip: white, hairline border, 12 px text, beside the button.
    component ToolTipLabel: Rectangle {
        property string text
        property bool shown
        visible: shown
        x: parent.width - 6; y: parent.height / 2 - height / 2 - 14
        width: tip.implicitWidth + 22; height: 26; radius: theme.radius
        color: theme.menu; z: 10
        border.color: theme.divider
        Text { id: tip; anchors.centerIn: parent; text: parent.text; color: theme.text; font.family: theme.font; font.pixelSize: theme.small }
    }
}
