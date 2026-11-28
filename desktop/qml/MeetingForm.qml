import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import com.ost.desktop

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
    /// scope: "" (an event that doesn't repeat), "occurrence", "following"
    /// or "series".
    signal cancelMeeting(string note, string scope)
    signal respond(string response, bool sendResponse, string note, bool series)
    /// Add to calendar (a team calendar's meeting, Teams' AddToMyCalendar).
    signal addToCalendar()
    signal join()
    signal openChat()
    signal copyLink()
    /// A command of Outlook's event form the calendar carries out for the
    /// event (CalendarView.tileAct's: "owa:Forward", "owa:Duplicate",
    /// "owa:Print", "owa:Save as .ics", "owa:Propose new time",
    /// "owa:Breakout rooms", "copy", "charm:<n>", "showAs:<v>", "cat:<name>",
    /// "private", "reminder:<min>", "patch:<json>", "delete", "apps",
    /// "options", "popout").
    signal command(string act)
    /// Copilot with a prompt (a Prepare chip, Add a room); "" opens it.
    signal copilotPrompt(string label)

    // ── what the calendar gives Outlook's form ──────────────────────
    /// The charms (CalendarView.charms: [id, name, icon, label]) and this
    /// event's charm id.
    property var charms: []
    property int charm: 0
    /// A Copilot licence: the Copilot button, the Prepare card, Add a room.
    property bool copilot: false
    /// Your master categories ([{name, color}]) and their tag colours.
    property var categories: []
    property var categoryTagOf: null

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
    /// Your own event's page (not a channel meeting) is Outlook's event
    /// form on Teams desktop (winpc, 2026-11-23/24, CSS px): a 48 px title
    /// bar "<subject> - Event instance" (Meeting, Event series) with Open
    /// in new window and Close 48 x 48; on #FAFAFA the command bar card (16
    /// in, 8 under the bar, 40 tall, radius 8) and Copilot's round button;
    /// 10 under it the info bar, the Prepare card, the fields' card and the
    /// body's card, 813 wide (radius 8, 8 apart); the Tracking pane a 351
    /// wide card 16 from the right edge, level with the info bar (the
    /// details are in docs/spec/calendar.md and the parts below). An
    /// invitation's page (someone else's event) is Outlook's reading form:
    /// "<subject> - Meeting - Calendar", the answers in the command bar,
    /// the fields read-only.
    readonly property bool outlookPage: existing && !channel
    /// A channel meeting read from its team's calendar (not in yours: the
    /// Meetings pane's): Teams' channel event page, Add to calendar and
    /// Copy link in place of the answers.
    readonly property bool teamCalendarEvent: String(event.calendar_id || "").startsWith("group:")
    readonly property bool outlookRead: outlookPage && readOnly
    readonly property bool outlookEdit: outlookPage && !readOnly
    readonly property bool readOnly: mode === "view"
    /// Outlook's personal settings of the event (Graph): the reminder
    /// (minutes, -1 off), whether answers are asked for and the attendee
    /// list hidden; saved as they change, as Outlook's form does.
    property int reminder: 15
    property bool responseRequested: true
    property bool hideAttendees: false
    property string sensitivity: "normal"
    property var eventCategories: []
    /// The Prepare card's second row of chips (More suggestions).
    property bool moreSuggestions: false
    /// The time row's panel (Start date, times, All day, Recurring).
    property bool timeOpen: false
    /// The body's formatting toolbar (Show formatting options).
    property bool formatOpen: false
    /// Tracking's attendee order (Sort A to Z / Z to A) and search.
    property int trackSort: 0
    property string trackQuery: ""
    property bool trackSearching: false
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
        : dirty || outlookChanged ? (wasMeeting || hasInvitees ? "send" : "save")
        : event.join_url ? "join" : ""
    readonly property string primaryLabel: ({ join: qsTr("Join"), send: qsTr("Send"), save: qsTr("Save") })[primaryKind] || ""
    // A virtual appointment sends once it has a title and its guests.
    readonly property bool primaryEnabled: primaryKind === "join" ? !!event.join_url
        : virtualAppointment && !existing ? guestsReady && titleInput.text.trim().length > 0 : !!primaryKind
    readonly property int durationMin: Math.max(0, Math.round((endAt - startAt) / 60000))
    /// Outlook's show-as names (its form's menu): Out of office, not Away.
    readonly property var outlookShowAs: ({ Free: qsTr("Free"), WorkingElsewhere: qsTr("Working elsewhere"), Tentative: qsTr("Tentative"), Busy: qsTr("Busy"), Oof: qsTr("Out of office") })
    readonly property var showAsLabels: ({ Free: qsTr("Free"), WorkingElsewhere: qsTr("Working elsewhere"), Tentative: qsTr("Tentative"), Busy: qsTr("Busy"), Oof: qsTr("Away") })

    onRequiredChanged: { if (!loading) { dirty = true; availabilityWanted(allMails()) } if (timeOpen) suggestTimer.restart() }
    onOptionalChanged: { if (!loading) { dirty = true; availabilityWanted(allMails()) } if (timeOpen) suggestTimer.restart() }
    onDetailChanged: if (existing && detail && detail.body_html !== undefined) {
        loading = true
        // A Loop component in the body (Outlook's embedded Loop link)
        // shows as its card under the text, as Outlook's form shows it.
        let html = detail.body_html || ""
        if (outlookEdit) {
            const m = /<a\b[^>]*data-loopstyle="embedded"[^>]*>[\s\S]*?<\/a>/i.exec(html)
            const href = m ? /href="([^"]+)"/i.exec(m[0]) : null
            if (href) {
                bodyLoop = { key: "evloop" + Date.now().toString(36), url: href[1].replace(/&amp;/g, "&"), title: m[0].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim(), description: "", linking: false, existing: true }
                html = html.replace(m[0], "")
            }
        }
        setBody(html); bodyAtLoad = bodyHtml()
        // A series' repeat (an occurrence shows its series').
        if (detail.recurrence && !dirty) { recurrence = scopedRecurrence(fromGraph(detail.recurrence, startAt)); recurrenceAtLoad = recurrenceKey(recurrence) }
        if (detail.reminder !== undefined) reminder = detail.reminder
        if (detail.response_requested !== undefined) responseRequested = detail.response_requested
        if (detail.hide_attendees !== undefined) hideAttendees = detail.hide_attendees
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
        html = keepBodyParts(String(html || ""))
        // (Qt imports only what lies between fragment markers, which would
        // leave the style sheet out; a browser ignores them.)
        editor.text = html ? "<style>a { color: " + bodyLinkSet + "; }</style>" + html.replace(/<!--(Start|End)Fragment-->/g, "") : ""
    }
    /// Body parts Qt's rich text can't keep as Outlook wrote them, kept
    /// aside and put back by bodyHtml(): a OneDrive file's link (Outlook's
    /// read-only link entity: the file-type icon, the #FAFAFA chip, its
    /// classes), by the link's address; a picture kept as a data address
    /// (an inserted stock image or sticker, its alt text and max-width), by
    /// that address, shown fitted into the body's 729 px as Outlook's
    /// max-width does.
    property var bodyLinks: ({})
    property var bodyPictures: ({})
    property var bodyLinkIds: ({})
    /// The body's spelling marks (Teams' Editor session, one document for
    /// the page; from the body's first focus).
    readonly property string bodyDoc: "eventbody-" + Math.random().toString(36).slice(2)
    property bool spellingOn: false
    property var bodyCritiques: []
    function checkBodySpelling() { if (spellingOn && outlookEdit && !readOnly) backend.editorSetText(bodyDoc, editor.getText(0, editor.length)) }
    Connections {
        target: backend
        function onEditorCritiques(doc, json) { if (doc === root.bodyDoc) root.bodyCritiques = JSON.parse(json).filter(c => !c.category || c.category === "Spelling") }
    }
    Component.onDestruction: backend.editorClose(bodyDoc)
    function keepBodyParts(html) {
        const links = {}, pics = {}
        // (As Outlook saves it, the delimiters carry the text's font and
        // the link sits in two spans: Teams on winpc, 2026-11-24.)
        html = html.replace(/<span class="entityDelimiterBefore"[^>]*>[^<]*<\/span>\s*<span class="_Entity[^"]*"[^>]*>\s*(?:<span>\s*)+(<a\b[^>]*data-loopstyle="linkonly"[^>]*>[\s\S]*?<\/a>)\s*(?:<\/span>\s*)+<span class="entityDelimiterAfter"[^>]*>[^<]*<\/span>/g, (all, a) => {
            const href = /\bhref="([^"]*)"/.exec(a)
            if (!href) return all
            links[unescapeHtml(href[1])] = all.replace(/\s+data-imagetype="[^"]*"/g, "")
            return "\u200B" + fileLinkShown(a) + "\u200B"
        })
        // A link with an id (the Teams meeting block's) would come back
        // from Qt split after its first letter, the rest no longer a link:
        // the editor gets it without the id, which goes back on save.
        const ids = {}
        html = html.replace(/<a\b([^>]*)>/gi, (all, attrs) => {
            const h = /\bhref="([^"]*)"/i.exec(attrs), id = /\b(?:id|name)="([^"]*)"/i.exec(attrs)
            if (!h || !id) return all
            ids[unescapeHtml(h[1])] = id[1]
            return "<a" + attrs.replace(/\s+(?:id|name)="[^"]*"/gi, "") + ">"
        })
        bodyLinkIds = ids
        html = html.replace(/<img\b[^>]*>/gi, tag => {
            const src = /\bsrc="(data:image\/[^"]+)"/i.exec(tag)
            if (!src) return tag
            pics[src[1]] = tag.replace(/\s+data-imagetype="[^"]*"/g, "")
            if (/\bwidth="\d/i.test(tag)) return tag
            const size = dataImageSize(src[1])
            if (!size) return tag
            const k = Math.min(1, 729 / size[0])
            return tag.replace(/^<img\b/i, "<img width=\"" + Math.round(size[0] * k) + "\" height=\"" + Math.round(size[1] * k) + "\"")
        })
        bodyLinks = links; bodyPictures = pics
        return html
    }
    function unescapeHtml(s) { return String(s).replace(/&quot;/g, "\"").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") }
    function escapeHtml(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;") }
    /// A file link as the editor shows it: just its address, the icon 16 px
    /// (Qt draws the width attribute, Outlook its style's) and the name on
    /// the chip's #FAFAFA (Qt would turn the entity's id into a named
    /// anchor that splits the link). Outlook sets the icon in the middle
    /// and its text stays where it is on the line (its Aptos 12pt line
    /// grows 0.53 below): the icon here is centred on the line without
    /// making it taller (on the baseline it would push the text down; Qt
    /// sizes a middle picture by the x-height of its own font, so a large
    /// one keeps it inside the line).
    readonly property string linkChip: theme.pick("#FAFAFA", "#292929", "#000000")
    function fileLinkShown(a) {
        const href = (/\bhref="([^"]*)"/i.exec(a) || [])[1] || ""
        const icon = (/<img\b[^>]*\bsrc="([^"]*)"/i.exec(a) || [])[1] || ""
        const name = a.replace(/^<a\b[^>]*>/i, "").replace(/<\/a>\s*$/i, "").replace(/<img\b[^>]*>/gi, "")
        return "<a href=\"" + href + "\" style=\"background-color:" + linkChip + "\">" + (icon ? "<img src=\"" + icon + "\" width=\"16\" height=\"16\" style=\"vertical-align: middle; font-size: 40px\" />" : "") + name + "</a>"
    }
    /// A data: picture's size from its PNG, GIF or JPEG header.
    function dataImageSize(u) {
        const m = /^data:image\/(png|jpe?g|gif);base64,([A-Za-z0-9+/=]+)/i.exec(u)
        if (!m) return null
        let b64 = m[2].slice(0, 262144)
        b64 = b64.slice(0, b64.length - b64.length % 4)
        let b
        try { b = Qt.atob(b64) } catch (e) { return null }
        const at = i => b.charCodeAt(i) & 255
        const kind = m[1].toLowerCase()
        if (kind === "png") return b.length > 24 ? [(at(16) << 24 | at(17) << 16 | at(18) << 8 | at(19)) >>> 0, (at(20) << 24 | at(21) << 16 | at(22) << 8 | at(23)) >>> 0] : null
        if (kind === "gif") return b.length > 10 ? [at(6) | at(7) << 8, at(8) | at(9) << 8] : null
        for (let i = 2; i + 9 < b.length;) {
            if (at(i) !== 0xFF) { i++; continue }
            const mk = at(i + 1)
            if (mk >= 0xC0 && mk <= 0xCF && mk !== 0xC4 && mk !== 0xC8 && mk !== 0xCC) return [at(i + 7) << 8 | at(i + 8), at(i + 5) << 8 | at(i + 6)]
            if (mk === 0xD8 || mk === 0x01 || (mk >= 0xD0 && mk <= 0xD7)) { i += 2; continue }
            i += 2 + (at(i + 2) << 8 | at(i + 3))
        }
        return null
    }
    function regexEscape(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }
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
    // Outlook's suggestion length: "30 min", "1 hr", "1 hr 30 min".
    function durLabelLong(min) {
        const h = Math.floor(min / 60), m = min % 60
        return [h ? qsTr("%1 hr").arg(h) : "", m || !h ? qsTr("%1 min").arg(m) : ""].filter(t => t).join(" ")
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
        sensitivity = ev.sensitivity || "normal"
        eventCategories = (ev.categories || []).slice()
        reminder = 15; responseRequested = ev.response_requested !== false; hideAttendees = false
        timeOpen = false; formatOpen = false; moreSuggestions = false; trackSort = 0; trackQuery = ""; trackSearching = false
        outlookInfo = ({}); outlookAtLoad = ({}); allowForwarding = true; rebookRooms = false; copilotReschedule = false
        acceptDays = defaultAcceptDays(); acceptWeekdays = [1, 2, 3, 4, 5]; acceptTimes = [[0, 720], [720, 780], [780, 1440]]; emailReminders = []; attachments = []
        docLinks = []; timeSuggestions = []; suggestionsKey = ""; facilitatorOn = null; sidePane = ""; bodyLoop = null; spellingOn = false; bodyCritiques = []
        paneOpen = true
        dirty = false
        // Outlook's form opens with the title focused (its brand line).
        if (outlookEdit) Qt.callLater(() => titleInput.forceActiveFocus())
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
        html = html.replace(/(<a [^>]*><span style="(?:[^"]*?[\s;])?)color:(#[0-9a-f]{6});/gi, (all, head, col) => col.toLowerCase() === c ? head : all)
        // File links and kept pictures as Outlook wrote them (Qt splits a
        // link around its icon: each part is an <a> of the same address).
        for (const href in bodyLinks) {
            const zw = "(?:\u200B|&#8203;|&#x200[bB];)?"
            const a = "<a href=\"" + regexEscape(escapeHtml(href)) + "\"[^>]*>[\\s\\S]*?</a>"
            // (and any of its name Qt left outside the link, still on the
            // chip's colour)
            const rest = "(?:<span style=\"[^\"]*background-color:" + regexEscape(linkChip.toLowerCase()) + ";[^\"]*\">[^<]*</span>)*"
            html = html.replace(new RegExp(zw + "(?:" + a + ")+" + rest + zw, "i"), bodyLinks[href].replace(/\$/g, "$$$$"))
        }
        for (const href in bodyLinkIds)
            html = html.replace(new RegExp("<a href=\"" + regexEscape(escapeHtml(href)) + "\""), m => m + " id=\"" + bodyLinkIds[href] + "\"")
        for (const src in bodyPictures) {
            const re = new RegExp("<img\\b[^>]*\\bsrc=\"" + regexEscape(escapeHtml(src)) + "\"[^>]*>", "g")
            html = html.replace(re, bodyPictures[src].replace(/\$/g, "$$$$"))
        }
        // The body's Loop component: Outlook's embedded Loop link.
        if (bodyLoop && bodyLoop.url && html.indexOf(bodyLoop.url) < 0)
            html += "<a href=\"" + bodyLoop.url.replace(/&/g, "&amp;") + "\" class=\"OWAAutoLink none\" data-loopstyle=\"embedded\" style=\"display: block;\">"
                  + String(bodyLoop.title || titleInput.text.trim()).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</a>"
        return html
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
            outlook: outlookPage ? outlookDiff : ({}),
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

    Rectangle { anchors.fill: parent; color: root.outlookPage ? theme.pick("#FAFAFA", "#141414", "#000000") : theme.surface }

    // ── header ──────────────────────────────────────────────────────
    Item {
        id: header
        width: parent.width; height: root.outlookPage ? 48 : 61
        // Outlook's title bar: "<subject> - Event instance" 14 #616161 at
        // 16, Close 48 x 48 at the right, a #D1D1D1 line under it.
        Rectangle {
            visible: root.outlookPage
            anchors.fill: parent; color: theme.surface
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16 - 56; elide: Text.ElideRight
                text: (root.event.subject || qsTr("(No title)")) + " - " + (root.outlookRead ? qsTr("Meeting - Calendar") : root.scope === "occurrence" ? qsTr("Event instance") : root.scope === "series" ? qsTr("Event series") : qsTr("Meeting"))
                font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            // Open in new window (Outlook's form pops itself out).
            Rectangle {
                id: obPop
                anchors.right: parent.right; anchors.rightMargin: 48; width: 48; height: 48
                visible: !root.poppedOut
                color: obPopHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "open-20"; size: 20; color: theme.onFill(obPop, theme.textStrong) }
                HoverHandler { id: obPopHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.command("popout") }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Open in new window")
            }
            Rectangle {
                id: obClose
                anchors.right: parent.right; width: 48; height: 48
                color: obCloseHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(obClose, theme.textStrong) }
                HoverHandler { id: obCloseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.closed() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.stroke }
        }
        Rectangle {
            id: hcFill1
            visible: !root.outlookPage
            x: 20; y: 14; width: 32; height: 32; radius: 4
            color: theme.brandFill
            FluentIcon { anchors.centerIn: parent; name: "calendar-20"; size: 20; color: theme.onFill(hcFill1, "white") }
        }
        Text {
            id: titleText
            visible: !root.outlookPage
            x: 60; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width * 0.35)
            elide: Text.ElideRight
            text: root.mode === "new" ? (root.virtualAppointment ? qsTr("Virtual appointment") : qsTr("New meeting")) : (root.event.subject || qsTr("(No title)"))
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            visible: !root.outlookPage
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
            visible: !root.outlookPage
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
        Rectangle { visible: !root.outlookPage; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }

    // ── command bar ─────────────────────────────────────────────────
    Item {
        id: bar
        anchors.top: header.bottom; anchors.topMargin: root.outlookPage ? 8 : 0
        x: root.outlookPage ? 16 : 0
        width: root.outlookPage ? root.width - 16 - 68 : optionsPane.visible && root.paneOpen ? optionsPane.x : parent.width; height: root.outlookPage ? 40 : 41
        // Outlook's command bar: a white card, radius 8, padding 4 8; its
        // buttons 31 tall (20 px glyph, 14 px #424242 label, a 12 px ▾).
        // Outlook's command bar (Teams' event page, winpc 2026-11-24):
        // - your one-off event: Event | Series, Cancel, Share ▾,
        //   Duplicate | Busy ▾, Reminder ▾, Categories ▾, Private ▾ |
        //   (a Teams meeting: Apps |) Print (and … with Breakout rooms);
        // - your series: Cancel (▾ on one event: This event / This and all
        //   following / All events), the rest as above; one event and
        //   this and following keep Private greyed, this and following
        //   the show-as, reminder and category menus too;
        // - an invitation: Accept, Decline, Follow, RSVP with note,
        //   Propose new time, More options ▾ | Delete, Share ▾, Duplicate
        //   | show as ▾, Reminder ▾, Categories ▾, Private ▾ | Apps |
        //   Print, … (Save as .ics);
        // dividers 12.67 wide (a 16 px #D1D1D1 line), buttons 4 apart.
        FluentSurface {
            visible: root.outlookPage
            anchors.fill: parent; depth: 4; radius: 8; color: theme.surface
            Row {
                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                // An invitation's answers.
                Repeater {
                    model: root.outlookRead ? [
                        { r: "Accept", t: qsTr("Accept"), icon: "checkmark-20", c: theme.hc("#498205", "#3FF23F") },
                        { r: "Decline", t: qsTr("Decline"), icon: "dismiss-20", c: theme.hc("#A4262C", "#FFFFFF") },
                        { r: "Follow", t: qsTr("Follow"), icon: "calendar-eye-20", c: theme.hc("#881798", "#FFFFFF") }
                    ] : []
                    OutlookBarButton {
                        id: rsvpBtn2
                        required property var modelData
                        icon: modelData.icon; iconColor: modelData.c; label: modelData.t
                        onClicked: {
                            if (root.isSeries) { seriesMenu.response = modelData.r; seriesMenu.parent = rsvpBtn2; seriesMenu.y = rsvpBtn2.height + 4; seriesMenu.open() }
                            else root.respond(modelData.r, true, "", false)
                        }
                    }
                }
                OutlookBarButton { visible: root.outlookRead; icon: "note-20"; accessible: qsTr("RSVP with note"); onClicked: rsvpDialog.openFor() }
                OutlookBarButton { visible: root.outlookRead && root.event.allow_new_time_proposals !== false; icon: "calendar-clock-20"; accessible: qsTr("Propose new time"); onClicked: root.command("owa:Propose new time") }
                OutlookBarButton {
                    id: obRespMore
                    visible: root.outlookRead
                    icon: "chevron-down-20"; accessible: qsTr("More options")
                    onClicked: obRespMoreMenu.open()
                    MenuPopup {
                        id: obRespMoreMenu
                        y: obRespMore.height + 1
                        items: [{ label: qsTr("Tentative"), icon: "question-circle-20" }]
                        onPicked: i => { if (root.isSeries) { seriesMenu.response = "Tentative"; seriesMenu.parent = obRespMore; seriesMenu.y = obRespMore.height + 4; seriesMenu.open() } else root.respond("Tentative", true, "", false) }
                    }
                }
                ObSep { visible: root.outlookRead }
                OutlookBarButton { visible: root.outlookRead; icon: "delete-20"; accessible: qsTr("Delete"); onClicked: root.command("delete") }
                // Your one-off event: Event | Series.
                OutlookBarButton {
                    visible: root.outlookEdit && !root.isSeries
                    radio: true; checked: !root.recurrence; icon: "calendar-empty-20-filled"; label: qsTr("Event")
                    onClicked: if (root.recurrence) { root.recurrence = null; root.markDirty() }
                }
                OutlookBarButton {
                    visible: root.outlookEdit && !root.isSeries
                    radio: true; checked: !!root.recurrence; icon: "arrow-repeat-all-20"; label: qsTr("Series")
                    onClicked: if (!root.recurrence) { root.recurrence = root.defaultSeries(); root.markDirty(); root.timeOpen = true }
                }
                ObSep { visible: root.outlookEdit && !root.isSeries }
                OutlookBarButton {
                    id: obCancel
                    visible: root.outlookEdit
                    icon: "calendar-cancel-20"; iconColor: theme.hc("#A4262C", "#FFFFFF"); label: qsTr("Cancel")
                    chevron: root.seriesScoped && root.scope === "occurrence"
                    onClicked: { if (chevron) pageCancelMenu2.open(); else root.openCancel(root.seriesScoped ? root.scope : "") }
                    MenuPopup {
                        id: pageCancelMenu2
                        y: obCancel.height + 1
                        items: [{ label: qsTr("This event") }, { label: qsTr("This and all following events") }, { label: qsTr("All events in the series") }]
                        onPicked: i => root.openCancel(["occurrence", "following", "series"][i])
                    }
                }
                OutlookBarButton {
                    id: obShare
                    icon: "arrow-forward-20"; iconColor: theme.hc("#0078D4", "#FFFFFF"); chevron: true; accessible: qsTr("Share")
                    onClicked: obShareMenu.open()
                    MenuPopup {
                        id: obShareMenu
                        y: obShare.height + 1
                        items: [{ label: qsTr("Forward this event"), icon: "arrow-forward-20", iconColor: theme.hc("#0078D4", "#FFFFFF") }]
                            .concat(root.event.join_url ? [{ label: qsTr("Copy join link"), icon: "link-20" }] : [])
                        onPicked: i => root.command(i === 0 ? "owa:Forward" : "copy")
                    }
                }
                OutlookBarButton { icon: "square-multiple-20"; accessible: qsTr("Duplicate event"); onClicked: root.command("owa:Duplicate") }
                ObSep {}
                // Busy ▾ (show as), Reminder ▾, Categories ▾, Private ▾:
                // saved as they're picked, as Outlook does.
                OutlookBarButton {
                    id: obShowAs
                    icon: "calendar-pattern-20"; label: root.outlookShowAs[root.showAs] || qsTr("Busy"); chevron: true
                    enabledState: root.personalEditable
                    onClicked: obShowAsMenu.open()
                    MenuPopup {
                        id: obShowAsMenu
                        y: obShowAs.height + 1
                        radioColumn: true; radioLabelX: 26
                        items: ["Free", "WorkingElsewhere", "Tentative", "Busy", "Oof"].map(k => ({ label: root.outlookShowAs[k], checked: root.showAs === k }))
                        onPicked: i => { const k = ["Free", "WorkingElsewhere", "Tentative", "Busy", "Oof"][i]; root.showAs = k; root.command("showAs:" + ({ Free: "free", WorkingElsewhere: "workingElsewhere", Tentative: "tentative", Busy: "busy", Oof: "oof" })[k]) }
                    }
                }
                OutlookBarButton {
                    id: obReminder
                    icon: "clock-alarm-20"; chevron: true; enabledState: root.personalEditable
                    accessible: qsTr("Reminder, %1 selected").arg(root.reminderLabel(root.reminder))
                    onClicked: obReminderMenu.open()
                    MenuPopup {
                        id: obReminderMenu
                        y: obReminder.height + 1
                        radioColumn: true; radioLabelX: 26
                        items: root.reminderChoices.map(m => ({ label: root.reminderLabel(m), checked: root.reminder === m }))
                            .concat([{ separator: true }, { label: root.emailReminders.length ? qsTr("Edit email reminder") : qsTr("Add email reminder") }])
                        onPicked: i => {
                            if (i < root.reminderChoices.length) { root.reminder = root.reminderChoices[i]; root.command("reminder:" + root.reminder) }
                            else emailReminderDialog.openFor(root.emailReminders)
                        }
                    }
                }
                OutlookBarButton {
                    id: obCats
                    icon: "tag-20"; chevron: true; enabledState: root.personalEditable; accessible: qsTr("Categories")
                    onClicked: obCatsMenu.open()
                    MenuPopup {
                        id: obCatsMenu
                        y: obCats.height + 1
                        radioColumn: true; radioLabelX: 50
                        items: (root.categories || []).map(c => ({ label: c.name, tag: root.categoryTagOf ? root.categoryTagOf(c.color) : undefined, checked: root.eventCategories.indexOf(c.name) >= 0, persist: true }))
                            .concat([{ separator: true }, { label: qsTr("New category") }])
                        onPicked: i => {
                            const c = (root.categories || [])[i]
                            if (!c) { newCategoryDialog.openNew(); return }
                            const l = root.eventCategories.slice(), k = l.indexOf(c.name)
                            if (k >= 0) l.splice(k, 1); else l.push(c.name)
                            root.eventCategories = l
                            root.command("cat:" + c.name)
                        }
                    }
                }
                OutlookBarButton {
                    id: obPrivate
                    icon: root.sensitivity === "private" ? "lock-closed-20" : "lock-open-20"; chevron: true
                    enabledState: root.personalEditable && root.scope !== "occurrence"
                    accessible: root.sensitivity === "private" ? qsTr("Private") : qsTr("Not private")
                    onClicked: obPrivateMenu.open()
                    MenuPopup {
                        id: obPrivateMenu
                        y: obPrivate.height + 1
                        radioColumn: true; radioLabelX: 26
                        items: [{ label: qsTr("Private"), checked: root.sensitivity === "private" }, { label: qsTr("Not private"), checked: root.sensitivity !== "private" }]
                        onPicked: i => { const s = i === 0 ? "private" : "normal"; if (s !== root.sensitivity) { root.sensitivity = s; root.command("private") } }
                    }
                }
                ObSep {}
                // A Teams meeting's Apps (its meeting apps) and divider.
                OutlookBarButton { visible: !!root.event.join_url; icon: "app-folder-20"; accessible: qsTr("Apps"); onClicked: root.command("apps") }
                ObSep { visible: !!root.event.join_url }
                OutlookBarButton { icon: "print-20"; accessible: qsTr("Print"); onClicked: root.command("owa:Print") }
                OutlookBarButton {
                    id: obMore
                    visible: root.outlookRead || !!root.event.join_url
                    icon: "more-horizontal-20"; accessible: qsTr("More options")
                    onClicked: obMoreMenu.open()
                    MenuPopup {
                        id: obMoreMenu
                        y: obMore.height + 1
                        items: root.outlookRead ? [{ label: qsTr("Save as .ics"), icon: "arrow-download-20" }] : [{ label: qsTr("Breakout rooms"), icon: "people-community-20" }]
                        onPicked: i => root.command(root.outlookRead ? "owa:Save as .ics" : "owa:Breakout rooms")
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                OutlookBarButton {
                    visible: root.outlookEdit && (root.primaryKind === "send" || root.primaryKind === "save")
                    primary: true; strong: true; icon: root.primaryKind === "save" ? "save-20" : "send-20"; label: root.primaryLabel
                    onClicked: root.primaryAction()
                }
                OutlookBarButton { visible: !!root.event.join_url; outlined: true; strong: true; icon: "video-20"; label: qsTr("Join"); onClicked: root.join() }
                OutlookBarButton { visible: !!root.event.join_url; outlined: true; strong: true; icon: "chat-20"; label: qsTr("Chat"); accessible: qsTr("Chat with participants"); onClicked: root.openChat() }
            }
        }
        Row {
            visible: !root.outlookPage
            x: 24; height: 40
            // Organizer of an existing meeting.
            // (Your series' page: Cancel ▾ This event / This and all
            // following events / All events in the series, as Teams'.)
            BarButton2 {
                id: cancelBarBtn
                visible: root.mode === "edit"
                icon: "dismiss-20"; label: qsTr("Cancel meeting"); strong: true
                chevron: root.seriesScoped && !root.channel
                onClicked: {
                    if (root.channel) cancelDialog.open()
                    else if (root.seriesScoped) pageCancelMenu.open()
                    else root.openCancel("")
                }
                MenuPopup {
                    id: pageCancelMenu
                    y: cancelBarBtn.height
                    items: [{ label: qsTr("This event") }, { label: qsTr("This and all following events") }, { label: qsTr("All events in the series") }]
                    onPicked: i => root.openCancel(["occurrence", "following", "series"][i])
                }
            }
            // A team calendar's meeting (Teams' channel event page: Add to
            // calendar, a line, Copy link, Show as greyed).
            BarButton2 {
                visible: root.readOnly && root.teamCalendarEvent
                icon: "add-20"; iconColor: theme.brand; label: qsTr("Add to calendar"); strong: true
                onClicked: root.addToCalendar()
            }
            Rectangle { visible: root.readOnly && root.teamCalendarEvent; width: 1; height: 20; y: 10; color: theme.divider }
            BarButton2 { visible: (root.mode === "edit" || root.teamCalendarEvent) && !!root.event.join_url; icon: "link-20"; label: qsTr("Copy link"); onClicked: root.copyLink() }
            Rectangle { visible: root.mode === "edit"; width: 1; height: 20; y: 10; color: theme.divider }
            // An invitation.
            Repeater {
                model: root.readOnly && !root.teamCalendarEvent ? [
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
            BarButton2 { visible: root.readOnly && !root.teamCalendarEvent; icon: "note-edit-20"; label: qsTr("RSVP with note"); onClicked: rsvpDialog.openFor() }
            Rectangle { visible: root.readOnly && !root.teamCalendarEvent; width: 1; height: 20; y: 10; color: theme.divider }
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
        Rectangle { visible: !root.outlookPage; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
    }
    // Copilot's 44 px round button right of the command bar (white, the
    // depth-16 shadow, its 24 px logo).
    FluentSurface {
        id: obCopilot
        visible: root.outlookPage && root.copilot
        x: root.width - 60; y: header.height + 6; width: 44; height: 44
        depth: 4; radius: 22; color: obCopilotHover.hovered ? theme.rowHover : theme.surface
        Image { anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(48, 48); source: "../assets/icons/copilot-color-48.svg" }
        HoverHandler { id: obCopilotHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.copilotPrompt("") }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Chat with Copilot")
    }
    /// Outlook keeps the show-as, reminder and category menus greyed when
    /// editing this and the following events.
    readonly property bool personalEditable: !(seriesScoped && scope === "following")
    property bool poppedOut: false
    readonly property var reminderChoices: [-1, 0, 5, 15, 30, 60, 120, 720, 1440, 10080]
    function reminderLabel(m) {
        const l = { "-1": qsTr("Don't remind me"), "0": qsTr("At time of event"), "5": qsTr("5 minutes before"), "15": qsTr("15 minutes before"),
            "30": qsTr("30 minutes before"), "60": qsTr("1 hour before"), "120": qsTr("2 hours before"), "720": qsTr("12 hours before"),
            "1440": qsTr("1 day before"), "10080": qsTr("1 week before") }[String(m)]
        return l || qsTr("%1 minutes before").arg(m)
    }
    /// Series on a one-off event: weekly on its weekday, until the last
    /// such weekday within six months (Outlook's default).
    function defaultSeries() {
        const s = dayStart(startAt), e = new Date(s); e.setMonth(e.getMonth() + 6)
        while (e.getDay() !== s.getDay()) e.setDate(e.getDate() - 1)
        return makeRecurrence("week", 1, [s.getDay()], s, e)
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
        anchors { top: bar.bottom; bottom: parent.bottom; left: parent.left; topMargin: root.outlookPage ? 10 : 0; leftMargin: root.outlookPage ? 16 : 0 }
        width: root.outlookPage ? (optionsPane.visible && root.paneOpen ? optionsPane.x - 32 : root.width - 32) : optionsPane.visible && root.paneOpen ? optionsPane.x : parent.width
        contentHeight: root.outlookPage ? ofields.height + 16 : fields.height + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // (Outlook's fields: the icons 18 into the card, the inputs from
        // 52 to 22 before its edge.)
        readonly property real fieldW: root.outlookPage ? width - 74 : Math.max(320, Math.min(1037, width - 74 - 32))
        // Outlook's white cards behind the fields: from the title on.

        Column {
            id: fields
            visible: !root.outlookPage
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
                        linkColor: theme.brand; onLinkActivated: l => backend.openExternal(l)
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
                x: root.outlookPage ? 0 : 32; width: root.outlookPage ? scroller.width : scroller.fieldW + 42; height: visible ? (root.outlookPage ? 36 + 8 : 36) : 0
                Rectangle {
                    height: 36; width: parent.width
                    radius: 4; color: theme.inputFilled; border.width: root.outlookPage ? 0.67 : 0; border.color: theme.stroke
                    FluentIcon { x: 13; anchors.verticalCenter: parent.verticalCenter; name: "info-20"; size: 20; color: theme.textSecondary }
                    Row {
                        x: 41; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                        Text {
                            text: root.scope === "following" ? qsTr("You're editing this and all following events in the series.")
                                : root.scope === "series" ? qsTr("You're editing the series.") : qsTr("You're editing one event in the series.")
                            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                        }
                        LinkButton { visible: root.scope === "occurrence" && !root.outlookPage; label: qsTr("Edit series"); onClicked: root.setScope("series") }
                        LinkButton { visible: root.scope === "occurrence" && !root.outlookPage; label: qsTr("Edit this and all following events"); onClicked: root.setScope("following") }
                        // (Outlook: 23 tall outlined buttons, 12 px, 11 apart.)
                        Row {
                            visible: root.scope === "occurrence" && root.outlookPage
                            anchors.verticalCenter: parent.verticalCenter; spacing: 11
                            InfoBarButton { label: qsTr("Edit series"); onClicked: root.setScope("series") }
                            InfoBarButton { label: qsTr("Edit this and all following events"); onClicked: root.setScope("following") }
                        }
                    }
                }
            }

            // Title
            FieldRow {
                id: titleRow
                icon: "edit-20"; height: root.outlookPage ? 40 : 34
                FieldBox {
                    id: titleBox
                    width: scroller.fieldW; height: 34
                    focused: titleInput.activeFocus
                    TextInput {
                        id: titleInput
                        // (Outlook's form: in its title row, 16 px.)
                        parent: root.outlookEdit ? oTitleSlot : titleBox
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        readOnly: root.readOnly
                        font.family: theme.font; font.pixelSize: root.outlookEdit ? 16 : 14; color: theme.text
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
                        id: locRowItem
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
                            // (Outlook's form: its location field, after
                            // the place.)
                            parent: root.outlookEdit ? oLocSlot : locRowItem
                            visible: !root.readOnly
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.outlookEdit ? oLocSlot.width - (oLocText.visible ? oLocText.width + 8 : 0) : scroller.fieldW - (locChip.visible ? locChip.width + 8 : 0) - 200
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            clip: true; selectByMouse: true
                            Keys.onReturnPressed: root.commitLocation()
                            Keys.onEnterPressed: root.commitLocation()
                            Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.location) { root.location = ""; root.markDirty(); e.accepted = true } }
                            onActiveFocusChanged: if (!activeFocus && text.trim()) root.commitLocation()
                            Accessible.name: qsTr("Add location")
                            Text { visible: !locationInput.text && !root.location && !root.outlookPage; text: qsTr("Add location"); color: theme.textSecondary; font: locationInput.font }
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
                        // (Outlook's form: above its attachments toolbar.)
                        parent: root.outlookEdit ? oFmtSlot : detailsBox
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
                        // Outlook's form: in its body card (black text; an
                        // invitation's #616161, read-only).
                        parent: root.outlookEdit ? oBodySlot : root.outlookRead ? oReadBody : detailsBox
                        x: root.outlookPage ? 0 : 12; y: root.outlookPage ? 0 : fmtBar.visible ? 44 : 12
                        width: parent.width - (root.outlookPage ? 0 : 24)
                        textFormat: TextEdit.RichText
                        wrapMode: TextEdit.Wrap
                        readOnly: root.readOnly
                        selectByMouse: true
                        font.family: theme.font; font.pixelSize: 14
                        color: root.outlookEdit ? theme.pick("#000000", "#FFFFFF", "#FFFFFF") : root.outlookRead ? theme.textSecondary : theme.text
                        onTextChanged: { root.markDirty(); root.checkBodySpelling() }
                        onActiveFocusChanged: if (activeFocus && root.outlookEdit && !root.spellingOn) { root.spellingOn = true; root.checkBodySpelling() }
                        onLinkActivated: link => backend.openExternal(link)
                        // Outlook's body marks misspelt words as the browser's
                        // spellchecker does once the body is first focused
                        // (Teams desktop on winpc, 2026-11-24: a wavy #FF0000
                        // line, a 6 px period 2.67 high and 1.33 thick, its
                        // centre below the word's baseline as Chromium puts
                        // it, 2.33 at 150 %, also on a line a file link makes
                        // taller; no card on a click). OST finds them with
                        // Teams' Editor.
                        RichText { id: bodyRich }
                        Repeater {
                            model: root.spellingOn ? root.bodyCritiques : []
                            Item {
                                id: bsq
                                required property var modelData
                                readonly property rect a: { editor.text; editor.width; return editor.positionToRectangle(modelData.start) }
                                readonly property rect b: { editor.text; editor.width; return editor.positionToRectangle(modelData.start + modelData.length) }
                                // The wave's centre below the line's top.
                                readonly property real mid: { editor.text; editor.width; const m = JSON.parse(bodyRich.spellingMarkLines(JSON.stringify([modelData.start])))[0]; return typeof m === "number" ? m : a.height - 0.33 }
                                z: 1
                                x: a.x; y: a.y + mid - 1.67
                                width: Math.max(1, (b.y === a.y ? b.x : editor.width) - a.x); height: 3.34
                                Canvas {
                                    anchors.fill: parent
                                    onWidthChanged: requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.strokeStyle = "#FF0000"
                                        ctx.lineWidth = 1.33
                                        ctx.beginPath()
                                        for (let x = 0; x <= width; x += 0.5) {
                                            const y = 1.67 + 1.33 * Math.sin(2 * Math.PI * x / 6)
                                            if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                        }
                                        ctx.stroke()
                                    }
                                }
                            }
                        }
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
                        Text { visible: editor.length === 0 && !root.readOnly && !root.outlookPage; text: qsTr("Type details for this new meeting"); color: theme.textSecondary; font: editor.font }
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

        // ── Outlook's event form (your event's page, an invitation's) ──
        // Teams desktop on winpc, 2026-11-24 (CSS px, the page 1212 wide):
        // white cards 813 wide, 8 apart, radius 8, the depth-2 shadow; the
        // field rows 40 tall and 12 apart (12 inside the card), their 20 px
        // #616161 glyphs 18 in, 10 down; the fields from 52 (texts at 64),
        // ending 22 before the card's edge (an invitation's 12), each edit
        // row with a 0.67 #616161 line under it (the focused title a 2 px
        // brand one).
        Column {
            id: ofields
            visible: root.outlookPage
            width: parent.width
            spacing: 8
            readonly property real fieldEnd: width - (root.outlookRead ? 12 : 22)

            // Your series: which events the page edits (36 tall, #F5F5F5,
            // a 0.67 #D1D1D1 edge; the glyph 13 in, the text 41 in, Edit
            // series / Edit this and all following events 12 after it).
            Rectangle {
                visible: root.seriesScoped
                width: parent.width; height: visible ? 36 : 0
                radius: 4; color: theme.inputFilled; border.width: 0.67; border.color: theme.stroke
                FluentIcon { x: 13; y: 8; name: "info-20"; size: 20; color: theme.textSecondary }
                Row {
                    x: 41; height: parent.height; spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.scope === "following" ? qsTr("You're editing this and all following events in the series.")
                            : root.scope === "series" ? qsTr("You're editing the series.") : qsTr("You're editing one event in the series.")
                        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                    Row {
                        visible: root.scope === "occurrence"
                        anchors.verticalCenter: parent.verticalCenter; spacing: 11
                        InfoBarButton { label: qsTr("Edit series"); onClicked: root.setScope("series") }
                        InfoBarButton { label: qsTr("Edit this and all following events"); onClicked: root.setScope("following") }
                    }
                }
            }

            // Prepare for your meeting (Copilot): the calendar-sparkle glyph,
            // "Prepare for your meeting" 14 #242424 at 52,23; "Chat with
            // Copilot to get ready" 12 #616161 at 55 (a series: Show
            // insights, 40 tall); then Copilot's chat glyph and three chips
            // 208.32 x 24 (radius 8, a 0.67 #D1D1D1 edge, 12 px), 216.33
            // apart from 80, More suggestions (▾) at 733 opening three more
            // 30 under them; 12 under the chips the card ends.
            FluentSurface {
                id: prepCard
                visible: root.copilot
                width: parent.width; height: visible ? prepChips.y + prepChips.height + 12 : 0
                depth: 2; radius: 8; color: theme.surface
                readonly property bool insights: false
                readonly property var chips: root.outlookRead
                    ? [qsTr("Talking points"), qsTr("Meeting outcomes"), qsTr("Why attend?"), qsTr("What will be covered?"), qsTr("Suggest a question"), qsTr("Prep me for this")]
                    : [qsTr("Talking points"), qsTr("Identify concerns"), qsTr("What will be covered?"), qsTr("Suggest a question"), qsTr("Meeting outcomes"), qsTr("Prep me for this")]
                FluentIcon { x: 18; y: 22.33; name: "calendar-sparkle-20"; size: 20; color: theme.textSecondary }
                Text { x: 52; y: 23; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Prepare for your meeting"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text {
                    visible: !prepCard.insights
                    x: 52; y: 55; height: 16; verticalAlignment: Text.AlignVCenter
                    text: qsTr("Chat with Copilot to get ready"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                }
                Rectangle {
                    id: insightsBtn
                    visible: prepCard.insights
                    x: 52; y: 55; width: parent.width - 64; height: 40; radius: 4
                    color: insightsHover.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 13; y: 14; name: "chevron-down-12"; size: 12; color: theme.onFill(insightsBtn, theme.text) }
                    Text { x: 31; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Show insights"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(insightsBtn, theme.text) }
                    HoverHandler { id: insightsHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.copilotPrompt("Prep me for this") }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Show insights for this meeting")
                }
                Item {
                    id: prepChips
                    x: 52; y: prepCard.insights ? 107 : 83
                    width: parent.width - 64; height: root.moreSuggestions ? 54 : 24
                    FluentIcon { name: "chat-20-filled"; size: 20; color: theme.brand }
                    Repeater {
                        model: prepCard.chips
                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index
                            visible: index < 3 || root.moreSuggestions
                            x: 28 + (index % 3) * 216.33; y: Math.floor(index / 3) * 30
                            width: 208.32; height: 24; radius: 8
                            color: chipHover.hovered ? theme.rowHover : theme.surface
                            border.width: 0.67; border.color: theme.stroke
                            Text {
                                x: 8.67; width: parent.width - 17.33; anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: chip.modelData; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(chip, theme.text)
                            }
                            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.copilotPrompt(chip.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: chip.modelData
                        }
                    }
                    Rectangle {
                        id: moreChips
                        x: 681; width: 29.33; height: 24; radius: 4
                        color: moreChipsHover.hovered ? theme.rowHover : "transparent"
                        FluentIcon { x: 8.67; y: 6; name: root.moreSuggestions ? "chevron-up-20" : "chevron-down-12"; size: 12; color: theme.onFill(moreChips, root.moreSuggestions ? theme.brand : theme.textStrong) }
                        HoverHandler { id: moreChipsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.moreSuggestions = !root.moreSuggestions }
                        Accessible.role: Accessible.Button
                        Accessible.name: root.moreSuggestions ? qsTr("Less suggestions") : qsTr("More suggestions")
                    }
                }
            }

            // The fields' card.
            FluentSurface {
                id: formCard
                width: parent.width; height: formRows.y + formRows.height + 12
                depth: 2; radius: 8; color: theme.surface
                Column {
                    id: formRows
                    y: 12; width: parent.width
                    spacing: 12

                    // The charm (32 x 32 at 12.5, radius 4, a 0.67 #C7C7C7
                    // edge; the charm 24 px brand, none: a 14 px glyph) and
                    // the title (739 x 40, 16 px, its text 12 in); an
                    // invitation's title 16 px #616161 with Sensitivity
                    // (greyed) at the right.
                    Item {
                        width: parent.width; height: 40
                        Rectangle {
                            id: charmBtn
                            x: 12.5; y: 4; width: 32; height: 32; radius: 4
                            color: charmHover.hovered && root.outlookEdit ? theme.rowHover : "transparent"
                            border.width: 0.67; border.color: theme.pick("#C7C7C7", "#5C5C5C", "#FFFFFF")
                            readonly property var c: root.charm > 0 ? (root.charms || []).find(x => x[0] === root.charm) : null
                            FluentIcon { anchors.centerIn: parent; name: charmBtn.c ? charmBtn.c[2] : "symbols-20"; size: charmBtn.c ? 24 : 14; color: theme.onFill(charmBtn, theme.brand) }
                            HoverHandler { id: charmHover; enabled: root.outlookEdit; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: root.outlookEdit; onTapped: charmPop.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: charmBtn.c ? qsTr("Select an event charm button, %1 icon selected").arg(charmBtn.c[3]) : qsTr("Select an event charm")
                            Popup {
                                id: charmPop
                                y: charmBtn.height + 4
                                padding: 4; width: 454; height: 112
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                background: FluentSurface { depth: 16; radius: 4 }
                                contentItem: Grid {
                                    columns: 12; spacing: 4
                                    Repeater {
                                        model: root.charms
                                        Rectangle {
                                            id: cpCell
                                            required property var modelData
                                            width: 32; height: 32; radius: 2
                                            color: root.charm === modelData[0] ? theme.pick("#DCDFFA", "#2F2F4A", "#1AEBFF") : cpHover.hovered ? theme.rowHover : "transparent"
                                            FluentIcon { anchors.centerIn: parent; name: cpCell.modelData[2] || "prohibited-20"; size: 17; color: theme.onFill(cpCell, theme.textSecondary) }
                                            HoverHandler { id: cpHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: { root.charm = cpCell.modelData[0]; charmPop.close(); root.command("charm:" + cpCell.modelData[0]) } }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: qsTr("%1 icon").arg(cpCell.modelData[3])
                                        }
                                    }
                                }
                            }
                        }
                        Item { id: oTitleSlot; visible: root.outlookEdit; x: 52; width: ofields.fieldEnd - 52; height: 40 }
                        Text {
                            visible: root.outlookRead
                            x: 52; y: 9; height: 22; width: ofields.fieldEnd - 52 - 103.91 - 8; elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            text: root.event.subject || ""
                            font.family: theme.font; font.pixelSize: 16; color: theme.textSecondary
                        }
                        Item {
                            visible: root.outlookRead
                            x: ofields.fieldEnd - 103.91; y: 4; width: 103.91; height: 32
                            FluentIcon { x: 6.67; anchors.verticalCenter: parent.verticalCenter; name: "shield-20"; size: 20; color: theme.text }
                            Text { x: 32.67; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Sensitivity"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.disabled }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Sensitivity")
                        }
                        Rectangle {
                            visible: root.outlookEdit
                            x: 52; y: titleInput.activeFocus ? 39 : 39.67; width: ofields.fieldEnd - 52; height: titleInput.activeFocus ? 2 : 1
                            color: titleInput.activeFocus ? theme.brand : theme.textSecondary
                        }
                    }

                    // Attendees: 28 px pictures in pills (34 tall, a 0.67
                    // #D1D1D1 edge, the name 12 px 40.67 in, ✕ after it), 4
                    // apart from 64; Tracking (92.6) and Response options ▾
                    // (49.33) at the right. An invitation: the names, the
                    // organizer first, "; " between them. This and following:
                    // the names, then "You can only change attendees by
                    // editing the series." with Open series.
                    Item {
                        id: oAttRow
                        width: parent.width
                        height: root.outlookRead ? 40 : root.attendeesLocked ? 51.33 : Math.max(40, oAttFlow.height + 6)
                        readonly property real trackX: ofields.fieldEnd - (root.outlookEdit && !root.attendeesLocked ? 49.33 + 4 : 0) - 92.6
                        FluentIcon { x: 18; y: 10; name: "people-20"; size: 20; color: theme.textSecondary }
                        Flow {
                            id: oAttFlow
                            visible: root.outlookEdit && !root.attendeesLocked
                            x: 64; y: 1; width: oAttRow.trackX - 8 - 64
                            spacing: 4
                            Repeater {
                                model: root.required.concat(root.optional)
                                OutlookChip {
                                    required property var modelData
                                    required property int index
                                    name: modelData.name || modelData.address
                                    onRemove: {
                                        if (index < root.required.length) root.required = root.required.filter((_, j) => j !== index)
                                        else { const k = index - root.required.length; root.optional = root.optional.filter((_, j) => j !== k) }
                                    }
                                }
                            }
                            TextInput {
                                id: oPeople
                                width: 120; height: 34
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                                clip: true; selectByMouse: true
                                onTextEdited: { if (text.trim().length >= 2) root.searchPeople(text.trim()); suggest.target = oPeople; suggest.optionalField = false }
                                Keys.onReturnPressed: suggest.pickFirst(oPeople, false)
                                Keys.onEnterPressed: suggest.pickFirst(oPeople, false)
                                Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.required.length) { root.required = root.required.slice(0, -1); e.accepted = true } }
                                Accessible.name: qsTr("Invite required attendees")
                                Text { visible: !oPeople.text && root.required.length + root.optional.length === 0; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Invite required attendees"); color: theme.textSecondary; font: oPeople.font }
                            }
                        }
                        Text {
                            visible: root.outlookRead || root.attendeesLocked
                            x: 64; y: root.outlookRead ? 10.67 : 0; height: 18.67; width: oAttRow.trackX - 8 - 64
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            text: (root.outlookRead ? [root.event.organizer] : []).concat(root.required.concat(root.optional).map(p => p.name || p.address)).filter(n => n).join("; ")
                            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                        }
                        Row {
                            visible: root.attendeesLocked
                            x: 64; y: 28.67; spacing: 4
                            Text { text: qsTr("You can only change attendees by editing the series."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                            LinkButton { label: qsTr("Open series"); onClicked: root.setScope("series") }
                        }
                        OutlookFieldButton {
                            x: oAttRow.trackX; y: root.attendeesLocked ? 4.33 : 4.33
                            icon: "people-list-20"; label: qsTr("Tracking")
                            onClicked: root.paneOpen = !root.paneOpen
                        }
                        OutlookFieldButton {
                            id: respOpts
                            visible: root.outlookEdit && !root.attendeesLocked
                            x: ofields.fieldEnd - 49.33; y: 4
                            icon: "people-settings-20"; chevron: true; accessible: qsTr("Response options")
                            onClicked: respMenu2.open()
                            OutlookSwitchMenu {
                                id: respMenu2
                                y: respOpts.height + 1
                                // (Sent with Send, as Outlook's form does:
                                // CalendarIsResponseRequested,
                                // DoNotForwardMeeting, HideAttendees.)
                                rows: [{ label: qsTr("Request responses"), on: root.responseRequested },
                                       { label: qsTr("Allow forwarding"), on: root.allowForwarding },
                                       { label: qsTr("Hide attendee list"), on: root.hideAttendees }]
                                tail: qsTr("Add optional attendees")
                                onToggled: i => {
                                    if (i === 0) root.responseRequested = !root.responseRequested
                                    else if (i === 1) root.allowForwarding = !root.allowForwarding
                                    else root.hideAttendees = !root.hideAttendees
                                }
                                onTailPicked: { root.showOptional = true; oPeople.forceActiveFocus() }
                            }
                        }
                        Rectangle { visible: root.outlookEdit; x: 52; y: parent.height - 0.33; width: ofields.fieldEnd - 52; height: 1; color: theme.textSecondary }
                    }

                    // The time: one line (a series: Outlook's sentence),
                    // 14 px #616161 at 64 (an invitation's at 52), opening
                    // the time panel; Show all instances (one event of a
                    // series) and Scheduler at the right.
                    Item {
                        id: oTimeRow
                        width: parent.width; height: 40
                        FluentIcon { x: 18; y: 10; name: "clock-20"; size: 20; color: theme.textSecondary }
                        Text {
                            x: root.outlookRead ? 52 : 64; y: root.outlookRead ? 10 : 10.67; height: root.outlookRead ? 20 : 18.67
                            width: (root.seriesScoped && root.scope === "occurrence" ? showAllBtn.x : schedBtn.x) - 8 - x
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            text: root.timeLine()
                            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                            HoverHandler { enabled: root.outlookEdit; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: root.outlookEdit; onTapped: root.timeOpen = !root.timeOpen }
                        }
                        OutlookFieldButton {
                            id: showAllBtn
                            visible: root.outlookEdit && root.seriesScoped && root.scope === "occurrence"
                            x: schedBtn.x - 4 - width; y: 4.33
                            icon: "document-text-20"; label: qsTr("Show all instances")
                            onClicked: root.command("owa:Show all instances")
                        }
                        OutlookFieldButton {
                            id: schedBtn
                            x: ofields.fieldEnd - width; y: 4.33
                            icon: "calendar-search-20"; label: qsTr("Scheduler")
                            onClicked: root.command("owa:Scheduler")
                        }
                        Rectangle { visible: root.outlookEdit; x: 52; y: 39.67; width: ofields.fieldEnd - 52; height: 1; color: theme.textSecondary }
                    }

                    // If conflicts arise, let Copilot reschedule this event:
                    // a 40 x 20 switch at 64 (greyed on one event, a one-off
                    // and before a series is sent), the label at 112,
                    // Acceptable times ▾ 6 after it, ⓘ 8 after that.
                    // Live when Outlook allows it (one other attendee at
                    // most, not all day, busy, an hour or less, a weekly or
                    // daily repeat); otherwise greyed with ⓘ "Why can't I
                    // use this feature?" and the reason. Saved with Send
                    // (CopilotManagedEventType, Intent).
                    Item {
                        id: rescheduleRow
                        visible: root.outlookEdit
                        width: parent.width; height: 40
                        readonly property bool live: root.rescheduleSwitchLive
                        FluentIcon { x: 18; y: 10; name: "calendar-sparkle-20"; size: 20; color: theme.textSecondary }
                        OutlookSwitch {
                            x: 64; y: 10; on: root.copilotReschedule && (parent.live || root.isSeries); enabledState: parent.live
                            accessible: conflictText.text
                            onToggled: root.copilotReschedule = !root.copilotReschedule
                            HoverHandler { id: reschedHover }
                            ToolTip.visible: reschedHover.hovered && parent.live
                            ToolTip.text: qsTr("If you accept or create another event during this time, Copilot will help resolve conflicts by rescheduling this event.")
                            ToolTip.delay: 600
                        }
                        Text { id: conflictText; x: 116; height: 40; verticalAlignment: Text.AlignVCenter; text: qsTr("If conflicts arise, let Copilot reschedule this event."); font.family: theme.font; font.pixelSize: 14; color: parent.live ? theme.text : theme.disabled
                               TapHandler { enabled: rescheduleRow.live; onTapped: root.copilotReschedule = !root.copilotReschedule } }
                        Row {
                            id: acceptable
                            x: Math.max(conflictText.x + conflictText.implicitWidth + 10, 433.59); height: 40; spacing: 2
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Acceptable times"); font.family: theme.font; font.pixelSize: 14; color: root.acceptableLive ? theme.brand : theme.disabled }
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: root.acceptableLive ? theme.textSecondary : theme.disabled }
                            HoverHandler { enabled: root.acceptableLive; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: root.acceptableLive; onTapped: acceptPop.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Acceptable times")
                            OutlookAcceptableTimes {
                                id: acceptPop
                                x: 64 - acceptable.x - 12; y: 40
                                form: root
                                // Under the row, or over it when there's no
                                // room under it (Outlook's popover flips).
                                onAboutToShow: {
                                    const top = parent.mapToItem(null, 0, 0).y, win = root.Window.window ? root.Window.window.height : 1e6
                                    y = top + 40 + height + 8 > win ? -height - 2 : 40
                                }
                            }
                        }
                        Item {
                            id: reschedInfo
                            visible: !!root.rescheduleBlock
                            x: Math.max(acceptable.x + acceptable.width + 8, 569.22); y: 8; width: 24; height: 24
                            FluentIcon { x: 4; y: 4; name: reschedInfoTap.pressed || reschedWhy.opened ? "info-16" : "info-16-regular"; size: 16; color: reschedWhy.opened ? theme.brand : theme.textStrong }
                            TapHandler { id: reschedInfoTap; onTapped: reschedWhy.opened ? reschedWhy.close() : reschedWhy.open() }
                            HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) reschedWhy.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Why can't I use this feature?")
                            // "Why can't I use this feature?" and the reason
                            // (a 240 wide tooltip over the ⓘ).
                            Popup {
                                id: reschedWhy
                                width: 240; padding: 12
                                x: 12 - width / 2; y: -height - 8
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
                                contentItem: Column {
                                    spacing: 4
                                    Text { width: 216; text: qsTr("Why can't I use this feature?"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text; wrapMode: Text.Wrap }
                                    Text { width: 216; text: root.rescheduleBlock; font.family: theme.font; font.pixelSize: 12; color: theme.text; wrapMode: Text.Wrap; lineHeight: 16; lineHeightMode: Text.FixedHeight }
                                }
                            }
                        }
                    }

                    // The place: Add a room with Copilot (14 #4F52B2 at 64),
                    // the location field (509.34 x 34 at 224.32), Location
                    // settings ▾ (49.33) at the right.
                    Item {
                        id: oLocRow
                        width: parent.width; height: 40
                        FluentIcon { x: 18; y: 10; name: "location-20"; size: 20; color: theme.textSecondary }
                        Text {
                            id: roomLink
                            visible: root.copilot
                            x: 64; y: 10.67; height: 18.67; verticalAlignment: Text.AlignVCenter
                            text: qsTr("Add a room with Copilot"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                            font.underline: roomHover.hovered
                            HoverHandler { id: roomHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.copilotPrompt("Add a room") }
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                        }
                        Text {
                            visible: root.outlookRead && !!root.location
                            x: roomLink.visible ? roomLink.x + roomLink.width + 16 : 64; y: 10.67; height: 18.67; verticalAlignment: Text.AlignVCenter
                            text: root.location; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                        }
                        Row {
                            id: oLocSlot
                            visible: root.outlookEdit
                            x: root.copilot ? 224.32 : 64; y: 3; width: ofields.fieldEnd - 49.33 - 8 - x; height: 34
                            spacing: 8
                            Text {
                                id: oLocText
                                visible: !!root.location
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.location; font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                        }
                        OutlookFieldButton {
                            id: locSettings
                            visible: root.outlookEdit
                            x: ofields.fieldEnd - 49.33; y: 4
                            icon: "location-settings-20"; chevron: true; accessible: qsTr("Location settings")
                            onClicked: locMenu.open()
                            OutlookSwitchMenu {
                                id: locMenu
                                y: locSettings.height + 1
                                rows: [{ label: qsTr("Rebook declined rooms"), on: root.rebookRooms, info: qsTr("Copilot will rebook a similar room if there are room declines or the meeting is rescheduled") }]
                                onToggled: i => root.rebookRooms = !root.rebookRooms
                            }
                        }
                        Rectangle { visible: root.outlookEdit; x: 52; y: 39.67; width: ofields.fieldEnd - 52; height: 1; color: theme.textSecondary }
                    }

                    // Microsoft Teams meeting: its switch (greyed once sent
                    // as one), then "Facilitator is off for this meeting.
                    // Turn on" and Options (89.64) at the right.
                    Item {
                        width: parent.width; height: 40
                        readonly property bool teams: !!root.event.join_url
                        readonly property bool live: root.outlookEdit && !teams
                        FluentIcon { x: 18; y: 10; name: "video-20"; size: 20; color: theme.textSecondary }
                        OutlookSwitch { x: 64; y: 10; on: parent.teams || root.online && root.outlookEdit; enabledState: parent.live; onToggled: { root.online = !root.online; root.markDirty() } }
                        Text { id: teamsLabel; x: 116; height: 40; verticalAlignment: Text.AlignVCenter; text: qsTr("Microsoft Teams meeting"); font.family: theme.font; font.pixelSize: 14; color: parent.live ? theme.text : theme.disabled }
                        FluentIcon {
                            id: facIcon
                            visible: root.outlookEdit && parent.teams
                            x: Math.max(teamsLabel.x + teamsLabel.implicitWidth + 12, 287.85); y: 13
                            name: "sparkle-16"; size: 14; color: theme.textSecondary
                        }
                        Text {
                            id: facText
                            visible: facIcon.visible
                            x: facIcon.x + 18; y: 10.67; height: 18.67; verticalAlignment: Text.AlignVCenter
                            text: root.facilitatorOn ? qsTr("Facilitator is on for this meeting.") : qsTr("Facilitator is off for this meeting."); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                        }
                        // Turn on / Turn off: the meeting's Facilitator
                        // option (POST …/facilitator/options/…
                        // IsGroupCopilotEnabled, as Outlook's form sends).
                        LinkButton {
                            visible: facIcon.visible
                            x: Math.max(facText.x + facText.implicitWidth + 8, root.facilitatorOn ? 0 : 512.63); y: 10.67; height: 18.67; verticalAlignment: Text.AlignVCenter
                            label: root.facilitatorOn ? qsTr("Turn off") : qsTr("Turn on"); color: theme.brand
                            onClicked: root.calendarCall("eventFacilitator", { joinUrl: root.event.join_url, on: !root.facilitatorOn })
                        }
                        // Options: Teams' Meeting options dialog for the
                        // meeting (the same dialog Teams opens over the page).
                        OutlookFieldButton {
                            visible: root.outlookEdit && parent.teams
                            x: ofields.fieldEnd - width; y: 4.33
                            icon: "settings-20"; label: qsTr("Options"); accessible: qsTr("Button that opens the a dialog to change the online meeting options.")
                            onClicked: { root.optionsWanted = true; root.calendarCall("eventOptions", { joinUrl: root.event.join_url }) }
                        }
                    }
                }
                // The time panel (Start date, Start time, End time, the time
                // zone, All day, Recurring; a series' repeat), a white
                // surface 749 wide at 52 under the time row.
                OutlookTimePanel {
                    id: timePanel
                    visible: root.timeOpen && root.outlookEdit
                    x: 52; y: formRows.y + oTimeRow.y + 40 + 4
                    width: parent.width - 64
                    z: 5
                }
            }

            // The body: the editor (748 wide at 53, a 0.67 #D1D1D1 edge,
            // radius 4; its text 9.67 in, at least 71.83 tall, 24 under the
            // text) with the attachments toolbar along its bottom (#F5F5F5,
            // 46.5 tall, 32 px buttons 36 apart from 7: Attach ▾, Insert
            // pictures inline, emoji, Show formatting options, Editor,
            // Loop, accessibility), then Add an agenda (749 x 40, a 0.67
            // #BDBDBD edge) 20 under it; an invitation's body read-only at
            // 52, 22 down.
            FluentSurface {
                id: bodyCard
                width: parent.width
                height: root.outlookRead ? oReadBody.y + oReadBody.height + 22 : agendaBtn.y + 40 + 12
                depth: 2; radius: 8; color: theme.surface
                FluentIcon { x: 18; y: 22; name: "textbox-20"; size: 20; color: theme.textSecondary }
                Item { id: oReadBody; visible: root.outlookRead; x: 52; y: 22; width: parent.width - 64; height: editor.contentHeight }
                Rectangle {
                    id: edBox
                    visible: root.outlookEdit
                    x: 53; y: 12; width: parent.width - 65
                    // The attachments over the text (Outlook's file
                    // chips, 11.67 down) and the Loop component under it.
                    readonly property real chipsH: root.attachments.length ? attachFlow.height + 11.67 : 0
                    readonly property real loopH: bodyLoopCard.visible ? bodyLoopCard.height + 12 : 0
                    readonly property real area: Math.max(71.83, editor.contentHeight + 24 + loopH)
                    height: 6.67 + chipsH + area + strip.height + 0.67
                    radius: 4; color: theme.surface
                    border.width: 0.67; border.color: editor.activeFocus ? theme.brand : theme.stroke
                    // A file chip (Outlook's: 260 x 48, radius 4, a 0.67
                    // #F0F0F0 edge; the type glyph 20 at 7.67, 13.67; the
                    // name 14 #424242 at 34.67, 6.17; its size 10/600
                    // #707070 at 34.67, 27.83; More actions ▾ 32 x 46.67 at
                    // 228.33: Preview, Download, Remove attachment), 4 apart.
                    Flow {
                        id: attachFlow
                        visible: root.attachments.length > 0
                        x: 6.67; y: 11.67; width: parent.width - 13.34; spacing: 4
                        Repeater {
                            model: root.attachments
                            Rectangle {
                                id: achip
                                required property var modelData
                                width: 260; height: 48; radius: 4
                                color: achipHover.hovered ? theme.rowHover : theme.surface
                                border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
                                FluentIcon { x: 7.67; y: 13.67; name: /^image\//.test(achip.modelData.contentType || "") ? "image-20" : "document-20"; size: 20; color: theme.textSecondary }
                                Text { x: 34.67; y: 6.17; width: 191; height: 22.67; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle; text: achip.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                                Text { x: 34.67; y: 27.83; height: 13.33; verticalAlignment: Text.AlignVCenter; text: root.sizeLabel(achip.modelData.size); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                                HoverHandler { id: achipHover }
                                TapHandler { onTapped: root.calendarCall("attachmentFile", { attachmentId: achip.modelData.id, name: achip.modelData.name, download: false }) }
                                Rectangle {
                                    id: achipMore
                                    x: 228.33; y: 0.67; width: 32; height: 46.67
                                    color: achipMoreHover.hovered || achipMenu.opened ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                                    FluentIcon { anchors.centerIn: parent; name: "chevron-down-12"; size: 12; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                                    HoverHandler { id: achipMoreHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: achipMenu.open() }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: qsTr("More actions")
                                    MenuPopup {
                                        id: achipMenu
                                        x: -60; y: achipMore.height + 6
                                        items: [{ label: qsTr("Preview"), icon: "eye-20" }, { label: qsTr("Download"), icon: "arrow-download-20" }, { label: qsTr("Remove attachment"), icon: "dismiss-20" }]
                                        onPicked: i => {
                                            const a = achip.modelData
                                            if (i < 2) root.calendarCall("attachmentFile", { attachmentId: a.id, name: a.name, download: i === 1 })
                                            else root.calendarCall("deleteAttachment", { attachmentId: a.id })
                                        }
                                    }
                                }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: achip.modelData.name + " " + root.sizeLabel(achip.modelData.size)
                            }
                        }
                    }
                    Item { id: oBodySlot; x: 9.67; y: 6.67 + edBox.chipsH; width: parent.width - 19.34; height: edBox.area - edBox.loopH }
                    // Insert Loop component: a Loop component in the body
                    // (made in your OneDrive's Attachments folder, named
                    // after the event; Send puts its link in the body and
                    // DocLinks, as Outlook does).
                    LoopCard {
                        id: bodyLoopCard
                        visible: !!root.bodyLoop
                        x: 9.67; y: 6.67 + edBox.chipsH + editor.contentHeight + 12
                        width: parent.width - 19.34
                        mode: root.bodyLoop && root.bodyLoop.existing ? "edit" : "compose"
                        live: visible
                        loopKey: root.bodyLoop ? root.bodyLoop.key : ""
                        conversation: "event:" + (titleInput.text.trim() || qsTr("Loop component"))
                        componentUrl: root.bodyLoop ? root.bodyLoop.url || "" : ""
                        name: root.bodyLoop && root.bodyLoop.title ? root.bodyLoop.title : (titleInput.text.trim() || qsTr("Loop component"))
                        description: root.bodyLoop ? root.bodyLoop.description || "" : ""
                        linking: !!root.bodyLoop && !!root.bodyLoop.linking
                        onCreated: info => {
                            if (!root.bodyLoop) return
                            root.bodyLoop = Object.assign({}, root.bodyLoop, { driveId: info.driveId || "", itemId: info.itemId || "", linking: true })
                            backend.loopHostRequest("composeLink", root.bodyLoop.key + ":link", JSON.stringify({ driveId: info.driveId, itemId: info.itemId, url: info.componentUrl }))
                        }
                        onTitleChanged: t => { if (root.bodyLoop) root.bodyLoop = Object.assign({}, root.bodyLoop, { title: t }) }
                        onDiscardRequested: {
                            const l = root.bodyLoop
                            root.bodyLoop = null; root.docLinks = []
                            if (l && l.itemId) backend.loopHostRequest("composeDiscard", "compose-discard", JSON.stringify({ driveId: l.driveId, itemId: l.itemId }))
                        }
                    }
                    Connections {
                        target: backend
                        function onLoopHostReply(id, json) {
                            const l = root.bodyLoop
                            if (!l || id !== l.key + ":link") return
                            let r = {}
                            try { r = JSON.parse(json) } catch (e) {}
                            if (r.componentUrl) { root.bodyLoop = Object.assign({}, l, { url: r.componentUrl, description: r.description || "", linking: false }); root.docLinks = [r.componentUrl]; root.markDirty() }
                            else root.bodyLoop = Object.assign({}, l, { linking: false })
                        }
                    }
                    Rectangle {
                        id: strip
                        x: 0.67; y: 6.67 + edBox.chipsH + edBox.area; width: parent.width - 1.34
                        height: 46.5 + (root.formatOpen ? 40 : 0)
                        radius: 4; color: theme.inputFilled
                        Item { id: oFmtSlot; visible: root.formatOpen; x: 7; y: 8; width: parent.width - 14; height: 32 }
                        Row {
                            x: 7; y: (root.formatOpen ? 40 : 0) + 8.5; spacing: 4
                            // Attach ▾ (Outlook's "Attach from": Browse this
                            // computer, OneDrive, Upload and share).
                            OutlookToolButton {
                                id: attachBtn
                                icon: "attach-20"; chevron: true; tip: qsTr("Attach"); checked: attachMenu.opened
                                onClicked: attachMenu.open()
                                MenuPopup {
                                    id: attachMenu
                                    y: -height - 2
                                    header: Component { Text { leftPadding: 8; topPadding: 6; bottomPadding: 6; text: qsTr("Attach from"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textStrong } }
                                    items: [{ label: qsTr("Browse this computer"), icon: "folder-20" }, { label: qsTr("OneDrive"), icon: "onedrive-color" },
                                            { label: qsTr("Upload and share"), icon: "cloud-arrow-up-20" }]
                                    onPicked: i => { if (i === 0) attachDialog.open(); else if (i === 1) root.pickOneDrive(); else uploadFileDialog.open() }
                                }
                            }
                            OutlookToolButton { icon: "image-20"; tip: qsTr("Insert pictures inline"); onClicked: pictureDialog.open() }
                            OutlookToolButton { icon: "sticker-20"; glyph: 22; iconColor: theme.brand; checked: root.sidePane === "graphics"; tip: qsTr("Insert emoji, images and stickers."); onClicked: root.sidePane = root.sidePane === "graphics" ? "" : "graphics" }
                            OutlookToolButton { icon: "text-edit-style-20"; checked: root.formatOpen; tip: qsTr("Show formatting options"); onClicked: root.formatOpen = !root.formatOpen }
                            OutlookToolButton { icon: "text-proofing-tools-20"; tip: qsTr("Editor"); onClicked: editorSettings.open() }
                            OutlookToolButton { icon: "loop-page-20"; iconColor: theme.brand; tip: qsTr("Insert Loop component"); onClicked: root.insertBodyLoop() }
                            OutlookToolButton { icon: "accessibility-checkmark-20"; checked: root.sidePane === "accessibility"; tip: qsTr("Check for accessibility issues"); onClicked: { root.sidePane = "accessibility"; accessibilityPane.check() } }
                        }
                    }
                }
                FluentIcon { visible: root.outlookEdit; x: 18; y: agendaBtn.y + 2; name: "notepad-20"; size: 20; color: theme.textSecondary }
                Rectangle {
                    id: agendaBtn
                    visible: root.outlookEdit
                    x: 52; y: edBox.y + edBox.height + 20; width: parent.width - 64; height: 40; radius: 4
                    color: agendaHover2.hovered ? theme.rowHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                    Text { x: 16.67; y: 8.67; height: 22.67; verticalAlignment: Text.AlignVCenter; text: qsTr("Add an agenda"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(agendaBtn, theme.textStrong) }
                    HoverHandler { id: agendaHover2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { editor.forceActiveFocus(); editor.cursorPosition = editor.length; editor.insert(editor.length, "<p><b>" + qsTr("Agenda") + "</b></p><ul><li></li></ul>"); root.markDirty() } }
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

    // Graphics / Accessibility checker in Tracking's place (Outlook's
    // flex pane: the same 351 wide card).
    OutlookFormPane {
        id: formPane
        z: 4
        visible: root.outlookEdit && root.sidePane !== "" && root.width >= 1000
        mode: root.sidePane || "graphics"
        form: root
        editor: editor
        x: root.width - 16 - 351
        y: header.height + 58
        height: Math.min(510, root.height - y - 16)
        onClosed: root.sidePane = ""
    }
    property alias graphicsPane: formPane
    property alias accessibilityPane: formPane

    // ── Options / Tracking pane ─────────────────────────────────────
    Item {
        id: optionsPane
        visible: root.width >= 1000 && (!root.outlookPage || root.paneOpen)
        x: root.outlookPage ? (root.paneOpen ? root.width - 16 - 351 : root.width - 56) : root.paneOpen ? root.width - 368 : root.width - 56
        anchors { top: header.bottom; bottom: parent.bottom; topMargin: root.outlookPage ? 58 : 0; bottomMargin: root.outlookPage ? 16 : 0 }
        width: root.outlookPage && root.paneOpen ? 351 : root.width - x
        // (Outlook's Tracking pane: a white card, radius 8; "Tracking"
        // 16/600 15 in, a #F0F0F0 line 52 down.)
        FluentSurface { visible: root.outlookPage && root.paneOpen; anchors.fill: parent; depth: 2; radius: 8; color: theme.surface }
        Rectangle { visible: root.outlookPage && root.paneOpen; y: 52; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#141414", "#5C5C5C") }
        Rectangle { visible: !root.outlookPage; width: 1; height: parent.height; color: theme.dividerSoft }
        Text {
            visible: root.paneOpen
            x: root.outlookPage ? 15 : 18; y: root.outlookPage ? 10 : root.existing ? 12 : 10
            height: root.outlookPage ? 31 : implicitHeight; verticalAlignment: Text.AlignVCenter
            text: root.existing ? qsTr("Tracking") : qsTr("Options")
            font.family: theme.font; font.pixelSize: root.outlookPage ? 16 : root.existing ? 18 : 14; font.weight: Font.DemiBold; color: root.outlookPage ? theme.textSecondary : theme.text
        }
        // Outlook's More options: Search attendees, Sort A to Z / Z to A;
        // Copy attendee names, Copy all tracking information, Download as
        // CSV.
        Rectangle {
            id: trackMore
            visible: root.outlookPage
            x: 264; y: 10; width: 32; height: 31.33; radius: 4
            color: trackMoreHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(trackMore, theme.textStrong) }
            HoverHandler { id: trackMoreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: trackMoreMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More options")
            MenuPopup {
                id: trackMoreMenu
                y: trackMore.height + 1
                items: [{ label: qsTr("Search attendees"), icon: "search-16" }, { label: qsTr("Sort attendees A to Z"), icon: "text-sort-ascending-16" }, { label: qsTr("Sort attendees Z to A"), icon: "text-sort-descending-16" },
                        { separator: true }, { label: qsTr("Copy attendee names"), icon: "copy-20" }, { label: qsTr("Copy all tracking information"), icon: "copy-20" }, { label: qsTr("Download as CSV"), icon: "copy-20" }]
                onPicked: i => root.trackAct(i)
            }
        }
        Rectangle {
            id: hcFill2
            anchors.right: parent.right; anchors.rightMargin: root.outlookPage ? 15 : 24; y: root.outlookPage ? 10 : 8
            width: 32; height: root.outlookPage ? 31 : 24; radius: 4
            color: collapseHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: root.outlookPage ? "panel-right-contract-20" : root.paneOpen ? "panel-right-20" : "panel-right-expand-20"; size: 20; color: theme.onFill(hcFill2, root.outlookPage ? theme.textStrong : theme.textSecondary) }
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
        // Outlook's Tracking (winpc, 2026-11-24): "Organizer" (14/600
        // #707070, 30.67 tall, 12 in) 52 down; the organizer (32 px
        // picture at 12, the name 14 #424242 at 52, "Sent on …" 12 #616161
        // 18 under it) in a 47.67 row with a #F0F0F0 line; "Attendees";
        // an invitation's "You didn't respond" (12 #707070, 28.35); then
        // each answer's group ("Didn't respond: 2", 12/600 #707070 at 24
        // after a 12 px ▾, 40 tall) and its people (14 in, 44 apart,
        // "Required"/"Optional" under the name).
        Flickable {
            id: oTrack
            visible: root.paneOpen && root.outlookPage
            y: 52; width: parent.width; height: parent.height - y
            contentHeight: oTrackCol.height + 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: oTrackCol
                width: parent.width
                Rectangle {
                    visible: root.trackSearching
                    x: 12; width: parent.width - 24; height: visible ? 32 : 0; radius: 4
                    color: theme.surface; border.width: 0.67; border.color: theme.stroke
                    TextInput {
                        id: trackSearch
                        x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        onTextEdited: root.trackQuery = text
                        Accessible.name: qsTr("Search attendees")
                        Text { visible: !trackSearch.text; text: qsTr("Search attendees"); color: theme.textSecondary; font: trackSearch.font }
                    }
                }
                Item {
                    width: parent.width; height: 30.67
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Organizer"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                }
                Item { width: 1; height: 12 }
                Item {
                    width: parent.width; height: 47.67
                    Avatar { x: 12; y: 8; size: 32; name: root.event.organizer || root.me.name || ""; colorful: true }
                    Text { x: 52; y: 7; height: 20; verticalAlignment: Text.AlignVCenter; text: root.event.organizer || root.me.name || ""; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                    Text {
                        visible: !!root.sentAt
                        x: 52; y: 25; height: 16; verticalAlignment: Text.AlignVCenter
                        text: root.sentAt ? qsTr("Sent on %1 at %2").arg(theme.fmtDate(root.sentAt, "dddd, M/d/yyyy")).arg(root.fmtTime(root.sentAt)) : ""
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    Rectangle { y: 47; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#141414", "#5C5C5C") }
                }
                Item {
                    width: parent.width; height: 30.67
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Attendees"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                }
                Item { width: 1; height: 10 }
                Item {
                    visible: root.outlookRead
                    width: parent.width; height: visible ? 28.35 + 12 : 0
                    Text {
                        x: 12; height: 28.35; verticalAlignment: Text.AlignVCenter
                        text: ({ accepted: qsTr("You accepted"), tentativelyAccepted: qsTr("You tentatively accepted"), declined: qsTr("You declined"), following: qsTr("You're following") })[root.event.response] || qsTr("You didn't respond")
                        font.family: theme.font; font.pixelSize: 12; color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
                    }
                }
                Repeater {
                    model: [
                        { key: "accepted", label: qsTr("Accepted") },
                        { key: "tentativelyAccepted", label: qsTr("Tentative") },
                        { key: "declined", label: qsTr("Declined") },
                        { key: "following", label: qsTr("Following") },
                        { key: "none", label: qsTr("Didn't respond") }
                    ]
                    Column {
                        id: ogroup
                        required property var modelData
                        readonly property var members: root.trackList.filter(p => root.responseKey(p.response) === modelData.key)
                        property bool open: true
                        visible: members.length > 0
                        width: parent.width
                        Item {
                            width: parent.width; height: 40
                            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: ogroup.open ? "chevron-down-12" : "chevron-right-12"; size: 12; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                            Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: qsTr("%1: %2").arg(ogroup.modelData.label).arg(ogroup.members.length); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                            TapHandler { onTapped: ogroup.open = !ogroup.open }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1: %2").arg(ogroup.modelData.label).arg(ogroup.members.length)
                        }
                        Item { visible: ogroup.open; width: 1; height: 6 }
                        Repeater {
                            model: ogroup.open ? ogroup.members : []
                            Item {
                                id: oPerson
                                required property var modelData
                                width: parent.width; height: 44
                                Avatar { x: 14; y: 1; size: 32; name: oPerson.modelData.name || oPerson.modelData.address; colorful: true }
                                Text { x: 54; y: 0; height: 20; verticalAlignment: Text.AlignVCenter; text: oPerson.modelData.name || oPerson.modelData.address; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                                Text { x: 54; y: 18; height: 16; verticalAlignment: Text.AlignVCenter; text: oPerson.modelData.kind === "optional" ? qsTr("Optional") : qsTr("Required"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Open Profile Card for %1, Status: %2").arg(oPerson.modelData.name || oPerson.modelData.address).arg(oPerson.modelData.kind === "optional" ? qsTr("Optional") : qsTr("Required"))
                            }
                        }
                    }
                }
            }
        }
        // Tracking
        Flickable {
            visible: root.paneOpen && root.existing && !root.outlookPage
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
    /// Tracking's people as Outlook lists them (searched, sorted).
    readonly property var trackList: {
        const q = trackQuery.trim().toLowerCase()
        let l = trackPeople.filter(p => !q || (p.name || "").toLowerCase().indexOf(q) >= 0 || (p.address || "").toLowerCase().indexOf(q) >= 0)
        if (trackSort) l = l.slice().sort((a, b) => trackSort * (a.name || a.address || "").localeCompare(b.name || b.address || ""))
        return l
    }
    /// When the invitation went out (Outlook's "Sent on …"; the event's
    /// createdDateTime).
    readonly property var sentAt: detail && detail.created ? new Date(detail.created) : null
    function trackStatus(p) { return ({ accepted: qsTr("Accepted"), tentativelyAccepted: qsTr("Tentative"), declined: qsTr("Declined"), following: qsTr("Following") })[p.response] || qsTr("Didn't respond") }
    function trackAct(i) {
        if (i === 0) { trackSearching = !trackSearching; trackQuery = ""; if (trackSearching) trackSearch.forceActiveFocus() }
        else if (i === 1) trackSort = 1
        else if (i === 2) trackSort = -1
        else if (i === 4) backend.copyText(trackList.map(p => p.name || p.address).join("; "))
        else if (i === 5) backend.copyText([qsTr("Organizer") + "\t" + (event.organizer || "")]
            .concat(trackList.map(p => (p.name || p.address) + "\t" + (p.kind === "optional" ? qsTr("Optional") : qsTr("Required")) + "\t" + trackStatus(p))).join("\n"))
        else if (i === 6) root.command("csv:" + JSON.stringify([[qsTr("Name"), qsTr("Attendance"), qsTr("Response")], [event.organizer || "", qsTr("Meeting organizer"), qsTr("None")]]
            .concat(trackList.map(p => [p.name || p.address, p.kind === "optional" ? qsTr("Optional attendee") : qsTr("Required attendee"), trackStatus(p)]))))
    }


    // ── behaviour ───────────────────────────────────────────────────
    function commitLocation() {
        const t = locationInput.text.trim()
        if (!t) return
        location = t; locationInput.text = ""; markDirty()
    }
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
                FormButton { primary: true; wide: true; label: qsTr("Cancel meeting"); onClicked: { root.cancelMeeting(cancelNote.text.trim(), ""); cancelDialog.close() } }
            }
        }
    }

    // Cancel meeting (Outlook's dialog on Teams' event page, measured on
    // winpc 2026-11-23): 600 wide, radius 8, padding 24; "Cancel meeting"
    // 20/600; "Cancel … and notify attendees" (14/600 #616161, a 17 px brand
    // glyph) 15 under it; the message box 15 under that (112 tall, a 0.67
    // #616161 edge, padding 12); Send and Discard at the right 8 under it.
    property string cancelScope: ""
    function openCancel(scope) { cancelScope = scope; outlookCancel.open() }
    Popup {
        id: outlookCancel
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; padding: 24.67
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        onAboutToShow: ocNote.text = ""
        onOpened: ocNote.forceActiveFocus()
        contentItem: Item {
            implicitHeight: ocButtons.y + 32 + 8
            Text { id: ocTitle; text: qsTr("Cancel meeting"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
            FluentIcon { x: 0; y: 43.5; name: "calendar-cancel-20"; size: 17; color: theme.hc("#4F52B2", "#FFFFFF") }
            Text {
                id: ocHead
                x: 25; y: 43.5; width: 525
                text: root.cancelScope === "following" ? qsTr("Cancel this and all following events and notify attendees")
                    : root.cancelScope === "series" ? qsTr("Cancel all events in the series and notify attendees")
                    : root.cancelScope === "occurrence" ? qsTr("Cancel this event and notify attendees")
                    : qsTr("Cancel event and notify attendees")
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: theme.textSecondary
            }
            Rectangle {
                id: ocBox
                y: ocHead.y + ocHead.lineCount * 17 + 15.5; width: 550.67; height: 112
                color: theme.surface; border.width: 0.67; border.color: ocNote.activeFocus ? theme.textSecondary : theme.stroke
                bottomLeftRadius: 4; bottomRightRadius: 4
                Flickable {
                    id: ocFlick
                    x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
                    contentHeight: ocNote.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: ocNote
                        width: ocFlick.width; wrapMode: TextEdit.Wrap
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; selectByMouse: true
                        onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > ocFlick.contentY + ocFlick.height) ocFlick.contentY = cursorRectangle.y + cursorRectangle.height - ocFlick.height
                        Accessible.role: Accessible.EditableText
                        Accessible.name: ocHead.text + ", " + qsTr("Add an optional message.")
                        Text { visible: !ocNote.text; text: qsTr("Add a message (optional)"); color: theme.textSecondary; font: ocNote.font }
                    }
                }
            }
            Row {
                id: ocButtons
                anchors.right: parent.right; y: ocBox.y + ocBox.height + 8; spacing: 12
                OutlookButton { primary: true; icon: "send-20"; label: qsTr("Send"); onClicked: { root.cancelMeeting(ocNote.text.trim(), root.cancelScope); outlookCancel.close() } }
                OutlookButton { icon: "delete-20"; label: qsTr("Discard"); onClicked: outlookCancel.close() }
            }
        }
    }
    // Outlook's dialog buttons: 32 tall, padding 0 12, a 20 px glyph 4 in,
    // the label 14/600 8 after it; Send brand, Discard white with a
    // #BDBDBD edge.
    component OutlookButton: Rectangle {
        id: ob
        property string icon
        property string label
        property bool primary: false
        signal clicked()
        width: obRow.implicitWidth + 33.33; height: 32; radius: 4
        color: primary ? (obh.hovered ? theme.brandHover : theme.brandFill) : (obh.hovered ? theme.rowHover : theme.surface)
        border.width: 0.67; border.color: primary ? theme.brandFill : theme.pick("#BDBDBD", "#666666", "#FFFFFF")
        Row {
            id: obRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: ob.icon; size: 20; color: theme.onFill(ob, ob.primary ? "white" : theme.textSecondary) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ob.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(ob, ob.primary ? "white" : theme.textSecondary) }
        }
        HoverHandler { id: obh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ob.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ob.label
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
    function openCancelForTest(scope) { if (channel) cancelDialog.open(); else openCancel(scope || "") }
    function confirmCancelForTest(note) { if (channel) { cancelMeeting(note || "", ""); cancelDialog.close() } else { cancelMeeting(note || "", cancelScope); outlookCancel.close() } }
    readonly property bool cancelOpenForTest: outlookCancel.opened || cancelDialog.opened
    function pageCancelItemsForTest() { return pageCancelMenu.items.map(x => x.label) }
    /// Outlook's page's menus by name (the harness opens and captures them).
    /// The time panel's suggestions as laid out (relative to the panel):
    /// the heading's parts and each row with its texts.
    function suggestionsLayoutForTest() {
        const box = timePanel.suggestItem, out = []
        const g = (it, tag) => { const p = it.mapToItem(timePanel, 0, 0); return [tag, Math.round(p.x * 100) / 100, Math.round(p.y * 100) / 100, Math.round(it.width * 100) / 100, Math.round(it.height * 100) / 100] }
        const walk = (it, depth) => {
            for (const c of it.children) {
                if (!c.visible) continue
                if (c.text !== undefined) out.push(g(c, "text:" + c.text).concat([Math.round(c.implicitWidth * 100) / 100]))
                else if (c.name !== undefined && c.size !== undefined) out.push(g(c, "icon:" + c.name))
                else if (c.radius !== undefined && c.width > 600) out.push(g(c, "row"))
                if (depth < 3) walk(c, depth + 1)
            }
        }
        out.push(g(timePanel, "panel"), g(box, "box"))
        walk(box, 0)
        return out
    }
    /// The page's Outlook parts for the harness.
    function outlookStateForTest() {
        return { info: outlookInfo, diff: outlookDiff, primary: primaryKind, allowForwarding: allowForwarding, responseRequested: responseRequested,
                 hideAttendees: hideAttendees, rebookRooms: rebookRooms, reschedule: copilotReschedule, rescheduleBlock: rescheduleBlock,
                 acceptDays: acceptDays, acceptTimes: acceptTimes, emailReminders: emailReminders, attachments: attachments,
                 facilitator: facilitatorOn, sidePane: sidePane, loop: bodyLoop, suggestions: timeSuggestions, categories: eventCategories, charm: charm }
    }
    function emailReminderDialogForTest() { return emailReminderDialog }
    function newCategoryDialogForTest() { return newCategoryDialog }
    function editorSettingsForTest() { return editorSettings }
    function meetingOptionsForTest() { return meetingOptions }
    function acceptableTimesForTest() { return acceptPop }
    function formPaneForTest() { return formPane }
    function uploadToForTest() { return uploadTo }
    function bodyEditorForTest() { return editor }
    function pageMenuForTest(name) {
        return ({ share: obShareMenu, busy: obShowAsMenu, reminder: obReminderMenu, categories: obCatsMenu, private: obPrivateMenu, more: obMoreMenu,
                  cancel: pageCancelMenu2, response: respMenu2, location: locMenu, tracking: trackMoreMenu, respmore: obRespMoreMenu, charm: charmPop, attach: attachMenu })[name] || null
    }
    function pickReminderForTest(m) { reminder = m; command("reminder:" + m) }
    function pickShowAsForTest(k) { showAs = k; command("showAs:" + ({ Free: "free", WorkingElsewhere: "workingElsewhere", Tentative: "tentative", Busy: "busy", Oof: "oof" })[k]) }
    function openRsvpNoteForTest() { rsvpDialog.openFor() }
    readonly property bool rsvpNoteOpen: rsvpDialog.visible
    function closeRsvpNoteForTest() { rsvpDialog.close() }
    function confirmRsvpNoteForTest(response, note) { rsvpNote.text = note || ""; rsvpDialog.response = response; respond(response, true, note || "", false); rsvpDialog.close() }

    // ── Outlook's form: its parts ───────────────────────────────────
    property bool copilotReschedule: false
    property bool rebookRooms: false
    /// Response options' Allow forwarding (Outlook's DoNotForwardMeeting).
    property bool allowForwarding: true
    /// What Outlook's form reads of the event beyond Graph (GetCalendarEvent,
    /// event_form::outlook_event), set by the calendar as the page opens.
    property var outlookInfo: ({})
    /// The switches as Outlook had them: Send carries only what changed
    /// (Response options, Rebook declined rooms, the Copilot reschedule
    /// switch with its acceptable times), as Outlook's form does (winpc,
    /// 2026-11-24: toggling one back takes Send away again).
    property var outlookAtLoad: ({})
    /// Acceptable times: the days ("yyyy-MM-dd") and the times of day
    /// ([from, to] minutes: Morning 0..720, Midday 720..780, Afternoon
    /// 780..1440, Custom).
    property var acceptDays: []
    property var acceptTimes: []
    /// A series' acceptable weekdays (0 Sunday … 6 Saturday, in the order
    /// picked; Outlook starts Monday to Friday); the series' own days are
    /// always in (`seriesWeekdays`).
    property var acceptWeekdays: [1, 2, 3, 4, 5]
    /// Acceptable times for the series (weekdays instead of dates).
    readonly property bool acceptSeries: outlookEdit && !!recurrence && !(isSeries && scope === "occurrence")
    /// The series' days as Outlook takes them: a weekly series' days, every
    /// day of a daily one, else its start's weekday.
    readonly property var seriesWeekdays: {
        const r = recurrence
        if (!r) return []
        if (r.unit === "week") return r.days.slice().sort()
        if (r.unit === "day" && r.interval === 1) return [0, 1, 2, 3, 4, 5, 6]
        return [startAt.getDay()]
    }
    // Turning on "let Copilot reschedule" starts Acceptable times afresh,
    // as Outlook's form does.
    onCopilotRescheduleChanged: if (copilotReschedule && !loading) {
        acceptDays = defaultAcceptDays(); acceptWeekdays = [1, 2, 3, 4, 5]; acceptTimes = [[0, 720], [720, 780], [780, 1440]]
    }
    /// Reminder ▸ Add email reminder: [{id, offset, message, sendOption}].
    property var emailReminders: []
    /// The event's attachments ([{id, name, size, contentType}]) and the
    /// Loop components put in the body (their links, Send's DocLinks).
    property var attachments: []
    property var docLinks: []
    /// Time suggestions ([{start, end, available, total, confidence}]) for
    /// the panel's times and attendees (suggestionsKey).
    property var timeSuggestions: []
    property string suggestionsKey: ""
    property bool suggestionsLoading: false
    /// The meeting's Facilitator option (null until read).
    property var facilitatorOn: null
    /// The right column's pane instead of Tracking: "graphics" (Insert
    /// emoji, images and stickers) or "accessibility".
    property string sidePane: ""
    onSidePaneChanged: if (sidePane) paneOpen = true
    /// The Loop component put in the body: {key, url, driveId, itemId, title}.
    property var bodyLoop: null
    /// A calendar request of the page ("outlookEvent", "findTimes",
    /// "emailReminders", "newCategory", "attachFile", "deleteAttachment",
    /// "attachmentFile", "eventOptions", "setEventOptions",
    /// "eventFacilitator", "uploadShare", "shareLink", "graphics",
    /// "graphicsThemes", "graphicsFile", "driveFolders", "createFolder",
    /// "editorOptions", "setEditorOptions"); the answer comes back in
    /// actionDone().
    signal calendarCall(string op, var args)
    onOutlookInfoChanged: {
        const o = outlookInfo || {}
        if (o.allowForwarding === undefined) return
        allowForwarding = o.allowForwarding
        responseRequested = o.requestResponses !== false
        hideAttendees = !!o.hideAttendees
        rebookRooms = !!o.rebookRooms
        copilotReschedule = o.managed === 1
        if ((o.intentDays || []).length) acceptDays = o.intentDays.slice()
        if ((o.intentWeekdays || []).length) acceptWeekdays = o.intentWeekdays.map(n => dayNames.indexOf(n)).filter(i => i >= 0)
        if ((o.intentTimes || []).length) acceptTimes = o.intentTimes.map(t => [t[0], t[1]])
        emailReminders = (o.inboxReminders || []).slice()
        attachments = (o.attachments || []).slice()
        outlookAtLoad = { allowForwarding: allowForwarding, requestResponses: responseRequested, hideAttendees: hideAttendees,
                          rebookRooms: rebookRooms, managed: copilotReschedule, intent: intentJson() }
    }
    /// What Send carries beyond the form's fields (event_form::form_updates).
    function outlookChanges() {
        const a = outlookAtLoad, c = {}
        if (a.allowForwarding === undefined) return c
        if (allowForwarding !== a.allowForwarding) c.allowForwarding = allowForwarding
        if (responseRequested !== a.requestResponses) c.requestResponses = responseRequested
        if (hideAttendees !== a.hideAttendees) c.hideAttendees = hideAttendees
        if (rebookRooms !== a.rebookRooms) c.rebookRooms = rebookRooms
        const intent = intentJson()
        if (copilotReschedule !== a.managed || (copilotReschedule && intent !== a.intent)) c.managed = { on: copilotReschedule, intent: copilotReschedule ? intent : "" }
        if (docLinks.length) c.docLinks = docLinks
        return c
    }
    readonly property var outlookDiff: outlookChanges()
    readonly property bool outlookChanged: Object.keys(outlookDiff).length > 0
    function isoDay(d) { const p = n => (n < 10 ? "0" : "") + n; return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) }
    /// Acceptable days as Outlook's form starts them: the next five
    /// weekdays from today (winpc 2026-11-24: Tue 24 to Fri 27 and Mon 30).
    function defaultAcceptDays() {
        const out = [], d = new Date(); d.setHours(0, 0, 0, 0)
        while (out.length < 5) { if (d.getDay() > 0 && d.getDay() < 6) out.push(isoDay(d)); d.setDate(d.getDate() + 1) }
        return out
    }
    /// Outlook's Intent (event_form::intent_json): days as Date filters (a
    /// run "a..b", a single day alone), a series' as DayOfWeek filters (its
    /// own days first, then the picked ones), times as TimeOfDay minute
    /// ranges.
    function intentJson() {
        const days = acceptSeries ? [] : acceptDays.slice().sort(), runs = []
        if (acceptSeries) {
            const seen = []
            for (const d of seriesWeekdays.concat(acceptWeekdays)) if (seen.indexOf(d) < 0) { seen.push(d); runs.push({ FilterType: "DayOfWeek", FilterValue: dayNames[d] }) }
        }
        const next = s => { const d = new Date(s + "T00:00:00"); d.setDate(d.getDate() + 1); return isoDay(d) }
        for (let i = 0; i < days.length;) {
            let j = i
            while (j + 1 < days.length && days[j + 1] === next(days[j])) j++
            runs.push({ FilterType: "Date", FilterValue: i === j ? days[i] : days[i] + ".." + days[j] })
            i = j + 1
        }
        const times = acceptTimes.map(t => ({ FilterType: "TimeOfDay", FilterValue: t[0] + ".." + t[1] }))
        const group = l => l.length === 0 ? null : l.length === 1 ? l[0] : { ConstraintType: "OR", Constraints: l }
        const parts = [group(runs), group(times)].filter(x => x)
        return JSON.stringify({ IntentConstraint: { ConstraintType: "AND", Constraints: parts }, Version: 1 })
    }
    /// Why "If conflicts arise, let Copilot reschedule this event." is
    /// greyed (Outlook's reasons, in its order); "" when it can be used.
    /// An occurrence keeps the switch but not Acceptable times.
    readonly property string rescheduleBlock: {
        const r = recurrence
        if (r && !(isSeries && scope === "occurrence") && (r.unit === "year" || r.unit === "month" || r.interval > 1))
            return r.unit === "month" ? qsTr("Events that happen on a specific date of the month can't be automatically rescheduled.")
                                      : qsTr("This event doesn't occur regularly enough to be automatically rescheduled.")
        const me = (event.organizer_address || root.me.mail || "").toLowerCase()
        const others = required.concat(optional).filter(p => (p.address || "").toLowerCase() !== me)
        if (others.length > 1) return qsTr("This feature currently works for personal events or events with just one other attendee in your organization.")
        if (allDay) return qsTr("All day events can't be automatically rescheduled.")
        if (showAs === "Oof") return qsTr("Out of office events can't be automatically rescheduled.")
        if (showAs === "Free") return qsTr("Events marked as Free can't be automatically rescheduled.")
        if (showAs === "Tentative") return qsTr("Events marked as Tentative can't be automatically rescheduled.")
        if (durationMin > 60) return qsTr("Events that are longer than 1 hour can’t be automatically rescheduled.")
        if (isSeries && scope === "occurrence") return qsTr("You can turn automatic rescheduling on or off for this occurrence, but to make other changes, edit the event series.")
        return ""
    }
    readonly property bool rescheduleSwitchLive: outlookEdit && (!rescheduleBlock || (isSeries && scope === "occurrence"))
    readonly property bool acceptableLive: outlookEdit && !rescheduleBlock

    // ── Time suggestions ────────────────────────────────────────────
    /// What the suggestions are for: the attendees, the times and the
    /// repeat (a new key asks again while the panel is open).
    function suggestionsWant() {
        const series = !!recurrence && !(isSeries && scope === "occurrence")
        return JSON.stringify([allMails(), startAt.getTime(), endAt.getTime(), series ? recurrenceKey(recurrence) : ""])
    }
    function askSuggestions() {
        if (!outlookEdit || !timeOpen || allDay || required.length + optional.length === 0) { if (required.length + optional.length === 0) timeSuggestions = []; return }
        const key = suggestionsWant()
        if (key === suggestionsKey) return
        suggestionsKey = key; suggestionsLoading = true
        const p = n => (n < 10 ? "0" : "") + n
        const local = d => isoDay(d) + "T" + p(d.getHours()) + ":" + p(d.getMinutes()) + ":00"
        const args = { key: key, existing: existing, duration: durationMin,
                       attendees: required.map(a => ({ address: a.address })).concat(optional.map(a => ({ address: a.address, optional: true }))) }
        const r = recurrence
        if (r && !(isSeries && scope === "occurrence")) {
            const off = -r.start.getTimezoneOffset(), sign = off >= 0 ? "+" : "-", ao = Math.abs(off)
            const zone = sign + p(Math.floor(ao / 60)) + ":" + p(ao % 60)
            const pattern = { type: ({ day: "daily", week: "weekly", month: "absoluteMonthly", year: "absoluteYearly" })[r.unit], interval: r.interval, firstDayofWeek: "Sunday" }
            if (r.unit === "week") pattern.daysOfWeek = r.days.slice()
            if (r.unit === "month" || r.unit === "year") pattern.dayOfMonth = r.start.getDate()
            if (r.unit === "year") pattern.month = r.start.getMonth() + 1
            args.recurrence = { pattern: pattern, range: r.end ? { type: "endDate", startDate: isoDay(r.start) + "T00:00:00" + zone, endDate: isoDay(r.end) + "T00:00:00" + zone }
                                                         : { type: "noEnd", startDate: isoDay(r.start) + "T00:00:00" + zone } }
        } else {
            // From the event's start: 9 days to look in, the best of 5.
            const to = new Date(startAt); to.setDate(to.getDate() + 9)
            const last = new Date(startAt); last.setDate(last.getDate() + 5)
            args.from = local(startAt); args.to = local(to); args.query = "Date:" + isoDay(startAt) + ".." + isoDay(last)
        }
        calendarCall("findTimes", args)
    }
    onTimeOpenChanged: if (timeOpen) askSuggestions()
    Timer { id: suggestTimer; interval: 400; onTriggered: root.askSuggestions() }
    onStartAtChanged: if (timeOpen) suggestTimer.restart()
    onEndAtChanged: if (timeOpen) suggestTimer.restart()
    onRecurrenceChanged: if (timeOpen) suggestTimer.restart()
    /// Picking a suggestion: its times (a series keeps its repeat).
    /// A suggestion's time: UTC ("…Z") or the zone's wall time.
    function slotTime(t) {
        const m = /^(\d+)-(\d+)-(\d+)[T ](\d+):(\d+)(?::(\d+))?(Z?)/.exec(t || "")
        if (!m) return null
        return m[7] ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5])) : new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5])
    }
    function pickSuggestion(s) {
        const a = slotTime(s.start), b = slotTime(s.end)
        if (!a || !b) return
        if (recurrence && !(isSeries && scope === "occurrence")) {
            const n = new Date(startAt); n.setHours(a.getHours(), a.getMinutes(), 0, 0)
            startAt = n; endAt = new Date(n.getTime() + (b - a))
        } else { startAt = a; endAt = b }
        markDirty()
    }

    /// A calendar answer for the page (CalendarView forwards them).
    function actionDone(op, r, error) {
        if (op === "findTimes") {
            if (r.key !== undefined && r.key !== suggestionsKey) return
            suggestionsLoading = false
            timeSuggestions = error ? [] : (r.suggestions || [])
        } else if (op === "attachFile" && !error && r.id) { attachments = attachments.concat([r]); markDirty() }
        else if (op === "deleteAttachment" && !error) { attachments = attachments.filter(a => a.id !== r.attachmentId); markDirty() }
        else if (op === "attachmentFile" && !error && r.path) { if (!r.download) backend.openLocalPath(r.path) }
        else if ((op === "eventOptions" || op === "setEventOptions") && !error) {
            if (r.facilitator !== undefined && r.facilitator !== null) facilitatorOn = r.facilitator
            // (The dialog takes the options by name.)
            const byName = {}
            for (const o of r.options || []) byName[o.name] = o
            if (optionsWanted) { optionsWanted = false; meetingOptions.options = byName; meetingOptions.people = r; meetingOptions.open() }
            else if (op === "setEventOptions") { meetingOptions.options = byName; meetingOptions.people = r }
        }
        else if (op === "eventFacilitator" && !error) facilitatorOn = !!r.facilitator
        else if ((op === "uploadShare" || op === "shareLink") && !error && r.url) insertFileLink(r.url, r.name || "", r.icon || "")
        else if (op === "graphics") graphicsPane.answer(r, error)
        else if (op === "graphicsThemes") graphicsPane.themesAnswer(r, error)
        else if (op === "graphicsFile" && !error && r.path) insertStockImage(r)
        else if (op === "driveFolders" || op === "createFolder") uploadTo.answer(op, r, error)
        else if (op === "editorOptions" || op === "setEditorOptions") editorSettings.answer(op, r, error)
    }
    property bool optionsWanted: false
    /// A OneDrive file's link at the cursor, as Outlook's Share link and
    /// Upload and share put it (captured 2026-11-24): its read-only link
    /// entity, `<a … class="OWAAutoLink eScj0 none" data-loopstyle="linkonly"
    /// style="…background-color:rgb(250,250,250)">` with the file-type icon
    /// (16 px) before the file's name.
    function insertFileLink(url, name, icon) {
        editor.forceActiveFocus()
        const id = "OLK_Beautified_" + ([8, 4, 4, 4, 12].map(n => Array.from({ length: n }, () => Math.floor(Math.random() * 16).toString(16)).join("")).join("-"))
        const a = "<a href=\"" + escapeHtml(url) + "\" rel=\"noopener noreferrer\" id=\"" + id + "\" class=\"OWAAutoLink eScj0 none\" data-loopstyle=\"linkonly\""
                + " style=\"padding: 0px 1px; border-radius: 2px; user-select: text; background-color: rgb(250, 250, 250);\" data-ogsc=\"\">"
                + "<img src=\"" + escapeHtml(icon) + "\" class=\"suRDx\" alt=\"\" role=\"presentation\" width=\"18\" height=\"18\" style=\"width: 16px; height: 16px; vertical-align: middle; padding: 0px 2px 2px 0px;\">"
                + escapeHtml(name || url) + "</a>"
        const entity = "<span class=\"entityDelimiterBefore\">​</span><span class=\"_Entity _EType_OWALink _EId_OWALink _EReadonly_1\" style=\"display: inline-block;\"><span>"
                     + a + "</span></span><span class=\"entityDelimiterAfter\">​</span>"
        const l = Object.assign({}, bodyLinks); l[url] = entity; bodyLinks = l
        editor.insert(editor.cursorPosition, "\u200B" + fileLinkShown(a) + "\u200B")
        markDirty()
    }
    /// A stock image or sticker in the body (Outlook's, captured
    /// 2026-11-24): the local copy shows (a stock image at its own size up
    /// to the body's 729 px, a sticker 100 x 100); the body keeps it as a
    /// data address, a stock image as a JPEG at quality 50.
    function insertStockImage(r) {
        const local = "file://" + r.path
        const alt = escapeHtml(r.alt || "")
        const p = Object.assign({}, bodyPictures)
        p[local] = r.sticker ? "<img src=\"" + r.dataUri + "\" alt=\"" + alt + "\" width=\"100\" height=\"100\" style=\"width: 100px; height: 100px; max-width: 729px;\">"
                             : "<img src=\"" + r.dataUri + "\" alt=\"" + alt + "\" style=\"max-width: 729px;\">"
        bodyPictures = p
        editor.forceActiveFocus()
        let w = 100, h = 100
        if (!r.sticker) { const k = Math.min(1, 729 / Math.max(1, r.width)); w = Math.round(r.width * k); h = Math.round(r.height * k) }
        editor.insert(editor.cursorPosition, "<img src=\"" + local + "\" width=\"" + w + "\" height=\"" + h + "\" />")
        markDirty()
    }
    function insertEmoji(e) {
        editor.forceActiveFocus()
        editor.insert(editor.cursorPosition, e)
        markDirty()
    }
    /// "20 bytes", "12 KB", "3.4 MB", as Outlook's file chip.
    function sizeLabel(n) {
        n = Number(n || 0)
        if (n < 1024) return qsTr("%n bytes", "", n)
        if (n < 1024 * 1024) return qsTr("%1 KB").arg(Math.round(n / 1024))
        return qsTr("%1 MB").arg((n / 1024 / 1024).toFixed(1))
    }
    function pickOneDrive() { oneDrivePicker.entry = "home"; oneDrivePicker.open() }
    /// Insert Loop component: one Loop component under the text (Outlook
    /// puts one at a time at the cursor; OST keeps it under the text).
    function insertBodyLoop() {
        if (bodyLoop) return
        bodyLoop = { key: "evloop" + Date.now().toString(36), url: "", driveId: "", itemId: "", title: "", description: "", linking: false }
        markDirty()
    }
    /// The time row's text: "Wed 12/2/2026 9:00 PM - 9:30 PM", or for a
    /// series Outlook's sentence ("Occurs every Monday from 9:00 PM to
    /// 9:30 PM effective Mon 11/30/2026 until Mon 5/17/2027").
    function timeLine() {
        const day = theme.fmtDate(startAt, "ddd M/d/yyyy")
        const showSeries = outlookEdit && !!recurrence && (!isSeries || scope !== "occurrence")
        if (!showSeries) return allDay ? day + " " + qsTr("All day") : day + " " + fmtTime(startAt) + " - " + fmtTime(endAt)
        const r = recurrence
        const head = r.unit === "day" ? (r.interval === 1 ? qsTr("Occurs every day") : qsTr("Occurs every %1 days").arg(r.interval))
            : r.unit === "week" ? (r.interval === 1 ? qsTr("Occurs every %1").arg(daysText(r.days)) : qsTr("Occurs every %1 weeks on %2").arg(r.interval).arg(daysText(r.days)))
            : r.unit === "month" ? qsTr("Occurs day %1 of every month").arg(r.start.getDate())
            : qsTr("Occurs every %1 %2").arg(monthLabels[r.start.getMonth()]).arg(r.start.getDate())
        const when = allDay ? "" : " " + qsTr("from %1 to %2").arg(fmtTime(startAt)).arg(fmtTime(endAt))
        const from = " " + qsTr("effective %1").arg(theme.fmtDate(r.start, "ddd M/d/yyyy"))
        const until = r.end ? " " + qsTr("until %1").arg(theme.fmtDate(r.end, "ddd M/d/yyyy")) : ""
        return head + when + from + until
    }
    FileDialog {
        id: pictureDialog
        title: qsTr("Insert pictures inline")
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.gif *.bmp)")]
        onAccepted: { editor.insert(editor.cursorPosition, "<img src=\"" + selectedFile + "\" />"); root.markDirty() }
    }
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }
    // Attach ▸ Browse this computer: the file goes to the event at once
    // (Outlook's CreateAttachmentFromLocalFile).
    FileDialog {
        id: attachDialog
        title: qsTr("Browse this computer")
        onAccepted: root.calendarCall("attachFile", { path: root.localPath(selectedFile) })
    }
    // Attach ▸ Upload and share: the file, then "Upload to" (OneDrive ▸
    // Attachments), then its link in the body.
    FileDialog {
        id: uploadFileDialog
        title: qsTr("Upload and share")
        onAccepted: uploadTo.openFor(root.localPath(selectedFile))
    }
    // "Upload to" (Outlook's, with Change location: OutlookUploadTo).
    OutlookUploadTo {
        id: uploadTo
        form: root
        onUpload: (path, folderId) => root.calendarCall("uploadShare", { path: path, folderId: folderId })
    }
    // Attach ▸ OneDrive: OneDrive's picker; Share link puts the file's link
    // in the body.
    CloudPicker {
        id: oneDrivePicker
        single: true
        confirmLabel: qsTr("Share link")
        onAttached: files => {
            const f = files && files[0]
            if (f) root.calendarCall("shareLink", { driveId: f.drive_id || "", itemId: f.id || "", name: f.name || "" })
        }
    }
    // Options: Teams' Meeting options dialog for the event's meeting.
    MeetingOptionsDialog {
        id: meetingOptions
        onApply: changes => root.calendarCall("setEventOptions", { joinUrl: root.event.join_url, changes: changes })
    }
    // Reminder ▸ Add email reminder (Outlook's "Email reminder" dialog).
    OutlookEmailReminder {
        id: emailReminderDialog
        meeting: root.hasInvitees
        eventStart: root.startAt
        onSaved: list => { root.emailReminders = list; root.calendarCall("emailReminders", { reminders: list }) }
    }
    // Categories ▸ New category (Outlook's "Create new category").
    OutlookNewCategory {
        id: newCategoryDialog
        existing: (root.categories || []).map(c => c.name)
        onCreated: (name, color) => {
            const l = root.eventCategories.concat([name])
            root.eventCategories = l
            root.calendarCall("newCategory", { name: name, color: color, categories: l })
        }
    }
    // Editor: Microsoft Editor Settings (kept in your Outlook options, as
    // Outlook keeps them).
    OutlookEditorSettings { id: editorSettings; form: root }
    // A person in the attendees row (Outlook's pill: 34 tall, a 0.67
    // #D1D1D1 edge; the 28 px picture 2.67 in, the name 12 px 40.67 in, a
    // 20 px ✕ 8 after it, 10.67 to the edge).
    component OutlookChip: Rectangle {
        id: oc
        property string name
        signal remove()
        width: 40.67 + ocName.implicitWidth + 8 + 20 + 10.67; height: 34; radius: 17
        color: theme.surface; border.width: 0.67; border.color: theme.stroke
        Avatar { x: 2.67; y: 3; size: 28; name: oc.name; colorful: true }
        Text { id: ocName; x: 40.67; y: 8.33; height: 16; verticalAlignment: Text.AlignVCenter; text: oc.name; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Item {
            x: 40.67 + ocName.implicitWidth + 8; y: 7; width: 20; height: 20
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: oc.remove() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Remove %1").arg(oc.name)
        }
        Accessible.role: Accessible.ListItem
        Accessible.name: oc.name
    }
    // A field row's button (Tracking, Scheduler, Options: 31.33 tall, the
    // glyph 6.67 in, the label 14/600 #424242 6 after it, 6.67 to the
    // edge; Response options and Location settings: the glyph and a 12 px
    // ▾, 49.33 x 32).
    component OutlookFieldButton: Rectangle {
        id: ofb
        property string icon
        property string label
        property string accessible: ""
        property bool chevron: false
        signal clicked()
        width: label ? 6.67 + 20 + 6 + ofbText.implicitWidth + 6.67 : 6.67 + 20 + 4 + 12 + 6.67
        height: label ? 31.33 : 32; radius: 4
        color: ofbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { x: 6.67; anchors.verticalCenter: parent.verticalCenter; name: ofb.icon; size: 20; color: theme.onFill(ofb, theme.textStrong) }
        Text { id: ofbText; visible: !!ofb.label; x: 32.67; anchors.verticalCenter: parent.verticalCenter; text: ofb.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(ofb, theme.textStrong) }
        FluentIcon { visible: ofb.chevron; x: 30.67; y: 10.67; name: "chevron-down-12"; size: 12; color: theme.onFill(ofb, theme.textStrong) }
        HoverHandler { id: ofbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ofb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ofb.accessible || ofb.label
    }
    // Outlook's switch: 40 x 20, a 0.67 #616161 edge off (#E0E0E0 when
    // greyed) with the 14 px knob at the left; on: brand with a white knob
    // at the right (greyed: #F0F0F0 with a #BDBDBD knob).
    component OutlookSwitch: Rectangle {
        id: osw
        property bool on: false
        property bool enabledState: true
        property string accessible
        signal toggled()
        width: 40; height: 20; radius: 10
        color: osw.on ? (osw.enabledState ? theme.checkedFill : theme.pick("#F0F0F0", "#3D3D3D", "#000000")) : "transparent"
        border.width: osw.on ? 0 : 0.67
        border.color: osw.enabledState ? theme.textSecondary : theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
        Rectangle {
            x: osw.on ? 23 : 3; anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: !osw.enabledState ? theme.disabled : osw.on ? theme.onFill(osw, "white") : theme.textSecondary
        }
        HoverHandler { enabled: osw.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: osw.enabledState; onTapped: osw.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: osw.accessible
        Accessible.checked: osw.on
    }
    // Response options / Location settings: a Fluent menu of switch rows
    // (the label 6 in, the switch 6 after the widest label, 8 from the
    // edge; rows 32 tall, 2 apart) and an optional row after a divider.
    component OutlookSwitchMenu: Popup {
        id: osm
        property var rows: []
        property string tail: ""
        signal toggled(int index)
        signal tailPicked()
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 16; radius: 4 }
        FontMetrics { id: osmMetrics; font.family: theme.font; font.pixelSize: 14 }
        readonly property real labelW: Math.max(0, ...osm.rows.map(r => osmMetrics.advanceWidth(r.label) + (r.info ? 30 : 0)))
        contentItem: Column {
            spacing: 2
            Repeater {
                model: osm.rows
                Rectangle {
                    id: osmRow
                    required property var modelData
                    required property int index
                    width: 6 + osm.labelW + 6 + 40 + 8; height: modelData.info ? 36.5 : 32; radius: 4
                    color: osmHover.hovered ? theme.menuHover : "transparent"
                    Text { x: 6; anchors.verticalCenter: parent.verticalCenter; text: osmRow.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(osmRow, theme.textStrong) }
                    FluentIcon {
                        visible: !!osmRow.modelData.info; x: osmRow.width - 8 - 40 - 6 - 24 + 4; anchors.verticalCenter: parent.verticalCenter; name: "info-16-regular"; size: 16; color: theme.textStrong
                        HoverHandler { id: osmInfoHover }
                        ToolTip.visible: osmInfoHover.hovered && typeof osmRow.modelData.info === "string"
                        ToolTip.text: typeof osmRow.modelData.info === "string" ? osmRow.modelData.info : ""
                        Accessible.role: Accessible.StaticText
                        Accessible.name: ToolTip.text
                    }
                    OutlookSwitch { x: osmRow.width - 8 - 40; anchors.verticalCenter: parent.verticalCenter; on: osmRow.modelData.on; accessible: osmRow.modelData.label; onToggled: osm.toggled(osmRow.index) }
                    HoverHandler { id: osmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: osm.toggled(osmRow.index) }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: osmRow.modelData.label
                    Accessible.checked: osmRow.modelData.on
                }
            }
            Item { visible: !!osm.tail; width: 1; height: 8.67; Rectangle { y: 4; width: 6 + osm.labelW + 6 + 40 + 8; height: 1; color: theme.dividerSoft } }
            Rectangle {
                id: osmTail
                visible: !!osm.tail
                width: 6 + osm.labelW + 6 + 40 + 8; height: 32; radius: 4
                color: osmTailHover.hovered ? theme.menuHover : "transparent"
                Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: osm.tail; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(osmTail, theme.textStrong) }
                HoverHandler { id: osmTailHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { osm.close(); osm.tailPicked() } }
                Accessible.role: Accessible.MenuItem
                Accessible.name: osm.tail
            }
        }
    }
    // The body's toolbar buttons: 32 x 32, radius 2, the 20 px glyph
    // centred (the emoji's 22); Attach 46 wide with a 16 px ▾.
    component OutlookToolButton: Rectangle {
        id: otb
        property string icon
        property string tip
        property bool chevron: false
        property bool checked: false
        property int glyph: 20
        property color iconColor: theme.textStrong
        signal clicked()
        width: chevron ? 46 : 32; height: 32; radius: 2
        color: otb.checked ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : otbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { x: otb.chevron ? 3 : (32 - otb.glyph) / 2; anchors.verticalCenter: parent.verticalCenter; name: otb.icon; size: otb.glyph; color: theme.onFill(otb, otb.iconColor) }
        FluentIcon { visible: otb.chevron; x: 27; y: 8; name: "chevron-down-16"; size: 16; color: theme.onFill(otb, theme.textStrong) }
        HoverHandler { id: otbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: otb.clicked() }
        ToolTip.visible: otbHover.hovered
        ToolTip.text: otb.tip
        ToolTip.delay: 600
        Accessible.role: Accessible.Button
        Accessible.name: otb.tip
    }
    // The time row's panel (Outlook's, measured on winpc 2026-11-24): a
    // white surface (radius 4, the depth-16 shadow); "Start date", "Start
    // time", "End time" 12 px #707070 over their fields (200.67 / 120 / 120
    // x 32 with a 0.67 #D1D1D1 line under them) at 16.67, 244.33, 379.33,
    // 36.67 down; the time zone (a brand globe) at 503.33; All day and
    // Recurring 93.67 down (a series: All day at 551 in the first row and
    // the repeat in the second: Repeat every, the count and unit, the
    // weekday circles 43 apart from 239, Until and its date, Remove).
    component OutlookTimePanel: FluentSurface {
        id: otp
        depth: 16; radius: 4; color: theme.surface
        readonly property bool seriesForm: root.seriesScoped && root.scope !== "occurrence"
        readonly property real repeatY: seriesForm ? 91.67 : 141
        readonly property bool repeatShown: !!root.recurrence && !(root.seriesScoped && root.scope === "occurrence")
        property alias suggestItem: suggestBox
        readonly property real fieldsBottom: repeatShown ? repeatY + 35 : 93.67 + 32
        // Time suggestions (winpc 2026-11-24): the heading 12 under All
        // day (15 under a repeat), its rows 44 under the heading.
        readonly property bool suggestionsShown: root.required.length + root.optional.length > 0 && !root.allDay
        readonly property real suggestY: fieldsBottom + (repeatShown ? 15 : 12)
        readonly property real fullHeight: suggestionsShown ? suggestY + 44 + Math.max(1, root.timeSuggestions.length) * 48 - 8 + 16 : fieldsBottom + 16
        // Outlook's panel shows what fits (245 tall for one event, 289
        // for a series as measured) and scrolls the rest.
        height: Math.min(fullHeight, suggestionsShown ? (repeatShown ? 289 : 245) : fullHeight)
        TapHandler {}
        Flickable {
            id: otpFlick
            anchors.fill: parent
            contentHeight: otp.fullHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: otpFlick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        Item {
            width: otp.width; height: otp.fullHeight
        Repeater {
            model: [[qsTr("Start date"), 16.67, 200.67], [qsTr("Start time"), 244.33, 120], [qsTr("End time"), 379.33, 120]]
            Item {
                id: otpField
                required property var modelData
                required property int index
                x: modelData[1]; width: modelData[2]; height: 72
                Text { x: 5; y: 16.67; height: 20; verticalAlignment: Text.AlignVCenter; text: otpField.modelData[0]; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
                Item {
                    id: otpBox
                    y: 36.67; width: parent.width; height: 32
                    Text {
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        text: otpField.index === 0 ? root.fmtDate(root.startAt) : root.fmtTime(otpField.index === 1 ? root.startAt : root.endAt)
                        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                    FluentIcon { x: otpBox.width - (otpField.index === 0 ? 25 : 18); anchors.verticalCenter: parent.verticalCenter; name: otpField.index === 0 ? "calendar-ltr-20" : "chevron-down-12"; size: otpField.index === 0 ? 20 : 12; color: theme.textSecondary }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.stroke }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (otpField.index === 0) otpDate.openPicker(); else timeList.show(otpBox, otpField.index === 2) } }
                    DatePickerField {
                        id: otpDate
                        visible: otpField.index === 0
                        bare: true; width: otpBox.width; height: otpBox.height
                        date: root.startAt
                        onPicked: d => { const n = new Date(root.startAt); n.setFullYear(d.getFullYear(), d.getMonth(), d.getDate()); root.setStart(n) }
                    }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: otpField.modelData[0]
                }
            }
        }
        Item {
            x: 503.33; y: 34.67; width: 32; height: 32
            FluentIcon { anchors.centerIn: parent; name: "globe-20"; size: 20; color: theme.brand }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Time zone")
        }
        Row {
            x: otp.seriesForm ? 551.33 : 28.67; y: otp.seriesForm ? 34.67 : 93.67; height: 32; spacing: 0
            Item {
                width: 32; height: 32
                Rectangle {
                    anchors.centerIn: parent; width: 16; height: 16; radius: 2
                    color: root.allDay ? theme.checkedFill : "transparent"; border.width: root.allDay ? 0 : 0.67; border.color: theme.textSecondary
                    FluentIcon { visible: root.allDay; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                }
                TapHandler { onTapped: { root.allDay = !root.allDay; root.markDirty() } }
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("All day")
                Accessible.checked: root.allDay
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("All day"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary; TapHandler { onTapped: { root.allDay = !root.allDay; root.markDirty() } } }
        }
        Rectangle {
            id: recurBtn
            visible: !otp.seriesForm && !root.isSeries
            x: 121.46; y: 93.67; width: 110.3; height: 32; radius: 4
            color: recurHover.hovered || root.recurrence ? theme.rowHover : "transparent"
            FluentIcon { x: 12.67; anchors.verticalCenter: parent.verticalCenter; name: "arrow-repeat-all-20"; size: 20; color: theme.onFill(recurBtn, root.recurrence ? theme.brand : theme.textStrong) }
            Text { x: 38.67; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Recurring"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(recurBtn, theme.textStrong) }
            HoverHandler { id: recurHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.recurrence = root.recurrence ? null : root.defaultSeries(); root.markDirty() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Make recurring")
        }
        // The repeat (a series, or a one-off made recurring).
        Item {
            visible: !!root.recurrence && !(root.seriesScoped && root.scope === "occurrence")
            y: otp.repeatY; width: parent.width; height: 35
            readonly property var r: root.recurrence
            Text { x: 18.67; y: 4; height: 26; verticalAlignment: Text.AlignVCenter; text: qsTr("Repeat every"); font.family: theme.font; font.pixelSize: 12; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
            Rectangle {
                id: everyBox
                x: 90.84; y: 2; width: 49.55; height: 28; radius: 4; color: theme.inputFilled
                Text { x: 4; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.r ? parent.parent.r.interval : ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { x: 25.56; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                TapHandler { onTapped: everyMenu.open() }
                MenuPopup {
                    id: everyMenu
                    y: everyBox.height + 2
                    items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => ({ label: String(n), checked: !!root.recurrence && root.recurrence.interval === n }))
                    onPicked: i => { const r = root.recurrence; root.recurrence = root.makeRecurrence(r.unit, i + 1, r.days, r.start, r.end); root.markDirty() }
                }
            }
            Rectangle {
                id: unitBox2
                x: 150.4; y: 2; width: 73.72; height: 28; radius: 4; color: theme.inputFilled
                Text { x: 4; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.r ? ({ day: qsTr("day"), week: qsTr("week"), month: qsTr("month"), year: qsTr("year") })[parent.parent.r.unit] : ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                FluentIcon { x: 49.71; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                TapHandler { onTapped: unitMenu2.open() }
                MenuPopup {
                    id: unitMenu2
                    y: unitBox2.height + 2
                    items: [qsTr("day"), qsTr("week"), qsTr("month"), qsTr("year")].map((l, i) => ({ label: l, checked: !!root.recurrence && root.recurrence.unit === ["day", "week", "month", "year"][i] }))
                    onPicked: i => { const r = root.recurrence; root.recurrence = root.makeRecurrence(["day", "week", "month", "year"][i], r.interval, r.days, r.start, r.end); root.markDirty() }
                }
            }
            Repeater {
                // Monday first, as Outlook's circles.
                model: (parent.r && parent.r.unit === "week") ? [1, 2, 3, 4, 5, 6, 0] : []
                Rectangle {
                    id: wd
                    required property int modelData
                    required property int index
                    readonly property bool on: !!root.recurrence && root.recurrence.days.indexOf(modelData) >= 0
                    x: 239.11 + index * 43; y: 0; width: 32; height: 32; radius: 16
                    color: on ? theme.checkedFill : theme.pick("#EDEBE9", "#3D3D3D", "#000000")
                    Text { anchors.centerIn: parent; text: Qt.locale().dayName(wd.modelData, Locale.NarrowFormat); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(wd, wd.on ? "white" : theme.pick("#201F1E", "#FFFFFF", "#FFFFFF")) }
                    TapHandler {
                        onTapped: {
                            const r = root.recurrence, d = r.days.slice(), k = d.indexOf(wd.modelData)
                            if (k >= 0) { if (d.length > 1) d.splice(k, 1) } else d.push(wd.modelData)
                            root.recurrence = root.makeRecurrence(r.unit, r.interval, d, r.start, r.end); root.markDirty()
                        }
                    }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: root.dayLabels[wd.modelData]
                    Accessible.checked: wd.on
                }
            }
            Text { x: 542.11; y: 4; height: 27.33; verticalAlignment: Text.AlignVCenter; text: qsTr("Until"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Rectangle {
                id: untilBox
                x: 573.03; y: -4; width: 99.01; height: 35.33; radius: 4; color: theme.inputFilled
                Text { x: 6.67; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.r && parent.parent.r.end ? theme.fmtDate(parent.parent.r.end, "MMM d, yyyy") : qsTr("Select date"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                FluentIcon { x: 77.35; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 10; color: theme.textSecondary }
                TapHandler { onTapped: untilPicker.openPicker() }
                DatePickerField {
                    id: untilPicker
                    bare: true; width: untilBox.width; height: untilBox.height
                    date: root.recurrence && root.recurrence.end ? root.recurrence.end : root.startAt
                    minDate: root.startAt
                    onPicked: d => { const r = root.recurrence; root.recurrence = root.makeRecurrence(r.unit, r.interval, r.days, r.start, d); root.markDirty() }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("End date")
            }
            Item {
                visible: !!parent.r && !!parent.r.end
                x: 672.04; y: -4; width: 27; height: 34
                FluentIcon { x: 6; y: 11; name: "delete-16"; size: 16; color: theme.brandLink }
                TapHandler { onTapped: { const r = root.recurrence; root.recurrence = root.makeRecurrence(r.unit, r.interval, r.days, r.start, null); root.markDirty() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Remove end date")
            }
        }
        // Time suggestions: the calendar glyph (20) at 16.67, "Time
        // suggestions" 12/600 at 44.67, ⓘ (18, "The best options in a 5-day
        // window") at 147.73; rows 715.67 x 40, 48 apart, from 44 under it
        // (radius 4, a 0.67 #D1D1D1 edge): one event "Tue 12/1" 12/600 at
        // 16.67, its times and "(30 min)" 12 px 16 after it, and how many
        // are free (a 14 px green person-available and the count, 14 px, 16.67
        // from the right); a series the repeat glyph (16) at 16.67, "Occurs
        // every Thursday" 12/600 at 48.67, the times, and "100% available"
        // (the glyph, the share 12/600, "available" 12).
        Item {
            id: suggestBox
            visible: otp.suggestionsShown
            x: 16.67; y: otp.suggestY; width: 715.67; height: 44 + Math.max(1, root.timeSuggestions.length) * 48 - 8
            FluentIcon { x: 0; y: 6; name: "calendar-ltr-20"; size: 20; color: theme.text }
            Text { id: tsHead; x: 28; y: 8; height: 16; verticalAlignment: Text.AlignVCenter; text: qsTr("Time suggestions"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
            Item {
                x: 131.06; y: 2; width: 18; height: 28
                FluentIcon { x: 0; y: 6; name: "info-16-regular"; size: 18; color: theme.text }
                HoverHandler { id: tsInfoHover }
                ToolTip.visible: tsInfoHover.hovered
                ToolTip.text: qsTr("The best options in a 5-day window")
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("The best options in a 5-day window")
            }
            Text {
                visible: root.timeSuggestions.length === 0
                x: 0; y: 44; height: 40; verticalAlignment: Text.AlignVCenter
                text: root.suggestionsLoading ? qsTr("Searching for suggestions...") : qsTr("No suggestions found")
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
            }
            Repeater {
                model: root.timeSuggestions
                Rectangle {
                    id: tsRow
                    required property var modelData
                    required property int index
                    readonly property bool series: otp.repeatShown
                    readonly property date from: root.slotTime(modelData.start) || new Date()
                    readonly property date to: root.slotTime(modelData.end) || new Date()
                    y: 44 + index * 48; width: 715.67; height: 40; radius: 4
                    color: tsHover.hovered ? theme.rowHover : theme.surface
                    border.width: 0.67; border.color: theme.stroke
                    FluentIcon { visible: tsRow.series; x: 16.67; y: 12; name: "arrow-repeat-all-16"; size: 16; color: theme.text }
                    Text {
                        id: tsDay
                        x: tsRow.series ? 48.67 : 16.67; y: 12; height: 16; verticalAlignment: Text.AlignVCenter
                        text: tsRow.series ? qsTr("Occurs every %1").arg(root.dayLabels[tsRow.from.getDay()]) : theme.fmtDate(tsRow.from, "ddd M/d")
                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text
                    }
                    Text {
                        id: tsTime
                        x: tsDay.x + tsDay.implicitWidth + 16; y: 12; height: 16; verticalAlignment: Text.AlignVCenter
                        text: root.fmtTime(tsRow.from) + " - " + root.fmtTime(tsRow.to)
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    Text {
                        x: tsTime.x + tsTime.implicitWidth + 4; y: 12; height: 16; verticalAlignment: Text.AlignVCenter
                        text: "(" + root.durLabelLong(Math.round((tsRow.to - tsRow.from) / 60000)) + ")"
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 16.67; y: 12; height: 16; spacing: 2
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "person-available-20"; size: 14; color: theme.hc("#0E700E", "#3FF23F") }
                        Text {
                            visible: !tsRow.series
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(tsRow.modelData.available); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                        }
                        Text {
                            visible: tsRow.series
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(tsRow.modelData.confidence) + "%"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text
                        }
                        Text {
                            visible: tsRow.series
                            anchors.verticalCenter: parent.verticalCenter; leftPadding: 2
                            text: qsTr("available"); font.family: theme.font; font.pixelSize: 12; color: theme.text
                        }
                    }
                    HoverHandler { id: tsHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pickSuggestion(tsRow.modelData) }
                    Accessible.role: Accessible.Button
                    Accessible.name: tsDay.text + " " + tsTime.text + (tsRow.series ? ", " + Math.round(tsRow.modelData.confidence) + "% " + qsTr("available") : ", " + qsTr("%1 Available").arg(tsRow.modelData.available))
                }
            }
        }
        }
        }
    }

    // ── parts ───────────────────────────────────────────────────────
    // A field row: its 20 px icon in a 32 x 32 box at 32, the field at 74.
    component FieldRow: Item {
        id: fr
        default property alias content: slot.data
        property string icon
        width: parent ? parent.width : 0
        FluentIcon { visible: !!fr.icon; x: root.outlookPage ? 18 : 38; y: Math.min(fr.height, root.outlookPage ? 40 : 32) / 2 - 10; name: fr.icon; size: 20; color: theme.textSecondary }
        Item { id: slot; x: root.outlookPage ? 52 : 74; width: fr.width - (root.outlookPage ? 52 : 74); height: fr.height }
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
    // Outlook's command bar button: 31 tall, padding 0 7, a 20 px glyph,
    // a 14 px label (600 for Send, Join, Chat), a 12 px ▾; Send brand,
    // Join and Chat outlined.
    // Outlook's command bar button (Fluent ToolbarButton, 31.33 tall,
    // radius 4): an icon-only one is 32 wide (6, the 20 px glyph, 6); else
    // 6.67, the glyph, 4, the 14 px #424242 label, then 4 and the 12 px ▾
    // and 4.67, or 6.67. Join, Chat and Send: 12.67, the glyph, 6,
    // the label 14/600, 12.67 (Join and Chat outlined #D1D1D1, Send brand).
    // Event | Series are radio buttons (the picked one #EBEBEB with a 0.67
    // #616161 edge).
    component OutlookBarButton: Rectangle {
        id: obb
        property string icon
        property color iconColor: primary ? "white" : enabledState ? theme.textStrong : theme.disabled
        property string label
        property string accessible: ""
        property bool chevron: false
        property bool primary: false
        property bool outlined: false
        property bool strong: false
        property bool radio: false
        property bool checked: false
        property bool enabledState: true
        signal clicked()
        readonly property real labelW: obbText.visible ? obbText.implicitWidth : 0
        readonly property bool big: outlined || primary
        width: big ? 12.67 + 20 + 6 + labelW + 12.67
            : !label && !chevron ? 32
            : 6.67 + 20 + (label ? 4 + labelW : 0) + (chevron ? 4 + 12 + 4.67 : 6.67)
        height: 31.33; radius: 4
        color: primary ? (obbh.hovered ? theme.brandHover : theme.brandFill)
            : radio && checked ? theme.pick("#EBEBEB", "#383838", "#1AEBFF")
            : outlined ? (obbh.hovered ? theme.rowHover : theme.surface)
            : obbh.hovered && enabledState ? theme.rowHover : "transparent"
        border.width: outlined || (radio && checked) ? 0.67 : 0
        border.color: radio ? theme.textSecondary : theme.stroke
        FluentIcon {
            x: obb.big ? 12.67 : !obb.label && !obb.chevron ? 6 : 6.67; anchors.verticalCenter: parent.verticalCenter
            name: obb.icon; size: 20; color: theme.onFill(obb, obb.iconColor)
        }
        Text {
            id: obbText
            visible: !!obb.label
            x: obb.big ? 12.67 + 20 + 6 : 6.67 + 20 + 4; anchors.verticalCenter: parent.verticalCenter
            text: obb.label; font.family: theme.font; font.pixelSize: 14; font.weight: obb.strong ? Font.DemiBold : Font.Normal
            color: theme.onFill(obb, obb.primary ? "white" : !obb.enabledState ? theme.disabled : obb.strong || (obb.radio && obb.checked) ? theme.text : theme.textStrong)
        }
        FluentIcon {
            visible: obb.chevron
            x: obb.width - 4.67 - 12; y: 10.33
            name: "chevron-down-12"; size: 12; color: theme.onFill(obb, obb.enabledState ? theme.textStrong : theme.disabled)
        }
        HoverHandler { id: obbh; enabled: obb.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: obb.enabledState; onTapped: obb.clicked() }
        Accessible.role: obb.radio ? Accessible.RadioButton : Accessible.Button
        Accessible.name: obb.accessible || obb.label
        Accessible.checkable: obb.radio
        Accessible.checked: obb.checked
    }
    // A command bar divider: 12.67 between its neighbours (4 + 4.67 + 4),
    // a 0.67 x 16 #D1D1D1 line.
    component ObSep: Item {
        width: 4.67; height: 31.33
        Rectangle { x: 2; anchors.verticalCenter: parent.verticalCenter; width: 0.67; height: 16; color: theme.stroke }
    }
    // The info bar's buttons (Outlook: 23 tall, 0.67 #D1D1D1 edge, radius
    // 4, 12 px #242424, padding 0 8).
    component InfoBarButton: Rectangle {
        id: ibb
        property string label
        signal clicked()
        width: ibbText.implicitWidth + 16; height: 23; radius: 4
        color: ibbh.hovered ? theme.rowHover : theme.surface
        border.width: 0.67; border.color: theme.stroke
        Text { id: ibbText; anchors.centerIn: parent; text: ibb.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(ibb, theme.text) }
        HoverHandler { id: ibbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ibb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ibb.label
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
