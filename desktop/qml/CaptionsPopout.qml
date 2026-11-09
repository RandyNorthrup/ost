import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Teams' captions in a window of their own ("Open captions in new
// window"; flyout-closed-captions, measured on winpc, 2026-11-09): 606 x
// 353, kept on top until unpinned:
// - its title row (32 tall): Pop in (32 x 31.33) and the meeting's title
//   (12/16), the pin (24 x 23.33, "Unpin window") at the right;
// - "Live Captions" (20/28.57 bold), 20 in and 13.4 down, with caption
//   settings (32 px) 18 from the right, 55.35 tall in all;
// - the captions, 15 in, under it, 10 above the bottom.
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
    property bool pinned: true
    signal popIn()
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
        color: tbh.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: tb.icon; size: tb.glyph; color: theme.textStrong }
        HoverHandler { id: tbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
        ToolTip.visible: tbh.hovered
        ToolTip.delay: 250
        ToolTip.text: tb.tip
        Accessible.role: Accessible.Button
        Accessible.name: tb.tip
    }
    Item {
        id: titleRow
        width: parent.width; height: 32
        TitleButton { width: 32; height: 31.33; icon: "window-pop-in-20"; tip: "Pop in"; onClicked: win.popIn() }
        Text {
            x: 32; y: 7.67; height: 16
            width: Math.min(implicitWidth, parent.width - 32 - 60)
            elide: Text.ElideRight
            text: win.meetingTitle
            font.family: theme.font; font.pixelSize: 12
            color: theme.text
        }
        // Kept on top until unpinned; once unpinned Teams no longer shows
        // the pin (as measured).
        TitleButton {
            visible: win.pinned
            anchors.right: parent.right; anchors.rightMargin: 8; y: 4.42
            width: 24; height: 23.33
            icon: "pin-20"; glyph: 20
            tip: "Unpin window"
            onClicked: win.pinned = false
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: Qt.rgba(0, 0, 0, 0.06) }
    }
    Item {
        id: header
        y: 32; width: parent.width; height: 56.02
        Text {
            x: 20; y: 13.4; height: 28.57
            verticalAlignment: Text.AlignVCenter
            text: "Live Captions"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold
            color: theme.pick("#000000", "#FFFFFF")
            Accessible.role: Accessible.Heading
            Accessible.name: text
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
        width: parent.width; height: parent.height - y - 10
        windowHeight: 0; areaHeight: 0
    }
}
