import QtQuick
import QtQuick.Controls.Basic

// A message's file opened in Teams (measured on winpc 2026-11-13,
// ost-share-test.txt from OST TEST 121): it fills the app's area right of
// the app bar, over the chat list and the conversation.
// - The header: 61 tall, white, a 0.67 #E0E0E0 line under it; the file's
//   20 px type icon at 20, 20; the name (16.38/23.4 bold; 16 px here, Qt takes whole pixels) at 60; Close (96
//   x 32, white, a 0.67 #D1D1D1 edge, radius 4, 14 semibold) 39 from the
//   right, and "More attachment options" (32 x 32, a 16 px ···) 2 from
//   it: the card's menu (Open in Browser, Download, Share, Copy link,
//   Favorite).
// - Under it, OneDrive's embedded viewer (PreviewBody, embedded).
// Esc or Close returns to the conversation.
Item {
    id: root
    visible: !!file
    /// The message's file (parse_files' entry), or null.
    property var file: null
    property var item: null
    property var preview: null
    property bool loading: false
    property string error: ""
    signal menuRequested(var file, Item anchor)
    readonly property string tag: "fv" + Math.floor(Math.random() * 1e9) + ":"

    function show(f) {
        file = f; item = null; preview = null; error = ""; loading = true
        forceActiveFocus()
        backend.driveAction(tag + "card_item", "{}", JSON.stringify({ url: f.object_url || "" }))
    }
    function close() { file = null; item = null; preview = null }
    Connections {
        target: backend
        function onDriveActionDone(op, result, err) {
            if (!root.file || !op.startsWith(root.tag)) return
            const kind = op.slice(root.tag.length)
            const v = result ? JSON.parse(result) : null
            if (kind === "card_item") {
                if (err || !v || v.url !== root.file.object_url) { root.loading = false; root.error = err || "This file can't be opened"; return }
                root.item = v.item
                backend.driveAction(root.tag + "preview", JSON.stringify(v.item), "{}")
            } else if (kind === "preview") {
                root.loading = false
                root.error = err || ""
                root.preview = err ? null : v
            }
        }
    }
    focus: visible
    Keys.onEscapePressed: close()
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: ev => ev.accepted = true }

    function typeIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-20"
    }
    function appIcon() {
        const k = file ? String(file.file_type).toLowerCase() : ""
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : ""
    }

    Rectangle {
        id: header
        width: parent.width; height: 61
        color: theme.surface
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
        FluentIcon { x: 20; y: 20; size: 20; name: root.file ? root.typeIcon(root.file.file_type) : "" }
        Text {
            x: 60; y: 17.5
            width: closeButton.x - 60 - 16
            elide: Text.ElideRight
            text: root.file ? root.file.name : ""
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 23.4; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: closeButton
            x: parent.width - 39 - 96; y: 14.17; width: 96; height: 32; radius: 4
            color: closeHover.pressed ? theme.pick("#E0E0E0", "#3D3D3D") : closeHover.hovered ? theme.menuHover : theme.surface
            border.width: 0.67; border.color: closeHover.hovered ? theme.pick("#C7C7C7", "#757575") : theme.pick("#D1D1D1", "#666666")
            Text { anchors.centerIn: parent; text: "Close"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Rectangle {
            id: moreButton
            x: parent.width - 2 - 32; y: 14.17; width: 32; height: 32; radius: 4
            color: moreHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 16; name: "more-horizontal-16"; color: moreHover.hovered ? theme.brand : theme.textStrong }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (root.file) root.menuRequested(root.file, moreButton) }
            ToolTip.visible: moreHover.hovered
            ToolTip.delay: 500
            ToolTip.text: "More attachment options"
            Accessible.role: Accessible.Button
            Accessible.name: "More attachment options"
        }
    }
    Rectangle {
        y: header.height; width: parent.width; height: parent.height - header.height
        color: theme.surface
        PreviewBody {
            id: body
            anchors.fill: parent
            embedded: true
            preview: root.preview
            name: root.file ? root.file.name : ""
            kind: root.file ? root.file.file_type : ""
            loading: root.loading
            error: root.error
            iconName: root.file ? root.typeIcon(root.file.file_type).replace("-20", "-32") : ""
            appIconName: root.appIcon()
        }
    }

    function moreButtonForTest() { return moreButton }
    function stateForTest() {
        return { open: !!file, name: file ? file.name : "", loading: loading, error: error, kind: preview ? preview.kind : "",
                 lines: preview && preview.kind === "text" ? preview.text.split("\n").length : 0, pages: body.pageCount }
    }
}
