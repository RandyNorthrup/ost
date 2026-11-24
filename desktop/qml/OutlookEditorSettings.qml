import QtQuick
import QtQuick.Controls.Basic

// The body's Editor button: Outlook's "Microsoft Editor Settings" (Teams
// desktop on winpc, 2026-11-24, CSS px): 600 wide and the page's height,
// radius 8, padding 24.67; the title 20/600 and Cancel's ✕ (32 x 31.33) at
// 543.33; Enable auto correct, Capitalize 'I' (English only) and Enable
// auto capitalization (14 px at 24.67, 40 apart from 74, their switches at
// 509.33); "Proofing language" 14/600 #616161 at 194 over its dropdown
// (300 x 32, 232 down: your Editor languages); a box (520.67 wide at 26.67,
// 280, a 0.67 #D1D1D1 edge, radius 4) with "Corrections" (Spelling,
// Grammar: 36 px rows, the label at 75.33, the switch at 474.67) and the
// greyed premium "Refinements" (Clarity, Conciseness, Formality,
// Inclusiveness, Punctuation Conventions, Sensitive Geopolitical
// References, Vocabulary) with "Try Editor's advanced writing suggestions.
// Go premium"; Reset to default, OK and Cancel at the bottom (577.33).
// The switches are OST's Editor options (the ones Teams' Editor uses, by
// language); OK keeps them.
Popup {
    id: dlg
    parent: Overlay.overlay
    modal: true; padding: 0
    x: (parent.width - width) / 2; y: 0
    width: 600; height: Math.min(632, parent ? parent.height : 632)
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    property var st: ({ languages: [], supported: [], critiques: {}, autocorrect: [] })
    property var opts: ({})
    readonly property string lang: st.languages && st.languages.length ? st.languages[0] : ""
    readonly property var defaults: ({ autocorrect: true, capitalizeI: true, autoCapitalize: true, spelling: true, grammar: true })
    onOpened: {
        backend.editorReadSettings()
        try { st = JSON.parse(backend.editorSettingsJson()) } catch (e) {}
        let saved = {}
        try { saved = JSON.parse(backend.setting("outlookEditorOptions") || "{}") } catch (e) {}
        const o = Object.assign({}, defaults, saved)
        if (lang) o.autocorrect = (st.autocorrect || []).indexOf(lang) >= 0 || saved.autocorrect === undefined
        opts = o
    }
    Connections { target: backend; function onEditorSettingsChanged() { try { dlg.st = JSON.parse(backend.editorSettingsJson()) } catch (e) {} } }
    function set(k, v) { const o = Object.assign({}, opts); o[k] = v; opts = o }
    function nameOf(code) { const l = (st.supported || []).find(x => x.code === code); return l ? l.native : code }
    function accept() {
        backend.setSetting("outlookEditorOptions", JSON.stringify(opts))
        if (lang) {
            const l = (st.autocorrect || []).filter(x => x !== lang)
            backend.setSetting("editorAutoCorrect", JSON.stringify(opts.autocorrect ? l.concat([lang]) : l))
        }
        close()
    }

    Text { x: 24.67; y: 24.67; height: 31.33; verticalAlignment: Text.AlignVCenter; text: qsTr("Microsoft Editor Settings"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
    Rectangle {
        x: 543.33; y: 24.67; width: 32; height: 31.33; radius: 4; color: xHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: xHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
    }
    Flickable {
        x: 0; y: 74; width: 600; height: dlg.height - 74 - 78
        clip: true; contentHeight: body.height + 12
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        Item {
            id: body
            width: 600; height: 676
            Repeater {
                model: [["autocorrect", qsTr("Enable auto correct")], ["capitalizeI", qsTr("Capitalize 'I' (English only)")], ["autoCapitalize", qsTr("Enable auto capitalization")]]
                Item {
                    id: srow
                    required property var modelData
                    required property int index
                    y: index * 40; width: 600; height: 20
                    Text { x: 24.67; height: 20; verticalAlignment: Text.AlignVCenter; text: srow.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    EdSwitch { x: 509.33; on: !!dlg.opts[srow.modelData[0]]; label: srow.modelData[1]; onToggled: dlg.set(srow.modelData[0], !dlg.opts[srow.modelData[0]]) }
                }
            }
            Text { x: 24.67; y: 120; height: 30; verticalAlignment: Text.AlignVCenter; text: qsTr("Proofing language"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
            Rectangle {
                x: 24.67; y: 158; width: 300; height: 32; radius: 2
                color: theme.surface; border.width: 0.67; border.color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF")
                Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: dlg.lang ? dlg.nameOf(dlg.lang) : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                FluentIcon { x: 276; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: theme.textSecondary }
                Accessible.role: Accessible.ComboBox
                Accessible.name: qsTr("Proofing language")
            }
            Rectangle {
                x: 26.67; y: 206; width: 520.67; height: 457.33; radius: 4
                color: "transparent"; border.width: 0.67; border.color: theme.stroke
                Text { x: 24.67; y: 12.67; height: 30; verticalAlignment: Text.AlignVCenter; text: qsTr("Corrections"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Repeater {
                    model: [["spelling", qsTr("Spelling"), true], ["grammar", qsTr("Grammar"), true],
                            ["", qsTr("Clarity"), false], ["", qsTr("Conciseness"), false], ["", qsTr("Formality"), false], ["", qsTr("Inclusiveness"), false],
                            ["", qsTr("Punctuation Conventions"), false], ["", qsTr("Sensitive Geopolitical References"), false], ["", qsTr("Vocabulary"), false]]
                    Item {
                        id: trow
                        required property var modelData
                        required property int index
                        readonly property bool live: modelData[2]
                        x: 14.67; y: 42.67 + index * 36 + (index >= 2 ? 30 : 0); width: 491.33; height: 36
                        FluentIcon { x: 10; y: 10; name: "chevron-right-16"; size: 12; color: theme.textStrong }
                        Text { x: 34; height: 36; verticalAlignment: Text.AlignVCenter; text: trow.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: trow.live ? theme.text : theme.disabled }
                        EdSwitch { x: 433.33; y: 8; on: trow.live && !!dlg.opts[trow.modelData[0]]; enabledState: trow.live; label: trow.modelData[1]; onToggled: if (trow.live) dlg.set(trow.modelData[0], !dlg.opts[trow.modelData[0]]) }
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: trow.modelData[1]
                    }
                }
                Text { x: 24.67; y: 114.67; height: 30; verticalAlignment: Text.AlignVCenter; text: qsTr("Refinements"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.disabled }
                Rectangle {
                    x: 0.67; y: 396.67; width: 519.33; height: 48; color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                    Row {
                        x: 56; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: qsTr("Try Editor's advanced writing suggestions."); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        Text { text: qsTr("Go premium"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.brandLink }
                    }
                }
            }
        }
    }
    Rectangle {
        x: 24.67; y: dlg.height - 54.67; width: resetText.implicitWidth + 24; height: 31.33; radius: 4
        color: resetHover.hovered ? theme.rowHover : theme.surface; border.width: 0.67; border.color: theme.stroke
        Text { id: resetText; anchors.centerIn: parent; text: qsTr("Reset to default"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.opts = Object.assign({}, dlg.defaults) }
        Accessible.role: Accessible.Button; Accessible.name: resetText.text
    }
    Rectangle {
        x: 375.33; y: dlg.height - 54.67; width: 96; height: 31.33; radius: 4
        color: okHover.hovered ? theme.brandHover : theme.brandFill
        Text { anchors.centerIn: parent; text: qsTr("OK"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
        HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.accept() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("OK")
    }
    Rectangle {
        x: 479.33; y: dlg.height - 54.67; width: 96; height: 31.33; radius: 4
        color: canHover.hovered ? theme.rowHover : theme.surface; border.width: 0.67; border.color: theme.stroke
        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        HoverHandler { id: canHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Cancel")
    }

    // Fluent's switch (40 x 20): brand with a white knob at the right on,
    // a #616161 edge and knob at the left off, greyed #E0E0E0.
    component EdSwitch: Rectangle {
        id: es
        property bool on: false
        property bool enabledState: true
        property string label
        signal toggled()
        width: 40; height: 20; radius: 10
        color: on ? theme.checkedFill : "transparent"
        border.width: on ? 0 : 0.67
        border.color: enabledState ? theme.textSecondary : theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
        Rectangle { x: es.on ? 23 : 3; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: !es.enabledState ? theme.disabled : es.on ? "white" : theme.textSecondary }
        TapHandler { enabled: es.enabledState; onTapped: es.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: es.label
        Accessible.checked: es.on
    }
}
