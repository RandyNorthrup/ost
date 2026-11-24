import QtQuick
import QtQuick.Controls

// Teams' "Choose an Interpreter mode" (ai-interpretation-mode-selection-
// dialog, measured on winpc 2026-11-20): a 490 x 525.33 alert dialog,
// padding 24, radius 8; a round picture at the top, the title (16/600,
// centred) at 134.67 and Close (32 x 31.33) at 437.33, 22.67; two cards
// (436.67 wide, radius 16, a 0.67 px #D1D1D1 edge, brand #4F52B2 when
// picked): "Consecutive interpretation" (14/600) with the "Uses credits"
// (#F5F5F5 / #616161) and "On for everyone" (#E8EBFA / #5B5FC7) badges
// (10/600, 16 tall, pill), its description (14/20 #424242) and two
// 162 x 32 "Language" boxes with the swap glyph between, at 192.67 (143.33
// tall); "Simultaneous interpretation" with "On for you" at 346 (97.33
// tall); "Learn more" (#4F52B2) at 24.67, 479.33; Cancel and "Turn on"
// (consecutive) or "Next" (simultaneous), 96 wide, at 469.33.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 490; height: 525.33
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    /// [{code, name}] the languages consecutive interpretation takes.
    property var languages: []
    /// Consecutive is on for everyone: only the organizer may turn it on.
    property bool canConsecutive: true
    signal consecutive(string first, string second)
    signal simultaneous()

    property string mode: canConsecutive ? "consecutive" : "simultaneous"
    property string first: ""
    property string second: ""
    function show() { mode = canConsecutive ? "consecutive" : "simultaneous"; first = ""; second = ""; open() }
    function nameOf(code) { const l = languages.find(x => x.code === code); return l ? l.name : "" }

    component Badge: Rectangle {
        property string text
        property color fg
        height: 16; radius: 8; width: bt.implicitWidth + 8
        Text { id: bt; anchors.centerIn: parent; text: parent.text; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: parent.fg }
    }
    component Card: Rectangle {
        id: card
        property string key
        property bool picked: root.mode === key
        radius: 16; color: theme.surface
        border.width: 0.67; border.color: picked ? theme.brandLink : theme.stroke
        Rectangle {
            x: 13.33; y: card.key === "consecutive" ? 42.67 : 40.67; width: 16; height: 16; radius: 8
            color: "transparent"; border.width: 0.67; border.color: card.picked ? theme.brand : theme.textSecondary
            Rectangle { visible: card.picked; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
        }
        TapHandler { enabled: card.enabled; onTapped: root.mode = card.key }
        Accessible.role: Accessible.RadioButton; Accessible.checked: picked
    }
    component LangBox: Rectangle {
        id: lb
        property string code
        property string label
        signal picked(string code)
        width: 162; height: 32; radius: 4
        color: theme.surface; border.width: 0.67; border.color: lb.enabled ? theme.stroke : theme.divider
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: 120; elide: Text.ElideRight
            text: lb.code ? root.nameOf(lb.code) : qsTr("Language")
            font.family: theme.font; font.pixelSize: 14
            color: !lb.enabled ? theme.disabled : lb.code ? theme.text : theme.textSecondary
        }
        FluentIcon { x: 132; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: lb.enabled ? theme.textSecondary : theme.disabled }
        TapHandler { enabled: lb.enabled; onTapped: menu.open() }
        Accessible.role: Accessible.ComboBox; Accessible.name: lb.label
        MenuPopup {
            id: menu; y: parent.height + 4; width: 200; height: Math.min(implicitHeight, 300)
            items: root.languages.map(l => ({ label: l.name, checked: l.code === lb.code }))
            onPicked: i => lb.picked(root.languages[i].code)
        }
    }

    // The picture: Teams' own artwork isn't OST's to ship; a Fluent round
    // backdrop with Interpreter's glyph takes its place and size.
    Rectangle {
        x: (root.width - 110) / 2; y: 24.67; width: 110; height: 110; radius: 55
        color: theme.brandTint
        FluentIcon { anchors.centerIn: parent; name: "sound-wave-circle-sparkle-20"; size: 48; color: theme.brand }
    }
    Text {
        x: 24.67; y: 134.67; width: 432.67; height: 40
        topPadding: 15; bottomPadding: 5
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("Choose an Interpreter mode")
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    Rectangle {
        id: close
        x: 437.33; y: 22.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close interpreter mode dialog")
    }
    Card {
        key: "consecutive"; enabled: root.canConsecutive
        x: 24.67; y: 192.67; width: 436.67; height: 143.33
        Accessible.name: qsTr("Consecutive interpretation")
        Row {
            x: 39.67; y: 21.33; spacing: 4
            Text { text: qsTr("Consecutive interpretation"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Badge { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Uses credits"); color: theme.menuHover; fg: theme.textSecondary }
            Badge { anchors.verticalCenter: parent.verticalCenter; text: qsTr("On for everyone"); color: theme.brandTint; fg: theme.brand }
        }
        Text {
            x: 39.67; y: 40.67; width: 396.33
            wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
            text: qsTr("Interpreter translates after each speaker. Good for interactive discussions in two languages.")
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
        }
        LangBox { x: 41.67; y: 90.67; enabled: parent.picked; code: root.first; label: qsTr("1st interpretation language"); onPicked: c => root.first = c }
        FluentIcon { x: 211.67; y: 94.67; name: "arrow-swap-20"; size: 24; color: parent.picked ? theme.text : theme.disabled }
        LangBox { x: 243.67; y: 90.67; enabled: parent.picked; code: root.second; label: qsTr("2nd interpretation language"); onPicked: c => root.second = c }
    }
    Card {
        key: "simultaneous"
        x: 24.67; y: 346; width: 436.67; height: 97.33
        Accessible.name: qsTr("Simultaneous interpretation")
        Row {
            x: 41.67; y: 18.67; spacing: 4
            Text { text: qsTr("Simultaneous interpretation"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Badge { anchors.verticalCenter: parent.verticalCenter; text: qsTr("On for you"); color: theme.brandTint; fg: theme.brand }
        }
        Text {
            x: 41.67; y: 38.67; width: 386.33
            wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight
            text: qsTr("Real-time translation into each participant’s chosen language. Good for one‑way communication like town halls.")
            font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
        }
    }
    Text {
        x: 24.67; y: 479.33; height: 20
        text: qsTr("Learn more"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2321802") }
        Accessible.role: Accessible.Link; Accessible.name: text
    }
    Row {
        x: 261.33; y: 469.33; spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke; border.width: 0.67
            Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
        }
        Rectangle {
            id: go
            readonly property bool ok: root.mode === "simultaneous" || (!!root.first && !!root.second && root.first !== root.second)
            width: 96; height: 31.33; radius: 4
            color: !ok ? theme.bgDisabled : goHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: root.mode === "consecutive" ? qsTr("Turn on") : qsTr("Next"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: go.ok ? theme.textOnBrand : theme.disabled }
            HoverHandler { id: goHover; cursorShape: go.ok ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler {
                enabled: go.ok
                onTapped: { root.close(); if (root.mode === "consecutive") root.consecutive(root.first, root.second); else root.simultaneous() }
            }
            Accessible.role: Accessible.Button
            Accessible.name: root.mode === "consecutive" ? qsTr("Turn on consecutive interpretation") : qsTr("Next")
        }
    }
}
