import QtQuick

// Teams' app link card (app link unfurling, TASK-0168; measured on winpc
// 2026-11-16 with Wikipedia Search, OST TEST 168a): a link to a site with a
// Teams app shows that app's card instead of the plain preview.
// - The frame: 452 wide, white, a 0.67 px NeutralStroke2 border, radius 4,
//   16.67 padding.
// - The header (24 tall): the app's icon (24, round, on #FAFAFA) and its
//   name (12/600 on a 16 line, NeutralForeground1) 12 to the right. In
//   compose, Collapse preview (20, ArrowMinimize) and Remove URL Preview
//   (20, Dismiss) sit at its end, 10 apart.
// - 12 under it, the app's card (a thumbnail card here: the 100 x 100
//   picture 8 down, the title as a 16 px brand link on a 22 line, the text
//   8 under it, 12 px NeutralForeground2 on a 15 line).
// - In compose, for an app used without installing it, the footer: 10
//   down, a 0.67 px line, 10 more, "By using {app}, you agree to the
//   privacy policy, terms of use, and permissions." (12 on a 17.14 line,
//   the links brand) and a settings button (32 x 31.33) that opens
//   Settings ▸ Privacy.
// The sent message's card has no footer and no buttons.
Rectangle {
    id: card
    /// link_unfurl::AppCard {app_name, app_icon, content_type, content,
    /// anonymous, privacy_url, terms_url} (or a message Card with
    /// app_name/app_icon).
    property var appCard: null
    /// Compose: the header's buttons and the footer.
    property bool compose: false
    signal collapseRequested()
    signal removeRequested()
    signal settingsRequested()
    signal permissionsRequested()
    signal openLink(string url)
    /// Teams' permission card (707715): Show Preview installs the app, Sign
    /// in opens the app's sign-in window, Setup its setup page.
    signal showPreviewRequested()
    signal signInRequested(string url)
    readonly property string permission: appCard && appCard.permission ? appCard.permission : ""
    readonly property bool hasFooter: compose && !!appCard && appCard.anonymous === true && permission !== "auth" && permission !== "config"
    width: 452
    height: col.y + col.height + 16.67
    radius: 4
    color: theme.surface
    border.width: 0.67; border.color: theme.divider

    Column {
        id: col
        x: 16.67; y: 16.67
        width: card.width - 33.33
        Item {
            width: parent.width; height: 24
            Rectangle {
                width: 24; height: 24; radius: 12
                color: theme.pick("#FAFAFA", "#292929", "#000000")
                clip: true
                Image {
                    anchors.fill: parent
                    source: { backend.emoticonsVersion; return card.appCard && card.appCard.app_icon ? backend.cardImage(card.appCard.app_icon) : "" }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
            }
            Text {
                x: 36; y: 4; height: 16
                width: parent.width - 36 - (card.compose ? 60 : 0)
                text: card.appCard ? (card.appCard.app_name || "") : ""
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: theme.text
            }
            Item {
                visible: card.compose
                x: parent.width - 50; y: 2; width: 20; height: 20
                FluentIcon { anchors.centerIn: parent; name: "arrow-minimize-20"; size: 20; color: theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.collapseRequested() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Collapse preview")
            }
            Item {
                visible: card.compose
                x: parent.width - 20; y: 0.67; width: 20; height: 20
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.removeRequested() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Remove URL Preview")
            }
        }
        Item { width: 1; height: 12 }
        // The app's hero or thumbnail card, as Teams lays it out in a link
        // card: the picture first (a thumbnail's 100 x 100, 8 down; a hero's
        // 16:9 across), then the title and text.
        Column {
            id: body
            visible: !adaptive.visible && !connector.visible && !!card.appCard && !!card.appCard.content_type
            width: parent.width
            readonly property var content: card.appCard ? (card.appCard.content || ({})) : ({})
            readonly property bool thumb: !!card.appCard && card.appCard.content_type === "application/vnd.microsoft.card.thumbnail"
            readonly property var image: content.images && content.images.length ? content.images[0] : null
            Item {
                visible: !!body.image
                width: parent.width; height: body.thumb ? 108 : width * 0.5625 + 8
                Image {
                    y: 8
                    width: body.thumb ? 100 : parent.width; height: body.thumb ? 100 : parent.width * 0.5625
                    source: { backend.emoticonsVersion; return body.image ? backend.cardImage(body.image.url) : "" }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    clip: true
                    Accessible.role: Accessible.Graphic
                    Accessible.name: body.image ? (body.image.alt || "") : ""
                }
            }
            Text {
                visible: !!body.content.title
                width: parent.width; wrapMode: Text.Wrap
                // Teams' links aren't underlined.
                textFormat: Text.RichText
                text: "<style>a { text-decoration: none; color: " + theme.brandForeground1 + "; }</style>" + (body.content.title || "")
                lineHeight: 22; lineHeightMode: Text.FixedHeight
                // A linked title is a 16 px brand link (Teams: 400 inside the
                // semibold title).
                font.family: theme.font; font.pixelSize: 16
                font.weight: /<a\s/i.test(body.content.title || "") ? Font.Normal : Font.DemiBold
                color: theme.textStrong
                onLinkActivated: link => card.openLink(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            Text {
                visible: !!body.content.subtitle
                width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: body.content.subtitle || ""
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong
            }
            Item { visible: !!body.content.text; width: 1; height: 8 }
            Text {
                visible: !!body.content.text
                width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: theme.brandForeground1
                text: body.content.text || ""
                lineHeight: 15; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                onLinkActivated: link => card.openLink(link)
            }
        }
        // The permission card's link (pre-auth cards: the app's card above
        // it, when it gave one): Install "Show Preview", Auth a 16 px icon
        // and "Sign in to view card content", Config "Setup".
        Row {
            visible: card.permission !== ""
            spacing: 4
            FluentIcon { visible: card.permission === "auth"; anchors.verticalCenter: parent.verticalCenter; name: "person-16"; size: 16; color: theme.brandForeground1 }
            Text {
                text: card.permission === "install" ? qsTr("Show Preview") : card.permission === "auth" ? qsTr("Sign in to view card content") : qsTr("Setup")
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.permission === "install" ? card.showPreviewRequested() : card.signInRequested(card.appCard.auth_url || "") }
                Accessible.role: Accessible.Link
                Accessible.name: text
            }
        }
        // An Office 365 connector card (Azure Boards' work items; measured
        // on winpc 2026-11-22, "OST TEST 200 item 2"): its sections under
        // the header as ConnectorCard draws them (the 52 px activity image,
        // the activity's lines 62 in), the frame ending 26.6 under them; its
        // themeColor is the card's 3 px top bar.
        ConnectorCard {
            id: connector
            readonly property bool isConnector: !!card.appCard && card.appCard.content_type === "application/vnd.microsoft.teams.card.o365connector"
            visible: isConnector && card.permission === ""
            embedded: true
            content: isConnector ? (card.appCard.content || ({})) : ({})
            cardWidth: col.width
        }
        Item { visible: connector.visible; width: 1; height: 10 }
        AdaptiveCard {
            id: adaptive
            visible: !!card.appCard && card.appCard.content_type === "application/vnd.microsoft.card.adaptive"
            content: visible ? card.appCard.content : ({})
            cardWidth: col.width
            hostsLinks: true
            onOpenLink: link => card.openLink(link)
        }
        Item {
            visible: card.hasFooter
            width: parent.width; height: visible ? footerText.height + 20.67 : 0
            Rectangle { y: 10; width: parent.width; height: 0.67; color: theme.pick("#FAFAFA", "#292929", "#FFFFFF") }
            Text {
                id: footerText
                y: 20.67; width: parent.width - 32
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                lineHeight: 17.14; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 12
                color: theme.textStrong
                text: card.appCard ? "<style>a { text-decoration: none; color: " + theme.brandForeground1 + "; }</style>" + qsTr("By using %1, you agree to the <1>%2</1>, <2>%3</2>, and <3>%4</3>.").arg(card.appCard.app_name || "").arg(qsTr("privacy policy")).arg(qsTr("terms of use")).arg(qsTr("permissions")).replace("<1>", "<a href=\"privacy\">").replace("<2>", "<a href=\"terms\">").replace("<3>", "<a href=\"permissions\">").replace(/<\/[123]>/g, "</a>") : ""
                onLinkActivated: link => {
                    if (link === "privacy" && card.appCard.privacy_url) Qt.openUrlExternally(card.appCard.privacy_url)
                    else if (link === "terms" && card.appCard.terms_url) Qt.openUrlExternally(card.appCard.terms_url)
                    else if (link === "permissions") card.permissionsRequested()
                }
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            Rectangle {
                id: gear
                x: parent.width - 32; y: 12.2; width: 32; height: 31.33; radius: 4
                color: gearHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "settings-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.settingsRequested() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Settings")
            }
        }
    }
    Rectangle {
        readonly property string tint: connector.visible ? String(connector.content.themeColor || "").replace(/^#/, "") : ""
        visible: /^[0-9a-fA-F]{6}$/.test(tint)
        width: card.width; height: 3
        topLeftRadius: 4; topRightRadius: 4
        color: visible ? "#" + tint : "transparent"
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: card.appCard ? (card.appCard.app_name || "") : ""
}
