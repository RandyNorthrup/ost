import QtQuick

// Teams' forward card (forward-message-card, measured in the client's
// forward dialog): white, a 1 px NeutralStroke1 border with a 4 px left
// edge, radius 4, padding 12. The header has the forward arrow (16), the
// original sender's avatar (20), their name and the original's date and time
// (12 px, NeutralForeground3). Under it is the original's text (14/20). The
// time links to the original ("Go to original message").
Rectangle {
    id: root
    property var forward
    property real maxWidth: 535
    signal openOriginal()
    readonly property string stamp: forward && forward.arrival_ms ? Qt.formatDateTime(new Date(forward.arrival_ms), "M/d/yyyy h:mm AP") : ""
    // The header ends at 68 + name + 9 + time; the card 12 px after its
    // widest line.
    readonly property real headerRight: 68 + nameText.implicitWidth + 9 + timeText.implicitWidth
    width: Math.min(maxWidth, Math.max(headerRight, 16 + bodyText.implicitWidth) + 12)
    height: 40 + Math.max(20, bodyText.implicitHeight) + 13
    radius: 4
    color: theme.surface
    border.color: theme.stroke
    Rectangle { x: 0; y: 0; width: 4; height: parent.height; color: theme.stroke; radius: 4 }
    Rectangle { x: 2; y: 0; width: 2; height: parent.height; color: theme.stroke }
    FluentIcon { x: 16; y: 14; name: "arrow-forward-16"; size: 16; color: theme.textStrong }
    Avatar {
        x: 40; y: 12; size: 20
        name: root.forward ? root.forward.sender_name : ""
        photoId: root.forward ? root.forward.sender_mri : ""
    }
    Text {
        id: nameText
        x: 68; y: 14; height: 16; verticalAlignment: Text.AlignVCenter
        text: root.forward ? root.forward.sender_name : ""
        font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
    }
    Text {
        id: timeText
        x: nameText.x + nameText.implicitWidth + 9; y: 14; height: 16; verticalAlignment: Text.AlignVCenter
        text: root.stamp
        // A link to the original (Teams: underlined, BrandForeground2).
        font.family: theme.font; font.pixelSize: theme.small; font.underline: true; color: theme.brandForeground2
        HoverHandler { id: timeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openOriginal() }
        Accessible.role: Accessible.Link
        Accessible.name: "Go to original message"
    }
    Text {
        id: bodyText
        x: 16; y: 40
        width: Math.min(implicitWidth, root.maxWidth - 32)
        text: !root.forward ? "" : root.forward.deleted ? "<i>This message was deleted.</i>" : (root.forward.html || root.forward.text)
        textFormat: Text.RichText
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: "Begin Reference, " + (forward ? forward.text : "") + ", " + (forward ? forward.sender_name : "") + ", " + stamp + ", End reference"
}
