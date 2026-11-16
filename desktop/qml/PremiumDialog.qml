import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// Teams' "Start your free Teams Premium trial" (Settings and more ▸ Unlock
// Teams Premium; measured on winpc 2026-11-15): 600 x 600, centred;
// Teams' header picture (600 x 128) with Close (32 x 31.33, white at 50%)
// 24 in; the premium diamond (68) in a 108 px round badge (white to
// #C6B1DE, 136°) overlapping it at 74; the title (24/32 bold) centred at
// 197; three features (52 px pictures at 110,
// titles 14/20 semibold and text 12/16 #616161 at 177, 313 wide) at 244,
// 311 and 378; "Free 60-day trial, no card required." (12/20 #616161) and
// the Trial Terms & Conditions link centred at 460 and 480; "View all
// benefits" (subtle) 24 in and Start trial (primary) 24 from the right at
// 544.67. Start trial takes the low-friction trial (the auth service's
// lfts/TeamsPremium/acquire).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 600
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    readonly property var st: backend.premiumJson ? JSON.parse(backend.premiumJson) : ({})
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    Item {
        width: 600; height: 128
        clip: true
        Rectangle {
            width: 600; height: 136; radius: 8; color: "transparent"; clip: true
            Image { width: 600; height: 128; source: "../assets/dialogs/premium-header.png"; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true }
        }
    }
    Rectangle {
        x: 544; y: 24; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.5)
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: "#424242" }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
        Accessible.onPressAction: root.close()
    }
    // The badge: a circle filled with Teams' 136° gradient.
    Shape {
        x: 246; y: 74; width: 108; height: 108
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"
            fillGradient: LinearGradient {
                // 136° in CSS runs top left to bottom right, a little steeper.
                x1: 54 - 54 * Math.sin(136 * Math.PI / 180); y1: 54 + 54 * Math.cos(136 * Math.PI / 180)
                x2: 54 + 54 * Math.sin(136 * Math.PI / 180); y2: 54 - 54 * Math.cos(136 * Math.PI / 180)
                GradientStop { position: 0.1669; color: "#FFFFFF" }
                GradientStop { position: 1.2623; color: "#C6B1DE" }
            }
            PathAngleArc { centerX: 54; centerY: 54; radiusX: 54; radiusY: 54; startAngle: 0; sweepAngle: 360 }
        }
    }
    Image {
        x: 266; y: 94; width: 68; height: 68
        source: "../assets/dialogs/premium-diamond.svg"
        sourceSize: Qt.size(136, 136)
        smooth: true
    }
    // The title (Teams' style names a gradient, but its text draws in the
    // plain #242424, as on winpc).
    Text {
        width: root.width; y: 197
        horizontalAlignment: Text.AlignHCenter
        text: "Start your free Teams Premium trial"
        font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Repeater {
        model: [
            { y: 244, image: "premium-protected.svg", title: "More protected", text: "Expand security in meetings & calls with added controls and features." },
            { y: 311, image: "premium-engaging.svg", title: "More engaging", text: "Build stronger connections with branded experiences in meetings and collaborative call handling in Queues app." },
            { y: 378, image: "premium-intelligent.svg", title: "More intelligent", text: "Use AI to focus on what matters most in every meeting or call." }
        ]
        Item {
            required property var modelData
            y: modelData.y; width: root.width; height: 52
            Image { x: 110; width: 52; height: 52; source: "../assets/dialogs/" + parent.modelData.image; sourceSize: Qt.size(104, 104); smooth: true }
            Text { x: 177; width: 313; text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { x: 177; y: 20; width: 313; text: parent.modelData.text; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter; y: 460
        // Teams' strings for Start trial's steps (premium-benefits): the
        // wait, the failure and success. Their own dialogs' layout isn't
        // measured yet (no trial was started on the test accounts).
        text: root.st.starting ? "Getting your trial ready..."
            : root.st.error ? "We ran into a problem setting up your trial. Let's try again."
            : root.st.started ? "Your Teams Premium trial is now active!"
            : "Free 60-day trial, no card required."
        font.family: theme.font; font.pixelSize: 12; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: root.st.error ? theme.danger : theme.textSecondary
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter; y: 480
        text: "Microsoft Teams Trial Terms & Conditions."
        font.family: theme.font; font.pixelSize: 12; lineHeight: 14; lineHeightMode: Text.FixedHeight
        color: theme.brandLink
        font.underline: termsHover.hovered
        HoverHandler { id: termsHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2194722") }
        Accessible.role: Accessible.Link
        Accessible.name: text
    }
    Rectangle {
        x: 24; y: 544.67; width: 129.39; height: 31.33; radius: 4
        color: benefitsHover.hovered ? theme.menuHover : "transparent"
        Text { anchors.centerIn: parent; text: "View all benefits"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
        HoverHandler { id: benefitsHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2227979") }
        Accessible.role: Accessible.Button
        Accessible.name: "View all benefits"
    }
    Rectangle {
        x: 480; y: 544.67; width: 96; height: 31.33; radius: 4
        color: startHover.hovered && !root.st.starting ? theme.brandHover : theme.brandFill; opacity: root.st.starting ? 0.6 : 1
        readonly property string label: root.st.started ? "Got it" : root.st.error ? "Try again" : "Start trial"
        Text { id: startText; anchors.centerIn: parent; text: parent.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
        HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !root.st.starting; onTapped: { if (root.st.started) root.close(); else backend.startPremiumTrial() } }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
