import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import com.ost.desktop

// Teams' Events app, drawn natively as Teams draws it itself (it is not a
// hosted page): docs/spec/events.md, measured in Teams on the web as
// ost-test1 on 2026-11-16 in a 1212 x 752 window (app area 1144 wide from
// x 68, its header 61 tall at y 84). The data is the virtual events
// service's (api::events through backend.eventsRequest).
// - Header (#FAFAFA): the app's 32 px tile (#5B5FC7, radius 4, a 20 px
//   white ticket) 20 in and 14 down, "Events" 20/28.57 semibold #616161
//   at 60; the Discover and Manage tabs (44 tall, text 10 in, 14/20,
//   semibold #242424 when chosen with the brand line, else #424242) from
//   136; on the right Pin app, Filters (Discover only) and Create event
//   (outlined, white, #D1D1D1), 32 tall, 8 apart, 20 from the edge.
// - Discover: the sticky intro card (#F5F5F5, #D1D1D1, radius 16, 17 in,
//   32 from the top and sides), the lists or the empty state (128 px
//   picture, "No events have been scheduled yet" 16/22 bold, the hint
//   14/20 in 450, Create event 155 x 38), then "Get started with a
//   template" (16/22 semibold) and the template cards (517 x 317 at 1144:
//   two columns 16 apart, radius 24, card shadow; the picture panel
//   #FAFAFA radius 16, 163 tall, 12 in; title 16/22 semibold, text 14/20,
//   feature chips 24 tall #F5F5F5).
// - Manage: Connect apps (right), Drafts (n), Published and Past with up to
//   four event cards each (351 x 303, radius 24: the promo picture 109
//   tall, the title 16/22 semibold, the time 14/20 #616161, Organizer and
//   Online 12/16, Edit and ···), or the empty state and the templates.
// - Create event: "Create" with a back arrow, "Choose what you're
//   organizing" and Create from scratch plus the templates in three
//   columns (347 x 292, 20 apart); a choice opens the New event form.
// - The form: Save and continue (primary, top right), the welcome card,
//   and four cards (white, radius 16, 25 in): Add event details (Name,
//   Start/End date and time, Location, Description), Who's planning the
//   event?, Who can attend? (Public / Your organization / Specific people
//   and groups, Turn on registration?) and Set up experience and options
//   (capacity, Optimize for large audience, Attendee participation tiles,
//   Enable green room). Save asks "Save as a draft and continue?" and
//   makes the draft (POST events), then shows it with "Draft event
//   created".
Rectangle {
    id: root
    color: theme.pick("#FAFAFA", "#141414", "#000000")
    /// "discover" or "manage".
    property string tab: "discover"
    /// "" (the tab), "create" (choose a template), "form" (New event) or
    /// "event" (an event's page).
    property string page: ""
    property var discoverData: null
    property var manageData: null
    property var features: null
    property var current: null
    property string loadError: ""
    property bool filtersOpen: false
    property bool myEvents: false
    property string dateRange: ""
    property bool welcome: true
    /// Pinned to the app bar: Teams keeps it in your app entitlements (read
    /// on load, written by Pin app and the save dialog's Pin the Events app);
    /// the device setting only remembers it for the bar until then.
    property bool pinned: backend.setting("eventsAppPinned") === "true"
    /// Custom range's From and To (Filters).
    property var customFrom: null
    property var customTo: null
    /// See more: {section, title, items, total, next} while a whole section
    /// is shown.
    property var seeMore: null
    /// Your saved templates (Create's "Your saved templates").
    property var savedTemplates: null
    /// The event page's tab: "overview", "people", "insights", "highlights".
    property string eventTab: "overview"
    /// The event page's Preview (what attendees will see).
    property bool previewOn: false
    /// People & emails' lists.
    property var peopleData: null
    /// Teams' time zones ([key, label]) and this device's.
    property var zones: []
    property string localZone: ""
    signal pinToggled(bool on)
    signal viewMeetings()
    /// The intro card's View audio recaps: Meeting Recaps' Audio recaps.
    signal viewAudioRecaps()
    /// Manage apps' "here": the event meeting's details page (Teams'
    /// entityCommanding.calendar.meetingDetails for the session's meeting:
    /// the scheduling form's view, its default tab).
    signal openMeetingDetails(string joinUrl, string start)
    signal toast(var d)
    /// The event page's Join: its meeting's pre-join.
    signal joinEvent(string url, string title, string start, string end)
    /// The event page's chat button: the event meeting's chat.
    signal openEventChat(string chatId, string title)
    /// Copy join details: the title, time and join link (Teams' own text
    /// wasn't captured).
    function joinDetails(ev) {
        return (ev.title || "") + "\n" + whenText(ev.start, ev.end, true) + "\n\nJoin: " + (ev.join_url || "")
    }

    readonly property string cdn: "https://teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/"
    readonly property var templates: [
        { key: "scratch", title: "Create from scratch", text: "Mix and match capabilities as you go", img: "webp/192/design-l-standard-192x192.webp", chips: [], type: "Webinar", formTitle: "New event", access: "Organization", registration: false, greenRoom: false, chatLabel: "Chat" },
        { key: "webinar", title: "Webinar", text: "Best for interactive trainings, product demos, or thought leadership sessions", img: "webp/192/person-presentation-l-standard-192x192.webp", chips: ["Registration", "Video on demand", "Waitlist", "Green room"], type: "Webinar", formTitle: "New webinar", access: "Public", registration: true, greenRoom: true, chatLabel: "During event" },
        { key: "townhall", title: "Town hall", text: "Reach a large audience with a professional produced broadcast", img: "v2/person-video-live-l-standard.svg", chips: ["Up to 10K attendees", "Green room", "Video on demand", "HD video stream"], type: "Townhall", formTitle: "New town hall", access: "Organization", registration: false, greenRoom: true, large: true, chatLabel: "During event" },
        { key: "allhands", title: "All hands", text: "Share organization updates and engage employees at scale", img: "v2/web-meet-l-standard.svg", chips: ["Moderated Q&A", "Real-time reactions", "Green room", "Video on demand"], type: "Webinar", formTitle: "New all hands", access: "Organization", registration: false, greenRoom: true, chatLabel: "Chat" },
        { key: "training", title: "Training", text: "Teach, onboard, or upskill with an interactive session", img: "v2/book-pencil-l-standard.svg", chips: ["Breakout rooms", "Polls", "Live captions", "Registration", "Video on demand"], type: "Webinar", formTitle: "New training", access: "Public", registration: true, greenRoom: false, chatLabel: "Chat" },
        { key: "ama", title: "Ask me anything", text: "Open Q&A sessions with moderated audience questions", img: "v2/chat-multiple-l-standard.svg", chips: ["Moderated Q&A", "Polls", "Green room", "Producer controls"], type: "Townhall", formTitle: "New ask me anything", access: "Organization", registration: false, greenRoom: false, large: true, chatLabel: "During event" },
        { key: "community", title: "Community event", text: "Bring a community together for virtual experiences", img: "webp/192/people-house-l-standard-192x192.webp", chips: ["Registration", "Event chat", "Highlights", "Green room", "Waitlist"], type: "Webinar", formTitle: "New community event", access: "Public", registration: true, greenRoom: true, chatLabel: "During event" }
    ]

    // Requests to the events service, answered by events_reply.
    property var pending: ({})
    property int seq: 0
    function call(kind, payload, cb) {
        const id = "events" + (++seq)
        const p = Object.assign({}, pending); p[id] = cb; pending = p
        backend.eventsRequest(kind, id, JSON.stringify(payload || {}))
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            const cb = root.pending[id]
            if (!cb) return
            const p = Object.assign({}, root.pending); delete p[id]; root.pending = p
            let v = {}
            try { v = JSON.parse(json) } catch (e) { v = { error: "Bad reply" } }
            cb(v)
        }
    }
    // A date range's first and last moment, local days (Teams: From's
    // midnight to To's 23:59:59.999, sent in UTC with milliseconds).
    function range() {
        if (!dateRange) return {}
        const now = new Date()
        let start = new Date(now.getFullYear(), now.getMonth(), now.getDate()), last = new Date(start)
        if (dateRange === "thisWeek") { start.setDate(start.getDate() - start.getDay()); last = new Date(start); last.setDate(last.getDate() + 6) }
        else if (dateRange === "thisMonth") { start.setDate(1); last = new Date(start.getFullYear(), start.getMonth() + 1, 0) }
        else if (dateRange === "custom") {
            if (!customFrom || !customTo) return {}
            start = new Date(customFrom.getFullYear(), customFrom.getMonth(), customFrom.getDate())
            last = new Date(customTo.getFullYear(), customTo.getMonth(), customTo.getDate())
        }
        const end = new Date(last.getFullYear(), last.getMonth(), last.getDate(), 23, 59, 59, 999)
        return { from: start.toISOString(), to: end.toISOString() }
    }
    // The filter chip's text: "November 18 - 30, 2026", "Today", …
    function rangeText() {
        if (dateRange === "today") return "Today"
        if (dateRange === "thisWeek") return "This week"
        if (dateRange === "thisMonth") return "This month"
        if (dateRange !== "custom" || !customFrom || !customTo) return ""
        const a = customFrom, b = customTo
        if (a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth())
            return Qt.formatDate(a, "MMMM d") + " - " + b.getDate() + ", " + b.getFullYear()
        if (a.getFullYear() === b.getFullYear()) return Qt.formatDate(a, "MMMM d") + " - " + Qt.formatDate(b, "MMMM d, yyyy")
        return Qt.formatDate(a, "MMMM d, yyyy") + " - " + Qt.formatDate(b, "MMMM d, yyyy")
    }
    function clearFilters() { myEvents = false; dateRange = ""; customFrom = null; customTo = null; discoverData = null; reload() }
    // Pin app: Teams' pinned apps (and the toast "The Events app has been
    // pinned."); the header's Pin app goes once pinned (unpinning is the
    // app bar's Unpin).
    function setPinned(on) {
        call("pin", { on: on }, v => {
            if (v.error) { toast({ text: "Couldn't pin the app. " + v.error, intent: "error" }); return }
            pinned = on; pinToggled(on)
            if (on) toast({ text: "The Events app has been pinned.", intent: "success" })
        })
    }
    function openSeeMore(section, title) {
        seeMore = { section: section, title: title, items: [], total: 0, next: null, loading: true }
        page = "seeMore"
        call("seeMore", { section: section }, v => { if (!v.error) seeMore = { section: section, title: title, items: v.items || [], total: v.total || (v.items || []).length, next: v.next, loading: false } })
    }
    function moreOfSeeMore() {
        if (!seeMore || !seeMore.next) return
        const s = seeMore
        call("seeMore", { section: s.section, skip: s.next }, v => { if (!v.error) seeMore = Object.assign({}, s, { items: s.items.concat(v.items || []), next: v.next }) })
    }
    function loadTemplates() { call("templates", {}, v => { if (!v.error) savedTemplates = Array.isArray(v) ? v : [] }) }
    // "in 25 mins" while an event starts within the hour.
    // "in N mins" in the hour before the start (Teams: rounded down to 5,
    // at least 5; measured 2026-11-18).
    function soonText(start) {
        const m = Math.floor((new Date(start) - new Date()) / 60000)
        return m >= 0 && m <= 59 ? "in " + Math.max(5, Math.floor(m / 5) * 5) + " mins" : ""
    }
    // The event's two chats.
    function openChat(ev, crew) {
        const id = crew ? ev.backroom_thread_id : (ev.thread_id || ((decodeURIComponent(ev.join_url || "").match(/19:meeting_[^/]+@thread\.v2/) || [""])[0]))
        if (id) openEventChat(id, ev.title)
    }
    function copyJoinDetails(ev) {
        call("joinDetails", { link: ev.update_link || "" }, v => {
            if (v.error || !v.html) backend.copyText(joinDetails(ev)); else backend.copyHtml(v.html, joinDetails(ev))
            toast({ text: "Join details copied successfully", intent: "success" })
        })
    }
    function reload() {
        loadError = ""
        if (tab === "discover") call("discover", Object.assign({ myEvents: myEvents }, range()), v => { if (v.error) loadError = v.error; else discoverData = v })
        else call("manage", {}, v => { if (v.error) loadError = v.error; else manageData = v })
    }
    function openTab(t) { tab = t; page = ""; filtersOpen = false; reload() }
    function startCreate() { page = "create"; filtersOpen = false; loadTemplates() }
    /// Calendar ▸ New ▸ Webinar / Town hall: the form with that template.
    function startFormKey(key) { const t = templates.find(x => x.key === key); if (t) { filtersOpen = false; startForm(t) } }
    function startForm(t) {
        const now = new Date(), s = new Date(now)
        // Teams' default: the next half hour, for 30 minutes.
        s.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0)
        const e = new Date(s.getTime() + 30 * 60000)
        form.reset(t, s, e)
        page = "form"
        if (!features) call("features", {}, v => { if (!v.error) features = v })
    }
    function openEvent(card) {
        current = card; page = "event"; eventTab = "overview"; previewOn = false; peopleData = null
        call("overview", { id: card.id }, v => { if (!v.error && v.card) current = Object.assign({}, v.card, { access: v.access, inviteOnly: v.inviteOnly, registration: v.registration, description: v.description }) })
        call("people", { id: card.id }, v => { if (!v.error) peopleData = v })
    }
    // Edit (a card's, the page's Edit details): the event in the form.
    function editEvent(card) {
        current = current && current.id === card.id ? current : card
        call("event", { id: card.id }, v => {
            if (v.error) { toast({ text: "Couldn't open the event. " + v.error, intent: "error" }); return }
            form.fill(v); form.mode = "edit"; form.sourceId = card.id; page = "form"
            if (!features) call("features", {}, f => { if (!f.error) features = f })
        })
    }
    // Duplicate: the event's details in a new event's form, today's slot.
    function duplicateEvent(card) {
        call("event", { id: card.id }, v => {
            if (v.error) { toast({ text: "Couldn't open the event. " + v.error, intent: "error" }); return }
            form.fill(v); form.mode = "duplicate"; form.sourceId = card.id; page = "form"
        })
    }
    // A saved template's Schedule: a new event from it (Teams keeps
    // everything but the date and time).
    function scheduleFromTemplate(t) {
        const now = new Date(), s = new Date(now)
        s.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0)
        const d = Object.assign({}, t.data, { start: s.toISOString(), end: new Date(s.getTime() + 30 * 60000).toISOString() })
        form.fill(d); form.mode = "new"; page = "form"
        if (!features) call("features", {}, f => { if (!f.error) features = f })
    }
    function editTemplate(t) {
        form.fill(t.data); form.mode = "template"; form.sourceId = t.id
        form.templateName = t.name || ""; form.templateDescription = t.description || ""; page = "form"
    }
    // All options: the event template's meeting options (Teams'
    // meetingTemplates/details) with the event's values, in the meeting
    // options dialog; Apply keeps them for the save.
    function openAllOptions() {
        call("options", { townHall: form.townHall }, v => {
            if (v.error) { toast({ text: "Couldn't load the meeting options. " + v.error, intent: "error" }); return }
            // A new event's options as the form sends them (api::events'
            // defaults), then the event's own, then All options' changes.
            const defaults = { autoAdmittedUsers: "EveryoneInCompany", usersCanAdmitFromLobby: "OrganizersAndPresentersOnly", allowedUsersForMeetingDetails: "UsersAllowedToByPassTheLobby",
                               allowPstnUsersToBypassLobby: false, entryExitAnnouncementsEnabled: false, whoCanManageQna: "OrganizersAndCoorganizers", producerOption: "OrganizersAndPresentersOnly",
                               recorderOption: "OrganizersAndPresentersOnly", autoRecordAndTranscribeMode: "AutoRecordingAndTranscription", copilotMode: "EnabledWithTranscript",
                               meetingSpokenLanguage: "en-us", whoCanAccessTranscriptAndRecording: "Default", enableMultiLingualMeeting: false, attendanceReportEnabled: true }
            const cur = Object.assign(defaults, form.eventOptions || {}, form.optionChanges)
            // The form's own choices win.
            const restr = form.townHall && form.large ? "DisableAudio,DisableVideo" : form.mic && form.camera ? "UnRestricted" : !form.mic && !form.camera ? "DisableAudio,DisableVideo" : !form.mic ? "DisableAudio" : "DisableVideo"
            Object.assign(cur, { attendeeRestrictions: restr, allowTeamsMeetingReactions: form.react, allowMeetingChat: form.chat ? (cur.allowMeetingChat && cur.allowMeetingChat !== "Disabled" ? cur.allowMeetingChat : "Enabled") : "Disabled",
                                 yammerQNAEnabled: form.qna, stagingRoomEnabled: form.greenRoom })
            const opts = {}
            for (const o of (v.options || [])) {
                const key = o.name.charAt(0).toLowerCase() + o.name.slice(1)
                const copy = Object.assign({}, o)
                if (cur[key] !== undefined && copy.type !== "PeopleSelection" && copy.type !== "PresenterSelection") copy.currentValue = cur[key]
                // An event's lobby, recording and Copilot rows are fixed (Teams
                // shows them off); it has no Accessibility section.
                if (["AutoAdmittedUsers", "RecorderOption", "CopilotMode"].indexOf(o.name) >= 0) copy.isDisabled = true
                if (o.name === "CARTExternalFeed") continue
                opts[o.name] = copy
            }
            allOptions.options = opts
            allOptions.people = { translations: v.translations || {}, people: {}, invitees: [] }
            allOptions.open()
        })
    }
    Component.onCompleted: {
        reload()
        call("pinned", {}, v => { if (!v.error && v.pinned !== pinned) { pinned = v.pinned; pinToggled(v.pinned) } })
        call("zones", {}, v => { if (!v.error) { zones = v.zones || []; localZone = v.local || "" } })
        call("policy", {}, v => { if (!v.error) eventsPolicy = v })
    }
    onVisibleChanged: if (visible && page === "") reload()
    function stateForTest() {
        return JSON.stringify({ tab: tab, page: page, error: loadError, discover: discoverData ? { now: (discoverData.now || []).length, upcoming: (discoverData.upcoming || []).length, past: (discoverData.past || []).length } : null,
                                manage: manageData ? { drafts: manageData.drafts ? manageData.drafts.total : 0, published: manageData.published ? manageData.published.total : 0, past: manageData.past ? manageData.past.total : 0,
                                                       draftTitles: manageData.drafts ? manageData.drafts.items.map(i => i.title) : [] } : null,
                                filtered: discoverData && discoverData.filtered ? discoverData.filtered.map(i => i.title + " (" + (i.role || i.by) + ")") : null,
                                pinned: pinned, zones: zones.length, localZone: localZone,
                                seeMore: seeMore ? { title: seeMore.title, items: seeMore.items.length, total: seeMore.total } : null,
                                templates: savedTemplates ? savedTemplates.map(t => t.name) : null,
                                form: page === "form" ? { mode: form.mode, title: form.title, zone: form.zone, team: form.team.map(p => p.name), presenters: form.presenters.map(p => p.name),
                                                          attendees: form.attendees.map(p => p.name), rooms: form.rooms.map(p => p.name), options: Object.keys(form.optionChanges),
                                                          stage: [stagePreview.visible, stagePreview.x, stagePreview.y, stagePreview.width, stagePreview.parent ? stagePreview.parent.width : -1, form.open] } : null,
                                eventTab: page === "event" ? eventTab : "", preview: previewOn,
                                people: peopleData ? { organizers: (peopleData.organizerList || []).map(p => p.name), presenters: (peopleData.presenterList || []).map(p => p.name),
                                                       rooms: (peopleData.roomList || []).map(p => p.name), attendees: (peopleData.attendeeList || []).length } : null,
                                current: current ? { id: current.id, title: current.title, state: current.state, rooms: current.rooms, location: current.location, by: current.by,
                                                     discoverable: current.discoverable, description: current.description } : null })
    }
    // Test helpers (the harness, --events-test).
    function pickerForTest(kind) { return ({ team: teamPicker, presenters: presenterPicker, attendees: attendeePicker, rooms: roomPicker })[kind] }
    function descriptionForTest(text) {
        description.text = ""; description.insert(0, text)
        const w = text.lastIndexOf(" ") + 1
        rich.apply(w, text.length, "bold", ""); form.refreshRich()
    }
    function zoneForTest(open) { form.zoneOpen = open }
    function filtersForTest(mine, range, from, to) { myEvents = mine; dateRange = range; customFrom = from; customTo = to; discoverData = null; page = ""; tab = "discover"; reload() }
    function allOptionsForTest() { openAllOptions() }
    function allOptionsStateForTest() { return { open: allOptions.opened, options: Object.keys(allOptions.options).length } }
    function closeAllOptionsForTest() { allOptions.close() }
    function templateForTest(name) { templateDialog.openFor(current); templateDialog.nameForTest(name) }
    function saveTemplateForTest() { templateDialog.save() }
    function shareForTest(success) { shareDialog.openFor(current, success) }
    function closeShareForTest() { shareDialog.close() }
    function connectAppsForTest() { connectApps.openNow() }
    function closeConnectAppsForTest() { connectApps.close() }
    function connectAppsStateForTest() { return connectApps.items.map(i => i.name) }
    function roomOptionsForTest(on) { if (on) roomOptions.open(); else roomOptions.close() }
    function saveChangesForTest() { form.saveChanges() }
    function stageShotForTest(path) { stagePreview.grabToImage(r => r.saveToFile(path)); return [stagePreview.visible, stagePreview.mapToItem(root, 0, 0).x, stagePreview.mapToItem(root, 0, 0).y, stagePreview.opacity, stagePreview.parent.visible, stagePreview.parent.height] }
    function scrollCreateForTest() { createPage.contentY = Math.max(0, createPage.contentHeight - createPage.height) }
    function openSectionsForTest(list) { form.open = list; form.contentY = 0 }
    function scrollFormForTest(y) { form.contentY = y }

    // ---- shared parts ----
    component Btn: Rectangle {
        id: b
        property string text
        property string icon
        property bool primary: false
        property bool outlined: false
        property bool usable: true
        property int fontSize: 14
        property real pad: 12
        signal clicked()
        height: 32; radius: 4
        implicitWidth: (icon ? 20 + (text ? 6 : 0) : 0) + bt.implicitWidth + pad * 2
        width: implicitWidth
        color: !usable ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : outlined ? (bh.hovered ? theme.menuHover : theme.surface) : (bh.hovered ? theme.hover : "transparent")
        border.width: outlined && usable ? 1 : 0
        border.color: theme.stroke
        Row {
            anchors.centerIn: parent
            spacing: 6
            FluentIcon { visible: !!b.icon; name: b.icon; size: 20; anchors.verticalCenter: parent.verticalCenter; color: !b.usable ? theme.disabled : b.primary ? theme.textOnBrand : theme.textStrong }
            Text {
                id: bt
                text: b.text; visible: !!b.text
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: b.fontSize; font.weight: b.fontSize >= 14 ? Font.DemiBold : Font.Normal
                color: !b.usable ? theme.disabledStrong : b.primary ? theme.textOnBrand : outlined ? theme.text : theme.textStrong
            }
        }
        HoverHandler { id: bh; cursorShape: b.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: b.usable; onTapped: b.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: b.text
        Accessible.onPressAction: if (b.usable) b.clicked()
    }
    component Chip: Rectangle {
        property alias text: ct.text
        height: 24; radius: 12; width: ct.implicitWidth + 16
        color: theme.pick("#F5F5F5", "#292929", "#000000")
        border.width: theme.highContrast ? 1 : 0; border.color: theme.stroke
        Text { id: ct; anchors.centerIn: parent; font.family: theme.font; font.pixelSize: 12; color: theme.text }
    }
    // A template card (the tab pages' and Create's).
    component TemplateCard: Item {
        id: tc
        required property var modelData
        property real imageHeight: 163
        signal picked()
        FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
        Rectangle {
            x: 12; y: 12; width: parent.width - 24; height: tc.imageHeight; radius: 16
            color: theme.pick("#FAFAFA", "#141414", "#000000")
            Image { anchors.centerIn: parent; width: 88; height: 88; source: root.cdn + tc.modelData.img; asynchronous: true; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(176, 176) }
        }
        Text {
            id: tt
            x: 20; y: tc.imageHeight + 24; width: parent.width - 40
            text: tc.modelData.title; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: 20; y: tt.y + 34; width: parent.width - 40
            text: tc.modelData.text; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text
        }
        Flow {
            x: 12; y: tt.y + 92; width: parent.width - 24; spacing: 8
            Repeater { model: tc.modelData.chips; Chip { required property var modelData; text: modelData } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tc.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: tc.modelData.key === "scratch" ? tc.modelData.title : tc.modelData.title + " template, " + tc.modelData.text
    }
    // An event card (Manage's and Discover's lists).
    component EventCard: Item {
        id: ec
        required property var modelData
        width: 351; height: 303
        FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
        Rectangle {
            x: 12; y: 12; width: parent.width - 24; height: 109; radius: 16; clip: true
            color: ec.modelData.primary_color || "#5B5FC7"
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                source: { theme.dark; backend.emoticonsVersion; return ec.modelData.promo_image ? backend.cardImage(ec.modelData.promo_image) : "" }
            }
        }
        Text { x: 20; y: 131; width: parent.width - 40; text: ec.modelData.title; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        // Teams' card header (meet-app, measured 2026-11-18): a published
        // event shows a red "Live" badge (record glyph) from its start to
        // its end, or "in N mins" (clock, brand on #E8EBFA, rounded down
        // to 5, at least 5) in the hour before; the date follows it.
        property real now: Date.now()
        Timer { interval: 30000; running: ec.published; repeat: true; onTriggered: ec.now = Date.now() }
        readonly property bool published: ec.modelData.state === "Published"
        readonly property real startMs: ec.modelData.start ? new Date(ec.modelData.start).getTime() : 0
        readonly property real endMs: ec.modelData.end ? new Date(ec.modelData.end).getTime() : 0
        readonly property bool live: published && now >= startMs && now < endMs
        readonly property int soonMinutes: Math.floor((startMs - now) / 60000)
        readonly property bool soon: published && !live && soonMinutes >= 0 && soonMinutes <= 59
        // Teams' card actions: Join from 5 minutes before the start to the end.
        readonly property bool joinable: published && !!ec.modelData.join_url && now >= startMs - 300000 && now <= endMs
        Rectangle {
            id: ecBadge
            visible: ec.live || ec.soon
            x: 20; y: 160; height: 16; radius: 8
            width: ecBadgeRow.implicitWidth + (ec.live ? 10 : 6)
            color: ec.live ? "#D13438" : theme.pick("#E8EBFA", "#2F2F4A", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: theme.text
            Row {
                id: ecBadgeRow
                x: ec.live ? 4 : 2; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: ec.live ? "record-20" : "clock-12-filled"; size: ec.live ? 10 : 12
                             color: ec.live ? "#FFFFFF" : theme.brand }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ec.live ? "Live" : "in " + Math.max(5, Math.floor(ec.soonMinutes / 5) * 5) + " mins"
                       font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: ec.live ? "#FFFFFF" : theme.brand }
            }
        }
        Text { x: ecBadge.visible ? ecBadge.x + ecBadge.width + 4 : 20; y: ecBadge.visible ? 158 : 157; text: root.whenText(ec.modelData.start, ec.modelData.end, false); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        Column {
            x: 20; y: 187; spacing: 4
            // Your role ("Organizer"), else the presenter ("By OST Test 3").
            Row { spacing: 4; visible: !!ec.modelData.role || !!ec.modelData.by
                FluentIcon { name: "person-16"; size: 16; color: theme.textSecondary }
                Text { text: ec.modelData.role === "Organizer" || !ec.modelData.by ? (ec.modelData.role || "") : "By " + ec.modelData.by; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
            Row { spacing: 4
                FluentIcon { name: "location-20"; size: 16; color: theme.textSecondary }
                Text { text: ec.modelData.location || "Online"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
        }
        // Not joinable: Edit (64 x 24, outlined), Share (published), ···
        // (Chat with participants, Chat with event group, Duplicate).
        Row {
            visible: !ec.joinable
            x: 20; y: 259; spacing: 8
            readonly property bool organizer: ec.modelData.role === "Organizer" || ec.modelData.role === "CoOrganizer"
            Btn { visible: parent.organizer && ec.modelData.state !== "Canceled"; height: 24; text: "Edit"; icon: "edit-16"; outlined: true; fontSize: 12; pad: 8; onClicked: root.editEvent(ec.modelData) }
            Btn { visible: parent.organizer && ec.modelData.state === "Published"; width: 24; height: 24; icon: "share-16"; text: ""; outlined: true; pad: 4; Accessible.name: "Share event"; onClicked: shareDialog.openFor(ec.modelData, false) }
            Btn {
                id: cardMore
                visible: parent.organizer
                width: 24; height: 24; icon: "more-horizontal-20"; text: ""; pad: 2; Accessible.name: "More actions"
                onClicked: { cardMenu.ev = ec.modelData; cardMenu.parent = cardMore; cardMenu.x = 0; cardMenu.y = cardMore.height + 4; cardMenu.open() }
            }
        }
        // Joinable (5 minutes before the start to the end): Join (64 x 23,
        // brand, the video glyph), Copy event page link and More (24 x 23).
        Row {
            visible: ec.joinable
            x: 20; y: 261; spacing: 8
            Btn { height: 23; width: 64; primary: true; icon: "video-16"; text: "Join"; fontSize: 12; pad: 8; onClicked: root.joinEvent(ec.modelData.join_url, ec.modelData.title, ec.modelData.start, ec.modelData.end) }
            Btn { height: 23; width: 24; outlined: true; icon: "link-16"; text: ""; pad: 2; onClicked: { backend.copyText(ec.modelData.site_url || ec.modelData.join_url); root.toast({ text: "Copied", intent: "success" }) }
                  Accessible.name: "Copy event page link" }
            Btn {
                id: cardJoinMore
                visible: ec.modelData.role === "Organizer" || ec.modelData.role === "CoOrganizer"
                width: 24; height: 23; icon: "more-horizontal-20"; text: ""; pad: 2; Accessible.name: "More actions"
                onClicked: { cardMenu.ev = ec.modelData; cardMenu.parent = cardJoinMore; cardMenu.x = 0; cardMenu.y = cardJoinMore.height + 4; cardMenu.open() }
            }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openEvent(ec.modelData) }
        Accessible.role: Accessible.Button
        Accessible.name: "Event, " + ec.modelData.title + ", " + root.whenText(ec.modelData.start, ec.modelData.end, false)
    }
    // "Monday, Nov 16, 3:30 PM - 4:00 PM" (long: "Monday, November 16, …").
    function whenText(s, e, full) {
        if (!s) return ""
        const a = new Date(s), b = new Date(e || s)
        return Qt.formatDate(a, full ? "dddd, MMMM d" : "dddd, MMM d") + ", " + theme.time(a) + " - " + theme.time(b)
    }

    // An event card's ··· (Teams: Chat with participants, Chat with event
    // group, Duplicate).
    MenuPopup {
        id: cardMenu
        property var ev: ({})
        items: [{ key: "chat", label: "Chat with participants", icon: "chat-20" },
                { key: "crew", label: "Chat with event group", icon: "people-team-20" },
                { key: "dup", label: "Duplicate", icon: "copy-20" }]
        onPicked: i => { const k = items[i].key; if (k === "dup") root.duplicateEvent(ev); else root.openChat(ev, k === "crew") }
    }
    // ---- header ----
    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.pick("#FAFAFA", "#141414", "#000000")
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        Rectangle {
            x: 20; y: 14; width: 32; height: 32; radius: 4; color: "#5B5FC7"
            FluentIcon { anchors.centerIn: parent; name: "ticket-diagonal-20"; size: 20; color: "white" }
        }
        Text { x: 60; y: 15.7; text: "Events"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.textSecondary }
        Row {
            x: 136; y: 8
            Repeater {
                model: [["discover", "Discover"], ["manage", "Manage"]]
                Item {
                    required property var modelData
                    readonly property bool chosen: root.tab === modelData[0] && root.page === ""
                    width: tabText.implicitWidth + 20; height: 44
                    Text {
                        id: tabText
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]
                        font.family: theme.font; font.pixelSize: 14; font.weight: parent.chosen ? Font.DemiBold : Font.Normal
                        color: parent.chosen ? theme.text : theme.textStrong
                    }
                    Rectangle { visible: parent.chosen; x: 10; width: tabText.implicitWidth; height: 3; radius: 2; anchors.bottom: parent.bottom; anchors.bottomMargin: 0; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openTab(modelData[0]) }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData[1]
                    Accessible.selected: chosen
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 20; y: 14; spacing: 8
            Btn { visible: !root.pinned; icon: "pin-20"; text: "Pin app"; onClicked: root.setPinned(true) }
            Btn { visible: root.tab === "discover" && root.page === ""; icon: "filter-20"; text: "Filters"; onClicked: root.filtersOpen = !root.filtersOpen }
            Btn { icon: "calendar-add-20"; text: "Create event"; outlined: true; onClicked: root.startCreate() }
        }
    }

    // ---- the tabs ----
    Flickable {
        id: tabPage
        visible: root.page === ""
        anchors { top: header.bottom; left: parent.left; right: filters.visible ? filters.left : parent.right; bottom: parent.bottom }
        contentHeight: tabCol.y + tabCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real inner: width - 32 - 46
        // Teams' section titles (oneevents_discover_tab_*_section_title_text)
        // and See more's sections.
        readonly property bool filtered: root.tab === "discover" && (root.myEvents || root.dateRange !== "")
        readonly property var lists: root.tab === "discover"
            ? (root.discoverData ? (root.discoverData.filtered !== undefined ? [["", root.discoverData.filtered, ""]]
                : [["Happening now", root.discoverData.now || [], "now"], ["Upcoming events in your org", root.discoverData.upcoming || [], "upcoming"], ["Catch up on past events", root.discoverData.past || [], "past"]]) : [])
            : (root.manageData ? [["Drafts", root.manageData.drafts, "Draft"], ["Published", root.manageData.published, "Published"], ["Past", root.manageData.past, "Past"]] : [])
        readonly property bool empty: root.tab === "discover"
            ? !filtered && lists.every(l => l[1].length === 0)
            : !!root.manageData && (root.manageData.drafts.total + root.manageData.published.total + root.manageData.past.total) === 0
        Column {
            id: tabCol
            x: 32; y: root.tab === "discover" ? 168 : 32
            width: tabPage.inner
            spacing: 0
            // Manage: Connect apps on the right (146 x 32, outlined).
            Item {
                visible: root.tab === "manage"
                width: parent.width; height: 64
                Btn { anchors.right: parent.right; y: 0; outlined: true; icon: "plug-connected-20"; text: "Connect apps"; onClicked: connectApps.openNow() }
            }
            // Discover's filters as chips (24 tall, #D1D1D1, radius 4, 12/16
            // #424242, a dismiss) and Clear all (brand).
            Row {
                visible: tabPage.filtered
                height: visible ? 56 : 0; spacing: 8
                topPadding: 0
                Repeater {
                    model: [root.myEvents ? ["mine", "My events", ""] : null, root.dateRange ? ["range", root.rangeText(), "calendar-20"] : null].filter(x => !!x)
                    Rectangle {
                        required property var modelData
                        height: 24; radius: 4; width: chipRow.implicitWidth + 16; color: "transparent"; border.color: theme.stroke; border.width: 1
                        Row {
                            id: chipRow; x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            FluentIcon { visible: !!modelData[2]; name: modelData[2] || "calendar-20"; size: 16; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData[1]; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                            FluentIcon { name: "dismiss-12"; size: 12; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                        }
                        TapHandler { onTapped: { if (modelData[0] === "mine") root.myEvents = false; else { root.dateRange = ""; root.customFrom = null; root.customTo = null } root.discoverData = null; root.reload() } }
                        Accessible.role: Accessible.Button; Accessible.name: "Remove " + modelData[1]
                    }
                }
                Text {
                    y: 2; text: "Clear all"; font.family: theme.font; font.pixelSize: 14; color: theme.brand
                    TapHandler { onTapped: root.clearFilters() }
                    Accessible.role: Accessible.Button; Accessible.name: text
                }
            }
            // No matches.
            Row {
                visible: tabPage.filtered && !!root.discoverData && (root.discoverData.filtered || []).length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                height: visible ? 60 : 0; spacing: 8
                FluentIcon { name: "calendar-clock-20"; size: 20; color: theme.text; y: 20 }
                Text { y: 20; text: "No events match your filters."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text {
                    y: 20; text: "Clear all filters"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1; font.underline: true
                    TapHandler { onTapped: root.clearFilters() }
                    Accessible.role: Accessible.Button; Accessible.name: text
                }
            }
            Text { visible: !!root.loadError; text: "Couldn't load events. " + root.loadError; font.family: theme.font; font.pixelSize: 14; color: theme.danger; width: parent.width; wrapMode: Text.Wrap }
            // The empty state.
            Column {
                visible: tabPage.empty && (root.tab === "manage" ? !!root.manageData : !!root.discoverData)
                width: parent.width
                Item { width: 1; height: root.tab === "discover" ? 24 : 0 }
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; source: root.cdn + "v2/calendar-add-l-standard.svg"; sourceSize: Qt.size(256, 256); asynchronous: true }
                Item { width: 1; height: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No events have been scheduled yet"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: 450; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: "Customize everything from registration to how you want attendees to interact. We’ll walk you through each step."
                       font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 16 }
                Btn { anchors.horizontalCenter: parent.horizontalCenter; width: 155; height: 38; primary: true; text: "Create event"; onClicked: root.startCreate() }
                Item { width: 1; height: 32 }
            }
            // The lists.
            Repeater {
                model: tabPage.empty ? [] : tabPage.lists
                Column {
                    required property var modelData
                    // Discover's lists are arrays, Manage's {items, total}
                    // (a Repeater hands nested arrays over as sequences, not
                    // Arrays, so tell them apart by `items`).
                    readonly property var items: modelData[1] && modelData[1].items !== undefined ? modelData[1].items : (modelData[1] || [])
                    readonly property int total: modelData[1] && modelData[1].total !== undefined ? modelData[1].total : items.length
                    readonly property bool manage: root.tab === "manage"
                    // Discover leaves out an empty Happening now.
                    visible: manage || modelData[2] !== "now" || items.length > 0
                    width: tabCol.width
                    Item { width: 1; height: modelData[0] ? 26 : 0 }
                    Item {
                        visible: !!modelData[0]
                        width: parent.width; height: visible ? 32 : 0
                        Text { text: manage && total ? modelData[0] + " (" + total + ")" : modelData[0]; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 32; verticalAlignment: Text.AlignVCenter }
                        // See more (brand link) on the right.
                        Text {
                            visible: !manage || total > 0
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "See more"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.openSeeMore(modelData[2], modelData[0]) }
                            Accessible.role: Accessible.Link; Accessible.name: "See more " + modelData[0] + " events"
                        }
                    }
                    Item { width: 1; height: modelData[0] ? 16 : 0 }
                    Row {
                        visible: manage && items.length === 0
                        spacing: 12; leftPadding: 0; height: 47
                        FluentIcon { name: "calendar-clock-20"; size: 20; color: theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2] === "Draft" ? "Events you haven’t published yet will show up here." : modelData[0] + " events will show up here."; font.family: theme.font; font.pixelSize: 16; color: theme.textSecondary }
                    }
                    Flow {
                        visible: items.length > 0
                        width: parent.width; spacing: 16; leftPadding: 2; topPadding: 0
                        Repeater { model: items; EventCard {} }
                    }
                    Item { width: 1; height: items.length ? 30 : 0 }
                }
            }
            // Get started with a template.
            Column {
                visible: tabPage.empty
                width: parent.width
                Text { x: 8; text: "Get started with a template"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
                Item { width: 1; height: 8 }
                Flow {
                    x: 8; width: parent.width - 16; spacing: 16
                    Repeater {
                        model: root.templates.slice(1)
                        TemplateCard { width: (tabCol.width - 32) / 2; height: 317; onPicked: root.startForm(modelData) }
                    }
                }
            }
            // Manage immersive collections (ECS
            // enableImmersiveContentManagementInMeetApp and your events
            // policy's immersive events): Teams' archive picture, the title,
            // the text, View immersive collections.
            Item {
                visible: root.tab === "manage" && !!root.eventsPolicy.immersiveCollections
                width: parent.width; height: visible ? 24 + 176 : 0
                Rectangle {
                    y: 24; width: parent.width; height: 176; radius: 24
                    color: theme.pick("#F5F5F5", "#292929", "#000000"); border.color: theme.stroke; border.width: 1
                    Image { x: 24; anchors.verticalCenter: parent.verticalCenter; width: 128; height: 128; asynchronous: true
                            source: root.cdn + "webp/128/archive-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard-128x128.webp" }
                    Column { x: 24 + 128 + 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 24; spacing: 0
                        Text { text: "Manage immersive collections"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Item { width: 1; height: 4 }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: "Use immersive collections to save and manage templates for immersive events."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Item { width: 1; height: 16 }
                        Btn { outlined: true; text: "View immersive collections"; onClicked: root.openCollections() } }
                }
            }
        }
        // Manage's Connect apps (Teams' integrations dialog isn't built).
        // Discover's intro card stays at the top while the page scrolls.
        Rectangle {
            id: intro
            visible: root.tab === "discover"
            x: 32; width: tabPage.inner; height: 136
            y: Math.max(32, tabPage.contentY)
            z: 2; radius: 16
            color: theme.pick("#F5F5F5", "#292929", "#000000")
            border.color: theme.stroke; border.width: 1
            Text { x: 17; y: 13; text: "Introducing an app for all things events!"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 17; y: 39; width: parent.width - 34; wrapMode: Text.Wrap; maximumLineCount: 2
                   text: "Discover what's happening in your org and plan your own professional events, all in one place. You can still access your meetings and audio recaps."
                   font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Row {
                x: 17; y: 99; spacing: 10
                Btn { height: 24; fontSize: 12; pad: 8; outlined: true; text: "View meetings"; onClicked: root.viewMeetings() }
                Btn { height: 24; fontSize: 12; pad: 8; outlined: true; text: "View audio recaps"; onClicked: root.viewAudioRecaps() }
            }
        }
    }

    // ---- Manage ▸ Immersive collections (Teams 26304's immersive
    // collections pages, in Manage) ----
    // The list: the retirement notice (a warning bar: "Changes are coming to
    // Immersive Events in Teams." … Learn more, Dismiss), a back arrow,
    // "Immersive collections (n)" and Create collection; the collections as
    // cards (auto-fill, at least 300 wide, 24 / 20 apart, 150 tall: the
    // name, the description, View details) or the empty state (Teams'
    // folder-favorite picture, "You don’t have any immersive collections").
    // A collection: back, its name, the tabs Templates, Members, Settings.
    property var collections: null
    property var collection: null
    property var collectionPeople: null
    property string collectionTab: "templates"
    property bool retirementDismissed: false
    function openCollections() { page = "collections"; collections = null; call("collections", {}, v => { collections = v.error ? [] : v }) }
    function openCollection(c) {
        collection = { collection: { id: c.id, displayName: c.displayName, description: c.description } }
        collectionTab = "templates"; collectionPeople = null; page = "collection"
        pollCollection(c.id, 0)
    }
    // The group's owners and members (Graph; a new group shows up there a
    // little later, so ask again a few times).
    function loadCollectionPeople(id, tries) {
        call("collectionPeople", { id: id }, v => {
            if (!v.error) collectionPeople = v
            else if ((tries || 0) < 10) peopleTimer.again(id, (tries || 0) + 1)
        })
    }
    Timer { id: peopleTimer; interval: 3000; property string cid: ""; property int n: 0
            function again(id, k) { cid = id; n = k; restart() }
            onTriggered: root.loadCollectionPeople(cid, n) }
    // Teams asks again every second until the collection is ready (15 min).
    function pollCollection(id, n) {
        call("collection", { id: id }, v => {
            if (page !== "collection" || !collection || collection.collection.id !== id) return
            if (v.error) { if (n > 900) collection = { error: true }; else collTimer.again(id, n); return }
            collection = v
            if (v.status && v.status !== "Succeeded" && n < 900) collTimer.again(id, n)
            else if (!collectionPeople) loadCollectionPeople(id)
        })
    }
    Timer { id: collTimer; interval: 1000; property string cid: ""; property int n: 0
            function again(id, k) { cid = id; n = k + 1; restart() }
            onTriggered: root.pollCollection(cid, n) }
    readonly property bool imOwner: !!collectionPeople && (collectionPeople.owners || []).some(o => o.id === backend.userMri.replace("8:orgid:", ""))
    Flickable {
        id: collPage
        visible: root.page === "collections" || root.page === "collection"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: collCol.y + collCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: collCol
            x: 20; y: 24; width: Math.min(1440, collPage.width - 40); spacing: 8
            // The retirement notice.
            Rectangle {
                visible: root.page === "collections" && !root.retirementDismissed
                width: parent.width; height: visible ? retCol.implicitHeight + 24 : 0; radius: 4
                color: theme.pick("#FFF9F5", "#411200", "#000000"); border.color: theme.pick("#FDCFB4", "#8A3200", "#FFFFFF"); border.width: 1
                FluentIcon { x: 12; y: 14; name: "warning-20"; size: 20; color: theme.pick("#BC4B09", "#FAB28C", "#FFFFFF") }
                Column { id: retCol; x: 40; y: 12; width: parent.width - 96; spacing: 2
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Changes are coming to Immersive Events in Teams."; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Immersive Events will remain available and supported through April 2027. If your organization uses Immersive Events, please review future event plans and watch for additional guidance."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { text: "Learn more"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1; font.underline: true
                           HoverHandler { cursorShape: Qt.PointingHandCursor }
                           TapHandler { onTapped: Qt.openUrlExternally("https://aka.ms/ImmersiveUpdate") }
                           Accessible.role: Accessible.Link; Accessible.name: "Learn more about the Immersive Events update (opens in new tab)" } }
                Btn { anchors.right: parent.right; anchors.rightMargin: 8; y: 8; icon: "dismiss-20"; text: ""; pad: 6; Accessible.name: "Dismiss"; onClicked: root.retirementDismissed = true }
            }
            Item { width: 1; height: root.page === "collections" && !root.retirementDismissed ? 8 : 0 }
            // The header.
            Item {
                width: parent.width; height: 32
                Btn { icon: "arrow-left-20"; text: ""; pad: 6; Accessible.name: root.page === "collection" ? "Back to collections" : "Go back"
                      onClicked: { if (root.page === "collection") root.openCollections(); else { root.page = ""; root.openTab("manage") } } }
                Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 260; elide: Text.ElideRight
                       text: root.page === "collection" ? (root.collection && root.collection.collection ? root.collection.collection.displayName : "")
                             : (root.collections && root.collections.length ? "Immersive collections (" + root.collections.length + ")" : "Immersive collections")
                       font.family: theme.font; font.pixelSize: root.page === "collection" ? 16 : 20; font.weight: Font.DemiBold; color: theme.text }
                Btn { visible: root.page === "collections"; anchors.right: parent.right; outlined: true; icon: "add-20"; text: "Create collection"; onClicked: collDialog.openFor(null) }
            }
            // ---- the list ----
            Text { visible: root.page === "collections" && root.collections === null; text: "Loading..."; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary; height: 400; width: parent.width; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            Column {
                visible: root.page === "collections" && !!root.collections && root.collections.length === 0
                width: parent.width; spacing: 8
                Item { width: 1; height: 160 }
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; asynchronous: true
                        source: root.cdn + "webp/128/folder-favorite-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard-128x128.webp" }
                Item { width: 1; height: 8 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(600, parent.width); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: "You don’t have any immersive collections"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(600, parent.width); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2
                       text: "Immersive collections allow you to share custom environments and templates. Create a collection when the time’s right!"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Flow {
                visible: root.page === "collections" && !!root.collections && root.collections.length > 0
                width: parent.width; spacing: 20
                readonly property int cols: Math.max(1, Math.floor((width + 20) / 320))
                Repeater {
                    model: root.collections || []
                    Item {
                        required property var modelData
                        width: (collCol.width - 20 * (parent.cols - 1)) / parent.cols; height: 150 + 4
                        FluentSurface { width: parent.width; height: 150; depth: 4; radius: 8; color: theme.surface }
                        Column { x: 12; y: 12; width: parent.width - 24; spacing: 4
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.displayName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { visible: !!modelData.description; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: modelData.description || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                        Btn { anchors.right: parent.right; anchors.rightMargin: 12; y: 150 - 44; outlined: true; icon: "calendar-add-20"; text: "View details"; onClicked: root.openCollection(modelData) }
                        TapHandler { onTapped: root.openCollection(modelData) }
                        Accessible.role: Accessible.ListItem; Accessible.name: "Immersive collection, " + modelData.displayName + ", " + (modelData.description || "")
                    }
                }
            }
            // ---- a collection ----
            Text { visible: root.page === "collection" && !!root.collection && !!root.collection.error; text: "Error loading collection details"; font.family: theme.font; font.pixelSize: 14; color: theme.danger }
            Row {
                visible: root.page === "collection" && !!root.collection && !root.collection.error
                height: 44; spacing: 4
                Repeater { model: [["templates", "Templates"], ["members", "Members"], ["settings", "Settings"]]
                    Item {
                        required property var modelData
                        width: tabT.implicitWidth + 20; height: 44
                        Text { id: tabT; anchors.centerIn: parent; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: root.collectionTab === modelData[0] ? Font.DemiBold : Font.Normal; color: root.collectionTab === modelData[0] ? theme.text : theme.textStrong }
                        Rectangle { visible: root.collectionTab === modelData[0]; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; anchors.horizontalCenter: parent.horizontalCenter; width: tabT.implicitWidth; height: 3; radius: 2; color: theme.brand }
                        TapHandler { onTapped: root.collectionTab = modelData[0] }
                        Accessible.role: Accessible.PageTab; Accessible.name: modelData[1]
                    } }
            }
            readonly property bool provisioning: !!root.collection && root.collection.status === "Provisioning"
            // Templates.
            Column {
                visible: root.page === "collection" && root.collectionTab === "templates" && !!root.collection && !root.collection.error
                width: parent.width; spacing: 16
                Text { text: "Immersive templates (0)"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Text { visible: collCol.provisioning; width: parent.width; height: 400; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap
                       text: "Your collection is being created! It can take up to 15 minutes before storage is set up and you can upload environments and edit templates."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Column {
                    visible: !collCol.provisioning
                    width: parent.width; spacing: 16
                    Item { width: 1; height: 60 }
                    Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; asynchronous: true
                            source: root.cdn + "webp/128/design-from-scratch-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard-128x128.webp" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(600, parent.width); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                           text: "You don't have any immersive templates in this collection yet. You can create a template from any immersive event."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                }
            }
            // Members.
            Column {
                visible: root.page === "collection" && root.collectionTab === "members"
                width: parent.width; spacing: 12
                Item { width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Owners (" + ((root.collectionPeople || {}).owners || []).length + ")"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                    Btn { anchors.right: parent.right; outlined: true; icon: "person-add-20"; text: "Add people"; usable: root.imOwner; onClicked: collAdd.openNow() } }
                CollTable { people: (root.collectionPeople || {}).owners || []; owners: true }
                Text { text: "Members (" + ((root.collectionPeople || {}).members || []).length + ")"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 32; verticalAlignment: Text.AlignVCenter }
                CollTable { people: (root.collectionPeople || {}).members || []; owners: false }
            }
            // Settings.
            Column {
                visible: root.page === "collection" && root.collectionTab === "settings" && !!root.collection && !!root.collection.collection
                width: parent.width; spacing: 20
                Item { width: parent.width; height: 32
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Collection details"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                    Btn { anchors.right: parent.right; outlined: true; icon: "settings-20"; text: "Edit details"; onClicked: collDialog.openFor(root.collection.collection) } }
                Item {
                    width: parent.width; height: detailsCol.height
                    FluentSurface { anchors.fill: parent; depth: 8; radius: 8; color: theme.surface }
                    Column { id: detailsCol; width: parent.width
                        Repeater { model: root.collection && root.collection.collection ? [["Collection name", root.collection.collection.displayName], ["Description", root.collection.collection.description || "—"],
                                                                                         ["Sensitivity", "—"], ["Privacy", "Private"]] : []
                            Item { required property var modelData; width: detailsCol.width; height: 40
                                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                Text { x: 200; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 216; elide: Text.ElideRight; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text } } } }
                }
                Text { text: "Manage"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Item {
                    width: parent.width; height: 56
                    FluentSurface { anchors.fill: parent; depth: 8; radius: 8; color: theme.surface }
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Delete collection"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { x: 176; anchors.verticalCenter: parent.verticalCenter; text: "Deleting a collection is permanent and cannot be undone"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: delT.implicitWidth + 24; height: 32; radius: 4
                        color: delH.hovered ? theme.pick("#B10E1C", "#D13438", "#FFFFFF") : theme.pick("#C50F1F", "#C50F1F", "#FFFFFF")
                        Text { id: delT; anchors.centerIn: parent; text: "Delete collection"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                        HoverHandler { id: delH; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: collDelete.open() }
                        Accessible.role: Accessible.Button; Accessible.name: "Delete collection" }
                }
            }
        }
    }
    // A collection's people table: Name and email (the avatar, the name,
    // the UPN), Title, Role (Owner / Member), and Remove for members.
    component CollTable: Column {
        id: ct
        property var people: []
        property bool owners: false
        width: collCol.width
        Item { width: parent.width; height: 40
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Name and email"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 516; anchors.verticalCenter: parent.verticalCenter; text: "Title"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 716; anchors.verticalCenter: parent.verticalCenter; text: "Role"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text } }
        Rectangle { width: parent.width; height: 1; color: theme.divider }
        Repeater { model: ct.people
            Column { required property var modelData; required property int index
                width: ct.width
                Item { width: parent.width; height: 64
                    Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 36; name: modelData.displayName; photoId: "8:orgid:" + modelData.id }
                    Column { x: 64; anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.displayName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { text: modelData.userPrincipalName || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    Text { x: 516; anchors.verticalCenter: parent.verticalCenter; text: modelData.jobTitle || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    ComboBox {
                        x: 716; anchors.verticalCenter: parent.verticalCenter; width: 120
                        model: ["Owner", "Member"]; currentIndex: ct.owners ? 0 : 1
                        enabled: root.imOwner && !(ct.owners && ct.people.length <= 1)
                        onActivated: i => root.call("changeCollectionPerson", { id: root.collection.collection.id, user: modelData.id, what: i === 0 ? "owner" : "member" },
                                                    v => { if (!v.error) root.call("collectionPeople", { id: root.collection.collection.id }, p => { if (!p.error) root.collectionPeople = p }) })
                        Accessible.name: "Role"
                    }
                    Btn { visible: !ct.owners && (root.imOwner || modelData.id === backend.userMri.replace("8:orgid:", "")); anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                          icon: "dismiss-20"; text: ""; pad: 6; Accessible.name: "Remove " + modelData.displayName; onClicked: collRemove.openFor(modelData) }
                }
                Rectangle { visible: index < ct.people.length - 1; width: parent.width; height: 1; color: theme.divider } } }
    }
    // Create an immersive collection / Edit immersive collection.
    Popup {
        id: collDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: Math.max(320, Math.min(600, parent.width * 0.9))
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var editing: null
        property bool busy: false
        property string error: ""
        property bool touched: false
        function openFor(c) { editing = c; busy = false; error = ""; touched = false; collName.text = c ? c.displayName : ""; collDesc.text = c ? (c.description || "") : ""; open() }
        function submit() {
            if (!collName.text.trim()) { touched = true; return }
            busy = true
            const done = v => {
                busy = false
                if (v.error) { error = /403/.test(v.error) ? "Your organization doesn't allow you to create Microsoft 365 groups, which are required for collections. Contact your IT administrator, or ask to be added to an existing collection." : "Something went wrong. Please try again."; return }
                close()
                if (editing) root.pollCollection(editing.id, 0)
                else { root.call("collections", {}, l => { if (!l.error) root.collections = l }); root.openCollection({ id: v.id, displayName: collName.text.trim(), description: collDesc.text.trim() }) }
            }
            if (editing) root.call("updateCollection", { id: editing.id, name: collName.text, description: collDesc.text }, done)
            else root.call("createCollection", { name: collName.text, description: collDesc.text }, done)
        }
        contentItem: Column {
            spacing: 15
            Item { width: parent.width; height: 28
                Text { text: collDialog.editing ? "Edit immersive collection" : "Create an immersive collection"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: collDialog.close(); Accessible.name: "Close dialog" } }
            Rectangle { visible: !!collDialog.error; width: parent.width; height: visible ? errT.implicitHeight + 16 : 0; radius: 4; color: theme.pick("#FDF3F4", "#3B2326", "#000000")
                        Text { id: errT; x: 12; y: 8; width: parent.width - 24; wrapMode: Text.Wrap; text: collDialog.error; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
            Column { width: parent.width; spacing: 4
                Label { text: "Collection name *" }
                Rectangle { width: parent.width; height: 32; radius: 4; color: theme.input; border.color: collName.activeFocus ? theme.brand : theme.stroke; border.width: 1
                    TextInput { id: collName; x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; clip: true; selectByMouse: true; font.family: theme.font; font.pixelSize: 14; color: theme.text; Accessible.name: "Collection name"
                                Text { visible: !parent.text && !parent.activeFocus; text: "Enter a name for your collection"; font: parent.font; color: theme.textSecondary } } }
                Text { visible: collDialog.touched && collName.text.length > 0 && !collName.text.trim() || (collDialog.touched && !collName.text.trim()); text: "Collection name is required"; font.family: theme.font; font.pixelSize: 12; color: theme.danger } }
            Column { width: parent.width; spacing: 4
                Label { text: "Collection description" }
                Rectangle { width: parent.width; height: collDialog.editing ? 72 : 32; radius: 4; color: theme.input; border.color: collDesc.activeFocus ? theme.brand : theme.stroke; border.width: 1
                    TextEdit { id: collDesc; x: 10; y: 6; width: parent.width - 20; height: parent.height - 12; wrapMode: TextEdit.Wrap; clip: true; selectByMouse: true; font.family: theme.font; font.pixelSize: 14; color: theme.text; Accessible.name: "Collection description"
                               Text { visible: !parent.text && !parent.activeFocus; text: "Enter a short description for your collection"; font: parent.font; color: theme.textSecondary } } } }
            Column { width: parent.width; spacing: 4
                Label { text: collDialog.editing ? "Privacy" : "Privacy *" }
                Row { spacing: 15
                    Repeater { model: [["Private", "People need permission to join", "lock-closed-20", true], ["Public", "Anyone can join", "globe-20", false]]
                        Rectangle { required property var modelData
                            width: (collDialog.availableWidth - 15) / 2; height: 80; radius: 8; opacity: modelData[3] ? 1 : 0.6
                            color: theme.surface; border.color: modelData[3] ? theme.brand : theme.stroke; border.width: modelData[3] ? 2 : 1
                            FluentIcon { x: 12; y: 12; name: modelData[2]; size: 20; color: theme.textStrong }
                            Text { x: 40; y: 12; text: modelData[0]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { x: 40; y: 34; width: parent.width - 52; wrapMode: Text.Wrap; text: modelData[1]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                            ToolTip.visible: !modelData[3] && pubH.hovered; ToolTip.text: "Public immersive collections are not supported yet."
                            HoverHandler { id: pubH }
                            Accessible.role: Accessible.RadioButton; Accessible.name: modelData[0]; Accessible.checked: modelData[3] } } } }
            Row { anchors.right: parent.right; spacing: 8
                Btn { outlined: true; text: "Cancel"; usable: !collDialog.busy; onClicked: collDialog.close() }
                Btn { primary: true; usable: !collDialog.busy && !!collName.text.trim()
                      text: collDialog.editing ? (collDialog.busy ? "Saving..." : "Save") : (collDialog.busy ? "Creating..." : "Create collection"); onClicked: collDialog.submit() } }
        }
    }
    // Add people to this collection: Owners and Members pickers.
    Popup {
        id: collAdd
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 600
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var owners: []
        property var members: []
        property bool busy: false
        function openNow() { owners = []; members = []; busy = false; open() }
        contentItem: Column {
            spacing: 30
            Item { width: parent.width; height: 28
                Text { text: "Add people to this collection"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: collAdd.close(); Accessible.name: "Close dialog" } }
            Column { width: parent.width; spacing: 10
                Label { text: "Owners" }
                EventPeoplePicker { id: collOwnersPicker; width: parent.width; kind: "team"; placeholder: "Enter a name or distribution list to add to your collection"; picked: collAdd.owners; onChanged: list => collAdd.owners = list }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Those who have admin privileges and can edit templates and environments"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
            Column { width: parent.width; spacing: 10
                Label { text: "Members" }
                EventPeoplePicker { id: collMembersPicker; width: parent.width; kind: "team"; placeholder: "Enter a name or distribution list to add to your collection"; picked: collAdd.members; onChanged: list => collAdd.members = list }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Those who can access and edit event templates and environments"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
            Row { anchors.right: parent.right; spacing: 8
                Btn { outlined: true; text: "Cancel"; onClicked: collAdd.close() }
                Btn { primary: true; usable: !collAdd.busy && collAdd.owners.length + collAdd.members.length > 0; text: "Add people"
                      onClicked: {
                          collAdd.busy = true
                          const id = root.collection.collection.id
                          root.call("addCollectionPeople", { id: id, owners: collAdd.owners.map(p => p.object_id || p.objectId), members: collAdd.members.map(p => p.object_id || p.objectId) }, v => {
                              collAdd.busy = false
                              console.warn("EVENTS collection people added", JSON.stringify(v))
                              // Teams adds them to its cached lists (no refetch).
                              if (!v.error) {
                                  const asRow = p => ({ id: p.object_id || p.objectId, displayName: p.name, jobTitle: null, userPrincipalName: p.upn || p.email })
                                  const cur = root.collectionPeople || { owners: [], members: [] }
                                  const owners = cur.owners.concat(collAdd.owners.map(asRow).filter(o => !cur.owners.some(x => x.id === o.id)))
                                  const members = cur.members.concat(collAdd.members.map(asRow)).filter((m, i, a) => !owners.some(o => o.id === m.id) && a.findIndex(x => x.id === m.id) === i)
                                  root.collectionPeople = { owners: owners, members: members }
                                  collAdd.close()
                              }
                          })
                      } } }
        }
    }
    // Remove person from this collection?
    Popup {
        id: collRemove
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var person: null
        function openFor(p) { person = p; open() }
        contentItem: Column {
            spacing: 16
            Text { text: "Remove person from this collection?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { width: parent.width; wrapMode: Text.Wrap; text: "This person will no longer have access to the collection or its contents."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Row { anchors.right: parent.right; spacing: 8
                Btn { outlined: true; text: "Cancel"; onClicked: collRemove.close() }
                Btn { primary: true; text: "Remove person"
                      onClicked: { const id = root.collection.collection.id
                          root.call("changeCollectionPerson", { id: id, user: collRemove.person.id, what: "remove" }, v => {
                              collRemove.close(); root.call("collectionPeople", { id: id }, p => { if (!p.error) root.collectionPeople = p }) }) } } }
        }
    }
    // Delete this collection?
    Popup {
        id: collDelete
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property bool busy: false
        contentItem: Column {
            spacing: 16
            Text { text: "Delete this collection?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { width: parent.width; wrapMode: Text.Wrap; text: "This action cannot be undone and you will lose all associated content within."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Row { anchors.right: parent.right; spacing: 8
                Btn { outlined: true; text: "Cancel"; onClicked: collDelete.close() }
                Btn { primary: true; usable: !collDelete.busy; text: "Delete collection"
                      onClicked: { collDelete.busy = true
                          root.call("deleteCollection", { id: root.collection.collection.id }, v => {
                              collDelete.busy = false; console.warn("EVENTS collection deleted", JSON.stringify(v)); collDelete.close()
                              // Teams drops it from its cached list (Graph lists it a while longer).
                              if (!v.error) { const gone = root.collection.collection.id; root.page = "collections"; root.collections = (root.collections || []).filter(c => c.id !== gone)
                                              root.call("collections", {}, l => { if (!l.error) root.collections = l.filter(c => c.id !== gone) }) } }) } } }
        }
    }
    // Manage's card: Manage immersive collections.
    function collectionsStateForTest() { return JSON.stringify({ page: page, list: collections ? collections.map(c => c.displayName) : null, collection: collection, people: collectionPeople, tab: collectionTab, owner: imOwner }) }
    function createCollectionForTest(name, desc) { collDialog.openFor(null); collName.text = name; collDesc.text = desc; collDialog.submit() }
    function addCollectionPeopleForTest(text) { collAdd.openNow(); collMembersPicker.typeForTest(text) }
    function pickCollectionPersonForTest() { collMembersPicker.pickFirstForTest() }
    function confirmAddCollectionPeopleForTest() { collAdd.contentItem.children[collAdd.contentItem.children.length - 1].children[1].clicked() }
    function deleteCollectionForTest() { collDelete.open(); collDelete.contentItem.children[collDelete.contentItem.children.length - 1].children[1].clicked() }
    // ---- Filters (Discover) ----
    Rectangle {
        id: filters
        visible: root.filtersOpen && root.page === "" && root.tab === "discover"
        anchors { top: header.bottom; bottom: parent.bottom; right: parent.right }
        width: 352
        color: theme.surface
        Rectangle { width: 1; height: parent.height; color: theme.divider }
        property bool mine: root.myEvents
        property string range: root.dateRange
        property var from: root.customFrom
        property var to: root.customTo
        property bool tried: false
        onVisibleChanged: if (visible) { mine = root.myEvents; range = root.dateRange; from = root.customFrom; to = root.customTo; tried = false }
        // Custom range needs both dates ("Select a date." under an empty one).
        readonly property bool rangeOk: range !== "custom" || (!!from && !!to && to >= from)
        Text { x: 25; y: 22; text: "Filters"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Btn { x: parent.width - 56; y: 20; icon: "dismiss-20"; text: ""; pad: 6; onClicked: root.filtersOpen = false; Accessible.name: "Close filters" }
        Rectangle { x: 1; y: 72; width: parent.width - 1; height: 1; color: theme.divider }
        Text { x: 25; y: 93; text: "My events"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 25; y: 119; text: "Events you're invited to or registered for"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        SettingsParts.Toggle { x: parent.width - 72; y: 101; stateLabel: false; on: filters.mine; accessibleName: "My events"; onToggled: v => filters.mine = v }
        Rectangle { x: 1; y: 155; width: parent.width - 1; height: 1; color: theme.divider }
        Text { x: 25; y: 176; text: "Date range"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Grid {
            x: 25; y: 204; columns: 2; columnSpacing: 0; rowSpacing: 0
            Repeater {
                model: [["today", "Today"], ["thisWeek", "This week"], ["thisMonth", "This month"], ["custom", "Custom range"]]
                Item {
                    required property var modelData
                    width: 141; height: 36
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
                                border.color: filters.range === modelData[0] ? theme.brand : theme.textSecondary
                                Rectangle { visible: filters.range === modelData[0]; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand } }
                    Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                    TapHandler { onTapped: filters.range = modelData[0] }
                    Accessible.role: Accessible.RadioButton; Accessible.name: modelData[1]; Accessible.checked: filters.range === modelData[0]
                }
            }
        }
        // Custom range: From and To (146 x 32 filled date fields, 14 apart,
        // labels 14/20 at 24 above them).
        Row {
            visible: filters.range === "custom"
            x: 25; y: 280; spacing: 13
            Repeater {
                model: [["From", "from"], ["To", "to"]]
                Column {
                    required property var modelData
                    spacing: 8
                    Text { text: modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text; height: 20 }
                    DatePickerField {
                        width: 146; height: 32; format: "MM/dd/yyyy"
                        date: filters[modelData[1]] || new Date()
                        placeholder: "mm/dd/yyyy"
                        empty: !filters[modelData[1]]
                        filled: true
                        onPicked: d => filters[modelData[1]] = d
                    }
                    Text { visible: filters.tried && !filters[modelData[1]]; text: "Select a date."; font.family: theme.font; font.pixelSize: 12; color: theme.danger }
                }
            }
        }
        Rectangle { x: 1; y: parent.height - 57; width: parent.width - 1; height: 1; color: theme.divider }
        Text {
            x: 17; y: parent.height - 38; text: "Clear all"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
            TapHandler { onTapped: { filters.mine = false; filters.range = ""; filters.from = null; filters.to = null } }
        }
        Btn { x: parent.width - 216; y: parent.height - 44; width: 96; outlined: true; text: "Cancel"; onClicked: root.filtersOpen = false }
        Btn { x: parent.width - 112; y: parent.height - 44; width: 96; primary: true; text: "Apply"
              onClicked: {
                  filters.tried = true
                  if (!filters.rangeOk) return
                  root.myEvents = filters.mine; root.dateRange = filters.range
                  root.customFrom = filters.range === "custom" ? filters.from : null; root.customTo = filters.range === "custom" ? filters.to : null
                  root.filtersOpen = false; root.discoverData = null; root.reload()
              } }
    }

    // ---- See more: a whole section ----
    // A back arrow and the section's title (20/28 semibold, 157 down in
    // Teams' 1280 window), "Showing 1 event" (14/20) 46 under it, then the
    // cards in rows (16 apart); more load as it scrolls (25 a page).
    Flickable {
        id: seeMorePage
        visible: root.page === "seeMore" && !!root.seeMore
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: seeFlow.y + seeFlow.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onAtYEndChanged: if (atYEnd && visible) root.moreOfSeeMore()
        Btn { x: 20; y: 32; icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.openTab(root.tab); Accessible.name: "Go back" }
        Text { x: 64; y: 34; text: root.seeMore ? root.seeMore.title : ""; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 20; y: 84; text: root.seeMore && !root.seeMore.loading ? (root.seeMore.total === 1 ? "Showing 1 event" : "Showing " + root.seeMore.total + " events") : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Flow {
            id: seeFlow
            x: 22; y: 124; width: seeMorePage.width - 44; spacing: 16
            Repeater { model: root.seeMore ? root.seeMore.items : []; EventCard {} }
        }
    }

    // ---- Create: choose what you're organizing ----
    Flickable {
        id: createPage
        visible: root.page === "create"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: savedCol.y + savedCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Btn { x: 24; y: 32; icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.page = ""; Accessible.name: "Go back" }
        Text { x: 71; y: 34; text: "Create"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 24; y: 90; text: "Choose what you're organizing"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Flow {
            id: createGrid
            x: 24; y: 134; width: createPage.width - 24 - 38; spacing: 20
            Repeater {
                model: root.templates
                TemplateCard { width: (createGrid.width - 40) / 3; height: 292.4; imageHeight: 106.4; onPicked: root.startForm(modelData) }
            }
        }
        // "Your saved templates" (20/28 semibold, 50 under the cards): your
        // templates' cards (the promo picture 323 x 108, the name 16/22
        // semibold, the description, Schedule and ···: Edit template,
        // Delete), or "Save an event as a template and it will show up here."
        Column {
            id: savedCol
            x: 24; y: createGrid.y + createGrid.height + 40; width: createGrid.width
            spacing: 0
            Text { text: "Your saved templates"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 28 }
            Item { width: 1; height: 28 }
            Column {
                visible: !!root.savedTemplates && root.savedTemplates.length === 0
                width: parent.width; spacing: 16
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; source: root.cdn + "v2/document-add-l-standard.svg"; sourceSize: Qt.size(256, 256); asynchronous: true }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Save an event as a template and it will show up here."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Flow {
                width: parent.width; spacing: 20
                Repeater {
                    model: root.savedTemplates || []
                    Item {
                        id: tcard
                        required property var modelData
                        width: (createGrid.width - 40) / 3; height: 303
                        FluentSurface { anchors.fill: parent; depth: 2; radius: 24; color: theme.surface }
                        Rectangle {
                            x: 12; y: 12; width: parent.width - 24; height: 108; radius: 16; clip: true; color: "#5B5FC7"
                            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                    source: { backend.emoticonsVersion; return tcard.modelData.promo ? backend.cardImage(tcard.modelData.promo) : "" } }
                        }
                        Text { x: 20; y: 130; width: parent.width - 40; elide: Text.ElideRight; text: tcard.modelData.name; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Text { x: 20; y: 158; width: parent.width - 40; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: tcard.modelData.description || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Row {
                            x: 20; y: 259; spacing: 8
                            Btn { height: 24; outlined: true; fontSize: 12; pad: 8; icon: "calendar-add-20"; text: "Schedule"; onClicked: root.scheduleFromTemplate(tcard.modelData) }
                            Btn {
                                id: tmore; width: 24; height: 24; icon: "more-horizontal-20"; text: ""; pad: 2; Accessible.name: "More actions"
                                onClicked: { templateMenu.t = tcard.modelData; templateMenu.parent = tmore; templateMenu.x = 0; templateMenu.y = tmore.height + 4; templateMenu.open() }
                            }
                        }
                    }
                }
            }
        }
        MenuPopup {
            id: templateMenu
            property var t: ({})
            items: [{ key: "edit", label: "Edit template", icon: "edit-20" }, { key: "delete", label: "Delete", icon: "delete-20" }]
            onPicked: i => {
                if (items[i].key === "edit") root.editTemplate(t)
                else root.call("deleteTemplate", { id: t.id }, v => {
                    if (v.error) { root.toast({ text: "Couldn't delete the template. " + v.error, intent: "error" }); return }
                    root.toast({ text: "Template deleted", intent: "success" }); root.loadTemplates()
                })
            }
        }
    }

    // ---- New event ----
    Flickable {
        id: form
        visible: root.page === "form"
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: formCol.y + formCol.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        property var template: root.templates[0]
        property date start: new Date()
        property date end: new Date()
        property string access: "Organization"
        property bool registration: false
        property bool greenRoom: false
        property bool mic: true
        property bool camera: true
        property bool react: true
        property bool chat: true
        property bool qna: true
        property int capacity: 0
        property bool large: false
        property var open: [true, false, false, false]
        property bool saving: false
        // A town hall streams to a large audience by default (3,000
        // view-only attendees, green room on); its tiles are Mic and Camera
        // (off, "Selected capacity does not support this engagement
        // feature.") and Q&A, then "Manage what attendees see".
        readonly property bool townHall: template.type === "Townhall"
        property string attendeeView: "Off"
        /// "new", "edit" (Edit details: Save changes), "duplicate" (Save and
        /// continue makes the copy) or "template" (Edit template).
        property string mode: "new"
        /// The event (edit, duplicate) or template (template) behind it.
        property string sourceId: ""
        property string sessionId: ""
        property string promo: ""
        property string templateName: ""
        property string templateDescription: ""
        property bool discoverable: false
        property string zone: ""
        property bool zoneOpen: false
        property var team: []
        property var presenters: []
        property var attendees: []
        property var rooms: []
        /// All options' changes (meetingOptions names) over the form's.
        property var optionChanges: ({})
        /// The event's own meeting options (Edit details), for All options.
        property var eventOptions: null
        property var richState: ({})
        function refreshRich() { richState = JSON.parse(rich.state(description.cursorPosition) || "{}") }
        function reset(t, s, e) {
            const th = t.type === "Townhall"
            const big = th && t.large !== false
            template = t; start = s; end = e; access = t.access || "Organization"; registration = !!t.registration; greenRoom = t.greenRoom !== undefined ? t.greenRoom : th
            mic = !big; camera = !big; react = true; chat = true; qna = true; capacity = big ? 3000 : th ? 1000 : 0; large = big; attendeeView = "Off"
            open = [true, false, false, false]; nameField.text = "New event"; description.text = ""; contentY = 0
            mode = "new"; sourceId = ""; sessionId = ""; promo = ""; discoverable = false; zone = root.localZone; zoneOpen = false
            team = []; presenters = []; attendees = []; rooms = []; optionChanges = ({}); eventOptions = null
        }
        // An event's or template's fields into the form (Edit details,
        // Duplicate, Schedule, Edit template).
        function fill(d) {
            const type = d.type === "Townhall" ? root.templates[2] : root.templates[0]
            const s = d.start ? new Date(d.start) : start, e = d.end ? new Date(d.end) : end
            reset(type, s, e)
            nameField.text = d.title || ""
            if (d.description) rich.importHtml(d.description, theme.brand)
            access = d.access === "Public" ? "Public" : d.inviteOnly ? "Private" : "Organization"
            registration = !!d.registration; discoverable = !!d.discoverable; promo = d.promoImage || ""
            zone = d.timeZone || root.localZone
            team = d.team || []; presenters = d.presenters || []; attendees = d.attendees || []; rooms = d.rooms || []
            sessionId = d.sessionId || ""
            const o = d.meetingOptions
            eventOptions = o || null
            if (o) {
                const r = String(o.attendeeRestrictions || "UnRestricted")
                mic = r.indexOf("DisableAudio") < 0 && r !== "DisableAv"; camera = r.indexOf("DisableVideo") < 0 && r !== "DisableAv"
                if (o.allowTeamsMeetingReactions !== undefined) react = !!o.allowTeamsMeetingReactions
                if (o.allowMeetingChat) chat = o.allowMeetingChat !== "Disabled"
                if (o.yammerQNAEnabled !== undefined) qna = !!o.yammerQNAEnabled
                if (o.stagingRoomEnabled !== undefined) greenRoom = !!o.stagingRoomEnabled
            }
            if (d.capacity) capacity = d.capacity
        }
        readonly property string title: mode === "edit" ? (nameField.text.trim() || "Edit event") : mode === "template" ? "Edit template"
            : mode === "duplicate" ? (nameField.text.trim() || "New event") : (template.formTitle || "New event")
        // The room search's slot: "yyyy-MM-dd HH:mm:ss" in the zone (Teams
        // sends the form's times in its Windows zone name).
        readonly property string windowsZone: {
            const z = zone || root.localZone
            const map = { PacificSt: "Pacific Standard Time", MountainSt: "Mountain Standard Time", CentralSt: "Central Standard Time", EasternSt: "Eastern Standard Time", GMTSt: "GMT Standard Time", WEuropeSt: "W. Europe Standard Time", UTC: "UTC" }
            return map[z] || (z.endsWith("St") ? z.slice(0, -2).replace(/([a-z])([A-Z])/g, "$1 $2") + " Standard Time" : z)
        }
        function slot(d) { return Qt.formatDateTime(d, "yyyy-MM-dd HH:mm:ss") }
        function toggle(i) { const o = open.slice(); o[i] = !o[i]; open = o }
        function setTime(d, hm) { const x = new Date(d); x.setHours(hm[0], hm[1], 0, 0); return x }
        function payload() {
            // Teams' editor writes <strong> / <em> / <u>.
            const html = description.length > 0 ? rich.exportHtml().replace(/<b>/g, "<strong>").replace(/<\/b>/g, "</strong>").replace(/<i>/g, "<em>").replace(/<\/i>/g, "</em>") : ""
            return { eventType: template.type, title: nameField.text.trim(), description: html,
                     start: start.toISOString(), end: end.toISOString(), access: access, registration: registration, greenRoom: greenRoom,
                     allowMic: mic, allowCamera: camera, reactions: react, chat: chat, qna: qna,
                     capacity: townHall ? capacity : large ? 10000 : capacity, baseExperience: !townHall && large,
                     largeAudience: townHall && large, attendeeView: attendeeView,
                     timeZone: zone, team: team, presenters: presenters, attendees: attendees, rooms: rooms,
                     meetingOptions: Object.keys(optionChanges).length ? optionChanges : null,
                     promoImage: promo, sessionId: sessionId, discoverable: discoverable }
        }
        // Save changes (Edit details) and Edit template's Save.
        function saveChanges() {
            saving = true
            if (mode === "template") {
                root.call("updateTemplate", { id: sourceId, name: templateName, templateDescription: templateDescription, event: payload() }, v => {
                    saving = false
                    if (v.error) { root.toast({ text: "Couldn't save the template. " + v.error, intent: "error" }); return }
                    root.toast({ text: "Template saved", intent: "success" }); root.page = "create"; root.loadTemplates()
                })
                return
            }
            root.call("update", Object.assign({ id: sourceId }, payload()), v => {
                saving = false
                if (v.error) { root.toast({ text: "Couldn't save the event. " + v.error, intent: "error" }); return }
                root.toast({ text: "Event updated", intent: "success" })
                root.manageData = null
                root.openEvent(Object.assign({}, root.current || {}, { id: sourceId, title: nameField.text.trim() }))
            })
        }
        readonly property var times: {
            const out = []
            for (let m = 0; m < 24 * 60; m += 30) out.push([Math.floor(m / 60), m % 60])
            return out
        }
        function timeLabel(hm) { const d = new Date(2000, 0, 1, hm[0], hm[1]); return theme.time(d) }
        Btn { x: 24; y: 32; icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.page = form.mode === "edit" ? "event" : "create"; Accessible.name: "Go back" }
        Text { x: 64; y: 34; text: form.title; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Btn { anchors.right: parent.right; anchors.rightMargin: 22; y: 32; primary: true; icon: "save-20"
              text: form.mode === "edit" ? "Save changes" : form.mode === "template" ? "Save" : "Save and continue"
              usable: nameField.text.trim().length > 0 && !form.saving
              onClicked: form.mode === "edit" || form.mode === "template" ? form.saveChanges() : saveDialog.open() }
        Column {
            id: formCol
            x: 20; y: 88; width: form.width - 44
            spacing: 16
            // The welcome card.
            Rectangle {
                visible: root.welcome && form.mode === "new"
                x: 2; width: parent.width; height: 162; radius: 16
                color: theme.pick("#F5F5F5", "#292929", "#000000"); border.color: theme.divider; border.width: 1
                Text { x: 25; y: 30; text: "Welcome! Let's walk through creating your first event."; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Btn { x: parent.width - 57; y: 25; icon: "dismiss-20"; text: ""; pad: 6; onClicked: root.welcome = false; Accessible.name: "Dismiss welcome banner" }
                Row {
                    x: 25; y: 73; spacing: 16
                    Repeater {
                        model: [["webp/128/editor-l-standard-128x128.webp", "1. Fill out details", "Add the who, where, when and decide on the kind of experience you want."],
                                ["webp/128/expressions-l-standard-128x128.webp", "2. Personalize event page", "Add branding and get a preview of exactly what attendees will see."],
                                ["webp/128/share-l-standard-128x128.webp", "3. Spread the word", "Help people discover your event by sharing to the Events app and more."]]
                        Item {
                            required property var modelData
                            width: (formCol.width - 50 - 32) / 3; height: 64
                            Image { width: 64; height: 64; source: root.cdn + modelData[0]; sourceSize: Qt.size(128, 128); asynchronous: true }
                            Text { x: 80; width: parent.width - 80; text: modelData[1]; font.family: theme.font; font.pixelSize: 16; color: theme.text }
                            Text { x: 80; y: 30; width: parent.width - 80; text: modelData[2]; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                        }
                    }
                }
            }
            // 1. Add event details.
            Section {
                index: 0; title: "Add event details"
                Column {
                    width: parent.width; spacing: 0
                    Item { width: 1; height: 22 }
                    Row { spacing: 2
                        Label { text: "Name" }
                        Text { text: "*"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.redForeground3 } }
                    Item { width: 1; height: 12 }
                    Rectangle {
                        width: parent.width; height: 40; radius: 4; color: theme.input; border.color: nameField.activeFocus ? theme.brand : theme.stroke; border.width: 1
                        TextInput { id: nameField; x: 19; width: parent.width - 38; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 16; color: theme.text; clip: true; selectByMouse: true; Accessible.name: "Name" }
                    }
                    Item { width: 1; height: 24 }
                    Row {
                        spacing: 16
                        readonly property real w: (parent.width - 48 - 48) / 4
                        enabled: form.mode !== "template"
                        opacity: enabled ? 1 : 0.5
                        Column { spacing: 12
                            Label { text: "Start date" }
                            DatePickerField { width: parent.parent.w; height: 32; format: theme.regional.shortDate; date: form.start; onPicked: d => { const len = form.end - form.start; const s = new Date(d); s.setHours(form.start.getHours(), form.start.getMinutes()); form.start = s; form.end = new Date(s.getTime() + len) } } }
                        Column { spacing: 12
                            Label { text: "Start time" }
                            Dropdown { width: parent.parent.w; height: 32; label: theme.time(form.start); accessibleName: "Start time"
                                       options: form.times.map(t => [t[0] + ":" + t[1], form.timeLabel(t)])
                                       onPicked: c => { const len = form.end - form.start; form.start = form.setTime(form.start, c.split(":").map(Number)); form.end = new Date(form.start.getTime() + len) } } }
                        Column { spacing: 12
                            Label { text: "End date" }
                            DatePickerField { width: parent.parent.w; height: 32; format: theme.regional.shortDate; date: form.end; minDate: form.start; onPicked: d => { const e = new Date(d); e.setHours(form.end.getHours(), form.end.getMinutes()); form.end = e } } }
                        Column { spacing: 12
                            Label { text: "End time" }
                            Dropdown { width: parent.parent.w; height: 32; label: theme.time(form.end); accessibleName: "End time"
                                       options: form.times.map(t => [t[0] + ":" + t[1], form.timeLabel(t)])
                                       onPicked: c => form.end = form.setTime(form.end, c.split(":").map(Number)) } }
                        // The time zone toggle (32 x 32, a 20 px globe in brand,
                        // #F0F0F0 while the Time zone row shows).
                        Item {
                            width: 32; height: 64
                            Rectangle {
                                y: 32; width: 32; height: 32; radius: 4
                                color: form.zoneOpen ? theme.pick("#F0F0F0", "#3D3D3D", "#000000") : hovered2.hovered ? theme.hover : "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "globe-20"; size: 20; color: theme.brand }
                                ToolTip.visible: hovered2.hovered; ToolTip.text: "Time zone"
                                HoverHandler { id: hovered2; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: form.zoneOpen = !form.zoneOpen }
                                Accessible.role: Accessible.Button; Accessible.name: "Time zone"
                            }
                        }
                    }
                    // Time zone (Teams' list of 140, "(UTC-08:00) Pacific Time (US &
                    // Canada)"), the form's full width.
                    Column {
                        visible: form.zoneOpen
                        width: parent.width; spacing: 8
                        Item { width: 1; height: 4 }
                        Label { text: "Time zone" }
                        Dropdown {
                            width: parent.width; height: 32; accessibleName: "Time zone"
                            options: root.zones
                            label: (root.zones.find(z => z[0] === (form.zone || root.localZone)) || ["", form.zone])[1]
                            onPicked: k => form.zone = k
                        }
                    }
                    Item { width: 1; height: 22 }
                    Label { text: "Location" }
                    Item { width: 1; height: 8 }
                    // Location: the Teams Online Meeting chip, the rooms' chips (a
                    // 20 px initials disc, the name, a dismiss) and Add a room
                    // (Teams' room search for the event's time); Room options
                    // beside it once there's a room.
                    Item {
                        width: parent.width; height: 34
                        Rectangle {
                            id: locBox
                            width: parent.width - (form.rooms.length ? 149 : 0); height: 34; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                            Row {
                                id: locRow
                                x: 13; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Rectangle {
                                    height: 20; radius: 10; width: chipRow.implicitWidth + 12
                                    color: theme.brandTint
                                    Row { id: chipRow; x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                        Rectangle { width: 20; height: 20; radius: 10; color: theme.brandFill
                                            FluentIcon { anchors.centerIn: parent; name: "video-16"; size: 12; color: theme.textOnBrand } }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Teams Online Meeting"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1 } }
                                }
                                Repeater {
                                    model: form.rooms
                                    Rectangle {
                                        id: roomChip
                                        required property var modelData
                                        required property int index
                                        height: 20; radius: 10; width: rcRow.implicitWidth + 10; color: theme.pick("#F5F5F5", "#292929", "#000000")
                                        Row { id: rcRow; x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                            Avatar { size: 16; name: roomChip.modelData.name; photoId: ""; anchors.verticalCenter: parent.verticalCenter }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: roomChip.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                            FluentIcon { name: "dismiss-12"; size: 12; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter
                                                TapHandler { onTapped: { const a = form.rooms.slice(); a.splice(roomChip.index, 1); form.rooms = a } }
                                                Accessible.role: Accessible.Button; Accessible.name: "Remove " + roomChip.modelData.name } }
                                    }
                                }
                            }
                            EventPeoplePicker {
                                id: roomPicker
                                kind: "rooms"; chips: false; filled: false; bare: true
                                x: locRow.x + locRow.width + 4; width: locBox.width - x - 4; height: 30
                                anchors.verticalCenter: parent.verticalCenter
                                placeholder: "Add a room"
                                picked: form.rooms
                                start: form.slot(form.start); end: form.slot(form.end); zone: form.windowsZone
                                onChanged: list => form.rooms = list
                            }
                        }
                        Btn {
                            visible: form.rooms.length > 0
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            icon: "door-20"; text: "Room options"; onClicked: roomOptions.open()
                        }
                    }
                    Item { width: 1; height: 18 }
                    Label { text: "Description" }
                    Item { width: 1; height: 12 }
                    // The description editor (Teams' Formatting toolbar: Bold, Italic,
                    // Underline | Text highlight color, Font color, Font size, Clear
                    // all formatting | Decrease indent, Increase indent, Bulleted
                    // list, Numbered list | Insert link; 32 px buttons).
                    Rectangle {
                        width: parent.width; height: 137; radius: 6; color: theme.input; border.color: theme.divider; border.width: 1
                        FormatBar {
                            id: descBar
                            x: -6; y: -9; width: parent.width + 6; tierWidth: 640
                            discard: false
                            custom: [[{ k: "bold", icon: "fmt-bold", label: "Bold", on: !!form.richState.bold }, { k: "italic", icon: "fmt-italic", label: "Italic", on: !!form.richState.italic },
                                      { k: "underline", icon: "fmt-underline", label: "Underline", on: !!form.richState.underline }],
                                     [{ k: "highlight", icon: "fmt-highlight", label: "Text highlight color", popup: true }, { k: "color", icon: "fmt-font-color", label: "Font color", popup: true },
                                      { k: "size", icon: "fmt-font-size", label: "Font size", popup: true }, { k: "clear", icon: "fmt-clear-format", label: "Clear all formatting" }],
                                     [{ k: "outdent", icon: "fmt-outdent", label: "Decrease indent" }, { k: "indent", icon: "fmt-indent", label: "Increase indent" },
                                      { k: "ul", icon: "fmt-bullets", label: "Bulleted list", on: form.richState.list === "ul" }, { k: "ol", icon: "fmt-numbers", label: "Numbered list", on: form.richState.list === "ol" }],
                                     [{ k: "link", icon: "fmt-link", label: "Insert link", popup: true }]]
                            st: form.richState
                            selectedText: description.selectedText
                            onCommand: (op, arg) => { rich.apply(description.selectionStart, description.selectionEnd, op, arg || ""); description.forceActiveFocus(); form.refreshRich() }
                            Accessible.name: "Formatting"
                        }
                        Flickable {
                            x: 13; y: 40; width: parent.width - 26; height: parent.height - 46
                            contentHeight: description.contentHeight; clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: description
                                width: parent.width
                                textFormat: TextEdit.RichText
                                wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true
                                selectionColor: theme.selectionFill; selectedTextColor: theme.text
                                onCursorPositionChanged: form.refreshRich()
                                RichText { id: rich }
                                Text { visible: description.length === 0 && !description.activeFocus; text: "Add a description to share with attendees"; font: description.font; color: theme.textSecondary }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: "Description"
                            }
                        }
                    }
                }
            }
            // 2. Who's planning the event?
            Section {
                index: 1; title: "Who's planning the event?"
                Column {
                    width: parent.width
                    Item { width: 1; height: 16 }
                    Label { text: "Send invites as" }
                    Item { width: 1; height: 12 }
                    Rectangle { width: parent.width; height: 32; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: backend.userName + " on behalf of " + (nameField.text.trim() || "New event"); font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                    Text { text: "Invites sent from Event mailbox. Co-organizers have full access to manage the event."; font.family: theme.font; font.pixelSize: 12; color: theme.text; height: 16 }
                    Item { width: 1; height: 16 }
                    Label { text: "Organizers" }
                    Item { width: 1; height: 10 }
                    Rectangle {
                        height: 32; radius: 16; width: orgRow.implicitWidth + 10; color: theme.pick("#F5F5F5", "#292929", "#000000")
                        Row { id: orgRow; x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Avatar { size: 28; name: backend.userName; photoId: backend.userMri }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: backend.userName; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong } }
                    }
                    Item { width: 1; height: 16 }
                    Label { text: "Co-organizers" }
                    Item { width: 1; height: 10 }
                    EventPeoplePicker {
                        id: teamPicker
                        width: parent.width; kind: "team"; placeholder: "Add people to help organize the event"
                        picked: form.team; onChanged: list => form.team = list
                    }
                    Text { text: "They'll receive invites when you save the event."; font.family: theme.font; font.pixelSize: 12; color: theme.text; height: 18; verticalAlignment: Text.AlignBottom }
                    Item { width: 1; height: 16 }
                    Label { text: "Presenters" }
                    Item { width: 1; height: 10 }
                    EventPeoplePicker {
                        id: presenterPicker
                        width: parent.width; kind: "presenters"; placeholder: "Add people to speak at the event"
                        picked: form.presenters; onChanged: list => form.presenters = list
                    }
                    Text { text: "They'll receive invites when you save the event."; font.family: theme.font; font.pixelSize: 12; color: theme.text; height: 18; verticalAlignment: Text.AlignBottom }
                    Item { width: 1; height: 16 }
                }
            }
            // 3. Who can attend?
            Section {
                index: 2; title: "Who can attend?"
                summary: (form.access === "Public" ? "Public" : form.access === "Private" ? "Specific people and groups" : "Your organization") + "     Registration " + (form.registration ? "On" : "Off")
                Column {
                    width: parent.width
                    Item { width: 1; height: 26 }
                    Row {
                        spacing: 16
                        Repeater {
                            model: [["Public", "Public", "Anyone can view the event page, register, or join the event.", "globe-20"],
                                    ["Organization", "Your organization", "Anyone in your org can view the event page, register, or join the event.", "building-20"],
                                    ["Private", "Specific people and groups", "Only people and groups you choose from your org can view the event page and join the event.", "people-20"]]
                            Item {
                                id: opt
                                required property var modelData
                                readonly property bool chosen: form.access === modelData[0]
                                width: (formCol.width - 50 - 32) / 3; height: 114
                                FluentSurface { anchors.fill: parent; depth: 2; radius: 12; color: theme.surface; borderColor: opt.chosen ? theme.brand : theme.stroke }
                                Rectangle { x: 17; y: 17; width: 36; height: 36; radius: 18; color: opt.chosen ? theme.brandTint : theme.pick("#F5F5F5", "#292929", "#000000")
                                    FluentIcon { anchors.centerIn: parent; name: opt.modelData[3]; size: 17; color: opt.chosen ? theme.brand : theme.textStrong } }
                                Text { x: 65; y: 17; width: parent.width - 102; text: opt.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                Text { x: 65; y: 39; width: parent.width - 102; text: opt.modelData[2]; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                                Rectangle { x: parent.width - 37; y: 18; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1; border.color: opt.chosen ? theme.brand : theme.textSecondary
                                    Rectangle { visible: opt.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand } }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: form.access = opt.modelData[0] }
                                Accessible.role: Accessible.RadioButton; Accessible.name: opt.modelData[1]; Accessible.checked: opt.chosen
                            }
                        }
                    }
                    Item { width: 1; height: 24 }
                    // Invite people to attend (Optional): people and groups who get
                    // the invitation when the event is published.
                    Label { text: "Invite people to attend (Optional)" }
                    Item { width: 1; height: 16 }
                    EventPeoplePicker {
                        id: attendeePicker
                        width: parent.width; kind: "attendees"
                        placeholder: form.access === "Private" ? "Add people and groups who can attend" : "Add people and groups who will receive email invites"
                        picked: form.attendees; onChanged: list => form.attendees = list
                    }
                    Text {
                        height: 18; verticalAlignment: Text.AlignBottom; textFormat: Text.StyledText
                        text: "They'll be invited when the event is published. Customize your invite preferences in the <b>People &amp; emails</b> tab."
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    Item { width: 1; height: 28 }
                    Item {
                        width: parent.width; height: 40
                        Text { text: "Turn on registration?"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 24; width: parent.width - 80; elide: Text.ElideRight; text: "Attendees will need to register before they can view all event details."; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                        SettingsParts.Toggle { anchors.right: parent.right; anchors.rightMargin: 8; y: 8; stateLabel: false; on: form.registration; accessibleName: "Turn on registration?"; onToggled: v => form.registration = v }
                    }
                    Item { width: 1; height: 12 }
                }
            }
            // 4. Set up experience and options.
            Section {
                index: 3; title: "Set up experience and options"
                summary: form.townHall ? (form.large ? "Optimize for large audience · " : "") + Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) + " attendees"
                    : (form.large ? "10,000" : form.capacity ? Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) : "1,000") + " attendees"
                Column {
                    width: parent.width
                    Item { width: 1; height: 16 }
                    Label { text: "Set your max event capacity" }
                    Text { y: 4; text: "We'll use this info to suggest the best settings for your audience"; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong; height: 18 }
                    Item { width: 1; height: 12 }
                    Row {
                        spacing: 24; height: 36
                        Dropdown {
                            width: 250; height: 32; anchors.verticalCenter: parent.verticalCenter; accessibleName: "Set your max event capacity"
                            label: form.townHall ? (options.find(o => o[0] === String(form.capacity)) || options[1])[1]
                                : (form.large ? "10,000" : form.capacity ? Number(form.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) : "1,000") + " attendees"
                            // A town hall offers 1,000, 3,000 and the view-only 10,000
                            // (measured 2026-11-17).
                            options: form.townHall ? [["1000", "1,000 attendees"], ["3000", "3,000 attendees"], ["10000", "10,000 attendees (View only, with Q&A)"]]
                                : [["0", "1,000 attendees"]].concat(((root.features || {}).eventCapacity || { eventCapacityOptions: [] }).eventCapacityOptions
                                .filter(o => o.isAvailableForUserLicense && !o.isBaseEventExperience).map(o => [String(o.capacity), Number(o.capacity).toLocaleString(Qt.locale("en_US"), "f", 0) + " attendees"]))
                            onPicked: c => { form.capacity = Number(c); if (!form.townHall) form.large = false }
                        }
                        Row {
                            spacing: 8; anchors.verticalCenter: parent.verticalCenter
                            SettingsParts.Toggle { stateLabel: false; on: form.large; accessibleName: "Optimize for large audience"
                                onToggled: v => { form.large = v; if (form.townHall) { form.capacity = v ? 3000 : 1000; form.mic = !v; form.camera = !v } } }
                            Text { text: "Optimize for large audience"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                    }
                    Item { width: 1; height: 16 }
                    Label { text: "Attendee participation" }
                    Item { width: 1; height: 16 }
                    Grid {
                        columns: 3; spacing: 8
                        Repeater {
                            // A streaming town hall: Mic and Camera unavailable, then Q&A;
                            // an interactive one: Mic, Camera, React, "During event" (chat), Q&A.
                            model: form.townHall && form.large
                                ? [["mic", "Mic", "mic-20", "mic-off-20", true], ["camera", "Camera", "video-20", "video-off-20", true], ["qna", "Q&A", "chat-bubbles-question-20", "chat-bubbles-question-20"]]
                                : [["mic", "Mic", "mic-20", "mic-off-20"], ["camera", "Camera", "video-20", "video-off-20"], ["react", "React", "emoji-20", "emoji-20"],
                                   ["chat", form.template.chatLabel || (form.townHall ? "During event" : "Chat"), "chat-20", "chat-bubbles-off-20"], ["qna", "Q&A", "chat-bubbles-question-20", "chat-bubbles-question-20"]]
                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool on: form[modelData[0]]
                                // Unavailable at this capacity (Teams' tooltip: "Selected capacity
                                // does not support this engagement feature.").
                                readonly property bool unavailable: !!modelData[4]
                                opacity: unavailable ? 0.3 : 1
                                ToolTip.visible: unavailable && tileHover.hovered; ToolTip.text: "Selected capacity does not support this engagement feature."
                                width: 132; height: 75; radius: 12; color: theme.surface; border.color: theme.divider; border.width: 1
                                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 16; name: tile.on ? tile.modelData[2] : tile.modelData[3]; size: 20; color: tile.on ? theme.brand : theme.textSecondary }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 41.5; text: tile.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: tile.on ? theme.text : theme.textSecondary }
                                HoverHandler { id: tileHover; cursorShape: tile.unavailable ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                TapHandler { enabled: !tile.unavailable; onTapped: form[tile.modelData[0]] = !tile.on }
                                Accessible.role: Accessible.CheckBox; Accessible.name: tile.modelData[1]; Accessible.checked: tile.on
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                    // A town hall's "Manage what attendees see" (Off, On, On with
                    // preview): who and what attendees see is brought on screen.
                    Item {
                        visible: form.townHall; width: 412; height: visible ? 80 : 0
                        Text { text: "Manage what attendees see"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 26; text: "Control the layout, content, and people seen on screen."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Dropdown {
                            x: 1; y: 49; width: 410; height: 30; accessibleName: "Manage what attendees see"
                            options: [["Off", "Off"], ["On", "On"], ["Preview", "On with preview"]]
                            label: (options.find(o => o[0] === form.attendeeView) || options[0])[1]
                            onPicked: v => form.attendeeView = v
                        }
                    }
                    Item { visible: form.townHall; width: 1; height: visible ? 16 : 0 }
                    Item {
                        width: 412; height: 68
                        Text { text: "Enable green room"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { y: 28; width: 334; wrapMode: Text.Wrap; text: "Check audio, video, and screen setup before event starts."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        SettingsParts.Toggle { x: 352; y: 8; stateLabel: false; on: form.greenRoom; accessibleName: "Enable green room"; onToggled: v => form.greenRoom = v }
                    }
                    // Room under the preview, then All options (the event's
                    // meeting options dialog) and Manage apps (the event meeting's
                    // apps; "Available after you save." until it exists).
                    Item { width: 1; height: Math.max(16, 520 - 330 - (form.townHall ? 96 : 0)) }
                    Row {
                        spacing: 12
                        Btn { outlined: true; text: "All options"; onClicked: root.openAllOptions() }
                        Btn {
                            outlined: true; text: "Manage apps"
                            usable: form.mode === "edit" && !!(root.current && root.current.thread_id)
                            ToolTip.visible: !usable && maHover.hovered; ToolTip.text: "Available after you save."
                            HoverHandler { id: maHover }
                            onClicked: root.openMeetingDetails(root.current.thread_id, root.current.title)
                        }
                    }
                    Item { width: 1; height: 16 }
                }
                // The stage preview on the right, beside the participation tiles
                // (what attendees' meeting window will look like).
                EventStagePreview {
                    id: stagePreview
                    visible: form.visible && form.open[3] && parent.width > 1000
                    z: 1
                    x: parent.width - width; y: 120
                    mic: form.mic; camera: form.camera; react: form.react; chat: form.chat; qna: form.qna
                    broadcast: form.townHall && form.large
                }
            }
        }
    }
    component Label: Text { font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; height: 20 }
    // One of the form's cards: its header toggles it.
    component Section: Item {
        id: sec
        property int index
        property string title
        property string summary: ""
        default property alias content: body.data
        width: formCol.width; height: form.open[index] ? body.y + body.childrenRect.height + 25 : 82
        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
        Text { x: 25; y: 27; text: sec.title; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        Text { visible: !!sec.summary; anchors.right: parent.right; anchors.rightMargin: 57; y: 33; text: sec.summary; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        FluentIcon { x: parent.width - 51; y: 31; name: form.open[sec.index] ? "chevron-up-20" : "chevron-down-20"; size: 20; color: theme.textStrong }
        Item {
            x: 25; y: 25; width: parent.width - 50; height: 32
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: form.toggle(sec.index) }
            Accessible.role: Accessible.Button; Accessible.name: sec.title
        }
        Item { id: body; visible: form.open[sec.index]; x: 25; y: 57; width: parent.width - 50; height: childrenRect.height }
    }

    // "Save as a draft and continue?" (save-event-dialog), 600 wide.
    Popup {
        id: saveDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 600
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property bool pin: true
        onOpened: pin = !root.pinned
        contentItem: Column {
            spacing: 0
            Text { text: "Save as a draft and continue?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 28 }
            Item { width: 1; height: 8 }
            Text { text: "Attendees can't view the event until after you publish it."; font.family: theme.font; font.pixelSize: 14; color: theme.text; height: 20 }
            Item { width: 1; height: 15 }
            // "Invites will be sent to": Organizers n (Can view and edit) and
            // Presenters n (Can view), 268 x 111 #FAFAFA radius 8 cards, 15
            // apart, their 24 px avatars (measured 2026-11-18).
            Column {
                visible: form.team.length + form.presenters.length > 0
                spacing: 10; height: visible ? implicitHeight + 15 : 0
                Text { text: "Invites will be sent to"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
                Row {
                    spacing: 15
                    Repeater {
                        model: [["Organizers", form.team, "Can view and edit", "edit-16"], ["Presenters", form.presenters, "Can view", "eye-16"]].filter(m => m[1].length > 0)
                        Rectangle {
                            required property var modelData
                            width: 268; height: 111; radius: 8; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                            Text { x: 12; y: 12; text: modelData[0] + " " + modelData[1].length; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                            Row { x: 12; y: 40; spacing: 4
                                FluentIcon { name: modelData[3]; size: 14; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData[2]; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                            Row { x: 12; y: 75; spacing: 4
                                Repeater { model: modelData[1].slice(0, 9); Avatar { required property var modelData; size: 24; name: modelData.name; photoId: modelData.mri || "" } } }
                        }
                    }
                }
            }
            Text { text: "These settings will be locked after saving"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                Repeater {
                    model: [["people-20", "Invites from:", "Event mailbox"], ["filter-20", "Optimize for large audience:", form.large ? "On" : "Off"]]
                    Rectangle {
                        required property var modelData
                        height: 32; radius: 16; width: pr.implicitWidth + 24; color: theme.surface; border.color: theme.divider; border.width: 1
                        Row { id: pr; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            FluentIcon { name: modelData[0]; size: 20; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    }
                }
            }
            Item { width: 1; height: 12 }
            Rectangle {
                visible: !root.pinned
                width: 550; height: 42; radius: 4; color: theme.pick("#FAFAFA", "#1F1F1F", "#000000"); border.color: theme.divider; border.width: 1
                Rectangle { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 2; color: "#5B5FC7"
                    FluentIcon { anchors.centerIn: parent; name: "calendar-add-20"; size: 14; color: "white" } }
                Text { x: 37; anchors.verticalCenter: parent.verticalCenter; text: "Get back to events you're organizing faster"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Rectangle { width: 16; height: 16; radius: 2; anchors.verticalCenter: parent.verticalCenter
                        color: saveDialog.pin ? theme.brandFill : "transparent"; border.width: 1; border.color: saveDialog.pin ? theme.brandFill : theme.textSecondary
                        FluentIcon { visible: saveDialog.pin; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.textOnBrand } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Pin the Events app"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    TapHandler { onTapped: saveDialog.pin = !saveDialog.pin }
                }
            }
            Item { width: 1; height: 8 }
            Row {
                anchors.right: parent.right; spacing: 13
                Btn { width: 96; outlined: true; text: "Cancel"; onClicked: saveDialog.close() }
                Btn { primary: true; text: "Save and continue"; usable: !form.saving
                      onClicked: {
                          form.saving = true
                          const pinIt = !root.pinned && saveDialog.pin
                          const dup = form.mode === "duplicate"
                          root.call(dup ? "duplicate" : "create", Object.assign({ sourceId: form.sourceId }, form.payload()), v => {
                              form.saving = false
                              saveDialog.close()
                              if (v.error) { root.toast({ text: "Couldn't save the event. " + v.error, intent: "error" }); return }
                              if (pinIt) root.setPinned(true)
                              root.toast({ text: "Draft event created", intent: "success" })
                              root.manageData = null
                              if (v.card) root.openEvent(v.card); else root.openTab("manage")
                          })
                      } }
            }
        }
    }

    // ---- An event's page ----
    // Measured in Teams desktop 26304 (winpc, 2026-11-18, 1280 x 680): the
    // draft card (#F5F5F5, radius 16, 1025 wide at 155) with Publish event;
    // the title row 279 down: Go back, the title 20/28 semibold, then Edit
    // details (outlined, 121 x 31), Share (32 x 31; disabled while a draft:
    // "Event sharing is available after publishing."), More options (···:
    // Duplicate, Save as template, Cancel), a divider and Preview (a
    // switch); the tabs ("Event navigation tabs", 40 tall, 15 in): Overview,
    // People & emails, Insights, Highlights; Preview on replaces the tabs by
    // "This is a preview of what attendees will see." and shows the page as
    // attendees do (Add to calendar, no Manage apps).
    // Overview: the promo picture (646 x 215, radius 16, Edit event banner),
    // the title card (24/32 semibold, the description), Presenter cards;
    // on the right the date / location / access card with Join (split:
    // Copy join link, Copy join details; "Event isn't published yet." while
    // a draft) and the chat button (split for a webinar: Chat with
    // participants, Chat with event group), then Manage apps ("Manage or add
    // apps for your session here.").
    Flickable {
        id: eventPage
        visible: root.page === "event" && !!root.current
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: pageCol.y + pageCol.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property var ev: root.current || ({})
        readonly property bool draft: ev.state === "Draft"
        readonly property bool canceled: ev.state === "Canceled"
        readonly property bool organizer: !ev.role || ev.role === "Organizer" || ev.role === "CoOrganizer"
        readonly property real w: Math.min(1025, width - 64)
        readonly property real x0: (width - w) / 2
        readonly property var pd: root.peopleData || ({})
        readonly property string emailError: root.emailTemplateList === undefined ? "error" : ""
        readonly property var speakers: pd.presenterList || []
        Rectangle {
            id: draftCard
            visible: eventPage.draft
            x: eventPage.x0; y: 16; width: eventPage.w; height: visible ? 119 : 0; radius: 16
            color: theme.pick("#F5F5F5", "#292929", "#000000"); border.color: theme.divider; border.width: 1
            Image { x: 28; anchors.verticalCenter: parent.verticalCenter; width: 52; height: 52; source: root.cdn + "webp/128/editor-l-standard-128x128.webp"; sourceSize: Qt.size(104, 104) }
            Text { x: 85; y: 24; width: parent.width - 120; text: "This event is a draft. Publish when you’re ready to share with attendees."; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; elide: Text.ElideRight }
            Text { x: 85; y: 50; width: parent.width - 300; wrapMode: Text.Wrap; text: "Only organizers and presenters you’ve invited can view this event. Organizers have permission to make edits."; font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Btn { anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; height: 40; fontSize: 16
                  primary: true; icon: "rocket-20"; text: "Publish event"; onClicked: publishDialog.openFor(root.current) }
        }
        Item {
            id: evHead
            x: eventPage.x0; y: eventPage.draft ? 162 : 32; width: eventPage.w; height: 32
            Btn { icon: "arrow-left-20"; text: ""; pad: 6; onClicked: root.openTab(root.tab); Accessible.name: "Go back" }
            Text { x: 42; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 420; elide: Text.ElideRight; text: eventPage.ev.title || ""; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Row {
                anchors.right: parent.right; spacing: 8
                Btn { visible: eventPage.organizer && !eventPage.canceled; outlined: true; icon: "edit-20"; text: "Edit details"; onClicked: root.editEvent(eventPage.ev) }
                Btn {
                    visible: eventPage.organizer && !eventPage.canceled
                    width: 32; outlined: true; icon: "share-20"; text: ""; pad: 6; usable: !eventPage.draft
                    Accessible.name: "Share"
                    ToolTip.visible: shareHover.hovered && eventPage.draft; ToolTip.text: "Event sharing is available after publishing."
                    HoverHandler { id: shareHover }
                    onClicked: shareDialog.openFor(eventPage.ev, false)
                }
                Btn {
                    id: evMore; visible: eventPage.organizer && !eventPage.canceled
                    icon: "more-horizontal-20"; text: ""; pad: 6; Accessible.name: "More options"
                    onClicked: { evMenu.parent = evMore; evMenu.x = 0; evMenu.y = evMore.height + 4; evMenu.open() }
                }
                Rectangle { visible: root.eventTab === "overview" || root.eventTab === "highlights"; width: 1; height: 24; anchors.verticalCenter: parent.verticalCenter; color: theme.divider }
                Row {
                    visible: root.eventTab === "overview" || root.eventTab === "highlights"
                    spacing: 8; anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.eventTab === "highlights" ? "Preview as published" : "Preview"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    SettingsParts.Toggle { stateLabel: false; on: root.previewOn; accessibleName: "Preview"; onToggled: v => root.previewOn = v }
                }
            }
        }
        // The tabs, or Preview's note.
        Row {
            id: evTabs
            visible: !root.previewOn
            x: eventPage.x0; y: evHead.y + 55; height: 40
            Repeater {
                model: [["overview", "Overview"], ["people", "People & emails"], ["insights", "Insights"], ["highlights", "Highlights"]]
                Item {
                    required property var modelData
                    readonly property bool chosen: root.eventTab === modelData[0]
                    width: tabLabel.implicitWidth + 30; height: 40
                    Text { id: tabLabel; x: 15; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; font.weight: parent.chosen ? Font.DemiBold : Font.Normal; color: parent.chosen ? theme.text : theme.textStrong }
                    Rectangle { visible: parent.chosen; x: 12; width: tabLabel.implicitWidth + 6; height: 3; radius: 2; anchors.bottom: parent.bottom; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.eventTab = parent.modelData[0]; if (parent.modelData[0] === "people") root.loadPeopleTab() } }
                    Accessible.role: Accessible.PageTab; Accessible.name: modelData[1]; Accessible.selected: chosen
                }
            }
        }
        Text { visible: root.previewOn; x: eventPage.x0; y: evHead.y + 62; width: eventPage.w; horizontalAlignment: Text.AlignHCenter
               text: "This is a preview of what attendees will see."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Column {
            id: pageCol
            x: eventPage.x0; y: evHead.y + 105; width: eventPage.w
            spacing: 16
            // Overview (and Preview).
            Item {
                visible: root.eventTab === "overview" || root.previewOn
                width: parent.width; height: visible ? Math.max(leftCol.height, rightCol.height) : 0
                readonly property real leftW: Math.round(parent.width * 0.64)
                Column {
                    id: leftCol
                    width: parent.leftW; spacing: 16
                    Rectangle {
                        width: parent.width; height: 215; radius: 16; clip: true
                        color: eventPage.ev.primary_color || "#5B5FC7"
                        Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                source: { backend.emoticonsVersion; return eventPage.ev.promo_image ? backend.cardImage(eventPage.ev.promo_image) : "" } }
                        // Edit event banner (40 px round, 24 from the top right).
                        Rectangle {
                            visible: eventPage.organizer && !root.previewOn && !eventPage.canceled
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 24
                            width: 40; height: 40; radius: 20
                            color: bannerHover.hovered ? theme.menuHover : theme.surface; border.color: theme.divider; border.width: 1
                            FluentIcon { anchors.centerIn: parent; name: "edit-20"; size: 24; color: theme.textStrong }
                            HoverHandler { id: bannerHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: branding.openNow() }
                            Accessible.role: Accessible.Button; Accessible.name: "Edit event banner"
                        }
                    }
                    Item {
                        width: parent.width; height: titleCol.height + 40
                        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
                        Column {
                            id: titleCol
                            x: 20; y: 20; width: parent.width - 40; spacing: 24
                            Text { width: parent.width; wrapMode: Text.Wrap; text: eventPage.ev.title || ""; font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.text }
                            Text { visible: !!eventPage.ev.description; width: parent.width; wrapMode: Text.Wrap; textFormat: Text.RichText; text: eventPage.ev.description || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                    }
                    // Presenter cards (48 px avatar, the name 14/20 semibold).
                    Item {
                        visible: eventPage.speakers.length > 0
                        width: parent.width; height: visible ? presCol.height + 40 : 0
                        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
                        Column {
                            id: presCol
                            x: 20; y: 20; width: parent.width - 40; spacing: 20
                            Text { text: eventPage.speakers.length === 1 ? "Presenter" : "Presenters"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                            Flow {
                                width: parent.width; spacing: 12
                                Repeater {
                                    model: eventPage.speakers
                                    Rectangle {
                                        required property var modelData
                                        width: 295; height: 72; radius: 8; color: theme.surface; border.color: theme.divider; border.width: 1
                                        Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 48; name: parent.modelData.name; photoId: parent.modelData.mri || "" }
                                        Text { x: 72; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 84; elide: Text.ElideRight; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                    }
                                }
                            }
                        }
                    }
                }
                Column {
                    id: rightCol
                    x: parent.leftW + 24; width: parent.width - parent.leftW - 24; spacing: 16
                    Item {
                        width: parent.width; height: infoCol.height + 42
                        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
                        Column {
                            id: infoCol
                            x: 21; y: 21; width: parent.width - 42; spacing: 18
                            Rectangle { visible: eventPage.ev.state === "Published" && new Date(eventPage.ev.start) > new Date(); height: 22; radius: 11; width: upc.implicitWidth + 16
                                color: theme.pick("#E8EBFA", "#2F2F4A", "#000000"); border.color: theme.pick("#C5CBFA", "#444791", "#FFFFFF"); border.width: 1
                                Text { id: upc; anchors.centerIn: parent; text: "Upcoming"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brand } }
                            Rectangle { visible: eventPage.canceled; height: 24; radius: 12; width: cxl.implicitWidth + 20; color: "transparent"; border.color: theme.danger
                                Text { id: cxl; anchors.centerIn: parent; text: "Canceled"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.danger } }
                            Row { spacing: 8; width: parent.width
                                FluentIcon { name: "clock-20"; size: 20; color: theme.brand }
                                Text { width: parent.width - 28; wrapMode: Text.Wrap; text: root.whenText(eventPage.ev.start, eventPage.ev.end, true); font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                            Row { spacing: 8
                                FluentIcon { name: "location-20"; size: 20; color: theme.brand }
                                Text { text: (eventPage.ev.rooms || []).length ? eventPage.ev.rooms.join(", ") + " • Online" : "Online"; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                            Row { spacing: 8
                                FluentIcon { name: "people-20"; size: 20; color: theme.brand }
                                Text { text: eventPage.ev.access === "Public" ? "Anyone can view and join." : eventPage.ev.inviteOnly ? "Only invited attendees can view and join." : "Anyone in your org can view and join."; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                            // Preview: attendees' Add to calendar.
                            Btn { visible: root.previewOn; width: parent.width; icon: "calendar-add-20"; text: "Add to calendar"; usable: false }
                            // Join (split) and the chat button.
                            Row {
                                visible: !root.previewOn
                                width: parent.width; height: 32; spacing: 8
                                readonly property bool can: !eventPage.canceled && !eventPage.draft && !!eventPage.ev.join_url
                                readonly property bool webinar: eventPage.ev.event_type === "Webinar"
                                Rectangle {
                                    width: parent.width - (parent.webinar ? 64 : 40); height: 32; radius: 4; color: parent.can ? (joinHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#333333", "#000000")
                                    Row { anchors.centerIn: parent; anchors.horizontalCenterOffset: -12; spacing: 6
                                        FluentIcon { name: "video-20"; size: 20; color: parent.parent.parent.can ? theme.textOnBrand : theme.disabled }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Join"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.parent.parent.can ? theme.textOnBrand : theme.disabled } }
                                    Rectangle { x: parent.width - 25; y: 0; width: 1; height: 32; color: theme.pick("#FFFFFF", "#141414", "#000000"); opacity: 0.5 }
                                    FluentIcon { x: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: parent.parent.can ? theme.textOnBrand : theme.disabled }
                                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                                    ToolTip.visible: joinHover.hovered && eventPage.draft; ToolTip.text: "Event isn't published yet."
                                    TapHandler { enabled: parent.parent.can; onTapped: (e) => {
                                        if (e.position.x > parent.width - 25) { joinMenu.parent = parent; joinMenu.x = parent.width - joinMenu.implicitWidth; joinMenu.y = 36; joinMenu.open() }
                                        else root.joinEvent(eventPage.ev.join_url, eventPage.ev.title, eventPage.ev.start, eventPage.ev.end) } }
                                    Accessible.role: Accessible.Button; Accessible.name: eventPage.draft ? "Join - Event isn't published yet." : "Join"
                                }
                                Rectangle {
                                    id: chatSplit
                                    width: parent.webinar ? 56 : 32; height: 32; radius: 4; color: chatHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 1
                                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "chat-20"; size: 20; color: theme.textStrong }
                                    FluentIcon { visible: parent.parent.webinar; x: 34; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.textStrong }
                                    HoverHandler { id: chatHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: (e) => {
                                        if (chatSplit.parent.webinar && e.position.x > 32) { chatMenu.parent = chatSplit; chatMenu.x = 0; chatMenu.y = 36; chatMenu.open() }
                                        else root.openChat(eventPage.ev, false) } }
                                    Accessible.role: Accessible.Button; Accessible.name: "Chat with participants"
                                }
                            }
                        }
                    }
                    // Manage apps.
                    Item {
                        visible: !root.previewOn && eventPage.organizer
                        width: parent.width; height: visible ? 104 : 0
                        Rectangle { anchors.fill: parent; radius: 16; color: theme.pick("#F5F5F5", "#292929", "#000000") }
                        Text { x: 21; y: 20; text: "Manage apps"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Text {
                            x: 21; y: 54; width: parent.width - 42; wrapMode: Text.Wrap; textFormat: Text.StyledText
                            text: "Manage or add apps for your session <a href='here'>here</a>."; linkColor: theme.brandForeground1
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            onLinkActivated: root.openMeetingDetails(eventPage.ev.join_url || "", eventPage.ev.start || "")
                        }
                    }
                }
            }
            // People & emails.
            Column {
                visible: root.eventTab === "people" && !root.previewOn
                width: parent.width; spacing: 16
                PeopleSection {
                    title: "Email notifications"; key: "emails"
                    Column {
                        width: parent.width; spacing: 0
                        Item {
                            width: parent.width; height: 40
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Attendees"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                SettingsParts.Toggle { stateLabel: false; on: !eventPage.pd.disableAttendeeEmails; enabled: eventPage.draft; opacity: enabled ? 1 : 0.5
                                    accessibleName: eventPage.pd.disableAttendeeEmails ? "Turn on all attendee notifications" : "Turn off all attendee notifications"
                                    onToggled: v => root.call("theme", { id: eventPage.ev.id }, th => {
                                        const cp = Object.assign({}, th.communicationProperties || {}, { disableAttendeeEmails: !v })
                                        root.call("patch", { id: eventPage.ev.id, body: { communicationProperties: cp } }, r => { if (!r.error) root.peopleData = Object.assign({}, root.peopleData, { disableAttendeeEmails: !v }) }) }) }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Send attendee emails"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text } }
                        }
                        // Teams' rows: the event's templates (GET emailtemplates)
                        // of these types in this order; Edit only with your
                        // events policy's email editing; the reminder's
                        // timing opens Send event reminder; the switch
                        // changes only a draft, and off greys the table.
                        Text { visible: !!eventPage.emailError; text: "Error loading email templates"; font.family: theme.font; font.pixelSize: 14; color: theme.danger; height: 32; verticalAlignment: Text.AlignVCenter }
                        PeopleTable {
                            visible: !eventPage.emailError
                            enabled: !eventPage.pd.disableAttendeeEmails
                            opacity: enabled ? 1 : 0.5
                            headers: ["Email", "When it's sent", "Actions"]
                            rows: (root.emailTemplateList || []).map(t => [root.emailLabel(t.templateType), root.emailTiming(t), t.templateId, t.templateType])
                            actions: true
                        }
                        Text { visible: !eventPage.emailError && !!root.emailTemplateList && root.emailTemplateList.length === 0; text: "No attendee notifications configured"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary; height: 44; verticalAlignment: Text.AlignVCenter }
                    }
                }
                PeopleSection {
                    title: "Organizers (" + (eventPage.pd.organizerList || []).length + ")"; key: "organizers"
                    Column {
                        width: parent.width; spacing: 12
                        PeopleTable { headers: ["Name", "Email"]; people: eventPage.pd.organizerList || [] }
                        Btn { outlined: true; text: "Manage organizers"; onClicked: root.editEvent(eventPage.ev) }
                    }
                }
                PeopleSection {
                    title: "Presenters (" + eventPage.speakers.length + ")"; key: "presenters"
                    Column {
                        width: parent.width; spacing: 12
                        Text { visible: eventPage.speakers.length === 0; text: "No presenters added yet"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        PeopleTable { visible: eventPage.speakers.length > 0; headers: ["Name", "Email"]; people: eventPage.speakers }
                        Btn { outlined: true; text: "Manage presenters"; onClicked: root.editEvent(eventPage.ev) }
                    }
                }
                PeopleSection {
                    visible: (eventPage.pd.roomList || []).length > 0
                    title: "Location (" + (eventPage.pd.roomList || []).length + ")"; key: "location"
                    PeopleTable { headers: ["Name", "Email"]; people: eventPage.pd.roomList || [] }
                }
                PeopleSection {
                    title: "Attendees"; key: "attendees"
                    Column {
                        width: parent.width; spacing: 16
                        PeopleTable { visible: (eventPage.pd.attendeeList || []).length > 0; headers: ["Name", "Email"]; people: eventPage.pd.attendeeList || [] }
                        Column {
                            visible: (eventPage.pd.attendeeList || []).length === 0
                            width: parent.width; spacing: 16
                            Item { width: 1; height: 40 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "When attendees RSVP or register, they'll show up here."; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 128; height: 128; source: root.cdn + (theme.dark || theme.highContrast ? "v2/people-d-standard.svg" : "v2/people-l-standard.svg"); sourceSize: Qt.size(256, 256); asynchronous: true }
                            Item { width: 1; height: 40 }
                        }
                    }
                }
            }
            // Insights: "No reports yet" until the event ends.
            Column {
                visible: root.eventTab === "insights" && !root.previewOn
                width: parent.width; spacing: 8
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 537; height: 200; source: "../assets/illustrations/events-insights-empty.svg"; sourceSize: Qt.size(1074, 400) }
                Item { width: 1; height: 22 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No reports yet"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "You'll get a set of reports after the event ends."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            // Highlights: the recording bar (Recording used for highlights,
            // Download, View recap, Included content, Publish; off until the
            // event has a recording) and "No AI highlights yet".
            Column {
                visible: root.eventTab === "highlights" && !root.previewOn
                width: parent.width; spacing: 0
                Item {
                    width: parent.width; height: 40
                    Text { x: 0; anchors.verticalCenter: parent.verticalCenter; text: "Recording used for highlights:"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Rectangle { x: 200; anchors.verticalCenter: parent.verticalCenter; width: 311; height: 30; radius: 4; color: theme.bgDisabled
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "No video is selected"; font.family: theme.font; font.pixelSize: 14; color: theme.disabledStrong } }
                    Btn { x: 519; anchors.verticalCenter: parent.verticalCenter; width: 64; icon: "arrow-download-20"; text: ""; usable: false; Accessible.name: "Download" }
                    Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Btn { width: 32; icon: "video-clip-20"; text: ""; usable: false; Accessible.name: "View recap" }
                        Btn { text: "Included content"; usable: false }
                        Btn { width: 96; text: "Publish"; usable: false } }
                }
                Rectangle { width: parent.width; height: 1; color: theme.divider }
                Item { width: 1; height: 32 }
                Image { anchors.horizontalCenter: parent.horizontalCenter; width: 157; height: 128; source: root.cdn + "v2/ai-video-record-l-standard.svg"; sourceSize: Qt.size(314, 256); asynchronous: true }
                Item { width: 1; height: 24 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No AI highlights yet"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 8 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; width: 400; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: "Check back after the event has ended to generate them and share with attendees."; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
            }
        }
        MenuPopup {
            id: joinMenu
            items: [{ key: "link", label: "Copy join link", icon: "copy-20" }, { key: "details", label: "Copy join details", icon: "text-align-justify-20" }]
            onPicked: i => {
                if (items[i].key === "link") { backend.copyText(eventPage.ev.join_url); root.toast({ text: "Join link copied successfully", intent: "success" }) }
                else root.copyJoinDetails(eventPage.ev)
            }
        }
        MenuPopup {
            id: chatMenu
            items: [{ key: "chat", label: "Chat with participants", icon: "chat-20" }, { key: "crew", label: "Chat with event group", icon: "people-team-20" }]
            onPicked: i => root.openChat(eventPage.ev, items[i].key === "crew")
        }
        // ···: Duplicate, Save as template, Cancel.
        MenuPopup {
            id: evMenu
            items: [{ key: "dup", label: "Duplicate", icon: "copy-20" }, { key: "template", label: "Save as template", icon: "save-20" }, { key: "cancel", label: "Cancel", icon: "calendar-cancel-20" }]
            onPicked: i => {
                const k = items[i].key
                if (k === "dup") root.duplicateEvent(eventPage.ev)
                else if (k === "template") templateDialog.openFor(eventPage.ev)
                else cancelDialog.open()
            }
        }
    }
    function loadPeopleTab() {
        if (!current) return
        call("people", { id: current.id }, v => { if (!v.error) peopleData = v })
        emailTemplateList = null
        call("emailTemplates", { id: current.id }, v => {
            if (v.error) { emailTemplateList = undefined; return }
            const list = Array.isArray(v) ? v : (v.emailTemplates || v.value || [])
            emailTemplateList = emailOrder.map(k => list.find(t => t.templateType === k)).filter(t => !!t)
        })
        call("policy", {}, v => { if (!v.error) eventsPolicy = v })
    }
    // People & emails ▸ Email notifications (Teams 26304: the rows in this
    // order, their labels and "When it's sent").
    property var emailTemplateList: null
    property var eventsPolicy: ({})
    readonly property var emailOrder: ["AttendeeRegistration", "AttendeePendingApproval", "AttendeeCancellation", "AttendeeCancellationRequest",
        "AttendeeRegisterAfterWaitlist", "AttendeeWaitlisting", "AttendeeRejection", "EventDateTimeUpdate", "EventCancellation",
        "EventAttendeeReminder", "EventInvite", "AttendeesEventInvite", "EventRecording"]
    readonly property var emailLabels: ({ AttendeeRegistration: ["Registration confirmation", "Attendee registers"],
        AttendeePendingApproval: ["Registration pending", "Attendee registration is pending"],
        AttendeeCancellation: ["Registration cancellation", "Attendee cancels registration"],
        AttendeeCancellationRequest: ["Cancellation request", "Attendee requests cancellation"],
        AttendeeRegisterAfterWaitlist: ["Registration after waitlist", "Attendee registers after waitlist"],
        AttendeeWaitlisting: ["Waitlist confirmation", "Attendee joins waitlist for full event"],
        AttendeeRejection: ["Registration rejected", "Pending registration is rejected"],
        EventDateTimeUpdate: ["Date and time update", "Immediately"], EventCancellation: ["Event cancellation", "Immediately"],
        EventAttendeeReminder: ["Event reminder", ""], EventInvite: ["Event invite", "Event is published or updated"],
        AttendeesEventInvite: ["Attendees event invitation", "Event is published or updated"],
        EventRecording: ["Event recording available", "As soon as recording is published"] })
    function emailLabel(type) { return (emailLabels[type] || ["Email notification"])[0] }
    function emailTiming(t) {
        if (t.templateType !== "EventAttendeeReminder") return (emailLabels[t.templateType] || ["", "Unknown timing"])[1]
        const d = (t.sendTimeInterval || {}).days || 0, h = (t.sendTimeInterval || {}).hours || 0
        if (d === 1) return "1 day before event"
        if (d > 1) return d + " days before event"
        if (h === 1) return "1 hour before event starts"
        if (h > 1) return h + " hours before event"
        return "Unknown timing"
    }
    // A People & emails card (white, radius 16, its title 20/28 semibold
    // with a chevron; open by default).
    component PeopleSection: Item {
        id: ps
        property string title
        property string key
        property bool open: true
        default property alias content: psBody.data
        width: pageCol.width; height: open ? psBody.y + psBody.childrenRect.height + 24 : 92
        FluentSurface { anchors.fill: parent; depth: 2; radius: 16; color: theme.surface }
        Text { x: 24; y: 32; text: ps.title; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
        FluentIcon { x: parent.width - 44; y: 36; name: ps.open ? "chevron-up-20" : "chevron-down-20"; size: 20; color: theme.textStrong }
        Item { x: 24; y: 24; width: parent.width - 48; height: 44
               TapHandler { onTapped: ps.open = !ps.open }
               Accessible.role: Accessible.Button; Accessible.name: ps.title }
        Item { id: psBody; visible: ps.open; x: 24; y: 76; width: parent.width - 48; height: childrenRect.height }
    }
    // A People & emails table: header row (14, 32 tall) then rows 44 tall
    // with a #E0E0E0 line; a person: 28 px avatar, the name 14/20 semibold;
    // the email at 325.
    component PeopleTable: Column {
        id: pt
        property var headers: []
        property var people: []
        property var rows: []
        property bool actions: false
        width: parent ? parent.width : 400
        Item {
            width: parent.width; height: 32
            Repeater { model: pt.headers
                Text { required property var modelData; required property int index; x: 8 + index * 325; anchors.verticalCenter: parent.verticalCenter; text: modelData; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
        }
        Rectangle { width: parent.width; height: 1; color: theme.divider }
        Repeater {
            model: pt.people
            Column {
                required property var modelData
                width: pt.width
                Item {
                    width: parent.width; height: 44
                    Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 28; name: parent.parent.modelData.name; photoId: parent.parent.modelData.user_type === "Room" || parent.parent.modelData.userType === "Room" ? "" : (parent.parent.modelData.mri || "") }
                    Text { x: 51; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { x: 333; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.email; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                }
                Rectangle { width: parent.width; height: 1; color: theme.divider }
            }
        }
        Repeater {
            model: pt.rows
            Column {
                required property var modelData
                width: pt.width
                Item {
                    width: parent.width; height: 44
                    Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { visible: parent.parent.modelData[3] !== "EventAttendeeReminder"; x: 333; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    // The reminder's timing is a brand link with a clock.
                    Row {
                        visible: pt.actions && parent.parent.modelData[3] === "EventAttendeeReminder"
                        x: 333; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        FluentIcon { name: "clock-20"; size: 16; color: theme.brandForeground1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: parent.parent.parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1; anchors.verticalCenter: parent.verticalCenter }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: emailTiming.openFor(parent.parent.parent.modelData[2]) }
                        Accessible.role: Accessible.Button; Accessible.name: "Edit timing"
                    }
                    Row {
                        visible: pt.actions
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                        Btn { icon: "eye-20"; text: "Preview"; Accessible.name: "Preview email"; onClicked: emailEditor.openFor(parent.parent.parent.modelData[2], parent.parent.parent.modelData[3], true) }
                        Btn { visible: !!root.eventsPolicy.emailEditing; outlined: true; icon: "edit-20"; text: "Edit"; Accessible.name: "Edit email"; onClicked: emailEditor.openFor(parent.parent.parent.modelData[2], parent.parent.parent.modelData[3], false) }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: theme.divider }
            }
        }
    }
    // People & emails ▸ an email's Preview and Edit (Teams' email template
    // dialog, 600 wide): Edit email template with Sender's name (only with
    // registration on and more than 3,000 allowed attendees), Sender's
    // email, Email subject *, the cover image and logo (the event's theme,
    // read-only), Email body * (the Formatting toolbar and Personalization:
    // tokens such as {{eventName}} show as read-only chips), Email footer
    // ("This is set by your IT admin."); Preview / Edit email, Cancel, Save
    // (PATCH {subject, body, senderName}). Preview draws the email with
    // sample values.
    Popup {
        id: emailEditor
        parent: Overlay.overlay
        modal: true; padding: 0
        x: (parent.width - width) / 2; y: Math.max(16, (parent.height - height) / 2)
        width: 600; height: Math.min(edCol.implicitHeight + 48, parent.height - 32)
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property string templateId: ""
        property string type: ""
        property bool preview: false
        property bool saving: false
        property bool subjectTouched: false
        property var t: null
        property var th: ({})
        property var keyOf: ({})
        readonly property bool editable: !!root.eventsPolicy.emailEditing
        readonly property string status: t ? (t.adO4867893_IsBodyEditableStatusCode || "None") : "None"
        readonly property bool bodyEditable: status !== "BodyNotEditable" && status !== "Indeterminate"
        readonly property bool senderEditable: !!(root.current && root.current.registration) && ((root.features && root.features.eventCapacity && root.features.eventCapacity.allowedAttendeeCount) || 0) > 3000
        readonly property var labels: ({ eventName: "Event Name", dateTime: "Event Date Time", eventDateTimeRange: "Event Date Time", eventDescription: "Event Description",
                                         eventOrganization: "Organization Name", eventOrganizationName: "Organization Name", eventOrganizerName: "Organizer Name",
                                         firstName: "Attendee First Name", lastName: "Attendee Last Name", eventInviteCard: "Event Invite Card" })
        readonly property var tokenMenu: (type === "EventInvite" || type === "AttendeesEventInvite") ? ["eventName", "dateTime", "eventDescription", "eventOrganization", "eventInviteCard"]
                                       : type === "EventRecording" ? ["eventName", "eventOrganization", "eventInviteCard"]
                                       : ["eventName", "dateTime", "eventOrganizerName", "firstName", "lastName", "eventInviteCard"]
        function chip(key) {
            const label = labels[key] || key
            const k = Object.assign({}, keyOf); k[label] = key; keyOf = k
            return "<span style=\"background-color:" + theme.pick("#FAFAFA", "#292929", "#000000") + ";\">⁠" + label + "⁠</span>"
        }
        // The service's HTML is indented: its spaces aren't text.
        function toEditor(html) { return (html || "").replace(/>\s+</g, "><").replace(/[ \t\r\n]{2,}/g, " ").replace(/\{\{\s*([A-Za-z]+)\s*\}\}/g, (m, k) => chip(k)) }
        // Tokens back to {{key}}, without the chip's shading.
        function fromEditor(html) {
            const shade = theme.pick("#FAFAFA", "#292929", "#000000")
            return html.split("background-color:" + shade + ";").join("").replace(/⁠([^⁠]*)⁠/g, (m, l) => "{{" + (keyOf[l] || l) + "}}")
        }
        function sample(html) {
            const ev = root.current || {}
            const org = ((root.peopleData || {}).organizerList || [])[0] || {}
            const when = ev.start ? new Date(Date.parse(ev.start)).toLocaleString(Qt.locale(), "dddd, MMMM d, yyyy h:mm AP") + " - " + new Date(Date.parse(ev.end)).toLocaleTimeString(Qt.locale(), "h:mm AP") : ""
            const tenant = ((t && t.footer) || "").replace(/<[^>]*>/g, " ").trim().split(/ This event| This /)[0]
            const v = { eventName: ev.title || "", dateTime: when, eventDateTimeRange: when, eventDescription: (ev.description || "").replace(/<[^>]*>/g, ""),
                        eventOrganizerName: org.name || "", eventOrganization: tenant, eventOrganizationName: tenant, firstName: "Attendee First Name", lastName: "Attendee Last Name", eventInviteCard: "" }
            return (html || "").replace(/\{\{\s*([A-Za-z]+)\s*\}\}/g, (m, k) => "<span style=\"background-color:#FDF6E3;\">" + (v[k] !== undefined ? v[k] : k) + "</span>")
        }
        function openFor(id, kind, asPreview) {
            templateId = id; type = kind; preview = asPreview; saving = false; subjectTouched = false; t = null; keyOf = ({})
            edSubject.text = ""; edSender.text = ""; edBody.text = ""
            open()
            root.call("theme", { id: root.current.id }, v => { if (!v.error) th = Object.assign({}, v, { promoImage: v.promoImage || root.current.promo_image || "" }) })
            root.call("emailTemplate", { id: root.current.id, templateId: id }, v => {
                if (v.error) { t = { error: v.error }; return }
                t = v
                edSubject.text = v.subject || ""; edSender.text = v.senderName || ""
                edBody.text = ""; edRich.importHtml(toEditor(v.body || ""), theme.text)
            })
        }
        function bodyHtml() { return fromEditor(edRich.exportHtml()) }
        readonly property bool bodyEmpty: edBody.length === 0
        function save() {
            if (!edSubject.text.trim() || bodyEmpty || !edSender.text.trim()) { subjectTouched = true; return }
            saving = true
            root.call("saveEmailTemplate", { id: root.current.id, templateId: templateId, template: { subject: edSubject.text, body: bodyHtml(), senderName: edSender.text } }, v => {
                saving = false
                console.warn("EVENTS email saved", JSON.stringify(v).slice(0, 300))
                // Teams keeps the dialog open when saving fails.
                if (!v.error) { emailEditor.close(); root.loadPeopleTab() }
            })
        }
        component EdLabel: Text { font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; height: 20 }
        component EdField: Rectangle {
            id: ef
            property alias text: efIn.text
            property alias input: efIn
            property string placeholder
            property bool usable: true
            height: 32; radius: 4
            color: usable ? theme.input : theme.bgDisabled
            border.color: efIn.activeFocus ? theme.brand : theme.stroke; border.width: usable ? 1 : 0
            TextInput { id: efIn; x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; enabled: ef.usable; clip: true; selectByMouse: true
                        font.family: theme.font; font.pixelSize: 14; color: ef.usable ? theme.text : theme.disabledStrong
                        Text { visible: !parent.text && !parent.activeFocus; text: ef.placeholder; font: parent.font; color: theme.textSecondary } }
        }
        contentItem: Flickable {
            contentHeight: edCol.implicitHeight + 48; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: edCol
                x: 24; y: 24; width: parent.width - 48; spacing: 12
                Item { width: parent.width; height: 28
                    Text { text: emailEditor.preview ? "Preview" : "Edit email template"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                    Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: emailEditor.close(); Accessible.name: "Close" } }
                // Teams' domain banners.
                Rectangle {
                    visible: emailEditor.status === "BodyNotEditable" || emailEditor.status === "Indeterminate"
                    width: parent.width; height: visible ? bannerText.implicitHeight + 16 : 0; radius: 4
                    color: emailEditor.status === "Indeterminate" ? theme.pick("#FDF3F4", "#3B2326", "#000000") : theme.pick("#F5F5F5", "#292929", "#000000")
                    Text { id: bannerText; x: 12; y: 8; width: parent.width - 24; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text
                           text: emailEditor.status === "Indeterminate" ? "Editing isn't available because we couldn't fetch your org's email domain for M365 notifications. Try again or check back later."
                                                                       : "Editing isn't available because your org hasn't finished setting up your email domain for M365 notifications yet. Contact your admin for help." }
                }
                Text { visible: !emailEditor.t; text: "Loading..."; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                // ---- Edit ----
                Column {
                    visible: !emailEditor.preview && !!emailEditor.t
                    width: parent.width; spacing: 12
                    Row {
                        spacing: 12
                        Column { spacing: 4; width: (edCol.width - 12) / 2
                            EdLabel { text: "Sender's name *" }
                            EdField { id: edSender; width: parent.width; usable: emailEditor.senderEditable && emailEditor.editable; input.Accessible.name: "Sender's name" } }
                        Column { spacing: 4; width: (edCol.width - 12) / 2
                            EdLabel { text: "Sender's email" }
                            EdField { width: parent.width; usable: false; text: emailEditor.t ? (emailEditor.t.senderEmail || "") : ""; input.Accessible.name: "Sender's email" } }
                    }
                    Column { width: parent.width; spacing: 4
                        EdLabel { text: "Email subject *" }
                        EdField { id: edSubject; width: parent.width; placeholder: "Enter subject"; usable: emailEditor.editable; input.Accessible.name: "Email subject"
                                  input.onActiveFocusChanged: if (!input.activeFocus) emailEditor.subjectTouched = true }
                        Text { visible: emailEditor.subjectTouched && !edSubject.text.trim(); text: "Email subject is required"; font.family: theme.font; font.pixelSize: 12; color: theme.danger } }
                    Column { width: parent.width; spacing: 4
                        EdLabel { text: "Cover image" }
                        Rectangle {
                            width: parent.width; height: Math.round(width * 0.25); radius: 4; clip: true
                            color: theme.pick("#F0F0F0", "#1F1F1F", "#000000"); border.color: theme.divider; border.width: 1
                            Image { anchors.fill: parent; anchors.margins: 1; fillMode: Image.PreserveAspectCrop; source: emailEditor.th.promoImage ? backend.cardImage(emailEditor.th.promoImage) : ""; asynchronous: true; visible: status === Image.Ready }
                            Text { anchors.centerIn: parent; visible: !emailEditor.th.promoImage; text: "No banner image"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        } }
                    Column { spacing: 4
                        EdLabel { text: "Logo" }
                        Rectangle {
                            width: 50; height: 50; radius: 4; clip: true
                            color: theme.pick("#F0F0F0", "#1F1F1F", "#000000"); border.color: theme.divider; border.width: 1
                            Image { anchors.fill: parent; anchors.margins: 1; fillMode: Image.PreserveAspectFit; source: emailEditor.th.logoImage ? backend.cardImage(emailEditor.th.logoImage) : ""; asynchronous: true; visible: status === Image.Ready }
                            Text { anchors.centerIn: parent; visible: !emailEditor.th.logoImage; text: "No logo"; font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                        } }
                    Column { width: parent.width; spacing: 4
                        EdLabel { text: "Email body *" }
                        Rectangle {
                            width: parent.width; height: 260; radius: 4; color: theme.input; border.color: theme.stroke; border.width: 1
                            enabled: emailEditor.editable && emailEditor.bodyEditable; opacity: enabled ? 1 : 0.6
                            property var rs: ({})
                            FormatBar {
                                id: edBar
                                x: -6; y: -9; width: parent.width - 120; tierWidth: 640
                                discard: false
                                custom: [[{ k: "bold", icon: "fmt-bold", label: "Bold", on: !!parent.rs.bold }, { k: "italic", icon: "fmt-italic", label: "Italic", on: !!parent.rs.italic },
                                          { k: "underline", icon: "fmt-underline", label: "Underline", on: !!parent.rs.underline }],
                                         [{ k: "highlight", icon: "fmt-highlight", label: "Text highlight color", popup: true }, { k: "color", icon: "fmt-font-color", label: "Font color", popup: true },
                                          { k: "size", icon: "fmt-font-size", label: "Font size", popup: true }, { k: "clear", icon: "fmt-clear-format", label: "Clear all formatting" }],
                                         [{ k: "outdent", icon: "fmt-outdent", label: "Decrease indent" }, { k: "indent", icon: "fmt-indent", label: "Increase indent" },
                                          { k: "ul", icon: "fmt-bullets", label: "Bulleted list", on: parent.rs.list === "ul" }, { k: "ol", icon: "fmt-numbers", label: "Numbered list", on: parent.rs.list === "ol" }],
                                         [{ k: "link", icon: "fmt-link", label: "Insert link", popup: true }]]
                                st: parent.rs
                                selectedText: edBody.selectedText
                                onCommand: (op, arg) => { edRich.apply(edBody.selectionStart, edBody.selectionEnd, op, arg || ""); edBody.forceActiveFocus(); parent.rs = JSON.parse(edRich.state(edBody.cursorPosition) || "{}") }
                                Accessible.name: "Email body formatting"
                            }
                            Btn {
                                id: persBtn
                                anchors.right: parent.right; anchors.rightMargin: 4; y: 4
                                text: "Personalization"; icon: "chevron-down-20"
                                onClicked: { persMenu.parent = persBtn; persMenu.x = persBtn.width - persMenu.width; persMenu.y = persBtn.height + 4; persMenu.open() }
                            }
                            MenuPopup {
                                id: persMenu
                                items: emailEditor.tokenMenu.map(k => ({ key: k, label: emailEditor.labels[k] }))
                                onPicked: i => { edBody.insert(edBody.cursorPosition, emailEditor.chip(items[i].key)); edBody.forceActiveFocus() }
                            }
                            Flickable {
                                x: 13; y: 40; width: parent.width - 26; height: parent.height - 46
                                contentHeight: edBody.contentHeight; clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                TextEdit {
                                    id: edBody
                                    width: parent.width
                                    textFormat: TextEdit.RichText
                                    wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true
                                    selectionColor: theme.selectionFill; selectedTextColor: theme.text
                                    onCursorPositionChanged: parent.parent.rs = JSON.parse(edRich.state(cursorPosition) || "{}")
                                    RichText { id: edRich }
                                    Text { visible: edBody.length === 0 && !edBody.activeFocus; text: "Enter email body"; font: edBody.font; color: theme.textSecondary }
                                    Accessible.role: Accessible.EditableText
                                    Accessible.name: "Email body"
                                }
                            }
                        }
                        Text { visible: emailEditor.subjectTouched && emailEditor.bodyEmpty; text: "Email body is required"; font.family: theme.font; font.pixelSize: 12; color: theme.danger } }
                    Column { width: parent.width; spacing: 4
                        EdLabel { text: "Email footer" }
                        EdField { width: parent.width; usable: false; text: emailEditor.t ? (emailEditor.t.footer || "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim() : "" }
                        Text { text: "This is set by your IT admin."; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                }
                // ---- Preview ----
                Column {
                    visible: emailEditor.preview && !!emailEditor.t
                    width: parent.width; spacing: 12
                    Text { width: parent.width; wrapMode: Text.Wrap; text: (emailEditor.t && emailEditor.t.subject) ? emailEditor.sample(emailEditor.t.subject).replace(/<[^>]*>/g, "") : root.emailLabel(emailEditor.type)
                           font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                    Row { spacing: 8
                        Avatar { size: 32; name: (emailEditor.t && emailEditor.t.senderName) || "Event Organizer" }
                        Column { anchors.verticalCenter: parent.verticalCenter
                            Row { Text { text: (emailEditor.t && emailEditor.t.senderName) || "Event Organizer"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                  Text { text: " <" + ((emailEditor.t && emailEditor.t.senderEmail) || "noreply@microsoft.com") + ">"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary } }
                            Text { text: "To: Recipient"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } } }
                    Rectangle {
                        width: parent.width; height: Math.round(width / 3); radius: 4; clip: true
                        color: "transparent"; border.color: emailEditor.th.promoImage ? "transparent" : theme.stroke; border.width: 1
                        Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: emailEditor.th.promoImage ? backend.cardImage(emailEditor.th.promoImage) : ""; asynchronous: true }
                        Text { anchors.centerIn: parent; visible: !emailEditor.th.promoImage; horizontalAlignment: Text.AlignHCenter; text: "Event Banner Image\n(Appears here in actual email)"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    }
                    Image { visible: !!emailEditor.th.logoImage; width: 50; height: 50; fillMode: Image.PreserveAspectFit; source: emailEditor.th.logoImage ? backend.cardImage(emailEditor.th.logoImage) : "" }
                    Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.RichText; text: emailEditor.sample(emailEditor.t ? emailEditor.t.body : "")
                           font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.RichText; text: emailEditor.t ? (emailEditor.t.footer || "") : ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Row { spacing: 6
                        FluentIcon { name: "info-16"; size: 16; color: theme.textSecondary }
                        Text { width: edCol.width - 30; wrapMode: Text.Wrap; text: "The design seen by your recipients may not look like this preview, depending on their email service and device."; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                }
                // The buttons.
                Item {
                    width: parent.width; height: 32
                    Row { visible: emailEditor.editable
                        spacing: 4; anchors.verticalCenter: parent.verticalCenter
                        FluentIcon { name: emailEditor.preview ? "edit-20" : "eye-20"; size: 20; color: theme.brandForeground1; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: emailEditor.preview ? "Edit email" : "Preview"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1; anchors.verticalCenter: parent.verticalCenter }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { if (!emailEditor.preview && emailEditor.t) emailEditor.t = Object.assign({}, emailEditor.t, { subject: edSubject.text, body: emailEditor.bodyHtml(), senderName: edSender.text }); emailEditor.preview = !emailEditor.preview } } }
                    Row {
                        anchors.right: parent.right; spacing: 8
                        Btn { visible: emailEditor.editable; outlined: true; text: "Cancel"; onClicked: emailEditor.close() }
                        Btn { visible: emailEditor.editable; primary: true; usable: !emailEditor.saving && !!emailEditor.t && !emailEditor.t.error; text: emailEditor.saving ? "Saving" : "Save"; onClicked: emailEditor.save() }
                        Btn { visible: !emailEditor.editable; outlined: true; text: "Close"; onClicked: emailEditor.close() }
                    }
                }
            }
        }
    }
    // Send event reminder (the reminder's timing): a number (1-23 hours, or
    // 1 day) and Hours / Days, "before the event starts."; locked within an
    // hour of the start. Save: PATCH the template with sendTimeInterval.
    Popup {
        id: emailTiming
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property string templateId: ""
        property var t: null
        property int amount: 1
        property string unit: "hours"
        property bool saving: false
        readonly property bool locked: !!root.current && Date.parse(root.current.start) - Date.now() < 3600000
        function openFor(id) {
            templateId = id; t = null; saving = false; open()
            root.call("emailTemplate", { id: root.current.id, templateId: id }, v => {
                t = v
                const iv = v.sendTimeInterval || {}
                if ((iv.days || 0) > 0) { unit = "days"; amount = iv.days } else { unit = "hours"; amount = iv.hours || 1 }
            })
        }
        contentItem: Column {
            spacing: 16
            Item { width: parent.width; height: 28
                Text { text: "Send event reminder"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: emailTiming.close(); Accessible.name: "Close" } }
            Text { visible: emailTiming.locked; width: parent.width; wrapMode: Text.Wrap; text: "Reminder timing cannot be changed because the event starts in less than an hour."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Row {
                spacing: 8; enabled: !emailTiming.locked; opacity: enabled ? 1 : 0.5
                ComboBox { width: 80; model: emailTiming.unit === "days" ? [1] : Array.from({ length: 23 }, (x, i) => i + 1); currentIndex: Math.max(0, emailTiming.amount - 1)
                           onActivated: i => emailTiming.amount = i + 1; Accessible.name: "Reminder amount" }
                ComboBox { width: 100; model: ["Hours", "Days"]; currentIndex: emailTiming.unit === "days" ? 1 : 0
                           onActivated: i => { emailTiming.unit = i === 1 ? "days" : "hours"; emailTiming.amount = 1 }; Accessible.name: "Reminder unit" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "before the event starts."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Row {
                anchors.right: parent.right; spacing: 8
                Btn { outlined: true; text: "Cancel"; onClicked: emailTiming.close() }
                Btn { primary: true; usable: !emailTiming.saving && !emailTiming.locked && !!emailTiming.t; text: emailTiming.saving ? "Saving" : "Save"
                      onClicked: {
                          emailTiming.saving = true
                          const iv = emailTiming.unit === "days" ? { hours: 0, days: emailTiming.amount } : { hours: emailTiming.amount, days: 0 }
                          root.call("saveEmailTemplate", { id: root.current.id, templateId: emailTiming.templateId,
                                    template: { subject: emailTiming.t.subject, body: emailTiming.t.body, senderName: emailTiming.t.senderName, sendTimeInterval: iv } }, v => {
                              emailTiming.saving = false; if (!v.error) { emailTiming.close(); root.loadPeopleTab() } })
                      } }
            }
        }
    }
    // Test helpers for the email editor (--events-test=emails).
    function emailEditorForTest(i, preview) { const t = (emailTemplateList || [])[i]; if (t) emailEditor.openFor(t.templateId, t.templateType, preview); return !!t }
    function emailEditorStateForTest() { return JSON.stringify({ open: emailEditor.opened, preview: emailEditor.preview, type: emailEditor.type, subject: edSubject.text, sender: edSender.text,
                                                                   senderEditable: emailEditor.senderEditable, editable: emailEditor.editable, status: emailEditor.status,
                                                                   body: emailEditor.bodyHtml().slice(0, 600), rows: (emailTemplateList || []).map(t => root.emailLabel(t.templateType) + " / " + root.emailTiming(t)) }) }
    function emailEditorTypeForTest(text) { edBody.insert(edBody.length, text) }
    function emailEditorSaveForTest() { emailEditor.save() }
    function emailEditorCloseForTest() { emailEditor.close() }
    // Overview ▸ Edit event banner: Teams' Branding dialog (722 wide): the
    // cover image (3:1; Edit image, or Upload image when there's none), the
    // logo (90 x 90; Upload logo / Edit image), Theme color (nine 40 px
    // swatches, the chosen one underlined); Cancel / Save. Edit image crops
    // (670 x 223 for the cover, 300 x 300 for the logo) with Zoom out / the
    // zoom level / Zoom in and Upload image; Back / Save. PNG or JPG up to
    // 5 MB. Save sends the changed parts in turn: PATCH events/{id}/theme
    // {primaryColor}, /theme/promo and /theme/logo {imageId, image}; then
    // "Cover image successfully updated.", "Logo successfully updated.",
    // "Theme color successfully updated.".
    FileDialog {
        id: brandFile
        title: "Choose an image"
        nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        onAccepted: branding.picked(selectedFile.toString())
    }
    Popup {
        id: branding
        parent: Overlay.overlay
        modal: true; padding: 24; topPadding: 12
        x: (parent.width - width) / 2; y: Math.max(16, (parent.height - height) / 2)
        width: 722
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        readonly property var swatches: [["Default", "#5B5FC7"], ["Red", "#B82F41"], ["Orange", "#FFA08F"], ["Yellow", "#FFBA82"], ["Green", "#9DE3CB"],
                                         ["Teal", "#9EE5DE"], ["Blue", "#257ACC"], ["Pink", "#D13B6D"], ["Grey", "#F0F0F0"]]
        property var th: ({})
        property string color: ""
        property string coverFile: ""
        property string logoFile: ""
        property string view: "main"   // main, cover, logo
        property string cropSource: ""
        property string error: ""
        property bool saving: false
        property real zoom: 1
        property real minZoom: 1
        property int savedSeq: 0
        function openNow() {
            view = "main"; error = ""; saving = false; coverFile = ""; logoFile = ""; th = ({}); color = ""
            open()
            root.call("theme", { id: root.current.id }, v => { if (!v.error) { th = v; color = v.primaryColor || "#8C5BD2" } })
        }
        readonly property string coverSource: coverFile ? coverFile : (th.promoImage ? backend.cardImage(th.promoImage) : "")
        readonly property string logoSource: logoFile ? logoFile : (th.logoImage ? backend.cardImage(th.logoImage) : "")
        property string pickFor: ""
        function pick(which) { pickFor = which; brandFile.open() }
        function picked(url) {
            if (!/\.(png|jpe?g)$/i.test(url)) { error = "Choose a PNG or JPG file."; return }
            const size = backend.fileSize(url.replace(/^file:\/\//, ""))
            if (size > 5 * 1024 * 1024) { error = "Choose a file smaller than 5 MB. "; return }
            error = ""
            cropSource = url; view = pickFor
        }
        function editCurrent(which) { cropSource = which === "cover" ? coverSource : logoSource; view = which }
        // The crop as Teams makes it: the visible part at the image's own
        // size, a JPEG.
        function saveCrop() {
            const which = view
            const n = ++savedSeq
            const out = "/tmp/ost-branding-" + which + "-" + n + ".jpg"
            const scale = cropImg.sourceSize.width > 0 ? cropImg.sourceSize.width / cropImg.paintedWidth : 1
            cropBox.grabToImage(r => {
                r.saveToFile(out)
                if (which === "cover") coverFile = "file://" + out; else logoFile = "file://" + out
                view = "main"
            }, Qt.size(Math.round(cropBox.width * scale), Math.round(cropBox.height * scale)))
        }
        function save() {
            saving = true; error = ""
            const id = root.current.id, etag = th.eTag || "*"
            const steps = []
            if (color && color !== (th.primaryColor || "#8C5BD2")) steps.push(["color", "Theme color successfully updated."])
            if (coverFile) steps.push(["promo", "Cover image successfully updated."])
            if (logoFile) steps.push(["logo", "Logo successfully updated."])
            const done = []
            const next = () => {
                const s = steps.shift()
                if (!s) {
                    saving = false
                    for (const t of done) root.toast({ text: t })
                    root.call("overview", { id: id }, v => { if (!v.error && v.card) root.current = Object.assign({}, root.current, v.card) })
                    branding.close(); return
                }
                const cb = v => {
                    console.warn("EVENTS branding", s[0], JSON.stringify(v).slice(0, 200))
                    if (v.error) { saving = false; error = "Something went wrong. Please try again."; return }
                    done.push(s[1]); next()
                }
                if (s[0] === "color") root.call("setThemeColor", { id: id, eTag: etag, color: color }, cb)
                else root.call("setThemeImage", { id: id, eTag: etag, which: s[0], current: s[0] === "promo" ? (th.promoImage || "") : (th.logoImage || ""),
                                                  path: s[0] === "promo" ? coverFile : logoFile }, cb)
            }
            next()
        }
        component RoundBtn: Rectangle {
            id: rb
            property string icon
            property string text
            signal clicked()
            height: 32; width: text ? rbRow.implicitWidth + 24 : 32; radius: 16
            color: rbh.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 1
            Row { id: rbRow; anchors.centerIn: parent; spacing: 6
                FluentIcon { name: rb.icon; size: 20; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                Text { visible: !!rb.text; text: rb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; anchors.verticalCenter: parent.verticalCenter } }
            HoverHandler { id: rbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: rb.clicked() }
            Accessible.role: Accessible.Button; Accessible.name: rb.text
        }
        contentItem: Column {
            spacing: 0
            width: branding.availableWidth
            Item { width: parent.width; height: 44
                Text { y: 12; text: branding.view === "main" ? "Branding" : "Edit image"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; y: 6; icon: "dismiss-20"; text: ""; pad: 6; onClicked: branding.close(); Accessible.name: "Close dialog" } }
            // ---- main ----
            Column {
                visible: branding.view === "main"
                width: parent.width; spacing: 16
                Row { spacing: 6
                    Text { width: Math.min(implicitWidth, branding.availableWidth - 30); wrapMode: Text.Wrap; text: "Choose a PNG or JPG file (max 5 MB). For best results, image ratio should be at least 796 x 265 pixels."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    FluentIcon { name: "info-16"; size: 16; color: theme.textStrong
                        ToolTip.visible: infoHover.hovered; ToolTip.text: "The images you upload will be hosted in a publicly available CDN."
                        HoverHandler { id: infoHover }
                        Accessible.role: Accessible.Button; Accessible.name: "Public CDN hosting more information" } }
                Column { width: parent.width; spacing: 8
                    Text { text: "Cover image"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Rectangle {
                        width: parent.width; height: Math.round(width / 3); radius: 8; clip: true
                        color: theme.pick("#F0F0F0", "#1F1F1F", "#000000")
                        Image { anchors.fill: parent; fillMode: Image.PreserveAspectFit; source: branding.coverSource; asynchronous: true; cache: false }
                        RoundBtn { visible: !!branding.coverSource; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8; icon: "image-edit-20"; text: "Edit image"; onClicked: branding.editCurrent("cover") }
                        Btn { visible: !branding.coverSource; anchors.centerIn: parent; opacity: 0.7; icon: "arrow-upload-20"; text: "Upload image"; onClicked: branding.pick("cover") }
                    } }
                Row {
                    spacing: 24
                    Column { spacing: 8
                        Text { text: "Logo"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Rectangle {
                            width: 90; height: 90; radius: 4; clip: true
                            color: theme.pick("#F0F0F0", "#1F1F1F", "#000000"); border.color: theme.divider; border.width: 1
                            Image { anchors.fill: parent; anchors.margins: 1; fillMode: Image.PreserveAspectFit; source: branding.logoSource; asynchronous: true; cache: false }
                            RoundBtn { visible: !!branding.logoSource; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4; icon: "image-edit-20"; onClicked: branding.editCurrent("logo"); Accessible.name: "Edit image" }
                            RoundBtn { visible: !branding.logoSource; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6; icon: "arrow-upload-20"; onClicked: branding.pick("logo"); Accessible.name: "Upload logo" }
                        } }
                    Column { spacing: 8
                        Text { text: "Theme color"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Row { spacing: 18
                            Repeater { model: branding.swatches
                                Item {
                                    required property var modelData
                                    width: 40; height: 48
                                    Rectangle {
                                        width: 40; height: 40; radius: 20
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: Qt.lighter(modelData[1], 1.25) }
                                            GradientStop { position: 1; color: Qt.darker(modelData[1], 1.1) }
                                        }
                                        border.color: theme.dividerSoft; border.width: modelData[0] === "Grey" ? 1 : 0
                                    }
                                    Rectangle { visible: branding.color.toUpperCase() === modelData[1].toUpperCase(); y: 44; width: 40; height: 4; radius: 2; color: theme.brand }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: branding.color = modelData[1] }
                                    ToolTip.visible: swh.hovered; ToolTip.text: modelData[0]
                                    HoverHandler { id: swh }
                                    Accessible.role: Accessible.RadioButton; Accessible.name: modelData[0]; Accessible.checked: branding.color.toUpperCase() === modelData[1].toUpperCase()
                                } } } }
                }
                Item { width: parent.width; height: 40
                    Text { visible: !!branding.error; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 260; elide: Text.ElideRight; text: branding.error; font.family: theme.font; font.pixelSize: 12; color: theme.danger }
                    Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Btn { outlined: true; text: "Cancel"; onClicked: branding.close() }
                        Btn { primary: true; usable: !branding.saving; text: branding.saving ? "Saving..." : "Save"; onClicked: branding.save() } } }
            }
            // ---- Edit image (crop) ----
            Column {
                visible: branding.view !== "main"
                width: parent.width; spacing: 12
                Text { text: branding.view === "logo" ? "Logo image" : "Cover image"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Text { width: parent.width; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text
                       text: branding.view === "logo" ? "PNG or JPG (max 5 MB). For best results, use a 1:1 image (at least 280×280 px)." : "PNG or JPG (max 5 MB). For best results, use a 3:1 image (at least 796 × 265 px)." }
                Rectangle {
                    width: parent.width; height: branding.view === "logo" ? 300 : 287
                    color: theme.pick("#F0F0F0", "#1F1F1F", "#000000"); clip: true
                    Item {
                        id: cropBox
                        anchors.centerIn: parent
                        width: branding.view === "logo" ? 300 : 670; height: branding.view === "logo" ? 300 : 223
                        clip: true
                        Image {
                            id: cropImg
                            source: branding.view !== "main" ? branding.cropSource : ""
                            fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                            width: cropBox.width * branding.zoom; height: cropBox.height * branding.zoom
                            x: (cropBox.width - width) / 2 + dragX; y: (cropBox.height - height) / 2 + dragY
                            property real dragX: 0
                            property real dragY: 0
                            DragHandler { target: null; onTranslationChanged: { cropImg.dragX += translation.x - (cropImg._lx || 0); cropImg.dragY += translation.y - (cropImg._ly || 0); cropImg._lx = translation.x; cropImg._ly = translation.y }
                                          onActiveChanged: { cropImg._lx = 0; cropImg._ly = 0 } }
                            property real _lx: 0
                            property real _ly: 0
                        }
                    }
                    Rectangle { anchors.fill: cropBox; color: "transparent"; border.color: theme.textOnBrand; border.width: 2 }
                }
                Row {
                    spacing: 12
                    RoundBtn { icon: "arrow-upload-20"; text: "Upload image"; onClicked: branding.pick(branding.view) }
                    Btn { icon: "zoom-out-20"; text: ""; pad: 6; Accessible.name: "Zoom out"; onClicked: branding.zoom = Math.max(branding.minZoom, branding.zoom - 0.1) }
                    Slider { id: zoomSlider; width: 200; from: branding.minZoom; to: branding.minZoom + 5; stepSize: 0.1; value: branding.zoom; onMoved: branding.zoom = value
                             Accessible.name: "Zoom level"; Accessible.description: "Zoom " + Math.round(branding.zoom * 100) + "%" }
                    Btn { icon: "zoom-in-20"; text: ""; pad: 6; Accessible.name: "Zoom in"; onClicked: branding.zoom = Math.min(branding.minZoom + 5, branding.zoom + 0.1) }
                }
                Item { width: parent.width; height: 40
                    Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Btn { outlined: true; text: "Back"; Accessible.name: "Go back"; onClicked: branding.view = "main" }
                        Btn { primary: true; text: "Save"; onClicked: branding.saveCrop() } } }
            }
        }
        onViewChanged: { zoom = 1; cropImg.dragX = 0; cropImg.dragY = 0 }
    }
    function brandingForTest() { branding.openNow() }
    function brandingStateForTest() { return JSON.stringify({ open: branding.opened, view: branding.view, color: branding.color, theme: branding.th, cover: branding.coverFile, logo: branding.logoFile, error: branding.error }) }
    function brandingColorForTest(c) { branding.color = c }
    function brandingCoverForTest(url) { branding.pickFor = "cover"; branding.picked(url) }
    function brandingCropSaveForTest() { branding.saveCrop() }
    function brandingSaveForTest() { branding.save() }
    // "Save this event as a template?" (722 wide: the promo picture, Name *
    // with the event's name, Description; Save template).
    Popup {
        id: templateDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 722
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var ev: ({})
        property bool busy: false
        function openFor(e) { ev = e || {}; tName.text = ev.title || ""; tDesc.text = ""; busy = false; open() }
        contentItem: Column {
            spacing: 0
            Item { width: parent.width; height: 31
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Save this event as a template?"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: templateDialog.close(); Accessible.name: "Close dialog" } }
            Item { width: 1; height: 16 }
            Text { text: "We'll save everything except the date and time for you to use again."; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
            Item { width: 1; height: 24 }
            Rectangle {
                width: parent.width; height: 219; radius: 8; clip: true; color: templateDialog.ev.primary_color || "#5B5FC7"
                Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                        source: { backend.emoticonsVersion; return templateDialog.ev.promo_image ? backend.cardImage(templateDialog.ev.promo_image) : "" } }
            }
            Item { width: 1; height: 20 }
            Row { spacing: 2
                Text { text: "Name"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { text: "*"; font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3 } }
            Item { width: 1; height: 4 }
            Rectangle { width: parent.width; height: 32; radius: 4; color: theme.inputFilled
                TextInput { id: tName; x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true; Accessible.name: "Name" } }
            Item { width: 1; height: 12 }
            Text { text: "Description"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 4 }
            Rectangle { width: parent.width; height: 80; radius: 4; color: theme.inputFilled
                TextEdit { id: tDesc; x: 12; y: 8; width: parent.width - 24; height: parent.height - 16; wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true
                    Text { visible: !tDesc.text; text: "Type some details about this template"; font: tDesc.font; color: theme.textSecondary }
                    Accessible.name: "Description" } }
            Item { width: 1; height: 30 }
            Btn {
                anchors.right: parent.right; primary: true; text: "Save template"; usable: tName.text.trim().length > 0 && !templateDialog.busy
                onClicked: templateDialog.save()
            }
        }
        function nameForTest(n) { tName.text = n }
        function save() {
                {
                    templateDialog.busy = true
                    root.call("event", { id: templateDialog.ev.id }, d => {
                        if (d.error) { templateDialog.busy = false; root.toast({ text: "Couldn't save the template. " + d.error, intent: "error" }); return }
                        form.fill(d)
                        root.call("saveTemplate", { id: templateDialog.ev.id, name: tName.text.trim(), templateDescription: tDesc.text, event: form.payload() }, v => {
                            templateDialog.busy = false; templateDialog.close()
                            if (v.error) { root.toast({ text: "Couldn't save the template. " + v.error, intent: "error" }); return }
                            root.toast({ text: "Template saved", intent: "success", action: "View your templates", onAction: () => root.startCreate() })
                        })
                    })
                }
            }
    }
    // Room options ("Teams rooms options", 600 wide): each room's Set up room
    // for (Presenting, Attendee viewing); Save.
    Popup {
        id: roomOptions
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 600
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Column {
            spacing: 0
            Item { width: parent.width; height: 32
                Row { anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    FluentIcon { name: "door-20"; size: 20; color: theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Teams rooms options"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text } }
                Btn { anchors.right: parent.right; icon: "dismiss-20"; text: ""; pad: 6; onClicked: roomOptions.close(); Accessible.name: "Close" } }
            Item { width: 1; height: 24 }
            Item { width: parent.width; height: 32
                Row { x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    FluentIcon { name: "video-person-20"; size: 16; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Teams Rooms"; font.family: theme.font; font.pixelSize: 14; color: theme.text } }
                Row { x: 336; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    FluentIcon { name: "people-20"; size: 16; color: theme.textStrong; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Set up room for"; font.family: theme.font; font.pixelSize: 14; color: theme.text } } }
            Rectangle { width: parent.width; height: 1; color: theme.divider }
            Repeater {
                model: form.rooms
                Column {
                    required property var modelData
                    width: roomOptions.width - 48
                    Item { width: parent.width; height: 44
                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Dropdown { x: 336; anchors.verticalCenter: parent.verticalCenter; width: 206; height: 30; accessibleName: "Set up room for"
                                   options: [["Presenting", "Presenting"], ["AttendeeViewing", "Attendee viewing"]]
                                   label: parent.parent.modelData.roomRole === "AttendeeViewing" ? "Attendee viewing" : "Presenting"
                                   onPicked: v => { const a = form.rooms.map(r => r.email === parent.parent.modelData.email ? Object.assign({}, r, { roomRole: v }) : r); form.rooms = a } } }
                    Rectangle { width: parent.width; height: 1; color: theme.divider }
                }
            }
            Item { width: 1; height: 12 }
            Btn { anchors.right: parent.right; primary: true; width: 96; text: "Save"; onClicked: roomOptions.close() }
        }
    }
    // Connect apps ("Connect apps and workflows", 900 wide): Teams'
    // third-party integrations as cards (416 x 142, #D1D1D1, radius 8: the
    // apps' 28 px logos, the open-in-new glyph, the name 14/20 semibold, the
    // description 12/16 #616161); a card opens its page in the browser.
    Popup {
        id: connectApps
        parent: Overlay.overlay
        modal: true; padding: 25
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 900
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var items: []
        function openNow() { open(); root.call("integrations", {}, v => { if (!v.error) items = v.items || [] }) }
        contentItem: Column {
            spacing: 0
            Item { width: parent.width; height: 34
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Connect apps and workflows"; font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; color: theme.text }
                Btn { anchors.right: parent.right; y: -16; icon: "dismiss-20"; text: ""; pad: 6; onClicked: connectApps.close(); Accessible.name: "Close" } }
            Item { width: 1; height: 15 }
            Text { text: "Save time by sharing event data with your favorite apps."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 16 }
            Flow {
                width: parent.width; spacing: 17
                Repeater {
                    model: connectApps.items
                    Rectangle {
                        id: integ
                        required property var modelData
                        width: 416; height: 142; radius: 8; color: ih.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 1
                        Row { x: 16; y: 18; spacing: 6
                            Repeater { model: integ.modelData.icons || []
                                Image { required property var modelData; width: 28; height: 28; source: modelData; sourceSize: Qt.size(56, 56); asynchronous: true } } }
                        FluentIcon { x: parent.width - 39; y: 18; name: "open-20"; size: 20; color: theme.text }
                        Text { x: 16; y: 52; width: parent.width - 32; elide: Text.ElideRight; text: integ.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        Text { x: 16; y: 78; width: parent.width - 32; wrapMode: Text.Wrap; maximumLineCount: 3; text: integ.modelData.description; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
                        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally(integ.modelData.link) }
                        Accessible.role: Accessible.Button; Accessible.name: integ.modelData.name
                    }
                }
            }
        }
    }
    // The meeting options dialog for All options (Apply keeps the changes
    // for the save; the form's own tiles follow them).
    MeetingOptionsDialog {
        id: allOptions
        onApply: changes => {
            const o = Object.assign({}, form.optionChanges)
            Object.keys(changes).forEach(k => {
                const key = k.charAt(0).toLowerCase() + k.slice(1)
                o[key] = changes[k]
                if (k === "AttendeeRestrictions") { const r = String(changes[k]); form.mic = r.indexOf("DisableAudio") < 0; form.camera = r.indexOf("DisableVideo") < 0 }
                else if (k === "AllowTeamsMeetingReactions") form.react = !!changes[k]
                else if (k === "AllowMeetingChat") form.chat = changes[k] !== "Disabled"
                else if (k === "YammerQNAEnabled") form.qna = !!changes[k]
                else if (k === "StagingRoomEnabled") form.greenRoom = !!changes[k]
            })
            form.optionChanges = o
            allOptions.close()
        }
    }
    // "Ready to publish your event?" (800 wide, radius 8, padding 24;
    // measured 2026-11-17): the settings that lock on publishing as chips,
    // then Cancel and Publish event (rocket). Publishing is
    // `PATCH events/{id}` {state: Published}; the People & emails lists
    // are read first so OST can say who will be invited.
    Popup {
        id: publishDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 800
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var ev: ({})
        property var people: null
        property bool busy: false
        function openFor(e) { ev = e || {}; people = null; open(); root.call("people", { id: ev.id }, v => { if (!v.error) people = v }) }
        contentItem: Column {
            spacing: 0
            Text { text: "Ready to publish your event?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; height: 28 }
            Item { width: 1; height: 13 }
            Text { width: 752; wrapMode: Text.Wrap; text: "Invites will be sent to attendees. You can add more attendees and share the event after it's published."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 15 }
            Text { text: "These settings can’t be changed after publishing"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text; height: 22 }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                Repeater {
                    model: [["people-community-20", "Who can view and join:", publishDialog.ev.access === "Public" ? "Public" : publishDialog.ev.inviteOnly ? "Specific people" : "Your organization"],
                            ["clipboard-20", "Registration:", publishDialog.ev.registration ? "On" : "Off"]]
                    Rectangle {
                        required property var modelData
                        height: 32; radius: 16; width: pubr.implicitWidth + 24; color: theme.surface; border.color: theme.divider; border.width: 1
                        Row { id: pubr; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            FluentIcon { name: modelData[0]; size: 20; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2]; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    }
                }
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                Btn { width: 96; outlined: true; text: "Cancel"; onClicked: publishDialog.close() }
                Btn { primary: true; icon: "rocket-20"; text: "Publish event"; usable: !publishDialog.busy
                      onClicked: {
                          publishDialog.busy = true
                          root.call("publish", { id: publishDialog.ev.id }, v => {
                              publishDialog.busy = false; publishDialog.close()
                              if (v.error) { root.toast({ text: "Couldn't publish the event. " + v.error, intent: "error" }); return }
                              root.current = Object.assign({}, root.current, { state: v.state || "Published" })
                              root.manageData = null
                              shareDialog.openFor(root.current, true, v)
                          })
                      } }
            }
        }
    }
    // After Publish ("Success! Your event has been published" / "Help your
    // attendees discover it:", 20/28 semibold centred) and the page's Share
    // ("Help attendees discover this event", 24/32 bold): 800 wide; on the
    // left the card attendees see (369 x 309, radius 24: the promo picture,
    // the title, "in 25 mins" and the time, "By {presenter}", the location,
    // Add to calendar and Copy event page link) over "Here's what attendees
    // will see."; on the right Show event in Events app ("Attendees with
    // access can view": PATCH events/{id} {"isDiscoverable"} with the
    // event's eTag, as Teams' toggleDiscoverability), then Copy join
    // details, Copy event page link and, for a town hall, Copy embed code
    // (Teams' town hall player in an iframe), 369 x 31, outlined, at the
    // bottom. The card shows Join (from 5 minutes before the start) or
    // Add to calendar, and the Live / "in N mins" badge as cards do.
    Popup {
        id: shareDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 800
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property var ev: ({})
        property bool success: false
        property bool discoverable: false
        property bool toggling: false
        property string embedCode: ""
        property real now: Date.now()
        readonly property real startMs: ev.start ? new Date(ev.start).getTime() : 0
        readonly property real endMs: ev.end ? new Date(ev.end).getTime() : 0
        readonly property bool live: now >= startMs && now < endMs
        readonly property bool joinable: !!ev.join_url && now >= startMs - 300000 && now <= endMs
        // `reply`: the publish reply (isDiscoverable, embedCode); else the
        // card's own (Share).
        function openFor(e, s, reply) {
            ev = e || {}; success = !!s; now = Date.now()
            discoverable = reply && reply.isDiscoverable !== undefined ? !!reply.isDiscoverable : !!ev.discoverable
            embedCode = reply && reply.embedCode ? reply.embedCode : ""
            if (!embedCode && ev.event_type === "Townhall" && ev.id) root.call("embedCode", { id: ev.id }, v => { if (!v.error && v.code) embedCode = v.code })
            open()
        }
        contentItem: Item {
            implicitHeight: shareDialog.success ? 406 : 394
            Item {
                width: parent.width; height: shareDialog.success ? 48 : 32
                Column {
                    visible: shareDialog.success
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Success! Your event has been published"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Help your attendees discover it:"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                }
                Text { visible: !shareDialog.success; y: 8; text: "Help attendees discover this event"; font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; color: theme.text }
                Btn { anchors.right: parent.right; y: shareDialog.success ? 0 : 8; icon: "dismiss-20"; text: ""; pad: 6; onClicked: shareDialog.close(); Accessible.name: "Close" }
            }
            // The attendee card.
            Item {
                id: aCard
                y: shareDialog.success ? 68 : 56; width: 369; height: 309
                FluentSurface { anchors.fill: parent; depth: 4; radius: 24; color: theme.surface }
                Rectangle {
                    x: 12; y: 12; width: parent.width - 24; height: 115; radius: 16; clip: true; color: shareDialog.ev.primary_color || "#5B5FC7"
                    Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                            source: { backend.emoticonsVersion; return shareDialog.ev.promo_image ? backend.cardImage(shareDialog.ev.promo_image) : "" } }
                }
                Text { x: 20; y: 137; width: parent.width - 40; elide: Text.ElideRight; text: shareDialog.ev.title || ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Row {
                    x: 20; y: 163; spacing: 6; height: 20
                    readonly property string soon: shareDialog.live ? "Live" : root.soonText(shareDialog.ev.start)
                    Rectangle { visible: !!parent.soon; anchors.verticalCenter: parent.verticalCenter; height: 16; radius: 8; width: sRow.implicitWidth + (shareDialog.live ? 10 : 8)
                        color: shareDialog.live ? "#D13438" : theme.pick("#E8EBFA", "#2F2F4A", "#000000")
                        border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                        Row { id: sRow; x: shareDialog.live ? 4 : 2; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: shareDialog.live ? "record-20" : "clock-12-filled"; size: shareDialog.live ? 10 : 12; color: shareDialog.live ? "#FFFFFF" : theme.brand }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.parent.soon; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: shareDialog.live ? "#FFFFFF" : theme.brand } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.whenText(shareDialog.ev.start, shareDialog.ev.end, false); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                }
                Column {
                    x: 20; y: 193; spacing: 4
                    Row { visible: !!shareDialog.ev.by; spacing: 4
                        FluentIcon { name: "person-16"; size: 16; color: theme.textSecondary }
                        Text { text: "By " + (shareDialog.ev.by || ""); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                    Row { spacing: 4
                        FluentIcon { name: "location-20"; size: 16; color: theme.textSecondary }
                        Text { text: shareDialog.ev.location || "Online"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary } }
                }
                Row {
                    x: 20; y: 265; spacing: 8
                    Btn { visible: shareDialog.joinable; height: 23; width: 64; primary: true; icon: "video-16"; text: "Join"; fontSize: 12; pad: 8; usable: false }
                    Btn { visible: !shareDialog.joinable; height: 24; outlined: true; fontSize: 12; pad: 8; icon: "calendar-add-20"; text: "Add to calendar"; usable: false }
                    Btn { width: 24; height: 24; outlined: true; icon: "link-20"; text: ""; pad: 2; Accessible.name: "Copy event page link"
                          onClicked: { backend.copyText(shareDialog.ev.site_url || ""); root.toast({ text: "Event page link copied successfully", intent: "success" }) } }
                }
            }
            Text { x: 0; y: aCard.y + aCard.height + 12; width: 369; horizontalAlignment: Text.AlignHCenter; text: "Here’s what attendees will see."; font.family: theme.font; font.pixelSize: 10; color: theme.text }
            // Show event in Events app.
            Item {
                x: 381; y: aCard.y; width: 369; height: 36
                Rectangle { x: 0; y: 4; width: 28; height: 28; radius: 4; color: theme.brandFill
                    FluentIcon { anchors.centerIn: parent; name: "people-community-20"; size: 20; color: theme.textOnBrand } }
                Column { x: 38; y: 0
                    Text { text: "Show event in Events app"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                    Text { text: "Attendees with access can view"; font.family: theme.font; font.pixelSize: 12; color: theme.text } }
                SettingsParts.Toggle {
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    stateLabel: false; on: shareDialog.discoverable; accessibleName: "Show event in Events app"
                    onToggled: v => {
                        if (shareDialog.toggling) return
                        shareDialog.toggling = true
                        shareDialog.discoverable = v
                        root.call("discoverable", { id: shareDialog.ev.id, on: v }, r => {
                            shareDialog.toggling = false
                            if (r.error) { root.toast({ text: "Couldn't change it. " + r.error, intent: "error" }); shareDialog.discoverable = !v; return }
                            const now = !!r.isDiscoverable
                            shareDialog.discoverable = now
                            shareDialog.ev = Object.assign({}, shareDialog.ev, { discoverable: now })
                            if (root.current && root.current.id === shareDialog.ev.id) root.current = Object.assign({}, root.current, { discoverable: now })
                        })
                    }
                }
            }
            Column {
                x: 381; y: aCard.y + aCard.height - (shareDialog.embedCode ? 113 : 72); width: 369; spacing: 10
                Btn { width: 369; height: 31; outlined: true; icon: "document-20"; text: "Copy join details"; onClicked: root.copyJoinDetails(shareDialog.ev) }
                Btn { width: 369; height: 31; outlined: true; icon: "link-20"; text: "Copy event page link"
                      onClicked: { backend.copyText(shareDialog.ev.site_url || ""); root.toast({ text: "Event page link copied successfully", intent: "success" }) } }
                Btn { visible: !!shareDialog.embedCode; width: 369; height: 31; outlined: true; icon: "code-20"; text: "Copy embed code"
                      onClicked: { backend.copyText(shareDialog.embedCode); root.toast({ text: "Copied", intent: "success" }) } }
            }
        }
    }
    function publishCurrentForTest() { if (current) call("publish", { id: current.id }, v => { console.warn("EVENTS publish", JSON.stringify(v)); if (!v.error) current = Object.assign({}, current, { state: v.state }) }) }
    // "Cancel event?" (one-events-cancel-event-dialog).
    Popup {
        id: cancelDialog
        parent: Overlay.overlay
        modal: true; padding: 24
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 480
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        property bool busy: false
        contentItem: Column {
            spacing: 8
            Text { text: "Cancel event?"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text { width: 432; wrapMode: Text.Wrap; text: "Once canceled, you cannot uncancel. Attendees will be notified by email."; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 12 }
            Btn { anchors.right: parent.right; primary: true; text: "Cancel event"; usable: !cancelDialog.busy
                  onClicked: {
                      cancelDialog.busy = true
                      root.call("cancel", { id: root.current.id }, v => {
                          cancelDialog.busy = false; cancelDialog.close()
                          if (v.error) { root.toast({ text: "Couldn't cancel the event. " + v.error, intent: "error" }); return }
                          root.current = Object.assign({}, root.current, { state: "Canceled" })
                          root.manageData = null
                      })
                  } }
        }
    }
    function cancelCurrentForTest() { if (current) call("cancel", { id: current.id }, v => { console.warn("EVENTS cancel", JSON.stringify(v)); current = Object.assign({}, current, { state: v.error ? current.state : "Canceled" }) }) }
    function openOptionsForTest() { form.open = [false, false, false, true]; form.contentY = 0 }
    function saveForTest(name) { nameField.text = name; saveDialog.open() }
    function accessForTest(a) { form.access = a }
    function confirmSaveForTest() { saveDialog.contentItem.children[saveDialog.contentItem.children.length - 1].children[1].clicked() }
}
