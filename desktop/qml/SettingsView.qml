import QtQuick
import QtQuick.Controls.Basic

// Settings (Ctrl+,), laid out as Teams desktop's (measured at 1x): a
// 379 px list of pages, and the chosen page as bordered cards. Only
// settings OST actually honours are offered.
Rectangle {
    id: root
    property string page: "general"
    color: theme.surface

    readonly property var pages: [
        { key: "general", label: "General", icon: "settings-20" },
        { key: "appearance", label: "Appearance", icon: "paint-brush-20" },
        { key: "chats", label: "Chats and channels", icon: "chat-20" },
        { key: "notifications", label: "Notifications and activity", icon: "alert" },
        { key: "devices", label: "Devices", icon: "headset-20" },
    ]
    property string filter: ""

    // Left: title, find box, pages.
    Rectangle {
        id: nav
        width: 379; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.edge }
        Text {
            x: 32; y: 20
            text: "Settings"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            x: 32; y: 73; width: 332; height: 32; radius: theme.radius
            color: theme.input
            border.color: find.activeFocus ? theme.brand : theme.stroke
            TextInput {
                id: find
                x: 12; width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                onTextChanged: root.filter = text.trim().toLowerCase()
                Text {
                    visible: !find.text
                    text: "Find in Settings (Ctrl+F)"
                    color: theme.textTertiary
                    font: find.font
                }
                Accessible.name: "Find in Settings"
            }
        }
        Column {
            x: 18.7; y: 121
            width: 344
            spacing: 1
            Repeater {
                model: root.pages.filter(p => !root.filter || p.label.toLowerCase().indexOf(root.filter) >= 0)
                Rectangle {
                    required property var modelData
                    readonly property bool sel: root.page === modelData.key
                    width: parent.width; height: 32; radius: theme.radius
                    color: sel ? theme.selected : (nh.hovered ? theme.rowHover : "transparent")
                    FluentIcon {
                        x: 18; anchors.verticalCenter: parent.verticalCenter; size: 20
                        name: parent.modelData.icon
                        color: parent.sel ? theme.brand : theme.textStrong
                    }
                    Text {
                        x: 48; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.label
                        font.family: theme.font; font.pixelSize: theme.base
                        font.weight: parent.sel ? Font.DemiBold : Font.Normal
                        color: parent.sel ? theme.text : theme.textStrong
                    }
                    HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.page = parent.modelData.key }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                }
            }
        }
        Rectangle {
            x: 18.7; y: parent.height - 52; width: 344; height: 32; radius: theme.radius
            readonly property bool sel: root.page === "about"
            color: sel ? theme.selected : (ah.hovered ? theme.rowHover : "transparent")
            FluentIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "info-16"; color: theme.textStrong }
            Text {
                x: 48; anchors.verticalCenter: parent.verticalCenter
                text: "About OST"
                font.family: theme.font; font.pixelSize: theme.base
                font.weight: parent.sel ? Font.DemiBold : Font.Normal
                color: parent.sel ? theme.text : theme.textStrong
            }
            HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.page = "about" }
            Accessible.role: Accessible.PageTab
            Accessible.name: "About OST"
        }
    }

    // A bordered settings card, as Teams draws them.
    component Card: Rectangle {
        id: card
        property string title
        property string subtitle
        property string icon
        default property alias content: body.data
        width: parent ? parent.width : 0
        height: body.y + body.implicitHeight + 24
        radius: 8
        color: "transparent"
        border.color: theme.stroke
        FluentIcon { x: 24; y: 24; name: card.icon; size: 20; color: theme.textStrong }
        Text {
            id: ct
            x: 56.7; y: 26.7
            text: card.title
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
        }
        Text {
            id: cs
            visible: card.subtitle.length > 0
            x: 56.7; y: ct.y + ct.height
            width: card.width - 80
            wrapMode: Text.Wrap
            text: card.subtitle
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.textSecondary
        }
        Column {
            id: body
            x: 56.7; y: (card.subtitle ? cs.y + cs.height : ct.y + ct.height) + 16
            width: card.width - 80
            spacing: 22
        }
    }

    // Fluent checkbox: 16 px, brand fill with a white tick when on.
    component Check: Item {
        id: chk
        property string label
        property bool checked
        property bool usable: true
        signal toggled(bool on)
        width: parent ? parent.width : 0; height: 20
        Rectangle {
            x: -28; y: 2; width: 16; height: 16; radius: 2
            color: chk.checked ? (chk.usable ? theme.brandFill : theme.disabled) : "transparent"
            border.color: chk.checked ? "transparent" : (chk.usable ? theme.textStrong : theme.disabled)
            FluentIcon { visible: chk.checked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
        }
        Text {
            text: chk.label
            font.family: theme.font; font.pixelSize: theme.base
            color: chk.usable ? theme.text : theme.textSecondary
        }
        TapHandler { enabled: chk.usable; onTapped: chk.toggled(!chk.checked) }
        HoverHandler { cursorShape: chk.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: checked
    }

    // Fluent switch: 40 x 20 pill with "On"/"Off" before it.
    component Switch2: Row {
        id: sw
        property bool on
        signal toggled(bool on)
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sw.on ? "On" : "Off"
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
        }
        Rectangle {
            width: 40; height: 20; radius: 10
            color: sw.on ? theme.brandFill : "transparent"
            border.color: sw.on ? "transparent" : theme.textStrong
            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: sw.on ? parent.width - width - 3 : 3
                color: sw.on ? "white" : theme.textStrong
                Behavior on x { NumberAnimation { duration: 100 } }
            }
            TapHandler { onTapped: sw.toggled(!sw.on) }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }

    // Fluent dropdown: 32 px, bottom-accented.
    component Choice: Rectangle {
        id: ch
        property var options: []     // [{value, label}]
        property string value
        signal chosen(string value)
        width: 300; height: 32; radius: theme.radius
        color: theme.input
        border.color: theme.stroke
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.textStrong; radius: 1 }
        Text {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40; elide: Text.ElideRight
            text: { const o = ch.options.find(o => o.value === ch.value); return o ? o.label : ch.value }
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.textStrong }
        TapHandler { onTapped: popup.open() }
        Popup {
            id: popup
            y: ch.height + 2
            width: ch.width
            padding: 4
            background: Rectangle { radius: theme.radius; color: theme.menu; border.color: theme.dividerSoft }
            contentItem: Column {
                Repeater {
                    model: ch.options
                    Rectangle {
                        required property var modelData
                        width: popup.width - 8; height: 32; radius: theme.radius
                        color: oh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { visible: parent.modelData.value === ch.value; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-12"; size: 12; color: theme.text }
                        Text {
                            x: 28; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.label
                            font.family: theme.font; font.pixelSize: theme.base
                            color: theme.text
                        }
                        HoverHandler { id: oh }
                        TapHandler { onTapped: { popup.close(); ch.chosen(parent.modelData.value) } }
                    }
                }
            }
        }
        Accessible.role: Accessible.ComboBox
    }

    // Right: the page.
    Flickable {
        id: content
        anchors { left: nav.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        contentHeight: pageCol.y + pageCol.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Text {
            x: 21; y: 18.6
            text: root.page === "about" ? "About OST" : (root.pages.find(p => p.key === root.page) || {}).label || ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Column {
            id: pageCol
            x: 21; y: 73
            width: content.width - 43
            spacing: 12

            // General
            Card {
                visible: root.page === "general"
                title: "System"; icon: "settings-20"
                Check {
                    label: "Auto-start OST"
                    checked: backend.setting("autoStart") === "true"
                    onToggled: on => { backend.setSetting("autoStart", on ? "true" : "false"); checked = on }
                }
                Check {
                    label: "On close, keep the application running"
                    checked: backend.setting("keepRunning") !== "false"
                    onToggled: on => { backend.setSetting("keepRunning", on ? "true" : "false"); checked = on }
                }
            }

            // Appearance
            Card {
                visible: root.page === "appearance"
                title: "Theme"; subtitle: "This will apply to all your OST windows."; icon: "paint-brush-20"
                Choice {
                    options: [
                        { value: "system", label: "Follow operating system theme" },
                        { value: "light", label: "Light" },
                        { value: "dark", label: "Dark" },
                    ]
                    value: backend.themeMode
                    onChosen: v => backend.setSetting("theme", v)
                }
            }

            // Chats and channels
            Card {
                id: enterCard
                visible: root.page === "chats"
                title: "When writing a message, press Enter to"; icon: "keyboard-20"
                property string enterKey: backend.setting("enterKey") || "send"
                Repeater {
                    model: [{ v: "send", l: "Send the message" }, { v: "newline", l: "Start a new line (to send, select Send or use Ctrl+Enter)" }]
                    Item {
                        required property var modelData
                        width: parent.width; height: 20
                        readonly property bool on: enterCard.enterKey === modelData.v
                        Rectangle {
                            x: -28; y: 2; width: 16; height: 16; radius: 8
                            color: "transparent"; border.color: parent.on ? theme.brandFill : theme.textStrong
                            Rectangle { visible: parent.parent.on; anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: theme.brandFill }
                        }
                        Text { text: parent.modelData.l; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                        TapHandler { onTapped: { backend.setSetting("enterKey", parent.modelData.v); enterCard.enterKey = parent.modelData.v; root.settingsChanged() } }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.l
                        Accessible.checked: on
                    }
                }
            }
            Card {
                visible: root.page === "chats"
                title: "Read receipts"; icon: "eye-16"
                subtitle: "Let people know when you've seen their messages and know when they've seen yours."
                Switch2 {
                    on: backend.readReceipts
                    onToggled: v => backend.changeReadReceipts(v)
                }
            }

            // Notifications and activity
            Card {
                visible: root.page === "notifications"
                title: "Notifications"; icon: "alert"
                subtitle: "Show a desktop notification for new messages when OST isn't the window you're using."
                Switch2 {
                    on: backend.setting("notifications") !== "off"
                    onToggled: v => { backend.setSetting("notifications", v ? "on" : "off"); on = v }
                }
            }

            // Devices
            Card {
                id: devices
                visible: root.page === "devices"
                title: "Audio devices"; icon: "headset-20"
                subtitle: "Used for calls you start or answer after changing them."
                readonly property var list: root.page === "devices" ? JSON.parse(backend.audioDevices()) : { inputs: [], outputs: [] }
                Text { text: "Speaker"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Choice {
                    width: 360
                    options: [{ value: "default", label: "Default" }].concat(devices.list.outputs.map(n => ({ value: n, label: n })))
                    value: backend.setting("speakerDevice") || "default"
                    onChosen: v => { backend.setSetting("speakerDevice", v); value = v }
                }
                Text { text: "Microphone"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                Choice {
                    width: 360
                    options: [{ value: "default", label: "Default" }].concat(devices.list.inputs.map(n => ({ value: n, label: n })))
                    value: backend.setting("micDevice") || "default"
                    onChosen: v => { backend.setSetting("micDevice", v); value = v }
                }
            }

            // About
            Card {
                visible: root.page === "about"
                title: "OST"; icon: "info-16"
                subtitle: "An open-source client for Microsoft Teams. Not affiliated with Microsoft."
                Text {
                    text: "Version " + Qt.application.version
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                }
            }
        }
    }
    signal settingsChanged()
    Component.onCompleted: backend.loadReadReceipts()
}
