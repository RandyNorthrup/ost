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
        view = v; trail = []; person = ""
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

    function size(n) {
        if (!n) return ""
        if (n < 1024) return n + " B"
        if (n < 1048576) return Math.round(n / 1024) + " KB"
        if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB"
        return (n / 1073741824).toFixed(1) + " GB"
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
        Rectangle {
            id: card
            x: 0; y: 76
            width: parent.width - 16; height: parent.height - y - 16
            radius: 4
            color: theme.surface
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
            // The files table
            Item {
                visible: root.view !== "libraries" && root.view !== "recycle" && (root.view !== "people" || !!root.person)
                anchors.fill: parent
                readonly property real wName: Math.max(200, width * 0.32)
                Row {
                    id: head
                    x: 0; y: 13; height: 36
                    Item { width: 77; height: 36; FluentIcon { anchors.centerIn: parent; name: "document-20"; size: 16; color: theme.textSecondary } }
                    HeadCell { label: "Name"; width: parent.parent.wName }
                    HeadCell { label: root.view === "recent" ? "Opened" : "Modified"; width: 136 }
                    HeadCell { label: root.view === "shared" ? "Shared by" : "Modified By"; width: 136 }
                    HeadCell { label: "File size"; width: 90 }
                    HeadCell { label: "Sharing"; width: 82 }
                }
                ListView {
                    id: files
                    anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true
                    model: root.items
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: frow
                        required property var modelData
                        width: files.width; height: 48
                        color: fh.hovered ? theme.rowHover : "transparent"
                        Rectangle { y: 0; x: 16; width: parent.width - 32; height: 1; color: theme.dividerSoft }
                        Row {
                            height: parent.height
                            Item {
                                width: 77; height: parent.height
                                FluentIcon {
                                    anchors.centerIn: parent; size: 20
                                    name: root.iconFor(frow.modelData)
                                    color: frow.modelData.is_folder ? "#E8A33D" : theme.brand
                                }
                            }
                            Cell { width: files.parent.wName; text: frow.modelData.name; strong: true }
                            Cell { width: 136; text: root.ago(frow.modelData.modified) }
                            Cell { width: 136; text: frow.modelData.modified_by || root.userName }
                            Cell { width: 90; text: frow.modelData.is_folder ? frow.modelData.child_count + " items" : root.size(frow.modelData.size) }
                            Cell { width: 82; text: frow.modelData.sharing }
                        }
                        Rectangle {
                            id: moreButton
                            visible: fh.hovered || actions.item === frow.modelData && actions.menuOpen
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: mh.hovered ? theme.pane : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: actions.popup(frow.modelData, moreButton, 0, moreButton.height) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "More options for " + frow.modelData.name
                        }
                        // Right-click: the same menu at the pointer, as Teams.
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: (ev) => actions.popup(frow.modelData, frow, ev.position.x, ev.position.y)
                        }
                        function activate() {
                            if (modelData.is_folder) root.openFolder(modelData.name, modelData.drive_id, modelData.id)
                            else if (modelData.web_url) Qt.openUrlExternally(modelData.web_url)
                        }
                        HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onDoubleTapped: frow.activate(); onTapped: if (frow.modelData.is_folder) frow.activate() }
                        Accessible.role: Accessible.Button
                        Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
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
    }

    // Test harness hooks
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
