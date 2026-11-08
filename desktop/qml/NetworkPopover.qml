import QtQuick
import QtQuick.Controls

// Teams' network strength popover (local-nsi, opened on hover over your
// name tag's bars): the heading ("Connection is weak / unstable / good"),
// the tip for your situation, and the action Teams offers — "Turn off all
// video" when it's weak and video is flowing, "All video off" (disabled)
// once it is, "Turn on all video" when it's good again. Fluent Popover:
// padding 16, radius 4, shadow 16, opening above the bars (below when they
// are near the top of the window).
Popup {
    id: root
    property var call
    property Item anchorItem
    signal left()
    readonly property bool hovered: hover.hovered
    parent: Overlay.overlay
    padding: 16
    width: Math.min(288, Math.max(heading.implicitWidth, actionRow.implicitWidth, 200) + 32)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface; HoverHandler { id: hover; onHoveredChanged: if (!hovered) root.left() } }
    onAboutToShow: {
        if (!anchorItem) return
        const p = anchorItem.mapToItem(Overlay.overlay, 0, 0)
        x = Math.max(4, Math.min(p.x, Overlay.overlay.width - width - 4))
        // Teams: below-start when the pointer is within 220 px of the top.
        y = p.y < 220 ? p.y + anchorItem.height + 4 : p.y - implicitHeight - 4
    }
    readonly property bool bad: call && call.networkStrength === "Bad"
    readonly property bool good: !call || call.networkStrength === "Good" || call.networkStrength === ""
    readonly property bool videoFlowing: call && (call.cameraOn || !call.incomingVideoOff)
    readonly property bool videoOffByUs: call && (call.nsiVideoOff || call.incomingVideoOff)

    contentItem: Column {
        spacing: 8
        Text {
            id: heading
            width: root.width - 32
            text: root.call ? root.call.networkHeading : ""
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
        }
        Text {
            visible: !root.good || root.videoOffByUs
            width: root.width - 32
            text: root.call ? root.call.networkTip : ""
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        Row {
            id: actionRow
            readonly property string label: root.bad && root.videoFlowing ? "Turn off all video"
                : root.bad && root.call && root.call.nsiVideoOff ? "All video off"
                : root.good && root.videoOffByUs ? "Turn on all video" : ""
            visible: label.length > 0
            Rectangle {
                readonly property bool usable: actionRow.label !== "All video off"
                width: actionText.implicitWidth + 20 + 8 + 24; height: 32; radius: 4
                color: usable && ah.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 1
                opacity: usable ? 1 : 0.45
                Row {
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: actionRow.label === "Turn on all video" ? "video-20" : "video-off"; size: 20; color: theme.text }
                    Text { id: actionText; anchors.verticalCenter: parent.verticalCenter; text: actionRow.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                }
                HoverHandler { id: ah; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    enabled: parent.usable
                    onTapped: {
                        const c = root.call
                        if (actionRow.label === "Turn off all video") {
                            if (c.cameraOn) c.toggleCamera()
                            c.incomingVideoOff = true
                            c.nsiVideoOff = true
                        } else {
                            c.incomingVideoOff = false
                            c.nsiVideoOff = false
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: actionRow.label
            }
        }
    }
}
