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
    /// Enter in search: Teams' results page for the text (with any
    /// "is:Messages" style tab in it).
    signal searchSubmitted(string text)
    /// Copilot in search (Teams' Serp catalyst, a licensed user with ECS
    /// autosuggest.enableSerpCatalystEntrySuggestion): the placeholders
    /// name Copilot and a query of two words or more is offered as "Ask
    /// Copilot about …", which opens the results with Copilot asked.
    property bool copilotSearch: false
    signal askCopilot(string text)
    /// Put text in the search box (the results page's tab adds "is:…").
    function setSearchText(t) { field.text = t }
    function suggestionsForTest() { return suggestions.items }
    function placeholderForTest() { return root.copilotSearch ? (field.activeFocus ? "focused-copilot" : "copilot") : "plain" }
    function chooseForTest(i) { suggestions.choose(suggestions.items[i]) }
    signal openChat(string id, string name)
    signal openPerson(string oid, string name)
    /// A meeting suggestion: its details (join link, iCal uid, start).
    signal openMeeting(string joinUrl, string uid, string start)
    /// A message (or image) suggestion: the chat or channel at it.
    signal openMessage(string thread, string messageId, string parentId, bool channel, var terms)
    /// "<person> in all results": the results page for that person.
    signal searchPerson(var person)
    /// Send feedback's thumbs under the suggestions.
    signal searchFeedback(string kind, string query)
    signal goBack()
    signal goForward()
    signal toggleRail()
    signal openSettings()
    signal openShortcuts()
    /// Settings and more ▸ Help (F1), and Feedback ▸ (Report a problem,
    /// Give a compliment: "problem" / "compliment"; Suggest a feature).
    signal openHelp()
    signal openFeedback(string kind)
    signal suggestFeature()
    /// Pin window on top (Ctrl+Shift+T).
    property bool pinned: false
    signal togglePin()
    function focusSearch() { field.forceActiveFocus() }
    function openProfileForTest() { menu.visible = true; statusMenu.open() }
    function profilePageForTest(page) { statusMenu.close(); if (page === "duration") durationPage.start(); if (page === "note") notePage.start(); menu.visible = true; menu.page = page }
    function closeProfileForTest() { menu.visible = false }
    function pauseForTest(what) {
        if (what === "flyout") { statusMenu.close(); menu.page = "main"; menu.visible = true }
        else if (what === "menu") pauseMenu.open()
        else if (what === "edit") editMenu.open()
        else if (what === "custom") { menu.visible = false; pauseDialog.start() }
        else if (what === "calendar") pauseDialog.datePickerForTest().openForTest()
        else if (what === "close") { pauseMenu.close(); editMenu.close(); pauseDialog.close(); menu.visible = false }
        else if (what === "resume") root.setStatusUntil("Reset", "Never")
        else if (what === "work") workMenu.open()
        else if (what === "Office" || what === "Remote" || what === "clear") { menu.visible = false; root.setWorkLocation(what === "clear" ? "" : what) }
        else if (what === "dbg") return [pauseMenu.implicitWidth, pauseMenu.width, pauseMenu.rowLabelX(pauseItems[6]), pauseMenu.perItemIcons].join(",")
        else { const i = pauseItems.findIndex(x => x.label === what); if (i >= 0) pickPause(i) }
    }
    function noteTypeForTest(t) { noteText.insert(noteText.cursorPosition, t); noteText.cursorPosition = noteText.length }
    function notePickForTest() { if (notePicker.people.length) notePage.pickMention(notePicker.people[0]); return notePicker.people.length }
    function noteHtmlForTest() { return noteText.text }
    function noteSaveForTest() { notePage.saving = true; root.setStatusNote(noteText.text, pinBox.checked, "Never") }
    // Test hook: type into search and keep the suggestions open offscreen,
    // where the window never has focus.
    property bool keepSuggestionsOpen: false
    function typeSearch(t) { keepSuggestionsOpen = true; field.text = t; peopleDebounce.restart() }
    color: theme.titleBar
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
        color: hover.hovered && btn.usable ? theme.titleHover : "transparent"
        HoverHandler { id: hover }
        TapHandler { enabled: btn.usable; onTapped: btn.clicked() }
        FluentIcon { id: glyph; anchors.centerIn: parent; size: 20; color: theme.onFill(btn, btn.usable ? theme.titleIcon : theme.titleIconDisabled) }
    }

    BarButton {
        icon: "panel-left-text-20-filled"; x: 18; anchors.verticalCenter: parent.verticalCenter
        Accessible.name: qsTr("Collapse app bar")
        onClicked: root.toggleRail()
    }
    BarButton {
        icon: "chevron-left-20"; x: 68; anchors.verticalCenter: parent.verticalCenter
        usable: root.canGoBack
        Accessible.name: qsTr("Back")
        onClicked: root.goBack()
    }
    BarButton {
        icon: "chevron-right-20"; x: 100; anchors.verticalCenter: parent.verticalCenter
        usable: root.canGoForward
        Accessible.name: qsTr("Forward")
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
    readonly property real searchRoomEnd: (premiumPill.visible ? premiumPill.x : moreButton.x) - 9
    readonly property real searchWide: width >= 1680 ? 760 : width >= 1440 ? 664 : width >= 1280 ? 624 : 468
    BarButton {
        id: searchButton
        visible: root.searchFolded && !root.searchOpen
        icon: "search-20"; x: 150; anchors.verticalCenter: parent.verticalCenter
        Accessible.name: qsTr("Search")
        onClicked: { root.searchOpen = true; field.forceActiveFocus() }
    }
    Rectangle {
        id: search
        visible: !root.searchFolded || root.searchOpen
        x: root.width >= 1024 ? Math.max(138, (root.width - root.searchWide - 15) / 2 + 6) : 138
        width: Math.max(0, Math.min(root.width >= 1024 ? root.searchWide : 468, root.searchRoomEnd - x))
        height: 32; radius: theme.radius
        anchors.verticalCenter: parent.verticalCenter
        color: theme.titleSearchFill
        border.color: field.activeFocus ? theme.brand : "transparent"
        FluentIcon { name: "search-20"; size: 16; x: 25; anchors.verticalCenter: parent.verticalCenter; color: theme.onFill(search, theme.titleSearchIcon) }
        TextInput {
            id: field
            // The input starts at 51 px with 8.5 px of padding, as in Teams.
            x: 60; width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.onFill(search, theme.text)
            clip: true
            onTextEdited: peopleDebounce.restart()
            Keys.onEscapePressed: { text = ""; focus = false; root.searchOpen = false }
            onActiveFocusChanged: if (!activeFocus && text.length === 0) root.searchOpen = false
            // The arrows move through the suggestions; Enter opens the one
            // picked, else the results.
            Keys.onDownPressed: suggestions.move(1)
            Keys.onUpPressed: suggestions.move(-1)
            // Alt+arrows scroll the scope pills that don't fit.
            Keys.onLeftPressed: e => { if (e.modifiers & Qt.AltModifier) suggestions.scrollPills(-1); else e.accepted = false }
            Keys.onRightPressed: e => { if (e.modifiers & Qt.AltModifier) suggestions.scrollPills(1); else e.accepted = false }
            Keys.onReturnPressed: {
                if (suggestions.current >= 0 && suggestions.options[suggestions.current]) { root.pick(suggestions.options[suggestions.current]); return }
                if (!root.searchWords) return
                root.submit(field.text)
            }
            Text {
                visible: !field.text
                text: root.copilotSearch
                    ? (field.activeFocus ? qsTr("Look for people, messages, files and more or ask Copilot") : qsTr("Search or ask Copilot (%1)").arg("Ctrl+E"))
                    : field.activeFocus ? qsTr("Press %1 to go right to a chat or channel").arg("Ctrl+G") : qsTr("Search (%1)").arg("Ctrl+E")
                color: theme.onFill(search, theme.textTertiary)
                font: field.font
            }
            Accessible.name: qsTr("Search")
        }
    }

    // What's typed, without an "is:<Tab>" scope (a scope pill puts one
    // in the box, as Teams does).
    readonly property var scopeKeys: ({ messages: "Messages", files: "Files", channels: "Channels", groupchats: "Group chats", meetings: "Meetings", images: "Images" })
    readonly property string searchScope: {
        const m = field.text.match(/\bis:(messages|files|channels|groupchats|group chats|meetings|images)\b/i)
        return m ? m[1].toLowerCase().replace(" ", "") : ""
    }
    readonly property string searchWords: field.text.replace(/\bis:(messages|files|channels|groupchats|group chats|meetings|images)\b/i, "").trim()
    function askSuggestions() { backend.searchSuggest(root.searchWords) }
    Timer { id: peopleDebounce; interval: 150; onTriggered: root.askSuggestions() }

    // Search suggestions (Teams' powerbar, SearchSuggest.qml): asked as the
    // box gets focus with nothing typed, and as you type.
    SearchSuggest {
        id: suggestions
        visible: field.activeFocus || root.keepSuggestionsOpen
        z: 100
        x: search.x; y: search.y + search.height + 2
        width: search.width
        maxHeight: Math.round((root.Window.window ? root.Window.window.height : 680) * 0.7)
        query: root.searchWords
        scope: root.searchScope
        reply: backend.suggestJson ? JSON.parse(backend.suggestJson) : ({})
        chats: root.chats
        copilot: root.copilotSearch
        readonly property var items: options
        // Opening asks again: nothing typed (Teams asks on every focus), or
        // words the last answer wasn't for (a picked search put them there).
        onVisibleChanged: if (visible && (!root.searchWords || String((reply || {}).query || "").trim() !== root.searchWords)) root.askSuggestions()
        function choose(item) { root.pick(item) }
        onActivate: item => root.pick(item)
        onPickScope: key => {
            // With words typed, the pill opens that tab of the results;
            // with none, the box keeps the scope ("is:Files") for them.
            if (key && root.searchWords) { root.submit(root.searchWords + " is:" + root.scopeKeys[key]); return }
            field.text = key ? "is:" + root.scopeKeys[key] + " " : root.searchWords
            field.forceActiveFocus()
        }
        onFeedback: kind => root.searchFeedback(kind, root.searchWords)
    }
    function submit(text) {
        root.keepSuggestionsOpen = false
        field.text = text
        field.focus = false
        root.searchSubmitted(text)
    }
    // A suggestion picked (Teams' hostAppActions): people and chats open
    // their chat, teams and channels the channel, files the file, meetings
    // their details, messages the chat at the message; a recent or
    // suggested search, "See more messages" and Enter run the search.
    function pick(item) {
        const done = () => { root.keepSuggestionsOpen = false; field.text = ""; field.focus = false }
        const terms = root.searchWords.split(/\s+/).filter(w => !!w)
        switch (item.kind) {
        case "copilot": root.keepSuggestionsOpen = false; field.focus = false; root.askCopilot(item.title); return
        case "person": root.openPerson(item.oid, item.plain_name || item.name); break
        case "chat": root.openChat(item.thread, suggestions.chatName(item)); break
        case "team": case "channel": root.openChat(item.thread, item.title); break
        case "file": backend.openFile(item.url, item.title, ""); break
        case "community": backend.openExternal("https://web.yammer.com/main/groups/" + encodeURIComponent(item.id)); break
        case "event": root.openMeeting(item.join || "", item.uid || "", item.start || ""); break
        case "message": case "image": root.openMessage(item.thread, item.id, item.parent || "", !!item.channel, terms); break
        // A recent or suggested search keeps a chosen scope ("is:Files").
        case "text": root.submit((item.query || item.title) + (root.searchScope ? " is:" + root.scopeKeys[root.searchScope] : "")); return
        // "<person> in all results": the results with that person.
        case "pcs":
            root.keepSuggestionsOpen = false; field.text = item.title; field.focus = false
            root.searchPerson({ name: item.title, mail: item.mail || "", mri: item.mri || "", from: false })
            return
        case "seemore": root.submit(item.query + " is:Messages"); return
        case "enter": if (field.text.trim()) root.submit(field.text); return
        case "tip": root.gotoMode(); return
        default: return
        }
        done()
    }
    // The tip's Ctrl+G: the box, focused for a chat or channel's name.
    function gotoMode() { field.forceActiveFocus() }

    BarButton {
        id: moreButton
        visible: !premiumPill.visible
        icon: "more-20"
        anchors.right: profile.left; anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        Accessible.name: qsTr("Settings and more")
        onClicked: moreMenu.visible = !moreMenu.visible
    }
    // With Teams Premium's pill (api::premium::entry: a trial's "N days
    // left"; "Get Premium" during a promo, or for 14 days from when it
    // first shows after a trial ended — on a device that showed the trial,
    // only once its end date has passed) Teams turns Settings and more
    // into a bordered button (measured on winpc
    // 2026-11-15): 31.33 tall, white, 0.67 #D1D1D1, radius 4; the premium
    // glyph (16) 8.67 in, "60 days left" / "Get Premium" (14 semibold) 6
    // after it, then ··· (20) 6 after that, 8.67 from the right edge, which
    // stays where the plain button's is.
    // The label is Teams' more_options_menu_premium_trial_days ("{{days}}
    // days left"), which has no singular: Teams fills it with {days}, not an
    // i18next count, so its last day reads "1 days left" too (async-entry's
    // dnt(), Teams 26304).
    // Teams renders the pill only in a window at least 1280 px wide (its
    // more-options button's Bnt: 947 where Teams draws its own window
    // controls, which Teams desktop on Windows doesn't) and not in its
    // first 120 s (Ose(12e4)); otherwise it's the plain ···, and the pill's
    // device marks wait until it shows (async-entry Wse/Dse, Teams 26304;
    // seen on testpc1: plain ··· at 1024 px).
    property bool premiumPillDue: false
    Timer { interval: 120000; running: true; onTriggered: root.premiumPillDue = true }
    readonly property bool premiumPillShown: premiumPill.visible
    signal premiumPillShowed()
    Rectangle {
        id: premiumPill
        visible: root.premiumPill !== "" && root.premiumPillDue && root.width >= 1280
        onVisibleChanged: if (visible) root.premiumPillShowed()
        readonly property string label: root.premiumPill === "days" ? qsTr("%1 days left").arg(root.premiumDaysLeft) : qsTr("Get Premium")
        anchors.right: moreButton.right
        anchors.verticalCenter: parent.verticalCenter
        width: pillRow.implicitWidth + 17.33; height: 31.33; radius: 4
        color: pillHover.hovered ? theme.menuHover : theme.surface
        border.color: theme.pick("#D1D1D1", "#666666", "#FFFFFF"); border.width: 0.67
        Row {
            id: pillRow
            x: 8.67; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "premium-16"; size: 16; color: theme.onFill(premiumPill, theme.text) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: premiumPill.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(premiumPill, theme.text) }
            FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "more-horizontal-20"; size: 20; color: theme.onFill(premiumPill, theme.text) }
        }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: moreMenu.visible = !moreMenu.visible }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Settings and more")
        Accessible.description: root.premiumPill === "days" ? qsTr("There are %1 days left in your premium trial").arg(root.premiumDaysLeft) : qsTr("Start your free 60 day Teams Premium trial")
        Accessible.onPressAction: moreMenu.visible = !moreMenu.visible
    }
    // "Settings and more", as Teams' (measured on winpc 2026-11-15): a
    // 238.47-wide popover centred under the button, 8 below it (radius 4,
    // padding 4, the depth-16 shadow); 32-tall rows 2 apart (radius 4, a
    // 20 px icon 6 in, the label 14 #424242 at 30, shortcuts 12 #616161
    // right-aligned 8 in); dividers across the whole popover with 4 above
    // and below. The Zoom row: "Zoom" 8 in, then Zoom out, "(100)%", Zoom
    // in and Reset (24 x 23.33 buttons, 8 apart) right-aligned. Get the
    // mobile app ends with Teams' "New" pill. Unlock Teams Premium shows
    // while you can start Teams' Premium trial.
    property int zoomPercent: 100
    /// Teams Premium's pill: "days" (N days left), "get" (Get Premium) or
    /// "" (the plain ···).
    property string premiumPill: ""
    /// Its ··· menu row: "unlock" (Unlock Teams Premium), "benefits"
    /// (Teams Premium benefits, in a trial), "get" (Get Teams Premium,
    /// after one) or "" (none).
    property string premiumMenu: ""
    /// Teams' separate Teams Premium benefits row (a Premium licence not
    /// in an active trial).
    property bool premiumBenefitsRow: false
    /// Days left in the trial (the button's "N days left").
    property int premiumDaysLeft: 0
    signal zoomOut()
    signal zoomIn()
    signal zoomReset()
    signal openPremium(string kind)
    signal openCast()
    signal openDownloads()
    signal openMobileApp()
    FluentSurface {
        id: moreMenu
        visible: false
        z: 100
        depth: 16; radius: 4; color: theme.menu
        width: 238.47; height: moreCol.implicitHeight + 9.33
        readonly property Item anchorButton: premiumPill.visible ? premiumPill : moreButton
        x: anchorButton.x + anchorButton.width / 2 - width / 2
        y: anchorButton.y + anchorButton.height + 8
        component MenuRow: Rectangle {
            id: mr
            property string icon
            property string label
            property string keys
            property bool checked: false
            /// Opens a submenu (Feedback ▸) instead of picking.
            property bool submenu: false
            property real labelX: 30
            property bool pill: false
            signal picked()
            width: moreCol.width; height: 32; radius: 4
            color: mrh.hovered || (submenu && feedbackMenu.visible) ? theme.rowHover : "transparent"
            FluentIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; name: mr.icon; size: 20; color: theme.onFill(mr, mr.checked ? theme.brand : theme.textStrong) }
            Text { x: mr.labelX; anchors.verticalCenter: parent.verticalCenter; text: mr.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(mr, mrh.hovered ? theme.text : theme.textStrong) }
            Text { visible: !!mr.keys; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: mr.keys; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(mr, theme.textSecondary) }
            FluentIcon { visible: mr.submenu; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-20"; size: 20; color: theme.onFill(mr, theme.textStrong) }
            Rectangle {
                id: hcFill1
                visible: mr.pill
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                width: 36.66; height: 20; radius: 10
                color: theme.brandFill
                Text { anchors.centerIn: parent; text: qsTr("New"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.onFill(hcFill1, theme.textOnBrand) }
            }
            HoverHandler { id: mrh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) feedbackMenu.showFor(mr.submenu ? mr : null) }
            TapHandler { onTapped: { if (mr.submenu) { feedbackMenu.showFor(mr); return } moreMenu.visible = false; mr.picked() } }
            Accessible.role: Accessible.MenuItem
            Accessible.name: mr.label
            Accessible.onPressAction: { if (mr.submenu) feedbackMenu.showFor(mr); else { moreMenu.visible = false; mr.picked() } }
        }
        component MenuDivider: Item {
            width: moreCol.width; height: 8.67
            Rectangle { x: -4.67; y: 4; width: moreMenu.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio); antialiasing: true; color: theme.pick("#E0E0E0", "#3D3D3D", "#000000") }
        }
        component ZoomButton: Rectangle {
            id: zb
            property string icon
            property string label
            signal picked()
            width: 24; height: 23.33; radius: 4
            color: zbh.hovered ? theme.rowHover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: zb.icon; size: 20; color: theme.onFill(zb, theme.textStrong) }
            HoverHandler { id: zbh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: zb.picked() }
            ToolTip.visible: zbh.hovered; ToolTip.delay: 500; ToolTip.text: zb.label
            Accessible.role: Accessible.MenuItem
            Accessible.name: zb.label
            Accessible.onPressAction: zb.picked()
        }
        Column {
            id: moreCol
            x: 4.67; y: 4.67; width: parent.width - 9.33
            spacing: 2
            // Teams Premium: one row (Teams' "promo" item), then Teams
            // Premium benefits for a Premium licence outside a trial.
            MenuRow { visible: root.premiumMenu === "unlock"; icon: "premium-20"; label: qsTr("Unlock Teams Premium"); onPicked: root.openPremium("offer") }
            MenuRow { visible: root.premiumMenu === "get"; icon: "premium-20"; label: qsTr("Get Teams Premium"); onPicked: root.openPremium("get") }
            MenuRow { visible: root.premiumMenu === "benefits"; icon: "premium-20"; label: qsTr("Teams Premium benefits"); onPicked: root.openPremium("home") }
            MenuRow { visible: root.premiumBenefitsRow; icon: "premium-20"; label: qsTr("Teams Premium benefits"); onPicked: root.openPremium("home") }
            MenuDivider { visible: root.premiumMenu !== "" || root.premiumBenefitsRow }
            MenuRow { icon: "pin-20"; label: root.pinned ? qsTr("Unpin window") : qsTr("Pin window on top"); keys: "Ctrl+Shift+T"; checked: root.pinned; onPicked: root.togglePin() }
            MenuRow { icon: "settings-20"; label: qsTr("Settings"); keys: "Ctrl+,"; onPicked: root.openSettings() }
            MenuRow { icon: "cast-20"; label: qsTr("Cast"); onPicked: root.openCast() }
            MenuRow { icon: "arrow-download-20"; label: qsTr("Downloads"); onPicked: root.openDownloads() }
            MenuDivider {}
            Item {
                width: moreCol.width; height: 27.33
                Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Zoom"); font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    ZoomButton { icon: "subtract-20"; label: qsTr("Zoom out"); onPicked: root.zoomOut() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "(" + root.zoomPercent + ")%"
                        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.textStrong
                        Accessible.role: Accessible.StaticText
                        Accessible.name: qsTr("Zoom %1%").arg(root.zoomPercent)
                    }
                    ZoomButton { icon: "add-20"; label: qsTr("Zoom in"); onPicked: root.zoomIn() }
                    ZoomButton { icon: "page-fit-20"; label: qsTr("Reset zoom"); onPicked: root.zoomReset() }
                }
            }
            MenuDivider {}
            MenuRow { icon: "question-circle-20"; label: qsTr("Help"); keys: "F1"; onPicked: root.openHelp() }
            MenuRow { id: feedbackRow; icon: "person-feedback-20"; label: qsTr("Feedback"); submenu: true }
            MenuRow { icon: "keyboard-20"; label: qsTr("Keyboard shortcuts"); keys: "Ctrl+."; onPicked: root.openShortcuts() }
            MenuRow { icon: "phone-20"; label: qsTr("Get the mobile app"); labelX: 32; pill: true; onPicked: root.openMobileApp() }
        }
        onVisibleChanged: if (!visible) feedbackMenu.visible = false
    }
    function moreMenuForTest(open) { moreMenu.visible = open !== false; return moreMenu }
    // Feedback ▸ (Teams' submenu, 245.4 wide, opening to the left with its
    // first row level with Feedback): Report a problem (Ctrl+Alt+Shift+R),
    // Give a compliment, Suggest a feature.
    Rectangle {
        id: feedbackMenu
        visible: false
        z: 101
        width: 245.4; height: feedbackCol.implicitHeight + 8
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        function showFor(row) {
            if (!row) { visible = false; return }
            const p = row.mapToItem(root, 0, 0)
            x = moreMenu.x - width + 4; y = p.y - 4
            visible = true
        }
        Column {
            id: feedbackCol
            x: 4; y: 4; width: parent.width - 8
            Repeater {
                model: [{ key: "problem", icon: "bug-20", label: qsTr("Report a problem"), keys: "Ctrl+Alt+Shift+R" },
                        { key: "compliment", icon: "heart-20", label: qsTr("Give a compliment"), keys: "" },
                        { key: "suggest", icon: "microscope-20", label: qsTr("Suggest a feature"), keys: "" }]
                Rectangle {
                    id: hcFill2
                    required property var modelData
                    width: feedbackCol.width; height: 36; radius: theme.radius
                    color: fbh.hovered ? theme.rowHover : "transparent"
                    FluentIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: parent.modelData.icon; size: 20; color: theme.onFill(hcFill2, theme.textStrong) }
                    Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(hcFill2, theme.text) }
                    Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.keys; font.family: theme.font; font.pixelSize: theme.small; color: theme.onFill(hcFill2, theme.textSecondary) }
                    HoverHandler { id: fbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            moreMenu.visible = false
                            if (parent.modelData.key === "suggest") root.suggestFeature()
                            else root.openFeedback(parent.modelData.key)
                        }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }
    }
    function feedbackMenuForTest() { moreMenu.visible = true; feedbackMenu.showFor(feedbackRow) }
    // This device's other accounts (refreshed every half minute and when
    // the flyout opens).
    property var otherAccounts: []
    function refreshAccounts() { otherAccounts = JSON.parse(backend.otherAccountsJson()) }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshAccounts() }
    // Profile: a 40 px round button around the 28 px avatar. With more
    // accounts (Teams' MTMA, measured on winpc 2026-11-22) it is a 140 x 28
    // pill with the organisation's name (12/16 #424242 at 6.7, cut at
    // 107.9) before the avatar.
    // A personal account's window (Teams for personal use): its profile
    // menu says "Personal" and has no Pause notifications or work location.
    property bool personal: false
    Rectangle {
        id: profile
        // The pill names the org: only a work window next to another work
        // account has one (with only a personal account beside it, Teams
        // keeps the round picture; testpc2, 2026-11-27).
        readonly property bool multi: !root.personal && root.otherAccounts.some(a => !a.personal)
        width: multi ? 140 : 40; height: multi ? 28 : 40; radius: height / 2
        anchors.right: controls.left; anchors.rightMargin: root.windowButtons ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        color: profileHover.hovered ? theme.titleHover : "transparent"
        HoverHandler { id: profileHover }
        TapHandler { onTapped: menu.visible = !menu.visible }
        Accessible.name: multi ? qsTr("Your profile, status %1 for %2 in %3").arg(root.statusLabel(root.presence)).arg(root.userMail).arg(root.orgName) : qsTr("Your profile")
        Text {
            visible: profile.multi
            x: 6.7; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 107.9); elide: Text.ElideRight
            text: root.orgName
            font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight
            color: theme.textStrong
        }
        Avatar {
            id: avatar
            anchors.centerIn: profile.multi ? undefined : parent
            anchors.verticalCenter: parent.verticalCenter
            x: profile.multi ? parent.width - 23.1 : (parent.width - width) / 2
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
            color: capHover.hovered ? (danger ? theme.hc("#C42B1C", "#1AEBFF") : theme.titleHover) : "transparent"
            HoverHandler { id: capHover }
            TapHandler { onTapped: cap.clicked() }
            Canvas {
                id: glyphs
                anchors.centerIn: parent
                width: 12; height: 12
                property color ink: capHover.hovered && cap.danger ? "white" : theme.titleIcon
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
            kind: "min"; Accessible.name: qsTr("Minimize")
            onClicked: if (root.Window.window) root.Window.window.showMinimized()
        }
        CaptionButton {
            kind: "max"; Accessible.name: qsTr("Maximize")
            onClicked: {
                const w = root.Window.window
                if (w) w.visibility = w.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
            }
        }
        CaptionButton {
            kind: "close"; danger: true; Accessible.name: qsTr("Close")
            onClicked: if (root.Window.window) root.Window.window.close()
        }
    }

    // Account flyout, as Teams lays it out: organisation and Sign out, your
    // picture, name and e-mail, then your status with its choices.
    property string userMail: ""
    property string orgName: ""
    signal setStatus(string status)
    readonly property var statuses: [
        { key: "Available", label: qsTr("Available") },
        { key: "Busy", label: qsTr("Busy") },
        { key: "DoNotDisturb", label: qsTr("Do not disturb") },
        { key: "BeRightBack", label: qsTr("Be right back") },
        { key: "Away", label: qsTr("Appear away") },
        { key: "Offline", label: qsTr("Appear offline") },
    ]
    function statusLabel(p) {
        const k = (p || "Available").toLowerCase()
        const s = statuses.find(s => s.key.toLowerCase() === k)
        return s ? s.label : (k === "inacall" || k === "inameeting" || k === "busyidle" ? qsTr("Busy") : k === "availableidle" ? qsTr("Available") : p)
    }
    readonly property var presenceInk: ({ available: "#13A10E", away: "#EAA300", busy: "#D13438", dnd: "#D13438", offline: "#616161" })
    function presenceKind(key) {
        const k = key.toLowerCase()
        return k === "available" ? "available" : (k === "away" || k === "berightback") ? "away"
            : k === "busy" ? "busy" : k === "donotdisturb" ? "dnd" : "offline"
    }
    // Pause notifications (Teams' me control, measured on winpc
    // 2026-11-09): Do not disturb until a time. Paused is Do not disturb
    // with an end (the presence service's forcedAvailability.expiry).
    property string statusUntil: ""
    /// Where you work today ("Office", "Remote" or "").
    property string workLocation: ""
    /// Its building and how it was set ({building, source}, JSON).
    property string workLocationDetail: ""
    signal setWorkLocation(string location)
    signal pauseUntil(string iso)
    signal openNotificationSettings()
    readonly property bool paused: (presence || "").toLowerCase() === "donotdisturb" && statusUntil.length > 0
    // Teams' "Until …": the time today, else "Nov 10, 12:02 AM".
    function untilText(iso) {
        const d = new Date(iso), now = new Date()
        const t = theme.time(d)
        return d.toDateString() === now.toDateString() ? t : theme.fmtDate(d, "MMM d") + ", " + t
    }
    readonly property var pauseItems: [
        { label: qsTr("10 minutes"), minutes: 10 }, { label: qsTr("30 minutes"), minutes: 30 }, { label: qsTr("1 hour"), minutes: 60 },
        { label: qsTr("Today"), minutes: -1 }, { label: qsTr("Custom"), custom: true },
        { separator: true }, { label: qsTr("Notifications settings"), icon: "settings-20", settings: true }
    ]
    function pickPause(i) {
        const it = pauseItems[i]
        menu.visible = false
        if (it.settings) { root.openNotificationSettings(); return }
        if (it.custom) { pauseDialog.start(); return }
        let end
        if (it.minutes > 0) end = new Date(Date.now() + it.minutes * 60000)
        else { end = new Date(); end.setHours(23, 59, 59, 999) }
        root.pauseUntil(end.toISOString())
    }
    PauseNotificationsDialog { id: pauseDialog; onSaved: d => root.pauseUntil(d.toISOString()) }
    // Your status message (Set status message), as last saved here.
    property string statusNote: ""
    /// The same with mentions marked (from the presence service).
    property string statusNoteHtml: ""
    property bool statusNotePinned: false
    Rectangle {
        id: menu
        visible: false
        z: 100
        // Teams' profile flyout: 320 wide; its pages replace one another.
        property string page: "main"
        width: 320; height: page === "main" ? menuCol.implicitHeight : (page === "duration" ? durationPage.implicitHeight : notePage.implicitHeight) + 8
        anchors.right: parent.right; anchors.rightMargin: 8
        y: parent.height + 4
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        onVisibleChanged: if (!visible) { statusMenu.close(); pauseMenu.close(); editMenu.close(); workMenu.close(); page = "main" }
        Column {
            id: menuCol
            visible: menu.page === "main"
            width: parent.width
            Item {
                width: parent.width; height: 48
                Text {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 120; elide: Text.ElideRight
                    text: root.personal ? qsTr("Personal") : (root.orgName || qsTr("Signed in"))
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.text
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Sign out")
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textStrong
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { menu.visible = false; root.signOut() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Sign out")
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
                    // View account ↗ (opens the Microsoft account page in the
                    // browser, as Teams does); a personal account's is "My
                    // Microsoft account" (account.microsoft.com).
                    Row {
                        spacing: 4
                        readonly property string label: root.personal ? qsTr("My Microsoft account") : qsTr("View account")
                        Text { text: parent.label; font.family: theme.font; font.pixelSize: theme.small; color: theme.textStrong }
                        FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "open-16"; size: 12; color: theme.textStrong }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { menu.visible = false; backend.openExternal(root.personal ? "https://account.microsoft.com/" : "https://myaccount.microsoft.com/") } }
                        Accessible.role: Accessible.Link
                        Accessible.name: parent.label
                    }
                }
            }
            component FlyoutRow: Rectangle {
                id: fr
                property string icon
                property string label
                property bool chevron: true
                property bool active: false
                property color iconColor: theme.textStrong
                default property alias lead: frLead.data
                signal clicked()
                width: menuCol.width - 8; x: 4; height: 36; radius: theme.radius
                color: frh.hovered || active ? theme.rowHover : "transparent"
                Item { id: frLead; x: 78; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
                FluentIcon { visible: !!fr.icon; x: 78; anchors.verticalCenter: parent.verticalCenter; name: fr.icon; size: 20; color: theme.onFill(fr, fr.iconColor) }
                Text { x: 108; anchors.verticalCenter: parent.verticalCenter; text: fr.label; font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(fr, theme.text) }
                FluentIcon { visible: fr.chevron; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; name: "chevron-right-12"; size: 12; color: theme.onFill(fr, theme.textStrong) }
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
            // Pause notifications ▸ 10 minutes, 30 minutes, 1 hour, Today,
            // Custom | Notifications settings (a submenu to the flyout's
            // left, its top at the row's).
            FlyoutRow {
                id: pauseRow
                visible: !root.paused && !root.personal
                icon: pauseMenu.opened || pauseRowHover.hovered ? "alert-20-filled" : "alert-20"
                iconColor: pauseMenu.opened || pauseRowHover.hovered ? theme.brand : theme.textStrong
                label: qsTr("Pause notifications")
                active: pauseMenu.opened
                HoverHandler { id: pauseRowHover }
                onClicked: pauseMenu.opened ? pauseMenu.close() : pauseMenu.open()
                MenuPopup {
                    id: pauseMenu
                    // (Not FlyoutRow's icon slot, where its default
                    // property would put it.)
                    parent: pauseRow
                    perItemIcons: true
                    x: -4 - implicitWidth + 3; y: 0
                    items: root.pauseItems
                    onPicked: i => root.pickPause(i)
                }
            }
            // Paused: Teams' card (76 in, 234 x 54, #F5F5F5, radius 4,
            // padding 8): "Notifications paused" (12/20 semibold) and
            // "Until …" (10/10, #424242) 8 under it; on hover or focus Edit
            // pause duration (the same choices, below, end-aligned) and
            // Resume notifications (16 px icons in 20 px buttons, 184 and
            // 206 in, 17 down).
            Item {
                visible: root.paused && !root.personal
                width: parent.width; height: 58
                Rectangle {
                    id: pausedCard
                    x: 76; y: 2; width: 234; height: 54; radius: 4
                    color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                    HoverHandler { id: pausedHover }
                    readonly property bool actions: pausedHover.hovered || editPause.activeFocus || resumePause.activeFocus || editMenu.opened
                    Text { x: 8; y: 8; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Notifications paused"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.text }
                    Text { x: 8; y: 36; height: 10; verticalAlignment: Text.AlignVCenter; text: qsTr("Until %1").arg(root.statusUntil ? root.untilText(root.statusUntil) : ""); font.family: theme.font; font.pixelSize: 10; color: theme.textStrong }
                    Rectangle {
                        id: editPause
                        x: 184; y: 17; width: 20; height: 20; radius: 4
                        opacity: pausedCard.actions ? 1 : 0
                        color: "transparent"
                        activeFocusOnTab: true
                        FluentIcon { anchors.centerIn: parent; name: editHoverP.hovered || editMenu.opened ? "edit-16-filled" : "edit-16"; size: 16; color: editHoverP.hovered || editMenu.opened ? theme.brand : theme.textStrong }
                        HoverHandler { id: editHoverP; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: editMenu.opened ? editMenu.close() : editMenu.open() }
                        ToolTip.visible: editHoverP.hovered && !editMenu.opened; ToolTip.delay: 500; ToolTip.text: qsTr("Edit pause duration")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Edit pause duration, Notifications paused, until %1, Your presence was changed to Do not disturb.").arg(root.statusUntil ? root.untilText(root.statusUntil) : "")
                        MenuPopup {
                            id: editMenu
                            perItemIcons: true
                            x: 42 - implicitWidth; y: 20 + 4
                            items: root.pauseItems
                            onPicked: i => root.pickPause(i)
                        }
                    }
                    Rectangle {
                        id: resumePause
                        x: 206; y: 17; width: 20; height: 20; radius: 4
                        opacity: pausedCard.actions ? 1 : 0
                        color: "transparent"
                        activeFocusOnTab: true
                        FluentIcon { anchors.centerIn: parent; name: resumeHover.hovered ? "dismiss-16-filled" : "dismiss-16"; size: 16; color: resumeHover.hovered ? theme.brand : theme.textStrong }
                        HoverHandler { id: resumeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.setStatusUntil("Reset", "Never") }
                        ToolTip.visible: resumeHover.hovered; ToolTip.delay: 500; ToolTip.text: qsTr("Resume notifications")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Resume notifications")
                    }
                }
            }
            // Set work location (Teams' places control, measured on winpc
            // 2026-11-10): the row says "Set work location" (location-add),
            // "In the office" (building-checkmark, filled brand) or "Working
            // remotely" (home, filled brand). Its menu (240 wide, centred
            // under the row): "For today" (12/20 semibold #616161, 32
            // tall), Office (building) and Remote (home), icons 12 in and
            // labels 38; once set, a divider and Clear work location
            // (delete, 6 / 32 in). Picking sets it until the end of today.
            FlyoutRow {
                id: workRow
                visible: !root.personal
                readonly property string loc: root.workLocation
                // A check-in's (or a building you picked) names its
                // building: Teams' status string "In <building>", or
                // "Planned in <building>" from the work plan.
                readonly property var detail: { try { return JSON.parse(root.workLocationDetail || "{}") } catch (e) { return {} } }
                readonly property string building: loc ? (detail.building || "") : ""
                // A check-in (VerifiedLocation) shows the regular
                // building-checkmark in the row's text colour (Teams 26304 on
                // winpc, 2026-11-23: #424242).
                readonly property bool verified: loc === "Office" && detail.source === "VerifiedLocation"
                icon: verified ? "building-checkmark-20" : loc === "Office" ? "building-checkmark-20-filled" : loc === "Remote" ? "home-20-filled" : "location-add-20"
                iconColor: (loc === "Office" && !verified) || loc === "Remote" || workMenu.opened ? theme.brand : theme.textStrong
                label: building && (detail.source === "VerifiedLocation" || detail.source === "ForcedLocation") ? qsTr("In %1").arg(building)
                    : building && detail.source === "ScheduledLocation" ? qsTr("Planned in %1").arg(building)
                    : loc === "Office" ? qsTr("In the office") : loc === "Remote" ? qsTr("Working remotely") : qsTr("Set work location")
                active: workMenu.opened
                onClicked: workMenu.opened ? workMenu.close() : workMenu.open()
                Accessible.name: qsTr("Your current work location: %1").arg(label)
                Popup {
                    id: workMenu
                    parent: workRow
                    x: (workRow.width - width) / 2; y: workRow.height
                    width: 240; padding: 4
                    background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
                    contentItem: Column {
                        Text { width: parent.width; height: 32; leftPadding: 12; verticalAlignment: Text.AlignVCenter; text: qsTr("For today"); font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.textSecondary }
                        Repeater {
                            model: [{ key: "Office", label: qsTr("Office"), icon: "building-20" }, { key: "Remote", label: qsTr("Remote"), icon: "home-20" }]
                            WorkItem { required property var modelData; iconX: 12; labelX: 38; icon: modelData.icon; label: modelData.label; onClicked: { menu.visible = false; root.setWorkLocation(modelData.key) } }
                        }
                        Item { visible: !!workRow.loc; width: parent.width; height: 8.6; Rectangle { x: -4; width: 240; height: 0.67; anchors.verticalCenter: parent.verticalCenter; color: theme.divider } }
                        WorkItem { visible: !!workRow.loc; iconX: 6; labelX: 32; icon: "delete-20"; label: qsTr("Clear work location"); onClicked: { menu.visible = false; root.setWorkLocation("") } }
                    }
                    component WorkItem: Rectangle {
                        id: wi
                        property real iconX
                        property real labelX
                        property string icon
                        property string label
                        signal clicked()
                        width: 230.7; height: 32; radius: 4
                        color: wiHover.hovered ? theme.menuHover : "transparent"
                        FluentIcon { x: wi.iconX; anchors.verticalCenter: parent.verticalCenter; name: wi.icon; size: 20; color: theme.onFill(wi, theme.textStrong) }
                        Text { x: wi.labelX; anchors.verticalCenter: parent.verticalCenter; text: wi.label; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(wi, theme.textStrong) }
                        HoverHandler { id: wiHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: wi.clicked() }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: wi.label
                    }
                }
            }
            FlyoutRow {
                visible: !root.statusNote
                icon: "status-20"; label: qsTr("Set status message")
                onClicked: { notePage.start(); menu.page = "note" }
            }
            // Your status message, as Teams shows it here (measured on
            // winpc): a 233-wide #F5F5F5 box, 76 in, its text 14/20 with
            // mentions in brand colour; on hover, edit and delete.
            Item {
                visible: !!root.statusNote
                width: parent.width; height: noteBox.height + 8
                Rectangle {
                    id: noteBox
                    x: 76; y: 4; width: 233; height: Math.max(62, noteShown.implicitHeight + 24); radius: 4
                    color: theme.pick("#F5F5F5", "#2E2E2E", "#000000")
                    Text {
                        id: noteShown
                        x: 12; y: 12; width: parent.width - 24 - (noteHover.hovered ? 56 : 0)
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        text: "<style>.mention, .mention-me { color: " + theme.brandForeground1 + "; }</style>" + (root.statusNoteHtml || root.statusNote.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
                        lineHeight: 20; lineHeightMode: Text.FixedHeight
                        font.family: theme.font; font.pixelSize: 14; color: theme.text
                    }
                    HoverHandler { id: noteHover }
                    TapHandler { onTapped: { notePage.start(); menu.page = "note" } }
                    Row {
                        visible: noteHover.hovered
                        anchors.right: parent.right; anchors.rightMargin: 4; y: 4
                        Rectangle {
                            id: hcFill3
                            width: 24; height: 24; radius: 4
                            color: editHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "edit-20"; size: 16; color: theme.onFill(hcFill3, theme.textSecondary) }
                            HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { notePage.start(); menu.page = "note" } }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Set status message")
                        }
                        Rectangle {
                            id: hcFill4
                            width: 24; height: 24; radius: 4
                            color: delHover.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 16; color: theme.onFill(hcFill4, theme.textSecondary) }
                            HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.setStatusNote("", false, "Never") }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Delete status message")
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Your current status message: %1").arg(root.statusNote)
                }
            }
            // Teams' accounts and orgs (its MTMA flyout, measured on winpc
            // 2026-11-22 with OST Test 2 added): under the white menu a
            // #F5F5F5 band, 80.3 tall per account: the 48 px picture at 16
            // with its 12 px presence at 36, 36, the name 14/600 at 76, 8 and
            // the address 12/16 under it; "Switch to account {upn},  Status
            // {availability}". OST keeps each account in its own profile and
            // window (its own sign-in).
            readonly property var otherAccounts: menu.visible ? root.otherAccounts : []
            Connections { target: menu; function onVisibleChanged() { if (menu.visible) root.refreshAccounts() } }
            Item { visible: menuCol.otherAccounts.length === 0; width: parent.width; height: 10 }
            Repeater {
                model: menuCol.otherAccounts
                Rectangle {
                    id: acctRow
                    required property var modelData
                    width: menuCol.width; height: 80.3
                    color: acctHover.hovered ? theme.pick("#EBEBEB", "#333333", "#1AEBFF") : theme.pick("#F5F5F5", "#292929", "#000000")
                    Avatar { x: 16; y: 0.6; size: 48; name: acctRow.modelData.name || acctRow.modelData.upn; photoId: acctRow.modelData.objectId || "" }
                    PresenceBadge { x: 52; y: 36.6; total: 12; presence: acctRow.modelData.availability || "Offline" }
                    Column {
                        x: 76; y: 8.6
                        width: parent.width - 92
                        Text { width: parent.width; elide: Text.ElideRight; text: acctRow.modelData.name || acctRow.modelData.upn; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.onFill(acctRow, theme.text) }
                        Text { width: parent.width; elide: Text.ElideRight; text: acctRow.modelData.upn; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.onFill(acctRow, theme.text) }
                    }
                    HoverHandler { id: acctHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { menu.visible = false; backend.switchAccount(acctRow.modelData.profile) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Switch to account %1,  Status %2").arg(acctRow.modelData.upn).arg(root.statusLabel(acctRow.modelData.availability || "Offline"))
                }
            }
            // Teams' footer (me-control-menu-add-account, measured on winpc
            // 2026-11-21): 65 tall under a 1.3 px #F5F5F5 rule on #F0F0F0,
            // a 32 px round slot at 26 with the 16 px person-add glyph
            // (#616161), "Add another account" 14/600 at 76.
            Rectangle {
                id: addAcct
                width: parent.width; height: 66.3
                color: addHover.hovered ? theme.pick("#E0E0E0", "#3D3D3D", "#1AEBFF") : theme.pick("#F0F0F0", "#1F1F1F", "#000000")
                bottomLeftRadius: 8; bottomRightRadius: 8
                Rectangle { width: parent.width; height: 1.3; color: theme.pick("#F5F5F5", "#2E2E2E", "#FFFFFF") }
                // Teams' 32 px round slot (#E6E6E6) with the glyph.
                Rectangle {
                    x: 26; y: 1.3 + (65 - 32) / 2; width: 32; height: 32; radius: 16
                    color: theme.pick("#E6E6E6", "#3D3D3D", "#000000")
                    border.color: theme.highContrast ? "#FFFFFF" : "transparent"; border.width: 0.67
                    FluentIcon { anchors.centerIn: parent; name: "person-add-20"; size: 16; color: theme.onFill(addAcct, theme.textSecondary) }
                }
                Text { x: 76; y: 1.3 + (65 - 20) / 2; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Add another account"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.onFill(addAcct, theme.text) }
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { menu.visible = false; backend.addAccount() } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Add another account")
            }
        }
        // The status choices, as Teams' menu: the statuses, Duration, Reset status.
        MenuPopup {
            id: statusMenu
            x: 72; y: statusRow.y + statusRow.height + 2
            items: root.statuses.map(s => ({ label: s.label, icon: "presence-" + root.presenceKind(s.key) + "-16",
                                               iconColor: root.presenceInk[root.presenceKind(s.key)] }))
                .concat([{ separator: true }, { label: qsTr("Duration"), icon: "clock-20", chevron: true },
                         { separator: true }, { label: qsTr("Reset status"), icon: "arrow-reset-20" }])
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
            FluentIcon { visible: !!dd.leadIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; name: dd.leadIcon; size: 16; color: theme.onFill(dd, dd.leadColor || theme.text) }
            Text {
                x: dd.leadIcon ? 36 : 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 12 - 20 - 4; elide: Text.ElideRight
                text: dd.options.length ? dd.options[dd.current].label : ""
                font.family: theme.font; font.pixelSize: theme.base; color: theme.onFill(dd, theme.text)
            }
            FluentIcon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-20"; size: 20; color: theme.onFill(dd, theme.text) }
            HoverHandler { id: ddHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: ddTap; onTapped: { dd.forceActiveFocus(); ddMenu.opened ? ddMenu.close() : ddMenu.open() } }
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Down) { ddMenu.open(); ddMenu.focusRing = true; e.accepted = true } }
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
            Text { anchors.centerIn: parent; text: pb.label; color: theme.onFill(pb, pb.enabled ? "white" : theme.disabled); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold }
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
                { key: "HalfHour", label: qsTr("30 minutes") }, { key: "OneHour", label: qsTr("1 hour") },
                { key: "TwoHours", label: qsTr("2 hours") }, { key: "Today", label: qsTr("Today") }, { key: "ThisWeek", label: qsTr("This week") }
            ]
            function start() {
                const i = root.statuses.findIndex(s => s.key.toLowerCase() === (root.presence || "Available").toLowerCase())
                statusPick.current = Math.max(0, i)
                durationPick.current = 3
                statusPick.forceActiveFocus()
            }
            Rectangle {
                id: hcFill5
                x: 16; y: 18; width: 57; height: 21; radius: 4
                color: durBack.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 1; y: 1; name: "chevron-left-20"; size: 20; color: theme.onFill(hcFill5, theme.textStrong) }
                Text { x: 27; y: 1; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Back"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.onFill(hcFill5, theme.textStrong) }
                HoverHandler { id: durBack; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: menu.page = "main" }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Back")
            }
            Rectangle { x: 11; y: 43; width: 298; height: 1; color: theme.divider }   // Fluent MenuDivider (NeutralStroke2)
            Text { x: 16; y: 61; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Status"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
            FilledDropdown {
                id: statusPick
                x: 16; y: 85
                options: root.statuses.map(s => ({ label: s.label, icon: "presence-" + root.presenceKind(s.key) + "-16", color: root.presenceInk[root.presenceKind(s.key)] }))
                leadIcon: options.length ? options[current].icon : ""
                leadColor: options.length ? options[current].color : theme.text
            }
            Text { x: 16; y: 142; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Reset status after"); font.family: theme.font; font.pixelSize: theme.base; color: theme.textStrong }
            FilledDropdown { id: durationPick; x: 16; y: 166; options: durationPage.durations }
            PrimaryButton {
                x: 208; y: 226; width: 96
                label: qsTr("Done")
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
            color: theme.inputFilled; border.color: theme.transparentStroke
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
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Down || (e.key === Qt.Key_Down && e.modifiers & Qt.AltModifier)) { fdMenu.open(); fdMenu.focusRing = true; e.accepted = true } }
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
                { key: "Never", label: qsTr("Never") }, { key: "Today", label: qsTr("Today") }, { key: "OneHour", label: qsTr("1 hour") },
                { key: "FourHours", label: qsTr("4 hours") }, { key: "ThisWeek", label: qsTr("This week") }
            ]
            // Teams focuses the editor when the page opens.
            function start() { saving = false; noteText.text = ""; noteText.insert(0, root.statusNote.replace(/&/g, "&amp;").replace(/</g, "&lt;")); pinBox.checked = root.statusNotePinned; clearPick.current = 0; noteText.forceActiveFocus() }
            // A picked person goes in as Teams' editor puts them: one token
            // per word of their name (sent as one mention).
            function pickMention(p) {
                const at = noteText.mentionAt, end = noteText.cursorPosition
                if (at < 0) return
                noteText.mentionAt = -1; notePicker.close()
                const words = String(p.name || "").split(/\s+/).filter(w => w)
                const style = 'style="color:' + theme.brandForeground1 + '; text-decoration:none"'
                const html = words.map(w => '<a href="mention:' + p.mri + '" ' + style + '>' + w.replace(/&/g, "&amp;").replace(/</g, "&lt;") + '</a>').join("&nbsp;") + "&nbsp;"
                noteText.remove(at, end)
                noteText.insert(at, html)
                noteText.cursorPosition = at + words.join(" ").length + 1
                noteText.forceActiveFocus()
            }
            // Teams' mention suggestions (as the compose picker: 300 wide,
            // "Suggestions", 47.3 px person rows), left of the editor.
            Popup {
                id: notePicker
                property int current: 0
                readonly property var people: {
                    const q = noteText.mentionQuery.trim().toLowerCase()
                    if (q.length < 2) return []
                    return (backend.peopleJson ? JSON.parse(backend.peopleJson) : []).slice(0, 8).map(p => ({ mri: Mri.work(p.id), name: p.name, mail: p.mail || p.email || "" }))
                }
                // Teams: 128 left of the editor, its bottom on the caret line.
                x: 16 - 128; y: Math.max(-40, 71 + noteText.cursorRectangle.y + 8 - height + 6)
                width: 300; padding: 0
                height: 43.2 + Math.max(1, people.length) * 47.3 + 8
                closePolicy: Popup.CloseOnPressOutside
                focus: false
                onPeopleChanged: current = 0
                background: FluentSurface { depth: 16; radius: 4; color: theme.surface }
                Text { x: 20; y: 10.7; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Suggestions"); font.family: theme.font; font.pixelSize: 14; color: theme.textStrong }
                Column {
                    y: 43.2
                    Repeater {
                        model: notePicker.people
                        Rectangle {
                            id: np
                            required property var modelData
                            required property int index
                            width: 298.7; height: 47.3; radius: 2.5
                            color: index === notePicker.current ? theme.pick("#E6E6E6", "#3D3D3D", "#1AEBFF") : npHover.hovered ? theme.menuHover : "transparent"
                            Avatar { x: 19.6; y: 7.6; size: 32; name: np.modelData.name; photoId: np.modelData.mri }
                            Text { x: 59.7; y: 5.7; height: 20; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; text: np.modelData.name; font.family: theme.font; font.pixelSize: 14; color: theme.onFill(np, theme.text) }
                            Text { x: 59.7; y: 25.7; height: 16; verticalAlignment: Text.AlignVCenter; width: 220; elide: Text.ElideRight; text: np.modelData.mail; font.family: theme.font; font.pixelSize: 12; color: theme.onFill(np, theme.text) }
                            HoverHandler { id: npHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: notePage.pickMention(np.modelData) }
                            Accessible.role: Accessible.ListItem; Accessible.name: np.modelData.name
                        }
                    }
                }
            }
            Rectangle {
                id: hcFill6
                x: 16; y: 16; width: 21; height: 21; radius: 4
                color: backHover.hovered ? theme.menuHover : "transparent"
                FluentIcon { x: 1; y: 1; name: "chevron-left-20"; size: 20; color: theme.onFill(hcFill6, theme.textStrong) }
                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: menu.page = "main" }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Back")
            }
            Text { x: 53; y: 17; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Set status message"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
            Text { x: 53; y: 37; height: 16; verticalAlignment: Text.AlignVCenter; text: root.userMail; font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
            Rectangle {
                x: 16; y: 71; width: 288; height: 240; radius: 3
                color: theme.editorFilled; border.color: theme.transparentStroke
                clip: true
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: theme.brand; visible: noteText.activeFocus }
                TextEdit {
                    id: noteText
                    x: 8; y: 8; width: parent.width - 16; height: parent.height - 16 - 20
                    wrapMode: TextEdit.Wrap
                    // Rich text: @mentions are tokens, as in Teams' editor.
                    textFormat: TextEdit.RichText
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    // "@" and what follows it, before the cursor.
                    property int mentionAt: -1
                    property string mentionQuery: ""
                    onTextChanged: {
                        if (length > 280) { const p = cursorPosition; remove(280, length); cursorPosition = Math.min(p, 280) }
                        const before = getText(0, cursorPosition)
                        const at = before.lastIndexOf("@")
                        const q = at >= 0 ? before.slice(at + 1) : ""
                        if (at >= 0 && (at === 0 || /\s/.test(before[at - 1])) && q.length <= 40 && !/\n/.test(q)) {
                            mentionAt = at; mentionQuery = q
                            if (q.trim().length >= 2) backend.searchPeopleWithMe(q.trim())
                            if (!notePicker.opened) notePicker.open()
                        } else if (notePicker.opened) { mentionAt = -1; notePicker.close() }
                    }
                    Keys.onPressed: e => {
                        if (!notePicker.opened) return
                        if (e.key === Qt.Key_Down) { notePicker.current = Math.min(notePicker.current + 1, notePicker.people.length - 1); e.accepted = true }
                        else if (e.key === Qt.Key_Up) { notePicker.current = Math.max(notePicker.current - 1, 0); e.accepted = true }
                        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) && notePicker.people.length) { notePage.pickMention(notePicker.people[notePicker.current]); e.accepted = true }
                        else if (e.key === Qt.Key_Escape) { notePicker.close(); e.accepted = true }
                    }
                    Text { visible: noteText.length === 0; text: qsTr("Type @ to mention someone in your status"); font: parent.font; color: theme.textSecondary }
                    Accessible.name: qsTr("Type @ to mention someone in your status")
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 8; y: 211; height: 20
                    verticalAlignment: Text.AlignVCenter
                    text: noteText.length + " / 280"
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
            }
            Item {
                x: 16; y: 341; width: 238; height: 39
                Rectangle {
                    id: pinBox
                    property bool checked: false
                    x: 2; y: 10; width: 16; height: 16; radius: 2
                    color: checked ? theme.checkedFill : "transparent"; border.color: checked ? theme.checkedFill : theme.textSecondary; border.width: 1
                    FluentIcon { anchors.centerIn: parent; visible: pinBox.checked; name: "checkmark-12-filled"; size: 12; color: theme.onFill(pinBox, "white") }
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: checked
                    Accessible.name: qsTr("Show when people message me")
                }
                Text { x: 30; y: 8; text: qsTr("Show when people message me"); font.family: theme.font; font.pixelSize: theme.base; color: theme.text }
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
                    contentItem: Text { text: qsTr("Your status message will show above the compose message box when someone sends you a message or @mentions you."); wrapMode: Text.Wrap; font.family: theme.font; font.pixelSize: theme.small; color: theme.text }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Your status message will show above the compose message box when someone sends you a message or @mentions you.")
            }
            Text { x: 16; y: 390; height: 20; verticalAlignment: Text.AlignVCenter; text: qsTr("Clear status message after"); font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.textStrong }
            Dropdown { id: clearPick; x: 16; y: 424; width: 288; options: notePage.clearAfter }
            // Teams' "Schedule out of office" link (16, 478) opens
            // Settings ▸ General ▸ Out of office.
            Text {
                x: 18; y: 480; height: 20; verticalAlignment: Text.AlignVCenter
                text: qsTr("Schedule out of office"); font.family: theme.font; font.pixelSize: theme.base; color: theme.brand
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { menu.visible = false; root.openOutOfOffice() } }
                Accessible.role: Accessible.Link
                Accessible.name: qsTr("Schedule out of office")
            }
            PrimaryButton {
                x: 191; y: 474
                label: notePage.saving ? qsTr("Saving...") : qsTr("Done")
                enabled: !notePage.saving && (noteText.getText(0, noteText.length).trim().length > 0 || root.statusNote.length > 0)
                onClicked: { notePage.saving = true; root.setStatusNote(noteText.getText(0, noteText.length).trim().length ? noteText.text : "", pinBox.checked, notePage.clearAfter[clearPick.current].key) }
            }
        }
    }
    signal setStatusUntil(string status, string duration)
    signal setStatusNote(string message, bool pinned, string clearAfter)
    signal openOutOfOffice()
    // A status message save finished: close on success, as Teams does.
    function statusNoteSaved(ok, message, pinned, html) {
        notePage.saving = false
        if (ok) { root.statusNote = message; root.statusNoteHtml = html || ""; root.statusNotePinned = pinned; menu.visible = false }
    }
}
