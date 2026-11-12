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

    property string view: "recent"
    /// Folders opened from My files or a library: [{name, drive_id, item_id}].
    property var trail: []
    readonly property var here: trail.length ? trail[trail.length - 1] : { name: "", drive_id: "", item_id: "" }
    readonly property var items: view === "people"
        ? ((driveData.people || []).find(p => p.name === person) || { items: [] }).items
        : driveData.items || []
    readonly property var deleted: driveData.deleted || []
    readonly property var people: driveData.people || []
    readonly property var libraries: driveData.libraries || []
    readonly property bool canWrite: view === "folder"

    function open(v) {
        view = v; trail = []; person = ""; selectedIds = []
        load(v === "myfiles" ? "folder" : v, "", "")
        if (v === "myfiles") { view = "folder"; trail = [{ name: "My files", drive_id: "", item_id: "" }] }
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
    readonly property string title: ({ recent: "Home", shared: "Shared", libraries: "Libraries", favorites: "Favorites",
        recycle: "Recycle bin", meetings: "Meetings", media: "Media", people: person || "People" })[view]
        || (trail.length ? trail[0].name : "My files")
    Component.onCompleted: open("recent")

    // Teams' OneDrive list colours.
    readonly property color ink: theme.pick("#616161", "#D6D6D6")
    readonly property color strong: theme.pick("#424242", "#D6D6D6")
    readonly property color accent: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color hairline: theme.pick("#F0F0F0", "#3D3D3D")
    readonly property color selectedFill: theme.pick("#E9EAF6", "#2B2C3F")
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
    readonly property var sortFields: [{ key: "kind", label: "Type" }, { key: "name", label: "Name" }, { key: "modified", label: "Modified" },
                                       { key: "modified_by", label: "Modified By" }, { key: "size", label: "File size" }]
    function sortMenuItems() {
        return sortFields.map(f => ({ label: f.label, checked: sortField === f.key })).concat([{ separator: true },
            { label: "Ascending", checked: !!sortField && sortAsc }, { label: "Descending", checked: !!sortField && !sortAsc }])
    }
    function pickSort(label) {
        const f = sortFields.find(x => x.label === label)
        if (f) { sortField = f.key; return }
        if (!sortField) sortField = "name"
        sortAsc = label === "Ascending"
    }
    readonly property var viewItems: [{ label: "List", icon: "list-16", checked: listView === "list" },
                                      { label: "Compact List", icon: "text-align-left-16", checked: listView === "compact" },
                                      { label: "Tiles", icon: "grid-16", checked: listView === "tiles" }]
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
    function badge(kind) {
        const k = String(kind || "").toLowerCase()
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : ""
    }
    // OneDrive's file size wording: "1 byte", "56 bytes", "26.0 KB",
    // "7.66 MB" (two decimals under 10, one under 100, none above).
    function size(n) {
        if (typeof n !== "number" || isNaN(n) || n < 0) return ""
        if (n === 1) return "1 byte"
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return n + " bytes"
        if (n < 1024e3) return f(n / 1024) + " KB"
        if (n < 1048576e3) return f(n / 1048576) + " MB"
        if (n < 1073741824e3) return f(n / 1073741824) + " GB"
        return f(n / 1099511627776) + " TB"
    }
    function itemCount(n) { return n === 1 ? "1 item" : (n || 0) + " items" }
    function fileIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "wmv", "avi", "mkv", "webm", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }
    // The selection bar's Open: the file's app icon for Office files,
    // OneDrive's OpenFile glyph otherwise.
    function openIcon(kind) {
        const k = String(kind || "").toLowerCase()
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : "open-16"
    }
    // The Activity column's glyph (OneDrive: Edit, Comment, Reply, Share,
    // Accounts, Groupedlist).
    function activityIcon(kind) {
        return ({ edit: "edit-16", comment: "comment-16", commentResponse: "arrow-reply-16", share: "share-16",
                  mention: "mention-16", createTask: "task-list-ltr-20", completeTask: "task-list-ltr-20" })[kind] || "edit-16"
    }
    function ago(t) {
        if (!t) return ""
        const d = new Date(t), s = (Date.now() - d) / 1000
        if (s < 60) return "Just now"
        if (s < 3600) return Math.floor(s / 60) + " minutes ago"
        if (s < 86400) return Math.floor(s / 3600) + " hours ago"
        if (s < 172800) return "Yesterday"
        return Qt.formatDate(d, "MMMM d")
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
            text: "OneDrive"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            color: theme.text
        }
        Rectangle {
            id: createButton
            x: 16; y: 80; width: 157; height: 32; radius: theme.radius
            color: cbh.hovered ? theme.brandHover : theme.brandFill
            Row {
                anchors.centerIn: parent; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Create or upload"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            }
            HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: createMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Create or upload"
            MenuPopup {
                id: createMenu
                y: parent.height + 4; width: 220
                items: [{ label: "Folder", icon: "folder-add-20" }, { separator: true }, { label: "Files upload", icon: "arrow-upload-20" }]
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
                    { key: "recent", label: "Home", icon: "home-20" },
                    { key: "myfiles", label: "My files", icon: "folder-20" },
                    { key: "shared", label: "Shared", icon: "people-20" },
                    { key: "favorites", label: "Favorites", icon: "star-20" },
                    { key: "libraries", label: "Libraries", icon: "library-20" },
                    { key: "recycle", label: "Recycle bin", icon: "delete-20" }
                ]
                NavRow {}
            }
            Item { width: 1; height: 16 }
            Text { x: 16; height: 36; verticalAlignment: Text.AlignVCenter; text: "Browse files by"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Repeater {
                model: [
                    { key: "people", label: "People", icon: "people-20" },
                    { key: "meetings", label: "Meetings", icon: "calendar-ltr-20" },
                    { key: "media", label: "Media", icon: "image-20" }
                ]
                NavRow {}
            }
            Item { width: 1; height: 16 }
            Text { x: 16; text: "Quick access"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Item { width: 1; height: 6 }
            Text {
                x: 16; width: parent.width - 16; wrapMode: Text.Wrap
                text: "As you open files from shared libraries, they'll appear in this Quick access list."
                font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong
            }
        }
    }

    component NavRow: Rectangle {
        id: nr
        required property var modelData
        readonly property bool sel: root.view === modelData.key || (modelData.key === "myfiles" && root.view === "folder" && root.trail.length && root.trail[0].name === "My files")
            || (modelData.key === "libraries" && root.view === "folder" && root.trail.length && root.trail[0].name !== "My files")
        width: parent.width + 16; height: 36; radius: theme.radius
        color: sel ? theme.selected : nh.hovered && !modelData.off ? theme.rowHover : "transparent"
        opacity: modelData.off ? 0.45 : 1
        Rectangle { visible: nr.sel; x: -8; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: theme.brand }
        FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: nr.sel && nr.modelData.key === "recent" ? "home-20-filled" : nr.sel && nr.modelData.key === "myfiles" ? "folder-20-filled" : nr.modelData.icon; size: 20; color: nr.sel ? theme.text : theme.textStrong }
        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: nr.modelData.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: nr.sel ? Font.DemiBold : Font.Normal; color: theme.text }
        HoverHandler { id: nh; cursorShape: nr.modelData.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !nr.modelData.off; onTapped: root.open(nr.modelData.key) }
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label + (modelData.off ? " (not available in OST yet)" : "")
    }

    // Content
    Item {
        id: content
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        // Title, or the folder trail.
        Row {
            visible: root.selection.length === 0
            x: 4; y: 30; spacing: 4
            Repeater {
                model: root.view === "folder" ? root.trail : [{ name: root.title }]
                Row {
                    required property var modelData
                    required property int index
                    spacing: 4
                    FluentIcon { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.textSecondary }
                    Text {
                        text: modelData.name
                        font.family: theme.font; font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: index === (root.view === "folder" ? root.trail.length - 1 : 0) ? theme.text : theme.textSecondary
                        HoverHandler { cursorShape: root.view === "folder" && index < root.trail.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: root.view === "folder" && index < root.trail.length - 1; onTapped: root.back(index) }
                    }
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
            x: card.x + card.width + 2; y: 76; width: 304; height: card.height
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
                    if (!it.is_folder) L.push({ label: "Open", icon: root.openIcon(it.kind), chevron: true })
                    if (it.sp_item) L.push({ label: "Share", icon: "share-16" })
                    if (it.sp_item || it.web_url) L.push({ label: "Copy link", icon: "link-16" })
                    if (root.canWrite) L.push({ label: "Delete", icon: "delete-16" })
                } else {
                    if (root.canWrite) L.push({ label: "Delete", icon: "delete-16" })
                    if (root.selection.some(i => !i.is_folder)) L.push({ label: "Add to favorites", icon: "star-16" })
                    L.push({ label: "Download", icon: "arrow-download-16" })
                }
                if (more.length) L.push({ label: "", tip: "More", icon: "more-horizontal-16" })
                return L
            }
            // ···: the rest of the item's menu (Teams: Add to favorites, Add
            // shortcut, Download, Duplicate, Move to, Copy to, Rename, Open in
            // OneDrive, Version history; several: Duplicate, Move to, Copy to).
            readonly property var more: {
                const it = one, L = []
                const sp = root.selection.every(i => !!i.sp_item)
                if (it) {
                    if (!it.is_folder) L.push({ label: fav ? "Remove from favorites" : "Add to favorites", icon: "star-16" })
                    L.push({ label: "Download", icon: "arrow-download-16" })
                }
                if (root.canWrite && sp) L.push({ label: "Duplicate", icon: "add-square-16" })
                if (root.canWrite && sp) L.push({ label: "Move to", icon: "folder-arrow-right-16" })
                if (sp) L.push({ label: "Copy to", icon: "copy-16" })
                if (it && root.canWrite) L.push({ label: "Rename", icon: "rename-16" })
                if (it && it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? "Open in OneDrive" : "Open in SharePoint", icon: "cloud-16" })
                if (it && !it.is_folder && it.sp_item) L.push({ label: "Version history", icon: "history-16" })
                return L
            }
            function run(label) {
                openMenu.close(); moreMenu.close()
                // The menus hang under their buttons: Open's from its left
                // (+4), ···'s right edge 4 inside its own.
                if (label === "Open" && !one) return
                if (label === "Open") { openMenu.x = cmdRow.x + cmds.itemAt(0).x + 4; openMenu.items = actions.itemsFor(one)[0].submenu; openMenu.open(); return }
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
                    label: "Sort"; icon: "arrow-sort-down-lines-16"; chevron: true; tip: "Sort all items by"
                    onClicked: { sortMenu2.items = root.sortMenuItems(); sortMenu2.open() }
                    MenuPopup { id: sortMenu2; fabric: true; fabricWidth: 232; y: parent.height + 10; onPicked: i => root.pickSort(items[i].label) }
                }
                Item { width: countPill.width; height: 32
            // "✕ n selected": clears the selection (0.67 #D1D1D1, radius 20).
            Rectangle {
                id: countPill
                y: 0; height: 32; radius: 16
                width: 36.67 + countText.implicitWidth + 14.67
                color: cph.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : "transparent"
                border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666")
                FluentIcon { x: 12.67; y: 10; name: "dismiss-12"; size: 12; color: root.ink }
                Text { id: countText; x: 36.67; y: 9; text: root.selection.length + " selected"; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selectedIds = [] }
                Accessible.role: Accessible.Button
                Accessible.name: "Clear selection, " + root.selection.length + " selected"
            }
                }
                Item { width: 25; height: 32; Rectangle { x: 12; y: 6; width: 1; height: 20; color: theme.pick("#E0E0E0", "#3D3D3D") } }
                ViewControls { inBar: true }
            }
        }
        Rectangle {
            id: card
            x: 0; y: 76
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
                    required property var modelData
                    width: ListView.view.width; height: 52; radius: theme.radius
                    color: pph.hovered ? theme.rowHover : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: modelData.name }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                        Text { text: modelData.items.length + (modelData.items.length === 1 ? " file" : " files"); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                    }
                    HoverHandler { id: pph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.person = modelData.name }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Files from " + modelData.name
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
                    HeadCell { label: "Name"; width: Math.max(200, parent.parent.width * 0.3) }
                    HeadCell { label: "Date deleted"; width: 150 }
                    HeadCell { label: "Deleted by"; width: 150 }
                    HeadCell { label: "Original location"; width: 220 }
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
                            Item { width: 77; height: parent.height; FluentIcon { anchors.centerIn: parent; name: "document-20"; size: 20; color: theme.textSecondary } }
                            Cell { width: Math.max(200, drow.width * 0.3); text: drow.modelData.name; strong: true }
                            Cell { width: 150; text: root.ago(drow.modelData.deleted) }
                            Cell { width: 150; text: drow.modelData.deleted_by }
                            Cell { width: 220; text: drow.modelData.from }
                        }
                        Rectangle {
                            visible: dh.hovered || dmenu.visible
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: dmh.hovered ? theme.pane : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: dmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: dmenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "More options for " + drow.modelData.name
                            MenuPopup {
                                id: dmenu
                                x: -200; y: parent.height; width: 220
                                items: [{ label: "Restore", icon: "arrow-upload-20" }, { label: "Delete permanently", icon: "delete-20" }]
                                onPicked: i => i === 0 ? root.restore(drow.modelData.id) : root.purge(drow.modelData.id)
                            }
                        }
                        HoverHandler { id: dh }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: "Deleted " + modelData.name
                    }
                }
            }
            // Libraries: cards to open.
            ListView {
                visible: root.view === "libraries"
                anchors.fill: parent; anchors.margins: 8
                model: root.libraries
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width; height: 52; radius: theme.radius
                    color: lh.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "library-20"; size: 20; color: theme.brand }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                        Text { text: modelData.site; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
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
                readonly property real wName: narrow ? Math.max(120, width - 56 - 40 - 189.33) : Math.max(200, width - 56 - 40 - 136 - 136 - 91 - 81 - 119)
                Item {
                    id: head
                    visible: root.listView !== "tiles" || root.view !== "folder"
                    width: parent.width; height: 49
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
                    HoverHandler { id: headHover }
                    // "Select all rows": on hover, or filled once all are picked.
                    Rectangle {
                        readonly property bool all: root.items.length > 0 && root.selection.length === root.items.length
                        visible: headHover.hovered || all
                        x: 29; y: 15.5; width: 18; height: 18; radius: 9
                        color: all ? root.accent : theme.surface
                        border.width: all ? 0 : 1; border.color: root.strong
                        FluentIcon { visible: parent.all; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                        TapHandler { onTapped: root.selectedIds = parent.all ? [] : root.items.map(i => i.id) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Select all rows"
                        Accessible.checked: all
                    }
                    Row {
                        height: parent.height
                        Item { width: 56; height: 49 }
                        Item { width: 40; height: 49; FluentIcon { x: 13.5; y: 16.17; name: "document-16"; size: 16; color: root.ink } }
                        ListHead { label: "Name"; field: root.view === "folder" ? "name" : ""; width: table.wName }
                        ListHead { label: root.view === "recent" ? "Opened" : "Modified"; field: root.view === "folder" ? "modified" : ""; width: table.narrow ? 189.33 : 136 }
                        ListHead { visible: !table.narrow; label: root.view === "shared" ? "Shared by" : "Modified By"; field: root.view === "folder" ? "modified_by" : ""; width: 136 }
                        ListHead { visible: !table.narrow; label: "File size"; field: root.view === "folder" ? "size" : ""; width: 91 }
                        ListHead { visible: !table.narrow; label: "Sharing"; width: 81 }
                        ListHead { visible: !table.narrow; label: "Activity"; width: 119 }
                    }
                }
                ListView {
                    id: files
                    anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: root.shown
                    visible: root.listView !== "tiles" || root.view !== "folder"
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
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
                        width: files.width; height: table.narrow ? 63 : compact ? 34 : 49
                        Rectangle {
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
                            FluentIcon { visible: frow.sel; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
                            TapHandler { onTapped: root.toggle(frow.modelData) }
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: frow.modelData.name
                            Accessible.checked: frow.sel
                        }
                        FluentIcon {
                            x: frow.compact ? 66 : 62; y: frow.compact ? 7 : 8; size: frow.compact ? 20 : 32
                            name: frow.modelData.is_folder ? "ft-folder-32" : root.fileIcon(frow.modelData.kind)
                        }
                        // Name: OneDrive's "New" mark, the name, then ···, Share and the star.
                        Item {
                            id: nameCell
                            x: 96; width: table.wName; height: frow.height
                            readonly property bool tools: frow.hot || frow.sel
                            FluentIcon { id: newMark; visible: !!frow.modelData.is_new; x: 12; y: frow.ty; size: 12; width: 7.92; name: "glimmer-12"; color: root.strong }
                            Text {
                                id: nameText
                                x: newMark.visible ? 19.92 : 12; y: frow.ty
                                width: Math.min(implicitWidth, nameCell.width - x - 8 - (nameCell.tools ? 101 : 0))
                                elide: Text.ElideRight
                                text: frow.modelData.name
                                font.family: theme.font; font.pixelSize: 14; font.weight: frow.sel ? Font.DemiBold : Font.Normal
                                color: root.ink
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: frow.activate() }
                                Accessible.role: Accessible.Link
                                Accessible.name: frow.modelData.name
                            }
                            // Narrow: "Modified by OST Test 1 · 0 items" (12 px #5E5E5D).
                            Text {
                                visible: table.narrow
                                x: 12; y: 35.33; width: nameCell.width - 20
                                elide: Text.ElideRight
                                text: "Modified by " + (frow.modelData.modified_by || root.userName) + " · " + (frow.modelData.is_folder ? root.itemCount(frow.modelData.child_count) : root.size(frow.modelData.size))
                                font.family: theme.font; font.pixelSize: 12; color: theme.pick("#5E5E5D", "#ADADAD")
                            }
                            Row {
                                visible: nameCell.tools
                                x: nameText.x + nameText.width + 8; y: frow.ty - 5; spacing: 4.5
                                RowTool {
                                    id: moreButton
                                    icon: "more-horizontal-16"; tip: "More Actions"
                                    onClicked: actions.popup(frow.modelData, moreButton, 0, moreButton.height)
                                }
                                RowTool { visible: !!frow.modelData.sp_item; icon: "share-16"; tip: "Share"; onClicked: { actions.item = frow.modelData; actions.act("Share") } }
                                RowTool {
                                    visible: !frow.modelData.is_folder
                                    icon: frow.fav ? "star-16-filled" : "star-16"
                                    tip: frow.fav ? "Remove this item from Favorites" : "Add this item to Favorites"
                                    onClicked: root.favorite(frow.modelData.drive_id, frow.modelData.id, !frow.fav)
                                }
                            }
                        }
                        Row {
                            x: 96 + table.wName; height: 49
                            RowCell {
                                ty: frow.ty
                                width: table.narrow ? 189.33 : 136; text: frow.modelData.modified_text || ""
                                tip: frow.modelData.modified_title || ""
                            }
                            RowCell { ty: frow.ty; visible: !table.narrow; width: 136; text: frow.modelData.modified_by || root.userName }
                            RowCell { ty: frow.ty; visible: !table.narrow; width: 91; text: frow.modelData.is_folder ? root.itemCount(frow.modelData.child_count) : root.size(frow.modelData.size) }
                            Item {
                                visible: !table.narrow
                                width: 81; height: 49
                                Row {
                                    x: 12; y: frow.ty + 0.67; spacing: 4
                                    FluentIcon { visible: frow.modelData.sharing === "Shared"; y: 2.5; name: "people-16"; size: 14; color: root.strong }
                                    Text { text: frow.modelData.sharing; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                                }
                            }
                            Item {
                                width: 119; height: 49
                                visible: !!frow.modelData.activity && !table.narrow
                                FluentIcon {
                                    x: 12; y: frow.ty + 1.83; size: 16; color: root.strong
                                    name: frow.modelData.activity ? root.activityIcon(frow.modelData.activity.kind) : ""
                                }
                                Text {
                                    x: 32; y: 15.83; width: parent.width - 32 - 4; height: 16
                                    elide: Text.ElideRight
                                    text: frow.modelData.activity ? frow.modelData.activity.text + " " + frow.modelData.activity.time : ""
                                    font.family: theme.font; font.pixelSize: 12; color: root.ink
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
                        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
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
                text: ({ recent: "Your recent files will show up here", shared: "Files shared with you will show up here",
                         favorites: "Your favorite files will show up here", recycle: "Your recycle bin is empty",
                         meetings: "Files from your meetings will show up here", media: "Your photos and videos will show up here",
                         people: "Files people share with you will show up here" })[root.view] || "This folder is empty"
                font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                color: theme.text
            }
            Text {
                visible: !!root.driveData.error
                anchors.centerIn: parent
                text: root.driveData.error || ""
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.danger
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
            label: "Sort"; icon: "arrow-sort-down-lines-16"; chevron: true; tip: "Sort all items by"
            onClicked: { sortMenu.items = root.sortMenuItems(); sortMenu.open() }
            MenuPopup { id: sortMenu; fabric: true; fabricWidth: 232; y: parent.height + 10; onPicked: i => root.pickSort(items[i].label) }
        }
        BarCommand {
            icon: root.listView === "tiles" ? "grid-16" : root.listView === "compact" ? "text-align-left-16" : "list-16"
            chevron: true; tip: "Switch view options"
            onClicked: viewMenu.open()
            MenuPopup {
                id: viewMenu; fabric: true; fabricWidth: 232; y: parent.height + 10
                items: root.viewItems
                onPicked: i => root.listView = ["list", "compact", "tiles"][i]
            }
        }
        BarCommand {
            label: "Details"; icon: "panel-right-16"; tip: "Open the details pane"
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
            visible: tile.hot
            x: parent.width - 30; y: 12; width: 18; height: 18; radius: 9
            color: tile.sel ? root.accent : theme.surface
            border.width: tile.sel ? 0 : 1; border.color: root.strong
            FluentIcon { visible: tile.sel; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: "white" }
            TapHandler { onTapped: root.toggle(tile.modelData) }
            Accessible.role: Accessible.CheckBox
            Accessible.name: tile.modelData.name
            Accessible.checked: tile.sel
        }
        // A folder: the art and its count.
        Item {
            visible: tile.modelData.is_folder
            x: 32; y: 24; width: 112; height: 80; clip: true
            FluentIcon { x: 0; y: -16; size: 112; name: "ft-folder-32" }
            Text { x: 14; y: 56; text: tile.modelData.child_count || 0; font.family: theme.font; font.pixelSize: 14; color: "#8F3900" }
        }
        // A file: its picture (or type icon) with the app's badge.
        Rectangle {
            visible: !tile.modelData.is_folder
            x: 51; y: 16; width: 74; height: 96; radius: 4
            color: theme.surface
            border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
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
                x: 6; y: parent.height - 30; width: 24; height: 24; radius: 4; color: "white"
                border.width: 0.67; border.color: "#E0E0E0"
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
        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
        Accessible.selected: sel
    }
    // The table's header cell: 14/600 #616161 at 10.67, 49 tall. A sortable
    // column shows ↑ / ↓ when sorted and a chevron; a click opens its menu
    // (Ascending, Descending).
    component ListHead: Item {
        id: lh
        property string label
        property string field: ""
        height: 49
        Row {
            x: 10.67; y: 14.83; spacing: 6
            Text { text: lh.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
            FluentIcon { visible: !!lh.field && root.sortField === lh.field; y: 3; size: 12; name: root.sortAsc ? "arrow-up-12" : "arrow-down-12"; color: theme.pick("#605E5C", "#D6D6D6") }
            FluentIcon { visible: !!lh.field; y: 4; size: 10; name: "chevron-down-12"; color: theme.pick("#605E5C", "#D6D6D6") }
        }
        HoverHandler { enabled: !!lh.field; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !!lh.field; onTapped: headMenu.open() }
        MenuPopup {
            id: headMenu
            fabric: true; fabricWidth: 232
            x: 2; y: 46
            items: [{ label: "Ascending", checked: root.sortField === lh.field && root.sortAsc }, { label: "Descending", checked: root.sortField === lh.field && !root.sortAsc }]
            onPicked: i => { root.sortField = lh.field; root.sortAsc = i === 0 }
        }
        Accessible.role: lh.field ? Accessible.Button : Accessible.ColumnHeader
        Accessible.name: label + (root.sortField === field && field ? (root.sortAsc ? ", sorted ascending" : ", sorted descending") : "")
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
        color: bc.pressed ? theme.pick("#EBEBEB", "#3D3D3D") : bch.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : "transparent"
        FluentIcon { x: 8; y: 8; name: bc.icon; size: 16; color: bc.icon.startsWith("ft-") ? "#212121" : root.ink }
        Text { id: bcText; visible: !!bc.label; x: 32; y: 9; text: bc.label; font.family: theme.font; font.pixelSize: 14; color: root.ink }
        FluentIcon { visible: bc.chevron; x: bcText.x + bcText.implicitWidth + 6; y: 10; name: "chevron-down-12"; size: 12; color: root.ink }
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
        color: rth2.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : "transparent"
        FluentIcon { anchors.centerIn: parent; name: rtool.icon; size: 16; color: theme.pick("#605E5C", "#D6D6D6") }
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
        title: "Upload files"
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
            Text { text: "Create a folder"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
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
                    Text { visible: !folderName.text; text: "Enter your folder name"; color: theme.textTertiary; font: folderName.font }
                    Accessible.name: "Folder name"
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 90; height: 32; radius: theme.radius
                    color: theme.brandFill
                    Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: folderName.createFolder() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Create"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius
                    color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: folderDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
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
    function previewStepForTest(d) { viewer.step(d) }
    function previewCloseForTest() { viewer.close() }

    // Test harness hooks
    /// Show row `i` as hovered (grabToImage has no pointer).
    property int hoverForTest: -1
    function selectForTest(names) { selectedIds = items.filter(i => names.indexOf(i.name) >= 0).map(i => i.id); return selectedIds.length }
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
