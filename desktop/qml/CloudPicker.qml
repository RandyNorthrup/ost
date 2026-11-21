import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

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
// - A folder's command bar (measured 2026-11-16; 285.6 x 44 at the top
//   right, y 20): New folder (108.2; a 16 px brand glyph at 8, the label 14
//   #424242 at 32), Upload (100.8, an 8 px #8A8A8A chevron: Files, Folder),
//   a 0.67 x 20 #D2D0CE line, and the view switch (48: List, Compact List,
//   Tiles). New folder opens OneDrive's "Create a folder" (Name, the 16
//   folder colours, Create / Cancel; a colour goes through
//   foldercoloring/createfolder).
// - Compact List: 32 px rows, 20 px icons, Name 300, Modified 150,
//   Modified By 150, File Size 150, Sharing 170. Tiles: 159.5 x 135 cells
//   12 apart, the folder drawing 72 wide with its count, the name and date
//   (12 px) under it.
// - Shared folders carry OneDrive's people mark (#8F3900): 12 px at 15, 12
//   on a 32 px folder, 7 px at 10, 6.7 on a 20 px one, 16 px on a tile.
// Not built yet: Media's layout menu (River, Waterfall, Square, Inline
// dates, Show file names), its compact toggle, zoom and date headings, and
// a person's own page; People lists who shared files with you in OneDrive's
// collaborator order (Teams also lists files you shared with them).
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
    background: FluentSurface { depth: 64; radius: 8; color: theme.pick("#F5F5F5", "#1F1F1F", "#000000") }

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
    /// The folders' view: "list", "compact" or "tiles".
    property string view: "list"
    /// The folder shown ({drive_id, item_id}), for New folder and Upload.
    readonly property var here: trail.length ? trail[trail.length - 1] : null
    readonly property bool folderView: trail.length > 0 && place !== "more"
    function reload() { if (here) ask("folders", { drive_id: here.drive_id, item_id: here.item_id }) }
    readonly property var placeTitles: ({ home: qsTr("Home"), shared: qsTr("Shared with you"), favorites: qsTr("Favorites"), people: qsTr("People"), meetings: qsTr("Meetings"), media: qsTr("Media"), more: qsTr("Shared libraries") })
    readonly property var emptyStates: ({ shared: [qsTr("Shared files will show up here"), "empty-shared-v3.png"],
                                          favorites: [qsTr("Items you favorite will show up here"), "empty-favorites-v3.png"],
                                          meetings: [qsTr("Files shared in meetings will show up here"), "empty-meeting-v3.png"] })
    readonly property color ink: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
    readonly property color faint: theme.pick("#8A8A8A", "#ADADAD")
    readonly property color label: theme.pick("#424242", "#D6D6D6")
    readonly property color railBlue: theme.pick("#115EA3", "#479EF5")

    // Media: OneDrive Photos' gallery as Teams' picker shows it
    // (measured on winpc 2026-11-20; AllPhotosView, ODSP 2026-11-06):
    // - the bar at 714.7 / 754.7 / 811.3, 29.3 (32 x 31.3 each, a line
    //   before Zoom): Select layout (View as River / Waterfall / Square,
    //   Inline dates, Show file names), Toggle Compact View (on: 2 px
    //   apart, off: 20) and Zoom controls (a popover: Zoom out, a 100 px
    //   slider 6..20 = 150..500 px, Zoom in; 200 to start);
    // - River: rows as tall as the zoom at most, filled to the width;
    //   Waterfall: columns as wide as the zoom at most; Square: square
    //   cells as large as the zoom at most;
    // - file names add a 44 px block (14 px, 12 in) under each picture;
    // - without inline dates one #F5F5F5 heading (64 tall, 18/600) names
    //   the pictures in view ("Nov 17 - Nov 20, 2026"); with them each
    //   day starts with its date over its first picture (a 40 px band);
    // - the 44 px Timeline at the right (4 px dots 68 apart, the year at
    //   the bottom).
    property string mediaLayout: "river"
    property bool mediaCompact: true
    property bool mediaNames: true
    property bool mediaInline: false
    property int mediaZoom: 200
    readonly property real mediaGap: mediaCompact ? 2 : 20
    readonly property real mediaWidth: 801.7
    readonly property real mediaHeader: mediaInline ? 40 : 0
    readonly property real mediaName: mediaNames ? 44 : 0
    function dayKey(it) { const d = new Date(it.taken || it.modified || 0); return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate() }
    function aspect(it) { return it.w > 0 && it.h > 0 ? it.w / it.h : 4 / 3 }
    // Tiles: [{i, x, y, w, h, header}] and the total height.
    readonly property var mediaTiles: {
        const items = dlg.place === "media" ? dlg.rows : []
        const W = mediaWidth, g = mediaGap, extra = mediaName, out = []
        if (!items.length) return { tiles: [], height: 0 }
        const newSection = i => mediaInline && (i === 0 || dayKey(items[i]) !== dayKey(items[i - 1]))
        let y = 0
        if (mediaLayout === "masonry") {
            let n = Math.max(1, Math.floor((W + g) / (mediaZoom + g)))
            let cw = (W - (n - 1) * g) / n
            while (cw > mediaZoom) { n++; cw = (W - (n - 1) * g) / n }
            const cols = Array(n).fill(0)
            items.forEach((it, i) => {
                let c = 0
                for (let k = 1; k < n; k++) if (cols[k] < cols[c]) c = k
                const h = Math.max(80, it.h > 0 ? Math.min(it.h, cw / aspect(it)) : cw * 0.75)
                out.push({ i: i, x: c * (cw + g), y: cols[c], w: cw, h: h, header: false })
                cols[c] += h + extra + g
            })
            return { tiles: out, height: Math.max(...cols) }
        }
        if (mediaLayout === "grid") {
            const n = Math.max(1, Math.round((W + g) / (mediaZoom + g)))
            const cw = (W - (n - 1) * g) / n
            let col = 0
            items.forEach((it, i) => {
                if (col === n) { col = 0; y += cw + extra + g }
                const hdr = newSection(i)
                if (hdr && col === 0) y += mediaHeader
                out.push({ i: i, x: col * (cw + g), y: y, w: cw, h: cw, header: hdr })
                col++
            })
            return { tiles: out, height: y + cw + extra }
        }
        // River.
        let row = [], sum = 0, last = mediaZoom
        const flush = (final) => {
            let h = (W - (row.length - 1) * g) / sum
            if (final && h > mediaZoom) h = Math.min(last, mediaZoom)
            last = h
            if (row.some(r => newSection(r))) y += mediaHeader
            let x = 0
            for (const r of row) { const w = aspect(items[r]) * h; out.push({ i: r, x: x, y: y, w: final && h < (W - (row.length - 1) * g) / sum ? w : w, h: h, header: newSection(r) }); x += w + g }
            y += h + extra + g
            row = []; sum = 0
        }
        items.forEach((it, i) => {
            row.push(i); sum += aspect(it)
            if ((W - (row.length - 1) * g) / sum <= mediaZoom) flush(false)
        })
        if (row.length) flush(true)
        return { tiles: out, height: y - g }
    }
    // The pictures in view, oldest to newest, as Teams names them.
    function rangeText(a, b) {
        if (!a || !b) return ""
        const loc = Qt.locale(), long_ = d => d.toLocaleDateString(loc, "MMM d, yyyy"), short_ = d => d.toLocaleDateString(loc, "MMM d")
        if (a.getFullYear() !== b.getFullYear()) return long_(a) + " - " + long_(b)
        if (a.toDateString() === b.toDateString()) return long_(a)
        return short_(a) + " - " + long_(b)
    }
    readonly property string mediaRange: {
        const t = mediaTiles.tiles, items = dlg.rows
        if (!t.length || dlg.place !== "media") return ""
        const top = mediaFlick.contentY, bottom = top + mediaFlick.height
        const seen = t.filter(x => x.y + x.h >= top && x.y <= bottom).map(x => new Date(items[x.i].taken || items[x.i].modified || 0))
        if (!seen.length) return ""
        const ms = seen.map(d => d.getTime())
        return rangeText(new Date(Math.min(...ms)), new Date(Math.max(...ms)))
    }

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
        else if (key === "myfiles") { trail = [{ name: qsTr("My files"), drive_id: "", item_id: "" }]; ask("folders", { drive_id: "", item_id: "" }) }
        else if (key === "more") ask("libraries")
        else ask("attach_place", { place: key })
    }
    function openLibrary(lib) {
        navOpen = false; place = "lib:" + lib.drive_id; rows = []
        trail = [{ name: lib.label || lib.name, drive_id: lib.drive_id, item_id: "", tile: lib }]
        ask("folders", { drive_id: lib.drive_id, item_id: "" })
    }
    function openFolder(it) {
        const t = trail.length ? trail : [{ name: placeTitles[place] || qsTr("My files"), drive_id: it.drive_id, item_id: "" }]
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
                             { name: qsTr("Documents"), drive_id: f.drive_id, item_id: "" },
                             { name: f.name, drive_id: f.drive_id, item_id: f.id, shared: true }]
                dlg.ask("folders", { drive_id: f.drive_id, item_id: f.id })
                return
            }
            if (kind === "libraries") { dlg.rows = (v || []).map(l => ({ name: l.name, library: l, is_folder: true })); return }
            dlg.people = v && v.people ? v.people : []
            dlg.rows = v && v.items ? v.items : []
            if (dlg.openWhenListed) {
                const f = dlg.rows.find(r => r.is_folder && r.name === dlg.openWhenListed)
                dlg.openWhenListed = ""
                if (f) dlg.openFolder(f)
            }
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
            border.color: theme.pick("#F0F0F0", "#333333", "#FFFFFF"); border.width: 0.67
            clip: true
            readonly property var cols: [[qsTr("Name"), 45.7], [qsTr("Opened"), 370.2], [qsTr("Owner"), 524.7], [qsTr("Activity"), 699.2]]
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
                    color: sel ? theme.pick("#CFE4FA", "#0C3B5E", "#000000") : hrHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    PickCircle { x: 21; y: 19; on: hr.sel; shown: hrHover.hovered || hr.sel }
                    FluentIcon { x: 53; y: 11.6; size: 32; name: dlg.typeIcon(hr.modelData.kind) }
                    Text {
                        x: 101; y: 9.8; width: 280; elide: Text.ElideRight
                        text: hr.modelData.name.replace(/\.(loop|fluid)$/i, "")
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hr, theme.text)
                    }
                    Text {
                        x: 101; y: 29.5; width: 280; elide: Text.ElideRight
                        text: hr.modelData.location || ""
                        font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hr, dlg.ink)
                    }
                    Text { x: 378.1; anchors.verticalCenter: parent.verticalCenter; width: 140; elide: Text.ElideRight; text: hr.modelData.opened || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hr, dlg.ink) }
                    Text { x: 532; anchors.verticalCenter: parent.verticalCenter; width: 160; elide: Text.ElideRight; text: hr.modelData.owner || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hr, dlg.ink) }
                    FluentIcon { visible: !!hr.modelData.activity; x: 710.5; y: 8; size: 16; name: "edit-16"; color: theme.onFill(hr, theme.pick("#0F6CBD", "#479EF5", "#FFFFFF")) }
                    Text {
                        visible: !!hr.modelData.activity
                        x: 736.5; y: 8; width: 95.5
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: dlg.activityText(hr.modelData)
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hr, dlg.ink)
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
            visible: dlg.place !== "home" && dlg.place !== "people" && dlg.place !== "media" && dlg.rows.length > 0 && !(dlg.folderView && dlg.view === "tiles")
            readonly property bool compact: dlg.folderView && dlg.view === "compact"
            x: 16; y: 80; width: content.width - 40; height: dlg.height - 80 - y
            radius: 12; color: theme.surface
            border.color: theme.pick("#F0F0F0", "#333333", "#FFFFFF"); border.width: 0.67
            clip: true
            Rectangle {
                x: 0.7; y: 0.7; width: parent.width - 1.4; height: 43.7
                topLeftRadius: 12; topRightRadius: 12
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
                HoverHandler { id: tableHead }
                PickCircle { x: 23; anchors.verticalCenter: parent.verticalCenter; shown: tableHead.hovered; on: dlg.allPicked(); TapHandler { onTapped: dlg.pickAll() } }
                FluentIcon { x: 64; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "document-16"; color: dlg.faint }
                Repeater {
                    model: table.compact ? [[qsTr("Name"), 92.3], [qsTr("Modified"), 392.3], [qsTr("Modified By"), 542.3], [qsTr("File Size"), 692.3], [qsTr("Sharing"), 842.3]]
                                         : [[qsTr("Name"), 104], [qsTr("Modified"), 374], [qsTr("Modified By"), 544], [qsTr("Activity"), 694]]
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
                    readonly property bool compact: table.compact
                    width: ListView.view.width; height: compact ? 32 : 59
                    color: sel ? theme.pick("#CFE4FA", "#0C3B5E", "#000000") : frHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: fr.sel ? "transparent" : theme.pick("#F5F5F5", "#2E2E2E", "#000000") }
                    PickCircle { visible: !fr.modelData.is_folder; x: 23; y: fr.compact ? 7 : 20.5; on: fr.sel; shown: frHover.hovered || fr.sel }
                    SiteTile { visible: !!fr.modelData.library; x: 58; y: 13.5; size: 32; acronym: fr.modelData.library ? dlg.acronymOf(fr.modelData.library.site || fr.modelData.name) : "" }
                    FluentIcon {
                        id: frIcon
                        visible: !fr.modelData.library
                        x: fr.compact ? 64.3 : 58; y: fr.compact ? 6 : 13.5; size: fr.compact ? 20 : 32
                        name: (fr.modelData.is_folder ? (fr.modelData.special === "shortcuts" ? "ft-companyfolder-32" : "ft-folder-32") : dlg.typeIcon(fr.modelData.kind)).replace("-32", fr.compact ? "-20" : "-32")
                        swaps: fr.modelData.is_folder && fr.modelData.special !== "shortcuts" ? theme.folderSwaps(fr.modelData.folder_color) : ({})
                    }
                    // OneDrive's people mark on a shared folder.
                    FluentIcon {
                        visible: !!fr.modelData.is_folder && fr.modelData.sharing === "Shared" && fr.modelData.special !== "shortcuts"
                        x: frIcon.x + (fr.compact ? 10 : 15); y: frIcon.y + (fr.compact ? 6.7 : 12)
                        size: fr.compact ? 7 : 12; name: fr.compact ? "person-16" : "people-12"; color: "#8F3900"
                    }
                    Text {
                        visible: !fr.compact
                        x: 104; y: fr.meta ? 11.5 : 19.2; width: 260; elide: Text.ElideRight
                        text: fr.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, dlg.ink)
                    }
                    readonly property string meta: modelData.library ? "" : modelData.is_folder ? dlg.itemCount(modelData.child_count) : dlg.sizeText(modelData.size)
                    // Compact List: one line, then Modified, Modified By, File
                    // Size and Sharing.
                    Text {
                        visible: fr.compact
                        x: 92.3; anchors.verticalCenter: parent.verticalCenter; width: 290; elide: Text.ElideRight
                        text: fr.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, dlg.ink)
                    }
                    Repeater {
                        model: fr.compact ? [[392.3, fr.modelData.modified_text || ""], [542.3, fr.modelData.modified_by || ""],
                                             [692.3, fr.modelData.is_folder ? dlg.itemCount(fr.modelData.child_count) : dlg.sizeText(fr.modelData.size)],
                                             [842.3, fr.modelData.sharing || ""]] : []
                        Text {
                            required property var modelData
                            x: modelData[0]; anchors.verticalCenter: parent.verticalCenter; width: 140; elide: Text.ElideRight
                            text: modelData[1]
                            font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, fr.cell)
                        }
                    }
                    Row {
                        visible: !!fr.meta && !fr.compact
                        x: 104; y: 30.9; spacing: 0
                        Text { text: fr.meta; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(fr, fr.cell) }
                        Text { visible: fr.modelData.sharing === "Shared"; text: " • "; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(fr, fr.cell) }
                        FluentIcon { visible: fr.modelData.sharing === "Shared"; y: 3.6; size: 12; name: "people-12"; color: theme.onFill(fr, fr.cell) }
                    }
                    Text { visible: !fr.compact; x: 374; anchors.verticalCenter: parent.verticalCenter; width: 150; elide: Text.ElideRight; text: fr.modelData.modified_text || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, fr.cell) }
                    Text { visible: !fr.compact; x: 544; anchors.verticalCenter: parent.verticalCenter; width: 130; elide: Text.ElideRight; text: fr.modelData.modified_by || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, fr.cell) }
                    FluentIcon {
                        visible: !!fr.modelData.activity && !fr.compact
                        x: 694; anchors.verticalCenter: parent.verticalCenter; size: 14
                        name: fr.modelData.activity ? dlg.activityIcon(fr.modelData.activity.kind) : ""
                        color: theme.onFill(fr, theme.pick("#0078D4", "#479EF5", "#FFFFFF"))
                    }
                    Text {
                        visible: !!fr.modelData.activity && !fr.compact
                        x: 712; anchors.verticalCenter: parent.verticalCenter; width: fr.width - x - 12
                        elide: Text.ElideRight
                        text: fr.modelData.activity ? fr.modelData.activity.text + " " + fr.modelData.activity.time : ""
                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(fr, fr.cell)
                    }
                    HoverHandler { id: frHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: fr.modelData.library ? dlg.openLibrary(fr.modelData.library) : dlg.toggle(fr.modelData) }
                    Accessible.role: fr.modelData.is_folder ? Accessible.Button : Accessible.CheckBox
                    Accessible.name: modelData.name
                    Accessible.checked: sel
                }
            }
        }

        // Tiles.
        GridView {
            id: tiles
            visible: dlg.folderView && dlg.view === "tiles" && dlg.rows.length > 0 && dlg.place !== "people" && dlg.place !== "media"
            x: 16; y: 88; width: content.width - 32; height: dlg.height - 80 - y
            clip: true; boundsBehavior: Flickable.StopAtBounds
            cellWidth: 171.5; cellHeight: 147
            model: visible ? dlg.rows : []
            delegate: Item {
                id: tl
                required property var modelData
                readonly property bool sel: dlg.isSelected(modelData)
                width: 159.5; height: 135
                Rectangle { anchors.fill: parent; radius: 4; color: tl.sel ? theme.pick("#CFE4FA", "#0C3B5E", "#000000") : tlHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#1AEBFF") : "transparent" }
                Item {
                    visible: !!tl.modelData.is_folder
                    x: 43.7; y: 21.5; width: 72; height: 52
                    FluentIcon { x: 0; y: -10; size: 72; name: "ft-folder-32"; swaps: theme.folderSwaps(tl.modelData.folder_color) }
                    Text { x: 4; y: 34; text: tl.modelData.child_count || 0; font.family: theme.font; font.pixelSize: 12; color: "#8F3900" }
                    FluentIcon { visible: tl.modelData.sharing === "Shared"; x: 52; y: 33.2; size: 16; name: "people-16"; color: "#8F3900" }
                }
                Image {
                    visible: !tl.modelData.is_folder
                    x: 39.75; y: 8; width: 80; height: 72
                    fillMode: Image.PreserveAspectFit
                    source: dlg.thumbs[tl.modelData.id] || ""
                    Component.onCompleted: if (!tl.modelData.is_folder) dlg.wantThumb(tl.modelData)
                    FluentIcon { visible: parent.status !== Image.Ready; anchors.centerIn: parent; size: 32; name: dlg.typeIcon(tl.modelData.kind) }
                }
                Text {
                    x: 6; y: 90; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: tl.modelData.name
                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(tl, dlg.ink)
                }
                Text {
                    x: 6; y: 107; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: tl.modelData.modified_text || ""
                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(tl, dlg.faint)
                }
                HoverHandler { id: tlHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.toggle(tl.modelData) }
                Accessible.role: tl.modelData.is_folder ? Accessible.Button : Accessible.CheckBox
                Accessible.name: modelData.name
                Accessible.checked: sel
            }
        }

        // The folder's command bar.
        Row {
            id: commandBar
            visible: dlg.folderView
            x: content.width - 285.6 + 10; y: 20; height: 44
            CmdItem { icon: "folder-add-20"; label: qsTr("New folder"); w: 108.2; onClicked: dlg.openNewFolder() }
            CmdItem { id: uploadItem; icon: "arrow-upload-16"; label: qsTr("Upload"); w: 100.8; chevron: true; onClicked: uploadMenu.open() }
            Item {
                width: 4.7; height: 44
                Rectangle { x: 2; y: 10; width: 0.67; height: 20; color: theme.pick("#D2D0CE", "#605E5C", "#FFFFFF") }
            }
            CmdItem { id: viewItem; icon: dlg.view === "tiles" ? "grid-16" : dlg.view === "compact" ? "text-align-left-16" : "list-16"; label: ""; tip: qsTr("View options"); w: 48; chevron: true; onClicked: viewMenu.open() }
        }
        MenuPopup {
            id: uploadMenu
            parent: uploadItem
            fabric: true; fabricWidth: 180
            x: 0; y: uploadItem.height
            items: [{ label: qsTr("Files"), icon: "document-arrow-up-20" }, { label: qsTr("Folder"), icon: "folder-arrow-up-20" }]
            onPicked: i => { if (i === 0) uploadFiles.open(); else uploadFolder.open() }
        }
        MenuPopup {
            id: viewMenu
            parent: viewItem
            fabric: true; fabricWidth: 180
            x: viewItem.width - 180; y: viewItem.height
            items: [{ label: qsTr("List"), icon: "list-16", checked: dlg.view === "list" }, { label: qsTr("Compact List"), icon: "text-align-left-16", checked: dlg.view === "compact" },
                    { label: qsTr("Tiles"), icon: "grid-16", checked: dlg.view === "tiles" }]
            onPicked: i => dlg.view = ["list", "compact", "tiles"][i]
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
                    Avatar { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 40; name: pr.modelData.name }
                    Text {
                        x: 76; anchors.verticalCenter: parent.verticalCenter; width: 170; elide: Text.ElideRight
                        text: pr.modelData.name
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    // Teams fills the files cell (570 wide from 268) with
                    // chips 12 apart, shortens the last name that fits and
                    // puts the rest under "+N" (measured 2026-11-20).
                    FontMetrics { id: chipFont; font.family: theme.font; font.pixelSize: 12 }
                    FontMetrics { id: pillFont; font.family: theme.font; font.pixelSize: 10 }
                    readonly property var fit: {
                        const items = pr.modelData.items || [], avail = 570, plus = 50, out = []
                        let used = 0
                        for (let i = 0; i < items.length; i++) {
                            const name = items[i].name.replace(/\.[^.]+$/, "")
                            const fixed = 32.7 + 0.7 + pillFont.advanceWidth(items[i].modified_text || "") + 36 + 8
                            const natural = fixed + chipFont.advanceWidth(name)
                            const rest = i < items.length - 1 ? 12 + plus : 0
                            if (used + natural + rest <= avail) { out.push({ item: items[i], nameW: chipFont.advanceWidth(name) }); used += natural + 12; continue }
                            const room = avail - used - (i < items.length - 1 ? 12 + plus : 0) - fixed
                            if (room >= 40) { out.push({ item: items[i], nameW: room }); i++ }
                            return { chips: out, more: items.length - i }
                        }
                        return { chips: out, more: 0 }
                    }
                    Row {
                        x: 268; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Repeater {
                            model: pr.fit.chips
                            Rectangle {
                                id: chip
                                required property var modelData
                                readonly property var item: modelData.item
                                readonly property bool sel: dlg.isSelected(item)
                                width: chipName.x + chipName.width + 8 + chipPill.width + 8; height: 41.3; radius: 6
                                color: sel ? theme.pick("#CFE4FA", "#0C3B5E", "#000000") : theme.surface
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 6 }
                                FluentIcon { x: 8.7; anchors.verticalCenter: parent.verticalCenter; size: 16; name: dlg.typeIcon(chip.item.kind).replace("-32", "-20") }
                                Text {
                                    id: chipName
                                    x: 32.7; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, chip.modelData.nameW); elide: Text.ElideRight
                                    text: chip.item.name.replace(/\.[^.]+$/, "")
                                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill(chip, theme.text)
                                }
                                Rectangle {
                                    id: chipPill
                                    x: chipName.x + chipName.width + 0.7; anchors.verticalCenter: parent.verticalCenter; width: chipTime.implicitWidth + 36; height: 24; radius: 20
                                    color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                                    // The activity glyph (shared with you).
                                    FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "share-16"; color: dlg.label }
                                    Text {
                                        id: chipTime
                                        x: 24; anchors.verticalCenter: parent.verticalCenter
                                        text: chip.item.modified_text || ""
                                        font.family: theme.font; font.pixelSize: 10; color: dlg.label
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: dlg.toggle(chip.item) }
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: item.name
                                Accessible.checked: sel
                            }
                        }
                        Rectangle {
                            id: moreChip
                            visible: pr.fit.more > 0
                            width: moreText.implicitWidth + 24; height: 41.3; radius: 6
                            color: moreHover.hovered ? theme.rowHover : theme.surface
                            FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 6 }
                            Text { id: moreText; anchors.centerIn: parent; text: "+" + pr.fit.more; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(moreChip, theme.text) }
                            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                            Accessible.role: Accessible.Button; Accessible.name: "+" + pr.fit.more
                        }
                    }
                }
            }
        }

        Row {
            visible: dlg.place === "media"
            x: 714.7; y: 29.3; spacing: 8
            MediaBtn { id: layoutItem; icon: dlg.mediaLayout === "masonry" ? "glance-20" : dlg.mediaLayout === "grid" ? "grid-20" : "glance-horizontal-20"; tip: qsTr("Select layout"); onClicked: layoutMenu.open() }
            MediaBtn { icon: dlg.mediaCompact ? "arrow-maximize-vertical-20" : "arrow-minimize-vertical-20"; tip: qsTr("Toggle Compact View"); onClicked: dlg.mediaCompact = !dlg.mediaCompact }
            Item { width: 8.6; height: 31.3; Rectangle { x: 4; y: 5.6; width: 0.67; height: 20; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") } }
            MediaBtn { id: zoomItem; icon: "add-subtract-circle-20"; tip: qsTr("Zoom controls"); onClicked: zoomPop.open() }
        }
        MenuPopup {
            id: layoutMenu
            parent: layoutItem
            checkColumn: true
            x: layoutItem.width - 252; y: layoutItem.height + 2
            items: [{ group: qsTr("View as") },
                    { label: qsTr("River"), icon: "glance-horizontal-20", checked: dlg.mediaLayout === "river" },
                    { label: qsTr("Waterfall"), icon: "glance-20", checked: dlg.mediaLayout === "masonry" },
                    { label: qsTr("Square"), icon: "grid-20", checked: dlg.mediaLayout === "grid" },
                    { separator: true },
                    { label: qsTr("Inline dates"), icon: "calendar-date-20", checked: dlg.mediaInline },
                    { label: qsTr("Show file names"), icon: "app-title-20", checked: dlg.mediaNames }]
            onPicked: i => {
                const k = items[i]
                if (k.label === qsTr("River")) dlg.mediaLayout = "river"
                else if (k.label === qsTr("Waterfall")) dlg.mediaLayout = "masonry"
                else if (k.label === qsTr("Square")) dlg.mediaLayout = "grid"
                else if (k.label === qsTr("Inline dates")) dlg.mediaInline = !dlg.mediaInline
                else if (k.label === qsTr("Show file names")) dlg.mediaNames = !dlg.mediaNames
            }
        }
        Popup {
            id: zoomPop
            parent: zoomItem
            x: zoomItem.width - width + 32; y: zoomItem.height
            width: 189.3; height: 48.7; padding: 0
            background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
            contentItem: Item {
                MediaBtn { x: 8.7; y: 8.6; icon: "subtract-circle-20"; tip: qsTr("Zoom out"); onClicked: dlg.mediaZoom = Math.max(150, dlg.mediaZoom - 25) }
                Slider {
                    id: zoomSlider
                    x: 44.7; y: 16.3; width: 100; height: 16
                    from: 6; to: 20; stepSize: 1
                    value: dlg.mediaZoom / 25
                    onMoved: dlg.mediaZoom = Math.round(value) * 25
                    Accessible.name: qsTr("Photo zoom level")
                }
                MediaBtn { x: 148.7; y: 8.6; icon: "add-circle-20"; tip: qsTr("Zoom in"); onClicked: dlg.mediaZoom = Math.min(500, dlg.mediaZoom + 25) }
            }
        }
        Rectangle {
            visible: dlg.place === "media" && !dlg.mediaInline && dlg.rows.length > 0
            x: 22; y: 78; width: 805.3; height: 64
            color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
            Text {
                y: 20; text: dlg.mediaRange
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
        }
        Flickable {
            id: mediaFlick
            visible: dlg.place === "media" && dlg.rows.length > 0
            x: 22; y: dlg.mediaInline ? 142 - dlg.mediaHeader : 142; width: dlg.mediaWidth; height: dlg.height - 80 - y
            contentHeight: dlg.mediaTiles.height
            clip: true; boundsBehavior: Flickable.StopAtBounds
            Repeater {
                model: dlg.place === "media" ? dlg.mediaTiles.tiles : []
                Item {
                    id: mt
                    required property var modelData
                    readonly property var item: dlg.rows[modelData.i] || ({})
                    readonly property bool sel: dlg.isSelected(item)
                    x: modelData.x; y: modelData.y
                    width: modelData.w; height: modelData.h + dlg.mediaName
                    // A day's date (inline dates): over its first picture.
                    Text {
                        visible: mt.modelData.header
                        y: -dlg.mediaHeader + 12
                        text: { const d = new Date(mt.item.taken || mt.item.modified || 0); return d.toLocaleDateString(Qt.locale(), d.getFullYear() === new Date().getFullYear() ? "MMM d" : "MMM d, yyyy") }
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    }
                    Rectangle {
                        width: mt.modelData.w; height: mt.modelData.h
                        color: "#000000"
                        border.color: mt.sel ? theme.brand : "transparent"; border.width: 2
                        Image { anchors.fill: parent; anchors.margins: mt.sel ? 4 : 0; fillMode: Image.PreserveAspectCrop; source: dlg.thumbs[mt.item.id] || ""; asynchronous: true }
                        // Videos: the play mark, with its length on hover or
                        // when picked.
                        Rectangle {
                            id: playMark
                            visible: !!mt.item.video
                            x: 12; y: 12; height: 28; radius: 4
                            width: playRow.implicitWidth + 8
                            color: Qt.rgba(0, 0, 0, 0.5)
                            Row {
                                id: playRow
                                anchors.centerIn: parent; spacing: 4
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: "play-circle-20-filled"; color: theme.onFill(playMark, "white") }
                                Text {
                                    visible: (mtHover.hovered || mt.sel) && mt.item.duration > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: { const s = Math.round((mt.item.duration || 0) / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
                                    font.family: theme.font; font.pixelSize: 12; color: "white"
                                }
                            }
                        }
                        Rectangle {
                            visible: mt.sel
                            anchors { right: parent.right; top: parent.top; margins: 12 }
                            width: 20; height: 20; radius: 10
                            color: theme.brand; border.color: "white"; border.width: 1.33
                            FluentIcon { anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: "white" }
                        }
                    }
                    Text {
                        visible: dlg.mediaNames
                        x: 12; y: mt.modelData.h + 12; width: mt.modelData.w - 24; elide: Text.ElideRight
                        text: mt.item.name || ""
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    Component.onCompleted: dlg.wantThumb(item)
                    HoverHandler { id: mtHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dlg.toggle(mt.item) }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: item.name || ""
                    Accessible.checked: sel
                }
            }
        }
        // The Timeline (44 px at the right): a dot per month in the list,
        // 68 apart, the oldest year at the bottom.
        Item {
            visible: dlg.place === "media" && dlg.rows.length > 0
            x: 823.3; y: 78; width: 44; height: Math.min(399.3, dlg.height - 80 - 78)
            Accessible.role: Accessible.ScrollBar; Accessible.name: qsTr("Timeline")
            readonly property var months: { const m = []; for (const it of dlg.rows) { const d = new Date(it.taken || it.modified || 0); const k = d.getFullYear() * 12 + d.getMonth(); if (m.indexOf(k) < 0) m.push(k) } return m }
            Repeater {
                model: Math.max(1, Math.floor((parent.height - 64) / 68) + 1)
                Rectangle { required property int index; x: 20; y: 64 + index * 68; width: 4; height: 4; radius: 2; color: theme.pick("#C7C7C7", "#5C5C5C", "#FFFFFF") }
            }
            Text {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 8 }
                text: dlg.rows.length ? String(new Date(dlg.rows[dlg.rows.length - 1].taken || dlg.rows[dlg.rows.length - 1].modified || 0).getFullYear()) : ""
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary
            }
        }

        // Empty places and folders.
        Item {
            visible: !dlg.loading && dlg.rows.length === 0 && dlg.people.length === 0
            x: 0; y: folder ? 207.7 : 119.7; width: content.width - 8; height: 316
            // A folder's (the library view's): 20/600 at 207.7 over
            // empty_files_v3 (256).
            readonly property var es: dlg.trail.length ? [qsTr("This folder is empty"), "empty-files-v3.png"] : dlg.emptyStates[dlg.place] || ["", ""]
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
                id: hcFill2
                visible: dlg.selected.length > 0
                x: 24; y: 24; height: 32; width: selText.implicitWidth + 47.8; radius: 18
                color: clearHover.hovered ? theme.menuHover : "transparent"
                border.color: theme.pick("#605E5C", "#A19F9D", "#FFFFFF"); border.width: 0.67
                Text {
                    id: selText
                    x: 12.7; anchors.verticalCenter: parent.verticalCenter
                    text: dlg.selected.length + " selected"
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill2, theme.text)
                }
                FluentIcon { x: selText.x + selText.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "dismiss-12"; color: theme.onFill(hcFill2, theme.text) }
                HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.selected = [] }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear selected items")
            }
            Rectangle {
                id: hcFill3
                x: parent.width - 192; y: 24; width: 80; height: 32; radius: 2
                readonly property bool on: dlg.selected.length > 0
                color: on ? (attachHover.hovered ? theme.brandHover : theme.brand) : theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                Text {
                    anchors.centerIn: parent; text: qsTr("Attach")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill3, parent.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F"))
                }
                HoverHandler { id: attachHover; enabled: parent.on; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: parent.on; onTapped: dlg.attach() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Attach")
            }
            Rectangle {
                id: hcFill4
                x: parent.width - 104; y: 24; width: 80; height: 32; radius: 2
                color: cancelHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cancel")
            }
        }
    }

    // Closing the wide pane: a click on the content.
    MouseArea { visible: dlg.navOpen; x: 210; width: dlg.width - 210; height: dlg.height; onClicked: dlg.navOpen = false }

    // The rail, or the Navigation Pane over the content.
    Rectangle {
        id: rail
        width: dlg.navOpen ? 210 : 68; height: dlg.height
        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
        topLeftRadius: 8; bottomLeftRadius: 8
        FluentSurface { visible: dlg.navOpen; z: -1; anchors.fill: parent; depth: 16; radius: 8 }
        Text {
            visible: dlg.navOpen
            x: 24; y: 14; height: 37.3; verticalAlignment: Text.AlignVCenter
            text: qsTr("OneDrive")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        }
        RailItem { y: 18; icon: dlg.navOpen ? "panel-left-contract-20" : "panel-left-expand-20"; tip: qsTr("Navigation Pane"); iconX: dlg.navOpen ? 162 : 8; onClicked: dlg.navOpen = !dlg.navOpen }
        RailItem { y: 51.3; key: "home"; icon: "home-20"; text: qsTr("Home") }
        RailItem { y: 87.3; key: "myfiles"; icon: "folder-20"; text: qsTr("My files") }
        RailItem { y: 123.3; key: "shared"; icon: "people-20"; text: qsTr("Shared") }
        RailItem { y: 159.3; key: "favorites"; icon: "star-20"; text: qsTr("Favorites") }
        Item {
            x: 16; y: 203.3; width: dlg.navOpen ? 190 : 36; height: 36
            Text {
                visible: dlg.navOpen
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Browse by")
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            }
            FluentIcon { visible: !dlg.navOpen; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "chevron-down-16"; color: dlg.ink }
            Accessible.role: Accessible.Heading
            Accessible.name: qsTr("Browse by")
        }
        RailItem { y: 239.3; key: "people"; icon: "person-20"; text: qsTr("People") }
        RailItem { y: 275.3; key: "meetings"; icon: "calendar-ltr-20"; text: qsTr("Meetings") }
        RailItem { y: 311.3; key: "media"; icon: "image-20"; text: qsTr("Media") }
        Rectangle { visible: !dlg.navOpen; x: 22; y: 366.8; width: 24; height: 1; radius: 1; color: theme.pick("#D1D1D1", "#3D3D3D", "#000000") }
        Row {
            visible: dlg.navOpen
            x: 24; y: 364; spacing: 6
            Text { text: qsTr("Quick access"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
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
                y: 10; text: qsTr("More places...")
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: dlg.railBlue
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.openPlace("more") }
            Accessible.role: Accessible.Link
            Accessible.name: qsTr("More places...")
        }
    }

    // New folder: OneDrive's "Create a folder" (measured 2026-11-16: the
    // title 20/28 600, Name 14/600 over a 390.7 x 32 box "Enter your folder
    // name", Folder color 14/600 over 24 px swatches 51 apart in two rows of
    // eight, the picked one ringed white and #0078D4; Create (brand; off
    // until a name) and Cancel).
    function openNewFolder() { newFolderName.text = ""; newFolderColor = 0; newFolderDialog.open(); newFolderName.forceActiveFocus() }
    property int newFolderColor: 0
    property string openWhenListed: ""
    function createFolder() {
        const n = newFolderName.text.trim()
        if (!n || !here) return
        newFolderDialog.close()
        loading = true
        backend.driveAction(tag + "picker_create_folder", "{}", JSON.stringify({ drive_id: here.drive_id, item_id: here.item_id, name: n, color: newFolderColor }))
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (op !== dlg.tag + "picker_create_folder" && op !== dlg.tag + "picker_upload") return
            dlg.loading = false
            if (error) console.warn("picker:", op, error)
            // Teams opens the folder it made.
            else if (op === dlg.tag + "picker_create_folder") dlg.openWhenListed = JSON.parse(result).name || ""
            dlg.reload()
        }
    }
    Popup {
        id: newFolderDialog
        parent: Overlay.overlay
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 390.7 + 2 * 24; padding: 24
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: "transparent" }
        Column {
            width: 390.7
            spacing: 0
            Item {
                width: parent.width; height: 28
                Text { text: qsTr("Create a folder"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; lineHeight: 28; lineHeightMode: Text.FixedHeight }
                Rectangle {
                    id: nfClose
                    x: 374.7; y: -12; width: 32; height: 30; radius: 4
                    color: nfCloseHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 20; name: "dismiss-20"; color: theme.onFill(nfClose, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                    HoverHandler { id: nfCloseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: newFolderDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close")
                }
            }
            Item { width: 1; height: 8 }
            Text { text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; lineHeight: 20; lineHeightMode: Text.FixedHeight }
            Item { width: 1; height: 10 }
            Rectangle {
                width: 390.7; height: 32; radius: 4; color: theme.surface
                border.width: 0.67; border.color: theme.pick("#B3B3B3", "#757575", "#FFFFFF")
                Rectangle { anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33; height: newFolderName.activeFocus ? 2 : 0.67; color: newFolderName.activeFocus ? theme.pick("#0F6CBD", "#479EF5", "#FFFFFF") : theme.pick("#4D4D4D", "#ADADAD", "#FFFFFF") }
                TextInput {
                    id: newFolderName
                    x: 8.7; width: parent.width - 17.4; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                    Keys.onReturnPressed: dlg.createFolder()
                    Text { visible: !newFolderName.text; text: qsTr("Enter your folder name"); font: newFolderName.font; color: theme.textSecondary }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Name")
                }
            }
            Item { width: 1; height: 28 }
            Text { text: qsTr("Folder color"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; lineHeight: 20; lineHeightMode: Text.FixedHeight }
            Item { width: 1; height: 6 }
            Grid {
                columns: 8; columnSpacing: 27; rowSpacing: 18
                x: 4; topPadding: 6
                Repeater {
                    model: theme.folderColors.slice().sort((a, b) => Number(a.code) - Number(b.code))
                    Item {
                        id: sw
                        required property var modelData
                        readonly property bool on: dlg.newFolderColor === Number(modelData.code)
                        width: 24; height: 24
                        Rectangle { visible: sw.on; anchors.centerIn: parent; width: 32; height: 32; radius: 16; color: "transparent"; border.width: 2; border.color: theme.pick("#0078D4", "#479EF5", "#FFFFFF") }
                        Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: sw.modelData.hex }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dlg.newFolderColor = Number(sw.modelData.code) }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.name
                        Accessible.checked: on
                    }
                }
            }
            Item { width: 1; height: 26 }
            Row {
                anchors.right: parent.right
                spacing: 12
                Rectangle {
                    id: nfCreate
                    readonly property bool on: !!newFolderName.text.trim()
                    width: 121; height: 32; radius: 2
                    color: on ? (nfCreateHover.hovered ? theme.brandHover : theme.brand) : theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                    Text { anchors.centerIn: parent; text: qsTr("Create"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(nfCreate, parent.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")) }
                    HoverHandler { id: nfCreateHover; enabled: parent.on; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: parent.on; onTapped: dlg.createFolder() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Create")
                }
                Rectangle {
                    id: nfCancel
                    width: 83.3; height: 32; radius: 2
                    color: nfCancelHover.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#8A8886", "#666666", "#FFFFFF")
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(nfCancel, theme.text) }
                    HoverHandler { id: nfCancelHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: newFolderDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel")
                }
            }
        }
    }
    FileDialog {
        id: uploadFiles
        title: qsTr("Upload")
        fileMode: FileDialog.OpenFiles
        onAccepted: dlg.upload(selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
    }
    FolderDialog {
        id: uploadFolder
        title: qsTr("Upload")
        onAccepted: dlg.upload([decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))])
    }
    function upload(paths) {
        if (!here || !paths.length) return
        loading = true
        backend.driveAction(tag + "picker_upload", "{}", JSON.stringify({ drive_id: here.drive_id, item_id: here.item_id, paths: paths }))
    }
    // Media's bar buttons (Fluent subtle, 32 x 31.3, 20 px icons).
    component MediaBtn: Rectangle {
        id: mb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: mbHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: mb.icon; color: theme.onFill(mb, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: mbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: mb.clicked() }
        ToolTip.visible: mbHover.hovered && !!tip; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
    component CmdItem: Item {
        id: ci
        property string icon
        property string label
        property string tip: label
        property real w: 100
        property bool chevron: false
        signal clicked()
        width: w; height: 44
        Rectangle { anchors.fill: parent; color: ciHover.hovered ? theme.pick("#F3F2F1", "#2E2E2E", "#1AEBFF") : "transparent" }
        FluentIcon { x: 8; y: 14; size: 16; name: ci.icon; color: theme.pick("#5B5FC7", "#7F85F5", "#FFFFFF") }
        Text {
            visible: !!ci.label
            x: 32; y: 15; text: ci.label
            font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
        }
        FluentIcon { visible: ci.chevron; x: ci.label ? ci.width - 16 : 32; y: 18; size: 8; name: "chevron-down-12"; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
        HoverHandler { id: ciHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ci.clicked() }
        ToolTip.visible: !ci.label && ciHover.hovered; ToolTip.delay: 500; ToolTip.text: ci.tip
        Accessible.role: Accessible.Button
        Accessible.name: ci.tip || ci.label
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
            color: theme.pick("#EBEBEB", "#2E2E2E", "#000000")
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
            id: hcFill5
            visible: parent.on || parent.shown
            anchors.fill: parent; radius: 9
            color: parent.on ? theme.brand : "transparent"
            border.color: parent.on ? theme.brand : dlg.faint; border.width: 1
            FluentIcon { visible: parent.parent.on; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: theme.onFill(hcFill5, "white") }
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
    function itemCount(n) { return n === 1 ? qsTr("1 item") : qsTr("%1 items").arg(n || 0) }
    function sizeText(n) {
        if (typeof n !== "number" || isNaN(n) || n < 0) return ""
        if (n === 1) return qsTr("1 byte")
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return qsTr("%1 bytes").arg(n)
        if (n < 1024e3) return qsTr("%1 KB").arg(f(n / 1024))
        if (n < 1048576e3) return qsTr("%1 MB").arg(f(n / 1048576))
        return qsTr("%1 GB").arg(f(n / 1073741824))
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
    function openForTest(key) { if (key === "nav") navOpen = !navOpen; else if (key.startsWith("view:")) view = key.slice(5); else if (key === "newfolder") openNewFolder(); else openPlace(key) }
    function closeDialogsForTest() { newFolderDialog.close(); uploadMenu.close(); viewMenu.close() }
    function attachForTest() { attach() }
}
