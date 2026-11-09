import QtQuick
import QtQuick.Controls.Basic

// Teams' meeting timer strip (More ▸ Timer; lazy-meeting-timer bundle,
// legacy layout as winpc draws it, measured 2026-11-09; spec: scratchpad
// timer/spec.md): under the bar, white with a 1 px #D1D1D1 line, 2 px
// above and below a 35 px row, 12 px in:
// - the countdown (24/32 semibold, brand; red once over time), the
//   "Timer controls" popover's trigger (padding 0 5, radius 8; hover
//   #F5F5F5, open #E0E0E0);
// - ▶/‖ (Start new timer / Pause timer / Resume timer; over time "Cancel
//   timer for everyone") and ↻ Reset timer (off while cancelled), 21.33 px,
//   10 apart;
// - the track (24 tall, radius 8, #EBEBEB): the time left as a lavender
//   (#C5CBFA) fill anchored right, turning red (#F1BBBC) near the end;
//   whole when the timer is off; "Paused" over 40 % black; over time red,
//   blinking three times, with "Time's up!" (#960B18).
// View-only (attendees) see the countdown and the track only.
Rectangle {
    id: root
    /// The meeting timer (backend.callTimerJson): {adhoc, lastEditMs,
    /// totalMs, skewMs, sequence, live}.
    property var info: null
    property bool viewOnly: false
    /// Ask for a change: start, pause, resume, reset, cancel,
    /// cancelOverTime, startWith (ms), add (minutes).
    signal action(string name, int arg)
    signal announce(string text)
    signal timeUp()
    readonly property var popupForTest: popover
    function openControls() { if (!viewOnly) popover.open() }

    height: 40
    color: theme.surface
    Rectangle { anchors.bottom: root.bottom; width: root.width; height: 1; color: theme.pick("#D1D1D1", "#666666") }

    readonly property var t: info && info.adhoc ? info.adhoc : ({ state: "Cancelled", remainingDuration: 300000 })
    readonly property string timerState: t.state || "Cancelled"
    readonly property real total: info ? Math.max(1, info.totalMs || 300000) : 300000
    readonly property real lastEdit: info && info.lastEditMs ? info.lastEditMs : 0
    readonly property real skew: info ? (info.skewMs || 0) : 0
    property real now: Date.now()
    Timer { interval: 100; repeat: true; running: root.visible && root.timerState === "InProgress"; onTriggered: root.now = Date.now() }
    readonly property real elapsed: (total - (t.remainingDuration || 0))
        + (timerState === "InProgress" && lastEdit > 0 ? Math.max(0, now - lastEdit - skew) : 0)
    readonly property real remaining: total - elapsed
    readonly property bool overTime: (timerState === "InProgress" || timerState === "Paused") && elapsed >= total
    readonly property bool cancelled: timerState === "Cancelled"

    // Teams' countdown text (zs): seconds rounded up while counting down,
    // toward zero over time; at most 99:59.
    function clock(r) {
        const neg = r <= -1000
        let m = Math.floor(Math.abs(r) / 60000)
        let s = Math.abs(Math.ceil((r % 60000) / 1000))
        if (s === 60) { m += 1; s = 0 }
        if (neg && (m > 99 || (m === 99 && s > 59))) { m = 99; s = 59 }
        return (neg ? "-" : "") + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }
    function spoken(ms) {
        if (ms <= 0) return "0 sec"
        const ts = Math.ceil(ms / 1000), m = Math.floor(ts / 60), s = ts % 60
        return m === 0 ? s + " sec" : s === 0 ? m + " min" : m + " min, " + s + " sec"
    }
    readonly property string display: cancelled ? clock(total) : clock(remaining)

    // Screen-reader thresholds while it runs (10, 5, 1 min, 10 s left).
    property var spokenMarks: ({})
    onRemainingChanged: {
        if (timerState !== "InProgress") return
        if (remaining > 610000) { spokenMarks = ({}); return }
        const marks = [[600000, "10 minutes remaining."], [300000, "5 minutes remaining."],
                       [60000, "1 minute remaining."], [10000, "10 seconds remaining."]]
        for (const [at, text] of marks)
            if (remaining <= at && remaining > at - 1000 && !spokenMarks[at]) { spokenMarks[at] = true; announce(text) }
    }
    onTimerStateChanged: if (timerState !== "InProgress") spokenMarks = ({})
    // Out of time: Teams plays its chime and says so, once.
    onOverTimeChanged: if (overTime) { announce("Timer has run out of time."); timeUp(); timeUpPulse.restart() }

    component ActionButton: Rectangle {
        id: ab
        property string icon
        property string tip
        property bool on: true
        signal clicked()
        width: 21.33; height: 21.33; radius: 4
        color: "transparent"
        FluentIcon {
            anchors.centerIn: parent; size: 20
            name: ab.icon + (abh.hovered && ab.on ? "-filled" : "")
            color: !ab.on ? theme.disabled : abh.hovered ? theme.brand : theme.textStrong
        }
        HoverHandler { id: abh; cursorShape: ab.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: ab.on; onTapped: ab.clicked() }
        ToolTip.visible: abh.hovered && ab.on
        ToolTip.delay: 250
        ToolTip.text: ab.tip
        Accessible.role: Accessible.Button
        Accessible.name: ab.tip
    }

    Row {
        id: controls
        x: 12; y: 2; height: 35
        spacing: 10
        // The countdown: the popover's trigger for controllers.
        Rectangle {
            id: trigger
            anchors.verticalCenter: parent.verticalCenter
            width: clockText.implicitWidth + 10; height: 32; radius: 8
            color: root.viewOnly ? "transparent" : popover.opened ? theme.pick("#E0E0E0", "#1F1F1F")
                 : th.hovered ? theme.pick("#F5F5F5", "#333333") : "transparent"
            Text {
                id: clockText
                x: 5; anchors.verticalCenter: parent.verticalCenter
                text: root.display
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: root.overTime ? theme.pick("#B10E1C", "#DC626D") : theme.pick("#5B5FC7", "#7F85F5")
            }
            HoverHandler { id: th; enabled: !root.viewOnly; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.viewOnly; onTapped: popover.opened ? popover.close() : popover.open() }
            ToolTip.visible: th.hovered && !popover.opened
            ToolTip.delay: 250
            ToolTip.text: "Timer controls"
            Accessible.role: root.viewOnly ? Accessible.StaticText : Accessible.Button
            Accessible.name: root.viewOnly ? root.display
                : root.cancelled ? "Timer controls" : "Timer controls, " + root.spoken(root.remaining) + " remaining"
        }
        Item {
            visible: !root.viewOnly
            width: 52.67; height: parent.height
            ActionButton {
                y: 6.83
                icon: root.overTime ? "dismiss-square-20" : root.timerState === "InProgress" ? "pause-20" : "play-20"
                tip: root.overTime ? "Cancel timer for everyone" : root.timerState === "InProgress" ? "Pause timer"
                    : root.timerState === "Paused" ? "Resume timer" : "Start new timer"
                onClicked: {
                    if (root.overTime) root.action("cancelOverTime", 0)
                    else if (root.timerState === "InProgress") root.action("pause", 0)
                    else if (root.timerState === "Paused") root.action("resume", 0)
                    else root.action("start", 0)
                }
            }
            ActionButton {
                x: 31.34; y: 6.83
                icon: "arrow-clockwise-20"; tip: "Reset timer"
                on: !root.cancelled
                onClicked: root.action("reset", 0)
            }
        }
    }

    // The track: what's left of the timer.
    Rectangle {
        id: track
        x: controls.x + controls.width + 10; y: 7.5
        width: root.width - x - 12; height: 24; radius: 8
        color: theme.pick("#EBEBEB", "#0A0A0A")
        clip: true
        readonly property color progress: theme.pick("#C5CBFA", "#7579EB")
        readonly property color red: theme.pick("#F1BBBC", "#D13438")
        readonly property real f: root.cancelled ? 0 : Math.max(0, Math.min(1, root.elapsed / root.total))
        // Running or paused: the part left, from the right edge, its colour
        // sliding to red over the last stretch (Teams' 200 % gradient).
        Item {
            visible: !root.overTime
            x: track.width * track.f; width: track.width - x; height: parent.height
            clip: true
            Rectangle {
                x: -track.width * track.f; width: track.width * 2; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.8; color: track.progress }
                    GradientStop { position: 1.0; color: root.cancelled ? track.progress : track.red }
                }
            }
        }
        // Over time: red, growing back to full width, then blinking.
        Rectangle {
            id: overFill
            visible: root.overTime
            anchors.right: parent.right
            width: track.width; height: parent.height
            color: track.red
        }
        SequentialAnimation {
            id: timeUpPulse
            NumberAnimation { target: overFill; property: "width"; from: 0; to: track.width; duration: 400 }
            SequentialAnimation {
                loops: 3
                NumberAnimation { target: overFill; property: "opacity"; from: 1; to: 0.2; duration: 500 }
                NumberAnimation { target: overFill; property: "opacity"; from: 0.2; to: 1; duration: 500 }
            }
        }
        // Paused (not over time): 40 % black and "Paused".
        Rectangle {
            visible: root.timerState === "Paused" && !root.overTime
            anchors.fill: parent; radius: 8
            color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5))
            Text {
                anchors.centerIn: parent
                text: "Paused"
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: "white"
            }
        }
        Text {
            visible: root.overTime
            anchors.centerIn: parent
            text: "Time's up!"
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.pick("#960B18", theme.text)
        }
        HoverHandler { id: trackHover }
        ToolTip.visible: trackHover.hovered
        ToolTip.delay: 500
        ToolTip.text: {
            const m = Math.round(root.total / 60000)
            return (root.total < 60000 ? "<1" : Math.min(999, m)) + " min"
        }
    }

    // "Timer controls": 180 wide inside Fluent's popover padding, a grid
    // 10 apart: the time (read-only "mm : ss", or minutes and seconds to
    // edit), "+1 min", "+5 min", "+10 min", then the secondary button
    // (Cancel timer / Undo) and the primary (Edit / Start).
    Popup {
        id: popover
        parent: trigger
        x: 0; y: trigger.height
        padding: 16.67
        width: 213.33
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        property bool editing: false
        property int minutes: 5
        property int seconds: 0
        function fill(ms) {
            const ts = Math.ceil(Math.max(0, ms) / 1000)
            minutes = Math.min(99, Math.floor(ts / 60)); seconds = ts % 60
        }
        function enterEdit() {
            fill(root.overTime ? root.total : root.remaining)
            editing = true
            root.announce("You are now in edit mode. You can modify the timer settings.")
        }
        // Cancelled: set a new one (last length, else 5:00); running or
        // paused: show the time left.
        onAboutToShow: {
            if (root.cancelled) { fill(root.total); editing = true }
            else editing = false
        }
        Connections {
            target: root
            function onTimerStateChanged() {
                if (root.cancelled) { popover.fill(root.total); popover.editing = true }
                else { popover.editing = false; popover.close() }
            }
        }
        readonly property int inputMs: (minutes * 60 + seconds) * 1000
        function addMinutes(n) {
            if (editing) {
                const ms = Math.min(5999000, inputMs + n * 60000)
                fill(ms)
                root.announce("Timer set to " + root.spoken(ms))
                return
            }
            root.action("add", n)
            root.announce(n === 1 ? "Added 1 minute to the timer." : "Added " + n + " minutes to the timer.")
            close()
        }
        function canAdd(n) {
            if (editing) return inputMs + n * 60000 <= 5999000
            if (root.overTime) return true
            return (root.cancelled ? root.total : root.remaining) + n * 60000 <= 5999000
        }

        contentItem: Column {
            spacing: 10
            width: 180
            // The time.
            Item {
                width: 180; height: 45
                Rectangle {
                    visible: !popover.editing
                    x: 2; width: 176; height: 45; radius: 8
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: { const c = root.display.replace(":", " : "); return c }
                        font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold
                        font.features: { "tnum": 1, "case": 1 }
                        color: root.overTime ? theme.pick("#B10E1C", "#DC626D") : theme.pick("#5B5FC7", "#7F85F5")
                    }
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.spoken(root.remaining)
                }
                Row {
                    visible: popover.editing
                    x: 14.13; y: 1.16
                    TimerSpin { id: minutesSpin; value: popover.minutes; max: 99; label: "Minutes"; tip: "Adjust minutes for new timer"
                                onEdited: v => { popover.minutes = v; root.announce("Timer set to " + root.spoken(popover.inputMs)) } }
                    Text {
                        width: 11.72; height: 42.67; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                        text: ":"; font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold; color: theme.text
                    }
                    TimerSpin { value: popover.seconds; max: 59; label: "Seconds"; tip: "Adjust seconds for new timer"
                                onEdited: v => { popover.seconds = v; root.announce("Timer set to " + root.spoken(popover.inputMs)) } }
                }
            }
            // Add time.
            Item {
                width: 180; height: 23.33
                Repeater {
                    model: [1, 5, 10]
                    Rectangle {
                        id: addBtn
                        required property int modelData
                        required property int index
                        readonly property bool on: popover.canAdd(modelData)
                        width: addText.implicitWidth + 8; height: 23.33; radius: 4
                        x: index === 0 ? -0.23 : index === 1 ? (180 - width) / 2 - 0.77 : 180 - width + 0.23
                        color: addHover.hovered && on ? theme.menuHover : "transparent"
                        Text {
                            id: addText
                            anchors.centerIn: parent
                            text: "+" + addBtn.modelData + " min"
                            font.family: theme.font; font.pixelSize: 12
                            color: addBtn.on ? theme.textStrong : theme.disabled
                        }
                        HoverHandler { id: addHover; cursorShape: addBtn.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: addBtn.on; onTapped: popover.addMinutes(addBtn.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "+" + addBtn.modelData + " min"
                    }
                }
            }
            // Footer.
            Item {
                width: 180; height: 31.33
                component FooterButton: Rectangle {
                    id: fb
                    property string label
                    property bool primary: false
                    property bool on: true
                    signal clicked()
                    width: fbText.implicitWidth + 15; height: 31.33; radius: 4
                    color: !on ? theme.bgDisabled : primary ? (fbh.hovered ? theme.brandHover : theme.brandFill)
                         : (fbh.hovered ? theme.menuHover : theme.surface)
                    border.color: primary || !on ? "transparent" : theme.stroke; border.width: 0.67
                    Text {
                        id: fbText
                        anchors.centerIn: parent
                        text: fb.label
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: !fb.on ? theme.disabled : fb.primary ? theme.textOnBrand : theme.text
                    }
                    HoverHandler { id: fbh; cursorShape: fb.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: fb.on; onTapped: fb.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: fb.label
                }
                FooterButton {
                    label: root.cancelled || !popover.editing ? "Cancel timer" : "Undo"
                    on: !root.cancelled
                    onClicked: {
                        if (popover.editing) {
                            popover.editing = false
                            root.announce("You have exited edit mode.")
                        } else {
                            root.action("cancel", 0)
                            root.announce("Timer has been ended.")
                            popover.close()
                        }
                    }
                }
                FooterButton {
                    anchors.right: parent.right
                    primary: true
                    label: popover.editing || root.cancelled ? "Start" : "Edit"
                    on: !(popover.editing && popover.inputMs === 0)
                    onClicked: {
                        if (popover.editing || root.cancelled) {
                            root.action("startWith", popover.inputMs)
                            popover.editing = false
                            root.announce("You have exited edit mode.")
                        } else popover.enterEdit()
                    }
                }
            }
        }
    }
    function startForTest(ms) { root.action("startWith", ms) }
}
