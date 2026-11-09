import QtQuick

// Teams' RTT box (real-time-text-input, the captions window's bottom while
// RTT is on; measured on winpc, 2026-11-09): an outlined Fluent input, 32
// tall, radius 4, white, its sides #B3B3B3 and bottom #4D4D4D (0.67 px), a
// 2 px brand line under it while focused; "Type a message in real-time"
// (14/20) 12 in. What changed goes every 300 ms; Enter ends the line, and
// so do 3 s without a key. Above it, when needed, a 36 px message bar
// (#F5F5F5, a #D1D1D1 border, radius 4, its words 20.67 in):
// - "Please type a message to continue." (Enter on nothing but spaces);
// - "You cannot type more than 2000 characters" (an error bar).
Column {
    id: root
    /// A line still being typed ends when the box goes (Teams' unmount).
    property bool active: visible
    readonly property bool barShown: onlySpaces || tooLong
    property bool onlySpaces: false
    property bool tooLong: false
    // Text set here rather than typed isn't sent.
    property bool quiet: false
    property string accepted: ""
    function clearBox() {
        quiet = true
        input.text = ""
        accepted = ""
        quiet = false
    }
    // As keys would: the text, and the 3 s line timer restarted.
    function typeForTest(t) { input.forceActiveFocus(); input.insert(input.cursorPosition, t); idle.restart() }
    function holdForTest() { idle.stop() }
    function textForTest() { return input.text }
    function barForTest() { return onlySpaces ? "onlySpaces" : tooLong ? "tooLong" : "" }
    function enterForTest() { root.commit(true) }
    function commit(manual) {
        const sent = backend.rttCommit(manual)
        if (manual) onlySpaces = !sent
        else if (sent) onlySpaces = false
        idle.stop()
        clearBox()
    }
    onActiveChanged: if (!active && input.text.length > 0) commit(false)
    Connections {
        target: backend
        function onRttInputCleared() { root.clearBox(); idle.stop() }
    }
    Timer {
        interval: 300; repeat: true; running: root.active
        onTriggered: if (backend.rttFlush()) root.onlySpaces = false
    }
    Timer { id: idle; interval: 3000; onTriggered: root.commit(false) }

    Rectangle {
        visible: root.barShown
        width: root.width; height: 36; radius: 4
        color: root.tooLong ? theme.pick("#FDF3F4", "#3F1011") : theme.pick("#F5F5F5", "#1F1F1F")
        border.color: root.tooLong ? theme.pick("#EEACB2", "#6E0811") : theme.pick("#D1D1D1", "#3D3D3D")
        border.width: 0.67
        Text {
            x: 20.67; width: parent.width - x - 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.tooLong ? "You cannot type more than 2000 characters" : "Please type a message to continue."
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.tooLong ? "You cannot type more than 2000 characters" : "Please type a message to continue."
    }
    Rectangle {
        width: root.width; height: 32; radius: 4
        color: theme.surface
        border.width: 0.67
        border.color: theme.pick("#B3B3B3", "#666666")
        clip: true
        Rectangle {
            anchors.bottom: parent.bottom; x: 0.67; width: parent.width - 1.33; height: 0.67
            color: input.activeFocus ? "transparent" : theme.pick("#4D4D4D", "#ADADAD")
        }
        Rectangle {
            visible: input.activeFocus
            anchors.bottom: parent.bottom; width: parent.width; height: 2
            color: theme.brand
        }
        TextInput {
            id: input
            x: 12.67; width: parent.width - 25.33
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            selectByMouse: true
            clip: true
            onTextChanged: {
                if (root.quiet) return
                if (!backend.rttInput(text)) {
                    // Past 2000: the box keeps what it had.
                    const at = Math.min(cursorPosition, root.accepted.length)
                    root.quiet = true
                    text = root.accepted
                    cursorPosition = at
                    root.quiet = false
                    root.tooLong = true
                    return
                }
                root.tooLong = false
                root.accepted = text
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (text.length > 0) root.commit(true)
                    else idle.stop()
                    event.accepted = true
                } else {
                    idle.restart()
                }
            }
            TapHandler { onTapped: if (input.text.length > 0) idle.restart() }
            Text {
                visible: !input.text
                text: "Type a message in real-time"
                font: input.font
                color: theme.pick("#707070", "#ADADAD")
            }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Type a message in real-time"
        }
    }
}
