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
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// The meeting's options as the API lists them ({name: option}).
    property var options: ({})
    /// What's been changed and not applied yet ({name: value}).
    property var changes: ({})
    signal apply(var changes)
    onAboutToShow: changes = ({})
    function value(n) { return changes[n] !== undefined ? changes[n] : (options[n] ? options[n].currentValue : undefined) }
    function change(n, v) { const c = Object.assign({}, changes); if (options[n] && options[n].currentValue === v) delete c[n]; else c[n] = v; changes = c }
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
        TapHandler { onTapped: root.close() }
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
                            readonly property bool locked: !!opt.isDisabled
                            readonly property bool isSwitch: ["switch", "audio", "video"].indexOf(modelData.kind) >= 0
                            width: sec.width
                            height: fieldCol.implicitHeight + 21.7
                            Column {
                                id: fieldCol
                                width: parent.width
                                spacing: 0
                                Text {
                                    visible: text !== ""
                                    width: field.isSwitch ? 450.7 : parent.width
                                    text: field.modelData.label
                                    wrapMode: Text.Wrap
                                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                                    color: theme.textSecondary
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
                                // People pickers: who's chosen, then Teams' search box.
                                Column {
                                    visible: field.modelData.kind === "people"
                                    width: parent.width
                                    spacing: 4
                                    Repeater {
                                        model: field.opt.selectedPeople || []
                                        Text {
                                            required property var modelData
                                            text: modelData.displayName || modelData.name || modelData.email || ""
                                            font.family: theme.font; font.pixelSize: 14
                                            color: theme.text
                                        }
                                    }
                                    Rectangle {
                                        x: 0.67; width: 497.3; height: 50; radius: 4
                                        color: theme.surface
                                        border.color: theme.stroke; border.width: 0.67
                                        Text {
                                            x: 17.3; anchors.verticalCenter: parent.verticalCenter
                                            text: "Search for participants"
                                            font.family: theme.font; font.pixelSize: 14
                                            color: theme.disabled
                                        }
                                        Accessible.role: Accessible.EditableText
                                        Accessible.name: field.modelData.label || "Search for participants"
                                    }
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
        TapHandler { enabled: root.dirty; onTapped: { root.apply(root.changes); root.changes = ({}) } }
        Accessible.role: Accessible.Button
        Accessible.name: "Apply"
    }
}
