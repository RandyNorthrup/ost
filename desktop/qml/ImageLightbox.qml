import QtQuick
import QtQuick.Controls.Basic

// Teams' picture viewer (its PhotoSwipe lightbox, measured on winpc
// 2026-11-22 opening "OST TEST 246 image post"'s picture): over the app
// under the title bar,
// - a #3D3D3D backdrop at 90 %;
// - a 60 px bar (#292929, padding 14 20): Back (an arrow, 32 x 31.3), then
//   at 62 the sender (14/20 semibold, white) over "image | {when} | Show
//   message" (12/16 #D6D6D6, 0.67 x 12 #525252 dividers 4 either side,
//   Show message #7F85F5); at the end Zoom out, Zoom in, a divider and
//   Download (32 x 31.3 buttons, 20 px white glyphs), 20 from the edge;
// - the picture centred under the bar at no more than its own size (an
//   800 x 450 picture showed 745 x 419 in a 1280 x 572 area: fitted to a
//   419 tall area, 10.5 above the middle).
// Esc or Back closes it; Left / Right step through the message's pictures.
Item {
    id: root
    visible: images.length > 0
    property var images: []
    property int index: 0
    property string sender: ""
    property string when: ""
    property string messageId: ""
    signal showMessage(string id)
    readonly property var current: images.length ? images[Math.max(0, Math.min(index, images.length - 1))] : null
    property real zoom: 1
    function show(list, i, who, at, id) { images = list || []; index = i || 0; sender = who || ""; when = at || ""; messageId = id || ""; zoom = 1; forceActiveFocus() }
    function close() { images = [] }
    Keys.onEscapePressed: close()
    Keys.onLeftPressed: if (index > 0) { index--; zoom = 1 }
    Keys.onRightPressed: if (index < images.length - 1) { index++; zoom = 1 }

    // Swallow clicks and wheel under it.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }
    Rectangle { anchors.fill: parent; color: theme.hc("#3D3D3D", "#000000"); opacity: 0.9 }

    // The picture.
    Item {
        id: area
        y: 60; width: parent.width; height: parent.height - 60
        readonly property real w0: root.current && root.current.width > 0 ? root.current.width : img.implicitWidth
        readonly property real h0: root.current && root.current.height > 0 ? root.current.height : img.implicitHeight
        // Fitted inside the area less Teams' margins (153 of height, 0
        // of width as measured), never above its own size.
        readonly property real fit: w0 > 0 && h0 > 0 ? Math.min(1, (width - 0) / w0, (height - 153) / h0) : 1
        Image {
            id: img
            source: root.current ? root.current.local_path || "" : ""
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            width: area.w0 * area.fit * root.zoom
            height: area.h0 * area.fit * root.zoom
            x: (area.width - width) / 2
            y: (area.height - height) / 2 - 10.5
            DragHandler { enabled: root.zoom > 1 }
        }
    }

    // The bar.
    Rectangle {
        width: parent.width; height: 60
        color: theme.hc("#292929", "#000000")
        BarButton { x: 20; y: 14.33; icon: "arrow-left-20"; tip: qsTr("Back"); onClicked: root.close() }
        Column {
            x: 62; y: 12
            width: Math.max(0, tools.x - 62 - 20)
            Text {
                width: parent.width; elide: Text.ElideRight
                text: root.sender
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: "white"
            }
            Row {
                height: 16
                spacing: 4
                Text { text: qsTr("image"); font.family: theme.font; font.pixelSize: 12; color: "#D6D6D6"; height: 16; verticalAlignment: Text.AlignVCenter }
                Rectangle { y: 2; width: 0.67; height: 12; color: "#525252" }
                Text { text: root.when; font.family: theme.font; font.pixelSize: 12; color: "#D6D6D6"; height: 16; verticalAlignment: Text.AlignVCenter }
                Rectangle { y: 2; width: 0.67; height: 12; color: "#525252" }
                Text {
                    text: qsTr("Show message")
                    height: 16; verticalAlignment: Text.AlignVCenter
                    rightPadding: 4
                    font.family: theme.font; font.pixelSize: 12; font.underline: showHover.hovered
                    color: theme.hc("#7F85F5", "#FFFF00")
                    HoverHandler { id: showHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { const id = root.messageId; root.close(); root.showMessage(id) } }
                    Accessible.role: Accessible.Button; Accessible.name: text
                }
            }
        }
        Row {
            id: tools
            anchors { right: parent.right; rightMargin: 20 }
            y: 14.33
            Row {
                leftPadding: 8; rightPadding: 8
                BarButton { icon: "zoom-out-20"; tip: qsTr("Zoom out"); onClicked: root.zoom = Math.max(1, root.zoom / 1.5) }
                BarButton { icon: "zoom-in-20"; tip: qsTr("Zoom in"); onClicked: root.zoom = Math.min(8, root.zoom * 1.5) }
            }
            Item { width: 8.7; height: 31.3; Rectangle { x: 0; y: 5.67; width: 0.67; height: 20; color: "#525252" } }
            BarButton { icon: "arrow-download-20"; tip: qsTr("Download"); onClicked: if (root.current) backend.imageDownload(root.current.local_path || "", "image") }
        }
    }

    component BarButton: Rectangle {
        id: bb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: bbHover.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: bb.icon; color: "white" }
        HoverHandler { id: bbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        ToolTip.visible: bbHover.hovered; ToolTip.text: bb.tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: bb.tip
    }
}
