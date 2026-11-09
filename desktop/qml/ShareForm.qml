import QtQuick
import QtQuick.Controls.Basic

// Teams' Share form (shareToTeams), as an app header's Share app opens it.
// Measured on winpc 2026-11-09 (scratchpad ab/share-dump.txt):
// - 600 wide, radius 8, content 25 in; "Share" (20/28 semibold) and close.
// - "Share to" (12/16), then a 551 x 32 picker on #F0F0F0 with "Type the
//   name of a person, group, or channel" and a chevron. Picks become 29 px
//   pills (28 px avatar, the name at 12/16, a 12 px dismiss) and the picker
//   grows to 41. Suggestions are grouped under People, Chats and Channels
//   (12/16 semibold headers); rows are 44 tall with a 32 px avatar.
// - "Say something about this", then a #F0F0F0 box with the message
//   ("Take a look at this app." and a link to the app) and the app's card
//   under an "App" header with a dismiss.
// - Copy link (outline, link icon) and Share (brand; disabled until
//   someone is picked).
// - Once shared, the form becomes "Your message has been shared." with
//   View (opens the conversation) and Done.
Popup {
    id: root
    property string appId: ""
    property bool done: false
    property var picked: []
    property string query: ""
    property bool showCard: true
    modal: true; focus: true
    width: 600
    height: done ? 130 : (picked.length > 0 ? 520 : 511)
    padding: 0
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }

    readonly property var info: { const r = backend.appDetailsJson ? JSON.parse(backend.appDetailsJson) : null; return r && r.app === appId ? r : null }
    readonly property var d: info && info.details ? info.details : null

    readonly property var people: query.trim().length === 0 ? [] : (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).filter(p => !picked.some(x => x.oid === p.id)).slice(0, 5)
    readonly property var chats: {
        const q = query.trim().toLowerCase()
        if (q.length < 1) return []
        const list = backend.chatsJson ? JSON.parse(backend.chatsJson) : []
        return list.filter(c => !c.isSelf && !String(c.id).endsWith("@unq.gbl.spaces") && String(c.id).endsWith("@thread.v2") && (c.name || "").toLowerCase().indexOf(q) >= 0 && !picked.some(x => x.id === c.id)).slice(0, 5)
    }
    readonly property var channels: {
        const q = query.trim().toLowerCase()
        if (q.length < 1) return []
        const out = []
        for (const t of (backend.teamsJson ? JSON.parse(backend.teamsJson) : []))
            for (const c of t.channels) if ((c.name + " " + t.name).toLowerCase().indexOf(q) >= 0 && !picked.some(x => x.id === c.id)) out.push({ id: c.id, name: c.name + " (" + t.name + ")" })
        return out.slice(0, 5)
    }
    // A chat or channel is a single choice; several people go to one group chat.
    readonly property bool single: picked.some(p => p.kind === "chat")
    readonly property var groups: {
        if (single) return []
        const g = []
        const ppl = people.map(p => ({ kind: "person", oid: p.id, name: p.name }))
        if (ppl.length) g.push({ title: "People", items: ppl })
        if (picked.length === 0) {
            if (chats.length) g.push({ title: "Chats", items: chats.map(c => ({ kind: "chat", id: c.id, name: c.name })) })
            if (channels.length) g.push({ title: "Channels", items: channels.map(c => ({ kind: "chat", id: c.id, name: c.name, channel: true })) })
        }
        return g
    }

    function start(id) {
        appId = id; done = false; picked = []; query = ""; search.text = ""; showCard = true
        backend.shareState = ""
        note.text = "Take a look at this app."
        if (!d) backend.appDetailsLoad(id)
        open()
        search.forceActiveFocus()
    }
    function pick(s) { picked = picked.concat([s]); search.text = ""; search.forceActiveFocus() }
    // Test hooks.
    function typeForTest(t) { search.text = t }
    function pickFirstForTest() { if (groups.length > 0) pick(groups[0].items[0]); return picked.length }
    function shareForTest() { share() }
    function share() {
        if (picked.length === 0 || backend.shareState === "sharing") return
        backend.shareApp(appId, JSON.stringify(picked), note.text, showCard)
    }
    Connections {
        target: backend
        function onShareStateChanged() { if (root.opened && backend.shareState === "shared") root.done = true }
    }

    component OutlineButton: Rectangle {
        id: ob
        property string label
        property string icon
        signal clicked()
        width: obRow.implicitWidth + 24; height: 31.33; radius: 4
        color: obHover.hovered ? theme.menuHover : theme.surface
        border.width: 0.67; border.color: obHover.hovered ? theme.strokeHover : theme.stroke
        Row {
            id: obRow
            anchors.centerIn: parent; spacing: 8
            FluentIcon { visible: !!ob.icon; anchors.verticalCenter: parent.verticalCenter; name: ob.icon; size: 20; color: theme.textStrong }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ob.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        }
        HoverHandler { id: obHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ob.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ob.label
    }

    contentItem: Item {
        Text {
            x: 25; y: 25; width: 511; height: 31; verticalAlignment: Text.AlignVCenter
            text: root.done ? "Your message has been shared." : "Share"
            font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Rectangle {
            x: 543; y: 25; width: 32; height: 31.33; radius: 4
            color: closeHover.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Close"
        }

        // ---- Shared ----
        Row {
            visible: root.done
            x: 375; y: 74; spacing: 8
            OutlineButton {
                width: 96; label: "View"
                onClicked: { const c = backend.sharedConversation(); root.close(); if (c) backend.selectChat(c, "") }
            }
            Rectangle {
                width: 96; height: 31.33; radius: 4
                color: doneHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Done"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                HoverHandler { id: doneHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Done"
            }
        }

        // ---- The form ----
        Item {
            visible: !root.done
            anchors.fill: parent
            Text { x: 25; y: 64; height: 20; verticalAlignment: Text.AlignVCenter; text: "Share to"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Rectangle {
                id: picker
                x: 25; y: 86; width: 551; height: root.picked.length > 0 ? 41 : 32; radius: 4
                color: theme.inputFilledDark
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: search.activeFocus ? 2 : 0; color: theme.brand; radius: 1 }
                Flow {
                    id: tags
                    x: 12; width: 510; height: parent.height
                    spacing: 6; topPadding: root.picked.length > 0 ? 6 : 0
                    Repeater {
                        model: root.picked
                        Rectangle {
                            id: tag
                            required property var modelData
                            required property int index
                            width: tagName.x + tagName.implicitWidth + 24; height: 29; radius: 14.5
                            color: theme.pane
                            Avatar { x: 1; y: 0.5; size: 28; name: tag.modelData.name; photoId: tag.modelData.oid || ""; group: tag.modelData.kind === "chat" }
                            Text { id: tagName; x: 37; anchors.verticalCenter: parent.verticalCenter; text: tag.modelData.name; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
                            FluentIcon {
                                x: tagName.x + tagName.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; name: "dismiss-12"; size: 12; color: theme.textStrong
                                TapHandler { onTapped: { const p = root.picked.slice(); p.splice(tag.index, 1); root.picked = p; search.forceActiveFocus() } }
                            }
                            Accessible.role: Accessible.Button; Accessible.name: "Remove " + tag.modelData.name
                        }
                    }
                    TextField {
                        id: search
                        visible: !root.single
                        width: root.picked.length > 0 ? 160 : tags.width
                        height: root.picked.length > 0 ? 29 : 32
                        leftPadding: 0
                        placeholderText: root.picked.length > 0 ? "" : "Type the name of a person, group, or channel"
                        placeholderTextColor: theme.textTertiary
                        background: null
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                        onTextChanged: { root.query = text; if (text.trim().length > 0) backend.searchPeople(text) }
                        Keys.onReturnPressed: if (root.groups.length > 0) root.pick(root.groups[0].items[0])
                        Accessible.name: "Share to"
                    }
                }
                FluentIcon { x: 522; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.textStrong }
            }

            Text { x: 25; y: picker.y + picker.height + 15; height: 16; text: "Say something about this"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
            Rectangle {
                id: compose
                x: 25; y: picker.y + picker.height + 39; width: 551; height: 276
                color: theme.inputFilledDark
                Flickable {
                    anchors.fill: parent
                    contentHeight: composeCol.height + 20
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: composeCol
                        x: 12; y: 10; width: 527
                        TextEdit {
                            id: note
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                            selectByMouse: true
                            Accessible.role: Accessible.EditableText; Accessible.name: "Say something about this"
                        }
                        Item { width: 1; height: 20 }
                        Text {
                            text: root.d ? root.d.name : ""
                            font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                            font.underline: true
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: if (root.d) Qt.openUrlExternally(root.d.share_link) }
                        }
                        Item { width: 1; height: 11 }
                        // The app's card preview.
                        Rectangle {
                            visible: root.showCard && !!root.info && !!root.info.card
                            x: 6; width: 356; height: visible ? 40 + previewCard.height : 0
                            radius: 6; color: theme.quoteFill
                            border.width: 0.67; border.color: theme.quoteBorder
                            Row {
                                x: 16; y: 16; spacing: 12
                                FluentIcon { name: "apps-20"; size: 20; color: theme.textStrong }
                                Text { height: 20; verticalAlignment: Text.AlignVCenter; text: "App"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                            }
                            FluentIcon {
                                x: 320; y: 18; name: "dismiss-20"; size: 20; color: theme.textStrong
                                TapHandler { onTapped: root.showCard = false }
                                Accessible.role: Accessible.Button; Accessible.name: "Remove the card"
                            }
                            AdaptiveCard {
                                id: previewCard
                                y: 40
                                content: root.info && root.info.card ? root.info.card : ({})
                                cardWidth: 356
                                topInset: 16
                                framed: false
                            }
                        }
                    }
                }
            }

            // Suggestions under the picker.
            Rectangle {
                visible: root.groups.length > 0 && search.activeFocus
                x: 25; y: picker.y + picker.height + 2; width: 551
                height: sugCol.height + 8; radius: 4
                color: theme.menu
                border.width: 0.67; border.color: theme.dividerSoft
                z: 10
                Column {
                    id: sugCol
                    x: 4; y: 4; width: 543
                    Repeater {
                        model: root.groups
                        Column {
                            required property var modelData
                            width: 543
                            Text { x: 8; height: 32; verticalAlignment: Text.AlignVCenter; text: modelData.title; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Repeater {
                                model: modelData.items
                                Rectangle {
                                    required property var modelData
                                    width: 543; height: 44; radius: 4
                                    color: sugHover.hovered ? theme.menuHover : "transparent"
                                    Avatar { x: 8; y: 6; size: 32; name: modelData.name; photoId: modelData.oid || ""; group: modelData.kind === "chat" }
                                    Text { x: 49; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                    HoverHandler { id: sugHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.pick(modelData) }
                                    Accessible.role: Accessible.ListItem; Accessible.name: modelData.name
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: backend.shareState === "error"
                x: 25; y: compose.y + compose.height + 6
                text: "Something went wrong while trying to share to Teams."
                font.family: theme.font; font.pixelSize: 12; color: theme.redForeground1
            }
            Row {
                x: 576 - width; y: compose.y + compose.height + 22
                spacing: 8
                OutlineButton {
                    label: copied.running ? "Link copied" : "Copy link"; icon: "link-20"
                    onClicked: { if (root.d) { backend.copyText(root.d.share_link); copied.restart() } }
                    Timer { id: copied; interval: 3000 }
                }
                Rectangle {
                    width: 96; height: 31.33; radius: 4
                    readonly property bool on: root.picked.length > 0 && backend.shareState !== "sharing" && !!root.d
                    color: !on ? theme.bgDisabled : shareHover.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: backend.shareState === "sharing" ? "Sharing" : "Share"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? theme.textOnBrand : theme.disabled }
                    HoverHandler { id: shareHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: parent.on; onTapped: root.share() }
                    Accessible.role: Accessible.Button; Accessible.name: "Share"
                }
            }
        }
    }
}
