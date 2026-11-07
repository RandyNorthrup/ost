import QtQuick
import QtQuick.Controls.Basic

// Teams' "Report this message" dialog (chat-report-a-concern-v2-dialog,
// measured on this tenant, where only security reporting applies):
// - 600 x 349, radius 8, content 25 in;
// - "Report a security concern" (20/28 semibold), with a Close button;
// - the message as a quote card (name only);
// - "Enter an explanation (optional)": 551 x 52, NeutralStroke2 border,
//   at most 250 characters, with "{n}/250 maximum characters" under it;
// - Teams' notice about sharing with your IT admin and Microsoft, with
//   Learn more;
// - Cancel and Report (96 x 32); "Reporting" while it sends. A failure shows
//   "Report didn't send. Try again.".
Popup {
    id: root
    property var message: null
    modal: true; focus: true
    width: 600; height: 349 + (failed ? 28 : 0)
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }
    readonly property bool sending: backend.reportResult === "sending"
    readonly property bool failed: backend.reportResult === "error"
    onOpened: { why.text = ""; why.forceActiveFocus() }
    Connections {
        target: backend
        function onReportResultChanged() { if (root.opened && backend.reportResult === "ok") root.close() }
    }

    Text { x: 25; y: 25; height: 28; verticalAlignment: Text.AlignVCenter; text: "Report a security concern"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Rectangle {
        x: 543; y: 25; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    QuoteCard {
        x: 25; y: 68
        showTime: false
        maxWidth: 551
        quote: root.message ? { message_id: root.message.id, sender_mri: root.message.sender_mri, sender_name: root.message.sender, preview: root.message.quote_text || root.message.text } : null
    }
    Rectangle {
        x: 25; y: 139; width: 551; height: 52; radius: 4
        color: theme.surface; border.color: why.activeFocus ? theme.brand : theme.divider
        TextInput {
            id: why
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            maximumLength: 250
            clip: true
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            Text { visible: !why.text; text: "Enter an explanation (optional)"; font: why.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Enter an explanation (optional)"
        }
    }
    Text { x: 25; y: 199; height: 16; verticalAlignment: Text.AlignVCenter; text: why.text.length + "/250 maximum characters"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
    Text {
        x: 25; y: 230; width: 551
        wrapMode: Text.Wrap; textFormat: Text.StyledText
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        text: "Information about this message will be shared with your IT admin and Microsoft. Microsoft may use the information to improve the accuracy of detection. <a href=\"https://learn.microsoft.com\">Learn more</a>"
        linkColor: theme.brandForeground2
        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
    Row {
        visible: root.failed
        x: 25; y: 274; spacing: 6
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "warning-12-filled"; size: 16; color: theme.redForeground1 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Report didn't send. Try again."; font.family: theme.font; font.pixelSize: theme.base; color: theme.redForeground1 }
    }
    Row {
        x: 375; y: 293 + (root.failed ? 28 : 0); spacing: 8
        Rectangle {
            width: 96; height: 32; radius: 4
            color: cancelHover.hovered && !root.sending ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: root.sending ? theme.disabled : theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.sending; onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            width: 96; height: 32; radius: 4
            color: root.sending ? theme.bgDisabled : reportHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: root.sending ? "Reporting" : "Report"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: root.sending ? theme.disabledStrong : "white" }
            HoverHandler { id: reportHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !root.sending; onTapped: backend.reportMessage(root.message.id, why.text) }
            Accessible.role: Accessible.Button
            Accessible.name: "Report"
        }
    }
}
