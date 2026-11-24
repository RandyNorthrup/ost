import QtQuick
import QtTest

// --keys-test: press OST's keyboard shortcuts as real key events and
// check what each did; captures the shortcuts dialog. Loaded only for
// the test, so normal runs don't need the QtTest module.
Item {
    id: root
    property var win
    property int step: 0
    property var fails: []
    function check(name, ok) { console.warn("KEYS", ok ? "ok  " : "FAIL", name); if (!ok) fails.push(name) }
    TestCase { id: t; when: false; name: "keys" }
    Timer {
        interval: 700; repeat: true; running: root.win && root.win.backendReady
        onTriggered: {
            const w = root.win, s = root.step++
            if (s === 0) { w.requestActivate(); t.keyClick(Qt.Key_Period, Qt.ControlModifier) }
            else if (s === 1) {
                root.check("Ctrl+. opens the shortcuts", w.kShortcuts.visible)
                w.contentItem.grabToImage(r => r.saveToFile(w.shotPath.replace(".png", "-keys.png")))
            }
            else if (s === 2) { t.keyClick("m"); t.keyClick("u"); t.keyClick("t"); t.keyClick("e") }
            else if (s === 3) { w.contentItem.grabToImage(r => r.saveToFile(w.shotPath.replace(".png", "-keys-filter.png"))) }
            else if (s === 4) { t.keyClick(Qt.Key_Escape); t.keyClick(Qt.Key_Escape) }
            else if (s === 5) { root.check("Esc closes the shortcuts", !w.kShortcuts.visible); t.keyClick(Qt.Key_3, Qt.ControlModifier) }
            else if (s === 6) { root.check("Ctrl+3 opens Calendar", w.kRail.current === "calendar"); t.keyClick(Qt.Key_2, Qt.ControlModifier) }
            else if (s === 7) { root.check("Ctrl+2 opens Chat", w.kRail.current === "chat"); t.keyClick(Qt.Key_U, Qt.ControlModifier | Qt.AltModifier) }
            else if (s === 8) { root.check("Ctrl+Alt+U shows unread", w.kChatList.chipFilter === "unread"); t.keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.AltModifier) }
            else if (s === 9) { root.check("Ctrl+Alt+Z clears filters", w.kChatList.chipFilter === ""); t.keyClick(Qt.Key_F, Qt.ControlModifier | Qt.ShiftModifier) }
            else if (s === 10) { root.check("Ctrl+Shift+F opens the filter", w.kChatList.filtering); t.keyClick(Qt.Key_Escape) }
            else if (s === 11) { const c = w.kChatList.chats.find(c => c.peerMri && c.peerMri !== "8:orgid:me") || w.kChatList.chats[0]; w.kBackend.selectChat(c.id, c.name) }
            else if (s === 13) { t.keyClick(Qt.Key_2, Qt.AltModifier) }
            else if (s === 14) { root.check("Alt+2 opens the Shared tab", w.kConversation.tab === "Shared"); t.keyClick(Qt.Key_1, Qt.AltModifier) }
            else if (s === 15) { root.check("Alt+1 opens the Chat tab", w.kConversation.tab === ""); t.keyClick(Qt.Key_F, Qt.ControlModifier) }
            else if (s === 16) { root.check("Ctrl+F opens find", w.kConversation.finding); t.keyClick(Qt.Key_Escape) }
            else if (s === 17) { t.keyClick(Qt.Key_P, Qt.AltModifier) }
            else if (s === 18) { root.check("Alt+P opens details", w.kConversation.detailsOpen); t.keyClick(Qt.Key_P, Qt.AltModifier) }
            else if (s === 19) { root.check("Alt+P closes details", !w.kConversation.detailsOpen); t.keyClick(Qt.Key_R, Qt.ControlModifier) }
            else if (s === 20) { root.check("Ctrl+R focuses the compose box", w.kConversation.composeFocused) }
            else if (s === 21) { console.warn("KEYS done, failures:", root.fails.length); Qt.quit() }
        }
    }
}
