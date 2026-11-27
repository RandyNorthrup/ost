import QtQuick
import QtQuick.Controls.Basic

// Teams' "Add an existing page" (a channel's "+" ▸ Existing page; the
// paste-loop-modal), measured in Teams on the web 2026-11-16
// (docs/spec/add-a-tab.md):
// - 600 wide, radius 8, padding 16 24, Teams' dialog shadow; 186 tall,
//   274 with the page's card;
// - "Add an existing page" (h2, 20/28 semibold) 17 down; "When you add a
//   page, everyone in the channel can access it." (12/16, #424242) at 48;
// - the link field (550 x 32, filled, "Paste a link" 12/20 #707070,
//   padding 0 12, brand focus line) at 81;
// - Add page resolves the link and shows the page's card (550 x 64 at 137,
//   white, radius 4, padding 12): the Loop icon (20) at 12, the page's name
//   (14/20 semibold) and "Last edited by <name>" (12/20 semibold #424242)
//   at 44, "Open in Loop" (32 x 32) at the end; the primary button becomes
//   Confirm, which adds the tab;
// - New Page (96 x 32, outline) at the left, Cancel (96 x 32) and Add page
//   / Confirm (96 x 32, brand; #F0F0F0 / #BDBDBD while off) at the right,
//   24 under the last row.
Popup {
    id: root
    property string teamId: ""
    property string channelId: ""
    property bool busy: false
    property string failure: ""
    property var page: null
    readonly property bool confirming: !!page
    anchors.centerIn: Overlay.overlay
    modal: true; focus: true
    width: 600; height: confirming ? 274 : 186 + (failure ? 20 : 0)
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
    /// New Page: a channel's New page instead (Teams makes one).
    signal newPage()
    function start(team, channel) {
        teamId = team; channelId = channel; busy = false; failure = ""; page = null
        field.text = ""
        open()
        field.forceActiveFocus()
    }
    function next() {
        if (busy || !field.text.trim()) return
        busy = true; failure = ""
        if (!confirming) backend.resolvePageLink(field.text.trim())
        else backend.addExistingPage(teamId, channelId, field.text.trim())
    }
    Connections {
        target: backend
        enabled: root.opened && root.busy
        function onPageLinkJsonChanged() {
            const r = JSON.parse(backend.pageLinkJson || "{}")
            if (r.link !== field.text.trim()) return
            root.busy = false
            if (r.page) root.page = r.page
            else root.failure = r.error || ""
        }
        function onChannelTabResultChanged() {
            const r = JSON.parse(backend.channelTabResult || "{}")
            if (r.op !== "add" || r.conversation !== root.channelId) return
            root.busy = false
            if (r.ok) root.close()
            else root.failure = r.error || ""
        }
    }
    function fillForTest(t) { field.text = t }
    function stateForTest() { return JSON.stringify({ link: field.text, page: page, failure: failure, busy: busy, height: height }) }

    component Button96: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        width: 96; height: 32; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (bh.hovered ? theme.brandHover : theme.brandFill) : (bh.hovered ? theme.menuHover : theme.surface)
        border.width: 1; border.color: primary || !enabled ? "transparent" : theme.stroke
        Text { anchors.centerIn: parent; text: b.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(b, !b.enabled ? theme.disabled : b.primary ? theme.textOnBrand : theme.text) }
        HoverHandler { id: bh; cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: b.enabled; onTapped: b.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    Text {
        x: 25; y: 17; width: 550; height: 28
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Add an existing page")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    Text {
        x: 25; y: 48; height: 16
        text: qsTr("When you add a page, everyone in the channel can access it.")
        font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
    }
    Rectangle {
        id: box
        x: 25; y: 81; width: 550; height: 32; radius: 4
        color: theme.inputFilled; border.width: 1; border.color: theme.transparentStroke
        TextInput {
            id: field
            x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 12; color: theme.text; clip: true
            selectByMouse: true
            enabled: !root.confirming
            onTextChanged: if (!root.confirming) root.failure = ""
            Keys.onReturnPressed: root.next()
            Keys.onEnterPressed: root.next()
            Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Paste a link")
        }
        Text {
            visible: !field.text
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Paste a link"); font.family: theme.font; font.pixelSize: 12; color: theme.textTertiary
        }
        Rectangle { visible: field.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
    }
    Text {
        visible: !!root.failure
        x: 25; y: 117; width: 550
        text: root.failure; elide: Text.ElideRight
        font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3
        Accessible.role: Accessible.AlertMessage; Accessible.name: text
    }
    // The page's card.
    Rectangle {
        id: card
        visible: root.confirming
        x: 25; y: 137; width: 550; height: 64; radius: 4
        color: theme.surface; border.width: 1; border.color: theme.dividerSoft
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "loop-page-20"; size: 20; color: theme.brand }
        Text {
            x: 44; y: 12; width: parent.width - 44 - 56; height: 20
            text: root.page ? root.page.name : ""; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
        }
        Text {
            x: 44; y: 32; width: parent.width - 44 - 56; height: 20
            text: root.page && root.page.edited_by ? qsTr("Last edited by %1").arg(root.page.edited_by) : ""; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textStrong
        }
        Rectangle {
            id: openBtn
            x: parent.width - 44; y: 16; width: 32; height: 32; radius: 4
            color: openHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "open-20"; size: 20; color: theme.onFill(openBtn, theme.textStrong) }
            HoverHandler { id: openHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (root.page && root.page.web_url) backend.openExternal(root.page.web_url) }
            ToolTip.visible: openHover.hovered; ToolTip.text: qsTr("Open in Loop"); ToolTip.delay: 500
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Open in Loop")
        }
    }
    Item {
        x: 25; y: root.confirming ? 225 : 137 + (root.failure ? 20 : 0); width: 550; height: 32
        Button96 { label: qsTr("New Page"); onClicked: { root.close(); root.newPage() } }
        Row {
            anchors.right: parent.right; spacing: 8
            Button96 { label: qsTr("Cancel"); onClicked: root.close() }
            Button96 { label: root.confirming ? qsTr("Confirm") : qsTr("Add page"); primary: true; enabled: !!field.text.trim() && !root.busy; onClicked: root.next() }
        }
    }
}
