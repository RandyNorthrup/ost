import QtQuick
import QtQuick.Controls.Basic

// A Loop component as Teams shows it in the compose box and in a message
// (measured on winpc 2026-11-20, "OST TEST 85 loop" in OST group test):
// - a white card, radius 12, 0.67 #E0E0E0 (a brand glow while you are in
//   it), 372 tall: a 48 px header and Loop's frame (320 tall, Teams'
//   messaging maxHeight 20rem) 2.67 in and 50.7 down;
// - the header: the component's name as a button (28 tall at 22, 12; the
//   20 px Loop icon at +2, +4; the name 12/16 semibold #424242 at +30);
// - compose: a line, then the link's description (12 #424242, a button
//   that opens the link's settings), and Discard (a 32 x 31.3 trash
//   button 18 from the right);
// - a message: Shared locations, Copy component and See who has access
//   (32 x 31.3, 20 px #616161 glyphs), the last 18 from the right.
// The component itself is Loop's own (LoopPage, docs/spec/loop-host.md).
Rectangle {
    id: root
    /// "compose" (made here; `conversation` is where) or "message".
    property string mode: "message"
    property string conversation: ""
    /// The component's link (a message's; a compose one once made).
    property string componentUrl: ""
    /// The header's name: the file's (a message), Loop's title as typed
    /// (compose), "Loop paragraph" until then.
    property string name: ""
    /// The link's description (compose).
    property string description: ""
    /// The link is being made (compose).
    property bool linking: false
    readonly property alias page: loop.item
    /// The component is loaded (a compose box sets it while one is in it).
    property bool live: true
    signal discardRequested()
    signal linkSettingsRequested()
    signal created(var info)
    signal titleChanged(string title)
    width: 616.7; height: 372
    radius: 12
    color: theme.pick("#FFFFFF", "#292929", "#000000")
    border.width: 0.67
    border.color: focusInside ? theme.brand : theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
    // Teams' Loop glow (loopGlowBorderEnabled) while the component has the
    // keyboard: a brand edge.
    readonly property bool focusInside: loop.item ? loop.item.activeFocus || loopFocus.activeFocus : false
    FocusScope { id: loopFocus }

    Item {
        id: header
        width: parent.width; height: 48
        Rectangle {
            id: nameButton
            x: 22; y: 12; height: 28
            width: Math.min(nameRow.implicitWidth + 6, header.width - 22 - (root.mode === "compose" ? 60 : 130))
            radius: 4
            color: nameHover.hovered ? theme.rowHover : "transparent"
            Row {
                id: nameRow
                x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Image { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "../assets/icons/ft-loop-20.svg" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, nameButton.width - 34)
                    elide: Text.ElideRight
                    text: root.name || qsTr("Loop paragraph")
                    lineHeight: 16; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.pick("#424242", "#D6D6D6", "#FFFFFF")
                }
            }
            HoverHandler { id: nameHover; cursorShape: Qt.PointingHandCursor }
            // Teams opens the component in Loop (the browser here).
            TapHandler { onTapped: if (root.componentUrl) Qt.openUrlExternally(root.componentUrl) }
            Accessible.role: Accessible.Button
            Accessible.name: root.name || qsTr("Loop paragraph")
        }
        // Compose: the link's description after a line.
        Rectangle {
            visible: root.mode === "compose" && (root.description || root.linking)
            x: nameButton.x + nameButton.width + 8; y: 16; width: 0.67; height: 20
            color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
        }
        Text {
            id: desc
            visible: root.mode === "compose"
            x: nameButton.x + nameButton.width + 16.7; y: 13.3
            width: Math.min(implicitWidth, header.width - x - 60)
            elide: Text.ElideRight
            text: root.linking ? qsTr("Updating link settings...") : root.description
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 12; font.underline: descHover.hovered
            color: descHover.hovered ? theme.pick("#4F52B2", "#7F85F5", "#FFFF00") : theme.pick("#424242", "#D6D6D6", "#FFFFFF")
            HoverHandler { id: descHover; enabled: !!root.description && !root.linking; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !!root.description && !root.linking; onTapped: root.linkSettingsRequested() }
            Accessible.role: Accessible.Button
            Accessible.name: text
        }
        Row {
            anchors { right: parent.right; rightMargin: 18 }
            y: root.mode === "compose" ? 10.4 : 10.3
            HeaderButton { visible: root.mode === "compose"; icon: "delete-20"; tip: qsTr("Discard"); onClicked: root.discardRequested() }
            HeaderButton { visible: root.mode === "message"; icon: "apps"; tip: qsTr("Shared locations"); onClicked: locations.open() }
            HeaderButton { visible: root.mode === "message"; icon: "select-object-20"; tip: qsTr("Copy component"); onClicked: { copier.text = root.componentUrl; copier.selectAll(); copier.copy() } }
            HeaderButton { visible: root.mode === "message"; icon: "people-checkmark-20"; tip: qsTr("See who has access"); onClicked: if (root.componentUrl) Qt.openUrlExternally(root.componentUrl) }
        }
        TextEdit { id: copier; visible: false }
        Popup {
            id: locations
            x: parent.width - width - 16; y: parent.height
            padding: 12
            background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
            contentItem: Text { text: qsTr("Shared locations"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
        }
    }
    Loader {
        id: loop
        x: 2.67; y: 50.7
        width: parent.width - 5.33; height: 320
        // Only while shown (a compose box keeps its card hidden until a
        // component is inserted).
        active: root.live && (root.mode === "compose" || root.componentUrl.length > 0)
        sourceComponent: LoopPage {
            kind: root.mode
            create: root.mode === "compose"
            channel: root.conversation
            componentUrl: root.mode === "compose" ? "" : root.componentUrl
            onCreated: url => root.created(createdInfo)
            onComponentTitleChanged: root.titleChanged(componentTitle)
        }
    }
    // Loop's loading indicator while the component isn't drawn.
    BusyIndicator {
        anchors.centerIn: loop
        running: !loop.item || loop.item.state_ === "loading"
        visible: running
    }
    Text {
        visible: !!loop.item && loop.item.state_ === "error"
        anchors.centerIn: loop
        width: loop.width - 40
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        text: qsTr("This Loop component is temporarily not available.")
        font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Loop component")

    component HeaderButton: Rectangle {
        id: hb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31.3; radius: 4
        color: hbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: hb.icon; size: 20; color: theme.onFill(hb, theme.pick("#616161", "#ADADAD", "#FFFFFF")) }
        HoverHandler { id: hbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hb.clicked() }
        ToolTip.visible: hbh.hovered
        ToolTip.text: hb.tip
        ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: hb.tip
    }
}
