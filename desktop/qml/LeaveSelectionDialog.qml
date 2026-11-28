import QtQuick

// Teams' multiselect speedbump (chat-app `j_`, data-tid
// "multiselect-speedbump-dialog"; seen on Teams desktop 26304 as OST Test 2,
// 2026-11-27): leaving a chat or channel while picking messages to forward
// asks first. A 600 wide dialog: "Discard and leave", "You're currently
// selecting messages to forward. Leaving now will discard your
// selection.", Cancel (keep picking) and Discard (drop the picks, then go
// where you were going).
ConfirmDialog {
    /// Where the click was going.
    property var go: null
    dialogWidth: 600
    title: qsTr("Discard and leave")
    body: qsTr("You're currently selecting messages to forward. Leaving now will discard your selection.")
    confirmText: qsTr("Discard")
    onCancelled: go = null
    onClosed: if (!visible) Qt.callLater(() => { if (!visible) go = null })
}
