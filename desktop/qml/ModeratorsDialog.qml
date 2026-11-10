import QtQuick
import QtQuick.Controls.Basic

// Add or remove moderators (Manage channel ▸ Moderation ▸ Manage; Teams'
// dialog, measured on winpc 2026-11-09): 600 x 600, padding 24, radius 8.
// - "Add or remove moderators" (20/28 bold).
// - The search box 52 under the title's top (546 x 32, white, a #D1D1D1
//   hairline with a darker bottom line, brand underline when focused,
//   "Type a name of a person" at 12, a search glyph at the end). Typing
//   searches the team's members (owners and moderators left out); the
//   matches drop 2 under it (546 wide, padding 4), each a person (picture,
//   name, "(ALIAS) job title"); none reads "We didn't find any matches".
//   Picking one adds them to the list.
// - The list 44 under the box: "Team owners" / "{n} people" with the group
//   picture first (Channel owners in private and shared channels), then the
//   moderators, each with their e-mail and Remove at the end; 48.3 tall rows
//   with a #E0E0E0 line under each.
// - "Moderator capability is not audited." (12/16) and Cancel / Done (96 x
//   31.3) along the bottom. Done writes the changes (added and removed
//   moderators), Cancel drops them.
Popup {
    id: dlg
    property string teamId: ""
    property string channelId: ""
    property string ownersLabel: "Team owners"
    property int ownersCount: 0
    property var owners: []
    property var moderators: []
    // The list as edited here.
    property var local: []
    property var results: []
    property string searched: ""
    property bool searching: false

    function start() {
        local = moderators.slice()
        results = []; searched = ""; searching = false
        search.text = ""
        open()
        search.forceActiveFocus()
    }
    function done() {
        const before = moderators.map(m => m.mri)
        const after = local.map(m => m.mri)
        const add = after.filter(id => before.indexOf(id) < 0)
        const remove = before.filter(id => after.indexOf(id) < 0)
        if (add.length || remove.length)
            backend.channelAction("moderators", teamId, channelId, JSON.stringify({ add: add, remove: remove }))
        close()
    }
    function pick(p) {
        if (!local.some(m => m.mri === p.mri)) local = local.concat([{ mri: p.mri, name: p.name, mail: p.mail, detail: p.detail }])
        search.text = ""
        results = []; searched = ""
        search.forceActiveFocus()
    }
    // Owners and the listed moderators aren't offered.
    readonly property var excluded: owners.map(o => o.mri.toLowerCase()).concat(local.map(m => m.mri.toLowerCase()))

    Timer {
        id: debounce
        interval: 300
        onTriggered: {
            const q = search.text.trim()
            if (!q) { dlg.results = []; dlg.searched = ""; return }
            dlg.searching = true
            backend.channelAction("moderator-search", dlg.teamId, dlg.channelId, q)
        }
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op !== "moderator-search" || r.channel !== dlg.channelId || !dlg.opened) return
            if (!r.ok || r.data.query.trim() !== search.text.trim()) { dlg.searching = false; return }
            dlg.searching = false
            dlg.searched = r.data.query
            dlg.results = (r.data.people || []).filter(p => dlg.excluded.indexOf(p.mri.toLowerCase()) < 0)
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; height: 600; padding: 24
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            x: 0.7; y: 0.7
            text: "Add or remove moderators"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }

        // The search box.
        Rectangle {
            id: box
            x: 0.7; y: 52.7; width: 546; height: 32; radius: 4
            color: theme.surface
            border.color: theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 0.67; color: theme.textSecondary }
            Rectangle {
                visible: search.activeFocus
                anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
                color: theme.brand
            }
            TextInput {
                id: search
                x: 12; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                selectByMouse: true
                clip: true
                onTextChanged: {
                    if (!text.trim()) { debounce.stop(); dlg.results = []; dlg.searched = ""; return }
                    debounce.restart()
                }
                Keys.onEscapePressed: event => {
                    if (text) { text = ""; event.accepted = true }
                    else { event.accepted = false }
                }
                Text {
                    visible: !search.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Type a name of a person"
                    font: search.font
                    color: theme.textTertiary
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Type a name of a person"
            }
            FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
        }

        // The list.
        Flickable {
            x: 0.7; y: 96.7
            width: 532; height: parent.height - y - 56
            contentHeight: rows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: rows
                width: parent.width
                Row48 {
                    header: dlg.ownersLabel
                    content: dlg.ownersCount + " people"
                    group: true
                }
                Repeater {
                    model: dlg.local
                    Row48 {
                        required property var modelData
                        required property int index
                        header: modelData.name
                        content: modelData.mail || ""
                        mri: modelData.mri
                        removable: true
                        onRemove: dlg.local = dlg.local.filter(m => m.mri !== modelData.mri)
                    }
                }
            }
            Accessible.role: Accessible.Table
            Accessible.name: "Moderator List"
        }

        // The matches, over the list.
        Item {
            visible: search.text.trim().length > 0 && (dlg.searched.length > 0 || dlg.results.length > 0)
            x: box.x; y: box.y + box.height + 2
            width: 546; height: Math.min(529.3, matches.implicitHeight + 8)
            FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
            Flickable {
                anchors.fill: parent; anchors.margins: 4
                contentHeight: matches.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: matches
                    width: parent.width
                    Rectangle {
                        visible: dlg.results.length === 0
                        width: parent.width; height: 32; radius: 4
                        color: "transparent"
                        Text {
                            x: 28; anchors.verticalCenter: parent.verticalCenter
                            text: "We didn't find any matches"
                            font.family: theme.font; font.pixelSize: 14
                            color: theme.text
                        }
                    }
                    Repeater {
                        model: dlg.results
                        Rectangle {
                            id: match
                            required property var modelData
                            width: matches.width; height: 48; radius: 4
                            color: matchHover.hovered ? theme.menuHover : "transparent"
                            Avatar { x: 8; y: 8; size: 32; name: match.modelData.name || "?"; photoId: match.modelData.mri }
                            Text {
                                x: 48; y: 6; width: parent.width - 56; elide: Text.ElideRight
                                text: match.modelData.name
                                font.family: theme.font; font.pixelSize: 14
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                                color: theme.text
                            }
                            Text {
                                x: 48; y: 26; width: parent.width - 56; elide: Text.ElideRight
                                text: match.modelData.detail
                                font.family: theme.font; font.pixelSize: 12
                                lineHeight: 16; lineHeightMode: Text.FixedHeight
                                color: theme.textSecondary
                            }
                            HoverHandler { id: matchHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: dlg.pick(match.modelData) }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: match.modelData.name
                        }
                    }
                }
            }
        }

        // Footer.
        Text {
            x: 0.7; y: 524.2
            text: "Moderator capability is not audited."
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 17.1; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Row {
            x: 349.3; y: 520
            spacing: 10
            DialogButton { text: "Cancel"; onClicked: dlg.close() }
            DialogButton { text: "Done"; primary: true; onClicked: dlg.done() }
        }
    }

    component Row48: Item {
        id: row
        property string header
        property string content
        property string mri: ""
        property bool group: false
        property bool removable: false
        signal remove()
        width: rows.width; height: 48.3
        Rectangle {
            x: 8; y: 8; width: 32; height: 32; radius: 16
            visible: row.group
            color: theme.pick("#E6E6E6", "#3D3D3D")
            FluentIcon { anchors.centerIn: parent; name: "people-team-20"; size: 20; color: theme.textSecondary }
        }
        Avatar { visible: !row.group; x: 8; y: 8; size: 32; name: row.header || "?"; photoId: row.mri }
        Text {
            x: 48; y: 6; width: parent.width - 48 - (row.removable ? 48 : 8); elide: Text.ElideRight
            text: row.header
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            x: 48; y: 26; width: parent.width - 48 - (row.removable ? 48 : 8); elide: Text.ElideRight
            text: row.content
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            visible: row.removable
            x: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 4
            color: "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: removeHover.hovered ? theme.brand : theme.textStrong }
            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.remove() }
            Accessible.role: Accessible.Button
            Accessible.name: "Remove " + row.header
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    component DialogButton: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: btn.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function searchForTest(q) { search.text = q }
}
