import QtQuick
import QtQuick.Controls.Basic

// The OneNote app. Teams shows OneNote for the web here; OST lays it out
// the same way: your notebooks (most recent first, Create notebook), and
// in a notebook its sections and pages beside the page, with Add section,
// Add page and Open in OneNote.
Item {
    id: root
    /// The backend's onenote_json, parsed (one reply at a time).
    property var reply: ({})
    property bool busy: false
    signal load(string view, string id)
    signal create(string kind, string parent, string name, string text)
    signal removePage(string id)

    property var notebooks: []
    property var notebook: null
    property var sections: []
    property var section: null
    property var pages: []
    property var page: null
    property string html: ""
    /// Writing a new page.
    property bool writing: false
    property string error: ""

    Component.onCompleted: load("notebooks", "")
    onReplyChanged: {
        const r = reply || {}
        error = r.error || ""
        if (r.view === "notebooks") notebooks = r.notebooks || []
        else if (r.view === "sections" && notebook && r.id === notebook.id) {
            sections = r.sections || []
            if (!section && sections.length) openSection(sections[0])
        } else if (r.view === "pages" && section && r.id === section.id) {
            pages = r.pages || []
            if (!page && !writing && pages.length) openPage(pages[0])
        } else if (r.view === "page" && page && r.id === page.id) html = r.html || ""
        else if (r.view === "created") {
            if (r.kind === "notebook") { openNotebook(r.item) }
            else if (r.kind === "section") { section = null; load("sections", notebook.id); openSection(r.item) }
            // A new page takes a moment to list; show it straight away.
            else { writing = false; pages = [r.item].concat(pages); openPage(r.item) }
        } else if (r.view === "deleted") {
            pages = pages.filter(p => p.id !== r.id); page = null; html = ""
            if (pages.length) openPage(pages[0])
        }
    }
    function openNotebook(nb) { notebook = nb; sections = []; section = null; pages = []; page = null; html = ""; load("sections", nb.id) }
    function openSection(sec) { section = sec; pages = []; page = null; html = ""; writing = false; load("pages", sec.id) }
    function openPage(p) { page = p; html = ""; writing = false; load("page", p.id) }
    function when(iso) { return iso ? Qt.formatDateTime(new Date(iso), "dddd, MMMM d, yyyy  h:mm AP") : "" }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // Notebooks
    Item {
        visible: !root.notebook
        anchors.fill: parent
        Row {
            x: 24; y: 18; spacing: 10
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "notebook-20"; size: 22; color: "#7719AA" }
            Text { text: "OneNote"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }
        Text { x: 24; y: 80; text: "Recent notebooks"; font.family: theme.font; font.pixelSize: theme.base + 2; font.weight: Font.DemiBold; color: theme.text }
        AddButton { x: parent.width - width - 24; y: 74; label: "Create notebook"; onClicked: nameDialog.ask("notebook", "", "Create notebook", "Notebook name") }
        ListView {
            x: 16; y: 116; width: parent.width - 32; height: parent.height - y
            clip: true
            model: root.notebooks
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 56; radius: theme.radius
                color: nbh.hovered ? theme.rowHover : "transparent"
                Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4; color: "#F1E6F7"
                    FluentIcon { anchors.centerIn: parent; name: "notebook-20"; size: 20; color: "#7719AA" }
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    Text { text: modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                    Text { text: "Modified " + root.when(modelData.modified); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
                HoverHandler { id: nbh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openNotebook(modelData) }
                Accessible.role: Accessible.Button
                Accessible.name: "Notebook " + modelData.name
            }
        }
        Column {
            visible: !root.busy && !root.error && root.notebooks.length === 0
            anchors.centerIn: parent
            spacing: 12
            FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "notebook-20"; size: 64; color: "#7719AA" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "You don't have any notebooks yet"; font.family: theme.font; font.pixelSize: theme.base + 1; font.weight: Font.DemiBold; color: theme.text }
        }
    }

    // A notebook: sections, pages, the page.
    Item {
        visible: !!root.notebook
        anchors.fill: parent
        Rectangle {
            id: top
            width: parent.width; height: 52; color: theme.surface
            Rectangle {
                x: 12; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: theme.radius
                color: bh.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "chevron-left-20"; size: 18; color: theme.textStrong }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.notebook = null; root.load("notebooks", "") } }
                Accessible.role: Accessible.Button
                Accessible.name: "All notebooks"
            }
            FluentIcon { x: 52; anchors.verticalCenter: parent.verticalCenter; name: "notebook-20"; size: 20; color: "#7719AA" }
            Text { x: 80; anchors.verticalCenter: parent.verticalCenter; text: root.notebook ? root.notebook.name : ""; font.family: theme.font; font.pixelSize: theme.base + 2; font.weight: Font.Bold; color: theme.text }
            Rectangle {
                visible: !!root.notebook && !!root.notebook.web_url
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                width: openRow.implicitWidth + 20; height: 32; radius: theme.radius
                color: oh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
                Row { id: openRow; anchors.centerIn: parent; spacing: 6
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "open-20"; size: 16; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Open in OneNote"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                }
                HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally((root.page && root.page.web_url) || root.notebook.web_url) }
                Accessible.role: Accessible.Button
                Accessible.name: "Open in OneNote"
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.dividerSoft }
        }
        // Sections
        Rectangle {
            id: secCol
            anchors { top: top.bottom; bottom: parent.bottom }
            width: 220; color: theme.pane
            ListView {
                anchors { fill: parent; topMargin: 8; bottomMargin: 48 }
                clip: true
                model: root.sections
                delegate: ListRow {
                    required property var modelData
                    label: modelData.name; selected: root.section && root.section.id === modelData.id
                    bar: "#7719AA"
                    onClicked: root.openSection(modelData)
                }
            }
            AddButton { x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; label: "Add section"; onClicked: nameDialog.ask("section", root.notebook.id, "Add section", "Section name") }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        }
        // Pages
        Rectangle {
            id: pageCol
            anchors { top: top.bottom; bottom: parent.bottom; left: secCol.right }
            width: 260; color: theme.surface
            ListView {
                anchors { fill: parent; topMargin: 8; bottomMargin: 48 }
                clip: true
                model: root.pages
                delegate: ListRow {
                    required property var modelData
                    label: modelData.title; selected: root.page && root.page.id === modelData.id
                    onClicked: root.openPage(modelData)
                }
            }
            AddButton {
                visible: !!root.section
                x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; label: "Add page"
                onClicked: { root.page = null; root.html = ""; root.writing = true; newTitle.text = ""; newText.text = ""; newTitle.forceActiveFocus() }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        }
        // The page
        Flickable {
            visible: !!root.page && !root.writing
            anchors { top: top.bottom; bottom: parent.bottom; left: pageCol.right; right: parent.right; margins: 24 }
            contentHeight: pageCol2.height; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: pageCol2
                width: parent.width; spacing: 8
                Row {
                    width: parent.width
                    Text { width: parent.width - 40; wrapMode: Text.Wrap; text: root.page ? root.page.title : ""; font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.text }
                    Rectangle {
                        width: 32; height: 32; radius: theme.radius
                        color: dh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "delete-20"; size: 18; color: theme.textStrong }
                        HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.removePage(root.page.id) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Delete page"
                    }
                }
                Text { text: root.page ? root.when(root.page.modified) : ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: root.html
                    font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text
                    // Links in notes open in the browser (http/https only).
                    onLinkActivated: l => { if (/^https?:\/\//.test(l)) Qt.openUrlExternally(l) }
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                }
            }
        }
        // A new page
        Column {
            visible: root.writing
            anchors { top: top.bottom; left: pageCol.right; right: parent.right; margins: 24 }
            spacing: 12
            TextInput {
                id: newTitle
                width: parent.width
                font.family: theme.font; font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.text
                Text { visible: !newTitle.text; text: "Page title"; color: theme.textTertiary; font: newTitle.font }
                Accessible.name: "Page title"
            }
            Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
            Rectangle {
                width: parent.width; height: 280; radius: theme.radius
                color: theme.input; border.color: newText.activeFocus ? theme.brand : theme.stroke
                Flickable {
                    anchors.fill: parent; anchors.margins: 10
                    contentHeight: newText.contentHeight; clip: true
                    TextEdit {
                        id: newText
                        width: parent.width; wrapMode: TextEdit.Wrap
                        font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text
                        Text { visible: !newText.text; text: "Start typing"; color: theme.textTertiary; font: newText.font }
                        Accessible.name: "Page text"
                    }
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    opacity: newTitle.text.trim() ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: "Save"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: if (newTitle.text.trim()) root.create("page", root.section.id, newTitle.text.trim(), newText.text) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Save page"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: { root.writing = false; if (root.pages.length) root.openPage(root.pages[0]) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
        Text {
            visible: !root.busy && !!root.section && root.pages.length === 0 && !root.writing
            anchors { left: pageCol.right; right: parent.right; verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignHCenter
            text: "This section is empty. Add a page to start."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
    }
    Text {
        visible: !!root.error
        anchors.centerIn: parent
        text: root.error
        font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
    }
    BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }

    // Name a new notebook or section.
    Popup {
        id: nameDialog
        property string kind
        property string parentId
        property string heading
        property string hint
        function ask(k, p, h, ht) { kind = k; parentId = p; heading = h; hint = ht; open() }
        anchors.centerIn: parent
        width: 400; padding: 24; modal: true
        onOpened: { nameField.text = ""; nameField.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 14
            Text { text: nameDialog.heading; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Rectangle {
                width: 352; height: 32; radius: theme.radius
                color: theme.input; border.color: nameField.activeFocus ? theme.brand : theme.stroke
                TextInput {
                    id: nameField
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
                    Text { visible: !nameField.text; text: nameDialog.hint; color: theme.textTertiary; font: nameField.font }
                    Keys.onReturnPressed: nameDialog.done()
                    Accessible.name: nameDialog.hint
                }
            }
            Row {
                spacing: 8; layoutDirection: Qt.RightToLeft; width: 352
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: nameDialog.done() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Create"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: nameDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
        function done() {
            if (!nameField.text.trim()) return
            root.create(kind, parentId, nameField.text.trim(), "")
            close()
        }
    }

    component AddButton: Rectangle {
        id: ab
        property string label
        signal clicked()
        width: abRow.implicitWidth + 20; height: 32; radius: theme.radius
        color: abh.hovered ? theme.rowHover : "transparent"
        Row { id: abRow; anchors.centerIn: parent; spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "add-20"; size: 18; color: theme.brand }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ab.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand }
        }
        HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ab.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component ListRow: Rectangle {
        id: lr
        property string label
        property bool selected
        property color bar: theme.brand
        signal clicked()
        width: ListView.view ? ListView.view.width : 200; height: 40
        color: selected ? theme.selected : lh.hovered ? theme.rowHover : "transparent"
        Rectangle { visible: lr.selected; width: 4; height: parent.height; color: lr.bar }
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24; elide: Text.ElideRight; text: lr.label; font.family: theme.font; font.pixelSize: theme.base; font.weight: lr.selected ? Font.DemiBold : Font.Normal; color: theme.text }
        HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: lr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    // Test harness hooks
    function newPageForTest(title, text) { root.writing = true; root.create("page", root.section.id, title, text) }
}
