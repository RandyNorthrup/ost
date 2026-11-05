import QtQuick

// Presence, as Fluent draws it in Teams: the presence icon (available
// check, away clock, busy, do not disturb, out of office, offline,
// unknown) at the badge size, on a white disc that shows through the
// icon's glyph, in Fluent's colours.
Item {
    id: badge
    property string presence: ""
    /// Badge size: Fluent's 6, 10, 12, 16, 20 or 28 px.
    property int total: 10
    readonly property string p: presence.toLowerCase()
    readonly property string kind: (p === "available" || p === "availableidle") ? "available"
        : (p === "away" || p === "berightback") ? "away"
        : (p === "busy" || p === "busyidle" || p === "inacall" || p === "inameeting" || p === "inaconferencecall") ? "busy"
        : (p === "donotdisturb" || p === "presenting" || p === "focusing" || p === "urgentinterruptionsonly") ? "dnd"
        : p === "outofoffice" ? "oof"
        : p === "offline" ? "offline"
        : "unknown"
    readonly property color ink: kind === "available" ? "#13A10E" : kind === "away" ? "#EAA300"
        : (kind === "busy" || kind === "dnd") ? "#D13438" : kind === "oof" ? "#C239B3" : theme.textSecondary
    visible: presence.length > 0
    width: total; height: total
    Rectangle {
        anchors.centerIn: parent
        width: badge.total; height: width; radius: width / 2
        color: theme.surface
    }
    FluentIcon {
        anchors.fill: parent
        size: badge.total
        name: "presence-" + badge.kind + "-" + (badge.total <= 10 ? 10 : badge.total <= 12 ? 12 : badge.total <= 16 ? 16 : 20)
        color: badge.ink
    }
    Accessible.name: presence
}
