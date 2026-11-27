import QtQuick
import QtQuick.Controls.Basic

// Teams' device store cart (measured on winpc 2026-11-20; CSS px): a 720
// x 640 dialog, radius 8, Teams' dialog shadow.
// - "Your cart" (18/22 bold) at (32.7, 24.7), Close (32 x 31.3) at 667.3.
// - The item table (654.7 wide from 32.7): headers 12/16 #616161 at 79.3
//   (Item; Item Price at 340; Quantity at 432.7; Price right-aligned) over
//   a hairline at 112; each row 96.7 tall: the picture 92.5 x 56.1 (white,
//   radius 4) 20 down, the name 14/20 semibold at 145, the item price 14/20
//   semibold ending at 412.7, the quantity dropdown (83.5 x 31.3) at 452.7
//   and Delete (32 x 32, a 20 px bin) at 546.2, the line price 14/20 bold
//   at the right; a hairline under it.
// - "Subtotal" 14/20 at 425.6 and, right-aligned, "US" (14/20 bold) and the
//   amount (18/20 bold) 27 under the table; "Shipping and taxes will be
//   calculated at checkout." 12/16 #616161 30 under that.
// - The footer at 578.2: "Powered by UnifiedCommunications.com." 12/16,
//   then "Privacy" | "Terms of service" (12/16 brand links), and Checkout
//   (265 x 31.3, brand) at 422.3.
// - Empty: the picture, "Your cart is empty" (14/20) and Continue shopping
//   (brand) centred.
// The cart is kept on this device for the market, as Teams keeps it (its
// IndexedDB store cart); Checkout hands it to the fulfiller's store (the
// Client Store app Teams embeds, which reads it with TeamsJS'
// marketplace.getCart).
Popup {
    id: root
    /// The cart: {items: [{id, name, price, price_text, quantity, image}]}.
    property var cart: ({ items: [] })
    signal setQuantity(string id, int quantity)
    signal removeItem(string id)
    signal checkout()
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true
    width: 720; height: 640; padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
    readonly property var items: cart && cart.items ? cart.items : []
    readonly property real subtotal: items.reduce((s, i) => s + i.price * i.quantity, 0)
    function money(v) {
        const c = Math.round(v * 100), w = Math.floor(c / 100), f = c % 100
        return "$" + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + "." + (f < 10 ? "0" : "") + f
    }

    Text { x: 32.7; y: 24.7; width: 620; height: 22; verticalAlignment: Text.AlignVCenter; text: qsTr("Your cart"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
    Rectangle {
        id: closeBtn
        x: 667.3; y: 20.7; width: 32; height: 31.3; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }
    Rectangle { visible: root.items.length > 0; x: 0; y: 63; width: parent.width; height: 0.67; color: theme.divider }

    // The table.
    Item {
        visible: root.items.length > 0
        x: 32.7; y: 63.3; width: 654.7; height: 48.7 + root.items.length * 96.7
        Text { y: 16; text: qsTr("Item"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Text { x: 307.3; y: 16; width: 72.7; horizontalAlignment: Text.AlignRight; text: qsTr("Item Price"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Text { x: 400; y: 16; text: qsTr("Quantity"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Text { anchors.right: parent.right; y: 16; text: qsTr("Price"); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Rectangle { y: 48; width: parent.width; height: 0.67; color: theme.divider }
        Column {
            y: 48.7; width: parent.width
            Repeater {
                model: root.items
                Item {
                    id: row
                    required property var modelData
                    width: parent.width; height: 96.7
                    Rectangle {
                        y: 20; width: 92.5; height: 56.1; radius: 4; color: "#FFFFFF"
                        Image { anchors.fill: parent; source: row.modelData.image || ""; fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true; sourceSize: Qt.size(185, 112) }
                        Accessible.role: Accessible.Graphic; Accessible.name: (row.modelData.name || "") + "-image"
                    }
                    Text { x: 112.4; width: 190; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: row.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Text { x: 307.3; width: 72.7; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: root.money(row.modelData.price); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    QuantityBox { x: 420; width: 83.5; anchors.verticalCenter: parent.verticalCenter; value: row.modelData.quantity; onPicked: v => root.setQuantity(row.modelData.id, v) }
                    Rectangle {
                        id: delBtn
                        x: 513.5; width: 32; height: 32; radius: 4; anchors.verticalCenter: parent.verticalCenter
                        color: delHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "delete-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.removeItem(row.modelData.id) }
                        Accessible.role: Accessible.Button; Accessible.name: qsTr("delete button")
                    }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.money(row.modelData.price * row.modelData.quantity); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                }
            }
        }
        // Subtotal.
        Item {
            y: parent.height + 27; width: parent.width; height: 50
            Text { x: 392.9; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Subtotal"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Row {
                anchors.right: parent.right; spacing: 4
                Text { height: 20; verticalAlignment: Text.AlignBottom; text: "US"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                Text { height: 20; verticalAlignment: Text.AlignVCenter; text: root.money(root.subtotal); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            }
            Text { x: 392.9; y: 30; width: 261.8; horizontalAlignment: Text.AlignRight; text: qsTr("Shipping and taxes will be calculated at checkout."); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
    }
    // Empty.
    Column {
        visible: root.items.length === 0
        anchors.horizontalCenter: parent.horizontalCenter; y: 213.8; spacing: 0
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "cart-20"; size: 96; color: theme.textSecondary; Accessible.role: Accessible.Graphic; Accessible.name: qsTr("an image indicate the cart is empty") }
        Item { width: 1; height: 37 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Your cart is empty"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
        Item { width: 1; height: 24 }
        StoreButton { anchors.horizontalCenter: parent.horizontalCenter; label: qsTr("Continue shopping"); primary: true; onClicked: root.close() }
    }
    // Footer.
    Item {
        visible: root.items.length > 0
        x: 32.7; y: 578.2; width: 654.7; height: 31.3
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 4
            Text { text: qsTr("Powered by %1.").arg("UnifiedCommunications.com"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Text {
                text: qsTr("Privacy"); font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.openExternal("https://unifiedcommunications.com/docs/teams-marketplace/en-us/privacy-policy") }
                Accessible.role: Accessible.Link; Accessible.name: text
            }
            Text { text: "|"; font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1 }
            Text {
                text: qsTr("Terms of service"); font.family: theme.font; font.pixelSize: 12; color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.openExternal("https://unifiedcommunications.com/docs/teams-marketplace/en-us/terms-of-service") }
                Accessible.role: Accessible.Link; Accessible.name: text
            }
        }
        StoreButton { x: 389.6; width: 265; label: qsTr("Checkout"); primary: true; onClicked: root.checkout() }
    }
}
