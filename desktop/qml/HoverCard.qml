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
// Not in OST yet: the LinkedIn button and tab, and the sections under Show
// more (Badges failed to load in Teams that day, so their layout wasn't
// measured).
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
    readonly property string mri: card.id ? "8:orgid:" + card.id : who
    // Their data once it has loaded for this person (the full card shares
    // it), else what the hovered item showed.
    readonly property bool loaded: !!card.id && ("8:orgid:" + card.id) === who
    readonly property var p: (loaded && card.presence) || (fallbackPresence ? { availability: fallbackPresence } : ({}))
    readonly property bool hovered: cardHover.hovered

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

    readonly property var statusLabels: ({ Available: "Available", Busy: "Busy", DoNotDisturb: "Do not disturb", BeRightBack: "Be right back", Away: "Away", Offline: "Offline", OffWork: "Offline" })
    function relative(iso) {
        const t = Date.parse(iso || ""); if (!t) return ""
        const m = Math.round((Date.now() - t) / 60000)
        if (m < 60) return m <= 1 ? "1 min" : m + " min"
        const h = Math.round(m / 60); if (h < 24) return h + " h"
        const d = Math.round(h / 24); return d === 1 ? "1 day" : d + " days"
    }
    // Teams' compact card: "Last seen 22 h ago" (the full card says "22
    // hours").
    readonly property string availability: {
        const a = p.availability || ""
        const offline = !a || a === "Offline" || a === "PresenceUnknown"
        let s = offline ? (p.lastActive ? "Last seen " + relative(p.lastActive) + " ago" : "Offline") : (statusLabels[a] || a)
        if (p.outOfOffice) s = "Out of office"
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
            implicitHeight: 328 + 32 + 16
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
                        { icon: "chat-20", label: "Start a chat with ", act: "chat" },
                        { icon: "org-20", label: "Navigate to the org chart of ", act: "org" },
                        { icon: "video-20", label: "Start a video call with ", act: "video" },
                        { icon: "call-20", label: "Start an audio call with ", act: "call" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: 44; height: 32; radius: 4
                        color: hah.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: modelData.icon; size: 16; color: hah.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: hah; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const n = root.displayName
                                if (modelData.act === "chat") { root.close(); root.startChat(root.mri, n) }
                                else if (modelData.act === "org") root.full("organization")
                                else { root.close(); root.startCall(root.mri, n, modelData.act === "video") }
                            }
                        }
                        ToolTip.visible: hah.hovered; ToolTip.delay: 500; ToolTip.text: modelData.label + (root.displayName)
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label + (root.displayName)
                    }
                }
            }
            Rectangle {
                x: 13.7; y: 163.3; width: 255.3; height: 32; radius: 4
                color: theme.pick("#F3F2F1", "#3B3A39")
                TextInput {
                    id: quick
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    clip: true; font.family: theme.font; font.pixelSize: 14; color: theme.text
                    Text { visible: !quick.text; text: "Send a quick message"; font: quick.font; color: theme.textSecondary }
                    Keys.onReturnPressed: send.go()
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Send a quick message"
                }
            }
            Rectangle {
                id: send
                x: 273.7; y: 162.7; width: 44; height: 32; radius: 4
                color: sh.hovered ? theme.menuHover : "transparent"
                function go() { if (!quick.text.trim()) return; const t = quick.text.trim(); root.close(); root.quickMessage(root.mri, root.displayName, t) }
                FluentIcon { anchors.centerIn: parent; name: "send-20"; size: 16; color: quick.text.trim() ? theme.brand : theme.textStrong }
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: send.go() }
                Accessible.role: Accessible.Button
                Accessible.name: "Send"
            }
            Rectangle {
                x: 14; y: 208; width: 304; height: 38; radius: 4
                color: "transparent"; border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
                PresenceBadge { x: 25.7 - 14; anchors.verticalCenter: parent.verticalCenter; total: 16; presence: root.p.availability || "Offline" }
                Text {
                    x: 55.7 - 14; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                    text: root.availability
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text
                }
            }
            Row {
                x: 25; y: 262; height: 22; spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Profile"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.text }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.full("profile") }
                Accessible.role: Accessible.Button
                Accessible.name: "Profile"
            }
            Rectangle {
                readonly property string mail: root.loaded ? (root.card.mail || "") : ""
                visible: !!mail
                x: 1; y: 292; width: 312.7; height: 32
                color: mh.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 25; anchors.verticalCenter: parent.verticalCenter; name: "mail-20"; size: 16; color: theme.textStrong }
                Text { x: 57; width: 290.7 - 57 - 8; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: parent.mail; font.family: theme.font; font.pixelSize: 12; color: theme.brand }
                HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally("mailto:" + parent.mail) }
                Rectangle {
                    x: 290.7 - 5; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; radius: 4
                    color: ch.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "copy-16"; size: 14; color: theme.textSecondary }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: backend.copyText(parent.parent.mail) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Copy email"
                }
                Accessible.role: Accessible.Link
                Accessible.name: mail
            }
            Rectangle {
                x: 9; y: 328; width: 92; height: 32; radius: 4
                color: smh.hovered ? theme.menuHover : "transparent"
                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Show more"; font.family: theme.font; font.pixelSize: 12; color: theme.brand }
                HoverHandler { id: smh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.full("profile") }
                Accessible.role: Accessible.Link
                Accessible.name: "Show more"
            }
        }
    }
}
