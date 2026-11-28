import QtQuick
import QtQuick.Controls.Basic

// The Calls app's Intelligent call delegation pane (Teams 26304's
// calls-main-app CallsTabPAOnboardingContainer and its summary pane), the
// right-hand pane the History banner toggles:
// - Not set up: Teams' onboarding. The splash (the call delegation glyph
//   48 px at 32,69 under a 52 px header, "Set up intelligent call
//   delegation" 24/32, four feature rows 65 apart from 250 with a 36 px
//   circle at 32 and the text at 80, then Get started and Enable now),
//   then Voice (its language, saved when picked), Exemptions (VIPs: your
//   priority contacts, saved on Continue) and Review settings (how
//   external and internal calls are screened, follow-ups, the answered
//   call banner; "Enable and make a test call" / "Enable and complete
//   setup"). Enable now turns it on at once and shows what's configured.
//   Finishing marks Teams' paOnboardingCompleted (userPersonalSettings'
//   callingUserSettings).
// - Set up: its summary (on or off, the same choices, VIPs, More
//   settings in Settings ▸ Calls ▸ Intelligent call delegation).
Item {
    id: root
    /// Teams' settings (SettingsView's synced: {props, mt}).
    property var props: ({})
    property var mt: ({})
    signal closed()
    signal openSettings(string id)

    readonly property var pol: mt.attendantPolicy || {}
    readonly property var s: mt.attendant || {}
    readonly property bool userChoice: pol.personalAttendant === "EnabledUserOverride"
    readonly property bool on: pol.personalAttendant === "Enabled" || (userChoice && s.isEnabled === true)
    readonly property bool completed: ((((props.userPersonalSettings || {}).callingUserSettings) || {}).paOnboardingCompleted) === true
    readonly property bool extChoice: pol.inboundFederatedCalls === "EnabledUserOverride" && pol.inboundPSTNCalls === "EnabledUserOverride"
    readonly property bool intChoice: pol.inboundInternalCalls === "EnabledUserOverride"
    readonly property bool followUps: pol.calendarBookings === "EnabledUserOverride"
    readonly property string external: (s.enableInboundFederatedCalls || s.enableInboundPSTNCalls) ? "automatic" : "manual"
    readonly property string internal: s.enableInboundInternalCalls ? "automatic" : "manual"
    readonly property bool banner: s.enableScreeningNotification !== false

    /// splash | voice | exceptions | review | confirm (after Enable now) |
    /// congrats (after finishing) | summary.
    property string step: completed || on ? "summary" : "splash"
    property int reached: 0
    readonly property var steps: ["voice", "exceptions", "review"]
    function go(st) { step = st; const i = steps.indexOf(st); if (i > reached) reached = i }
    function reset() { step = completed || on ? "summary" : "splash"; reached = 0; added = []; removed = [] }

    function set(patch) { backend.changeSetting("mt", "attendant", JSON.stringify(patch)) }
    function markCompleted() { backend.changeSetting("prop", "userPersonalSettings", JSON.stringify({ callingUserSettings: { paOnboardingCompleted: true } })) }
    function screening(kind, v) {
        if (kind === "external") set({ enableInboundFederatedCalls: v === "automatic", enableInboundPSTNCalls: v === "automatic", enableManualExternalCalls: v !== "automatic" })
        else set({ enableInboundInternalCalls: v === "automatic", enableManualInternalCalls: v !== "automatic" })
    }
    function enableNow() { set({ isEnabled: true }); markCompleted(); step = "confirm" }
    function enableAndComplete() { set({ isEnabled: true }); markCompleted(); step = "congrats" }
    function enableAndTest() { set({ isEnabled: true }); markCompleted(); backend.callPersonalAttendant(); step = "congrats" }

    // Teams' languages (ECS personalAttendantSupportedLanguages).
    readonly property var languageNames: ({
        "ar-SA": qsTr("Arabic (Saudi Arabia)"), "zh-CN": qsTr("Chinese (China)"), "zh-TW": qsTr("Chinese (Taiwan)"), "cs-CZ": qsTr("Czech (Czechia)"),
        "da-DK": qsTr("Danish (Denmark)"), "nl-NL": qsTr("Dutch (Netherlands)"), "en-AU": qsTr("English (Australia)"), "en-GB": qsTr("English (United Kingdom)"),
        "en-US": qsTr("English (United States)"), "fi-FI": qsTr("Finnish (Finland)"), "fr-CA": qsTr("French (Canada)"), "fr-FR": qsTr("French (France)"),
        "de-DE": qsTr("German (Germany)"), "el-GR": qsTr("Greek (Greece)"), "hi-IN": qsTr("Hindi (India)"), "id-ID": qsTr("Indonesian (Indonesia)"),
        "it-IT": qsTr("Italian (Italy)"), "ja-JP": qsTr("Japanese (Japan)"), "ko-KR": qsTr("Korean (South Korea)"), "nb-NO": qsTr("Norwegian, Bokmål (Norway)"),
        "pl-PL": qsTr("Polish (Poland)"), "pt-BR": qsTr("Portuguese (Brazil)"), "ru-RU": qsTr("Russian (Russia)"), "es-ES": qsTr("Spanish (Spain)"),
        "es-US": qsTr("Spanish (United States)"), "sv-SE": qsTr("Swedish (Sweden)"), "th-TH": qsTr("Thai (Thailand)"), "tr-TR": qsTr("Turkish (Türkiye)"),
        "en": qsTr("English (United States)"), "fr": qsTr("French (France)")
    })
    readonly property var languages: {
        let codes = []
        try { codes = JSON.parse(backend.ecsSetting("calling", "personalAttendantSupportedLanguages") || "[]") } catch (e) {}
        if (!Array.isArray(codes) || !codes.length) codes = ["ar-SA", "zh-CN", "zh-TW", "cs-CZ", "da-DK", "nl-NL", "en-AU", "en-GB", "en-US", "fi-FI", "fr-CA", "fr-FR", "de-DE", "el-GR", "hi-IN", "id-ID", "it-IT", "ja-JP", "ko-KR", "nb-NO", "pl-PL", "pt-BR", "ru-RU", "es-ES", "es-US", "sv-SE", "th-TH", "tr-TR"]
        return codes.filter(c => !!languageNames[c]).map(c => ({ code: c, name: languageNames[c] }))
    }
    readonly property string languageCode: s.defaultLanguage === "en" ? "en-US" : s.defaultLanguage === "fr" ? "fr-FR" : (s.defaultLanguage || "en-US")

    // VIPs: your priority contacts (Teams' priorityContacts), with the
    // exemption step's additions and removals kept until Continue.
    property var vips: []
    property var added: []
    property var removed: []
    readonly property var names: backend.peopleNamesJson ? JSON.parse(backend.peopleNamesJson) : ({})
    readonly property var shownVips: vips.filter(m => removed.indexOf(m) < 0).concat(added.filter(m => vips.indexOf(m) < 0 && removed.indexOf(m) < 0))
    function loadVips() { backend.channelAction("people-list", "", "", JSON.stringify({ list: "priority" })) }
    function saveVips() {
        added.filter(m => vips.indexOf(m) < 0).forEach(m => backend.channelAction("people-list-add", "", "", JSON.stringify({ list: "priority", mri: m })))
        removed.filter(m => vips.indexOf(m) >= 0).forEach(m => backend.channelAction("people-list-remove", "", "", JSON.stringify({ list: "priority", mri: m })))
        added = []; removed = []
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "people-list" && r.ok && r.data && r.data.list === "priority") {
                root.vips = r.data.mris || []
                const want = root.vips.filter(m => !root.names[m])
                if (want.length) backend.resolveNames(JSON.stringify(want))
            } else if ((r.op === "people-list-add" || r.op === "people-list-remove") && r.ok) root.loadVips()
        }
    }
    onVisibleChanged: if (visible) { reset(); loadVips() }
    Component.onCompleted: loadVips()

    function stepForTest(st) { go(st) }
    readonly property string stepNow: step

    // Teams' pane background: a lilac wash from the top right.
    Rectangle {
        anchors.fill: parent
        color: theme.surface
        Rectangle {
            visible: !theme.dark && !theme.highContrast
            y: 52; width: parent.width; height: parent.height - 52
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#FCFBFE" }
                GradientStop { position: 1; color: "#FBE6F4" }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00FFFFFF" }
                    GradientStop { position: 0.55; color: "#FFFFFFFF" }
                }
            }
        }
    }
    // Header: the title (14/600, 20 in) and Close.
    Item {
        id: head
        width: parent.width; height: 52
        Text {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Intelligent call delegation")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Rectangle {
            id: hcClose
            x: parent.width - 48; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: theme.radius
            color: clh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcClose, theme.textStrong) }
            HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    component PaButton: Rectangle {
        id: pb
        property string label
        property bool primary: false
        signal clicked()
        width: parent ? parent.width : 300; height: 32; radius: theme.radius
        color: primary ? (pbh.hovered ? theme.brandHover : theme.brandFill) : (pbh.hovered ? theme.rowHover : theme.surface)
        border.color: primary ? "transparent" : theme.stroke
        Text { anchors.centerIn: parent; text: pb.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(pb, pb.primary ? "white" : theme.text) }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }
    component Back: Rectangle {
        id: bk
        signal clicked()
        width: backRow.implicitWidth + 16; height: 32; radius: theme.radius
        color: bkh.hovered ? theme.rowHover : "transparent"
        Row { id: backRow; x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-left-20"; size: 20; color: theme.onFill(bk, theme.textStrong) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(bk, theme.text) }
        }
        HoverHandler { id: bkh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bk.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
    }
    // Teams' breadcrumb: Voice › Exemptions › Review settings; steps you've
    // reached are links.
    component Crumbs: Row {
        spacing: 4
        Repeater {
            model: [qsTr("Voice"), qsTr("Exemptions"), qsTr("Review settings")]
            Row {
                required property string modelData
                required property int index
                spacing: 4
                FluentIcon { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.textSecondary }
                Text {
                    readonly property bool current: root.steps[index] === root.step
                    readonly property bool link: !current && index <= root.reached
                    text: modelData
                    font.family: theme.font; font.pixelSize: 12; font.weight: current ? Font.DemiBold : Font.Normal
                    color: current ? theme.text : link ? theme.brand : theme.disabled
                    TapHandler { enabled: parent.link; onTapped: root.go(root.steps[index]) }
                    HoverHandler { cursorShape: parent.link ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    Accessible.role: Accessible.Link; Accessible.name: text
                }
            }
        }
    }
    component ScreenChoice: Column {
        property string label
        property string kind
        spacing: 6
        width: parent ? parent.width : 300
        Text { text: label; width: parent.width; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        OutlineDropdown {
            width: parent.width; height: 32
            readonly property var values: ["automatic", "manual"]
            options: [{ label: qsTr("Automatically answer calls") }, { label: qsTr("Let calls ring me first") }]
            current: values.indexOf(kind === "external" ? root.external : root.internal)
            accessibleName: label
            onPicked: i => root.screening(kind, values[i])
        }
    }

    Flickable {
        id: flick
        anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        contentHeight: body.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Item {
            id: body
            width: flick.width
            height: { let h = 0; for (const c of children) if (c.visible) h = Math.max(h, c.y + c.height); return h }

            // ---- Splash ----
            Column {
                visible: root.step === "splash"
                x: 20; width: parent.width - 40
                Item { width: 1; height: 17 }
                Image { x: 12; width: 48; height: 48; source: "../assets/illustrations/personal-attendant-avatar.svg"; sourceSize: Qt.size(96, 96) }
                Item { width: 1; height: 49 }
                Text {
                    x: 12; width: parent.width - 24; wrapMode: Text.Wrap
                    text: qsTr("Set up intelligent call delegation")
                    font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; lineHeight: 32; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Item { width: 1; height: 22 }
                Repeater {
                    model: [["person-question-mark-20", qsTr("Know who's calling and why before you answer")], ["flag-20", qsTr("Filter spam calls before they reach you")],
                            ["calendar-ltr-20", qsTr("Handle calls and schedule follow-ups automatically")], ["sparkle-20", qsTr("Stay informed with a summary of every call")]]
                    Rectangle {
                        required property var modelData
                        width: parent.width; height: 65
                        color: theme.dark ? "#14FFFFFF" : "#B3FFFFFF"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
                        Rectangle {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36; radius: 18
                            color: theme.pick("#E8EBFA", "#2F2F4A", "#000000")
                            FluentIcon { anchors.centerIn: parent; name: parent.parent.modelData[0]; size: 20; color: theme.brand }
                        }
                        Text {
                            x: 60; width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData[1]; wrapMode: Text.Wrap
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
                        }
                    }
                }
                Item { width: 1; height: 1 }
                PaButton { primary: true; label: qsTr("Get started"); onClicked: root.go("voice") }
                Item { width: 1; height: 8 }
                PaButton { label: qsTr("Enable now"); onClicked: root.enableNow() }
            }

            // ---- Voice ----
            Column {
                visible: root.step === "voice"
                x: 20; y: 12; width: parent.width - 40
                spacing: 12
                Back { onClicked: root.reset() }
                Crumbs {}
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("What language should I speak?"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                OutlineDropdown {
                    width: parent.width; height: 32
                    placeholder: qsTr("Select a language")
                    options: root.languages.map(l => ({ label: l.name }))
                    current: root.languages.findIndex(l => l.code === root.languageCode)
                    accessibleName: qsTr("What language should I speak?")
                    onPicked: i => { if (root.languages[i].code !== root.languageCode) root.set({ defaultLanguage: root.languages[i].code }) }
                }
                Item { width: 1; height: 8 }
                PaButton { primary: true; label: qsTr("Continue"); onClicked: root.go("exceptions") }
            }

            // ---- Exemptions (VIPs) ----
            Column {
                visible: root.step === "exceptions"
                x: 20; y: 12; width: parent.width - 40
                spacing: 12
                Back { onClicked: root.go("voice") }
                Crumbs {}
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Set up VIPs to bypass intelligent call delegation"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Any call you don't answer will be handled by intelligent call delegation."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Rectangle {
                    id: vipBox
                    width: parent.width; height: 32; radius: theme.radius
                    color: theme.input; border.color: vipField.activeFocus ? theme.brand : theme.stroke
                    TextInput {
                        id: vipField
                        x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        onTextEdited: if (text.trim().length > 1) vipDelay.restart()
                        Text { visible: !vipField.text; text: qsTr("Add people"); color: theme.textTertiary; font: vipField.font }
                        Accessible.name: qsTr("Add people")
                    }
                    Timer { id: vipDelay; interval: 300; onTriggered: backend.searchPeople(vipField.text.trim()) }
                }
                Column {
                    visible: vipField.text.trim().length > 1
                    width: parent.width
                    Repeater {
                        model: { const p = backend.peopleJson ? JSON.parse(backend.peopleJson) : []; return p.slice(0, 5) }
                        Rectangle {
                            id: hcVipHit
                            required property var modelData
                            width: parent.width; height: 40; radius: theme.radius
                            color: vhh.hovered ? theme.rowHover : "transparent"
                            Avatar { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.modelData.name; photoId: parent.modelData.id }
                            Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcVipHit, theme.text) }
                            HoverHandler { id: vhh; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    const m = Mri.work(parent.modelData.id)
                                    root.removed = root.removed.filter(x => x !== m)
                                    if (root.added.indexOf(m) < 0) root.added = root.added.concat([m])
                                    vipField.text = ""
                                }
                            }
                        }
                    }
                }
                Text { visible: root.shownVips.length > 0; text: qsTr("VIPs") + " (" + root.shownVips.length + ")"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Repeater {
                    model: root.shownVips
                    Item {
                        required property string modelData
                        width: parent.width; height: 40
                        Avatar { anchors.verticalCenter: parent.verticalCenter; size: 28; name: root.names[parent.modelData] || ""; photoId: parent.modelData }
                        Text { x: 40; width: parent.width - 80; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: root.names[parent.modelData] || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Rectangle {
                            id: hcRemove
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: rmh.hovered ? theme.rowHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 16; color: theme.onFill(hcRemove, theme.textStrong) }
                            HoverHandler { id: rmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { const m = parent.parent.modelData; root.added = root.added.filter(x => x !== m); if (root.removed.indexOf(m) < 0) root.removed = root.removed.concat([m]) } }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Remove %1 from exemptions").arg(root.names[parent.modelData] || "")
                        }
                    }
                }
                Item { width: 1; height: 8 }
                PaButton { primary: true; label: qsTr("Continue"); onClicked: { root.saveVips(); root.go("review") } }
            }

            // ---- Review settings ----
            Column {
                visible: root.step === "review"
                x: 20; y: 12; width: parent.width - 40
                spacing: 12
                Back { onClicked: root.go("exceptions") }
                Crumbs {}
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Review other settings"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("You can always change these later in Teams settings."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                ScreenChoice { visible: root.extChoice; kind: "external"; label: qsTr("Choose how external calls are handled") }
                ScreenChoice { visible: root.intChoice; kind: "internal"; label: qsTr("Choose how internal calls are handled") }
                Item {
                    visible: root.followUps
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Follow-ups"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    SettingsParts.Button { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: qsTr("Manage"); onClicked: root.openSettings("personal_attendant_booking_manage_hours") }
                }
                Item {
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; wrapMode: Text.Wrap; text: qsTr("Display banner for answered calls"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    SettingsParts.Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; stateLabel: false; on: root.banner; accessibleName: qsTr("Display banner for answered calls"); onToggled: v => root.set({ enableScreeningNotification: v }) }
                }
                Item { width: 1; height: 8 }
                PaButton { primary: true; label: qsTr("Enable and make a test call"); onClicked: root.enableAndTest() }
                PaButton { label: qsTr("Enable and complete setup"); onClicked: root.enableAndComplete() }
            }

            // ---- Done: after Enable now (what's configured) or finishing ----
            Column {
                visible: root.step === "confirm" || root.step === "congrats"
                x: 20; y: 24; width: parent.width - 40
                spacing: 12
                Image { width: 48; height: 48; source: "../assets/illustrations/personal-attendant-avatar.svg"; sourceSize: Qt.size(96, 96) }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Intelligent call delegation is ready to answer your calls."); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Text { visible: root.step === "confirm"; width: parent.width; text: qsTr("Here is what's configured for you:"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Repeater {
                    model: root.step === "confirm" ? [
                        ["local-language-20", qsTr("%1 is your default language").arg((root.languageNames[root.languageCode] || "").replace(/ \(.*\)$/, ""))],
                        ["call-20", qsTr("External and internal calls are set to be answered on your behalf.")],
                        ["star-20", qsTr("Calls from your VIPs go directly to you")],
                        ["flag-20", qsTr("Spam call filtering is enabled")]] : []
                    Row {
                        required property var modelData
                        spacing: 12
                        FluentIcon { name: parent.modelData[0]; size: 20; color: theme.brand }
                        Text { width: 260; wrapMode: Text.Wrap; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                }
                Item { width: 1; height: 8 }
                PaButton { primary: true; label: qsTr("Finish"); onClicked: root.step = "summary" }
                PaButton { visible: root.step === "confirm"; label: qsTr("Go to settings"); onClicked: root.openSettings("personal_attendant_group_section_title") }
            }

            // ---- Summary (set up) ----
            Column {
                visible: root.step === "summary"
                x: 20; y: 16; width: parent.width - 40
                spacing: 16
                Rectangle {
                    width: parent.width; height: 64; radius: 8
                    color: theme.pick("#FFFFFF", "#292929", "#000000"); border.color: theme.stroke
                    Image { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; source: "../assets/illustrations/personal-attendant-avatar.svg"; sourceSize: Qt.size(64, 64) }
                    Text { x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 120; wrapMode: Text.Wrap; text: root.on ? qsTr("Intelligent call delegation is active") : qsTr("Intelligent call delegation"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    SettingsParts.Toggle { visible: root.userChoice; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; stateLabel: false; on: root.on; accessibleName: qsTr("Toggle Call Delegation on or off"); onToggled: v => root.set({ isEnabled: v }) }
                }
                ScreenChoice { visible: root.extChoice; kind: "external"; label: qsTr("Choose how external calls are handled") }
                ScreenChoice { visible: root.intChoice; kind: "internal"; label: qsTr("Choose how internal calls are handled") }
                Item {
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 110; elide: Text.ElideRight; text: root.vips.length ? qsTr("VIPs") + " (" + root.vips.length + ")" : qsTr("VIPs"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    SettingsParts.Button { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: qsTr("Manage priority access"); onClicked: root.openSettings("privacy_manage_priority_access") }
                }
                Item {
                    width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; wrapMode: Text.Wrap; text: qsTr("Display banner for answered calls"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    SettingsParts.Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; stateLabel: false; on: root.banner; accessibleName: qsTr("Display banner for answered calls"); onToggled: v => root.set({ enableScreeningNotification: v }) }
                }
                Text {
                    text: qsTr("More settings")
                    font.family: theme.font; font.pixelSize: 14; color: theme.brand
                    TapHandler { onTapped: root.openSettings("personal_attendant_group_section_title") }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Link; Accessible.name: qsTr("Open more Call Delegation settings")
                }
            }
        }
    }
}
