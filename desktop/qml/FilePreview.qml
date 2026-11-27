import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Pdf

// Teams' file Preview (OneDrive's viewer, docs/spec/file-preview.md): over
// the whole view, a rgba(0,0,0,.4) backdrop under a rgba(31,31,31,.88)
// layer; a 48 tall bar (Download, Favorite, Delete | Details, ···; the
// name; Open ▾, Share ▾, Close); the file: text on a white page (75% wide,
// a 30 px name strip, line numbers), a picture, or PDF pages (Office files
// converted by Graph) with "PAGE n OF m" and the zoom; Previous / Next.
Item {
    id: root
    visible: !!item
    /// The file shown, and the list it steps through.
    property var item: null
    property var siblings: []
    property var actions: null
    property var favoriteIds: []
    property var preview: null
    property bool loading: false
    property string error: ""
    signal favorite(var item, bool on)
    signal download(var item)
    signal details(var item)
    readonly property string tag: "pv" + Math.floor(Math.random() * 1e9) + ":"
    readonly property color ink: theme.hc("#F3F2F1", "#FFFFFF")
    readonly property var files: siblings.filter(i => !i.is_folder)
    readonly property int at: item ? files.findIndex(i => i.id === item.id) : -1
    readonly property bool fav: !!item && favoriteIds.indexOf(item.id) >= 0

    function show(it, list) { siblings = list || []; item = it }
    function close() { item = null; preview = null; commentsOpen = false }
    function step(d) { const n = at + d; if (n >= 0 && n < files.length) item = files[n] }
    onItemChanged: {
        preview = null; error = ""
        if (!item) return
        loading = true
        backend.driveAction(tag + "preview", JSON.stringify(item), "{}")
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, err) {
            if (op !== root.tag + "preview") return
            root.loading = false
            root.error = err || ""
            root.preview = err ? null : JSON.parse(result)
        }
    }

    Rectangle { id: hcFill2; anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4) }
    Rectangle { id: hcFill1; anchors.fill: parent; color: Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: ev => ev.accepted = true }
    focus: visible
    Keys.onEscapePressed: if (commentsOpen) commentsOpen = false; else close()
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)

    // The content
    PreviewBody {
        id: body
        x: 0; y: 45; width: parent.width - (root.commentsOpen ? 378 : 0); height: parent.height - 45
        preview: root.preview
        name: root.item ? root.item.name : ""
        kind: root.item ? root.item.kind : ""
        loading: root.loading
        error: root.error
        iconName: root.item ? root.fileIcon(root.item.kind) : ""
        appIconName: root.appIcon()
        ink: root.ink
    }

    // Previous / Next: 40 px circles at the edges, halfway down.
    component Arrow: Rectangle {
        id: ar
        property bool next: false
        width: 40; height: 40; radius: 20
        color: arh.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88)
        border.width: 0.67; border.color: theme.hc("#808080", "#FFFFFF")
        FluentIcon { anchors.centerIn: parent; size: 16; name: ar.next ? "chevron-right-16" : "chevron-left-16"; color: theme.onFill(ar, theme.hc("#7F85F5", "#FFFFFF")) }
        HoverHandler { id: arh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.step(ar.next ? 1 : -1) }
        ToolTip.visible: arh.hovered
        ToolTip.text: next ? qsTr("Next") : qsTr("Previous")
        Accessible.role: Accessible.Button
        Accessible.name: next ? qsTr("Next") : qsTr("Previous")
    }
    Arrow { visible: root.at > 0; x: 12; y: parent.height / 2 - 20 }
    Arrow { visible: root.at >= 0 && root.at < root.files.length - 1; next: true; x: body.width - 52; y: parent.height / 2 - 20 }

    component BarIcon: Rectangle {
        id: bi
        property string icon
        property string tip
        signal clicked()
        width: 32; height: 40; radius: 6
        color: bih.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: bi.icon; color: theme.onFill(bi, theme.hc("#0078D4", "#FFFFFF")) }
        HoverHandler { id: bih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bi.clicked() }
        ToolTip.visible: bih.hovered
        ToolTip.text: tip
        Accessible.role: Accessible.Button
        Accessible.name: tip
    }
    component BarButton: Rectangle {
        id: bb
        property string label
        property string icon
        signal clicked()
        height: 32; radius: 6
        width: 12 + 16 + 8 + bbt.implicitWidth + 8 + 12 + 12
        color: bbh.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88)
        border.width: 0.67; border.color: theme.hc("#808080", "#FFFFFF")
        FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: bb.icon; color: theme.onFill(bb, bb.icon.startsWith("ft-") ? theme.hc("#212121", "#FFFFFF") : theme.hc("#0078D4", "#FFFFFF")) }
        Text { id: bbt; x: 36; anchors.verticalCenter: parent.verticalCenter; text: bb.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(bb, theme.hc("#0078D4", "#FFFFFF")) }
        FluentIcon { x: bbt.x + bbt.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "chevron-down-12"; color: theme.onFill(bb, "#FFFFFF") }
        HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // The bar (measured on winpc 2026-11-19, TASK-0190). Glyphs and the
    // buttons' labels are #0078D4, the chevrons white.
    // - Left, 32 x 40 each from 10, 36 apart: Download, Favorite, Delete, a
    //   divider (24), Info (32 x 32) and ···. As the view narrows they fold
    //   into ··· from the end: Info under 796, Delete under 760, Favorite
    //   under 724, Download under 688.
    // - The name (16 px) centred between the left group and the right one,
    //   60 clear of each.
    // - Right: your picture, Show comments (32), Open ▾ and Share ▾ (12
    //   apart), Close (32 x 40) 14 from the edge.
    // - 640 and narrower: the name from 8 (W - 210 wide), then ···, Share ▾
    //   and Close; ··· also holds Show comments and Open ▸.
    readonly property bool narrow: width <= 640
    readonly property var leftKeys: ["download", "favorite"].concat(actions && actions.canWrite ? ["delete"] : []).concat(["info"])
    readonly property int leftShown: narrow ? 0 : Math.max(0, Math.min(leftKeys.length, Math.floor((width - 654) / 36)))
    readonly property bool dividerShown: !narrow && leftShown === leftKeys.length
    property bool commentsOpen: false
    onCommentsOpenChanged: if (commentsOpen) comments.load()
    function leftItem(k) {
        return ({ download: { label: qsTr("Download"), icon: "arrow-download-16" }, favorite: { label: qsTr("Favorite"), icon: fav ? "star-16-filled" : "star-16" },
                  delete: { label: qsTr("Delete"), icon: "delete-16" }, info: { label: qsTr("Info"), icon: "info-16" } })[k]
    }
    function doLeft(k) {
        const it = root.item
        if (k === "download") root.download(it)
        else if (k === "favorite") root.favorite(it, !root.fav)
        else if (k === "delete") { root.close(); root.actions.item = it; root.actions.act("Delete") }
        else if (k === "info") { root.close(); root.details(it) }
    }
    /// ···: the folded left items, then Copy to, Embed, Version history and
    /// Help ▸ (Send feedback, View tutorial); narrow, also Show comments (a
    /// glyph only, as Teams draws it) and Open ▸.
    readonly property var moreItems: {
        const L = leftKeys.slice(leftShown).map(k => leftItem(k))
        if (item && item.sp_item) L.push({ label: qsTr("Copy to"), icon: "copy-16" })
        L.push({ label: qsTr("Embed"), icon: "code-16" })
        if (item && item.sp_item) L.push({ label: qsTr("Version history"), icon: "history-16" })
        L.push({ label: qsTr("Help"), submenu: [{ label: qsTr("Send feedback") }, { label: qsTr("View tutorial") }] })
        if (narrow) {
            L.push({ label: "", icon: "comment-16", key: "comments" })
            const open = actions && item ? actions.itemsFor(item)[0].submenu || [] : []
            if (open.length) L.push({ label: qsTr("Open"), icon: "open-16", submenu: open })
        }
        return L
    }
    function moreAct(i, j) {
        const m = moreItems[i]
        if (!m) return
        if (m.key === "comments") { commentsOpen = !commentsOpen; return }
        const lk = leftKeys.slice(leftShown)
        if (i < lk.length) { doLeft(lk[i]); return }
        if (m.label === qsTr("Embed")) { embed.open(); return }
        if (m.label === qsTr("Help")) {
            if (j === 0) backend.requestFeedback("problem", "Files", "Preview: " + (item ? item.name : ""))
            else backend.openExternal("https://support.microsoft.com/office/preview-files-in-onedrive-for-work-or-school-d0b7cc7a-ba2d-4ae4-b0fc-bce2bdd2c3e2")
            return
        }
        if (m.label === qsTr("Open") && j !== undefined) { actions.item = item; actions.act(m.submenu[j].label); return }
        actions.item = item
        actions.act(m.label)
    }
    Item {
        id: bar
        width: parent.width; height: 48
        readonly property color glyph: theme.hc("#0078D4", "#FFFFFF")
        Repeater {
            model: root.leftKeys.slice(0, root.leftShown)
            BarIcon {
                required property string modelData
                required property int index
                x: 10 + 36 * index + (root.dividerShown && modelData === "info" ? 24 : 0)
                y: modelData === "info" ? 8 : 4; height: modelData === "info" ? 32 : 40
                icon: ({ download: "arrow-download-20", favorite: root.fav ? "star-20-filled" : "star-20", delete: "delete-20", info: "info-20" })[modelData]
                tip: ({ download: qsTr("Download this file to your device"), favorite: root.fav ? qsTr("Unfavorite this file") : qsTr("Favorite this file"),
                        delete: qsTr("Delete this file"), info: qsTr("Info, View file details") })[modelData]
                onClicked: root.doLeft(modelData)
            }
        }
        Rectangle { visible: root.dividerShown; x: 10 + 36 * (root.leftShown - 1) + 11.5; y: 14; width: 1; height: 20; color: theme.hc("#F3F2F1", "#FFFFFF") }
        BarIcon {
            id: moreIcon
            x: root.narrow ? shareButton.x - 8 - 32 : 10 + 36 * root.leftShown + (root.dividerShown ? 24 : 0); y: 4
            icon: "more-horizontal-20"; tip: qsTr("More")
            onClicked: moreMenu.open()
            MenuPopup {
                id: moreMenu
                fabric: true; darkCallout: true; fabricWidth: 180
                y: parent.height
                items: root.moreItems
                onPicked: i => { if (!root.moreItems[i].submenu) root.moreAct(i) }
                onSubPicked: (i, j) => root.moreAct(i, j)
            }
        }
        // The name: centred between the groups (60 clear), or from 8 when narrow.
        Item {
            id: titleBox
            readonly property real leftEnd: moreIcon.x + 32 + 60
            readonly property real rightStart: avatar.x - 3 - 60
            readonly property real natural: 24 + titleText.implicitWidth
            x: root.narrow ? 8 : Math.max(leftEnd, Math.min(rightStart - width, (leftEnd + rightStart) / 2 - natural / 2))
            width: root.narrow ? root.width - 210 : Math.min(natural, Math.max(0, rightStart - leftEnd))
            height: 48; clip: true
            Row {
                id: titleRow
                y: 12; spacing: 8
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: root.item ? root.fileIcon(root.item.kind) : "" }
                Text {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, titleBox.width - 24)
                    elide: Text.ElideRight
                    text: root.item ? root.item.name : ""
                    font.family: theme.font; font.pixelSize: 14; color: theme.onFill([hcFill1, hcFill2], theme.hc("#F3F2F1", "#FFFFFF"))
                    Accessible.role: Accessible.Heading
                    Accessible.name: root.item ? root.item.name : ""
                }
            }
        }
        // Your picture: 32 with a 2 px presence ring.
        Avatar { id: avatar; visible: !root.narrow; x: commentsButton.x - 7 - 32; y: 8; size: 32; photoId: "me"; name: backend.userName }
        // Show comments: 32 x 32, the same border; pressed while its pane is open.
        Rectangle {
            id: commentsButton
            visible: !root.narrow
            x: openButton.x - 8 - 32; y: 8; width: 32; height: 32; radius: 6
            color: root.commentsOpen || cbh.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(31 / 255, 31 / 255, 31 / 255, 0.88)
            border.width: 0.67; border.color: theme.hc("#808080", "#FFFFFF")
            FluentIcon { anchors.centerIn: parent; size: 16; name: root.commentsOpen ? "comment-16-filled" : "comment-16"; color: theme.onFill(commentsButton, bar.glyph) }
            HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.commentsOpen = !root.commentsOpen }
            ToolTip.visible: cbh.hovered
            ToolTip.text: root.commentsOpen ? qsTr("Hide comments") : qsTr("Show comments")
            Accessible.role: Accessible.Button
            Accessible.name: root.commentsOpen ? qsTr("Hide comments") : qsTr("Show comments")
            Accessible.checked: root.commentsOpen
        }
        BarButton {
            id: openButton
            visible: !root.narrow
            x: shareButton.x - 12 - width; y: 8
            label: qsTr("Open"); icon: root.appIcon() || "open-16"
            onClicked: openMenu.open()
            MenuPopup {
                id: openMenu
                fabric: true; darkCallout: true; fabricWidth: 180
                y: parent.height
                items: root.actions && root.item ? root.actions.itemsFor(root.item)[0].submenu || [] : []
                onPicked: i => { root.actions.item = root.item; root.actions.act(items[i].label) }
            }
        }
        // Share ▾: Share, Copy link, Manage access, in a dark callout under
        // the button whose right edge stays 8 in from the view's.
        BarButton {
            id: shareButton
            x: root.width - 58 - width; y: 8
            label: qsTr("Share"); icon: "share-16"
            onClicked: shareMenu.open()
            MenuPopup {
                id: shareMenu
                fabric: true; darkCallout: true; fabricWidth: 180
                x: Math.min(0, root.width - 8 - shareButton.x - width); y: parent.height
                items: [{ label: qsTr("Share"), icon: "share-16" }, { label: qsTr("Copy link"), icon: "link-16" }, { label: qsTr("Manage access"), icon: "person-16" }]
                onPicked: i => { root.actions.item = root.item; root.actions.act(items[i].label) }
            }
        }
        BarIcon { x: root.width - 46; y: 4; icon: "dismiss-20"; tip: qsTr("Close"); onClicked: root.close() }
    }

    // Show comments: OneDrive's dark comments pane, 370 wide, 8 in from the
    // right, from 53 to 8 above the bottom (#141414, radius 5): "Comments"
    // (20/600), Close comments, the "@mention or comment" box (328 x 30.67:
    // #252423, 0.67 #424242, a 2 px #BEBBB8 bottom, radius 6), then the
    // comments, newest first, or OneDrive's empty state (its 128 px picture,
    // "No comments yet", "Be the first to add a comment to the file").
    Rectangle {
        id: comments
        visible: root.commentsOpen && !!root.item
        x: root.width - 378; y: 53; width: 370; height: root.height - 61
        radius: 5; color: theme.hc("#141414", "#000000")
        property var list: []
        property var oids: ({})
        property bool loading: false
        property bool sending: false
        property string error: ""
        function load() {
            if (!root.item) return
            loading = true; error = ""
            backend.driveAction(root.tag + "comments", JSON.stringify(root.item), "{}")
        }
        function send() {
            const t = box.text.trim()
            if (!t || sending) return
            sending = true; error = ""
            backend.driveAction(root.tag + "comment", JSON.stringify(root.item), JSON.stringify({ text: t }))
        }
        readonly property color fg: theme.hc("#F3F2F1", "#FFFFFF")
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: ev => ev.accepted = false }
        Text {
            x: 20; y: 26.59; height: 32; verticalAlignment: Text.AlignVCenter
            text: qsTr("Comments")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: comments.fg
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Rectangle {
            id: ccClose
            x: 328; y: 26.59; width: 32; height: 32; radius: 4
            color: cch.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 16; name: "dismiss-16"; color: theme.onFill(ccClose, bar.glyph) }
            HoverHandler { id: cch; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.commentsOpen = false }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close comments")
        }
        Rectangle {
            x: 21; y: 76.19; width: 328; height: Math.max(30.67, box.contentHeight + 10.67); radius: 6
            color: theme.hc("#252423", "#000000")
            border.width: 0.67; border.color: theme.hc("#424242", "#FFFFFF")
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: box.activeFocus ? 2 : 2; radius: 1; color: box.activeFocus ? theme.hc("#0078D4", "#1AEBFF") : theme.hc("#BEBBB8", "#FFFFFF") }
            TextEdit {
                id: box
                x: 8; y: 5; width: parent.width - 16
                wrapMode: TextEdit.Wrap
                font.family: theme.font; font.pixelSize: 14; color: theme.hc("#D2D0CE", "#FFFFFF")
                selectByMouse: true
                Keys.onReturnPressed: ev => { if (ev.modifiers & Qt.ShiftModifier) ev.accepted = false; else comments.send() }
                Text { visible: !box.text; text: qsTr("@mention or comment"); font: box.font; color: theme.hc("#D2D0CE", "#FFFFFF") }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Comment input")
            }
        }
        Text {
            visible: !!comments.error
            x: 20; y: 112; width: 330; wrapMode: Text.Wrap
            text: comments.error
            font.family: theme.font; font.pixelSize: 12; color: theme.hc("#F1707B", "#FFFFFF")
        }
        // The empty state, centred in the list.
        Column {
            visible: !comments.loading && !comments.list.length && !comments.error
            anchors.horizontalCenter: parent.horizontalCenter
            y: 245; spacing: 0
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 128; height: 128
                source: "https://res.public.onecdn.static.microsoft/files/sp-client/odsp-media-2f10e0e9/images/commentspane/nocommentsua.png"
                fillMode: Image.PreserveAspectFit; asynchronous: true
            }
            Item { width: 1; height: 14 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("No comments yet")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: comments.fg
            }
            Item { width: 1; height: 10 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 138; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: qsTr("Be the first to add a comment to the file")
                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: comments.fg
            }
        }
        ListView {
            id: commentList
            x: 20; y: 122; width: 330; height: parent.height - y - 12
            clip: true; spacing: 12
            model: comments.list
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: cc
                required property var modelData
                width: commentList.width
                height: ccText.y + ccText.height + 4 + 16 + (cc.modelData.replies || []).length * 0
                Avatar {
                    x: 0; y: 2; size: 32; name: cc.modelData.author || ""
                    photoId: comments.oids[(cc.modelData.author_email || "").toLowerCase()] || ""
                }
                Text { x: 44; y: 0; width: parent.width - 44; elide: Text.ElideRight; text: cc.modelData.author || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: comments.fg }
                Text {
                    id: ccText
                    x: 44; y: 22; width: parent.width - 44
                    wrapMode: Text.Wrap; textFormat: Text.StyledText
                    text: cc.modelData.text
                    font.family: theme.font; font.pixelSize: 14; color: comments.fg
                }
                Text {
                    x: 44; y: ccText.y + ccText.height + 4
                    text: cc.modelData.edited ? qsTr("%1 • Edited").arg(cc.modelData.time) : cc.modelData.time
                    font.family: theme.font; font.pixelSize: 12; color: theme.hc("#C8C6C4", "#FFFFFF")
                    HoverHandler { id: ctt }
                    ToolTip.visible: ctt.hovered && !!cc.modelData.tip
                    ToolTip.text: cc.modelData.tip || ""
                    ToolTip.delay: 500
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: (cc.modelData.author || "") + ": " + cc.modelData.text + " " + cc.modelData.time
            }
        }
        Connections {
            target: backend
            function onDriveActionDone(op, result, err) {
                if (op === root.tag + "comments") {
                    comments.loading = false
                    if (err) { comments.error = err; return }
                    const v = JSON.parse(result)
                    comments.list = v.comments || []; comments.oids = v.oids || {}
                } else if (op === root.tag + "comment") {
                    comments.sending = false
                    if (err) comments.error = err
                    else { box.text = ""; comments.load() }
                }
            }
        }
    }

    // Embed (···): OneDrive's dialog, 598.67 wide, padding 24, on the dark
    // layer: "Embed" (20/600), 'Embed "{name}" on a blog or webpage.', the
    // file as embed.aspx shows it (550.67 x 212), the code (92 tall) and
    // Copy embed code / Close.
    Popup {
        id: embed
        parent: root
        anchors.centerIn: parent
        modal: true; focus: true; padding: 24
        width: 598.67
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: Rectangle { radius: 4; color: theme.hc("#1B1A19", "#000000"); border.width: theme.highContrast ? 1 : 0; border.color: "#FFFFFF" }
        readonly property string stem: root.item ? root.item.name.replace(/\.[^.]*$/, "") : ""
        readonly property string code: root.item ? "<iframe src=\"" + String(root.item.sp_site || "").replace(/\/$/, "") + "/_layouts/15/embed.aspx?UniqueId=" + root.item.sp_item
                                                    + "\" width=\"640\" height=\"360\" frameborder=\"0\" scrolling=\"no\" allowfullscreen title=\"" + stem + "\"></iframe>" : ""
        contentItem: Column {
            spacing: 0
            Item {
                width: parent.width; height: 31.33
                Text { text: qsTr("Embed"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.hc("#F3F2F1", "#FFFFFF"); lineHeight: 28; lineHeightMode: Text.FixedHeight }
                Rectangle {
                    id: emClose
                    anchors.right: parent.right; width: 32; height: 31.33; radius: 4
                    color: emch.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    FluentIcon { anchors.centerIn: parent; size: 16; name: "dismiss-16"; color: theme.onFill(emClose, theme.hc("#A19F9D", "#FFFFFF")) }
                    HoverHandler { id: emch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: embed.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Close")
                }
            }
            Item { width: 1; height: 8 }
            Text {
                text: qsTr("Embed \"%1\" on a blog or webpage.").arg(embed.stem)
                font.family: theme.font; font.pixelSize: 14; color: theme.hc("#F3F2F1", "#FFFFFF")
            }
            Item { width: 1; height: 20 }
            Rectangle {
                width: parent.width; height: 212
                color: "transparent"; border.width: 2; border.color: theme.hc("#F3F2F1", "#FFFFFF")
                PreviewBody {
                    anchors.fill: parent; anchors.margins: 2
                    embedded: true
                    preview: root.preview
                    name: root.item ? root.item.name : ""
                    kind: root.item ? root.item.kind : ""
                    loading: root.loading
                    error: root.error
                    iconName: root.item ? root.fileIcon(root.item.kind) : ""
                    appIconName: root.appIcon()
                }
            }
            Item { width: 1; height: 16 }
            Rectangle {
                width: parent.width; height: 95.33; radius: 4
                color: theme.hc("#1B1A19", "#000000")
                border.width: 0.67; border.color: theme.hc("#3B3A39", "#FFFFFF")
                TextEdit {
                    id: embedCode
                    x: 8; y: 6; width: parent.width - 16; height: 84
                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                    text: embed.code
                    font.family: theme.font; font.pixelSize: 14; color: theme.hc("#F3F2F1", "#FFFFFF")
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("embed code")
                }
            }
            Item { width: 1; height: 16 }
            Row {
                anchors.right: parent.right; spacing: 8
                Repeater {
                    model: [qsTr("Copy embed code"), qsTr("Close")]
                    Rectangle {
                        id: emb
                        required property string modelData
                        required property int index
                        width: Math.max(80, embt.implicitWidth + 24); height: 32; radius: 4
                        color: emh.hovered ? theme.hc("#115EA3", "#1AEBFF") : theme.hc("#0F6CBD", "#000000")
                        border.width: index === 1 ? 0.67 : 0; border.color: theme.hc("#808080", "#FFFFFF")
                        Text { id: embt; anchors.centerIn: parent; text: emb.modelData; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(emb, "#FFFFFF") }
                        HoverHandler { id: emh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (emb.index === 0) { embedCode.selectAll(); embedCode.copy(); embedCode.deselect() }
                                else embed.close()
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                    }
                }
            }
        }
    }

    function fileIcon(kind) {
        const k = String(kind || "").toLowerCase()
        const m = { doc: "docx", docx: "docx", xls: "xlsx", xlsx: "xlsx", ppt: "pptx", pptx: "pptx", pdf: "pdf", txt: "txt", one: "one", loop: "loop",
                    png: "photo", jpg: "photo", jpeg: "photo", gif: "photo" }[k]
        return m ? "ft-" + m + "-20" : "document-16"
    }
    function appIcon() {
        const k = root.item ? String(root.item.kind).toLowerCase() : ""
        return ["doc", "docx"].indexOf(k) >= 0 ? "ft-docx-20" : ["xls", "xlsx"].indexOf(k) >= 0 ? "ft-xlsx-20"
             : ["ppt", "pptx"].indexOf(k) >= 0 ? "ft-pptx-20" : k === "pdf" ? "ft-pdf-20" : ""
    }
    function barForTest() {
        const out = []
        for (let i = 0; i < bar.children.length; i++) {
            const c = bar.children[i]
            if (!c.visible || c.width <= 0) continue
            out.push([c === titleBox ? "title" : c.Accessible.name || c.tip || c.label || "", Math.round(c.x * 100) / 100, Math.round(c.width * 100) / 100])
        }
        return { width: width, narrow: narrow, left: leftShown, more: moreItems.map(m => m.label || m.key), items: out }
    }
    function moreForTest() { moreMenu.open() }
    function shareForTest() { shareMenu.open() }
    function closeMenusForTest() { moreMenu.close(); shareMenu.close(); openMenu.close(); embed.close() }
    function embedForTest() { embed.open(); return embed.code }
    function commentsForTest(on) { if (on !== undefined) commentsOpen = on; return { open: commentsOpen, loading: comments.loading, count: comments.list.length, error: comments.error, texts: comments.list.map(c => c.text) } }
    function commentSendForTest(t) { box.text = t; comments.send() }
    function commentIdForTest(t) { const c = comments.list.find(x => x.text === t || x.source === t); return c ? c.comment_id : "" }
    function stateForTest() {
        return { item: item ? item.name : "", loading: loading, error: error, kind: preview ? preview.kind : "",
                 lines: preview && preview.kind === "text" ? preview.text.split("\n").length : 0, pages: body.pageCount, at: at, files: files.length }
    }
}
