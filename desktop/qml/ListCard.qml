import QtQuick
import QtQuick.Controls.Basic

// Teams' list card (application/vnd.microsoft.teams.card.list), measured on
// winpc 2026-11-12 ("OST TEST 115"): a white frame (0.67 #E0E0E0, radius
// 4), 452 wide; the title 16/22 semibold NeutralForeground2 at 16.7, 26.7;
// the items 4 further in, from 26.7 under the title:
// - a result item: its title 14/18.67 semibold, then 2 lower its subtitle
//   12/16 (both NeutralForeground2); its tap opens its link;
// - a section: 12/16 bold #616161;
// items are 19.7 apart; the buttons (as the hero card's) 26.7 under the
// last, 16.6 above the bottom.
// Items' icons aren't measured yet (the test list had none).
Rectangle {
    id: card
    property var content: ({})
    property real cardWidth: 452
    signal imBack(string text)
    readonly property var items: content && content.items ? content.items : []
    readonly property var buttons: content && content.buttons ? content.buttons.slice(0, 6) : []
    width: cardWidth
    height: buttonRow.visible ? buttonRow.y + buttonRow.height + 16.6 : col.y + col.height + 16.6
    radius: 4
    color: theme.surface
    border.color: theme.pick("#E0E0E0", "#3D3D3D"); border.width: 0.67

    function act(b) {
        if (!b) return
        const t = String(b.type || "").toLowerCase()
        if (t === "openurl" || t === "signin") Qt.openUrlExternally(b.value)
        else if (t === "imback") card.imBack(String(b.value || b.title || ""))
    }

    Text {
        id: title
        visible: !!card.content.title
        x: 16.7; y: 26.7; width: card.cardWidth - 33.4; wrapMode: Text.Wrap
        text: card.content.title || ""
        lineHeight: 22; lineHeightMode: Text.FixedHeight
        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong
    }
    Column {
        id: col
        x: 16.7 + 4; y: title.visible ? title.y + title.height + 26.7 : 26.7
        width: card.cardWidth - 33.4 - 8
        spacing: 19.7
        Repeater {
            model: card.items
            Column {
                id: item
                required property var modelData
                readonly property bool section: String(modelData.type || "") === "section"
                width: col.width
                spacing: 2
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: item.modelData.title || ""
                    lineHeight: item.section ? 16 : 18.67; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: item.section ? 12 : 14
                    font.weight: item.section ? Font.Bold : Font.DemiBold
                    color: item.section ? theme.pick("#616161", "#ADADAD") : theme.textStrong
                }
                Text {
                    visible: !item.section && !!item.modelData.subtitle
                    width: parent.width; wrapMode: Text.Wrap
                    text: item.modelData.subtitle || ""
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                }
                HoverHandler { enabled: !!item.modelData.tap; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !!item.modelData.tap; onTapped: card.act(item.modelData.tap) }
                Accessible.role: item.modelData.tap ? Accessible.Link : Accessible.StaticText
                Accessible.name: (item.modelData.title || "") + " " + (item.modelData.subtitle || "")
            }
        }
    }
    Flow {
        id: buttonRow
        visible: card.buttons.length > 0
        x: 16.7; y: col.y + col.height + 26.7
        width: card.cardWidth - 33.4
        spacing: 8
        Repeater {
            model: card.buttons
            Rectangle {
                id: btn
                required property var modelData
                width: Math.min(buttonRow.width, label.implicitWidth + 40); height: 32; radius: 4
                color: bh.hovered ? theme.menuHover : theme.surface
                border.color: theme.pick("#C5CBFA", "#4F52B2"); border.width: 0.67
                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, buttonRow.width - 40); elide: Text.ElideRight
                    text: btn.modelData.title || ""
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
                }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.act(btn.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.title || ""
            }
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: content.title || ""
}
