import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// The OneDrive app, laid out as Teams desktop's (measured at 1x): a
// 280 px pane with "OneDrive", Create or upload, and the views (Home,
// My files, Shared, Favorites, Libraries, Recycle bin, Browse files by
// People / Meetings / Media);
// the content shows the view's title and a white card with the files
// table (Name, Modified, Modified By, File size, Sharing). Libraries are
// your teams' SharePoint document libraries.
Item {
    id: root
    /// The backend's drive_json, parsed.
    property var driveData: ({})
    property bool busy: false
    property string userName: ""
    signal load(string view, string driveId, string itemId)
    signal download(string itemJson)
    signal upload(string driveId, string folderId, string paths)
    signal newFolder(string driveId, string parentId, string name)
    signal remove(string driveId, string itemId)
    signal favorite(string driveId, string itemId, bool on)
    signal restore(string ids)
    signal purge(string ids)
    readonly property alias fileActions: actions
    /// Browse files by People: the person picked.
    property string person: ""
    /// Their object id (two people can share a name).
    property string personId: ""

    property string view: "recent"
    /// Folders opened from My files or a library: [{name, drive_id, item_id}].
    property var trail: []
    readonly property var here: trail.length ? trail[trail.length - 1] : { name: "", drive_id: "", item_id: "" }
    readonly property var items: view === "people"
        ? ((driveData.people || []).find(p => personId ? p.id === personId : p.name === person) || { items: [] }).items
        : driveData.items || []
    readonly property var deleted: driveData.deleted || []
    // Filter by (TASK-0236): the folder's column filters as the backend
    // applied them ([{field: "Modified"|"Editor", values, labels}]).
    readonly property var filters: view === "folder" ? (driveData.filters || []) : []
    function filterOf(field) { return filters.find(f => f.field === field) || { field: field, values: [], labels: [] } }
    function setFilter(field, values, labels) {
        const out = filters.filter(f => f.field !== field)
        if (values.length) out.push({ field: field, values: values, labels: labels })
        backend.driveSetFilters(JSON.stringify(out))
    }
    function removeFilterValue(field, value) {
        const f = filterOf(field)
        const i = f.values.indexOf(value)
        setFilter(field, f.values.filter((v, j) => j !== i), (f.labels || []).filter((v, j) => j !== i))
    }
    readonly property var people: driveData.people || []
    /// Shared and a person's page list Date shared and Shared by.
    readonly property bool sharedView: view === "shared" || view === "people"
    readonly property var libraries: driveData.libraries || []
    readonly property bool canWrite: view === "folder"
    /// In a subfolder Teams puts the folder's own command bar on the top
    /// line, the trail under it (68 lower) and the list at 144.67.
    readonly property bool sub: view === "folder" && trail.length > 1
    readonly property var hereItem: sub && driveData.here && driveData.here.id === here.item_id ? driveData.here : null

    function open(v) {
        view = v; trail = []; person = ""; personId = ""; selectedIds = []
        load(v === "myfiles" ? "folder" : v, "", "")
        if (v === "myfiles") { view = "folder"; trail = [{ name: qsTr("My files"), drive_id: "", item_id: "" }] }
    }
    function openFolder(name, driveId, itemId) {
        view = "folder"
        trail = trail.concat([{ name: name, drive_id: driveId, item_id: itemId }])
        load("folder", driveId, itemId)
    }
    function back(i) {
        trail = trail.slice(0, i + 1)
        load("folder", here.drive_id, here.item_id)
    }
    readonly property string title: ({ recent: qsTr("Home"), shared: qsTr("Shared"), libraries: qsTr("Libraries"), favorites: qsTr("Favorites"),
        recycle: qsTr("Recycle bin"), meetings: qsTr("Meetings"), media: qsTr("Media"), people: person || qsTr("People") })[view]
        || (trail.length ? trail[0].name : qsTr("My files"))
    Component.onCompleted: { open("recent"); actions.loadQuickAccess() }

    // Teams' OneDrive list colours.
    readonly property color ink: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
    readonly property color strong: theme.pick("#424242", "#D6D6D6")
    readonly property color accent: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color hairline: theme.pick("#F0F0F0", "#3D3D3D")
    readonly property color selectedFill: theme.pick("#E9EAF6", "#2B2C3F", "#000000")
    readonly property var favoriteIds: driveData.favorite_ids || []

    /// Sort ▾ and the column headers (OneDrive's: Type, Name, Modified,
    /// Modified By, File size; folders stay first), and the view switch
    /// (List, Compact List, Tiles). Both last for the session.
    property string sortField: ""
    property bool sortAsc: true
    property string listView: "list"
    readonly property var shown: {
        if (!sortField) return items
        const key = it => sortField === "size" ? (it.is_folder ? it.child_count || 0 : it.size || 0)
                        : sortField === "kind" ? String(it.kind || "") : String(it[sortField] || "").toLowerCase()
        const out = items.slice()
        out.sort((a, b) => {
            if (a.is_folder !== b.is_folder) return a.is_folder ? -1 : 1
            const x = key(a), y = key(b)
            const c = typeof x === "number" ? x - y : x < y ? -1 : x > y ? 1 : 0
            return sortAsc ? c : -c
        })
        return out
    }
    /// OneDrive's responsive columns for a grid `t` wide (its
    /// ODBMyFilesResponsiveBehavior and layout module 4377): DocIcon 40,
    /// Name 210-800, Modified 130-200, Modified By 130-260, File size
    /// 85-110, Sharing 75-110, Activity 113-550. Too narrow: columns drop by
    /// priority (Sharing, File size, Activity, Modified By, Modified); spare
    /// width is shared evenly up to each maximum, then among all but DocIcon.
    /// [DocIcon, Name, Modified, Modified By, File size, Sharing, Activity];
    /// 0 for a dropped column.
    function responsiveWidths(t) {
        const cols = [[40, 40, 1, false, false], [210, 800, 1, false, true], [130, 200, 2, true, true], [130, 260, 3, true, true],
                      [85, 110, 5, true, true], [75, 110, 6, true, true], [113, 550, 4, true, true]]
            .map(c => ({ min: c[0], max: c[1], priority: c[2], hide: c[3], unlimited: c[4], grow: 1 }))
        if (t <= 0) return cols.map(() => 0)
        const a = cols.map(c => c.min), n = cols.map(c => c.grow), shown = cols.map(() => true)
        let o = a.reduce((x, y) => x + y, 0), i = cols.length, s = cols.filter(c => c.min !== c.max).length, l = cols.filter(c => c.unlimited).length
        const hideable = cols.map((c, idx) => ({ c: c, idx: idx })).filter(x => x.c.hide).sort((x, y) => y.c.priority - x.c.priority)
        if (o > t) {
            for (let d = 0; d < hideable.length && o > t; d++) {
                const k = hideable[d].idx
                o -= cols[k].min; shown[k] = false; a[k] = 0; i -= n[k]; n[k] = 0; s--
                if (cols[k].unlimited) l--
            }
        }
        let d = t - o
        const growable = () => cols.some((c, k) => a[k] < c.max && n[k] > 0 || a[k] >= c.max && c.unlimited)
        for (let guard = 0; d > 1 && s > 0 && growable() && i !== 0 && guard < 50; guard++) {
            const per = d / i
            let full = 0
            for (let k = 0; k < cols.length; k++) {
                if (!shown[k]) { a[k] = 0; continue }
                if (a[k] >= cols[k].max) { full++; continue }
                if (a[k] + per * n[k] > cols[k].max) { d -= cols[k].max - a[k]; a[k] = cols[k].max; s--; i -= n[k]; n[k] = 0 }
                else { a[k] += per * n[k]; d -= per * n[k] }
            }
            if (full === cols.length) break
        }
        const m = a.reduce((x, y) => x + y, 0)
        if (l > 0) {
            const p = (t - m) / l
            for (let k = 0; k < cols.length; k++) if (shown[k] && cols[k].unlimited) a[k] += p * cols[k].grow
        }
        return a
    }
    /// Column widths you set (Column settings ▸ Widen / Narrow, or a drag):
    /// Teams keeps them on this device for each library's view, by the
    /// column's name (OneDrive's spcolumnsize-unsaved-{view} in the page's
    /// local storage). OST keeps them in the device setting
    /// "oneDriveColumnWidths" by library.
    property var allColumnWidths: {
        try { return JSON.parse(backend.setting("oneDriveColumnWidths") || "{}") } catch (e) { return {} }
    }
    readonly property var columnWidths: allColumnWidths[here.drive_id || "me"] || ({})
    function colLabel(k) { return ({ name: "Name", modified: "Modified", modified_by: "Modified By", size: "File size", sharing: "Sharing", activity: "Activity" })[k] || k }
    function setColumnWidth(k, px) {
        const drive = here.drive_id || "me"
        if (!drive) return
        const all = Object.assign({}, allColumnWidths)
        all[drive] = Object.assign({}, all[drive] || {})
        all[drive][colLabel(k)] = String(px)
        allColumnWidths = all
        backend.setSetting("oneDriveColumnWidths", JSON.stringify(all))
    }
    /// Widen / Narrow: the column's width (whole pixels) ± 32.
    function resizeColumn(k, wider) { setColumnWidth(k, Math.floor(table.w(k)) + (wider ? 32 : -32)) }
    readonly property var sortFields: [{ key: "kind", label: qsTr("Type") }, { key: "name", label: qsTr("Name") }, { key: "modified", label: qsTr("Modified") },
                                       { key: "modified_by", label: qsTr("Modified By") }, { key: "size", label: qsTr("File size") }]
    function sortMenuItems() {
        return sortFields.map(f => ({ label: f.label, checked: sortField === f.key })).concat([{ separator: true },
            { label: qsTr("Ascending"), checked: !!sortField && sortAsc }, { label: qsTr("Descending"), checked: !!sortField && !sortAsc }])
    }
    function pickSort(label) {
        const f = sortFields.find(x => x.label === label)
        if (f) { sortField = f.key; return }
        if (!sortField) sortField = "name"
        sortAsc = label === qsTr("Ascending")
    }
    readonly property var viewItems: [{ label: qsTr("List"), icon: "list-16", checked: listView === "list" },
                                      { label: qsTr("Compact List"), icon: "text-align-left-16", checked: listView === "compact" },
                                      { label: qsTr("Tiles"), icon: "grid-16", checked: listView === "tiles" }]
    function toggleDetails(it) {
        if (details.visible) { details.item = null; details.folder = null; return }
        if (it) details.item = it
        else { details.item = null; details.folder = { name: root.view === "folder" ? root.here.name : root.title, drive_id: root.here.drive_id, item_id: root.here.item_id } }
    }

    /// The rows picked with their selection circles (ids); a reload keeps
    /// those still there, so another folder starts with none.
    property var selectedIds: []
    readonly property var selection: items.filter(i => selectedIds.indexOf(i.id) >= 0)
    onItemsChanged: selectedIds = selectedIds.filter(id => items.some(i => i.id === id))
    function toggle(it) {
        selectedIds = selectedIds.indexOf(it.id) >= 0 ? selectedIds.filter(i => i !== it.id) : selectedIds.concat([it.id])
    }
    function selectOnly(it) { selectedIds = [it.id] }
    // The Details pane follows the selected item.
    onSelectionChanged: if (details.item && selection.length === 1 && selection[0].id !== details.item.id) details.item = selection[0]

    // File pictures for Tiles (Graph's "medium"), by item id.
    property var thumbs: ({})
    property var thumbAsked: ({})
    readonly property string thumbTag: "odt" + Math.floor(Math.random() * 1e9) + ":"
    function wantThumb(it) {
        if (thumbAsked[it.id] || it.is_folder) return
        thumbAsked[it.id] = true
        backend.driveAction(thumbTag + "thumb", JSON.stringify(it), JSON.stringify({ size: "medium" }))
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.thumbTag) || error) return
            const v = JSON.parse(result)
            if (v.path) { const t = Object.assign({}, root.thumbs); t[v.id] = v.path; root.thumbs = t }
        }
    }
    // A coloured folder: OneDrive's shades in place of the yellow folder
    // drawing's (front gradient, back, its dark stop).
    function folderSwaps(code) {
        if (!code || code === "0") return ({})
        const c = actions.colorFor(code).shades
        return { "#FFDD57": c[3], "#F7AB40": c[4], "#D48300": c[1], "#C77B00": c[1], "#BA7300": c[2] }
    }
    function badge(kind) {
        const k = String(kind || "").toLowerCase()
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : ""
    }
    // OneDrive's file size wording (FileActions.sizeText).
    function size(n) { return actions.sizeText(n) }
    function itemCount(n) { return n === 1 ? qsTr("1 item") : qsTr("%1 items").arg(n || 0) }
    function fileIcon(kind) { return actions.fileIcon(kind) }
    // The selection bar's Open: the file's app icon for Office files,
    // OneDrive's OpenFile glyph otherwise.
    function openIcon(kind) {
        const k = String(kind || "").toLowerCase()
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : "open-16"
    }
    // The Activity column's glyph (OneDrive: Edit, Comment, Reply, Share,
    // Accounts, Groupedlist).
    function activityIcon(kind) { return actions.activityIcon(kind) }
    function ago(t) {
        if (!t) return ""
        const d = new Date(t), s = (Date.now() - d) / 1000
        if (s < 60) return qsTr("Just now")
        if (s < 3600) return qsTr("%1 minutes ago").arg(Math.floor(s / 60))
        if (s < 86400) return qsTr("%1 hours ago").arg(Math.floor(s / 3600))
        if (s < 172800) return qsTr("Yesterday")
        return theme.fmtDate(d, "MMMM d")
    }
    function iconFor(it) {
        if (it.is_folder) return "folder-20-filled"
        if (["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(it.kind) >= 0) return "image-20"
        return "document-20"
    }

    Rectangle { anchors.fill: parent; color: theme.pane }

    // The left pane
    Item {
        id: pane
        width: 280; height: parent.height
        Text {
            x: 24; y: 31
            text: qsTr("OneDrive")
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            id: createButton
            x: 16; y: 80; width: 157; height: 32; radius: theme.radius
            color: cbh.hovered ? theme.brandHover : theme.brandFill
            Row {
                anchors.centerIn: parent; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: theme.onFill(createButton, "white") }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Create or upload"); color: theme.onFill(createButton, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            }
            HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: createMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Create or upload")
            MenuPopup {
                id: createMenu
                y: parent.height + 4; width: 220
                items: [{ label: qsTr("Folder"), icon: "folder-add-20" }, { separator: true }, { label: qsTr("Files upload"), icon: "arrow-upload-20" }]
                // Outside a folder (Home, Shared, ...) it goes into My files, as in Teams.
                onPicked: i => {
                    if (!root.canWrite) root.open("myfiles")
                    i === 0 ? folderDialog.open() : uploadPicker.open()
                }
            }
        }
        Column {
            x: 8; y: 137; width: parent.width - 32
            Repeater {
                model: [
                    { key: "recent", label: qsTr("Home"), icon: "home-20" },
                    { key: "myfiles", label: qsTr("My files"), icon: "folder-20" },
                    { key: "shared", label: qsTr("Shared"), icon: "people-20" },
                    { key: "favorites", label: qsTr("Favorites"), icon: "star-20" },
                    { key: "libraries", label: qsTr("Libraries"), icon: "library-20" },
                    { key: "recycle", label: qsTr("Recycle bin"), icon: "delete-20" }
                ]
                NavRow {}
            }
            Item { width: 1; height: 16 }
            Text { x: 16; height: 36; verticalAlignment: Text.AlignVCenter; text: qsTr("Browse files by"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Repeater {
                model: [
                    { key: "people", label: qsTr("People"), icon: "people-20" },
                    { key: "meetings", label: qsTr("Meetings"), icon: "calendar-ltr-20" },
                    { key: "media", label: qsTr("Media"), icon: "image-20" }
                ]
                NavRow {}
            }
            Item { width: 1; height: 16 }
            Text { x: 16; text: qsTr("Quick access"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Item { width: 1; height: 6 }
            // Teams' Quick access: pinned libraries, then the ones used
            // lately; the text only while there are none.
            Text {
                visible: actions.quickAccess.length === 0
                x: 16; width: parent.width - 16; wrapMode: Text.Wrap
                text: qsTr("As you open files from shared libraries, they'll appear in this Quick access list.")
                font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong
            }
            Repeater {
                model: actions.quickAccess
                QuickRow {}
            }
        }
    }

    /// A Quick access library: its 20 px tile, the name, and a pin at the
    /// right on hover (solid, and always shown, once pinned).
    component QuickRow: Rectangle {
        id: qr
        required property var modelData
        readonly property bool sel: root.view === "folder" && root.trail.length > 0 && !!modelData.drive_id && root.trail[0].drive_id === modelData.drive_id
        width: parent.width + 16; height: 36; radius: theme.radius
        color: sel ? theme.selected : qh.hovered ? theme.rowHover : "transparent"
        Rectangle { visible: qr.sel; x: -8; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: theme.brand }
        SiteTile { x: 16; anchors.verticalCenter: parent.verticalCenter; acronym: qr.modelData.acronym; tint: qr.modelData.color }
        Text {
            x: 44; width: parent.width - 44 - 36; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
            text: qr.modelData.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: qr.sel ? Font.DemiBold : Font.Normal; color: theme.onFill(qr, theme.text)
        }
        HoverHandler { id: qh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (qr.modelData.drive_id) { root.trail = []; root.openFolder(qr.modelData.label, qr.modelData.drive_id, "") } }
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label
        Rectangle {
            id: hcFill1
            visible: qh.hovered || qr.modelData.pinned
            x: parent.width - 32; width: 24; height: 24; radius: 4; anchors.verticalCenter: parent.verticalCenter
            color: qph.hovered ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : "transparent"
            FluentIcon { anchors.centerIn: parent; name: qr.modelData.pinned ? "pin-16-filled" : "pin-16"; size: 16; color: theme.onFill(hcFill1, root.ink) }
            HoverHandler { id: qph; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: actions.pinLibrary(qr.modelData, !qr.modelData.pinned) }
            ToolTip.visible: qph.hovered; ToolTip.delay: 300
            ToolTip.text: (qr.modelData.pinned ? qsTr("Unpin %1 from Quick access") : qsTr("Pin %1 to Quick access")).arg(qr.modelData.label)
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Pin to Quick access")
        }
    }

    component NavRow: Rectangle {
        id: nr
        required property var modelData
        readonly property bool sel: root.view === modelData.key || (modelData.key === "myfiles" && root.view === "folder" && root.trail.length && root.trail[0].name === qsTr("My files"))
            || (modelData.key === "libraries" && root.view === "folder" && root.trail.length && root.trail[0].name !== qsTr("My files")
                && !actions.quickAccess.some(q => q.drive_id && q.drive_id === root.trail[0].drive_id))
        width: parent.width + 16; height: 36; radius: theme.radius
        color: sel ? theme.selected : nh.hovered && !modelData.off ? theme.rowHover : "transparent"
        opacity: modelData.off ? 0.45 : 1
        Rectangle { visible: nr.sel; x: -8; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: theme.brand }
        FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: nr.sel && nr.modelData.key === "recent" ? "home-20-filled" : nr.sel && nr.modelData.key === "myfiles" ? "folder-20-filled" : nr.modelData.icon; size: 20; color: theme.onFill(nr, nr.sel ? theme.text : theme.textStrong) }
        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: nr.modelData.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: nr.sel ? Font.DemiBold : Font.Normal; color: theme.onFill(nr, theme.text) }
        HoverHandler { id: nh; cursorShape: nr.modelData.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !nr.modelData.off; onTapped: root.open(nr.modelData.key) }
        Accessible.role: Accessible.Button
        Accessible.name: modelData.off ? qsTr("%1 (not available in OST yet)").arg(modelData.label) : modelData.label
    }

    // Content
    Item {
        id: content
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        // Title, or the folder trail.
        Row {
            visible: root.selection.length === 0 || root.sub
            x: 4; y: root.sub ? 98 : 30; spacing: 4
            Repeater {
                model: root.view === "folder" ? root.trail : [{ name: root.title }]
                Row {
                    required property var modelData
                    required property int index
                    spacing: 4
                    // Teams: the folders above are 400, the one you're in 600,
                    // with a 12 px chevron (#424242) 4 either side.
                    FluentIcon { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: root.strong }
                    Text {
                        text: modelData.name
                        font.family: theme.font; font.pixelSize: 18
                        font.weight: index === (root.view === "folder" ? root.trail.length - 1 : 0) ? Font.DemiBold : Font.Normal
                        color: index === (root.view === "folder" ? root.trail.length - 1 : 0) ? theme.text : theme.textSecondary
                        HoverHandler { cursorShape: root.view === "folder" && index < root.trail.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: root.view === "folder" && index < root.trail.length - 1; onTapped: root.back(index) }
                    }
                }
            }
        }
        // A subfolder's own commands, with nothing selected: Share, Copy
        // link, Download and Open in OneDrive (Teams' bar, without its card).
        Row {
            id: folderBar
            visible: root.selection.length === 0 && !!root.hereItem
            x: 10; y: 26; spacing: 4
            readonly property var commands: {
                const it = root.hereItem, L = []
                if (!it) return L
                if (it.sp_item) L.push({ label: qsTr("Share"), icon: "share-16" })
                if (it.sp_item || it.web_url) L.push({ label: qsTr("Copy link"), icon: "link-16" })
                if (it.sp_item) L.push({ label: qsTr("Download"), icon: "arrow-download-16" })
                if (it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? qsTr("Open in OneDrive") : qsTr("Open in SharePoint"), icon: "cloud-16" })
                return L
            }
            Repeater {
                model: folderBar.commands
                BarCommand {
                    required property var modelData
                    label: modelData.label; icon: modelData.icon; tip: modelData.label
                    onClicked: actions.actMany([root.hereItem], modelData.label)
                }
            }
        }
        // Sort ▾, the view switch and Details at the title's right.
        Row {
            visible: root.selection.length === 0 && root.view === "folder"
            anchors.right: parent.right; anchors.rightMargin: 16 + 6
            y: 26; spacing: 4
            ViewControls {}
        }
        // The Details pane (Teams': 304 wide at the list's right, under the
        // command bar).
        DetailsPane {
            id: details
            visible: !!item || !!folder
            x: card.x + card.width + 2; y: card.y; width: 304; height: card.height
            item: null
            actions: actions
            onDismissed: { item = null; folder = null }
        }
        // With rows selected, Teams' command bar takes the title's place: a
        // white card (52 tall, radius 12, shadow 8) with the selection's
        // commands from 10 in, and "✕ n selected" at the right.
        FluentSurface {
            id: selBar
            visible: root.selection.length > 0
            x: 0; y: 16; width: parent.width - 16; height: 52
            radius: 12; depth: 8; color: theme.surface
            readonly property var one: root.selection.length === 1 ? root.selection[0] : null
            readonly property bool fav: !!one && root.favoriteIds.indexOf(one.id) >= 0
            // One file: Open ▾, Share, Copy link, Delete, ···; one folder: the
            // same without Open; several: Delete, Add to favorites, Download, ···.
            readonly property var commands: {
                const it = one, L = []
                if (it) {
                    if (!it.is_folder) L.push({ label: qsTr("Open"), icon: root.openIcon(it.kind), chevron: true })
                    if (it.sp_item) L.push({ label: qsTr("Share"), icon: "share-16" })
                    if (it.sp_item || it.web_url) L.push({ label: qsTr("Copy link"), icon: "link-16" })
                    if (root.canWrite) L.push({ label: qsTr("Delete"), icon: "delete-16" })
                } else {
                    if (root.canWrite) L.push({ label: qsTr("Delete"), icon: "delete-16" })
                    if (root.selection.some(i => !i.is_folder)) L.push({ label: qsTr("Add to favorites"), icon: "star-16" })
                    L.push({ label: qsTr("Download"), icon: "arrow-download-16" })
                }
                if (more.length) L.push({ label: "", tip: qsTr("More"), icon: "more-horizontal-16" })
                return L
            }
            // ···: the rest of the item's menu (Teams: Add to favorites, Add
            // shortcut, Download, Duplicate, Move to, Copy to, Rename, Open in
            // OneDrive, Version history; several: Duplicate, Move to, Copy to).
            readonly property var more: {
                const it = one, L = []
                const sp = root.selection.every(i => !!i.sp_item)
                if (it) {
                    if (!it.is_folder) L.push({ label: fav ? qsTr("Remove from favorites") : qsTr("Add to favorites"), icon: "star-16" })
                    L.push({ label: qsTr("Download"), icon: "arrow-download-16" })
                }
                if (root.canWrite && sp) L.push({ label: qsTr("Duplicate"), icon: "add-square-16" })
                if (root.canWrite && sp) L.push({ label: qsTr("Move to"), icon: "folder-arrow-right-16" })
                if (sp) L.push({ label: qsTr("Copy to"), icon: "copy-16" })
                if (it && root.canWrite) L.push({ label: qsTr("Rename"), icon: "rename-16" })
                if (it && it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? qsTr("Open in OneDrive") : qsTr("Open in SharePoint"), icon: "cloud-16" })
                if (it && !it.is_folder && it.sp_item) L.push({ label: qsTr("Version history"), icon: "history-16" })
                return L
            }
            function run(label) {
                openMenu.close(); moreMenu.close()
                // The menus hang under their buttons: Open's from its left
                // (+4), ···'s right edge 4 inside its own.
                if (label === qsTr("Open") && !one) return
                if (label === qsTr("Open")) { openMenu.x = cmdRow.x + cmds.itemAt(0).x + 4; openMenu.items = actions.itemsFor(one)[0].submenu; openMenu.open(); return }
                if (label === "") {
                    const b = cmds.itemAt(commands.length - 1)
                    moreMenu.x = Math.max(0, Math.min(cmdRow.x + b.x + b.width - 4 - 232, width - 232)); moreMenu.open(); return
                }
                actions.actMany(root.selection, label)
            }
            Row {
                id: cmdRow
                x: 10; y: 10; spacing: 4
                Repeater {
                    id: cmds
                    model: selBar.commands
                    BarCommand {
                        required property var modelData
                        label: modelData.label; icon: modelData.icon; chevron: !!modelData.chevron
                        tip: modelData.tip || modelData.label
                        onClicked: selBar.run(modelData.label)
                    }
                }
            }
            MenuPopup {
                id: openMenu
                fabric: true; fabricWidth: 232
                y: 52
                onPicked: i => { actions.item = selBar.one; actions.others = []; actions.act(items[i].label) }
            }
            MenuPopup {
                id: moreMenu
                fabric: true; fabricWidth: 232
                items: selBar.more
                y: 52
                onPicked: i => actions.actMany(root.selection, items[i].label)
            }
            // At the right: Sort ▾, "✕ n selected", a divider, the view switch
            // and Details.
            Row {
                anchors.right: parent.right; anchors.rightMargin: 6
                y: 10; spacing: 4
                BarCommand {
                    label: qsTr("Sort"); icon: "arrow-sort-down-lines-16"; chevron: true; tip: qsTr("Sort all items by")
                    onClicked: { sortMenu2.items = root.sortMenuItems(); sortMenu2.open() }
                    MenuPopup { id: sortMenu2; fabric: true; fabricWidth: 232; y: parent.height + 10; onPicked: i => root.pickSort(items[i].label) }
                }
                Item { width: countPill.width; height: 32
            // "✕ n selected": clears the selection (0.67 #D1D1D1, radius 20).
            Rectangle {
                id: countPill
                y: 0; height: 32; radius: 16
                width: 36.67 + countText.implicitWidth + 14.67
                color: cph.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
                border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                FluentIcon { x: 12.67; y: 10; name: "dismiss-12"; size: 12; color: theme.onFill(countPill, root.ink) }
                Text { id: countText; x: 36.67; y: 9; text: qsTr("%1 selected").arg(root.selection.length); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(countPill, root.ink) }
                HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selectedIds = [] }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear selection") + ", " + qsTr("%1 selected").arg(root.selection.length)
            }
                }
                Item { width: 25; height: 32; Rectangle { x: 12; y: 6; width: 1; height: 20; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") } }
                ViewControls { inBar: true }
            }
        }
        Rectangle {
            id: card
            x: 0; y: root.sub ? 144.67 : 76
            width: parent.width - 16 - (details.visible ? 304 + 2 : 0); height: parent.height - y - 16
            radius: 4
            color: root.listView === "tiles" && root.view === "folder" ? "transparent" : theme.surface
            clip: true
            // People: who shared files with you; pick one to see them.
            ListView {
                visible: root.view === "people" && !root.person
                anchors.fill: parent; anchors.margins: 8
                model: root.people
                delegate: Rectangle {
                    id: hcFill2
                    required property var modelData
                    width: ListView.view.width; height: 52; radius: theme.radius
                    color: pph.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: modelData.name }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill2, theme.text) }
                        Text { text: qsTr("%n files", "", (modelData.files || modelData.items).length); font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill2, theme.textSecondary) }
                    }
                    HoverHandler { id: pph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.personId = modelData.id || ""; root.person = modelData.name } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Files from %1").arg(modelData.name)
                }
            }
            // Recycle bin: Name, Date deleted, Deleted by, Original location.
            Item {
                visible: root.view === "recycle"
                anchors.fill: parent
                Row {
                    id: rhead
                    x: 0; y: 13; height: 36
                    Item { width: 77; height: 36 }
                    HeadCell { label: qsTr("Name"); width: Math.max(200, parent.parent.width * 0.3) }
                    HeadCell { label: qsTr("Date deleted"); width: 150 }
                    HeadCell { label: qsTr("Deleted by"); width: 150 }
                    HeadCell { label: qsTr("Original location"); width: 220 }
                }
                ListView {
                    anchors { top: rhead.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: root.deleted
                    delegate: Rectangle {
                        id: drow
                        required property var modelData
                        width: ListView.view.width; height: 48
                        color: dh.hovered ? theme.rowHover : "transparent"
                        Rectangle { x: 16; width: parent.width - 32; height: 1; color: theme.dividerSoft }
                        Row {
                            height: parent.height
                            Item { width: 77; height: parent.height; FluentIcon { anchors.centerIn: parent; name: "document-20"; size: 20; color: theme.onFill(drow, theme.textSecondary) } }
                            Cell { width: Math.max(200, drow.width * 0.3); text: drow.modelData.name; strong: true }
                            Cell { width: 150; text: root.ago(drow.modelData.deleted) }
                            Cell { width: 150; text: drow.modelData.deleted_by }
                            Cell { width: 220; text: drow.modelData.from }
                        }
                        Rectangle {
                            id: hcFill3
                            visible: dh.hovered || dmenu.visible
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: dmh.hovered ? theme.hc(theme.pane, theme.hcHighlight) : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill3, theme.textStrong) }
                            HoverHandler { id: dmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: dmenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("More options for %1").arg(drow.modelData.name)
                            MenuPopup {
                                id: dmenu
                                x: -200; y: parent.height; width: 220
                                items: [{ label: qsTr("Restore"), icon: "arrow-upload-20" }, { label: qsTr("Delete permanently"), icon: "delete-20" }]
                                onPicked: i => i === 0 ? root.restore(drow.modelData.id) : root.purge(drow.modelData.id)
                            }
                        }
                        HoverHandler { id: dh }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: qsTr("Deleted %1").arg(modelData.name)
                    }
                }
            }
            // Libraries: cards to open.
            ListView {
                visible: root.view === "libraries"
                anchors.fill: parent; anchors.margins: 8
                model: root.libraries
                delegate: Rectangle {
                    id: hcFill4
                    required property var modelData
                    width: ListView.view.width; height: 52; radius: theme.radius
                    color: lh.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "library-20"; size: 20; color: theme.onFill(hcFill4, theme.brand) }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.text) }
                        Text { text: modelData.site; font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill4, theme.textSecondary) }
                    }
                    HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.trail = []; root.openFolder(modelData.site + " · " + modelData.name, modelData.drive_id, "") } }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.site + " " + modelData.name
                }
            }
            // The files table, as Teams' OneDrive app (OneDrive's own list in
            // a frame): select 56, Type 40, Name, Modified 136, Modified By
            // 136, File size 91, Sharing 81, Activity 119; header and rows
            // 49 tall. A hovered row is #EBEBEB, a selected one #E9EAF6,
            // both inset 8 with radius 8.
            Item {
                id: table
                visible: root.view !== "libraries" && root.view !== "recycle" && (root.view !== "people" || !!root.person)
                anchors.fill: parent
                // With the Details pane open the list is narrow (Teams: 555
                // wide): Name and Modified only, rows 63 tall with "Modified
                // by … · size" under the name.
                readonly property bool narrow: width < 640
                // The columns' widths (TASK-0189, measured 2026-11-19): OneDrive's
                // responsive layout over the grid (the width after the 56 px
                // selection column), then the widths you set with Column
                // settings ▸ Widen / Narrow or the header's dividers, never
                // under the responsive one. Activity, the last, fills the rest.
                // The grid can then be wider than the view and scrolls sideways.
                // (The grid: the card less the 56 px selection column and
                // the 9.4 px scroll gutter, as Teams measures.)
                readonly property var base: root.responsiveWidths(width - 56 - 9.4)
                readonly property var keys: ["name", "modified", "modified_by", "size", "sharing", "activity"]
                readonly property var widths: {
                    const stored = root.view === "folder" ? root.columnWidths : ({})
                    const out = {}
                    let used = 40
                    for (let i = 0; i < keys.length - 1; i++) {
                        const b = base[i + 1]
                        if (!b) { out[keys[i]] = 0; continue }
                        const s = parseFloat(stored[root.colLabel(keys[i])])
                        out[keys[i]] = isNaN(s) ? b : Math.max(s, b)
                        used += out[keys[i]]
                    }
                    const b = base[keys.length]
                    const s = parseFloat(stored[root.colLabel("activity")])
                    out.activity = b ? Math.max(isNaN(s) ? b : s, width - 56 - 9.4 - used) : 0
                    return out
                }
                function w(k) { return narrow ? (k === "modified" ? 189.33 : 0) : widths[k] || 0 }
                function shows(k) { return w(k) > 0 }
                readonly property real wName: narrow ? Math.max(120, width - 56 - 40 - 189.33) : widths.name
                readonly property real gridWidth: narrow ? width : 56 + 40 + keys.reduce((a, k) => a + (widths[k] || 0), 0)
                // Filter by's bar (OneDrive's, measured 2026-11-20): 42.67 tall
                // above the header; "Modified:" / "Modified By:" (14,
                // #424242) and a chip per value (24 tall, radius 12, a 24 px
                // picture for a person, 13.33 px text, a 16 px X), 8 apart;
                // a "Clear" pill (22 tall, 1 px border) at the right clears all.
                Item {
                    id: fbar
                    visible: root.filters.length > 0
                    width: parent.width; height: visible ? 42.67 : 0
                    Row {
                        x: 25; y: 10; spacing: 20
                        // chips stop short of the Clear pill
                        width: Math.min(implicitWidth, fbar.width - 25 - clearPill.width - 17 - 12); clip: true
                        Repeater {
                            model: ["Modified", "Editor"].map(f => root.filterOf(f)).filter(f => f.values.length > 0)
                            Row {
                                id: fgroup
                                required property var modelData
                                spacing: 8
                                Text {
                                    y: 2.5
                                    text: (fgroup.modelData.field === "Modified" ? qsTr("Modified") : qsTr("Modified By")) + ":"
                                    font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                }
                                Repeater {
                                    model: fgroup.modelData.values
                                    Rectangle {
                                        id: chip
                                        required property string modelData
                                        required property int index
                                        readonly property bool person: fgroup.modelData.field === "Editor"
                                        readonly property string label: modelData === "@Me" ? qsTr("[Me]") : ((fgroup.modelData.labels || [])[index] || modelData)
                                        height: 24; radius: 12
                                        width: (person ? 32 : 8) + chipText.implicitWidth + 10 + 16 + 8
                                        color: chiph.hovered ? theme.rowHover : theme.surface
                                        Rectangle {
                                            visible: chip.person
                                            width: 24; height: 24; radius: 12
                                            color: theme.pick("#C8C6C4", "#605E5C", "#000000")
                                            FluentIcon { anchors.centerIn: parent; name: "person-16"; size: 16; color: theme.pick("#FFFFFF", "#D6D6D6", "#FFFFFF") }
                                        }
                                        Text {
                                            id: chipText
                                            x: chip.person ? 32 : 8; y: 3
                                            text: chip.label
                                            font.family: theme.font; font.pixelSize: 13; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                        }
                                        FluentIcon {
                                            x: chipText.x + chipText.implicitWidth + 10; y: 4
                                            name: "dismiss-12"; size: 16; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                        }
                                        HoverHandler { id: chiph; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.removeFilterValue(fgroup.modelData.field, chip.modelData) }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: chip.label
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        id: clearPill
                        anchors.right: parent.right; anchors.rightMargin: 17; y: 11
                        height: 22; radius: 12
                        width: 9 + clearText.implicitWidth + 10 + 16 + 8
                        color: clearPillHover.hovered ? theme.rowHover : "transparent"
                        border.width: 1; border.color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                        Text { id: clearText; x: 9; y: 2; text: qsTr("Clear"); font.family: theme.font; font.pixelSize: 13; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                        FluentIcon { x: clearText.x + clearText.implicitWidth + 10; y: 3; name: "dismiss-12"; size: 16; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                        HoverHandler { id: clearPillHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.driveSetFilters("[]") }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Clear")
                    }
                }
                Item {
                    id: head
                    visible: root.listView !== "tiles" || root.view !== "folder"
                    y: fbar.height
                    x: -files.contentX
                    width: Math.max(parent.width, table.gridWidth); height: 49
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
                    HoverHandler { id: headHover }
                    // "Select all rows": on hover, or filled once all are picked.
                    Rectangle {
                        id: hcFill5
                        readonly property bool all: root.items.length > 0 && root.selection.length === root.items.length
                        visible: headHover.hovered || all
                        x: 29; y: 15.5; width: 18; height: 18; radius: 9
                        color: all ? root.accent : theme.surface
                        border.width: all ? 0 : 1; border.color: root.strong
                        FluentIcon { visible: parent.all; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(hcFill5, "white") }
                        TapHandler { onTapped: root.selectedIds = parent.all ? [] : root.items.map(i => i.id) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: qsTr("Select all rows")
                        Accessible.checked: all
                    }
                    Row {
                        id: headRow
                        height: parent.height
                        Item { width: 56; height: 49 }
                        Item { width: 40; height: 49; FluentIcon { x: 13.5; y: 16.17; name: "document-16"; size: 16; color: theme.onFill(card, root.ink) } }
                        ListHead { label: qsTr("Name"); field: root.view === "folder" ? "name" : ""; col: "name"; width: table.wName }
                        ListHead { label: root.view === "recent" ? qsTr("Opened") : root.sharedView ? qsTr("Date shared") : qsTr("Modified"); field: root.view === "folder" ? "modified" : ""; col: "modified"; width: table.w("modified") }
                        ListHead { visible: table.shows("modified_by"); label: root.sharedView ? qsTr("Shared by") : root.view === "recent" ? qsTr("Owner") : qsTr("Modified By"); field: root.view === "folder" ? "modified_by" : ""; col: "modified_by"; width: table.w("modified_by") }
                        ListHead { visible: table.shows("size"); label: qsTr("File size"); field: root.view === "folder" ? "size" : ""; col: "size"; width: table.w("size") }
                        ListHead { visible: table.shows("sharing"); label: qsTr("Sharing"); col: "sharing"; width: table.w("sharing") }
                        ListHead { visible: table.shows("activity"); label: qsTr("Activity"); width: table.w("activity") }
                    }
                    // The dividers: 16 x 36, 8 down, centred on each column's
                    // right edge (Name … Sharing); a drag sets the column to
                    // its left (not under its responsive width), kept as
                    // Teams keeps it. Hover: a 1 px #605E5C line, 28 tall.
                    Repeater {
                        model: root.view === "folder" && !table.narrow ? ["name", "modified", "modified_by", "size", "sharing"] : []
                        Item {
                            id: divider
                            required property string modelData
                            required property int index
                            visible: table.shows(modelData)
                            readonly property real edge: 96 + table.keys.slice(0, index + 1).reduce((a, k) => a + table.w(k), 0)
                            x: edge - 8; y: 8; width: 16; height: 36
                            Rectangle {
                                visible: dvh.hovered || dvDrag.active
                                anchors.centerIn: parent; width: 1; height: 28
                                color: theme.pick("#605E5C", "#ADADAD", "#FFFFFF")
                            }
                            HoverHandler { id: dvh; cursorShape: Qt.SizeHorCursor }
                            property real startWidth: 0
                            DragHandler {
                                id: dvDrag
                                target: null
                                xAxis.enabled: true; yAxis.enabled: false
                                cursorShape: Qt.SizeHorCursor
                                onActiveChanged: if (active) divider.startWidth = table.w(divider.modelData)
                                onTranslationChanged: if (active) root.setColumnWidth(divider.modelData, Math.max(table.base[table.keys.indexOf(divider.modelData) + 1], divider.startWidth + translation.x))
                            }
                            Accessible.role: Accessible.Separator
                            Accessible.name: qsTr("Resize %1").arg(root.colLabel(modelData))
                        }
                    }
                }
                ListView {
                    id: files
                    anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: root.shown
                    visible: root.listView !== "tiles" || root.view !== "folder"
                    boundsBehavior: Flickable.StopAtBounds
                    // Wider columns than the view scroll sideways, as Teams' grid.
                    contentWidth: Math.max(width, table.gridWidth)
                    flickableDirection: contentWidth > width ? Flickable.HorizontalAndVerticalFlick : Flickable.VerticalFlick
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Item {
                        id: frow
                        required property var modelData
                        required property int index
                        readonly property bool sel: root.selectedIds.indexOf(modelData.id) >= 0
                        readonly property bool hot: fh.hovered || actions.item === modelData && actions.menuOpen || root.hoverForTest === index
                        readonly property bool fav: root.favoriteIds.indexOf(modelData.id) >= 0
                        // Compact List: 34 tall rows, 20 px icons.
                        readonly property bool compact: root.listView === "compact" && !table.narrow && root.view === "folder"
                        readonly property real ty: compact ? 7.67 : 14
                        width: Math.max(files.width, table.gridWidth); height: table.narrow ? 63 : compact ? 34 : 49
                        Rectangle {
                            id: hcFill6
                            x: 8; width: parent.width - 16; height: parent.height - 1; radius: 8
                            color: frow.sel ? root.selectedFill : frow.hot ? theme.rowHover : "transparent"
                        }
                        // The selection circle (18, at 29,14): on hover, filled when selected.
                        Rectangle {
                            id: circle
                            visible: frow.hot || frow.sel
                            x: 29; y: (frow.compact ? 34 : 49) / 2 - 9; width: 18; height: 18; radius: 9
                            color: frow.sel ? root.accent : theme.surface
                            border.width: frow.sel ? 0 : 1; border.color: root.strong
                            FluentIcon { visible: frow.sel; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(circle, "white") }
                            TapHandler { onTapped: root.toggle(frow.modelData) }
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: frow.modelData.name
                            Accessible.checked: frow.sel
                        }
                        FluentIcon {
                            x: frow.compact ? 66 : 62; y: frow.compact ? 7 : 8; size: frow.compact ? 20 : 32
                            // OneDrive's Shortcuts folder has its own icon
                            // (Fabric's companyfolder).
                            name: frow.modelData.special === "shortcuts" ? (frow.compact ? "ft-companyfolder-20" : "ft-companyfolder-32")
                                : frow.modelData.is_folder ? "ft-folder-32" : root.fileIcon(frow.modelData.kind)
                            swaps: frow.modelData.is_folder && frow.modelData.special !== "shortcuts" ? root.folderSwaps(frow.modelData.folder_color) : ({})
                        }
                        // Name: OneDrive's "New" mark, the name, then ···, Share and the star.
                        Item {
                            id: nameCell
                            x: 96; width: table.wName; height: frow.height
                            readonly property bool tools: frow.hot || frow.sel
                            FluentIcon { id: newMark; visible: !!frow.modelData.is_new; x: 12; y: frow.ty; size: 12; width: 7.92; name: "glimmer-12"; color: theme.onFill([hcFill6, card], root.strong) }
                            Text {
                                id: nameText
                                x: newMark.visible ? 19.92 : 12; y: frow.ty
                                width: Math.min(implicitWidth, nameCell.width - x - 8 - (nameCell.tools ? 101 : 0))
                                elide: Text.ElideRight
                                text: frow.modelData.title || frow.modelData.name
                                font.family: theme.font; font.pixelSize: 14; font.weight: frow.sel ? Font.DemiBold : Font.Normal
                                color: theme.onFill([hcFill6, card], root.ink)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: frow.activate() }
                                Accessible.role: Accessible.Link
                                Accessible.name: frow.modelData.title || frow.modelData.name
                            }
                            // Narrow: "Modified by OST Test 1 · 0 items" (12 px #5E5E5D).
                            Text {
                                visible: table.narrow
                                x: 12; y: 35.33; width: nameCell.width - 20
                                elide: Text.ElideRight
                                text: qsTr("Modified by %1").arg(frow.modelData.modified_by || root.userName) + " · " + (frow.modelData.is_folder ? root.itemCount(frow.modelData.child_count) : root.size(frow.modelData.size))
                                font.family: theme.font; font.pixelSize: 12; color: theme.onFill([hcFill6, card], theme.pick("#5E5E5D", "#ADADAD", "#FFFFFF"))
                            }
                            Row {
                                visible: nameCell.tools
                                x: nameText.x + nameText.width + 8; y: frow.ty - 5; spacing: 4.5
                                RowTool {
                                    id: moreButton
                                    icon: "more-horizontal-16"; tip: qsTr("More Actions")
                                    onClicked: actions.popup(frow.modelData, moreButton, 0, moreButton.height)
                                }
                                RowTool { visible: !!frow.modelData.sp_item; icon: "share-16"; tip: qsTr("Share"); onClicked: { actions.item = frow.modelData; actions.act("Share") } }
                                RowTool {
                                    visible: !frow.modelData.is_folder
                                    icon: frow.fav ? "star-16-filled" : "star-16"
                                    tip: frow.fav ? qsTr("Remove this item from Favorites") : qsTr("Add this item to Favorites")
                                    onClicked: root.favorite(frow.modelData.drive_id, frow.modelData.id, !frow.fav)
                                }
                            }
                        }
                        Row {
                            x: 96 + table.wName; height: 49
                            RowCell {
                                ty: frow.ty
                                width: table.w("modified"); text: frow.modelData.modified_text || ""
                                tip: frow.modelData.modified_title || ""
                            }
                            RowCell { ty: frow.ty; visible: table.shows("modified_by"); width: table.w("modified_by"); text: root.view === "recent" ? (frow.modelData.owner || "") : root.sharedView ? (frow.modelData.modified_by || "") : frow.modelData.modified_by || root.userName }
                            RowCell { ty: frow.ty; visible: table.shows("size"); width: table.w("size"); text: frow.modelData.is_folder ? root.itemCount(frow.modelData.child_count) : root.size(frow.modelData.size) }
                            Item {
                                visible: table.shows("sharing")
                                width: table.w("sharing"); height: 49
                                clip: true
                                Row {
                                    x: 12; y: frow.ty + 0.67; spacing: 4
                                    FluentIcon { visible: frow.modelData.sharing === "Shared"; y: 2.5; name: "people-16"; size: 14; color: theme.onFill([hcFill6, card], root.strong) }
                                    Text { text: frow.modelData.sharing; font.family: theme.font; font.pixelSize: 14; color: theme.onFill([hcFill6, card], root.ink) }
                                }
                            }
                            Item {
                                width: table.w("activity"); height: 49
                                visible: !!frow.modelData.activity && table.shows("activity")
                                FluentIcon {
                                    x: 12; y: frow.ty + 1.83; size: 16; color: theme.onFill([hcFill6, card], root.strong)
                                    name: frow.modelData.activity && frow.modelData.activity.kind ? root.activityIcon(frow.modelData.activity.kind) : ""
                                }
                                Text {
                                    x: 32; y: 15.83; width: parent.width - 32 - 4; height: 16
                                    elide: Text.ElideRight
                                    text: frow.modelData.activity ? frow.modelData.activity.text + " " + frow.modelData.activity.time : ""
                                    font.family: theme.font; font.pixelSize: 12; color: theme.onFill([hcFill6, card], root.ink)
                                }
                            }
                        }
                        // Right-click: the same menu at the pointer, as Teams.
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: (ev) => actions.popup(frow.modelData, frow, ev.position.x, ev.position.y)
                        }
                        function activate() {
                            if (modelData.is_folder) root.openFolder(modelData.name, modelData.drive_id, modelData.id)
                            else if (modelData.web_url) backend.openFile(modelData.web_url, modelData.name, JSON.stringify(modelData))
                        }
                        HoverHandler { id: fh }
                        // A click selects the row alone (Ctrl adds or removes
                        // it); a double click opens it.
                        TapHandler {
                            onTapped: (ev, button) => (ev.modifiers & Qt.ControlModifier) ? root.toggle(frow.modelData) : root.selectOnly(frow.modelData)
                            onDoubleTapped: frow.activate()
                        }
                        Accessible.role: Accessible.Row
                        Accessible.name: (modelData.is_folder ? qsTr("Folder %1") : qsTr("File %1")).arg(modelData.name)
                        Accessible.selected: sel
                    }
                }
            }
            // Tiles (OneDrive's): 176 x 171 cells, 8 apart, folders first and
            // files from a new row 40 below; a folder is its 112 x 80 art with
            // the item count (#8F3900) and the name and date under it, a file
            // its 74 x 96 picture with the app's badge and its name. Hover:
            // a white card (radius 12, shadow) with the selection circle.
            Flickable {
                id: tiles
                visible: root.listView === "tiles" && root.view === "folder"
                anchors.fill: parent; anchors.leftMargin: 4; anchors.topMargin: 12
                contentHeight: tileCol.height + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: tileCol
                    width: tiles.width
                    spacing: 40
                    Repeater {
                        model: [root.shown.filter(i => i.is_folder), root.shown.filter(i => !i.is_folder)]
                        Flow {
                            required property var modelData
                            visible: modelData.length > 0
                            width: tileCol.width; spacing: 8
                            Repeater {
                                model: parent.modelData
                                Tile {}
                            }
                        }
                    }
                }
            }
            // Empty states, as Teams words them.
            Text {
                visible: !root.busy && !root.driveData.error && root.view !== "libraries"
                    && (root.view === "recycle" ? root.deleted.length === 0 : root.view === "people" && !root.person ? root.people.length === 0 : root.items.length === 0)
                anchors.centerIn: parent
                text: ({ recent: qsTr("Your recent files will show up here"), shared: qsTr("Files shared with you will show up here"),
                         favorites: qsTr("Your favorite files will show up here"), recycle: qsTr("Your recycle bin is empty"),
                         meetings: qsTr("Files from your meetings will show up here"), media: qsTr("Your photos and videos will show up here"),
                         people: qsTr("Files people share with you will show up here") })[root.view] || qsTr("This folder is empty")
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                color: theme.onFill(card, theme.text)
            }
            Text {
                visible: !!root.driveData.error
                anchors.centerIn: parent
                text: root.driveData.error || ""
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.onFill(card, theme.danger)
            }
            BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }
        }
    }

    // The view switch and Details (and, on the title line, Sort ▾ first).
    component ViewControls: Row {
        property bool inBar: false
        spacing: 4
        BarCommand {
            visible: !parent.inBar
            label: qsTr("Sort"); icon: "arrow-sort-down-lines-16"; chevron: true; tip: qsTr("Sort all items by")
            onClicked: { sortMenu.items = root.sortMenuItems(); sortMenu.open() }
            MenuPopup { id: sortMenu; fabric: true; fabricWidth: 232; y: parent.height + 10; onPicked: i => root.pickSort(items[i].label) }
        }
        BarCommand {
            icon: root.listView === "tiles" ? "grid-16" : root.listView === "compact" ? "text-align-left-16" : "list-16"
            chevron: true; tip: qsTr("Switch view options")
            onClicked: viewMenu.open()
            MenuPopup {
                id: viewMenu; fabric: true; fabricWidth: 232; y: parent.height + 10
                items: root.viewItems
                onPicked: i => root.listView = ["list", "compact", "tiles"][i]
            }
        }
        BarCommand {
            label: qsTr("Details"); icon: "panel-right-16"; tip: qsTr("Open the details pane")
            pressed: details.visible
            onClicked: root.toggleDetails(root.selection.length === 1 ? root.selection[0] : null)
        }
    }
    component Tile: Item {
        id: tile
        required property var modelData
        readonly property bool sel: root.selectedIds.indexOf(modelData.id) >= 0
        readonly property bool hot: th.hovered || sel
        width: 176; height: 171
        FluentSurface {
            visible: tile.hot
            anchors.fill: parent; radius: 12; depth: 4
            color: tile.sel ? root.selectedFill : theme.surface
        }
        Rectangle {
            id: hcFill7
            visible: tile.hot
            x: parent.width - 30; y: 12; width: 18; height: 18; radius: 9
            color: tile.sel ? root.accent : theme.surface
            border.width: tile.sel ? 0 : 1; border.color: root.strong
            FluentIcon { visible: tile.sel; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(hcFill7, "white") }
            TapHandler { onTapped: root.toggle(tile.modelData) }
            Accessible.role: Accessible.CheckBox
            Accessible.name: tile.modelData.name
            Accessible.checked: tile.sel
        }
        // A folder: the art and its count.
        Item {
            visible: tile.modelData.is_folder
            x: 32; y: 24; width: 112; height: 80; clip: true
            FluentIcon { x: 0; y: -16; size: 112; name: "ft-folder-32"; swaps: root.folderSwaps(tile.modelData.folder_color) }
            Text { x: 14; y: 56; text: tile.modelData.child_count || 0; font.family: theme.font; font.pixelSize: 14; color: actions.colorFor(tile.modelData.folder_color).shades[5] }
        }
        // A file: its picture (or type icon) with the app's badge.
        Rectangle {
            visible: !tile.modelData.is_folder
            x: 51; y: 16; width: 74; height: 96; radius: 4
            color: theme.surface
            border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
            Image {
                id: thumbImg
                anchors.fill: parent; anchors.margins: 1
                source: root.thumbs[tile.modelData.id] || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            FluentIcon { visible: !thumbImg.source.toString(); anchors.centerIn: parent; size: 32; name: root.fileIcon(tile.modelData.kind) }
            Rectangle {
                visible: !!root.badge(tile.modelData.kind)
                x: 6; y: parent.height - 30; width: 24; height: 24; radius: 4; color: theme.hc("white", "#000000")
                border.width: 0.67; border.color: theme.hc("#E0E0E0", "#FFFFFF")
                FluentIcon { anchors.centerIn: parent; size: 16; name: root.badge(tile.modelData.kind) }
            }
            Component.onCompleted: root.wantThumb(tile.modelData)
        }
        Text {
            x: 8; y: 117; width: parent.width - 16; height: 30
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: tile.modelData.name
            font.family: theme.font; font.pixelSize: 14; color: root.ink
            font.underline: tile.modelData.is_folder && th.hovered
        }
        Text {
            visible: tile.modelData.is_folder
            x: 8; y: 141; width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: tile.modelData.modified_text || ""
            font.family: theme.font; font.pixelSize: 14; color: root.ink
        }
        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: (ev, button) => (ev.modifiers & Qt.ControlModifier) ? root.toggle(tile.modelData) : tile.modelData.is_folder ? root.openFolder(tile.modelData.name, tile.modelData.drive_id, tile.modelData.id) : root.selectOnly(tile.modelData)
            onDoubleTapped: if (!tile.modelData.is_folder && tile.modelData.web_url) backend.openFile(tile.modelData.web_url, tile.modelData.name, JSON.stringify(tile.modelData))
        }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => actions.popup(tile.modelData, tile, ev.position.x, ev.position.y) }
        Accessible.role: Accessible.ListItem
        Accessible.name: (modelData.is_folder ? qsTr("Folder %1") : qsTr("File %1")).arg(modelData.name)
        Accessible.selected: sel
    }
    // The table's header cell: 14/600 #616161 at 10.67, 49 tall. A sortable
    // column shows ↑ / ↓ when sorted and a chevron; a click opens its menu
    // (Ascending, Descending).
    // Teams' menus (OneDrive's wording per column, measured 2026-11-19):
    // Name: Ascending / Descending; Modified: Older to newer / Newer to
    // older; Modified By: A to Z / Z to A; File size: Smaller to larger /
    // Larger to smaller; then Column settings ▸ (Widen column, Narrow
    // column), which Sharing has alone and Activity not at all.
    component ListHead: Item {
        id: lh
        property string label
        property string field: ""
        /// The column, for Column settings ▸ (in a folder).
        property string col: ""
        readonly property bool settings: !!col && root.view === "folder" && !table.narrow
        /// Filter by's field ("Modified", "Editor"), in a folder.
        readonly property string filterField: root.view !== "folder" ? "" : field === "modified" ? "Modified" : field === "modified_by" ? "Editor" : ""
        readonly property int filterCount: filterField ? root.filterOf(filterField).values.length : 0
        readonly property bool hasMenu: !!field || settings
        readonly property var sortWords: ({ name: [qsTr("Ascending"), qsTr("Descending")], modified: [qsTr("Older to newer"), qsTr("Newer to older")],
                                            modified_by: [qsTr("A to Z"), qsTr("Z to A")], size: [qsTr("Smaller to larger"), qsTr("Larger to smaller")] })[field] || [qsTr("Ascending"), qsTr("Descending")]
        height: 49
        Row {
            x: 10.67; y: 14.83; spacing: 6
            Text { text: lh.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink; width: Math.min(implicitWidth, lh.width - 40); elide: Text.ElideRight }
            FluentIcon { visible: !!lh.field && root.sortField === lh.field; y: 3; size: 12; name: root.sortAsc ? "arrow-up-12" : "arrow-down-12"; color: theme.pick("#605E5C", "#D6D6D6", "#FFFFFF") }
            // A filtered column shows OneDrive's funnel after its name.
            FluentIcon { visible: lh.filterCount > 0; y: 1; size: 16; name: "funnel-16"; color: theme.pick("#605E5C", "#D6D6D6", "#FFFFFF") }
            FluentIcon { visible: lh.hasMenu; y: 4; size: 10; name: "chevron-down-12"; color: theme.pick("#605E5C", "#D6D6D6", "#FFFFFF") }
        }
        HoverHandler { enabled: lh.hasMenu; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: lh.hasMenu; onTapped: headMenu.open() }
        function openMenuForTest() { headMenu.open(); return headMenu.items.map(i => i.separator ? "-" : i.label + (i.submenu ? " ▸ " + i.submenu.map(s => s.label).join(", ") : "")) }
        function pickForTest(i, j) { if (j === undefined) headMenu.picked(i); else headMenu.subPicked(i, j); headMenu.close() }
        MenuPopup {
            id: headMenu
            fabric: true; fabricWidth: 232
            x: 2; y: 46
            // Modified and Modified By add Filter by ("Filter by (N)", ticked,
            // once filtered), as OneDrive's column menu.
            items: (lh.field ? [{ label: lh.sortWords[0], checked: root.sortField === lh.field && root.sortAsc }, { label: lh.sortWords[1], checked: root.sortField === lh.field && !root.sortAsc }] : [])
                .concat(lh.filterField ? [{ separator: true }, { label: lh.filterCount ? qsTr("Filter by (%1)", "x.odsp.fb.i:695.columnMenuFilterByWithNumber").arg(lh.filterCount) : qsTr("Filter by"), checked: lh.filterCount > 0 }] : [])
                .concat(lh.field && lh.settings ? [{ separator: true }] : [])
                .concat(lh.settings ? [{ label: qsTr("Column settings"), submenu: [{ label: qsTr("Widen column") }, { label: qsTr("Narrow column") }] }] : [])
            onPicked: i => {
                if (lh.field && i < 2) { root.sortField = lh.field; root.sortAsc = i === 0 }
                else if (lh.filterField && i === 3) filterPane.openFor(lh.filterField, lh.label)
            }
            onSubPicked: (i, j) => root.resizeColumn(lh.col, j === 0)
        }
        Accessible.role: lh.field ? Accessible.Button : Accessible.ColumnHeader
        Accessible.name: root.sortField === field && field ? (root.sortAsc ? qsTr("%1, sorted ascending") : qsTr("%1, sorted descending")).arg(label) : label
    }
    // A row's text cell: 14 px at 12, 14 down; `tip` shows on hover (the
    // Modified column's full date).
    component RowCell: Item {
        property alias text: rt.text
        property string tip: ""
        property real ty: 14
        height: 49
        Text {
            id: rt
            x: 12; y: parent.ty; width: parent.width - 20
            elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; color: root.ink
            HoverHandler { id: rth }
            ToolTip.visible: rth.hovered && parent.tip.length > 0
            ToolTip.text: parent.tip
            ToolTip.delay: 500
        }
    }
    // A command bar button: 32 tall, a 16 px glyph at 8, the label (14 px)
    // at 32, an optional 12 px chevron; 8 px either side.
    component BarCommand: Rectangle {
        id: bc
        property bool pressed: false
        property string label
        property string icon
        property string tip
        property bool chevron: false
        signal clicked()
        height: 32; radius: 4
        width: 8 + 16 + (label ? 8 + bcText.implicitWidth : 0) + (chevron ? 4 + 16 : 0) + 8
        color: bc.pressed ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : bch.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
        FluentIcon { x: 8; y: 8; name: bc.icon; size: 16; color: theme.onFill(bc, bc.icon.startsWith("ft-") ? theme.hc("#212121", "#FFFFFF") : root.ink) }
        Text { id: bcText; visible: !!bc.label; x: 32; y: 9; text: bc.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(bc, root.ink) }
        FluentIcon { visible: bc.chevron; x: bcText.x + bcText.implicitWidth + 6; y: 10; name: "chevron-down-12"; size: 12; color: theme.onFill(bc, root.ink) }
        HoverHandler { id: bch; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bc.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: bc.tip
    }
    // The 28 px buttons after a hovered row's name (16 px #605E5C glyphs).
    component RowTool: Rectangle {
        id: rtool
        property string icon
        property string tip
        signal clicked()
        width: 28; height: 28; radius: 4
        color: rth2.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
        FluentIcon { anchors.centerIn: parent; name: rtool.icon; size: 16; color: theme.onFill(rtool, theme.pick("#605E5C", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: rth2; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rtool.clicked() }
        ToolTip.visible: rth2.hovered
        ToolTip.text: tip
        ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component HeadCell: Item {
        property string label
        height: 36
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Text { text: parent.parent.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
        }
    }
    component Cell: Item {
        property alias text: t.text
        property bool strong: false
        height: 48
        Text {
            id: t
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 12; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: theme.base
            color: parent.strong ? theme.text : theme.textStrong
        }
    }

    FileDialog {
        id: uploadPicker
        title: qsTr("Upload files")
        fileMode: FileDialog.OpenFiles
        onAccepted: root.upload(root.here.drive_id, root.here.item_id,
            selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))).join("\n"))
    }
    Popup {
        id: folderDialog
        anchors.centerIn: parent
        width: 380; padding: 20; modal: true
        onOpened: { folderName.text = ""; folderName.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 14
            Text { text: qsTr("Create a folder"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Rectangle {
                width: 340; height: 32; radius: theme.radius
                color: theme.input; border.color: folderName.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: folderName
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Keys.onReturnPressed: createFolder()
                    function createFolder() {
                        if (!text.trim()) return
                        root.newFolder(root.here.drive_id, root.here.item_id, text.trim()); folderDialog.close()
                    }
                    Text { visible: !folderName.text; text: qsTr("Enter your folder name"); color: theme.textTertiary; font: folderName.font }
                    Accessible.name: qsTr("Folder name")
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    id: hcFill8
                    width: 90; height: 32; radius: theme.radius
                    color: theme.brandFill
                    Text { anchors.centerIn: parent; text: qsTr("Create"); color: theme.onFill(hcFill8, "white"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: folderName.createFolder() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Create")
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius
                    color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: folderDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel")
                }
            }
        }
    }
    // The item's More actions (Teams' OneDrive context menu), its
    // dialogs and notices.
    FileActions {
        id: actions
        anchors.fill: content
        favoriteIds: root.driveData.favorite_ids || []
        canWrite: root.canWrite
        folder: root.view === "folder" ? { drive_id: root.here.drive_id, item_id: root.here.item_id } : { drive_id: "-", item_id: "-" }
        onChanged: root.load(root.view, root.here.drive_id, root.here.item_id)
        onDeleteItem: it => root.remove(it.drive_id, it.id)
        onFavoriteItem: (it, on) => root.favorite(it.drive_id, it.id, on)
        onDownloadItem: it => root.download(JSON.stringify(it))
        onDetailsItem: it => details.item = it
        onPreviewItem: it => viewer.show(it, root.items)
    }

    // Preview: OneDrive's viewer over the whole view.
    FilePreview {
        id: viewer
        anchors.fill: parent
        z: 10
        actions: actions
        favoriteIds: root.favoriteIds
        onFavorite: (it, on) => root.favorite(it.drive_id, it.id, on)
        onDownload: it => root.download(JSON.stringify(it))
        onDetails: it => details.item = it
    }
    function previewForTest() { return viewer.stateForTest() }
    function previewBarForTest() { return viewer.barForTest() }
    function previewHookForTest() { return viewer }
    // Column settings (TASK-0189).
    // Filter by's pane (OneDrive's, measured on winpc 2026-11-20): 340 wide
    // at the right, full height, white with Fluent's panel shadow. Title
    // "Filter by '<column>'" (+ " (N)" with N ticked) 20/600 at 24,20, a
    // 32 px Close 30 from the right; Modified By has a people box
    // ("Enter a name or email address", 290x34 at 25,50) and @Me (a 32 row)
    // before each editor (40 rows, 24 px pictures); Modified lists the
    // dates (32 rows). Apply (80x32) and Clear all (84x32) sit 16 from the
    // bottom; Clear all only unticks, nothing changes until Apply, which
    // closes the pane. A person picked in the box is added, ticked.
    Item {
        id: filterPane
        property string field: ""
        property string title: ""
        property bool open: false
        /// The rows: [{value, label}] (@Me and people the box added first).
        property var options: []
        property var picked: []
        property var pickedLabels: []
        readonly property var current: root.filterOf(field)
        readonly property bool changed: JSON.stringify(picked) !== JSON.stringify(current.values)
        readonly property var served: {
            try { const v = JSON.parse(backend.driveFilterValuesJson || "{}"); return v.field === field ? v : {} } catch (e) { return {} }
        }
        readonly property var people: {
            try { const v = JSON.parse(backend.driveFilterPeopleJson || "{}"); return v.query === peopleBox.text && peopleBox.text.length ? v.people || [] : [] } catch (e) { return [] }
        }
        property var added: []
        readonly property var rows: (field === "Editor" ? [{ value: "@Me", label: qsTr("@Me", "x.odsp.fb.i:2011.FilterByMeFilterOptionLabel") }] : [])
            .concat((served.values || []).filter(o => !added.some(a => a.value === o.value)))
            .concat(added)
            .concat(current.values.filter(v => v !== "@Me" && !(served.values || []).some(o => o.value === v) && !added.some(a => a.value === v))
                        .map(v => ({ value: v, label: (current.labels || [])[current.values.indexOf(v)] || v })))
        function openFor(f, label) {
            field = f; title = label; added = []
            picked = current.values.slice(); pickedLabels = (current.labels || []).slice()
            peopleBox.text = ""
            backend.driveFilterValues(f)
            open = true
        }
        function toggle(o) {
            const i = picked.indexOf(o.value)
            if (i >= 0) { picked = picked.filter((v, j) => j !== i); pickedLabels = pickedLabels.filter((v, j) => j !== i) }
            else { picked = picked.concat([o.value]); pickedLabels = pickedLabels.concat([o.label]) }
        }
        function apply() { root.setFilter(field, picked, pickedLabels); open = false }
        visible: open
        anchors.fill: parent
        z: 50
        // A click outside closes it (Fluent's light-dismiss panel).
        MouseArea { anchors.fill: parent; onClicked: filterPane.open = false }
        FluentSurface {
            id: panel
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 340
            depth: 64; radius: 0
            color: theme.surface
            MouseArea { anchors.fill: parent }
            Text {
                x: 24; y: 20; width: 240
                text: filterPane.picked.length ? qsTr("Filter by '%1' (%2)", "x.odsp.fb.o:8282.FilterSelectPanelTitleWithNumber").arg(filterPane.title).arg(filterPane.picked.length) : qsTr("Filter by '%1'", "x.odsp.fb.o:8282.FilterSelectPanelTitle").arg(filterPane.title)
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
            }
            Rectangle {
                x: 278; y: 18; width: 32; height: 32; radius: 4
                color: closeh.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                HoverHandler { id: closeh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: filterPane.open = false }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
            }
            Rectangle {
                id: boxFrame
                visible: filterPane.field === "Editor"
                x: 25; y: 50; width: 290; height: 34
                color: theme.surface
                border.width: peopleBox.activeFocus ? 2 : 1
                border.color: peopleBox.activeFocus ? root.accent : theme.pick("#605E5C", "#ADADAD", "#FFFFFF")
                TextField {
                    id: peopleBox
                    anchors.fill: parent; anchors.margins: 2
                    leftPadding: 6; background: null
                    placeholderText: qsTr("Enter a name or email address")
                    font.family: theme.font; font.pixelSize: 13
                    onTextEdited: if (text.length) backend.driveFilterPeople(text)
                }
            }
            Column {
                x: 25; y: filterPane.field === "Editor" ? 97 : 49
                width: 290
                Repeater {
                    model: filterPane.rows
                    Item {
                        id: frowItem
                        required property var modelData
                        readonly property bool person: filterPane.field === "Editor" && modelData.value !== "@Me"
                        readonly property bool ticked: filterPane.picked.indexOf(modelData.value) >= 0
                        width: 290; height: person ? 40 : 32
                        Rectangle {
                            id: box
                            x: 8; y: (parent.height - 16) / 2; width: 16; height: 16; radius: 2
                            color: frowItem.ticked ? root.accent : theme.surface
                            border.width: frowItem.ticked ? 0 : 1; border.color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                            FluentIcon { visible: frowItem.ticked; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(box, "white") }
                        }
                        Avatar { visible: frowItem.person; x: 36; y: 8; size: 24; name: frowItem.modelData.label; colorful: true }
                        Text {
                            x: frowItem.person ? 72 : 32; y: (parent.height - height) / 2
                            text: frowItem.modelData.label
                            font.family: theme.font; font.pixelSize: 14; color: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
                        }
                        TapHandler { onTapped: filterPane.toggle(frowItem.modelData) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: frowItem.modelData.label
                        Accessible.checked: frowItem.ticked
                    }
                }
            }
            // The box's suggestions: 260 wide, 54 rows, 40 px pictures.
            Rectangle {
                visible: filterPane.field === "Editor" && peopleBox.activeFocus && filterPane.people.length > 0
                x: 25; y: 88; width: 260; height: filterPane.people.length * 54
                color: theme.surface; radius: 4; z: 5
                border.width: 1; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                Column {
                    Repeater {
                        model: filterPane.people
                        Rectangle {
                            id: sug
                            required property var modelData
                            width: 260; height: 54
                            color: sugh.hovered ? theme.pick("#F0F0F0", "#3D3D3D", "#1AEBFF") : "transparent"
                            Avatar { x: 12; y: 7; size: 40; name: sug.modelData.name; colorful: true }
                            Text { x: 60; y: 17; text: sug.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#616161", "#D6D6D6", "#FFFFFF") }
                            HoverHandler { id: sugh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: filterPane.pickPerson(sug.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: sug.modelData.name
                        }
                    }
                }
            }
            Rectangle {
                id: applyBtn
                x: 25; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                width: 80; height: 32; radius: 4
                readonly property bool on: filterPane.changed
                color: on ? (aph.hovered ? theme.pick("#4F52B2", "#7579EB") : root.accent) : theme.surface
                border.width: on ? 0 : 1; border.color: theme.pick("#EBEBEB", "#3D3D3D", "#FFFFFF")
                Text { anchors.centerIn: parent; text: qsTr("Apply", "x.odsp.fb.o:8282.ApplyFilterButtonLabel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: applyBtn.on ? theme.onFill(applyBtn, "white") : theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") }
                HoverHandler { id: aph; enabled: applyBtn.on; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: applyBtn.on; onTapped: filterPane.apply() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Apply", "x.odsp.fb.o:8282.ApplyFilterButtonLabel")
            }
            Rectangle {
                id: clearBtn
                x: 25 + 80 + 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                width: 84; height: 32; radius: 4
                readonly property bool on: filterPane.picked.length > 0
                color: clh.hovered && on ? theme.rowHover : theme.surface
                border.width: 1; border.color: on ? theme.pick("#D1D1D1", "#666666", "#FFFFFF") : theme.pick("#EBEBEB", "#3D3D3D", "#FFFFFF")
                Text { anchors.centerIn: parent; text: qsTr("Clear all", "x.odsp.fb.o:8282.ClearAllButtonLabel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: clearBtn.on ? theme.pick("#242424", "#FFFFFF", "#FFFFFF") : theme.pick("#D1D1D1", "#5C5C5C", "#3FF23F") }
                HoverHandler { id: clh; enabled: clearBtn.on; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: clearBtn.on; onTapped: { filterPane.picked = []; filterPane.pickedLabels = [] } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear all", "x.odsp.fb.o:8282.ClearAllButtonLabel")
            }
        }
        function pickPerson(p) {
            const o = { value: p.name, label: p.name }
            if (!rows.some(r => r.value === o.value)) added = added.concat([o])
            if (picked.indexOf(o.value) < 0) toggle(o)
            peopleBox.text = ""
        }
    }
    // Filter by (TASK-0236).
    function filterPaneForTest(field) {
        const lh = field === "Modified" ? columnHeadForTest("modified") : columnHeadForTest("modified_by")
        if (lh) lh.pickForTest(3)
        return filterPane.open
    }
    function filterPaneStateForTest() { return { open: filterPane.open, field: filterPane.field, rows: filterPane.rows, picked: filterPane.picked, changed: filterPane.changed, served: filterPane.served } }
    function filterTickForTest(value) { const o = filterPane.rows.find(r => r.value === value); if (o) filterPane.toggle(o); return filterPane.picked }
    function filterTypeForTest(text) { peopleBox.text = text; backend.driveFilterPeople(text) }
    function filterPickPersonForTest(name) { const p = filterPane.people.find(x => x.name === name); if (p) filterPane.pickPerson(p); return !!p }
    function filterApplyForTest() { filterPane.apply() }
    function filterClearAllForTest() { filterPane.picked = []; filterPane.pickedLabels = [] }
    function filtersForTest() { return { filters: root.filters, shown: root.shown.map(i => i.name) } }

    function columnsForTest() { return { width: table.width, base: table.base.map(x => Math.round(x * 100) / 100), widths: table.widths, grid: table.gridWidth, stored: columnWidths, narrow: table.narrow } }
    function columnHeadForTest(col) { for (let i = 0; i < headRow.children.length; i++) { const h = headRow.children[i]; if (h.col === col || (!col && h.label === qsTr("Activity"))) return h } return null }
    function columnMenuForTest(col) { const h = columnHeadForTest(col); return h ? (h.hasMenu ? h.openMenuForTest() : []) : null }
    function columnResizeForTest(col, wider) { resizeColumn(col, wider) }
    function columnDragForTest(col, px) { setColumnWidth(col, Math.max(table.base[table.keys.indexOf(col) + 1], px)) }
    function columnResetForTest() { const all = Object.assign({}, allColumnWidths); delete all[here.drive_id || "me"]; allColumnWidths = all; backend.setSetting("oneDriveColumnWidths", JSON.stringify(all)) }
    function previewStepForTest(d) { viewer.step(d) }
    function previewCloseForTest() { viewer.close() }

    // Test harness hooks
    /// Show row `i` as hovered (grabToImage has no pointer).
    property int hoverForTest: -1
    function selectForTest(names) { selectedIds = items.filter(i => names.indexOf(i.name) >= 0).map(i => i.id); return selectedIds.length }
    function openQuickForTest(label) { const q = actions.quickAccess.find(x => x.label === label); if (q) { root.trail = []; root.openFolder(q.label, q.drive_id, "") } return !!q }
    function folderBarForTest() { return folderBar.visible ? folderBar.commands.map(c => c.label) : [] }
    function folderBarRunForTest(label) { actions.actMany([root.hereItem], label) }
    function barForTest() { return { commands: selBar.commands.map(c => c.label || "···"), more: selBar.more.map(c => c.label), count: root.selection.length } }
    function barRunForTest(label) { selBar.run(label) }
    function setViewForTest(v) { listView = v }
    function sortForTest(f, asc) { sortField = f; sortAsc = asc; return shown.map(i => i.name) }
    function folderDetailsForTest() { selectedIds = []; toggleDetails(null) }
    function detailsForTest() { return details.stateForTest() }
    function detailsScrollForTest(y) { details.scrollForTest(y) }
    function detailsBellForTest() { details.bellForTest() }
    function detailsReloadForTest() { details.load() }
    function detailsCommentForTest(t) { details.commentForTest(t) }
    function detailsDeleteCommentForTest(t) { return details.deleteCommentForTest(t) }
    function detailsCommentsForTest() { return details.commentsForTest() }
    function detailsEditCommentForTest(t, to) { return details.editCommentForTest(t, to) }
    function detailsReplyForTest(t, r) { return details.replyForTest(t, r) }
    function detailsStartEditForTest(t) { return details.startEditForTest(t) }
    function openDetailsForTest(name) { const it = items.find(i => i.name === name); details.item = it || null; return !!it }
    function barCloseForTest() { openMenu.close(); moreMenu.close() }
    function rowsForTest() { return items.map(i => [i.name, i.modified_text, i.modified_title, i.modified_by, i.is_folder ? itemCount(i.child_count) : size(i.size), i.sharing, i.is_new ? "new" : "", i.activity ? i.activity.text + " " + i.activity.time : ""].join(" | ")) }
    function newFolderForTest(name) { root.newFolder(root.here.drive_id, root.here.item_id, name) }
    function restoreTestFolders() {
        const ids = root.deleted.filter(d => d.name === "OST drive test").map(d => d.id)
        if (ids.length) root.restore(ids[0])
        return ids.length
    }
    function purgeTestFolders() {
        const ids = root.deleted.filter(d => d.name === "OST drive test").map(d => d.id)
        if (ids.length) root.purge(ids.join(","))
        return ids.length
    }
    function deleteForTest(name) {
        const it = root.items.find(i => i.name === name)
        if (it) root.remove(it.drive_id, it.id)
        return !!it
    }
}
