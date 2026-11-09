import QtQuick
import QtQuick.Controls.Basic

// One of the meeting timer's duration boxes (Teams' Fluent SpinButton,
// measured on winpc): 70 x 42.67 on #F5F5F5, radius 4; the two digits
// (32/32 semibold) right-aligned in 46 px; Increment / Decrement (24 x
// 16, a 14 px chevron, #616161) at the right, top and bottom. Digits only,
// two at most, zero-padded; focus selects them.
Rectangle {
    id: root
    property int value: 0
    property int max: 59
    property string label
    property string tip
    signal edited(int v)
    width: 70; height: 42.67; radius: 4
    color: theme.pick("#F5F5F5", "#1F1F1F")
    function pad(v) { return (v < 10 ? "0" : "") + v }
    // Filled from outside (+N min, a new length): show it unless typing.
    onValueChanged: if (!input.activeFocus) input.text = pad(value)
    function set(v) { const c = Math.max(0, Math.min(root.max, v)); input.text = pad(c); root.edited(c) }
    TextInput {
        id: input
        width: 46; height: parent.height
        horizontalAlignment: TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        Component.onCompleted: text = root.pad(root.value)
        maximumLength: 2
        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,2}/ }
        font.family: theme.font; font.pixelSize: 32; font.weight: Font.DemiBold
        color: theme.text
        selectByMouse: true
        onActiveFocusChanged: if (activeFocus) selectAll(); else root.set(parseInt(text || "0"))
        onTextEdited: if (text.length > 0) root.edited(Math.min(root.max, parseInt(text)))
        Keys.onUpPressed: root.set(root.value + 1)
        Keys.onDownPressed: root.set(root.value - 1)
        Accessible.role: Accessible.SpinBox
        Accessible.name: root.label
    }
    component Step: Rectangle {
        id: st
        property bool up: true
        x: 46; y: up ? 0 : 21.33
        width: 24; height: 16
        radius: 4
        color: sh.hovered ? theme.pick("#E0E0E0", "#333333") : "transparent"
        FluentIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            y: st.up ? 1.5 : -1.5
            name: st.up ? "chevron-up-16" : "chevron-down-16"; size: 14
            color: theme.textSecondary
        }
        HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.set(root.value + (st.up ? 1 : -1)) }
        Accessible.role: Accessible.Button
        Accessible.name: st.up ? "Increment value" : "Decrement value"
    }
    Step { up: true }
    Step { up: false }
    ToolTip.visible: hov.hovered
    ToolTip.delay: 500
    ToolTip.text: root.tip
    HoverHandler { id: hov }
}
