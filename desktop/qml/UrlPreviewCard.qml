import QtQuick
import QtQuick.Effects

// Teams' link preview card (url-preview, measured on winpc 2026-11-15 in
// compose and in a sent message): 460 x 96, radius 6 with Fluent's shadow 2.
// - The picture (120 x 96, cropped to fill) on NeutralBackground4. With no
//   picture, or one not behind Teams' URL proxy, Teams' grey placeholder
//   with the link glyph.
// - The body (340, NeutralBackground2, padding 8 / 12):
//   - the title (14/600, one line) with Remove URL Preview (Dismiss, 20)
//     at its end for the sender;
//   - the description (12/16, two lines);
//   - the link's host name (12/16, NeutralForeground3) at the bottom.
// In a message the whole card opens the link.
Item {
    id: card
    /// {url, title, description, thumbnail, enabled}
    property var preview: null
    /// Shows Remove URL Preview (compose, and your own messages).
    property bool removable: false
    /// The card opens its link when clicked (messages).
    property bool clickable: false
    signal removeRequested()
    width: 460; height: 96

    readonly property string title: preview ? String(preview.title || "").trim() : ""
    readonly property string description: preview ? String(preview.description || "") : ""
    readonly property string url: preview ? String(preview.url || "") : ""
    readonly property string host: { const m = url.match(/^[a-z]+:\/\/([^\/?#:]+)/i); return m ? m[1] : "" }
    // Teams shows only pictures from its URL proxy and media hosts.
    readonly property string thumbnail: {
        const t = preview ? String(preview.thumbnail || "") : ""
        return /^https:\/\/([^\/]*\.)?(asm\.skype\.com|asyncgw\.teams\.microsoft\.com|urlp\.sfbassets\.com)\//i.test(t) ? t : ""
    }

    RectangularShadow { anchors.fill: surface; radius: 6; blur: 2; color: Qt.rgba(0, 0, 0, 0.12) }
    RectangularShadow { anchors.fill: surface; radius: 6; offset.y: 1; blur: 2; color: Qt.rgba(0, 0, 0, 0.14) }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 6
        color: theme.pick("#F0F0F0", "#0A0A0A", "#000000")
        clip: true
        Item {
            width: 120; height: 96
            // Teams' placeholder: #ccc with the link glyph in #525252.
            Rectangle {
                anchors.fill: parent
                visible: picture.status !== Image.Ready
                color: theme.hc("#CCCCCC", "#000000")
                FluentIcon { anchors.centerIn: parent; name: "link-20"; size: 48; color: theme.hc("#525252", "#FFFFFF") }
            }
            Image {
                id: picture
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: { backend.emoticonsVersion; return card.thumbnail ? backend.cardImage(card.thumbnail) : "" }
                Accessible.role: Accessible.Graphic
                Accessible.name: "Url Preview for " + card.title
            }
        }
        Rectangle {
            x: 120; width: 340; height: 96
            color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
            Text {
                visible: !!card.title
                x: 12; y: 8; width: card.removable ? 284 : 316; height: 20
                verticalAlignment: Text.AlignVCenter
                text: card.title
                elide: Text.ElideRight; maximumLineCount: 1
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: theme.text
            }
            Item {
                visible: card.removable && !!card.title
                x: 308; y: 8; width: 20; height: 20
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.pick("#424242", "#D6D6D6", "#FFFFFF") }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.removeRequested() }
                Accessible.role: Accessible.Button
                Accessible.name: "Remove URL Preview"
            }
            Text {
                visible: !!card.description
                x: 12; y: card.title ? 28 : 8; width: 316
                text: card.description
                wrapMode: Text.Wrap; elide: Text.ElideRight; maximumLineCount: 2
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                x: 12; y: 96 - 8 - 16; width: 316; height: 16
                text: card.host
                elide: Text.ElideRight
                font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
                color: theme.textSecondary
            }
        }
    }
    HoverHandler { enabled: card.clickable; cursorShape: Qt.PointingHandCursor }
    // (Remove URL Preview's corner doesn't open the link.)
    TapHandler {
        enabled: card.clickable
        onTapped: ev => { if (!(card.removable && ev.position.x >= 120 + 300 && ev.position.y <= 32)) Qt.openUrlExternally(card.url) }
    }
    Accessible.role: card.clickable ? Accessible.Link : Accessible.Grouping
    Accessible.name: card.title || card.url
}
