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
        { key: "general", label: qsTr("General"), icon: "settings-20" },
        { key: "appearance", label: qsTr("Appearance"), icon: "wand-20" },
        { key: "chats", label: qsTr("Chats and channels"), icon: "chat-20" },
        { key: "notifications", label: qsTr("Notifications and activity"), icon: "alert-20" },
        { key: "accounts", label: qsTr("Accounts and orgs"), icon: "contact-card-20" },
        { key: "privacy", label: qsTr("Privacy"), icon: "lock-closed-20" },
        { key: "accessibility", label: qsTr("Accessibility"), icon: "accessibility-20" },
        { key: "devices", label: qsTr("Devices"), icon: "headset-20" },
        { key: "calls", label: qsTr("Calls"), icon: "call-20" },
        { key: "files", label: qsTr("Files and links"), icon: "document-20" },
        { key: "apppermissions", label: qsTr("App permissions"), icon: "shield-20" },
        { key: "recognition", label: qsTr("Recognition"), icon: "slide-text-20" },
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
    /// Teams' feedback form (a Teams Labs feature turned off asks for a
    /// thumbs-down): kind, area, context.
    signal feedbackRequested(string kind, string area, string context)

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
    /// Their names as Teams shows them.
    readonly property var soundLabels: ({
        Default: qsTr("Default"), DefaultUrgent: qsTr("Default"), Vibe: qsTr("Vibe"), Nudge: qsTr("Nudge"), Tap: qsTr("Tap"),
        Flick: qsTr("Flick"), Pluck: qsTr("Pluck"), Summon: qsTr("Summon"), Ping: qsTr("Ping"),
        Prioritize: qsTr("Prioritize"), Escalate: qsTr("Escalate"), Alarm: qsTr("Alarm")
    })
    // Teams' Preview button: play (stop while it plays), 32 x 31.3.
    component PreviewButton: Rectangle {
        id: pb
        property string file
        property string label: qsTr("Preview sound")
        width: 32; height: 31.3; radius: 4
        color: pbHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: preview.playing === pb.file ? "stop-20-filled" : "play-20"; size: 20; color: theme.onFill(pb, theme.text) }
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
            options: sp.keys.map(k => ({ label: root.soundLabels[k] || k }))
            current: Math.max(0, sp.keys.indexOf(sp.value))
            accessibleName: sp.accessibleName
            onPicked: i => root.setProp("userPersonalSettings", "toastSettings." + sp.setting, sp.keys[i])
        }
        PreviewButton { x: 249.3; y: -0.6; file: root.soundFiles[sp.value] || root.soundFiles.Default }
    }

    // Recognition's consent line: the text with its <a>Learn More</a>, and
    // Privacy Policy.
    component RecognitionConsent: Text {
        property string lead
        property string privacyName
        textFormat: Text.StyledText
        text: lead.replace("<a>", "<a href=\"learn\">") + " <a href=\"privacy\">" + qsTr("Privacy Policy") + "</a>"
        linkColor: theme.brandForeground1
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.textSecondary
        onLinkActivated: link => Qt.openUrlExternally(link === "learn"
            ? "https://learn.microsoft.com/en-us/microsoftteams/rooms/voice-and-face-recognition?branch=main#data-retention"
            : "https://myaccount.microsoft.com/settingsandprivacy/privacy")
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Accessible.role: Accessible.StaticText
        Accessible.name: lead.replace(/<[^>]+>/g, "") + " " + privacyName
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
        /// The consent (or retention) line ending in <a>Learn More</a>., or "".
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
        border.color: theme.pick("#D1D1D1", "#3D3D3D", "#FFFFFF"); border.width: 0.67
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
                color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
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
            label: qsTr("Start voice capture")
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
            RecognitionSmall { text: qsTr("Takes about 30 seconds.") }
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
        border.color: theme.pick("#D1D1D1", "#3D3D3D", "#FFFFFF"); border.width: 0.67
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
        Accessible.name: external ? qsTr("%1 (opens in new window)").arg(label) : label
        Accessible.onPressAction: { if (al.url) Qt.openUrlExternally(al.url); else al.activated() }
    }

    // Left: title, find box, pages.
    Rectangle {
        id: nav
        width: 380; height: parent.height
        color: theme.pane
        Text {
            x: 32; y: 20
            text: qsTr("Settings")
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
                Text { visible: !find.text; text: qsTr("Find in Settings") + " (Ctrl+F)"; color: theme.textSecondary; font: find.font }
                Accessible.name: qsTr("Find in Settings")
            }
        }
        Shortcut { sequence: "Ctrl+F"; enabled: root.visible; onActivated: find.forceActiveFocus() }
        component NavItem: Rectangle {
            id: ni
            property var def
            readonly property bool sel: root.page === def.key
            width: 346; height: 32; radius: 4
            color: sel ? theme.hc(theme.surface, theme.hcHighlight) : nh.hovered ? theme.rowHover : "transparent"
            border.color: sel ? Qt.rgba(0, 0, 0, 0.05) : "transparent"; border.width: 0.67
            FluentIcon { x: 16.7; anchors.verticalCenter: parent.verticalCenter; size: 20; name: ni.sel ? ni.def.icon + "-filled" : ni.def.icon; color: theme.onFill(ni, ni.sel ? theme.brand : theme.textStrong) }
            Text {
                x: 49.7; anchors.verticalCenter: parent.verticalCenter
                text: ni.def.label
                font.family: theme.font; font.pixelSize: 14
                font.weight: nh.hovered && !ni.sel ? Font.DemiBold : Font.Normal
                color: theme.onFill(ni, ni.sel ? theme.text : theme.textStrong)
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
        NavItem { x: 17; y: parent.height - 49; def: ({ key: "about", label: qsTr("About OST"), icon: "info-20" }) }
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
                text: root.subPage === "channelNotifs" ? qsTr("Manage") : root.subPage === "oof" ? qsTr("Out of office") : root.subPage === "priority" ? qsTr("Manage priority access") : root.subPage === "blocked" ? qsTr("Manage blocked people") : root.subPage === "spellcheck" ? qsTr("Manage spellcheck languages") : root.subPage === "status" ? qsTr("Manage status notifications") : root.subPage === "connected" ? qsTr("Manage devices") : root.subPage === "stationary" ? qsTr("Stationary device location") : root.subPage === "ddv" ? qsTr("Diagnostic data viewer") : root.subPage === "interpreters" ? qsTr("Manage interpreters") : root.page === "about" ? qsTr("About OST") : (root.pages.find(p => p.key === root.page) || {}).label || ""
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
        // Teams' About header button when an update is available: Update
        // now (OST: the release's page, to get it).
        SettingsParts.Button {
            readonly property var u: backend.updateJson ? JSON.parse(backend.updateJson) : ({})
            visible: root.page === "about" && u.state === "available"
            primary: true
            anchors.right: parent.right; anchors.rightMargin: Math.max(22, content.width - pageCol.x - pageCol.width)
            y: 14.8
            label: qsTr("Update now")
            onClicked: if (u.url) Qt.openUrlExternally(u.url)
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
                icon: "settings-20"; title: qsTr("System")
                SettingsParts.CheckRow {
                    label: qsTr("Auto-start OST")
                    checked: root.local("autoStart", "false") === "true"
                    onToggled: on => { backend.setSetting("autoStart", on ? "true" : "false"); checked = on }
                }
                SettingsParts.CheckRow {
                    label: qsTr("Open application in background")
                    checked: root.local("openInBackground", "false") === "true"
                    onToggled: on => { backend.setSetting("openInBackground", on ? "true" : "false"); checked = on }
                }
                SettingsParts.CheckRow {
                    label: qsTr("On close, keep the application running")
                    checked: root.local("keepRunning", "true") !== "false"
                    onToggled: on => { backend.setSetting("keepRunning", on ? "true" : "false"); checked = on }
                }
            }
            // Teams' "Opening content in Teams windows" (measured on winpc
            // 2026-11-20, Teams 26304): the two pictures (148 x 88, 24.6
            // under the header, labels 4 under them), then a table (24.7
            // under the labels): "Content" (14/700) with Main window and New
            // window columns 108 wide from 346.5 in, a 29 tall header and
            // 32 tall rows, each row a radio pair centred in its columns.
            // Rows: notifications and links (Teams' client preference
            // windowing.shouldOpenContentInNewWindow, kept on this device)
            // and new chats (the synced alwaysPopOutNewChat).
            SettingsParts.Card {
                id: windowModeCard
                visible: root.page === "general" && !root.subPage
                icon: "chat-multiple-20"; title: qsTr("Opening content in OST windows")
                bodyGap: 24.6
                subtitle: qsTr("Choose to open the following content in either the main window or a new window. This will only apply to this account.")
                property string contentMode: root.local("openContentIn", "main")
                readonly property bool chatPopout: root.prop("userPersonalSettings", ["messagingSettings", "alwaysPopOutNewChat"], false) === true
                readonly property string variant: theme.classic ? "classic" : theme.pick("default", "dark", "contrast")
                Row {
                    x: 8.3; spacing: 28
                    Repeater {
                        model: [{ key: "mainwindow", label: qsTr("Main window") }, { key: "popout", label: qsTr("New window") }]
                        Column {
                            required property var modelData
                            spacing: 4
                            Image { width: 148; height: 88; source: "../assets/settings/new-chat-" + modelData.key + "-" + windowModeCard.variant + ".svg"; sourceSize: Qt.size(296, 176); fillMode: Image.PreserveAspectFit }
                            Text { width: 146.7; text: modelData.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        }
                    }
                }
                SettingsParts.Gap { size: 24.7 }
                Item {
                    width: parent.width; height: 29
                    Text { width: 346.5; height: 29; verticalAlignment: Text.AlignVCenter; text: qsTr("Content"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Text { x: 346.5; width: 108; height: 29; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; text: qsTr("Main window"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Text { x: 454.5; width: 108; height: 29; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; text: qsTr("New window"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                }
                Repeater {
                    model: [{ key: "content", label: qsTr("Notifications and links to chats, channels, and messages") },
                            { key: "chats", label: qsTr("New chats") }]
                    Item {
                        id: wmRow
                        required property var modelData
                        width: parent.width; height: 32
                        readonly property bool popout: modelData.key === "content" ? windowModeCard.contentMode === "popout" : windowModeCard.chatPopout
                        function choose(p) {
                            if (modelData.key === "content") { backend.setSetting("openContentIn", p ? "popout" : "main"); windowModeCard.contentMode = p ? "popout" : "main" }
                            else root.setProp("userPersonalSettings", "messagingSettings.alwaysPopOutNewChat", p)
                        }
                        Text { width: 346.5; height: 32; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: wmRow.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Repeater {
                            model: [false, true]
                            Item {
                                required property bool modelData
                                x: 346.5 + (modelData ? 108 : 0) + 38; width: 32; height: 32
                                SettingsParts.Dot { anchors.centerIn: parent; checked: wmRow.popout === parent.modelData; hovered: wmHover.hovered }
                                HoverHandler { id: wmHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: wmRow.choose(parent.modelData) }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: wmRow.modelData.label + ", " + (modelData ? qsTr("New window") : qsTr("Main window"))
                                Accessible.checked: wmRow.popout === modelData
                            }
                        }
                    }
                }
            }
            // Teams' Meeting card (measured on winpc 2026-11-16). "New
            // meeting controls" is a Teams Labs feature (OptIn): Teams keeps
            // it on this device only (its cache storage), so OST keeps it in
            // its local settings; on, the meeting window uses Teams' new
            // controls (InlineCentered). Turning it off opens Teams'
            // thumbs-down feedback form (OST's, sent to its GitHub).
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "video-20"; title: qsTr("Meeting")
                SettingsParts.SwitchRow {
                    id: newControlsRow
                    label: qsTr("New meeting controls")
                    sublabel: qsTr("Meetings are easier than ever with a simplified, organized, and intuitive experience.")
                    on: root.local("newMeetingControls", "false") === "true"
                    onToggled: v => {
                        backend.setSetting("newMeetingControls", v ? "true" : "false")
                        newControlsRow.on = v
                        if (!v) root.feedbackRequested("problem", "New meeting controls", "Turned off New meeting controls")
                    }
                }
                SettingsParts.SwitchRow {
                    id: leaveRow
                    label: qsTr("Ask me to confirm when I leave a meeting")
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
                icon: "local-language-20"; title: qsTr("Language and regional formats")
                subtitle: qsTr("Please restart OST to apply language settings. Date and time format settings are applied automatically.")
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
                function dateSample(p) { return theme.fmtDate(new Date(new Date().getFullYear(), 0, 31), p) }
                function timeSample(p) {
                    const q = p.replace(/tt/g, "AP"), y = new Date().getFullYear()
                    return theme.fmtTime(new Date(y, 0, 31, 1, 1), q) + " - " + theme.fmtTime(new Date(y, 0, 31, 23, 59), q)
                }
                // The current choice first, then the others in Teams' order.
                function ordered(list, cur) { return [cur].concat(list.filter(x => x !== cur)) }
                readonly property var dates: ordered(opts.dateFormats, followOs ? opts.os.dateFormat : dateFormat)
                readonly property var times: ordered(opts.timeFormats.map(t => t.short), followOs ? opts.os.timeFormat : timeFormat)
                SettingsParts.SwitchRow {
                    label: qsTr("Follow OS settings")
                    on: regionalCard.followOs
                    onToggled: v => regionalCard.followOs = v
                }
                // Teams' "Manage Windows settings": the desktop's own region
                // settings (KDE or GNOME), 15 under the switch.
                SettingsParts.Link {
                    visible: backend.hasOsSettings("region")
                    text: qsTr("Manage OS settings", "framework:k2ui0wj94"); font.pixelSize: 14
                    height: 16.1; verticalAlignment: Text.AlignVCenter
                    onClicked: backend.openOsSettings("region")
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
                SettingsParts.Gap { size: backend.hasOsSettings("region") ? 15 : 4 }
                SettingsParts.SubHeading { text: qsTr("App language") }
                SettingsParts.Gap { size: 10.6 }
                SearchCombobox {
                    width: 258.7; height: 30.7
                    enabled: !regionalCard.followOs
                    options: regionalCard.opts.languages.map(l => ({ key: l.code, label: l.nativeName, sublabel: l.name }))
                    current: regionalCard.followOs ? "" : regionalCard.appLanguage
                    accessibleName: qsTr("App language")
                    onPicked: code => regionalCard.appLanguage = code
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.SubHeading { text: qsTr("Date format") }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    enabled: !regionalCard.followOs
                    options: regionalCard.dates.map(p => ({ label: regionalCard.dateSample(p) }))
                    current: 0
                    accessibleName: qsTr("Date format")
                    onPicked: i => regionalCard.dateFormat = regionalCard.dates[i]
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.SubHeading { text: qsTr("Time format") }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    enabled: !regionalCard.followOs
                    options: regionalCard.times.map(p => ({ label: regionalCard.timeSample(p) }))
                    current: 0
                    accessibleName: qsTr("Time format")
                    onPicked: i => regionalCard.timeFormat = regionalCard.times[i]
                }
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.Button {
                    visible: regionalCard.changed
                    x: -8
                    primary: true
                    label: regionalCard.followOs ? qsTr("Restart") : qsTr("Save and restart")
                    onClicked: backend.saveRegionalAndRestart(regionalCard.followOs, regionalCard.appLanguage, regionalCard.dateFormat, regionalCard.timeFormat)
                }
                SettingsParts.Gap { size: regionalCard.changed ? 10 : 0 }
            }
            // Teams' Time zone card (its "Manage Windows settings" link is
            // Windows' own).
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "globe-20"; title: qsTr("Time zone")
                subtitle: qsTr("You can adjust the time zone from your OS settings.")
                SettingsParts.SubHeading { text: qsTr("Current time zone: %1").arg(backend.timeZoneName()) }
                // Teams' "Manage Windows settings": the desktop's own date
                // and time settings (KDE or GNOME).
                SettingsParts.Link {
                    visible: backend.hasOsSettings("timezone")
                    text: qsTr("Manage OS settings", "framework:k7ikk1urg"); font.pixelSize: 14
                    height: 16.1; verticalAlignment: Text.AlignVCenter
                    onClicked: backend.openOsSettings("timezone")
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Link to Manage your OS time zone settings")
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
                icon: "translate-20-filled"; title: qsTr("Translation")
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
                SettingsParts.SubHeading { text: qsTr("Translate messages into this language") }
                SettingsParts.Gap { size: 10 }
                SearchCombobox {
                    id: translationTargetBox
                    width: 294; height: 32
                    options: translationCard.languages.map(l => ({ key: l.code, label: l.native, sublabel: l.english }))
                    current: translationCard.settings.target
                    accessibleName: qsTr("Translate messages into this language")
                    onPicked: code => {
                        // Your new language is one you never translate.
                        const known = translationCard.settings.known.filter(k => k !== code).concat([code])
                        translationCard.save("translationTarget", code)
                        translationCard.save("translationKnown", JSON.stringify(known))
                    }
                }
                SettingsParts.Gap { size: 15 }
                SettingsParts.SubHeading { text: qsTr("How to handle messages in other languages") }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    width: 294; height: 31.3
                    options: [{ label: qsTr("Ask me before translating") }, { label: qsTr("Auto-translate all messages") }, { label: qsTr("Never Translate") }]
                    current: Math.max(0, translationCard.modes.indexOf(translationCard.settings.mode))
                    accessibleName: qsTr("How to handle messages in other languages")
                    onPicked: i => translationCard.save("translationMode", translationCard.modes[i])
                }
                SettingsParts.Gap { size: 15 }
                SettingsParts.SubHeading { text: qsTr("Never translate messages in these languages") }
                SettingsParts.Gap { size: 10 }
                OutlineDropdown {
                    id: addLanguage
                    width: 294; height: 31.3
                    maxListHeight: 332
                    placeholder: qsTr("Add another language")
                    current: -1
                    readonly property var choices: translationCard.languages.filter(l => translationCard.settings.known.indexOf(l.code) < 0 && l.code !== translationCard.settings.target)
                    options: choices.map(l => ({ label: l.name }))
                    accessibleName: qsTr("Never translate messages in these languages")
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
                            color: chipHover.hovered && removable ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                            border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                            Row {
                                id: chipRow
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { anchors.verticalCenter: parent.verticalCenter; text: translationCard.nameOf(chip.modelData); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(chip, theme.text) }
                                FluentIcon { visible: chip.removable; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-20"; size: 20; color: theme.onFill(chip, theme.text) }
                            }
                            HoverHandler { id: chipHover; enabled: chip.removable; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: chip.removable; onTapped: translationCard.save("translationKnown", JSON.stringify(translationCard.settings.known.filter(k => k !== chip.modelData))) }
                            Accessible.role: chip.removable ? Accessible.Button : Accessible.StaticText
                            Accessible.name: chip.removable ? qsTr("Remove %1 from known languages").arg(translationCard.nameOf(chip.modelData)) : translationCard.nameOf(chip.modelData)
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
                icon: "local-language-20"; title: qsTr("Editor spellcheck")
                subtitle: qsTr("Customize Editor to check for spelling and grammar improvements in up to three languages. If you'd like to include a different language or remove an old one, select Manage spellcheck languages.")
                trailing: Component { SettingsParts.Button { label: qsTr("Manage"); onClicked: root.subPage = "spellcheck" } }
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
                    label: qsTr("Correct words while typing")
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
                icon: "calendar-arrow-right-20"; title: qsTr("Out of office")
                subtitle: qsTr("Schedule out of office and set automatic replies")
                trailing: Component { SettingsParts.Button { label: qsTr("Schedule"); onClicked: root.subPage = "oof" } }
            }
            // Teams' Keyboard shortcuts card: its profile dropdown (248.7 x
            // 30) — Teams only, + Slack, + Zoom, + combined — saved to the
            // synced keyboardShortcutsSettings.shortcutProfile.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: qsTr("Keyboard shortcuts")
                bodyGap: 10.6
                subtitle: qsTr("Use OST shortcuts, or combine them with those of other apps.") + " <a href=\"shortcuts\">" + qsTr("See available keyboard shortcuts") + "</a>"
                onLinkActivated: root.showShortcuts()
                OutlineDropdown {
                    width: 248.7; height: 30
                    readonly property var keys: ["default", "chats_alt", "meetings_alt", "chats_meetings_alt"]
                    readonly property string current_: {
                        let v = root.props.keyboardShortcutsSettings
                        if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { v = null } }
                        return (v && v.shortcutProfile) || "default"
                    }
                    options: [{ label: qsTr("OST only (default)") }, { label: qsTr("OST + Slack shortcuts") }, { label: qsTr("OST + Zoom shortcuts") }, { label: qsTr("OST + combined shortcuts") }]
                    current: Math.max(0, keys.indexOf(current_))
                    accessibleName: qsTr("Keyboard shortcuts")
                    onPicked: i => root.setProp("keyboardShortcutsSettings", "shortcutProfile", keys[i])
                }
                SettingsParts.Gap { size: 0.8 }
            }

            // Teams' "Use Enter or Spacebar to show content" (the synced
            // messagingSettings.disableAutomaticConvSwitchOnKeyboardNav):
            // the chat list's Up / Down then only move, Enter or Space opens.
            SettingsParts.Card {
                visible: root.page === "general" && !root.subPage
                icon: "keyboard-20"; title: qsTr("Use Enter or Spacebar to show content")
                subtitle: qsTr("Press Enter or Spacebar to open an item in a list (like @mentions, chats, or channels) and view its content.")
                trailing: Component {
                    SettingsParts.Toggle {
                        on: root.prop("userPersonalSettings", ["messagingSettings", "disableAutomaticConvSwitchOnKeyboardNav"], false) === true
                        accessibleName: qsTr("Use Enter or Spacebar to show content")
                        onToggled: v => root.setProp("userPersonalSettings", "messagingSettings.disableAutomaticConvSwitchOnKeyboardNav", v)
                    }
                }
            }
            // Teams' Efficiency mode card (measured on winpc 2026-11-14):
            // three radios with second lines; "auto" is Teams' default.
            SettingsParts.Card {
                id: efficiencyCard
                visible: root.page === "general" && !root.subPage
                icon: "top-speed-20"; title: qsTr("Efficiency mode")
                bodyGap: 26
                subtitle: qsTr("This mode reduces processor, memory and network usage and is ideal for lower performance devices or those under heavy load. Turning this on may affect some functionality such as camera resolution.")
                property string mode: root.local("efficiencyMode", "auto")
                function pick(m) { mode = m; backend.setSetting("efficiencyMode", m) }
                SettingsParts.RadioRow { label: qsTr("Use only when resources are low (Default)"); sublabel: qsTr("Reduce processor and memory usage when reduced resources are detected."); checked: efficiencyCard.mode === "auto"; onPicked: efficiencyCard.pick("auto") }
                SettingsParts.RadioRow { label: qsTr("Never use efficiency mode"); sublabel: qsTr("Prioritize a richer experience, using more system resources."); checked: efficiencyCard.mode === "off"; onPicked: efficiencyCard.pick("off") }
                SettingsParts.RadioRow { label: qsTr("Always use efficiency mode"); sublabel: qsTr("Reduce processor and memory use at all times."); checked: efficiencyCard.mode === "on"; onPicked: efficiencyCard.pick("on") }
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
                icon: "local-language-20"; title: qsTr("Spellcheck languages")
                subtitle: qsTr("Select up to three languages you'd like Editor to work in. Make sure you select your preferred language at the top of the list.")
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
                            id: hcFill1
                            visible: spellManage.st.languages.length > 1
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 4
                            color: moreHover.hovered || langMenu.opened ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill1, theme.text) }
                            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: langMenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("More options")
                            Menu {
                                id: langMenu
                                y: parent.height
                                MenuItem { visible: langRow.index > 0; height: visible ? implicitHeight : 0; text: qsTr("Move up"); onTriggered: { const l = spellManage.st.languages.slice(); l.splice(langRow.index - 1, 0, l.splice(langRow.index, 1)[0]); spellManage.setLanguages(l) } }
                                MenuItem { visible: langRow.index < spellManage.st.languages.length - 1; height: visible ? implicitHeight : 0; text: qsTr("Move down"); onTriggered: { const l = spellManage.st.languages.slice(); l.splice(langRow.index + 1, 0, l.splice(langRow.index, 1)[0]); spellManage.setLanguages(l) } }
                                MenuItem { text: qsTr("Remove"); onTriggered: spellManage.setLanguages(spellManage.st.languages.filter(x => x !== langRow.modelData)) }
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
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
                        accessibleName: qsTr("Select a spell check language")
                        placeholder: qsTr("Select a spell check language")
                        onPicked: code => spellManage.pick = code
                    }
                    SettingsParts.Button {
                        label: qsTr("Add")
                        height: 32
                        onClicked: if (spellManage.pick) { spellManage.setLanguages(spellManage.st.languages.concat([spellManage.pick])); spellManage.pick = "" }
                    }
                }
                SettingsParts.Gap { size: 10 }
            }

            // ---- Appearance ----
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "dark-theme-20"; title: qsTr("Theme"); subtitle: qsTr("This will apply to all your OST apps.")
                bodyGap: 10.6
                OutlineDropdown {
                    width: 249.3; height: 30
                    readonly property var keys: ["system", "light", "dark", "classic", "highContrast"]
                    options: [{ label: qsTr("Follow operating system theme") }, { label: qsTr("Light") }, { label: qsTr("Dark") }, { label: qsTr("Classic") }, { label: qsTr("High contrast") }]
                    current: Math.max(0, keys.indexOf(backend.themeMode))
                    accessibleName: qsTr("Theme")
                    onPicked: i => backend.setSetting("theme", keys[i])
                }
                // Teams: only in the Light theme.
                SettingsParts.Gap { size: 16.7 }
                SettingsParts.CheckRow {
                    rowHeight: 32
                    label: qsTr("Always use dark theme for calls and meetings")
                    usable: !theme.dark && !theme.classic
                    checked: window.darkCallSetting
                    onToggled: v => { backend.setSetting("darkCallTheme", v ? "true" : "false"); window.darkCallSetting = v }
                }
            }
            SettingsParts.Card {
                visible: root.page === "appearance"
                icon: "emoji-hand-20"; title: qsTr("Skin tone preference"); subtitle: qsTr("Reactions and emoji will appear with this skin tone.")
                // Teams' skin tone radios (measured on winpc 2026-11-14): 42 x
                // 50 each from 8 left of the text, a 30 px swatch 6 in and the
                // chosen one's 30 x 4 brand bar at 40.
                Row {
                    x: -8; spacing: 0
                    Repeater {
                        // Teams' radio names: its emoji skin tone words with
                        // the first letter capitalised.
                        model: [qsTr("none", "messaging:k1e57n758"), qsTr("light", "messaging:kdditzq3h"), qsTr("medium light", "messaging:k1ay2emet"),
                            qsTr("medium", "messaging:kcv8hdqb2"), qsTr("medium dark", "messaging:kbkrx29m7"), qsTr("dark", "messaging:k2kcmet5z")]
                            .map(t => t.length ? t[0].toUpperCase() + t.slice(1) : t)
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
                id: appBarCard
                visible: root.page === "appearance"
                icon: "panel-left-text-20"; title: qsTr("App bar")
                subtitle: qsTr("Customize your app bar layout and properties")
                SettingsParts.SwitchRow {
                    id: appBarNamesRow
                    label: qsTr("Show app names")
                    on: window.appBarNames
                    onToggled: v => { backend.setSetting("appBarShowNames", v ? "true" : "false"); window.appBarNames = v }
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Auto collapse app bar")
                    sublabel: qsTr("The app bar will automatically collapse after you select an app.")
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
                icon: "window-layout-20"; title: qsTr("Viewing chats, teams, and channels")
                bodyGap: 28
                subtitle: qsTr("See all conversations in a combined view, or keep chats separate from teams and channels.")
                Row {
                    spacing: 12.7
                    readonly property bool separate: window.splitView
                    SettingsParts.ImageRadio { imageHeight: 80; label: qsTr("Combined"); image: "../assets/settings/simple-collab-picker-combined-" + theme.pick("light", "dark", "contrast") + ".svg"; checked: !parent.separate
                        onPicked: backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ hasUserEnabledAdaptiveRailForDesktop: true, hasUserEnabledUnifiedAppForDesktop: true })) }
                    SettingsParts.ImageRadio { imageHeight: 80; label: qsTr("Separate"); image: "../assets/settings/simple-collab-picker-separate-" + theme.pick("light", "dark", "contrast") + ".svg"; checked: parent.separate
                        onPicked: backend.changeSetting("prop", "simpleCollabUserSettings", JSON.stringify({ hasUserEnabledAdaptiveRailForDesktop: true, hasUserEnabledUnifiedAppForDesktop: false })) }
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "apps-list-20"; title: qsTr("Chats and channels list")
                SettingsParts.SwitchRow {
                    label: qsTr("Show message previews for chats and team names for channels")
                    // Separate view has its own (on unless turned off).
                    on: window.splitView ? root.prop("simpleCollabUserSettings", ["hasUserEnabledMessagePreviewsForSplitApp"], true) !== false : root.prop("simpleCollabUserSettings", ["hasUserEnabledMessagePreviews"], false) === true
                    onToggled: v => root.setProp("simpleCollabUserSettings", window.splitView ? "hasUserEnabledMessagePreviewsForSplitApp" : "hasUserEnabledMessagePreviews", v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Show time stamps")
                    // Always on in the Separate view (Teams greys it).
                    usable: !window.splitView
                    on: window.splitView || root.prop("simpleCollabUserSettings", ["hasUserEnabledShowTimeStamps"], false) === true
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserEnabledShowTimeStamps", v)
                }
                // Teams' "Show private chats in meetings" (the synced
                // simpleCollabUserSettings.hasUserEnabledNewPrivateChatInMeetingChat,
                // on unless turned off): a meeting's chat keeps its private
                // chat tabs beside Everyone.
                SettingsParts.SwitchRow {
                    label: qsTr("Show private chats in meetings")
                    on: root.prop("simpleCollabUserSettings", ["hasUserEnabledNewPrivateChatInMeetingChat"], true) !== false
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserEnabledNewPrivateChatInMeetingChat", v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Filters")
                    on: root.prop("simpleCollabUserSettings", ["hasUserDisabledShowingFilterAtTop"], false) !== true
                    onToggled: v => root.setProp("simpleCollabUserSettings", "hasUserDisabledShowingFilterAtTop", !v)
                }
                // Teams offers Copilot's switch to licensed users with the
                // Copilot app installed (ECS enableMetaOSCopilotToggleInSettings).
                SettingsParts.SwitchRow {
                    visible: !!window.copilotState.settingsToggle && window.copilotInstalled
                    label: qsTr("Copilot")
                    on: root.prop("userPersonalSettings", ["messagingSettings", "shouldShowMetaOSCopilotApp"], true) !== false
                    onToggled: v => root.setProp("userPersonalSettings", "messagingSettings.shouldShowMetaOSCopilotApp", v)
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-bubbles-question-20"; title: qsTr("Automatically follow threads in channels")
                subtitle: qsTr("To choose how you get notified, go to <0>Replies to followed threads and posts</0>").replace("<0>", "<a href=\"followed\">").replace("</0>", "</a>")
                onLinkActivated: root.page = "notifications"
                Repeater {
                    model: [{ key: "Authored", label: qsTr("Threads started from my messages or posts") }, { key: "Participated", label: qsTr("Threads I reply to") }, { key: "AtMentioned", label: qsTr("Threads where I'm @mentioned") }]
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
            // Teams' Compose card (measured on winpc 2026-11-20, Teams 26304:
            // Enter to send moved out of its own card): the question (14/20)
            // with its note (12/16) under the header, the radios 10 under.
            SettingsParts.Card {
                id: enterCard
                visible: root.page === "chats"
                icon: "keyboard-20"; title: qsTr("Compose")
                property string enterKey: root.local("enterKey", "send")
                SettingsParts.SubHeading { text: qsTr("When writing a message, press Enter to") }
                Text { width: parent.width; text: qsTr("This setting doesn't apply when message formatting is active."); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                SettingsParts.Gap { size: 10 }
                SettingsParts.RadioRow { label: qsTr("Send the message"); checked: enterCard.enterKey === "send"; onPicked: { backend.setSetting("enterKey", "send"); enterCard.enterKey = "send"; root.settingsChanged() } }
                SettingsParts.RadioRow { label: qsTr("Start a new line (to send, select Send or use %1).").arg("Ctrl+Enter"); checked: enterCard.enterKey === "newline"; onPicked: { backend.setSetting("enterKey", "newline"); enterCard.enterKey = "newline"; root.settingsChanged() } }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-20"; title: qsTr("Chat")
                SettingsParts.SubHeading { text: qsTr("Message density") }
                SettingsParts.Gap { size: 12 }
                Row {
                    spacing: 12.7
                    readonly property string mode: root.prop("messageDensity", [], "COMFY")
                    SettingsParts.ImageRadio { label: qsTr("Comfy"); image: "../assets/settings/chat-density-comfy-" + theme.pick("default", "dark", "contrast") + ".svg"; checked: parent.mode !== "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMFY") }
                    SettingsParts.ImageRadio { label: qsTr("Compact"); image: "../assets/settings/chat-density-compact-" + theme.pick("default", "dark", "contrast") + ".svg"; checked: parent.mode === "COMPACT"; onPicked: root.setProp("messageDensity", "", "COMPACT") }
                }
                SettingsParts.SubHeading { text: qsTr("When I open a chat, take me to"); gapAbove: 15 }
                SettingsParts.Gap { size: 12 }
                Row {
                    spacing: 12.7
                    readonly property bool lastRead: root.prop("userPersonalSettings", ["messagingSettings", "navigateToLastReadMessage"], true) !== false
                    SettingsParts.ImageRadio { label: qsTr("Last read message"); image: "../assets/settings/chat-landing-unread-" + theme.pick("light", "dark", "contrast") + ".svg"; checked: parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", true) }
                    SettingsParts.ImageRadio { label: qsTr("Newest message"); image: "../assets/settings/chat-landing-latest-" + theme.pick("light", "dark", "contrast") + ".svg"; checked: !parent.lastRead; onPicked: root.setProp("userPersonalSettings", "messagingSettings.navigateToLastReadMessage", false) }
                }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "eye-20"; title: qsTr("Read receipts")
                subtitle: qsTr("Let people know when you’ve seen their messages and know when they’ve seen yours. Close and reopen any chat windows for the setting to take effect in those chats.")
                trailing: Component { SettingsParts.Toggle { on: backend.readReceipts; accessibleName: qsTr("Read receipts"); onToggled: v => backend.changeReadReceipts(v) } }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "arrow-sort-20"; title: qsTr("In post channels, show recent activity")
                bodyGap: 26
                SettingsParts.RadioRow { label: qsTr("At the top"); checked: backend.channelPostsAtTop; onPicked: backend.channelAction("posts-at-top", "", "", "") }
                SettingsParts.RadioRow { label: qsTr("At the bottom"); checked: !backend.channelPostsAtTop; onPicked: backend.channelAction("posts-at-bottom", "", "", "") }
            }
            SettingsParts.Card {
                visible: root.page === "chats"
                icon: "chat-sparkle-20"; title: qsTr("Suggested replies"); subtitle: qsTr("Show suggested replies in chat")
                trailing: Component { SettingsParts.Toggle { on: root.prop("suggestedRepliesSettings", ["suggestionsEnabled"], true) !== false; accessibleName: qsTr("Suggested replies"); onToggled: v => root.setProp("suggestedRepliesSettings", "suggestionsEnabled", v) } }
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
                readonly property var levels: [{ label: qsTr("Show in Activity and banner") }, { label: qsTr("Show in Activity") }, { label: qsTr("Off") }]
            }
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: qsTr("General"); first: true }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "alert-off-20"; title: qsTr("Mute all notifications (except for calls and meetings)")
                readonly property bool muted: notif.ts("muteGenericNotifications", "Off") === "On"
                trailing: Component { SettingsParts.Toggle { on: notif.ts("muteGenericNotifications", "Off") === "On"; accessibleName: qsTr("Mute all notifications (except for calls and meetings)"); onToggled: v => notif.setTs("muteGenericNotifications", v ? "On" : "Off") } }
                SettingsParts.CheckRow {
                    label: qsTr("Always allow urgent and priority contact notifications")
                    usable: parent.parent.muted
                    checked: root.local("allowUrgentWhenMuted", "false") === "true"
                    onToggled: v => { backend.setSetting("allowUrgentWhenMuted", v ? "true" : "false"); checked = v }
                }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "speaker-2-20"; title: qsTr("Sound")
                // Teams' last row keeps its 36 px label box.
                bottomPad: 23.6
                // Teams' rows (measured on winpc 2026-11-15): labels wrap at
                // 332.3, 44 apart (64 for two lines); the notification and
                // urgent sounds' dropdowns (248.7 x 30) and Preview sound
                // beside them.
                Item {
                    width: parent.width; height: soundRow.height
                    SettingsParts.CheckRow { id: soundRow; rowHeight: 44; labelWidth: 332.3; label: qsTr("Play sounds with notifications"); checked: root.prop("userPersonalSettings", ["soundsSettings", "alertSound"], "All") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.alertSound", v ? "All" : "Off") }
                    SoundPicker { y: 2.6; setting: "alertSoundType"; dflt: "Default"; keys: ["Default", "Vibe", "Nudge", "Tap", "Flick", "Pluck", "Summon", "Ping"]; accessibleName: soundRow.label }
                }
                Item {
                    width: parent.width; height: urgentRow.height
                    SettingsParts.CheckRow { id: urgentRow; rowHeight: 44; labelWidth: 332.3; label: qsTr("Play sounds with urgent and priority contact notifications"); checked: notif.ts("PlayNotificationSoundsForUrgentAndPriority", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsForUrgentAndPriority", v ? "On" : "Off") }
                    SoundPicker { y: 2.6; setting: "alertUrgentSoundType"; dflt: "DefaultUrgent"; keys: ["DefaultUrgent", "Prioritize", "Escalate", "Alarm"]; accessibleName: urgentRow.label }
                }
                SettingsParts.CheckRow { rowHeight: 44; labelWidth: 332.3; label: qsTr("Play sounds with incoming calls, requests to join, and meeting start notifications"); checked: root.prop("userPersonalSettings", ["soundsSettings", "incomingCallsAndMeetingStartSound"], "On") !== "Off"; onToggled: v => root.setProp("userPersonalSettings", "soundsSettings.incomingCallsAndMeetingStartSound", v ? "On" : "Off") }
                SettingsParts.CheckRow { rowHeight: 44; labelWidth: 332.3; label: qsTr("Play sounds when I'm busy or in a meeting"); checked: notif.ts("PlayNotificationSoundsWhenBusyOrInMeetings", "On") !== "Off"; onToggled: v => notif.setTs("PlayNotificationSoundsWhenBusyOrInMeetings", v ? "On" : "Off") }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "eye-20"; title: qsTr("Display")
                trailing: Component { SettingsParts.Button { label: qsTr("Test notification"); onClicked: backend.testNotification() } }
                SettingsParts.CheckRow { rowHeight: 44; label: qsTr("Show message and content previews in notifications"); checked: notif.ts("ShowPreviewInToasts", "On") !== "Off"; onToggled: v => notif.setTs("ShowPreviewInToasts", v ? "On" : "Off") }
                SettingsParts.CheckRow { rowHeight: 44; label: qsTr("Show notifications during calls and meetings"); checked: notif.ts("MuteNotificationsDuringMeetings", "Off") !== "On"; onToggled: v => notif.setTs("MuteNotificationsDuringMeetings", v ? "Off" : "On") }
                SettingsParts.CheckRow { rowHeight: 44; label: qsTr("Flash taskbar when notifications are received"); checked: root.local("flashTaskbar", "true") !== "false"; onToggled: v => { backend.setSetting("flashTaskbar", v ? "true" : "false"); checked = v } }
                SettingsParts.SubHeading { text: qsTr("Dismiss notifications after this amount of time"); gapAbove: 4 }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    readonly property var secs: [5, 7, 15, 30, 60, 300]
                    // Teams' one plural message per unit (its "=5" form is "5 seconds (Default)").
                    options: [{ label: qsTr("%n seconds", "settings:k1z6j877l_mf", 5) }, { label: qsTr("%n seconds", "settings:k1z6j877l_mf", 7) }, { label: qsTr("%n seconds", "settings:k1z6j877l_mf", 15) }, { label: qsTr("%n seconds", "settings:k1z6j877l_mf", 30) }, { label: qsTr("%n minutes", "settings:kdf2mzr5x_mf", 1) },{ label: qsTr("%n minutes", "settings:kdf2mzr5x_mf", 5) }]
                    current: Math.max(0, secs.indexOf(parseInt(root.local("toastSeconds", "5"))))
                    accessibleName: qsTr("Dismiss notifications after this amount of time")
                    onPicked: i => backend.setSetting("toastSeconds", String(secs[i]))
                }
                // Where OST's banners go and how big they are (Teams' own
                // pictures; only where OST draws its banners itself, see
                // NotificationBanners.qml).
                SettingsParts.SubHeading { visible: notif.ownBanners; text: qsTr("Position on the screen"); gapAbove: 12.7 }
                SettingsParts.Gap { visible: notif.ownBanners; size: 12 }
                Grid {
                    id: cornerTiles
                    visible: notif.ownBanners
                    columns: 3; columnSpacing: 12; rowSpacing: 12
                    property string corner: root.local("notificationCorner", "BR")
                    Repeater {
                        model: [{ key: "BR", label: qsTr("Bottom right") }, { key: "TR", label: qsTr("Top right") }, { key: "BL", label: qsTr("Bottom left") }, { key: "TL", label: qsTr("Top left") }]
                        delegate: SettingsParts.ImageRadio {
                            required property var modelData
                            imageHeight: 80
                            label: modelData.label
                            checked: cornerTiles.corner === modelData.key
                            image: "../assets/settings/notification-position-" + modelData.key.toLowerCase() + "-" + theme.pick("default", "dark", "contrast") + "-" + (checked ? "active" : "inactive") + ".svg"
                            onPicked: { backend.setSetting("notificationCorner", modelData.key); cornerTiles.corner = modelData.key }
                        }
                    }
                }
                SettingsParts.SubHeading { visible: notif.ownBanners; text: qsTr("Size"); gapAbove: 12 }
                SettingsParts.Gap { visible: notif.ownBanners; size: 12 }
                Row {
                    id: sizeTiles
                    visible: notif.ownBanners
                    spacing: 12
                    property string size: root.local("notificationSize", "COMFY")
                    Repeater {
                        model: [{ key: "COMFY", label: qsTr("Comfy") }, { key: "COMPACT", label: qsTr("Compact") }]
                        delegate: SettingsParts.ImageRadio {
                            required property var modelData
                            imageHeight: 80
                            label: modelData.label
                            checked: sizeTiles.size === modelData.key
                            image: "../assets/settings/notification-style-" + modelData.key.toLowerCase() + "-" + theme.pick("default", "dark", "contrast") + "-" + (checked ? "active" : "inactive") + ".svg"
                            onPicked: { backend.setSetting("notificationSize", modelData.key); sizeTiles.size = modelData.key }
                        }
                    }
                }
                SettingsParts.Gap { size: notif.ownBanners ? 1.1 : 20 }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "mail-20"; title: qsTr("Missed activity emails")
                pad: 16.3; bottomPad: 16.4; minHeader: 0; iconX: 16.7; titleX: 61.7
                trailing: Component {
                    OutlineDropdown {
                        width: 249.3; height: 30
                        readonly property var keys: ["Immediately", "Every10Mins", "Hourly", "EveryEightHours", "Daily", "Never"]
                        options: [{ label: qsTr("As soon as possible") }, { label: qsTr("Once every 10 mins") }, { label: qsTr("Once every hour") }, { label: qsTr("Once every 8 hours") }, { label: qsTr("Daily") }, { label: qsTr("Off") }]
                        current: Math.max(0, keys.indexOf(root.prop("userPersonalSettings", ["emailSettings", "EmailNotificationDelay"], "Hourly")))
                        accessibleName: qsTr("Missed activity emails")
                        onPicked: i => root.setProp("userPersonalSettings", "emailSettings.EmailNotificationDelay", keys[i])
                    }
                }
            }
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: qsTr("Chats and channels") }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "chat-20"; title: qsTr("Chat message notifications")
                pad: 16.3; bottomPad: 16.4; minHeader: 0; iconX: 16.7; titleX: 61.7
                trailing: Component {
                    OutlineDropdown {
                        width: 249.3; height: 30
                        options: [{ label: qsTr("Off") }, { label: qsTr("Show in banner") }]
                        current: notif.ts("Chat", true) === false ? 0 : 1
                        accessibleName: qsTr("Chat message notifications")
                        onPicked: i => notif.setMany({ toastSettings: { Chat: i === 1 }, activityGenerationSettings: { Chat: i === 1 } })
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "mention-20"; title: qsTr("@Mentions")
                id: mentionsCard
                pad: 14.7; bodyGap: 33.3; bottomPad: 34.9
                // Teams' @Mentions switch (Global_Mention): on while any row
                // is above its off value (Off; Personal: Show in Activity) or
                // Global_Mention is on. Turning it on sets Personal to
                // Activity and banner and the rest to Activity; off, the
                // reverse floor. The rows are disabled while it's off.
                readonly property var rows: [
                    { label: qsTr("Channel and team @mentions"), keys: ["Mention_Team", "Visible_ChannelMention_v2"], dflt: 0, off: true },
                    { label: qsTr("Tag @mentions"), keys: ["Mention_Tag"], dflt: 0, off: true },
                    { label: qsTr("Everyone in chat @mentions"), keys: ["MentionInChat_Everyone"], dflt: 0, off: true },
                    { label: qsTr("Personal @mentions"), keys: ["Mention_Person", "MentionInChat_Person_v2"], dflt: 0, off: false }
                ]
                readonly property bool on: rows.some(r => notif.level(r.keys, r.dflt) !== (r.off ? 2 : 1)) || notif.level(["Global_Mention"], 0) !== 2
                function setAll(v) {
                    notif.setLevel(["Global_Mention"], v ? 0 : 2)
                    for (const r of rows) notif.setLevel(r.keys, r.off ? (v ? 1 : 2) : (v ? 0 : 1))
                }
                trailing: Component { SettingsParts.Toggle { on: mentionsCard.on; accessibleName: mentionsCard.title + " " + (mentionsCard.on ? qsTr("On", "settings:k9vpf66yr") : qsTr("Off", "settings:k3jiar193")); onToggled: v => mentionsCard.setAll(v) } }
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
                    { icon: "arrow-reply-20", title: qsTr("Replies to followed threads and posts"), keys: ["Reply", "ReplyToReply"] },
                    { icon: "heart-20", title: qsTr("Likes and reactions"), keys: ["Like", "LikeInChat_v2"] },
                    // Teams' Reminders (its "Remind me" reminders: Reminder,
                    // Show in Activity and banner unless changed).
                    { icon: "clock-alarm-20", title: qsTr("Reminders"), keys: ["Reminder"] }
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
            // Teams' Channel Notifications card (Teams 26304, measured on
            // winpc 2026-11-20; it replaced "Posts in all shown channels"):
            // Manage opens Notifications and activity › Manage, every
            // channel's notification choice.
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "people-team-20"; title: qsTr("Channel Notifications")
                subtitle: qsTr("Choose where to see notifications for each channel, or turn them off. By default, all new channel notifications are set to '@Mentions & replies' unless changed individually.")
                trailing: Component { SettingsParts.Button { label: qsTr("Manage"); onClicked: root.subPage = "channelNotifs" } }
            }
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: qsTr("Meetings") }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "calendar-20"; title: qsTr("Meetings")
                pad: 22.7; minHeader: 20; bodyGap: 48; bottomPad: 18.7; iconX: 17.7; titleX: 55.7
                SettingsParts.SwitchRow { rowHeight: 61; label: qsTr("Meeting start notifications"); on: notif.ts("MeetingWentLiveNotification", true) !== false
                    onToggled: v => notif.setMany(v ? { toastSettings: { MeetingWentLiveNotification: true }, activityGenerationSettings: { MeetingWentLiveNotification: true }, emailSettings: { MeetingWentLiveNotification: true } } : { toastSettings: { MeetingWentLiveNotification: false } }) }
                SettingsParts.SwitchRow { rowHeight: 59.3; label: qsTr("Show meeting join bar"); on: notif.ts("liveMeetingStatusBanner", true) !== false; onToggled: v => notif.setTs("liveMeetingStatusBanner", v) }
                // Teams' meeting chat notifications by your RSVP (chatSettings:
                // Mute / Unmute / Mute until I join or send a message).
                Repeater {
                    model: [{ key: "meetingChatNotificationForAcceptedMeetings", label: qsTr("Meeting chat notifications for meetings I've accepted"), dflt: "MeetingsUserIsInvitedTo" },
                            { key: "meetingChatNotificationForTentativeMeetings", label: qsTr("Meeting chat notifications for meetings marked as tentative or no response"), dflt: "MeetingsUserParticipatesIn" }]
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
                            options: [{ label: qsTr("Mute") }, { label: qsTr("Unmute") }, { label: qsTr("Mute until I join or send a message") }]
                            current: Math.max(0, mcRow.values.indexOf(root.prop("userPersonalSettings", ["chatSettings", mcRow.modelData.key], mcRow.modelData.dflt)))
                            accessibleName: mcRow.modelData.label
                            onPicked: i => root.setProp("userPersonalSettings", "chatSettings." + mcRow.modelData.key, mcRow.values[i])
                        }
                    }
                }
                SettingsParts.SwitchRow { label: qsTr("Meet now start notifications"); on: notif.ts("HuddleStartedNotification", false) === true; onToggled: v => notif.setTs("HuddleStartedNotification", v) }
            }

            // Teams' Presence: Manage notifications opens Manage status
            // notifications (Notify when available, contacts v3 "Tagged").
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: qsTr("Presence") }
            SettingsParts.Card {
                visible: root.page === "notifications" && !root.subPage
                icon: "person-available-20"; title: qsTr("Presence")
                subtitle: qsTr("Keep track of someone's status and get notified when they appear available or offline.")
                pad: 15.7; bottomPad: 15.6; minHeader: 0; iconX: 16.7; titleX: 58.7; textWidth: 494.2; subtitleSize: 14
                trailing: Component { SettingsParts.Button { label: qsTr("Manage notifications"); onClicked: root.subPage = "status" } }
            }
            // Notifications and activity › Manage (Teams' channel
            // notification manager, measured on winpc 2026-11-20): the
            // Channel Notifications card (padding 15.7, the icon at 24.7),
            // then one card listing "Team" (14/600 #424242, 28 tall) and
            // every team (a 44 tall expander: chevron, its 20 px picture,
            // the name 14/600) with its channels (47.3 apart: the name, the
            // choice in a 294 x 31.3 dropdown at 367.3 and Customize).
            // A choice is saved as the channel menu's Manage notifications
            // does; Customize opens the channel's notification dialog.
            SettingsParts.Card {
                visible: root.page === "notifications" && root.subPage === "channelNotifs"
                icon: "people-team-20"; title: qsTr("Channel Notifications")
                subtitle: qsTr("Choose where to see notifications for each channel, or turn them off. By default, all new channel notifications are set to '@Mentions & replies' unless changed individually.")
                pad: 15.7; bottomPad: 16.3; minHeader: 0; iconX: 24.7; titleX: 59.7
            }
            Rectangle {
                id: chanNotifs
                visible: root.page === "notifications" && root.subPage === "channelNotifs"
                width: parent.width; height: visible ? chanCol.height + 24 + 20.7 : 0
                radius: 8; color: "transparent"
                border.color: theme.pick("#D1D1D1", "#3D3D3D", "#FFFFFF"); border.width: 0.67
                readonly property var teams: visible && backend.teamsJson ? JSON.parse(backend.teamsJson) : []
                property var collapsed: ({})
                readonly property var modes: [
                    { mode: "all", label: qsTr("All new messages"), hint: qsTr("New messages, all @mentions, and replies to followed threads") },
                    { mode: "mentions", label: qsTr("@mentions and replies"), hint: qsTr("All @mentions and replies to followed threads") },
                    { mode: "mute", label: qsTr("Mute"), hint: qsTr("You'll still be notified for personal mentions and replies to followed threads") }]
                ChannelNotifyDialog { id: chanNotifyDialog; parent: Overlay.overlay }
                Column {
                    id: chanCol
                    x: 16.7; y: 24; width: parent.width - 16.7 - 20.7
                    Text { width: parent.width; height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Team"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong; Accessible.role: Accessible.Heading; Accessible.name: text }
                    Repeater {
                        model: chanNotifs.teams
                        Column {
                            id: tnTeam
                            required property var modelData
                            required property int index
                            readonly property bool open: !chanNotifs.collapsed[modelData.id]
                            width: chanCol.width
                            topPadding: index > 0 ? 12 : 0
                            Item {
                                width: parent.width; height: 44
                                FluentIcon { y: 12; size: 20; name: tnTeam.open ? "chevron-down-20" : "chevron-right-20"; color: theme.text }
                                Avatar { x: 28; y: 12; size: 20; square: true; name: tnTeam.modelData.name; initialsText: tnTeam.modelData.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase(); photoId: "team:" + tnTeam.modelData.id }
                                Text { x: 52; y: 12; width: parent.width - 52; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: tnTeam.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { const c = Object.assign({}, chanNotifs.collapsed); c[tnTeam.modelData.id] = tnTeam.open; chanNotifs.collapsed = c } }
                                Accessible.role: Accessible.Button
                                Accessible.name: tnTeam.modelData.name
                            }
                            Repeater {
                                model: tnTeam.open ? (tnTeam.modelData.channels || []) : []
                                Item {
                                    id: tnRow
                                    required property var modelData
                                    property string mode: modelData.notify || "mentions"
                                    width: tnTeam.width; height: 47.33
                                    Text { y: 13.7; width: 326.7; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: tnRow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                    OutlineDropdown {
                                        x: 350.6; y: 8; width: 294; height: 31.3
                                        options: chanNotifs.modes.map(m => ({ label: m.label, sublabel: m.hint }))
                                        current: Math.max(0, chanNotifs.modes.findIndex(m => m.mode === tnRow.mode))
                                        accessibleName: tnRow.modelData.name
                                        onPicked: i => { const m = chanNotifs.modes[i].mode; if (m !== tnRow.mode) { tnRow.mode = m; backend.channelAction("notify", tnTeam.modelData.id, tnRow.modelData.id, m) } }
                                    }
                                    SettingsParts.Button {
                                        x: 656.6; y: 8; label: qsTr("Customize")
                                        onClicked: { chanNotifyDialog.teamId = tnTeam.modelData.id; chanNotifyDialog.teamName = tnTeam.modelData.name; chanNotifyDialog.start(tnRow.modelData) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SettingsParts.Card {
                id: statusNotif
                visible: root.page === "notifications" && root.subPage === "status"
                icon: "contact-card-20"; title: qsTr("Manage status notifications")
                subtitle: qsTr("Keep track of someone's status and get notified when they appear available or offline.")
                property var tagged: []
                readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
                onVisibleChanged: if (visible) backend.channelAction("notify-tagged", "", "", "")
                // Teams' Add people box beside the title (371 x 41, filled, brand
                // underline while typing, measured), its matches under it.
                trailingY: 21; trailingRight: 12
                trailing: Component {
                    Rectangle {
                        width: 371; height: 41
                        color: theme.inputFilled; border.color: theme.transparentStroke; radius: 4
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: addPeople.activeFocus ? 2 : 0.67; color: addPeople.activeFocus ? theme.brand : theme.textSecondary }
                        TextInput {
                            id: addPeople
                            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                            onTextEdited: { peopleDelay.restart(); if (text.trim().length >= 2) matches.open(); else matches.close() }
                            Text { visible: !addPeople.text; text: qsTr("Add people"); font: addPeople.font; color: theme.textSecondary }
                            Keys.onEscapePressed: { text = ""; matches.close() }
                            Accessible.name: qsTr("Add people")
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
                                        id: hcFill2
                                        required property var modelData
                                        width: matches.width - 8; height: 44; radius: 4
                                        color: pHover.hovered ? theme.menuHover : "transparent"
                                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name || ""; photoId: parent.modelData.id || "" }
                                        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; elide: Text.ElideRight; text: parent.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill2, theme.text) }
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
                            id: hcFill3
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 4
                            color: rmHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill3, theme.text) }
                            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.channelAction("notify-off", "", "", JSON.stringify({ id: tagRow.modelData.id, mri: tagRow.modelData.mri, email: tagRow.modelData.email })) }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Remove %1").arg(tagRow.name)
                        }
                    }
                }
                SettingsParts.Gap { size: 8 }
            }

            // Teams' Calendar notifications: the Calendar app's Graph
            // notification settings (userGraphSettings), each choice setting its
            // group of meeting notification kinds.
            SectionTitle { visible: root.page === "notifications" && !root.subPage; text: qsTr("Calendar") }
            SettingsParts.Card {
                id: calNotif
                visible: root.page === "notifications" && !root.subPage
                icon: "calendar-20"; title: qsTr("Calendar")
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
                    model: [{ key: "privateMeetingCreated", label: qsTr("New invites, updates and cancellations sent to me") }, { key: "privateMeetingForwardedNotification", label: qsTr("When people forward meetings I’ve organized") }]
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
                        else if ((r.op === "people-list-add" || r.op === "people-list-remove") && !r.ok) backend.toast(qsTr("Something went wrong on our end. Please try again."), "error")
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
                        Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("When you block someone, they can't call you, message you, or see your presence."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { visible: peopleLists.mris.length === 0; width: parent.width; wrapMode: Text.Wrap; text: qsTr("When you block people, you'll see them listed below."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                    SettingsParts.Card {
                        id: priorityCard
                        visible: peopleLists.list === "priority"
                        icon: "presence-dnd-20"; title: qsTr("Manage priority access")
                        subtitle: qsTr("When your status is set to Do not disturb, you can still receive notifications for chats, calls, and @mentions from the people below.")
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
                                    Text { visible: !prioField.text; text: qsTr("Search for a name or number"); font: prioField.font; color: theme.textSecondary }
                                    Keys.onEscapePressed: { text = ""; prioMatches.close() }
                                    Accessible.name: qsTr("Search for a name or number")
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
                                                id: hcFill4
                                                required property var modelData
                                                width: prioMatches.width - 8; height: 44; radius: 4
                                                color: ppHover.hovered ? theme.menuHover : "transparent"
                                                Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name || ""; photoId: parent.modelData.id || "" }
                                                Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; elide: Text.ElideRight; text: parent.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill4, theme.text) }
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
                                label: peopleLists.list === "blocked" ? qsTr("Unblock") : qsTr("Remove")
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
                border.color: theme.pick("#D1D1D1", "#3D3D3D", "#FFFFFF"); border.width: 0.67
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
                    color: refreshHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                    border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; name: "arrow-clockwise-20"; size: 20; color: theme.onFill(refreshBtn, theme.text) }
                    HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.restartApp() }
                    ToolTip {
                        visible: refreshHover.hovered; delay: 500
                        y: -height - 4; padding: 8
                        background: FluentSurface { depth: 16; radius: 4 }
                        contentItem: Text { text: qsTr("Refresh license and restart"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Refresh license and restart")
                }
                Rectangle {
                    id: hcFill5
                    x: parent.width - 118.7; y: 21.2
                    width: 96; height: 32; radius: 4
                    color: manageHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                    border.color: theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 0.67
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Manage"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill5, theme.text) }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "open-16"; size: 14; color: theme.onFill(hcFill5, theme.text) }
                    }
                    HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://myaccount.microsoft.com/?login_hint=" + encodeURIComponent(backend.userMail)) }
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Manage Account for %1 (opens in new tab)").arg(backend.userName)
                }
                Rectangle { y: 72; width: parent.width; height: 0.67; color: theme.pick("#D1D1D1", "#3D3D3D", "#000000") }
                Rectangle {
                    x: 0.67; y: 72.67; width: parent.width - 1.33; height: 47.3
                    color: theme.pick("#FAFAFA", "#242424", "#000000")
                    Rectangle { x: 2; y: 4; width: 3; height: parent.height - 8; radius: 1.5; color: theme.brand }
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: backend.orgName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: backend.orgName
                }
            }

            // ---- Privacy ----
            // Manage my work location (Teams' presence-location card). With
            // the tenant's work-location detection policy off, Teams says
            // so; with it on (teamsWorkLocationDetectionPolicy, and the
            // places flights enableAutoDetectPlaceWifi and
            // enableAutoDetectLocationToggle), the automatic work location
            // switch, "Learn about automatically setting a work location"
            // (its dialog) and, with adlWiredCheckout, "Manage stationary
            // location" (measured on winpc 2026-11-15: the header 54.3, the
            // button 12 under it, the Outlook note 12 under that, the switch
            // centred on the whole card). The switch is the user property
            // placesSettings.autoUpdateLocationPreference ("Enabled" /
            // "Disabled"), written with autoLocationFirstEngagement
            // "SETTING_TOGGLE" as Teams does. Where your work hours and
            // location are set: Outlook.
            SettingsParts.Card {
                id: workLocationCard
                // (ECS answers aren't notified: read again each time Privacy opens.)
                readonly property bool shown: root.page === "privacy" && !root.subPage
                readonly property var policy: backend.workLocationPolicyJson ? JSON.parse(backend.workLocationPolicyJson) : ({})
                function flag(ns, key, dflt) { const v = backend.ecsSetting(ns, key); return v === "" ? dflt : v === "true" }
                readonly property bool detection: shown && policy.detection === true && flag("places", "enableAutoDetectPlaceWifi", false) && flag("places", "enableAutoDetectLocationToggle", false)
                readonly property bool stationary: detection && flag("places", "adlWiredCheckout", true)
                readonly property string outlookUrl: { if (!shown) return ""; const v = backend.ecsSetting("presence", "outlookLocationSettingUrl"); return v ? JSON.parse(v) : "" }
                readonly property bool outlookLink: shown && backend.ecsSetting("presence", "enableWorkLocationSettingsLink") === "true" && outlookUrl.length > 0
                function link(href, label) { return "<a href=\"" + href + "\" style=\"color:" + theme.brandLink + ";text-decoration:none\">" + label + "</a>" }
                readonly property string outlookNote: qsTr("Your work location will be shared with Places and Outlook. Manage more preferences in Outlook.") + " " + link(outlookUrl, qsTr("Open Outlook work hours and location settings"))
                // Teams' convertAutoUpdateLocationPreferenceToBool: set, or
                // for an unset preference the policy's default (with the
                // adlEnableDefaultOptIn flight) unless this is the first run.
                readonly property bool autoOn: {
                    const pref = root.prop("placesSettings", ["autoUpdateLocationPreference"], "")
                    if (pref === "Enabled") return true
                    if (pref === "Disabled") return false
                    if (policy.userDefault === "Enabled" && flag("places", "adlEnableDefaultOptIn", false))
                        return root.prop("placesSettings", ["autoLocationFirstEngagement"], "") !== "FIRST_RUN"
                    return flag("places", "adlSettingDefaultEnabled", false) || flag("places", "tpp", false)
                }
                function setAuto(on) { root.setProp("placesSettings", "", { autoUpdateLocationPreference: on ? "Enabled" : "Disabled", autoLocationFirstEngagement: "SETTING_TOGGLE" }) }
                visible: shown
                icon: "building-home-20"; title: qsTr("Manage my work location")
                subtitleLineHeight: 17.14
                subtitleFormat: Text.RichText
                subtitle: detection
                    ? qsTr("Automatically set my location across all devices when connecting to my organization's networks and devices.") + " " + link("learn", qsTr("Learn about automatically setting a work location"))
                    : qsTr("Automatically setting your work location has been turned off by your IT department.") + " " + link("https://support.microsoft.com/en-us/office/first-things-to-know-about-bookable-desks-in-microsoft-teams-5d10c217-1205-48a1-a883-ff4533f4ae71?preview=true", qsTr("Learn more"))
                        + (outlookLink ? "<br>" + outlookNote : "")
                onLinkActivated: l => { if (l === "learn") autoLocationDialog.open(); else Qt.openUrlExternally(l) }
                trailingGapX: 0
                bodyGap: 11.9
                trailingY: detection ? (pad + headerHeight + bodyGap + bodyHeight + bottomPad - 36) / 2 : NaN
                trailing: detection ? workLocationToggle : null
                Component {
                    id: workLocationToggle
                    SettingsParts.Toggle { on: workLocationCard.autoOn; // Teams' switch is labelled by its card's title and subtitle.
                        accessibleName: workLocationCard.title + " " + qsTr("Automatically set my location across all devices when connecting to my organization's networks and devices.") + " " + qsTr("Learn about automatically setting a work location"); onToggled: v => workLocationCard.setAuto(v) }
                }
                SettingsParts.Button {
                    visible: workLocationCard.stationary
                    label: qsTr("Manage stationary location")
                    onClicked: { root.subPage = "stationary"; backend.loadBuildings() }
                }
                SettingsParts.Gap { visible: workLocationCard.stationary && workLocationCard.detection && workLocationCard.outlookLink; size: 12.1 }
                Text {
                    visible: workLocationCard.detection && workLocationCard.outlookLink
                    width: parent.width - 116
                    text: workLocationCard.outlookNote
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    linkColor: theme.brandForeground1
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                    color: theme.textSecondary
                    onLinkActivated: l => Qt.openUrlExternally(l)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }
            AutoLocationDialog {
                id: autoLocationDialog
                settingOn: workLocationCard.autoOn
                onTurnOn: workLocationCard.setAuto(true)
            }

            // Privacy ▸ Stationary device location (Teams' device home
            // building; measured on winpc 2026-11-15): the paragraph (14/20
            // #424242) 8 down, "Permanent device building" (14 semibold) 16
            // under it, then a 300 x 32 "Find a building" combobox 15 under
            // that. Its list opens beside the box (2 to the right, 4 up),
            // 300 wide; with no buildings, a disabled "No buildings found".
            // The building is this device's (Teams keeps it in its client
            // preferences, places.deviceHomeBuildingId); the list is the
            // tenant's buildings from Places.
            Column {
                id: stationaryPage
                visible: root.page === "privacy" && root.subPage === "stationary"
                width: parent.width
                topPadding: 8
                spacing: 0
                readonly property var data_: backend.buildingsJson ? JSON.parse(backend.buildingsJson) : ({ buildings: [] })
                readonly property var buildings: data_.buildings || []
                readonly property string chosen: backend.setting("deviceHomeBuildingId")
                readonly property var chosenBuilding: buildings.find(b => b.id === chosen) || null
                onVisibleChanged: if (!visible) buildingList.close()
                Text {
                    width: Math.min(parent.width, 790)
                    text: qsTr("Set a permanent location for stationary devices that stay in one building. When Wi-Fi isn't detected, this device will remain checked in at the selected building instead of being automatically checked out.")
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.textStrong
                }
                SettingsParts.Gap { size: 16 }
                Text {
                    text: qsTr("Permanent device building")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                SettingsParts.Gap { size: 15 }
                Rectangle {
                    id: buildingBox
                    width: 300; height: 32; radius: 4
                    color: theme.surface
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33; height: buildingField.activeFocus ? 2 : 0.67; radius: 1; color: buildingField.activeFocus ? theme.brand : theme.pick("#575757", "#ADADAD", "#000000") }
                    TextInput {
                        id: buildingField
                        x: 8.67; width: 264.7 - 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        text: stationaryPage.chosenBuilding ? stationaryPage.chosenBuilding.name : ""
                        onTextEdited: buildingList.open()
                        Text { visible: !buildingField.text; text: qsTr("Find a building"); font: buildingField.font; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                        Keys.onEscapePressed: buildingList.close()
                        Keys.onDownPressed: buildingList.open()
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: qsTr("Permanent device building")
                    }
                    FluentIcon { x: 269.3; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
                    TapHandler { onTapped: { buildingField.forceActiveFocus(); if (buildingList.opened) buildingList.close(); else buildingList.open() } }
                    Popup {
                        id: buildingList
                        x: buildingBox.width + 2; y: -4; width: 300; padding: 4
                        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
                        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                        readonly property var matches: {
                            const q = buildingField.text.trim().toLowerCase()
                            const chosenName = stationaryPage.chosenBuilding ? stationaryPage.chosenBuilding.name.toLowerCase() : ""
                            return stationaryPage.buildings.filter(b => !q || q === chosenName || b.name.toLowerCase().indexOf(q) >= 0)
                        }
                        contentItem: Column {
                            Item {
                                visible: buildingList.matches.length === 0
                                width: 292; height: 32
                                Text { x: 28; anchors.verticalCenter: parent.verticalCenter; text: stationaryPage.data_.loading ? qsTr("Loading…") : qsTr("No buildings found"); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: qsTr("No buildings found")
                            }
                            Repeater {
                                model: buildingList.matches
                                Rectangle {
                                    id: hcFill6
                                    required property var modelData
                                    width: 292; height: 32; radius: 4
                                    color: bHover.hovered ? theme.menuHover : "transparent"
                                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; visible: parent.modelData.id === stationaryPage.chosen; name: "checkmark-16"; size: 16; color: theme.onFill(hcFill6, theme.text) }
                                    Text { x: 28; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 36; elide: Text.ElideRight; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill6, theme.text) }
                                    HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { backend.setSetting("deviceHomeBuildingId", parent.modelData.id); buildingField.text = parent.modelData.name; buildingList.close() } }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: modelData.name
                                }
                            }
                        }
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "presence-dnd-20"; title: qsTr("Do not disturb")
                subtitle: qsTr("You can still receive notifications from people who have priority access when your status is set to Do not disturb.")
                trailing: Component { SettingsParts.Button { label: qsTr("Manage priority contacts"); onClicked: root.subPage = "priority" } }
                SettingsParts.CheckRow {
                    label: qsTr("Set my status to do not disturb when I'm sharing my screen")
                    sublabel: qsTr("Turning this setting off will change your status to busy and let you receive calls, as well as urgent and priority contact notifications.")
                    checked: root.mt.allowAutoDnd !== false
                    onToggled: on => root.setMt("allowAutoDnd", on)
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "person-prohibited-20"; title: qsTr("Blocked contacts")
                subtitle: qsTr("Blocked contacts will be unable to call you, message you, or see your presence.")
                trailing: Component { SettingsParts.Button { label: qsTr("Manage blocked contacts"); onClicked: root.subPage = "blocked" } }
                SettingsParts.CheckRow {
                    label: qsTr("Block calls with no caller ID")
                    checked: root.mt.blockAnonymousCaller === true
                    onToggled: on => root.setMt("blockAnonymousCaller", on)
                }
            }
            // Teams' "Delete Copilot activity history" (Teams 26304, measured
            // on winpc 2026-11-20; licensed users, ECS messaging.
            // enableCopilotDeleteHistorySetting): the note with "Learn how
            // to delete Copilot activity history" (12/16, the link inline,
            // wrapping at 433.4) and "Open Copilot activity history" (an
            // open glyph before it), both from ECS (your Microsoft account's
            // privacy page and Microsoft's article).
            SettingsParts.Card {
                id: copilotHistory
                visible: root.page === "privacy" && !root.subPage && !!window.copilotState.deleteHistory
                icon: "mo-copilot"; title: qsTr("Delete Copilot activity history")
                textWidth: 433.4
                subtitleFormat: Text.RichText
                subtitle: qsTr("You can delete your history in your Microsoft account.") + " <a href=\"learn\" style=\"color:" + theme.brandForeground1 + ";text-decoration:none\">" + qsTr("Learn how to delete Copilot activity history") + "</a>"
                onLinkActivated: Qt.openUrlExternally(window.copilotState.deleteHistoryLearnUrl)
                trailing: Component {
                    SettingsParts.Button {
                        icon: "open-20"
                        label: qsTr("Open Copilot activity history")
                        onClicked: Qt.openUrlExternally(window.copilotState.deleteHistoryUrl)
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "clipboard-task-list-20"; title: qsTr("Surveys"); subtitle: qsTr("Participate in surveys from OST.")
                trailing: Component { SettingsParts.Toggle { on: root.prop("userEnableSurveysNotification", [], "true") !== "false"; accessibleName: qsTr("Surveys"); onToggled: v => root.setProp("userEnableSurveysNotification", "", v ? "true" : "false") } }
                // OST's opt-in for Teams' post-call "How was the call
                // quality?" (off by default; kept on this device). Teams asks
                // only while Surveys is on, so this does too.
                SettingsParts.CheckRow {
                    id: cqfRow
                    readonly property bool surveysOn: root.prop("userEnableSurveysNotification", [], "true") !== "false"
                    property bool optedIn: backend.setting("callQualitySurvey") === "true"
                    label: qsTr("Ask me about call quality after calls")
                    sublabel: qsTr("OST asks after some calls. If a call had issues, Report a problem opens with its technical details (no one's name) for you to post as a public issue on GitHub.")
                    usable: surveysOn
                    checked: optedIn && surveysOn
                    onToggled: on => { backend.setSetting("callQualitySurvey", on ? "true" : "false"); optedIn = on }
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "video-person-off-20"; title: qsTr("Turn off my camera and mic when my screen locks")
                subtitle: qsTr("If your screen locks due to inactivity while you're in a meeting, your camera, mic, and screensharing will automatically turn off. Restart OST to apply this setting.")
                trailing: Component { SettingsParts.Toggle { on: backend.setting("turnOffMediaOnDeviceLock") === "true"; accessibleName: qsTr("Turn off my camera and mic when my screen locks"); onToggled: v => { backend.setSetting("turnOffMediaOnDeviceLock", v ? "true" : "false"); on = v } } }
            }
            // Teams' "View Diagnostic Data" (settings-app FF/RF, measured on
            // winpc 2026-11-19): Manage opens Privacy › Diagnostic data
            // viewer.
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "data-area-20"; title: qsTr("View Diagnostic Data")
                trailing: Component { SettingsParts.Button { label: qsTr("Manage"); onClicked: root.subPage = "ddv" } }
            }
            // Teams' diagnostic data viewer (its trusted-UI page, measured
            // on winpc 2026-11-19): at 20, 21 in the pane, 790 wide. With
            // "Enable data viewing" on, OST streams the diagnostic data it
            // sends to the Diagnostic Data Viewer of the Windows device at
            // the connection string, as Teams does (api::ddv).
            Column {
                id: ddvPage
                visible: root.page === "privacy" && root.subPage === "ddv"
                x: 0; topPadding: 0
                width: 790
                spacing: 0
                readonly property var st: backend.ddvJson ? JSON.parse(backend.ddvJson) : ({})
                onVisibleChanged: if (visible) backend.loadDdv()
                Text { width: parent.width; text: qsTr("View Diagnostic Data"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Item { width: 1; height: 15 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("To view diagnostic data associated with this app, connect to a Windows device running Diagnostic Data Viewer and enter the connection string below. The app will disconnect after 24 hours."); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 8 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Note: When you enable data viewing the data sent to the device running Diagnostic Data Viewer (at the connection string you enter) will use HTTP instead of HTTPS so that it can properly display. However, diagnostic data sent to Microsoft will still use HTTPS to encrypt and protect your data."); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 8 }
                Text {
                    text: qsTr("Learn More")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.underline: ddvLink.hovered
                    color: theme.brandForeground1
                    HoverHandler { id: ddvLink; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://support.microsoft.com/office/using-the-diagnostic-data-viewer-with-office-cf761ce9-d805-4c60-a339-4e07f3182855") }
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
                Item { width: 1; height: 15 }
                // The switch (Fluent's, in its 56 x 36 hit area) with its label.
                Item {
                    width: parent.width; height: 36
                    SettingsParts.Toggle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        stateLabel: false
                        on: ddvPage.st.enabled === true
                        accessibleName: qsTr("Enable data viewing")
                        onToggled: v => backend.setDdvEnabled(v)
                    }
                    Text { x: 56; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Enable data viewing"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
                }
                Item { visible: ddvPage.st.enabled === true; width: 1; height: 15 }
                Text {
                    visible: ddvPage.st.enabled === true
                    text: qsTr("Diagnostic data viewer connection string")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                }
                Item { visible: ddvPage.st.enabled === true; width: 1; height: 8 }
                Row {
                    visible: ddvPage.st.enabled === true
                    spacing: 10
                    Rectangle {
                        width: 325; height: 31.33; radius: 4
                        color: theme.pick("#F0F0F0", "#0A0A0A", "#000000")
                        border.color: theme.highContrast ? "#FFFFFF" : "transparent"; border.width: 0.67
                        Rectangle { visible: ddvField.activeFocus; anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; color: theme.brand }
                        TextInput {
                            id: ddvField
                            x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                            text: ddvPage.st.connectionString || ""
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                            selectByMouse: true
                            onAccepted: backend.connectDdv(text.trim())
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Diagnostic data viewer connection string")
                        }
                        // After a try: Teams' CheckmarkCircleRegular (green)
                        // or ErrorCircleRegular (red) at the end.
                        FluentIcon {
                            visible: ddvPage.st.state === "connected" || ddvPage.st.state === "failed"
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            name: ddvPage.st.state === "connected" ? "checkmark-circle-20" : "error-circle-20"; size: 20
                            color: ddvPage.st.state === "connected" ? theme.pick("#107C10", "#54B054", "#3FF23F") : theme.pick("#BC2F32", "#E37D80", "#FFFF00")
                        }
                    }
                    SettingsParts.Button { primary: true; label: qsTr("Connect"); height: 32; onClicked: backend.connectDdv(ddvField.text.trim()) }
                }
                Item { visible: ddvPage.st.enabled === true && !!ddvPage.st.state && ddvPage.st.state !== "idle"; width: 1; height: 8 }
                Text {
                    visible: ddvPage.st.enabled === true && !!ddvPage.st.state && ddvPage.st.state !== "idle"
                    width: 325; wrapMode: Text.Wrap
                    text: ddvPage.st.state === "connecting" ? qsTr("Attempting to establish connection...")
                        : ddvPage.st.state === "connected" ? qsTr("Connection established")
                        : qsTr("Couldn't connect. Double check the connection string is correct and that Diagnostic Data Viewer is running on the Windows device you're connecting to, then try again.")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: ddvPage.st.state === "failed" ? theme.pick("#BC2F32", "#E37D80", "#FFFF00") : theme.text
                    Accessible.role: ddvPage.st.state === "failed" ? Accessible.AlertMessage : Accessible.StaticText
                    Accessible.name: text
                }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "data-area-20"; title: qsTr("Extended diagnostics data")
                subtitle: qsTr("Enable the application to store a larger duration of diagnostics data for debugging purposes.")
                trailing: Component { SettingsParts.Toggle { on: backend.setting("shouldPersistLogsIntoIDB") === "true"; accessibleName: qsTr("Extended diagnostics data"); onToggled: v => { backend.setSetting("shouldPersistLogsIntoIDB", v ? "true" : "false"); on = v } } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "people-list-20"; title: qsTr("Identify me in attendance reports"); subtitle: qsTr("Let meeting or event organizer know your attendance information.")
                trailing: Component { SettingsParts.Toggle { on: root.prop("showInMeetingReport", [], "true") !== "false"; accessibleName: qsTr("Identify me in attendance reports"); onToggled: v => root.setProp("showInMeetingReport", "", v ? "true" : "false") } }
            }
            // Teams' E2EE card (settings-app m4, measured on winpc): its
            // switch is greyed when the tenant's encryption policy doesn't let
            // users choose (callingEndtoEndEncryptionEnabledType Disabled);
            // the choice is kept in the middle tier (useEndToEndEncryption).
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "call-20"; title: qsTr("End-to-end encrypted calls")
                subtitle: qsTr("One-on-one OST calls are end-to-end encrypted if both participants turn on this setting. Some features won't be available, including recording and transcription. %1").arg("<a href=\"https://go.microsoft.com/fwlink/?linkid=2174740\">" + qsTr("Learn more") + "</a>")
                onLinkActivated: l => Qt.openUrlExternally(l)
                trailing: Component { SettingsParts.Toggle { on: root.mt.useEndToEndEncryption === true; usable: root.mt.e2eeAllowedByAdmin === true; accessibleName: qsTr("End-to-end encrypted calls"); onToggled: v => root.setMt("useEndToEndEncryption", v) } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "image-sparkle-20"; title: qsTr("Optional connected experiences")
                subtitle: qsTr("Enhance your OST experience with cloud-backed services, including Giphy, URL Preview, and more.") + " <a href=\"https://go.microsoft.com/fwlink/?linkid=2295907\">" + qsTr("Learn More") + "</a><br><a href=\"https://privacy.microsoft.com/privacystatement\">" + qsTr("Microsoft Privacy Statement") + "</a>"
                onLinkActivated: l => Qt.openUrlExternally(l)
                trailing: Component { SettingsParts.Toggle { on: root.prop("controllerConnectedServicesEnabled", [], "true") !== "false"; accessibleName: qsTr("Optional connected experiences"); onToggled: v => root.setProp("controllerConnectedServicesEnabled", "", v ? "true" : "false") } }
            }
            SettingsParts.Card {
                visible: root.page === "privacy" && !root.subPage
                icon: "mic-20"; title: qsTr("Keyboard shortcut to unmute"); subtitle: qsTr("Press and hold Ctrl + Spacebar to temporarily unmute your mic during a meeting.")
                trailing: Component { SettingsParts.Toggle { on: root.prop("enablePushToTalk", [], "true") !== "false"; accessibleName: qsTr("Keyboard shortcut to unmute"); onToggled: v => root.setProp("enablePushToTalk", "", v ? "true" : "false") } }
            }

            // ---- Accessibility ----
            // Teams' Sign language mode (settings-app, measured on winpc
            // 2026-11-19): with it on, "I am a Signer" (with "Show my signer
            // status…" and Manage interpreters) or "I am a Sign Language
            // Interpreter", kept in the callAccessibilitySettings property
            // (signLanguageModeSelection, showSignerIdentificationToOthers,
            // selectedDHHInterpreters) and acted on in meetings.
            SettingsParts.Card {
                id: signCard
                visible: root.page === "accessibility" && !root.subPage
                readonly property bool on: root.prop("callAccessibilitySettings", ["accessibilityModeEnabledV2"], false) === true
                readonly property bool signer: root.prop("callAccessibilitySettings", ["signLanguageModeSelection"], "SIGNER") !== "INTERPRETER"
                icon: "hand-wave-20"; title: qsTr("Sign language mode"); subtitle: qsTr("Enable features that provide an enhanced experience for sign language users.")
                bodyGap: 30.3
                trailing: Component { SettingsParts.Toggle { on: signCard.on; accessibleName: qsTr("Sign language mode"); onToggled: v => root.setProp("callAccessibilitySettings", "accessibilityModeEnabledV2", v) } }
                SettingsParts.RadioRow {
                    visible: signCard.on
                    height: 46
                    label: qsTr("I am a Signer")
                    sublabel: qsTr("I am a Deaf/Hard-of-hearing meeting participant who uses sign language to communicate.")
                    checked: signCard.signer
                    onPicked: root.setProp("callAccessibilitySettings", "signLanguageModeSelection", "SIGNER")
                }
                Item {
                    visible: signCard.on
                    width: parent.width; height: 42
                    SettingsParts.CheckRow {
                        x: 49; width: parent.width - 49; rowHeight: 32
                        label: qsTr("Show my signer status to others using Sign language mode")
                        usable: signCard.signer
                        checked: root.prop("callAccessibilitySettings", ["showSignerIdentificationToOthers"], true) !== false
                        onToggled: v => root.setProp("callAccessibilitySettings", "showSignerIdentificationToOthers", v)
                    }
                }
                Item {
                    visible: signCard.on
                    width: parent.width; height: 37
                    SettingsParts.Button { x: 28; label: qsTr("Manage interpreters"); enabled: signCard.signer; opacity: enabled ? 1 : 0.4; onClicked: root.subPage = "interpreters" }
                }
                SettingsParts.RadioRow {
                    visible: signCard.on
                    label: qsTr("I am a Sign Language Interpreter")
                    sublabel: qsTr("I provide sign language interpretation for Deaf/Hard-of-hearing meeting participants.")
                    checked: !signCard.signer
                    onPicked: root.setProp("callAccessibilitySettings", "signLanguageModeSelection", "INTERPRETER")
                }
            }
            // Teams' Manage interpreters page: the people you sign with, in
            // selectedDHHInterpreters (MRIs), each with Remove as signer.
            Column {
                id: interpretersPage
                visible: root.page === "accessibility" && root.subPage === "interpreters"
                width: 600
                readonly property var mris: { const v = root.prop("callAccessibilitySettings", ["selectedDHHInterpreters"], []); return Array.isArray(v) ? v : [] }
                readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
                onVisibleChanged: if (visible && mris.length) backend.resolveNames(JSON.stringify(mris))
                function save(list) { root.setProp("callAccessibilitySettings", "selectedDHHInterpreters", list) }
                Text { height: 26; text: qsTr("Add someone as an interpreter"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 26; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Item { width: 1; height: 10 }
                Text { height: 17; text: qsTr("Please choose the interpreters for your meetings."); font.family: theme.font; font.pointSize: 8.75 /* Teams: 11.67 px */; color: theme.text }
                Item { width: 1; height: 9.3 }
                VoicemailTransferPicker {
                    width: 600
                    placeholder: qsTr("Add someone as an interpreter")
                    accessibleName: qsTr("Type a name or email address to add someone as an interpreter")
                    phoneSuggestions: false
                    exclude: interpretersPage.mris
                    people: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.items || [] }
                    peopleQuery: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.query || "" }
                    onSearch: q => backend.newChatPeople(q)
                    onPicked: (mri, oid, name) => { if (interpretersPage.mris.indexOf(mri) < 0) interpretersPage.save(interpretersPage.mris.concat([mri])) }
                }
                Repeater {
                    model: interpretersPage.mris
                    Item {
                        id: irow
                        required property string modelData
                        width: 600; height: 48
                        readonly property string name: interpretersPage.names[modelData] || ""
                        Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: irow.name || "?"; photoId: irow.modelData.replace(/^8:orgid:/, "") }
                        Text { x: 52; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 100; elide: Text.ElideRight; text: irow.name || irow.modelData; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Rectangle {
                            id: irm
                            anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 4
                            color: irmHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(irm, theme.textStrong) }
                            HoverHandler { id: irmHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: interpretersPage.save(interpretersPage.mris.filter(m => m !== irow.modelData)) }
                            ToolTip {
                                visible: irmHover.hovered; delay: 500
                                y: -height - 4; padding: 8
                                background: FluentSurface { depth: 16; radius: 4 }
                                contentItem: Text { text: qsTr("Remove as signer"); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Remove %1 from signers list").arg(irow.name || irow.modelData)
                        }
                    }
                }
            }
            SettingsParts.Card {
                visible: root.page === "accessibility" && !root.subPage
                icon: "closed-caption-20"; title: qsTr("Captions and transcripts")
                SettingsParts.SwitchRow {
                    label: qsTr("Always show captions in my calls and meetings")
                    on: root.prop("callAccessibilitySettings", ["startCaptionsAutomatically"], false) === true
                    onToggled: v => root.setProp("callAccessibilitySettings", "startCaptionsAutomatically", v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Automatically identify me in live captions and live transcripts")
                    on: root.mt.enableSpeakerAttribution !== false
                    onToggled: v => root.setMt("enableSpeakerAttribution", v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Filter out profane words in live captions")
                    on: root.prop("callAccessibilitySettings", ["profanityFilterEnabled"], false) === true
                    onToggled: v => root.setProp("callAccessibilitySettings", "profanityFilterEnabled", v)
                }
            }
            // Teams' Muted notification (clientPreferences meeting.mutedDialogs,
            // on this device): the same setting as the call's Accessibility
            // pane, so a call in progress follows it at once.
            SettingsParts.Card {
                visible: root.page === "accessibility" && !root.subPage
                icon: "mic-off-20"; title: qsTr("Muted notification")
                subtitle: qsTr("Show the 'You're muted' notification when audio is detected while your microphone is off.")
                trailing: Component { SettingsParts.Toggle { on: backend.setting("showMutedNotice") !== "false"; accessibleName: qsTr("Muted notification"); onToggled: v => { backend.setSetting("showMutedNotice", v ? "true" : "false"); on = v; callWindow.showMutedNotice = v } } }
            }
            // Teams' "Turn on single pointer controls" (measured on winpc
            // 2026-11-16, after Muted notification; clientPreferences
            // SimpleCollabPreferences.enableSinglePointReordering, on this
            // device): the chat list's item and section menus then offer
            // Start reordering (ChatList.reorderMode).
            SettingsParts.Card {
                visible: root.page === "accessibility" && !root.subPage
                icon: "hand-point-20"; title: qsTr("Turn on single pointer controls")
                subtitle: qsTr("Available: Start reordering, an alternate to drag and drop in the chats and channels list.")
                trailing: Component { SettingsParts.Toggle { on: backend.setting("singlePointReordering") === "true"; accessibleName: qsTr("Turn on single pointer controls"); onToggled: v => { backend.setSetting("singlePointReordering", v ? "true" : "false"); on = v; window.singlePointReordering = v } } }
            }
            // Teams' Teletypewriter (TTY) mode (measured on winpc 2026-11-16:
            // the last card, 93.3 tall, Teams' accessibility glyph, the
            // subtitle on two 16 px lines). Kept on this device (Teams'
            // TTY local storage); the call's audio takes it as the next
            // call starts (apm::set_tty_mode), and after a change Teams
            // shows "Changes will be applied for your next call" with its
            // info glyph under the header (and announces it).
            SettingsParts.Card {
                id: ttyCard
                visible: root.page === "accessibility" && !root.subPage
                property bool changed: false
                icon: "accessibility-20"; title: qsTr("Teletypewriter (TTY) mode")
                subtitle: qsTr("Use the TTY mode to communicate using text over the phone. For this to work, you’ll need to connect a TTY device.")
                trailing: Component { SettingsParts.Toggle { on: backend.setting("ttyMode") === "true"; accessibleName: qsTr("Teletypewriter (TTY) mode"); onToggled: v => { backend.setSetting("ttyMode", v ? "true" : "false"); on = v; ttyCard.changed = true } } }
                // Measured on winpc 2026-11-17: the glyph 8 left of the
                // text column, 16 under the subtitle; the text 10 after it;
                // the card 129.3 tall then.
                Row {
                    visible: ttyCard.changed
                    x: -8
                    spacing: 10
                    FluentIcon { name: "info-20"; size: 20; color: theme.text }
                    Text {
                        height: 20; verticalAlignment: Text.AlignVCenter
                        text: qsTr("Changes will be applied for your next call")
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: text
                    }
                }
            }

            // ---- Devices: Audio (Teams' Settings ▸ Devices, measured on
            // winpc 2026-11-14) ----
            // "Audio" (14/700) over the "Audio settings" card: Speaker and
            // Microphone (292.7 px dropdowns), Automatically adjust mic
            // sensitivity, a divider, Noise suppression with its two
            // choices (Voice isolation needs Microsoft's voice profile, so
            // Teams shows it disabled), a divider and Secondary Ringer.
            // "Make a test call" places Teams' test call
            // (call-and-meeting-window.md §12a), and Spatial audio follows
            // (calling::spatial). Teams' headset button rows (calling::
            // hid_telephony) sit between the test call and Noise suppression.
            Text {
                visible: root.page === "devices" && !root.subPage
                width: parent.width; height: 44
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Audio")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                id: devices
                visible: root.page === "devices" && !root.subPage
                icon: "speaker-settings-20"; title: qsTr("Audio settings")
                readonly property var list: root.page === "devices" ? JSON.parse(backend.audioDevices()) : { inputs: [], outputs: [] }
                property bool noise: root.local("noiseSuppression", "on") !== "off"
                SettingsParts.SubHeading { text: qsTr("Speaker", "calling:kp3u3qpn") }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["default"].concat(devices.list.outputs)
                    options: values.map(v => ({ label: v === "default" ? qsTr("Default") : v }))
                    current: Math.max(0, values.indexOf(root.local("speakerDevice", "default")))
                    accessibleName: qsTr("Speaker", "calling:kp3u3qpn")
                    onPicked: i => backend.setSetting("speakerDevice", values[i])
                }
                SettingsParts.Gap { size: 30.7 }
                SettingsParts.SubHeading { text: qsTr("Microphone") }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["default"].concat(devices.list.inputs)
                    options: values.map(v => ({ label: v === "default" ? qsTr("Default") : v }))
                    current: Math.max(0, values.indexOf(root.local("micDevice", "default")))
                    accessibleName: qsTr("Microphone")
                    onPicked: i => backend.setSetting("micDevice", values[i])
                }
                SettingsParts.Gap { size: 22 }
                SettingsParts.SwitchRow {
                    id: agcRow
                    label: qsTr("Automatically adjust mic sensitivity")
                    on: root.local("autoGainControl", "on") !== "off"
                    onToggled: v => { backend.setSetting("autoGainControl", v ? "on" : "off"); agcRow.on = v }
                }
                // Teams' "Make a test call" (start-echo-bot-call, measured
                // on winpc 2026-11-16): an outlined button with its glyph,
                // 30 under the row above and 30 over the divider, 12 left
                // of the card's text. It places Teams' test call.
                SettingsParts.Gap { size: 30 }
                SettingsParts.Button {
                    x: -12
                    icon: "test-call-20"
                    label: qsTr("Make a test call")
                    enabled: backend.callState === "" || backend.callState === "ended"
                    onClicked: backend.makeTestCall()
                }
                SettingsParts.Gap { size: 30 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#000000") }
                // Teams' headset call controls (HID telephony; measured on
                // winpc 2026-11-17): "Audio device button controls" with
                // its headset glyph, 30.6 under the divider, and "Transfer
                // controls to this app" (disabled, with Teams' tooltip,
                // while this OST already answers the buttons; another OST
                // may hold them), then "Sync audio device buttons when in
                // use on this app" 30 under it, its switch centred on its
                // two lines, 30 over the next divider. The switch is Teams'
                // audioDeviceSyncEnabled, kept on this device (on unless
                // turned off): off, the headset's call buttons do nothing
                // and its lights stay as they are; the Teams button still
                // works.
                SettingsParts.Gap { size: 30.6 }
                Item {
                    id: hidRow
                    property var status: ({})
                    function refresh() { try { status = JSON.parse(backend.headsetStatus()) } catch (e) { status = {} } }
                    Component.onCompleted: refresh()
                    Timer { running: devices.visible; interval: 1000; repeat: true; onTriggered: hidRow.refresh() }
                    readonly property bool hasControl: !!status.has_control
                    width: parent.width; height: 36
                    FluentIcon { x: -38; y: 8; name: "headset-20"; size: 20; color: theme.text }
                    Column {
                        width: parent.width - transferBtn.width - 28 - 24
                        Text { width: parent.width; text: qsTr("Audio device button controls"); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        Text { width: parent.width; text: qsTr("Choose whether this OST app responds to buttons on connected audio devices."); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                    }
                    Rectangle {
                        id: transferBtn
                        readonly property bool usable: !hidRow.hasControl
                        anchors.right: parent.right; anchors.rightMargin: 28
                        y: 2.4; width: transferText.implicitWidth + 25.4; height: 31.3; radius: 4
                        color: !usable ? theme.bgDisabled : tbh.pressed ? theme.menuHover : tbHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                        border.color: !usable ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF"); border.width: 0.67
                        Text { id: transferText; anchors.centerIn: parent; text: qsTr("Transfer controls to this app"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: transferBtn.usable ? theme.onFill(transferBtn, theme.text) : theme.disabled }
                        HoverHandler { id: tbHover; cursorShape: transferBtn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { id: tbh; enabled: transferBtn.usable; onTapped: { backend.headsetTakeControl(); hidRow.refresh() } }
                        ArrowTip { visible: tbHover.hovered && !transferBtn.usable; tipText: qsTr("This app already responds to buttons on your audio device.") }
                        Accessible.role: Accessible.Button
                        Accessible.name: transferBtn.usable ? qsTr("Transfer controls to this app") : qsTr("This app already responds to buttons on your audio device.")
                    }
                }
                SettingsParts.Gap { size: 22 }
                SettingsParts.SwitchRow {
                    id: syncRow
                    label: qsTr("Sync audio device buttons when in use on this app")
                    sublabel: qsTr("The Teams buttons will always work when this app is in use. (Recommended)")
                    centred: true
                    on: root.local("audioDeviceSyncEnabled", "true") !== "false"
                    onToggled: v => { backend.setSetting("audioDeviceSyncEnabled", v ? "true" : "false"); syncRow.on = v }
                }
                SettingsParts.Gap { size: 23 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#000000") }
                // Noise suppression: its title 38.7 under the divider (winpc 2026-11-17).
                SettingsParts.Gap { size: 30 }
                SettingsParts.SwitchRow {
                    label: qsTr("Noise suppression")
                    on: devices.noise
                    onToggled: v => { devices.noise = v; backend.setNoiseSuppression(v) }
                }
                // Teams' choice (358966 re): Voice isolation needs a voice
                // profile (Recognition); the choice is kept on the device
                // (noiseSuppressionMode Pns / Auto) and acted on by OST's
                // own isolator (calling::voice_isolation, TASK-0181).
                readonly property var vi: backend.voiceIsolationJson ? JSON.parse(backend.voiceIsolationJson) : ({})
                readonly property bool isolation: vi.profile === true && vi.mode === "Pns"
                SettingsParts.RadioRow {
                    label: qsTr("Background noise only")
                    sublabel: "Enable this to enhance your microphone audio quality by removing background noise."
                    checked: !devices.isolation
                    usable: devices.noise
                    onPicked: { backend.setSetting("noiseSuppressionMode", "Auto"); backend.applyVoiceIsolation() }
                }
                SettingsParts.Gap { size: 4 }
                SettingsParts.RadioRow {
                    label: qsTr("Voice isolation")
                    sublabel: qsTr("Isolate your voice from background noise and other voices while speaking. Only your voice will be audible.")
                    checked: devices.isolation
                    usable: devices.noise && devices.vi.profile === true
                    onPicked: { backend.setSetting("noiseSuppressionMode", "Pns"); backend.applyVoiceIsolation() }
                }
                SettingsParts.Gap { size: 24 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#000000") }
                // Teams' Spatial audio (measured on winpc 2026-11-14: 30.7
                // under the divider, the switch centred on the title and its
                // two lines, 30 over the next divider). Off unless turned on
                // (enableSpatialAudioDefaultOn is off); shown Off and
                // disabled when the speaker can't play it (not stereo, or
                // Bluetooth) or in a 1:1 call, as Teams' SpatialAudioContainer.
                // Kept on this device (Teams' spatialAudioEnabled).
                SettingsParts.Gap { size: 22.7 }
                // Its glyph (Fluent's person-sound-spatial, Teams'
                // SpatialAudioIcon) sits in the card's icon column, centred
                // on the text (winpc 2026-11-17).
                Item {
                    width: parent.width; height: spatialRow.height
                    FluentIcon {
                        x: -38; y: 8 + (spatialRow.height - 15 - 20) / 2
                        name: "person-sound-spatial-20"; size: 20
                        color: theme.text
                    }
                    SettingsParts.SwitchRow {
                        id: spatialRow
                        readonly property bool capable: root.page === "devices" && backend.spatialAudioCapable()
                        readonly property bool inOneToOne: backend.callState === "connected" && !callWindow.meeting
                        label: qsTr("Spatial audio")
                        sublabel: qsTr("Voices will sound like they're coming from where each person is positioned on your screen. Not yet available with wireless headphones. ") + qsTr("Available with Together mode, Gallery and Speaker view.")
                        link: qsTr("Learn more")
                        centred: true
                        rowHeight: 36
                        usable: capable && !inOneToOne
                        on: usable && root.local("spatialAudio", "false") === "true"
                        onToggled: v => { backend.setSetting("spatialAudio", v ? "true" : "false"); on = v }
                        onLinkActivated: Qt.openUrlExternally("https://support.microsoft.com/en-us/office/spatial-audio-in-teams-meetings-547b5f81-1825-4ee1-a1cf-f02e12db4fdb")
                    }
                }
                SettingsParts.Gap { size: 22.6 }
                Rectangle { x: -44.3; width: devices.width - 25.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#000000") }
                SettingsParts.Gap { size: 30 }
                SettingsParts.SubHeading { text: qsTr("Secondary Ringer") }
                SettingsParts.Gap { size: 16.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    readonly property var values: ["none"].concat(devices.list.outputs)
                    options: values.map(v => ({ label: v === "none" ? qsTr("None") : v }))
                    current: Math.max(0, values.indexOf(root.local("secondaryRinger", "none")))
                    accessibleName: qsTr("Secondary Ringer")
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
            // Soft focus, with "Automatically adjust camera controls" and
            // "Open camera settings" under Camera (the camera's V4L2
            // controls, calling::camera_controls). Super resolution is
            // TASK-0139's.
            Text {
                visible: root.page === "devices" && !root.subPage
                width: parent.width; height: 44
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Video")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                id: videoCard
                visible: root.page === "devices" && !root.subPage
                icon: "video-20"; title: qsTr("Video settings")
                readonly property bool showing: visible && root.visible
                property bool previewing: false
                property bool picking: false
                property var cameras: []
                property string currentCamera: ""
                /// Teams' switch: your choice, else the camera's own state.
                function autoCamera() {
                    const chosen = root.local("autoCameraControls", "")
                    if (chosen !== "") return chosen === "true"
                    return currentCamera !== "" && backend.cameraAutoControls(currentCamera) === "true"
                }
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
                // A call takes the camera (Make a test call starts one from
                // this page, camera on): the preview lets go of it, and
                // comes back once the call is over.
                Connections {
                    target: backend
                    function onCallStateChanged() {
                        const inCall = backend.callState !== "" && backend.callState !== "ended"
                        if (inCall && videoCard.previewing) { videoCard.previewing = false; backend.setCameraPreview(false) }
                        else if (backend.callState === "" && videoCard.showing && !videoCard.previewing && videoCard.cameras.length > 0)
                            videoCard.previewing = backend.setCameraPreview(true)
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
                            id: hcFill7
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 24
                            color: Qt.rgba(0, 0, 0, 0.5)
                            Text {
                                anchors.centerIn: parent
                                text: videoEffects.greenScreen ? qsTr("What is your background color?") : qsTr("Preview")
                                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                color: theme.onFill(hcFill7, "white")
                            }
                            Rectangle {
                                visible: videoEffects.greenScreen
                                x: parent.width - 23; y: 1; width: 22; height: 22; radius: 5
                                color: "transparent"; border.color: "white"; border.width: 2
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 3
                                    color: videoCard.picking ? theme.pick("#F5F5F5", "#3D3D3D", "#000000") : (videoEffects.greenScreenColor || videoEffects.detectedColor || theme.hc("#FFFFFF", "#000000"))
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
                                ToolTip.text: qsTr("Select a color")
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Select a color")
                            }
                        }
                    }
                }
                SettingsParts.SubHeading { text: qsTr("Camera") }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 292.7; height: 30
                    options: videoCard.cameras.map(c => ({ label: c.name }))
                    current: Math.max(0, videoCard.cameras.findIndex(c => c.path === videoCard.currentCamera))
                    accessibleName: qsTr("Camera")
                    onPicked: i => {
                        const c = videoCard.cameras[i]
                        if (!c || c.path === videoCard.currentCamera) return
                        videoCard.currentCamera = c.path
                        backend.setCameraDevice(c.path)
                        if (videoCard.previewing) { backend.setCameraPreview(false); backend.setCameraPreview(true) }
                        autoCamRow.on = videoCard.autoCamera()
                    }
                }
                SettingsParts.Gap { size: 30 }
                // Teams' "Automatically adjust camera controls" (measured on
                // winpc 2026-11-14: a 36 px switch row 30.6 under the
                // camera; with it off, "Open camera settings" (14, brand)
                // right under it and Teams' note (12, on a 17.1 line), 30
                // over Green Screen). The switch puts the camera's own
                // automatic controls on or off (V4L2); it shows your choice,
                // else what the camera is set to. Kept on this device
                // (Teams' automaticCameraSettingsSelected).
                SettingsParts.SwitchRow {
                    id: autoCamRow
                    label: qsTr("Automatically adjust camera controls")
                    rowHeight: on ? 66 : 36
                    on: videoCard.showing && videoCard.autoCamera()
                    onToggled: v => { backend.setCameraAutoControls(videoCard.currentCamera, v); on = v }
                }
                SettingsParts.Link {
                    visible: !autoCamRow.on
                    height: 16.1
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Open camera settings")
                    onClicked: cameraSettings.show(videoCard.currentCamera, (videoCard.cameras.find(c => c.path === videoCard.currentCamera) || {}).name || "")
                }
                Text {
                    visible: !autoCamRow.on
                    text: qsTr("Some settings might not be available for all camera types.")
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 17.1; lineHeightMode: Text.FixedHeight
                    color: theme.textSecondary
                }
                SettingsParts.Gap { visible: !autoCamRow.on; size: 30.1 }
                SettingsParts.SwitchRow {
                    id: greenScreenRow
                    label: qsTr("Green Screen")
                    sublabel: qsTr("Turn on Green screen for a better look when you're using a virtual background.")
                    on: videoEffects.greenScreen
                    onToggled: v => {
                        if (!v && videoCard.picking) { videoCard.picking = false; backend.setGreenScreenPicking(false) }
                        videoEffects.setGreenScreen(v)
                    }
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Mirror my video")
                    sublabel: qsTr("Changing this setting will only change the view for you. This setting doesn’t currently work in Together mode.")
                    on: videoEffects.mirror
                    onToggled: v => videoEffects.setMirror(v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Adjust brightness")
                    sublabel: qsTr("Enhance the quality of your video in low light conditions.")
                    on: videoEffects.brightness
                    onToggled: v => videoEffects.setBrightness(v)
                }
                SettingsParts.SwitchRow {
                    label: qsTr("Soft focus")
                    sublabel: qsTr("Smoothen your appearance for a polished look.")
                    on: videoEffects.softFocus
                    onToggled: v => videoEffects.setSoftFocus(v)
                }
            }
            CameraSettingsDialog { id: cameraSettings }
            // Teams' Connected devices (measured on winpc 2026-11-15, 204.9
            // tall): "Manage your connected devices" with Manage devices
            // (Teams' paired phones, its Better Together list), and
            // "Automatically activate meeting room mode when in a meeting"
            // with its explanation and Learn More (Teams' clientPreferences
            // byod.pushToRoomAudio, on unless turned off, kept on the device).
            SettingsParts.Card {
                visible: root.page === "devices" && !root.subPage
                icon: "laptop-20"; title: qsTr("Connected devices")
                bottomPad: 16.3
                SettingsParts.ButtonRow {
                    label: qsTr("Manage your connected devices"); buttonText: qsTr("Manage devices")
                    onClicked: root.subPage = "connected"
                }
                SettingsParts.Gap { size: 21.6 }
                SettingsParts.SwitchRow {
                    rowHeight: 36
                    label: qsTr("Automatically activate meeting room mode when in a meeting")
                    // Teams' one sentence with its Learn More link (<0>).
                    readonly property string msg: qsTr("Optimizes meeting setup for connected audio/video devices and room displays. Attendees see only meeting content on the room display. <0>Learn More</0>")
                    sublabel: msg.replace(/\s*<0>[\s\S]*<\/0>\s*/, " ").trim()
                    on: root.local("pushToRoomAudio", "true") !== "false"
                    onToggled: v => backend.setSetting("pushToRoomAudio", v ? "true" : "false")
                    link: (msg.match(/<0>([\s\S]*)<\/0>/) || ["", qsTr("Learn More")])[1]; centred: true
                    onLinkActivated: Qt.openUrlExternally("https://aka.ms/meetingroommode")
                }
            }
            // Devices ▸ Manage devices (Teams' BttDeviceSettings): "Select a
            // device to connect", then each Teams phone paired with this PC
            // (Better Together): Teams' screen-and-phone glyph, the phone's
            // name, "Connected" while it is, and Disconnect (Teams'
            // betterTogetherUnpairDevice).
            Column {
                id: btDevices
                visible: root.page === "devices" && root.subPage === "connected"
                width: parent.width
                spacing: 15
                property var devices: []
                function reload() { try { btDevices.devices = JSON.parse(backend.betterTogetherDevices()) } catch (e) { btDevices.devices = [] } }
                onVisibleChanged: if (visible) reload()
                Connections { target: backend; function onBetterTogetherChanged() { btDevices.reload() } }
                Text {
                    width: parent.width; height: 20
                    text: qsTr("Select a device to connect")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                // Teams' BttDeviceSettings styles (its Griffel classes): the
                // list 15 under the text (Flex gap.medium) and 15 apart;
                // each phone a 10-padded, hoverable column (gap.small 10):
                // the glyph, its name (16 semibold, 55rem wide), "Connected"
                // (14) while it is, then Disconnect.
                Repeater {
                    model: btDevices.devices
                    delegate: Rectangle {
                        id: btRow
                        required property var modelData
                        width: btDevices.width
                        height: btCol.height + 20
                        radius: 4
                        color: btHover.hovered ? theme.pick("#F0F0F0", "#343434", "transparent") : "transparent"
                        HoverHandler { id: btHover; cursorShape: Qt.PointingHandCursor }
                        Column {
                            id: btCol
                            x: 10; y: 10
                            width: parent.width - 20
                            spacing: 10
                            FluentIcon { name: "video-person-call-20"; size: 20; color: theme.onFill(btRow, theme.text) }
                            Column {
                                width: parent.width
                                Text {
                                    width: Math.min(parent.width, 550); text: btRow.modelData.deviceName; elide: Text.ElideRight
                                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                                    color: theme.onFill(btRow, theme.text)
                                }
                                Text {
                                    visible: btRow.modelData.connectionStatus === 0
                                    width: parent.width; text: qsTr("Connected")
                                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.onFill(btRow, theme.text)
                                }
                            }
                            SettingsParts.Button {
                                label: qsTr("Disconnect")
                                onClicked: backend.betterTogetherUnpair(btRow.modelData.endPointId)
                            }
                        }
                        Accessible.role: Accessible.Grouping
                        Accessible.name: btRow.modelData.deviceName
                    }
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
                // Teams' voicemail settings (the voice admin settings'
                // electedSettings), with each change shown at once.
                readonly property var vm: Object.assign({ vmUseOof: false, vmUseAutoRepliesForOof: false, vmCallAnswerRule: "", vmAudioLang: "", vmDefaultGreetingPromptOverwrite: "", vmDefaultOofGreetingPromptOverwrite: "", vmTransferTarget: null }, root.mt.vm || {})
                // Teams' five answer rules (settings-app bA), in its order.
                readonly property var rules: ["RegularVoicemail", "VoicemailWithTransferOption", "PromptOnly", "PromptOnlyWithTransfer", "DeclineCall"]
                // A transfer rule picked with no target yet: shown, with the
                // people picker, but saved only once someone is picked.
                property string pendingRule: ""
                // Delete clears the shown target only (Teams saves nothing
                // until someone else is picked).
                property bool targetCleared: false
                readonly property string rule: pendingRule || vm.vmCallAnswerRule || ""
                readonly property bool transferRule: rule === "VoicemailWithTransferOption" || rule === "PromptOnlyWithTransfer"
                readonly property string targetMri: {
                    const t = vm.vmTransferTarget
                    if (!t || !t.type) return ""
                    if (t.type === "Pstn" || t.type === "Unspecified") return "4:" + (t.telUri || "")
                    if (t.type === "ApplicationEndpoint") return "28:orgid:" + (t.objectId || "")
                    if (t.type === "User") return "8:orgid:" + (t.objectId || "")
                    return t.objectId || ""
                }
                onTargetMriChanged: if (targetMri && !targetMri.startsWith("4:")) { backend.resolveNames(JSON.stringify([targetMri])); backend.loadPresences(JSON.stringify([targetMri])) }
                function pickRule(r) {
                    if ((r === "VoicemailWithTransferOption" || r === "PromptOnlyWithTransfer") && !vm.vmTransferTarget) { pendingRule = r; return }
                    pendingRule = ""
                    root.setMt("voicemail", { vmCallAnswerRule: r, vmEnabled: true })
                }
                // Teams' rg: the picked person or number becomes the target,
                // saved with the transfer rule.
                function pickTarget(mri, oid) {
                    root.setMt("voicemail", { vmTransferTarget: {
                        objectId: oid || null, tenantId: oid ? backend.tenantId() : null,
                        type: oid ? (mri.startsWith("8:") ? "User" : "ApplicationEndpoint") : "Pstn",
                        sipUri: null, telUri: mri.replace("4:", "") }, vmCallAnswerRule: rule })
                    pendingRule = ""
                    targetCleared = false
                }
                // Teams' voicemail greeting languages (measured on winpc
                // 2026-11-14, in its order): [native, English, code].
                readonly property var greetingLanguages: [
                    ["Arabic (Egypt)", qsTr("Arabic (Egypt)"), "ar-eg"], ["Bahasa Indonesia (Indonesia)", qsTr("Indonesian (Indonesia)"), "id-id"],
                    ["Català (Català)", qsTr("Catalan (Catalan)"), "ca-es"], ["Čeština (Česká republika)", qsTr("Czech (Czechia)"), "cs-cz"],
                    ["Dansk (Danmark)", qsTr("Danish (Denmark)"), "da-dk"], ["Deutsch (Deutschland)", qsTr("German (Germany)"), "de-de"],
                    ["English (Australia)", qsTr("English (Australia)"), "en-au"], ["English (Canada)", qsTr("English (Canada)"), "en-ca"],
                    ["English (India)", qsTr("English (India)"), "en-in"], ["English (United Kingdom)", qsTr("English (United Kingdom)"), "en-gb"],
                    ["English (United States)", qsTr("English (United States)"), "en-us"], ["Español (España, alfabetización internacional)", qsTr("Spanish (Spain)"), "es-es"],
                    ["Español (México)", qsTr("Spanish (Mexico)"), "es-mx"], ["Français (Canada)", qsTr("French (Canada)"), "fr-ca"],
                    ["Français (France)", qsTr("French (France)"), "fr-fr"], ["Hrvatski (Hrvatska)", qsTr("Croatian (Croatia)"), "hr-hr"],
                    ["Italiano (Italia)", qsTr("Italian (Italy)"), "it-it"], ["Magyar (Magyarország)", qsTr("Hungarian (Hungary)"), "hu-hu"],
                    ["Nederlands (Nederland)", qsTr("Dutch (Netherlands)"), "nl-nl"], ["Norsk, Bokmål (Norge)", qsTr("Norwegian, Bokmål (Norway)"), "nb-no"],
                    ["Polski (Polska)", qsTr("Polish (Poland)"), "pl-pl"], ["Português (Brasil)", qsTr("Portuguese (Brazil)"), "pt-br"],
                    ["Português (Portugal)", qsTr("Portuguese (Portugal)"), "pt-pt"], ["Română (România)", qsTr("Romanian (Romania)"), "ro-ro"],
                    ["Slovenčina (Slovenská republika)", qsTr("Slovak (Slovakia)"), "sk-sk"], ["Slovenščina (Slovenija)", qsTr("Slovenian (Slovenia)"), "sl-si"],
                    ["Suomi (Suomi)", qsTr("Finnish (Finland)"), "fi-fi"], ["Svenska (Sverige)", qsTr("Swedish (Sweden)"), "sv-se"],
                    ["Türkçe (Türkiye)", qsTr("Turkish (Türkiye)"), "tr-tr"], ["Ελληνικά (Ελλάδας)", qsTr("Greek (Greece)"), "el-gr"],
                    ["Русский (Россия)", qsTr("Russian (Russia)"), "ru-ru"], ["ไทย (ไทย)", qsTr("Thai (Thailand)"), "th-th"],
                    ["한국어 (대한민국)", qsTr("Korean (Korea)"), "ko-kr"], ["中文(中国)", qsTr("Chinese (China)"), "zh-cn"],
                    ["中文(台灣)", qsTr("Chinese (Taiwan)"), "zh-tw"], ["中文(香港特別行政區)", qsTr("Chinese (Traditional, Hong Kong SAR)"), "zh-hk"],
                    ["日本語 (日本)", qsTr("Japanese (Japan)"), "ja-jp"]
                ]
                function setVm(k, v) { const b = {}; b[k] = v; root.setMt("voicemail", b) }
            }
            Text {
                visible: root.page === "calls"
                text: qsTr("Call handling and forwarding")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "call-forward-20"; title: qsTr("Call handling and forwarding")
                bottomPad: 21.4
                // Teams Phone (Enterprise Voice) users get Teams 26304's call
                // handling (settings-app Fg / Po / also-ring; api::
                // call_forwarding): Forward all my calls with where to, else
                // who else rings and the delay, then unanswered calls; each
                // target type only where the calling policy allows it.
                SettingsParts.SwitchRow {
                    visible: fwd.ev
                    label: qsTr("Forward all my calls")
                    on: fwd.immediate
                    onToggled: v => fwd.change(v ? { op: "forwardAll", targetType: fwd.vmAllowed ? "Voicemail" : "SingleTarget" } : { op: "forwardAllOff" })
                }
                QtObject {
                    id: fwd
                    readonly property var pol: root.mt.callingPolicy || {}
                    readonly property bool ev: pol.ev === true
                    readonly property var r: (root.mt.voice || {}).callRedirectionSettings || {}
                    readonly property var cf: r.callForwardingSettings || {}
                    readonly property var un: r.unansweredCallSettings || {}
                    readonly property bool immediate: cf.isEnabled === true && (cf.forwardingType || "").toLowerCase() === "immediate"
                    readonly property bool vmAllowed: pol.allowVoicemail !== "AlwaysDisabled"
                    readonly property bool toUser: pol.allowCallForwardingToUser === true
                    readonly property bool toPhone: pol.allowCallForwardingToPhone === true
                    readonly property bool groups: pol.allowCallGroups === true && (((r.callGroupDetails || {}).targets || []).length > 0)
                    readonly property bool delegates: pol.allowDelegation === true && !!r.hasDelegates
                    readonly property string newTarget: toPhone ? (toUser ? "contact_or_number" : "number") : "contact"
                    function change(v) { root.setMt("forwarding", v) }
                    function items(kind) {
                        const out = []
                        const single = { contact_or_number: [qsTr("Forward to a new number or contact"), qsTr("Also ring a new number or contact"), qsTr("Redirect to a new number or contact")],
                                         number: [qsTr("Forward to a new number"), qsTr("Also ring a new number"), qsTr("Redirect to a new number")],
                                         contact: [qsTr("Forward to a new contact"), qsTr("Also ring a new contact"), qsTr("Redirect to a new contact")] }[newTarget]
                        const k = kind === "forward" ? 0 : kind === "also" ? 1 : 2
                        if (kind === "also") out.push({ value: "DoNothing", label: qsTr("Do not ring anyone else") })
                        if (kind === "unanswered") out.push({ value: "DoNothing", label: qsTr("Do not redirect calls") })
                        if (vmAllowed && kind !== "also") out.push({ value: "Voicemail", label: kind === "forward" ? qsTr("Forward to voicemail") : qsTr("Redirect to voicemail") })
                        if (toUser || toPhone) out.push({ value: "SingleTarget", label: single[k] })
                        if (groups && !(kind === "unanswered" && (cf.targetType || "") === "Group")) out.push({ value: "Group", label: [qsTr("Forward to call group"), qsTr("Also ring call group"), qsTr("Redirect to call group")][k] })
                        if (delegates && !(kind === "unanswered" && (cf.targetType || "") === "MyDelegates")) out.push({ value: "MyDelegates", label: [qsTr("Forward to delegates"), qsTr("Also ring delegates"), qsTr("Redirect to delegates")][k] })
                        return out
                    }
                    readonly property string alsoType: !cf.isEnabled ? "DoNothing" : (cf.targetType || "DoNothing")
                    readonly property string unType: un.isEnabled === false ? "DoNothing" : (un.targetType || "Voicemail")
                    readonly property var delays: [0, 5, 10, 15, 20, 30, 40, 50, 60]
                }
                SettingsParts.Divider { visible: fwd.ev }
                SettingsParts.SubHeading { visible: fwd.ev && fwd.immediate; text: qsTr("Choose how all your calls will be forwarded"); gapAbove: 15.6 }
                SettingsParts.SubHeading { visible: fwd.ev && !fwd.immediate; text: qsTr("When you receive a call"); gapAbove: 15.6 }
                SettingsParts.Gap { visible: fwd.ev; size: 10 }
                OutlineDropdown {
                    visible: fwd.ev
                    width: 293.3; height: 30
                    readonly property var list: fwd.items(fwd.immediate ? "forward" : "also")
                    readonly property string cur: fwd.immediate ? (fwd.cf.targetType || "Voicemail") : fwd.alsoType
                    options: list.map(o => ({ label: o.label }))
                    current: Math.max(0, list.findIndex(o => o.value.toLowerCase() === cur.toLowerCase()))
                    accessibleName: fwd.immediate ? qsTr("Choose how all your calls will be forwarded") : qsTr("When you receive a call")
                    onPicked: i => {
                        const t = list[i].value
                        if (t === "SingleTarget") { fwdPicker.mode = fwd.immediate ? "forward" : "also"; fwdPicker.open = true; return }
                        fwdPicker.open = false
                        fwd.change(fwd.immediate ? { op: "forwardAll", targetType: t } : { op: "alsoRing", targetType: t })
                    }
                }
                // The person or number (Teams' target box under the dropdown,
                // as the voicemail transfer target's).
                SettingsParts.Gap { visible: fwdPickerRow.visible; size: 15.6 }
                Item {
                    id: fwdPickerRow
                    readonly property string shown: (fwd.immediate || fwd.alsoType === "SingleTarget") ? (fwd.cf.target || "") : ""
                    visible: fwd.ev && (fwdPicker.open && fwdPicker.mode !== "unanswered" || (fwd.cf.targetType === "SingleTarget" && fwd.cf.isEnabled === true))
                    width: parent.width; height: visible ? fwdPicker.height : 0
                    VoicemailTransferPicker {
                        id: fwdPicker
                        property bool open: false
                        property string mode: "also"
                        anchors.right: parent.right
                        phoneSuggestions: fwd.toPhone
                        targetMri: fwd.cf.targetType === "SingleTarget" ? (fwd.cf.target || "") : ""
                        targetName: { const n = backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({}); return n[targetMri] || "" }
                        people: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.items || [] }
                        peopleQuery: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.query || "" }
                        onSearch: q => backend.newChatPeople(q)
                        onPicked: (mri, oid, name) => { open = false; fwd.change(fwd.immediate ? { op: "forwardAll", targetType: "SingleTarget", target: mri } : { op: "alsoRing", targetType: "SingleTarget", target: mri }) }
                        onRemoved: open = true
                        onTargetMriChanged: if (targetMri && !targetMri.startsWith("4:")) backend.resolveNames(JSON.stringify([targetMri]))
                    }
                }
                // Teams' "Delay for this many seconds before ringing" while
                // someone else also rings.
                SettingsParts.SubHeading { visible: fwd.ev && !fwd.immediate && fwd.alsoType !== "DoNothing"; text: qsTr("Delay for this many seconds before ringing"); gapAbove: 15.7 }
                SettingsParts.Gap { visible: fwd.ev && !fwd.immediate && fwd.alsoType !== "DoNothing"; size: 10 }
                OutlineDropdown {
                    visible: fwd.ev && !fwd.immediate && fwd.alsoType !== "DoNothing"
                    width: 293.3; height: 30
                    readonly property var list: fwd.delays.filter(d => !(fwd.un.isEnabled && fwd.un.delaySeconds) || d < fwd.un.delaySeconds)
                    options: list.map(d => ({ label: d === 0 ? qsTr("No delay (default)") : qsTr("%1 seconds").arg(d) }))
                    current: Math.max(0, list.indexOf(fwd.cf.delaySeconds || 0))
                    accessibleName: qsTr("Delay for this many seconds before ringing")
                    onPicked: i => fwd.change({ op: "alsoRingDelay", seconds: list[i] })
                }
                SettingsParts.SubHeading { visible: fwd.ev && (!fwd.immediate || fwd.cf.targetType === "MyDelegates"); text: qsTr("When you can't answer a call"); gapAbove: 15.6 }
                SettingsParts.Gap { visible: fwd.ev && (!fwd.immediate || fwd.cf.targetType === "MyDelegates"); size: 10 }
                OutlineDropdown {
                    visible: fwd.ev && (!fwd.immediate || fwd.cf.targetType === "MyDelegates")
                    width: 293.3; height: 30
                    readonly property var list: fwd.items("unanswered")
                    options: list.map(o => ({ label: o.label }))
                    current: Math.max(0, list.findIndex(o => o.value.toLowerCase() === fwd.unType.toLowerCase()))
                    accessibleName: qsTr("When you can't answer a call")
                    onPicked: i => {
                        const t = list[i].value
                        if (t === "SingleTarget") { unPicker.open = true; return }
                        unPicker.open = false
                        fwd.change({ op: "unanswered", targetType: t })
                    }
                }
                SettingsParts.Gap { visible: unPickerRow.visible; size: 15.6 }
                Item {
                    id: unPickerRow
                    visible: fwd.ev && (unPicker.open || fwd.unType === "SingleTarget")
                    width: parent.width; height: visible ? unPicker.height : 0
                    VoicemailTransferPicker {
                        id: unPicker
                        property bool open: false
                        anchors.right: parent.right
                        phoneSuggestions: fwd.toPhone
                        targetMri: fwd.unType === "SingleTarget" ? (fwd.un.target || "") : ""
                        targetName: { const n = backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({}); return n[targetMri] || "" }
                        people: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.items || [] }
                        peopleQuery: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.query || "" }
                        onSearch: q => backend.newChatPeople(q)
                        onPicked: (mri, oid, name) => { open = false; fwd.change({ op: "unanswered", targetType: "SingleTarget", target: mri }) }
                        onRemoved: open = true
                        onTargetMriChanged: if (targetMri && !targetMri.startsWith("4:")) backend.resolveNames(JSON.stringify([targetMri]))
                    }
                }
                SettingsParts.SubHeading { visible: fwd.ev && fwd.unType !== "DoNothing" && (!fwd.immediate || fwd.cf.targetType === "MyDelegates"); text: qsTr("Ring for this many seconds before redirecting"); gapAbove: 15.7 }
                SettingsParts.Gap { visible: fwd.ev && fwd.unType !== "DoNothing" && (!fwd.immediate || fwd.cf.targetType === "MyDelegates"); size: 10 }
                OutlineDropdown {
                    visible: fwd.ev && fwd.unType !== "DoNothing" && (!fwd.immediate || fwd.cf.targetType === "MyDelegates")
                    width: 293.3; height: 30
                    readonly property var secs: [5, 10, 15, 20, 30, 40, 50, 60]
                    options: secs.map(n => ({ label: n === 20 ? qsTr("20 seconds (default)") : qsTr("%1 seconds").arg(n) }))
                    current: Math.max(0, secs.indexOf(fwd.un.delaySeconds || 20))
                    accessibleName: qsTr("Ring for this many seconds before redirecting")
                    onPicked: i => fwd.change({ op: "unansweredDelay", seconds: secs[i] })
                }
                SettingsParts.SwitchRow {
                    visible: !fwd.ev
                    label: qsTr("Forward all calls to voicemail")
                    on: calls.forwardAll
                    onToggled: v => calls.save(v, calls.toVoicemail, calls.delay)
                }
                SettingsParts.Divider { visible: !fwd.ev && !calls.forwardAll }
                SettingsParts.SubHeading { visible: !fwd.ev && !calls.forwardAll; text: qsTr("When you can't answer a call"); gapAbove: 15.6 }
                SettingsParts.Gap { visible: !fwd.ev && !calls.forwardAll; size: 10 }
                OutlineDropdown {
                    visible: !fwd.ev && !calls.forwardAll
                    width: 293.3; height: 30
                    options: [{ label: qsTr("Do not redirect calls") }, { label: qsTr("Redirect to voicemail") }]
                    current: calls.toVoicemail ? 1 : 0
                    accessibleName: qsTr("When you can't answer a call")
                    onPicked: i => calls.save(false, i === 1, calls.delay)
                }
                SettingsParts.SubHeading { visible: !fwd.ev && !calls.forwardAll && calls.toVoicemail; text: qsTr("Ring for this many seconds before redirecting"); gapAbove: 15.7 }
                SettingsParts.Gap { visible: !fwd.ev && !calls.forwardAll && calls.toVoicemail; size: 10 }
                OutlineDropdown {
                    visible: !fwd.ev && !calls.forwardAll && calls.toVoicemail
                    width: 293.3; height: 30
                    readonly property var secs: [5, 10, 15, 20, 30, 40, 50, 60]
                    options: secs.map(n => ({ label: n === 20 ? qsTr("20 seconds (default)") : qsTr("%1 seconds").arg(n) }))
                    current: Math.max(0, secs.indexOf(calls.delay))
                    accessibleName: qsTr("Ring for this many seconds before redirecting")
                    onPicked: i => calls.save(false, true, secs[i])
                }
                // Teams' "Choose a ringtone for you" (measured on winpc
                // 2026-11-15): 31.4 under the row above, the dropdown
                // (Teams' 18 ringtones, Ring as "Default") with Preview
                // ringtone 10.7 after it; saved with Teams' ringtone
                // settings and rung by Main.qml's ringer.
                // Teams Phone users also choose ringtones for forwarded (call
                // group) and delegated calls (settings-app n1: Regular,
                // CallGroup, Delegate), each 15.6 under the one before.
                Repeater {
                    model: fwd.ev ? [{ kind: "Regular", label: qsTr("Choose a ringtone for you") }, { kind: "CallGroup", label: qsTr("Choose a ringtone for forwarded calls") }, { kind: "Delegate", label: qsTr("Choose a ringtone for delegated calls") }]
                                  : [{ kind: "Regular", label: qsTr("Choose a ringtone for you") }]
                    Column {
                        id: toneRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        SettingsParts.SubHeading { text: toneRow.modelData.label; gapAbove: toneRow.index === 0 ? 32 : 15.7 }
                        SettingsParts.Gap { size: 10.6 }
                        Row {
                            spacing: 10.7
                            readonly property var names: ["Ring", "Beep", "Bop", "Bounce", "Bubbles", "BubblesLoud", "DripDrop", "Eureka", "Flutter", "HighScore", "NextLevel", "Plink", "Remix", "RingRing", "Ripple", "Spacetime", "WishGranted", "Wobble"]
                            readonly property var labels: [qsTr("Default"), qsTr("Beep"), qsTr("Bop"), qsTr("Bounce"), qsTr("Bubbles"), qsTr("Bubbles (Loud)"), qsTr("Drip Drop"), qsTr("Eureka"), qsTr("Flutter"), qsTr("High Score"), qsTr("Next Level"), qsTr("Plink"), qsTr("Remix"), qsTr("Ring Ring"), qsTr("Ripple"), qsTr("Spacetime"), qsTr("Wish Granted"), qsTr("Wobble")]
                            readonly property string chosen: {
                                const voice = root.mt.voice || {}
                                const list = ((voice.ringtoneSettings || {}).assignments || {}).ringToneAssignments || []
                                const own = list.find(a => a.type === toneRow.modelData.kind)
                                return own && own.value ? own.value : "Ring"
                            }
                            OutlineDropdown {
                                width: 293.3; height: 30
                                options: parent.labels.map(l => ({ label: l }))
                                current: Math.max(0, parent.names.indexOf(parent.chosen))
                                accessibleName: toneRow.modelData.label
                                onPicked: i => backend.changeSetting("mt", "ringtone", JSON.stringify(toneRow.modelData.kind === "Regular" ? parent.names[i] : { type: toneRow.modelData.kind, name: parent.names[i] }))
                            }
                            PreviewButton { height: 30; label: qsTr("Preview ringtone"); file: parent.chosen.toLowerCase() }
                        }
                    }
                }
            }
            Text {
                visible: root.page === "calls"
                text: qsTr("Voicemail")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "voicemail-20"; title: qsTr("Voicemail")
                // Teams' "Record a custom greeting" (measured on winpc
                // 2026-11-10: its button at the body's top, a divider 15 under
                // it) calls your own voicemail, where the greeting is
                // recorded (Backend record_voicemail_greeting). Voicemail
                // settings can't be read back (Teams shows them unset too);
                // what you set here shows.
                SettingsParts.ButtonRow {
                    label: qsTr("Record a custom greeting")
                    buttonText: qsTr("Record a greeting")
                    onClicked: backend.recordVoicemailGreeting()
                }
                SettingsParts.Gap { size: 15.1 }
                SettingsParts.Divider {}
                SettingsParts.SubHeading { text: qsTr("Choose a language for your default greeting"); gapAbove: 15.6 }
                SettingsParts.Gap { size: 10.7 }
                SearchCombobox {
                    width: 258.7; height: 30.7
                    options: calls.greetingLanguages.map(l => ({ key: l[2], label: l[0], sublabel: l[1] }))
                    current: calls.vm.vmAudioLang || ""
                    accessibleName: qsTr("Choose a language for your default greeting")
                    onPicked: code => calls.setVm("vmAudioLang", code)
                }
                SettingsParts.Gap { size: 15.6 }
                SettingsParts.Divider {}
                SettingsParts.SubHeading { text: qsTr("Choose what happens when the call is redirected to voicemail"); gapAbove: 15.7 }
                SettingsParts.Gap { size: 10.7 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    options: [{ label: qsTr("Let the caller record a message") }, { label: qsTr("Let the caller record a message or be transferred to someone else") }, { label: qsTr("Play your greeting and end the call") }, { label: qsTr("Play greeting then transfer the call to someone else") }, { label: qsTr("End the call without playing your greeting") }]
                    current: calls.rules.indexOf(calls.rule)
                    placeholder: qsTr("Choose what happens when the call is redirected to voicemail")
                    accessibleName: qsTr("Choose what happens when the call is redirected to voicemail")
                    onPicked: i => calls.pickRule(calls.rules[i])
                }
                // The transfer rules' target (Teams' rg, measured on winpc
                // 2026-11-19): 15.6 under the dropdown, at the body's right.
                SettingsParts.Gap { visible: calls.transferRule; size: 15.6 }
                Item {
                    visible: calls.transferRule
                    width: parent.width; height: transferPicker.height
                    VoicemailTransferPicker {
                        id: transferPicker
                        anchors.right: parent.right
                        targetMri: calls.targetCleared ? "" : calls.targetMri
                        targetName: { const n = backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({}); return n[calls.targetMri] || "" }
                        targetPresence: { const n = backend.peoplePresenceJson ? JSON.parse(backend.peoplePresenceJson) : ({}); return n[calls.targetMri] || "" }
                        people: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.items || [] }
                        peopleQuery: { const v = backend.newChatPeopleJson ? JSON.parse(backend.newChatPeopleJson) : ({}); return v.query || "" }
                        onSearch: q => backend.newChatPeople(q)
                        onPicked: (mri, oid, name) => calls.pickTarget(mri, oid)
                        // Teams' Delete only clears the box (nothing is saved
                        // until someone else is picked).
                        onRemoved: calls.targetCleared = true
                    }
                }
                SettingsParts.Gap { size: 15.6 }
                SettingsParts.Divider {}
                SettingsParts.Gap { size: 15.7 }
                SettingsParts.ButtonRow {
                    label: qsTr("Set up text-to-speech customized greeting option")
                    sublabel: qsTr("If you\u2019ve recorded a greeting, it\u2019ll override this option.")
                    buttonText: calls.vm.vmDefaultGreetingPromptOverwrite ? qsTr("Edit custom greeting") : qsTr("Write a custom greeting")
                    onClicked: { greetingDialog.oof = false; greetingDialog.show(calls.vm.vmDefaultGreetingPromptOverwrite || "") }
                }
                
            }
            Text {
                visible: root.page === "calls"
                text: qsTr("Manage out-of-office voicemail")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            SettingsParts.Card {
                visible: root.page === "calls"
                icon: "voicemail-arrow-back-20"; title: qsTr("Manage out-of-office voicemail")
                SettingsParts.SubHeading { text: qsTr("When should your greeting play") }
                SettingsParts.Gap { size: 15 }
                SettingsParts.CheckRow { label: qsTr("All the time"); checked: calls.vm.vmUseOof === true; onToggled: v => calls.setVm("vmUseOof", v) }
                SettingsParts.CheckRow { label: qsTr("When Outlook automatic replies are on"); checked: calls.vm.vmUseAutoRepliesForOof === true; onToggled: v => calls.setVm("vmUseAutoRepliesForOof", v) }
                SettingsParts.ButtonRow {
                    label: qsTr("Your custom greeting")
                    buttonText: calls.vm.vmDefaultOofGreetingPromptOverwrite ? qsTr("Edit custom greeting") : qsTr("Write a custom greeting")
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
                    color: theme.pick("#FDF3F4", "#3F1011", "#000000")
                    border.color: theme.pick("#EEACB2", "#6E0811", "#FFFFFF"); border.width: 0.67
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "error-circle-20-filled"; size: 16; color: theme.pick("#BC2F32", "#DC626D", "#FFFFFF") }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: qsTr("You are currently in a meeting. To modify your profile, please return after your meeting."); font.family: theme.font; font.pixelSize: 12; color: theme.text }
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
                    icon: "mic-20-filled"; title: qsTr("Voice Recognition")
                    enabled: !recognition.inCall && !!recognition.st.loaded
                    textWidth: !enrolled && !joined ? 484.3 : enrolled && !joined ? 416.7 : 532.7
                    about: enrolled && !joined
                        ? qsTr("Your voice profile is used to suppress background noises in Teams meetings through voice isolation and to identify you in meeting rooms, transcripts, and notes.")
                        : qsTr("Microsoft Teams, on behalf of your organization, collects and processes your pitch, inflection, and speech patterns to build and update your unique voice profile, which may be considered biometric data. Your voice profile is used to suppress background noises in Teams meetings through voice isolation and to identify you in meeting rooms, transcripts, and notes.")
                    consent: enrolled && !joined ? ""
                        : joined ? qsTr("Your voice profile will be retained as described in the data retention section of this <a>Learn More</a>.")
                        : qsTr("When you click \u201cStart voice capture\u201d you are consenting to the collection and use of your data. Your voice profile will be retained as described in the data retention section of this <a>Learn More</a>.")
                    privacyName: qsTr("Privacy policy - Voice recognition")
                    badge: enrolled ? qsTr("Voice profile complete") : joined ? qsTr("Generating voice profile") : ""
                    badgeWave: !enrolled
                    topButtons: !enrolled && !joined ? [{ label: qsTr("Start voice capture"), x: 591, act: "optin" }]
                        : enrolled && !joined ? [{ label: qsTr("Export"), x: 523.3, act: "export" }, { label: qsTr("Opt out"), x: 634.3, act: "optout" }]
                        : [{ label: qsTr("Opt out"), x: 639.3, act: "optout" }]
                    infoTip: enrolled ? qsTr("Opting out will remove your voice profile, disabling all features that use it.") : ""
                    optIn: enrolled && !joined
                    optInTitle: qsTr("Opt in to keep my voice profile up to date automatically")
                    optInAbout: qsTr("Microsoft Teams, on behalf of your organization, collects and processes your pitch, inflection, and speech patterns to build and update your unique voice profile, which may be considered biometric data.")
                    optInConsent: qsTr("When you click \u201cStart voice capture\u201d you are consenting to the collection and use of your data. Your voice profile will be retained as described in the data retention section of this <a>Learn More</a>.")
                    rowLabel: joined ? (enrolled ? qsTr("Update my voice profile now") : qsTr("Create my voice profile now")) : ""
                    rowButtons: enrolled ? [{ label: qsTr("Export"), x: 533.3, act: "export" }, { label: qsTr("Update"), x: 639.3, act: "capture" }]
                                         : [{ label: qsTr("Create"), x: 639.3, act: "capture" }]
                    onAct: what => {
                        if (what === "optin") backend.recognitionPassiveVoice(true)
                        else if (what === "optout") { if (joined) backend.recognitionPassiveVoice(false); else backend.recognitionRemoveVoice() }
                        else if (what === "export") backend.recognitionExport("voice")
                        else root.startRecognition("voice")
                    }
                }
                RecognitionCard {
                    readonly property bool enrolled: !!recognition.st.face
                    icon: "video-person-20-filled"; title: qsTr("Face Recognition")
                    enabled: !recognition.inCall && !!recognition.st.loaded
                    textWidth: enrolled ? 527.7 : 572.7
                    about: qsTr("Microsoft Teams, on behalf of your organization, collects and processes facial data to build and update your unique face profile, which may be considered biometric data. Your face profile is used to automatically recognize you during meetings, display your name, and add your name to the participant list as you walk into a Microsoft Teams Rooms with supported equipment.")
                    consent: enrolled ? qsTr("Your face profile will be retained as described in the data retention section of this <a>Learn More</a>.")
                                      : qsTr("When you click \u201cStart face capture\u201d, you are consenting to the collection and use of your data. Your face profile will be retained as described in the data retention section of this <a>Learn More</a>.")
                    privacyName: qsTr("Privacy policy - Face recognition")
                    badge: enrolled ? qsTr("Face profile complete") : ""
                    topButtons: enrolled ? [{ label: qsTr("Opt out"), x: 634.3, act: "optout" }] : []
                    infoTip: enrolled ? qsTr("Opting out will remove your face profile, disabling all features that use it.") : ""
                    rowLabel: enrolled ? qsTr("Update my face profile now") : qsTr("Create my face profile now")
                    rowButtons: enrolled ? [{ label: qsTr("Export"), x: 528.3, act: "export" }, { label: qsTr("Update"), x: 639.3, act: "capture" }]
                                         : [{ label: qsTr("Start face capture"), x: 597.9, act: "capture" }]
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
                border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
                FluentIcon { x: 18.7; y: 22.7; size: 20; name: "shield-20"; color: theme.text }
                Text { x: 68.5; y: 5.5; text: qsTr("App permissions"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    x: 68.5; y: 25.5; width: parent.width - 68.5 - 1
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: qsTr("Control what your apps can access when using Teams. Some apps have permissions enabled by default for your convenience.") + " <a href=\"https://go.microsoft.com/fwlink/?linkid=2166702&clcid=0x409\" style=\"color:" + theme.brandLink + ";text-decoration:none\">" + qsTr("Learn more") + "</a>"
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
                                color: theme.pick("#EBEBEB", "#3D3D3D", "#000000")
                            }
                            Item {
                                width: parent.width; height: 65.33
                                Image {
                                    x: 18.6; y: 16.6; width: 32; height: 32
                                    source: appRow.modelData.icon || ""
                                    sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; asynchronous: true
                                    Rectangle { anchors.fill: parent; radius: 6; color: "transparent"; border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }
                                }
                                Text { x: 68.6; y: 22.6; width: parent.width - 68.6 - 60; elide: Text.ElideRight; text: appRow.modelData.name; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                                FluentIcon { x: 754; y: 22.6; size: 20; name: appRow.expanded ? "chevron-up-20" : "chevron-down-20"; color: theme.textStrong }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: appPerms.open = appRow.expanded ? "" : appRow.modelData.id }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("App permissions for %1").arg(appRow.modelData.name)
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
                                            accessibleName: qsTr("%1 for %2").arg(permRow.modelData.title).arg(appRow.modelData.name)
                                            onToggled: v => { backend.setAppPermission(appRow.modelData.id, permRow.modelData.kind, v); appPerms.rev++ }
                                        }
                                    }
                                }
                                Text {
                                    y: 2.5
                                    textFormat: Text.StyledText
                                    text: qsTr("<strong>Note:</strong> Permission updates will be applied the next time you open or refresh this app.")
                                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.text
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: !!appPerms.data_.loading
                    x: 68.5; y: 72; text: qsTr("Loading…"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
            }

            // ---- Files and links ----
            SettingsParts.Card {
                id: downloads
                visible: root.page === "files"
                icon: "arrow-download-20"; title: qsTr("Downloads"); subtitle: qsTr("Location")
                property string where: root.page === "files" ? backend.downloadLocation() : ""
                Item {
                    width: parent.width; height: 47
                    Text { y: 4; width: parent.width - 140; elide: Text.ElideMiddle; text: downloads.where; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Rectangle {
                        id: hcFill8
                        anchors.right: parent.right; anchors.rightMargin: 28; y: -2
                        width: changeRow.implicitWidth + 16; height: 31.3; radius: 4
                        color: changeHover.hovered ? theme.menuHover : "transparent"
                        Row { id: changeRow; anchors.centerIn: parent; spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder-20"; size: 20; color: theme.onFill(hcFill8, theme.textStrong) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Change"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill8, theme.text) } }
                        HoverHandler { id: changeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: folderPick.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Change download location")
                    }
                }
                // Teams' "Always ask where to save downloaded file" (this
                // device's): each download asks for its place first.
                SettingsParts.SwitchRow {
                    label: qsTr("Always ask where to save downloaded file")
                    on: root.local("askDownloadLocation", "false") === "true"
                    onToggled: v => backend.setSetting("askDownloadLocation", v ? "true" : "false")
                }
                FolderDialog {
                    id: folderPick
                    title: qsTr("Choose a download location")
                    currentFolder: "file://" + downloads.where
                    onAccepted: { const p = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")); backend.setSetting("downloadDir", p); downloads.where = backend.downloadLocation() }
                }
            }
            SettingsParts.Card {
                visible: root.page === "files"
                id: openIn
                icon: "document-20"; title: qsTr("Always open Word, PowerPoint, and Excel files in:")
                bodyGap: 26
                // Teams' choices (docs/spec/file-actions.md): Teams (Office
                // for the web inside its window, synced "teamsV2"), Desktop
                // app when Office is installed (kept on the device; OST
                // offers the desktop's own app for Word files) and Browser
                // (synced "web"). OST opens Teams' choice in its app host
                // (api::office_open) and keeps the device's choice in
                // "fileOpenIn"; without one, the synced value decides.
                readonly property string app: root.page === "files" ? backend.officeAppName() : ""
                readonly property string synced: root.prop("userPersonalSettings", ["filesSettings", "fileOpenPreference"], "teamsV2")
                property string choice: root.page === "files" ? (backend.setting("fileOpenIn") || (synced === "web" ? "web" : "teams")) : ""
                function pick(v) {
                    backend.setSetting("fileOpenIn", v); choice = v
                    if (v === "web" || v === "teams") root.setProp("userPersonalSettings", "filesSettings.fileOpenPreference", v === "web" ? "web" : "teamsV2")
                }
                SettingsParts.RadioRow { label: qsTr("Teams"); checked: openIn.choice === "teams"; onPicked: openIn.pick("teams") }
                SettingsParts.RadioRow { visible: !!openIn.app; label: qsTr("Desktop app"); checked: openIn.choice === "desktop" && !!openIn.app; onPicked: openIn.pick("desktop") }
                SettingsParts.RadioRow { label: qsTr("Browser"); checked: openIn.choice === "web" || (openIn.choice === "desktop" && !openIn.app); onPicked: openIn.pick("web") }
            }
            // Teams' "Links open preference": web links open in the default
            // browser or Microsoft Edge (when installed; Teams' default).
            SettingsParts.Card {
                id: linksPref
                visible: root.page === "files"
                icon: "link-20"; title: qsTr("Links open preference")
                readonly property var browsers: root.page === "files" ? JSON.parse(backend.webBrowsers()) : []
                readonly property string choice: root.local("linkBrowser", browsers.some(b => b.key === "edge") ? "edge" : "default")
                SettingsParts.SubHeading { text: qsTr("Always open web links in:") }
                SettingsParts.Gap { size: 10.6 }
                OutlineDropdown {
                    width: 293.3; height: 30
                    options: linksPref.browsers.map(b => ({ label: b.label }))
                    current: Math.max(0, linksPref.browsers.findIndex(b => b.key === linksPref.choice))
                    accessibleName: qsTr("Always open web links in:")
                    onPicked: i => backend.setSetting("linkBrowser", linksPref.browsers[i].key)
                }
                
            }
            SettingsParts.Card {
                visible: root.page === "files"
                icon: "image-20"; title: qsTr("File previews")
                subtitle: qsTr("Show preview cards for files shared in chats, channels, and groups, including files you share.")
                trailing: Component { SettingsParts.Toggle { on: root.prop("userPersonalSettings", ["filesSettings", "enableThumbnailPreview"], true) !== false; accessibleName: qsTr("File previews"); onToggled: v => root.setProp("userPersonalSettings", "filesSettings.enableThumbnailPreview", v) } }
            }

            // ---- About (Teams' About Teams, measured on winpc 2026-11-14) ----
            // Four cards, 20.7 padding, the 20 px glyph at 18.7 centred on
            // the text: Version (the app's mark), Legal information, Privacy
            // and cookies, Third party notice. OST's own documents stand in
            // for Microsoft's; Teams' "Web" notices have no OST counterpart.
            // The update line checks OST's GitHub releases.
            AboutCard {
                title: qsTr("Version")
                Text {
                    width: parent.width; height: 20.7; verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: qsTr("You have OST version <0>%1</0>.").arg(Qt.application.version).replace("<0>", "<b>").replace("</0>", "</b>")
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                // Teams' update line (settings-app `vd`), from OST's release
                // channel (api::updates): checking, up to date with the day
                // of the last check, an update, or the check's error.
                Item {
                    width: parent.width; height: 18.7
                    readonly property var u: backend.updateJson ? JSON.parse(backend.updateJson) : ({ state: "checking" })
                    Row {
                        visible: parent.u.state === "checking"
                        spacing: 8; anchors.verticalCenter: parent.verticalCenter
                        BusyIndicator { width: 16; height: 16; running: parent.visible }
                        Text { text: qsTr("Checking for updates"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    }
                    Text {
                        visible: parent.u.state !== "checking"
                        width: parent.width; height: 18.7; verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: parent.u.state === "error" ? qsTr("Issue occurred while checking for updates.")
                            : parent.u.state === "available" ? qsTr("An update is available.")
                            : qsTr("You've got the latest version. %1").arg(parent.u.checkedAt ? qsTr("It was last checked on %1.").arg(Qt.formatDate(new Date(parent.u.checkedAt), Qt.locale(), Locale.ShortFormat)) : "").trim()
                        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                }
            }
            // Teams' Early access card (Teams 26304, measured on winpc
            // 2026-11-20, 121.3 tall: the title row, then "Public preview",
            // a checkbox): offered where the update policy allows public
            // preview (teamsUpdateManagementPolicy.allowPublicPreview).
            // Teams' host starts its preview build on the next launch; OST
            // follows its pre-releases (the update check above).
            SettingsParts.Card {
                readonly property var u: backend.updateJson ? JSON.parse(backend.updateJson) : ({})
                visible: root.page === "about" && !root.subPage && !!u.previewAllowed
                icon: "rocket-20"; title: qsTr("Early access")
                SettingsParts.CheckRow {
                    rowHeight: 32
                    label: qsTr("Public preview")
                    checked: root.local("publicPreview", "false") === "true"
                    onToggled: on => { backend.setSetting("publicPreview", on ? "true" : "false"); checked = on; backend.checkForUpdates() }
                }
            }
            AboutCard {
                icon: "info-20"; title: qsTr("Legal information")
                AboutLink { label: qsTr("OST Legal Information"); url: "https://github.com/RandyNorthrup/ost/blob/main/LICENSE" }
            }
            AboutCard {
                icon: "cookies-20"; title: qsTr("Privacy and cookies")
                AboutLink { label: qsTr("OST Privacy Statement"); url: "https://github.com/RandyNorthrup/ost/blob/main/PRIVACY.md" }
            }
            AboutCard {
                icon: "document-text-20"; title: qsTr("Third party notice")
                AboutLink { label: qsTr("Desktop"); external: false; onActivated: { const u = backend.thirdPartyNoticesUrl(); if (u) Qt.openUrlExternally(u) } }
            }

            // A failed save, as Teams' Settings says it.
            Text {
                visible: !!backend.settingsError
                text: qsTr("Couldn't save your setting. Try again.")
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
    /// --headset-take-at: Devices' "Transfer controls to this app" as its
    /// tap does it, when it's enabled; returns whether it was.
    function transferControlsForTest() {
        hidRow.refresh()
        if (!transferBtn.usable) return false
        backend.headsetTakeControl(); hidRow.refresh()
        return true
    }
    function transferButtonUsableForTest() { hidRow.refresh(); return transferBtn.usable }
    // --work-location-test: the work location card's state and geometry,
    // its dialog, and the stationary location list.
    function workLocationForTest(what) {
        if (what === "dialog") { autoLocationDialog.open(); return "" }
        if (what === "closeDialog") { autoLocationDialog.close(); return "" }
        if (what === "list") { buildingList.open(); return "" }
        if (what === "on" || what === "off") { workLocationCard.setAuto(what === "on"); return "" }
        const c = workLocationCard
        const at = it => { const p = it.mapToItem(c, 0, 0); return [Math.round(p.x * 10) / 10, Math.round(p.y * 10) / 10, Math.round(it.width * 10) / 10, Math.round(it.height * 10) / 10] }
        const kids = []
        const walk = it => { for (let i = 0; i < it.children.length; i++) { const k = it.children[i]; if (!k.visible) continue; if (k.text !== undefined && k.text) kids.push([String(k.text).replace(/<[^>]+>/g, "").slice(0, 40)].concat(at(k))); else if (k.label !== undefined && k.label) kids.push([k.label].concat(at(k))); walk(k) } }
        walk(c)
        return JSON.stringify({ policy: c.policy, detection: c.detection, stationary: c.stationary, autoOn: c.autoOn, outlookLink: c.outlookLink, card: [c.width, c.height], trailingY: c.trailingY, items: kids, buildings: stationaryPage.buildings, chosen: stationaryPage.chosen })
    }
    /// Teams' "Green screen settings" (the effects pane's link): Devices,
    /// scrolled to Green Screen.
    function showGreenScreen() {
        page = "devices"; subPage = ""
        Qt.callLater(() => { content.contentY = Math.max(0, greenScreenRow.mapToItem(content.contentItem, 0, 0).y - 40) })
    }
    /// Teams' openSettingPage({settingCategory, settingId}): the page,
    /// scrolled to the setting, its first control focused (Customize app
    /// bar: Appearance, "app-bar-settings", Show app names).
    function showSetting(category, settingId) {
        page = category; subPage = ""
        Qt.callLater(() => {
            if (settingId !== "app-bar-settings") return
            content.contentY = Math.max(0, Math.min(pageCol.y + appBarCard.y - 12, content.contentHeight - content.height))
            appBarNamesRow.focusSwitch()
        })
    }
    function oofForTest() { return oofPage }
    function scrollForTest() { content.contentY = Math.max(0, content.contentHeight - content.height) }
    function scrollByForTest(dy) { content.contentY = Math.max(0, Math.min(content.contentHeight - content.height, content.contentY + dy)) }
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
    /// --vm-transfer-test (TASK-0180): the voicemail answer rule and its
    /// transfer target: "state", "rule" <rule>, "type" <text>, "pick"
    /// <mri> <oid>, "remove", "raw" <settings JSON> (a whole voicemail
    /// settings save, to put settings back).
    function vmTransferForTest(what, a, b) {
        if (what === "rule") calls.pickRule(a)
        else if (what === "type") transferPicker.typeForTest(a)
        else if (what === "pick") calls.pickTarget(a, b)
        else if (what === "remove") transferPicker.removed()
        else if (what === "raw") setMt("voicemail", JSON.parse(a))
        const at = it => { const p = it.mapToItem(null, 0, 0); return [Math.round(p.x * 10) / 10, Math.round(p.y * 10) / 10, Math.round(it.width * 10) / 10, Math.round(it.height * 10) / 10] }
        return JSON.stringify({ rule: calls.rule, pending: calls.pendingRule, saved: calls.vm, targetMri: calls.targetMri, cleared: calls.targetCleared,
            picker: transferPicker.visible ? at(transferPicker) : null, rows: transferPicker.visible ? transferPicker.rowsForTest() : [] })
    }
    // Settings ▸ Devices' camera controls and spatial audio, and
    // Accessibility's TTY card (TASK-0158, 0157, 0151 harnesses).
    function scrollToCardForTest(card) { const c = card === "video" ? videoCard : card === "tty" ? ttyCard : devices; content.contentY = Math.max(0, Math.min(pageCol.y + c.y - 12, content.contentHeight - content.height)) }
    function cameraForTest() { return { camera: videoCard.currentCamera, autoOn: autoCamRow.on, rowY: autoCamRow.mapToItem(videoCard, 0, 0).y, cardH: videoCard.height } }
    function toggleAutoCameraForTest(on) { autoCamRow.toggled(on) }
    function openCameraSettingsForTest() { cameraSettings.show(videoCard.currentCamera, (videoCard.cameras.find(c => c.path === videoCard.currentCamera) || {}).name || "") }
    function cameraSettingsForTest() { return cameraSettings }
    function spatialRowForTest() { return { on: spatialRow.on, usable: spatialRow.usable, capable: spatialRow.capable, y: spatialRow.mapToItem(devices, 0, 0).y, h: spatialRow.height, cardH: devices.height } }
    function toggleSpatialForTest(on) { spatialRow.toggled(on) }
    function ttyForTest() { return { changed: ttyCard.changed, h: ttyCard.height, setting: backend.setting("ttyMode") } }
    function toggleTtyForTest(on) { backend.setSetting("ttyMode", on ? "true" : "false"); ttyCard.changed = true }
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
