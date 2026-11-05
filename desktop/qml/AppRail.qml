import QtQuick

// Left app bar: icon-only buttons on a 44 px pitch, selected one marked by a
// 3 px brand bar and a filled brand-coloured icon.
Rectangle {
    id: root
    property string current: "chat"
    /// "Collapse app bar": the rail folds away, as in Teams.
    property bool collapsed: false
    property int unreadChats: 0
    color: theme.chrome
    width: collapsed ? 0 : theme.railWidth
    visible: !collapsed
    clip: true

    readonly property var apps: [
        { key: "activity", icon: "alert", label: "Activity" },
        { key: "chat", icon: "chat", label: "Chat" },
        { key: "calendar", icon: "calendar", label: "Calendar" },
        { key: "calls", icon: "call", label: "Calls" },
        { key: "onedrive", icon: "onedrive", label: "OneDrive" },
        { key: "apps", icon: "apps", label: "Apps" },
        { key: "add", icon: "add-app", label: "Add apps" },
        { key: "more", icon: "more", label: "More apps" },
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
                    visible: modelData.key === "chat" && root.unreadChats > 0
                    x: parent.width / 2 + 4; y: 6
                    width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
                    color: theme.badge
                    border.color: theme.chrome; border.width: 1
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.unreadChats
                        color: "white"
                        font.family: theme.font; font.pixelSize: theme.caption; font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: root.current = modelData.key }
                ToolTipLabel { text: modelData.label; shown: hover.hovered }
            }
        }
    }

    component ToolTipLabel: Rectangle {
        property string text
        property bool shown
        visible: shown
        x: parent.width - 4; anchors.verticalCenter: parent.verticalCenter
        width: tip.implicitWidth + 16; height: 26; radius: theme.radius
        color: "#242424"; z: 10
        Text { id: tip; anchors.centerIn: parent; text: parent.text; color: "white"; font.family: theme.font; font.pixelSize: theme.small }
    }
}
