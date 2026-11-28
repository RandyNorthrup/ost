import QtQuick
import QtQuick.Controls.Basic

// Attach cloud files for a personal account (Teams free embeds OneDrive's
// consumer picker, onedrive.live.com/picker, seen on teams.live.com as OST
// Personal 1 on 2026-11-28): a dialog 76 % x 82 % of the window, white,
// radius 8; on the left (224 wide, #F5F5F5) "OneDrive" (20/28 semibold)
// over My files, Recent, Photos and Shared (36 tall rows, a 20 px glyph,
// the current one #EBEBEB with a 3 px brand bar); on the right the place's
// title (20/28 semibold), the list (Name, Modified, Modified by in My files;
// Name, Accessed in Recent) with 58 tall rows and a 32 px type glyph, and
// Attach (primary, off until a file is picked) and Cancel at the bottom.
// Folders open; files toggle their selection. The rows come from Graph
// (your OneDrive's folders, recent files, Pictures and shared files).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true
    width: Math.round(Overlay.overlay.width * 0.76)
    height: Math.round(Overlay.overlay.height * 0.82)
    x: (Overlay.overlay.width - width) / 2
    y: (Overlay.overlay.height - height) / 2
    padding: 0
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(37 / 255, 36 / 255, 36 / 255, 0.75) }
    background: Rectangle { radius: 8; color: theme.surface }
    /// The picked files ({name, web_url, drive_id, id, kind}).
    signal attached(var files)

    property string place: "recent"
    /// The folders opened in My files: [{id, name}].
    property var path: []
    property var items: []
    property bool loading: false
    property var picked: ({})
    readonly property var pickedItems: items.filter(i => !!picked[i.id])
    readonly property string tag: "ppicker-" + Math.floor(Math.random() * 1e9) + ":"
    readonly property var places: [
        { key: "myfiles", label: qsTr("My files"), icon: "folder-20" },
        { key: "recent", label: qsTr("Recent"), icon: "clock-20" },
        { key: "photos", label: qsTr("Photos"), icon: "image-20" },
        { key: "shared", label: qsTr("Shared"), icon: "people-20" }
    ]
    function go(key) { place = key; path = []; load() }
    function load() {
        loading = true
        items = []
        backend.driveAction(tag + "personal_picker", "{}", JSON.stringify({ place: place, folder: path.length ? path[path.length - 1].id : "", drive: path.length ? path[path.length - 1].drive : "" }))
    }
    onOpened: { picked = ({}); go("recent") }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (op !== root.tag + "personal_picker") return
            if (error) { root.loading = false; console.warn("personal picker:", error); return }
            const v = JSON.parse(result)
            // (Only the folder shown now: a late answer for another is dropped.)
            const here = root.path.length ? root.path[root.path.length - 1].id : ""
            if (v.place !== root.place || (v.folder || "") !== here) return
            root.loading = false
            root.items = v.items || []
        }
    }
    function tap(it) {
        if (it.is_folder) { path = path.concat([{ id: it.id, name: it.name, drive: it.drive_id || "" }]); load(); return }
        const m = Object.assign({}, picked)
        if (m[it.id]) delete m[it.id]; else m[it.id] = true
        picked = m
    }
    function attach() {
        const files = pickedItems.map(i => ({ name: i.name, web_url: i.web_url || i.id, drive_id: i.drive_id, id: i.id, kind: i.kind }))
        if (!files.length) return
        close()
        root.attached(files)
    }
    function ago(t) {
        const d = new Date(t)
        if (isNaN(d)) return ""
        const s = Math.max(0, (Date.now() - d.getTime()) / 1000)
        if (s < 60) return qsTr("Just now")
        if (s < 3600) { const n = Math.round(s / 60); return n === 1 ? qsTr("1 minute ago") : qsTr("%1 minutes ago").arg(n) }
        if (s < 86400) { const n = Math.round(s / 3600); return n === 1 ? qsTr("1 hour ago") : qsTr("%1 hours ago").arg(n) }
        const n = Math.round(s / 86400)
        return n === 1 ? qsTr("Yesterday") : n < 30 ? qsTr("%1 days ago").arg(n) : d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }
    function size(b) { return b < 1024 ? qsTr("%1 bytes").arg(b) : b < 1048576 ? (b / 1024).toFixed(1) + " KB" : (b / 1048576).toFixed(2) + " MB" }
    function typeIcon(it) {
        if (it.is_folder) return "ft-folder-32"
        const t = String(it.kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }
    function stateForTest() { return { place: place, path: path.map(p => p.name), items: items.map(i => i.name), picked: pickedItems.map(i => i.name) } }
    function tapForTest(name) { const it = items.find(i => i.name === name); if (it) tap(it); return !!it }

    // The places.
    Rectangle {
        width: 224; height: parent.height
        topLeftRadius: 8; bottomLeftRadius: 8
        color: theme.pick("#F5F5F5", "#292929", "#000000")
        Text { x: 24; y: 22; text: qsTr("OneDrive"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
        Column {
            x: 16; y: 58; width: parent.width - 32
            spacing: 0
            Repeater {
                model: root.places
                Rectangle {
                    id: pl
                    required property var modelData
                    readonly property bool on: root.place === modelData.key
                    width: parent.width; height: 36; radius: 4
                    color: on ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : plHover.hovered ? theme.menuHover : "transparent"
                    Rectangle { visible: pl.on; x: -12; y: 8; width: 3; height: 20; radius: 1.5; color: theme.brand }
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; size: 20; name: pl.modelData.icon; color: pl.on ? theme.brand : theme.text }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: pl.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: pl.on ? Font.DemiBold : Font.Normal; color: theme.text }
                    HoverHandler { id: plHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.go(pl.modelData.key) }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: pl.modelData.label
                }
            }
        }
    }
    // The place.
    Item {
        x: 224; width: parent.width - 224; height: parent.height
        Row {
            x: 23; y: 30
            spacing: 6
            Repeater {
                model: [{ id: "", name: (root.places.find(p => p.key === root.place) || {}).label }].concat(root.path)
                Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    spacing: 6
                    Text {
                        visible: crumb.index > 0
                        text: ">"; font.family: theme.font; font.pixelSize: 20; color: theme.textSecondary
                    }
                    Text {
                        text: crumb.modelData.name || ""
                        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight
                        color: theme.text
                        HoverHandler { enabled: crumb.index < root.path.length; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: crumb.index < root.path.length; onTapped: { root.path = root.path.slice(0, crumb.index); root.load() } }
                    }
                }
            }
        }
        readonly property bool recentCols: root.place === "recent"
        Item {
            id: cols
            x: 16; y: 96; width: parent.width - 46; height: 44
            Text { x: 100; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Text { x: parent.width * 0.42; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.recentCols ? qsTr("Accessed") : qsTr("Modified"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Text { visible: !parent.parent.recentCols; x: parent.width * 0.62; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Modified by"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: theme.divider }
        }
        ListView {
            id: rows
            x: 16; y: cols.y + cols.height; width: cols.width; height: parent.height - y - 72
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.items
            delegate: Rectangle {
                id: rw
                required property var modelData
                readonly property bool sel: !!root.picked[modelData.id]
                width: rows.width; height: 58
                color: sel ? theme.pick("#EBEBEB", "#3D3D3D", "#1AEBFF") : rwHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 56; anchors.verticalCenter: parent.verticalCenter; size: 32; name: root.typeIcon(rw.modelData) }
                Column {
                    x: 100; anchors.verticalCenter: parent.verticalCenter
                    width: cols.width * 0.42 - 110
                    Text { width: parent.width; text: rw.modelData.name; elide: Text.ElideMiddle; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Text { visible: rw.modelData.size > 0 && root.place === "myfiles"; text: root.size(rw.modelData.size); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                }
                Text { x: cols.width * 0.42; anchors.verticalCenter: parent.verticalCenter; text: root.ago(rw.modelData.time); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { visible: root.place !== "recent"; x: cols.width * 0.62; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 8; elide: Text.ElideRight
                    text: rw.modelData.modified_by; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: theme.divider }
                HoverHandler { id: rwHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.tap(rw.modelData) }
                Accessible.role: Accessible.Row
                Accessible.name: rw.modelData.name
            }
        }
        Text {
            visible: !root.loading && root.items.length === 0
            anchors.centerIn: rows
            text: qsTr("This folder is empty")
            font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
        }
        BusyIndicator { anchors.centerIn: rows; running: root.loading; visible: running }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.bottom: parent.bottom; anchors.bottomMargin: 22
            spacing: 8
            Rectangle {
                readonly property bool ok: root.pickedItems.length > 0
                width: 80; height: 32; radius: 4
                color: !ok ? theme.pick("#F0F0F0", "#3D3D3D", "#000000") : atHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Attach"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.ok ? theme.textOnBrand : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
                HoverHandler { id: atHover; enabled: parent.ok; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: parent.ok; onTapped: root.attach() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Attach")
            }
            Rectangle {
                width: 80; height: 32; radius: 4
                color: cnHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 1
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cnHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cancel")
            }
        }
    }
}
