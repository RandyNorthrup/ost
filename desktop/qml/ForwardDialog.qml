import QtQuick
import QtQuick.Controls.Basic

// Teams' forward dialog (forward-message-dialog, measured in the client):
// - a 600-wide Fluent dialog, radius 8, content 33 in;
// - title "Forward this message" (20/28 semibold) and "You can forward to
//   any chat or channel." (14, NeutralForeground3);
// - "Add recipients *": a 535 x 33 picker on NeutralBackground5 (#F0F0F0).
//   People come from the directory, chats and channels from your list.
//   Suggestions are 50 px rows with a 32 px avatar and the match in bold.
//   Picks become pills (24 px avatar, name, dismiss). A group chat or channel
//   is a single choice. More than one person goes to a group chat;
// - "Message preview": a 535 x 168 box on NeutralBackground3 with a
//   NeutralStroke2 border and radius 6. It holds the optional note ("Add a
//   message (optional)"), the forward card and Emoji;
// - Cancel and Forward (96 x 32), Forward enabled once someone is picked.
Popup {
    id: root
    property var message: null
    signal forwardTo(var targets, string note)
    modal: true; focus: true
    width: 600; height: 487 + (multiPeople ? 24 : 0)
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }

    property var picked: []
    readonly property bool single: picked.some(p => p.kind === "chat")
    readonly property bool multiPeople: picked.filter(p => p.kind === "person").length > 1
    property string query: ""
    readonly property var people: (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).filter(p => !picked.some(x => x.oid === p.id))
    readonly property var chats: {
        const q = query.trim().toLowerCase()
        if (q.length < 1) return []
        const list = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
        return list.filter(c => !c.isSelf && !String(c.id).endsWith("@unq.gbl.spaces") && (c.name || "").toLowerCase().indexOf(q) >= 0 && !picked.some(x => x.id === c.id)).slice(0, 6)
    }
    readonly property var teamsChannels: {
        const q = query.trim().toLowerCase()
        if (q.length < 1) return []
        const out = []
        for (const t of (backend.teamsJson ? JSON.parse(backend.teamsJson) : []))
            for (const c of t.channels) if ((c.name + " " + t.name).toLowerCase().indexOf(q) >= 0) out.push({ id: c.id, name: c.name + " (" + t.name + ")" })
        return out.slice(0, 4)
    }
    readonly property var suggestions: query.trim().length === 0 ? []
        : people.map(p => ({ kind: "person", oid: p.id, name: p.name, sub: p.job_title || p.mail || "" }))
            .concat((picked.filter(p => p.kind === "person").length > 0 ? [] : chats).map(c => ({ kind: "chat", id: c.id, name: c.name, sub: "" })))
            .concat(picked.length > 0 ? [] : teamsChannels.map(c => ({ kind: "chat", id: c.id, name: c.name, sub: "" })))

    onOpened: { picked = []; query = ""; search.text = ""; note.text = ""; search.forceActiveFocus() }
    // Test hooks (--forward-test).
    function typeForTest(t) { search.text = t }
    function pickForTest(oid) { const s = suggestions.find(x => x.oid === oid); if (s) { picked = picked.concat([s]); search.text = "" } return !!s }
    function forwardForTest() { forwardTo(picked, note.text); close() }

    function bolded(name) {
        const q = root.query.trim()
        const i = name.toLowerCase().indexOf(q.toLowerCase())
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        return i < 0 || !q ? esc(name) : esc(name.slice(0, i)) + "<b>" + esc(name.slice(i, i + q.length)) + "</b>" + esc(name.slice(i + q.length))
    }

    Text { x: 33; y: 33; height: 28; verticalAlignment: Text.AlignVCenter; text: "Forward this message"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Text { x: 33; y: 61; height: 28; verticalAlignment: Text.AlignVCenter; text: "You can forward to any chat or channel."; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
    Row {
        x: 33; y: 110; height: 25; spacing: 4
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Add recipients"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "*"; font.family: theme.font; font.pixelSize: theme.small; color: theme.redForeground3 }
    }
    // Recipient picker
    Rectangle {
        id: pickerBox
        x: 33; y: 135; width: 535; height: root.picked.length > 0 ? 39 : 33; radius: 4
        color: theme.inputFilledDark
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand; visible: search.activeFocus }
        Flow {
            x: 12; y: root.picked.length > 0 ? 6 : 0; width: parent.width - 24; spacing: 4
            Repeater {
                model: root.picked
                Rectangle {
                    id: chip
                    required property var modelData
                    required property int index
                    width: 2 + 24 + 8 + chipName.implicitWidth + 4 + 12 + 6; height: 25; radius: 12.5
                    color: theme.surface
                    Avatar { x: 2; y: 0.5; size: 24; name: chip.modelData.name; photoId: chip.modelData.oid || ""; group: chip.modelData.kind === "chat" }
                    Text { id: chipName; x: 34; anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                    FluentIcon {
                        x: chipName.x + chipName.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: theme.textStrong
                        TapHandler { onTapped: { const p = root.picked.slice(); p.splice(chip.index, 1); root.picked = p; search.forceActiveFocus() } }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + modelData.name
                }
            }
            TextInput {
                id: search
                width: Math.max(40, pickerBox.width - 24 - (root.picked.length > 0 ? 160 * root.picked.length : 0))
                height: root.picked.length > 0 ? 25 : 33
                verticalAlignment: TextInput.AlignVCenter
                enabled: !root.single
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                onTextChanged: { root.query = text; backend.searchPeople(text) }
                Keys.onPressed: e => { if (e.key === Qt.Key_Backspace && text.length === 0 && root.picked.length > 0) { root.picked = root.picked.slice(0, -1); e.accepted = true } }
                Text { visible: !search.text && root.picked.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Enter name, email, group or tag"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Add recipients"
            }
        }
    }
    Row {
        visible: root.multiPeople
        x: 33; y: pickerBox.y + pickerBox.height + 6; spacing: 6
        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "info-16"; size: 16; color: theme.textSecondary }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Message will be forwarded to a group chat"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
    }
    Text { x: 33; y: 206 + (root.multiPeople ? 24 : 0) + (root.picked.length > 0 ? 6 : 0); height: 25; verticalAlignment: Text.AlignVCenter; text: "Message preview"; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
    // Preview: the note, the card, Emoji
    Rectangle {
        id: previewBox
        x: 33; y: 231 + (root.multiPeople ? 24 : 0) + (root.picked.length > 0 ? 6 : 0); width: 535; height: 168; radius: 6
        color: theme.inputFilled; border.color: theme.divider
        TextArea {
            id: note
            x: 1; y: 1; width: parent.width - 2; height: 38
            leftPadding: 12; topPadding: 9
            background: null
            wrapMode: TextArea.Wrap
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            placeholderText: "Add a message (optional)"; placeholderTextColor: theme.textSecondary
        }
        ForwardCard { x: 11; y: 47; maxWidth: 535 - 22; forward: root.message ? { sender_mri: root.message.sender_mri, sender_name: root.message.sender, arrival_ms: parseInt(root.message.id), html: root.message.html, text: root.message.text } : null }
        Rectangle {
            x: 494; y: 131; width: 32; height: 32; radius: 4
            color: emojiHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "emoji-16"; size: 16; color: theme.textStrong }
            HoverHandler { id: emojiHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: noteEmoji.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Emoji"
            EmojiPicker { id: noteEmoji; y: -height - 4; x: parent.width - width; onPicked: e => { note.insert(note.cursorPosition, e); close(); note.forceActiveFocus() } }
        }
    }
    // Footer
    Row {
        x: 359; y: previewBox.y + previewBox.height + 24; spacing: 16
        Rectangle {
            width: 96; height: 32; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            readonly property bool on: root.picked.length > 0
            width: 96; height: 32; radius: 4
            color: !on ? theme.bgDisabled : fwdHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Forward"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: parent.on ? "white" : theme.disabledStrong }
            HoverHandler { id: fwdHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.on; onTapped: { root.forwardTo(root.picked, note.text); root.close() } }
            Accessible.role: Accessible.Button
            Accessible.name: "Forward"
        }
    }
    // Suggestions under the picker
    Popup {
        id: suggest
        visible: root.opened && root.suggestions.length > 0 && search.activeFocus
        x: pickerBox.x; y: pickerBox.y + pickerBox.height + 2
        width: 535; padding: 4
        height: Math.min(6, root.suggestions.length) * 52 + 8
        background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
        contentItem: ListView {
            clip: true; spacing: 2
            model: root.suggestions
            delegate: Rectangle {
                id: opt
                required property var modelData
                width: 526.7; height: 50; radius: 4
                color: optHover.hovered ? theme.menuHover : "transparent"
                Avatar { x: 12; y: 9; size: 32; name: opt.modelData.name; photoId: opt.modelData.oid || ""; group: opt.modelData.kind === "chat" }
                Column {
                    x: 60; anchors.verticalCenter: parent.verticalCenter
                    Text { text: root.bolded(opt.modelData.name); textFormat: Text.StyledText; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
                    Text { visible: !!opt.modelData.sub; text: root.bolded(opt.modelData.sub); textFormat: Text.StyledText; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.picked = root.picked.concat([opt.modelData]); search.text = ""; search.forceActiveFocus() } }
                Accessible.role: Accessible.ListItem
                Accessible.name: opt.modelData.name + (opt.modelData.sub ? ", " + opt.modelData.sub : "")
            }
        }
    }
}
