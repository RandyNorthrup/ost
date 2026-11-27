import QtQuick
import QtQuick.Controls

// The call window's Notes (Teams' calling-right-side-panel "Meeting notes",
// measured in Teams on the web on a Meet now, 2026-11-16): #F5F5F5, 360
// wide; a white header (58 tall, 3 down) with "Notes" (18/25.7 bold
// #252423, 22 in), More actions and Close (32 x 32, 16 from the right);
// the meeting's notes 16 below it as a Loop page (Loop's own page
// container, OST's Loop host: Agenda, Meeting notes, Follow-up tasks)
// filling the rest less 8 at the bottom.
//
// The page is the one the call shares (collabResources.notes); else
// Teams' meeting-notes service gets or makes it; else OST makes it as
// Teams does (claims collabLeaders.notes, makes the page from Loop's
// meeting blueprint in your OneDrive's Meetings folder, shares its link).
Rectangle {
    id: root
    color: theme.pane
    signal closed()
    /// "", "resolving", "waiting" (someone else is making them),
    /// "creating", "ready" or "error".
    property string state_: ""
    property string error: ""
    property string url: ""
    property string title: ""
    property bool create: false
    property var events: []
    readonly property string sharedUrl: backend.callNotesUrl
    property int seq: 0
    function note(e) { events = events.concat([e]); console.info("MEETINGNOTES", e) }
    function open() { if (state_ === "" || state_ === "error") resolve(false) }
    function resolve(force) {
        state_ = "resolving"; error = ""
        note("resolve" + (force ? " (force)" : ""))
        backend.callNotesRequest("resolve", "notes" + (++seq), JSON.stringify({ force: force ? "1" : "" }))
    }
    function show(u, how) { url = u; create = false; state_ = "ready"; note("show " + how); page.active = false; page.active = true }
    function stateForTest() { return JSON.stringify({ state: root.state_, error: root.error, events: root.events, url: root.url.split("?")[0], page: page.item ? JSON.parse(page.item.stateForTest()) : null }) }
    Connections {
        target: backend
        function onCallNotesReply(id, json) {
            if (id.indexOf("notes") !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            if (v.error) { root.error = v.error; root.state_ = "error"; root.note("error " + v.error); return }
            if (v.url) {
                if (v.source === "made") { root.note("shared"); return }
                root.show(v.url, v.source)
            } else if (v.waiting) { root.state_ = "waiting"; root.note("waiting"); waitTimer.restart() }
            else if (v.create) { root.title = v.title || ""; root.create = true; root.url = ""; root.state_ = "creating"; root.note("create"); page.active = false; page.active = true }
        }
    }
    // Someone else made the notes: open them.
    onSharedUrlChanged: if (sharedUrl && (state_ === "waiting" || state_ === "resolving")) show(sharedUrl, "call")
    // Teams waits for the one making the notes; after a while, make them.
    Timer { id: waitTimer; interval: 30000; onTriggered: if (root.state_ === "waiting") root.resolve(true) }

    Rectangle {
        id: header
        y: 3; width: parent.width; height: 58
        color: theme.surface
        Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Notes"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.pick("#252423", "#FFFFFF") }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: [["more-horizontal-20", qsTr("More actions")], ["dismiss-20", qsTr("Close")]]
                Rectangle {
                    id: hb
                    required property var modelData
                    width: 32; height: 32; radius: 6
                    color: hh.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: hb.modelData[0]; size: 20; color: theme.icon }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: hb.modelData[0] === "dismiss-20" ? root.closed() : moreMenu.open() }
                    Accessible.role: Accessible.Button; Accessible.name: hb.modelData[1]
                }
            }
        }
    }
    // More actions (the Loop host controls Teams gives the notes): Shared
    // locations (where the notes are shared: the meeting's chat), Copy
    // component, See who has access (OneDrive's Manage access for the notes'
    // file), Open in Loop and Add to Loop workspace (Loop's own page for it:
    // loop.microsoft.com/p/<base64 {"p":{"u":link,"r":false},"a":
    // "AddToWorkspace"}>).
    property string meetingTitle: ""
    MenuPopup {
        id: moreMenu
        parent: header
        x: header.width - 16 - 64 - implicitWidth + 32; y: 50
        items: [{ key: "locations", label: qsTr("Shared locations"), icon: "apps-20" },
                { key: "copy", label: qsTr("Copy component"), icon: "select-object-20" },
                { key: "access", label: qsTr("See who has access"), icon: "people-checkmark-20" },
                { key: "loop", label: qsTr("Open in Loop"), icon: "open-20" },
                { key: "workspace", label: qsTr("Add to Loop Workspace"), icon: "add-square-20" }]
        onPicked: i => {
            const link = root.url || root.sharedUrl
            if (!link) return
            const k = items[i].key
            if (k === "copy") backend.copyText(link)
            else if (k === "loop") backend.openExternal(link)
            else if (k === "locations") locations.open()
            else if (k === "access") backend.callNotesRequest("item", "nmitem" + (++root.seq), JSON.stringify({ url: link }))
            else if (k === "workspace") backend.callNotesRequest("workspace", "nmws" + (++root.seq), JSON.stringify({ url: link }))
        }
    }
    Connections {
        target: backend
        function onCallNotesReply(id, json) {
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            if (id.indexOf("nmitem") === 0) {
                if (v.error) { root.note("access error " + v.error); return }
                notesShare.openManage({ site: v.site, list: v.list, item: v.item }, v.name, "loop")
                root.note("access")
            } else if (id.indexOf("nmws") === 0 && v.url) { backend.openExternal(v.url); root.note("workspace") }
            else if (id.indexOf("nmtestws") === 0) root.note("workspace url " + (v.url || v.error))
        }
    }
    OneDriveShare { id: notesShare }
    // Shared locations: the notes' name, then "Open component in" the
    // meeting's chat.
    Popup {
        id: locations
        parent: header
        x: header.width - width - 16; y: 50
        padding: 12; width: 280
        background: FluentSurface { depth: 16; radius: 8; color: theme.menu }
        contentItem: Column {
            spacing: 8
            Text { text: qsTr("Shared locations"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text { width: 256; elide: Text.ElideRight; text: (root.title || root.meetingTitle || qsTr("Meeting notes")) + ".loop"; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1
                   TapHandler { onTapped: backend.openExternal(root.url || root.sharedUrl) } }
            Text { text: qsTr("Open component in"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Row { spacing: 8
                FluentIcon { name: "chat-20"; size: 16; color: theme.textStrong }
                Text { text: qsTr("Teams / Chat") + " · " + (root.meetingTitle || root.title || qsTr("Meeting chat")); font.family: theme.font; font.pixelSize: 14; color: theme.text } }
        }
    }
    function menuForTest() { return moreMenu.items.map(i => i.label) }
    // The harness: See who has access as the menu does; Add to Loop
    // workspace's address logged instead of opened.
    function accessForTest() { backend.callNotesRequest("item", "nmitem" + (++seq), JSON.stringify({ url: root.url || root.sharedUrl })) }
    function workspaceForTest() { backend.callNotesRequest("workspace", "nmtestws" + (++seq), JSON.stringify({ url: root.url || root.sharedUrl })) }
    function locationsForTest(on) { if (on) locations.open(); else locations.close() }
    function closeAccessForTest() { notesShare.close() }
    Loader {
        id: page
        active: false
        x: 1; y: header.y + header.height + 16; width: parent.width - 1; height: parent.height - y - 8
        sourceComponent: LoopPage {
            kind: "meetingNotes"
            title: root.title
            create: root.create
            componentUrl: root.create ? "" : root.url
            onCreated: u => {
                root.url = u
                root.note("created")
                backend.callNotesRequest("made", "notes" + (++root.seq), JSON.stringify({ componentUrl: u, driveId: createdInfo.driveId || "", itemId: createdInfo.itemId || "" }))
            }
            onFailed: m => { root.error = m; root.note("page error") }
            Component.onCompleted: root.note("page")
        }
    }
    Column {
        visible: root.state_ !== "ready" && root.state_ !== "creating"
        anchors.centerIn: page
        spacing: 12
        BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: root.state_ === "resolving" || root.state_ === "waiting"; visible: running; width: 32; height: 32 }
        Text {
            visible: root.state_ === "error"
            width: 300; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: qsTr("We couldn't load meeting notes.") + " " + root.error
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Text {
            visible: root.state_ === "error"
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Try again"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
            TapHandler { onTapped: root.resolve(false) }
            Accessible.role: Accessible.Button; Accessible.name: text
        }
    }
}
