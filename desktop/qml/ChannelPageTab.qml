import QtQuick
import QtQuick.Controls.Basic

// A channel's Page tab as Teams shows it (measured in Teams on the web,
// 2026-11-16, OST test channel): Teams' header, then the page in Loop's
// own page container (LoopPage, docs/spec/loop-host.md) filling the tab.
// - Header (50 tall, a #E0E0E0 line under it): the page's name as a
//   button (127 x 28 at 19, 10; the 20 px Loop file icon at 21, 14; the
//   name 12/16 semibold #424242 at 49), which opens the page in Loop; on
//   the right, 15 in, three 32 x 32 buttons (20 px #616161 glyphs):
//   Shared locations, Copy component, See who has access.
// - A New page: Loop's page container makes the page in the channel's
//   folder ("Loop paragraph", its page header drawn by Loop) and the tab is
//   pointed at it, as Teams does.
Rectangle {
    id: root
    /// The channel's Page tab (OST's tab: id, name, content_url).
    property var tab: null
    property string channel: ""
    /// Where the page is shared (Shared locations), e.g. "General · Team".
    property string location: ""
    /// Make the page (a New page this OST just added).
    property bool create: false
    color: theme.surface
    readonly property string link: createdUrl || (tab ? tab.content_url || "" : "")
    property string createdUrl: ""
    property string pageName: ""
    readonly property string hostId: "page" + Math.floor(Math.random() * 1e9).toString(36)
    signal pageCreated(string componentUrl)
    function reload() { if (page.item) page.item.reload() }
    function loopForTest() { return page.item }
    function createdForTest() { return page.item ? page.item.createdInfo : null }

    Connections {
        target: backend
        function onLoopHostReply(id, json) {
            if (id === root.hostId + ":name") {
                let r = {}
                try { r = JSON.parse(json) } catch (e) {}
                if (r.name) root.pageName = r.name
            } else if (id === root.hostId + ":save") {
                let r = {}
                try { r = JSON.parse(json) } catch (e) {}
                console.info("LOOPPAGE saved link", !!r.ok, r.error || "")
                if (r.ok) root.pageCreated(root.createdUrl)
            }
        }
    }
    Component.onCompleted: {
        if (create) pageName = "Loop paragraph"
        else if (link) backend.loopHostRequest("pageName", hostId + ":name", JSON.stringify({ url: link }))
    }

    // Teams' header.
    Item {
        id: header
        width: parent.width; height: 50
        Rectangle {
            id: titleButton
            x: 19; y: 10; height: 28
            width: titleRow.implicitWidth + 12
            radius: 4
            color: titleHover.hovered ? theme.rowHover : "transparent"
            Row {
                id: titleRow
                x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Image { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; sourceSize: Qt.size(40, 40); source: "../assets/icons/ft-loop-20.svg" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pageName
                    font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textStrong
                }
            }
            HoverHandler { id: titleHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (root.link) Qt.openUrlExternally(root.link) }
            Accessible.role: Accessible.Button
            Accessible.name: root.pageName
        }
        Row {
            anchors { right: parent.right; rightMargin: 15 }
            y: 8
            PageButton { icon: "apps"; tip: qsTr("Shared locations"); onClicked: locations.open() }
            PageButton { icon: "select-object-20"; tip: qsTr("Copy component"); onClicked: { copier.text = root.link; copier.selectAll(); copier.copy() } }
            PageButton { icon: "people-checkmark-20"; tip: qsTr("See who has access"); onClicked: if (root.link) Qt.openUrlExternally(root.link) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.divider }
        TextEdit { id: copier; visible: false }
        Popup {
            id: locations
            x: parent.width - width - 16; y: parent.height
            padding: 12
            background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
            contentItem: Column {
                spacing: 6
                Text { text: qsTr("Shared locations"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text { text: root.location; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
            }
        }
    }

    Loader {
        id: page
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        active: root.create || root.link.length > 0
        sourceComponent: LoopPage {
            kind: "channelPages"
            create: root.create
            channel: root.channel
            componentUrl: root.create ? "" : root.link
            onCreated: url => {
                root.createdUrl = url
                backend.loopHostRequest("saveComponentUrl", root.hostId + ":save", JSON.stringify({ channel: root.channel, tab: root.tab ? root.tab.id : "", url: url }))
                backend.loopHostRequest("pageName", root.hostId + ":name", JSON.stringify({ url: url }))
            }
        }
    }

    // Teams' loading and error pages while the page isn't drawn.
    Column {
        visible: !page.item || page.item.state_ !== "ready"
        anchors.centerIn: page
        width: Math.min(parent.width - 40, 600)
        readonly property bool error: !!page.item && page.item.state_ === "error"
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 192; height: 192; sourceSize: Qt.size(384, 384)
            source: "../assets/illustrations/" + (parent.error ? "warning" : "workspace") + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: parent.error ? qsTr("This page is temporarily not available.") : qsTr("Give us a moment while we get things ready for you...")
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
        }
        Item { width: 1; height: 12; visible: parent.error }
        Rectangle {
            visible: parent.error
            anchors.horizontalCenter: parent.horizontalCenter
            width: retryText.implicitWidth + 24; height: 32; radius: 4
            color: retryHover.hovered ? theme.brandHover : theme.brandFill
            Text { id: retryText; anchors.centerIn: parent; text: qsTr("Retry"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: retryHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.reload() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Retry")
        }
    }

    component PageButton: Rectangle {
        id: pb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 32; radius: 4
        color: pbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: pb.icon; size: 20; color: theme.onFill(pb, theme.textSecondary) }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.clicked() }
        ToolTip.visible: pbh.hovered; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
}
