import QtQuick
import QtQuick.Controls.Basic

// Teams' app details dialog (app-details-northstar-dialog), measured on
// winpc 2026-11-09 for Help (scratchpad ab/*-dump.txt; spec
// docs/spec/app-details.md):
// - 899 x 564, radius 8. A 60 px footer ("By using {app}, you agree to the
//   privacy policy, terms of use, and permissions.") is fixed under the
//   scrolling page.
// - The page: the app's tile (64), name (20/28.57 semibold) and developer;
//   "Add" and share for an app you haven't added; a stats row (rating,
//   installs in the last month, Works in, pricing); the short and long
//   descriptions; "Capabilities in Teams"; Reviews (AppSource rating,
//   histogram, the two best reviews); Permissions overview; Details;
//   More like this.
// - Scrolled past the hero, a sticky 80 px header shows the tile (40),
//   name and close, with a brand scroll-progress line under it.
// - Views: All reviews (sort, report), Permissions, and Write a review.
//   Each has a Back button and the app's name over the view's title.
//   Opening an app from More like this adds Back to the main view.
Popup {
    id: root
    /// Teams' Share form for this app (the share button).
    signal shareApp(string appId)
    /// Open the app (offered for apps you have, where the dialog was opened
    /// from the Store or a chat).
    signal openApp(string appId, string name)
    property bool offerOpen: false
    /// Opened from "Add agent" for a conversation ({id, channel}): Add puts
    /// the app there, and Back returns to that Store.
    property var addTo: null
    signal backToStore()
    /// The app was added to `addTo` (the Add's result).
    signal addedTo(var result)
    readonly property var adding: { const a = backend.appAddedJson ? JSON.parse(backend.appAddedJson) : null; return a && a.app === appId ? a : null }
    modal: true; focus: true
    width: Math.min(899, (parent ? parent.width : 899) - 32)
    height: Math.min(564, (parent ? parent.height : 564) - 32)
    anchors.centerIn: Overlay.overlay
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: "#66000000" }

    property string appId: ""
    /// Apps opened before this one from More like this.
    property var history: []
    /// "main", "reviews", "permissions", "write" or "report".
    property string view: "main"
    property bool languagesOpen: false
    property string sort: "recent"
    property int rating: 0

    readonly property var info: { const r = backend.appDetailsJson ? JSON.parse(backend.appDetailsJson) : null; return r && r.app === appId ? r : null }
    readonly property var d: info && info.details ? info.details : null
    readonly property var revs: { const r = backend.appReviewsJson ? JSON.parse(backend.appReviewsJson) : null; return r && r.app === appId ? r : null }
    readonly property var similar: { const r = backend.appSimilarJson ? JSON.parse(backend.appSimilarJson) : null; return r && r.app === appId ? (r.apps || []) : [] }
    readonly property string name: d ? d.name : ""

    function show(id, target) { history = []; addTo = target || null; load(id); open() }
    function load(id) {
        appId = id; view = "main"; languagesOpen = false; rating = 0
        backend.appDetailsLoad(id)
        backend.appReviewsLoad(id, "highest", 2, false)
        backend.appSimilarLoad(id)
        mainFlick.contentY = 0
    }
    function addOrOpen() {
        if (root.adding && root.adding.busy) return
        // Teams' Add: for you, and into the conversation it was opened for.
        if (root.addTo) backend.addApp(root.appId, root.addTo.id, root.addTo.channel)
        else if (root.d && root.d.installed) { root.openApp(root.appId, root.name); root.close() }
        else backend.addApp(root.appId, "", false)
    }
    Connections {
        target: backend
        function onAppAddedJsonChanged() {
            const a = root.adding
            if (!a || !a.ok) return
            if (root.addTo && a.conversation === root.addTo.id) { root.close(); root.addedTo(a) }
            else if (!root.addTo) backend.appDetailsLoad(root.appId)
        }
    }
    function leaveToStore() { root.close(); root.backToStore() }
    function openSimilar(id) { history = history.concat([appId]); load(id) }
    function back() {
        if (view === "report") { view = "reviews"; return }
        if (view !== "main") {
            const from = view
            view = "main"
            if (from === "reviews") backend.appReviewsLoad(appId, "highest", 2, false)
            return
        }
        if (history.length > 0) { const h = history.slice(); const id = h.pop(); history = h; load(id) }
    }
    function showReviews() { view = "reviews"; sort = "recent"; backend.appReviewsLoad(appId, sort, 10, false); reviewsFlick.contentY = 0 }
    function sortReviews(s) { sort = s; backend.appReviewsLoad(appId, s, 10, false); reviewsFlick.contentY = 0 }
    function showWrite() { view = "write"; rating = 0; reviewTitle.text = ""; reviewBody.text = ""; publicBox.checked = false }
    property var reportReview: null
    property string reportReason: "OffensiveContent"
    function showReport(r) { reportReview = r; reportReason = "OffensiveContent"; reportComment.text = ""; view = "report" }
    function stars(n) { return n === 1 ? "1 star" : n + " stars" }
    // Test hooks.
    function viewForTest(v) { if (v === "reviews") showReviews(); else if (v === "write") showWrite(); else view = v }
    function scrollForTest(y) { mainFlick.contentY = Math.min(y, Math.max(0, mainFlick.contentHeight - mainFlick.height)) }
    function languagesForTest() { languagesOpen = !languagesOpen }
    function sortMenuForTest() { sortMenu.open() }
    property alias sortMenuForTest_: sortMenu

    onClosed: { view = "main"; history = [] }

    // A text link in the brand link colour.
    component LinkText: Text {
        id: lt
        property string url
        signal activated()
        font.family: theme.font; font.pixelSize: 14
        color: theme.brandLink
        font.underline: ltHover.hovered
        HoverHandler { id: ltHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (lt.url) Qt.openUrlExternally(lt.url); lt.activated() } }
        Accessible.role: Accessible.Link
        Accessible.name: text
    }
    // Teams' secondary (outline) button: 31 tall, radius 4, 14/20 semibold.
    component OutlineButton: Rectangle {
        id: ob
        property string label
        signal clicked()
        width: obText.implicitWidth + 32; height: 31.33; radius: 4
        color: obHover.hovered ? theme.menuHover : theme.surface
        border.width: 0.67; border.color: obHover.hovered ? theme.strokeHover : theme.stroke
        Text { id: obText; anchors.centerIn: parent; text: ob.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
        HoverHandler { id: obHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ob.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: ob.label
    }
    component IconButton: Rectangle {
        id: ib
        property string icon
        property string tip
        property int glyph: 20
        signal clicked()
        width: 32; height: 31.33; radius: 4
        color: ibHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: ib.icon; size: ib.glyph; color: theme.textStrong }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        ToolTip.visible: ibHover.hovered && ib.tip.length > 0
        ToolTip.delay: 500
        ToolTip.text: ib.tip
        Accessible.role: Accessible.Button
        Accessible.name: ib.tip
    }
    // An app tile as Teams draws it: a squircle (corner-shape
    // superellipse(2), radius 50%) on #FAFAFA.
    component AppTile: Item {
        id: at
        property string src
        property color background: theme.surface
        Rectangle { anchors.fill: parent; color: theme.quoteFill }
        Image {
            anchors.fill: parent
            source: at.src
            sourceSize: Qt.size(at.width * 2, at.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }
        RoundedCorners { anchors.fill: parent; squircle: true; background: at.background }
    }
    // Five stars, filled up to `value`.
    component StarRow: Row {
        id: sr
        property int value
        property int size: 16
        spacing: 1
        Repeater {
            model: 5
            FluentIcon { required property int index; size: sr.size; name: index < sr.value ? "star-16-filled" : "star-16"; color: theme.brand }
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: "Rating " + sr.value + " out of 5"
    }
    // The rating summary: big average, counts and the 5..1 histogram.
    component RatingSummary: Item {
        id: rs
        property real barWidth: 157
        width: 30 + barWidth + 2; height: 200
        readonly property var r: root.d ? root.d.rating : null
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "star-20-filled"; size: 20; color: theme.brand }
            Text { text: rs.r ? rs.r.average : ""; font.family: theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; color: theme.textStrong; height: 36; verticalAlignment: Text.AlignVCenter }
        }
        Text { y: 40; anchors.horizontalCenter: parent.horizontalCenter; text: rs.r ? rs.r.count_text + " ratings" : ""; font.family: theme.font; font.pixelSize: 10; color: theme.textStrong }
        Text { y: 56; anchors.horizontalCenter: parent.horizontalCenter; text: (root.d ? root.d.installs_text : "0") + " installs in the last month"; font.family: theme.font; font.pixelSize: 10; color: theme.textStrong }
        Repeater {
            model: 5
            Item {
                required property int index
                y: 85 + index * 20; width: rs.width; height: 12
                readonly property int n: rs.r ? rs.r.stars[index] : 0
                Text { x: 0; text: 5 - parent.index; font.family: theme.font; font.pixelSize: 10; color: theme.textStrong; height: 12; verticalAlignment: Text.AlignVCenter }
                FluentIcon { x: 7; y: 1; size: 10; name: "star-12-filled"; color: theme.brand }
                Rectangle {
                    x: 28; y: 2; width: rs.barWidth; height: 8; radius: 4; color: theme.brandTint
                    Rectangle {
                        height: 8; radius: 4; color: theme.brand
                        width: rs.r && rs.r.count > 0 ? parent.width * Math.round(parent.parent.n * 100 / rs.r.count) / 100 : 0
                    }
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: root.stars(5 - index) + " " + (rs.r && rs.r.count > 0 ? Math.round(n * 100 / rs.r.count) : 0) + "%"
            }
        }
    }
    // A review as Teams lists it.
    component ReviewItem: Column {
        id: ri
        property var review
        property bool reportable: false
        spacing: 0
        Text {
            width: parent.width
            text: ri.review.title || (root.name + " review")
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
            lineHeight: 20; lineHeightMode: Text.FixedHeight
        }
        Item { width: 1; height: 10 }
        Row {
            height: 16; spacing: 8
            StarRow { value: ri.review.rating }
            Rectangle { width: 1; height: 12; y: 2; color: theme.stroke }
            Text { text: ri.review.author; height: 16; verticalAlignment: Text.AlignVCenter; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
            Rectangle { width: 1; height: 12; y: 2; color: theme.stroke }
            Text { text: ri.review.when; height: 16; verticalAlignment: Text.AlignVCenter; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
        }
        Item { width: 1; height: 10 }
        Text {
            width: parent.width
            visible: text.length > 0
            text: ri.review.content
            wrapMode: Text.Wrap
            font.family: theme.font; font.pixelSize: 14; color: theme.text
            lineHeight: 20; lineHeightMode: Text.FixedHeight
        }
        Column {
            visible: !!ri.review.developer_reply
            width: parent.width
            topPadding: 8
            Text { text: "Developer Response"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
            Text { width: parent.width; text: ri.review.developer_reply || ""; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: 14; color: theme.text }
        }
        Item { width: 1; height: ri.reportable ? 10 : 0 }
        Rectangle {
            visible: ri.reportable
            width: 103; height: 21; radius: 4
            color: rpHover.hovered ? theme.menuHover : "transparent"
            Row {
                x: 3; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                FluentIcon { name: "flag-16"; size: 16; color: theme.textStrong }
                Text { text: "Report review"; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textStrong }
            }
            HoverHandler { id: rpHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.showReport(ri.review) }
            Accessible.role: Accessible.Button
            Accessible.name: "Report review"
        }
    }
    // A sub-view's header: Back, the tile, the app's name and the view.
    component ViewHeader: Rectangle {
        id: vh
        property string subtitle
        width: parent.width; height: 80
        color: theme.surface
        IconButton { x: 14; y: 24; icon: "chevron-left-20"; tip: "Back"; onClicked: root.back() }
        AppTile { x: 56; y: 20; width: 40; height: 40; src: root.d ? root.d.icon : "" }
        Text { x: 106; y: 21; height: 22; verticalAlignment: Text.AlignVCenter; text: root.name; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
        Text { x: 106; y: 43; text: vh.subtitle; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong }
        IconButton { x: 811; y: 24; icon: "dismiss-20"; tip: "Close"; onClicked: root.close() }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
    }
    // "Powered by Microsoft AppSource | View Terms".
    component PoweredBy: Row {
        spacing: 0
        Text { text: "Powered by "; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
        LinkText { text: "Microsoft AppSource"; url: "https://appsource.microsoft.com/en-us/?exp=ubp8" }
        Text { text: " | "; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
        LinkText { text: "View Terms"; url: "https://learn.microsoft.com/en-us/legal/marketplace/marketplace-terms" }
    }

    contentItem: Item {
        clip: true

        // ---- The main view ----
        Item {
            id: mainView
            anchors.fill: parent
            visible: root.view === "main"

            Flickable {
                id: mainFlick
                width: parent.width; height: parent.height - 60
                contentWidth: width
                contentHeight: page.height + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Item {
                    id: page
                    width: 899
                    height: moreLike.y + moreLike.height
                    readonly property bool canAdd: !!root.d && (!root.d.installed || root.offerOpen || !!root.addTo)
                    readonly property real heroX: root.history.length > 0 || root.addTo ? 88 : 56

                    IconButton { visible: root.history.length > 0 || !!root.addTo; x: 56; y: 24; icon: "chevron-left-20"; tip: "Back"; onClicked: root.history.length > 0 ? root.back() : root.leaveToStore() }
                    AppTile { id: heroTile; x: page.heroX; y: root.history.length > 0 || root.addTo ? 24 : 29; width: 64; height: 64; src: root.d ? root.d.icon : "" }
                    Text {
                        x: page.heroX + 86; y: heroTile.y + 4; height: 29
                        text: root.name
                        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }
                    Text { x: page.heroX + 86; y: heroTile.y + 33; text: root.d ? root.d.developer : ""; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Row {
                        visible: page.canAdd
                        x: page.heroX + 86; y: heroTile.y + 74
                        spacing: 8
                        Rectangle {
                            width: 96; height: 32; radius: 4
                            color: addHover.hovered ? theme.brandHover : theme.brandFill
                            Text { anchors.centerIn: parent; text: root.d && root.d.installed && !root.addTo ? "Open" : "Add"; opacity: root.adding && root.adding.busy ? 0.6 : 1; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.addOrOpen() }
                            Accessible.role: Accessible.Button; Accessible.name: root.d && root.d.installed ? "Open" : "Add"
                        }
                        IconButton { width: 32; height: 32; icon: "share-20"; tip: "Share"; onClicked: root.shareApp(root.appId) }
                    }
                    IconButton { x: 811; y: 24; icon: "dismiss-20"; tip: "Close"; onClicked: root.close() }

                    Rectangle { id: heroRule; x: 56; y: page.canAdd ? 180 : 148; width: 771; height: 1; color: theme.quoteBorder }

                    // Stats: rating, installs, Works in, pricing.
                    Row {
                        id: stats
                        x: 40; y: heroRule.y + 13
                        readonly property var items: {
                            if (!root.d) return []
                            const out = []
                            if (root.d.rating.count > 0) out.push({ kind: "rating", value: root.d.rating.average, lines: [root.d.rating.count_text + " ratings"].concat(root.d.reviews_count > 1 ? [root.d.reviews_count_text + " reviews"] : []) })
                            out.push({ kind: "installs", value: root.d.installs_text, lines: ["Installs in the last month"] })
                            out.push({ kind: "works", value: "Works in", lines: [root.d.works_in] })
                            out.push({ kind: "pricing", value: root.d.pricing_label, lines: [root.d.pricing_sublabel] })
                            return out
                        }
                        visible: items.length >= 3
                        Repeater {
                            model: stats.items
                            Item {
                                required property var modelData
                                required property int index
                                width: 201; height: 63
                                Rectangle { visible: parent.index > 0; x: 0; y: 20; width: 1; height: 24; color: theme.quoteBorder }
                                Column {
                                    x: 50; width: 100; y: 6
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 4
                                        FluentIcon { visible: modelData.kind === "rating"; anchors.verticalCenter: parent.verticalCenter; name: "star-16"; size: 16; color: theme.textSecondary }
                                        Text { text: modelData.value; height: 20; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textSecondary }
                                    }
                                    Item { width: 1; height: 4 }
                                    Repeater {
                                        model: modelData.lines
                                        Text {
                                            required property string modelData
                                            width: 75; anchors.horizontalCenter: parent.horizontalCenter
                                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                            text: modelData; font.family: theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.textSecondary
                                            lineHeight: 14; lineHeightMode: Text.FixedHeight
                                        }
                                    }
                                }
                                HoverHandler { cursorShape: modelData.kind === "rating" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { enabled: modelData.kind === "rating"; onTapped: mainFlick.contentY = Math.min(reviewsHead.y - 24, mainFlick.contentHeight - mainFlick.height) }
                                Accessible.role: Accessible.StaticText
                                Accessible.name: modelData.value + " " + modelData.lines.join(" ")
                            }
                        }
                    }

                    Text {
                        id: shortDesc
                        x: 56; y: heroRule.y + 100; width: 771; height: 36
                        verticalAlignment: Text.AlignVCenter
                        text: root.d ? root.d.short_description : ""
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }
                    Text {
                        id: longDesc
                        x: 56; y: shortDesc.y + 44; width: 771
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        text: root.d ? root.d.description : ""
                        font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        linkColor: theme.brandLink
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }

                    // Capabilities in Teams.
                    Rectangle {
                        id: caps
                        visible: !!root.d && root.d.capabilities.length > 0
                        x: 56; y: longDesc.y + longDesc.height + 48; width: 771
                        height: visible ? 62 + 1 + capList.height + 16 : 0
                        radius: 12; color: theme.quoteFill
                        Text { x: 16; height: 62; verticalAlignment: Text.AlignVCenter; text: "Capabilities in Teams"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Rectangle { x: 16; y: 62; width: parent.width - 32; height: 1; color: theme.divider }
                        Column {
                            id: capList
                            x: 18; y: 79; width: parent.width - 36
                            spacing: 16
                            Repeater {
                                model: root.d ? root.d.capabilities : []
                                Item {
                                    required property var modelData
                                    width: capList.width; height: 44
                                    FluentIcon { y: 2; name: modelData.icon; size: 20; color: theme.textStrong }
                                    Text { x: 32; text: modelData.title; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text; height: 20 }
                                    Text { x: 32; y: 24; width: parent.width - 32; text: modelData.description; font.family: theme.font; font.pixelSize: 12; color: theme.textStrong; height: 20; elide: Text.ElideRight }
                                }
                            }
                        }
                    }

                    // Reviews (only for apps with ratings).
                    Item {
                        id: reviewsHead
                        readonly property bool shown: !!root.d && root.d.rating.count > 0
                        x: 56; y: caps.y + caps.height + 13; width: 771
                        height: shown ? Math.max(rightCol.y + rightCol.height, 302) : 0
                        visible: shown
                        Text { height: 22; text: "Reviews"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        PoweredBy { y: 42 }
                        RatingSummary { x: 32; y: 114 }
                        Column {
                            id: rightCol
                            x: 264; y: 82; width: 507
                            spacing: 20
                            readonly property var list: root.revs && root.revs.sort === "highest" ? (root.revs.reviews || []) : []
                            Repeater {
                                model: rightCol.list.slice(0, 2)
                                ReviewItem { required property var modelData; width: rightCol.width; review: modelData }
                            }
                            // Teams' empty state, until reviews come.
                            Column {
                                visible: rightCol.list.length === 0
                                width: rightCol.width
                                spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Be the first to write a review"; font.family: theme.font; font.pixelSize: 14; font.bold: true; color: theme.text }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Share your experience to help others learn about this app."; font.family: theme.font; font.pixelSize: 12; color: theme.text }
                                Item { width: 1; height: 8 }
                                OutlineButton { anchors.horizontalCenter: parent.horizontalCenter; label: "Write a review"; onClicked: root.showWrite() }
                            }
                            Row {
                                visible: rightCol.list.length > 0
                                spacing: 10
                                OutlineButton { label: "Write a review"; onClicked: root.showWrite() }
                                OutlineButton { label: "See all reviews"; onClicked: root.showReviews() }
                            }
                        }
                    }

                    // Permissions overview.
                    Item {
                        id: perms
                        x: 56; y: reviewsHead.y + reviewsHead.height + (reviewsHead.shown ? 49 : 13); width: 771
                        visible: !!root.d && root.d.permissions.length > 0
                        height: visible ? 46 + permCards.height : 0
                        Text { height: 26; verticalAlignment: Text.AlignVCenter; text: "Permissions overview"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        LinkText { anchors.right: parent.right; height: 20; y: 3; text: "View detailed permissions"; color: theme.brand; onActivated: root.view = "permissions" }
                        Row {
                            id: permCards
                            y: 46; spacing: 20
                            Repeater {
                                model: root.d ? root.d.permissions : []
                                Rectangle {
                                    required property var modelData
                                    width: 376; height: Math.max(120, 80 + modelData.groups.length * 28 + 12)
                                    radius: 12; color: theme.quoteFill
                                    Rectangle {
                                        x: 20; y: 20; width: 336; height: 27; radius: 4
                                        color: phHover.hovered ? theme.menuHover : "transparent"
                                        Text { x: 1; height: 24; verticalAlignment: Text.AlignVCenter; text: modelData.title; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                                        FluentIcon { x: 315; y: 6; name: "chevron-right-16"; size: 14; color: theme.textStrong }
                                        HoverHandler { id: phHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.view = "permissions" }
                                        Accessible.role: Accessible.Button; Accessible.name: modelData.title
                                    }
                                    Rectangle { x: 20; y: 59; width: 336; height: 1; color: theme.divider }
                                    Column {
                                        x: 20; y: 80; spacing: 8
                                        Repeater {
                                            model: modelData.groups
                                            Row {
                                                required property var modelData
                                                spacing: 4
                                                FluentIcon { name: modelData.icon === "ost" ? "" : modelData.icon + "-20"; visible: modelData.icon !== "ost"; size: 20; color: theme.text }
                                                Image { visible: modelData.icon === "ost"; source: "../assets/logo.png"; width: 20; height: 20; sourceSize: Qt.size(40, 40) }
                                                Text { text: modelData.title; height: 20; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Details.
                    Item {
                        id: detailsSec
                        x: 56; y: perms.y + perms.height + 60; width: 771
                        height: langCell.y + langCell.height
                        Text { height: 22; text: "Details"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Column {
                            y: 42; width: 244; spacing: 8
                            visible: !!root.d && !!root.d.developer && !!root.d.developer_url
                            Text { text: "Created by"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            LinkText { text: root.d ? root.d.developer : ""; url: root.d ? root.d.developer_url : "" }
                        }
                        Column {
                            x: 263; y: 42; width: 244; spacing: 8
                            Text { text: "Version"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { text: root.d ? root.d.version : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                        Column {
                            x: 527; y: 42; width: 244; spacing: 8
                            Text { text: "Pricing"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text { text: root.d ? root.d.pricing_details : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        }
                        Column {
                            id: langCell
                            y: 113; width: 244; spacing: 8
                            visible: !!root.d && root.d.languages.length > 0
                            readonly property var all: root.d ? root.d.languages : []
                            Text { text: "Languages"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                            Text {
                                width: 244; wrapMode: Text.Wrap
                                text: {
                                    const a = langCell.all
                                    if (a.length <= 1) return a[0] || ""
                                    if (root.languagesOpen) return a.length === 2 ? a[0] + " and " + a[1] : a.slice(0, -1).join(", ") + ", and " + a[a.length - 1]
                                    return root.d.language_first + " and"
                                }
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                                lineHeight: 20; lineHeightMode: Text.FixedHeight
                            }
                            Row {
                                visible: langCell.all.length > 1
                                spacing: 0
                                LinkText { text: root.languagesOpen ? "See less" : (langCell.all.length - 1) + " more"; onActivated: root.languagesOpen = !root.languagesOpen }
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: root.languagesOpen ? "chevron-up-16" : "chevron-down-16"; size: 14; color: theme.brandLink }
                            }
                        }
                    }

                    // More like this.
                    Item {
                        id: moreLike
                        x: 56; y: detailsSec.y + detailsSec.height + 52; width: 771
                        visible: root.similar.length > 0
                        height: visible ? 42 + Math.ceil(root.similar.length / 2) * 100 - 16 : 0
                        Text { height: 22; text: "More like this"; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                        Grid {
                            y: 42; columns: 2; columnSpacing: 16; rowSpacing: 16
                            Repeater {
                                model: root.similar
                                Rectangle {
                                    required property var modelData
                                    width: 378; height: 84; radius: 8
                                    color: mlHover.hovered ? theme.menuHover : theme.surface
                                    border.width: 0.67; border.color: theme.quoteBorder
                                    AppTile { x: 16; y: 16; width: 52; height: 52; src: modelData.icon; background: parent.color }
                                    Text { x: 80; y: 23; width: 282; text: modelData.name; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                                    Text { x: 80; y: 45; width: 282; text: modelData.short; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                                    HoverHandler { id: mlHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.openSimilar(modelData.id) }
                                    Accessible.role: Accessible.Button; Accessible.name: modelData.name + ", " + modelData.short
                                }
                            }
                        }
                    }
                }
            }

            // The sticky header, once the hero has scrolled away.
            Rectangle {
                width: parent.width; height: 80
                color: theme.surface
                visible: mainFlick.contentY > 100
                IconButton { visible: root.history.length > 0 || !!root.addTo; x: 56; y: 24; icon: "chevron-left-20"; tip: "Back"; onClicked: root.history.length > 0 ? root.back() : root.leaveToStore() }
                AppTile { x: root.history.length > 0 || root.addTo ? 98 : 56; y: 20; width: 40; height: 40; src: root.d ? root.d.icon : "" }
                Text { x: root.history.length > 0 || root.addTo ? 148 : 106; y: 29; height: 22; text: root.name; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                Rectangle {
                    visible: page.canAdd
                    x: 707; y: 24; width: 96; height: 32; radius: 4
                    color: addHover2.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: root.d && root.d.installed && !root.addTo ? "Open" : "Add"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                    HoverHandler { id: addHover2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.addOrOpen() }
                }
                IconButton { x: 811; y: 24; icon: "dismiss-20"; tip: "Close"; onClicked: root.close() }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: theme.divider }
                // Teams' scroll progress.
                Rectangle {
                    y: 77; height: 2; color: theme.brand
                    width: parent.width * Math.min(1, mainFlick.contentY / Math.max(1, mainFlick.contentHeight - mainFlick.height))
                }
            }

            // Footer: terms and privacy.
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 60
                color: theme.surface
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                Text {
                    x: 56; y: 20; width: parent.width - 112
                    textFormat: Text.StyledText
                    linkColor: theme.brandLink
                    text: "By using " + root.name + ", you agree to the "
                          + (root.d && root.d.privacy_url ? '<a href="' + root.d.privacy_url + '">privacy policy</a>' : "privacy policy") + ", "
                          + (root.d && root.d.terms_url ? '<a href="' + root.d.terms_url + '">terms of use</a>' : "terms of use")
                          + ', and <a href="#permissions">permissions</a>.'
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onLinkActivated: link => {
                        if (link === "#permissions") mainFlick.contentY = Math.min(perms.y - 24, mainFlick.contentHeight - mainFlick.height)
                        else Qt.openUrlExternally(link)
                    }
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }

            // Loading and failure.
            Text {
                anchors.centerIn: parent
                visible: !root.d
                text: root.info && root.info.error ? "You can't view this app right now." : ""
                font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
            }
            BusyIndicator { anchors.centerIn: parent; running: !root.d && !(root.info && root.info.error); visible: running }
        }

        // ---- All reviews ----
        Item {
            id: reviewsView
            anchors.fill: parent
            visible: root.view === "reviews"
            ViewHeader { subtitle: "Reviews" }
            RatingSummary { x: 56; y: 122; barWidth: 221 }
            OutlineButton { x: 122; y: 379; label: "Write a review"; onClicked: root.showWrite() }
            Text {
                x: 325; y: 102; height: 20
                text: root.revs && root.revs.count !== undefined ? (root.revs.count === 1 ? "1 review" : root.revs.count + " reviews") : ""
                font.family: theme.font; font.pixelSize: 14; font.bold: true; color: theme.text
            }
            Rectangle {
                id: sortButton
                x: 747; y: 96; width: 96; height: 31.33; radius: 4
                color: sbHover.hovered || sortMenu.opened ? theme.menuHover : "transparent"
                Row {
                    anchors.centerIn: parent; spacing: 6
                    FluentIcon { name: "arrow-sort-20"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Sort"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textStrong }
                }
                HoverHandler { id: sbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sortMenu.open() }
                Accessible.role: Accessible.Button; Accessible.name: "Sort"
                MenuPopup {
                    id: sortMenu
                    x: sortButton.width - implicitWidth; y: sortButton.height + 20
                    readonly property var keys: ["recent", "highest", "lowest"]
                    items: [
                        { label: "Most recent", icon: "calendar-ltr-20", endCheck: root.sort === "recent" },
                        { label: "Highest rating", icon: "star-20", endCheck: root.sort === "highest" },
                        { label: "Lowest rating", icon: "star-20", endCheck: root.sort === "lowest" }
                    ]
                    onPicked: i => root.sortReviews(keys[i])
                }
            }
            Rectangle { x: 325; y: 133; width: 504; height: 1; color: theme.divider }
            Flickable {
                id: reviewsFlick
                x: 325; y: 152; width: 520; height: parent.height - 152 - 61
                contentHeight: reviewList.height + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                // Teams loads the next page as you reach the end.
                onContentYChanged: if (root.revs && root.revs.more && contentY + height > contentHeight - 200 && !pageTimer.running) { pageTimer.start(); backend.appReviewsLoad(root.appId, root.sort, 10, true) }
                Timer { id: pageTimer; interval: 800 }
                Column {
                    id: reviewList
                    width: 504
                    spacing: 36
                    Repeater {
                        model: root.revs && root.revs.sort === root.sort ? (root.revs.reviews || []) : []
                        ReviewItem { required property var modelData; width: reviewList.width; review: modelData; reportable: modelData.author !== "You" }
                    }
                    Text {
                        visible: !!root.revs && root.revs.count === 0
                        text: "No results found"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 61
                color: theme.surface
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                PoweredBy { x: 32; y: 21 }
            }
        }

        // ---- Permissions ----
        Item {
            anchors.fill: parent
            visible: root.view === "permissions"
            ViewHeader { subtitle: "Permissions" }
            Flickable {
                y: 80; width: parent.width; height: parent.height - 80 - 60
                contentHeight: permL2.height + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: permL2
                    x: 56; y: 12; width: 771; spacing: 20
                    Repeater {
                        model: root.d ? root.d.permissions : []
                        Rectangle {
                            required property var modelData
                            width: 771; height: l2Groups.y + l2Groups.height + 36
                            radius: 12; color: theme.quoteFill
                            Text { x: 20; y: 20; height: 26; verticalAlignment: Text.AlignVCenter; text: modelData.title; font.family: theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; color: theme.text }
                            Rectangle { x: 20; y: 66; width: 731; height: 1; color: theme.divider }
                            Column {
                                id: l2Groups
                                x: 44; y: 95; width: 707; spacing: 20
                                Repeater {
                                    model: modelData.groups
                                    Column {
                                        required property var modelData
                                        width: 707; spacing: 4
                                        Item {
                                            width: 707; height: 24
                                            FluentIcon { visible: modelData.icon !== "ost"; y: 4; name: modelData.icon === "cursor-click" ? "cursor-click-20" : (modelData.icon === "ost" ? "" : modelData.icon + "-16"); size: 16; color: theme.textStrong }
                                            Image { visible: modelData.icon === "ost"; y: 4; source: "../assets/logo.png"; width: 16; height: 16; sourceSize: Qt.size(32, 32) }
                                            Text { x: 24; height: 24; verticalAlignment: Text.AlignVCenter; text: modelData.title; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.textStrong }
                                        }
                                        Repeater {
                                            model: modelData.items
                                            Text {
                                                required property string modelData
                                                x: 24; width: 683; wrapMode: Text.Wrap
                                                text: modelData; font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                                                lineHeight: 24; lineHeightMode: Text.FixedHeight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 60
                color: theme.surface
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                Text {
                    x: 56; y: 20
                    textFormat: Text.StyledText; linkColor: theme.brandLink
                    text: "By using " + root.name + ", you agree to the "
                          + (root.d && root.d.privacy_url ? '<a href="' + root.d.privacy_url + '">privacy policy</a>' : "privacy policy") + ", "
                          + (root.d && root.d.terms_url ? '<a href="' + root.d.terms_url + '">terms of use</a>' : "terms of use") + ", and permissions."
                    font.family: theme.font; font.pixelSize: 14; color: theme.text
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }

        // ---- Report review (Teams' reasons, sent to AppSource) ----
        Item {
            anchors.fill: parent
            visible: root.view === "report"
            ViewHeader { subtitle: "Report review" }
            Column {
                x: 56; y: 104; width: 787
                Text { height: 22; text: "Provide a reason for reporting this review"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                Item { width: 1; height: 18 }
                Repeater {
                    model: [["OffensiveContent", "Offensive content"], ["SpamAndAdvertising", "Spam or advertising"], ["InvalidReview", "Invalid review"], ["Other", "Other"]]
                    Column {
                        required property var modelData
                        readonly property bool on: root.reportReason === modelData[0]
                        width: 787
                        Item {
                            width: 787; height: 40
                            Rectangle {
                                x: 8; y: 12; width: 16; height: 16; radius: 8
                                color: "transparent"
                                border.width: 0.67; border.color: parent.parent.on ? theme.brand : theme.textSecondary
                                Rectangle { anchors.centerIn: parent; visible: parent.parent.parent.on; width: 10; height: 10; radius: 5; color: theme.brand }
                            }
                            Text { x: 32; height: 40; verticalAlignment: Text.AlignVCenter; text: modelData[1]; font.family: theme.font; font.pixelSize: 14; color: parent.parent.on ? theme.text : theme.textSecondary }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.reportReason = modelData[0] }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData[1]
                            Accessible.checked: parent.on
                        }
                        // The comment box sits under the chosen reason.
                        Rectangle {
                            visible: parent.on
                            width: 787; height: visible ? 120 : 0; radius: 4; color: theme.inputFilled
                            TextArea {
                                anchors.fill: parent
                                placeholderText: "Add a comment"; placeholderTextColor: theme.textTertiary
                                wrapMode: TextArea.Wrap; background: null
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                                text: reportComment.text
                                onTextChanged: if (reportComment.text !== text) reportComment.text = text
                            }
                        }
                        Item { visible: parent.on; width: 1; height: 8 }
                    }
                }
                Item { width: 1; height: 20 }
                Rectangle {
                    width: 124; height: 31.33; radius: 4
                    color: rsHover.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: "Submit"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
                    HoverHandler { id: rsHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            backend.reportAppReview(root.appId, root.reportReview ? root.reportReview.id : "", root.reportReason, reportComment.text)
                            root.view = "reviews"
                        }
                    }
                    Accessible.role: Accessible.Button; Accessible.name: "Submit"
                }
            }
            // The comment, kept while the reason changes.
            TextEdit { id: reportComment; visible: false }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 61
                color: theme.surface
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                PoweredBy { x: 56; y: 21 }
            }
        }

        // ---- Write a review ----
        Item {
            anchors.fill: parent
            visible: root.view === "write"
            ViewHeader { subtitle: "Write a review" }
            Flickable {
                y: 80; width: parent.width; height: parent.height - 80 - 61
                contentHeight: 600
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Item {
                    width: 899; height: 600
                    Row {
                        x: 56; y: 24; spacing: 0
                        Text { text: "Rating"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                        Text { text: " *"; font.family: theme.font; font.pixelSize: 12; color: theme.redForeground3 }
                    }
                    Row {
                        x: 56; y: 48; spacing: 1.5
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                width: 28; height: 28; radius: 4
                                color: "transparent"
                                FluentIcon { anchors.fill: parent; size: 28; name: index < (starHover.hovered ? root.hoverStar : root.rating) ? "star-28-filled" : "star-28"; color: index < (starHover.hovered ? root.hoverStar : root.rating) ? theme.brand : theme.textStrong }
                                HoverHandler { id: starHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.hoverStar = index + 1 }
                                TapHandler { onTapped: root.rating = index + 1 }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: root.stars(index + 1)
                                Accessible.checked: root.rating === index + 1
                            }
                        }
                    }
                    Text { x: 56; y: 96; text: "Title"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Rectangle {
                        x: 56; y: 120; width: 773; height: 32; radius: 4; color: theme.inputFilled
                        TextField {
                            id: reviewTitle
                            anchors.fill: parent; leftPadding: 10
                            placeholderText: "Give your review a title (optional)"
                            placeholderTextColor: theme.textTertiary
                            background: null
                            font.family: theme.font; font.pixelSize: 14; color: theme.text
                        }
                    }
                    Text { x: 56; y: 172; text: "Description"; font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary }
                    Rectangle {
                        x: 56; y: 196; width: 773; height: 200; radius: 4; color: theme.inputFilled
                        ScrollView {
                            anchors.fill: parent
                            TextArea {
                                id: reviewBody
                                leftPadding: 10; topPadding: 6
                                placeholderText: "Share your experience with this app (optional)"
                                placeholderTextColor: theme.textTertiary
                                wrapMode: TextArea.Wrap
                                background: null
                                font.family: theme.font; font.pixelSize: 14; color: theme.text
                            }
                        }
                    }
                    CheckBox {
                        id: publicBox
                        x: 56; y: 404
                        indicator: Rectangle {
                            x: 8; y: 10; width: 16; height: 16; radius: 2
                            color: publicBox.checked ? theme.brandFill : "transparent"
                            border.width: publicBox.checked ? 0 : 0.67; border.color: theme.textSecondary
                            FluentIcon { anchors.centerIn: parent; visible: publicBox.checked; name: "checkmark-12-filled"; size: 12; color: theme.textOnBrand }
                        }
                        contentItem: Column {
                            leftPadding: 32
                            Text { text: "Post my review publicly as " + (backend.userMail || backend.userName) + "."; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                            Text { leftPadding: 4; text: "(If unchecked, the review will be posted as Anonymous.)"; font.family: theme.font; font.pixelSize: 14; color: theme.textSecondary }
                        }
                    }
                    Rectangle {
                        x: 56; y: 476; width: 124; height: 31.33; radius: 4
                        readonly property bool on: root.rating > 0
                        color: !on ? theme.bgDisabled : submitHover.hovered ? theme.brandHover : theme.brandFill
                        Text { anchors.centerIn: parent; text: "Submit"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? theme.textOnBrand : theme.disabled }
                        HoverHandler { id: submitHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: parent.on
                            onTapped: {
                                backend.postAppReview(root.appId, root.rating, reviewTitle.text, reviewBody.text, !publicBox.checked)
                                root.view = "main"
                            }
                        }
                        Accessible.role: Accessible.Button; Accessible.name: "Submit"
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 61
                color: theme.surface
                Rectangle { width: parent.width; height: 0.67; color: theme.divider }
                PoweredBy { x: 56; y: 21 }
            }
        }
    }
    property int hoverStar: 0

}
