import QtQuick

// Initials avatar with Teams' muted per-person colour.
Rectangle {
    id: root
    property string name
    property int size: 32
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
}
