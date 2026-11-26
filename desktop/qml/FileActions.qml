import QtQuick
import QtQuick.Controls.Basic

// A Files item's actions as Teams' OneDrive app and channel Files show
// them (OneDrive's own pages in Teams; measured on winpc 2026-11-11,
// docs/spec/file-actions.md): the right-click / ··· menu, Rename, the
// Delete? question, Copy link's "Link created", Move to / Copy to,
// Duplicate, and the notices under the list. Fills its view; the view
// does the deleting, favorites and downloads it asks for.
Item {
    id: root
    /// Ids of your favorites (the menu offers Add to or Remove from).
    property var favoriteIds: []
    /// The folder shown ({drive_id, item_id}; both empty for My files'
    /// top), so Move to can't pick where the item already is.
    property var folder: ({ drive_id: "", item_id: "" })
    /// Items here can be renamed, moved and deleted.
    property bool canWrite: true
    signal changed()
    signal deleteItem(var item)
    signal favoriteItem(var item, bool on)
    signal downloadItem(var item)
    /// Details: the list opens its Details pane for the item.
    signal detailsItem(var item)
    /// Preview: the list shows its viewer for the item.
    signal previewItem(var item)

    /// This view's tag on backend replies.
    readonly property string tag: "fa" + Math.floor(Math.random() * 1e9) + ":"
    /// Rename offers Copilot's Suggested names with a Copilot licence.
    readonly property bool renameSuggestions: {
        try { return !!JSON.parse(backend.composeCopilotJson || "{}").rename } catch (e) { return false }
    }
    property var item: null
    readonly property bool menuOpen: menu.opened

    // OneDrive's colours (Fluent, as its pages in Teams draw them).
    readonly property color ink: theme.pick("#616161", "#D6D6D6", "#FFFFFF")
    readonly property color strong: theme.pick("#424242", "#D6D6D6")
    readonly property color accent: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color line: theme.pick("#D1D1D1", "#666666")

    readonly property var textKinds: ["txt", "md", "json", "xml", "log", "csv", "css", "js", "ts", "html", "htm", "yaml", "yml", "ini", "cfg"]
    readonly property var videoKinds: ["mp4", "mov", "m4v", "wmv", "avi", "webm", "mkv", "mpg", "mpeg", "3gp", "mts", "m2ts", "ts", "asf"]
    readonly property var officeKinds: ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "vsdx", "one"]

    /// Open the menu for `it` at (x, y) in `source`'s coordinates.
    function popup(it, source, x, y) {
        item = it; others = []
        menu.items = itemsFor(it)
        const p = source.mapToItem(root, x, y)
        menu.x = Math.max(0, Math.min(p.x, root.width - menu.width))
        menu.y = Math.max(0, Math.min(p.y, root.height - menu.implicitHeight))
        menu.open()
    }
    function ref(it) { return { site: it.sp_site, list: it.sp_list, item: it.sp_item } }
    /// Copy link straight to "Link copied" (a message's file card).
    function copyLinkNow(it) { copyLink.auto = true; copyLink.start(it) }
    function closeCopyLinkForTest() { copyLink.close() }
    function copyLinkStateForTest() { return { open: copyLink.opened, copied: copyLink.copied, url: copyLink.url, sentence: copyLink.sentence, kind: copyLink.kind, shareId: copyLink.shareId } }
    function itemsFor(it) {
        const sp = !!it.sp_item
        const fav = root.favoriteIds.indexOf(it.id) >= 0
        const L = []
        if (!it.is_folder) {
            const text = textKinds.indexOf(it.kind) >= 0
            L.push({ label: qsTr("Open"), icon: "open-16", submenu: [
                text ? { label: qsTr("Open in Text Editor"), icon: "edit-16" } : { label: qsTr("Open in browser"), icon: "globe-16" },
                { label: qsTr("Open in app"), icon: "open-16" }] })
            L.push({ label: qsTr("Preview"), icon: "full-screen-maximize-16" })
        }
        if (sp) L.push({ label: qsTr("Share"), icon: "share-16" })
        if (sp || it.web_url) L.push({ label: qsTr("Copy link"), icon: "link-16" })
        if (sp && it.is_folder && canWrite) L.push({ label: qsTr("Request files"), icon: "folder-arrow-up-16" })
        if (sp) L.push({ label: qsTr("Manage access"), icon: "person-16" })
        L.push({ separator: true })
        if (canWrite) L.push({ label: qsTr("Delete"), icon: "delete-16" })
        // Graph's favorites (followed items) hold files, not folders.
        if (!it.is_folder) L.push({ label: fav ? qsTr("Remove from favorites") : qsTr("Add to favorites"), icon: "star-16" })
        if (!it.is_folder && sp) L.push({ label: qsTr("Add shortcut"), icon: "link-square-16", submenu: [{ label: qsTr("Shortcuts") }, { label: qsTr("My files") }, { label: qsTr("Other locations") }] })
        L.push({ label: qsTr("Download"), icon: "arrow-download-16" })
        if (canWrite) L.push({ label: qsTr("Rename"), icon: "rename-16" })
        // A team site's file opens in SharePoint (not yet seen in Teams).
        if (it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? qsTr("Open in OneDrive") : qsTr("Open in SharePoint"), icon: "cloud-16" })
        if (canWrite && sp) L.push({ label: qsTr("Move to"), icon: "folder-arrow-right-16" })
        if (sp) L.push({ label: qsTr("Copy to"), icon: "copy-16" })
        if (canWrite && sp) L.push({ label: qsTr("Duplicate"), icon: "add-square-16" })
        // A video: Add to playlist (Stream playlists), after Duplicate.
        if (!it.is_folder && sp && videoKinds.indexOf(String(it.kind || "").toLowerCase()) >= 0) L.push({ label: qsTr("Add to playlist"), icon: "video-clip-multiple-16" })
        if (canWrite && sp && it.is_folder) L.push({ label: qsTr("Folder color"), icon: "paint-bucket-16", flyout: true, dot: colorFor(it.folder_color).hex })
        if (!it.is_folder && sp) { L.push({ separator: true }); L.push({ label: qsTr("Version history"), icon: "history-16" }) }
        if (sp) { L.push({ separator: true }); L.push({ label: qsTr("Details"), icon: "info-16" }) }
        while (L.length && L[L.length - 1].separator) L.pop()
        return L
    }
    /// The action a menu label stands for: its English name. The menu's
    /// labels are translated; callers pass either (act("Delete")).
    function keyOf(label) {
        const names = { "Open": qsTr("Open"), "Open in Text Editor": qsTr("Open in Text Editor"), "Open in browser": qsTr("Open in browser"),
                        "Open in app": qsTr("Open in app"), "Preview": qsTr("Preview"), "Share": qsTr("Share"), "Copy link": qsTr("Copy link"),
                        "Request files": qsTr("Request files"), "Manage access": qsTr("Manage access"), "Delete": qsTr("Delete"),
                        "Remove from favorites": qsTr("Remove from favorites"), "Add to favorites": qsTr("Add to favorites"),
                        "Add shortcut": qsTr("Add shortcut"), "Shortcuts": qsTr("Shortcuts"), "My files": qsTr("My files"),
                        "Other locations": qsTr("Other locations"), "Download": qsTr("Download"), "Rename": qsTr("Rename"),
                        "Open in OneDrive": qsTr("Open in OneDrive"), "Open in SharePoint": qsTr("Open in SharePoint"),
                        "Move to": qsTr("Move to"), "Copy to": qsTr("Copy to"), "Duplicate": qsTr("Duplicate"),
                        "Folder color": qsTr("Folder color"), "Version history": qsTr("Version history"), "Details": qsTr("Details"),
                        "Add to playlist": qsTr("Add to playlist") }
        if (names[label] !== undefined) return label
        for (const k in names) if (names[k] === label) return k
        return label
    }
    /// OneDrive's counted wording: "{0} item||{0} items" (%1 here).
    function count(n, one, many) { return (n === 1 ? one : many).arg(n) }
    /// Items acted on together (the selection), besides `item`.
    property var others: []
    /// How many the running job covers, for its notice.
    property int jobCount: 1
    /// The selection toolbar's actions on several items (Teams: Delete, Add
    /// to favorites, Download, then Duplicate, Move to and Copy to).
    function actMany(list, label) {
        label = keyOf(label); if (!list.length) return
        if (list.length === 1) { item = list[0]; others = []; act(label); return }
        item = list[0]; others = list.slice(1)
        if (label === "Delete") deleteDialog.openForMany(list)
        else if (label === "Add to favorites") list.filter(i => !i.is_folder).forEach(i => favoriteItem(i, true))
        else if (label === "Download") zip(list)
        else if (label === "Move to") { picker.shortcut = false; picker.openFor(item, true) }
        else if (label === "Copy to") { picker.shortcut = false; picker.openFor(item, false) }
        else if (label === "Duplicate") {
            jobCount = list.length
            notice("progress", count(jobCount, qsTr("Copying %1 item"), qsTr("Copying %1 items")))
            backend.driveAction(tag + "duplicate", JSON.stringify(item), JSON.stringify({ more: others }))
        }
    }
    /// A folder, or several items: OneDrive's zip (docs/spec/zip-download.md).
    /// Quick access (Teams': pinned libraries, then the ones used lately),
    /// shared by the OneDrive pane and the picker; pin / unpin with
    /// OneDrive's notices ("Updating {0}", "Pinned {0} to Quick access").
    property var quickAccess: []
    property var pendingPin: null
    function loadQuickAccess() { backend.driveAction(tag + "quick_access", "{}", "{}") }
    function pinLibrary(lib, pin) {
        pendingPin = { title: lib.title || lib.label, pin: pin }
        notice("progress", qsTr("Updating %1").arg(lib.title || lib.label))
        backend.driveAction(tag + "quick_pin", "{}", JSON.stringify({ lib: lib, pin: pin }))
    }
    // Add shortcut: OneDrive's "Added {0} as a shortcut to {1}."
    property var pendingShortcut: null
    function addShortcut(it, place, placeName, extra) {
        pendingShortcut = { name: it.name, place: placeName }
        backend.driveAction(tag + "shortcut", JSON.stringify(it), JSON.stringify(Object.assign({ place: place }, extra)))
    }
    property int zipCount: 0
    property string lastZip: ""
    function zip(list) {
        // OneDrive's names: the one item's, else OneDrive_{n}_{M-D-YYYY}.zip.
        const d = new Date()
        const name = list.length === 1 ? list[0].name + ".zip" : "OneDrive_" + (++zipCount) + "_" + (d.getMonth() + 1) + "-" + d.getDate() + "-" + d.getFullYear() + ".zip"
        lastZip = name
        notice("progress", qsTr("Preparing %1 for download. This can take a moment.").arg(name))
        backend.driveAction(tag + "zip", JSON.stringify(list[0]), JSON.stringify({ more: list.slice(1), name: name }))
    }
    // Folder color ▸: OneDrive's 4 x 4 grid of 24 px colours (40 apart, in
    // a 164 x 160 card), the current one ringed.
    Popup {
        id: colorPicker
        width: 164; height: 160; padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
        contentItem: Item {
            Repeater {
                model: root.folderColors
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: root.item && String(root.item.folder_color || "0") === modelData.code
                    x: 10 + (index % 4) * 40 - 3; y: 8 + Math.floor(index / 4) * 40 - 3
                    width: 30; height: 30; radius: 15
                    color: "transparent"
                    border.width: current ? 2 : 0; border.color: theme.pick("#0F6CBD", "#479EF5", "#FFFFFF")
                    Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: parent.modelData.hex }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            colorPicker.close(); menu.close()
                            backend.driveAction(root.tag + "folder_color", JSON.stringify(root.item), JSON.stringify({ code: parent.modelData.code }))
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: current ? qsTr("%1 selected").arg(modelData.name) : modelData.name
                }
            }
        }
    }

    function act(label) {
        label = keyOf(label); const it = root.item
        if (!it) return
        if (label === "Open in Text Editor" || label === "Open in browser" || label === "Open in OneDrive" || label === "Open in SharePoint") Qt.openUrlExternally(it.web_url)
        else if (label === "Open in app") { notice("progress", qsTr("Opening %1").arg(it.name)); backend.driveAction(tag + "open_app", JSON.stringify(it), "{}") }
        else if (label === "Share") share.openFor(ref(it), it.name, it.kind)
        else if (label === "Manage access") share.openManage(ref(it), it.name, it.kind)
        else if (label === "Copy link") { copyLink.auto = false; copyLink.start(it) }
        else if (label === "Delete") deleteDialog.openFor(it)
        else if (label === "Add to favorites") favoriteItem(it, true)
        else if (label === "Remove from favorites") favoriteItem(it, false)
        else if (label === "Download") it.is_folder ? zip([it]) : downloadItem(it)
        else if (label === "Rename") renameDialog.openFor(it)
        else if (label === "Move to") { picker.shortcut = false; picker.openFor(it, true) }
        else if (label === "Copy to") { picker.shortcut = false; picker.openFor(it, false) }
        else if (label === "Version history") versions.openFor(it)
        else if (label === "Request files") fileRequest.openFor(it)
        else if (label === "Shortcuts") addShortcut(it, "shortcuts", qsTr("Shortcuts"), {})
        else if (label === "My files") addShortcut(it, "myfiles", qsTr("My files"), {})
        else if (label === "Other locations") { picker.shortcut = true; picker.openFor(it, false) }
        else if (label === "Details") detailsItem(it)
        else if (label === "Preview") previewItem(it)
        else if (label === "Add to playlist") playlists.openFor(it)
        else if (label === "Duplicate") { jobCount = 1; notice("progress", qsTr("Copying %1 item").arg(1)); backend.driveAction(tag + "duplicate", JSON.stringify(it), "{}") }
    }

    // The clipboard, without OST's own "Copied to clipboard" notice
    // (OneDrive says "Link copied" itself).
    TextEdit { id: copier; visible: false }
    function copy(text) { copier.text = text; copier.selectAll(); copier.copy() }

    // OneDrive's sixteen folder colours (Theme.folderColors).
    readonly property var folderColors: theme.folderColors
    function colorFor(code) { return folderColors.find(c => c.code === String(code || "0")) || folderColors[0] }

    MenuPopup {
        id: menu
        fabric: true
        onFlyoutRequested: (i, row) => {
            if (i < 0 || !row || items[i].label !== qsTr("Folder color")) { colorPicker.close(); return }
            const p = row.mapToItem(root, 0, 0)
            colorPicker.x = Math.max(0, p.x - 4 - 164)
            colorPicker.y = Math.max(0, Math.min(p.y + row.height - 160 + 2, root.height - 160))
            colorPicker.open()
        }
        onPicked: i => root.act(items[i].label)
        onSubPicked: (i, j) => root.act(items[i].submenu[j].label)
    }

    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.tag)) return
            const kind = op.slice(root.tag.length)
            const v = result ? JSON.parse(result) : null
            // The picker numbers its requests ("<n>:<op>"): an answer to an
            // older one is dropped.
            const m = /^(\d+):(.*)$/.exec(kind)
            if (m) { if (Number(m[1]) === picker.seq) picker.reply(m[2], v, error); return }
            if (kind === "playlists" || kind === "playlist_create" || kind === "playlist_add") { playlists.reply(kind, v, error); return }
            if (kind === "pic:location_picture") { if (v && v.web) { const m = Object.assign({}, picker.locationPics); m[v.web] = v; picker.locationPics = m } return }
            if (kind === "people:picker_people") { if (v && v.query === picker.peopleQuery) { picker.peopleFound = v.people || []; picker.peopleLoading = false } else if (error) picker.peopleLoading = false; return }
            const rs = /^r(\d+):(.*)$/.exec(kind)
            if (rs) { renameDialog.suggReply(Number(rs[1]), rs[2], v, error); return }
            if (kind === "libraries") { picker.reply(kind, v, error); return }
            if (kind === "thumb") { if (!error && v && v.path) { const t = Object.assign({}, picker.thumbs); t[v.id] = v.path; picker.thumbs = t } return }
            if (kind === "quick_access") { if (!error) root.quickAccess = v || []; return }
            if (kind === "quick_pin") {
                const p = root.pendingPin || { title: "", pin: true }
                if (error) root.notice("error", (p.pin ? qsTr("%1 wasn't pinned") : qsTr("%1 wasn't unpinned")).arg(p.title), error)
                else { root.quickAccess = v.items || root.quickAccess; root.notice("done", (p.pin ? qsTr("Pinned %1 to Quick access") : qsTr("Unpinned %1 from Quick access")).arg(p.title)) }
                return
            }
            if (kind === "versions" || kind === "restore_version" || kind === "delete_version") { versions.reply(kind, v, error); return }
            if (kind === "shortcut") {
                const p = root.pendingShortcut || { name: "", place: "" }
                if (error) root.notice("error", qsTr("Something went wrong so we couldn't add %1 as a shortcut to %2. %3").arg(p.name).arg(p.place).arg("").trim(), error)
                else root.notice("done", qsTr("Added %1 as a shortcut to %2.").arg(p.name).arg(p.place))
                return
            }
            if (kind === "folder_color") {
                if (error) root.notice("error", qsTr("The folder color wasn't changed"), error)
                else root.changed()
                return
            }
            if (kind === "file_request") { fileRequest.reply(kind, v, error); return }
            if (kind === "zip") {
                if (error) root.notice("error", qsTr("Couldn't download %1. Try again.").arg(root.lastZip), error)
                else root.notice("done", qsTr("%1 was downloaded.").arg(v.name))
                return
            }
            if (kind === "open_app") {
                if (error) root.notice("error", qsTr("The file couldn't be opened"), error)
                else { toast.visible = false; Qt.openUrlExternally("file://" + v.path) }
                return
            }
            // OneDrive's strings: "Moved {0} item||Moved {0} items", "{0} item
            // wasn't moved||{0} items weren't moved", and so on.
            const n = kind === "rename" ? 1 : root.jobCount
            const words = { rename: [qsTr("Renamed %1 item"), qsTr("Renamed %1 items"), qsTr("%1 item wasn't renamed"), qsTr("%1 items weren't renamed")],
                            move: [qsTr("Moved %1 item"), qsTr("Moved %1 items"), qsTr("%1 item wasn't moved"), qsTr("%1 items weren't moved")],
                            copy: [qsTr("Copied %1 item"), qsTr("Copied %1 items"), qsTr("%1 item wasn't copied"), qsTr("%1 items weren't copied")],
                            duplicate: [qsTr("Copied %1 item"), qsTr("Copied %1 items"), qsTr("%1 item wasn't copied"), qsTr("%1 items weren't copied")] }[kind]
            if (!words) return
            if (error) root.notice("error", root.count(n, words[2], words[3]), error)
            else { root.notice("done", root.count(n, words[0], words[1])); root.changed() }
        }
    }

    // OneDrive's notice under the list: 390 wide, #292929, radius 4,
    // padding 12; a 20 px state glyph, the text (13/17 #F0F0F0) at 48 and
    // a 24 px dismiss; 23 above the view's bottom.
    function notice(state, title, detail, link, linkUrl) {
        toast.state2 = state; toast.title = title; toast.detail = detail || ""
        toast.link = link || ""; toast.linkUrl = linkUrl || ""
        toast.visible = true
        hideTimer.restart()
    }
    Rectangle {
        id: toast
        property string state2: "done"
        property string title
        property string detail
        /// An action under the words (Add to playlist's "View").
        property string link
        property string linkUrl
        visible: false
        z: 10
        width: 390; height: Math.max(48, toastText.implicitHeight + 24)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 23 - height
        radius: 4; color: theme.hc("#292929", "#000000")
        FluentIcon {
            x: 12; y: 14; size: 20
            name: toast.state2 === "error" ? "dismiss-circle-20-filled" : toast.state2 === "progress" ? "arrow-sync-20" : "checkmark-circle-20-filled"
            color: toast.state2 === "error" ? theme.hc("#F1707B", "#FFFFFF") : toast.state2 === "progress" ? theme.hc("#F0F0F0", "#FFFFFF") : theme.hc("#92C353", "#FFFFFF")
        }
        Column {
            id: toastText
            x: 48; y: 12; width: 294
            topPadding: 3.5
            Text { width: parent.width; wrapMode: Text.Wrap; text: toast.title; font.family: theme.font; font.pixelSize: 13; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: theme.hc("#F0F0F0", "#FFFFFF") }
            Text { visible: !!toast.detail; width: parent.width; topPadding: 4; wrapMode: Text.Wrap; text: toast.detail; font.family: theme.font; font.pixelSize: 13; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: theme.hc("#F0F0F0", "#FFFFFF") }
            Text {
                visible: !!toast.link
                topPadding: 4
                text: toast.link
                font.family: theme.font; font.pixelSize: 13; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: theme.hc("#7F85F5", "#1AEBFF")
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { if (toast.linkUrl) Qt.openUrlExternally(toast.linkUrl); toast.visible = false } }
                Accessible.role: Accessible.Link
                Accessible.name: text
            }
        }
        Rectangle {
            id: hcFill1
            anchors.right: parent.right; anchors.rightMargin: 12; y: 12
            width: 24; height: 24; radius: 4
            color: dth.hovered ? theme.hc("#3D3D3D", "#1AEBFF") : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 14; color: theme.onFill(hcFill1, theme.hc("#7F85F5", "#FFFFFF")) }
            HoverHandler { id: dth; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: toast.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Dismiss notification")
        }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: title + (detail ? ". " + detail : "")
    }
    // Done notices go after a while; errors and work in progress stay.
    Timer { id: hideTimer; interval: 5000; onTriggered: if (toast.state2 === "done") toast.visible = false }

    // OneDrive's question / form dialog: 440 wide, padding 24, radius 8;
    // the title 20/28 600 with a 32 px Close; two 80 x 32 buttons at the
    // bottom right, 8 apart.
    component OdspDialog: Popup {
        id: dlg
        property string title
        property string okText
        property bool okEnabled: true
        default property alias body: bodyArea.data
        property real bodyHeight: 0
        signal accepted()
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 0
        width: 440; height: 24 + 31.33 + bodyHeight + 32 + 24
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Item {
        Text {
            x: 24; y: 24; width: 350.67; height: 31.33
            text: dlg.title; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: root.ink
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: hcFill2
            x: parent.width - 24 - 32; y: 24; width: 32; height: 31.33; radius: 4
            color: dch.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill2, root.strong) }
            HoverHandler { id: dch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Item { id: bodyArea; x: 24; y: 24 + 31.33; width: 392; height: dlg.bodyHeight }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24
            y: parent.height - 24 - 32
            spacing: 8
            OdspButton { label: dlg.okText; enabled2: dlg.okEnabled; onClicked: dlg.accepted() }
            OdspButton { label: qsTr("Cancel"); onClicked: dlg.close() }
        }
        }
    }
    // Version history (OneDrive's): 70% of the window wide at most 848.4,
    // padding 24, radius 8; "Version history" 20/28 600 and Close; the
    // versions on a 316 tall white card (radius 4, shadow 4): Version 100,
    // then Modified, Size and Modified By at 40/20/40 of the rest; header
    // 46 tall (12/20 600, a 2 px #F0F0F0 line), rows 46 (14/20), #EBEBEB on
    // hover with a 28 px ··· after the label: Open File, and for older
    // versions Restore and Delete Version (both at once, no question).
    Popup {
        id: versions
        property var target: null
        property var list: []
        property bool loading: false
        property string error: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 0
        width: Math.min(848.4, (Overlay.overlay ? Overlay.overlay.width : 1212) * 0.7)
        height: 24 + 31.33 + 8.33 + 316 + 2 + 31
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        function openFor(it) { target = it; list = []; error = ""; open(); load() }
        function load() { loading = true; backend.driveAction(root.tag + "versions", JSON.stringify(target), "{}") }
        function reply(kind, v, err) {
            if (kind === "versions") { loading = false; error = err || ""; list = err ? [] : (v || []); return }
            if (err) { root.notice("error", kind === "restore_version" ? qsTr("The version wasn't restored") : qsTr("The version wasn't deleted"), err); return }
            load(); root.changed()
        }
        function run(ver, label) {
            if (label === "Open File") Qt.openUrlExternally(ver.url)
            else if (label === "Restore") backend.driveAction(root.tag + "restore_version", JSON.stringify(target), JSON.stringify({ label: ver.label }))
            else if (label === "Delete Version") backend.driveAction(root.tag + "delete_version", JSON.stringify(target), JSON.stringify({ label: ver.label }))
        }
        contentItem: Item {
            Text {
                x: 24; y: 24; width: parent.width - 48 - 40; height: 31.33
                text: qsTr("Version history")
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: root.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Rectangle {
                id: hcFill3
                x: parent.width - 24 - 32; y: 24; width: 32; height: 31.33; radius: 4
                color: vch.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill3, root.strong) }
                HoverHandler { id: vch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: versions.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
            }
            FluentSurface {
                id: vcard
                x: 24; y: 24 + 31.33 + 8.33 + 2; width: parent.width - 48; height: 316
                depth: 4; radius: 4; color: theme.surface
                readonly property real rest: width - 100
                readonly property var cols: [100, rest * 0.4, rest * 0.2, rest * 0.4]
                Item {
                    width: parent.width; height: 46
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.pick("#F0F0F0", "#3D3D3D", "#000000") }
                    Row {
                        Repeater {
                            model: [qsTr("Version"), qsTr("Modified"), qsTr("Size"), qsTr("Modified By")]
                            Item {
                                required property string modelData
                                required property int index
                                width: vcard.cols[index]; height: 46
                                Text { x: index === 0 ? 20 : 8; y: 13; text: modelData; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.ink }
                            }
                        }
                    }
                }
                ListView {
                    id: vlist
                    y: 46; width: parent.width; height: parent.height - 46
                    clip: true
                    model: versions.list
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: vrow
                        required property var modelData
                        width: vlist.width; height: 46
                        readonly property bool hot: vrh.hovered || vmenu.opened
                        color: hot ? theme.rowHover : "transparent"
                        readonly property color cell: theme.pick("#5E5E5D", "#D6D6D6")
                        // The label opens that version.
                        Text {
                            id: vlabel
                            x: 20; anchors.verticalCenter: parent.verticalCenter
                            text: vrow.modelData.label
                            font.family: theme.font; font.pixelSize: 16; color: theme.onFill(vrow, root.ink)
                            font.underline: vlh.hovered
                            HoverHandler { id: vlh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: versions.run(vrow.modelData, "Open File") }
                            Accessible.role: Accessible.Link
                            Accessible.name: qsTr("Version %1").arg(vrow.modelData.label)
                        }
                        Rectangle {
                            id: vmore
                            visible: vrow.hot
                            x: 63; y: 9; width: 28; height: 28; radius: 2
                            color: vmh.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-16"; size: 16; color: theme.onFill(vmore, theme.pick("#605E5C", "#D6D6D6", "#FFFFFF")) }
                            HoverHandler { id: vmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: vmenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Show more actions for this item")
                            MenuPopup {
                                id: vmenu
                                fabric: true; fabricWidth: 232
                                x: 3.5; y: parent.height + 4
                                items: vrow.modelData.current ? [{ key: "Open File", label: qsTr("Open File"), icon: "open-16" }]
                                    : [{ key: "Open File", label: qsTr("Open File"), icon: "open-16" }, { key: "Restore", label: qsTr("Restore"), icon: "arrow-undo-16" }, { key: "Delete Version", label: qsTr("Delete Version"), icon: "delete-16" }]
                                onPicked: i => versions.run(vrow.modelData, items[i].key)
                            }
                        }
                        Row {
                            x: 100; height: parent.height
                            Text { width: vcard.cols[1]; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.modified; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(vrow, vrow.cell) }
                            Text { width: vcard.cols[2]; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.size; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(vrow, vrow.cell) }
                            Item {
                                width: vcard.cols[3]; height: 46
                                Avatar { x: 8; y: 11; size: 24; name: vrow.modelData.by; photoId: vrow.modelData.by_oid }
                                Text { x: 48; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.by; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(vrow, vrow.cell) }
                            }
                        }
                        HoverHandler { id: vrh }
                        Accessible.role: Accessible.Row
                        Accessible.name: qsTr("Version %1").arg(modelData.label) + ", " + modelData.modified + ", " + modelData.size + ", " + modelData.by
                    }
                }
                BusyIndicator { anchors.centerIn: parent; running: versions.loading; visible: versions.loading }
                Text {
                    visible: !!versions.error
                    anchors.centerIn: parent; width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: versions.error
                    font.family: theme.font; font.pixelSize: 14; color: theme.danger
                }
            }
        }
    }
    // Request files (a folder's), OneDrive's two steps (600 wide, padding
    // 24, radius 8): "Request files for this folder" with the description
    // (Next / Cancel), then "Send file request": the upload link with Copy
    // link, "Anyone with the link can upload files", and "Or you can send it
    // via email" (To, Message; Done, or Send once someone is picked).
    Popup {
        id: fileRequest
        property var target: null
        property int step: 1
        property string url: ""
        property string shareId: ""
        property bool busy: false
        property bool tried: false
        property bool copied: false
        property var picked: []
        property var found: []
        property string query: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 24
        width: 600
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        function openFor(it) {
            target = it; step = 1; url = ""; shareId = ""; busy = false; tried = false; copied = false; picked = []; found = []; query = ""
            frName.text = ""; frMessage.text = ""; frTo.text = ""
            open(); frName.forceActiveFocus()
        }
        function next() {
            tried = true
            if (!frName.text.trim() || busy) return
            busy = true
            backend.driveAction(root.tag + "file_request", JSON.stringify(target), JSON.stringify({ description: frName.text.trim() }))
        }
        function send() {
            if (busy) return
            busy = true
            backend.driveAction(root.tag + "file_request", JSON.stringify(target), JSON.stringify({ description: frName.text.trim(), people: picked, message: frMessage.text }))
        }
        function reply(kind, v, error) {
            busy = false
            if (error) { root.notice("error", step === 1 ? qsTr("Something went wrong, please try again") : qsTr("Send file request email failed."), error); return }
            if (v.sent) { close(); frDone.show(true); return }
            url = v.url; shareId = v.share_id; step = 2
        }
        function search(q) {
            query = q
            if (q.trim().length < 1) { found = []; return }
            backend.shareAction(root.tag + "frpeople", JSON.stringify(root.ref(target)), JSON.stringify({ query: q }))
        }
        Connections {
            target: backend
            function onShareDone(op, result, error) {
                if (op !== root.tag + "frpeople" || error) return
                const v = JSON.parse(result)
                if (v.query === fileRequest.query) fileRequest.found = v.people || []
            }
        }
        contentItem: Column {
            spacing: 0
            Text {
                width: parent.width; height: 28
                text: fileRequest.step === 1 ? qsTr("Request files for this folder") : qsTr("Send file request")
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.Medium; color: root.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            // Step 1: the description.
            Column {
                visible: fileRequest.step === 1
                width: parent.width; topPadding: 34; spacing: 0
                Row {
                    spacing: 9; height: 23
                    FluentIcon { y: 3; size: 14; name: "folder-arrow-up-16"; color: root.ink }
                    Text { text: qsTr("Let the recipients know which files you're requesting."); font.family: theme.font; font.pixelSize: 14; color: root.ink }
                }
                Item { width: 1; height: 9 }
                Rectangle {
                    width: parent.width; height: 32; radius: 4
                    color: theme.surface; border.width: 0.67; border.color: root.line
                    Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: frName.activeFocus ? 2 : 0.67; color: frName.activeFocus ? root.accent : root.strong }
                    TextInput {
                        id: frName
                        x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                        Keys.onReturnPressed: fileRequest.next()
                        Text { visible: !frName.text; text: qsTr("Enter a description"); color: theme.textTertiary; font: frName.font }
                        Accessible.name: qsTr("Let the recipients know which files you're requesting.")
                    }
                }
                Row {
                    visible: fileRequest.tried && !frName.text.trim()
                    spacing: 4; height: 18
                    FluentIcon { y: 2; size: 12; name: "error-circle-12"; color: theme.hc("#BC2F32", "#FFFFFF") }
                    Text { text: qsTr("Please type a name for the request."); font.family: theme.font; font.pixelSize: 12; color: theme.hc("#BC2F32", "#FFFFFF") }
                }
                Item { width: 1; height: 12 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Recipients will only see the file description you've entered and can only upload files to this folder."); font.family: theme.font; font.pixelSize: 12; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: root.strong }
                Item { width: 1; height: 80 }
                Row {
                    anchors.right: parent.right; spacing: 8
                    OdspButton { label: fileRequest.busy ? "…" : qsTr("Next"); onClicked: fileRequest.next() }
                    OdspButton { label: qsTr("Cancel"); onClicked: fileRequest.close() }
                }
            }
            // Step 2: the link, and sending it.
            Column {
                visible: fileRequest.step === 2
                width: parent.width; topPadding: 18; spacing: 0
                Text { height: 30; verticalAlignment: Text.AlignVCenter; text: qsTr("Here's the link people can use to upload files"); font.family: theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; color: root.ink }
                Item { width: 1; height: 5 }
                Rectangle {
                    width: 418; height: 34; color: theme.surface
                    border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666", "#FFFFFF")
                    TextInput {
                        x: 9; width: 300; anchors.verticalCenter: parent.verticalCenter
                        readOnly: true; selectByMouse: true; clip: true
                        text: fileRequest.url
                        font.family: theme.font; font.pixelSize: 12; color: root.ink
                        Accessible.name: qsTr("Link")
                    }
                    Rectangle {
                        id: hcFill4
                        anchors.right: parent.right; anchors.rightMargin: 0.67; y: 0.67; width: 98.75; height: 32.67
                        color: crh.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#1AEBFF") : theme.surface
                        Rectangle { width: 1; height: parent.height; color: theme.pick("#A19F9D", "#666666", "#000000") }
                        Text { anchors.centerIn: parent; text: fileRequest.copied ? qsTr("Copied") : qsTr("Copy link"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(hcFill4, theme.hc("#7F85F5", "#FFFF00")) }
                        HoverHandler { id: crh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.copy(fileRequest.url); fileRequest.copied = true } }
                        Accessible.role: Accessible.Button
                        Accessible.name: fileRequest.copied ? qsTr("Link copied") : qsTr("Copy link")
                    }
                }
                Row {
                    topPadding: 8; spacing: 5; height: 30
                    FluentIcon { y: 10; size: 14; name: "folder-arrow-up-16"; color: root.strong }
                    Text { y: 8; text: qsTr("Anyone with the link can upload files"); font.family: theme.font; font.pixelSize: 12; color: root.strong }
                }
                Item { width: 1; height: 32 }
                Text { text: qsTr("Or you can send it via email"); font.family: theme.font; font.pixelSize: 15; color: root.ink }
                Item { width: 1; height: 8 }
                // To: picked people as pills, then the search box.
                Rectangle {
                    width: parent.width; height: Math.max(32.67, toFlow.height + 4); color: "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.accent }
                    Flow {
                        id: toFlow
                        width: parent.width; y: 2; spacing: 6
                        Repeater {
                            model: fileRequest.picked
                            Rectangle {
                                required property var modelData
                                required property int index
                                height: 28; radius: 14; width: pn.implicitWidth + 40
                                color: theme.pick("#F0F0F0", "#3D3D3D", "#000000")
                                Text { id: pn; x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.DisplayText; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                                FluentIcon { x: pn.x + pn.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "dismiss-12"; color: root.ink }
                                TapHandler { onTapped: fileRequest.picked = fileRequest.picked.filter((p, i) => i !== parent.index) }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Remove %1").arg(modelData.DisplayText)
                            }
                        }
                        TextInput {
                            id: frTo
                            width: Math.max(200, toFlow.width - 20); height: 28
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                            onTextChanged: fileRequest.search(text)
                            Text { visible: !frTo.text && !fileRequest.picked.length; anchors.verticalCenter: parent.verticalCenter; text: qsTr("To: Name, group, or email"); color: root.ink; font: frTo.font }
                            Accessible.name: qsTr("To: Name, group, or email")
                        }
                    }
                }
                // Suggestions
                Column {
                    width: parent.width
                    Repeater {
                        model: fileRequest.found.slice(0, 6)
                        Rectangle {
                            id: hcFill5
                            required property var modelData
                            width: parent.width; height: 40
                            color: sgh.hovered ? theme.menuHover : "transparent"
                            Avatar { x: 8; y: 6; size: 28; name: parent.modelData.DisplayText; photoId: parent.modelData.EntityData && parent.modelData.EntityData.ObjectId ? Mri.work(parent.modelData.EntityData.ObjectId) : "" }
                            Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.DisplayText + (parent.modelData.Description ? "  " + parent.modelData.Description : ""); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill5, root.ink); elide: Text.ElideRight; width: parent.width - 52 }
                            HoverHandler { id: sgh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { fileRequest.picked = fileRequest.picked.concat([parent.modelData]); frTo.text = ""; fileRequest.found = [] } }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.DisplayText
                        }
                    }
                }
                Item { width: 1; height: 12 }
                Rectangle {
                    width: parent.width; height: 67; radius: 4; color: theme.surface
                    TextEdit {
                        id: frMessage
                        anchors.fill: parent; anchors.margins: 6
                        wrapMode: TextEdit.Wrap
                        font.family: theme.font; font.pixelSize: 12; color: root.ink
                        Text { visible: !frMessage.text; text: qsTr("Message..."); color: root.ink; font: frMessage.font }
                        Accessible.name: qsTr("Add message")
                    }
                }
                Item { width: 1; height: 47 }
                Row {
                    anchors.right: parent.right
                    OdspButton {
                        label: fileRequest.busy ? "…" : fileRequest.picked.length ? qsTr("Send") : qsTr("Done")
                        onClicked: if (fileRequest.picked.length) fileRequest.send(); else { fileRequest.close(); frDone.show(false) }
                    }
                }
            }
        }
    }
    // After Request files: "Your file request was created!" (or "…sent!"),
    // a 44 px #107C10 check over the words, centred; 600 wide, a Close.
    Popup {
        id: frDone
        property bool sent: false
        function show(s) { sent = s; open() }
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 24
        width: 600
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Item {
            implicitHeight: 31.33 + 6 + 119 - 2
            Rectangle {
                id: hcFill6
                anchors.right: parent.right; width: 32; height: 31.33; radius: 4
                color: fdh.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill6, root.strong) }
                HoverHandler { id: fdh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: frDone.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
            }
            Column {
                y: 39.33; width: parent.width; spacing: 0
                Rectangle {
                    id: hcFill7
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44; height: 44; radius: 22; color: theme.hc("#107C10", "#000000")
                    FluentIcon { anchors.centerIn: parent; name: "checkmark-20"; size: 20; color: theme.onFill(hcFill7, "white") }
                }
                Item { width: 1; height: 16 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: frDone.sent ? qsTr("Your file request was sent!") : qsTr("Your file request was created!")
                    font.family: theme.font; font.pixelSize: 21; color: root.ink
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }
                Item { width: 1; height: 11 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("We will notify you when someone uploads files.")
                    font.family: theme.font; font.pixelSize: 12; color: root.strong
                }
            }
        }
    }
    // Both of OneDrive's dialog buttons are brand-filled in Teams.
    component OdspButton: Rectangle {
        id: ob
        property string label
        property bool enabled2: true
        signal clicked()
        width: Math.max(80, obText.implicitWidth + 24); height: 32; radius: 4
        color: !enabled2 ? theme.pick("#F0F0F0", "#3D3D3D", "#000000") : obh.hovered ? theme.brandHover : theme.brandFill
        Text {
            id: obText
            anchors.centerIn: parent
            text: ob.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(ob, ob.enabled2 ? "white" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F"))
        }
        HoverHandler { id: obh; cursorShape: ob.enabled2 ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: ob.enabled2; onTapped: ob.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // Rename: the name without its extension in a 32 px box, the
    // extension after it (".txt", 10 down, 5 in).
    OdspDialog {
        id: renameDialog
        property var target: null
        property string ext: ""
        title: qsTr("Rename"); okText: qsTr("Update")
        // 240 tall, as Teams' Rename without Copilot's Suggested names; with
        // the folded row 266.67, growing as it opens (25 + 8.67 under it).
        bodyHeight: sugg.visible ? sugg.y + sugg.height + 33.67 : 128.67
        okEnabled: nameInput.text.trim().length > 0
        // Copilot's Suggested names (OneDrive's RenameSuggestions): offered
        // for OneDrive's document, text and picture types with a Copilot
        // licence; asked the first time the row opens.
        property bool suggOffered: false
        property bool suggOpen: false
        property bool suggLoading: false
        property bool suggConfidential: false
        property var suggNames: []
        property string suggError: ""
        property string suggThumb: ""
        property int suggReq: 0
        readonly property var suggExts: ["doc", "docx", "docm", "dot", "dotx", "dotm", "xls", "xlsx", "xlsm", "xlt", "xltx", "xltm", "ppt", "pptx", "pptm", "pot", "potx", "potm",
            "pdf", "txt", "rtf", "csv", "tsv", "json", "md", "odt", "ods", "odp", "jpg", "jpeg", "png", "bmp", "tiff", "tif"]
        function openFor(it) {
            target = it
            const dot = it.is_folder ? -1 : it.name.lastIndexOf(".")
            ext = dot > 0 ? it.name.slice(dot) : ""
            nameInput.text = dot > 0 ? it.name.slice(0, dot) : it.name
            suggReq++
            suggOpen = false; suggLoading = false; suggConfidential = false; suggNames = []; suggError = ""; suggThumb = ""
            suggOffered = root.renameSuggestions && dot > 0 && suggExts.indexOf(ext.slice(1).toLowerCase()) >= 0
            if (suggOffered) backend.driveAction(root.tag + "r" + suggReq + ":rename_check", JSON.stringify(it), "{}")
            open()
            nameInput.selectAll(); nameInput.forceActiveFocus()
        }
        function suggest() {
            suggReq++
            suggLoading = true; suggNames = []; suggError = ""; suggThumb = ""
            backend.driveAction(root.tag + "r" + suggReq + ":rename_suggest", JSON.stringify(target), "{}")
        }
        function toggleSugg() {
            if (suggConfidential) return
            suggOpen = !suggOpen
            if (suggOpen && !suggLoading && !suggNames.length && !suggError) suggest()
        }
        function suggReply(n, kind, v, error) {
            if (n !== suggReq) return
            if (kind === "rename_check") { suggConfidential = !error && !!v && !!v.confidential; return }
            if (kind === "rename_suggest_part") { if (v && v.names) suggNames = v.names; return }
            suggLoading = false
            if (error || !v) { suggNames = []; suggError = "Generic"; return }
            if (v.confidential) { suggConfidential = true; suggOpen = false; return }
            if (v.error) { suggNames = []; suggError = v.error; return }
            suggNames = v.names || []
        }
        onAccepted: {
            const n = nameInput.text.trim() + ext
            if (!nameInput.text.trim()) return
            close()
            if (n === target.name) return
            backend.driveAction(root.tag + "rename", JSON.stringify(target), JSON.stringify({ name: n }))
        }
        Rectangle {
            y: 33.67; width: parent.width - extText.width; height: 32; radius: 4
            color: theme.pick("#FFFFFF", "#292929", "#000000")
            border.width: 0.67; border.color: root.line
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: nameInput.activeFocus ? 2 : 0.67; radius: 1; color: nameInput.activeFocus ? root.accent : root.strong }
            TextInput {
                id: nameInput
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                selectByMouse: true
                Keys.onReturnPressed: renameDialog.accepted()
                Accessible.name: qsTr("Name")
            }
        }
        Text {
            id: extText
            anchors.right: parent.right
            y: 33.67; width: renameDialog.ext ? implicitWidth : 0
            leftPadding: 5; rightPadding: 5; topPadding: 10
            text: renameDialog.ext
            font.family: theme.font; font.pixelSize: 14; color: root.ink
        }
        // Suggested names (measured on winpc 2026-11-19): a 390.67 wide
        // accordion, radius 4, 12 under the box; its 44 tall header has the
        // Copilot glyph (16, at 10), "Suggested names" (14/20 #424242, at 34)
        // and a 20 px chevron 10 from the right. Open: the names as 28 tall
        // pills (12/16 #242424, 1 px #D1D1D1, radius 14, padding 19, 8
        // apart), 6 under the header, or a 12/16 message; then "AI-generated
        // content may be incorrect" (12/16) with the Helpful / Not helpful
        // thumbs (24, 2 apart), 12 from the bottom.
        Rectangle {
            id: sugg
            visible: renameDialog.suggOffered
            y: 77.67; width: 390.67; radius: 4
            height: renameDialog.suggOpen ? suggBody.y + suggBody.height + 12 : 44
            color: theme.surface
            clip: true
            readonly property color fg: renameDialog.suggConfidential ? theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
            Rectangle {
                id: hcFillSg
                width: parent.width; height: 44; radius: 4
                color: sgHead.hovered && !renameDialog.suggConfidential ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : "transparent"
                FluentIcon { x: 10; y: 14; size: 16; name: "copilot-16"; color: theme.onFill(hcFillSg, sugg.fg) }
                Text {
                    x: 34; y: 12; text: qsTr("Suggested names")
                    font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.onFill(hcFillSg, sugg.fg)
                }
                FluentIcon { x: parent.width - 30; y: 12; size: 20; name: renameDialog.suggOpen ? "chevron-up-20" : "chevron-down-20"; color: theme.onFill(hcFillSg, sugg.fg) }
                HoverHandler { id: sgHead; cursorShape: renameDialog.suggConfidential ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { onTapped: renameDialog.toggleSugg() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Suggested names")
                Accessible.description: renameDialog.suggConfidential ? qsTr("This file is confidential, so its content can’t be accessed") : ""
                ToolTip.visible: sgHead.hovered && renameDialog.suggConfidential
                ToolTip.text: qsTr("This file is confidential, so its content can’t be accessed")
            }
            // Get new suggestions: 28 x 28, 32 from the right, once there are three.
            Rectangle {
                id: hcFillRs
                visible: renameDialog.suggOpen && renameDialog.suggNames.length >= 3 && !renameDialog.suggLoading
                x: parent.width - 32 - 28; y: 8; width: 28; height: 28; radius: 6
                color: rsh.hovered ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : "transparent"
                FluentIcon { anchors.centerIn: parent; size: 16; name: "arrow-sync-16"; color: theme.onFill(hcFillRs, rsh.hovered ? theme.pick("#242424", "#FFFFFF") : sugg.fg) }
                HoverHandler { id: rsh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: renameDialog.suggest() }
                ToolTip.visible: rsh.hovered
                ToolTip.text: qsTr("Get new suggestions")
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Get new suggestions")
            }
            Column {
                id: suggBody
                visible: renameDialog.suggOpen
                x: 12; y: 44; width: parent.width - 24
                spacing: 0
                // The names, or three loading pills.
                Flow {
                    visible: renameDialog.suggLoading && !renameDialog.suggNames.length || renameDialog.suggNames.length > 0
                    width: parent.width; spacing: 8
                    topPadding: 6; bottomPadding: 6
                    Repeater {
                        model: renameDialog.suggNames.length ? renameDialog.suggNames : (renameDialog.suggLoading ? 3 : 0)
                        Rectangle {
                            id: pill
                            required property var modelData
                            readonly property bool skeleton: typeof modelData === "number"
                            width: skeleton ? 150 : Math.min(pillText.implicitWidth + 40, suggBody.width)
                            height: skeleton ? 34 : 28; radius: height / 2
                            color: !skeleton && ph.hovered ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : "transparent"
                            border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                            Rectangle {
                                visible: pill.skeleton
                                anchors.centerIn: parent; width: 110; height: 10; radius: 4
                                color: theme.pick("#E6E6E6", "#3D3D3D", "#FFFFFF")
                            }
                            Text {
                                id: pillText
                                visible: !pill.skeleton
                                anchors.centerIn: parent; width: Math.min(implicitWidth, pill.width - 40)
                                text: pill.skeleton ? "" : pill.modelData
                                elide: Text.ElideRight
                                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                                color: theme.onFill(pill, theme.pick("#242424", "#FFFFFF"))
                            }
                            HoverHandler { id: ph; enabled: !pill.skeleton; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                enabled: !pill.skeleton
                                onTapped: { nameInput.text = pill.modelData; renameDialog.suggOpen = false; nameInput.forceActiveFocus() }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: pill.skeleton ? qsTr("Loading suggestions") : qsTr("Suggestion: %1").arg(pill.modelData)
                        }
                    }
                }
                // OneDrive's messages; a retryable one has "Try again".
                Text {
                    visible: !renameDialog.suggLoading && !renameDialog.suggNames.length && !!renameDialog.suggError
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    readonly property string message: ({
                        InsufficientContent: qsTr("This file doesn't have enough content to suggest names."),
                        FileNotAvailable: qsTr("This file is no longer available."),
                        Confidential: qsTr("This file is confidential, so its content can’t be accessed")
                    })[renameDialog.suggError] || qsTr("Something went wrong.")
                    readonly property bool retry: ["InsufficientContent", "FileNotAvailable", "Confidential"].indexOf(renameDialog.suggError) < 0
                    text: retry ? message + " <a href=\"retry\" style=\"color:" + theme.brand + ";text-decoration:none\">" + qsTr("Try again") + "</a>" : message
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                    color: theme.pick("#242424", "#FFFFFF")
                    onLinkActivated: renameDialog.suggest()
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: message
                }
                Item { width: 1; height: renameDialog.suggError && !renameDialog.suggNames.length && !renameDialog.suggLoading ? 12 : 8 }
                Row {
                    height: 24; spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("AI-generated content may be incorrect")
                        font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.pick("#5E5E5D", "#ADADAD", "#FFFFFF")
                    }
                    Row {
                        spacing: 2
                        Repeater {
                            model: [["like", qsTr("Helpful")], ["dislike", qsTr("Not helpful")]]
                            Rectangle {
                                id: hcFillTh
                                required property var modelData
                                readonly property bool pressed: renameDialog.suggThumb === modelData[0]
                                width: 24; height: 24
                                color: thh.hovered ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : "transparent"
                                FluentIcon {
                                    anchors.centerIn: parent; size: 16
                                    name: "thumb-" + hcFillTh.modelData[0] + "-16" + (hcFillTh.pressed ? "-filled" : "")
                                    color: theme.onFill(hcFillTh, hcFillTh.pressed ? theme.brand : thh.hovered ? theme.pick("#242424", "#FFFFFF") : theme.pick("#5E5E5D", "#ADADAD", "#FFFFFF"))
                                }
                                HoverHandler { id: thh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: renameDialog.suggThumb = hcFillTh.pressed ? "" : hcFillTh.modelData[0] }
                                ToolTip.visible: thh.hovered
                                ToolTip.text: modelData[1]
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData[1]
                                Accessible.checked: pressed
                            }
                        }
                    }
                }
            }
        }
    }

    // Delete?: "Are you sure you want to send this item to the recycle bin?"
    OdspDialog {
        id: deleteDialog
        property var target: null
        property var targets: []
        title: qsTr("Delete?"); okText: qsTr("Delete")
        bodyHeight: 128.67
        function openFor(it) { target = it; targets = [it]; open() }
        function openForMany(list) { target = list[0]; targets = list; open() }
        onAccepted: { close(); targets.forEach(t => root.deleteItem(t)) }
        Text {
            y: 22.67; width: parent.width
            wrapMode: Text.Wrap
            text: deleteDialog.targets.length > 1 ? qsTr("Are you sure you want to send these items to the recycle bin?")
                : qsTr("Are you sure you want to send this item to the recycle bin?")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: root.ink
        }
    }

    // Copy link: OneDrive makes the default link and shows it ("Link
    // created", 480 wide) with Copy; after Copy, "Link copied" and only
    // what the link does, with Settings.
    Popup {
        id: copyLink
        property var target: null
        property string url: ""
        property string sentence: ""
        property bool copied: false
        property bool busy: false
        /// Copy as soon as the link is made (a message's file card: Teams
        /// goes straight to "Link copied").
        property bool auto: false
        /// The link made (its kind and share id), for tests to delete.
        property int kind: 0
        property string shareId: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 0
        width: 480; height: copied ? 105.33 : 137.33
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        function start(it) {
            target = it; url = ""; copied = false; busy = true
            if (!it.sp_item) { url = it.web_url; sentence = qsTr("People with existing access can use the link"); busy = false; show(); return }
            backend.shareAction(root.tag + "info", JSON.stringify(root.ref(it)), "{}")
        }
        Connections {
            target: backend
            function onShareDone(op, result, error) {
                if (!op.startsWith(root.tag) || !copyLink.target) return
                const kind = op.slice(root.tag.length)
                const v = result ? JSON.parse(result) : null
                if (error) { copyLink.busy = false; root.notice("error", qsTr("The link wasn't created"), error); return }
                if (kind === "info") {
                    const edit = !!v.default_edit
                    if (v.default_existing) {
                        copyLink.url = v.direct_url
                        copyLink.sentence = qsTr("People with existing access can use the link")
                        copyLink.busy = false; copyLink.show()
                        return
                    }
                    copyLink.sentence = v.default_scope === 0 ? (edit ? qsTr("Anyone with the link can edit") : qsTr("Anyone with the link can view"))
                        : v.default_scope === 1 ? (edit ? qsTr("People in %1 with the link can edit") : qsTr("People in %1 with the link can view")).arg(v.tenant)
                        : (edit ? qsTr("Only the people you specified can edit") : qsTr("Only the people you specified can view"))
                    copyLink.kind = v.default_scope === 0 ? (v.default_edit ? 5 : 4) : v.default_scope === 1 ? (v.default_edit ? 3 : 2) : 6
                    backend.shareAction(root.tag + "link", JSON.stringify(root.ref(copyLink.target)), JSON.stringify({ scope: v.default_scope, edit: v.default_edit }))
                } else if (kind === "link") {
                    copyLink.url = v.url; copyLink.shareId = v.share_id || ""; copyLink.busy = false; copyLink.show()
                }
            }
        }
        function show() {
            if (auto) { root.copy(url); copied = true }
            open()
        }
        Row {
            x: 24; y: 24; height: 32; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-16"; size: 16; color: theme.pick("#107C10", "#54B054", "#FFFFFF") }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: copyLink.copied ? qsTr("Link copied") : qsTr("Link created")
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
        Rectangle {
            id: hcFill8
            x: parent.width - 24 - 32; y: 24; width: 32; height: 32; radius: 2
            color: clch.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 14; color: theme.onFill(hcFill8, root.ink) }
            HoverHandler { id: clch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copyLink.close() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Item {
            visible: !copyLink.copied
            x: 24; y: 56; width: 432; height: 32
            Rectangle {
                width: 358.05; height: 32; radius: 4
                color: theme.pick("#FFFFFF", "#292929", "#000000"); border.width: 0.67; border.color: root.line
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.strong }
                // The link from its start, cut with "..." as OneDrive's box shows it.
                Text {
                    x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                    text: copyLink.url; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Link created")
                }
            }
            Rectangle {
                id: hcFill9
                x: 358.05; width: 73.95; height: 32; radius: 2
                color: cpb.hovered ? theme.menuHover : theme.surface
                border.width: 0.67; border.color: theme.pick("#7A7A7A", "#ADADAD", "#FFFFFF")
                Text { anchors.centerIn: parent; text: qsTr("Copy"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill9, root.ink) }
                HoverHandler { id: cpb; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.copy(copyLink.url); copyLink.copied = true } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Copy")
            }
        }
        Item {
            x: 24; y: copyLink.copied ? 64.67 : 96.67; width: 432; height: 17.33
            Text { y: 0.67; text: copyLink.sentence; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 4; spacing: 4
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "settings-16"; size: 14; color: root.accent }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Settings"); font.family: theme.font; font.pixelSize: 14; color: root.accent }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { copyLink.close(); share.openLinkSettingsFor(root.ref(copyLink.target), copyLink.target.name, copyLink.target.kind) } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Sharing settings")
            }
        }
    }

    MovePicker { id: picker }
    PlaylistPicker { id: playlists; actions: root }

    // Move to / Copy to: OneDrive's picker over the window (1140 x 720 at
    // most, #F5F5F5): the places on the left (My files, then your teams'
    // libraries under Quick access), the folder's list on a white card,
    // and Move here / Copy here with Cancel at the bottom right.
    component MovePicker: Popup {
        id: pk
        property var target: null
        property bool moving: true
        /// The folder shown: {drive_id, item_id, here, items}; the trail of
        /// folders opened: [{name, drive_id, item_id}].
        property var shown: null
        property var trail: []
        property var libraries: []
        property string place: "mine"
        property bool loading: false
        /// Add shortcut ▸ Other locations: OneDrive's "Pick a folder" with Select.
        property bool shortcut: false
        readonly property bool sameFolder: !!shown && moving && !shortcut && shown.drive_id === (root.folder.drive_id || "") && shown.item_id === (root.folder.item_id || "")
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 0
        width: Math.min(1140, Overlay.overlay ? Overlay.overlay.width - 32 : 1140)
        height: Math.min(720, Overlay.overlay ? Overlay.overlay.height - 32 : 720)
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: Rectangle { color: theme.pick("#F5F5F5", "#141414", "#000000"); radius: 4 }
        function openFor(it, move) {
            target = it; moving = move; place = "mine"; shown = null
            root.jobCount = 1 + root.others.length
            trail = [{ name: qsTr("My files"), drive_id: "", item_id: "" }]
            open()
            load("", "")
            backend.driveAction(root.tag + "libraries", "{}", "{}")
            root.loadQuickAccess()
        }
        /// The Navigation Pane button folds the places into a 68-wide rail of
        /// icons; "Browse by" folds People and Meetings away.
        property bool navCollapsed: false
        property bool browseOpen: true
        /// The view switch: List, Compact List or Tiles (Teams' picker keeps
        /// it while it's open).
        property string view: "list"
        readonly property var viewItems: [{ label: qsTr("List"), icon: "list-16", checked: view === "list" },
                                          { label: qsTr("Compact List"), icon: "text-align-left-16", checked: view === "compact" },
                                          { label: qsTr("Tiles"), icon: "grid-16", checked: view === "tiles" }]
        property var thumbs: ({})
        property var thumbAsked: ({})
        function wantThumb(it, size) {
            if (thumbAsked[it.id] || it.is_folder) return
            thumbAsked[it.id] = true
            backend.driveAction(root.tag + "thumb", JSON.stringify(it), JSON.stringify({ size: size }))
        }
        property int seq: 0
        function ask(op, args) { seq++; backend.driveAction(root.tag + seq + ":" + op, "{}", JSON.stringify(args)) }
        function load(d, i) { if (searching) pkSearch.text = ""; searching = false; newFolder = false; loading = true; ask("folders", { drive_id: d, item_id: i }) }
        /// Search ("Search in …"): its results replace the list, with All
        /// files / My files; New folder: an inline name row.
        property bool searching: false
        property bool searchAll: false
        property string query: ""
        /// The date filter: all, today, last7Days, last30Days, last3Months,
        /// lastYear (OneDrive's keys).
        property string dates: "all"
        readonly property var dateFilters: [["all", qsTr("All dates")], ["today", qsTr("Today")], ["last7Days", qsTr("Last 7 days")], ["last30Days", qsTr("Last 30 days")], ["last3Months", qsTr("Last 3 months")], ["lastYear", qsTr("In the last year")]]
        readonly property string datesLabel: (dateFilters.find(d => d[0] === dates) || dateFilters[0])[1]
        property bool newFolder: false
        /// People: the person picked.
        property string person: ""
        readonly property var placeTitles: ({ shared: qsTr("Shared with you"), favorites: qsTr("Favorites"), people: qsTr("People"), meetings: qsTr("Meetings"), more: qsTr("Shared libraries") })
        readonly property bool inPlaceList: ["shared", "favorites", "people", "meetings", "more"].indexOf(place) >= 0 && trail.length <= 1
        function search(q, all) {
            if (!searching) dates = "all"
            query = q; searchAll = all; searching = true; loading = true
            if (pkSearch.text !== q) pkSearch.text = q
            if (!searching) searchPeople = []
            ask("picker_search", { query: q, all: all, dates: dates, people: searchPeople })
        }
        /// The Person filter (OneDrive's people pill): at most one person
        /// ({name, email, id}); results are theirs (modified or authored).
        property var searchPeople: []
        property var peopleFound: []
        property bool peopleLoading: false
        property string peopleQuery: ""
        function findPeople(q) { peopleQuery = q; peopleLoading = true; backend.driveAction(root.tag + "people:picker_people", "{}", JSON.stringify({ query: q })) }
        function setPerson(p) { searchPeople = p ? [p] : []; search(query, searchAll) }
        /// Location pictures by web address: {path} (a site's logo) or {oid}.
        property var locationPics: ({})
        function locationPicture(web, kind, author) {
            if (!web || locationPics[web] !== undefined) return
            const m = Object.assign({}, locationPics); m[web] = null; locationPics = m
            backend.driveAction(root.tag + "pic:location_picture", "{}", JSON.stringify({ web: web, kind: kind, author: author || "" }))
        }
        function datesMenuForTest(o) { if (o) datesMenu.open(); else datesMenu.close() }
        function personMenuForTest(o) { if (o) { personMenu.open(); personSearch.text = ""; findPeople("") } else personMenu.close() }
        function personTypeForTest(t) { personSearch.text = t }
        /// Location opens the folder a result is in (its library when it is
        /// at the top).
        function openLocation(h) {
            const loc = h.location || []
            if (loc.length <= 1) { if (h.same_site) openPlace("mine", null); else openPlace(h.drive_id, { name: loc[0] || "", drive_id: h.drive_id }); return }
            trail = [{ name: loc[0], drive_id: h.same_site ? "" : h.drive_id, item_id: "" }, { name: loc[loc.length - 1], drive_id: h.drive_id, item_id: h.parent_id }]
            load(h.drive_id, h.parent_id)
        }
        function createFolder(name) {
            if (!name.trim() || !shown) return
            newFolder = false; loading = true
            ask("picker_new_folder", { drive_id: shown.drive_id || "", item_id: shown.item_id || "", name: name.trim() })
        }
        function reply(kind, v, error) {
            if (kind === "libraries") { libraries = v || []; return }
            loading = false
            if (kind === "picker_new_folder") { if (error) root.notice("error", qsTr("The folder wasn't created"), error); else into(v); return }
            // The service's own text (an HTTP status and address) is in the
            // log; the list says what OneDrive says.
            if (error) { shown = { drive_id: "", item_id: "", items: [], error: qsTr("Sorry, something went wrong.") }; return }
            if (kind === "picker_search") { if (v.query === query && v.dates === dates && JSON.stringify((v.people || []).map(p => p.name)) === JSON.stringify(searchPeople.map(p => p.name))) shown = { drive_id: "", item_id: "", items: v.items, search: true }; return }
            if (kind === "picker_place") { shown = { drive_id: "", item_id: "", items: v.items || [], people: v.people || null }; return }
            shown = v
        }
        function into(f) {
            if (searching) trail = trail.slice(0, 1)
            trail = trail.concat([{ name: f.name, drive_id: f.drive_id, item_id: f.id }]); load(f.drive_id, f.id)
        }
        function back(i) {
            if (trail[i].place) { openPlace(place, null); return }
            trail = trail.slice(0, i + 1); const t = trail[i]; load(t.drive_id, t.item_id)
        }
        function openPlace(key, lib) {
            place = key; person = ""; searching = false; newFolder = false; pkSearch.text = ""
            if (placeTitles[key]) {
                trail = [{ name: placeTitles[key], drive_id: "", item_id: "", place: true }]
                // Nothing to ask for: any answer still on its way is stale.
                if (key === "more") { seq++; loading = false; shown = { drive_id: "", item_id: "", items: [] }; return }
                loading = true; shown = null
                ask("picker_place", { place: key })
                return
            }
            trail = [{ name: lib ? lib.name : qsTr("My files"), drive_id: lib ? lib.drive_id : "", item_id: "" }]
            load(lib ? lib.drive_id : "", "")
        }
        function done() {
            if (!shown || !shown.here || sameFolder) return
            if (shortcut) {
                const place = trail.length ? trail[trail.length - 1].name : qsTr("My files")
                close()
                root.addShortcut(target, "folder", place, { site: shown.here.sp_site, drive_id: shown.drive_id || shown.here.drive_id, folder: shown.item_id ? shown.here.sp_item : "" })
                return
            }
            const op = moving ? "move" : "copy"
            root.notice("progress", root.count(root.jobCount, moving ? qsTr("Moving %1 item") : qsTr("Copying %1 item"), moving ? qsTr("Moving %1 items") : qsTr("Copying %1 items")))
            backend.driveAction(root.tag + op, JSON.stringify(target), JSON.stringify({ dest: shown.here.web_url, more: root.jobCount > 1 ? root.others : [] }))
            close()
        }

        // The places (210 wide, or a 68-wide rail when folded)
        Item {
            width: pk.navCollapsed ? 68 : 210; height: parent.height
            // The title row (16, 18; 190 x 36) is the Navigation Pane
            // button: hovering shows its glyph at the right; folded, only
            // the glyph remains (36 x 36).
            Rectangle {
                id: hcFill10
                x: 16; y: 18; width: pk.navCollapsed ? 36 : 190; height: 36; radius: 4
                color: pk.navCollapsed && nph.hovered ? theme.menuHover : "transparent"
                Text {
                    visible: !pk.navCollapsed
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    text: pk.shortcut ? qsTr("Pick a folder") : pk.moving ? qsTr("Move to") : qsTr("Copy to")
                    font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.onFill(hcFill10, theme.text)
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                FluentIcon {
                    visible: pk.navCollapsed || nph.hovered
                    x: pk.navCollapsed ? 8 : parent.width - 30; anchors.verticalCenter: parent.verticalCenter
                    name: pk.navCollapsed ? "panel-left-expand-20" : "panel-left-contract-20"; size: 20; color: theme.onFill(hcFill10, root.ink)
                }
                HoverHandler { id: nph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pk.navCollapsed = !pk.navCollapsed }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Navigation Pane")
            }
            Column {
                y: 58; width: parent.width
                PlaceRow { label: qsTr("My files"); icon: "folder-16"; on: pk.place === "mine"; onPicked: pk.openPlace("mine", null) }
                PlaceRow { label: qsTr("Shared"); icon: "people-16"; on: pk.place === "shared"; onPicked: pk.openPlace("shared", null) }
                PlaceRow { label: qsTr("Favorites"); icon: "star-16"; on: pk.place === "favorites"; onPicked: pk.openPlace("favorites", null) }
                Item { width: 1; height: 8 }
                // "Browse by" (36 tall) folds People and Meetings; its
                // chevron shows on hover (down while open, up while folded),
                // and always on the folded rail.
                Rectangle {
                    id: hcFill11
                    x: 16; width: pk.navCollapsed ? 36 : 190; height: 36; radius: 4
                    color: pk.navCollapsed && bbh.hovered ? theme.menuHover : "transparent"
                    Text { visible: !pk.navCollapsed; x: 8; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Browse by"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill11, theme.text) }
                    FluentIcon {
                        visible: pk.navCollapsed || bbh.hovered
                        x: pk.navCollapsed ? 10 : parent.width - 28; anchors.verticalCenter: parent.verticalCenter
                        name: pk.browseOpen ? "chevron-down-16" : "chevron-up-16"; size: 16; color: theme.onFill(hcFill11, root.ink)
                    }
                    HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.browseOpen = !pk.browseOpen }
                    ToolTip.visible: bbh.hovered; ToolTip.delay: 300; ToolTip.text: qsTr("Browse by")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Browse by")
                }
                PlaceRow { visible: pk.browseOpen; label: qsTr("People"); icon: "person-16"; on: pk.place === "people"; onPicked: pk.openPlace("people", null) }
                PlaceRow { visible: pk.browseOpen; label: qsTr("Meetings"); icon: "calendar-ltr-16"; on: pk.place === "meetings"; onPicked: pk.openPlace("meetings", null) }
                Item { width: 1; height: 16 }
                // "Quick access" with its (i): "Frequently used team
                // locations, …"; each library has a pin on hover (solid and
                // always shown once pinned). Folded, a 36-wide line.
                Row {
                    x: 24; height: 18.67; spacing: 8; visible: root.quickAccess.length > 0 && !pk.navCollapsed
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Quick access"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    InfoTip { anchors.verticalCenter: parent.verticalCenter }
                }
                Item {
                    visible: root.quickAccess.length > 0 && pk.navCollapsed; width: parent.width; height: 18.67
                    Rectangle { x: 16; y: 9; width: 36; height: 1; color: theme.pick("#D1D1D1", "#3D3D3D", "#000000") }
                }
                Item { width: 1; height: 9.33; visible: root.quickAccess.length > 0 }
                Repeater {
                    model: root.quickAccess
                    PlaceRow {
                        required property var modelData
                        label: modelData.label; site: true; lib: modelData
                        on: !!modelData.drive_id && pk.place === modelData.drive_id
                        onPicked: if (modelData.drive_id) pk.openPlace(modelData.drive_id, { name: modelData.label, drive_id: modelData.drive_id })
                    }
                }
                Item { width: 1; height: 6 }
                // Folded: "…" (36 x 36) for More places.
                Rectangle {
                    id: hcFill12
                    visible: pk.navCollapsed
                    x: 16; width: 36; height: 36; radius: 4
                    color: mph2.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(hcFill12, root.accent) }
                    HoverHandler { id: mph2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.openPlace("more", null) }
                    ToolTip.visible: mph2.hovered; ToolTip.delay: 300; ToolTip.text: qsTr("More places...")
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("More places...")
                }
                Text {
                    visible: !pk.navCollapsed
                    x: 32; height: 24; verticalAlignment: Text.AlignVCenter
                    text: qsTr("More places...")
                    font.family: theme.font; font.pixelSize: 14; color: root.accent; font.underline: mph.hovered || pk.place === "more"
                    HoverHandler { id: mph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.openPlace("more", null) }
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
            }
        }
        // The folder
        Item {
            id: pkBody
            x: pk.navCollapsed ? 82 : 224; width: parent.width - x; height: parent.height
            readonly property var listItems: !pk.shown ? [] : pk.shown.people
                ? (pk.person ? (pk.shown.people.find(p => (p.id || p.name) === pk.person) || { items: [] }).items : [])
                : pk.shown.items || []
            // Search results: ← "Search results".
            Row {
                visible: pk.searching
                x: 23; y: 18; height: 36; spacing: 12
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter; name: "arrow-left-20"; size: 20; color: root.ink
                    TapHandler { onTapped: { pk.searching = false; pk.back(pk.trail.length - 1) } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Back")
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Search results"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: root.ink }
            }
            // "Search in …" and New folder at the top right.
            Row {
                anchors.right: parent.right; anchors.rightMargin: 31.33; y: 20; spacing: 12
                Rectangle {
                    width: 240; height: 32; radius: 16
                    color: theme.surface; border.width: pkSearch.activeFocus ? 2 : 0.67; border.color: pkSearch.activeFocus ? root.accent : root.line
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search-16"; size: 16; color: root.strong }
                    TextInput {
                        id: pkSearch
                        x: 32; width: parent.width - 32 - 28; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                        Keys.onReturnPressed: if (text.trim()) pk.search(text.trim(), pk.place !== "mine" || pk.searchAll)
                        Text {
                            visible: !pkSearch.text
                            text: pk.place === "mine" || !pk.inPlaceList ? qsTr("Search in %1").arg(pk.trail.length ? pk.trail[pk.trail.length - 1].name : qsTr("My files")) : qsTr("Search in all files")
                            color: theme.textTertiary; font: pkSearch.font; elide: Text.ElideRight; width: parent.width
                        }
                        Accessible.name: qsTr("Search")
                    }
                    FluentIcon {
                        visible: !!pkSearch.text
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: root.strong
                        TapHandler { onTapped: { pkSearch.text = ""; if (pk.searching) { pk.searching = false; pk.back(pk.trail.length - 1) } } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Clear search")
                    }
                }
                Rectangle {
                    id: hcFill13
                    visible: !pk.inPlaceList && !pk.searching && !!pk.shown && !!pk.shown.here
                    width: nfRow.implicitWidth + 16; height: 32; radius: 4
                    color: nfh.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: root.line
                    Row { id: nfRow; anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder-add-20"; size: 16; color: theme.onFill(hcFill13, root.strong) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("New folder"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill13, root.ink) } }
                    HoverHandler { id: nfh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { pk.newFolder = true; nfName.text = qsTr("New folder"); nfName.selectAll(); nfName.forceActiveFocus() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("New folder")
                }
                // The view switch (48 x 40): the view's glyph and a chevron;
                // its menu (172 wide) ticks List, Compact List or Tiles.
                Rectangle {
                    id: hcFill14
                    visible: !(pk.place === "more" && !pk.searching) && !(pk.shown && pk.shown.people && !pk.person)
                    width: 48; height: 32; radius: 4
                    color: vsh.hovered || vsMenu.opened ? theme.menuHover : "transparent"
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: pk.view === "tiles" ? "grid-16" : pk.view === "compact" ? "text-align-left-16" : "list-16"; size: 16; color: theme.onFill(hcFill14, root.ink) }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.onFill(hcFill14, root.ink) }
                    }
                    HoverHandler { id: vsh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: vsMenu.open() }
                    ToolTip.visible: vsh.hovered && !vsMenu.opened; ToolTip.delay: 300; ToolTip.text: qsTr("View options")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Switch view options")
                    MenuPopup {
                        id: vsMenu; fabric: true; fabricWidth: 172
                        x: parent.width - 172; y: parent.height + 4
                        items: pk.viewItems
                        onPicked: i => pk.view = ["list", "compact", "tiles"][i]
                    }
                }
            }
            // All files / My files under the results' title (16/22 semibold
            // tabs, 4 px padding, the chosen one underlined 2 px in the
            // brand colour), then the date filter (a 32 tall pill: the
            // choice 14/600 and a 16 px chevron; its menu 4.6 right and
            // 4.7 under it, 170.7 wide).
            Row {
                visible: pk.searching
                x: 16; y: 85; spacing: 22
                Row {
                spacing: 12
                Repeater {
                    model: [{ label: qsTr("All files"), all: true }, { label: qsTr("My files"), all: false }]
                    Item {
                        id: tabItem
                        required property var modelData
                        width: tabText.implicitWidth + 8; height: 30
                        Text {
                            id: tabText
                            x: 4; y: 2; height: 22; verticalAlignment: Text.AlignVCenter
                            text: tabItem.modelData.label
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: root.ink
                        }
                        Rectangle { visible: pk.searchAll === tabItem.modelData.all; y: 28; width: parent.width; height: 2; radius: 1; color: root.accent }
                        TapHandler { onTapped: pk.search(pk.query, tabItem.modelData.all) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: tabItem.modelData.all ? qsTr("Search results in files across your organization") : qsTr("Search results in your files")
                        Accessible.selected: pk.searchAll === tabItem.modelData.all
                    }
                }
                }
                // The date pill, then Person, 10.67 apart.
                Row {
                spacing: 10.67
                Rectangle {
                    id: datesButton
                    y: -1; width: 18.6 + datesText.implicitWidth + 10 + 16 + 18.7; height: 32; radius: 16
                    color: dbh.hovered || datesMenu.opened ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Text { id: datesText; x: 18.6; anchors.verticalCenter: parent.verticalCenter; text: pk.datesLabel; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(datesButton, root.ink) }
                    FluentIcon { x: datesText.x + datesText.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.onFill(datesButton, root.ink) }
                    HoverHandler { id: dbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: datesMenu.open() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Filter files by %1").arg(pk.datesLabel.toLowerCase())
                    MenuPopup {
                        id: datesMenu
                        padding: 0; minRowWidth: 170.67
                        x: 4.6; y: parent.height + 4.7
                        items: pk.dateFilters.map(d => ({ label: d[1], checked: d[0] === pk.dates }))
                        onPicked: i => { pk.dates = pk.dateFilters[i][0]; pk.search(pk.query, pk.searchAll) }
                    }
                }
                // Person (OneDrive's people pill, its spofilepicker code): 32
                // tall, radius 16, padding 5 14, 14/600, a chevron; "Person",
                // or the person's 20 px picture and name, on brand-2 once
                // picked. Its menu: a round "Search for a person" box, people
                // rows (a check slot, the 20 px picture, the name), "Loading
                // people…" / "No people found", and Clear.
                Rectangle {
                    id: personButton
                    readonly property var person: pk.searchPeople.length ? pk.searchPeople[0] : null
                    y: -1; width: 14 + (person ? 20 + 6 : 0) + Math.min(220, personText.implicitWidth) + 6 + 16 + 14; height: 32; radius: 16
                    color: person || personMenu.opened ? theme.pick("#E1E3F7", "#2B2C3F", "#000000") : pph.hovered ? theme.menuHover : theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                    border.width: 1; border.color: person || personMenu.opened ? theme.pick("#4F52B2", "#7F85F5", "#1AEBFF") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                    Avatar { visible: !!personButton.person; x: 14; anchors.verticalCenter: parent.verticalCenter; size: 20; name: personButton.person ? personButton.person.name : ""; photoId: personButton.person && personButton.person.id ? Mri.work(personButton.person.id) : "" }
                    Text {
                        id: personText
                        x: personButton.person ? 40 : 14; width: Math.min(220, implicitWidth); anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -1
                        elide: Text.ElideRight
                        text: personButton.person ? personButton.person.name : qsTr("Person")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(personButton, theme.pick("#242424", "#FFFFFF"))
                    }
                    FluentIcon { x: personText.x + personText.width + 6; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.onFill(personButton, theme.pick("#242424", "#FFFFFF")) }
                    HoverHandler { id: pph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { personMenu.open(); personSearch.text = ""; pk.findPeople("") } }
                    ToolTip.visible: pph.hovered
                    ToolTip.text: personText.text
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Filter by people") + " " + personText.text
                    Popup {
                        id: personMenu
                        x: 0; y: parent.height + 4
                        width: 320; padding: 0; topPadding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                        background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
                        contentItem: Column {
                            spacing: 4
                            Item {
                                width: 320; height: 32
                                Rectangle {
                                    x: 8; width: 304; height: 32; radius: 16
                                    color: theme.surface; border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
                                    TextInput {
                                        id: personSearch
                                        x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; clip: true
                                        font.family: theme.font; font.pixelSize: 14; color: theme.pick("#242424", "#FFFFFF")
                                        onTextChanged: if (personMenu.opened) personDelay.restart()
                                        Text { visible: !personSearch.text; text: qsTr("Search for a person"); font: personSearch.font; color: theme.pick("#616161", "#ADADAD", "#FFFFFF") }
                                        Accessible.role: Accessible.EditableText
                                        Accessible.name: qsTr("Search for a person")
                                    }
                                    Timer { id: personDelay; interval: 300; onTriggered: pk.findPeople(personSearch.text) }
                                }
                            }
                            Text {
                                visible: pk.peopleLoading && !pk.peopleFound.length
                                width: 320; horizontalAlignment: Text.AlignHCenter; topPadding: 12; bottomPadding: 12
                                text: qsTr("Loading people…")
                                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#616161", "#ADADAD", "#FFFFFF")
                            }
                            Text {
                                visible: !pk.peopleLoading && !pk.peopleFound.length
                                width: 320; horizontalAlignment: Text.AlignHCenter; topPadding: 12; bottomPadding: 12
                                text: qsTr("No people found")
                                font.family: theme.font; font.pixelSize: 14; color: theme.pick("#616161", "#ADADAD", "#FFFFFF")
                            }
                            ListView {
                                id: peopleList
                                visible: pk.peopleFound.length > 0
                                width: 320; height: Math.min(contentHeight, personSearch.text ? 168 : 104)
                                clip: true; spacing: 0
                                model: pk.peopleFound
                                delegate: Rectangle {
                                    id: prow
                                    required property var modelData
                                    readonly property bool on: !!personButton.person && personButton.person.id === modelData.id
                                    x: 4; width: 312; height: 32; radius: 8
                                    color: prh.hovered ? theme.pick("#F0F0F0", "#2E2E2E", "#1AEBFF") : "transparent"
                                    FluentIcon { visible: prow.on; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "checkmark-16"; color: theme.onFill(prow, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                                    Avatar { x: 36; anchors.verticalCenter: parent.verticalCenter; size: 20; name: prow.modelData.name; photoId: prow.modelData.id ? Mri.work(prow.modelData.id) : "" }
                                    Text {
                                        x: 64; width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                        text: prow.modelData.name
                                        font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, theme.pick("#242424", "#FFFFFF"))
                                    }
                                    HoverHandler { id: prh; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { personMenu.close(); pk.setPerson(prow.on ? null : prow.modelData) } }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: prow.modelData.name
                                    Accessible.selected: prow.on
                                }
                            }
                            Rectangle {
                                width: 320; height: 33
                                color: "transparent"
                                Rectangle { width: parent.width; height: 1; color: theme.pick("#D1D1D1", "#666666", "#FFFFFF") }
                                Row {
                                    x: 14; y: 8.5; spacing: 11; height: 16
                                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 12; name: "dismiss-12"; color: clh.hovered ? theme.pick("#424242", "#D6D6D6", "#FFFFFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF") }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("Clear")
                                        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                        color: clh.hovered ? theme.pick("#424242", "#D6D6D6", "#FFFFFF") : theme.pick("#616161", "#ADADAD", "#FFFFFF")
                                    }
                                    HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { personMenu.close(); if (pk.searchPeople.length) pk.setPerson(null) } }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: qsTr("Clear")
                                }
                            }
                        }
                    }
                }
                }
            }
            Row {
                visible: !pk.searching
                x: 23; y: 18; height: 36; spacing: 4
                Repeater {
                    model: pk.trail
                    Row {
                        required property var modelData
                        required property int index
                        spacing: 4; height: 36
                        FluentIcon { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: root.ink }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: root.ink
                            HoverHandler { cursorShape: index < pk.trail.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler { enabled: index < pk.trail.length - 1; onTapped: pk.back(index) }
                        }
                    }
                }
            }
            Rectangle {
                id: hcFill15
                x: 16.67; y: pk.searching ? 136.67 : 74.67; width: parent.width - 16.67 - 31.33; height: parent.height - y - 80 - 8
                // Tiles drop the white card, as in Teams.
                radius: 12; color: pk.view === "tiles" && !pkMore.visible && !(pk.shown && pk.shown.people && !pk.person) ? "transparent" : theme.surface; clip: true
                // Header: Type, Name, Modified, Modified By (14/600, 48 tall).
                Row {
                    id: pkHead
                    visible: !pkMore.visible && pk.view !== "tiles" && !pk.searching
                    height: 48
                    Item { width: 55; height: 48; FluentIcon { x: 22; anchors.verticalCenter: parent.verticalCenter; name: "document-16"; size: 16; color: theme.onFill(hcFill15, root.strong) } }
                    PickHead { width: pk.view === "compact" ? 300 : 270; label: qsTr("Name") }
                    PickHead { width: pk.view === "compact" ? 150 : 170; label: qsTr("Modified") }
                    PickHead { width: 150; label: qsTr("Modified By") }
                    PickHead { visible: pk.view === "compact"; width: 150; label: qsTr("File Size") }
                    PickHead { visible: pk.view === "compact"; width: 170; label: qsTr("Sharing") }
                    PickHead { visible: pk.view === "list" && !pk.searching; width: 200; label: qsTr("Activity") }
                }
                Rectangle { visible: pkHead.visible; y: 48.67; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333", "#000000") }
                // New folder: a name row at the top (Enter creates it, Esc drops it).
                Rectangle {
                    id: nfRowItem
                    visible: pk.newFolder
                    anchors.top: pkHead.bottom; anchors.topMargin: 1.67
                    width: parent.width; height: visible ? 59 : 0; color: theme.menuHover
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: "ft-folder-32" }
                    Rectangle {
                        x: 67; width: 260; height: 32; anchors.verticalCenter: parent.verticalCenter; radius: 4
                        color: theme.surface; border.width: 1; border.color: root.accent
                        TextInput {
                            id: nfName
                            x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                            Keys.onReturnPressed: pk.createFolder(text)
                            Keys.onEscapePressed: pk.newFolder = false
                            Accessible.name: qsTr("New folder name")
                        }
                    }
                }
                // People: who shared folders with you.
                ListView {
                    visible: !!pk.shown && !!pk.shown.people && !pk.person
                    anchors { top: pkHead.bottom; topMargin: 1.67; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: pk.shown && pk.shown.people ? pk.shown.people.filter(p => p.items.length) : []
                    delegate: Rectangle {
                        id: hcFill16
                        required property var modelData
                        width: ListView.view.width; height: 59
                        color: pph2.hovered ? theme.menuHover : "transparent"
                        Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: parent.modelData.name }
                        Column {
                            x: 67; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill16, root.ink) }
                            Text { text: parent.parent.modelData.items.length + (parent.parent.modelData.items.length === 1 ? " folder" : " folders"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill16, root.ink) }
                        }
                        HoverHandler { id: pph2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { pk.person = parent.modelData.id || parent.modelData.name; pk.trail = pk.trail.slice(0, 1).concat([{ name: parent.modelData.name, place: true }]) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Folders from %1").arg(modelData.name)
                    }
                }
                // More places…: "Shared libraries", Recent and Your Teams.
                Flickable {
                    id: pkMore
                    visible: pk.place === "more" && !pk.searching
                    anchors.fill: parent; anchors.margins: 0
                    contentHeight: moreCol.height + 24; clip: true
                    Column {
                        id: moreCol
                        x: 16; y: 24; width: parent.width - 32; spacing: 12
                        Repeater {
                            model: [qsTr("Recent"), qsTr("Your Teams")]
                            // Recent: Quick access's libraries; Your Teams:
                            // your teams' default libraries.
                            Column {
                                required property string modelData
                                width: moreCol.width; spacing: 12
                                Text { text: parent.modelData; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(hcFill15, root.ink) }
                                Flow {
                                    width: parent.width; spacing: 16
                                    Repeater {
                                        model: parent.parent.modelData === qsTr("Recent")
                                            ? root.quickAccess.map(q => ({ site: q.site_title, name: q.title, drive_id: q.drive_id, acronym: q.acronym, color: q.color }))
                                            : pk.libraries
                                        Rectangle {
                                            id: hcFill17
                                            required property var modelData
                                            width: Math.min(316, (moreCol.width - 16) / 2); height: 58; radius: 4
                                            color: lch.hovered ? theme.menuHover : theme.surface
                                            border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
                                            SiteTile { visible: !!parent.modelData.color; x: 9; anchors.verticalCenter: parent.verticalCenter; size: 40; acronym: parent.modelData.acronym || ""; tint: parent.modelData.color || "" }
                                            Avatar { visible: !parent.modelData.color; x: 9; anchors.verticalCenter: parent.verticalCenter; size: 40; name: parent.modelData.site; square: true }
                                            Column {
                                                x: 62; width: parent.width - 70; anchors.verticalCenter: parent.verticalCenter
                                                Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.site; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill17, root.ink) }
                                                Text { visible: parent.parent.modelData.name !== "Documents"; width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hcFill17, root.strong) }
                                            }
                                            HoverHandler { id: lch; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: if (parent.modelData.drive_id) pk.openPlace(parent.modelData.drive_id, { name: parent.modelData.site, drive_id: parent.modelData.drive_id }) }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData.site + " " + modelData.name
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // Search results as Teams' picker lists them: Name (a 32 px
                // folder, the name 14 px over "Created by: …" 12 px
                // #616161), Modified ("Sun at 3:41 PM"), Modified by and
                // Location, all #616161; the header 48 tall (14/600), rows
                // 56. Columns 200, 215.9 and 198.9 wide, Name the rest.
                Item {
                    id: pkFound
                    visible: pk.searching
                    anchors.fill: parent
                    readonly property real nameW: width - 200 - 215.9 - 198.9
                    Row {
                        id: foundHead
                        height: 48
                        Item { width: pkFound.nameW; height: 48; Text { x: 20.6; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill15, root.ink) } }
                        Repeater {
                            model: [[qsTr("Modified"), 200], [qsTr("Modified by"), 215.9], [qsTr("Location"), 198.9]]
                            Item {
                                required property var modelData
                                width: modelData[1]; height: 48
                                Text { x: 8.6; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill15, root.ink) }
                                Accessible.role: Accessible.ColumnHeader
                                Accessible.name: modelData[0]
                            }
                        }
                    }
                    Rectangle { y: 48.67; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333", "#000000") }
                    ListView {
                        anchors { top: foundHead.bottom; topMargin: 1.67; left: parent.left; right: parent.right; bottom: parent.bottom }
                        clip: true
                        model: pk.searching ? pkBody.listItems : []
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        Accessible.role: Accessible.Table
                        Accessible.name: qsTr("List of search result folders")
                        delegate: Rectangle {
                            id: frow
                            required property var modelData
                            readonly property bool pickable: modelData.id !== (pk.target ? pk.target.id : "")
                            // Teams' Location: the first part, then the next
                            // or "…" and the last, with chevrons between.
                            readonly property var locParts: {
                                const s = modelData.location || [], same = !!modelData.same_site
                                if (!s.length) return []
                                const l = [s[0]]
                                if (s.length === 2) l.push(s[1])
                                if (s.length > 2 && same) l.push(s[1])
                                if ((s.length > 3 && same) || s.length > 2) l.push("...", s[s.length - 1])
                                return l
                            }
                            width: ListView.view.width; height: 56
                            color: pickable && frh.hovered ? theme.menuHover : "transparent"
                            opacity: pickable ? 1 : 0.45
                            FluentIcon { x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32; name: "ft-folder-32" }
                            Text { x: 68; y: 9.8; width: pkFound.nameW - 68 - 8; elide: Text.ElideRight; text: frow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(frow, root.ink) }
                            Text { x: 68; y: 29.5; width: pkFound.nameW - 68 - 8; elide: Text.ElideRight; visible: !!frow.modelData.created_by; text: qsTr("Created by: ") + frow.modelData.created_by; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(frow, root.strong) }
                            Text { x: pkFound.nameW + 8.6; width: 200 - 16; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: frow.modelData.modified_text || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(frow, root.strong) }
                            Text { x: pkFound.nameW + 200 + 8; width: 215.9 - 16; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: frow.modelData.modified_by || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(frow, root.strong) }
                            Row {
                                id: locRow
                                visible: frow.locParts.length > 0
                                x: pkFound.nameW + 200 + 215.9 + 12; width: 198.9 - 24; height: 18.67; anchors.verticalCenter: parent.verticalCenter
                                spacing: 4; clip: true
                                // Another site's logo, or the picture of the
                                // person whose OneDrive it is, before its name.
                                readonly property var pic: frow.modelData.location_kind ? pk.locationPics[frow.modelData.location_web] : null
                                Component.onCompleted: if (frow.modelData.location_kind) pk.locationPicture(frow.modelData.location_web, frow.modelData.location_kind, frow.modelData.location_author)
                                Image {
                                    visible: frow.modelData.location_kind === "site" && !!locRow.pic && !!locRow.pic.path
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? 16 : 0; height: 16; sourceSize: Qt.size(32, 32)
                                    source: locRow.pic && locRow.pic.path ? locRow.pic.path : ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                                Avatar {
                                    visible: frow.modelData.location_kind === "person"
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 16; name: frow.locParts[0] ? String(frow.locParts[0]).replace(/'s OneDrive$/, "") : ""
                                    photoId: locRow.pic && locRow.pic.oid ? Mri.work(locRow.pic.oid) : ""
                                }
                                Repeater {
                                    model: frow.locParts
                                    Row {
                                        required property string modelData
                                        required property int index
                                        spacing: 4
                                        FluentIcon { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.onFill(frow, root.strong) }
                                        Text {
                                            // The last part shrinks with an ellipsis.
                                            width: index === frow.locParts.length - 1 ? Math.min(implicitWidth, Math.max(0, locRow.width - x - parent.x)) : implicitWidth
                                            elide: Text.ElideRight
                                            text: modelData; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(frow, root.strong)
                                        }
                                    }
                                }
                                HoverHandler { id: loch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: pk.openLocation(frow.modelData) }
                                ToolTip.visible: loch.hovered; ToolTip.delay: 500; ToolTip.text: (frow.modelData.location || []).join("/")
                                Accessible.role: Accessible.Link
                                Accessible.name: (frow.modelData.location || [])[0] || ""
                            }
                            HoverHandler { id: frh; cursorShape: frow.pickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler { enabled: frow.pickable; onTapped: pk.into(frow.modelData) }
                            Accessible.role: Accessible.Row
                            Accessible.name: qsTr("Folder %1").arg(modelData.name)
                        }
                    }
                }
                ListView {
                    visible: !pk.searching && !(pk.shown && pk.shown.people && !pk.person) && pk.place !== "more" && pk.view !== "tiles"
                    anchors { top: nfRowItem.bottom; topMargin: pk.newFolder ? 0 : 1.67; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: parent.parent.listItems
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: prow
                        required property var modelData
                        readonly property bool folder: modelData.is_folder && modelData.id !== (pk.target ? pk.target.id : "")
                        // List: 59 tall, a 32 px icon and the name over "n
                        // items" or the size (• a people glyph when shared);
                        // Compact List: 32 tall, a 20 px icon, plus File Size
                        // and Sharing columns.
                        readonly property bool compact: pk.view === "compact"
                        readonly property string sizeLine: modelData.is_folder ? (modelData.child_count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(modelData.child_count || 0)) : root.sizeText(modelData.size)
                        width: ListView.view.width; height: compact ? 32 : 59
                        color: folder && prh2.hovered ? theme.menuHover : "transparent"
                        opacity: folder ? 1 : 0.45
                        FluentIcon {
                            x: prow.compact ? 22 : 16; anchors.verticalCenter: parent.verticalCenter; size: prow.compact ? 20 : 32
                            name: prow.modelData.is_folder ? "ft-folder-32" : root.fileIcon(prow.modelData.kind)
                        }
                        Column {
                            x: 67; width: (prow.compact ? 300 : 270) - 20; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: prow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.ink) }
                            Row {
                                visible: !prow.compact
                                spacing: 4
                                Text { text: prow.sizeLine + (prow.modelData.sharing === "Shared" && !prow.modelData.is_folder ? " •" : ""); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(prow, root.ink) }
                                FluentIcon { visible: prow.modelData.sharing === "Shared" && !prow.modelData.is_folder; anchors.verticalCenter: parent.verticalCenter; name: "people-12"; size: 12; color: theme.onFill(prow, root.ink) }
                            }
                        }
                        Text { x: prow.compact ? 367 : 337; width: 150 - 12; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.modified_text || root.ago(prow.modelData.modified); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.strong) }
                        Text { x: prow.compact ? 517 : 507; width: 130; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.modified_by; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.strong) }
                        Text { visible: prow.compact; x: 667; width: 138; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.sizeLine; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.strong) }
                        Row {
                            visible: prow.compact; x: 817; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            FluentIcon { visible: prow.modelData.sharing === "Shared"; anchors.verticalCenter: parent.verticalCenter; name: "people-16"; size: 14; color: theme.onFill(prow, root.strong) }
                            Text { text: prow.modelData.sharing || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.strong) }
                        }
                        // List: Activity (a 14 px #0078D4 glyph, the text and
                        // its time in 14 px).
                        Row {
                            visible: !prow.compact && !pk.searching && !!prow.modelData.activity
                            x: 657; width: parent.width - 657 - 16; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 14; color: theme.onFill(prow, theme.hc("#0078D4", "#FFFFFF")); name: prow.modelData.activity ? root.activityIcon(prow.modelData.activity.kind) : "" }
                            Text {
                                width: parent.width - 18; elide: Text.ElideRight
                                text: prow.modelData.activity ? prow.modelData.activity.text + " " + prow.modelData.activity.time : ""
                                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(prow, root.strong)
                            }
                        }
                        HoverHandler { id: prh2; cursorShape: prow.folder ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: prow.folder; onTapped: pk.into(prow.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: (modelData.is_folder ? qsTr("Folder %1") : qsTr("File %1")).arg(modelData.name)
                    }
                }
                // Tiles: folders as in the OneDrive app's Tiles (176 x 171,
                // the drawing with its count, name and date); videos as
                // 304 x 171 pictures with the name and date on a dark
                // nameplate; other files as their 74 x 96 picture. Files
                // can't be picked (half opacity).
                Flickable {
                    visible: pk.view === "tiles" && !pk.searching && !(pk.shown && pk.shown.people && !pk.person) && pk.place !== "more"
                    anchors { top: pk.newFolder ? nfRowItem.bottom : parent.top; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true; contentHeight: pkTiles.height + 16
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Flow {
                        id: pkTiles
                        width: parent.width - 8; spacing: 8
                        Repeater {
                            model: pkBody.listItems
                            PickTile {}
                        }
                    }
                }
                Text {
                    visible: !!pk.shown && !pk.loading && pk.place !== "more" && (pk.shown.people ? (pk.person ? false : !pk.shown.people.some(p => p.items.length)) : (pk.shown.items || []).length === 0)
                    anchors.centerIn: parent
                    text: pk.shown && pk.shown.error ? pk.shown.error : pk.searching ? qsTr("We couldn't find any results") : pk.place === "favorites" && pk.inPlaceList ? qsTr("Items you favorite will show up here") : qsTr("This folder is empty")
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill(hcFill15, pk.shown && pk.shown.error ? theme.danger : root.ink)
                }
                BusyIndicator { anchors.centerIn: parent; running: pk.loading; visible: pk.loading }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24
                y: parent.height - 24 - 32; spacing: 8
                Rectangle {
                    id: hcFill18
                    readonly property bool ok: !!pk.shown && !!pk.shown.here && !pk.sameFolder && !pk.loading
                    width: hereText.implicitWidth + 24; height: 32; radius: 4
                    color: !ok ? theme.surface : hh.hovered ? theme.brandHover : theme.brandFill
                    border.width: ok ? 0 : 0.67; border.color: theme.pick("#EBEBEB", "#3D3D3D", "#FFFFFF")
                    Text { id: hereText; anchors.centerIn: parent; text: pk.shortcut ? qsTr("Select") : pk.moving ? qsTr("Move here") : qsTr("Copy here"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill18, parent.ok ? "white" : root.line) }
                    HoverHandler { id: hh; cursorShape: parent.ok ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: parent.ok; onTapped: pk.done() }
                    Accessible.role: Accessible.Button
                    Accessible.name: hereText.text
                }
                Rectangle {
                    id: hcFill19
                    width: 80; height: 32; radius: 4
                    color: ch2.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#7A7A7A", "#ADADAD", "#FFFFFF")
                    Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(hcFill19, root.ink) }
                    HoverHandler { id: ch2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel")
                }
            }
        }
    }

    /// Quick access's (i): "Frequently used team locations, including
    /// shared libraries and Teams channels."
    component InfoTip: FluentIcon {
        name: "info-16-regular"; size: 16; color: root.ink
        HoverHandler { id: ith }
        ToolTip.visible: ith.hovered; ToolTip.delay: 300
        ToolTip.text: qsTr("Frequently used team locations, including shared libraries and Teams channels.")
        Accessible.name: ToolTip.text
    }

    component PlaceRow: Rectangle {
        id: pr
        property string label
        property string icon
        property bool on: false
        property bool site: false
        /// A Quick access library: its tile and pin.
        property var lib: null
        signal picked()
        // Folded (the picker's rail): 36 x 36, the icon alone, the name as
        // a tooltip.
        readonly property bool folded: picker.navCollapsed
        x: 16; width: folded ? 36 : 190; height: 36; radius: 8
        color: prh.hovered ? theme.menuHover : "transparent"
        Rectangle { visible: pr.on; x: -16; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: root.accent }
        FluentIcon { visible: !pr.site; x: pr.folded ? 10 : 12; anchors.verticalCenter: parent.verticalCenter; name: pr.icon; size: 16; color: theme.onFill(pr, pr.on ? root.accent : root.strong) }
        Avatar { visible: pr.site && !pr.lib; x: 8; anchors.verticalCenter: parent.verticalCenter; size: 20; name: pr.label; square: true }
        SiteTile { visible: !!pr.lib; x: 8; anchors.verticalCenter: parent.verticalCenter; acronym: pr.lib ? pr.lib.acronym : ""; tint: pr.lib ? pr.lib.color : "" }
        ToolTip.visible: pr.folded && prh.hovered; ToolTip.delay: 300; ToolTip.text: pr.label
        Text {
            visible: !pr.folded
            x: 36; width: parent.width - 44 - (pr.lib ? 28 : 0); anchors.verticalCenter: parent.verticalCenter
            text: pr.label; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; font.weight: pr.on ? Font.DemiBold : Font.Normal; color: theme.onFill(pr, root.strong)
        }
        HoverHandler { id: prh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pr.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        // Pin to Quick access: 24 px at the row's right (16 px glyph),
        // shown on hover, and always (solid) once pinned.
        PinButton { visible: !!pr.lib && !pr.folded && (prh.hovered || pr.lib.pinned); x: 160; anchors.verticalCenter: parent.verticalCenter; lib: pr.lib }
    }

    component PinButton: Rectangle {
        id: pb
        property var lib: null
        width: 24; height: 24; radius: 4
        color: pbh.hovered ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : "transparent"
        readonly property bool pinned: !!lib && lib.pinned
        FluentIcon { anchors.centerIn: parent; name: pb.pinned ? "pin-16-filled" : "pin-16"; size: 16; color: theme.onFill(pb, root.ink) }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.pinLibrary(pb.lib, !pb.pinned) }
        ToolTip.visible: pbh.hovered; ToolTip.delay: 300
        ToolTip.text: lib ? (pinned ? qsTr("Unpin %1 from Quick access") : qsTr("Pin %1 to Quick access")).arg(lib.label) : ""
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Pin to Quick access")
    }

    component PickTile: Item {
        id: pt
        required property var modelData
        readonly property bool folder: modelData.is_folder && modelData.id !== (picker.target ? picker.target.id : "")
        readonly property bool wide: !modelData.is_folder && root.isVideo(modelData.kind)
        width: wide ? 304 : 176; height: 171
        opacity: folder ? 1 : 0.5
        FluentSurface { visible: pt.folder && pth.hovered; anchors.fill: parent; radius: 12; depth: 4; color: theme.surface }
        Item {
            visible: pt.modelData.is_folder
            x: 32; y: 24; width: 112; height: 80; clip: true
            FluentIcon { x: 0; y: -16; size: 112; name: "ft-folder-32" }
            Text { x: 14; y: 56; text: pt.modelData.child_count || 0; font.family: theme.font; font.pixelSize: 14; color: theme.hc("#8F3900", "#FFFFFF") }
        }
        Rectangle {
            visible: pt.wide
            anchors.fill: parent; radius: 12; clip: true; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000")
            Image { anchors.fill: parent; source: picker.thumbs[pt.modelData.id] || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Rectangle {
                y: parent.height - 76; width: parent.width; height: 76
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 0.2; color: "#32000000" }
                    GradientStop { position: 0.45; color: theme.hc("#8D000000", "#000000") }
                    GradientStop { position: 1; color: theme.hc("#A6000000", "#000000") }
                }
            }
            Text { x: 10; y: parent.height - 54; width: parent.width - 20; elide: Text.ElideRight; text: pt.modelData.name; font.family: theme.font; font.pixelSize: 14; color: "white" }
            Text { x: 10; y: parent.height - 32; text: pt.modelData.modified_text || root.ago(pt.modelData.modified); font.family: theme.font; font.pixelSize: 12; color: "white" }
        }
        Rectangle {
            visible: !pt.modelData.is_folder && !pt.wide
            x: 51; y: 16; width: 74; height: 96; radius: 4
            color: theme.surface; border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
            Image { id: ptImg; anchors.fill: parent; anchors.margins: 1; source: picker.thumbs[pt.modelData.id] || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            FluentIcon { visible: !ptImg.source.toString(); anchors.centerIn: parent; size: 32; name: root.fileIcon(pt.modelData.kind) }
        }
        Text {
            visible: !pt.wide
            x: 8; y: 117; width: parent.width - 16; height: 30
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            text: pt.modelData.name; font.family: theme.font; font.pixelSize: 14; color: root.ink
        }
        Text {
            visible: pt.modelData.is_folder
            x: 8; y: 141; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: pt.modelData.modified_text || root.ago(pt.modelData.modified); font.family: theme.font; font.pixelSize: 12; color: root.strong
        }
        Component.onCompleted: if (!modelData.is_folder) picker.wantThumb(modelData, wide ? "c304x171" : "medium")
        HoverHandler { id: pth; cursorShape: pt.folder ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: pt.folder; onTapped: picker.into(pt.modelData) }
        Accessible.role: Accessible.Button
        Accessible.name: (modelData.is_folder ? qsTr("Folder %1") : qsTr("File %1")).arg(modelData.name)
    }

    component PickHead: Item {
        property string label
        height: 48
        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
    }

    // OneDrive's file size wording: "1 byte", "56 bytes", "26.0 KB",
    // "7.66 MB" (two decimals under 10, one under 100, none above).
    function sizeText(n) {
        if (typeof n !== "number" || isNaN(n) || n < 0) return ""
        if (n === 1) return qsTr("1 byte")
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return qsTr("%1 bytes").arg(n)
        if (n < 1024e3) return qsTr("%1 KB").arg(f(n / 1024))
        if (n < 1048576e3) return qsTr("%1 MB").arg(f(n / 1048576))
        if (n < 1073741824e3) return qsTr("%1 GB").arg(f(n / 1073741824))
        return qsTr("%1 TB").arg(f(n / 1099511627776))
    }
    /// OneDrive's file-type icon (32 px drawings).
    function fileIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : t === "md" || t === "markdown" ? "md" : t === "html" || t === "htm" ? "html" : t === "whiteboard" ? "whiteboard"
                : t === "pbix" ? "powerbi" : isVideo(t) ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }
    // The Activity column's glyph (OneDrive: Edit, Comment, Reply, Share,
    // Accounts, Groupedlist).
    function activityIcon(kind) {
        return ({ edit: "edit-16", comment: "comment-16", commentResponse: "arrow-reply-16", share: "share-16",
                  mention: "mention-16", createTask: "task-list-ltr-20", completeTask: "task-list-ltr-20" })[kind] || "edit-16"
    }
    function isVideo(kind) { return ["mp4", "mov", "wmv", "avi", "mkv", "webm", "m4v"].indexOf(String(kind || "").toLowerCase()) >= 0 }

    function ago(t) {
        if (!t) return ""
        const d = new Date(t), s = (Date.now() - d) / 1000
        if (s < 60) return qsTr("A few seconds ago")
        if (s < 3600) return qsTr("%n minutes ago", "", Math.floor(s / 60))
        if (s < 86400) return qsTr("%n hours ago", "", Math.floor(s / 3600))
        const days = Math.floor(s / 86400)
        if (days < 7) return days === 1 ? qsTr("Yesterday") : qsTr("%n days ago", "", days)
        return theme.fmtDate(d, "MMMM d")
    }

    // OneDrive's share dialog (Share, Manage access, Copy link's Settings).
    OneDriveShare { id: share }

    // Test harness hooks
    function versionsForTest() { return { open: versions.opened, loading: versions.loading, error: versions.error, list: versions.list.map(v => [v.label, v.modified, v.size, v.by, v.current ? "current" : ""].join(" | ")) } }
    function versionRunForTest(label, action) { const v = versions.list.find(x => x.label === label); if (v) versions.run(v, action); return !!v }
    function menuForTest(it) { return itemsFor(it).map(i => i.separator ? "--" : i.label + (i.submenu ? " >" : "")) }
    function popupForTest(it) { popup(it, root, root.width / 2 - 108, 60) }
    function actForTest(it, label) { item = it; act(label) }
    function stateForTest() { return { menu: menu.opened, rename: renameDialog.opened, del: deleteDialog.opened, link: copyLink.opened, url: copyLink.url, picker: picker.opened, shown: picker.shown ? (picker.shown.items || []).length : -1, toast: toast.visible ? toast.title + (toast.detail ? ": " + toast.detail : "") : "" } }
    function pickerPlaceForTest(key) { if (key === "more" || ["shared", "favorites", "people", "meetings", "mine"].indexOf(key) >= 0) picker.openPlace(key, null) }
    function pickerStateForTest() {
        const sh = picker.shown || {}
        return { place: picker.place, trail: picker.trail.map(t => t.name), loading: picker.loading, searching: picker.searching, all: picker.searchAll,
                 items: (sh.items || []).map(i => i.name + (i.is_folder ? "/" : "") + (i.location ? " @" + i.location.join("›") : i.parent_name ? " @" + i.parent_name : "")),
                 dates: picker.dates, created: (sh.items || []).filter(i => i.created_by).length,
                 people: sh.people ? sh.people.map(p => p.name + ":" + p.items.length) : null, libraries: picker.libraries.length, error: sh.error || "" }
    }
    function pickerSearchForTest(q, all) { picker.search(q, all) }
    function pickerDatesForTest(key) { picker.dates = key; picker.search(picker.query, picker.searchAll) }
    function pickerDatesMenuForTest(open) { picker.datesMenuForTest(open) }
    function pickerLocationForTest(name) { const f = (picker.shown && picker.shown.items || []).find(i => i.name === name); if (f) picker.openLocation(f); return !!f }
    function pickerViewForTest(v) { picker.view = v }
    function pickerNavForTest(folded, browseOpen) { picker.navCollapsed = folded; picker.browseOpen = browseOpen }
    function pickerNewFolderForTest(name) { picker.createFolder(name) }
    function pickerIntoForTest(name) { const f = (picker.shown && picker.shown.items || []).find(i => i.name === name); if (f) picker.into(f); return !!f }
    function pickerDoneForTest() { picker.done() }
    function renameForTest(name) { nameInput.text = name; renameDialog.accepted() }
    function playlistsForTest() { return playlists }
    function pickerHookForTest() { return picker }
    function renameOpenForTest(it) { item = it; renameDialog.openFor(it) }
    function renameSuggestionsForTest() { return { offered: renameDialog.suggOffered, open: renameDialog.suggOpen, loading: renameDialog.suggLoading, confidential: renameDialog.suggConfidential, names: renameDialog.suggNames, error: renameDialog.suggError, height: renameDialog.height, name: nameInput.text } }
    function renameToggleSuggestionsForTest() { renameDialog.toggleSugg() }
    function renamePickSuggestionForTest(i) { if (renameDialog.suggNames[i]) { nameInput.text = renameDialog.suggNames[i]; renameDialog.suggOpen = false } }
    function renameResuggestForTest() { renameDialog.suggest() }
    function submenuForTest() { menu.openSubmenuForTest(0) }
    function fileRequestForTest(it, name) { fileRequest.openFor(it); frName.text = name; fileRequest.next() }
    function fileRequestStateForTest() { return { open: fileRequest.opened, step: fileRequest.step, url: fileRequest.url ? "(link)" : "", share_id: fileRequest.shareId } }
    function shortcutForTest(it, place) { addShortcut(it, place, place === "shortcuts" ? "Shortcuts" : "My files", {}) }
    function colorForTest(it, code) { item = it; backend.driveAction(tag + "folder_color", JSON.stringify(it), JSON.stringify({ code: code })) }
    function closeAllForTest() { menu.close(); fileRequest.close(); colorPicker.close(); renameDialog.close(); deleteDialog.close(); copyLink.close(); picker.close(); versions.close(); share.close(); playlists.close() }
    function shareOpenForTest() { return share.opened }
    function quickForTest() { return root.quickAccess.map(q => q.label + (q.pinned ? " (pinned)" : "") + (q.drive_id ? "" : " (no drive)")) }
    function pinForTest(label, pin) { const q = root.quickAccess.find(x => x.label === label); if (q) root.pinLibrary(q, pin); return !!q }
    function copyForTest() { root.copy(copyLink.url); copyLink.copied = true }
    function linkForTest() { return { kind: copyLink.kind, share_id: copyLink.shareId, ref: copyLink.target ? ref(copyLink.target) : null } }
}
