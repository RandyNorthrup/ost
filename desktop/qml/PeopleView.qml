import QtQuick
import QtQuick.Controls.Basic

// The People app, laid out as Teams': a pane with "People" and Add
// contact, All contacts, Favorites and Categories (or "When you create
// categories, they will appear here."); the content has the view's title
// and your contacts, or "You haven't added any contacts yet" with Add new
// contact. Contacts are your Outlook contacts.
Item {
    id: root
    /// The backend's contacts_json, parsed: {contacts, categories}.
    property var data_: ({})
    property bool busy: false
    signal load()
    signal add(string contactJson)
    signal favorite(string id, bool on)
    signal remove(string id)

    /// "all", "favorites" or "cat:<name>".
    property string view: "all"
    property bool categoriesOpen: true
    readonly property var all: data_.contacts || []
    readonly property var categories: data_.categories || []
    readonly property var shown: view === "favorites" ? all.filter(c => c.favorite)
        : view.indexOf("cat:") === 0 ? all.filter(c => (c.categories || []).indexOf(view.slice(4)) >= 0)
        : all
    readonly property string title: view === "favorites" ? "Favorites" : view.indexOf("cat:") === 0 ? view.slice(4) : "All contacts"
    Component.onCompleted: load()

    // Outlook's category presets as colours.
    function catColor(preset) {
        const map = { preset0: "#E74856", preset1: "#FF8C00", preset2: "#C19C00", preset3: "#FFF100", preset4: "#00CC6A",
                      preset5: "#00B7C3", preset6: "#8E8CD8", preset7: "#0078D4", preset8: "#E3008C", preset9: "#A4262C" }
        return map[preset] || theme.textSecondary
    }

    Rectangle { anchors.fill: parent; color: theme.surface }

    // The pane
    Rectangle {
        id: pane
        width: 320; height: parent.height
        color: theme.pane
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }
        Text { x: 20; y: 18; text: "People"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Rectangle {
            x: parent.width - 48; y: 12; width: 32; height: 32; radius: theme.radius
            color: ah.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: "person-add-20"; size: 20; color: theme.textStrong }
            HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: addDialog.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Add contact"
        }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }
        Column {
            x: 4; y: 72; width: parent.width - 8
            Repeater {
                model: [
                    { key: "all", label: "All contacts", icon: "people-20", iconOn: "people-20-filled" },
                    { key: "favorites", label: "Favorites", icon: "star-20", iconOn: "star-20" }
                ]
                NavRow {
                    required property var modelData
                    label: modelData.label
                    icon: root.view === modelData.key ? modelData.iconOn : modelData.icon
                    selected: root.view === modelData.key
                    onClicked: root.view = modelData.key
                }
            }
            NavRow {
                label: "Categories"; icon: "tag-20"; selected: false
                chevron: root.categoriesOpen ? "down" : "right"
                onClicked: root.categoriesOpen = !root.categoriesOpen
            }
            Text {
                visible: root.categoriesOpen && root.categories.length === 0
                x: 28; width: parent.width - 40; wrapMode: Text.Wrap
                topPadding: 4
                text: "When you create categories, they will appear here."
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
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
        anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Text { x: 20; y: 18; text: root.title; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
        Rectangle { y: 59; width: parent.width; height: 1; color: theme.dividerSoft }

        // The list: Name, Email, Phone, Company.
        Item {
            id: table
            visible: root.shown.length > 0
            anchors { fill: parent; topMargin: 60 }
            readonly property real wName: Math.max(220, width * 0.3)
            Row {
                id: head
                x: 20; height: 40
                HeadCell { width: table.wName; label: "Name" }
                HeadCell { width: Math.max(200, table.width * 0.28); label: "Email" }
                HeadCell { width: 160; label: "Phone" }
                HeadCell { width: 180; label: "Company" }
            }
            ListView {
                anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                clip: true
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: crow
                    required property var modelData
                    width: ListView.view.width; height: 52
                    color: rh.hovered ? theme.rowHover : "transparent"
                    Rectangle { x: 20; width: parent.width - 40; height: 1; color: theme.dividerSoft }
                    Row {
                        x: 20; height: parent.height
                        Item {
                            width: table.wName; height: parent.height
                            Avatar { anchors.verticalCenter: parent.verticalCenter; size: 32; name: crow.modelData.name }
                            Column {
                                x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56
                                Row {
                                    spacing: 6
                                    Text { text: crow.modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text; elide: Text.ElideRight }
                                    FluentIcon { visible: crow.modelData.favorite; anchors.verticalCenter: parent.verticalCenter; name: "star-20"; size: 14; color: theme.handRaised }
                                }
                                Text { visible: !!crow.modelData.job_title; text: crow.modelData.job_title; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary; elide: Text.ElideRight; width: parent.width }
                            }
                        }
                        Cell { width: Math.max(200, table.width * 0.28); text: crow.modelData.email }
                        Cell { width: 160; text: crow.modelData.mobile || crow.modelData.phone }
                        Cell { width: 180; text: crow.modelData.company }
                    }
                    Rectangle {
                        visible: rh.hovered || rowMenu.visible
                        anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: theme.radius
                        color: mh.hovered ? theme.pane : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: theme.textStrong }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: rowMenu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options for " + crow.modelData.name
                        MenuPopup {
                            id: rowMenu
                            x: -200; y: parent.height; width: 230
                            items: (crow.modelData.email ? [{ label: "Send email", icon: "mail-20" }, { label: "Copy email", icon: "copy-20" }] : [])
                                .concat([{ label: crow.modelData.favorite ? "Remove from favorites" : "Add to favorites", icon: "star-20" },
                                         { separator: true }, { label: "Delete", icon: "delete-20" }])
                            onPicked: i => {
                                const l = items[i].label
                                if (l === "Send email") Qt.openUrlExternally("mailto:" + encodeURIComponent(crow.modelData.email))
                                else if (l === "Copy email") { copier.text = crow.modelData.email; copier.selectAll(); copier.copy() }
                                else if (l === "Add to favorites") root.favorite(crow.modelData.id, true)
                                else if (l === "Remove from favorites") root.favorite(crow.modelData.id, false)
                                else if (l === "Delete") { deleteDialog.contact = crow.modelData; deleteDialog.open() }
                            }
                        }
                    }
                    HoverHandler { id: rh }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (modelData.email ? ", " + modelData.email : "")
                }
            }
        }

        // Empty: Teams' notebook illustration, the line and Add new contact.
        Column {
            visible: !root.busy && !root.data_.error && root.shown.length === 0
            anchors.centerIn: parent; anchors.verticalCenterOffset: 30
            spacing: 16
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 150; height: 150; radius: 24
                color: theme.brandTint
                FluentIcon { anchors.centerIn: parent; name: "book-contacts-32"; size: 96; color: theme.brand }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.view === "favorites" ? "Your favorite contacts will show up here"
                    : root.view === "all" ? "You haven't added any contacts yet" : "No contacts in this category"
                font.family: theme.font; font.pixelSize: theme.base + 1; font.weight: Font.DemiBold; color: theme.text
            }
            Rectangle {
                visible: root.view === "all"
                anchors.horizontalCenter: parent.horizontalCenter
                width: addRow.implicitWidth + 24; height: 32; radius: theme.radius
                color: anh.hovered ? theme.rowHover : theme.input; border.color: theme.stroke
                Row {
                    id: addRow
                    anchors.centerIn: parent; spacing: 8
                    FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "person-add-20"; size: 20; color: theme.textStrong }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Add new contact"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                }
                HoverHandler { id: anh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: addDialog.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Add new contact"
            }
        }
        Text {
            visible: !!root.data_.error
            anchors.centerIn: parent
            text: root.data_.error || ""
            font.family: theme.font; font.pixelSize: theme.base; color: theme.danger
        }
        BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: root.busy }
    }

    TextEdit { id: copier; visible: false }

    // Add new contact
    Popup {
        id: addDialog
        anchors.centerIn: parent
        width: 440; padding: 24; modal: true
        onOpened: { for (const f of [first, last, email, mobile, company, job]) f.text = ""; first.forceActiveFocus() }
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 12
            Text { text: "Add new contact"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Row {
                spacing: 12
                Field { id: first; width: 190; hint: "First name" }
                Field { id: last; width: 190; hint: "Last name" }
            }
            Field { id: email; width: 392; hint: "Email" }
            Field { id: mobile; width: 392; hint: "Mobile phone" }
            Field { id: company; width: 392; hint: "Company" }
            Field { id: job; width: 392; hint: "Job title" }
            Row {
                spacing: 8
                layoutDirection: Qt.RightToLeft
                width: 392
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    opacity: (first.text + last.text + email.text).trim() ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: "Save"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler {
                        onTapped: {
                            if (!(first.text + last.text + email.text).trim()) return
                            root.add(JSON.stringify({ first: first.text, last: last.text, email: email.text, mobile: mobile.text, company: company.text, job_title: job.text }))
                            addDialog.close()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Save"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: addDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
    }

    Popup {
        id: deleteDialog
        property var contact: null
        anchors.centerIn: parent
        width: 400; padding: 24; modal: true
        background: Rectangle { radius: 8; color: theme.menu; border.color: theme.dividerSoft }
        contentItem: Column {
            spacing: 16
            Text { text: "Delete contact?"; font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: theme.text }
            Text { width: 352; wrapMode: Text.Wrap; text: (deleteDialog.contact ? deleteDialog.contact.name : "") + " will be removed from your contacts."; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Row {
                spacing: 8; layoutDirection: Qt.RightToLeft; width: 352
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.brandFill
                    Text { anchors.centerIn: parent; text: "Delete"; color: "white"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
                    TapHandler { onTapped: { root.remove(deleteDialog.contact.id); deleteDialog.close() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Delete"
                }
                Rectangle {
                    width: 90; height: 32; radius: theme.radius; color: theme.input; border.color: theme.stroke
                    Text { anchors.centerIn: parent; text: "Cancel"; color: theme.text; font.family: theme.font; font.pixelSize: theme.base }
                    TapHandler { onTapped: deleteDialog.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
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
        signal clicked()
        width: parent ? parent.width : 300; height: 44; radius: theme.radius
        color: selected ? theme.surface : nh.hovered ? theme.rowHover : "transparent"
        FluentIcon {
            visible: nr.chevron !== ""
            x: 6; anchors.verticalCenter: parent.verticalCenter
            name: nr.chevron === "right" ? "chevron-right-12" : "chevron-down-12"; size: 12; color: theme.textStrong
        }
        FluentIcon {
            visible: !!nr.icon
            x: 28 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            name: nr.icon || "people-20"; size: 20; color: nr.selected ? theme.brand : theme.textStrong
        }
        Rectangle {
            visible: !nr.icon
            x: 30 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6; color: nr.dot
        }
        Text {
            x: 58 + nr.indent; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 12; elide: Text.ElideRight
            text: nr.label; font.family: theme.font; font.pixelSize: theme.base + 1
            font.weight: nr.selected ? Font.DemiBold : Font.Normal; color: theme.text
        }
        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nr.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component HeadCell: Item {
        property string label
        height: 40
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
    }
    component Cell: Item {
        property alias text: t.text
        height: 52
        Text { id: t; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 12; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
    }
    component Field: Rectangle {
        property alias text: fi.text
        property string hint
        height: 32; radius: theme.radius
        color: theme.input; border.color: fi.activeFocus ? theme.brand : theme.stroke
        function forceActiveFocus() { fi.forceActiveFocus() }
        TextInput {
            id: fi
            x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base; color: theme.text; clip: true
            Text { visible: !fi.text; text: parent.parent.hint; color: theme.textTertiary; font: fi.font }
            Accessible.name: parent.hint
        }
    }

    // Test harness hooks
    function addForTest(first, last, mail) { root.add(JSON.stringify({ first: first, last: last, email: mail })) }
    function find(name) { return root.all.find(c => c.name === name) }
}
