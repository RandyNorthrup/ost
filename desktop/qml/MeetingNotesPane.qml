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
        Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: "Notes"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.pick("#252423", "#FFFFFF") }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: [["more-horizontal-20", "More actions"], ["dismiss-20", "Close"]]
                Rectangle {
                    id: hb
                    required property var modelData
                    width: 32; height: 32; radius: 6
                    color: hh.hovered ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: hb.modelData[0]; size: 20; color: theme.icon }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: hb.modelData[1] === "Close" ? root.closed() : moreMenu.open() }
                    Accessible.role: Accessible.Button; Accessible.name: hb.modelData[1]
                }
            }
        }
    }
    // More actions: Teams lists Shared locations, Copy component, See who
    // has access, Open in Loop and Add to Loop workspace; OST has the
    // link's two.
    MenuPopup {
        id: moreMenu
        parent: header
        x: header.width - 16 - 64 - implicitWidth + 32; y: 50
        items: [{ key: "copy", label: "Copy component", icon: "copy-20" }, { key: "loop", label: "Open in Loop", icon: "open-20" }]
        onPicked: i => {
            const link = root.url || root.sharedUrl
            if (!link) return
            if (items[i].key === "copy") backend.copyText(link)
            else Qt.openUrlExternally(link)
        }
    }
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
            text: "Couldn't open the meeting's notes. " + root.error
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        Text {
            visible: root.state_ === "error"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Try again"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
            TapHandler { onTapped: root.resolve(false) }
            Accessible.role: Accessible.Button; Accessible.name: text
        }
    }
}
