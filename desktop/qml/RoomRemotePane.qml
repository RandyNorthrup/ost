import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes

// Teams' Room Remote pane (Control Room System on a Teams Room's ··· menu
// in a meeting; measured on winpc 2026-11-24 with Teams controlling OST
// Test Room): the side panel "Room Remote", a spinner while Teams reaches
// and pairs with the room, then the room's remote in a 319.33-wide area
// 21 in and 20.33 under the header's line (#F5F5F5):
// - "Controlling" 12/16 semibold, the room's name 16/22 semibold, at 16.
// - Video, Mic, Captions: 20 px filled glyphs (Teams' remote draws them
//   from 2..18 of the 20 grid) over 14/20 semibold labels ("Video off",
//   "Mic on", "Captions off" wrapping); a control the room doesn't offer
//   is greyed (#C7C7C7 glyph, #BDBDBD label).
// - Layout: the glyph over "Layout" (brand when hovered); it lists the
//   room's layouts in a popover above it.
// - The volume box: 0.67 #424242 edge, radius 2, 52.67 tall, 16 in:
//   volume down, the speaker, volume up.
// - Disconnect room: 120 x 40, white, 0.67 #D1D1D1 edge, 12/16.
// The column spreads evenly over the panel's height (Teams' Flex
// space="evenly"). Teams' dialogs: Room not detected, Connection failed,
// Error (a command), Retry / Cancel.
Rectangle {
    id: root
    /// backend.roomRemoteJson: {view, error, roomName, caps, state}.
    property var remote: ({})
    signal closed()
    signal command(string name)
    signal retry()
    color: theme.pane

    readonly property string view: remote.view || "loading"
    readonly property var caps: remote.caps || ({})
    readonly property var st: remote.state || ({})
    readonly property var media: caps.mediaControls || []
    readonly property var layouts: caps.stageLayoutControls || []
    readonly property var meetingControls: caps.meetingControls || []
    readonly property bool canMute: media.indexOf("toggleMute") >= 0
    readonly property bool canCamera: media.indexOf("toggleCamera") >= 0
    readonly property bool canCaptions: media.indexOf("toggleCaptions") >= 0
    readonly property bool canVolume: media.indexOf("volume") >= 0
    readonly property bool canLeave: meetingControls.indexOf("leaveMeeting") >= 0
    // The room's mic is "on" when it isn't muted (Teams' MicRenderer).
    readonly property bool micOn: st.toggleMute === false
    readonly property bool videoOn: st.toggleCamera === true
    readonly property bool captionsOn: st.toggleCaptions === true

    readonly property color ink: theme.pick("#242424", "#FFFFFF", "#FFFFFF")
    readonly property color inkSoft: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
    readonly property color offGlyph: theme.pick("#C7C7C7", "#5C5C5C", "#3FF23F")
    readonly property color offText: theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")

    function layoutName(id) {
        switch (id) {
        case "showVideoGallery": case "showMixedGrid": return qsTr("Gallery", "x.roomremote:app_remote_layout_option_gallery")
        case "showPrioritizeVideoView": return qsTr("Prioritize video", "x.roomremote:app_remote_layout_option_prioritize_video_view")
        case "showContent": return qsTr("Content", "x.roomremote:app_remote_layout_option_content")
        case "showVideoGalleryAndContent": return qsTr("Content + gallery", "x.roomremote:app_remote_layout_option_content_and_gallery")
        case "showLargeGallery": return qsTr("Large Gallery", "x.roomremote:app_remote_layout_option_large_gallery")
        case "showTogether": return qsTr("Together mode", "x.roomremote:app_remote_layout_option_together_mode")
        case "showFrontRow": return qsTr("Front row", "x.roomremote:app_remote_layout_option_front_row")
        }
        return ""
    }

    // Header, as the call window's other panes.
    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Room Remote")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.onFill(parent, theme.textStrong) }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // Reaching the room: Fluent's spinner (32), centred in the panel.
    Item {
        visible: root.view === "loading"
        anchors.centerIn: parent
        width: 32; height: 32
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 3; strokeColor: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF"); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5; startAngle: 0; sweepAngle: 360 } }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 3; strokeColor: theme.brand; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5; startAngle: -90; sweepAngle: 100 } }
            RotationAnimator on rotation { from: 0; to: 360; duration: 1500; loops: Animation.Infinite; running: root.visible && root.view === "loading" }
        }
        Accessible.role: Accessible.ProgressBar
        Accessible.name: qsTr("Room Remote")
    }

    // The remote.
    Item {
        id: pad
        visible: root.view === "remote"
        x: 21; y: header.y + header.height + 20.33
        width: parent.width - 41; height: parent.height - y
        // Teams' spacing at its 471.33 tall panel; more height goes evenly
        // to the six gaps (space evenly).
        readonly property real extra: Math.max(0, height - 471.33) / 6
        function at(y, gaps) { return y + extra * gaps }

        Text {
            x: 15.96; y: pad.at(23.56, 1)
            text: qsTr("Controlling", "x.roomremote:app_header_connected_to")
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: root.ink
        }
        Text {
            x: 15.96; y: pad.at(37.7, 1); width: pad.width - 32; elide: Text.ElideRight
            text: root.remote.roomName || ""
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: root.ink
        }
        // Video, Mic, Captions (their columns centred at 40.73, 140.51 and
        // 240.28).
        RemoteControl {
            cx: 40.73; y: pad.at(61.1, 2)
            enabledControl: root.canCamera
            icon: root.canCamera && root.videoOn ? "room-remote-video" : "room-remote-video-off"
            label: root.canCamera && root.videoOn ? qsTr("Video on", "x.roomremote:app_remote_video_on") : qsTr("Video off", "x.roomremote:app_remote_video_off")
            onClicked: root.command(root.videoOn ? "cameraOff" : "cameraOn")
        }
        RemoteControl {
            cx: 140.51; y: pad.at(61.1, 2)
            enabledControl: root.canMute
            icon: root.canMute && root.micOn ? "room-remote-mic" : "room-remote-mic-off"
            label: root.canMute && root.micOn ? qsTr("Mic on", "x.roomremote:app_remote_mic_on") : qsTr("Mic off", "x.roomremote:app_remote_mic_off")
            onClicked: root.command(root.micOn ? "mute" : "unmute")
        }
        RemoteControl {
            cx: 240.28; y: pad.at(61.1, 2)
            enabledControl: root.canCaptions
            labelColor: root.inkSoft
            icon: "room-remote-captions"
            label: root.canCaptions && root.captionsOn ? qsTr("Captions on", "x.roomremote:app_remote_captions_on") : qsTr("Captions off", "x.roomremote:app_remote_captions_off")
            onClicked: root.command(root.captionsOn ? "captionsOff" : "captionsOn")
        }
        RemoteControl {
            id: layoutControl
            cx: pad.width / 2; y: pad.at(209.33, 3)
            enabledControl: root.layouts.length > 0
            hoverBrand: true
            icon: "room-remote-layout"
            label: qsTr("Layout", "x.roomremote:app_remote_layout")
            onClicked: layoutMenu.open()
            Popup {
                id: layoutMenu
                padding: 0
                x: (layoutControl.width - width) / 2; y: -height - 7.33
                background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
                contentItem: Column {
                    Repeater {
                        model: root.layouts
                        Rectangle {
                            id: li
                            required property string modelData
                            width: liText.implicitWidth + 12; height: 32; radius: 4
                            color: liHover.hovered ? theme.menuHover : "transparent"
                            Text {
                                id: liText
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                text: root.layoutName(li.modelData)
                                font.family: theme.font; font.pixelSize: 14
                                color: root.inkSoft
                            }
                            HoverHandler { id: liHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { layoutMenu.close(); root.command(li.modelData) } }
                            Accessible.role: Accessible.MenuItem
                            Accessible.name: liText.text + (li.modelData === root.st.stageLayout ? " " + qsTr("selected", "x.roomremote:app_remote_layout_option_selected") : "")
                        }
                    }
                }
            }
        }
        // The volume box.
        Rectangle {
            id: volume
            x: 15.96; y: pad.at(327.55, 4)
            width: pad.width - 31.92; height: 52.67; radius: 2
            color: "transparent"
            border.width: 0.67; border.color: root.inkSoft
            GlyphButton {
                x: 53.18 - 16; y: 10.67
                icon: "room-remote-volume-down"; label: qsTr("volume down", "x.roomremote:app_remote_volume_down"); enabledControl: root.canVolume
                onClicked: root.command("volumeDown")
            }
            FluentIcon {
                anchors.centerIn: parent
                name: "room-remote-speaker"; size: 20
                color: root.canVolume ? root.ink : root.offGlyph
            }
            GlyphButton {
                x: volume.width - 53.18 - 16; y: 10.67
                icon: "room-remote-volume-up"; label: qsTr("volume up", "x.roomremote:app_remote_volume_up"); enabledControl: root.canVolume
                onClicked: root.command("volumeUp")
            }
        }
        Rectangle {
            x: (pad.width - width) / 2; y: pad.at(420.77, 5)
            width: 120; height: 40; radius: 4
            color: leaveHover.hovered && root.canLeave ? theme.menuHover : theme.surface
            border.width: 0.67; border.color: theme.stroke
            Text {
                anchors.centerIn: parent
                text: qsTr("Disconnect room", "x.roomremote:app_remote_end_call")
                font.family: theme.font; font.pixelSize: 12
                color: root.canLeave ? root.ink : root.offText
            }
            HoverHandler { id: leaveHover; cursorShape: root.canLeave ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: root.canLeave; onTapped: root.command("leaveMeeting") }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Disconnect room", "x.roomremote:app_remote_end_call")
        }
    }

    // A control: its 32 x 31.33 glyph button over its label (Teams' 96
    // wide label button, 46.33 below the glyph's top; long labels wrap).
    component RemoteControl: Item {
        id: rc
        property real cx: 0
        property string icon
        property string label
        property bool enabledControl: true
        property bool hoverBrand: false
        property color labelColor: root.ink
        signal clicked()
        x: cx - 48; width: 96; height: 46.33 + labelText.height + 5.67
        readonly property bool hot: rcGlyphHover.hovered || rcLabelHover.hovered
        FluentIcon {
            x: 38; y: 5.67; name: rc.icon; size: 20
            color: rc.enabledControl ? root.ink : root.offGlyph
            HoverHandler { id: rcGlyphHover; cursorShape: rc.enabledControl ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: rc.enabledControl; onTapped: rc.clicked() }
        }
        Text {
            id: labelText
            x: 10; y: 46.33 + 5.67; width: 76
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: rc.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: !rc.enabledControl ? root.offText : rc.hoverBrand && rc.hot ? theme.brand : rc.labelColor
            HoverHandler { id: rcLabelHover; cursorShape: rc.enabledControl ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: rc.enabledControl; onTapped: rc.clicked() }
        }
        Accessible.role: Accessible.Button
        Accessible.name: rc.label
    }

    component GlyphButton: Rectangle {
        id: gb
        property string icon
        property string label
        property bool enabledControl: true
        signal clicked()
        width: 32; height: 31.33; radius: 4
        color: "transparent"
        FluentIcon { anchors.centerIn: parent; name: gb.icon; size: 20; color: gb.enabledControl ? root.ink : root.offGlyph }
        HoverHandler { cursorShape: gb.enabledControl ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: gb.enabledControl; onTapped: gb.clicked() }
        ToolTip.visible: false
        Accessible.role: Accessible.Button
        Accessible.name: gb.label
    }

    // Teams' room remote dialogs (RoomRemoteDialog): Retry / Cancel.
    ConfirmDialog {
        id: errorDialog
        readonly property int code: root.remote.error === undefined ? -1 : root.remote.error
        title: code === 0 ? qsTr("Room not detected") : code === 1 ? qsTr("Connection failed") : code === 2 ? qsTr("Disconnected") : qsTr("Error")
        body: code === 0 ? qsTr("We couldn't detect any nearby rooms.")
            : code === 1 ? qsTr("We were unable to establish a connection with the room.")
            : code === 2 ? qsTr("The room has left the meeting.")
            : code === 3 ? qsTr("Unable to perform action.")
            : qsTr("Something went wrong. Please try again.")
        confirmText: code === 2 ? qsTr("Ok") : qsTr("Retry")
        // Retry starts over (Teams' errorDialogConfirmHandler); Cancel
        // closes the panel.
        onConfirmed: code === 2 ? root.closed() : root.retry()
        onCancelled: root.closed()
    }
    readonly property bool showError: visible && root.view === "error"
    onShowErrorChanged: if (showError) errorDialog.open(); else errorDialog.close()
    // The room left (Disconnect room) or ended the pairing: Teams closes
    // the panel.
    readonly property bool gone: visible && root.view === "left"
    onGoneChanged: if (gone) root.closed()
}
