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
            text: qsTr("Meeting info")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: hcFill1
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(hcFill1, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: qsTr("Hide meeting info pane")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Hide meeting info pane")
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
            // Teams' dial-in block (measured in Teams on the web,
            // 2026-11-16): 30 below the lines above, the 20 px dial pad
            // glyph, then 30 in: "Dial in manually", the toll number as a
            // tel: link with " (Toll)", the toll-free one, "Get local
            // numbers" and "Conference ID: 975 755 048 #", 14/20.
            Item { visible: dialBlock.visible; width: 1; height: 30 }
            Item {
                id: dialBlock
                readonly property var dial: root.info ? root.info.dial : null
                visible: !!dial
                width: parent.width; height: dialCol.implicitHeight
                FluentIcon { x: 0; y: 2; name: "dialpad-20"; size: 20; color: theme.text }
                Column {
                    id: dialCol
                    x: 30; width: parent.width - 30
                    Text {
                        text: qsTr("Dial in manually")
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    DialLink { visible: !!dialBlock.dial; number: dialBlock.dial ? dialBlock.dial.toll : ""; kind: qsTr(" (Toll)"); aria: dialBlock.dial ? dialBlock.dial.tollAria : "" }
                    DialLink { visible: !!dialBlock.dial && dialBlock.dial.tollFree.length > 0; number: dialBlock.dial ? dialBlock.dial.tollFree : ""; kind: qsTr(" (Toll-Free)"); aria: dialBlock.dial ? dialBlock.dial.tollFreeAria : "" }
                    Text {
                        visible: !!dialBlock.dial && dialBlock.dial.localNumbersUrl.length > 0
                        text: qsTr("Get local numbers")
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.underline: localHover.hovered
                        color: theme.brandLink
                        HoverHandler { id: localHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally(dialBlock.dial.localNumbersUrl) }
                        Accessible.role: Accessible.Link
                        Accessible.name: text
                    }
                    Text {
                        text: dialBlock.dial ? dialBlock.dial.conferenceText : ""
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                }
            }
            Item { visible: !!root.info && root.info.canCopy; width: 1; height: 30 }
            Row {
                visible: !!root.info && root.info.canCopy
                spacing: 10
                height: 31.33
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "link-20"; size: 20; color: theme.text }
                Rectangle {
                    id: hcFill2
                    width: 240; height: 31.33; radius: 4
                    color: copyHover.hovered ? theme.menuHover : theme.surface
                    border.color: copyHover.hovered ? theme.strokeHover : theme.stroke
                    border.width: 0.67
                    Text {
                        anchors.centerIn: parent
                        text: root.copied ? qsTr("Copied to clipboard") : qsTr("Copy join info")
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.onFill(hcFill2, theme.text)
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
                    Accessible.name: root.copied ? qsTr("Copied to clipboard") : qsTr("Copy join info")
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
    // A dial-in number: the number as a tel: link (brand, underlined) and
    // its kind ("(Toll)") in the text colour.
    component DialLink: Row {
        property string number
        property string kind
        property string aria
        Text {
            text: parent.number
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            // Fluent's Link: the underline shows on hover.
            font.underline: numberHover.hovered
            color: theme.brandLink
            HoverHandler { id: numberHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Qt.openUrlExternally("tel:" + parent.parent.number) }
            Accessible.role: Accessible.Link
            Accessible.name: parent.aria
        }
        Text {
            text: parent.kind
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.textStrong
        }
    }
    // Teams' spinner while the meeting's details load.
    BusyIndicator { anchors.centerIn: parent; running: !root.info; visible: !root.info }
}
