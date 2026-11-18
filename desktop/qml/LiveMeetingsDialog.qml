import QtQuick
import QtQuick.Controls

// Teams' "Live meetings" dialog (calendar-multimeeting-view-dialog), the
// join bar's "View meetings" when more than one meeting has started; as
// measured in Teams desktop on winpc (2026-11-17): a 600-wide Fluent dialog,
// padding 24, the 20/28 semibold title and a 32 x 31.33 Dismiss, then one
// 550.67 x 139.33 card per meeting, 8 apart. Each card is the calendar's
// active-event card: brand fill (radius 4, padding 16) holding the show-as
// bar, the start time (14/24 semibold, lower case) over its length (12/16),
// the subject (14/20 semibold), location and "{organizer} invited you"
// (12/16), Chat and Join; below, how long the call has run and who is in
// it (28 px). Chat opens the meeting's chat and Join its pre-join; either
// closes the dialog.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600
    height: Math.min(parent ? parent.height - 48 : 600, list.y + list.contentHeight + 2 + 24)
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    property var meetings: []
    // Who is in each call: Teams watches each live meeting's call while the
    // dialog shows (subscribedCallChangedEvent, joined without media).
    readonly property var rosters: backend.liveMeetingRostersJson ? JSON.parse(backend.liveMeetingRostersJson) : ({})
    onOpened: backend.watchLiveMeetings(JSON.stringify(meetings.map(m => ({ threadId: m.threadId, callId: m.callId || "" }))))
    onClosed: backend.watchLiveMeetings("[]")
    onMeetingsChanged: if (visible) backend.watchLiveMeetings(JSON.stringify(meetings.map(m => ({ threadId: m.threadId, callId: m.callId || "" }))))
    signal joinMeeting(var meeting)
    signal openChat(var meeting)

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.now = new Date() }

    function elapsed(m) {
        const s = Math.max(0, Math.floor((root.now - new Date(m.startedAt || m.start)) / 1000))
        const p = n => (n < 10 ? "0" : "") + n
        const h = Math.floor(s / 3600)
        return (h > 0 ? h + ":" : "") + p(Math.floor(s / 60) % 60) + ":" + p(s % 60)
    }
    function length(m) {
        if (!m.start || !m.end) return ""
        const min = Math.round((new Date(m.end) - new Date(m.start)) / 60000), h = Math.floor(min / 60), r = min % 60
        return h > 0 ? h + " hr" + (r ? " " + r + " min" : "") : r + " min"
    }
    function tentative(m) {
        return m.showAs === "tentative" || (!m.isOrganizer && (m.response === "" || m.response === "notResponded" || m.response === "none" || m.response === "tentativelyAccepted"))
    }

    Text {
        x: 24; y: 24; height: 31.33; width: root.width - 24 - 24 - 40
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        text: "Live meetings"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading
    }
    Rectangle {
        id: dismissFill
        x: root.width - 24 - 32; y: 24; width: 32; height: 31.33; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(dismissFill, theme.textStrong) }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss"
    }

    ListView {
        id: list
        x: 24.67; y: 64; width: 550.67
        height: root.height - y - 2 - 24
        clip: true; spacing: 8
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: root.meetings
        Accessible.role: Accessible.List
        Accessible.name: "Live meetings"
        delegate: Item {
            id: card
            required property var modelData
            width: 550.67; height: 139.33
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.subject
            FluentSurface { anchors.fill: parent; depth: 2; radius: 8; color: theme.surface }
            Rectangle {
                id: fill
                x: 0.67; y: 0.67; width: 549.33; height: 138; radius: 4
                color: theme.brandFill
                // The show-as bar: hatched while unanswered or tentative.
                Item {
                    x: 16; y: 17; width: 4; height: 39
                    Rectangle { anchors.fill: parent; radius: 2; visible: !root.tentative(card.modelData); color: theme.pick("#E8EBFA", "#2F2F4A", "#FFFFFF") }
                    Canvas {
                        anchors.fill: parent
                        visible: root.tentative(card.modelData)
                        onPaint: {
                            const c = getContext("2d")
                            c.clearRect(0, 0, width, height)
                            c.strokeStyle = theme.pick("#E8EBFA", "#2F2F4A", "#FFFFFF"); c.lineWidth = 1.5
                            for (let y = -4; y < height + 4; y += 4) { c.beginPath(); c.moveTo(0, y + 4); c.lineTo(width, y); c.stroke() }
                        }
                    }
                }
                Text {
                    x: 36; y: 16; width: 90; height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: card.modelData.start ? theme.time(new Date(card.modelData.start)).toLowerCase() : ""
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(fill, "white")
                }
                Text {
                    x: 36; y: 40; width: 90; height: 16
                    text: root.length(card.modelData)
                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(fill, "white")
                }
                Column {
                    x: 126; y: 16; width: chatBtn.x - 8 - x
                    Text {
                        width: parent.width; height: 22; elide: Text.ElideRight
                        text: card.modelData.subject || "(No title)"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(fill, "white")
                    }
                    Text {
                        width: parent.width; height: 20; topPadding: 2; elide: Text.ElideRight
                        text: card.modelData.location || ""
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(fill, "white")
                    }
                    Text {
                        width: parent.width; height: 18; topPadding: 2; elide: Text.ElideRight
                        visible: !card.modelData.isOrganizer && !!card.modelData.organizer
                        text: (card.modelData.organizer || "") + " invited you"
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(fill, "white")
                    }
                }
                // Chat (secondary, 20 px glyph) and Join (16 px glyph), 8 apart.
                Rectangle {
                    id: chatBtn
                    x: joinBtn.x - 8 - width; y: 17; width: 66.33; height: 23.33; radius: 4
                    color: chatHover.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.stroke
                    FluentIcon { x: 8.67; anchors.verticalCenter: parent.verticalCenter; name: "chat-20"; size: 20; color: theme.onFill(chatBtn, theme.text) }
                    Text { x: 32.67; anchors.verticalCenter: parent.verticalCenter; text: "Chat"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(chatBtn, theme.text) }
                    HoverHandler { id: chatHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.openChat(card.modelData); root.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Chat with participants"
                }
                Rectangle {
                    id: joinBtn
                    x: fill.width - 16 - width; y: 16.5; width: 65.33; height: 24; radius: 4
                    color: joinHover.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.stroke
                    FluentIcon { x: 8.67; anchors.verticalCenter: parent.verticalCenter; name: "video-16"; size: 16; color: theme.onFill(joinBtn, theme.text) }
                    Text { x: 34.67; anchors.verticalCenter: parent.verticalCenter; text: "Join"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(joinBtn, theme.text) }
                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.joinMeeting(card.modelData); root.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Join " + (card.modelData.subject || "(No title)")
                }
                // How long the call has run, and who started it.
                Text {
                    x: 43; y: 98; width: 70; height: 20
                    text: root.elapsed(card.modelData)
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(fill, "white")
                }
                // The people in the call (Teams' participants-live-roster-list:
                // at most 3, then +N), the starter until the roster comes.
                Row {
                    id: people
                    readonly property var list: root.rosters[card.modelData.threadId]
                        || (card.modelData.initiator ? [{ id: card.modelData.initiator, name: card.modelData.initiatorName || "" }] : [])
                    readonly property int hidden: Math.max(0, list.length - 3)
                    x: 141; y: 94
                    spacing: -10
                    Repeater {
                        model: people.list.slice(0, 3)
                        Avatar { required property var modelData; size: 28; name: modelData.name || "?"; photoId: modelData.id || "" }
                    }
                    Rectangle {
                        visible: people.hidden > 0
                        width: 28; height: 28; radius: 14
                        color: theme.pick("#EBEBEB", "#333333", "#000000")
                        Text { anchors.centerIn: parent; text: "+" + people.hidden; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.pick("#616161", "#ADADAD", "#FFFFFF") }
                    }
                }
            }
        }
    }
}
