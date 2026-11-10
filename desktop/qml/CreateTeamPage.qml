import QtQuick
import QtQuick.Controls.Basic

// Teams' Create team page (Create a team ▸ More create team options;
// measured on winpc 2026-11-09). It takes the chat list's and the
// conversation's place:
// - Left (380, #EBEBEB): Back (32 x 31.3 at 10, 14) and "Create team"
//   (16/22 bold) at 42; From template / From another team / From group
//   (380 x 40 rows from 60, 42 apart; text 40 in, 14/20; the chosen one
//   white, the others #424242); "What's a team?" (13, brand, underlined)
//   at 40, 214.
// - From template: "Create a team from a template" (16/22 bold) at 32, 20
//   and "Skip the setup and use a template to get your team engaged
//   quickly." at 47; cards 260 x 120 (14 apart, 134 down; padding 12,
//   radius 4, #D1D1D1 line, shadow, #F5F5F5 on hover): a 48 px picture,
//   the name (14 bold) and category (12/16) 72.7 in, the line (12/16) 76.7
//   down. From scratch first. A card opens the template's details.
// - From another team: "Which team do you want to use?" (24/32 bold) and
//   Teams' line, centred; 280 x 300 cards of the teams you own (picture
//   48, name 16/22 bold, lock and Private / Public, description).
// - From group: "Which Microsoft 365 group do you want to use?", "This
//   will permanently add Teams to your existing Microsoft 365 Group." and
//   Learn more; with none, Teams' cactus (205 x 166) and "You need to own a
//   group with fewer than 10000 people to create a team from that group." /
//   "Please create a group first." (18/25.7 bold).
Rectangle {
    id: page
    property string view: "template"
    signal back()
    signal teamCreated(string groupId, string threadId)
    color: theme.surface
    readonly property var ownedTeams: (backend.teamsJson ? JSON.parse(backend.teamsJson) : []).filter(t => t.role === "admin" && !t.archived)
    property var templates: []
    property var groups: []
    property bool groupsLoaded: false
    function load() {
        view = "template"
        backend.channelAction("team-templates", "", "", "")
        backend.channelAction("my-groups", "", "", "")
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "team-templates" && r.ok) page.templates = r.data || []
            else if (r.op === "my-groups") { page.groupsLoaded = true; page.groups = r.ok ? r.data || [] : [] }
            else if (r.op === "team-template" && r.ok && templateDialog.loading) { templateDialog.loading = false; templateDialog.details = r.data }
        }
    }

    // ---- Left pane ----
    Rectangle {
        id: left
        width: 380; height: parent.height
        color: theme.pick("#EBEBEB", "#1F1F1F")
        Rectangle {
            x: 10; y: 14; width: 32; height: 31.3; radius: 4
            color: backHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-left-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: page.back() }
            Accessible.role: Accessible.Button
            Accessible.name: "Back to channel list"
        }
        Text { x: 42; y: 18.7; text: "Create team"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            model: [["template", "From template"], ["another", "From another team"], ["group", "From group"]]
            Rectangle {
                id: nav
                required property var modelData
                required property int index
                readonly property bool sel: page.view === modelData[0]
                y: 60 + index * 42; width: 380; height: 40; radius: 4
                color: sel ? theme.surface : navHover.hovered ? theme.pick("#F5F5F5", "#292929") : "transparent"
                Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: nav.sel ? theme.text : theme.textStrong }
                HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.view = nav.modelData[0] }
                Accessible.role: Accessible.RadioButton
                Accessible.name: nav.modelData[1]
                Accessible.checked: sel
            }
        }
        Text {
            x: 40; y: 214
            text: "What's a team?"
            font.family: theme.font; font.pixelSize: 13; font.underline: true
            color: theme.brandForeground1
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2275168") }
            Accessible.role: Accessible.Link
            Accessible.name: text
        }
    }

    component Card: Rectangle {
        id: card
        signal clicked()
        radius: 4
        color: cardHover.hovered ? theme.pick("#F5F5F5", "#2E2E2E") : theme.surface
        border.color: theme.stroke; border.width: 0.67
        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: card.clicked() }
        Accessible.role: Accessible.Button
    }

    // ---- From template ----
    Flickable {
        visible: page.view === "template"
        x: left.width; width: parent.width - x; height: parent.height
        contentHeight: 98 + Math.ceil((page.templates.length + 1) / 2) * 134 + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Text { x: 32; y: 20; text: "Create a team from a template"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { x: 32; y: 47; text: "Skip the setup and use a template to get your team engaged quickly."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            model: [{ id: "", name: "From scratch", category: "", short_description: "We'll help you create a basic team.", icon: "" }].concat(page.templates)
            Card {
                id: tcard
                required property var modelData
                required property int index
                x: 31 + (index % 2) * 274; y: 98 + Math.floor(index / 2) * 134
                width: 260; height: 120
                Accessible.name: modelData.name
                onClicked: modelData.id ? templateDialog.start(modelData) : createDialog.startScratch()
                Image {
                    x: 12.7; y: 12.7; width: 48; height: 48
                    source: tcard.modelData.icon || "../assets/illustrations/team-from-scratch.svg"
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                }
                Text { x: 72.7; y: 12.7; width: 162.7; elide: Text.ElideRight; text: tcard.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { x: 72.7; y: 33.7; width: 162.7; elide: Text.ElideRight; text: tcard.modelData.category; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text { x: 12.7; y: 76.7; width: 234.7; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight; text: tcard.modelData.short_description; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
            }
        }
    }

    // ---- From another team ----
    Flickable {
        visible: page.view === "another"
        x: left.width; width: parent.width - x; height: parent.height
        contentHeight: 196 + Math.ceil(page.ownedTeams.length / Math.max(1, Math.floor((width - 40) / 296))) * 316
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Text { width: parent.width; y: 80; horizontalAlignment: Text.AlignHCenter; text: "Which team do you want to use?"; font.family: theme.font; font.pixelSize: 24; font.weight: Font.Bold; lineHeight: 32; lineHeightMode: Text.FixedHeight; color: theme.text }
        Text { width: parent.width; y: 129; horizontalAlignment: Text.AlignHCenter; text: "Copy apps, settings, and channels over to your new team. Your existing team won't be changed"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Flow {
            readonly property int perRow: Math.max(1, Math.min(page.ownedTeams.length, Math.floor((parent.width - 40) / 296)))
            // Teams' grid sits 12 right of centre.
            x: (parent.width - (perRow * 280 + (perRow - 1) * 16)) / 2 + 12; y: 196
            width: perRow * 280 + (perRow - 1) * 16
            spacing: 16
            Repeater {
                model: page.ownedTeams
                Card {
                    id: acard
                    required property var modelData
                    width: 280; height: 300
                    Accessible.name: modelData.name
                    onClicked: createDialog.startClone(modelData)
                    Avatar {
                        x: (parent.width - 48) / 2; y: 41; size: 48; square: true; squareRadius: 4
                        name: acard.modelData.name || ""
                        initialsText: (acard.modelData.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: "team:" + acard.modelData.id
                    }
                    Text { x: 12.7; width: 254.7; y: 109; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: acard.modelData.name || ""; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 161; spacing: 10
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: acard.modelData["public"] ? "globe-20" : "lock-closed-20-filled"; size: 12; color: theme.text }
                        Text { text: acard.modelData["public"] ? "Public" : "Private"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    }
                    Text { x: 12.7; width: 254.7; y: 217; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: acard.modelData.description || ""; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                }
            }
        }
    }

    // ---- From group ----
    Item {
        visible: page.view === "group"
        x: left.width; width: parent.width - x; height: parent.height
        Text { x: 32; y: 20; text: "Which Microsoft 365 group do you want to use?"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 22; lineHeightMode: Text.FixedHeight; color: theme.text }
        Row {
            x: 32; y: 47
            Text { text: "This will permanently add Teams to your existing Microsoft 365 Group. "; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text {
                text: "Learn more"; font.family: theme.font; font.pixelSize: 14; font.underline: true; lineHeight: 20; lineHeightMode: Text.FixedHeight
                color: theme.brandForeground1
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally("https://go.microsoft.com/fwlink/?linkid=2275168") }
                Accessible.role: Accessible.Link; Accessible.name: "Learn more"
            }
        }
        Image {
            visible: page.groupsLoaded && page.groups.length === 0
            x: (parent.width - width) / 2; y: 206.8; width: 205; height: 166
            source: "../assets/illustrations/no-groups.svg"
            sourceSize: Qt.size(410, 332)
            fillMode: Image.PreserveAspectFit
        }
        Column {
            visible: page.groupsLoaded && page.groups.length === 0
            y: 410.8; width: parent.width; spacing: 36
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "You need to own a group with fewer than 10000 people to create a team from that group."; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Please create a group first."; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text }
        }
        // Your groups (none in the test tenant; Teams' team cards).
        Flow {
            visible: page.groups.length > 0
            x: 31; y: 98; width: parent.width - 62; spacing: 14
            Repeater {
                model: page.groups
                Card {
                    id: gcard
                    required property var modelData
                    width: 260; height: 120
                    Accessible.name: modelData.name
                    onClicked: groupConfirm.start(modelData)
                    Avatar { x: 12.7; y: 12.7; size: 48; square: true; squareRadius: 4; name: gcard.modelData.name || "" }
                    Text { x: 72.7; y: 12.7; width: 162.7; elide: Text.ElideRight; text: gcard.modelData.name; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
                    Text { x: 72.7; y: 33.7; width: 162.7; elide: Text.ElideRight; text: gcard.modelData.mail; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                    Text { x: 12.7; y: 76.7; width: 234.7; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight; text: gcard.modelData.description; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                }
            }
        }
    }
    ConfirmDialog {
        id: groupConfirm
        property var group: null
        function start(g) { group = g; open() }
        title: "Create a team from " + (group ? group.name : "")
        body: "This will permanently add Teams to your existing Microsoft 365 Group."
        confirmText: "Create"
        onConfirmed: backend.channelAction("create-team", "", "", JSON.stringify({ mode: "group", group: groupConfirm.group }))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "create-team" && !createDialog.opened) {
                if (r.ok) page.teamCreated(r.data.group_id || "", r.data.thread_id || "")
                else backend.toast("We couldn't create your team. Please try again.", "error")
            }
        }
    }

    CreateTeamDialog { id: createDialog; onCreated: (g, t) => page.teamCreated(g, t) }

    // A template's details (600 x 600): its name and Close; the
    // description (14/20) at 40; "N channels" (channel icon, 14 bold) at
    // 10.3 / 40, 105 with the channels (12/16) 20 apart from 151; "N apps"
    // (apps icon) at 278 / 305.3 with each app's 20 px picture and name
    // (12/16, 34 in), rows 27 apart, an app's SharePoint lists or pages
    // under it (24 apart, a chevron to fold them); "Use this template"
    // (primary, 135.9 x 31.3) at the bottom right.
    Popup {
        id: templateDialog
        property var template: null
        property var details: null
        property bool loading: false
        property var folded: ({})
        function start(t) {
            template = t; details = null; loading = true; folded = ({})
            backend.channelAction("team-template", "", "", JSON.stringify({ path: t.path }))
            open()
        }
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; width: 600; height: 600; padding: 24
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: theme.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(0, 0, 0, 0.5)) }
        readonly property var d: details || ({ channels: [], apps: [] })
        readonly property var rows: {
            // The apps' rows, laid out as Teams spaces them.
            const out = []
            let y = 154
            for (const a of (templateDialog.d.apps || [])) {
                const items = templateDialog.folded[a.id] ? [] : (a.items || [])
                if ((a.items || []).length) {
                    y -= 1.7
                    out.push({ app: a, y: y, items: items, expandable: true })
                    y += 30.7 + items.length * 24 + 3
                } else {
                    out.push({ app: a, y: y, items: [], expandable: false })
                    y += 27
                }
            }
            return out
        }
        Text {
            y: 0.7; width: 510.7; elide: Text.ElideRight
            text: templateDialog.template ? templateDialog.template.name : ""
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 28; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        Rectangle {
            x: 518.7; width: 32; height: 31.3; radius: 4
            color: tclose.hovered ? theme.menuHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: tclose; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: templateDialog.close() }
            Accessible.role: Accessible.Button; Accessible.name: "Close"
        }
        Text {
            y: 40; width: 550.7; wrapMode: Text.Wrap
            text: templateDialog.details ? templateDialog.details.description : (templateDialog.template ? templateDialog.template.description : "")
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        FluentIcon { visible: !!templateDialog.details; x: 10.3; y: 105; name: "channel-20-filled"; size: 20; color: theme.text }
        Text { visible: !!templateDialog.details; x: 40; y: 105; text: (templateDialog.d.channels || []).length + " channels"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            model: templateDialog.d.listed_channels || []
            Text { required property var modelData; required property int index; x: 40; y: 151 + index * 20; width: 220; elide: Text.ElideRight; text: modelData.displayName; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        }
        FluentIcon { visible: !!templateDialog.details; x: 278; y: 105; name: "apps-20-filled"; size: 20; color: theme.text }
        Text { visible: !!templateDialog.details; x: 305.3; y: 105; text: (templateDialog.details ? templateDialog.details.app_ids.length : 0) + " apps"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
        Repeater {
            model: templateDialog.rows
            Item {
                id: arow
                required property var modelData
                x: 0; y: modelData.y; width: 550.7; height: 20
                Rectangle {
                    visible: arow.modelData.expandable
                    x: 281.3; width: 24; height: 23.3; radius: 4
                    color: foldHover.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: templateDialog.folded[arow.modelData.app.id] ? "chevron-right-16" : "chevron-down-16"; size: 14; color: theme.textStrong }
                    HoverHandler { id: foldHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { const f = Object.assign({}, templateDialog.folded); f[arow.modelData.app.id] = !f[arow.modelData.app.id]; templateDialog.folded = f } }
                    Accessible.role: Accessible.Button
                    Accessible.name: (templateDialog.folded[arow.modelData.app.id] ? "Show " : "Hide ") + arow.modelData.app.name + " items"
                }
                Image { x: 305.3; width: 20; height: 20; source: arow.modelData.app.icon || ""; sourceSize: Qt.size(40, 40); fillMode: Image.PreserveAspectFit }
                Text { x: 339.3; y: arow.modelData.expandable ? 7.4 : 4; text: arow.modelData.app.name; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                Repeater {
                    model: arow.modelData.items
                    Text { required property var modelData; required property int index; x: 339.3; y: 30.7 + index * 24; text: modelData; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
                }
            }
        }
        Rectangle {
            anchors.right: parent.right; y: 520; width: 135.9; height: 31.3; radius: 4
            color: !templateDialog.details ? theme.bgDisabled : useHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Use this template"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: templateDialog.details ? theme.textOnBrand : theme.disabled }
            HoverHandler { id: useHover; enabled: !!templateDialog.details; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: !!templateDialog.details
                onTapped: {
                    const d = templateDialog.details
                    templateDialog.close()
                    createDialog.startTemplate({ id: d.id, name: d.name, locale: d.locale, visibility: d.visibility, channels: d.channels, app_ids: d.app_ids })
                }
            }
            Accessible.role: Accessible.Button; Accessible.name: "Use this template"
        }
    }

    // Test hooks.
    function templateDialogForTest() { return templateDialog }
    function createDialogForTest() { return createDialog }
}
