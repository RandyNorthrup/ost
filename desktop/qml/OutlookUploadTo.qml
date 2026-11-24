import QtQuick
import QtQuick.Controls.Basic

// Attach ▸ Upload and share: Outlook's "Upload to" (Teams desktop on winpc,
// 2026-11-24, CSS px), a white dialog (radius 8) centred over the page:
// - First 384 x 236.67: "Upload to" 20/600 at 22.67; Close (32) at 341.33,
//   18.67; the place (336 x 56 at 22.67, 78.67, a 0.67 #F0F0F0 edge):
//   OneDrive's cloud and "OneDrive - <organization>" 14/600 #616161 at
//   72.67 over the folder (a 20 px folder glyph, "Attachments" until
//   changed) 26 under it; "Change location" (14, #4F52B2) at 22.67, 146.67;
//   Upload (96 x 31.33, brand) and Cancel at 136.67 and 246.67, 182.67.
// - Change location: 384 x 521.33. "Upload to" 21/600 #616161 at 26.67,
//   22.67; the path at 59.33: "OneDrive - <organization>" (cut to fit) ›
//   "Files" while in Files, else "…" (Parent folders, 32 x 31.33 at 28.67)
//   › its last two folders (the current 14/600; the 7 px chevrons #8A8A8A
//   10 after a name); a 0.67 line at 114.67 over the folders (42 tall from
//   115.33, 340.67 wide: a 20 px folder glyph 12 in, the name 14 #616161
//   at 52; #F5F5F5 hovered), which open on a click; an empty folder says
//   "Upload to your <folder> folder" (#8A8A8A) under Outlook's
//   illustration; a 0.67 line at 406; "Create new folder" (+ 16, 14
//   #444791 at 78.33, 410.67: a 269 x 32 name field with a 0.67 #444791
//   edge while typing, Upload greyed; Enter makes it, Escape leaves it);
//   Upload and Cancel at 148.67 and 258.67, 470.67.
// Upload puts the file in the folder shown (event_form::upload_and_share)
// and its link in the body.
Popup {
    id: dlg
    /// The event page (its calendarCall).
    property var form: null
    property string path: ""
    signal upload(string path, string folderId)
    parent: Overlay.overlay
    modal: true; padding: 0
    x: (parent.width - width) / 2; y: (parent.height - height) / 2
    width: 384; height: browsing ? 521.33 : 236.67
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    /// Change location's view.
    property bool browsing: false
    /// The folders from Files down to the one shown: [{id, name}]
    /// ("root" is Files); empty while the default (Attachments).
    property var trail: []
    readonly property var here: trail.length ? trail[trail.length - 1] : null
    property var folders: ({})
    property bool loadingFolders: false
    property bool naming: false
    property string nameError: ""
    readonly property string orgLabel: qsTr("OneDrive - %1").arg(backend.orgName || qsTr("OneDrive"))
    function openFor(p) { path = p; browsing = false; trail = []; naming = false; nameError = ""; open() }
    function browse(folder) {
        const i = trail.findIndex(f => f.id === folder.id)
        trail = i >= 0 ? trail.slice(0, i + 1) : trail.concat([folder])
        naming = false
        if (!folders[folder.id] && form) { loadingFolders = true; form.calendarCall("driveFolders", { folderId: folder.id }) }
    }
    function changeLocation() { browsing = true; trail = []; browse({ id: "root", name: qsTr("Files") }) }
    function answer(op, r, error) {
        if (op === "driveFolders") {
            loadingFolders = false
            if (error) return
            const f = Object.assign({}, folders); f[r.folderId] = r.folders || []; folders = f
        } else if (op === "createFolder") {
            if (error) { nameError = /in use/.test(error) ? qsTr("This folder name is already in use.") : qsTr("We weren't able to create a new folder. Please try again."); return }
            naming = false; nameError = ""
            const parentId = here ? here.id : "root"
            const f = Object.assign({}, folders); f[parentId] = (f[parentId] || []).concat([{ id: r.id, name: r.name }]).sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1); folders = f
            browse({ id: r.id, name: r.name })
        }
    }
    function createFolder(name) {
        name = name.trim()
        if (!name || !form) { naming = false; return }
        form.calendarCall("createFolder", { parentId: here ? here.id : "root", name: name })
    }
    function doUpload() { upload(path, here ? here.id : ""); close() }

    // ── The first view ──────────────────────────────────────────────
    Item {
        visible: !dlg.browsing
        anchors.fill: parent
        Text { x: 22.67; y: 6.67; height: 72; verticalAlignment: Text.AlignVCenter; text: qsTr("Upload to"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text; Accessible.role: Accessible.Heading }
        Rectangle {
            x: 22.67; y: 78.67; width: 336; height: 56; color: "transparent"; border.width: 0.67; border.color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF")
            FluentIcon { x: 4; y: 12; name: "onedrive-color"; size: 32 }
            Text { x: 50; y: 5; width: 274; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: dlg.orgLabel; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
            FluentIcon { x: 50; y: 31; name: "folder-20"; size: 20; color: theme.textSecondary }
            Text { x: 74; y: 31; width: 250; height: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: dlg.here ? dlg.here.name : qsTr("Attachments"); font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
        }
        Text {
            x: 22.67; y: 146.67; height: 20; verticalAlignment: Text.AlignVCenter
            text: qsTr("Change location"); font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
            font.underline: changeHover.hovered
            HoverHandler { id: changeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: dlg.changeLocation() }
            Accessible.role: Accessible.Button; Accessible.name: text
        }
        UpButton { x: 136.67; y: 182.67; primary: true; label: qsTr("Upload"); onClicked: dlg.doUpload() }
        UpButton { x: 246.67; y: 182.67; label: qsTr("Cancel"); onClicked: dlg.close() }
    }

    // ── Change location ─────────────────────────────────────────────
    Item {
        visible: dlg.browsing
        anchors.fill: parent
        Text { x: 26.67; y: 22.67; width: 328; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Upload to"); font.family: theme.font; font.pixelSize: 21; font.weight: Font.DemiBold; color: theme.textSecondary; Accessible.role: Accessible.Heading }
        // The path.
        Row {
            id: crumbs
            x: dlg.trail.length > 1 ? 28.67 : 27.67; y: dlg.trail.length > 1 ? 59.67 : 59.33; height: 31.33
            spacing: 0
            readonly property var shown: dlg.trail.length > 1 ? dlg.trail.slice(-2) : dlg.trail
            Rectangle {
                visible: dlg.trail.length > 1
                width: 32; height: 31.33; radius: 4; color: parentsHover.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: parentsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: parentsMenu.open() }
                ToolTip.visible: parentsHover.hovered && !parentsMenu.opened
                ToolTip.text: qsTr("Parent folders")
                Accessible.role: Accessible.Button; Accessible.name: qsTr("Parent folders")
                MenuPopup {
                    id: parentsMenu
                    y: parent.height
                    items: [{ label: dlg.orgLabel }].concat(dlg.trail.slice(0, -2).map(f => ({ label: f.name })))
                    onPicked: i => { if (i > 0) dlg.browse(dlg.trail[i - 1]) }
                }
            }
            Item { visible: dlg.trail.length > 1; width: 2; height: 1 }
            Text {
                visible: dlg.trail.length <= 1
                width: Math.min(implicitWidth, 204); height: 18.67; anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight; text: dlg.orgLabel; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            Repeater {
                model: crumbs.shown
                Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    readonly property bool last: index === crumbs.shown.length - 1
                    anchors.verticalCenter: parent.verticalCenter
                    Item { visible: crumb.index > 0 || dlg.trail.length <= 1; width: 24; height: 20
                           FluentIcon { x: 10; y: 4; name: "chevron-right-12"; size: 12; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") } }
                    Text {
                        height: 18.67; text: crumb.modelData.name; font.family: theme.font; font.pixelSize: 14
                        font.weight: crumb.last ? Font.DemiBold : Font.Normal; color: theme.textSecondary
                        HoverHandler { enabled: !crumb.last; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !crumb.last; onTapped: dlg.browse(crumb.modelData) }
                    }
                }
            }
        }
        Rectangle { x: 26.67; y: 114.67; width: 328; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }
        readonly property var list: dlg.here ? (dlg.folders[dlg.here.id] || []) : []
        ListView {
            id: folderList
            x: 26.67; y: 115.33; width: 340.67; height: 290.67
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: parent.list
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: frow
                required property var modelData
                width: 340.67; height: 42
                color: frowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E", "#000000") : theme.surface
                FluentIcon { x: 12; y: 11; name: "folder-20"; size: 20; color: theme.textSecondary }
                Text { x: 52; width: 270; height: 42; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: frow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                HoverHandler { id: frowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.browse(frow.modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: frow.modelData.name
            }
        }
        // An empty folder.
        Item {
            visible: !dlg.loadingFolders && !!dlg.here && !!dlg.folders[dlg.here.id] && parent.list.length === 0
            x: 26.67; y: 115.33; width: 328; height: 290
            Image {
                x: 64; y: 28.33; width: 200; height: 200; fillMode: Image.PreserveAspectFit; asynchronous: true
                source: "https://res.public.onecdn.static.microsoft/owamail/hashed-v1/resources/images/files-hash-5c57d482.h.svg"
                sourceSize: Qt.size(400, 400)
            }
            Text {
                y: 228.33; width: 328; height: 34; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap
                text: qsTr("Upload to your %1 folder").arg(dlg.here ? dlg.here.name : ""); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF")
            }
        }
        Rectangle { x: 26.67; y: 406; width: 328; height: 0.67; color: theme.pick("#F0F0F0", "#3D3D3D", "#FFFFFF") }
        // Create new folder.
        Item {
            x: 26.67; y: 410.67; width: 329.33; height: 35.33
            FluentIcon { x: 10.67; y: 9.67; name: "add-16"; size: 16; color: theme.pick("#444791", "#9EA2FF", "#FFFF00") }
            Text {
                visible: !dlg.naming
                x: 51.67; height: 35.33; verticalAlignment: Text.AlignVCenter
                text: qsTr("Create new folder"); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#444791", "#9EA2FF", "#FFFF00")
            }
            HoverHandler { enabled: !dlg.naming; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !dlg.naming; onTapped: { dlg.naming = true; dlg.nameError = ""; nameInput.text = ""; nameInput.forceActiveFocus() } }
            Accessible.role: Accessible.Button; Accessible.name: qsTr("Create new folder")
            Rectangle {
                visible: dlg.naming
                x: 51.67; y: 1.67; width: 269; height: 32; radius: 2
                color: theme.surface; border.width: 0.67; border.color: theme.pick("#444791", "#9EA2FF", "#FFFF00")
                TextInput {
                    id: nameInput
                    x: 8; width: 253; height: 32; verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    Keys.onReturnPressed: dlg.createFolder(text)
                    Keys.onEnterPressed: dlg.createFolder(text)
                    Keys.onEscapePressed: e => { dlg.naming = false; e.accepted = true }
                    onActiveFocusChanged: if (!activeFocus && dlg.naming && !text.trim()) dlg.naming = false
                    Accessible.name: qsTr("Enter your folder name")
                    Text { visible: !nameInput.text; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Enter your folder name"); font: nameInput.font; color: theme.pick("#8A8A8A", "#ADADAD", "#FFFFFF") }
                }
            }
            Text {
                visible: !!dlg.nameError
                x: 51.67; y: 36; width: 269; wrapMode: Text.Wrap
                text: dlg.nameError; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#C50F1F", "#DC626D", "#FFFF00")
            }
        }
        UpButton { x: 148.67; y: 470.67; primary: true; label: qsTr("Upload"); enabledState: !dlg.naming && !!dlg.here; onClicked: dlg.doUpload() }
        UpButton { x: 258.67; y: 470.67; label: qsTr("Cancel"); onClicked: dlg.close() }
    }
    Rectangle {
        x: 341.33; y: 18.67; width: 32; height: dlg.browsing ? 31.33 : 32; radius: 4; color: closeHover.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }

    // Fluent's buttons as the dialog draws them (96 x 31.33, radius 4;
    // Upload brand, greyed #F0F0F0 / #BDBDBD; Cancel a 0.67 #D1D1D1 edge).
    component UpButton: Rectangle {
        id: ub
        property string label
        property bool primary: false
        property bool enabledState: true
        signal clicked()
        width: 96; height: 31.33; radius: 4
        color: !enabledState ? theme.pick("#F0F0F0", "#2E2E2E", "#000000") : primary ? (ubh.hovered ? theme.brandHover : theme.brandFill) : (ubh.hovered ? theme.rowHover : theme.surface)
        border.width: 0.67; border.color: primary || !enabledState ? "transparent" : theme.stroke
        Text { anchors.centerIn: parent; text: ub.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !ub.enabledState ? theme.disabled : ub.primary ? "white" : theme.text }
        HoverHandler { id: ubh; enabled: ub.enabledState; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: ub.enabledState; onTapped: ub.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ub.label
    }
}
