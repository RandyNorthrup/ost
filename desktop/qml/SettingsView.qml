import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import com.ost.desktop

// Settings (Ctrl+,), laid out as Teams desktop's (measured on winpc
// 2026-11-10):
// - the left pane: 380 wide, "Settings" (18/25.7 bold) at 32, 20; "Find in
//   Settings (Ctrl+F)" (332 x 32) at 32, 73; the pages from 17, 120, each
//   346 x 32 every 33 (icon 20 at 16.7, label 14 at 49.7; the open one on
//   white with a 0.67 rgba(0,0,0,0.05) border, its icon filled in brand);
//   About at the bottom, 17 up;
// - the header: 61 tall, the page's title (18/25.7 bold) at 20, 17.6; a
//   sub-page shows "Page › Sub-page";
// - the page: cards 790 wide from 20, 12 down, 12 apart (SettingsParts).
// Settings Teams keeps for you across devices are read and saved as Teams
// does (user properties and the middle tier; Backend.loadSettings /
// changeSetting); this device's own settings stay local.
Rectangle {
    id: root
    property string page: "general"
    /// A page's sub-page ("oof": General ▸ Out of office).
    property string subPage: ""
    color: theme.surface

    readonly property var pages: [
        { key: "general", label: "General", icon: "settings-20" },
        { key: "appearance", label: "Appearance", icon: "wand-20" },
        { key: "chats", label: "Chats and channels", icon: "chat-20" },
        { key: "notifications", label: "Notifications and activity", icon: "alert-20" },
        { key: "accounts", label: "Accounts and orgs", icon: "contact-card-20" },
        { key: "privacy", label: "Privacy", icon: "lock-closed-20" },
        { key: "accessibility", label: "Accessibility", icon: "accessibility-20" },
        { key: "devices", label: "Devices", icon: "headset-20" },
        { key: "calls", label: "Calls", icon: "call-20" },
        { key: "files", label: "Files and links", icon: "document-20" },
        { key: "apppermissions", label: "App permissions", icon: "shield-20" },
    ]
    property string filter: ""
    function appPermsForTest() { return { n: (appPerms.data_.apps || []).length, names: (appPerms.data_.apps || []).map(a => a.name), loading: !!appPerms.data_.loading } }
    function openAppPermForTest(name) { const a = (appPerms.data_.apps || []).find(x => x.name === name); appPerms.open = a ? a.id : "" }
    onPageChanged: {
        subPage = ""
        if (page === "apppermissions") backend.loadPermissionApps(JSON.stringify((backend.teamsJson ? JSON.parse(backend.teamsJson) : []).map(t => t.thread_id).filter(t => !!t)))
    }
    onVisibleChanged: if (visible) backend.loadSettings()

    // Synced settings (user properties parsed; the middle tier's).
    readonly property var synced: backend.settingsJson ? JSON.parse(backend.settingsJson) : ({ props: {}, mt: {} })
    readonly property var props: synced.props || {}
    readonly property var mt: synced.mt || {}
    function prop(name, path, dflt) {
        let v = props[name]
        for (const k of path) { if (v === undefined || v === null) break; v = v[k] }
        return v === undefined || v === null ? dflt : v
    }
    // A nested patch for an object property: patch("a.b", v) -> {a: {b: v}}.
    function patch(path, value) { const o = {}; let c = o; const ks = path.split("."); ks.slice(0, -1).forEach(k => { c[k] = {}; c = c[k] }); c[ks[ks.length - 1]] = value; return o }
    function setProp(name, path, value) { backend.changeSetting("prop", name, JSON.stringify(path ? patch(path, value) : value)) }
    function setMt(name, value) { backend.changeSetting("mt", name, JSON.stringify(value)) }
    function local(name, dflt) { const v = backend.setting(name); return v === "" ? dflt : v }
    signal settingsChanged()

    // Left: title, find box, pages.
    Rectangle {
        id: nav
        width: 380; height: parent.height
        color: theme.pane
        Text {
            x: 32; y: 20
            text: "Settings"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            x: 32; y: 73; width: 332; height: 32; radius: 4
            color: theme.surface
            border.color: find.activeFocus ? theme.brand : "transparent"; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: find.activeFocus ? 2 : 0.67; color: find.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: find
                x: 12.7; width: parent.width - 25
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                onTextChanged: root.filter = text.trim().toLowerCase()
                Text { visible: !find.text; text: "Find in Settings (Ctrl+F)"; color: theme.textSecondary; font: find.font }
                Accessible.name: "Find in Settings"
            }
        }
        Shortcut { sequence: "Ctrl+F"; enabled: root.visible; onActivated: find.forceActiveFocus() }
        component NavItem: Rectangle {
            id: ni
            property var def
            readonly property bool sel: root.page === def.key
            width: 346; height: 32; radius: 4
            color: sel ? theme.surface : nh.hovered ? theme.rowHover : "transparent"
            border.color: sel ? Qt.rgba(0, 0, 0, 0.05) : "transparent"; border.width: 0.67
            FluentIcon { x: 16.7; anchors.verticalCenter: parent.verticalCenter; size: 20; name: ni.sel ? ni.def.icon + "-filled" : ni.def.icon; color: ni.sel ? theme.brand : theme.textStrong }
            Text {
                x: 49.7; anchors.verticalCenter: parent.verticalCenter
                text: ni.def.label
                font.family: theme.font; font.pixelSize: 14
                font.weight: nh.hovered && !ni.sel ? Font.DemiBold : Font.Normal
                color: ni.sel ? theme.text : theme.textStrong
            }
            HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.page = ni.def.key; root.subPage = "" } }
            Accessible.role: Accessible.PageTab
            Accessible.name: def.label
            Accessible.selected: sel
        }
        Column {
            x: 17; y: 120
            spacing: 1
            Repeater {
                model: root.pages.filter(p => !root.filter || p.label.toLowerCase().indexOf(root.filter) >= 0)
                NavItem { required property var modelData; def: modelData }
            }
        }
        NavItem { x: 17; y: parent.height - 49; def: ({ key: "about", label: "About OST", icon: "info-20" }) }
    }


    // Header.
    Rectangle {
        id: header
        anchors { left: nav.right; right: parent.right; top: parent.top }
        height: 61
        color: theme.surface
        Row {
            x: 20; y: 17.6; spacing: 8
            Text {
                visible: !!root.subPage
                text: (root.pages.find(p => p.key === root.page) || {}).label || ""
                font.family: theme.font; font.pixelSize: 18; lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                color: crumbHover.hovered ? theme.text : theme.textStrong
                HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.subPage = "" }
                Accessible.role: Accessible.Link
                Accessible.name: text
            }
            FluentIcon { visible: !!root.subPage; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-16"; size: 16; color: theme.textStrong }
            Text {
                text: root.subPage === "oof" ? "Out of office" : root.page === "about" ? "About OST" : (root.pages.find(p => p.key === root.page) || {}).label || ""
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
    }

    // The page.
    Flickable {
        id: content
        anchors { left: nav.right; right: parent.right; top: header.bottom; bottom: parent.bottom }
        contentHeight: pageCol.y + pageCol.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: pageCol
            x: 20; y: 12
            width: Math.min(790, content.width - 42)
            spacing: 12

            // ---- General ----
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "settings-20"; title: "System"
                SettingsParts.CheckRow {
                    label: "Auto-start OST"
                    checked: root.local("autoStart", "false") === "true"
                    onToggled: on => { backend.setSetting("autoStart", on ? "true" : "false"); checked = on }
                }
                SettingsParts.CheckRow {
                    label: "Open application in background"
                    checked: root.local("openInBackground", "false") === "true"
                    onToggled: on => { backend.setSetting("openInBackground", on ? "true" : "false"); checked = on }
                }
                SettingsParts.CheckRow {
                    label: "On close, keep the application running"
                    checked: root.local("keepRunning", "true") !== "false"
                    onToggled: on => { backend.setSetting("keepRunning", on ? "true" : "false"); checked = on }
                }
            }
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "chat-multiple-20"; title: "Opening content in OST windows"
                subtitle: "Open incoming notifications and links in the main window or a new window. This will only apply to this account."
                Row {
                    spacing: 12.7
                    property string mode: root.local("openContentIn", "main")
                    SettingsParts.ImageRadio { imageHeight: 80; label: "Main window"; image: "../assets/settings/new-chat-mainwindow-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode === "main"; onPicked: { backend.setSetting("openContentIn", "main"); parent.mode = "main" } }
                    SettingsParts.ImageRadio { imageHeight: 80; label: "New window"; image: "../assets/settings/new-chat-popout-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode === "popout"; onPicked: { backend.setSetting("openContentIn", "popout"); parent.mode = "popout" } }
                }
            }
            // Teams' Starting chats card: new chats in the main window or a
            // new window (the synced alwaysPopOutNewChat).
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "compose-20"; title: "Starting chats"
                subtitle: "Create new chats in the main window or a new window. This will only apply to this account."
                Row {
                    spacing: 12.7
                    readonly property bool popout: root.prop("userPersonalSettings", ["messagingSettings", "alwaysPopOutNewChat"], false) === true
                    SettingsParts.ImageRadio { imageHeight: 80; label: "Main window"; image: "../assets/settings/new-chat-mainwindow-" + theme.pick("default", "dark") + ".svg"; checked: !parent.popout; onPicked: root.setProp("userPersonalSettings", "messagingSettings.alwaysPopOutNewChat", false) }
                    SettingsParts.ImageRadio { imageHeight: 80; label: "New window"; image: "../assets/settings/new-chat-popout-" + theme.pick("default", "dark") + ".svg"; checked: parent.popout; onPicked: root.setProp("userPersonalSettings", "messagingSettings.alwaysPopOutNewChat", true) }
                }
            }
            // Teams' Meeting card. Its "New meeting controls" switches Teams
            // to a different meeting toolbar; OST has Teams' current one.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "video-20"; title: "Meeting"
                SettingsParts.SwitchRow {
                    id: leaveRow
                    label: "Ask me to confirm when I leave a meeting"
                    on: root.local("leaveConfirmation", "false") === "true"
                    onToggled: v => { backend.setSetting("leaveConfirmation", v ? "true" : "false"); leaveRow.on = v }
                }
            }
            // Teams' Time zone card (its "Manage Windows settings" link is
            // Windows' own).
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "globe-20"; title: "Time zone"
                subtitle: "You can adjust the time zone from your OS settings."
                SettingsParts.SubHeading { text: "Current time zone: " + backend.timeZoneName() }
                SettingsParts.Gap { size: 8 }
            }
            // Teams' Translation card (measured on winpc 2026-11-14): the
            // language to translate into (a searchable combobox of Teams'
            // translation languages), how to handle other languages, and
            // the languages never to translate as chips (yours first, with
            // no remove). Kept on this device, as Teams does.
            SettingsParts.Card {
                id: translationCard
                visible: root.page === "general" && !root.subPage
                icon: "translate-20-filled"; title: "Translation"
                property var settings: JSON.parse(backend.translationSettingsJson())
                property var languages: JSON.parse(backend.translationLanguagesJson())
                Connections {
                    target: backend
                    function onTranslationLanguagesReady() { translationCard.languages = JSON.parse(backend.translationLanguagesJson()) }
                }
                onVisibleChanged: if (visible) {
                    settings = JSON.parse(backend.translationSettingsJson())
                    if (languages.length === 0) languages = JSON.parse(backend.translationLanguagesJson())
                }
                function nameOf(code) { const l = languages.find(x => x.code === code); return l ? l.name : code }
                function save(key, value) {
                    backend.setSetting(key, value)
                    settings = JSON.parse(backend.translationSettingsJson())
                }
                readonly property var modes: ["SUGGEST_TRANSLATION", "ALWAYS_TRANSLATE", "NEVER_TRANSLATE"]
                // The other known languages (yours is its own chip).
                readonly property var others: settings.known.filter(k => k !== settings.target)
                SettingsParts.SubHeading { text: "Translate messages into this language" }
                SettingsParts.Gap { size: 10 }
                SearchCombobox {
                    id: translationTargetBox
                    width: 294; height: 32
                    options: translationCard.languages.map(l => ({ key: l.code, label: l.native, sublabel: l.english }))
                    current: translationCard.settings.target
                    accessibleName: "Translate messages into this language"
                    onPicked: code => {
                        // Your new language is one you never translate.
                        const known = translationCard.settings.known.filter(k => k !== code).concat([code])
                        translationCard.save("translationTarget", code)
                        translationCard.save("translationKnown", JSON.stringify(known))
                    }
                }
                SettingsParts.Gap { size: 15 }
                SettingsParts.SubHeading { text: "How to handle messages in other languages" }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    width: 294; height: 31.3
                    options: [{ label: "Ask me before translating" }, { label: "Auto-translate all messages" }, { label: "Never translate" }]
                    current: Math.max(0, translationCard.modes.indexOf(translationCard.settings.mode))
                    accessibleName: "How to handle messages in other languages"
                    onPicked: i => translationCard.save("translationMode", translationCard.modes[i])
                }
                SettingsParts.Gap { size: 15 }
                SettingsParts.SubHeading { text: "Never translate messages in these languages" }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    id: addLanguage
                    width: 294; height: 31.3
                    maxListHeight: 332
                    placeholder: "Add another language"
                    current: -1
                    readonly property var choices: translationCard.languages.filter(l => translationCard.settings.known.indexOf(l.code) < 0 && l.code !== translationCard.settings.target)
                    options: choices.map(l => ({ label: l.name }))
                    accessibleName: "Never translate messages in these languages"
                    onPicked: i => translationCard.save("translationKnown", JSON.stringify(translationCard.settings.known.concat([choices[i].code])))
                }
                SettingsParts.Gap { size: 15 }
                Flow {
                    x: -8; width: parent.width + 8
                    spacing: 12
                    bottomPadding: 12
                    Repeater {
                        model: [translationCard.settings.target].concat(translationCard.others)
                        // Teams' chip: a pill with a 0.67 NeutralStroke1 border,
                        // 14 px semibold 12 in, 31.3 tall; the others carry a
                        // dismiss (20) and remove themselves when clicked.
                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property bool removable: index > 0
                            width: chipRow.width + 24; height: 31.3
                            radius: height / 2
                            color: chipHover.hovered && removable ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
                            border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                            Row {
                                id: chipRow
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { anchors.verticalCenter: parent.verticalCenter; text: translationCard.nameOf(chip.modelData); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                FluentIcon { visible: chip.removable; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-20"; size: 20; color: theme.text }
                            }
                            HoverHandler { id: chipHover; enabled: chip.removable; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: chip.removable; onTapped: translationCard.save("translationKnown", JSON.stringify(translationCard.settings.known.filter(k => k !== chip.modelData))) }
                            Accessible.role: chip.removable ? Accessible.Button : Accessible.StaticText
                            Accessible.name: chip.removable ? "Remove " + translationCard.nameOf(chip.modelData) + " from known languages" : translationCard.nameOf(chip.modelData)
                            Accessible.onPressAction: if (chip.removable) translationCard.save("translationKnown", JSON.stringify(translationCard.settings.known.filter(k => k !== chip.modelData)))
                        }
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "calendar-arrow-right-20"; title: "Out of office"
                subtitle: "Schedule out of office and set automatic replies"
                trailingY: 29
                trailing: Component { SettingsParts.Button { label: "Schedule"; onClicked: root.subPage = "oof" } }
            }
            // Teams' Keyboard shortcuts card: its profile dropdown (248.7 x
            // 30) — Teams only, + Slack, + Zoom, + combined — saved to the
            // synced keyboardShortcutsSettings.shortcutProfile.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: "Keyboard shortcuts"
                subtitle: "Use OST shortcuts, or combine them with those of other apps. <a href=\"shortcuts\">See available keyboard shortcuts</a>"
                onLinkActivated: root.showShortcuts()
                OutlineDropdown {
                    width: 248.7; height: 30
                    readonly property var keys: ["default", "chats_alt", "meetings_alt", "chats_meetings_alt"]
                    readonly property string current_: {
                        let v = root.props.keyboardShortcutsSettings
                        if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { v = null } }
                        return (v && v.shortcutProfile) || "default"
                    }
                    options: [{ label: "OST only (Default)" }, { label: "OST + Slack shortcuts" }, { label: "OST + Zoom shortcuts" }, { label: "OST + combined shortcuts" }]
                    current: Math.max(0, keys.indexOf(current_))
                    accessibleName: "Keyboard shortcuts"
                    onPicked: i => root.setProp("keyboardShortcutsSettings", "shortcutProfile", keys[i])
                }
                SettingsParts.Gap { size: 8 }
            }

            // Teams' "Use Enter or Spacebar to show content" (the synced
            // messagingSettings.disableAutomaticConvSwitchOnKeyboardNav):
            // the chat list's Up / Down then only move, Enter or Space opens.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: "Use Enter or Spacebar to show content"
                subtitle: "Press Enter or Spacebar to open an item in a list (like @mentions, chats, or channels) and view its content."
                trailing: Component {
                    SettingsParts.Toggle {
                        on: root.prop("userPersonalSettings", ["messagingSettings", "disableAutomaticConvSwitchOnKeyboardNav"], false) === true
                        accessibleName: "Use Enter or Spacebar to show content"
                        onToggled: v => root.setProp("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", v)
                    }
                }
            }
            // Teams' Efficiency mode card (measured on winpc 2026-11-14):
            // three radios with second lines; "auto" is Teams' default.
            SettingsParts.Card {
                id: efficiencyCard
                visible: root.page === "general" && !root.subPage
                icon: "top-speed-20"; title: "Efficiency mode"
                subtitle: "This mode reduces processor, memory and network usage and is ideal for lower performance devices or those under heavy load. Turning this on may affect some functionality such as camera resolution."
                property string mode: root.local("efficiencyMode", "auto")
                function pick(m) { mode = m; backend.setSetting("efficiencyMode", m) }
                SettingsParts.RadioRow { label: "Use only when resources are low (Default)"; sublabel: "Reduce processor and memory usage when reduced resources are detected."; checked: efficiencyCard.mode === "auto"; onPicked: efficiencyCard.pick("auto") }
                SettingsParts.RadioRow { label: "Never use efficiency mode"; sublabel: "Prioritize a richer experience, using more system resources."; checked: efficiencyCard.mode === "off"; onPicked: efficiencyCard.pick("off") }
                SettingsParts.RadioRow { label: "Always use efficiency mode"; sublabel: "Reduce processor and memory use at all times."; checked: efficiencyCard.mode === "on"; onPicked: efficiencyCard.pick("on") }
                SettingsParts.Gap { size: 8 }
            }

            // ---- General ▸ Out of office ----
            OofPage {
                id: oofPage
                visible: root.page === "general" && root.subPage === "oof"
                width: parent.width
                setting: root.mt.oof || null
                onSave: v => { root.setMt("oof", v); root.subPage = "" }
                onCancel: root.subPage = ""
            }

            // ---- Appearance ----
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "dark-theme-20"; title: "Theme"; subtitle: "This will apply to all your OST apps."
                OutlineDropdown {
                    width: 249.3; height: 30
                    readonly property var keys: ["system", "light", "dark"]
                    options: [{ label: "Follow operating system theme" }, { label: "Light" }, { label: "Dark" }]
                    current: Math.max(0, keys.indexOf(backend.themeMode))
                    accessibleName: "Theme"
                    onPicked: i => backend.setSetting("theme", keys[i])
                }
                SettingsParts.Gap { size: 16 }
            }
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "emoji-hand-20"; title: "Skin tone preference"; subtitle: "Reactions and emoji will appear with this skin tone."
                Row {
                    spacing: 8
                    Repeater {
                        model: ["None", "Light", "Medium light", "Medium", "Medium dark", "Dark"]
                        Item {
                            required property string modelData
                            required property int index
                            readonly property bool on: backend.skinTone === index
                            width: 32; height: 40
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 2; width: 24; height: 24; radius: 12; color: ["#FFC83D", "#F7D7C4", "#D8B094", "#BB9167", "#8E562E", "#613D30"][index] }
                            Rectangle { visible: parent.on; anchors.horizontalCenter: parent.horizontalCenter; y: 32; width: 24; height: 3; radius: 1.5; color: theme.brand }
                            TapHandler { onTapped: { backend.changeSetting("prop", "preferredSkinToneIndex", JSON.stringify(String(index))); backend.skinTone = index } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData
                            Accessible.checked: on
                        }
                    }
                }
                SettingsParts.Gap { size: 8 }
            }

            // ---- Chats and channels ----
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "apps-list-20"; title: "Chats and channels list"
                SettingsParts.SwitchRow {
                    label: "Show message previews for chats and team names for channels"
                    on: root.prop("simpleCollabUserSettings", ["hasUserEnabledMessagePreviews"], false) === true
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserEnabledMessagePreviews", v)
                }
                SettingsParts.SwitchRow {
                    label: "Show time stamps"
                    on: root.prop("simpleCollabUserSettings", ["hasUserEnabledShowTimeStamps"], false) === true
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserEnabledShowTimeStamps", v)
                }
                SettingsParts.SwitchRow {
                    label: "Filters"
                    on: root.prop("simpleCollabUserSettings", ["hasUserDisabledShowingFilterAtTop"], false) !== true
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserDisabledShowingFilterAtTop", !v)
                }
                SettingsParts.SwitchRow {
                    label: "Copilot"
                    on: root.prop("userPersonalSettings", ["messagingSettings", "shouldShowMetaOSCopilotApp"], true) !== false
                    onToggled: v => root.setProp("userPersonalSettings", "messagingSettings.shouldShowMetaOSCopilotApp", v)
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-bubbles-question-20"; title: "Automatically follow threads in channels"
                subtitle: "To choose how you get notified, go to <a href=\"followed\">Replies to followed threads and posts</a>"
                onLinkActivated: root.page = "notifications"
                Repeater {
                    model: [{ key: "Authored", label: "Threads started from my messages or posts" }, { key: "Participated", label: "Threads I reply to" }, { key: "AtMentioned", label: "Threads where I'm @mentioned" }]
                    SettingsParts.CheckRow {
                        required property var modelData
                        label: modelData.label
                        checked: root.prop("userPersonalSettings", ["teamsAndChannelsSettings", "autoFollow" + modelData.key + "Threads"], true) !== false
                        onToggled: on => {
                            const p = {}
                            p["autoFollow" + modelData.key + "Threads"] = on
                            p["autoFollow" + modelData.key + "Posts"] = on
                            backend.changeSetting("prop", "userPersonalSettings", JSON.stringify({ teamsAndChannelsSettings: p }))
                        }
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-20"; title: "Chat"
                SettingsParts.SubHeading { text: "Message density" }
                SettingsParts.Gap { size: 13 }
                Row {
                    spacing: 12.7
                    readonly property string mode: root.prop("messageDensity", [], "COMFY")
                    SettingsParts.ImageRadio { label: "Comfy"; image: "../assets/settings/chat-density-comfy-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode !== "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMFY") }
                    SettingsParts.ImageRadio { label: "Compact"; image: "../assets/settings/chat-density-compact-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode === "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMPACT") }
                }
                SettingsParts.SubHeading { text: "When I open a chat, take me to"; gapAbove: 15 }
                SettingsParts.Gap { size: 13 }
                Row {
                    spacing: 12.7
                    readonly property bool lastRead: root.prop("userPersonalSettings", ["messagingSettings", "navigateToLastReadMessage"], true) !== false
                    SettingsParts.ImageRadio { label: "Last read message"; image: "../assets/settings/chat-landing-unread-" + theme.pick("light", "dark") + ".svg"; checked: parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", true) }
                    SettingsParts.ImageRadio { label: "Newest message"; image: "../assets/settings/chat-landing-latest-" + theme.pick("light", "dark") + ".svg"; checked: !parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", false) }
                }
                SettingsParts.Gap { size: 4 }
            }
            SettingsParts.Card {
                id: enterCard
                visible: root.page === "chats"
                icon: "keyboard-20"; title: "When writing a message, press Enter to"
                subtitle: "This setting doesn't apply when message formatting is active."
                property string enterKey: root.local("enterKey", "send")
                SettingsParts.RadioRow { label: "Send the message"; checked: enterCard.enterKey === "send"; onPicked: { backend.setSetting("enterKey", "send"); enterCard.enterKey = "send"; root.settingsChanged() } }
                SettingsParts.RadioRow { label: "Start a new line (to send, select Send or use Ctrl+Enter)."; checked: enterCard.enterKey === "newline"; onPicked: { backend.setSetting("enterKey", "newline"); enterCard.enterKey = "newline"; root.settingsChanged() } }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "eye-20"; title: "Read receipts"
                subtitle: "Let people know when you’ve seen their messages and know when they’ve seen yours. When this is off, you won't see read receipts from others."
                trailing: Component { SettingsParts.Toggle { on: backend.readReceipts; accessibleName: "Read receipts"; onToggled: v => backend.changeReadReceipts(v) } }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "arrow-sort-20"; title: "In post channels, show recent activity"
                SettingsParts.RadioRow { label: "At the top"; checked: backend.channelPostsAtTop; onPicked: backend.channelAction("posts-at-top", "", "", "") }
                SettingsParts.RadioRow { label: "At the bottom"; checked: !backend.channelPostsAtTop; onPicked: backend.channelAction("posts-at-bottom", "", "", "") }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-sparkle-20"; title: "Suggested replies"; subtitle: "Show suggested replies in chat"
                trailing: Component { SettingsParts.Toggle { on: root.prop("suggestedRepliesSettings", ["suggestionsEnabled"], true) !== false; accessibleName: "Suggested replies"; onToggled: v => root.setProp("suggestedRepliesSettings", "suggestionsEnabled", v) } }
            }

            // ---- Notifications and activity ----
            // Teams' page (measured and captured on winpc 2026-11-10):
            // synced settings in userPersonalSettings' toastSettings,
            // soundsSettings, emailSettings and activityGenerationSettings;
            // the dismiss time and taskbar flash stay on this device.
            Item {
                id: notif
                visible: false
                function ts(k, d) { return root.prop("userPersonalSettings", ["toastSettings", k], d) }
                function setTs(k, v) { root.setProp("userPersonalSettings", "toastSettings." + k, v) }
                function setMany(o) { backend.changeSetting("prop", "userPersonalSettings", JSON.stringify(o)) }
                // A notification kind's dropdown: 0 Activity and banner, 1 Activity only, 2 Off.
                function level(keys, dflt) {
                    const t = ts(keys[0], undefined), a = root.prop("userPersonalSettings", ["activityGenerationSettings", keys[0]], undefined)
                    if (t === undefined && a === undefined) return dflt
                    return t === true ? 0 : a === false ? 2 : 1
                }
                function setLevel(keys, i) {
                    const toast = {}, act = {}, mail = {}
                    for (const k of keys) { toast[k] = i === 0; act[k] = i !== 2; mail[k] = i === 0 }
                    setMany({ toastSettings: toast, activityGenerationSettings: act, emailSettings: mail })
                }
                readonly property var levels: [{ label: "Show in Activity and banner" }, { label: "Show in Activity" }, { label: "Off" }]
            }
            SectionTitle { visible: root.page === "notifications"; text: "General" }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "alert-off-20"; title: "Mute all notifications (except for calls and meetings)"
                readonly property bool muted: notif.ts("muteGenericNotifications", "Off") === "On"
                trailing: Component { SettingsParts.Toggle { on: notif.ts("muteGenericNotifications", "Off") === "On"; accessibleName: "Mute all notifications (except for calls and meetings)"; onToggled: v => notif.setTs("muteGenericNotifications", v ? "On" : "Off") } }
                SettingsParts.CheckRow {
                    label: "Always allow urgent and priority contact notifications"
                    usable: parent.parent.muted
                    checked: root.local("allowUrgentWhenMuted", "false") === "true"
                    onToggled: v => { backend.setSetting("allowUrgentWhenMuted", v ? "true" : "false"); checked = v }
                }
            }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "speaker-2-20"; title: "Sound"
                SettingsParts.CheckRow { label: "Play sounds with notifications"; checked: root.prop("userPersonalSettings", ["soundsSettings", "alertSound"], "All") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.alertSound", v ? "All" : "Off") }
                SettingsParts.CheckRow { label: "Play sounds with urgent and priority contact notifications"; checked: notif.ts("PlayNotificationSoundsForUrgentAndPriority", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsForUrgentAndPriority", v ? "On" : "Off") }
                SettingsParts.CheckRow { label: "Play sounds with incoming calls, requests to join, and meeting start notifications"; checked: root.prop("userPersonalSettings", ["soundsSettings", "incomingCallsAndMeetingStartSound"], "On") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.incomingCallsAndMeetingStartSound", v ? "On" : "Off") }
                SettingsParts.CheckRow { label: "Play sounds when I'm busy or in a meeting"; checked: notif.ts("PlayNotificationSoundsWhenBusyOrInMeetings", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsWhenBusyOrInMeetings", v ? "On" : "Off") }
            }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "eye-20"; title: "Display"
                trailingY: 29
                trailing: Component { SettingsParts.Button { label: "Test notification"; onClicked: backend.testNotification() } }
                SettingsParts.CheckRow { label: "Show message and content previews in notifications"; checked: notif.ts("ShowPreviewInToasts", "On") !== "Off"; onToggled: v => notif.setTs("ShowPreviewInToasts", v ? "On" : "Off") }
                SettingsParts.CheckRow { label: "Show notifications during calls and meetings"; checked: notif.ts("MuteNotificationsDuringMeetings", "Off") !== "On"; onToggled: v => notif.setTs("MuteNotificationsDuringMeetings", v ? "Off" : "On") }
                SettingsParts.CheckRow { label: "Flash taskbar when notifications are received"; checked: root.local("flashTaskbar", "true") !== "false"; onToggled: v => { backend.setSetting("flashTaskbar", v ? "true" : "false"); checked = v } }
                SettingsParts.SubHeading { text: "Dismiss notifications after this amount of time"; gapAbove: 4 }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    readonly property var secs: [5, 7, 15, 30, 60, 300]
                    options: [{ label: "5 seconds (Default)" }, { label: "7 seconds" }, { label: "15 seconds" }, { label: "30 seconds" }, { label: "1 minute" }, { label: "5 minutes" }]
                    current: Math.max(0, secs.indexOf(parseInt(root.local("toastSeconds", "5"))))
                    accessibleName: "Dismiss notifications after this amount of time"
                    onPicked: i => backend.setSetting("toastSeconds", String(secs[i]))
                }
                SettingsParts.Gap { size: 20 }
            }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "mail-20"; title: "Missed activity emails"
                trailingY: 22
                trailing: Component {
                    OutlineDropdown {
                        width: 249.3; height: 30
                        readonly property var keys: ["Immediately", "Every10Mins", "Hourly", "EveryEightHours", "Daily", "Never"]
                        options: [{ label: "As soon as possible" }, { label: "Once every 10 mins" }, { label: "Once every hour" }, { label: "Once every 8 hours" }, { label: "Daily" }, { label: "Off" }]
                        current: Math.max(0, keys.indexOf(root.prop("userPersonalSettings", ["emailSettings", "EmailNotificationDelay"], "Hourly")))
                        accessibleName: "Missed activity emails"
                        onPicked: i => root.setProp("userPersonalSettings", "emailSettings.EmailNotificationDelay", keys[i])
                    }
                }
            }
            SectionTitle { visible: root.page === "notifications"; text: "Chats and channels" }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "chat-20"; title: "Chat message notifications"
                trailingY: 22
                trailing: Component {
                    OutlineDropdown {
                        width: 249.3; height: 30
                        options: [{ label: "Off" }, { label: "Show in banner" }]
                        current: notif.ts("Chat", true) === false ? 0 : 1
                        accessibleName: "Chat message notifications"
                        onPicked: i => notif.setMany({ toastSettings: { Chat: i === 1 }, activityGenerationSettings: { Chat: i === 1 } })
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "mention-20"; title: "@Mentions"
                Repeater {
                    model: [
                        { label: "Channel and team @mentions", keys: ["Mention_Team", "Visible_ChannelMention_v2"], dflt: 0, off: true },
                        { label: "Tag @mentions", keys: ["Mention_Tag"], dflt: 0, off: true },
                        { label: "Everyone in chat @mentions", keys: ["MentionInChat_Everyone"], dflt: 0, off: true },
                        { label: "Personal @mentions", keys: ["Mention_Person", "MentionInChat_Person_v2"], dflt: 0, off: false }
                    ]
                    Item {
                        required property var modelData
                        width: parent.width; height: 68
                        Text { y: 12; text: modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        OutlineDropdown {
                            anchors.right: parent.right; anchors.rightMargin: 28; y: 8
                            width: 249.3; height: 30
                            options: modelData.off ? notif.levels : notif.levels.slice(0, 2)
                            current: notif.level(modelData.keys, modelData.dflt)
                            accessibleName: modelData.label
                            onPicked: i => notif.setLevel(modelData.keys, i)
                        }
                    }
                }
            }
            Repeater {
                model: [
                    { icon: "arrow-reply-20", title: "Replies to followed threads and posts", keys: ["Reply", "ReplyToReply"] },
                    { icon: "heart-20", title: "Likes and reactions", keys: ["Like", "LikeInChat_v2"] }
                ]
                SettingsParts.Card {
                    required property var modelData
                    visible: root.page === "notifications"
                    icon: modelData.icon; title: modelData.title
                    trailingY: 22
                    trailing: Component {
                        OutlineDropdown {
                            width: 249.3; height: 30
                            options: notif.levels
                            current: notif.level(modelData.keys, 0)
                            accessibleName: modelData.title
                            onPicked: i => notif.setLevel(modelData.keys, i)
                        }
                    }
                }
            }
            SectionTitle { visible: root.page === "notifications"; text: "Meetings" }
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "calendar-20"; title: "Meetings"
                SettingsParts.SwitchRow { label: "Meeting start notifications"; on: notif.ts("MeetingWentLiveNotification", true) !== false
                    onToggled: v => notif.setMany(v ? { toastSettings: { MeetingWentLiveNotification: true }, activityGenerationSettings: { MeetingWentLiveNotification: true }, emailSettings: { MeetingWentLiveNotification: true } } : { toastSettings: { MeetingWentLiveNotification: false } }) }
                SettingsParts.SwitchRow { label: "Show meeting join bar"; on: notif.ts("liveMeetingStatusBanner", true) !== false; onToggled: v => notif.setTs("liveMeetingStatusBanner", v) }
                SettingsParts.SwitchRow { label: "Meet now start notifications"; on: notif.ts("HuddleStartedNotification", false) === true; onToggled: v => notif.setTs("HuddleStartedNotification", v) }
            }

            // ---- Privacy ----
            SettingsParts.Card {
                visible: root.page === "privacy"
                icon: "presence-dnd-20"; title: "Do not disturb"
                subtitle: "You can still receive notifications from people who have priority access when your status is set to do not disturb."
                SettingsParts.CheckRow {
                    label: "Set my status to do not disturb when I'm sharing my screen"
                    checked: root.mt.allowAutoDnd !== false
                    onToggled: on => root.setMt("allowAutoDnd", on)
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy"
                icon: "person-prohibited-20"; title: "Blocked contacts"
                subtitle: "Blocked contacts will be unable to call you, message you, or see your presence."
                SettingsParts.CheckRow {
                    label: "Block calls with no caller ID"
                    checked: root.mt.blockAnonymousCaller === true
                    onToggled: on => root.setMt("blockAnonymousCaller", on)
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy"
                icon: "clipboard-task-list-20"; title: "Surveys"; subtitle: "Participate in surveys from OST."
                trailing: Component { SettingsParts.Toggle { on: root.prop("userEnableSurveysNotification", [], "true") !== "false"; accessibleName: "Surveys"; onToggled: v => root.setProp("userEnableSurveysNotification", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy"
                icon: "people-list-20"; title: "Identify me in attendance reports"; subtitle: "Let meeting or event organizer know your attendance information."
                trailing: Component { SettingsParts.Toggle { on: root.prop("showInMeetingReport", [], "true") !== "false"; accessibleName: "Identify me in attendance reports"; onToggled: v => root.setProp("showInMeetingReport", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy"
                icon: "mic-20"; title: "Keyboard shortcut to unmute"; subtitle: "Press and hold Ctrl + Spacebar to temporarily unmute your mic during a meeting."
                trailing: Component { SettingsParts.Toggle { on: root.prop("enablePushToTalk", [], "true") !== "false"; accessibleName: "Keyboard shortcut to unmute"; onToggled: v => root.setProp("enablePushToTalk", "", v ? "true" : "false") } }
            }

            // ---- Accessibility ----
            SettingsParts.Card {
                visible: root.page === "accessibility"
                icon: "hand-wave-20"; title: "Sign language mode"; subtitle: "Enable features that provide an enhanced experience for sign language users."
                trailing: Component { SettingsParts.Toggle { on: root.prop("callAccessibilitySettings", ["accessibilityModeEnabledV2"], false) === true; accessibleName: "Sign language mode"; onToggled: v => root.setProp("callAccessibilitySettings", "accessibilityModeEnabledV2", v) } }
            }
            SettingsParts.Card {
                visible: root.page === "accessibility"
                icon: "closed-caption-20"; title: "Captions and transcripts"
                SettingsParts.SwitchRow {
                    label: "Always show captions in my calls and meetings"
                    on: root.prop("callAccessibilitySettings", ["startCaptionsAutomatically"], false) === true
                    onToggled: v => root.setProp("callAccessibilitySettings", "startCaptionsAutomatically", v)
                }
                SettingsParts.SwitchRow {
                    label: "Automatically identify me in live captions and live transcripts"
                    on: root.mt.enableSpeakerAttribution !== false
                    onToggled: v => root.setMt("enableSpeakerAttribution", v)
                }
                SettingsParts.SwitchRow {
                    label: "Filter out profane words in live captions"
                    on: root.prop("callAccessibilitySettings", ["profanityFilterEnabled"], false) === true
                    onToggled: v => root.setProp("callAccessibilitySettings", "profanityFilterEnabled", v)
                }
            }

            // ---- Devices: Audio (Teams' Settings ▸ Devices, measured on
            // winpc 2026-11-14) ----
            // "Audio" (14/700) over the "Audio settings" card: Speaker and
            // Microphone (292.7 px dropdowns), Automatically adjust mic
            // sensitivity, a divider, Noise suppression with its two
            // choices (Voice isolation needs Microsoft's voice profile, so
            // Teams shows it disabled), a divider and Secondary Ringer.
            // Teams' "Sync device buttons" (headset HID buttons), "Make a
            // test call" (TASK-0141), Spatial audio (OST can't render it)
            // and the Devices section (Teams Rooms' connected devices) aren't
            // offered.
            Text {
                visible: root.page === "devices"
                width: parent.width; height: 44
                verticalAlignment: Text.AlignVCenter
                text: "Audio"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                id: devices
                visible: root.page === "devices"
                icon: "speaker-settings-20"; title: "Audio settings"
                readonly property var list: root.page === "devices" ? JSON.parse(backend.audioDevices()) : { inputs: [], outputs: [] }
                property bool noise: root.local("noiseSuppression", "on") !== "off"
                SettingsParts.SubHeading { text: "Speaker" }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["default"].concat(devices.list.outputs)
                    options: values.map(v => ({ label: v === "default" ? "Default" : v }))
                    current: Math.max(0, values.indexOf(root.local("speakerDevice", "default")))
                    accessibleName: "Speaker"
                    onPicked: i => backend.setSetting("speakerDevice", values[i])
                }
                SettingsParts.Gap { size: 30.7 }
                SettingsParts.SubHeading { text: "Microphone" }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["default"].concat(devices.list.inputs)
                    options: values.map(v => ({ label: v === "default" ? "Default" : v }))
                    current: Math.max(0, values.indexOf(root.local("micDevice", "default")))
                    accessibleName: "Microphone"
                    onPicked: i => backend.setSetting("micDevice", values[i])
                }
                SettingsParts.Gap { size: 22 }
                SettingsParts.SwitchRow {
                    id: agcRow
                    label: "Automatically adjust mic sensitivity"
                    on: root.local("autoGainControl", "on") !== "off"
                    onToggled: v => { backend.setSetting("autoGainControl", v ? "on" : "off"); agcRow.on = v }
                }
                SettingsParts.Gap { size: 8 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D") }
                SettingsParts.Gap { size: 22 }
                SettingsParts.SwitchRow {
                    label: "Noise suppression"
                    on: devices.noise
                    onToggled: v => { devices.noise = v; backend.setNoiseSuppression(v) }
                }
                SettingsParts.RadioRow {
                    label: "Background noise only"
                    sublabel: "Enable this to enhance your microphone audio quality by removing background noise."
                    checked: true
                    usable: devices.noise
                }
                SettingsParts.Gap { size: 4 }
                SettingsParts.RadioRow {
                    label: "Voice isolation"
                    sublabel: "Isolate your voice from background noise and other voices while speaking. Only your voice will be audible."
                    checked: false
                    usable: false
                }
                SettingsParts.Gap { size: 24 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D") }
                SettingsParts.Gap { size: 30 }
                SettingsParts.SubHeading { text: "Secondary Ringer" }
                SettingsParts.Gap { size: 16.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["none"].concat(devices.list.outputs)
                    options: values.map(v => ({ label: v === "none" ? "None" : v }))
                    current: Math.max(0, values.indexOf(root.local("secondaryRinger", "none")))
                    accessibleName: "Secondary Ringer"
                    onPicked: i => backend.setSetting("secondaryRinger", values[i])
                }
                SettingsParts.Gap { size: 8 }
            }

            // Teams' Video section (Settings ▸ Devices, measured on winpc
            // 2026-11-14): "Video" (14/700, 44 high) over the "Video
            // settings" card: your preview (640 x 360 from 44.7 in) with a
            // 24 px rgba(0,0,0,0.5) bar ("Preview", 12/600 white; with
            // Green Screen on, "What is your background color?" and a 14 px
            // swatch in a 22 px white frame at its right — pressing it
            // turns the preview into an eyedropper: click your backdrop),
            // Camera, Green Screen, Mirror my video, Adjust brightness and
            // Soft focus. Teams' "Automatically adjust camera controls" and
            // "Open camera settings" are Windows camera controls, and Super
            // resolution is TASK-0139's.
            Text {
                visible: root.page === "devices"
                width: parent.width; height: 44
                verticalAlignment: Text.AlignVCenter
                text: "Video"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                id: videoCard
                visible: root.page === "devices"
                icon: "video-20"; title: "Video settings"
                readonly property bool showing: visible && root.visible
                property bool previewing: false
                property bool picking: false
                property var cameras: []
                property string currentCamera: ""
                onShowingChanged: {
                    if (showing) {
                        const d = JSON.parse(backend.videoDevices())
                        cameras = d.devices || []
                        currentCamera = d.current || ""
                        previewing = backend.callState !== "connected" && cameras.length > 0 && backend.setCameraPreview(true)
                    } else {
                        if (picking) { picking = false; backend.setGreenScreenPicking(false) }
                        if (previewing) { previewing = false; backend.setCameraPreview(false) }
                    }
                }
                // Green Screen's detected backdrop until you pick one.
                Timer {
                    interval: 500; repeat: true
                    running: videoCard.showing && videoEffects.greenScreen && videoEffects.greenScreenColor === ""
                    onTriggered: { const c = backend.greenScreenDetected(); if (c) videoEffects.detectedColor = c }
                }
                Item {
                    x: -12.3; width: 640; height: 360 + 30
                    Rectangle {
                        id: devicePreview
                        width: 640; height: 360
                        color: theme.stage
                        clip: true
                        VideoFrame {
                            id: deviceFrame
                            anchors.fill: parent
                            visible: hasFrame
                            source: videoCard.showing && (videoCard.previewing || backend.callState === "connected") ? "self" : ""
                            transform: Scale { origin.x: deviceFrame.width / 2; xScale: videoEffects.mirror ? -1 : 1 }
                            Timer { interval: 33; repeat: true; running: videoCard.showing; onTriggered: deviceFrame.refresh() }
                        }
                        // The eyedropper (Teams' picker cursor, hotspot 2,19)
                        // while picking.
                        Image {
                            visible: videoCard.picking && pickHover.hovered
                            x: pickHover.point.position.x - 2; y: pickHover.point.position.y - 19
                            width: 24; height: 24; sourceSize: Qt.size(48, 48)
                            source: "../assets/icons/eyedropper-cursor.svg"
                            z: 2
                        }
                        HoverHandler { id: pickHover; enabled: videoCard.picking; cursorShape: videoCard.picking ? Qt.BlankCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: videoCard.picking
                            onTapped: ev => {
                                // The picture is shown mirrored when Mirror my video is on.
                                let fx = ev.position.x / devicePreview.width
                                if (videoEffects.mirror) fx = 1 - fx
                                const c = backend.previewColorAt(fx, ev.position.y / devicePreview.height)
                                if (c) videoEffects.setGreenScreenColor(c)
                                videoCard.picking = false
                                backend.setGreenScreenPicking(false)
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 24
                            color: Qt.rgba(0, 0, 0, 0.5)
                            Text {
                                anchors.centerIn: parent
                                text: videoEffects.greenScreen ? "What is your background color?" : "Preview"
                                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                color: "white"
                            }
                            Rectangle {
                                visible: videoEffects.greenScreen
                                x: parent.width - 23; y: 1; width: 22; height: 22; radius: 5
                                color: "transparent"; border.color: "white"; border.width: 2
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 3
                                    color: videoCard.picking ? theme.pick("#F5F5F5", "#3D3D3D") : (videoEffects.greenScreenColor || videoEffects.detectedColor || "#FFFFFF")
                                    border.color: theme.stroke; border.width: 0.67
                                }
                                HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        videoCard.picking = !videoCard.picking
                                        backend.setGreenScreenPicking(videoCard.picking)
                                    }
                                }
                                ToolTip.visible: swatchHover.hovered
                                ToolTip.text: "Select a color"
                                Accessible.role: Accessible.Button
                                Accessible.name: "Select a color"
                            }
                        }
                    }
                }
                SettingsParts.SubHeading { text: "Camera" }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    options: videoCard.cameras.map(c => ({ label: c.name }))
                    current: Math.max(0, videoCard.cameras.findIndex(c => c.path === videoCard.currentCamera))
                    accessibleName: "Camera"
                    onPicked: i => {
                        const c = videoCard.cameras[i]
                        if (!c || c.path === videoCard.currentCamera) return
                        videoCard.currentCamera = c.path
                        backend.setCameraDevice(c.path)
                        if (videoCard.previewing) { backend.setCameraPreview(false); backend.setCameraPreview(true) }
                    }
                }
                SettingsParts.Gap { size: 30 }
                SettingsParts.SwitchRow {
                    id: greenScreenRow
                    label: "Green Screen"
                    sublabel: "Turn on Green screen for a better look when you're using a virtual background."
                    on: videoEffects.greenScreen
                    onToggled: v => {
                        if (!v && videoCard.picking) { videoCard.picking = false; backend.setGreenScreenPicking(false) }
                        videoEffects.setGreenScreen(v)
                    }
                }
                SettingsParts.SwitchRow {
                    label: "Mirror my video"
                    sublabel: "Changing this setting will only change the view for you. This setting doesn’t currently work in Together mode."
                    on: videoEffects.mirror
                    onToggled: v => videoEffects.setMirror(v)
                }
                SettingsParts.SwitchRow {
                    label: "Adjust brightness"
                    sublabel: "Enhance the quality of your video in low light conditions."
                    on: videoEffects.brightness
                    onToggled: v => videoEffects.setBrightness(v)
                }
                SettingsParts.SwitchRow {
                    label: "Soft focus"
                    sublabel: "Smoothen your appearance for a polished look."
                    on: videoEffects.softFocus
                    onToggled: v => videoEffects.setSoftFocus(v)
                }
            }
            // ---- Calls ----
            // Teams' call handling (voicesettings' callRedirectionSettings)
            // and voicemail settings (measured and captured on winpc
            // 2026-11-10).
            Item {
                id: calls
                visible: false
                readonly property var redir: (root.mt.voice || {}).callRedirectionSettings || {}
                readonly property var pending: root.mt.redirection || null
                readonly property bool forwardAll: pending ? pending.forwardAll : (redir.callForwardingSettings || {}).isEnabled === true
                readonly property bool toVoicemail: pending ? pending.unansweredToVoicemail : (redir.unansweredCallSettings || {}).isEnabled !== false
                readonly property int delay: pending ? pending.delay : ((redir.unansweredCallSettings || {}).delaySeconds || 20)
                function save(fa, vm, d) { root.setMt("redirection", { forwardAll: fa, unansweredToVoicemail: vm, delay: d }) }
                property var vm: ({ vmUseOof: false, vmUseAutoRepliesForOof: false, vmCallAnswerRule: "" })
                function setVm(k, v) { const o = Object.assign({}, vm); o[k] = v; vm = o; const b = {}; b[k] = v; root.setMt("voicemail", b) }
            }
            Text {
                visible: root.page === "calls"
                text: "Call handling and forwarding"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "call-forward-20"; title: "Call handling and forwarding"
                SettingsParts.SwitchRow {
                    label: "Forward all calls to voicemail"
                    on: calls.forwardAll
                    onToggled: v => calls.save(v, calls.toVoicemail, calls.delay)
                }
                SettingsParts.SubHeading { visible: !calls.forwardAll; text: "When you can't answer a call"; gapAbove: 7 }
                SettingsParts.Gap { visible: !calls.forwardAll; size: 10 }
                OutlineDropdown {
                    visible: !calls.forwardAll
                    width: 293.3; height: 30
                    options: [{ label: "Do not redirect calls" }, { label: "Redirect to voicemail" }]
                    current: calls.toVoicemail ? 1 : 0
                    accessibleName: "When you can't answer a call"
                    onPicked: i => calls.save(false, i === 1, calls.delay)
                }
                SettingsParts.SubHeading { visible: !calls.forwardAll && calls.toVoicemail; text: "Ring for this many seconds before redirecting"; gapAbove: 16 }
                SettingsParts.Gap { visible: !calls.forwardAll && calls.toVoicemail; size: 10 }
                OutlineDropdown {
                    visible: !calls.forwardAll && calls.toVoicemail
                    width: 293.3; height: 30
                    readonly property var secs: [5, 10, 15, 20, 30, 40, 50, 60]
                    options: secs.map(n => ({ label: n + " seconds" + (n === 20 ? " (default)" : "") }))
                    current: Math.max(0, secs.indexOf(calls.delay))
                    accessibleName: "Ring for this many seconds before redirecting"
                    onPicked: i => calls.save(false, true, secs[i])
                }
                SettingsParts.Gap { size: 20 }
            }
            Text {
                visible: root.page === "calls"
                text: "Voicemail"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "voicemail-20"; title: "Voicemail"
                SettingsParts.SubHeading { text: "Choose what happens when the call is redirected to voicemail" }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    readonly property var rules: ["RegularVoicemail", "PromptOnly", "DeclineCall"]
                    options: [{ label: "Let the caller record a message" }, { label: "Play your greeting and end the call" }, { label: "End the call without playing your greeting" }]
                    current: rules.indexOf(calls.vm.vmCallAnswerRule)
                    placeholder: "Choose what happens when the call is redirected to voicemail"
                    accessibleName: "Choose what happens when the call is redirected to voicemail"
                    onPicked: i => calls.setVm("vmCallAnswerRule", rules[i])
                }
                SettingsParts.Gap { size: 20 }
            }
            Text {
                visible: root.page === "calls"
                text: "Out-of-office voicemail"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "voicemail-arrow-back-20"; title: "Out-of-office voicemail"
                SettingsParts.SubHeading { text: "When should your greeting play" }
                SettingsParts.Gap { size: 6 }
                SettingsParts.CheckRow { label: "All the time"; checked: calls.vm.vmUseOof === true; onToggled: v => calls.setVm("vmUseOof", v) }
                SettingsParts.CheckRow { label: "When Outlook automatic replies are on"; checked: calls.vm.vmUseAutoRepliesForOof === true; onToggled: v => calls.setVm("vmUseAutoRepliesForOof", v) }
            }

            // ---- App permissions (measured on winpc 2026-11-13) ----
            // One card (790, a 0.67 #F0F0F0 edge, radius 8): the shield (20)
            // at 18.7, 22.7, "App permissions" (14/20) at 68.5, 5.5 over the
            // explanation (12, line 17.14) with Learn more (#4F52B2). Then an
            // expander per app, 65.33 tall and 75 apart from 64.7: its icon
            // (32, a 0.67 #F0F0F0 edge, radius 6) at 19.3, 16.6, the name
            // (14/20) at 69.3, 22.6 and a 20 px chevron at 754.7. Open, each
            // permission it asks for: Teams' glyphs at 59.3 and 94.3, the
            // title (14/20) at 129.3 and its subtitle (12/16, light) under
            // it, a switch at 698.7; then "Note: Permission updates will be
            // applied the next time you open or refresh this app." The apps:
            // api::app_details::permission_apps (Teams' rule); the switches
            // stay on this device, as Teams keeps them, and OST's app views
            // honour them.
            Rectangle {
                id: appPerms
                visible: root.page === "apppermissions"
                readonly property var data_: backend.permissionAppsJson ? JSON.parse(backend.permissionAppsJson) : ({ apps: [] })
                property string open: ""
                property int rev: 0
                width: parent ? parent.width : 790
                height: 64.7 + permList.height + 10
                radius: 8; color: "transparent"
                border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D")
                FluentIcon { x: 18.7; y: 22.7; size: 20; name: "shield-20"; color: theme.text }
                Text { x: 68.5; y: 5.5; text: "App permissions"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    x: 68.5; y: 25.5; width: parent.width - 68.5 - 1
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: "Control what your apps can access when using Teams. Some apps have permissions enabled by default for your convenience. <a href=\"https://go.microsoft.com/fwlink/?linkid=2166702&clcid=0x409\" style=\"color:" + theme.brandLink + ";text-decoration:none\">Learn more</a>"
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    onLinkActivated: l => Qt.openUrlExternally(l)
                }
                Column {
                    id: permList
                    x: 0.7; y: 64.7; width: parent.width - 1.4
                    spacing: 9.7
                    Repeater {
                        model: appPerms.data_.apps || []
                        Item {
                            id: appRow
                            required property var modelData
                            required property int index
                            readonly property bool expanded: appPerms.open === modelData.id
                            width: permList.width
                            height: expanded ? 94.6 + modelData.permissions.length * 48 + 2.5 + 20 + 13 : 65.33
                            Rectangle {
                                visible: appRow.index > 0
                                x: 18.6; y: -5.3; width: parent.width - 37.2; height: 0.67
                                color: theme.pick("#EBEBEB", "#3D3D3D")
                            }
                            Item {
                                width: parent.width; height: 65.33
                                Image {
                                    x: 18.6; y: 16.6; width: 32; height: 32
                                    source: appRow.modelData.icon || ""
                                    sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; asynchronous: true
                                    Rectangle { anchors.fill: parent; radius: 6; color: "transparent"; border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D") }
                                }
                                Text { x: 68.6; y: 22.6; width: parent.width - 68.6 - 60; elide: Text.ElideRight; text: appRow.modelData.name; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                                FluentIcon { x: 754; y: 22.6; size: 20; name: appRow.expanded ? "chevron-up-20" : "chevron-down-20"; color: theme.textStrong }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: appPerms.open = appRow.expanded ? "" : appRow.modelData.id }
                                Accessible.role: Accessible.Button
                                Accessible.name: "App permissions for " + appRow.modelData.name
                            }
                            Column {
                                visible: appRow.expanded
                                x: 58.6; y: 94.6; width: parent.width - 58.6 - 40
                                Repeater {
                                    model: appRow.expanded ? appRow.modelData.permissions : []
                                    Item {
                                        id: permRow
                                        required property var modelData
                                        readonly property var glyph: ({ media: "camera", geolocation: "location", notifications: "alert", midi: "music-note-2", openExternal: "open" })[modelData.kind] || "shield"
                                        width: parent.width; height: 48
                                        FluentIcon { x: 0; y: 7.3; size: 20; name: permRow.glyph + "-20-filled"; color: theme.text }
                                        FluentIcon { x: 35; y: 7.3; size: 20; name: permRow.glyph + "-20"; color: theme.text }
                                        Text { x: 70.7; y: 0; text: permRow.modelData.title; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                        Text { visible: !!permRow.modelData.subtitle; x: 70.7; y: 22.5; text: permRow.modelData.subtitle; font.family: theme.font; font.pixelSize: 12; font.weight: Font.ExtraLight; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                                        SettingsParts.Toggle {
                                            x: 640.1; y: 9.3
                                            stateLabel: false
                                            on: { appPerms.rev; return backend.appPermission(appRow.modelData.id, permRow.modelData.kind) }
                                            accessibleName: permRow.modelData.title + " for " + appRow.modelData.name
                                            onToggled: v => { backend.setAppPermission(appRow.modelData.id, permRow.modelData.kind, v); appPerms.rev++ }
                                        }
                                    }
                                }
                                Text {
                                    y: 2.5
                                    textFormat: Text.StyledText
                                    text: "<b>Note:</b> Permission updates will be applied the next time you open or refresh this app."
                                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: !!appPerms.data_.loading
                    x: 68.5; y: 72; text: "Loading…"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
            }

            // ---- Files and links ----
            SettingsParts.Card {
                id: downloads
                visible: root.page === "files"
                icon: "arrow-download-20"; title: "Downloads"; subtitle: "Location"
                property string where: root.page === "files" ? backend.downloadLocation() : ""
                Item {
                    width: parent.width; height: 47
                    Text { y: 4; width: parent.width - 140; elide: Text.ElideMiddle; text: downloads.where; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 28; y: -2
                        width: changeRow.implicitWidth + 16; height: 31.3; radius: 4
                        color: changeHover.hovered ? theme.menuHover : "transparent"
                        Row { id: changeRow; anchors.centerIn: parent; spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder-20"; size: 20; color: theme.textStrong }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Change"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text } }
                        HoverHandler { id: changeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: folderPick.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Change download location"
                    }
                }
                // Teams' "Always ask where to save downloaded file" (this
                // device's): each download asks for its place first.
                SettingsParts.SwitchRow {
                    label: "Always ask where to save downloaded file"
                    on: root.local("askDownloadLocation", "false") === "true"
                    onToggled: v => backend.setSetting("askDownloadLocation", v ? "true" : "false")
                }
                FolderDialog {
                    id: folderPick
                    title: "Choose a download location"
                    currentFolder: "file://" + downloads.where
                    onAccepted: { const p = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")); backend.setSetting("downloadDir", p); downloads.where = backend.downloadLocation() }
                }
            }
            SettingsParts.Card {
                visible: root.page === "files"
                id: openIn
                icon: "document-20"; title: "Always open Word, PowerPoint, and Excel files in:"
                // Teams offers "Desktop app" when Office is installed and
                // keeps that choice on the device; Browser is its synced
                // "web". OST offers the desktop's own app for Word files.
                // Teams' third choice, opening in Teams, is Office for the
                // web inside its window, which OST doesn't embed (and Teams
                // is retiring it for the desktop app).
                readonly property string app: root.page === "files" ? backend.officeAppName() : ""
                property string choice: root.page === "files" ? (backend.setting("fileOpenIn") || (app ? "desktop" : "web")) : ""
                function pick(v) { backend.setSetting("fileOpenIn", v); choice = v; if (v === "web") root.setProp("userPersonalSettings", "filesSettings.fileOpenPreference", "web") }
                SettingsParts.RadioRow { visible: !!openIn.app; label: "Desktop app"; checked: openIn.choice === "desktop" && !!openIn.app; onPicked: openIn.pick("desktop") }
                SettingsParts.RadioRow { label: "Browser"; checked: openIn.choice !== "desktop" || !openIn.app; onPicked: openIn.pick("web") }
            }
            // Teams' "Links open preference": web links open in the default
            // browser or Microsoft Edge (when installed; Teams' default).
            SettingsParts.Card {
                id: linksPref
                visible: root.page === "files"
                icon: "link-20"; title: "Links open preference"
                readonly property var browsers: root.page === "files" ? JSON.parse(backend.webBrowsers()) : []
                readonly property string choice: root.local("linkBrowser", browsers.some(b => b.key === "edge") ? "edge" : "default")
                Text { text: "Always open web links in:"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    options: linksPref.browsers.map(b => ({ label: b.label }))
                    current: Math.max(0, linksPref.browsers.findIndex(b => b.key === linksPref.choice))
                    accessibleName: "Always open web links in"
                    onPicked: i => backend.setSetting("linkBrowser", linksPref.browsers[i].key)
                }
                SettingsParts.Gap { size: 20 }
            }
            SettingsParts.Card {
                visible: root.page === "files"
                icon: "image-20"; title: "File previews"
                subtitle: "Show preview cards for files shared in chats, channels, and groups, including files you share."
                trailing: Component { SettingsParts.Toggle { on: root.prop("userPersonalSettings", ["filesSettings", "enableThumbnailPreview"], true) !== false; accessibleName: "File previews"; onToggled: v => root.setProp("userPersonalSettings", "filesSettings.enableThumbnailPreview", v) } }
            }

            // ---- About ----
            SettingsParts.Card {
                visible: root.page === "about"
                icon: "info-20"; title: "OST"
                subtitle: "An open-source client for Microsoft Teams. Not affiliated with Microsoft. Version " + Qt.application.version
            }

            // A failed save, as Teams' Settings says it.
            Text {
                visible: !!backend.settingsError
                text: "Couldn't save your setting. Try again."
                font.family: theme.font; font.pixelSize: 12; color: theme.danger
            }
        }
    }
    /// Your presence, for the account card.
    property string myPresence: ""
    signal showShortcuts()
    // Teams' section headings on long pages (16/22 semibold, 20 in).
    component SectionTitle: Text {
        width: parent ? parent.width : 0
        topPadding: 8
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Component.onCompleted: backend.loadReadReceipts()
    function setPropForTest(name, path, value) { setProp(name, path, value) }
    function pageForTest(p, sub) { page = p; subPage = sub || ""; content.contentY = 0 }
    /// Teams' "Green screen settings" (the effects pane's link): Devices,
    /// scrolled to Green Screen.
    function showGreenScreen() {
        page = "devices"; subPage = ""
        Qt.callLater(() => { content.contentY = Math.max(0, greenScreenRow.mapToItem(content.contentItem, 0, 0).y - 40) })
    }
    function oofForTest() { return oofPage }
    function scrollForTest() { content.contentY = Math.max(0, content.contentHeight - content.height) }
    /// Test hook: General scrolled to the Translation card.
    function openTranslationTargetForTest(open) { if (open) translationTargetBox.openList(); else translationTargetBox.closeList() }
    function scrollToTranslationForTest() { content.contentY = Math.max(0, Math.min(pageCol.y + translationCard.y - 12, content.contentHeight - content.height)) }
}
