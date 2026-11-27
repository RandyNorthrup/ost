import QtQuick
import QtQuick.Controls.Basic

// Teams' compact profile card, opened by hovering a person's picture or
// name (measured on winpc 2026-11-12 with OST Test 2's card in a chat
// header): 340 wide, at most 446 tall (it scrolls), white, its left at the
// hovered item's and its top 8 under it.
// - the 72 px picture with presence at 24, 29; the name (14/700) at
//   116, 52.5;
// - 44 x 32 actions every 52 from 24, 106: Start a chat, Navigate to the
//   org chart, Start a video call, Start an audio call;
// - "Send a quick message" (255.3 x 32, #F3F2F1) at 13.7, 163.3 with Send
//   (44 x 32) at 273.7;
// - the availability box (304 x 38 at 14, 208; the 16 px status glyph at
//   25.7 and the text 12/600 at 55.7);
// - "Profile ›" (12/700) at 25, 262; the email row (32 tall at 1, 292: a
//   16 px mail glyph at 25, the address 12 px brand at 57, Copy at 290.7);
// - "Show more" (12 px brand) at 9, 328.
// Profile ›, Show more and the org chart open the full card (ProfileCard)
// on their tab. It opens about 640 ms after the pointer reaches the
// picture or name and closes 500 ms after it leaves both (Fluent's
// mouseLeaveDelay), as Teams' does.
// Not in OST yet: the LinkedIn button and tab.
Popup {
    id: root
    parent: Overlay.overlay
    modal: false; focus: false
    padding: 0
    width: 340
    height: Math.min(446, body.implicitHeight)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 0; color: theme.surface }

    /// The full card, which Profile ›, Show more and the org chart open.
    property var fullCard: null
    signal startChat(string mri, string name)
    signal startCall(string mri, string name, bool video)
    signal quickMessage(string mri, string name, string text)

    property string who: ""
    property Item pendingItem: null
    property string pendingWho: ""
    readonly property var card: backend.profileCardJson ? JSON.parse(backend.profileCardJson) : ({})
    readonly property string mri: card.id ? Mri.work(card.id) : who
    // Their data once it has loaded for this person (the full card shares
    // it), else what the hovered item showed.
    readonly property bool loaded: !!card.id && Mri.work(card.id) === who
    readonly property var p: (loaded && card.presence) || (fallbackPresence ? { availability: fallbackPresence } : ({}))
    readonly property bool hovered: cardHover.hovered
    /// Their direct reports (Loki's org chart, else Graph's) and whether
    /// there's an org chart to show.
    readonly property var directs: loaded ? ((card.org && card.org.directs && card.org.directs.length ? card.org.directs : card.reports) || []).map(d => ({ name: d.name || d.displayName || "", mri: d.mri || (d.id ? Mri.work(d.id) : "") })) : []
    readonly property bool hasOrg: loaded && !!card.org && ((card.org.managers || []).length > 0 || (card.org.directs || []).length > 0)

    /// The pointer reached a person's picture or name.
    /// The hovered person's name, shown until the card's data loads.
    property string pendingName: ""
    property string fallbackName: ""
    property string pendingPresence: ""
    property string fallbackPresence: ""
    readonly property string displayName: loaded ? (card.displayName || fallbackName) : fallbackName
    function hoverEnter(id, item, name, presence) {
        if (!id || id.indexOf("8:orgid:") !== 0) return
        closeTimer.stop()
        if (opened && id === who) return
        pendingWho = id; pendingItem = item; pendingName = name || ""; pendingPresence = presence || ""
        openTimer.restart()
    }
    /// It left it.
    function hoverLeave() {
        openTimer.stop()
        if (opened && !cardHover.hovered) closeTimer.restart()
    }
    function showFor(id, item) {
        who = id; quick.text = ""; fallbackName = pendingName; fallbackPresence = pendingPresence
        backend.loadProfileCard(id)
        const p = item.mapToItem(Overlay.overlay, 0, item.height)
        x = Math.max(8, Math.min(Overlay.overlay.width - width - 8, p.x))
        y = Math.max(8, Math.min(Overlay.overlay.height - 446 - 8, p.y + 8))
        open()
    }
    function full(tab) {
        close()
        if (!fullCard) return
        fullCard.show(who)
        fullCard.tab = tab
    }
    Timer { id: openTimer; interval: 640; onTriggered: if (root.pendingItem) root.showFor(root.pendingWho, root.pendingItem) }
    Timer { id: closeTimer; interval: 500; onTriggered: if (!cardHover.hovered) root.close() }

    readonly property var statusLabels: ({ Available: qsTr("Available"), Busy: qsTr("Busy"), DoNotDisturb: qsTr("Do not disturb"), BeRightBack: qsTr("Be right back"), Away: qsTr("Away"), Offline: qsTr("Offline"), OffWork: qsTr("Offline") })
    // Teams' profile card time ago: "%d %u ago" with its short units ("22 h
    // ago", "5 m ago"), "Yesterday" from a day, then the date.
    function relative(iso) {
        const t = Date.parse(iso || ""); if (!t) return ""
        const ago = (n, u) => qsTr("%d %u ago", "livePersonaCard:k36g9nwlf").replace(/%d %u/i, n + " " + u)
        const m = Math.round((Date.now() - t) / 60000)
        if (m < 60) return ago(Math.max(m, 1), qsTr("m", "livePersonaCard:k5r9cziff"))
        const h = Math.round(m / 60); if (h < 24) return ago(h, qsTr("h", "livePersonaCard:k8ch74srv"))
        return h < 48 ? qsTr("Yesterday", "livePersonaCard:kax87tkxj") : theme.dateMaybeYear(t)
    }
    // Teams' compact card: "Last seen 22 h ago" (the full card says "22
    // hours").
    readonly property string availability: {
        const a = p.availability || ""
        const offline = !a || a === "Offline" || a === "PresenceUnknown"
        let s = offline ? (p.lastActive ? qsTr("Last seen %1").arg(relative(p.lastActive)) : qsTr("Offline")) : (statusLabels[a] || a)
        if (p.outOfOffice) s = qsTr("Out of office")
        return s
    }

    contentItem: Flickable {
        clip: true
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        HoverHandler { id: cardHover; onHoveredChanged: if (hovered) closeTimer.stop(); else closeTimer.restart() }
        Item {
            id: body
            width: 340
            implicitHeight: orgSection.visible ? orgSection.y + orgSection.height + 16 : 328 + 32 + 16
            Avatar {
                x: 24; y: 29; size: 72
                name: root.displayName
                photoId: root.who
                presence: root.p.availability || ""
            }
            Text {
                x: 116; y: 52.5; width: 340 - 116 - 16; height: 20; elide: Text.ElideRight
                text: root.displayName
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Row {
                x: 24; y: 106; spacing: 8
                Repeater {
                    model: [
                        { icon: "chat-20", label: qsTr("Start a chat with %1"), act: "chat" },
                        { icon: "org-20", label: qsTr("Navigate to %1's org chart"), act: "org" },
                        { icon: "video-20", label: qsTr("Start a video call with %1"), act: "video" },
                        { icon: "call-20", label: qsTr("Start an audio call with %1"), act: "call" },
                        // LinkedIn's logo, as the full card's: its people search.
                        { icon: "linkedin-logo", label: qsTr("Find LinkedIn profile for %1"), act: "linkedin" }
                    ]
                    Rectangle {
                        id: hcFill1
                        required property var modelData
                        width: 44; height: 32; radius: 4
                        color: hah.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: modelData.icon; size: 16; color: theme.onFill(hcFill1, modelData.act === "linkedin" ? theme.hc("#1177B3", "#FFFF00") : hah.hovered ? theme.brand : theme.textStrong) }
                        HoverHandler { id: hah; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const n = root.displayName
                                if (modelData.act === "chat") { root.close(); root.startChat(root.mri, n) }
                                else if (modelData.act === "org") root.full("organization")
                                else if (modelData.act === "linkedin") backend.openExternal("https://www.linkedin.com/search/results/people/?keywords=" + encodeURIComponent(n))
                                else { root.close(); root.startCall(root.mri, n, modelData.act === "video") }
                            }
                        }
                        ToolTip.visible: hah.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label.arg(root.displayName)
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label.arg(root.displayName)
                    }
                }
            }
            Rectangle {
                x: 13.7; y: 163.3; width: 255.3; height: 32; radius: 4
                color: theme.pick("#F3F2F1", "#3B3A39", "#000000")
                TextInput {
                    id: quick
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    clip: true; font.family: theme.font; font.pixelSize: 14; color: theme.text
                    Text { visible: !quick.text; text: qsTr("Send a quick message"); font: quick.font; color: theme.textSecondary }
                    Keys.onReturnPressed: send.go()
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Send a quick message")
                }
            }
            Rectangle {
                id: send
                x: 273.7; y: 162.7; width: 44; height: 32; radius: 4
                color: sh.hovered ? theme.menuHover : "transparent"
                function go() { if (!quick.text.trim()) return; const t = quick.text.trim(); root.close(); root.quickMessage(root.mri, root.displayName, t) }
                FluentIcon { anchors.centerIn: parent; name: "send-20"; size: 16; color: theme.onFill(send, quick.text.trim() ? theme.brand : theme.textStrong) }
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: send.go() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Send")
            }
            Rectangle {
                x: 14; y: 208; width: 304; height: 38; radius: 4
                color: "transparent"; border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                PresenceBadge { x: 25.7 - 14; anchors.verticalCenter: parent.verticalCenter; total: 16; presence: root.p.availability || "Offline" }
                Text {
                    x: 55.7 - 14; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                    text: root.availability
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text
                }
            }
            Row {
                x: 25; y: 262; height: 22; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Profile"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.text }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.full("profile") }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Profile")
            }
            Rectangle {
                id: hcFill2
                readonly property string mail: root.loaded ? (root.card.mail || "") : ""
                visible: !!mail
                x: 1; y: 292; width: 312.7; height: 32
                color: mh.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 25; anchors.verticalCenter: parent.verticalCenter; name: "mail-20"; size: 16; color: theme.onFill(hcFill2, theme.textStrong) }
                Text { x: 57; width: 290.7 - 57 - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: parent.mail; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill2, theme.brand) }
                HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.openExternal("mailto:" + parent.mail) }
                Rectangle {
                    id: hcFill3
                    x: 290.7 - 5; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; radius: 4
                    color: ch.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "copy-16"; size: 14; color: theme.onFill(hcFill3, theme.textSecondary) }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.copyText(parent.parent.mail) }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Copy email")
                }
                Accessible.role: Accessible.Link
                Accessible.name: mail
            }
            Rectangle {
                id: hcFill4
                x: 9; y: 328; width: 92; height: 32; radius: 4
                color: smh.hovered ? theme.menuHover : "transparent"
                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Show more"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill4, theme.brand) }
                HoverHandler { id: smh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.full("profile") }
                Accessible.role: Accessible.Link
                Accessible.name: qsTr("Show more")
            }
            // Under Show more (measured on winpc 2026-11-20, OST Test 2's
            // card): "Direct reports (n) ›" (12/16 bold) at 24, 392, their
            // 40 px pictures from 24, 422 (one opens that person's card),
            // then "Show organization" (12 px brand, 131 x 32) at 8, 466;
            // the heading and the link open Organization.
            Item {
                id: orgSection
                y: 392; width: parent.width
                visible: root.directs.length > 0 || root.hasOrg
                height: (root.directs.length > 0 ? 74 : 0) + 32
                Row {
                    id: directsHead
                    visible: root.directs.length > 0
                    x: 24; height: 22; spacing: 2
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Direct reports (%1)").arg(root.directs.length); font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.text }
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.text }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.full("organization") }
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Direct reports (%1)").arg(root.directs.length)
                }
                Row {
                    visible: root.directs.length > 0
                    x: 24; y: 30; spacing: 8
                    Repeater {
                        model: root.directs.slice(0, 6)
                        Avatar {
                            required property var modelData
                            size: 40
                            name: modelData.name || ""
                            photoId: modelData.mri || ""
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { const m = parent.modelData.mri; root.close(); if (root.fullCard && m) root.fullCard.show(m) } }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name || ""
                        }
                    }
                }
                Rectangle {
                    id: showOrg
                    x: 8; y: root.directs.length > 0 ? 74 : 0; width: 131; height: 32; radius: 4
                    color: soh.hovered ? theme.menuHover : "transparent"
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Show organization"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(showOrg, theme.brand) }
                    HoverHandler { id: soh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.full("organization") }
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Show organization")
                }
            }
        }
    }
}
