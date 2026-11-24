import QtQuick
import QtQuick.Controls.Basic

// A channel meeting's calendar card in its post (Teams' pre-state schedule
// meeting banner, `pre-state-schedule-meeting-banner-renderer`; TASK-0265,
// measured on winpc 2026-11-24 in OST Test Team > OST test channel and
// read from Teams' 395276 / 546745):
// - The banner: padding 16 20, at least 70 tall, radius 4, filled
//   NeutralBackground1Selected with a 1 px NeutralBackground1Pressed line,
//   and a 2 px brand bar 5 in on its left (90 % of its height). In a post
//   it sits 2 left of the text and 4 wider, 12 above it.
// - The meeting: a 32 px white box (radius 4) with the brand calendar
//   (filled, 20), then 10 after it the title (14/20 semibold, two lines at
//   most; "Canceled: {title}" struck through once cancelled; the repeat
//   glyph after a series' title) over the start (12/16: "Thursday,
//   November 19, 2026 6:00 AM").
// - Not cancelled: clicking it opens the meeting's details (hover
//   NeutralBackground2 with a NeutralStroke1Selected line), with More
//   options (32 x 31.3; brand while its menu is open: View / Edit meeting
//   details with the bullet-list glyph, centred 5 under it) and, 8 after
//   it, Join (at least 96 x 31.3, white, a #D1D1D1 line, 14/600) 20.7 from
//   the right. Teams opens the meeting's own page (the organizer's
//   editable form); OST opens it in Calendar.
Rectangle {
    id: root
    /// The message's `scheduled_meeting`.
    property var meeting: null
    /// You organize it (More options says Edit meeting details).
    property bool organizer: false
    signal join()
    signal openDetails()
    readonly property bool cancelled: !!meeting && meeting.cancelled === true
    readonly property string title: !meeting ? "" : meeting.title || qsTr("No title")
    readonly property string when: {
        if (!meeting || !meeting.start) return ""
        const d = new Date(meeting.start)
        return isNaN(d) ? "" : theme.longDate(d) + " " + theme.time(d)
    }
    readonly property bool hot: !cancelled && (hover.hovered || pressed.pressed)
    implicitHeight: Math.max(70, info.height + 32 + 1.34)
    radius: 4
    color: pressed.pressed && !cancelled ? theme.pick("#BDBDBD", "#2E2E2E", "#000000")
        : hot ? theme.pick("#FAFAFA", "#333333", "#000000")
        : theme.pick("#EBEBEB", "#3D3D3D", "#000000")
    border.width: 0.67
    border.color: hot ? theme.pick("#BDBDBD", "#5C5C5C", "#1AEBFF") : theme.pick("#E0E0E0", "#141414", "#FFFFFF")
    // The brand bar.
    Rectangle {
        x: 5.67; width: 2; radius: 1
        height: (parent.height - 1.34) * 0.9
        anchors.verticalCenter: parent.verticalCenter
        color: theme.brand
    }
    HoverHandler { id: hover; enabled: !root.cancelled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: pressed; enabled: !root.cancelled; onTapped: root.openDetails() }
    Rectangle {
        id: iconBox
        x: 20.7; anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32; radius: 4
        color: theme.pick("#FFFFFF", "#FFFFFF", "#000000")
        border.width: theme.highContrast ? 1 : 0
        border.color: theme.brand
        FluentIcon { anchors.centerIn: parent; name: "calendar-filled"; size: 20; color: theme.pick("#5B5FC7", "#5B5FC7", "#1AEBFF") }
    }
    Column {
        id: info
        x: iconBox.x + 32 + 10
        width: (buttons.visible ? buttons.x - 8 : root.width - 20.7) - x
        anchors.verticalCenter: parent.verticalCenter
        Row {
            width: parent.width
            spacing: 5
            Text {
                id: titleText
                width: Math.min(implicitWidth, parent.width - (repeatIcon.visible ? 25 : 0))
                text: root.cancelled ? qsTr("Canceled: %1").arg(root.title) : root.title
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                font.strikeout: root.cancelled
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            FluentIcon {
                id: repeatIcon
                visible: !!root.meeting && root.meeting.recurring === true
                y: 0; size: 20; name: "arrow-repeat-all-16"; color: theme.text
            }
        }
        Text {
            visible: root.when !== ""
            width: parent.width; elide: Text.ElideRight
            text: root.when
            font.family: theme.font; font.pixelSize: 12
            lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }
    // Join and More options (not once cancelled).
    Row {
        id: buttons
        visible: !root.cancelled
        anchors.right: parent.right; anchors.rightMargin: 20.7
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Rectangle {
            id: moreButton
            width: 32; height: 31.3; radius: 4
            color: moreHover.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(moreButton, moreMenu.opened ? theme.brand : theme.textStrong) }
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: moreMenu.open() }
            ToolTip.visible: moreHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("More options")
            Accessible.role: Accessible.Button; Accessible.name: qsTr("More options")
            MenuPopup {
                id: moreMenu
                y: parent.height + 5
                x: (parent.width - width) / 2
                items: [{ key: "details", label: root.organizer ? qsTr("Edit meeting details") : qsTr("View meeting details"), icon: "text-bullet-list-20" }]
                onPicked: i => root.openDetails()
            }
        }
        Rectangle {
            id: joinButton
            width: Math.max(96, joinText.implicitWidth + 24); height: 31.3; radius: 4
            color: joinHover.hovered ? theme.hover : theme.surface
            border.width: 0.67; border.color: joinHover.hovered ? theme.pick("#C7C7C7", "#757575", "#1AEBFF") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
            Text { id: joinText; anchors.centerIn: parent; text: qsTr("Join"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(joinButton, theme.textStrong) }
            HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.join() }
            ToolTip.visible: joinHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Join meeting")
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Join meeting")
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: (root.cancelled ? qsTr("Cancelled.") + " " : "") + root.title + ". " + root.when
}
