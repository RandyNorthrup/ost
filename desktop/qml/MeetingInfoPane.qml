import QtQuick
import QtQuick.Controls

// Teams' Meeting info pane (calling-right-side-panel with the meeting info
// panel, measured in Teams on winpc, 2026-11-08): #F5F5F5, the rail
// header "Meeting info" (16/22 bold, 20.67 in) with its close button, then
// 20.67 in and 305.33 wide:
// - the meeting's title (call-title, 20/28) 10 above the lines below,
// - "3:00 PM - 3:30 PM (30 minutes)" (meeting-hours), the schedule line
//   (recurrence) and the location, 14/20,
// - 30 below: the link glyph and "Copy join info" (a 240 x 31.33 button,
//   14/20 semibold, #D1D1D1 hairline), "Copied to clipboard" for 2 s,
// - 30 below: the calendar event's body (meeting-body), links in brand.
// The whole pane below the header scrolls.
Rectangle {
    id: root
    /// {title, hours, schedule, location, body, canCopy}, or null while
    /// loading.
    property var info: null
    signal closed()
    signal copyJoinInfo()
    color: theme.pane

    property bool copied: false
    Timer { id: copiedTimer; interval: 2000; onTriggered: root.copied = false }

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Meeting info"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Hide meeting info pane"
            Accessible.role: Accessible.Button
            Accessible.name: "Hide meeting info pane"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; topMargin: 16; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: col.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            x: 20.67; width: 305.33
            Text {
                visible: !!root.info && root.info.title.length > 0
                width: parent.width
                text: root.info ? root.info.title : ""
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 20
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Item { visible: !!root.info && root.info.title.length > 0; width: 1; height: 10 }
            Repeater {
                model: root.info ? [root.info.hours, root.info.schedule, root.info.location].filter(t => t.length > 0) : []
                Text {
                    required property string modelData
                    width: col.width
                    text: modelData
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: 14
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: theme.text
                }
            }
            Item { visible: !!root.info && root.info.canCopy; width: 1; height: 30 }
            Row {
                visible: !!root.info && root.info.canCopy
                spacing: 10
                height: 31.33
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "link-20"; size: 20; color: theme.text }
                Rectangle {
                    width: 240; height: 31.33; radius: 4
                    color: copyHover.hovered ? theme.menuHover : theme.surface
                    border.color: copyHover.hovered ? theme.strokeHover : theme.stroke
                    border.width: 0.67
                    Text {
                        anchors.centerIn: parent
                        text: root.copied ? "Copied to clipboard" : "Copy join info"
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.copyJoinInfo()
                            root.copied = true
                            copiedTimer.restart()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.copied ? "Copied to clipboard" : "Copy join info"
                }
            }
            Item { visible: !!root.info && root.info.body.length > 0; width: 1; height: 30 }
            Text {
                visible: !!root.info && root.info.body.length > 0
                width: parent.width
                textFormat: Text.RichText
                // Teams: 14.67 px text on 20.95 px lines, links in brand
                // without underline.
                text: root.info ? "<html><head><style>a { color: " + theme.brandLink + "; text-decoration: none; }</style></head><body>" + root.info.body + "</body></html>" : ""
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 15
                lineHeight: 20.95; lineHeightMode: Text.FixedHeight
                color: theme.text
                linkColor: theme.brandLink
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }
    }
    // Teams' spinner while the meeting's details load.
    BusyIndicator { anchors.centerIn: parent; running: !root.info; visible: !root.info }
}
