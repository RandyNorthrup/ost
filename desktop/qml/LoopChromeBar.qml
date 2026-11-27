import QtQuick
import QtQuick.Controls.Basic

// The header Teams' bundled Loop control draws over a Loop component it
// hosts (Teams 26304, 698099; measured on winpc 2026-11-21 over the recap
// Notes of OST TEST 240 recap meeting): the Loop icon and the component's
// name as a button (12/16 semibold #424242, the 20 px icon 2 in, the name
// 8 after it; it opens the component), and at the right three 32 x 31.3
// buttons with 20 px #616161 glyphs:
// - Shared locations: a 280-wide callout below it (radius 8, padding 4,
//   kept inside the window): "Shared locations for" (12/600) over the
//   component's name as a link, a #FAFAFA band "Open component in" with the
//   places it was shared to (Teams' sharedlocations service), and "Add to
//   Loop workspace", which opens Loop's page for it in the browser.
// - Copy component: copies its link.
// - See who has access: LoopAccessPopover.
Item {
    id: root
    /// The component's name and its link.
    property string title: ""
    property string link: ""
    /// The component's app icon (LoopPage.iconUrl / iconState).
    property string iconUrl: ""
    property string iconState: "pending"
    onIconUrlChanged: appIcon.loadFailed = false
    /// Teams' own Loop glyphs (assets/icons/loop-commanding.json) by name.
    function loopGlyph(name, color) {
        const k = "loop-commanding-icons"
        let m = IconCache.get(k)
        if (m === undefined) {
            const x = new XMLHttpRequest()
            x.open("GET", Qt.resolvedUrl("../assets/icons/loop-commanding.json"), false)
            x.send()
            try { m = JSON.parse(x.responseText) } catch (e) { m = {} }
            IconCache.put(k, m)
        }
        const svg = m[name]
        return svg ? "data:image/svg+xml;utf8," + encodeURIComponent(svg.replace(/#212121/g, color.toString())) : ""
    }
    implicitHeight: 31.3
    readonly property string tag: "loopchrome" + Math.floor(Math.random() * 1e9) + ":"
    property var places: null
    property string workspaceUrl: ""
    function stateForTest() {
        return { shown: visible && title !== "", title: title, icon: appIcon.shown, iconUrl: iconUrl.split("?")[0], buttons: [locationsButton.tip, copyButton.tip, accessButton.tip], places: places, workspace: workspaceUrl !== "" }
    }
    function openLocations() {
        locations.open()
        if (places === null) backend.eventsRequest("loopPlaces", tag + "places", JSON.stringify({ url: link }))
    }
    /// Read the component's name from its file (when `title` isn't given).
    property bool readName: false
    onLinkChanged: if (readName && link) backend.loopHostRequest("pageName", tag + "name", JSON.stringify({ url: link }))
    Component.onCompleted: if (readName && link) backend.loopHostRequest("pageName", tag + "name", JSON.stringify({ url: link }))
    Connections {
        target: backend
        function onLoopHostReply(id, json) {
            if (id !== root.tag + "name") return
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            if (r.name) root.title = r.name
        }
        function onEventsReply(id, json) {
            if (id !== root.tag + "places") return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            root.places = v.places || []
            root.workspaceUrl = v.workspace || ""
            console.info("LOOPCHROME places", root.places.length)
        }
    }
    // Teams' fallback title for a chat without a subject.
    function placeTitle(p) {
        if (p.title) return p.title
        if (p.host === "Outlook") return qsTr("(no subject)")
        const n = (p.participants || []).slice().sort((a, b) => a.localeCompare(b))
        if (n.length === 0) return p.self ? qsTr("%1 (You)").arg(p.self) : ""
        if (n.length === 1) return n[0]
        if (n.length === 2) return qsTr("%1 and %2").arg(n[0]).arg(n[1])
        if (n.length === 3) return qsTr("%1, %2, and %3").arg(n[0]).arg(n[1]).arg(n[2])
        return qsTr("%1, %2, +%3").arg(n[0]).arg(n[1]).arg(n.length - 2)
    }
    function placeSubtitle(p) {
        const where = { "Teams/Chat": qsTr("%1 / Chat"), "Teams/Channel": qsTr("%1 / Channel"), "Outlook/Email": qsTr("%1 / Email"), "Outlook/Calendar": qsTr("%1 / Calendar"),
                        "Loop/Workspace": qsTr("%1 / Workspace"), "Loop/Page": qsTr("%1 / Page") }[p.host + "/" + p.location]
        if (where) return where.arg(p.host)
        return p.host === "Word" || p.host === "Whiteboard" ? p.host : qsTr("Other location")
    }
    function placeIcon(p) {
        return ({ "Teams/Chat": "chat-20", "Teams/Channel": "people-team-20", "Outlook/Email": "mail-20", "Outlook/Calendar": "calendar-20" })[p.host + "/" + p.location]
            || (p.host === "Loop" ? "loop-page-20" : p.host === "Word" ? "document-20" : "document-20")
    }

    Rectangle {
        id: titleButton
        y: (parent.height - height) / 2
        width: titleRow.implicitWidth + 4; height: 28; radius: 4
        color: titleHover.hovered ? theme.rowHover : "transparent"
        Row {
            id: titleRow
            x: 2; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            // Teams' AppIcon (698099 `z`): a 20 px square skeleton until the
            // component's icon is known (at most 5 s), then its iconUrl
            // (contain-fit), else Loop's logo (FFXLoopIcon); a component that
            // failed or an icon that didn't load gets the Loop outline
            // (FFXLoopOutline) in the disabled colour.
            Item {
                id: appIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                property bool loadFailed: false
                readonly property string shown: root.iconState === "pending" ? "skeleton"
                    : root.iconState === "failed" || loadFailed ? "outline" : root.iconUrl ? "url" : "logo"
                Rectangle {
                    anchors.fill: parent; radius: 4
                    visible: appIcon.shown === "skeleton"
                    color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                    SequentialAnimation on opacity { running: parent.visible; loops: Animation.Infinite; NumberAnimation { to: 0.4; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
                }
                Image {
                    anchors.fill: parent; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(40, 40)
                    visible: appIcon.shown === "url"
                    source: root.iconUrl
                    onStatusChanged: if (status === Image.Error && root.iconUrl) { console.info("LOOPCHROME icon didn't load"); appIcon.loadFailed = true }
                }
                Image {
                    anchors.fill: parent; sourceSize: Qt.size(40, 40)
                    visible: appIcon.shown === "logo" || appIcon.shown === "outline"
                    source: visible ? root.loopGlyph(appIcon.shown === "logo" ? "FFXLoopIcon" : "FFXLoopOutline", theme.disabled) : ""
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width - 140); elide: Text.ElideRight
                text: root.title
                lineHeight: 16; lineHeightMode: Text.FixedHeight
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(titleButton, theme.textStrong)
            }
        }
        HoverHandler { id: titleHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (root.link) backend.openExternal(root.link) }
        Accessible.role: Accessible.Button
        Accessible.name: root.title
    }
    Row {
        anchors.right: parent.right
        y: (parent.height - 31.3) / 2
        ChromeButton { id: locationsButton; icon: locations.opened ? "apps-20-filled" : "apps-20"; tip: qsTr("Shared locations"); onClicked: locations.opened ? locations.close() : root.openLocations() }
        ChromeButton { id: copyButton; icon: "select-object-20"; tip: qsTr("Copy component"); onClicked: { copier.text = root.link; copier.selectAll(); copier.copy() } }
        ChromeButton { id: accessButton; icon: "people-checkmark-20"; tip: qsTr("See who has access"); onClicked: if (root.link) accessPop.openFor(this, root.link) }
    }
    TextEdit { id: copier; visible: false }
    LoopAccessPopover { id: accessPop }
    Popup {
        id: locations
        parent: locationsButton
        width: 280; padding: 4
        y: locationsButton.height
        // Centred under the button, kept inside the window.
        x: {
            const w = locationsButton.Window.window
            const at = locationsButton.mapToItem(null, 0, 0).x
            const want = (locationsButton.width - width) / 2
            return w ? Math.max(-at, Math.min(want, w.width - at - width)) : want
        }
        background: FluentSurface { depth: 16; radius: 8; color: theme.surface }
        contentItem: Column {
            spacing: 0
            Column {
                width: parent.width; topPadding: 6; bottomPadding: 9.3; leftPadding: 12; rightPadding: 12
                Text { text: qsTr("Shared locations for"); lineHeight: 16; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    width: parent.width - 24; wrapMode: Text.Wrap
                    text: root.title; font.underline: true
                    lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.brandForeground1
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { locations.close(); if (root.link) backend.openExternal(root.link) } }
                    Accessible.role: Accessible.Link; Accessible.name: qsTr("Shared locations for") + " " + root.title
                }
            }
            Rectangle {
                width: parent.width; height: placesColumn.implicitHeight + 8 + 8
                color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
                Column {
                    id: placesColumn
                    y: 4; width: parent.width
                    Text { x: 12; height: 36; verticalAlignment: Text.AlignVCenter; text: qsTr("Open component in"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                    Repeater {
                        model: root.places || []
                        Rectangle {
                            id: place
                            required property var modelData
                            width: placesColumn.width; height: 44; radius: 4
                            color: placeHover.hovered ? theme.rowHover : "transparent"
                            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: root.placeIcon(place.modelData); size: 20; color: theme.onFill(place, theme.textSecondary) }
                            Column {
                                x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56
                                Text { width: parent.width; elide: Text.ElideRight; text: root.placeTitle(place.modelData); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(place, theme.text) }
                                Text { width: parent.width; elide: Text.ElideRight; text: root.placeSubtitle(place.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(place, theme.textSecondary) }
                            }
                            HoverHandler { id: placeHover; cursorShape: place.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler { enabled: !!place.modelData.url; onTapped: { locations.close(); backend.openExternal(place.modelData.url) } }
                            Accessible.role: Accessible.Link; Accessible.name: root.placeTitle(place.modelData)
                        }
                    }
                }
            }
            Item { width: 1; height: 2 }
            Rectangle {
                id: workspaceButton
                visible: root.workspaceUrl !== ""
                width: parent.width; height: 33.3; radius: 6
                color: wsHover.hovered ? theme.rowHover : "transparent"
                Row {
                    x: 12.7; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: wsHover.hovered ? "layer-diagonal-add-20-filled" : "layer-diagonal-add-20"; size: 20; color: wsHover.hovered ? theme.brand : theme.onFill(workspaceButton, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add to %1 workspace").arg("Loop"); font.family: theme.font; font.pixelSize: 14; color: theme.onFill(workspaceButton, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
                }
                HoverHandler { id: wsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { locations.close(); backend.openExternal(root.workspaceUrl) } }
                ToolTip.visible: wsHover.hovered; ToolTip.delay: 500
                ToolTip.text: qsTr("Adding this component will link it to a workspace so you can start organizing and collecting content.")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Add to %1 workspace").arg("Loop")
            }
        }
    }

    component ChromeButton: Rectangle {
        id: cb
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 31.3; radius: 6
        color: cbh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: cb.icon; size: 20; color: theme.onFill(cb, theme.textSecondary) }
        HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.clicked() }
        ToolTip.visible: cbh.hovered; ToolTip.text: tip; ToolTip.delay: 500
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
}
