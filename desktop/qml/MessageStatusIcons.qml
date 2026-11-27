import QtQuick
import QtQuick.Controls.Basic

// A message's status icons, in Teams' MessageStatusBar order (763654
// `Lt`): Saved by you (the bookmark), then your reminder (the filled
// alarm, Miz), both 16 px in colorPaletteBerryForeground1, each with
// Teams' tooltip: "Saved by you. Others won't see that it was saved.",
// "Reminder due at {time}." today, else "Reminder due on {date}."
// (month/day).
Row {
    id: root
    property var message: ({})
    readonly property real due: message && message.reminder_due ? message.reminder_due : 0
    spacing: 4
    function dueTip(t) {
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString()) return qsTr("Reminder due at %1.").arg(theme.time(d))
        return qsTr("Reminder due on %1.").arg((d.getMonth() + 1) + "/" + d.getDate())
    }
    FluentIcon {
        visible: !!root.message && root.message.saved === true
        name: "bookmark-16-filled"; size: 16; color: theme.savedFg
        HoverHandler { id: savedHover }
        ToolTip {
            visible: savedHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: qsTr("Saved by you. Others won't see that it was saved."); font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.name: qsTr("Saved by you. Others won't see that it was saved.")
    }
    FluentIcon {
        visible: root.due > 0
        name: "clock-alarm-16-filled"; size: 16; color: theme.savedFg
        HoverHandler { id: dueHover }
        ToolTip {
            visible: dueHover.hovered; delay: 500
            y: -height - 4; padding: 8
            background: FluentSurface { depth: 16; radius: 4 }
            contentItem: Text { text: root.due > 0 ? root.dueTip(root.due) : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        }
        Accessible.name: root.due > 0 ? root.dueTip(root.due) : ""
    }
}
