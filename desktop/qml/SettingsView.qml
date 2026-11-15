import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtMultimedia
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
        { key: "recognition", label: "Recognition", icon: "slide-text-20" },
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

    /// Starts Teams' voice or face capture (Recognition).
    signal recognitionRequested(string kind)
    function startRecognition(kind) {
        recognitionRequested(kind)
        const st = backend.recognitionJson ? JSON.parse(backend.recognitionJson) : ({})
        if (kind === "face") { faceDialog.voiceEnrolled = !!st.voice; faceDialog.show() }
        else { voiceDialog.faceEnrolled = !!st.face; voiceDialog.show() }
    }
    FaceCaptureDialog { id: faceDialog; onStartVoice: root.startRecognition("voice") }
    VoiceCaptureDialog { id: voiceDialog; onStartFace: root.startRecognition("face") }
    /// Test hooks: the Recognition dialogs.
    function faceDialogForTest() { return faceDialog }
    function voiceDialogForTest() { return voiceDialog }
    // Teams' sounds, previewed here (assets/sounds, Teams' own files).
    MediaPlayer {
        id: preview
        property string playing: ""
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) playing = ""
    }
    function previewSound(file) {
        preview.stop()
        if (preview.playing === file) { preview.playing = ""; return }
        preview.source = "../assets/sounds/" + file + ".mp3"
        preview.playing = file
        preview.play()
    }
    /// Teams' sound names (settings-app `T`, files in assets/sounds).
    readonly property var soundFiles: ({
        Default: "00_teams_basic_notification_r4_default", DefaultUrgent: "00_teams_basic_notification_r4_default",
        Vibe: "a2_teams_basic_notification_r4_vibe", Nudge: "a3_teams_basic_notification_r4_nudge",
        Tap: "a4_teams_basic_notification_r4_tap", Flick: "a5_teams_basic_notification_r4_flick",
        Pluck: "a6_teams_basic_notification_r4_pluck", Summon: "a7_teams_basic_notification_r4_summon",
        Ping: "a8_teams_basic_notification_r4_ping", Prioritize: "b2_teams_urgent_notification_r4_prioritize",
        Escalate: "b3_teams_urgent_notification_r4_escalate", Alarm: "b4_teams_urgent_notification_r4_alarm"
    })
    // Teams' Preview button: play (stop while it plays), 32 x 31.3.
    component PreviewButton: Rectangle {
        id: pb
        property string file
        property string label: "Preview sound"
        width: 32; height: 31.3; radius: 4
        color: pbHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: preview.playing === pb.file ? "stop-20-filled" : "play-20"; size: 20; color: theme.text }
        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.previewSound(pb.file) }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // A sound dropdown (Teams' 248.7 x 30 at 443.3 in the row) and Preview.
    component SoundPicker: Item {
        id: sp
        property string setting
        property string dflt
        property var keys: []
        property string accessibleName
        readonly property string value: root.prop("userPersonalSettings", ["toastSettings", setting], dflt)
        x: 443.3; width: 281.3; height: 31.3
        OutlineDropdown {
            width: 248.7; height: 30
            options: sp.keys.map(k => ({ label: k === "DefaultUrgent" ? "Default" : k }))
            current: Math.max(0, sp.keys.indexOf(sp.value))
            accessibleName: sp.accessibleName
            onPicked: i => root.setProp("userPersonalSettings", "toastSettings." + sp.setting, sp.keys[i])
        }
        PreviewButton { x: 249.3; y: -0.6; file: root.soundFiles[sp.value] || root.soundFiles.Default }
    }

    // Recognition's consent line: the text, Learn More and Privacy Policy.
    component RecognitionConsent: Text {
        property string lead
        property string privacyName
        textFormat: Text.StyledText
        text: lead + " <a href=\"learn\">Learn More</a>. <a href=\"privacy\">Privacy Policy</a>"
        linkColor: theme.brandForeground1
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.textSecondary
        onLinkActivated: link => Qt.openUrlExternally(link === "learn"
            ? "https://learn.microsoft.com/en-us/microsoftteams/rooms/voice-and-face-recognition?branch=main#data-retention"
            : "https://myaccount.microsoft.com/settingsandprivacy/privacy")
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Accessible.role: Accessible.StaticText
        Accessible.name: lead + " Learn More. " + privacyName
    }
    // Recognition's 12/16 secondary text.
    component RecognitionSmall: Text {
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.textSecondary
    }

    component RecognitionCard: Rectangle {
        id: rc
        property string icon
        property string title
        property string about
        /// The consent (or retention) line before Learn More, or "".
        property string consent
        property string privacyName
        property real textWidth
        /// The status badge ("Face profile complete"), or "".
        property string badge
        /// The badge's sound-wave picture (a profile being generated).
        property bool badgeWave: false
        /// The buttons beside the text: [{label, x, act}], centred on it.
        property var topButtons: []
        /// The info tip after them (an i button at the right), or "".
        property string infoTip
        /// Teams' passive opt-in section (a voice profile made by hand).
        property bool optIn: false
        property string optInTitle
        property string optInAbout
        property string optInConsent
        /// The "Create/Update my … profile now" row and its buttons.
        property string rowLabel
        property var rowButtons: []
        signal act(string what)
        width: parent ? parent.width : 790
        height: (rowLabel ? rowCol.y + rowCol.height : optIn ? optInCol.y + optInCol.height : textCol.y + textCol.height) + 16.6
        radius: 8
        color: "transparent"
        border.color: theme.pick("#D1D1D1", "#3D3D3D"); border.width: 0.67
        FluentIcon { x: 12.7; y: 16.7; name: rc.icon; size: 20; color: theme.text }

        Column {
            id: textCol
            x: 44.7; y: 16.7; width: rc.textWidth
            Text {
                text: rc.title
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            RecognitionSmall { width: parent.width; text: rc.about }
            Item { visible: !!rc.consent; width: 1; height: 15 }
            RecognitionConsent { visible: !!rc.consent; width: parent.width; lead: rc.consent; privacyName: rc.privacyName }
            Item { visible: !!rc.badge; width: 1; height: 8 }
            // Teams' badge: #F5F5F5, radius 8, 4 x 8 padding, 4 gap.
            Rectangle {
                visible: !!rc.badge
                width: badgeRow.implicitWidth + 16; height: 24; radius: 8
                color: theme.pick("#F5F5F5", "#2E2E2E")
                Row {
                    id: badgeRow
                    x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    FluentIcon { visible: !rc.badgeWave; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-20"; size: 16; color: theme.brandFill }
                    // Teams' sound-wave picture: four bars.
                    Item {
                        visible: rc.badgeWave
                        width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: [[0, 1.71, 8.57], [2.86, 4.29, 3.43], [5.71, 0, 12], [8.57, 3.43, 5.14]]
                            delegate: Rectangle { required property var modelData; x: modelData[0]; y: modelData[1]; width: 0.95; height: modelData[2]; radius: 0.48; color: theme.brandFill }
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: rc.badge; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                }
            }
        }
        Repeater {
            model: rc.topButtons
            delegate: SettingsParts.Button {
                required property var modelData
                enabled: rc.enabled
                x: modelData.x; y: textCol.y + (textCol.height - height) / 2
                label: modelData.label
                onClicked: rc.act(modelData.act)
            }
        }
        Item {
            visible: !!rc.infoTip
            x: 745.7; y: textCol.y + (textCol.height - 31.3) / 2
            width: 31.3; height: 31.3
            FluentIcon { anchors.centerIn: parent; name: "info-20"; size: 20; color: theme.text }
            HoverHandler { id: infoHover }
            ToolTip.visible: infoHover.hovered
            ToolTip.text: rc.infoTip
            Accessible.role: Accessible.Button
            Accessible.name: rc.infoTip
        }

        // Teams' passive opt-in section.
        Column {
            id: optInCol
            visible: rc.optIn
            x: 44.7; y: textCol.y + textCol.height + 30; width: 484.3
            Text {
                width: parent.width
                text: rc.optInTitle
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            RecognitionSmall { width: parent.width; text: rc.optInAbout }
            Item { width: 1; height: 15 }
            RecognitionConsent { width: parent.width; lead: rc.optInConsent; privacyName: rc.privacyName }
        }
        SettingsParts.Button {
            visible: rc.optIn
            enabled: rc.enabled
            x: 591; y: optInCol.y + (optInCol.height - height) / 2
            label: "Start voice capture"
            onClicked: rc.act("optin")
        }

        Column {
            id: rowCol
            visible: !!rc.rowLabel
            x: 44.7; y: textCol.y + textCol.height + 30
            Text {
                text: rc.rowLabel
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            RecognitionSmall { text: "Takes about 30 seconds." }
        }
        Repeater {
            model: rc.rowLabel ? rc.rowButtons : []
            delegate: SettingsParts.Button {
                required property var modelData
                enabled: rc.enabled
                x: modelData.x; y: rowCol.y + (36 - height) / 2
                label: modelData.label
                onClicked: rc.act(modelData.act)
            }
        }
    }

    component AboutCard: Rectangle {
        id: ac
        property string icon
        property string title
        default property alias rows: acCol.data
        visible: root.page === "about"
        width: parent ? parent.width : 0
        height: 20.7 + 20 + acCol.height + 20.6
        radius: 8; color: "transparent"
        border.color: theme.pick("#D1D1D1", "#3D3D3D"); border.width: 0.67
        FluentIcon { visible: !!ac.icon; x: 18.7; y: (ac.height - 20) / 2; name: ac.icon; size: 20; color: theme.text }
        Image { visible: !ac.icon; x: 18.7; y: (ac.height - 20) / 2; width: 20; height: 20; source: "../assets/logo.png"; sourceSize: Qt.size(40, 40); smooth: true }
        Text { x: 56.7; y: 20.7; text: ac.title; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Column { id: acCol; x: 56.7; y: 40.7; width: ac.width - 113.4 }
        Accessible.role: Accessible.Grouping
        Accessible.name: title
    }
    component AboutLink: Row {
        id: al
        property string label
        property string url
        property bool external: true
        signal activated()
        height: 16.1; spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; text: al.label; font.family: theme.font; font.pixelSize: 14; color: alHover.hovered ? theme.brandHover : theme.brandForeground1; font.underline: alHover.hovered }
        FluentIcon { visible: al.external; anchors.verticalCenter: parent.verticalCenter; name: "open-16"; size: 16; color: theme.brandForeground1 }
        HoverHandler { id: alHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (al.url) Qt.openUrlExternally(al.url); else al.activated() } }
        Accessible.role: Accessible.Link
        Accessible.name: label + (external ? " (opens in new window)" : "")
        Accessible.onPressAction: { if (al.url) Qt.openUrlExternally(al.url); else al.activated() }
    }

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
                text: root.subPage === "oof" ? "Out of office" : root.subPage === "priority" ? "Manage priority access" : root.subPage === "blocked" ? "Manage blocked people" : root.subPage === "spellcheck" ? "Manage spellcheck languages" : root.subPage === "status" ? "Manage status notifications" : root.page === "about" ? "About OST" : (root.pages.find(p => p.key === root.page) || {}).label || ""
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
                bodyGap: 28
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
                bodyGap: 28
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
            // Teams' Language and regional formats card (measured on winpc
            // 2026-11-14): Follow OS settings (on: the choices show the OS's,
            // greyed), else App language (OST's text is English, so its
            // English locales), one of Teams' eight date formats and four
            // time formats, and Save and restart: they apply after a
            // restart, as in Teams. (Its "Manage Windows settings" link is
            // Windows' own.)
            SettingsParts.Card {
                id: regionalCard
                visible: root.page === "general" && !root.subPage
                icon: "local-language-20"; title: "Language and regional formats"
                subtitle: "Restart OST to apply language and regional format settings"
                property var opts: JSON.parse(backend.regionalOptionsJson())
                property bool followOs: opts.followOs
                property string appLanguage: opts.appLanguage
                property string dateFormat: opts.dateFormat || opts.os.dateFormat
                property string timeFormat: opts.timeFormat || opts.os.timeFormat
                onVisibleChanged: if (visible) reset()
                function reset() {
                    opts = JSON.parse(backend.regionalOptionsJson())
                    followOs = opts.followOs; appLanguage = opts.appLanguage
                    dateFormat = opts.dateFormat || opts.os.dateFormat; timeFormat = opts.timeFormat || opts.os.timeFormat
                }
                readonly property bool changed: followOs !== opts.followOs || (!followOs && (appLanguage !== opts.appLanguage || dateFormat !== (opts.dateFormat || opts.os.dateFormat) || timeFormat !== (opts.timeFormat || opts.os.timeFormat)))
                // Teams' samples: January 31 of this year, 1:01 to 23:59.
                function dateSample(p) { return Qt.formatDate(new Date(new Date().getFullYear(), 0, 31), p) }
                function timeSample(p) {
                    const q = p.replace(/tt/g, "AP"), y = new Date().getFullYear()
                    return Qt.formatTime(new Date(y, 0, 31, 1, 1), q) + " - " + Qt.formatTime(new Date(y, 0, 31, 23, 59), q)
                }
                // The current choice first, then the others in Teams' order.
                function ordered(list, cur) { return [cur].concat(list.filter(x => x !== cur)) }
                readonly property var dates: ordered(opts.dateFormats, followOs ? opts.os.dateFormat : dateFormat)
                readonly property var times: ordered(opts.timeFormats.map(t => t.short), followOs ? opts.os.timeFormat : timeFormat)
                SettingsParts.SwitchRow {
                    label: "Follow OS settings"
                    on: regionalCard.followOs
                    onToggled: v => regionalCard.followOs = v
                }
                // Teams' "Manage Windows settings": the desktop's own region
                // settings (KDE or GNOME), 15 under the switch.
                SettingsParts.Link {
                    visible: backend.hasOsSettings("region")
                    text: "Manage system settings"; font.pixelSize: 14
                    height: 16.1; verticalAlignment: Text.AlignVCenter
                    onClicked: backend.openOsSettings("region")
                    Accessible.role: Accessible.Link
                    Accessible.name: "Link to Manage your OS language and region settings"
                }
                SettingsParts.Gap { size: backend.hasOsSettings("region") ? 15 : 4 }
                SettingsParts.SubHeading { text: "App language" }
                SettingsParts.Gap { size: 10.6 }
                SearchCombobox {
                    width: 258.7; height: 30.7
                    enabled: !regionalCard.followOs
                    options: regionalCard.opts.languages.map(l => ({ key: l.code, label: l.nativeName, sublabel: l.name }))
                    current: regionalCard.followOs ? "" : regionalCard.appLanguage
                    accessibleName: "App language"
                    onPicked: code => regionalCard.appLanguage = code
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.SubHeading { text: "Date format" }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    enabled: !regionalCard.followOs
                    options: regionalCard.dates.map(p => ({ label: regionalCard.dateSample(p) }))
                    current: 0
                    accessibleName: "Date format"
                    onPicked: i => regionalCard.dateFormat = regionalCard.dates[i]
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.SubHeading { text: "Time format" }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    enabled: !regionalCard.followOs
                    options: regionalCard.times.map(p => ({ label: regionalCard.timeSample(p) }))
                    current: 0
                    accessibleName: "Time format"
                    onPicked: i => regionalCard.timeFormat = regionalCard.times[i]
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.Button {
                    visible: regionalCard.changed
                    x: -8
                    primary: true
                    label: regionalCard.followOs ? "Restart" : "Save and restart"
                    onClicked: backend.saveRegionalAndRestart(regionalCard.followOs, regionalCard.appLanguage, regionalCard.dateFormat, regionalCard.timeFormat)
                }
                SettingsParts.Gap { size: regionalCard.changed ? 10 : 0 }
            }
            // Teams' Time zone card (its "Manage Windows settings" link is
            // Windows' own).
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "globe-20"; title: "Time zone"
                subtitle: "You can adjust the time zone from your OS settings."
                SettingsParts.SubHeading { text: "Current time zone: " + backend.timeZoneName() }
                // Teams' "Manage Windows settings": the desktop's own date
                // and time settings (KDE or GNOME).
                SettingsParts.Link {
                    visible: backend.hasOsSettings("timezone")
                    text: "Manage system settings"; font.pixelSize: 14
                    height: 16.1; verticalAlignment: Text.AlignVCenter
                    onClicked: backend.openOsSettings("timezone")
                    Accessible.role: Accessible.Link
                    Accessible.name: "Link to Manage your OS time zone settings"
                }
                SettingsParts.Gap { size: backend.hasOsSettings("timezone") ? 15 : 8 }
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
            // Teams' Editor spellcheck card (measured on winpc 2026-11-14): Manage
            // opens Manage spellcheck languages; with languages chosen they
            // are listed as radios (the language whose options show). Your
            // languages and dictionary are kept by Microsoft Editor (AugLoop,
            // src/api/editor.rs).
            SettingsParts.Card {
                id: editorSpellCard
                visible: root.page === "general" && !root.subPage
                icon: "local-language-20"; title: "Editor spellcheck"
                subtitle: "Customize Editor to check for spelling and grammar improvements in up to three languages. If you'd like to include a different language or remove an old one, select Manage spellcheck languages."
                trailing: Component { SettingsParts.Button { label: "Manage"; onClicked: root.subPage = "spellcheck" } }
                property var st: JSON.parse(backend.editorSettingsJson())
                property string selected: ""
                Connections {
                    target: backend
                    function onEditorSettingsChanged() { editorSpellCard.st = JSON.parse(backend.editorSettingsJson()) }
                }
                onVisibleChanged: if (visible) backend.editorReadSettings()
                function nameOf(code) { const l = st.supported.find(x => x.code === code); return l ? l.native : code }
                Column {
                    width: parent.width
                    topPadding: editorSpellCard.st.languages.length ? 10 : 0
                    Repeater {
                        model: editorSpellCard.st.languages
                        SettingsParts.RadioRow {
                            required property string modelData
                            required property int index
                            label: editorSpellCard.nameOf(modelData)
                            checked: (editorSpellCard.selected || editorSpellCard.st.languages[0]) === modelData
                            onPicked: editorSpellCard.selected = modelData
                        }
                    }
                }
                // The chosen language's options (Teams' measured layout): Correct
                // words while typing, then each category's switch over its
                // checkboxes (greyed while the category is off).
                readonly property string optLang: selected || st.languages[0] || ""
                property var cats: []
                function loadCats() { cats = optLang ? JSON.parse(backend.editorCategoriesJson(optLang)).filter(c => c.priority <= 0) : [] }
                onOptLangChanged: loadCats()
                onStChanged: loadCats()
                function value(id, def) { const m = st.critiques[optLang]; return m && m[id] !== undefined ? Number(m[id]) : def }
                function setValue(id, v) {
                    const all = JSON.parse(JSON.stringify(st.critiques || {}))
                    all[optLang] = all[optLang] || {}
                    all[optLang][id] = String(v)
                    backend.setSetting("editorCritiques", JSON.stringify(all))
                }
                SettingsParts.Gap { size: editorSpellCard.optLang ? 15 : 0 }
                SettingsParts.SwitchRow {
                    visible: editorSpellCard.optLang !== ""
                    label: "Correct words while typing"
                    on: editorSpellCard.st.autocorrect.indexOf(editorSpellCard.optLang) >= 0
                    onToggled: v => {
                        const l = editorSpellCard.st.autocorrect.filter(x => x !== editorSpellCard.optLang)
                        backend.setSetting("editorAutoCorrect", JSON.stringify(v ? l.concat([editorSpellCard.optLang]) : l))
                    }
                }
                Repeater {
                    model: editorSpellCard.cats
                    Column {
                        id: catCol
                        required property var modelData
                        readonly property bool catOn: editorSpellCard.value(modelData.id, 1) === 1
                        // Its last row's 8 px gap, dropped when it ends the card.
                        readonly property real trailingGap: 8
                        width: parent.width
                        SettingsParts.SwitchRow {
                            label: catCol.modelData.name
                            on: catCol.catOn
                            height: 44
                            onToggled: v => editorSpellCard.setValue(catCol.modelData.id, v ? 1 : 0)
                        }
                        Repeater {
                            model: catCol.modelData.critiques.filter(t => t.priority <= 0 && t.binary)
                            SettingsParts.CheckRow {
                                required property var modelData
                                rowHeight: 40
                                label: modelData.name
                                usable: catCol.catOn
                                checked: editorSpellCard.value(modelData.id, modelData.default) === 1
                                onToggled: v => editorSpellCard.setValue(modelData.id, v ? 1 : 0)
                            }
                        }
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "calendar-arrow-right-20"; title: "Out of office"
                subtitle: "Schedule out of office and set automatic replies"
                trailing: Component { SettingsParts.Button { label: "Schedule"; onClicked: root.subPage = "oof" } }
            }
            // Teams' Keyboard shortcuts card: its profile dropdown (248.7 x
            // 30) — Teams only, + Slack, + Zoom, + combined — saved to the
            // synced keyboardShortcutsSettings.shortcutProfile.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: "Keyboard shortcuts"
                bodyGap: 10.6
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
                SettingsParts.Gap { size: 0.8 }
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
                bodyGap: 26
                subtitle: "This mode reduces processor, memory and network usage and is ideal for lower performance devices or those under heavy load. Turning this on may affect some functionality such as camera resolution."
                property string mode: root.local("efficiencyMode", "auto")
                function pick(m) { mode = m; backend.setSetting("efficiencyMode", m) }
                SettingsParts.RadioRow { label: "Use only when resources are low (Default)"; sublabel: "Reduce processor and memory usage when reduced resources are detected."; checked: efficiencyCard.mode === "auto"; onPicked: efficiencyCard.pick("auto") }
                SettingsParts.RadioRow { label: "Never use efficiency mode"; sublabel: "Prioritize a richer experience, using more system resources."; checked: efficiencyCard.mode === "off"; onPicked: efficiencyCard.pick("off") }
                SettingsParts.RadioRow { label: "Always use efficiency mode"; sublabel: "Reduce processor and memory use at all times."; checked: efficiencyCard.mode === "on"; onPicked: efficiencyCard.pick("on") }
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

            // ---- General ▸ Manage spellcheck languages (Teams', measured) ----
            // Your languages as 40 px rows over a divider (360 wide, with ···
            // Move up / Move down / Remove when there are several), then a
            // language picker (250 x 32) and Add (96 x 32) while fewer than three.
            SettingsParts.Card {
                id: spellManage
                visible: root.page === "general" && root.subPage === "spellcheck"
                icon: "local-language-20"; title: "Spellcheck languages"
                subtitle: "Select up to three languages you'd like Editor to work in. Make sure you select your preferred language at the top of the list."
                property var st: JSON.parse(backend.editorSettingsJson())
                property string pick: ""
                Connections {
                    target: backend
                    function onEditorSettingsChanged() { spellManage.st = JSON.parse(backend.editorSettingsJson()) }
                }
                onVisibleChanged: if (visible) { pick = ""; backend.editorReadSettings() }
                function nameOf(code) { const l = st.supported.find(x => x.code === code); return l ? l.native : code }
                function setLanguages(l) { backend.editorSetLanguages(JSON.stringify(l)) }
                SettingsParts.Gap { size: spellManage.st.languages.length ? 15 : 0 }
                Repeater {
                    model: spellManage.st.languages
                    Item {
                        id: langRow
                        required property string modelData
                        required property int index
                        width: 360; height: 40
                        Text { y: 9.6; text: spellManage.nameOf(langRow.modelData); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Rectangle {
                            visible: spellManage.st.languages.length > 1
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 4
                            color: moreHover.hovered || langMenu.opened ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.text }
                            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: langMenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "More options"
                            Menu {
                                id: langMenu
                                y: parent.height
                                MenuItem { visible: langRow.index > 0; height: visible ? implicitHeight : 0; text: "Move up"; onTriggered: { const l = spellManage.st.languages.slice(); l.splice(langRow.index - 1, 0, l.splice(langRow.index, 1)[0]); spellManage.setLanguages(l) } }
                                MenuItem { visible: langRow.index < spellManage.st.languages.length - 1; height: visible ? implicitHeight : 0; text: "Move down"; onTriggered: { const l = spellManage.st.languages.slice(); l.splice(langRow.index + 1, 0, l.splice(langRow.index, 1)[0]); spellManage.setLanguages(l) } }
                                MenuItem { text: "Remove"; onTriggered: spellManage.setLanguages(spellManage.st.languages.filter(x => x !== langRow.modelData)) }
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
                    }
                }
                SettingsParts.Gap { size: spellManage.st.languages.length ? 23.7 : 15 }
                Row {
                    visible: spellManage.st.languages.length < spellManage.st.max
                    spacing: 14
                    SearchCombobox {
                        width: 250; height: 32
                        options: spellManage.st.supported.filter(l => spellManage.st.languages.indexOf(l.code) < 0).map(l => ({ key: l.code, label: l.native, sublabel: l.english }))
                        current: spellManage.pick
                        accessibleName: "Select a spell check language"
                        placeholder: "Select a spell check language"
                        onPicked: code => spellManage.pick = code
                    }
                    SettingsParts.Button {
                        label: "Add"
                        height: 32
                        onClicked: if (spellManage.pick) { spellManage.setLanguages(spellManage.st.languages.concat([spellManage.pick])); spellManage.pick = "" }
                    }
                }
                SettingsParts.Gap { size: 10 }
            }

            // ---- Appearance ----
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "dark-theme-20"; title: "Theme"; subtitle: "This will apply to all your OST apps."
                bodyGap: 10.6
                OutlineDropdown {
                    width: 249.3; height: 30
                    readonly property var keys: ["system", "light", "dark", "classic"]
                    options: [{ label: "Follow operating system theme" }, { label: "Light" }, { label: "Dark" }, { label: "Classic" }]
                    current: Math.max(0, keys.indexOf(backend.themeMode))
                    accessibleName: "Theme"
                    onPicked: i => backend.setSetting("theme", keys[i])
                }
                // Teams: only in the Light theme.
                SettingsParts.Gap { size: 16.7 }
                SettingsParts.CheckRow {
                    rowHeight: 32
                    label: "Always use dark theme for calls and meetings"
                    usable: !theme.dark && !theme.classic
                    checked: window.darkCallSetting
                    onToggled: v => { backend.setSetting("darkCallTheme", v ? "true" : "false"); window.darkCallSetting = v }
                }
            }
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "emoji-hand-20"; title: "Skin tone preference"; subtitle: "Reactions and emoji will appear with this skin tone."
                // Teams' skin tone radios (measured on winpc 2026-11-14): 42 x
                // 50 each from 8 left of the text, a 30 px swatch 6 in and the
                // chosen one's 30 x 4 brand bar at 40.
                Row {
                    x: -8; spacing: 0
                    Repeater {
                        model: ["None", "Light", "Medium light", "Medium", "Medium dark", "Dark"]
                        Item {
                            required property string modelData
                            required property int index
                            readonly property bool on: backend.skinTone === index
                            width: 42; height: 50
                            Rectangle { x: 6; y: 6; width: 30; height: 30; radius: 15; color: ["#FFC83D", "#F7D7C4", "#D8B094", "#BB9167", "#8E562E", "#613D30"][index] }
                            Rectangle { visible: parent.on; x: 6; y: 40; width: 30; height: 4; radius: 2; color: theme.brand }
                            TapHandler { onTapped: { backend.changeSetting("prop", "preferredSkinToneIndex", JSON.stringify(String(index))); backend.skinTone = index } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData
                            Accessible.checked: on
                        }
                    }
                }
            }

            // Teams' App bar card (measured on winpc 2026-11-14).
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "panel-left-text-20"; title: "App bar"
                subtitle: "Customize your app bar layout and properties"
                SettingsParts.SwitchRow {
                    label: "Show app names"
                    on: window.appBarNames
                    onToggled: v => { backend.setSetting("appBarShowNames", v ? "true" : "false"); window.appBarNames = v }
                }
                SettingsParts.SwitchRow {
                    label: "Auto collapse app bar"
                    sublabel: "The app bar will automatically collapse after you select an app."
                    on: window.appBarAutoCollapse
                    onToggled: v => { backend.setSetting("appBarAutoCollapse", v ? "true" : "false"); window.appBarAutoCollapse = v }
                }
            }

            // ---- Chats and channels ----
            // Teams' "Viewing chats, teams, and channels" (measured): Combined
            // or Separate (Teams in its own app), the synced
            // simpleCollabUserSettings.
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "window-layout-20"; title: "Viewing chats, teams, and channels"
                bodyGap: 28
                subtitle: "See all conversations in a combined view, or keep chats separate from teams and channels."
                Row {
                    spacing: 12.7
                    readonly property bool separate: window.splitView
                    SettingsParts.ImageRadio { imageHeight: 80; label: "Combined"; image: "../assets/settings/simple-collab-picker-combined-" + theme.pick("light", "dark") + ".svg"; checked: !parent.separate
                        onPicked: backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ hasUserEnabledAdaptiveRailForDesktop: true, hasUserEnabledUnifiedAppForDesktop: true })) }
                    SettingsParts.ImageRadio { imageHeight: 80; label: "Separate"; image: "../assets/settings/simple-collab-picker-separate-" + theme.pick("light", "dark") + ".svg"; checked: parent.separate
                        onPicked: backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ hasUserEnabledAdaptiveRailForDesktop: true, hasUserEnabledUnifiedAppForDesktop: false })) }
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "apps-list-20"; title: "Chats and channels list"
                SettingsParts.SwitchRow {
                    label: "Show message previews for chats and team names for channels"
                    // Separate view has its own (on unless turned off).
                    on: window.splitView ? root.prop("simpleCollabUserSettings", ["hasUserEnabledMessagePreviewsForSplitApp"], true) !== false : root.prop("simpleCollabUserSettings", ["hasUserEnabledMessagePreviews"], false) === true
                    onToggled: v => root.setProp("simpleCollabUserSettings", window.splitView ? "hasUserEnabledMessagePreviewsForSplitApp" : "hasUserEnabledMessagePreviews", v)
                }
                SettingsParts.SwitchRow {
                    label: "Show time stamps"
                    // Always on in the Separate view (Teams greys it).
                    usable: !window.splitView
                    on: window.splitView || root.prop("simpleCollabUserSettings", ["hasUserEnabledShowTimeStamps"], false) === true
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
                SettingsParts.Gap { size: 12 }
                Row {
                    spacing: 12.7
                    readonly property string mode: root.prop("messageDensity", [], "COMFY")
                    SettingsParts.ImageRadio { label: "Comfy"; image: "../assets/settings/chat-density-comfy-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode !== "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMFY") }
                    SettingsParts.ImageRadio { label: "Compact"; image: "../assets/settings/chat-density-compact-" + theme.pick("default", "dark") + ".svg"; checked: parent.mode === "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMPACT") }
                }
                SettingsParts.SubHeading { text: "When I open a chat, take me to"; gapAbove: 15 }
                SettingsParts.Gap { size: 12 }
                Row {
                    spacing: 12.7
                    readonly property bool lastRead: root.prop("userPersonalSettings", ["messagingSettings", "navigateToLastReadMessage"], true) !== false
                    SettingsParts.ImageRadio { label: "Last read message"; image: "../assets/settings/chat-landing-unread-" + theme.pick("light", "dark") + ".svg"; checked: parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", true) }
                    SettingsParts.ImageRadio { label: "Newest message"; image: "../assets/settings/chat-landing-latest-" + theme.pick("light", "dark") + ".svg"; checked: !parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", false) }
                }
            }
            SettingsParts.Card {
                id: enterCard
                visible: root.page === "chats"
                icon: "keyboard-20"; title: "When writing a message, press Enter to"
                bodyGap: 26
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
                bodyGap: 26
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
                /// OST draws Teams' banners here (else the desktop's own
                /// notifications show, and place themselves).
                readonly property bool ownBanners: backend.bannerSupport() > 0
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
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: "General"; first: true }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
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
                visible: root.page === "notifications" && !root.subPage
                icon: "speaker-2-20"; title: "Sound"
                // Teams' last row keeps its 36 px label box.
                bottomPad: 23.6
                // Teams' rows (measured on winpc 2026-11-15): labels wrap at
                // 332.3, 44 apart (64 for two lines); the notification and
                // urgent sounds' dropdowns (248.7 x 30) and Preview sound
                // beside them.
                Item {
                    width: parent.width; height: soundRow.height
                    SettingsParts.CheckRow { id: soundRow; rowHeight: 44; labelWidth: 332.3; label: "Play sounds with notifications"; checked: root.prop("userPersonalSettings", ["soundsSettings", "alertSound"], "All") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.alertSound", v ? "All" : "Off") }
                    SoundPicker { y: 2.6; setting: "alertSoundType"; dflt: "Default"; keys: ["Default", "Vibe", "Nudge", "Tap", "Flick", "Pluck", "Summon", "Ping"]; accessibleName: "Notification sound" }
                }
                Item {
                    width: parent.width; height: urgentRow.height
                    SettingsParts.CheckRow { id: urgentRow; rowHeight: 44; labelWidth: 332.3; label: "Play sounds with urgent and priority contact notifications"; checked: notif.ts("PlayNotificationSoundsForUrgentAndPriority", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsForUrgentAndPriority", v ? "On" : "Off") }
                    SoundPicker { y: 2.6; setting: "alertUrgentSoundType"; dflt: "DefaultUrgent"; keys: ["DefaultUrgent", "Prioritize", "Escalate", "Alarm"]; accessibleName: "Urgent and priority contact notification sound" }
                }
                SettingsParts.CheckRow { rowHeight: 44; labelWidth: 332.3; label: "Play sounds with incoming calls, requests to join, and meeting start notifications"; checked: root.prop("userPersonalSettings", ["soundsSettings", "incomingCallsAndMeetingStartSound"], "On") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.incomingCallsAndMeetingStartSound", v ? "On" : "Off") }
                SettingsParts.CheckRow { rowHeight: 44; labelWidth: 332.3; label: "Play sounds when I'm busy or in a meeting"; checked: notif.ts("PlayNotificationSoundsWhenBusyOrInMeetings", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsWhenBusyOrInMeetings", v ? "On" : "Off") }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "eye-20"; title: "Display"
                trailing: Component { SettingsParts.Button { label: "Test notification"; onClicked: backend.testNotification() } }
                SettingsParts.CheckRow { rowHeight: 44; label: "Show message and content previews in notifications"; checked: notif.ts("ShowPreviewInToasts", "On") !== "Off"; onToggled: v => notif.setTs("ShowPreviewInToasts", v ? "On" : "Off") }
                SettingsParts.CheckRow { rowHeight: 44; label: "Show notifications during calls and meetings"; checked: notif.ts("MuteNotificationsDuringMeetings", "Off") !== "On"; onToggled: v => notif.setTs("MuteNotificationsDuringMeetings", v ? "Off" : "On") }
                SettingsParts.CheckRow { rowHeight: 44; label: "Flash taskbar when notifications are received"; checked: root.local("flashTaskbar", "true") !== "false"; onToggled: v => { backend.setSetting("flashTaskbar", v ? "true" : "false"); checked = v } }
                SettingsParts.SubHeading { text: "Dismiss notifications after this amount of time"; gapAbove: 4 }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    readonly property var secs: [5, 7, 15, 30, 60, 300]
                    options: [{ label: "5 seconds (Default)" }, { label: "7 seconds" }, { label: "15 seconds" }, { label: "30 seconds" }, { label: "1 minute" }, { label: "5 minutes" }]
                    current: Math.max(0, secs.indexOf(parseInt(root.local("toastSeconds", "5"))))
                    accessibleName: "Dismiss notifications after this amount of time"
                    onPicked: i => backend.setSetting("toastSeconds", String(secs[i]))
                }
                // Where OST's banners go and how big they are (Teams' own
                // pictures; only where OST draws its banners itself, see
                // NotificationBanners.qml).
                SettingsParts.SubHeading { visible: notif.ownBanners; text: "Position on the screen"; gapAbove: 12.7 }
                SettingsParts.Gap { visible: notif.ownBanners; size: 12 }
                Grid {
                    id: cornerTiles
                    visible: notif.ownBanners
                    columns: 3; columnSpacing: 12; rowSpacing: 12
                    property string corner: root.local("notificationCorner", "BR")
                    Repeater {
                        model: [{ key: "BR", label: "Bottom right" }, { key: "TR", label: "Top right" }, { key: "BL", label: "Bottom left" }, { key: "TL", label: "Top left" }]
                        delegate: SettingsParts.ImageRadio {
                            required property var modelData
                            imageHeight: 80
                            label: modelData.label
                            checked: cornerTiles.corner === modelData.key
                            image: "../assets/settings/notification-position-" + modelData.key.toLowerCase() + "-" + theme.pick("default", "dark") + "-" + (checked ? "active" : "inactive") + ".svg"
                            onPicked: { backend.setSetting("notificationCorner", modelData.key); cornerTiles.corner = modelData.key }
                        }
                    }
                }
                SettingsParts.SubHeading { visible: notif.ownBanners; text: "Size"; gapAbove: 12 }
                SettingsParts.Gap { visible: notif.ownBanners; size: 12 }
                Row {
                    id: sizeTiles
                    visible: notif.ownBanners
                    spacing: 12
                    property string size: root.local("notificationSize", "COMFY")
                    Repeater {
                        model: [{ key: "COMFY", label: "Comfy" }, { key: "COMPACT", label: "Compact" }]
                        delegate: SettingsParts.ImageRadio {
                            required property var modelData
                            imageHeight: 80
                            label: modelData.label
                            checked: sizeTiles.size === modelData.key
                            image: "../assets/settings/notification-style-" + modelData.key.toLowerCase() + "-" + theme.pick("default", "dark") + "-" + (checked ? "active" : "inactive") + ".svg"
                            onPicked: { backend.setSetting("notificationSize", modelData.key); sizeTiles.size = modelData.key }
                        }
                    }
                }
                SettingsParts.Gap { size: notif.ownBanners ? 1.1 : 20 }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "mail-20"; title: "Missed activity emails"
                pad: 16.3; bottomPad: 16.4; minHeader: 0; iconX: 16.7; titleX: 61.7
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
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: "Chats and channels" }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "chat-20"; title: "Chat message notifications"
                pad: 16.3; bottomPad: 16.4; minHeader: 0; iconX: 16.7; titleX: 61.7
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
                visible: root.page === "notifications" && !root.subPage
                icon: "mention-20"; title: "@Mentions"
                id: mentionsCard
                pad: 14.7; bodyGap: 33.3; bottomPad: 34.9
                // Teams' @Mentions switch (Global_Mention): on while any row
                // is above its off value (Off; Personal: Show in Activity) or
                // Global_Mention is on. Turning it on sets Personal to
                // Activity and banner and the rest to Activity; off, the
                // reverse floor. The rows are disabled while it's off.
                readonly property var rows: [
                    { label: "Channel and team @mentions", keys: ["Mention_Team", "Visible_ChannelMention_v2"], dflt: 0, off: true },
                    { label: "Tag @mentions", keys: ["Mention_Tag"], dflt: 0, off: true },
                    { label: "Everyone in chat @mentions", keys: ["MentionInChat_Everyone"], dflt: 0, off: true },
                    { label: "Personal @mentions", keys: ["Mention_Person", "MentionInChat_Person_v2"], dflt: 0, off: false }
                ]
                readonly property bool on: rows.some(r => notif.level(r.keys, r.dflt) !== (r.off ? 2 : 1)) || notif.level(["Global_Mention"], 0) !== 2
                function setAll(v) {
                    notif.setLevel(["Global_Mention"], v ? 0 : 2)
                    for (const r of rows) notif.setLevel(r.keys, r.off ? (v ? 1 : 2) : (v ? 0 : 1))
                }
                trailing: Component { SettingsParts.Toggle { on: mentionsCard.on; accessibleName: "@Mentions " + (mentionsCard.on ? "On" : "Off"); onToggled: v => mentionsCard.setAll(v) } }
                Repeater {
                    model: mentionsCard.rows
                    Item {
                        required property var modelData
                        // Teams: rows 68.7 apart, the label 5 under the
                        // dropdown's top and 6.6 in.
                        readonly property real trailingGap: 38.7
                        width: parent.width; height: 68.7
                        Text { x: 6.6; y: 5; text: modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: mentionsCard.on ? theme.text : theme.disabled }
                        OutlineDropdown {
                            anchors.right: parent.right; anchors.rightMargin: 28; y: 0
                            width: 249.3; height: 30
                            enabled: mentionsCard.on
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
                    visible: root.page === "notifications" && !root.subPage
                    icon: modelData.icon; title: modelData.title
                    pad: 16.3; bottomPad: 16.4; minHeader: 0; iconX: 16.7; titleX: 61.7
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
            // Teams' "Posts in all shown channels" (Visible_ChannelNewMessage_v2)
            // with "Include replies" (Visible_ChannelReplyMessage_v2), measured.
            SettingsParts.Card {
                id: shownPosts
                visible: root.page === "notifications" && !root.subPage
                icon: "channel-20"; title: "Posts in all shown channels"
                pad: 20; bottomPad: 28.7; minHeader: 0; bodyGap: 19.3; iconX: 16.3; titleX: 61.3
                readonly property int lvl: notif.level(["Visible_ChannelNewMessage_v2"], 2)
                trailing: Component {
                    OutlineDropdown {
                        width: 249.3; height: 30
                        options: notif.levels
                        current: shownPosts.lvl
                        accessibleName: "Posts in all shown channels"
                        onPicked: i => {
                            notif.setLevel(["Visible_ChannelNewMessage_v2"], i)
                            // Teams: replies follow the posts (off when the posts are).
                            if (i === 2) notif.setLevel(["Visible_ChannelReplyMessage_v2"], 2)
                        }
                    }
                }
                SettingsParts.CheckRow {
                    rowHeight: 32
                    label: "Include replies"
                    usable: shownPosts.lvl !== 2
                    checked: root.prop("userPersonalSettings", ["activityGenerationSettings", "Visible_ChannelReplyMessage_v2"], false) === true
                    onToggled: v => notif.setLevel(["Visible_ChannelReplyMessage_v2"], v ? shownPosts.lvl : 2)
                }
            }
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: "Meetings" }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "calendar-20"; title: "Meetings"
                pad: 22.7; minHeader: 20; bodyGap: 48; bottomPad: 18.7; iconX: 17.7; titleX: 55.7
                SettingsParts.SwitchRow { rowHeight: 61; label: "Meeting start notifications"; on: notif.ts("MeetingWentLiveNotification", true) !== false
                    onToggled: v => notif.setMany(v ? { toastSettings: { MeetingWentLiveNotification: true }, activityGenerationSettings: { MeetingWentLiveNotification: true }, emailSettings: { MeetingWentLiveNotification: true } } : { toastSettings: { MeetingWentLiveNotification: false } }) }
                SettingsParts.SwitchRow { rowHeight: 59.3; label: "Show meeting join bar"; on: notif.ts("liveMeetingStatusBanner", true) !== false; onToggled: v => notif.setTs("liveMeetingStatusBanner", v) }
                // Teams' meeting chat notifications by your RSVP (chatSettings:
                // Mute / Unmute / Mute until I join or send a message).
                Repeater {
                    model: [{ key: "meetingChatNotificationForAcceptedMeetings", label: "Meeting chat notifications for meetings I've accepted", dflt: "MeetingsUserIsInvitedTo" },
                            { key: "meetingChatNotificationForTentativeMeetings", label: "Meeting chat notifications for meetings marked as tentative or without a response", dflt: "MeetingsUserParticipatesIn" }]
                    Item {
                        id: mcRow
                        required property var modelData
                        readonly property var values: ["MeetingsManuallyUnmuted", "MeetingsUserIsInvitedTo", "MeetingsUserParticipatesIn"]
                        // Teams: the label 5 under the dropdown's top; rows 68.7
                        // apart, the two-line one 80.3.
                        width: parent.width; height: mcRow.modelData.key.indexOf("Tentative") > 0 ? 80.3 : 68.7
                        Text { id: mcLabel; y: 5; width: parent.width - 249.3 - 40; wrapMode: Text.Wrap; text: mcRow.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        OutlineDropdown {
                            anchors.right: parent.right; anchors.rightMargin: 28; y: 0
                            width: 249.3; height: mcRow.modelData.key.indexOf("Tentative") > 0 ? 50 : 30
                            options: [{ label: "Mute" }, { label: "Unmute" }, { label: "Mute until I join or send a message" }]
                            current: Math.max(0, mcRow.values.indexOf(root.prop("userPersonalSettings", ["chatSettings", mcRow.modelData.key], mcRow.modelData.dflt)))
                            accessibleName: mcRow.modelData.label
                            onPicked: i => root.setProp("userPersonalSettings", "chatSettings." + mcRow.modelData.key, mcRow.values[i])
                        }
                    }
                }
                SettingsParts.SwitchRow { label: "Meet now start notifications"; on: notif.ts("HuddleStartedNotification", false) === true; onToggled: v => notif.setTs("HuddleStartedNotification", v) }
            }

            // Teams' Presence: Manage notifications opens Manage status
            // notifications (Notify when available, contacts v3 "Tagged").
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: "Presence" }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "person-available-20"; title: "Presence"
                subtitle: "Keep track of someone's status and get notified when they appear available or offline."
                pad: 15.7; bottomPad: 15.6; minHeader: 0; iconX: 16.7; titleX: 58.7; textWidth: 494.2; subtitleSize: 14
                trailing: Component { SettingsParts.Button { label: "Manage notifications"; onClicked: root.subPage = "status" } }
            }
            SettingsParts.Card {
                id: statusNotif
                visible: root.page === "notifications" && root.subPage === "status"
                icon: "contact-card-20"; title: "Manage status notifications"
                subtitle: "Keep track of someone's status and get notified when they appear available or offline."
                property var tagged: []
                readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
                onVisibleChanged: if (visible) backend.channelAction("notify-tagged", "", "", "")
                // Teams' Add people box beside the title (371 x 41, filled, brand
                // underline while typing, measured), its matches under it.
                trailingY: 21; trailingRight: 12
                trailing: Component {
                    Rectangle {
                        width: 371; height: 41
                        color: theme.inputFilled; radius: 4
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: addPeople.activeFocus ? 2 : 0.67; color: addPeople.activeFocus ? theme.brand : theme.textSecondary }
                        TextInput {
                            id: addPeople
                            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                            onTextEdited: { peopleDelay.restart(); if (text.trim().length >= 2) matches.open(); else matches.close() }
                            Text { visible: !addPeople.text; text: "Add people"; font: addPeople.font; color: theme.textSecondary }
                            Keys.onEscapePressed: { text = ""; matches.close() }
                            Accessible.name: "Add people"
                        }
                        Timer { id: peopleDelay; interval: 300; onTriggered: if (addPeople.text.trim().length >= 2) backend.searchPeople(addPeople.text.trim()) }
                        Popup {
                            id: matches
                            y: parent.height + 2; width: parent.width; padding: 4
                            closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            contentItem: Column {
                                Repeater {
                                    model: backend.peopleJson ? JSON.parse(backend.peopleJson).slice(0, 6) : []
                                    Rectangle {
                                        required property var modelData
                                        width: matches.width - 8; height: 44; radius: 4
                                        color: pHover.hovered ? theme.menuHover : "transparent"
                                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name || ""; photoId: parent.modelData.id || "" }
                                        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; elide: Text.ElideRight; text: parent.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                        HoverHandler { id: pHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { backend.channelAction("notify-on", "", "", JSON.stringify({ mri: "8:orgid:" + parent.modelData.id })); addPeople.text = ""; matches.close() } }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.name || ""
                                    }
                                }
                            }
                        }
                    }
                }
                Connections {
                    target: backend
                    function onChannelActionResultChanged() {
                        const r = JSON.parse(backend.channelActionResult || "{}")
                        if (r.op === "notify-tagged" && r.ok) {
                            statusNotif.tagged = r.data || []
                            const want = statusNotif.tagged.map(t => t.mri).filter(m => !statusNotif.names[m])
                            if (want.length) backend.resolveNames(JSON.stringify(want))
                        } else if ((r.op === "notify-on" || r.op === "notify-off") && r.ok) backend.channelAction("notify-tagged", "", "", "")
                    }
                }
                SettingsParts.Gap { size: statusNotif.tagged.length ? 12 : 0 }
                Repeater {
                    model: statusNotif.tagged
                    Item {
                        id: tagRow
                        required property var modelData
                        width: Math.min(parent.width, 372); height: 48
                        readonly property string name: statusNotif.names[modelData.mri] || modelData.email || modelData.mri
                        Avatar { anchors.verticalCenter: parent.verticalCenter; size: 32; name: tagRow.name; photoId: tagRow.modelData.mri.replace(/^8:orgid:/, "") }
                        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 88; elide: Text.ElideRight; text: tagRow.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 4
                            color: rmHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.text }
                            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.channelAction("notify-off", "", "", JSON.stringify({ id: tagRow.modelData.id, mri: tagRow.modelData.mri, email: tagRow.modelData.email })) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + tagRow.name
                        }
                    }
                }
                SettingsParts.Gap { size: 8 }
            }

            // Teams' Calendar notifications: the Calendar app's Graph
            // notification settings (userGraphSettings), each choice setting its
            // group of meeting notification kinds.
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: "Calendar" }
            SettingsParts.Card {
                id: calNotif
                visible: root.page === "notifications" && !root.subPage
                icon: "calendar-20"; title: "Calendar"
                pad: 22.7; minHeader: 20; bodyGap: 19.3; bottomPad: 46; iconX: 17.7; titleX: 55.7
                readonly property string app: "ef56c0de-36fc-4ef8-b417-3d82ba9d073c"
                readonly property var groups: ({
                    privateMeetingCreated: ["privateMeetingCreated", "privateMeetingUpdated", "privateMeetingCanceled", "channelMeetingCreated", "channelMeetingUpdated", "channelMeetingCanceled", "delegateMeetingCreated", "delegateMeetingUpdated", "delegateMeetingCanceled", "privateMeetingForwarded", "channelMeetingForwarded", "channelMeetingForwardedWithoutOrganizer"],
                    privateMeetingForwardedNotification: ["privateMeetingForwardedNotification", "privateMeetingForwardedNotificationWithAttendee", "privateMeetingForwardedNotificationWithTwoAttendee", "privateMeetingForwardedNotificationWithAttendeeAndTotal"]
                })
                function lvl(key) {
                    const a = root.prop("userGraphSettings", [app, "activityGenerationSettings", key], true), t = root.prop("userGraphSettings", [app, "toastSettings", key], false)
                    return t === true ? 0 : a === false ? 2 : 1
                }
                function setLvl(key, i) {
                    const act = {}, toast = {}
                    for (const k of groups[key]) { act[k] = i !== 2; toast[k] = i === 0 }
                    backend.changeSetting("prop", "userGraphSettings", JSON.stringify({ [app]: { activityGenerationSettings: act, toastSettings: toast } }))
                }
                Repeater {
                    model: [{ key: "privateMeetingCreated", label: "New invites, updates and cancellations sent to me" }, { key: "privateMeetingForwardedNotification", label: "When people forward meetings I’ve organized" }]
                    Item {
                        id: calRow
                        required property var modelData
                        readonly property real trailingGap: 38.7
                        width: parent.width; height: 68.7
                        Text { y: 5; width: parent.width - 249.3 - 40; elide: Text.ElideRight; text: calRow.modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        OutlineDropdown {
                            anchors.right: parent.right; anchors.rightMargin: 28; y: 0
                            width: 249.3; height: 30
                            options: notif.levels
                            current: calNotif.lvl(calRow.modelData.key)
                            accessibleName: calRow.modelData.label
                            onPicked: i => calNotif.setLvl(calRow.modelData.key, i)
                        }
                    }
                }
            }

            // ---- Privacy ▸ Manage priority access / Manage blocked people ----
            // Teams' user-settings lists (breakthroughlist, blocklist): the
            // people, each removable; priority access adds people through
            // Teams' "Search for a name or number" picker (347 x 32).
            Item {
                id: peopleLists
                visible: root.page === "privacy" && (root.subPage === "priority" || root.subPage === "blocked")
                width: parent.width; height: listCol.height
                readonly property string list: root.subPage === "blocked" ? "blocked" : "priority"
                property var mris: []
                readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
                function load() { mris = []; backend.channelAction("people-list", "", "", JSON.stringify({ list: list })) }
                onVisibleChanged: if (visible) load()
                onListChanged: if (visible) load()
                Connections {
                    target: backend
                    function onChannelActionResultChanged() {
                        const r = JSON.parse(backend.channelActionResult || "{}")
                        if (r.op === "people-list" && r.ok && r.data && r.data.list === peopleLists.list) {
                            peopleLists.mris = r.data.mris || []
                            const want = peopleLists.mris.filter(m => !peopleLists.names[m])
                            if (want.length) backend.resolveNames(JSON.stringify(want))
                        } else if ((r.op === "people-list-add" || r.op === "people-list-remove") && r.ok) peopleLists.load()
                        else if ((r.op === "people-list-add" || r.op === "people-list-remove") && !r.ok) backend.toast("Something went wrong on our end. Please try again.", "error")
                    }
                }
                Column {
                    id: listCol
                    width: parent.width
                    spacing: 0
                    // Blocked: Teams' page is two lines of text, then the people.
                    Column {
                        visible: peopleLists.list === "blocked"
                        width: parent.width
                        topPadding: 20
                        spacing: 30
                        Text { width: parent.width; wrapMode: Text.Wrap; text: "When you block someone, they can't call you, message you, or see your presence."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { visible: peopleLists.mris.length === 0; width: parent.width; wrapMode: Text.Wrap; text: "When you block people, you'll see them listed below."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                    SettingsParts.Card {
                        id: priorityCard
                        visible: peopleLists.list === "priority"
                        icon: "presence-dnd-20"; title: "Manage priority access"
                        subtitle: "When your status is set to Do not disturb, you can still receive notifications for chats, calls, and @mentions from the people below."
                        trailingY: 21; trailingRight: 24.7
                        trailing: Component {
                            Rectangle {
                                width: 347; height: 32; radius: 4
                                color: theme.surface
                                border.color: prioField.activeFocus ? theme.brand : theme.stroke; border.width: 0.67
                                FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-16"; size: 16; color: theme.textSecondary }
                                TextInput {
                                    id: prioField
                                    x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                                    onTextEdited: { prioDelay.restart(); if (text.trim().length >= 2) prioMatches.open(); else prioMatches.close() }
                                    Text { visible: !prioField.text; text: "Search for a name or number"; font: prioField.font; color: theme.textSecondary }
                                    Keys.onEscapePressed: { text = ""; prioMatches.close() }
                                    Accessible.name: "Search for a name or number"
                                }
                                Timer { id: prioDelay; interval: 300; onTriggered: if (prioField.text.trim().length >= 2) backend.searchPeople(prioField.text.trim()) }
                                Popup {
                                    id: prioMatches
                                    y: parent.height + 2; width: parent.width; padding: 4
                                    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                                    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                                    contentItem: Column {
                                        Repeater {
                                            model: backend.peopleJson ? JSON.parse(backend.peopleJson).slice(0, 6) : []
                                            Rectangle {
                                                required property var modelData
                                                width: prioMatches.width - 8; height: 44; radius: 4
                                                color: ppHover.hovered ? theme.menuHover : "transparent"
                                                Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name || ""; photoId: parent.modelData.id || "" }
                                                Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; elide: Text.ElideRight; text: parent.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                                HoverHandler { id: ppHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: { backend.channelAction("people-list-add", "", "", JSON.stringify({ list: "priority", mri: "8:orgid:" + parent.modelData.id })); prioField.text = ""; prioMatches.close() } }
                                                Accessible.role: Accessible.Button
                                                Accessible.name: modelData.name || ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    SettingsParts.Gap { size: peopleLists.mris.length ? 12 : 0 }
                    Repeater {
                        model: peopleLists.mris
                        Item {
                            id: plRow
                            required property string modelData
                            width: Math.min(listCol.width, 560); height: 48
                            readonly property string name: peopleLists.names[modelData] || ""
                            Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: plRow.name || "?"; photoId: plRow.modelData.replace(/^8:orgid:/, "") }
                            Text { x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 170; elide: Text.ElideRight; text: plRow.name || plRow.modelData; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            SettingsParts.Button {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                label: peopleLists.list === "blocked" ? "Unblock" : "Remove"
                                onClicked: backend.channelAction("people-list-remove", "", "", JSON.stringify({ list: peopleLists.list, mri: plRow.modelData }))
                            }
                        }
                    }
                }
            }

            // ---- Accounts and orgs (Teams', measured on winpc 2026-11-14) ----
            // Your account (64 avatar, name, e-mail) with Refresh license and
            // restart and Manage (your Microsoft account page), then your
            // organisation, the active one marked with the brand bar.
            Rectangle {
                id: accountCard
                visible: root.page === "accounts"
                width: parent.width; height: 120.7
                radius: 8; color: theme.surface
                border.color: theme.pick("#D1D1D1", "#3D3D3D"); border.width: 0.67
                clip: true
                Avatar { x: 10.7; y: 10.7; size: 56; name: backend.userName || "?"; photoId: "me"; presence: titleBar.presence }
                Column {
                    x: 76.7; y: 20.7
                    Text { text: backend.userName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Text { text: backend.userMail; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                }
                Rectangle {
                    id: refreshBtn
                    x: parent.width - 158.7; y: 21.2
                    width: 32; height: 32; radius: 4
                    color: refreshHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
                    border.color: theme.pick("#D1D1D1", "#5C5C5C"); border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; name: "arrow-clockwise-20"; size: 20; color: theme.text }
                    HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.restartApp() }
                    ToolTip {
                        visible: refreshHover.hovered; delay: 500
                        y: -height - 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: "Refresh license and restart"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Refresh license and restart"
                }
                Rectangle {
                    x: parent.width - 118.7; y: 21.2
                    width: 96; height: 32; radius: 4
                    color: manageHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
                    border.color: theme.pick("#D1D1D1", "#5C5C5C"); border.width: 0.67
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Manage"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "open-16"; size: 14; color: theme.text }
                    }
                    HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://myaccount.microsoft.com/?login_hint=" + encodeURIComponent(backend.userMail)) }
                    Accessible.role: Accessible.Link
                    Accessible.name: "Manage Account for " + backend.userName + " (opens in browser)"
                }
                Rectangle { y: 72; width: parent.width; height: 0.67; color: theme.pick("#D1D1D1", "#3D3D3D") }
                Rectangle {
                    x: 0.67; y: 72.67; width: parent.width - 1.33; height: 47.3
                    color: theme.pick("#FAFAFA", "#242424")
                    Rectangle { x: 2; y: 4; width: 3; height: parent.height - 8; radius: 1.5; color: theme.brand }
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: backend.orgName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: backend.orgName
                }
            }

            // ---- Privacy ----
            // Manage my work location (Teams' presence-location card): with
            // the tenant's work-location detection policy off, Teams says so;
            // where your work hours and location are set, in Outlook.
            SettingsParts.Card {
                id: workLocationCard
                // (ECS answers aren't notified: read again each time Privacy opens.)
                readonly property bool shown: root.page === "privacy" && !root.subPage
                readonly property bool detection: shown && backend.ecsSetting("places", "enableWorkLocationDetectionPolicy") === "true" && backend.ecsSetting("places", "enableAutoDetectPlaceWifi") === "true"
                readonly property string outlookUrl: { if (!shown) return ""; const v = backend.ecsSetting("presence", "outlookLocationSettingUrl"); return v ? JSON.parse(v) : "" }
                readonly property bool outlookLink: shown && backend.ecsSetting("presence", "enableWorkLocationSettingsLink") === "true" && outlookUrl.length > 0
                visible: root.page === "privacy" && !root.subPage && (!detection || outlookLink)
                icon: "building-home-20"; title: "Manage my work location"
                subtitleLineHeight: 17.14
                subtitle: (detection ? "" : "Automatically setting your work location has been turned off by your IT department. <a href=\"https://support.microsoft.com/en-us/office/first-things-to-know-about-bookable-desks-in-microsoft-teams-5d10c217-1205-48a1-a883-ff4533f4ae71?preview=true\">Learn more</a>")
                    + (!detection && outlookLink ? "<br>" : "")
                    + (outlookLink ? "Your work location will be shared with Places and Outlook. Manage more preferences in Outlook. <a href=\"" + outlookUrl + "\">Open Outlook work hours and location settings</a>" : "")
                onLinkActivated: l => Qt.openUrlExternally(l)
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "presence-dnd-20"; title: "Do not disturb"
                subtitle: "You can still receive notifications from people who have priority access when your status is set to Do not disturb."
                trailing: Component { SettingsParts.Button { label: "Manage priority contacts"; onClicked: root.subPage = "priority" } }
                SettingsParts.CheckRow {
                    label: "Set my status to do not disturb when I'm sharing my screen"
                    sublabel: "Turning this setting off will change your status to busy and let you receive calls, as well as urgent and priority contact notifications."
                    checked: root.mt.allowAutoDnd !== false
                    onToggled: on => root.setMt("allowAutoDnd", on)
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "person-prohibited-20"; title: "Blocked contacts"
                subtitle: "Blocked contacts will be unable to call you, message you, or see your presence."
                trailing: Component { SettingsParts.Button { label: "Manage blocked contacts"; onClicked: root.subPage = "blocked" } }
                SettingsParts.CheckRow {
                    label: "Block calls with no caller ID"
                    checked: root.mt.blockAnonymousCaller === true
                    onToggled: on => root.setMt("blockAnonymousCaller", on)
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "clipboard-task-list-20"; title: "Surveys"; subtitle: "Participate in surveys from OST."
                trailing: Component { SettingsParts.Toggle { on: root.prop("userEnableSurveysNotification", [], "true") !== "false"; accessibleName: "Surveys"; onToggled: v => root.setProp("userEnableSurveysNotification", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "video-person-off-20"; title: "Turn off my camera and mic when my screen locks"
                subtitle: "If your screen locks due to inactivity while you're in a meeting, your camera, mic, and screensharing will automatically turn off. Restart OST to apply this setting."
                trailing: Component { SettingsParts.Toggle { on: backend.setting("turnOffMediaOnDeviceLock") === "true"; accessibleName: "Turn off my camera and mic when my screen locks"; onToggled: v => { backend.setSetting("turnOffMediaOnDeviceLock", v ? "true" : "false"); on = v } } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "data-area-20"; title: "Extended diagnostics data"
                subtitle: "Enable the application to store a larger duration of diagnostics data for debugging purposes."
                trailing: Component { SettingsParts.Toggle { on: backend.setting("shouldPersistLogsIntoIDB") === "true"; accessibleName: "Extended diagnostics data"; onToggled: v => { backend.setSetting("shouldPersistLogsIntoIDB", v ? "true" : "false"); on = v } } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "people-list-20"; title: "Identify me in attendance reports"; subtitle: "Let meeting or event organizer know your attendance information."
                trailing: Component { SettingsParts.Toggle { on: root.prop("showInMeetingReport", [], "true") !== "false"; accessibleName: "Identify me in attendance reports"; onToggled: v => root.setProp("showInMeetingReport", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "image-sparkle-20"; title: "Optional connected experiences"
                subtitle: "Enhance your OST experience with cloud-backed services, including Giphy, URL Preview, and more. <a href=\"https://go.microsoft.com/fwlink/?linkid=2295907\">Learn More</a><br><a href=\"https://privacy.microsoft.com/privacystatement\">Microsoft Privacy Statement</a>"
                onLinkActivated: l => Qt.openUrlExternally(l)
                trailing: Component { SettingsParts.Toggle { on: root.prop("controllerConnectedServicesEnabled", [], "true") !== "false"; accessibleName: "Optional connected experiences"; onToggled: v => root.setProp("controllerConnectedServicesEnabled", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
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
            // Teams' Muted notification (clientPreferences meeting.mutedDialogs,
            // on this device): the same setting as the call's Accessibility
            // pane, so a call in progress follows it at once.
            SettingsParts.Card {
                visible: root.page === "accessibility"
                icon: "mic-off-20"; title: "Muted notification"
                subtitle: "Show the 'You're muted' notification when audio is detected while your microphone is off."
                trailing: Component { SettingsParts.Toggle { on: backend.setting("showMutedNotice") !== "false"; accessibleName: "Muted notification"; onToggled: v => { backend.setSetting("showMutedNotice", v ? "true" : "false"); on = v; callWindow.showMutedNotice = v } } }
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
                property var vm: ({ vmUseOof: false, vmUseAutoRepliesForOof: false, vmCallAnswerRule: "", vmAudioLang: "", vmDefaultGreetingPromptOverwrite: "", vmDefaultOofGreetingPromptOverwrite: "" })
                // Teams' voicemail greeting languages (measured on winpc
                // 2026-11-14, in its order): [native, English, code].
                readonly property var greetingLanguages: [
                    ["Arabic (Egypt)", "Arabic (Egypt)", "ar-eg"], ["Bahasa Indonesia (Indonesia)", "Indonesian (Indonesia)", "id-id"],
                    ["Català (Català)", "Catalan (Spain)", "ca-es"], ["Čeština (Česká republika)", "Czech (Czechia)", "cs-cz"],
                    ["Dansk (Danmark)", "Danish (Denmark)", "da-dk"], ["Deutsch (Deutschland)", "German (Germany)", "de-de"],
                    ["English (Australia)", "English (Australia)", "en-au"], ["English (Canada)", "English (Canada)", "en-ca"],
                    ["English (India)", "English (India)", "en-in"], ["English (United Kingdom)", "English (United Kingdom)", "en-gb"],
                    ["English (United States)", "English (United States)", "en-us"], ["Español (España, alfabetización internacional)", "Spanish (Spain)", "es-es"],
                    ["Español (México)", "Spanish (Mexico)", "es-mx"], ["Français (Canada)", "French (Canada)", "fr-ca"],
                    ["Français (France)", "French (France)", "fr-fr"], ["Hrvatski (Hrvatska)", "Croatian (Croatia)", "hr-hr"],
                    ["Italiano (Italia)", "Italian (Italy)", "it-it"], ["Magyar (Magyarország)", "Hungarian (Hungary)", "hu-hu"],
                    ["Nederlands (Nederland)", "Dutch (Netherlands)", "nl-nl"], ["Norsk, Bokmål (Norge)", "Norwegian Bokmål (Norway)", "nb-no"],
                    ["Polski (Polska)", "Polish (Poland)", "pl-pl"], ["Português (Brasil)", "Portuguese (Brazil)", "pt-br"],
                    ["Português (Portugal)", "Portuguese (Portugal)", "pt-pt"], ["Română (România)", "Romanian (Romania)", "ro-ro"],
                    ["Slovenčina (Slovenská republika)", "Slovak (Slovakia)", "sk-sk"], ["Slovenščina (Slovenija)", "Slovenian (Slovenia)", "sl-si"],
                    ["Suomi (Suomi)", "Finnish (Finland)", "fi-fi"], ["Svenska (Sverige)", "Swedish (Sweden)", "sv-se"],
                    ["Türkçe (Türkiye)", "Turkish (Türkiye)", "tr-tr"], ["Ελληνικά (Ελλάδας)", "Greek (Greece)", "el-gr"],
                    ["Русский (Россия)", "Russian (Russia)", "ru-ru"], ["ไทย (ไทย)", "Thai (Thailand)", "th-th"],
                    ["한국어 (대한민국)", "Korean (Korea)", "ko-kr"], ["中文(中国)", "Chinese (China)", "zh-cn"],
                    ["中文(台灣)", "Chinese (Taiwan)", "zh-tw"], ["中文(香港特別行政區)", "Chinese (Hong Kong SAR)", "zh-hk"],
                    ["日本語 (日本)", "Japanese (Japan)", "ja-jp"]
                ]
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
                bottomPad: 21.4
                SettingsParts.SwitchRow {
                    label: "Forward all calls to voicemail"
                    on: calls.forwardAll
                    onToggled: v => calls.save(v, calls.toVoicemail, calls.delay)
                }
                SettingsParts.Divider { visible: !calls.forwardAll }
                SettingsParts.SubHeading { visible: !calls.forwardAll; text: "When you can't answer a call"; gapAbove: 15.6 }
                SettingsParts.Gap { visible: !calls.forwardAll; size: 10 }
                OutlineDropdown {
                    visible: !calls.forwardAll
                    width: 293.3; height: 30
                    options: [{ label: "Do not redirect calls" }, { label: "Redirect to voicemail" }]
                    current: calls.toVoicemail ? 1 : 0
                    accessibleName: "When you can't answer a call"
                    onPicked: i => calls.save(false, i === 1, calls.delay)
                }
                SettingsParts.SubHeading { visible: !calls.forwardAll && calls.toVoicemail; text: "Ring for this many seconds before redirect"; gapAbove: 15.7 }
                SettingsParts.Gap { visible: !calls.forwardAll && calls.toVoicemail; size: 10 }
                OutlineDropdown {
                    visible: !calls.forwardAll && calls.toVoicemail
                    width: 293.3; height: 30
                    readonly property var secs: [5, 10, 15, 20, 30, 40, 50, 60]
                    options: secs.map(n => ({ label: n + " seconds" + (n === 20 ? " (default)" : "") }))
                    current: Math.max(0, secs.indexOf(calls.delay))
                    accessibleName: "Ring for this many seconds before redirect"
                    onPicked: i => calls.save(false, true, secs[i])
                }
                // Teams' "Choose a ringtone for you" (measured on winpc
                // 2026-11-15): 31.4 under the row above, the dropdown
                // (Teams' 18 ringtones, Ring as "Default") with Preview
                // ringtone 10.7 after it; saved with Teams' ringtone
                // settings and rung by Main.qml's ringer.
                SettingsParts.SubHeading { text: "Choose a ringtone for you"; gapAbove: 32 }
                SettingsParts.Gap { size: 10.6 }
                Row {
                    spacing: 10.7
                    readonly property var names: ["Ring", "Beep", "Bop", "Bounce", "Bubbles", "BubblesLoud", "DripDrop", "Eureka", "Flutter", "HighScore", "NextLevel", "Plink", "Remix", "RingRing", "Ripple", "Spacetime", "WishGranted", "Wobble"]
                    readonly property var labels: ["Default", "Beep", "Bop", "Bounce", "Bubbles", "Bubbles (Loud)", "Drip Drop", "Eureka", "Flutter", "High Score", "Next Level", "Plink", "Remix", "Ring Ring", "Ripple", "Spacetime", "Wish Granted", "Wobble"]
                    readonly property string chosen: {
                        const voice = root.mt.voice || {}
                        const list = ((voice.ringtoneSettings || {}).assignments || {}).ringToneAssignments || []
                        const own = list.find(a => a.type === "Regular")
                        return own && own.value ? own.value : "Ring"
                    }
                    OutlineDropdown {
                        width: 293.3; height: 30
                        options: parent.labels.map(l => ({ label: l }))
                        current: Math.max(0, parent.names.indexOf(parent.chosen))
                        accessibleName: "Choose a ringtone for you"
                        onPicked: i => backend.changeSetting("mt", "ringtone", JSON.stringify(parent.names[i]))
                    }
                    PreviewButton { height: 30; label: "Preview ringtone"; file: parent.chosen.toLowerCase() }
                }
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
                // Teams' "Record a custom greeting" calls your voicemail
                // (TASK-0152). Voicemail settings can't be read back (Teams
                // shows them unset too); what you set here shows.
                SettingsParts.SubHeading { text: "Choose a language for your default greeting" }
                SettingsParts.Gap { size: 10.7 }
                SearchCombobox {
                    width: 258.7; height: 30.7
                    options: calls.greetingLanguages.map(l => ({ key: l[2], label: l[0], sublabel: l[1] }))
                    current: calls.vm.vmAudioLang || ""
                    accessibleName: "Choose a language for your default greeting"
                    onPicked: code => calls.setVm("vmAudioLang", code)
                }
                SettingsParts.Gap { size: 15.6 }
                SettingsParts.Divider {}
                SettingsParts.SubHeading { text: "Choose what happens when the call is redirected to voicemail"; gapAbove: 15.7 }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    readonly property var rules: ["RegularVoicemail", "PromptOnly", "DeclineCall"]
                    options: [{ label: "Let the caller record a message" }, { label: "Play your greeting and end the call" }, { label: "End the call without playing your greeting" }]
                    current: rules.indexOf(calls.vm.vmCallAnswerRule)
                    placeholder: "Choose what happens when the call is redirected to voicemail"
                    accessibleName: "Choose what happens when the call is redirected to voicemail"
                    onPicked: i => calls.setVm("vmCallAnswerRule", rules[i])
                }
                SettingsParts.Gap { size: 15.6 }
                SettingsParts.Divider {}
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.ButtonRow {
                    label: "Set up text-to-speech customized greeting option"
                    sublabel: "If you\u2019ve recorded a greeting, it\u2019ll override this option."
                    buttonText: calls.vm.vmDefaultGreetingPromptOverwrite ? "Edit custom greeting" : "Write a custom greeting"
                    onClicked: { greetingDialog.oof = false; greetingDialog.show(calls.vm.vmDefaultGreetingPromptOverwrite || "") }
                }
                
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
                SettingsParts.Gap { size: 15 }
                SettingsParts.CheckRow { label: "All the time"; checked: calls.vm.vmUseOof === true; onToggled: v => calls.setVm("vmUseOof", v) }
                SettingsParts.CheckRow { label: "When Outlook automatic replies are on"; checked: calls.vm.vmUseAutoRepliesForOof === true; onToggled: v => calls.setVm("vmUseAutoRepliesForOof", v) }
                SettingsParts.ButtonRow {
                    label: "Your custom greeting"
                    buttonText: calls.vm.vmDefaultOofGreetingPromptOverwrite ? "Edit custom greeting" : "Write a custom greeting"
                    onClicked: { greetingDialog.oof = true; greetingDialog.show(calls.vm.vmDefaultOofGreetingPromptOverwrite || "") }
                }
                
            }
            GreetingDialog {
                id: greetingDialog
                property bool oof: false
                onSaved: text => calls.setVm(oof ? "vmDefaultOofGreetingPromptOverwrite" : "vmDefaultGreetingPromptOverwrite", text)
            }

            // ---- Recognition (Teams' biometric-enrollment app, measured on
            // winpc 2026-11-15): two cards 35 apart, 8 lower than other
            // pages' first card; a bold 14 px title over 12/16 secondary
            // text, the consent (or retention) line with Learn More and
            // Privacy Policy, a status badge; the card's top control centred
            // on that text (voice: Start voice capture, which opts you in to
            // passive enrollment, then Opt out; face: Opt out once you have
            // a profile), and the "Create/Update my … profile now" row.
            // Profiles: api::biometric (Teams' biometric service). ----
            Column {
                id: recognition
                objectName: "cardGroup"
                visible: root.page === "recognition"
                width: parent ? parent.width : 790
                topPadding: 8
                spacing: 35
                readonly property var st: backend.recognitionJson ? JSON.parse(backend.recognitionJson) : ({})
                readonly property bool inCall: backend.callState !== "" && backend.callState !== "ended"
                onVisibleChanged: if (visible) backend.loadRecognition()
                // Teams: "You are currently in a meeting…" and no changes.
                Rectangle {
                    visible: recognition.inCall
                    width: parent.width; height: 36; radius: 4
                    color: theme.pick("#FDF3F4", "#3F1011")
                    border.color: theme.pick("#EEACB2", "#6E0811"); border.width: 0.67
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "error-circle-20-filled"; size: 16; color: theme.pick("#BC2F32", "#DC626D") }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: "You are currently in a meeting. To modify your profile, please return after your meeting."; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                }
                    // Teams' voice card, by whether you have a profile and whether
                // you opted in to keeping it up to date from your calls
                // (passive enrollment):
                // - neither: the consent text and Start voice capture (opt in);
                // - opted in: "Generating voice profile", Opt out, Create;
                // - a profile: "Voice profile complete", Export, Opt out (i),
                //   and the opt-in section;
                // - both: "Voice profile complete", Opt out (i), Export, Update.
                RecognitionCard {
                    readonly property bool enrolled: !!recognition.st.voice
                    readonly property bool joined: !!recognition.st.passiveVoice
                    icon: "mic-20-filled"; title: "Voice Recognition"
                    enabled: !recognition.inCall && !!recognition.st.loaded
                    textWidth: !enrolled && !joined ? 484.3 : enrolled && !joined ? 416.7 : 532.7
                    about: enrolled && !joined
                        ? "Your voice profile is used to suppress background noises in Teams meetings through voice isolation and to identify you in meeting rooms, transcripts, and notes."
                        : "Microsoft Teams, on behalf of your organization, collects and processes your pitch, inflection, and speech patterns to build and update your unique voice profile, which may be considered biometric data. Your voice profile is used to suppress background noises in Teams meetings through voice isolation and to identify you in meeting rooms, transcripts, and notes."
                    consent: enrolled && !joined ? ""
                        : joined ? "Your voice profile will be retained as described in the data retention section of this"
                        : "When you click \u201cStart voice capture\u201d you are consenting to the collection and use of your data. Your voice profile will be retained as described in the data retention section of this"
                    privacyName: "Privacy policy - Voice recognition"
                    badge: enrolled ? "Voice profile complete" : joined ? "Generating voice profile" : ""
                    badgeWave: !enrolled
                    topButtons: !enrolled && !joined ? [{ label: "Start voice capture", x: 591, act: "optin" }]
                        : enrolled && !joined ? [{ label: "Export", x: 523.3, act: "export" }, { label: "Opt out", x: 634.3, act: "optout" }]
                        : [{ label: "Opt out", x: 639.3, act: "optout" }]
                    infoTip: enrolled ? "Opting out will remove your voice profile, disabling all features that use it." : ""
                    optIn: enrolled && !joined
                    optInTitle: "Opt in to keep my voice profile up to date automatically"
                    optInAbout: "Microsoft Teams, on behalf of your organization, collects and processes your pitch, inflection, and speech patterns to build and update your unique voice profile, which may be considered biometric data."
                    optInConsent: "When you click \u201cStart voice capture\u201d you are consenting to the collection and use of your data. Your voice profile will be retained as described in the data retention section of this"
                    rowLabel: joined ? (enrolled ? "Update my voice profile now" : "Create my voice profile now") : ""
                    rowButtons: enrolled ? [{ label: "Export", x: 533.3, act: "export" }, { label: "Update", x: 639.3, act: "capture" }]
                                         : [{ label: "Create", x: 639.3, act: "capture" }]
                    onAct: what => {
                        if (what === "optin") backend.recognitionPassiveVoice(true)
                        else if (what === "optout") { if (joined) backend.recognitionPassiveVoice(false); else backend.recognitionRemoveVoice() }
                        else if (what === "export") backend.recognitionExport("voice")
                        else root.startRecognition("voice")
                    }
                }
                RecognitionCard {
                    readonly property bool enrolled: !!recognition.st.face
                    icon: "video-person-20-filled"; title: "Face Recognition"
                    enabled: !recognition.inCall && !!recognition.st.loaded
                    textWidth: enrolled ? 527.7 : 572.7
                    about: "Microsoft Teams, on behalf of your organization, collects and processes facial data to build and update your unique face profile, which may be considered biometric data. Your face profile is used to automatically recognize you during meetings, display your name, and add your name to the participant list as you walk into a Microsoft Teams Rooms with supported equipment."
                    consent: enrolled ? "Your face profile will be retained as described in the data retention section of this"
                                      : "When you click \u201cStart face capture\u201d, you are consenting to the collection and use of your data. Your face profile will be retained as described in the data retention section of this"
                    privacyName: "Privacy policy - Face recognition"
                    badge: enrolled ? "Face profile complete" : ""
                    topButtons: enrolled ? [{ label: "Opt out", x: 634.3, act: "optout" }] : []
                    infoTip: enrolled ? "Opting out will remove your face profile, disabling all features that use it." : ""
                    rowLabel: enrolled ? "Update my face profile now" : "Create my face profile now"
                    rowButtons: enrolled ? [{ label: "Export", x: 528.3, act: "export" }, { label: "Update", x: 639.3, act: "capture" }]
                                         : [{ label: "Start face capture", x: 597.9, act: "capture" }]
                    onAct: what => {
                        if (what === "optout") backend.recognitionRemoveFace()
                        else if (what === "export") backend.recognitionExport("face")
                        else root.startRecognition("face")
                    }
                }
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
                bodyGap: 26
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
                SettingsParts.SubHeading { text: "Always open web links in:" }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    options: linksPref.browsers.map(b => ({ label: b.label }))
                    current: Math.max(0, linksPref.browsers.findIndex(b => b.key === linksPref.choice))
                    accessibleName: "Always open web links in"
                    onPicked: i => backend.setSetting("linkBrowser", linksPref.browsers[i].key)
                }
                
            }
            SettingsParts.Card {
                visible: root.page === "files"
                icon: "image-20"; title: "File previews"
                subtitle: "Show preview cards for files shared in chats, channels, and groups, including files you share."
                trailing: Component { SettingsParts.Toggle { on: root.prop("userPersonalSettings", ["filesSettings", "enableThumbnailPreview"], true) !== false; accessibleName: "File previews"; onToggled: v => root.setProp("userPersonalSettings", "filesSettings.enableThumbnailPreview", v) } }
            }

            // ---- About (Teams' About Teams, measured on winpc 2026-11-14) ----
            // Four cards, 20.7 padding, the 20 px glyph at 18.7 centred on
            // the text: Version (the app's mark), Legal information, Privacy
            // and cookies, Third party notice. OST's own documents stand in
            // for Microsoft's; Teams' "Web" notices have no OST counterpart,
            // and OST has no release channel to check for updates yet.
            AboutCard {
                title: "Version"
                Text {
                    width: parent.width; height: 20.7; verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: "You have OST version <b>" + Qt.application.version + "</b>."
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "An open-source client for Microsoft Teams. Not affiliated with or endorsed by Microsoft."
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 18.7; lineHeightMode: Text.FixedHeight; color: theme.textSecondary
                }
            }
            AboutCard {
                icon: "info-20"; title: "Legal information"
                AboutLink { label: "OST Legal Information"; url: "https://github.com/RandyNorthrup/ost/blob/main/LICENSE" }
            }
            AboutCard {
                icon: "cookies-20"; title: "Privacy and cookies"
                AboutLink { label: "OST Privacy Statement"; url: "https://github.com/RandyNorthrup/ost/blob/main/PRIVACY.md" }
            }
            AboutCard {
                icon: "document-text-20"; title: "Third party notice"
                AboutLink { label: "Desktop"; external: false; onActivated: { const u = backend.thirdPartyNoticesUrl(); if (u) Qt.openUrlExternally(u) } }
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
    // Teams' section headings (Notifications and activity, measured on
    // winpc 2026-11-14): 14/700 on a 20 px line, 18 above and below (the
    // first one 6, and 8 under the page's top), cards 12 above.
    component SectionTitle: Text {
        property bool first: false
        width: parent ? parent.width : 0
        height: first ? 52 : 44
        topPadding: first ? 14 : 18
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight
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
    function greetingDialogForTest() { return greetingDialog }
    /// Each visible card on the page: [y in the window, height, first text].
    function cardsForTest() {
        const out = []
        const all = []
        for (let i = 0; i < pageCol.children.length; i++) {
            const c = pageCol.children[i]
            if (c.objectName === "cardGroup" && c.visible) { for (let j = 0; j < c.children.length; j++) all.push(c.children[j]) }
            else all.push(c)
        }
        for (const c of all) {
            if (!c.visible || c.radius !== 8 || c.height <= 0) continue
            let t = c.title !== undefined ? c.title : ""
            out.push([Math.round(c.mapToItem(null, 0, 0).y * 10) / 10, Math.round(c.height * 10) / 10, t])
        }
        return out
    }
    /// The visible texts of the card titled `title` as [y, height, text]
    /// relative to the card (rows compared with Teams' cardrows dump).
    function cardRowsForTest(title) {
        const all = []
        for (let i = 0; i < pageCol.children.length; i++) {
            const c = pageCol.children[i]
            if (c.objectName === "cardGroup") { for (let j = 0; j < c.children.length; j++) all.push(c.children[j]) }
            else all.push(c)
        }
        const card = all.find(c => c.visible && c.radius === 8 && c.title === title)
        if (!card) return []
        const out = []
        const walk = it => {
            for (const ch of it.children) {
                if (!ch.visible) continue
                if (ch.text !== undefined && typeof ch.text === "string" && ch.text.length && ch.width > 0)
                    out.push([Math.round(ch.mapToItem(card, 0, 0).y * 10) / 10, Math.round(ch.height * 10) / 10, ch.text.slice(0, 40)])
                walk(ch)
            }
        }
        walk(card)
        return out.sort((a, b) => a[0] - b[0])
    }
    function scrollToForTest(y) { content.contentY = y }
    /// Editor spellcheck (the Editor card's links): General scrolled to it,
    /// or its Manage spellcheck languages page.
    function showEditor(manage) {
        page = "general"
        subPage = manage ? "spellcheck" : ""
        content.contentY = 0
        if (!manage) Qt.callLater(() => { content.contentY = Math.max(0, Math.min(pageCol.y + editorSpellCard.y - 12, content.contentHeight - content.height)) })
    }
    /// Test hooks: General scrolled to Language and regional formats; the card.
    function scrollToRegionalForTest() { content.contentY = Math.max(0, Math.min(pageCol.y + regionalCard.y - 12, content.contentHeight - content.height)) }
    function regionalForTest() { return regionalCard }
    /// Test hook: General scrolled to the Translation card.
    function openTranslationTargetForTest(open) { if (open) translationTargetBox.openList(); else translationTargetBox.closeList() }
    function scrollToTranslationForTest() { content.contentY = Math.max(0, Math.min(pageCol.y + translationCard.y - 12, content.contentHeight - content.height)) }
}
