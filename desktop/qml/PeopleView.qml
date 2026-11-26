import QtQuick
import QtQuick.Controls.Basic

// The People app, laid out as Teams' (measured on winpc 2026-11-26,
// TASK-0333 / TASK-0339): a pane with "People" and Add contact, All
// contacts (with its count), Favorites and Categories (or "When you create
// categories, they will appear here."); the content has the view's title,
// Teams' toolbar (Sort ▾ and "Find a contact"), the column header (Name,
// Contact info, Categories, Company, Office location; each sorts on a
// click, ↑ / ↓ on the sorted one) with Manage column view (···), and the
// contacts: the star, the picture and name with Chat, Audio call and More
// options on hover, the email and phone as links, then the rest. Your
// contacts live in Teams' contacts service (api::contacts).
//
// Teams' rules, from its People app code: Find a contact keeps contacts
// whose name, an email address or a number holds the text (any case,
// 500 ms after typing); Sort is First name, Last name, Company or Recently
// added (the date's order words New to Old / Old to New), and missing
// values sort last (first when reversed), then by name. A header click
// sorts by its column (Contact info by email address) and a second click
// reverses it.
Item {
    id: root
    /// The backend's contacts_json, parsed: {contacts, categories, notice}.
    property var data_: ({})
    property bool busy: false
    signal load()
    signal remove(string id)
    signal change(string op, string json)
    signal chatWith(string mri, string name)
    signal callPerson(string mri, string name)

    /// "all", "favorites" or "cat:<name>".
    property string view: "all"
    property bool categoriesOpen: true
    readonly property var all: data_.contacts || []
    readonly property var categories: data_.categories || []
    readonly property var inView: view === "favorites" ? all.filter(c => c.favorite)
        : view.indexOf("cat:") === 0 ? all.filter(c => (c.categories || []).indexOf(view.slice(4)) >= 0)
        : all
    readonly property string title: view === "favorites" ? qsTr("Favorites") : view.indexOf("cat:") === 0 ? view.slice(4) : qsTr("All contacts")

    // ---- Sort and Find (kept on this device) --------------------------
    property string sortField: "FIRST_NAME"
    property string sortDirection: "ASCENDING"
    property string keyword: ""
    readonly property var dateFields: ["RECENTLY_ADDED"]
    function setSort(field, direction) {
        sortField = field; sortDirection = direction
        backend.setSetting("peopleSort", JSON.stringify({ field: field, direction: direction }))
    }
    // The menu's field: a date field and the other kind keep the order's
    // place (A to Z ↔ New to Old).
    function pickSortField(f) {
        let d = sortDirection
        if (dateFields.indexOf(f) >= 0 && d === "ASCENDING") d = "DESCENDING"
        else if (dateFields.indexOf(sortField) >= 0 && d === "DESCENDING") d = "ASCENDING"
        setSort(f, d)
    }
    function sortKey(c) {
        switch (sortField) {
        case "FIRST_NAME": return c.first || ""
        case "LAST_NAME": return c.last || ""
        case "COMPANY": return c.company || ""
        case "OFFICE_LOCATION": return c.office_location || ""
        case "RECENTLY_ADDED": return c.created || ""
        case "EMAIL_ADDRESS": return c.email || ""
        case "TAG": return (c.categories || []).join(",")
        default: return ""
        }
    }
    function compare(a, b) {
        const asc = sortDirection === "ASCENDING"
        const o = asc ? a : b, s = asc ? b : a
        const l = sortKey(o), d = sortKey(s)
        return (l && d ? l.localeCompare(d) : l ? -1 : d ? 1 : 0) || String(o.name || "").localeCompare(String(s.name || ""))
    }
    function matches(c, k) {
        const q = k.toLowerCase()
        const digits = k.replace(/[\s().+-]/g, "")
        const num = /^\d+$/.test(digits) ? digits : ""
        const hit = t => !!t && (String(t).toLowerCase().indexOf(q) >= 0 || (!!num && String(t).replace(/\D/g, "").indexOf(num) >= 0))
        return [c.name, c.first + " " + c.last].some(t => !!t && String(t).toLowerCase().indexOf(q) >= 0)
            || (c.emails || [c.email]).some(e => !!e && String(e).toLowerCase().indexOf(q) >= 0)
            || (c.phones || [c.phone, c.mobile]).some(hit)
    }
    readonly property var shown: {
        const k = keyword.trim()
        const list = k ? inView.filter(c => matches(c, k)) : inView.slice()
        list.sort(compare)
        return list
    }
    // The sort menu's words and the button's label and icon.
    readonly property var sortFields: [{ value: "FIRST_NAME", label: qsTr("First name") }, { value: "LAST_NAME", label: qsTr("Last name") },
                                       { value: "COMPANY", label: qsTr("Company") }, { value: "RECENTLY_ADDED", label: qsTr("Recently added") }]
    readonly property var sortPicked: sortFields.find(f => f.value === sortField) || null
    readonly property var orderWords: dateFields.indexOf(sortField) >= 0
        ? [{ value: "DESCENDING", label: qsTr("New to Old") }, { value: "ASCENDING", label: qsTr("Old to New") }]
        : [{ value: "ASCENDING", label: qsTr("A to Z") }, { value: "DESCENDING", label: qsTr("Z to A") }]
    readonly property string sortIcon: !sortPicked ? "arrow-sort-20"
        : dateFields.indexOf(sortField) >= 0 ? (sortDirection === "ASCENDING" ? "arrow-sort-up-lines-20" : "arrow-sort-down-lines-20")
        : (sortDirection === "ASCENDING" ? "text-sort-ascending-20" : "text-sort-descending-20")

    // ---- Columns (Manage column view; kept on this device) ------------
    property bool showCategories: false
    property bool showCompany: true
    property bool showOffice: true
    function saveColumns() { backend.setSetting("peopleColumns", JSON.stringify({ categories: showCategories, company: showCompany, office: showOffice })) }
    Component.onCompleted: {
        load()
        try { const s = JSON.parse(backend.setting("peopleSort") || "{}"); if (s.field) { sortField = s.field; sortDirection = s.direction || "ASCENDING" } } catch (e) {}
        try { const c = JSON.parse(backend.setting("peopleColumns") || "{}"); if (c.company !== undefined) { showCategories = !!c.categories; showCompany = !!c.company; showOffice = !!c.office } } catch (e) {}
    }
    // Teams' columns: Name at least 260, the rest share what is left
    // (all equal when Name gets 260 or more), 2 px apart, from 52 to 44
    // before the right edge (the ··· column).
    readonly property var columns: {
        const L = [{ id: "NAME", label: qsTr("Name"), field: "FIRST_NAME" }, { id: "CONTACT_INFO", label: qsTr("Contact info"), field: "EMAIL_ADDRESS" }]
        if (showCategories) L.push({ id: "CATEGORIES", label: qsTr("Categories"), field: "TAG" })
        if (showCompany) L.push({ id: "COMPANY", label: qsTr("Company"), field: "COMPANY" })
        if (showOffice) L.push({ id: "OFFICE_LOCATION", label: qsTr("Office location"), field: "OFFICE_LOCATION" })
        const avail = content.width - 96 - 2 * L.length
        const even = avail / L.length
        const nameW = Math.max(260, even)
        const rest = even >= 260 ? even : (avail - 260) / (L.length - 1)
        let x = 52
        for (let i = 0; i < L.length; i++) { L[i].x = x; L[i].w = i === 0 ? nameW : Math.max(0, rest); x += L[i].w + 2 }
        return L
    }
    function col(id) { return columns.find(c => c.id === id) || null }
    // The header's ↑ / ↓: Last name shows on Name.
    function headerSorted(c) { return (sortField === "LAST_NAME" ? "FIRST_NAME" : sortField) === c.field }
    function toggleColumnSort(c) {
        setSort(c.field, sortField === c.field && sortDirection === "ASCENDING" ? "DESCENDING" : "ASCENDING")
    }

    // Teams' notices for a change ("Contact saved.", "Contact deleted.",
    // "Added to speed dial.").
    property real noticeAt: 0
    onData_Changed: {
        if (data_.notice && data_.at && data_.at !== noticeAt) {
            noticeAt = data_.at
            window.showToast({ text: data_.notice, intent: "success" })
        }
    }

    // Outlook's category presets as colours.
    function catColor(preset) {
        const map = { preset0: "#E74856", preset1: "#FF8C00", preset2: "#C19C00", preset3: "#FFF100", preset4: "#00CC6A",
                      preset5: "#00B7C3", preset6: "#8E8CD8", preset7: "#0078D4", preset8: "#E3008C", preset9: "#A4262C" }
        return map[preset] || theme.textSecondary
    }
    function contactJson(c) { return JSON.stringify({ contact: c }) }
    function op(name, c, extra) { root.change(name, JSON.stringify(Object.assign({ contact: c }, extra || {}))) }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // The pane (380 wide): "People" 18/700 at 20,18, Add contact (32 x 31
    // at 328,14); rows 36 tall from 72 (icon at 28, label 14 px at 54, All
    // contacts' count 12/600 in brand at 316).
    Rectangle {
        id: pane
        width: 380; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Text { x: 20; y: 18; text: qsTr("People"); font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Rectangle {
            id: hcFill1
            x: 328; y: 14; width: 32; height: 31; radius: theme.radius
            color: ah.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "person-add-20"; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
            HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: addDialog.start() }
            ToolTip.visible: ah.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Add contact")
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Add contact")
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }
        Column {
            x: 4; y: 72; width: parent.width - 8
            NavRow {
                label: qsTr("All contacts"); icon: root.view === "all" ? "people-20-filled" : "people-20"
                count: root.all.length; selected: root.view === "all"
                onClicked: root.view = "all"
            }
            NavRow {
                label: qsTr("Favorites"); icon: root.view === "favorites" ? "star-20-filled" : "star-20"
                selected: root.view === "favorites"
                onClicked: root.view = "favorites"
            }
            NavRow {
                label: qsTr("Categories"); icon: "tag-20"; selected: false; height: 34
                chevron: root.categoriesOpen ? "down" : "right"
                onClicked: root.categoriesOpen = !root.categoriesOpen
            }
            Text {
                visible: root.categoriesOpen && root.categories.length === 0
                x: 28; width: parent.width - 40; wrapMode: Text.Wrap
                topPadding: 2
                text: qsTr("When you create categories, they will appear here.")
                font.family: theme.font; font.pixelSize: 12; color: theme.text
            }
            Repeater {
                model: root.categoriesOpen ? root.categories : []
                NavRow {
                    required property var modelData
                    label: modelData.name; indent: 28
                    dot: root.catColor(modelData.color)
                    selected: root.view === "cat:" + modelData.name
                    onClicked: root.view = "cat:" + modelData.name
                }
            }
        }
    }

    // Content
    Item {
        id: content
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Text { x: 20; y: 18; text: root.title; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }

        // The toolbar (68 down): Sort (a subtle button, its icon at 12)
        // ending 8 before "Find a contact" (210 x 32, #F5F5F5, 20 from the
        // right).
        Rectangle {
            id: sortButton
            visible: root.inView.length > 0 || root.keyword.length > 0
            x: findBox.x - 8 - width; y: 68
            width: 12 + 20 + 5 + sortLabel.implicitWidth + 12; height: 31; radius: 4
            color: sbh.hovered || sortMenu.opened ? theme.rowHover : "transparent"
            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: root.sortIcon; size: 20; color: theme.onFill(sortButton, theme.text) }
            Text {
                id: sortLabel
                x: 37; anchors.verticalCenter: parent.verticalCenter
                text: root.sortPicked ? root.sortPicked.label : qsTr("Sort")
                font.family: theme.font; font.pixelSize: 14; color: theme.onFill(sortButton, theme.text)
            }
            HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sortMenu.open() }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Sort")
            Accessible.description: root.sortPicked ? qsTr("Currently selected: %1, %2").arg(root.sortPicked.label).arg((root.orderWords.find(w => w.value === root.sortDirection) || {}).label || "")
                                                    : qsTr("No option selected")
            MenuPopup {
                id: sortMenu
                y: parent.height; minRowWidth: 264; labelInset: 26
                items: [{ heading: qsTr("Sort by") }].concat(root.sortFields.map(f => ({ label: f.label, checked: root.sortField === f.value, value: f.value })))
                    .concat([{ separator: true }, { heading: qsTr("Sort order") }])
                    .concat(root.orderWords.map(w => ({ label: w.label, checked: !!root.sortPicked && root.sortDirection === w.value, order: w.value })))
                onPicked: i => {
                    const it = items[i]
                    if (it.value) root.pickSortField(it.value)
                    else if (it.order) root.setSort(root.sortField, it.order)
                }
            }
        }
        Rectangle {
            id: findBox
            visible: sortButton.visible
            x: parent.width - 20 - width; y: 68; width: 210; height: 32; radius: 4
            color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
            border.width: theme.highContrast ? 1 : 0; border.color: theme.stroke
            Rectangle { visible: findInput.activeFocus; anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: theme.brand }
            FluentIcon { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 20; color: theme.textSecondary }
            TextInput {
                id: findInput
                x: 37; width: parent.width - 37 - (findClear.visible ? 34 : 10); anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                selectByMouse: true
                onTextChanged: findDebounce.restart()
                Keys.onEscapePressed: text = ""
                Text { visible: !findInput.text; text: qsTr("Find a contact"); color: theme.textSecondary; font: findInput.font }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Find a contact")
            }
            Timer { id: findDebounce; interval: 500; onTriggered: root.keyword = findInput.text }
            Rectangle {
                id: findClear
                visible: findInput.text.length > 0
                x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; radius: 4
                color: fch.hovered ? theme.rowHover : "transparent"
                FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textSecondary }
                HoverHandler { id: fch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { findInput.text = ""; root.keyword = "" } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear")
            }
        }

        // The list (from 107): the header (44.67) and 69 px rows, each
        // with a #E0E0E0 rule; links in #4F52B2.
        Item {
            id: table
            visible: root.shown.length > 0
            anchors { fill: parent; topMargin: 107 }
            readonly property color rule: theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF")
            readonly property color link: theme.pick("#4F52B2", "#7F85F5", "#FFFF00")
            Rectangle { width: parent.width; height: 0.67; color: table.rule }
            Item {
                id: head
                y: 1; width: parent.width; height: 44.67
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: table.rule }
                Repeater {
                    model: root.columns
                    Rectangle {
                        id: hc
                        required property var modelData
                        x: modelData.x; y: 6; width: modelData.w; height: 32; radius: 4
                        color: hch.hovered ? theme.rowHover : "transparent"
                        Row {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Text { text: hc.modelData.label; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(hc, theme.text) }
                            FluentIcon {
                                visible: root.headerSorted(hc.modelData); anchors.verticalCenter: parent.verticalCenter
                                name: root.sortDirection === "ASCENDING" ? "arrow-up-12" : "arrow-down-12"; size: 12; color: theme.onFill(hc, theme.text)
                            }
                        }
                        HoverHandler { id: hch; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.toggleColumnSort(hc.modelData) }
                        Accessible.role: Accessible.ColumnHeader
                        Accessible.name: hc.modelData.label
                    }
                }
                // Manage column view: Show columns (Name and Contact info
                // always; Categories, Company, Office location).
                Rectangle {
                    id: colButton
                    x: parent.width - 44; y: 6.33; width: 32; height: 31.33; radius: 4
                    color: cbh.hovered || colMenu.opened ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: colMenu.opened ? theme.brand : theme.onFill(colButton, theme.textStrong) }
                    HoverHandler { id: cbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: colMenu.open() }
                    ToolTip.visible: cbh.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Manage column view")
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Manage column view")
                    Popup {
                        id: colMenu
                        x: parent.width - width; y: parent.height + 1; width: 272; padding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
                        contentItem: Column {
                            Text { height: 32; leftPadding: 5; verticalAlignment: Text.AlignVCenter; text: qsTr("Show columns"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                            Repeater {
                                model: [{ k: "", label: qsTr("Name"), on: true, fixed: true }, { k: "", label: qsTr("Contact info"), on: true, fixed: true },
                                        { k: "categories", label: qsTr("Categories"), on: root.showCategories }, { k: "company", label: qsTr("Company"), on: root.showCompany },
                                        { k: "office", label: qsTr("Office location"), on: root.showOffice }]
                                Rectangle {
                                    id: cm
                                    required property var modelData
                                    width: 264; height: 34; radius: 4
                                    color: cmh.hovered && !cm.modelData.fixed ? theme.rowHover : "transparent"
                                    Rectangle {
                                        id: box
                                        x: 13; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 2
                                        color: cm.modelData.on && !cm.modelData.fixed ? theme.brand : "transparent"
                                        border.width: cm.modelData.on && !cm.modelData.fixed ? 0 : 0.67
                                        border.color: cm.modelData.fixed ? theme.pick("#E0E0E0", "#3D3D3D", "#FFFFFF") : theme.textSecondary
                                        FluentIcon { visible: cm.modelData.on; anchors.centerIn: parent; name: "checkmark-12"; size: 12
                                                     color: cm.modelData.fixed ? theme.disabled : theme.onFill(box, "white") }
                                    }
                                    Text { x: 37; anchors.verticalCenter: parent.verticalCenter; text: cm.modelData.label; font.family: theme.font; font.pixelSize: 14
                                           color: cm.modelData.fixed ? theme.disabled : theme.text }
                                    HoverHandler { id: cmh; cursorShape: cm.modelData.fixed ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                    TapHandler {
                                        enabled: !cm.modelData.fixed
                                        onTapped: {
                                            if (cm.modelData.k === "categories") root.showCategories = !root.showCategories
                                            else if (cm.modelData.k === "company") root.showCompany = !root.showCompany
                                            else root.showOffice = !root.showOffice
                                            root.saveColumns()
                                        }
                                    }
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: cm.modelData.label
                                    Accessible.checked: cm.modelData.on
                                }
                            }
                        }
                    }
                }
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
                    readonly property var nameCol: root.columns[0]
                    width: ListView.view.width - 20; height: 69
                    color: crow.hot ? theme.rowHover : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.67; color: table.rule }
                    // Favorite: the star at 16 (on hover; always when it is one).
                    Rectangle {
                        id: starButton
                        visible: crow.hot || crow.modelData.favorite
                        x: 16; y: 18.33; width: 32; height: 31.33; radius: 4
                        color: sth.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: crow.modelData.favorite ? "star-16-filled" : "star-16"; size: 16
                                     color: crow.modelData.favorite ? theme.brand : theme.onFill(crow, theme.textStrong) }
                        HoverHandler { id: sth; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.op("favorite", crow.modelData, { on: !crow.modelData.favorite }) }
                        Accessible.role: Accessible.Button
                        Accessible.name: crow.modelData.favorite ? qsTr("Remove from favorites") : qsTr("Favorite")
                    }
                    Avatar { x: crow.nameCol.x + 5; y: 18.33; size: 32; name: crow.modelData.name; photoId: crow.modelData.mri || "" }
                    Text {
                        x: crow.nameCol.x + 45; y: 24.33
                        width: crow.nameCol.w - 45 - (crow.hot ? 115 : 4)
                        text: crow.modelData.name; elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(crow, theme.text)
                    }
                    // Chat, Audio call and More options, 18 from Name's end.
                    Row {
                        visible: crow.hot
                        x: crow.nameCol.x + crow.nameCol.w - 18 - 96; y: 18.33
                        RowTool { icon: "chat-20"; tip: qsTr("Chat"); usable: !!crow.modelData.mri; onClicked: root.chatWith(crow.modelData.mri, crow.modelData.name) }
                        RowTool { icon: "call-20"; tip: qsTr("Audio call"); usable: !!crow.modelData.mri; onClicked: root.callPerson(crow.modelData.mri, crow.modelData.name) }
                        RowTool {
                            id: moreTool
                            icon: "more-horizontal-20"; tip: qsTr("More options"); active: rowMenu.opened
                            onClicked: rowMenu.open()
                            MenuPopup {
                                id: rowMenu
                                y: parent.height; minRowWidth: 264
                                readonly property var c: crow.modelData
                                items: [{ label: qsTr("Edit"), icon: "edit-20", k: "edit" },
                                        { label: c.favorite ? qsTr("Remove from favorites") : qsTr("Add to favorites"), icon: c.favorite ? "star-off-20" : "star-add-20", k: "fav" },
                                        { label: c.speed_dial ? qsTr("Remove from speed dial") : qsTr("Add to speed dial"), icon: "person-add-20", k: "speed", enabled: !!c.mri },
                                        { label: qsTr("Add category"), icon: "tag-20", k: "cat", flyout: true },
                                        { separator: true },
                                        { label: qsTr("Chat"), icon: "chat-20", k: "chat", enabled: !!c.mri },
                                        { label: qsTr("Audio call"), icon: "call-20", k: "call", enabled: !!c.mri },
                                        { label: qsTr("Email"), icon: "mail-20", k: "mail", enabled: !!c.email },
                                        { separator: true },
                                        { label: qsTr("Delete"), icon: "delete-20", k: "delete" }]
                                onFlyoutRequested: (i, row) => {
                                    if (i < 0 || !row) { catFlyout.close(); return }
                                    catFlyout.contact = c; catFlyout.menu = rowMenu
                                    const p = row.mapToItem(rowMenu.contentItem, 0, 0)
                                    catFlyout.parent = rowMenu.contentItem
                                    catFlyout.x = -catFlyout.width + 4; catFlyout.y = p.y - 4
                                    catFlyout.open()
                                }
                                onPicked: i => {
                                    const k = items[i].k
                                    if (k === "edit") editDialog.start(c)
                                    else if (k === "fav") root.op("favorite", c, { on: !c.favorite })
                                    else if (k === "speed") root.op("speedDial", c, { on: !c.speed_dial })
                                    else if (k === "chat") root.chatWith(c.mri, c.name)
                                    else if (k === "call") root.callPerson(c.mri, c.name)
                                    else if (k === "mail") Qt.openUrlExternally("mailto:" + encodeURIComponent(c.email))
                                    else if (k === "delete") { deleteDialog.contact = c; deleteDialog.open() }
                                }
                                onClosed: catFlyout.close()
                            }
                        }
                    }
                    // Contact info: the email over the phone (one line is
                    // centred), 12 px links.
                    Column {
                        readonly property var cc: root.col("CONTACT_INFO")
                        readonly property var lines: [crow.modelData.email, crow.modelData.phone || crow.modelData.mobile].filter(t => !!t)
                        x: cc.x + 4; y: lines.length > 1 ? 14.33 : 24.33; width: cc.w - 8
                        Repeater {
                            model: parent.lines
                            Text {
                                required property string modelData
                                height: 20; verticalAlignment: Text.AlignVCenter
                                width: Math.min(implicitWidth, parent.width); elide: Text.ElideRight
                                text: modelData; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(crow, table.link)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Qt.openUrlExternally((modelData.indexOf("@") > 0 ? "mailto:" : "tel:") + encodeURIComponent(modelData)) }
                            }
                        }
                    }
                    Cell { readonly property var cc: root.col("CATEGORIES"); visible: !!cc; x: cc ? cc.x + 4 : 0; y: 8.33; width: cc ? cc.w - 4 : 0; text: (crow.modelData.categories || []).join(", ") }
                    Cell { readonly property var cc: root.col("COMPANY"); visible: !!cc; x: cc ? cc.x + 4 : 0; y: 8.33; width: cc ? cc.w - 4 : 0; text: crow.modelData.company }
                    Cell { readonly property var cc: root.col("OFFICE_LOCATION"); visible: !!cc; x: cc ? cc.x + 4 : 0; y: 8.33; width: cc ? cc.w - 4 : 0; text: crow.modelData.office_location }
                    HoverHandler { id: rh }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.email ? ", " + modelData.email : "")
                }
            }
        }

        // Empty: Teams' illustration and line (Add new contact on All
        // contacts); a search with no match: "We didn't find anyone that
        // matches your search" and "Try a different keyword".
        Column {
            visible: !root.busy && !root.data_.error && root.shown.length === 0
            anchors.centerIn: parent; anchors.verticalCenterOffset: 30
            spacing: 16
            readonly property bool searching: root.keyword.trim().length > 0 && root.inView.length > 0
            Image {
                visible: parent.searching
                anchors.horizontalCenter: parent.horizontalCenter
                width: 170; height: 140; fillMode: Image.PreserveAspectFit
                source: "../assets/illustrations/no-matches.svg"
            }
            Rectangle {
                visible: !parent.searching
                anchors.horizontalCenter: parent.horizontalCenter
                width: 150; height: 150; radius: 24
                color: theme.brandTint
                FluentIcon { anchors.centerIn: parent; name: root.view === "favorites" ? "star-20" : "book-contacts-32"; size: 96; color: theme.brand }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.searching ? qsTr("We didn't find anyone that matches your search")
                    : root.view === "favorites" ? qsTr("People you favorite will show up here")
                    : root.view === "all" ? qsTr("You haven't added any contacts yet") : qsTr("Your category folder is empty")
                font.family: theme.font; font.pixelSize: theme.base + 1; font.weight: Font.DemiBold; color: theme.text
            }
            Text {
                visible: parent.searching
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Try a different keyword")
                font.family: theme.font; font.pixelSize: theme.base + 1; color: theme.text
            }
            Rectangle {
                id: hcFill3
                visible: root.view === "all" && !parent.searching
                anchors.horizontalCenter: parent.horizontalCenter
                width: addRow.implicitWidth + 24; height: 32; radius: theme.radius
                color: anh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
                Row {
                    id: addRow
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "person-add-20"; size: 20; color: theme.onFill(hcFill3, theme.textStrong) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add new contact"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill3, theme.text) }
                }
                HoverHandler { id: anh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: addDialog.start() }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Add new contact")
            }
        }
        Text {
            visible: !!root.data_.error
            anchors.centerIn: parent
            text: root.data_.error || ""
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        BusyIndicator { anchors.centerIn: parent; running: root.busy && root.all.length === 0; visible: running }
    }

    // Add category ▸: Teams' flyout beside the menu — your categories (a
    // check on the contact's own), then "Create new category" with "Type a
    // category name" and "Custom categories help you organize your
    // contacts. These are only visible to you."
    Popup {
        id: catFlyout
        property var contact: null
        property var menu: null
        function done() { close(); if (menu) menu.close() }
        width: 336; padding: 12
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
        onOpened: catName.text = ""
        contentItem: Column {
            spacing: 6
            Repeater {
                model: root.categories
                Rectangle {
                    id: catRow
                    required property var modelData
                    readonly property bool on: !!catFlyout.contact && (catFlyout.contact.categories || []).indexOf(modelData.name) >= 0
                    width: 312; height: 32; radius: 4
                    color: crh.hovered ? theme.rowHover : "transparent"
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: root.catColor(catRow.modelData.color) }
                    Text { x: 30; anchors.verticalCenter: parent.verticalCenter; text: catRow.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    FluentIcon { visible: catRow.on; x: parent.width - 22; anchors.verticalCenter: parent.verticalCenter; name: "checkmark-16"; size: 16; color: theme.textStrong }
                    HoverHandler { id: crh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.op("category", catFlyout.contact, { name: catRow.modelData.name, color: catRow.modelData.color, on: !catRow.on }); catFlyout.done() } }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: catRow.modelData.name
                    Accessible.checked: catRow.on
                }
            }
            Text { text: qsTr("Create new category"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
            Rectangle {
                width: 312; height: 32; radius: 4
                color: theme.pick("#F5F5F5", "#1F1F1F", "#000000")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: catName.activeFocus ? 2 : 1; color: catName.activeFocus ? theme.brand : theme.textSecondary }
                TextInput {
                    id: catName
                    x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                    font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                    maximumLength: 255
                    Text { visible: !catName.text; text: qsTr("Type a category name"); color: theme.textSecondary; font: catName.font }
                    Keys.onReturnPressed: create()
                    Keys.onEnterPressed: create()
                    function create() {
                        if (!text.trim() || !catFlyout.contact) return
                        root.op("category", catFlyout.contact, { name: text.trim(), color: "", on: true })
                        catFlyout.done()
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Type a category name")
                }
            }
            Text {
                width: 312; wrapMode: Text.Wrap
                text: qsTr("Custom categories help you organize your contacts. These are only visible to you.")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
        }
    }

    // ---- Add to contacts (Teams' people picker), then Add contact ------
    // "Add to contacts" (480 wide, radius 8, padding 25): the picker
    // ("Type a name or number", #F0F0F0); typing lists the number the text
    // reads as ("+1 555-123-4567", External) and the directory's people
    // (name with the typed words bold, their address's name in capitals,
    // Guest); picking one shows them, and Add opens Add contact with what
    // the directory knows (name and email, not editable), Phone and
    // Company to fill in; a number: First name (required) and the rest.
    Popup {
        id: addDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 480; padding: 0; modal: true
        property var picked: null
        property var results: []
        property var number: null
        property int highlighted: 0
        readonly property string tag: "peoplepick" + Math.floor(Math.random() * 1e9).toString(36)
        function start() { picked = null; results = []; number = null; pickInput.text = ""; open(); pickInput.forceActiveFocus() }
        readonly property var options: (number ? [{ phone: number }] : []).concat(results)
        Timer { id: pickDebounce; interval: 300; onTriggered: backend.eventsRequest("contactsSearch", addDialog.tag, JSON.stringify({ q: pickInput.text })) }
        Connections {
            target: backend
            function onEventsReply(id, json) {
                if (id !== addDialog.tag) return
                let v = {}
                try { v = JSON.parse(json) } catch (e) {}
                if (v.q !== pickInput.text) return
                addDialog.results = v.people || []
                addDialog.number = v.number || null
                addDialog.highlighted = 0
            }
        }
        function choose(o) { picked = o.phone ? { phone: o.phone } : o; results = []; number = null }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Item {
            implicitHeight: addCol.implicitHeight + 50
            Column {
                id: addCol
                x: 25; y: 25; width: 431; spacing: 8
                Text { height: 36; text: qsTr("Add to contacts"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
                Rectangle {
                    visible: !addDialog.picked
                    width: 431; height: 33; radius: 4
                    color: theme.pick("#F0F0F0", "#1F1F1F", "#000000")
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: pickInput.activeFocus ? 2 : 0.67; color: pickInput.activeFocus ? theme.brand : theme.textSecondary }
                    TextInput {
                        id: pickInput
                        x: 12; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                        font.family: theme.font; font.pixelSize: 14; color: theme.text; clip: true
                        onTextChanged: { if (text.trim()) pickDebounce.restart(); else { addDialog.results = []; addDialog.number = null } }
                        Keys.onDownPressed: addDialog.highlighted = Math.min(addDialog.options.length - 1, addDialog.highlighted + 1)
                        Keys.onUpPressed: addDialog.highlighted = Math.max(0, addDialog.highlighted - 1)
                        Keys.onReturnPressed: if (addDialog.options.length) addDialog.choose(addDialog.options[addDialog.highlighted])
                        Text { visible: !pickInput.text; text: qsTr("Type a name or number"); color: theme.textSecondary; font: pickInput.font }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Type a name or number")
                    }
                    FluentIcon { visible: pickInput.text.length > 0; x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-16"; size: 16; color: theme.textSecondary }
                }
                // The picked person or number.
                Item {
                    visible: !!addDialog.picked
                    width: 431; height: 48
                    Avatar {
                        visible: !!addDialog.picked && !addDialog.picked.phone
                        y: 0; size: 32
                        name: addDialog.picked ? addDialog.picked.name || "" : ""; photoId: addDialog.picked ? addDialog.picked.mri || "" : ""
                    }
                    Rectangle {
                        visible: !!addDialog.picked && !!addDialog.picked.phone
                        width: 32; height: 32; radius: 16; color: "#4CCFCF"
                        FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: "white" }
                    }
                    Column {
                        x: 42; anchors.verticalCenter: parent.verticalCenter
                        Text { text: addDialog.picked ? (addDialog.picked.phone || addDialog.picked.name || "") : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                        Text { visible: !!addDialog.picked && !addDialog.picked.phone; text: addDialog.picked ? addDialog.picked.mail || "" : ""; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    }
                }
                Row {
                    layoutDirection: Qt.RightToLeft; width: 431; spacing: 8; topPadding: 4
                    DialogButton {
                        label: qsTr("Add"); primary: true
                        enabled_: !!addDialog.picked || addDialog.options.length > 0
                        onClicked: {
                            const p = addDialog.picked || (addDialog.options.length ? addDialog.options[addDialog.highlighted] : null)
                            if (!p) return
                            addDialog.close()
                            formDialog.start(p.phone ? { phone: p.phone } : p)
                        }
                    }
                    DialogButton { label: qsTr("Cancel"); onClicked: addDialog.close() }
                }
            }
            // The suggestions under the box (409 wide rows of 50 / 52, a
            // 32 px picture, the name 14 px with the typed words bold, the
            // second line 12 px #616161).
            FluentSurface {
                visible: !addDialog.picked && addDialog.options.length > 0 && pickInput.text.trim().length > 0
                x: 25; y: 25 + 36 + 8 + 33; width: 431; z: 5
                height: Math.min(sugg.contentHeight + 8, 312)
                depth: 8; radius: 4; color: theme.surface
                ListView {
                    id: sugg
                    anchors.fill: parent; anchors.margins: 4
                    clip: true; model: addDialog.options
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: so
                        required property var modelData
                        required property int index
                        width: ListView.view.width; height: modelData.phone ? 50 : 52; radius: 4
                        color: addDialog.highlighted === index || soh.hovered ? theme.rowHover : "transparent"
                        border.width: addDialog.highlighted === index && pickInput.activeFocus ? 2 : 0; border.color: theme.text
                        Rectangle {
                            visible: !!so.modelData.phone
                            x: 12; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 16; color: "#4CCFCF"
                            FluentIcon { anchors.centerIn: parent; name: "person-20"; size: 20; color: "white" }
                        }
                        Avatar { visible: !so.modelData.phone; x: 12; anchors.verticalCenter: parent.verticalCenter; size: 32; name: so.modelData.name || ""; photoId: so.modelData.mri || "" }
                        Row {
                            x: 60; y: so.modelData.phone ? 15 : 7; spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.StyledText
                                text: so.modelData.phone ? so.modelData.phone : root.bolded(so.modelData.name || "", pickInput.text)
                                font.family: theme.font; font.pixelSize: 14; color: theme.textStrong
                            }
                            Rectangle {
                                visible: !!so.modelData.phone || !!so.modelData.guest
                                anchors.verticalCenter: parent.verticalCenter
                                width: badgeRow.implicitWidth + 8; height: 24; radius: 4
                                color: so.modelData.phone ? "#616161" : "#EBEBEB"
                                Row {
                                    id: badgeRow
                                    x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "person-20"; size: 16; color: so.modelData.phone ? "white" : "#616161" }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: so.modelData.phone ? qsTr("External") : qsTr("Guest"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: so.modelData.phone ? "white" : "#616161" }
                                }
                            }
                        }
                        Text {
                            visible: !so.modelData.phone
                            x: 60; y: 28; width: parent.width - 72; elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: root.boldedPrefix(so.modelData.detail || "", pickInput.text)
                            font.family: theme.font; font.pixelSize: 12; color: theme.textSecondary
                        }
                        HoverHandler { id: soh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: addDialog.choose(so.modelData) }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: so.modelData.phone ? so.modelData.phone + ", " + qsTr("External") : (so.modelData.name || "")
                    }
                }
            }
        }
    }
    /// The second line: the typed text in bold when the line starts with
    /// all of it (Teams: "OST" marks OST-TEST2, "OST Test 2" marks nothing).
    function boldedPrefix(t, q) {
        const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const k = String(q || "").trim()
        return k && String(t).toLowerCase().indexOf(k.toLowerCase()) === 0 ? "<b>" + esc(String(t).slice(0, k.length)) + "</b>" + esc(String(t).slice(k.length)) : esc(t)
    }
    /// The typed words in bold where a name starts with them (as Teams'
    /// picker marks them).
    function bolded(t, q) {
        const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const words = String(q || "").trim().toLowerCase().split(/\s+/).filter(w => !!w)
        if (!words.length) return esc(t)
        return String(t).split(/(\s+|-)/).map(part => {
            const w = words.find(x => part.toLowerCase().indexOf(x) === 0)
            return w ? "<b>" + esc(part.slice(0, w.length)) + "</b>" + esc(part.slice(w.length)) : esc(part)
        }).join("")
    }

    // Add contact / Edit contact (320 wide, padding 33; title 20/600;
    // labels 14 px over 255 x 32 fields, #F5F5F5 to fill in, those the
    // directory knows bordered and greyed; Cancel and Save 122 wide).
    Popup {
        id: formDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 320; padding: 0; modal: true
        property bool editing: false
        property var person: null
        property var contact: null
        readonly property bool directory: editing ? !!(contact && contact.mri) : !!(person && person.mri)
        readonly property bool phoneFixed: !editing && !!(person && person.phone) || editing && directory
        function start(p) {
            editing = false; contact = null; person = p
            fFirst.text = p.given || (p.mri ? p.name || "" : ""); fLast.text = p.surname || ""; fEmail.text = p.mail || ""
            fPhone.text = p.phone || ""; fCompany.text = ""
            original = ""
            open()
            if (p.mri) fPhone.forceActiveFocus(); else fFirst.forceActiveFocus()
        }
        function startEdit(c) {
            editing = true; contact = c; person = null
            fFirst.text = c.first || (c.mri ? c.name : ""); fLast.text = c.last || ""; fEmail.text = c.email || ""
            fPhone.text = c.phone || c.mobile || ""; fCompany.text = c.company || ""
            original = snapshot()
            open()
            fCompany.forceActiveFocus()
        }
        property string original: ""
        function snapshot() { return [fFirst.text, fLast.text, fEmail.text, fPhone.text, fCompany.text].join("\n") }
        readonly property bool canSave: fFirst.text.trim().length > 0 && (editing ? snapshot() !== original : true)
        background: FluentSurface { depth: 64; radius: 4; color: theme.surface }
        contentItem: Column {
            padding: 33; spacing: 0
            Text { height: 42; text: formDialog.editing ? qsTr("Edit contact") : qsTr("Add contact"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            FormField { id: fFirst; label: qsTr("First name"); required: true; fixed: formDialog.directory }
            FormField { id: fLast; label: qsTr("Last name"); fixed: formDialog.directory }
            FormField { id: fEmail; label: qsTr("Email"); fixed: formDialog.directory }
            FormField { id: fPhone; label: qsTr("Phone"); fixed: formDialog.phoneFixed }
            FormField { id: fCompany; label: qsTr("Company") }
            Item { width: 1; height: 18 }
            Row {
                spacing: 10
                DialogButton { label: qsTr("Cancel"); width: 122; onClicked: formDialog.close() }
                DialogButton {
                    label: qsTr("Save"); primary: true; width: 122; enabled_: formDialog.canSave
                    onClicked: {
                        if (!formDialog.canSave) return
                        const form = { first: fFirst.text, last: fLast.text, email: fEmail.text, phone: fPhone.text, company: fCompany.text }
                        if (formDialog.editing) root.op("edit", formDialog.contact, { form: form })
                        else root.change("add", JSON.stringify({ form: Object.assign({ person: formDialog.person && !formDialog.person.phone ? formDialog.person : {} }, form) }))
                        formDialog.close()
                    }
                }
            }
        }
    }
    QtObject { id: editDialog; function start(c) { formDialog.startEdit(c) } }

    // Delete contact: "Do you want to delete the contact <b>name</b>?"
    Popup {
        id: deleteDialog
        property var contact: null
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 400; padding: 0; modal: true
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Column {
            padding: 33; spacing: 20
            Text { text: qsTr("Delete contact", "jana:k7je5fz68"); font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: theme.text }
            Text {
                width: 334; wrapMode: Text.Wrap; textFormat: Text.StyledText
                text: qsTr("Do you want to delete the contact %1?").arg("<b>" + String(deleteDialog.contact ? deleteDialog.contact.name : "").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>")
                font.family: theme.font; font.pixelSize: 14; color: theme.text
            }
            Row {
                spacing: 8; layoutDirection: Qt.RightToLeft; width: 334
                DialogButton { label: qsTr("Delete"); primary: true; width: 96; onClicked: { root.remove(deleteDialog.contact.id); deleteDialog.close() } }
                DialogButton { label: qsTr("Cancel"); width: 96; onClicked: deleteDialog.close() }
            }
        }
    }

    component NavRow: Rectangle {
        id: nr
        property string label
        property string icon
        property bool selected
        property string chevron: ""
        property color dot: "transparent"
        property int indent: 0
        property int count: -1
        signal clicked()
        width: parent ? parent.width : 300; height: 36; radius: theme.radius
        color: selected ? theme.hc(theme.surface, theme.hcHighlight) : nh.hovered ? theme.rowHover : "transparent"
        FluentIcon {
            visible: nr.chevron !== ""
            x: 6; anchors.verticalCenter: parent.verticalCenter
            name: nr.chevron === "right" ? "chevron-right-12" : "chevron-down-12"; size: 12; color: theme.onFill(nr, theme.textStrong)
        }
        FluentIcon {
            visible: !!nr.icon
            x: 24 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            name: nr.icon || "people-20"; size: 20; color: theme.onFill(nr, nr.selected ? theme.brand : theme.textStrong)
        }
        Rectangle {
            visible: !nr.icon
            x: 28 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6; color: nr.dot
        }
        Text {
            x: 50 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 40; elide: Text.ElideRight
            text: nr.label; font.family: theme.font; font.pixelSize: 14
            color: theme.onFill(nr, nr.chevron ? theme.textStrong : theme.text)
        }
        Text {
            visible: nr.count >= 0
            x: 316; width: 20; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
            text: nr.count; font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(nr, theme.brand)
        }
        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component RowTool: Rectangle {
        id: rt
        property string icon
        property string tip
        property bool active: false
        property bool usable: true
        signal clicked()
        width: 32; height: 31.33; radius: 4
        opacity: rt.usable ? 1 : 0.4
        color: rth.hovered && rt.usable || rt.active ? theme.hc(theme.pick("#F5F5F5", "#3D3D3D", "#000000"), theme.hcHighlight) : "transparent"
        FluentIcon { anchors.centerIn: parent; name: rt.icon; size: 20; color: rt.active ? theme.brand : theme.onFill(rt, theme.textStrong) }
        HoverHandler { id: rth; cursorShape: rt.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: rt.usable; onTapped: rt.clicked() }
        ToolTip.visible: rth.hovered; ToolTip.delay: 500; ToolTip.text: rt.tip
        Accessible.role: Accessible.Button
        Accessible.name: rt.tip
    }
    component Cell: Item {
        property alias text: t.text
        height: 52
        Text { id: t; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 4; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: 12; color: theme.text }
    }
    component DialogButton: Rectangle {
        id: db
        property string label
        property bool primary: false
        property bool enabled_: true
        signal clicked()
        width: 96; height: 31.33; radius: 4
        color: db.primary ? (db.enabled_ ? (dbh.hovered ? theme.brandHover : theme.brandFill) : theme.pick("#F0F0F0", "#2E2E2E", "#000000"))
                          : (dbh.hovered ? theme.rowHover : theme.surface)
        border.width: db.primary ? 0 : 0.67; border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF")
        Text { anchors.centerIn: parent; text: db.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
               color: db.primary ? (db.enabled_ ? theme.onFill(db, "white") : theme.disabled) : theme.text }
        HoverHandler { id: dbh; cursorShape: db.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: db.enabled_; onTapped: db.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: db.label
    }
    // A form field: its label (14 px, a red * when required) over a
    // 255 x 32 box; the directory's values bordered and greyed, not
    // editable.
    component FormField: Column {
        id: ff
        property string label
        property bool required: false
        property bool fixed: false
        property alias text: fin.text
        function forceActiveFocus() { fin.forceActiveFocus() }
        width: 255; spacing: 2; bottomPadding: 12
        Row {
            spacing: 2
            Text { height: 24; verticalAlignment: Text.AlignVCenter; text: ff.label; font.family: theme.font; font.pixelSize: 14; color: theme.text }
            Text { visible: ff.required; height: 24; verticalAlignment: Text.AlignVCenter; text: "*"; font.family: theme.font; font.pixelSize: 14; color: theme.pick("#D13438", "#F1707B", "#FFFF00") }
        }
        Rectangle {
            width: 255; height: 32; radius: 4
            color: ff.fixed ? "transparent" : theme.pick("#F5F5F5", "#1F1F1F", "#000000")
            border.width: ff.fixed || !fin.activeFocus ? 0.67 : 0
            border.color: ff.fixed ? theme.pick("#D1D1D1", "#666666", "#FFFFFF") : fin.activeFocus ? "transparent" : theme.pick("#D1D1D1", "#666666", "#FFFFFF")
            Rectangle { visible: !ff.fixed; anchors.bottom: parent.bottom; width: parent.width; height: fin.activeFocus ? 2 : 0.67; color: fin.activeFocus ? theme.brand : theme.pick("#616161", "#ADADAD", "#FFFFFF") }
            TextInput {
                id: fin
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                readOnly: ff.fixed
                font.family: theme.font; font.pixelSize: 14; color: ff.fixed ? theme.disabled : theme.text; clip: true
                selectByMouse: true
                Accessible.role: Accessible.EditableText
                Accessible.name: ff.label
            }
        }
    }

    // Test harness hooks
    function addForTest(person) { root.change("add", JSON.stringify({ form: { person: person, first: person.given || "", last: person.surname || "", email: person.mail || "" } })) }
    function find(name) { return root.all.find(c => c.name === name) }
    function stateForTest() { return { sort: sortField + " " + sortDirection, keyword: keyword, shown: shown.map(c => c.name), columns: columns.map(c => c.id + "@" + Math.round(c.x) + "+" + Math.round(c.w)) } }
    function setKeywordForTest(k) { findInput.text = k; root.keyword = k }
    function openForTest(which) {
        if (which === "sort") sortMenu.open()
        else if (which === "columns") colMenu.open()
        else if (which === "add") addDialog.start()
        else if (which === "close") { sortMenu.close(); colMenu.close(); addDialog.close(); formDialog.close() }
    }
    function pickerTypeForTest(t) { pickInput.text = t }
    function pickerStateForTest() { return { options: addDialog.options.map(o => o.phone ? o.phone + " [External]" : o.name + " / " + o.detail + (o.guest ? " [Guest]" : "")), picked: addDialog.picked } }
    function pickForTest(i) { addDialog.choose(addDialog.options[i]) }
    function addPressForTest() { const p = addDialog.picked; addDialog.close(); formDialog.start(p.phone ? { phone: p.phone } : p) }
    function formForTest() { return { title: formDialog.editing ? "Edit contact" : "Add contact", first: fFirst.text, last: fLast.text, email: fEmail.text, phone: fPhone.text, directory: formDialog.directory, canSave: formDialog.canSave } }
    function editForTest(c) { formDialog.startEdit(c) }
    function setCompanyForTest(t) { fCompany.text = t }
    function saveFormForTest() {
        const form = { first: fFirst.text, last: fLast.text, email: fEmail.text, phone: fPhone.text, company: fCompany.text }
        if (formDialog.editing) root.op("edit", formDialog.contact, { form: form })
        else root.change("add", JSON.stringify({ form: Object.assign({ person: formDialog.person && !formDialog.person.phone ? formDialog.person : {} }, form) }))
        formDialog.close()
    }
}
