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
        if (m < 60) return m <= 1 ? "1 minute" : m + " minutes"
        const h = Math.round(m / 60); if (h < 24) return h === 1 ? "1 hour" : h + " hours"
        const d = Math.round(h / 24); return d === 1 ? "1 day" : d + " days"
    }
    readonly property var statusLabels: ({ Available: "Available", Busy: "Busy", DoNotDisturb: "Do not disturb", BeRightBack: "Be right back", Away: "Away", Offline: "Offline", OffWork: "Offline" })
    readonly property string availability: {
        const a = p.availability || ""
        const offline = !a || a === "Offline" || a === "PresenceUnknown"
        let s = offline ? (p.lastActive ? "Last seen " + relative(p.lastActive) + " ago" : "Offline") : (statusLabels[a] || a)
        if (p.outOfOffice) s = "Out of office"
        return s + (freeText ? " • " + freeText : "")
    }
    // "Free at …": the end of what's on their calendar, else the start of
    // their next working hours when they're outside them.
    readonly property string freeText: {
        const sch = card.schedule || {}
        const wh = sch.workingHours || {}
        if (sch.nextFree) return "Free at " + Qt.formatTime(new Date(sch.nextFree), "h:mm AP")
        if (wh.startTime && wh.daysOfWeek) {
            const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            const [sh, sm] = wh.startTime.split(":").map(Number), [eh, em] = (wh.endTime || "17:00").split(":").map(Number)
            const now = new Date(), mins = now.getHours() * 60 + now.getMinutes()
            const today = wh.daysOfWeek.indexOf(days[now.getDay()]) >= 0
            if (today && mins >= sh * 60 + sm && mins < eh * 60 + em) return ""
            const at = new Date(now); at.setHours(sh, sm, 0, 0)
            return "Free at " + Qt.formatTime(at, "h:mm AP")
        }
        return ""
    }
    readonly property string workHours: {
        const wh = (card.schedule || {}).workingHours || {}
        if (!wh.startTime) return ""
        const t = s => { const [h, m] = s.split(":").map(Number); return Qt.formatTime(new Date(2000, 0, 1, h, m), "h:mm AP") }
        return "Work hours: " + t(wh.startTime) + " - " + t(wh.endTime || "17:00")
    }
    readonly property string localTime: {
        const sch = card.schedule || {}
        const theirs = ((sch.workingHours || {}).timeZone || {}).name || ""
        if (!theirs) return ""
        return Qt.formatTime(new Date(), "h:mm AP") + (theirs === sch.myTimeZone ? " - Same time zone as you" : " - " + theirs)
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
                    { icon: "chat-20", label: "Start a chat with ", act: "chat" },
                    { icon: "org-20", label: "Navigate to the org chart of ", act: "org" },
                    { icon: "video-20", label: "Start a video call with ", act: "video" },
                    { icon: "call-20", label: "Start an audio call with ", act: "call" },
                    // LinkedIn's logo (16 px, #1177B3): its people search for the name.
                    { icon: "linkedin-logo", label: "Find LinkedIn profile for ", act: "linkedin" }
                ]
                Rectangle {
                    required property var modelData
                    width: 44; height: 32; radius: 4
                    color: ah.hovered ? theme.menuHover : "transparent"
                    FluentIcon {
                        anchors.centerIn: parent; name: modelData.icon
                        size: modelData.act === "linkedin" ? 16 : 20
                        color: modelData.act === "linkedin" ? "#1177B3" : ah.hovered ? theme.brand : theme.textStrong
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
                    ToolTip.visible: ah.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label + (root.card.displayName || "")
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label + (root.card.displayName || "")
                }
            }
        }
        Rectangle {
            x: 800; y: 16; width: 24; height: 24; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        // Tabs.
        Row {
            x: 20.7; y: 148.7
            Repeater {
                model: [{ key: "overview", label: "Overview" }, { key: "profile", label: "Profile" }, { key: "organization", label: "Organization" }, { key: "linkedin", label: "LinkedIn" }]
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
            contentHeight: (root.tab === "overview" ? overview.height : root.tab === "profile" ? profileTab.height : root.tab === "linkedin" ? linkedInTab.height : orgTab.y + orgTab.height) + 32
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
                        color: theme.pick("#F5F5F5", "#292929")
                        TextInput {
                            id: quick
                            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                            onAccepted: send.go()
                            Text { visible: !quick.text; text: "Send a quick message"; font: quick.font; color: theme.textSecondary }
                            Accessible.name: "Send a quick message"
                        }
                    }
                    Rectangle {
                        id: send
                        function go() { if (!quick.text.trim()) return; root.quickMessage(root.mri, root.card.displayName || "", quick.text.trim()); quick.text = "" }
                        width: 44; height: 32; radius: 4
                        color: sendHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "send-20"; size: 20; color: quick.text.trim() ? theme.brand : theme.textStrong }
                        HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: send.go() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Send"
                    }
                }
                Item { width: 1; height: 15 }
                Rectangle {
                    x: 3; width: 773; height: availCol.height + 20; radius: 4
                    color: "transparent"; border.color: theme.pick("#E0E0E0", "#3D3D3D"); border.width: 0.67
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
                            Text { x: 43; y: 4; text: root.p.workLocation === "Office" ? "In the office" : "Working remotely"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        }
                        Rectangle { visible: !!root.localTime; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
                        Item {
                            visible: !!root.localTime
                            width: parent.width; height: 34
                            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "clock-20"; size: 20; color: theme.textStrong }
                            Text { x: 43; anchors.verticalCenter: parent.verticalCenter; text: root.localTime; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        }
                    }
                }
                Item { width: 1; height: 20 }
                Heading { text: "Contact information" }
                Item { width: 1; height: 20 }
                Flow {
                    x: 4; width: 773; spacing: 20
                    readonly property var items: {
                        const c = root.card, out = []
                        if (c.mail) out.push({ icon: "mail-20", label: "Email", value: c.mail, url: "mailto:" + c.mail })
                        const im = (c.imAddresses || [])[0] || c.userPrincipalName
                        if (im) out.push({ icon: "chat-20", label: "Chat", value: im, chat: true })
                        if ((c.businessPhones || []).length) out.push({ icon: "call-20", label: "Work phone", value: c.businessPhones[0], url: "tel:" + c.businessPhones[0] })
                        if (root.moreContact) {
                            if (c.mobilePhone) out.push({ icon: "phone-20", label: "Mobile", value: c.mobilePhone, url: "tel:" + c.mobilePhone })
                            if (c.officeLocation) out.push({ icon: "building-20", label: "Office location", value: c.officeLocation })
                            if (c.companyName) out.push({ icon: "building-multiple-20", label: "Company", value: c.companyName })
                            const addr = [c.streetAddress, c.city, c.state, c.postalCode, c.country].filter(x => x).join(", ")
                            if (addr) out.push({ icon: "location-20", label: "Business address", value: addr })
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
                LinkButton { visible: !root.moreContact; text: "Show more contact information"; onClicked: root.moreContact = true }
                Item { width: 1; height: 24 }
                Heading { visible: orgPreview.count > 0 || !!root.card.manager; text: "Organization" }
                Item { width: 1; height: 16 }
                Text {
                    visible: (root.card.reports || []).length > 0 || !!root.card.manager
                    text: (root.card.reports || []).length ? "People reporting to " + (root.card.displayName || "") + " (" + root.card.reports.length + ")" : "Reports to"
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
                LinkButton { visible: orgPreview.count > 0; text: "Show organization"; onClicked: root.tab = "organization" }
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
                        add("Job title", c.jobTitle); add("Department", c.department); add("Company", c.companyName)
                        add("Office location", c.officeLocation); add("Email", c.mail); add("Chat", (c.imAddresses || [])[0] || c.userPrincipalName)
                        add("Work phone", (c.businessPhones || [])[0]); add("Mobile", c.mobilePhone)
                        add("Business address", [c.streetAddress, c.city, c.state, c.postalCode, c.country].filter(x => x).join(", "))
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
                y: -1.3; width: body.width; height: Math.max(body.height, orgTab.y + orgTab.height + 32) + 1.3
                color: theme.pick("#FAFAFA", "#1F1F1F")
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
                    FluentIcon { anchors.centerIn: parent; size: 20; name: nbtn.icon; color: nbtn.can ? theme.textStrong : theme.pick("#BDBDBD", "#5C5C5C") }
                    HoverHandler { id: nbh; enabled: nbtn.can; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: nbtn.can; onTapped: nbtn.go() }
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                }
                NavButton { icon: "home-20"; label: "Home"; can: root.historyAt > 0; onGo: root.stepTo(0) }
                Item { width: 8; height: 1 }
                NavButton { icon: "chevron-left-20"; label: "Back to previous profile"; can: root.historyAt > 0; onGo: root.stepTo(root.historyAt - 1) }
                NavButton { icon: "chevron-right-20"; label: "Next profile"; can: root.historyAt < root.history.length - 1; onGo: root.stepTo(root.historyAt + 1) }
            }
            Column {
                id: orgTab
                visible: root.tab === "organization"
                readonly property bool noOrg: !root.card.loading && !root.card.manager && !(root.card.reports || []).length
                x: 40; y: 40.6; width: 758.67; spacing: 12
                Rectangle {
                    visible: orgTab.noOrg
                    width: parent.width; height: noOrgText.height + 24
                    radius: 4
                    color: theme.pick("#F5F5F5", "#292929")
                    border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 24; name: "error-circle-24"; color: theme.textStrong }
                    Text {
                        id: noOrgText
                        x: 48; y: 12; width: parent.width - 48 - 16
                        wrapMode: Text.Wrap
                        text: "We don't have the necessary details to show the organization chart for " + (root.card.displayName || "") + ". Organization details are provided by your admin or human resources department."
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.textStrong
                    }
                }
                Heading { visible: !!root.card.manager; text: "Reports to" }
                PersonTile { visible: !!root.card.manager; person: root.card.manager || ({}) }
                Heading { visible: !orgTab.noOrg; text: root.card.displayName || "" }
                Heading { visible: (root.card.reports || []).length > 0; text: "People reporting to " + (root.card.displayName || "") + " (" + (root.card.reports || []).length + ")" }
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
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 64; name: "linkedin-logo"; color: "#1177B3" }
                Item { width: 1; height: 24 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Learn more on LinkedIn"
                    font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; lineHeight: 32; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Item { width: 1; height: 24 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 400; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: (root.card.displayName || "") + " isn't sharing LinkedIn profile information here or doesn't have a LinkedIn profile."
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 18.67; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
                Item { width: 1; height: 16 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 360; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.RichText
                    readonly property string link: theme.brandForeground1
                    text: "If your contact is based in the European Economic Area or Switzerland, they may need to change the LinkedIn Digital Markets Act <a href=\"https://aka.ms/LinkedInDMAVisibility\" style=\"color:" + link + ";text-decoration:none\">privacy setting</a> for you and others to see their LinkedIn profile here. <a href=\"https://aka.ms/LinkedInPrivacyHelp\" style=\"color:" + link + ";text-decoration:none\">Learn more</a>"
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 18.67; lineHeightMode: Text.FixedHeight
                    color: theme.text
                    onLinkActivated: l => Qt.openUrlExternally(l)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Item { width: 1; height: 34.7 }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: settingsLabel.implicitWidth + 41.33; height: 32; radius: 4
                    color: setHover.pressed ? theme.pick("#444791", "#444791") : setHover.hovered ? theme.brandHover : theme.brand
                    Text { id: settingsLabel; anchors.centerIn: parent; text: "Check your own settings"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
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
                        text: "Connect your account"
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
                        ToolTip.text: "Securely connect your LinkedIn account to bring your professional network into Microsoft apps."
                    }
                }
            }
        }
        Text {
            visible: !!root.card.loading || !!root.card.error
            anchors.centerIn: parent
            text: root.card.error ? "Couldn't load this profile." : ""
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
        Text { x: 8; y: 68; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: pt.person.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 8; y: 112; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: pt.person.jobTitle || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        HoverHandler { id: pth; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (pt.person.mri) root.visit(pt.person.mri) }
        Accessible.role: Accessible.Button
        Accessible.name: (pt.person.name || "") + (pt.person.jobTitle ? ", " + pt.person.jobTitle : "")
    }
}
