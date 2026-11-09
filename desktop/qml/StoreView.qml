import QtQuick
import QtQuick.Controls.Basic

// The Store, laid out as Teams': "Store" with Home, the "Do more in
// Teams" banner with Search agents and apps, then "Added by your org",
// apps from Microsoft and every app, as cards (icon, name, what it does).
// An app's card opens Teams' app details dialog; Add installs it in Teams
// on the web (installing needs a permission OST's sign-in doesn't have).
Item {
    id: root
    property var reply: ({})
    property bool busy: false
    signal load()
    /// Open a native app (planner, onenote, people) in OST.
    signal openApp(string key)

    readonly property var apps: reply.apps || []
    property string query: ""
    property int shown: 48
    readonly property var native_: ({ "Planner": "planner", "OneNote": "onenote", "People": "people" })
    readonly property var microsoftNames: ["Planner", "OneNote", "Whiteboard", "Shifts", "Clipchamp", "Forms", "Lists", "Approvals",
        "Bookings", "Viva Engage", "Viva Insights", "Viva Learning", "Power BI", "Loop", "Stream", "Word", "Excel", "PowerPoint"]
    readonly property var org: apps.filter(a => a.distribution === "organization")
    readonly property var microsoft: microsoftNames.map(n => apps.find(a => a.name === n)).filter(a => !!a)
    // Exact names first, then names that start with it, then the rest.
    readonly property var results: {
        const q = query.trim().toLowerCase()
        if (q.length < 2) return []
        const rank = a => { const n = a.name.toLowerCase(); return n === q ? 0 : n.indexOf(q) === 0 ? 1 : n.indexOf(q) >= 0 ? 2 : 3 }
        return apps.filter(a => (a.name + " " + a.short).toLowerCase().indexOf(q) >= 0)
            .map((a, i) => ({ a: a, r: rank(a), i: i })).sort((x, y) => x.r - y.r || x.i - y.i).map(x => x.a)
    }

    onVisibleChanged: if (visible && !apps.length && !busy) load()

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Header
    Row {
        x: 24; y: 0; height: 60; spacing: 32
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Store"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Item {
            width: homeText.implicitWidth; height: 60
            Text { id: homeText; anchors.verticalCenter: parent.verticalCenter; text: "Home"; font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 3; radius: 1.5; color: theme.brand }
        }
    }
    Rectangle { y: 60; width: parent.width; height: 1; color: theme.dividerSoft }

    Flickable {
        anchors { fill: parent; topMargin: 61 }
        contentHeight: body.height + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: body
            width: parent.width
            // Banner
            Rectangle {
                width: parent.width; height: 300
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: theme.dark ? "#2B2B40" : "#E8EBFA" }
                    GradientStop { position: 0.5; color: theme.dark ? "#262636" : "#F3F2FA" }
                    GradientStop { position: 1.0; color: theme.dark ? "#2B2B40" : "#E8EBFA" }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Do more in Teams"; font.family: theme.font; font.pixelSize: 40; font.weight: Font.Bold; color: theme.text }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Discover agents and apps that can help you tackle any task."; font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text }
                    Item { width: 1; height: 8 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(580, root.width - 80); height: 48; radius: 24
                        color: theme.surface; border.color: search.activeFocus ? theme.brand : theme.dividerSoft
                        FluentIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textStrong }
                        TextInput {
                            id: search
                            x: 48; width: parent.width - 64; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text; clip: true
                            Text { visible: !search.text; text: "Search agents and apps"; color: theme.textSecondary; font: search.font }
                            onTextChanged: { root.query = text; root.shown = 48 }
                            Keys.onEscapePressed: text = ""
                            Accessible.name: "Search agents and apps"
                        }
                    }
                }
            }
            Item { width: 1; height: 24 }
            // Search results
            Section {
                visible: root.query.trim().length >= 2
                title: root.results.length ? "Results for “" + root.query.trim() + "”" : "No apps match “" + root.query.trim() + "”"
                apps: root.results.slice(0, root.shown)
            }
            Section {
                visible: root.query.trim().length < 2
                title: "Added by your org"
                subtitle: "Made available by your organization's technology team"
                apps: root.org
                empty: "Your organization hasn't added any apps yet."
            }
            Section {
                visible: root.query.trim().length < 2 && root.microsoft.length > 0
                title: "Apps from Microsoft"
                subtitle: "Get more done with Microsoft 365 apps in Teams"
                apps: root.microsoft
            }
            Section {
                visible: root.query.trim().length < 2
                title: "All apps"
                subtitle: root.apps.length ? root.apps.length + " apps" : ""
                apps: root.apps.slice(0, root.shown)
            }
            Rectangle {
                visible: (root.query.trim().length < 2 ? root.apps.length : root.results.length) > root.shown
                x: 48; width: moreText.implicitWidth + 24; height: 32; radius: theme.radius
                color: smh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
                Text { id: moreText; anchors.centerIn: parent; text: "Show more"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                HoverHandler { id: smh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.shown += 48 }
                Accessible.role: Accessible.Button
                Accessible.name: "Show more"
            }
        }
    }
    Text {
        visible: !!root.reply.error
        anchors.centerIn: parent
        text: root.reply.error || ""
        font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
    }
    BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }

    // An app's details: Teams' app details dialog.
    AppDetailsDialog {
        id: details
        offerOpen: true
        onShareApp: id => storeShare.start(id)
        // Apps OST has natively open here; the rest in Teams on the web.
        onOpenApp: (id, name) => {
            const k = root.native_[name] || ""
            if (k) root.openApp(k)
            else Qt.openUrlExternally("https://teams.microsoft.com/l/app/" + encodeURIComponent(id))
        }
    }
    ShareForm { id: storeShare }

    component Section: Column {
        id: sec
        property string title
        property string subtitle
        property var apps: []
        property string empty: ""
        x: 48; width: root.width - 96; spacing: 6
        bottomPadding: 28
        Text { text: sec.title; font.family: theme.font; font.pixelSize: 20; font.weight: Font.Bold; color: theme.text }
        Text { visible: !!sec.subtitle; text: sec.subtitle; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
        Item { width: 1; height: 8 }
        Text { visible: sec.apps.length === 0 && !!sec.empty; text: sec.empty; font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary }
        Flow {
            width: parent.width; spacing: 16
            Repeater {
                model: sec.apps
                Rectangle {
                    required property var modelData
                    width: 300; height: 96; radius: 8
                    color: ch.hovered ? theme.rowHover : theme.surface; border.color: theme.dividerSoft
                    AppIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 48; app: parent.modelData }
                    Column {
                        x: 80; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 96; spacing: 4
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                        Text { width: parent.width; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight; text: modelData.short; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                    }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: details.show(modelData.teams_id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name + ". " + modelData.short
                }
            }
        }
    }
    component AppIcon: Rectangle {
        property var app
        property int size: 48
        width: size; height: size; radius: 8
        color: theme.pane
        Image {
            anchors.fill: parent; anchors.margins: 4
            source: parent.app && parent.app.icon ? parent.app.icon : ""
            sourceSize: Qt.size(parent.size * 2, parent.size * 2)
            fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
        }
        Text {
            visible: !parent.app || !parent.app.icon
            anchors.centerIn: parent
            text: parent.app ? parent.app.name.charAt(0) : ""
            font.family: theme.font; font.pixelSize: parent.size / 2; font.weight: Font.Bold; color: theme.textStrong
        }
    }

    // Test harness hooks
    function searchForTest(q) { search.text = q }
    function detailsForTest(name) { const a = root.apps.find(x => x.name === name); if (a) details.show(a.teams_id); return !!a }
}
