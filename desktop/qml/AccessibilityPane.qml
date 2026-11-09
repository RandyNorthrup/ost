import QtQuick
import QtQuick.Controls

// Teams' in-meeting Accessibility pane (More ▸ Settings ▸ Accessibility
// settings; accessibility-settings-panel, measured on winpc, 2026-11-09):
// #F5F5F5, the rail header "Accessibility", then cards 305.33 wide at
// 20.67, 12 apart from y 89, each with a 0.67 #D1D1D1 border, radius 8 and
// padding 20 x 12: a 20 px glyph at 18.67, the title (14/20) at 56.67,
// a description (12/16 #616161, 138.68 wide) and a switch with its
// "On" / "Off" (14/20) before it.
// - Captions: "Always show captions in my calls and meetings" and
//   "Filter out profane words in live captions" (the callAccessibility
//   user property, as caption settings).
// - Muted notification: the 'You're muted' notice (kept on the device).
// - Monitoring participants: "Hide Call Monitor when minimizing meeting
//   window" (the compact call window; the user property).
Rectangle {
    id: root
    /// {startCaptionsAutomatically, profanityFilterEnabled,
    /// hideCallMonitorOnMinimize, …}
    property var accessibility: ({})
    property bool showMutedNotice: true
    signal closed()
    signal updateAccessibility(string patch)
    signal mutedNoticeToggled(bool on)
    color: theme.pane

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Accessibility"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    // A switch with its state word before it (Fluent Switch, label before).
    component Toggle: Item {
        id: tg
        property bool checked: false
        property string accessibleName
        signal toggled(bool on)
        width: 88; height: 36
        Text {
            anchors.right: track.left; anchors.rightMargin: 10.67
            y: 8; height: 20
            verticalAlignment: Text.AlignVCenter
            text: tg.checked ? "On" : "Off"
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        Rectangle {
            id: track
            x: 48; y: 8; width: 40; height: 20; radius: 10
            color: tg.checked ? (th.hovered ? theme.brandHover : theme.brandFill) : "transparent"
            border.color: tg.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (tg.checked ? 20.67 : 0.67) + 9 - 7.2
                color: tg.checked ? "white" : theme.textSecondary
            }
        }
        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tg.toggled(!tg.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.name: tg.accessibleName
        Accessible.checked: tg.checked
    }
    component Card: Rectangle {
        default property alias content: body.data
        width: 305.33; height: body.implicitHeight + 40 + 1.33
        color: "transparent"; radius: 8
        border.color: theme.stroke; border.width: 0.67
        Item {
            id: body
            x: 12.67; y: 20.67; width: parent.width - 25.33
            implicitHeight: childrenRect.height
        }
    }
    component Description: Text {
        width: 138.68
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 12
        lineHeight: 16; lineHeightMode: Text.FixedHeight
        color: theme.textSecondary
    }
    component Setting: Text {
        width: 138.68
        wrapMode: Text.Wrap
        font.family: theme.font; font.pixelSize: 14
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: theme.text
    }

    Flickable {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: cards.implicitHeight + 28 + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: cards
            x: 20.67; y: 28
            spacing: 12
            // Captions (a group: its title beside the glyph, settings below).
            Card {
                FluentIcon { x: 6; y: 6; size: 20; name: "closed-caption-card-20"; color: theme.text }
                Text { x: 44; y: 6; height: 20; verticalAlignment: Text.AlignVCenter; text: "Captions"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Setting { id: alwaysText; x: 44; y: 48; text: "Always show captions in my calls and meetings" }
                Toggle {
                    x: 182.67; y: 48; accessibleName: alwaysText.text
                    checked: root.accessibility.startCaptionsAutomatically === true
                    onToggled: on => root.updateAccessibility(JSON.stringify({ startCaptionsAutomatically: on }))
                }
                Setting { id: profaneText; x: 44; y: alwaysText.y + alwaysText.height + 15; text: "Filter out profane words in live captions" }
                Toggle {
                    x: 182.67; y: profaneText.y; accessibleName: profaneText.text
                    checked: root.accessibility.profanityFilterEnabled === true
                    onToggled: on => root.updateAccessibility(JSON.stringify({ profanityFilterEnabled: on }))
                }
            }
            // Muted notification: Teams' 'You're muted' notice on or off.
            Card {
                FluentIcon { x: 6; y: 6; size: 20; name: "mic-off-card-20"; color: theme.text }
                Setting { id: mutedTitle; x: 44; y: 0; text: "Muted notification" }
                Description { x: 44; y: 20; text: "Show the 'You're muted' notification when audio is detected while your microphone is off." }
                Toggle {
                    x: 182.67; y: 0; accessibleName: mutedTitle.text
                    checked: root.showMutedNotice
                    onToggled: on => root.mutedNoticeToggled(on)
                }
            }
            // Monitoring participants.
            Card {
                FluentIcon { x: 6; y: 6; size: 20; name: "call-monitor-20"; color: theme.text }
                Text { x: 44; y: 6; height: 20; verticalAlignment: Text.AlignVCenter; text: "Monitoring participants"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Setting { id: monitorText; x: 44; y: 48; text: "Hide Call Monitor when minimizing meeting window" }
                Toggle {
                    x: 182.67; y: 48; accessibleName: monitorText.text
                    checked: root.accessibility.hideCallMonitorOnMinimize === true
                    onToggled: on => root.updateAccessibility(JSON.stringify({ hideCallMonitorOnMinimize: on }))
                }
                Description {
                    x: 44; y: monitorText.y + monitorText.height
                    text: "The Call Monitor is the floating window that appears when the meeting window is minimized. When this toggle is enabled we won't display the floating window when you minimize the meeting window. This setting doesn't affect the experience when sharing a screen or window."
                }
            }
        }
    }
}
