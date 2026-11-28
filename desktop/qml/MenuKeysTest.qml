import QtQuick
import QtTest

// --menu-keys-test (TASK-0362): MenuPopup's keyboard, as Teams' Fluent
// menus take it, with real key events. First a menu of every kind of row
// (a heading, a disabled row, a separator, a split row, a submenu row),
// then, once signed in, the chat list's ··· More list options (a split
// Mark all as read with its submenu) and a chat's ··· menu (typeahead to
// Move to section and its submenu). TASK-0370: a header strip's buttons in
// the arrow-key loop (a test menu, then a chat message's right-click menu
// and its reactions), and the focus back on a button that can't take it
// by itself (a test BarButton, then a message's ··· More options, its bar
// staying up). MENUKEYS ok / FAIL lines, then
// "MENUKEYS done, failures: N". With --shots=<dir>: menukeys-*.png.
Item {
    id: root
    property var win
    property int step: 0
    property var fails: []
    property var log: []
    property string rowId: ""
    property int moveRow: -1
    property string msgId: ""
    property int waits: 0
    readonly property string shotDir: (Qt.application.arguments.find(a => a.startsWith("--shots=")) || "").slice(8)
    function check(name, ok) {
        console.warn("MENUKEYS", ok ? "ok  " : "FAIL", name)
        if (ok) return
        fails.push(name)
        console.warn("MENUKEYS   window active:", win.active, "focus:", String(win.activeFocusItem), "menu open:", menu.opened, "row:", menu.current, menu.currentPart, "submenu open:", !!menu.subMenu && menu.subMenu.opened)
    }
    function shot(n) { if (shotDir) win.contentItem.grabToImage(r => r.saveToFile(shotDir + "/menukeys-" + n + ".png")) }
    function at(m, i, part) { return m.current === i && m.currentPart === (part || "") }
    // Click a button, then the pointer off it and off the menu it opens
    // (a hovered row would take the keyboard's row).
    function clickAway(item) { t.mouseClick(item); t.mouseMove(win.contentItem, win.width / 2, win.height - 4) }
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
                { label: "Charlie two", keys: "Ctrl+G" }
            ]
            onPicked: i => picks.push("p" + i)
            onSubPicked: (i, j) => picks.push("s" + i + "." + j)
        }
    }
    // A button that can't take the focus by itself (Teams: clicking one
    // focuses it), opening a menu with a header strip of three buttons, as
    // the message menu's reactions (TASK-0370).
    BarButton {
        id: btn
        parent: root.win ? root.win.contentItem : root
        // Clear of the chat list (its rows' own hover ···) and of the
        // other test items; the pointer leaves it after each click.
        x: (root.win ? root.win.width : 1000) - 60; y: 120; icon: "more-horizontal-20"; tip: "Test button"
        onClicked: bmenu.open()
        MenuPopup {
            id: bmenu
            x: btn.width - width; y: 34
            property var log: []
            header: Component {
                Row {
                    readonly property var keyItems: [h0, h1, h2]
                    Item { id: h0; width: 32; height: 31; function activate() { bmenu.log.push("h0"); bmenu.close() } }
                    Item { id: h1; width: 32; height: 31; function activate() { bmenu.log.push("h1"); bmenu.close() } }
                    Item { id: h2; width: 32; height: 31; function activate() { bmenu.log.push("h2"); bmenu.close() } }
                }
            }
            items: [{ label: "Uno" }, { separator: true }, { label: "Dos" }]
            onPicked: i => log.push("p" + i)
        }
    }
    // A window shortcut on Escape must not take the menu's Esc.
    property int escShortcuts: 0
    Shortcut { sequence: "Escape"; enabled: menu.opened; onActivated: root.escShortcuts++ }
    // Escape with a modifier still runs its shortcut (Teams' Shift+Esc;
    // Ctrl+Esc here, which nothing else uses) and closes the menu.
    property int ctrlEscShortcuts: 0
    Shortcut { sequence: "Ctrl+Esc"; onActivated: root.ctrlEscShortcuts++ }

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
                root.check("the row itself has the focus (for screen readers)", w.activeFocusItem === menu.rowAt(2).focusItem)
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
                t.keyClick(Qt.Key_G, Qt.ControlModifier)
            }
            else if (s === 39) {
                root.check("a row's own chord (Ctrl+G) picks it", menu.picks.indexOf("p6") >= 0 && !menu.opened)
                menu.open()
            }
            else if (s === 40) { t.keyClick(Qt.Key_Escape, Qt.ControlModifier) }
            else if (s === 41) {
                root.check("Ctrl+Esc closes the menu and runs its shortcut", !menu.opened && root.ctrlEscShortcuts === 1)
                menu.items = [{ label: "Golf", submenu: [{ label: "G1" }, { label: "G2" }] }, { label: "Hotel", submenu: [{ label: "H1" }, { label: "H2" }] }]
                menu.open()
            }
            // The pointer from one submenu row to another: the open
            // submenu shows the new list, with the keys on its first row.
            else if (s === 42) { const r = menu.rowAt(0); t.mouseMove(r, 20, r.height / 2) }
            else if (s === 43) { const r = menu.rowAt(1); t.mouseMove(r, 20, r.height / 2) }
            else if (s === 44) {
                const m = menu.subMenu
                root.check("hover from one submenu row to another: its list, the keys on its first row", m.opened && m.items[0].label === "H1" && root.at(m, 0) && m.keysHere)
                k(Qt.Key_Down)
            }
            else if (s === 45) {
                root.check("and Down moves in that submenu", root.at(menu.subMenu, 1) && root.at(menu, 1))
                // The pointer into the submenu, then back on its row: the
                // keys in the parent, the submenu still open.
                const r = menu.subMenu.rowAt(0); t.mouseMove(r, 20, r.height / 2)
            }
            else if (s === 46) { const r = menu.rowAt(1); t.mouseMove(r, 30, r.height / 2) }
            else if (s === 47) {
                root.check("the pointer back on the submenu's row: the keys there, the submenu open", menu.keysHere && menu.subMenu.opened && root.at(menu, 1))
                k(Qt.Key_Right)
            }
            else if (s === 48) {
                root.check("Right there goes into the open submenu, on its first row", menu.subMenu.keysHere && root.at(menu.subMenu, 0))
                k(Qt.Key_Escape); k(Qt.Key_Escape)
            }
            // A header strip and a button opener (TASK-0370).
            else if (s === 49) { after.forceActiveFocus(); root.clickAway(btn) }
            else if (s === 50) {
                const hk = bmenu.headerKeys()
                root.check("a button's menu with a header opens on the header's first button", bmenu.opened && root.at(bmenu, 0, "header") && hk.length === 3 && w.activeFocusItem === hk[0])
                root.check("no outline after the click", !bmenu.focusRing)
                k(Qt.Key_Down)
            }
            else if (s === 51) { root.check("Down: the header's second button, focused, outlined", root.at(bmenu, 1, "header") && w.activeFocusItem === bmenu.headerKeys()[1] && bmenu.focusRing); k(Qt.Key_Down) }
            else if (s === 52) { root.check("Down: the header's last button", root.at(bmenu, 2, "header")); k(Qt.Key_Down) }
            else if (s === 53) { root.check("Down from the header's last button: the first row", root.at(bmenu, 0) && w.activeFocusItem === bmenu.rowAt(0).focusItem); root.shot("header-row"); k(Qt.Key_Down) }
            else if (s === 54) { root.check("Down: past the separator to the last row", root.at(bmenu, 2)); k(Qt.Key_Down) }
            else if (s === 55) { root.check("Down from the last row wraps to the header's first button", root.at(bmenu, 0, "header") && w.activeFocusItem === bmenu.headerKeys()[0]); k(Qt.Key_Up) }
            else if (s === 56) { root.check("Up from the header's first button wraps to the last row", root.at(bmenu, 2)); k(Qt.Key_Home) }
            else if (s === 57) { root.check("Home: the header's first button", root.at(bmenu, 0, "header")); k(Qt.Key_End) }
            else if (s === 58) { root.check("End: the last row", root.at(bmenu, 2)); k(Qt.Key_Home); k(Qt.Key_Right) }
            else if (s === 59) { root.check("Right doesn't move in the header", root.at(bmenu, 0, "header")); k(Qt.Key_Left) }
            else if (s === 60) { root.check("Left doesn't either, nor close the menu", root.at(bmenu, 0, "header") && bmenu.opened); k(Qt.Key_Down); k(Qt.Key_Return) }
            else if (s === 61) {
                root.check("Enter on a header button runs it and closes the menu", bmenu.log.indexOf("h1") >= 0 && !bmenu.opened)
                root.check("a pick gives the focus back to where it was", after.activeFocus && !btn.activeFocus)
                after.forceActiveFocus(); root.clickAway(btn)
            }
            else if (s === 62) { k(Qt.Key_Space) }
            else if (s === 63) {
                root.check("Space on a header button runs it", bmenu.log.indexOf("h0") >= 0 && !bmenu.opened)
                after.forceActiveFocus(); root.clickAway(btn)
            }
            else if (s === 64) { k(Qt.Key_Escape) }
            else if (s === 65) {
                root.check("Esc: the focus on the clicked button (not where it was), outlined", !bmenu.opened && btn.activeFocus && !after.activeFocus && btn.focusRingShown)
                root.shot("button-focus")
                after.forceActiveFocus(); root.clickAway(btn)
            }
            else if (s === 66) { t.keyClick(Qt.Key_Tab, Qt.ShiftModifier) }
            else if (s === 67) { root.check("Shift+Tab: the focus on the clicked button", !bmenu.opened && btn.activeFocus); k(Qt.Key_Return) }
            else if (s === 68) { root.check("Enter on the focused button opens its menu again", bmenu.opened && root.at(bmenu, 0, "header")); k(Qt.Key_Escape) }
            else if (s === 69) { root.check("and Esc gives it the focus back", !bmenu.opened && btn.activeFocus); after.forceActiveFocus(); root.clickAway(btn) }
            else if (s === 70) { k(Qt.Key_Tab) }
            else if (s === 71) {
                root.check("Tab: closes, the focus goes on past the button", !bmenu.opened && !btn.activeFocus && !!w.activeFocusItem && !bmenu.owns(w.activeFocusItem))
                if (!w.backendReady) { console.warn("MENUKEYS (not signed in: skipping the chat list's and the message menus)"); root.step = 150 }
                else root.step = 80
            }
            // The chat list's ··· More list options (signed in).
            else if (s === 80) { t.mouseMove(w.contentItem, w.width / 2, w.height - 4); opener.forceActiveFocus(); w.kChatList.openListMenuForTest() }
            else if (s === 81) {
                const m = w.kChatList.listMenuForTest()
                root.check("More list options: open with the focus on Mark all as read", m.opened && m.current === 0 && m.owns(w.activeFocusItem))
                k(Qt.Key_Down)
            }
            else if (s === 82) {
                const m = w.kChatList.listMenuForTest(), it = m.items[0]
                root.check("More list options: Down", it.split ? root.at(m, 0, "chevron") : root.at(m, 1))
                root.shot("chatlist-down")
                if (it.split) k(Qt.Key_Right)
            }
            else if (s === 83) {
                const m = w.kChatList.listMenuForTest()
                if (m.items[0].split) root.check("More list options: Right opens Mark all as read's options", m.subMenu && m.subMenu.opened && root.at(m.subMenu, 0))
                root.shot("chatlist-submenu")
                k(Qt.Key_Escape)
            }
            else if (s === 84) { k(Qt.Key_Escape) }
            else if (s === 85) {
                const m = w.kChatList.listMenuForTest()
                root.check("More list options: Esc, Esc closes it, the focus on its ··· button (Teams; TASK-0370)", !m.opened && !!m.parent && m.parent.activeFocus && !opener.activeFocus)
                // A chat's ··· menu: its Move to section submenu.
                const id = w.kChatList.chats.map(c => c.id).find(i => !!w.kChatList.rowsForTest[i])
                if (!id) { root.check("a chat row to open the menu of", false); root.step = 150; return }
                root.rowId = id
                opener.forceActiveFocus()
                w.kChatList.openRowMenuForTest(id)
            }
            else if (s === 86) {
                const m = w.kChatList.rowsForTest[root.rowId].menu()
                root.check("chat menu: open with the focus on its first row", m.opened && m.current === 0 && m.owns(w.activeFocusItem))
                root.moveRow = m.items.findIndex(i => i.key === "move")
                // Typeahead to Move to section: m goes from row to row
                // starting with M (Mark as read, Manage notifications, Move).
                for (let n = 0; n < m.items.length && m.current !== root.moveRow; n++) k(Qt.Key_M)
            }
            else if (s === 87) {
                const m = w.kChatList.rowsForTest[root.rowId].menu()
                root.check("chat menu: M, M... reaches Move to section", m.current === root.moveRow && m.focusRing)
                root.shot("chatrow-move")
                k(Qt.Key_Right)
            }
            else if (s === 88) {
                const m = w.kChatList.rowsForTest[root.rowId].menu()
                root.check("chat menu: Right opens Move to section on its first row", !!m.subMenu && m.subMenu.opened && root.at(m.subMenu, 0) && m.subMenu.owns(w.activeFocusItem) && !m.keysHere)
                root.shot("chatrow-submenu")
                k(Qt.Key_Left)
            }
            else if (s === 89) {
                const m = w.kChatList.rowsForTest[root.rowId].menu()
                root.check("chat menu: Left back on Move to section", !m.subMenu.opened && m.opened && m.current === root.moveRow && m.keysHere)
                k(Qt.Key_Escape)
            }
            else if (s === 90) {
                const m = w.kChatList.rowsForTest[root.rowId].menu()
                root.check("chat menu: Esc closes it, the focus back", !m.opened && opener.activeFocus)
                // --open-chat=<id>, or a one-on-one chat (has messages).
                const one = w.kChatList.chats.find(c => !!c.peerMri && !c.isSelf)
                const want = (Qt.application.arguments.find(a => a.startsWith("--open-chat=")) || "").slice(12) || (one ? one.id : root.rowId)
                if (backend.currentChatId !== want) backend.selectChat(want, (w.kChatList.chats.find(c => c.id === want) || { name: "" }).name)
                root.waits = 0
            }
            // A chat message's right-click menu: its reactions in the loop.
            else if (s === 91) {
                const msgs = JSON.parse(backend.messagesJson || "[]").filter(m => m.kind === "message" && !m.deleted && !m.send_state && !m.scheduled_at)
                const m = msgs.pop()
                if (!m || !w.kConversation.hoverBarForTest(m.id)) {
                    if (++root.waits < 80) { root.step--; return }
                    root.check("a chat with a message to open the menu of", false); root.step = 150; return
                }
                root.msgId = m.id
                w.kConversation.focusCompose()
                w.kConversation.openMessageMenu(m, w.kConversation, true, 300, 200)
            }
            else if (s === 92) {
                const mm = w.kConversation.messageMenuForTest(), hk = mm.headerKeys()
                root.check("message menu (right-click): opens on the first reaction (Teams: Like), no outline", mm.opened && root.at(mm, 0, "header") && hk.length >= 2 && w.activeFocusItem === hk[0] && !mm.focusRing)
                k(Qt.Key_Up)
            }
            else if (s === 93) {
                const mm = w.kConversation.messageMenuForTest()
                root.check("message menu: Up from the first reaction wraps to More actions", root.at(mm, mm.items.length - 1) && mm.items[mm.current].key === "more")
                k(Qt.Key_Down)
            }
            else if (s === 94) {
                const mm = w.kConversation.messageMenuForTest()
                root.check("message menu: Down from More actions, back on the first reaction", root.at(mm, 0, "header"))
                for (let n = 1; n < mm.headerKeys().length; n++) k(Qt.Key_Down)
            }
            else if (s === 95) {
                const mm = w.kConversation.messageMenuForTest(), hk = mm.headerKeys()
                root.check("message menu: Down through the reactions to More reactions, outlined", root.at(mm, hk.length - 1, "header") && w.activeFocusItem === hk[hk.length - 1] && hk[hk.length - 1].focusRingShown)
                root.shot("message-menu-more-reactions")
            }
            else if (s === 96) { k(Qt.Key_Down) }
            else if (s === 97) {
                const mm = w.kConversation.messageMenuForTest()
                root.check("message menu: Down from More reactions: Reply with quote", mm.currentPart === "" && mm.items[mm.current] && mm.items[mm.current].key === "reply")
                k(Qt.Key_Escape)
            }
            // Its ··· More options: Esc puts the focus on it, the bar up.
            else if (s === 98) {
                root.check("message menu: Esc closes it", !w.kConversation.messageMenuForTest().opened)
                w.kConversation.forceBarId = root.msgId
            }
            else if (s === 99) {
                const bar = w.kConversation.hoverBarForTest(root.msgId)
                w.kConversation.focusCompose()
                t.mouseClick(bar.moreButtonForTest)
            }
            else if (s === 100) {
                const mm = w.kConversation.messageMenuForTest()
                root.check("··· opens the message menu, no reactions in it (Teams)", mm.opened && !mm.rightClick && mm.headerKeys().length === 0)
                // The pointer leaves the bar; only the menu keeps it up.
                w.kConversation.forceBarId = ""
                t.mouseMove(w.contentItem, 4, 4)
            }
            else if (s === 101) { k(Qt.Key_Escape) }
            else if (s === 102) {
                const bar = w.kConversation.hoverBarForTest(root.msgId), mb = bar.moreButtonForTest
                root.check("Esc: the focus on the message's ··· More options, outlined, its bar still up", !w.kConversation.messageMenuForTest().opened && mb.activeFocus && mb.focusRingShown && bar.visible)
                root.shot("more-options-focus")
            }
            else if (s === 103) { k(Qt.Key_Escape) }
            else if (s === 104) {
                const bar = w.kConversation.hoverBarForTest(root.msgId)
                root.check("a second Esc leaves the bar, which hides", !bar.moreButtonForTest.activeFocus && !bar.visible)
                root.step = 150
            }
            else if (s > 150) { console.warn("MENUKEYS done, failures:", root.fails.length, JSON.stringify(root.fails)); Qt.quit() }
        }
    }
}
