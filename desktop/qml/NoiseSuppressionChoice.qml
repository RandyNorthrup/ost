import QtQuick
import QtQuick.Controls

// Teams' noise suppression choice in a call (358966 module 327752 `be`:
// the Mic ▾ flyout and the Audio settings pane): under the Noise
// suppression switch, where voice isolation is supported, a Fluent
// RadioGroup with "Background noise only" and "Voice isolation". Both are
// disabled with the switch off (keeping their pick); Voice isolation also
// without a voice profile, and with Room audio, which forces Background
// noise only. In the panes (not the flyout) each label carries an info
// button with its tooltip. The pick is Teams' device-local
// noiseSuppressionMode (Pns = Voice isolation, Auto = Background noise
// only; unset is Voice isolation once there is a profile), acted on by
// OST's isolator (calling::voice_isolation, TASK-0181).
//
// Measured in Teams on winpc in a test call (2026-11-19, flyout and pane
// alike): Fluent v9 radios in 32 px rows right under the switch row, the
// 16 px indicator 8 in and 8 down (0.67 px ring: brand when picked,
// #E0E0E0 when disabled), the 14/20 text 36 in and 6 down (#242424,
// disabled #BDBDBD), the pane's 24 px info button right after the text,
// 4 down.
Column {
    id: root
    /// The Noise suppression switch.
    property bool noiseOn: true
    /// The panes show the tooltips' info buttons; the flyout doesn't.
    property bool showInfo: false
    /// Joined with Room audio (Teams' isRoomAudioSelected).
    property bool roomAudio: false
    readonly property var vi: backend.voiceIsolationJson ? JSON.parse(backend.voiceIsolationJson) : ({})
    readonly property bool hasProfile: vi.profile === true
    readonly property bool isolation: hasProfile && vi.mode === "Pns"
    // Teams' useEffect: with Room audio, Voice isolation is put back to
    // Background noise only.
    onRoomAudioChanged: forceBackgroundOnly()
    onIsolationChanged: forceBackgroundOnly()
    Component.onCompleted: forceBackgroundOnly()
    function forceBackgroundOnly() {
        if (roomAudio && isolation) pick("Auto")
    }
    function pick(mode) {
        console.warn("NOISE pick", mode)
        backend.setSetting("noiseSuppressionMode", mode)
        backend.applyVoiceIsolation()
    }
    // Set from outside (the flyout's and pane's own InfoButton component).
    property Component infoButton: null

    Choice {
        label: qsTr("Background noise only")
        tooltip: qsTr("Enable this to enhance your microphone audio quality by removing background noise. <0>Learn more</0>").replace("<0>", "<a href=\"https://aka.ms/noisesuppression\">").replace("</0>", "</a>")
        checked: !root.isolation
        usable: root.noiseOn
        onPicked: root.pick("Auto")
    }
    Choice {
        label: qsTr("Voice isolation")
        tooltip: root.roomAudio ? qsTr("You are currently in a meeting with others nearby. Voice isolation is disabled for you to ensure everyone is heard.")
                                : qsTr("Isolate your voice from background noise and other voices while speaking. Only your voice will be audible.")
        checked: root.isolation
        usable: root.noiseOn && root.hasProfile && !root.roomAudio
        onPicked: root.pick("Pns")
    }

    component Choice: Item {
        id: ch
        property string label
        property string tooltip
        property bool checked
        property bool usable: true
        signal picked()
        width: root.width; height: 32
        // Fluent's indicator: a thin ring (brand when picked, #616161 not,
        // the disabled stroke when off) and the 10 px dot.
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 8
            color: "transparent"
            border.width: 0.67
            border.color: !ch.usable ? theme.divider : ch.checked ? theme.checkedFill : hover.hovered ? theme.textStrong : theme.textSecondary
            Rectangle {
                visible: ch.checked
                anchors.centerIn: parent; width: 10; height: 10; radius: 5
                color: ch.usable ? theme.brandFill : theme.disabled
            }
        }
        // The radio itself (indicator and label) takes the click; the
        // info button after the label keeps its own.
        Item {
            width: 36 + labelText.implicitWidth; height: parent.height
            HoverHandler { id: hover; enabled: ch.usable; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: ch.usable && !ch.checked; onTapped: ch.picked() }
        }
        Row {
            x: 36; y: 6
            Text {
                id: labelText
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: ch.label
                font.family: theme.font; font.pixelSize: 14
                color: ch.usable ? theme.text : theme.disabled
            }
            Loader {
                y: -2
                active: root.showInfo && !!root.infoButton
                sourceComponent: root.infoButton
                onLoaded: item.info = Qt.binding(() => ch.tooltip)
            }
        }
        Accessible.role: Accessible.RadioButton
        Accessible.name: ch.label
        Accessible.checked: ch.checked
        Accessible.onPressAction: if (ch.usable) ch.picked()
    }
}
