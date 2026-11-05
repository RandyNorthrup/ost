import QtQuick

// Initials avatar with Teams' muted per-person colour.
Rectangle {
    id: root
    property string name
    property int size: 32
    /// Presence availability (Available, Busy, DoNotDisturb, Away,
    /// BeRightBack, Offline…); empty hides the badge.
    property string presence: ""
    width: size
    height: size
    radius: size / 2
    readonly property var swatches: ["#E8C8CA", "#D6E6F7", "#DFF6DD", "#FCE4D6", "#E9E3F7", "#D4EDEB"]
    readonly property var inks: ["#751D1F", "#0F548C", "#0E700E", "#8A3707", "#5C2E91", "#00666D"]
    readonly property int hue: {
        let h = 0
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 997
        return h % swatches.length
    }
    color: swatches[hue]

    function initials(n) {
        const words = n.trim().split(/\s+/).filter(w => w.length > 0)
        if (words.length === 0) return "?"
        if (words.length === 1) return words[0].substring(0, 2).toUpperCase()
        return (words[0][0] + words[words.length - 1][0]).toUpperCase()
    }

    Text {
        anchors.centerIn: parent
        text: root.initials(root.name)
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
