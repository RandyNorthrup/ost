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
    /// A group chat without a picture: Teams' grey circle with people.
    property bool group: false
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
    color: pic.visible ? "transparent" : group ? "#949494" : swatches[hue]

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
        // Decode at the canvas' resolution (sharp, and no full-size copies kept).
        sourceSize.width: Math.ceil(pic.width * Math.max(1, Screen.devicePixelRatio))
        sourceSize.height: Math.ceil(pic.height * Math.max(1, Screen.devicePixelRatio))
        // The pixels reach the canvas a moment after Ready; paint again then.
        onStatusChanged: { pic.requestPaint(); if (status === Image.Ready) repaint.restart() }
    }
    Timer { id: repaint; interval: 50; onTriggered: pic.requestPaint() }
    // Painted at twice the avatar's size and scaled down, so the picture
    // (often Teams' small initials image) stays sharp on scaled screens
    // where a canvas the avatar's size would be stretched and blurred.
    Canvas {
        id: pic
        readonly property real oversample: 2
        width: root.width * oversample; height: root.height * oversample
        scale: 1 / oversample
        transformOrigin: Item.TopLeft
        smooth: true
        antialiasing: true
        visible: root.photo.length > 0 && src.status === Image.Ready
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (src.status !== Image.Ready) return
            ctx.beginPath()
            if (root.square) {
                ctx.roundedRect(0, 0, width, height, theme.radius * oversample, theme.radius * oversample)
            } else {
                ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI)
            }
            ctx.closePath()
            ctx.clip()
            ctx.drawImage(src, 0, 0, width, height)
        }
    }

    FluentIcon {
        visible: root.group && !pic.visible
        anchors.centerIn: parent
        name: root.size > 24 ? "people-team-20" : "people-team-16"
        size: Math.round(root.size * 0.55)
        color: "white"
    }
    Text {
        visible: !pic.visible && !root.group
        anchors.centerIn: parent
        text: root.initialsText || root.initials(root.name)
        color: root.inks[root.hue]
        font.family: theme.font
        font.pixelSize: Math.round(root.size * 0.38)
        font.weight: Font.DemiBold
    }

    // Presence badge, flush with the avatar's bottom-right corner.
    PresenceBadge {
        presence: root.presence
        total: root.size >= 96 ? 28 : root.size >= 64 ? 20 : root.size >= 56 ? 16
            : root.size >= 40 ? 12 : root.size >= 28 ? 10 : 6
        x: root.width - total; y: root.height - total
    }
}
