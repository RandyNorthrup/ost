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

    // The extras (Teams 991291): Open in Clipchamp's address, Manage's
    // download and expiration, whether Copilot is offered; Mentions,
    // Custom summary and Notes' Add notes load when their page opens.
    property var extras: null
    property var mentions: null
    property var templates: null
    property string summaryKey: ""
    property string summaryTemplateId: ""
    property string summaryText: ""
    property string summaryState: ""
    property string notesUrl: ""
    property string notesState: ""
    property bool copilotOpen: false
    property var copilotLaunch: null
    readonly property string hostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    Component.onCompleted: {
        backend.eventsRequest("recapOpen", tag + "open", JSON.stringify({ recap: win.recap }))
        backend.eventsRequest("recapExtras", tag + "extras", JSON.stringify({ recap: win.recap }))
    }
    onRightPillChanged: {
        if (rightPill === "Mentions" && mentions === null) backend.eventsRequest("recapMentions", tag + "mentions", JSON.stringify({ recap: win.recap }))
        if (rightPill === "CustomSummary" && templates === null) backend.eventsRequest("recapTemplates", tag + "templates", "{}")
    }
    function summarize(key, template) {
        summaryKey = key; summaryText = ""; summaryState = "generating"
        backend.eventsRequest("recapSummary", tag + "summary", JSON.stringify({ recap: win.recap, key: key, template: template || "" }))
    }
    function toggleCopilot() {
        copilotOpen = !copilotOpen
        if (copilotOpen && !copilotLaunch) backend.eventsRequest("recapCopilot", tag + "copilot", JSON.stringify({ recap: win.recap, theme: win.hostTheme }))
    }
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
            } else if (what === "extras") {
                if (!v.error) win.extras = v
                console.info("RECAP extras", v.error || "", v.clipchamp ? "clipchamp" : "", v.remainingDays, v.copilot)
            } else if (what === "mentions") {
                win.mentions = v.error ? { error: v.error, items: [], count: 0 } : v
                console.info("RECAP mentions", v.error || "", v.count)
            } else if (what === "templates") {
                win.templates = v.templates || []
            } else if (what === "summary") {
                win.summaryText = v.text || ""; win.summaryState = v.error ? "error" : "done"
                console.info("RECAP summary", v.error || "", (v.text || "").length)
            } else if (what === "notes") {
                win.notesUrl = v.url || ""; win.notesState = v.error ? "error" : "ready"
                console.info("RECAP notes", v.error || "", !!v.url)
            } else if (what === "copilot") {
                win.copilotLaunch = v.error ? null : v
                console.info("RECAP copilot", v.error || "ready")
            } else if (what === "expiry") {
                if (!v.error) backend.eventsRequest("recapExtras", win.tag + "extras", JSON.stringify({ recap: win.recap }))
                backend.toast(v.error ? qsTr("Failed to update expiration date. Please try again.") : qsTr("Expiration date updated successfully."), v.error ? "error" : "success")
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
            // Teams' "Open in Clipchamp" (MeetingRecap.enableOpenInClipchamp's
            // label for Watch in browser): the recording's web page.
            BandButton { visible: !!win.extras && !!win.extras.clipchamp; icon: "open-20"; label: qsTr("Open in Clipchamp"); onClicked: Qt.openUrlExternally(win.extras.clipchamp) }
            // Copilot (licensed users): the Copilot pane over the right side.
            BandButton {
                visible: !!win.extras && win.extras.copilot
                icon: "copilot-16"; label: qsTr("Copilot")
                onClicked: win.toggleCopilot()
                ToolTip.visible: bbHoverCopilot.hovered; ToolTip.text: win.copilotOpen ? qsTr("Close Copilot") : qsTr("Open Copilot"); ToolTip.delay: 500
                HoverHandler { id: bbHoverCopilot }
            }
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
                // Teams' Manage (RecapOnePlayerManageButton) over the
                // player's corner: Download, and for an editor Expires in
                // {n} days ▸ Extend by 60 days / Remove expiration.
                Rectangle {
                    id: manageBtn
                    visible: !!win.extras && !!win.data_ && !!win.data_.player
                    anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                    width: manageRow.implicitWidth + 24; height: 31.3; radius: 4
                    border.color: Qt.rgba(1, 1, 1, 0.2); border.width: 0.67
                    color: manageHover.hovered ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.6)
                    Row {
                        id: manageRow
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "settings-20"; size: 20; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Manage"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: "white" }
                    }
                    HoverHandler { id: manageHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: manageMenu.open() }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Manage")
                }
                // Teams' Manage menu: dark, over the player (Download; Expires
                // in {n} days ▸ Extend by 60 days / Remove expiration).
                MenuPopup {
                    id: manageMenu
                    parent: manageBtn
                    darkCallout: true
                    x: manageBtn.width - implicitWidth; y: manageBtn.height + 8
                    readonly property int days: win.extras ? win.extras.remainingDays : -1
                    items: [{ key: "download", label: qsTr("Download"), icon: "arrow-download-20" }].concat(
                        days >= 0 && win.extras.file.canEdit ? [{ key: "expiry", icon: "clock-20",
                            label: qsTr("Expires in %n days", "", days),
                            submenu: [{ label: qsTr("Extend by 60 days"), key: "extend" }, { label: qsTr("Remove expiration"), key: "remove" }] }] : [])
                    onPicked: i => { if (items[i].key === "download") backend.driveDownload(JSON.stringify({ id: win.recap.item_id, drive_id: win.recap.drive_id, name: win.extras.file.name || "" })) }
                    onSubPicked: (i, j) => {
                        const k = items[i].submenu[j].key
                        backend.eventsRequest("recapExpiry", win.tag + "expiry", JSON.stringify(k === "remove"
                            ? { site: win.extras.file.site, path: win.extras.file.path, remove: true }
                            : { site: win.extras.file.site, path: win.extras.file.path, expiration: win.extras.file.expiration }))
                    }
                }
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
            // Teams: Transcript fourth when opened on it (the transcript
            // chip), otherwise Mentions; the other under "+1".
            property string fourth: win.startTab === "transcript" ? "Transcript" : "Mentions"
            Connections { target: win; function onRightPillChanged() { if (win.rightPill === "Transcript" || win.rightPill === "Mentions") right.fourth = win.rightPill } }
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
            // Notes (the meeting's notes): Teams' invitation to add them;
            // Add notes makes them (Teams' meeting-notes service) and shows
            // the Loop notes here.
            Loader {
                active: win.rightPill === "Notes" && win.notesUrl !== ""
                x: 1; y: 53.4; width: parent.width - 2; height: parent.height - y - 1
                sourceComponent: LoopPage { kind: "meetingNotes"; title: win.recap.subject || ""; componentUrl: win.notesUrl }
            }
            Column {
                visible: win.rightPill === "Notes" && win.notesUrl === ""
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
                Item { width: 1; height: 20 }
                Rectangle {
                    id: addNotes
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Teams' outlined Add notes (124.4 x 31.3): the 20 px
                    // Loop icon and the label 14/600.
                    width: addNotesRow.implicitWidth + 24; height: 31.3; radius: 4
                    color: addNotesHover.hovered ? theme.rowHover : theme.surface
                    border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
                    opacity: win.notesState === "making" ? 0.5 : 1
                    Row {
                        id: addNotesRow
                        anchors.centerIn: parent; spacing: 6
                        Image { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "../assets/icons/ft-loop-20.svg" }
                        Text { id: addNotesText; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add notes"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(addNotes, theme.text) }
                    }
                    HoverHandler { id: addNotesHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: win.notesState !== "making"
                        onTapped: { win.notesState = "making"; backend.eventsRequest("recapNotes", win.tag + "notes", JSON.stringify({ recap: win.recap })) }
                    }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Add notes")
                }
                Item { width: 1; height: 12 }
                Text {
                    visible: win.notesState === "error"
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: qsTr("Something went wrong. Try again.")
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                }
            }
            // Mentions (Teams' recap Mentions: the catch-up service's
            // mentions of you, or its empty pages).
            ListView {
                id: mentionList
                visible: win.rightPill === "Mentions" && count > 0
                x: 12; y: 64; width: parent.width - 24; height: parent.height - y - 12
                clip: true; spacing: 16
                model: win.mentions ? win.mentions.items : []
                delegate: Item {
                    required property var modelData
                    width: mentionList.width; height: mCol.implicitHeight
                    Avatar { x: 0; y: 0; size: 32; name: modelData.speaker || "?"; photoId: modelData.speakerId ? "8:orgid:" + modelData.speakerId : "" }
                    Column {
                        id: mCol
                        x: 44; width: parent.width - 44; spacing: 4
                        Row {
                            spacing: 4
                            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "mention-16"; size: 16; color: theme.brand }
                            Text {
                                textFormat: Text.StyledText
                                text: "<b>" + String(modelData.speaker || "").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b> " + qsTr("mentioned you")
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap; textFormat: Text.StyledText
                            readonly property string raw: String(modelData.text || "")
                            text: {
                                const t = raw, a = modelData.nameStart, n = modelData.nameLength
                                const e = x => x.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                if (a >= 0 && n > 0 && a + n <= t.length) return e(t.slice(0, a)) + "<b>" + e(t.slice(a, a + n)) + "</b>" + e(t.slice(a + n))
                                return e(t)
                            }
                            lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                        }
                    }
                }
            }
            Column {
                visible: win.rightPill === "Mentions" && mentionList.count === 0
                anchors.horizontalCenter: parent.horizontalCenter; y: 140
                width: Math.min(parent.width - 48, 420)
                BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: win.mentions === null; visible: running; width: 32; height: 32 }
                Image {
                    visible: !!win.mentions && !!win.mentions.error
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 192; height: 192; sourceSize: Qt.size(384, 384)
                    source: "../assets/illustrations/warning" + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                }
                Item { visible: !!win.mentions && !!win.mentions.error; width: 1; height: 24 }
                Text {
                    visible: win.mentions !== null
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    // No transcript: "Know if your name came up"; nothing
                    // found: "We didn't find mentions of you"; an error: "We
                    // couldn't load mentions".
                    text: !win.mentions ? "" : win.mentions.error ? qsTr("We couldn't load mentions")
                        : (win.data_ && (win.data_.transcript || []).length === 0 && !win.mentions.found) ? qsTr("Know if your name came up") : qsTr("We didn't find mentions of you")
                    lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                }
                Item { width: 1; height: 8 }
                Text {
                    visible: !!win.mentions && !!win.mentions.error
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Something went wrong. Try again.")
                    lineHeight: 28; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                Text {
                    visible: !!win.mentions && !win.mentions.error && win.data_ && (win.data_.transcript || []).length === 0 && !win.mentions.found
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: qsTr("Turn on recording and transcription, and AI will find mentions of you in the transcript.")
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
            }
            // Custom summary (Teams' customize-notes panel): the template
            // cards (Speaker summary, Executive report, Project update and
            // yours), then the summary Copilot writes in that format.
            Item {
                visible: win.rightPill === "CustomSummary"
                x: 12; y: 64; width: parent.width - 24; height: parent.height - y - 12
                // Teams' template cards (customize-notes panel, measured on
                // winpc): a page of 4 (948 wide or more), 3 (480-947) or 2
                // cards, 50.7 tall, 8 apart, the title 14/600; Create template
                // first; Next / Previous templates (25 x 25) when there are
                // more.
                Item {
                    id: cards
                    width: parent.width; height: 50.7
                    readonly property var all: [
                        { key: "Create", t: qsTr("Create template"), create: true },
                        { key: "SpeakersBasedRecap", t: qsTr("Speaker summary"), d: qsTr("Main points by speaker") },
                        { key: "ExecutiveSummary", t: qsTr("Executive report"), d: qsTr("Overview and key area updates") },
                        { key: "ProjectSummary", t: qsTr("Project update"), d: qsTr("Accomplishments, risks, and action items") }
                    ].concat((win.templates || []).map(x => ({ key: "SavedTemplate:" + x.id, t: x.name, d: qsTr("Created by you"), template: x.template })))
                    readonly property int perPage: width >= 948 ? 4 : width >= 480 ? 3 : 2
                    property int page: 0
                    readonly property int pages: Math.ceil(all.length / perPage)
                    readonly property real cardWidth: (width - 8 * (perPage - 1)) / perPage
                    Row {
                        spacing: 8
                        Repeater {
                            model: cards.all.slice(cards.page * cards.perPage, (cards.page + 1) * cards.perPage)
                            Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool chosen: win.summaryKey === modelData.key || (!!modelData.template && win.summaryKey === "SavedTemplate" && win.summaryTemplateId === modelData.key)
                                width: cards.cardWidth; height: 50.7; radius: 4
                                color: cardHover.hovered ? theme.rowHover : theme.surface
                                border.color: chosen ? theme.brand : "transparent"; border.width: chosen ? 1.33 : 0
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 4 }
                                Row {
                                    x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    FluentIcon { visible: !!card.modelData.create; anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: theme.onFill(card, theme.text) }
                                    Text { width: card.width - 32 - (card.modelData.create ? 28 : 0); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: card.modelData.t; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(card, theme.text) }
                                }
                                HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (card.modelData.create) return
                                        if (card.modelData.template) { win.summaryTemplateId = card.modelData.key; win.summarize("SavedTemplate", JSON.stringify(card.modelData.template)) }
                                        else win.summarize(card.modelData.key, "")
                                    }
                                }
                                ToolTip.visible: cardHover.hovered && !!card.modelData.d
                                ToolTip.text: card.modelData.d || ""
                                ToolTip.delay: 500
                                Accessible.role: Accessible.Button; Accessible.name: modelData.t
                            }
                        }
                    }
                    IconBtn { visible: cards.page > 0; x: -12; y: 12.8; width: 25; height: 25; icon: "chevron-left-20"; tip: qsTr("Previous templates"); onClicked: cards.page-- }
                    IconBtn { visible: cards.page < cards.pages - 1; x: cards.width - 13; y: 12.8; width: 25; height: 25; icon: "chevron-right-20"; tip: qsTr("Next templates"); onClicked: cards.page++ }
                }
                Flickable {
                    y: cards.height + 16; width: parent.width; height: parent.height - y
                    contentHeight: sumCol.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: sumCol
                        width: parent.width; spacing: 8
                        Item { visible: win.summaryState === ""; width: 1; height: 36 }
                        Image {
                            visible: win.summaryState === ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 192; height: 192; sourceSize: Qt.size(384, 384)
                            source: "../assets/illustrations/meeting-notes" + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                        }
                        Text {
                            visible: win.summaryState === ""
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 16
                            text: qsTr("Pick a template or create your own")
                            lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                        }
                        Row {
                            visible: win.summaryState === "generating"
                            anchors.horizontalCenter: parent.horizontalCenter; spacing: 8; topPadding: 40
                            BusyIndicator { running: parent.visible; width: 24; height: 24 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Generating your summary..."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                        Column {
                            visible: win.summaryState === "error"
                            width: parent.width; topPadding: 40; spacing: 8
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("We couldn't load custom AI summary"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Something went wrong. Try again."); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                        Text { visible: win.summaryState === "done"; text: qsTr("AI-generated content may be incorrect"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        Text {
                            visible: win.summaryState === "done"
                            width: parent.width; wrapMode: Text.Wrap; textFormat: Text.MarkdownText
                            text: win.summaryText
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            onLinkActivated: link => { if (link.indexOf("https://") === 0) Qt.openUrlExternally(link) }
                        }
                        Rectangle {
                            id: copyAll
                            visible: win.summaryState === "done"
                            width: copyRow.implicitWidth + 16; height: 32; radius: 4
                            color: copyHover.hovered ? theme.rowHover : "transparent"
                            Row { id: copyRow; anchors.centerIn: parent; spacing: 6
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "copy-20"; size: 20; color: theme.onFill(copyAll, theme.textStrong) }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Copy all"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(copyAll, theme.textStrong) }
                            }
                            HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.copyText(win.summaryText) }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Copy all")
                        }
                    }
                }
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

    // Copilot (the band's button): the Microsoft 365 Copilot app in the
    // recap's right-hand pane (Teams' meetingcollaboration info pane).
    Rectangle {
        id: copilotPane
        visible: win.copilotOpen
        x: files.x; y: header.y + header.height + files.y; width: files.width; height: win.height - y - 14
        radius: 8; color: theme.surface; clip: true
        border.color: theme.pick(Qt.rgba(0, 0, 0, 0.05), "#333333", "#FFFFFF"); border.width: 0.67
        Rectangle {
            id: copilotHeader
            width: parent.width; height: 44; color: "transparent"
            FluentIcon { x: 16; y: 12; size: 20; name: "copilot-color-48"; color: theme.text }
            Text { x: 44; y: 12; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Copilot"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            IconBtn { x: parent.width - 44; y: 6; width: 32; height: 31.3; icon: "dismiss-20"; tip: qsTr("Close Copilot"); onClicked: win.copilotOpen = false }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
        }
        BusyIndicator { anchors.centerIn: parent; running: win.copilotOpen && !win.copilotLaunch; visible: running }
        Loader {
            anchors { top: copilotHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
            active: win.copilotOpen && !!win.copilotLaunch
            sourceComponent: WebApp {
                showHeader: false; teamsHost: true; deepNaa: true
                appName: "Copilot"; appId: "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162"
                frameContext: "sidePanel"
                ssr: true
                runtimeSupports: ({ appPerformanceMetrics: {}, copilot: { eligibility: {} }, mouseRelay: {} })
                hostThread: win.recap.thread_id || ""
                hostContext: win.copilotLaunch.context
                home: win.copilotLaunch.url
                onHostEvent: (name, json) => {
                    if (name === "ChatReady") {
                        sendFrameMessage("contextualChatChanged", [win.copilotLaunch.contextualChat])
                        sendFrameMessage("updateCapabilities", [win.copilotLaunch.capabilities])
                    }
                }
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

    function pillForTest(k) { win.rightPill = k }
    function summarizeForTest(k) { win.summarize(k, "") }
    function copilotForTest() { win.toggleCopilot() }
    function manageForTest() { manageMenu.open() }
    function extrasForTest() { return JSON.stringify({ extras: win.extras, mentions: win.mentions, summary: win.summaryState, summaryLen: win.summaryText.length, notes: win.notesState, copilot: !!win.copilotLaunch }) }
    function stateForTest() { return JSON.stringify({ loading: win.loading, pill: win.rightPill, player: !!(win.data_ && win.data_.player), transcript: win.data_ ? (win.data_.transcript || []).length : -1, thread: win.recap.thread_id || "", link: win.data_ ? win.data_.link : "" }) }
    function shareDialogForTest() { return shareDialog }
}
