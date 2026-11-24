import QtQuick
import QtQuick.Controls.Basic

// Teams' profile card (the live persona card), measured on winpc
// 2026-11-10 with a colleague's card: an 840-wide sheet under the title
// bar over a dimmed window:
// - the header (padding 24): the 100 px picture with presence, the name
//   (24/32 bold) at 144.7, 42.7 and 44 x 32 actions every 52 from 144.7,
//   74.7 (Start a chat, Navigate to org chart, Start a video call, Start
//   an audio call); Close (24) at 800, 16;
// - tabs at 148.7 (44 tall; 14, the open one semibold brand): Overview,
//   Profile, Organization;
// - Overview: "Send a quick message" (739 x 32) with Send; the
//   availability box (773 wide, #E0E0E0, radius 4): "Last seen … • Free
//   at …" (14/19 semibold) and "Work hours: …" (12/16), then their local
//   time; "Contact information" (14 bold) with Email, Chat and Work phone
//   (237 wide each: 12 #424242 label over the 14 brand value) and "Show
//   more contact information"; "Organization" with their manager and the
//   people reporting to them (122 x 156 tiles: a 56 px picture, the name
//   14 semibold, the job title 12 #424242) and "Show organization".
Popup {
    id: root
    /// "8:orgid:<oid>" or the object id.
    property string who: ""
    property string tab: "overview"
    property bool moreContact: false
    signal startChat(string mri, string name)
    signal startCall(string mri, string name, bool video)
    signal quickMessage(string mri, string name, string text)
    readonly property var card: backend.profileCardJson ? JSON.parse(backend.profileCardJson) : ({})
    readonly property string mri: card.id ? "8:orgid:" + card.id : who
    readonly property var p: card.presence || ({})
    function show(id) { who = id; tab = "overview"; moreContact = false; quick.text = ""; history = [id]; historyAt = 0; backend.loadProfileCard(id); open() }
    // The org chart's people: Home, Back to previous profile and Next
    // profile walk this list (Teams' org chart navigation).
    property var history: []
    property int historyAt: -1
    function visit(id) {
        history = history.slice(0, historyAt + 1).concat([id]); historyAt = history.length - 1
        who = id; backend.loadProfileCard(id)
    }
    function stepTo(i) { if (i < 0 || i >= history.length) return; historyAt = i; who = history[i]; backend.loadProfileCard(who) }
    parent: Overlay.overlay
    modal: true; focus: true
    x: (parent.width - width) / 2; y: 47.5
    width: 840; height: Math.min(618, parent.height - y - 14)
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: theme.surface; radius: 4; FluentSurface { anchors.fill: parent; z: -1; depth: 64; radius: 4; color: theme.surface } }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    function relative(iso) {
        const t = Date.parse(iso || ""); if (!t) return ""
        const m = Math.round((Date.now() - t) / 60000)
        if (m < 60) return qsTr("%n minutes ago", "", Math.max(m, 1))
        const h = Math.round(m / 60); if (h < 24) return qsTr("%n hours ago", "", h)
        const d = Math.round(h / 24); return qsTr("%n days ago", "", d)
    }
    readonly property var statusLabels: ({ Available: qsTr("Available"), Busy: qsTr("Busy"), DoNotDisturb: qsTr("Do not disturb"), BeRightBack: qsTr("Be right back"), Away: qsTr("Away"), Offline: qsTr("Offline"), OffWork: qsTr("Offline") })
    readonly property string availability: {
        const a = p.availability || ""
        const offline = !a || a === "Offline" || a === "PresenceUnknown"
        let s = offline ? (p.lastActive ? qsTr("Last seen %1").arg(relative(p.lastActive)) : qsTr("Offline")) : (statusLabels[a] || a)
        if (p.outOfOffice) s = qsTr("Out of office")
        return s + (freeText ? " • " + freeText : "")
    }
    // "Free at …": the end of what's on their calendar, else the start of
    // their next working hours when they're outside them.
    readonly property string freeText: {
        const sch = card.schedule || {}
        const wh = sch.workingHours || {}
        if (sch.nextFree) return qsTr("Free at %1").arg(theme.time(new Date(sch.nextFree)))
        if (wh.startTime && wh.daysOfWeek) {
            const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            const [sh, sm] = wh.startTime.split(":").map(Number), [eh, em] = (wh.endTime || "17:00").split(":").map(Number)
            const now = new Date(), mins = now.getHours() * 60 + now.getMinutes()
            const today = wh.daysOfWeek.indexOf(days[now.getDay()]) >= 0
            if (today && mins >= sh * 60 + sm && mins < eh * 60 + em) return ""
            const at = new Date(now); at.setHours(sh, sm, 0, 0)
            return qsTr("Free at %1").arg(theme.time(at))
        }
        return ""
    }
    readonly property string workHours: {
        const wh = (card.schedule || {}).workingHours || {}
        if (!wh.startTime) return ""
        const t = s => { const [h, m] = s.split(":").map(Number); return theme.time(new Date(2000, 0, 1, h, m)) }
        return qsTr("Work hours: %1 - %2").arg(t(wh.startTime)).arg(t(wh.endTime || "17:00"))
    }
    readonly property string localTime: {
        const sch = card.schedule || {}
        const theirs = ((sch.workingHours || {}).timeZone || {}).name || ""
        if (!theirs) return ""
        return theme.time(new Date()) + (theirs === sch.myTimeZone ? " - " + qsTr("Same time zone as you") : " - " + theirs)
    }

    contentItem: Item {
        clip: true
        // Header.
        Avatar {
            x: 24.7; y: 24.7; size: 100
            name: root.card.displayName || ""
            photoId: root.mri
            presence: root.p.availability || ""
        }
        Text {
            x: 144.7; y: 42.7; width: 600; elide: Text.ElideRight
            text: root.card.displayName || ""
            font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Row {
            x: 144.7; y: 74.7; spacing: 8
            Repeater {
                model: [
                    { icon: "chat-20", label: qsTr("Start a chat with %1"), act: "chat" },
                    { icon: "org-20", label: qsTr("Navigate to %1's org chart"), act: "org" },
                    { icon: "video-20", label: qsTr("Start a video call with %1"), act: "video" },
                    { icon: "call-20", label: qsTr("Start an audio call with %1"), act: "call" },
                    // LinkedIn's logo (16 px, #1177B3): its people search for the name.
                    { icon: "linkedin-logo", label: qsTr("Find LinkedIn profile for %1"), act: "linkedin" }
                ]
                Rectangle {
                    id: hcFill1
                    required property var modelData
                    width: 44; height: 32; radius: 4
                    color: ah.hovered ? theme.menuHover : "transparent"
                    FluentIcon {
                        anchors.centerIn: parent; name: modelData.icon
                        size: modelData.act === "linkedin" ? 16 : 20
                        color: theme.onFill(hcFill1, modelData.act === "linkedin" ? theme.hc("#1177B3", "#FFFF00") : ah.hovered ? theme.brand : theme.textStrong)
                    }
                    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const n = root.card.displayName || ""
                            if (modelData.act === "chat") { root.close(); root.startChat(root.mri, n) }
                            else if (modelData.act === "org") root.tab = "organization"
                            else if (modelData.act === "linkedin") Qt.openUrlExternally("https://www.linkedin.com/search/results/people/?keywords=" + encodeURIComponent(n))
                            else { root.close(); root.startCall(root.mri, n, modelData.act === "video") }
                        }
                    }
                    ToolTip.visible: ah.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label.arg(root.card.displayName || "")
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label.arg(root.card.displayName || "")
                }
            }
        }
        Rectangle {
            id: hcFill2
            x: 800; y: 16; width: 24; height: 24; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill2, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        // Tabs.
        Row {
            x: 20.7; y: 148.7
            Repeater {
                model: [{ key: "overview", label: qsTr("Overview") }, { key: "profile", label: qsTr("Profile") }, { key: "organization", label: qsTr("Organization") }, { key: "linkedin", label: qsTr("LinkedIn") }]
                Item {
                    required property var modelData
                    readonly property bool on: root.tab === modelData.key
                    width: tabLabel.implicitWidth + 20; height: 44
                    Text { id: tabLabel; x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: parent.on ? Font.DemiBold : Font.Normal; color: parent.on ? theme.brand : theme.text }
                    Rectangle { visible: parent.on; x: 10; width: tabLabel.implicitWidth; height: 3; radius: 1.5; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.tab = modelData.key }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                    Accessible.selected: on
                }
            }
        }
        Rectangle { y: 192.7; width: parent.width; height: 1; color: theme.dividerSoft }

        Flickable {
            id: body
            y: 194; width: parent.width; height: parent.height - y
            contentHeight: (root.tab === "overview" ? overview.height : root.tab === "profile" ? profileTab.height : root.tab === "linkedin" ? linkedInTab.height : (orgChart.visible ? orgChart.y + orgChart.height : orgTab.y + orgTab.height)) + 32
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // ---- Overview ----
            Column {
                id: overview
                visible: root.tab === "overview"
                x: 26.3; y: 16; width: 773
                spacing: 0
                Row {
                    spacing: 5
                    Rectangle {
                        width: 739.3; height: 32; radius: 4
                        color: theme.pick("#F5F5F5", "#292929", "#000000")
                        TextInput {
                            id: quick
                            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                            onAccepted: send.go()
                            Text { visible: !quick.text; text: qsTr("Send a quick message"); font: quick.font; color: theme.textSecondary }
                            Accessible.name: qsTr("Send a quick message")
                        }
                    }
                    Rectangle {
                        id: send
                        function go() { if (!quick.text.trim()) return; root.quickMessage(root.mri, root.card.displayName || "", quick.text.trim()); quick.text = "" }
                        width: 44; height: 32; radius: 4
                        color: sendHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "send-20"; size: 20; color: theme.onFill(send, quick.text.trim() ? theme.brand : theme.textStrong) }
                        HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: send.go() }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Send")
                    }
                }
                Item { width: 1; height: 15 }
                Rectangle {
                    x: 3; width: 773; height: availCol.height + 20; radius: 4
                    color: "transparent"; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF"); border.width: 0.67
                    Column {
                        id: availCol
                        x: 0; y: 10; width: parent.width
                        Item {
                            width: parent.width; height: 44
                            PresenceBadge { x: 12; y: 2; total: 20; presence: root.p.availability || "Offline" }
                            Column {
                                x: 43
                                Text { text: root.availability; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 19; lineHeightMode: Text.FixedHeight; color: theme.text }
                                Text { visible: !!root.workHours; text: root.workHours; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                            }
                        }
                        // Their status message and where they work today.
                        Item {
                            visible: !!root.p.note
                            width: parent.width; height: noteText.height + 12
                            FluentIcon { x: 12; y: 2; name: "status-20"; size: 20; color: theme.textStrong }
                            Text { id: noteText; x: 43; y: 2; width: parent.width - 60; wrapMode: Text.Wrap; textFormat: Text.StyledText; text: root.p.noteHtml || root.p.note || ""; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                        }
                        Item {
                            visible: root.p.workLocation === "Office" || root.p.workLocation === "Remote"
                            width: parent.width; height: 28
                            FluentIcon { x: 12; y: 2; name: root.p.workLocation === "Office" ? "building-20" : "home-20"; size: 20; color: theme.textStrong }
                            Text { x: 43; y: 4; text: root.p.workLocation === "Office" ? qsTr("In the office") : qsTr("Working remotely"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        }
                        Rectangle { visible: !!root.localTime; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                        Item {
                            visible: !!root.localTime
                            width: parent.width; height: 34
                            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "clock-20"; size: 20; color: theme.textStrong }
                            Text { x: 43; anchors.verticalCenter: parent.verticalCenter; text: root.localTime; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        }
                    }
                }
                Item { width: 1; height: 20 }
                Heading { text: qsTr("Contact information") }
                Item { width: 1; height: 20 }
                Flow {
                    x: 4; width: 773; spacing: 20
                    readonly property var items: {
                        const c = root.card, out = []
                        if (c.mail) out.push({ icon: "mail-20", label: qsTr("Email"), value: c.mail, url: "mailto:" + c.mail })
                        const im = (c.imAddresses || [])[0] || c.userPrincipalName
                        if (im) out.push({ icon: "chat-20", label: qsTr("Chat"), value: im, chat: true })
                        if ((c.businessPhones || []).length) out.push({ icon: "call-20", label: qsTr("Work phone"), value: c.businessPhones[0], url: "tel:" + c.businessPhones[0] })
                        if (root.moreContact) {
                            if (c.mobilePhone) out.push({ icon: "phone-20", label: qsTr("Mobile"), value: c.mobilePhone, url: "tel:" + c.mobilePhone })
                            if (c.officeLocation) out.push({ icon: "building-20", label: qsTr("Office location"), value: c.officeLocation })
                            if (c.companyName) out.push({ icon: "building-multiple-20", label: qsTr("Company"), value: c.companyName })
                            const addr = [c.streetAddress, c.city, c.state, c.postalCode, c.country].filter(x => x).join(", ")
                            if (addr) out.push({ icon: "location-20", label: qsTr("Business address"), value: addr })
                        }
                        return out
                    }
                    Repeater {
                        model: parent.items
                        Item {
                            required property var modelData
                            width: 237.3; height: 36
                            FluentIcon { x: 0; y: 6; name: modelData.icon; size: 20; color: theme.textStrong }
                            Text { x: 35; text: modelData.label; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                            Text {
                                x: 35; y: 16; width: parent.width - 35; elide: Text.ElideRight
                                text: modelData.value
                                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.brandForeground1
                                HoverHandler { cursorShape: (modelData.url || modelData.chat) ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { onTapped: { if (modelData.chat) { root.close(); root.startChat(root.mri, root.card.displayName || "") } else if (modelData.url) Qt.openUrlExternally(modelData.url) } }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label + ": " + modelData.value
                        }
                    }
                }
                LinkButton { visible: !root.moreContact; text: qsTr("Show more contact information"); onClicked: root.moreContact = true }
                Item { width: 1; height: 24 }
                Heading { visible: orgPreview.count > 0 || !!root.card.manager; text: qsTr("Organization") }
                Item { width: 1; height: 16 }
                Text {
                    visible: (root.card.reports || []).length > 0 || !!root.card.manager
                    text: (root.card.reports || []).length ? qsTr("People reporting to %1 (%2)").arg(root.card.displayName || "").arg(root.card.reports.length) : qsTr("Reports to")
                    font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                }
                Item { width: 1; height: 8 }
                Row {
                    spacing: 8
                    Repeater {
                        id: orgPreview
                        model: ((root.card.reports || []).length ? root.card.reports : (root.card.manager ? [root.card.manager] : [])).slice(0, 5)
                        PersonTile { required property var modelData; person: modelData }
                    }
                }
                LinkButton { visible: orgPreview.count > 0; text: qsTr("Show organization"); onClicked: root.tab = "organization" }
            }

            // ---- Profile ----
            Column {
                id: profileTab
                visible: root.tab === "profile"
                x: 29.7; y: 16; width: 773; spacing: 16
                Repeater {
                    model: {
                        const c = root.card, out = []
                        const add = (l, v) => { if (v) out.push({ label: l, value: v }) }
                        add(qsTr("Job title"), c.jobTitle); add(qsTr("Department"), c.department); add(qsTr("Company"), c.companyName)
                        add(qsTr("Office location"), c.officeLocation); add(qsTr("Email"), c.mail); add(qsTr("Chat"), (c.imAddresses || [])[0] || c.userPrincipalName)
                        add(qsTr("Work phone"), (c.businessPhones || [])[0]); add(qsTr("Mobile"), c.mobilePhone)
                        add(qsTr("Business address"), [c.streetAddress, c.city, c.state, c.postalCode, c.country].filter(x => x).join(", "))
                        return out
                    }
                    Column {
                        required property var modelData
                        Text { text: modelData.label; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                        Text { text: modelData.value; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                }
            }

            // ---- Organization (measured on winpc 2026-11-13, OST Test 2) ----
            // #FAFAFA under the tabs; Home (40), Back to previous profile
            // (80) and Next profile (112): 32 px buttons 8 down, 20 px glyphs,
            // #BDBDBD while there's nowhere to go. Without a manager or
            // reports Teams says so in a #F5F5F5 bar (0.67 #E0E0E0, radius 4,
            // padding 12 16, 758.67 wide) 42 down: a 24 px glyph, then the
            // text at 48 (14/20 #424242).
            Rectangle {
                visible: root.tab === "organization"
                y: -1.3; width: body.width; height: Math.max(body.height, (orgChart.visible ? orgChart.y + orgChart.height : orgTab.y + orgTab.height) + 32) + 1.3
                color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
            }
            Row {
                visible: root.tab === "organization"
                x: 40; y: 6.6
                component NavButton: Rectangle {
                    id: nbtn
                    property string icon
                    property string label
                    property bool can: false
                    signal go()
                    width: 32; height: 32; radius: 4
                    color: can && nbh.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 20; name: nbtn.icon; color: theme.onFill(nbtn, nbtn.can ? theme.textStrong : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
                    HoverHandler { id: nbh; enabled: nbtn.can; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: nbtn.can; onTapped: nbtn.go() }
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                }
                NavButton { icon: "home-20"; label: qsTr("Home"); can: root.historyAt > 0; onGo: root.stepTo(0) }
                Item { width: 8; height: 1 }
                NavButton { icon: "chevron-left-20"; label: qsTr("Back to previous profile"); can: root.historyAt > 0; onGo: root.stepTo(root.historyAt - 1) }
                NavButton { icon: "chevron-right-20"; label: qsTr("Next profile"); can: root.historyAt < root.history.length - 1; onGo: root.stepTo(root.historyAt + 1) }
            }
            // Teams' org chart (Loki OrgExplorer; measured on winpc
            // 2026-11-20, OST Test 2 with one report), in the 750.67 wide
            // area 40 in, under the navigation (42 down):
            // - the manager chain, top first, then the person in focus: a
            //   495.4 x 156.7 card 127.6 in (0.67 #E0E0E0, radius 4): the 64
            //   px picture with presence at 16.7, the name (16/22 semibold) at
            //   92.7, their job title under it; under a #F0F0F0 line (100
            //   down) "View profile" (127 x 31.3, 0.67 #D1D1D1, a 16 px
            //   contact-card glyph, 14/20 semibold) and at the right "{n}
            //   report(s)" / "{n} direct" (10/14 semibold);
            // - "People reporting to **{name}**" (14/20 #424242) centred
            //   between rules, 16 under the card; their cards 369.3 x 85.3 in
            //   two columns 56 under it (the 48 px picture at 12, the name 14
            //   semibold, job title and location at 72; a 24 px View profile
            //   glyph at the top right);
            // - "**{name}** also works with" (i), 16 under: 128.6 x 140 tiles
            //   (the 48 px picture 16.7 down, the name centred under it).
            // A person's card makes them the person in focus.
            Item {
                id: orgChart
                readonly property var org: root.card.org || null
                visible: root.tab === "organization" && !!org && !!org.focus && !!org.focus.name
                x: 40; y: 42; width: 750.67
                height: worksCol.y + worksCol.height + 24
                component OrgRule: Item {
                    id: rule
                    property string lead
                    property string bold
                    property string tail
                    property bool info: false
                    width: orgChart.width; height: 20
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: ruleText.x - 16; height: 1; color: theme.divider }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: ruleText.x + ruleText.width + (rule.info ? 28 : 0) + 16; width: parent.width - x; height: 1; color: theme.divider }
                    Text {
                        id: ruleText
                        x: (parent.width - width - (rule.info ? 28 : 0)) / 2
                        textFormat: Text.StyledText
                        text: rule.lead + "<b>" + rule.bold + "</b>" + rule.tail
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.textStrong
                    }
                    FluentIcon { visible: rule.info; x: ruleText.x + ruleText.width + 8; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "info-20"; color: theme.textStrong }
                }
                component PersonCard: Rectangle {
                    id: pc
                    property var person: ({})
                    property bool inFocus: false
                    width: 495.4; height: inFocus ? 156.7 : 84
                    radius: 4; color: theme.surface
                    border.width: 0.67; border.color: theme.stroke
                    Avatar { x: pc.inFocus ? 16.7 : 12.7; y: pc.inFocus ? 16.7 : 18; size: pc.inFocus ? 64 : 48; name: pc.person.name || ""; photoId: pc.person.mri || ""; presence: pc.person.availability || "" }
                    Column {
                        x: pc.inFocus ? 92.7 : 72.7; y: pc.inFocus ? 16.7 : (pc.height - height) / 2; width: parent.width - x - (pc.inFocus ? 16 : 60)
                        Text { width: parent.width; elide: Text.ElideRight; text: pc.person.name || ""; font.family: theme.font; font.pixelSize: pc.inFocus ? 16 : 14; font.weight: Font.DemiBold; lineHeight: pc.inFocus ? 22 : 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        Text { visible: !!pc.person.jobTitle; width: parent.width; elide: Text.ElideRight; text: pc.person.jobTitle || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                        Text { visible: !!pc.person.location; width: parent.width; elide: Text.ElideRight; text: pc.person.location || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                    }
                    // A manager's card: their reports count with a people glyph.
                    Row {
                        visible: !pc.inFocus && (pc.person.reports || 0) > 0
                        x: 454.3; y: 45.8; spacing: 2
                        FluentIcon { size: 16; name: "people-20"; color: theme.textStrong }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(pc.person.reports || 0); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                    }
                    Rectangle { visible: pc.inFocus; x: 0.67; y: 100; width: parent.width - 1.33; height: 0.67; color: theme.pick("#F0F0F0", "#2E2E2E", "#FFFFFF") }
                    Rectangle {
                        id: viewProfile
                        visible: pc.inFocus
                        x: 16.7; y: 112.7; width: 127.1; height: 31.3; radius: 4
                        color: vph.hovered ? theme.menuHover : theme.surface
                        border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                        Row {
                            anchors.centerIn: parent; spacing: 8
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "contact-card-20"; color: theme.onFill(viewProfile, theme.text) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("View profile"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(viewProfile, theme.text) }
                        }
                        HoverHandler { id: vph; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.tab = "overview" }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("View profile")
                    }
                    Column {
                        visible: pc.inFocus && (pc.person.reports || 0) > 0
                        anchors.right: parent.right; anchors.rightMargin: 16; y: 114.3
                        Text { anchors.right: parent.right; text: (pc.person.reports === 1 ? qsTr("1 report") : qsTr("%1 reports").arg(pc.person.reports || 0)); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; lineHeight: 14; lineHeightMode: Text.FixedHeight; color: theme.text }
                        Text { anchors.right: parent.right; text: qsTr("%1 direct").arg(pc.person.directs || 0); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; lineHeight: 14; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                    HoverHandler { enabled: !pc.inFocus; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !pc.inFocus; onTapped: if (pc.person.mri) root.visit(pc.person.mri) }
                    Accessible.role: Accessible.Button
                    Accessible.name: (pc.person.name || "") + (pc.person.reports ? ", " + (pc.person.reports === 1 ? qsTr("1 report") : qsTr("%1 reports").arg(pc.person.reports)) : "")
                }
                Column {
                    id: chainCol
                    width: parent.width
                    // The manager chain, top first, each linked down to the next.
                    Repeater {
                        model: orgChart.org ? orgChart.org.managers || [] : []
                        Item {
                            required property var modelData
                            width: chainCol.width; height: 84 + 16
                            PersonCard { x: 127.6; person: modelData }
                            Rectangle { x: chainCol.width / 2; y: 84; width: 1; height: 16; color: theme.stroke }
                        }
                    }
                    PersonCard { x: 127.6; inFocus: true; person: orgChart.org ? orgChart.org.focus : ({}) }
                }
                Rectangle {
                    visible: reportsCol.visible
                    x: parent.width / 2; y: chainCol.height; width: 1; height: 16 + 10; color: theme.stroke
                }
                Column {
                    id: reportsCol
                    readonly property var people: orgChart.org ? orgChart.org.directs || [] : []
                    visible: people.length > 0
                    y: chainCol.height + 16
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    spacing: 32
                    // The card's "People reporting to {0}" (the name bold
                    // where the language puts it), "People reporting to you".
                    OrgRule {
                        readonly property var who: orgChart.org ? orgChart.org.focus || ({}) : ({})
                        readonly property var parts: qsTr("People reporting to %1").split("%1")
                        lead: who.isMe ? qsTr("People reporting to you") : parts[0]
                        bold: who.isMe ? "" : who.name || ""
                        tail: who.isMe ? "" : parts[1] || ""
                    }
                    Grid {
                        columns: 2; columnSpacing: 12; rowSpacing: 12
                        Repeater {
                            model: reportsCol.people
                            Rectangle {
                                id: rc
                                required property var modelData
                                width: 369.3; height: 85.3; radius: 4
                                color: rch.hovered ? theme.menuHover : theme.surface
                                border.width: 0.67; border.color: theme.stroke
                                Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 48; name: rc.modelData.name || ""; photoId: rc.modelData.mri || ""; presence: rc.modelData.availability || "" }
                                Column {
                                    x: 72; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 72 - 44
                                    Text { width: parent.width; elide: Text.ElideRight; text: rc.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(rc, theme.text) }
                                    Text { visible: !!rc.modelData.jobTitle; width: parent.width; elide: Text.ElideRight; text: rc.modelData.jobTitle || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(rc, theme.textStrong) }
                                    Text { visible: !!rc.modelData.location; width: parent.width; elide: Text.ElideRight; text: rc.modelData.location || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(rc, theme.textStrong) }
                                }
                                FluentIcon { x: parent.width - 12 - 20; y: 16; size: 16; name: "contact-card-20"; color: theme.onFill(rc, theme.textStrong) }
                                HoverHandler { id: rch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (rc.modelData.mri) root.visit(rc.modelData.mri) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("%1, currently: %2").arg(rc.modelData.name || "").arg(root.statusLabels[rc.modelData.availability] || rc.modelData.availability || "")
                            }
                        }
                    }
                }
                Column {
                    id: worksCol
                    readonly property var people: orgChart.org ? orgChart.org.worksWith || [] : []
                    visible: people.length > 0
                    y: (reportsCol.visible ? reportsCol.y + reportsCol.height : chainCol.height) + 16
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    spacing: 30
                    OrgRule { lead: ""; bold: orgChart.org && orgChart.org.focus.isMe ? qsTr("You") : orgChart.org ? orgChart.org.focus.name || "" : ""; tail: " " + (orgChart.org && orgChart.org.focus.isMe ? qsTr("work with") : qsTr("also works with")); info: true }
                    Flow {
                        x: 2; width: parent.width - 4; spacing: 12
                        Repeater {
                            model: worksCol.people
                            Rectangle {
                                id: wc
                                required property var modelData
                                width: 128.6; height: 140; radius: 4
                                color: wch.hovered ? theme.menuHover : theme.surface
                                border.width: 0.67; border.color: theme.stroke
                                Avatar { anchors.horizontalCenter: parent.horizontalCenter; y: 16.7; size: 48; name: wc.modelData.name || ""; photoId: wc.modelData.mri || ""; presence: wc.modelData.availability || "" }
                                Text { x: 8; y: 72.7; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: wc.modelData.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(wc, theme.text) }
                                HoverHandler { id: wch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (wc.modelData.mri) root.visit(wc.modelData.mri) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("%1, currently: %2").arg(wc.modelData.name || "").arg(root.statusLabels[wc.modelData.availability] || wc.modelData.availability || "")
                            }
                        }
                    }
                }
            }
            Column {
                id: orgTab
                visible: root.tab === "organization" && !orgChart.visible
                readonly property bool noOrg: !root.card.loading && !root.card.manager && !(root.card.reports || []).length
                x: 40; y: 40.6; width: 758.67; spacing: 12
                Rectangle {
                    visible: orgTab.noOrg
                    width: parent.width; height: noOrgText.height + 24
                    radius: 4
                    color: theme.pick("#F5F5F5", "#292929", "#000000")
                    border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 24; name: "error-circle-24"; color: theme.textStrong }
                    Text {
                        id: noOrgText
                        x: 48; y: 12; width: parent.width - 48 - 16
                        wrapMode: Text.Wrap
                        text: qsTr("We don't have the necessary details to show the organization chart for %1. Organization details are provided by your admin or human resources department.").arg(root.card.displayName || "")
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.textStrong
                    }
                }
                Heading { visible: !!root.card.manager; text: qsTr("Reports to") }
                PersonTile { visible: !!root.card.manager; person: root.card.manager || ({}) }
                Heading { visible: !orgTab.noOrg; text: root.card.displayName || "" }
                Heading { visible: (root.card.reports || []).length > 0; text: qsTr("People reporting to %1 (%2)").arg(root.card.displayName || "").arg((root.card.reports || []).length) }
                Flow {
                    width: parent.width; spacing: 8
                    Repeater { model: root.card.reports || []; PersonTile { required property var modelData; person: modelData } }
                }
            }

            // ---- LinkedIn (measured on winpc 2026-11-13, OST Test 2, who
            // shares no LinkedIn profile) ----
            // Centred, ~400 wide: LinkedIn's logo (64) 100 down; "Learn more
            // on LinkedIn" (24 semibold) 24 under it; the two paragraphs
            // (14, line 18.67) 24 and 16 under that, the second with its
            // "privacy setting" and "Learn more" links; "Check your own
            // settings" (a brand button, 32 tall, radius 4, 14 semibold
            // white) and "Connect your account" (14 brand) with its info
            // glyph. The links open LinkedIn's settings and Microsoft's help
            // as the card's code names them.
            Column {
                id: linkedInTab
                visible: root.tab === "linkedin"
                width: body.width
                topPadding: 98.7
                spacing: 0
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 64; name: "linkedin-logo"; color: theme.hc("#1177B3", "#FFFF00") }
                Item { width: 1; height: 24 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Learn more on LinkedIn")
                    font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; lineHeight: 32; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Item { width: 1; height: 24 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 400; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("%1 isn't sharing LinkedIn profile information here or doesn't have a LinkedIn profile.").arg(root.card.displayName || "")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 18.67; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Item { width: 1; height: 16 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 360; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.RichText
                    readonly property string link: theme.brandForeground1
                    text: qsTr("If your contact is based in the European Economic Area or Switzerland, they may need to change the LinkedIn Digital Markets Act %1 for you and others to see their LinkedIn profile here.").arg("<a href=\"https://aka.ms/LinkedInDMAVisibility\" style=\"color:" + link + ";text-decoration:none\">" + qsTr("privacy setting") + "</a>") + " <a href=\"https://aka.ms/LinkedInPrivacyHelp\" style=\"color:" + link + ";text-decoration:none\">" + qsTr("Learn more") + "</a>"
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 18.67; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    onLinkActivated: l => Qt.openUrlExternally(l)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Item { width: 1; height: 34.7 }
                Rectangle {
                    id: hcFill3
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: settingsLabel.implicitWidth + 41.33; height: 32; radius: 4
                    color: setHover.pressed ? theme.pick("#444791", "#444791", "#1AEBFF") : setHover.hovered ? theme.brandHover : theme.brand
                    Text { id: settingsLabel; anchors.centerIn: parent; text: qsTr("Check your own settings"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, "#FFFFFF") }
                    HoverHandler { id: setHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://aka.ms/LinkedInVisibility") }
                    Accessible.role: Accessible.Button
                    Accessible.name: settingsLabel.text
                }
                Item { width: 1; height: 17.3 }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Text {
                        text: qsTr("Connect your account")
                        font.family: theme.font; font.pixelSize: 14
                        font.underline: connectHover.hovered
                        color: theme.brandForeground1
                        HoverHandler { id: connectHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally("https://www.linkedin.com/psettings/microsoft-accounts") }
                        Accessible.role: Accessible.Link
                        Accessible.name: text
                    }
                    FluentIcon {
                        anchors.verticalCenter: parent.verticalCenter; size: 12; name: "info-16"; color: theme.textStrong
                        HoverHandler { id: infoHover }
                        ToolTip.visible: infoHover.hovered
                        ToolTip.text: qsTr("Securely connect your LinkedIn account to bring your professional network into Microsoft apps.")
                    }
                }
            }
        }
        Text {
            visible: !!root.card.loading || !!root.card.error
            anchors.centerIn: parent
            text: root.card.error ? qsTr("Couldn't load this profile.") : ""
            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
        }
    }

    component Heading: Text {
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    component LinkButton: Text {
        id: lb
        signal clicked()
        height: 44; verticalAlignment: Text.AlignVCenter
        font.family: theme.font; font.pixelSize: 14
        color: lbh.hovered ? theme.brandHover : theme.brandForeground1
        HoverHandler { id: lbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    component PersonTile: Rectangle {
        id: pt
        property var person
        width: 122; height: 156; radius: 4
        color: pth.hovered ? theme.menuHover : "transparent"
        Avatar { anchors.horizontalCenter: parent.horizontalCenter; y: 12; size: 56; name: pt.person.name || ""; photoId: pt.person.mri || "" }
        Text { x: 8; y: 68; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: pt.person.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(pt, theme.text) }
        Text { x: 8; y: 112; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: pt.person.jobTitle || ""; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(pt, theme.textStrong) }
        HoverHandler { id: pth; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (pt.person.mri) root.visit(pt.person.mri) }
        Accessible.role: Accessible.Button
        Accessible.name: (pt.person.name || "") + (pt.person.jobTitle ? ", " + pt.person.jobTitle : "")
    }
}
