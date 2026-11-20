import QtQuick
import QtQuick.Controls.Basic

// An installed app's compose panel in place of "+" (measured on winpc
// 2026-11-20, Power BI and Workflows in OST group test): 340 wide, at most
// 434 tall, radius 4, Teams' shadow 16.
// - The header: the app's 32 px icon (round, on #FAFAFA) at 16, 17 and its
//   name (14/20 bold) at 60, 23.
// - A search command: "Search here" (308 x 32 at 16, 60, #F5F5F5, radius
//   4 4 2 2, a brand line while focused, the search glyph at its end);
//   the app's results (its attachments' previews) under it; an error reads
//   "Unable to reach app. Please try again." (14, at 16, 103).
// - Several commands (or the app's own list, fetchCommands): one row per
//   command, its title and description.
Popup {
    id: root
    property var app: ({})
    /// The search command (a query panel) or null (the command list).
    property var command: null
    property string conversation: ""
    property Item anchorItem: null
    /// Results ({title, text, image, attachment}), "loading" or an error.
    property var results: []
    property string error: ""
    property bool loading: false
    property var commands: (app && app.commands) || []
    signal commandPicked(var command)
    signal resultPicked(var attachment)
    parent: Overlay.overlay
    width: 340; padding: 0
    height: Math.min(434, 103 + Math.max(40, body.implicitHeight) + 16)
    x: !anchorItem ? 0 : Math.min(Overlay.overlay.width - width - 8, anchorItem.mapToItem(Overlay.overlay, 0, 0).x + anchorItem.width - width)
    y: anchorItem ? anchorItem.mapToItem(Overlay.overlay, 0, 0).y - height - 8 : 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
    readonly property string reqId: "compose-app-panel"
    function ask(text) {
        if (!command) return
        root.loading = true; root.error = ""
        const param = ((command.parameters || [])[0] || {}).name || "query"
        backend.composeAppRequest("invoke", reqId, JSON.stringify({ bot: app.botId, appId: app.id, kind: "query", command: command.id,
            args: { text: text || "", parameter: param }, conversation: conversation }))
    }
    function openFor(a, cmd, anchor) {
        app = a; command = cmd; anchorItem = anchor
        results = []; error = ""; loading = false
        open()
        if (cmd && (cmd.initialRun || true)) ask("")
        else if (!cmd && (a.commands || []).length === 0) {
            root.loading = true
            backend.composeAppRequest("invoke", reqId, JSON.stringify({ bot: a.botId, appId: a.id, kind: "fetchCommands", command: "", args: {}, conversation: conversation }))
        }
    }
    Connections {
        target: backend
        function onComposeAppReply(id, json) {
            if (id !== root.reqId || !root.opened) return
            root.loading = false
            let r = {}
            try { r = JSON.parse(json) } catch (e) {}
            const ce = r.composeExtension || {}
            if (r.error || r.errorCode) { root.error = qsTr("Unable to reach app. Please try again."); return }
            if (ce.type === "command" || ce.commands) { root.commands = ce.commands || []; return }
            if (ce.type === "message") { root.error = ce.text || ""; return }
            const atts = ce.attachments || []
            root.results = atts.map(a => {
                const p = a.preview || a
                const c = p.content || {}
                const img = (c.images && c.images[0] && c.images[0].url) || ""
                return { title: String(c.title || "").replace(/<[^>]+>/g, ""), text: String(c.text || c.subtitle || "").replace(/<[^>]+>/g, ""), image: /^https:/.test(img) ? img : "", attachment: a }
            })
            if (root.results.length === 0) root.error = qsTr("We didn't find any matches.")
        }
    }
    Item {
        anchors.fill: parent
        Rectangle {
            x: 16; y: 17; width: 32; height: 32; radius: 16
            color: theme.pick("#FAFAFA", "#292929", "#000000")
            Image { anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(48, 48); source: root.app.icon || ""; asynchronous: true; fillMode: Image.PreserveAspectFit }
        }
        Text {
            x: 60; y: 23; width: parent.width - 76
            elide: Text.ElideRight
            text: root.app.name || ""
            lineHeight: 20; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            id: box
            visible: !!root.command
            x: 16; y: 60; width: 308; height: 32
            topLeftRadius: 4; topRightRadius: 4; bottomLeftRadius: 2; bottomRightRadius: 2
            color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: query.activeFocus ? 2 : 0.67; color: query.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: query
                x: 12; width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                Text { visible: !query.text; text: qsTr("Search here"); font: query.font; color: theme.textSecondary }
                onAccepted: root.ask(text)
                onTextEdited: searchDelay.restart()
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search here")
            }
            Timer { id: searchDelay; interval: 400; onTriggered: root.ask(query.text) }
            FluentIcon { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } name: "search-20"; size: 20; color: theme.textSecondary }
        }
        Flickable {
            x: 0; y: root.command ? 103 : 60
            width: parent.width; height: parent.height - y - 8
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: parent.width
                Text {
                    visible: !!root.error
                    x: 16; width: 308
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: root.error
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                }
                BusyIndicator { visible: root.loading; running: visible; anchors.horizontalCenter: parent.horizontalCenter }
                // The app's commands (no search command picked).
                Repeater {
                    model: root.command ? [] : root.commands
                    Rectangle {
                        id: cmdRow
                        required property var modelData
                        x: 8; width: 324; height: cmdCol.implicitHeight + 16; radius: 4
                        color: cmdHover.hovered ? theme.menuHover : "transparent"
                        Column {
                            id: cmdCol
                            x: 8; y: 8; width: parent.width - 16
                            Text { width: parent.width; elide: Text.ElideRight; text: cmdRow.modelData.title || cmdRow.modelData.id || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { visible: !!cmdRow.modelData.description; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: cmdRow.modelData.description || ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        }
                        HoverHandler { id: cmdHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const c = cmdRow.modelData; root.close(); root.commandPicked(c) } }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: cmdRow.modelData.title || ""
                    }
                }
                // Search results: each attachment's preview.
                Repeater {
                    model: root.command ? root.results : []
                    Rectangle {
                        id: resRow
                        required property var modelData
                        x: 8; width: 324; height: Math.max(56, resCol.implicitHeight + 16); radius: 4
                        color: resHover.hovered ? theme.menuHover : "transparent"
                        Image {
                            id: resImg
                            visible: !!resRow.modelData.image
                            x: 8; y: 8; width: 40; height: 40; sourceSize: Qt.size(80, 80)
                            source: resRow.modelData.image; asynchronous: true; fillMode: Image.PreserveAspectCrop
                        }
                        Column {
                            id: resCol
                            x: resImg.visible ? 56 : 8; y: 8; width: parent.width - x - 8
                            Text { width: parent.width; elide: Text.ElideRight; text: resRow.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { visible: !!resRow.modelData.text; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: resRow.modelData.text; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        }
                        HoverHandler { id: resHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { const a = resRow.modelData.attachment; root.close(); root.resultPicked(a) } }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: resRow.modelData.title
                    }
                }
            }
        }
    }
}
