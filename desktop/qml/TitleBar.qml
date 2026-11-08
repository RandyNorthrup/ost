import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

// Top bar, laid out as Teams desktop's (measured from its DOM at 1x):
// sidebar toggle, back/forward, search, settings-and-more, profile, and the
// window buttons. Empty areas drag the window; double-click maximises.
Rectangle {
    id: root
    property string userName
    /// Your own availability (from the presence service).
    property string presence: "Available"
    /// Suggestions while searching: chats from the list, people from the
    /// directory (set by Main).
    property var chats: []
    property var people: []
    /// History navigation (Main keeps the stack).
    property bool canGoBack: false
    property bool canGoForward: false
    /// Draw our own minimise/maximise/close (frameless window).
    property bool windowButtons: true
    signal signOut()
    signal searchPeople(string query)
    signal openChat(string id, string name)
    signal openPerson(string oid, string name)
    signal goBack()
    signal goForward()
    signal toggleRail()
    signal openSettings()
    signal openShortcuts()
    /// Pin window on top (Ctrl+Shift+T).
    property bool pinned: false
    signal togglePin()
    function focusSearch() { field.forceActiveFocus() }
    function openProfileForTest() { menu.visible = true; statusMenu.open() }
    function profilePageForTest(page) { statusMenu.close(); if (page === "duration") durationPage.start(); if (page === "note") notePage.start(); menu.visible = true; menu.page = page }
    function closeProfileForTest() { menu.visible = false }
    // Test hook: type into search and keep the suggestions open offscreen,
    // where the window never has focus.
    property bool keepSuggestionsOpen: false
    function typeSearch(t) { keepSuggestionsOpen = true; field.text = t; peopleDebounce.restart() }
    color: theme.chrome
    height: theme.titleBarHeight

    // Drag the window by its title bar, as on every desktop app.
    DragHandler {
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: if (active && root.Window.window) root.Window.window.startSystemMove()
    }
    TapHandler {
        onDoubleTapped: {
            const w = root.Window.window
            if (w) w.visibility = w.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
        }
    }
    // Hairline under the bar (rgba(0,0,0,0.06) on the chrome colour).
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.titleHairline }

    component BarButton: Rectangle {
        id: btn
        property alias icon: glyph.name
        property bool usable: true
        signal clicked()
        width: 32; height: 32; radius: theme.radius
        color: hover.hovered && btn.usable ? theme.hover : "transparent"
        HoverHandler { id: hover }
        TapHandler { enabled: btn.usable; onTapped: btn.clicked() }
        FluentIcon { id: glyph; anchors.centerIn: parent; size: 20; color: btn.usable ? theme.icon : theme.disabled }
    }

    BarButton {
        icon: "panel-left-text-20-filled"; x: 18; anchors.verticalCenter: parent.verticalCenter
        Accessible.name: "Collapse app bar"
        onClicked: root.toggleRail()
    }
    BarButton {
        icon: "chevron-left-20"; x: 68; anchors.verticalCenter: parent.verticalCenter
        usable: root.canGoBack
        Accessible.name: "Back"
        onClicked: root.goBack()
    }
    BarButton {
        icon: "chevron-right-20"; x: 100; anchors.verticalCenter: parent.verticalCenter
        usable: root.canGoForward
        Accessible.name: "Forward"
        onClicked: root.goForward()
    }

    // Teams' title-bar search (measured on winpc at 800-1280 px, widths
    // from its responsiveSearchAndSERPWidths config): below 1024 px it
    // starts at x 138 and is at most 468 wide, ending 9 px before
    // "Settings and more"; from 1024 px it is centred in the window, 468
    // wide, then 624 from 1280, 664 from 1440 and 760 from 1680. Below
    // 720 px it folds into a search button until clicked.
    readonly property bool searchFolded: width < 720
    property bool searchOpen: false
    readonly property real searchRoomEnd: moreButton.x - 9
    readonly property real searchWide: width >= 1680 ? 760 : width >= 1440 ? 664 : width >= 1280 ? 624 : 468
    BarButton {
        id: searchButton
        visible: root.searchFolded && !root.searchOpen
        icon: "search-20"; x: 150; anchors.verticalCenter: parent.verticalCenter
        Accessible.name: "Search"
        onClicked: { root.searchOpen = true; field.forceActiveFocus() }
    }
    Rectangle {
        id: search
        visible: !root.searchFolded || root.searchOpen
        x: root.width >= 1024 ? Math.max(138, (root.width - root.searchWide - 15) / 2 + 6) : 138
        width: Math.max(0, Math.min(root.width >= 1024 ? root.searchWide : 468, root.searchRoomEnd - x))
        height: 32; radius: theme.radius
        anchors.verticalCenter: parent.verticalCenter
        color: theme.searchFill
        border.color: field.activeFocus ? theme.brand : "transparent"
        FluentIcon { name: "search-20"; size: 16; x: 25; anchors.verticalCenter: parent.verticalCenter; color: theme.icon }
        TextInput {
            id: field
            // The input starts at 51 px with 8.5 px of padding, as in Teams.
            x: 60; width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            onTextEdited: peopleDebounce.restart()
            Keys.onEscapePressed: { text = ""; focus = false; root.searchOpen = false }
            onActiveFocusChanged: if (!activeFocus && text.length === 0) root.searchOpen = false
            Keys.onReturnPressed: {
                const first = suggestions.items[0]
                if (first) suggestions.choose(first)
            }
            Text {
                visible: !field.text
                text: field.activeFocus ? "Press Ctrl+G to go right to a chat or channel" : "Search (Ctrl+E)"
                color: theme.textTertiary
                font: field.font
            }
            Accessible.name: "Search"
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
        color: theme.menu
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

    BarButton {
        id: moreButton
        icon: "more-20"
        anchors.right: profile.left; anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        Accessible.name: "Settings and more"
        onClicked: moreMenu.visible = !moreMenu.visible
    }
    // "Settings and more", as Teams lists it (the parts OST offers).
    Rectangle {
        id: moreMenu
        visible: false
        z: 100
        width: 360; height: moreCol.implicitHeight + 8
        x: moreButton.x + moreButton.width - width; y: parent.height + 4
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        component MenuRow: Rectangle {
            id: mr
            property string icon
            property string label
            property string keys
            property bool checked: false
            signal picked()
            width: moreCol.width; height: 36; radius: theme.radius
            color: mrh.hovered ? theme.rowHover : "transparent"
            FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: mr.icon; size: 20; color: mr.checked ? theme.brand : theme.textStrong }
            Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: mr.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: mr.keys; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            HoverHandler { id: mrh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { moreMenu.visible = false; mr.picked() } }
            Accessible.role: Accessible.MenuItem
            Accessible.name: mr.label
        }
        Column {
            id: moreCol
            x: 4; y: 4; width: parent.width - 8
            MenuRow { icon: "pin-20"; label: root.pinned ? "Unpin window" : "Pin window on top"; keys: "Ctrl+Shift+T"; checked: root.pinned; onPicked: root.togglePin() }
            MenuRow { icon: "settings-20"; label: "Settings"; keys: "Ctrl+,"; onPicked: root.openSettings() }
            MenuRow { icon: "keyboard-20"; label: "Keyboard shortcuts"; keys: "Ctrl+."; onPicked: root.openShortcuts() }
        }
    }
    // Profile: a 40 px round button around the 28 px avatar.
    Rectangle {
        id: profile
        width: 40; height: 40; radius: 20
        anchors.right: controls.left; anchors.rightMargin: root.windowButtons ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        color: profileHover.hovered ? theme.hover : "transparent"
        HoverHandler { id: profileHover }
        TapHandler { onTapped: menu.visible = !menu.visible }
        Accessible.name: "Your profile"
        Avatar {
            id: avatar
            anchors.centerIn: parent
            name: root.userName || "?"
            photoId: "me"
            size: 28
            presence: root.presence
        }
    }

    // Window buttons: 44 px columns (measured), glyphs drawn like the
    // system ones.
    Row {
        id: controls
        anchors.right: parent.right
        height: parent.height
        width: root.windowButtons ? 132 : 6
        visible: root.windowButtons
        component CaptionButton: Rectangle {
            id: cap
            property string kind
            property bool danger: false
            signal clicked()
            width: 44; height: parent.height
            color: capHover.hovered ? (danger ? "#C42B1C" : theme.hover) : "transparent"
            HoverHandler { id: capHover }
            TapHandler { onTapped: cap.clicked() }
            Canvas {
                id: glyphs
                anchors.centerIn: parent
                width: 12; height: 12
                property color ink: capHover.hovered && cap.danger ? "white" : theme.icon
                property bool maximized: root.Window.window ? root.Window.window.visibility === Window.Maximized : false
                onInkChanged: requestPaint()
                onMaximizedChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.strokeStyle = ink
                    c.lineWidth = 1
                    c.beginPath()
                    if (cap.kind === "min") {
                        c.moveTo(1, 6.5); c.lineTo(11, 6.5)
                    } else if (cap.kind === "max") {
                        if (maximized) {
                            c.roundedRect(1.5, 3.5, 7, 7, 1.5, 1.5)
                            c.moveTo(3.5, 1.5); c.lineTo(9, 1.5)
                            c.arcTo(10.5, 1.5, 10.5, 3, 1.5); c.lineTo(10.5, 8.5)
                        } else {
                            c.roundedRect(1.5, 1.5, 9, 9, 1.5, 1.5)
                        }
                    } else {
                        c.moveTo(1.5, 1.5); c.lineTo(10.5, 10.5)
                        c.moveTo(10.5, 1.5); c.lineTo(1.5, 10.5)
                    }
                    c.stroke()
                }
            }
        }
        CaptionButton {
            kind: "min"; Accessible.name: "Minimize"
            onClicked: if (root.Window.window) root.Window.window.showMinimized()
        }
        CaptionButton {
            kind: "max"; Accessible.name: "Maximize"
            onClicked: {
                const w = root.Window.window
                if (w) w.visibility = w.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
            }
        }
        CaptionButton {
            kind: "close"; danger: true; Accessible.name: "Close"
            onClicked: if (root.Window.window) root.Window.window.close()
        }
    }

    // Account flyout, as Teams lays it out: organisation and Sign out, your
    // picture, name and e-mail, then your status with its choices.
    property string userMail: ""
    property string orgName: ""
    signal setStatus(string status)
    readonly property var statuses: [
        { key: "Available", label: "Available" },
        { key: "Busy", label: "Busy" },
        { key: "DoNotDisturb", label: "Do not disturb" },
        { key: "BeRightBack", label: "Be right back" },
        { key: "Away", label: "Appear away" },
        { key: "Offline", label: "Appear offline" },
    ]
    function statusLabel(p) {
        const k = (p || "Available").toLowerCase()
        const s = statuses.find(s => s.key.toLowerCase() === k)
        return s ? s.label : (k === "inacall" || k === "inameeting" || k === "busyidle" ? "Busy" : k === "availableidle" ? "Available" : p)
    }
    readonly property var presenceInk: ({ available: "#13A10E", away: "#EAA300", busy: "#D13438", dnd: "#D13438", offline: "#616161" })
    function presenceKind(key) {
        const k = key.toLowerCase()
        return k === "available" ? "available" : (k === "away" || k === "berightback") ? "away"
            : k === "busy" ? "busy" : k === "donotdisturb" ? "dnd" : "offline"
    }
    // Your status message (Set status message), as last saved here.
    property string statusNote: ""
    property bool statusNotePinned: false
    Rectangle {
        id: menu
        visible: false
        z: 100
        // Teams' profile flyout: 320 wide; its pages replace one another.
        property string page: "main"
        width: 320; height: (page === "main" ? menuCol.implicitHeight : page === "duration" ? durationPage.implicitHeight : notePage.implicitHeight) + 8
        anchors.right: parent.right; anchors.rightMargin: 8
        y: parent.height + 4
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        onVisibleChanged: if (!visible) { statusMenu.close(); page = "main" }
        Column {
            id: menuCol
            visible: menu.page === "main"
            width: parent.width
            Item {
                width: parent.width; height: 48
                Text {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 120; elide: Text.ElideRight
                    text: root.orgName || "Signed in"
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.text
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    text: "Sign out"
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textStrong
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { menu.visible = false; root.signOut() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Sign out"
                }
            }
            Item {
                width: parent.width; height: 80
                Avatar { x: 18; anchors.verticalCenter: parent.verticalCenter; name: root.userName || "?"; size: 56; photoId: "me" }
                Column {
                    x: 88; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 100
                    Text { width: parent.width; elide: Text.ElideRight; text: root.userName; font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: theme.text }
                    Text { visible: root.userMail.length > 0; width: parent.width; elide: Text.ElideRight; text: root.userMail; font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong }
                    // View account ↗ (opens the Microsoft account page in the browser, as Teams does).
                    Row {
                        spacing: 4
                        Text { text: "View account"; font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "open-16"; size: 12; color: theme.textStrong }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { menu.visible = false; Qt.openUrlExternally("https://myaccount.microsoft.com/") } }
                        Accessible.role: Accessible.Link
                        Accessible.name: "View account"
                    }
                }
            }
            component FlyoutRow: Rectangle {
                id: fr
                property string icon
                property string label
                property bool chevron: true
                property bool active: false
                default property alias lead: frLead.data
                signal clicked()
                width: menuCol.width - 8; x: 4; height: 36; radius: theme.radius
                color: frh.hovered || active ? theme.rowHover : "transparent"
                Item { id: frLead; x: 78; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
                FluentIcon { visible: !!fr.icon; x: 78; anchors.verticalCenter: parent.verticalCenter; name: fr.icon; size: 20; color: theme.textStrong }
                Text { x: 108; anchors.verticalCenter: parent.verticalCenter; text: fr.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                FluentIcon { visible: fr.chevron; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.textStrong }
                HoverHandler { id: frh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: fr.clicked() }
                Accessible.role: Accessible.Button
                Accessible.name: fr.label
            }
            // Your status: the Fluent status menu beside it.
            FlyoutRow {
                id: statusRow
                label: root.statusLabel(root.presence)
                active: statusMenu.opened
                PresenceBadge { anchors.centerIn: parent; total: 16; presence: root.presence || "Available" }
                onClicked: statusMenu.opened ? statusMenu.close() : statusMenu.open()
            }
            FlyoutRow {
                icon: "status-20"; label: "Set status message"
                onClicked: { notePage.start(); menu.page = "note" }
            }
            Item { width: 1; height: 8 }
        }
        // The status choices, as Teams' menu: the statuses, Duration, Reset status.
        MenuPopup {
            id: statusMenu
            x: 72; y: statusRow.y + statusRow.height + 2
            items: root.statuses.map(s => ({ label: s.label, icon: "presence-" + root.presenceKind(s.key) + "-16",
                                               iconColor: root.presenceInk[root.presenceKind(s.key)] }))
                .concat([{ separator: true }, { label: "Duration", icon: "clock-20", chevron: true },
                         { separator: true }, { label: "Reset status", icon: "arrow-reset-20" }])
            onPicked: i => {
                const n = root.statuses.length
                if (i < n) { menu.visible = false; root.setStatus(root.statuses[i].key) }
                else if (i === n + 1) { durationPage.start(); menu.page = "duration" }
                else if (i === n + 3) { menu.visible = false; root.setStatus("Reset") }
            }
        }
        // A Fluent dropdown of the flyout's pages (30 tall, as measured).
        // Teams' "Reset status after" / "Clear status message after" trigger
        // (clearStatusMenuTrigger on a Fluent secondary Button): 288 x 30,
        // NeutralBackground3, no border, 14 px regular text at 12, a 20 px
        // chevron 12 from the right; pressed NeutralBackground1Pressed; a 1 px
        // brand bottom border while focused. Its menu (288 wide, radio items)
        // opens on hover after Fluent's 500 ms delay, or on click.
        component Dropdown: Rectangle {
            id: dd
            property var options: []
            property int current: 0
            property var leadColor
            property string leadIcon
            width: parent ? parent.width : 288; height: 30; radius: 4
            color: ddTap.pressed ? theme.pressed : ddHover.hovered ? theme.menuHover : theme.inputFilled
            activeFocusOnTab: true
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 1; radius: 0
                color: theme.brand; visible: dd.activeFocus
            }
            FluentIcon { visible: !!dd.leadIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; name: dd.leadIcon; size: 16; color: dd.leadColor || theme.text }
            Text {
                x: dd.leadIcon ? 36 : 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 12 - 20 - 4; elide: Text.ElideRight
                text: dd.options.length ? dd.options[dd.current].label : ""
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.text }
            HoverHandler { id: ddHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: ddTap; onTapped: { dd.forceActiveFocus(); ddMenu.opened ? ddMenu.close() : ddMenu.open() } }
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Down) { ddMenu.open(); e.accepted = true } }
            // Fluent Menu openOnHover: open after the hover delay; close once
            // the pointer has left both the trigger and the menu.
            Timer { interval: 500; running: ddHover.hovered && !ddMenu.opened; onTriggered: ddMenu.open() }
            Timer { interval: 500; running: ddMenu.opened && !ddHover.hovered && !ddMenu.hovered; onTriggered: ddMenu.close() }
            MenuPopup {
                id: ddMenu
                y: dd.height + 2; width: dd.width
                items: dd.options.map((o, k) => ({ label: o.label, icon: o.icon, iconColor: o.color, checked: k === dd.current }))
                onPicked: k => dd.current = k
                onClosed: dd.forceActiveFocus()
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: dd.options.length ? dd.options[dd.current].label : ""
        }
        component PrimaryButton: Rectangle {
            id: pb
            property string label
            signal clicked()
            width: 100; height: 32; radius: 4
            color: !enabled ? theme.bgDisabled : pbh.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: pb.label; color: pb.enabled ? "white" : theme.disabled; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
            HoverHandler { id: pbh; cursorShape: pb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: pb.enabled; onTapped: pb.clicked() }
            Accessible.role: Accessible.Button
            Accessible.name: label
        }
        // Duration, laid out as Teams' page (measured in the client, 320 x 273):
        // "Back"; Status and "Reset status after" (default Today) as Fluent
        // filled-darker Dropdowns; Done.
        Item {
            id: durationPage
            visible: menu.page === "duration"
            width: 320; implicitHeight: 273 - 8
            readonly property var durations: [
                { key: "HalfHour", label: "30 minutes" }, { key: "OneHour", label: "1 hour" },
                { key: "TwoHours", label: "2 hours" }, { key: "Today", label: "Today" }, { key: "ThisWeek", label: "This week" }
            ]
            function start() {
                const i = root.statuses.findIndex(s => s.key.toLowerCase() === (root.presence || "Available").toLowerCase())
                statusPick.current = Math.max(0, i)
                durationPick.current = 3
                statusPick.forceActiveFocus()
            }
            Rectangle {
                x: 16; y: 18; width: 57; height: 21; radius: 4
                color: durBack.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 1; y: 1; name: "chevron-left-20"; size: 20; color: theme.textStrong }
                Text { x: 27; y: 1; height: 20; verticalAlignment: Text.AlignVCenter; text: "Back"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
                HoverHandler { id: durBack; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: menu.page = "main" }
                Accessible.role: Accessible.Button
                Accessible.name: "Back"
            }
            Rectangle { x: 11; y: 43; width: 298; height: 1; color: theme.divider }   // Fluent MenuDivider (NeutralStroke2)
            Text { x: 16; y: 61; height: 20; verticalAlignment: Text.AlignVCenter; text: "Status"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            FilledDropdown {
                id: statusPick
                x: 16; y: 85
                options: root.statuses.map(s => ({ label: s.label, icon: "presence-" + root.presenceKind(s.key) + "-16", color: root.presenceInk[root.presenceKind(s.key)] }))
                leadIcon: options.length ? options[current].icon : ""
                leadColor: options.length ? options[current].color : theme.text
            }
            Text { x: 16; y: 142; height: 20; verticalAlignment: Text.AlignVCenter; text: "Reset status after"; font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
            FilledDropdown { id: durationPick; x: 16; y: 166; options: durationPage.durations }
            PrimaryButton {
                x: 208; y: 226; width: 96
                label: "Done"
                onClicked: { menu.visible = false; root.setStatusUntil(root.statuses[statusPick.current].key, durationPage.durations[durationPick.current].key) }
            }
        }
        // Fluent's Dropdown, filled-darker (as Teams' Duration page uses it):
        // 288 x 32, NeutralBackground3, a transparent 1 px border; hover
        // NeutralStroke1Hover with an accessible-hover bottom; pressed or
        // focused the pressed strokes and a 2 px brand underline that scales
        // in (200 ms) and out (50 ms); text 12 in, chevron 20 (#616161) 11 from
        // the right.
        component FilledDropdown: Rectangle {
            id: fd
            property var options: []
            property int current: 0
            property var leadColor
            property string leadIcon
            readonly property bool engaged: fd.activeFocus || fdMenu.opened
            width: 288; height: 32; radius: 4
            color: theme.inputFilled
            activeFocusOnTab: true
            border.width: 0
            // Borders drawn per side (the bottom one differs).
            Rectangle { anchors.fill: parent; radius: 4; color: "transparent"; border.width: 1; visible: fd.engaged || fdTap.pressed || fdHover.hovered
                border.color: fd.engaged || fdTap.pressed ? theme.strokePressed : theme.strokeHover }
            Rectangle { x: 2; width: parent.width - 4; height: 1; anchors.bottom: parent.bottom; visible: fd.engaged || fdTap.pressed || fdHover.hovered
                color: fd.engaged || fdTap.pressed ? theme.strokeAccessiblePressed : theme.strokeAccessibleHover }
            // Fluent's ::after: a 4 px bar with rounded bottom corners, of
            // which only the bottom 2 px show, scaled from the centre.
            Item {
                y: parent.height - 2; width: parent.width; height: 2; clip: true
                transform: Scale { origin.x: fd.width / 2; xScale: fd.engaged ? 1 : 0
                    Behavior on xScale { NumberAnimation { duration: fd.engaged ? 200 : 50; easing.type: fd.engaged ? Easing.OutCubic : Easing.InCubic } } }
                Rectangle { y: -2; width: parent.width; height: 4; radius: 4; color: theme.brand }
            }
            FluentIcon { visible: !!fd.leadIcon; x: 13; anchors.verticalCenter: parent.verticalCenter; name: fd.leadIcon; size: 16; color: fd.leadColor || theme.text }
            Text {
                x: fd.leadIcon ? 41 : 13; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 11 - 20 - 4; elide: Text.ElideRight
                text: fd.options.length ? fd.options[fd.current].label : ""
                font.family: theme.font; font.pixelSize: theme.base; color: theme.text
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 11; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.textSecondary }
            HoverHandler { id: fdHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: fdTap; onTapped: { fd.forceActiveFocus(); fdMenu.opened ? fdMenu.close() : fdMenu.open() } }
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Down || (e.key === Qt.Key_Down && e.modifiers & Qt.AltModifier)) { fdMenu.open(); e.accepted = true } }
            MenuPopup {
                id: fdMenu
                y: fd.height + 2; width: fd.width
                items: fd.options.map((o, k) => ({ label: o.label, icon: o.icon, iconColor: o.color, checked: k === fd.current }))
                onPicked: k => fd.current = k
                onClosed: fd.forceActiveFocus()
            }
            Accessible.role: Accessible.ComboBox
            Accessible.name: fd.options.length ? fd.options[fd.current].label : ""
        }
        // Set status message, laid out as Teams' page (measured in the client,
        // 320 x 522): back button and title with your UPN; a 288 x 240 filled
        // editor (280 characters, counter inside); "Show when people message
        // me" with its info tooltip; "Clear status message after" (default
        // Never); Done / Saving....
        Item {
            id: notePage
            visible: menu.page === "note"
            width: 320; implicitHeight: 522 - 8
            property bool saving: false
            readonly property var clearAfter: [
                { key: "Never", label: "Never" }, { key: "Today", label: "Today" }, { key: "OneHour", label: "1 hour" },
                { key: "FourHours", label: "4 hours" }, { key: "ThisWeek", label: "This week" }
            ]
            // Teams focuses the editor when the page opens.
            function start() { saving = false; noteText.text = root.statusNote; pinBox.checked = root.statusNotePinned; clearPick.current = 0; noteText.forceActiveFocus() }
            Rectangle {
                x: 16; y: 16; width: 21; height: 21; radius: 4
                color: backHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 1; y: 1; name: "chevron-left-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: menu.page = "main" }
                Accessible.role: Accessible.Button
                Accessible.name: "Back"
            }
            Text { x: 53; y: 17; height: 20; verticalAlignment: Text.AlignVCenter; text: "Set status message"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 53; y: 37; height: 16; verticalAlignment: Text.AlignVCenter; text: root.userMail; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            Rectangle {
                x: 16; y: 71; width: 288; height: 240; radius: 3
                color: theme.editorFilled
                clip: true
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand; visible: noteText.activeFocus }
                TextEdit {
                    id: noteText
                    x: 8; y: 8; width: parent.width - 16; height: parent.height - 16 - 20
                    wrapMode: TextEdit.Wrap
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    onTextChanged: if (text.length > 280) { const p = cursorPosition; text = text.slice(0, 280); cursorPosition = Math.min(p, 280) }
                    Text { visible: !parent.text; text: "Type @ to mention someone in your status"; font: parent.font; color: theme.textSecondary }
                    Accessible.name: "Type @ to mention someone in your status"
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 8; y: 211; height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: noteText.text.length + " / 280"
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
            }
            Item {
                x: 16; y: 341; width: 238; height: 39
                Rectangle {
                    id: pinBox
                    property bool checked: false
                    x: 2; y: 10; width: 16; height: 16; radius: 2
                    color: checked ? theme.brandFill : "transparent"; border.color: checked ? theme.brandFill : theme.textSecondary; border.width: 1
                    FluentIcon { anchors.centerIn: parent; visible: pinBox.checked; name: "checkmark-12-filled"; size: 12; color: "white" }
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: checked
                    Accessible.name: "Show when people message me"
                }
                Text { x: 30; y: 8; text: "Show when people message me"; font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pinBox.checked = !pinBox.checked }
            }
            Rectangle {
                x: 254; y: 349; width: 24; height: 24; radius: 4
                color: "transparent"
                FluentIcon { x: 2; y: 2; name: "info-20"; size: 20; color: theme.textStrong }
                HoverHandler { id: infoHover }
                ToolTip {
                    visible: infoHover.hovered; width: 240
                    background: FluentSurface { depth: 16; radius: 4 }
                    contentItem: Text { text: "Your status message will show above the compose message box when someone sends you a message or @mentions you."; wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Your status message will show above the compose message box when someone sends you a message or @mentions you."
            }
            Text { x: 16; y: 390; height: 20; verticalAlignment: Text.AlignVCenter; text: "Clear status message after"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
            Dropdown { id: clearPick; x: 16; y: 424; width: 288; options: notePage.clearAfter }
            // Teams' "Schedule out of office" link (16, 478) opens its
            // out-of-office dialog; shown once OST has that dialog (TASK-0041).
            Text {
                visible: false
                x: 18; y: 480; height: 20; verticalAlignment: Text.AlignVCenter
                text: "Schedule out of office"; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { menu.visible = false; root.openOutOfOffice() } }
                Accessible.role: Accessible.Link
                Accessible.name: "Schedule out of office"
            }
            PrimaryButton {
                x: 191; y: 474
                label: notePage.saving ? "Saving..." : "Done"
                enabled: !notePage.saving && (noteText.text.trim().length > 0 || root.statusNote.length > 0)
                onClicked: { notePage.saving = true; root.setStatusNote(noteText.text.trim(), pinBox.checked, notePage.clearAfter[clearPick.current].key) }
            }
        }
    }
    signal setStatusUntil(string status, string duration)
    signal setStatusNote(string message, bool pinned, string clearAfter)
    signal openOutOfOffice()
    // A status message save finished: close on success, as Teams does.
    function statusNoteSaved(ok, message, pinned) {
        notePage.saving = false
        if (ok) { root.statusNote = message; root.statusNotePinned = pinned; menu.visible = false }
    }
}
