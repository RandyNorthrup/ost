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
    /// AI summary's notes and tasks ({notes, tasks}); null until loaded.
    property var aiNotes: null
    function loadAiNotes() { backend.eventsRequest("recapAINotes", tag + "ainotes", JSON.stringify({ recap: win.recap })) }
    function escapeHtml(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    /// Your Custom summary templates ({id, name}, newest first); null
    /// until they've come.
    property var templates: null
    /// The chosen template: a built-in's key or one of yours (its item id,
    /// `summaryOdb`).
    property string summaryKey: ""
    property bool summaryOdb: false
    /// Teams moves the remembered template to the front when the cards
    /// first show.
    property string frontKey: ""
    /// ECS meetingRecap: Project update hidden, Create template offered.
    property bool hideProjectUpdate: false
    property bool createTemplate: true
    property string menuFor: ""
    property string lastShared: ""
    property string summaryText: ""
    property string summaryState: ""
    property string notesUrl: ""
    property string notesState: ""
    property bool copilotOpen: false
    property var copilotLaunch: null
    readonly property string hostTheme: theme.highContrast ? "contrast" : theme.dark ? "dark" : "default"
    // A recording-less recap (Teams' ODSPTranscript: only a transcript)
    // has no recording card; its file is known once the meeting is read.
    readonly property bool recording: !data_ || data_.recording !== false
    /// The Audio recap mini player, while one is open.
    property var audioPlayer: null
    Component.onCompleted: {
        backend.eventsRequest("recapOpen", tag + "open", JSON.stringify({ recap: win.recap }))
        if (win.recap.item_id) backend.eventsRequest("recapExtras", tag + "extras", JSON.stringify({ recap: win.recap }))
    }
    // Audio recap: Teams' mini player pops out at once ("Generating..."),
    // then plays the audio recap or says why there isn't one.
    function openAudioRecap() {
        if (!audioPlayer) {
            audioPlayer = audioPlayerComponent.createObject(null, { subject: win.recap.subject || "" })
            audioPlayer.closing.connect(() => { win.audioPlayer = null })
            audioPlayer.x = win.x + Math.round((win.width - audioPlayer.width) / 2) + 200
            audioPlayer.y = win.y + Math.round((win.height - audioPlayer.height) / 2) - 80
        }
        audioPlayer.state_ = "generating"
        audioPlayer.show(); audioPlayer.raise()
        backend.eventsRequest("recapAudio", tag + "audio", JSON.stringify({ recap: win.recap }))
        console.info("RECAP audio requested")
    }
    Component { id: audioPlayerComponent; AudioRecapPlayer {} }
    onRightPillChanged: {
        if (rightPill === "Mentions" && mentions === null) backend.eventsRequest("recapMentions", tag + "mentions", JSON.stringify({ recap: win.recap }))
        if (rightPill === "CustomSummary" && templates === null) loadTemplates()
        if (rightPill === "AINotes" && aiNotes === null && !loading) loadAiNotes()
    }
    // Custom summary's chosen template, kept per meeting chat as Teams
    // keeps it (its localStorage[threadId] = {key, isOdbTemplate}): here a
    // device-local setting.
    readonly property string memoryKey: "recapCustomSummaryTemplates"
    function remembered() {
        try { return (JSON.parse(backend.setting(memoryKey) || "{}") || {})[recap.thread_id || ""] || null } catch (e) { return null }
    }
    function remember(v) {
        let m = {}
        try { m = JSON.parse(backend.setting(memoryKey) || "{}") || {} } catch (e) {}
        if (v) m[recap.thread_id || ""] = v
        else delete m[recap.thread_id || ""]
        backend.setSetting(memoryKey, JSON.stringify(m))
    }
    readonly property var builtInKeys: hideProjectUpdate ? ["SpeakersBasedRecap", "ExecutiveSummary"] : ["SpeakersBasedRecap", "ExecutiveSummary", "ProjectSummary"]
    /// Pick a template (a card, or a template just saved): remembered, and
    /// its summary asked for.
    function choose(key, odb) {
        remember({ key: key, isOdbTemplate: odb })
        summarize(key, odb)
    }
    function summarize(key, odb) {
        summaryKey = key; summaryOdb = !!odb; summaryText = ""; summaryState = "generating"
        backend.eventsRequest("recapSummary", tag + "summary", JSON.stringify(odb ? { recap: win.recap, templateId: key } : { recap: win.recap, key: key }))
    }
    function loadTemplates() { backend.eventsRequest("recapTemplates", tag + "templates", "{}") }
    // A template's menu: Edit, Share (copy its text), Rename, Delete.
    function templateAction(action, id, name) {
        console.info("RECAP template", action, id)
        if (action === "edit") templateEditor.openEdit(id, name, win.templates || [])
        else if (action === "share") backend.eventsRequest("recapTemplateContent", tag + "share", JSON.stringify({ id: id }))
        else if (action === "rename") { renameDialog.renaming = id; renameDialog.openFor(name, win.templates || []) }
        else if (action === "delete") backend.eventsRequest("recapTemplateDelete", tag + "delete:" + id, JSON.stringify({ id: id }))
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
                // The meeting's notes, when made: Notes shows them.
                if (v.notesUrl && !win.notesUrl) { win.notesUrl = v.notesUrl; win.notesState = "ready" }
                // The file is known now (a transcript-only recap's comes
                // from the meeting's artifacts).
                if (!win.extras && win.recap.item_id) backend.eventsRequest("recapExtras", win.tag + "extras", JSON.stringify({ recap: win.recap }))
                if (win.rightPill === "AINotes" && win.aiNotes === null) win.loadAiNotes()
                console.info("RECAP open", !!v.player, (v.transcript || []).length, v.recap ? v.recap.thread_id : "")
            } else if (what === "extras") {
                if (!v.error) win.extras = v
                console.info("RECAP extras", v.error || "", v.clipchamp ? "clipchamp" : "", v.remainingDays, v.copilot)
            } else if (what === "ainotes") {
                win.aiNotes = v.error ? { error: v.error, notes: [], tasks: [] } : v
                console.info("RECAP ainotes", v.error || "", (v.notes || []).length, (v.tasks || []).length, v.notesState || "", v.tasksState || "")
            } else if (what === "mentions") {
                win.mentions = v.error ? { error: v.error, items: [], count: 0 } : v
                console.info("RECAP mentions", v.error || "", v.count)
            } else if (what === "templates") {
                const first = win.templates === null
                win.frontKey = ""
                win.hideProjectUpdate = !!v.hideProjectUpdate
                win.createTemplate = v.createTemplate !== false
                win.templates = v.templates || []
                console.info("RECAP templates", v.error || "", win.templates.length)
                // The remembered template, when it's still there: first in
                // the row, and its summary.
                const m = first ? win.remembered() : null
                if (m && m.key && (win.builtInKeys.indexOf(m.key) >= 0 || (m.isOdbTemplate && win.templates.some(x => x.id === m.key)))) {
                    win.frontKey = m.key
                    if (win.summaryKey !== m.key) win.summarize(m.key, !!m.isOdbTemplate)
                }
            } else if (what === "share") {
                // Share: the template's text copied (Teams' toast either way).
                if (v.content) { backend.copyText(v.content); win.lastShared = v.content }
                win.toast({ text: v.content ? qsTr("Prompt copied") : qsTr("Failed to copy. Please try again."), intent: v.content ? "success" : "error" })
                console.info("RECAP template shared", v.error || "", (v.content || "").length)
            } else if (what.indexOf("rename:") === 0) {
                const id = what.slice(7)
                if (v.error) { console.warn("RECAP template rename failed", v.error); return }
                win.templates = (win.templates || []).map(x => x.id === id ? { id: x.id, name: renameDialog.lastName } : x)
                console.info("RECAP template renamed", id)
            } else if (what.indexOf("delete:") === 0) {
                const id = what.slice(7)
                if (v.error) { console.warn("RECAP template delete failed", v.error); return }
                console.info("RECAP template deleted", id)
                win.loadTemplates()
                if (win.summaryKey === id) {
                    const m = win.remembered()
                    if (m && m.key === id) win.remember(null)
                    win.summaryKey = ""; win.summaryOdb = false; win.summaryText = ""; win.summaryState = ""
                }
            } else if (what === "summary") {
                win.summaryText = v.text || ""; win.summaryState = v.error ? "error" : "done"
                console.info("RECAP summary", v.error || "", (v.text || "").length)
            } else if (what === "notes") {
                win.notesUrl = v.url || ""; win.notesState = v.error ? "error" : "ready"
                console.info("RECAP notes", v.error || "", !!v.url)
            } else if (what === "audio") {
                console.info("RECAP audio", v.error || "", v.status || "", v.message || "", !!v.existing)
                if (win.audioPlayer) win.audioPlayer.result(v)
            } else if (what === "copilot") {
                win.copilotLaunch = v.error ? null : v
                console.info("RECAP copilot", v.error || "ready")
            } else if (what === "expiry") {
                if (!v.error) backend.eventsRequest("recapExtras", win.tag + "extras", JSON.stringify({ recap: win.recap }))
                win.toast({ text: v.error ? qsTr("Failed to update expiration date. Please try again.") : qsTr("Expiration date updated successfully."), intent: v.error ? "error" : "success" })
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
            // Teams' Audio recap (126 x 32, headphones): an AI audio recap
            // of the meeting in its mini player.
            BandButton { id: audioButton; visible: !!win.data_ && !!win.data_.audioRecap; icon: "headphones-20"; label: qsTr("Audio recap"); active: !!win.audioPlayer; onClicked: win.openAudioRecap() }
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
            visible: win.recording
            x: 13; y: 49; width: win.recording ? Math.max(320, parent.width - 13 - 507.7 - 13) : 0; height: parent.height - y - 14
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
            x: win.recording ? left.x + left.width + 7.6 : 12; y: 49; width: parent.width - x - (win.recording ? 13 : 12); height: 89.3
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
                // Teams' two-column file grid (226.2 in the 495.7 column,
                // 609 across a transcript-only recap's full width).
                x: 15.7; y: 42.7; width: (files.width - 43.3) / 2; height: 32; radius: 4
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
            // (Full width, without the recording card, all five fit.)
            // (Teams then puts Mentions before Transcript.)
            readonly property var shown: win.recording ? all.filter(p => p.k !== (fourth === "Transcript" ? "Mentions" : "Transcript")) : [all[0], all[1], all[2], all[4], all[3]]
            readonly property var hidden: all.filter(p => shown.indexOf(p) < 0)
            Row {
                x: 12; y: 12.7; spacing: 8
                Repeater {
                    model: right.shown
                    Pill { required property var modelData; label: modelData.t; isNew: !!modelData.isNew; chosen: win.rightPill === modelData.k; onClicked: win.rightPill = modelData.k }
                }
            }
            Pill {
                visible: right.hidden.length > 0
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
            // AI summary (Teams 26304's AI notes and tasks panels, measured on
            // winpc 2026-11-21 with OST TEST 240 recap meeting): under the
            // line, "AI-generated content may be incorrect" with Copy all at
            // the right; then "Meeting notes" with Expand all / Collapse all,
            // one row per topic (a caret, "<b>Headline:</b> summary"; open, its
            // points as bullets), "Are these notes useful?" with like and
            // dislike; then "Follow-up tasks": "<b>Headline:</b> task
            // (owner)" bullets and "Are these tasks useful?". Without notes or
            // tasks, Teams' "We didn't find any …" lines.
            Item {
                id: aiPage
                visible: win.rightPill === "AINotes"
                y: 52.7; width: parent.width; height: parent.height - y
                readonly property var notes: win.aiNotes && win.aiNotes.notes ? win.aiNotes.notes : []
                readonly property var tasks: win.aiNotes && win.aiNotes.tasks ? win.aiNotes.tasks : []
                property var open: ({})
                readonly property bool allOpen: notes.length > 0 && notes.every((n, i) => !!open[i] || !(n.details || []).length)
                function toggle(i) { const o = Object.assign({}, open); o[i] = !o[i]; open = o }
                function setAll(v) { const o = {}; for (let i = 0; i < notes.length; i++) o[i] = v; open = o }
                // Teams' Copy all (991291 `ef`): the plain text of both
                // sections with the recap's link.
                function copyAll() {
                    let t = qsTr("Generated by AI. Be sure to check for accuracy.")
                    if (win.data_ && win.data_.link) t += "\n" + qsTr("View the full meeting recap in Teams: %1.").arg(win.data_.link) + "\n"
                    t += "\n" + qsTr("Meeting notes") + ":"
                    for (const n of notes) {
                        if (n.title) t += "\n" + n.title + ": "
                        t += "\n" + n.summary
                        for (const d of (n.details || [])) t += "\n\t" + d.topic + ": " + d.text
                    }
                    t += "\n" + qsTr("Follow-up tasks") + ":"
                    for (const k of tasks) {
                        if (k.title) t += "\n" + k.title + ": "
                        t += "\n" + k.text + (k.title && k.owner ? " (" + k.owner + ")" : "")
                    }
                    backend.copyText(t)
                    copied.restart()
                    console.info("RECAP ai copied", t.length)
                    return t
                }
                Timer { id: copied; interval: 5000 }
                Text {
                    x: 20.7; y: 14.7; width: parent.width - 80
                    text: qsTr("AI-generated content may be incorrect"); elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                IconBtn {
                    visible: aiPage.notes.length + aiPage.tasks.length > 0
                    anchors { right: parent.right; rightMargin: 22.6 }
                    y: 9; width: 32; height: 31.3; icon: "copy-20"
                    tip: copied.running ? qsTr("Copied to clipboard") : qsTr("Copy all")
                    onClicked: aiPage.copyAll()
                }
                Flickable {
                    id: aiFlick
                    y: 49; width: parent.width; height: parent.height - y - 1
                    clip: true; contentHeight: aiColumn.height + 8; boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: aiFlick.contentHeight > aiFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    Column {
                        id: aiColumn
                        x: 20.7; width: aiPage.width - 20.7 - 34.6
                        Item {
                            width: parent.width; height: 59.2
                            Text {
                                y: 27.6; text: qsTr("Meeting notes")
                                lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
                                Accessible.role: Accessible.Heading; Accessible.name: text
                            }
                            Text {
                                id: expandAll
                                visible: aiPage.notes.some(n => (n.details || []).length > 0)
                                anchors.right: parent.right; y: 27.6
                                text: aiPage.allOpen ? qsTr("Collapse all") : qsTr("Expand all")
                                lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                color: expandHover.hovered ? theme.brand : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                                HoverHandler { id: expandHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: aiPage.setAll(!aiPage.allOpen) }
                                Accessible.role: Accessible.Button; Accessible.name: text
                            }
                        }
                        Text {
                            visible: !!win.aiNotes && aiPage.notes.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: qsTr("We didn't find any notes for this meeting.")
                            lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text
                        }
                        Repeater {
                            model: aiPage.notes
                            Column {
                                id: topic
                                required property var modelData
                                required property int index
                                readonly property bool opened: !!aiPage.open[index]
                                width: aiColumn.width
                                Item {
                                    width: parent.width; height: Math.max(32, l1Text.implicitHeight + 12)
                                    FluentIcon {
                                        visible: (topic.modelData.details || []).length > 0
                                        x: 4; y: 9; size: 14
                                        name: topic.opened ? "caret-down-12-filled" : "caret-right-12-filled"; color: theme.text
                                    }
                                    Text {
                                        id: l1Text
                                        x: 29; y: 6; width: parent.width - 29
                                        textFormat: Text.StyledText; wrapMode: Text.Wrap
                                        text: (topic.modelData.title ? "<b>" + win.escapeHtml(topic.modelData.title) + ":</b> " : "") + win.escapeHtml(topic.modelData.summary)
                                        lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text
                                    }
                                    HoverHandler { enabled: (topic.modelData.details || []).length > 0; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { enabled: (topic.modelData.details || []).length > 0; onTapped: aiPage.toggle(topic.index) }
                                    Accessible.role: Accessible.Button; Accessible.name: (topic.modelData.title || "") + " " + topic.modelData.summary
                                }
                                Repeater {
                                    model: topic.opened ? topic.modelData.details : []
                                    Item {
                                        required property var modelData
                                        width: topic.width; height: Math.max(32, l2Text.implicitHeight + 12)
                                        Text { x: 30; y: 6; text: "•"; lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                        Text {
                                            id: l2Text
                                            x: 46.9; y: 6; width: parent.width - 46.9
                                            textFormat: Text.StyledText; wrapMode: Text.Wrap
                                            text: "<b>" + win.escapeHtml(parent.modelData.topic) + ":</b> " + win.escapeHtml(parent.modelData.text)
                                            lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text
                                        }
                                    }
                                }
                            }
                        }
                        Feedback { visible: aiPage.notes.length > 0; width: parent.width; question: qsTr("Are these notes useful?"); area: "notes" }
                        Item { width: 1; height: 45.7 }
                        Text {
                            text: qsTr("Follow-up tasks"); height: !!win.aiNotes && aiPage.tasks.length === 0 ? 41.7 : 36.6
                            lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
                            Accessible.role: Accessible.Heading; Accessible.name: text
                        }
                        Text {
                            visible: !!win.aiNotes && aiPage.tasks.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: qsTr("We didn't find any tasks for this meeting.")
                            lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text
                        }
                        Repeater {
                            model: aiPage.tasks
                            Item {
                                required property var modelData
                                required property int index
                                // (Teams' rows: 25 tall, 2 apart.)
                                width: aiColumn.width; height: taskText.implicitHeight + (index === aiPage.tasks.length - 1 ? 5 : 7)
                                Text { x: 10; y: 0; text: "•"; lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                Text {
                                    id: taskText
                                    x: 31; width: parent.width - 31
                                    textFormat: Text.StyledText; wrapMode: Text.Wrap
                                    text: (parent.modelData.title ? "<b>" + win.escapeHtml(parent.modelData.title) + ":</b> " : "") + win.escapeHtml(parent.modelData.text)
                                          + (parent.modelData.title && parent.modelData.owner ? " (" + win.escapeHtml(parent.modelData.owner) + ")" : "")
                                    lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.text
                                }
                            }
                        }
                        Feedback { visible: aiPage.tasks.length > 0; width: parent.width; question: qsTr("Are these tasks useful?"); area: "tasks" }
                    }
                }
            }
            // Notes (the meeting's notes): Teams' invitation to add them;
            // Add notes makes them (Teams' meeting-notes service) and shows
            // the Loop notes here.
            // Teams' Loop header row over the notes (the bundled Loop
            // control: the notes' name, Shared locations, Copy component, See
            // who has access; 13 under the line, the page 51.7 under it).
            Loader {
                id: notesChrome
                active: win.rightPill === "Notes" && win.notesUrl !== ""
                x: 22.7; y: 64; width: parent.width - x - 18.6; height: 31.3
                sourceComponent: LoopChromeBar { readName: true; link: win.notesUrl }
            }
            Loader {
                active: win.rightPill === "Notes" && win.notesUrl !== ""
                x: 3.3; y: 104.4; width: parent.width - 6.6; height: parent.height - y - 3
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
                    visible: !!win.mentions
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 192; height: 192; sourceSize: Qt.size(384, 384)
                    // Teams: the warning on an error, its tag otherwise.
                    source: "../assets/illustrations/" + (win.mentions && win.mentions.error ? "warning" : "tag") + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                }
                Item { visible: !!win.mentions; width: 1; height: 24 }
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
            // cards (Create template, yours, then Speaker summary, Executive
            // report and Project update), then the summary Copilot writes in
            // the chosen one's format.
            BusyIndicator {
                visible: win.rightPill === "CustomSummary" && win.templates === null
                running: visible
                anchors.horizontalCenter: parent.horizontalCenter; y: 140; width: 32; height: 32
            }
            Item {
                visible: win.rightPill === "CustomSummary" && win.templates !== null
                x: 12; y: 64; width: parent.width - 24; height: parent.height - y - 12
                // Teams' template cards (customize-notes panel, measured on
                // winpc): a page of 4 (948 wide or more), 3 (480-947) or 2
                // cards, 50.7 tall, 8 apart, the title 14/600; Next /
                // Previous templates (25 x 25) when there are more. The chosen
                // card is NeutralBackground1Selected with a brand checkmark
                // (20, in a 32 px area 8 from its right); on yours, hovering
                // shows "..." (25, Actions) there instead.
                Item {
                    id: cards
                    width: parent.width; height: 50.7
                    readonly property var all: {
                        const mine = (win.templates || []).map(x => ({ key: x.id, t: x.name, d: qsTr("Created by you"), odb: true }))
                        const builtIn = [
                            { key: "SpeakersBasedRecap", t: qsTr("Speaker summary"), d: qsTr("Main points by speaker") },
                            { key: "ExecutiveSummary", t: qsTr("Executive report"), d: qsTr("Overview and key area updates") },
                            { key: "ProjectSummary", t: qsTr("Project update"), d: qsTr("Accomplishments, risks, and action items") }
                        ].filter(c => win.builtInKeys.indexOf(c.key) >= 0)
                        let list = mine.concat(builtIn)
                        if (win.frontKey) list = list.filter(c => c.key === win.frontKey).concat(list.filter(c => c.key !== win.frontKey))
                        return win.createTemplate ? [{ key: "CreateOwnTemplate", t: qsTr("Create template"), create: true }].concat(list) : list
                    }
                    readonly property int perPage: width >= 948 ? 4 : width >= 480 ? 3 : 2
                    property int page: 0
                    readonly property int pages: Math.ceil(all.length / perPage)
                    onPagesChanged: if (page > pages - 1) page = Math.max(0, pages - 1)
                    readonly property real cardWidth: (width - 8 * (perPage - 1)) / perPage
                    Row {
                        spacing: 8
                        Repeater {
                            id: cardRepeater
                            model: cards.all.slice(cards.page * cards.perPage, (cards.page + 1) * cards.perPage)
                            Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool chosen: !modelData.create && win.summaryKey === modelData.key
                                readonly property bool menuShown: !!modelData.odb && (cardHover.hovered || win.menuFor === modelData.key)
                                readonly property Item moreButton: moreBtn
                                width: cards.cardWidth; height: 50.7; radius: 4
                                color: chosen ? theme.pick("#EBEBEB", "#383838") : cardHover.hovered ? theme.rowHover : theme.surface
                                FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 4 }
                                Row {
                                    x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    FluentIcon { visible: !!card.modelData.create; anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 20; color: theme.onFill(card, theme.text) }
                                    Text { width: card.width - 16 - (card.modelData.create ? 44 : 40); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: card.modelData.t; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(card, theme.text) }
                                }
                                HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        if (card.modelData.create) templateEditor.openNew(win.templates || [])
                                        else win.choose(card.modelData.key, !!card.modelData.odb)
                                    }
                                }
                                Item {
                                    visible: !card.modelData.create
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: 32; height: 32
                                    FluentIcon { visible: card.chosen && !card.menuShown; anchors.centerIn: parent; name: "checkmark-20"; size: 20; color: theme.onFill(card, theme.brandForeground1) }
                                    Rectangle {
                                        id: moreBtn
                                        visible: card.menuShown
                                        anchors.centerIn: parent; width: 25; height: 25; radius: 4
                                        color: moreHover.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 16; color: theme.onFill(moreBtn, theme.textStrong) }
                                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: win.openTemplateMenu(moreBtn, card.modelData) }
                                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Actions")
                                    }
                                }
                                ToolTip.visible: cardHover.hovered && !card.menuShown && !!card.modelData.d
                                ToolTip.text: card.modelData.d || ""
                                ToolTip.delay: 500
                                Accessible.role: Accessible.PageTab; Accessible.name: modelData.t
                                Accessible.selected: chosen
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
                        Item { visible: win.summaryState === "" || win.summaryState === "error"; width: 1; height: 36 }
                        Image {
                            visible: win.summaryState === "" || win.summaryState === "error"
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 192; height: 192; sourceSize: Qt.size(384, 384)
                            source: "../assets/illustrations/" + (win.summaryState === "error" ? "warning" : "meeting-notes") + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
                        }
                        Text {
                            visible: win.summaryState === ""
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 16
                            text: qsTr("Pick a template or create your own")
                            lineHeight: 22.86; lineHeightMode: Text.FixedHeight
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                        }
                        // Teams' loading card (radius 8, shadow 2, 40 tall, 8
                        // around it).
                        Rectangle {
                            id: sumLoading
                            visible: win.summaryState === "generating"
                            x: 8; width: parent.width - 16; height: 40; radius: 8
                            color: theme.surface; clip: true
                            FluentSurface { z: -1; anchors.fill: parent; depth: 2; radius: 8 }
                            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Generating your summary..."); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(sumLoading, theme.text) }
                            Rectangle {
                                id: sumBar
                                y: parent.height - 2; height: 2; width: parent.width * 0.33; radius: 1; color: theme.brand
                                NumberAnimation on x { running: sumLoading.visible; loops: Animation.Infinite; from: -sumBar.width; to: sumLoading.width; duration: 3000 }
                            }
                            Accessible.role: Accessible.ProgressBar; Accessible.name: qsTr("Generating your summary...")
                        }
                        Column {
                            visible: win.summaryState === "error"
                            width: parent.width; topPadding: 16; spacing: 8
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
    RecapTemplateEditor {
        id: templateEditor
        recap: win.recap
        // A new template: the list again, and it's chosen (its summary).
        onCreated: (id, name) => { win.loadTemplates(); if (id) win.choose(id, true) }
        // An edited one: its card's name, and its summary again.
        onUpdated: (id, name, content) => {
            win.templates = (win.templates || []).map(x => x.id === id ? { id: x.id, name: name } : x)
            win.choose(id, true)
        }
    }
    RecapTemplateNameDialog {
        id: renameDialog
        property string renaming: ""
        property string lastName: ""
        onConfirmed: name => {
            lastName = name
            backend.eventsRequest("recapTemplateUpdate", win.tag + "rename:" + renaming, JSON.stringify({ id: renaming, name: name }))
        }
    }
    // Teams' template menu (below-start of "..."): Edit, Share ("Copy and
    // share prompt"), Rename, and Delete in red.
    MenuPopup {
        id: templateMenu
        property var target: null
        items: [{ key: "edit", label: qsTr("Edit"), icon: "edit-20" },
                { key: "share", label: qsTr("Share"), icon: "share-20", tip: qsTr("Copy and share prompt") },
                { key: "rename", label: qsTr("Rename"), icon: "rename-20" },
                { key: "delete", label: qsTr("Delete"), icon: "delete-20", danger: true }]
        onPicked: i => { if (target) win.templateAction(items[i].key, target.key, target.t) }
        onClosed: win.menuFor = ""
    }
    function openTemplateMenu(button, card) {
        templateMenu.target = card
        win.menuFor = card.key
        const p = button.mapToItem(win.contentItem, 0, button.height + 4)
        templateMenu.parent = win.contentItem
        templateMenu.y = p.y
        templateMenu.open()
        // Below-start, shifted back inside the window (Fluent's positioning).
        templateMenu.x = Math.max(8, Math.min(p.x, win.contentItem.width - templateMenu.width - 8))
    }

    // Teams' "Are these notes useful?" row (532855's feedback renderer:
    // 12 px question, then like and dislike, 32 x 31.3 with 16 px glyphs),
    // 4 below the list, at the right. Like and dislike open the feedback
    // form (Teams' showFeedback with Intelligent_Recap).
    component Feedback: Item {
        id: fb
        property string question
        property string area
        height: 35.3
        Row {
            anchors.right: parent.right; y: 4
            Text { anchors.verticalCenter: parent.verticalCenter; text: fb.question; lineHeight: 17.14; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Repeater {
                model: [{ k: "compliment", icon: "thumb-like-16", tip: qsTr("Like") }, { k: "problem", icon: "thumb-dislike-16", tip: qsTr("Dislike") }]
                Rectangle {
                    required property var modelData
                    width: 32; height: 31.3; radius: 4
                    color: thumbHover.hovered ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon + (thumbHover.hovered ? "-filled" : ""); size: 16; color: theme.onFill(parent, theme.text) }
                    HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            console.info("RECAP ai feedback", fb.area, parent.modelData.k)
                            backend.requestFeedback(parent.modelData.k, "Intelligent recap", "AI summary " + fb.area + ": " + (win.recap.subject || ""))
                        }
                    }
                    ToolTip.visible: thumbHover.hovered; ToolTip.text: modelData.tip; ToolTip.delay: 500
                    Accessible.role: Accessible.Button; Accessible.name: fb.question + " " + modelData.tip
                }
            }
        }
    }
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
        /// Teams' brand colour while what it opened is open (Audio recap).
        property bool active: false
        signal clicked()
        height: 32; width: bbRow.implicitWidth + 24; radius: 4
        color: bbh.hovered ? theme.rowHover : "transparent"
        Row {
            id: bbRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: bb.icon; size: 20; color: bb.active ? theme.brandForeground1 : theme.onFill(bb, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: bb.label; font.family: theme.font; font.pixelSize: 14; color: bb.active ? theme.brandForeground1 : theme.onFill(bb, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
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
    function aiNotesForTest() {
        const a = win.aiNotes
        return JSON.stringify({ loaded: a !== null, error: a ? a.error || "" : "", notes: a ? (a.notes || []).map(n => n.title + " (" + (n.details || []).length + ")") : [], tasks: a ? (a.tasks || []).map(t => t.title + " / " + t.owner) : [],
                                notesState: a ? a.notesState || "" : "", tasksState: a ? a.tasksState || "" : "", open: aiPage.allOpen, flick: Math.round(aiFlick.contentHeight) })
    }
    function aiExpandAllForTest() { aiPage.setAll(true) }
    function aiCopyForTest() { return aiPage.copyAll() }
    function notesHeaderForTest() { return notesChrome.item ? notesChrome.item.stateForTest() : { shown: false } }
    function summarizeForTest(k) { win.choose(k, false) }
    // --recap-window-test=template.
    function templatesForTest() {
        return JSON.stringify({ templates: win.templates, key: win.summaryKey, odb: win.summaryOdb, summary: win.summaryState, order: cards.all.map(c => c.t),
                                remembered: win.remembered(), menu: win.menuFor, shared: win.lastShared })
    }
    function templateEditorForTest() { return templateEditor }
    function closeTemplateMenuForTest() { templateMenu.close() }
    function renameDialogForTest() { return renameDialog }
    function templateActionForTest(action, id) { const t = (win.templates || []).find(x => x.id === id); win.templateAction(action, id, t ? t.name : "") }
    function templateMenuForTest(id) {
        for (let i = 0; i < cardRepeater.count; i++) {
            const c = cardRepeater.itemAt(i)
            if (c && c.modelData.key === id) { win.openTemplateMenu(c.moreButton, c.modelData); return true }
        }
        return false
    }
    function copilotForTest() { win.toggleCopilot() }
    function manageForTest() { manageMenu.open() }
    function extrasForTest() { return JSON.stringify({ extras: win.extras, mentions: win.mentions, summary: win.summaryState, summaryLen: win.summaryText.length, notes: win.notesState, copilot: !!win.copilotLaunch }) }
    function audioForTest() { if (audioButton.visible) win.openAudioRecap(); return audioButton.visible }
    function audioStateForTest() { return win.audioPlayer ? win.audioPlayer.stateForTest() : "none" }
    function audioPlayerForTest() { return win.audioPlayer }
    function addNotesForTest() { win.notesState = "making"; backend.eventsRequest("recapNotes", win.tag + "notes", JSON.stringify({ recap: win.recap })) }
    function bandForTest() {
        const out = []
        for (const b of [audioButton]) if (b.visible) { const p = b.mapToItem(win.contentItem, 0, 0); out.push({ label: b.label, x: p.x, y: p.y, w: b.width, h: b.height }) }
        return JSON.stringify({ band: out, recording: win.recording, pills: right.shown.map(p => p.k), hidden: right.hidden.map(p => p.k), clipchamp: !!(win.extras && win.extras.clipchamp), files: { x: files.x, w: files.width } })
    }
    function stateForTest() { return JSON.stringify({ loading: win.loading, pill: win.rightPill, player: !!(win.data_ && win.data_.player), recording: win.recording, audio: !!(win.data_ && win.data_.audioRecap), transcript: win.data_ ? (win.data_.transcript || []).length : -1, thread: win.recap.thread_id || "", link: win.data_ ? win.data_.link : "" }) }
    function shareDialogForTest() { return shareDialog }
}
