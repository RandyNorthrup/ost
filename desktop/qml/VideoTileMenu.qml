import QtQuick
import QtQuick.Controls

// Teams' video tile ··· menu: someone else's (CallingParticipantContextMenu,
// 879019 getMoreMenuItems) and your own (MyselfVideo's menu, 846553
// renderMoreMenu), with Teams' items in Teams' order, each only where
// Teams offers it. Measured on winpc 2026-11-24 (Teams as the organizer):
// - OST Test 3 (a presenter with video): Mute participant (disabled while
//   they're muted), Pin for me, Spotlight for everyone, Fit to frame, a
//   divider, Report.
// - OST Test Room (a Teams Room): Mute participant, Pin for me, Spotlight
//   for everyone, Control Room System, a divider, Report.
// - Your own tile: Pin for me, Hide me, Remove me from gallery, Spotlight
//   for everyone (in the gallery; floating over the stage with one other
//   person there is no gallery item).
// - As an attendee: theirs Pin for me, Fit / Fill, a divider, Report;
//   yours Pin for me, Hide me. At least 134 wide.
// No Remove from meeting or role changes here: those are the People
// pane's. The surface is white, radius 4, 2 px in, Fluent's menu shadow
// and no edge; items 32 tall and 2 apart, as wide as the longest label +
// 36 (the 20 px glyph at 6, the 14 px #424242 label at 30), disabled
// ones #BDBDBD; a divider is 0.67 thick with 4 above and below.
Popup {
    id: root
    /// The call window.
    property var call
    /// The tile's person: a roster entry, or your selfEntry ({self: true}).
    property var who: ({})
    readonly property bool self: !!who.self
    /// Whose menu is open (the tile's ··· turns brand while it is).
    readonly property string forId: opened ? (self ? "me" : (who.id || "")) : ""
    padding: 2
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
    // Its size from its items (known before it lays out, so it can be
    // placed as it opens).
    width: itemWidth + 2 * padding
    height: items.reduce((s, it) => s + (it.sep ? 8.67 : 32), 0) + 2 * Math.max(0, items.length - 1) + 2 * padding

    /// Open from a tile's ···: someone else's to its right, bottom-aligned
    /// (Fluent's "after-bottom"); yours above it, start-aligned
    /// ("above-start"). Either flips to stay in the window.
    function openFor(button, person) {
        who = person
        const host = parent
        const tl = button.mapToItem(host, 0, 0)
        const w = width, h = height
        let x, y
        if (person.self) {
            x = tl.x; y = tl.y - h
            // (End-aligned when it would run past the window: measured
            // with your tile at the stage's bottom right.)
            if (x + w > host.width) x = tl.x + button.width - w
            if (y < 0) y = tl.y + button.height
        } else {
            x = tl.x + button.width; y = tl.y + button.height - h
            if (x + w > host.width) x = tl.x - w
            if (y < 0) y = tl.y
        }
        root.x = Math.max(0, Math.min(x, host.width - w))
        root.y = Math.max(0, Math.min(y, host.height - h))
        open()
    }
    /// Open where a tile was right-clicked: centred on the pointer, above
    /// it, else below it (Teams' context menu, "above" over a virtual
    /// target at the pointer; measured flipped below near the stage top).
    function openAt(item, px, py, person, top) {
        who = person
        const host = parent
        const p = item.mapToItem(host, px, py)
        const w = width, h = height
        let y = p.y - h
        if (y < top) y = p.y + 1.33
        root.x = Math.max(0, Math.min(p.x - w / 2, host.width - w))
        root.y = Math.max(0, Math.min(y, host.height - h))
        open()
    }

    readonly property var items: {
        const c = call, w = who
        if (!c || !w) return []
        const out = []
        const add = it => out.push(it)
        const presenter = c.presenterRole
        const pinned = c.pinnedIds.indexOf(root.self ? c.selfId : w.id) >= 0
        const spotlit = root.self ? c.spotlighted.some(p => p.id === c.selfId) : !!w.spotlight
        const othersSpotlit = c.spotlighted.filter(p => p.id !== (root.self ? c.selfId : w.id)).length
        const spotFull = c.spotlighted.length >= c.maxSpotlights
        const managed = !!c.liveEvent && !!c.liveEvent.managed
        if (root.self) {
            // Switch camera: video on and more than one camera.
            if (c.cameraOn && c.cameraCount() > 1) add({ k: "switchCamera", t: qsTr("Switch camera"), icon: "camera-switch-20" })
            // Pin for me (yours): disabled while spotlighted or full.
            const pinOff = !pinned && (c.pinningFull || spotlit || managed)
            add({ k: pinned ? "unpin" : "pin", t: pinned ? qsTr("Unpin for me") : qsTr("Pin for me"), icon: pinned ? "pin-off-20" : "pin-20", off: pinOff,
                  tip: pinOff ? (managed ? qsTr("Unavailable while presenters are managing what attendees see") : spotlit ? qsTr("Can't pin a participant that is spotlighted") : qsTr("You reached the maximum number of pins"))
                              : pinned ? qsTr("Unpin your own video") : qsTr("Pin your own video") })
            // Hide me: not while you're pinned ("Unpin your video to hide it").
            if (!managed) add({ k: "hideMe", t: qsTr("Hide me"), icon: "eye-off-20", off: pinned,
                                tip: pinned ? qsTr("Unpin your video to hide it") : qsTr("Hide your own video. Others will still see it.") })
            // Gallery: whether you're one of its tiles.
            if (c.layout === "gallery" && !c.meOverlayShown) {
                const t = c.meInGallery ? qsTr("Remove me from gallery") : qsTr("Include me in gallery")
                add({ k: "meInGallery", t: t, icon: "apps-20", tip: t })
            }
            if (presenter && c.meeting) {
                if (managed) add({ k: spotlit ? "unspotlight" : "spotlight", t: spotlit ? qsTr("Take off screen") : qsTr("Bring on screen"), icon: "spotlight-20" })
                else add({ k: spotlit ? "unspotlight" : "spotlight", t: spotlit ? qsTr("Exit spotlight") : othersSpotlit ? qsTr("Add spotlight") : qsTr("Spotlight for everyone"),
                           icon: "spotlight-20", off: !spotlit && spotFull,
                           tip: spotlit ? qsTr("Stop highlighting this video for everyone in the meeting") : spotFull ? qsTr("No more people can be spotlighted") : qsTr("Highlight this video for everyone in the meeting") })
            }
            if (c.handRaised && c.lowerHandsOffered) add({ k: "lowerMyHand", t: qsTr("Lower my hand"), icon: "hand-right-off-20" })
            // Fit or fill your own video (a camera tile in the gallery).
            if (c.cameraOn && c.layout === "gallery" && !c.meOverlayShown) add(c.fitted("me")
                ? { k: "fill", t: qsTr("Fill frame"), icon: "scale-fill-20", tip: qsTr("Fill video to frame. Others may see more of your background than what your video shows.") }
                : { k: "fit", t: qsTr("Fit to frame"), icon: "scale-fit-20", tip: qsTr("Fit to frame") })
            return out
        }
        // Someone else.
        if (presenter && !c.oneOnOne && String(w.id || "").indexOf("28:") !== 0) add({ k: "mute", t: qsTr("Mute participant"), icon: "mic-off-20", off: !!w.muted })
        if (presenter && !!w.hand && c.lowerHandsOffered) add({ k: "lowerHand", t: qsTr("Lower hand"), icon: "hand-right-off-20" })
        // Pin for me: disabled once the pin area is full, or while they're
        // spotlighted.
        const pinOff = !pinned && (c.pinningFull || spotlit || managed)
        add({ k: pinned ? "unpin" : "pin", t: pinned ? qsTr("Unpin") : qsTr("Pin for me"), icon: pinned ? "pin-off-20" : "pin-20", off: pinOff,
              tip: pinOff ? (managed ? qsTr("Unavailable while presenters are managing what attendees see") : spotlit ? qsTr("Can't pin a participant that is spotlighted") : qsTr("You reached the maximum number of pins"))
                          : pinned ? qsTr("Unpin this video from your view") : qsTr("Pin this video to your view") })
        if (presenter && c.meeting) {
            if (managed) add({ k: spotlit ? "unspotlight" : "spotlight", t: spotlit ? qsTr("Take off screen") : qsTr("Bring on screen"), icon: "spotlight-20" })
            else add({ k: spotlit ? "unspotlight" : "spotlight", t: spotlit ? qsTr("Stop spotlighting") : othersSpotlit ? qsTr("Add spotlight") : qsTr("Spotlight for everyone"),
                       icon: "spotlight-20", off: !spotlit && spotFull,
                       tip: spotlit ? qsTr("Stop highlighting this video for everyone in the meeting") : spotFull ? qsTr("No more people can be spotlighted") : qsTr("Highlight this video for everyone in the meeting") })
        }
        // Fit or fill their video (while it shows).
        if (!!c.videoKeys[w.id] && !c.incomingVideoOff) add(c.fitted(w.id)
            ? { k: "fill", t: qsTr("Fill frame"), icon: "scale-fill-20" }
            : { k: "fit", t: qsTr("Fit to frame"), icon: "scale-fit-20" })
        if (w.room && c.roomRemoteOn) add({ k: "controlRoom", t: qsTr("Control Room System"), icon: "device-meeting-room-remote-20" })
        if (c.canReportPeople) { add({ sep: true }); add({ k: "report", t: qsTr("Report"), icon: "shield-error-20" }) }
        return out
    }
    signal chosen(string action, var person)

    FontMetrics { id: metrics; font.family: theme.font; font.pixelSize: 14 }
    readonly property real itemWidth: {
        let w = 0
        for (const it of items) if (!it.sep) w = Math.max(w, metrics.advanceWidth(it.t))
        return Math.max(134, Math.ceil(w * 100) / 100 + 36)
    }
    contentItem: Column {
        spacing: 2
        Repeater {
            model: root.items
            Item {
                id: mi
                required property var modelData
                readonly property bool sep: !!modelData.sep
                readonly property bool off: !!modelData.off
                width: root.itemWidth; height: sep ? 8.67 : 32
                Rectangle { visible: mi.sep; y: 4; width: parent.width; height: 0.67; color: theme.divider }
                Rectangle {
                    id: fill
                    visible: !mi.sep
                    anchors.fill: parent; radius: 4
                    color: hover.hovered && !mi.off ? theme.menuHover : "transparent"
                    FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.icon || ""; size: 20; color: theme.onFill(fill, mi.off ? theme.disabled : hover.hovered ? theme.text : theme.textStrong) }
                    Text {
                        x: 30; anchors.verticalCenter: parent.verticalCenter
                        text: mi.modelData.t || ""
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.onFill(fill, mi.off ? theme.disabled : hover.hovered ? theme.text : theme.textStrong)
                    }
                    HoverHandler { id: hover; cursorShape: mi.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
                    // Teams' title on the item.
                    ToolTip.visible: hover.hovered && !!mi.modelData.tip
                    ToolTip.delay: 500
                    ToolTip.text: mi.modelData.tip || ""
                    TapHandler {
                        enabled: !mi.sep && !mi.off
                        onTapped: { const w = root.who; root.close(); root.chosen(mi.modelData.k, w) }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: mi.modelData.t || ""
                }
            }
        }
    }
    function itemsForTest() { return items.map(it => it.sep ? "—" : (it.t + (it.off ? " (disabled)" : ""))) }
}
