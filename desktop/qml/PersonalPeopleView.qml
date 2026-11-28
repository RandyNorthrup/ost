import QtQuick
import QtQuick.Controls.Basic

// A personal account's People app, as Teams for personal use shows it
// (Teams 26304 on testpc2 and teams.live.com, 2026-11-28, TASK-0295):
// - the pane: "People" with People settings (the gear), All contacts and
//   Active now, a rule, your profile (your picture with presence, your
//   name over "Your profile"), and Invite to Teams at the bottom;
// - the content: the view's title with "Find a contact", then the table:
//   Name (sorts, ↑ / ↓), Email and Phone; each contact shows their picture
//   with presence and their name over their status, then Chat, Call and
//   More options (Block, Delete); the address is a mailto link with Copy;
// - Active now: the contacts whose presence isn't offline;
// - empty: "Bring your contacts with you" (Sync device contacts), "No
//   active contacts at this time", or "No results found for '…'";
// - People settings: Sync contacts and Blocked users (Unblock, Delete).
// Your contacts are Teams free's buddy list and block list
// (api::tfl_people); Invite to Teams copies your invite link.
Item {
    id: root
    /// The backend's contacts_json for a personal account: {personal,
    /// contacts, blocked, notice}.
    property var data_: ({})
    property bool busy: false
    signal load()
    signal change(string op, string json)
    signal chatWith(string mri, string name)
    signal callPerson(string mri, string name)
    signal openProfile(string mri)

    /// "all", "active", "settings" or "blocked".
    property string view: "all"
    property bool descending: false
    property string keyword: ""
    readonly property var all: data_.contacts || []
    readonly property var blockedPeople: data_.blocked || []
    function isActive(c) { const a = c.presence || ""; return !!a && a !== "Offline" && a !== "PresenceUnknown" && a !== "OffWork" }
    readonly property var shown: {
        const q = keyword.trim().toLowerCase()
        const list = all.filter(c => (view !== "active" || isActive(c))
            && (!q || [c.name, c.email, c.phone].some(t => !!t && String(t).toLowerCase().indexOf(q) >= 0)))
        list.sort((a, b) => (descending ? -1 : 1) * String(a.name || "").localeCompare(String(b.name || "")))
        return list
    }
    readonly property var statusLabels: ({ Available: qsTr("Available"), Away: qsTr("Away"), BeRightBack: qsTr("Away"), Busy: qsTr("Busy"),
                                            InACall: qsTr("Busy"), DoNotDisturb: qsTr("Do not disturb"), Offline: qsTr("Offline"), PresenceUnknown: qsTr("Offline") })
    function statusOf(c) { return statusLabels[c.presence || "Offline"] || qsTr("Offline") }
    function op(name, extra) { root.change(name, JSON.stringify(extra)) }
    function stateForTest() {
        return { view: view, busy: busy, error: data_.error || "", shown: shown.map(c => ({ name: c.name, mri: c.mri, presence: c.presence, status: statusOf(c), email: c.email, blocked: !!c.blocked })),
                 blocked: blockedPeople }
    }
    function find(name) { return all.find(c => c.name === name) || null }
    Component.onCompleted: load()
    onVisibleChanged: if (visible) load()
    // Their presence as it changes (Teams free's list follows it live).
    Timer { interval: 60000; repeat: true; running: root.visible; onTriggered: root.load() }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // ---- The pane (380 wide) ----------------------------------------
    Rectangle {
        id: pane
        width: 380; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Text { x: 20; y: 18; text: qsTr("People"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
               Accessible.role: Accessible.Heading; Accessible.name: text }
        RowTool {
            x: 328; y: 14; icon: "settings-20"; tip: qsTr("People settings"); active: root.view === "settings" || root.view === "blocked"
            onClicked: root.view = "settings"
        }
        Column {
            x: 20; y: 69; width: parent.width - 40; spacing: 4
            NavRow { label: qsTr("All contacts"); icon: root.view === "all" ? "people-20-filled" : "people-20"; selected: root.view === "all"; onClicked: root.view = "all" }
            NavRow { label: qsTr("Active now"); icon: root.view === "active" ? "checkmark-circle-20-filled" : "checkmark-circle-20"; selected: root.view === "active"; onClicked: root.view = "active" }
        }
        Rectangle { x: 20; y: 153; width: parent.width - 40; height: 1; color: theme.dividerSoft }
        // Your profile.
        Rectangle {
            id: me
            x: 20; y: 167; width: parent.width - 40; height: 58; radius: theme.radius
            color: meh.hovered ? theme.rowHover : "transparent"
            Avatar { x: 12; y: 15; size: 28; name: backend.userName; photoId: backend.userMri; presence: window.myPresence || "" }
            Text { x: 48; y: 12; width: parent.width - 60; elide: Text.ElideRight; text: backend.userName; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(me, theme.text) }
            Text { x: 48; y: 31; text: qsTr("Your profile"); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(me, theme.textSecondary) }
            HoverHandler { id: meh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openProfile(backend.userMri) }
            Accessible.role: Accessible.Button
            Accessible.name: backend.userName + ", " + qsTr("Your profile")
        }
        // Invite to Teams.
        Rectangle {
            id: invite
            x: 20; y: parent.height - 16 - height; width: parent.width - 40; height: 32; radius: theme.radius
            color: ih.hovered ? theme.rowHover : theme.input; border.color: theme.stroke; border.width: 1
            Row {
                anchors.centerIn: parent; spacing: 6
                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "person-add-20"; size: 20; color: theme.onFill(invite, theme.textStrong) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Invite to Teams"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(invite, theme.text) }
            }
            HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.peopleInviteLink() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Invite to Teams")
        }
    }

    // ---- Contacts ---------------------------------------------------
    Item {
        id: content
        visible: root.view === "all" || root.view === "active"
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Text { x: 20; y: 18; text: root.view === "active" ? qsTr("Active now") : qsTr("All contacts")
               font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
               Accessible.role: Accessible.Heading; Accessible.name: text }
        Rectangle {
            id: findBox
            x: parent.width - 20 - width; y: 14; width: 240; height: 32; radius: 4
            color: theme.input; border.width: 1; border.color: findInput.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: findInput
                x: 34; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                onTextChanged: findDebounce.restart()
                Keys.onEscapePressed: text = ""
                Text { visible: !findInput.text; text: qsTr("Find a contact"); color: theme.textSecondary; font: findInput.font }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Find a contact")
            }
            Timer { id: findDebounce; interval: 300; onTriggered: root.keyword = findInput.text }
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }

        Item {
            id: table
            visible: root.shown.length > 0
            anchors { fill: parent; topMargin: 80; leftMargin: 20; rightMargin: 20 }
            readonly property color rule: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
            readonly property color link: theme.pick("#4F52B2", "#7F85F5", "#FFFF00")
            readonly property real nameW: Math.max(320, width * 0.5)
            readonly property real emailW: (width - nameW) / 2
            Item {
                id: head
                width: parent.width; height: 33
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: table.rule }
                Rectangle {
                    id: nameHead
                    x: 8; y: 0; width: nameRow.implicitWidth + 12; height: 32; radius: 4
                    color: nhh.hovered ? theme.rowHover : "transparent"
                    Row {
                        id: nameRow
                        x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: qsTr("Name"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(nameHead, theme.text) }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: root.descending ? "arrow-down-12" : "arrow-up-12"; size: 12; color: theme.onFill(nameHead, theme.text) }
                    }
                    HoverHandler { id: nhh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.descending = !root.descending }
                    Accessible.role: Accessible.ColumnHeader
                    Accessible.name: qsTr("Name")
                }
                Text { x: table.nameW + 14; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Email"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text { x: table.nameW + table.emailW + 14; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Phone"); font.family: theme.font; font.pixelSize: 14; color: theme.text }
            }
            ListView {
                id: list
                anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: crow
                    required property var modelData
                    readonly property bool hot: rh.hovered || rowMenu.opened
                    width: ListView.view.width; height: 44
                    color: crow.hot ? theme.rowHover : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: table.rule }
                    Avatar {
                        id: pic
                        x: 8; y: 8; size: 28; name: crow.modelData.name || ""; photoId: crow.modelData.mri; presence: crow.modelData.blocked ? "Blocked" : (crow.modelData.presence || "Offline")
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openProfile(crow.modelData.mri) }
                    }
                    Column {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: table.nameW - 44 - 120
                        Text { width: parent.width; elide: Text.ElideRight; text: crow.modelData.name || crow.modelData.email || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(crow, theme.text) }
                        Text { width: parent.width; elide: Text.ElideRight; text: root.statusOf(crow.modelData); font.family: theme.font; font.pixelSize: 12; color: theme.onFill(crow, theme.textSecondary) }
                    }
                    // Chat, Call and More options.
                    Row {
                        x: table.nameW - 120; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        RowTool { anchors.verticalCenter: parent.verticalCenter; icon: "chat-20"; small: true; tip: qsTr("Chat"); onClicked: root.chatWith(crow.modelData.mri, crow.modelData.name) }
                        RowTool { anchors.verticalCenter: parent.verticalCenter; icon: "call-20"; small: true; tip: qsTr("Call"); onClicked: root.callPerson(crow.modelData.mri, crow.modelData.name) }
                        RowTool {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "more-horizontal-20"; tip: qsTr("More options"); active: rowMenu.opened
                            onClicked: rowMenu.open()
                            MenuPopup {
                                id: rowMenu
                                y: parent.height; minRowWidth: 128
                                items: [{ label: qsTr("Block"), icon: "prohibited-20", k: "block" }, { label: qsTr("Delete"), icon: "delete-20", k: "delete" }]
                                onPicked: i => {
                                    if (items[i].k === "block") { blockDialog.person = crow.modelData; blockDialog.open() }
                                    else { deleteDialog.person = crow.modelData; deleteDialog.open() }
                                }
                            }
                        }
                    }
                    // The address (a mailto link) with Copy.
                    Row {
                        visible: !!crow.modelData.email
                        x: table.nameW + 14; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, table.emailW - 50); elide: Text.ElideRight
                            text: crow.modelData.email || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(crow, table.link)
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.openExternal("mailto:" + crow.modelData.email) }
                        }
                        RowTool {
                            id: copyTool
                            anchors.verticalCenter: parent.verticalCenter
                            property bool done: false
                            icon: done ? "checkmark-16" : "copy-16"; small: true; tip: qsTr("Copy")
                            onClicked: { backend.copyHtml("", crow.modelData.email); done = true; copied.restart() }
                            Timer { id: copied; interval: 500; onTriggered: copyTool.done = false }
                        }
                    }
                    Text {
                        x: table.nameW + table.emailW + 14; anchors.verticalCenter: parent.verticalCenter
                        width: table.emailW - 20; elide: Text.ElideRight
                        text: crow.modelData.phone || ""; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(crow, theme.text)
                    }
                    HoverHandler { id: rh }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: (modelData.name || "") + ", " + root.statusOf(modelData)
                }
            }
        }

        // Empty: Teams free's lines.
        Column {
            visible: !root.busy && !root.data_.error && root.shown.length === 0
            anchors.centerIn: parent; anchors.verticalCenterOffset: 30
            spacing: 12
            readonly property bool searching: root.keyword.trim().length > 0
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160; height: 160; radius: 24
                color: theme.brandTint
                FluentIcon { anchors.centerIn: parent; name: root.view === "active" ? "checkmark-circle-20" : "book-contacts-32"; size: 96; color: theme.brand }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.searching ? qsTr("No results found for '%1'").arg(root.keyword.trim())
                    : root.view === "active" ? qsTr("No active contacts at this time") : qsTr("Bring your contacts with you")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.searching ? qsTr("They may not be in your contacts yet. Try expanding your search to all of Teams.")
                    : root.view === "active" ? qsTr("Check back later!") : qsTr("Sync your device contacts, or invite folks to Teams.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Item { width: 1; height: 12; visible: syncButton.visible }
            Rectangle {
                id: syncButton
                visible: !parent.searching && root.view === "all"
                anchors.horizontalCenter: parent.horizontalCenter
                width: syncLabel.implicitWidth + 48; height: 32; radius: 4
                color: sbh.hovered ? theme.brandHover : theme.brandFill
                Text { id: syncLabel; anchors.centerIn: parent; text: qsTr("Sync device contacts"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(syncButton, "white") }
                HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: syncDialog.open() }
                Accessible.role: Accessible.Button
                Accessible.name: syncLabel.text
            }
        }
        Text {
            visible: !!root.data_.error && root.all.length === 0
            anchors.centerIn: parent
            text: qsTr("We've run into an issue") + "\n" + qsTr("Try refreshing or check back later.")
            horizontalAlignment: Text.AlignHCenter
            font.family: theme.font; font.pixelSize: 14; color: theme.text
        }
        BusyIndicator { anchors.centerIn: parent; running: root.busy && root.all.length === 0 && !root.data_.personal; visible: running }
    }

    // ---- People settings: Sync contacts and Blocked users -------------
    Item {
        id: settingsPage
        visible: root.view === "settings" || root.view === "blocked"
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        // The breadcrumb: People (› Blocked users).
        Row {
            x: 20; y: 16; spacing: 8
            Text {
                id: crumb
                text: qsTr("People"); font.family: theme.font; font.pixelSize: 18
                font.weight: root.view === "settings" ? Font.Bold : Font.Normal; color: theme.text
                HoverHandler { enabled: root.view === "blocked"; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: root.view === "blocked"; onTapped: root.view = "settings" }
                Accessible.role: root.view === "blocked" ? Accessible.Link : Accessible.Heading
                Accessible.name: text
            }
            FluentIcon { visible: root.view === "blocked"; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-16"; size: 16; color: theme.textStrong }
            Text { visible: root.view === "blocked"; text: qsTr("Blocked users"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
                   Accessible.role: Accessible.Heading; Accessible.name: text }
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }
        Column {
            visible: root.view === "settings"
            x: 20; y: 78; width: Math.min(760, parent.width - 40); spacing: 12
            SettingCard {
                icon: "people-20"; title: qsTr("Sync contacts"); subtitle: qsTr("Manage contact sync settings.")
                onManage: syncDialog.open()
            }
            SettingCard {
                icon: "prohibited-20"; title: qsTr("Blocked users"); subtitle: qsTr("Blocked users won't be able to call you, message you, or see your presence in Teams.")
                onManage: root.view = "blocked"
            }
        }
        Column {
            visible: root.view === "blocked"
            x: 20; y: 80; width: Math.min(700, parent.width - 40); spacing: 0
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: qsTr("Blocking a user prevents you from seeing their messages. They will still be able to see any content you send in a group with them, including messages, files.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Item { width: 1; height: 24 }
            Text {
                visible: root.blockedPeople.length === 0
                text: qsTr("When you block people, you'll see them listed below.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Repeater {
                model: root.blockedPeople
                Item {
                    id: brow
                    required property var modelData
                    width: parent.width; height: 46
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") }
                    Avatar { x: 6; y: 7; size: 32; name: brow.modelData.name || "?"; photoId: brow.modelData.mri; presence: "Blocked" }
                    Text { x: 52; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52 - 210; elide: Text.ElideRight
                           text: brow.modelData.name || brow.modelData.mri; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        DialogButton { label: qsTr("Unblock"); onClicked: root.op("tflBlock", { mri: brow.modelData.mri, on: false }) }
                        DialogButton { label: qsTr("Delete"); onClicked: root.op("tflForget", { mri: brow.modelData.mri }) }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: brow.modelData.name || ""
                }
            }
        }
    }

    // ---- Dialogs (Teams free's contacts strings) -------------------------
    ConfirmDialog {
        id: deleteDialog
        property var person: null
        dialogWidth: 600
        title: qsTr("Delete this person?")
        body: qsTr("When you delete a contact they’ll no longer show up in your contacts and will be removed from your blocked list. This means they can contact you again.")
              + "\n\n" + qsTr("If you synced this contact to Teams from another device, you'll need to delete them there too. If you don't, they might show up as a contact in Teams again.")
        confirmText: qsTr("Delete")
        onConfirmed: if (person) root.op("tflDelete", { mri: person.mri })
    }
    ConfirmDialog {
        id: blockDialog
        property var person: null
        dialogWidth: 600
        title: qsTr("Block this person?")
        body: qsTr("When you block someone, they can't see your status and you won't receive any Teams communications from them. They'll still be able to see your messages in group chats.")
              + "\n\n" + qsTr("To delete this person, go to Settings > People > Blocked users.")
        confirmText: qsTr("Block")
        onConfirmed: if (person) root.op("tflBlock", { mri: person.mri, on: true })
    }
    // Sync contacts: Teams desktop syncs device contacts through its mobile
    // app ("Sync or import your device contacts using Teams mobile app").
    ConfirmDialog {
        id: syncDialog
        dialogWidth: 480
        title: qsTr("Sync or import your device contacts using Teams mobile app")
        body: qsTr("Find people you know in Teams by installing the mobile app and syncing your phone contacts.")
        confirmText: qsTr("Learn more")
        cancelText: qsTr("Close")
        onConfirmed: backend.openExternal("https://go.microsoft.com/fwlink/?linkid=2272231")
    }

    component NavRow: Rectangle {
        id: nr
        property string label
        property string icon
        property bool selected
        signal clicked()
        width: parent ? parent.width : 300; height: 32; radius: theme.radius
        color: selected ? theme.hc(theme.surface, theme.hcHighlight) : nh.hovered ? theme.rowHover : "transparent"
        border.width: selected ? 1 : 0; border.color: theme.stroke
        FluentIcon { x: 20; anchors.verticalCenter: parent.verticalCenter; name: nr.icon; size: 20; color: theme.onFill(nr, nr.selected ? theme.brand : theme.textStrong) }
        Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: nr.label; font.family: theme.font; font.pixelSize: 14
               font.weight: nr.selected ? Font.DemiBold : Font.Normal; color: theme.onFill(nr, theme.text) }
        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checked: selected
    }
    component RowTool: Rectangle {
        id: rt
        property string icon
        property string tip
        property bool active: false
        property bool small: false
        signal clicked()
        width: small ? 24 : 32; height: small ? 24 : 32; radius: 4
        color: rth.hovered || rt.active ? theme.hc(theme.pick("#F5F5F5", "#3D3D3D", "#000000"), theme.hcHighlight) : "transparent"
        FluentIcon { anchors.centerIn: parent; name: rt.icon; size: rt.small ? 16 : 20; color: rt.active ? theme.brand : theme.onFill(rt, theme.textStrong) }
        HoverHandler { id: rth; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rt.clicked() }
        ToolTip.visible: rth.hovered; ToolTip.delay: 500; ToolTip.text: rt.tip
        Accessible.role: Accessible.Button
        Accessible.name: rt.tip
    }
    component DialogButton: Rectangle {
        id: db
        property string label
        signal clicked()
        width: 96; height: 32; radius: 4
        color: dbh.hovered ? theme.rowHover : theme.surface
        border.width: 1; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Text { anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(db, theme.text) }
        HoverHandler { id: dbh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: db.label
    }
    component SettingCard: Rectangle {
        id: sc
        property string icon
        property string title
        property string subtitle
        signal manage()
        width: parent ? parent.width : 700; height: 78; radius: 4
        color: theme.surface; border.width: 1; border.color: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
        FluentIcon { x: 20; anchors.verticalCenter: parent.verticalCenter; name: sc.icon; size: 20; color: theme.textStrong }
        Column {
            x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56 - 140
            Text { text: sc.title; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { width: parent.width; wrapMode: Text.Wrap; text: sc.subtitle; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
        }
        DialogButton { anchors.right: parent.right; anchors.rightMargin: 56; anchors.verticalCenter: parent.verticalCenter; label: qsTr("Manage"); onClicked: sc.manage() }
        Accessible.role: Accessible.Grouping
        Accessible.name: sc.title
    }
}
