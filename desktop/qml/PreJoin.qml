import QtQuick
import QtQuick.Window
import com.ost.desktop

// The pre-join window, as Teams desktop shows it before a meeting
// (measured at 1x): "Meeting join | <title>", the logo, title and time;
// the camera panel (off) on the left; the audio choices on the right
// (Computer audio with the mic switch and your devices); Cancel and
// Join now. Choices OST can't offer yet are shown disabled.
Window {
    id: win
    property string subject
    property string joinUrl
    property date startTime
    property date endTime
    property bool micOn: true
    /// Your camera (Teams' pre-join switch): a live preview while on.
    property bool cameraOn: false
    /// Teams' audio choices: "computer", "room" or "none" (Don't use audio).
    property string audio: "computer"
    /// Held in the meeting's lobby (Teams' InLobby pre-join state): the
    /// title says someone will let you in, Join now and the audio choices
    /// are disabled; the mic and camera switches still work.
    property bool lobby: false
    /// Someone is in the meeting (else Teams says "when the meeting
    /// starts").
    property bool presenterConnected: true
    property string userName: ""
    signal join(bool micOn, bool withAudio, bool cameraOn)
    signal cancelled()
    /// Leave the lobby (Cancel, Escape).
    signal leaveLobby()

    width: 1280; height: 680
    minimumWidth: 1000; minimumHeight: 640
    color: theme.pane
    title: "Meeting join | " + subject

    function openFor(url, subj, start, end) {
        joinUrl = url; subject = subj
        startTime = start ? new Date(start) : new Date()
        endTime = end ? new Date(end) : new Date()
        micOn = true; audio = "computer"; cameraOn = false
        show(); raise(); requestActivate()
    }
    readonly property string mic: { const v = backend.setting("micDevice"); return v && v !== "default" ? v : "Default microphone" }
    readonly property string speaker: { const v = backend.setting("speakerDevice"); return v && v !== "default" ? v : "Default speaker" }

    Shortcut { sequence: "Escape"; onActivated: win.cancel() }
    function cancel() {
        win.close()
        if (win.lobby) win.leaveLobby(); else win.cancelled()
    }
    onCameraOnChanged: if (cameraOn && !backend.setCameraPreview(true)) cameraOn = false; else if (!cameraOn) backend.setCameraPreview(false)
    // The camera is free again for the call (or for nobody) once we go.
    onVisibleChanged: if (!visible && cameraOn) backend.setCameraPreview(false)
    Rectangle { anchors.fill: parent; color: theme.pane }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 73
        spacing: 6
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "../assets/logo.png"; width: 40; height: 40
            sourceSize: Qt.size(80, 80); fillMode: Image.PreserveAspectFit; smooth: true
        }
        Item { width: 1; height: 8 }
        // The title, or in the lobby Teams' lobby text in its place.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !win.lobby ? win.subject
                : win.presenterConnected ? "Hi, " + win.userName + ". Someone will let you in shortly."
                : "Hi, " + win.userName + ". Someone will let you in when the meeting starts."
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            color: theme.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(win.startTime, "dddd, MMM d") + "  •  " + Qt.formatTime(win.startTime, "h:mm AP") + " – " + Qt.formatTime(win.endTime, "h:mm AP")
            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
            color: theme.textStrong
        }
    }

    Row {
        id: panels
        anchors.horizontalCenter: parent.horizontalCenter
        y: 211
        spacing: 16
        // Camera: off, or your live preview (Teams' prejoin-v2-video-
        // preview: mirrored, filling the panel above its bar, inside the
        // 1 px edge).
        Rectangle {
            width: 508; height: 329; radius: 4
            color: theme.surface; border.color: theme.dividerSoft
            VideoFrame {
                id: preview
                visible: win.cameraOn && hasFrame
                source: win.cameraOn ? "self" : ""
                x: 1; y: 1; width: parent.width - 2; height: parent.height - 45
                radius: 3
                transform: Scale { origin.x: preview.width / 2; xScale: -1 }
                Timer { interval: 33; repeat: true; running: win.visible && win.cameraOn; onTriggered: preview.refresh() }
            }
            Column {
                visible: !preview.visible
                anchors.centerIn: parent; anchors.verticalCenterOffset: -22
                spacing: 8
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "video-off"; size: 20; color: theme.textStrong }
                Text { text: win.cameraOn ? "Starting your camera…" : "Your camera is turned off"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            Rectangle { y: parent.height - 44; width: parent.width; height: 1; color: theme.dividerSoft }
            Row {
                x: 16; y: parent.height - 44; height: 44
                spacing: 12
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: win.cameraOn ? "video-20-filled" : "video-off"; size: 20; color: theme.textStrong }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    on: win.cameraOn
                    onToggled: v => win.cameraOn = v
                    Accessible.name: "Camera"
                }
            }
        }
        // Audio
        Column {
            width: 449
            spacing: 8
            Rectangle {
                // Teams shows your devices only under Computer audio.
                width: parent.width; height: win.audio === "computer" ? 185 : 54; radius: 4
                clip: true
                color: theme.surface; border.color: theme.dividerSoft
                Radio {
                    x: 16; y: 18; on: win.audio === "computer"; label: "Computer audio"
                    opacity: win.lobby ? 0.45 : 1
                    TapHandler { enabled: !win.lobby; onTapped: win.audio = "computer" }
                }
                Rectangle { y: 54; width: parent.width; height: 1; color: theme.dividerSoft }
                Rectangle { y: 55; width: parent.width; height: parent.height - 56; color: theme.pane }
                Row {
                    x: 18; y: 74; spacing: 12
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: win.micOn ? "mic-24" : "mic-off-24"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 300; elide: Text.ElideRight; text: win.mic; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                Toggle {
                    anchors.right: parent.right; anchors.rightMargin: 18; y: 76
                    on: win.micOn
                    onToggled: v => win.micOn = v
                    Accessible.name: "Microphone"
                }
                Row {
                    x: 18; y: 112; spacing: 12
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 260; elide: Text.ElideRight; text: win.speaker; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
            }
            // Phone audio needs the tenant's Audio Conferencing; Teams greys
            // it the same way when the meeting has no dial-in.
            Repeater {
                model: [
                    { key: "phone", label: "Phone audio", usable: false },
                    { key: "room", label: "Room audio", usable: true },
                    { key: "none", label: "Don't use audio", usable: true }
                ]
                Rectangle {
                    required property var modelData
                    width: 449; height: win.audio === "room" && modelData.key === "room" ? 80 : 40; radius: 4
                    color: theme.surface; border.color: theme.dividerSoft
                    Radio {
                        x: 16; y: 10
                        on: win.audio === parent.modelData.key; label: parent.modelData.label
                        opacity: parent.modelData.usable && !win.lobby ? 1 : 0.45
                    }
                    // Room audio: Teams looks for a Teams Room nearby to pair with.
                    Text {
                        visible: win.audio === "room" && parent.modelData.key === "room"
                        x: 48; y: 46; width: parent.width - 64; wrapMode: Text.Wrap
                        text: "No rooms found nearby. Join with computer audio, or try again when you're in a Teams Room."
                        font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary
                    }
                    HoverHandler { cursorShape: parent.modelData.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: parent.modelData.usable && !win.lobby; onTapped: win.audio = parent.modelData.key }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.label
                    Accessible.checked: win.audio === modelData.key
                }
            }
        }
    }

    Row {
        anchors.right: panels.right; y: panels.y + Math.max(329, panels.height) + 24
        spacing: 8
        Rectangle {
            width: 96; height: 32; radius: theme.radius
            color: cxh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cxh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.cancel() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 32; radius: theme.radius
            // Disabled in the lobby (Fluent's disabled primary button).
            color: win.lobby ? theme.pick("#F0F0F0", "#141414") : jnh.hovered ? theme.brandHover : theme.brandFill
            border.color: win.lobby ? theme.pick("#E0E0E0", "#424242") : "transparent"
            Text { anchors.centerIn: parent; text: "Join now"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: win.lobby ? theme.pick("#BDBDBD", "#5C5C5C") : "white" }
            HoverHandler { id: jnh; cursorShape: win.lobby ? Qt.ArrowCursor : Qt.PointingHandCursor }
            // Room audio found no room: Teams then joins with computer audio.
            TapHandler { enabled: !win.lobby; onTapped: { win.close(); win.join(win.audio !== "none" && win.micOn, win.audio !== "none", win.cameraOn) } }
            Accessible.role: Accessible.Button
            Accessible.name: "Join now"
        }
    }

    // Fluent switch: a 40 x 20 pill.
    component Toggle: Rectangle {
        id: tg
        property bool on
        property bool usable: true
        signal toggled(bool on)
        width: 40; height: 20; radius: 10
        color: on ? theme.brandFill : "transparent"
        border.color: on ? "transparent" : theme.textStrong
        Rectangle {
            width: 14; height: 14; radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: tg.on ? parent.width - width - 3 : 3
            color: tg.on ? "white" : theme.textStrong
        }
        TapHandler { enabled: tg.usable; onTapped: tg.toggled(!tg.on) }
        HoverHandler { cursorShape: tg.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: on
    }

    component Radio: Row {
        property bool on
        property string label
        spacing: 12
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: "transparent"; border.color: parent.on ? theme.brand : theme.textStrong; border.width: 1
            Rectangle { visible: parent.parent.on; anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: theme.brand }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: on
    }
}
