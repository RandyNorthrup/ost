import QtQuick
import QtQuick.Controls

// Teams' "Share someone's contact info" (chat-share-contact-popup,
// measured on winpc): pick people by name; OK puts each one's contact card
// in the message. They aren't @mentioned or notified.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 402
    height: buttons.y + 31.3 + 24.7
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
    Overlay.modal: Rectangle { color: "transparent" }

    /// The people picked: [{mri, name}].
    property var picked: []
    /// The current results' highlighted row.
    property int current: 0
    signal accepted(var people)

    function start() {
        picked = []
        field.text = ""
        current = 0
        open()
        field.forceActiveFocus()
    }
    readonly property string query: field.text.trim()
    readonly property var results: {
        if (query.length < 2 || !backend.peopleJson) return []
        const list = JSON.parse(backend.peopleJson)
        return list.filter(p => !root.picked.some(x => x.mri === "8:orgid:" + p.id))
            .map(p => ({ mri: "8:orgid:" + p.id, name: p.name, sub: p.job_title || p.mail || "" }))
    }
    onQueryChanged: { current = 0; if (query.length >= 2) backend.searchPeople(query) }
    function pick(p) {
        if (!p) return
        picked = picked.concat([{ mri: p.mri, name: p.name }])
        field.text = ""
        field.forceActiveFocus()
    }
    // The typed part bold, as Teams' picker shows it.
    function bold(s, q) {
        const t = String(s || "")
        const i = q ? t.toLowerCase().indexOf(q.toLowerCase()) : -1
        const esc = x => x.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        if (i < 0) return esc(t)
        return esc(t.slice(0, i)) + "<b>" + esc(t.slice(i, i + q.length)) + "</b>" + esc(t.slice(i + q.length))
    }

    Text {
        x: 16.7; y: 16.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "Share someone's contact info in the message"
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    // The tag picker: #F5F5F5, rounded 4, 12 in; a brand line under it
    // while it has focus.
    Rectangle {
        id: control
        x: 16.7; y: 46.7; width: 368.7
        height: root.picked.length > 0 ? 38.7 : 33.3
        radius: 4
        color: theme.pick("#F5F5F5", "#1F1F1F")
        Flow {
            id: tags
            x: 12.6; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: root.picked
                // A picked person: a white pill, their 24 px picture, the
                // name and a dismiss (x).
                Rectangle {
                    required property var modelData
                    required property int index
                    width: 31 + nameText.implicitWidth + 4 + 19; height: 25.3; radius: height / 2
                    color: theme.surface
                    Avatar { x: 1; anchors.verticalCenter: parent.verticalCenter; size: 24; name: parent.modelData.name; photoId: parent.modelData.mri }
                    Text { id: nameText; x: 33; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                    FluentIcon { x: nameText.x + nameText.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: theme.textStrong }
                    TapHandler { onTapped: root.picked = root.picked.filter((_, i) => i !== index) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + modelData.name
                }
            }
            TextInput {
                id: field
                width: Math.max(80, tags.width - (root.picked.length ? 160 : 0))
                height: 32
                verticalAlignment: TextInput.AlignVCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                selectByMouse: true
                Text {
                    visible: !field.text && root.picked.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Enter name"
                    font: field.font; color: theme.pick("#424242", "#D6D6D6")
                }
                Keys.onDownPressed: if (root.results.length) root.current = (root.current + 1) % root.results.length
                Keys.onUpPressed: if (root.results.length) root.current = (root.current - 1 + root.results.length) % root.results.length
                Keys.onReturnPressed: if (root.results.length) root.pick(root.results[root.current])
                Keys.onEnterPressed: if (root.results.length) root.pick(root.results[root.current])
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && !field.text && root.picked.length) { root.picked = root.picked.slice(0, -1); event.accepted = true }
                }
                Accessible.name: "Enter name"
            }
        }
        Rectangle {
            visible: field.activeFocus
            anchors.bottom: parent.bottom; width: parent.width; height: 2
            color: theme.brand
        }
    }
    Text {
        x: 24.7; y: control.y + control.height + 8.7; height: 20; verticalAlignment: Text.AlignVCenter
        text: "They won't be @mentioned or notified"
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    Row {
        id: buttons
        x: 177.3; y: control.y + control.height + 54
        spacing: 8
        Rectangle {
            width: 96; height: 31.3; radius: 4
            color: cancelHover.hovered ? theme.menuHover : theme.surface; border.color: theme.stroke
            Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel"
        }
        Rectangle {
            readonly property bool can: root.picked.length > 0
            width: 96; height: 31.3; radius: 4
            color: !can ? theme.pick("#F0F0F0", "#141414") : okHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "OK"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.can ? "white" : theme.pick("#BDBDBD", "#5C5C5C") }
            HoverHandler { id: okHover; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: { const p = root.picked; root.close(); root.accepted(p) } }
            Accessible.role: Accessible.Button
            Accessible.name: "OK"
        }
    }
    // The results under the picker: white, rounded 4, a menu shadow; rows
    // 50 tall from 4 in, 2 apart.
    Item {
        visible: root.results.length > 0
        x: control.x; y: control.y + control.height
        width: 368.7; height: 4 + root.results.length * 52 - 2 + 4
        z: 10
        FluentSurface { anchors.fill: parent; depth: 16; radius: 4; color: theme.surface }
        Column {
            x: 4; y: 4; spacing: 2
            Repeater {
                model: root.results
                Rectangle {
                    required property var modelData
                    required property int index
                    width: 346.7; height: 50; radius: 4
                    color: index === root.current || rowHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : "transparent"
                    Avatar { x: 12; y: 9; size: 32; name: parent.modelData.name; photoId: parent.modelData.mri }
                    Text { x: 60; y: 6.5; height: 20; verticalAlignment: Text.AlignVCenter; width: 280; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.modelData.name, root.query); font.family: theme.font; font.pixelSize: 14; color: theme.pick("#424242", "#D6D6D6") }
                    Text { x: 60; y: 27.5; height: 16; verticalAlignment: Text.AlignVCenter; width: 280; elide: Text.ElideRight; textFormat: Text.StyledText; text: root.bold(parent.modelData.sub, root.query); font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pick(parent.modelData) }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                }
            }
        }
    }
    // Test hooks.
    function typeForTest(t) { field.text = t }
    function pickFirstForTest() { if (results.length) pick(results[0]) }
    function okForTest() { const p = picked; close(); accepted(p) }
}
