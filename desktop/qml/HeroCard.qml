import QtQuick
import QtQuick.Controls.Basic

// Teams' hero and thumbnail cards (944311 `me` / `he`), measured from a
// hero card in the desktop client:
// - the frame: white, a 0.67 px NeutralStroke2 border, radius 4; content
//   16.7 in, the title 26.7 down; 452 wide in a chat at least 720 wide;
// - title 16/22 semibold, subtitle 14/20 semibold (both NeutralForeground2),
//   each 8 apart; the hero image 16:9, cropped to fill; the text 14/20
//   NeutralForeground1; the buttons 4 under it;
// - buttons (at most 6): 32 tall, padding 0 20, a 0.67 px BrandStroke2
//   (#C5CBFA) border, radius 4, white, 14/20 semibold brand text, 8 apart.
// A thumbnail card puts a 100 x 100 image left of the title, subtitle and
// text (12 px, line height 1.25), stacking it above below 360 wide.
Rectangle {
    id: card
    property var content: ({})
    property bool thumbnail: false
    property real cardWidth: 452
    signal imBack(string text)
    readonly property var image: content && content.images && content.images.length ? content.images[0] : null
    readonly property var buttons: content && content.buttons ? content.buttons.slice(0, 6) : []
    readonly property bool stacked: thumbnail && cardWidth < 360
    width: cardWidth
    height: col.y + col.height + (buttonRow.visible ? 4 + buttonRow.height : 0) + 16.6
    radius: 4
    color: theme.surface
    border.color: theme.divider; border.width: 0.67

    function act(b) {
        const t = String(b.type || "").toLowerCase()
        if (t === "openurl" || t === "signin") Qt.openUrlExternally(b.value)
        else if (t === "imback") card.imBack(String(b.value || b.title || ""))
    }

    Row {
        id: col
        x: 16.7; y: 26.7
        spacing: 12
        // Thumbnail: the picture beside the text.
        Image {
            visible: card.thumbnail && !card.stacked && !!card.image
            width: 100; height: 100
            source: { backend.emoticonsVersion; return card.image ? backend.cardImage(card.image.url) : "" }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Column {
            id: textCol
            width: card.cardWidth - 33.4 - (card.thumbnail && !card.stacked && card.image ? 112 : 0)
            spacing: 8
            Image {
                visible: card.thumbnail && card.stacked && !!card.image
                width: 100; height: 100
                source: { backend.emoticonsVersion; return card.image ? backend.cardImage(card.image.url) : "" }
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Text {
                visible: !!card.content.title
                width: parent.width; wrapMode: Text.Wrap
                text: card.content.title || ""
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong
            }
            Text {
                visible: !!card.content.subtitle
                width: parent.width; wrapMode: Text.Wrap
                text: card.content.subtitle || ""
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
            }
            Image {
                visible: !card.thumbnail && !!card.image
                width: parent.width; height: width * 0.5625
                source: { backend.emoticonsVersion; return card.image ? backend.cardImage(card.image.url) : "" }
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
                TapHandler { enabled: !!(card.image && card.image.tap); onTapped: card.act(card.image.tap) }
                Accessible.role: Accessible.Graphic
                Accessible.name: card.image ? (card.image.alt || "") : ""
            }
            Text {
                visible: !!card.content.text
                width: parent.width; wrapMode: Text.Wrap
                text: card.content.text || ""
                lineHeight: card.thumbnail ? 15 : 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: card.thumbnail ? 12 : 14; color: theme.text
            }
        }
    }
    Flow {
        id: buttonRow
        visible: card.buttons.length > 0
        x: 16.7; y: col.y + col.height + 4 + 4
        width: card.cardWidth - 33.4
        spacing: 8
        Repeater {
            model: card.buttons
            Rectangle {
                id: btn
                required property var modelData
                width: Math.min(buttonRow.width, label.implicitWidth + 40); height: 32; radius: 4
                color: btnHover.hovered ? theme.menuHover : theme.surface
                border.color: theme.pick("#C5CBFA", "#4F52B2"); border.width: 0.67
                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, buttonRow.width - 40); elide: Text.ElideRight
                    text: btn.modelData.title || ""
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
                }
                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.act(btn.modelData) }
                ToolTip {
                    visible: btnHover.hovered; delay: 500
                    y: -height - 4; padding: 8
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text {
                        text: (btn.modelData.title || "") + (String(btn.modelData.type || "").toLowerCase() === "openurl" ? "\nThis is a card action with a link" : "")
                        font.family: theme.font; font.pixelSize: theme.small; color: theme.text
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.title || ""
            }
        }
    }
    TapHandler { enabled: !!(card.content && card.content.tap); onTapped: card.act(card.content.tap) }
    Accessible.role: Accessible.Grouping
    Accessible.name: (content.title || "") + " " + (content.subtitle || "")
}
