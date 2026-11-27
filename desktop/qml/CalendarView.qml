import QtQuick
import QtQuick.Controls.Basic
import QtCore

// The Calendar app, laid out as Teams' calendar (its Outlook-hosted
// calendar, measured in Teams on the web as ost-test1, 2026-11-17, at 1x;
// docs/spec/calendar.md):
// - a 235 px side pane with the month and your calendars;
// - a 61 px toolbar: Today, previous/next, the range ▾ | the view ▾, Meet
//   now ▾ (Join with an ID), New ▾ (Event, Channel meeting);
// - Day, Work week and Week: 54 px day headers, the all-day strip (18 px
//   bars 21 apart, titles centred 10/600), the grid at 80 px an hour.
//   Overlapping events share their day side by side (2.6 in, 12 free on the
//   right, 4 between); an event crossing midnight is drawn in each day. In
//   the week that holds today, today takes 30 % of the width and past days
//   11 %; the other days share the rest (a day gets at least what its
//   overlapping events need). Past days and hours outside 8–17 are #FAFAFA (dark #242424, calOff),
//   a day under an all-day busy event the calendar colour at 10 % over it;
// - Month: 28 px day names, 163 px cells, events 24 tall 26 apart from 31.6
//   down (time 12/400, title 12/600; all-day ones centred), "+N" when the
//   cell is full; multi-day events span the week's cells;
// - the peek card (392 wide) with Join ▾ / Chat, the time, location, who
//   invited you and your answer (Email organizer, a message, Accept /
//   Decline / Tentative, for a series This event / All events in the
//   series), and the expand button for the event page (MeetingForm).
Item {
    id: root
    property var events: []
    /// The first day shown (local midnight).
    property date start: mondayOf(new Date())
    /// "workweek" (Mon-Fri), "week" (Sun-Sat), "day" or "month".
    property string view: "workweek"
    property bool paneShown: true
    property bool showCalendar: true
    /// For the scheduling form: the teams list, people search results and you.
    property var teams: []
    property var people: []
    property var me: ({})

    // ── Teams' calendar settings (docs/spec/calendar.md, "Filter, Time
    // scale, Saved views, Split view") ──────────────────────────────────
    /// Time scale in minutes: 60, 30, 15, 10, 6 or 5 (Outlook options'
    /// CalendarSurfaceOptions.timeScaleSetting).
    property int timeScale: 30
    /// The Day view's day count, 1 to 7 (numDaysInDayRange).
    property int numDays: 1
    /// The Filter menu's unchecked values, {filterType: [values]} (Teams'
    /// calendar_filters roaming setting): "Filter applied" while any.
    property var filterMap: ({})
    readonly property bool filterApplied: Object.keys(filterMap).length > 0
    property var savedViews: []
    /// The saved view shown (its id) until the view or a filter changes.
    property string currentViewId: ""
    property var categories: []
    property string calendarId: ""
    property bool prefsLoaded: false
    property bool splitView: false
    /// Split view needs two calendars shown, and Month has none (Teams:
    /// disabled with fewer than two selected).
    readonly property int selectedCalendars: (showCalendar ? 1 : 0) + otherSelected.length
    /// Your calendars (Graph: your own and your groups'), Teams' pane's My
    /// calendars and Groups; the ones ticked besides Calendar, and their
    /// events for the range shown.
    property var calendarList: []
    property var otherSelected: []
    property var extraEvents: []
    property bool showAllCalendars: false
    readonly property var otherCalendars: calendarList.filter(c => !c.is_default)
    function calendarById(id) { return calendarList.find(c => c.id === id) || { id: id, name: "", color: "" } }
    function toggleCalendar(id) {
        const l = otherSelected.slice(), i = l.indexOf(id)
        if (i >= 0) l.splice(i, 1); else l.push(id)
        otherSelected = l
        calendarLocal.selectedCalendars = JSON.stringify(l)
        loadExtraEvents()
    }
    property string rangeStartIso: ""
    property string rangeEndIso: ""
    function loadExtraEvents() {
        if (!otherSelected.length) { extraEvents = []; return }
        if (rangeStartIso) calendarAction("calendarEvents", JSON.stringify({ calendars: otherSelected, start: rangeStartIso, end: rangeEndIso }))
    }
    /// The calendars Split view shows, in the pane's order: yours first.
    readonly property var splitCalendars: (showCalendar ? [{ id: "", name: qsTr("Calendar"), color: "" }] : []).concat(otherCalendars.filter(c => otherSelected.indexOf(c.id) >= 0))
    readonly property bool splitActive: splitView && canSplit
    readonly property bool canSplit: selectedCalendars >= 2 && !monthView
    // Teams' device-local marker (localStorage UnselectedReservationFilter):
    // the first time a device opens the calendar, Reservations ▸ Desk is
    // unchecked and saved.
    Settings { id: calendarLocal; location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation) + "/calendar.ini"; category: "calendar"; property string unselectedReservationFilter: ""; property string selectedCalendars: "[]" }
    function applyPrefs(r) {
        timeScale = [60, 30, 15, 10, 6, 5].indexOf(r.timeScale) >= 0 ? r.timeScale : 30
        numDays = Math.max(1, Math.min(7, r.numDays || 1))
        categories = r.categories || []
        savedViews = r.savedViews || []
        calendarId = r.calendarId || ""
        objectId = r.objectId || ""
        copilotEntries = !!r.copilot
        tenantId = r.tenantId || ""
        const m = {}
        for (const e of r.filters || []) if (e && e.length === 2 && Array.isArray(e[1]) && e[1].length) m[e[0]] = e[1]
        // A category filter's mailbox, as Teams wrote it.
        for (const v of m.Category || []) { try { const o = JSON.parse(v); if (o.mailboxInfo) { catMailboxInfo = o.mailboxInfo; break } } catch (err) {} }
        filterMap = m
        if (calendarLocal.unselectedReservationFilter !== "Desk") {
            calendarLocal.unselectedReservationFilter = "Desk"
            if ((m.Reservations || []).indexOf("Desk") < 0) {
                const n = Object.assign({}, m); n.Reservations = (m.Reservations || []).concat(["Desk"])
                filterMap = n
                saveFilters()
            }
        }
        prefsLoaded = true
    }
    readonly property var meetingValues: ["Organizer", "Drafts", "Accepted", "DeclinedEvents", "Followed", "Maybe", "Canceled", "NotResponded"]
    function filterValues(type) {
        switch (type) {
        case "Meetings": return meetingValues
        case "PollHolds": return ["SeeAll", "VotedYes", "VotedNo", "NotVoted"]
        case "Reservations": return ["Desk"]
        case "ShowAs": return ["Free", "WorkingElsewhere", "Tentative", "Busy", "OOF"]
        case "Recurrence": return ["Single", "Series"]
        case "InPerson": return ["Required", "NotRequired"]
        case "Category": return ["Uncategorized"].concat(categories.map(c => c.name)).map(n => catValue(n))
        }
        return []
    }
    // A category's filter value, as Teams keeps it: {mailboxInfo, categoryName}.
    property var catMailboxInfo: null
    function catValue(name) {
        return JSON.stringify({ mailboxInfo: catMailboxInfo || { type: "UserMailbox", userIdentity: me.mail || "", mailboxSmtpAddress: me.mail || "" }, categoryName: name })
    }
    function catName(v) { try { return JSON.parse(v).categoryName || "" } catch (e) { return "" } }
    function isExcluded(type, v) {
        const list = filterMap[type] || []
        return type === "Category" ? list.some(x => catName(x) === catName(v)) : list.indexOf(v) >= 0
    }
    /// A filter group's checkbox: 2 all shown, 1 some, 0 none.
    function groupState(type) {
        const n = (filterMap[type] || []).length
        return !n ? 2 : n >= filterValues(type).length ? 0 : 1
    }
    function setFilters(m) { filterMap = m; currentViewId = ""; saveFilters() }
    function saveFilters() {
        calendarAction("setFilters", JSON.stringify({ filters: Object.keys(filterMap).map(k => [k, filterMap[k]]) }))
    }
    function toggleFilter(type, v) {
        const m = Object.assign({}, filterMap), list = (m[type] || []).slice()
        const i = type === "Category" ? list.findIndex(x => catName(x) === catName(v)) : list.indexOf(v)
        if (i >= 0) list.splice(i, 1); else list.push(v)
        if (list.length) m[type] = list; else delete m[type]
        setFilters(m)
    }
    function filterAct(a) {
        if (!a) return
        const m = Object.assign({}, filterMap)
        if (a[0] === "clear") setFilters({})
        else if (a[0] === "toggle") toggleFilter(a[1], a[2])
        else if (a[0] === "all") { delete m[a[1]]; setFilters(m) }
        else if (a[0] === "none") { m[a[1]] = filterValues(a[1]).slice(); setFilters(m) }
    }
    // Teams' rules for what each unchecked value hides (its calendar's
    // filter, V2): an event shows only when every unchecked value lets it.
    // Outlook's IsMeeting when its calendar view gave it, else from Graph.
    function evIsMeeting(e) { return e.is_meeting !== undefined && e.is_meeting !== null ? !!e.is_meeting : e.is_organizer === false || (e.attendees || []).length > 0 }
    function pollVoted(e, vote) { return (e.poll_vote || "").toLowerCase() === vote.toLowerCase() }
    function evRecurring(e) { return ["occurrence", "exception", "seriesMaster"].indexOf(e.event_type) >= 0 }
    function passesFilter(e, type, v) {
        const meeting = evIsMeeting(e), attendee = meeting && !e.is_organizer
        switch (type) {
        case "General": return v !== "Appointments" || meeting || !!e.poll_hold
        case "Meetings":
            switch (v) {
            case "Drafts": return !e.is_draft
            case "Organizer": return !meeting || !e.is_organizer || !!e.is_draft
            case "Accepted": return e.response !== "accepted"
            case "Maybe": return !(attendee && e.response === "tentativelyAccepted")
            case "Followed": return !(attendee && e.response === "following")
            case "DeclinedEvents": return e.response !== "declined"
            case "Canceled": return !e.is_cancelled
            case "NotResponded": return e.response !== "notResponded"
            }
            return true
        case "ShowAs": return (e.show_as || "").toLowerCase() !== v.toLowerCase()
        case "Recurrence": return v === "Single" ? evRecurring(e) : !evRecurring(e)
        // From Outlook's view of the event: the hybrid RSVP's requested
        // attendance, desk bookings and scheduling polls' holds.
        case "InPerson": return v === "Required" ? e.attendance_mode !== "InPersonRequired" : e.attendance_mode === "InPersonRequired"
        case "Reservations": return !e.is_desk_booking
        case "PollHolds":
            switch (v) {
            case "SeeAll": return e.poll_hold !== "OrganizerHold"
            case "VotedYes": return !(e.poll_hold === "AttendeeHold" && pollVoted(e, "Yes"))
            case "VotedNo": return !(e.poll_hold === "AttendeeHold" && pollVoted(e, "No"))
            case "NotVoted": return !(e.poll_hold === "AttendeeHold" && pollVoted(e, "HasNotVoted"))
            }
            return true
        }
        return true
    }
    function passesFilters(e) {
        for (const type in filterMap) {
            const vals = filterMap[type]
            if (type === "Category") {
                const off = vals.map(catName), cats = e.categories || []
                for (const n of off) {
                    const ok = n === "Uncategorized" ? cats.length > 0 : (!cats.length || cats.some(c => off.indexOf(c) < 0))
                    if (!ok) return false
                }
                continue
            }
            for (const v of vals) if (!passesFilter(e, type, v)) return false
        }
        return true
    }
    // The Filter menu (Teams' FilterMenu): Clear filters; Appointments,
    // Meetings ▸, Poll holds ▸, Reservations ▸; Categories ▸, Show as ▸,
    // Recurrence ▸, In-person ▸. Checkboxes keep the menu open.
    function cbIcon(st) { return st === 2 ? "checkbox-checked-20-filled" : st === 1 ? "checkbox-indeterminate-20" : "checkbox-unchecked-20" }
    function fLeaf(type, v, label) { return { label: label, icon: cbIcon(isExcluded(type, v) ? 0 : 2), iconColor: theme.brand, persist: true, act: ["toggle", type, v] } }
    function fUnselect(type) { return { label: qsTr("Unselect all"), persist: true, enabled: groupState(type) !== 0, act: ["none", type] } }
    function fGroup(type, label, sub) {
        const st = groupState(type)
        return { label: label, icon: cbIcon(st), iconColor: theme.brand, persist: true, split: true, splitLabel: qsTr("More %1 options").arg(label), act: [st === 2 ? "none" : "all", type], submenu: sub }
    }
    // Outlook's category colour presets (light theme): [fill, outline].
    readonly property var categoryPresets: [["#F6D1D5", "#C50F1F"], ["#F1D9CC", "#A74109"], ["#FFDDB3", "#8F4E00"], ["#FCEFD3", "#835B00"], ["#CEF0CD", "#0E7A0B"],
        ["#A6E9ED", "#00666D"], ["#E5F1D3", "#405F14"], ["#D4F4FD", "#006A88"], ["#E7E4FB", "#6656D1"], ["#FBDDF0", "#AD2D7E"], ["#D8DFE0", "#657174"],
        ["#94C8D4", "#005B70"], ["#EAE8E8", "#6E6968"], ["#CECCCB", "#474443"], ["#C4C4C4", "#333333"], ["#E9C7CD", "#750B1C"], ["#F9DCD1", "#C43501"],
        ["#CAADA3", "#4D291C"], ["#F5EECE", "#6C5700"], ["#9AD29A", "#085108"], ["#92D1D1", "#003939"], ["#BDD99B", "#294903"], ["#C2D6E7", "#003966"],
        ["#B9A3D3", "#512B7E"], ["#D696C0", "#87105D"]]
    function categoryTag(color) {
        const i = /^preset(\d+)$/.exec(color || "")
        const c = categoryPresets[i ? Number(i[1]) : 13] || categoryPresets[13]
        return { fill: c[0], stroke: c[1] }
    }
    readonly property var filterMenuItems: {
        const m = filterMap
        const meet = [fUnselect("Meetings"), { separator: true }, { group: qsTr("I'm the organizer") }, fLeaf("Meetings", "Organizer", qsTr("Sent")), fLeaf("Meetings", "Drafts", qsTr("Draft")),
            { separator: true }, { group: qsTr("I'm an attendee") }, fLeaf("Meetings", "Accepted", qsTr("Accepted")), fLeaf("Meetings", "DeclinedEvents", qsTr("Declined")),
            fLeaf("Meetings", "Followed", qsTr("Followed")), fLeaf("Meetings", "Maybe", qsTr("Tentative")), fLeaf("Meetings", "Canceled", qsTr("Canceled")), fLeaf("Meetings", "NotResponded", qsTr("Not responded"))]
        const polls = [{ label: qsTr("Organizer holds"), enabled: false }, fLeaf("PollHolds", "SeeAll", qsTr("See all")), { separator: true },
            { label: qsTr("Attendee holds"), enabled: false }, fLeaf("PollHolds", "VotedYes", qsTr("Voted: yes")), fLeaf("PollHolds", "VotedNo", qsTr("Voted: no")), fLeaf("PollHolds", "NotVoted", qsTr("Not voted"))]
        const cats = [fUnselect("Category"), { separator: true }, fLeaf("Category", catValue("Uncategorized"), qsTr("Uncategorized")), { separator: true }]
            .concat(categories.map(c => Object.assign(fLeaf("Category", catValue(c.name), c.name), { tag: categoryTag(c.color) })))
        const showAs = [fUnselect("ShowAs"), { separator: true }, fLeaf("ShowAs", "Free", qsTr("Free")), fLeaf("ShowAs", "WorkingElsewhere", qsTr("Working elsewhere")),
            fLeaf("ShowAs", "Tentative", qsTr("Tentative")), fLeaf("ShowAs", "Busy", qsTr("Busy")), fLeaf("ShowAs", "OOF", qsTr("Out of office"))]
        return [{ label: qsTr("Clear filters"), icon: "dismiss-20", persist: true, enabled: filterApplied, act: ["clear"] }, { separator: true },
            fLeaf("General", "Appointments", qsTr("Appointments")), fGroup("Meetings", qsTr("Meetings"), meet), fGroup("PollHolds", qsTr("Poll holds"), polls),
            fGroup("Reservations", qsTr("Reservations"), [fLeaf("Reservations", "Desk", qsTr("Desk"))]), { separator: true },
            fGroup("Category", qsTr("Categories"), cats), fGroup("ShowAs", qsTr("Show as"), showAs),
            fGroup("Recurrence", qsTr("Recurrence"), [fLeaf("Recurrence", "Single", qsTr("Single")), fLeaf("Recurrence", "Series", qsTr("Series"))]),
            fGroup("InPerson", qsTr("In-person"), [fLeaf("InPerson", "Required", qsTr("Requested")), fLeaf("InPerson", "NotRequired", qsTr("Not requested"))])]
    }
    // The view menu (Teams' CalendarViewTypes): Day ▸ (1 to 7 days), Work
    // week, Week, Month; Split view; Time scale ▸; Saved views ▸.
    function scaleLabel(m) { return m === 60 ? qsTr("60 minutes - Least space for details") : m === 5 ? qsTr("5 minutes - Most space for details") : qsTr("%n minutes", "", m) }
    // Saved views' icons ("charms"): the picker's 36 in its order, and the
    // glyph each shows in the menu (no icon, Pill, Exam and Goal: a dot).
    readonly property var charms: [[0, "No icon", "", qsTr("No icon")], [3, "Plane", "airplane-20", qsTr("Plane")], [4, "Note", "notepad-20", qsTr("Note")], [5, "First aid", "briefcase-medical-20", qsTr("First aid")], [6, "Trophy", "trophy-20", qsTr("Trophy")],
        [7, "Home", "home-20", qsTr("Home")], [8, "Pill", "pill-20", qsTr("Pill")], [9, "Luggage", "luggage-20", qsTr("Luggage")], [11, "Group", "people-20", qsTr("Group")], [12, "Timer", "timer-20", qsTr("Timer")], [13, "Music", "music-note-2-20", qsTr("Music")],
        [15, "Car", "vehicle-car-20", qsTr("Car")], [16, "Star", "star-20", qsTr("Star")], [18, "Person", "person-20", qsTr("Person")], [19, "Balloon", "balloon-20", qsTr("Balloon")], [20, "Fork knife", "food-20", qsTr("Fork knife")], [21, "Heart", "heart-20", qsTr("Heart")],
        [22, "Soccer", "sport-soccer-20", qsTr("Soccer")], [23, "Movie", "movies-and-tv-20", qsTr("Movie")], [25, "Books", "book-open-20", qsTr("Books")], [26, "Cake", "food-cake-20", qsTr("Cake")], [27, "TV", "tv-20", qsTr("TV")],
        [29, "Package delivery", "vehicle-truck-profile-20", qsTr("Package delivery")], [31, "Event", "ticket-diagonal-20", qsTr("Event")], [33, "Credit card", "payment-20", qsTr("Credit card")], [34, "Bike", "vehicle-bicycle-20", qsTr("Bike")],
        [38, "Bus", "vehicle-bus-20", qsTr("Bus")], [42, "Class", "hat-graduation-20", qsTr("Class")], [46, "Gym", "dumbbell-20", qsTr("Gym")], [47, "Island", "beach-20", qsTr("Island")], [50, "Professional", "city-20", qsTr("Professional")],
        [51, "Repair", "wrench-20", qsTr("Repair")], [53, "Sprint", "run-20", qsTr("Sprint")], [55, "Todo", "checkmark-20", qsTr("Todo")], [57, "Exam", "note-edit-20", qsTr("Exam")], [58, "Goal", "target-arrow-20", qsTr("Goal")]]
    function charmMenuIcon(id) {
        const n = Number(id) || 0
        if ([0, 8, 57, 58].indexOf(n) >= 0) return "circle-20-filled"
        const c = charms.find(x => x[0] === n)
        return c ? c[2] : "circle-20-filled"
    }
    readonly property var viewMenuItems: {
        const days = [1, 2, 3, 4, 5, 6, 7].map(n => ({ label: qsTr("%n days", "", n), checked: view === "day" && numDays === n, act: ["days", n] }))
        const scales = [60, 30, 15, 10, 6, 5].map(m => ({ label: scaleLabel(m), checked: timeScale === m, persist: true, act: ["scale", m] }))
        const views = savedViews.map(v => ({ label: v.viewName || "", icon: charmMenuIcon(v.viewIcon), checked: currentViewId === v.id, split: true,
            splitLabel: qsTr("More %1 options").arg(v.viewName || ""), act: ["openView", v.id],
            submenu: [{ label: qsTr("Open"), icon: "open-20", act: ["openView", v.id] }, { label: qsTr("Edit"), icon: "edit-20", act: ["editView", v.id] }, { label: qsTr("Delete"), icon: "delete-20", act: ["deleteView", v.id] }] }))
        if (views.length) views.push({ separator: true })
        views.push({ label: qsTr("Save current view"), indent: true, enabled: savedViews.length < 10, act: ["saveView"] })
        return [{ label: qsTr("Day"), icon: "calendar-day-20", checked: view === "day", split: true, splitLabel: qsTr("Expand to see more Day options"), act: ["view", "day"], submenu: days },
            { label: qsTr("Work week"), icon: "calendar-work-week-20", checked: view === "workweek", act: ["view", "workweek"] },
            { label: qsTr("Week"), icon: "calendar-week-numbers-20", checked: view === "week", act: ["view", "week"] },
            { label: qsTr("Month"), icon: "calendar-month-20", checked: view === "month", act: ["view", "month"] },
            { separator: true },
            { label: qsTr("Split view"), icon: "square-multiple-20", checked: splitView && canSplit, enabled: canSplit, act: ["split"] },
            { separator: true },
            { label: qsTr("Time scale"), icon: "arrow-autofit-height-20", secondary: qsTr("%n minutes", "", timeScale), chevron: false, enabled: !monthView, submenu: scales },
            { label: qsTr("Saved views"), icon: "save-20", checked: !!currentViewId, submenu: views }]
    }
    readonly property var rangeTypes: ({ day: 1, week: 2, workweek: 3, month: 4 })
    function viewAct(a) {
        if (!a) return
        switch (a[0]) {
        case "view": currentViewId = ""; view = a[1]; break
        case "days":
            currentViewId = ""
            if (numDays !== a[1]) { numDays = a[1]; calendarAction("setSurface", JSON.stringify({ numDaysInDayRange: a[1] })) }
            if (view !== "day") view = "day"; else emitRange()
            break
        case "split": splitView = !splitView; currentViewId = ""; break
        case "scale":
            if (timeScale !== a[1]) { timeScale = a[1]; calendarAction("setSurface", JSON.stringify({ timeScaleSetting: a[1] })) }
            break
        case "openView": applySavedView(a[1]); break
        case "editView": saveViewDialog.openFor(savedViews.find(v => v.id === a[1]) || null); break
        case "deleteView": {
            const v = savedViews.find(x => x.id === a[1])
            if (v) { deleteViewDialog.view = v; deleteViewDialog.open() }
            break
        }
        case "saveView": saveViewDialog.openFor(null); break
        }
    }
    function applySavedView(id) {
        const v = savedViews.find(x => x.id === id)
        if (!v) return
        if (v.numDaysInDayRange) numDays = Math.max(1, Math.min(7, v.numDaysInDayRange))
        if (v.filterState) {
            try {
                const ent = typeof v.filterState === "string" ? JSON.parse(v.filterState) : v.filterState, m = {}
                for (const e of ent) if (e && e.length === 2) m[e[0]] = e[1]
                filterMap = m
            } catch (err) {}
        }
        splitView = !!v.splitView
        const t = ({ 1: "day", 2: "week", 3: "workweek", 4: "month" })[v.dateRangeType] || "workweek"
        if (view !== t) view = t; else emitRange()
        currentViewId = id
    }
    function saveView(existing, name, icon) {
        const v = existing ? Object.assign({}, existing, { viewName: name, viewIcon: String(icon) })
            : { selectedCalendarIds: calendarId ? [calendarId] : [], dateRangeType: rangeTypes[view] || 3, splitView: false, viewName: name, chosenHotkey: null,
                numDaysInDayRange: numDays, viewIcon: String(icon), filterState: JSON.stringify(Object.keys(filterMap).map(k => [k, filterMap[k]])) }
        calendarAction("saveView", JSON.stringify({ view: v }))
    }
    /// Teams' toolbar overflow: Filter goes into "More options" when the
    /// toolbar is short of room (measured on winpc: inline from a 1321 px
    /// calendar, 28.5 px or more between the date and the view button).
    readonly property bool filterInline: !copilotOpen && bar.dabX - 12 - (viewButton.width + filterBtn.width + 32 + 1 + meetRow.width + newRow.width + 5 * rightRow.spacing)
                                         - (leftRow.x + leftRow.width) >= 28.5
    /// Copilot's pane in the calendar (Teams' "Chat with Copilot").
    property bool copilotOpen: false
    readonly property real copilotWidth: copilotOpen ? 580 : 0
    signal rangeChanged(string startUtc, string endUtc)
    signal joinMeeting(string joinUrl, string subject)
    /// Meet now's Start meeting: its pre-join (Teams' Meet now pre-join,
    /// the title to edit).
    signal startMeetNow(string joinUrl, string subject)
    signal createEvent(string subject, string startUtc, string endUtc, string attendees, bool teamsMeeting)
    signal openMeetingChat(string joinUrl, string subject)
    signal deleteEvent(string id)
    signal updateEvent(string id, string subject, string startUtc, string endUtc)
    /// backend.calendarAction(op, argsJson).
    signal calendarAction(string op, string argsJson)
    signal searchPeople(string query)
    /// Join with an ID: the meeting ID and passcode.
    signal joinWithId(string meetingId, string passcode)

    /// An hour's height for the time scale (Teams: 40 px slots at 60 and
    /// 30 minutes, else 30 px slots).
    readonly property real hourHeight: ({ 60: 40, 30: 80, 15: 120, 10: 180, 6: 300, 5: 360 })[timeScale] || 80
    readonly property real slotHeight: hourHeight * timeScale / 60
    readonly property int gutter: 48
    readonly property int days: view === "day" ? numDays : view === "week" ? 7 : view === "month" ? 7 * monthWeeks : 5
    readonly property bool monthView: view === "month"
    /// Month view: the weeks shown (the month's, Sunday first).
    readonly property int monthWeeks: {
        const f = new Date(focusMonth.getFullYear(), focusMonth.getMonth(), 1)
        const last = new Date(f.getFullYear(), f.getMonth() + 1, 0)
        return Math.ceil((f.getDay() + last.getDate()) / 7)
    }
    property date focusMonth: new Date()
    property date now: new Date()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // ── harness ─────────────────────────────────────────────────────────
    function eventBySubject(subject) { return root.events.find(e => e.subject === subject) }
    function cardForTest(subject) {
        const e = eventBySubject(subject)
        if (!e) return false
        details.show(e, null)
        return true
    }
    function editForTest(newTitle) { openPage(details.ev); details.close(); form.typeTitleForTest(newTitle) }
    function saveForTest() { form.submitForTest() }
    function deleteForTest() { details.confirming = true }
    /// Where each visible text, glyph and line sits (x y w h, from base's
    /// top left): the card's (details.background) or the page's rows, to
    /// set against Teams' measurements.
    function layoutForTest(item, base) {
        const out = []
        function walk(it) {
            for (const c of it.children) {
                if (!c.visible || c.opacity === 0) continue
                const p = c.mapToItem(base, 0, 0)
                const g = [Math.round(p.x * 10) / 10, Math.round(p.y * 10) / 10, Math.round(c.width * 10) / 10, Math.round(c.height * 10) / 10].join(" ")
                if (typeof c.text === "string" && c.text) out.push("text " + JSON.stringify(c.text.slice(0, 50)) + " " + g + (c.font ? " " + c.font.pixelSize + "/" + c.font.weight : ""))
                else if (typeof c.name === "string" && c.name && c.size !== undefined) out.push("icon " + c.name + " " + g)
                else if (c.height <= 1.5 && c.width > 20 && c.color !== undefined) out.push("line " + g)
                else if (c.border && c.border.width > 0 && c.width > 20 && c.height > 20) out.push("box " + g)
                else if (c.depth !== undefined && c.radius !== undefined && c.width > 20 && c.height > 20) out.push("card " + g)
                walk(c)
            }
        }
        walk(item)
        return out
    }
    function cardLayoutForTest() { return layoutForTest(details.contentItem, details.background) }
    function cancelMenuForTest() { cancelScopeMenu.openFor(cancelBtn) }
    property alias cancelScopeMenuForTest: cancelScopeMenu
    function confirmDeleteForTest() { root.deleteEvent(details.ev.id); details.close() }
    function pageForTest(subject, scope) { const e = eventBySubject(subject); if (e) openPage(e, scope || ""); return !!e }
    function respondForTest(response, series, note) { details.respond(response, series, note) }
    function monthDebug() { return { events: root.events.length, shown: root.shown.length, start: root.iso(root.start), days: root.days, weeks: root.monthWeeks, laid: monthArea.weeksLaid.map(w => w.bars.length), cellH: monthArea.cellH, rows: monthArea.rowsPerCell } }
    property alias formForTest: form
    property alias detailsForTest: details
    property alias joinIdForTest: joinId
    property alias meetNowForTest: meetNowDialog
    property alias filterMenuForTest: filterMenu
    property alias moreMenuForTest: moreMenu
    property alias viewMenuForTest: viewMenu
    property alias dabChipsForTest: dabChips
    property alias saveViewForTest: saveViewDialog
    property alias charmPickerForTest: charmPicker
    property alias composeForTest: composeHost
    property alias copilotForTest: copilotHost
    function filterStateForTest() { return JSON.stringify({ inline: filterInline, applied: filterApplied, map: filterMap, shown: shown.length, events: events.length, timeScale: timeScale, hourHeight: hourHeight, numDays: numDays, days: days, views: savedViews.map(v => v.viewName + ":" + v.id), current: currentViewId, categories: categories.length, bar: bar.width }) }

    /// Alt+N: schedule a meeting.
    function newMeeting() { openForm(null, [], null) }
    /// The form with people (comma-separated mails) and times filled in (a
    /// suggested reply's meeting: the chat's members, the proposed times).
    function newMeetingWith(attendees, startIso, endIso) {
        const s = startIso ? new Date(startIso) : null
        const people = (attendees || "").split(/[,;]/).map(a => a.trim()).filter(a => a.indexOf("@") > 0).map(a => ({ address: a, name: a }))
        openForm(s && !isNaN(s) ? s : null, people, null)
        const e = endIso ? new Date(endIso) : null
        if (s && e && !isNaN(e) && e > s) form.setTimesForTest(s, e)
    }
    /// Schedule a meeting from a channel's header: the form with the channel.
    function newChannelMeeting(teamId, teamName, channelId, channelName) {
        openForm(null, [], { teamId: teamId, teamName: teamName, channelId: channelId, channelName: channelName })
    }
    /// An agent's meeting opened in the form (Teams' Edit on a Channel
    /// Agent's meeting: the scheduling form with its title, time, details
    /// and channel).
    function newAgentMeeting(channel, subject, startIso, minutes, body) {
        const s = startIso ? new Date(startIso) : null
        openForm(s && !isNaN(s) ? s : null, [], channel)
        if (s && !isNaN(s)) form.setTimesForTest(s, new Date(s.getTime() + (minutes || 30) * 60000))
        form.prefill(subject, body)
    }
    function openForm(at, people, channel) {
        formLayer.visible = true
        form.detail = ({})
        form.openNew(at, people, channel)
    }
    /// New ▸ Virtual appointment: the meeting form with Teams' Virtual
    /// appointment template (external guests, its options).
    function openVirtualAppointment() {
        formLayer.visible = true
        form.detail = ({})
        form.openVirtualAppointment(null)
    }
    function openNewMenuForTest() { newMenu.open() }
    function closeNewMenuForTest() { newMenu.close() }
    function liveEventDialogForTest() { return liveEventsRetiring }
    function newLiveEventForTest() { return newLiveEvent }
    /// The event page: yours to edit, or an invitation to answer.
    /// The event page; for your series' event, which events it edits
    /// ("occurrence", "following", "series"; the card's Edit menu).
    function openPage(e, scope) {
        const ev = withTeam(e)
        formLayer.visible = true
        form.detail = ({})
        form.openEvent(ev, !!ev.is_organizer, scope || "")
        calendarAction("detail", JSON.stringify({ id: ev.id }))
        // Outlook's form reads the rest from Outlook (GetCalendarEvent) and
        // a Teams meeting's options (Facilitator).
        if (ev.is_organizer && !ev.channel_id) {
            calendarAction("outlookEvent", JSON.stringify({ id: ev.id }))
            if (ev.join_url) calendarAction("eventOptions", JSON.stringify({ id: ev.id, joinUrl: ev.join_url }))
        }
    }
    /// A channel meeting's team and channel names, from the teams list.
    function withTeam(e) {
        if (!e || !e.channel_id) return e
        const ev = Object.assign({}, e)
        for (const t of root.teams || []) {
            const c = (t.channels || []).find(c => c.id === e.channel_id)
            if (c) { ev.team_id = t.id; ev.team_name = t.name; ev.channel_name = c.name; break }
        }
        return ev
    }
    /// backend.calendarActionDone.
    property string mtTimeZone: ""
    function actionDone(op, result, error) {
        const r = result ? JSON.parse(result) : {}
        if (op === "detail" && !error && formLayer.visible && form.event && r.id === form.event.id) form.detail = r
        else if (op === "outlookEvent") { if (!error && form.event && r.id === form.event.id) form.outlookInfo = r }
        else if (["findTimes", "attachFile", "deleteAttachment", "attachmentFile", "eventOptions", "setEventOptions", "eventFacilitator",
                  "uploadShare", "shareLink", "graphics", "graphicsThemes", "graphicsFile", "emailReminders", "newCategory",
                  "driveFolders", "createFolder", "editorOptions", "setEditorOptions"].indexOf(op) >= 0) {
            form.actionDone(op, r, error)
            if (op === "newCategory" && !error) loadPrefs()
        }
        else if (op === "prefs" && !error) applyPrefs(r)
        else if (op === "calendars" && !error) { calendarList = r.calendars || []; otherSelected = otherSelected.filter(id => calendarList.some(c => c.id === id)); loadExtraEvents() }
        else if (op === "calendarEvents" && !error) { if (r.start === rangeStartIso) extraEvents = r.events || [] }
        else if (op === "saveView" && !error && r.view) {
            const v = r.view, list = savedViews.filter(x => x.id !== v.id)
            const i = savedViews.findIndex(x => x.id === v.id)
            if (i >= 0) list.splice(i, 0, v); else list.push(v)
            savedViews = list
            currentViewId = v.id
        }
        else if (op === "deleteView" && !error) { savedViews = savedViews.filter(x => x.id !== r.id); if (currentViewId === r.id) currentViewId = "" }
        else if (op === "propose" && !error) details.close()
        else if (op === "availability" && !error) { form.freeBusy = r.freeBusy || {}; if (r.timeZone) mtTimeZone = r.timeZone }
        else if ((op === "schedule" || op === "update" || op === "cancel") && !error) formLayer.visible = false
        else if (op === "joinById" && !error && r.joinUrl) root.joinMeeting(r.joinUrl, r.subject || qsTr("Meeting"))
        else if (op === "meetNow" && !error && r.joinUrl) {
            if (meetNowDialog.linkOnly) { meetNowDialog.link = r.joinUrl } else { meetNowDialog.close(); root.startMeetNow(r.joinUrl, r.subject || qsTr("Meeting")) }
        }
    }

    // ── dates ───────────────────────────────────────────────────────────
    function mondayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - (m.getDay() + 6) % 7)
        return m
    }
    function sundayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        m.setDate(m.getDate() - m.getDay())
        return m
    }
    function startFor(d) {
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        if (view === "month") { focusMonth = new Date(day.getFullYear(), day.getMonth(), 1); return sundayOf(focusMonth) }
        return view === "day" ? day : view === "week" ? sundayOf(day) : mondayOf(day)
    }
    function dayAt(i) { const d = new Date(start); d.setDate(d.getDate() + i); return d }
    function shift(n) {
        if (view === "month") { const m = new Date(focusMonth.getFullYear(), focusMonth.getMonth() + n, 1); start = startFor(m); return }
        const d = new Date(start); d.setDate(d.getDate() + n * (view === "day" ? numDays : 7)); start = d
    }
    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function midnight(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function iso(d) { return d.toISOString().replace(/\.\d+Z$/, "Z") }
    /// Local time with its offset, as Teams' form sends times.
    function isoLocal(d) {
        const p = n => (n < 10 ? "0" : "") + n
        const off = -d.getTimezoneOffset(), sign = off >= 0 ? "+" : "-", a = Math.abs(off)
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "T" + p(d.getHours()) + ":" + p(d.getMinutes()) + ":00" + sign + p(Math.floor(a / 60)) + ":" + p(a % 60)
    }
    // The range shown, from the view itself: a handler can run before the
    // `days` binding catches up with a view change (Month asked for one
    // day after Day). Coalesced, so a view and date change ask once.
    function spanDays() {
        if (view === "day") return numDays
        if (view === "week") return 7
        if (view !== "month") return 5
        const f = new Date(focusMonth.getFullYear(), focusMonth.getMonth(), 1)
        return 7 * Math.ceil((f.getDay() + new Date(f.getFullYear(), f.getMonth() + 1, 0).getDate()) / 7)
    }
    function emitRange() { Qt.callLater(emitRangeNow) }
    function emitRangeNow() {
        const end = new Date(start); end.setDate(end.getDate() + spanDays())
        rangeStartIso = iso(start); rangeEndIso = iso(end)
        rangeChanged(iso(start), iso(end))
        loadExtraEvents()
    }
    onStartChanged: emitRange()
    // Leaving Month: the week of today when it's in the month shown, else
    // of the month's first day.
    property string prevView: view
    onViewChanged: {
        const fromMonth = prevView === "month"
        prevView = view
        const n = new Date()
        const anchor = view === "month" ? start
            : fromMonth ? (n.getMonth() === focusMonth.getMonth() && n.getFullYear() === focusMonth.getFullYear() ? n : focusMonth)
            : view === "day" && todayIndex >= 0 ? n : start
        start = startFor(anchor)
        emitRange()
    }
    Component.onCompleted: { emitRange(); loadPrefs() }
    function loadPrefs() {
        calendarAction("prefs", "{}"); calendarAction("calendars", "{}")
        try { otherSelected = JSON.parse(calendarLocal.selectedCalendars || "[]") } catch (e) { otherSelected = [] }
    }
    readonly property string rangeLabel: {
        if (monthView) return theme.fmtDate(focusMonth, "MMMM yyyy")
        const a = start, b = dayAt(days - 1)
        if (days === 1) return theme.fmtDate(a, "MMMM d, yyyy")
        if (a.getMonth() === b.getMonth()) return theme.fmtDate(a, "MMMM d") + "–" + b.getDate() + ", " + b.getFullYear()
        if (a.getFullYear() === b.getFullYear()) return theme.fmtDate(a, "MMMM d") + " – " + theme.fmtDate(b, "MMMM d, yyyy")
        return theme.fmtDate(a, "MMMM d, yyyy") + " – " + theme.fmtDate(b, "MMMM d, yyyy")
    }

    // ── events laid out ─────────────────────────────────────────────────
    function evStart(e) { return new Date(e.start_utc) }
    function evEnd(e) { return new Date(e.end_utc) }
    /// Teams' rule for the all-day strip: all-day events, and events over
    /// several days that run a full day or start or end at midnight.
    function inStrip(e) {
        if (e.is_all_day) return true
        const s = evStart(e), en = evEnd(e)
        if (sameDay(s, new Date(en - 1))) return false
        return (en - s) >= 86400000 || (s.getHours() === 0 && s.getMinutes() === 0) || (en.getHours() === 0 && en.getMinutes() === 0)
    }
    readonly property var shown: (showCalendar ? events : []).concat(extraEvents.filter(e => otherSelected.indexOf(e.calendar_id) >= 0))
        .filter(e => (!e.is_cancelled || e.is_organizer === false) && passesFilters(e))
    // One day's timed pieces in side-by-side lanes (Teams: earlier first,
    // then shorter).
    function layDay(list0, d0, d1) {
        const list = []
        for (const e of list0) {
            if (inStrip(e)) continue
            const s = evStart(e), en = evEnd(e)
            if (en <= d0 || s >= d1) continue
            const a = Math.max(0, (s - d0) / 60000), b = Math.min(1440, (en - d0) / 60000)
            list.push({ ev: e, s: a, e: Math.max(b, a + 15), lane: 0, lanes: 1 })
        }
        list.sort((x, y) => x.s - y.s || x.e - y.e)
        let cluster = [], laneEnds = [], clusterEnd = -1
        const close = () => { for (const p of cluster) p.lanes = laneEnds.length; cluster = []; laneEnds = [] }
        for (const p of list) {
            if (p.s >= clusterEnd) { close(); clusterEnd = -1 }
            let lane = laneEnds.findIndex(t => t <= p.s)
            if (lane < 0) { lane = laneEnds.length; laneEnds.push(p.e) } else laneEnds[lane] = p.e
            p.lane = lane
            cluster.push(p)
            clusterEnd = Math.max(clusterEnd, p.e)
        }
        close()
        return list
    }
    /// Split view: per calendar, per day, its pieces.
    readonly property var splitPieces: {
        const out = []
        if (!splitActive) return out
        for (let k = 0; k < splitCalendars.length; k++) {
            const id = splitCalendars[k].id
            const mine = shown.filter(e => (e.calendar_id || "") === id)
            for (let i = 0; i < days; i++) for (const p of layDay(mine, dayAt(i), dayAt(i + 1))) out.push(Object.assign({ col: k * days + i }, p))
        }
        return out
    }
    /// Timed pieces per day column: [{ev, s, e (minutes), lane, lanes}].
    readonly property var dayPieces: {
        const out = []
        if (monthView) return out
        for (let i = 0; i < days; i++) out.push(layDay(shown, dayAt(i), dayAt(i + 1)))
        return out
    }
    /// The all-day strip's bars: [{ev, c0, c1, row}].
    readonly property var stripBars: {
        const bars = []
        if (monthView) return bars
        const rows = []
        const list = shown.filter(inStrip).sort((a, b) => evStart(a) - evStart(b) || evEnd(b) - evEnd(a))
        for (const e of list) {
            const s = evStart(e), en = evEnd(e)
            const c0 = Math.max(0, Math.floor((midnight(s) - start) / 86400000))
            const c1 = Math.min(days - 1, Math.floor((midnight(new Date(en - 1)) - start) / 86400000))
            if (c1 < 0 || c0 > days - 1) continue
            let row = rows.findIndex(r => r < c0)
            if (row < 0) { row = rows.length; rows.push(c1) } else rows[row] = c1
            bars.push({ ev: e, c0: c0, c1: c1, row: row })
        }
        return bars
    }
    readonly property int stripRows: stripBars.reduce((m, b) => Math.max(m, b.row + 1), 0)
    readonly property real stripHeight: Math.max(42, stripRows * 21 + 4)
    /// A day under an all-day event that keeps you busy.
    function busyDay(i) { return stripBars.some(b => b.c0 <= i && b.c1 >= i && (b.ev.show_as === "busy" || b.ev.show_as === "oof")) }
    function pastDay(i) { return midnight(dayAt(i)) < midnight(now) && todayIndex >= 0 }
    readonly property int todayIndex: { for (let i = 0; i < days; i++) if (sameDay(dayAt(i), now)) return i; return -1 }
    /// Teams' calendar lays out wide above 1550 px (its hosted calendar's
    /// width): full day names and the week focused on today.
    readonly property bool wideLayout: root.width > 1550
    /// Column widths, as Teams: equal, except in the wide layout for the week
    /// holding today, where today takes 1.5 and tomorrow 1.3 of an equal
    /// share and the other days split the rest, a past day getting two
    /// thirds of a later one. Side-by-side events never widen a day.
    readonly property var colWidths: {
        const W = Math.max(0, gridArea.width - gutter), n = days
        if (monthView) return []
        // Split view: each calendar's block of days, a day at least 100 px,
        // scrolling sideways when they don't fit.
        if (splitActive) return Array(nCols).fill(Math.max(100, W / nCols))
        if (n === 1 || todayIndex < 0 || !wideLayout) return Array(n).fill(W / n)
        const u = W / n, w = Array(n).fill(0), t = todayIndex, tm = t + 1 < n ? t + 1 : -1
        w[t] = 1.5 * u
        let left = W - w[t], weights = 0
        if (tm >= 0) { w[tm] = 1.3 * u; left -= w[tm] }
        const weight = i => i < t ? 2 : 3
        for (let i = 0; i < n; i++) if (i !== t && i !== tm) weights += weight(i)
        for (let i = 0; i < n; i++) if (i !== t && i !== tm) w[i] = weights > 0 ? Math.max(0, left) * weight(i) / weights : 0
        return w
    }
    /// Columns: the days, or in Split view each calendar's days in turn.
    readonly property int nCols: splitActive ? splitCalendars.length * days : days
    function dayOfCol(c) { return splitActive ? c % days : c }
    readonly property real splitHead: splitActive ? 56.67 : 0
    readonly property real gridWidth: gutter + colWidths.reduce((a, b) => a + b, 0)
    readonly property var splitStripBars: splitActive
        ? stripBars.map(b => { const k = Math.max(0, splitCalendars.findIndex(c => c.id === (b.ev.calendar_id || ""))); return Object.assign({}, b, { c0: b.c0 + k * days, c1: b.c1 + k * days }) })
        : stripBars
    function colX(i) { let x = gutter; for (let k = 0; k < i; k++) x += colWidths[k] || 0; return x }
    function colW(i) { return colWidths[i] || 0 }

    // The hosted calendar's palette, light and dark (Teams' Outlook calendar
    // frame, measured on winpc 2026-11-23 with Teams in Light and Dark):
    // the toolbar, days and month cells on neutralPrimarySurface, past days
    // and the hours outside the working day on neutralLighterAlt, the side
    // pane #FFFFFF/#0F0F0F, hour, header and month lines neutralTertiaryAlt,
    // the time scale's dashed lines #EBEBEB/#141414, the mini month's
    // shown range colorBrandBackground2Hover. High contrast (measured
    // 2026-11-23) is Teams' "contrast" palette for the frame: days and
    // past days #000000, lines #5C5C5C, dashes #141414; the mini month
    // keeps dark's range #383966 and a #4F52B2 today.
    readonly property color calDay: theme.pick("#FFFFFF", "#292929", "#000000")
    readonly property color calOff: theme.pick("#FAFAFA", "#242424", "#000000")
    readonly property color calLine: theme.pick("#D1D1D1", "#5C5C5C", "#5C5C5C")
    readonly property color calDash: theme.pick("#EBEBEB", "#141414", "#141414")
    readonly property color calPane: theme.pick("#FFFFFF", "#0F0F0F", "#000000")
    readonly property color calRange: theme.pick("#DCE0FA", "#383966", "#383966")
    /// The peek card's lines and edge (neutralLight; #5C5C5C in high
    /// contrast) and outlined buttons' edges.
    readonly property color cardLine: theme.pick("#F0F0F0", "#141414", "#5C5C5C")
    readonly property color cardEdge: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
    readonly property color calLink: theme.pick("#4F52B2", "#7F85F5", "#7F85F5")
    /// A day under an all-day busy event: the calendar colour at 10 % over
    /// the day, its hours outside the working day and its header (measured
    /// 2026-11-23: light #EEEFF9 and #EAEBF5, dark #32323E and #2D2D39,
    /// high contrast #1A1800).
    function dayFill(busy, under) { return busy ? tint(calPrimary, under) : under }

    // ── Event colours, as Outlook's hosted calendar works them out (its
    // bundle: the calendar's colour scheme, the tile fill, edge and text,
    // and the show-as bar). The default calendar's colour is the theme's
    // themePrimary (#5B5FC7, dark #7F85F5); its shades come from Fluent's
    // shade generator, which in dark darkens where light lightens. Measured
    // on winpc 2026-11-23: light busy #C7C9EE, past busy #E1E1F6 with
    // #555555 text and a #C7C9EE bar; dark past busy #26284A with #A5A5A5
    // text and a #4C5093 bar; canceled #FFFFFF/#292929 at 75 %. High
    // contrast works the same way as dark with Teams' contrast themePrimary
    // #FFF200 on #000000 days (measured 2026-11-23: busy #999100 and free,
    // tentative and ended #4D4900 at 90 %, text #000000 / #E6E6E6, Month
    // #FFFFFF, ended #BEBEBE; bars #FFF200 at 90 %).
    readonly property color calPrimary: theme.pick("#5B5FC7", "#7F85F5", "#FFF200")
    /// Away (show as Out of office): the palette's freeBusyAwayColor.
    readonly property color awayColor: theme.pick("#B4009E", "#F500D8", "#F500D8")
    /// [calLighterAlt, calLighter, calLight, calTertiary, calSecondary].
    readonly property var calShades: [1, 2, 3, 4, 5].map(k => shadeOf(calPrimary, k, theme.dark))
    function shadeOf(base, k, dark) {
        const S = [.96, .84, .7, .4, .12], U = [.1, .24, .44]
        const L = [.88, .77, .66, .55, .44, .33, .22, .11], D = [.11, .22, .33, .44, .55, .66, .77, .88]
        const c = Qt.color(base), i = k - 1, l = c.hslLightness
        let h = Math.max(0, c.hsvHue), sat = c.hsvSaturation, v = c.hsvValue
        const lighten = t => { sat = sat - sat * t; v = v + (1 - v) * t }
        const darken = t => { v = v - v * t }
        const up = dark ? darken : lighten, down = dark ? lighten : darken
        if (l > .94) down(D[i])
        else if (l < .2) up(L[i])
        else if (i < S.length) up(S[i])
        else down(U[i - S.length])
        return Qt.hsva(h, Math.max(0, Math.min(1, sat)), Math.max(0, Math.min(1, v)), 1)
    }
    function shade(name) { return calShades[["lighterAlt", "lighter", "light", "tertiary", "secondary"].indexOf(name)] }
    function alpha(c, a) { const q = Qt.color(c); return Qt.rgba(q.r, q.g, q.b, a) }
    /// `top` at 10 % opacity over the opaque `under`, as the hosted
    /// calendar's layer composites it (alpha 26/255, rounded).
    function tint(top, under) {
        const t = Qt.color(top), u = Qt.color(under), a = 26 / 255, f = (x, y) => Math.round(255 * (y + a * (x - y))) / 255
        return Qt.rgba(f(t.r, u.r), f(t.g, u.g), f(t.b, u.b), 1)
    }
    /// `top` at `a` over the opaque `under`, as the bundle composites (floored).
    function over(top, a, under) {
        const t = Qt.color(top), u = Qt.color(under), f = (x, y) => Math.floor(a * x * 255 + (1 - a) * y * 255) / 255
        return Qt.rgba(f(t.r, u.r), f(t.g, u.g), f(t.b, u.b), 1)
    }
    function luminance(c) {
        const f = x => x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
    function contrast(a, b) { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) }
    /// Text on a tile: the grey nearest the fill (in steps of 5 from black
    /// or white) that keeps `target` contrast.
    function greyOn(bg, target) {
        const b = Qt.color(bg), grey = n => Qt.rgba(n / 255, n / 255, n / 255, 1)
        const darkText = contrast(b, grey(255)) < contrast(b, grey(0))
        let n = darkText ? 0 : 255
        for (let d = 0; d < 51; d++) {
            const e = darkText ? n + 5 : n - 5
            if (contrast(grey(e), b) < target) break
            n = e
        }
        return grey(n)
    }

    // How an event's left bar and fill look for its show-as and your answer.
    function isTentative(e) { return e.show_as === "tentative" || (!e.is_organizer && (e.response === "notResponded" || e.response === "none" || e.response === "tentativelyAccepted")) }
    /// Teams dims events that have ended (the calendar's "dim past events").
    function isPast(e) { return !!e.end_utc && evEnd(e) <= now }
    function isCanceled(e) { return !!e.is_cancelled || e.response === "declined" }
    function fillOf(e) {
        if (!e) return "transparent"
        if (isCanceled(e)) return alpha(calDay, .75)
        const past = isPast(e), d = theme.dark
        const light = isTentative(e) || e.show_as === "free" || e.show_as === "tentative" || e.show_as === "workingElsewhere"
        return alpha(light ? shade(d ? (past ? "lighter" : "light") : (past ? "lighterAlt" : "lighter"))
                           : shade(d ? (past ? "light" : "tertiary") : (past ? "lighter" : "light")), .9)
    }
    /// The tile text: grey with 8:1 contrast on the fill (11:1 in Month),
    /// 5.5:1 once past, 6:1 when canceled.
    function textOf(e, month) {
        if (!e) return theme.text
        const f = Qt.color(fillOf(e))
        return greyOn(over(f, f.a, calDay), isPast(e) ? 5.5 : isCanceled(e) ? 6 : month ? 11 : 8)
    }
    /// A canceled event's tile edge (top, right and bottom).
    function edgeOf(e) {
        if (!e) return "transparent"
        const d = theme.dark
        return alpha(isPast(e) ? shade(d ? "tertiary" : "light") : shade(d ? "secondary" : "tertiary"), .9)
    }
    /// The show-as bar: the calendar colour, dimmed once past; a free
    /// event's edge calLight once past, a canceled one's its tile edge.
    function barOf(e) {
        if (!e) return calPrimary
        if (isCanceled(e)) return edgeOf(e)
        if (e.show_as === "oof") { const a = awayColor; return alpha(isPast(e) ? shadeOf(a, theme.dark ? 4 : 3, theme.dark) : a, .9) }
        if (e.show_as === "free") return alpha(isPast(e) ? shade("light") : calPrimary, .9)
        return alpha(isPast(e) ? shade(theme.dark ? "tertiary" : "light") : calPrimary, .9)
    }
    function joinable(e) { return !!e.join_url && now >= new Date(evStart(e) - 5 * 60000) && now < evEnd(e) }
    /// Meetings whose call is going on (the join bar's list, and yours).
    readonly property var liveThreads: (backend.liveMeetingsJson ? JSON.parse(backend.liveMeetingsJson) : []).map(m => (m.threadId || "").toLowerCase())
        .concat(backend.callState !== "" && backend.callThreadId ? [backend.callThreadId.toLowerCase()] : [])
    function isLive(e) {
        if (!e.join_url || !liveThreads.length) return false
        let u = e.join_url
        try { u = decodeURIComponent(u) } catch (err) {}
        u = u.toLowerCase()
        return liveThreads.some(t => t && u.indexOf(t) >= 0)
    }

    Rectangle { anchors.fill: parent; color: root.calDay }

    // ── side pane: title, month, calendars ──────────────────────────────
    Rectangle {
        id: pane
        visible: root.paneShown
        width: visible ? 235 : 0; height: parent.height
        color: root.calPane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.calLine }
        Text { x: 16; y: 19; text: qsTr("Calendar"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Item {
            id: month
            x: 8; y: 78; width: 219; height: 230
            property date shown: new Date(root.start.getFullYear(), root.start.getMonth(), 1)
            readonly property date first: { const d = new Date(shown); d.setDate(1 - d.getDay()); return d }
            readonly property int weeks: {
                const last = new Date(shown.getFullYear(), shown.getMonth() + 1, 0)
                return Math.ceil((first.getDay() + (last - first) / 86400000 + 1) / 7)
            }
            Text { x: 24; y: 0; text: theme.fmtDate(month.shown, "MMMM yyyy"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; y: -4
                Repeater {
                    model: [{ icon: "chevron-left-20", d: -1, l: qsTr("Previous month") }, { icon: "chevron-right-20", d: 1, l: qsTr("Next month") }]
                    Rectangle {
                        id: mFill
                        required property var modelData
                        width: 28; height: 28; radius: theme.radius
                        color: mh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16; color: theme.onFill(mFill, theme.textStrong); rotation: 90 }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const d = new Date(month.shown); d.setMonth(d.getMonth() + parent.modelData.d); month.shown = d } }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.l
                    }
                }
            }
            Row {
                y: 28
                Repeater {
                    model: [0, 1, 2, 3, 4, 5, 6].map(i => Qt.locale().dayName(i, Locale.NarrowFormat))
                    Text { required property string modelData; width: 28; horizontalAlignment: Text.AlignHCenter; text: modelData; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
            }
            Grid {
                y: 48
                columns: 7
                Repeater {
                    model: month.weeks * 7
                    Item {
                        required property int index
                        readonly property date day: { const d = new Date(month.first); d.setDate(d.getDate() + index); return d }
                        readonly property bool today: root.sameDay(day, root.now)
                        readonly property bool inRange: root.monthView ? false : root.view === "day" ? root.sameDay(day, root.start)
                            : day >= root.sundayOf(root.start) && day < root.dayAt(root.days + (root.view === "workweek" ? 1 : 0))
                        width: 28; height: 28
                        Rectangle { id: rFill; visible: parent.inRange; anchors.fill: parent; color: root.calRange }
                        Rectangle { id: tFill; visible: parent.today; anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: theme.hc(theme.brandFill, "#4F52B2") }
                        Text {
                            anchors.centerIn: parent
                            text: parent.day.getDate()
                            font.family: theme.font; font.pixelSize: theme.small
                            font.weight: parent.today ? Font.DemiBold : Font.Normal
                            // Every date in the text colour, the next month's too (Teams).
                            color: theme.onFill([tFill, rFill], parent.today ? "white" : theme.text)
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.start = root.startFor(parent.day) }
                        Accessible.role: Accessible.Button
                        Accessible.name: theme.longDateNoYear(day)
                    }
                }
            }
        }
        // Your calendars, as Teams' pane lists them: My calendars, then
        // Groups; collapsed it shows the ticked ones, "Show all" the rest.
        Flickable {
            x: 16; y: 340; width: parent.width - 32; height: parent.height - 340
            contentHeight: calCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: calCol
                width: parent.width
                spacing: 6
                Text { text: qsTr("My calendars"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                CalRow { label: qsTr("Calendar"); on: root.showCalendar; onToggled: root.showCalendar = !root.showCalendar }
                Repeater {
                    model: root.otherCalendars.filter(c => c.section === "My calendars" && (root.showAllCalendars || root.otherSelected.indexOf(c.id) >= 0))
                    CalRow { required property var modelData; label: modelData.name; on: root.otherSelected.indexOf(modelData.id) >= 0; tick: modelData.color || theme.brandFill; onToggled: root.toggleCalendar(modelData.id) }
                }
                Text {
                    visible: root.otherCalendars.some(c => c.section === "Groups" && (root.showAllCalendars || root.otherSelected.indexOf(c.id) >= 0))
                    topPadding: 8; text: qsTr("Groups"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
                }
                Repeater {
                    model: root.otherCalendars.filter(c => c.section === "Groups" && (root.showAllCalendars || root.otherSelected.indexOf(c.id) >= 0))
                    CalRow { required property var modelData; label: modelData.name; on: root.otherSelected.indexOf(modelData.id) >= 0; onToggled: root.toggleCalendar(modelData.id) }
                }
                Text {
                    visible: root.otherCalendars.length > 0
                    topPadding: 8; leftPadding: 32
                    text: root.showAllCalendars ? qsTr("Show selected") : qsTr("Show all")
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.showAllCalendars = !root.showAllCalendars }
                    Accessible.role: Accessible.Link; Accessible.name: text
                }
            }
        }
    }

    // A calendar's tick box in the pane.
    component CalRow: Item {
        id: cr
        property string label
        property bool on: false
        property color tick: theme.brandFill
        signal toggled()
        width: parent ? parent.width : 0; height: 28
        Rectangle {
            id: crBox
            x: 6; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 2
            color: cr.on ? cr.tick : "transparent"
            border.color: cr.on ? "transparent" : theme.textStrong
            FluentIcon { visible: cr.on; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(crBox, "white") }
        }
        Text { x: 32; width: parent.width - 32; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: cr.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        TapHandler { onTapped: cr.toggled() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.CheckBox
        Accessible.name: cr.label
        Accessible.checked: cr.on
    }
    component NavButton: Rectangle {
        id: nb
        property alias icon: nbIcon.name
        property string tip
        property int iconSize: 20
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: nbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { id: nbIcon; anchors.centerIn: parent; size: nb.iconSize; color: theme.onFill(nb, theme.textStrong) }
        HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component BarButton2: Rectangle {
        id: bb
        property string icon
        property string label
        property bool chevron: false
        property bool primary: false
        /// Teams' "Filter applied": a 0.67 #BDBDBD edge.
        property bool outlined: false
        signal clicked()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        border.width: outlined ? 0.67 : 0
        border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
        width: bbRow.implicitWidth + 20; height: 32; radius: theme.radius
        color: primary ? (bbh.hovered ? theme.brandHover : theme.brandFill) : bbh.hovered ? theme.rowHover : "transparent"
        Row {
            id: bbRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!bb.icon; anchors.verticalCenter: parent.verticalCenter; name: bb.icon; size: 16; color: theme.onFill(bb, bb.primary ? "white" : theme.textStrong) }
            Text { visible: !!bb.label; text: bb.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: bb.primary ? Font.DemiBold : Font.Normal; color: theme.onFill(bb, bb.primary ? "white" : theme.text) }
            FluentIcon { visible: bb.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(bb, bb.primary ? "white" : theme.textStrong) }
        }
        HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // ── toolbar ─────────────────────────────────────────────────────────
    Item {
        id: bar
        anchors { left: pane.right; right: parent.right }
        height: 61
        z: 2
        /// Copilot's button: 10 from the edge, or 8.67 left of its pane.
        readonly property real dabX: !root.copilotEntries ? bar.width + 12 - 12 : root.copilotOpen ? bar.width - root.copilotWidth - 8.67 - 44 : bar.width - 10 - 44
        // Teams' "Chat with Copilot" (the calendar's Copilot button): a 44
        // px round button, white with the depth-16 shadow and Copilot's 24
        // px logo; hovering it lists Copilot's suggestions (12/20 chips,
        // padding 9 12, radius 12, 8 apart, right-aligned under it); it
        // opens Copilot's pane in the calendar.
        Item {
            id: dab
            visible: root.copilotEntries
            x: bar.dabX; y: 6.33; width: 44; height: 44
            FluentSurface { anchors.fill: parent; depth: 16; radius: 22; color: dabHover.hovered ? theme.hc("#F5F5F5", "#000000") : theme.surface }
            Image { anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(48, 48); source: "../assets/icons/copilot-color-48.svg" }
            HoverHandler { id: dabHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.copilotOpen = !root.copilotOpen; dabChips.visible = false } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Chat with Copilot")
            Timer { interval: 400; running: dabHover.hovered && !root.copilotOpen; onTriggered: dabChips.visible = true }
        }
        Column {
            id: dabChips
            visible: false
            z: 5
            spacing: 8
            x: dab.x + dab.width - width; y: 57.33
            readonly property bool inside: chipsHover.hovered || dabHover.hovered
            onInsideChanged: if (!inside) chipsHide.restart(); else chipsHide.stop()
            Timer { id: chipsHide; interval: 300; onTriggered: dabChips.visible = false }
            HoverHandler { id: chipsHover }
            Repeater {
                model: [{ k: "Find my next one-on-one with", t: qsTr("Find my next one-on-one with") }, { k: "Show me meetings I haven't responded to next week", t: qsTr("Show me meetings I haven't responded to next week") },
                    { k: "What are the top three things I should focus on right now?", t: qsTr("What are the top 3 things I should focus on right now?") }, { k: "Schedule 1 hour of focus time", t: qsTr("Schedule 1 hour of focus time") }]
                Item {
                    id: chip
                    required property var modelData
                    anchors.right: parent ? parent.right : undefined
                    width: chipText.implicitWidth + 24; height: 39.33
                    FluentSurface { anchors.fill: parent; depth: 16; radius: 12; color: chipHover.hovered ? theme.hc("#F5F5F5", "#000000") : theme.surface }
                    Text { id: chipText; x: 12; anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.t; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { dabChips.visible = false; root.openCopilotWith(chip.modelData.k, true) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: chip.modelData.t
                }
            }
        }
        Row {
            id: leftRow
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            // With Copilot's pane open Teams keeps only the pane toggle here.
            readonly property bool narrow: root.copilotOpen
            NavButton { icon: "panel-left-20"; tip: root.paneShown ? qsTr("Hide navigation pane") : qsTr("Show navigation pane"); onClicked: root.paneShown = !root.paneShown }
            Rectangle { visible: !leftRow.narrow; width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
            BarButton2 { visible: !leftRow.narrow; icon: "calendar-ltr-20"; label: qsTr("Today"); onClicked: root.start = root.startFor(new Date()); Accessible.name: qsTr("Go to today") }
            NavButton { visible: !leftRow.narrow; icon: root.monthView ? "chevron-up-20" : "chevron-left-20"; iconSize: 16; onClicked: root.shift(-1); tip: root.monthView ? qsTr("Go to previous month") : root.view === "day" ? qsTr("Go to previous day") : qsTr("Go to previous week") }
            NavButton { visible: !leftRow.narrow; icon: root.monthView ? "chevron-down-20" : "chevron-right-20"; iconSize: 16; onClicked: root.shift(1); tip: root.monthView ? qsTr("Go to next month") : root.view === "day" ? qsTr("Go to next day") : qsTr("Go to next week") }
            BarButton2 {
                visible: !leftRow.narrow
                label: root.rangeLabel; chevron: true
                onClicked: { month.shown = new Date(root.start.getFullYear(), root.start.getMonth(), 1); root.paneShown = true }
                Accessible.name: qsTr("%1, Jump to a specific date or date range.").arg(root.rangeLabel)
            }
        }
        Row {
            id: rightRow
            anchors.right: parent.right; anchors.rightMargin: bar.width - bar.dabX + 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            BarButton2 {
                id: viewButton
                visible: !root.copilotOpen
                icon: ({ day: "calendar-day-20", workweek: "calendar-work-week-20", week: "calendar-week-numbers-20", month: "calendar-month-20" })[root.view]
                label: ({ day: qsTr("Day"), workweek: qsTr("Work week"), week: qsTr("Week"), month: qsTr("Month") })[root.view]
                chevron: true
                onClicked: viewMenu.open()
                Accessible.role: Accessible.ComboBox
                MenuPopup {
                    id: viewMenu
                    radioColumn: true
                    minRowWidth: 216.43
                    y: parent.height + 4
                    items: root.viewMenuItems
                    onPicked: i => root.viewAct(items[i].act)
                    onSubPicked: (i, j) => root.viewAct(items[i].submenu[j].act)
                    onSubSubPicked: (i, j, k) => root.viewAct(items[i].submenu[j].submenu[k].act)
                }
            }
            // Filter: "Filter applied" (outlined) while anything is
            // unchecked; in "More options" when the toolbar is short.
            BarButton2 {
                id: filterBtn
                visible: root.filterInline
                icon: "filter-20"; label: root.filterApplied ? qsTr("Filter applied") : qsTr("Filter"); chevron: true
                outlined: root.filterApplied
                onClicked: filterMenu.open()
                Accessible.name: qsTr("Apply or remove calendar event filters.")
                MenuPopup {
                    id: filterMenu
                    submenuMinWidth: 0
                    y: parent.height + 4
                    items: root.filterMenuItems
                    onPicked: i => root.filterAct(items[i].act)
                    onSubPicked: (i, j) => root.filterAct(items[i].submenu[j].act)
                }
            }
            NavButton {
                id: moreBtn
                icon: "more-horizontal-20"; tip: qsTr("More options")
                onClicked: moreMenu.open()
                MenuPopup {
                    id: moreMenu
                    submenuMinWidth: 0
                    perItemIcons: true
                    y: parent.height + 4
                    items: root.moreMenuItems
                    onPicked: i => root.moreAct(items[i].act)
                    onSubPicked: (i, j) => { if (items[i].act === "filter") root.filterAct(items[i].submenu[j].act); else root.moreAct(items[i].submenu[j].act) }
                    onSubSubPicked: (i, j, k) => root.filterAct(items[i].submenu[j].submenu[k].act)
                }
            }
            Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
            // Meet now ▾: Start a meeting now; the chevron: Join with an ID.
            Row {
                id: meetRow
                anchors.verticalCenter: parent.verticalCenter
                BarButton2 { icon: "video-20"; label: qsTr("Meet now"); onClicked: meetNowDialog.openFresh(); Accessible.name: qsTr("Start an instant Teams meeting.") }
                BarButton2 {
                    chevron: true; width: 28
                    onClicked: meetMenu.open()
                    Accessible.name: qsTr("More meet now options")
                    MenuPopup {
                        id: meetMenu
                        x: -120; y: parent.height + 4; width: 141
                        perItemIcons: true
                        items: [{ label: qsTr("Join with an ID"), icon: "number-symbol-20" }]
                        onPicked: joinId.openFresh()
                    }
                }
            }
            // New ▾ (measured in Teams desktop 2026-11-18, 174 wide): Event,
            // Channel meeting, then "Organization templates" (12/600
            // #616161): Webinar and Town hall open the Events app's form
            // with that template.
            Row {
                id: newRow
                visible: !root.copilotOpen
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                BarButton2 { primary: true; icon: "calendar-add-20"; label: qsTr("New"); onClicked: root.openForm(null, [], null); Accessible.name: qsTr("Create a new event.") }
                BarButton2 {
                    primary: true; chevron: true; width: 24
                    onClicked: newMenu.open()
                    Accessible.name: qsTr("More new options")
                    MenuPopup {
                        id: newMenu
                        x: -150; y: parent.height + 4; width: 174
                        perItemIcons: true
                        items: [{ label: qsTr("Event"), icon: "calendar-ltr-20" }, { label: qsTr("Channel meeting"), icon: "channel-20" }, { separator: true },
                                { heading: true, label: qsTr("Organization templates") },
                                { label: qsTr("Webinar"), icon: "board-person-20" }, { label: qsTr("Town hall"), icon: "megaphone-loud-20" },
                                { label: qsTr("Virtual appointment"), icon: "desktop-20" }, { label: qsTr("Live Event"), icon: "live-20" }]
                        onPicked: i => { if (i === 0) root.openEventForm(); else if (i === 1) root.openForm(null, [], null)
                                         else if (i === 4) root.newEventTemplate("webinar"); else if (i === 5) root.newEventTemplate("townhall")
                                         else if (i === 6) root.openVirtualAppointment(); else if (i === 7) liveEventsRetiring.open() }
                    }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // ── Day / Work week / Week ──────────────────────────────────────────
    Item {
        id: gridArea
        visible: !root.monthView
        anchors { top: bar.bottom; bottom: parent.bottom; left: pane.right; right: parent.right; rightMargin: root.copilotWidth }
        // Day headers (54) and the all-day strip.
        clip: true
        Item {
            id: heads
            x: -grid.contentX
            width: Math.max(parent.width, root.gridWidth); height: root.splitHead + 54 + root.stripHeight
            // Split view: each calendar's name over its days, and its close.
            Repeater {
                model: root.splitActive ? root.splitCalendars : []
                Rectangle {
                    id: blk
                    required property var modelData
                    required property int index
                    x: root.colX(index * root.days); width: root.colX((index + 1) * root.days) - x; height: root.splitHead
                    color: root.calDay
                    Rectangle { width: 1; height: parent.height; color: root.calLine }
                    Text {
                        x: 13; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 13 - 40; elide: Text.ElideRight
                        text: blk.modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                        color: blk.modelData.color || theme.brand
                    }
                    NavButton {
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                        icon: "dismiss-20"; tip: qsTr("Close %1").arg(blk.modelData.name)
                        onClicked: { if (blk.modelData.id === "") root.showCalendar = false; else root.toggleCalendar(blk.modelData.id) }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.calLine }
                }
            }
            Repeater {
                model: root.nCols
                Rectangle {
                    required property int index
                    readonly property int dayIndex: root.dayOfCol(index)
                    readonly property date day: root.dayAt(dayIndex)
                    readonly property bool today: dayIndex === root.todayIndex
                    x: root.colX(index); width: root.colW(index); y: root.splitHead; height: heads.height - y
                    color: root.dayFill(root.busyDay(dayIndex), root.pastDay(dayIndex) ? root.calOff : root.calDay)
                    Rectangle { visible: parent.today; width: parent.width; height: 3; color: root.calPrimary }
                    Text { x: 13; y: 8; text: parent.day.getDate(); font.family: theme.font; font.pixelSize: 20; color: root.calPrimary }
                    Text { x: 13; y: 33; text: theme.fmtDate(parent.day, root.wideLayout ? "dddd" : "ddd"); font.family: theme.font; font.pixelSize: theme.small; color: parent.today ? root.calPrimary : theme.textSecondary }
                    Rectangle { width: 1; height: parent.height; color: root.calLine }
                    Rectangle { y: 54; width: parent.width; height: 1; color: root.calLine }
                }
            }
            Repeater {
                model: root.splitStripBars
                Rectangle {
                    id: sb
                    required property var modelData
                    readonly property var ev: modelData.ev
                    x: root.colX(modelData.c0) + 2.6
                    width: root.colX(modelData.c1) + root.colW(modelData.c1) - 12 - x
                    y: root.splitHead + 56 + modelData.row * 21; height: 18
                    radius: 4
                    color: root.fillOf(ev)
                    ShowAsBar { ev: sb.ev; height: parent.height }
                    Text {
                        anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 18)
                        text: sb.ev.subject || qsTr("(No title)"); elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: root.textOf(sb.ev)
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: details.show(sb.ev, sb) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ep => tileMenu.openFor(sb.ev, sb, ep.position.x, ep.position.y) }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1, all day event").arg(ev.subject || qsTr("Event"))
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.calLine }
        }

        Flickable {
            id: grid
            anchors { top: heads.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            contentHeight: 24 * root.hourHeight
            contentWidth: Math.max(width, root.gridWidth)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            Component.onCompleted: contentY = Math.max(0, Math.min(contentHeight - height, (new Date().getHours() - 1) * root.hourHeight))
            Connections {
                target: root
                function onTimeScaleChanged() { grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, (new Date().getHours() - 1) * root.hourHeight)) }
            }
            // Day backgrounds: past days, hours outside 8–17 and busy days.
            Repeater {
                model: root.nCols
                Item {
                    required property int index
                    readonly property int d: root.dayOfCol(index)
                    readonly property bool weekend: [0, 6].indexOf(root.dayAt(d).getDay()) >= 0
                    x: root.colX(index); width: root.colW(index); height: grid.contentHeight
                    readonly property bool busy: root.busyDay(d)
                    Rectangle { anchors.fill: parent; color: root.dayFill(parent.busy, root.pastDay(parent.d) || parent.weekend ? root.calOff : root.calDay) }
                    Rectangle { visible: !root.pastDay(parent.d) && !parent.weekend; width: parent.width; height: 8 * root.hourHeight; color: root.dayFill(parent.busy, root.calOff) }
                    Rectangle { visible: !root.pastDay(parent.d) && !parent.weekend; y: 17 * root.hourHeight; width: parent.width; height: 7 * root.hourHeight; color: root.dayFill(parent.busy, root.calOff) }
                    Rectangle { width: 1; height: parent.height; color: root.calLine }
                }
            }
            Repeater {
                model: 24
                Item {
                    required property int index
                    y: index * root.hourHeight; width: grid.contentWidth; height: root.hourHeight
                    Text {
                        visible: index > 0 && grid.contentX <= 0
                        x: 10; y: 8
                        text: index < 12 ? qsTr("%1 AM").arg(index % 12 === 0 ? 12 : index % 12) : qsTr("%1 PM").arg(index % 12 === 0 ? 12 : index % 12)
                        font.family: theme.font; font.pixelSize: 11; color: theme.textSecondary
                    }
                    Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: root.calLine }
                    // The time scale's slots: a dashed line at each, the hour solid.
                    Repeater {
                        model: Math.max(0, Math.round(60 / root.timeScale) - 1)
                        Row {
                            required property int index
                            x: root.gutter; y: (index + 1) * root.slotHeight
                            spacing: 3
                            Repeater { model: Math.ceil((grid.contentWidth - root.gutter) / 6); Rectangle { width: 3; height: 1; color: root.calDash } }
                        }
                    }
                }
            }
            // Click an empty slot to schedule there.
            MouseArea {
                x: root.gutter; width: grid.contentWidth - root.gutter; height: grid.contentHeight
                onClicked: m => {
                    let col = 0
                    while (col < root.nCols - 1 && root.gutter + m.x >= root.colX(col + 1)) col++
                    const slot = Math.floor(m.y / root.slotHeight)
                    const d = root.dayAt(root.dayOfCol(col)); d.setHours(0, slot * root.timeScale, 0, 0)
                    root.openForm(d, [], null)
                }
            }
            Repeater {
                id: eventRepeater
                model: {
                    if (root.splitActive) return root.splitPieces
                    const all = []
                    root.dayPieces.forEach((list, i) => list.forEach(p => all.push(Object.assign({ col: i }, p))))
                    return all
                }
                Rectangle {
                    id: evTile
                    required property var modelData
                    readonly property var ev: modelData.ev
                    readonly property real laneW: (root.colW(modelData.col) - 14.6 - 4 * (modelData.lanes - 1)) / modelData.lanes
                    readonly property bool shortOne: height < 40
                    x: root.colX(modelData.col) + 2.6 + modelData.lane * (laneW + 4)
                    width: laneW
                    y: modelData.s / 60 * root.hourHeight + 2
                    height: Math.max(17, (modelData.e - modelData.s) / 60 * root.hourHeight - 5)
                    radius: 4
                    color: root.fillOf(ev)
                    TileEdge { ev: evTile.ev; selected: details.visible && details.ev.id === evTile.ev.id }
                    ShowAsBar { ev: evTile.ev; height: parent.height }
                    // Short: one line (title, location, organizer); else stacked.
                    Text {
                        visible: evTile.shortOne
                        x: 12; y: 4; width: parent.width - 16 - (joinTile.visible ? joinTile.width + 6 : 0) - (seriesIcon.visible ? 20 : 0)
                        elide: Text.ElideRight; textFormat: Text.StyledText
                        text: "<b>" + (evTile.ev.subject || qsTr("(No title)")).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b> " + [evTile.ev.location, evTile.ev.is_organizer ? "" : evTile.ev.organizer].filter(x => x).join(" ").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                        font.family: theme.font; font.pixelSize: 12; color: root.textOf(evTile.ev)
                    }
                    Column {
                        visible: !evTile.shortOne
                        x: 12; y: 4; width: parent.width - 16
                        Text { width: parent.width; elide: Text.ElideRight; text: evTile.ev.subject || qsTr("(No title)"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textOf(evTile.ev) }
                        Text { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: Math.max(1, Math.floor((evTile.height - 24) / 16)); elide: Text.ElideRight; visible: !!text; text: [evTile.ev.location, evTile.ev.is_organizer ? "" : evTile.ev.organizer].filter(x => x).join(" "); font.family: theme.font; font.pixelSize: 12; color: root.textOf(evTile.ev) }
                    }
                    FluentIcon {
                        id: seriesIcon
                        visible: evTile.ev.event_type === "occurrence" || evTile.ev.event_type === "exception"
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                        name: evTile.ev.event_type === "exception" ? "arrow-repeat-all-off-16" : "arrow-repeat-all-16"; size: 16; color: root.textOf(evTile.ev)
                    }
                    // Join on the tile from five minutes before the start, as
                    // Teams: brand while its call is going on, else outlined;
                    // beside other events only the 20 x 20 Video glyph.
                    Rectangle {
                        id: joinTile
                        visible: root.joinable(evTile.ev)
                        readonly property bool live: root.isLive(evTile.ev)
                        readonly property bool iconOnly: evTile.modelData.lanes > 1
                        anchors.right: parent.right; anchors.rightMargin: 4.4; y: 5.8
                        width: iconOnly ? 20 : jt.implicitWidth + 16; height: iconOnly ? 20 : 22; radius: 4
                        color: live ? (jth.hovered ? theme.brandHover : theme.brandFill) : jth.hovered ? theme.rowHover : theme.surface
                        border.width: live ? 0 : 0.67
                        border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                        FluentIcon { visible: joinTile.iconOnly; anchors.centerIn: parent; name: "video-16"; size: 16; color: theme.onFill(joinTile, joinTile.live ? "white" : theme.textSecondary) }
                        Text { id: jt; visible: !joinTile.iconOnly; anchors.centerIn: parent; text: qsTr("Join"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(joinTile, joinTile.live ? "white" : theme.textSecondary) }
                        HoverHandler { id: jth; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.joinMeeting(evTile.ev.join_url, evTile.ev.subject || qsTr("Meeting")) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Join Teams meeting")
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: details.show(evTile.ev, evTile) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ep => tileMenu.openFor(evTile.ev, evTile, ep.position.x, ep.position.y) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (ev.subject || qsTr("Event")) + ", " + theme.time(root.evStart(ev)) + " to " + theme.time(root.evEnd(ev))
                }
            }
            // Scrolled sideways (Split view): the hours stay at the left.
            Rectangle {
                visible: grid.contentX > 0
                x: grid.contentX; width: root.gutter; height: grid.contentHeight
                color: theme.surface; z: 3
                Repeater {
                    model: 23
                    Text {
                        required property int index
                        x: 10; y: (index + 1) * root.hourHeight + 8
                        text: index + 1 < 12 ? qsTr("%1 AM").arg((index + 1) % 12 === 0 ? 12 : (index + 1) % 12) : qsTr("%1 PM").arg((index + 1) % 12 === 0 ? 12 : (index + 1) % 12)
                        font.family: theme.font; font.pixelSize: 11; color: theme.textSecondary
                    }
                }
            }
            // Now: a line across today, dashed before it, with a dot.
            Item {
                id: nowLine
                readonly property int col: root.todayIndex
                visible: col >= 0
                y: (root.now.getHours() + root.now.getMinutes() / 60) * root.hourHeight
                Row {
                    x: root.gutter; spacing: 3
                    Repeater { model: Math.max(0, Math.ceil((root.colX(Math.max(0, nowLine.col)) - root.gutter) / 6)); Rectangle { width: 3; height: 1; color: root.calPrimary } }
                }
                Rectangle { x: root.colX(Math.max(0, nowLine.col)); width: root.colW(Math.max(0, nowLine.col)); height: 2; y: -0.5; color: root.calPrimary }
                Rectangle { x: root.colX(Math.max(0, nowLine.col)) - 5; y: -5; width: 10; height: 10; radius: 5; color: root.calPrimary }
            }
        }
    }

    // How busy an event keeps you: a 4 px bar in the calendar colour (busy
    // solid; tentative and unanswered hatched with the day's colour; free
    // and canceled the day's colour with a calendar-colour edge). As the
    // hosted calendar draws them (its show-as styles, measured 2026-11-23):
    // Working elsewhere is open with calendar-colour dots (three in every
    // 4 x 4 px), Away is the away colour crossed both ways with the day's
    // colour at 80 % every 6 px.
    component ShowAsBar: Item {
        id: sab
        property var ev
        readonly property bool open: !!ev && (ev.show_as === "free" || root.isCanceled(ev))
        readonly property string pattern: !ev || open ? "" : ev.show_as === "oof" ? "away" : ev.show_as === "workingElsewhere" ? "elsewhere" : root.isTentative(ev) ? "tentative" : ""
        readonly property color barColor: root.barOf(ev)
        width: 4
        Rectangle {
            anchors.fill: parent; radius: 4
            visible: sab.pattern === ""
            color: sab.open ? root.calDay : sab.barColor
            border.width: sab.open ? 1 : 0; border.color: sab.barColor
        }
        Canvas {
            id: hatch
            anchors.fill: parent
            visible: sab.pattern !== ""
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.fillStyle = sab.barColor; c.fillRect(0, 0, width, height)
                if (sab.pattern === "tentative") {
                    c.strokeStyle = root.calDay; c.lineWidth = 1.5
                    for (let y = -4; y < height + 4; y += 4) { c.beginPath(); c.moveTo(0, y + 4); c.lineTo(width, y); c.stroke() }
                } else if (sab.pattern === "away") {
                    c.strokeStyle = root.calDay; c.globalAlpha = 0.8; c.lineWidth = 1
                    for (let y = -6; y < height + 6; y += 6) {
                        c.beginPath(); c.moveTo(0, y); c.lineTo(width, y + width); c.stroke()
                        c.beginPath(); c.moveTo(0, y + width); c.lineTo(width, y); c.stroke()
                    }
                    c.globalAlpha = 1
                } else if (sab.pattern === "elsewhere") {
                    // The day's colour inside a 1 px edge, then the dots.
                    c.fillStyle = root.calDay; c.fillRect(1, 0, width - 2, height)
                    c.fillStyle = sab.barColor
                    for (let v = 0; v < height; v++) for (let u = 0; u < width - 2; u++) {
                        const a = u % 4, b = v % 4
                        if (a % 2 === 0 && b % 2 === 0 && !(a === 0 && b === 2)) c.fillRect(1 + u, v, 1, 1)
                    }
                }
            }
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            Connections { target: sab; function onBarColorChanged() { hatch.requestPaint() } function onPatternChanged() { hatch.requestPaint() } }
            Connections { target: root; function onCalDayChanged() { hatch.requestPaint() } }
        }
    }
    // A tile's edge: a canceled event's 1 px edge (top, right, bottom), and
    // the selected event's 2 px inset ring (neutralDark: #242424, dark
    // #D6D6D6).
    component TileEdge: Item {
        id: te
        property var ev
        property bool selected: false
        anchors.fill: parent
        readonly property bool canceled: !!ev && root.isCanceled(ev)
        Rectangle { visible: te.canceled; x: 4; width: parent.width - 4; height: 1; color: root.edgeOf(te.ev) }
        Rectangle { visible: te.canceled; x: 4; anchors.bottom: parent.bottom; width: parent.width - 4; height: 1; color: root.edgeOf(te.ev) }
        Rectangle { visible: te.canceled; anchors.right: parent.right; width: 1; height: parent.height; color: root.edgeOf(te.ev) }
        Rectangle {
            visible: te.selected
            anchors.fill: parent; radius: 4; z: 2
            color: "transparent"; border.width: 2; border.color: theme.pick("#242424", "#D6D6D6", "#FFFFFF")
        }
    }

    // ── Month ───────────────────────────────────────────────────────────
    Item {
        id: monthArea
        visible: root.monthView
        anchors { top: bar.bottom; bottom: parent.bottom; left: pane.right; right: parent.right }
        readonly property real cellW: width / 7
        readonly property real cellH: (height - 28) / root.monthWeeks
        readonly property int rowsPerCell: Math.max(1, Math.floor((cellH - 32 - 4) / 26))
        Repeater {
            model: [qsTr("Sunday"), qsTr("Monday"), qsTr("Tuesday"), qsTr("Wednesday"), qsTr("Thursday"), qsTr("Friday"), qsTr("Saturday")]
            Text { required property int index; required property string modelData; x: index * monthArea.cellW + 8; y: 8; text: modelData; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
        Rectangle { y: 28; width: parent.width; height: 1; color: root.calLine }
        /// Per week row: bars [{ev, c0, c1, row, multi}] and, per cell, how many didn't fit.
        readonly property var weeksLaid: {
            const out = []
            if (!root.monthView) return out
            for (let w = 0; w < root.monthWeeks; w++) {
                const d0 = root.dayAt(w * 7), d7 = root.dayAt(w * 7 + 7)
                const items = []
                for (const e of root.shown) {
                    const s = root.evStart(e), en = root.evEnd(e)
                    if (en <= d0 || s >= d7) continue
                    const c0 = Math.max(0, Math.floor((root.midnight(s) - d0) / 86400000))
                    const c1 = Math.min(6, Math.floor((root.midnight(new Date(en - 1)) - d0) / 86400000))
                    items.push({ ev: e, c0: c0, c1: Math.max(c0, c1), multi: c1 > c0 || root.inStrip(e) })
                }
                // Multi-day first, then by start.
                items.sort((a, b) => (b.multi - a.multi) || (root.evStart(a.ev) - root.evStart(b.ev)) || (b.c1 - b.c0) - (a.c1 - a.c0))
                const used = Array(7).fill(0).map(() => [])
                const bars = [], hidden = Array(7).fill(0)
                for (const it of items) {
                    let row = 0
                    while (true) { let ok = true; for (let c = it.c0; c <= it.c1; c++) if (used[c][row]) ok = false; if (ok) break; row++ }
                    for (let c = it.c0; c <= it.c1; c++) used[c][row] = true
                    it.row = row
                    bars.push(it)
                }
                // A cell shows rowsPerCell rows; when it has more, the last is "+N".
                const R = monthArea.rowsPerCell
                for (let c = 0; c < 7; c++) {
                    const n = used[c].filter(x => x).length
                    const lastRow = used[c].length - 1
                    if (lastRow >= R) hidden[c] = bars.filter(b => b.c0 <= c && b.c1 >= c && b.row >= R - 1).length
                }
                out.push({ bars: bars.filter(b => { for (let c = b.c0; c <= b.c1; c++) if (hidden[c] > 0 ? b.row >= R - 1 : b.row >= R) return false; return true }), hidden: hidden })
            }
            return out
        }
        Repeater {
            model: root.monthView ? root.monthWeeks * 7 : 0
            Rectangle {
                id: cell
                required property int index
                readonly property date day: root.dayAt(index)
                readonly property bool today: root.sameDay(day, root.now)
                readonly property bool inMonth: day.getMonth() === root.focusMonth.getMonth()
                x: (index % 7) * monthArea.cellW; y: 29 + Math.floor(index / 7) * monthArea.cellH
                width: monthArea.cellW; height: monthArea.cellH
                // Days before today on neutralLighterAlt, as the week's.
                color: root.midnight(day) < root.midnight(root.now) ? root.calOff : root.calDay
                border.width: today ? 1 : 0; border.color: root.calPrimary
                Rectangle { visible: !cell.today; anchors.right: parent.right; width: 1; height: parent.height; color: root.calLine }
                Rectangle { visible: !cell.today; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.calLine }
                // Today: a calendar-colour circle (#5B5FC7, dark #7F85F5).
                Rectangle { id: todayDot; visible: cell.today; x: 4; y: 6; width: 22; height: 22; radius: 11; color: root.calPrimary }
                Text {
                    x: cell.today ? 4 : 8; y: 6; width: cell.today ? 22 : implicitWidth; height: cell.today ? 22 : 19
                    horizontalAlignment: cell.today ? Text.AlignHCenter : Text.AlignLeft; verticalAlignment: Text.AlignVCenter
                    text: cell.day.getDate() === 1 ? theme.fmtDate(cell.day, "MMM d") : cell.day.getDate()
                    font.family: theme.font; font.pixelSize: 14; font.weight: cell.today ? Font.DemiBold : Font.Normal
                    color: theme.onFill(todayDot, cell.today ? theme.pick("#FFFFFF", "#242424", "#000000") : theme.textSecondary)
                }
                MouseArea {
                    anchors.fill: parent; z: -1
                    onClicked: { const d = new Date(cell.day); d.setHours(8, 0, 0, 0); root.openForm(d, [], null) }
                }
                // "+N": the rest of the day (opens it).
                Rectangle {
                    readonly property int n: monthArea.weeksLaid[Math.floor(cell.index / 7)] ? monthArea.weeksLaid[Math.floor(cell.index / 7)].hidden[cell.index % 7] : 0
                    visible: n > 0
                    x: 0; y: 31.6 + (monthArea.rowsPerCell - 1) * 26
                    width: parent.width - 8; height: 24; radius: 4
                    color: moreH.hovered ? theme.pick("#EBEBEB", "#5C5C5C", "#1AEBFF") : theme.pick("#F0F0F0", "#141414", "#000000")
                    Text { anchors.centerIn: parent; text: "+" + parent.n; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    HoverHandler { id: moreH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.view = "day"; root.start = root.startFor(cell.day) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1 more events from %2").arg(n).arg(theme.longDate(cell.day))
                }
            }
        }
        Repeater {
            model: {
                const all = []
                monthArea.weeksLaid.forEach((w, i) => w.bars.forEach(b => all.push(Object.assign({ week: i }, b))))
                return all
            }
            Rectangle {
                id: mb
                required property var modelData
                readonly property var ev: modelData.ev
                readonly property bool allDay: root.inStrip(ev)
                x: modelData.c0 * monthArea.cellW
                width: (modelData.c1 - modelData.c0 + 1) * monthArea.cellW - 8.3
                y: 29 + modelData.week * monthArea.cellH + 31.6 + modelData.row * 26
                height: 24; radius: 4
                color: root.fillOf(ev)
                TileEdge { ev: mb.ev; selected: details.visible && details.ev.id === mb.ev.id }
                ShowAsBar { ev: mb.ev; height: parent.height }
                Text {
                    x: mb.allDay ? Math.max(11, (parent.width - implicitWidth) / 2) : 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 11 - (mbSeries.visible ? 26 : 9))
                    elide: Text.ElideRight; textFormat: Text.StyledText
                    text: (mb.allDay ? "" : theme.time(root.evStart(mb.ev)).replace(":00", "") + " ") + "<b>" + (mb.ev.subject || qsTr("(No title)")).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>"
                    font.family: theme.font; font.pixelSize: 12; color: root.textOf(mb.ev, true)
                }
                FluentIcon {
                    id: mbSeries
                    visible: mb.ev.event_type === "occurrence" || mb.ev.event_type === "exception"
                    anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                    name: mb.ev.event_type === "exception" ? "arrow-repeat-all-off-16" : "arrow-repeat-all-16"; size: 16; color: root.textOf(mb.ev, true)
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: details.show(mb.ev, mb) }
                Accessible.role: Accessible.Button
                Accessible.name: (ev.subject || qsTr("Event")) + ", " + theme.dateTime(ev.start_utc)
            }
        }
    }

    // ── the peek card ───────────────────────────────────────────────────
    property var pendingMeeting: null
    /// Show a meeting's card (from its chat's Meeting details): its week,
    /// then its card (with `page`, its event page: a channel meeting's
    /// calendar card). False when the calendar doesn't have it.
    function showMeeting(joinUrl, icalUid, startIso, page) {
        const e = root.events.find(x => (joinUrl && x.join_url === joinUrl) || (icalUid && x.ical_uid === icalUid))
        if (e) {
            const d = new Date(e.start_utc)
            if (!isNaN(d)) root.start = root.startFor(d)
            pendingMeeting = null
            if (page) openPage(e, ""); else details.show(e, null)
            return true
        }
        const d = new Date(startIso || "")
        if (isNaN(d)) return false
        pendingMeeting = { joinUrl: joinUrl, icalUid: icalUid, page: !!page }
        root.start = root.startFor(d)
        return true
    }
    onEventsChanged: {
        if (pendingMeeting) {
            const p = pendingMeeting
            const e = root.events.find(x => (p.joinUrl && x.join_url === p.joinUrl) || (p.icalUid && x.ical_uid === p.icalUid))
            if (e) { pendingMeeting = null; if (p.page) openPage(e, ""); else details.show(e, null) }
        }
        // Keep an open card on the event's new state (after an answer).
        if (details.visible && details.ev.id) {
            const e = root.events.find(x => x.id === details.ev.id)
            if (e) details.ev = e
        }
    }
    /// Your meeting's attendee tracking line on the card, as Outlook's
    /// peek writes it (its AttendeeTrackingDetails): one or two attendees
    /// by name ("OST Test 2 didn't respond.", "A and B accepted.", two
    /// different answers side by side), more as counts in Outlook's order
    /// ("Accepted 1, Didn't respond 2"). The organizer and rooms don't count.
    function trackingLine(e) {
        const org = (e.organizer_address || "").toLowerCase()
        const meMail = (root.me.mail || "").toLowerCase()
        const people = (e.attendees || []).filter(a => a.kind !== "resource" && (a.address || "").toLowerCase() !== org)
        const answer = a => ({ accepted: "a", tentativelyAccepted: "t", declined: "d", following: "f" })[a.response] || "n"
        const nameOf = a => (a.address || "").toLowerCase() === meMail ? qsTr("You") : a.name || a.address
        const named = people.filter(a => !!a.name)
        // You first, as Outlook lists them.
        named.sort((a, b) => ((b.address || "").toLowerCase() === meMail) - ((a.address || "").toLowerCase() === meMail))
        const one = a => ({ a: qsTr("%1 accepted."), t: qsTr("%1 tentatively accepted."), d: qsTr("%1 declined."), f: qsTr("%1 is following.") })[answer(a)] || qsTr("%1 didn't respond.")
        if (named.length === 1) return one(named[0]).arg(nameOf(named[0]))
        if (named.length === 2) {
            const [a, b] = named
            if (answer(a) !== answer(b)) return one(a).arg(nameOf(a)) + " " + one(b).arg(nameOf(b))
            const two = ({ a: qsTr("%1 and %2 accepted."), t: qsTr("%1 and %2 tentatively accepted."), d: qsTr("%1 and %2 declined."), f: qsTr("%1 and %2 are following.") })[answer(a)] || qsTr("%1 and %2 didn't respond.")
            return two.arg(nameOf(a)).arg(nameOf(b))
        }
        const n = { a: 0, f: 0, t: 0, d: 0, n: 0 }
        for (const a of people) n[answer(a)]++
        const parts = []
        if (n.a) parts.push(qsTr("Accepted %1").arg(n.a))
        if (n.f) parts.push(qsTr("Following %1").arg(n.f))
        if (n.t) parts.push(qsTr("Tentative %1").arg(n.t))
        if (n.d) parts.push(qsTr("Declined %1").arg(n.d))
        if (n.n) parts.push(qsTr("Didn't respond %1").arg(n.n))
        return parts.length ? parts.reduce((x, y) => qsTr("%1, %2").arg(x).arg(y)) : ""
    }
    function responseLine(r) {
        return ({ accepted: qsTr("You accepted"), tentativelyAccepted: qsTr("You tentatively accepted"), declined: qsTr("You declined"), following: qsTr("You are following") })[r] || qsTr("You didn't respond")
    }
    Popup {
        id: details
        property var ev: ({})
        property bool confirming: false
        /// Cancelling your meeting: "single", or for a series "occurrence",
        /// "following" or "series" (the card's Cancel ▾).
        property string cancelScope: ""
        /// Cancel (a meeting: attendees or a channel) rather than Delete.
        readonly property bool cancels: !!(ev.attendees && ev.attendees.length) || !!ev.channel_id
        property bool changing: false
        property bool emailOrganizer: true
        readonly property bool invite: !!ev.id && ev.is_organizer === false && ev.response_requested !== false
        readonly property bool answered: ["accepted", "tentativelyAccepted", "declined", "following"].indexOf(ev.response) >= 0
        readonly property bool series: ev.event_type === "occurrence" || ev.event_type === "exception"
        readonly property bool live: !!ev.start_utc && root.now >= new Date(root.evStart(ev) - 5 * 60000) && root.now < root.evEnd(ev)
        function show(e, item) {
            ev = e; confirming = false; cancelScope = ""; cancelNote.text = ""; changing = false; emailOrganizer = true; note.text = ""
            if (!item) { x = (root.width - width) / 2; y = 80; open(); return }
            const p = item.mapToItem(root, 0, 0)
            x = p.x - width - 8 >= 0 ? p.x - width - 8 : Math.min(root.width - width - 8, p.x + item.width + 8)
            y = Math.max(8, Math.min(root.height - implicitHeight - 8, p.y - 8))
            open()
        }
        /// The cancel message in place of Edit and Cancel; the card keeps
        /// its bottom edge, as Teams' does.
        function beginCancel(scope) {
            const bottom = y + height
            cancelNote.text = ""; cancelScope = scope
            // (A series' choice puts the cursor in the message; an event
            // that doesn't repeat doesn't.)
            Qt.callLater(() => { y = Math.max(8, bottom - implicitHeight); if (scope !== "single") cancelNote.forceActiveFocus() })
        }
        function endCancel() {
            const bottom = y + height
            cancelScope = ""
            Qt.callLater(() => { y = Math.max(8, Math.min(root.height - implicitHeight - 8, bottom - implicitHeight)) })
        }
        /// Send: Outlook's CancelCalendarEvent with the scope and message.
        function sendCancel() {
            const e = root.withTeam(ev)
            root.calendarAction("cancel", JSON.stringify({ event: e, teamId: e.team_id || "", note: cancelNote.text.trim(), scope: cancelScope === "single" ? "" : cancelScope }))
            close()
        }
        /// Answer (Teams: RespondToCalendarEvent); a series answer goes to its series.
        function respond(response, wholeSeries, msg) {
            const id = wholeSeries && ev.series_master_id ? ev.series_master_id : ev.id
            root.calendarAction("respond", JSON.stringify({ id: id, event: { id: ev.id, ical_uid: ev.ical_uid, event_type: ev.event_type, start_utc: ev.start_utc, series_master_id: ev.series_master_id }, series: !!wholeSeries, response: response, send: emailOrganizer, note: msg !== undefined ? msg : note.text }))
            close()
        }
        width: 392; padding: 0
        background: Rectangle {
            radius: 4; color: theme.menu; border.color: theme.pick(theme.dividerSoft, "#141414", "#5C5C5C")
            Rectangle { width: parent.width; height: 4; radius: 2; color: root.calPrimary }
        }
        contentItem: Column {
            topPadding: 17; bottomPadding: 16; leftPadding: 17; rightPadding: 17
            spacing: 0
            Item {
                width: 358; height: Math.max(36, titleText.height)
                // The event's charm before the title (24 px, brand; the
                // title then 40 further in), as Teams' card shows it.
                readonly property var charm: { const n = root.charmOf(details.ev); return n ? root.charms.find(x => x[0] === n) : null }
                FluentIcon { visible: !!parent.charm; x: -1; y: 4; size: 24; name: parent.charm ? parent.charm[2] : ""; color: theme.pick("#5B5FC7", "#7F85F5", "#FFFFFF") }
                Text {
                    id: titleText
                    x: parent.charm ? 39 : 0
                    width: parent.width - 32 - x; wrapMode: Text.Wrap
                    text: details.ev.subject || qsTr("(No title)")
                    font.family: theme.font; font.pixelSize: 21; font.weight: Font.DemiBold; color: theme.pick(theme.text, "#ADADAD", "#FFFFFF")
                }
                NavButton {
                    anchors.right: parent.right; y: 2; width: 24; height: 24; iconSize: 16
                    icon: "open-20"; tip: qsTr("View event")
                    onClicked: { const e = details.ev; details.close(); root.openPage(e) }
                }
            }
            // "Now" for a meeting that's on.
            Row {
                visible: details.live
                height: 24; spacing: 4
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "clock-20"; size: 12; color: theme.brand }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Now"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brand }
            }
            Item { width: 1; height: 16 }
            Row {
                visible: !!details.ev.join_url
                spacing: 5
                // Join ▾ (a split button: Join 77 wide, then a 24 px ▾ part
                // 1 after it with Join Teams meeting and Copy join link).
                Row {
                    spacing: 1
                    CardButton {
                        primary: true; icon: "video-20"; label: qsTr("Join"); minWidth: 77
                        onClicked: { root.joinMeeting(details.ev.join_url, details.ev.subject || qsTr("Meeting")); details.close() }
                    }
                    Rectangle {
                        id: joinMore
                        width: 24; height: 32; radius: 4
                        color: jmh.hovered ? theme.brandHover : theme.brandFill
                        FluentIcon { anchors.centerIn: parent; name: "chevron-down-12"; size: 12; color: theme.onFill(joinMore, "white") }
                        HoverHandler { id: jmh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: joinMenu.openFor(joinMore) }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("More join options")
                    }
                }
                CardButton {
                    icon: "chat-20"; label: qsTr("Chat"); minWidth: 96
                    onClicked: { root.openMeetingChat(details.ev.join_url, details.ev.subject || qsTr("Meeting")); details.close() }
                    Accessible.name: qsTr("Chat with participants")
                }
            }
            Item { visible: !!details.ev.join_url; width: 1; height: 16 }
            Rectangle { width: 358; height: 1; color: root.cardLine }
            // The rows as Outlook's card lays them out (Teams desktop, winpc
            // 2026-11-23): each under a line from 51 (the first under the
            // title's): the time 17 under it and 7 above the next line, the
            // location 9 and 9 (no place: "Add a room with Copilot" in its
            // place), who organised or invited you, "Prepare for this
            // meeting", then the description 13 under its line and 11 above
            // the next.
            DetailRow {
                line: false; textTop: 17; bottomGap: 7
                icon: "clock-20"
                text: {
                    const e = details.ev
                    if (!e.start_utc) return ""
                    const s = root.evStart(e), en = root.evEnd(e)
                    const d = theme.fmtDate(s, "ddd") + " " + theme.fmtDate(s, "M/d/yyyy")
                    let t = e.is_all_day ? d + " " + qsTr("All day") : root.sameDay(s, new Date(en - 1)) ? d + " " + theme.time(s) + " - " + theme.time(en)
                        : d + " " + theme.time(s) + " - " + theme.fmtDate(en, "ddd") + " " + theme.fmtDate(en, "M/d/yyyy") + " " + theme.time(en)
                    return t
                }
                suffix: details.series ? qsTr("Series") : ""
            }
            // Your meeting: each proposed time under the time, as Teams'
            // card shows it: "{name} proposed new time" (12 px brand),
            // then the time (12 px #616161) and Accept (14/600 brand).
            Repeater {
                model: details.ev.is_organizer ? (details.ev.attendees || []).filter(a => !!a.proposed_start) : []
                Column {
                    id: proposal
                    required property var modelData
                    x: 35; topPadding: -8; bottomPadding: 8; spacing: 4
                    Text {
                        text: qsTr("%1 proposed new time").arg(proposal.modelData.name || proposal.modelData.address)
                        font.family: theme.font; font.pixelSize: 12; color: theme.brand
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const e = details.ev; details.close(); root.openPage(e) } }
                        Accessible.role: Accessible.Button; Accessible.name: text
                    }
                    Row {
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: theme.fmtDate(new Date(proposal.modelData.proposed_start), "ddd M/d/yyyy") + " " + theme.time(new Date(proposal.modelData.proposed_start)) + " - " + theme.time(new Date(proposal.modelData.proposed_end))
                            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Accept")
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            // Accepting moves the meeting to the proposed time.
                            TapHandler { onTapped: { root.updateEvent(details.ev.id, details.ev.subject || "", proposal.modelData.proposed_start, proposal.modelData.proposed_end); details.close() } }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Accept the proposed time")
                        }
                    }
                }
            }
            // The place; with no place, Copilot's "Add a room with Copilot"
            // in its stead (14/20 #4F52B2) for a meeting. A Teams meeting
            // (its place "Microsoft Teams Meeting") says "No location
            // added" with the link under it (winpc, 2026-11-23).
            DetailRow {
                readonly property bool teamsPlace: !!details.ev.is_online_meeting && details.ev.location === "Microsoft Teams Meeting"
                readonly property bool noPlace: !details.ev.location || teamsPlace
                readonly property bool copilotRoom: noPlace && root.copilotEntries && (root.evIsMeeting(details.ev) || !!details.ev.is_online_meeting)
                icon: "location-20"
                link: copilotRoom && !teamsPlace
                linkBelow: copilotRoom && teamsPlace ? qsTr("Add a room with Copilot") : ""
                text: link ? qsTr("Add a room with Copilot") : noPlace ? qsTr("No location added") : details.ev.location
                onClicked: root.askCopilot("Add a room")
            }
            // Who invited you (or the channel), and your answer.
            Item {
                visible: !!details.ev.id && !details.ev.is_organizer
                width: 358; height: visible ? 52 : 0
                Rectangle { y: 0; x: 34; width: 324; height: 1; color: root.cardLine }
                Avatar { x: 0; y: 14; size: 24; name: (details.ev.channel_id ? (root.withTeam(details.ev).team_name || details.ev.organizer) : details.ev.organizer) || ""; photoId: details.ev.channel_id && root.withTeam(details.ev).team_id ? "team:" + root.withTeam(details.ev).team_id : "" }
                Text {
                    x: 36; y: 14; width: 322; elide: Text.ElideRight
                    text: details.ev.channel_id ? qsTr("%1 in the channel %2").arg(root.withTeam(details.ev).team_name || details.ev.organizer).arg(root.withTeam(details.ev).channel_name || "") : qsTr("%1 invited you.").arg(details.ev.organizer || qsTr("Someone"))
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text { x: 36; y: 38; text: root.responseLine(details.ev.response); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            }
            // Your meeting: "You're the organizer." with your picture, and
            // who answered under it (Outlook's PeekEventOrganizerRow, for a
            // meeting that isn't a draft; the tracking while it asks for
            // answers and isn't canceled). Measured on winpc 2026-11-23:
            // 13 under the line, the 24 px picture and 14 px text in a 24
            // row, the tracking 12/16 under it, 12 above the next line.
            Item {
                id: orgRow
                readonly property string tracking: details.ev.response_requested !== false && !details.ev.is_cancelled ? root.trackingLine(details.ev) : ""
                visible: !!details.ev.id && details.ev.is_organizer === true && root.evIsMeeting(details.ev) && !details.ev.is_draft
                width: 358; height: visible ? (tracking ? 67 : 50) : 0
                Rectangle { y: 0; x: 34; width: 324; height: 1; color: root.cardLine }
                Avatar { x: 0; y: 14; size: 24; name: root.me.name || ""; photoId: "me" }
                Text {
                    x: 36; y: 14; width: 322; height: 24; elide: Text.ElideRight
                    text: qsTr("You're the organizer.")
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text {
                    visible: !!orgRow.tracking
                    x: 36; y: 38; width: 322; height: 16; elide: Text.ElideRight
                    text: orgRow.tracking
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    Accessible.name: qsTr("Attendee tracking") + ": " + text
                }
            }
            // Copilot: "Prepare for this meeting" (a 32 px outlined button,
            // padding 0 20, #BDBDBD edge, 14/600 #616161) after who
            // organised or invited you: 10 under its line, the glyph 14, 9
            // above the next line.
            Item {
                visible: root.copilotEntries && (root.evIsMeeting(details.ev) || !!details.ev.is_online_meeting)
                width: 358; height: visible ? 51 : 0
                Rectangle { x: 34; width: 324; height: 1; color: root.cardLine }
                FluentIcon { x: 2; y: 14; name: "calendar-sparkle-20"; size: 20; color: theme.textSecondary }
                Rectangle {
                    id: prepBtn
                    x: 35; y: 10; width: prepText.implicitWidth + 40; height: 32; radius: 4
                    color: prepHover.hovered ? theme.rowHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                    Text { id: prepText; anchors.centerIn: parent; text: qsTr("Prepare for this meeting"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(prepBtn, theme.textSecondary) }
                    HoverHandler { id: prepHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.askCopilot("Prepare for this meeting") }
                    Accessible.role: Accessible.Button; Accessible.name: prepText.text
                }
            }
            // The description, after Prepare for this meeting.
            DetailRow {
                // (A Teams meeting's join details, from the line of
                // underscores on, aren't shown: Teams' card leaves them out.)
                readonly property string own: (details.ev.preview || "").replace(/_{4,}[\s\S]*$/, "").replace(/\s+/g, " ").trim()
                visible: !!own
                textTop: 13; iconTop: 14; bottomGap: 11
                icon: "text-description-20"
                text: own
                lines: 5
            }
            // Your answer, as Teams' card asks for it.
            Column {
                visible: details.invite && !details.ev.is_cancelled && (!details.answered || details.changing)
                topPadding: 12; spacing: 8
                Row {
                    spacing: 12
                    FluentIcon { name: "calendar-person-20"; size: 17; color: theme.textSecondary }
                    Rectangle {
                        id: emailBox
                        width: 20; height: 20; radius: 2
                        color: details.emailOrganizer ? theme.brandFill : "transparent"
                        border.color: details.emailOrganizer ? theme.brandFill : theme.textSecondary
                        FluentIcon { visible: details.emailOrganizer; anchors.centerIn: parent; name: "checkmark-12"; size: 14; color: theme.onFill(emailBox, "white") }
                        TapHandler { onTapped: details.emailOrganizer = !details.emailOrganizer }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: qsTr("Email organizer")
                        Accessible.checked: details.emailOrganizer
                    }
                    Text { text: qsTr("Email organizer"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                }
                Rectangle {
                    x: 37; width: 309; height: 31
                    color: theme.menu; border.color: note.activeFocus ? theme.brand : root.cardLine
                    TextInput {
                        id: note
                        x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                        enabled: details.emailOrganizer
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        Text { visible: !note.text; text: qsTr("Add a message (optional)"); color: theme.textSecondary; font: note.font }
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Add a message (optional)")
                }
                Row {
                    x: 37; spacing: 6
                    Repeater {
                        model: [{ r: "Accept", t: qsTr("Accept"), icon: "checkmark-20", c: "#498205" }, { r: "Decline", t: qsTr("Decline"), icon: "dismiss-20", c: "#E81123" }, { r: "Tentative", t: qsTr("Tentative"), icon: "question-20", c: "#881798" }]
                        Rectangle {
                            id: rb
                            required property var modelData
                            width: rbRow.implicitWidth + 18; height: 32; radius: 2
                            color: rbh.hovered ? theme.rowHover : modelData.r === "Accept" ? theme.pick("#FAFAFA", "#1F1F1F", "#000000") : theme.menu
                            border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                            Row {
                                id: rbRow
                                anchors.centerIn: parent; spacing: 8
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: rb.modelData.icon; size: 16; color: theme.hc(rb.modelData.c, "#FFFFFF") }
                                Text { visible: !details.series || rb.modelData.r !== "Tentative"; anchors.verticalCenter: parent.verticalCenter; text: rb.modelData.t; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                                FluentIcon { visible: details.series; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                            }
                            HoverHandler { id: rbh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: details.series ? scopeMenu.openFor(rb.modelData.r, rb) : details.respond(rb.modelData.r, false) }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.t
                        }
                    }
                }
            }
            // Answered: the answer and Change.
            Row {
                visible: details.invite && details.answered && !details.changing
                topPadding: 12; spacing: 12
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "calendar-person-20"; size: 17; color: theme.textSecondary }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter; size: 16
                    name: ({ accepted: "checkmark-20", declined: "dismiss-20", tentativelyAccepted: "question-20" })[details.ev.response] || "star-20"
                    color: theme.hc(({ accepted: "#498205", declined: "#E81123", tentativelyAccepted: "#881798" })[details.ev.response] || "#5B5FC7", "#FFFFFF")
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ({ accepted: qsTr("Accepted"), declined: qsTr("Declined"), tentativelyAccepted: qsTr("Tentative"), following: qsTr("Following") })[details.ev.response] || ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; text: qsTr("Change"); font.family: theme.font; font.pixelSize: 14; color: theme.brand
                    TapHandler { onTapped: details.changing = true }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Change")
                }
            }
            // Your event: Edit (for a series ▾ This event / This and all
            // following events / All events in the series) and Cancel (for
            // a series ▾ with the same three), 20 under a line and 30 above
            // the card's edge.
            Item {
                visible: details.ev.is_organizer === true && !details.confirming && !details.cancelScope
                width: 358; height: visible ? 66 : 0
                Rectangle { x: 34; width: 324; height: 1; color: root.cardLine }
                Row {
                    x: 34; y: 20; spacing: 6
                    CardButton {
                        id: editBtn
                        icon: "edit-20"; iconColor: theme.pick("#5B5FC7", theme.textStrong, "#0F6ABA"); label: qsTr("Edit")
                        chevron: details.series
                        onClicked: { if (details.series) editScopeMenu.openFor(editBtn); else { const e = details.ev; details.close(); root.openPage(e) } }
                    }
                    CardButton {
                        id: cancelBtn
                        icon: "calendar-cancel-20"; iconColor: theme.pick("#E81123", "#C50F1F", "#E81123")
                        label: details.cancels ? qsTr("Cancel") : qsTr("Delete")
                        chevron: details.cancels && details.series
                        onClicked: {
                            if (!details.cancels) details.confirming = true
                            else if (details.series) cancelScopeMenu.openFor(cancelBtn)
                            else details.beginCancel("single")
                        }
                    }
                }
            }
            // Cancel (Teams desktop, winpc 2026-11-23): the Edit and Cancel
            // row turns into "Cancel … and notify attendees" (14/600
            // #616161, its glyph 17 px #A4262C) 16 under the line, the
            // message box 8 under it (320 x 72 at 39, a 0.67 #616161 edge,
            // padding 12), then Send and Discard 12 under the box; the card
            // keeps its bottom edge and grows upwards.
            Item {
                id: cancelCompose
                visible: !!details.cancelScope
                width: 358; height: visible ? cancelButtons.y + 32 : 0
                Rectangle { x: 34; width: 324; height: 1; color: root.cardLine }
                FluentIcon { x: -1; y: cancelHead.y + (cancelHead.height - 17) / 2; name: "calendar-cancel-20"; size: 17; color: theme.hc("#A4262C", "#FFFFFF") }
                Text {
                    id: cancelHead
                    x: 24; y: 16; width: 342; wrapMode: Text.Wrap
                    text: details.cancelScope === "following" ? qsTr("Cancel this and all following events and notify attendees")
                        : details.cancelScope === "series" ? qsTr("Cancel all events in the series and notify attendees")
                        : details.cancelScope === "occurrence" ? qsTr("Cancel this event and notify attendees")
                        : qsTr("Cancel event and notify attendees")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 17; lineHeightMode: Text.FixedHeight
                    color: theme.textSecondary
                }
                Rectangle {
                    id: cancelBox
                    x: 22; y: cancelHead.y + cancelHead.lineCount * 17 + 8; width: 320; height: 72
                    // (#616161 while typing, else #D1D1D1.)
                    color: theme.menu; border.width: 0.67; border.color: cancelNote.activeFocus ? theme.textSecondary : theme.stroke
                    Flickable {
                        id: cancelFlick
                        x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
                        contentHeight: cancelNote.implicitHeight; clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        TextEdit {
                            id: cancelNote
                            width: cancelFlick.width; wrapMode: TextEdit.Wrap
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true
                            onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > cancelFlick.contentY + cancelFlick.height) cancelFlick.contentY = cursorRectangle.y + cursorRectangle.height - cancelFlick.height
                            Accessible.role: Accessible.EditableText
                            Accessible.name: cancelHead.text + ", " + qsTr("Add an optional message.")
                            Text { visible: !cancelNote.text; text: qsTr("Add a message (optional)"); color: theme.textSecondary; font: cancelNote.font }
                        }
                    }
                }
                Row {
                    id: cancelButtons
                    x: 22; y: cancelBox.y + cancelBox.height + 12; spacing: 12
                    ComposeButton { primary: true; icon: "send-20"; label: qsTr("Send"); onClicked: details.sendCancel() }
                    ComposeButton { icon: "delete-20"; label: qsTr("Discard"); onClicked: details.endCancel() }
                }
            }
            // Delete an appointment (no attendees).
            Column {
                visible: details.confirming
                topPadding: 14; spacing: 10
                Text {
                    width: 358; wrapMode: Text.Wrap
                    text: qsTr("Delete this event?")
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
                }
                Row {
                    spacing: 8
                    CardButton { danger: true; label: qsTr("Delete"); onClicked: { root.deleteEvent(details.ev.id); details.close() } }
                    CardButton { label: qsTr("Keep it"); onClicked: details.confirming = false }
                }
            }
        }
    }
    // A series answer: this event or the whole series.
    // Copilot's prompts under a meeting's card (a separate surface 4 below
    // it: Copilot's glyph at 12, chips 25.33 tall 8 apart at 40, padding 2
    // 8, radius 8, a #D1D1D1 edge, 14/20).
    Popup {
        id: cardPrompts
        visible: details.visible && root.copilotEntries && (root.evIsMeeting(details.ev) || !!details.ev.is_online_meeting)
        x: details.x; y: details.y + details.height + 4
        width: details.width; padding: 0
        closePolicy: Popup.NoAutoClose
        height: promptCol.implicitHeight + 16.5
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Item {
            FluentIcon { x: 12; y: 12.5; name: "mo-copilot"; size: 16; color: theme.textSecondary }
            Column {
                id: promptCol
                x: 40; y: 8.5; spacing: 8
                Repeater {
                    // (Not "What are key talking points?" once the meeting
                    // is on, as Teams' card.)
                    model: (details.live ? [] : [{ k: "What are key talking points?", t: qsTr("What are key talking points?") }]).concat([{ k: "What are the anticipated outcomes?", t: qsTr("What are the anticipated outcomes?") }, { k: "What will this meeting cover?", t: qsTr("What will this meeting cover?") }])
                    Rectangle {
                        id: chipP
                        required property var modelData
                        width: chipPText.implicitWidth + 16; height: 25.33; radius: 8
                        color: chipPHover.hovered ? theme.rowHover : theme.surface
                        border.width: 0.67; border.color: theme.stroke
                        Text { id: chipPText; anchors.centerIn: parent; text: chipP.modelData.t; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(chipP, theme.text) }
                        HoverHandler { id: chipPHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.askCopilot(chipP.modelData.k) }
                        Accessible.role: Accessible.Button; Accessible.name: chipP.modelData.t
                    }
                }
            }
        }
    }
    /// Copilot's entry points show for a Copilot licence (Teams' calendar:
    /// the Copilot button, the card's room, prepare and prompt rows).
    property bool copilotEntries: false
    function askCopilot(prompt) { details.close(); openCopilotWith(prompt, true) }
    // A suggestion or prompt goes to Copilot as Teams' calendar hands it
    // over: the pane's host sends updatePromptInputData {promptText,
    // correlationId, promptTimestamp, isDraft (not to be sent yet)} once the
    // pane is ready.
    property bool copilotReady: false
    property var copilotPending: null
    // The prompt each suggestion sends (Outlook's calendar strings).
    readonly property var copilotPrompts: ({
        "Find my next one-on-one with": ["When is my next one-on-one with /", false],
        "Show me meetings I haven't responded to next week": ["Show me meetings I haven't responded to next week? Don't offer to respond on my behalf", true],
        "What are the top three things I should focus on right now?": ["Look through all my emails, chats and meetings and let me know what are the top 3 things I need to get done in the future.", true],
        "Schedule 1 hour of focus time": ["Schedule 1 hour of focus time for me in the next week", true],
        "What are the anticipated outcomes?": ["For this meeting, search across all enterprise data (agenda, documents, chats, emails), gather only relevant information, and infer anticipated end-of-meeting outcomes to propose.", true]
    })
    function openCopilotWith(label, execute) {
        const p = copilotPrompts[label]
        copilotPending = { promptText: p ? p[0] : label, isDraft: p ? !p[1] : !execute }
        copilotOpen = true
        if (copilotReady) sendCopilotPrompt()
    }
    function sendCopilotPrompt() {
        if (!copilotPending || !copilotHost.item) return
        const d = Object.assign({ correlationId: guid(), promptTimestamp: new Date().toISOString(), queryAnnotations: [], rawEntityData: [], focusOnLoadTarget: "Compose" }, copilotPending)
        copilotPending = null
        copilotHost.item.sendFrameMessage("updatePromptInputData", [d])
    }
    // Propose new time where Outlook's own form can't be hosted (no
    // browser sign-in): its "Propose new time:" with the time, the answer
    // (Tentative or Decline), an optional message, Send.
    Dialog600 {
        id: proposeDialog
        property var ev: ({})
        property string response: "Tentative"
        property date day: new Date()
        property int startMin: 0
        property int minutes: 30
        function openFor(e, r) {
            ev = e; response = r
            const s = new Date(e.start_utc), en = new Date(e.end_utc)
            day = root.midnight(s); startMin = s.getHours() * 60 + s.getMinutes()
            minutes = Math.max(15, Math.round((en - s) / 60000))
            proposeNote.text = ""
            open()
        }
        readonly property date startAt: { const d = new Date(day); d.setHours(0, startMin, 0, 0); return d }
        readonly property date endAt: new Date(startAt.getTime() + minutes * 60000)
        function send() {
            root.calendarAction("propose", JSON.stringify({ event: { id: ev.id, ical_uid: ev.ical_uid, event_type: ev.event_type, start_utc: ev.start_utc },
                response: response, start: root.isoLocal(startAt), end: root.isoLocal(endAt), send: true, note: proposeNote.text }))
        }
        readonly property var times: { const out = []; for (let m = 0; m < 1440; m += 30) { const d = new Date(2000, 0, 1, 0, m); out.push([String(m), theme.time(d)]) } return out }
        contentItem: Column {
            spacing: 16
            Text { text: qsTr("Propose new time"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
            Text { width: 550; elide: Text.ElideRight; text: proposeDialog.ev.subject || ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Propose new time:"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                DatePickerField { width: 150; date: proposeDialog.day; onPicked: d => proposeDialog.day = root.midnight(d) }
                Dropdown { width: 120; label: theme.time(proposeDialog.startAt); options: proposeDialog.times; accessibleName: qsTr("Start time"); onPicked: c => proposeDialog.startMin = parseInt(c) }
                Dropdown { width: 120; label: theme.time(proposeDialog.endAt); accessibleName: qsTr("End time")
                    options: proposeDialog.times.filter(t => parseInt(t[0]) > proposeDialog.startMin); onPicked: c => proposeDialog.minutes = parseInt(c) - proposeDialog.startMin }
            }
            Dropdown {
                width: 180; label: proposeDialog.response === "Decline" ? qsTr("Decline") : qsTr("Tentative"); accessibleName: qsTr("Response")
                options: [["Tentative", qsTr("Tentative")], ["Decline", qsTr("Decline")]]
                onPicked: c => proposeDialog.response = c
            }
            Field600 { id: proposeNote; hint: qsTr("Add a message (optional)") }
            Row {
                anchors.right: parent.right; spacing: 8
                CardButton { label: qsTr("Cancel"); onClicked: proposeDialog.close() }
                CardButton { primary: true; icon: "send-20"; label: qsTr("Send"); onClicked: proposeDialog.send() }
            }
        }
    }
    // An event's right-click menu, as Teams' calendar (Outlook's
    // CalendarItemContextMenu): the Teams meeting's Join, Chat with
    // participants and Copy meeting link; Print; your answer (Accept,
    // Decline, Tentative, Propose new time) and Forward when invited;
    // Charm, Show as, Categorize and Private; Duplicate event, Save as
    // .ics and Delete. Print, Propose new time, Forward, Duplicate and
    // Save as .ics open Outlook's own forms, as Teams does.
    MenuPopup {
        id: tileMenu
        property var ev: ({})
        function openFor(e, item, px, py) {
            ev = e; parent = item; x = px; y = py
            items = build(e)
            open()
        }
        perItemIcons: true
        submenuMinWidth: 0
        function build(e) {
            const invited = e.is_organizer === false
            const r = e.response || ""
            const out = []
            if (e.join_url) out.push({ label: qsTr("Join Teams meeting"), icon: "video-20", act: "join" }, { label: qsTr("Chat with participants"), icon: "chat-20", act: "chat" }, { label: qsTr("Copy meeting link"), icon: "link-20", act: "copy" }, { separator: true })
            out.push({ label: qsTr("Print"), icon: "print-20", act: "owa:Print" }, { separator: true })
            if (invited) {
                out.push({ label: qsTr("Accept"), icon: "checkmark-20", checked: r === "accepted", act: "rsvp:Accept" },
                         { label: qsTr("Decline"), icon: "dismiss-20", checked: r === "declined", act: "rsvp:Decline" },
                         { label: qsTr("Tentative"), icon: "question-20", checked: r === "tentativelyAccepted", act: "rsvp:Tentative" })
                if (e.allow_new_time_proposals !== false) out.push({ label: qsTr("Propose new time"), icon: "calendar-arrow-right-20", act: "owa:Propose new time" })
                out.push({ label: qsTr("Forward"), icon: "arrow-forward-20", act: "owa:Forward" }, { separator: true })
            }
            const shows = [["free", qsTr("Free")], ["workingElsewhere", qsTr("Working elsewhere")], ["tentative", qsTr("Tentative")], ["busy", qsTr("Busy")], ["oof", qsTr("Away")]]
            // Charm › opens the charm picker beside it (Outlook's CharmPicker).
            out.push({ label: qsTr("Charm"), icon: root.charmOf(e) ? root.charmMenuIcon(root.charmOf(e)) : "emoji-20", chevron: true, flyout: true },
                     { label: qsTr("Show as"), icon: "status-20", submenu: shows.map(x => ({ label: x[1], checked: e.show_as === x[0], act: "showAs:" + x[0] })) },
                     { label: qsTr("Categorize"), icon: "tag-20", submenu: root.categories.map(c => ({ label: c.name, tag: root.categoryTag(c.color), checked: (e.categories || []).indexOf(c.name) >= 0, act: "cat:" + c.name })) },
                     { label: qsTr("Private"), icon: "lock-closed-20", checked: e.sensitivity === "private", act: "private" })
            // Instructions › (Copilot's calendar instructions, for a Copilot
            // user): Create instruction (not on your own meetings) hands
            // Copilot "Always {accept|follow|decline} meeting from {organizer}"
            // to finish; Manage instructions opens Outlook's Calendar
            // settings at Calendar instructions.
            if (copilotEntries && !e.is_draft) {
                const sub = []
                if (invited) sub.push({ label: qsTr("Create instruction"), act: "instr:create" })
                sub.push({ label: qsTr("Manage instructions"), act: "instr:manage" })
                out.push({ label: qsTr("Instructions"), icon: "calendar-sparkle-20", submenu: sub })
            }
            out.push({ separator: true },
                     { label: qsTr("Duplicate event"), icon: "copy-20", act: "owa:Duplicate" },
                     { label: qsTr("Save as .ics"), icon: "arrow-download-20", act: "owa:Save as .ics" },
                     { label: qsTr("Delete"), icon: "delete-20", act: "delete" })
            return out
        }
        onPicked: i => root.tileAct(ev, items[i].act)
        onSubPicked: (i, j) => root.tileAct(ev, items[i].submenu[j].act)
        onFlyoutRequested: (i, row) => {
            if (i < 0 || !row) { tileCharms.close(); return }
            const p = row.mapToItem(root, row.width + 8, 0)
            tileCharms.x = p.x + tileCharms.width > root.width - 8 ? row.mapToItem(root, 0, 0).x - tileCharms.width - 8 : p.x
            tileCharms.y = Math.max(8, Math.min(root.height - tileCharms.height - 8, p.y))
            tileCharms.open()
        }
        onClosed: tileCharms.close()
    }
    // An event's charm: Outlook names it ("Plane"); the picker's ids.
    function charmOf(e) {
        const c = (e && e.charm) || ""
        if (!c) return 0
        if (/^[0-9]+$/.test(c)) return parseInt(c)
        const k = c.toLowerCase(), hit = charms.find(x => x[1].replace(/[^A-Za-z]/g, "").toLowerCase() === k)
        return hit ? hit[0] : 0
    }
    Popup {
        id: tileCharms
        parent: root
        padding: 4; width: 454; height: 112
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Grid {
            columns: 12; spacing: 4
            Repeater {
                model: root.charms
                Rectangle {
                    id: tcCell
                    required property var modelData
                    width: 32; height: 32; radius: 2
                    color: root.charmOf(tileMenu.ev) === modelData[0] ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : tcHover.hovered ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: tcCell.modelData[2] || "prohibited-20"; size: 17; color: theme.onFill(tcCell, theme.textSecondary) }
                    HoverHandler { id: tcHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { const e = tileMenu.ev; tileCharms.close(); tileMenu.close(); root.tileAct(e, "charm:" + tcCell.modelData[0]) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1 icon").arg(tcCell.modelData[3])
                }
            }
        }
    }
    function tileCharmsForTest() { return tileCharms }
    function tileAct(e, a) {
        if (!a) return
        const id = e.id
        if (a === "join") root.joinMeeting(e.join_url, e.subject || qsTr("Meeting"))
        else if (a === "chat") root.openMeetingChat(e.join_url, e.subject || qsTr("Meeting"))
        else if (a === "copy") backend.copyText(e.join_url)
        else if (a === "owa:Propose new time" && !objectId) proposeDialog.openFor(e, "Tentative")
        else if (a.startsWith("owa:")) openOwaItem(e, a.slice(4))
        else if (a.startsWith("rsvp:")) calendarAction("respond", JSON.stringify({ id: id, event: { id: id, ical_uid: e.ical_uid, event_type: e.event_type, start_utc: e.start_utc, series_master_id: e.series_master_id }, series: false, response: a.slice(5), send: true, note: "" }))
        else if (a.startsWith("charm:")) calendarAction("charm", JSON.stringify({ id: id, charm: parseInt(a.slice(6)) }))
        else if (a.startsWith("showAs:")) calendarAction("patchEvent", JSON.stringify({ id: id, patch: { showAs: a.slice(7) } }))
        else if (a.startsWith("cat:")) {
            const c = (e.categories || []).slice(), n = a.slice(4), k = c.indexOf(n)
            if (k >= 0) c.splice(k, 1); else c.push(n)
            calendarAction("patchEvent", JSON.stringify({ id: id, patch: { categories: c } }))
        }
        else if (a === "private") calendarAction("patchEvent", JSON.stringify({ id: id, patch: { sensitivity: e.sensitivity === "private" ? "normal" : "private" } }))
        else if (a === "delete") { details.show(e, null); if (details.cancels && e.is_organizer) details.beginCancel(details.series ? "occurrence" : "single"); else details.confirming = true }
        else if (a === "instr:manage") openOutlookCommand(["Calendar settings", "Calendar instructions"])
        else if (a === "instr:create") {
            const verb = e.response === "tentativelyAccepted" ? "follow" : e.response === "declined" ? "decline" : "accept"
            if (e.is_cancelled) openCopilotWith("Automatically delete canceled meetings", false)
            else if (e.organizer) openCopilotWith("Always " + verb + " meeting from " + e.organizer, false)
            else openCopilotWith("Help me create calendar instructions", true)
        }
    }
    // The toolbar's "…" (Outlook's CalendarSurfaceToolbar overflow): what
    // doesn't fit (Filter; with Copilot's pane open, the toolbar's own
    // items), Share (a submenu of your calendars when more than one can be
    // shared), Print, Calendar settings.
    readonly property var shareable: calendarList.filter(c => c.can_share)
    readonly property var moreMenuItems: {
        const out = []
        // With the pane open (measured on winpc): Go to today, previous,
        // next, the range, the view, Filter, a divider, New (split), then
        // Share, Print, Calendar settings.
        if (copilotOpen) out.push(
            { label: qsTr("Go to today"), icon: "calendar-today-20", act: "today" },
            { label: monthView ? qsTr("Go to previous month") : view === "day" ? qsTr("Go to previous day") : qsTr("Go to previous week"), icon: "chevron-left-20", act: "prev" },
            { label: monthView ? qsTr("Go to next month") : view === "day" ? qsTr("Go to next day") : qsTr("Go to next week"), icon: "chevron-right-20", act: "next" },
            { label: rangeLabel, icon: "calendar-month-20", act: "range" },
            { label: ({ day: qsTr("Day"), workweek: qsTr("Work week"), week: qsTr("Week"), month: qsTr("Month") })[view], icon: "calendar-work-week-20", submenu: viewMenuItems.filter(x => !x.separator && !x.heading && x.act), act: "view" })
        if (!filterInline || copilotOpen) out.push({ label: filterApplied ? qsTr("Filter applied") : qsTr("Filter"), icon: "filter-20", outlined: filterApplied, submenu: filterMenuItems, act: "filter" }, { separator: true })
        if (copilotOpen) out.push({ label: qsTr("New"), icon: "calendar-add-20", split: true, act: "new", submenu: [{ label: qsTr("Event"), icon: "calendar-ltr-20", act: "newEvent" }, { label: qsTr("Channel meeting"), icon: "channel-20", act: "new" }] })
        out.push(shareable.length > 1
            ? { label: qsTr("Share"), icon: "share-20", submenu: shareable.map(c => ({ label: c.name, icon: "calendar-ltr-20", act: "share:" + c.name })), act: "share" }
            : { label: qsTr("Share"), icon: "share-20", act: "share" },
            { label: qsTr("Print"), icon: "print-20", act: "print" },
            { label: qsTr("Calendar settings"), icon: "settings-20", act: "settings" })
        return out
    }
    function moreAct(a) {
        if (!a) return
        if (Array.isArray(a)) { viewAct(a); return }
        if (a === "share") openOutlookCommand(["Share"])
        else if (a.startsWith("share:")) openOutlookCommand(["Share", a.slice(6)])
        else if (a === "print") openOutlookCommand(["Print"])
        else if (a === "settings") openOutlookCommand(["Calendar settings"])
        else if (a === "today") start = startFor(new Date())
        else if (a === "prev") shift(-1)
        else if (a === "next") shift(1)
        else if (a === "range") { month.shown = new Date(start.getFullYear(), start.getMonth(), 1); paneShown = true }
        else if (a === "newEvent") openEventForm()
        else if (a === "new") openForm(null, [], null)
    }
    function tileMenuForTest(e) { tileMenu.openFor(e, root, 400, 200); return tileMenu }

    // Outlook's event page, hosted as Teams hosts it (its reading form,
    // hosted/calendar/item/<id>), opening one of its own commands when it
    // is up: Propose new time (Outlook's propose form with its scheduling
    // grid), Print, Forward, Duplicate, Save as .ics.
    function owaItemPath(e) {
        let id = (e.id || "").replace(/-/g, "/").replace(/_/g, "+")
        while (id.length % 4) id += "="
        return "/hosted/calendar/item/" + encodeURIComponent(id)
    }
    function openOwaItem(e, command) {
        openOutlook(surfaceUrl(), owaItemPath(e), command ? [command] : [], false)
    }
    /// Outlook's calendar surface, hosted as Teams hosts it, for its own
    /// "…" commands' dialogs (Share, Print, Calendar settings); the layer
    /// closes with the dialog.
    function surfaceUrl() { return "https://outlook.office.com/hosted/calendar/'OID:" + objectId + "@" + tenantId + "'" }
    function openOutlookCommand(steps) { openOutlook(surfaceUrl(), "", ["More options"].concat(steps), true) }
    function openOutlook(url, route, steps, autoClose) {
        details.close()
        owaItemLayer.url = url; owaItemLayer.route = route; owaItemLayer.steps = steps; owaItemLayer.autoClose = autoClose
        owaItemHost.active = false; owaItemLayer.visible = true; owaItemHost.active = true
    }
    // Drives Outlook's own page as a click would. `route`: the page to show
    // first (Outlook's router: the event page, which a fresh load sends back
    // to the calendar view); then each step names a button or menu item by
    // its text or label, clicked in turn (one kept in the answer button's
    // or More's menu is found by opening those once each). The page asks
    // its host to close (stageView.self.close) when Outlook leaves the
    // event page (Send, Cancel, Close) or, with autoClose, once the dialog
    // the steps opened has gone.
    function owaCommandScript(route, steps, autoClose) {
        return "(() => { if (location.host !== 'outlook.office.com' || !location.pathname.startsWith('/hosted/calendar')) return;"
            + " const route = " + JSON.stringify(route) + ", steps = " + JSON.stringify(steps) + ", autoClose = " + (autoClose ? "true" : "false") + ";"
            + " if (!route && !steps.length) return;"
            // innerText: what shows (Fluent tabs keep a hidden copy of their label).
            + " const txt = el => (el.innerText || el.textContent || '').replace(/[^\\x20-\\x7e]/g, ' ').replace(/\\s+/g, ' ').trim();"
            + " const lab = el => (el.getAttribute('aria-label') || txt(el)).trim();"
            + " let n = 0, k = 0, routed = !route, onRoute = false, opened = new Set(), shown = 0, gone = 0;"
            + " const close = () => window.parent.postMessage({ id: 990001, func: 'stageView.self.close', args: [], timestamp: Date.now() }, '*');"
            + " const t = setInterval(() => { n++;"
            + "  const all = [...document.querySelectorAll('button,[role=button],[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=tab],[role=treeitem],[role=link],a')].filter(b => b.offsetParent);"
            + "  if (!routed) { if (all.length < 5) return; routed = true; history.pushState({}, '', route); dispatchEvent(new PopStateEvent('popstate', { state: {} })); n = 0; return; }"
            + "  if (route) { const here = location.pathname.startsWith('/hosted/calendar/item/') || location.pathname.startsWith('/hosted/calendar/deeplink/');"
            + "   if (here) onRoute = true; else if (onRoute) { clearInterval(t); close(); return; } }"
            + "  if (k >= steps.length) { if (!autoClose) return;"
            + "   const d = document.querySelector('[role=dialog],[role=alertdialog]');"
            + "   if (d) { shown = 1; gone = 0 } else if (shown && ++gone > 4) { clearInterval(t); close() } else if (!shown && n > 200) { clearInterval(t); close() }"
            + "   return; }"
            + "  if (n > 200) { k = steps.length; if (autoClose) { clearInterval(t); close() } return; }"
            + "  const want = steps[k];"
            + "  const hit = all.find(b => txt(b) === want || lab(b) === want);"
            + "  if (hit) { hit.click(); k++; n = 0; return; }"
            + "  if (n % 3) return;"
            + "  const menu = all.find(b => b.getAttribute('aria-haspopup') && b.getAttribute('aria-expanded') !== 'true' && !opened.has(lab(b))"
            + "   && /^(Accept|Accepted|Tentative|Tentatively accepted|Decline|Declined|Respond|RSVP|More actions|More options|More)/.test(lab(b)));"
            + "  if (menu) { opened.add(lab(menu)); menu.click(); }"
            + " }, 250); })()"
    }
    Rectangle {
        id: owaItemLayer
        visible: false
        anchors.fill: parent
        color: root.calOff
        z: 11
        property string url: ""
        property string route: ""
        property var steps: []
        property bool autoClose: false
        Loader {
            id: owaItemHost
            active: false
            anchors.fill: parent
            sourceComponent: WebApp {
                showHeader: false; teamsHost: true; deepNaa: true
                appName: "Calendar"; appId: "ef56c0de-36fc-4ef8-b417-3d82ba9d073c"
                homeTemplate: owaItemLayer.url
                hostContext: ({ entityId: "calendar" })
                frameScript: root.owaCommandScript(owaItemLayer.route, owaItemLayer.steps, owaItemLayer.autoClose)
                printQuietly: root.printQuietlyForTest
                onPagePrinted: (path, ok) => console.warn("CALTEST printed", path, ok)
                onHostEvent: (name, json) => {
                    console.warn("CALITEM host", name, (json || "").slice(0, 300))
                    if (name === "stageViewClose") root.closeOwaItem()
                    // The form's own Open in new window.
                    else if (name === "stageViewOpen") { root.closeOwaItem(); root.popOutCompose(JSON.parse(json || "{}")) }
                }
            }
        }
    }
    property bool printQuietlyForTest: false
    function closeOwaItem() { owaItemLayer.visible = false; owaItemHost.active = false; emitRange() }
    function owaItemForTest() { return owaItemHost.item }
    function proposeForTest(e, response, start, minutes, note) {
        details.close(); proposeDialog.openFor(e, response)
        proposeDialog.day = midnight(start); proposeDialog.startMin = start.getHours() * 60 + start.getMinutes(); proposeDialog.minutes = minutes
        proposeNote.text = note || ""
    }
    function sendProposalForTest() { proposeDialog.send() }
    MenuPopup {
        id: scopeMenu
        property string response
        function openFor(r, item) { response = r; parent = item; x = 0; y = item.height + 2; open() }
        width: 180
        items: [{ label: qsTr("This event") }, { label: qsTr("All events in the series") }]
        onPicked: i => details.respond(scopeMenu.response, i === 1)
    }
    // Your series' Edit ▾ on the card (Teams desktop, winpc 2026-11-23):
    // the event page for this event, this and all following events, or
    // the series.
    MenuPopup {
        id: editScopeMenu
        // (Outlook's ContextualMenu: 194.33 wide, 36 px rows, labels 8 in,
        // right under the button.)
        function openFor(item) { parent = item; x = 0; y = item.height; open() }
        fabric: true; fabricWidth: 194.33; labelInset: 8
        items: [{ label: qsTr("This event") }, { label: qsTr("This and all following events") }, { label: qsTr("All events in the series") }]
        onPicked: i => { const e = details.ev; details.close(); root.openPage(e, ["occurrence", "following", "series"][i]) }
    }
    function editScopeItemsForTest() { return editScopeMenu.items.map(x => x.label) }
    // The card's Join ▾ (Teams desktop, winpc 2026-11-23).
    MenuPopup {
        id: joinMenu
        function openFor(item) { parent = item; x = -78; y = item.height + 2; open() }
        items: [{ label: qsTr("Join Teams meeting"), icon: "video-20" }, { label: qsTr("Copy join link"), icon: "link-20" }]
        onPicked: i => { const e = details.ev; if (i === 0) { details.close(); root.joinMeeting(e.join_url, e.subject || qsTr("Meeting")) } else backend.copyText(e.join_url) }
    }
    // Your series' Cancel ▾ on the card: the same three (Teams desktop,
    // winpc 2026-11-23), then the cancel message.
    MenuPopup {
        id: cancelScopeMenu
        // (Outlook's ContextualMenu: 194.33 wide, 36 px rows, labels 8 in,
        // right under the button.)
        function openFor(item) { parent = item; x = 0; y = item.height; open() }
        fabric: true; fabricWidth: 194.33; labelInset: 8
        items: [{ label: qsTr("This event") }, { label: qsTr("This and all following events") }, { label: qsTr("All events in the series") }]
        onPicked: i => details.beginCancel(["occurrence", "following", "series"][i])
    }
    function cancelScopeItemsForTest() { return cancelScopeMenu.items.map(x => x.label) }
    function cancelForTest(scope, msg) { details.beginCancel(scope); Qt.callLater(() => { cancelNote.text = msg || "" }) }
    function sendCancelForTest() { details.sendCancel() }

    component DetailRow: Item {
        id: dr
        property alias icon: drIcon.name
        property alias text: drText.text
        property string suffix: ""
        property int lines: 2
        /// Its line on top (the first row has the title's), the text's y
        /// under it, the glyph's, and the space above the next line.
        property bool line: true
        property real textTop: 9
        property real iconTop: textTop
        property real bottomGap: 9
        /// A link (Outlook's 14/20 #4F52B2 button) instead of text.
        property bool link: false
        /// A link under the text, 2 below it (a Teams meeting's "Add a
        /// room with Copilot" under "No location added").
        property string linkBelow: ""
        signal clicked()
        width: 358; height: visible ? textTop + drText.height + (linkBelow ? 22 : 0) + bottomGap : 0
        Rectangle { visible: dr.line; x: 34; width: 324; height: 1; color: root.cardLine }
        FluentIcon { id: drIcon; x: 2; y: dr.iconTop; size: 20; color: theme.textSecondary }
        Text {
            id: drText
            x: 35; y: dr.textTop; width: dr.suffix || dr.link ? Math.min(implicitWidth, dr.link ? 314 : 250) : 314; wrapMode: Text.Wrap; maximumLineCount: dr.lines; elide: Text.ElideRight
            lineHeight: dr.line ? 20 : 1; lineHeightMode: dr.line ? Text.FixedHeight : Text.ProportionalHeight
            font.family: theme.font; font.pixelSize: 14; color: dr.link ? root.calLink : theme.textSecondary
            HoverHandler { enabled: dr.link; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: dr.link; onTapped: dr.clicked() }
            Accessible.role: dr.link ? Accessible.Button : Accessible.StaticText
            Accessible.name: text
        }
        Text {
            visible: !!dr.linkBelow
            x: 35; y: dr.textTop + drText.height + 2; height: 20; verticalAlignment: Text.AlignVCenter
            text: dr.linkBelow
            font.family: theme.font; font.pixelSize: 14; color: root.calLink
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dr.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: text
        }
        Row {
            visible: !!dr.suffix
            x: drText.x + drText.width + 10; y: dr.textTop + 2; spacing: 4
            Text { text: dr.suffix; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            FluentIcon { name: "arrow-repeat-all-16"; size: 14; color: theme.textSecondary }
        }
    }
    // The cancel message's Send and Discard (Outlook's buttons: 32 tall,
    // padding 0 12, a 20 px glyph 4 in, the label 14/600 8 after it; Send
    // brand, Discard white with a #BDBDBD edge).
    component ComposeButton: Rectangle {
        id: kb
        property string icon
        property string label
        property bool primary: false
        signal clicked()
        width: kbRow.implicitWidth + 33.33; height: 32; radius: 4
        color: primary ? (kbh.hovered ? theme.brandHover : theme.brandFill) : (kbh.hovered ? theme.rowHover : theme.menu)
        border.width: 0.67; border.color: primary ? theme.brandFill : theme.pick("#BDBDBD", "#666666", "#FFFFFF")
        Row {
            id: kbRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: kb.icon; size: 20; color: theme.onFill(kb, kb.primary ? "white" : theme.textSecondary) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: kb.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(kb, kb.primary ? "white" : theme.textSecondary) }
        }
        HoverHandler { id: kbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: kb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: kb.label
    }
    component CardButton: Rectangle {
        id: cb
        property string icon
        property string label
        property bool primary: false
        property bool danger: false
        /// A ▾ after the label (a series' Edit).
        property bool chevron: false
        property color iconColor: primary || danger ? "white" : theme.textStrong
        /// Fluent's buttons are at least 96 wide (Chat); Join's part of
        /// its split button is 77.
        property real minWidth: 0
        signal clicked()
        width: Math.max(minWidth, cbRow.implicitWidth + 24); height: 32; radius: 4
        color: primary ? (cbh.hovered ? theme.brandHover : theme.brandFill)
            : danger ? (cbh.hovered ? theme.hc("#BC2F32", "#1AEBFF") : theme.hc("#D13438", "#000000"))
            : (cbh.hovered ? theme.rowHover : theme.menu)
        border.color: primary || danger ? "transparent" : root.cardEdge
        Row {
            id: cbRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!cb.icon; anchors.verticalCenter: parent.verticalCenter; name: cb.icon; size: 18; color: theme.onFill(cb, cb.iconColor) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cb.label
                font.family: theme.font; font.pixelSize: theme.base; font.weight: cb.primary || cb.danger || cb.label === qsTr("Chat") ? Font.DemiBold : Font.Normal
                color: theme.onFill(cb, cb.primary || cb.danger ? "white" : theme.text)
            }
            FluentIcon { visible: cb.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(cb, theme.textSecondary) }
        }
        HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: cb.label
    }

    // ── New ▸ Live Event (measured in Teams desktop 2026-11-19): Teams'
    // retirement notice, a 340 x 209 dialog (radius 2, title 20/400 #242424,
    // text 14/400 #616161 in 292, "Create town hall" (primary, 145 x 32)
    // and "Continue" (99 x 32), radius 2). Create town hall opens the town
    // hall form; Continue opens Teams' "New live event" page saying live
    // events are retiring.
    Popup {
        id: liveEventsRetiring
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 0
        width: 340; height: lerCol.implicitHeight + 23.3
        background: Rectangle { radius: 2; color: theme.menu; border.color: theme.hc("transparent", "#FFFFFF") }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        contentItem: Item {
            Column {
                id: lerCol
                width: 340
                Text {
                    leftPadding: 24; topPadding: 16; rightPadding: 46; bottomPadding: 20; width: 340; wrapMode: Text.Wrap
                    text: qsTr("Teams Live Events is Retiring"); font.family: theme.font; font.pixelSize: 20; color: theme.text
                }
                Text {
                    x: 24; width: 292; wrapMode: Text.Wrap; textFormat: Text.StyledText
                    text: qsTr("Teams Live Events is retiring. Please transition to Teams town hall to get the improved experience for large digital and hybrid events at scale. For more information, ") + "<a href=\"https://go.microsoft.com/fwlink/?linkid=2347480\">" + qsTr("Learn more") + "</a>."
                    linkColor: theme.brand; onLinkActivated: l => backend.openExternal(l)
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Item { width: 1; height: 16.7 }
                Row {
                    x: 340 - 24 - width; spacing: 8
                    Repeater {
                        model: [[qsTr("Create town hall"), true], [qsTr("Continue"), false]]
                        Rectangle {
                            id: lerBtn
                            required property var modelData
                            width: lerText.implicitWidth + 41.3; height: 32; radius: 2
                            color: lerBtn.modelData[1] ? (lerHover.hovered ? theme.brandHover : theme.brand) : (lerHover.hovered ? theme.hover : theme.surface)
                            border.width: lerBtn.modelData[1] ? 0 : 1; border.color: theme.hc("#8A8886", "#FFFFFF")
                            Text { id: lerText; anchors.centerIn: parent; text: lerBtn.modelData[0]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                   color: lerBtn.modelData[1] ? "white" : theme.textSecondary }
                            HoverHandler { id: lerHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { liveEventsRetiring.close(); if (lerBtn.modelData[1]) root.newEventTemplate("townhall"); else newLiveEvent.show() } }
                            Accessible.role: Accessible.Button; Accessible.name: lerBtn.modelData[0]
                        }
                    }
                }
            }
        }
    }
    // Continue: Teams' "New live event" window (946 x 713): the heading
    // (21/700 #616161 at 30, 49), the Prohibited glyph (80, #616161)
    // centred, "Teams live events is retiring, please use Teams town halls
    // for your large digital and hybrid events" (14/700, the link 14/400
    // brand), and Close (96 x 32, 600, a #D1D1D1 edge) at the bottom left.
    Window {
        id: newLiveEvent
        title: qsTr("Microsoft Teams")
        width: 946; height: 681
        color: theme.surface
        modality: Qt.NonModal
        Rectangle { anchors.fill: parent; color: theme.surface }
        Text { x: 30; y: 17.4; text: qsTr("New live event"); font.family: theme.font; font.pixelSize: 21; font.weight: Font.Bold; color: theme.textSecondary }
        FluentIcon { x: (parent.width - 80) / 2; y: 278.4; name: "prohibited-20-regular"; size: 80; color: theme.textSecondary }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 366.4
            textFormat: Text.StyledText; linkColor: theme.brand; onLinkActivated: l => backend.openExternal(l)
            text: qsTr("Teams live events is retiring, please use ") + "<a href=\"https://adoption.microsoft.com/en-us/microsoft-teams/meetings-webinars-and-town-halls/town-halls/\"><span style=\"font-weight:400\">" + qsTr("Teams town halls") + "</span></a>" + qsTr(" for your large digital and hybrid events")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
        }
        Rectangle {
            x: 30; y: parent.height - 61.3; width: 96; height: 32; radius: 4
            color: nleClose.hovered ? theme.hover : theme.surface; border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
            Text { anchors.centerIn: parent; text: qsTr("Close"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: nleClose; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: newLiveEvent.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
    }

    // ── Meet now: "Start a meeting now" ─────────────────────────────────
    component Dialog600: Popup {
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 24
        width: 600
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.hc("transparent", "#FFFFFF") }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    }
    component Field600: Rectangle {
        id: f6
        property alias text: f6in.text
        property alias input: f6in
        property string hint
        width: 550; height: 32; radius: 4
        color: theme.surface; border.color: f6in.activeFocus ? theme.brand : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        TextInput {
            id: f6in
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
            Text { visible: !f6in.text; text: f6.hint; color: theme.textSecondary; font: f6in.font }
        }
        Accessible.role: Accessible.EditableText
        Accessible.name: hint
    }
    Dialog600 {
        id: meetNowDialog
        property bool linkOnly: false
        property string link: ""
        function openFresh() { linkOnly = false; link = ""; meetName.text = qsTr("Meeting with %1").arg(root.me.name || ""); open() }
        contentItem: Column {
            spacing: 0
            Item {
                width: 550; height: 32
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Start a meeting now"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                NavButton { anchors.right: parent.right; icon: "dismiss-20"; tip: qsTr("Close"); onClicked: meetNowDialog.close() }
            }
            Item { width: 1; height: 16 }
            Text { text: qsTr("Meeting name"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 8 }
            Field600 { id: meetName; hint: qsTr("Meeting name") }
            Item { width: 1; height: 20 }
            Text {
                visible: !!meetNowDialog.link
                width: 550; wrapMode: Text.WrapAnywhere; text: meetNowDialog.link
                font.family: theme.font; font.pixelSize: 12; color: theme.brand
            }
            Item { visible: !!meetNowDialog.link; width: 1; height: 12 }
            Row {
                anchors.right: parent.right; spacing: 8
                CardButton { primary: true; icon: "video-20"; label: qsTr("Start meeting"); onClicked: { meetNowDialog.linkOnly = false; root.calendarAction("meetNow", JSON.stringify({ subject: meetName.text.trim() || "Meeting", start: true })) } }
                CardButton {
                    icon: "link-20"; label: meetNowDialog.link ? qsTr("Copy link") : qsTr("Get a link to share")
                    onClicked: {
                        if (meetNowDialog.link) { textCopy.text = meetNowDialog.link; textCopy.selectAll(); textCopy.copy(); return }
                        meetNowDialog.linkOnly = true
                        root.calendarAction("meetNow", JSON.stringify({ subject: meetName.text.trim() || "Meeting", start: false }))
                    }
                }
            }
        }
    }
    TextEdit { id: textCopy; visible: false }

    // ── Join with an ID ─────────────────────────────────────────────────
    Dialog600 {
        id: joinId
        function openFresh() { idField.text = ""; passField.text = ""; open(); idField.input.forceActiveFocus() }
        readonly property bool ready: idField.text.replace(/\s/g, "").length > 0 && passField.text.length > 0
        contentItem: Column {
            spacing: 0
            Item {
                width: 550; height: 32
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Join a meeting with an ID"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                NavButton { anchors.right: parent.right; icon: "dismiss-20"; tip: qsTr("Close"); onClicked: joinId.close() }
            }
            Item { width: 1; height: 16 }
            Row {
                spacing: 2
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Meeting ID"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                NavButton {
                    icon: "info-16"; iconSize: 12; tip: qsTr("You'll find the meeting ID with the other join info near the bottom of the meeting invite.")
                    ToolTip.visible: hovered2.hovered; ToolTip.text: tip
                    HoverHandler { id: hovered2 }
                }
            }
            Item { width: 1; height: 4 }
            Field600 { id: idField; hint: qsTr("Type a meeting ID") }
            Item { width: 1; height: 18 }
            Text { text: qsTr("Meeting passcode"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Item { width: 1; height: 12 }
            Field600 { id: passField; hint: qsTr("Type a meeting passcode") }
            Item { width: 1; height: 16 }
            Rectangle {
                id: joinIdButton
                anchors.right: parent.right
                width: jidRow.implicitWidth + 24; height: 32; radius: 4
                color: !joinId.ready ? theme.hc("#F0F0F0", "#000000") : jidh.hovered ? theme.brandHover : theme.brandFill
                Row {
                    id: jidRow
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "video-20"; size: 16; color: joinId.ready ? theme.onFill(joinIdButton, "white") : theme.pick("#BDBDBD", "#666666", "#3FF23F") }
                    Text { text: qsTr("Join Meeting"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: joinId.ready ? theme.onFill(joinIdButton, "white") : theme.pick("#BDBDBD", "#666666", "#3FF23F") }
                }
                HoverHandler { id: jidh; cursorShape: joinId.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: joinId.ready; onTapped: { root.joinWithId(idField.text.replace(/\s/g, ""), passField.text.trim()); joinId.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Join Meeting")
            }
        }
    }


    // ── Saved views: "Save current view" / "Edit view" (Teams' dialog,
    // measured on winpc 2026-11-18: 340 wide, radius 4, the title 16/600,
    // "Name this view" 14/600 #616161, the charm button 28 px, the name
    // field 232 x 32 with a 0.67 #8A8A8A edge, Save and Cancel 32 tall) ──
    Popup {
        id: saveViewDialog
        property var existing: null
        property int charm: 0
        function openFor(v) {
            existing = v
            charm = v && v.viewIcon !== undefined ? Number(v.viewIcon) || 0 : 0
            viewName.text = v ? (v.viewName || "") : ""
            open()
            viewName.forceActiveFocus()
        }
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 0
        width: 340; height: 208.67
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: Rectangle { radius: 4; color: theme.menu; border.color: theme.hc("transparent", "#FFFFFF") }
        contentItem: Item {
            Text {
                x: 27; y: 18; width: 220; elide: Text.ElideRight
                text: saveViewDialog.existing ? qsTr("Edit view") : qsTr("Save current view")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Rectangle {
                id: svClose
                x: 293; y: 15; width: 32; height: 32; radius: 2
                color: svCloseHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(svClose, theme.textSecondary) }
                HoverHandler { id: svCloseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: saveViewDialog.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
            }
            Text { x: 51; y: 61; text: qsTr("Name this view"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
            Rectangle {
                id: charmBtn
                x: 14; y: 92.67; width: 28; height: 28; radius: 2
                color: charmPicker.visible ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : charmHover.hovered ? theme.rowHover : "transparent"
                FluentIcon {
                    anchors.centerIn: parent
                    name: saveViewDialog.charm > 0 ? (root.charms.find(c => c[0] === saveViewDialog.charm) || [0, "", "symbols-20"])[2] : "symbols-20"
                    size: saveViewDialog.charm > 0 ? 17 : 14; color: theme.onFill(charmBtn, theme.brand)
                }
                HoverHandler { id: charmHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: charmPicker.visible ? charmPicker.close() : charmPicker.open() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Select an event charm button, %1 selected").arg(saveViewDialog.charm > 0 ? qsTr("%1 icon").arg((root.charms.find(c => c[0] === saveViewDialog.charm) || [0, "", "", qsTr("No")])[3]) : qsTr("No icon"))
                // The charms (Teams' CharmDefaultSet): 12 a row, 32 px each,
                // 4 apart, the chosen one #DCDFFA, glyphs 17 px #616161.
                Popup {
                    id: charmPicker
                    y: parent.height + 4; padding: 4
                    width: 454; height: 112
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Grid {
                        columns: 12; spacing: 4
                        Repeater {
                            model: root.charms
                            Rectangle {
                                id: charmCell
                                required property var modelData
                                width: 32; height: 32; radius: 2
                                color: saveViewDialog.charm === modelData[0] ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : cellHover.hovered ? theme.rowHover : "transparent"
                                FluentIcon { visible: !!charmCell.modelData[2]; anchors.centerIn: parent; name: charmCell.modelData[2]; size: 17; color: theme.onFill(charmCell, theme.textSecondary) }
                                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { saveViewDialog.charm = charmCell.modelData[0]; charmPicker.close() } }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("%1 icon").arg(charmCell.modelData[3])
                            }
                        }
                    }
                }
            }
            Rectangle {
                x: 51; y: 89.67; width: 232; height: 32; radius: 2
                color: theme.surface
                border.width: 0.67; border.color: viewName.activeFocus ? theme.brand : theme.hc("#8A8A8A", "#FFFFFF")
                TextInput {
                    id: viewName
                    x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                    onAccepted: if (text.trim().length) svSave.clicked()
                }
                Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Name this view")
            }
            Rectangle {
                id: svSave
                readonly property bool on: viewName.text.trim().length > 0
                signal clicked()
                onClicked: { root.saveView(saveViewDialog.existing, viewName.text.trim(), saveViewDialog.charm); saveViewDialog.close() }
                x: 144.81; y: 152.67; width: 80; height: 32; radius: 2
                color: !on ? theme.hc("#F5F5F5", "#000000") : svSaveHover.hovered ? theme.brandHover : theme.brandFill
                border.width: 0.67; border.color: on ? "transparent" : theme.hc("#F5F5F5", "#3FF23F")
                Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: svSave.on ? theme.onFill(svSave, "white") : theme.disabled }
                HoverHandler { id: svSaveHover; cursorShape: svSave.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: svSave.on; onTapped: svSave.clicked() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Save")
            }
            Rectangle {
                id: svCancel
                x: 232.81; y: 152.67; width: 83.19; height: 32; radius: 2
                color: svCancelHover.hovered ? theme.rowHover : theme.surface
                border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(svCancel, theme.textSecondary) }
                HoverHandler { id: svCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: saveViewDialog.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
            }
        }
    }
    // Saved views ▸ … ▸ Delete: Teams' confirmation ("Delete view").
    ConfirmDialog {
        id: deleteViewDialog
        property var view: null
        title: qsTr("Delete view")
        body: view ? qsTr("Do you want to delete the view \"%1\"?").arg(view.viewName || "") : ""
        confirmText: qsTr("Delete")
        onConfirmed: if (view) root.calendarAction("deleteView", JSON.stringify({ id: view.id }))
    }

    // ── Copilot's pane in the calendar (Teams' "Chat with Copilot", 580
    // wide on the right: "Copilot" 16/600, Collapse and Close 32 px, then
    // Outlook's Copilot (hosted/semanticoverview, its calendar scenario)
    // on #FAFAFA, as the hosted calendar frames it) ──────────────────────
    property string copilotPrompt: ""
    Rectangle {
        id: copilotPane
        visible: root.copilotOpen
        z: formLayer.visible ? 12 : 3
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: root.copilotWidth
        color: theme.surface
        FluentSurface { anchors.fill: parent; depth: 4; radius: 0; z: -1 }
        Text { x: 16.67; y: 21.67; text: qsTr("Copilot"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        NavButton { x: parent.width - 80; y: 20; icon: "panel-right-contract-20"; tip: qsTr("Collapse Copilot Chat"); onClicked: root.copilotOpen = false }
        NavButton { x: parent.width - 48; y: 20; icon: "dismiss-20"; tip: qsTr("Close Copilot Chat"); onClicked: root.copilotOpen = false }
        Rectangle {
            anchors { top: parent.top; topMargin: 59.33; left: parent.left; right: parent.right; bottom: parent.bottom }
            color: root.calOff
            Loader {
                id: copilotHost
                anchors.fill: parent
                active: root.copilotOpen
                sourceComponent: WebApp {
                    showHeader: false; teamsHost: true; deepNaa: true
                    appName: "Copilot"; appId: "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162"
                    frameContext: "sidePanel"
                    homeTemplate: root.copilotUrl()
                    onHostEvent: (name, json) => { if (name === "success" || name === "ChatReady") { root.copilotReady = true; root.sendCopilotPrompt() } }
                }
                onActiveChanged: if (!active) root.copilotReady = false
            }
        }
    }
    property string objectId: ""
    property string tenantId: ""
    function guid() { return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16) }) }
    function copilotUrl() {
        const q = ["hostApp=hub", "isanonymous=true", "culture=en-us", "mysite={mySiteDomain}", "hostName=TeamsModern", "hostClientType=desktop",
                   "sessionId=" + root.guid(), "renderingSurface=copilotSidePanel", "theme=" + (theme.dark ? "dark" : "default"), "includeAgents=true",
                   "M365ChatFeatures=disableFPSLoggingForStreaming,enableGptWrapperInChat,enablePrefetchAnnotationContext", "overrideScenario=CalendarSidepane",
                   "rootHub=TeamsModern", "topOrigin=https%3A%2F%2Fteams.microsoft.com", "isDeeplyNAASupported=true", "hostRing=" + backend.clientRing()]
        return "https://outlook.office.com/hosted/semanticoverview/Users('OID:" + root.objectId + "@" + root.tenantId + "')?" + q.join("&")
    }

    // ── New ▾ Event: Teams' event form, Outlook's (the hosted calendar's
    // compose page, as Teams' calendar opens it: hosted/calendar/deeplink/
    // compose with subEntityId {"type":"compose"}), under Teams' 48 px
    // "New event" bar (14/400 #616161, 16 in, a 0.67 #D1D1D1 edge) ──────
    /// New ▸ Webinar / Town hall ("webinar", "townhall").
    signal newEventTemplate(string key)
    function openEventForm() { composeLayer.visible = true; composeHost.active = true }
    Rectangle {
        id: composeLayer
        visible: false
        anchors.fill: parent
        color: root.calOff
        z: 11
        onVisibleChanged: if (!visible) { composeHost.active = false; root.refreshAfterCompose() }
        Rectangle {
            id: composeBar
            width: parent.width; height: 48
            color: theme.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.calLine }
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: qsTr("New event"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            // Open in new window (Teams' stage view pop-out of the same page).
            Rectangle {
                id: composePop
                anchors.right: composeClose.left; width: 48; height: 48
                color: cpHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "open-20"; size: 20; color: theme.onFill(composePop, theme.text) }
                HoverHandler { id: cpHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.popOutCompose({}) }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Open in new window")
            }
            Rectangle {
                id: composeClose
                anchors.right: parent.right; width: 48; height: 48
                color: ccHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(composeClose, theme.text) }
                HoverHandler { id: ccHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: composeLayer.visible = false }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
            }
        }
        Loader {
            id: composeHost
            anchors { top: composeBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            active: false
            sourceComponent: WebApp {
                showHeader: false; teamsHost: true; deepNaa: true
                appName: "Calendar"; appId: "ef56c0de-36fc-4ef8-b417-3d82ba9d073c"
                homeTemplate: "https://outlook.office.com/hosted/calendar/deeplink/compose"
                hostContext: ({ entityId: "calendar", subEntityId: JSON.stringify({ type: "compose" }) })
                onHostEvent: (name, json) => {
                    console.warn("CALCOMPOSE host", name, (json || "").slice(0, 300))
                    if (name === "stageViewClose") composeLayer.visible = false
                    // The form's own Open in new window: the same page in a
                    // window of its own (Teams' stage view pop-out).
                    else if (name === "stageViewOpen") root.popOutCompose(JSON.parse(json || "{}"))
                }
            }
        }
    }
    Component {
        id: composeWindow
        Window {
            id: cw
            property string url: ""
            title: qsTr("New event | Calendar")
            width: root.Window.window ? root.Window.window.width : 1280
            height: root.Window.window ? root.Window.window.height : 680
            color: root.calOff
            onClosing: Qt.callLater(() => cw.destroy())
            WebApp {
                anchors.fill: parent
                showHeader: false; teamsHost: true; deepNaa: true
                appName: "Calendar"; appId: "ef56c0de-36fc-4ef8-b417-3d82ba9d073c"
                homeTemplate: cw.url || "https://outlook.office.com/hosted/calendar/deeplink/compose"
                hostContext: ({ entityId: "calendar", subEntityId: JSON.stringify({ type: "compose" }) })
                frameContext: "content"
                onHostEvent: (name, json) => { if (name === "stageViewClose") { cw.close(); root.refreshAfterCompose() } }
            }
        }
    }
    signal composeClosed()
    function popOutCompose(p) {
        composeLayer.visible = false; composeHost.active = false
        const w = composeWindow.createObject(null, { url: p.contentUrl || "", title: p.title || qsTr("New event | Calendar") })
        w.show()
        popoutForTest = w
        return w
    }
    property var popoutForTest: null
    function refreshAfterCompose() { root.composeClosed(); emitRange() }

    // ── the scheduling form and event page (Teams' own, MeetingForm) ────
    Rectangle {
        id: formLayer
        visible: false
        anchors.fill: parent
        color: theme.surface
        z: 10
        anchors.rightMargin: root.copilotWidth
        MeetingForm {
            id: form
            anchors.fill: parent
            teams: root.teams
            people: root.people
            me: root.me
            charms: root.charms
            charm: root.charmOf(event)
            copilot: root.copilotEntries
            categories: root.categories
            categoryTagOf: c => root.categoryTag(c)
            onCommand: act => root.formAct(act)
            onCalendarCall: (op, args) => root.calendarAction(op, JSON.stringify(Object.assign({ id: form.event.id || "" }, args || {})))
            onCopilotPrompt: label => { if (label) root.openCopilotWith(label, true); else root.copilotOpen = !root.copilotOpen }
            onSearchPeople: q => root.searchPeople(q)
            onClosed: formLayer.visible = false
            onAvailabilityWanted: mails => {
                const s = form.startAt, e = form.endAt
                root.calendarAction("availability", JSON.stringify({ people: mails.map(m => [m, m]), start: root.isoLocal(s), end: root.isoLocal(e) }))
            }
            onSubmit: f => {
                const out = {
                    subject: f.subject || "", start: root.isoLocal(f.start), end: root.isoLocal(f.end), allDay: !!f.allDay,
                    attendees: f.attendees || [], location: f.location || "", bodyHtml: f.bodyHtml || "", online: !!f.online,
                    channel: f.channel && f.channel.channelId ? f.channel : null, showAs: f.showAs || "Busy",
                    editingId: f.editingId || "", sendPersonalInvites: !!f.sendPersonalInvites, timeZone: root.mtTimeZone,
                    templateId: f.templateId || "", guests: f.guests || [], bodyChanged: !!f.bodyChanged,
                    recurrenceChanged: !!f.recurrenceChanged, targetAudience: f.targetAudience || 0, scope: f.scope || "",
                    outlook: f.outlook || {}
                }
                if (f.recurrence) {
                    const r = f.recurrence, pattern = { patternType: r.patternType }
                    for (const k of ["daily", "weekly", "monthly", "yearly"]) if (r[k]) pattern[k] = r[k]
                    const range = { startDate: root.isoLocal(root.midnight(r.range && r.range.startDate ? r.range.startDate : f.start)) }
                    if (r.range && r.range.endDate) range.endDate = root.isoLocal(root.midnight(r.range.endDate))
                    out.recurrence = { pattern: pattern, range: range }
                }
                if (out.editingId) root.calendarAction("update", JSON.stringify({ id: out.editingId, form: out, joinUrl: form.event.join_url || "", eventType: form.event.event_type || "" }))
                else root.calendarAction("schedule", JSON.stringify({ form: out }))
            }
            onCancelMeeting: (note, scope) => {
                const e = root.withTeam(form.event)
                root.calendarAction("cancel", JSON.stringify({ event: e, teamId: e.team_id || "", note: note, scope: scope }))
            }
            onRespond: (response, send, msg, series) => {
                const e = form.event
                const id = series && e.series_master_id ? e.series_master_id : e.id
                root.calendarAction("respond", JSON.stringify({ id: id, event: { id: e.id, ical_uid: e.ical_uid, event_type: e.event_type, start_utc: e.start_utc, series_master_id: e.series_master_id }, series: !!series, response: response, send: send, note: msg }))
                formLayer.visible = false
            }
            onJoin: root.joinMeeting(form.event.join_url, form.event.subject || qsTr("Meeting"))
            onOpenChat: root.openMeetingChat(form.event.join_url, form.event.subject || qsTr("Meeting"))
            onCopyLink: { textCopy.text = form.event.join_url || ""; textCopy.selectAll(); textCopy.copy() }
        }
    }
    /// A command of the event page (Outlook's event form, MeetingForm's
    /// command bar and fields) for its event.
    function formAct(a) {
        const e = form.event
        if (!a || !e || !e.id) return
        if (a === "popout") { popOutForm(); return }
        if (a.startsWith("reminder:")) {
            const m = parseInt(a.slice(9))
            calendarAction("patchEvent", JSON.stringify({ id: e.id, patch: m < 0 ? { isReminderOn: false } : { isReminderOn: true, reminderMinutesBeforeStart: m } }))
        } else if (a.startsWith("cat:")) calendarAction("patchEvent", JSON.stringify({ id: e.id, patch: { categories: form.eventCategories } }))
        else if (a === "private") calendarAction("patchEvent", JSON.stringify({ id: e.id, patch: { sensitivity: form.sensitivity } }))
        else if (a.startsWith("patch:")) calendarAction("patchEvent", JSON.stringify({ id: e.id, patch: JSON.parse(a.slice(6)) }))
        else if (a.startsWith("csv:")) calendarAction("saveCsv", JSON.stringify({ name: (e.subject || "Tracking") + ".csv", rows: JSON.parse(a.slice(4)) }))
        else if (a === "delete") { formLayer.visible = false; tileAct(e, "delete") }
        else if (a === "apps") openOwaItem(e, "")
        else tileAct(e, a)
    }
    /// The event page in a window of its own (Outlook's form's Open in new
    /// window): the form moves into the window and back when it closes.
    function popOutForm() {
        const w = formWindow.createObject(null, { title: (form.event.subject || qsTr("(No title)")) + " | " + qsTr("Calendar") })
        form.parent = w.contentItem
        form.poppedOut = true
        formLayer.visible = false
        w.show()
        popoutForTest = w
    }
    Component {
        id: formWindow
        Window {
            id: fw
            width: root.Window.window ? root.Window.window.width : 1280
            height: root.Window.window ? root.Window.window.height : 680
            color: root.calOff
            onClosing: {
                form.parent = formLayer
                form.poppedOut = false
                Qt.callLater(() => fw.destroy())
            }
            Connections { target: form; function onClosed() { if (form.poppedOut) fw.close() } }
        }
    }
    // Make sure the form never covers a calendar it didn't start from.
    property alias formOpen: formLayer.visible
}
