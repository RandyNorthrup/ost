import QtQuick
import QtQuick.Controls.Basic

// A video's "Add to playlist" (TASK-0123), as Teams' Files app shows it:
// OneDrive's file picker in its playlist mode (FilePicker.aspx, scenario
// StreamPlaylist.AddToPlaylist; measured on winpc 2026-11-19 in a 1140
// wide frame, docs/spec/file-actions.md "Add to playlist").
// - Left (228): "Add to playlist" (20/600 #242424 at 24, 20), then My lists,
//   Recent lists and Favorites (204 x 40 from 12, 74.67; a 16 px glyph at
//   24, the label at 50), "Quick access" (14/600) with your sites (a 24 px
//   tile at 24, the name at 56, rows 40) and "More places...".
// - Right from 245.33: the place's name (18/600 at 251.67, 24), the search
//   box, and the list on a white card (radius 12 at the top): Type, Name and
//   Modified (Accessed in Recent lists), the header 49.67 tall and rows 59
//   (a check circle at 23, the 32 px playlist icon at 58, the name at 104,
//   the time at 374).
// - The tray 24 from the bottom right: New playlist, Done (until a pick,
//   disabled) and Cancel, 8 apart.
// New playlist opens the list form (Name "Playlist", Description, Save to
// My lists, Create / Cancel); Create makes it and adds the video.
Popup {
    id: pk
    /// FileActions (its tag, notices and Quick access).
    property var actions: null
    property var target: null
    property string place: "mine"
    property var lists: []
    property bool loading: false
    property string error: ""
    property var picked: null
    property string query: ""
    property var site: null
    readonly property color ink: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
    readonly property var shown: query ? lists.filter(l => l.title.toLowerCase().indexOf(query.toLowerCase()) >= 0) : lists
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true; padding: 0
    width: Math.min(1140, Overlay.overlay ? Overlay.overlay.width - 32 : 1140)
    height: Math.min(720, Overlay.overlay ? Overlay.overlay.height - 32 : 720)
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    background: Rectangle { color: theme.pick("#F5F5F5", "#141414", "#000000"); radius: 4 }

    function openFor(it) {
        target = it; picked = null; query = ""; site = null
        open()
        load("mine")
    }
    function load(p) {
        place = p; picked = null; error = ""; lists = []; site = null
        if (p === "mine" || p === "recent") {
            loading = true
            backend.driveAction(actions.tag + "playlists", JSON.stringify(target), JSON.stringify({ place: p }))
        } else loading = false
    }
    function done() {
        if (!picked) return
        const t = target, l = picked
        close()
        actions.notice("progress", qsTr("Adding to the playlist"))
        backend.driveAction(actions.tag + "playlist_add", JSON.stringify(t), JSON.stringify({ list: l }))
    }
    function create(name, description) {
        const t = target
        close()
        actions.notice("progress", qsTr("Adding to the playlist"))
        backend.driveAction(actions.tag + "playlist_create", JSON.stringify(t), JSON.stringify({ name: name, description: description }))
    }
    /// FileActions hands over the backend's answers.
    function reply(kind, v, err) {
        if (kind === "playlists") {
            if (!v || v.place !== place) { if (err) { loading = false; error = err } return }
            loading = false; lists = v.lists || []
            return
        }
        if (err) {
            const denied = /\b403\b|Access denied|UnauthorizedAccess/i.test(err)
            actions.notice("error", qsTr("Couldn't add to the playlist."),
                           denied ? qsTr("Sorry, you do not have permission to add to this playlist. Select a different one.") : qsTr("Sorry, there was a problem adding to this playlist, please try again."))
            return
        }
        const url = v && v.list ? v.list.url + "/AllItems.aspx?env=WebViewList" : ""
        // OneDrive's string starts with a space.
        actions.notice("done", qsTr(" Added to the playlist").trim(), "", url ? qsTr("View") : "", url)
    }
    function relTime(iso) {
        if (!iso) return ""
        const t = new Date(String(iso).replace(/\.(\d{3})\d*Z$/, ".$1Z")), now = new Date(), s = (now - t) / 1000
        if (isNaN(s)) return ""
        if (s < 60) return qsTr("A few seconds ago")
        if (s < 120) return qsTr("About a minute ago")
        if (s < 3600) return qsTr("%1 minutes ago").arg(Math.floor(s / 60))
        if (s < 7200) return qsTr("About an hour ago")
        if (s < 86400) return qsTr("%1 hours ago").arg(Math.floor(s / 3600))
        return t.toLocaleDateString(Qt.locale(), "MMMM d")
    }

    contentItem: Item {
        // Places
        Text {
            x: 24; y: 20; height: 26.67
            text: qsTr("Add to playlist")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.pick("#242424", "#FFFFFF")
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Column {
            x: 12; y: 74.67; width: 204
            Repeater {
                model: [["mine", qsTr("My lists"), "folder-16"], ["recent", qsTr("Recent lists"), "history-16"], ["favorites", qsTr("Favorites"), "star-16"]]
                Rectangle {
                    id: navRow
                    required property var modelData
                    readonly property bool on: pk.place === modelData[0] && !pk.site
                    width: 204; height: 40; radius: 4
                    color: on ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : nrh.hovered ? theme.pick("#F0F0F0", "#2E2E2E", "#1AEBFF") : "transparent"
                    Rectangle { visible: navRow.on; x: 0; y: 10; width: 3; height: 20; radius: 1.5; color: theme.brand }
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: navRow.modelData[2]; color: theme.onFill(navRow, pk.ink) }
                    Text {
                        x: 38; anchors.verticalCenter: parent.verticalCenter
                        text: navRow.modelData[1]
                        font.family: theme.font; font.pixelSize: 14; font.weight: navRow.on ? Font.DemiBold : Font.Normal; color: theme.onFill(navRow, pk.ink)
                    }
                    HoverHandler { id: nrh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.load(navRow.modelData[0]) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData[1]
                    Accessible.checked: on
                }
            }
            Item { width: 1; height: 32 }
            Text {
                x: 8; height: 36; verticalAlignment: Text.AlignVCenter
                text: qsTr("Quick access")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pk.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Repeater {
                model: (pk.actions ? pk.actions.quickAccess || [] : []).slice(0, 3)
                Rectangle {
                    id: siteRow
                    required property var modelData
                    readonly property bool on: !!pk.site && pk.site.list_id === modelData.list_id
                    width: 204; height: 40; radius: 4
                    color: on ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : srh.hovered ? theme.pick("#F0F0F0", "#2E2E2E", "#1AEBFF") : "transparent"
                    SiteTile { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 24; radius: 2; acronym: siteRow.modelData.acronym || ""; tint: siteRow.modelData.color || "" }
                    Text {
                        x: 44; width: 160; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: siteRow.modelData.site_title || siteRow.modelData.title || ""
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(siteRow, pk.ink)
                    }
                    HoverHandler { id: srh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { pk.place = "site"; pk.lists = []; pk.picked = null; pk.site = siteRow.modelData } }
                    Accessible.role: Accessible.Button
                    Accessible.name: siteRow.modelData.site_title || ""
                }
            }
            Text {
                x: 0; height: 44; verticalAlignment: Text.AlignVCenter
                text: qsTr("More places...")
                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#3D3E66", "#ADADAD", "#1AEBFF")
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { pk.place = "more"; pk.lists = []; pk.picked = null; pk.site = null } }
                Accessible.role: Accessible.Link
                Accessible.name: text
            }
        }
        // The place
        Text {
            x: 251.67; y: 24; height: 24; verticalAlignment: Text.AlignVCenter
            text: pk.site ? (pk.site.site_title || pk.site.title || "") : ({ mine: qsTr("My lists"), recent: qsTr("Recent lists"), favorites: qsTr("Favorites"), more: qsTr("More places...") })[pk.place] || ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: pk.ink
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        // Search: 240 x 32, round, "Search".
        Rectangle {
            x: parent.width - (pk.place === "favorites" ? 24 : 92) - 240 + 24; y: 20; width: 240 - 24; height: 32; radius: 16
            color: theme.surface
            border.width: search.activeFocus ? 2 : 1; border.color: search.activeFocus ? theme.brand : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "search-16"; color: theme.brand }
            TextInput {
                id: search
                x: 36; width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter; clip: true
                font.family: theme.font; font.pixelSize: 14; color: pk.ink
                onTextChanged: pk.query = text
                Text { visible: !search.text; text: qsTr("Search"); font: search.font; color: theme.textTertiary }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search")
            }
        }
        // The list
        Rectangle {
            id: card
            visible: pk.place !== "favorites"
            x: 245.33; y: 74.67; width: parent.width - 245.33 - 30.67; height: head.height + Math.max(1, list.contentHeight)
            radius: 12; color: theme.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Math.min(12, parent.height); color: theme.surface; visible: list.count > 0 }
            Item {
                id: head
                width: parent.width; height: 49.67
                FluentIcon { x: 64; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "document-16"; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                Text { x: 104; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pk.ink }
                Text { x: 374; anchors.verticalCenter: parent.verticalCenter; text: pk.place === "recent" ? qsTr("Accessed") : qsTr("Modified"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pk.ink }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.pick("#F0F0F0", "#3D3D3D") }
            }
            ListView {
                id: list
                y: head.height; width: parent.width; height: Math.min(contentHeight, pk.height - 74.67 - head.height - 80)
                clip: true; interactive: contentHeight > height
                model: pk.shown
                delegate: Rectangle {
                    id: lrow
                    required property var modelData
                    readonly property bool sel: !!pk.picked && pk.picked.url === modelData.url
                    width: list.width; height: 59
                    color: sel ? theme.pick("#E9EAF6", "#2B2C3F", "#000000") : lrh.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    Rectangle {
                        id: lcheck
                        visible: lrh.hovered || lrow.sel
                        x: 23; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9
                        color: lrow.sel ? theme.brand : theme.surface
                        border.width: lrow.sel ? 0 : 1; border.color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                        FluentIcon { visible: lrow.sel; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: theme.onFill(lcheck, "white") }
                    }
                    FluentIcon { x: 58; anchors.verticalCenter: parent.verticalCenter; size: 32; name: "ft-video-32" }
                    Text {
                        x: 104; width: 260; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: lrow.modelData.title
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(lrow, pk.ink)
                    }
                    Text {
                        x: 374; width: 150; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: pk.relTime(lrow.modelData.when)
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(lrow, theme.pick("#424242", "#D6D6D6", "#FFFFFF"))
                    }
                    HoverHandler { id: lrh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.picked = lrow.sel ? null : lrow.modelData; onDoubleTapped: { pk.picked = lrow.modelData; pk.done() } }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.title
                    Accessible.selected: sel
                }
            }
        }
        // Empty states, OneDrive's words.
        Text {
            visible: !pk.loading && (pk.place === "favorites" || pk.place === "site" || pk.place === "more" || !!pk.error || pk.shown.length === 0)
            anchors.horizontalCenter: card.horizontalCenter
            y: pk.place === "favorites" ? 120 : 300
            text: pk.error ? pk.error : pk.place === "favorites" ? qsTr("Items you favorite will show up here")
                : pk.place === "site" ? qsTr("There are no playlists in this site") : qsTr("This folder is empty")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: pk.error ? theme.danger : theme.pick("#242424", "#FFFFFF")
        }
        BusyIndicator { anchors.centerIn: card; running: pk.loading; visible: pk.loading }
        // The tray
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.bottom: parent.bottom; anchors.bottomMargin: 24
            spacing: 8
            TrayButton { label: qsTr("New playlist"); onClicked: newList.openNew() }
            TrayButton { label: qsTr("Done"); primary: true; on: !!pk.picked; onClicked: pk.done() }
            TrayButton { label: qsTr("Cancel"); onClicked: pk.close() }
        }
    }
    component TrayButton: Rectangle {
        id: tb
        property string label
        property bool primary: false
        property bool on: true
        signal clicked()
        width: Math.max(80, tbt.implicitWidth + 24); height: 32; radius: 4
        color: !on ? theme.surface : primary ? (tbh.hovered ? theme.brandHover : theme.brandFill) : tbh.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : theme.surface
        border.width: primary && on ? 0 : 1
        border.color: !on ? theme.pick("#E0E0E0", "#3D3D3D", "#3FF23F") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Text {
            id: tbt; anchors.centerIn: parent; text: tb.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(tb, !tb.on ? theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") : tb.primary ? "white" : pk.ink)
        }
        HoverHandler { id: tbh; cursorShape: tb.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tb.on; onTapped: tb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // New playlist: Microsoft Lists' form for the playlist template ("Name *"
    // with "Playlist", "Description", "Save to *" My lists; Create in the
    // Lists purple #892FFF, Cancel).
    Popup {
        id: newList
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 24
        width: 582.67
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        function openNew() { nameBox.text = qsTr("Playlist"); descBox.text = ""; open(); nameBox.selectAll(); nameBox.forceActiveFocus() }
        contentItem: Column {
            spacing: 0
            Item {
                width: parent.width; height: 24
                Row {
                    spacing: 2
                    Text { text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#242424", "#FFFFFF") }
                    Text { text: "*"; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#C4314B", "#F1707B", "#FFFFFF") }
                }
                Rectangle {
                    id: nlClose
                    anchors.right: parent.right; y: -8; width: 32; height: 32; radius: 4
                    border.width: 1; border.color: theme.pick("#616161", "#ADADAD", "#FFFFFF")
                    color: nlch.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 16; name: "dismiss-16"; color: theme.onFill(nlClose, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                    HoverHandler { id: nlch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: newList.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close")
                }
            }
            Item {
                width: parent.width - 20; height: 40
                TextInput {
                    id: nameBox
                    width: parent.width; anchors.verticalCenter: parent.verticalCenter; clip: true
                    font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.pick("#242424", "#FFFFFF")
                    selectByMouse: true
                    Keys.onReturnPressed: if (text.trim()) pk.create(text.trim(), descBox.text.trim())
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Name")
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: nameBox.activeFocus ? 2 : 1; color: nameBox.activeFocus ? theme.hc("#892FFF", "#1AEBFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF") }
            }
            Item { width: 1; height: 24 }
            Text { text: qsTr("Description"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#242424", "#FFFFFF") }
            Item {
                width: parent.width - 20; height: 32
                TextInput {
                    id: descBox
                    width: parent.width; anchors.verticalCenter: parent.verticalCenter; clip: true
                    font.family: theme.font; font.pixelSize: 14; color: theme.pick("#242424", "#FFFFFF")
                    selectByMouse: true
                    Text { visible: !descBox.text; text: qsTr("What is your list about?"); font: descBox.font; color: theme.textTertiary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Description")
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: descBox.activeFocus ? 2 : 1; color: descBox.activeFocus ? theme.hc("#892FFF", "#1AEBFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF") }
            }
            Item { width: 1; height: 24 }
            Row {
                spacing: 2
                Text { text: qsTr("Save to"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#242424", "#FFFFFF") }
                Text { text: "*"; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#C4314B", "#F1707B", "#FFFFFF") }
            }
            Item { width: 1; height: 8 }
            Rectangle {
                width: parent.width - 20; height: 38; radius: 4
                color: theme.surface; border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "home-20"; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: qsTr("My lists"); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#242424", "#FFFFFF") }
                FluentIcon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "chevron-down-12"; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Save to") + " " + qsTr("My lists")
            }
            Item { width: 1; height: 28 }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 20
                spacing: 8
                Rectangle {
                    id: nlCreate
                    readonly property bool on: nameBox.text.trim().length > 0
                    width: 62; height: 32; radius: 4
                    color: !on ? theme.pick("#F0F0F0", "#3D3D3D", "#000000") : nlcr.hovered ? theme.hc("#7A1FEF", "#1AEBFF") : theme.hc("#892FFF", "#1AEBFF")
                    Text { anchors.centerIn: parent; text: qsTr("Create"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(nlCreate, nlCreate.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C")) }
                    HoverHandler { id: nlcr; cursorShape: nlCreate.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: nlCreate.on; onTapped: { newList.close(); pk.create(nameBox.text.trim(), descBox.text.trim()) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Create")
                }
                Rectangle {
                    id: nlCancel
                    width: 62; height: 32; radius: 4
                    color: nlca.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : theme.surface
                    border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(nlCancel, theme.pick("#242424", "#FFFFFF")) }
                    HoverHandler { id: nlca; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: newList.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel")
                }
            }
        }
    }
    function stateForTest() { return { open: opened, place: place, loading: loading, error: error, lists: shown.map(l => l.title), picked: picked ? picked.title : "", newOpen: newList.opened } }
    function pickForTest(title) { picked = lists.find(l => l.title === title) || null; return !!picked }
    function newForTest(name) { newList.openNew(); nameBox.text = name }
}
