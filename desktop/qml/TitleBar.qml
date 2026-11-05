import QtQuick

// Top bar: app launcher, sidebar toggle, search, more, profile.
Rectangle {
    id: root
    property string userName
    /// Suggestions while searching: chats from the list, people from the
    /// directory (set by Main).
    property var chats: []
    property var people: []
    signal signOut()
    signal searchPeople(string query)
    signal openChat(string id, string name)
    signal openPerson(string oid, string name)
    function focusSearch() { field.forceActiveFocus() }
    // Test hook: type into search and keep the suggestions open offscreen,
    // where the window never has focus.
    property bool keepSuggestionsOpen: false
    function typeSearch(t) { keepSuggestionsOpen = true; field.text = t; peopleDebounce.restart() }
    color: theme.chrome
    height: theme.titleBarHeight

    component BarButton: Rectangle {
        property alias icon: glyph.name
        width: 32; height: 32; radius: theme.radius
        color: hover.hovered ? theme.hover : "transparent"
        HoverHandler { id: hover }
        FluentIcon { id: glyph; anchors.centerIn: parent; size: 20 }
    }

    BarButton { icon: "waffle-20"; x: 18; anchors.verticalCenter: parent.verticalCenter }
    BarButton { icon: "panel-left-20"; x: 70; anchors.verticalCenter: parent.verticalCenter }

    Rectangle {
        id: search
        x: 327; width: Math.min(623, parent.width - 327 - 140)
        height: 32; radius: theme.radius
        anchors.verticalCenter: parent.verticalCenter
        color: theme.searchFill
        border.color: field.activeFocus ? theme.brand : theme.dividerSoft
        FluentIcon { name: "search-20"; size: 16; x: 28; anchors.verticalCenter: parent.verticalCenter; color: theme.textSecondary }
        TextInput {
            id: field
            x: 59; width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            onTextEdited: peopleDebounce.restart()
            Keys.onEscapePressed: { text = ""; focus = false }
            Keys.onReturnPressed: {
                const first = suggestions.items[0]
                if (first) suggestions.choose(first)
            }
            Text {
                visible: !field.text && !field.activeFocus
                text: "Press Ctrl+Alt+G to go right to a chat or channel"
                color: theme.textSecondary
                font: field.font
            }
        }
    }

    Timer { id: peopleDebounce; interval: 300; onTriggered: root.searchPeople(field.text) }

    // Search suggestions: matching chats, then people, as Teams lists them.
    Rectangle {
        id: suggestions
        readonly property string q: field.text.trim().toLowerCase()
        readonly property var items: {
            if (q.length === 0) return []
            const chats = root.chats.filter(c => (c.name || "").toLowerCase().indexOf(q) >= 0)
                .slice(0, 5).map(c => ({ kind: "chat", id: c.id, name: c.name, sub: "Chat" }))
            const chatNames = chats.map(c => c.name)
            const people = root.people.filter(p => chatNames.indexOf(p.name) < 0 || p.mail)
                .slice(0, 6).map(p => ({ kind: "person", id: p.id, name: p.name, sub: p.mail || p.job_title }))
            return chats.concat(people)
        }
        function choose(item) {
            if (item.kind === "chat") root.openChat(item.id, item.name)
            else root.openPerson(item.id, item.name)
            field.text = ""; field.focus = false
        }
        visible: (field.activeFocus || root.keepSuggestionsOpen) && q.length > 0
        z: 100
        x: search.x; y: search.y + search.height + 4
        width: search.width; height: Math.max(48, col.implicitHeight + 8)
        radius: 8
        color: theme.surface
        border.color: theme.dividerSoft
        Column {
            id: col
            x: 0; y: 4; width: parent.width
            Repeater {
                model: suggestions.items
                Rectangle {
                    id: item
                    required property var modelData
                    width: col.width; height: 44
                    color: itemHover.hovered ? theme.pane : "transparent"
                    Avatar { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 28; name: item.modelData.name }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        Text { text: item.modelData.name; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                        Text { text: item.modelData.sub || ""; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                    }
                    HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: suggestions.choose(item.modelData) }
                }
            }
        }
        Text {
            visible: suggestions.items.length === 0
            anchors.centerIn: parent
            text: "No matches yet"
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.textSecondary
        }
    }

    BarButton { icon: "more-20"; anchors.right: avatar.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter }
    Avatar {
        id: avatar
        name: root.userName || "?"
        size: 28
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            width: 10; height: 10; radius: 5
            color: "#6BB700"; border.color: theme.chrome; border.width: 2
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: -2; anchors.bottomMargin: -2
        }
        TapHandler { onTapped: menu.visible = !menu.visible }
    }

    // Account flyout, as in Teams: name, status, and sign out.
    Rectangle {
        id: menu
        visible: false
        z: 100
        width: 280; height: menuCol.implicitHeight + 24
        anchors.right: parent.right; anchors.rightMargin: 8
        y: parent.height + 4
        radius: 8
        color: theme.surface
        border.color: theme.dividerSoft
        Column {
            id: menuCol
            x: 16; y: 12; width: parent.width - 32
            spacing: 12
            Row {
                spacing: 12
                Avatar { name: root.userName || "?"; size: 48 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: root.userName; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                    Text { text: "Available"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                }
            }
            Rectangle { width: parent.width; height: 1; color: theme.dividerSoft }
            Text {
                text: "Sign out"
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                TapHandler { onTapped: { menu.visible = false; root.signOut() } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }
}
