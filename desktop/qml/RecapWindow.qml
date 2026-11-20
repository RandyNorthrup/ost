import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtWebEngine

// Teams' intelligent recap of a meeting, which its recap card opens in a
// window of its own (measured on winpc 2026-11-20 from "Event group: OST
// TEST 217 town hall 2", 1283 x 730):
// - Teams' child-window title row (the meeting's title), then the header
//   (white, 61): a home button (20 x 24 at 20) and the title (18/24 700 at
//   60);
// - a #F5F5F5 band 48 tall: the date range (14/20 at 12) and at the right
//   Share (78 x 32), Open in Clipchamp, Copilot and More options (32 x 30:
//   Go to chat, Delete recap content);
// - on #F5F5F5, the recording's card (white, radius 8, 755.6 x 574 at 13,
//   142): its player (Microsoft's Stream player, the part Teams embeds,
//   414 tall, #242424 behind it), then the pills Speakers / Topics /
//   Chapters (31.3 tall, radius 15, 13/20; the chosen one #E8EBFA with a
//   #444791 line and #4F52B2 semibold) and the chosen one's page;
// - at the right (495.7 wide): "Shared files" (a white card, radius 8:
//   "Shared files" 14/20 600, its files as 226 x 32 chips) and a card
//   with the pills Notes, AI summary, Custom summary (New), Transcript /
//   Mentions and "+1" for the other, and the chosen one's page.
// The transcript chip opens it on Transcript, the thumbnail and View recap
// on AI summary (Teams' defaultRightTab).
Window {
    id: win
    /// The recap card's recap (api::recaps::RecapRef as JSON).
    property var recap: ({})
    /// "transcript" or "" (AI summary).
    property string startTab: ""
    property bool hasAttendance: false
    property var data_: null
    property bool loading: true
    property string rightPill: startTab === "transcript" ? "Transcript" : "AINotes"
    property string leftPill: "Speakers"
    signal goToChat()
    signal openAttendance()
    signal toast(var d)
    title: recap.subject || ""
    width: 1283; height: 730
    color: theme.surface
    readonly property string tag: "recap" + Math.floor(Math.random() * 1e9) + ":"

    Component.onCompleted: backend.eventsRequest("recapOpen", tag + "open", JSON.stringify({ recap: win.recap }))
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id.indexOf(win.tag) !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            const what = id.slice(win.tag.length)
            if (what === "open") {
                win.loading = false
                if (v.error) { console.warn("RECAP open failed", v.error); return }
                win.data_ = v
                if (v.recap) win.recap = v.recap
                console.info("RECAP open", !!v.player, (v.transcript || []).length, v.recap ? v.recap.thread_id : "")
            }
        }
    }
    function dateRange() {
        const a = new Date(recap.start_ms || 0), b = new Date(recap.end_ms || 0)
        if (!recap.start_ms) return ""
        const loc = Qt.locale()
        const first = a.toLocaleDateString(loc, "dddd, MMMM d, yyyy") + " " + theme.time(a)
        const same = a.toDateString() === b.toDateString()
        return qsTr("%1 - %2", "calendar:k6vk7q5v3").arg(first).arg((same ? "" : b.toLocaleDateString(loc, "dddd, MMMM d") + " ") + theme.time(b))
    }

    ChildWindowTitleBar { id: titleRow; title: win.title }

    // Header.
    Rectangle {
        id: header
        y: titleRow.height; width: parent.width; height: 61
        color: theme.surface
        IconBtn { x: 20; y: 18.2; width: 20; height: 24; icon: "home-20"; tip: qsTr("Meeting Recaps"); onClicked: win.goToChat() }
        Text {
            x: 60; y: 17.2; width: parent.width - 80
            elide: Text.ElideRight
            text: win.recap.subject || ""
            lineHeight: 24; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
    }
    Rectangle {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        color: theme.pick("#F5F5F5", "#141414", "#000000")
        // The band.
        Text {
            x: 12; y: 14; text: win.dateRange()
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Row {
            anchors { right: parent.right; rightMargin: 20 }
            y: 8; spacing: 0
            BandButton { icon: "share-20"; label: qsTr("Share"); onClicked: shareMenu.popup(this, 0, height + 4) }
            BandButton { visible: false; icon: "open-20"; label: qsTr("Open in Clipchamp") }
            IconBtn { y: 1; width: 32; height: 30; icon: "more-horizontal-20"; tip: qsTr("More options"); onClicked: moreMenu.popup(this, width - moreMenu.width, height + 4) }
        }
        Menu {
            id: shareMenu
            MenuItem { text: qsTr("Share recap access"); onTriggered: shareDialog.openFor(win.recap) }
            MenuItem {
                text: qsTr("Copy link")
                onTriggered: shareDialog.copyLink(win.recap)
            }
        }
        Menu {
            id: moreMenu
            MenuItem { text: qsTr("Go to chat"); onTriggered: { win.goToChat(); win.close() } }
        }

        // The recording's card.
        Rectangle {
            id: left
            x: 13; y: 49; width: Math.max(320, parent.width - 13 - 507.7 - 13); height: parent.height - y - 14
            radius: 8; color: theme.surface; clip: true
            Rectangle {
                id: player
                width: parent.width; height: Math.min(414, parent.height - 160)
                topLeftRadius: 8; topRightRadius: 8
                color: "#242424"
                WebEngineView {
                    id: playerView
                    anchors.fill: parent
                    visible: !!win.data_ && !!win.data_.player
                    url: win.data_ && win.data_.player ? win.data_.player : ""
                    settings.javascriptCanOpenWindows: false
                    settings.localContentCanAccessRemoteUrls: false
                    onNewWindowRequested: req => { const u = req.requestedUrl.toString(); if (u.indexOf("https://") === 0) Qt.openUrlExternally(u) }
                    Component.onCompleted: profile = webAppsProfile.instance()
                }
                BusyIndicator { anchors.centerIn: parent; running: win.loading; visible: running }
            }
            Row {
                x: 12; y: player.height + 12.3; spacing: 8
                Repeater {
                    model: [{ k: "Speakers", t: qsTr("Speakers") }, { k: "Topics", t: qsTr("Topics") }, { k: "Chapters", t: qsTr("Chapters") }]
                    Pill { required property var modelData; label: modelData.t; chosen: win.leftPill === modelData.k; onClicked: win.leftPill = modelData.k }
                }
            }
            Text {
                visible: win.leftPill === "Speakers"
                anchors.horizontalCenter: parent.horizontalCenter; y: player.height + 90
                text: qsTr("Speaker info isn't available for this meeting.")
                lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
            }
            // Topics and Chapters (AI): Teams' words when it has none, with
            // its Learn more.
            Column {
                visible: win.leftPill !== "Speakers"
                anchors.horizontalCenter: parent.horizontalCenter; y: player.height + 90
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.leftPill === "Topics" ? qsTr("Topics aren't available for this meeting") : qsTr("Chapters aren't available for this meeting")
                    lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.StyledText
                    text: (win.leftPill === "Topics" ? qsTr("In some situations, AI isn't able to generate topics.") : qsTr("In some situations, AI isn't able to generate chapters."))
                          + " <a href=\"https://support.microsoft.com/office/meeting-recap-in-microsoft-teams-c2e3a0fe-504f-4b2c-bf85-504938f110ef\" style=\"color:" + theme.brandForeground1 + "; text-decoration:none\">" + qsTr("Learn more") + "</a>"
                    lineHeight: 28; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }
        }

        // Shared files and the right-hand pills.
        Rectangle {
            id: files
            x: left.x + left.width + 7.6; y: 49; width: parent.width - x - 13; height: 89.3
            radius: 8; color: theme.surface
            border.color: theme.pick(Qt.rgba(0, 0, 0, 0.05), "#333333", "#FFFFFF"); border.width: 0.67
            Text {
                x: 15.7; y: 12.7; text: qsTr("Shared files")
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                Accessible.role: Accessible.Heading; Accessible.name: text
            }
            Rectangle {
                visible: win.hasAttendance
                x: 15.7; y: 42.7; width: 226.2; height: 32; radius: 4
                color: attHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.pick("#F0F0F0", "#333333", "#FFFFFF"); border.width: 0.67
                FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "people-list-20"; size: 20; color: theme.brand }
                Text { x: 44.6; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Attendance"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                HoverHandler { id: attHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.openAttendance() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Attendance")
            }
        }
        Rectangle {
            id: right
            x: files.x; y: files.y + files.height + 8; width: files.width; height: parent.height - y - 14
            radius: 8; color: theme.surface; clip: true
            border.color: theme.pick(Qt.rgba(0, 0, 0, 0.05), "#333333", "#FFFFFF"); border.width: 0.67
            // Teams shows four pills and puts the fifth under "+1"
            // (Transcript or Mentions, whichever isn't chosen).
            readonly property var all: [
                { k: "Notes", t: qsTr("Notes") }, { k: "AINotes", t: qsTr("AI summary") }, { k: "CustomSummary", t: qsTr("Custom summary"), isNew: true },
                { k: "Transcript", t: qsTr("Transcript") }, { k: "Mentions", t: qsTr("Mentions") }]
            readonly property string fourth: win.rightPill === "Mentions" ? "Mentions" : "Transcript"
            readonly property var shown: all.filter(p => p.k !== (fourth === "Transcript" ? "Mentions" : "Transcript"))
            readonly property var hidden: all.filter(p => shown.indexOf(p) < 0)
            Row {
                x: 12; y: 12.7; spacing: 8
                Repeater {
                    model: right.shown
                    Pill { required property var modelData; label: modelData.t; isNew: !!modelData.isNew; chosen: win.rightPill === modelData.k; onClicked: win.rightPill = modelData.k }
                }
            }
            Pill {
                anchors { right: parent.right; rightMargin: 3 }
                y: 12.7; label: qsTr("+%1").arg(right.hidden.length); chevron: true
                onClicked: overflow.popup(this, 0, height + 4)
            }
            Menu {
                id: overflow
                Repeater {
                    model: right.hidden
                    MenuItem { required property var modelData; text: modelData.t; onTriggered: win.rightPill = modelData.k }
                }
            }
            Rectangle { y: 52.7; width: parent.width; height: 0.67; color: theme.divider }
            // AI summary (Teams' empty sections).
            Column {
                visible: win.rightPill === "AINotes"
                x: 20.7; y: 67.7; width: parent.width - 41.4; spacing: 0
                Row {
                    width: parent.width
                    Text { width: parent.width - 24; text: qsTr("AI-generated content may be incorrect"); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                }
                Item { width: 1; height: 42 }
                Text { text: qsTr("Meeting notes"); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 11.6 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("We didn't find any notes for this meeting."); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Item { width: 1; height: 45.6 }
                Text { text: qsTr("Follow-up tasks"); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 21.7 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("We didn't find any tasks for this meeting."); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            // Notes (the meeting's notes): Teams' invitation to add them.
            Column {
                visible: win.rightPill === "Notes"
                anchors.horizontalCenter: parent.horizontalCenter; y: 92.4
                width: parent.width - 48
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 192; height: 192; sourceSize: Qt.size(384, 384)
                    source: "../assets/illustrations/meeting-notes" + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                }
                Item { width: 1; height: 24 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Add meeting notes for everyone"); lineHeight: 22.86; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 8 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: qsTr("Anyone can contribute to the notes, anytime."); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            // Transcript: its entries, or Teams' empty page.
            ListView {
                id: transcriptList
                visible: win.rightPill === "Transcript" && count > 0
                x: 12; y: 64; width: parent.width - 24; height: parent.height - y - 48
                clip: true; spacing: 12
                model: win.data_ ? win.data_.transcript : []
                delegate: Column {
                    required property var modelData
                    width: transcriptList.width
                    Text { text: modelData.speaker || ""; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: modelData.text || ""; lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                }
            }
            Column {
                visible: win.rightPill === "Transcript" && !win.loading && transcriptList.count === 0
                anchors.horizontalCenter: parent.horizontalCenter; y: 140
                width: Math.min(parent.width - 48, 420)
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 128; height: 128; sourceSize: Qt.size(256, 256)
                    source: "../assets/illustrations/meeting-notes" + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                }
                Item { width: 1; height: 24 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("No transcript available"); lineHeight: 22.86; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 8 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: qsTr("The transcript for this meeting was never created, has expired, or has been deleted."); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Row {
                visible: win.rightPill === "Transcript"
                anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 0 }
                height: 31.3
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Is this transcript useful?"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                IconBtn { width: 32; height: 31.3; icon: "copilot-like-20"; tip: qsTr("Useful") }
                IconBtn { width: 32; height: 31.3; icon: "copilot-dislike-20"; tip: qsTr("Not useful") }
            }
        }
    }

    RecapShareDialog { id: shareDialog }

    component IconBtn: Rectangle {
        id: ib
        property string icon
        property string tip
        signal clicked()
        radius: 4
        color: ibh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: 20; color: theme.onFill(ib, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        ToolTip.visible: ibh.hovered && !!tip
        ToolTip.text: tip
        ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
    component BandButton: Rectangle {
        id: bb
        property string icon
        property string label
        signal clicked()
        height: 32; width: bbRow.implicitWidth + 24; radius: 4
        color: bbh.hovered ? theme.rowHover : "transparent"
        Row {
            id: bbRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: bb.icon; size: 20; color: theme.onFill(bb, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: bb.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(bb, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        }
        HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }
    component Pill: Rectangle {
        id: pill
        property string label
        property bool chosen: false
        property bool isNew: false
        property bool chevron: false
        signal clicked()
        height: 31.3; radius: 15
        width: pillRow.implicitWidth + 21.4
        color: chosen ? theme.pick("#E8EBFA", "#2F2F4A", "#000000") : (ph.hovered ? theme.rowHover : theme.surface)
        border.width: 0.67
        border.color: chosen ? theme.pick("#444791", "#7F85F5", "#FFFF00") : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Row {
            id: pillRow
            anchors.centerIn: parent; spacing: 4
            Text { anchors.verticalCenter: parent.verticalCenter; text: pill.label; font.family: theme.font; font.pixelSize: 13; font.weight: pill.chosen ? Font.DemiBold : Font.Normal; color: pill.chosen ? theme.pick("#4F52B2", "#A6A7DC", "#FFFF00") : theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
            Rectangle {
                visible: pill.isNew
                anchors.verticalCenter: parent.verticalCenter
                width: 32.6; height: 20; radius: 10; color: theme.pick("#5B5FC7", "#7F85F5", "#FFFF00")
                Text { anchors.centerIn: parent; text: qsTr("New"); font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: "#FFFFFF" }
            }
            FluentIcon { visible: pill.chevron; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
        }
        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    function stateForTest() { return JSON.stringify({ loading: win.loading, pill: win.rightPill, player: !!(win.data_ && win.data_.player), transcript: win.data_ ? (win.data_.transcript || []).length : -1, thread: win.recap.thread_id || "", link: win.data_ ? win.data_.link : "" }) }
    function shareDialogForTest() { return shareDialog }
}
