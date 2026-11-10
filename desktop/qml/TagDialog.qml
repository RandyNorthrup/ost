import QtQuick
import QtQuick.Controls.Basic

// Teams' tag dialogs (Manage team ▸ Tags, measured on winpc 2026-11-09):
// 600 wide, padding 27 32 32, radius 8, the title 18/25.7 bold.
// - Create a new tag / Create a copy (594.7 tall): "Tag name" * with
//   "n/40" at the right, its filled field ("Letters, numbers, spaces and
//   emojis are allowed"), "Tag description" and its 52 tall field ("Let
//   people know what this tag is all about"), "Enter name of a member" *
//   and its picker ("Enter name", an underline), the picked people under
//   it; Cancel / Create. A copy starts as "{name}_copy" with the tag's
//   people.
// - Edit tag (364.7): name and description; Save once something changed.
// - Add people (594.7): the picker alone; Add.
// - Are you sure? (164.7): You're about to delete the "{name}" tag.; Cancel /
//   Delete tag.
// The picker searches the team's members (people already in the tag are
// left out): 43 tall rows with a 28 px picture, the name and e-mail; "We
// couldn't find any matches." otherwise.
Popup {
    id: dlg
    property string teamId: ""
    property string teamThread: ""
    property string mode: "create"
    property var tag: null
    property var existing: []
    property var picked: []
    property var results: []
    property string searched: ""
    readonly property string title: mode === "edit" ? "Edit tag" : mode === "add" ? "Add people" : mode === "delete" ? "Are you sure?" : "Create a new tag"
    readonly property bool hasName: mode === "create" || mode === "edit"
    readonly property bool hasPicker: mode === "create" || mode === "add"
    readonly property bool valid: {
        if (mode === "delete") return true
        if (mode === "add") return picked.length > 0
        const n = nameField.text.trim()
        if (!n || n.length > 40 || descField.text.length > 200) return false
        if (mode === "edit") return n !== tag.name || descField.text.trim() !== (tag.description || "")
        return picked.length > 0
    }

    function reset() {
        picked = []; results = []; searched = ""; picker.text = ""
        nameField.text = ""; descField.text = ""
    }
    function startCreate(people) { mode = "create"; tag = null; existing = []; reset(); open(); nameField.forceActiveFocus() }
    function startCopy(t, people) {
        mode = "create"; tag = t; existing = []; reset()
        nameField.text = (t.name + "_copy").slice(0, 40)
        descField.text = t.description || ""
        // The tag's people: names come with the members list when it was read.
        const known = people || []
        picked = (t.member_ids || []).map(m => known.find(p => p.mri === m) || { mri: m, name: "", mail: "" })
        if (!people) backend.channelAction("tag-members", teamId, teamThread, t.id)
        open(); nameField.forceActiveFocus()
    }
    function startEdit(t) { mode = "edit"; tag = t; reset(); nameField.text = t.name; descField.text = t.description || ""; open(); nameField.forceActiveFocus() }
    function startAdd(t, people) { mode = "add"; tag = t; existing = (people || []).map(p => p.mri.toLowerCase()); reset(); open(); picker.forceActiveFocus() }
    function startDelete(t) { mode = "delete"; tag = t; reset(); open() }
    function submit() {
        if (!valid) return
        const act = (op, a) => backend.channelAction(op, teamId, teamThread, JSON.stringify(a))
        if (mode === "create") act("tag-create", { name: nameField.text.trim(), description: descField.text.trim(), members: picked.map(p => p.mri) })
        else if (mode === "edit") act("tag-update", { id: tag.id, version: tag.version, name: nameField.text.trim(), description: descField.text.trim() })
        else if (mode === "add") act("tag-add-members", { id: tag.id, name: tag.name, members: picked.map(p => p.mri) })
        else if (mode === "delete") backend.channelAction("tag-delete", teamId, teamThread, tag.id)
        close()
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: if (picker.text.trim()) backend.channelAction("tag-member-search", dlg.teamId, dlg.teamThread, picker.text.trim())
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            if (!dlg.opened) return
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "tag-members" && r.ok && dlg.tag && r.data.tag === dlg.tag.id && dlg.mode === "create") {
                // A copy's people, named.
                const people = r.data.people || []
                dlg.picked = dlg.picked.map(p => people.find(x => x.mri === p.mri) || p)
                return
            }
            if (r.op !== "tag-member-search" || r.channel !== dlg.teamThread || !r.ok || r.data.query.trim() !== picker.text.trim()) return
            dlg.searched = r.data.query
            dlg.results = (r.data.people || []).filter(p => dlg.existing.indexOf(p.mri.toLowerCase()) < 0 && !dlg.picked.some(x => x.mri === p.mri))
        }
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 600
    height: mode === "delete" ? 164.7 : mode === "edit" ? 364.7 : 594.7
    topPadding: 27; leftPadding: 32; rightPadding: 32; bottomPadding: 32
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }

    Item {
        anchors.fill: parent
        Text {
            text: dlg.title
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
            lineHeight: 25.7; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Text {
            visible: dlg.mode === "delete"
            y: 33.8; width: parent.width; wrapMode: Text.Wrap
            text: "You're about to delete the \"" + (dlg.tag ? dlg.tag.name : "") + "\" tag."
            font.family: theme.font; font.pixelSize: 14
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.pick("#0F0F0F", "#FFFFFF")
        }

        // Name and description.
        Label { visible: dlg.hasName; y: 33.8; text: "Tag name"; mandatory: true }
        // Counters show while their field has focus.
        Text {
            visible: dlg.hasName && nameField.activeFocus
            anchors.right: parent.right; y: 33.8
            text: nameField.text.length + "/40"
            font.family: theme.font; font.pixelSize: 12
            color: theme.pick("#0F0F0F", "#FFFFFF")
        }
        Rectangle {
            visible: dlg.hasName
            x: 0.7; y: 58.4; width: 534.7; height: 32; radius: 4
            color: theme.inputFilled
            TextInput {
                id: nameField
                x: 12; width: parent.width - 14; anchors.verticalCenter: parent.verticalCenter
                maximumLength: 40
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Keys.onReturnPressed: dlg.submit()
                Text { visible: !nameField.text; anchors.verticalCenter: parent.verticalCenter; text: "Letters, numbers, spaces and emojis are allowed"; font: nameField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Tag name"
            }
            Rectangle { visible: nameField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        }
        Label { visible: dlg.hasName; y: dlg.mode === "edit" ? 109.8 : 101.8; text: "Tag description" }
        Text {
            visible: dlg.hasName && descField.activeFocus
            anchors.right: parent.right; y: dlg.mode === "edit" ? 109.8 : 101.8
            text: descField.text.length + "/200"
            font.family: theme.font; font.pixelSize: 12
            color: theme.pick("#0F0F0F", "#FFFFFF")
        }
        Rectangle {
            visible: dlg.hasName
            x: 0.7; y: dlg.mode === "edit" ? 134.4 : 126.4; width: 534.7; height: 52; radius: 4
            color: theme.inputFilled
            TextEdit {
                id: descField
                x: 12; y: 6; width: parent.width - 24; height: parent.height - 12
                wrapMode: TextEdit.Wrap
                onTextChanged: if (text.length > 200) { text = text.slice(0, 200); cursorPosition = 200 }
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                selectByMouse: true
                Text { visible: !descField.text; text: "Let people know what this tag is all about"; font: descField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText
                Accessible.name: "Tag description"
            }
            Rectangle { visible: descField.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
        }

        // Members.
        Label { visible: dlg.hasPicker; y: dlg.mode === "add" ? 33.8 : 193.1; text: "Enter name of a member"; mandatory: true }
        Item {
            id: pickerBox
            visible: dlg.hasPicker
            y: dlg.mode === "add" ? 58.4 : 217.8; width: 536; height: 20.7
            TextInput {
                id: picker
                width: parent.width; height: 18.7
                font.family: theme.font; font.pixelSize: 14
                color: theme.text
                clip: true
                onTextChanged: { dlg.results = []; dlg.searched = ""; if (text.trim()) debounce.restart(); else debounce.stop() }
                Keys.onReturnPressed: if (dlg.results.length) dlg.pickPerson(dlg.results[0])
                Text { visible: !picker.text; text: "Enter name"; font: picker.font; color: theme.textSecondary }
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Enter name of a member"
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: picker.activeFocus ? 2 : 0.67; color: picker.activeFocus ? theme.brand : theme.textSecondary }
        }
        Flickable {
            visible: dlg.hasPicker
            y: pickerBox.y + 31.3; width: parent.width; height: parent.height - y - 48
            contentHeight: pickedCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: pickedCol
                width: parent.width
                spacing: 8
                Repeater {
                    model: dlg.picked
                    Item {
                        id: pickedRow
                        required property var modelData
                        width: pickedCol.width; height: 34
                        Avatar { y: 1; size: 32; name: pickedRow.modelData.name || "?"; photoId: pickedRow.modelData.mri }
                        Text { x: 42; y: -1; width: parent.width - 90; elide: Text.ElideRight; text: pickedRow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#0F0F0F", "#FFFFFF") }
                        Text { x: 42; y: 19; width: parent.width - 90; elide: Text.ElideRight; text: pickedRow.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                        Rectangle {
                            x: parent.width - 32; y: 1.3; width: 32; height: 31.3; radius: 4
                            color: "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: rmHover.hovered ? theme.brand : theme.textStrong }
                            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: dlg.picked = dlg.picked.filter(p => p.mri !== pickedRow.modelData.mri) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove " + pickedRow.modelData.name
                        }
                    }
                }
            }
        }
        // Matches.
        Item {
            visible: dlg.hasPicker && picker.activeFocus && picker.text.trim().length > 0 && (dlg.results.length > 0 || dlg.searched.length > 0)
            y: pickerBox.y + 21.3; width: 536; height: Math.min(300, matchCol.implicitHeight + 14)
            z: 5
            FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
            Column {
                id: matchCol
                y: 8; width: parent.width
                Text {
                    visible: dlg.results.length === 0
                    x: 12.3; height: 30.7; verticalAlignment: Text.AlignVCenter
                    text: "We couldn't find any matches."
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.textSecondary
                }
                Repeater {
                    model: dlg.results
                    Rectangle {
                        id: match
                        required property var modelData
                        x: 0.7; width: 534.7; height: 43
                        color: matchHover.hovered ? theme.menuHover : "transparent"
                        Avatar { x: 11.6; y: 7.4; size: 28; name: match.modelData.name || "?"; photoId: match.modelData.mri }
                        Text { x: 51.6; y: 4.6; width: parent.width - 60; elide: Text.ElideRight; text: match.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                        Text { x: 51.6; y: 22.3; width: parent.width - 60; elide: Text.ElideRight; text: match.modelData.mail || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        HoverHandler { id: matchHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dlg.pickPerson(match.modelData) }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: match.modelData.name
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 8
            DialogButton { text: "Cancel"; onClicked: dlg.close() }
            DialogButton {
                text: dlg.mode === "edit" ? "Save" : dlg.mode === "add" ? "Add" : dlg.mode === "delete" ? "Delete tag" : "Create"
                primary: true; enabled: dlg.valid
                onClicked: dlg.submit()
            }
        }
    }
    function pickPerson(p) {
        if (!picked.some(x => x.mri === p.mri)) picked = picked.concat([p])
        picker.text = ""; results = []; searched = ""
        picker.forceActiveFocus()
    }

    component Label: Row {
        property string text
        property bool mandatory: false
        spacing: 4
        Text { text: parent.text; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        Text { visible: parent.mandatory; text: "*"; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3 }
    }
    component DialogButton: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(96, btnText.implicitWidth + 40); height: 32; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (btnHover.hovered ? theme.brandHover : theme.brandFill) : (btnHover.hovered ? theme.menuHover : theme.surface)
        border.color: primary || !enabled ? "transparent" : theme.stroke; border.width: 0.67
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.text
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !btn.enabled ? theme.disabledStrong : btn.primary ? theme.textOnBrand : theme.text
        }
        HoverHandler { id: btnHover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: text
    }

    // Test hooks.
    function fillForTest(name, desc) { nameField.text = name; descField.text = desc }
    function searchForTest(q) { picker.forceActiveFocus(); picker.text = q }
}
