import QtQuick
import QtQuick.Controls.Basic

// OneDrive's share dialog as Teams opens it (Share outside Teams, Files'
// Share), drawn natively over SharePoint's sharing service; measured on
// winpc 2026-11-11 (docs/spec/onedrive-share.md). Views: the share form,
// Link settings, Manage Access (People / Groups / Links), a person's Access
// summary, and the "You've invited" confirmation.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 480
    height: view === "manage" || view === "access" ? 650 : content.height
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }

    // OneDrive's colours.
    readonly property color ink: theme.pick("#252424", "#F3F2F1")
    readonly property color soft: theme.pick("#605E5C", "#C8C6C4")
    readonly property color edge: theme.pick("#C8C8C8", "#605E5C")
    readonly property color accent: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color rule: theme.pick("#F3F2F1", "#3B3A39")

    /// The file: {site, list, item}, its name and type.
    property var item: null
    property string fileName: ""
    property string fileType: ""
    property var info: null
    property string view: "main"
    // The form.
    property var picked: []
    property string query: ""
    property var suggestions: []
    property bool sendEdit: true
    property string message: ""
    property bool sending: false
    property string copied: ""
    property string error: ""
    // The link Copy link makes: scope (0 anyone, 1 organisation, 2 people
    // you choose, 3 existing access), edit, expiration (ISO) and password.
    property int linkScope: 1
    property bool linkEdit: false
    property string expiration: ""
    property string password: ""
    // Link settings' choices before Apply.
    property int pendScope: 1
    property bool pendEdit: false
    property string pendExpiration: ""
    property string pendPassword: ""
    // Manage Access.
    property string tab: "people"
    property string filter: ""
    property var person: null
    property int personRole: 0
    property var invited: []
    property bool invitedEdit: true
    // A question over the dialog: {title, text, ok, run}.
    property var ask: null
    /// Link settings alone, for Teams' "Share this file" (its file card's
    /// link line, Give access): no Back, "People currently in this chat"
    /// (scope 4) among the choices, and Apply hands the choice back.
    property bool chatMode: false
    signal linkChosen(int scope, bool edit, string expiration, string password)
    /// Anyone but the owners has access.
    readonly property bool shared: !!info && (info.links.length > 0 || info.people.some(p => p.role !== 3))

    function openLinkSettings(itemRef, name, type, scope, edit, expiry, pass) {
        openFor(itemRef, name, type)
        chatMode = true
        pendScope = scope; pendEdit = edit; pendExpiration = expiry || ""; pendPassword = pass || ""
        view = "settings"
    }
    function openFor(itemRef, name, type) {
        chatMode = false
        item = itemRef; fileName = name || ""; fileType = type || ""
        info = null; view = "main"; picked = []; query = ""; suggestions = []; message = ""; copied = ""; error = ""
        sending = false; tab = "people"; filter = ""; person = null; ask = null; expiration = ""; password = ""
        open()
        load()
    }
    function load() { backend.shareAction("info", JSON.stringify(item), "{}") }
    Connections {
        target: backend
        function onShareDone(op, result, error) {
            if (!root.opened) return
            const v = result ? JSON.parse(result) : null
            if (op === "info") {
                if (error) { root.error = error; return }
                const first = !root.info
                root.info = v
                if (first) {
                    root.linkScope = v.default_existing ? 3 : v.default_scope
                    root.linkEdit = v.default_edit
                    root.sendEdit = true
                }
            } else if (op === "people") {
                if (v && v.query === root.query.trim()) root.suggestions = v.people.filter(p => !root.picked.some(q => q.Key === p.Key))
            } else if (op === "send") {
                root.sending = false
                if (error) { root.error = error; return }
                root.view = "invited"
                root.load()
            } else if (op === "link") {
                if (error) { root.error = error; return }
                backend.copyText(v.url)
                root.copied = root.linkSentence(root.linkScope, root.linkEdit, false)
                root.load()
            } else if (op === "role" || op === "unlink" || op === "stop") {
                if (error) root.error = error
                root.load()
            }
        }
    }

    // The organisation's name as OneDrive shortens it (more than 24
    // characters: the first and last 12).
    function org() { const n = info ? info.tenant : ""; return n.length > 24 ? n.slice(0, 12) + "..." + n.slice(-12) : n }
    function linkSentence(scope, edit, full) {
        const can = edit ? "edit" : "view"
        if (scope === 3) return "People with existing access can use the link."
        if (scope === 0) return "Anyone with the link can " + can + "."
        if (scope === 1) return "People in " + (full ? (info ? info.tenant : "") : "your organization") + " with the link can " + can + "."
        return "Only the people you specified can " + can + "."
    }
    // A name shortened in the middle to fit, as OneDrive writes it ("...").
    TextMetrics { id: tm; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; elide: Text.ElideMiddle }
    function middle(text, width, size) {
        tm.font.pixelSize = size; tm.text = text; tm.elideWidth = width
        return tm.elidedText.replace("…", "...")
    }
    function copyLink() {
        error = ""
        if (linkScope === 3) {
            if (!info) return
            backend.copyText(info.direct_url)
            copied = linkSentence(3, false, false)
            return
        }
        backend.shareAction("link", JSON.stringify(item), JSON.stringify({ scope: linkScope, edit: linkEdit, expiration: expiration, password: password }))
    }
    function send() {
        if (!picked.length || sending) return
        error = ""; sending = true
        invited = picked.map(p => p.DisplayText); invitedEdit = sendEdit
        backend.shareAction("send", JSON.stringify(item), JSON.stringify({ people: picked, edit: sendEdit, message: message }))
    }
    function pick(p) {
        picked = picked.concat([p]); query = ""; suggestions = []
        pickerInput.text = ""; pickerInput.forceActiveFocus()
    }
    function unpick(i) { const a = picked.slice(); a.splice(i, 1); picked = a }
    function roleWord(r) { return r === 3 ? "Owner" : r === 2 ? "Can edit" : "Can view" }
    function personPhoto(p) { return p && p.oid ? "8:orgid:" + p.oid : "" }

    // A 32 px OneDrive icon button (Help, Close, Back, Grant Access).
    component IconButton: Rectangle {
        id: ib
        property string icon
        property string label
        property int glyph: 16
        signal clicked()
        width: 32; height: 32; radius: 2
        color: ibh.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: ib.glyph; color: root.soft }
        HoverHandler { id: ibh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        ToolTip.visible: ibh.hovered; ToolTip.delay: 600; ToolTip.text: label
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // OneDrive's buttons: primary (#5B5FC7) or default (white, a #8A8886 edge).
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        property bool enabled2: true
        signal clicked()
        height: 32; radius: 3
        width: Math.max(96, dbt.implicitWidth + 32)
        color: !enabled2 ? theme.pick("#F3F2F1", "#323130") : primary ? (dbh.hovered ? theme.pick("#4F52B2", "#9297F7") : root.accent) : (dbh.hovered ? theme.menuHover : theme.surface)
        border.width: primary || !enabled2 ? 0 : 0.67; border.color: theme.pick("#8A8886", "#8A8886")
        Text { id: dbt; anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: !db.enabled2 ? theme.pick("#B6B4B4", "#797775") : db.primary ? "white" : root.ink }
        HoverHandler { id: dbh; cursorShape: db.enabled2 ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: db.enabled2; onTapped: db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    // A link scope's 24 px round badge.
    component ScopeBadge: Rectangle {
        property int scope: 0
        property int size: 24
        width: size; height: size; radius: size / 2
        readonly property var look: [["#F1F6F1", "#0B6A0B", "globe-20"], ["#F0F5F8", "#004E8C", "briefcase-20"], ["#F2F2F2", "#393939", "person-add-20"], ["#F4EFEB", "#8E562E", "person-20"], ["#F6F6FA", "#6365A8", "chat-20"]][scope]
        color: look[0]; border.width: 0.67; border.color: look[1]
        FluentIcon { anchors.centerIn: parent; name: parent.look[2]; size: Math.round(parent.size * 0.58); color: parent.look[1] }
    }

    Item {
        id: content
        width: root.width
        height: root.view === "main" ? mainView.height : root.view === "settings" ? settingsView.height : root.view === "invited" ? 288 : 650

        // ---- The share form ----
        Item {
            id: mainView
            visible: root.view === "main"
            width: parent.width
            height: footer.y + footer.height + (copiedBar.visible ? 12 + copiedBar.height : 0) + (errorText.visible ? 8 + errorText.height : 0) + 24
            Text {
                x: 24; y: 26.67; width: 356; height: 26.67
                text: "Share \"" + titleMetrics.elidedText.replace("\u2026", "...") + "\""
                TextMetrics { id: titleMetrics; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; elide: Text.ElideMiddle; elideWidth: 276; text: root.fileName }
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink
                elide: Text.ElideRight
            }
            IconButton { x: 389; y: 24; width: 30; icon: "question-circle-20"; label: "Help"; onClicked: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2103402") }
            IconButton { x: 424; y: 24; icon: "dismiss-20"; label: "Close"; onClicked: root.close() }

            // Recipients.
            Rectangle {
                id: box
                x: 24; y: 66; width: 432
                height: root.picked.length ? pills.height + 11 + 8 + 18.67 + 11.33 : 44
                radius: 4; color: theme.surface; border.width: 0.67; border.color: root.edge
                FluentIcon { x: 12.67; y: 14; size: 16; name: "person-20"; color: root.ink }
                Flow {
                    id: pills
                    visible: root.picked.length > 0
                    x: 39.67; y: 11; width: 318; spacing: 4
                    Repeater {
                        model: root.picked
                        Rectangle {
                            id: pill
                            required property var modelData
                            required property int index
                            width: pillName.implicitWidth + 28 + 8 + 32; height: 28; radius: 16
                            color: theme.pick("#F3F2F1", "#3B3A39")
                            Avatar { x: 1; size: 28; name: parent.modelData.DisplayText; photoId: parent.modelData.EntityData && parent.modelData.EntityData.ObjectId ? "8:orgid:" + parent.modelData.EntityData.ObjectId : "" }
                            Text { id: pillName; x: 37; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.DisplayText; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            Rectangle {
                                x: parent.width - 32; width: 32; height: 28; radius: 16; color: pxh.hovered ? theme.menuHover : "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 16; color: root.accent }
                                HoverHandler { id: pxh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.unpick(pill.index) }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove " + pill.modelData.DisplayText
                            }
                        }
                    }
                }
                TextInput {
                    id: pickerInput
                    x: 35.67; y: root.picked.length ? pills.y + pills.height + 8 : 12.67; width: 320.67; height: 18.67
                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                    clip: true
                    onTextChanged: {
                        root.query = text
                        if (text.trim().length) backend.shareAction("people", JSON.stringify({ site: root.item ? root.item.site : "" }), JSON.stringify({ query: text.trim() }))
                        else root.suggestions = []
                    }
                    Keys.onReturnPressed: if (root.suggestions.length) root.pick(root.suggestions[0])
                    Text { visible: !parent.text; text: root.picked.length ? "Add more" : "Add a name, group, or email"; font: parent.font; color: root.soft }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Add a name, group, or email"
                }
                Rectangle { x: 362.33; y: 3.67; width: 1; height: parent.height - 7.33; color: theme.pick("#D1D1D1", "#605E5C") }
                Rectangle {
                    id: roleButton
                    x: 363.33; y: 0.67; width: 68; height: parent.height - 1.33; radius: 4
                    color: rbh.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: root.sendEdit ? "edit-20" : "eye-20"; size: 16; color: root.ink }
                    FluentIcon { x: 40; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 12; color: root.ink }
                    HoverHandler { id: rbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: roleMenu.open() }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: "Select a role for the person you would like to grant access to"
                }
                Rectangle { visible: pickerInput.activeFocus; anchors.bottom: parent.bottom; x: 0; width: parent.width; height: 2; radius: 1; color: root.accent }
            }
            // The role menu (182 wide, right-aligned under the role button).
            Popup {
                id: roleMenu
                x: box.x + box.width - width; y: box.y + box.height
                width: 182; padding: 0
                height: 104
                background: FluentSurface { depth: 16; radius: 2; color: theme.surface }
                Column {
                    Repeater {
                        model: [{ edit: true, name: "Can edit", line: "Make any changes", icon: "edit-20" }, { edit: false, name: "Can view", line: "Can't make changes", icon: "eye-20" }]
                        Rectangle {
                            required property var modelData
                            width: 182; height: 52; color: rmh.hovered ? theme.menuHover : "transparent"
                            FluentIcon { visible: root.sendEdit === parent.modelData.edit; x: 8; y: 20; size: 12; name: "checkmark-12"; color: root.ink }
                            FluentIcon { x: 32; y: 18; size: 16; name: parent.modelData.icon; color: root.ink }
                            Text { x: 60; y: 8; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                            Text { x: 60; y: 28; text: parent.modelData.line; font.family: theme.font; font.pixelSize: 12; color: root.soft }
                            HoverHandler { id: rmh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.sendEdit = parent.modelData.edit; roleMenu.close() } }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.name
                            Accessible.checked: root.sendEdit === modelData.edit
                        }
                    }
                }
            }
            // Suggestions.
            Rectangle {
                id: suggest
                visible: root.suggestions.length > 0 && pickerInput.activeFocus
                z: 5
                x: box.x; y: box.y + box.height; width: 432
                height: Math.min(3, root.suggestions.length) * 54 + 40
                color: theme.surface
                FluentSurface { anchors.fill: parent; depth: 8; radius: 0; color: theme.surface; z: -1 }
                ListView {
                    width: parent.width; height: parent.height - 40; clip: true
                    model: root.suggestions
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 54
                        color: sgh.hovered ? theme.menuHover : "transparent"
                        Avatar { x: 12; y: 7; size: 40; name: parent.modelData.DisplayText; photoId: parent.modelData.EntityData && parent.modelData.EntityData.ObjectId && parent.modelData.EntityType === "User" ? "8:orgid:" + parent.modelData.EntityData.ObjectId : "" }
                        Text { x: 60; y: 17; text: parent.modelData.DisplayText; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                        HoverHandler { id: sgh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pick(parent.modelData) }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.DisplayText
                    }
                }
                Rectangle {
                    y: parent.height - 40; width: parent.width; height: 40
                    color: sdh.hovered ? theme.menuHover : "transparent"
                    Row {
                        anchors.centerIn: parent; spacing: 12
                        FluentIcon { size: 16; name: "search-20"; color: theme.pick("#383966", "#C5C7F9") }
                        Text { text: "Search directory"; font.family: theme.font; font.pixelSize: 12; color: root.ink }
                    }
                    HoverHandler { id: sdh; cursorShape: Qt.PointingHandCursor }
                    // The directory search is the same people search, with
                    // what is typed.
                    TapHandler { onTapped: backend.shareAction("people", JSON.stringify({ site: root.item ? root.item.site : "" }), JSON.stringify({ query: root.query.trim() })) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Search directory"
                }
            }

            // The message.
            Rectangle {
                id: msgBox
                x: 24; y: box.y + box.height + 12; width: 432; height: 105.67
                radius: 4; color: theme.surface; border.width: 0.67; border.color: root.edge
                FluentIcon { x: 13; y: 13; size: 16; name: "note-edit-20"; color: root.ink }
                Flickable {
                    x: 35.67; y: 10; width: 388; height: parent.height - 16
                    contentHeight: msgEdit.height; clip: true
                    TextEdit {
                        id: msgEdit
                        width: parent.width; wrapMode: TextEdit.Wrap
                        font.family: theme.font; font.pixelSize: 14; color: root.ink
                        onTextChanged: root.message = text
                        Text { visible: !parent.text; text: "Add a message"; font: parent.font; color: root.soft }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Add a message"
                    }
                }
                Rectangle { visible: msgEdit.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: root.accent }
            }

            // Manage access, Copy link, Link settings, Send.
            Item {
                id: footer
                x: 24; y: msgBox.y + msgBox.height + 34; width: 432; height: 33.33
                Rectangle {
                    visible: !!root.info
                    y: root.shared ? 4 : 0; width: root.shared ? 48 : 40; height: root.shared ? 25.33 : 33.33; radius: root.shared ? 2 : 16.67
                    color: mah.hovered ? theme.menuHover : "transparent"
                    // A file only its owners have: a lock.
                    Rectangle {
                        visible: !root.shared; x: 4; anchors.verticalCenter: parent.verticalCenter; width: 26; height: 26; radius: 13
                        color: theme.pick("#F3F2F1", "#3B3A39")
                        FluentIcon { anchors.centerIn: parent; size: 16; name: "lock-closed-20"; color: root.soft }
                    }
                    Repeater {
                        model: root.shared ? root.info.people.filter(p => p.role !== 3).concat(root.info.people.filter(p => p.role === 3)).slice(0, 2) : []
                        Rectangle {
                            required property var modelData
                            required property int index
                            x: 4 + 14 * index; y: 0.67; width: 24; height: 24; radius: 12; color: theme.surface
                            Avatar { anchors.centerIn: parent; size: 20; name: parent.modelData.name; photoId: root.personPhoto(parent.modelData) }
                        }
                    }
                    HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.tab = "people"; root.view = "manage" } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Manage access (" + (root.info ? root.info.people.length : 0) + " people) Select to manage access."
                }
                Rectangle {
                    x: 175.71; width: 116.63; height: 33.33
                    color: clh.hovered ? theme.pick("#E8E9F7", "#3D3E66") : theme.pick("#F4F4F9", "#2B2B40"); border.width: 0.67; border.color: theme.pick("#696BAA", "#7F85F5")
                    radius: 4
                    Rectangle { anchors.right: parent.right; width: 4; height: parent.height; color: parent.color; border.width: 0; visible: false }
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "link-20"; color: theme.pick("#383966", "#C5C7F9") }
                        Text { text: "Copy link"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.pick("#383966", "#C5C7F9") }
                    }
                    HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.copyLink() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Copy link"
                }
                Rectangle {
                    x: 292.33; width: 32.67; height: 33.33; radius: 4
                    color: lsh.hovered ? theme.pick("#E8E9F7", "#3D3E66") : theme.pick("#F4F4F9", "#2B2B40"); border.width: 0.67; border.color: theme.pick("#696BAA", "#7F85F5")
                    FluentIcon { anchors.centerIn: parent; size: 16; name: "settings-20"; color: root.accent }
                    HoverHandler { id: lsh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openSettings() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Link settings"
                }
                Rectangle {
                    x: 337; width: 95; height: 33.33; radius: 3
                    opacity: root.sending ? 0.6 : 1
                    color: sdbh.hovered ? theme.pick("#4F52B2", "#9297F7") : root.accent
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "send-20"; color: "white" }
                        Text { text: "Send"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                    }
                    HoverHandler { id: sdbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.picked.length ? root.send() : pickerInput.forceActiveFocus() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Send"
                }
            }
            // "Link copied." and what the link does.
            Rectangle {
                id: copiedBar
                visible: !!root.copied
                x: 24; y: footer.y + footer.height + 12; width: 432; height: Math.max(31.33, copiedText.implicitHeight + 12)
                radius: 2; color: theme.pick("#DFF6DD", "#054B16")
                FluentIcon { x: 12; y: 8; size: 16; name: "checkmark-circle-20-filled"; color: theme.pick("#107C10", "#92C353") }
                Text {
                    id: copiedText
                    x: 34; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap; textFormat: Text.StyledText
                    text: "<b>Link copied.</b> " + root.copied
                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                }
                Accessible.role: Accessible.AlertMessage
                Accessible.name: "Link copied. " + root.copied
            }
            Text {
                id: errorText
                visible: !!root.error
                x: 24; y: (copiedBar.visible ? copiedBar.y + copiedBar.height : footer.y + footer.height) + 8; width: 432
                wrapMode: Text.Wrap; text: root.error
                font.family: theme.font; font.pixelSize: 12; color: theme.pick("#A4262C", "#F1707B")
            }
        }

        // ---- Link settings ----
        Item {
            id: settingsView
            visible: root.view === "settings"
            width: parent.width
            height: applyRow.y + 32 + 32
            IconButton { visible: !root.chatMode; x: 24; y: 30.67; icon: "arrow-left-20"; label: "Back"; onClicked: root.view = "main" }
            Text { x: root.chatMode ? 24 : 65; y: 24; width: 313; height: 26.67; text: "Link settings"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink }
            Text { x: root.chatMode ? 24 : 65; y: 50.67; width: 313; elide: Text.ElideMiddle; text: root.fileName; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            IconButton { x: 387; y: 30.67; icon: "info-20"; label: "Learn more"; onClicked: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2185222") }
            IconButton { x: 424; y: 30.67; icon: "dismiss-20"; label: "Close"; onClicked: root.close() }
            Text { x: 24; y: 93.33; text: "The link works for"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
            Column {
                id: scopes
                x: 24; y: 132; width: 432; spacing: 12
                Repeater {
                    model: [
                        { scope: 0, name: "Anyone", line: "Share with anyone, doesn't require sign-in" },
                        { scope: 1, name: "People in " + root.org(), line: "Share with people in " + root.org() + ", organization account required." }
                    ].concat(root.chatMode ? [{ scope: 4, name: "People currently in this chat", line: "", noInfo: true }] : []).concat([
                        { scope: 3, name: "Only people with existing access", line: "Reshare with people in your organization who already have access." },
                        { scope: 2, name: "People you choose", line: "Share with specific people you choose inside or outside of " + root.org() + ", using their name, group, or email." }
                    ])
                    Column {
                        id: srow
                        required property var modelData
                        required property int index
                        readonly property bool on: root.pendScope === modelData.scope
                        width: 432; spacing: 12
                        Rectangle { visible: srow.index > 0; width: 432; height: 0.67; color: "transparent" }
                        Item {
                            width: 432; height: srow.on && srow.modelData.line ? Math.max(24, scopeLine.y + scopeLine.height) : 24
                            ScopeBadge { scope: srow.modelData.scope }
                            Row {
                                x: 40; y: 2; spacing: 0
                                Text { text: srow.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: srow.on ? Font.Bold : Font.Normal; color: srow.on ? theme.pick("#575454", "#E1DFDD") : root.ink }
                                Item {
                                    visible: !srow.on && !srow.modelData.noInfo; width: 24; height: 20
                                    FluentIcon { anchors.centerIn: parent; size: 12; name: "info-16"; color: root.soft }
                                }
                            }
                            Text {
                                id: scopeLine
                                visible: srow.on && !!srow.modelData.line
                                x: 40; y: 21.33; width: 322.55
                                wrapMode: Text.Wrap; lineHeight: 1.15
                                text: srow.modelData.line
                                font.family: theme.font; font.pixelSize: 12; color: root.soft
                            }
                            // The radio.
                            Rectangle {
                                x: 412; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 10
                                color: "transparent"; border.width: 1; border.color: srow.on ? root.accent : theme.pick("#605E5C", "#C8C6C4")
                                Rectangle { visible: srow.on; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: root.accent }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.pendScope = srow.modelData.scope }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: srow.modelData.name
                            Accessible.checked: srow.on
                        }
                    }
                }
            }
            // More settings (not for existing access).
            Column {
                id: more
                visible: root.pendScope !== 3
                x: 24; y: scopes.y + scopes.height; width: 432
                Item {
                    width: 432; height: 50.67
                    Text { y: 24; text: "More settings"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                }
                Rectangle {
                    id: roleCombo
                    width: 432; height: 42; color: rch.hovered ? theme.menuHover : "transparent"
                    FluentIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 16; name: root.pendEdit ? "edit-20" : "eye-20"; color: root.soft }
                    Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: root.pendEdit ? "Can edit" : "Can view"; font.family: theme.font; font.pixelSize: 14; color: root.soft }
                    FluentIcon { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; size: 12; name: "chevron-down-20"; color: root.soft }
                    HoverHandler { id: rch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: linkRoleList.open() }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: "Select a role, " + (root.pendEdit ? "Can edit" : "Can view")
                    Popup {
                        id: linkRoleList
                        y: parent.height + 4; width: 432; height: 133.58; padding: 4
                        background: FluentSurface { depth: 16; radius: 2; color: theme.surface }
                        Column {
                            spacing: 2
                            Repeater {
                                model: [{ edit: true, name: "Can edit", line: "Make any changes", icon: "edit-20" }, { edit: false, name: "Can view", line: "Can't make changes", icon: "eye-20" }]
                                Rectangle {
                                    required property var modelData
                                    width: 424; height: 61.79; color: root.pendEdit === modelData.edit ? theme.menuHover : lrh.hovered ? theme.menuHover : "transparent"
                                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: parent.modelData.icon; color: root.ink }
                                    Text { x: 40; y: 12; text: parent.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                                    Text { x: 40; y: 32; text: parent.modelData.line; font.family: theme.font; font.pixelSize: 12; color: root.soft }
                                    HoverHandler { id: lrh; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { root.pendEdit = parent.modelData.edit; linkRoleList.close() } }
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData.name
                                    Accessible.checked: root.pendEdit === modelData.edit
                                }
                            }
                        }
                    }
                }
                Item { width: 1; height: 12 }
                Item {
                    width: 432; height: 32.67
                    FluentIcon { y: 8.33; size: 16; name: "calendar-20"; color: root.ink }
                    Rectangle {
                        x: 28; width: 404; height: 32.67; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.rule }
                        Text {
                            x: 12.67; anchors.verticalCenter: parent.verticalCenter
                            text: root.pendExpiration ? Qt.formatDate(new Date(root.pendExpiration), "MM/dd/yyyy") : "Set expiration date (MM/DD/YYYY)"
                            font.family: theme.font; font.pixelSize: 14; color: root.pendExpiration ? root.ink : root.soft
                        }
                        Rectangle {
                            visible: !!root.pendExpiration
                            x: parent.width - 16; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; color: "transparent"
                            FluentIcon { anchors.centerIn: parent; size: 12; name: "dismiss-20"; color: root.ink }
                            TapHandler { onTapped: root.pendExpiration = "" }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Remove expiration date"
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: expiryPicker.openPicker() }
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: "Set expiration date"
                        DatePickerField {
                            id: expiryPicker
                            bare: true; width: parent.width; height: parent.height
                            minDate: new Date()
                            date: root.pendExpiration ? new Date(root.pendExpiration) : new Date()
                            onPicked: d => root.pendExpiration = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59).toISOString()
                        }
                    }
                }
                Item { visible: root.pendScope === 0; width: 1; height: 12 }
                Item {
                    visible: root.pendScope === 0
                    width: 432; height: 32.67
                    FluentIcon { y: 9.33; size: 14; name: "lock-closed-20"; color: root.ink }
                    Rectangle {
                        x: 26; width: 406; height: 32.67; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.rule }
                        TextInput {
                            id: passwordInput
                            x: 0; y: 2; width: parent.width; height: 28; verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            text: root.pendPassword; onTextChanged: root.pendPassword = text
                            font.family: theme.font; font.pixelSize: 14; color: root.ink
                            Text { visible: !parent.text; anchors.verticalCenter: parent.verticalCenter; text: "Set password"; font: parent.font; color: theme.pick("#3F3D3D", "#C8C6C4") }
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "Password field"
                        }
                    }
                }
            }
            Item {
                id: applyRow
                x: 24; y: (more.visible ? more.y + more.height : scopes.y + scopes.height) + 36; width: 432; height: 32
                DialogButton {
                    anchors.right: parent.right; label: "Apply"; primary: true
                    onClicked: {
                        root.linkScope = root.pendScope; root.linkEdit = root.pendEdit
                        root.expiration = root.pendScope === 3 ? "" : root.pendExpiration
                        root.password = root.pendScope === 0 ? root.pendPassword : ""
                        root.copied = ""
                        if (root.chatMode) { root.linkChosen(root.pendScope, root.pendEdit, root.expiration, root.password); root.close() }
                        else root.view = "main"
                    }
                }
            }
        }

        // ---- You've invited … ----
        Item {
            visible: root.view === "invited"
            width: parent.width; height: 288
            IconButton { x: 424; y: 24; icon: "dismiss-20"; label: "Close"; onClicked: root.close() }
            Text {
                x: 24; y: 70; width: 432; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                lineHeight: 26; lineHeightMode: Text.FixedHeight
                text: "You've invited " + root.invited.join(", ") + " to " + (root.invitedEdit ? "edit" : "view") + "\n\"" + invitedMetrics.elidedText.replace("\u2026", "...") + "\""
                TextMetrics { id: invitedMetrics; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; elide: Text.ElideMiddle; elideWidth: 260; text: root.fileName }
                font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter; y: 158.79; width: 44; height: 39.33; radius: 2
                color: ivh.hovered ? theme.menuHover : "transparent"
                Avatar { anchors.centerIn: parent; size: 36; name: root.invited.length ? root.invited[0] : ""; photoId: root.picked.length && root.picked[0].EntityData && root.picked[0].EntityData.ObjectId ? "8:orgid:" + root.picked[0].EntityData.ObjectId : "" }
                HoverHandler { id: ivh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.tab = "people"; root.view = "manage" } }
                Accessible.role: Accessible.Button
                Accessible.name: "Shared with " + root.invited.join(", ") + ". Select to manage access."
            }
        }

        // ---- Manage Access ----
        Item {
            id: manageView
            visible: root.view === "manage"
            width: parent.width; height: 650
            IconButton { x: 24; y: 24; icon: "arrow-left-20"; label: "Back"; onClicked: { root.picked = []; root.view = "main" } }
            Text { x: 65; y: 26.67; text: "Manage Access"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink }
            IconButton { x: 387; y: 24; icon: "person-add-20"; label: "Grant Access"; onClicked: { root.view = "main"; pickerInput.forceActiveFocus() } }
            IconButton { x: 424; y: 24; icon: "dismiss-20"; label: "Close"; onClicked: root.close() }
            FluentIcon { x: 31; y: 68; size: 16; name: root.fileIconName(); color: root.ink }
            Text { x: 55; y: 66.33; width: 400; elide: Text.ElideMiddle; text: root.fileName; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            Rectangle {
                visible: root.shared
                x: 30; y: 92; width: stopRow.implicitWidth + 4; height: 20; color: "transparent"
                Row {
                    id: stopRow; x: 2; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 14; name: "subtract-circle-20"; color: theme.pick("#383966", "#C5C7F9") }
                    Text { text: "Stop sharing"; font.family: theme.font; font.pixelSize: 14; color: root.accent; font.underline: ssh.hovered }
                }
                HoverHandler { id: ssh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.ask = { title: "Stop sharing?", text: "Only owners of this item will still have access.", ok: "Stop sharing", run: () => backend.shareAction("stop", JSON.stringify(root.item), "{}") } }
                Accessible.role: Accessible.Button
                Accessible.name: "Stop sharing"
            }
            Row {
                x: 24; y: root.shared ? 124 : 94
                Repeater {
                    model: [
                        { key: "people", label: "People" + (root.info ? " • " + root.info.people.length : "") },
                        { key: "groups", label: "Groups" },
                        { key: "links", label: "Links" + (root.info && root.info.links.length ? " • " + root.info.links.length : "") }
                    ]
                    Item {
                        required property var modelData
                        readonly property bool on: root.tab === modelData.key
                        width: tabText.implicitWidth + 24; height: 44
                        Text { id: tabText; x: 12; y: 12; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: parent.on ? Font.DemiBold : Font.Normal; color: root.ink }
                        Rectangle { visible: parent.on; x: 12; y: 41; width: tabText.implicitWidth; height: 3; radius: 1.5; color: root.accent }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.tab = parent.modelData.key }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.selected: on
                    }
                }
            }
            // People.
            Item {
                visible: root.tab === "people"
                x: 24; y: root.shared ? 180 : 150; width: 432; height: parent.height - y - 24
                Item {
                    visible: root.shared
                    x: 12; width: 420; height: 28
                    FluentIcon { x: 0; y: 4; size: 16; name: "search-20"; color: root.accent }
                    TextInput {
                        x: 28; y: 4; width: 384; height: 19.17
                        font.family: theme.font; font.pixelSize: 14; color: root.ink
                        onTextChanged: root.filter = text
                        Text { visible: !parent.text; text: "Search displayed names"; font: parent.font; color: root.soft }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Search displayed names"
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.soft }
                }
                // Shared with no one: "This file has not been shared with
                // anyone yet." and Start sharing.
                Column {
                    visible: !!root.info && !root.shared
                    y: 76; width: 432; spacing: 10
                    Text { text: "This file has not been shared with anyone yet."; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                    Row {
                        spacing: 10
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "add-circle-20"; color: root.accent }
                        Text { text: "Start sharing"; font.family: theme.font; font.pixelSize: 14; color: root.accent; font.underline: stsh.hovered; HoverHandler { id: stsh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.view = "main"; pickerInput.forceActiveFocus() } } }
                    }
                }
                ListView {
                    y: root.shared ? 46 : 0; width: 432; height: root.shared ? parent.height - 46 : 60; clip: true
                    interactive: root.shared
                    model: root.info ? root.info.people.filter(p => !root.filter || p.name.toLowerCase().indexOf(root.filter.toLowerCase()) >= 0) : []
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        id: prow
                        required property var modelData
                        width: 432; height: 58.67
                        Avatar { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 32; name: prow.modelData.name; photoId: root.personPhoto(prow.modelData) }
                        Text { x: 48; anchors.verticalCenter: parent.verticalCenter; width: 260; elide: Text.ElideRight; text: prow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            width: roleRow.implicitWidth + 8; height: 28; radius: 2
                            color: prow.modelData.role !== 3 && prh.hovered ? theme.menuHover : "transparent"
                            Row {
                                id: roleRow; anchors.centerIn: parent; spacing: 6
                                FluentIcon { visible: prow.modelData.role !== 3; anchors.verticalCenter: parent.verticalCenter; size: 14; name: prow.modelData.role === 2 ? "edit-20" : "eye-20"; color: root.ink }
                                Text { text: root.roleWord(prow.modelData.role); font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            }
                            HoverHandler { id: prh; cursorShape: prow.modelData.role !== 3 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            TapHandler {
                                enabled: prow.modelData.role !== 3
                                onTapped: { root.person = prow.modelData; root.personRole = root.person.direct ? root.person.role : 0; root.view = "access" }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: root.roleWord(prow.modelData.role)
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.rule }
                    }
                }
            }
            // Groups.
            Column {
                visible: root.tab === "groups"
                x: 24; y: 192; width: 432; spacing: 10
                Text {
                    width: 432; wrapMode: Text.Wrap; textFormat: Text.StyledText
                    text: "This file has not been shared with a group yet. <a href=\"learn\" style=\"color:" + root.accent + "\">Learn more</a>"
                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                    onLinkActivated: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2185222")
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Row {
                    spacing: 10
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "add-circle-20"; color: root.ink }
                    Text { text: "Share with a group"; font.family: theme.font; font.pixelSize: 14; color: root.accent; font.underline: sgg.hovered; HoverHandler { id: sgg; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.view = "main"; pickerInput.forceActiveFocus() } } }
                }
            }
            // Links.
            Item {
                visible: root.tab === "links"
                x: 24; y: 192; width: 432; height: parent.height - y - 24
                Column {
                    visible: !!root.info && root.info.links.length === 0
                    width: 432; spacing: 10
                    Text { width: 432; wrapMode: Text.Wrap; text: "A sharing link hasn't been created for this file yet. Create a new link to start sharing with others."; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                    Row {
                        spacing: 10
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "add-circle-20"; color: root.ink }
                        Text { text: "Create and share a new link"; font.family: theme.font; font.pixelSize: 14; color: root.accent; font.underline: cnl.hovered; HoverHandler { id: cnl; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.openSettings() } }
                    }
                }
                ListView {
                    width: 432; height: parent.height; clip: true
                    model: root.info ? root.info.links : []
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        required property var modelData
                        width: 432; height: linkSentence.y + linkSentence.height + 16
                        ScopeBadge { y: 0.5; size: 32; scope: parent.modelData.scope }
                        Rectangle {
                            x: 42.67; y: 0.67; width: 270.67; height: 30.67; radius: 4; color: theme.surface; border.width: 0.67; border.color: root.edge
                            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16; elide: Text.ElideRight; text: parent.parent.modelData.url; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                        }
                        Rectangle {
                            x: 314; width: 54; height: 32; radius: 3; color: lch.hovered ? theme.menuHover : theme.surface; border.width: 0.67; border.color: theme.pick("#B6B4B4", "#8A8886")
                            Text { anchors.centerIn: parent; text: "Copy"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.ink }
                            HoverHandler { id: lch; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.copyText(parent.parent.modelData.url) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Copy link"
                        }
                        IconButton { x: 368; icon: "settings-20"; label: "More link options"; onClicked: { root.pendScope = parent.modelData.scope; root.pendEdit = parent.modelData.edit; root.openSettings() } }
                        IconButton { x: 400; icon: "delete-20"; label: "Remove link"
                            onClicked: { const l = parent.modelData; root.ask = { title: "Delete link?", text: "The link will not work for anyone anymore.", ok: "Remove", run: () => backend.shareAction("unlink", JSON.stringify(root.item), JSON.stringify({ kind: l.kind, share_id: l.share_id })) } } }
                        Text {
                            id: linkSentence
                            x: 42; y: 40; width: 382; wrapMode: Text.Wrap
                            text: parent.modelData.scope === 0 ? "Anyone with the link can " + (parent.modelData.edit ? "edit" : "view")
                                : parent.modelData.scope === 1 ? "People in " + (root.info ? root.info.tenant : "") + " with the link can " + (parent.modelData.edit ? "edit" : "view")
                                : "Only the people you specified can " + (parent.modelData.edit ? "edit" : "view")
                            font.family: theme.font; font.pixelSize: 14; color: root.ink
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: root.rule }
                    }
                }
            }
        }

        // ---- Access summary ----
        Item {
            visible: root.view === "access"
            width: parent.width; height: 650
            IconButton { x: 24; y: 24; icon: "arrow-left-20"; label: "Back"; onClicked: root.view = "manage" }
            Text { x: 65; y: 32; text: "Manage Access"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.ink }
            IconButton { x: 424; y: 24; icon: "dismiss-20"; label: "Close"; onClicked: root.close() }
            Row {
                x: 24; y: 83.61; spacing: 4
                Text { text: "Access summary"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; size: 12; name: "info-16"; color: root.soft }
            }
            Avatar { x: 24; y: 129.56; size: 32; name: root.person ? root.person.name : ""; photoId: root.personPhoto(root.person) }
            Text {
                x: 64; y: 129.56; height: 32; verticalAlignment: Text.AlignVCenter; textFormat: Text.StyledText
                text: root.person ? root.escapeText(root.person.name) + " <b>can " + (root.person.role === 2 ? "edit" : "view") + "</b>" : ""
                font.family: theme.font; font.pixelSize: 18; color: root.ink
            }
            Text { x: 24; y: 210.23; text: "Ways this person has access"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink }
            Column {
                x: 24; y: 254.51; width: 432; spacing: 16
                // Through links first ("Anyone with this link: can edit"),
                // each opening to the link with Copy and its settings.
                Repeater {
                    model: root.info && root.person ? root.info.links.filter(l => l.members.some(m => m.login === root.person.login)) : []
                    Column {
                        id: way
                        required property var modelData
                        property bool expanded: false
                        width: 432; spacing: 10
                        Item {
                            width: 432; height: 20
                            FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 8; name: way.expanded ? "chevron-up-20" : "chevron-down-20"; color: root.soft }
                            Text {
                                x: 22; anchors.verticalCenter: parent.verticalCenter
                                text: (way.modelData.scope === 0 ? "Anyone with this link" : way.modelData.scope === 1 ? "People in " + root.info.tenant + " with this link" : "Specific people with this link") + ": can " + (way.modelData.edit ? "edit" : "view")
                                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: way.expanded = !way.expanded }
                            Accessible.role: Accessible.Button
                            Accessible.name: parent.children[1].text
                        }
                        Item {
                            visible: way.expanded
                            x: 32; width: 400; height: 68
                            ScopeBadge { y: 0; size: 32; scope: way.modelData.scope }
                            Rectangle {
                                x: 42.67; y: 0.67; width: 240; height: 30.67; radius: 4; color: theme.surface; border.width: 0.67; border.color: root.edge
                                Text { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16; elide: Text.ElideRight; text: way.modelData.url; font.family: theme.font; font.pixelSize: 14; color: root.ink }
                            }
                            Rectangle {
                                x: 283; width: 54; height: 32; radius: 3; color: wch.hovered ? theme.menuHover : theme.surface; border.width: 0.67; border.color: theme.pick("#B6B4B4", "#8A8886")
                                Text { anchors.centerIn: parent; text: "Copy"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.ink }
                                HoverHandler { id: wch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: backend.copyText(way.modelData.url) }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Copy link"
                            }
                            IconButton { x: 338; icon: "settings-20"; label: "More link options"; onClicked: { root.pendScope = way.modelData.scope; root.pendEdit = way.modelData.edit; root.openSettings() } }
                            Text { x: 42.67; y: 44; text: "How do I modify this link?"; font.family: theme.font; font.pixelSize: 12; color: root.ink }
                        }
                    }
                }
                // Direct access.
                Column {
                    id: direct
                    property bool expanded: false
                    readonly property bool viaLink: !!root.person && !root.person.direct
                    width: 432; spacing: 10
                    Item {
                        width: 432; height: 20
                        FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 8; name: direct.expanded ? "chevron-up-20" : "chevron-down-20"; color: root.soft }
                        Text {
                            x: 22; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.StyledText
                            text: (direct.expanded ? "<b>Direct Access</b>" : "Direct Access") + ": <b>" + (root.person && root.person.direct ? (root.person.role === 2 ? "can edit" : "can view") : "none") + "</b>"
                            font.family: theme.font; font.pixelSize: 14; color: root.ink
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: direct.expanded = !direct.expanded }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Direct Access"
                    }
                    Text {
                        visible: direct.expanded
                        x: 22; width: 410; wrapMode: Text.Wrap
                        text: direct.viaLink ? "Grant access is not available because this person can already " + (root.person.role === 2 ? "edit" : "view") + " this item."
                                             : "Direct Access grants access permissions without the use of a link"
                        font.family: theme.font; font.pixelSize: 14; color: root.soft
                    }
                    Repeater {
                        model: !direct.expanded ? [] : direct.viaLink ? [{ role: 2, name: "Can edit", line: "Make any changes" }, { role: 1, name: "Can view", line: "Can't make changes" }]
                             : [{ role: 2, name: "Can edit", line: "Make any changes" }, { role: 1, name: "Can view", line: "Can't make changes" }, { role: 0, name: "No direct access", line: "" }]
                        Item {
                            id: opt
                            required property var modelData
                            x: 22; width: 410; height: modelData.line ? 52 : 26
                            Rectangle {
                                x: 12; y: 2; width: 20; height: 20; radius: 10; color: "transparent"
                                border.width: 1; border.color: !direct.viaLink && root.personRole === opt.modelData.role ? root.accent : theme.pick("#605E5C", "#C8C6C4")
                                Rectangle { visible: !direct.viaLink && root.personRole === opt.modelData.role; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: root.accent }
                            }
                            Text { x: 46; y: 2; text: opt.modelData.name; font.family: theme.font; font.pixelSize: 14; color: direct.viaLink ? root.soft : root.ink }
                            Text { visible: !!opt.modelData.line; x: 46; y: 22; text: opt.modelData.line; font.family: theme.font; font.pixelSize: 14; color: direct.viaLink ? root.soft : root.ink }
                            HoverHandler { cursorShape: direct.viaLink ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            TapHandler { enabled: !direct.viaLink; onTapped: root.personRole = opt.modelData.role }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.name
                            Accessible.checked: !direct.viaLink && root.personRole === modelData.role
                        }
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24; y: 520.23; spacing: 12
                readonly property int was: root.person && root.person.direct ? root.person.role : 0
                DialogButton {
                    label: "Apply"; primary: true; enabled2: root.personRole !== parent.was
                    onClicked: {
                        const p = root.person
                        if (root.personRole === 0) root.ask = { title: "Want to remove " + p.name + "'s direct access?", text: "They may still have access to this item through a group or link.", ok: "Remove",
                                                               run: () => { backend.shareAction("role", JSON.stringify(root.item), JSON.stringify({ login: p.login, role: 0 })); root.view = "manage" } }
                        else { backend.shareAction("role", JSON.stringify(root.item), JSON.stringify({ login: p.login, role: root.personRole })); root.person = Object.assign({}, p, { role: root.personRole, direct: true }) }
                    }
                }
                DialogButton { label: "Cancel"; enabled2: root.personRole !== parent.was; onClicked: root.personRole = parent.was }
            }
        }
    }

    // A question over the dialog (380 wide, padding 24, radius 8).
    Rectangle {
        visible: !!root.ask
        anchors.fill: parent; radius: 8; color: Qt.rgba(0, 0, 0, 0.4)
        TapHandler {}
        Rectangle {
            anchors.centerIn: parent; width: 380; height: askTitle.height + askText.height + 24 + 16 + 16 + 32 + 24
            radius: 8; color: theme.surface
            Text { id: askTitle; x: 24; y: 24; width: 290.67; wrapMode: Text.Wrap; lineHeight: 28; lineHeightMode: Text.FixedHeight; text: root.ask ? root.ask.title : ""; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink }
            IconButton { x: 323.33; y: 24; height: 31.33; icon: "dismiss-20"; label: "Close"; onClicked: root.ask = null }
            Text { id: askText; x: 24; y: askTitle.y + askTitle.height + 8.67; width: 332; wrapMode: Text.Wrap; lineHeight: 20; lineHeightMode: Text.FixedHeight; text: root.ask ? root.ask.text : ""; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24; y: askText.y + askText.height + 8.67; spacing: 8
                DialogButton { label: root.ask ? root.ask.ok : ""; primary: true; width: Math.max(80, implicitWidth); onClicked: { const r = root.ask.run; root.ask = null; r() } }
                DialogButton { label: "Cancel"; width: 83.19; onClicked: root.ask = null }
            }
        }
    }

    /// Files' Manage access: the dialog on its People tab.
    function openManage(itemRef, name, type) { openFor(itemRef, name, type); view = "manage"; tab = "people" }
    /// Copy link's Settings: Link settings over the share form.
    function openLinkSettingsFor(itemRef, name, type) { openFor(itemRef, name, type); openSettings() }
    function openSettings() {
        pendScope = linkScope; pendEdit = linkEdit; pendExpiration = expiration; pendPassword = password
        view = "settings"
    }
    function escapeText(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;") }
    function fileIconName() {
        const t = String(fileType || fileName.split(".").pop()).toLowerCase()
        return t === "txt" ? "ft-txt-20" : t === "docx" || t === "doc" ? "ft-docx-20" : t === "xlsx" ? "ft-xlsx-20" : t === "pptx" ? "ft-pptx-20" : t === "pdf" ? "ft-pdf-20" : "ft-txt-20"
    }
    // Test hooks.
    function pickForTest(name) { const p = suggestions.find(p => p.DisplayText === name); if (p) pick(p) }
    function messageForTest(t) { msgEdit.text = t }
    function typeForTest(q) { pickerInput.forceActiveFocus(); pickerInput.text = q }
    function showForTest(v, t) { view = v; if (t) tab = t; if (v === "access" && info) { person = info.people.find(p => p.role !== 3) || null; personRole = person && person.direct ? person.role : 0 } }
    function stateForTest() { return { view: view, info: info, picked: picked.length, suggestions: suggestions.length, copied: copied, error: error, scope: linkScope, edit: linkEdit } }
}
