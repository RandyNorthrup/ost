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
    // Chips and the filter box.
    property string chip: ""
    property string nameFilter: ""
    property bool filtering: false
    signal markAllRead()
    readonly property var shown: items.filter(it =>
        (chip !== "unread" || it.unread)
        && (chip !== "mentions" || it.kind === "mention")
        && (chip !== "tags" || it.kind === "tagMention")
        && (!nameFilter || (it.title + " " + it.preview).toLowerCase().indexOf(nameFilter) >= 0))
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
    Row {
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 14
        spacing: 0
        Repeater {
            model: [{ icon: "more-20", label: qsTr("More options") }, { icon: "search-20", label: qsTr("Filter") }]
            Rectangle {
                id: hcFill1
                required property var modelData
                required property int index
                width: 32; height: 32; radius: theme.radius
                color: hh.hovered ? theme.hover : "transparent"
                HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (parent.index === 0) actMenu.open()
                        else { root.filtering = !root.filtering; if (!root.filtering) actFilter.text = ""; else actFilter.forceActiveFocus() }
                    }
                }
                FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: theme.onFill(hcFill1, theme.textStrong) }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                MenuPopup {
                    id: actMenu
                    x: -200; y: parent.height + 4
                    items: [{ label: qsTr("Mark all as read"), icon: "checkmark-12" }]
                    onPicked: root.markAllRead()
                }
            }
        }
    }
    Row {
        visible: !root.filtering
        x: 16; y: 78
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
    Rectangle {
        visible: root.filtering
        x: 16; y: 74; width: parent.width - 32; height: 32; radius: theme.radius
        color: theme.input
        border.color: actFilter.activeFocus ? theme.brand : theme.stroke
        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
        TextInput {
            id: actFilter
            x: 32; width: parent.width - 40
            anchors.verticalCenter: parent.verticalCenter
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            clip: true
            onTextChanged: root.nameFilter = text.trim().toLowerCase()
            Keys.onEscapePressed: { text = ""; root.filtering = false }
            Text { visible: !actFilter.text; text: qsTr("Filter"); color: theme.textTertiary; font: actFilter.font }
            Accessible.name: qsTr("Type to filter")
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
        y: 111
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
                    text: it.modelData.title
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
                    text: (it.modelData.preview || "").replace(/\s+/g, " ").trim()
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
                        text: theme.activityPlace(it.modelData.context)
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
                        text: it.modelData.channel || ""
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
