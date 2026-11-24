import QtQuick
import QtQuick.Controls.Basic

// Teams' Share recap access (the recap card's and the recap window's
// Share > Share recap access), and its Copy link.
// Share recap access (measured): 600 x 280, the title 20/28 600, "People
// you specify will have access to the recap" 14 #616161, "Share access
// with" (12) over the people picker (#F5F5F5, "Enter name, email,
// group or tag"), "Notify them in chat" ticked, Give access (97 x 31.3).
Popup {
    id: root
    /// The recap shared (api::recaps::RecapRef).
    property var recap: ({})
    readonly property string tag: "recapshare" + Math.floor(Math.random() * 1e9) + ":"
    property var picked: []
    property bool notify: true
    property bool busy: false
    property string error: ""
    property var suggestions: []
    function openFor(r) { recap = r; picked = []; notify = true; busy = false; error = ""; suggestions = []; query.text = ""; open(); query.forceActiveFocus() }
    parent: Overlay.overlay
    modal: true
    anchors.centerIn: parent
    width: 600; height: 280; padding: 0
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Text { x: 32.7; y: 32.7; text: qsTr("Share recap access"); lineHeight: 28; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
    Text { x: 32.7; y: 60.7; text: qsTr("People you specify will have access to the recap"); lineHeight: 28; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
    IconBtn { x: 527.3; y: 32.7; width: 40; height: 39.3; icon: "dismiss-20"; tip: qsTr("Close"); onClicked: root.close() }
    Text { x: 32.7; y: 109.7; text: qsTr("Share access with"); lineHeight: 20; lineHeightMode: Text.FixedHeight; font.family: theme.font; font.pixelSize: 12; color: theme.text }
    Rectangle {
        x: 32.7; y: 135.3; width: 534.7; height: 32; radius: 4
        color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: query.activeFocus ? 2 : 0; color: theme.brand }
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Repeater {
                model: root.picked
                Rectangle {
                    required property var modelData
                    required property int index
                    height: 24; width: chipText.implicitWidth + 30; radius: 12; color: theme.surface
                    Text { id: chipText; x: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    IconBtn { x: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; icon: "dismiss-12"; tip: qsTr("Remove"); onClicked: root.picked = root.picked.filter((x, i) => i !== index) }
                }
            }
            TextInput {
                id: query
                width: 300; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !query.text && root.picked.length === 0; text: qsTr("Enter name, email, group or tag"); font: query.font; color: theme.textSecondary }
                onTextChanged: if (text.trim().length > 1) backend.eventsRequest("searchPeople", root.tag + "people", JSON.stringify({ kind: "people", query: text.trim() }))
                Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Share access with")
            }
        }
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id !== root.tag + "people") return
            let v = []
            try { v = JSON.parse(json) } catch (e) {}
            root.suggestions = Array.isArray(v) ? v : (v.people || [])
        }
    }
    ListView {
        visible: query.text.trim().length > 1 && count > 0
        x: 32.7; y: 167.3; width: 534.7; height: Math.min(contentHeight, 260); z: 5
        clip: true
        model: root.suggestions
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width; height: 52
            color: sh.hovered ? theme.rowHover : theme.menu
            Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 32; name: modelData.name || modelData.displayName || "" }
            Column {
                x: 64; anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.name || modelData.displayName || ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { text: modelData.email || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
            }
            HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    const oid = modelData.object_id || ""
                    if (oid && !root.picked.some(p => p.oid === oid)) root.picked = root.picked.concat([{ oid: oid, name: modelData.name || modelData.displayName || "" }])
                    query.text = ""
                }
            }
        }
    }
    CheckBox {
        x: 32.7; y: 206; checked: root.notify
        onToggled: root.notify = checked
        text: qsTr("Notify them in chat")
        font.family: theme.font; font.pixelSize: 14
    }
    Text { visible: !!root.error; x: 32.7; y: 244; text: root.error; font.family: theme.font; font.pixelSize: 12; color: theme.danger }
    Rectangle {
        readonly property bool on: root.picked.length > 0 && !root.busy
        x: 470.3; y: 206.3; width: 97; height: 31.3; radius: 4
        color: on ? (gh.hovered ? theme.brandHover : theme.brand) : theme.pick("#F0F0F0", "#333333", "#000000")
        Text { anchors.centerIn: parent; text: qsTr("Give access"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? "#FFFFFF" : theme.pick("#BDBDBD", "#5C5C5C", "#3FF23F") }
        HoverHandler { id: gh; enabled: parent.on; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: parent.on
            onTapped: {
                root.busy = true; root.error = ""
                const a = new Date(root.recap.start_ms || 0), b = new Date(root.recap.end_ms || 0)
                const day = a.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                backend.eventsRequest("recapShare", root.tag + "share", JSON.stringify({ recap: root.recap, people: root.picked.map(p => p.oid), notify: root.notify,
                    day: day, when: day + " · " + theme.time(a) + " - " + theme.time(b) }))
            }
        }
        Accessible.role: Accessible.Button; Accessible.name: qsTr("Give access")
    }

    // Copy link: Teams' recap link (the meeting it belongs to is looked up
    // first).
    function copyLink(r) {
        recap = r
        backend.eventsRequest("recapLink", root.tag + "link", JSON.stringify({ recap: r }))
    }
    Connections {
        target: backend
        function onEventsReply(id, json) {
            if (id.indexOf(root.tag) !== 0) return
            let v = {}
            try { v = JSON.parse(json) } catch (e) {}
            const what = id.slice(root.tag.length)
            if (what === "link") {
                if (v.link) { backend.copyText(v.link); console.info("RECAP link copied") }
            } else if (what === "share") {
                root.busy = false
                if (v.error) { root.error = v.error; return }
                root.close()
                console.info("RECAP shared", JSON.stringify(v.given || []))
            }
        }
    }

    component IconBtn: Rectangle {
        id: ib
        property string icon
        property string tip
        signal clicked()
        radius: 4
        color: ibh.hovered ? theme.rowHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: 20; color: theme.onFill(ib, theme.pick("#424242", "#D6D6D6", "#FFFFFF")) }
        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        ToolTip.visible: ibh.hovered && !!tip
        ToolTip.text: tip
        ToolTip.delay: 500
        Accessible.role: Accessible.Button; Accessible.name: tip
    }
}
