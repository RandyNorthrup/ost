import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// A channel's Shared tab, as Teams shows it: the channel's folder in the
// team's SharePoint library with a breadcrumb, Share, Copy link, Add
// shortcut to OneDrive and Create or upload, then Name, Modified and
// Modified By, or "This folder is empty".
Item {
    id: root
    /// The team (group id) and channel (thread id) shown.
    property string teamId
    property string channelId
    property string channelName
    /// The backend's channel_files_json, parsed.
    property var reply: ({})
    property bool busy: false
    signal load(string teamId, string channelId, string driveId, string itemId)
    signal change(string op, string driveId, string itemId, string arg)

    /// The folders opened, from the channel's own: [{name, drive_id, id, web_url}].
    property var trail: []
    readonly property var here: trail.length ? trail[trail.length - 1] : null
    readonly property var items: (reply.items || [])
    property string error: ""

    function reset() { trail = []; error = ""; if (teamId && channelId) load(teamId, channelId, "", "") }
    onChannelIdChanged: reset()
    onVisibleChanged: if (visible && !trail.length) reset()
    onReplyChanged: {
        const r = reply || {}
        error = r.error || ""
        if (r.root && r.channel === channelId) trail = [{ name: r.root.name || channelName, drive_id: r.root.drive_id, id: r.root.id, web_url: r.root.web_url, sp_site: r.root.sp_site, sp_list: r.root.sp_list, sp_item: r.root.sp_item }]
    }
    function open(it) {
        if (it.is_folder) { trail = trail.concat([{ name: it.name, drive_id: it.drive_id, id: it.id, web_url: it.web_url, sp_site: it.sp_site, sp_list: it.sp_list, sp_item: it.sp_item }]); load(teamId, channelId, it.drive_id, it.id) }
        else if (it.web_url) Qt.openUrlExternally(it.web_url)
    }
    function back(i) { trail = trail.slice(0, i + 1); load(teamId, channelId, here.drive_id, here.id) }
    function ago(t) {
        if (!t) return ""
        const d = new Date(t), s = (Date.now() - d) / 1000
        if (s < 60) return "Just now"
        if (s < 3600) return Math.floor(s / 60) + " minutes ago"
        if (s < 86400) return Math.floor(s / 3600) + " hours ago"
        if (s < 172800) return "Yesterday"
        return Qt.formatDate(d, "MMMM d")
    }
    function copy(text) { copier.text = text; copier.selectAll(); copier.copy() }

    Rectangle { anchors.fill: parent; color: theme.surface }
    TextEdit { id: copier; visible: false }

    // Breadcrumb and actions
    Row {
        id: crumbs
        x: 24; y: 14; height: 36; spacing: 6
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder-20"; size: 20; color: theme.textStrong }
        Repeater {
            model: root.trail
            Row {
                required property var modelData
                required property int index
                anchors.verticalCenter: parent.verticalCenter; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.textStrong }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    font.family: theme.font; font.pixelSize: index === root.trail.length - 1 ? 20 : theme.base + 1
                    font.weight: index === root.trail.length - 1 ? Font.Bold : Font.Normal
                    color: theme.text
                    TapHandler { enabled: index < root.trail.length - 1; onTapped: root.back(index) }
                    HoverHandler { cursorShape: index < root.trail.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }
        }
    }
    Row {
        anchors { right: parent.right; rightMargin: 24 }
        y: 14; height: 36; spacing: 4
        ToolButton2 { icon: "share-20"; label: "Share"; enabled: !!root.here && !!root.here.sp_item; onClicked: driveShare.openFor({ site: root.here.sp_site, list: root.here.sp_list, item: root.here.sp_item }, root.here.name, root.here.kind) }
        ToolButton2 { icon: "link-20"; label: "Copy link"; enabled: !!root.here && !!root.here.web_url; onClicked: { root.copy(root.here.web_url); backend.statusText = "Link copied" } }
        ToolButton2 { icon: "cloud-add-20"; label: "Add shortcut to OneDrive"; enabled: !!root.here; onClicked: root.change("shortcut", root.here.drive_id, root.here.id, root.here.name) }
        Rectangle {
            width: cuRow.implicitWidth + 24; height: 32; radius: theme.radius
            anchors.verticalCenter: parent.verticalCenter
            color: cuh.hovered ? theme.brandHover : theme.brandFill
            opacity: root.here ? 1 : 0.5
            Row { id: cuRow; anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 18; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Create or upload"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            }
            HoverHandler { id: cuh; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !!root.here; onTapped: createMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Create or upload"
            MenuPopup {
                id: createMenu
                y: parent.height + 4; x: parent.width - width; width: 220
                items: [{ label: "Folder", icon: "folder-add-20" }, { separator: true }, { label: "Files upload", icon: "arrow-upload-20" }]
                onPicked: i => i === 0 ? folderDialog.open() : uploadPicker.open()
            }
        }
    }

    // The table
    Rectangle {
        anchors { fill: parent; topMargin: 64; leftMargin: 16; rightMargin: 16; bottomMargin: 12 }
        radius: 6; color: theme.surface; border.color: theme.dividerSoft
        clip: true
        readonly property real wName: Math.max(240, width * 0.42)
        Row {
            id: head
            x: 0; y: 6; height: 40
            Item { width: 64; height: 40; FluentIcon { anchors.centerIn: parent; name: "document-20"; size: 18; color: theme.textStrong } }
            HeadCell { width: parent.parent.wName; label: "Name" }
            HeadCell { width: 180; label: "Modified" }
            HeadCell { width: 200; label: "Modified By" }
        }
        Rectangle { x: 16; y: head.y + head.height; width: parent.width - 32; height: 1; color: theme.dividerSoft }
        ListView {
            anchors { top: head.bottom; topMargin: 1; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true
            model: root.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: frow
                required property var modelData
                width: ListView.view.width; height: 48
                color: fh.hovered ? theme.rowHover : "transparent"
                Row {
                    height: parent.height
                    Item { width: 64; height: parent.height; FluentIcon { anchors.centerIn: parent; name: frow.modelData.is_folder ? "folder-20-filled" : "document-20"; size: 20; color: frow.modelData.is_folder ? "#C19C00" : theme.textSecondary } }
                    Cell { width: frow.parent.parent.parent.wName; text: frow.modelData.name; strong: true }
                    Cell { width: 180; text: root.ago(frow.modelData.modified) }
                    Cell { width: 200; text: frow.modelData.modified_by }
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
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (ev) => actions.popup(frow.modelData, frow, ev.position.x, ev.position.y)
                }
                HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onDoubleTapped: root.open(frow.modelData); onTapped: if (frow.modelData.is_folder) root.open(frow.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: (modelData.is_folder ? "Folder " : "File ") + modelData.name
            }
        }
        Column {
            id: emptyState
            visible: !root.busy && !root.error && root.items.length === 0 && !!root.here
            anchors.centerIn: parent
            spacing: 12
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "This folder is empty"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "folder-20"; size: 96; color: theme.brandTint }
        }
        Text {
            visible: !!root.error
            anchors.centerIn: parent
            text: root.error
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }
    }

    FileDialog {
        id: uploadPicker
        title: "Upload files"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.change("upload", root.here.drive_id, root.here.id,
            selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))).join("\n"))
    }
    Popup {
        id: folderDialog
        anchors.centerIn: parent
        width: 380; padding: 24; modal: true
        onOpened: { folderName.text = ""; folderName.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 14
            Text { text: "Create a folder"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Rectangle {
                width: 332; height: 32; radius: theme.radius
                color: theme.input; border.color: folderName.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: folderName
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !folderName.text; text: "Folder name"; color: theme.textTertiary; font: folderName.font }
                    Keys.onReturnPressed: folderDialog.done()
                    Accessible.name: "Folder name"
                }
            }
            Row {
                spacing: 8; layoutDirection: Qt.RightToLeft; width: 332
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: folderDialog.done() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Create"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: folderDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
        function done() {
            if (!folderName.text.trim()) return
            root.change("folder", root.here.drive_id, root.here.id, folderName.text.trim())
            close()
        }
    }
    component ToolButton2: Rectangle {
        id: tb
        property string icon
        property string label
        signal clicked()
        width: tbRow.implicitWidth + 16; height: 32; radius: theme.radius
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: tbh.hovered && enabled ? theme.rowHover : "transparent"
        opacity: enabled ? 1 : 0.45
        Row { id: tbRow; anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: tb.icon; size: 18; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: tb.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
        }
        HoverHandler { id: tbh; cursorShape: tb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: tb.enabled; onTapped: tb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component HeadCell: Item {
        property string label
        height: 40
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
    }
    component Cell: Item {
        property alias text: t.text
        property bool strong: false
        height: 48
        Text { id: t; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 12; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: theme.base; color: parent.strong ? theme.text : theme.textStrong }
    }

    // Test harness hooks
    function emptyShownForTest() { return emptyState.visible + " " + emptyState.width + "x" + emptyState.height }
    function newFolderForTest(name) { root.change("folder", root.here.drive_id, root.here.id, name) }
    function deleteForTest(name) { const it = root.items.find(i => i.name === name); if (it) root.change("delete", root.here.drive_id, root.here.id, it.id); return !!it }
    function shareForTest() { driveShare.openFor({ site: root.here.sp_site, list: root.here.sp_list, item: root.here.sp_item }, root.here.name, root.here.kind) }
    // OneDrive's share dialog (Share), as Teams opens it.
    OneDriveShare { id: driveShare }
    // An item's More actions (Teams' Files context menu), dialogs and notices.
    FileActions {
        id: actions
        anchors.fill: parent
        folder: root.here ? { drive_id: root.here.drive_id, item_id: root.here.id } : { drive_id: "-", item_id: "-" }
        onChanged: if (root.here) root.load(root.teamId, root.channelId, root.here.drive_id, root.here.id)
        onDeleteItem: it => root.change("delete", root.here.drive_id, root.here.id, it.id)
        onFavoriteItem: (it, on) => backend.driveFavorite(it.drive_id, it.id, on)
        onDownloadItem: it => backend.driveDownload(JSON.stringify(it))
    }
}
