import QtQuick

// A Fluent UI System Icon in any colour. The SVGs are single-colour glyphs
// filled with #212121, so the colour is swapped in the SVG text itself:
// this renders identically on GPU, software and offscreen backends. The
// picture comes from src/native.cpp's "fluent" image provider, which draws
// it as the item is made: an icon is there in its first frame, and one that
// changes (an app bar icon turning filled) never blanks, as in Teams.
Image {
    id: root
    property string name
    property int size: 20
    property color color: theme.icon
    width: size
    height: size
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
    fillMode: Image.PreserveAspectFit
    // Right to left the window is mirrored (src/i18n.cpp) and its pictures
    // mirrored back; Teams leaves the icons its library marks flipInRtl
    // mirrored.
    readonly property bool ostMirrorsItself: true
    mirror: theme.rtl && !theme.iconFlips(name)

    /// Colours to swap in the SVG ({"#FFDD57": "#9FDAFF"}): a coloured
    /// folder (OneDrive's Folder color).
    property var swaps: ({})
    source: name
        ? "image://fluent/" + encodeURIComponent(name) + "?c=" + encodeURIComponent(root.color.toString())
          + (Object.keys(swaps).length ? "&s=" + encodeURIComponent(Object.keys(swaps).map(k => k + "," + swaps[k]).join(";")) : "")
        : ""
}
