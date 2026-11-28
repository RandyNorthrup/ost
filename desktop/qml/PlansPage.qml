import QtQuick

// Settings ▸ Plans and upgrades for a personal account, as Teams for
// personal use shows it to a free account (Teams desktop 26304 with OST
// Personal 2 and teams.live.com with OST Personal 1, 2026-11-28): Teams'
// Microsoft 365 banner (the page's width, 962 x 225), then two cards side
// by side, 359 wide, centred, 24 under it:
// - "Microsoft 365 plan" (white, radius 12, Fluent shadow 8, 554 tall):
//   the Microsoft mark (48) 30 down, the title (16/22 bold) 94 down, the
//   plan's benefits from 150 down every 36 (their 20 px marks 29 in, the
//   text 54 in, 14/20), Upgrade (265 x 32, primary) 408 down, "Already
//   have a subscription?" 456 down and Verify subscription (a 331 x 32
//   brand-text button) 492 down;
// - "Your free benefits" (#F0F0F0, its right corners rounded, 520 tall,
//   18 down): the Teams mark 16 down, the title 80 down, the free
//   benefits from 136 down with a brand check mark.
// Teams' Upgrade opens its in-app purchase dialog; OST opens Microsoft's
// plans page in the browser instead (it never buys in the app). Verify
// subscription reads the licence again.
Item {
    id: root
    /// The account's consumerLicenseDetails (maxMeetingDurationMinutes,
    /// maxMeetingParticipants, …).
    property var license: ({})
    signal upgrade()
    signal verify()
    readonly property string cdn: "https://tflteams.public.onecdn.static.microsoft/evergreen-assets/fre/monetization/"
    readonly property int minutes: (license.teamsFree || license).maxMeetingDurationMinutes || 60
    readonly property int participants: (license.teamsFree || license).maxMeetingParticipants || 100
    height: cards.y + planCard.height + 20

    Image {
        id: banner
        width: parent.width; height: width * 225 / 962
        source: root.cdn + "plans/M365Banner.png"
        fillMode: Image.PreserveAspectCrop; asynchronous: true
        Rectangle { anchors.fill: parent; visible: parent.status !== Image.Ready; color: theme.pick("#F5EFE6", "#292929", "#000000") }
    }
    Item {
        id: cards
        y: banner.height + 24
        width: 718; height: planCard.height
        anchors.horizontalCenter: parent.horizontalCenter
        // The free card first, so the plan card's shadow falls over it.
        Rectangle {
            id: freeCard
            x: 361; y: 18; width: 359; height: 520
            color: theme.pick("#F0F0F0", "#292929", "#000000")
            radius: 12
            // (only the right corners rounded)
            Rectangle { width: 12; height: parent.height; color: parent.color }
            Image { x: (parent.width - 48) / 2; y: 16; width: 48; height: 48; sourceSize: Qt.size(96, 96); source: root.cdn + "plans/Teams2Icon_48.svg"; asynchronous: true }
            Text { y: 80; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Your free benefits"); font.family: theme.font; font.pixelSize: 16; font.bold: true; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Column {
                x: 60; y: 136
                spacing: 16
                Repeater {
                    model: [root.minutes % 60 === 0 && root.minutes >= 60
                                ? (root.minutes === 60 ? qsTr("1 hour for each meeting and call") : qsTr("%1 hours for each meeting and call").arg(root.minutes / 60))
                                : qsTr("%1 minutes for each meeting and call").arg(root.minutes),
                            qsTr("Up to %1 meeting participants").arg(root.participants),
                            qsTr("5 GB OneDrive cloud storage")]
                    Row {
                        required property string modelData
                        spacing: 5; height: 20
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "checkmark-20"; size: 20; color: theme.brand }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                }
            }
        }
        FluentSurface {
            id: planCard
            width: 359; height: 554
            depth: 8; radius: 12; color: theme.surface
            Image { x: (parent.width - 48) / 2; y: 30; width: 48; height: 48; sourceSize: Qt.size(96, 96); source: root.cdn + "plans/MicrosoftSVG.svg"; asynchronous: true }
            Text { y: 94; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Microsoft 365 plan"); font.family: theme.font; font.pixelSize: 16; font.bold: true; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
            Column {
                x: 29; y: 150
                spacing: 16
                Repeater {
                    model: [{ icon: "plans/Video.png", text: qsTr("30 hours for each meeting and call") },
                            { icon: "plans/People.png", text: qsTr("Up to 300 meeting participants") },
                            { icon: "plans/Cloud.png", text: qsTr("1 TB of secure cloud storage (2 TB shared)") },
                            { icon: "copilot.png", text: qsTr("Productivity apps with Microsoft Copilot") },
                            { icon: "record.png", text: qsTr("Record calls and meetings") },
                            { icon: "plans/Microsoft.png", text: qsTr("And more benefits from Microsoft 365") }]
                    Row {
                        required property var modelData
                        spacing: 5; height: 20
                        Image { width: 20; height: 20; sourceSize: Qt.size(40, 40); source: root.cdn + modelData.icon; asynchronous: true }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                }
            }
            Rectangle {
                id: upgradeBtn
                x: 42; y: 408; width: 265; height: 32; radius: 4
                color: uh.pressed ? theme.pick("#444791", "#444791", "#1AEBFF") : uhh.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Upgrade"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(upgradeBtn, "#FFFFFF") }
                HoverHandler { id: uhh; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: uh; onTapped: root.upgrade() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Upgrade")
                Accessible.onPressAction: root.upgrade()
            }
            Text { y: 456; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Already have a subscription?"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Rectangle {
                id: verifyBtn
                x: 14; y: 492; width: 331; height: 32; radius: 4
                color: vh.hovered ? theme.rowHover : "transparent"
                Text { anchors.centerIn: parent; text: qsTr("Verify subscription"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(verifyBtn, theme.brandForeground1) }
                HoverHandler { id: vh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.verify() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Verify subscription")
                Accessible.onPressAction: root.verify()
            }
        }
    }
}
