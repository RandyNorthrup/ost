import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes

// Teams' "Customize your reactions & appearance in Teams" dialog
// (customize-reactions-dialog, measured on winpc): 600 x 392.7, radius 4,
// content 24.7 in.
// - The title (20/28 semibold) and "Click on a reaction below, then choose
//   an emoji to replace it with." (14/20).
// - Five 46 px slots, 15 apart and centred, at y 116.7: a 1 px
//   NeutralStroke1 border, radius 4, the 30 px emoticon at 8. An empty slot
//   is "Choose an emoji" with Add24. Clicking one opens the reaction picker
//   centred under it; Backspace or Delete removes it.
// - "Choose a skin tone. After selection, reactions and emoji will appear
//   with this skin tone." (470 wide), then six 30 px tone circles in 42 x 50
//   radios, 15 apart and centred, at y 258.7; the selected one has a 30 x 4
//   brand bar under it. Picking a tone re-tones the slots that have tones.
// - Cancel and Save (96 x 31.3); Save stays disabled until something
//   changes. Saving writes defaultMessageReactions and preferredSkinToneIndex.
Popup {
    id: root
    modal: true; focus: true
    width: 600; height: 392.7
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }

    readonly property int maxSlots: 5
    // Client ids, as the hover bar shows them.
    property var slots: []
    property int tone: 0
    property var startSlots: []
    property int startTone: 0
    property int picking: -1
    readonly property bool changed: tone !== startTone || JSON.stringify(slots) !== JSON.stringify(startSlots)
    readonly property bool saving: backend.reactionPrefsResult === "saving"
    readonly property var toneNames: ["None", "Light", "Medium light", "Medium", "Medium dark", "Dark"]
    // Teams' tone circles: radial gradients lit from the lower left.
    readonly property var toneStops: [["#FCD53F", "#FFB02E"], ["#F4BFAA", "#B77C6C"], ["#E8B192", "#A0685B"], ["#B28876", "#794E54"], ["#875D59", "#4E2C32"], ["#26131B", "#503B3B"]]

    function commonKey(id) { const m = /^(.{1,40})-tone\d$/.exec(id); return m ? m[1] : id }
    onAboutToShow: {
        const q = backend.quickReactionsJson ? JSON.parse(backend.quickReactionsJson) : ["yes", "heart", "laugh", "surprised"]
        startSlots = q.slice(0, maxSlots); slots = startSlots.slice()
        startTone = backend.skinTone; tone = startTone
        picking = -1
        backend.reactionPrefsResult = ""
    }
    Connections {
        target: backend
        function onReactionPrefsResultChanged() { if (root.opened && backend.reactionPrefsResult === "ok") root.close() }
    }
    function setTone(t) {
        tone = t
        slots = slots.map(k => backend.emoticonInTone(root.commonKey(k), t))
    }
    function setSlot(i, id) {
        const s = slots.slice()
        if (i < s.length) s[i] = id; else s.push(id)
        slots = s
    }
    function removeSlot(i) {
        if (i >= slots.length) return
        const s = slots.slice(); s.splice(i, 1); slots = s
    }

    Text {
        x: 24.7; y: 24.7; width: 550.7; height: 28; verticalAlignment: Text.AlignVCenter
        text: "Customize your reactions & appearance in Teams"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading
    }
    Text {
        x: 24.7; y: 61.3; height: 18.7; verticalAlignment: Text.AlignVCenter
        text: "Click on a reaction below, then choose an emoji to replace it with."
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    Row {
        id: slotRow
        x: (root.width - (root.maxSlots * 46 + (root.maxSlots - 1) * 15)) / 2; y: 116.7
        spacing: 15
        Repeater {
            model: Math.min(root.maxSlots, root.slots.length + 1)
            Rectangle {
                id: slot
                required property int index
                readonly property string key: index < root.slots.length ? root.slots[index] : ""
                readonly property bool lit: slotHover.hovered || root.picking === index || activeFocus
                width: 46; height: 46; radius: 4
                color: lit ? theme.menuHover : theme.surface
                border.color: lit ? theme.strokeHover : theme.stroke
                activeFocusOnTab: true
                Emoticon { visible: !!slot.key; x: 8; y: 8; key: slot.key; named: "medium"; size: 30 }
                FluentIcon { visible: !slot.key; anchors.centerIn: parent; name: "add-24"; size: 24; color: theme.textStrong }
                HoverHandler { id: slotHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { slot.forceActiveFocus(); root.openPicker(slot, slot.index) } }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { root.removeSlot(slot.index); event.accepted = true }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.openPicker(slot, slot.index); event.accepted = true }
                }
                Accessible.role: Accessible.Button
                Accessible.name: key ? backend.emoticonName(key) : "Choose an emoji"
                Accessible.description: key ? "Use backspace or delete to remove reaction" : ""
            }
        }
    }
    Text {
        x: 24.7; y: 198.7; width: 470
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: "Choose a skin tone. After selection, reactions and emoji will appear with this skin tone."
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
    }
    Row {
        x: 24.7 + (550.7 - (6 * 42 + 5 * 15)) / 2; y: 258.7
        spacing: 15
        Accessible.role: Accessible.Grouping
        Repeater {
            model: 6
            Item {
                id: radio
                required property int index
                readonly property bool checked: root.tone === index
                width: 42; height: 50
                activeFocusOnTab: checked
                Shape {
                    x: 6; y: 6; width: 30; height: 30
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            // The SVG's gradient (centre 21.14, 7.5, radius
                            // 23.19) on a circle turned 180 degrees.
                            centerX: 8.86; centerY: 22.5; centerRadius: 23.19
                            focalX: 8.86; focalY: 22.5; focalRadius: 0
                            GradientStop { position: 0.264298; color: root.toneStops[radio.index][0] }
                            GradientStop { position: 1; color: root.toneStops[radio.index][1] }
                        }
                        PathAngleArc { centerX: 15; centerY: 15; radiusX: 15; radiusY: 15; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Rectangle {
                    visible: radio.checked
                    x: 6; y: 40; width: 30; height: 4; radius: 2
                    color: theme.brand
                }
                Rectangle {
                    visible: radio.activeFocus
                    anchors.fill: parent; radius: 4
                    color: "transparent"; border.color: theme.text; border.width: 2
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.setTone(radio.index) }
                Keys.onLeftPressed: if (radio.index > 0) root.setTone(radio.index - 1)
                Keys.onRightPressed: if (radio.index < 5) root.setTone(radio.index + 1)
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.toneNames[index]
                Accessible.checked: checked
            }
        }
    }
    Row {
        x: 375.3; y: 336.7; spacing: 8
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered && !root.saving ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: root.saving ? theme.disabled : theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.saving; onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            readonly property bool can: root.changed && !root.saving
            width: 96; height: 31.3; radius: 4
            color: !can ? theme.bgDisabled : saveHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.disabledStrong }
            HoverHandler { id: saveHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: backend.saveReactionPrefs(JSON.stringify(root.slots), root.tone) }
            Accessible.role: Accessible.Button
            Accessible.name: "Save"
        }
    }

    // The picker for a slot: Teams' reaction picker without its customize
    // button, centred under the slot.
    ReactionPicker {
        id: slotPicker
        customizing: true
        onPicked: (key, on) => root.setSlot(root.picking, key)
        onClosed: root.picking = -1
    }
    function openPicker(slot, i) {
        picking = i
        slotPicker.parent = slot
        slotPicker.x = (slot.width - slotPicker.width) / 2
        slotPicker.y = slot.height
        slotPicker.open()
    }
    // Test hook.
    function pickForTest(i) {
        const slot = [...slotRow.children].find(c => c.index === i && c.width === 46)
        if (slot) openPicker(slot, i)
    }
}
