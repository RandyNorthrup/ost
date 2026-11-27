import QtQuick
import QtQuick.Controls.Basic

// View Copilot history (a post view's More, Teams' viewSummaryHistory: its
// own Copilot's history for the post, isHistoryOnly), measured on winpc
// 2026-11-24 (TASK-0265, "OST TEST 265 plain post" in its window): in the
// Copilot pane's place (360 beside the post, or over a narrow window).
// - The header (channel-copilot-header-renderer): 48 tall, padding 0 20, a
//   0.67 #E0E0E0 line under it: the colour Copilot mark (20) 13.7 down,
//   "Copilot history" (14/600) at 45, 3.7 down, over "Learn what's in
//   Copilot history" (a 14 px brand link, 23.7 down; Teams'
//   copilotHistoryLearnMoreUrl), and Close (32 x 31.3, 52 from the right,
//   8 down).
// - With nothing kept (Teams asked for nothing for this account: no
//   history yet), centred in the rest: Teams' picture (192, 23 under its
//   box's top), "No history yet." (16/20 bold, 20 under it) and "This is
//   where you'll find your old Copilot requests and summaries for this
//   conversation." (14/20, 7 under it, centred).
Rectangle {
    id: root
    signal closed()
    color: theme.surface
    Rectangle { width: 0.67; height: parent.height; color: theme.divider }
    readonly property string learnMoreUrl: "https://support.microsoft.com/en-us/office/use-copilot-in-microsoft-teams-chat-and-channels-cccccca2-9dc8-49a9-ab76-b1a8ee21486c"
    Item {
        id: header
        x: 0.67; width: parent.width - 0.67; height: 48
        Image {
            x: 20; y: 13.7; width: 20; height: 20
            source: "../assets/icons/copilot-color-48.svg"
            sourceSize: Qt.size(40, 40)
        }
        Text {
            x: 45; y: 3.7
            width: closeButton.x - x - 8; elide: Text.ElideRight
            text: qsTr("Copilot history")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
        }
        Text {
            id: learn
            x: 45; y: 23.7
            width: Math.min(implicitWidth, closeButton.x - x - 8); elide: Text.ElideRight
            text: qsTr("Learn what’s in Copilot history")
            font.family: theme.font; font.pixelSize: 14; font.underline: true
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: learnHover.hovered ? theme.brandHover : theme.brandForeground1
            HoverHandler { id: learnHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.openExternal(root.learnMoreUrl) }
            Accessible.role: Accessible.Link
            Accessible.name: text
        }
        Rectangle {
            id: closeButton
            x: parent.width - 52; y: 8; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeButton, closeHover.hovered ? theme.brand : theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    Item {
        id: body
        x: 20.67; y: 48; width: parent.width - 20.67 - 20; height: parent.height - 48
        Column {
            id: empty
            width: parent.width
            y: Math.max(0, (parent.height - height) / 2)
            Item {
                width: parent.width; height: 215
                Image {
                    x: (parent.width - 192) / 2; y: 23; width: 192; height: 192
                    source: "../assets/illustrations/copilot-history-empty.svg"
                    sourceSize: Qt.size(384, 384)
                    fillMode: Image.PreserveAspectFit
                }
            }
            Text {
                width: parent.width; topPadding: 20; height: 40
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No history yet.")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                width: parent.width; topPadding: 7
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("This is where you'll find your old Copilot requests and summaries for this conversation.")
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
        }
    }
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Copilot history")
}
