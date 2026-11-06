import QtQuick
import QtQuick.Controls.Basic

// Sign-in: start a device-code sign-in, show the code, open the
// Microsoft sign-in page, and wait. The app loads once it's approved.
Rectangle {
    id: root
    property string code
    property string url
    property bool busy
    property string error
    signal signIn()
    color: theme.pane

    Rectangle {
        anchors.centerIn: parent
        width: 440
        height: content.implicitHeight + 88
        radius: 8
        color: theme.surface
        border.color: theme.dividerSoft

        Column {
            id: content
            x: 44; y: 44
            width: parent.width - 88
            spacing: 16

            Image {
                source: "../assets/logo.png"
                width: 56; height: 56
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: root.code ? "Enter this code to sign in" : "Sign in to OST"
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                color: theme.text
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.code
                    ? "Open the sign-in page, enter the code below and approve with your work or school account."
                    : "Use your work or school account to chat, meet and call."
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.textSecondary
            }

            // The device code, selectable so it can be copied.
            Rectangle {
                visible: root.code.length > 0
                width: parent.width; height: 64; radius: theme.radius
                color: theme.pane
                TextEdit {
                    id: codeText
                    anchors.centerIn: parent
                    text: root.code
                    readOnly: true
                    selectByMouse: true
                    font.family: "monospace"; font.pixelSize: 28; font.letterSpacing: 4
                    color: theme.text
                }
            }

            Row {
                spacing: 8
                visible: root.code.length > 0
                PrimaryButton {
                    label: "Open sign-in page"
                    onClicked: Qt.openUrlExternally(root.url)
                }
                SecondaryButton {
                    label: copied ? "Copied" : "Copy code"
                    property bool copied: false
                    onClicked: { codeText.selectAll(); codeText.copy(); codeText.deselect(); copied = true }
                }
            }
            Text {
                visible: root.code.length > 0
                text: "Waiting for you to finish signing in…"
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
            }

            PrimaryButton {
                visible: root.code.length === 0
                label: root.busy ? "Starting…" : "Sign in"
                enabled: !root.busy
                width: parent.width
                onClicked: root.signIn()
            }
            Text {
                visible: root.error.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.error
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.danger
            }
        }
    }

    component PrimaryButton: Rectangle {
        id: btn
        property string label
        signal clicked()
        implicitWidth: btnText.implicitWidth + 32
        height: 32; radius: theme.radius
        opacity: enabled ? 1 : 0.6
        color: hover.hovered ? theme.brandHover : theme.brand
        Text { id: btnText; anchors.centerIn: parent; text: btn.label; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (btn.enabled) btn.clicked() }
    }
    component SecondaryButton: Rectangle {
        id: sbtn
        property string label
        signal clicked()
        implicitWidth: sText.implicitWidth + 32
        height: 32; radius: theme.radius
        color: shover.hovered ? theme.pane : theme.surface
        border.color: theme.stroke
        Text { id: sText; anchors.centerIn: parent; text: sbtn.label; color: theme.text; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
        HoverHandler { id: shover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sbtn.clicked() }
    }
}
