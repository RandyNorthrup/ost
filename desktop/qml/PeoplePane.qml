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
    /// In the lobby: [{id, name, suspected}].
    property var lobby: []
    property bool meeting: true
    signal closed()
    signal admit(string id, string name)
    /// A suspected guest: Teams asks first.
    signal admitSuspected(string id, string name)
    signal deny(string id, string name)
    /// Teams' Admit all (no suspected guests waiting).
    signal admitAll()
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

    // The rows, flattened: sections, subsections and people.
    readonly property var rows: {
        const out = []
        const waiting = lobby.filter(p => !p.suspected && matches(p.name))
        const threats = lobby.filter(p => p.suspected && matches(p.name))
        const lobbyShown = waiting.length + threats.length
        if (lobbyShown > 0) {
            const split = threats.length > 0
            out.push({ kind: "section", key: "lobby", title: "Waiting in lobby (" + lobbyShown + ")",
                       action: !split && lobbyShown > 1 ? "Admit all" : "", level: 0 })
            if (!collapsed.lobby) {
                if (split) {
                    if (waiting.length > 0) {
                        out.push({ kind: "section", key: "waiting", title: "Waiting (" + waiting.length + ")",
                                   action: waiting.length > 1 ? "Admit (" + waiting.length + ")" : "", level: 1, list: waiting })
                        if (!collapsed.waiting) waiting.forEach(p => out.push({ kind: "lobby", p: p, level: 2 }))
                    }
                    out.push({ kind: "section", key: "threats", title: "Suspected threats (" + threats.length + ")",
                               action: threats.length > 1 ? "Deny (" + threats.length + ")" : "", level: 1, list: threats })
                    if (!collapsed.threats) threats.forEach(p => out.push({ kind: "lobby", p: p, level: 2 }))
                } else {
                    waiting.forEach(p => out.push({ kind: "lobby", p: p, level: 1 }))
                }
            }
        }
        const here = people.filter(p => matches(p.name))
        out.push({ kind: "section", key: "here", title: (meeting ? "In this meeting (" : "In this call (") + here.length + ")", action: "", level: 0 })
        if (!collapsed.here) here.forEach(p => out.push({ kind: "person", p: p, level: 1 }))
        return out
    }

    // Header: "Participants" and close (rail-header, 58 tall, from y 3).
    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.7; y: 17.7; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Participants"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            x: parent.width - 52; y: 13.7; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close participants pane"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // "Type a name"
    Rectangle {
        id: search
        x: 20.7; y: 77; width: 319.3; height: 32; radius: 4
        color: theme.surface
        TextInput {
            id: field
            x: 12.6; width: 274; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            clip: true
            selectByMouse: true
            onTextChanged: root.query = text.trim()
            Accessible.role: Accessible.EditableText
            Accessible.name: "Type a name"
        }
        Text {
            visible: field.text.length === 0
            x: field.x; anchors.verticalCenter: parent.verticalCenter
            text: "Type a name"
            font.family: theme.font; font.pixelSize: 14
            color: theme.textTertiary
        }
        FluentIcon { x: 288.6; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
        // Teams' focused input: a 2 px brand line along the bottom.
        Rectangle { visible: field.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
    }

    Flickable {
        id: list
        y: search.y + search.height + 10
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
                visible: !!entry.action
                anchors.right: parent.right; anchors.rightMargin: 22
                y: 7; height: 24; radius: 4
                width: Math.max(72, actionText.implicitWidth + 21.3)
                color: actionHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 0.67
                Text {
                    id: actionText
                    anchors.centerIn: parent
                    text: entry.action || ""
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.text
                }
                HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (entry.key === "lobby") root.admitAll()
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
                icon: "checkmark-20"; tint: theme.pick("#107C10", "#54B054"); label: "Admit participant in lobby"
                onClicked: p.suspected ? root.admitSuspected(p.id, p.name) : root.admit(p.id, p.name)
            }
            LobbyButton {
                x: parent.width - 50; y: 12
                icon: "dismiss-20"; tint: theme.redForeground3; label: "Deny participant in lobby"
                onClicked: root.deny(p.id, p.name)
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (p.name || "") + (p.suspected ? " Unverified" : "")
        }
    }

    // Someone in the call: avatar, name, role, raised hand, mic.
    Component {
        id: personRow
        Item {
            property var entry: ({ p: {} })
            readonly property var p: entry.p || ({})
            height: 48
            Avatar { visible: !p.suspected; x: 21.7; y: 8; size: 32; name: p.name || ""; photoId: p.guest ? "" : (p.id || "") }
            GuestAvatar { visible: !!p.suspected; x: 21.7; y: 8; personId: p.id || "" }
            Column {
                x: 65.7; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 65.7 - 46
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
                // Teams names only the organizer here.
                Text {
                    visible: (p.role || "").toLowerCase() === "organizer"
                    height: 16; verticalAlignment: Text.AlignVCenter
                    text: "Organizer"
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.textStrong
                }
                id: personRowColumn
            }
            Text {
                visible: !!p.hand
                anchors.right: parent.right; anchors.rightMargin: 64; anchors.verticalCenter: parent.verticalCenter
                text: "\u270B"; font.pixelSize: 16
            }
            FluentIcon {
                x: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                name: p.mutedNow ? "mic-off-20" : "roster-mic-20"; size: 20
                color: theme.text
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (p.name || "") + (p.hand ? ", hand raised" : "") + (p.mutedNow ? ", muted" : "")
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
        FluentIcon { anchors.centerIn: parent; name: lb.icon; size: 20; color: lb.tint }
        HoverHandler { id: lbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: lb.label
    }

    // Test hooks.
    function rowsForTest() { return JSON.stringify(rows) }
}
