import QtQuick
import QtQuick.Controls.Basic

// The Events form's people and room pickers (Co-organizers, Presenters,
// Invite people to attend, Location's Add a room), measured in Teams
// desktop 26304 on winpc 2026-11-18 (CSS px):
// - the field (filled, #F0F0F0, radius 4, no border; a 2 px brand line
//   under it while focused): 32 tall with nobody picked, the placeholder
//   14/20 #616161 12 in; picked people as tags (24 tall, the 20 px
//   avatar, the name 14/20 #242424, a 12 px dismiss), 8 apart, then the
//   search text;
// - typing searches the service (Teams' searchV2 with source oneEvents,
//   the room search for rooms) and the matches drop under the field
//   (above it when there's no room): white, radius 4, the menu shadow;
//   rows 50 tall with a 32 px avatar 16 in, the name 14 #424242 and the
//   second line 12 #616161 (an alias in capitals, a group's mail, a
//   room's "Available · address"), the typed text bold in both; "We
//   couldn't find any matches." when nothing matches;
// - a person already picked in this picker isn't offered again.
// Location draws its own chips (the Teams Online Meeting chip first):
// `chips: false` leaves the tags to it.
Item {
    id: root
    /// "team", "presenters", "attendees" or "rooms".
    property string kind: "team"
    property string placeholder: ""
    /// [{name, email, mri, objectId, tenantId, upn, userType, group, detail}].
    property var picked: []
    property bool chips: true
    /// The room search's time slot ("yyyy-MM-dd HH:mm:ss" in the Windows
    /// zone `zone`).
    property string start: ""
    property string end: ""
    property string zone: ""
    property bool filled: true
    /// Inside another field (Location's Add a room): no box of its own.
    property bool bare: false
    readonly property alias text: input.text
    readonly property bool searching: pending !== ""
    property var results: []
    property bool searched: false
    property string pending: ""
    property int seq: 0
    signal changed(var people)
    implicitHeight: Math.max(32, flow.implicitHeight + 8)
    height: implicitHeight

    function add(p) {
        if (picked.some(x => (x.objectId && x.objectId === p.objectId) || (x.email && x.email === p.email))) return
        const a = picked.slice(); a.push(p); picked = a; changed(a)
        input.text = ""; results = []; searched = false; drop.close()
    }
    function remove(i) { const a = picked.slice(); a.splice(i, 1); picked = a; changed(a) }
    function search() {
        const q = input.text.trim()
        if (!q) { results = []; searched = false; drop.close(); return }
        const id = "picker" + kind + (++seq)
        pending = id
        if (kind === "rooms") backend.eventsRequest("searchRooms", id, JSON.stringify({ query: q, start: start, end: end, zone: zone }))
        else backend.eventsRequest("searchPeople", id, JSON.stringify({ kind: kind, query: q }))
    }
    function focusField() { input.forceActiveFocus() }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id !== root.pending) return
            root.pending = ""
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            const list = (root.kind === "rooms" ? v.rooms : v.people) || []
            root.results = list.filter(p => !root.picked.some(x => x.objectId && x.objectId === p.objectId))
            root.searched = true
            if (input.text.trim()) drop.open()
        }
    }
    Timer { id: debounce; interval: 300; onTriggered: root.search() }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: 4
        color: root.bare ? "transparent" : root.filled ? theme.inputFilledDark : theme.input
        border.width: root.filled || root.bare ? 0 : 1
        border.color: theme.stroke
        Rectangle { visible: input.activeFocus && !root.bare; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        TapHandler { onTapped: input.forceActiveFocus() }
    }
    Flow {
        id: flow
        x: 12; width: parent.width - 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: root.chips ? root.picked : []
            Rectangle {
                id: tag
                required property var modelData
                required property int index
                height: 24; radius: 12; width: tagRow.implicitWidth + 10
                color: "transparent"
                Row {
                    id: tagRow
                    x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Avatar { size: 20; name: tag.modelData.name; photoId: tag.modelData.mri || ""; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: tag.modelData.name; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    FluentIcon {
                        name: "dismiss-12"; size: 12; color: theme.textSecondary; anchors.verticalCenter: parent.verticalCenter
                        TapHandler { onTapped: root.remove(tag.index) }
                        Accessible.role: Accessible.Button; Accessible.name: "Remove " + tag.modelData.name
                    }
                }
            }
        }
        TextInput {
            id: input
            width: root.chips && root.picked.length ? 160 : flow.width
            height: 24
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            clip: true; selectByMouse: true
            onTextEdited: debounce.restart()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Backspace && text === "" && root.chips && root.picked.length) { root.remove(root.picked.length - 1); e.accepted = true }
                else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.results.length) { root.add(root.results[0]); e.accepted = true }
                else if (e.key === Qt.Key_Escape && drop.opened) { drop.close(); e.accepted = true }
            }
            Text {
                visible: !input.text && !(root.chips && root.picked.length)
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: root.placeholder
        }
    }
    // The matches.
    Popup {
        id: drop
        readonly property real below: root.mapToItem(null, 0, root.height).y
        readonly property bool up: Overlay.overlay && below + implicitHeight + 8 > Overlay.overlay.height
        y: up ? -implicitHeight - 2 : root.height + 2
        width: root.width
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
        contentItem: Column {
            Text {
                visible: root.searched && root.results.length === 0
                width: drop.width - 8; height: 50; leftPadding: 12; verticalAlignment: Text.AlignVCenter
                text: root.kind === "rooms" ? "We couldn't find any matches." : "We couldn't find any matches."
                font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
            }
            Repeater {
                model: root.results.slice(0, 8)
                Rectangle {
                    id: row
                    required property var modelData
                    width: drop.width - 8; height: 50; radius: 4
                    color: rh.hovered ? theme.menuHover : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: row.modelData.name; photoId: row.modelData.group ? "" : (row.modelData.mri || "") }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 68
                        Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bolden(row.modelData.name); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                        Row {
                            spacing: 4
                            FluentIcon { visible: root.kind === "rooms"; name: row.modelData.availability === "Free" ? "checkmark-circle-16" : "clock-12"; size: 12; color: row.modelData.availability === "Free" ? theme.greenForeground1 : theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                textFormat: Text.StyledText
                                text: root.kind === "rooms"
                                    ? "<font color='" + (row.modelData.availability === "Free" ? theme.greenForeground1 : theme.textSecondary) + "'>" + (row.modelData.availability === "Free" ? "Available" : row.modelData.availability === "Busy" ? "Busy" : (row.modelData.availability || "Unknown")) + "</font> · " + root.esc(row.modelData.email)
                                    : root.bolden(row.modelData.detail || row.modelData.email)
                                font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                            }
                        }
                    }
                    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.add(row.modelData) }
                    Accessible.role: Accessible.ListItem; Accessible.name: row.modelData.name
                }
            }
        }
    }
    function esc(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;") }
    // The typed text in bold (Teams' match highlight).
    function bolden(t) {
        const q = input.text.trim(), s = String(t || "")
        if (!q) return esc(s)
        const i = s.toLowerCase().indexOf(q.toLowerCase())
        if (i < 0) return esc(s)
        return esc(s.slice(0, i)) + "<b>" + esc(s.slice(i, i + q.length)) + "</b>" + esc(s.slice(i + q.length))
    }
    function typeForTest(q) { input.forceActiveFocus(); input.text = q; search() }
    function pickFirstForTest() {
        const q = input.text.trim().toLowerCase()
        const best = results.find(r => (r.name || "").toLowerCase() === q) || results[0]
        if (best) add(best)
    }
}
