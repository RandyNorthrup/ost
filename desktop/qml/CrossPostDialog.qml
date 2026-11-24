import QtQuick
import QtQuick.Controls.Basic

// Teams' Choose channels (Post in other channels' "+", cross-post-channel-
// selection-dialog, measured on winpc 2026-11-24, TASK-0265): a 600 wide
// dialog (padding 28 0 32, radius 8):
// - "Choose channels" (20/28 600) 30.7 in, the description (14/20, 538.7
//   wide) 36 under it, then a search box (506.7 x 31.3, the 20 px search
//   glyph at its end, an underline) 126.7 down;
// - from 180.7 your teams (40 tall: the team's 28 px picture 5 in, its
//   name 14/20 at 43, a chevron after it; the first one open) and their
//   channels (32 tall, the name at 43, a 16 px checkbox 12 after it, radius
//   2, brand when ticked); the post's own channel reads "{name} (Source)",
//   #BDBDBD, ticked and fixed;
// - "N channel(s) selected" (14/20) 29.3 above the bottom, Cancel and
//   Update (96 x 32; Update disabled until the choice changes).
// Standard channels only (Teams posts to those).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    x: Math.round((parent.width - width) / 2)
    y: Math.round(Math.max(8, (parent.height - height) / 2))
    width: 600; height: 621.3
    padding: 0
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    /// The post's channel, and the other channels chosen.
    property string source: ""
    property var selected: []
    property var initial: []
    signal updated(var channels)
    onAboutToShow: { initial = selected.slice(); search.text = ""; open_ = {}; if (teams.length) open_[teams[0].id] = true; open_ = Object.assign({}, open_) }
    readonly property var teams: (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).filter(t => !t.archived)
    property var open_: ({})
    readonly property bool changed: JSON.stringify(selected.slice().sort()) !== JSON.stringify(initial.slice().sort())
    function standard(c) { return !c.channel_type && !c.archived }
    function channelName(c) { return c.general ? qsTr("General") : c.name }
    /// The rows: [{team}] and [{channel, team}] as shown.
    readonly property var rows: {
        const q = search.text.trim().toLowerCase()
        const out = []
        for (const t of teams) {
            const chans = (t.channels || []).filter(c => standard(c) && (!q || channelName(c).toLowerCase().indexOf(q) >= 0 || String(t.name).toLowerCase().indexOf(q) >= 0))
            if (!chans.length) continue
            out.push({ team: t })
            if (q || open_[t.id]) for (const c of chans) out.push({ channel: c, team: t })
        }
        return out
    }
    function toggle(id) {
        if (id === source) return
        selected = selected.indexOf(id) >= 0 ? selected.filter(c => c !== id) : selected.concat([id])
    }

    Text {
        x: 30.7; y: 28.7; width: 538.7
        text: qsTr("Choose channels")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        lineHeight: 28; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
    }
    Text {
        x: 30.7; y: 64.7; width: 538.7
        wrapMode: Text.Wrap
        text: qsTr("Pick the channels where you want this message posted. Replies to the original post won't be included.")
        font.family: theme.font; font.pixelSize: 14
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Item {
        x: 30.7; y: 126.7; width: 538.7; height: 31.3
        TextInput {
            id: search
            x: 12; width: 506.7 - 14; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text; clip: true
            selectByMouse: true
            Text { visible: !search.text && !search.preeditText; text: qsTr("Search"); font: search.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: qsTr("Search")
        }
        FluentIcon { x: 508.6; anchors.verticalCenter: parent.verticalCenter; size: 20; name: "search-20"; color: theme.textSecondary }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width
            height: search.activeFocus ? 2 : 0.67
            color: search.activeFocus ? theme.brand : theme.textSecondary
        }
    }
    ListView {
        id: list
        x: 30.7; y: 180.7; width: 538.7; height: 360
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool isTeam: !modelData.channel
            readonly property string cid: isTeam ? "" : modelData.channel.id
            readonly property bool own: cid !== "" && cid === root.source
            readonly property bool ticked: own || root.selected.indexOf(cid) >= 0
            width: list.width; height: isTeam ? 40 : 32
            Rectangle {
                anchors.fill: parent
                color: rowHover.hovered && !row.own ? theme.rowHover : "transparent"
            }
            Avatar {
                visible: row.isTeam
                x: 5; y: 6; size: 28; square: true; squareRadius: 4
                name: row.modelData.team.name
                initialsText: String(row.modelData.team.name).split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                photoId: "team:" + row.modelData.team.id
            }
            Text {
                id: label
                x: 43; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width - 43 - 40)
                elide: Text.ElideRight
                text: row.isTeam ? row.modelData.team.name : root.channelName(row.modelData.channel) + (row.own ? " " + qsTr("(Source)") : "")
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: row.own ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : row.isTeam ? theme.textStrong : theme.text
            }
            FluentIcon {
                visible: row.isTeam
                x: label.x + label.width; anchors.verticalCenter: parent.verticalCenter; size: 20
                name: root.open_[row.modelData.team.id] ? "chevron-up-20" : "chevron-down-20"
                color: theme.textStrong
            }
            Rectangle {
                id: box
                visible: !row.isTeam
                x: label.x + label.width + 12; anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 2
                color: row.own ? "transparent" : row.ticked ? theme.brandFill : "transparent"
                border.width: 0.67
                border.color: row.own ? theme.pick("#E0E0E0", "#3D3D3D", "#3FF23F") : row.ticked ? theme.brandFill : theme.textStrong
                FluentIcon {
                    visible: row.ticked
                    anchors.centerIn: parent; size: 12; name: "checkmark-12"
                    color: row.own ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : theme.onFill(box, "white")
                }
            }
            HoverHandler { id: rowHover; cursorShape: row.own ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    if (row.isTeam) { const o = Object.assign({}, root.open_); o[row.modelData.team.id] = !o[row.modelData.team.id]; root.open_ = o }
                    else root.toggle(row.cid)
                }
            }
            Accessible.role: row.isTeam ? Accessible.Button : Accessible.CheckBox
            Accessible.checked: row.ticked
            Accessible.name: row.isTeam ? qsTr("Team, %1").arg(row.modelData.team.name) : qsTr("Channel, %1").arg(label.text)
        }
    }
    Text {
        x: 30.7; y: 558.7
        // (The post's own channel counts.)
        text: root.selected.length + 1 === 1 ? qsTr("1 channel selected") : qsTr("%1 channels selected").arg(root.selected.length + 1)
        font.family: theme.font; font.pixelSize: 14
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    Rectangle {
        id: cancelBtn
        x: 367.3; y: 552.7; width: 96; height: 32; radius: 4
        color: cancelHover.hovered ? theme.hover : theme.surface
        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(cancelBtn, theme.text) }
        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Cancel")
    }
    Rectangle {
        id: updateBtn
        x: 473.3; y: 552.7; width: 96; height: 32; radius: 4
        color: !root.changed ? theme.pick("#F0F0F0", "#141414", "#000000") : updateHover.hovered ? theme.brandHover : theme.brandFill
        Text { anchors.centerIn: parent; text: qsTr("Update"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.changed ? theme.onFill(updateBtn, "white") : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
        HoverHandler { id: updateHover; enabled: root.changed; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.changed; onTapped: { root.updated(root.selected.slice()); root.close() } }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Update")
    }
}
