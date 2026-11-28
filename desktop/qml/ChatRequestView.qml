import QtQuick
import QtQuick.Controls.Basic

// Teams' chat request (a 1:1 chat someone outside your org, on Teams free,
// started with you: your membership's relationshipState.inQuarantine).
// Measured on testpc2's Teams 26304 for OST Test 2 and on teams.microsoft.com
// for OST Test 1 (2026-11-27), in place of the chat's messages and compose:
// - Teams' request picture (its AcceptBlockSvg, 200 x 200) centred 1 under
//   the header;
// - "{name} ({email}) wants to chat with you" (or "{name} wants to chat with
//   you" when OST has no address for them) 20/28 semibold, centred, 43 under
//   the picture;
// - a 600 wide #EBEBEB box (radius 4, padding 24 32) 17 under it: "This
//   person is from outside your organization" 14/20 semibold after the
//   warning glyph, Teams' spam warning, and when they don't share their
//   address "Note: This person is not sharing their email in Teams. To be
//   safe," and the "preview their messages." link (14/20);
// - Block and Accept (96 x 32, 8 apart) 38 under the box;
// - at the bottom, 12/17 centred in 580: "By selecting Accept, you agree …
//   (External). To limit communications, you can block them at any time."
//   and Learn more.
// "preview their messages." shows the chat's messages with Block and Accept
// kept under them (`previewing`).
// A personal account's request (`personal`; Teams free on testpc2,
// 2026-11-28, OST Personal 2 asked by OST Personal 1) has no "from outside
// your organization" line and no disclaimer; its preview bar holds "{name}
// wants to chat with you" (14/20 semibold) and the spam warning (14/20) at
// the left, Block and Accept at the right, 16 from the bottom.
Rectangle {
    id: root
    color: theme.surface
    /// The person asking: {mri, name, mail}.
    property var person: ({})
    /// While their messages are previewed: only the bottom bar shows.
    property bool previewing: false
    /// Asking the service (Accept or Block pressed).
    property bool busy: false
    /// Teams free's request (see above).
    property bool personal: false
    /// Teams free's group request: "{name} added you to a group chat".
    property bool groupRequest: false
    /// How tall the bar under a preview is (Block / Accept and the
    /// disclaimer).
    readonly property real previewHeight: personal ? personalBar.height + 32 : 32 + 16 + disclaimer.height + 12
    signal accept()
    signal block()
    signal preview()

    readonly property string personName: person && person.name ? person.name : ""
    readonly property string personMail: person && person.mail ? person.mail : ""
    readonly property bool mailPrivate: !personMail || !!(person && person.mail_private)
    // Teams' tfwTfwFedOneOnOneNewUILearnMoreUrl.
    readonly property string learnMoreUrl: "https://go.microsoft.com/fwlink/?linkid=2243561"

    // The pane scrolls when the window is too short for it.
    Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.previewing ? height : Math.max(height, root.personal ? content.y + content.height + 24 : disclaimer.y + disclaimer.height + 12)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: !root.previewing && contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: content
            visible: !root.previewing
            width: parent.width
            spacing: 0
            Item { width: 1; height: 1 }
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "../assets/illustrations/chat-request.svg"
                sourceSize: Qt.size(200, 200)
                width: 200; height: 200
            }
            Item { width: 1; height: 43 }
            Text {
                width: Math.min(parent.width - 48, 800); anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: root.groupRequest ? qsTr("%1 added you to a group chat").arg(root.personName)
                    : root.personMail
                    ? qsTr("%1 (%2) wants to chat with you", "messaging:k8i85rtfs").arg(root.personName).arg(root.personMail)
                    : qsTr("%1 wants to chat with you", "messaging:k8zm4zvb2").arg(root.personName)
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                lineHeight: 28; lineHeightMode: Text.FixedHeight
                color: theme.text
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Item { width: 1; height: 17 }
            Rectangle {
                id: box
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(600, parent.width - 48); height: boxCol.height + 48
                radius: 4
                color: theme.pick("#EBEBEB", "#292929", "#000000")
                border.color: theme.hc("transparent", "#FFFFFF"); border.width: theme.highContrast ? 1 : 0
                Column {
                    id: boxCol
                    x: 32; y: 24; width: parent.width - 64
                    spacing: 20
                    Row {
                        visible: !root.personal
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "warning-20"; size: 16; color: theme.text }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("This person is from outside your organization", "messaging:kc21tzs78")
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: theme.text
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: qsTr("Messages from unknown or unexpected people could be spam or phishing attempts. Never share your account information or authorize sign-in requests over chat.", "messaging:karvikcmc")
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Column {
                        width: parent.width
                        spacing: 6
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            textFormat: Text.StyledText
                            // (As Teams showed it for both test accounts, whose
                            // addresses are private; someone sharing theirs gets
                            // only "To be safe, preview their messages.")
                            text: (root.mailPrivate ? "<b>" + qsTr("Note: ", "messaging:k6f4shg5b").trim() + "</b> "
                                + qsTr("This person is not sharing their email in Teams. ", "messaging:k1icza3g0") : "") + qsTr("To be safe, ", "messaging:k7fj7t837").trim()
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                            color: theme.text
                        }
                        Text {
                            id: previewLink
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("preview their messages.", "messaging:k8dhlu5yh")
                            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
                            font.underline: previewHover.hovered
                            color: theme.brandForeground1
                            HoverHandler { id: previewHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.preview() }
                            Accessible.role: Accessible.Link
                            Accessible.name: text
                        }
                    }
                }
            }
            Item { width: 1; height: 38 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                RequestButton { text: qsTr("Block"); onClicked: root.block() }
                RequestButton { text: qsTr("Accept"); onClicked: root.accept() }
            }
        }
        Text {
            id: disclaimer
            visible: !root.personal
            anchors.horizontalCenter: parent.horizontalCenter
            // At the bottom, but never over Block and Accept: in a short window
            // (the 588 x 493 chat pop-out) the pane scrolls instead.
            y: root.previewing ? root.height - 12 - height : Math.max(content.y + content.height + 40, root.height - 78 - height)
            width: Math.min(580, parent.width - 48)
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: theme.linkCss(theme.brandForeground1, true)
                + qsTr("By selecting Accept, you agree to receive future communications and share some account information such as your name and status with %1 (External). To limit communications, you can block them at any time.", "messaging:k9lkmkyv7")
                    .arg(root.personName).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                + " <a href=\"" + root.learnMoreUrl + "\">" + qsTr("Learn more") + "</a>"
            font.family: theme.font; font.pixelSize: 12; lineHeight: 17; lineHeightMode: Text.FixedHeight
            color: theme.textStrong
            onLinkActivated: link => backend.openExternal(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }

    }
    // The Block / Accept bar under a preview.
    // Teams free's preview bar.
    Item {
        id: personalBar
        visible: root.previewing && root.personal
        x: 64; width: parent.width - 128
        y: parent.height - 16 - height
        height: Math.max(barText.height, 32)
        Column {
            id: barText
            width: parent.width - barButtons.width - 16
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: root.groupRequest ? qsTr("%1 added you to a group chat").arg(root.personName) : qsTr("%1 wants to chat with you", "messaging:k8zm4zvb2").arg(root.personName)
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: qsTr("Messages from unknown or unexpected people could be spam or phishing attempts. Never share your account information or authorize sign-in requests over chat.", "messaging:karvikcmc")
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.textStrong
            }
        }
        Row {
            id: barButtons
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            RequestButton { text: qsTr("Block"); onClicked: root.block() }
            RequestButton { text: qsTr("Accept"); onClicked: root.accept() }
        }
    }
    Rectangle {
        visible: root.previewing && !root.personal
        // (16 over the disclaimer; the pane doesn't scroll while previewing.)
        anchors { left: parent.left; right: parent.right }
        y: disclaimer.y - 16 - height
        height: 32
        color: "transparent"
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            RequestButton { text: qsTr("Block"); onClicked: root.block() }
            RequestButton { text: qsTr("Accept"); onClicked: root.accept() }
        }
    }
    component RequestButton: Rectangle {
        id: btn
        property string text
        signal clicked()
        width: Math.max(96, label.implicitWidth + 24); height: 32; radius: 4
        opacity: root.busy ? 0.6 : 1
        color: btnHover.hovered && !root.busy ? theme.menuHover : theme.surface
        border.color: theme.stroke; border.width: 0.67
        Text {
            id: label
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.onFill(btn, theme.text)
        }
        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !root.busy; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
