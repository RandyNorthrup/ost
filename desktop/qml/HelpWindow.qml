import QtQuick
import QtQuick.Window

// Help (F1, Settings and more ▸ Help): Teams' Help window (measured on
// winpc 2026-11-10: 946 x 593, the child-window title row "Help", then the
// Help app), with OST's help (HelpView).
Window {
    id: win
    title: "Help"
    width: 946; height: 593
    minimumWidth: 480; minimumHeight: 360
    color: theme.surface
    property bool pinned: false
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
    Rectangle { anchors.fill: parent; color: theme.surface }
    ChildWindowTitleBar { id: titleRow; title: win.title; width: parent.width; pinned: win.pinned; onTogglePin: win.pinned = !win.pinned }
    HelpView { id: view; anchors { top: titleRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom } }
    Shortcut { sequence: "Escape"; onActivated: win.close() }
    function viewForTest() { return view }
}
