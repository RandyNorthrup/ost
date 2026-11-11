import QtQuick
import QtQuick.Controls.Basic

// Help (F1, and the Help app): Teams' Help (measured on winpc 2026-11-10:
// the Help app header and help.svc.cloud.microsoft's home) with OST's own
// articles (docs/help, compiled in) in Microsoft's place
// (docs/spec/feedback-and-help.md §4).
// - The header (61): the Help app's 32 px icon at 20, "Help" (18/700) at
//   72, More Help actions (···, 32 x 31.3, 39 from the right): Reload app,
//   About, Share app.
// - The page column: 727 wide, centred (91.5 in at 946). Back (34) and
//   Home (42) then Search help (660 x 40, radius 6, 16 px) at the top.
// - Home: "Help for OST" (22/700); three cards (a 229 x 145 picture, the
//   title 18/700, a 14 px brand link), 249 apart; "Browse all help"
//   (18/700) and Teams' nine categories in a 3 x 3 grid (a 64 px icon at
//   20, the name 14/600 brand 82.6 under it, the description 14 under
//   that, 189 wide; rows 204 apart); "Featured topics" (six links, 14/600
//   brand, with their descriptions, 3 x 2); then Licence | Privacy (12).
// - A category lists its articles; an article shows its text with "Was
//   this information helpful? Yes / No" (to the feedback forms) and "Edit
//   on GitHub"; Search help lists the matching articles.
Rectangle {
    id: root
    color: theme.surface
    /// Pages: {page: "home"} | {page: "category", id} | {page: "article",
    /// id} | {page: "search", q}.
    property var current: ({ page: "home" })
    property var history: []
    property var library: []
    function load() { try { library = JSON.parse(backend.helpLibrary()) } catch (e) { library = [] } }
    Component.onCompleted: load()
    function go(p) { history = history.concat([current]); current = p; scroller.contentY = 0 }
    function back() { if (!history.length) return; current = history[history.length - 1]; history = history.slice(0, -1); scroller.contentY = 0 }
    function home() { if (current.page !== "home") go({ page: "home" }) }
    function category(id) { return library.find(c => c.id === id) || null }
    function article(id) { for (const c of library) { const a = (c.articles || []).find(a => a.id === id); if (a) return a } return null }
    readonly property var featured: library.reduce((all, c) => all.concat((c.articles || []).filter(a => a.featured)), [])
    function openArticle(id) { go({ page: "article", id: id }) }
    function search(q) { q = q.trim(); if (q) go({ page: "search", q: q }) }
    readonly property var results: current.page === "search" ? (() => { try { return JSON.parse(backend.helpSearch(current.q)) } catch (e) { return [] } })() : []
    readonly property string repoUrl: backend.feedbackLink("repo")
    // The three cards on Help's home (Teams' "Change your background",
    // "Grow your network", "Set up Teams on mobile"), with OST's own.
    readonly property var heroes: [
        { title: "Find anything in a chat", link: "Learn how", image: "hero-find.png", article: "chat/find-in-a-chat" },
        { title: "Tell us what you think", link: "Send feedback", image: "hero-feedback.png", article: "troubleshoot/report-a-problem" },
        { title: "Find your way around OST", link: "Get started", image: "hero-tour.png", article: "get-started/find-your-way-around" }
    ]
    readonly property var categoryIcons: ({ "get-started": "rocket-20", chat: "chat-20", meetings: "video-20", "teams-and-channels": "people-team-20",
                                            "notifications-and-settings": "alert-20", "calls-and-devices": "call-20", files: "document-20",
                                            "apps-and-services": "apps-20", troubleshoot: "wrench-20" })

    // The header.
    Item {
        id: header
        width: parent.width; height: 61
        Rectangle {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 6
            color: "#33344A"
            FluentIcon { anchors.centerIn: parent; name: "question-circle-20"; size: 20; color: "#FFFFFF" }
        }
        Text {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            text: "Help"
            font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text
            Accessible.role: Accessible.Heading
        }
        Rectangle {
            id: moreHelp
            x: parent.width - 39; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 31.3; radius: 4
            color: mhh.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: helpMenu.opened ? theme.brand : theme.textStrong }
            HoverHandler { id: mhh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: helpMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "More Help actions"
            MenuPopup {
                id: helpMenu
                x: parent.width - width; y: parent.height + 4
                items: [{ label: "Reload app", icon: "arrow-clockwise-20" }, { separator: true },
                        { label: "About", icon: "info-20" }, { label: "Share app", icon: "share-20" }]
                onPicked: i => {
                    close()
                    if (i === 0) { root.load(); root.history = []; root.current = { page: "home" } }
                    else if (i === 2) about.open()
                    else if (i === 3) { backend.copyText(root.repoUrl + "/blob/main/SUPPORT.md") }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
    }

    // The page.
    Flickable {
        id: scroller
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: page.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: page
            x: Math.max(16, (scroller.width - 763) / 2); width: Math.min(727, scroller.width - 32)
            // Back, Home and Search help.
            Item {
                width: parent.width; height: 74
                component NavButton: Rectangle {
                    id: nb
                    property string icon
                    property string label
                    property bool usable: true
                    signal clicked()
                    radius: 4
                    color: nbh.hovered && usable ? theme.hover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: nb.icon; size: 20; color: nb.usable ? theme.brand : theme.pick("#BDBDBD", "#5C5C5C") }
                    HoverHandler { id: nbh; cursorShape: nb.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: nb.usable; onTapped: nb.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: nb.label
                }
                NavButton { x: 5.5; y: 20; width: 34; height: 34; icon: "chevron-left-20"; label: "Previous page"; usable: root.history.length > 0; onClicked: root.back() }
                NavButton { x: 39.5; y: 16; width: 42; height: 42; icon: "home-20-filled"; label: "Home"; onClicked: root.home() }
                Rectangle {
                    x: 81.5; y: 17; width: Math.min(660, parent.width - 81.5); height: 40; radius: 6
                    color: theme.surface
                    border.color: theme.stroke; border.width: q.activeFocus ? 0 : 0.67
                    Rectangle { anchors.bottom: parent.bottom; x: 2; width: parent.width - 4; height: 2; radius: 1; color: theme.brand; visible: q.activeFocus }
                    TextInput {
                        id: q
                        x: 16; width: parent.width - 16 - 48; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 16; color: theme.text
                        clip: true
                        Keys.onReturnPressed: root.search(text)
                        Keys.onEnterPressed: root.search(text)
                        Text { visible: !q.text; text: "Search help"; font: q.font; color: theme.textSecondary }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Search help"
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 38.7; radius: 4
                        color: sbh.hovered ? theme.hover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "search-20"; size: 24; color: theme.brand }
                        HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.search(q.text) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Search"
                    }
                }
            }

            // Home.
            Column {
                visible: root.current.page === "home"
                width: parent.width
                Item { width: 1; height: 21 }
                Text { text: "Help for OST"; font.family: theme.font; font.pixelSize: 22; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading }
                Item { width: 1; height: 50 }
                Row {
                    spacing: 20
                    Repeater {
                        model: root.heroes
                        Column {
                            required property var modelData
                            width: 229
                            Image {
                                width: 229; height: 145.3
                                source: "../assets/help/" + parent.modelData.image
                                fillMode: Image.PreserveAspectCrop; smooth: true
                                TapHandler { onTapped: root.openArticle(parent.parent.modelData.article) }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            Item { width: 1; height: 36 }
                            Text { width: 229; wrapMode: Text.Wrap; text: parent.modelData.title; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; lineHeight: 24; lineHeightMode: Text.FixedHeight; color: theme.text }
                            Item { width: 1; height: 12.6 }
                            Text {
                                text: parent.modelData.link; font.family: theme.font; font.pixelSize: 14; color: theme.brandLink
                                font.underline: lh.hovered
                                HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.openArticle(parent.parent.modelData.article) }
                                Accessible.role: Accessible.Link
                                Accessible.name: parent.modelData.link + ": " + parent.modelData.title
                            }
                        }
                    }
                }
                Item { width: 1; height: 50 }
                Text { text: "Browse all help"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading }
                Item { width: 1; height: 28 }
                Grid {
                    columns: 3; columnSpacing: 20; rowSpacing: 0
                    Repeater {
                        model: root.library
                        Item {
                            required property var modelData
                            width: 229; height: 204
                            Rectangle {
                                x: 20; width: 64; height: 64; radius: 32
                                color: theme.brandTint
                                FluentIcon { anchors.centerIn: parent; name: root.categoryIcons[parent.parent.modelData.id] || "question-circle-20"; size: 32; color: theme.brand }
                            }
                            Text {
                                x: 20; y: 82.6
                                text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandLink
                                font.underline: ch.hovered
                                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.go({ page: "category", id: parent.parent.modelData.id }) }
                                Accessible.role: Accessible.Link
                                Accessible.name: parent.modelData.title
                            }
                            Text { x: 20; y: 116; width: 189; wrapMode: Text.Wrap; text: parent.modelData.description; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        }
                    }
                }
                Item { width: 1; height: 22 }
                Text { text: "Featured topics"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text; Accessible.role: Accessible.Heading }
                Item { width: 1; height: 28.6 }
                Grid {
                    columns: 3; columnSpacing: 20; rowSpacing: 18
                    Repeater {
                        model: root.featured.slice(0, 6)
                        Column {
                            required property var modelData
                            width: 229; spacing: 4
                            Text {
                                width: 229; wrapMode: Text.Wrap
                                text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandLink
                                font.underline: fh.hovered
                                HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.openArticle(parent.parent.modelData.id) }
                                Accessible.role: Accessible.Link
                                Accessible.name: parent.modelData.title
                            }
                            Text { width: 229; wrapMode: Text.Wrap; text: parent.modelData.description; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                        }
                    }
                }
                Item { width: 1; height: 40 }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.StyledText
                    text: "<a href=\"licence\">Licence</a> &nbsp;|&nbsp; <a href=\"privacy\">Privacy</a>"
                    linkColor: theme.brandLink
                    font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                    onLinkActivated: l => Qt.openUrlExternally(l === "privacy" ? backend.feedbackLink("privacy") : root.repoUrl + "/blob/main/LICENSE")
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }

            // A list of articles (a category, or search results).
            Column {
                visible: root.current.page === "category" || root.current.page === "search"
                width: parent.width
                readonly property var cat: root.current.page === "category" ? root.category(root.current.id) : null
                readonly property var items: cat ? cat.articles : root.results
                Item { width: 1; height: 21 }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: parent.cat ? parent.cat.title : "Results for “" + (root.current.q || "") + "”"
                    font.family: theme.font; font.pixelSize: 22; font.weight: Font.Bold; color: theme.text
                    Accessible.role: Accessible.Heading
                }
                Item { width: 1; height: 8 }
                Text {
                    visible: !!parent.cat || parent.items.length === 0
                    width: parent.width; wrapMode: Text.Wrap
                    text: parent.cat ? parent.cat.description : "We couldn't find any help for “" + (root.current.q || "") + "”. Try other words, or browse all help."
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                }
                Item { width: 1; height: 28 }
                Repeater {
                    model: parent.items
                    Column {
                        required property var modelData
                        width: parent.width; spacing: 4; bottomPadding: 22
                        Text {
                            text: parent.modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.brandLink
                            font.underline: ah.hovered
                            HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.openArticle(parent.parent.modelData.id) }
                            Accessible.role: Accessible.Link
                            Accessible.name: parent.modelData.title
                        }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: parent.modelData.description; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                }
            }

            // An article.
            Column {
                visible: root.current.page === "article"
                width: parent.width
                readonly property var art: root.current.page === "article" ? root.article(root.current.id) : null
                readonly property var cat: art ? root.category(art.category) : null
                Item { width: 1; height: 21 }
                Text {
                    textFormat: Text.StyledText
                    text: "<a href=\"home\">Help</a> &nbsp;›&nbsp; <a href=\"cat\">" + (parent.cat ? parent.cat.title : "") + "</a>"
                    linkColor: theme.brandLink
                    font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    onLinkActivated: l => l === "home" ? root.home() : root.go({ page: "category", id: parent.cat.id })
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Item { width: 1; height: 16 }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.MarkdownText
                    text: parent.art ? parent.art.body : ""
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    linkColor: theme.brandLink
                    lineHeight: 1.2
                    onLinkActivated: l => Qt.openUrlExternally(l)
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Item { width: 1; height: 32 }
                Rectangle { width: parent.width; height: 0.67; color: theme.pick("#E0E0E0", "#3D3D3D") }
                Item { width: 1; height: 20 }
                Row {
                    spacing: 12
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Was this information helpful?"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                    Repeater {
                        model: [{ label: "Yes", kind: "compliment" }, { label: "No", kind: "problem" }]
                        Rectangle {
                            required property var modelData
                            width: 64; height: 32; radius: 4
                            color: yh.hovered ? theme.pick("#F5F5F5", "#3D3D3D") : theme.surface
                            border.color: theme.stroke; border.width: 0.67
                            Text { anchors.centerIn: parent; text: parent.modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            HoverHandler { id: yh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { const a = root.article(root.current.id); backend.requestFeedback(parent.modelData.kind, "Help", a ? "Help article: " + a.title + " (docs/help/" + a.id + ".md)" : "Help") } }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label
                        }
                    }
                }
                Item { width: 1; height: 16 }
                Text {
                    textFormat: Text.StyledText
                    text: "<a href=\"edit\">Edit on GitHub</a>"
                    linkColor: theme.brandLink
                    font.family: theme.font; font.pixelSize: 14
                    onLinkActivated: Qt.openUrlExternally(backend.feedbackLink("docs") + "/" + root.current.id + ".md")
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }

    // About (More Help actions ▸ About).
    Popup {
        id: about
        anchors.centerIn: parent
        width: 420; padding: 24
        modal: true
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Column {
            spacing: 12
            Text { text: "Help for OST"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text {
                width: 372; wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: theme.brandLink
                text: "Help articles for OST, built into the app so they work offline. They're written by the OST project; "
                      + "you can read and improve them on <a href=\"docs\">GitHub</a>."
                font.family: theme.font; font.pixelSize: 14; color: theme.text
                onLinkActivated: Qt.openUrlExternally(backend.feedbackLink("docs"))
            }
            Rectangle {
                anchors.right: parent.right
                width: 96; height: 32; radius: 4
                color: abh.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Close"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#FFFFFF" }
                HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: about.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Close"
            }
        }
    }

    // Test hooks.
    function openForTest(p) { go(p) }
}
