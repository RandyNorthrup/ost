import QtQuick
import QtQuick.Controls.Basic

// Teams' caption settings menu (the caption window's gear, or "…" ▸ Open
// caption settings; measured on winpc, 2026-11-09), rows 32 tall with 2
// between and padding 4:
// - "Meeting spoken language" with the language (12/20, #616161) before a
//   20 px chevron 6 in; it opens the languages to the left;
// - a divider (6 above and below);
// - Caption styles (its 20 px glyph), the Caption styles pane;
// - "Position" with "At bottom" / "At top" and a chevron;
// - a divider;
// - "Always turn on captions" and "Filter profane words" with 40 x 20
//   switches 10 in from the right.
Popup {
    id: root
    /// The meeting's spoken language code ("en-us") and its name.
    property string language: "en-us"
    property string languageName: "English (US)"
    /// [{code, name}] Teams' spoken languages.
    property var languages: []
    /// "Top" or "Bottom".
    property string position: "Bottom"
    property bool alwaysOn: false
    property bool filterProfanity: false
    signal languagePicked(string code)
    signal captionStyles()
    signal positionPicked(string position)
    signal alwaysOnToggled(bool on)
    signal filterProfanityToggled(bool on)

    padding: 4
    implicitWidth: Math.ceil(Math.max(
        6 + metrics.advanceWidth("Meeting spoken language") + 6 + small.advanceWidth(languageName) + 6 + 20 + 6,
        30 + metrics.advanceWidth("Position") + 6 + small.advanceWidth(positionName) + 6 + 20 + 6,
        6 + metrics.advanceWidth("Always turn on captions") + 10 + 40 + 10,
        30 + metrics.advanceWidth("Caption styles") + 6)) + 2 * padding
    background: FluentSurface { depth: 16; radius: 4 }
    FontMetrics { id: metrics; font.family: theme.font; font.pixelSize: theme.base }
    FontMetrics { id: small; font.family: theme.font; font.pixelSize: 12 }
    readonly property string positionName: position === "Top" ? "At top" : "At bottom"
    onClosed: { languageMenu.close(); positionMenu.close() }

    component Row32: Rectangle {
        id: r
        property string label
        property string icon: ""
        property string value: ""
        property bool chevron: false
        signal activated()
        signal hovered()
        width: parent.width; height: 32; radius: 4
        color: rh.hovered ? theme.menuHover : "transparent"
        FluentIcon { visible: r.icon.length > 0; x: 6; y: 6; size: 20; name: r.icon; color: rh.hovered ? theme.text : theme.textStrong }
        Text {
            x: r.icon.length > 0 ? 30 : 6; y: 6; height: 20
            verticalAlignment: Text.AlignVCenter
            text: r.label
            font.family: theme.font; font.pixelSize: theme.base
            color: rh.hovered ? theme.text : theme.textStrong
        }
        Text {
            visible: r.value.length > 0
            anchors.right: r.chevron ? chev.left : parent.right; anchors.rightMargin: 6
            y: 6; height: 20
            verticalAlignment: Text.AlignVCenter
            text: r.value
            font.family: theme.font; font.pixelSize: 12
            color: theme.textSecondary
        }
        FluentIcon { id: chev; visible: r.chevron; anchors.right: parent.right; anchors.rightMargin: 6; y: 6; size: 20; name: "chevron-right-20"; color: rh.hovered ? theme.text : theme.textStrong }
        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) r.hovered() }
        TapHandler { onTapped: r.activated() }
        Accessible.role: Accessible.MenuItem
        Accessible.name: r.value.length > 0 ? r.label + ", " + r.value : r.label
    }
    component SwitchRow32: Rectangle {
        id: s
        property string label
        property bool checked: false
        signal toggled()
        signal hovered()
        width: parent.width; height: 32; radius: 4
        color: sh.hovered ? theme.menuHover : "transparent"
        Text {
            x: 6; y: 6; height: 20
            verticalAlignment: Text.AlignVCenter
            text: s.label
            font.family: theme.font; font.pixelSize: theme.base
            color: sh.hovered ? theme.text : theme.textStrong
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 10; y: 6
            width: 40; height: 20; radius: 10
            color: s.checked ? (sh.hovered ? theme.brandHover : theme.brandFill) : "transparent"
            border.color: s.checked ? "transparent" : theme.textSecondary
            border.width: 0.67
            Rectangle {
                width: 14.4; height: 14.4; radius: 7.2
                anchors.verticalCenter: parent.verticalCenter
                x: (s.checked ? 20.67 : 0.67) + 9 - 7.2
                color: s.checked ? "white" : theme.textSecondary
            }
        }
        HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) s.hovered() }
        TapHandler { onTapped: s.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.name: s.label
        Accessible.checked: s.checked
    }
    component Divider: Item {
        width: parent.width; height: 8.67
        Rectangle { y: 4; x: -root.padding - 1; width: root.width + 2; height: 0.67; color: theme.divider }
    }

    contentItem: Column {
        spacing: 2
        Row32 {
            id: languageRow
            label: "Meeting spoken language"; value: root.languageName; chevron: true
            onHovered: { positionMenu.close(); root.openLanguages() }
            onActivated: root.openLanguages()
        }
        Divider {}
        Row32 {
            label: "Caption styles"; icon: "caption-styles-20"
            onHovered: { languageMenu.close(); positionMenu.close() }
            onActivated: { root.close(); root.captionStyles() }
        }
        Row32 {
            id: positionRow
            label: "Position"; icon: "caption-position-20"; value: root.positionName; chevron: true
            onHovered: { languageMenu.close(); root.openPositions() }
            onActivated: root.openPositions()
        }
        Divider {}
        SwitchRow32 {
            label: "Always turn on captions"; checked: root.alwaysOn
            onHovered: { languageMenu.close(); positionMenu.close() }
            onToggled: root.alwaysOnToggled(!root.alwaysOn)
        }
        SwitchRow32 {
            label: "Filter profane words"; checked: root.filterProfanity
            onHovered: { languageMenu.close(); positionMenu.close() }
            onToggled: root.filterProfanityToggled(!root.filterProfanity)
        }
    }

    // The pick-one lists open to the left, their surface overlapping ours by
    // 5 (as Teams' do), level with the row.
    function openLanguages() {
        const current = languages.find(l => l.code === language)
        languageMenu.items = (current ? [{ label: current.name, checked: true, code: current.code }] : [])
            .concat(languages.map(l => ({ label: l.name, checked: false, code: l.code })))
        languageMenu.x = -languageMenu.implicitWidth + 5 - root.padding
        languageMenu.y = languageRow.mapToItem(root.contentItem, 0, 0).y + 0.67
        languageMenu.open()
    }
    function openPositions() {
        positionMenu.items = [{ label: "At top", checked: position === "Top" }, { label: "At bottom", checked: position !== "Top" }]
        positionMenu.x = -positionMenu.implicitWidth + 5 - root.padding
        positionMenu.y = positionRow.mapToItem(root.contentItem, 0, 0).y
        positionMenu.open()
    }
    RadioMenu {
        id: languageMenu
        parent: root.contentItem
        dividerAfterFirst: true
        onPicked: i => { const code = items[i].code; root.close(); if (code !== root.language) root.languagePicked(code) }
    }
    RadioMenu {
        id: positionMenu
        parent: root.contentItem
        onPicked: i => { root.close(); root.positionPicked(i === 0 ? "Top" : "Bottom") }
    }
}
