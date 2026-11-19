import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Window

// Left app bar: icon-only buttons on a 44 px pitch, selected one marked by a
// 3 px brand bar and a filled brand-coloured icon.
Rectangle {
    id: root
    property string current: "chat"
    /// No app shown as chosen (Teams' Create team and Join a team pages).
    property bool noneChosen: false
    /// "Collapse app bar": the rail folds away, as in Teams.
    property bool collapsed: false
    /// Teams' "Show app names": labels under the icons (56 px items).
    property bool showNames: false
    /// Teams' "Auto collapse app bar": it folds away once you pick an app.
    property bool autoCollapse: false
    /// Teams' Separate view: a Teams app after Chat (Ctrl+3), the rest
    /// moved down one; Chat and Teams share the chat view.
    property bool split: false
    property string collabPane: "chats"
    signal collabPicked(string pane)
    /// The app bar menu's Pin / Unpin (Events).
    signal pinRequested(string key, bool on)
    function pick(key) {
        if (split && (key === "chat" || key === "teams")) collabPicked(key === "teams" ? "teams" : "chats")
        else current = key
        if (autoCollapse) collapsed = true
    }
    property int unreadChats: 0
    property int unreadActivity: 0
    color: theme.chrome
    width: collapsed ? 0 : theme.railWidth
    visible: !collapsed
    clip: true

    // Apps opened from "View more apps" join the rail, as in Teams.
    property var opened: []
    readonly property var extraApps: [
        { key: "planner", icon: "clipboard-task-list-ltr-24", label: qsTr("Planner"), keys: "" },
        { key: "people", icon: "people-20", label: qsTr("People"), keys: "" },
        { key: "onenote", icon: "notebook-20", label: qsTr("OneNote"), keys: "" },
        { key: "whiteboard", icon: "board-20", label: qsTr("Whiteboard"), keys: "" },
        { key: "clipchamp", icon: "video", label: qsTr("Clipchamp"), keys: "" },
        { key: "shifts", icon: "calendar-clock-20", label: qsTr("Shifts"), keys: "" },
        // An app from Teams' store shows its own outline icon (the
        // manifest's), tinted as the rail's glyphs are.
        { key: "avatars", icon: "person-20", iconUrl: avatarHost.app.outline || "", label: qsTr("Avatars"), keys: "" },
        { key: "help", icon: "question-circle-20", label: qsTr("Help"), keys: "" },
        { key: "events", icon: "ticket-diagonal-20", label: qsTr("Events"), keys: "" },
        { key: "recaps", icon: "arrow-counterclockwise-20", label: qsTr("Meeting Recaps"), keys: "" },
        // A Word, Excel or PowerPoint file open in Office for the web takes
        // the slot as its app (Teams' "Teams" choice).
        { key: "office", icon: "document-20", label: officeLabel || qsTr("Office", "nova:k71egteo9"), keys: "" }
    ]
    property string officeLabel: ""
    /// Apps pinned to the bar (Events' Pin app).
    property var pinned: backend.setting("eventsAppPinned") === "true" ? ["events"] : []
    // Teams desktop's rail, with its labels and shortcuts (Copilot left out).
    readonly property var apps: (split ? [
        { key: "activity", icon: "alert", label: qsTr("Activity"), keys: "Ctrl+1" },
        { key: "chat", icon: "chat", label: qsTr("Chat"), keys: "Ctrl+2" },
        { key: "teams", icon: "people-team", label: qsTr("Teams"), keys: "Ctrl+3" },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar"), keys: "Ctrl+4" },
        { key: "calls", icon: "call", label: qsTr("Calls"), keys: "Ctrl+5" },
        { key: "onedrive", icon: "onedrive", label: qsTr("OneDrive"), keys: "Ctrl+6" },
    ] : [
        { key: "activity", icon: "alert", label: qsTr("Activity"), keys: "Ctrl+1" },
        { key: "chat", icon: "chat", label: qsTr("Chat"), keys: "Ctrl+2" },
        { key: "calendar", icon: "calendar", label: qsTr("Calendar"), keys: "Ctrl+3" },
        { key: "calls", icon: "call", label: qsTr("Calls"), keys: "Ctrl+4" },
        { key: "onedrive", icon: "onedrive", label: qsTr("OneDrive"), keys: "Ctrl+5" },
    ]).concat(extraApps.filter(a => opened.indexOf(a.key) >= 0 || current === a.key || pinned.indexOf(a.key) >= 0)).concat([
        { key: "add", icon: "add-app", label: qsTr("Store"), keys: "" },
        { key: "more", icon: "more", label: qsTr("View more apps"), keys: "" },
    ])
    // Teams keeps one slot for an app opened from View more apps: the
    // newest replaces the last.
    function openApp(key) {
        opened = pinned.indexOf(key) >= 0 ? opened : [key]
        current = key
    }

    Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: theme.edge }

    Column {
        y: 0
        width: parent.width
        spacing: root.showNames ? 0 : 4
        Repeater {
            model: root.apps
            delegate: Item {
                required property var modelData
                readonly property bool selected: !root.noneChosen && (root.split && (modelData.key === "chat" || modelData.key === "teams")
                    ? root.current === "chat" && root.collabPane === (modelData.key === "teams" ? "teams" : "chats")
                    : root.current === modelData.key)
                width: root.width; height: root.showNames ? 56 : 40
                // With app names (Teams, measured): the chosen app's whole 68 x 56
                // item is filled, its bar 3 x 47, the label 10 px under the icon.
                Rectangle {
                    id: hcFill2
                    // High contrast fills the selected app's whole 68 x 44 item
                    // with #1AEBFF (Teams, measured), names or not.
                    visible: (root.showNames || theme.highContrast) && (parent.selected || hover.hovered && root.showNames)
                    anchors.fill: parent
                    color: parent.selected ? theme.hc(theme.surface, theme.hcHighlight) : theme.hover
                }
                Rectangle {
                    visible: parent.selected
                    width: 3; height: root.showNames ? 47 : 32; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.highContrast ? "#000000" : theme.brand
                }
                Rectangle {
                    id: hcFill1
                    visible: !root.showNames
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: theme.radius
                    color: hover.hovered && !parent.selected ? theme.hover : "transparent"
                }
                FluentIcon {
                    visible: !modelData.iconUrl
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.showNames ? 8 : (parent.height - height) / 2
                    size: 24
                    name: modelData.iconUrl ? "" : parent.selected ? modelData.icon + "-filled" : modelData.icon
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.icon)
                }
                Image {
                    id: appOutline
                    visible: false
                    width: 20; height: 20
                    source: modelData.iconUrl || ""
                    sourceSize: Qt.size(48, 48)
                    smooth: true
                    layer.enabled: true
                }
                // (The icon's shape as a mask over the glyph colour.)
                Rectangle {
                    id: appOutlineFill
                    visible: false
                    width: 20; height: 20
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.icon)
                    layer.enabled: true
                }
                MultiEffect {
                    visible: !!modelData.iconUrl
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.showNames ? 10 : (parent.height - height) / 2
                    // Teams draws an app's outline icon 20 px (its manifest's
                    // smallImage, tinted by an SVG filter).
                    width: 20; height: 20
                    source: appOutlineFill
                    maskEnabled: true
                    maskSource: appOutline
                }
                Text {
                    visible: root.showNames && modelData.key !== "more"
                    x: 4; y: 34; width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.label
                    font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                    color: theme.onFill([hcFill1, hcFill2], parent.selected ? theme.brand : theme.textSecondary)
                }
                Rectangle {
                    id: hcFill3
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
                        color: theme.onFill(hcFill3, "white")
                        font.family: theme.font; font.pixelSize: theme.caption; font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: modelData.key === "more" ? moreApps.open() : root.pick(modelData.key) }
                // Events' entry: Teams' app bar menu Pin / Unpin (kept in
                // Teams' pinned apps, as the app's Pin app).
                TapHandler {
                    enabled: modelData.key === "events"
                    acceptedButtons: Qt.RightButton
                    onTapped: { railMenu.parent = parent; railMenu.y = parent.height; railMenu.open() }
                }
                MenuPopup {
                    id: railMenu
                    items: [{ key: "pin", label: root.pinned.indexOf("events") >= 0 ? qsTr("Unpin") : qsTr("Pin"), icon: root.pinned.indexOf("events") >= 0 ? "pin-off-20" : "pin-20" }]
                    onPicked: i => root.pinRequested("events", root.pinned.indexOf("events") < 0)
                }
                ToolTipLabel { text: modelData.keys ? qsTr("%1 (%2)").arg(modelData.label).arg(modelData.keys) : modelData.label; shown: hover.hovered }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.keys ? qsTr("%1 (%2)").arg(modelData.label).arg(modelData.keys) : modelData.label
            }
        }
    }

    // View more apps: Teams' flyout with a search box and the apps. Planner,
    // OneNote and People are native; Whiteboard, Shifts and Clipchamp open
    // in OST's TeamsJS host as Teams hosts them; Help is embedded.
    Popup {
        id: moreApps
        parent: root.Window.contentItem
        x: root.width + 2; y: 92
        width: 300; padding: 8
        onOpened: { appSearch.text = ""; appSearch.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        // Teams' list and order for this account. Shifts, Clipchamp and
        // Whiteboard are apps Teams hosts (OST's TeamsJS host); Events is
        // Teams' own module, drawn natively (EventsView).
        readonly property var all: [
            { key: "shifts", label: qsTr("Shifts"), icon: "calendar-clock-20", color: "#5B5FC7" },
            { key: "planner", label: qsTr("Planner"), icon: "clipboard-task-list-ltr-24-filled", color: theme.brand },
            { key: "onenote", label: qsTr("OneNote"), icon: "notebook-20", color: "#7719AA" },
            { key: "help", label: qsTr("Help"), icon: "question-circle-20", color: theme.textStrong },
            { key: "clipchamp", label: qsTr("Clipchamp"), icon: "video", color: "#8764B8" },
            { key: "whiteboard", label: qsTr("Whiteboard"), icon: "board-20", color: "#0F6CBD" },
            { key: "events", label: qsTr("Events"), icon: "ticket-diagonal-20", color: theme.textStrong },
            { key: "people", label: qsTr("People"), icon: "people-20", color: theme.textStrong },
            { key: "avatars", label: qsTr("Avatars"), icon: "person-20", color: "#1D1F4E" }
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
                    Text { visible: !appSearch.text; text: qsTr("Search apps"); color: theme.textSecondary; font: appSearch.font }
                    Keys.onEscapePressed: moreApps.close()
                    Accessible.name: qsTr("Search apps")
                }
            }
            Item { width: 1; height: 4 }
            Repeater {
                model: moreApps.all.filter(a => !appSearch.text || a.label.toLowerCase().indexOf(appSearch.text.toLowerCase()) >= 0)
                Rectangle {
                    id: hcFill4
                    required property var modelData
                    width: 284; height: 40; radius: theme.radius
                    color: ah.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 22; color: theme.onFill(hcFill4, modelData.color) }
                    Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill4, theme.text) }
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
