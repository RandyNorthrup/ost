import QtQuick

// A posts channel's "see more" / "see less" (Teams 26304, 395276 `nn`,
// measured on winpc 2026-11-22 in "OST TEST 206 long post"): a Fluent link
// (14 px, colorBrandForegroundLink, underlined in the hover colour on
// hover) on a 20 px row right under the cut text, at the text's start.
Text {
    id: link
    property bool expanded: false
    signal toggled()
    height: 20
    verticalAlignment: Text.AlignVCenter
    text: expanded ? qsTr("see less", "channels:ka9z5xy9i") : qsTr("see more", "channels:k5k7nxeca")
    font.family: theme.font; font.pixelSize: 14
    font.underline: hover.hovered
    color: hover.hovered ? theme.brandForeground2 : theme.brandForeground1
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: link.toggled() }
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: link.toggled()
}
