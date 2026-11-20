import QtQuick
import QtQuick.Controls.Basic

// Teams' meeting recap card under a meeting's ended row (its recap
// chiclet, meeting-recap-chiclet-app; measured on winpc 2026-11-20 in
// "Event group: OST TEST 217 town hall 2"): 646 x 162, white, radius 8,
// Teams' shadow (0 0 2 .12, 0 2 4 .14), padding 14 20 0.
// - The subject (16/20 600 #242424) over the date range (12/20 #616161,
//   "Wednesday, November 18, 2026 8:40 PM - 9:40 PM"; another end day adds
//   its date without the year).
// - At the right: Share (32 x 32) and the recap button: "View recap", or for
//   an event's organizer the "Highlights" split button (brand, its 20 x 32
//   chevron opening Highlights / Recap).
// - A line, then "Content" (12/20 600 #616161) over the chips (Transcript:
//   96 x 32, white, 0.67 #F0F0F0, radius 4, a 20 px icon and 12 px label).
// - The recording at the right: a 108 x 60 thumbnail (radius 6) with its
//   duration on a rgba(0,0,0,.4) pill (12 px white, radius 2, padding 1 6),
//   "{n} recordings" for several, "Saving..." while saved; under it the
//   expiry ("Expires in 119 days", 10 px #616161 after a 10 px clock).
// Each part opens what Teams opens: the chat's Recap (View recap, the
// thumbnail, the transcript chip), Highlights the event's highlights.
Item {
    id: root
    property var recap: ({})
    /// The meeting's title when the call-end message names none.
    property string fallbackTitle: ""
    /// An event's organizer (Teams shows Highlights then).
    property bool highlights: false
    signal openRecap(string tab)
    signal openHighlights()
    signal share()
    width: 646; height: 162
    readonly property var recs: (recap && recap.recordings) || []
    readonly property bool hasRec: recs.length > 0 || !!(recap && recap.saving)
    function dateRange() {
        if (!recap || !recap.start) return ""
        const a = new Date(recap.start), b = recap.end ? new Date(recap.end) : null
        const loc = Qt.locale()
        const first = a.toLocaleDateString(loc, "dddd, MMMM d, yyyy") + " " + theme.time(a)
        if (!b || isNaN(b.getTime())) return first
        const same = a.toDateString() === b.toDateString()
        const second = (same ? "" : b.toLocaleDateString(loc, "dddd, MMMM d") + " ") + theme.time(b)
        // Teams' dash_space_separated_format ("{{value1}} - {{value2}}").
        return qsTr("%1 - %2", "calendar:k6vk7q5v3").arg(first).arg(second)
    }
    function durationText(s) { return backend.durationText("call", s) }
    FluentSurface { anchors.fill: parent; depth: 4; radius: 8; color: theme.surface }
    Text {
        x: 20.7; y: 14.7; width: shareBtn.x - x - 8
        elide: Text.ElideRight
        text: (root.recap && root.recap.subject) || root.fallbackTitle
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong
    }
    Text {
        x: 20.7; y: 34.7; width: shareBtn.x - x - 8
        elide: Text.ElideRight
        text: root.dateRange()
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
    }
    Rectangle {
        id: shareBtn
        x: recapBtn.x - 4 - width; y: 20.7; width: 32; height: 32; radius: 4
        color: shareHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "share-20"; size: 20; color: theme.onFill(shareBtn, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: shareHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.share() }
        ToolTip.visible: shareHover.hovered; ToolTip.text: qsTr("Share", "meetingRecap:k6u0o3ifj"); ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Share", "meetingRecap:k6u0o3ifj")
    }
    // The recap button (brand): "View recap", or Highlights with its chevron.
    Row {
        id: recapBtn
        x: root.width - 20.7 - width; y: 20.7
        Rectangle {
            id: primary
            width: primaryRow.implicitWidth + 24; height: 32
            topLeftRadius: 4; bottomLeftRadius: 4; topRightRadius: root.highlights ? 0 : 4; bottomRightRadius: root.highlights ? 0 : 4
            color: primaryHover.hovered ? theme.brandHover : theme.brandFill
            Row {
                id: primaryRow
                anchors.centerIn: parent; spacing: 4
                FluentIcon { visible: root.highlights; anchors.verticalCenter: parent.verticalCenter; name: "sparkle-20"; size: 20; color: theme.textOnBrand }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.highlights ? qsTr("Highlights", "meetingRecap:kc40v5p0g") : qsTr("View recap", "messaging:k1tc0zdrt")
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand
                }
            }
            HoverHandler { id: primaryHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.highlights ? root.openHighlights() : root.openRecap("") }
            Accessible.role: Accessible.Button
            Accessible.name: root.highlights ? qsTr("Highlights", "meetingRecap:kc40v5p0g") : qsTr("View recap", "messaging:k1tc0zdrt")
        }
        Rectangle {
            visible: root.highlights
            width: 20; height: 32
            topRightRadius: 4; bottomRightRadius: 4
            color: triggerHover.hovered ? theme.brandHover : theme.brandFill
            Rectangle { width: 0.67; height: parent.height; color: Qt.rgba(1, 1, 1, 0.4) }
            FluentIcon { anchors.centerIn: parent; name: "chevron-down-12"; size: 12; color: theme.textOnBrand }
            HoverHandler { id: triggerHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { const p = recapBtn.mapToItem(Overlay.overlay, 0, recapBtn.height + 4); recapMenu.x = p.x; recapMenu.y = p.y; recapMenu.open() } }
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: qsTr("Highlights", "meetingRecap:kc40v5p0g")
        }
    }
    Menu {
        id: recapMenu
        parent: Overlay.overlay
        MenuItem { text: qsTr("Highlights", "meetingRecap:kc40v5p0g"); onTriggered: root.openHighlights() }
        MenuItem { text: qsTr("Recap", "extensibility:k5hpfls5x"); onTriggered: root.openRecap("") }
    }
    Rectangle { x: 20.7; y: 66.7; width: root.width - 41.4; height: 0.67; color: theme.divider }
    Text {
        x: 20.7; y: 77.3
        text: qsTr("Content", "meetingRecap:kaeryhl69")
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary
    }
    Text {
        visible: !(root.recap && root.recap.transcript)
        x: 20.7; y: 107.3; height: 32
        verticalAlignment: Text.AlignVCenter
        text: qsTr("No content was shared", "meetingRecap:kcorsfr1k")
        font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
    }
    Rectangle {
        id: chip
        visible: !!(root.recap && root.recap.transcript)
        x: 20.7; y: 107.3; width: chipRow.implicitWidth + 17.2; height: 32; radius: 4
        color: chipHover.hovered ? theme.menuHover : theme.surface
        border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF"); border.width: 0.67
        Row {
            id: chipRow
            x: 8.6; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "document-text-20"; size: 20; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Transcript", "artifactsPlatform:k1tttxcnb"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openRecap("transcript") }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Transcript", "artifactsPlatform:k1tttxcnb")
    }
    // The recording.
    Rectangle {
        id: thumb
        visible: root.hasRec
        x: root.width - 20.7 - width; y: 79.3; width: 108; height: 60; radius: 6
        color: theme.pick("#E0E0E0", "#3D3D3D", "#000000")
        clip: true
        Image {
            anchors.fill: parent
            visible: root.recs.length > 0 && !!root.recs[0].thumb_local
            source: root.recs.length > 0 ? root.recs[0].thumb_local || "" : ""
            fillMode: Image.PreserveAspectCrop; asynchronous: true
        }
        FluentIcon { visible: root.recs.length === 0 || !root.recs[0].thumb_local; anchors.centerIn: parent; name: "video-20"; size: 20; color: theme.textSecondary }
        Rectangle {
            anchors { right: parent.right; rightMargin: 6; bottom: parent.bottom; bottomMargin: 8 }
            width: pill.implicitWidth + 12; height: 20; radius: 2
            color: Qt.rgba(0, 0, 0, 0.4)
            Text {
                id: pill
                anchors.centerIn: parent
                text: root.recap && root.recap.saving && root.recs.length === 0 ? qsTr("Saving...", "meetingRecap:ka97b62m1")
                    : root.recs.length > 1 ? qsTr("%1 recordings", "meetingRecap:kc0ilq7jw").arg(root.recs.length)
                    : root.recs.length === 1 ? root.durationText(root.recs[0].duration_seconds) : ""
                font.family: theme.font; font.pixelSize: 12; color: "#FFFFFF"
            }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openRecap("recording") }
        Accessible.role: Accessible.Button
        Accessible.name: pill.text
    }
    Row {
        visible: root.recs.length > 0
        anchors { right: thumb.right; rightMargin: 5.3 }
        y: 137.3; height: 24; spacing: 4
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "clock-12"; size: 10; color: theme.textSecondary }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            readonly property var days: root.recs.length === 1 ? root.recs[0].expires_days : null
            text: days === null || days === undefined || root.recs.length > 1 ? qsTr("Set to expire", "meetingRecap:k7mpmiird")
                : qsTr("Expires in %n day(s)", "meetingRecap:kanosvkvh_mf", days)
            font.family: theme.font; font.pixelSize: 10; color: theme.textSecondary
        }
    }
}
