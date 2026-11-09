import QtQuick
import QtQuick.Controls.Basic

// Get email address (Teams' channel email dialog, measured on winpc
// 2026-11-09): 600 wide, padding 24, radius 8.
// - "Get email address" (20/28 semibold); the address as "{channel} -
//   {team} <{address}>" in a read-only field (32, #F5F5F5, radius 4,
//   padding 0 12), selected.
// - "Remove email address" (the delete icon) and "Advanced settings" (a
//   chevron), subtle buttons 31.3 tall.
// - Advanced settings: Anyone can send emails to this address / Only
//   members of this team / Only email sent from these domains: with the
//   domains field ("e.g. microsoft.com, gmail.com", 490.7 wide, 60 in).
// - Close and Copy (Save while the settings are open), 96 x 31.3.
// The address comes from the middle tier (made when the channel has none).
Popup {
    id: dlg
    property string teamId: ""
    property string teamName: ""
    property var channel: ({})
    property var email: null
    property bool advanced: false
    property string allowed: "members"
    property string domains: ""
    property bool busy: false
    property string failure: ""
    readonly property string shown: email ? (channel.name || "") + " - " + teamName + " <" + email.address + ">" : ""

    function start(c) {
        channel = c; email = null; advanced = false; busy = true; failure = ""
        backend.channelAction("email", teamId, c.id, "")
        open()
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== dlg.channel.id) return
            if (r.op === "email" || r.op === "email-senders") {
                dlg.busy = false
                if (r.ok && r.data) {
                    if (r.op === "email") dlg.email = r.data
                    else { const e = Object.assign({}, dlg.email || {}); e.allowed = r.data.allowed; e.domains = r.data.domains; dlg.email = e; dlg.advanced = false }
                    dlg.allowed = dlg.email.allowed || "members"
                    dlg.domains = (dlg.email.domains || []).join(", ")
                    Qt.callLater(() => { field.selectAll(); field.forceActiveFocus() })
                } else dlg.failure = "Something went wrong on our end. Please try again."
            } else if (r.op === "email-remove") {
                dlg.busy = false
                if (r.ok) dlg.close(); else dlg.failure = "Something went wrong on our end. Please try again."
            }
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600; padding: 24
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    component Subtle: Rectangle {
        id: sb
        property string icon
        property string label
        signal clicked()
        width: sbRow.implicitWidth + 24; height: 31.3; radius: 4
        color: sbHover.hovered ? theme.rowHover : "transparent"
        Row {
            id: sbRow
            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 20; name: sb.icon; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: sb.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
        }
        HoverHandler { id: sbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: sb.enabled; onTapped: sb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component Radio: Item {
        id: rb
        property string key
        property string label
        readonly property bool chosen: dlg.allowed === key
        width: 300; height: 32
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 8
            color: "transparent"
            border.color: rb.chosen ? theme.brandForeground1 : theme.textSecondary; border.width: 0.67
            Rectangle { visible: rb.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brandForeground1 }
        }
        Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: rb.label; font.family: theme.font; font.pixelSize: 14; color: rb.chosen ? theme.text : theme.textSecondary }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.allowed = rb.key }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: chosen
        Accessible.name: label
    }

    contentItem: Column {
        spacing: 0
        Text { text: "Get email address"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
        Item { width: 1; height: 23 }
        Rectangle {
            width: parent.width; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#1F1F1F")
            TextInput {
                id: field
                anchors.fill: parent; leftPadding: 12; rightPadding: 12
                verticalAlignment: TextInput.AlignVCenter
                readOnly: true
                selectByMouse: true
                text: dlg.busy && !dlg.email ? "" : dlg.shown
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                selectionColor: theme.selectionFill
                selectedTextColor: theme.text
                clip: true
                Accessible.name: "Email address"
            }
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: field.activeFocus ? 2 : 0; color: theme.brand }
        }
        Item { width: 1; height: 10 }
        Subtle { icon: "delete-20"; label: "Remove email address"; enabled: !!dlg.email && !dlg.busy; onClicked: { dlg.busy = true; backend.channelAction("email-remove", dlg.teamId, dlg.channel.id, "") } }
        Item { width: 1; height: 10 }
        Subtle { icon: dlg.advanced ? "chevron-down-20" : "chevron-right-20"; label: "Advanced settings"; onClicked: dlg.advanced = !dlg.advanced }
        Column {
            visible: dlg.advanced
            x: 30; width: parent.width - 30
            Item { width: 1; height: 4 }
            Radio { key: "anyone"; label: "Anyone can send emails to this address" }
            Radio { key: "members"; label: "Only members of this team" }
            Radio { key: "domains"; label: "Only email sent from these domains:" }
            Item { width: 1; height: 10 }
            Rectangle {
                x: 30; width: 490.7; height: 32; radius: 4
                color: theme.surface
                border.color: theme.divider; border.width: 0.67
                TextInput {
                    id: domainField
                    anchors.fill: parent; leftPadding: 12; rightPadding: 12
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: dlg.allowed === "domains"
                    text: dlg.domains
                    onTextEdited: dlg.domains = text
                    font.family: theme.font; font.pixelSize: 14
                    color: enabled ? theme.text : theme.disabled
                    clip: true
                    Text { visible: !domainField.text; x: 12; anchors.verticalCenter: parent.verticalCenter; text: "e.g. microsoft.com, gmail.com"; font: domainField.font; color: theme.disabled }
                    Accessible.name: "Domains"
                }
            }
        }
        Text {
            visible: !!dlg.failure
            topPadding: 8
            text: dlg.failure
            font.family: theme.font; font.pixelSize: 12; color: theme.danger
        }
        Item { width: 1; height: 24 }
        Row {
            anchors.right: parent.right
            spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: closeHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                Text { anchors.centerIn: parent; text: "Close"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Close"
            }
            Rectangle {
                readonly property bool on: !!dlg.email && !dlg.busy
                width: 96; height: 31.3; radius: 4
                color: !on ? theme.pick("#F0F0F0", "#141414") : primaryHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: dlg.advanced ? "Save" : "Copy"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? "white" : theme.disabled }
                HoverHandler { id: primaryHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    enabled: parent.on
                    onTapped: {
                        if (dlg.advanced) {
                            dlg.busy = true
                            backend.channelAction("email-senders", dlg.teamId, dlg.channel.id, JSON.stringify({ allowed: dlg.allowed, domains: dlg.domains.split(/[,;\s]+/).filter(d => d) }))
                        } else {
                            backend.copyText(dlg.shown)
                            dlg.close()
                        }
                    }
                }
                Accessible.role: Accessible.Button; Accessible.name: dlg.advanced ? "Save" : "Copy"
            }
        }
    }
}
