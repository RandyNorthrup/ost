import QtQuick
import QtQuick.Controls

// Teams' "Get the Teams mobile app" (Settings and more ▸ Get the mobile
// app; measured on winpc 2026-11-15): 600 wide, padding 24.67, centred;
// the title (16/22 bold) centred with Close (32) at the top right; "Scan
// the code below…" (14/20); Teams' QR code in a 160 px card (radius 32,
// the depth-4 shadow) centred 15 under it; then the App Store and Google
// Play badges (100 x 30, 8 apart) centred 24 under the card, opening
// aka.ms/iosteams and aka.ms/androidteams.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 351.33
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter; y: 29.67
        text: "Get the Teams mobile app"
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }
    Rectangle {
        x: 543.33; y: 24.67; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
        Accessible.onPressAction: root.close()
    }
    Text {
        x: 24.67; y: 77.67; width: 550.67
        text: "Scan the code below with your mobile camera or with a QR reader app."
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }
    FluentSurface {
        x: (root.width - 160) / 2; y: 112.67; width: 160; height: 160
        depth: 4; radius: 32; color: "#FFFFFF"
        Image {
            anchors.fill: parent
            source: "../assets/dialogs/mobile-app-qr.png"
            fillMode: Image.PreserveAspectFit
            smooth: false
            Accessible.role: Accessible.Graphic
            Accessible.name: "QR code to download teams app."
        }
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: 296.67
        spacing: 8
        Repeater {
            model: [{ label: "Download on the Apple App Store", image: "app-store-badge.png", url: "https://aka.ms/iosteams" },
                    { label: "Get it on the Google Play", image: "google-play-badge.png", url: "https://aka.ms/androidteams" }]
            Rectangle {
                required property var modelData
                width: 100; height: 30; radius: 5
                color: "transparent"
                Image { anchors.fill: parent; source: "../assets/dialogs/" + parent.modelData.image; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally(parent.modelData.url) }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.onPressAction: Qt.openUrlExternally(modelData.url)
            }
        }
    }
}
