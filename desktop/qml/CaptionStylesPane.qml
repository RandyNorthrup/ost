import QtQuick
import QtQuick.Controls

// Teams' Caption styles pane (caption settings ▸ Caption styles; measured
// on winpc, 2026-11-09): #F5F5F5, the rail header "Caption styles" (close:
// "Hide caption styles panel"), then 20.67 in:
// - "Font color" (14/20, y 77) and seven 32 px swatches 38 apart (y 106):
//   White, Black, Red, Green, Blue, Yellow, Aqua;
// - "Background color" (y 168) and its swatches (y 197): Black, White, Red,
//   Green, Blue, Yellow, Aqua;
// - "Font size" (y 259) over a 318 x 30 dropdown (y 284.67): Small,
//   Medium, Large, Extra large;
// - "Panel height" (y 341.33) over its dropdown (y 367): Small, Medium,
//   Large.
// Swatches: radius 4, a 0.67 #D1D1D1 border, the chosen one 2 px #444791.
// Teams keeps these on the device (its "closed-captions-settings").
Rectangle {
    id: root
    /// {fontColor, backgroundColor, fontSize, captionHeight}
    property var styles: ({})
    signal closed()
    signal changed(var styles)
    color: theme.pane

    readonly property bool lightTheme: theme.pick(true, false)
    readonly property string fontColor: styles.fontColor || (lightTheme ? "Black" : "White")
    readonly property string backgroundColor: styles.backgroundColor || (lightTheme ? "White" : "Black")
    readonly property string fontSize: styles.fontSize || "Medium"
    readonly property string captionHeight: styles.captionHeight || "Medium"
    function set(key, value) {
        const s = Object.assign({ fontColor: fontColor, backgroundColor: backgroundColor,
                                  fontSize: fontSize, captionHeight: captionHeight }, styles)
        s[key] = value
        changed(s)
    }
    readonly property var colors: ({ White: "#FFFFFF", Black: "#000000", Red: "#FE0000", Green: "#00FF00",
                                     Blue: "#0000FF", Yellow: "#FFFF00", Aqua: "#00FFFF" })

    Item {
        id: header
        y: 3; width: parent.width; height: 58
        Text {
            x: 20.67; y: 17.67; height: 22
            verticalAlignment: Text.AlignVCenter
            text: "Caption styles"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            x: parent.width - 52; y: 13.67; width: 32; height: 30; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.closed() }
            ToolTip.visible: closeHover.hovered
            ToolTip.delay: 250
            ToolTip.text: "Hide caption styles panel"
            Accessible.role: Accessible.Button
            Accessible.name: "Hide caption styles panel"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }

    component Label: Text {
        x: 20.67; height: 20
        verticalAlignment: Text.AlignVCenter
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
    }
    component Swatches: Row {
        id: sw
        property var names: []
        property string selected
        property string labelFormat
        signal picked(string name)
        x: 20.67; spacing: 6
        Repeater {
            model: sw.names
            Rectangle {
                required property string modelData
                width: 32; height: 32; radius: 4
                color: root.colors[modelData]
                border.width: modelData === sw.selected ? 2 : 0.67
                border.color: modelData === sw.selected ? "#444791" : "#D1D1D1"
                HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sw.picked(modelData) }
                ToolTip.visible: swh.hovered
                ToolTip.delay: 250
                ToolTip.text: modelData
                Accessible.role: Accessible.RadioButton
                Accessible.name: sw.labelFormat.replace("%1", modelData)
                Accessible.checked: modelData === sw.selected
            }
        }
    }

    Label { y: 77; text: "Font color" }
    Swatches {
        y: 106
        names: ["White", "Black", "Red", "Green", "Blue", "Yellow", "Aqua"]
        selected: root.fontColor
        labelFormat: "Captions font color: %1"
        onPicked: n => root.set("fontColor", n)
    }
    Label { y: 168; text: "Background color" }
    Swatches {
        y: 197
        names: ["Black", "White", "Red", "Green", "Blue", "Yellow", "Aqua"]
        selected: root.backgroundColor
        labelFormat: "Background color: %1"
        onPicked: n => root.set("backgroundColor", n)
    }
    Label { y: 259; text: "Font size" }
    Dropdown {
        x: 21.33; y: 284.67; width: 318
        readonly property var names: ({ Small: "Small", Medium: "Medium", Large: "Large", Larger: "Extra large" })
        options: [["Small", "Small"], ["Medium", "Medium"], ["Large", "Large"], ["Larger", "Extra large"]]
        label: names[root.fontSize] || "Medium"
        accessibleName: "Font size"
        onPicked: v => root.set("fontSize", v)
    }
    Label { y: 341.33; text: "Panel height" }
    Dropdown {
        x: 21.33; y: 367; width: 318
        options: [["Small", "Small"], ["Medium", "Medium"], ["Large", "Large"]]
        label: root.captionHeight
        accessibleName: "Caption window height"
        onPicked: v => root.set("captionHeight", v)
    }
}
