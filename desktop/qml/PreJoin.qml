import QtQuick
import QtQuick.Window

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
    signal join(bool micOn)
    signal cancelled()

    width: 1280; height: 680
    minimumWidth: 1000; minimumHeight: 640
    color: theme.pane
    title: "Meeting join | " + subject

    function openFor(url, subj, start, end) {
        joinUrl = url; subject = subj
        startTime = start ? new Date(start) : new Date()
        endTime = end ? new Date(end) : new Date()
        micOn = true
        show(); raise(); requestActivate()
    }
    readonly property string mic: { const v = backend.setting("micDevice"); return v && v !== "default" ? v : "Default microphone" }
    readonly property string speaker: { const v = backend.setting("speakerDevice"); return v && v !== "default" ? v : "Default speaker" }

    Shortcut { sequence: "Escape"; onActivated: { win.close(); win.cancelled() } }
    Rectangle { anchors.fill: parent; color: theme.pane }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 73
        spacing: 6
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "../assets/logo.jpg"; width: 40; height: 40
            sourceSize: Qt.size(80, 80); fillMode: Image.PreserveAspectFit; smooth: true
        }
        Item { width: 1; height: 8 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.subject
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
        // Camera (off; OST has no video yet)
        Rectangle {
            width: 508; height: 329; radius: 4
            color: theme.surface; border.color: theme.dividerSoft
            Column {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -22
                spacing: 8
                FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "video-off"; size: 20; color: theme.textStrong }
                Text { text: "Your camera is turned off"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            Rectangle { y: parent.height - 44; width: parent.width; height: 1; color: theme.dividerSoft }
            Row {
                x: 16; y: parent.height - 44; height: 44
                spacing: 12
                opacity: 0.45
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "video-off"; size: 20; color: theme.textStrong }
                Toggle { on: false; usable: false; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        // Audio
        Column {
            width: 449
            spacing: 8
            Rectangle {
                width: parent.width; height: 185; radius: 4
                color: theme.surface; border.color: theme.dividerSoft
                Radio { x: 16; y: 18; on: true; label: "Computer audio" }
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
            Repeater {
                model: ["Phone audio", "Room audio", "Don't use audio"]
                Rectangle {
                    required property string modelData
                    width: 449; height: 40; radius: 4
                    color: theme.surface; border.color: theme.dividerSoft
                    Radio { x: 16; anchors.verticalCenter: parent.verticalCenter; on: false; label: parent.modelData; opacity: 0.45 }
                }
            }
        }
    }

    Row {
        anchors.right: panels.right; y: panels.y + 329 + 24
        spacing: 8
        Rectangle {
            width: 96; height: 32; radius: theme.radius
            color: cxh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cxh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { win.close(); win.cancelled() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 32; radius: theme.radius
            color: jnh.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Join now"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: "white" }
            HoverHandler { id: jnh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { win.close(); win.join(win.micOn) } }
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
