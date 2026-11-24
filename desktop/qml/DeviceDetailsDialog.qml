import QtQuick
import QtQuick.Controls.Basic

// A device's details in Teams' device store (measured on winpc
// 2026-11-20, ADAPT 165T USB C II; CSS px): a 720 x 640 dialog, radius 8,
// Teams' dialog shadow.
// - Close (32 x 31.3, a 16 px dismiss) at (667.3, 20.7).
// - The picture (the catalog's large image) 324.3 x 186.4 at (32.7, 48.7);
//   a hairline divides it from the facts at the right (407.3, 258 wide):
//   the name 18/24 bold, the maker 14/20 #616161 at 76.7, the price 18/24
//   bold at 112.7, "Free shipping in most of the US" (a 24 px #E8EBFA
//   circle with a 16 px van, 12/16 semibold, an info button "See details")
//   at 156.7, "Quantity" 12/16 #424242 at 200.7 over the quantity dropdown
//   (112 x 31.3, #F5F5F5, radius 4) and Share ▾ (40 x 32; Copy Link) at
//   220.7, then Add to cart (112 x 31.3, brand) at 264.7. Once in the cart,
//   View Cart (brand) and Add to cart (outline) side by side.
// - The tabs Overview, Highlights and Tech Specs (14/20, 44 tall, a brand
//   underline) at 368.7 scroll to their sections: Overview (18/20 bold),
//   the short description (14/20 bold) and the full description (14/20);
//   Highlights, each a 14/20 bold heading over its text; Tech Specs, a
//   table of key (14/20 semibold) and value rows on #FAFAFA with hairline
//   rules.
// - A footer 72 tall with a top hairline: "Powered by" and the fulfiller,
//   "UnifiedCommunications.com" (14/16).
Popup {
    id: root
    property var device: null   // the page's Device (id, name, …)
    property var info: null     // DeviceDetails, once loaded
    property string error: ""
    property int quantity: 1
    /// What the cart holds (DeviceCart's items), to offer View Cart.
    property var cartIds: []
    signal addToCart(var device, int quantity)
    signal viewCart()
    signal copyLink(var device)
    readonly property string call: "devdetail:" + Math.floor(Math.random() * 1e9).toString(36)
    readonly property bool inCart: !!device && cartIds.indexOf(String(device.id)) >= 0
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true
    width: 720; height: 640; padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }

    function show(d) {
        device = d; info = null; error = ""; quantity = 1
        open()
        backend.storeRequest("device", call, JSON.stringify({ id: String(d.id) }))
    }
    Connections {
        target: backend
        function onStoreReply(id, json) {
            if (id !== root.call) return
            const r = JSON.parse(json)
            if (r.error) root.error = r.error
            else root.info = r
        }
    }
    readonly property var d: info ? info.device : device

    Flickable {
        id: flick
        x: 0; y: 0; width: parent.width; height: parent.height - 72
        contentHeight: body.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Item {
            id: body
            width: flick.width
            height: sections.y + sections.height
            Image {
                x: 32.7; y: 48.7; width: 324.3; height: 186.4
                source: root.info && root.info.images.length ? root.info.images[0] : (root.d ? root.d.image : "")
                fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                sourceSize: Qt.size(648, 373)
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("%1 image of %2").arg(0).arg(root.d ? root.d.name : "")
            }
            Rectangle { x: 374; y: 48.7; width: 0.67; height: 288; color: theme.divider }
            Column {
                x: 407.3; y: 48.7; width: 258
                Text { width: parent.width; wrapMode: Text.Wrap; lineHeight: 24; lineHeightMode: Text.FixedHeight; text: root.d ? root.d.name : ""; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                Item { width: 1; height: 4 }
                Text { height: 20; verticalAlignment: Text.AlignVCenter; text: root.d ? root.d.maker : ""; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                Item { width: 1; height: 16 }
                Text { height: 24; verticalAlignment: Text.AlignVCenter; text: root.d ? root.d.price_text : ""; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
                Item { width: 1; height: 20 }
                Row {
                    height: 24; spacing: 8
                    Rectangle {
                        width: 24; height: 24; radius: 12; color: theme.pick("#E8EBFA", "#2B2B40", "#000000")
                        FluentIcon { anchors.centerIn: parent; name: "vehicle-truck-profile-16"; size: 16; color: theme.brandForeground1 }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Free shipping in most of the US"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                    Item {
                        width: 21.3; height: 24
                        FluentIcon { anchors.centerIn: parent; name: "info-16"; size: 16; color: theme.textStrong }
                        HoverHandler { id: shipHover }
                        ToolTip.visible: shipHover.hovered; ToolTip.delay: 300
                        ToolTip.text: qsTr("Free shipping is confirmed in checkout. Usually ships in 2-3 days. Expedited shipping available.")
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("See details")
                    }
                }
                Item { width: 1; height: 20 }
                Text { height: 16; verticalAlignment: Text.AlignVCenter; text: qsTr("Quantity"); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                Item { width: 1; height: 4.6 }
                Row {
                    spacing: 12
                    QuantityBox { value: root.quantity; onPicked: v => root.quantity = v }
                    Rectangle {
                        id: shareBtn
                        width: 40; height: 32; radius: 4
                        color: shareHover.hovered ? theme.menuHover : "transparent"
                        Row { anchors.centerIn: parent; spacing: 2; FluentIcon { name: "share-20"; size: 20; color: theme.textStrong } FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.textStrong } }
                        HoverHandler { id: shareHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { shareMenu.parent = shareBtn; shareMenu.y = shareBtn.height + 4; shareMenu.open() } }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("Share")
                        MenuPopup {
                            id: shareMenu
                            items: [{ label: qsTr("Copy Link"), icon: "link-20" }]
                            onPicked: root.copyLink(root.d)
                        }
                    }
                }
                Item { width: 1; height: 12 }
                Row {
                    spacing: 12
                    StoreButton { visible: root.inCart; label: qsTr("View Cart"); primary: true; width: 112; onClicked: root.viewCart() }
                    StoreButton { label: qsTr("Add to cart"); primary: !root.inCart; width: 112; enabled: !!root.d; onClicked: root.addToCart(root.d, root.quantity) }
                }
            }
            Text {
                visible: !!root.error
                x: 407.3; y: 310; width: 258; wrapMode: Text.Wrap
                text: qsTr("Looks like we can't show you this link.")
                font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3
            }
            // The section tabs.
            Row {
                id: tabsRow
                x: 34.7; y: 368.7
                Repeater {
                    model: [{ k: "overview", l: qsTr("Overview") }, { k: "highlights", l: qsTr("Highlights") }, { k: "specs", l: qsTr("Tech Specs") }]
                    Item {
                        id: tabBtn
                        required property var modelData
                        readonly property bool on: root.section === modelData.k
                        width: tabText.implicitWidth + 20; height: 44
                        Text { id: tabText; anchors.centerIn: parent; text: tabBtn.modelData.l; font.family: theme.font; font.pixelSize: 14; font.weight: tabBtn.on ? Font.DemiBold : Font.Normal; color: tabBtn.on ? theme.text : theme.textStrong }
                        Rectangle { visible: tabBtn.on; anchors.bottom: parent.bottom; x: 10; width: parent.width - 20; height: 3; radius: 1.5; color: theme.brand }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.scrollTo(tabBtn.modelData.k) }
                        Accessible.role: Accessible.PageTab; Accessible.name: tabBtn.modelData.l; Accessible.selected: tabBtn.on
                    }
                }
            }
            Rectangle { x: 32.7; y: 412.7; width: 654.7; height: 0.67; color: theme.divider }
            Column {
                id: sections
                x: 44.7; y: 437.3; width: 636.7
                spacing: 0
                Item {
                    id: overviewSec
                    width: parent.width; height: ovCol.height + 30
                    Column {
                        id: ovCol
                        width: parent.width; spacing: 28
                        Text { text: qsTr("Overview"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                        Text { visible: !!root.d && !!root.d.short; width: parent.width; wrapMode: Text.Wrap; text: root.d ? root.d.short : ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: root.info ? root.info.full_description : ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                }
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                Item {
                    id: highlightsSec
                    width: parent.width; height: hiCol.height + 60
                    Column {
                        id: hiCol
                        y: 30; width: parent.width; spacing: 24
                        Text { text: qsTr("Highlights"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                        Repeater {
                            model: root.info ? root.info.highlights : []
                            Column {
                                required property var modelData
                                width: hiCol.width; spacing: 8
                                Text { width: parent.width; wrapMode: Text.Wrap; text: parent.modelData.key; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                Text { width: parent.width; wrapMode: Text.Wrap; text: parent.modelData.value; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                Item {
                    id: specsSec
                    width: parent.width; height: spCol.height + 30
                    Column {
                        id: spCol
                        y: 30; width: parent.width; spacing: 30
                        Text { text: qsTr("Tech Specs"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
                        Column {
                            width: parent.width
                            Repeater {
                                model: root.info ? root.info.tech_specs : []
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: spCol.width; height: Math.max(keyText.height, valText.height) + 24
                                    color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                                    Text { id: keyText; x: 16; width: 130; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.Wrap; text: parent.modelData.key; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                    Text { id: valText; x: 162; width: parent.width - 162; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.Wrap; text: parent.modelData.value; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    /// The section in view (Teams marks the tab of what's shown).
    readonly property string section: {
        const y = flick.contentY + 120
        if (y >= sections.y + specsSec.y) return "specs"
        if (y >= sections.y + highlightsSec.y) return "highlights"
        return "overview"
    }
    function scrollTo(k) {
        const item = k === "specs" ? specsSec : k === "highlights" ? highlightsSec : overviewSec
        flick.contentY = Math.min(sections.y + item.y - 60, Math.max(0, flick.contentHeight - flick.height))
    }

    // Scrolled past the facts, Teams pins a compact header (measured): the
    // thumbnail (46.7, a hairline box) at (45.3, 25.3), "<thumbnail alt>"
    // (14/20 bold) and the price (12/16) at 112.7, the quantity box at
    // 405.3 and Add to cart at 537.3 (24.7 down), and the section tabs at
    // 84.7 over a hairline.
    Rectangle {
        visible: flick.contentY > tabsRow.y - 84
        width: parent.width; height: 129; radius: 8; color: theme.surface; z: 2
        Rectangle {
            x: 32.7; y: 18; width: 60; height: 60; radius: 4; color: "#FFFFFF"; border.width: 0.67; border.color: theme.divider
            Image { anchors.centerIn: parent; width: 46.7; height: 46.7; source: root.d ? root.d.image : ""; fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true; sourceSize: Qt.size(94, 94) }
        }
        Text { x: 112.7; y: 24.7; width: 280; height: 20; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; text: root.d ? (root.d.image_alt || root.d.maker + " - " + root.d.name) : ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
        Text { x: 112.7; y: 44.7; height: 16; verticalAlignment: Text.AlignVCenter; text: root.d ? root.d.price_text : ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        QuantityBox { x: 405.3; y: 24.7; value: root.quantity; onPicked: v => root.quantity = v }
        StoreButton { x: 537.3; y: 24.7; width: 112; label: qsTr("Add to cart"); primary: true; enabled: !!root.d; onClicked: root.addToCart(root.d, root.quantity) }
        Row {
            x: 34.7; y: 84.7 - 12
            Repeater {
                model: [{ k: "overview", l: qsTr("Overview") }, { k: "highlights", l: qsTr("Highlights") }, { k: "specs", l: qsTr("Tech Specs") }]
                Item {
                    id: tab2
                    required property var modelData
                    readonly property bool on: root.section === modelData.k
                    width: t2.implicitWidth + 20; height: 44
                    Text { id: t2; anchors.centerIn: parent; text: tab2.modelData.l; font.family: theme.font; font.pixelSize: 14; font.weight: tab2.on ? Font.DemiBold : Font.Normal; color: tab2.on ? theme.text : theme.textStrong }
                    Rectangle { visible: tab2.on; anchors.bottom: parent.bottom; x: 10; width: parent.width - 20; height: 3; radius: 1.5; color: theme.brand }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.scrollTo(tab2.modelData.k) }
                    Accessible.role: Accessible.PageTab; Accessible.name: tab2.modelData.l; Accessible.selected: tab2.on
                }
            }
        }
        Rectangle { x: 32.7; y: 128.3; width: 654.7; height: 0.67; color: theme.divider }
    }

    // Close.
    Rectangle {
        id: closeBtn
        x: 667.3; y: 20.7; width: 32; height: 31.3; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }
    // Footer.
    Rectangle {
        x: 0.7; y: parent.height - 72; width: parent.width - 1.4; height: 72; color: theme.surface; radius: 8
        Rectangle { width: parent.width; height: 0.67; color: theme.divider }
        Row {
            x: 30; anchors.verticalCenter: parent.verticalCenter; spacing: 5
            Text { text: qsTr("Powered by"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { text: "UnifiedCommunications.com"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        }
    }
    function stateForTest() { return JSON.stringify({ name: root.d ? root.d.name : "", price: root.d ? root.d.price_text : "", loaded: !!root.info, highlights: root.info ? root.info.highlights.length : 0, specs: root.info ? root.info.tech_specs.length : 0, error: root.error, inCart: root.inCart }) }
}
