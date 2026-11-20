import QtQuick
import QtQuick.Window

// A personal app in a window of its own: Teams' app bar menu "Open in new
// window" (measured on winpc 2026-11-20 with Planner and Whiteboard).
// - The window opens 946 x 593 with Teams' child-window title row, titled
//   with the app's name (12/16), and its Settings and more.
// - Under it the app's personal page in Teams' host, as in the main
//   window: a full-screen app (Planner, OneNote, Shifts, Clipchamp) fills
//   the window; another (Whiteboard) gets Teams' app header (entity-header,
//   61 tall: the 32 px icon at 20, the name 18/25.7 bold at 72, "More
//   <app> actions" at the right; no Present now).
// The page is told it is in a window of its own (getContext
// isMultiWindow).
Window {
    id: win
    /// The app: {key, name, appId}.
    property var app: ({})
    property bool pinned: false
    title: app.name || ""
    width: 946; height: 593
    color: theme.surface
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)

    ChildWindowTitleBar {
        id: titleRow
        title: win.title
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    WebApp {
        id: page
        anchors { top: titleRow.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        appName: win.app.name || ""; appId: win.app.appId || ""
        teamsHost: true; personalApp: true; presentNow: false
        hostContext: ({ isMultiWindow: true })
    }
    function pageForTest() { return page }
}
