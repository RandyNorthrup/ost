import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Shapes
import QtCore

// Add a background image (the announcement banner's Upload an image;
// Teams' dialog, measured on winpc 2026-11-09): 918 wide, padding 27 32 32,
// radius 8.
// - "Add a background image" (18/25.7 bold); Close (32, a 16 px dismiss) at
//   the top right.
// - No picture yet: a 854 x 360 drop area (a 2.67 px dashed #D1D1D1 line,
//   radius 3) with "To get the best result, choose an image that's at least
//   848x244 px." (12/16) in its middle and Upload an image (outline, 159.6 x
//   31.3) 14 from its bottom right; under it the same hint (a 12 px info
//   icon) and Cancel.
// - A picture: Teams' cropper (react-easy-crop) across the dialog (344.3
//   tall, the picture contained), a 848 x 244 frame (2 px white, the rest
//   under 50% white), drag to move, the wheel or the slider (1 to 4, 0.05
//   steps, 320 wide) to zoom; Upload an image on the picture to change it;
//   Cancel and Done.
// Done gives the framed part at the picture's own resolution, as a PNG.
Popup {
    id: dlg
    property url source: ""
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    signal picked(string path, int width, int height)

    readonly property bool hasPicture: preview.status === Image.Ready
    readonly property real areaW: 918
    readonly property real areaH: 344.3
    readonly property real frameW: 848
    readonly property real frameH: 244
    // The picture contained in the area at zoom 1.
    readonly property real fit: hasPicture ? Math.min(areaW / preview.implicitWidth, areaH / preview.implicitHeight) : 1
    readonly property real shownW: hasPicture ? preview.implicitWidth * fit * zoom : 0
    readonly property real shownH: hasPicture ? preview.implicitHeight * fit * zoom : 0
    // react-easy-crop's restrictPosition: the frame stays on the picture.
    function clampPan() {
        const mx = Math.max(0, (shownW - frameW) / 2), my = Math.max(0, (shownH - frameH) / 2)
        panX = Math.max(-mx, Math.min(mx, panX)); panY = Math.max(-my, Math.min(my, panY))
    }
    onZoomChanged: clampPan()

    function start() { source = ""; zoom = 1; panX = 0; panY = 0; open() }
    function pickFile() { files.open() }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 918; padding: 0
    height: hasPicture ? 560.7 : 504.7
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    FileDialog {
        id: files
        title: "Upload an image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"]
        onAccepted: { dlg.zoom = 1; dlg.panX = 0; dlg.panY = 0; dlg.source = selectedFile }
    }
    Image { id: preview; visible: false; source: dlg.source; asynchronous: true }

    component OutlineButton: Rectangle {
        id: ob
        property string icon
        property string label
        signal clicked()
        width: obRow.implicitWidth + 24; height: 31.3; radius: 4
        color: obHover.hovered ? theme.rowHover : theme.surface
        border.color: theme.stroke; border.width: 0.67
        Row {
            id: obRow
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: !!ob.icon; anchors.verticalCenter: parent.verticalCenter; size: 20; name: ob.icon; color: theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ob.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        }
        HoverHandler { id: obHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ob.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    contentItem: Item {
        Text {
            x: 32; y: 27
            text: "Add a background image"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            x: 862; y: 24; width: 32; height: 32; radius: 4
            color: xHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 16; name: "dismiss-16"; color: theme.text }
            HoverHandler { id: xHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }

        // No picture yet: the drop area.
        Item {
            visible: !dlg.hasPicture
            x: 32; y: 60.7; width: 854; height: 360
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: theme.stroke; strokeWidth: 2.67
                    strokeStyle: ShapePath.DashLine; dashPattern: [2, 2]
                    fillColor: "transparent"
                    startX: 3; startY: 1.3
                    PathLine { x: 854 - 3; y: 1.3 }
                    PathArc { x: 854 - 1.3; y: 3; radiusX: 3; radiusY: 3 }
                    PathLine { x: 854 - 1.3; y: 360 - 3 }
                    PathArc { x: 854 - 3; y: 360 - 1.3; radiusX: 3; radiusY: 3 }
                    PathLine { x: 3; y: 360 - 1.3 }
                    PathArc { x: 1.3; y: 360 - 3; radiusX: 3; radiusY: 3 }
                    PathLine { x: 1.3; y: 3 }
                    PathArc { x: 3; y: 1.3; radiusX: 3; radiusY: 3 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: 168
                text: "To get the best result, choose an image that's at least 848x244 px."
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.pick("#0F0F0F", "#FFFFFF")
            }
            OutlineButton {
                x: parent.width - 14.3 - width; y: 314
                icon: "arrow-upload-20"; label: "Upload an image"
                onClicked: dlg.pickFile()
            }
        }

        // A picture: the cropper.
        Item {
            id: area
            visible: dlg.hasPicture
            x: 0; y: 68.6; width: dlg.areaW; height: dlg.areaH
            clip: true
            Image {
                id: shown
                source: dlg.source
                width: dlg.shownW; height: dlg.shownH
                x: (area.width - width) / 2 + dlg.panX
                y: (area.height - height) / 2 + dlg.panY
                smooth: true; mipmap: true
            }
            // The frame and the 50% white shade around it.
            readonly property real fx: (width - dlg.frameW) / 2
            readonly property real fy: (height - dlg.frameH) / 2
            Rectangle { x: 0; y: 0; width: area.width; height: area.fy; color: Qt.rgba(1, 1, 1, 0.5) }
            Rectangle { x: 0; y: area.fy + dlg.frameH; width: area.width; height: area.height - area.fy - dlg.frameH; color: Qt.rgba(1, 1, 1, 0.5) }
            Rectangle { x: 0; y: area.fy; width: area.fx; height: dlg.frameH; color: Qt.rgba(1, 1, 1, 0.5) }
            Rectangle { x: area.fx + dlg.frameW; y: area.fy; width: area.width - area.fx - dlg.frameW; height: dlg.frameH; color: Qt.rgba(1, 1, 1, 0.5) }
            Rectangle { x: area.fx; y: area.fy; width: dlg.frameW; height: dlg.frameH; color: "transparent"; border.color: "white"; border.width: 2 }
            DragHandler {
                target: null
                cursorShape: Qt.SizeAllCursor
                property real sx: 0
                property real sy: 0
                onActiveChanged: if (active) { sx = dlg.panX; sy = dlg.panY }
                onTranslationChanged: { dlg.panX = sx + translation.x; dlg.panY = sy + translation.y; dlg.clampPan() }
            }
            WheelHandler {
                onWheel: event => { dlg.zoom = Math.max(1, Math.min(4, dlg.zoom + event.angleDelta.y / 120 * 0.05 * 2)) }
            }
            OutlineButton {
                x: 712.4; y: 251.8
                icon: "arrow-upload-20"; label: "Upload an image"
                onClicked: dlg.pickFile()
            }
        }
        // Zoom.
        Slider {
            id: zoomSlider
            visible: dlg.hasPicture
            x: 299 - 5; y: 460.7 - 3; width: 320 + 10; height: 22
            from: 1; to: 4; stepSize: 0.05
            value: dlg.zoom
            onMoved: dlg.zoom = value
            leftPadding: 5; rightPadding: 5
            background: Rectangle {
                x: zoomSlider.leftPadding; y: (zoomSlider.height - 2) / 2
                width: zoomSlider.availableWidth; height: 2; color: theme.stroke
            }
            handle: Rectangle {
                x: zoomSlider.leftPadding + zoomSlider.visualPosition * zoomSlider.availableWidth - 5
                y: (zoomSlider.height - 10) / 2
                width: 10; height: 10; radius: 5
                color: theme.textSecondary
            }
            Accessible.name: "Image Crop slider. The number value represents amplifying multiplier."
        }
        // The hint and the buttons.
        Row {
            x: 32; y: dlg.hasPicture ? 504.7 : 448.7; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 12; name: "info-12"; color: theme.pick("#0F0F0F", "#FFFFFF") }
            Text {
                text: "To get the best result, choose an image that's at least 848x244 px."
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.pick("#0F0F0F", "#FFFFFF")
            }
        }
        Rectangle {
            x: dlg.hasPicture ? 686 : 790; y: dlg.hasPicture ? 496.7 : 440.7
            width: 96; height: 32; radius: 4
            color: cancelHover.hovered ? theme.rowHover : theme.surface
            border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Cancel"
        }
        Rectangle {
            visible: dlg.hasPicture
            x: 790; y: 496.7
            width: 96; height: 32; radius: 4
            color: doneHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Done"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            HoverHandler { id: doneHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.finish() }
            Accessible.role: Accessible.Button; Accessible.name: "Done"
        }
    }

    // The framed part at the picture's resolution: the picture placed as
    // shown, under a frame-sized window, grabbed at the natural size.
    Item {
        id: cropper
        parent: dlg.contentItem
        visible: false
        x: -width - 10; y: 0
        width: dlg.frameW; height: dlg.frameH
        clip: true
        Image {
            source: dlg.source
            width: dlg.shownW; height: dlg.shownH
            x: (dlg.areaW - width) / 2 + dlg.panX - (dlg.areaW - dlg.frameW) / 2
            y: (dlg.areaH - height) / 2 + dlg.panY - (dlg.areaH - dlg.frameH) / 2
            smooth: true; mipmap: true
        }
    }
    function finish() {
        // The frame in the picture's own pixels (at most 4096 wide).
        const per = 1 / (fit * zoom)
        let w = Math.round(frameW * per), h = Math.round(frameH * per)
        if (w > 4096) { h = Math.round(h * 4096 / w); w = 4096 }
        const dir = String(StandardPaths.writableLocation(StandardPaths.CacheLocation)).replace(/^file:\/\//, "")
        const out = dir + "/announcement-" + Date.now() + ".png"
        cropper.visible = true
        cropper.grabToImage(r => {
            cropper.visible = false
            if (r.saveToFile(out)) { dlg.picked("file://" + out, w, h); dlg.close() }
        }, Qt.size(w, h))
    }

    // Test hooks.
    function setSourceForTest(u) { source = u }
}
