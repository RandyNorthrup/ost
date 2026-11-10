import QtQuick
import QtQuick.Controls.Basic

// Teams' Join a team page (Create team ▸ Join Team; measured on winpc
// 2026-11-09, cards read from its teams-gallery code). It takes the chat
// list's and the conversation's place:
// - Left (380, #F5F5F5): Back (32 x 31.3 at 11, 12), "Join a team" (18/25.7
//   bold) at 43, a "Create a new team" + (32 x 31.3) at 328; Type to search
//   (368 x 32 at 4, 59.3; a search glyph, a dismiss while there's text);
//   the lists Search results (while searching) and Teams for you (368 x 32
//   rows from 99.3, the chosen one white, text 16 in).
// - Teams for you (`beta/teams/suggested`): with none, "You don't have any
//   teams discoverable" / "Try searching, join with a code, or create one."
//   (18/25.7 bold) and "Not sure why you should create a team? Watch this"
//   centred from 40; then 238 x 268 cards (padding 20 11, #D1D1D1 line)
//   from 151.4, 16 apart: Join a team with a code (Teams' # picture, an
//   "Enter join code." field, Add team once there's a code) and Create a
//   new team (Teams' picture, three people, the primary button). With
//   suggestions the join-with-a-code card comes first, then a card per
//   team: its picture (64), name, lock and Private or Public, description
//   and people you know, and Join team (Request sent / Joining... / Joined
//   team after).
// - Search results (`beta/teams/find`, on Enter): the cards, or Teams'
//   "We didn't find any matches", "This could be a good time to create a
//   new team." and Create a new team.
Rectangle {
    id: page
    property string view: "suggested"
    property var suggested: []
    property bool suggestedLoaded: false
    property var results: []
    property string searched: ""
    property bool searching: false
    property var joinState: ({})
    property bool codeBusy: false
    signal back()
    signal createTeam()
    signal joined(string groupId, string threadId)
    color: theme.surface

    function load() {
        view = "suggested"; search.text = ""; searched = ""; results = []; joinState = ({})
        backend.channelAction("teams-suggested", "", "", "")
    }
    function runSearch() {
        const q = search.text.trim()
        if (!q) return
        searching = true; view = "results"
        backend.channelAction("teams-find", "", "", JSON.stringify({ q: q }))
    }
    function join(team) {
        const s = Object.assign({}, joinState); s[team.group_id] = "Joining"; joinState = s
        backend.channelAction("team-join", "", "", JSON.stringify({ groupId: team.group_id }))
    }
    function joinByCode(code) {
        codeBusy = true
        backend.channelAction("team-join-code", "", "", JSON.stringify({ code: code }))
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.op === "teams-suggested") { page.suggestedLoaded = true; page.suggested = r.ok ? r.data || [] : [] }
            else if (r.op === "teams-find" && r.ok && r.data.q === search.text.trim()) { page.searching = false; page.searched = r.data.q; page.results = r.data.teams || [] }
            else if (r.op === "teams-find" && !r.ok) page.searching = false
            else if (r.op === "team-join") {
                const all = page.suggested.concat(page.results)
                const g = r.ok ? r.data.groupId : Object.keys(page.joinState).find(k => page.joinState[k] === "Joining")
                const t = all.find(x => x.group_id === g)
                const s = Object.assign({}, page.joinState)
                s[g] = !r.ok ? "NotJoined" : t && t.private ? "Pending" : "Joined"
                page.joinState = s
                if (r.ok && t && !t.private) page.joined(g, "")
            } else if (r.op === "team-join-code") {
                page.codeBusy = false
                if (r.ok) { codeField.text = ""; if (!(r.data && r.data.isTeamOwnerApprovalRequired)) page.joined(r.data && r.data.siteInfo ? r.data.siteInfo.groupId || "" : "", r.data ? r.data.skypeThreadId || "" : "") }
                else codeError.open()
            }
        }
    }

    // ---- Left pane ----
    Rectangle {
        id: left
        width: 380; height: parent.height
        color: theme.pane
        Rectangle {
            x: 11; y: 12; width: 32; height: 31.3; radius: 4
            color: backHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "chevron-left-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: page.back() }
            Accessible.role: Accessible.Button; Accessible.name: "Back"
        }
        Text { x: 43; y: 14.8; text: "Join a team"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text; Accessible.role: Accessible.Heading; Accessible.name: text }
        Rectangle {
            x: 328; y: 12; width: 32; height: 31.3; radius: 4
            color: newHover.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "add-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: newHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: page.createTeam() }
            ToolTip.visible: newHover.hovered; ToolTip.delay: 600; ToolTip.text: "Create a new team"
            Accessible.role: Accessible.Button; Accessible.name: "Create a new team"
        }
        Rectangle {
            x: 4; y: 59.3; width: 368; height: 32; radius: 4
            color: search.activeFocus ? theme.surface : theme.pick("#F5F5F5", "#333333")
            Rectangle { visible: !search.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
            TextInput {
                id: search
                x: 12; width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                selectByMouse: true
                onAccepted: page.runSearch()
                Text { visible: !search.text; text: "Type to search"; font: search.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText; Accessible.name: "Type to search"
            }
            FluentIcon {
                x: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
                name: search.text ? "dismiss-20" : "search-20"; size: 20; color: theme.textStrong
                TapHandler { enabled: !!search.text; onTapped: { search.text = ""; page.view = "suggested"; page.searched = "" } }
            }
            Rectangle { visible: search.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand }
        }
        Column {
            x: 4; y: 99.3; spacing: 0
            Repeater {
                model: (page.searched || page.searching ? [["results", "Search results"]] : []).concat([["suggested", "Teams for you"]])
                Rectangle {
                    id: nav
                    required property var modelData
                    readonly property bool sel: page.view === modelData[0]
                    width: 368; height: 32; radius: 4
                    color: sel ? theme.surface : navHover.hovered ? theme.rowHover : "transparent"
                    Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData[1]; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.view = nav.modelData[0] }
                    Accessible.role: Accessible.ListItem; Accessible.name: nav.modelData[1]; Accessible.selected: sel
                }
            }
        }
    }

    component PrimaryButton: Rectangle {
        id: pb
        property string text
        property string icon: ""
        signal clicked()
        height: 31.3; radius: 4
        color: !enabled ? theme.bgDisabled : pbHover.hovered ? theme.brandHover : theme.brandFill
        border.color: enabled ? "transparent" : theme.divider; border.width: 0.67
        Row {
            anchors.centerIn: parent; spacing: 6
            FluentIcon { visible: pb.icon !== ""; anchors.verticalCenter: parent.verticalCenter; name: pb.icon; size: 20; color: pb.enabled ? theme.textOnBrand : theme.disabled }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: pb.enabled ? theme.textOnBrand : theme.disabled }
        }
        HoverHandler { id: pbHover; enabled: pb.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: pb.enabled; onTapped: pb.clicked() }
        Accessible.role: Accessible.Button; Accessible.name: text
    }
    component GalleryCard: Rectangle {
        width: 238; height: 268; radius: 4
        color: theme.surface
        border.color: theme.stroke; border.width: 0.67
    }
    // Join a team with a code.
    component CodeCard: GalleryCard {
        Image { x: 87; y: 24.7; width: 64; height: 64; source: "../assets/illustrations/join-code.svg"; sourceSize: Qt.size(128, 128) }
        Text { width: parent.width; y: 120.7; horizontalAlignment: Text.AlignHCenter; text: "Join a team with a code"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.Bold; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.text }
        Rectangle {
            x: 25; y: 144.7; width: 188; height: 32; radius: 4
            color: theme.surface
            border.color: theme.stroke; border.width: 0.67
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: codeField.activeFocus ? 2 : 0.67; color: codeField.activeFocus ? theme.brand : theme.textSecondary }
            TextInput {
                id: codeField
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                selectByMouse: true
                onAccepted: if (text.trim()) page.joinByCode(text.trim())
                Text { visible: !codeField.text; text: "Enter join code."; font: codeField.font; color: theme.textSecondary }
                Accessible.role: Accessible.EditableText; Accessible.name: "Enter join code."
            }
        }
        PrimaryButton { x: 11.7; y: 216; width: 214.7; text: "Add team"; enabled: codeField.text.trim().length > 0 && !page.codeBusy; onClicked: page.joinByCode(codeField.text.trim()) }
    }
    component CreateCard: GalleryCard {
        Image { x: 87; y: 24.7; width: 64; height: 64; source: "../assets/illustrations/join-create.svg"; sourceSize: Qt.size(128, 128) }
        Row {
            x: 61; y: 140.7; spacing: 10
            Repeater {
                model: 3
                Rectangle { width: 32; height: 32; radius: 16; color: theme.pick("#E6E6E6", "#3D3D3D"); FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: theme.textSecondary } }
            }
        }
        PrimaryButton { x: 11.7; y: 216; width: 214.7; text: "Create a new team"; onClicked: page.createTeam() }
    }
    component TeamCard: GalleryCard {
        id: tc
        property var team: ({})
        readonly property string state: page.joinState[team.group_id] || team.status || "NotJoined"
        HoverHandler { id: tcHover }
        Avatar {
            x: 87; y: 24.7; size: 64; square: true; squareRadius: 4
            name: tc.team.name || ""
            initialsText: (tc.team.name || "").split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: tc.team.group_id ? "team:" + tc.team.group_id : ""
        }
        Text { x: 11; width: parent.width - 22; y: 100.7; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: tc.team.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; color: theme.text }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 124.7; spacing: 4
            FluentIcon { visible: !!tc.team.private; anchors.verticalCenter: parent.verticalCenter; name: "lock-closed-20"; size: 16; color: theme.text }
            Text { text: tc.team.private ? "Private" : "Public"; font.family: theme.font; font.pixelSize: 12; color: theme.text }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 148.7; spacing: 4
            Repeater {
                model: (tc.team.people || []).slice(0, 5)
                Avatar { required property var modelData; size: 24; name: modelData.name || modelData.email || ""; photoId: modelData.id ? "8:orgid:" + modelData.id : "" }
            }
        }
        Text {
            visible: !tcHover.hovered || tc.state === "Joined" || tc.state === "Pending"
            x: 11; width: parent.width - 22; y: 184.7; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
            text: tc.state === "Pending" ? "Request sent" : tc.state === "Joined" ? "Joined team" : (tc.team.description || "")
            font.family: theme.font; font.pixelSize: tc.state === "Pending" || tc.state === "Joined" ? 14 : 12
            font.weight: tc.state === "Pending" || tc.state === "Joined" ? Font.DemiBold : Font.Normal
            color: theme.text
        }
        PrimaryButton {
            visible: tcHover.hovered && tc.state !== "Joined" && tc.state !== "Pending"
            x: 11.7; y: 216; width: 214.7
            text: tc.state === "Joining" ? "Joining..." : "Join team"
            enabled: tc.state !== "Joining"
            onClicked: page.join(tc.team)
        }
        Accessible.role: Accessible.Grouping
        Accessible.name: (team.name || "") + ", " + (team.private ? "Private" : "Public")
    }

    // ---- Right side ----
    Flickable {
        id: right
        x: left.width; width: parent.width - x; height: parent.height
        contentHeight: Math.max(height, grid.y + grid.height + 40)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property var cards: page.view === "results" ? page.results : page.suggested
        readonly property bool empty: page.view === "results" ? (!page.searching && page.results.length === 0) : (page.suggestedLoaded && page.suggested.length === 0)
        // Teams for you, none.
        Column {
            visible: page.view === "suggested" && right.empty
            y: 40; width: parent.width
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "You don't have any teams discoverable"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Try searching, join with a code, or create one."; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                Text { text: "Not sure why you should create a team?"; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    text: " Watch this"; font.family: theme.font; font.pixelSize: 14; font.underline: true; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.brandForeground1
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://aka.ms/microsoftteams") }
                    Accessible.role: Accessible.Link; Accessible.name: "Watch this"
                }
            }
        }
        // Search results, none.
        Column {
            visible: page.view === "results" && right.empty
            y: 104; width: parent.width; spacing: 0
            Image { anchors.horizontalCenter: parent.horizontalCenter; width: 186; height: 186; source: "../assets/illustrations/no-matches.svg"; sourceSize: Qt.size(372, 372) }
            Item { width: 1; height: 69 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "We didn't find any matches"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 25.7; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 27 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "This could be a good time to create a new team."; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
            Item { width: 1; height: 30 }
            PrimaryButton { anchors.horizontalCenter: parent.horizontalCenter; width: 169; text: "Create a new team"; icon: "people-team-add-20"; onClicked: page.createTeam() }
            Item { width: 1; height: 16 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                Text { text: "Not sure why you should create a team?"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                Text {
                    text: " Watch this"; font.family: theme.font; font.pixelSize: 14; font.underline: true; color: theme.brandForeground1
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally("https://aka.ms/microsoftteams") }
                    Accessible.role: Accessible.Link; Accessible.name: "Watch this"
                }
            }
        }
        Flow {
            id: grid
            visible: !(page.view === "results" && right.empty)
            readonly property int perRow: Math.max(1, Math.floor((right.width + 16) / 254))
            readonly property int count: page.view === "suggested" && right.empty ? 2 : right.cards.length + (page.view === "suggested" ? 1 : 0)
            readonly property int cols: Math.min(perRow, Math.max(1, count))
            x: (right.width - (cols * 238 + (cols - 1) * 16)) / 2
            y: page.view === "suggested" && right.empty ? 151.4 : 40
            width: cols * 238 + (cols - 1) * 16
            spacing: 16
            CodeCard { visible: page.view === "suggested" }
            CreateCard { visible: page.view === "suggested" && right.empty }
            Repeater {
                model: right.cards
                TeamCard { required property var modelData; team: modelData }
            }
        }
    }

    // Teams' "unable to join" dialog: its line and OK.
    Popup {
        id: codeError
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; width: 400; padding: 24
        height: errText.height + 48 + 31.3 + 20
        closePolicy: Popup.CloseOnEscape
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        Text {
            id: errText
            width: parent.width; wrapMode: Text.Wrap
            text: "Couldn't join this team with that code. Double-check the code or try another one."
            font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
            color: theme.text
        }
        PrimaryButton { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 96; text: "OK"; onClicked: codeError.close() }
    }

    // Test hooks.
    function searchForTest(q) { search.text = q; page.runSearch() }
}
