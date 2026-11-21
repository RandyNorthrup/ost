import QtQuick
import QtQuick.Controls.Basic

// Teams' "Save as a template" (the recap's Custom summary: Create
// template's Save and Apply, and a template's Rename; Teams 26304's
// customize-notes panel, an alert dialog): 41.7 % of the window wide (at
// most 600), the Fluent dialog's padding 24 and 20/28 title with its Close
// (32, 20 from the right); "Template name" (10 above, 5 below) over a
// 35-tall input (padding 0 5, a 1 px NeutralStroke1 edge, radius 4, a 2 px
// brand line while focused), Teams' message under it (12,
// StatusDangerForeground1, 20 tall at least), then Cancel and Save.
// The name is checked as you type: none of " * : < > ? / \ |, not one of
// your templates' names; Save says "This field cannot be blank" for none
// and is off while there's a message or no name.
Popup {
    id: root
    /// Your templates ({id, name}) a name mustn't repeat.
    property var templates: []
    property string error: ""
    signal confirmed(string name)
    function openFor(name, list) {
        templates = list || []
        field.text = name || ""
        error = ""
        open()
        field.forceActiveFocus()
    }
    function check(t) {
        if (/["*:<>?\/\\|]/.test(t)) return qsTr("Please enter a name that doesn't include any of these characters: \" * : < > ? / \\ |")
        return templates.some(x => String(x.name || "").trim() === t.trim()) ? qsTr("Template name already exists!") : ""
    }
    function save() {
        if (field.text.trim().length === 0) { error = qsTr("This field cannot be blank", "meetingRecap:k2xmqdy8"); return }
        if (error) return
        const name = field.text.trim()
        close()
        confirmed(name)
    }
    parent: Overlay.overlay
    modal: true; focus: true
    z: 10
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    width: Math.min(parent ? parent.width * 0.417 : 600, 600)
    height: 216
    padding: 0
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    Text {
        x: 24; y: 24; width: root.width - 48 - 40; height: 28
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        text: qsTr("Save as a template")
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
        Accessible.role: Accessible.Heading; Accessible.name: text
    }
    Rectangle {
        id: closeBtn
        x: root.width - 20 - 32; y: 22; width: 32; height: 32; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.onFill(closeBtn, theme.textStrong) }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
    }
    Text {
        x: 24; y: 70; height: 20; verticalAlignment: Text.AlignVCenter
        text: qsTr("Template name", "meetingRecap:k1244ssdf")
        font.family: theme.font; font.pixelSize: 14; color: theme.text
    }
    Rectangle {
        x: 24; y: 95; width: root.width - 48; height: 35; radius: 4
        color: theme.surface
        border.color: theme.stroke; border.width: 1
        Rectangle { visible: field.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brandForeground1 }
        TextInput {
            id: field
            x: 5; width: parent.width - 10; anchors.verticalCenter: parent.verticalCenter
            clip: true
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            selectionColor: theme.selectionFill; selectedTextColor: theme.text
            onTextEdited: root.error = root.check(text)
            Text {
                visible: !field.text
                text: qsTr("Give your template a name", "meetingRecap:k55y38ci7")
                font: field.font; color: theme.textTertiary
            }
            Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Template name", "meetingRecap:k1244ssdf")
        }
    }
    Text {
        x: 24; y: 132; width: root.width - 48
        wrapMode: Text.Wrap
        text: root.error
        font.family: theme.font; font.pixelSize: 12; color: theme.pick("#B10E1C", "#DC626D", "#FFFFFF")
        Accessible.role: Accessible.AlertMessage; Accessible.name: text
    }
    Row {
        anchors { right: parent.right; rightMargin: 24 }
        y: 160; spacing: 8
        DialogButton { label: qsTr("Cancel"); onClicked: root.close() }
        DialogButton { label: qsTr("Save"); primary: true; enabled: !root.error && field.text.trim().length > 0; onClicked: root.save() }
    }

    // Fluent's medium button (32 tall, at least 96 wide, padding 0 12,
    // 14/600): secondary, or primary (brand; disabled greys).
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        signal clicked()
        width: Math.max(96, dbText.implicitWidth + 24); height: 32; radius: 4
        color: !enabled ? theme.bgDisabled : primary ? (dbHover.hovered ? theme.brandHover : theme.brandFill) : (dbHover.hovered ? theme.menuHover : theme.surface)
        border.color: !enabled ? theme.pick("#E0E0E0", "#424242", "#3FF23F") : primary ? "transparent" : theme.stroke; border.width: primary && enabled ? 0 : 1
        Text {
            id: dbText
            anchors.centerIn: parent
            text: db.label
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: !db.enabled ? theme.disabled : theme.onFill(db, db.primary ? theme.textOnBrand : theme.text)
        }
        HoverHandler { id: dbHover; enabled: db.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: db.enabled; onTapped: db.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: label
    }

    // The harness's (--recap-window-test=template) typing.
    function typeForTest(t) { field.text = t; root.error = root.check(t) }
    function stateForTest() { return { name: field.text, error: root.error, opened: root.opened } }
}
