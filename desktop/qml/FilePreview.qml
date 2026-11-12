import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Pdf

// Teams' file Preview (OneDrive's viewer, docs/spec/file-preview.md): over
// the whole view, a rgba(0,0,0,.4) backdrop under a rgba(31,31,31,.88)
// layer; a 48 tall bar (Download, Favorite, Delete | Details, ···; the
// name; Open ▾, Share ▾, Close); the file: text on a white page (75% wide,
// a 30 px name strip, line numbers), a picture, or PDF pages (Office files
// converted by Graph) with "PAGE n OF m" and the zoom; Previous / Next.
Item {
    id: root
    visible: !!item
    /// The file shown, and the list it steps through.
    property var item: null
    property var siblings: []
    property var actions: null
    property var favoriteIds: []
    property var preview: null
    property bool loading: false
    property string error: ""
    signal favorite(var item, bool on)
    signal download(var item)
    signal details(var item)
    readonly property string tag: "pv" + Math.floor(Math.random() * 1e9) + ":"
    readonly property color ink: "#F3F2F1"
    readonly property var files: siblings.filter(i => !i.is_folder)
    readonly property int at: item ? files.findIndex(i => i.id === item.id) : -1
    readonly property bool fav: !!item && favoriteIds.indexOf(item.id) >= 0

    function show(it, list) { siblings = list || []; item = it }
    function close() { item = null; preview = null }
    function step(d) { const n = at + d; if (n >= 0 && n < files.length) item = files[n] }
    onItemChanged: {
        preview = null; error = ""
        if (!item) return
        loading = true
        backend.driveAction(tag + "preview", JSON.stringify(item), "{}")
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, err) {
            if (op !== root.tag + "preview") return
            root.loading = false
            root.error = err || ""
            root.preview = err ? null : JSON.parse(result)
        }
    }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4) }
    Rectangle { anchors.fill: parent; color: Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: ev => ev.accepted = true }
    focus: visible
    Keys.onEscapePressed: close()
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)

    // The content
    Item {
        id: body
        x: 0; y: 45; width: parent.width; height: parent.height - 45
        // Text: a white page, 75% wide, the name strip and numbered lines.
        Rectangle {
            visible: !!root.preview && root.preview.kind === "text"
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.75; height: parent.height
            color: "#FFFFFE"
            Text {
                x: 15; height: 30; verticalAlignment: Text.AlignVCenter
                text: root.item ? root.item.name : ""
                font.family: theme.font; font.pixelSize: 14; color: "#242424"
            }
            ListView {
                id: lines
                x: 0; y: 30; width: parent.width; height: parent.height - 30
                clip: true
                model: root.preview && root.preview.kind === "text" ? root.preview.text.split("\n") : []
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: lines.width; height: Math.max(19, lt.implicitHeight)
                    Text { width: 52; horizontalAlignment: Text.AlignRight; text: index + 1; font.family: theme.mono; font.pixelSize: 14; color: "#237893" }
                    Text { id: lt; x: 72; width: parent.width - 72 - 16; text: modelData.replace(/\r$/, ""); wrapMode: Text.WrapAnywhere; font.family: theme.mono; font.pixelSize: 14; lineHeight: 19; lineHeightMode: Text.FixedHeight; color: "#000000"; textFormat: Text.PlainText }
                }
            }
        }
        // A picture, fitted.
        Image {
            visible: !!root.preview && root.preview.kind === "image"
            anchors.fill: parent; anchors.margins: 24
            source: root.preview && root.preview.kind === "image" ? root.preview.path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        // PDF pages (and Office files as PDF), with the status line.
        PdfDocument { id: pdf; source: root.preview && root.preview.kind === "pdf" ? root.preview.path : "" }
        ListView {
            id: pages
            visible: !!root.preview && root.preview.kind === "pdf"
            x: 0; y: 10; width: parent.width; height: parent.height - 10 - 22
            clip: true; spacing: 10
            model: visible ? pdf.pageCount : 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            readonly property real pageWidth: Math.min(818, width - 80)
            delegate: Item {
                required property int index
                width: pages.width
                height: page.height
                PdfPageImage {
                    id: page
                    anchors.horizontalCenter: parent.horizontalCenter
                    document: pdf
                    currentFrame: parent.index
                    width: pages.pageWidth
                    height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : width * 1.294
                    sourceSize.width: width * 2
                    fillMode: Image.PreserveAspectFit
                    Rectangle { anchors.fill: parent; z: -1; color: "white" }
                }
            }
        }
        Rectangle {
            visible: pages.visible
            anchors.bottom: parent.bottom; width: parent.width; height: 22
            color: "#2B2B2B"
            FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 16; name: root.appIcon() }
            Text {
                x: 46; anchors.verticalCenter: parent.verticalCenter
                text: "PAGE " + (Math.min(pdf.pageCount, pages.indexAt(10, pages.contentY + 10) + 1) || 1) + " OF " + pdf.pageCount
                font.family: theme.font; font.pixelSize: 11; color: "#FFFFFF"
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 104; anchors.verticalCenter: parent.verticalCenter
                text: "100%"
                font.family: theme.font; font.pixelSize: 11; color: "#FFFFFF"
            }
        }
        // No preview
        Column {
            visible: !root.loading && (!!root.error || (!!root.preview && root.preview.kind === "none"))
            anchors.centerIn: parent; spacing: 12
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 32; name: root.item ? root.fileIcon(root.item.kind) : "" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.error || "No preview available"; font.family: theme.font; font.pixelSize: 16; color: root.ink }
        }
        BusyIndicator { anchors.centerIn: parent; running: root.loading; visible: root.loading }
    }

    // Previous / Next: 40 px circles at the edges, halfway down.
    component Arrow: Rectangle {
        id: ar
        property bool next: false
        width: 40; height: 40; radius: 20
        color: arh.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88)
        border.width: 0.67; border.color: "#808080"
        FluentIcon { anchors.centerIn: parent; size: 16; name: ar.next ? "chevron-right-16" : "chevron-left-16"; color: "#7F85F5" }
        HoverHandler { id: arh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.step(ar.next ? 1 : -1) }
        ToolTip.visible: arh.hovered
        ToolTip.text: next ? "Next" : "Previous"
        Accessible.role: Accessible.Button
        Accessible.name: next ? "Next" : "Previous"
    }
    Arrow { visible: root.at > 0; x: 12; y: parent.height / 2 - 20 }
    Arrow { visible: root.at >= 0 && root.at < root.files.length - 1; next: true; x: parent.width - 52; y: parent.height / 2 - 20 }

    // The bar
    component BarIcon: Rectangle {
        id: bi
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 40; radius: 6
        color: bih.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: bi.icon; color: root.ink }
        HoverHandler { id: bih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bi.clicked() }
        ToolTip.visible: bih.hovered
        ToolTip.text: tip
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component BarButton: Rectangle {
        id: bb
        property string label
        property string icon
        signal clicked()
        height: 32; radius: 6
        width: 12 + 16 + 8 + bbt.implicitWidth + 8 + 12 + 12
        color: bbh.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88)
        border.width: 0.67; border.color: "#808080"
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: bb.icon; color: bb.icon.startsWith("ft-") ? "#212121" : "#7F85F5" }
        Text { id: bbt; x: 36; anchors.verticalCenter: parent.verticalCenter; text: bb.label; font.family: theme.font; font.pixelSize: 14; color: "#7F85F5" }
        FluentIcon { x: bbt.x + bbt.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "chevron-down-12"; color: "#FFFFFF" }
        HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    Item {
        width: parent.width; height: 48
        Row {
            x: 10; y: 4; spacing: 4
            BarIcon { icon: "arrow-download-20"; tip: "Download this file to your device"; onClicked: root.download(root.item) }
            BarIcon { icon: root.fav ? "star-20-filled" : "star-20"; tip: root.fav ? "Unfavorite this file" : "Favorite this file"; onClicked: root.favorite(root.item, !root.fav) }
            BarIcon {
                icon: "delete-20"; tip: "Delete this file"
                visible: !!root.actions && root.actions.canWrite
                onClicked: { const it = root.item; root.close(); root.actions.item = it; root.actions.act("Delete") }
            }
            Rectangle { width: 1; height: 20; y: 10; color: "#808080" }
            Item { width: 18; height: 40 }
            BarIcon { icon: "info-20"; tip: "Info, View file details"; onClicked: { const it = root.item; root.close(); root.details(it) } }
            BarIcon {
                id: moreIcon
                icon: "more-horizontal-20"; tip: "More"
                onClicked: if (root.actions) root.actions.popup(root.item, moreIcon, 0, moreIcon.height)
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 12; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: root.item ? root.fileIcon(root.item.kind) : "" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.item ? root.item.name : ""
                font.family: theme.font; font.pixelSize: 16; color: "#FFFFFF"
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14; y: 8; spacing: 10
            Avatar { size: 32; photoId: "me"; name: backend.userName }
            BarButton {
                id: openButton
                label: "Open"; icon: root.appIcon() || "open-16"
                onClicked: openMenu.open()
                MenuPopup {
                    id: openMenu
                    fabric: true; y: parent.height + 4
                    items: root.actions && root.item ? root.actions.itemsFor(root.item)[0].submenu || [] : []
                    onPicked: i => { root.actions.item = root.item; root.actions.act(items[i].label) }
                }
            }
            BarButton {
                label: "Share"; icon: "share-16"
                onClicked: shareMenu.open()
                MenuPopup {
                    id: shareMenu
                    fabric: true; y: parent.height + 4
                    items: [{ label: "Share", icon: "share-16" }, { label: "Copy link", icon: "link-16" }, { label: "Manage access", icon: "person-16" }]
                    onPicked: i => { root.actions.item = root.item; root.actions.act(items[i].label) }
                }
            }
            Item {
                width: 32; height: 32
                BarIcon { y: -4; icon: "dismiss-20"; tip: "Close"; onClicked: root.close() }
            }
        }
    }

    function fileIcon(kind) {
        const k = String(kind || "").toLowerCase()
        const m = { doc: "docx", docx: "docx", xls: "xlsx", xlsx: "xlsx", ppt: "pptx", pptx: "pptx", pdf: "pdf", txt: "txt", one: "one", loop: "loop",
                    png: "photo", jpg: "photo", jpeg: "photo", gif: "photo" }[k]
        return m ? "ft-" + m + "-20" : "document-16"
    }
    function appIcon() {
        const k = root.item ? String(root.item.kind).toLowerCase() : ""
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : ""
    }
    function stateForTest() {
        return { item: item ? item.name : "", loading: loading, error: error, kind: preview ? preview.kind : "",
                 lines: preview && preview.kind === "text" ? preview.text.split("\n").length : 0, pages: pdf.pageCount, at: at, files: files.length }
    }
}
