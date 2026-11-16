import QtQuick

// Teams' completion step after a voice or face capture (biometric-
// enrollment `me`, measured on winpc 2026-11-15): 600 x 592.5 at its
// fullest. Teams' "all set" picture (600 x 160), "Thanks for letting us get
// to know you!" (24/700), then a Voice and a Face section: a green check
// after the name when you have that profile, else what it is for, Privacy
// policy and Get started; Close.
Item {
    id: done
    property bool voice: false
    property bool face: false
    signal startVoice()
    signal startFace()
    signal closed()
    width: 600
    height: closeButton.y + closeButton.height + 15

    readonly property string privacyUrl: "https://myaccount.microsoft.com/settingsandprivacy/privacy"

    Image {
        width: 600; height: 160
        source: "../assets/biometric/all_set_enrollment.svg"
        sourceSize: Qt.size(1200, 320)
        Accessible.name: "voice enrollment completed icon"
    }
    Text {
        x: 30; y: 180; height: 32
        verticalAlignment: Text.AlignVCenter
        text: "Thanks for letting us get to know you!"
        font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold
        color: theme.text
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    Section {
        id: voiceSection
        y: 252.7
        title: "Voice recognition"
        enrolled: done.voice
        body: "Your voice profile is used to suppress background noises in Teams meetings through voice isolation. When using an intelligent speaker, your voice profile is used to identify you in meeting transcripts." + (done.voice ? "" : " Manage and delete your profile anytime from this device. Takes about 30 seconds.")
        privacyName: "Privacy policy - Voice recognition"
        onStart: done.startVoice()
    }
    Section {
        id: faceSection
        y: voiceSection.y + voiceSection.height + 40.7
        title: "Face recognition"
        enrolled: done.face
        body: done.face ? "Your face will now be identified by Teams when you attend a meeting in a room with an intelligent camera."
                        : "A face profile lets Teams identify you when you attend a meeting in a room with an intelligent camera."
        privacyName: "Privacy policy - Face recognition"
        onStart: done.startFace()
    }
    SettingsParts.Button {
        id: closeButton
        x: 489; y: faceSection.y + faceSection.height + 27.5
        label: "Close"
        onClicked: done.closed()
    }

    component Section: Item {
        id: sec
        property string title
        property string body
        property string privacyName
        property bool enrolled
        signal start()
        x: 30; width: 540
        height: getStarted.visible ? getStarted.y + getStarted.height : bodyText.y + bodyText.height
        Text {
            id: titleText
            height: 22
            text: sec.title
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        FluentIcon {
            visible: sec.enrolled
            x: titleText.implicitWidth + 10; y: 4.5
            name: "checkmark-20-filled"; size: 13; color: theme.hc("#11910D", "#FFFFFF")
        }
        Text {
            id: bodyText
            y: 32; width: 538.7
            textFormat: Text.StyledText
            text: sec.body + (sec.enrolled ? "" : " <a href=\"privacy\">Privacy policy</a>")
            linkColor: theme.brandForeground1
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
            onLinkActivated: Qt.openUrlExternally(done.privacyUrl)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            Accessible.role: Accessible.StaticText
            Accessible.name: sec.body + (sec.enrolled ? "" : " " + sec.privacyName)
        }
        SettingsParts.Button {
            id: getStarted
            visible: !sec.enrolled
            x: 433.1; y: bodyText.y + bodyText.height + 10
            label: "Get started"
            onClicked: sec.start()
        }
    }
}
