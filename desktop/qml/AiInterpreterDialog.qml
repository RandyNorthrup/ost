import QtQuick
import QtQuick.Controls

// Teams' Interpreter settings (ai-interpreter-settings-dialog-v2, dialog
// module 658445 in Teams 26304; strings from its en-us bundle): "Set up
// your Interpreter" when turning it on, else "Interpreter settings".
// "What you hear": "You'll hear speech translated into" over the language
// list ("Choose interpretation language"; Teams' names, by name), "Speech
// in {language} won't be translated.", and "Balance volume" (-100..100,
// "More original audio" / "More interpretation audio"; 80 at first).
// "How others hear you": "Voice others hear when your speech is
// translated" with "Simulate my voice" or "Automated voice" (Auto, Ava,
// Andrew, Fable Turbo). Cancel (setup only) and "Turn on for me" / Save.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: setup ? 480 : 600; height: setup ? 252 : col.implicitHeight + 49.33
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// The interpreter state (backend call_interpreter_json).
    property var state_: ({})
    /// Turning Interpreter on (setup) rather than changing its settings.
    property bool setup: true
    signal confirmed(string language, string voice, real balance)

    property string language: ""
    property int balance: 80
    property string voice: "0"
    readonly property var languages: (state_.languages || []).slice().sort((a, b) => a.name.localeCompare(b.name))
    function nameOf(code) { const l = languages.find(x => x.code === code); return l ? l.name : "" }
    function show(isSetup) {
        setup = isSetup
        language = state_.myLanguage || state_.language || ""
        balance = Math.round((state_.balance !== undefined ? state_.balance : 0.8) * 100)
        voice = state_.voice || "0"
        open()
    }

    component Heading: Text {
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    component Radio: Item {
        id: rb
        property string label
        property bool checked: false
        signal clicked()
        width: parent ? parent.width : 300; height: 32
        Rectangle {
            x: 2; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8
            color: "transparent"; border.color: rb.checked ? theme.brand : theme.textSecondary; border.width: 0.67
            Rectangle { visible: rb.checked; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
        }
        Text { x: 28; anchors.verticalCenter: parent.verticalCenter; text: rb.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        TapHandler { onTapped: rb.clicked() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.RadioButton; Accessible.checked: checked; Accessible.name: label
    }
    component Combo: Rectangle {
        id: cb
        property string text
        property string placeholder
        property var items: []
        signal picked(int index)
        width: parent ? parent.width : 300; height: 32; radius: 4
        color: theme.surface; border.color: theme.stroke; border.width: 0.67
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; elide: Text.ElideRight
            text: cb.text || cb.placeholder
            font.family: theme.font; font.pixelSize: 14; color: cb.text ? theme.text : theme.textSecondary
        }
        FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
        TapHandler { enabled: cb.enabled; onTapped: menu.open() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Accessible.role: Accessible.ComboBox; Accessible.name: cb.text || cb.placeholder
        MenuPopup { id: menu; y: parent.height + 4; width: parent.width; height: Math.min(implicitHeight, 320); items: cb.items; onPicked: i => cb.picked(i) }
    }

    // Setting it up (measured on winpc 2026-11-20, 480 x 252, padding 24):
    // the title (20/28 semibold), Close (24 x 23.33) at 431.33, 25.5; "You'll
    // hear speech translated into" (14/600) at 68.67 over the language box
    // (430.67 x 31.33, "Choose interpretation language" in #707070) at
    // 92.67; the ticked "Allow AI to simulate my voice when others hear my
    // translated speech" (14/20, two lines, with its information button) at
    // 140.67; Cancel and "Turn on for me" (off until a language is chosen)
    // at 196.
    Item {
        visible: root.setup
        anchors.fill: parent
        Text {
            x: 24.67; y: 24.67; width: 398.67; height: 28; verticalAlignment: Text.AlignVCenter
            text: qsTr("Set up your Interpreter")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Rectangle {
            id: setupClose
            x: 431.33; y: 25.5; width: 24; height: 23.33; radius: 4
            color: setupCloseHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: setupCloseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
        Text { x: 24.67; y: 68.67; height: 20; text: qsTr("You'll hear speech translated into"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        Combo {
            x: 24.67; y: 92.67; width: 430.67; height: 31.33
            placeholder: qsTr("Choose interpretation language")
            text: root.nameOf(root.language)
            items: root.languages.map(l => ({ label: l.name, checked: l.code === root.language }))
            onPicked: i => root.language = root.languages[i].code
        }
        Rectangle {
            id: simBox
            x: 24.67; y: 142; width: 16; height: 16; radius: 2
            color: root.voice === "0" ? theme.checkedFill : "transparent"
            border.width: 0.67; border.color: root.voice === "0" ? theme.checkedFill : theme.textStrong
            FluentIcon { visible: root.voice === "0"; anchors.centerIn: parent; name: "checkmark-12"; size: 12; color: theme.onFill(simBox, theme.textOnBrand) }
            Accessible.role: Accessible.CheckBox; Accessible.checked: root.voice === "0"
            Accessible.name: qsTr("Allow AI to simulate my voice when others hear my translated speech")
        }
        Text {
            id: simLabel
            x: 48.67; y: 140.67; width: 380.77
            wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
            text: qsTr("Allow AI to simulate my voice when others hear my translated speech")
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        MouseArea {
            x: 24.67; y: 138; width: 405; height: 42
            cursorShape: Qt.PointingHandCursor
            onClicked: root.voice = root.voice === "0" ? "1" : "0"
        }
        Item {
            x: 91.88; y: 158; width: 24; height: 24
            FluentIcon { anchors.centerIn: parent; name: "info-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: simInfo }
            ToolTip.visible: simInfo.hovered
            ToolTip.text: qsTr("This is the voice others hear when your speech is interpreted.")
            Accessible.role: Accessible.Button; Accessible.name: "information"
        }
        Row {
            x: 231.57; y: 196; spacing: 8
            Rectangle {
                width: 96; height: 31.33; radius: 4
                color: setupCancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: setupCancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: setupGo
                readonly property bool ok: !!root.language
                width: 119.76; height: 31.33; radius: 4
                color: !ok ? theme.bgDisabled : setupGoHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Turn on for me"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: setupGo.ok ? theme.textOnBrand : theme.disabled }
                HoverHandler { id: setupGoHover; cursorShape: setupGo.ok ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: setupGo.ok; onTapped: { root.confirmed(root.language, root.voice, root.balance / 100); root.close() } }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Turn on for me")
            }
        }
    }

    Column {
        id: col
        visible: !root.setup
        x: 24.67; y: 24.67; width: root.width - 49.33; spacing: 12
        Text {
            width: parent.width; height: 28; verticalAlignment: Text.AlignVCenter
            text: root.setup ? qsTr("Set up your Interpreter") : qsTr("Interpreter settings")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Heading { text: qsTr("What you hear") }
        Text { text: qsTr("You'll hear speech translated into"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Combo {
            placeholder: qsTr("Choose interpretation language")
            text: root.language === "original" ? qsTr("Original audio") : root.nameOf(root.language)
            items: (root.setup ? [] : [{ label: qsTr("Original audio"), checked: root.language === "original" }])
                .concat(root.languages.map(l => ({ label: l.name, checked: l.code === root.language })))
            onPicked: i => {
                const off = root.setup ? 0 : 1
                root.language = i < off ? "original" : root.languages[i - off].code
            }
        }
        Text {
            visible: !!root.language && root.language !== "original"
            text: qsTr("Speech in %1 won't be translated.").arg(root.nameOf(root.language))
            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
        }
        Text { text: qsTr("Balance volume"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Item {
            width: parent.width; height: 44
            Slider {
                id: slider
                width: parent.width; from: -100; to: 100; stepSize: 1
                value: root.balance
                onMoved: root.balance = Math.round(value)
                Accessible.name: qsTr("Balance volume")
            }
            Text { anchors.left: parent.left; anchors.bottom: parent.bottom; text: qsTr("More original audio"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: qsTr("More interpretation audio"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
        Heading { text: qsTr("How others hear you") }
        Text { text: qsTr("Voice others hear when your speech is translated"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Radio { label: qsTr("Simulate my voice"); checked: root.voice === "0"; onClicked: root.voice = "0" }
        Radio { label: qsTr("Automated voice"); checked: root.voice !== "0"; onClicked: if (root.voice === "0") root.voice = "1" }
        Combo {
            visible: root.voice !== "0"
            placeholder: qsTr("Select an automated voice")
            readonly property var voices: [{ v: "1", n: qsTr("Auto") }, { v: "1", n: "Ava" }, { v: "2", n: "Andrew" }, { v: "3", n: "Fable Turbo" }]
            text: root.voice === "2" ? "Andrew" : root.voice === "3" ? "Fable Turbo" : qsTr("Auto")
            items: voices.map(x => ({ label: x.n }))
            onPicked: i => root.voice = voices[i].v
        }
        Item { width: 1; height: 8 }
        Row {
            anchors.right: parent.right; spacing: 8
            Rectangle {
                id: cancel
                visible: root.setup
                width: 96; height: 32; radius: 4
                color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 0.67
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
            }
            Rectangle {
                id: confirm
                readonly property bool ok: !!root.language && !(root.setup && root.language === "original")
                width: Math.max(96, confirmText.implicitWidth + 24); height: 32; radius: 4
                color: !ok ? theme.bgDisabled : confirmHover.hovered ? theme.brandHover : theme.brandFill
                Text { id: confirmText; anchors.centerIn: parent; text: root.setup ? qsTr("Turn on for me") : qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: confirm.ok ? theme.textOnBrand : theme.disabled }
                HoverHandler { id: confirmHover; cursorShape: confirm.ok ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: confirm.ok; onTapped: { root.confirmed(root.language, root.voice, root.balance / 100); root.close() } }
                Accessible.role: Accessible.Button; Accessible.name: confirmText.text
            }
        }
    }
}
