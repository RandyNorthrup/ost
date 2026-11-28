import QtQuick

// Forward ▸ Multiple messages (Teams' forward multiselect, 282978 `E`;
// 763654 `V`): which messages are picked and why one can't be. At most
// forwardMultiselectSelectionLimit (5) at once; deleted and system rows
// get no checkbox; unsent and scheduled messages, and in a channel a
// meeting's post, get a disabled one with Teams' reason
// (forward_multiselect_*_validation; a channel meeting's post says "This
// message can't be forwarded.", seen on Teams desktop 26304 as OST Test 2,
// 2026-11-27). The view shows the picks and the selection bar while
// `selecting`.
QtObject {
    id: sel
    /// The view's messages (the picks are forwarded oldest first).
    property var messages: []
    /// A channel's posts list or post view (meeting posts are disabled
    /// rather than left out).
    property bool channel: false
    property bool selecting: false
    property var selectedIds: []
    readonly property int limit: 5
    /// "none" (no checkbox), "" (can be picked) or why it can't be.
    function reason(m) {
        if (!m || m.deleted) return "none"
        if (m.kind === "call" && sel.channel && !!m.meeting_join_url) return qsTr("This message can't be forwarded.")
        if (m.kind !== "message") return "none"
        if (m.scheduled_at) return qsTr("Scheduled messages can't be forwarded until they're sent.")
        if (m.send_state) return qsTr("Undelivered messages can't be forwarded.")
        if (selectedIds.indexOf(m.id) < 0 && selectedIds.length >= limit) return qsTr("You can only forward up to %1 messages at a time.").arg(limit)
        return ""
    }
    function isSelected(id) { return selectedIds.indexOf(id) >= 0 }
    function toggle(m) {
        if (!m || reason(m) !== "" && selectedIds.indexOf(m.id) < 0) return
        const i = selectedIds.indexOf(m.id)
        const next = selectedIds.slice()
        if (i >= 0) next.splice(i, 1); else next.push(m.id)
        selectedIds = next
    }
    function start(m) { selectedIds = m ? [m.id] : []; selecting = true }
    function stop() { selecting = false; selectedIds = [] }
    /// The picked messages, oldest first.
    function picked() {
        const ids = selectedIds.slice().sort((a, b) => Number(a) - Number(b))
        return ids.map(id => (sel.messages || []).find(m => m.id === id)).filter(m => !!m)
    }
}
