import QtQuick
import QtQuick.Controls.Basic

// Activity (Ctrl+1), laid out as Teams desktop's (measured at 1x): a
// 379 px list of what happened to you; the chosen item's chat opens
// beside it (Main places the conversation there).
Rectangle {
    id: root
    /// ActivityItem list, newest first.
    property var items: []
    property string selectedId: ""
    /// The open item's kind (a missed call or voicemail shows Calls beside
    /// the feed instead of a chat).
    property string selectedKind: ""
    // Chips and the filter box.
    property string chip: ""
    property string nameFilter: ""
    property bool filtering: false
    signal markAllRead()
    /// The ··· menu's Notification settings (Settings ▸ Notifications and
    /// activity).
    signal notificationSettings()
    /// What a row shows, as Teams' filter matches it: every line of the
    /// item (headline, preview, where), case-insensitively.
    function rowText(it) {
        return [it.title, (it.preview || "").replace(/\s+/g, " ").trim(), theme.activityPlace(it.context), it.channel || ""].join("\n").toLowerCase()
    }
    readonly property var shown: items.filter(it =>
        (chip !== "unread" || it.unread)
        && (chip !== "mentions" || it.kind === "mention")
        && (chip !== "tags" || it.kind === "tagMention")
        && (!nameFilter || rowText(it).indexOf(nameFilter) >= 0))
    /// Teams' filter marks (feeditem_search_highlight): each match on a
    /// colorPaletteMarigoldBorder1 fill in NeutralForeground1 at regular
    /// weight, as rich text; plain text (with its elision) otherwise.
    readonly property color markFill: theme.pick("#F9E2AE", "#EAA300", "#000000")
    function escaped(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function marked(t) {
        if (!nameFilter) return t
        const low = t.toLowerCase()
        let out = "", from = 0, i = low.indexOf(nameFilter)
        while (i >= 0) {
            out += escaped(t.substring(from, i))
                + "<span style=\"background-color:" + markFill + ";color:" + theme.text + ";font-weight:400\">"
                + escaped(t.substring(i, i + nameFilter.length)) + "</span>"
            from = i + nameFilter.length
            i = low.indexOf(nameFilter, from)
        }
        return out + escaped(t.substring(from))
    }
    function hasMark(t) { return !!nameFilter && (t || "").toLowerCase().indexOf(nameFilter) >= 0 }
    signal openItem(var item)
    signal callBack(var item)
    signal chatWith(var item)
    color: theme.pane
    width: 379
    // Up / Down / Home / End through the feed, as Teams' (ListKeys).
    property alias enterToOpen: keys.enterToOpen
    ListKeys {
        id: keys
        owner: root
        view: list
        items: root.shown
        onOpen: item => root.openItem(item)
    }
    Keys.onPressed: e => keys.handle(e, root.selectedId)
    function keysForTest() { return keys }
    // Teams puts the keyboard in the feed as Activity opens.
    onVisibleChanged: if (visible) forceActiveFocus()

    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.edge }

    Text {
        x: 20; y: 17
        text: qsTr("Activity")
        font.family: theme.font; font.pixelSize: 18; font.weight: Font.Bold
        color: theme.text
    }
    // ··· (More options) and Filter, Teams' feed header buttons.
    Row {
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 14
        spacing: 0
        Rectangle {
            id: moreButton
            width: 32; height: 32; radius: theme.radius
            color: moreHover.hovered || actMenu.opened ? theme.hover : "transparent"
            HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: actMenu.opened ? actMenu.close() : actMenu.open() }
            FluentIcon { anchors.centerIn: parent; name: "more-20"; size: 20; color: theme.onFill(moreButton, theme.textStrong) }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More options")
            // Teams' activity menu (generalMenuConfig): Mark all as read
            // with its shortcut, Notification settings; below the button,
            // its end level with the button's.
            MenuPopup {
                id: actMenu
                x: parent.width - width; y: parent.height + 1
                items: [{ label: qsTr("Mark all as read"), icon: "glasses-20", keys: "Shift+Esc" },
                        { label: qsTr("Notification settings"), icon: "settings-20" }]
                onPicked: i => { if (i === 0) root.markAllRead(); else root.notificationSettings() }
            }
        }
        Rectangle {
            id: filterButton
            width: 32; height: 32; radius: theme.radius
            color: filterHover.hovered ? theme.hover : "transparent"
            HoverHandler { id: filterHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.toggleFilter() }
            // On while the box is open: Teams' filled icon in brand.
            FluentIcon {
                anchors.centerIn: parent; size: 20
                name: root.filtering ? "search-20-filled" : "search-20"
                color: theme.onFill(filterButton, root.filtering ? theme.brand : theme.textStrong)
            }
            ToolTip.visible: filterHover.hovered
            ToolTip.delay: 600
            // (Teams' open/close_feeds_filter_button_tooltip_with_shortcut)
            ToolTip.text: root.filtering ? qsTr("Close filter text box") + " (Ctrl+Shift+F)" : qsTr("Show filter text box") + " (Ctrl+Shift+F)"
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Filter")
        }
    }
    function toggleFilter() {
        filtering = !filtering
        if (!filtering) actFilter.text = ""
        else actFilter.forceActiveFocus()
    }
    function menuForTest() { return actMenu }
    function filterFieldForTest() { return actFilter }
    // The pills; under the filter box while it's open (Teams keeps them).
    readonly property real filterBoxH: filtering ? 47 : 0
    Row {
        x: 16; y: 78 + root.filterBoxH
        spacing: 8
        Repeater {
            model: [{ l: qsTr("Unread"), k: "unread" }, { l: qsTr("@Mentions"), k: "mentions" }, { l: qsTr("Tag mentions"), k: "tags" }]
            delegate: Rectangle {
                id: chipRect
                required property var modelData
                readonly property bool on: root.chip === modelData.k
                height: 24; radius: 12
                width: chip.implicitWidth + 16
                color: on ? theme.hc(theme.brandTint, theme.hcHighlight) : (ach.hovered ? theme.rowHover : "transparent")
                border.color: on ? theme.brand : theme.stroke
                HoverHandler { id: ach; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.chip = chipRect.on ? "" : chipRect.modelData.k }
                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: chipRect.modelData.l
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.onFill(chipRect, chipRect.on ? theme.brand : theme.textStrong)
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData.l
                Accessible.checked: on
            }
        }
    }
    // Teams' activity filter box (measured on Teams web 2026-11-27 as
    // ost-test1): over the pills, 16 in and 72 down, 32 tall, white with
    // Fluent's shadow 2 and radius 4, no icon; "Filter by name or group
    // name" 13 in (14/20, NeutralForeground4); a 2 px brand line along its
    // bottom while it has the focus; with text, Clear filter text (24 px, a
    // 20 px dismiss, 6 from its end).
    Item {
        id: filterBox
        visible: root.filtering
        x: 16; y: 72; width: parent.width - 32; height: 32
        FluentSurface { anchors.fill: parent; depth: 2; radius: 4; color: theme.input }
        Rectangle {
            visible: actFilter.activeFocus
            anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1
            color: theme.brand
        }
        TextInput {
            id: actFilter
            x: 13; width: parent.width - x - (clearFilter.visible ? 36 : 12)
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            selectionColor: theme.brand; selectedTextColor: "white"
            clip: true
            onTextChanged: root.nameFilter = text.trim().toLowerCase()
            Keys.onEscapePressed: { text = ""; root.filtering = false; root.forceActiveFocus() }
            Text { visible: !actFilter.text; width: actFilter.width; elide: Text.ElideRight; text: qsTr("Filter by name or group name"); color: theme.textTertiary; font: actFilter.font }
            Accessible.role: Accessible.EditableText
            Accessible.name: qsTr("Filter by name or group name")
        }
        Rectangle {
            id: clearFilter
            visible: actFilter.text.length > 0
            x: parent.width - 6 - width; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 4
            color: clh.hovered ? theme.hover : "transparent"
            FluentIcon { anchors.centerIn: parent; name: clh.hovered ? "dismiss-20-filled" : "dismiss-20"; size: 20; color: theme.onFill(clearFilter, theme.textStrong) }
            HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { actFilter.text = ""; actFilter.forceActiveFocus() } }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Clear filter text")
        }
    }

    // Relative time as Teams shows it in the feed: time today, M/d before.
    function when(t) {
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString()) return theme.time(d)
        return theme.dateNoYear(d)
    }

    ListView {
        id: list
        y: 111 + root.filterBoxH
        width: parent.width - 1; height: parent.height - y
        clip: true
        spacing: 0
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: it
            required property var modelData
            readonly property bool selected: modelData.id === root.selectedId
            readonly property bool call: modelData.kind === "missedCall"
            width: list.width
            height: Math.max(64, body.y + body.height + (call ? 34 : 0) + 10)
            Rectangle {
                x: 4; width: 358; height: parent.height; radius: theme.radius
                color: it.selected ? theme.selected : (hov.hovered ? theme.rowHover : "transparent")
            }
            // The keyboard's focus ring (Teams: 2 px NeutralForeground1).
            Rectangle {
                visible: keys.ringOn(it.modelData)
                z: 2
                x: 4; width: 358; height: parent.height; radius: theme.radius
                color: "transparent"; border.width: 2; border.color: theme.text
            }
            // Unread: a small dot left of the picture.
            Rectangle {
                visible: it.modelData.unread
                x: 10; y: 24; width: 5; height: 5; radius: 2.5
                color: theme.text
            }
            // People show their picture; apps (team owners, bots) an app tile.
            readonly property bool fromPerson: (modelData.actor_mri || "").startsWith("8:orgid:")
            Avatar {
                visible: it.fromPerson
                x: 20.7; y: 10.7
                size: 32; name: it.modelData.actor_name || "?"
                photoId: it.fromPerson ? it.modelData.actor_mri : ""
            }
            // An app's activity: the app's icon (Teams' customIconUrl).
            AppIcon {
                visible: !it.fromPerson && !!it.modelData.icon
                x: 20.7; y: 10.7; width: 32; height: 32
                source: it.modelData.icon || ""
            }
            Rectangle {
                id: hcFill2
                visible: !it.fromPerson && !it.modelData.icon
                x: 20.7; y: 10.7; width: 32; height: 32; radius: theme.radius
                color: theme.brand
                FluentIcon { anchors.centerIn: parent; name: "apps-20-filled"; size: 20; color: theme.onFill(hcFill2, "white") }
            }
            // What happened, as a badge on the picture: the reaction itself,
            // or a coloured icon.
            Rectangle {
                // An app's activity by a person: the app's icon here (Teams'
                // customIconUrl); by the app itself: none.
                // A reaction: Teams' emoticon itself (the client's id, so the
                // service's like is the thumbs-up "yes"), 20 px in a 24 px
                // circle of the pane's colour, 18 right and 14 down from the
                // picture (measured on winpc 2026-11-23).
                readonly property bool reaction: !!it.modelData.reaction
                visible: it.modelData.kind !== "app" || (it.fromPerson && !!it.modelData.icon)
                x: reaction ? 20.7 + 18 : 20.7 + 32 - 14; y: reaction ? 10.7 + 14 : 10.7 + 32 - 14
                width: reaction ? 24 : 18; height: width; radius: width / 2
                color: reaction ? theme.pane : theme.surface
                Emoticon {
                    visible: parent.reaction
                    anchors.centerIn: parent; size: 20; named: "large"
                    key: parent.reaction ? it.modelData.reaction : ""
                }
                AppIcon {
                    visible: it.modelData.kind === "app"
                    anchors.centerIn: parent; width: 14; height: 14
                    source: visible ? it.modelData.icon : ""
                }
                Text {
                    visible: it.modelData.emoji.length > 0 && !parent.reaction
                    anchors.centerIn: parent
                    text: it.modelData.emoji
                    font.pixelSize: 12
                }
                FluentIcon {
                    visible: it.modelData.emoji.length === 0 && it.modelData.kind !== "app"
                    anchors.centerIn: parent; size: 14
                    name: it.modelData.kind === "missedCall" ? "call-missed-16-filled"
                        : it.modelData.kind === "voicemail" ? "voicemail-16-filled"
                        : it.modelData.kind === "addedToTeam" ? "people-team-16-filled"
                        : it.modelData.kind === "reminder" ? "clock-alarm-16"
                        : "chat-20"
                    color: it.modelData.kind === "missedCall" ? theme.hc("#D13438", "#FFFFFF")
                        : it.modelData.kind === "voicemail" ? theme.hc("#CA5010", "#FFFFFF") : theme.brand
                }
            }
            Column {
                id: body
                x: 72.7; y: 6.7
                width: 273
                Text {
                    width: 201
                    readonly property bool marks: root.hasMark(it.modelData.title)
                    textFormat: marks ? Text.RichText : Text.PlainText
                    text: marks ? root.marked(it.modelData.title) : it.modelData.title
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: theme.base
                    font.weight: it.modelData.unread ? Font.Bold : Font.Normal
                    color: theme.text
                }
                Text {
                    visible: text.length > 0
                    width: parent.width
                    // (one line, as Teams: a multi-line message runs on)
                    readonly property string plain: (it.modelData.preview || "").replace(/\s+/g, " ").trim()
                    readonly property bool marks: root.hasMark(plain)
                    textFormat: marks ? Text.RichText : Text.PlainText
                    text: marks ? root.marked(plain) : plain
                    maximumLineCount: 1; clip: marks
                    elide: Text.ElideRight
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    font.family: theme.font; font.pixelSize: theme.base
                    color: theme.textSecondary
                }
                // Where: a chat, an app's own place (its dates worded), or
                // a channel as Teams' "Team > Channel".
                Row {
                    visible: placeText.text.length > 0
                    width: parent.width
                    spacing: 4
                    Text {
                        id: placeText
                        width: Math.min(implicitWidth, parent.width - (channelText.visible ? Math.min(channelText.implicitWidth, parent.width / 2) + 20 : 0))
                        readonly property string plain: theme.activityPlace(it.modelData.context)
                        readonly property bool marks: root.hasMark(plain)
                        textFormat: marks ? Text.RichText : Text.PlainText
                        text: marks ? root.marked(plain) : plain
                        clip: marks
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.textStrong
                    }
                    FluentIcon {
                        visible: channelText.visible
                        anchors.verticalCenter: parent.verticalCenter
                        size: 12; name: "chevron-right-12"; color: theme.textStrong
                    }
                    Text {
                        id: channelText
                        visible: !!it.modelData.channel
                        width: Math.max(0, Math.min(implicitWidth, parent.width - placeText.width - 20))
                        readonly property bool marks: root.hasMark(it.modelData.channel)
                        textFormat: marks ? Text.RichText : Text.PlainText
                        text: marks ? root.marked(it.modelData.channel || "") : (it.modelData.channel || "")
                        clip: marks
                        elide: Text.ElideRight
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.textStrong
                    }
                }
            }
            Text {
                x: 345.5 - implicitWidth; y: 6.7
                text: root.when(it.modelData.time)
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textStrong
            }
            // Missed calls: call back or chat, as in Teams.
            Row {
                visible: it.call
                x: 72.7; y: body.y + body.height + 8
                spacing: 8
                Repeater {
                    model: [qsTr("Call"), qsTr("Chat")]
                    Rectangle {
                        id: hcFill3
                        required property string modelData
                        width: 65; height: 24; radius: theme.radius
                        color: bh.hovered ? theme.hc(theme.pane, theme.hcHighlight) : theme.surface
                        border.color: theme.stroke
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                            color: theme.onFill(hcFill3, theme.text)
                        }
                        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: modelData === qsTr("Call") ? root.callBack(it.modelData) : root.chatWith(it.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                    }
                }
            }
            HoverHandler { id: hov }
            TapHandler { onTapped: { keys.clicked(it.modelData); root.openItem(it.modelData) } }
            Accessible.role: Accessible.ListItem
            Accessible.name: it.modelData.title
        }
        Text {
            visible: root.shown.length === 0
            x: 20; y: 8
            text: root.items.length === 0 ? qsTr("You will see @mentions, reactions and other notifications here.") : qsTr("We didn't find any matches.", "activity:k53gfg4hr")
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.textSecondary
        }
    }
}
