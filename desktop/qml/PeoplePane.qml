import QtQuick
import QtQuick.Controls

// The meeting People pane (calling-right-side-panel "Participants"), laid
// out as Teams desktop draws it on winpc: a 58 px header, the "Type a name"
// search, then collapsible sections — "Waiting in lobby (n)" (split into
// "Waiting" and "Suspected threats" when the join shield flagged someone)
// and "In this meeting (n)". Section headers are 38 tall, rows 48.
Rectangle {
    id: root
    /// In the call: [{name, id, you, mutedNow, role, hand}].
    property var people: []
    /// Presenters manage what attendees see (a town hall or webinar with
    /// Manage what attendees see on).
    property bool managed: false
    /// The call's chat members ([{mri, name, me, presence}]): those not in
    /// the call show under "People added to the chat (n)", as Teams lists them.
    property var chatMembers: []
    /// Teams' shared display (Optimize for room) pane: the list only, no
    /// close, search, Share invite, lobby or section actions.
    property bool display: false
    /// In the lobby: [{id, name, suspected}].
    property var lobby: []
    property bool meeting: true
    /// A group call (a 1:1 call someone was invited into): Teams' roster
    /// says "Currently in this call", as in a 1:1 call.
    property bool groupCall: false
    /// People can be invited into the call (a 1:1 or group call): the box
    /// is Teams' people picker, "Invite someone or dial a number", and
    /// picking someone rings them in.
    property bool canInvite: false
    signal invite(string mri, string name)
    /// The meeting's link to share; Teams' Share invite shows with it.
    property string inviteUrl: ""
    signal shareInvite()
    /// Teams' Mute all on "In this meeting".
    property bool canMuteAll: false
    /// You can manage others (organizer): the participant ··· menu offers
    /// Mute, Spotlight, roles and Remove; everyone can Pin for themselves.
    property bool canManage: false
    /// Teams Rooms in the meeting can be controlled from here (Teams'
    /// Control Room System: ECS enableRoomRemoteDesktop, desktop, not a
    /// 1:1 call).
    property bool roomRemote: false
    /// Who you pinned (Pin for me), if anyone.
    /// Whom you pinned, and whether the pin area is full (Teams' 9).
    property var pinnedIds: []
    property bool pinningFull: false
    /// A participant ··· menu choice: "mute", "pin", "unpin", "spotlight",
    /// "unspotlight", "attendee", "presenter" or "remove".
    signal participantAction(string action, string id, string name, string stateId)
    /// Participants can be reported (a scheduled meeting, as Report a
    /// concern).
    property bool canReport: false
    signal muteAll()
    /// The header's More actions (roster-header-more-menu), in Teams'
    /// order; each shows only when Teams would show it:
    /// [{k, t, icon}] with k "muteAll", "restrictMic" / "allowMic",
    /// "restrictCamera" / "allowCamera", "lowerHands", "attendance",
    /// "stopSpotlights", "lock" / "unlock".
    property var moreItems: []
    signal moreAction(string action)
    signal closed()
    signal admit(string id, string name)
    /// A suspected guest: Teams asks first.
    signal admitSuspected(string id, string name)
    signal deny(string id, string name)
    /// Teams' Admit all (no suspected guests waiting).
    signal admitAll()
    /// Teams' lobby chat (organizers): with one person waiting the lobby
    /// header's action is Chat (72 x 24, the chat glyph 20 and "Chat" 12,
    /// measured on winpc 2026-11-11).
    property bool lobbyChatAvailable: false
    signal chatLobby()
    /// Admit or deny everyone in a subsection: [{id, name}].
    signal admitEach(var list)
    signal denyEach(var list)

    color: theme.pane
    Rectangle { width: 0.67; height: parent.height; color: theme.divider }

    property string query: ""
    /// Collapsed sections, by key.
    property var collapsed: ({})
    function toggle(key) { const c = Object.assign({}, collapsed); c[key] = !c[key]; collapsed = c }
    function matches(name) { return query.length === 0 || (name || "").toLowerCase().indexOf(query.toLowerCase()) >= 0 }

    /// Raised hands in the order they went up (ids): the rank Teams shows.
    property var handOrder: []
    // Teams' sort (978369): raised hands by rank, then you, then by name.
    function sorted(list) {
        const rank = p => { const i = handOrder.indexOf(p.id === "me" ? root.selfKey : p.id); return p.hand ? (i < 0 ? 999 : i) : -1 }
        return list.slice().sort((a, b) => {
            const ra = rank(a), rb = rank(b)
            if (ra >= 0 || rb >= 0) {
                if (ra < 0) return 1
                if (rb < 0) return -1
                if (ra !== rb) return ra - rb
            }
            if (a.you !== b.you) return a.you ? -1 : 1
            // Sign language mode: the people your role signs with first.
            if (!!a.signFirst !== !!b.signFirst) return a.signFirst ? -1 : 1
            return (a.name || "").localeCompare(b.name || "")
        })
    }
    // Teams' roster sub-items: whoever joined in a Teams Room in the list
    // (mappedToMeetingRoom) nests under that room, the room drawn with a
    // ring and a line down to them.
    function nested(list) {
        const rooms = list.filter(p => !!p.room).map(p => p.id)
        const subOf = p => !p.room && !!p.meetingRoom && rooms.indexOf(p.meetingRoom) >= 0
        const out = []
        sorted(list.filter(p => !subOf(p))).forEach(p => {
            const subs = p.room ? sorted(list.filter(s => subOf(s) && s.meetingRoom === p.id)) : []
            out.push({ kind: "person", p: p, level: 1, parentWithSub: subs.length > 0 })
            subs.forEach((s, i) => out.push({ kind: "person", p: s, level: 1, sub: true, lastSub: i === subs.length - 1 }))
        })
        return out
    }
    /// Your id in handOrder.
    property string selfKey: ""

    // The rows, flattened: sections, subsections and people.
    readonly property var rows: {
        const out = []
        const waiting = lobby.filter(p => !p.suspected && matches(p.name))
        const threats = lobby.filter(p => p.suspected && matches(p.name))
        const lobbyShown = waiting.length + threats.length
        if (lobbyShown > 0 && !display) {
            const split = threats.length > 0
            out.push({ kind: "section", key: "lobby", title: qsTr("Waiting in lobby (%1)").arg(lobbyShown),
                       action: !split && lobbyShown > 1 ? qsTr("Admit all") : root.lobbyChatAvailable && waiting.length === 1 && !split ? qsTr("Chat") : "",
                       actionIcon: !split && lobbyShown === 1 && root.lobbyChatAvailable ? "chat-20" : "", level: 0 })
            if (!collapsed.lobby) {
                if (split) {
                    if (waiting.length > 0) {
                        out.push({ kind: "section", key: "waiting", title: qsTr("Waiting (%1)").arg(waiting.length),
                                   action: waiting.length > 1 ? qsTr("Admit (%1)").arg(waiting.length) : "", level: 1, list: waiting })
                        if (!collapsed.waiting) waiting.forEach(p => out.push({ kind: "lobby", p: p, level: 2 }))
                    }
                    out.push({ kind: "section", key: "threats", title: qsTr("Suspected threats (%1)").arg(threats.length),
                               action: threats.length > 1 ? qsTr("Deny (%1)").arg(threats.length) : "", level: 1, list: threats })
                    if (!collapsed.threats) threats.forEach(p => out.push({ kind: "lobby", p: p, level: 2 }))
                } else {
                    waiting.forEach(p => out.push({ kind: "lobby", p: p, level: 1 }))
                }
            }
        }
        // Teams' sections (320296): "Presenters (n)" and "Attendees (n)"
        // when the meeting has attendees, else "In this meeting (n)"
        // ("In this call" outside meetings); empty ones aren't drawn.
        const here = people.filter(p => matches(p.name))
        const isAttendee = p => (p.role || "").toLowerCase() === "attendee"
        const attendees = here.filter(isAttendee)
        const presenters = here.filter(p => !isAttendee(p))
        const anyAttendees = meeting && people.some(isAttendee)
        const muteAll = canMuteAll && !display ? qsTr("Mute all") : ""
        if (anyAttendees) {
            if (presenters.length > 0) {
                out.push({ kind: "section", key: "here", title: qsTr("Presenters (%1)").arg(presenters.length), action: muteAll, level: 0 })
                if (!collapsed.here) nested(presenters).forEach(r => out.push(r))
            }
            if (attendees.length > 0) {
                out.push({ kind: "section", key: "attendees", title: qsTr("Attendees (%1)").arg(attendees.length), action: "", level: 0 })
                if (!collapsed.attendees) nested(attendees).forEach(r => out.push(r))
            }
        } else {
            out.push({ kind: "section", key: "here", title: qsTr("%1 (%2)", "calling:k63z7tn13").arg(meeting && !groupCall ? qsTr("In this meeting", "calling:k7zs2oxna") : qsTr("Currently in this call")).arg(here.length), action: muteAll, level: 0 })
            if (!collapsed.here) nested(here).forEach(r => out.push(r))
        }
        const inCall = people.map(p => (p.id || "").toLowerCase())
        const away = chatMembers.filter(m => !m.me && inCall.indexOf((m.mri || "").toLowerCase()) < 0 && matches(m.name))
        if (meeting && away.length > 0) {
            out.push({ kind: "section", key: "chat", title: qsTr("%1 (%2)", "calling:k63z7tn13").arg(qsTr("People added to the chat")).arg(away.length), action: "", level: 0 })
            if (!collapsed.chat) away.forEach(m => out.push({ kind: "person", p: { id: m.mri, name: m.name, presence: m.presence || "", chatOnly: true }, level: 1 }))
        }
        return out
    }

    // Header: "Participants" and close (rail-header, 58 tall, from y 3).
    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.7; y: 17.7; height: 22
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Participants")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        // More actions (more-menu-trigger): 32 x 31.33 left of close.
        Rectangle {
            id: headerMore
            visible: !root.display && root.moreItems.length > 0
            x: parent.width - 84; y: 13; width: 32; height: 31.33; radius: 4
            // Fluent's transparent button: no fill; the glyph turns filled
            // and brand-coloured on hover and while its menu is open.
            color: "transparent"
            FluentIcon {
                anchors.centerIn: parent; size: 20
                name: moreHover.hovered || moreMenu.opened ? "more-horizontal-20-filled" : "more-horizontal-20"
                color: moreHover.hovered || moreMenu.opened ? theme.brand : theme.textStrong
            }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: moreMenu.opened ? moreMenu.close() : moreMenu.openUnder(headerMore) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More actions")
        }
        Rectangle {
            id: hcFill1
            visible: !root.display
            x: parent.width - 52; y: 13.7; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close participants pane")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // "Type a name" (a meeting's search box). In a 1:1 call Teams' people
    // picker instead (people-picker-input, measured on testpc1
    // 2026-11-26): the pane's whole width from just under the header
    // divider (y 79, 33 tall), #F0F0F0, no edge or corners, the text 13.3
    // in, the brand line under it while focused.
    readonly property bool wideBox: root.canInvite && !root.meeting
    Rectangle {
        id: search
        visible: !root.display
        x: root.wideBox ? 0.67 : 20.7; y: root.wideBox ? 79 : 77
        width: root.wideBox ? parent.width - 0.67 : 319.3; height: root.wideBox ? 33 : 32
        radius: root.wideBox ? 0 : 4
        color: root.wideBox ? theme.pick("#F0F0F0", "#1F1F1F", "#000000") : theme.surface
        TextInput {
            id: field
            x: root.wideBox ? 13.3 : 12.6; width: root.wideBox ? parent.width - x - 45 : 274; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            clip: true
            selectByMouse: true
            onTextChanged: {
                root.query = text.trim()
                picker.results = []
                picker.highlighted = 0
                if (root.canInvite && root.query.length > 0) pickDebounce.restart()
            }
            Keys.onDownPressed: picker.highlighted = Math.min(picker.options.length - 1, picker.highlighted + 1)
            Keys.onUpPressed: picker.highlighted = Math.max(0, picker.highlighted - 1)
            Keys.onReturnPressed: if (picker.shown) picker.choose(picker.options[picker.highlighted])
            Keys.onEscapePressed: field.text = ""
            Accessible.role: Accessible.EditableText
            Accessible.name: root.canInvite ? qsTr("Invite someone or dial a number") : qsTr("Type a name")
        }
        Text {
            visible: field.text.length === 0
            x: field.x; anchors.verticalCenter: parent.verticalCenter
            text: root.canInvite ? qsTr("Invite someone or dial a number") : qsTr("Type a name")
            font.family: theme.font; font.pixelSize: 14
            color: root.wideBox ? theme.textSecondary : theme.textTertiary
        }
        // (The people picker shows its search glyph only once there's text.)
        FluentIcon { visible: !root.wideBox || field.text.length > 0; x: parent.width - 30.7; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
        // Teams' focused input: a 2 px brand line along the bottom.
        Rectangle { visible: field.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
    }

    // "Share invite" (openSharePanelButton): 319.3 x 31.3 at 20.7, 119;
    // 14 semibold #242424 on white, a 0.67 NeutralStroke1 edge, the share
    // glyph before the label, both centred.
    Rectangle {
        id: shareInvite
        visible: root.meeting && root.inviteUrl.length > 0 && !root.display
        x: 20.7; y: 119; width: 319.3; height: 31.3; radius: 4
        color: shareHover.hovered ? theme.menuHover : theme.surface
        border.color: theme.stroke; border.width: 0.67
        Row {
            anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "share-invite-20"; size: 20; color: theme.onFill(shareInvite, theme.text) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Share invite"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(shareInvite, theme.text) }
        }
        HoverHandler { id: shareHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.shareInvite() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Share invite")
    }

    Flickable {
        id: list
        // The roster starts 155.3 down below Share invite (measured).
        // (Right under the 1:1 people picker, measured.)
        y: root.display ? 77 : shareInvite.visible ? 155.3 : root.wideBox ? search.y + search.height : search.y + search.height + 10
        width: parent.width; height: parent.height - y
        contentHeight: column.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: column
            width: list.width
            Repeater {
                model: root.rows
                Loader {
                    required property var modelData
                    width: column.width
                    sourceComponent: modelData.kind === "section" ? sectionRow : modelData.kind === "lobby" ? lobbyRow : personRow
                    onLoaded: item.entry = modelData
                }
            }
        }
    }

    // Teams' roster people picker (people-picker-list): typing in the box
    // lists the directory's people (searchV2) under it, the name with the
    // typed words in bold and the address's name in capitals; whoever is
    // already in the call (or being rung) and you are left out. Picking one
    // (click, or arrows and Enter) rings them in.
    Item {
        id: picker
        property var results: []
        property int highlighted: 0
        readonly property string tag: "callinvite" + Math.floor(Math.random() * 1e9).toString(36)
        readonly property var options: {
            const taken = root.people.map(p => (p.id || "").toLowerCase()).concat([root.selfKey.toLowerCase()])
            return results.filter(r => taken.indexOf((r.mri || "").toLowerCase()) < 0)
        }
        /// The test harness types without the window focused.
        property bool forTest: false
        readonly property bool shown: root.canInvite && (field.activeFocus || forTest) && root.query.length > 0 && options.length > 0
        function choose(o) {
            if (!o) return
            root.invite(o.mri, o.name || "")
            field.text = ""
        }
        Timer { id: pickDebounce; interval: 300; onTriggered: backend.eventsRequest("contactsSearch", picker.tag, JSON.stringify({ q: root.query })) }
        Connections {
            target: backend
            function onEventsReply(id, json) {
                if (id !== picker.tag) return
                let v = {}
                try { v = JSON.parse(json) } catch (e) {}
                if (v.q !== root.query) return
                picker.results = v.people || []
                picker.highlighted = 0
            }
        }
        visible: shown
        z: 10
        // Measured on testpc1 (2026-11-26): 4 in from each side, flush
        // under the box, 3 padding; rows 50 tall 2 apart, the highlighted
        // one #F5F5F5 in a 2 px edge; the picture 32 at 12, the name (14,
        // the typed text in bold where the name starts with it) and the
        // address's name in capitals (12, #616161) at 60.
        x: 4; y: search.y + search.height + 1
        width: root.width - 8; height: Math.min(suggestions.contentHeight + 6, root.height - y - 8)
        FluentSurface { anchors.fill: parent; depth: 8; radius: 4; color: theme.surface }
        ListView {
            id: suggestions
            anchors.fill: parent; anchors.margins: 3
            clip: true; model: picker.options
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: opt
                required property var modelData
                required property int index
                width: ListView.view.width; height: 50; radius: 4
                color: picker.highlighted === index || optHover.hovered ? theme.menuHover : "transparent"
                // Fluent's StrokeFocus2 around the highlighted one.
                border.width: picker.highlighted === index && field.activeFocus ? 2 : 0
                border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
                Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: opt.modelData.name || ""; photoId: opt.modelData.mri || "" }
                Text {
                    x: 60; y: 6; width: parent.width - 72; elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: root.boldedPrefix(opt.modelData.name || "", root.query)
                    font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                }
                Text {
                    x: 60; y: 27; width: parent.width - 72; elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: root.boldedPrefix(opt.modelData.detail || "", root.query)
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                }
                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: picker.choose(opt.modelData) }
                Accessible.role: Accessible.ListItem
                Accessible.name: (opt.modelData.name || "") + ", " + (opt.modelData.detail || "")
            }
        }
    }
    // The test harness (--invite-test): type in the box, read and pick
    // the suggestions.
    function typeForTest(t) { picker.forTest = true; field.forceActiveFocus(); field.text = t }
    function inviteOptionsForTest() { return picker.options.map(o => o.name) }
    function pickForTest(i) { picker.choose(picker.options[i]) }
    function pickAllForTest() { const all = picker.options.slice(); all.forEach(o => root.invite(o.mri, o.name || "")); field.text = "" }
    /// The typed text in bold where the line starts with all of it (Teams:
    /// "OST Test 2" marks "OST Test 2", not "OST Test Room").
    function boldedPrefix(t, q) {
        const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const k = String(q || "").trim()
        return k && String(t).toLowerCase().indexOf(k.toLowerCase()) === 0 ? "<b>" + esc(String(t).slice(0, k.length)) + "</b>" + esc(String(t).slice(k.length)) : esc(t)
    }

    // A section or subsection header: 38 tall, chevron and 12 px label,
    // indented 16 per level; the section's action on the right.
    Component {
        id: sectionRow
        Item {
            property var entry: ({})
            height: 38
            readonly property real indent: 16 * (entry.level || 0)
            FluentIcon {
                x: 2.7 + indent + 6; y: 13
                name: "chevron-right-12"; size: 12; color: theme.textSecondary
                rotation: root.collapsed[entry.key] ? 0 : 90
            }
            Text {
                x: 2.7 + indent + 26; anchors.verticalCenter: parent.verticalCenter
                text: entry.title || ""
                font.family: theme.font; font.pixelSize: 12
                color: theme.textStrong
            }
            TapHandler { onTapped: root.toggle(entry.key) }
            Accessible.role: Accessible.Button
            Accessible.name: entry.title || ""
            Rectangle {
                id: hcFill2
                visible: !!entry.action
                anchors.right: parent.right; anchors.rightMargin: 22
                y: 7; height: 24; radius: 4
                width: Math.max(72, actionRow.implicitWidth + 21.3)
                color: actionHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Row {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 4
                    FluentIcon { visible: !!entry.actionIcon; name: entry.actionIcon || "chat-20"; size: 20; color: theme.onFill(hcFill2, theme.text); anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        id: actionText
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.action || ""
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.onFill(hcFill2, theme.text)
                    }
                }
                HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (entry.key === "here") root.muteAll()
                        else if (entry.key === "lobby" && entry.action === qsTr("Chat")) root.chatLobby()
                        else if (entry.key === "lobby") root.admitAll()
                        else if (entry.key === "waiting") root.admitEach(entry.list.map(p => ({ id: p.id, name: p.name })))
                        else if (entry.key === "threats") root.denyEach(entry.list.map(p => ({ id: p.id, name: p.name })))
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: entry.action || ""
            }
        }
    }

    // Someone waiting: avatar, name (and badge), Admit ✓ and Deny ✗.
    Component {
        id: lobbyRow
        Item {
            property var entry: ({ p: {} })
            readonly property var p: entry.p || ({})
            height: 48
            readonly property real avatarX: 2.7 + 19 + 17 * ((entry.level || 1) - 1)
            GuestAvatar { visible: !!p.suspected; x: avatarX; y: 8; personId: p.id || "" }
            Avatar { visible: !p.suspected; x: avatarX; y: 8; size: 32; name: p.name || ""; photoId: "" }
            Row {
                x: avatarX + 44; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, (parent.parent.width - 82) - parent.x - 4 - (unv.visible ? unv.width + 4 : 0))
                    elide: Text.ElideRight
                    text: p.name || ""
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                }
                UnverifiedBadge { id: unv; visible: !!p.suspected; anchors.verticalCenter: parent.verticalCenter }
            }
            LobbyButton {
                x: parent.width - 82; y: 12
                icon: "checkmark-20"; tint: theme.pick("#107C10", "#54B054"); label: qsTr("Admit participant in lobby")
                onClicked: p.suspected ? root.admitSuspected(p.id, p.name) : root.admit(p.id, p.name)
            }
            LobbyButton {
                x: parent.width - 50; y: 12
                icon: "dismiss-20"; tint: theme.redForeground3; label: qsTr("Deny participant in lobby")
                onClicked: root.deny(p.id, p.name)
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (p.name || "") + (p.suspected ? " " + qsTr("Unverified") : "")
        }
    }

    // Someone in the call: avatar, name, role, raised hand, mic.
    Component {
        id: personRow
        Item {
            property var entry: ({ p: {} })
            readonly property var p: entry.p || ({})
            height: 48
            // Under a Teams Room (measured on winpc 2026-11-23): sub-items
            // 36.3 further in; the room's avatar in a 2 px brand ring 1 px
            // out (38 across), a 2 px brand line from it down to a 10 px
            // brand circle beside the last one in the room.
            readonly property real indent: entry.sub ? 36.3 : 0
            Rectangle {
                visible: !!entry.parentWithSub
                x: 18.7; y: 5; width: 38; height: 38; radius: 19
                color: "transparent"; border.width: 2; border.color: theme.brand
            }
            Rectangle { visible: !!entry.parentWithSub; x: 36.7; y: 43; width: 2; height: 5; color: theme.brand }
            Rectangle { visible: !!entry.sub; x: 36.7; y: 0; width: 2; height: entry.lastSub ? 23 : 48; color: theme.brand }
            Rectangle {
                visible: !!entry.lastSub
                x: 32.7; y: 23; width: 10; height: 10; radius: 5
                color: "transparent"; border.width: 2; border.color: theme.brand
            }
            Avatar { visible: !p.suspected; x: 21.7 + indent; y: 8; size: 32; name: p.name || ""; photoId: p.id || ""; presence: p.presence || "" }
            GuestAvatar { visible: !!p.suspected; x: 21.7 + indent; y: 8; personId: p.id || "" }
            Column {
                x: 65.7 + parent.indent; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 46
                // The name, and for an anonymous guest Teams' 16 px
                // Unverified trust icon 4 px after it.
                Row {
                    height: 18.7; spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, personRowColumn.width - (trust.visible ? 20 : 0))
                        elide: Text.ElideRight
                        text: p.name || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    FluentIcon { id: trust; visible: !!p.guest; anchors.verticalCenter: parent.verticalCenter; name: "person-unverified-16"; size: 16; color: theme.text }
                }
                // Teams names only the organizer here, and in Sign language
                // mode the interpreters ("{{rosterItemMessage}}, …").
                Text {
                    readonly property bool organizer: (p.role || "").toLowerCase() === "organizer"
                    visible: organizer || !!p.signLine
                    height: 16; verticalAlignment: Text.AlignVCenter
                    text: organizer && p.signLine ? qsTr("Organizer") + ", " + p.signLine : organizer ? qsTr("Organizer") : (p.signLine || "")
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.textStrong
                }
                id: personRowColumn
            }
            // A raised hand: its place in the queue (14 px) and Teams'
            // raised-hand emoji (32 px, raisehandV3-3D), 5 before the mic.
            readonly property int handRank: p.hand ? root.handOrder.indexOf(p.you ? root.selfKey : p.id) + 1 : 0
            Text {
                id: handRankText
                visible: !!p.hand && handRank > 0
                x: parent.width - 75 - width; y: 13; height: 20
                verticalAlignment: Text.AlignVCenter
                text: handRank
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
            }
            Image {
                visible: !!p.hand
                x: parent.width - 77; y: 8; width: 32; height: 32
                source: visible ? (backend.emoticonsVersion, backend.cardImage("https://statics.teams.cdn.office.net/evergreen-assets/skype/v2/raisehandV3-3D/64.png")) : ""
                sourceSize: Qt.size(64, 64)
                smooth: true
            }
            // Pinned (Pin for me): Teams' 20 px pin, 8 before the mic, or
            // 12 before a raised hand's rank.
            FluentIcon {
                visible: !p.chatOnly && !p.you && root.pinnedIds.indexOf(p.id) >= 0
                x: p.hand ? (handRankText.visible ? handRankText.x : parent.width - 77) - 37 : parent.width - 68
                anchors.verticalCenter: parent.verticalCenter
                name: "pin-20"; size: 20; color: theme.textStrong
            }
            HoverHandler { id: rowHover }
            // Someone invited and still being rung: Teams' "Calling..."
            // where the mic would be, and no menu.
            Text {
                visible: !!p.calling
                anchors.right: parent.right; anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Calling...")
                font.family: theme.font; font.pixelSize: 12
                color: theme.textSecondary
            }
            FluentIcon {
                visible: !p.chatOnly && !p.calling && !(moreButton.visible)
                x: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                name: p.mutedNow ? "mic-off-20" : "roster-mic-20"; size: 20
                color: theme.text
            }
            // Hovering someone else: Teams' ··· (24 x 23.33) in the mic's
            // place opens their menu.
            Rectangle {
                id: moreButton
                visible: !p.chatOnly && !p.calling && !p.you && root.meeting && (rowHover.hovered || participantMenu.forId === (p.id || ""))
                x: parent.width - 42; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 23.33; radius: 4
                color: moreHover.hovered ? theme.hover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, participantMenu.forId === (p.id || "") ? theme.brand : theme.textStrong) }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: participantMenu.openFor(moreButton, p) }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("More options")
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (p.name || "") + (p.hand ? ", " + qsTr("hand raised") : "") + (p.mutedNow ? ", " + qsTr("muted") : "")
        }
    }

    // A participant's ··· menu (measured on winpc): 187.21 wide, padding
    // 4 inside a 0.67 edge, radius 4, flush under the ··· and right-aligned
    // to it; 177.88 x 32 items 2 apart, the 20 px glyph at 6 and the label
    // (14 px #424242) at 30; a separator before Remove; Report last (Report
    // this person); Mute is disabled (#BDBDBD) for someone already muted.
    Popup {
        id: participantMenu
        property var who: ({})
        property string forId: ""
        width: 187.21; padding: 4.67
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        onClosed: forId = ""
        function openFor(button, person) {
            who = person; forId = person.id || ""
            const pt = button.mapToItem(root, button.width - width, button.height)
            x = pt.x; y = pt.y
            open()
        }
        readonly property var items: {
            const w = who
            const out = []
            if (root.canManage) out.push({ k: "mute", t: qsTr("Mute participant"), icon: "mic-off-20", off: !!w.mutedNow })
            out.push(root.pinnedIds.indexOf(w.id) >= 0 ? { k: "unpin", t: qsTr("Unpin for me"), icon: "pin-off-20" }
                     : { k: "pin", t: qsTr("Pin for me"), icon: "pin-20", off: root.pinningFull, tip: root.pinningFull ? qsTr("You reached the maximum number of pins") : "" })
            if (root.canManage) {
                // Manage what attendees see: Teams' spotlight becomes "Bring on
                // screen" / "Take off screen" (calling:bring_on_stage_label).
                if (root.managed)
                    out.push(w.spotlight ? { k: "unspotlight", t: qsTr("Take off screen"), icon: "spotlight-20" } : { k: "spotlight", t: qsTr("Bring on screen"), icon: "spotlight-20" })
                else
                    out.push(w.spotlight ? { k: "unspotlight", t: qsTr("Stop spotlighting"), icon: "spotlight-20" } : { k: "spotlight", t: qsTr("Spotlight for everyone"), icon: "spotlight-20" })
                // A Teams Room: its remote (Teams' controlRoomSystemItem).
                if (w.room && root.roomRemote) out.push({ k: "controlRoom", t: qsTr("Control Room System"), icon: "device-meeting-room-remote-20" })
                if ((w.role || "").toLowerCase() !== "organizer")
                    out.push((w.role || "").toLowerCase() === "attendee"
                        ? { k: "presenter", t: qsTr("Make a presenter"), icon: "presenter-off-20" }
                        : { k: "attendee", t: qsTr("Make an attendee"), icon: "presenter-off-20" })
                out.push({ sep: true })
                out.push({ k: "remove", t: qsTr("Remove from meeting"), icon: "person-remove-20" })
            } else {
                if (w.room && root.roomRemote) out.push({ k: "controlRoom", t: qsTr("Control Room System"), icon: "device-meeting-room-remote-20" })
                if (root.canReport) out.push({ sep: true })
            }
            // Report this person (a security report, as Teams files it).
            if (root.canReport) out.push({ k: "report", t: qsTr("Report"), icon: "shield-error-20" })
            return out
        }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: participantMenu.items
                Item {
                    id: mi
                    required property var modelData
                    readonly property bool sep: !!modelData.sep
                    readonly property bool off: !!modelData.off
                    width: 177.88; height: sep ? 8.67 : 32
                    Rectangle { visible: mi.sep; y: 4; width: parent.width; height: 0.67; color: theme.divider }
                    Rectangle {
                        id: hcFill3
                        visible: !mi.sep
                        anchors.fill: parent; radius: 4
                        color: pmHover.hovered && !mi.off ? theme.menuHover : "transparent"
                        FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.icon || ""; size: 20; color: theme.onFill(hcFill3, mi.off ? theme.disabled : theme.textStrong) }
                        Text {
                            x: 30; anchors.verticalCenter: parent.verticalCenter
                            text: mi.modelData.t || ""
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.onFill(hcFill3, mi.off ? theme.disabled : pmHover.hovered ? theme.text : theme.textStrong)
                        }
                        HoverHandler { id: pmHover; cursorShape: mi.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
                        // Teams' title on a disabled item (why it is).
                        ToolTip.visible: pmHover.hovered && !!mi.modelData.tip
                        ToolTip.text: mi.modelData.tip || ""
                        TapHandler {
                            enabled: !mi.sep && !mi.off
                            onTapped: {
                                const w = participantMenu.who
                                participantMenu.close()
                                root.participantAction(mi.modelData.k, w.id || "", w.name || "", w.spotlight || "")
                            }
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: mi.modelData.t || ""
                    }
                }
            }
        }
    }

    // The More actions popover (roster-header-more-menu-popover), below
    // the button and flush with its right edge: padding 8 x 4 inside a
    // 0.67 edge, radius 4; items 32 tall, 2 apart, as wide as the longest
    // label + 40 (icon 20 at 6, label at 32, 6 after it).
    Popup {
        id: moreMenu
        topPadding: 8.67; bottomPadding: 8.67; leftPadding: 4.67; rightPadding: 4.67
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        // The button's bottom-right corner; the menu's right edge follows
        // it as the menu's width settles.
        property point corner: Qt.point(0, 0)
        x: corner.x - width; y: corner.y
        function openUnder(button) {
            corner = button.mapToItem(root, button.width, button.height)
            open()
        }
        // Measured without writing to anything the binding reads (a
        // TextMetrics' text would loop the binding).
        FontMetrics { id: moreMetrics; font.family: theme.font; font.pixelSize: 14 }
        readonly property real itemWidth: {
            let w = 0
            for (const it of root.moreItems) w = Math.max(w, moreMetrics.advanceWidth(it.t))
            return Math.ceil(w * 100) / 100 + 40
        }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: root.moreItems
                Rectangle {
                    id: mm
                    required property var modelData
                    width: moreMenu.itemWidth; height: 32; radius: 4
                    color: mmHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 6; y: 6; size: 20; name: mm.modelData.icon; color: theme.onFill(mm, mmHover.hovered ? theme.text : theme.textStrong) }
                    Text {
                        x: 32; anchors.verticalCenter: parent.verticalCenter
                        text: mm.modelData.t
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.onFill(mm, mmHover.hovered ? theme.text : theme.textStrong)
                    }
                    HoverHandler { id: mmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { moreMenu.close(); root.moreAction(mm.modelData.k) } }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: mm.modelData.t
                }
            }
        }
    }

    // Teams' lobby row buttons: 24 px, white, 0.67 #D1D1D1 edge, radius 4.
    component LobbyButton: Rectangle {
        id: lb
        property string icon
        property color tint
        property string label
        signal clicked()
        width: 24; height: 24; radius: 4
        color: lbHover.hovered ? theme.menuHover : theme.surface
        border.color: theme.stroke; border.width: 0.67
        FluentIcon { anchors.centerIn: parent; name: lb.icon; size: 20; color: theme.onFill(lb, lb.tint) }
        HoverHandler { id: lbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: lb.label
    }

    // Test hooks.
    function closeMenusForTest() { participantMenu.close(); moreMenu.close() }
    function moreMenuForTest() { moreMenu.openUnder(headerMore) }
    function participantMenuForTest(person) { participantMenu.who = person; participantMenu.forId = person.id; participantMenu.x = root.width - 4 - participantMenu.width; participantMenu.y = 220; participantMenu.open() }
    function rowsForTest() { return JSON.stringify(rows) }
}
