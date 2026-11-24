import QtQuick

// Teams' keyboard for its lists (Activity, @mentions, the quick views;
// the chat list has its own, ChatList.moveFocus): Up / Down (and Home /
// End) move a focus ring through the rows; Teams opens each row as you
// arrive (the activity feed's option takes aria-selected as focus lands,
// measured on winpc 2026-11-16), unless Settings ▸ General ▸ "Use Enter or
// Spacebar to show content" is on (the synced messagingSettings.
// disableAutomaticConvSwitchOnKeyboardNav), when Enter or Space opens the
// focused row. The ring (2 px NeutralForeground1, the row's radius) shows
// only while you use the keyboard.
//
// Use: `ListKeys { id: keys; view: list; items: root.shown; keyOf: … }`,
// forward the view's Keys to `keys.handle(event)`, call `keys.clicked(item)`
// from a row's tap, and draw the ring where `keys.ringOn(item)`.
QtObject {
    id: nav
    /// The rows, in order.
    property var items: []
    /// The ListView showing them (scrolled to keep the ring in view).
    property ListView view: null
    /// The item the keys go to (has the ring while it has focus).
    property Item owner: null
    /// A row's identity.
    property var keyOf: it => it.id
    property bool enterToOpen: false
    property string focusKey: ""
    property bool keyboardNav: false
    signal open(var item)

    function indexOfKey(k) { return items.findIndex(x => nav.keyOf(x) === k) }
    function moveTo(i) {
        if (items.length === 0) return
        i = Math.max(0, Math.min(items.length - 1, i))
        keyboardNav = true
        focusKey = keyOf(items[i])
        if (view) view.positionViewAtIndex(i, ListView.Contain)
        if (!enterToOpen) open(items[i])
    }
    function move(step, selectedKey) {
        if (items.length === 0) return
        let i = indexOfKey(focusKey || selectedKey || "")
        moveTo(i < 0 ? (step > 0 ? 0 : items.length - 1) : i + step)
    }
    function openFocused() {
        const i = indexOfKey(focusKey)
        if (i >= 0) open(items[i])
    }
    /// A row was clicked: it takes the keyboard from there (no ring).
    function clicked(item) {
        keyboardNav = false
        focusKey = keyOf(item)
        if (owner && !owner.activeFocus) owner.forceActiveFocus()
    }
    function ringOn(item) { return keyboardNav && !!owner && owner.activeFocus && focusKey === keyOf(item) }
    /// Keys.onPressed: true when the key was the list's.
    function handle(e, selectedKey) {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        if (e.key === Qt.Key_Down) move(1, selectedKey)
        else if (e.key === Qt.Key_Up) move(-1, selectedKey)
        else if (e.key === Qt.Key_Home) moveTo(0)
        else if (e.key === Qt.Key_End) moveTo(items.length - 1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { if (!focusKey) return false; openFocused() }
        else return false
        e.accepted = true
        return true
    }
}
