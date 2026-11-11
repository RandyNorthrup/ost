import QtQuick
import QtQuick.Controls.Basic

// Teams' Find in chat / Find in channel pane (measured on winpc
// 2026-11-10), 360 wide on the right, a 0.67 px line on its left:
// - the header (61): "Find in chat" (14/600, 20.7 in) and Close (32 x
//   31.3, 312 in);
// - the keyword box (12.7, 69; 335.3 x 32): "Enter a search keyword...",
//   the search icon on the right until there's text, then "Clear";
// - the filters (113 down, from 12.7, 8 apart; pills 24 tall, 12 px):
//   Messages ▾ / Files ▾ (54, brand), then the filters turned on (brand,
//   with ×) in the order they were, then the rest (#E8EBFA): Date ▾,
//   From ▾, and Attachment and Mentions (36) for messages or Type ▾ for
//   files; a line under them at 152.7;
// - results grouped by month (12 px #616161, 12.7 in, 8 above and below):
//   a message row (inset 4.7, padding 12 / 8, radius 3; hover #FAFAFA,
//   the open one #EBEBEB) has the sender's 28 px picture with presence,
//   "You" or their name and the time (12, #616161, the time on the right),
//   two lines of the text (14/20, the terms on #F9E2AE) and a #D1D1D1
//   line 8 under; a file row (54 tall, padding 0 8) its 32 px type icon,
//   name (14) and "{who}, {time}" (12, the terms bold) and ··· (Open in
//   browser, Download, Copy link, Favorite);
// - before a search, the search-keywords picture (220) with "Search in
//   this chat" (18/700) and "Find messages, files, and URLs shared in this
//   chat." (12, #616161); with none found, the exclamation picture with
//   "We couldn't find any results in this chat" and "Check for spelling,
//   try another search keyword, or search in another chat."
// The search is Substrate's (backend.findInChat); a message opens in the
// conversation with the terms marked.
Rectangle {
    id: pane
    property string chatId: ""
    property bool isChannel: false
    /// The chat's members ([{mri, name, mail, presence}]) for From.
    property var members: []
    /// A channel's team group id and folder address (its Files).
    property string channelGroup: ""
    property string channelPath: ""
    signal closed()
    /// A message picked: its hit and the terms to mark.
    signal jumpTo(var hit, var terms)
    color: theme.surface
    /// Find in post (a post's own window): the post's id.
    property string postRoot: ""
    /// In a window of its own (Find in post): the pane fills the window
    /// under its title bar, with a line under the header and room for the
    /// window's scroll bar.
    property bool windowed: false
    /// Wide (Find in post's window): the pills show their names.
    readonly property bool wide: width >= 480
    readonly property string place: postRoot ? "post" : isChannel ? "channel" : "chat"
    readonly property real headerHeight: 61
    readonly property real boxY: headerHeight + 8
    readonly property real listY: boxY + 44 + 40.4

    // The filters.
    property bool files: false
    property string dateKey: ""          // today | yesterday | week | month | custom
    property date customFrom: new Date()
    property date customTo: new Date()
    property var person: null             // {name, mail, mri}
    property bool attachment: false
    property bool mentions: false
    property string fileType: ""
    /// The filters on, in the order they were turned on (Teams lines them
    /// up after Messages that way).
    property var activeOrder: []
    function setActive(k, on) {
        const a = activeOrder.filter(x => x !== k)
        if (on) a.push(k)
        activeOrder = a
    }

    property string selectedId: ""
    property int generation: 0
    readonly property string key: chatId + "#" + generation
    readonly property var result: {
        try { const r = JSON.parse(backend.findJson || "{}"); return r.key === key ? r : null } catch (e) { return null }
    }
    readonly property string query: field.text.trim()
    readonly property bool hasFilters: !!dateKey || !!person || (files ? !!fileType : (attachment || mentions))
    readonly property bool idle: !query && !hasFilters
    readonly property var hits: result && result.hits ? result.hits : []
    /// The rows: each month's heading, then its results.
    readonly property var rows: {
        const out = []
        let last = ""
        for (const h of hits) {
            const g = group(h.time)
            if (g !== last) { out.push({ heading: g }); last = g }
            out.push(h)
        }
        return out
    }
    readonly property var terms: result && result.terms && result.terms.length ? result.terms : query.split(/\s+/).filter(t => !!t)

    function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    // The date range in local days, as UTC (Teams: the week from Sunday).
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
            files: files,
            start: r ? r[0].toISOString() : "", end: r ? r[1].toISOString() : "",
            attachment: !files && attachment, mentions: !files && mentions,
            from_mail: person ? person.mail : "", from_oid: person ? String(person.mri).split(":").pop() : "",
            file_type: files ? fileType : "",
            channel_group: channelGroup, channel_path: channelPath, post_root: postRoot,
        }
    }
    function run() {
        selectedId = ""
        generation++
        if (!idle) backend.findInChat(key, chatId, query, JSON.stringify(filters()), 0)
        list.contentY = 0
    }
    function more() {
        if (result && result.more && !result.loading && !idle)
            backend.findInChat(key, chatId, query, JSON.stringify(filters()), hits.length)
    }
    function reset() {
        field.text = ""; files = false; dateKey = ""; person = null; attachment = false; mentions = false
        fileType = ""; activeOrder = []; selectedId = ""; generation++
    }
    function focusField() { field.forceActiveFocus() }
    onChatIdChanged: reset()

    // Times as Teams writes them in the results.
    function when(iso) {
        const d = new Date(iso)
        if (isNaN(d)) return ""
        const days = Math.round((dayStart(new Date()) - dayStart(d)) / 86400000)
        const time = Qt.formatTime(d, "h:mm AP")
        if (days === 0) return time
        if (days === 1) return "Yesterday, " + time
        return d.getFullYear() === new Date().getFullYear() ? Qt.formatDate(d, "M/d") : Qt.formatDate(d, "M/d/yyyy")
    }
    function group(iso) {
        const d = new Date(iso), n = new Date()
        const months = (n.getFullYear() - d.getFullYear()) * 12 + n.getMonth() - d.getMonth()
        return months <= 0 ? "This month" : months === 1 ? "Last month" : "Older"
    }
    function escaped(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    // Two lines of `text` at `width`, ellipsised, with the terms marked.
    function clamped(text, width) {
        const words = String(text || "").split(/\s+/).filter(w => !!w)
        const lines = []
        let cur = "", i = 0
        for (; i < words.length && lines.length < 2; i++) {
            const next = cur ? cur + " " + words[i] : words[i]
            if (rowMetrics.advanceWidth(next) <= width) { cur = next; continue }
            if (cur) { lines.push(cur); cur = "" }
            if (lines.length === 2) break
            cur = words[i]
            while (rowMetrics.advanceWidth(cur) > width && cur.length > 1) {
                let k = cur.length
                while (k > 1 && rowMetrics.advanceWidth(cur.slice(0, k)) > width) k--
                lines.push(cur.slice(0, k)); cur = cur.slice(k)
                if (lines.length === 2) break
            }
        }
        const cut = i < words.length || (lines.length === 2 && !!cur)
        if (lines.length < 2 && cur) { lines.push(cur); cur = "" }
        if (cut && lines.length) {
            let last = lines[lines.length - 1]
            while (last.length && rowMetrics.advanceWidth(last + "…") > width) last = last.slice(0, -1)
            lines[lines.length - 1] = last.replace(/\s+$/, "") + "…"
        }
        return lines.map(l => theme.markTerms(escaped(l), terms)).join("<br>")
    }
    // Bold the terms (a file row's second line).
    function bolded(text) {
        const re = theme.termPattern(terms)
        const t = escaped(text)
        return re ? t.replace(re, "$1<b>$2</b>") : t
    }
    FontMetrics { id: rowMetrics; font.family: theme.font; font.pixelSize: 14 }
    FontMetrics { id: chipMetrics; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
    FontMetrics { id: plainChip; font.family: theme.font; font.pixelSize: 12 }

    Rectangle { z: 3; width: 0.67; height: parent.height; color: theme.pick("#E0E0E0", "#3D3D3D") }

    // A header button.
    component PaneAction: Rectangle {
        id: pa
        property alias icon: paIcon.name
        signal clicked()
        width: 32; height: 31.3; radius: theme.radius
        color: paHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: paHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pa.clicked() }
        FluentIcon { id: paIcon; anchors.centerIn: parent; size: 20; color: theme.textStrong }
        Accessible.role: Accessible.Button
    }

    Item {
        id: head
        x: 0.67; width: parent.width - 0.67; height: pane.headerHeight
        Text {
            x: 20.7 - 0.67; anchors.verticalCenter: parent.verticalCenter
            text: "Find in " + pane.place
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        PaneAction {
            x: pane.width - 48 - (pane.windowed ? 14 : 0) - 0.67; anchors.verticalCenter: parent.verticalCenter
            icon: "dismiss-20"; Accessible.name: "Close Find in " + pane.place
            onClicked: pane.closed()
        }
    }

    // The keyword box.
    Rectangle {
        id: box
        x: 12.7; y: pane.boxY; width: pane.width - 24.7 - (pane.windowed ? 13.3 : 0); height: 32; radius: 4
        color: theme.surface
        border.color: boxHover.hovered ? theme.strokeHover : theme.stroke; border.width: 0.67
        HoverHandler { id: boxHover; cursorShape: Qt.IBeamCursor }
        Rectangle {
            anchors.bottom: parent.bottom; x: 1; width: parent.width - 2
            height: field.activeFocus ? 2 : 0.67
            color: field.activeFocus ? theme.brand : theme.textSecondary
        }
        TextInput {
            id: field
            x: 12; width: parent.width - 12 - 45
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            selectionColor: theme.selectionFill; selectedTextColor: theme.text
            clip: true
            onTextChanged: typing.restart()
            Keys.onReturnPressed: { typing.stop(); pane.run() }
            Keys.onEnterPressed: { typing.stop(); pane.run() }
            Keys.onEscapePressed: pane.closed()
            Keys.onDownPressed: if (list.count) { list.currentIndex = 0; list.forceActiveFocus() }
            Text {
                visible: !field.text
                text: "Enter a search keyword..."
                font: field.font; color: theme.textSecondary
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Find in " + pane.place
        }
        // Teams searches as you type, a moment after the last key.
        Timer { id: typing; interval: 400; onTriggered: pane.run() }
        FluentIcon {
            visible: !field.text
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            name: "search-20"; size: 20; color: theme.textStrong
        }
        Text {
            visible: !!field.text
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            text: "Clear"
            font.family: theme.font; font.pixelSize: 14; color: theme.brand
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { field.text = ""; typing.stop(); pane.run(); field.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear"
        }
    }

    // A filter pill.
    component Chip: Rectangle {
        id: chip
        /// Off: its icon (16) and chevron, or (wide, or Type) its text and
        /// chevron; on: brand, its label (or type icon, or icon) and ×.
        property string icon: ""
        property string text: ""          // the name shown when wide (Type always)
        property string label: ""         // what it's set to, when on
        property string typeIcon: ""      // a coloured type icon when on
        property bool on: false
        property bool chevron: true
        property bool mode: false         // Messages / Files: brand, no ×
        property bool wide: false
        property string name: ""
        signal clicked()
        signal cleared()
        readonly property bool texted: (wide || !icon) && !!text
        readonly property real textWidth: Math.ceil((mode ? chipMetrics : plainChip).advanceWidth(text))
        // Teams' pills (measured): Messages 54 (wide: icon 10, text 30,
        // chevron 2 after, 10 right); Date / From 54 (wide: text 12,
        // chevron 2 after, 12 right); Attachment / Mentions 36 (wide: icon
        // 6, text 22, 10 right); on: the label 12 in with 4 after, or the
        // icon in 30, then × (18 / 16).
        readonly property real labelWidth: mode ? (wide ? 30 + textWidth + 2 + 12 + 10 : 54)
                                          : on && label ? 10 + 2 + Math.ceil(chipMetrics.advanceWidth(label)) + 2 + 4
                                          : on ? 30
                                          : texted ? (chevron ? 12 + textWidth + 2 + 12 + 12 : 22 + textWidth + 10)
                                          : chevron ? 54 : 36
        width: labelWidth + (on && !mode ? (label ? 18 : 16) : 0)
        height: 24; radius: 12
        color: on || mode ? (chipHover.hovered || dismissHover.hovered ? theme.brandHover : theme.brand) : chipHover.hovered ? theme.pick("#DCE0FA", "#3D3E66") : theme.brandTint
        readonly property color ink: on || mode ? "#FFFFFF" : theme.text
        Item {
            id: face
            width: chip.labelWidth; height: parent.height
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chip.clicked() }
            // Off (or the mode pill).
            FluentIcon {
                visible: (!chip.on || chip.mode) && !!chip.icon && (chip.mode || !chip.texted || !chip.chevron)
                x: chip.mode ? 10 : chip.texted ? 6 : chip.chevron ? 12 : 10
                anchors.verticalCenter: parent.verticalCenter
                name: chip.icon; size: 16; color: chip.ink
            }
            Text {
                visible: (!chip.on || chip.mode) && chip.texted && (chip.wide || !chip.mode)
                x: chip.mode ? 30 : chip.chevron ? 12 : 22
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text; font.family: theme.font; font.pixelSize: 12
                font.weight: chip.mode ? Font.DemiBold : Font.Normal; color: chip.ink
            }
            FluentIcon {
                visible: (!chip.on || chip.mode) && chip.chevron
                x: chip.mode ? (chip.wide ? 30 + chip.textWidth + 2 : 32) : chip.texted ? 12 + chip.textWidth + 2 : 30
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-down-20"; size: 12; color: chip.ink
            }
            // On: its label, type icon or icon.
            Text {
                visible: chip.on && !chip.mode && !!chip.label
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: chip.label; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: chip.ink
            }
            FluentIcon {
                visible: chip.on && !chip.mode && !chip.label
                x: chip.typeIcon ? 6 : 10; anchors.verticalCenter: parent.verticalCenter
                name: chip.typeIcon || chip.icon; size: chip.typeIcon ? 20 : 16; color: chip.ink
            }
        }
        Item {
            visible: chip.on && !chip.mode
            x: chip.labelWidth; width: chip.width - chip.labelWidth; height: parent.height
            HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chip.cleared() }
            FluentIcon { x: 0; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-20"; size: 12; color: "#FFFFFF" }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear"
        }
        Accessible.role: Accessible.Button
        Accessible.name: chip.name
    }

    readonly property var typeNames: ({ excel: "Excel", images: "Images", loop: "Loop", onenote: "OneNote", pdf: "PDF", powerpoint: "PowerPoint", text: "Text file", word: "Word" })
    readonly property var typeKeys: ["excel", "images", "loop", "onenote", "pdf", "powerpoint", "text", "word"]
    readonly property var typeIcons: ({ excel: "ft-xlsx-20", images: "ft-photo-20", loop: "ft-loop-20", onenote: "ft-one-20", pdf: "ft-pdf-20", powerpoint: "ft-pptx-20", text: "ft-txt-20", word: "ft-docx-20" })
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
    // The pills after Messages / Files: those on, in order, then the rest.
    readonly property var chipKeys: {
        const all = files ? ["date", "from", "type"] : ["date", "from", "attachment", "mentions"]
        const on = activeOrder.filter(k => all.indexOf(k) >= 0)
        return on.concat(all.filter(k => on.indexOf(k) < 0))
    }
    function isOn(k) {
        return k === "date" ? !!dateKey : k === "from" ? !!person : k === "type" ? !!fileType : k === "attachment" ? attachment : mentions
    }
    function clear(k) {
        if (k === "date") dateKey = ""
        else if (k === "from") person = null
        else if (k === "type") fileType = ""
        else if (k === "attachment") attachment = false
        else mentions = false
        setActive(k, false)
        run()
    }

    Row {
        id: chips
        x: 12.7; y: pane.boxY + 44; spacing: 8
        Chip {
            id: modeChip
            mode: true; on: true; wide: pane.wide
            icon: pane.files ? "document-20" : "chat-bubbles-20"
            text: pane.files ? "Files" : "Messages"
            name: pane.files ? "Files" : "Messages"
            onClicked: modeMenu.open()
            RadioMenu {
                id: modeMenu
                y: parent.height + 4
                items: [{ label: "Messages", checked: !pane.files }, { label: "Files", checked: pane.files }]
                onPicked: i => {
                    close()
                    if ((i === 1) === pane.files) return
                    pane.files = i === 1
                    pane.setActive(pane.files ? "attachment" : "type", false)
                    pane.setActive(pane.files ? "mentions" : "type", false)
                    pane.attachment = false; pane.mentions = false; pane.fileType = ""
                    pane.run()
                }
            }
        }
        Repeater {
            model: pane.chipKeys
            Chip {
                id: fc
                required property string modelData
                on: pane.isOn(modelData)
                wide: pane.wide
                chevron: modelData !== "attachment" && modelData !== "mentions"
                text: ({ date: "Date", from: "From", attachment: "Attachment", mentions: "Mentions", type: "Type" })[modelData]
                icon: ({ date: "calendar-ltr-20", from: "person-20", attachment: "attach-20", mentions: "mention-20", type: "" })[modelData]
                label: modelData === "date" ? (on ? pane.dateLabel() : "")
                     : modelData === "from" ? (on && pane.person ? pane.person.name : "")
                     : pane.wide && on && (modelData === "attachment" || modelData === "mentions") ? text : ""
                typeIcon: modelData === "type" && on ? pane.typeIcons[pane.fileType] : ""
                name: ({ date: on ? "Date " + pane.dateLabel() : "Date filter", from: on && pane.person ? "From " + pane.person.name : "From filter",
                         attachment: "Attachment", mentions: "Mentions", type: on ? "File type " + pane.typeNames[pane.fileType] + " selected" : "File type" })[modelData]
                onClicked: {
                    if (modelData === "attachment") { pane.attachment = !pane.attachment; pane.setActive("attachment", pane.attachment); pane.run() }
                    else if (modelData === "mentions") { pane.mentions = !pane.mentions; pane.setActive("mentions", pane.mentions); pane.run() }
                    else if (modelData === "date") { datePop.anchorTo(fc); datePop.open() }
                    else if (modelData === "from") { fromPop.anchorTo(fc); fromPop.open() }
                    else { typeMenu.x = fc.x + chips.x; typeMenu.open() }
                }
                onCleared: pane.clear(modelData)
            }
        }
    }
    MenuPopup {
        id: typeMenu
        y: chips.y + 24 + 4
        perItemIcons: true
        items: pane.typeKeys.map(k => ({ label: pane.typeNames[k], icon: pane.typeIcons[k] }))
        onPicked: i => { close(); pane.fileType = pane.typeKeys[i]; pane.setActive("type", true); pane.run() }
    }
    Rectangle { x: 0.67; y: pane.listY - 0.7; width: parent.width - 0.67; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
    Rectangle { visible: pane.windowed; x: 0.67; y: pane.headerHeight; width: parent.width - 0.67; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }

    // Date ▾ (254 x 336.7, under the pill, its right edge on the pill's):
    // Today, Yesterday, This week, This month (32 tall, 16 in), a line,
    // From / To (12) with their date fields (222.7 x 32, #F5F5F5), then
    // Clear and Apply.
    Popup {
        id: datePop
        function anchorTo(item) { const p = item.mapToItem(pane, 0, 0); x = p.x + item.width - width; y = p.y + item.height }
        width: 254; height: 336.7; padding: 0
        property bool fromSet: false
        property date fromDate: new Date()
        property date toDate: new Date()
        onAboutToShow: {
            fromSet = pane.dateKey === "custom"
            fromDate = pane.dateKey === "custom" ? pane.customFrom : new Date()
            toDate = pane.dateKey === "custom" ? pane.customTo : new Date()
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 0.67; y: 6.7; width: parent.width - 1.33
            Repeater {
                model: [{ k: "today", l: "Today" }, { k: "yesterday", l: "Yesterday" }, { k: "week", l: "This week" }, { k: "month", l: "This month" }]
                Rectangle {
                    required property var modelData
                    width: parent.width; height: 32
                    color: dh.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : pane.dateKey === modelData.k ? theme.pick("#EBEBEB", "#383838") : "transparent"
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.l; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { pane.dateKey = parent.modelData.k; pane.setActive("date", true); datePop.close(); pane.run() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.l
                }
            }
        }
        Rectangle { x: 0.67; y: 144.7; width: parent.width - 1.33; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
        Text { x: 15.7; y: 161.7; text: "From"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        DatePickerField {
            x: 15.7; y: 181.7; width: 222.7
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            empty: !datePop.fromSet; placeholder: "Select a date"
            date: datePop.fromDate; maxDate: datePop.toDate
            onPicked: d => { datePop.fromDate = d; datePop.fromSet = true }
        }
        Text { x: 15.7; y: 225; text: "To"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        DatePickerField {
            x: 15.7; y: 245; width: 222.7
            filled: true; format: "dddd, MMMM d, yyyy"; iconSize: 16; iconRight: 6
            date: datePop.toDate; minDate: datePop.fromSet ? datePop.fromDate : new Date(1900, 0, 1); maxDate: new Date()
            onPicked: d => datePop.toDate = d
        }
        Rectangle {
            x: 79.6; y: 289; width: 54.7; height: 32; radius: 4
            readonly property bool usable: datePop.fromSet || !!pane.dateKey
            color: usable && clh.hovered ? theme.hover : "transparent"
            Text { anchors.centerIn: parent; text: "Clear"; font.family: theme.font; font.pixelSize: 14; color: parent.usable ? theme.text : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: clh; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.usable; onTapped: { datePop.fromSet = false; datePop.toDate = new Date(); if (pane.dateKey) { datePop.close(); pane.clear("date") } } }
            Accessible.role: Accessible.Button
            Accessible.name: "Clear the Selected Date Range"
        }
        Rectangle {
            x: 142.3; y: 289; width: 96; height: 32; radius: 4
            readonly property bool usable: datePop.fromSet
            color: usable ? (aph.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E")
            Text { anchors.centerIn: parent; text: "Apply"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.usable ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: aph; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler {
                enabled: parent.usable
                onTapped: { pane.customFrom = datePop.fromDate; pane.customTo = datePop.toDate; pane.dateKey = "custom"; pane.setActive("date", true); datePop.close(); pane.run() }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Apply the Selected Date Range"
        }
    }

    // From ▾ (254 wide, padding 16 / 12): "Filter by person" (230 x 33.3,
    // #F5F5F5) and the people who match (50 tall: their 32 px picture at
    // 12, the name 14 and address 12, the match bold).
    Popup {
        id: fromPop
        function anchorTo(item) { const p = item.mapToItem(pane, 0, 0); x = p.x + item.width - width; y = p.y + item.height }
        width: 254; padding: 0
        height: 66.7 + (people.length ? people.length * 50 + 8 : 0)
        onOpened: { who.text = ""; who.forceActiveFocus() }
        readonly property var people: {
            const q = who.text.trim().toLowerCase()
            if (pane.isChannel) {
                if (!q) return []
                try {
                    const r = JSON.parse(backend.findPeopleJson || "{}")
                    return r.keyword && r.keyword.toLowerCase() === q ? r.people || [] : []
                } catch (e) { return [] }
            }
            return pane.members.filter(m => !q || (m.name || "").toLowerCase().split(/\s+/).some(w => w.startsWith(q))
                                          || (m.name || "").toLowerCase().startsWith(q) || (m.mail || "").toLowerCase().startsWith(q))
        }
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        Rectangle {
            x: 12.7; y: 16.7; width: 230; height: 33.3; radius: 4
            color: theme.pick("#F5F5F5", "#141414")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: who.activeFocus ? 2 : 0.67; color: who.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: who
                x: 14.6; width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                clip: true
                onTextChanged: if (pane.isChannel) peopleTimer.restart()
                Keys.onReturnPressed: if (fromPop.people.length) fromPop.pick(fromPop.people[0])
                Keys.onEscapePressed: fromPop.close()
                Text { visible: !who.text; text: "Filter by person"; font: who.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Filter by person"
            }
            Timer { id: peopleTimer; interval: 250; onTriggered: backend.findPeople(pane.chatId, who.text) }
        }
        function pick(p) { pane.person = { name: p.name, mail: p.mail, mri: p.mri }; pane.setActive("from", true); close(); pane.run() }
        Column {
            x: 16.7; y: 54; width: 222
            Repeater {
                model: fromPop.people
                Rectangle {
                    id: prow
                    required property var modelData
                    readonly property bool me: (modelData.mri || "").toLowerCase() === (backend.userMri || "").toLowerCase()
                    width: 222; height: 50; radius: 4
                    color: ph.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: prow.modelData.name || ""; photoId: prow.modelData.mri || "" }
                    Text {
                        x: 60; y: 7; width: parent.width - 68
                        textFormat: Text.StyledText; elide: Text.ElideRight
                        text: pane.boldPrefix(prow.modelData.name || "", who.text) + (prow.me ? " (You)" : "")
                        font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                    }
                    Text {
                        x: 60; y: 27.5; width: parent.width - 68
                        textFormat: Text.StyledText; elide: Text.ElideRight
                        text: pane.boldPrefix(prow.modelData.mail || "", who.text)
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: fromPop.pick(prow.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: (modelData.name || "") + " " + (modelData.mail || "")
                }
            }
        }
    }
    // The typed start of each word in bold.
    function boldPrefix(t, q) {
        q = String(q || "").trim()
        const e = escaped(t)
        if (!q) return e
        const re = new RegExp("(^|[\\s.@-])(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi")
        return e.replace(re, "$1<b>$2</b>")
    }

    // Results.
    ListView {
        id: list
        x: 0.67; y: pane.listY; width: parent.width - 0.67; height: parent.height - y - feedbackBar.height
        clip: true
        visible: !pane.idle && pane.hits.length > 0
        model: pane.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { id: bar; policy: ScrollBar.AsNeeded }
        readonly property real rowWidth: width - 4 * 2 - (bar.visible && !pane.files ? 14 : 0)
        onContentYChanged: if (contentY + height > contentHeight - 200) pane.more()
        Keys.onUpPressed: { let i = currentIndex - 1; while (i >= 0 && pane.rows[i].heading) i--; if (i >= 0) currentIndex = i; else field.forceActiveFocus() }
        Keys.onDownPressed: { let i = currentIndex + 1; while (i < count && pane.rows[i].heading) i++; if (i < count) currentIndex = i }
        Keys.onReturnPressed: if (currentItem) currentItem.open()
        Keys.onEscapePressed: field.forceActiveFocus()
        delegate: Item {
            id: hitRow
            required property var modelData
            required property int index
            readonly property bool heading: !!modelData.heading
            readonly property bool isFile: !!modelData.file_name
            readonly property bool picked: !heading && pane.selectedId === modelData.id
            readonly property bool me: (modelData.sender_mri || "").toLowerCase() === (backend.userMri || "").toLowerCase()
            // A channel post (not a reply): "{who} posted" with the post
            // icon, its subject in bold, then the subject and text.
            readonly property bool posted: !heading && !isFile && pane.isChannel && (!modelData.parent_id || modelData.parent_id === modelData.id)
            readonly property bool hasSubject: posted && !!modelData.subject
            readonly property var member: pane.members.find(m => (m.mri || "").toLowerCase() === (modelData.sender_mri || "").toLowerCase()) || null
            width: list.width
            height: heading ? 17.1 + 16 : isFile ? 54 : 12 + textBlock.y + textBlock.height + 8
            function open() {
                if (heading) return
                if (isFile) { Qt.openUrlExternally(modelData.url); return }
                pane.selectedId = modelData.id
                pane.jumpTo(modelData, pane.terms)
            }
            Text {
                visible: hitRow.heading
                x: 12; y: 8; text: hitRow.modelData.heading || ""
                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                lineHeight: 17.1; lineHeightMode: Text.FixedHeight
                Accessible.role: Accessible.Heading
            }
            Rectangle {
                visible: !hitRow.heading
                x: 4; width: list.rowWidth; height: parent.height; radius: 3
                color: hitRow.picked ? theme.pick("#EBEBEB", "#3D3D3D") : rowHover.hovered || (list.activeFocus && list.currentIndex === hitRow.index) ? theme.pick("#FAFAFA", "#2E2E2E") : "transparent"
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { list.currentIndex = hitRow.index; hitRow.open() } }

                // A message.
                Item {
                    visible: !hitRow.isFile
                    x: 8; y: 12; width: parent.width - 16; height: parent.height - 12
                    Avatar {
                        size: 28
                        name: hitRow.modelData.sender_name || ""
                        photoId: hitRow.modelData.sender_mri || ""
                        presence: hitRow.member ? hitRow.member.presence || "" : ""
                    }
                    FluentIcon {
                        visible: hitRow.posted
                        x: 41; y: 1; size: 16; name: "textbox-20"; color: theme.textStrong
                    }
                    Text {
                        x: hitRow.posted ? 59.1 : 40; width: parent.width - x - timeText.width - 8; height: 16
                        text: (hitRow.me ? "You" : hitRow.modelData.sender_name || "") + (hitRow.posted ? " posted" : "")
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    Text {
                        visible: hitRow.hasSubject
                        x: 41; y: 24.2; width: parent.width - 41
                        textFormat: Text.RichText
                        text: hitRow.hasSubject ? theme.markTerms(pane.escaped(hitRow.modelData.subject), pane.terms) : ""
                        elide: Text.ElideRight; maximumLineCount: 1
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    }
                    Text {
                        id: timeText
                        anchors.right: parent.right; height: 16
                        text: pane.when(hitRow.modelData.time)
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    Text {
                        id: textBlock
                        x: hitRow.posted ? 41 : 40; y: hitRow.hasSubject ? 48.2 : hitRow.posted ? 24.2 : 18.7; width: parent.width - x
                        textFormat: Text.RichText
                        text: pane.clamped(hitRow.modelData.text, width)
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Rectangle { y: parent.height - 0.67; width: parent.width; height: 0.67; color: theme.pick("#D1D1D1", "#525252") }
                }

                // A file.
                Item {
                    visible: hitRow.isFile
                    anchors.fill: parent
                    FluentIcon {
                        x: 8; y: 11; size: 32
                        name: pane.fileIcon(hitRow.modelData.file_type, hitRow.modelData.file_name, 32)
                    }
                    Text {
                        x: 55; y: 8; width: parent.width - 55 - 48; height: 20
                        text: hitRow.modelData.file_name || ""
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Text {
                        x: 55; y: 30; width: parent.width - 55 - 48; height: 16
                        textFormat: Text.StyledText; elide: Text.ElideRight
                        text: pane.bolded((hitRow.modelData.sender_name || "") + ", " + pane.when(hitRow.modelData.time))
                        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    }
                    Rectangle {
                        id: moreBtn
                        x: parent.width - 8 - 32; y: 11; width: 32; height: 32; radius: 4
                        color: mh.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: fileMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options"
                        MenuPopup {
                            id: fileMenu
                            x: parent.width - width; y: parent.height + 4; width: 180
                            readonly property bool loop: /\.(loop|fluid)$/i.test(hitRow.modelData.file_name || "")
                            items: [{ label: "Open in Browser", icon: "globe-20" }]
                                .concat(loop ? [] : [{ label: "Download", icon: "arrow-download-20" }])
                                .concat([{ label: "Copy link", icon: "link-20" }, { label: "Favorite", icon: "star-20" }])
                            onPicked: i => {
                                close()
                                const label = items[i].label
                                if (label === "Open in Browser") Qt.openUrlExternally(hitRow.modelData.url)
                                else if (label === "Download") backend.findFileAction("download", hitRow.modelData.file_url || hitRow.modelData.url)
                                else if (label === "Copy link") { backend.copyText(hitRow.modelData.url); backend.statusText = "Link copied" }
                                else backend.findFileAction("favorite", hitRow.modelData.file_url || hitRow.modelData.url)
                            }
                        }
                    }
                }
            }
            Accessible.role: heading ? Accessible.Heading : Accessible.ListItem
            Accessible.name: heading ? modelData.heading : isFile ? (modelData.file_name || "") + " by " + (modelData.sender_name || "")
                                    : (me ? "You" : modelData.sender_name || "") + ", " + pane.when(modelData.time) + ", " + (modelData.text || "")
            Accessible.description: "Press enter to open message, then Escape to return"
        }
        footer: Item {
            width: list.width; height: pane.result && pane.result.loading && pane.hits.length ? 40 : 8
            BusyIndicator { anchors.centerIn: parent; width: 24; height: 24; running: parent.height > 8; visible: running }
        }
    }
    BusyIndicator {
        anchors.horizontalCenter: parent.horizontalCenter; y: 200
        width: 32; height: 32
        running: !pane.idle && !!pane.result && pane.result.loading && !pane.hits.length
        visible: running
    }

    // Before a search, and when nothing is found.
    Item {
        id: emptyState
        readonly property bool none: !pane.idle && !!pane.result && !pane.result.loading && !pane.hits.length
        visible: pane.idle || none
        x: 0.67; width: parent.width - 0.67; y: pane.listY; height: parent.height - y - feedbackBar.height
        Image {
            id: art
            anchors.horizontalCenter: parent.horizontalCenter; y: 12.3; width: 220; height: 220
            sourceSize: Qt.size(440, 440)
            source: emptyState.none ? "../assets/illustrations/search-exclamation-l-standard.svg" : "../assets/illustrations/search-keywords-l-standard.svg"
        }
        Text {
            id: emptyTitle
            anchors.horizontalCenter: parent.horizontalCenter; y: art.y + art.height + 10; width: 220
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            text: emptyState.none ? (pane.result && pane.result.error ? "Something went wrong" : "We couldn't find any results in this " + pane.place) : "Search in this " + pane.place
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: emptyTitle.y + emptyTitle.height + 10; width: 228
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            text: emptyState.none ? (pane.result && pane.result.error ? pane.result.error : "Check for spelling, try another search keyword, or search in another " + pane.place + ".")
                                  : "Find messages, files, and URLs shared in this " + pane.place + "."
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
    }

    // Teams' "Send feedback 👍 👎" footer (36 tall, #FAFAFA, padding 8 12
    // 8 0, at the right: "Send feedback" 12 #616161, then This was helpful
    // and Didn't help, 16 px, 8 apart). They open OST's feedback form
    // (Give a compliment / Report a problem) with the search filled in.
    Rectangle {
        id: feedbackBar
        x: 0.67; width: parent.width - 0.67; height: 36
        anchors.bottom: parent.bottom
        color: theme.pick("#FAFAFA", "#1A1A1A")
        function context() {
            const bits = [pane.files ? "Files" : "Messages"]
            if (pane.dateKey) bits.push(pane.dateLabel())
            if (pane.person) bits.push("From " + pane.person.name)
            if (pane.attachment) bits.push("Attachment")
            if (pane.mentions) bits.push("Mentions")
            if (pane.fileType) bits.push(pane.typeNames[pane.fileType])
            const n = pane.result ? pane.result.total : 0
            return "Find in " + pane.place + (pane.query ? ": \u201c" + pane.query + "\u201d" : "") + " (" + bits.join(", ") + "), " + n + (n === 1 ? " result" : " results")
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text { height: 20; verticalAlignment: Text.AlignVCenter; text: "Send feedback"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Repeater {
                model: [{ icon: "thumb-like-20", name: "This was helpful", kind: "compliment", ink: theme.pick("#BDBDBD", "#5C5C5C") },
                        { icon: "thumb-dislike-20", name: "Didn't help", kind: "problem", ink: theme.textStrong }]
                Item {
                    required property var modelData
                    width: 16; height: 20
                    FluentIcon { y: 2; size: 16; name: parent.modelData.icon; color: thh.hovered ? theme.brand : parent.modelData.ink }
                    HoverHandler { id: thh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.requestFeedback(parent.modelData.kind, "Find in " + pane.place, feedbackBar.context()) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                }
            }
        }
    }

    // A file's type icon (Fluent's file type icons).
    function fileIcon(type, name, size) {
        const t = String(type || String(name || "").split(".").pop()).toLowerCase()
        const kind = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                   : t === "pdf" ? "pdf" : t === "one" || t === "onepart" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                   : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp"].indexOf(t) >= 0 ? "photo" : "genericfile"
        return "ft-" + kind + "-" + size
    }

    function runForTest(q) { field.text = q; typing.stop(); run() }
    function datePopForTest() { const c = chips.children.find(c => c.name && c.name.startsWith("Date")); if (c) { datePop.anchorTo(c); datePop.open() } }
    function pickDateForTest(k) { datePop.close(); dateKey = k; setActive("date", true); run() }
    function fromPopForTest() { const c = chips.children.find(c => c.name && c.name.startsWith("From")); if (c) { fromPop.anchorTo(c); fromPop.open() } }
    function closePopsForTest() { datePop.close(); fromPop.close() }
    function toggleForTest(k) { if (k === "attachment") attachment = !attachment; else mentions = !mentions; setActive(k, k === "attachment" ? attachment : mentions); run() }
    function chipKeysForTest() { return chipKeys }
}
