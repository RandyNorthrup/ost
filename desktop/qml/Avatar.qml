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
    /// A square's corner: 4 in lists, 2 in headers (as measured).
    property real squareRadius: theme.radius
    /// A group chat without a picture: Teams' grey circle with people.
    property bool group: false
    /// A meeting's chat: Teams' #C5CBFA circle with the 16 px calendar
    /// glyph in brand (measured on winpc at 20 and 32 px).
    property bool meeting: false
    /// The glyph's size: 16 in lists and cards, 32 (filling it) in the
    /// chat header.
    property int meetingGlyph: 16
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
    /// Clicking opens the person's profile card (Teams does this for
    /// people's pictures in messages, the people pane and 1:1 headers).
    property bool opensProfile: false
    HoverHandler { enabled: root.opensProfile && root.photoId.indexOf("8:orgid:") === 0; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: root.opensProfile && root.photoId.indexOf("8:orgid:") === 0
        onTapped: backend.requestProfile(root.photoId)
    }
    width: size
    height: size
    radius: square ? squareRadius : size / 2
    /// Fluent's colourful avatar, as Teams' Fluent pickers draw people
    /// without a picture (Meeting options): the colour hashed from the name
    /// with Fluent's getHashCode over its 30 persona colours (Background2
    /// with Foreground2 initials, swapped in dark), the initials in Fluent's
    /// type ramp, one initial at 16 px. Read from Teams on winpc 2026-11-11.
    property bool colorful: false
    readonly property var fluentPalette: [
        ["#D69CA5", "#420610"], ["#EEACB2", "#6E0811"], ["#F1BBBC", "#751D1F"], ["#EFC4AD", "#712D09"], ["#FFDDB3", "#8F4E00"],
        ["#F9E2AE", "#835B00"], ["#ECDFA5", "#6C5700"], ["#E0CEA2", "#553E06"], ["#DDC3B0", "#50301A"], ["#BDD99B", "#294903"],
        ["#A8F0CD", "#00723B"], ["#9AD29A", "#063B06"], ["#A6E9ED", "#00666D"], ["#9BD9DB", "#02494C"], ["#94C8D4", "#00333F"],
        ["#A9D3F2", "#004377"], ["#9ABFDC", "#002C4E"], ["#C8D1FA", "#2C3C85"], ["#A3B2E8", "#001665"], ["#D2CCF8", "#3F3682"],
        ["#C6B1DE", "#341A51"], ["#D9A7E0", "#4C0D55"], ["#E6BFED", "#63276D"], ["#F7C0E3", "#80215D"], ["#ECA5D1", "#6B0043"],
        ["#D696C0", "#43002B"], ["#D7D4D4", "#444241"], ["#CECCCB", "#343231"], ["#CDD6D8", "#3B4447"], ["#BCC3C7", "#202427"]]
    readonly property var fluentColors: {
        let h = 0
        for (let i = name.length - 1; i >= 0; i--) {
            const ch = name.charCodeAt(i), shift = i % 8
            h ^= (ch << shift) + (ch >> (8 - shift))
        }
        const pair = fluentPalette[Math.abs(h) % fluentPalette.length]
        return [theme.pick(pair[0], pair[1]), theme.pick(pair[1], pair[0])]
    }
    readonly property var swatches: ["#E8C8CA", "#D6E6F7", "#DFF6DD", "#FCE4D6", "#E9E3F7", "#D4EDEB"]
    readonly property var inks: ["#751D1F", "#0F548C", "#0E700E", "#8A3707", "#5C2E91", "#00666D"]
    readonly property int hue: {
        let h = 0
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 997
        return h % swatches.length
    }
    color: meeting ? "#C5CBFA" : pic.visible ? "transparent" : group ? "#949494" : colorful ? fluentColors[0] : swatches[hue]

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
        visible: !root.meeting && root.photo.length > 0 && src.status === Image.Ready
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (src.status !== Image.Ready) return
            ctx.beginPath()
            if (root.square) {
                ctx.roundedRect(0, 0, width, height, root.squareRadius * oversample, root.squareRadius * oversample)
            } else {
                ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI)
            }
            ctx.closePath()
            ctx.clip()
            ctx.drawImage(src, 0, 0, width, height)
        }
    }

    FluentIcon {
        visible: root.meeting
        anchors.centerIn: parent
        name: "meeting-chat-20"; size: root.meetingGlyph
        color: "#5B5FC7"
    }
    FluentIcon {
        visible: root.group && !root.meeting && !pic.visible
        anchors.centerIn: parent
        name: root.size > 24 ? "people-team-20" : "people-team-16"
        size: Math.round(root.size * 0.55)
        color: "white"
    }
    Text {
        visible: !pic.visible && !root.group && !root.meeting
        anchors.centerIn: parent
        text: root.initialsText || (root.colorful && root.size <= 16 ? root.initials(root.name).charAt(0) : root.initials(root.name))
        color: root.colorful ? root.fluentColors[1] : root.inks[root.hue]
        font.family: theme.font
        font.pixelSize: root.colorful ? (root.size <= 24 ? 10 : root.size <= 28 ? 12 : root.size <= 40 ? 14 : Math.round(root.size * 0.38)) : Math.round(root.size * 0.38)
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
