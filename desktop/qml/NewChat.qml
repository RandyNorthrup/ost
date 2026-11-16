import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Teams' new chat form (measured on Teams web, 2026-11-16; the spec is
// docs/spec/chat-list-and-header.md §2.4):
// - the "To:" row in the header's place (61 tall): "To:" 32 in, the
//   people picker ("Enter name, chat, channel, email or tag") from 64, each
//   person picked a 32 px chip from 73, and the group name chevron ("Add
//   group name and create a new group chat" / "Collapse group name") 35.5
//   from the right; its bottom line turns brand while the picker has focus;
// - the chevron opens "Group name:" above it, with a 2 px underline 20 in
//   from each side;
// - while the picker has focus its suggestions drop 2 below the row (your
//   recent one-on-one chats, then you, until you type; then the search);
// - with nobody picked, or a new conversation, the note "You're starting a
//   new conversation" / "Type your first message below." and the compose
//   box, always shown;
// - one person you already have a chat with: that chat's messages and its
//   compose box under the To row (the form only keeps its rows: the chat is
//   opened behind it, `previewChat`).
// Sending with one person and no group name opens (or starts) your 1:1 chat
// with them; with more people, or a name, it starts a group chat. The
// message goes from that chat's own compose box as written (formatting,
// emoji and GIFs, files, cloud files, a clip, its delivery option; see
// `message()`), as Teams makes the chat as the first message goes.
Rectangle {
    id: root
    /// The directory search (fallback while Teams' picker answers nothing).
    property var people: []
    /// Teams' people picker for this form (backend.newChatPeopleJson):
    /// {query, items: [{id, name, sub, guest, upn}]}.
    property var suggested: ({ query: "", items: [] })
    /// The chat list (suggestions, and the chat you already have with a
    /// person).
    property var chats: []
    /// You, for the suggestions ("<name> (You)").
    property string myMri: ""
    property string myName: ""
    /// The chat behind the form can show (the main window; not the pop-out).
    property bool allowHistory: true
    /// Picked so far: [{ id, name }].
    property var picked: []
    property bool naming: false
    property alias nameText: nameField.text
    signal search(string query)
    /// One person, no name: open your 1:1 chat and send `message` (JSON,
    /// `message()`; "" when nothing was written).
    signal chosen(string oid, string name, string message)
    /// Several people, or a name: start a group chat and send `message`.
    signal group(string oids, string topic, string message)
    /// "+" ▸ Schedule meeting: a meeting with the people picked (emails).
    signal scheduleMeetingWith(string attendees)
    signal cancelled()
    /// Show this chat behind the form ("" when the form shows its own note).
    signal previewChat(string chatId, string name)
    signal emojiRequested(Item box)
    function setMessage(t) { compose.setPlain(t) }
    function composeBox() { return compose }

    function chatWith(oid) {
        const mri = "8:orgid:" + oid
        const c = root.chats.find(c => c.peerMri === mri && !c.isGroup && !c.isSelf && !c.meeting)
        return c ? c.id : ""
    }
    readonly property string existingChat: allowHistory && picked.length === 1 && !nameField.text.trim() ? chatWith(picked[0].id) : ""
    readonly property bool history: existingChat.length > 0
    onExistingChatChanged: if (visible) root.previewChat(existingChat, existingChat ? picked[0].name : "")
    color: history ? "transparent" : theme.surface

    onVisibleChanged: if (visible) {
        picked = []; naming = false; field.text = ""; nameField.text = ""; compose.clear(); clearAttachments()
        highlight = -1; suggestOpen = true; field.forceActiveFocus()
        root.search("")
    }

    function pick(p) {
        if (!picked.some(x => x.id === p.id)) picked = picked.concat([{ id: p.id, name: p.name.replace(/ \(You\)$/, ""), mail: p.guest ? (p.sub || "") : (p.upn || p.mail || "") }])
        field.text = ""
        root.search("")
        highlight = -1
        field.forceActiveFocus()
    }
    function unpick(id) { picked = picked.filter(x => x.id !== id) }
    /// What the compose box holds, for the chat's own box to send
    /// (Conversation.adoptAndSend): {text, html, media, importance, files,
    /// cloud, clip}; "" when there is nothing to send.
    function message() {
        const d = compose.draftState()
        const text = compose.plainText()
        const m = {
            text: text, html: text.trim() ? compose.formattedText() : "", media: compose.mediaInUse(),
            importance: compose.importance, files: root.pendingFiles, cloud: cloudAttach.pending, clip: compose.clip
        }
        const empty = !text.trim() && m.media.length === 0 && m.files.length === 0 && m.cloud.length === 0 && !m.clip
        return empty ? "" : JSON.stringify(m)
    }
    function submit() {
        if (picked.length === 0) return
        const m = root.message()
        if (picked.length === 1 && !nameField.text.trim()) root.chosen(picked[0].id, picked[0].name, m)
        else root.group(picked.map(p => p.id).join(","), nameField.text.trim(), m)
        compose.clear(); compose.importance = ""; compose.clip = null; root.clearAttachments()
    }

    // ---- Attach and "+" (the conversation's own, before there is a chat) ----
    property var pendingFiles: []
    function clearAttachments() { pendingFiles = []; cloudAttach.clear() }
    function addFiles(urls) {
        const paths = urls.map(u => String(u).replace(/^file:\/\//, ""))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    CloudAttach {
        id: cloudAttach
        onUploadRequested: filePicker.open()
        onFailed: text => compose.showBanner(text, false, 3000)
    }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }
    // Teams' recorder; the clip is stored once the chat is made.
    VideoClipRecorder {
        id: clipRecorder
        onFinished: clip => compose.clip = Object.assign({}, clip, { uploading: false, id: "", url: "" })
    }
    function attachForTest(paths) { root.pendingFiles = paths }
    function cloudForTest() { return cloudAttach }
    function plusForTest() { compose.plusForTest() }
    function setFieldForTest(t) { field.text = t; root.suggestOpen = true; field.forceActiveFocus(); root.search(t) }

    // ---- Suggestions ----
    // Teams' people picker: before typing its top-N people (the people you
    // work with most, you among them as "(You)", then the rest of its
    // ranking: guests too); then its search. People only. (Teams keeps the
    // top-N list from earlier; OST shows it once the service answers.)
    property var zeroItems: []
    onSuggestedChanged: if (suggested && suggested.query === "" && suggested.items.length > 0) zeroItems = suggested.items
    readonly property var typedItems: suggested && suggested.query !== "" && suggested.query === field.text.trim() ? suggested.items : null
    readonly property var suggestions: (field.text.length > 0
        ? (typedItems !== null ? typedItems : root.people.map(p => ({ id: p.id, name: p.name, sub: p.mail || "" })))
        : zeroItems).filter(p => !root.picked.some(x => x.id === p.id))
    /// The row Up / Down reached (-1: none; Return then takes the first).
    property int highlight: -1
    /// Esc closes the suggestions first; typing or a click shows them again.
    property bool suggestOpen: true
    readonly property bool suggesting: field.activeFocus && suggestOpen && suggestions.length > 0

    // ---- The header rows ----
    Column {
        id: rows
        width: parent.width
        // Group name (the chevron).
        Rectangle {
            id: nameRow
            visible: root.naming
            width: parent.width; height: visible ? 61 : 0
            color: theme.surface
            Text {
                id: nameLabel
                x: 32; anchors.verticalCenter: parent.verticalCenter
                text: "Group name:"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
            }
            TextField {
                id: nameField
                anchors { left: nameLabel.right; leftMargin: 8; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                leftPadding: 0
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                background: Item {}
                Keys.onEscapePressed: root.cancelled()
                Accessible.name: "Group name"
            }
            Rectangle {
                anchors.bottom: parent.bottom; x: 20; width: parent.width - 40
                height: nameField.activeFocus ? 2 : 1
                color: nameField.activeFocus ? theme.brand : theme.divider
            }
        }
        Rectangle {
            id: toRow
            width: parent.width; height: Math.max(61, chips.height + 29)
            color: theme.surface
            Text {
                id: toLabel
                x: 32; y: (61 - height) / 2
                text: "To:"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
            }
            Flow {
                id: chips
                anchors.left: parent.left; anchors.leftMargin: root.picked.length ? 73 : 64
                anchors.right: chevron.left; anchors.rightMargin: 8
                y: 14.5
                spacing: 9
                Repeater {
                    model: root.picked
                    // Teams' recipient chip (fui-Tag): 32 tall, a pill on
                    // NeutralBackground4, the 32 px picture, the name 8
                    // after it and a 20 px dismiss.
                    Rectangle {
                        id: chip
                        required property var modelData
                        height: 32; radius: 16
                        width: 41 + chipName.implicitWidth + 20
                        color: theme.pick("#F0F0F0", "#0A0A0A", "#000000")
                        border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                        Avatar { x: 1; anchors.verticalCenter: parent.verticalCenter; size: 32; name: chip.modelData.name; photoId: chip.modelData.id }
                        Text {
                            id: chipName
                            x: 41; anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.name
                            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                        }
                        Rectangle {
                            id: chipX
                            x: chipName.x + chipName.implicitWidth; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 10
                            color: xh.hovered ? theme.rowHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.onFill(chipX, theme.textStrong) }
                            HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.unpick(chip.modelData.id) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + chip.modelData.name
                        }
                    }
                }
                TextField {
                    id: field
                    width: root.picked.length ? Math.max(120, chips.width - root.chipsWidth - 9) : chips.width
                    height: 32
                    leftPadding: 0
                    placeholderText: root.picked.length ? "" : "Enter name, chat, channel, email or tag"
                    placeholderTextColor: theme.textSecondary
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.text
                    background: Item {}
                    focus: true
                    onTextEdited: { root.suggestOpen = true; root.highlight = -1; debounce.restart() }
                    onActiveFocusChanged: if (activeFocus) root.suggestOpen = true
                    Keys.onEscapePressed: { if (root.suggesting) root.suggestOpen = false; else root.cancelled() }
                    Keys.onDownPressed: if (root.suggesting) root.highlight = Math.min(root.suggestions.length - 1, root.highlight + 1)
                    Keys.onUpPressed: if (root.suggesting) root.highlight = Math.max(0, root.highlight - 1)
                    Keys.onReturnPressed: {
                        if (root.suggesting) root.pick(root.suggestions[Math.max(0, Math.min(root.highlight, root.suggestions.length - 1))])
                        else if (root.picked.length > 0) compose.focusEditor()
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Backspace && field.text.length === 0 && root.picked.length > 0) {
                            root.unpick(root.picked[root.picked.length - 1].id); e.accepted = true
                        }
                    }
                    TapHandler { onTapped: { root.suggestOpen = true; field.forceActiveFocus() } }
                    Component.onCompleted: forceActiveFocus()
                    Accessible.name: "To"
                    Accessible.description: "Enter name, chat, channel, email or tag"
                }
            }
            Rectangle {
                id: chevron
                x: parent.width - 35.5 - width / 2
                y: (61 - height) / 2
                width: 32; height: 32; radius: theme.radius
                color: cvh.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: root.naming ? "chevron-up-20" : "chevron-down-20"; size: 20; color: theme.onFill(chevron, theme.textStrong) }
                HoverHandler { id: cvh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.naming = !root.naming; if (root.naming) nameField.forceActiveFocus(); else { nameField.text = ""; field.forceActiveFocus() } } }
                Accessible.role: Accessible.Button
                Accessible.name: root.naming ? "Collapse group name" : "Add group name and create a new group chat"
            }
            Timer { id: debounce; interval: 300; onTriggered: root.search(field.text) }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width
                height: 1
                color: field.activeFocus ? theme.brand : theme.divider
            }
        }
    }
    // The chips' width on the picker's last line (the field takes the rest).
    FontMetrics { id: chipFont; font.family: theme.font; font.pixelSize: theme.base }
    readonly property real chipsWidth: {
        let line = 0
        for (const p of root.picked) {
            const w = 61 + chipFont.advanceWidth(p.name)
            line = line > 0 && line + 9 + w > chips.width ? w : line + (line > 0 ? 9 : 0) + w
        }
        return line
    }

    // The note, with nobody picked or for a new conversation (measured on
    // winpc 2026-11-16): Teams' chat-pencil illustration (256), the heading
    // 23.3 under it and the line 23.2 under that, centred between the To
    // row and the compose box; the picture only where it fits.
    Column {
        id: note
        visible: !root.history
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property real room: compose.y - rows.height
        readonly property bool art: room >= 344.5 + 32
        y: rows.height + (room - height) / 2
        spacing: 23.3
        Image {
            visible: note.art
            anchors.horizontalCenter: parent.horizontalCenter
            width: 256; height: 256
            source: "../assets/illustrations/chat-pencil-l-standard.svg"
            sourceSize: Qt.size(512, 512)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You're starting a new conversation"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            color: theme.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Type your first message below."
            font.family: theme.font; font.pixelSize: theme.base
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
    }

    // The compose box, as the conversation's (Teams always shows it).
    ComposeBox {
        id: compose
        visible: !root.history
        readonly property real gut: root.width < 480 ? 14 : root.width < 720 ? 32 : 72
        anchors { left: parent.left; right: parent.right; leftMargin: gut; rightMargin: gut }
        y: root.height - height - 6
        compact: root.width < 480
        tierWidth: root.width
        previewsAllowed: false
        scheduleAllowed: false
        placeholder: "Type a message"
        newConversation: true
        files: root.pendingFiles
        cloudFiles: cloudAttach.pending
        onFileRemoved: path => root.pendingFiles = root.pendingFiles.filter(p => p !== path)
        onCloudRemoved: key => cloudAttach.remove(key)
        onCloudLinkRequested: key => cloudAttach.openLink(key)
        onAttachRequested: a => cloudAttach.openMenu(a || compose)
        canRecordClip: true
        onRecordClipRequested: clipRecorder.openFor("")
        onClipRemoved: {
            if (compose.clip) {
                if (compose.clip.path) backend.removeRecorderFile(compose.clip.path)
                if (compose.clip.spec) for (const sg of compose.clip.spec.segments) backend.removeRecorderFile(sg.path)
            }
            compose.clip = null
        }
        onScheduleMeetingRequested: root.scheduleMeetingWith(root.picked.map(p => p.mail).filter(m => m).join(", "))
        onSubmit: root.submit()
        onEmojiRequested: a => root.emojiRequested(compose)
        onCancelled: { compose.clear(); root.clearAttachments() }
    }

    // The suggestions (Teams' people-picker-list): 2 below the To row, as
    // wide as the picker, white, radius 4, shadow 16, padding 4; rows 50
    // tall (2 apart), the 32 px picture 16 in, the name (14/20) and the
    // second line (12/16, #616161) at 64.
    FluentSurface {
        id: suggestBox
        visible: root.suggesting
        z: 5
        x: 52.67; y: rows.height + 2
        width: root.width - 52.67 - 71.33
        height: Math.min(225, suggestCol.height + 8)
        depth: 16; radius: 4; color: theme.surface
        clip: true
        Flickable {
            id: suggestFlick
            x: 4; y: 4; width: parent.width - 8; height: parent.height - 8
            contentHeight: suggestCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: suggestCol
            width: parent.width
            spacing: 2
            Repeater {
                model: root.suggesting ? root.suggestions : []
                // Teams' people-picker-entry (measured on winpc 2026-11-16):
                // 50 tall (52 for a guest), padding 6 / 8; the 32 px picture
                // 12 in; the name 14/20 NeutralForeground2 at 60, 6.5 down
                // (8 for a guest); the second line 12/16 NeutralForeground3
                // 21 under it: the sign-in name before "@" in capitals,
                // "(ALIAS) job title" with a job title, a guest's email.
                // A guest's name has Teams' "Guest" tag 4 after it: 24 tall,
                // radius 4, NeutralBackground5-ish #EBEBEB, padding 0 6, the
                // guest icon (16, filled) and "Guest" 12 semibold #616161.
                Rectangle {
                    id: person
                    required property var modelData
                    required property int index
                    readonly property bool guest: person.modelData.guest === true
                    readonly property string second: person.modelData.sub || ""
                    width: suggestCol.width; height: guest ? 52 : 50; radius: 4
                    color: hover.hovered || root.highlight === index ? theme.hc(theme.menuHover, theme.hcHighlight) : "transparent"
                    Avatar { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: person.modelData.name.replace(/ \(You\)$/, ""); photoId: person.modelData.id || "" }
                    Text {
                        id: personName
                        x: 60; y: person.guest ? 8 : 6.5
                        text: person.modelData.name
                        font.family: theme.font; font.pixelSize: theme.base; lineHeight: 20; lineHeightMode: Text.FixedHeight
                        color: theme.onFill(person, theme.textStrong)
                    }
                    Rectangle {
                        id: guestTag
                        visible: person.guest
                        x: personName.x + personName.implicitWidth + 4; y: 6
                        width: 12 + 16 + 2 + guestText.implicitWidth; height: 24; radius: 4
                        color: theme.pick("#EBEBEB", "#3D3D3D", "transparent")
                        border.width: theme.highContrast ? 1 : 0; border.color: theme.text
                        FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "guest-16-filled"; size: 16; color: theme.onFill(guestTag, theme.textSecondary) }
                        Text {
                            id: guestText
                            x: 24; anchors.verticalCenter: parent.verticalCenter
                            text: "Guest"
                            font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                            color: theme.onFill(guestTag, theme.textSecondary)
                        }
                    }
                    Text {
                        visible: person.second.length > 0
                        x: 60; y: personName.y + 21; width: person.width - 60 - 8
                        elide: Text.ElideRight
                        text: person.second
                        font.family: theme.font; font.pixelSize: theme.small; lineHeight: 16; lineHeightMode: Text.FixedHeight
                        color: theme.onFill(person, theme.textSecondary)
                    }
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pick(person.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: person.modelData.name + (person.guest ? " Guest" : "") + (person.second ? ", " + person.second : "")
                }
            }
        }
        }
    }
    Text {
        visible: field.activeFocus && field.text.length >= 2 && root.typedItems !== null && root.typedItems.length === 0 && !debounce.running
        x: 52.67 + 16; y: rows.height + 18
        text: "No people found"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }
}
