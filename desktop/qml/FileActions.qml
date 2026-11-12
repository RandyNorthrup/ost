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
        }
        if (sp) L.push({ label: "Share", icon: "share-16" })
        if (sp || it.web_url) L.push({ label: "Copy link", icon: "link-16" })
        if (sp) L.push({ label: "Manage access", icon: "person-16" })
        L.push({ separator: true })
        if (canWrite) L.push({ label: "Delete", icon: "delete-16" })
        // Graph's favorites (followed items) hold files, not folders.
        if (!it.is_folder) L.push({ label: fav ? "Remove from favorites" : "Add to favorites", icon: "star-16" })
        if (!it.is_folder) L.push({ label: "Download", icon: "arrow-download-16" })
        if (canWrite) L.push({ label: "Rename", icon: "rename-16" })
        // A team site's file opens in SharePoint (not yet seen in Teams).
        if (it.web_url) L.push({ label: /-my\.sharepoint\.com/.test(it.sp_site || it.web_url) ? "Open in OneDrive" : "Open in SharePoint", icon: "cloud-16" })
        if (canWrite && sp) L.push({ label: "Move to", icon: "folder-arrow-right-16" })
        if (sp) L.push({ label: "Copy to", icon: "copy-16" })
        if (canWrite && sp) L.push({ label: "Duplicate", icon: "add-square-16" })
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
        else if (label === "Download") list.filter(i => !i.is_folder).forEach(i => downloadItem(i))
        else if (label === "Move to") picker.openFor(item, true)
        else if (label === "Copy to") picker.openFor(item, false)
        else if (label === "Duplicate") {
            jobCount = list.length
            notice("progress", count(jobCount, "Copying {0} item", "Copying {0} items"))
            backend.driveAction(tag + "duplicate", JSON.stringify(item), JSON.stringify({ more: others }))
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
        else if (label === "Download") downloadItem(it)
        else if (label === "Rename") renameDialog.openFor(it)
        else if (label === "Move to") picker.openFor(it, true)
        else if (label === "Copy to") picker.openFor(it, false)
        else if (label === "Version history") versions.openFor(it)
        else if (label === "Details") detailsItem(it)
        else if (label === "Duplicate") { jobCount = 1; notice("progress", "Copying 1 item"); backend.driveAction(tag + "duplicate", JSON.stringify(it), "{}") }
    }

    // The clipboard, without OST's own "Copied to clipboard" notice
    // (OneDrive says "Link copied" itself).
    TextEdit { id: copier; visible: false }
    function copy(text) { copier.text = text; copier.selectAll(); copier.copy() }

    MenuPopup {
        id: menu
        fabric: true
        onPicked: i => root.act(items[i].label)
        onSubPicked: (i, j) => root.act(items[i].submenu[j].label)
    }

    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (!op.startsWith(root.tag)) return
            const kind = op.slice(root.tag.length)
            const v = result ? JSON.parse(result) : null
            if (kind === "folders" || kind === "libraries") { picker.reply(kind, v, error); return }
            if (kind === "versions" || kind === "restore_version" || kind === "delete_version") { versions.reply(kind, v, error); return }
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
        bodyHeight: 98.67
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
        readonly property bool sameFolder: !!shown && moving && shown.drive_id === (root.folder.drive_id || "") && shown.item_id === (root.folder.item_id || "")
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
        }
        function load(d, i) { loading = true; backend.driveAction(root.tag + "folders", "{}", JSON.stringify({ drive_id: d, item_id: i })) }
        function reply(kind, v, error) {
            if (kind === "libraries") { libraries = v || []; return }
            loading = false
            if (error) { shown = { drive_id: "", item_id: "", items: [], error: error }; return }
            shown = v
        }
        function into(f) { trail = trail.concat([{ name: f.name, drive_id: f.drive_id, item_id: f.id }]); load(f.drive_id, f.id) }
        function back(i) { trail = trail.slice(0, i + 1); const t = trail[i]; load(t.drive_id, t.item_id) }
        function openPlace(key, lib) {
            place = key
            trail = [{ name: lib ? lib.name : "My files", drive_id: lib ? lib.drive_id : "", item_id: "" }]
            load(lib ? lib.drive_id : "", "")
        }
        function done() {
            if (!shown || !shown.here || sameFolder) return
            const op = moving ? "move" : "copy"
            root.notice("progress", root.count(root.jobCount, moving ? "Moving {0} item" : "Copying {0} item", moving ? "Moving {0} items" : "Copying {0} items"))
            backend.driveAction(root.tag + op, JSON.stringify(target), JSON.stringify({ dest: shown.here.web_url, more: root.jobCount > 1 ? root.others : [] }))
            close()
        }

        // The places
        Item {
            width: 210; height: parent.height
            Text {
                x: 24; y: 14; height: 44; verticalAlignment: Text.AlignVCenter
                text: pk.moving ? "Move to" : "Copy to"
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Column {
                y: 58; width: parent.width
                PlaceRow { label: "My files"; icon: "folder-16"; on: pk.place === "mine"; onPicked: pk.openPlace("mine", null) }
                Item { width: 1; height: 16 }
                Text { x: 24; height: 18.67; visible: pk.libraries.length > 0; text: "Quick access"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Item { width: 1; height: 9.33; visible: pk.libraries.length > 0 }
                Repeater {
                    model: pk.libraries
                    PlaceRow {
                        required property var modelData
                        label: modelData.site; site: true
                        on: pk.place === modelData.drive_id
                        onPicked: pk.openPlace(modelData.drive_id, modelData)
                    }
                }
            }
        }
        // The folder
        Item {
            x: 224; width: parent.width - 224; height: parent.height
            Row {
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
                radius: 12; color: theme.surface; clip: true
                // Header: Type, Name, Modified, Modified By (14/600, 48 tall).
                Row {
                    id: pkHead
                    height: 48
                    Item { width: 55; height: 48; FluentIcon { x: 22; anchors.verticalCenter: parent.verticalCenter; name: "document-16"; size: 16; color: root.strong } }
                    PickHead { width: 270; label: "Name" }
                    PickHead { width: 170; label: "Modified" }
                    PickHead { width: 150; label: "Modified By" }
                }
                Rectangle { y: 48.67; width: parent.width; height: 0.67; color: theme.pick("#F0F0F0", "#333333") }
                ListView {
                    anchors { top: pkHead.bottom; topMargin: 1.67; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: pk.shown ? pk.shown.items || [] : []
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: prow
                        required property var modelData
                        readonly property bool folder: modelData.is_folder && modelData.id !== (pk.target ? pk.target.id : "")
                        width: ListView.view.width; height: 59
                        color: folder && prh2.hovered ? theme.menuHover : "transparent"
                        opacity: folder ? 1 : 0.45
                        FluentIcon {
                            x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32
                            name: prow.modelData.is_folder ? "folder-32-filled" : "document-16"
                            color: prow.modelData.is_folder ? "#F2C94C" : root.strong
                        }
                        Column {
                            x: 67; width: 250; anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: prow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            Text {
                                visible: prow.modelData.is_folder
                                text: prow.modelData.child_count + (prow.modelData.child_count === 1 ? " item" : " items")
                                font.family: theme.font; font.pixelSize: 12; color: root.ink
                            }
                        }
                        Text { x: 337; width: 150; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: root.ago(prow.modelData.modified); font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        Text { x: 507; width: 130; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prow.modelData.modified_by; font.family: theme.font; font.pixelSize: 14; color: root.strong }
                        HoverHandler { id: prh2; cursorShape: prow.folder ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: prow.folder; onTapped: pk.into(prow.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
                    }
                }
                Text {
                    visible: !!pk.shown && !pk.loading && (pk.shown.items || []).length === 0
                    anchors.centerIn: parent
                    text: pk.shown && pk.shown.error ? pk.shown.error : "This folder is empty"
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
                    Text { id: hereText; anchors.centerIn: parent; text: pk.moving ? "Move here" : "Copy here"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.ok ? "white" : root.line }
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

    component PlaceRow: Rectangle {
        id: pr
        property string label
        property string icon
        property bool on: false
        property bool site: false
        signal picked()
        x: 16; width: 190; height: 36; radius: 8
        color: prh.hovered ? theme.menuHover : "transparent"
        Rectangle { visible: pr.on; x: -16; width: 3; height: 20; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: root.accent }
        FluentIcon { visible: !pr.site; x: 12; anchors.verticalCenter: parent.verticalCenter; name: pr.icon; size: 16; color: pr.on ? root.accent : root.strong }
        Avatar { visible: pr.site; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 20; name: pr.label; square: true }
        Text {
            x: 36; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
            text: pr.label; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; font.weight: pr.on ? Font.DemiBold : Font.Normal; color: root.strong
        }
        HoverHandler { id: prh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pr.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    component PickHead: Item {
        property string label
        height: 48
        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
    }

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
    function pickerIntoForTest(name) { const f = (picker.shown && picker.shown.items || []).find(i => i.name === name); if (f) picker.into(f); return !!f }
    function pickerDoneForTest() { picker.done() }
    function renameForTest(name) { nameInput.text = name; renameDialog.accepted() }
    function submenuForTest() { menu.openSubmenuForTest(0) }
    function closeAllForTest() { menu.close(); renameDialog.close(); deleteDialog.close(); copyLink.close(); picker.close(); versions.close() }
    function copyForTest() { root.copy(copyLink.url); copyLink.copied = true }
    function linkForTest() { return { kind: copyLink.kind, share_id: copyLink.shareId, ref: copyLink.target ? ref(copyLink.target) : null } }
}
