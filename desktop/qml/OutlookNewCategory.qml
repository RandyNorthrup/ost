import QtQuick
import QtQuick.Controls.Basic

// Categories ▸ New category: Outlook's "Create new category" (Teams desktop
// on winpc, 2026-11-24, CSS px): 600 x 334.67, radius 8, padding 24.67;
// "Create new category" 20/600; "Name" 14/600 70.67 down over the name
// (518.67 x 32, a 0.67 #B3B3B3 edge, radius 4, "Name your category") and
// the favourite star (32 x 31.33, "Favoriting adds the category to your
// folder pane"); "Color" 14/600 152.67 down over Outlook's 25 colours and
// None, 30 px circles 42.35 apart in two rows of 13 from 29.67, 187.67 and
// 227.67 (each its background, edge and a 14.33 px "A" in its text colour;
// the picked one shrinks to 22 px inside a 2 px brand ring); Save (96 x
// 31.33, greyed until named) and Cancel 278.67 down. The colour is
// Outlook's preset number (-1 None).
Popup {
    id: dlg
    /// The names already taken.
    property var existing: []
    signal created(string name, int color)
    parent: Overlay.overlay
    modal: true; padding: 0
    x: (parent.width - width) / 2; y: (parent.height - height) / 2
    width: 600; height: 334.67
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    property int picked: 0
    property bool favorite: false
    function openNew() { nameInput.text = ""; picked = 0; favorite = false; open(); nameInput.forceActiveFocus() }
    readonly property bool taken: existing.some(n => n.toLowerCase() === nameInput.text.trim().toLowerCase())
    readonly property bool ready: nameInput.text.trim().length > 0 && !taken
    // [name, preset, background, edge, text] in the picker's order.
    readonly property var colors: [
        [qsTr("Dark red"), 15, "#E9C7CD", "#AC4F5E", "#420610"], [qsTr("Cranberry"), 0, "#F6D1D5", "#DC626D", "#6E0811"],
        [qsTr("Dark orange"), 16, "#F9DCD1", "#E9835E", "#7A2101"], [qsTr("Bronze"), 1, "#F1D9CC", "#CA8057", "#5E2405"],
        [qsTr("Peach"), 2, "#FFDDB3", "#FFBA66", "#4D2A00"], [qsTr("Marigold"), 3, "#FCEFD3", "#F2C661", "#463100"],
        [qsTr("Gold"), 18, "#F5EECE", "#DAC157", "#3A2F00"], [qsTr("Dark brown"), 17, "#CAADA3", "#946B5C", "#2B1710"],
        [qsTr("Lime"), 6, "#E5F1D3", "#A4CC6C", "#22330B"], [qsTr("Forest"), 21, "#BDD99B", "#85B44C", "#162702"],
        [qsTr("Light green"), 4, "#CEF0CD", "#5EC75A", "#063004"], [qsTr("Dark green"), 19, "#9AD29A", "#4DA64D", "#032003"],
        [qsTr("Light teal"), 5, "#A6E9ED", "#58D3DB", "#00373A"], [qsTr("Dark teal"), 20, "#92D1D1", "#41A3A3", "#003939"],
        [qsTr("Steel"), 11, "#94C8D4", "#4496A9", "#00333F"], [qsTr("Sky blue"), 7, "#D4F4FD", "#63D7F7", "#004659"],
        [qsTr("Dark blue"), 22, "#C2D6E7", "#4178A3", "#002039"], [qsTr("Lavender"), 8, "#E7E4FB", "#A79CF1", "#3F3682"],
        [qsTr("Dark purple"), 23, "#B9A3D3", "#7E5CA7", "#240F3C"], [qsTr("Pink"), 9, "#FBDDF0", "#EF85C8", "#80215D"],
        [qsTr("Plum"), 24, "#D696C0", "#AD4589", "#43002B"], [qsTr("Beige"), 12, "#EAE8E8", "#AFABAA", "#444241"],
        [qsTr("Mink"), 13, "#CECCCB", "#9E9B99", "#343231"], [qsTr("Silver"), 10, "#D8DFE0", "#B3BFC2", "#282D2E"],
        [qsTr("Charcoal"), 14, "#C4C4C4", "#888888", "#202020"], [qsTr("None"), -1, "transparent", "#D1D1D1", "#424242"]]

    Text { x: 24.67; y: 24.67; height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Create new category"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
    Text { x: 24.67; y: 70.67; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
    Rectangle {
        x: 24.67; y: 100.67; width: 518.67; height: 32; radius: 4
        color: theme.surface; border.width: 0.67; border.color: nameInput.activeFocus ? theme.brand : theme.pick("#B3B3B3", "#666666", "#FFFFFF")
        Rectangle { visible: nameInput.activeFocus; x: 0; y: parent.height - 2; width: parent.width; height: 2; radius: 1; color: theme.brand }
        TextInput {
            id: nameInput
            x: 10.67; width: 497.33; height: 30.67; y: 0.67
            verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            Keys.onReturnPressed: if (dlg.ready) { dlg.created(nameInput.text.trim(), dlg.colors[dlg.picked][1]); dlg.close() }
            Accessible.name: qsTr("Name your category")
            Text { visible: !nameInput.text; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Name your category"); font: nameInput.font; color: theme.pick("#707070", "#ADADAD", "#FFFFFF") }
        }
    }
    Rectangle {
        x: 543.33; y: 101; width: 32; height: 31.33; radius: 4
        color: starHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: dlg.favorite ? "star-20-filled" : "star-20"; size: 20; color: dlg.favorite ? theme.brand : theme.textStrong }
        HoverHandler { id: starHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.favorite = !dlg.favorite }
        ToolTip.visible: starHover.hovered
        ToolTip.text: qsTr("Favoriting adds the category to your folder pane")
        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Favoriting adds the category to your folder pane")
        Accessible.checked: dlg.favorite
    }
    Text { x: 24.67; y: 152.67; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Color"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
    Repeater {
        model: dlg.colors
        Item {
            id: sw
            required property var modelData
            required property int index
            readonly property bool on: dlg.picked === index
            x: 29.67 + (index % 13) * 42.355; y: 187.67 + Math.floor(index / 13) * 40; width: 30; height: 30
            Rectangle { visible: sw.on; anchors.fill: parent; radius: 15; color: theme.surface; border.width: 2; border.color: theme.brand }
            Rectangle {
                anchors.centerIn: parent
                width: sw.on ? 22 : 30; height: width; radius: width / 2
                color: sw.modelData[2]; border.width: 0.67; border.color: sw.modelData[3]
                Text { anchors.centerIn: parent; text: "A"; font.family: theme.font; font.pixelSize: sw.on ? 10.33 : 14.33; color: sw.modelData[4] }
            }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.picked = sw.index }
            ToolTip.visible: swHover.hovered
            ToolTip.text: sw.modelData[0]
            Accessible.role: Accessible.RadioButton
            Accessible.name: sw.modelData[0]
            Accessible.checked: sw.on
        }
    }
    Rectangle {
        x: 375.33; y: 278.67; width: 96; height: 31.33; radius: 4
        color: dlg.ready ? (saveHover.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#3D3D3D", "#000000")
        Text { anchors.centerIn: parent; text: qsTr("Save"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: dlg.ready ? "white" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
        HoverHandler { id: saveHover; enabled: dlg.ready; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: dlg.ready; onTapped: { dlg.created(nameInput.text.trim(), dlg.colors[dlg.picked][1]); dlg.close() } }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Save")
    }
    Rectangle {
        x: 479.33; y: 278.67; width: 96; height: 31.33; radius: 4
        color: cancelHover.hovered ? theme.rowHover : theme.surface; border.width: 0.67; border.color: theme.stroke
        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.close() }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Cancel")
    }
}
