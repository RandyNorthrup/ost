import QtQuick
import QtQuick.Controls.Basic

// Teams' quick-start dialog for an app you have ("Let's go": the app
// details dialog's ContextlessConfigPicker view), as a Store card of an
// app you have opens it (Teams 26304, measured on testpc1 2026-11-27 over
// read-only CDP; docs/spec/store.md §5). CSS px, dialog coordinates:
// - 520 wide, 720 tall (less when the window is lower), radius 8; 620
//   tall when the app can't be used in a channel, chat or meeting; the
//   close button (32) at (432, 24).
// - A 486 x 136 band at (16, 0) shaded from the app's accent colour (0 to
//   20% alpha, top to bottom; #242424 for a white or missing accent) under
//   a white-clear-white horizontal veil; the app's 96 px picture at
//   (211, 56); its name 16/22.86 semibold at 164; "Let's go" 28/40
//   semibold at 232.8; the line under it 15/21.43 at 280.8 (350 wide).
// - Open (173 x 32, brand, radius 4) at 334.3 for an app you can use on
//   your own, then "Or choose a place to use the app" (15/21.43) at 390.3.
// - The search (456 x 40 at (32, 435.7), #F5F5F5, radius 4, a 16 px
//   search glyph at 43) names the places the app supports ("Search for a
//   channel, chat or meeting").
// - Per place: "Select a channel" / "Select a chat" / "Select a meeting"
//   (14/20 #424242) and "View more" (14/20, brand) 20 below, then three
//   56 px rows from 32 below: a 16 px radio at 52, a 32 px picture at 88
//   (the team's square picture, a chat's round one, a meeting's calendar)
//   and the name 14/20 at 132 (a channel's team 12/16 under it). A picked
//   row is #EBEBEB.
// - Scrolled past 240 (220 without Open), a 486 x 88 header at (16, 0)
//   with the app's 48 px picture (radius 6) at (32, 20) and "Choose where
//   to get started" 16/22 semibold at (96, 33), over a #E0E0E0 line.
// - A pick brings the footer (486 x 72 at the bottom, #E0E0E0 line on
//   top) with Go (96 x 40, brand) 16 from its right; View more shows the
//   place's whole list under a header naming it, with Back in the footer.
// Places come as Teams' appInstallOptions resolver makes them: your
// teams' channels (recently read first, then favourite teams, General, the
// teams' order and name), your chats (no bots, meetings, hidden or system
// threads) and your calendar's Teams meetings (upcoming first) with your
// other meeting chats after them.
Popup {
    id: root
    /// The Store card's app ({id, name, icon, config_url, features}).
    property var app: null
    /// Go: use the app there ({kind: "channel" | "chat" | "meeting", id,
    /// name, teamId, teamThread}); `info` adds the app's places.
    signal useIn(var app, var place)
    /// Open: the app on your own.
    signal openApp(string appId, string name)
    modal: true; focus: true
    padding: 0
    width: Math.min(520, (parent ? parent.width : 520) - 32)
    height: Math.min(shortDialog ? 620 : 720, parent ? parent.height : 720)
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }

    readonly property var info: { const r = backend.appDetailsJson ? JSON.parse(backend.appDetailsJson) : null; return r && app && r.app === app.id ? r : null }
    readonly property var d: info && info.details ? info.details : null
    readonly property var places: d && d.places ? d.places : ({})
    /// The places it supports, in Teams' order.
    readonly property var kinds: ["channel", "chat", "meeting"].filter(k => k === "channel" ? !!places.team : k === "chat" ? !!places.chat : !!places.meeting)
    readonly property bool personal: !!places.personal
    /// Teams' short dialog: nothing but Open.
    readonly property bool shortDialog: !!d && kinds.length === 0
    /// "", or the place whose whole list shows (Teams' L2).
    property string expanded: ""
    property var picked: null
    property string query: ""
    property var meetings: []
    readonly property string meetingsTag: "appplaces" + Math.floor(Math.random() * 1e9).toString(36)

    function show(a) {
        app = a; expanded = ""; picked = null; query = ""; search.text = ""
        flick.contentY = 0
        backend.appDetailsLoad(a.id)
        backend.eventsRequest("appPlaceMeetings", meetingsTag, "{}")
        open()
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id !== root.meetingsTag) return
            try { const v = JSON.parse(json); root.meetings = v.meetings || [] } catch (e) { root.meetings = [] }
        }
    }

    // Teams' search: the words (lower case, each once; one-letter words
    // only first), and a place matches when any is in its names.
    readonly property var tokens: { const w = query.trim().toLowerCase().split(/\s+/).filter(x => x); return w.filter((x, i) => w.indexOf(x) === i && (x.length > 1 || i === 0)) }
    function matches(texts) { return tokens.reduce((n, t) => n + (texts.some(s => String(s || "").toLowerCase().indexOf(t) >= 0) ? 1 : 0), 0) }
    function searched(list) {
        if (!tokens.length) return list
        return list.map((p, i) => ({ p: p, n: matches([p.name, p.sub]), i: i })).filter(x => x.n > 0).sort((a, b) => b.n - a.n || a.i - b.i).map(x => x.p)
    }

    readonly property var teamsList: { try { return JSON.parse(backend.teamsJson || "[]") } catch (e) { return [] } }
    readonly property var chatsList: { try { return JSON.parse(backend.chatsJson || "[]") } catch (e) { return [] } }
    /// Why a channel can't take the app (Teams' unsupported text), or "".
    function unsupported(t, c) {
        if (t.archived || c.archived) return qsTr("Apps can't be added to archived channels. Select an active channel.")
        if (t.role !== "admin" && t.member_apps === false) return qsTr("Permissions needed. Ask a team owner to add the app to this channel.")
        if (t.role === "guest" && !t.guest_apps) return qsTr("Permission needed. Ask a team member to add this app to the channel.")
        if (c.channel_type === 1 && !places.private_channels) return qsTr("App isn’t supported in private channels. Select another channel.")
        if (c.channel_type === 2 && !places.shared_channels) return qsTr("App isn’t supported in shared channels. Select another channel.")
        return ""
    }
    readonly property var channels: {
        const out = []
        teamsList.forEach((t, order) => (t.channels || []).forEach(c => out.push({
            kind: "channel", id: c.id, name: c.name || (c.general ? qsTr("General") : ""), sub: t.name, teamId: t.id, teamThread: t.thread_id,
            teamName: t.name, read: c.read_ms || 0, favorite: !!t.favorite, general: !!c.general, order: order, why: unsupported(t, c) })))
        return out.sort((a, b) => b.read - a.read || (b.favorite - a.favorite) || (b.general - a.general) || a.order - b.order || a.name.localeCompare(b.name))
    }
    function isMeetingChat(c) { return !!c.meeting || String(c.id).indexOf("19:meeting_") === 0 }
    // (Teams leaves out hidden, bot, system and interop threads; an empty
    // chat has nothing to add the app to yet.)
    readonly property var chats: chatsList.filter(c => !c.isSelf && !c.hidden && !c.empty && !String(c.id).startsWith("48:") && !String(c.id).startsWith("19:uni01_")
                                                    && !isMeetingChat(c) && !String(c.peerMri || "").startsWith("28:"))
                                          .map((c, i) => ({ kind: "chat", id: c.id, name: c.name || "", sub: "", chat: c, muted: !!c.muted, i: i }))
                                          .sort((a, b) => (a.muted - b.muted) || a.i - b.i)
    readonly property var meetingPlaces: {
        const known = {}
        chatsList.forEach(c => { known[c.id] = c })
        const channelIds = {}
        teamsList.forEach(t => (t.channels || []).forEach(c => { if (!t.archived) channelIds[c.id] = t }))
        const out = [], seen = {}
        for (const m of meetings) {
            if (m.chat_id) {
                if (!known[m.chat_id] || seen[m.chat_id]) continue
                seen[m.chat_id] = true
                out.push({ kind: "meeting", id: m.chat_id, name: m.title, sub: "" })
            } else if (channelIds[m.channel_id]) {
                const t = channelIds[m.channel_id]
                out.push({ kind: "meeting", id: m.channel_id, messageId: m.message_id, name: m.title, sub: "", teamId: t.id, teamThread: t.thread_id, channelMeeting: true })
            }
        }
        // Meeting chats not on the calendar follow.
        for (const c of chatsList) if (isMeetingChat(c) && !seen[c.id] && !c.hidden) { seen[c.id] = true; out.push({ kind: "meeting", id: c.id, name: c.name || "", sub: "" }) }
        return out
    }
    function listOf(kind) { return searched(kind === "channel" ? channels : kind === "chat" ? chats : meetingPlaces) }
    function title(kind) { return kind === "channel" ? qsTr("Select a channel") : kind === "chat" ? qsTr("Select a chat") : qsTr("Select a meeting") }
    function heading(kind) { return kind === "channel" ? qsTr("Channels") : kind === "chat" ? qsTr("Chats") : qsTr("Meetings") }
    readonly property string placeholder: {
        const k = expanded ? [expanded] : kinds
        if (k.length === 1) return k[0] === "channel" ? qsTr("Search for a channel") : k[0] === "chat" ? qsTr("Search for a chat") : qsTr("Search for a meeting")
        if (k.length === 2) return k.indexOf("channel") < 0 ? qsTr("Search for a chat or meeting") : k.indexOf("chat") < 0 ? qsTr("Search for a channel or meeting") : qsTr("Search for a channel or chat")
        return qsTr("Search for a channel, chat or meeting")
    }
    readonly property string subText: personal && kinds.length ? qsTr("How would you like to use this app today?")
                                      : personal ? qsTr("Let's head straight to the app ...")
                                      : kinds.length ? qsTr("Choose a place to use the app.")
                                      : qsTr("This app is not available. Please check with your admin for more details")
    readonly property color accent: { const a = d && d.accent_color ? String(d.accent_color) : ""; return /^#[0-9a-f]{6}$/i.test(a) && a.toUpperCase() !== "#FFFFFF" ? a : "#242424" }
    readonly property bool sticky: !expanded && flick.contentY > (personal ? 240 : 220)

    function go() {
        if (!picked || !app) return
        const a = Object.assign({}, app, { team_tab: !!places.team_tab, chat_tab: !!places.chat_tab, icon: app.icon || (d ? d.icon : "") })
        const p = picked
        close()
        root.useIn(a, p)
    }

    onClosed: { picked = null; expanded = "" }

    // A place's row: the radio, the picture and its names.
    component PlaceRow: Item {
        id: pr
        property var place
        readonly property bool on: !!root.picked && root.picked.id === place.id && root.picked.kind === place.kind && root.picked.messageId === place.messageId
        readonly property bool off: !!place.why
        width: 456; height: 56
        Rectangle { id: hcRow; anchors.fill: parent; radius: 4; color: pr.on ? theme.pick("#EBEBEB", "#383838", "#1AEBFF") : rowHover.hovered && !pr.off ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent" }
        Rectangle {
            x: 20; y: 20; width: 16; height: 16; radius: 8
            color: "transparent"; border.width: 1
            border.color: pr.off ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : pr.on ? theme.brand : theme.onFill(hcRow, theme.pick("#616161", "#D6D6D6", "#FFFFFF"))
            Rectangle { visible: pr.on; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
        }
        Avatar {
            x: 56; y: 12; size: 32
            visible: pr.place.kind !== "meeting"
            square: pr.place.kind === "channel"
            name: pr.place.kind === "channel" ? pr.place.teamName : pr.place.name
            initialsText: pr.place.kind === "channel" ? String(pr.place.teamName || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase() : ""
            photoId: pr.place.kind === "channel" ? "team:" + pr.place.teamId
                     : pr.place.chat ? (pr.place.chat.peerMri || (pr.place.chat.isGroup === true ? "chat:" + pr.place.id : "")) : ""
            group: pr.place.kind === "chat" && !!pr.place.chat && pr.place.chat.isGroup === true && !pr.place.chat.peerMri
        }
        // A meeting: the calendar in a lavender circle.
        Rectangle {
            visible: pr.place.kind === "meeting"
            x: 56; y: 12; width: 32; height: 32; radius: 16
            color: theme.pick("#C5CBFA", "#3D3E78", "#000000")
            FluentIcon { anchors.centerIn: parent; name: "calendar-20"; size: 20; color: theme.pick("#5B5FC7", "#E0E0E0", "#FFFFFF") }
        }
        Column {
            x: 100; width: 356 - 8; anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; elide: Text.ElideRight; text: pr.place.name; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: pr.off ? theme.textTertiary : theme.onFill(hcRow, theme.text) }
            Text {
                visible: !!(pr.place.why || pr.place.sub)
                width: parent.width; elide: Text.ElideRight
                text: pr.place.why || pr.place.sub || ""
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: pr.off ? theme.textTertiary : theme.onFill(hcRow, theme.text)
            }
        }
        HoverHandler { id: rowHover; cursorShape: pr.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !pr.off; onTapped: root.picked = pr.place }
        Accessible.role: Accessible.RadioButton
        Accessible.name: pr.place.name + (pr.place.sub ? ", " + pr.place.sub : "")
        Accessible.checked: pr.on
    }

    // A place's section: its title, View more and its first three rows.
    component PlaceSection: Column {
        id: ps
        property string kind
        readonly property var list: root.listOf(kind)
        visible: list.length > 0
        width: 456
        Item { width: 1; height: 20 }
        Item {
            width: 456; height: 20
            Text { width: 360; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: root.title(ps.kind); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
            Text {
                visible: ps.list.length > 3
                anchors.right: parent.right; height: 20; verticalAlignment: Text.AlignVCenter
                text: qsTr("View more"); font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.expanded = ps.kind; flick.contentY = 0 } }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("View more %1").arg(root.heading(ps.kind))
            }
        }
        Item { width: 1; height: 12 }
        Repeater { model: ps.list.slice(0, 3); PlaceRow { required property var modelData; place: modelData } }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: footer.visible ? footer.height : 0
        contentHeight: body.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Item {
            id: body
            width: root.width
            height: (root.expanded ? listCol.y + listCol.height : placesCol.y + placesCol.height)
            // The accent band and its veil.
            Rectangle {
                visible: !root.expanded
                x: 16; width: parent.width - 34; height: 136
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
                    GradientStop { position: 1; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, theme.highContrast ? 0 : 0.2) }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: theme.surface }
                        GradientStop { position: 0.5; color: "transparent" }
                        GradientStop { position: 1; color: theme.surface }
                    }
                }
            }
            Item {
                visible: !root.expanded
                x: (parent.width - 96) / 2 - 1; y: 56; width: 96; height: 96
                Rectangle { anchors.fill: parent; radius: 48; color: theme.quoteFill }
                Image { anchors.fill: parent; source: root.app ? (root.app.icon || (root.d ? root.d.icon : "")) : ""; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true }
                RoundedCorners { anchors.fill: parent; squircle: true; background: theme.surface }
            }
            Column {
                id: headCol
                visible: !root.expanded
                y: 164; width: parent.width
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.app ? root.app.name : ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; lineHeight: 22.86; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 46 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Let's go"); font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; lineHeight: 40; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Item { width: 1; height: 8 }
                Text { x: (parent.width - width) / 2; width: 350; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: root.subText; font.family: theme.font; font.pixelSize: 15; lineHeight: 21.43; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { visible: root.personal; width: 1; height: 32 }
                Rectangle {
                    id: openButton
                    visible: root.personal
                    x: (parent.width - width) / 2 - 1; width: 173; height: 32; radius: 4
                    color: openHover.pressed ? theme.pick("#444791", "#3D3E78", "#1AEBFF") : openHover.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Open"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                    HoverHandler { id: openHover; cursorShape: Qt.PointingHandCursor; property bool pressed: false }
                    TapHandler { onTapped: { const a = root.app; root.close(); root.openApp(a.id, a.name) } }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Open")
                }
                Item { visible: root.personal && root.kinds.length > 0; width: 1; height: 24 }
                Text { visible: root.personal && root.kinds.length > 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Or choose a place to use the app"); font.family: theme.font; font.pixelSize: 15; lineHeight: 21.43; lineHeightMode: Text.FixedHeight; color: theme.text }
                Item { width: 1; height: 24 }
            }
            // The search, then the places.
            Rectangle {
                id: searchBox
                visible: root.kinds.length > 0
                x: 32; y: root.expanded ? 104 : headCol.y + headCol.height
                width: parent.width - 64; height: 40; radius: 4
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                border.width: theme.highContrast ? 1 : 0; border.color: theme.stroke
                Rectangle { visible: search.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
                FluentIcon { x: 11; anchors.verticalCenter: parent.verticalCenter; name: "search-16"; size: 16; color: theme.textSecondary }
                TextField {
                    id: search
                    x: 29; width: parent.width - 39; anchors.verticalCenter: parent.verticalCenter
                    placeholderText: root.placeholder; placeholderTextColor: theme.textSecondary
                    background: null; font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onTextChanged: queryDelay.restart()
                    Accessible.name: root.placeholder
                }
                Timer { id: queryDelay; interval: 300; onTriggered: root.query = search.text }
            }
            Column {
                id: placesCol
                visible: !root.expanded
                x: 32; y: searchBox.y + searchBox.height
                Repeater { model: root.kinds; PlaceSection { required property var modelData; kind: modelData } }
                Column {
                    visible: root.tokens.length > 0 && root.kinds.every(k => root.listOf(k).length === 0)
                    width: 456; topPadding: 40; spacing: 4
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("No results found"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Check your spelling and spacing or try another search"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                }
            }
            // View more: the place's whole list.
            Column {
                id: listCol
                visible: !!root.expanded
                x: 32; y: searchBox.y + searchBox.height + 12
                Repeater { model: root.expanded ? root.listOf(root.expanded) : []; PlaceRow { required property var modelData; place: modelData } }
            }
        }
    }
    // The header that stays: scrolled down, or a place's whole list.
    Rectangle {
        visible: root.sticky || !!root.expanded
        x: 16; width: parent.width - 34; height: 88
        color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
        Item {
            visible: !root.expanded
            x: 16; y: 20; width: 48; height: 48
            Image { anchors.fill: parent; source: root.app ? (root.app.icon || "") : ""; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true }
            RoundedCorners { anchors.fill: parent; radius: 6; background: theme.surface }
        }
        Text {
            x: root.expanded ? 16 : 80; y: root.expanded ? 0 : 33; height: root.expanded ? 88 : 22; verticalAlignment: Text.AlignVCenter
            text: root.expanded ? root.heading(root.expanded) : qsTr("Choose where to get started")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
    }
    // Close.
    Rectangle {
        x: parent.width - 88; y: 24; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.icon }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }
    // The footer: Back (a place's whole list) and Go (a place picked).
    Rectangle {
        id: footer
        visible: !!root.picked || !!root.expanded
        x: 16; y: parent.height - height; width: parent.width - 34; height: 72
        color: theme.surface
        Rectangle { width: parent.width; height: 1; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
        Row {
            visible: !!root.expanded
            x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-left-20"; size: 20; color: theme.icon }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.expanded = ""; flick.contentY = 0 } }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
        }
        Rectangle {
            visible: !!root.picked
            anchors.right: parent.right; anchors.rightMargin: 0; anchors.verticalCenter: parent.verticalCenter
            width: 96; height: 40; radius: 4
            color: goHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: qsTr("Go"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.go() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Go")
        }
    }

    // Test hooks.
    function stateForTest() {
        return JSON.stringify({ app: app ? app.name : "", loaded: !!d, short: shortDialog, personal: personal, kinds: kinds, placeholder: placeholder, sub: subText,
                                sections: kinds.map(k => [k, listOf(k).slice(0, 3).map(p => p.name + (p.sub ? " (" + p.sub + ")" : "") + (p.why ? " [" + p.why + "]" : ""))]),
                                meetings: meetings.length, picked: picked ? picked.name : "", expanded: expanded, sticky: sticky })
    }
    function pickForTest(kind, i) { const l = listOf(kind); if (l[i]) picked = l[i]; return picked ? picked.name : "" }
    function scrollForTest(y) { flick.contentY = Math.min(y, Math.max(0, flick.contentHeight - flick.height)) }
    function searchForTest(t) { search.text = t; root.query = t }
}
