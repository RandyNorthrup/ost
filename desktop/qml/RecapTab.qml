import QtQuick
import QtQuick.Controls.Basic

// A chat's Recap tab (chattabs.recap), which Teams draws itself (no
// frame). Measured in Teams on the web on 2026-11-16 at 864 x 555 (CSS px,
// docs/spec/chat-tabs.md):
// - a chat (group or 1:1) with no recap: #F5F5F5, padding 0 12 12; centred,
//   a 600-wide box (padding 24) with the meeting-notes picture (256), "No
//   recap in this chat" (16/22.86 bold) 24 under it and "Turn on
//   transcription during a call to get a recap with notes and follow-up
//   tasks." (14/20) 10 under that;
// - a meeting chat (intelligent recap): on #F5F5F5, a 48-tall header
//   (padding 8 12) with More options at the right (Go to Meeting Recaps,
//   Delete recap content); "Shared files" (a white card, radius 8, padding
//   12 0, 8 above the next): the title 14/20 semibold 16 in, then the
//   meeting's files (Attendance: 399 x 32, a #F0F0F0 line, radius 4, the
//   20 px icon 11 in, the name 12/20 at 45), opening them; then a white
//   card (radius 8) to the bottom (12 above it) with the pills AI summary,
//   Mentions and Transcript (32 tall, radius 15, padding 5 8, 13/20, 8
//   apart, 12 in and 12 down; the chosen one #E8EBFA with a #444791 line
//   and #4F52B2 semibold text, the others a #D1D1D1 line and #424242), a
//   hairline 56 down, and the pill's page: a 192 picture, its title (16/22.86
//   bold) 24 under it and its text (14/20) 8 under that, centred in 600.
Rectangle {
    id: root
    /// A meeting chat (Teams' intelligent recap) or another chat.
    property bool meeting: false
    /// The meeting has an attendance report (its Shared files' Attendance).
    property bool hasAttendance: false
    signal openAttendance()
    color: theme.pane
    property string pill: "AI summary"
    function pillForTest(p) { pill = p }
    function moreForTest() { more.openMenu() }

    // An empty page: Teams' picture, title and text, centred.
    component EmptyState: Item {
        id: es
        property string picture
        property int pictureSize: 192
        property string title
        property string body
        Column {
            anchors.centerIn: parent
            width: Math.min(es.width, 600) - 48
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: es.pictureSize; height: es.pictureSize; sourceSize: Qt.size(es.pictureSize * 2, es.pictureSize * 2)
                source: "../assets/illustrations/" + es.picture + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
            }
            Item { width: 1; height: 24 }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: es.title
                lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Item { width: 1; height: es.pictureSize === 256 ? 10 : 8 }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: es.body
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
        }
    }

    // A chat without a recap.
    EmptyState {
        visible: !root.meeting
        anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
        picture: "meeting-notes"; pictureSize: 256
        title: "No recap in this chat"
        body: "Turn on transcription during a call to get a recap with notes and follow-up tasks."
    }

    // A meeting's recap.
    Item {
        visible: root.meeting
        anchors.fill: parent
        // The header: More options (Teams' Copilot button opens Copilot's
        // own page beside it, which OST doesn't have).
        Item {
            id: recapHeader
            width: parent.width; height: 48
            Rectangle {
                id: more
                anchors.right: parent.right; anchors.rightMargin: 20; y: 9
                width: 32; height: 30; radius: 4
                color: moreHover.hovered || moreMenu.opened ? theme.menuHover : "transparent"
                function openMenu() { moreMenu.x = more.width - moreMenu.implicitWidth; moreMenu.y = more.height + 5; moreMenu.open() }
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.onFill(more, theme.textStrong) }
                HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: more.openMenu() }
                Accessible.role: Accessible.Button; Accessible.name: "More options"
                // Teams' items; what they open isn't in OST yet (TASK-0171
                // notes), so they're shown off.
                MenuPopup {
                    id: moreMenu
                    items: [{ label: "Go to Meeting Recaps", icon: "arrow-counterclockwise-20", enabled: false },
                            { label: "Delete recap content", icon: "delete-20", enabled: false }]
                }
            }
        }
        Column {
            anchors { top: recapHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
            spacing: 8
            // Shared files.
            Rectangle {
                id: filesCard
                visible: root.hasAttendance
                width: parent.width; height: visible ? 90 : 0; radius: 8
                color: theme.surface
                Text {
                    x: 17; y: 13; height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: "Shared files"
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Rectangle {
                    id: attendanceItem
                    x: 16; y: 43
                    width: Math.min(399, parent.width - 32); height: 32; radius: 4
                    color: attHover.hovered ? theme.menuHover : theme.surface
                    border.width: 1; border.color: theme.pick("#F0F0F0", "#333333", "#FFFFFF")
                    Image {
                        x: 11; anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; sourceSize: Qt.size(40, 40)
                        source: "../assets/icons/attendance-report-32.svg"
                    }
                    Text {
                        x: 45; anchors.verticalCenter: parent.verticalCenter
                        text: "Attendance"
                        font.family: theme.font; font.pixelSize: 12; color: theme.text
                    }
                    HoverHandler { id: attHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openAttendance() }
                    Accessible.role: Accessible.Button; Accessible.name: "Attendance"
                }
            }
            // The recap's pages.
            Rectangle {
                width: parent.width
                height: parent.height - (filesCard.visible ? filesCard.height + parent.spacing : 0)
                radius: 8; color: theme.surface
                Row {
                    x: 13; y: 13; spacing: 8
                    Accessible.role: Accessible.PageTabList
                    Repeater {
                        model: ["AI summary", "Mentions", "Transcript"]
                        Rectangle {
                            id: pillItem
                            required property string modelData
                            readonly property bool sel: root.pill === modelData
                            // Its width holds the semibold name (Teams keeps
                            // a hidden bold copy).
                            width: boldWidth.advanceWidth + 22; height: 32; radius: 15
                            TextMetrics { id: boldWidth; text: pillItem.modelData; font.family: theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            color: sel ? theme.brandTint : pillHover.hovered ? theme.menuHover : theme.surface
                            border.width: 1; border.color: sel ? theme.pick("#444791", "#7F85F5", "#1AEBFF") : theme.stroke
                            Text {
                                id: pillText
                                anchors.centerIn: parent
                                text: pillItem.modelData
                                font.family: theme.font; font.pixelSize: 13; font.weight: pillItem.sel ? Font.DemiBold : Font.Normal
                                color: theme.onFill(pillItem, pillItem.sel ? theme.brandForeground1 : theme.textStrong)
                            }
                            HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.pill = pillItem.modelData }
                            Accessible.role: Accessible.PageTab; Accessible.name: modelData
                            Accessible.selected: sel
                        }
                    }
                }
                Rectangle { y: 57; x: 1; width: parent.width - 2; height: 1; color: theme.divider }
                EmptyState {
                    anchors { top: parent.top; topMargin: 58; left: parent.left; right: parent.right; bottom: parent.bottom }
                    picture: root.pill === "Mentions" ? "tag" : "meeting-notes"
                    title: root.pill === "AI summary" ? "Get AI-powered meeting summary"
                        : root.pill === "Mentions" ? "Know if your name came up" : "No transcript available"
                    body: root.pill === "AI summary" ? "When Intelligent recap is turned on, AI can generate notes and suggest tasks to follow up on."
                        : root.pill === "Mentions" ? "Turn on transcription, and AI will find mentions of you in the transcript."
                        : "The transcript for this meeting was never created, has expired, or has been deleted."
                }
            }
        }
    }
}
