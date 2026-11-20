import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Teams' "Manage your apps" (the Store header's gear; measured on winpc
// 2026-11-20, CSS px from the area right of the app bar):
// - Back (32 x 31.3, a 20 px arrow) at (12, 14.8); the entity header from
//   52: a 32 px brand tile with a white gear (radius 4) at 14.2, "Manage
//   your apps" (18/24 bold) at 92, and the "Apps" tab (14/20 semibold, a
//   brand underline) after it; a hairline under the header (61).
// - The toolbar at 73.7: "Get more apps" (outline, 140.8 x 32, a 20 px
//   plus) at 20, "Upload an app" (transparent, an 18 px upload arrow) at
//   175.8; at the right Sort (96 x 32, a 20 px sort arrow) and "Find by
//   name" (210 x 32, #FAFAFA, radius 3, a 20 px search icon at its end).
// - The list from 117.7: each app a 65 tall row with a #D1D1D1 hairline
//   above it, inset 1: a 14 px caret at 41, the 36 px round icon at 63,
//   the name (14/20 bold) at 106 and the publisher (14/16 #616161) under
//   it, and "More options" (···) at 1119.7 (View details, Copy link).
//   Expanded: "Recently used" (12/16) with its info button at 90, then
//   "Personal app" (the 20 px icon) and each team (its 24 px tile), each
//   with Remove (a 20 px bin) at the right.
// - Sort: Recently used, A-Z, Z-A (a 160 wide menu, the check 6 in).
// Upload an app opens "Upload an app" (600 wide): Submit an app to your org.
Item {
    id: root
    signal back()
    signal getMoreApps()
    signal viewDetails(string appId)
    signal toast(var data)
    property string sort: "recent"
    property var apps: []
    property bool loading: false
    property string error: ""
    property var expanded: ({})
    readonly property string call: "manage:" + Math.floor(Math.random() * 1e9).toString(36)
    readonly property string query: findBox.text.trim().toLowerCase()
    readonly property var shown: apps.filter(a => !query || a.name.toLowerCase().indexOf(query) >= 0)

    function load() {
        loading = true; error = ""
        backend.storeRequest("manageApps", call, JSON.stringify({ sort: sort }))
    }
    onSortChanged: load()
    Connections {
        target: backend
        function onStoreReply(id, json) {
            if (id === root.call) {
                const r = JSON.parse(json)
                root.loading = false
                if (r.error) root.error = r.error
                else root.apps = r.apps
            } else if (id === root.call + ":rm") {
                const r = JSON.parse(json)
                if (r.error) root.toast({ text: qsTr("We couldn't remove the app. Please try again."), intent: "error" })
                root.load()
            }
        }
    }
    Rectangle { anchors.fill: parent; color: theme.surface }

    // Header.
    Rectangle {
        id: backBtn
        x: 12; y: 14.8; width: 32; height: 31.3; radius: 4
        color: backHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "arrow-left-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.back() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Back")
    }
    Rectangle {
        x: 52; y: 14.2; width: 32; height: 32; radius: 4; color: theme.brandFill
        FluentIcon { anchors.centerIn: parent; name: "settings-20-filled"; size: 20; color: theme.textOnBrand }
    }
    Text { x: 92; y: 17.2; height: 24; verticalAlignment: Text.AlignVCenter; text: qsTr("Manage your apps"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
    Item {
        x: 260.8; y: 2; width: 48.3; height: 56.3
        Text { anchors.centerIn: parent; text: qsTr("Apps"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        Rectangle { anchors.bottom: parent.bottom; x: 8; width: parent.width - 16; height: 3; radius: 1.5; color: theme.brand }
        Accessible.role: Accessible.PageTab; Accessible.name: qsTr("Apps"); Accessible.selected: true
    }
    Rectangle { y: 60.3; width: parent.width; height: 0.67; color: theme.divider }

    // Toolbar.
    StoreButton { x: 20; y: 73.7; height: 32; label: qsTr("Get more apps"); icon: "add-20"; onClicked: root.getMoreApps() }
    Rectangle {
        id: uploadBtn
        x: 175.8; y: 73.7; width: uploadRow.implicitWidth + 24; height: 32; radius: 4
        color: uploadHover.hovered ? theme.menuHover : "transparent"
        Row { id: uploadRow; anchors.centerIn: parent; spacing: 8; FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-upload-20"; size: 18; color: theme.textStrong } Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Upload an app"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong } }
        HoverHandler { id: uploadHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: uploadDialog.open() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Upload an app")
    }
    Rectangle {
        id: sortBtn
        x: parent.width - 341; y: 73.7; width: 96; height: 32; radius: 4
        color: sortHover.hovered || sortMenu.opened ? theme.menuHover : "transparent"
        Row { anchors.centerIn: parent; spacing: 8; FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-sort-20"; size: 20; color: sortMenu.opened ? theme.brand : theme.textStrong } Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Sort"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: sortMenu.opened ? theme.brand : theme.textStrong } }
        HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { sortMenu.parent = sortBtn; sortMenu.y = sortBtn.height + 2; sortMenu.open() } }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Sort")
        MenuPopup {
            id: sortMenu
            readonly property var keys: ["recent", "az", "za"]
            labelInset: 26
            items: [qsTr("Recently used"), qsTr("A-Z"), qsTr("Z-A")].map((l, i) => ({ label: l, icon: sortMenu.keys[i] === root.sort ? "checkmark-16" : "" }))
            onPicked: i => root.sort = keys[i]
        }
    }
    Rectangle {
        x: parent.width - 230; y: 73.7; width: 210; height: 32; radius: 3
        color: theme.pick("#FAFAFA", "#1F1F1F", "#000000")
        TextInput {
            id: findBox
            x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
            Text { visible: !findBox.text; text: qsTr("Find by name"); font: findBox.font; color: theme.textSecondary }
            Keys.onEscapePressed: text = ""
            Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Find by name")
        }
        FluentIcon { anchors.right: parent.right; anchors.rightMargin: 10.7; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textStrong }
    }

    // The list.
    ListView {
        id: list
        x: 0; y: 117.7; width: parent.width; height: parent.height - y
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        model: root.shown
        Accessible.role: Accessible.Tree; Accessible.name: qsTr("Installed apps")
        delegate: Column {
            id: entry
            required property var modelData
            readonly property bool open: !!root.expanded[modelData.id]
            width: list.width - 16
            Item {
                id: rowItem
                width: parent.width; height: 65
                Rectangle { x: 1; width: parent.width; height: 0.67; color: theme.stroke }
                Rectangle { anchors.fill: parent; anchors.leftMargin: 1; color: rowHover.hovered ? theme.rowHover : "transparent" }
                FluentIcon { x: 41; y: 25; name: entry.open ? "caret-down-12-filled" : "caret-right-12-filled"; size: 14; color: theme.textStrong }
                Item {
                    x: 63; y: 13.6; width: 36; height: 36
                    Rectangle { anchors.fill: parent; radius: 18; color: theme.pick("#FAFAFA", "#292929", "#000000") }
                    Image { anchors.fill: parent; source: entry.modelData.icon || ""; sourceSize: Qt.size(72, 72); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true }
                    RoundedCorners { anchors.fill: parent; radius: 18; background: rowHover.hovered ? theme.rowHover : theme.surface }
                }
                Text { x: 106; y: 15.6; height: 20; verticalAlignment: Text.AlignVCenter; text: entry.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                Text { x: 106; y: 35.6; height: 16; verticalAlignment: Text.AlignVCenter; text: entry.modelData.developer; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                HoverHandler { id: rowHover }
                TapHandler {
                    onTapped: { const e = Object.assign({}, root.expanded); e[entry.modelData.id] = !entry.open; root.expanded = e }
                }
                Rectangle {
                    id: moreBtn
                    x: 1119.7 * parent.width / 1196; y: 24.6; width: 31.3; height: 16; radius: 4
                    color: moreHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                    HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { rowMenu.parent = moreBtn; rowMenu.y = moreBtn.height + 4; rowMenu.x = moreBtn.width - 129; rowMenu.open() } }
                    Accessible.role: Accessible.Button; Accessible.name: qsTr("More options")
                    MenuPopup {
                        id: rowMenu
                        items: [{ label: qsTr("View details"), icon: "apps-20" }].concat(entry.modelData.shared ? [] : [{ label: qsTr("Copy link"), icon: "link-20" }])
                        onPicked: i => {
                            if (i === 0) root.viewDetails(entry.modelData.id)
                            else { backend.copyText(entry.modelData.link); root.toast({ text: qsTr("Link copied") }) }
                        }
                    }
                }
                Accessible.role: Accessible.TreeItem; Accessible.name: entry.modelData.name
            }
            Column {
                visible: entry.open
                width: parent.width
                Rectangle { x: 1; width: parent.width; height: 0.67; color: theme.stroke }
                Item {
                    width: parent.width; height: 52
                    Row {
                        x: 90; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Recently used"); font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        Item {
                            width: 20; height: 20
                            FluentIcon { anchors.centerIn: parent; name: "info-12"; size: 12; color: theme.textStrong }
                            HoverHandler { id: infoHover }
                            ToolTip.visible: infoHover.hovered; ToolTip.delay: 300
                            ToolTip.text: qsTr("Shows where the app was recently used, except for chats and meetings.")
                        }
                    }
                }
                Repeater {
                    model: (entry.modelData.personal ? [{ thread: "", name: qsTr("Personal app"), personal: true }] : []).concat(entry.modelData.teams)
                    Item {
                        id: place
                        required property var modelData
                        width: entry.width; height: 49.3
                        Avatar {
                            visible: !place.modelData.personal
                            x: 90; anchors.verticalCenter: parent.verticalCenter; size: 24; square: true
                            name: place.modelData.name
                            initialsText: place.modelData.name.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        }
                        Image { visible: !!place.modelData.personal; x: 90; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: entry.modelData.icon || ""; sourceSize: Qt.size(40, 40); smooth: true }
                        Text { x: place.modelData.personal ? 118 : 122; anchors.verticalCenter: parent.verticalCenter; text: place.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Rectangle {
                            id: rmBtn
                            x: parent.width - 52.3; anchors.verticalCenter: parent.verticalCenter; width: 21.3; height: 21.3; radius: 4
                            color: rmHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "delete-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: removeDialog.start(entry.modelData, place.modelData) }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Remove")
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: root.loading && root.apps.length === 0
        x: 20; y: 140; text: qsTr("Loading…"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
    }
    Text {
        visible: !!root.error
        x: 20; y: 140; text: root.error; font.family: theme.font; font.pixelSize: 14; color: theme.redForeground3
    }

    // Remove: Teams asks first.
    ConfirmDialog {
        id: removeDialog
        property var app: null
        property var place: null
        function start(a, p) {
            app = a; place = p
            title = qsTr("Remove %1?").arg(a.name)
            body = qsTr("Are you sure you want to remove %1?").arg(a.name)
            open()
        }
        confirmText: qsTr("Remove")
        onConfirmed: backend.storeRequest("uninstall", root.call + ":rm", JSON.stringify({ app: app.id, thread: place.thread || "" }))
    }

    // Upload an app (measured: 600 x 216.7, padding 24.7, "Upload an app"
    // 20/28 semibold, Close; one 536 x 96 card: Submit an app to your org).
    Popup {
        id: uploadDialog
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 600; height: 216.7; padding: 0
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.hc("#66000000", "#000000") }
        Text { x: 24.7; y: 24.7; height: 31.3; verticalAlignment: Text.AlignVCenter; text: qsTr("Upload an app"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Rectangle {
            id: upClose
            x: 543.3; y: 24.7; width: 32; height: 31.3; radius: 4
            color: upCloseHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: upCloseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: uploadDialog.close() }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
        }
        Item {
            x: 32; y: 88; width: 536; height: 96
            FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: subHover.hovered ? theme.menuHover : theme.surface; borderColor: theme.stroke }
            Rectangle {
                x: 20.7; y: 16; width: 64; height: 64; radius: 4; color: theme.pick("#E8EBFA", "#2B2B40", "#000000")
                FluentIcon { anchors.centerIn: parent; name: "arrow-upload-20"; size: 40; color: theme.brandForeground1 }
            }
            Text { x: 116.7; y: 18; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Submit an app to your org"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
            Text { x: 116.7; y: 46; width: 398.7; wrapMode: Text.Wrap; lineHeight: 16; lineHeightMode: Text.FixedHeight; text: qsTr("Submit an app to your IT admin for approval and check the status of your submissions."); font.family: theme.font; font.pixelSize: 12; font.weight: Font.Light; color: theme.text }
            HoverHandler { id: subHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { uploadDialog.close(); root.submitApp() } }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Submit an app to your org")
        }
    }
    /// Submit an app to your org: Teams picks the app package (.zip) and
    /// hands it to your admin for approval (api::manage_apps::submit_app).
    function submitApp() { packagePicker.open() }
    FileDialog {
        id: packagePicker
        title: qsTr("Upload an app")
        nameFilters: ["*.zip"]
        onAccepted: backend.storeRequest("submitApp", root.call + ":submit", JSON.stringify({ file: selectedFile.toString() }))
    }
    Connections {
        target: backend
        function onStoreReply(id, json) {
            if (id !== root.call + ":submit") return
            const r = JSON.parse(json)
            root.toast(r.error ? { text: r.error, intent: "error" } : { text: qsTr("Your app was submitted to your IT admin for approval.") })
        }
    }

    function rowsForTest() { return root.shown.map(a => a.name) }
    function expandForTest(name) { const a = root.apps.find(x => x.name === name); if (!a) return false; const e = Object.assign({}, root.expanded); e[a.id] = true; root.expanded = e; return true }
    function sortMenuForTest() { sortMenu.parent = sortBtn; sortMenu.y = sortBtn.height + 2; sortMenu.open() }
    function uploadForTest() { uploadDialog.open() }
    function closeAllForTest() { sortMenu.close(); uploadDialog.close() }
}
