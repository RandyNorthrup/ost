import QtQuick

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

    // Teams desktop's rail, with its labels and shortcuts (Copilot left out).
    readonly property var apps: [
        { key: "activity", icon: "alert", label: "Activity", keys: "Ctrl+1" },
        { key: "chat", icon: "chat", label: "Chat", keys: "Ctrl+2" },
        { key: "calendar", icon: "calendar", label: "Calendar", keys: "Ctrl+3" },
        { key: "calls", icon: "call", label: "Calls", keys: "Ctrl+4" },
        { key: "onedrive", icon: "onedrive", label: "OneDrive", keys: "Ctrl+5" },
        { key: "add", icon: "add-app", label: "Store", keys: "" },
        { key: "more", icon: "more", label: "View more apps", keys: "" },
    ]

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: "#E6E6E6" }

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
                TapHandler { onTapped: root.current = modelData.key }
                ToolTipLabel { text: modelData.keys ? modelData.label + " (" + modelData.keys + ")" : modelData.label; shown: hover.hovered }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.keys ? modelData.label + " (" + modelData.keys + ")" : modelData.label
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
        color: theme.surface; z: 10
        border.color: theme.divider
        Text { id: tip; anchors.centerIn: parent; text: parent.text; color: theme.text; font.family: theme.font; font.pixelSize: theme.small }
    }
}
