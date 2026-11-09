import QtQuick
import QtQuick.Controls

// Teams' chat bubble (ufd_chatBubble, measured on winpc, 2026-11-09): one
// at a time, centred 8 px below the stage's top, 320 wide; a #FAFAFA card
// (radius 8, a 0.67 #F0F0F0 border) with the sender's 32 px avatar (12.67
// in) and presence, their name (12/20 #242424) and a guest's unverified
// glyph 4 after it, "Mute these notifications" and Close (20 px glyphs,
// 28 and 56 from the right), and the message (14/20 #616161, two lines at
// most, then "…") at 56.67, 40.67 down. A newer message replaces it; it
// lasts 4 s and fades in 300 ms. Clicking it opens the chat.
Item {
    id: root
    property var bubble: null   // {mri, name, text, guest}
    signal openChat()
    signal muteBubbles()
    width: 320
    height: card.height + 1.33
    visible: opacity > 0
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    function show(b) {
        bubble = b
        opacity = 1
        life.restart()
    }
    function dismiss() { life.stop(); opacity = 0 }
    Timer { id: life; interval: 4000; onTriggered: root.opacity = 0 }

    Rectangle {
        id: card
        x: 0.67; y: 0.67
        width: 318.67
        height: Math.max(68, message.y + message.height + 7.33)
        radius: 8
        color: theme.pick("#FAFAFA", "#292929")
        border.color: theme.pick("#F0F0F0", "#3D3D3D"); border.width: 0.67
        TapHandler { onTapped: { root.dismiss(); root.openChat() } }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Avatar {
            x: 12; y: 12; size: 32
            name: root.bubble ? root.bubble.name : ""
            photoId: root.bubble ? root.bubble.mri : ""
            presence: root.bubble ? (root.bubble.presence || "") : ""
        }
        Row {
            x: 56; y: 12; height: 20
            spacing: 4
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 190)
                elide: Text.ElideRight
                text: root.bubble ? root.bubble.name : ""
                font.family: theme.font; font.pixelSize: 12
                color: theme.text
            }
            FluentIcon {
                visible: !!root.bubble && root.bubble.guest
                anchors.verticalCenter: parent.verticalCenter
                name: "person-unverified-16-filled"; size: 16; color: theme.text
            }
        }
        component BubbleButton: Item {
            id: bb
            property string icon
            property string tip
            signal clicked()
            width: 20; height: 20
            FluentIcon { anchors.centerIn: parent; name: bb.icon; size: 20; color: bbh.hovered ? theme.text : theme.textSecondary }
            HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: bb.clicked() }
            ToolTip.visible: bbh.hovered
            ToolTip.delay: 250
            ToolTip.text: bb.tip
            Accessible.role: Accessible.Button
            Accessible.name: bb.tip
        }
        BubbleButton {
            x: 261.17; y: 12
            icon: "alert-snooze-20"; tip: "Mute these notifications"
            onClicked: { root.dismiss(); root.muteBubbles() }
        }
        BubbleButton {
            x: 288.67; y: 12
            icon: "dismiss-20"; tip: "Close"
            onClicked: root.dismiss()
        }
        Text {
            id: message
            x: 56; y: 40; width: 252.67
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.bubble ? root.bubble.text : ""
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textSecondary
        }
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: bubble ? bubble.name + ": " + bubble.text : ""
}
