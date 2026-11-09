import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' captions in a window of their own ("Open captions in new
// window"; flyout-closed-captions, measured on winpc, 2026-11-09): 606 x
// 353, kept on top until unpinned:
// - its title row (ChildWindowTitleBar, 32 tall): Pop in (32 x 31.33) and
//   the meeting's title (12/16); at the right the pin (24 x 23.33, "Unpin
//   window") and Settings and more;
// - "Live Captions" (20/28.57 bold), 20 in and 13.4 down, with caption
//   settings (32 px) 18 from the right, 55.35 tall in all;
// - the captions, 15 in, under it, 10 above the bottom.
// While RTT is on ("Open RTT/Captions in new window") the heading is "RTT",
// a "Live Captions" switch (its 40 x 20 track at 341.93, 17.68 down; the
// label 4 after the 56 px switch) turns captions on and off, and the RTT
// box is at the bottom.
// Pop in (or closing it) puts the captions back under the stage.
Window {
    id: win
    property string meetingTitle: ""
    property alias captions: list.captions
    property alias roster: list.roster
    property alias meId: list.meId
    property alias meName: list.meName
    property alias filterProfanity: list.filterProfanity
    property alias languageName: list.languageName
    property alias styles: list.styles
    property alias rttOn: list.rttOn
    property alias rttInitiator: list.rttInitiator
    property alias privacyUrl: list.privacyUrl
    property bool captionsOn: false
    property bool pinned: true
    signal popIn()
    signal setCaptions(bool on)
    signal settingsRequested(Item anchor)
    title: meetingTitle
    width: 606; height: 353
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
    onClosing: close => win.popIn()

    Rectangle { anchors.fill: parent; color: theme.surface }

    component TitleButton: Rectangle {
        id: tb
        property string icon
        property string tip
        property int glyph: 20
        signal clicked()
        radius: 4
        color: tbh.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: tb.icon; size: tb.glyph; color: theme.textStrong }
        HoverHandler { id: tbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        ToolTip.visible: tbh.hovered
        ToolTip.delay: 250
        ToolTip.text: tb.tip
        Accessible.role: Accessible.Button
        Accessible.name: tb.tip
    }
    ChildWindowTitleBar {
        id: titleRow
        title: win.meetingTitle
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
        leading: [
            TitleButton { width: 32; height: 31.33; icon: "window-pop-in-20"; tip: "Pop in"; onClicked: win.popIn() }
        ]
        // Kept on top until unpinned; once unpinned Teams no longer shows
        // the pin (as measured).
        trailing: [
            TitleButton {
                visible: win.pinned
                width: 24; height: 23.33
                icon: "pin-20"; glyph: 20
                tip: "Unpin window"
                onClicked: win.pinned = false
            }
        ]
    }
    Item {
        id: header
        y: 32; width: parent.width; height: 56.02
        Text {
            x: 20; y: 13.4; height: 28.57
            verticalAlignment: Text.AlignVCenter
            text: win.rttOn ? "RTT" : "Live Captions"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            color: theme.pick("#000000", "#FFFFFF")
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        // RTT's "Live Captions" switch.
        Item {
            id: captionsSwitch
            visible: win.rttOn
            x: win.width - 272.07; y: 9.68
            width: 150.07; height: 36
            Rectangle {
                x: 8; y: 8; width: 40; height: 20; radius: 10
                color: win.captionsOn ? (sw.hovered ? theme.brandHover : theme.brandFill) : "transparent"
                border.color: win.captionsOn ? "transparent" : (sw.hovered ? theme.text : theme.textStrong)
                border.width: 0.67
                Rectangle {
                    width: 14; height: 14; radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    x: win.captionsOn ? parent.width - width - 3 : 3
                    color: win.captionsOn ? "white" : (sw.hovered ? theme.text : theme.textStrong)
                }
            }
            Text {
                x: 60; y: 8; height: 20
                verticalAlignment: Text.AlignVCenter
                text: "Live Captions"
                font.family: theme.font; font.pixelSize: 14
                color: theme.pick("#000000", "#FFFFFF")
            }
            HoverHandler { id: sw; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.setCaptions(!win.captionsOn) }
            Accessible.role: Accessible.CheckBox
            Accessible.name: "Live Captions"
            Accessible.checkable: true
            Accessible.checked: win.captionsOn
        }
        TitleButton {
            id: settingsButton
            anchors.right: parent.right; anchors.rightMargin: 18; y: 11.68
            width: 32; height: 32
            icon: "settings-20"; tip: "Open caption settings"
            onClicked: win.settingsRequested(settingsButton)
        }
    }
    CaptionsWindow {
        id: list
        popout: true
        y: header.y + header.height
        width: parent.width; height: parent.height - y
        windowHeight: 0; areaHeight: 0
    }
}
