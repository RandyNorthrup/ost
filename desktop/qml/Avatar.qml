import QtQuick
import QtQuick.Window

// Profile picture, or initials in Teams' muted per-person colour when
// there is none.
Rectangle {
    id: root
    property string name
    property int size: 32
    /// Whose picture: "me", a user MRI/object id, or "team:<group id>".
    /// Empty shows initials only.
    property string photoId: ""
    /// Teams draw teams as rounded squares, people as circles.
    property bool square: false
    /// Teams take initials from the first two words of a team's name.
    property string initialsText: ""
    // Ask only once the name is known: Teams draws the initials picture
    // from it for people without a photo.
    readonly property bool canAsk: photoId.length > 0 && name.length > 0 && name !== "?"
    property string photo: canAsk ? backend.photoFor(photoId, name) : ""
    onCanAskChanged: photo = canAsk ? backend.photoFor(photoId, name) : ""
    onPhotoIdChanged: photo = canAsk ? backend.photoFor(photoId, name) : ""
    onNameChanged: photo = canAsk ? backend.photoFor(photoId, name) : ""
    Connections {
        target: backend
        enabled: root.canAsk && root.photo.length === 0
        function onPhotoReady(id) { if (id === root.photoId) root.photo = backend.photoFor(root.photoId, root.name) }
    }
    /// Presence availability (Available, Busy, DoNotDisturb, Away,
    /// BeRightBack, Offline…); empty hides the badge.
    property string presence: ""
    width: size
    height: size
    radius: square ? theme.radius : size / 2
    readonly property var swatches: ["#E8C8CA", "#D6E6F7", "#DFF6DD", "#FCE4D6", "#E9E3F7", "#D4EDEB"]
    readonly property var inks: ["#751D1F", "#0F548C", "#0E700E", "#8A3707", "#5C2E91", "#00666D"]
    readonly property int hue: {
        let h = 0
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 997
        return h % swatches.length
    }
    color: pic.visible ? "transparent" : swatches[hue]

    function initials(n) {
        const words = n.trim().split(/\s+/).filter(w => w.length > 0)
        if (words.length === 0) return "?"
        if (words.length === 1) return words[0].substring(0, 2).toUpperCase()
        return (words[0][0] + words[words.length - 1][0]).toUpperCase()
    }

    // The picture: loaded by a hidden Image, then drawn clipped to the
    // avatar's shape on a canvas (no shaders, so it looks the same on
    // every renderer).
    Image {
        id: src
        visible: false
        source: root.photo
        asynchronous: true
        // Decode at the size shown (sharp, and no full-size copies kept).
        sourceSize.width: Math.ceil(root.size * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(root.size * Screen.devicePixelRatio)
        // The pixels reach the canvas a moment after Ready; paint again then.
        onStatusChanged: { pic.requestPaint(); if (status === Image.Ready) repaint.restart() }
    }
    Timer { id: repaint; interval: 50; onTriggered: pic.requestPaint() }
    Canvas {
        id: pic
        anchors.fill: parent
        visible: root.photo.length > 0 && src.status === Image.Ready
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (src.status !== Image.Ready) return
            ctx.beginPath()
            if (root.square) {
                ctx.roundedRect(0, 0, width, height, theme.radius, theme.radius)
            } else {
                ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI)
            }
            ctx.closePath()
            ctx.clip()
            ctx.drawImage(src, 0, 0, width, height)
        }
    }

    Text {
        visible: !pic.visible
        anchors.centerIn: parent
        text: root.initialsText || root.initials(root.name)
        color: root.inks[root.hue]
        font.family: theme.font
        font.pixelSize: Math.round(root.size * 0.38)
        font.weight: Font.DemiBold
    }

    // Presence badge, bottom right, with the surface-coloured ring Teams uses.
    Rectangle {
        readonly property int d: root.size <= 24 ? 8 : (root.size <= 40 ? 10 : Math.round(root.size * 0.22))
        readonly property string p: root.presence.toLowerCase()
        visible: root.presence.length > 0
        width: d + 2; height: d + 2; radius: width / 2
        x: root.width - d + 1; y: root.height - d + 1
        color: theme.surface
        Rectangle {
            anchors.centerIn: parent
            width: parent.d; height: parent.d; radius: width / 2
            readonly property bool offline: parent.p === "offline" || parent.p === "presenceunknown" || parent.p === ""
            color: offline ? "transparent"
                : parent.p === "available" ? "#13A10E"
                : (parent.p === "busy" || parent.p === "donotdisturb") ? "#C4314B"
                : "#EAA300"
            border.width: offline ? 1.5 : 0
            border.color: "#8A8886"
            // Do not disturb: a white bar across the red dot.
            Rectangle {
                visible: parent.parent.p === "donotdisturb"
                anchors.centerIn: parent
                width: parent.width * 0.55; height: Math.max(1, parent.height * 0.18)
                color: "white"
            }
        }
    }
}
