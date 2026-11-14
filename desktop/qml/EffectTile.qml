import QtQuick
import QtQuick.Controls

// One of Teams' video effect tiles (the Backgrounds grids of Camera ▾, the
// pre-join picker and the Video effects pane; measured on winpc,
// 2026-11-14): a #E6E6E6 tile (radius 2) — 77 x 48 in the flyout, 74 x 42
// in the pre-join picker, 88 x 50 in the pane. A picture fills it (an
// animated one carries the 20 px video-clip mark 3 px in from the bottom
// left); None, Standard blur and Show all show a 16 px glyph over a
// 10 px/600 label, the pair centred. Standard blur's glyph sits left of a
// 16 px chevron that opens the blur menu. The chosen tile has a 2 px brand
// ring outside it and Teams' Checkmark12 at its top right.
Item {
    id: tile
    /// "none", "blur", "showall" or "image".
    property string kind: "image"
    property string label: ""
    property string thumb: ""
    property bool animated: false
    property bool selected: false
    /// The name read out (Teams' aria-label).
    property string accessibleName: label
    /// The blur tile's kind: "standard" or "portrait".
    property string blurKind: "standard"
    signal picked()
    /// A blur was chosen in the blur tile's menu.
    signal blurPicked(string kind)
    width: 88; height: 50

    // Glyph (16) + 5 + label (12), centred, a pixel low as Teams draws it.
    readonly property real glyphY: Math.round((height - 33) / 2 + 1)

    Rectangle {
        visible: tile.selected
        x: -2; y: -2; width: tile.width + 4; height: tile.height + 4; radius: 4
        color: "transparent"
        border.color: theme.brand; border.width: 2
    }
    Rectangle {
        anchors.fill: parent; radius: 2
        color: hover.hovered && tile.kind !== "image" ? theme.hover : theme.effectTile
    }
    Image {
        visible: tile.kind === "image"
        anchors.fill: parent
        source: tile.kind === "image" ? tile.thumb : ""
        sourceSize: Qt.size(tile.width * 2, tile.height * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: hover.hovered ? 0.9 : 1
    }
    FluentIcon {
        visible: tile.kind === "image" && tile.animated
        x: 3; y: tile.height - 22.4
        name: "video-clip-20"; size: 20; color: "white"
    }
    FluentIcon {
        visible: tile.kind === "none" || tile.kind === "showall"
        x: (tile.width - 16) / 2; y: tile.glyphY
        name: tile.kind === "none" ? "prohibited-20" : "more-horizontal-20-filled"
        size: 16; color: theme.text
    }
    FluentIcon {
        visible: tile.kind === "blur"
        x: tile.width / 2 + 4 - 20; y: tile.glyphY
        name: "video-background-effect-20"; size: 16; color: theme.text
    }
    Rectangle {
        id: chev
        visible: tile.kind === "blur"
        x: tile.width / 2 + 4; y: tile.glyphY; width: 16; height: 16; radius: 4
        color: chevHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "chevron-down-16"; size: 14; color: theme.textStrong }
        HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: blurMenu.opened ? blurMenu.close() : blurMenu.open() }
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: "Blur options"
    }
    Text {
        visible: tile.kind !== "image"
        x: (tile.width - 74) / 2; y: tile.glyphY + 21; width: 74; height: 12
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: tile.label
        font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
        color: theme.text
    }
    // Teams' Checkmark12: its filled part under its outline.
    Item {
        visible: tile.selected
        x: tile.width - 17.7; y: 1; width: 16; height: 16
        // Measured: the filled part #8A8A8A, the outline white.
        FluentIcon { anchors.fill: parent; name: "tile-check-filled"; size: 16; color: "#8A8A8A" }
        FluentIcon { anchors.fill: parent; name: "tile-check-outline"; size: 16; color: "white" }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: if (!chevHover.hovered) tile.picked() }

    // The blur menu (measured: 128.7 x 66, padding 4; 32 px radio items
    // with a 16 px checkmark 6 in and 14 px text 26 in), 4.8 below the
    // chevron and 4.9 right of it.
    Popup {
        id: blurMenu
        parent: Overlay.overlay
        width: 128.67; height: 74; padding: 4
        background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
        onAboutToShow: {
            const p = chev.mapToItem(Overlay.overlay, 0, 0)
            x = p.x + 4.9; y = p.y + chev.height + 4.8 - 4
        }
        Column {
            Repeater {
                model: [{ k: "standard", t: "Standard blur" }, { k: "portrait", t: "Portrait blur" }]
                Rectangle {
                    id: bm
                    required property var modelData
                    width: 120.67; height: 32; radius: 4
                    color: bmHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 6; y: 8; visible: tile.blurKind === bm.modelData.k; name: "checkmark-16"; size: 16; color: theme.textStrong }
                    Text {
                        x: 26; anchors.verticalCenter: parent.verticalCenter
                        text: bm.modelData.t
                        font.family: theme.font; font.pixelSize: 14
                        color: theme.textStrong
                    }
                    HoverHandler { id: bmHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { blurMenu.close(); tile.blurPicked(bm.modelData.k) } }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: bm.modelData.t
                    Accessible.checked: tile.blurKind === bm.modelData.k
                }
            }
        }
    }
    ToolTip.visible: hover.hovered && tile.kind === "image" && tile.label.length > 0
    ToolTip.delay: 500
    ToolTip.text: tile.label
    Accessible.role: tile.kind === "showall" ? Accessible.MenuItem : Accessible.CheckBox
    Accessible.name: tile.accessibleName
    Accessible.checked: tile.selected
}
