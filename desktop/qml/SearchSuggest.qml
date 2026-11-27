import QtQuick
import QtQuick.Controls.Basic

// The title bar search's suggestions under the box, as Teams desktop draws
// them (measured on winpc 2026-11-27, Teams 26304, from its DOM at 1x):
// a white flyout (radius 4, Fluent shadow 16) as wide as the box, at most
// 70% of the window tall. On top the scope pills (Messages, Files,
// Channels, Group chats, Meetings, Images: 24 tall, radius 32, #E8EBFA,
// 12/14 text 10.7 in, 8 apart, at 17.7, 12.7); then the groups, which
// scroll: nothing typed, "People" (a row of 80-wide cells, 88 apart: the
// 32 px picture over the first name and the rest, 12 px) and
// "Suggestions"; typing, the top hits (no heading), "Recent messages" (5
// and "See more messages for …"), People, Files, Channels, Teams, Group
// Chats, Meetings and Recent images. Headings are 12/17 #616161 in a 37 px
// band; rows put a 32 px picture at 17.7 and the text (14/20, the typed
// words bold; second lines 11/16 #424242) at 59.7. At the bottom, over a
// 0.67 #F0F0F0 line: "Tip: Go right to a chat or channel (Ctrl+G)" (44)
// with nothing typed, else "Press Enter to view all results" (32, brand
// semibold, Enter in a key box); then "Send feedback" with the thumbs
// (12/20 #616161, 21.3 px buttons, 32 tall).
FluentSurface {
    id: root
    /// What's typed (without an "is:" scope).
    property string query: ""
    /// The chosen scope pill's key ("" for none).
    property string scope: ""
    /// The service's answer: {query, groups: [{id, title, items}]}.
    property var reply: ({})
    /// The chat list, for chats the service names only by thread.
    property var chats: []
    /// Ask Copilot about the query (a licensed user, two words or more).
    property bool copilot: false
    property real maxHeight: 476
    /// The keyboard's pick (an index into `options`), -1 for none.
    property int current: -1
    signal activate(var item)
    signal pickScope(string key)
    signal feedback(string kind)

    depth: 16; radius: 4; color: theme.menu
    height: Math.min(maxHeight, 51.3 + groupCol.height + 2 + footer.height + 4)

    // Teams' domainPillsOrder (ECS autosuggest), outside an app.
    readonly property var pills: [
        { key: "messages", label: qsTr("Messages") }, { key: "files", label: qsTr("Files") },
        { key: "channels", label: qsTr("Channels") }, { key: "groupchats", label: qsTr("Group chats") },
        { key: "meetings", label: qsTr("Meetings") }, { key: "images", label: qsTr("Images") }
    ]
    readonly property bool typed: query.trim().length > 0
    // The service's groups for what's in the box now (an older answer
    // waits for the new one).
    readonly property var groups: {
        const r = root.reply || {}
        if (String(r.query || "").trim() !== root.query.trim()) return []
        const gs = (r.groups || []).map(g => ({ id: g.id, title: g.title, items: g.items.slice() }))
        if (root.copilot && root.typed && root.query.trim().split(/\s+/).length > 1) {
            const ask = { kind: "copilot", title: root.query.trim() }
            const top = gs.find(g => g.id === "TOPHITS")
            if (top) top.items.push(ask); else gs.unshift({ id: "TOPHITS", title: "", items: [ask] })
        }
        // The People row shows as many as fit.
        const row = gs.find(g => g.id === "PEOPLE" && !root.typed)
        if (row) row.items = row.items.slice(0, Math.max(1, Math.floor((root.width - 32) / 88)))
        // Each item's place among the options (the arrows' order).
        let i = 0
        for (const g of gs) g.items = g.items.map(it => Object.assign({}, it, { _i: i++ }))
        return gs
    }
    // Everything the arrows move through, in order.
    readonly property var options: {
        const out = []
        for (const g of groups) for (const it of g.items) out.push(it)
        return out
    }
    function picked(item) { return root.current >= 0 && !!item && item._i === root.current }
    function move(step) {
        if (!options.length) return
        current = current < 0 ? (step > 0 ? 0 : options.length - 1) : (current + step + options.length) % options.length
    }
    // Keep the keyboard's pick in view.
    onCurrentChanged: if (current >= 0) Qt.callLater(root.showCurrent)
    function findRow(item) {
        for (const c of item.children) {
            if (c.item && c.item.it && c.item.it._i === root.current) return c
            const f = findRow(c)
            if (f) return f
        }
        return null
    }
    function showCurrent() {
        const row = findRow(groupCol)
        if (!row) return
        const y = row.mapToItem(groupCol, 0, 0).y
        if (y < flick.contentY) flick.contentY = y
        else if (y + row.height > flick.contentY + flick.height) flick.contentY = Math.min(y + row.height - flick.height, Math.max(0, flick.contentHeight - flick.height))
    }
    onQueryChanged: current = -1
    onReplyChanged: current = -1

    // Bold the typed words where a word starts with them (Teams marks
    // "release" in "Software_release": "_" separates words too).
    function esc(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function bold(t) {
        const words = root.query.trim().split(/\s+/).filter(w => !!w).map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
        const e = esc(t)
        if (!words.length) return e
        const re = new RegExp("(^|[^A-Za-z0-9])(" + words.map(w => esc(w)).join("|") + ")", "gi")
        return e.replace(/(&[a-z]+;)|([^&]+)/g, (m, ent, text) => ent ? ent : text.replace(re, "$1<b>$2</b>"))
    }
    function chatName(item) {
        if (item.title) return item.title
        const c = root.chats.find(c => c.id === item.thread)
        return c ? c.name : ""
    }
    function fileIcon(ext) {
        const t = String(ext || "").toLowerCase()
        const kind = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                   : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                   : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp"].indexOf(t) >= 0 ? "photo"
                   : ["mp4", "mov", "wmv", "avi", "mkv", "webm", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + kind + "-32"
    }
    // A meeting's time line: "Now" or "in N minutes" (brand) for one on or
    // starting within 15 minutes, else "Friday 10:00 AM - 10:30 AM".
    function eventTime(e) {
        const s = new Date(e.start), en = new Date(e.end), now = new Date()
        if (isNaN(s) || isNaN(en)) return ""
        if (s <= now && en >= now) return "<font color='" + theme.brand + "'>" + qsTr("Now") + "</font>"
        const mins = Math.floor((s - now) / 60000)
        if (s > now && mins <= 15)
            return "<font color='" + theme.brand + "'>" + (mins > 1 ? qsTr("in %1 minutes").arg(mins) : qsTr("in %1 minute").arg(mins)) + "</font>"
        return esc(qsTr("%1 %2 - %3").arg(theme.fmtDate(s, "dddd")).arg(theme.time(s)).arg(theme.time(en)))
    }
    // A message's date: the time today, else the day (and year before this one).
    function messageDate(iso) {
        const d = new Date(iso), now = new Date()
        if (isNaN(d)) return ""
        if (d.toDateString() === now.toDateString()) return theme.time(d)
        return d.getFullYear() === now.getFullYear() ? theme.dateNoYear(d) : theme.date(d)
    }
    readonly property var metaIcons: ({ attach: "attach-20", image: "image-20", link: "link-16", important: "important-20", mention: "mention-16", urgent: "important-20-filled" })

    // Scope pills; with one chosen, just it, filled, with ×.
    Item {
        id: pillBand
        x: 1.7; y: 4.7; width: parent.width - 3.4; height: 44
        // Pills that don't fit scroll sideways (wheel, drag or the arrows
        // on the focused pill).
        Flickable {
            id: pillFlick
            anchors.fill: parent
            clip: true
            contentWidth: pillRow.width + 32; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            WheelHandler { onWheel: e => pillFlick.contentX = Math.max(0, Math.min(pillFlick.contentWidth - pillFlick.width, pillFlick.contentX - (e.angleDelta.y || e.angleDelta.x) / 2)) }
        Row {
            id: pillRow
            x: 16; y: 8; spacing: 8
            Repeater {
                model: root.scope ? root.pills.filter(p => p.key === root.scope) : root.pills
                Rectangle {
                    id: pill
                    required property var modelData
                    readonly property bool chosen: root.scope === modelData.key
                    height: 24; radius: 12
                    width: pillText.implicitWidth + (chosen ? 38 : 21.3)
                    color: chosen ? theme.brandFill : pillHover.hovered ? theme.pick("#DCE0FA", "#3D3E66", "#1AEBFF") : theme.pick("#E8EBFA", "#2B2B40", "#000000")
                    border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                    Text {
                        id: pillText
                        x: 10.7; anchors.verticalCenter: parent.verticalCenter
                        text: pill.modelData.label
                        font.family: theme.font; font.pixelSize: 12; font.weight: pill.chosen ? Font.DemiBold : Font.Normal
                        color: pill.chosen ? theme.textOnBrand : theme.onFill(pill, theme.text)
                    }
                    FluentIcon { visible: pill.chosen; x: parent.width - 24; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: theme.textOnBrand }
                    HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pickScope(pill.chosen ? "" : pill.modelData.key) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
        }
    }
    function scrollPills(step) { pillFlick.contentX = Math.max(0, Math.min(pillFlick.contentWidth - pillFlick.width, pillFlick.contentX + step * 88)) }
    Rectangle { x: 1.7; y: 50.6; width: parent.width - 3.4; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }

    Flickable {
        id: flick
        x: 1.7; y: 51.3; width: parent.width - 3.4
        height: root.height - y - footer.height - 4
        contentHeight: groupCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        Column {
            id: groupCol
            width: flick.width
            Repeater {
                model: root.groups
                Column {
                    id: grp
                    required property var modelData
                    width: groupCol.width
                    Item {
                        visible: !!grp.modelData.title
                        width: parent.width; height: visible ? 37.1 : 0
                        Text { x: 16; y: 12; text: grp.modelData.title || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    }
                    // The People row (nothing typed) and Recent images are rows of cells.
                    Row {
                        visible: (grp.modelData.id === "PEOPLE" && !root.typed) || grp.modelData.id === "IMAGES"
                        x: 16; spacing: grp.modelData.id === "IMAGES" ? 11.3 : 8
                        height: visible ? (grp.modelData.id === "IMAGES" ? 117.3 : 84) : 0
                        Repeater {
                            model: parent.visible ? grp.modelData.items : []
                            Loader {
                                required property var modelData
                                sourceComponent: modelData.kind === "image" ? imageCell : personCell
                                onLoaded: item.it = modelData
                            }
                        }
                    }
                    Repeater {
                        model: (grp.modelData.id === "PEOPLE" && !root.typed) || grp.modelData.id === "IMAGES" ? [] : grp.modelData.items
                        Loader {
                            required property var modelData
                            width: groupCol.width
                            sourceComponent: ({ message: messageRow, event: eventRow, copilot: copilotRow })[modelData.kind] || plainRow
                            onLoaded: item.it = modelData
                        }
                    }
                }
            }
        }
    }

    // A row's hover and keyboard fill.
    component RowFill: Rectangle {
        property var it
        anchors.fill: parent
        readonly property bool on: rowHover.hovered || root.picked(it)
        color: on ? theme.menuHover : "transparent"
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.activate(it) }
    }
    // A 32 px #F0F0F0 circle with a 16 px glyph.
    component GlyphCircle: Rectangle {
        property string icon
        width: 32; height: 32; radius: 16
        color: theme.pick("#F0F0F0", "#333333", "#000000")
        border.width: theme.highContrast ? 0.67 : 0; border.color: "#FFFFFF"
        FluentIcon { anchors.centerIn: parent; name: parent.icon; size: 16; color: theme.onFill(parent, theme.textStrong) }
    }

    // Chats, teams, channels, people, files, texts, "See more messages".
    Component {
        id: plainRow
        Item {
            id: pr
            property var it: ({})
            readonly property string kind: it.kind || ""
            readonly property bool glyph: kind === "text" || kind === "pcs" || kind === "seemore"
            readonly property string sub: kind === "person" ? (it.sub || "") : kind === "channel" ? (it.sub || "") : (it.sub || "")
            width: parent ? parent.width : 0
            height: glyph ? 44 : kind === "person" || kind === "channel" || kind === "team" ? 48 : 50
            RowFill { it: pr.it }
            Avatar {
                visible: !pr.glyph && pr.kind !== "file" && !(pr.kind === "community" && !!pr.it.avatar)
                x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32
                colorful: pr.kind === "community"; squareRadius: 4
                name: pr.kind === "chat" ? root.chatName(pr.it) : pr.kind === "channel" ? (pr.it.sub || pr.it.title || "") : (pr.it.plain_name || pr.it.title || pr.it.name || "")
                photoId: pr.kind === "person" ? (pr.it.mri || "") : pr.kind === "chat" && !pr.it.meeting ? "chat:" + pr.it.thread : (pr.kind === "team" || pr.kind === "channel") && pr.it.group ? "team:" + pr.it.group : ""
                square: pr.kind === "team" || pr.kind === "channel" || pr.kind === "community"
                group: pr.kind === "chat" && !pr.it.meeting
                meeting: pr.kind === "chat" && !!pr.it.meeting
            }
            FluentIcon { visible: pr.kind === "file"; x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: root.fileIcon(pr.it.ext) }
            Image {
                visible: pr.kind === "community" && !!pr.it.avatar
                x: 16; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32
                source: { backend.emoticonsVersion; const a = pr.it.avatar; return pr.kind === "community" && a ? backend.cardImage(a.replace("{width}", "64").replace("{height}", "64")) : "" }
                fillMode: Image.PreserveAspectCrop
                RoundedCorners { anchors.fill: parent; radius: 4; background: theme.menu }
            }
            GlyphCircle {
                visible: pr.glyph
                x: 16; anchors.verticalCenter: parent.verticalCenter
                icon: pr.kind === "text" && pr.it.history ? "history-16" : "search-16"
            }
            Column {
                x: 58; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    text: pr.kind === "pcs" ? qsTr("%1 in all results").arg("<b>" + root.esc(pr.it.title) + "</b>")
                        : pr.kind === "seemore" ? root.esc(qsTr("See more messages for")) + " <b>" + root.esc(pr.it.query) + "</b>"
                        : pr.kind === "chat" ? root.bold(root.chatName(pr.it))
                        : root.bold(pr.it.name || pr.it.title || "")
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(pr, theme.text)
                }
                Text {
                    visible: !pr.glyph && pr.sub.length > 0
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    text: pr.kind === "person" ? root.bold(pr.sub) : root.esc(pr.sub)
                    font.family: theme.font; font.pixelSize: pr.kind === "person" ? 12 : 11
                    color: theme.onFill(pr, pr.kind === "person" ? theme.text : theme.textStrong)
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: pr.kind === "pcs" ? qsTr("%1 in all results").arg(pr.it.title) : pr.kind === "seemore" ? qsTr("See more messages for") + " " + pr.it.query : (pr.kind === "chat" ? root.chatName(pr.it) : (pr.it.name || pr.it.title || "")) + (pr.sub ? ", " + pr.sub : "")
        }
    }
    // A meeting: its date box, subject, time line | who invited whom.
    Component {
        id: eventRow
        Item {
            id: er
            property var it: ({})
            width: parent ? parent.width : 0; height: 50
            RowFill { it: er.it }
            Rectangle {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 4; color: "transparent"
                border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                Column {
                    anchors.centerIn: parent
                    Text { anchors.horizontalCenter: parent.horizontalCenter; height: 14; verticalAlignment: Text.AlignVCenter; text: new Date(er.it.start).getDate(); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; height: 14; verticalAlignment: Text.AlignVCenter; text: theme.fmtDate(new Date(er.it.start), "MMM"); font.family: theme.font; font.pixelSize: 10; color: theme.text }
                }
            }
            Column {
                x: 58; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter
                Row {
                    spacing: 4
                    Text { textFormat: Text.StyledText; text: root.bold(er.it.title); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(er, theme.text) }
                    FluentIcon { visible: !!er.it.recurring; anchors.verticalCenter: parent.verticalCenter; name: "arrow-repeat-all-16"; size: 16; color: theme.textStrong }
                }
                Row {
                    spacing: 6
                    Text { textFormat: Text.StyledText; text: root.eventTime(er.it); lineHeight: 17; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(er, theme.text) }
                    Rectangle { visible: !!er.it.who; anchors.verticalCenter: parent.verticalCenter; width: 0.67; height: 14; color: theme.pick("#D1D1D1", "#666666", "#FFFFFF") }
                    Text { text: er.it.who || ""; lineHeight: 17; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(er, theme.text) }
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: er.it.title + " " + er.it.who
        }
    }
    // A message: the sender's picture; "Name: text" (two lines at most);
    // where (a chat's picture, topic and members; a channel's team
    // picture and "Team > Channel"); the date and its icons on the right.
    Component {
        id: messageRow
        Item {
            id: mr
            property var it: ({})
            width: parent ? parent.width : 0
            height: Math.max(56, mtext.height + 5 + 15.7 + 14)
            RowFill { it: mr.it }
            Avatar { x: 16; y: 7; size: 32; name: mr.it.sender || ""; photoId: mr.it.sender_mri || "" }
            Text {
                id: mtext
                x: 58; y: 7; width: parent.width - 58 - 60
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                textFormat: Text.StyledText; lineHeight: 20; lineHeightMode: Text.FixedHeight
                text: root.esc(mr.it.prefix) + root.bold(String(mr.it.title || "").replace(/\s+/g, " ").trim())
                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(mr, theme.text)
            }
            Row {
                x: 58; y: mtext.y + mtext.height + 5; spacing: 4
                readonly property var chat: root.chats.find(c => c.id === mr.it.thread)
                Avatar {
                    visible: !mr.it.one_on_one && (!!mr.it.topic || !!mr.it.channel)
                    anchors.verticalCenter: parent.verticalCenter; size: 18
                    name: mr.it.channel ? String(mr.it.place || "").split(" > ")[0] : (mr.it.topic || "")
                    photoId: mr.it.channel ? (mr.it.group ? "team:" + mr.it.group : "") : "chat:" + mr.it.thread
                    square: !!mr.it.channel; squareRadius: 2
                    group: !mr.it.channel
                }
                Text { visible: !!mr.it.topic; textFormat: Text.StyledText; text: root.bold(mr.it.topic || ""); font.family: theme.font; font.pixelSize: 11; color: theme.textSecondary }
                Rectangle { visible: !!mr.it.topic && !!mr.it.place; anchors.verticalCenter: parent.verticalCenter; width: 0.67; height: 12; color: theme.pick("#D1D1D1", "#666666", "#FFFFFF") }
                Text { textFormat: Text.StyledText; text: root.bold(mr.it.place || ""); font.family: theme.font; font.pixelSize: 11; color: theme.textSecondary }
            }
            Column {
                anchors.right: parent.right; anchors.rightMargin: 12; y: 7
                spacing: 6
                Text { anchors.right: parent.right; height: 20; verticalAlignment: Text.AlignVCenter; text: root.messageDate(mr.it.time); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                Row {
                    anchors.right: parent.right; spacing: 8
                    Repeater {
                        model: mr.it.icons || []
                        FluentIcon { required property string modelData; name: root.metaIcons[modelData] || ""; size: 16; color: theme.textSecondary }
                    }
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: qsTr("Message") + " " + mr.it.prefix + mr.it.title
        }
    }
    // Teams' "Ask Copilot about <query>" (measured on winpc 2026-11-20).
    Component {
        id: copilotRow
        Item {
            id: cr
            property var it: ({})
            width: parent ? parent.width : 0; height: 50
            RowFill { it: cr.it }
            Rectangle {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 16
                color: theme.pick("#F0F0F0", "#333333", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF"); border.width: theme.highContrast ? 0.67 : 0
                FluentIcon { anchors.centerIn: parent; name: "mo-copilot"; size: 16; color: theme.onFill(parent, theme.textStrong) }
            }
            Text {
                x: 58; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText; elide: Text.ElideRight
                text: qsTr("Ask Copilot about") + " <b>" + root.esc(cr.it.title) + "</b>"
                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(cr, theme.text)
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: qsTr("Ask Copilot about") + " " + cr.it.title
        }
    }
    // A person in the People row: picture over the name in two lines.
    Component {
        id: personCell
        Item {
            id: pc
            property var it: ({})
            readonly property string nm: it.plain_name || it.name || ""
            readonly property string first: nm.split(" ")[0]
            readonly property string rest: (nm.indexOf(" ") > 0 ? nm.slice(nm.indexOf(" ") + 1) : "") + (it.you ? (nm.indexOf(" ") > 0 ? " " : "") + qsTr("(You)", "autosuggest:k9m83y7y2") : "")
            width: 80; height: 84
            Rectangle {
                anchors.fill: parent; radius: 4
                color: pch.hovered || root.picked(pc.it) ? theme.menuHover : "transparent"
            }
            Avatar { x: 24; y: 4; size: 32; name: pc.nm; photoId: pc.it.mri || "" }
            Text { x: 0; y: 41; width: 80; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: pc.first; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Text { x: 0; y: 58; width: 80; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: pc.rest; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            HoverHandler { id: pch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.activate(pc.it) }
            Accessible.role: Accessible.ListItem
            Accessible.name: qsTr("Person") + " " + nm
        }
    }
    // A recent image: a 101.3 px tile (radius 8, 0.67 #E0E0E0).
    Component {
        id: imageCell
        Rectangle {
            id: ic
            property var it: ({})
            y: 8; width: 101.3; height: 101.3; radius: 8
            color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
            border.width: 0.67; border.color: ich.hovered ? theme.brand : theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
            Image {
                anchors.fill: parent; anchors.margins: 0.67
                fillMode: Image.PreserveAspectCrop
                source: ic.it.src || ""
                asynchronous: true
                RoundedCorners { anchors.fill: parent; radius: 8; background: theme.menu }
            }
            HoverHandler { id: ich; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.activate(ic.it) }
            Accessible.role: Accessible.ListItem
            Accessible.name: qsTr("Image")
        }
    }

    // The bottom: the tip or "Press Enter", then Send feedback.
    Column {
        id: footer
        x: 1.7; y: root.height - height - 4; width: parent.width - 3.4
        Rectangle { width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }
        Item {
            id: tip
            visible: !root.typed && !root.scope
            width: parent.width; height: visible ? 44 : 0
            RowFill { it: ({ kind: "tip" }) }
            GlyphCircle { x: 16; anchors.verticalCenter: parent.verticalCenter; icon: "lightbulb-20" }
            Text {
                x: 58; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Tip: Go right to a chat or channel (%1)").arg("Ctrl+G")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: qsTr("Tip: Go right to a chat or channel (%1)").arg("Ctrl+G")
        }
        Item {
            visible: root.typed
            width: parent.width; height: visible ? 32 : 0
            Rectangle { anchors.fill: parent; color: enterHover.hovered ? theme.menuHover : "transparent" }
            Row {
                anchors.centerIn: parent; spacing: 4
                readonly property var parts: qsTr("Press %1 to view all results").split("%1")
                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parts[0].trim(); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: keyText.implicitWidth + 17.3; height: 20; radius: 2; color: "transparent"
                    border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Text { id: keyText; anchors.centerIn: parent; text: qsTr("Enter"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: (parent.parts[1] || "").trim(); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand }
            }
            HoverHandler { id: enterHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.activate({ kind: "enter" }) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Press enter to view all results")
        }
        Item {
            width: parent.width; height: 32
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { height: 21.3; verticalAlignment: Text.AlignVCenter; rightPadding: 6; text: qsTr("Send feedback"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                Repeater {
                    model: [{ icon: "thumb-like-16", name: qsTr("This was helpful"), kind: "compliment" }, { icon: "thumb-dislike-16", name: qsTr("Didn't help"), kind: "problem" }]
                    Rectangle {
                        required property var modelData
                        width: 21.3; height: 21.3; radius: 4
                        color: thh.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; size: 16; name: parent.modelData.icon; color: thh.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: thh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.feedback(parent.modelData.kind) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name
                    }
                }
            }
        }
    }
}
