import QtQuick
import QtQuick.Effects

// Teams' in-call alerts (calling-alerts; seen on winpc 2026-11-11 in a
// breakout rooms meeting): a 320 wide white card at the top of the stage
// with radius 8, the alert's text (14/20, wrapping) and Dismiss at the
// right; some lead with a 20 px glyph ("Breakout rooms have been
// created." with the rooms glyph). "We'll move you to your assigned room
// in 10 seconds." wraps to two lines.
Item {
    id: root
    property string icon: ""
    property string text
    /// A title above the text (Teams' alerts with one, such as
    /// PowerPoint Live's "Another user took control").
    property string title: ""
    /// An action button under the text ("Take back").
    property string actionText: ""
    /// The text is Teams' HTML (rich text: styled spans, <a href>).
    property bool richText: false
    signal dismissed()
    signal action()
    width: 320
    height: Math.max(41.33, body.y + body.height + (actionText ? 8 + 32 : 0) + 10.67)
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 0.6; blur: 1.8; color: theme.shadowAmbient }
    RectangularShadow { anchors.fill: surface; radius: 8; offset.y: 3.2; blur: 7.2; color: theme.shadowKey }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 8
        color: theme.surface
    }
    FluentIcon {
        visible: root.icon.length > 0
        x: 14.67; y: 10.67; size: 20
        name: root.icon
        color: theme.textStrong
    }
    Text {
        id: heading
        visible: root.title.length > 0
        x: body.x; y: 10.67
        width: body.width
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: root.title
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        color: theme.text
    }
    Text {
        id: body
        x: root.icon.length > 0 ? 44 : 12.67; y: root.title.length > 0 ? heading.y + heading.height : 10.67
        width: root.width - x - 44
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        // Alerts whose text Teams gives as HTML (a span at 600, a link).
        text: root.richText ? "<style>a { color: " + theme.brandLink + "; text-decoration: none; }</style>" + root.text : root.text
        textFormat: root.richText ? Text.RichText : Text.PlainText
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { enabled: root.richText; cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        font.family: theme.font; font.pixelSize: 14
        color: root.icon.length > 0 ? theme.textSecondary : theme.text
    }
    Rectangle {
        id: actionButton
        visible: root.actionText.length > 0
        x: body.x; y: body.y + body.height + 8
        width: actionLabel.implicitWidth + 24; height: 32; radius: 4
        color: actionHover.pressed ? theme.pick("#E0E0E0", "#1F1F1F", "#000000") : actionHover.hovered ? theme.pick("#F5F5F5", "#3D3D3D", "#000000") : theme.surface
        border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Text {
            id: actionLabel
            anchors.centerIn: parent
            text: root.actionText
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
        }
        HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor; property bool pressed: actionTap.pressed }
        TapHandler { id: actionTap; onTapped: root.action() }
        Accessible.role: Accessible.Button
        Accessible.name: root.actionText
    }
    Rectangle {
        id: hcFill1
        x: root.width - 36; y: 6.67; width: 28; height: 28; radius: 4
        color: dismissHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(hcFill1, theme.textSecondary) }
        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.dismissed() }
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss"
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.title ? root.title + " " + root.text : root.text
}
