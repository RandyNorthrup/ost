import QtQuick
import QtTest

// --kb-dialog-test (TASK-0183): the Keyboard shortcuts dialog's profile
// choice and Teams' React to the last message, as real key events.
// --kb-dialog-chat=<chat name> picks the chat (default: the first 1:1).
// KBTEST lines; pictures -kb-*.png. With a call up (--kb-dialog-call),
// Announce active speaker is pressed in the call window too.
Item {
    id: root
    property var win
    property int step: 0
    function log() { console.warn("KBTEST", Array.prototype.slice.call(arguments).map(a => typeof a === "string" ? a : JSON.stringify(a)).join(" ")) }
    function shot(n) { win.contentItem.grabToImage(r => r.saveToFile(win.shotPath.replace(".png", "-kb-" + n + ".png"))) }
    readonly property string chatName: (Qt.application.arguments.find(a => a.startsWith("--kb-dialog-chat=")) || "").slice(17).replace(/~/g, " ")
    TestCase { id: t; when: false; name: "kb" }
    property var callKeys: null
    Timer {
        interval: 900; repeat: true; running: root.win && root.win.backendReady
        onTriggered: {
            const w = root.win, d = w.kShortcuts, s = root.step++
            if (s === 0) { w.requestActivate(); t.keyClick(Qt.Key_Period, Qt.ControlModifier) }
            else if (s === 1) { root.log("open", d.visible, "profile", w.shortcutProfile, "chosen", d.chosen, "counts", ["chats_alt", "meetings_alt", "chats_meetings_alt"].map(p => d.changeCount(p))); root.shot("default") }
            else if (s === 2) { d.chosen = "chats_alt" }
            else if (s === 3) {
                const ch = []; for (const sec of d.sections) for (const i of sec.items) if (d.changed(i)) ch.push([i[0], d.keysOf(i)])
                root.log("slack preview", ch); root.shot("slack")
            }
            else if (s === 4) { d.chosen = "meetings_alt" }
            else if (s === 5) { const ch = []; for (const sec of d.sections) for (const i of sec.items) if (d.changed(i)) ch.push([i[0], d.keysOf(i)]); root.log("zoom preview", ch); d.changesFirst = true }
            else if (s === 6) { root.shot("zoom-top"); d.changesFirst = false; d.chosen = w.shortcutProfile }
            else if (s === 7) { t.keyClick(Qt.Key_Escape); t.keyClick(Qt.Key_Escape) }
            else if (s === 8) {
                root.log("closed", !d.visible)
                const c = (root.chatName ? w.kChatList.chats.find(c => (c.name || "").indexOf(root.chatName) >= 0) : null) || w.kChatList.chats.find(c => c.peerMri && c.peerMri !== "8:orgid:me") || w.kChatList.chats[0]
                root.log("chat", c ? c.name : "none")
                if (c) w.kBackend.selectChat(c.id, c.name)
            }
            else if (s === 11) { w.requestActivate(); t.keyClick(Qt.Key_R, Qt.ControlModifier | Qt.AltModifier) }
            else if (s === 12) { root.log("react", "forceBar", w.kConversation.forceBarId, "focusObject", String(w.activeFocusItem)); root.shot("react") }
            else if (s === 13) { t.keyClick(Qt.Key_Right) }
            else if (s === 14) { root.shot("react-right"); t.keyClick(Qt.Key_Escape) }
            else if (s === 15) { root.log("escape", "forceBar", JSON.stringify(w.kConversation.forceBarId), "composeFocused", w.kConversation.composeFocused) }
            else if (s === 16 && Qt.application.arguments.indexOf("--kb-dialog-call") >= 0) {
                const cw = w.kCallWindow
                root.log("call", w.kBackend.callState, "speaker", cw ? cw.speakerId : "")
                if (cw && cw.visible) {
                    root.callKeys = Qt.createQmlObject('import QtTest; TestCase { when: false; name: "kbcall" }', cw.contentItem)
                    cw.requestActivate()
                }
            }
            else if (s === 17 && root.callKeys) root.callKeys.keyClick(Qt.Key_S, Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier)
            else if (s > 18) { Qt.quit() }
        }
    }
}
