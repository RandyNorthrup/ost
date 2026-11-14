import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import QtMultimedia

// A video clip in a message, as Teams shows it (measured on winpc,
// 2026-11-14, "OST TEST 135"):
// - Preview: the poster at the clip's shape, 400 wide at most (1280 x 720
//   → 400 x 225), rounded 4; a 48 px play circle (black at 40 %, white
//   play icon) 12 in from the left and bottom; the length ("0:16", 14 px
//   white on black at 40 %, 5 / 8 padding, rounded 4) 12 in from the right
//   and bottom; on hover, Options (32 x 30, black at 40 %, rounded 4) 12
//   in at the top right, whose menu is "Download video".
// - Playing (Teams' media player): the video over black; the controls on a
//   dark fade along the bottom while the pointer is over it or it is
//   paused: the progress bar (384 x 12, 8 in, 4 above the buttons), then
//   32 px buttons 8 from the bottom: Play/Pause, Skip 10 seconds backward,
//   Skip 10 seconds forward and the sound ("This video has no sound" when
//   it has none) from the left; closed captions ("This video doesn't
//   contain closed captions."), Playback speed ("1x"), Playback options
//   and Full screen from the right, 8 in.
// - Its menus are dark (#292827 at 80 %, rounded 2, 3 padding, 32 px rows
//   of white 14 px text), 20 above the buttons: the speeds 2x, 1.8x, 1.5x,
//   1.2x, 1x and 0.8x; Playback options (269 wide): Quality ▸ (Auto and
//   the clip's renditions) and Keyboard shortcuts.
// - At the end: the poster dimmed and blurred, "Reply with a video clip"
//   (brand, 31.3 tall) and, 10 under it, "Play again" with the replay icon.
Item {
    id: root
    objectName: "videoClip-" + (clip.id || "")
    /// The clip as the backend lists it (api::messages::VideoClip).
    property var clip: ({})
    property real maxWidth: 400
    /// The colour around the card, for its rounded corners.
    property color background: theme.surface
    /// "Reply with a video clip" was picked; the button shows only where
    /// OST can record a clip (`canReply`).
    signal replyWithClip()
    property bool canReply: false

    readonly property real cardW: Math.min(400, maxWidth)
    width: cardW
    height: clip.width > 0 && clip.height > 0 ? cardW * clip.height / clip.width : cardW * 9 / 16

    /// "preview", "loading", "playback" or "ended".
    property string state_: "preview"
    property string quality: ""
    property var qualities: []
    property string error: ""
    property bool fullScreen: false

    function clock(s) {
        s = Math.max(0, Math.round(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0")
    }
    function spokenLength(s) {
        s = Math.max(1, Math.round(s))
        const m = Math.floor(s / 60), ss = s % 60
        return (m > 0 ? m + (m === 1 ? " minute" : " minutes") + (ss > 0 ? " " : "") : "") + (ss > 0 || m === 0 ? ss + (ss === 1 ? " second" : " seconds") : "")
    }
    function play(fromQuality) {
        error = ""
        if (state_ === "ended") { player.position = 0; player.play(); state_ = "playback"; return }
        state_ = "loading"
        backend.videoClipLoad(clip.id || "", clip.url || "", fromQuality === undefined ? quality : fromQuality)
    }
    function setQuality(q) {
        if (q === quality) return
        resumeAt = player.position
        resumePlaying = player.playbackState === MediaPlayer.PlayingState
        quality = q
        play(q)
    }
    property real resumeAt: 0
    property real seekOnLoad: 0
    property bool resumePlaying: true
    function skip(ms) { player.position = Math.max(0, Math.min(player.duration, player.position + ms)) }
    function closePopups() { speedMenu.close(); optionsMenu.close(); qualityMenu.close(); shortcuts.visible = false }
    readonly property var speeds: [2, 1.8, 1.5, 1.2, 1, 0.8]
    function stepSpeed(dir) {
        const i = speeds.indexOf(player.playbackRate)
        const j = Math.max(0, Math.min(speeds.length - 1, (i < 0 ? 4 : i) - dir))
        player.playbackRate = speeds[j]
    }

    Connections {
        target: backend
        function onVideoClipReady(id, json) {
            if (id !== root.clip.id || root.state_ !== "loading") return
            const r = JSON.parse(json)
            if (r.quality !== root.quality) return
            if (r.error) { root.error = r.error; root.state_ = "preview"; return }
            root.qualities = r.qualities || []
            player.source = r.path
            root.state_ = "playback"
            // A quality change carries on where it was (once the new file
            // has loaded: seeking before that is lost).
            root.seekOnLoad = root.resumeAt
            root.resumeAt = 0
            if (root.resumePlaying) player.play(); else player.pause()
            root.resumePlaying = true
            surface.forceActiveFocus()
        }
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput { id: audio }
        videoOutput: root.fullScreen ? fullVideo : video
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState && root.state_ === "playback" && duration > 0 && position >= duration - 250) root.state_ = "ended"
        onErrorOccurred: (e, s) => { root.error = s; root.state_ = "preview" }
        onMediaStatusChanged: if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && root.seekOnLoad > 0) { position = root.seekOnLoad; root.seekOnLoad = 0 }
    }

    Rectangle { anchors.fill: parent; color: "black"; visible: root.state_ === "playback" || root.state_ === "loading" }
    // The poster (preview, loading and the end screen).
    Image {
        id: poster
        anchors.fill: parent
        visible: root.state_ !== "playback"
        source: root.clip.thumb_local || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // The end screen's poster: drawn from a tiny copy, which blurs it.
    Image {
        anchors.fill: parent
        visible: root.state_ === "ended"
        source: root.clip.thumb_local || ""
        sourceSize: Qt.size(32, 18)
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }
    VideoOutput {
        id: video
        anchors.fill: parent
        visible: root.state_ === "playback"
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Keys and hover over the whole card.
    Item {
        id: surface
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (root.state_ !== "playback") return
            const alt = ev.modifiers & Qt.AltModifier
            if (ev.key === Qt.Key_Escape) { root.closePopups(); ev.accepted = true; return }
            if (!alt) {
                if (ev.key === Qt.Key_Space) { player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play(); ev.accepted = true }
                return
            }
            ev.accepted = true
            switch (ev.key) {
            case Qt.Key_K: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play(); break
            case Qt.Key_Return: case Qt.Key_Enter: root.fullScreen = !root.fullScreen; break
            case Qt.Key_M: audio.muted = !audio.muted; break
            case Qt.Key_Up: audio.volume = Math.min(1, audio.volume + 0.1); break
            case Qt.Key_Down: audio.volume = Math.max(0, audio.volume - 0.1); break
            case Qt.Key_X: root.stepSpeed(1); break
            case Qt.Key_Z: root.stepSpeed(-1); break
            case Qt.Key_L: root.skip(10000); break
            case Qt.Key_J: root.skip(-10000); break
            case Qt.Key_Right: root.skip(15000); break
            case Qt.Key_Left: root.skip(-15000); break
            case Qt.Key_G: shortcuts.visible = true; break
            default:
                if (ev.key >= Qt.Key_0 && ev.key <= Qt.Key_9) player.position = player.duration * (ev.key - Qt.Key_0) / 10
                else ev.accepted = false
            }
        }
        HoverHandler { id: cardHover }
        // Clicking the video plays or pauses it (Teams' player).
        TapHandler {
            enabled: root.state_ === "playback"
            onTapped: { surface.forceActiveFocus(); player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
        }
    }

    // ---- Preview ----
    Rectangle {
        visible: root.state_ === "preview" || root.state_ === "loading"
        x: 12; y: parent.height - 12 - 48
        width: 48; height: 48; radius: 24
        color: "#66000000"
        FluentIcon { visible: root.state_ === "preview"; anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; name: "play-20-filled"; size: 22; color: "white" }
        BusyIndicator { visible: root.state_ === "loading"; anchors.centerIn: parent; width: 28; height: 28; running: visible; palette.dark: "white" }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.state_ === "preview"; onTapped: root.play() }
        Accessible.role: Accessible.Button
        Accessible.name: "Play video. " + root.spokenLength(root.clip.duration || 0) + " long"
        Accessible.onPressAction: root.play()
    }
    Rectangle {
        visible: root.state_ === "preview" || root.state_ === "loading"
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
        width: lengthText.implicitWidth + 16; height: 32; radius: 4
        color: "#66000000"
        Text { id: lengthText; anchors.centerIn: parent; text: root.clock(root.clip.duration || 0); font.family: theme.font; font.pixelSize: 14; color: "white" }
    }
    Text {
        visible: root.error.length > 0 && root.state_ === "preview"
        x: 72; y: parent.height - 12 - 40; width: parent.width - 72 - 80
        text: "Couldn't load video clip."
        font.family: theme.font; font.pixelSize: 12; color: "white"; wrapMode: Text.Wrap
        style: Text.Raised; styleColor: "#80000000"
    }
    // Options (hover): Download video.
    Rectangle {
        id: optionsBtn
        visible: root.state_ !== "ended" && (cardHover.hovered || clipMenu.opened)
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
        width: 32; height: 30; radius: 4
        color: "#66000000"
        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: "white" }
        HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: clipMenu.popup(optionsBtn, optionsBtn.width - clipMenu.width, optionsBtn.height + 4) }
        ToolTip.visible: optHover.hovered && !clipMenu.opened
        ToolTip.text: "More video clip options"
        Accessible.role: Accessible.Button
        Accessible.name: "Options"
    }
    MenuPopup {
        id: clipMenu
        items: [{ label: "Download video", icon: "arrow-download-20" }]
        // (Placed in the card's own coordinates, under the button, its end
        // at the button's.)
        function popup(item, px, py) { const p = item.mapToItem(root, px, py); x = p.x; y = p.y; open() }
        onPicked: backend.videoClipDownload(root.clip.url || "")
    }

    // ---- End screen ----
    Rectangle { anchors.fill: parent; visible: root.state_ === "ended"; color: "#80000000" }
    Column {
        visible: root.state_ === "ended"
        anchors.centerIn: parent
        spacing: 10
        Rectangle {
            visible: root.canReply
            anchors.horizontalCenter: parent.horizontalCenter
            width: replyText.implicitWidth + 24; height: 31.3; radius: 4
            color: replyHover.hovered ? theme.brandHover : theme.brand
            Text { id: replyText; anchors.centerIn: parent; text: "Reply with a video clip"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: replyHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.replyWithClip() }
            Accessible.role: Accessible.Button
            Accessible.name: "Reply with a video clip"
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: againRow.implicitWidth + 24; height: 31.3
            Row {
                id: againRow
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "replay-20"; size: 20; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Play again"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.play() }
            Accessible.role: Accessible.Button
            Accessible.name: "Play again"
        }
    }

    // ---- Player controls ----
    Item {
        id: controls
        anchors.fill: parent
        visible: root.state_ === "playback" && !shortcuts.visible && (cardHover.hovered || player.playbackState !== MediaPlayer.PlayingState || speedMenu.opened || optionsMenu.opened || qualityMenu.opened)
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 64
            gradient: Gradient {
                GradientStop { position: 0; color: "#00000000" }
                GradientStop { position: 1; color: "#99000000" }
            }
        }
        // The progress bar.
        Item {
            id: bar
            x: 8; y: parent.height - 8 - 32 - 4 - 12
            width: parent.width - 16; height: 12
            readonly property real frac: player.duration > 0 ? player.position / player.duration : 0
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#66FFFFFF" }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * bar.frac; height: 4; radius: 2; color: "white" }
            Rectangle { x: parent.width * bar.frac - 6; width: 12; height: 12; radius: 6; color: "white" }
            MouseArea {
                anchors.fill: parent; anchors.topMargin: -4; anchors.bottomMargin: -4
                cursorShape: Qt.PointingHandCursor
                function seek(mx) { if (player.duration > 0) player.position = Math.max(0, Math.min(1, mx / bar.width)) * player.duration }
                onPressed: m => seek(m.x)
                onPositionChanged: m => { if (pressed) seek(m.x) }
            }
            Accessible.role: Accessible.Slider
            Accessible.name: "Progress bar"
        }
        component CtlButton: Item {
            id: cb
            property string icon
            property string label
            property string text
            property bool enabledCtl: true
            signal clicked()
            width: 32; height: 32
            // (FluentIcon writes its colour into the SVG, which takes no
            // alpha: a disabled control is dimmed instead.)
            FluentIcon { visible: !cb.text; anchors.centerIn: parent; name: cb.icon; size: 20; color: "white"; opacity: cb.enabledCtl ? 1 : 0.6 }
            Text { visible: !!cb.text; anchors.centerIn: parent; text: cb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            HoverHandler { id: cbHover; cursorShape: cb.enabledCtl ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: { surface.forceActiveFocus(); if (cb.enabledCtl) cb.clicked() } }
            ToolTip.visible: cbHover.hovered
            ToolTip.delay: 300
            ToolTip.text: cb.label
            Accessible.role: Accessible.Button
            Accessible.name: cb.label
        }
        Row {
            x: 8; y: parent.height - 8 - 32
            CtlButton {
                readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
                icon: playing ? "pause-20" : "play-20"
                label: playing ? "Pause" : "Play"
                onClicked: playing ? player.pause() : player.play()
            }
            CtlButton { icon: "skip-back-10-20"; label: "Skip 10 seconds backward"; onClicked: root.skip(-10000) }
            CtlButton { icon: "skip-forward-10-20"; label: "Skip 10 seconds forward"; onClicked: root.skip(10000) }
            CtlButton {
                enabledCtl: player.hasAudio
                icon: !player.hasAudio || audio.muted || audio.volume === 0 ? "speaker-mute-20" : "speaker-2-20"
                label: !player.hasAudio ? "This video has no sound" : audio.muted ? "Unmute (Alt + M)" : "Mute (Alt + M)"
                onClicked: audio.muted = !audio.muted
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8
            y: parent.height - 8 - 32
            CtlButton { enabledCtl: false; icon: "closed-caption-20"; label: "This video doesn't contain closed captions." }
            CtlButton {
                id: speedBtn
                text: player.playbackRate + "x"
                label: "Playback speed is " + player.playbackRate
                onClicked: speedMenu.opened ? speedMenu.close() : speedMenu.openAt(speedBtn)
            }
            CtlButton {
                id: optionsCtl
                icon: "settings-20"; label: "Playback options"
                onClicked: optionsMenu.opened ? optionsMenu.close() : optionsMenu.openAt(optionsCtl)
            }
            CtlButton { icon: "full-screen-maximize-20"; label: root.fullScreen ? "Exit Fullscreen" : "Full screen"; onClicked: root.fullScreen = !root.fullScreen }
        }
    }

    // The player's dark menus, 20 above the buttons, centred on the
    // button that opened them and kept within the card.
    component DarkMenu: Popup {
        id: dm
        property var rows: []   // [{ label, value?, chevron?, checked? }]
        signal pickedRow(int index)
        parent: root
        padding: 3
        width: implicitWidth
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: Rectangle { color: "#CC292827"; radius: 2 }
        // Placed above the buttons, as tall as the room there allows (the
        // rest scrolls, as in Teams' player).
        property real anchorX: 0
        property real anchorY: 0
        x: Math.max(0, Math.min(root.width - width, anchorX - width / 2))
        height: Math.min(implicitHeight, anchorY - 20 - 8)
        y: anchorY - 20 - height
        function openAt(btn) {
            const p = btn.mapToItem(root, btn.width / 2, 0)
            anchorX = p.x
            anchorY = p.y
            open()
        }
        contentItem: Flickable {
            implicitWidth: menuCol.implicitWidth
            implicitHeight: menuCol.implicitHeight
            contentHeight: menuCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // (Teams' rows sit 5 in from the menu's top and bottom.)
            Column {
            id: menuCol
            topPadding: 5; bottomPadding: 5
            Repeater {
                model: dm.rows
                Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(dm.minRow, rowLabel.implicitWidth + (rowValue.visible ? rowValue.implicitWidth + 32 : 0) + 16)
                    height: 32
                    color: rowHover.hovered ? "#33FFFFFF" : "transparent"
                    Text { id: rowLabel; x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: parent.modelData.checked ? Font.DemiBold : Font.Normal; color: "white" }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { id: rowValue; visible: !!parent.parent.modelData.value; anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.value || ""; font.family: theme.font; font.pixelSize: 14; color: "white" }
                        FluentIcon { visible: !!parent.parent.modelData.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-20"; size: 20; color: "white" }
                        FluentIcon { visible: !!parent.parent.modelData.checked; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-20"; size: 20; color: "white" }
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dm.pickedRow(parent.index) }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
            }
        }
        property real minRow: 80.7
    }
    DarkMenu {
        id: speedMenu
        minRow: 80.7
        rows: root.speeds.map(s => ({ label: s + "x", checked: player.playbackRate === s }))
        onPickedRow: i => { player.playbackRate = root.speeds[i]; close() }
    }
    readonly property string qualityLabel: {
        if (!quality) return "Auto"
        const q = qualities.find(q => q.id === quality)
        return q ? q.height + "p" : "Auto"
    }
    DarkMenu {
        id: optionsMenu
        minRow: 265
        rows: [{ label: "Quality", value: root.qualityLabel, chevron: true }, { label: "Keyboard shortcuts" }]
        onPickedRow: i => {
            close()
            if (i === 0) qualityMenu.openAt(optionsCtl)
            else shortcuts.visible = true
        }
    }
    DarkMenu {
        id: qualityMenu
        minRow: 160
        rows: [{ label: "Auto", checked: !root.quality }].concat(root.qualities.map(q => ({ label: q.height + "p", checked: root.quality === q.id })))
        onPickedRow: i => { close(); root.setQuality(i === 0 ? "" : root.qualities[i - 1].id) }
    }

    // Keyboard shortcuts (Teams' player lists them in a white panel).
    Rectangle {
        id: shortcuts
        visible: false
        anchors.fill: parent
        color: theme.surface
        z: 5
        readonly property var rows: [
            ["Play or pause media", "Alt + K"], ["Close open popups", "Esc"], ["Enter or exit full screen mode", "Alt + Enter"],
            ["Mute or unmute sound", "Alt + M"], ["Increase sound volume", "Alt + up arrow key"], ["Decrease sound volume", "Alt + down arrow key"],
            ["Toggle noise suppression on and off", "Alt + A"], ["Toggle between audio tracks", "Alt + H"], ["Toggle between caption languages", "Alt + C"],
            ["Enter or exit captions reposition mode", "Alt + R"], ["Move captions while in reposition mode", "Alt + arrow keys"],
            ["Increase playback speed", "Alt + X"], ["Decrease playback speed", "Alt + Z"], ["Skip 10 seconds forward", "Alt + L"],
            ["Skip 10 seconds backward", "Alt + J"], ["Skip 15 seconds forward", "Alt + right arrow key"], ["Skip 15 seconds backward", "Alt + left arrow key"],
            ["Go to 0% to 90% of the media", "Alt + 0 to 9 number keys"], ["Access keyboard shortcuts", "Alt + G"]
        ]
        Text { x: 24; y: 22; text: "Keyboard shortcuts"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Rectangle {
            x: parent.width - 24 - 32; y: 16; width: 32; height: 31.3; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { shortcuts.visible = false; surface.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Close keyboard shortcuts modal"
        }
        Flickable {
            x: 24; y: 48; width: parent.width - 48; height: parent.height - 48
            contentHeight: table.height; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Column {
                id: table
                width: parent.width
                Row {
                    Text { width: table.width * 0.54; padding: 12; text: "Shortcut name"; font.family: theme.font; font.pixelSize: 14; font.bold: true; color: theme.text; wrapMode: Text.Wrap }
                    Text { width: table.width * 0.46; padding: 12; text: "Keyboard command"; font.family: theme.font; font.pixelSize: 14; font.bold: true; color: theme.text; wrapMode: Text.Wrap }
                }
                Repeater {
                    model: shortcuts.rows
                    Row {
                        required property var modelData
                        Text { width: table.width * 0.54; padding: 12; text: parent.modelData[0]; font.family: theme.font; font.pixelSize: 14; color: theme.text; wrapMode: Text.Wrap }
                        Text { width: table.width * 0.46; padding: 12; text: parent.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text; wrapMode: Text.Wrap }
                    }
                }
            }
        }
    }

    RoundedCorners { anchors.fill: parent; radius: 4; background: root.background; z: 6 }

    // Full screen: the same player in a window of its own; Esc or the
    // button leaves it.
    Window {
        id: fullWin
        visible: root.fullScreen
        visibility: root.fullScreen ? Window.FullScreen : Window.Hidden
        color: "black"
        title: "Video Clip"
        onClosing: root.fullScreen = false
        VideoOutput { id: fullVideo; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.fullScreen = false
            Keys.onSpacePressed: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            TapHandler { onTapped: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
            TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: root.fullScreen = false }
        }
    }

    // Test hooks (--videoclip-test).
    function stateForTest() { return { state: state_, quality: quality, qualities: qualities, error: error, position: player.position, duration: player.duration, hasAudio: player.hasAudio, rate: player.playbackRate, source: String(player.source) } }
    function openSpeedForTest() { speedMenu.openAt(speedBtn) }
    function openOptionsForTest() { optionsMenu.openAt(optionsCtl) }
    function openQualityForTest() { qualityMenu.openAt(optionsCtl) }
    function closeMenusForTest() { closePopups() }
    function showShortcutsForTest(on) { shortcuts.visible = on }
    function pauseForTest() { player.pause() }
    function resumeForTest() { player.play() }
    function seekForTest(frac) { player.position = player.duration * frac }
    function openClipMenuForTest() { clipMenu.popup(optionsBtn, optionsBtn.width - clipMenu.width, optionsBtn.height + 4) }

    Accessible.role: Accessible.Grouping
    Accessible.name: "Media player. Press enter, spacebar, or otherwise activate player controls to play or pause the video."
}
