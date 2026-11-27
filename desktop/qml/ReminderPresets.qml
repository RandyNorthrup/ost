import QtQuick

// Teams' Remind me presets (735788 `w2`), for the message menu and the
// Reminders view's Edit reminder: Now; Later today, an hour on rounded to
// the half hour (under :15 down to :00, under :45 to :30, else the next
// hour); Tomorrow at 9:00 AM; Next week, that week's Monday at 9:00 AM;
// Custom. With a reminder set, a divider and Remove reminder follow.
QtObject {
    function times(now) {
        const later = new Date(now.getTime() + 3600000)
        const mins = later.getMinutes()
        if (mins < 15) later.setMinutes(0, 0, 0)
        else if (mins < 45) later.setMinutes(30, 0, 0)
        else later.setHours(later.getHours() + 1, 0, 0, 0)
        const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0, 0, 0)
        const week = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7, 9, 0, 0, 0)
        week.setDate(week.getDate() - (week.getDay() + 6) % 7)
        return { now: now, later: later, tomorrow: tomorrow, week: week }
    }
    // Teams' weekday and time ("Sat, 9:00 AM").
    function dayAndTime(d) { return Qt.locale().toString(d, "ddd") + ", " + theme.time(d) }
    function submenu(t, withRemove) {
        const sub = [
            { key: "now", label: qsTr("Now") },
            { key: "later", label: qsTr("Later today"), secondary: theme.time(t.later) },
            { key: "tomorrow", label: qsTr("Tomorrow"), secondary: dayAndTime(t.tomorrow) },
            { key: "week", label: qsTr("Next week"), secondary: dayAndTime(t.week) },
            { key: "custom", label: qsTr("Custom") }]
        if (withRemove) sub.push({ separator: true }, { key: "remove", label: qsTr("Remove reminder") })
        return sub
    }
    /// The due time a preset stands for (null for Custom / Remove).
    function at(key, t) { return key === "now" ? new Date() : key === "later" ? t.later : key === "tomorrow" ? t.tomorrow : key === "week" ? t.week : null }
}
