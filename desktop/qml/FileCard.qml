import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

// A file in a message, as Teams draws it (OST TEST 121, measured on winpc
// 2026-11-13): a 320 wide card, radius 6, a 0.67 #E0E0E0 edge and a soft
// shadow.
// - The head: 48.67 tall, #FAFAFA, a 0.67 #E0E0E0 line under it. "Main
//   actions" (238.67 x 44 at 8, 2, radius 8; white on hover) holds the
//   32 px type icon at 4, 6 and, at 44, the name (14/20 semibold) over
//   where it lives (12/16 #616161: Teams' breadcrumbs, "personal >
//   ost-test1_…"); clicking opens the file.
// - Share (32 x 31.33 at 246.67, 8.33; a 20 px #616161 glyph) opens Share
//   this file; More actions (···, the same size, radius 6) opens the menu:
//   Open in Browser, Download, Share, Copy link, Favorite / Unfavorite.
// - The preview: 318.67 x 179.33 (16:9), #F5F5F5 under the picture; a
//   file without one keeps the head alone.
Item {
    id: root
    /// The file (a message's properties.files entry, as parse_files reads it).
    property var file: ({})
    /// The preview picture (a local file URL), or "".
    property string thumbnail: ""
    /// Hover look for tests (grabToImage has no pointer).
    property bool hoverForTest: false
    signal openRequested()
    signal shareRequested()
    signal menuRequested(Item anchor)
    readonly property bool hasPreview: thumbnail !== "" && pic.status !== Image.Error
    readonly property real hair: Math.max(0.67, 1 / Screen.devicePixelRatio)
    width: 320
    height: hasPreview ? 229.33 : 50
    Accessible.role: Accessible.Grouping
    Accessible.name: file.name || ""

    function moreButtonForTest() { return moreButton }
    function typeIcon(kind) {
        const t = String(kind || "").toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx"
                : t === "pdf" ? "pdf" : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop"
                : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(t) >= 0 ? "photo"
                : ["mp4", "mov", "avi", "mkv", "webm", "wmv", "m4v"].indexOf(t) >= 0 ? "video" : "genericfile"
        return "ft-" + k + "-32"
    }

    FluentSurface { anchors.fill: parent; depth: 2; radius: 6; color: theme.surface }
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "transparent"
        border.width: root.hair
        border.color: theme.pick("#E0E0E0", "#3D3D3D")
        z: 3
    }
    Item {
        id: inner
        x: 0.67; y: 0.67
        width: parent.width - 1.33; height: parent.height - 1.33
        clip: true
        // The head
        Rectangle {
            id: head
            width: parent.width; height: 48.67
            color: theme.pick("#FAFAFA", "#1F1F1F")
            radius: 5.33
            Rectangle { y: parent.height - 6; width: parent.width; height: 6; color: parent.color; visible: root.hasPreview }
            Rectangle { y: parent.height - root.hair; width: parent.width; height: root.hair; color: theme.pick("#E0E0E0", "#3D3D3D"); visible: root.hasPreview }
            Rectangle {
                id: main
                x: 8; y: 2; width: 238.67; height: 44; radius: 8
                color: mainHover.hovered || root.hoverForTest ? theme.surface : "transparent"
                FluentIcon { x: 4; y: 6; size: 32; name: root.typeIcon(root.file.file_type) }
                Column {
                    x: 44; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44
                    Text {
                        width: parent.width
                        text: root.file.name || ""
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: root.file.location || ""
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 12
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                }
                HoverHandler { id: mainHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openRequested() }
                ToolTip.visible: mainHover.hovered
                ToolTip.delay: 500
                ToolTip.text: (root.file.name || "") + "\n" + (root.file.object_url || "")
                Accessible.role: Accessible.Link
                Accessible.name: root.file.name || ""
            }
            Row {
                x: 246.67; y: 8.33
                Rectangle {
                    width: 32; height: 31.33; radius: 4
                    color: "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 20; name: "share-20"; color: shareHover.hovered ? theme.brand : theme.textSecondary }
                    HoverHandler { id: shareHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.shareRequested() }
                    ToolTip.visible: shareHover.hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Share"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Share"
                }
                Rectangle {
                    id: moreButton
                    width: 32; height: 31.33; radius: 6
                    color: moreHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 20; name: "more-horizontal-20"; color: moreHover.hovered ? theme.textStrong : theme.textSecondary }
                    HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.menuRequested(moreButton) }
                    ToolTip.visible: moreHover.hovered
                    ToolTip.delay: 500
                    ToolTip.text: "More actions"
                    Accessible.role: Accessible.Button
                    Accessible.name: "More actions"
                }
            }
        }
        // The preview
        Rectangle {
            visible: root.hasPreview
            y: 48.67; width: parent.width; height: 179.33
            color: theme.pick("#F5F5F5", "#141414")
            Image {
                id: pic
                anchors.fill: parent
                source: root.thumbnail
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                asynchronous: true
                sourceSize.width: 640
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openRequested() }
            Accessible.role: Accessible.Button
            Accessible.name: "Thumbnail Preview"
        }
    }
}
