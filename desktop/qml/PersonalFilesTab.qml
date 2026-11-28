import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// A personal account's chat Files tab, as Teams free draws it (measured on
// teams.live.com as OST Personal 1, 2026-11-28): the chat's files from
// Teams' message search (msgsearch v3, 50 at a time).
// - Empty: Teams' folder-files illustration (256), "Share files in this
//   chat" (16/22 semibold), "When you upload files to this files tab, they
//   will show up in chat." (14/20) and a primary Upload button.
// - Otherwise an Upload button (outline, 32 tall, 30 in and 17 down), then
//   the list: a 40 tall header (select all, the type column, Name, "Shared
//   on" with its down arrow, "Sent by") and 42 tall rows (a checkbox on
//   hover or when selected, the type glyph, the name, More options on
//   hover, the time, the sender). Clicking a row opens the file in the
//   browser; its menu has Open in Browser, Download and Copy link.
// - With a selection, Upload gives way to Open (Open in Browser), Copy link
//   and Download, and "N selected" with a clear button at the end.
// Upload posts the picked files to the chat, as Teams does ("they will show
// up in chat").
Item {
    id: root
    property string chatId: ""
    property var stamp: t => t
    signal toastRequested(var data)

    property var files: []
    property bool loading: false
    property bool loaded: false
    property var selected: ({})
    readonly property var selectedFiles: files.filter(f => !!selected[keyOf(f)])
    readonly property string tag: "pfiles-" + Math.floor(Math.random() * 1e9) + ":"
    function keyOf(f) { return f.message_id + "|" + f.name }
    function load() {
        if (!chatId) return
        loading = true
        backend.driveAction(tag + "personal_files", "{}", JSON.stringify({ chat: chatId }))
    }
    onChatIdChanged: { files = []; selected = ({}); loaded = false; load() }
    Component.onCompleted: load()
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (op !== root.tag + "personal_files") return
            root.loading = false
            root.loaded = true
            if (error) { console.warn("personal files:", error); return }
            const v = JSON.parse(result)
            if (v.chat !== root.chatId) return
            root.files = v.files || []
        }
    }
    // The search finds a message a moment after it is sent.
    Timer { id: reloadSoon; interval: 4000; onTriggered: root.load() }

    function attachment(f) {
        return { name: f.name, file_type: f.file_type, object_url: f.object_url, share_url: f.share_url, item_id: "", location: "", site_url: f.site_url || "" }
    }
    function act(f, what) {
        if (what === "open") backend.openExternal(f.share_url || f.object_url)
        else if (what === "download") backend.downloadFile(JSON.stringify(attachment(f)))
        else if (what === "copy") { backend.copyText(f.share_url || f.object_url); root.toastRequested({ text: qsTr("Link copied"), intent: "success" }) }
    }
    function toggle(f) { const m = Object.assign({}, selected); if (m[keyOf(f)]) delete m[keyOf(f)]; else m[keyOf(f)] = true; selected = m }
    function typeIcon(t) {
        const k = String(t || "").toLowerCase()
        return ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(k) >= 0 ? "image-20"
             : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(k) >= 0 ? "video-20" : "document-20"
    }

    FileDialog {
        id: uploadDialog
        title: qsTr("Upload")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            const paths = selectedFiles.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
            if (!paths.length) return
            backend.sendFiles(paths.join("\n"), "")
            reloadSoon.restart()
        }
    }
    function uploadForTest(paths) { backend.sendFiles(paths.join("\n"), ""); reloadSoon.restart() }
    function stateForTest() { return { loaded: loaded, files: files.map(f => f.name), selected: selectedFiles.map(f => f.name) } }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Empty.
    Column {
        visible: root.loaded && root.files.length === 0
        anchors.centerIn: parent
        spacing: 0
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 256; height: 256
            source: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/illustrations/v2/folder-files-" + (theme.dark || theme.highContrast ? "d" : "l") + "-standard.svg"
            sourceSize: Qt.size(256, 256)
            asynchronous: true
        }
        Item { width: 1; height: 12 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Share files in this chat"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Item { width: 1; height: 8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("When you upload files to this files tab, they will show up in chat."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Item { width: 1; height: 96 }
        Rectangle {
            id: emptyUpload
            anchors.horizontalCenter: parent.horizontalCenter
            width: emptyRow.implicitWidth + 24; height: 32; radius: 4
            color: euHover.hovered ? theme.brandHover : theme.brandFill
            Row {
                id: emptyRow
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: "arrow-upload-20"; color: theme.textOnBrand }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Upload"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            }
            HoverHandler { id: euHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: uploadDialog.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Upload")
        }
    }

    // The command bar.
    Item {
        id: bar
        visible: root.files.length > 0
        x: 0; y: 0; width: parent.width; height: 66
        Rectangle {
            visible: root.selectedFiles.length === 0
            x: 30; y: 17; width: upRow.implicitWidth + 24; height: 32; radius: 4
            color: upHover.hovered ? theme.menuHover : theme.surface
            border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 1
            Row {
                id: upRow
                anchors.centerIn: parent
                spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: "arrow-upload-20"; color: theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Upload"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            }
            HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: uploadDialog.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Upload")
        }
        Row {
            visible: root.selectedFiles.length > 0
            x: 12; y: 10; height: 32
            spacing: 4
            BarAction { id: openAction; icon: "document-20"; label: qsTr("Open"); chevron: true; onClicked: openMenu.popup(openAction, 0, openAction.height + 4) }
            BarAction { icon: "link-20"; label: qsTr("Copy link"); onClicked: if (root.selectedFiles.length) root.act(root.selectedFiles[0], "copy") }
            BarAction { icon: "arrow-download-20"; label: qsTr("Download"); onClicked: root.selectedFiles.forEach(f => root.act(f, "download")) }
        }
        Row {
            visible: root.selectedFiles.length > 0
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 10; height: 32
            spacing: 6
            Rectangle {
                width: 28; height: 28; radius: 4; anchors.verticalCenter: parent.verticalCenter
                color: clrHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; size: 16; name: "dismiss-16"; color: theme.textSecondary }
                HoverHandler { id: clrHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selected = ({}) }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear selection")
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("%1 selected").arg(root.selectedFiles.length); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        }
    }
    MenuPopup {
        id: openMenu
        items: [{ act: "open", label: qsTr("Open in Browser"), icon: "globe-20" }]
        onPicked: i => { if (root.selectedFiles.length) root.act(root.selectedFiles[0], "open") }
        function popup(anchor, dx, dy) { const p = anchor.mapToItem(root, dx, dy); x = p.x; y = p.y; open() }
    }

    readonly property real sharedX: width - 431
    readonly property real sentX: width - 232
    // The header.
    Item {
        id: head
        visible: root.files.length > 0
        y: 66; width: parent.width; height: 40
        Check { x: 22; anchors.verticalCenter: parent.verticalCenter; checked: root.files.length > 0 && root.selectedFiles.length === root.files.length
            onToggled: { const m = {}; if (!checked) for (const f of root.files) m[root.keyOf(f)] = true; root.selected = m } }
        FluentIcon { x: 96; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "document-16"; color: theme.textSecondary }
        Text { x: 172; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Row {
            x: root.sharedX; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: qsTr("Shared on"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 12; name: "arrow-down-12"; color: theme.textSecondary }
        }
        Text { x: root.sentX; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Sent by"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Rectangle { y: parent.height - 1; width: parent.width - 14; height: 1; color: theme.divider }
    }
    ListView {
        id: list
        visible: root.files.length > 0
        y: 106; width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.files
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool sel: !!root.selected[root.keyOf(modelData)]
            width: list.width - 14; height: 42
            color: sel ? theme.pick("#EBEBEB", "#3D3D3D", "#000000") : rowHover.hovered ? theme.rowHover : "transparent"
            Check { visible: row.sel || rowHover.hovered; x: 22; anchors.verticalCenter: parent.verticalCenter; checked: row.sel; onToggled: root.toggle(row.modelData) }
            FluentIcon { x: 94; anchors.verticalCenter: parent.verticalCenter; size: 20; name: root.typeIcon(row.modelData.file_type); color: theme.textSecondary }
            Text {
                x: 172; anchors.verticalCenter: parent.verticalCenter
                width: root.sharedX - 172 - 44
                text: row.modelData.name; elide: Text.ElideMiddle
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Rectangle {
                id: more
                visible: rowHover.hovered || row.sel
                x: root.sharedX - 29 - 14; anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 4
                color: moreHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; size: 20; name: "more-horizontal-20"; color: theme.brand }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { rowMenu.file = row.modelData; const p = more.mapToItem(root, 0, more.height + 4); rowMenu.x = p.x; rowMenu.y = p.y; rowMenu.open() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("More options")
            }
            Text { x: root.sharedX + 10; anchors.verticalCenter: parent.verticalCenter; text: root.stamp(row.modelData.time); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { x: root.sentX + 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 8; elide: Text.ElideRight
                text: row.modelData.sender; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: theme.divider }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.act(row.modelData, "open") }
            Accessible.role: Accessible.Row
            Accessible.name: row.modelData.name
        }
    }
    MenuPopup {
        id: rowMenu
        property var file: null
        items: [{ act: "open", label: qsTr("Open in Browser"), icon: "globe-20" }, { act: "download", label: qsTr("Download"), icon: "arrow-download-20" },
                { act: "copy", label: qsTr("Copy link"), icon: "link-20" }]
        onPicked: i => { if (file) root.act(file, items[i].act) }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.loading && !root.loaded; visible: running }

    component BarAction: Rectangle {
        id: ba
        property string icon
        property string label
        property bool chevron: false
        signal clicked()
        width: baRow.implicitWidth + 16; height: 32; radius: 4
        color: baHover.hovered ? theme.menuHover : "transparent"
        Row {
            id: baRow
            anchors.centerIn: parent
            spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: ba.icon; color: theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ba.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            FluentIcon { visible: ba.chevron; anchors.verticalCenter: parent.verticalCenter; size: 16; name: "chevron-down-16"; color: theme.text }
        }
        HoverHandler { id: baHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ba.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ba.label
    }
    component Check: Rectangle {
        id: ck
        property bool checked: false
        signal toggled()
        width: 20; height: 20; radius: 4
        color: checked ? theme.brandFill : "transparent"
        border.color: checked ? theme.brand : theme.textSecondary; border.width: 1
        FluentIcon { visible: ck.checked; anchors.centerIn: parent; size: 16; name: "checkmark-16"; color: theme.textOnBrand }
        TapHandler { onTapped: ck.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: ck.checked
        Accessible.name: qsTr("Select")
    }
}
