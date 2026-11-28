import QtQuick
import QtQuick.Controls

// Teams' network strength popover (local-nsi, opened on hover over your
// name tag's bars; calling bundle 119108 Ke/vt, Teams 26304): the heading
// ("Connection is weak / unstable / good"), the tip for your situation,
// the action Teams offers ("Turn off all video" when it's weak and video
// is flowing, "All video off" (disabled) once it is, "Turn on all video"
// when it's good again) and, when sampled, "Was this accurate?" with a
// thumbs up and down. Measured on winpc 2026-11-27 (MSTeams 26304, a test
// meeting): the Fluent PopoverSurface with Teams' toolTip class, 173 wide
// (border-box: 0.67 transparent border, padding 10 10 6), the shadow 16,
// radius 4, opening right above the bars at their left edge (below them
// within 220 px of the top); the heading 12/16 bold, the tip 12/16; the
// action 10 below (an outline button, 12/16); the prompt 10 below
// (10/14 #707070) with the two 32 x 25.33 transparent buttons (20 px
// thumbs 6 in) at the right.
// Teams sends the answer to Microsoft (NsiUserFeedback); OST sends nothing:
// "This was not accurate" opens Report a problem with what the popover
// showed and the call's media, as the call quality survey's "Had issues"
// does; either answer hides the prompt until the popover opens again.
Popup {
    id: root
    property var call
    property Item anchorItem
    signal left()
    /// "This was not accurate": the Report a problem text and details.
    signal feedbackReport(string text, string details)
    readonly property bool hovered: hover.hovered
    parent: Overlay.overlay
    topPadding: 10.67; leftPadding: 10.67; rightPadding: 10.67; bottomPadding: 6.67
    width: 173
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface; HoverHandler { id: hover; onHoveredChanged: if (!hovered) root.left() } }
    // Teams' prompt is the popover's own state: answered, it goes until the
    // popover opens again (its surface mounts afresh).
    property bool answered: false
    onAboutToShow: {
        answered = false
        if (!anchorItem) return
        const p = anchorItem.mapToItem(Overlay.overlay, 0, 0)
        x = Math.max(4, Math.min(p.x, Overlay.overlay.width - width - 4))
        // Teams: below-start when the pointer is within 220 px of the top.
        y = p.y < 220 ? p.y + anchorItem.height : p.y - implicitHeight
    }
    readonly property bool bad: call && call.networkStrength === "Bad"
    readonly property bool good: !call || call.networkStrength === "Good" || call.networkStrength === ""
    readonly property bool videoFlowing: call && (call.cameraOn || !call.incomingVideoOff)
    readonly property bool videoOffByUs: call && (call.nsiVideoOff || call.incomingVideoOff)
    readonly property bool prompt: !!call && call.nsiFeedback && !answered

    function answer(accurate) {
        answered = true
        if (accurate || !call) return
        const c = call
        const state = { networkStrength: c.networkStrength, isVideoOn: !!c.cameraOn, isIncomingVideoOn: !c.incomingVideoOff, wired: !!c.wired, participantsCount: (c.roster || []).length }
        close()
        root.feedbackReport("The network indicator wasn't accurate: " + c.networkHeading, backend.nsiFeedbackDetails(JSON.stringify(state)))
    }
    function answerForTest(accurate) { answer(accurate) }

    contentItem: Column {
        spacing: 0
        Text {
            id: heading
            width: root.availableWidth
            text: root.call ? root.call.networkHeading : ""
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            visible: !root.good || root.videoOffByUs
            width: root.availableWidth
            text: root.call ? root.call.networkTip : ""
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Item {
            readonly property string label: root.bad && root.videoFlowing ? qsTr("Turn off all video")
                : root.bad && root.call && root.call.nsiVideoOff ? qsTr("All video off")
                : root.good && root.videoOffByUs ? qsTr("Turn on all video") : ""
            id: actionRow
            visible: label.length > 0
            width: root.availableWidth; height: 10 + 32
            Rectangle {
                id: hcFill1
                y: 10
                readonly property bool usable: actionRow.label !== qsTr("All video off")
                width: Math.max(96, actionText.implicitWidth + 20 + 6 + 24); height: 32; radius: 4
                color: usable && ah.hovered ? theme.menuHover : theme.surface
                border.color: theme.stroke; border.width: 1
                opacity: usable ? 1 : 0.45
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: actionRow.label === qsTr("Turn on all video") ? "video-20" : "video-off"; size: 20; color: theme.onFill(hcFill1, theme.text) }
                    Text { id: actionText; anchors.verticalCenter: parent.verticalCenter; text: actionRow.label; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(hcFill1, theme.text) }
                }
                HoverHandler { id: ah; cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    enabled: parent.usable
                    onTapped: {
                        const c = root.call
                        if (actionRow.label === qsTr("Turn off all video")) {
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
        // "Was this accurate?" (calling user_feedback_network_strength).
        Item {
            id: promptRow
            visible: root.prompt
            width: root.availableWidth; height: 10 + 25.33
            Text {
                y: 10; height: 25.33; verticalAlignment: Text.AlignVCenter
                width: parent.width - thumbs.width
                text: qsTr("Was this accurate?", "calling:kb4c90hxq")
                wrapMode: Text.Wrap
                font.family: theme.font; font.pixelSize: 10; lineHeight: 14; lineHeightMode: Text.FixedHeight
                color: theme.pick("#707070", "#ADADAD", "#FFFFFF")
            }
            Row {
                id: thumbs
                anchors.right: parent.right; y: 10
                Repeater {
                    model: [
                        { icon: "thumb-like-20", name: qsTr("This was accurate", "calling:ka0niju4k"), accurate: true },
                        { icon: "thumb-dislike-20", name: qsTr("This was not accurate", "calling:kbx9316mo"), accurate: false }
                    ]
                    Item {
                        id: thumb
                        required property var modelData
                        width: 32; height: 25.33
                        FluentIcon {
                            x: 6; y: 0.67
                            name: thumbHover.hovered ? thumb.modelData.icon + "-filled" : thumb.modelData.icon
                            size: 20
                            color: thumbHover.hovered ? theme.brand : theme.textStrong
                        }
                        HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.answer(thumb.modelData.accurate) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name
                        Accessible.onPressAction: root.answer(thumb.modelData.accurate)
                    }
                }
            }
        }
    }
}
