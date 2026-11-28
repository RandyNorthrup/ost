import QtQuick
import QtQuick.Controls.Basic

// The Meet app of Teams for personal use (TASK-0298), laid out as Teams'
// (measured on teams.live.com as OST Personal 1, 2026-11-28, at 1x):
// - a 400 px left pane titled "Meet" with Meeting links, Schedule a
//   meeting and Calls;
// - Meeting links: "Create a meeting link" (brand, 444 x 60) and "Join with
//   a meeting ID" side by side, then a card per link (its title, "Created
//   …", ··· with Edit meeting name, Join and Share link) and the card
//   "Quickly create, save, and share links with anyone." with "Learn more
//   about meeting links";
// - Create a meeting link asks "Give your meeting a title" ("Meeting with
//   <you>") and "Create and copy link" ("Link copied to clipboard").
// The links are your Meet now chats (api::calendar::meeting_links).
Item {
    id: root
    /// Your meeting chats (ids) from the chat list: where the links are.
    property var meetingChats: []
    property string myName: ""
    property string page: "links"
    property var links: []
    property bool loading: false
    signal calendarAction(string op, string args)
    signal joinLink(string url, string title)
    signal joinWithId(string meetingId, string passcode)
    signal scheduleMeeting()
    signal openCalls()
    signal toast(string text)

    function reload() {
        loading = true
        calendarAction("meetingLinks", JSON.stringify({ threads: meetingChats }))
    }
    onVisibleChanged: if (visible) reload()
    /// Calendar actions' answers (Main forwards "meetingLinks" and
    /// "meetLink" here).
    function actionDone(op, result, error) {
        let r = {}
        try { r = JSON.parse(result || "{}") } catch (e) {}
        if (op === "meetingLinks") { loading = false; if (!error) links = r.links || [] }
        else if (op === "meetLink") {
            if (error || !r.joinUrl) { toast(qsTr("Couldn't create a meeting link. Try again.")); return }
            copy(r.joinUrl)
            toast(qsTr("Link copied to clipboard"))
            reloadTimer.restart()
        }
    }
    // The new chat shows in the chat list a moment later.
    Timer { id: reloadTimer; interval: 2500; onTriggered: root.reload() }
    function copy(text) { clip.text = text; clip.selectAll(); clip.copy() }
    TextEdit { id: clip; visible: false }
    function created(iso) {
        const t = new Date(iso)
        if (isNaN(t.getTime())) return ""
        const mins = Math.round((Date.now() - t.getTime()) / 60000)
        if (mins < 1) return qsTr("Created just now")
        if (mins < 60) return qsTr("Created %n minute(s) ago", "", mins)
        if (mins < 24 * 60) return qsTr("Created %n hour(s) ago", "", Math.round(mins / 60))
        return qsTr("Created %1").arg(t.toLocaleDateString(Qt.locale(), Locale.ShortFormat))
    }

    Rectangle { anchors.fill: parent; color: theme.chrome }

    // Left pane.
    Item {
        id: side
        width: 400; height: parent.height
        Text {
            x: 20; y: 18; text: qsTr("Meet")
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Column {
            x: 20; y: 69; width: parent.width - 40; spacing: 0
            Repeater {
                model: [
                    { key: "links", icon: "link-20", label: qsTr("Meeting links") },
                    { key: "schedule", icon: "calendar-ltr-20", label: qsTr("Schedule a meeting") },
                    { key: "calls", icon: "call-20", label: qsTr("Calls") }
                ]
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    readonly property bool current: root.page === modelData.key
                    width: parent.width; height: 48; radius: 4
                    color: current ? theme.surface : navHover.hovered ? theme.rowHover : "transparent"
                    Row {
                        x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: navItem.modelData.icon; size: 20; color: navItem.current ? theme.brand : theme.text }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter; text: navItem.modelData.label
                            font.family: theme.font; font.pixelSize: 16; font.weight: navItem.current ? Font.Bold : Font.DemiBold; color: theme.text
                        }
                    }
                    HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (navItem.modelData.key === "schedule") root.scheduleMeeting()
                            else if (navItem.modelData.key === "calls") root.openCalls()
                            else root.page = navItem.modelData.key
                        }
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                    Accessible.selected: current
                    Accessible.onPressAction: if (modelData.key === "links") root.page = "links"
                }
            }
        }
    }

    // Meeting links.
    Rectangle {
        anchors { left: side.right; top: parent.top; right: parent.right; bottom: parent.bottom; margins: 8; leftMargin: 20 }
        radius: 8; color: theme.surface
        Flickable {
            anchors.fill: parent; anchors.margins: 32
            contentHeight: body.height; clip: true
            Item {
                id: body
                readonly property real colW: Math.min(444, (width - 32) / 2)
                width: parent.width; height: grid.y + grid.height + 32
                // Create a meeting link | Join with a meeting ID.
                Rectangle {
                    id: createButton
                    width: body.colW; height: 60; radius: 6
                    color: createHover.hovered ? theme.brandHover : theme.brandFill
                    Row {
                        anchors.centerIn: parent; spacing: 10
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "link-20"; size: 20; color: theme.onFill(createButton, "white") }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Create a meeting link"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.onFill(createButton, "white") }
                    }
                    HoverHandler { id: createHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { titleInput.text = qsTr("Meeting with %1").arg(root.myName); createPopup.open(); titleInput.forceActiveFocus(); titleInput.selectAll() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Create a meeting link")
                    Popup {
                        id: createPopup
                        y: parent.height + 4; x: (parent.width - width) / 2
                        width: 316; padding: 16
                        background: Rectangle { radius: 4; color: theme.menu; border.color: theme.stroke }
                        contentItem: Column {
                            spacing: 12
                            Item {
                                width: 284; height: 20
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Give your meeting a title"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                FluentIcon {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-20"; size: 16; color: theme.text
                                    TapHandler { onTapped: createPopup.close() }
                                    Accessible.role: Accessible.Button; Accessible.name: qsTr("Close")
                                }
                            }
                            Rectangle {
                                width: 284; height: 32; radius: 4
                                color: theme.inputFilled; border.color: titleInput.activeFocus ? theme.brand : "transparent"
                                TextInput {
                                    id: titleInput
                                    x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
                                    onAccepted: createGo.go()
                                    Accessible.role: Accessible.EditableText
                                    Accessible.name: qsTr("Give your meeting a title")
                                }
                            }
                            Rectangle {
                                id: createGo
                                function go() {
                                    root.calendarAction("meetLink", JSON.stringify({ subject: titleInput.text.trim() || qsTr("Meeting with %1").arg(root.myName), start: false }))
                                    createPopup.close()
                                }
                                width: 284; height: 32; radius: 4
                                color: goHover.hovered ? theme.brandHover : theme.brandFill
                                Text { anchors.centerIn: parent; text: qsTr("Create and copy link"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(createGo, "white") }
                                HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: createGo.go() }
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Create and copy link")
                            }
                        }
                    }
                }
                Rectangle {
                    id: joinButton
                    x: body.colW + 32; width: body.colW; height: 60; radius: 6
                    color: joinHover.hovered ? theme.rowHover : theme.surface; border.color: theme.stroke
                    Row {
                        anchors.centerIn: parent; spacing: 10
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "number-symbol-square-20"; size: 20; color: theme.brand }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Join with a meeting ID"); font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                    }
                    HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { idInput.text = ""; passInput.text = ""; joinPopup.open(); idInput.forceActiveFocus() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Join with a meeting ID")
                }
                // The links, then Teams' explainer card.
                Flow {
                    id: grid
                    y: 94; width: body.colW * 2 + 32; spacing: 24
                    Repeater {
                        model: root.links
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            width: body.colW; height: 190; radius: 8
                            color: theme.surface; border.color: theme.stroke
                            Rectangle {
                                x: 20; y: 20; width: 40; height: 40; radius: 20; color: theme.pick("#FFF4CE", "#4A3D00", "#000000")
                                FluentIcon { anchors.centerIn: parent; name: "lightbulb-20"; size: 20; color: theme.pick("#C19C00", "#FCE100", "#FFFFFF") }
                            }
                            Text {
                                x: 20; y: 74; width: parent.width - 40; elide: Text.ElideRight
                                text: card.modelData.title; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                            }
                            Text {
                                x: 20; y: 100; text: root.created(card.modelData.created)
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                            Row {
                                x: 20; y: 138; spacing: 16
                                Repeater {
                                    model: [qsTr("Join"), qsTr("Share link")]
                                    delegate: Rectangle {
                                        id: cardButton
                                        required property string modelData
                                        required property int index
                                        width: (card.width - 56) / 2; height: 32; radius: 4
                                        color: cbHover.hovered ? theme.rowHover : theme.chrome
                                        Text { anchors.centerIn: parent; text: cardButton.modelData; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                                        HoverHandler { id: cbHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                if (cardButton.index === 0) root.joinLink(card.modelData.join_url, card.modelData.title)
                                                else { root.copy(card.modelData.join_url); root.toast(qsTr("Link copied to clipboard")) }
                                            }
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData + " " + card.modelData.title
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        width: body.colW; height: 190; radius: 8
                        color: theme.surface; border.color: theme.stroke
                        FluentIcon { x: 20; y: 24; name: "link-20"; size: 32; color: theme.brand }
                        Text {
                            x: 20; y: 74; width: parent.width - 40; wrapMode: Text.Wrap
                            text: qsTr("Quickly create, save, and share links with anyone.")
                            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
                        }
                        Text {
                            x: 20; y: 138; text: qsTr("Learn more about meeting links")
                            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brand
                            TapHandler { onTapped: backend.openExternal("https://support.microsoft.com/teams/personal/meetings-calls/create-a-meeting-in-microsoft-teams-personal") }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Accessible.role: Accessible.Link
                            Accessible.name: text
                        }
                    }
                }
            }
        }
    }

    // Join with a meeting ID (Teams' dialog: Meeting ID, Meeting passcode,
    // Join meeting).
    Popup {
        id: joinPopup
        anchors.centerIn: Overlay.overlay
        modal: true; padding: 24; width: 480
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.hc("transparent", "#FFFFFF") }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        readonly property bool ready: idInput.text.replace(/\s/g, "").length > 0
        contentItem: Column {
            spacing: 12
            Text { text: qsTr("Join a meeting with an ID"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Repeater {
                model: [{ label: qsTr("Meeting ID"), hint: qsTr("Type a meeting ID") }, { label: qsTr("Meeting passcode"), hint: qsTr("Type a meeting passcode") }]
                delegate: Column {
                    id: fieldCol
                    required property var modelData
                    required property int index
                    spacing: 4
                    Text { text: fieldCol.modelData.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Rectangle {
                        width: 432; height: 32; radius: 4; color: theme.surface
                        border.color: (fieldCol.index === 0 ? idInput : passInput).activeFocus ? theme.brand : theme.stroke
                        data: [fieldCol.index === 0 ? idInput : passInput]
                    }
                }
            }
            Rectangle {
                id: joinGo
                anchors.right: parent.right
                width: 120; height: 32; radius: 4
                color: !joinPopup.ready ? theme.pick("#F0F0F0", "#2E2E2E", "#000000") : jgHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("Join meeting"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: joinPopup.ready ? theme.onFill(joinGo, "white") : theme.disabled }
                HoverHandler { id: jgHover; cursorShape: joinPopup.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: joinPopup.ready; onTapped: { root.joinWithId(idInput.text.replace(/\s/g, ""), passInput.text.trim()); joinPopup.close() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Join meeting")
            }
        }
    }
    TextInput {
        id: idInput
        x: 12; width: 408; y: 7
        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
        Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Meeting ID")
    }
    TextInput {
        id: passInput
        x: 12; width: 408; y: 7
        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true; selectByMouse: true
        Accessible.role: Accessible.EditableText; Accessible.name: qsTr("Meeting passcode")
    }
}
