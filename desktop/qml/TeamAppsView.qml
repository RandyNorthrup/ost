import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Manage team ▸ Apps (Teams' tab, measured on winpc 2026-11-09;
// docs/spec/chat-list-and-header.md §5.6.7). Offsets from the tab area:
// - Get more apps (outlined, the add glyph, 140.8 x 31.3) at 64, 28.6;
//   Create an outgoing webhook (transparent, the webhook glyph) at 219.8;
//   Sort (transparent, A-Z / Z-A) at 551; Find by name (filled, a search
//   glyph) at the right.
// - The apps from 68.3 down, 41 in, 836 wide: 65 tall rows with a line
//   between them: the icon (36) at 89, the name (14/20 bold) and publisher
//   (14/16 #616161) at 132, ··· (Copy link | Remove) at the right.
// - Create an outgoing webhook: Teams' dialog (Name *, Callback URL *,
//   Description *, a 30 KB PNG profile picture; Cancel / Create).
Item {
    id: view
    property string teamId: ""
    property string teamThread: ""
    property bool owner: false
    property var apps: []
    property bool descending: false
    property bool sorted: false
    signal getMoreApps()
    readonly property string query: find.text.trim().toLowerCase()
    readonly property var shown: {
        const list = apps.filter(a => !query || (a.name || "").toLowerCase().indexOf(query) >= 0).slice()
        list.sort((a, b) => (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase()))
        return descending ? list.reverse() : list
    }

    function load() { if (teamThread) backend.channelAction("team-apps", teamId, teamThread, "") }
    onTeamThreadChanged: { apps = []; find.text = ""; descending = false; sorted = false; load() }
    Component.onCompleted: load()
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== view.teamThread) return
            if (r.op === "team-apps" && r.ok) view.apps = r.data.apps || []
            else if (r.op === "team-app-remove" || r.op === "team-webhook") {
                if (!r.ok) backend.toast("Something went wrong on our end. Please try again.", "error")
                view.load()
            }
        }
    }

    Rectangle {
        x: 64; y: 28.6; width: 140.8; height: 31.3; radius: 4
        color: moreHover.hovered ? theme.menuHover : theme.surface
        border.color: theme.stroke; border.width: 0.67
        Row {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { name: "add-20"; size: 20; color: theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Get more apps"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        }
        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: view.getMoreApps() }
        Accessible.role: Accessible.Button
        Accessible.name: "Get more apps"
    }
    Plain {
        visible: view.owner
        x: 219.8; y: 28.6
        icon: "webhook-20"; text: "Create an outgoing webhook"
        onClicked: webhook.start()
    }
    Plain {
        x: 551; y: 28.3
        icon: "arrow-sort-20"; text: "Sort"
        active: view.sorted
        onClicked: { if (view.sorted) view.descending = !view.descending; view.sorted = true }
    }
    Rectangle {
        x: parent.width - 21.3 - width; y: 28.6; width: 200; height: 31.3; radius: 4
        color: theme.inputFilled
        Rectangle { visible: find.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        TextInput {
            id: find
            x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            clip: true
            selectByMouse: true
            Text { visible: !find.text; anchors.verticalCenter: parent.verticalCenter; text: "Find by name"; font: find.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Find by name"
        }
        FluentIcon { x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
    }

    Flickable {
        x: 41; y: 68.3; width: Math.min(836, parent.width - 76); height: parent.height - y
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: list
            width: parent.width
            Rectangle { width: parent.width; height: 0.67; color: theme.divider }
            Repeater {
                model: view.shown
                Rectangle {
                    id: row
                    required property var modelData
                    width: list.width; height: 65
                    color: rowHover.hovered ? theme.menuHover : "transparent"
                    HoverHandler { id: rowHover }
                    AppIcon {
                        x: 48; y: 14.4; width: 36; height: 36
                        source: /^(https|file):\/\//.test(row.modelData.icon || "") ? row.modelData.icon : ""
                    }
                    Text {
                        x: 91; y: 16.4; width: parent.width - 160; elide: Text.ElideRight
                        text: row.modelData.name || row.modelData.id
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.text
                    }
                    Text {
                        x: 91; y: 36.4; width: parent.width - 160; elide: Text.ElideRight
                        text: row.modelData.publisher || ""
                        font.family: theme.font; font.pixelSize: 14
                        lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.textSecondary
                    }
                    Rectangle {
                        id: more
                        x: 758.7 - (836 - list.width); y: 17; width: 32; height: 31.3; radius: 4
                        color: moreH.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: moreH; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { rowMenu.app = row.modelData; rowMenu.parent = more; rowMenu.x = more.width - rowMenu.implicitWidth; rowMenu.y = more.height + 4; rowMenu.open() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options"
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                }
            }
        }
    }

    MenuPopup {
        id: rowMenu
        property var app: null
        margins: 8
        items: [{ key: "link", label: "Copy link", icon: "link-20" }].concat(view.owner ? [{ key: "remove", label: "Remove", icon: "delete-20" }] : [])
        onPicked: i => {
            const k = items[i].key
            if (k === "link") backend.copyText("https://teams.microsoft.com/l/app/" + rowMenu.app.id + "?source=manage-apps-copy-link")
            else if (k === "remove") backend.channelAction("team-app-remove", view.teamId, view.teamThread, rowMenu.app.id)
        }
    }

    // Create an outgoing webhook.
    Popup {
        id: webhook
        property string icon: ""
        function start() { nameField.text = ""; urlField.text = ""; descField.text = ""; icon = ""; open(); nameField.forceActiveFocus() }
        readonly property bool valid: nameField.text.trim().length > 0 && /^https:\/\//i.test(urlField.text.trim()) && descField.text.trim().length > 0
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600; height: 561.8; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }
        FileDialog {
            id: iconFile
            title: "Profile picture"
            nameFilters: ["PNG (*.png)"]
            onAccepted: webhook.icon = selectedFile.toString()
        }
        Item {
            anchors.fill: parent
            Text { y: 0.7; text: "Create an outgoing webhook"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 28; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text {
                y: 36.6; width: parent.width; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: "Outgoing webhooks allow you to send commands to services that respond with messages and rich cards. While you control whether data is sent to or received from third parties, Microsoft recommends that you only integrate with trusted systems. <a href=\"https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-outgoing-webhook\">Click to learn more</a> about outgoing webhooks."
                linkColor: theme.brandForeground1
                font.family: theme.font; font.pixelSize: 14
                lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.text
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            FieldLabel { y: 148; text: "Name" }
            Field { id: nameField; y: 170.6 }
            FieldLabel { y: 219; text: "Callback URL" }
            Field { id: urlField; y: 241.6 }
            FieldLabel { y: 290; text: "Description*" }
            Rectangle {
                y: 312.6; width: parent.width; height: 76.7; radius: 4
                color: theme.inputFilled
                TextEdit {
                    id: descField
                    x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.text
                    clip: true
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Description"
                }
                Rectangle { visible: descField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
            }
            Text { y: 407; text: "Profile picture (optional) - 30kb max, png only"; font.family: theme.font; font.pixelSize: 12; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textSecondary }
            Row {
                y: 431; spacing: 8
                Rectangle {
                    width: chooseText.implicitWidth + 16; height: 22; radius: 2
                    color: chooseHover.hovered ? theme.pick("#E5E5E5", "#3D3D3D") : theme.pick("#EFEFEF", "#333333")
                    border.color: theme.pick("#767676", "#999999"); border.width: 1
                    Text { id: chooseText; anchors.centerIn: parent; text: "Choose File"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: chooseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: iconFile.open() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Choose File"
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: webhook.icon ? webhook.icon.split("/").pop() : "No file chosen"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            Row {
                anchors.right: parent.right; y: 479.1
                spacing: 10
                Btn { text: "Cancel"; onClicked: webhook.close() }
                Btn {
                    text: "Create"; primary: true; enabled: webhook.valid
                    onClicked: {
                        backend.channelAction("team-webhook", view.teamId, view.teamThread, JSON.stringify({ name: nameField.text.trim(), url: urlField.text.trim(), description: descField.text.trim(), icon: webhook.icon.replace(/^file:\/\//, "") }))
                        webhook.close()
                    }
                }
            }
        }
    }

    component FieldLabel: Row {
        property string text
        spacing: 4
        Text { text: parent.text; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        Text { text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3 }
    }
    component Field: Rectangle {
        property alias text: input.text
        function forceActiveFocus() { input.forceActiveFocus() }
        width: parent.width; height: 32; radius: 4
        color: theme.inputFilled
        TextInput {
            id: input
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
            clip: true
            selectByMouse: true
        }
        Rectangle { visible: input.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
    }
    component Plain: Rectangle {
        id: pb
        property string icon
        property string text
        property bool active: false
        signal clicked()
        width: pbRow.implicitWidth + 24; height: 31.3; radius: 4
        color: pbHover.hovered ? theme.menuHover : "transparent"
        Row {
            id: pbRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { name: pb.icon; size: 20; color: pb.active ? theme.brand : theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pb.active ? theme.brand : theme.textStrong }
        }
        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
    component Btn: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: 96; height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text { anchors.centerIn: parent; text: btn.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !btn.enabled ? theme.disabled : btn.primary ? theme.textOnBrand : theme.text }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function webhookForTest() { return webhook }
    function rowMenuForTest() { return rowMenu }
}
