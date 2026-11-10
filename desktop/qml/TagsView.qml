import QtQuick
import QtQuick.Controls.Basic

// Manage team ▸ Tags (a team's menu ▸ Manage tags; Teams' tab, measured on
// winpc 2026-11-09; docs/spec/chat-list-and-header.md §5.6.2). Offsets are
// from the tab area's top left.
// - List: "Search for tags" (170 x 32, a search glyph at its end) 52 in,
//   32.3 down; Create tag (brand, the tag glyph) 52 from the right. Then
//   three sections 60 in, 82.3 down (44 tall headers: chevron 20 at 10, the
//   name 14/20 at 38): Tags assigned to you (n), Other tags (n), Deleted (n).
//   Each holds a table 12 further in (header 34: Name, Members,
//   Description, Imported from, 12/16 in 149.6 wide columns; rows 44 with a
//   #FAFAFA line: the tag's round badge (32, #C5CBFA, the glyph #444791),
//   its name 14/20; the people glyph and the count; the description; ···
//   at the end with Chat with group, Create a copy | Delete). A deleted
//   tag's row offers Restore.
// - A tag: All tags (back, 600) 52 in; Add people, Edit tag details, Create
//   a copy | Delete tag (32 x 31.3 icon buttons) at the right; the badge (42)
//   and name (16/22 bold) 100.3 down; "Members (n)" (14/20 bold) 190.3 down
//   and its table (Name, Title, Location, Organization, 154.4 wide; rows 44
//   with the picture 32 and presence, Remove at the end).
// Only owners change tags when the team says so (onlyOwnersCanUpdate).
Item {
    id: view
    property string teamId: ""
    property string teamThread: ""
    property bool owner: false
    property string myPresence: ""
    property var list: null
    property var open: null
    property var people: []
    property bool peopleLoaded: false
    property bool mineOpen: true
    property bool otherOpen: false
    property bool deletedOpen: false
    property string pendingChat: ""
    signal chatWithGroup(var people)
    readonly property bool canChange: owner || (list !== null && !list.only_owners)
    readonly property string myMri: (backend.userMri || "").toLowerCase()
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var matching: (list ? list.tags : []).filter(t => !query || t.name.toLowerCase().indexOf(query) >= 0)
    readonly property var mine: matching.filter(t => t.mine)
    readonly property var others: matching.filter(t => !t.mine)
    readonly property var deleted: (list ? list.deleted : []).filter(t => !query || t.name.toLowerCase().indexOf(query) >= 0)

    function load() { if (teamThread) backend.channelAction("tags-load", teamId, teamThread, "") }
    function show(tag) {
        open = tag; people = []; peopleLoaded = false
        backend.channelAction("tag-members", teamId, teamThread, tag.id)
    }
    function act(op, arg) { backend.channelAction(op, teamId, teamThread, typeof arg === "string" ? arg : JSON.stringify(arg)) }
    onTeamThreadChanged: { list = null; open = null; search.text = ""; load() }
    Component.onCompleted: load()

    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== view.teamThread || !/^tag/.test(r.op)) return
            if (r.op === "tags-load" && r.ok) {
                view.list = r.data
                if (view.open) view.open = r.data.tags.find(t => t.id === view.open.id) || null
            } else if (r.op === "tag-members" && r.ok && r.data.tag === view.pendingChat) {
                // Chat with group: a new chat with the tag's people (you left out).
                view.pendingChat = ""
                view.chatWithGroup((r.data.people || []).filter(p => p.mri.toLowerCase() !== view.myMri).map(p => ({ id: p.mri.replace(/^8:orgid:/, ""), name: p.name })))
            } else if (r.op === "tag-members" && r.ok && view.open && r.data.tag === view.open.id) {
                view.people = r.data.people || []
                view.peopleLoaded = true
            } else if (["tag-create", "tag-update", "tag-delete", "tag-restore", "tag-add-members", "tag-remove-members"].indexOf(r.op) >= 0) {
                if (!r.ok) {
                    const msg = r.op === "tag-delete" ? "We're having trouble deleting the tag. Please try again later."
                        : r.op === "tag-restore" ? "We're having trouble restoring the tag. Please try again later."
                        : r.op === "tag-create" ? "We couldn't create the tag"
                        : /already|duplicate|409/i.test(r.error || "") ? "This tag name is already taken." : "We ran into a problem"
                    backend.toast(msg, "error")
                }
                if (r.op === "tag-delete" && r.ok) view.open = null
                view.load()
                if (view.open && r.ok && r.op !== "tag-delete") view.show(view.open)
            }
        }
    }

    // ---- List ----
    Item {
        visible: !view.open
        anchors.fill: parent
        Item {
            id: searchBox
            x: 52; y: 32.3; width: 170; height: 32
            TextInput {
                id: search
                x: 12; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Text {
                    visible: !search.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search for tags"
                    font: search.font
                    color: theme.textSecondary
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search for tags"
            }
            FluentIcon { x: 176; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
            Rectangle { visible: search.activeFocus; anchors.bottom: parent.bottom; width: parent.width + 30; height: 2; radius: 1; color: theme.brand }
        }
        Rectangle {
            visible: view.canChange
            x: parent.width - 52 - width; y: 32.6
            width: createRow.implicitWidth + 24; height: 31.3; radius: 4
            color: createHover.hovered ? theme.brandHover : theme.brandFill
            Row {
                id: createRow
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { name: "tag-20"; size: 20; color: theme.textOnBrand }
                Text { text: "Create tag"; anchors.verticalCenter: parent.verticalCenter; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            }
            HoverHandler { id: createHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dialog.startCreate([]) }
            Accessible.role: Accessible.Button
            Accessible.name: "Create tag"
        }

        Flickable {
            x: 60; y: 82.3; width: parent.width - 120; height: parent.height - y
            contentHeight: sections.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: sections
                width: parent.width
                Section {
                    label: "Tags assigned to you (" + view.mine.length + ")"
                    open: view.mineOpen; onToggled: view.mineOpen = !view.mineOpen
                    TagTable { tags: view.mine; emptyText: view.list ? "No tags are currently assigned to you" : "" }
                }
                Section {
                    label: "Other tags (" + view.others.length + ")"
                    open: view.otherOpen; onToggled: view.otherOpen = !view.otherOpen
                    TagTable { tags: view.others }
                }
                Section {
                    label: "Deleted (" + view.deleted.length + ")"
                    open: view.deletedOpen; onToggled: view.deletedOpen = !view.deletedOpen
                    TagTable { tags: view.deleted; deletedRows: true }
                }
            }
        }
    }

    // ---- A tag ----
    Item {
        visible: !!view.open
        anchors.fill: parent
        Rectangle {
            x: 52; y: 32.6; width: 96; height: 31.3; radius: 4
            color: backHover.hovered ? theme.menuHover : "transparent"
            Row {
                x: 9.3; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-left-12"; size: 12; color: theme.textStrong }
                Text { text: "All tags"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: view.open = null }
            Accessible.role: Accessible.Button
            Accessible.name: "All tags"
        }
        Row {
            visible: view.canChange
            x: parent.width - 84 - width; y: 32.6
            spacing: 10
            IconButton { icon: "person-add-20"; label: "Add people"; onClicked: dialog.startAdd(view.open, view.people) }
            IconButton { icon: "edit-20"; label: "Edit tag details"; onClicked: dialog.startEdit(view.open) }
            IconButton { icon: "copy-20"; label: "Create a copy"; onClicked: dialog.startCopy(view.open, view.people) }
            Rectangle { width: 0.67; height: 32; color: theme.divider }
            IconButton { icon: "delete-20"; label: "Delete tag"; onClicked: dialog.startDelete(view.open) }
        }
        Badge { x: 76; y: 100.3; size: 42 }
        Text {
            x: 130; y: 110.3
            text: view.open ? view.open.name : ""
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            visible: !!view.open && !!view.open.description
            x: 130; y: 134
            width: parent.width - 200; elide: Text.ElideRight
            text: view.open ? view.open.description : ""
            font.family: theme.font; font.pixelSize: 14
            color: theme.textSecondary
        }
        Text {
            x: 52; y: 190.3
            text: "Members (" + (view.peopleLoaded ? view.people.length : (view.open ? view.open.count : 0)) + ")"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item {
            id: memberTable
            x: 52; y: 210.3; width: parent.width - 120; height: parent.height - y
            readonly property real col: width / 5
            Repeater {
                model: ["Name", "Title", "Location", "Organization"]
                Text {
                    required property string modelData
                    required property int index
                    x: index * memberTable.col + 8; y: 8.8
                    text: modelData
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.text
                }
            }
            Flickable {
                y: 34; width: parent.width; height: parent.height - 34
                contentHeight: memberRows.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: memberRows
                    width: parent.width
                    Repeater {
                        model: view.people
                        Rectangle {
                            id: personRow
                            required property var modelData
                            width: memberRows.width; height: 44
                            color: personHover.hovered ? theme.menuHover : "transparent"
                            HoverHandler { id: personHover }
                            Avatar {
                                x: 8; y: 6; size: 32
                                name: personRow.modelData.name || "?"
                                photoId: personRow.modelData.mri
                                presence: personRow.modelData.mri.toLowerCase() === view.myMri ? view.myPresence : ""
                            }
                            Repeater {
                                model: [personRow.modelData.name, personRow.modelData.title, personRow.modelData.location, personRow.modelData.organization]
                                Text {
                                    required property string modelData
                                    required property int index
                                    x: index * memberTable.col + (index === 0 ? 50 : 8)
                                    width: memberTable.col - (index === 0 ? 58 : 16); elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData || ""
                                    font.family: theme.font; font.pixelSize: 14
                                    color: theme.text
                                }
                            }
                            IconButton {
                                visible: view.canChange
                                x: parent.width - 40; y: 6.3
                                icon: "dismiss-20"; label: "Remove " + (personRow.modelData.name || "")
                                onClicked: view.act("tag-remove-members", { id: view.open.id, name: view.open.name, members: [personRow.modelData.mri] })
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#FAFAFA", "#2E2E2E") }
                        }
                    }
                }
            }
        }
    }

    TagDialog {
        id: dialog
        teamId: view.teamId
        teamThread: view.teamThread
    }
    MenuPopup {
        id: rowMenu
        property var tag: null
        margins: 8
        items: [
            { key: "chat", label: "Chat with group", icon: "chat-20" },
            { key: "copy", label: "Create a copy", icon: "copy-20" },
            { separator: true },
            { key: "delete", label: "Delete", icon: "delete-20" }
        ].filter(i => view.canChange || i.key === "chat")
        onPicked: i => {
            const k = items[i].key, t = rowMenu.tag
            if (k === "chat") { view.pendingChat = t.id; view.act("tag-members", t.id) }
            else if (k === "copy") dialog.startCopy(t, null)
            else if (k === "delete") dialog.startDelete(t)
        }
    }

    // A section of the list.
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
    // A section's table.
    component TagTable: Item {
        id: table
        property var tags: []
        property string emptyText: ""
        property bool deletedRows: false
        readonly property real col: width / 5
        x: 12; width: parent ? parent.width - 24 : 0
        height: tags.length ? 34 + tags.length * 44 : (emptyText ? 44 : 0)
        Repeater {
            model: table.tags.length ? ["Name", "Members", "Description", "Imported from"] : []
            Text {
                required property string modelData
                required property int index
                x: index * table.col + 8; y: 8.8
                text: modelData
                font.family: theme.font; font.pixelSize: 12
                color: theme.text
            }
        }
        Text {
            visible: !table.tags.length && !!table.emptyText
            x: 8; height: 44; verticalAlignment: Text.AlignVCenter
            text: table.emptyText
            font.family: theme.font; font.pixelSize: 14
            color: theme.textSecondary
        }
        Column {
            y: 34; width: parent.width
            Repeater {
                model: table.tags
                Rectangle {
                    id: tagRow
                    required property var modelData
                    width: table.width; height: 44
                    color: tagHover.hovered ? theme.menuHover : "transparent"
                    HoverHandler { id: tagHover; cursorShape: table.deletedRows ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    TapHandler { enabled: !table.deletedRows; onTapped: view.show(tagRow.modelData) }
                    Badge { x: 8; y: 6; size: 32 }
                    Text {
                        x: 50; width: table.col - 58; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagRow.modelData.name
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Row {
                        x: table.col + 8; anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        FluentIcon { name: "people-20"; size: 20; color: theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(tagRow.modelData.count); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                    Text {
                        x: table.col * 2 + 8; width: table.col - 16; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagRow.modelData.description || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    Text {
                        x: table.col * 3 + 8; width: table.col - 16; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagRow.modelData.source || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                    }
                    // Restore (deleted) or ···.
                    Rectangle {
                        visible: table.deletedRows && view.canChange
                        x: parent.width - 8 - width; anchors.verticalCenter: parent.verticalCenter
                        width: restoreText.implicitWidth + 24; height: 31.3; radius: 4
                        color: restoreHover.hovered ? theme.menuHover : theme.surface
                        border.color: theme.stroke; border.width: 0.67
                        Text { id: restoreText; anchors.centerIn: parent; text: "Restore"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                        HoverHandler { id: restoreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: view.act("tag-restore", tagRow.modelData.id) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Restore"
                    }
                    IconButton {
                        id: more
                        visible: !table.deletedRows
                        x: parent.width - 40; y: 6.3
                        icon: "more-horizontal-20"; label: "More options"
                        onClicked: { rowMenu.tag = tagRow.modelData; rowMenu.parent = more; rowMenu.x = more.width - rowMenu.implicitWidth; rowMenu.y = more.height + 4; rowMenu.open() }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#FAFAFA", "#2E2E2E") }
                }
            }
        }
    }
    // The round tag badge.
    component Badge: Rectangle {
        property int size: 32
        width: size; height: size; radius: size / 2
        color: theme.pick("#C5CBFA", "#3D3E78")
        FluentIcon { anchors.centerIn: parent; name: parent.size > 36 ? "tag-24" : "tag-20"; size: parent.size > 36 ? 24 : 20; color: theme.pick("#444791", "#C5CBFA") }
    }
    component IconButton: Rectangle {
        id: ib
        property string icon
        property string label
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: ibHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: 20; color: ibHover.hovered ? theme.brand : theme.textStrong }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        ToolTip.visible: ibHover.hovered
        ToolTip.text: label
        ToolTip.delay: 500
    }

    // Test hooks.
    function dialogForTest() { return dialog }
    function rowMenuForTest() { return rowMenu }
}
