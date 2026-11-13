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
    property var item: null
    readonly property bool menuOpen: menu.opened

    // OneDrive's colours (Fluent, as its pages in Teams draw them).
    readonly property color ink: theme.pick("#616161", "#D6D6D6")
    readonly property color strong: theme.pick("#424242", "#D6D6D6")
    readonly property color accent: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color line: theme.pick("#D1D1D1", "#666666")

    readonly property var textKinds: ["txt", "md", "json", "xml", "log", "csv", "css", "js", "ts", "html", "htm", "yaml", "yml", "ini", "cfg"]
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
    function itemsFor(it) {
        const sp = !!it.sp_item
        const fav = root.favoriteIds.indexOf(it.id) >= 0
        const L = []
        if (!it.is_folder) {
            const text = textKinds.indexOf(it.kind) >= 0
            L.push({ label: "Open", icon: "open-16", submenu: [
                text ? { label: "Open in Text Editor", icon: "edit-16" } : { label: "Open in browser", icon: "globe-16" },
                { label: "Open in app", icon: "open-16" }] })
            L.push({ label: "Preview", icon: "full-screen-maximize-16" })
        }
        if (sp) L.push({ label: "Share", icon: "share-16" })
        if (sp || it.web_url) L.push({ label: "Copy link", icon: "link-16" })
        if (sp && it.is_folder && canWrite) L.push({ label: "Request files", icon: "folder-arrow-up-16" })
        if (sp) L.push({ label: "Manage access", icon: "person-16" })
        L.push({ separator: true })
        if (canWrite) L.push({ label: "Delete", icon: "delete-16" })
        // Graph's favorites (followed items) hold files, not folders.
        if (!it.is_folder) L.push({ label: fav ? "Remove from favorites" : "Add to favorites", icon: "star-16" })
        if (!it.is_folder && sp) L.push({ label: "Add shortcut", icon: "link-square-16", submenu: [{ label: "Shortcuts" }, { label: "My files" }, { label: "Other locations" }] })
        L.push({ label: "Download", icon: "arrow-download-16" })
        if (canWrite) L.push({ label: "Rename", icon: "rename-16" })
        // A team site's file opens in SharePoint (not yet seen in Teams).
        if (it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? "Open in OneDrive" : "Open in SharePoint", icon: "cloud-16" })
        if (canWrite && sp) L.push({ label: "Move to", icon: "folder-arrow-right-16" })
        if (sp) L.push({ label: "Copy to", icon: "copy-16" })
        if (canWrite && sp) L.push({ label: "Duplicate", icon: "add-square-16" })
        if (canWrite && sp && it.is_folder) L.push({ label: "Folder color", icon: "paint-bucket-16", flyout: true, dot: colorFor(it.folder_color).hex })
        if (!it.is_folder && sp) { L.push({ separator: true }); L.push({ label: "Version history", icon: "history-16" }) }
        if (sp) { L.push({ separator: true }); L.push({ label: "Details", icon: "info-16" }) }
        while (L.length && L[L.length - 1].separator) L.pop()
        return L
    }
    /// OneDrive's counted wording: "{0} item||{0} items".
    function count(n, one, many) { return (n === 1 ? one : many).replace("{0}", n) }
    /// Items acted on together (the selection), besides `item`.
    property var others: []
    /// How many the running job covers, for its notice.
    property int jobCount: 1
    /// The selection toolbar's actions on several items (Teams: Delete, Add
    /// to favorites, Download, then Duplicate, Move to and Copy to).
    function actMany(list, label) {
        if (!list.length) return
        if (list.length === 1) { item = list[0]; others = []; act(label); return }
        item = list[0]; others = list.slice(1)
        if (label === "Delete") deleteDialog.openForMany(list)
        else if (label === "Add to favorites") list.filter(i => !i.is_folder).forEach(i => favoriteItem(i, true))
        else if (label === "Download") zip(list)
        else if (label === "Move to") { picker.shortcut = false; picker.openFor(item, true) }
        else if (label === "Copy to") { picker.shortcut = false; picker.openFor(item, false) }
        else if (label === "Duplicate") {
            jobCount = list.length
            notice("progress", count(jobCount, "Copying {0} item", "Copying {0} items"))
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
        notice("progress", "Updating " + (lib.title || lib.label))
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
        notice("progress", "Preparing " + name + " for download. This can take a moment.")
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
                    border.width: current ? 2 : 0; border.color: theme.pick("#0F6CBD", "#479EF5")
                    Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: parent.modelData.hex }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            colorPicker.close(); menu.close()
                            backend.driveAction(root.tag + "folder_color", JSON.stringify(root.item), JSON.stringify({ code: parent.modelData.code }))
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name + (current ? " selected" : "")
                }
            }
        }
    }

    function act(label) {
        const it = root.item
        if (!it) return
        if (label === "Open in Text Editor" || label === "Open in browser" || label === "Open in OneDrive" || label === "Open in SharePoint") Qt.openUrlExternally(it.web_url)
        else if (label === "Open in app") { notice("progress", "Opening " + it.name); backend.driveAction(tag + "open_app", JSON.stringify(it), "{}") }
        else if (label === "Share") share.openFor(ref(it), it.name, it.kind)
        else if (label === "Manage access") share.openManage(ref(it), it.name, it.kind)
        else if (label === "Copy link") copyLink.start(it)
        else if (label === "Delete") deleteDialog.openFor(it)
        else if (label === "Add to favorites") favoriteItem(it, true)
        else if (label === "Remove from favorites") favoriteItem(it, false)
        else if (label === "Download") it.is_folder ? zip([it]) : downloadItem(it)
        else if (label === "Rename") renameDialog.openFor(it)
        else if (label === "Move to") { picker.shortcut = false; picker.openFor(it, true) }
        else if (label === "Copy to") { picker.shortcut = false; picker.openFor(it, false) }
        else if (label === "Version history") versions.openFor(it)
        else if (label === "Request files") fileRequest.openFor(it)
        else if (label === "Shortcuts") addShortcut(it, "shortcuts", "Shortcuts", {})
        else if (label === "My files") addShortcut(it, "myfiles", "My files", {})
        else if (label === "Other locations") { picker.shortcut = true; picker.openFor(it, false) }
        else if (label === "Details") detailsItem(it)
        else if (label === "Preview") previewItem(it)
        else if (label === "Duplicate") { jobCount = 1; notice("progress", "Copying 1 item"); backend.driveAction(tag + "duplicate", JSON.stringify(it), "{}") }
    }

    // The clipboard, without OST's own "Copied to clipboard" notice
    // (OneDrive says "Link copied" itself).
    TextEdit { id: copier; visible: false }
    function copy(text) { copier.text = text; copier.selectAll(); copier.copy() }

    // OneDrive's sixteen folder colours, in the picker's order, with their
    // codes and the shades its folder drawing uses (main, background,
    // accent, gradient start, gradient stop, count).
    readonly property var folderColors: [
        { code: "0", name: "Yellow", hex: "#FFCE3C", shades: ["#FFCE3C", "#F5B800", "#B64D07", "#FFE561", "#FFB515", "#8F3900"] },
        { code: "8", name: "Grey", hex: "#B0B7BA", shades: ["#B0B7BA", "#96A3A7", "#575757", "#BDBFBF", "#A0ADB2", "#361500"] },
        { code: "1", name: "Dark red", hex: "#E73E29", shades: ["#E73E29", "#D62E1F", "#590700", "#FF5028", "#C92828", "#000000"] },
        { code: "9", name: "Light red", hex: "#FFBCB2", shades: ["#FFBCB2", "#F58076", "#BD2113", "#FFC7BA", "#FF9191", "#910C00"] },
        { code: "2", name: "Dark orange", hex: "#EE7110", shades: ["#EE7110", "#E56000", "#6B2500", "#FF8E1D", "#DB5101", "#361500"] },
        { code: "10", name: "Light orange", hex: "#FFBF84", shades: ["#FFBF84", "#FF8E3D", "#A14200", "#FFC48A", "#FF8C4A", "#782E00"] },
        { code: "3", name: "Dark green", hex: "#3F9F4A", shades: ["#3F9F4A", "#33852C", "#053B00", "#5EB75A", "#1D8539", "#001404"] },
        { code: "11", name: "Light green", hex: "#8ED290", shades: ["#8ED290", "#5BC26B", "#0B6E1A", "#B6E6AC", "#62BD71", "#00520A"] },
        { code: "4", name: "Dark teal", hex: "#27938E", shades: ["#27938E", "#037D81", "#003133", "#3DB7AB", "#106E70", "#000000"] },
        { code: "12", name: "Light teal", hex: "#7AD1CD", shades: ["#7AD1CD", "#5DC6C9", "#07676B", "#94EBE2", "#5DB4B6", "#0E4E4E"] },
        { code: "5", name: "Dark blue", hex: "#1E84D0", shades: ["#1E84D0", "#036DC9", "#032F54", "#2F9ADE", "#0E6EC2", "#000000"] },
        { code: "13", name: "Light blue", hex: "#86C8F7", shades: ["#86C8F7", "#73B3EB", "#1F64A1", "#9FDAFF", "#6EB6F0", "#004881"] },
        { code: "6", name: "Dark purple", hex: "#9A61C7", shades: ["#9A61C7", "#7E54B8", "#370086", "#BC7ADD", "#7342AD", "#000000"] },
        { code: "14", name: "Light purple", hex: "#D4AFF6", shades: ["#D4AFF6", "#BA90F5", "#7A2AD2", "#E2BFFA", "#BD94EF", "#5915A1"] },
        { code: "7", name: "Dark pink", hex: "#CC53B4", shades: ["#CC53B4", "#BC4293", "#5C003D", "#E36DE3", "#BA3E91", "#000000"] },
        { code: "15", name: "Light pink", hex: "#F7AAE7", shades: ["#F7AAE7", "#ED87CB", "#B8148C", "#FFBEFF", "#F097D2", "#8F0069"] }
    ]
    function colorFor(code) { return folderColors.find(c => c.code === String(code || "0")) || folderColors[0] }

    MenuPopup {
        id: menu
        fabric: true
        onFlyoutRequested: (i, row) => {
            if (i < 0 || !row || items[i].label !== "Folder color") { colorPicker.close(); return }
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
            if (kind === "libraries") { picker.reply(kind, v, error); return }
            if (kind === "thumb") { if (!error && v && v.path) { const t = Object.assign({}, picker.thumbs); t[v.id] = v.path; picker.thumbs = t } return }
            if (kind === "quick_access") { if (!error) root.quickAccess = v || []; return }
            if (kind === "quick_pin") {
                const p = root.pendingPin || { title: "", pin: true }
                if (error) root.notice("error", p.title + (p.pin ? " wasn't pinned" : " wasn't unpinned"), error)
                else { root.quickAccess = v.items || root.quickAccess; root.notice("done", (p.pin ? "Pinned " : "Unpinned ") + p.title + (p.pin ? " to " : " from ") + "Quick access") }
                return
            }
            if (kind === "versions" || kind === "restore_version" || kind === "delete_version") { versions.reply(kind, v, error); return }
            if (kind === "shortcut") {
                const p = root.pendingShortcut || { name: "", place: "" }
                if (error) root.notice("error", "Something went wrong so we couldn't add " + p.name + " as a shortcut to " + p.place + ".", error)
                else root.notice("done", "Added " + p.name + " as a shortcut to " + p.place + ".")
                return
            }
            if (kind === "folder_color") {
                if (error) root.notice("error", "The folder color wasn't changed", error)
                else root.changed()
                return
            }
            if (kind === "file_request") { fileRequest.reply(kind, v, error); return }
            if (kind === "zip") {
                if (error) root.notice("error", "Couldn't download " + root.lastZip + ". Try again.", error)
                else root.notice("done", v.name + " was downloaded.")
                return
            }
            if (kind === "open_app") {
                if (error) root.notice("error", "The file couldn't be opened", error)
                else { toast.visible = false; Qt.openUrlExternally("file://" + v.path) }
                return
            }
            // OneDrive's strings: "Moved {0} item||Moved {0} items", "{0} item
            // wasn't moved||{0} items weren't moved", and so on.
            const n = kind === "rename" ? 1 : root.jobCount
            const words = { rename: ["Renamed {0} item", "Renamed {0} items", "{0} item wasn't renamed", "{0} items weren't renamed"],
                            move: ["Moved {0} item", "Moved {0} items", "{0} item wasn't moved", "{0} items weren't moved"],
                            copy: ["Copied {0} item", "Copied {0} items", "{0} item wasn't copied", "{0} items weren't copied"],
                            duplicate: ["Copied {0} item", "Copied {0} items", "{0} item wasn't copied", "{0} items weren't copied"] }[kind]
            if (!words) return
            if (error) root.notice("error", root.count(n, words[2], words[3]), error)
            else { root.notice("done", root.count(n, words[0], words[1])); root.changed() }
        }
    }

    // OneDrive's notice under the list: 390 wide, #292929, radius 4,
    // padding 12; a 20 px state glyph, the text (13/17 #F0F0F0) at 48 and
    // a 24 px dismiss; 23 above the view's bottom.
    function notice(state, title, detail) {
        toast.state2 = state; toast.title = title; toast.detail = detail || ""
        toast.visible = true
        hideTimer.restart()
    }
    Rectangle {
        id: toast
        property string state2: "done"
        property string title
        property string detail
        visible: false
        z: 10
        width: 390; height: Math.max(48, toastText.implicitHeight + 24)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 23 - height
        radius: 4; color: "#292929"
        FluentIcon {
            x: 12; y: 14; size: 20
            name: toast.state2 === "error" ? "dismiss-circle-20-filled" : toast.state2 === "progress" ? "arrow-sync-20" : "checkmark-circle-20-filled"
            color: toast.state2 === "error" ? "#F1707B" : toast.state2 === "progress" ? "#F0F0F0" : "#92C353"
        }
        Column {
            id: toastText
            x: 48; y: 12; width: 294
            topPadding: 3.5
            Text { width: parent.width; wrapMode: Text.Wrap; text: toast.title; font.family: theme.font; font.pixelSize: 13; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: "#F0F0F0" }
            Text { visible: !!toast.detail; width: parent.width; topPadding: 4; wrapMode: Text.Wrap; text: toast.detail; font.family: theme.font; font.pixelSize: 13; lineHeight: 17; lineHeightMode: Text.FixedHeight; color: "#F0F0F0" }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12; y: 12
            width: 24; height: 24; radius: 4
            color: dth.hovered ? "#3D3D3D" : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 14; color: "#7F85F5" }
            HoverHandler { id: dth; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: toast.visible = false }
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"
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
            x: parent.width - 24 - 32; y: 24; width: 32; height: 31.33; radius: 4
            color: dch.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: root.strong }
            HoverHandler { id: dch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Item { id: bodyArea; x: 24; y: 24 + 31.33; width: 392; height: dlg.bodyHeight }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24
            y: parent.height - 24 - 32
            spacing: 8
            OdspButton { label: dlg.okText; enabled2: dlg.okEnabled; onClicked: dlg.accepted() }
            OdspButton { label: "Cancel"; onClicked: dlg.close() }
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
            if (err) { root.notice("error", kind === "restore_version" ? "The version wasn't restored" : "The version wasn't deleted", err); return }
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
                text: "Version history"
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: root.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Rectangle {
                x: parent.width - 24 - 32; y: 24; width: 32; height: 31.33; radius: 4
                color: vch.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: root.strong }
                HoverHandler { id: vch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: versions.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Close"
            }
            FluentSurface {
                id: vcard
                x: 24; y: 24 + 31.33 + 8.33 + 2; width: parent.width - 48; height: 316
                depth: 4; radius: 4; color: theme.surface
                readonly property real rest: width - 100
                readonly property var cols: [100, rest * 0.4, rest * 0.2, rest * 0.4]
                Item {
                    width: parent.width; height: 46
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.pick("#F0F0F0", "#3D3D3D") }
                    Row {
                        Repeater {
                            model: ["Version", "Modified", "Size", "Modified By"]
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
                            font.family: theme.font; font.pixelSize: 16; color: root.ink
                            font.underline: vlh.hovered
                            HoverHandler { id: vlh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: versions.run(vrow.modelData, "Open File") }
                            Accessible.role: Accessible.Link
                            Accessible.name: "Version " + vrow.modelData.label
                        }
                        Rectangle {
                            id: vmore
                            visible: vrow.hot
                            x: 63; y: 9; width: 28; height: 28; radius: 2
                            color: vmh.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-16"; size: 16; color: theme.pick("#605E5C", "#D6D6D6") }
                            HoverHandler { id: vmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: vmenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Show more actions for this item"
                            MenuPopup {
                                id: vmenu
                                fabric: true; fabricWidth: 232
                                x: 3.5; y: parent.height + 4
                                items: vrow.modelData.current ? [{ label: "Open File", icon: "open-16" }]
                                    : [{ label: "Open File", icon: "open-16" }, { label: "Restore", icon: "arrow-undo-16" }, { label: "Delete Version", icon: "delete-16" }]
                                onPicked: i => versions.run(vrow.modelData, items[i].label)
                            }
                        }
                        Row {
                            x: 100; height: parent.height
                            Text { width: vcard.cols[1]; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.modified; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: vrow.cell }
                            Text { width: vcard.cols[2]; leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.size; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: vrow.cell }
                            Item {
                                width: vcard.cols[3]; height: 46
                                Avatar { x: 8; y: 11; size: 24; name: vrow.modelData.by; photoId: vrow.modelData.by_oid }
                                Text { x: 48; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter; text: vrow.modelData.by; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 14; color: vrow.cell }
                            }
                        }
                        HoverHandler { id: vrh }
                        Accessible.role: Accessible.Row
                        Accessible.name: "Version " + modelData.label + ", " + modelData.modified + ", " + modelData.size + ", " + modelData.by
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
            if (error) { root.notice("error", step === 1 ? "Something went wrong, please try again" : "Send file request email failed.", error); return }
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
                text: fileRequest.step === 1 ? "Request files for this folder" : "Send file request"
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
                    Text { text: "Let the recipients know which files you're requesting."; font.family: theme.font; font.pixelSize: 14; color: root.ink }
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
                        Text { visible: !frName.text; text: "Enter a description"; color: theme.textTertiary; font: frName.font }
                        Accessible.name: "Let the recipients know which files you're requesting."
                    }
                }
                Row {
                    visible: fileRequest.tried && !frName.text.trim()
                    spacing: 4; height: 18
                    FluentIcon { y: 2; size: 12; name: "error-circle-12"; color: "#BC2F32" }
                    Text { text: "Please type a name for the request."; font.family: theme.font; font.pixelSize: 12; color: "#BC2F32" }
                }
                Item { width: 1; height: 12 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Recipients will only see the file description you've entered and can only upload files to this folder."; font.family: theme.font; font.pixelSize: 12; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: root.strong }
                Item { width: 1; height: 80 }
                Row {
                    anchors.right: parent.right; spacing: 8
                    OdspButton { label: fileRequest.busy ? "…" : "Next"; onClicked: fileRequest.next() }
                    OdspButton { label: "Cancel"; onClicked: fileRequest.close() }
                }
            }
            // Step 2: the link, and sending it.
            Column {
                visible: fileRequest.step === 2
                width: parent.width; topPadding: 18; spacing: 0
                Text { height: 30; verticalAlignment: Text.AlignVCenter; text: "Here's the link people can use to upload files"; font.family: theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; color: root.ink }
                Item { width: 1; height: 5 }
                Rectangle {
                    width: 418; height: 34; color: theme.surface
                    border.width: 0.67; border.color: theme.pick("#BDBDBD", "#666666")
                    TextInput {
                        x: 9; width: 300; anchors.verticalCenter: parent.verticalCenter
                        readOnly: true; selectByMouse: true; clip: true
                        text: fileRequest.url
                        font.family: theme.font; font.pixelSize: 12; color: root.ink
                        Accessible.name: "Link"
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 0.67; y: 0.67; width: 98.75; height: 32.67
                        color: crh.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
                        Rectangle { width: 1; height: parent.height; color: theme.pick("#A19F9D", "#666666") }
                        Text { anchors.centerIn: parent; text: fileRequest.copied ? "Copied" : "Copy link"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#7F85F5" }
                        HoverHandler { id: crh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.copy(fileRequest.url); fileRequest.copied = true } }
                        Accessible.role: Accessible.Button
                        Accessible.name: fileRequest.copied ? "Link copied" : "Copy link"
                    }
                }
                Row {
                    topPadding: 8; spacing: 5; height: 30
                    FluentIcon { y: 10; size: 14; name: "folder-arrow-up-16"; color: root.strong }
                    Text { y: 8; text: "Anyone with the link can upload files"; font.family: theme.font; font.pixelSize: 12; color: root.strong }
                }
                Item { width: 1; height: 32 }
                Text { text: "Or you can send it via email"; font.family: theme.font; font.pixelSize: 15; color: root.ink }
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
                                color: theme.pick("#F0F0F0", "#3D3D3D")
                                Text { id: pn; x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.DisplayText; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                                FluentIcon { x: pn.x + pn.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "dismiss-12"; color: root.ink }
                                TapHandler { onTapped: fileRequest.picked = fileRequest.picked.filter((p, i) => i !== parent.index) }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove " + modelData.DisplayText
                            }
                        }
                        TextInput {
                            id: frTo
                            width: Math.max(200, toFlow.width - 20); height: 28
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                            onTextChanged: fileRequest.search(text)
                            Text { visible: !frTo.text && !fileRequest.picked.length; anchors.verticalCenter: parent.verticalCenter; text: "To: Name, group, or email"; color: root.ink; font: frTo.font }
                            Accessible.name: "To: Name, group, or email"
                        }
                    }
                }
                // Suggestions
                Column {
                    width: parent.width
                    Repeater {
                        model: fileRequest.found.slice(0, 6)
                        Rectangle {
                            required property var modelData
                            width: parent.width; height: 40
                            color: sgh.hovered ? theme.menuHover : "transparent"
                            Avatar { x: 8; y: 6; size: 28; name: parent.modelData.DisplayText; photoId: parent.modelData.EntityData && parent.modelData.EntityData.ObjectId ? "8:orgid:" + parent.modelData.EntityData.ObjectId : "" }
                            Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.DisplayText + (parent.modelData.Description ? "  " + parent.modelData.Description : ""); font.family: theme.font; font.pixelSize: 14; color: root.ink; elide: Text.ElideRight; width: parent.width - 52 }
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
                        Text { visible: !frMessage.text; text: "Message..."; color: root.ink; font: frMessage.font }
                        Accessible.name: "Add message"
                    }
                }
                Item { width: 1; height: 47 }
                Row {
                    anchors.right: parent.right
                    OdspButton {
                        label: fileRequest.busy ? "…" : fileRequest.picked.length ? "Send" : "Done"
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
                anchors.right: parent.right; width: 32; height: 31.33; radius: 4
                color: fdh.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: root.strong }
                HoverHandler { id: fdh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: frDone.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Close"
            }
            Column {
                y: 39.33; width: parent.width; spacing: 0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44; height: 44; radius: 22; color: "#107C10"
                    FluentIcon { anchors.centerIn: parent; name: "checkmark-20"; size: 20; color: "white" }
                }
                Item { width: 1; height: 16 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: frDone.sent ? "Your file request was sent!" : "Your file request was created!"
                    font.family: theme.font; font.pixelSize: 21; color: root.ink
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }
                Item { width: 1; height: 11 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "We will notify you when someone uploads files."
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
        color: !enabled2 ? theme.pick("#F0F0F0", "#3D3D3D") : obh.hovered ? theme.brandHover : theme.brandFill
        Text {
            id: obText
            anchors.centerIn: parent
            text: ob.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: ob.enabled2 ? "white" : theme.pick("#BDBDBD", "#5C5C5C")
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
        title: "Rename"; okText: "Update"
        // 240 tall, as Teams' Rename without Copilot's Suggested names.
        bodyHeight: 128.67
        okEnabled: nameInput.text.trim().length > 0
        function openFor(it) {
            target = it
            const dot = it.is_folder ? -1 : it.name.lastIndexOf(".")
            ext = dot > 0 ? it.name.slice(dot) : ""
            nameInput.text = dot > 0 ? it.name.slice(0, dot) : it.name
            open()
            nameInput.selectAll(); nameInput.forceActiveFocus()
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
            color: theme.pick("#FFFFFF", "#292929")
            border.width: 0.67; border.color: root.line
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: nameInput.activeFocus ? 2 : 0.67; radius: 1; color: nameInput.activeFocus ? root.accent : root.strong }
            TextInput {
                id: nameInput
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                selectByMouse: true
                Keys.onReturnPressed: renameDialog.accepted()
                Accessible.name: "Name"
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
    }

    // Delete?: "Are you sure you want to send this item to the recycle bin?"
    OdspDialog {
        id: deleteDialog
        property var target: null
        property var targets: []
        title: "Delete?"; okText: "Delete"
        bodyHeight: 128.67
        function openFor(it) { target = it; targets = [it]; open() }
        function openForMany(list) { target = list[0]; targets = list; open() }
        onAccepted: { close(); targets.forEach(t => root.deleteItem(t)) }
        Text {
            y: 22.67; width: parent.width
            wrapMode: Text.Wrap
            text: deleteDialog.targets.length > 1 ? "Are you sure you want to send these items to the recycle bin?"
                : "Are you sure you want to send this item to the recycle bin?"
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
            if (!it.sp_item) { url = it.web_url; sentence = "People with existing access can use the link"; busy = false; open(); return }
            backend.shareAction(root.tag + "info", JSON.stringify(root.ref(it)), "{}")
        }
        Connections {
            target: backend
            function onShareDone(op, result, error) {
                if (!op.startsWith(root.tag) || !copyLink.target) return
                const kind = op.slice(root.tag.length)
                const v = result ? JSON.parse(result) : null
                if (error) { copyLink.busy = false; root.notice("error", "The link wasn't created", error); return }
                if (kind === "info") {
                    const can = v.default_edit ? "edit" : "view"
                    if (v.default_existing) {
                        copyLink.url = v.direct_url
                        copyLink.sentence = "People with existing access can use the link"
                        copyLink.busy = false; copyLink.open()
                        return
                    }
                    copyLink.sentence = v.default_scope === 0 ? "Anyone with the link can " + can
                        : v.default_scope === 1 ? "People in " + v.tenant + " with the link can " + can
                        : "Only the people you specified can " + can
                    copyLink.kind = v.default_scope === 0 ? (v.default_edit ? 5 : 4) : v.default_scope === 1 ? (v.default_edit ? 3 : 2) : 6
                    backend.shareAction(root.tag + "link", JSON.stringify(root.ref(copyLink.target)), JSON.stringify({ scope: v.default_scope, edit: v.default_edit }))
                } else if (kind === "link") {
                    copyLink.url = v.url; copyLink.shareId = v.share_id || ""; copyLink.busy = false; copyLink.open()
                }
            }
        }
        Row {
            x: 24; y: 24; height: 32; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "checkmark-circle-16"; size: 16; color: theme.pick("#107C10", "#54B054") }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: copyLink.copied ? "Link copied" : "Link created"
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
        Rectangle {
            x: parent.width - 24 - 32; y: 24; width: 32; height: 32; radius: 2
            color: clch.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 14; color: root.ink }
            HoverHandler { id: clch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: copyLink.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Item {
            visible: !copyLink.copied
            x: 24; y: 56; width: 432; height: 32
            Rectangle {
                width: 358.05; height: 32; radius: 4
                color: theme.pick("#FFFFFF", "#292929"); border.width: 0.67; border.color: root.line
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.strong }
                // The link from its start, cut with "..." as OneDrive's box shows it.
                Text {
                    x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                    text: copyLink.url; elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Link created"
                }
            }
            Rectangle {
                x: 358.05; width: 73.95; height: 32; radius: 2
                color: cpb.hovered ? theme.menuHover : theme.surface
                border.width: 0.67; border.color: theme.pick("#7A7A7A", "#ADADAD")
                Text { anchors.centerIn: parent; text: "Copy"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                HoverHandler { id: cpb; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.copy(copyLink.url); copyLink.copied = true } }
                Accessible.role: Accessible.Button
                Accessible.name: "Copy"
            }
        }
        Item {
            x: 24; y: copyLink.copied ? 64.67 : 96.67; width: 432; height: 17.33
            Text { y: 0.67; text: copyLink.sentence; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 4; spacing: 4
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "settings-16"; size: 14; color: root.accent }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Settings"; font.family: theme.font; font.pixelSize: 14; color: root.accent }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { copyLink.close(); share.openLinkSettingsFor(root.ref(copyLink.target), copyLink.target.name, copyLink.target.kind) } }
                Accessible.role: Accessible.Button
                Accessible.name: "Sharing settings"
            }
        }
    }

    MovePicker { id: picker }

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
        background: Rectangle { color: theme.pick("#F5F5F5", "#141414"); radius: 4 }
        function openFor(it, move) {
            target = it; moving = move; place = "mine"; shown = null
            root.jobCount = 1 + root.others.length
            trail = [{ name: "My files", drive_id: "", item_id: "" }]
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
        readonly property var viewItems: [{ label: "List", icon: "list-16", checked: view === "list" },
                                          { label: "Compact List", icon: "text-align-left-16", checked: view === "compact" },
                                          { label: "Tiles", icon: "grid-16", checked: view === "tiles" }]
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
        property bool newFolder: false
        /// People: the person picked.
        property string person: ""
        readonly property var placeTitles: ({ shared: "Shared with you", favorites: "Favorites", people: "People", meetings: "Meetings", more: "Shared libraries" })
        readonly property bool inPlaceList: ["shared", "favorites", "people", "meetings", "more"].indexOf(place) >= 0 && trail.length <= 1
        function search(q, all) {
            query = q; searchAll = all; searching = true; loading = true
            if (pkSearch.text !== q) pkSearch.text = q
            ask("picker_search", { query: q, all: all })
        }
        function createFolder(name) {
            if (!name.trim() || !shown) return
            newFolder = false; loading = true
            ask("picker_new_folder", { drive_id: shown.drive_id || "", item_id: shown.item_id || "", name: name.trim() })
        }
        function reply(kind, v, error) {
            if (kind === "libraries") { libraries = v || []; return }
            loading = false
            if (kind === "picker_new_folder") { if (error) root.notice("error", "The folder wasn't created", error); else into(v); return }
            // The service's own text (an HTTP status and address) is in the
            // log; the list says what OneDrive says.
            if (error) { shown = { drive_id: "", item_id: "", items: [], error: "Sorry, something went wrong." }; return }
            if (kind === "picker_search") { if (v.query === query) shown = { drive_id: "", item_id: "", items: v.items, search: true }; return }
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
            trail = [{ name: lib ? lib.name : "My files", drive_id: lib ? lib.drive_id : "", item_id: "" }]
            load(lib ? lib.drive_id : "", "")
        }
        function done() {
            if (!shown || !shown.here || sameFolder) return
            if (shortcut) {
                const place = trail.length ? trail[trail.length - 1].name : "My files"
                close()
                root.addShortcut(target, "folder", place, { site: shown.here.sp_site, drive_id: shown.drive_id || shown.here.drive_id, folder: shown.item_id ? shown.here.sp_item : "" })
                return
            }
            const op = moving ? "move" : "copy"
            root.notice("progress", root.count(root.jobCount, moving ? "Moving {0} item" : "Copying {0} item", moving ? "Moving {0} items" : "Copying {0} items"))
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
                x: 16; y: 18; width: pk.navCollapsed ? 36 : 190; height: 36; radius: 4
                color: pk.navCollapsed && nph.hovered ? theme.menuHover : "transparent"
                Text {
                    visible: !pk.navCollapsed
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    text: pk.shortcut ? "Pick a folder" : pk.moving ? "Move to" : "Copy to"
                    font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                FluentIcon {
                    visible: pk.navCollapsed || nph.hovered
                    x: pk.navCollapsed ? 8 : parent.width - 30; anchors.verticalCenter: parent.verticalCenter
                    name: pk.navCollapsed ? "panel-left-expand-20" : "panel-left-contract-20"; size: 20; color: root.ink
                }
                HoverHandler { id: nph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pk.navCollapsed = !pk.navCollapsed }
                Accessible.role: Accessible.Button
                Accessible.name: "Navigation Pane"
            }
            Column {
                y: 58; width: parent.width
                PlaceRow { label: "My files"; icon: "folder-16"; on: pk.place === "mine"; onPicked: pk.openPlace("mine", null) }
                PlaceRow { label: "Shared"; icon: "people-16"; on: pk.place === "shared"; onPicked: pk.openPlace("shared", null) }
                PlaceRow { label: "Favorites"; icon: "star-16"; on: pk.place === "favorites"; onPicked: pk.openPlace("favorites", null) }
                Item { width: 1; height: 8 }
                // "Browse by" (36 tall) folds People and Meetings; its
                // chevron shows on hover (down while open, up while folded),
                // and always on the folded rail.
                Rectangle {
                    x: 16; width: pk.navCollapsed ? 36 : 190; height: 36; radius: 4
                    color: pk.navCollapsed && bbh.hovered ? theme.menuHover : "transparent"
                    Text { visible: !pk.navCollapsed; x: 8; anchors.verticalCenter: parent.verticalCenter; text: "Browse by"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    FluentIcon {
                        visible: pk.navCollapsed || bbh.hovered
                        x: pk.navCollapsed ? 10 : parent.width - 28; anchors.verticalCenter: parent.verticalCenter
                        name: pk.browseOpen ? "chevron-down-16" : "chevron-up-16"; size: 16; color: root.ink
                    }
                    HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.browseOpen = !pk.browseOpen }
                    ToolTip.visible: bbh.hovered; ToolTip.delay: 300; ToolTip.text: "Browse by"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Browse by"
                }
                PlaceRow { visible: pk.browseOpen; label: "People"; icon: "person-16"; on: pk.place === "people"; onPicked: pk.openPlace("people", null) }
                PlaceRow { visible: pk.browseOpen; label: "Meetings"; icon: "calendar-ltr-16"; on: pk.place === "meetings"; onPicked: pk.openPlace("meetings", null) }
                Item { width: 1; height: 16 }
                // "Quick access" with its (i): "Frequently used team
                // locations, …"; each library has a pin on hover (solid and
                // always shown once pinned). Folded, a 36-wide line.
                Row {
                    x: 24; height: 18.67; spacing: 8; visible: root.quickAccess.length > 0 && !pk.navCollapsed
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Quick access"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    InfoTip { anchors.verticalCenter: parent.verticalCenter }
                }
                Item {
                    visible: root.quickAccess.length > 0 && pk.navCollapsed; width: parent.width; height: 18.67
                    Rectangle { x: 16; y: 9; width: 36; height: 1; color: theme.pick("#D1D1D1", "#3D3D3D") }
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
                    visible: pk.navCollapsed
                    x: 16; width: 36; height: 36; radius: 4
                    color: mph2.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: root.accent }
                    HoverHandler { id: mph2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.openPlace("more", null) }
                    ToolTip.visible: mph2.hovered; ToolTip.delay: 300; ToolTip.text: "More places..."
                    Accessible.role: Accessible.Link
                    Accessible.name: "More places..."
                }
                Text {
                    visible: !pk.navCollapsed
                    x: 32; height: 24; verticalAlignment: Text.AlignVCenter
                    text: "More places..."
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
                ? (pk.person ? (pk.shown.people.find(p => p.name === pk.person) || { items: [] }).items : [])
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
                    Accessible.name: "Back"
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Search results"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: root.ink }
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
                            text: pk.place === "mine" || !pk.inPlaceList ? "Search in " + (pk.trail.length ? pk.trail[pk.trail.length - 1].name : "My files") : "Search in all files"
                            color: theme.textTertiary; font: pkSearch.font; elide: Text.ElideRight; width: parent.width
                        }
                        Accessible.name: "Search"
                    }
                    FluentIcon {
                        visible: !!pkSearch.text
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: root.strong
                        TapHandler { onTapped: { pkSearch.text = ""; if (pk.searching) { pk.searching = false; pk.back(pk.trail.length - 1) } } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Clear search"
                    }
                }
                Rectangle {
                    visible: !pk.inPlaceList && !pk.searching && !!pk.shown && !!pk.shown.here
                    width: nfRow.implicitWidth + 16; height: 32; radius: 4
                    color: nfh.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: root.line
                    Row { id: nfRow; anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder-add-20"; size: 16; color: root.strong }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "New folder"; font.family: theme.font; font.pixelSize: 14; color: root.ink } }
                    HoverHandler { id: nfh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { pk.newFolder = true; nfName.text = "New folder"; nfName.selectAll(); nfName.forceActiveFocus() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "New folder"
                }
                // The view switch (48 x 40): the view's glyph and a chevron;
                // its menu (172 wide) ticks List, Compact List or Tiles.
                Rectangle {
                    visible: !(pk.place === "more" && !pk.searching) && !(pk.shown && pk.shown.people && !pk.person)
                    width: 48; height: 32; radius: 4
                    color: vsh.hovered || vsMenu.opened ? theme.menuHover : "transparent"
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: pk.view === "tiles" ? "grid-16" : pk.view === "compact" ? "text-align-left-16" : "list-16"; size: 16; color: root.ink }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: root.ink }
                    }
                    HoverHandler { id: vsh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: vsMenu.open() }
                    ToolTip.visible: vsh.hovered && !vsMenu.opened; ToolTip.delay: 300; ToolTip.text: "View options"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Switch view options"
                    MenuPopup {
                        id: vsMenu; fabric: true; fabricWidth: 172
                        x: parent.width - 172; y: parent.height + 4
                        items: pk.viewItems
                        onPicked: i => pk.view = ["list", "compact", "tiles"][i]
                    }
                }
            }
            // All files / My files under the results' title.
            Row {
                visible: pk.searching
                x: 23; y: 58; spacing: 24
                Repeater {
                    model: [{ label: "All files", all: true }, { label: "My files", all: false }]
                    Text {
                        required property var modelData
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: 14; font.weight: pk.searchAll === modelData.all ? Font.DemiBold : Font.Normal; color: root.ink
                        Rectangle { visible: pk.searchAll === parent.modelData.all; anchors.top: parent.bottom; anchors.topMargin: 4; width: parent.width; height: 2; radius: 1; color: root.accent }
                        TapHandler { onTapped: pk.search(pk.query, parent.modelData.all) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: text
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
                x: 16.67; y: 74.67; width: parent.width - 16.67 - 31.33; height: parent.height - y - 80 - 8
                // Tiles drop the white card, as in Teams.
                radius: 12; color: pk.view === "tiles" && !pkMore.visible && !(pk.shown && pk.shown.people && !pk.person) ? "transparent" : theme.surface; clip: true
                // Header: Type, Name, Modified, Modified By (14/600, 48 tall).
                Row {
                    id: pkHead
                    visible: !pkMore.visible && pk.view !== "tiles"
                    height: 48
                    Item { width: 55; height: 48; FluentIcon { x: 22; anchors.verticalCenter: parent.verticalCenter; name: "document-16"; size: 16; color: root.strong } }
                    PickHead { width: pk.view === "compact" ? 300 : 270; label: "Name" }
                    PickHead { width: pk.view === "compact" ? 150 : 170; label: "Modified" }
                    PickHead { width: 150; label: "Modified By" }
                    PickHead { visible: pk.view === "compact"; width: 150; label: "File Size" }
                    PickHead { visible: pk.view === "compact"; width: 170; label: "Sharing" }
                    PickHead { visible: pk.searching; width: 150; label: "Location" }
                    PickHead { visible: pk.view === "list" && !pk.searching; width: 200; label: "Activity" }
                }
                Rectangle { visible: pkHead.visible; y: 48.67; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333") }
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
                            Accessible.name: "New folder name"
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
                        required property var modelData
                        width: ListView.view.width; height: 59
                        color: pph2.hovered ? theme.menuHover : "transparent"
                        Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: parent.modelData.name }
                        Column {
                            x: 67; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            Text { text: parent.parent.modelData.items.length + (parent.parent.modelData.items.length === 1 ? " folder" : " folders"); font.family: theme.font; font.pixelSize: 12; color: root.ink }
                        }
                        HoverHandler { id: pph2; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { pk.person = parent.modelData.name; pk.trail = pk.trail.slice(0, 1).concat([{ name: parent.modelData.name, place: true }]) } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Folders from " + modelData.name
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
                            model: ["Recent", "Your Teams"]
                            // Recent: Quick access's libraries; Your Teams:
                            // your teams' default libraries.
                            Column {
                                required property string modelData
                                width: moreCol.width; spacing: 12
                                Text { text: parent.modelData; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: root.ink }
                                Flow {
                                    width: parent.width; spacing: 16
                                    Repeater {
                                        model: parent.parent.modelData === "Recent"
                                            ? root.quickAccess.map(q => ({ site: q.site_title, name: q.title, drive_id: q.drive_id, acronym: q.acronym, color: q.color }))
                                            : pk.libraries
                                        Rectangle {
                                            required property var modelData
                                            width: Math.min(316, (moreCol.width - 16) / 2); height: 58; radius: 4
                                            color: lch.hovered ? theme.menuHover : theme.surface
                                            border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
                                            SiteTile { visible: !!parent.modelData.color; x: 9; anchors.verticalCenter: parent.verticalCenter; size: 40; acronym: parent.modelData.acronym || ""; tint: parent.modelData.color || "" }
                                            Avatar { visible: !parent.modelData.color; x: 9; anchors.verticalCenter: parent.verticalCenter; size: 40; name: parent.modelData.site; square: true }
                                            Column {
                                                x: 62; width: parent.width - 70; anchors.verticalCenter: parent.verticalCenter
                                                Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.site; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                                                Text { visible: parent.parent.modelData.name !== "Documents"; width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: 12; color: root.strong }
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
                ListView {
                    visible: !(pk.shown && pk.shown.people && !pk.person) && !(pk.place === "more" && !pk.searching) && pk.view !== "tiles"
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
                        readonly property string sizeLine: modelData.is_folder ? (modelData.child_count === 1 ? "1 item" : (modelData.child_count || 0) + " items") : root.sizeText(modelData.size)
                        width: ListView.view.width; height: compact ? 32 : 59
                        color: folder && prh2.hovered ? theme.menuHover : "transparent"
                        opacity: folder ? 1 : 0.45
                        FluentIcon {
                            x: prow.compact ? 22 : 16; anchors.verticalCenter: parent.verticalCenter; size: prow.compact ? 20 : 32
                            name: prow.modelData.is_folder ? "ft-folder-32" : root.fileIcon(prow.modelData.kind)
                        }
                        Column {
                            x: 67; width: (prow.compact ? 300 : 270) - 20; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: prow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            Row {
                                visible: !prow.compact
                                spacing: 4
                                Text { text: prow.sizeLine + (prow.modelData.sharing === "Shared" && !prow.modelData.is_folder ? " •" : ""); font.family: theme.font; font.pixelSize: 12; color: root.ink }
                                FluentIcon { visible: prow.modelData.sharing === "Shared" && !prow.modelData.is_folder; anchors.verticalCenter: parent.verticalCenter; name: "people-12"; size: 12; color: root.ink }
                            }
                        }
                        Text { x: prow.compact ? 367 : 337; width: 150 - 12; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.modified_text || root.ago(prow.modelData.modified); font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        Text { x: prow.compact ? 517 : 507; width: 130; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.modified_by; font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        Text { visible: prow.compact; x: 667; width: 138; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.sizeLine; font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        Row {
                            visible: prow.compact; x: 817; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            FluentIcon { visible: prow.modelData.sharing === "Shared"; anchors.verticalCenter: parent.verticalCenter; name: "people-16"; size: 14; color: root.strong }
                            Text { text: prow.modelData.sharing || ""; font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        }
                        // List: Activity (a 14 px #0078D4 glyph, the text and
                        // its time in 14 px).
                        Row {
                            visible: !prow.compact && !pk.searching && !!prow.modelData.activity
                            x: 657; width: parent.width - 657 - 16; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 14; color: "#0078D4"; name: prow.modelData.activity ? root.activityIcon(prow.modelData.activity.kind) : "" }
                            Text {
                                width: parent.width - 18; elide: Text.ElideRight
                                text: prow.modelData.activity ? prow.modelData.activity.text + " " + prow.modelData.activity.time : ""
                                font.family: theme.font; font.pixelSize: 14; color: root.strong
                            }
                        }
                        // Search results also say where each one is.
                        Text { visible: pk.searching; x: prow.compact ? 987 : 657; width: parent.width - x - 16; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.parent_name || ""; font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        HoverHandler { id: prh2; cursorShape: prow.folder ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: prow.folder; onTapped: pk.into(prow.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
                    }
                }
                // Tiles: folders as in the OneDrive app's Tiles (176 x 171,
                // the drawing with its count, name and date); videos as
                // 304 x 171 pictures with the name and date on a dark
                // nameplate; other files as their 74 x 96 picture. Files
                // can't be picked (half opacity).
                Flickable {
                    visible: pk.view === "tiles" && !(pk.shown && pk.shown.people && !pk.person) && !(pk.place === "more" && !pk.searching)
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
                    text: pk.shown && pk.shown.error ? pk.shown.error : pk.searching ? "We couldn't find any results" : pk.place === "favorites" && pk.inPlaceList ? "Items you favorite will show up here" : "This folder is empty"
                    font.family: theme.font; font.pixelSize: 14; color: pk.shown && pk.shown.error ? theme.danger : root.ink
                }
                BusyIndicator { anchors.centerIn: parent; running: pk.loading; visible: pk.loading }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24
                y: parent.height - 24 - 32; spacing: 8
                Rectangle {
                    readonly property bool ok: !!pk.shown && !!pk.shown.here && !pk.sameFolder && !pk.loading
                    width: hereText.implicitWidth + 24; height: 32; radius: 4
                    color: !ok ? theme.surface : hh.hovered ? theme.brandHover : theme.brandFill
                    border.width: ok ? 0 : 0.67; border.color: theme.pick("#EBEBEB", "#3D3D3D")
                    Text { id: hereText; anchors.centerIn: parent; text: pk.shortcut ? "Select" : pk.moving ? "Move here" : "Copy here"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.ok ? "white" : root.line }
                    HoverHandler { id: hh; cursorShape: parent.ok ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: parent.ok; onTapped: pk.done() }
                    Accessible.role: Accessible.Button
                    Accessible.name: hereText.text
                }
                Rectangle {
                    width: 80; height: 32; radius: 4
                    color: ch2.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.pick("#7A7A7A", "#ADADAD")
                    Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                    HoverHandler { id: ch2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pk.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
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
        ToolTip.text: "Frequently used team locations, including shared libraries and Teams channels."
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
        FluentIcon { visible: !pr.site; x: pr.folded ? 10 : 12; anchors.verticalCenter: parent.verticalCenter; name: pr.icon; size: 16; color: pr.on ? root.accent : root.strong }
        Avatar { visible: pr.site && !pr.lib; x: 8; anchors.verticalCenter: parent.verticalCenter; size: 20; name: pr.label; square: true }
        SiteTile { visible: !!pr.lib; x: 8; anchors.verticalCenter: parent.verticalCenter; acronym: pr.lib ? pr.lib.acronym : ""; tint: pr.lib ? pr.lib.color : "" }
        ToolTip.visible: pr.folded && prh.hovered; ToolTip.delay: 300; ToolTip.text: pr.label
        Text {
            visible: !pr.folded
            x: 36; width: parent.width - 44 - (pr.lib ? 28 : 0); anchors.verticalCenter: parent.verticalCenter
            text: pr.label; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; font.weight: pr.on ? Font.DemiBold : Font.Normal; color: root.strong
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
        color: pbh.hovered ? theme.pick("#E0E0E0", "#3D3D3D") : "transparent"
        readonly property bool pinned: !!lib && lib.pinned
        FluentIcon { anchors.centerIn: parent; name: pb.pinned ? "pin-16-filled" : "pin-16"; size: 16; color: root.ink }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.pinLibrary(pb.lib, !pb.pinned) }
        ToolTip.visible: pbh.hovered; ToolTip.delay: 300
        ToolTip.text: lib ? (pinned ? "Unpin " + lib.label + " from Quick access" : "Pin " + lib.label + " to Quick access") : ""
        Accessible.role: Accessible.Button
        Accessible.name: "Pin to Quick access"
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
            Text { x: 14; y: 56; text: pt.modelData.child_count || 0; font.family: theme.font; font.pixelSize: 14; color: "#8F3900" }
        }
        Rectangle {
            visible: pt.wide
            anchors.fill: parent; radius: 12; clip: true; color: theme.pick("#E0E0E0", "#3D3D3D")
            Image { anchors.fill: parent; source: picker.thumbs[pt.modelData.id] || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Rectangle {
                y: parent.height - 76; width: parent.width; height: 76
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 0.2; color: "#32000000" }
                    GradientStop { position: 0.45; color: "#8D000000" }
                    GradientStop { position: 1; color: "#A6000000" }
                }
            }
            Text { x: 10; y: parent.height - 54; width: parent.width - 20; elide: Text.ElideRight; text: pt.modelData.name; font.family: theme.font; font.pixelSize: 14; color: "white" }
            Text { x: 10; y: parent.height - 32; text: pt.modelData.modified_text || root.ago(pt.modelData.modified); font.family: theme.font; font.pixelSize: 12; color: "white" }
        }
        Rectangle {
            visible: !pt.modelData.is_folder && !pt.wide
            x: 51; y: 16; width: 74; height: 96; radius: 4
            color: theme.surface; border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
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
        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
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
        if (n === 1) return "1 byte"
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return n + " bytes"
        if (n < 1024e3) return f(n / 1024) + " KB"
        if (n < 1048576e3) return f(n / 1048576) + " MB"
        if (n < 1073741824e3) return f(n / 1073741824) + " GB"
        return f(n / 1099511627776) + " TB"
    }
    /// OneDrive's file-type icon (32 px drawings).
    function fileIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : isVideo(t) ? "video" : "genericfile"
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
        if (s < 60) return "A few seconds ago"
        if (s < 3600) return Math.floor(s / 60) + (Math.floor(s / 60) === 1 ? " minute ago" : " minutes ago")
        if (s < 86400) return Math.floor(s / 3600) + (Math.floor(s / 3600) === 1 ? " hour ago" : " hours ago")
        const days = Math.floor(s / 86400)
        if (days < 7) return days === 1 ? "Yesterday" : days + " days ago"
        return Qt.formatDate(d, "MMMM d")
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
                 items: (sh.items || []).map(i => i.name + (i.is_folder ? "/" : "") + (i.parent_name ? " @" + i.parent_name : "")),
                 people: sh.people ? sh.people.map(p => p.name + ":" + p.items.length) : null, libraries: picker.libraries.length, error: sh.error || "" }
    }
    function pickerSearchForTest(q, all) { picker.search(q, all) }
    function pickerViewForTest(v) { picker.view = v }
    function pickerNavForTest(folded, browseOpen) { picker.navCollapsed = folded; picker.browseOpen = browseOpen }
    function pickerNewFolderForTest(name) { picker.createFolder(name) }
    function pickerIntoForTest(name) { const f = (picker.shown && picker.shown.items || []).find(i => i.name === name); if (f) picker.into(f); return !!f }
    function pickerDoneForTest() { picker.done() }
    function renameForTest(name) { nameInput.text = name; renameDialog.accepted() }
    function submenuForTest() { menu.openSubmenuForTest(0) }
    function fileRequestForTest(it, name) { fileRequest.openFor(it); frName.text = name; fileRequest.next() }
    function fileRequestStateForTest() { return { open: fileRequest.opened, step: fileRequest.step, url: fileRequest.url ? "(link)" : "", share_id: fileRequest.shareId } }
    function shortcutForTest(it, place) { addShortcut(it, place, place === "shortcuts" ? "Shortcuts" : "My files", {}) }
    function colorForTest(it, code) { item = it; backend.driveAction(tag + "folder_color", JSON.stringify(it), JSON.stringify({ code: code })) }
    function closeAllForTest() { menu.close(); fileRequest.close(); colorPicker.close(); renameDialog.close(); deleteDialog.close(); copyLink.close(); picker.close(); versions.close(); share.close() }
    function shareOpenForTest() { return share.opened }
    function quickForTest() { return root.quickAccess.map(q => q.label + (q.pinned ? " (pinned)" : "") + (q.drive_id ? "" : " (no drive)")) }
    function pinForTest(label, pin) { const q = root.quickAccess.find(x => x.label === label); if (q) root.pinLibrary(q, pin); return !!q }
    function copyForTest() { root.copy(copyLink.url); copyLink.copied = true }
    function linkForTest() { return { kind: copyLink.kind, share_id: copyLink.shareId, ref: copyLink.target ? ref(copyLink.target) : null } }
}
