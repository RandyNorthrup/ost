import QtQuick
import QtQuick.Controls.Basic

// Teams' own scheduling form ("calv2": New meeting, a channel meeting, the
// organizer's meeting details) and the attendee's event page, measured in
// Teams on the web as ost-test1 (2026-11-17, CSS px at 1x):
// - the header, 61 tall with a divider: a 32 x 32 brand calendar tile at
//   20, the title 18/700 at 60, then the tabs (56 tall, 14 px, the picked
//   one 600 with a 3 px brand line under it): Details, Scheduling
//   Assistant (an existing meeting: Chat, Details, Scheduling Assistant);
//   at the right Save / Send (or Join) 96 x 32 brand, then
//   Close 96 x 32 white with a #D1D1D1 border, both 14/600, 8 apart, 8 in;
// - the command bar, 40 tall with a divider: "Show as: Busy ▾",
//   "Category: None ▾" (greyed with a channel), "…"; an existing meeting
//   you organise starts with "✕ Cancel meeting" (brand 14/600) and "Copy
//   link"; an invitation's: Accept, Tentative, Decline, RSVP with
//   note (a series asks This event / All events in the series first);
// - the fields from x 74, 1037 wide, their 20 px icons in 32 x 32 boxes at
//   32: the title (34 tall), the attendees (50, "+ Optional" at the right),
//   Facilitator (38, white with a #D1D1D1 border, a switch), the dates and
//   times (32: date 134, time 100 with a ▾, →, end date, end time, the
//   duration 14/500, All day), Suggested times (attendees only), the
//   repeat (154, "Does not repeat ▾"), the channel ("Add channel"), the
//   location (50, with "Online meeting" and its switch), the details (a
//   rich editor with Teams' toolbar) and "Add an agenda" (44), 14 apart
//   (the attendees 4 above Facilitator); inputs #F5F5F5, radius 4, a 2 px
//   brand line under the focused one;
// - the Options pane at the right (lobby bypass, record automatically,
//   More options), Tracking for an existing meeting (organizer, then the
//   attendees grouped by their response).
Item {
    id: root
    property string mode: "new"
    property var event: ({})
    property var detail: ({})
    property var teams: []
    property var people: []
    property var me: ({})
    property var freeBusy: ({})
    signal searchPeople(string query)
    signal availabilityWanted(var mails)
    signal submit(var form)
    signal closed()
    signal cancelMeeting(string note)
    signal respond(string response, bool sendResponse, string note, bool series)
    signal join()
    signal openChat()
    signal copyLink()

    // ── the form's state ────────────────────────────────────────────
    property string editingId: ""
    property var required: []          // [{address, name}]
    property var optional: []
    property bool showOptional: false
    property date startAt: new Date()
    property date endAt: new Date()
    property bool allDay: false
    property var recurrence: null      // {unit, interval, days, start, end, patternType, …}
    property string location: ""
    property bool online: true
    property var channel: null         // {teamId, teamName, channelId, channelName}
    property bool personalInvites: false
    property bool facilitator: false
    property string showAs: "Busy"
    property string lobbyBypass: "People in my org and guests"
    property string recordAuto: "Off"
    property bool dirty: false
    /// Calendar ▸ New ▸ Virtual appointment (Teams' template, measured
    /// 2026-11-19): "Virtual appointment" heads the form, a notice bar,
    /// the external guests (name and email, both required) under the
    /// title, and the attendees are "within my organization".
    property bool virtualAppointment: false
    property var guests: [{ name: "", email: "" }]
    property bool noticeClosed: false
    property string vaPresenters: "Only organizers and co-organizers"
    property string vaChat: "In-meeting only"
    readonly property bool guestsReady: guests.every(g => g.name.trim().length > 0 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(g.email.trim()))
    property bool loading: false
    property string tab: "Details"
    property bool paneOpen: true
    property var collapsedTeams: ({})

    readonly property bool existing: mode !== "new"
    readonly property bool readOnly: mode === "view"
    readonly property bool hasInvitees: required.length + optional.length > 0 || !!channel
    readonly property bool isSeries: ["occurrence", "exception", "seriesMaster"].indexOf(event.event_type || "") >= 0
    // Which events of your series the page edits, as Outlook's form does
    // (Teams' event page, winpc 2026-11-23): "occurrence" (This event,
    // "You're editing one event in the series."), "following" (This and
    // all following events: the repeat from this event's date, attendees
    // only in the series) or "series" (All events in the series).
    property string scope: ""
    readonly property bool seriesScoped: existing && isSeries && mode === "edit"
    readonly property bool attendeesLocked: seriesScoped && scope === "following"
    /// The repeat can change for the series or this and the following
    /// events, never back to "Does not repeat" (Outlook's series form has
    /// only Repeat every … with an end date).
    readonly property bool repeatEditable: !readOnly && (!seriesScoped || scope !== "occurrence")
    function setScope(s) {
        const unchanged = !recurrenceChanged
        scope = s
        if (!unchanged) return
        const was = loading; loading = true
        const series = detail && detail.recurrence ? fromGraph(detail.recurrence, startAt) : recurrence
        recurrence = scopedRecurrence(series); recurrenceAtLoad = recurrenceKey(recurrence)
        loading = was
    }
    /// This and all following events: the series' repeat, effective from
    /// this event's date.
    function scopedRecurrence(r) {
        return r && scope === "following" ? makeRecurrence(r.unit, r.interval, r.days, dayStart(startAt), r.end) : r
    }
    /// It was sent as a meeting (attendees or a Teams meeting), not saved as
    /// an appointment.
    readonly property bool wasMeeting: existing && (event.is_meeting === true || !!event.join_url || !!event.channel_id
        || (event.attendees || []).some(a => a.kind !== "resource" && (a.address || "").toLowerCase() !== (event.organizer_address || "").toLowerCase()))
    // The primary button, as Teams' event page (Outlook's form, its
    // ComposeSendSaveButton; measured on winpc 2026-11-23) shows it:
    // - a new event: Save, Send once it has attendees;
    // - your event: nothing (a Teams meeting: Join) until something
    //   changes, then Send for a meeting (also once its attendees are
    //   gone) or an appointment given attendees, Save for an appointment.
    readonly property string primaryKind: mode === "view" ? "join"
        : !existing ? (hasInvitees || virtualAppointment ? "send" : "save")
        : dirty ? (wasMeeting || hasInvitees ? "send" : "save")
        : event.join_url ? "join" : ""
    readonly property string primaryLabel: ({ join: qsTr("Join"), send: qsTr("Send"), save: qsTr("Save") })[primaryKind] || ""
    // A virtual appointment sends once it has a title and its guests.
    readonly property bool primaryEnabled: primaryKind === "join" ? !!event.join_url
        : virtualAppointment && !existing ? guestsReady && titleInput.text.trim().length > 0 : !!primaryKind
    readonly property int durationMin: Math.max(0, Math.round((endAt - startAt) / 60000))
    readonly property var showAsLabels: ({ Free: qsTr("Free"), WorkingElsewhere: qsTr("Working elsewhere"), Tentative: qsTr("Tentative"), Busy: qsTr("Busy"), Oof: qsTr("Away") })

    onRequiredChanged: if (!loading) { dirty = true; availabilityWanted(allMails()) }
    onOptionalChanged: if (!loading) { dirty = true; availabilityWanted(allMails()) }
    onDetailChanged: if (existing && detail && detail.body_html !== undefined) {
        loading = true
        setBody(detail.body_html); bodyAtLoad = bodyHtml()
        // A series' repeat (an occurrence shows its series').
        if (detail.recurrence && !dirty) { recurrence = scopedRecurrence(fromGraph(detail.recurrence, startAt)); recurrenceAtLoad = recurrenceKey(recurrence) }
        loading = false
    }
    /// The repeat as the form opened it (an update sends it to the series
    /// only when it changed, as Outlook's Edit series does).
    property string recurrenceAtLoad: ""
    function recurrenceKey(r) { return r ? JSON.stringify([r.unit, r.interval, r.days, fmtDate(r.start), r.end ? fmtDate(r.end) : ""]) : "" }
    readonly property bool recurrenceChanged: existing && recurrenceKey(recurrence) !== recurrenceAtLoad
    /// The attendees, title, times and place as the form opened them.
    property string attendeesAtLoad: ""
    property var atLoad: ({})
    function attendeeKey() {
        const k = l => l.map(p => (p.address || "").toLowerCase()).sort()
        return JSON.stringify([k(required), k(optional)])
    }
    /// Outlook's "Send update" prompt: only the attendees changed (the
    /// title, times, place and repeat as they were), and there were and
    /// still are attendees.
    function asksAudience() {
        return existing && attendeesAtLoad !== JSON.stringify([[], []]) && required.length + optional.length > 0
            && attendeeKey() !== attendeesAtLoad && titleInput.text.trim() === atLoad.subject
            && startAt.getTime() === atLoad.start && endAt.getTime() === atLoad.end && location === atLoad.location && !recurrenceChanged
    }
    /// The details as the form opened them (an update sends the body only
    /// when it changed).
    property string bodyAtLoad: ""

    // Links in the details as Teams' event page draws them (Outlook's
    // editor, measured 2026-11-23): the browser's #0000EE in light, #BA7CFF
    // in dark and in high contrast (whose event page is dark), underlined.
    // Qt's rich text would draw #0000FF, so a style sheet goes ahead of the
    // HTML, and bodyHtml() takes the colour out again so the saved body
    // keeps its links as they came.
    readonly property color bodyLink: theme.pick("#0000EE", "#BA7CFF", "#BA7CFF")
    property string bodyLinkSet: ""
    function setBody(html) {
        bodyLinkSet = bodyLink.toString()
        // (Qt imports only what lies between fragment markers, which would
        // leave the style sheet out; a browser ignores them.)
        editor.text = html ? "<style>a { color: " + bodyLinkSet + "; }</style>" + String(html).replace(/<!--(Start|End)Fragment-->/g, "") : ""
    }
    onBodyLinkChanged: if (bodyLinkSet && editor.length > 0) { const was = loading; loading = true; setBody(bodyHtml()); loading = was }

    function allMails() { return required.concat(optional).map(p => (p.address || "").toLowerCase()).filter(m => m) }
    function fmtTime(d) { return theme.fmtTime(d, "h:mm AP") }
    function fmtDate(d) { return theme.fmtDate(d, "M/d/yyyy") }
    // Teams' scheduling form duration: "1d 2h 30m" (its calendar_meeting_
    // duration_in_* strings), read as "1 day 2 hours 30 minutes".
    function durLabel(min) {
        const d = Math.floor(min / 1440), h = Math.floor(min % 1440 / 60), m = min % 60
        return [d ? qsTr("%1d", "calendar:k1fh6unlv").arg(d) : "", h ? qsTr("%1h", "calendar:k4xp2r11v").arg(h) : "",
                m || !d && !h ? qsTr("%1m", "calendar:kdur9xdkr").arg(m) : ""].filter(t => t).join(" ")
    }
    function durSpoken(min) {
        const d = Math.floor(min / 1440), h = Math.floor(min % 1440 / 60), m = min % 60
        return [d ? qsTr("%n days", "calendar:kaltotpef_mf", d) : "", h ? qsTr("%n hours", "calendar:kbbf4ppcb_mf", h) : "",
                m || !d && !h ? qsTr("%n minutes", "calendar:k7zo3w10z_mf", m) : ""].filter(t => t).join(" ")
    }
    function nextSlot() {
        const s = new Date(); s.setSeconds(0, 0)
        s.setMinutes(s.getMinutes() < 30 ? 30 : 60)
        return s
    }
    function markDirty() { if (!loading) dirty = true }

    // ── opening ─────────────────────────────────────────────────────
    function reset() {
        loading = true
        editingId = ""; required = []; optional = []; showOptional = false
        allDay = false; recurrence = null; location = ""; online = true
        channel = null; personalInvites = false; facilitator = false
        showAs = "Busy"; tab = "Details"; dirty = false
        virtualAppointment = false; guests = [{ name: "", email: "" }]; noticeClosed = false
        titleInput.text = ""; editor.text = ""; peopleInput.text = ""; optionalInput.text = ""
        channelInput.text = ""; locationInput.text = ""
        loading = false
    }
    function openNew(start, attendees, chan) {
        reset()
        loading = true
        mode = "new"; event = ({}); detail = ({})
        const s = start ? new Date(start) : nextSlot()
        startAt = s; endAt = new Date(s.getTime() + 30 * 60000)
        required = (attendees || []).filter(a => a && a.address).map(a => ({ address: a.address, name: a.name || a.address }))
        channel = chan || null
        loading = false
        if (required.length) availabilityWanted(allMails())
        titleInput.forceActiveFocus()
    }
    /// New ▸ Virtual appointment: Teams' template's options (Who can
    /// present: only organizers and co-organizers; no automatic recording;
    /// in-meeting chat).
    function openVirtualAppointment(start) {
        openNew(start, [], null)
        virtualAppointment = true
        recordAuto = "Off"
    }
    function openEvent(ev, asOrganizer, withScope) {
        reset()
        loading = true
        event = ev || ({}); detail = ({})
        mode = asOrganizer ? "edit" : "view"
        scope = !isSeries ? "" : withScope ? withScope : event.event_type === "seriesMaster" ? "series" : "occurrence"
        editingId = ev.id || ""
        titleInput.text = ev.subject || ""
        startAt = new Date(ev.start_utc); endAt = new Date(ev.end_utc)
        allDay = !!ev.is_all_day
        if (allDay) { startAt = dayStart(startAt); endAt = dayStart(new Date(endAt.getTime() - 1)) }
        const atts = (ev.attendees || []).filter(a => a.kind !== "resource" && (a.address || "").toLowerCase() !== (ev.organizer_address || "").toLowerCase())
        required = atts.filter(a => a.kind !== "optional").map(a => ({ address: a.address, name: a.name || a.address, response: a.response }))
        optional = atts.filter(a => a.kind === "optional").map(a => ({ address: a.address, name: a.name || a.address, response: a.response }))
        showOptional = optional.length > 0
        online = !!ev.join_url
        location = (ev.location && !(online && ev.location === "Microsoft Teams Meeting")) ? ev.location : ""
        channel = ev.channel_id ? { teamId: ev.team_id || "", teamName: ev.team_name || "", channelId: ev.channel_id, channelName: ev.channel_name || "" } : null
        recurrence = scopedRecurrence(fromGraph(ev.recurrence, startAt))
        recurrenceAtLoad = recurrenceKey(recurrence)
        attendeesAtLoad = attendeeKey()
        atLoad = { subject: titleInput.text.trim(), start: startAt.getTime(), end: endAt.getTime(), location: location }
        showAs = ({ free: "Free", tentative: "Tentative", busy: "Busy", oof: "Oof", workingElsewhere: "WorkingElsewhere" })[ev.show_as] || "Busy"
        dirty = false
        loading = false
        availabilityWanted(allMails())
    }
    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }

    // ── recurrence ──────────────────────────────────────────────────
    // Graph's day names (daysOfWeek), and the ones shown.
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var dayLabels: [qsTr("Sunday"), qsTr("Monday"), qsTr("Tuesday"), qsTr("Wednesday"), qsTr("Thursday"), qsTr("Friday"), qsTr("Saturday")]
    readonly property var monthLabels: [qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"), qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"), qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")]
    function fromGraph(r, s) {
        if (!r || !r.pattern) return null
        const p = r.pattern, rg = r.range || {}
        const unit = ({ daily: "day", weekly: "week", absoluteMonthly: "month", relativeMonthly: "month", absoluteYearly: "year", relativeYearly: "year" })[p.type] || "week"
        const days = (p.daysOfWeek || []).map(d => dayNames.map(n => n.toLowerCase()).indexOf(d)).filter(i => i >= 0)
        const parse = t => { if (!t || t.startsWith("0001")) return null; const a = t.split("-"); return new Date(+a[0], +a[1] - 1, +a[2]) }
        return makeRecurrence(unit, p.interval || 1, days.length ? days : [s.getDay()], parse(rg.startDate) || dayStart(s), rg.type === "endDate" ? parse(rg.endDate) : null)
    }
    function makeRecurrence(unit, interval, days, start, end) {
        const r = { unit: unit, interval: Math.max(1, interval), days: days.slice().sort(), start: start, end: end }
        if (unit === "day") { r.patternType = 1; r.daily = { interval: r.interval } }
        else if (unit === "week") { r.patternType = 2; r.weekly = { interval: r.interval, daysOfTheWeek: r.days } }
        else if (unit === "month") { r.patternType = 3; r.monthly = { interval: r.interval, dayOfMonth: start.getDate() } }
        else { r.patternType = 5; r.yearly = { interval: r.interval, month: start.getMonth() + 1, dayOfMonth: start.getDate() } }
        r.range = { startDate: start, endDate: end }
        return r
    }
    // Teams' weekday list: "Monday, Tuesday and Thursday".
    function daysText(days) {
        const names = days.slice().sort().map(i => dayLabels[i])
        if (names.length <= 1) return names[0] || dayLabels[0]
        const head = names.slice(0, -1).reduce((a, b) => qsTr("%1, %2", "calendar:knwjgmlv").arg(a).arg(b))
        return qsTr("%1 and %2", "calendar:k4zyer6mh").arg(head).arg(names[names.length - 1])
    }
    // Teams' recurrence summary (its calendar meeting_recurrence_new_
    // summary_pattern_* sentences): every day of the week weekly is daily,
    // Monday to Friday weekly is "every Monday through Friday", a yearly
    // one names no start.
    function summary(r) {
        if (!r) return qsTr("Does not repeat")
        const n = r.interval, s = fmtDate(r.start), e = r.end ? fmtDate(r.end) : ""
        const d = r.days.slice().sort()
        if (r.unit === "day" || r.unit === "week" && n === 1 && d.length === 7)
            return e ? qsTr("Occurs every %n days starting %1 until %2", "calendar:k6iew97jq_mf", n).arg(s).arg(e)
                     : qsTr("Occurs every %n days starting %1", "calendar:k46d649ty_mf", n).arg(s)
        if (r.unit === "week" && n === 1 && d.join() === "1,2,3,4,5")
            return e ? qsTr("Occurs every Monday through Friday until %1").arg(e) : qsTr("Occurs every Monday through Friday")
        if (r.unit === "week")
            return e ? qsTr("Occurs every %n weeks on %1 starting %2 until %3", "calendar:k6ebbtba8_mf", n).arg(daysText(d)).arg(s).arg(e)
                     : qsTr("Occurs every %n weeks on %1 starting %2", "calendar:k5i6xu768_mf", n).arg(daysText(d)).arg(s)
        if (r.unit === "month")
            return e ? qsTr("Occurs every %n months on day %1 starting %2 until %3", "calendar:kcfcx7stk_mf", n).arg(r.start.getDate()).arg(s).arg(e)
                     : qsTr("Occurs every %n months on day %1 starting %2", "calendar:kdvq913fc_mf", n).arg(r.start.getDate()).arg(s)
        return e ? qsTr("Occurs every year on day %1 of %2 until %3").arg(r.start.getDate()).arg(monthLabels[r.start.getMonth()]).arg(e)
                 : qsTr("Occurs every year on day %1 of %2").arg(r.start.getDate()).arg(monthLabels[r.start.getMonth()])
    }

    // ── the form, as submit() sends it ──────────────────────────────
    function bodyHtml() {
        if (editor.getText(0, editor.length).trim().length === 0) return ""
        let html = editor.getFormattedText(0, editor.length)
        const m = /<body[^>]*>([\s\S]*)<\/body>/i.exec(html)
        html = (m ? m[1] : html).replace(/<!--(Start|End)Fragment-->/g, "").trim()
        // The link colour setBody() gave the links (Qt writes it on each
        // link's span).
        const c = (bodyLinkSet || bodyLink.toString()).toLowerCase()
        return html.replace(/(<a [^>]*><span style="(?:[^"]*?[\s;])?)color:(#[0-9a-f]{6});/gi, (all, head, col) => col.toLowerCase() === c ? head : all)
    }
    function form(send, audience) {
        let s = new Date(startAt), e = new Date(endAt)
        if (allDay) { s = dayStart(startAt); e = dayStart(endAt); e.setDate(e.getDate() + 1) }
        return {
            subject: titleInput.text.trim(),
            start: s, end: e, allDay: allDay,
            attendees: required.map(p => ({ address: p.address, name: p.name, type: "Required" }))
                .concat(optional.map(p => ({ address: p.address, name: p.name, type: "Optional" }))),
            location: location,
            bodyHtml: bodyHtml(),
            bodyChanged: bodyHtml() !== bodyAtLoad,
            recurrenceChanged: recurrenceChanged,
            targetAudience: audience || 0,
            scope: seriesScoped ? scope : "",
            online: channel ? true : online,
            channel: channel,
            recurrence: recurrence ? { patternType: recurrence.patternType, daily: recurrence.daily, weekly: recurrence.weekly, monthly: recurrence.monthly, yearly: recurrence.yearly, range: { startDate: recurrence.start, endDate: recurrence.end } } : null,
            showAs: showAs,
            send: send,
            editingId: editingId,
            sendPersonalInvites: personalInvites,
            lobbyBypass: lobbyBypass,
            recordAutomatically: recordAuto === "On",
            templateId: virtualAppointment ? "firstparty_e514e598-fba6-4e1f-b8b3-138dd3bca748" : "",
            guests: virtualAppointment ? guests.map(g => ({ displayName: g.name.trim(), emailAddress: g.email.trim() })) : []
        }
    }
    function primaryAction() {
        if (primaryKind === "join") { if (event.join_url) root.join(); return }
        if (!primaryEnabled) return
        // A new repeat for a series asks first (Outlook's "Edit series");
        // this and all following events are sent as they are.
        if (existing && isSeries && recurrenceChanged && scope !== "following") { editSeriesDialog.open(); return }
        sendNow()
    }
    function sendNow() {
        if (asksAudience()) { audienceDialog.open(); return }
        submit(form(primaryKind !== "save", 0))
    }
    Shortcut { sequence: "Ctrl+S"; enabled: root.visible && !root.readOnly; onActivated: root.primaryAction() }

    // ── people ──────────────────────────────────────────────────────
    function addPerson(p, opt) {
        const mail = (p.address || p.mail || "").trim()
        if (!mail) return
        const all = required.concat(optional)
        if (all.some(x => (x.address || "").toLowerCase() === mail.toLowerCase())) return
        const entry = { address: mail, name: p.name || mail }
        if (opt) optional = optional.concat([entry]); else required = required.concat([entry])
    }
    function suggestionsFor(text) {
        const t = (text || "").trim().toLowerCase()
        if (t.length < 2) return []
        const taken = required.concat(optional).map(p => (p.address || "").toLowerCase())
        return (people || []).filter(p => p.mail && taken.indexOf(p.mail.toLowerCase()) < 0).slice(0, 8)
    }
    function alias(mail) { return "(" + ((mail || "").split("@")[0] || "").toUpperCase() + ")" }
    function availability(mail) { return freeBusy[(mail || "").toLowerCase()] || "" }
    function availabilityText(a) { return ({ Free: qsTr("Free"), Busy: qsTr("Busy"), Tentative: qsTr("Tentative"), Oof: qsTr("Away"), WorkingElsewhere: qsTr("Working elsewhere"), Unknown: qsTr("Unknown") })[a] || "" }
    function availabilityColor(a) { return a === "Free" ? theme.hc("#107C10", "#3FF23F") : a === "Busy" || a === "Oof" ? theme.hc("#C4314B", "#FFFFFF") : a === "Tentative" ? theme.hc("#8764B8", "#FFFFFF") : theme.textSecondary }

    // ── times ───────────────────────────────────────────────────────
    function parseTime(t, base) {
        const m = /^\s*(\d{1,2})(?::(\d{2}))?\s*([ap])?/i.exec(t || "")
        if (!m) return null
        let h = +m[1] % 24, min = +(m[2] || 0)
        if (m[3]) { h = h % 12; if (m[3].toLowerCase() === "p") h += 12 }
        if (min > 59) return null
        const d = new Date(base); d.setHours(h, min, 0, 0)
        return d
    }
    function setStart(d) {
        const len = endAt - startAt
        startAt = d; endAt = new Date(d.getTime() + Math.max(0, len))
        markDirty()
    }
    function setEnd(d) {
        endAt = d < startAt ? new Date(startAt) : d
        markDirty()
    }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // ── header ──────────────────────────────────────────────────────
    Item {
        id: header
        width: parent.width; height: 61
        Rectangle {
            id: hcFill1
            x: 20; y: 14; width: 32; height: 32; radius: 4
            color: theme.brandFill
            FluentIcon { anchors.centerIn: parent; name: "calendar-20"; size: 20; color: theme.onFill(hcFill1, "white") }
        }
        Text {
            id: titleText
            x: 60; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width * 0.35)
            elide: Text.ElideRight
            text: root.mode === "new" ? (root.virtualAppointment ? qsTr("Virtual appointment") : qsTr("New meeting")) : (root.event.subject || qsTr("(No title)"))
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: titleText.x + titleText.width + 4; height: parent.height
            Repeater {
                model: root.existing ? [["Chat", qsTr("Chat")], ["Details", qsTr("Details")], ["Scheduling Assistant", qsTr("Scheduling Assistant")]] : [["Details", qsTr("Details")], ["Scheduling Assistant", qsTr("Scheduling Assistant")]]
                Item {
                    id: tabItem
                    required property var modelData
                    readonly property bool on: root.tab === modelData[0]
                    width: tabLabel.implicitWidth + 24; height: 56; y: 2
                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: tabItem.modelData[1]
                        font.family: theme.font; font.pixelSize: 14; font.weight: tabItem.on ? Font.DemiBold : Font.Normal
                        color: tabItem.on || tabHover.hovered ? theme.text : theme.textSecondary
                    }
                    Rectangle { visible: tabItem.on; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 3; width: tabLabel.implicitWidth; height: 3; radius: 1.5; color: theme.brand }
                    HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (tabItem.modelData[0] === "Chat") root.openChat(); else root.tab = tabItem.modelData[0] } }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData[1]
                    Accessible.selected: on
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            FormButton {
                visible: !!root.primaryKind && (root.primaryKind !== "join" || !!root.event.join_url)
                primary: true; label: root.primaryLabel; enabledState: root.primaryEnabled
                icon: ({ join: "video-20", send: "send-20", save: "save-20" })[root.primaryKind] || ""
                onClicked: root.primaryAction()
            }
            FormButton { label: qsTr("Close"); onClicked: root.closed() }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // ── command bar ─────────────────────────────────────────────────
    Item {
        id: bar
        anchors.top: header.bottom
        width: optionsPane.visible && root.paneOpen ? optionsPane.x : parent.width; height: 41
        Row {
            x: 24; height: 40
            // Organizer of an existing meeting.
            BarButton2 {
                visible: root.mode === "edit"
                icon: "dismiss-20"; label: root.channel ? qsTr("Cancel meeting") : qsTr("Cancel meeting"); strong: true
                onClicked: cancelDialog.open()
            }
            BarButton2 { visible: root.mode === "edit" && !!root.event.join_url; icon: "link-20"; label: qsTr("Copy link"); onClicked: root.copyLink() }
            Rectangle { visible: root.mode === "edit"; width: 1; height: 20; y: 10; color: theme.divider }
            // An invitation.
            Repeater {
                model: root.readOnly ? [
                    { r: "Accept", t: qsTr("Accept"), icon: "checkmark-20", c: theme.hc("#498205", "#3FF23F"), on: root.event.response === "accepted" },
                    { r: "Tentative", t: qsTr("Tentative"), icon: "question-circle-20", c: theme.hc("#881798", "#FFFFFF"), on: root.event.response === "tentativelyAccepted" },
                    { r: "Decline", t: qsTr("Decline"), icon: "dismiss-20", c: theme.hc("#A4262C", "#FFFFFF"), on: root.event.response === "declined" },
                    { r: "Follow", t: qsTr("Follow"), icon: "star-20", c: theme.textStrong, on: root.event.response === "following" }
                ] : []
                BarButton2 {
                    id: rsvpBtn
                    required property var modelData
                    icon: modelData.icon; iconColor: modelData.c; label: modelData.t; checked: modelData.on
                    onClicked: {
                        if (root.isSeries) { seriesMenu.response = modelData.r; seriesMenu.parent = rsvpBtn; seriesMenu.y = rsvpBtn.height; seriesMenu.open() }
                        else root.respond(modelData.r, true, "", false)
                    }
                }
            }
            BarButton2 { visible: root.readOnly; icon: "note-edit-20"; label: qsTr("RSVP with note"); onClicked: rsvpDialog.openFor() }
            Rectangle { visible: root.readOnly; width: 1; height: 20; y: 10; color: theme.divider }
            BarButton2 {
                id: showAsBtn
                label: qsTr("Show as: %1").arg(root.showAsLabels[root.showAs] || qsTr("Busy")); chevron: true
                enabledState: !root.readOnly
                onClicked: showAsMenu.open()
                MenuPopup {
                    id: showAsMenu
                    y: showAsBtn.height
                    items: ["Free", "WorkingElsewhere", "Tentative", "Busy", "Oof"].map(k => ({ label: root.showAsLabels[k], checked: root.showAs === k }))
                    onPicked: i => { root.showAs = ["Free", "WorkingElsewhere", "Tentative", "Busy", "Oof"][i]; root.markDirty() }
                }
            }
            BarButton2 {
                id: categoryBtn
                visible: !root.readOnly
                label: qsTr("Category: %n selected", "calendar:k2kxygcv5_mf", 0); chevron: true
                enabledState: !root.channel
                onClicked: categoryMenu.open()
                MenuPopup { id: categoryMenu; y: categoryBtn.height; items: [{ label: qsTr("None"), checked: true }] }
            }
            BarButton2 { visible: !root.readOnly; icon: "more-horizontal-20"; label: ""; accessible: qsTr("Meeting options"); onClicked: { root.paneOpen = true } }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }
    MenuPopup {
        id: seriesMenu
        property string response: ""
        items: [{ label: qsTr("This event") }, { label: qsTr("All events in the series") }]
        onPicked: i => root.respond(response, true, "", i === 1)
    }

    // ── the fields ──────────────────────────────────────────────────
    Flickable {
        id: scroller
        visible: root.tab === "Details"
        anchors { top: bar.bottom; bottom: parent.bottom; left: parent.left }
        width: optionsPane.visible && root.paneOpen ? optionsPane.x : parent.width
        contentHeight: fields.height + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        readonly property real fieldW: Math.max(320, Math.min(1037, width - 74 - 32))

        Column {
            id: fields
            y: 22
            width: parent.width
            spacing: 14

            // A virtual appointment's notice bar (Teams: 1 px #D1D1D1
            // border, radius 4, info glyph, 12/18 text, Learn more,
            // dismiss).
            Item {
                visible: root.virtualAppointment && !root.noticeClosed
                x: 32; width: scroller.fieldW + 42; height: visible ? noticeText.implicitHeight + 10 : 0
                Rectangle {
                    anchors.fill: parent; radius: 4; color: "transparent"; border.width: 1; border.color: theme.divider
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: theme.text }
                    Text {
                        id: noticeText
                        x: 46; y: 5; width: parent.width - 46 - 44; wrapMode: Text.Wrap; textFormat: Text.StyledText
                        text: qsTr("External guests will receive a tailored invitation for this scheduled online meeting. They will join from a mobile or web browser and experience a virtual lobby before the appointment begins.") + " <a href=\"https://go.microsoft.com/fwlink/?linkid=2209737\">" + qsTr("Learn more") + "</a>"
                        linkColor: theme.brand; onLinkActivated: l => Qt.openUrlExternally(l)
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 18; lineHeightMode: Text.FixedHeight; color: theme.text
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 0; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 30; radius: 4; color: noticeX.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.text }
                        HoverHandler { id: noticeX; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.noticeClosed = true }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Dismiss notice bar")
                    }
                }
            }

            // Your series: which events the page edits (Outlook's info bar
            // on Teams' event page, measured on winpc 2026-11-23: 36 tall,
            // the info glyph 13 in, 14 px #616161 text 41 in).
            Item {
                visible: root.seriesScoped
                x: 32; width: scroller.fieldW + 42; height: visible ? 36 : 0
                Rectangle {
                    anchors.fill: parent; radius: 4; color: theme.inputFilled
                    FluentIcon { x: 13; anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: theme.textSecondary }
                    Row {
                        x: 41; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                        Text {
                            text: root.scope === "following" ? qsTr("You're editing this and all following events in the series.")
                                : root.scope === "series" ? qsTr("You're editing the series.") : qsTr("You're editing one event in the series.")
                            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                        }
                        LinkButton { visible: root.scope === "occurrence"; label: qsTr("Edit series"); onClicked: root.setScope("series") }
                        LinkButton { visible: root.scope === "occurrence"; label: qsTr("Edit this and all following events"); onClicked: root.setScope("following") }
                    }
                }
            }

            // Title
            FieldRow {
                icon: "edit-20"; height: 34
                FieldBox {
                    width: scroller.fieldW; height: 34
                    focused: titleInput.activeFocus
                    TextInput {
                        id: titleInput
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        readOnly: root.readOnly
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        clip: true; selectByMouse: true
                        onTextEdited: root.markDirty()
                        Accessible.name: qsTr("Add title")
                        Text { visible: !titleInput.text; text: qsTr("Add title"); color: theme.textSecondary; font: titleInput.font }
                    }
                }
            }

            // A virtual appointment's external guests: "External guest name *"
            // and "Email *" (316 x 31 each, 9 apart) per guest, then "+ Add
            // additional external guest".
            Column {
                visible: root.virtualAppointment
                width: parent.width; spacing: 8
                Repeater {
                    model: root.virtualAppointment ? root.guests.length : 0
                    FieldRow {
                        id: guestRow
                        required property int index
                        icon: index === 0 ? "clipboard-20" : ""; height: 31
                        Repeater {
                            model: [["name", qsTr("External guest name") + " *"], ["email", qsTr("Email", "calendar:k35rkn32l") + " *"]]
                            FieldBox {
                                id: guestBox
                                required property var modelData
                                required property int index
                                x: index * ((scroller.fieldW - 9.3) / 2 + 9.3); width: (scroller.fieldW - 9.3) / 2; height: 31
                                focused: guestInput.activeFocus
                                TextInput {
                                    id: guestInput
                                    x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                                    text: (root.guests[guestRow.index] || {})[guestBox.modelData[0]] || ""
                                    onTextEdited: {
                                        const g = root.guests.slice()
                                        g[guestRow.index] = Object.assign({}, g[guestRow.index], { [guestBox.modelData[0]]: text })
                                        root.guests = g; root.markDirty()
                                    }
                                    Accessible.name: guestBox.modelData[1]
                                    Text { visible: !guestInput.text; text: guestBox.modelData[1]; color: theme.textSecondary; font: guestInput.font }
                                }
                            }
                        }
                    }
                }
                FieldRow {
                    height: 31
                    Rectangle {
                        x: 3; width: addGuestRow.implicitWidth + 24; height: 31; radius: 4
                        color: addGuestHover.hovered ? theme.hover : "transparent"
                        Row {
                            id: addGuestRow
                            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 18; color: theme.text }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add additional external guest"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        }
                        HoverHandler { id: addGuestHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.guests = root.guests.concat([{ name: "", email: "" }]) }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Add additional external guest")
                    }
                }
            }

            // Attendees (and the organizer line on an invitation)
            Column {
                width: parent.width
                spacing: 4
                FieldRow {
                    icon: "person-add-20"; height: Math.max(50, reqFlow.height + 8)
                    FieldBox {
                        width: scroller.fieldW; height: parent.height
                        focused: peopleInput.activeFocus
                        Flow {
                            id: reqFlow
                            x: 8; y: 4; width: parent.width - (root.readOnly ? 16 : 100)
                            spacing: 4
                            Repeater {
                                model: root.required
                                PersonChip {
                                    required property var modelData
                                    required property int index
                                    name: modelData.name; mail: modelData.address
                                    status: root.availabilityText(root.availability(modelData.address))
                                    statusColor: root.availabilityColor(root.availability(modelData.address))
                                    removable: !root.readOnly && !root.attendeesLocked
                                    onRemove: root.required = root.required.filter((_, j) => j !== index)
                                }
                            }
                            TextInput {
                                id: peopleInput
                                visible: !root.readOnly && !root.attendeesLocked
                                width: Math.max(160, reqFlow.width - 8); height: 42
                                verticalAlignment: TextInput.AlignVCenter
                                leftPadding: 4
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                                clip: true; selectByMouse: true
                                onTextEdited: { if (text.trim().length >= 2) root.searchPeople(text.trim()); suggest.target = peopleInput; suggest.optionalField = false }
                                Keys.onReturnPressed: suggest.pickFirst(peopleInput, false)
                                Keys.onEnterPressed: suggest.pickFirst(peopleInput, false)
                                Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.required.length) { root.required = root.required.slice(0, -1); e.accepted = true } }
                                Accessible.name: qsTr("Add required attendees")
                                Text { visible: !peopleInput.text && root.required.length === 0; anchors.verticalCenter: parent.verticalCenter; x: 4; text: root.virtualAppointment ? qsTr("Add attendees within my organization") : qsTr("Add required attendees"); color: theme.textSecondary; font: peopleInput.font }
                            }
                            Text {
                                visible: root.readOnly
                                height: 42; verticalAlignment: Text.AlignVCenter
                                text: [root.event.organizer].concat(root.required.map(p => p.name)).filter(n => n).join("; ")
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                        }
                        LinkButton {
                            visible: !root.readOnly && !root.showOptional && !root.attendeesLocked
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            label: "+ " + qsTr("Optional", "calendar:k3udpyy3u")
                            onClicked: { root.showOptional = true; optionalInput.forceActiveFocus() }
                        }
                    }
                }
                FieldRow {
                    visible: root.showOptional
                    icon: ""; height: Math.max(50, optFlow.height + 8)
                    FieldBox {
                        width: scroller.fieldW; height: parent.height
                        focused: optionalInput.activeFocus
                        Flow {
                            id: optFlow
                            x: 8; y: 4; width: parent.width - 16
                            spacing: 4
                            Repeater {
                                model: root.optional
                                PersonChip {
                                    required property var modelData
                                    required property int index
                                    name: modelData.name; mail: modelData.address
                                    status: root.availabilityText(root.availability(modelData.address))
                                    statusColor: root.availabilityColor(root.availability(modelData.address))
                                    removable: !root.readOnly && !root.attendeesLocked
                                    onRemove: root.optional = root.optional.filter((_, j) => j !== index)
                                }
                            }
                            TextInput {
                                id: optionalInput
                                visible: !root.readOnly && !root.attendeesLocked
                                width: Math.max(160, optFlow.width - 8); height: 42
                                verticalAlignment: TextInput.AlignVCenter
                                leftPadding: 4
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                                clip: true; selectByMouse: true
                                onTextEdited: { if (text.trim().length >= 2) root.searchPeople(text.trim()); suggest.target = optionalInput; suggest.optionalField = true }
                                Keys.onReturnPressed: suggest.pickFirst(optionalInput, true)
                                Keys.onEnterPressed: suggest.pickFirst(optionalInput, true)
                                Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.optional.length) { root.optional = root.optional.slice(0, -1); e.accepted = true } }
                                Accessible.name: qsTr("Add optional attendees")
                                Text { visible: !optionalInput.text && root.optional.length === 0; anchors.verticalCenter: parent.verticalCenter; x: 4; text: qsTr("Add optional attendees"); color: theme.textSecondary; font: optionalInput.font }
                            }
                        }
                    }
                }
                // This and all following events: the attendees change only
                // in the series (Outlook's form: 14 px #616161, "Open series").
                FieldRow {
                    visible: root.attendeesLocked
                    icon: ""; height: 20
                    Row {
                        x: 8; spacing: 4
                        Text { text: qsTr("You can only change attendees by editing the series."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                        LinkButton { label: qsTr("Open series"); onClicked: root.setScope("series") }
                    }
                }
                // Facilitator (not with a channel, not on an invitation)
                FieldRow {
                    visible: !root.channel && !root.readOnly && !root.existing && !root.virtualAppointment
                    icon: ""; height: 38
                    Rectangle {
                        width: scroller.fieldW; height: 38; radius: 4
                        color: theme.surface; border.color: theme.stroke
                        Rectangle { x: 11; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 4; color: theme.hc("#8764B8", "#FFFFFF")
                            FluentIcon { anchors.centerIn: parent; name: "sparkle-20-filled"; size: 14; color: "white" } }
                        Text { x: 41; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Facilitator"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: theme.text }
                        SwitchBox { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; on: root.facilitator; accessible: qsTr("Facilitator"); onToggled: { root.facilitator = !root.facilitator; root.markDirty() } }
                    }
                }
            }

            // Dates and times
            Column {
                width: parent.width
                spacing: 6
                FieldRow {
                    icon: "clock-20"; height: 32
                    Text {
                        visible: root.readOnly
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.allDay ? theme.fmtDate(root.startAt, "ddd M/d/yyyy") + "  " + qsTr("All day")
                            : theme.fmtDate(root.startAt, "ddd M/d/yyyy") + " " + root.fmtTime(root.startAt) + " - " + root.fmtTime(root.endAt)
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Row {
                        visible: !root.readOnly
                        spacing: 10
                        DatePickerField {
                            id: startDate
                            width: 134; height: 32
                            filled: true; format: "M/d/yyyy"
                            date: root.startAt
                            onPicked: d => { const n = new Date(root.startAt); n.setFullYear(d.getFullYear(), d.getMonth(), d.getDate()); root.setStart(n) }
                            Accessible.name: qsTr("Start date")
                        }
                        TimeBox {
                            id: startTime
                            visible: !root.allDay
                            value: root.startAt
                            accessible: qsTr("Start time")
                            onOpenList: timeList.show(startTime, false)
                            onTyped: t => { const d = root.parseTime(t, root.startAt); if (d) root.setStart(d) }
                        }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-right-20"; size: 20; color: theme.textSecondary }
                        DatePickerField {
                            id: endDate
                            width: 134; height: 32
                            filled: true; format: "M/d/yyyy"
                            date: root.endAt
                            minDate: root.startAt
                            onPicked: d => { const n = new Date(root.endAt); n.setFullYear(d.getFullYear(), d.getMonth(), d.getDate()); root.setEnd(n) }
                            Accessible.name: qsTr("End date")
                        }
                        TimeBox {
                            id: endTime
                            visible: !root.allDay
                            value: root.endAt
                            accessible: qsTr("End time")
                            onOpenList: timeList.show(endTime, true)
                            onTyped: t => { const d = root.parseTime(t, root.endAt); if (d) root.setEnd(d) }
                        }
                        Text {
                            visible: !root.allDay
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.durLabel(root.durationMin)
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: theme.textSecondary
                            Accessible.name: qsTr("Meeting duration %1").arg(root.durSpoken(root.durationMin))
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            SwitchBox { anchors.verticalCenter: parent.verticalCenter; on: root.allDay; outline: true; accessible: qsTr("All day"); onToggled: { root.allDay = !root.allDay; root.markDirty() } }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("All day"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: theme.textSecondary }
                        }
                    }
                }
                // Suggested times (with attendees).
                Row {
                    visible: !root.readOnly && !root.allDay && root.required.length + root.optional.length > 0
                    x: 74; spacing: 8
                    Text { text: qsTr("Suggested:"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Repeater {
                        model: [0, -30, 30]
                        Text {
                            id: sugg
                            required property int modelData
                            readonly property date s: new Date(root.startAt.getTime() + modelData * 60000)
                            readonly property date e: new Date(s.getTime() + Math.max(30, root.durationMin) * 60000)
                            text: root.fmtTime(s) + "-" + root.fmtTime(e)
                            font.family: theme.font; font.pixelSize: 12; color: theme.brandLink
                            font.underline: suggHover.hovered
                            HoverHandler { id: suggHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.startAt = sugg.s; root.endAt = sugg.e; root.markDirty() } }
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                        }
                    }
                }
            }

            // Repeat
            FieldRow {
                icon: "arrow-sync-20"; height: 32
                visible: !root.readOnly || !!root.recurrence
                Rectangle {
                    id: repeatBox
                    width: repeatLabel.implicitWidth + 50; height: 32; radius: 4
                    color: !root.repeatEditable ? "transparent" : repeatHover.hovered ? theme.pick("#EBEBEB", "#1F1F1F", "#000000") : theme.inputFilled
                    border.color: repeatMenu.opened ? theme.brand : "transparent"
                    Text {
                        id: repeatLabel
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: root.summary(root.recurrence)
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(repeatBox, theme.text)
                    }
                    FluentIcon { visible: root.repeatEditable; x: repeatLabel.x + repeatLabel.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.onFill(repeatBox, theme.textSecondary) }
                    HoverHandler { id: repeatHover; enabled: root.repeatEditable; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: root.repeatEditable; onTapped: repeatMenu.open() }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: qsTr("Recurrence")
                    // Your series keeps a repeat: Outlook's series form has
                    // no "Does not repeat" (winpc, 2026-11-23).
                    MenuPopup {
                        id: repeatMenu
                        y: repeatBox.height + 2
                        rowHeight: 34
                        items: [qsTr("Does not repeat"), qsTr("Every weekday (Mon - Fri)"), qsTr("Daily"), qsTr("Weekly"), qsTr("Monthly"), qsTr("Yearly"), qsTr("Custom")]
                            .slice(root.seriesScoped ? 1 : 0).map(l => ({ label: l }))
                        onPicked: i => root.pickRepeat(root.seriesScoped ? i + 1 : i)
                    }
                }
            }

            // Channel
            FieldRow {
                icon: "channel-20"; height: 32
                visible: (!root.readOnly || !!root.channel) && !root.virtualAppointment
                FieldBox {
                    id: channelBox
                    width: scroller.fieldW; height: 32
                    focused: channelInput.activeFocus
                    Row {
                        visible: !!root.channel
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        opacity: root.existing ? 0.55 : 1
                        Avatar { anchors.verticalCenter: parent.verticalCenter; size: 20; square: true; squareRadius: 4; name: root.channel ? root.channel.teamName : ""; photoId: root.channel && root.channel.teamId ? "team:" + root.channel.teamId : "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.channel ? root.channel.teamName : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.textSecondary }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.channel ? root.channel.channelName : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                    TextInput {
                        id: channelInput
                        visible: !root.channel
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        clip: true; selectByMouse: true
                        onTextEdited: channelPicker.show()
                        onActiveFocusChanged: if (activeFocus) channelPicker.show()
                        Keys.onReturnPressed: channelPicker.pickFirst()
                        Keys.onEnterPressed: channelPicker.pickFirst()
                        Accessible.name: qsTr("Add channel")
                        Text { visible: !channelInput.text; text: qsTr("Add channel"); color: theme.textSecondary; font: channelInput.font }
                    }
                    // Clear the channel (not once the meeting is sent).
                    Item {
                        visible: !!root.channel && !root.existing
                        x: parent.width - 296; width: 24; height: parent.height
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textSecondary }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.channel = null; root.markDirty() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Remove channel")
                    }
                    Row {
                        visible: !!root.channel
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        opacity: root.existing ? 0.55 : 1
                        SwitchBox { anchors.verticalCenter: parent.verticalCenter; on: root.personalInvites; outline: true; accessible: qsTr("Send personal invites"); onToggled: if (!root.existing) { root.personalInvites = !root.personalInvites; root.markDirty() } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Send personal invites"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 16; color: theme.textSecondary
                            Accessible.role: Accessible.StaticText
                            Accessible.name: qsTr("Meeting invitations will be added to the personal calendars of all channel members.") }
                    }
                }
            }

            // Location and Online meeting
            FieldRow {
                icon: "location-20"; height: 50
                FieldBox {
                    width: scroller.fieldW; height: 50
                    focused: locationInput.activeFocus
                    Row {
                        x: 8; height: parent.height
                        spacing: 8
                        Rectangle {
                            id: locChip
                            visible: root.location.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: locRow.implicitWidth + (root.readOnly ? 16 : 36); height: 34; radius: 4
                            color: theme.surface
                            Row {
                                id: locRow
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "location-20"; size: 16; color: theme.textStrong }
                                Column {
                                    Text { text: root.location; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                                    Text { text: qsTr("Unknown"); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.text }
                                }
                            }
                            Item {
                                visible: !root.readOnly
                                anchors.right: parent.right; width: 24; height: parent.height
                                FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textSecondary }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { root.location = ""; root.markDirty() } }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Remove %1").arg(root.location)
                            }
                        }
                        TextInput {
                            id: locationInput
                            visible: !root.readOnly
                            anchors.verticalCenter: parent.verticalCenter
                            width: scroller.fieldW - (locChip.visible ? locChip.width + 8 : 0) - 200
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            clip: true; selectByMouse: true
                            Keys.onReturnPressed: root.commitLocation()
                            Keys.onEnterPressed: root.commitLocation()
                            Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.location) { root.location = ""; root.markDirty(); e.accepted = true } }
                            onActiveFocusChanged: if (!activeFocus && text.trim()) root.commitLocation()
                            Accessible.name: qsTr("Add location")
                            Text { visible: !locationInput.text && !root.location; text: qsTr("Add location"); color: theme.textSecondary; font: locationInput.font }
                        }
                        Text {
                            visible: root.readOnly && !root.location
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("No location added")
                            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                        }
                    }
                    Row {
                        visible: !root.channel && !root.readOnly && !root.virtualAppointment
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Online meeting"); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                        SwitchBox { anchors.verticalCenter: parent.verticalCenter; on: root.online; accessible: qsTr("Online meeting"); onToggled: { root.online = !root.online; root.markDirty() } }
                    }
                }
            }

            // Details
            FieldRow {
                icon: "text-description-20"; height: detailsBox.height
                Rectangle {
                    id: detailsBox
                    width: scroller.fieldW
                    height: (root.readOnly ? 0 : 32) + Math.max(83, editor.contentHeight + 24)
                    radius: 4
                    color: theme.inputFilled
                    Row {
                        id: fmtBar
                        visible: !root.readOnly
                        height: 32
                        FmtButton { icon: "fmt-bold"; tip: qsTr("Bold"); onClicked: root.wrapSelection("<b>", "</b>") }
                        FmtButton { icon: "fmt-italic"; tip: qsTr("Italic"); onClicked: root.wrapSelection("<i>", "</i>") }
                        FmtButton { icon: "fmt-underline"; tip: qsTr("Underline"); onClicked: root.wrapSelection("<u>", "</u>") }
                        FmtButton { icon: "fmt-strike"; tip: qsTr("Strikethrough"); onClicked: root.wrapSelection("<s>", "</s>") }
                        FmtSep {}
                        FmtButton { icon: "fmt-highlight"; tip: qsTr("Text highlight color"); onClicked: root.wrapSelection("<span style=\"background-color:#FFF100\">", "</span>") }
                        FmtButton { icon: "fmt-font-color"; tip: qsTr("Font color"); onClicked: root.wrapSelection("<span style=\"color:#C4314B\">", "</span>") }
                        FmtButton { icon: "fmt-font-size"; tip: qsTr("Font size"); onClicked: root.wrapSelection("<span style=\"font-size:18px\">", "</span>") }
                        Item {
                            id: styleBtn
                            width: 100; height: 32
                            Rectangle { anchors.fill: parent; radius: 4; color: styleHover.hovered ? theme.rowHover : "transparent" }
                            Text { x: 11; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Paragraph"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                            FluentIcon { x: 79; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 10; color: theme.textStrong }
                            HoverHandler { id: styleHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: styleMenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Rich style")
                            MenuPopup {
                                id: styleMenu
                                y: styleBtn.height
                                items: [{ label: qsTr("Paragraph") }, { label: qsTr("Heading 1") }, { label: qsTr("Heading 2") }, { label: qsTr("Heading 3") }]
                                onPicked: i => { if (i > 0) root.wrapSelection("<h" + i + ">", "</h" + i + ">") }
                            }
                        }
                        FmtSep {}
                        FmtButton { icon: "fmt-outdent"; tip: qsTr("Decrease indent"); onClicked: root.wrapSelection("", "") }
                        FmtButton { icon: "fmt-indent"; tip: qsTr("Increase indent"); onClicked: root.wrapSelection("<blockquote style=\"margin-left:40px\">", "</blockquote>") }
                        FmtButton { icon: "fmt-bullets"; tip: qsTr("Bulleted list"); onClicked: root.wrapSelection("<ul><li>", "</li></ul>") }
                        FmtButton { icon: "fmt-numbers"; tip: qsTr("Numbered list"); onClicked: root.wrapSelection("<ol><li>", "</li></ol>") }
                        FmtSep {}
                        FmtButton { icon: "fmt-quote"; tip: qsTr("Quote"); onClicked: root.wrapSelection("<blockquote>", "</blockquote>") }
                        FmtButton { icon: "fmt-link"; tip: qsTr("Insert link"); onClicked: root.insertLink() }
                        FmtButton { icon: "fmt-rule"; tip: qsTr("Insert horizontal rule"); onClicked: { editor.insert(editor.cursorPosition, "<hr/>"); root.markDirty() } }
                        FmtButton { icon: "fmt-table"; tip: qsTr("Insert table"); onClicked: { editor.insert(editor.cursorPosition, "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\"><tr><td>&nbsp;</td><td>&nbsp;</td></tr><tr><td>&nbsp;</td><td>&nbsp;</td></tr></table>"); root.markDirty() } }
                        FmtSep {}
                        FmtButton { icon: "fmt-undo"; tip: qsTr("Undo typing"); enabledState: editor.canUndo; onClicked: editor.undo() }
                        FmtButton { icon: "fmt-redo"; tip: qsTr("Repeat typing"); enabledState: editor.canRedo; onClicked: editor.redo() }
                    }
                    TextEdit {
                        id: editor
                        x: 12; y: fmtBar.visible ? 44 : 12
                        width: parent.width - 24
                        textFormat: TextEdit.RichText
                        wrapMode: TextEdit.Wrap
                        readOnly: root.readOnly
                        selectByMouse: true
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                        onTextChanged: root.markDirty()
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        Keys.onPressed: e => {
                            if (e.modifiers & Qt.ControlModifier) {
                                if (e.key === Qt.Key_B) { root.wrapSelection("<b>", "</b>"); e.accepted = true }
                                else if (e.key === Qt.Key_I) { root.wrapSelection("<i>", "</i>"); e.accepted = true }
                                else if (e.key === Qt.Key_U) { root.wrapSelection("<u>", "</u>"); e.accepted = true }
                                else if (e.key === Qt.Key_K) { root.insertLink(); e.accepted = true }
                            }
                        }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Type details for this new meeting")
                        Text { visible: editor.length === 0 && !root.readOnly; text: qsTr("Type details for this new meeting"); color: theme.textSecondary; font: editor.font }
                        HoverHandler { cursorShape: hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor; property string hoveredLink: editor.hoveredLink }
                    }
                }
            }

            // Add an agenda
            FieldRow {
                visible: !root.readOnly
                icon: "clipboard-task-list-20"; height: 44
                Rectangle {
                    id: agendaBox
                    width: scroller.fieldW; height: 44; radius: 4
                    color: agendaHover.hovered ? theme.pick("#EBEBEB", "#1F1F1F", "#000000") : theme.inputFilled
                    Text { x: 13; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add an agenda"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(agendaBox, theme.text) }
                    HoverHandler { id: agendaHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { editor.forceActiveFocus(); if (editor.length === 0) { editor.insert(0, "<b>" + qsTr("Agenda") + "</b><ul><li></li></ul>"); root.markDirty() } } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Add an agenda")
                }
            }
        }
    }

    // ── Scheduling Assistant: everyone's availability for the slot ──
    Item {
        visible: root.tab === "Scheduling Assistant"
        anchors { top: bar.bottom; bottom: parent.bottom; left: parent.left }
        width: scroller.width
        Column {
            x: 32; y: 22
            spacing: 10
            Text {
                text: root.allDay ? theme.fmtDate(root.startAt, "dddd, MMMM d") + " · " + qsTr("All day")
                    : theme.fmtDate(root.startAt, "dddd, MMMM d") + " · " + root.fmtTime(root.startAt) + " - " + root.fmtTime(root.endAt)
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            }
            Repeater {
                model: [{ name: root.me.name || qsTr("You"), address: root.me.mail || "", role: qsTr("Organizer") }]
                    .concat(root.required.map(p => ({ name: p.name, address: p.address, role: qsTr("Required") })))
                    .concat(root.optional.map(p => ({ name: p.name, address: p.address, role: qsTr("Optional") })))
                Row {
                    required property var modelData
                    spacing: 12
                    Avatar { size: 32; name: parent.modelData.name }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { text: parent.parent.modelData.role; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        readonly property string a: root.availability(parent.modelData.address)
                        text: root.availabilityText(a) || qsTr("Unknown")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: root.availabilityColor(a)
                    }
                }
            }
        }
    }

    // ── Options / Tracking pane ─────────────────────────────────────
    Item {
        id: optionsPane
        visible: root.width >= 1000
        x: root.paneOpen ? root.width - 368 : root.width - 56
        anchors { top: header.bottom; bottom: parent.bottom }
        width: root.width - x
        Rectangle { width: 1; height: parent.height; color: theme.dividerSoft }
        Text {
            visible: root.paneOpen
            x: 18; y: root.existing ? 12 : 10
            text: root.existing ? qsTr("Tracking") : qsTr("Options")
            font.family: theme.font; font.pixelSize: root.existing ? 18 : 14; font.weight: Font.DemiBold; color: theme.text
        }
        Rectangle {
            id: hcFill2
            anchors.right: parent.right; anchors.rightMargin: 24; y: 8
            width: 32; height: 24; radius: 4
            color: collapseHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: root.paneOpen ? "panel-right-20" : "panel-right-expand-20"; size: 20; color: theme.onFill(hcFill2, theme.textSecondary) }
            HoverHandler { id: collapseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.paneOpen = !root.paneOpen }
            Accessible.role: Accessible.Button
            Accessible.name: (root.existing ? qsTr("Tracking") : qsTr("Options")) + ", " + (root.paneOpen ? qsTr("Visible", "calendar:k6nd3g73t") : qsTr("Hidden", "calendar:k3fucthaz"))
        }
        // Options
        Column {
            visible: root.paneOpen && !root.existing
            x: 18; y: 59
            spacing: 4
            // A virtual appointment's options (its template's): Who can
            // present, Record and transcribe automatically, Meeting chat.
            Text { visible: root.virtualAppointment; text: qsTr("Who can present"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            PaneDropdown {
                visible: root.virtualAppointment
                value: root.vaPresenters
                options: [["Only organizers and co-organizers", qsTr("Only organizers and co-organizers")], ["Specific people", qsTr("Specific people")], ["People in my org and guests", qsTr("People in my org and guests")], ["Everyone", qsTr("Everyone")]]
                accessible: qsTr("Who can present")
                onChosen: v => root.vaPresenters = v
            }
            Item { visible: root.virtualAppointment; width: 1; height: 12 }
            Row {
                visible: !root.virtualAppointment
                spacing: 2
                Text { text: qsTr("Who can bypass the lobby?"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 16; color: theme.textSecondary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("Who can bypass the lobby?", "calendar:kcogvhd7i") + ". " + qsTr("More information") }
            }
            PaneDropdown {
                id: lobbyDrop
                visible: !root.virtualAppointment
                value: root.lobbyBypass
                options: [["Only organizers and co-organizers", qsTr("Only organizers and co-organizers")], ["People who were invited", qsTr("People who were invited")], ["People in my org", qsTr("People in my org")],
                    ["People in my org and guests", qsTr("People in my org and guests")], ["Everyone", qsTr("Everyone")]]
                accessible: qsTr("Who can bypass the lobby?")
                onChosen: v => root.lobbyBypass = v
            }
            Item { visible: !root.virtualAppointment; width: 1; height: 12 }
            Text { text: qsTr("Record and transcribe automatically"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            PaneDropdown {
                value: root.recordAuto
                options: [["Off", qsTr("Off")], ["On", qsTr("On", "calling:kar4y63pl")]]
                accessible: qsTr("Record and transcribe automatically")
                onChosen: v => root.recordAuto = v
            }
            Item { visible: root.virtualAppointment; width: 1; height: 12 }
            Text { visible: root.virtualAppointment; text: qsTr("Meeting chat"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
            PaneDropdown {
                visible: root.virtualAppointment
                value: root.vaChat
                options: [["On", qsTr("On", "calling:kar4y63pl")], ["In-meeting only", qsTr("In meeting only")], ["Off", qsTr("Off")]]
                accessible: qsTr("Meeting chat")
                onChosen: v => root.vaChat = v
            }
            Item { width: 1; height: 21 }
            LinkButton { label: qsTr("More options"); bold: true }
        }
        // Tracking
        Flickable {
            visible: root.paneOpen && root.existing
            x: 12; y: 56; width: parent.width - 24; height: parent.height - 56
            contentHeight: tracking.height
            clip: true
            Column {
                id: tracking
                width: parent.width
                spacing: 8
                Text { text: qsTr("Organizer"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                TrackRow { name: root.event.organizer || (root.mode === "edit" ? root.me.name : "") || ""; sub: root.mode === "edit" ? qsTr("Organizer") : "" }
                Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                Text {
                    visible: root.trackPeople.length > 0
                    text: qsTr("Attendees"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                }
                Repeater {
                    model: [
                        { key: "accepted", label: qsTr("Accepted") },
                        { key: "tentativelyAccepted", label: qsTr("Tentative") },
                        { key: "declined", label: qsTr("Declined") },
                        { key: "following", label: qsTr("Following") },
                        { key: "none", label: qsTr("No response", "calendar:k65z5m1zz") }
                    ]
                    Column {
                        id: group
                        required property var modelData
                        readonly property var members: root.trackPeople.filter(p => root.responseKey(p.response) === modelData.key)
                        property bool open: true
                        visible: members.length > 0
                        width: parent.width
                        spacing: 4
                        Row {
                            spacing: 6
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: group.open ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.textSecondary }
                            Text { text: qsTr("%1: %2").arg(group.modelData.label).arg(group.members.length); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                            TapHandler { onTapped: group.open = !group.open }
                        }
                        Repeater {
                            model: group.open ? group.members : []
                            TrackRow { required property var modelData; name: modelData.name || modelData.address; sub: modelData.kind === "optional" ? qsTr("Optional") : qsTr("Required") }
                        }
                    }
                }
            }
        }
    }
    readonly property var trackPeople: ((detail && detail.attendees) || event.attendees || [])
        .filter(a => a.kind !== "resource" && (a.address || "").toLowerCase() !== (event.organizer_address || "").toLowerCase())
    function responseKey(r) { return ["accepted", "tentativelyAccepted", "declined", "following"].indexOf(r) >= 0 ? r : "none" }

    // ── behaviour ───────────────────────────────────────────────────
    function commitLocation() {
        const t = locationInput.text.trim()
        if (!t) return
        location = t; locationInput.text = ""; markDirty()
    }
    function escapeHtml(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function wrapSelection(open, close) {
        const s = editor.selectionStart, e = editor.selectionEnd
        if (s === e) { if (open.indexOf("<li>") >= 0) { editor.insert(s, open + close); markDirty() } return }
        const t = escapeHtml(editor.getText(s, e))
        editor.remove(s, e)
        editor.insert(s, open + t + close)
        markDirty()
    }
    function insertLink() {
        const s = editor.selectionStart, e = editor.selectionEnd
        const t = editor.getText(s, e).trim()
        if (!/^https?:\/\//.test(t)) return
        editor.remove(s, e)
        bodyLinkSet = bodyLink.toString()
        editor.insert(s, "<a href=\"" + escapeHtml(t) + "\" style=\"color: " + bodyLinkSet + "\">" + escapeHtml(t) + "</a>")
        markDirty()
    }
    function pickRepeat(i) {
        if (i === 0) { if (!seriesScoped) { recurrence = null; markDirty() } return }
        const s = dayStart(startAt)
        const preset = [null,
            { unit: "week", days: [1, 2, 3, 4, 5] },
            { unit: "day", days: [s.getDay()] },
            { unit: "week", days: [s.getDay()] },
            { unit: "month", days: [s.getDay()] },
            { unit: "year", days: [s.getDay()] },
            recurrence ? { unit: recurrence.unit, days: recurrence.days } : { unit: "week", days: [s.getDay()] }][i]
        recDialog.openWith(preset.unit, recurrence && i === 6 ? recurrence.interval : 1, preset.days, recurrence && i === 6 ? recurrence.start : s, recurrence && i === 6 ? recurrence.end : null)
    }

    // ── popups ──────────────────────────────────────────────────────
    // People suggestions (444 wide, 56 tall rows).
    Popup {
        id: suggest
        property Item target: null
        property bool optionalField: false
        readonly property var list: target ? root.suggestionsFor(target.text) : []
        function pickFirst(field, opt) {
            const l = root.suggestionsFor(field.text)
            if (l.length) root.addPerson({ address: l[0].mail, name: l[0].name }, opt)
            else if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(field.text.trim())) root.addPerson({ address: field.text.trim(), name: field.text.trim() }, opt)
            else return
            field.text = ""; close()
        }
        visible: !!target && target.activeFocus && list.length > 0
        parent: root
        x: target ? target.mapToItem(root, 0, 0).x - 8 : 0
        y: target ? target.mapToItem(root, 0, target.height).y + 4 : 0
        width: 444; padding: 0
        height: list.length * 56 + 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: Column {
            topPadding: 4
            Repeater {
                model: suggest.list
                Rectangle {
                    id: sugRow
                    required property var modelData
                    required property int index
                    width: 444; height: 56
                    color: sugHover.hovered || index === 0 ? theme.menuHover : "transparent"
                    Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: sugRow.modelData.name; photoId: sugRow.modelData.id || "" }
                    Column {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        Text { text: sugRow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(sugRow, theme.text) }
                        Text { text: root.alias(sugRow.modelData.mail); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(sugRow, theme.textSecondary) }
                    }
                    HoverHandler { id: sugHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.addPerson({ address: sugRow.modelData.mail, name: sugRow.modelData.name }, suggest.optionalField)
                            if (suggest.target) { suggest.target.text = ""; suggest.target.forceActiveFocus() }
                        }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: sugRow.modelData.name
                }
            }
        }
    }

    // The channel picker: teams with their matching channels (444 wide).
    Popup {
        id: channelPicker
        readonly property string q: channelInput.text.trim().toLowerCase()
        readonly property var groups: (root.teams || []).map(t => {
            const teamHit = !q || (t.name || "").toLowerCase().indexOf(q) >= 0
            const chans = (t.channels || []).filter(c => teamHit || (c.name || "").toLowerCase().indexOf(q) >= 0)
            return { team: t, channels: chans }
        }).filter(g => g.channels.length > 0)
        readonly property var rows: {
            const out = []
            for (const g of groups) {
                out.push({ header: true, team: g.team })
                if (!root.collapsedTeams[g.team.id]) for (const c of g.channels) out.push({ header: false, team: g.team, channel: c })
            }
            return out
        }
        function show() { if (!root.channel && !root.existing) open() }
        function pickFirst() { const r = rows.find(x => !x.header); if (r) pick(r.team, r.channel) }
        function pick(t, c) {
            root.channel = { teamId: t.id || "", teamName: t.name || "", channelId: c.id || "", channelName: c.name || "" }
            channelInput.text = ""; root.markDirty(); close()
        }
        parent: root
        x: channelBox.mapToItem(root, 0, 0).x
        y: channelBox.mapToItem(root, 0, channelBox.height).y + 2
        width: 444; padding: 0
        height: Math.min(320, rows.length * 28 + (rows.filter(r => r.header).length * 4) + 8)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: ListView {
            clip: true
            topMargin: 4
            model: channelPicker.rows
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: chRow
                required property var modelData
                width: 444; height: modelData.header ? 32 : 28
                color: chHover.hovered ? theme.menuHover : chRow.modelData.header ? theme.pick("#F5F5F5", "#1F1F1F", "#000000") : "transparent"
                Row {
                    visible: chRow.modelData.header
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: root.collapsedTeams[chRow.modelData.team.id] ? "chevron-right-12" : "chevron-down-12"; size: 12; color: theme.textStrong }
                    Avatar { anchors.verticalCenter: parent.verticalCenter; size: 20; square: true; squareRadius: 4; name: chRow.modelData.team.name || ""; photoId: "team:" + (chRow.modelData.team.id || "") }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: chRow.modelData.team.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(chRow, theme.text) }
                }
                Text {
                    visible: !chRow.modelData.header
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    text: chRow.modelData.channel ? chRow.modelData.channel.name : ""
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(chRow, theme.text)
                }
                HoverHandler { id: chHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (chRow.modelData.header) {
                            const c = Object.assign({}, root.collapsedTeams)
                            c[chRow.modelData.team.id] = !c[chRow.modelData.team.id]
                            root.collapsedTeams = c
                        } else channelPicker.pick(chRow.modelData.team, chRow.modelData.channel)
                    }
                }
                Accessible.role: chRow.modelData.header ? Accessible.Button : Accessible.ListItem
                Accessible.name: chRow.modelData.header ? (chRow.modelData.team.name || "") : (chRow.modelData.channel ? chRow.modelData.channel.name : "")
            }
        }
    }

    // The time lists: 30-minute steps; the end's starts at the start
    // time and carries the duration.
    Popup {
        id: timeList
        property Item box: null
        property bool isEnd: false
        function show(b, end) {
            box = b; isEnd = end
            const p = b.mapToItem(root, 0, b.height)
            x = p.x; y = p.y + 2
            open()
            list.positionViewAtIndex(Math.max(0, current), ListView.Center)
        }
        readonly property var items: {
            const out = []
            if (isEnd) {
                for (let i = 0; i < 48; i++) {
                    const d = new Date(root.startAt.getTime() + i * 30 * 60000)
                    out.push({ d: d, label: root.fmtTime(d) + (i ? " (" + root.durLabel(i * 30) + ")" : "") })
                }
            } else {
                const base = root.dayStart(root.startAt)
                for (let i = 0; i < 48; i++) {
                    const d = new Date(base.getTime() + i * 30 * 60000)
                    out.push({ d: d, label: root.fmtTime(d) })
                }
            }
            return out
        }
        readonly property int current: {
            const v = isEnd ? root.endAt : root.startAt
            for (let i = 0; i < items.length; i++) if (items[i].d.getTime() === v.getTime()) return i
            return -1
        }
        parent: root
        width: isEnd ? 166 : 110; height: 6 * 32 + 8; padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4 }
        contentItem: ListView {
            id: list
            clip: true
            topMargin: 4; bottomMargin: 4
            model: timeList.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: tRow
                required property var modelData
                required property int index
                width: timeList.width; height: 32
                color: index === timeList.current ? theme.pick("#EBEBEB", "#383838", "#000000") : tHover.hovered ? theme.menuHover : "transparent"
                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: tRow.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(tRow, theme.text) }
                HoverHandler { id: tHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { if (timeList.isEnd) root.setEnd(tRow.modelData.d); else root.setStart(tRow.modelData.d); timeList.close() } }
                Accessible.role: Accessible.ListItem
                Accessible.name: tRow.modelData.label
            }
        }
    }

    // Set recurrence (600 wide).
    Popup {
        id: recDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; padding: 32; topPadding: 26
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        property string unit: "week"
        property int interval: 1
        property var days: []
        property date start: new Date()
        property var end: null
        function openWith(u, n, d, s, e) { unit = u; interval = n; days = d.slice(); start = s; end = e; open() }
        readonly property var draft: root.makeRecurrence(unit, interval, days.length ? days : [start.getDay()], start, end)
        contentItem: Column {
            spacing: 18
            Text { text: qsTr("Set recurrence"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold; color: theme.text }
            Row {
                spacing: 12
                Text { width: 100; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Start"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                DatePickerField { width: 102; height: 32; filled: true; format: "M/d/yyyy"; iconSize: 0; date: recDialog.start; onPicked: d => recDialog.start = d; Accessible.name: qsTr("Start") }
            }
            Row {
                spacing: 12
                Text { width: 100; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Repeat every"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    width: 46; height: 32; radius: 4; color: theme.inputFilled
                    TextInput {
                        anchors.fill: parent; horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                        text: String(recDialog.interval)
                        validator: IntValidator { bottom: 1; top: 99 }
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        onTextEdited: if (+text > 0) recDialog.interval = +text
                        Accessible.name: qsTr("Repeat every")
                    }
                }
                Rectangle {
                    id: unitBox
                    width: 92; height: 32; radius: 4; color: theme.inputFilled
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: ({ day: qsTr("Day"), week: qsTr("Week"), month: qsTr("Month"), year: qsTr("Year") })[recDialog.unit]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    FluentIcon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 16; color: theme.textSecondary }
                    TapHandler { onTapped: unitMenu.open() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: qsTr("Repeat unit")
                    MenuPopup {
                        id: unitMenu
                        y: unitBox.height + 2
                        items: [qsTr("Day"), qsTr("Week"), qsTr("Month"), qsTr("Year")].map(l => ({ label: l }))
                        onPicked: i => recDialog.unit = ["day", "week", "month", "year"][i]
                    }
                }
            }
            Row {
                visible: recDialog.unit === "week"
                x: 112; spacing: 5
                Repeater {
                    model: [0, 1, 2, 3, 4, 5, 6].map(i => Qt.locale().dayName(i, Locale.NarrowFormat))
                    Rectangle {
                        id: dayDot
                        required property string modelData
                        required property int index
                        readonly property bool on: recDialog.days.indexOf(index) >= 0
                        width: 32; height: 32; radius: 16
                        color: on ? theme.brandFill : dotHover.hovered ? theme.rowHover : "transparent"
                        Text { anchors.centerIn: parent; text: dayDot.modelData; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(dayDot, dayDot.on ? "white" : theme.textSecondary) }
                        HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const d = recDialog.days.slice(), i = d.indexOf(dayDot.index)
                                if (i >= 0) { if (d.length > 1) d.splice(i, 1) } else d.push(dayDot.index)
                                recDialog.days = d.sort()
                            }
                        }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: root.dayLabels[index]
                        Accessible.checked: on
                    }
                }
            }
            Row {
                spacing: 12
                Text { width: 100; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: qsTr("End"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle {
                    id: endBox
                    width: endText.implicitWidth + 28; height: 32; radius: 4; color: theme.inputFilled
                    Text { id: endText; anchors.centerIn: parent; text: recDialog.end ? root.fmtDate(recDialog.end) : qsTr("Select date"); font.family: theme.font; font.pixelSize: 14; color: recDialog.end ? theme.text : theme.textSecondary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: endPicker.openPicker() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("End date")
                    DatePickerField {
                        id: endPicker
                        bare: true; width: endBox.width; height: endBox.height
                        date: recDialog.end || recDialog.start
                        minDate: recDialog.start
                        onPicked: d => recDialog.end = d
                    }
                }
                LinkButton { visible: !!recDialog.end; anchors.verticalCenter: parent.verticalCenter; label: qsTr("Remove"); bold: true; onClicked: recDialog.end = null }
            }
            Text { x: 112; text: root.summary(recDialog.draft); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Row {
                anchors.right: parent.right
                spacing: 8
                FormButton { label: qsTr("Cancel"); onClicked: recDialog.close() }
                FormButton { primary: true; label: qsTr("Save"); onClicked: { root.recurrence = recDialog.draft; root.markDirty(); recDialog.close() } }
            }
        }
    }

    // Cancel meeting? (400 wide)
    Popup {
        id: cancelDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 400; padding: 32; topPadding: 26
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        onAboutToShow: cancelNote.text = ""
        contentItem: Column {
            spacing: 16
            Item {
                width: 336; height: 28
                Text { text: qsTr("Cancel meeting?"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold; color: theme.text }
                Item {
                    anchors.right: parent.right; width: 24; height: 28
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: cancelDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close")
                }
            }
            NoteBox { id: cancelNote; width: 336; height: 96; placeholder: qsTr("Add a cancellation note (optional)") }
            Row {
                anchors.right: parent.right
                FormButton { primary: true; wide: true; label: qsTr("Cancel meeting"); onClicked: { root.cancelMeeting(cancelNote.text.trim()); cancelDialog.close() } }
            }
        }
    }

    // Send with only the attendees changed: Outlook's "Send update" prompt
    // (Teams' event page, measured on winpc 2026-11-23: 600 wide, "Only
    // added/removed attendees" primary, "All attendees"; Escape sends
    // nothing).
    Popup {
        id: audienceDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        contentItem: Column {
            spacing: 8
            Text { width: 552; text: qsTr("Send update"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text {
                width: 552; wrapMode: Text.Wrap
                text: qsTr("You've made changes to the attendee list. Do you want to send updates to only added/removed attendees or all of them?")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                FormButton { primary: true; label: qsTr("Only added/removed attendees"); onClicked: { audienceDialog.close(); root.submit(root.form(true, 2)) } }
                FormButton { label: qsTr("All attendees"); onClicked: { audienceDialog.close(); root.submit(root.form(true, 1)) } }
            }
        }
    }

    // Send with a new repeat for a series: Outlook's "Edit series" (Save,
    // Cancel; measured on winpc 2026-11-23).
    Popup {
        id: editSeriesDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 340; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        contentItem: Column {
            spacing: 8
            Text { width: 292; text: qsTr("Edit series"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text {
                width: 292; wrapMode: Text.Wrap
                text: qsTr("If you changed specific events in the series, your changes will be canceled and those events will match the series again.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                FormButton { primary: true; label: qsTr("Save"); onClicked: { editSeriesDialog.close(); root.sendNow() } }
                FormButton { label: qsTr("Cancel"); onClicked: editSeriesDialog.close() }
            }
        }
    }

    // RSVP to <title> with note (600 wide).
    Popup {
        id: rsvpDialog
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        property string response: ""
        // Only for an invitation (an event with an id you don't organise).
        function openFor() { if (!root.event || !root.event.id || root.event.is_organizer) return; response = ""; rsvpNote.text = ""; open() }
        contentItem: Column {
            spacing: 16
            Text {
                width: 552; elide: Text.ElideRight
                text: qsTr("RSVP to %1 with note").arg(root.event.subject || qsTr("(No title)"))
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            }
            NoteBox { id: rsvpNote; width: 552; height: 100; placeholder: qsTr("Add a note"); outlined: true }
            Rectangle {
                id: respBox
                width: 150; height: 34; radius: 4
                color: theme.surface; border.color: theme.stroke
                Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 1; color: theme.textSecondary }
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: rsvpDialog.response ? ({ Accept: qsTr("Accept"), Decline: qsTr("Decline"), Tentative: qsTr("Tentative"), Follow: qsTr("Follow") })[rsvpDialog.response] : qsTr("Select an option"); font.family: theme.font; font.pixelSize: 14; color: rsvpDialog.response ? theme.text : theme.textSecondary }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: respMenu.open() }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Response")
                MenuPopup {
                    id: respMenu
                    y: respBox.height + 2
                    width: 152
                    items: [["Accept", qsTr("Accept")], ["Decline", qsTr("Decline")], ["Tentative", qsTr("Tentative")], ["Follow", qsTr("Follow")]].map(l => ({ label: l[1], checked: rsvpDialog.response === l[0] }))
                    onPicked: i => rsvpDialog.response = ["Accept", "Decline", "Tentative", "Follow"][i]
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                FormButton { primary: true; label: qsTr("Confirm"); enabledState: rsvpDialog.response.length > 0; onClicked: { root.respond(rsvpDialog.response, true, rsvpNote.text.trim(), false); rsvpDialog.close() } }
                FormButton { label: qsTr("Cancel"); onClicked: rsvpDialog.close() }
            }
        }
    }

    // ── harness ─────────────────────────────────────────────────────
    function typeTitleForTest(t) { titleInput.text = t; markDirty() }
    function addAttendeeForTest(mail, name) { addPerson({ address: mail, name: name || mail }, false) }
    function setTimesForTest(s, e) { startAt = new Date(s); endAt = new Date(e); markDirty() }
    /// A suggested meeting's title and details (an agent's Edit).
    function prefill(subject, body) { titleInput.text = subject || ""; setBody(body || ""); markDirty() }
    function pickRepeatForTest(i) { pickRepeat(i) }
    function saveRecurrenceForTest(end) { if (end) recDialog.end = new Date(end); root.recurrence = recDialog.draft; markDirty(); recDialog.close() }
    /// A weekly repeat on these weekdays (0 = Sunday), keeping its start and end.
    function setWeeklyDaysForTest(days) {
        const r = recurrence
        recurrence = makeRecurrence("week", r ? r.interval : 1, days, r ? r.start : dayStart(startAt), r ? r.end : null)
        markDirty()
    }
    function setScopeForTest(s) { setScope(s) }
    /// The repeat menu's items as it would show them.
    function repeatItemsForTest() { return repeatMenu.items.map(x => x.label) }
    readonly property bool editSeriesOpen: editSeriesDialog.opened
    function confirmEditSeriesForTest() { if (editSeriesDialog.opened) { editSeriesDialog.close(); sendNow() } }
    readonly property bool audienceOpen: audienceDialog.opened
    function chooseAudienceForTest(n) { if (audienceDialog.opened) { audienceDialog.close(); submit(form(true, n === 1 ? 1 : 2)) } }
    function pickChannelForTest(teamName, channelName) {
        const t = (teams || []).find(x => x.name === teamName)
        const c = t ? (t.channels || []).find(x => x.name === channelName) : null
        if (!t || !c) return false
        channelPicker.pick(t, c)
        return true
    }
    function setLocationForTest(t) { locationInput.text = t; commitLocation() }
    function typeBodyForTest(t) { setBody(t); markDirty() }
    function submitForTest() { primaryAction() }
    function openCancelForTest() { cancelDialog.open() }
    function confirmCancelForTest(note) { cancelMeeting(note || ""); cancelDialog.close() }
    function openRsvpNoteForTest() { rsvpDialog.openFor() }
    readonly property bool rsvpNoteOpen: rsvpDialog.visible
    function closeRsvpNoteForTest() { rsvpDialog.close() }
    function confirmRsvpNoteForTest(response, note) { rsvpNote.text = note || ""; rsvpDialog.response = response; respond(response, true, note || "", false); rsvpDialog.close() }

    // ── parts ───────────────────────────────────────────────────────
    // A field row: its 20 px icon in a 32 x 32 box at 32, the field at 74.
    component FieldRow: Item {
        id: fr
        default property alias content: slot.data
        property string icon
        width: parent ? parent.width : 0
        FluentIcon { visible: !!fr.icon; x: 38; y: Math.min(fr.height, 32) / 2 - 10; name: fr.icon; size: 20; color: theme.textSecondary }
        Item { id: slot; x: 74; width: fr.width - 74; height: fr.height }
    }
    // Teams' filled input: #F5F5F5, radius 4, a 2 px brand line when focused.
    component FieldBox: Rectangle {
        id: fb
        property bool focused: false
        radius: 4
        color: theme.inputFilled
        Rectangle { visible: fb.focused; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
    }
    component FormButton: Rectangle {
        id: btn
        property string label
        property string icon: ""
        property bool primary: false
        property bool wide: false
        property bool enabledState: true
        signal clicked()
        width: Math.max(96, btnRow.implicitWidth + 24); height: 32; radius: 4
        color: !enabledState ? theme.bgDisabled
            : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill)
            : (btnHover.hovered ? theme.rowHover : theme.surface)
        border.color: primary || !enabledState ? "transparent" : theme.stroke
        Row {
            id: btnRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!btn.icon; anchors.verticalCenter: parent.verticalCenter; name: btn.icon; size: 20; color: theme.onFill(btn, btn.primary ? "white" : theme.textStrong) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.onFill(btn, !btn.enabledState ? theme.disabled : btn.primary ? "white" : theme.text)
            }
        }
        HoverHandler { id: btnHover; enabled: btn.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabledState; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: btn.label
    }
    // A command bar button: icon, label (14), an optional chevron.
    component BarButton2: Rectangle {
        id: bb
        property string icon: ""
        property color iconColor: theme.textSecondary
        property string label
        property string accessible: ""
        property bool chevron: false
        property bool strong: false
        property bool checked: false
        property bool enabledState: true
        signal clicked()
        width: bbRow.implicitWidth + 18; height: 40; radius: 4
        color: bbHover.hovered ? theme.rowHover : "transparent"
        Row {
            id: bbRow
            x: 9; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { visible: !!bb.icon; anchors.verticalCenter: parent.verticalCenter; name: bb.icon; size: bb.strong ? 16 : 20; color: theme.onFill(bb, bb.strong ? theme.brandLink : bb.iconColor) }
            Text {
                visible: !!bb.label
                anchors.verticalCenter: parent.verticalCenter
                text: bb.label
                font.family: theme.font; font.pixelSize: 14; font.weight: bb.strong || bb.checked ? Font.DemiBold : Font.Normal
                color: theme.onFill(bb, !bb.enabledState ? theme.disabled : bb.strong ? theme.brandLink : theme.textSecondary)
            }
            FluentIcon { visible: bb.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 16; color: theme.onFill(bb, bb.enabledState ? theme.textSecondary : theme.disabled) }
            FluentIcon { visible: bb.checked; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-12"; size: 12; color: theme.onFill(bb, theme.brand) }
        }
        HoverHandler { id: bbHover; enabled: bb.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: bb.enabledState; onTapped: bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: bb.accessible || bb.label
        Accessible.checked: bb.checked
    }
    component LinkButton: Text {
        id: lb
        property string label
        property bool bold: false
        signal clicked()
        text: lb.label
        font.family: theme.font; font.pixelSize: 14; font.weight: lb.bold ? Font.DemiBold : Font.Normal
        font.underline: lbHover.hovered
        color: theme.brandLink
        HoverHandler { id: lbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lb.clicked() }
        Accessible.role: Accessible.Link
        Accessible.name: lb.label
    }
    // Fluent switch, 40 x 20 (brand when on); `outline` is the off look of
    // All day / Send personal invites (white with a grey ring).
    component SwitchBox: Rectangle {
        id: sw
        property bool on: false
        property bool outline: false
        property string accessible
        signal toggled()
        width: 40; height: 20; radius: 10
        color: on ? theme.checkedFill : theme.surface
        border.color: on ? "transparent" : theme.textSecondary
        Rectangle {
            x: sw.on ? sw.width - 17 : 3; anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: sw.on ? theme.onFill(sw, "white") : theme.textSecondary
            Behavior on x { NumberAnimation { duration: 100 } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sw.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: sw.accessible
        Accessible.checked: sw.on
    }
    // A picked person: 32 tall, the avatar, the name (12) over their
    // availability (10/600), a dismiss.
    component PersonChip: Rectangle {
        id: pc
        property string name
        property string mail
        property string status
        property color statusColor
        property bool removable: true
        signal remove()
        width: pcRow.implicitWidth + (removable ? 34 : 12); height: 42; radius: 4
        color: "transparent"
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 36; radius: 18; color: theme.surface }
        Row {
            id: pcRow
            x: 2; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Avatar { anchors.verticalCenter: parent.verticalCenter; size: 32; name: pc.name }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: pc.name; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                Text { visible: !!pc.status; text: pc.status; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: pc.statusColor }
            }
        }
        Item {
            visible: pc.removable
            anchors.right: parent.right; anchors.rightMargin: 6
            width: 20; height: parent.height
            FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textSecondary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: pc.remove() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Remove %1").arg(pc.name)
        }
        Accessible.role: Accessible.ListItem
        Accessible.name: pc.name + (pc.status ? ", " + pc.status : "")
    }
    // The time combobox: 100 x 32, editable, a 34 px ▾ at its end.
    component TimeBox: Rectangle {
        id: tb
        property date value
        property string accessible
        signal openList()
        signal typed(string text)
        width: 100; height: 32; radius: 4
        color: theme.inputFilled
        Rectangle { visible: tbInput.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        TextInput {
            id: tbInput
            x: 12; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
            text: theme.fmtTime(tb.value, "h:mm AP")
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
            selectByMouse: true; clip: true
            onActiveFocusChanged: { if (activeFocus) selectAll(); else if (text !== theme.fmtTime(tb.value, "h:mm AP")) tb.typed(text) }
            Keys.onReturnPressed: tb.typed(text)
            Keys.onEnterPressed: tb.typed(text)
            Accessible.role: Accessible.ComboBox
            Accessible.name: tb.accessible
        }
        Item {
            x: parent.width - 34; width: 34; height: parent.height
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-20"; size: 16; color: theme.textSecondary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: tb.openList() }
        }
    }
    component FmtButton: Rectangle {
        id: fbt
        property string icon
        property string tip
        property bool enabledState: true
        signal clicked()
        width: 32; height: 32; radius: 4
        color: fbtHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: fbt.icon; size: 16; color: theme.onFill(fbt, fbt.enabledState ? theme.textStrong : theme.disabled) }
        HoverHandler { id: fbtHover; enabled: fbt.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: fbt.enabledState; onTapped: fbt.clicked() }
        ToolTip.visible: fbtHover.hovered
        ToolTip.text: fbt.tip
        ToolTip.delay: 600
        Accessible.role: Accessible.Button
        Accessible.name: fbt.tip
    }
    component FmtSep: Item {
        width: 9; height: 32
        Rectangle { anchors.centerIn: parent; width: 1; height: 16; color: theme.divider }
    }
    // A note box: #F5F5F5 (or outlined), a brand line under it.
    component NoteBox: Rectangle {
        id: nb
        property alias text: nbEdit.text
        property string placeholder
        property bool outlined: false
        radius: 4
        color: outlined ? theme.surface : theme.inputFilled
        border.color: outlined ? theme.stroke : "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        Flickable {
            anchors.fill: parent; anchors.margins: 12
            contentHeight: nbEdit.contentHeight
            clip: true
            TextEdit {
                id: nbEdit
                width: parent.width
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                selectByMouse: true
                Accessible.role: Accessible.EditableText
                Accessible.name: nb.placeholder
                Text { visible: !nbEdit.text; text: nb.placeholder; color: theme.textSecondary; font: nbEdit.font }
            }
        }
    }
    // The Options pane's dropdowns: 244 x 32, white with a #D1D1D1 border.
    component PaneDropdown: Rectangle {
        id: pd
        property string value
        /// [[value, label]]: the value is kept and sent, the label shown.
        property var options: []
        property string accessible
        signal chosen(string value)
        width: 244; height: 32; radius: 4
        color: theme.surface; border.color: theme.stroke
        Text { x: 12; width: parent.width - 44; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: (pd.options.find(o => o[0] === pd.value) || [pd.value, pd.value])[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pdMenu.open() }
        Accessible.role: Accessible.ComboBox
        Accessible.name: pd.accessible
        MenuPopup {
            id: pdMenu
            y: pd.height + 2
            items: pd.options.map(o => ({ label: o[1], checked: o[0] === pd.value }))
            onPicked: i => pd.chosen(pd.options[i][0])
        }
    }
    component TrackRow: Row {
        id: tr
        property string name
        property string sub
        spacing: 12
        Avatar { anchors.verticalCenter: parent.verticalCenter; size: 32; name: tr.name }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: tr.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { visible: !!tr.sub; text: tr.sub; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
    }
}
