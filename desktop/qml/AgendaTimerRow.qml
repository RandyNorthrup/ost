import QtQuick
import QtQuick.Controls.Basic

// Teams' agenda timer (the Facilitator's agenda in the meeting timer
// strip; lazy-meeting-timer bundle, legacy layout with resizable topics,
// measured on winpc 2026-11-20 in "OST TEST 73 agenda"; research:
// scratchpad c073/agenda.md):
// - one 24 px row of topics, 10 apart (8 read-only), each as wide as its
//   share of the agenda; 56 px kept at the right for the Add topic split
//   button (24 + 24 x 23.33);
// - a topic: radius 8, #EBEBEB; the time used filling it from the left in
//   lavender (#C5CBFA), the last topic fading to red (#F1BBBC) over its
//   last 20 %, every topic red once the agenda is over time; its title
//   (12/16 semibold, centred, 26 px in) and, 5 from the right, its length
//   (12 regular #424242) or, on the current topic, what is left of it
//   (12 semibold); a filled check circle 6 in once discussed, the reorder
//   dots there on hover;
// - between topics a resize handle (24 wide, shown while the row is
//   hovered); a click opens the topic editor (title, Mark … as discussed,
//   Delete topic), a right-click Move left / Move right;
// - read-only viewers see the same row; a click marks a topic discussed.
Item {
    id: root
    /// The agenda timer as received ({state, remainingDuration, sections, …}).
    property var agenda: null
    property real lastEdit: 0
    property real skew: 0
    property bool viewOnly: true
    /// Minutes Add topic can free (backend's addAvailable).
    property int addAvailable: 0
    signal announce(string text)
    signal cancelAsked()

    height: 35

    // Sections shown meanwhile: an edit held until the meeting's update
    // brings it back (Teams holds an edit 3 s), or a new topic being named.
    property var held: null
    property int newIndex: -1
    readonly property var received: agenda && agenda.sections ? agenda.sections : []
    readonly property var sections: held || received
    onReceivedChanged: if (newIndex < 0 && !dragging) held = null
    Timer { id: holdTimer; interval: 3000; onTriggered: if (root.newIndex < 0 && !root.dragging) root.held = null }

    readonly property string state_: agenda ? agenda.state || "Cancelled" : "Cancelled"
    readonly property real total: Math.max(1, sections.reduce((a, s) => a + (s.originalDuration || 0), 0))
    readonly property real receivedTotal: Math.max(1, received.reduce((a, s) => a + (s.originalDuration || 0), 0))
    property real now: Date.now()
    Timer { interval: 100; repeat: true; running: root.visible && root.state_ === "InProgress"; onTriggered: root.now = Date.now() }
    // Teams' `Yh`: the part used up, plus the time since the stamp while
    // it runs (negative before the meeting's scheduled start).
    readonly property real elapsed: agenda ? (receivedTotal - (agenda.remainingDuration || 0))
        + (state_ === "InProgress" && lastEdit > 0 ? now - lastEdit - skew : 0) : 0
    readonly property bool started: state_ !== "Cancelled" && elapsed >= 0
    readonly property bool overTime: (state_ === "InProgress" || state_ === "Paused") && elapsed >= total
    readonly property int current: {
        let end = 0
        for (let i = 0; i < sections.length; i++) {
            end += sections[i].originalDuration || 0
            if (elapsed < end) return i
        }
        return Math.max(0, sections.length - 1)
    }
    function startOf(i) { let s = 0; for (let k = 0; k < i; k++) s += sections[k].originalDuration || 0; return s }
    // A topic's lifecycle stage (Teams 26304: the Facilitator's
    // topicLifecycleStage, a person's topicLifecycleUserOverride winning);
    // without one, discussed or not.
    // Only NotStarted and Done count (another value, "InProgress" tried
    // live, makes Teams fall back to the older look): "" when it has none.
    function stage(s) {
        const known = v => v === "Done" || v === "NotStarted" ? v : ""
        return known(s.topicLifecycleUserOverride) || known(s.topicLifecycleStage)
    }
    function discussed(s) {
        const st = stage(s)
        if (st) return st === "Done"
        if (s.topicRelevanceUserOverride !== undefined) return !!s.topicRelevanceUserOverride
        if (s.isDiscussed !== undefined) return !!s.isDiscussed
        return s.relevanceScore !== undefined && s.relevanceScore >= 3
    }
    // Teams' `Ql`: M:SS, minutes not padded.
    function length(ms) { const s = Math.round(Math.max(0, ms) / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
    // Teams' `nn`: what is left of the current topic, below zero over time.
    function countdown(r) {
        let m = Math.floor(Math.abs(r) / 60000), s = Math.abs(Math.ceil((r % 60000) / 1000))
        if (s === 60) { m += 1; s = 0 }
        const neg = r <= -1000
        if (neg && (m > 999 || (m === 999 && s > 59))) { m = 999; s = 59 }
        return (neg ? "-" : "") + m + ":" + String(s).padStart(2, "0")
    }
    function minutesText(ms) { return qsTr("%1 min").arg(ms < 60000 ? "<1" : Math.min(999, Math.round(ms / 60000))) }

    // Spoken as the current topic moves on (Teams' `Js`).
    property int spokenIndex: -1
    onCurrentChanged: {
        if (!started || spokenIndex < 0) { spokenIndex = current; return }
        if (current !== spokenIndex && sections[spokenIndex] && sections[current])
            announce(qsTr("Time has elapsed for: %1. Moving to %2.").arg(sections[spokenIndex].title).arg(sections[current].title))
        spokenIndex = current
    }
    onOverTimeChanged: if (overTime && sections.length)
        announce(qsTr("Time has elapsed for final section: %1. The meeting elapsed time is over.").arg(sections[sections.length - 1].title))

    function edit(action, args) {
        const r = backend.agendaEdit(action, JSON.stringify(args || {}))
        if (!r) return null
        const v = JSON.parse(r)
        return v
    }
    function hold(sections) { held = sections; holdTimer.restart() }

    // Add topic: a new, untitled topic held here; its title editor opens.
    function addTopic() {
        if (newIndex >= 0) { editor.focusInput(); return }
        const v = edit("add", { sections: sections })
        if (!v) return
        held = v.sections; newIndex = v.index
        Qt.callLater(() => editor.openFor(newIndex))
    }
    // The title editor closed or committed.
    function commitTitle(index, draft, closing) {
        const isNew = index === newIndex
        const original = isNew ? "" : (sections[index] ? sections[index].title : "")
        if (!draft.trim()) {
            if (isNew) { newIndex = -1; held = null; return true }
            if (!original.trim()) { removeTopic(index); return true }
            return closing   // the old title stays
        }
        const v = edit("rename", { index: index, title: draft, sections: sections, isNew: isNew })
        newIndex = -1
        if (v) hold(v.sections); else if (isNew) held = null
        return true
    }
    function toggleDiscussed(index) { const v = edit("discussed", { index: index, sections: sections }); if (v) hold(v.sections) }
    function removeTopic(index) { const v = edit("delete", { index: index, sections: sections }); if (v) hold(v.sections) }
    function moveTopic(from, to, base) { const v = edit("move", { from: from, to: to, sections: base || sections }); if (v) hold(v.sections) }

    // Layout.
    readonly property real gap: viewOnly ? 8 : 10
    readonly property real reserve: viewOnly ? 0 : 56
    readonly property real avail: Math.max(0, width - reserve - gap * Math.max(0, sections.length - 1))
    function widthOf(i) { const s = sections[i]; return s ? avail * (s.originalDuration || 0) / total : 0 }
    function xOf(i) { let x = 0; for (let k = 0; k < i; k++) x += widthOf(k) + gap; return x }

    readonly property color progress: theme.pick("#C5CBFA", "#7579EB", "#1AEBFF")
    readonly property color red: theme.pick("#F1BBBC", "#D13438", "#1AEBFF")

    // Resizing (a handle being dragged or stepped with the keyboard).
    property bool dragging: false
    property var resizeFrom: null
    function resizeBy(divider, deltaMs, publish) {
        const v = edit("resize", { divider: divider, deltaMs: deltaMs, sections: resizeFrom || sections, publish: publish })
        if (v) held = v.sections
        if (publish) { resizeFrom = null; dragging = false; holdTimer.restart() }
    }
    function resizeCancel() { held = resizeFrom ? null : held; resizeFrom = null; dragging = false }
    // Reordering by drag (8 px threshold) or Shift+Alt+arrows.
    property int reorderFrom: -1
    property int reorderTo: -1

    HoverHandler { id: rowHover }

    Item {
        id: track
        y: (root.height - 24) / 2
        width: root.width - root.reserve; height: 24

        Repeater {
            id: pills
            model: root.sections.length
            Item {
                id: pill
                required property int index
                function focusPill() { pillFocus.forceActiveFocus() }
                readonly property var s: root.sections[index] || ({})
                readonly property real dur: s.originalDuration || 0
                readonly property real start: root.startOf(index)
                readonly property bool last: index === root.sections.length - 1
                readonly property bool isCurrent: index === root.current && root.state_ !== "Cancelled"
                readonly property real within: Math.max(0, root.elapsed - start)
                readonly property bool done: root.discussed(s)
                readonly property string stage: root.stage(s)
                readonly property string timing: isCurrent ? root.countdown(dur - within) : root.length(dur)
                readonly property bool neg: timing[0] === "-"
                readonly property int wide: timing.length - (neg ? 1 : 0) - 4   // 0, 1 (≥10 min), 2 (≥100 min)
                readonly property bool showTiming: width >= (neg ? [90, 100, 110][Math.min(2, wide)] : [80, 90, 100][Math.min(2, wide)])
                readonly property real padRight: !showTiming ? 11
                    : neg ? [44, 49, 54][Math.min(2, wide)] : isCurrent ? [40, 45, 50][Math.min(2, wide)] : [40, 44, 48][Math.min(2, wide)]
                x: root.xOf(index) + (root.reorderFrom === index && pillDrag.active ? pillDrag.dx : 0)
                width: root.widthOf(index); height: 24
                z: root.reorderFrom === index ? 2 : 1
                opacity: root.reorderFrom === index && pillDrag.active ? 0.5 : 1
                Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                Behavior on x { enabled: !root.dragging && !pillDrag.active; NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

                Rectangle {
                    id: pillBox
                    anchors.fill: parent; radius: 8; clip: true
                    color: theme.pick("#EBEBEB", "#0A0A0A", "#000000")
                    border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                    // The time used, from the left.
                    Item {
                        readonly property real f: root.overTime ? 1
                            : root.started && (pill.index <= root.current || pill.within > 0)
                              ? (pill.last ? Math.min(1, pill.within / Math.max(1, pill.dur)) : Math.min(1, pill.within / Math.max(1, pill.dur))) : 0
                        visible: f > 0
                        width: pill.width * f; height: parent.height
                        clip: true
                        Rectangle {
                            width: pill.width; height: parent.height
                            color: root.overTime ? root.red : root.progress
                            gradient: pill.last && !root.overTime ? lastFill : null
                            Gradient {
                                id: lastFill
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.8; color: root.progress }
                                GradientStop { position: 1.0; color: root.red }
                            }
                        }
                    }
                    // Hover: a 1 px ring.
                    Rectangle {
                        anchors.fill: parent; radius: 8; color: "transparent"
                        visible: (pillHover.hovered && !root.viewOnly) || pillFocus.activeFocus
                        border.width: pillFocus.activeFocus ? 2 : 1
                        border.color: pillFocus.activeFocus ? theme.pick("#000000", "#FFFFFF", "#FFFFFF") : theme.textStrong
                    }
                }
                // Discussed, or the reorder dots on hover.
                Item {
                    x: 4; y: 2; width: 20; height: 20; clip: true
                    readonly property bool dots: !root.viewOnly && pillHover.hovered
                    // Done: a filled check circle; a topic without a
                    // lifecycle stage shows an empty circle until
                    // discussed (Teams 26304, seen live).
                    FluentIcon {
                        anchors.centerIn: parent; size: 16; name: pill.done ? "checkmark-circle-16-filled" : "circle-20"
                        color: theme.onFill(pillBox, theme.text)
                        visible: pill.done || pill.stage === ""
                        anchors.verticalCenterOffset: parent.dots ? -20 : 0
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 150 } }
                    }
                    FluentIcon {
                        anchors.centerIn: parent; size: 16; name: "re-order-dots-vertical-16"
                        color: theme.onFill(pillBox, theme.text)
                        anchors.verticalCenterOffset: parent.dots ? 0 : 20
                        opacity: parent.dots ? 1 : 0
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
                Text {
                    x: root.viewOnly ? 27 : 26; width: Math.max(0, pill.width - x - pill.padRight)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: pill.s.title || ""
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.onFill(pillBox, theme.text)
                }
                Text {
                    visible: pill.showTiming
                    anchors.right: parent.right; anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.timing
                    font.family: theme.font; font.pixelSize: 12
                    font.weight: pill.isCurrent || root.dragging ? Font.DemiBold : Font.Normal
                    font.features: { "tnum": 1 }
                    color: theme.onFill(pillBox, pill.isCurrent || root.dragging ? theme.text : theme.textStrong)
                }

                HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                // A click opens the editor (read-only: marks it discussed);
                // a drag of 8 px reorders; a right-click opens Move left/right.
                DragHandler {
                    id: pillDrag
                    enabled: !root.viewOnly && root.newIndex < 0 && !root.dragging
                    target: null
                    dragThreshold: 8
                    acceptedButtons: Qt.LeftButton
                    property real dx: 0
                    onActiveChanged: {
                        if (active) { root.reorderFrom = pill.index; editor.close(); return }
                        const to = root.reorderTo
                        root.reorderFrom = -1; root.reorderTo = -1; dx = 0
                        if (to >= 0 && to !== pill.index) root.moveTopic(pill.index, to)
                    }
                    onTranslationChanged: {
                        dx = translation.x
                        // Where it would land: the topic under its middle.
                        const mid = root.xOf(pill.index) + dx + pill.width / 2
                        let to = 0
                        for (let i = 0; i < root.sections.length; i++)
                            if (mid > root.xOf(i) + root.widthOf(i) / 2) to = i
                        root.reorderTo = to
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        if (root.viewOnly) root.toggleDiscussed(pill.index)
                        else editor.openFor(pill.index)
                    }
                }
                TapHandler {
                    enabled: !root.viewOnly
                    acceptedButtons: Qt.RightButton
                    onTapped: { topicMenu.index = pill.index; topicMenu.openAt() }
                }
                // Tooltip: the title and its minutes (brand).
                ToolTip {
                    visible: pillHover.hovered && !pillDrag.active && !root.dragging && !(editor.opened && editor.index === pill.index)
                    delay: 250
                    y: pill.height + 8
                    contentItem: Row {
                        spacing: 8
                        Text { text: pill.s.title || ""; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                        Text { text: root.minutesText(pill.dur); font.family: theme.font; font.pixelSize: 12; color: theme.brand }
                    }
                    background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
                }

                Item {
                    id: pillFocus
                    activeFocusOnTab: true
                    Accessible.role: root.viewOnly ? Accessible.CheckBox : Accessible.Button
                    Accessible.checked: pill.done
                    // "{title}, {status}, {elapsed} min of {duration} min".
                    Accessible.name: qsTr("%1, %2, %3 min of %4 min").arg(pill.s.title || "")
                        .arg(pill.stage === "Done" ? qsTr("Done") : pill.stage === "NotStarted" ? qsTr("Not started")
                             : pill.done ? qsTr("Discussed") : qsTr("Not discussed"))
                        .arg(Math.max(1, Math.round(Math.min(pill.within, pill.dur) / 60000)))
                        .arg(Math.max(1, Math.round(pill.dur / 60000)))
                    Accessible.description: qsTr("Topic %1 of %2").arg(pill.index + 1).arg(root.sections.length)
                    Keys.onPressed: e => {
                        const alt = (e.modifiers & Qt.AltModifier) && (e.modifiers & Qt.ShiftModifier)
                        if (!root.viewOnly && alt && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                            // Keyboard reorder: moves here; Enter keeps it, Escape undoes.
                            if (root.reorderFrom < 0) { root.reorderFrom = pill.index; root.resizeFrom = root.sections }
                            const to = pill.index + (e.key === Qt.Key_Left ? -1 : 1)
                            if (to >= 0 && to < root.sections.length) {
                                const s = root.sections.slice(); const m = s.splice(pill.index, 1)[0]; s.splice(to, 0, m)
                                root.held = s; root.reorderTo = to
                                Qt.callLater(() => { const it = pills.itemAt(to); if (it) it.focusPill() })
                            }
                            e.accepted = true
                        } else if (root.reorderFrom >= 0 && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                            const from = root.reorderFrom, to = root.reorderTo, base = root.resizeFrom
                            root.resizeFrom = null; root.reorderFrom = -1; root.reorderTo = -1
                            if (to >= 0 && to !== from) root.moveTopic(from, to, base); else root.held = null
                            e.accepted = true
                        } else if (root.reorderFrom >= 0 && e.key === Qt.Key_Escape) {
                            root.held = null; root.resizeFrom = null; root.reorderFrom = -1; root.reorderTo = -1
                            e.accepted = true
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                            if (root.viewOnly) root.toggleDiscussed(pill.index); else editor.openFor(pill.index)
                            e.accepted = true
                        }
                    }
                }
            }
        }

        // The drop place while reordering: 2 px, brand.
        Rectangle {
            visible: root.reorderFrom >= 0 && root.reorderTo >= 0 && root.reorderTo !== root.reorderFrom
            width: 2; height: 24; radius: 2; z: 3
            color: theme.brand
            x: root.reorderTo > root.reorderFrom ? root.xOf(root.reorderTo) + root.widthOf(root.reorderTo) + root.gap / 2 - 1
                                                 : root.xOf(root.reorderTo) - root.gap / 2 - 1
        }

        // Resize handles, centred in the gaps.
        Repeater {
            model: root.viewOnly ? 0 : Math.max(0, root.sections.length - 1)
            Item {
                id: handle
                required property int index
                readonly property string leftTitle: (root.sections[index] || {}).title || ""
                readonly property string rightTitle: (root.sections[index + 1] || {}).title || ""
                x: root.xOf(index + 1) - root.gap / 2 - width / 2
                width: 24; height: 24; z: 0
                visible: root.reorderFrom < 0
                opacity: rowHover.hovered || handleFocus.activeFocus || handleDrag.active || handle.keyboard ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                property bool keyboard: false
                property real keyDelta: 0
                FluentIcon {
                    anchors.centerIn: parent; size: 16; name: "re-order-16"; rotation: 90
                    color: theme.text
                    scale: handleHover.hovered || handleDrag.active ? 1.15 : 1
                }
                Rectangle {
                    anchors.fill: parent; radius: 2; color: "transparent"
                    visible: handleFocus.activeFocus
                    border.width: 2; border.color: theme.pick("#000000", "#FFFFFF", "#FFFFFF")
                }
                HoverHandler { id: handleHover; cursorShape: Qt.SplitHCursor }
                ToolTip.visible: handleHover.hovered && !handleDrag.active
                ToolTip.delay: 500
                ToolTip.text: qsTr("Drag to resize section")
                readonly property real msPerPx: root.total / Math.max(1, root.avail)
                DragHandler {
                    id: handleDrag
                    target: null
                    dragThreshold: 0
                    cursorShape: Qt.SplitHCursor
                    onActiveChanged: {
                        if (active) { root.resizeFrom = root.sections; root.dragging = true; editor.close() }
                        else if (root.resizeFrom) root.resizeBy(handle.index, translation.x * handle.msPerPx, true)
                    }
                    onTranslationChanged: if (active) root.resizeBy(handle.index, translation.x * handle.msPerPx, false)
                }
                Item {
                    id: handleFocus
                    anchors.fill: parent
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Resize between %1 and %2").arg(handle.leftTitle).arg(handle.rightTitle)
                    Accessible.description: qsTr("To resize, press Enter or Shift+Alt+Arrow. Hold Ctrl for larger steps. Press Enter to confirm, Escape to cancel.")
                    function step(dir, big) {
                        if (!handle.keyboard) { handle.keyboard = true; handle.keyDelta = 0; root.resizeFrom = root.sections; root.dragging = true }
                        handle.keyDelta += dir * (big ? 5 : 1) * 60000
                        root.resizeBy(handle.index, handle.keyDelta, false)
                        const a = root.sections[handle.index], b = root.sections[handle.index + 1]
                        if (a && b) root.announce(qsTr("%1: %2. %3: %4.").arg(a.title).arg(root.minutesText(a.originalDuration)).arg(b.title).arg(root.minutesText(b.originalDuration)))
                    }
                    Keys.onPressed: e => {
                        const arrow = e.key === Qt.Key_Left || e.key === Qt.Key_Right
                        const dir = e.key === Qt.Key_Left ? -1 : 1
                        if (handle.keyboard) {
                            if (arrow) step(dir, e.modifiers & Qt.ControlModifier)
                            else if (e.key === Qt.Key_Escape) { handle.keyboard = false; root.resizeCancel() }
                            else if (e.key !== Qt.Key_Control && e.key !== Qt.Key_Shift && e.key !== Qt.Key_Alt) {
                                handle.keyboard = false; root.resizeBy(handle.index, handle.keyDelta, true)
                            }
                            e.accepted = true
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                            handle.keyboard = true; handle.keyDelta = 0; root.resizeFrom = root.sections; root.dragging = true
                            e.accepted = true
                        } else if (arrow && (e.modifiers & Qt.ShiftModifier) && (e.modifiers & Qt.AltModifier)) {
                            step(dir, e.modifiers & Qt.ControlModifier); e.accepted = true
                        }
                    }
                    onActiveFocusChanged: if (!activeFocus && handle.keyboard) { handle.keyboard = false; root.resizeBy(handle.index, handle.keyDelta, true) }
                }
            }
        }
    }

    // Add topic ▾ (a subtle split button) at the right.
    Row {
        visible: !root.viewOnly
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 23.33
        component SplitPart: Rectangle {
            id: sp
            property string icon
            property int iconSize: 20
            property bool on: true
            property string tip
            property bool filledOnHover: true
            signal clicked()
            width: 24; height: 23.33
            color: sph.hovered && on ? theme.menuHover : "transparent"
            FluentIcon {
                anchors.centerIn: parent; size: sp.iconSize
                name: sp.icon + (sph.hovered && sp.on && sp.filledOnHover ? "-filled" : "")
                color: theme.onFill(sp, !sp.on ? theme.disabled : sph.hovered ? theme.brand : theme.textStrong)
            }
            HoverHandler { id: sph; cursorShape: sp.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: sp.on; onTapped: sp.clicked() }
            ToolTip.visible: sph.hovered && sp.tip !== ""
            ToolTip.delay: 500
            ToolTip.text: sp.tip
            Accessible.role: Accessible.Button
            Accessible.name: sp.tip
        }
        SplitPart {
            id: addButton
            icon: "add-circle-20"; tip: qsTr("Add topic")
            topLeftRadius: 4; bottomLeftRadius: 4
            on: root.addAvailable >= 1 || root.sections.length === 0
            onClicked: root.addTopic()
        }
        SplitPart {
            id: moreButton
            icon: "chevron-down-12"; iconSize: 12; filledOnHover: false
            tip: qsTr("More options")
            topRightRadius: 4; bottomRightRadius: 4
            onClicked: agendaMenu.openAt(moreButton, moreButton.width - agendaMenu.width, moreButton.height + 4)
        }
    }

    MenuPopup {
        id: agendaMenu
        items: [
            { label: qsTr("Add topic"), icon: "add-circle-20", enabled: addButton.on },
            { label: qsTr("Cancel tracker"), icon: "dismiss-square-20", enabled: !(root.state_ === "Cancelled" && root.sections.length === 0) }
        ]
        function openAt(item, px, py) { parent = item; agendaMenu.x = px; agendaMenu.y = py; open() }
        onPicked: i => { if (i === 0) root.addTopic(); else root.cancelAsked() }
    }

    MenuPopup {
        id: topicMenu
        property int index: 0
        function openAt() {
            parent = root
            x = Math.min(root.width - width, Math.max(0, rowHover.point.position.x))
            y = track.y + 24
            open()
        }
        items: [
            { label: qsTr("Move left"), icon: "arrow-left-20", enabled: topicMenu.index > 0 },
            { label: qsTr("Move right"), icon: "arrow-right-20", enabled: topicMenu.index < root.sections.length - 1 }
        ]
        onPicked: i => root.moveTopic(index, index + (i === 0 ? -1 : 1))
    }

    // The topic editor: its title, Mark … as discussed, Delete topic
    // (278.57 wide, padding 7.5, the arrow over the topic).
    Popup {
        id: editor
        property int index: -1
        readonly property var s: root.sections[index] || ({})
        parent: root
        width: 278.57
        padding: 7.5
        y: track.y + 24 + 8
        x: {
            const mid = root.xOf(Math.max(0, index)) + root.widthOf(Math.max(0, index)) / 2
            const win = root.mapToItem(null, 0, 0)
            return Math.max(-win.x, mid - width / 2)
        }
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property bool committed: false
        function openFor(i) { index = i; committed = false; titleInput.text = (root.sections[i] || {}).title || ""; error = ""; open(); focusInput() }
        function focusInput() { titleInput.forceActiveFocus(); titleInput.selectAll() }
        property string error: ""
        onClosed: {
            if (!committed && index >= 0) root.commitTitle(index, titleInput.text, true)
            index = -1
        }
        background: Item {
            FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
            // The arrow toward the topic.
            Rectangle {
                width: 11.3; height: 11.3; rotation: 45
                color: theme.surface
                x: root.xOf(Math.max(0, editor.index)) + root.widthOf(Math.max(0, editor.index)) / 2 - editor.x - width / 2
                y: -width / 2
            }
        }
        contentItem: Column {
            spacing: 8
            width: 262.24
            Column {
                spacing: 2
                Rectangle {
                    width: 262.24; height: 32; radius: 4
                    color: theme.pick("#F5F5F5", "#141414", "#000000")
                    border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                    TextInput {
                        id: titleInput
                        x: 12; width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        maximumLength: 100
                        clip: true
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.text
                        selectByMouse: true
                        selectionColor: theme.brandFill; selectedTextColor: theme.textOnBrand
                        Accessible.name: qsTr("Topic title")
                        Text {
                            visible: !titleInput.text && !titleInput.preedit
                            text: qsTr("Enter a title")
                            font: titleInput.font; color: theme.textSecondary
                        }
                        onTextEdited: {
                            const t = text.trim().toLowerCase()
                            editor.error = t && root.sections.some((s, i) => i !== editor.index && (s.title || "").trim().toLowerCase() === t)
                                ? qsTr("A topic with this name already exists.") : ""
                        }
                        Keys.onReturnPressed: editor.commit()
                        Keys.onEnterPressed: editor.commit()
                    }
                    // Fluent's underline: brand while focused, red on error.
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                        width: editor.error || titleInput.activeFocus ? parent.width - 2 : 0; height: 2
                        color: editor.error ? theme.pick("#C50F1F", "#DC626D") : theme.brandFill
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                Text {
                    visible: editor.error !== ""
                    width: 262.24; wrapMode: Text.Wrap
                    text: editor.error
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.pick("#B10E1C", "#DC626D")
                }
            }
            Column {
                spacing: 8
                Rectangle {
                    id: markButton
                    width: 262.24; height: 23.33; radius: 4
                    color: markHover.hovered ? theme.menuHover : theme.surface
                    border.width: 0.67; border.color: theme.stroke
                    Text {
                        anchors.centerIn: parent; width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: root.discussed(editor.s) ? qsTr("Mark %1 as not discussed").arg(editor.s.title || "")
                                                      : qsTr("Mark %1 as discussed").arg(editor.s.title || "")
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.onFill(markButton, theme.text)
                    }
                    HoverHandler { id: markHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            const i = editor.index
                            // A typed title goes first, then the mark.
                            if (titleInput.text.trim() && titleInput.text.trim() !== (editor.s.title || "").trim()) {
                                root.commitTitle(i, titleInput.text, false)
                                Qt.callLater(() => root.toggleDiscussed(i))
                            } else if (i !== root.newIndex) root.toggleDiscussed(i)
                            editor.committed = true
                            editor.close()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.discussed(editor.s) ? qsTr("Mark %1 as not discussed").arg(editor.s.title || "")
                                                             : qsTr("Mark %1 as discussed").arg(editor.s.title || "")
                }
                Rectangle {
                    id: deleteButton
                    readonly property bool on: root.sections.length > 1
                    width: 262.24; height: 23.33; radius: 4
                    color: deleteHover.hovered && on ? theme.menuHover : "transparent"
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon {
                            anchors.verticalCenter: parent.verticalCenter; size: 20
                            name: "delete-20" + (deleteHover.hovered && deleteButton.on ? "-filled" : "")
                            color: theme.onFill(deleteButton, !deleteButton.on ? theme.disabled : deleteHover.hovered ? theme.brand : theme.textStrong)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Delete topic")
                            font.family: theme.font; font.pixelSize: 12
                            color: theme.onFill(deleteButton, !deleteButton.on ? theme.disabled : theme.textStrong)
                        }
                    }
                    HoverHandler { id: deleteHover; cursorShape: deleteButton.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        enabled: deleteButton.on
                        onTapped: {
                            const i = editor.index
                            editor.committed = true
                            editor.close()
                            if (i === root.newIndex) { root.newIndex = -1; root.held = null }
                            else root.removeTopic(i)
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Delete topic")
                }
            }
        }
        function commit() {
            const draft = titleInput.text
            const original = (editor.s.title || "").trim()
            if (!draft.trim() && !original) { error = qsTr("(* Required fields)"); return }
            committed = true
            root.commitTitle(index, draft, false)
            close()
        }
    }
    function editorForTest() { return editor }
}
