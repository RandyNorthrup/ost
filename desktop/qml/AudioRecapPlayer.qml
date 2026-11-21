import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtMultimedia

// Teams' Audio recap mini player (its podcast mini player popped out from
// the recap window's Audio recap; measured on winpc 2026-11-21, Teams
// 26304, "OST TEST 240 recap meeting"): a frameless 399 wide window on
// #F5F5F5 with a white card (radius 8, Teams' faint purple wash):
// - the head (8, 12, 383.3 x 28): the app's 16 px mark at 16, 18, the
//   title 12/600 at 40 ("Generating..." in #616161 while it's made, then
//   "Audio recap" in #242424), View generated audio recaps (list) and
//   Close mini player (24 x 28 each, 16 px icons, #424242) at 341.3 and
//   367.3;
// - while it's made or playing (152 tall): the progress line (16, 52,
//   367.3 x 4, #E6E6E6, Teams' moving blue-to-violet gradient while
//   generating), the controls centred (Playback speed 24 x 23.3, Skip
//   back 10 seconds 32 x 31.3, Pause/Play 40, Skip forward 10 seconds,
//   More options 24 x 28; dimmed #BDBDBD while generating), and "AI-
//   generated content may be incorrect" (10, #616161) with Like and
//   Dislike (24 x 23.3) at the bottom;
// - when it couldn't be made (106 tall): the error banner (8, 48, 383.3 x
//   51.3, #FDF6F6): a 20 px warning (#BC2F32), "Couldn't generate the
//   audio recap" (12/600) and the reason (12, #424242).
Window {
    id: win
    property string subject: ""
    /// "generating", "playing" or "error".
    property string state_: "generating"
    property string errorText: ""
    property var podcast: null
    property bool liked: false
    property bool disliked: false
    signal closing()
    title: qsTr("Audio recap")
    flags: Qt.Tool | Qt.FramelessWindowHint
    width: 399
    height: state_ === "error" ? 106 : 152
    color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
    onVisibleChanged: if (!visible) { player.stop(); win.closing() }

    /// The answer of the recap window's recapAudio request.
    function result(v) {
        if (v.error || v.status === "FAILED") {
            errorText = v.noInsight ? qsTr("None of the selected meetings have enough information.") : qsTr("Something went wrong. Try again later.")
            state_ = "error"
            return
        }
        podcast = v.podcast || null
        const file = podcast && podcast.fullAudioFile ? podcast.fullAudioFile.fileUrl : ""
        if (v.status === "COMPLETED" && file) {
            state_ = "playing"
            backend.eventsRequest("driveStreamUrl", "audiorecap:" + file, JSON.stringify({ url: file }))
        } else {
            errorText = qsTr("Something went wrong. Try again later.")
            state_ = "error"
        }
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id.indexOf("audiorecap:") !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            if (v.url) { player.source = v.url; player.play() }
            else { win.errorText = qsTr("Couldn’t play. Try again."); win.state_ = "error" }
        }
    }
    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: theme.surface
        border.color: theme.highContrast ? "#FFFFFF" : "transparent"; border.width: theme.highContrast ? 1 : 0
        // Teams' wash: 194.53° from rgba(140,91,210,.04) to rgba(79,82,178,.04).
        gradient: theme.dark || theme.highContrast ? null : wash
        Gradient {
            id: wash
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Qt.rgba(1 - 0.04 * (1 - 140 / 255), 1 - 0.04 * (1 - 91 / 255), 1 - 0.04 * (1 - 210 / 255), 1) }
            GradientStop { position: 1; color: Qt.rgba(1 - 0.04 * (1 - 79 / 255), 1 - 0.04 * (1 - 82 / 255), 1 - 0.04 * (1 - 178 / 255), 1) }
        }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

        Image { x: 16; y: 18; width: 16; height: 16; source: "../assets/logo.svg"; sourceSize: Qt.size(32, 32) }
        Text {
            x: 40; y: 18; width: 289.3; elide: Text.ElideRight
            text: win.state_ === "generating" ? qsTr("Generating...") : qsTr("Audio recap")
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: win.state_ === "generating" ? theme.textSecondary : theme.text
        }
        SmallBtn { x: 341.3; y: 12; icon: "list-16"; tip: qsTr("View generated audio recaps"); onClicked: if (typeof window !== "undefined") window.openAudioRecaps() }
        SmallBtn { x: 367.3; y: 12; icon: "dismiss-16"; tip: qsTr("Close mini player"); onClicked: win.close() }

        // Couldn't make it.
        Rectangle {
            visible: win.state_ === "error"
            x: 8; y: 48; width: 383.3; height: 51.3; radius: 4
            color: theme.pick("#FDF6F6", "#3F1011", "#000000")
            border.color: theme.pick("#F4BFC0", "#6E0811", "#FFFFFF"); border.width: 1
            FluentIcon { x: 12.7; y: 8.7; name: "warning-20-filled"; size: 20; color: theme.pick("#BC2F32", "#DC626D", "#FFFFFF") }
            Text { x: 40.7; y: 8.7; width: 330; elide: Text.ElideRight; text: qsTr("Couldn't generate the audio recap"); lineHeight: 16; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 40.7; y: 26.7; width: 330; wrapMode: Text.Wrap; text: win.errorText; lineHeight: 16; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        }

        // Making or playing it.
        Item {
            visible: win.state_ !== "error"
            anchors.fill: parent
            Rectangle {
                id: track
                x: 16; y: 52; width: 367.3; height: 4; radius: 4; clip: true
                color: theme.pick("#E6E6E6", "#3D3D3D", "#FFFFFF")
                // Generating: Teams' sweeping gradient.
                Rectangle {
                    visible: win.state_ === "generating"
                    height: 4; width: parent.width; radius: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: theme.pick("#E6E6E6", "#3D3D3D", "#FFFFFF") }
                        GradientStop { position: 0.35; color: "#185ABD" }
                        GradientStop { position: 0.7; color: "#47CFFA" }
                        GradientStop { position: 0.92; color: "#B47CF8" }
                        GradientStop { position: 1; color: theme.pick("#E6E6E6", "#3D3D3D", "#FFFFFF") }
                    }
                    NumberAnimation on x { running: win.state_ === "generating" && win.visible; from: -track.width; to: track.width; duration: 2000; loops: Animation.Infinite }
                }
                // Playing: how far along.
                Rectangle {
                    visible: win.state_ === "playing"
                    height: 4; radius: 4; color: theme.brand
                    width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                }
            }
            Item {
                id: controls
                x: 103.7; y: 70.3; width: 192; height: 40
                readonly property bool live: win.state_ === "playing"
                readonly property color dim: theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F")
                // Playback speed (1x, 1.25x, 1.5x, 2x, 0.75x, then 1x).
                Rectangle {
                    x: 0; y: 8.4; width: 24; height: 23.3; radius: 4
                    color: spH.hovered && controls.live ? theme.rowHover : "transparent"
                    Text { anchors.centerIn: parent; text: qsTr("%1x").arg(player.playbackRate); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: controls.live ? theme.textStrong : controls.dim }
                    HoverHandler { id: spH; cursorShape: controls.live ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: controls.live; onTapped: { const r = [1, 1.25, 1.5, 2, 0.75]; player.playbackRate = r[(r.indexOf(player.playbackRate) + 1) % r.length] } }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Playback speed")
                }
                CtrlBtn { x: 34; y: 4.4; icon: "skip-back-10-20"; tip: qsTr("Skip back 10 seconds"); onClicked: player.position = Math.max(0, player.position - 10000) }
                Rectangle {
                    x: 76; y: 0; width: 40; height: 40; radius: 20
                    color: controls.live ? theme.brand : controls.dim
                    FluentIcon { anchors.centerIn: parent; name: player.playbackState === MediaPlayer.PlayingState || win.state_ === "generating" ? "pause-20-filled" : "play-20-filled"; size: 20; color: theme.textOnBrand }
                    HoverHandler { cursorShape: controls.live ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: controls.live; onTapped: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                    Accessible.role: Accessible.Button
                    Accessible.name: player.playbackState === MediaPlayer.PlayingState || win.state_ === "generating" ? qsTr("Pause") : qsTr("Play")
                }
                CtrlBtn { x: 126; y: 4.4; icon: "skip-forward-10-20"; tip: qsTr("Skip forward 10 seconds"); onClicked: player.position = Math.min(player.duration, player.position + 10000) }
                SmallBtn { x: 168; y: 6; icon: "more-horizontal-20"; iconSize: 20; tip: qsTr("More options") }
            }
            Text { x: 16; y: 125.3; text: qsTr("AI-generated content may be incorrect"); lineHeight: 14; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary }
            SmallBtn { x: 333.3; y: 120.7; height: 23.3; icon: win.liked ? "thumb-like-16-filled" : "thumb-like-20"; iconSize: 20; tip: qsTr("Like"); onClicked: { win.liked = !win.liked; if (win.liked) win.disliked = false } }
            SmallBtn { x: 359.3; y: 120.7; height: 23.3; icon: win.disliked ? "thumb-dislike-16-filled" : "thumb-dislike-20"; iconSize: 20; tip: qsTr("Dislike"); onClicked: { win.disliked = !win.disliked; if (win.disliked) win.liked = false } }
        }
    }

    component SmallBtn: Rectangle {
        id: sb
        property string icon
        property string tip
        property int iconSize: 16
        signal clicked()
        width: 24; height: 28; radius: 4
        color: sbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: sb.icon; size: sb.iconSize; color: theme.textStrong }
        HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sb.clicked() }
        ToolTip.visible: sbh.hovered && !!tip; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
    component CtrlBtn: Rectangle {
        id: cb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: cbh.hovered && controls.live ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: cb.icon; size: 20; color: controls.live ? theme.textStrong : controls.dim }
        HoverHandler { id: cbh; cursorShape: controls.live ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: controls.live; onTapped: cb.clicked() }
        ToolTip.visible: cbh.hovered && !!tip; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: tip
    }

    function stateForTest() { return JSON.stringify({ state: win.state_, error: win.errorText, height: win.height, title: win.state_ === "generating" ? "Generating..." : "Audio recap", source: String(player.source).length > 0 }) }
}
