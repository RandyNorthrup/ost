import QtQuick
import QtQuick.Controls.Basic

// Manage team ▸ Members (Teams' tab, measured on winpc 2026-11-09;
// docs/spec/chat-list-and-header.md §5.6.4). Offsets from the tab area:
// - Add member (transparent, the add glyph, 14/20 semibold #424242) at 40,
//   20.6; Search members (278.7 x 30.7, outlined) 21.3 from the right.
// - Sections (44 tall headers, chevron at 10, label 14/20 at 38) 42 in,
//   74.3 down: Owners (n) and Members and guests (n).
// - Their grids 12 further in: a 48.7 header (12/16: Name, Title, Location,
//   Tags with an info glyph, Team role; 146.8 wide columns, padding 0 8),
//   rows 44.7 with a #EBEBEB line: the picture (32, presence) and name; the
//   title; the location; the person's tags as chips (12 bold #4F52B2, a
//   #DCE0FA border, radius 4); the role (Owner / Member, a transparent
//   dropdown; Guest stays); Remove from team for members.
// Role changes and removals are Teams' membership updates (Promoted,
// Demoted, Left).
Item {
    id: view
    property string teamId: ""
    property string teamThread: ""
    property bool owner: false
    property string myPresence: ""
    property var members: []
    property bool ownersOpen: true
    property bool othersOpen: true
    signal addMember()
    readonly property string myMri: (backend.userMri || "").toLowerCase()
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var shown: members.filter(m => !query || (m.name || "").toLowerCase().indexOf(query) >= 0)
    readonly property var owners: shown.filter(m => m.role === "Admin")
    readonly property var others: shown.filter(m => m.role !== "Admin")

    function load() { if (teamThread) backend.channelAction("team-roster", teamId, teamThread, "") }
    onTeamThreadChanged: { members = []; search.text = ""; load() }
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== view.teamThread) return
            if (r.op === "team-roster" && r.ok) view.members = r.data.members || []
            else if (r.op === "team-membership") {
                if (!r.ok || r.data.code) backend.toast("Something went wrong on our end. Please try again.", "error")
                view.load()
            } else if (r.op === "add-members") view.load()
        }
    }

    Rectangle {
        x: 40; y: 20.6; width: 134.8; height: 31.3; radius: 4
        color: addHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { x: 12.7; anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: theme.textStrong }
        Text { x: 38.7; anchors.verticalCenter: parent.verticalCenter; text: "Add member"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: view.addMember() }
        Accessible.role: Accessible.Button
        Accessible.name: "Add member"
    }
    Rectangle {
        x: parent.width - 21.3 - width; y: 21; width: 278.7; height: 30.7; radius: 4
        color: theme.surface
        border.color: theme.stroke; border.width: 0.67
        Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: search.activeFocus ? 2 : 0.67; color: search.activeFocus ? theme.brand : theme.textSecondary }
        TextInput {
            id: search
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            clip: true
            selectByMouse: true
            Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; text: "Search members"; font: search.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Search members"
        }
    }

    Flickable {
        x: 42; y: 74.3; width: parent.width - 64; height: parent.height - y
        contentHeight: sections.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: sections
            width: parent.width
            Section {
                label: "Owners (" + view.owners.length + ")"
                open: view.ownersOpen; onToggled: view.ownersOpen = !view.ownersOpen
                Grid_ { people: view.owners }
            }
            Section {
                label: "Members and guests (" + view.others.length + ")"
                open: view.othersOpen && view.others.length > 0; onToggled: view.othersOpen = !view.othersOpen
                Grid_ { people: view.others }
            }
        }
    }

    component Section: Column {
        id: sec
        property string label
        property bool open: false
        default property alias body: bodyCol.data
        signal toggled()
        width: parent ? parent.width : 0
        Rectangle {
            width: parent.width; height: 44; radius: 4
            color: secHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: sec.open ? "chevron-down-20" : "chevron-right-20"; size: 20; color: theme.text }
            Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: sec.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            HoverHandler { id: secHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sec.toggled() }
            Accessible.role: Accessible.Button
            Accessible.name: sec.label
        }
        Column { id: bodyCol; visible: sec.open; width: parent.width }
    }

    component Grid_: Item {
        id: grid
        property var people: []
        readonly property real col: 146.8
        x: 12; width: parent ? parent.width - 24 : 0
        height: people.length ? 48.7 + people.length * 44.7 + 4 : 0
        Repeater {
            model: grid.people.length ? ["Name", "Title", "Location", "Tags", "Team role"] : []
            Row {
                required property string modelData
                required property int index
                x: 8 + index * grid.col + 10; y: 16
                spacing: 10
                Text { text: modelData; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                FluentIcon { visible: modelData === "Tags"; y: -1.7; name: "info-16-regular"; size: 16; color: theme.text }
            }
        }
        Column {
            y: 52.7; x: 4; width: parent.width - 8
            Repeater {
                model: grid.people
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool me: modelData.mri.toLowerCase() === view.myMri
                    width: parent.width; height: 44.7
                    color: rowHover.hovered ? theme.menuHover : "transparent"
                    HoverHandler { id: rowHover }
                    Avatar {
                        x: 14; y: 6; size: 32
                        name: row.modelData.name || "?"
                        photoId: row.modelData.mri
                        presence: row.me ? view.myPresence : ""
                    }
                    Text {
                        x: 56; width: grid.col - 52; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Text {
                        x: 4 + grid.col + 10; width: grid.col - 20; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Text {
                        x: 4 + grid.col * 2 + 10; width: grid.col - 20; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.location || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Row {
                        x: 4 + grid.col * 3 + 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: (row.modelData.tags || []).slice(0, 2)
                            Rectangle {
                                required property string modelData
                                width: chip.implicitWidth + 16; height: 23.3; radius: 4
                                color: "transparent"
                                border.color: theme.pick("#DCE0FA", "#3D3E78"); border.width: 0.67
                                Text { id: chip; anchors.centerIn: parent; text: modelData; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; color: theme.brandForeground1 }
                            }
                        }
                    }
                    // Team role.
                    Item {
                        id: role
                        x: 4 + grid.col * 4 + 15; y: 7.3; width: roleRow.implicitWidth; height: 30
                        readonly property bool changeable: view.owner && row.modelData.role !== "Guest"
                        Row {
                            id: roleRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.role === "Admin" ? "Owner" : row.modelData.role === "Guest" ? "Guest" : "Member"
                                font.family: theme.font; font.pixelSize: 14
                                color: theme.text
                            }
                            FluentIcon { visible: role.changeable; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
                        }
                        HoverHandler { enabled: role.changeable; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: role.changeable; onTapped: roleMenu.open() }
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: "Current role for " + (row.modelData.name || "") + " is " + (row.modelData.role === "Admin" ? "Owner" : "Member") + ". Open the change role dropdown."
                        Popup {
                            id: roleMenu
                            y: role.height + 2; width: 127.6; height: 74; padding: 4
                            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                            Column {
                                spacing: 2
                                Repeater {
                                    model: [["Owner", "Admin"], ["Member", "User"]]
                                    Rectangle {
                                        id: opt
                                        required property var modelData
                                        readonly property bool chosen: row.modelData.role === modelData[1]
                                        width: 119.6; height: 32; radius: 4
                                        color: optHover.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { visible: opt.chosen; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.text }
                                        Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: opt.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                        HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                roleMenu.close()
                                                if (!opt.chosen) backend.channelAction("team-membership", view.teamId, view.teamThread, JSON.stringify({ mri: row.modelData.mri, update: opt.modelData[1] === "Admin" ? "Promoted" : "Demoted" }))
                                            }
                                        }
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: opt.modelData[0]
                                    }
                                }
                            }
                        }
                    }
                    // Remove from team (owners, for others).
                    Rectangle {
                        visible: view.owner && !row.me && rowHover.hovered
                        x: 4 + grid.col * 5 + 10; y: 6.7; width: 32; height: 31.3; radius: 4
                        color: "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: rmHover.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.channelAction("team-membership", view.teamId, view.teamThread, JSON.stringify({ mri: row.modelData.mri, update: "Left" })) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove from team"
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#EBEBEB", "#333333") }
                }
            }
        }
    }
}
