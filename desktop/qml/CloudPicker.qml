import QtQuick
import QtQuick.Controls.Basic

// Teams' Attach cloud files: OneDrive's file picker (FilePicker.aspx,
// "files" mode, several at once, Attach and Cancel), measured on winpc
// 2026-11-13.
// - A dialog 76% x 82% of the window (radius 8, Teams' 64 px shadow) over
//   rgba(37, 36, 36, .75); #F5F5F5 with the content white from x 82.
// - The rail (68 wide): Navigation Pane, Home, My files, Shared, Favorites,
//   Browse by (People, Meetings, Media), a line, Quick access (the sites'
//   tiles), More places…: 36 px items at x 16 (a 20 px glyph at 8, 8;
//   #424242, the open one #115EA3 on #EBEBEB with a 4 x 16 bar at x 4).
//   Navigation Pane widens it to 210 over the content: "OneDrive" (20/600)
//   and the labels (14, at 52).
// - The title (18/600 at 105, 30), or a folder's trail (18 px, the last
//   600), 18 above the list.
// - Home (OneDrive's recent files): a card (radius 12, 0.67 #F0F0F0) at
//   98, 78 with Name, Opened, Owner, Activity (12/600 #424242) and 56 px
//   rows: the type icon (32), the name (14) over its location (12 #616161),
//   then 14 px #616161 cells.
// - Folders: a #F5F5F5 header (43.7, 0.67 #E0E0E0 under it) with Name,
//   Modified, Modified By, Activity (14/600 #616161) and 59 px rows (0.67
//   #F5F5F5 between): the name (14 #616161) over "{n} items" or the size
//   (12 #8A8A8A), the cells 14 #8A8A8A. A folder opens; a file selects
//   (#CFE4FA, its circle filled).
// - Shared, Favorites, Meetings: OneDrive's empty states (20/600 over a
//   256 px picture). People: each person with chips of their files.
//   Media: 265.8 x 149.5 pictures under their dates.
// - The footer (80): "{n} selected ✕" (radius 18, 0.67 #605E5C) at 24, 24;
//   Attach (80 x 32, brand, radius 2; #F5F5F5 / #BDBDBD while nothing is
//   picked) and Cancel.
// Not built yet: the command bar (New folder, Upload, the view switch),
// Media's layout and zoom controls, and a person's own page.
Popup {
    id: dlg
    parent: Overlay.overlay
    modal: true
    width: Math.round(Overlay.overlay.width * 0.76 * 10) / 10
    height: Math.round(Overlay.overlay.height * 0.82 * 10) / 10
    x: (Overlay.overlay.width - width) / 2
    y: (Overlay.overlay.height - height) / 2
    padding: 0
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.75) }
    background: FluentSurface { depth: 64; radius: 8; color: theme.pick("#F5F5F5", "#1F1F1F") }

    /// The files picked ({name, kind, web_url, drive_id, id}), sent on Attach.
    signal attached(var files)
    /// Where it opens: "home", "myfiles", or a channel's folder
    /// ({team, team_id, channel_id}) for Browse Teams and Channels.
    property var entry: "home"
    readonly property string tag: "cloudpicker:"
    property int seq: 0
    property string place: "home"
    /// The folders opened ({name, drive_id, item_id}); the first is the
    /// library's (My files or a site's).
    property var trail: []
    property var rows: []
    property var people: []
    property bool loading: false
    property var selected: []
    property bool navOpen: false
    property var quickAccess: []
    readonly property var placeTitles: ({ home: "Home", shared: "Shared with you", favorites: "Favorites", people: "People", meetings: "Meetings", media: "Media", more: "Shared libraries" })
    readonly property var emptyStates: ({ shared: ["Shared files will show up here", "empty-shared-v3.png"],
                                          favorites: ["Items you favorite will show up here", "empty-favorites-v3.png"],
                                          meetings: ["Files shared in meetings will show up here", "empty-meeting-v3.png"] })
    readonly property color ink: theme.pick("#616161", "#D6D6D6")
    readonly property color faint: theme.pick("#8A8A8A", "#ADADAD")
    readonly property color label: theme.pick("#424242", "#D6D6D6")
    readonly property color railBlue: theme.pick("#115EA3", "#479EF5")

    property var thumbs: ({})
    property var thumbAsked: ({})
    function wantThumb(it) {
        if (!it.id || thumbAsked[it.id]) return
        thumbAsked[it.id] = true
        backend.driveAction(tag + "thumb", JSON.stringify(it), JSON.stringify({ size: "c400x400" }))
    }
    function ask(op, args, item) { seq++; loading = true; backend.driveAction(tag + seq + ":" + op, JSON.stringify(item || {}), JSON.stringify(args || {})) }
    function openPlace(key) {
        navOpen = false; place = key; trail = []; rows = []; people = []
        if (key === "home") ask("attach_recent")
        else if (key === "myfiles") { trail = [{ name: "My files", drive_id: "", item_id: "" }]; ask("folders", { drive_id: "", item_id: "" }) }
        else if (key === "more") ask("libraries")
        else ask("attach_place", { place: key })
    }
    function openLibrary(lib) {
        navOpen = false; place = "lib:" + lib.drive_id; rows = []
        trail = [{ name: lib.label || lib.name, drive_id: lib.drive_id, item_id: "", tile: lib }]
        ask("folders", { drive_id: lib.drive_id, item_id: "" })
    }
    function openFolder(it) {
        const t = trail.length ? trail : [{ name: placeTitles[place] || "My files", drive_id: it.drive_id, item_id: "" }]
        trail = t.concat([{ name: it.name, drive_id: it.drive_id, item_id: it.id }])
        rows = []
        ask("folders", { drive_id: it.drive_id, item_id: it.id })
    }
    function back(i) {
        trail = trail.slice(0, i + 1)
        const t = trail[i]
        rows = []
        ask("folders", { drive_id: t.drive_id, item_id: t.item_id })
    }
    function isSelected(it) { return selected.some(s => s.web_url === it.web_url) }
    function toggle(it) {
        if (it.is_folder) { openFolder(it); return }
        selected = isSelected(it) ? selected.filter(s => s.web_url !== it.web_url)
                                  : selected.concat([{ name: it.name, kind: it.kind || "", web_url: it.web_url, drive_id: it.drive_id || "", id: it.id || "" }])
    }
    /// The header's circle: every file shown picked, or none.
    function allPicked() { const f = rows.filter(r => !r.is_folder); return f.length > 0 && f.every(r => isSelected(r)) }
    function pickAll() {
        const f = rows.filter(r => !r.is_folder)
        if (allPicked()) selected = selected.filter(s => !f.some(r => r.web_url === s.web_url))
        else f.forEach(r => { if (!isSelected(r)) toggle(r) })
    }
    function attach() {
        if (!selected.length) return
        const files = selected
        close()
        attached(files)
    }
    onOpened: {
        selected = []; navOpen = false
        backend.driveAction(tag + "quick_access", "{}", "{}")
        if (entry && entry.channel_id) {
            place = "channel"; rows = []; trail = []
            ask("attach_place", { place: "channel", team_id: entry.team_id, channel_id: entry.channel_id })
        } else openPlace(entry === "myfiles" ? "myfiles" : "home")
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(dlg.tag)) return
            const v = result ? JSON.parse(result) : null
            if (op === dlg.tag + "quick_access") { if (!error) dlg.quickAccess = v || []; return }
            if (op === dlg.tag + "thumb") { if (v && v.path) { const t = Object.assign({}, dlg.thumbs); t[v.id] = v.path; dlg.thumbs = t }; return }
            if (op.indexOf(dlg.tag + dlg.seq + ":") !== 0) return
            dlg.loading = false
            const kind = op.split(":").pop()
            if (error) { dlg.rows = []; return }
            if (kind === "attach_place" && v && v.folder) {
                // A channel's folder: the team's library › Documents › the channel.
                const f = v.folder
                dlg.trail = [{ name: dlg.entry.team || "", drive_id: f.drive_id, item_id: "", site: true },
                             { name: "Documents", drive_id: f.drive_id, item_id: "" },
                             { name: f.name, drive_id: f.drive_id, item_id: f.id, shared: true }]
                dlg.ask("folders", { drive_id: f.drive_id, item_id: f.id })
                return
            }
            if (kind === "libraries") { dlg.rows = (v || []).map(l => ({ name: l.name, library: l, is_folder: true })); return }
            dlg.people = v && v.people ? v.people : []
            dlg.rows = v && v.items ? v.items : []
        }
    }

    // The content, white from x 82.
    Rectangle {
        id: content
        x: 82; width: dlg.width - 82; height: dlg.height
        color: theme.surface
        topRightRadius: 8; bottomRightRadius: 8

        // The title, or the folder's trail.
        Row {
            id: crumbs
            x: 15; y: 23.7; height: 36.7
            spacing: 0
            Repeater {
                model: dlg.trail.length ? dlg.trail : [{ name: dlg.placeTitles[dlg.place] || "" }]
                Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    readonly property bool last: index === (dlg.trail.length ? dlg.trail.length - 1 : 0)
                    height: 36.7; spacing: 0
                    FluentIcon { visible: crumb.index > 0; anchors.verticalCenter: parent.verticalCenter; width: 12; name: "chevron-right-12"; size: 12; color: dlg.label }
                    Item {
                        width: crumbText.x + crumbText.implicitWidth + 8; height: 36.7
                        SiteTile {
                            id: crumbTile
                            visible: !!crumb.modelData.site || !!crumb.modelData.tile
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            acronym: crumb.modelData.tile ? crumb.modelData.tile.acronym : dlg.acronymOf(crumb.modelData.name)
                            tint: crumb.modelData.tile ? crumb.modelData.tile.color : ""
                        }
                        Text {
                            id: crumbText
                            x: crumbTile.visible ? 34 : 8; anchors.verticalCenter: parent.verticalCenter
                            text: crumb.modelData.name
                            font.family: theme.font; font.pixelSize: 18; font.weight: crumb.last ? Font.DemiBold : Font.Normal; color: theme.text
                        }
                        HoverHandler { enabled: !crumb.last; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !crumb.last && dlg.trail.length > 0; onTapped: dlg.back(crumb.index) }
                        Accessible.role: crumb.last ? Accessible.Heading : Accessible.Link
                        Accessible.name: crumb.modelData.name
                    }
                    FluentIcon { visible: crumb.last && !!crumb.modelData.shared; anchors.verticalCenter: parent.verticalCenter; name: "people-16"; size: 16; color: dlg.label }
                }
            }
        }

        // Home: OneDrive's recent files.
        Rectangle {
            id: homeCard
            visible: dlg.place === "home" && dlg.rows.length > 0
            x: 16; y: 78; width: content.width - 40; height: dlg.height - 80 - y
            radius: 12; color: theme.surface
            border.color: theme.pick("#F0F0F0", "#333333"); border.width: 0.67
            clip: true
            readonly property var cols: [["Name", 45.7], ["Opened", 370.2], ["Owner", 524.7], ["Activity", 699.2]]
            Repeater {
                model: homeCard.cols
                Text {
                    required property var modelData
                    x: modelData[1] + 8.6; y: 16.3
                    text: modelData[0]
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: dlg.label
                }
            }
            // Select all rows: on hover, as Teams shows it.
            Item {
                x: 0; y: 0; width: parent.width; height: 48
                HoverHandler { id: homeHead }
                PickCircle { x: 21.7; y: 15; shown: homeHead.hovered; on: dlg.allPicked(); TapHandler { onTapped: dlg.pickAll() } }
            }
            ListView {
                x: 0.7; y: 48.7; width: parent.width - 1.4; height: parent.height - y - 1
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: dlg.place === "home" ? dlg.rows : []
                delegate: Rectangle {
                    id: hr
                    required property var modelData
                    readonly property bool sel: dlg.isSelected(modelData)
                    width: ListView.view.width; height: 56
                    color: sel ? theme.pick("#CFE4FA", "#0C3B5E") : hrHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    PickCircle { x: 21; y: 19; on: hr.sel; shown: hrHover.hovered || hr.sel }
                    FluentIcon { x: 53; y: 11.6; size: 32; name: dlg.typeIcon(hr.modelData.kind) }
                    Text {
                        x: 101; y: 9.8; width: 280; elide: Text.ElideRight
                        text: hr.modelData.name.replace(/\.(loop|fluid)$/i, "")
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Text {
                        x: 101; y: 29.5; width: 280; elide: Text.ElideRight
                        text: hr.modelData.location || ""
                        font.family: theme.font; font.pixelSize: 12; color: dlg.ink
                    }
                    Text { x: 378.1; anchors.verticalCenter: parent.verticalCenter; width: 140; elide: Text.ElideRight; text: hr.modelData.opened || ""; font.family: theme.font; font.pixelSize: 14; color: dlg.ink }
                    Text { x: 532; anchors.verticalCenter: parent.verticalCenter; width: 160; elide: Text.ElideRight; text: hr.modelData.owner || ""; font.family: theme.font; font.pixelSize: 14; color: dlg.ink }
                    FluentIcon { visible: !!hr.modelData.activity; x: 710.5; y: 8; size: 16; name: "edit-16"; color: theme.pick("#0F6CBD", "#479EF5") }
                    Text {
                        visible: !!hr.modelData.activity
                        x: 736.5; y: 8; width: 95.5
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: dlg.activityText(hr.modelData)
                        font.family: theme.font; font.pixelSize: 14; color: dlg.ink
                    }
                    HoverHandler { id: hrHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.toggle(hr.modelData) }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData.name
                    Accessible.checked: sel
                }
            }
        }

        // Folders (My files, a site's library, a channel's folder) and the
        // other places' files.
        Rectangle {
            id: table
            visible: dlg.place !== "home" && dlg.place !== "people" && dlg.place !== "media" && dlg.rows.length > 0
            x: 16; y: 80; width: content.width - 40; height: dlg.height - 80 - y
            radius: 12; color: theme.surface
            border.color: theme.pick("#F0F0F0", "#333333"); border.width: 0.67
            clip: true
            Rectangle {
                x: 0.7; y: 0.7; width: parent.width - 1.4; height: 43.7
                topLeftRadius: 12; topRightRadius: 12
                color: theme.pick("#F5F5F5", "#292929")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
                HoverHandler { id: tableHead }
                PickCircle { x: 23; anchors.verticalCenter: parent.verticalCenter; shown: tableHead.hovered; on: dlg.allPicked(); TapHandler { onTapped: dlg.pickAll() } }
                FluentIcon { x: 64; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "document-16"; color: dlg.faint }
                Repeater {
                    model: [["Name", 104], ["Modified", 374], ["Modified By", 544], ["Activity", 694]]
                    Text {
                        required property var modelData
                        x: modelData[1]; anchors.verticalCenter: parent.verticalCenter
                        text: modelData[0]
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: dlg.ink
                    }
                }
            }
            ListView {
                x: 0.7; y: 44.4; width: parent.width - 1.4; height: parent.height - y - 1
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: table.visible ? dlg.rows : []
                delegate: Rectangle {
                    id: fr
                    required property var modelData
                    readonly property bool sel: dlg.isSelected(modelData)
                    readonly property color cell: sel ? dlg.ink : dlg.faint
                    width: ListView.view.width; height: 59
                    color: sel ? theme.pick("#CFE4FA", "#0C3B5E") : frHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: fr.sel ? "transparent" : theme.pick("#F5F5F5", "#2E2E2E") }
                    PickCircle { visible: !fr.modelData.is_folder; x: 23; y: 20.5; on: fr.sel; shown: frHover.hovered || fr.sel }
                    SiteTile { visible: !!fr.modelData.library; x: 58; y: 13.5; size: 32; acronym: fr.modelData.library ? dlg.acronymOf(fr.modelData.library.site || fr.modelData.name) : "" }
                    FluentIcon {
                        visible: !fr.modelData.library
                        x: 58; y: 13.5; size: 32
                        name: fr.modelData.is_folder ? (fr.modelData.special === "shortcuts" ? "ft-companyfolder-32" : "ft-folder-32") : dlg.typeIcon(fr.modelData.kind)
                    }
                    Text {
                        x: 104; y: fr.meta ? 11.5 : 19.2; width: 260; elide: Text.ElideRight
                        text: fr.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: dlg.ink
                    }
                    readonly property string meta: modelData.library ? "" : modelData.is_folder ? dlg.itemCount(modelData.child_count) : dlg.sizeText(modelData.size)
                    Row {
                        visible: !!fr.meta
                        x: 104; y: 30.9; spacing: 0
                        Text { text: fr.meta; font.family: theme.font; font.pixelSize: 12; color: fr.cell }
                        Text { visible: fr.modelData.sharing === "Shared"; text: " • "; font.family: theme.font; font.pixelSize: 12; color: fr.cell }
                        FluentIcon { visible: fr.modelData.sharing === "Shared"; y: 3.6; size: 12; name: "people-12"; color: fr.cell }
                    }
                    Text { x: 374; anchors.verticalCenter: parent.verticalCenter; width: 150; elide: Text.ElideRight; text: fr.modelData.modified_text || ""; font.family: theme.font; font.pixelSize: 14; color: fr.cell }
                    Text { x: 544; anchors.verticalCenter: parent.verticalCenter; width: 130; elide: Text.ElideRight; text: fr.modelData.modified_by || ""; font.family: theme.font; font.pixelSize: 14; color: fr.cell }
                    FluentIcon {
                        visible: !!fr.modelData.activity
                        x: 694; anchors.verticalCenter: parent.verticalCenter; size: 14
                        name: fr.modelData.activity ? dlg.activityIcon(fr.modelData.activity.kind) : ""
                        color: theme.pick("#0078D4", "#479EF5")
                    }
                    Text {
                        visible: !!fr.modelData.activity
                        x: 712; anchors.verticalCenter: parent.verticalCenter; width: fr.width - x - 12
                        elide: Text.ElideRight
                        text: fr.modelData.activity ? fr.modelData.activity.text + " " + fr.modelData.activity.time : ""
                        font.family: theme.font; font.pixelSize: 14; color: fr.cell
                    }
                    HoverHandler { id: frHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: fr.modelData.library ? dlg.openLibrary(fr.modelData.library) : dlg.toggle(fr.modelData) }
                    Accessible.role: fr.modelData.is_folder ? Accessible.Button : Accessible.CheckBox
                    Accessible.name: modelData.name
                    Accessible.checked: sel
                }
            }
        }

        // People: each person and their files.
        Column {
            visible: dlg.place === "people"
            x: 19; y: 110; width: content.width - 40
            Repeater {
                model: dlg.place === "people" ? dlg.people : []
                Item {
                    id: pr
                    required property var modelData
                    width: parent.width; height: 65
                    Avatar { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 32; name: pr.modelData.name }
                    Text {
                        x: 76; anchors.verticalCenter: parent.verticalCenter; width: 170; elide: Text.ElideRight
                        text: pr.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Row {
                        x: 268; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: (pr.modelData.items || []).slice(0, 3)
                            Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool sel: dlg.isSelected(modelData)
                                width: 198; height: 41.3; radius: 6
                                color: sel ? theme.pick("#CFE4FA", "#0C3B5E") : theme.surface
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 6 }
                                FluentIcon { x: 12.7; anchors.verticalCenter: parent.verticalCenter; size: 16; name: dlg.typeIcon(chip.modelData.kind).replace("-32", "-20") }
                                Text {
                                    x: 32.7; anchors.verticalCenter: parent.verticalCenter; width: 82; elide: Text.ElideRight
                                    text: chip.modelData.name.replace(/\.[^.]+$/, "")
                                    font.family: theme.font; font.pixelSize: 12; color: theme.text
                                }
                                Rectangle {
                                    x: 118.4; anchors.verticalCenter: parent.verticalCenter; width: 71; height: 24; radius: 20
                                    color: theme.pick("#F5F5F5", "#2E2E2E")
                                    Text {
                                        anchors.centerIn: parent
                                        text: chip.modelData.modified_text || ""
                                        font.family: theme.font; font.pixelSize: 10; color: dlg.label
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: dlg.toggle(chip.modelData) }
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: modelData.name
                                Accessible.checked: sel
                            }
                        }
                    }
                }
            }
        }

        // Media: the pictures and videos.
        GridView {
            visible: dlg.place === "media" && dlg.rows.length > 0
            x: 22; y: 142; width: 3 * 267.8; height: dlg.height - 80 - y
            clip: true; boundsBehavior: Flickable.StopAtBounds
            cellWidth: 267.8; cellHeight: 195.5
            model: dlg.place === "media" ? dlg.rows : []
            delegate: Item {
                id: mt
                required property var modelData
                readonly property bool sel: dlg.isSelected(modelData)
                width: 265.8; height: 195.5
                Rectangle {
                    width: 265.8; height: 149.5; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.2)
                    border.color: mt.sel ? theme.brand : "transparent"; border.width: 2
                    Image { anchors.fill: parent; anchors.margins: 2; fillMode: Image.PreserveAspectCrop; source: dlg.thumbs[mt.modelData.id] || "" }
                    // Videos: a play mark (28, rgba(0,0,0,.5), radius 4) at 12, 12.
                    Rectangle {
                        visible: ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(String(mt.modelData.kind || "").toLowerCase()) >= 0
                        x: 12; y: 12; width: 28; height: 28; radius: 4; color: Qt.rgba(0, 0, 0, 0.5)
                        FluentIcon { anchors.centerIn: parent; size: 20; name: "play-20"; color: "white" }
                    }
                }
                Text {
                    x: 12; y: 162.2; width: 241.8; elide: Text.ElideRight
                    text: mt.modelData.name
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Component.onCompleted: dlg.wantThumb(modelData)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.toggle(mt.modelData) }
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData.name
                Accessible.checked: sel
            }
        }

        // Empty places and folders.
        Item {
            visible: !dlg.loading && dlg.rows.length === 0 && dlg.people.length === 0
            x: 0; y: folder ? 207.7 : 119.7; width: content.width - 8; height: 316
            // A folder's (the library view's): 20/600 at 207.7 over
            // empty_files_v3 (256).
            readonly property var es: dlg.trail.length ? ["This folder is empty", "empty-files-v3.png"] : dlg.emptyStates[dlg.place] || ["", ""]
            readonly property bool folder: dlg.trail.length > 0
            Text {
                id: esTitle
                width: parent.width; height: parent.folder ? 26.7 : 60
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: parent.es[0]
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            }
            Image {
                visible: !!parent.es[1]
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.folder ? 26.6 : 60
                width: 256; height: 256; sourceSize: Qt.size(512, 512)
                source: parent.es[1] ? "../assets/illustrations/" + parent.es[1] : ""
            }
        }
        BusyIndicator { anchors.centerIn: parent; running: dlg.loading; visible: dlg.loading }

        // The footer.
        Rectangle {
            y: dlg.height - 80; width: content.width; height: 80
            color: theme.surface
            bottomRightRadius: 8
            Rectangle {
                visible: dlg.selected.length > 0
                x: 24; y: 24; height: 32; width: selText.implicitWidth + 47.8; radius: 18
                color: clearHover.hovered ? theme.menuHover : "transparent"
                border.color: theme.pick("#605E5C", "#A19F9D"); border.width: 0.67
                Text {
                    id: selText
                    x: 12.7; anchors.verticalCenter: parent.verticalCenter
                    text: dlg.selected.length + " selected"
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                FluentIcon { x: selText.x + selText.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "dismiss-12"; color: theme.text }
                HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.selected = [] }
                Accessible.role: Accessible.Button
                Accessible.name: "Clear selected items"
            }
            Rectangle {
                x: parent.width - 192; y: 24; width: 80; height: 32; radius: 2
                readonly property bool on: dlg.selected.length > 0
                color: on ? (attachHover.hovered ? theme.brandHover : theme.brand) : theme.pick("#F5F5F5", "#2E2E2E")
                Text {
                    anchors.centerIn: parent; text: "Attach"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: parent.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C")
                }
                HoverHandler { id: attachHover; enabled: parent.on; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: parent.on; onTapped: dlg.attach() }
                Accessible.role: Accessible.Button
                Accessible.name: "Attach"
            }
            Rectangle {
                x: parent.width - 104; y: 24; width: 80; height: 32; radius: 2
                color: cancelHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
            }
        }
    }

    // Closing the wide pane: a click on the content.
    MouseArea { visible: dlg.navOpen; x: 210; width: dlg.width - 210; height: dlg.height; onClicked: dlg.navOpen = false }

    // The rail, or the Navigation Pane over the content.
    Rectangle {
        id: rail
        width: dlg.navOpen ? 210 : 68; height: dlg.height
        color: theme.pick("#F5F5F5", "#1F1F1F")
        topLeftRadius: 8; bottomLeftRadius: 8
        FluentSurface { visible: dlg.navOpen; z: -1; anchors.fill: parent; depth: 16; radius: 8 }
        Text {
            visible: dlg.navOpen
            x: 24; y: 14; height: 37.3; verticalAlignment: Text.AlignVCenter
            text: "OneDrive"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        }
        RailItem { y: 18; icon: dlg.navOpen ? "panel-left-contract-20" : "panel-left-expand-20"; tip: "Navigation Pane"; iconX: dlg.navOpen ? 162 : 8; onClicked: dlg.navOpen = !dlg.navOpen }
        RailItem { y: 51.3; key: "home"; icon: "home-20"; text: "Home" }
        RailItem { y: 87.3; key: "myfiles"; icon: "folder-20"; text: "My files" }
        RailItem { y: 123.3; key: "shared"; icon: "people-20"; text: "Shared" }
        RailItem { y: 159.3; key: "favorites"; icon: "star-20"; text: "Favorites" }
        Item {
            x: 16; y: 203.3; width: dlg.navOpen ? 190 : 36; height: 36
            Text {
                visible: dlg.navOpen
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: "Browse by"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            }
            FluentIcon { visible: !dlg.navOpen; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "chevron-down-16"; color: dlg.ink }
            Accessible.role: Accessible.Heading
            Accessible.name: "Browse by"
        }
        RailItem { y: 239.3; key: "people"; icon: "person-20"; text: "People" }
        RailItem { y: 275.3; key: "meetings"; icon: "calendar-ltr-20"; text: "Meetings" }
        RailItem { y: 311.3; key: "media"; icon: "image-20"; text: "Media" }
        Rectangle { visible: !dlg.navOpen; x: 22; y: 366.8; width: 24; height: 1; radius: 1; color: theme.pick("#D1D1D1", "#3D3D3D") }
        Row {
            visible: dlg.navOpen
            x: 24; y: 364; spacing: 6
            Text { text: "Quick access"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            FluentIcon { y: 1.3; size: 16; name: "info-16"; color: dlg.ink }
        }
        Column {
            y: 391.3
            Repeater {
                model: dlg.quickAccess.slice(0, 3)
                RailItem {
                    required property var modelData
                    key: "lib:" + modelData.drive_id
                    text: modelData.label
                    tile: modelData
                    onClicked: dlg.openLibrary(modelData)
                }
            }
        }
        Item {
            x: 16; y: 499.3; width: dlg.navOpen ? 190 : 36; height: 36
            FluentIcon { visible: !dlg.navOpen; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "more-horizontal-16"; color: dlg.railBlue }
            Text {
                visible: dlg.navOpen
                y: 10; text: "More places..."
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: dlg.railBlue
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.openPlace("more") }
            Accessible.role: Accessible.Link
            Accessible.name: "More places..."
        }
    }

    component RailItem: Item {
        id: ri
        property string key: ""
        property string icon: ""
        property string text: ""
        property string tip: ""
        property var tile: null
        property real iconX: 8
        signal clicked()
        readonly property bool open: !!key && (dlg.place === key || (key === "myfiles" && dlg.place === "myfiles"))
        x: 16; width: dlg.navOpen ? (tile ? 160 : 190) : 36; height: 36
        Rectangle {
            visible: ri.open || riHover.hovered
            width: dlg.navOpen ? ri.width : 36; height: 36; radius: 4
            color: theme.pick("#EBEBEB", "#2E2E2E")
        }
        Rectangle { visible: ri.open; x: -12; y: 10; width: 4; height: 16; radius: 2; color: dlg.railBlue }
        FluentIcon {
            visible: !ri.tile
            x: ri.iconX; y: 8; size: 20
            name: ri.open && ["home-20", "folder-20", "people-20", "star-20"].indexOf(ri.icon) >= 0 ? ri.icon + "-filled" : ri.icon
            color: ri.open ? dlg.railBlue : dlg.label
        }
        SiteTile { visible: !!ri.tile; x: 8; y: 8; acronym: ri.tile ? ri.tile.acronym : ""; tint: ri.tile ? ri.tile.color : "" }
        Text {
            visible: dlg.navOpen && !!ri.text
            x: 36; anchors.verticalCenter: parent.verticalCenter; width: ri.width - x - 4
            elide: Text.ElideRight
            text: ri.text
            font.family: theme.font; font.pixelSize: 14; font.weight: ri.open ? Font.DemiBold : Font.Normal; color: dlg.label
        }
        HoverHandler { id: riHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (ri.key && !ri.tile) dlg.openPlace(ri.key); ri.clicked() } }
        ToolTip.visible: !dlg.navOpen && riHover.hovered && !!(ri.text || ri.tip)
        ToolTip.delay: 500
        ToolTip.text: ri.text || ri.tip
        Accessible.role: Accessible.Link
        Accessible.name: ri.text || ri.tip
    }
    component PickCircle: Item {
        property bool on: false
        property bool shown: false
        width: 18; height: 18
        Rectangle {
            visible: parent.on || parent.shown
            anchors.fill: parent; radius: 9
            color: parent.on ? theme.brand : "transparent"
            border.color: parent.on ? theme.brand : dlg.faint; border.width: 1
            FluentIcon { visible: parent.parent.on; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: "white" }
        }
    }

    function typeIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" || t === "" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }
    function activityIcon(kind) {
        return ({ edit: "edit-16", comment: "comment-16", commentResponse: "arrow-reply-16", share: "share-16", mention: "mention-16" })[kind] || "edit-16"
    }
    function activityText(r) {
        const esc = s => String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
        const t = esc(r.activity).replace("{0}", "<b>" + esc(r.activity_user) + "</b>")
        return r.activity_time ? t + " · " + esc(r.activity_time) : t
    }
    function itemCount(n) { return n === 1 ? "1 item" : (n || 0) + " items" }
    function sizeText(n) {
        if (typeof n !== "number" || isNaN(n) || n < 0) return ""
        if (n === 1) return "1 byte"
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return n + " bytes"
        if (n < 1024e3) return f(n / 1024) + " KB"
        if (n < 1048576e3) return f(n / 1048576) + " MB"
        return f(n / 1073741824) + " GB"
    }
    function acronymOf(name) {
        const w = String(name || "").split(/\s+/).filter(x => /^[A-Za-z0-9]/.test(x))
        return (w.length > 1 ? w[0][0] + w[1][0] : (w[0] || "").slice(0, 2)).toUpperCase()
    }

    /// Tests: the picker's state, and picking by name.
    function stateForTest() {
        return { place: place, trail: trail.map(t => t.name), rows: rows.map(r => r.name), people: people.map(p => p.name),
                 selected: selected.map(s => s.name), loading: loading, nav: navOpen, quick: quickAccess.map(q => q.label) }
    }
    function pickForTest(name) { const r = rows.find(x => x.name === name); if (r) toggle(r); return !!r }
    function openForTest(key) { if (key === "nav") navOpen = !navOpen; else openPlace(key) }
    function attachForTest() { attach() }
}
