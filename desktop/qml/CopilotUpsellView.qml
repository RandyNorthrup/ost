import QtQuick

// Teams for personal use's Copilot app without a Microsoft 365 plan: its
// upsell page (measured on teams.live.com and Teams desktop 26304,
// 2026-11-28, OST Personal 1 and 2): a 600 wide column centred in the
// view; "Chat with [Copilot] Copilot in Teams" (28/36 semibold, the 32 px
// colour Copilot mark between); a 600 x 343 carousel (radius 12) of
// Teams' three pictures, turning on its own, with Pause, Previous, the
// three dots (the shown one a 16 x 8 pill) and Next under it, 12 down;
// "Collaborate with an AI companion …" (16/22, 47 under); the apps of the
// plan (20 px, 28 apart) and "View all benefits →" (14, brand); "Explore
// plans now" (179 x 40, 16/22 semibold, brand); "Already have a
// subscription? Start using Copilot" (the link bold).
// View all benefits opens Microsoft's plans page in the browser, as Teams
// does; Explore plans now opens it too (where Teams opens its purchase
// dialog: OST never buys in the app); Start using Copilot checks the
// subscription again (Teams' Copilot eligibility refresh).
Rectangle {
    id: root
    color: theme.surface
    signal explorePlans()
    signal viewBenefits()
    signal refreshRequested()
    readonly property string cdn: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/"
    readonly property var pictures: [1, 2, 3].map(i => cdn + "m365-subscription-upsell/upsell-" + i + ".png")
    property int shown: 0
    property bool playing: true
    Timer { interval: 5000; repeat: true; running: root.playing && root.visible; onTriggered: root.shown = (root.shown + 1) % 3 }
    function stateForTest() { return { shown: shown, playing: playing, title: heading.text } }

    Flickable {
        anchors.fill: parent
        contentHeight: Math.max(height, col.height + 82)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: 600
            x: (root.width - width) / 2
            y: Math.max(41, (parent.height - height) / 2)
            Item {
                width: parent.width; height: 39
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Text { id: heading; text: qsTr("Chat with"); font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; lineHeight: 36; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Image { anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; sourceSize: Qt.size(64, 64); source: root.cdn + "fre/monetization/copilot.png"; asynchronous: true }
                    Text { text: qsTr("Copilot in Teams"); font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; lineHeight: 36; lineHeightMode: Text.FixedHeight; color: theme.text }
                }
                Accessible.role: Accessible.Heading
                Accessible.name: qsTr("Chat with Copilot in Teams")
            }
            Item { width: 1; height: 30 }
            Rectangle {
                width: 600; height: 343; radius: 12; clip: true
                color: theme.pick("#F5F5F5", "#292929", "#000000")
                Repeater {
                    model: root.pictures
                    Image {
                        required property string modelData
                        required property int index
                        anchors.fill: parent
                        source: modelData; asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        opacity: root.shown === index ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Image %1").arg(root.shown + 1)
            }
            Item { width: 1; height: 12 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 32
                spacing: 0
                CarouselButton { icon: root.playing ? "pause-20" : "play-20"; label: root.playing ? qsTr("Pause") : qsTr("Autoplay"); boxed: true; onPicked: root.playing = !root.playing }
                CarouselButton { icon: "chevron-left-20"; label: qsTr("Previous image"); onPicked: root.shown = (root.shown + 2) % 3 }
                Item { width: 8; height: 1 }
                Repeater {
                    model: 3
                    Item {
                        required property int index
                        width: 24; height: 32
                        Rectangle {
                            anchors.centerIn: parent
                            width: root.shown === index ? 16 : 8; height: 8; radius: 4
                            color: root.shown === index ? theme.text : theme.textSecondary
                        }
                        TapHandler { onTapped: root.shown = index }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Go to image %1").arg(index + 1)
                    }
                }
                Item { width: 8; height: 1 }
                CarouselButton { icon: "chevron-right-20"; label: qsTr("Next image"); onPicked: root.shown = (root.shown + 1) % 3 }
            }
            Item { width: 1; height: 15 }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Collaborate with an AI companion to brainstorm, draft messages, and more with a Microsoft 365 subscription.")
                font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text
            }
            Item { width: 1; height: 30 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 20; spacing: 8
                Repeater {
                    model: ["brand-word-20", "brand-excel-20", "brand-powerpoint-20", "brand-onenote-20", "onedrive-color"]
                    Image { required property string modelData; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "../assets/icons/" + modelData + ".svg" }
                }
                Item { width: 2; height: 1 }
                Text {
                    id: benefits
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("View all benefits") + " →"
                    font.family: theme.font; font.pixelSize: 14
                    color: bh.hovered ? theme.brandHover : theme.brandForeground1
                    font.underline: bh.hovered
                    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.viewBenefits() }
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("View all benefits")
                }
            }
            Item { width: 1; height: 30 }
            Rectangle {
                id: explore
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(179, exploreText.implicitWidth + 40); height: 40; radius: 4
                color: eh.pressed ? theme.pick("#444791", "#444791", "#1AEBFF") : ehh.hovered ? theme.brandHover : theme.brandFill
                Text { id: exploreText; anchors.centerIn: parent; text: qsTr("Explore plans now"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(explore, "#FFFFFF") }
                HoverHandler { id: ehh; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: eh; onTapped: root.explorePlans() }
                Accessible.role: Accessible.Button
                Accessible.name: exploreText.text
            }
            Item { width: 1; height: 30 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text { text: qsTr("Already have a subscription?"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    text: qsTr("Start using Copilot")
                    font.family: theme.font; font.pixelSize: 14; font.bold: true; lineHeight: 20; lineHeightMode: Text.FixedHeight
                    color: sh.hovered ? theme.brandHover : theme.brandForeground1
                    font.underline: sh.hovered
                    HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.refreshRequested() }
                    Accessible.role: Accessible.Link
                    Accessible.name: text
                }
            }
        }
    }

    component CarouselButton: Rectangle {
        id: cb
        property string icon
        property string label
        property bool boxed: false
        signal picked()
        width: 32; height: 32; radius: 4
        color: boxed ? theme.pick("#EBEBEB", "#3D3D3D", "#000000") : cbh.hovered ? theme.rowHover : "transparent"
        border.color: boxed ? theme.pick("#D1D1D1", "#5C5C5C", "#FFFFFF") : "transparent"; border.width: 1
        FluentIcon { anchors.centerIn: parent; name: cb.icon; size: 20; color: theme.onFill(cb, theme.text) }
        HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
}
