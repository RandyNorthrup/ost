import QtQuick

// Teams' people picker in its small dialogs (Fluent TagPicker, measured on
// winpc in Share someone's contact info and Add): a #F5F5F5 box, rounded 4,
// 12 in, a brand line under it while focused; picked people are white
// pills (a 24 px picture, the name, a dismiss); matches drop down under it.
Item {
    id: root
    width: 368.7
    height: control.height
    property string placeholder: "Enter name"
    /// The people picked: [{mri, name}].
    property var picked: []
    /// MRIs not to offer (already in the chat).
    property var exclude: []
    property int current: 0
    readonly property string query: field.text.trim()
    readonly property var results: {
        if (query.length < 2 || !backend.peopleJson) return []
        const list = JSON.parse(backend.peopleJson)
        return list.map(p => ({ mri: "8:orgid:" + p.id, name: p.name, sub: p.job_title || p.mail || "" }))
            .filter(p => !root.picked.some(x => x.mri === p.mri) && root.exclude.indexOf(p.mri) < 0)
    }
    onQueryChanged: { current = 0; if (query.length >= 2) backend.searchPeople(query) }
    function reset() { picked = []; field.text = ""; current = 0 }
    function focusField() { field.forceActiveFocus() }
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

    Rectangle {
        id: control
        width: parent.width
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
                    text: root.placeholder
                    font: field.font; color: theme.pick("#424242", "#D6D6D6")
                }
                Keys.onDownPressed: if (root.results.length) root.current = (root.current + 1) % root.results.length
                Keys.onUpPressed: if (root.results.length) root.current = (root.current - 1 + root.results.length) % root.results.length
                Keys.onReturnPressed: if (root.results.length) root.pick(root.results[root.current])
                Keys.onEnterPressed: if (root.results.length) root.pick(root.results[root.current])
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && !field.text && root.picked.length) { root.picked = root.picked.slice(0, -1); event.accepted = true }
                }
                Accessible.name: root.placeholder
            }
        }
        Rectangle {
            visible: field.activeFocus
            anchors.bottom: parent.bottom; width: parent.width; height: 2
            color: theme.brand
        }
    }
    // The matches: white, rounded 4, a menu shadow; rows 50 tall from 4 in,
    // 2 apart, the active one #F5F5F5.
    Item {
        visible: root.results.length > 0
        y: control.height
        width: root.width; height: 4 + root.results.length * 52 - 2 + 4
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
    function typeForTest(t) { field.text = t }
    function pickFirstForTest() { if (results.length) pick(results[0]) }
}
