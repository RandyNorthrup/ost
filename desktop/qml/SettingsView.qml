import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

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
        { key: "privacy", label: "Privacy", icon: "lock-closed-20" },
        { key: "accessibility", label: "Accessibility", icon: "accessibility-20" },
        { key: "devices", label: "Devices", icon: "headset-20" },
        { key: "calls", label: "Calls", icon: "call-20" },
        { key: "files", label: "Files and links", icon: "document-20" },
    ]
    property string filter: ""
    onPageChanged: subPage = ""
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
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "calendar-arrow-right-20"; title: "Out of office"
                subtitle: "Schedule out of office and set automatic replies"
                trailingY: 29
                trailing: Component { SettingsParts.Button { label: "Schedule"; onClicked: root.subPage = "oof" } }
            }
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: "Keyboard shortcuts"
                subtitle: "Use OST shortcuts. <a href=\"shortcuts\">See available keyboard shortcuts</a>"
                onLinkActivated: root.showShortcuts()
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

            // ---- Notifications and activity (OST's own for now) ----
            SettingsParts.Card {
                visible: root.page === "notifications"
                icon: "alert-20"; title: "Notifications"
                subtitle: "Show a desktop notification for new messages when OST isn't the window you're using."
                trailing: Component { SettingsParts.Toggle { on: root.local("notifications", "on") !== "off"; accessibleName: "Notifications"; onToggled: v => { backend.setSetting("notifications", v ? "on" : "off"); on = v; root.notifyOn = v } } }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && root.notifyOn
                icon: "mention-20"; title: "Only mentions"
                subtitle: "Notify me only when someone @mentions me. Channel posts notify only for mentions either way."
                trailing: Component { SettingsParts.Toggle { on: root.local("notify_mentions_only", "off") === "on"; accessibleName: "Only mentions"; onToggled: v => { backend.setSetting("notify_mentions_only", v ? "on" : "off"); on = v } } }
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

            // ---- Devices (OST's own for now) ----
            SettingsParts.Card {
                id: devices
                visible: root.page === "devices"
                icon: "headset-20"; title: "Audio devices"
                subtitle: "Used for calls you start or answer after changing them."
                readonly property var list: root.page === "devices" ? JSON.parse(backend.audioDevices()) : { inputs: [], outputs: [] }
                SettingsParts.SubHeading { text: "Speaker" }
                SettingsParts.Gap { size: 8 }
                OutlineDropdown {
                    width: 360
                    readonly property var values: ["default"].concat(devices.list.outputs)
                    options: values.map(v => ({ label: v === "default" ? "Default" : v }))
                    current: Math.max(0, values.indexOf(root.local("speakerDevice", "default")))
                    accessibleName: "Speaker"
                    onPicked: i => backend.setSetting("speakerDevice", values[i])
                }
                SettingsParts.SubHeading { text: "Microphone"; gapAbove: 16 }
                SettingsParts.Gap { size: 8 }
                OutlineDropdown {
                    width: 360
                    readonly property var values: ["default"].concat(devices.list.inputs)
                    options: values.map(v => ({ label: v === "default" ? "Default" : v }))
                    current: Math.max(0, values.indexOf(root.local("micDevice", "default")))
                    accessibleName: "Microphone"
                    onPicked: i => backend.setSetting("micDevice", values[i])
                }
                SettingsParts.Gap { size: 8 }
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
                FolderDialog {
                    id: folderPick
                    title: "Choose a download location"
                    currentFolder: "file://" + downloads.where
                    onAccepted: { const p = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")); backend.setSetting("downloadDir", p); downloads.where = backend.downloadLocation() }
                }
            }
            SettingsParts.Card {
                visible: root.page === "files"
                icon: "document-20"; title: "Always open Word, PowerPoint, and Excel files in:"
                readonly property string pref: root.prop("userPersonalSettings", ["filesSettings", "fileOpenPreference"], "web")
                SettingsParts.RadioRow { label: "OST"; checked: parent.parent.pref === "teamsV2"; onPicked: root.setProp("userPersonalSettings", "filesSettings.fileOpenPreference", "teamsV2") }
                SettingsParts.RadioRow { label: "Browser"; checked: parent.parent.pref !== "teamsV2"; onPicked: root.setProp("userPersonalSettings", "filesSettings.fileOpenPreference", "web") }
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
    property bool notifyOn: local("notifications", "on") !== "off"
    signal showShortcuts()
    Component.onCompleted: backend.loadReadReceipts()
    function pageForTest(p, sub) { page = p; subPage = sub || ""; content.contentY = 0 }
    function oofForTest() { return oofPage }
    function scrollForTest() { content.contentY = Math.max(0, content.contentHeight - content.height) }
}
