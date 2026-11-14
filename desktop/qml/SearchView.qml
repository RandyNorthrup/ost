import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// Teams' search results page (Enter in the title bar's search; measured on
// winpc 2026-11-10), right of the app bar on white:
// - tab pills 16 down from 12 in on the 692 column (32 tall, radius 16,
//   padding 0 12, 12 apart; #F5F5F5, the chosen one #E8EBFA with a brand
//   0.67 border): All, Messages, Files, People, Channels, Group chats, +3
//   (Meetings, Images); a #EBEBEB line under them;
// - the tab's filters (24 tall, 14 px #616161 with a 10 px chevron, 8
//   apart, 12 in): All In, Person, Date; Messages Type, In, Person, Date,
//   More; Files File Type, In, Person, Date; Group chats Person; Meetings
//   Person, Date; Images In, Person, Date; a line under them;
// - results on the 692 column (Files 760): section headings 14/700 with
//   "Send feedback 👍 👎" (14 #616161) on the right; cards white, radius
//   8, Fluent shadow 2, 16 apart:
//   - a message: its place (a 20 px picture, the chat's name or "team ›
//     channel", 12 #616161) over a line, then the sender's 28 px picture
//     with presence, name (14, the terms bold) and time (12), and the text
//     (14, the terms on #F9E2AE);
//   - a group chat (70.6): its 32 px picture, name (14, terms bold), the
//     last message's date (12 #424242) and its people (12);
//   - a channel (64): the team's 32 px square picture, the channel (14)
//     and team (12), Copy link;
//   - a file (Files, 760 wide): its type icon, name (terms bold), place,
//     who and when, and the summary;
//   - a meeting (75.3): a 40 px date box (day 14/600, month 10), subject
//     (terms bold), times (12), Chat (Teams meetings) or Edit (yours);
//   - an image (242.3 x 216.3): the picture over its sender, date and chat.
// Messages open where they were said; the terms are marked there.
Rectangle {
    id: root
    color: theme.surface
    property string query: ""
    property string tab: "all"
    /// Chats and teams (to name a result's place).
    property var chats: []
    property var teams: []
    property var members: []
    signal openChat(string id, string name, string messageId, var terms)
    signal openChannel(string id, string name, string messageId, string postId, var terms)
    signal openPerson(string mri, string name)
    signal openMeeting(var event)
    signal joinMeeting(string url)
    signal openChatWindow(string id, string name)
    signal tabChanged2(string tab)

    // The filters.
    property string kind: ""           // Type ▾ (Messages): chat / channel
    property var inPlace: null         // In ▾: {kind, thread, group, name}
    property var person: null          // Person ▾: {name, mail, mri, from}
    property string dateKey: ""
    property date customFrom: new Date()
    property date customTo: new Date()
    property bool mentions: false
    property bool attachment: false
    property bool hideBots: false
    property string fileType: ""
    // Files' Grid view / List view (Teams keeps the choice).
    property string fileLayout: backend.setting("searchResultLayout") === "grid" ? "grid" : "list"
    readonly property bool fileGrid: tab === "files" && fileLayout === "grid"
    function setFileLayout(l) {
        if (l === fileLayout) return
        fileLayout = l
        backend.setSetting("searchResultLayout", l)
        run()
    }
    property int generation: 0
    /// The result open in the preview pane (Teams' preview beside the
    /// results: 40% of the page).
    property var preview: null
    readonly property real previewWidth: preview ? Math.round(width * 0.4) : 0
    readonly property real resultsWidth: width - previewWidth
    readonly property string key: tab + "#" + query + "#" + generation
    readonly property var result: { try { const r = JSON.parse(backend.searchPageJson || "{}"); return r.key === key ? r : null } catch (e) { return null } }
    readonly property var page: result && result.page ? result.page : null
    readonly property var terms: page && page.terms && page.terms.length ? page.terms : query.split(/\s+/).filter(t => !!t)
    readonly property bool hasFilters: !!kind || !!inPlace || !!person || !!dateKey || mentions || attachment || hideBots || !!fileType

    readonly property var tabNames: ({ all: "All", messages: "Messages", files: "Files", people: "People", channels: "Channels", groupchats: "Group chats", meetings: "Meetings", images: "Images", communities: "Communities" })
    readonly property var mainTabs: ["all", "messages", "files", "people", "channels", "groupchats"]
    readonly property var moreTabs: ["meetings", "images", "communities"]
    // An overflow tab picked takes the last slot before +3, as in Teams.
    readonly property var shownTabs: moreTabs.indexOf(tab) >= 0 ? mainTabs.slice(0, 5).concat([tab]) : mainTabs
    readonly property var hiddenTabs: mainTabs.concat(moreTabs).filter(t => shownTabs.indexOf(t) < 0)
    readonly property var filterKeys: ({ all: ["in", "person", "date"], messages: ["type", "in", "person", "date", "more"], files: ["filetype", "in", "person", "date"],
                                         people: [], channels: [], groupchats: ["person"], meetings: ["person", "date"], images: ["in", "person", "date"] })[tab] || []

    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function range() {
        const t = dayStart(new Date())
        const add = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
        switch (dateKey) {
        case "today": return [t, add(t, 1)]
        case "yesterday": return [add(t, -1), t]
        case "week": { const s = add(t, -t.getDay()); return [s, add(s, 7)] }
        case "month": return [new Date(t.getFullYear(), t.getMonth(), 1), new Date(t.getFullYear(), t.getMonth() + 1, 1)]
        case "custom": return [dayStart(customFrom), add(dayStart(customTo), 1)]
        }
        return null
    }
    function filters() {
        const r = range()
        return {
            kind: kind,
            in_kind: inPlace ? inPlace.kind : "", in_thread: inPlace ? inPlace.thread || "" : "", in_group: inPlace ? inPlace.group || "" : "",
            person_mail: person ? person.mail : "", person_oid: person ? String(person.mri || "").split(":").pop() : "", person_from: !!(person && person.from),
            start: r ? r[0].toISOString() : "", end: r ? r[1].toISOString() : "",
            mentions: mentions, attachment: attachment, file_type: fileType, grid: fileGrid,
        }
    }
    function run() {
        preview = null
        generation++
        if (query) backend.searchPage(key, tab, query, JSON.stringify(filters()), 0)
        list.contentY = 0
    }
    function more() {
        if (!page || !result || result.loading) return
        const set = tab === "files" ? page.files : tab === "images" ? page.images : page.messages
        if (set && set.more) backend.searchPage(key, tab, query, JSON.stringify(filters()), set.hits.length)
    }
    function search(q, t) {
        query = q
        if (t && t !== tab) { tab = t; clearFilters(false) }
        run()
    }
    function setTab(t) { if (t === tab) return; tab = t; clearFilters(false); tabChanged2(t); run() }
    function clearFilters(rerun) {
        kind = ""; inPlace = null; person = null; dateKey = ""; mentions = false; attachment = false; hideBots = false; fileType = ""
        if (rerun) run()
    }

    // Names and places.
    function chatName(id) { const c = chats.find(c => c.id === id); return c ? c.name : "" }
    function channelOf(thread) {
        for (const t of teams) { const c = (t.channels || []).find(c => c.id === thread); if (c) return { team: t, channel: c } }
        return null
    }
    function when(iso) {
        const d = new Date(iso)
        if (isNaN(d)) return ""
        const days = Math.round((dayStart(new Date()) - dayStart(d)) / 86400000)
        const time = Qt.formatTime(d, "h:mm AP")
        if (days === 0) return time
        if (days === 1) return "Yesterday " + time
        if (days > 1 && days < 7) return Qt.formatDate(d, "dddd") + " " + time
        return d.getFullYear() === new Date().getFullYear() ? Qt.formatDate(d, "M/d") : Qt.formatDate(d, "M/d/yyyy")
    }
    function shortDate(iso) {
        const d = new Date(iso)
        if (isNaN(d)) return ""
        const days = Math.round((dayStart(new Date()) - dayStart(d)) / 86400000)
        return days === 0 ? Qt.formatTime(d, "h:mm AP") : d.getFullYear() === new Date().getFullYear() ? Qt.formatDate(d, "M/d") : Qt.formatDate(d, "M/d/yyyy")
    }
    function escaped(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function bold(t) { const re = theme.termPattern(terms); const e = escaped(t); return re ? e.replace(re, "$1<b>$2</b>") : e }
    function marked(t) { return theme.markTerms(escaped(t), terms) }
    function isMe(mri) { return (mri || "").toLowerCase() === (backend.userMri || "").toLowerCase() }
    function presenceOf(mri) { const m = members.find(m => (m.mri || "").toLowerCase() === (mri || "").toLowerCase()); return m ? m.presence || "" : "" }
    function feedback(kind) {
        backend.requestFeedback(kind, "Search", "Search: “" + query + "” (" + tabNames[tab] + (hasFilters ? ", filtered" : "") + ")")
    }
    function openHit(h) {
        const ch = channelOf(h.thread)
        if (ch) root.openChannel(h.thread, ch.channel.name, h.id, h.parent_id || "", terms)
        else root.openChat(h.thread, chatName(h.thread) || h.subject || "", h.id, terms)
    }
    FontMetrics { id: fm14; font.family: theme.font; font.pixelSize: 14 }

    // Tabs.
    Row {
        id: tabRow
        x: Math.max(16, (root.resultsWidth - 692) / 2); y: 16.2; spacing: 12
        Repeater {
            model: root.shownTabs.concat(root.hiddenTabs.length ? ["+"] : [])
            Rectangle {
                id: pill
                required property string modelData
                readonly property bool chosen: modelData === root.tab
                height: 32; radius: 16
                width: label.implicitWidth + 24
                color: chosen ? theme.brandTint : ph.hovered ? theme.pick("#EBEBEB", "#3D3D3D") : theme.pick("#F5F5F5", "#2E2E2E")
                border.width: 0.67; border.color: chosen ? theme.brand : color
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: pill.modelData === "+" ? "+" + root.hiddenTabs.length : root.tabNames[pill.modelData]
                    font.family: theme.font; font.pixelSize: 14; font.weight: pill.chosen ? Font.DemiBold : Font.Normal; color: theme.text
                }
                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pill.modelData === "+" ? overflow.open() : root.setTab(pill.modelData) }
                Accessible.role: Accessible.PageTab
                Accessible.name: label.text
                Accessible.selected: chosen
                MenuPopup {
                    id: overflow
                    y: parent.height + 4
                    items: root.hiddenTabs.map(t => ({ label: root.tabNames[t] }))
                    onPicked: i => { close(); root.setTab(root.hiddenTabs[i]) }
                }
            }
        }
    }
    Rectangle { y: 60.7; width: root.resultsWidth; height: 0.67; color: theme.pick("#EBEBEB", "#3D3D3D") }

    // Filters.
    Item {
        id: filterRow
        visible: root.filterKeys.length > 0
        x: column.x; y: 61; width: column.width; height: visible ? 40 : 0
        component FilterButton: Rectangle {
            id: fb
            property string label
            property bool on: false
            signal clicked()
            signal cleared()
            height: 24; radius: 4
            width: fbText.implicitWidth + 12 + 4 + 10 + 12 + (on ? 20 : 0)
            color: fbh.hovered ? theme.hover : "transparent"
            Text { id: fbText; x: 12; anchors.verticalCenter: parent.verticalCenter; text: fb.label; font.family: theme.font; font.pixelSize: 14; color: fb.on ? theme.text : theme.textSecondary; font.weight: fb.on ? Font.DemiBold : Font.Normal }
            FluentIcon { visible: !fb.on; x: fbText.x + fbText.implicitWidth + 9; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 10; color: theme.textSecondary }
            HoverHandler { id: fbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: fb.clicked() }
            Rectangle {
                visible: fb.on
                x: fbText.x + fbText.implicitWidth + 6; anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 4
                color: fxh.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 12; color: theme.textSecondary }
                HoverHandler { id: fxh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: fb.cleared() }
                Accessible.role: Accessible.Button
                Accessible.name: "Clear selection"
            }
            Accessible.role: Accessible.Button
            Accessible.name: fb.label + " filter"
        }
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Repeater {
                model: root.filterKeys
                FilterButton {
                    id: fbtn
                    required property string modelData
                    on: modelData === "type" ? !!root.kind : modelData === "in" ? !!root.inPlace : modelData === "person" ? !!root.person
                      : modelData === "date" ? !!root.dateKey : modelData === "filetype" ? !!root.fileType : (root.mentions || root.attachment || root.hideBots)
                    label: modelData === "type" ? (root.kind ? (root.kind === "chat" ? "Chat" : "Channel") : "Type")
                         : modelData === "in" ? (root.inPlace ? root.inPlace.name : "In")
                         : modelData === "person" ? (root.person ? (root.person.from ? "From " : "With ") + root.person.name : "Person")
                         : modelData === "date" ? (root.dateKey ? root.dateLabel() : "Date")
                         : modelData === "filetype" ? (root.fileType ? root.fileTypeNames[root.fileType] : "File Type")
                         : ((root.mentions || root.attachment || root.hideBots) ? "More (" + [root.mentions, root.attachment, root.hideBots].filter(x => x).length + ")" : "More")
                    onClicked: {
                        const p = fbtn.mapToItem(root, 0, fbtn.height + 4)
                        if (modelData === "type") { typeMenu.x = p.x; typeMenu.y = p.y; typeMenu.open() }
                        else if (modelData === "filetype") { fileTypeMenu.x = p.x; fileTypeMenu.y = p.y; fileTypeMenu.open() }
                        else if (modelData === "in") { inPop.x = p.x; inPop.y = p.y; inPop.open() }
                        else if (modelData === "person") { personPop.x = p.x; personPop.y = p.y; personPop.open() }
                        else if (modelData === "date") { datePop.x = p.x; datePop.y = p.y; datePop.open() }
                        else { morePop.x = p.x; morePop.y = p.y; morePop.open() }
                    }
                    onCleared: {
                        if (modelData === "type") root.kind = ""
                        else if (modelData === "in") root.inPlace = null
                        else if (modelData === "person") root.person = null
                        else if (modelData === "date") root.dateKey = ""
                        else if (modelData === "filetype") root.fileType = ""
                        else { root.mentions = false; root.attachment = false; root.hideBots = false }
                        root.run()
                    }
                }
            }
            Text {
                visible: root.hasFilters
                height: 24; verticalAlignment: Text.AlignVCenter
                text: "Clear all"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                font.underline: cah.hovered
                HoverHandler { id: cah; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.clearFilters(true) }
                Accessible.role: Accessible.Button
                Accessible.name: "Clear all"
            }
        }
        Rectangle { y: 40.7; x: -column.x; width: root.resultsWidth; height: 0.67; color: theme.pick("#EBEBEB", "#3D3D3D") }
        // Files' Grid view / List view (Teams: 30.67 + 32 x 31.33 outline
        // buttons sharing a #D1D1D1 edge, radius 4 outside, 52.5 in from
        // the list's right; the chosen one's icon filled in brand colour).
        Row {
            visible: root.tab === "files"
            x: parent.width - 52.5 - width; y: 4.33
            Repeater {
                model: [{ key: "grid", label: "Grid view", icon: "grid-20" }, { key: "list", label: "List view", icon: "text-align-left-20" }]
                Item {
                    id: lb
                    required property var modelData
                    required property int index
                    readonly property bool on: root.fileLayout === modelData.key
                    width: index === 0 ? 30.67 : 32; height: 31.33
                    Rectangle {
                        // Rounded outside only: the inner corners hide under the clip.
                        x: lb.index === 0 ? 0 : -6; width: parent.width + 6; height: parent.height; radius: 4
                        color: lbh.hovered ? theme.hover : "transparent"
                        border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666")
                    }
                    clip: true
                    Rectangle { visible: lb.index === 1; width: 0.67; height: parent.height; color: theme.pick("#D1D1D1", "#666666") }
                    FluentIcon {
                        anchors.centerIn: parent; size: 16
                        name: lb.modelData.icon + (lb.on ? "-filled" : "")
                        color: lb.on ? theme.brandForeground1 : theme.textStrong
                    }
                    HoverHandler { id: lbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.setFileLayout(lb.modelData.key) }
                    ToolTip.visible: lbh.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.label
                    Accessible.checked: on
                }
            }
        }
    }
    readonly property var fileTypeKeys: ["excel", "images", "loop", "onenote", "pdf", "powerpoint", "text", "word"]
    readonly property var fileTypeNames: ({ excel: "Excel", images: "Images", loop: "Loop", onenote: "OneNote", pdf: "PDF", powerpoint: "PowerPoint", text: "Text file", word: "Word" })
    function dateLabel() {
        switch (dateKey) {
        case "today": return "Today"
        case "yesterday": return "Yesterday"
        case "week": return "This week"
        case "month": return "This month"
        case "custom": return Qt.formatDate(customFrom, "M/d/yyyy") + " - " + Qt.formatDate(customTo, "M/d/yyyy")
        }
        return ""
    }
    RadioMenu {
        id: typeMenu
        items: [{ label: "Chat", checked: root.kind === "chat" }, { label: "Channel", checked: root.kind === "channel" }]
        onPicked: i => { close(); root.kind = i === 0 ? "chat" : "channel"; root.run() }
    }
    MenuPopup {
        id: fileTypeMenu
        perItemIcons: true
        items: root.fileTypeKeys.map(k => ({ label: root.fileTypeNames[k], icon: ({ excel: "ft-xlsx-20", images: "ft-photo-20", loop: "ft-loop-20", onenote: "ft-one-20", pdf: "ft-pdf-20", powerpoint: "ft-pptx-20", text: "ft-txt-20", word: "ft-docx-20" })[k] }))
        onPicked: i => { close(); root.fileType = root.fileTypeKeys[i]; root.run() }
    }
    // In ▾ (350 wide): "Filter by Group chats, Teams and Channels" and the
    // matches, grouped.
    Popup {
        id: inPop
        width: 350; padding: 0
        height: 67 + Math.min(320, inList.contentHeight + (inList.count ? 8 : 0))
        onOpened: { inField.text = ""; inField.forceActiveFocus() }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        readonly property var items: {
            try {
                const r = JSON.parse(backend.searchInJson || "{}")
                if (!inField.text.trim() || r.keyword !== inField.text.trim()) return []
                return (r.groups || []).reduce((a, g) => a.concat(g.items || []), [])
            } catch (e) { return [] }
        }
        Rectangle {
            x: 12.7; y: 16.7; width: parent.width - 25.4; height: 33.3; radius: 4
            color: theme.pick("#F5F5F5", "#141414")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: inField.activeFocus ? 2 : 0.67; color: inField.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: inField
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                onTextChanged: inTimer.restart()
                Keys.onEscapePressed: inPop.close()
                Text { visible: !inField.text; text: "Filter by Group chats, Teams and Channels"; font: inField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Filter by Group chats, Teams and Channels"
            }
            Timer { id: inTimer; interval: 250; onTriggered: backend.searchInSuggest(inField.text) }
        }
        ListView {
            id: inList
            x: 4; y: 58; width: parent.width - 8; height: parent.height - y - 4
            clip: true
            model: inPop.items
            delegate: Rectangle {
                required property var modelData
                width: inList.width; height: 48; radius: 4
                color: ih.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                Avatar {
                    x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32
                    name: parent.modelData.kind === "chat" ? parent.modelData.name : parent.modelData.team || parent.modelData.name
                    square: parent.modelData.kind !== "chat"; squareRadius: 4
                    group: parent.modelData.kind === "chat"
                    photoId: parent.modelData.kind === "chat" ? "" : (parent.modelData.group ? "team:" + parent.modelData.group : "")
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 64
                    Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { visible: !!parent.parent.modelData.team && parent.parent.modelData.kind === "channel"; width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.team || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                }
                HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.inPlace = { kind: parent.modelData.kind, thread: parent.modelData.thread, group: parent.modelData.group, name: parent.modelData.name }; inPop.close(); root.run() } }
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name
            }
        }
    }
    // Person ▾ (350 wide): "Filter by person", With / From, Apply.
    Popup {
        id: personPop
        width: 350; padding: 0
        height: 219 + (picked ? 0 : Math.min(240, people.length * 50))
        property var picked: null
        property bool from: false
        onOpened: { picked = root.person; from = !!(root.person && root.person.from); pField.text = ""; pField.forceActiveFocus() }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        readonly property var people: { try { return pField.text.trim().length >= 2 ? JSON.parse(backend.peopleJson || "[]") : [] } catch (e) { return [] } }
        Rectangle {
            x: 12.7; y: 16.7; width: parent.width - 25.4; height: 33.3; radius: 4
            color: theme.pick("#F5F5F5", "#141414")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: pField.activeFocus ? 2 : 0.67; color: pField.activeFocus ? theme.brand : theme.textSecondary }
            Rectangle {
                id: pickedChip
                visible: !!personPop.picked
                x: 6; anchors.verticalCenter: parent.verticalCenter
                height: 24; radius: 4; width: pcText.implicitWidth + 36
                color: theme.pick("#EBEBEB", "#3D3D3D")
                Text { id: pcText; x: 8; anchors.verticalCenter: parent.verticalCenter; text: personPop.picked ? personPop.picked.name : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-20"; size: 12; color: theme.textSecondary
                    TapHandler { onTapped: personPop.picked = null } }
            }
            TextInput {
                id: pField
                x: pickedChip.visible ? pickedChip.x + pickedChip.width + 6 : 12; width: parent.width - x - 12; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                onTextChanged: backend.searchPeopleWithMe(text)
                Keys.onEscapePressed: personPop.close()
                Text { visible: !pField.text && !personPop.picked; text: "Filter by person"; font: pField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Filter by person"
            }
        }
        Column {
            visible: !personPop.picked && personPop.people.length > 0
            x: 4; y: 54; width: parent.width - 8
            Repeater {
                model: personPop.people.slice(0, 5)
                Rectangle {
                    required property var modelData
                    width: parent.width; height: 50; radius: 4
                    color: pph.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: parent.modelData.name || ""; photoId: parent.modelData.mri || "" }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 64
                        Text { width: parent.width; elide: Text.ElideRight; text: (parent.parent.modelData.name || "") + (root.isMe(parent.parent.modelData.mri) ? " (You)" : ""); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.mail || parent.parent.modelData.upn || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    }
                    HoverHandler { id: pph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { personPop.picked = { name: parent.modelData.name, mail: parent.modelData.mail || parent.modelData.upn || "", mri: parent.modelData.mri || ("8:orgid:" + (parent.modelData.id || "")) }; pField.text = "" } }
                }
            }
        }
        Column {
            y: personPop.picked || !personPop.people.length ? 62 : 62 + Math.min(240, personPop.people.length * 50)
            x: 12.7; spacing: 6
            Repeater {
                model: [{ label: "With", hint: "Shows all results related to a person", from: false }, { label: "From", hint: "Shows results sent by a person", from: true }]
                Item {
                    required property var modelData
                    width: 320; height: 40
                    Rectangle {
                        y: 4; width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
                        border.color: personPop.from === parent.modelData.from ? theme.brand : theme.textSecondary
                        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand; visible: personPop.from === parent.parent.modelData.from }
                    }
                    Text { x: 26; y: 0; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { x: 26; y: 20; text: parent.modelData.hint; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    TapHandler { onTapped: personPop.from = parent.modelData.from }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.label
                    Accessible.checked: personPop.from === modelData.from
                }
            }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12.7; anchors.bottom: parent.bottom; anchors.bottomMargin: 12.7
            width: 96; height: 32; radius: 4
            readonly property bool usable: !!personPop.picked
            color: usable ? (aph.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E")
            Text { anchors.centerIn: parent; text: "Apply"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.usable ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: aph; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.usable; onTapped: { root.person = Object.assign({}, personPop.picked, { from: personPop.from }); personPop.close(); root.run() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Apply"
        }
    }
    // Date ▾ (302 wide): "Date", the four ranges, From / To, Clear and Apply.
    Popup {
        id: datePop
        width: 302; padding: 0; height: 372
        property bool fromSet: false
        property date fromDate: new Date()
        property date toDate: new Date()
        onAboutToShow: { fromSet = root.dateKey === "custom"; fromDate = fromSet ? root.customFrom : new Date(); toDate = fromSet ? root.customTo : new Date() }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text { x: 16; y: 14; text: "Date"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        Column {
            x: 1; y: 40; width: parent.width - 2
            Repeater {
                model: [{ k: "today", l: "Today" }, { k: "yesterday", l: "Yesterday" }, { k: "week", l: "This week" }, { k: "month", l: "This month" }]
                Rectangle {
                    required property var modelData
                    width: parent.width; height: 32
                    color: dh.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : root.dateKey === modelData.k ? theme.pick("#EBEBEB", "#383838") : "transparent"
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.l; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.dateKey = parent.modelData.k; datePop.close(); root.run() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.l
                }
            }
        }
        Rectangle { x: 1; y: 176; width: parent.width - 2; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
        Text { x: 16; y: 190; text: "From"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        DatePickerField {
            x: 16; y: 210; width: parent.width - 32
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            empty: !datePop.fromSet; placeholder: "Select a date"
            date: datePop.fromDate; maxDate: datePop.toDate
            onPicked: d => { datePop.fromDate = d; datePop.fromSet = true }
        }
        Text { x: 16; y: 254; text: "To"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        DatePickerField {
            x: 16; y: 274; width: parent.width - 32
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            date: datePop.toDate; minDate: datePop.fromSet ? datePop.fromDate : new Date(1900, 0, 1); maxDate: new Date()
            onPicked: d => datePop.toDate = d
        }
        Rectangle {
            x: parent.width - 16 - 96 - 8 - 54.7; y: 324; width: 54.7; height: 32; radius: 4
            readonly property bool usable: datePop.fromSet || !!root.dateKey
            color: usable && dch.hovered ? theme.hover : "transparent"
            Text { anchors.centerIn: parent; text: "Clear"; font.family: theme.font; font.pixelSize: 14; color: parent.usable ? theme.text : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: dch; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.usable; onTapped: { datePop.fromSet = false; if (root.dateKey) { root.dateKey = ""; datePop.close(); root.run() } } }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear"
        }
        Rectangle {
            x: parent.width - 16 - 96; y: 324; width: 96; height: 32; radius: 4
            readonly property bool usable: datePop.fromSet
            color: usable ? (dah.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E")
            Text { anchors.centerIn: parent; text: "Apply"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.usable ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: dah; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.usable; onTapped: { root.customFrom = datePop.fromDate; root.customTo = datePop.toDate; root.dateKey = "custom"; datePop.close(); root.run() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Apply"
        }
    }
    // More ▾ (398 x 202): "More filters": @mentions me, Has attachment, Hide
    // apps & bots; Clear and Apply.
    Popup {
        id: morePop
        width: 398; height: 202; padding: 0
        property bool m: false
        property bool a: false
        property bool b: false
        onAboutToShow: { m = root.mentions; a = root.attachment; b = root.hideBots }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Text { x: 20; y: 18; text: "More filters"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        component Check: Item {
            id: ck
            property string label
            property bool checked
            signal toggled()
            width: 170; height: 32
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 2
                color: ck.checked ? theme.brand : "transparent"; border.width: 1; border.color: ck.checked ? theme.brand : theme.textSecondary
                FluentIcon { anchors.centerIn: parent; visible: ck.checked; name: "checkmark-12"; size: 12; color: "#FFFFFF" }
            }
            Text { x: 26; anchors.verticalCenter: parent.verticalCenter; text: ck.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            TapHandler { onTapped: ck.toggled() }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            Accessible.role: Accessible.CheckBox
            Accessible.name: ck.label
            Accessible.checked: ck.checked
        }
        Grid {
            x: 20; y: 54; columns: 2; columnSpacing: 20; rowSpacing: 0
            Check { label: "@mentions me"; checked: morePop.m; onToggled: morePop.m = !morePop.m }
            Check { label: "Has attachment"; checked: morePop.a; onToggled: morePop.a = !morePop.a }
            Check { label: "Hide apps & bots"; checked: morePop.b; onToggled: morePop.b = !morePop.b }
        }
        Rectangle {
            x: parent.width - 20 - 96 - 8 - 60; y: 150; width: 60; height: 32; radius: 4
            color: mch.hovered ? theme.hover : "transparent"
            Text { anchors.centerIn: parent; text: "Clear"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            HoverHandler { id: mch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { morePop.m = false; morePop.a = false; morePop.b = false } }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear"
        }
        Rectangle {
            x: parent.width - 20 - 96; y: 150; width: 96; height: 32; radius: 4
            color: mah.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Apply"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
            HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.mentions = morePop.m; root.attachment = morePop.a; root.hideBots = morePop.b; morePop.close(); root.run() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Apply"
        }
    }

    // The results.
    readonly property real columnWidth: tab === "files" ? 760 : 692
    // Teams' file grid (760, centred past a 62 margin and the same 112
    // padding, then 54 left) starts at width / 2 - 323: 34 right of the list.
    readonly property real gridShift: fileGrid ? Math.max(0, Math.min(34, resultsWidth - column.x - column.width - 16)) : 0
    Item {
        id: column
        // Files: Teams centres its 816 list (760 + 32 / 24 padding) in the
        // page past a 112 left padding and the 14 px scrollbar, then moves
        // it 30 left: the cards start at width / 2 - 357.
        x: root.tab === "files" ? Math.max(16, root.resultsWidth / 2 - 357) : Math.max(16, (root.resultsWidth - root.columnWidth) / 2)
        width: Math.min(root.columnWidth, root.resultsWidth - 32)
        y: filterRow.visible ? 101.7 : 61.4; height: root.height - y
    }
    // Messages without apps' and bots' (Hide apps & bots, the page's own).
    function visibleMessages(hits) { return hideBots ? (hits || []).filter(h => !String(h.sender_mri || "").startsWith("28:")) : (hits || []) }
    // What the list shows: [{t: "heading"|"message"|"chat"|"channel"|"file"|"person"|"event"|"image-row"|"more"|"none"|"chatrow"|"channelrow", …}].
    readonly property var rows: {
        const out = []
        if (!page) return out
        const msgs = visibleMessages(page.messages ? page.messages.hits : [])
        const heading = (title, feedbackToo) => out.push({ t: "heading", title: title, feedback: feedbackToo })
        if (tab === "all") {
            let first = true
            for (const s of (page.order && page.order.length ? page.order : ["messages", "groupchats", "channels", "files", "meetings", "people"])) {
                if (s === "messages" && msgs.length) { heading("Messages", first); for (const h of msgs.slice(0, 8)) out.push({ t: "message", h: h }); out.push({ t: "more", label: "More messages", tab: "messages" }); first = false }
                else if (s === "groupchats" && page.chats.length) { heading("Group chats", first); out.push({ t: "chatrow", items: page.chats.slice(0, 2) }); out.push({ t: "more", label: "More group chats", tab: "groupchats" }); first = false }
                else if (s === "channels" && page.channels.length) { heading("Channels", first); out.push({ t: "channelrow", items: page.channels.slice(0, 3) }); out.push({ t: "more", label: "More channels", tab: "channels" }); first = false }
                else if (s === "files" && page.files && page.files.hits.length) { heading("Files", first); for (const f of page.files.hits.slice(0, 3)) out.push({ t: "file", h: f }); out.push({ t: "more", label: "More files", tab: "files" }); first = false }
                else if (s === "meetings" && page.events.length) { heading("Meetings", first); for (const e of page.events.slice(0, 3)) out.push({ t: "event", e: e }); out.push({ t: "more", label: "More meetings", tab: "meetings" }); first = false }
                else if (s === "people" && page.people.length) { heading("People", first); for (const p of page.people.slice(0, 3)) out.push({ t: "person", p: p }); out.push({ t: "more", label: "More people", tab: "people" }); first = false }
            }
        } else if (tab === "messages") {
            if (msgs.length) heading("Top results", true)
            for (const h of msgs) out.push({ t: "message", h: h })
        } else if (tab === "files" && fileGrid) {
            const hits = page.files ? page.files.hits : []
            if (hits.length) out.push({ t: "grid-heading" })
            for (let i = 0; i < hits.length; i += 3) out.push({ t: "file-grid", items: hits.slice(i, i + 3) })
        } else if (tab === "files") {
            if (page.files && page.files.hits.length) heading("", true)
            for (const f of page.files ? page.files.hits : []) out.push({ t: "file", h: f })
        } else if (tab === "people") {
            if (page.people.length) heading("", true)
            for (const p of page.people) out.push({ t: "person", p: p })
        } else if (tab === "channels") {
            if (page.channels.length) heading("", true)
            for (const c of page.channels) out.push({ t: "channel", c: c })
        } else if (tab === "groupchats") {
            if (page.chats.length) heading("", true)
            for (const c of page.chats) out.push({ t: "chat", c: c })
        } else if (tab === "meetings") {
            if (page.events.length) heading("", true)
            for (const e of page.events) out.push({ t: "event", e: e })
        } else if (tab === "communities") {
            const cs = page.communities || []
            if (cs.length) heading("", true)
            for (const c of cs) out.push({ t: "community", c: c })
        } else if (tab === "images") {
            const imgs = page.images ? page.images.hits : []
            if (imgs.length) heading("", true)
            for (let i = 0; i < imgs.length; i += 4) out.push({ t: "image-row", items: imgs.slice(i, i + 4) })
        }
        if (!out.length && result && !result.loading) out.push({ t: "none" })
        return out
    }

    ListView {
        id: list
        x: column.x - 16; width: column.width + 32 + root.gridShift
        y: column.y; height: column.height
        clip: true
        spacing: 0
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onContentYChanged: if (contentY + height > contentHeight - 300) root.more()
        header: Item { width: 1; height: 20 }
        footer: Item {
            width: list.width; height: root.result && root.result.loading ? 60 : 24
            BusyIndicator { anchors.centerIn: parent; width: 28; height: 28; running: !!root.result && root.result.loading; visible: running }
        }
        delegate: Loader {
            id: rowLoader
            required property var modelData
            width: list.width
            sourceComponent: ({ heading: headingRow, message: messageCard, chat: chatCard, channel: channelCard, file: fileCard, person: personCard,
                                event: eventCard, more: moreLink, none: noneRow, chatrow: chatRowCards, channelrow: channelRowCards, "image-row": imageRow,
                                "grid-heading": gridHeading, "file-grid": fileGridRow, community: communityCard })[modelData.t]
            property var row: modelData
        }
    }

    SearchPreview {
        id: previewPane
        visible: !!root.preview
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: root.previewWidth
        hit: root.preview
        terms: root.terms
        place: root.preview ? root.channelOf(root.preview.thread) : null
        chatName: root.preview ? (String(root.preview.thread).startsWith("48:") ? backend.userName + " (You)" : root.chatName(root.preview.thread) || root.preview.sender_name || "") : ""
        onClosed: root.preview = null
        onGoTo: { const h = root.preview; root.preview = null; root.openHit(h) }
        onPopOut: {
            const h = root.preview
            const ch = root.channelOf(h.thread)
            root.openChatWindow(h.thread, ch ? ch.channel.name : root.chatName(h.thread))
        }
    }

    // Send feedback 👍 👎 (14 px #616161; the thumbs 16, 8 apart).
    component FeedbackThumbs: Row {
        property int textSize: 14
        spacing: 8
        Text { height: 20; verticalAlignment: Text.AlignVCenter; text: "Send feedback"; font.family: theme.font; font.pixelSize: parent.textSize; color: theme.textSecondary }
        Repeater {
            model: [{ icon: "thumb-like-20", name: "This was helpful", kind: "compliment" }, { icon: "thumb-dislike-20", name: "Didn't help", kind: "problem" }]
            Item {
                required property var modelData
                width: 16; height: 20
                FluentIcon { y: 2; size: 16; name: parent.modelData.icon; color: tth.hovered ? theme.brand : theme.textStrong }
                HoverHandler { id: tth; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.feedback(parent.modelData.kind) }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
            }
        }
    }
    // A white card (radius 8, Fluent shadow 2).
    component Card: FluentSurface {
        x: 16; width: list.width - 32
        depth: 2; radius: 8; color: theme.surface
    }
    // A 32 px icon button (Copy link, Open chat in new window, Reply).
    component CardAction: Rectangle {
        id: ca
        property string icon
        property string label
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: cah2.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ca.icon; size: 18; color: theme.textStrong }
        HoverHandler { id: cah2; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ca.clicked() }
        ToolTip.visible: cah2.hovered; ToolTip.delay: 500; ToolTip.text: ca.label
        Accessible.role: Accessible.Button
        Accessible.name: ca.label
    }

    Component {
        id: headingRow
        Item {
            // Files' feedback row is 28 (20 + 8), the cards right under it.
            height: !row.title && root.tab === "files" ? 28 : 48
            Text {
                visible: !!row.title
                x: 16; y: 0; height: 20
                text: row.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading
            }
            FeedbackThumbs { visible: row.feedback; anchors.right: parent.right; anchors.rightMargin: 16 }
        }
    }
    Component {
        id: moreLink
        Item {
            height: 56
            Text {
                x: 16; y: 4
                text: row.label; font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                font.underline: mlh.hovered
                HoverHandler { id: mlh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.setTab(row.tab) }
                Accessible.role: Accessible.Link
                Accessible.name: row.label
            }
        }
    }
    Component {
        id: noneRow
        Item {
            height: 420
            Image { anchors.horizontalCenter: parent.horizontalCenter; y: 40; width: 220; height: 220; sourceSize: Qt.size(440, 440); source: "../assets/illustrations/search-exclamation-l-standard.svg" }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: 270; width: 300
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: root.result && root.result.error ? "Something went wrong" : "We couldn't find any results for '" + root.query + "'"
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: 340; width: 360
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: root.result && root.result.error ? root.result.error : "Check for spelling or try searching for another term"
                font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
        }
    }
    // A message (Teams' search card, 116 tall for a line of text).
    Component {
        id: messageCard
        Item {
            id: mc
            readonly property var h: row.h
            readonly property var place: root.channelOf(h.thread)
            readonly property bool notes: String(h.thread).startsWith("48:")
            readonly property bool posted: !!place && (!h.parent_id || h.parent_id === h.id)
            height: card.height + 16
            HoverHandler { id: mch2 }
            Card {
                id: card
                height: 80 + mtext.height
                color: root.preview && root.preview.id === mc.h.id ? theme.pick("#FAFAFA", "#2E2E2E") : theme.surface
                // Its place.
                Avatar {
                    x: 20; y: 16; size: 20
                    name: mc.place ? mc.place.team.name : mc.notes ? backend.userName : (root.chatName(mc.h.thread) || mc.h.sender_name || "")
                    square: !!mc.place; squareRadius: 4
                    photoId: mc.place ? "team:" + mc.place.team.id : mc.notes ? (backend.userMri || "") : ""
                    group: !mc.place && !mc.notes && String(mc.h.thread).indexOf("@thread") > 0
                }
                Text {
                    x: 52; y: 17; width: parent.width - 52 - 16 - (mch2.hovered ? 220 : 0); height: 17.1
                    textFormat: Text.StyledText; elide: Text.ElideRight
                    text: mc.place ? root.bold(mc.place.team.name) + " &nbsp;›&nbsp; " + root.bold(mc.place.channel.name)
                        : mc.notes ? root.escaped(backend.userName) + " (You)" : root.bold(root.chatName(mc.h.thread) || mc.h.sender_name || "")
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                }
                Row {
                    visible: mch2.hovered
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 10
                    spacing: 6
                    FeedbackThumbs { textSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 1; height: 14; anchors.verticalCenter: parent.verticalCenter; color: theme.stroke }
                    CardAction { icon: mc.place ? "chat-20" : "arrow-reply-20"; label: mc.place ? "Reply in thread" : "Reply to this message"; onClicked: root.preview = mc.h }
                    CardAction {
                        icon: "open-window-20"; label: "Open chat in new window"
                        onClicked: root.openChatWindow(mc.h.thread, mc.place ? mc.place.channel.name : root.chatName(mc.h.thread))
                    }
                }
                Rectangle { x: 16; y: 52; width: parent.width - 32; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
                Avatar {
                    x: 16; y: 56
                    size: 28
                    name: mc.h.sender_name || ""
                    photoId: mc.h.sender_mri || ""
                    presence: root.presenceOf(mc.h.sender_mri)
                }
                Text {
                    id: who
                    x: 52; y: 56; height: 20
                    textFormat: Text.StyledText
                    text: root.bold(mc.h.sender_name || "") + (root.isMe(mc.h.sender_mri) ? " (You)" : "")
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Text { x: who.x + who.implicitWidth + 12; y: 57.4; text: root.when(mc.h.time); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                Text {
                    id: mtext
                    x: 52; y: 80; width: parent.width - 52 - 16
                    textFormat: Text.RichText; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    text: root.marked(mc.h.text || "")
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                TapHandler { onTapped: root.preview = mc.h }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: "Message from " + (h.sender_name || "") + ". " + (h.text || "")
        }
    }
    // A group chat row (Group chats tab: 70.6 tall).
    Component {
        id: chatCard
        Item {
            readonly property var c: row.c
            height: 70.6 + 16
            Card {
                height: 70.6
                Avatar { x: 16; y: 16; size: 32; name: parent.parent.c.name; group: true; meeting: String(parent.parent.c.thread).indexOf("meeting_") >= 0 }
                Text { x: 60; y: 15; width: parent.width - 60 - 120; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.c.name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 60; y: 38.3; width: parent.width - 60 - 120; elide: Text.ElideRight; text: root.membersLine(parent.parent.c); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                Text { anchors.right: parent.right; anchors.rightMargin: 17; y: 16; text: root.shortDate(parent.parent.c.last_message); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                TapHandler { onTapped: root.openChat(parent.parent.c.thread, parent.parent.c.name, "", []) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: "Group chat " + c.name
        }
    }
    function teamGroupOf(thread) {
        const t = teams.find(t => t.id === thread || (t.channels || []).some(c => c.id === thread))
        return t && t.group_id ? "team:" + t.group_id : t ? "team:" + t.id : ""
    }
    function membersLine(c) {
        const others = (c.members || []).filter(n => n !== backend.userName)
        if (!others.length) return "You"
        const first = others.map(n => n.split(" ")[0])
        return first.length === 1 ? "You and " + first[0] : "You, " + first.slice(0, -1).join(", ") + " and " + first[first.length - 1]
    }
    // A channel row (Channels tab: 64 tall).
    // A Viva Engage community (Teams' Communities tab; the service's
    // CommunitySearchTeams). The test tenant has none, so this follows the
    // channel card: the community's picture, its name (the match bold) and
    // its description; it opens in Viva Engage on the web.
    Component {
        id: communityCard
        Item {
            readonly property var c: row.c
            height: 64 + 16
            Card {
                height: 64
                Avatar {
                    x: 16; y: 16; size: 32; square: true; squareRadius: 4
                    name: parent.parent.c.name
                    visible: !parent.parent.c.avatar
                }
                Image {
                    visible: !!parent.parent.c.avatar
                    x: 16; y: 16; width: 32; height: 32
                    source: { backend.emoticonsVersion; const a = parent.parent.c.avatar; return a ? backend.cardImage(a.replace("{width}", "64").replace("{height}", "64")) : "" }
                    fillMode: Image.PreserveAspectCrop
                    RoundedCorners { anchors.fill: parent; radius: 4; background: theme.surface }
                }
                Text { x: 60; y: 11.3; width: parent.width - 76; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.c.name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 60; y: 32; width: parent.width - 76; elide: Text.ElideRight; text: parent.parent.c.description || (parent.parent.c.privacy === "PRIVATE" ? "Private community" : "Public community"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                TapHandler { onTapped: Qt.openUrlExternally("https://web.yammer.com/main/groups/" + encodeURIComponent(parent.parent.c.id)) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: c.name + " community"
        }
    }
    Component {
        id: channelCard
        Item {
            readonly property var c: row.c
            height: 64 + 16
            HoverHandler { id: chh }
            Card {
                height: 64
                Avatar { x: 16; y: 16; size: 32; square: true; squareRadius: 4; name: parent.parent.c.team || parent.parent.c.name; photoId: parent.parent.c.group ? "team:" + parent.parent.c.group : root.teamGroupOf(parent.parent.c.thread) }
                Text { x: 60; y: 11.3; width: parent.width - 60 - 90; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.c.name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 60; y: 32; width: parent.width - 60 - 90; elide: Text.ElideRight; text: parent.parent.c.team; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                Row {
                    visible: chh.hovered
                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    CardAction { icon: "link-20"; label: "Copy link"; onClicked: backend.copyText("https://teams.microsoft.com/l/channel/" + encodeURIComponent(parent.parent.parent.parent.c.thread) + "/" + encodeURIComponent(parent.parent.parent.parent.c.name) + "?groupId=" + parent.parent.parent.parent.c.group) }
                    CardAction { icon: "open-window-20"; label: "Open chat in new window"; onClicked: root.openChatWindow(parent.parent.parent.parent.c.thread, parent.parent.parent.parent.c.name) }
                }
                TapHandler { onTapped: root.openChannel(parent.parent.c.thread, parent.parent.c.name, "", "", []) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: c.name + " channel in " + c.team + " team"
        }
    }
    // All: group chats and channels side by side (294 x 82, 8 apart).
    Component {
        id: chatRowCards
        Item {
            height: 82 + 14
            Row {
                x: 16; spacing: 8
                Repeater {
                    model: row.items
                    FluentSurface {
                        required property var modelData
                        width: 294; height: 82; depth: 2; radius: 8; color: theme.surface
                        Avatar { x: 16; y: 16; size: 32; name: parent.modelData.name; group: true; meeting: String(parent.modelData.thread).indexOf("meeting_") >= 0 }
                        Text { x: 60; y: 16; width: parent.width - 60 - 50; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.modelData.name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { x: 60; y: 40; width: parent.width - 60 - 50; elide: Text.ElideRight; text: root.membersLine(parent.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; y: 42; text: root.shortDate(parent.modelData.last_message); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                        TapHandler { onTapped: root.openChat(parent.modelData.thread, parent.modelData.name, "", []) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: "Group chat " + modelData.name
                    }
                }
            }
        }
    }
    Component {
        id: channelRowCards
        Item {
            height: 82 + 14
            Row {
                x: 16; spacing: 8
                Repeater {
                    model: row.items
                    FluentSurface {
                        required property var modelData
                        width: (list.width - 32 - 16) / 3; height: 82; depth: 2; radius: 8; color: theme.surface
                        Avatar { x: 16; y: 16; size: 32; square: true; squareRadius: 4; name: parent.modelData.team; photoId: parent.modelData.group ? "team:" + parent.modelData.group : "" }
                        Text { x: 60; y: 16; width: parent.width - 76; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.modelData.name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { x: 60; y: 40; width: parent.width - 76; elide: Text.ElideRight; text: parent.modelData.team; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        TapHandler { onTapped: root.openChannel(parent.modelData.thread, parent.modelData.name, "", "", []) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + " channel in " + modelData.team + " team"
                    }
                }
            }
        }
    }
    // A file (Files tab, measured on winpc 2026-11-11): 760 wide, padding
    // 16; the 32 px type icon at 16, 20; at 60 the name (14/20, terms
    // bold) at 16, the place at 42, "Shared by OST Test 1 6 days ago" at 62
    // (both 12/16 #616161) and the summary (14/20 #424242, two lines) at 84.
    Component {
        id: fileCard
        Item {
            readonly property var f: row.h
            height: card2.height + 16
            HoverHandler { id: fh2 }
            Card {
                id: card2
                height: fcol.height + 32
                FluentIcon { x: 16; y: 20; size: 32; name: root.fileIcon(parent.parent.f.file_type, parent.parent.f.file_name) }
                Column {
                    id: fcol
                    x: 60; y: 16; width: parent.width - 60 - 56
                    Item {
                        width: parent.width; height: 26
                        Text { y: -0.67; width: parent.width; height: 20; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.parent.parent.f.file_name); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                    PlaceLine { visible: segments.length > 0; segments: root.filePlace(parent.parent.parent.f); height: 20 }
                    Item {
                        visible: !!lineText.text
                        width: parent.width; height: 22
                        Text { id: lineText; width: parent.width; height: 16; elide: Text.ElideRight; text: root.fileLine(parent.parent.parent.parent.f); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    }
                    Text {
                        visible: !!parent.parent.parent.f.text
                        width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        textFormat: Text.RichText; text: root.marked(parent.parent.parent.f.text)
                        font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                    }
                }
                CardAction {
                    visible: fh2.hovered
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 12
                    icon: "link-20"; label: "Copy link"
                    onClicked: backend.copyText(parent.parent.f.url)
                }
                TapHandler { onTapped: backend.openFile(parent.parent.f.url, parent.parent.f.file_name, "") }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: f.file_name
        }
    }
    // Teams' "Shared by OST Test 1 6 days ago" (or Created / Modified by;
    // just the author when that's all there is).
    function fileLine(f) {
        if (!f.file_action) return f.file_by || ""
        return f.file_action + " " + f.file_by + (f.file_when ? " " + ago(f.file_when) : "")
    }
    // The grid's "OST T." (the first word and the second's initial).
    function gridName(n) { const p = String(n || "").split(" "); return p[0] + " " + (p[1] ? p[1][0] + "." : "") }
    // Where a file is, as Teams' place line shows it: team › channel.
    // The team is the channel file's team (ChannelGroupId), else the joined
    // team whose site (or a channel's own site) is the file's, else the
    // site address's name; the channel is the first folder under the
    // library in the file's address, else "Shared Documents". A file never
    // opened (no Path) has no place.
    function filePlace(f) {
        if (!f || f.file_unredeemed) return []
        const teams = backend.teamsJson ? JSON.parse(backend.teamsJson) : []
        const site = String(f.file_site || "").toLowerCase()
        let t = f.file_group_id ? teams.find(t => t.id === f.file_group_id) : null
        if (!t && site) t = teams.find(t => String(t.site_url || "").toLowerCase() === site || (t.channels || []).some(c => String(c.site_url || "").toLowerCase() === site))
        const team = t ? t.name : String(f.file_site || "").split("/")[4]
        if (!team) return []
        let url = ""
        try { url = decodeURI(f.file_url || "") } catch (e) { url = "" }
        const m = url.match(/^https:\/\/[^\/]+\/[^\/]+\/(:w:\/|:v:\/)?(r\/)?([^\/]+)\/([^\/]+)\/([^\/]+)\/([^\/]+)/)
        return [team, (m && m[5]) || qsTr("Shared Documents")]
    }
    // Teams' place line: the parts (12/16 #616161, capitalized) between
    // 8 px chevrons 8 apart, all within 320; parts too long share the room.
    component PlaceLine: Row {
        id: pl
        property var segments: []
        spacing: 8
        FontMetrics { id: plm; font.family: theme.font; font.pixelSize: 12; font.capitalization: Font.Capitalize }
        readonly property var widths: {
            const natural = segments.map(t => Math.ceil(plm.advanceWidth(t)))
            let room = 320 - 16 * Math.max(0, segments.length - 1)
            const out = natural.slice()
            const order = natural.map((w, i) => i).sort((a, b) => natural[a] - natural[b])
            let left = order.length
            for (const i of order) { const share = room / left; out[i] = Math.min(natural[i], share); room -= out[i]; left-- }
            return out
        }
        Repeater {
            model: pl.segments
            Row {
                required property string modelData
                required property int index
                spacing: 8
                FluentIcon { visible: index > 0; y: 4; size: 8; name: "chevron-right-20"; color: theme.textSecondary }
                Text {
                    width: pl.widths[index] || 0; height: 16; elide: Text.ElideRight
                    text: modelData; font.family: theme.font; font.pixelSize: 12; font.capitalization: Font.Capitalize; color: theme.textSecondary
                }
            }
        }
    }
    function ago(iso) {
        const d = new Date(iso), days = Math.round((dayStart(new Date()) - dayStart(d)) / 86400000)
        return days <= 0 ? "today" : days === 1 ? "yesterday" : days < 30 ? days + " days ago" : Qt.formatDate(d, "M/d/yyyy")
    }
    function fileIcon(type, name) {
        const t = String(type || String(name || "").split(".").pop()).toLowerCase()
        const kind = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                   : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                   : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp"].indexOf(t) >= 0 ? "photo"
                   : ["mp4", "mov", "wmv", "avi", "mkv", "webm", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + kind + "-32"
    }
    // A person.
    Component {
        id: personCard
        Item {
            readonly property var p: row.p
            height: 64 + 16
            Card {
                height: 64
                // Teams: hovering the picture opens the person's card.
                Avatar { x: 16; y: 16; size: 32; name: parent.parent.p.name; photoId: parent.parent.p.mri; presence: root.presenceOf(parent.parent.p.mri); opensProfile: true }
                Text { x: 60; y: 11.3; width: parent.width - 76; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.p.name) + (root.isMe(parent.parent.p.mri) ? " (You)" : ""); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 60; y: 32; width: parent.width - 76; elide: Text.ElideRight; text: [parent.parent.p.title, parent.parent.p.department, parent.parent.p.mail].filter(x => !!x).join(" · "); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                TapHandler { onTapped: root.openPerson(parent.parent.p.mri, parent.parent.p.name) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: p.name
        }
    }
    // A meeting (75.3 tall): the date box, subject, times, Chat or Edit.
    Component {
        id: eventCard
        Item {
            readonly property var e: row.e
            readonly property date start: new Date(e.start)
            height: 75.3 + 16
            Card {
                height: 75.3
                Rectangle {
                    x: 16.7; y: 18.6; width: 40; height: 40; radius: 4
                    color: "transparent"; border.color: theme.stroke; border.width: 0.67
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 0.7; text: parent.parent.parent.start.getDate(); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 22.7; text: Qt.formatDate(parent.parent.parent.start, "MMM").toUpperCase(); font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
                }
                Text { x: 72.7; y: 17.3; width: parent.width - 72.7 - 130; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.parent.e.subject); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: 72.7; y: 38.6; text: Qt.formatDate(parent.parent.start, "dddd") + " " + Qt.formatTime(parent.parent.start, "h:mm AP") + " - " + Qt.formatTime(new Date(parent.parent.e.end), "h:mm AP") + (parent.parent.e.location ? "  |  " + parent.parent.e.location : ""); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 17
                    spacing: 0
                    Rectangle {
                        readonly property bool chat: !!parent.parent.parent.e.join_url && !parent.parent.parent.e.is_organizer || (!!parent.parent.parent.e.join_url && new Date(parent.parent.parent.e.end) < new Date())
                        width: ebText.implicitWidth + 16 + 6 + 20; height: 23.3; radius: 4
                        color: ebh.hovered ? theme.hover : theme.surface; border.color: theme.stroke; border.width: 0.67
                        FluentIcon { x: 10.6; anchors.verticalCenter: parent.verticalCenter; name: parent.chat ? "chat-20" : "edit-20"; size: 16; color: theme.text }
                        Text { id: ebText; x: 32.6; anchors.verticalCenter: parent.verticalCenter; text: parent.chat ? "Chat" : "Edit"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                        HoverHandler { id: ebh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openMeeting(parent.parent.parent.parent.e) }
                        Accessible.role: Accessible.Button
                        Accessible.name: (parent.chat ? "Chat with participants" : "Edit ") + parent.parent.parent.e.subject
                    }
                }
                TapHandler { onTapped: root.openMeeting(parent.parent.e) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: e.subject
        }
    }
    // Images: cards of 242.3 x 216.3 (the picture 136.3 over an 80 footer).
    Component {
        id: imageRow
        Item {
            height: 216.3 + 16
            Row {
                x: 16; spacing: 16
                Repeater {
                    model: row.items
                    FluentSurface {
                        required property var modelData
                        width: 242.3; height: 216.3; depth: 2; radius: 6; color: theme.surface
                        Rectangle {
                            width: parent.width; height: 136.3; radius: 6; color: theme.pick("#F5F5F5", "#2E2E2E"); clip: true
                            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; source: root.imageOf(parent.parent.modelData) }
                        }
                        Rectangle { y: 136.3; width: parent.width; height: 80; color: theme.pick("#FAFAFA", "#1A1A1A"); radius: 6 }
                        Avatar { x: 12.7; y: 142.9; size: 20; name: parent.modelData.sender_name || ""; photoId: parent.modelData.sender_mri || "" }
                        Text { x: 40.7; y: 144.9; text: root.shortName(parent.modelData.sender_name) + "   "; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        Text { x: 82.6; y: 144.9; text: root.shortDate(parent.modelData.time); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        Text { x: 12.7; y: 165.9; width: parent.width - 25; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(root.chatName(parent.modelData.thread) || parent.modelData.file_name || ""); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        Text { x: 12.7; y: 191.2; width: parent.width - 25; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.modelData.text || ""); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        TapHandler { onTapped: parent.modelData.file_name ? backend.openFile(parent.modelData.url, parent.modelData.file_name, "") : root.openHit(parent.modelData) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: "image shared by " + (modelData.sender_name || "")
                    }
                }
            }
        }
    }
    // Grid view: Send feedback over the grid's right edge, the cards 44
    // below it (Teams: feedback 28 under the filters, cards at 72).
    Component {
        id: gridHeading
        Item {
            height: 52
            FeedbackThumbs { y: 8; anchors.right: parent.right; anchors.rightMargin: 16 }
        }
    }
    // Grid view (Teams, measured on winpc 2026-11-11): three 242.27 x
    // 186.27 cards 15.6 apart (radius 6, Fluent shadow 2). The file's
    // preview (c960x540 thumbnail, cropped from the top) fills 136.27 on
    // #F5F5F5, or a 28 px generic file picture when it has none; under it a
    // #FAFAFA footer, 50 tall: the 32 px type icon at 12.67, the name (14/20
    // semibold, terms bold) at 52.67, 7 and "OST T." + "6 days ago" (12/16
    // #616161, 4 apart) at 27, and "More attachment options" (32 px, a 16 px
    // ···) at 202.6, 9.
    Component {
        id: fileGridRow
        Item {
            height: 186.27 + 15.6
            Row {
                x: 16 + root.gridShift; spacing: 15.6
                Repeater {
                    model: row.items
                    FluentSurface {
                        id: gcard
                        required property var modelData
                        readonly property string link: modelData.file_url || modelData.url || ""
                        property string thumb: backend.fileThumbnail(link)
                        Connections {
                            target: backend
                            function onThumbnailReady(url) { if (url === gcard.link) gcard.thumb = backend.fileThumbnail(gcard.link) }
                        }
                        width: 242.27; height: 186.27; depth: 2; radius: 6; color: theme.surface
                        // Rounded at the top only: the footer covers the rest.
                        Rectangle { width: parent.width; height: 136.27 + 6; radius: 6; color: theme.pick("#F5F5F5", "#2E2E2E") }
                        FluentIcon { visible: gimg.status !== Image.Ready; x: (parent.width - 28) / 2; y: (136.27 - 28) / 2; size: 28; name: "ft-genericfile-32" }
                        // The picture, cropped from its top to fill the area
                        // and clipped to the card's top corners on a canvas
                        // (painted at twice the size, like Avatar's).
                        Image {
                            id: gimg
                            visible: false; asynchronous: true; source: gcard.thumb
                            sourceSize.width: Math.ceil(gcard.width * 2 * Math.max(1, Screen.devicePixelRatio))
                            onStatusChanged: { gpic.requestPaint(); if (status === Image.Ready) grepaint.restart() }
                        }
                        Timer { id: grepaint; interval: 50; onTriggered: gpic.requestPaint() }
                        Canvas {
                            id: gpic
                            width: gcard.width * 2; height: 136.27 * 2; scale: 0.5; transformOrigin: Item.TopLeft
                            smooth: true; antialiasing: true
                            visible: gimg.status === Image.Ready
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const iw = gimg.implicitWidth, ih = gimg.implicitHeight
                                if (gimg.status !== Image.Ready || !iw || !ih) return
                                const r = 12
                                ctx.beginPath()
                                ctx.moveTo(0, height); ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r)
                                ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r); ctx.lineTo(width, height)
                                ctx.closePath()
                                ctx.clip()
                                const k = Math.max(width / iw, height / ih), sw = width / k, sh = height / k
                                ctx.drawImage(gimg, (iw - sw) / 2, 0, sw, sh, 0, 0, width, height)
                            }
                        }
                        Rectangle { y: 136.27; width: parent.width; height: 50; radius: 6; color: theme.pick("#FAFAFA", "#1A1A1A") }
                        Rectangle { y: 136.27; width: parent.width; height: 8; color: theme.pick("#FAFAFA", "#1A1A1A") }
                        FluentIcon { x: 12.67; y: 145.27; size: 32; name: root.fileIcon(gcard.modelData.file_type, gcard.modelData.file_name) }
                        Text {
                            x: 52.67; y: 143.27; width: 144.67; height: 20; verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(gcard.modelData.file_name || "")
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                        }
                        Row {
                            x: 52.67; y: 163.27; spacing: 4
                            Text { text: gcard.modelData.file_action ? root.gridName(gcard.modelData.file_by) : (gcard.modelData.file_by || ""); height: 16; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                            Text { visible: !!gcard.modelData.file_action && !!gcard.modelData.file_when; text: root.ago(gcard.modelData.file_when); height: 16; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        }
                        HoverHandler { id: gch; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.openFile(gcard.modelData.url, gcard.modelData.file_name, "") }
                        ToolTip.visible: gch.hovered && !gmore.hovered && !gmenu.visible; ToolTip.delay: 700
                        ToolTip.text: [gcard.modelData.file_name, root.fileLine(gcard.modelData), gcard.modelData.url].filter(x => !!x).join("\n")
                        Rectangle {
                            id: gmoreBtn
                            x: 202.6; y: 145.27; width: 32; height: 32; radius: 4
                            color: gmore.hovered ? theme.hover : "transparent"
                            FluentIcon { anchors.centerIn: parent; size: 16; name: "more-horizontal-20"; color: theme.textSecondary }
                            HoverHandler { id: gmore; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: gmenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "More attachment options"
                            // Teams: 180 wide under the button, from its left.
                            MenuPopup {
                                id: gmenu
                                x: 0; y: parent.height + 4; width: 180
                                readonly property bool loop: /\.(loop|fluid)$/i.test(gcard.modelData.file_name || "")
                                items: [{ label: "Open in Browser", icon: "globe-20" }]
                                    .concat(loop ? [] : [{ label: "Download", icon: "arrow-download-20" }])
                                    .concat([{ label: "Share", icon: "share-20" }, { label: "Copy link", icon: "link-20" }, { label: "Favorite", icon: "star-20" }])
                                onPicked: i => {
                                    close()
                                    const label = items[i].label
                                    if (label === "Open in Browser") Qt.openUrlExternally(gcard.modelData.url)
                                    else if (label === "Share") shareFile.openFor({ site: gcard.modelData.file_site, list: gcard.modelData.file_list, item: gcard.modelData.id }, gcard.modelData.file_name, gcard.modelData.file_type, gcard.link)
                                    else if (label === "Download") backend.findFileAction("download", gcard.link)
                                    else if (label === "Copy link") { backend.copyText(gcard.modelData.url); backend.statusText = "Link copied" }
                                    else backend.findFileAction("favorite", gcard.link)
                                }
                            }
                        }
                        function openMenu() { gmenu.open() }
                        function closeMenu() { gmenu.close() }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: (modelData.file_name || "") + " " + root.fileLine(modelData)
                    }
                }
            }
        }
    }
    function shortName(n) { const p = String(n || "").split(" "); return p.length > 1 ? p[0] + " " + p[p.length - 1][0] + "." : String(n || "") }
    function imageOf(h) { return h.image_url || (h.file_name ? "" : "") }

    // Teams' "Share this file" (Share in a file card's ···).
    ShareFileDialog { id: shareFile }

    // Test hooks.
    function rowsForTest() { return rows }
    function shareFileForTest() { return shareFile }
    property Item gridMenuOwner: null
    function openGridMenuForTest() {
        const row = list.itemAtIndex(1)
        const card = row && row.item ? Array.from(row.item.children[0].children).find(c => !!c.openMenu) : null
        if (card && card.openMenu) { gridMenuOwner = card; card.openMenu() }
    }
    function closeGridMenuForTest() { if (gridMenuOwner) gridMenuOwner.closeMenu() }
}
