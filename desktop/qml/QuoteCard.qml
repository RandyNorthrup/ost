import QtQuick
import QtQuick.Controls.Basic

// Teams' quoted-reply card (measured in the client), in a reply's bubble
// and, with a dismiss button, in the compose box:
// - NeutralBackground2, a 1 px NeutralStroke3 border, radius 4, shadow 2;
// - a 2 px grey bar 4 in;
// - from 18 in: the sender and the quoted message's date and time (12 px,
//   NeutralForeground3, 8 apart), then its text (14 px);
// - 8 px after the widest line.
// Clicking the card in a bubble goes to the quoted message.
FluentSurface {
    id: root
    property var quote
    property bool dismissable: false
    // The report dialog's card shows the name only.
    property bool showTime: true
    property real maxWidth: 640
    signal dismissed()
    signal activated()
    depth: 2; radius: 4
    color: theme.quoteFill; borderColor: theme.quoteBorder
    readonly property string stamp: {
        const ms = parseInt(quote ? quote.message_id : "")
        return isNaN(ms) ? "" : Qt.formatDateTime(new Date(ms), "M/d/yyyy h:mm AP")
    }
    readonly property real headerW: nameText.implicitWidth + (showTime ? 8 + timeText.implicitWidth : 0) + (dismissable ? 8 + 20 : 0)
    width: Math.min(maxWidth, 18 + Math.max(headerW, previewMetrics.advanceWidth) + 8)
    height: dismissable ? 56 : 52
    Rectangle { x: 4; y: 4; width: 2; height: parent.height - 8; radius: 1; color: theme.quoteBar }
    Text {
        id: nameText
        x: 18; y: root.dismissable ? 9 : 7
        text: root.quote ? root.quote.sender_name : ""
        font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
    }
    Text {
        id: timeText
        x: nameText.x + nameText.implicitWidth + 8; y: nameText.y
        text: root.showTime ? root.stamp : ""
        font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
    }
    FontMetrics { id: previewFont; font.family: theme.font; font.pixelSize: theme.base }
    TextMetrics { id: previewMetrics; font: previewFont.font; text: root.quote ? root.quote.preview : "" }
    Text {
        x: 18; y: root.dismissable ? 28 : 24
        width: root.width - 18 - 8
        text: root.quote ? root.quote.preview : ""
        elide: Text.ElideRight; maximumLineCount: 1
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    Rectangle {
        visible: root.dismissable
        x: root.width - 8 - 20; y: 7; width: 20; height: 20; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textStrong }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Remove Reference"
    }
    HoverHandler { enabled: !root.dismissable; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: !root.dismissable; onTapped: root.activated() }
    Accessible.role: Accessible.Grouping
    Accessible.name: "Begin quote, " + (quote ? quote.sender_name : "") + ", " + stamp + ", " + (quote ? quote.preview : "") + ", End quote"
}
