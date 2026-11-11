import QtQuick
import QtQuick.Controls
import QtQuick.Window

// Teams' Meeting options dialog (Controls ▸ View more options; calling
// meeting options form), measured on winpc 2026-11-10 (CSS px):
// - 780.7 x 538.7, white, radius 8, padding 0 24; "Meeting options"
//   20/600 at 24, 24; Close (20.8) 24 in from the right, 28.9 down;
// - a vertical tab list at 24, 78.5 (215 wide): 28 px tabs every 32,
//   padding 4 8, the icon (20, filled when chosen) at 8 and the label at 34
//   (14, 600 when chosen), a 3 px brand bar at the chosen tab's left;
// - the sections scroll at 244, 78.5 (512.7 x 413.8), one after another:
//   the section's icon (20) and title (16/700, line 22), its fields 48.5
//   under it, sections 57 apart with a divider; a field: its label 14/600
//   #616161, the description 12/16 #616161 (450.7 wide beside a switch,
//   498.7 otherwise), then its dropdown (497.3 x 30, 8.7 under) or the
//   switch (40 x 20) on the label's row at the right; fields 21.7 apart;
// - Apply (71 x 31.3) at the bottom right, 24 in; disabled until
//   something changes. Apply saves every option (Teams' POST of all of
//   them) and the dialog stays open.
// The labels and value names are Teams' (read from the live dialog).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 780.7; height: 538.7
    anchors.centerIn: Overlay.overlay
    // Escape and Close ask first when something's changed (tryClose).
    closePolicy: Popup.NoAutoClose
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// The meeting's options as the API lists them ({name: option}).
    property var options: ({})
    /// For the people pickers: {invitees: [{mri, upn, objectId, tenantId}],
    /// people: {mri: name}, organizer: {mri, objectId, upn, tenantId},
    /// tenantId}.
    property var people: ({})
    /// Teams' dialog strings from the same reply (translations).
    readonly property var strings: people.translations || ({})
    /// What's been changed and not applied yet ({name: value}).
    property var changes: ({})
    signal apply(var changes)
    onAboutToShow: changes = ({})
    function isPeople(o) { return !!o && (o.type === "PeopleSelection" || o.type === "PresenterSelection") }
    function value(n) {
        if (changes[n] !== undefined) return changes[n]
        const o = options[n]
        return !o ? undefined : isPeople(o) ? (o.selectedPeople || []) : o.currentValue
    }
    function change(n, v) {
        const c = Object.assign({}, changes)
        const o = options[n]
        const same = isPeople(o)
            ? (o.selectedPeople || []).map(p => p.mri).join() === v.map(p => p.mri).join()
            : !!o && o.currentValue === v
        if (same) delete c[n]; else c[n] = v
        changes = c
    }
    function tryClose() { if (dirty) unsaved.open(); else close() }
    // Teams' pickers (PeopleSelection `Xn`, PeoplePicker `da`): the
    // meeting's invitees; co-organizers also those picked and never the
    // organizer, nor anyone from another org; specific producers also the
    // organizer; nobody already picked in the same section.
    function samePerson(a, b) {
        const eq = (x, y) => !!x && !!y && String(x).toLowerCase() === String(y).toLowerCase()
        return eq(a.objectId, b.objectId) || eq(a.mri, b.mri) || eq(a.upn, b.upn)
    }
    function candidates(n) {
        const org = people.organizer
        let list = (people.invitees || []).filter(p => p.mri && p.upn && p.objectId)
        const add = p => { if (!list.some(x => samePerson(x, p))) list.push(p) }
        if (n === "CoOrganizers") {
            value(n).forEach(add)
            if (org) list = list.filter(p => !samePerson(p, org))
            list = list.filter(p => !p.tenantId || !people.tenantId || p.tenantId === people.tenantId)
        }
        if (n === "SpecifiedProducers" && org && org.upn) add(org)
        const cat = options[n] ? options[n].category : ""
        const taken = Object.keys(options).filter(k => k !== n && isPeople(options[k]) && options[k].category === cat)
            .reduce((all, k) => all.concat(value(k).map(p => p.mri)), [])
        return list.filter(p => taken.indexOf(p.mri) < 0)
    }
    // A picker that must name someone: specific presenters or producers
    // while "Specific people" is chosen (Teams' isValid).
    function invalid(n) {
        if (n === "SpecifiedPresenters") return value("PresenterOption") === "SpecifiedPeople" && value(n).length === 0
        if (n === "SpecifiedProducers") return value("ProducerOption") === "SpecifiedPeople" && value(n).length === 0
        return false
    }
    // Teams' planning-group note over Who can present: shown once there
    // are co-organizers, or only some people present.
    readonly property bool planningNote: (value("CoOrganizers") || []).length > 0
        || ["SpecifiedPeople", "OrganizerOnly"].indexOf(value("PresenterOption")) >= 0
    // Apply checks the pickers first, as Teams does: an empty required
    // one is shown instead of saving.
    function tryApply() {
        for (let i = 0; i < sections.length; i++) {
            if (sections[i].fields.some(f => f.kind === "people" && shown(f) && invalid(f.name))) { scrollTo(i); return }
        }
        const out = {}
        Object.keys(changes).forEach(k => {
            out[k] = isPeople(options[k]) ? changes[k].map(p => ({ mri: p.mri, upn: p.upn, objectId: p.objectId, tenantId: p.tenantId })) : changes[k]
        })
        apply(out)
        changes = ({})
    }
    // Escape closes an open picker list first, then the dialog.
    Shortcut {
        sequence: "Escape"
        enabled: root.opened && !unsaved.opened
        onActivated: {
            const f = root.contentItem.Window.activeFocusItem
            if (f && typeof f.closeDropForEscape === "function" && f.closeDropForEscape()) return
            root.tryClose()
        }
    }
    readonly property bool dirty: Object.keys(changes).length > 0

    // Teams' value names per option.
    readonly property var labels: ({
        AutoAdmittedUsers: { Everyone: "Everyone", EveryoneInSameAndFederatedCompany: "People in my org, trusted orgs, and guests", EveryoneInCompany: "People in my org and guests", EveryoneInCompanyExcludingGuests: "People in my org", InvitedUsers: "People who were invited", OrganizerOnly: "Only organizers and co-organizers" },
        UsersCanAdmitFromLobby: { OrganizersAndPresentersOnly: "Organizers, co-organizers, and presenters", OrganizerAndCoOrganizersOnly: "Organizers and co-organizers" },
        AllowedUsersForMeetingDetails: { UsersAllowedToByPassTheLobby: "Users allowed to bypass the lobby", Everyone: "Everyone" },
        PresenterOption: { Everyone: "Everyone", EveryoneInCompany: "People in my org and guests", SpecifiedPeople: "Specific people", OrganizerOnly: "Only organizers and co-organizers" },
        ProducerOption: { OrganizerAndCoOrganizersOnly: "Organizer and co-organizers", OrganizersAndPresentersOnly: "Organizer, co-organizers, and presenters", SpecifiedPeople: "Specific people" },
        AllowMeetingChat: { Enabled: "On", Disabled: "Off", InMeeting: "In-meeting only" },
        WhoCanStartAnnotations: { ActiveSharer: "Active sharer", Everyone: "Everyone" },
        AutoRecordAndTranscribeMode: { AutoRecordingAndTranscription: "Record and transcribe", AutoTranscriptionOnly: "Transcribe only", Off: "Off" },
        CopilotMode: { EnabledWithTranscript: "During and after the meeting", Enabled: "Only during the meeting", Disabled: "Off" }
    })
    // The sections and their fields, in Teams' order. kind: "list",
    // "switch", "people", "audio"/"video" (AttendeeRestrictions' bits).
    readonly property var sections: [
        { key: "MEETING_ACCESS", title: "Meeting access", icon: "mo-access", fields: [
            { name: "AutoAdmittedUsers", kind: "list", label: "Who can bypass the lobby?", desc: "Even if Everyone is selected, your org policy may require certain participants wait in the lobby until a member of your org or a trusted org joins. This could include people joining without an account, people from untrusted orgs, and people dialing in." },
            { name: "AllowPstnUsersToBypassLobby", kind: "switch", label: "People dialing in can bypass the lobby" },
            { name: "UsersCanAdmitFromLobby", kind: "list", label: "Who can admit from the lobby" },
            { name: "AllowedUsersForMeetingDetails", kind: "list", label: "Show meeting info on join screen", desc: "Display details about the meeting like title and start time, number of others joined, and presence of the organizer." },
            { name: "EntryExitAnnouncementsEnabled", kind: "switch", label: "Announce when people dialing in join or leave" },
            { name: "AllowAnonymousUsersToJoinMeeting", kind: "switch", label: "Require unverified participants to verify their info before joining", desc: "When this is on, unverified participants will need to sign in or verify their emails with a code before joining the meeting. Your license and admin policy also determine how they’ll join." }] },
        { key: "ROLES", title: "Roles", icon: "mo-roles", fields: [
            { name: "CoOrganizers", kind: "people", label: "Choose co-organizers:", desc: "In Teams meeting, co-organizer has the same capabilities as the organizer." },
            { name: "PresenterOption", kind: "list", label: "Who can present" },
            { name: "SpecifiedPresenters", kind: "people", label: "", showWhen: ["PresenterOption", "SpecifiedPeople"] },
            { name: "Interpretation", kind: "switch", label: "Enable language interpretation", desc: "Add interpreters who can interpret one language into another in real-time. To assign interpreters, send the meeting invite then refresh this page and choose them." }] },
        { key: "PRODUCTION_TOOLS", title: "Production tools", icon: "mo-production", fields: [
            { name: "ProducerOption", kind: "list", label: "Who has control of production tools", desc: "To give people in the meeting control over what is shown on screen for attendees, add them as co-organizers or presenters." },
            { name: "SpecifiedProducers", kind: "people", label: "", showWhen: ["ProducerOption", "SpecifiedPeople"] },
            { name: "StagingRoomEnabled", kind: "switch", label: "Enable Green room", desc: "Lets organizers and presenters check their audio, video, and content sharing before attendees are admitted. To use this feature, make someone a presenter and turn it on before the meeting starts." }] },
        { key: "PARTICIPATION", title: "Participation", icon: "mo-participation", fields: [
            { name: "AttendeeRestrictions", kind: "audio", label: "Allow mic for attendees", desc: "Turn this off to prevent attendees from unmuting. You can allow them to unmute individually as needed." },
            { name: "AttendeeRestrictions", kind: "video", label: "Allow camera for attendees", desc: "Turn this off to prevent attendees from sharing video. You can allow them to share video individually as needed." },
            { name: "AllowMeetingChat", kind: "list", label: "Meeting chat" },
            { name: "YammerQNAEnabled", kind: "switch", label: "Q&A", desc: "Organizers can customize Q&A to allow anonymous posts, review questions before they are published, and more." },
            { name: "AllowTeamsMeetingReactions", kind: "switch", label: "Allow reactions" },
            { name: "AttendanceReportEnabled", kind: "switch", label: "Allow attendance report" },
            { name: "WhoCanStartAnnotations", kind: "list", label: "Who can start annotations?" }] },
        { key: "RECORDING_AND_TRANSCRIPTION", title: "Recording & transcription", icon: "mo-recording", fields: [
            { name: "AutoRecordAndTranscribeMode", kind: "list", label: "Record and transcribe automatically", desc: "Recording and transcription will start automatically when the meeting begins. Your license and admin policy also determine how they turn on." }] },
        { key: "COPILOT", title: "Copilot and other AI", icon: "mo-copilot", fields: [
            { name: "CopilotMode", kind: "list", label: "Allow Copilot" },
            { name: "IsRecapEnabled", kind: "switch", label: "Start Intelligent Recap when Copilot is turned on", desc: "Turn this off if you don’t want a recap with AI-generated content." }] },
        { key: "ACCESSIBILITY", title: "Accessibility", icon: "mo-accessibility", fields: [
            { name: "CARTExternalFeed", kind: "switch", label: "Provide CART Captions" }] }
    ]
    // AttendeeRestrictions as two switches (Teams' invertToggleFlags "011":
    // on while that bit isn't set).
    function bitOn(kind) {
        const v = String(value("AttendeeRestrictions") || "UnRestricted")
        return v.indexOf(kind === "audio" ? "DisableAudio" : "DisableVideo") < 0
    }
    function setBit(kind, on) {
        const parts = String(value("AttendeeRestrictions") || "UnRestricted").split(",").map(s => s.trim()).filter(s => s && s !== "UnRestricted")
        const bit = kind === "audio" ? "DisableAudio" : "DisableVideo"
        const next = parts.filter(p => p !== bit).concat(on ? [] : [bit])
        change("AttendeeRestrictions", next.length ? ["DisableAudio", "DisableVideo"].filter(b => next.indexOf(b) >= 0).join(",") : "UnRestricted")
    }
    function shown(f) {
        if (!options[f.name]) return false
        return !f.showWhen || value(f.showWhen[0]) === f.showWhen[1]
    }
    property int currentSection: 0
    function scrollTo(i) {
        currentSection = i
        const item = sectionRepeater.itemAt(i)
        // The section's title at the top, 8.5 down, as Teams scrolls it.
        if (item) flick.contentY = Math.min(item.y + (i > 0 ? 0.67 + 56.3 - 8.5 : 0), Math.max(0, flick.contentHeight - flick.height))
    }

    Text {
        x: 24; y: 24; height: 28; verticalAlignment: Text.AlignVCenter
        text: "Meeting options"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Rectangle {
        x: root.width - 24 - 20.8; y: 28.9; width: 20.8; height: 20.8; radius: 4
        color: closeH.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeH; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.tryClose() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }

    // The tab list.
    Column {
        x: 24; y: 78.5; width: 215
        spacing: 4
        Repeater {
            model: root.sections
            Rectangle {
                id: tab
                required property var modelData
                required property int index
                readonly property bool chosen: root.currentSection === index
                x: 2; width: tabRow.implicitWidth + 16; height: 28; radius: 4
                color: tabH.hovered && !chosen ? theme.menuHover : "transparent"
                Rectangle { visible: tab.chosen; x: 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 16; radius: 1.5; color: theme.brand }
                Row {
                    id: tabRow
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    FluentIcon { name: tab.modelData.icon + (tab.chosen ? "-filled" : ""); size: 20; color: tab.chosen ? theme.brand : theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.title
                        font.family: theme.font; font.pixelSize: 14; font.weight: tab.chosen ? Font.DemiBold : Font.Normal
                        color: tab.chosen ? theme.text : theme.textStrong
                    }
                }
                HoverHandler { id: tabH; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.scrollTo(tab.index) }
                Accessible.role: Accessible.PageTab
                Accessible.name: tab.modelData.title
                Accessible.selected: tab.chosen
            }
        }
    }

    // The sections.
    Flickable {
        id: flick
        x: 244; y: 78.5; width: 512.7; height: 413.8
        contentHeight: sectionsCol.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // The tab follows the section at the top as the list scrolls.
        onContentYChanged: if (moving || dragging) {
            for (let i = root.sections.length - 1; i >= 0; i--) {
                const it = sectionRepeater.itemAt(i)
                if (it && it.y <= contentY + 8) { root.currentSection = i; break }
            }
        }
        Column {
            id: sectionsCol
            width: 499.4
            spacing: 0
            Repeater {
                id: sectionRepeater
                model: root.sections
                Column {
                    id: sec
                    required property var modelData
                    required property int index
                    readonly property var visibleFields: modelData.fields.filter(f => root.shown(f))
                    visible: visibleFields.length > 0
                    width: parent.width
                    spacing: 0
                    Rectangle { visible: sec.index > 0; width: parent.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio); color: theme.divider }
                    Item { width: 1; height: sec.index > 0 ? 56.3 : 8.5 }
                    Row {
                        spacing: 5
                        FluentIcon { name: sec.modelData.icon; size: 20; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: sec.modelData.title
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                            lineHeight: 22; lineHeightMode: Text.FixedHeight
                            color: theme.text
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }
                    }
                    Item { width: 1; height: 26.5 }
                    Repeater {
                        model: sec.visibleFields
                        Item {
                            id: field
                            required property var modelData
                            required property int index
                            readonly property var opt: root.options[modelData.name] || ({})
                            // Locked by the admin (isLocked) or unavailable (isDisabled).
                            readonly property bool locked: !!opt.isDisabled || !!opt.isLocked
                            readonly property bool isSwitch: ["switch", "audio", "video"].indexOf(modelData.kind) >= 0
                            width: sec.width
                            height: fieldCol.implicitHeight + 21.7
                            Column {
                                id: fieldCol
                                width: parent.width
                                spacing: 0
                                // Teams' planning-group note over Who can present
                                // (a #F5F5F5 alert, radius 5, padding 5: the
                                // filled info glyph (16), the text 12/16 20 after
                                // it with Learn more; 12 above the label).
                                Item { visible: note.visible; width: 1; height: 2 }
                                Rectangle {
                                    id: note
                                    visible: field.modelData.name === "PresenterOption" && root.planningNote
                                    width: 498.7; height: noteText.implicitHeight + 10; radius: 5
                                    color: theme.pick("#F5F5F5", "#2E2E2E")
                                    FluentIcon { x: 5; y: 5.5; name: "info-16"; size: 16; color: theme.text }
                                    Text {
                                        id: noteText
                                        x: 25; y: 5; width: 468.7
                                        wrapMode: Text.Wrap
                                        textFormat: Text.StyledText
                                        text: "You'll be able to chat separately with the co-organizers and presenters in the planning group. Once saved access it from chat list or Calendar&nbsp;<a href=\"https://support.microsoft.com/teams/meetings/chat-with-event-group-microsoft-teams\">Learn more</a>"
                                        linkColor: theme.brandForeground1
                                        font.family: theme.font; font.pixelSize: 12
                                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                                        color: theme.text
                                        onLinkActivated: url => Qt.openUrlExternally(url)
                                        HoverHandler { cursorShape: noteText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                    }
                                    Accessible.role: Accessible.AlertMessage
                                    Accessible.name: "You'll be able to chat separately with the co-organizers and presenters in the planning group. Once saved access it from chat list or Calendar"
                                }
                                Item { visible: note.visible; width: 1; height: 12 }
                                // The label, then Teams' lock (locked by the admin)
                                // and info (the chosen value's _Info string)
                                // buttons: 24 x 23.3, transparent, the 16 px glyph
                                // filled in brand on hover, Fluent's tooltip above.
                                Row {
                                    visible: field.modelData.label !== ""
                                    readonly property string valueInfo: field.modelData.kind === "list"
                                        ? (root.strings["meetingsOptions_" + field.modelData.name + "_" + root.value(field.modelData.name) + "_Info"] || "") : ""
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, (field.isSwitch ? 450.7 : fieldCol.width) - (lockBtn.visible ? 24 : 0) - (infoBtn.visible ? 24 : 0))
                                        text: field.modelData.label
                                        wrapMode: Text.Wrap
                                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                                        color: theme.textSecondary
                                    }
                                    LabelButton { id: lockBtn; visible: !!field.opt.isLocked; glyph: "lock-closed-16"; tip: "This option is locked by admin."; label: field.modelData.label }
                                    LabelButton { id: infoBtn; visible: parent.valueInfo !== ""; glyph: "info-16"; regular: "info-16-regular"; tip: parent.valueInfo; label: field.modelData.label }
                                }
                                Text {
                                    visible: !!field.modelData.desc
                                    width: field.isSwitch ? 450.7 : 498.7
                                    text: field.modelData.desc || ""
                                    wrapMode: Text.Wrap
                                    font.family: theme.font; font.pixelSize: 12
                                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                                    color: theme.textSecondary
                                }
                                Item { visible: !field.isSwitch; width: 1; height: 8.7 }
                                Dropdown {
                                    visible: field.modelData.kind === "list"
                                    x: 0.67; width: 497.3
                                    enabled: !field.locked
                                    opacity: field.locked ? 0.5 : 1
                                    readonly property var names: root.labels[field.modelData.name] || ({})
                                    label: names[root.value(field.modelData.name)] || String(root.value(field.modelData.name) || "")
                                    options: (field.opt.values || []).map(v => [v, names[v] || String(v)])
                                    accessibleName: field.modelData.label
                                    onPicked: code => root.change(field.modelData.name, code)
                                }
                                // People pickers (Teams' TagPicker).
                                MeetingPeoplePicker {
                                    readonly property string fieldName: field.modelData.name
                                    visible: field.modelData.kind === "people"
                                    picked: visible ? root.value(field.modelData.name) : []
                                    candidates: visible ? root.candidates(field.modelData.name) : []
                                    names: root.people.people || ({})
                                    max: field.opt.maxPeopleSelectionAllowed || 0
                                    // Teams' picker is off while there's nobody to offer.
                                    disabled: field.locked || (candidates.length === 0 && picked.length === 0)
                                    hasError: root.invalid(field.modelData.name)
                                    placeholder: "Search for participants"
                                    onChanged: list => root.change(field.modelData.name, list)
                                }
                            }
                            // Fluent's switch, 40 x 20, on the label's row.
                            Rectangle {
                                id: sw
                                visible: field.isSwitch
                                readonly property bool on: field.modelData.kind === "audio" || field.modelData.kind === "video"
                                    ? root.bitOn(field.modelData.kind) : root.value(field.modelData.name) === true
                                readonly property bool usable: !field.locked
                                x: parent.width - 40 - 10; y: 0
                                width: 40; height: 20; radius: 10
                                color: !on ? "transparent" : !usable ? theme.bgDisabled : swH.hovered ? theme.brandHover : theme.brandFill
                                border.width: on ? 0 : 1
                                border.color: !usable ? theme.pick("#E0E0E0", "#424242") : swH.hovered ? theme.text : theme.textSecondary
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: sw.on ? parent.width - width - 3 : 3
                                    color: sw.on ? (sw.usable ? "white" : theme.disabled) : (!sw.usable ? theme.disabled : swH.hovered ? theme.text : theme.textSecondary)
                                }
                                HoverHandler { id: swH; cursorShape: sw.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler {
                                    enabled: sw.usable
                                    onTapped: {
                                        if (field.modelData.kind === "audio" || field.modelData.kind === "video") root.setBit(field.modelData.kind, !sw.on)
                                        else root.change(field.modelData.name, !sw.on)
                                    }
                                }
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: field.modelData.label
                                Accessible.checked: on
                            }
                        }
                    }
                }
            }
        }
    }

    // Apply.
    Rectangle {
        x: root.width - 24 - width; y: 497.4
        width: 71; height: 31.3; radius: 4
        color: !root.dirty ? theme.bgDisabled : applyH.hovered ? theme.brandHover : theme.brandFill
        Text {
            anchors.centerIn: parent
            text: "Apply"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: root.dirty ? theme.textOnBrand : theme.disabled
        }
        HoverHandler { id: applyH; enabled: root.dirty; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.dirty; onTapped: root.tryApply() }
        Accessible.role: Accessible.Button
        Accessible.name: "Apply"
    }

    // Teams' "Unsaved changes" (Close or Escape with changes not
    // applied), measured on winpc 2026-11-11: 600 wide, radius 8, padding
    // 24, the dialog shadow; the title 20/600 (line 28), the question 14/20
    // 6 under it, the buttons 6 under that at the right, 8 apart:
    // Continue editing (primary) and Discard.
    Popup {
        id: unsaved
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: "transparent" }
        Column {
            width: parent.width
            spacing: 6
            Text {
                text: "Unsaved changes"
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Text {
                text: "Do you want to discard edits or continue editing?"
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                topPadding: 2; bottomPadding: 2
                color: theme.text
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Rectangle {
                    width: contLabel.implicitWidth + 24; height: 31.3; radius: 4
                    color: contH.hovered ? theme.brandHover : theme.brandFill
                    Text { id: contLabel; anchors.centerIn: parent; text: "Continue editing"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                    HoverHandler { id: contH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: unsaved.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Continue editing"
                }
                Rectangle {
                    width: Math.max(96, discLabel.implicitWidth + 24); height: 31.3; radius: 4
                    color: discH.hovered ? theme.menuHover : theme.surface
                    border.color: theme.stroke; border.width: 0.67
                    Text { id: discLabel; anchors.centerIn: parent; text: "Discard"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    HoverHandler { id: discH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { unsaved.close(); root.changes = ({}); root.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Discard"
                }
            }
        }
    }
    function pickerForTest(n) {
        for (let i = 0; i < sectionRepeater.count; i++) {
            const sec = sectionRepeater.itemAt(i)
            const found = sec ? findPicker(sec, n) : null
            if (found) return found
        }
        return null
    }
    function findPicker(item, n) {
        for (let i = 0; i < item.children.length; i++) {
            const c = item.children[i]
            if (c.candidates !== undefined && c.visible && c.fieldName === n) return c
            const deeper = findPicker(c, n)
            if (deeper) return deeper
        }
        return null
    }

    component LabelButton: Rectangle {
        id: lb
        property string glyph
        property string regular: glyph
        property string tip
        property string label
        width: 24; height: 23.3; radius: 4
        color: "transparent"
        FluentIcon {
            anchors.centerIn: parent
            name: lbH.hovered ? (lb.glyph === lb.regular ? lb.glyph + "-filled" : lb.glyph) : lb.regular
            size: 16
            color: lbH.hovered ? theme.brand : theme.textStrong
        }
        HoverHandler { id: lbH }
        ArrowTip { visible: lbH.hovered; tipText: lb.tip }
        Accessible.role: Accessible.Button
        Accessible.name: lb.label + " " + lb.tip
    }
}
