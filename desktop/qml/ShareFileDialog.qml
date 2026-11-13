import QtQuick
import QtQuick.Controls.Basic
import com.ost.desktop

// Teams' "Share this file" (a search file card's Share), measured on winpc
// 2026-11-11: a 600-wide Fluent dialog, radius 8, padding 32.
// - "Share this file" (20/28 semibold) over "You can share to any chat or
//   channel." (14/28 #616161); More actions (···: Share outside Teams) and
//   Close (40 x 39.33, a 24 px glyph).
// - "Add recipients *" (12/20, the star #D13438) over a 534.67 x 33.33
//   #F0F0F0 picker (radius 4, padding 0 12): "Enter name, email, group or
//   tag". Suggestions (Teams' peoplepicker.newChat: people, chats,
//   channels, teams in its order) drop below it, 225 at most: 50 px rows, a
//   32 px picture at 12, the name (14/20 #424242, the match bold) and
//   Teams' second line (12/16 #616161). Picks become white 25.33 px pills
//   (24 px picture, the name 14 px, a 12 px dismiss).
// - "Message preview" over a #F5F5F5 box (0.67 #E0E0E0, radius 6, 534.67
//   x 329.33): "Add a message (optional)" (14/20, padding 10 16 8 12), the
//   file card (320 x 236 at 13.67, 42.67: a #FAFAFA head 56.67 tall with the
//   32 px type icon, the name 14/16 semibold and the link line 12/20
//   #424242 that opens Link settings; the c960x540 preview under it), and
//   Emoji at the bottom right. A recipient who can't open the file puts a
//   32 px #FDF3F4 bar under the head: "The recipient can't access this
//   item" (10 px) and Give access (10 px, white, a #D1D1D1 edge, radius 4).
// - Copy link (outline) and Share (brand; #F0F0F0 / #BDBDBD until someone
//   is picked), 96 x 31.33, at the bottom right.
// Share posts the message with the file to the picked chat or channel (or
// the people's chat), with the link chosen in Link settings; "People
// currently in this chat" makes a specific-people link the chat service
// opens to the chat.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 600; height: 648.33 + (picker.height - 33.33) + (formatting ? 20.67 : 0)
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    /// The file: {site, list, item}, its name, type and address.
    property var item: null
    property string fileName: ""
    property string fileType: ""
    property string objectUrl: ""
    property var info: null
    property var picked: []
    property string query: ""
    property var suggestions: []
    // The link: scope (3 existing access, 0 anyone, 1 organisation, 4 this
    // chat, 2 people you choose), edit, expiry and password.
    property int scope: 3
    property bool edit: true
    property string expiration: ""
    property string password: ""
    property var noAccess: []
    property bool sharing: false
    property string error: ""
    property string thumb: ""
    /// Format on: Teams' formatting bar over the message (the box 20.67
    /// taller), and the message sent as formatted HTML.
    property bool formatting: false
    property var richState: ({})

    function openFor(itemRef, name, type, url) {
        item = itemRef; fileName = name || ""; fileType = type || ""; objectUrl = url || ""
        info = null; picked = []; query = ""; suggestions = []; scope = 3; edit = true; expiration = ""; password = ""
        noAccess = []; sharing = false; error = ""; formatting = false
        thumb = backend.fileThumbnail(objectUrl)
        linkTouched = false
        // Teams starts from the file's default link (its driveItem/commands
        // description, as the compose card's): "Anyone with the link can
        // edit" once the file has one.
        if (objectUrl) backend.driveAction(defaultTag + "attach_prepare", JSON.stringify({ web_url: objectUrl, name: fileName }), "{}")
        open()
        pickerInput.text = ""; note.text = ""
        pickerInput.forceActiveFocus()
        backend.shareAction("sf:info", JSON.stringify(item), "{}")
    }
    Connections {
        target: backend
        function onThumbnailReady(url) { if (url === root.objectUrl) root.thumb = backend.fileThumbnail(root.objectUrl) }
        function onShareDone(op, result, error) {
            if (!root.opened || op.indexOf("sf:") !== 0) return
            const v = result ? JSON.parse(result) : null
            if (op === "sf:info") { if (!error) root.info = v }
            else if (op === "sf:recipients") { if (v && v.query === root.query.trim()) root.suggestions = v.items.filter(s => !root.picked.some(p => root.same(p, s))) }
            else if (op === "sf:access") { if (v) root.noAccess = v.filter(a => !a.ok).map(a => a.upn.toLowerCase()) }
            else if (op === "sf:copy") {
                if (error) { root.error = error; return }
                backend.copyText(v.url); backend.statusText = "Link copied"
            } else if (op === "sf:link") {
                if (error) { root.error = error; root.sharing = false; return }
                root.post(v.url, v.share_id)
            } else if (op === "sf:post") {
                root.sharing = false
                if (error) { root.error = error; return }
                root.close()
            }
        }
    }
    property bool linkTouched: false
    readonly property string defaultTag: "sfd" + Math.floor(Math.random() * 1e9) + ":"
    /// The starting choice from a default link's description.
    function startFrom(description, write) {
        const d = String(description || "")
        if (!d || root.linkTouched) return
        if (d.startsWith("Anyone with the link")) { scope = 0; edit = write }
        else if (d.startsWith("People in ")) { scope = 1; edit = write }
        else if (d.startsWith("Specific people") || d.startsWith("Only the people")) { scope = 2; edit = write }
        else if (d.startsWith("People with existing access")) scope = 3
    }
    Connections {
        target: backend
        function onDriveActionDone(op, result, error) {
            if (op !== root.defaultTag + "attach_prepare" || error || !result || !root.opened) return
            const v = JSON.parse(result)
            if (v.file && v.file.object_url === root.objectUrl) root.startFrom(v.file.link_description, v.file.role === "write")
        }
    }
    function same(a, b) { return a.kind === b.kind && (a.kind === "person" ? a.oid === b.oid : a.id === b.id) }
    function pick(s) {
        picked = picked.concat([s]); query = ""; suggestions = []; pickerInput.text = ""
        pickerInput.forceActiveFocus()
        checkAccess()
    }
    function unpick(i) { const a = picked.slice(); a.splice(i, 1); picked = a; checkAccess() }
    function checkAccess() {
        const upns = picked.filter(p => p.kind === "person" && p.upn).map(p => p.upn)
        if (!upns.length) { noAccess = []; return }
        backend.shareAction("sf:access", JSON.stringify(item), JSON.stringify({ upns: upns }))
    }
    readonly property bool blocked: picked.some(p => p.kind === "person" && p.upn && noAccess.indexOf(p.upn.toLowerCase()) >= 0)
    function org() { return info ? info.tenant : "your organization" }
    function linkLine() {
        const can = edit ? "edit" : "view"
        return scope === 3 ? "People with existing access can use the link"
             : scope === 0 ? "Anyone with the link can " + can
             : scope === 1 ? "People in " + org() + " with the link can " + can
             : "Specific people with the link can " + can
    }
    function copyLink() {
        error = ""
        if (scope === 3) { if (info) { backend.copyText(info.direct_url); backend.statusText = "Link copied" } return }
        backend.shareAction("sf:copy", JSON.stringify(item), JSON.stringify({ scope: scope, edit: edit, expiration: expiration, password: password }))
    }
    function share() {
        if (!picked.length || sharing) return
        error = ""; sharing = true
        if (scope === 3) post(info ? info.direct_url : objectUrl, "")
        else backend.shareAction("sf:link", JSON.stringify(item), JSON.stringify({ scope: scope, edit: edit, expiration: expiration, password: password }))
    }
    function post(url, shareId) {
        backend.shareAction("sf:post", JSON.stringify(item), JSON.stringify({
            targets: picked, note: note.getText(0, note.length), note_html: note.length ? rich.exportHtml() : "",
            file: { name: fileName, object_url: objectUrl, share_url: url, share_id: shareId }
        }))
    }
    function bolded(name) {
        const q = query.trim()
        const e = String(name || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
        if (!q) return e
        const re = new RegExp("(^|\\b)(" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi")
        return e.replace(re, "$1<b>$2</b>")
    }
    function fileIcon() {
        const t = String(fileType || fileName.split(".").pop()).toLowerCase()
        const k = t === "doc" || t === "docx" ? "docx" : t === "xls" || t === "xlsx" ? "xlsx" : t === "ppt" || t === "pptx" ? "pptx" : t === "pdf" ? "pdf"
                : t === "one" || t === "onetoc2" ? "one" : t === "loop" || t === "fluid" ? "loop" : t === "txt" ? "txt" : ["png", "jpg", "jpeg", "gif", "bmp", "webp"].indexOf(t) >= 0 ? "photo" : "genericfile"
        return "ft-" + k + "-32"
    }

    // A recipient's picture: a person's, a meeting's calendar, a team's or
    // channel's team picture, a group chat's people.
    component Picture: Avatar {
        property var who: null
        name: who ? who.name.replace(/ \(You\)$/, "") : ""
        photoId: !who ? "" : who.kind === "person" ? "8:orgid:" + who.oid : who.group ? "team:" + who.group : ""
        meeting: !!who && who.thread_type === "Meeting"
        group: !!who && who.kind === "chat" && !who.group && who.thread_type !== "Meeting"
        square: !!who && !!who.group
    }

    Text { x: 32.67; y: 32.67; height: 28; verticalAlignment: Text.AlignVCenter; text: "Share this file"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Text { x: 32.67; y: 60.67; height: 28; verticalAlignment: Text.AlignVCenter; text: "You can share to any chat or channel."; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
    Rectangle {
        id: moreBtn
        x: 495.33; y: 36.67; width: 32; height: 31.33; radius: 4
        color: mbh.hovered || moreMenu.visible ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 20; name: "more-horizontal-20"; color: theme.textStrong }
        HoverHandler { id: mbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: moreMenu.open() }
        Accessible.role: Accessible.Button
        Accessible.name: "More actions"
        MenuPopup {
            id: moreMenu
            x: parent.width - width; y: parent.height + 4
            items: [{ label: "Share outside Teams", icon: "share-20" }]
            onPicked: { close(); const it = root.item, n = root.fileName, t = root.fileType; root.close(); outside.openFor(it, n, t) }
        }
    }
    Rectangle {
        x: 527.33; y: 32.67; width: 40; height: 39.33; radius: 4
        color: clh.hovered ? theme.hover : "transparent"
        FluentIcon { anchors.centerIn: parent; size: 24; name: "dismiss-20"; color: theme.textStrong }
        HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }

    // Recipients.
    Row {
        x: 32.67; y: 114.67
        Text { text: "Add recipients"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Text { leftPadding: 4; text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#D13438", "#F1707B") }
    }
    Rectangle {
        id: picker
        x: 32.67; y: 134.67; width: 534.67; height: root.picked.length ? Math.max(38.67, pillFlow.height + 12) : 33.33
        radius: 4; color: theme.pick("#F0F0F0", "#1F1F1F")
        Flow {
            id: pillFlow
            x: 12; y: 6; width: parent.width - 24; spacing: 4
            Repeater {
                model: root.picked
                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    width: pillName.implicitWidth + 31 + 4 + 19; height: 25.33; radius: 12.67; color: theme.surface
                    Picture { x: 1; y: 0.67; size: 24; who: pill.modelData }
                    Text { id: pillName; x: 33; anchors.verticalCenter: parent.verticalCenter; text: pill.modelData.name.replace(/ \(You\)$/, ""); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Item {
                        x: parent.width - 19; width: 19; height: parent.height
                        FluentIcon { anchors.centerIn: parent; size: 12; name: "dismiss-20"; color: theme.textStrong }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.unpick(pill.index) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove " + pill.modelData.name
                    }
                }
            }
            TextInput {
                id: pickerInput
                width: Math.max(120, pillFlow.width - (root.picked.length ? 140 : 0)); height: root.picked.length ? 25.33 : 21.33
                verticalAlignment: TextInput.AlignVCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                clip: true
                onTextChanged: {
                    root.query = text
                    if (text.trim().length) backend.shareAction("sf:recipients", "{}", JSON.stringify({ query: text.trim() }))
                    else root.suggestions = []
                }
                Keys.onReturnPressed: if (root.suggestions.length) root.pick(root.suggestions[0])
                Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && !text && root.picked.length) { root.unpick(root.picked.length - 1); e.accepted = true } }
                Text { visible: !parent.text && !root.picked.length; anchors.verticalCenter: parent.verticalCenter; text: "Enter name, email, group or tag"; font: parent.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Enter name, email, group or tag"
            }
        }
        Rectangle { visible: pickerInput.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        TapHandler { onTapped: pickerInput.forceActiveFocus() }
    }

    // The message, and the file.
    Text { x: 32.67; y: picker.y + picker.height + 37.33; text: "Message preview"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
    Rectangle {
        id: preview
        x: 32.67; y: picker.y + picker.height + 57.33; width: 534.67; height: 329.33 + (root.formatting ? 20.67 : 0)
        radius: 6; color: theme.pick("#F5F5F5", "#141414"); border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
        clip: true
        Rectangle { visible: note.activeFocus; anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 2; radius: 1; color: theme.brand; z: 2 }
        // Teams' formatting bar (458 for its buttons, no Discard), at 6.67, 9.67.
        FormatBar {
            id: fmtBar
            visible: root.formatting
            x: 0.67; y: 0.67; width: 490; tierWidth: 640
            discard: false
            st: root.richState
            selectedText: note.selectedText
            onCommand: (op, arg) => { rich.apply(note.selectionStart, note.selectionEnd, op, arg || ""); note.forceActiveFocus(); root.refreshRichState() }
            onUndoRequested: { note.undo(); note.forceActiveFocus() }
            onRedoRequested: { note.redo(); note.forceActiveFocus() }
        }
        TextEdit {
            id: note
            x: 12.67; y: root.formatting ? 43.67 : 10; width: parent.width - 28.67
            wrapMode: TextEdit.Wrap; textFormat: TextEdit.RichText
            selectByMouse: true; selectionColor: theme.selectionFill; selectedTextColor: theme.text
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            onCursorPositionChanged: root.refreshRichState()
            onTextChanged: root.refreshRichState()
            RichText { id: rich }
            // A rich-text editor's text is never empty (it is HTML): its length is.
            Text { visible: note.length === 0; text: "Add a message (optional)"; font: parent.font; color: theme.textSecondary }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Add a message (optional)"
        }
        // The file card.
        Rectangle {
            x: 13.67; y: Math.max(42.67, note.y + note.height + 12.67); width: 320; height: 236
            radius: 6; color: theme.surface; border.width: 0.67; border.color: theme.pick("#E0E0E0", "#3D3D3D")
            clip: true
            Rectangle { width: parent.width; height: 56.67; radius: 6; color: theme.pick("#FAFAFA", "#1A1A1A") }
            FluentIcon { x: 16.67; y: 12.67; size: 32; name: root.fileIcon() }
            Text { x: 60.67; y: 11; width: 240; height: 16; elide: Text.ElideRight; text: root.fileName; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Text {
                x: 60.67; y: 25.67; width: 240; height: 20; elide: Text.ElideRight
                text: root.linkLine(); font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                font.underline: llh.hovered
                HoverHandler { id: llh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: outside.openLinkSettings(root.item, root.fileName, root.fileType, root.scope, root.edit, root.expiration, root.password) }
                Accessible.role: Accessible.Button
                Accessible.name: text
            }
            Rectangle { y: 56.67; width: parent.width; height: 0.67; color: theme.divider }
            // A recipient can't open it.
            Rectangle {
                id: warn
                visible: root.blocked
                y: 57.33; width: parent.width; height: 32; color: theme.pick("#FDF3F4", "#3F1011")
                Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "The recipient can’t access this item"; font.family: theme.font; font.pixelSize: 10; color: theme.text }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    width: gaText.implicitWidth + 16; height: 21.33; radius: 4
                    color: gah.hovered ? theme.hover : theme.surface; border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666")
                    Text { id: gaText; anchors.centerIn: parent; text: "Give access"; font.family: theme.font; font.pixelSize: 10; color: theme.text }
                    HoverHandler { id: gah; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: outside.openLinkSettings(root.item, root.fileName, root.fileType, root.scope, root.edit, root.expiration, root.password) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Give access"
                }
            }
            Rectangle {
                y: warn.visible ? 89.33 : 57.33; width: parent.width; height: parent.height - y
                color: theme.pick("#F5F5F5", "#2E2E2E")
                clip: true
                Image { id: pimg; width: parent.width; height: parent.height; fillMode: Image.PreserveAspectCrop; verticalAlignment: Image.AlignTop; asynchronous: true; source: root.thumb }
                FluentIcon { visible: pimg.status !== Image.Ready; anchors.centerIn: parent; size: 32; name: "ft-genericfile-32" }
            }
            Accessible.role: Accessible.Grouping
            Accessible.name: root.fileName
        }
        // Format (Show / Hide Formatting option).
        Rectangle {
            x: parent.width - 8 - 64; y: parent.height - 36.67; width: 32; height: 32; radius: 4
            color: fmh.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 20; name: "format-20"; color: root.formatting ? theme.brand : theme.textStrong }
            HoverHandler { id: fmh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.formatting = !root.formatting; note.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: root.formatting ? "Hide Formatting option" : "Show Formatting options"
        }
        Rectangle {
            x: parent.width - 8 - 32; y: parent.height - 36.67; width: 32; height: 32; radius: 4
            color: emh.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; size: 20; name: "emoji-20"; color: theme.textStrong }
            HoverHandler { id: emh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: noteEmoji.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Emoji, GIFs and Stickers"
            EmojiPicker { id: noteEmoji; y: -height - 4; x: parent.width - width; onPicked: e => { note.insert(note.cursorPosition, e); close(); note.forceActiveFocus() } }
        }
    }
    Text {
        visible: !!root.error
        x: 32.67; y: preview.y + preview.height + 6; width: 534.67; elide: Text.ElideRight
        text: root.error; font.family: theme.font; font.pixelSize: 12; color: theme.pick("#C4314B", "#F1707B")
    }

    // Copy link, Share.
    Row {
        x: 367.33; y: preview.y + preview.height + 24; spacing: 8
        Rectangle {
            width: 96; height: 31.33; radius: 4
            color: cph.hovered ? theme.hover : theme.surface; border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666")
            Text { anchors.centerIn: parent; text: "Copy link"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.copyLink() }
            Accessible.role: Accessible.Button
            Accessible.name: "Copy link"
        }
        Rectangle {
            readonly property bool on: root.picked.length > 0 && !root.sharing
            width: 96; height: 31.33; radius: 4
            color: !on ? theme.pick("#F0F0F0", "#2E2E2E") : shh.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Share"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? "white" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: shh; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.on; onTapped: root.share() }
            Accessible.role: Accessible.Button
            Accessible.name: "Share"
        }
    }

    // The suggestions, over everything under the picker.
    Rectangle {
        visible: root.suggestions.length > 0 && pickerInput.activeFocus
        x: picker.x; y: picker.y + picker.height + 4; width: picker.width
        height: Math.min(225, root.suggestions.length * 52 + 4)
        radius: 4; color: theme.surface
        FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface; z: -1 }
        ListView {
            x: 4; y: 4; width: parent.width - 8; height: parent.height - 4; clip: true; spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.suggestions
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: sug
                required property var modelData
                width: ListView.view.width - 10; height: 50; radius: 4
                color: sgh.hovered ? theme.hover : "transparent"
                Picture { x: 12; y: 9; size: 32; who: sug.modelData }
                Column {
                    x: 60; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 72
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bolded(sug.modelData.name); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                    Text { visible: !!sug.modelData.sub; width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bolded(sug.modelData.sub); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                }
                HoverHandler { id: sgh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(sug.modelData) }
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + (modelData.sub ? ", " + modelData.sub : "")
            }
        }
    }

    // OneDrive's dialog: Share outside Teams, and Link settings for the
    // link line and Give access.
    OneDriveShare {
        id: outside
        onLinkChosen: (s, e, x, p) => { root.linkTouched = true; root.scope = s; root.edit = e; root.expiration = x; root.password = p }
    }

    function refreshRichState() { try { richState = JSON.parse(rich.state(note.cursorPosition)) } catch (e) { richState = ({}) } }

    // Test hooks.
    function formatForTest(op) { formatting = true; note.selectAll(); rich.apply(note.selectionStart, note.selectionEnd, op, ""); refreshRichState() }
    function typeForTest(q) { pickerInput.forceActiveFocus(); pickerInput.text = q }
    function pickForTest(name) { const s = suggestions.find(x => x.name === name); if (s) pick(s); return !!s }
    function noteForTest(t) { note.text = t }
    function noteHtmlForTest() { return rich.exportHtml() }
    function linkForTest(s, e) { scope = s; edit = e }
    function stateForTest() { return { picked: picked.map(p => p.name), suggestions: suggestions.map(s => s.name + " | " + s.sub), blocked: blocked, scope: scope, line: linkLine(), error: error, sharing: sharing } }
}
