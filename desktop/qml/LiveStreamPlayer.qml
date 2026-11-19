import QtQuick
import QtQuick.Controls.Basic as QC
import QtMultimedia

// A town hall's stream for its attendees (calling::live_stream): Teams
// plays the composition service's HLS stream in its web player; OST plays
// the same stream natively with Qt Multimedia, from OST's loopback server.
Item {
    id: root
    /// OST's loopback address for the stream ("" until it's offered).
    property string source: ""
    /// Play it (the event is live).
    property bool active: false
    property bool muted: false
    property real volume: 1.0
    /// Playing (frames on screen).
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState && player.hasVideo
    readonly property string error: player.errorString
    /// Buffering or loading.
    readonly property bool waiting: active && source !== "" && !playing

    MediaPlayer {
        id: player
        source: root.active ? root.source : ""
        audioOutput: AudioOutput { muted: root.muted; volume: root.volume }
        videoOutput: video
        onSourceChanged: if (source.toString() !== "") play()
        onErrorOccurred: (e, s) => {
            console.log("LIVESTREAM error", e, s)
            retry.restart()
        }
        onMediaStatusChanged: {
            console.log("LIVESTREAM status", mediaStatus)
            // A live stream that ends or stalls: start again from the live edge.
            if (mediaStatus === MediaPlayer.EndOfMedia && root.active) retry.restart()
        }
    }
    // Teams' player retries a failed or ended stream while the event is live.
    Timer { id: retry; interval: 3000; onTriggered: if (root.active && root.source !== "") { player.stop(); player.play() } }

    Rectangle { anchors.fill: parent; color: "black" }
    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
    QC.BusyIndicator {
        anchors.centerIn: parent
        running: root.waiting
        visible: running
    }
    component Ctl: Rectangle {
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 24; radius: 4
        color: ctlHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
        FluentIcon { anchors.centerIn: parent; name: parent.icon; size: 20; color: "white" }
        HoverHandler { id: ctlHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
    /// Full screen asked (Alt+Enter, the button).
    signal fullScreenRequested()
    // The player's controls, as Teams' Hydra player draws them (measured
    // 2026-11-18 in a 1280 x 588 stage): the progress bar 8 in, 20 tall,
    // 43.3 above the bottom; Pause (Alt+K), Skip back 10 s, Skip forward
    // 10 s (Alt+L), Mute (Alt+M), the position (14 px white) and Full
    // screen (Alt+Enter) on the right, 32 x 24, 15.7 above the bottom.
    // They show while the pointer is over the player.
    HoverHandler { id: playerHover }
    Item {
        id: controls
        anchors.fill: parent
        visible: root.active && root.source !== "" && (playerHover.hovered || player.playbackState !== MediaPlayer.PlayingState)
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 72
            gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) } }
        }
        QC.Slider {
            id: progress
            x: 8; width: parent.width - 16; height: 20
            y: parent.height - 43.3 - height
            from: 0; to: Math.max(1, player.duration)
            value: player.position
            enabled: player.seekable
            onMoved: player.position = value
            Accessible.name: qsTr("Progress bar")
        }
        Row {
            x: 8; y: parent.height - 15.7 - 24
            Ctl { icon: player.playbackState === MediaPlayer.PlayingState ? "pause-20-filled" : "play-20-filled"
                  tip: player.playbackState === MediaPlayer.PlayingState ? qsTr("Pause (Alt+K)") : qsTr("Play (Alt+K)")
                  onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
            Ctl { icon: "skip-back-10-20"; tip: qsTr("Skip backward 10 seconds"); onClicked: if (player.seekable) player.position = Math.max(0, player.position - 10000) }
            Ctl { icon: "skip-forward-10-20"; tip: qsTr("Skip forward 10 seconds (Alt+L)"); onClicked: if (player.seekable) player.position = Math.min(player.duration, player.position + 10000) }
            Ctl { icon: root.muted ? "speaker-mute-20" : "speaker-2-20"; tip: root.muted ? qsTr("Unmute (Alt+M)") : qsTr("Mute (Alt+M)"); onClicked: root.muted = !root.muted }
            Item { width: 10; height: 1 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: { const s = Math.floor(player.position / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
                color: "white"; font.family: theme.font; font.pixelSize: 14
            }
        }
        Rectangle {
            x: parent.width - 8 - width; y: parent.height - 15.7 - 24
            width: 32; height: 24; radius: 4
            color: fsHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "full-screen-maximize-20"; size: 20; color: "white" }
            HoverHandler { id: fsHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.fullScreenRequested() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Full screen (Alt+Enter)")
        }
    }
    focus: true
    Keys.onPressed: ev => {
        if (!(ev.modifiers & Qt.AltModifier)) return
        if (ev.key === Qt.Key_K) { player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play(); ev.accepted = true }
        else if (ev.key === Qt.Key_L) { if (player.seekable) player.position = Math.min(player.duration, player.position + 10000); ev.accepted = true }
        else if (ev.key === Qt.Key_M) { root.muted = !root.muted; ev.accepted = true }
        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.fullScreenRequested(); ev.accepted = true }
    }
    Accessible.role: Accessible.Animation
    Accessible.name: qsTr("Live event video")
}
