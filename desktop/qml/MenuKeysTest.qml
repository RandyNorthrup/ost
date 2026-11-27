import QtQuick
import QtTest

// --menu-keys-test (TASK-0362): MenuPopup's keyboard, as Teams' Fluent
// menus take it, with real key events. First a menu of every kind of row
// (a heading, a disabled row, a separator, a split row, a submenu row),
// then, once signed in, the chat list's ··· More list options (a split
// Mark all as read with its submenu). MENUKEYS ok / FAIL lines, then
// "MENUKEYS done, failures: N". With --shots=<dir>: menukeys-*.png.
Item {
    id: root
    property var win
    property int step: 0
    property var fails: []
    property var log: []
    readonly property string shotDir: (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "").slice(8)
    function check(name, ok) { console.warn("MENUKEYS", ok ? "ok  " : "FAIL", name); if (!ok) fails.push(name) }
    function shot(n) { if (shotDir) win.contentItem.grabToImage(r => r.saveToFile(shotDir + "/menukeys-" + n + ".png")) }
    function at(m, i, part) { return m.current === i && m.currentPart === (part || "") }
    TestCase { id: t; when: false; name: "menukeys" }
    Component.onCompleted: console.warn("MENUKEYS loaded")

    // Something to give the focus back to, and what Tab goes on to.
    Rectangle {
        id: opener
        parent: root.win ? root.win.contentItem : root
        x: 300; y: 120; width: 120; height: 32; color: "transparent"
        activeFocusOnTab: true
        Rectangle {
            id: after
            x: 0; y: 40; width: 120; height: 32; color: "transparent"
            activeFocusOnTab: true
        }
        MenuPopup {
            id: menu
            y: 34
            property var picks: []
            items: [
                { heading: "Group" },
                { label: "Alpha" },
                { label: "Bravo", enabled: false },
                { separator: true },
                { label: "Charlie", split: true, submenu: [{ label: "One" }, { label: "Two" }] },
                { label: "Delta", submenu: [{ label: "Echo" }, { label: "Foxtrot", keys: "X" }] },
                { label: "Charlie two" }
            ]
            onPicked: i => picks.push("p" + i)
            onSubPicked: (i, j) => picks.push("s" + i + "." + j)
        }
    }
    // A window shortcut on Escape must not take the menu's Esc.
    property int escShortcuts: 0
    Shortcut { sequence: "Escape"; enabled: menu.opened; onActivated: root.escShortcuts++ }

    Timer {
        interval: 300; repeat: true; running: !!root.win
        onTriggered: {
            const w = root.win, s = root.step++, sub = menu.subMenu
            const k = key => t.keyClick(key)
            if (s === 0) { w.requestActivate(); opener.forceActiveFocus(); menu.open() }
            else if (s === 1) {
                root.check("opens with the focus on its first row, past the heading", menu.opened && root.at(menu, 1) && w.activeFocusItem && menu.owns(w.activeFocusItem))
                root.check("no outline after a pointer open", !menu.focusRing)
                k(Qt.Key_Down)
            }
            else if (s === 2) {
                root.check("Down: the disabled row is a stop", root.at(menu, 2) && menu.focusRing)
                root.check("the row itself has the focus (for screen readers)", w.activeFocusItem === menu.rowAt(2))
                k(Qt.Key_Down)
            }
            else if (s === 3) { root.check("Down: past the separator to the split row's label", root.at(menu, 4)); k(Qt.Key_Down) }
            else if (s === 4) { root.check("Down: the split row's chevron part, focused", root.at(menu, 4, "chevron") && w.activeFocusItem === menu.rowAt(4).chevronItem); k(Qt.Key_Down) }
            else if (s === 5) { k(Qt.Key_Down) }
            else if (s === 6) { root.check("Down reaches the last row", root.at(menu, 6)); root.shot("down"); k(Qt.Key_Down) }
            else if (s === 7) { root.check("Down wraps to the first row", root.at(menu, 1)); k(Qt.Key_Up) }
            else if (s === 8) { root.check("Up wraps to the last row", root.at(menu, 6)); k(Qt.Key_Home) }
            else if (s === 9) { root.check("Home: the first row", root.at(menu, 1)); k(Qt.Key_End) }
            else if (s === 10) { root.check("End: the last row", root.at(menu, 6)); k(Qt.Key_PageUp) }
            else if (s === 11) { root.check("PageUp: the first row", root.at(menu, 1)); k(Qt.Key_PageDown) }
            else if (s === 12) { root.check("PageDown: the last row", root.at(menu, 6)); k(Qt.Key_C) }
            else if (s === 13) { root.check("c: the next row starting with c, wrapping", root.at(menu, 4)); k(Qt.Key_C) }
            else if (s === 14) { root.check("c again: the one after", root.at(menu, 6)); k(Qt.Key_Z) }
            else if (s === 15) { root.check("z: no match, stays", root.at(menu, 6)); k(Qt.Key_Home); k(Qt.Key_Down); k(Qt.Key_Down) }
            else if (s === 16) { root.check("on the split row", root.at(menu, 4)); k(Qt.Key_Right) }
            else if (s === 17) { root.check("Right: the split's chevron part", root.at(menu, 4, "chevron") && !(sub && sub.opened)); k(Qt.Key_Left) }
            else if (s === 18) { root.check("Left: back on the label part", root.at(menu, 4)); k(Qt.Key_Right); k(Qt.Key_Right) }
            else if (s === 19) {
                const m = menu.subMenu
                root.check("Right on the chevron: the submenu, on its first row, with the keys", !!m && m.opened && root.at(m, 0) && m.focusRing && m.owns(w.activeFocusItem))
                root.shot("submenu")
                k(Qt.Key_Down)
            }
            else if (s === 20) { root.check("Down in the submenu", root.at(sub, 1)); k(Qt.Key_Left) }
            else if (s === 21) { root.check("Left closes only the submenu, back on its row", !sub.opened && menu.opened && root.at(menu, 4, "chevron") && w.activeFocusItem && menu.owns(w.activeFocusItem)); k(Qt.Key_Return) }
            else if (s === 22) { root.check("Enter on the chevron opens the submenu", sub.opened && root.at(sub, 0)); k(Qt.Key_Escape) }
            else if (s === 23) { root.check("Esc closes only the submenu", !sub.opened && menu.opened); k(Qt.Key_Down) }
            else if (s === 24) { root.check("Down to the submenu row", root.at(menu, 5)); k(Qt.Key_Space) }
            else if (s === 25) { root.check("Space opens its submenu", sub.opened && sub.items.length === 2 && sub.items[0].label === "Echo"); k(Qt.Key_X) }
            else if (s === 26) {
                root.check("a row's own key (X) picks it in the submenu and closes the menu", menu.picks.indexOf("s5.1") >= 0 && !menu.opened && !sub.opened)
                root.check("the focus is back where it was", opener.activeFocus)
                menu.open()
            }
            else if (s === 27) { k(Qt.Key_Down); k(Qt.Key_Return) }
            else if (s === 28) { root.check("Enter on a disabled row does nothing", menu.opened && menu.picks.indexOf("p2") < 0); k(Qt.Key_Up); k(Qt.Key_Return) }
            else if (s === 29) { root.check("Enter picks a row and closes", menu.picks.indexOf("p1") >= 0 && !menu.opened && opener.activeFocus); menu.open() }
            else if (s === 30) { k(Qt.Key_Escape) }
            else if (s === 31) {
                root.check("Esc closes the menu, the focus back on the opener", !menu.opened && opener.activeFocus)
                root.check("a window's Escape shortcut didn't take it", root.escShortcuts === 0)
                menu.open()
            }
            else if (s === 32) { k(Qt.Key_Tab) }
            else if (s === 33) { root.check("Tab closes and goes on past the opener", !menu.opened && after.activeFocus); opener.forceActiveFocus(); menu.open() }
            else if (s === 34) { t.keyClick(Qt.Key_Tab, Qt.ShiftModifier) }
            else if (s === 35) { root.check("Shift+Tab closes, the focus on the opener", !menu.opened && opener.activeFocus); menu.open() }
            else if (s === 36) { const r = menu.rowAt(6); t.mouseMove(r, 20, r.height / 2) }
            else if (s === 37) { root.check("hovering a row moves the keyboard there", root.at(menu, 6)); k(Qt.Key_Up) }
            else if (s === 38) {
                root.check("and the keys go on from it", root.at(menu, 5) && menu.subMenu && !menu.subMenu.opened)
                k(Qt.Key_Escape)
                if (!w.backendReady) { console.warn("MENUKEYS (not signed in: skipping the chat list's menu)"); root.step = 100 }
            }
            // The chat list's ··· More list options (signed in).
            else if (s === 39) { opener.forceActiveFocus(); w.kChatList.openListMenuForTest() }
            else if (s === 40) {
                const m = w.kChatList.listMenuForTest()
                root.check("More list options: open with the focus on Mark all as read", m.opened && m.current === 0 && m.owns(w.activeFocusItem))
                k(Qt.Key_Down)
            }
            else if (s === 41) {
                const m = w.kChatList.listMenuForTest(), it = m.items[0]
                root.check("More list options: Down", it.split ? root.at(m, 0, "chevron") : root.at(m, 1))
                root.shot("chatlist-down")
                if (it.split) k(Qt.Key_Right)
            }
            else if (s === 42) {
                const m = w.kChatList.listMenuForTest()
                if (m.items[0].split) root.check("More list options: Right opens Mark all as read's options", m.subMenu && m.subMenu.opened && root.at(m.subMenu, 0))
                root.shot("chatlist-submenu")
                k(Qt.Key_Escape)
            }
            else if (s === 43) { k(Qt.Key_Escape) }
            else if (s === 44) {
                const m = w.kChatList.listMenuForTest()
                root.check("More list options: Esc, Esc closes it", !m.opened && opener.activeFocus)
                root.step = 100
            }
            else if (s > 100) { console.warn("MENUKEYS done, failures:", root.fails.length, JSON.stringify(root.fails)); Qt.quit() }
        }
    }
}
